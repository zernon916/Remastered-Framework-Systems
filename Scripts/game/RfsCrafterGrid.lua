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
	["e8f4a2b1-3c7d-4e9f-8a2b-1d5e6f7a8b9c"] = true, -- Handheld Radio tool, 5 Farmers
	["b4e8c1a0-7d2f-4a91-9c3e-29f1a8d6b5e7"] = true, -- Hack Beacon station core, 10 Farmers
	["ca2d0a9f-1a5b-4c7d-8e09-fb3a4b5c6d7e"] = true, -- Radio Antenna, 15 Farmers
	["d9e3b1a0-2b6c-4d8e-9f1a-0c4d5e6f7a8b"] = true, -- Radio Battery Brick, 15 Farmers
	["bb1c098e-094a-4b6c-7d08-ea293a4b5c6d"] = true, -- Radio Lock, 8000 miner tokens
	["6f391c5b-82d4-4e17-9a60-c1d5e8f2a4b7"] = true, -- Chemical Regeneration Station, 10 Farmers
	["7a402d6c-93e5-4f28-ab71-d2e6f9a3b5c8"] = true, -- Solar Panel, 5 Farmers
	["8b513e7d-a4f6-4039-bc82-e3f70a4b6d9e"] = true, -- Rechargeable Battery, 1 Farmer
	["9c624f8e-b507-414a-cd93-f4081b5c7eaf"] = true, -- Rechargeable Battery Box, 2 Farmers
	["c2f158b0-4d7e-4a19-9c6b-8e3a1f50d247"] = true, -- Aim Core, schematic-locked
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
	pcall( function()
		sm.gui.chatMessage( msg )
	end )
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

function RfsCrafterGrid.installRecipeSet( scan )
	local files = RfsCrafterGrid.collectGridFiles( scan )
	local recipes = {}
	local recipesByIndex = {}
	local gpsInFile = false
	local alwaysAvailable = {}

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
						if recipe.itemId == GPS_UUID then
							gpsInFile = true
						end
						recipes[recipe.itemId] = recipe
						recipesByIndex[#recipesByIndex + 1] = recipe
						if fromRfsOwn and not SCHEMATIC_LOCKED[recipe.itemId] then
							alwaysAvailable[recipe.itemId] = true
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

	g_unlockableCraftItems = g_unlockableCraftItems or {}
	for id, _ in pairs( recipes ) do
		if alwaysAvailable[id] then
			g_unlockableCraftItems[id] = nil
		else
			g_unlockableCraftItems[id] = true
		end
	end
	-- This pack: GPS must show on Tools without Hideout buy.
	g_unlockableCraftItems[GPS_UUID] = nil
	alwaysAvailable[GPS_UUID] = true

	print( string.format(
		"[RFS] craftbot C++ files n=%d gpsInFile=%s recipes=%d path=%s",
		#files, tostring( gpsInFile ), #recipesByIndex, CG_CRAFTBOT
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
	-- Pass unlockedRecipes so Hideout schematics (pod/solar) stay hidden.
	-- Always-available rows (GPS) are forced on. Hideout schematics stay hidden until unlock.
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
	for id, _ in pairs( _G.g_rfsCraftbotAlwaysAvailable or {} ) do
		unlocked[id] = true
	end
	unlocked[GPS_UUID] = true
	extraOpts.unlockedRecipes = unlocked
	for _, path in ipairs( paths ) do
		local ok, err = pcall( function()
			self.cl.guiInterface:addGridItemsFromFile( "RecipeGrid", path, extraOpts )
		end )
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
