-- ModRecipeScan.lua
-- Recipe Framework Survival — original ModDatabase scanner.
-- One pass at world load: craftbot, hideout trades, mining hub trades, optional loot.

ModRecipeScan = ModRecipeScan or {}

local MD_LOCAL = "40639a2c-bb9f-4d4f-b88c-41bfe264ffa8"
local MD_DESC = "$CONTENT_40639a2c-bb9f-4d4f-b88c-41bfe264ffa8/Scripts/data/descriptions.json"
local FARMERS_UUID = "8d601982-4608-4d5e-bb9e-e4041486f7c7"

local function fileExists( path )
	local ok, exists = pcall( function()
		return sm.json.fileExists( path )
	end )
	return ok and exists == true
end

local function itemPresentOnPeer( itemId )
	local id = tostring( itemId or "" )
	if id == "" then
		return false
	end
	local okUuid, uuid = pcall( sm.uuid.new, id )
	if not okUuid or not uuid then
		return false
	end
	local exists = false
	pcall( function()
		if sm.shape.uuidExists and sm.shape.uuidExists( uuid ) then
			exists = true
		end
	end )
	if not exists then
		pcall( function()
			if sm.tool and sm.tool.uuidExists and sm.tool.uuidExists( uuid ) then
				exists = true
			end
		end )
	end
	if not exists then
		return false
	end
	local title = nil
	pcall( function()
		title = sm.shape.getShapeTitle( uuid )
	end )
	if type( title ) == "string" then
		local lower = string.lower( title )
		if title == "" or string.find( lower, "not found", 1, true ) then
			return false
		end
	end
	return true
end

local function openJson( path )
	if not fileExists( path ) then
		local ok, data = pcall( sm.json.open, path )
		if ok and type( data ) == "table" then
			return data
		end
		return nil
	end
	local ok, data = pcall( sm.json.open, path )
	if ok and type( data ) == "table" then
		return data
	end
	return nil
end

local function contentPath( localId, rel )
	return "$CONTENT_" .. tostring( localId ) .. "/" .. rel
end

local function extractTradeList( cfg )
	if type( cfg ) ~= "table" then
		return nil
	end
	if type( cfg.trades ) == "table" then
		return cfg.trades
	end
	if cfg[1] and type( cfg[1] ) == "table" and cfg[1].itemId then
		return cfg
	end
	return nil
end

local function normalizeTrade( raw, sourceLid )
	if type( raw ) ~= "table" or not raw.itemId then
		return nil
	end
	local entry = {
		itemId = tostring( raw.itemId ),
		quantity = raw.quantity or 1,
		craftTime = raw.craftTime or 0,
		ingredientList = {},
		schematic = raw.schematic,
		cosmetic = raw.cosmetic,
		extras = raw.extras,
		_rfs = true,
		_rfsMod = tostring( sourceLid ),
	}
	if entry.schematic == nil and not entry.cosmetic then
		entry.schematic = true
	end
	for _, ing in ipairs( raw.ingredientList or {} ) do
		if ing and ing.itemId then
			entry.ingredientList[#entry.ingredientList + 1] = {
				itemId = tostring( ing.itemId ),
				quantity = tonumber( ing.quantity ) or 1,
			}
		end
	end
	-- Hideout currency is always Farmers for RFS (fold whatever the author listed).
	local qty = 0
	for _, ing in ipairs( entry.ingredientList ) do
		qty = qty + ( tonumber( ing.quantity ) or 1 )
	end
	if qty < 1 then qty = 1 end
	entry.ingredientList = { { itemId = FARMERS_UUID, quantity = qty } }
	return entry
end

