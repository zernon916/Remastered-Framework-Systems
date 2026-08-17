-- ModRecipeScan.lua
-- Recipe Framework Survival — ModDatabase-backed recipe scanner.
-- Only probes CraftingRecipes under CONTENT packs that are actually loaded.
-- Never calls sm.json.open / fileExists on unmounted $CONTENT_<uuid> roots
-- (those log DirectoryManager "Unable to replace key" + Lua tracebacks).

ModRecipeScan = ModRecipeScan or {}

local MD_LOCAL = "40639a2c-bb9f-4d4f-b88c-41bfe264ffa8"
local MD_DESC = "$CONTENT_40639a2c-bb9f-4d4f-b88c-41bfe264ffa8/Scripts/data/descriptions.json"
local MD_SHAPES = "$CONTENT_40639a2c-bb9f-4d4f-b88c-41bfe264ffa8/Scripts/data/shapesets.json"
local MD_TOOLS = "$CONTENT_40639a2c-bb9f-4d4f-b88c-41bfe264ffa8/Scripts/data/toolsets.json"
local FARMERS_UUID = "8d601982-4608-4d5e-bb9e-e4041486f7c7"
-- This Custom Game. Not in ModDatabase shapesets/toolsets (those catalog B&P mods).
local RFS_LOCAL = "29c99287-1213-48c7-9471-19a4a5c12247"
-- Nutt World Map in ModDatabase toolsets.json owns GPS uuid d96c2fe4-… .
-- RFS vendors that tool. Do not scan World Map (wrong recipe + double HUD).
local NUTT_MAP_LOCAL = "58df2b8e-a86f-44ed-b4f9-aa5b00b44162"

-- Session caches: never re-probe known-missing paths / unmounted content roots.
local missingPath = {}
local contentMounted = {}

local function openKnownJson( path )
	-- Path must already be under a known-mounted root (ModDatabase itself, or verified lid).
	local ok, data = pcall( sm.json.open, path )
	if ok and type( data ) == "table" then
		return data
	end
	return nil
end

local function fileExistsSafe( path )
	if missingPath[path] then
		return false
	end
	if not sm.json.fileExists then
		return nil
	end
	local ok, exists = pcall( sm.json.fileExists, path )
	if not ok then
		missingPath[path] = true
		return false
	end
	if exists ~= true then
		missingPath[path] = true
		return false
	end
	return true
end

-- Only call after content root is known mounted. Never open when missing.
local function openJson( path )
	if missingPath[path] then
		return nil
	end
	local ex = fileExistsSafe( path )
	if ex == false then
		return nil
	end
	-- ex == true, or fileExists unavailable (nil): try open once.
	local ok, data = pcall( sm.json.open, path )
	if ok and type( data ) == "table" then
		return data
	end
	missingPath[path] = true
	return nil
end

local function contentPath( localId, rel )
	return "$CONTENT_" .. tostring( localId ) .. "/" .. rel
end

-- True if this localId's CONTENT root is mounted. Uses one description.json probe
-- only after shape/tool UUID evidence suggests the mod is loaded.
local function isContentMounted( lid )
	lid = tostring( lid )
	local cached = contentMounted[lid]
	if cached ~= nil then
		return cached
	end
	local descPath = contentPath( lid, "description.json" )
	local ex = fileExistsSafe( descPath )
	if ex == true then
		contentMounted[lid] = true
		return true
	end
	if ex == false then
		contentMounted[lid] = false
		return false
	end
	-- No fileExists API: one open attempt, then cache.
	local data = openKnownJson( descPath )
	contentMounted[lid] = ( type( data ) == "table" )
	if not contentMounted[lid] then
		missingPath[descPath] = true
	end
	return contentMounted[lid]
end

-- Silent loaded check: shape UUID presence only (no fileExists / open).
-- Early-out false on first missing UUID — same idea as ModDatabase.isModLoaded
-- but without the shapeset fileExists that spams DirectoryManager on collisions.
local function shapesSuggestLoaded( shapeUuids )
	if type( shapeUuids ) ~= "table" then
		return false
	end
	for _, shapeUuid in ipairs( shapeUuids ) do
		local okUuid, uuid = pcall( sm.uuid.new, tostring( shapeUuid ) )
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
			return false
		end
		return true
	end
	return false
end

local function toolsSuggestLoaded( toolUuids )
	if type( toolUuids ) ~= "table" then
		return false
	end
	for _, toolUuid in ipairs( toolUuids ) do
		local okUuid, uuid = pcall( sm.uuid.new, tostring( toolUuid ) )
		if not okUuid or not uuid then
			return false
		end
		local exists = false
		pcall( function()
			if sm.item and sm.item.isTool and sm.item.isTool( uuid ) then
				exists = true
			elseif sm.tool and sm.tool.uuidExists and sm.tool.uuidExists( uuid ) then
				exists = true
			end
		end )
		if not exists then
			return false
		end
		return true
	end
	return false
end

