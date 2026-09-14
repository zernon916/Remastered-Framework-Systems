-- RfsCrafterGrid.lua
-- FROZEN: Craftbot C++ grid extras. Do not mix hijack/battery work into this file.
--
-- Pack W wrapped only Crafter.cl_updateRecipeGrid. Survival `class(Crafter)` copies
-- methods onto Craftbot, so vanilla Craftbot.cl_updateRecipeGrid kept running.
-- This module dofiles $SURVIVAL_DATA Crafter.lua then patches Craftbot too.
--
-- C++ addGridItemsFromFile does not resolve $CONTENT_DATA (same as IconMap).
-- Extra files use $CONTENT_<RFS lid>/CraftingRecipes/craftbot.json.

RfsCrafterGrid = RfsCrafterGrid or {}

local GPS_UUID = "d96c2fe4-177b-49bb-be40-e4b1bcdd8f76"
-- Hideout schematic rows exist (Farmers priced). Keep off Craftbot until unlock.
local SCHEMATIC_LOCKED = {
	[GPS_UUID] = true, -- GPS tool, 1 Farmer (was wrongly force-unlocked)
	["e8f4a2b1-3c7d-4e9f-8a2b-1d5e6f7a8b9c"] = true, -- Handheld Radio tool, 5 Farmers
	["b4e8c1a0-7d2f-4a91-9c3e-29f1a8d6b5e7"] = true, -- Hack Beacon station core, 10 Farmers
	["ca2d0a9f-1a5b-4c7d-8e09-fb3a4b5c6d7e"] = true, -- Radio Antenna, 15 Farmers
	["d9e3b1a0-2b6c-4d8e-9f1a-0c4d5e6f7a8b"] = true, -- Radio Battery Brick, 15 Farmers
	["bb1c098e-094a-4b6c-7d08-ea293a4b5c6d"] = true, -- Radio Lock, 8000 miner tokens
	["6f391c5b-82d4-4e17-9a60-c1d5e8f2a4b7"] = true, -- Chemical Regeneration Station, 10 Farmers
	["7a402d6c-93e5-4f28-ab71-d2e6f9a3b5c8"] = true, -- Solar Panel, 5 Farmers
	["8b513e7d-a4f6-4039-bc82-e3f70a4b6d9e"] = true, -- Rechargeable Battery, 1 Farmer
	["9c624f8e-b507-414a-cd93-f4081b5c7eaf"] = true, -- Rechargeable Battery Box, 2 Farmers
}
local RFS_LID = "29c99287-1213-48c7-9471-19a4a5c12247"
local CG_ROOT = "$CONTENT_" .. RFS_LID
local CG_CRAFTBOT = CG_ROOT .. "/CraftingRecipes/craftbot.json"
local CG_CRAFTBOT_RFS = CG_ROOT .. "/CraftingRecipes/craftbot_rfs.json"
local SURVIVAL_CRAFTER = "$SURVIVAL_DATA/Scripts/game/interactables/Crafter.lua"

pcall( function()
	if type( Crafter ) ~= "table" or type( Craftbot ) ~= "table" then
		dofile( SURVIVAL_CRAFTER )
	end
end )

local function recipeIsValid( recipe )
	local okUuid, recipeItemUuid = pcall( sm.uuid.new, recipe.itemId )
	if not okUuid or not recipeItemUuid then
		return false
	end
	local shapeOk = false
	pcall( function()
		shapeOk = sm.shape.uuidExists( recipeItemUuid ) == true
	end )
	if not shapeOk then
		local toolOk = false
		pcall( function()
			toolOk = sm.tool.uuidExists( recipeItemUuid ) == true
		end )
		if not toolOk then
			return false
		end
	end
	recipe.craftTime = math.ceil( tonumber( recipe.craftTime ) or 0 )
	for _, ingredient in ipairs( recipe.ingredientList or {} ) do
		local okIng, ingUuid = pcall( sm.uuid.new, ingredient.itemId )
		if not okIng or not ingUuid then
			return false
		end
		ingredient.itemId = ingUuid
		local ingShape = false
		pcall( function()
			ingShape = sm.shape.uuidExists( ingUuid ) == true
		end )
		if not ingShape then
			local ingTool = false
			pcall( function()
				ingTool = sm.tool.uuidExists( ingUuid ) == true
			end )
			if not ingTool then
				return false
			end
		end
	end
	return true