local function dedupeAppend( dest, seen, entry )
	local id = entry.itemId
	if seen[id] then
		return false
	end
	dest[#dest + 1] = entry
	seen[id] = true
	return true
end

local function applyLootForMod( recipes, lootCfg )
	if not LOOT_TABLES then
		return 0
	end
	local tableName = "loottable_interactive_01"
	local defaultWeight = 0.03
	local itemCfg = {}
	if type( lootCfg ) == "table" then
		if type( lootCfg.addToLootTable ) == "string" and lootCfg.addToLootTable ~= "" then
			tableName = lootCfg.addToLootTable
		end
		if type( lootCfg.defaultLootWeight ) == "number" then
			defaultWeight = lootCfg.defaultLootWeight
		end
		if type( lootCfg.items ) == "table" then
			itemCfg = lootCfg.items
		end
	end
	local lootTable = LOOT_TABLES[tableName]
	if not lootTable or type( lootTable.list ) ~= "table" then
		return 0
	end
	local desired = {}
	if next( itemCfg ) ~= nil then
		for itemId, meta in pairs( itemCfg ) do
			if type( meta ) == "table" then
				local add = meta.addToLoot
				if add == nil then add = true end
				if add then
					desired[tostring( itemId )] = tonumber( meta.lootWeight ) or defaultWeight
				end
			elseif type( meta ) == "number" then
				desired[tostring( itemId )] = meta
			end
		end
	elseif type( recipes ) == "table" then
		for _, recipe in ipairs( recipes ) do
			if recipe and recipe.itemId then
				desired[tostring( recipe.itemId )] = defaultWeight
			end
		end
	end
	if next( desired ) == nil then
		return 0
	end
	local filtered = {}
	for _, entry in ipairs( lootTable.list ) do
		local key = entry.uuid ~= nil and tostring( entry.uuid ) or nil
		if not ( key and desired[key] ~= nil ) then
			filtered[#filtered + 1] = entry
		end
	end
	lootTable.list = filtered
	local added = 0
	for itemId, weight in pairs( desired ) do
		local ok, uuid = pcall( sm.uuid.new, itemId )
		if ok and uuid then
			lootTable.list[#lootTable.list + 1] = { uuid = uuid, weight = weight, quantity = 1 }
			added = added + 1
		end
	end
	return added
end

function ModRecipeScan.run()
	local result = {
		modsScanned = 0,
		sources = {},
		craftPaths = {},
		craftRecipeCount = 0,
		hideoutTrades = {},
		miningTrades = {},
		hideoutAdded = 0,
		miningAdded = 0,
		lootApplied = 0,
		skippedDupes = 0,
	}

	local md = openJson( MD_DESC )
	if type( md ) ~= "table" then
		print( "[RFS] ModDatabase descriptions.json not found — subscribe ModDatabase (do not enable as world mod)." )
		ModRecipeScan._last = result
		return result
	end

	local hideSeen = {}
	local mineSeen = {}
	-- Preserve any trades already published (e.g. another helper), then fill gaps.
	_G.g_extraHideoutTrades = _G.g_extraHideoutTrades or {}
	_G.g_extraMiningHubTrades = _G.g_extraMiningHubTrades or {}
	_G.g_extraHideoutSchematicUnlocks = _G.g_extraHideoutSchematicUnlocks or {}

	for _, t in ipairs( _G.g_extraHideoutTrades ) do
		if t and t.itemId then
			hideSeen[tostring( t.itemId )] = true
		end
	end
	for _, t in ipairs( _G.g_extraMiningHubTrades ) do
		if t and t.itemId then
			mineSeen[tostring( t.itemId )] = true
		end
	end

	g_unlockableCraftItems = g_unlockableCraftItems or {}

	for lid, meta in pairs( md ) do
		lid = tostring( lid )
		if lid ~= MD_LOCAL then
			result.modsScanned = result.modsScanned + 1
			local name = ( type( meta ) == "table" and ( meta.name or meta.title ) ) or lid
			local source = { localId = lid, name = tostring( name ), craft = 0, hideout = 0, mining = 0, loot = 0 }

			local craftPath = contentPath( lid, "CraftingRecipes/craftbot.json" )
			local recipes = openJson( craftPath )
			if type( recipes ) == "table" then
				-- Index-style craftbot.json (name -> path) is rare for B&P mods; support both.
				local list = recipes
				if recipes.craftbot_beams or recipes.craftbot_core then
					list = {}
					for _, subPath in pairs( recipes ) do
						if type( subPath ) == "string" then
							local sub = openJson( subPath )
							if type( sub ) == "table" then
								for _, r in ipairs( sub ) do
									list[#list + 1] = r
								end
							end
						end
					end
				end
				local n = 0
				for _, recipe in ipairs( list ) do
					if type( recipe ) == "table" and recipe.itemId then
						local id = tostring( recipe.itemId )
						-- Mark unlockable; do NOT auto-unlock (blue schematic progression).
						g_unlockableCraftItems[id] = true
						n = n + 1
					end
				end
				if n > 0 then
					source.craft = n
					result.craftRecipeCount = result.craftRecipeCount + n
					result.craftPaths[#result.craftPaths + 1] = craftPath
				end
			end

			local hideCfg = openJson( contentPath( lid, "CraftingRecipes/hideout_trades.json" ) )
			-- Prefer hideout_trades.json only. Full hideout.json dumps from other games/mods
			-- can inject unknown UUIDs that show as "BLOCK NOT FOUND" in the shop.
			if hideCfg == nil then
				-- Allow hideout.json only when it declares currencyItemId / trades wrapper (RFS author format)
				local rawHide = openJson( contentPath( lid, "CraftingRecipes/hideout.json" ) )
				if type( rawHide ) == "table" and ( rawHide.trades or rawHide.currencyItemId ) then
					hideCfg = rawHide
				end
			end
			local hideList = extractTradeList( hideCfg )
			if type( hideList ) == "table" then
				for _, raw in ipairs( hideList ) do
					local entry = normalizeTrade( raw, lid )
					if entry then
						if not itemPresentOnPeer( entry.itemId ) then
							-- Missing mod/shape on this peer — do not publish a ghost shop row.
						elseif hideSeen[entry.itemId] then
							result.skippedDupes = result.skippedDupes + 1
						elseif dedupeAppend( result.hideoutTrades, hideSeen, entry ) then
							source.hideout = source.hideout + 1
							result.hideoutAdded = result.hideoutAdded + 1
							if entry.schematic ~= false then
								_G.g_extraHideoutSchematicUnlocks[entry.itemId] = true
							end
						end
					end
				end
			end

			local mineCfg = openJson( contentPath( lid, "CraftingRecipes/mininghub_trades.json" ) )
			local mineList = extractTradeList( mineCfg )
			if type( mineList ) == "table" then
				for _, raw in ipairs( mineList ) do
					local entry = normalizeTrade( raw, lid )
					if entry then
						if not itemPresentOnPeer( entry.itemId ) then
							-- Missing mod/shape on this peer — do not publish a ghost shop row.
						elseif mineSeen[entry.itemId] then
							result.skippedDupes = result.skippedDupes + 1
						elseif dedupeAppend( result.miningTrades, mineSeen, entry ) then
							source.mining = source.mining + 1
							result.miningAdded = result.miningAdded + 1
						end
					end
				end
			end

			local lootCfg = openJson( contentPath( lid, "CraftingRecipes/loot.json" ) )
			if type( lootCfg ) == "table" then
				local added = applyLootForMod( recipes, lootCfg )
				source.loot = added
				result.lootApplied = result.lootApplied + added
			end

			if source.craft > 0 or source.hideout > 0 or source.mining > 0 or source.loot > 0 then
				result.sources[#result.sources + 1] = source
				print( string.format(
					"[RFS] mod=%s craft=%d hideout=%d mining=%d loot=%d",
					source.name, source.craft, source.hideout, source.mining, source.loot
				) )
			end
		end
	end

	-- Publish merged trade globals (append new; keep prior non-dupes)
	for _, t in ipairs( result.hideoutTrades ) do
		_G.g_extraHideoutTrades[#_G.g_extraHideoutTrades + 1] = t
	end
	for _, t in ipairs( result.miningTrades ) do
		_G.g_extraMiningHubTrades[#_G.g_extraMiningHubTrades + 1] = t
	end
	_G.g_hideoutExtraTradesDirty = true
	_G.g_hideoutExtraTradesMerged = false
	_G.g_miningHubExtraTradesDirty = true
	_G.g_miningHubExtraTradesMerged = false

	print( string.format(
		"[RFS] scan done mods=%d sources=%d craftRecipes=%d hideout+=%d mining+=%d loot=%d dupesSkipped=%d",
		result.modsScanned, #result.sources, result.craftRecipeCount,
		result.hideoutAdded, result.miningAdded, result.lootApplied, result.skippedDupes
	) )

	ModRecipeScan._last = result
	return result
end

function ModRecipeScan.getLast()
	return ModRecipeScan._last
end
