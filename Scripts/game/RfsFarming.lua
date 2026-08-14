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

local SOIL_UUID = tostring( hvs_soil )

-- Water every ~2.5s while Always Watered is on (WaterRetention is ~1.5 days).
local WATER_INTERVAL_TICKS = 100
-- Unhosted text (setRotation is ignored on hosted effects). Prefer RfsGrowText
-- (InWorldText / VS_CLIP_SPACE nametag-style) then vanilla DebugText.
local OVERLAY_EFFECTS = { "RfsGrowText", "DebugText" }
local TEXT_FACE = sm.vec3.new( 0, 1, 0 ) -- DebugText / nametag default facing
local WORLD_UP = sm.vec3.new( 0, 0, 1 )
local OVERLAY_AABB_PAD = 0.32
local OVERLAY_FX_VER = 2

-- Contact mask for soil-on-blocks: omit staticBody so the foundation itself is allowed.
local BLOCK_SOIL_MASK = bit.bor(
	sm.physics.filter.dynamicBody,
	sm.physics.filter.waterArea,
	sm.physics.filter.terrainAsset,
	sm.physics.filter.harvestable,
	sm.physics.filter.voxelTerrain
)

local defaults = {
	alwaysWatered = false,
	dirtOnBlocks = false,
}

---------------------------------------------------------------------------
-- Persistence (world sm.storage) — alwaysWatered / dirtOnBlocks only.
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
	}
end

function RfsFarming.cl_applyGlobals( cfg )
	cfg = cfg or RfsFarming.get()
	_G.g_rfsAlwaysWatered = cfg.alwaysWatered and true or false
	_G.g_rfsDirtOnBlocks = cfg.dirtOnBlocks and true or false
	-- g_rfsGrowthOverlay is per-player; set via RfsFarming.cl_setLocalGrowthOverlay.
end

function RfsFarming.dirtOnBlocksActive()
	return ( _G.g_rfsDirtOnBlocks == true ) and RfsSettings.cheatsEnabled()
end

---------------------------------------------------------------------------
-- Harvestable helpers
---------------------------------------------------------------------------

function RfsFarming.isGrowingUuid( uuid )
	return GROWING_UUID[tostring( uuid )] == true
end

function RfsFarming.isSoilUuid( uuid )
	return tostring( uuid ) == SOIL_UUID
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

---------------------------------------------------------------------------
-- Dirt on blocks: extend SoilBag to accept body/lift raycasts (cheat-gated)
-- Vanilla SoilBag.constructionRayCast only accepts terrainSurface.
---------------------------------------------------------------------------

local function snapWorldSoilPos( pointWorld, normalWorld )
	local ratio = sm.construction.constants.subdivideRatio
	-- Sit just above the hit face (soil is a flat harvestable, not a block).
	local worldPos = pointWorld + normalWorld * ( ratio * 0.5 )
	-- Snap XY to construction grid for tidy plots; keep Z from surface.
	worldPos = sm.vec3.new(
		math.floor( worldPos.x / ratio + 0.5 ) * ratio,
		math.floor( worldPos.y / ratio + 0.5 ) * ratio,
		worldPos.z
	)
	return worldPos
end

function RfsFarming._soilConstructionRayCast( self )
	local orig = RfsFarming._soilOrigConstructionRayCast
	if orig then
		local valid, worldPos, worldNormal = orig( self )
		if valid then
			self._rfsSoilFromBody = false
			return valid, worldPos, worldNormal
		end
	end

	if not RfsFarming.dirtOnBlocksActive() then
		return false
	end

	local world = sm.localPlayer.getWorld()
	if world and ( world.clientPublicData and not world.clientPublicData.allowSoilPlacement ) or not world.clientPublicData then
		return false
	end

	local valid, result = sm.localPlayer.getLatestRaycast()
	if not valid or not result then
		return false
	end
	if result.type ~= "body" and result.type ~= "lift" then
		return false
	end

	local normal = result.normalWorld
	if not normal then
		return false
	end
	-- Same steepness gate as vanilla equipped update (cos ~15°).
	if normal.z < 0.96592583 then
		-- Still return position so UI can show TOO_STEEP; mark for contact path.
		local worldPos = snapWorldSoilPos( result.pointWorld, normal )
		self._rfsSoilFromBody = true
		return true, worldPos, normal
	end

	local worldPos = snapWorldSoilPos( result.pointWorld, normal )
	self._rfsSoilFromBody = true
	return true, worldPos, normal
end

