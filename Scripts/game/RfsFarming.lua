-- RfsFarming.lua — Farming helpers for Recipe Framework Survival (/setup Farming tab)
-- Author: DemonsDen126
-- Uses Survival GrowingHarvestable / HarvestableSoil / SoilBag APIs.

RfsFarming = RfsFarming or {}

dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_harvestable.lua" )

local STORAGE_KEY = { "rfs", "farming" }
-- Per-player Growth Time overlay prefs (not world-wide). Keyed by player id.
local PLAYER_OVERLAY_STORAGE = { "rfs", "playerGrowthOverlay" }

-- Outdoor plantables (GrowingHarvestable). Instant Farm / overlays target these.
local GROWING_UUID = {
	[tostring( hvs_growing_blueberry )] = true,
	[tostring( hvs_growing_banana )] = true,
	[tostring( hvs_growing_redbeet )] = true,
	[tostring( hvs_growing_carrot )] = true,
	[tostring( hvs_growing_tomato )] = true,
	[tostring( hvs_growing_orange )] = true,
	[tostring( hvs_growing_potato )] = true,
	[tostring( hvs_growing_pineapple )] = true,
	[tostring( hvs_growing_broccoli )] = true,
	[tostring( hvs_growing_cotton )] = true,
	[tostring( hvs_growing_chili )] = true,
	[tostring( hvs_growing_pigmentflower )] = true,
}

-- Mature outdoor crops (MatureHarvestable) — Hay Farm harvest targets.
local MATURE_UUID = {
	[tostring( hvs_mature_blueberry )] = true,
	[tostring( hvs_mature_banana )] = true,
	[tostring( hvs_mature_redbeet )] = true,
	[tostring( hvs_mature_carrot )] = true,
	[tostring( hvs_mature_tomato )] = true,
	[tostring( hvs_mature_orange )] = true,
	[tostring( hvs_mature_potato )] = true,
	[tostring( hvs_mature_pineapple )] = true,
	[tostring( hvs_mature_broccoli )] = true,
	[tostring( hvs_mature_cotton )] = true,
	[tostring( hvs_mature_chili )] = true,
	[tostring( hvs_mature_pigmentflower )] = true,
}

local SOIL_UUID = tostring( hvs_soil )

-- Plantable seeds — same set as Survival Planter.lua / sm.item.getPlantableUuids outdoor.
-- Static fallback UUIDs from survival_items.lua (used when ITEMS globals are late).
local SEED_DEFS = {
	{ name = "Banana", key = "obj_seed_banana", uuid = "22beade5-38ca-47b4-a2ee-32403f58a862" },
	{ name = "Blueberry", key = "obj_seed_blueberry", uuid = "4b6d2bee-d0f1-4e56-96f0-d2596388cad2" },
	{ name = "Orange", key = "obj_seed_orange", uuid = "bee966b0-b5e5-41da-b992-5d363ab85ae4" },
	{ name = "Pineapple", key = "obj_seed_pineapple", uuid = "9edb6f7c-fb44-4348-a1c4-8afb41b92d8a" },
	{ name = "Carrot", key = "obj_seed_carrot", uuid = "9c82a525-8a8b-4483-9595-505aaa042486" },
	{ name = "Redbeet", key = "obj_seed_redbeet", uuid = "64051718-a3f1-422b-bda3-277efa0c4545" },
	{ name = "Tomato", key = "obj_seed_tomato", uuid = "38e41fb5-dd50-4294-829d-a517f0282fed" },
	{ name = "Broccoli", key = "obj_seed_broccoli", uuid = "1c6756ca-3a60-4dcb-a5d1-353edf818308" },
	{ name = "Potato", key = "obj_seed_potato", uuid = "eb1ef696-5c05-4662-9e47-fe1e0875ff84" },
	{ name = "Cotton", key = "obj_seed_cotton", uuid = "93c27ab2-4930-4654-ba1c-bcfe35e966f6" },
	{ name = "Pigment Flower", key = "obj_seed_pigmentflower", uuid = "c44b27da-88cf-4e17-b872-6236a1172688" },
	{ name = "Chili", key = "obj_seed_chili", uuid = "8883e0ee-8a6e-423a-a4e0-583d9bf105bd" },
}

local SEED_BY_UUID = nil
local SEED_LABELS = nil
local DEFAULT_SEED_UUID = SEED_DEFS[7].uuid -- Tomato