local function collectLoadedLocalIds( shapesets, toolsets )
	local candidates = {}
	if type( shapesets ) == "table" then
		for lid, sets in pairs( shapesets ) do
			lid = tostring( lid )
			if lid ~= MD_LOCAL and type( sets ) == "table" then
				for _, shapeUuids in pairs( sets ) do
					if shapesSuggestLoaded( shapeUuids ) then
						candidates[lid] = true
						break
					end
				end
			end
		end
	end
	if type( toolsets ) == "table" then
		for lid, sets in pairs( toolsets ) do
			lid = tostring( lid )
			if lid ~= MD_LOCAL and not candidates[lid] and type( sets ) == "table" then
				for _, toolUuids in pairs( sets ) do
					if toolsSuggestLoaded( toolUuids ) then
						candidates[lid] = true
						break
					end
				end
			end
		end
	end

	local loaded = {}
	for lid in pairs( candidates ) do
		if lid ~= NUTT_MAP_LOCAL and isContentMounted( lid ) then
			loaded[#loaded + 1] = lid
		end
	end
	return loaded
end

-- Fant RecipeLoader is_uuid_valid: shape OR tool (Tools tab items are tools).
local function recipeItemIsShapeOrTool( itemId )
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
			elseif sm.item and sm.item.isTool and sm.item.isTool( uuid ) then
				exists = true
			end
		end )
	end
	return exists
end

local function itemPresentOnPeer( itemId )
	if not recipeItemIsShapeOrTool( itemId ) then
		return false
	end
	local id = tostring( itemId or "" )
	local okUuid, uuid = pcall( sm.uuid.new, id )
	if not okUuid or not uuid then
		return false
	end
	-- Tools have no shape title; getShapeTitle often returns "not found" and
	-- used to drop GPS from Hideout. Fant RecipeLoader accepts tools as-is.
	local isTool = false
	pcall( function()
		if sm.item and sm.item.isTool and sm.item.isTool( uuid ) then
			isTool = true
		elseif sm.tool and sm.tool.uuidExists and sm.tool.uuidExists( uuid ) then
			isTool = true
		end
	end )
	if isTool then
		return true
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
		modsCatalog = 0,
		modsLoaded = 0,
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

	local md = openKnownJson( MD_DESC )
	if type( md ) ~= "table" then
		print( "[RFS] ModDatabase descriptions.json not found — subscribe ModDatabase (do not enable as world mod)." )
		ModRecipeScan._last = result
		return result
	end

	local catalogCount = 0
	for _ in pairs( md ) do
		catalogCount = catalogCount + 1
	end
	result.modsCatalog = catalogCount

	local shapesets = openKnownJson( MD_SHAPES )
	local toolsets = openKnownJson( MD_TOOLS )
	local loadedList = collectLoadedLocalIds( shapesets, toolsets )
	-- Custom Game is not a ModDatabase B&P lid. Feed this pack through the
	-- same per-lid scan as Intelligentia: $CONTENT_<localId>/CraftingRecipes/…
	do
		local hasRfs = false
		for _, lid in ipairs( loadedList ) do
			if lid == RFS_LOCAL then
				hasRfs = true
				break
			end
		end
		if not hasRfs then
			loadedList[#loadedList + 1] = RFS_LOCAL
		end
	end
	result.modsLoaded = #loadedList

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

	for _, lid in ipairs( loadedList ) do
		if lid == NUTT_MAP_LOCAL then
			-- skip World Map craftbot.json (GPS uuid cataloged there)
		else
		result.modsScanned = result.modsScanned + 1
		local meta = md[lid]
		local name = ( type( meta ) == "table" and ( meta.name or meta.title ) ) or lid
		if lid == RFS_LOCAL then
			name = "RFS"
		end
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
					-- Tools are valid (Fant is_uuid_valid); do not require a shape.
					-- This pack: GPS stays visible on Craftbot Tools without Hideout buy.
					if id ~= "d96c2fe4-177b-49bb-be40-e4b1bcdd8f76" then
						g_unlockableCraftItems[id] = true
					else
						g_unlockableCraftItems[id] = nil
					end
					n = n + 1
				end
			end
			if n > 0 then
				source.craft = n
				result.craftRecipeCount = result.craftRecipeCount + n
				result.craftPaths[#result.craftPaths + 1] = craftPath
				if lid == RFS_LOCAL then
					print( "[RFS] scan RFS craftbot.json path=" .. tostring( craftPath ) .. " n=" .. tostring( n ) )
				end
			end
		end

		local hideCfg = openJson( contentPath( lid, "CraftingRecipes/hideout_trades.json" ) )
		if hideCfg == nil and lid == RFS_LOCAL then
			hideCfg = openJson( "$CONTENT_DATA/CraftingRecipes/hideout_trades.json" )
		end
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

	-- One summary line only (per-mod prints removed — use /mods for details).
	print( string.format(
		"[RFS] scan done catalog=%d loaded=%d scanned=%d sources=%d craftRecipes=%d hideout+=%d mining+=%d loot=%d dupesSkipped=%d",
		result.modsCatalog, result.modsLoaded, result.modsScanned, #result.sources, result.craftRecipeCount,
		result.hideoutAdded, result.miningAdded, result.lootApplied, result.skippedDupes
	) )

	ModRecipeScan._last = result
	return result
end

function ModRecipeScan.getLast()
	return ModRecipeScan._last
end