function RfsFarming._soilClientEquippedUpdate( self, primaryState, secondaryState, forceBuildActive )
	if not self.tool:isLocal() then
		return false, false
	end

	if forceBuildActive then
		if self.effect and self.effect:isPlaying() then
			self.effect:stop()
		end
		return false, false
	end

	local valid, worldPos, worldNormal = self:constructionRayCast()
	if not valid then
		if self.effect then
			self.effect:stop()
		end
		return false, false
	end

	self.effect:setPosition( worldPos )
	self.effect:setRotation( sm.quat.angleAxis( math.pi * 0.5, sm.vec3.new( 1, 0, 0 ) ) )

	local fromBody = self._rfsSoilFromBody == true
	local blocked = false
	if worldNormal.z < 0.96592583 then
		sm.gui.setInteractionText( "#{INFO_TOO_STEEP}" )
		self.effect:setParameter( "visualizationColor", "Lift Invalid" )
	else
		-- On bodies, omit staticBody from the mask so the platform itself is not a hard reject.
		if fromBody then
			blocked = sm.physics.sphereHasContact( worldPos, 0.28, nil, nil, BLOCK_SOIL_MASK )
		else
			local mask = bit.bor(
				sm.physics.filter.dynamicBody,
				sm.physics.filter.waterArea,
				sm.physics.filter.terrainAsset,
				sm.physics.filter.harvestable,
				sm.physics.filter.staticBody,
				sm.physics.filter.voxelTerrain
			)
			blocked = sm.physics.sphereHasContact( worldPos, 0.375, nil, nil, mask )
		end

		if blocked then
			self.effect:setParameter( "visualizationColor", "Lift Invalid" )
		else
			local keyBindingText = sm.gui.getKeyBinding( "Create", true )
			sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_PUT_SOIL}" )
			self.effect:setParameter( "visualizationColor", "Lift Valid" )

			if primaryState == sm.tool.interactState.start then
				self.network:sendToServer( "sv_n_putSoil", {
					pos = worldPos,
					slot = sm.localPlayer.getSelectedHotbarSlot()
				} )
				self:putSoil()
			end
		end
	end

	local keyBindingText = sm.gui.getKeyBinding( "ForceBuild", true )
	sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_FORCE_BUILD}" )

	if not self.effect:isPlaying() then
		self.effect:start()
	end
	return true, false
end

function RfsFarming.ensureSoilBagHooks()
	if type( SoilBag ) ~= "table" then
		pcall( function()
			dofile( "$SURVIVAL_DATA/Scripts/game/tools/SoilBag.lua" )
		end )
	end
	if type( SoilBag ) ~= "table" then
		return false
	end
	if SoilBag._rfsFarmHooked
		and SoilBag.constructionRayCast == RfsFarming._soilConstructionRayCast
		and SoilBag.client_onEquippedUpdate == RfsFarming._soilClientEquippedUpdate then
		return true
	end

	if not RfsFarming._soilOrigConstructionRayCast then
		RfsFarming._soilOrigConstructionRayCast = SoilBag.constructionRayCast
	end
	if not RfsFarming._soilOrigEquippedUpdate then
		RfsFarming._soilOrigEquippedUpdate = SoilBag.client_onEquippedUpdate
	end

	SoilBag.constructionRayCast = RfsFarming._soilConstructionRayCast
	SoilBag.client_onEquippedUpdate = RfsFarming._soilClientEquippedUpdate
	SoilBag._rfsFarmHooked = true
	print( "[RFS] Farming SoilBag hooked (dirt on blocks)" )
	return true
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
	print( "[RFS] Farming overlay hooked GrowingHarvestable" )
	return true
end

function RfsFarming.ensureHooks()
	RfsFarming.ensureGrowHooks()
	RfsFarming.ensureSoilBagHooks()
	RfsFarming.ensureCornHooks()
end

---------------------------------------------------------------------------
-- Corn stack (inventory 20) + force-place full stack + Woc eats stack
-- Vanilla: stackSize 10, CornPerMilk = 5 (5 corn → 1 milk).
-- RFS: shapeset override stackSize 20; force-place stamps qty on RfsCorn;
-- Woc consumes full shape qty and milk uses vanilla 5:1.
---------------------------------------------------------------------------