local function rebuildSeedIndex()
	SEED_BY_UUID = {}
	SEED_LABELS = {}
	for _, def in ipairs( SEED_DEFS ) do
		local uuid = nil
		if type( ITEMS ) == "table" and ITEMS[def.key] then
			uuid = ITEMS[def.key]
		else
			local g = _G[def.key]
			if g ~= nil then
				uuid = g
			else
				local ok, u = pcall( sm.uuid.new, def.uuid )
				if ok then
					uuid = u
				end
			end
		end
		if uuid then
			local s = string.lower( tostring( uuid ) )
			SEED_BY_UUID[s] = {
				name = def.name,
				key = def.key,
				uuid = uuid,
				uuidStr = s,
			}
			SEED_LABELS[#SEED_LABELS + 1] = { name = def.name, uuid = uuid, uuidStr = s }
		end
	end
	table.sort( SEED_LABELS, function( a, b )
		return tostring( a.name ) < tostring( b.name )
	end )
end

-- Water every ~2.5s while Always Watered is on (WaterRetention is ~1.5 days).
local WATER_INTERVAL_TICKS = 100
-- Unhosted text (setRotation is ignored on hosted effects). Prefer RfsGrowText
-- (InWorldText / VS_CLIP_SPACE nametag-style) then vanilla DebugText.
local OVERLAY_EFFECTS = { "RfsGrowText", "DebugText" }
local TEXT_FACE = sm.vec3.new( 0, 1, 0 ) -- DebugText / nametag default facing
local WORLD_UP = sm.vec3.new( 0, 0, 1 )
local OVERLAY_AABB_PAD = 0.32
local OVERLAY_FX_VER = 2

local defaults = {
	alwaysWatered = false,
	dirtOnBlocks = false,
	fastPlace = false,
	fastPickup = false,
}

---------------------------------------------------------------------------
-- Persistence (world sm.storage) — alwaysWatered / dirtOnBlocks / fastPlace / fastPickup.
-- Growth Time overlay is per-player (see getPlayerGrowthOverlay).
---------------------------------------------------------------------------

local function playerIdKey( player )
	local id = nil
	pcall( function() id = player.id end )
	if id == nil then
		pcall( function() id = player:getId() end )
	end
	if id == nil then
		return nil
	end
	return tostring( id )
end

local function loadPlayerOverlayTable()
	local ok, data = pcall( sm.storage.load, PLAYER_OVERLAY_STORAGE )
	if ok and type( data ) == "table" then
		return data
	end
	return {}
end

function RfsFarming.getPlayerGrowthOverlay( player )
	local key = playerIdKey( player )
	if not key then
		return false
	end
	local data = loadPlayerOverlayTable()
	local entry = data[key]
	if type( entry ) == "boolean" then
		return entry
	end
	if type( entry ) == "table" and entry.growthOverlay ~= nil then
		return entry.growthOverlay and true or false
	end
	return false
end

function RfsFarming.setPlayerGrowthOverlay( player, enabled )
	local key = playerIdKey( player )
	if not key then
		return false
	end
	local data = loadPlayerOverlayTable()
	data[key] = enabled and true or false
	pcall( sm.storage.save, PLAYER_OVERLAY_STORAGE, data )
	return enabled and true or false
end

function RfsFarming.togglePlayerGrowthOverlay( player )
	local nextVal = not RfsFarming.getPlayerGrowthOverlay( player )
	return RfsFarming.setPlayerGrowthOverlay( player, nextVal )
end

-- Client-local: only the local player's preference drives plant overlays.
_G.g_rfsGrowthOverlay = _G.g_rfsGrowthOverlay or false

function RfsFarming.cl_setLocalGrowthOverlay( enabled )
	_G.g_rfsGrowthOverlay = enabled and true or false
end

function RfsFarming.load()
	local cfg = {
		alwaysWatered = defaults.alwaysWatered,
		dirtOnBlocks = defaults.dirtOnBlocks,
		fastPlace = defaults.fastPlace,
		fastPickup = defaults.fastPickup,
	}
	local ok, data = pcall( sm.storage.load, STORAGE_KEY )
	if ok and type( data ) == "table" then
		if data.alwaysWatered ~= nil then
			cfg.alwaysWatered = data.alwaysWatered and true or false
		end
		-- Legacy world growthOverlay is ignored (moved to per-player /menu).
		if data.dirtOnBlocks ~= nil then
			cfg.dirtOnBlocks = data.dirtOnBlocks and true or false
		end
		if data.fastPlace ~= nil then
			cfg.fastPlace = data.fastPlace and true or false
		end
		if data.fastPickup ~= nil then
			cfg.fastPickup = data.fastPickup and true or false
		end
	end
	RfsFarming.state = cfg
	RfsFarming.cl_applyGlobals( cfg )
	return cfg
end

function RfsFarming.save()
	local cfg = RfsFarming.state or RfsFarming.load()
	-- Do not rewrite legacy growthOverlay into world storage.
	pcall( sm.storage.save, STORAGE_KEY, {
		alwaysWatered = cfg.alwaysWatered and true or false,
		dirtOnBlocks = cfg.dirtOnBlocks and true or false,
		fastPlace = cfg.fastPlace and true or false,
		fastPickup = cfg.fastPickup and true or false,
	} )
	RfsFarming.cl_applyGlobals( cfg )
	return cfg
end

function RfsFarming.get()
	return RfsFarming.state or RfsFarming.load()
end

function RfsFarming.snapshot()
	local cfg = RfsFarming.get()
	return {
		alwaysWatered = cfg.alwaysWatered and true or false,
		dirtOnBlocks = cfg.dirtOnBlocks and true or false,
		fastPlace = cfg.fastPlace and true or false,
		fastPickup = cfg.fastPickup and true or false,
	}
end

function RfsFarming.cl_applyGlobals( cfg )
	cfg = cfg or RfsFarming.get()
	_G.g_rfsAlwaysWatered = cfg.alwaysWatered and true or false
	_G.g_rfsDirtOnBlocks = cfg.dirtOnBlocks and true or false
	_G.g_rfsFastPlace = cfg.fastPlace and true or false
	_G.g_rfsFastPickup = cfg.fastPickup and true or false
	-- g_rfsGrowthOverlay is per-player; set via RfsFarming.cl_setLocalGrowthOverlay.
end

function RfsFarming.dirtOnBlocksActive()
	return ( _G.g_rfsDirtOnBlocks == true ) and RfsSettings.cheatsEnabled()
end

function RfsFarming.fastPlaceActive()
	return ( _G.g_rfsFastPlace == true ) and RfsSettings.cheatsEnabled()
end

function RfsFarming.fastPickupActive()
	return ( _G.g_rfsFastPickup == true ) and RfsSettings.cheatsEnabled()
end

---------------------------------------------------------------------------
-- Harvestable helpers
---------------------------------------------------------------------------

function RfsFarming.isGrowingUuid( uuid )
	return GROWING_UUID[tostring( uuid )] == true
end

function RfsFarming.isMatureUuid( uuid )
	return MATURE_UUID[tostring( uuid )] == true
end

function RfsFarming.isSoilUuid( uuid )
	return tostring( uuid ) == SOIL_UUID
end

---------------------------------------------------------------------------
-- Plantable seeds (Hay Farm seed picker + allowlist)
-- Source: Survival Planter.lua seedItems + survival_items.lua UUIDs.
-- Runtime prefer sm.item.getPlantable / getPlantableUuids when available.
---------------------------------------------------------------------------

function RfsFarming.getPlantableSeeds()
	if not SEED_LABELS then
		rebuildSeedIndex()
	end
	-- Prefer engine plantable list when present (filters non-plantables).
	local live = nil
	pcall( function()
		if type( sm.item.getPlantableUuids ) == "function" then
			live = sm.item.getPlantableUuids()
		end
	end )
	if type( live ) == "table" and #live > 0 then
		local out = {}
		local seen = {}
		for _, uuid in ipairs( live ) do
			local s = string.lower( tostring( uuid ) )
			local rec = SEED_BY_UUID and SEED_BY_UUID[s]
			if rec and not seen[s] then
				seen[s] = true
				out[#out + 1] = { name = rec.name, uuid = rec.uuid, uuidStr = s }
			end
		end
		if #out > 0 then
			table.sort( out, function( a, b )
				return tostring( a.name ) < tostring( b.name )
			end )
			return out
		end
	end
	return SEED_LABELS or {}
end

function RfsFarming.getSeedDropdownLabels()
	local labels = {}
	for _, rec in ipairs( RfsFarming.getPlantableSeeds() ) do
		labels[#labels + 1] = rec.name
	end
	return labels
end

function RfsFarming.seedUuidFromLabel( label )
	label = string.lower( tostring( label or "" ) )
	for _, rec in ipairs( RfsFarming.getPlantableSeeds() ) do
		if string.lower( tostring( rec.name ) ) == label then
			return rec.uuid, rec.name
		end
	end
	return nil, nil
end

function RfsFarming.seedLabelFromUuid( uuid )
	if not SEED_BY_UUID then
		rebuildSeedIndex()
	end
	local s = string.lower( tostring( uuid or "" ) )
	local rec = SEED_BY_UUID[s]
	if rec then
		return rec.name
	end
	return nil
end

function RfsFarming.isPlantableSeed( uuid )
	if not SEED_BY_UUID then
		rebuildSeedIndex()
	end
	local s = string.lower( tostring( uuid or "" ) )
	if SEED_BY_UUID[s] then
		return true
	end
	local ok, data = pcall( function()
		return sm.item.getPlantable( uuid )
	end )
	return ok and type( data ) == "table" and data.harvestable ~= nil
end

function RfsFarming.resolveSeedUuid( seedUuid )
	if not SEED_BY_UUID then
		rebuildSeedIndex()
	end
	if seedUuid and RfsFarming.isPlantableSeed( seedUuid ) then
		local s = string.lower( tostring( seedUuid ) )
		local rec = SEED_BY_UUID[s]
		return rec and rec.uuid or seedUuid
	end
	local ok, u = pcall( sm.uuid.new, DEFAULT_SEED_UUID )
	if ok then
		return u
	end
	return seedUuid
end

function RfsFarming.growingUuidForSeed( seedUuid )
	local ok, data = pcall( function()
		return sm.item.getPlantable( seedUuid )
	end )
	if ok and type( data ) == "table" and data.harvestable then
		local ok2, u = pcall( sm.uuid.new, data.harvestable )
		if ok2 then
			return u
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Bot plant / harvest (no player inventory; no melee crop destroy)
---------------------------------------------------------------------------

-- Plant seedUuid onto empty soil harvestable. Caller must already spend the seed.
-- Returns true on success.
function RfsFarming.sv_botPlant( soilHvs, seedUuid )
	if not soilHvs or not sm.exists( soilHvs ) or not seedUuid then
		return false
	end
	local uid = nil
	pcall( function()
		uid = soilHvs:getUuid()
	end )
	if not uid or not RfsFarming.isSoilUuid( uid ) then
		return false
	end
	-- Skip during farm raids (matches HarvestableSoil.sv_e_plant).
	local inRaid = false
	pcall( function()
		if type( RaidManager ) == "table" and RaidManager.Sv_AreaHasActiveRaid then
			inRaid = RaidManager.Sv_AreaHasActiveRaid( soilHvs.worldPosition or soilHvs:getPosition(), soilHvs:getWorld().id )
		end
	end )
	if inRaid then
		return false
	end
	local growingUuid = RfsFarming.growingUuidForSeed( seedUuid )
	if not growingUuid then
		return false
	end
	RfsFarming.ensureBotFarmHooks()
	local box = { ok = false }
	pcall( function()
		sm.event.sendToHarvestable( soilHvs, "sv_e_rfsBotPlant", {
			growingUuid = growingUuid,
			result = box,
		} )
	end )
	if box.ok then
		return true
	end
	-- Fallback if soil script not hooked / event missed.
	if sm.exists( soilHvs ) then
		return RfsFarming._sv_plantSoilInline( soilHvs, growingUuid )
	end
	return true
end

function RfsFarming._sv_plantSoilInline( soilHvs, growingUuid )
	if not soilHvs or not sm.exists( soilHvs ) or not growingUuid then
		return false
	end
	local planted = false
	pcall( function()
		local pos = soilHvs:getPosition()
		local rot = soilHvs:getRotation()
		local plantedHvs = sm.harvestable.createHarvestable( growingUuid, pos, rot )
		plantedHvs:setParams( { plantedByPlayer = true } )
		sm.effect.playEffect( "Plants - Planted", pos )
		soilHvs:destroy()
		planted = true
		pcall( function()
			local world = plantedHvs:getWorld()
			if world and world.publicData and world.publicData.type == "Overworld" and type( RaidManager ) == "table" then
				RaidManager.Sv_DetectCrop( plantedHvs )
			end
		end )
	end )
	return planted
end

-- Harvest a mature outdoor crop into a loot list { { uuid, qty }, ... }.
-- Leaves soil behind. Never uses melee destroy on growing plants.
function RfsFarming.sv_botHarvest( matureHvs )
	if not matureHvs or not sm.exists( matureHvs ) then
		return nil
	end
	local uid = nil
	pcall( function()
		uid = matureHvs:getUuid()
	end )
	if not uid or not RfsFarming.isMatureUuid( uid ) then
		return nil
	end
	local result = nil
	pcall( function()
		local box = { loot = nil }
		sm.event.sendToHarvestable( matureHvs, "sv_e_rfsBotHarvest", box )
		result = box.loot
	end )
	return result
end

function RfsFarming.ensureBotFarmHooks()
	-- HarvestableSoil: plant without inventory spend (seed already in bot buffer).
	if type( HarvestableSoil ) ~= "table" then
		pcall( function()
			dofile( "$SURVIVAL_DATA/Scripts/game/harvestable/HarvestableSoil.lua" )
		end )
	end
	if type( HarvestableSoil ) == "table" and not HarvestableSoil._rfsBotPlantRpc then
		function HarvestableSoil.sv_e_rfsBotPlant( self, params )
			if type( params ) ~= "table" or not params.growingUuid then
				return
			end
			if type( RaidManager ) == "table" and RaidManager.Sv_AreaHasActiveRaid then
				if RaidManager.Sv_AreaHasActiveRaid( self.harvestable.worldPosition, self.harvestable:getWorld().id ) then
					return
				end
			end
			if self.sv_plant then
				self:sv_plant( params.growingUuid )
				if type( params.result ) == "table" then
					params.result.ok = true
				end
			end
		end
		HarvestableSoil._rfsBotPlantRpc = true
		print( "[RFS] Farming bot plant hooked HarvestableSoil" )
	end

	-- MatureHarvestable: collect produce+seeds into params.loot (no player inventory).
	if type( MatureHarvestable ) ~= "table" then
		pcall( function()
			dofile( "$SURVIVAL_DATA/Scripts/game/harvestable/MatureHarvestable.lua" )
		end )
	end
	if type( MatureHarvestable ) == "table" and not MatureHarvestable._rfsBotHarvestRpc then
		function MatureHarvestable.sv_e_rfsBotHarvest( self, params )
			params = params or {}
			if not sm.exists( self.harvestable ) then
				return
			end
			self.harvestable.publicData = self.harvestable.publicData or {}
			if self.harvestable.publicData.harvested then
				return
			end
			local loot = {}
			local harvestUuid = nil
			local harvestQty = 1
			local seedUuid = nil
			local seedQty = 1
			pcall( function()
				harvestUuid = sm.uuid.new( self.data.harvest )
				harvestQty = tonumber( self.data.amount ) or 1
			end )
			pcall( function()
				seedUuid = sm.uuid.new( self.data.seed )
				if type( PlantSeedDropAmount ) == "function" then
					seedQty = PlantSeedDropAmount( seedUuid )
				else
					seedQty = 1
				end
			end )
			if harvestUuid then
				loot[#loot + 1] = { uuid = harvestUuid, qty = math.max( 1, harvestQty ) }
			end
			if seedUuid and ( tonumber( seedQty ) or 0 ) > 0 then
				loot[#loot + 1] = { uuid = seedUuid, qty = math.max( 1, math.floor( seedQty ) ) }
			end
			pcall( function()
				sm.effect.playEffect( "Plants - Picked", self.harvestable:getPosition() )
			end )
			pcall( function()
				sm.harvestable.createHarvestable( hvs_soil, self.harvestable:getPosition(), self.harvestable:getRotation() )
			end )
			pcall( function()
				if type( RaidManager ) == "table" and RaidManager.Sv_CropDestroyed then
					RaidManager.Sv_CropDestroyed( self.harvestable )
				end
			end )
			self.harvestable.publicData.harvested = true
			pcall( function()
				self.harvestable:destroy()
			end )
			params.loot = loot
		end
		MatureHarvestable._rfsBotHarvestRpc = true
		print( "[RFS] Farming bot harvest hooked MatureHarvestable" )
	end
	return true
end

function RfsFarming.sv_collectWorlds( game )
	local worlds = {}
	local seen = {}
	local function add( w )
		if w and sm.exists( w ) then
			local id = nil
			pcall( function() id = w.id end )
			local key = id ~= nil and tostring( id ) or tostring( w )
			if not seen[key] then
				seen[key] = true
				worlds[#worlds + 1] = w
			end
		end
	end

	if game and game.sv and game.sv.saved then
		add( game.sv.saved.overworld )
	end
	if game and game.sv and game.sv.undergroundWorlds then
		for _, w in pairs( game.sv.undergroundWorlds ) do
			add( w )
		end
	end
	pcall( function()
		add( sm.world.getCurrentWorld() )
	end )
	return worlds
end

function RfsFarming.sv_forEachHarvestable( game, fn )
	for _, world in ipairs( RfsFarming.sv_collectWorlds( game ) ) do
		local ok, list = pcall( sm.harvestable.getAllHarvestables, world )
		if ok and type( list ) == "table" then
			for _, hvs in ipairs( list ) do
				if hvs and sm.exists( hvs ) then
					fn( hvs )
				end
			end
		end
	end
end

function RfsFarming.advanceGrowthTicks( game, ticks )
	ticks = tonumber( ticks ) or 0
	if ticks <= 0 then
		return
	end
	RfsFarming.ensureGrowHooks()
	RfsFarming.sv_forEachHarvestable( game, function( hvs )
		pcall( function()
			sm.event.sendToHarvestable( hvs, "sv_e_rfsAdvanceGrowth", { ticks = ticks } )
		end )
	end )
end

-- Instant Farm: force every loaded GrowingHarvestable to mature (world-wide across
-- known Survival worlds). Only harvestables in currently loaded cells are returned
-- by getAllHarvestables — unload plants mature when their cell loads if you press again.
function RfsFarming.sv_instantFarm( game )
	local count = 0
	RfsFarming.sv_forEachHarvestable( game, function( hvs )
		local uuid = nil
		pcall( function() uuid = hvs:getUuid() or hvs.uuid end )
		if uuid and RfsFarming.isGrowingUuid( uuid ) then
			local ok = pcall( sm.event.sendToHarvestable, hvs, "sv_done" )
			if ok then
				count = count + 1
			end
		end
	end )
	return count
end

-- Keep soil + growing plantables wet (calls Survival sv_e_waterSoil).
function RfsFarming.sv_waterAll( game )
	local count = 0
	RfsFarming.sv_forEachHarvestable( game, function( hvs )
		local uuid = nil
		pcall( function() uuid = hvs:getUuid() or hvs.uuid end )
		if uuid and ( RfsFarming.isGrowingUuid( uuid ) or RfsFarming.isSoilUuid( uuid ) ) then
			local ok = pcall( sm.event.sendToHarvestable, hvs, "sv_e_waterSoil" )
			if ok then
				count = count + 1
			end
		end
	end )
	return count
end

function RfsFarming.sv_tick( game )
	local cfg = RfsFarming.get()
	if not cfg.alwaysWatered then
		return
	end
	if not RfsSettings.cheatsEnabled() then
		return
	end
	game.sv = game.sv or {}
	local now = sm.game.getCurrentTick()
	local nextAt = game.sv.rfsFarmWaterAt or 0
	if now < nextAt then
		return
	end
	game.sv.rfsFarmWaterAt = now + WATER_INTERVAL_TICKS
	RfsFarming.sv_waterAll( game )
end

function RfsFarming.ensureSoilBagHooks()
	if type( RfsSoilPlacement ) == "table" and type( RfsSoilPlacement.ensureHooks ) == "function" then
		return RfsSoilPlacement.ensureHooks()
	end
	return false
end

---------------------------------------------------------------------------
-- Growth overlay (client): patch GrowingHarvestable after Survival loads it
---------------------------------------------------------------------------

local function formatRemain( ticks )
	local secs = math.max( 0, math.ceil( ticks / 40 ) )
	local m = math.floor( secs / 60 )
	local s = secs % 60
	if m >= 60 then
		local h = math.floor( m / 60 )
		m = m % 60
		return string.format( "%d:%02d:%02d", h, m, s )
	end
	return string.format( "%d:%02d", m, s )
end

local function remainColor( frac )
	-- frac 1 = just started (red), frac 0 = ready (green)
	frac = math.max( 0, math.min( 1, frac ) )
	return sm.color.new( frac, 1.0 - frac, 0.08, 1.0 )
end

local function destroyGrowFx( self )
	if self.cl and self.cl.rfsGrowFx then
		pcall( function()
			if sm.exists( self.cl.rfsGrowFx ) then
				self.cl.rfsGrowFx:stop()
				self.cl.rfsGrowFx:destroy()
			end
		end )
		self.cl.rfsGrowFx = nil
		self.cl.rfsGrowFxName = nil
		self.cl.rfsGrowFxVer = nil
	end
end

-- World position slightly above the harvestable (AABB top, else origin + up).
local function overlayWorldPos( harvestable, grown )
	local pos = harvestable:getPosition()
	local up = WORLD_UP
	pcall( function()
		local rot = harvestable:getRotation()
		if rot then
			local localUp = rot * WORLD_UP
			if localUp:length2() > 0.01 then
				up = localUp:normalize()
			end
		end
	end )

	local minAabb, maxAabb
	local okAabb = pcall( function()
		minAabb, maxAabb = harvestable:getAabb()
	end )
	if okAabb and minAabb and maxAabb and minAabb.z and maxAabb.z then
		local x = ( minAabb.x + maxAabb.x ) * 0.5
		local y = ( minAabb.y + maxAabb.y ) * 0.5
		return sm.vec3.new( x, y, maxAabb.z ) + up * OVERLAY_AABB_PAD
	end

	local height = 1.05 + math.max( 0, math.min( 1, grown or 0 ) ) * 0.75
	return pos + up * height
end

-- Billboard: map DebugText local +Y onto -cameraDir (screen-parallel), then
-- roll so local +Z matches camera up. setRotation only works unhosted.
local function overlayBillboardQuat( worldPos )
	local camDir = sm.camera.getDirection()
	local face = -camDir
	if face:length2() < 1e-8 then
		local toCam = sm.camera.getPosition() - worldPos
		if toCam:length2() < 1e-8 then
			return sm.quat.identity()
		end
		face = toCam:normalize()
	else
		face = face:normalize()
	end

	local up = sm.camera.getUp()
	if not up or up:length2() < 1e-8 then
		up = WORLD_UP
	end
	local upOnPlane = up - face * face:dot( up )
	if upOnPlane:length2() > 1e-6 then
		up = upOnPlane:normalize()
	end

	local rot = sm.vec3.getRotation( TEXT_FACE, face )
	local zNow = rot * WORLD_UP
	if zNow:length2() > 1e-8 and up:length2() > 1e-8 then
		local okRoll, roll = pcall( sm.vec3.getRotation, zNow:normalize(), up )
		if okRoll and roll then
			rot = roll * rot
		end
	end
	return rot
end

local function ensureGrowFx( self )
	local fx = self.cl.rfsGrowFx
	if fx then
		local usable = false
		pcall( function()
			usable = sm.exists( fx ) and ( self.cl.rfsGrowFxVer == OVERLAY_FX_VER ) and ( not fx:hasHost() )
		end )
		if usable then
			return fx
		end
		destroyGrowFx( self )
	end

	for _, name in ipairs( OVERLAY_EFFECTS ) do
		local ok, created = pcall( sm.effect.createEffect, name )
		if ok and created then
			self.cl.rfsGrowFx = created
			self.cl.rfsGrowFxName = name
			self.cl.rfsGrowFxVer = OVERLAY_FX_VER
			pcall( function()
				local world = self.harvestable:getWorld()
				if world then
					created:setWorld( world )
				end
				created:setParameter( "anchor", "CENTER" )
				created:start()
			end )
			return created
		end
	end
	return nil
end

function RfsFarming.cl_plantOverlayUpdate( self, dt )
	if not _G.g_rfsGrowthOverlay then
		destroyGrowFx( self )
		return
	end
	if not self.harvestable or not sm.exists( self.harvestable ) then
		destroyGrowFx( self )
		return
	end

	self.cl = self.cl or {}
	local serverTick = sm.game.getServerTick()
	local days = ( self.data and self.data.daysToGrow ) or 0.875
	local growTickTime = DAYCYCLE_TIME_TICKS * days
	-- Match GrowingHarvestable.client_onUpdate fertilizer visual speed (*20)
	local fertilizeTicks = ( self.cl.fertilizeTick and self.cl.growStartTick )
		and ( serverTick - math.max( self.cl.fertilizeTick, self.cl.growStartTick ) ) or 0
	local growTicks = self.cl.growStartTick
		and ( serverTick - self.cl.growStartTick + fertilizeTicks * 20 ) or 0
	local remain = math.max( 0, growTickTime - growTicks )
	local frac = growTickTime > 0 and ( remain / growTickTime ) or 0
	local grown = 1.0 - frac
	local label = ( remain <= 0 ) and "READY" or formatRemain( remain )
	local color = remainColor( frac )

	local fx = ensureGrowFx( self )
	if not fx then
		return
	end

	local worldPos = overlayWorldPos( self.harvestable, grown )
	pcall( function()
		fx:setParameter( "TextContent", label )
		fx:setParameter( "Color", color )
		fx:setPosition( worldPos )
		fx:setRotation( overlayBillboardQuat( worldPos ) )
		if not fx:isPlaying() then
			fx:start()
		end
	end )
end

function RfsFarming.ensureGrowHooks()
	if type( GrowingHarvestable ) ~= "table" then
		pcall( function()
			dofile( "$SURVIVAL_DATA/Scripts/game/harvestable/GrowingHarvestable.lua" )
		end )
	end
	if type( GrowingHarvestable ) ~= "table" then
		return false
	end
	if GrowingHarvestable._rfsFarmHooked and GrowingHarvestable.client_onUpdate == RfsFarming._ghClientUpdate then
		if type( GrowingHarvestable.sv_e_rfsAdvanceGrowth ) ~= "function" then
			GrowingHarvestable.sv_e_rfsAdvanceGrowth = function( self, params )
				local ticks = tonumber( params and params.ticks ) or 0
				if ticks <= 0 or not self.sv or not self.sv.saved then
					return
				end
				if self.sv.saved.growStartTick then
					self.sv.saved.growStartTick = self.sv.saved.growStartTick - ticks
				end
				if self.sv.saved.waterTick then
					self.sv.saved.waterTick = self.sv.saved.waterTick - ticks
				end
				pcall( function()
					self:sv_saveAndSync()
				end )
			end
		end
		return true
	end

	RfsFarming._ghOrigClientUpdate = GrowingHarvestable.client_onUpdate
	RfsFarming._ghOrigClientDestroy = GrowingHarvestable.client_onDestroy

	function RfsFarming._ghClientUpdate( self, dt )
		local orig = RfsFarming._ghOrigClientUpdate
		if orig then
			orig( self, dt )
		end
		RfsFarming.cl_plantOverlayUpdate( self, dt )
	end

	GrowingHarvestable.client_onUpdate = RfsFarming._ghClientUpdate
	GrowingHarvestable.client_onDestroy = function( self )
		destroyGrowFx( self )
		local orig = RfsFarming._ghOrigClientDestroy
		if orig then
			orig( self )
		end
	end
	GrowingHarvestable._rfsFarmHooked = true
	function GrowingHarvestable.sv_e_rfsAdvanceGrowth( self, params )
		local ticks = tonumber( params and params.ticks ) or 0
		if ticks <= 0 or not self.sv or not self.sv.saved then
			return
		end
		if self.sv.saved.growStartTick then
			self.sv.saved.growStartTick = self.sv.saved.growStartTick - ticks
		end
		if self.sv.saved.waterTick then
			self.sv.saved.waterTick = self.sv.saved.waterTick - ticks
		end
		pcall( function()
			self:sv_saveAndSync()
		end )
		pcall( function()
			if self.server_onReceiveUpdate then
				self:server_onReceiveUpdate()
			end
		end )
	end
	print( "[RFS] Farming overlay hooked GrowingHarvestable" )
	return true
end

function RfsFarming.ensureHooks()
	pcall( function() RfsFarming.ensureGrowHooks() end )
	pcall( function() RfsFarming.ensureSoilBagHooks() end )
	pcall( function() RfsFarming.ensureCornHooks() end )
	pcall( function() RfsFarming.ensureBotFarmHooks() end )
	if not SEED_LABELS then
		pcall( function() rebuildSeedIndex() end )
	end
end

---------------------------------------------------------------------------
-- Corn stacks (Custom Game shapeset override pattern):
-- rfs_overrides.shapeset is listed FIRST in shapesets.shapedb and adds
-- itemStack on Survival corn uuid (same idea as Fant overrides.shapeset).
-- WARNING: Scrap Overdrive B&P redefines corn WITHOUT itemStack and loads after
-- the Custom Game, which strips Force Build stacks. Keep itemStack on the last
-- corn override (Overdrive patch and/or companion B&P RfsCornItemStack).
-- Engine Force Build then places the hotbar stack and sets shape.stackedAmount.
-- Woc wrap reads stackedAmount (vanilla milk ratio 5:1).
---------------------------------------------------------------------------

pcall( function() dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" ) end )
pcall( function() dofile( "$SURVIVAL_DATA/Scripts/game/survival_loot.lua" ) end )
pcall( function() dofile( "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua" ) end )

local RFS_CORN_PER_MILK = 5 -- match Survival WocUnit CornPerMilk

function RfsFarming._wocServerOnUnitUpdate( self, dt )
	if not sm.exists( self.unit ) then
		return
	end

	if self.currentState then
		self.currentState:onUnitUpdate( dt )
	end

	if self.unit.character:isTumbling() then
		return
	end

	local targetCorn, cornInRange = FindNearbyEdible( self.unit.character, obj_resource_corn, 6.0, 1.75 )

	local prevState = self.currentState
	local done, result = self.currentState:isDone()
	local abortState = (
		( self.fleeFrom ) or
		( ( self.currentState == self.pathingState or self.currentState == self.roamState ) and cornInRange )
	)

	if ( done or abortState ) then
		if self.fleeFrom then
			self:sv_flee( self.fleeFrom )
			prevState = self.currentState
			self.fleeFrom = nil
		elseif self.currentState == self.fleeState or self.currentState == self.eatEventState then
			self.currentState = self.idleState
		elseif targetCorn then
			if cornInRange then
				local eatFacingDirection = ( targetCorn.worldPosition - self.unit.character.worldPosition ):safeNormalize( self.currentState:getFacingDirection() )
				local facingDirection = self.currentState:getFacingDirection()
				local facingXY = sm.vec3.new( facingDirection.x, facingDirection.y, 0 ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
				local eatFacingXY = sm.vec3.new( eatFacingDirection.x, eatFacingDirection.y, 0 ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
				if self.currentState == self.turnState or facingXY:dot( eatFacingXY ) > math.cos( math.rad( 10 ) ) then
					self.currentState = self.eatEventState
					-- itemStack Force Build stamps qty on stackedAmount.
					local qty = targetCorn.stackedAmount
					if type( qty ) ~= "number" or qty < 1 then
						qty = 1
					else
						qty = math.floor( qty )
					end
					self.saved.stats.cornEaten = self.saved.stats.cornEaten + qty
					self.saved.deathTickTimestamp = sm.game.getCurrentTick() + DaysInTicks( 30 )
					if not self.saved.isCattle then
						local x = math.floor( self.saved.tetherPoint.x / CELL_SIZE )
						local y = math.floor( self.saved.tetherPoint.y / CELL_SIZE )
						local worldId = self.unit:getCharacter():getWorld():getId()
						UntrackUnitRespawn( { x = x, y = y, worldId = worldId }, "WOC", self.unit )
					end
					self.saved.tetherPoint = self.unit.character.worldPosition
					self.saved.isCattle = true
					while self.saved.stats.cornEaten >= RFS_CORN_PER_MILK do
						self.saved.stats.cornEaten = self.saved.stats.cornEaten - RFS_CORN_PER_MILK
						self.saved.stats.hp = self.saved.stats.maxhp
						if SurvivalGame then
							local loot = SelectLoot( "lootsource_woc_milk" )
							SpawnLoot( self.unit, loot )
						end
					end
					targetCorn:destroyShape()
					self.storage:save( self.saved )
				else
					self.turnState.desiredPosition = self.unit.character.worldPosition
					self.turnState.desiredDirection = eatFacingDirection
					self.currentState = self.turnState
				end
			else
				self.pathingState:sv_setDestination( targetCorn.worldPosition )
				self.currentState = self.pathingState
			end
		elseif self.currentState == self.turnState then
			self.currentState = self.idleState
		elseif self.roamTimer:done() and not ( self.currentState == self.idleState and result == "started" ) then
			self.roamTimer:start( math.random( 40 * 10, 40 * 25 ) )
			self.currentState = self.roamState
		elseif not ( self.currentState == self.roamState and result == "roaming" ) then
			self.currentState = self.idleState
		end
	end

	if prevState ~= self.currentState then
		prevState:stop()
		self.currentState:start()
		if DEBUG_AI_STATES then
			print( self.currentState.debugName )
		end
	end
end

function RfsFarming.ensureWocCornHooks()
	if type( WocUnit ) ~= "table" then
		pcall( function()
			dofile( "$SURVIVAL_DATA/Scripts/game/units/WocUnit.lua" )
		end )
	end
	if type( WocUnit ) ~= "table" then
		return false
	end
	if WocUnit._rfsCornHooked and WocUnit.server_onUnitUpdate == RfsFarming._wocServerOnUnitUpdate then
		return true
	end
	RfsFarming._wocOrigOnUnitUpdate = WocUnit.server_onUnitUpdate
	WocUnit.server_onUnitUpdate = RfsFarming._wocServerOnUnitUpdate
	WocUnit._rfsCornHooked = true
	print( "[RFS] WocUnit corn stack-eat hooked (stackedAmount, 5:1 milk)" )
	return true
end

function RfsFarming.ensureCornHooks()
	-- Place path: rfs_overrides.shapeset itemStack (listed first in shapedb). No Eat wrap.
	RfsFarming.ensureWocCornHooks()
end

function RfsFarming.cl_applyState( data )
	local cfg = RfsFarming.get()
	if type( data ) == "table" then
		if data.alwaysWatered ~= nil then
			cfg.alwaysWatered = data.alwaysWatered and true or false
		end
		if data.dirtOnBlocks ~= nil then
			cfg.dirtOnBlocks = data.dirtOnBlocks and true or false
		end
		if data.fastPlace ~= nil then
			cfg.fastPlace = data.fastPlace and true or false
		end
		if data.fastPickup ~= nil then
			cfg.fastPickup = data.fastPickup and true or false
		end
	end
	RfsFarming.cl_applyGlobals( cfg )
	RfsFarming.ensureHooks()
end