end

local function addUnique( files, seen, path )
	if type( path ) ~= "string" or path == "" or seen[path] then
		return
	end
	seen[path] = true
	files[#files + 1] = path
end

local function isVanillaIndexFile( json )
	return type( json ) == "table" and ( json.craftbot_core ~= nil or json.craftbot_beams ~= nil )
end

local function chatOnce( flag, msg )
	if _G[flag] then
		return
	end
	_G[flag] = true
	print( msg )
	-- Chat gui is not up during server_onCreate / loadCraftingRecipes (wrap stamp).
	if sm.localPlayer and sm.localPlayer.getLocalPlayer then
		pcall( function()
			if sm.localPlayer.getLocalPlayer() and sm.gui and sm.gui.chatMessage then
				sm.gui.chatMessage( msg )
			end
		end )
	end
end

local function stampPrefix()
	return tostring( RFS_PACK_STAMP or "[RFS] pack 0817-x grid" )
end

function RfsCrafterGrid.collectGridFiles( scan )
	local files = {}
	local seen = {}
	addUnique( files, seen, CG_CRAFTBOT )
	addUnique( files, seen, CG_CRAFTBOT_RFS )
	if scan and type( scan.craftPaths ) == "table" then
		for _, path in ipairs( scan.craftPaths ) do
			addUnique( files, seen, path )
		end
	end
	return files
end

local function schematicLockSet()
	local locks = {}
	for id, _ in pairs( SCHEMATIC_LOCKED ) do
		locks[id] = true
	end
	for id, _ in pairs( _G.g_extraHideoutSchematicUnlocks or {} ) do
		locks[tostring( id )] = true
	end
	return locks
end

function RfsCrafterGrid.installRecipeSet( scan )
	local files = RfsCrafterGrid.collectGridFiles( scan )
	local recipes = {}
	local recipesByIndex = {}
	local gpsInFile = false
	local alwaysAvailable = {}
	local schematicLocks = schematicLockSet()

	for _, path in ipairs( files ) do
		local fromRfsOwn = ( path == CG_CRAFTBOT_RFS or path == CG_CRAFTBOT )
		local ok, json = pcall( sm.json.open, path )
		if ok and type( json ) == "table" and not isVanillaIndexFile( json ) then
			for _, raw in ipairs( json ) do
				if type( raw ) == "table" and raw.itemId then
					local recipe = {
						itemId = tostring( raw.itemId ),
						quantity = tonumber( raw.quantity ) or 1,
						craftTime = tonumber( raw.craftTime ) or 0,
						ingredientList = {},
					}
					for _, ing in ipairs( raw.ingredientList or {} ) do
						if type( ing ) == "table" and ing.itemId then
							recipe.ingredientList[#recipe.ingredientList + 1] = {
								itemId = tostring( ing.itemId ),
								quantity = tonumber( ing.quantity ) or 1,
							}
						end
					end
					if recipeIsValid( recipe ) then
						if recipes[recipe.itemId] then
							-- Already from an earlier path (first wins). Avoid index/grid twins.
						else
							if recipe.itemId == GPS_UUID then
								gpsInFile = true
							end
							recipes[recipe.itemId] = recipe
							recipesByIndex[#recipesByIndex + 1] = recipe
							-- Free only when this pack owns the row and it is not a Hideout schematic.
							if fromRfsOwn and not schematicLocks[recipe.itemId] then
								alwaysAvailable[recipe.itemId] = true
							end
						end
					end
				end
			end
		end
	end

	g_craftingRecipeSets = g_craftingRecipeSets or {}
	g_craftingRecipeSets.craftbot_rfs_mods = {
		path = files,
		recipes = recipes,
		recipesByIndex = recipesByIndex,
	}
	_G.g_rfsCraftbotGridFiles = files
	_G.g_rfsCraftbotAlwaysAvailable = alwaysAvailable
	_G.g_rfsCraftbotSchematicLocks = schematicLocks

	g_unlockableCraftItems = g_unlockableCraftItems or {}
	for id, _ in pairs( recipes ) do
		if alwaysAvailable[id] then
			-- Always craftable (non-schematic RFS rows).
			g_unlockableCraftItems[id] = nil
		elseif schematicLocks[id] then
			-- Survival schematic banlist semantics: locked until Sv_UnlockRecipe.
			-- Do NOT mark unlockable=true — tools never enter recipesToUnlock and
			-- would otherwise appear free on the C++ grid.
			g_unlockableCraftItems[id] = nil
		else
			g_unlockableCraftItems[id] = true
		end
	end
	-- GPS is Hideout schematic — never force alwaysAvailable.
	local schematicN = 0
	for _ in pairs( schematicLocks ) do
		schematicN = schematicN + 1
	end
	print( string.format(
		"[RFS] craftbot C++ files n=%d gpsInFile=%s recipes=%d schematicLocks=%d path=%s",
		#files, tostring( gpsInFile ), #recipesByIndex, schematicN, CG_CRAFTBOT
	) )
	for i, path in ipairs( files ) do
		print( "[RFS] craftbot C++ " .. tostring( i ) .. " " .. tostring( path ) )
	end
	return gpsInFile
end

local function crafterWantsModGrid( self )
	if not ( self.crafter and type( self.crafter.recipeSets ) == "table" ) then
		return false
	end
	for _, recipeSet in ipairs( self.crafter.recipeSets ) do
		if recipeSet and recipeSet.name == "craftbot_other" then
			return true
		end
	end
	return false
end

local function vanillaSetCount( self )
	local n = 0
	if not ( self.crafter and g_craftingRecipeSets ) then
		return 0
	end
	for _, recipeSet in ipairs( self.crafter.recipeSets or {} ) do
		local set = recipeSet and g_craftingRecipeSets[recipeSet.name]
		if set and type( set.recipesByIndex ) == "table" then
			n = n + #set.recipesByIndex
		end
	end
	return n
end

-- itemIds already present in Survival / other recipe sets (e.g. Scrap Overdrive
-- craftbot_custom). Whole-file addGridItemsFromFile cannot partial-filter, so
-- skip a path when every recipe id is already known.
local function collectKnownRecipeIds()
	local seen = {}
	if type( g_craftingRecipeSets ) ~= "table" then
		return seen
	end
	for setName, setData in pairs( g_craftingRecipeSets ) do
		if setName ~= "craftbot_rfs_mods" and type( setData ) == "table" and type( setData.recipes ) == "table" then
			for id, _ in pairs( setData.recipes ) do
				seen[tostring( id )] = true
			end
		end
	end
	return seen
end

local function pathHasNewRecipeIds( path, seen )
	local ok, json = pcall( sm.json.open, path )
	if not ok or type( json ) ~= "table" or isVanillaIndexFile( json ) then
		return false
	end
	local any = false
	for _, raw in ipairs( json ) do
		if type( raw ) == "table" and raw.itemId then
			any = true
			if not seen[tostring( raw.itemId )] then
				return true
			end
		end
	end
	-- Empty / unreadable: do not add.
	return false
end

local function markPathRecipeIds( path, seen )
	local ok, json = pcall( sm.json.open, path )
	if not ok or type( json ) ~= "table" then
		return
	end
	for _, raw in ipairs( json ) do
		if type( raw ) == "table" and raw.itemId then
			seen[tostring( raw.itemId )] = true
		end
	end
end

-- Whole-file addGridItemsFromFile cannot drop individual rows. Write a pack-local
-- deduped slice so mod A + mod B (or twin path strings) cannot twin the same uuid.
local function saveDedupedGridFile( path, seen )
	local ok, json = pcall( sm.json.open, path )
	if not ok or type( json ) ~= "table" or isVanillaIndexFile( json ) then
		return nil, 0
	end
	local filtered = {}
	for _, raw in ipairs( json ) do
		if type( raw ) == "table" and raw.itemId then
			local id = tostring( raw.itemId )
			if not seen[id] then
				local row = {
					itemId = id,
					quantity = tonumber( raw.quantity ) or 1,
					craftTime = tonumber( raw.craftTime ) or 0,
					ingredientList = {},
				}
				for _, ing in ipairs( raw.ingredientList or {} ) do
					if type( ing ) == "table" and ing.itemId then
						row.ingredientList[#row.ingredientList + 1] = {
							itemId = tostring( ing.itemId ),
							quantity = tonumber( ing.quantity ) or 1,
						}
					end
				end
				filtered[#filtered + 1] = row
				seen[id] = true
			end
		end
	end
	if #filtered == 0 then
		return nil, 0
	end
	local safe = tostring( path ):gsub( "[^%w]", "_" )
	if #safe > 72 then
		safe = string.sub( safe, -72 )
	end
	local outPath = CG_ROOT .. "/CraftingRecipes/rfs_grid_" .. safe .. ".json"
	local okSave, errSave = pcall( sm.json.save, filtered, outPath )
	if not okSave then
		print( "[RFS] dedupe save failed: " .. tostring( errSave ) .. " path=" .. tostring( outPath ) )
		-- Fall back to original file (may twin already-known ids).
		return path, #filtered
	end
	return outPath, #filtered
end

local function rfsClUpdateRecipeGrid( self )
	local vanilla = Crafter._rfsVanillaUpdateGrid
	if type( vanilla ) == "function" then
		vanilla( self )
	end
	if not crafterWantsModGrid( self ) then
		return
	end
	local set = g_craftingRecipeSets and g_craftingRecipeSets.craftbot_rfs_mods
	if not ( set and self.cl and self.cl.guiInterface ) then
		return
	end
	local paths = set.path
	if type( paths ) == "string" then
		paths = { paths }
	end
	if type( paths ) ~= "table" then
		return
	end
	-- Pass unlockedRecipes so Hideout schematics stay locked until Sv_UnlockRecipe.
	-- Always-available rows are forced on. Never force schematic locks (incl. GPS) on.
	local extraOpts = {
		speed = ( self.crafter and self.crafter.speed ) or 1,
	}
	local unlocked = {}
	pcall( function()
		if RecipeManager and RecipeManager.Cl_GetUnlockedRecipes then
			unlocked = RecipeManager.Cl_GetUnlockedRecipes() or {}
		end
	end )
	if type( unlocked ) ~= "table" then
		unlocked = {}
	end
	local schematicLocks = _G.g_rfsCraftbotSchematicLocks or schematicLockSet()
	for id, _ in pairs( _G.g_rfsCraftbotAlwaysAvailable or {} ) do
		if not schematicLocks[id] then
			unlocked[id] = true
		end
	end
	-- Strip Hideout schematic rows unless RecipeManager already unlocked them.
	for id, _ in pairs( schematicLocks ) do
		local really = false
		pcall( function()
			really = RecipeManager.Cl_IsUnlocked( id ) == true
		end )
		if not really then
			unlocked[id] = nil
		end
	end
	extraOpts.unlockedRecipes = unlocked
	local seen = collectKnownRecipeIds()
	local skipped = 0
	for _, path in ipairs( paths ) do
		if path == CG_CRAFTBOT or path == CG_CRAFTBOT_RFS then
			if not pathHasNewRecipeIds( path, seen ) then
				skipped = skipped + 1
			else
				local ok, err = pcall( function()
					self.cl.guiInterface:addGridItemsFromFile( "RecipeGrid", path, extraOpts )
				end )
				markPathRecipeIds( path, seen )
				if not _G.g_rfsGridAddChat then
					chatOnce( "g_rfsGridAddChat", string.format(
						"%s wrap addGrid ok=%s %s",
						stampPrefix(), tostring( ok ), tostring( path )
					) )
					if not ok then
						print( "[RFS] addGridItemsFromFile failed: " .. tostring( err ) )
					end
				end
			end
		else
			local filteredPath, addedN = saveDedupedGridFile( path, seen )
			if not filteredPath or addedN <= 0 then
				skipped = skipped + 1
			else
				local ok, err = pcall( function()
					self.cl.guiInterface:addGridItemsFromFile( "RecipeGrid", filteredPath, extraOpts )
				end )
				if not _G.g_rfsGridAddChat then
					chatOnce( "g_rfsGridAddChat", string.format(
						"%s wrap addGrid ok=%s new=%d %s",
						stampPrefix(), tostring( ok ), addedN, tostring( path )
					) )
					if not ok then
						print( "[RFS] addGridItemsFromFile failed: " .. tostring( err ) )
					end
				end
			end
		end
	end
	if skipped > 0 and not _G.g_rfsGridSkipChat then
		chatOnce( "g_rfsGridSkipChat", string.format(
			"%s craftbot skip %d path(s) already on grid (itemId dedupe)",
			stampPrefix(), skipped
		) )
	end
	if self.cl then
		self.cl._rfsModGridApplied = true
	end
end

local function rfsGetRecipeByIndex( self, index )
	local offset = vanillaSetCount( self )
	if index <= offset then
		local vanilla = Crafter._rfsVanillaGetByIndex
		if type( vanilla ) == "function" then
			return vanilla( self, index )
		end
		return nil
	end
	local extras = g_craftingRecipeSets and g_craftingRecipeSets.craftbot_rfs_mods
	if extras and type( extras.recipesByIndex ) == "table" then
		return extras.recipesByIndex[index - offset]
	end
	return nil
end

local function rfsGetRecipeByUuid( self, stringUuid )
	local vanilla = Crafter._rfsVanillaGetByUuid
	if type( vanilla ) == "function" then
		local recipe = vanilla( self, stringUuid )
		if recipe then
			return recipe
		end
	end
	local extras = g_craftingRecipeSets and g_craftingRecipeSets.craftbot_rfs_mods
	if extras and extras.recipes then
		return extras.recipes[tostring( stringUuid )]
	end
	return nil
end

local function rfsClientOnUpdate( self, deltaTime )
	if crafterWantsModGrid( self ) and self.cl and self.cl.guiInterface and not self.cl._rfsModGridApplied then
		pcall( rfsClUpdateRecipeGrid, self )
		if self.cl then
			self.cl._rfsModGridApplied = true
		end
	end
	local vanilla = Crafter._rfsVanillaClientOnUpdate
	if type( vanilla ) == "function" then
		vanilla( self, deltaTime )
	end
end

-- Grid forces alwaysAvailable into unlockedRecipes for C++ display, but CRAFT
-- still gates on RecipeManager.Cl/Sv_IsUnlocked (DefaultUnlocked or saved unlock).
-- Always-available RFS rows never enter that table → yellow CRAFT, no craft.
local function rfsIsCraftUnlocked( itemId )
	local id = tostring( itemId or "" )
	if id == "" then
		return false
	end
	local always = _G.g_rfsCraftbotAlwaysAvailable
	local locks = _G.g_rfsCraftbotSchematicLocks or schematicLockSet()
	if always and always[id] and not locks[id] then
		return true
	end
	local unlocked = false
	pcall( function()
		if sm.isServerMode() then
			unlocked = RecipeManager.Sv_IsUnlocked( id ) == true
		else
			unlocked = RecipeManager.Cl_IsUnlocked( id ) == true
		end
	end )
	return unlocked
end

local function rfsClOnCraft( self, buttonName, index, data )
	local recipe = self:getRecipeByUuid( data.itemId )
	if recipe ~= nil and rfsIsCraftUnlocked( recipe.itemId ) then
		self.network:sendToServer( "sv_n_craft", { itemId = data.itemId } )
	else
		print( "Recipe is locked" )
	end
end

local function rfsSvNCraft( self, params, player )
	local recipe = self:getRecipeByUuid( params.itemId )
	if recipe ~= nil and rfsIsCraftUnlocked( recipe.itemId ) then
		self:sv_craft( { recipe = recipe }, player )
	else
		print( "Recipe is locked" )
	end
end

local function rfsSvNCraftIndex( self, params, player )
	local recipe = self:getRecipeByIndex( params.index )
	if recipe ~= nil and rfsIsCraftUnlocked( recipe.itemId ) then
		self:sv_craft( { recipe = recipe }, player )
	else
		print( "Recipe is locked index" )
	end
end

local function patchClass( cls )
	if type( cls ) ~= "table" then
		return false
	end
	if type( cls.cl_updateRecipeGrid ) ~= "function" then
		return false
	end
	cls.cl_updateRecipeGrid = rfsClUpdateRecipeGrid
	if type( cls.getRecipeByIndex ) == "function" then
		cls.getRecipeByIndex = rfsGetRecipeByIndex
	end
	if type( cls.getRecipeByUuid ) == "function" then
		cls.getRecipeByUuid = rfsGetRecipeByUuid
	end
	if type( cls.client_onUpdate ) == "function" then
		cls.client_onUpdate = rfsClientOnUpdate
	end
	if type( cls.cl_onCraft ) == "function" then
		cls.cl_onCraft = rfsClOnCraft
	end
	if type( cls.sv_n_craft ) == "function" then
		cls.sv_n_craft = rfsSvNCraft
	end
	if type( cls.sv_n_craftIndex ) == "function" then
		cls.sv_n_craftIndex = rfsSvNCraftIndex
	end
	return true
end

function RfsCrafterGrid.installHook()
	pcall( function()
		if type( Crafter ) ~= "table" or type( Craftbot ) ~= "table" then
			dofile( SURVIVAL_CRAFTER )
		end
	end )
	if type( Crafter ) ~= "table" then
		return false
	end
	if type( Crafter.cl_updateRecipeGrid ) ~= "function" then
		return false
	end
	if Crafter.cl_updateRecipeGrid ~= rfsClUpdateRecipeGrid then
		Crafter._rfsVanillaUpdateGrid = Crafter.cl_updateRecipeGrid
		Crafter._rfsVanillaGetByIndex = Crafter.getRecipeByIndex
		Crafter._rfsVanillaGetByUuid = Crafter.getRecipeByUuid
		Crafter._rfsVanillaClientOnUpdate = Crafter.client_onUpdate
		Crafter._rfsVanillaClOnCraft = Crafter.cl_onCraft
		Crafter._rfsVanillaSvNCraft = Crafter.sv_n_craft
		Crafter._rfsVanillaSvNCraftIndex = Crafter.sv_n_craftIndex
	end
	-- Survival copies methods onto Craftbot at class() time. Patch both.
	local crafterOk = patchClass( Crafter )
	local craftbotOk = patchClass( Craftbot )
	pcall( function() patchClass( PortableCraftbot ) end )
	if craftbotOk then
		chatOnce( "g_rfsGridWrapChat", string.format(
			"%s wrap Craftbot=%s Crafter=%s %s",
			stampPrefix(), tostring( craftbotOk ), tostring( crafterOk ), CG_CRAFTBOT
		) )
	end
	return crafterOk
end

function RfsCrafterGrid.tick()
	RfsCrafterGrid.installHook()
end