pcall( function() dofile( "$CONTENT_DATA/Scripts/game/RfsCorn.lua" ) end )
pcall( function() dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" ) end )
pcall( function() dofile( "$SURVIVAL_DATA/Scripts/game/survival_loot.lua" ) end )
pcall( function() dofile( "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua" ) end )

local RFS_CORN_UUID = obj_resource_corn or sm.uuid.new( "fe8bfeba-850b-4827-9785-10e2468c9c23" )
local RFS_CORN_PER_MILK = 5 -- match WocUnit.lua CornPerMilk

local function rfsCornSlotQty( container, slot, uuid )
	local qty = 0
	pcall( function()
		local item = container:getItem( slot )
		if item and item.uuid == uuid and type( item.quantity ) == "number" then
			qty = item.quantity
		end
	end )
	if qty < 1 then
		pcall( function()
			local item = sm.container.getItem( container, slot )
			if item and item.uuid == uuid and type( item.quantity ) == "number" then
				qty = item.quantity
			end
		end )
	end
	return math.max( 0, math.floor( qty ) )
end

function RfsFarming._eatClientEquippedUpdate( self, primaryState, secondaryState, forceBuildActive )
	-- Corn force-build: place entire hotbar stack as one shape (qty on RfsCorn).
	if forceBuildActive and not self.eating then
		local activeItem = nil
		pcall( function() activeItem = sm.localPlayer.getActiveItem() end )
		if activeItem == RFS_CORN_UUID then
			if primaryState == sm.tool.interactState.start then
				local valid, result = sm.localPlayer.getLatestRaycast()
				if valid and result and result.pointWorld then
					local normal = result.normalWorld or sm.vec3.new( 0, 0, 1 )
					local pos = result.pointWorld + normal * 0.35
					self.network:sendToServer( "sv_n_rfsPlaceCornStack", {
						pos = pos,
						slot = sm.localPlayer.getSelectedHotbarSlot()
					} )
				end
			end
			UpdateForceBuildText()
			return true, false
		end
		-- Other foods: keep vanilla force-build (engine places 1).
		return false, false
	end

	local orig = RfsFarming._eatOrigEquippedUpdate
	if orig then
		return orig( self, primaryState, secondaryState, forceBuildActive )
	end
	return true, false
end

function RfsFarming._eatSvPlaceCornStack( self, params )
	local player = self.tool:getOwner()
	if not player or type( params ) ~= "table" or not params.pos then
		return
	end
	local inv = player:getInventory()
	if not inv then
		return
	end
	local slot = params.slot or 0
	local qty = rfsCornSlotQty( inv, slot, RFS_CORN_UUID )
	if qty < 1 then
		return
	end
	local spent = false
	pcall( function()
		spent = sm.container.spendFromSlot( inv, slot, RFS_CORN_UUID, qty, true )
	end )
	if not spent then
		pcall( function()
			spent = sm.container.spend( inv, RFS_CORN_UUID, qty, true )
		end )
	end
	if not spent then
		return
	end
	_G.g_rfsPendingCornQty = qty
	local shape = nil
	local ok, err = pcall( function()
		shape = sm.shape.createPart( RFS_CORN_UUID, params.pos, sm.quat.identity(), true, true )
	end )
	if not ok then
		_G.g_rfsPendingCornQty = nil
		pcall( function() sm.container.collect( inv, RFS_CORN_UUID, qty, true ) end )
		print( "[RFS] corn force-place failed: " .. tostring( err ) )
		return
	end
	-- Fallback registry if shapeset scripted override did not attach RfsCorn.
	if shape and sm.exists( shape ) then
		_G.g_rfsCornQtyById = _G.g_rfsCornQtyById or {}
		local id = nil
		pcall( function() id = shape.id end )
		if id ~= nil then
			_G.g_rfsCornQtyById[id] = qty
		end
	end
	-- If RfsCorn.server_onCreate did not consume pending, clear so the next place is clean.
	if _G.g_rfsPendingCornQty == qty then
		_G.g_rfsPendingCornQty = nil
	end
end

function RfsFarming.ensureEatCornHooks()
	if type( Eat ) ~= "table" then
		pcall( function()
			dofile( "$SURVIVAL_DATA/Scripts/game/tools/Eat.lua" )
		end )
	end
	if type( Eat ) ~= "table" then
		return false
	end
	if Eat._rfsCornHooked and Eat.client_onEquippedUpdate == RfsFarming._eatClientEquippedUpdate then
		Eat.sv_n_rfsPlaceCornStack = RfsFarming._eatSvPlaceCornStack
		return true
	end
	if not RfsFarming._eatOrigEquippedUpdate then
		RfsFarming._eatOrigEquippedUpdate = Eat.client_onEquippedUpdate
	end
	Eat.client_onEquippedUpdate = RfsFarming._eatClientEquippedUpdate
	Eat.sv_n_rfsPlaceCornStack = RfsFarming._eatSvPlaceCornStack
	Eat._rfsCornHooked = true
	print( "[RFS] Eat corn force-place stack hooked" )
	return true
end

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
					-- RFS: consume full stack qty on the corn shape (vanilla was always +1).
					local qty = 1
					pcall( function() qty = RfsCorn.consumeShapeQty( targetCorn ) end )
					qty = math.max( 1, math.floor( qty or 1 ) )
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
					-- Spit milk immediately for this meal (vanilla ratio 5 corn = 1 milk).
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
	print( "[RFS] WocUnit corn stack-eat hooked (5 corn = 1 milk)" )
	return true
end

function RfsFarming.ensureCornHooks()
	RfsFarming.ensureEatCornHooks()
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
	end
	RfsFarming.cl_applyGlobals( cfg )
	RfsFarming.ensureHooks()
end
