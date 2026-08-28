-- Player.lua - Recipe Framework Survival
-- Author: DemonsDen126
dofile( "$SURVIVAL_DATA/Scripts/game/SurvivalPlayer.lua" )
dofile( "$CONTENT_DATA/Scripts/game/RfsHud.lua" )
dofile( "$CONTENT_DATA/Scripts/game/RfsMiniMap.lua" )
dofile( "$CONTENT_DATA/Scripts/game/RfsInventory.lua" )
dofile( "$CONTENT_DATA/Scripts/game/RfsGameMode.lua" )
dofile( "$CONTENT_DATA/Scripts/game/RfsFarming.lua" )
dofile( "$CONTENT_DATA/Scripts/game/RfsCarry.lua" )
pcall( function() dofile( "$CONTENT_DATA/Scripts/game/RfsGuiPrefs.lua" ) end )
pcall( function() dofile( "$CONTENT_DATA/Scripts/game/RfsBlockOverlay.lua" ) end )
pcall( function() dofile( "$CONTENT_DATA/Scripts/game/RfsHealthBars.lua" ) end )

Player = class( SurvivalPlayer )

local RFS_MAP_LOCK_UUID = sm.uuid.new( "9a1528a6-acd2-44db-8050-b2f493362191" )
local RFS_MAP_HEIGHT = 1200
local RFS_MAP_DEFAULT_ZOOM = 200
-- ~0.75s at 40 tick/s - blocks open->immediate toggle-close on double chat fire
local RFS_MAP_OPEN_DEBOUNCE_TICKS = 30
local RFS_MAP_SHAPE_GRACE_TICKS = 40
-- Chemical Regeneration Station (respawn bed must not seat into the tube).
local RFS_CHEM_STATION_UUID = "6f391c5b-82d4-4e17-9a60-c1d5e8f2a4b7"

local function rfsIsChemStationShape( shape )
	if not shape or not sm.exists( shape ) then
		return false
	end
	return string.lower( tostring( shape.uuid ) ) == RFS_CHEM_STATION_UUID
end

local function rfsSvReleaseChemRespawn( self, shape )
	local player = self.player
	local char = nil
	pcall( function()
		char = player:getCharacter()
	end )
	local pos = nil
	pcall( function()
		if type( RfsChemStation ) == "table" and RfsChemStation.exitPosForShape then
			pos = RfsChemStation.exitPosForShape( shape )
		end
	end )
	if char and sm.exists( char ) then
		pcall( function()
			local ia = shape and shape.interactable
			if ia and sm.exists( ia ) and ia.getSeatCharacter and ia:getSeatCharacter() == char then
				ia:setSeatCharacter( char )
			end
		end )
		pcall( function()
			char:setLockingInteractable( nil )
		end )
		pcall( function()
			char:setImmovable( false )
		end )
		if pos then
			pcall( function()
				char:setWorldPosition( pos )
			end )
		end
		pcall( function()
			char:setVelocity( sm.vec3.zero() )
		end )
		pcall( function()
			char:setLinearVelocity( sm.vec3.zero() )
		end )
	end
	pcall( function()
		local ia = shape and shape.interactable
		if ia and sm.exists( ia ) then
			sm.event.sendToInteractable( ia, "sv_e_rfsRespawnRelease", { player = player } )
		end
	end )
	pcall( function()
		self.network:sendToClient( player, "cl_rfs_releaseFromPod", {
			x = pos and pos.x,
			y = pos and pos.y,
			z = pos and pos.z,
		} )
	end )
end

g_rfs_mapFocus = g_rfs_mapFocus or nil
g_rfs_mapZoom = g_rfs_mapZoom or RFS_MAP_DEFAULT_ZOOM
g_rfs_mapHeight = g_rfs_mapHeight or RFS_MAP_HEIGHT
g_rfs_mapLockReady = g_rfs_mapLockReady or false

function Player.server_onCreate( self )
	SurvivalPlayer.server_onCreate( self )
	self.sv = self.sv or {}
	self.sv.rfsFly = false
	self.sv.rfsInRegen = false
	self.sv.rfsGameModePendingRestore = nil
	self.sv.rfsMapOpen = false
	self.sv.rfsMapShape = nil
	self.sv.rfsMapOpenTick = 0
	self.sv.rfsMapAwaitingClient = false
	self.sv.rfsMapUsingPart = false
	self.sv.rfsGrowthOverlay = RfsFarming.getPlayerGrowthOverlay( self.player )
	-- Apply saved world inventory size (after Survival creates the container).
	-- Late joiners also get this via Game.server_onPlayerJoined.
	pcall( function()
		local id = RfsInventory.getSavedOptionId()
		RfsInventory.applyGameDefault( RecipeFrameworkSurvival )
		RfsInventory.applyToPlayer( self.player, id )
	end )
	-- Sync per-player Growth Time preference to this client.
	self.network:sendToClient( self.player, "cl_rfs_growthOverlayState", {
		enabled = self.sv.rfsGrowthOverlay and true or false,
	} )
	pcall( function()
		if type( RfsGuiPrefs ) == "table" then
			local prefs = RfsGuiPrefs.load( self.player )
			self.sv.rfsGuiPrefs = prefs
			self.network:sendToClient( self.player, "cl_rfs_guiPrefState", prefs )
		end
	end )
	pcall( function()
		if type( RfsPaintPalette ) == "table" and RfsPaintPalette.loadPersisted then
			local paint = RfsPaintPalette.loadPersisted( self.player )
			self.sv.rfsPaintPrefs = paint
			self.network:sendToClient( self.player, "cl_rfs_paintPrefsState", paint )
		end
	end )
	pcall( function()
		RfsCarry.resetPlaceLock()
		RfsCarry.ensureHooks()
	end )
	pcall( function()
		local id = self.player.id
		if id == nil then
			id = self.player:getId()
		end
		if id ~= nil and _G.g_rfsRegenByPlayer then
			_G.g_rfsRegenByPlayer[tostring( id )] = nil
		end
		self.sv.rfsInRegen = false
		local char = self.player:getCharacter()
		if char and sm.exists( char ) then
			local ia = char:getLockingInteractable()
			if ia and sm.exists( ia ) and ia.shape then
				local uuid = string.lower( tostring( ia.shape.uuid ) )
				if uuid == "6f391c5b-82d4-4e17-9a60-c1d5e8f2a4b7" then
					local pos = nil
					pcall( function()
						if type( RfsChemStation ) == "table" and RfsChemStation.exitPosForShape then
							pos = RfsChemStation.exitPosForShape( ia.shape )
						end
					end )
					if pos then
						pcall( function()
							char:setWorldPosition( pos )
						end )
					end
					pcall( function()
						char:setVelocity( sm.vec3.zero() )
					end )
					pcall( function()
						char:setLinearVelocity( sm.vec3.zero() )
					end )
					pcall( function()
						if ia:getSeatCharacter() == char then
							ia:setSeatCharacter( char )
						end
					end )
					char:setLockingInteractable( nil )
					char:setImmovable( false )
					self.network:sendToClient( self.player, "cl_rfs_releaseFromPod", {
						x = pos and pos.x,
						y = pos and pos.y,
						z = pos and pos.z,
					} )
				end
			end
		end
	end )
end

-- Respawn at Chemical Station: Survival seats you in the tube (stuck). Warp to exit pad instead.
function Player.sv_e_onSpawnCharacter( self )
	local chemShape = nil
	pcall( function()
		if self.sv and self.sv.spawnparams and self.sv.spawnparams.respawn and g_respawnManager then
			local bed = g_respawnManager:sv_getPlayerBed( self.player )
			if bed and rfsIsChemStationShape( bed.shape ) then
				chemShape = bed.shape
			end
		end
	end )
	SurvivalPlayer.sv_e_onSpawnCharacter( self )
	if chemShape then
		rfsSvReleaseChemRespawn( self, chemShape )
	end
end

function Player.cl_seatCharacter( self, params )
	local shape = params and params.shape
	if rfsIsChemStationShape( shape ) then
		local pos = nil
		pcall( function()
			if type( RfsChemStation ) == "table" and RfsChemStation.exitPosForShape then
				pos = RfsChemStation.exitPosForShape( shape )
			end
		end )
		if type( RfsChemStation ) == "table" and RfsChemStation.cl_releasePlayerLocal then
			RfsChemStation.cl_releasePlayerLocal( shape.interactable, shape, pos )
		end
		return
	end
	SurvivalPlayer.cl_seatCharacter( self, params )
end

function Player.client_onCreate( self )
	SurvivalPlayer.client_onCreate( self )
	self.cl = self.cl or {}
	self.cl.rfsFly = false
	self.cl.rfsMapOpen = false
	self.cl.rfsMapFallback = false
	self.cl.rfsMapLockReady = false
	self.cl.rfsMapCamPos = nil
	self.cl.rfsMapHeight = RFS_MAP_HEIGHT
	self.cl.rfsMapZoom = RFS_MAP_DEFAULT_ZOOM
	self.cl.rfsGrowthOverlay = false
	self.cl.rfsGameModeSpectator = false
	if self.player == sm.localPlayer.getPlayer() then
		g_rfs_clientFly = false
		RfsFarming.cl_setLocalGrowthOverlay( false )
		RfsHud.ensure( self )
	end
	pcall( function()
		RfsCarry.resetPlaceLock()
		RfsCarry.ensureHooks()
	end )
	if self.player == sm.localPlayer.getPlayer() then
		pcall( function()
			local char = self.player:getCharacter()
			if char and sm.exists( char ) then
				local ia = char:getLockingInteractable()
				if ia and sm.exists( ia ) and ia.shape then
					local uuid = string.lower( tostring( ia.shape.uuid ) )
					if uuid == "6f391c5b-82d4-4e17-9a60-c1d5e8f2a4b7" then
						local pos = nil
						pcall( function()
							if type( RfsChemStation ) == "table" and RfsChemStation.exitPosForShape then
								pos = RfsChemStation.exitPosForShape( ia.shape )
							end
						end )
						if type( RfsChemStation ) == "table" and RfsChemStation.cl_releasePlayerLocal then
							RfsChemStation.cl_releasePlayerLocal( ia, ia.shape, pos )
						else
							char:setLockingInteractable( nil )
							char:setImmovable( false )
							if sm.camera.getCameraState() ~= sm.camera.state.default then
								sm.camera.setCameraState( sm.camera.state.default )
							end
						end
					end
				end
			end
		end )
	end
end

function Player.cl_rfs_releaseFromPod( self, params )
	if self.player ~= sm.localPlayer.getPlayer() then
		return
	end
	local pos = nil
	if type( params ) == "table" and type( params.x ) == "number" then
		pos = sm.vec3.new( params.x, params.y, params.z )
	end
	pcall( function()
		local char = self.player:getCharacter()
		if not char or not sm.exists( char ) then
			return
		end
		local ia = char:getLockingInteractable()
		if ia and sm.exists( ia ) and ia.shape then
			local uuid = string.lower( tostring( ia.shape.uuid ) )
			if uuid == "6f391c5b-82d4-4e17-9a60-c1d5e8f2a4b7" then
				if type( RfsChemStation ) == "table" and RfsChemStation.cl_releasePlayerLocal then
					RfsChemStation.cl_releasePlayerLocal( ia, ia.shape, pos )
				end
			end
		elseif pos and type( RfsChemStation ) == "table" and RfsChemStation.cl_releasePlayerLocal then
			RfsChemStation.cl_releasePlayerLocal( nil, nil, pos )
		end
	end )
end

function Player.sv_rfs_toggleGrowthOverlay( self )
	-- Growth Time HUD retired — force off.
	RfsFarming.setPlayerGrowthOverlay( self.player, false )
	self.sv = self.sv or {}
	self.sv.rfsGrowthOverlay = false
	self.network:sendToClient( self.player, "cl_rfs_growthOverlayState", {
		enabled = false,
		msg = "Growth Time HUD removed — use Farmers Tablet",
	} )
end

-- Legacy no-op (corn stacking is native itemStack now).
function Player.sv_rfs_placeCornStack( self, params )
end

function Player.cl_rfs_growthOverlayState( self, data )
	self.cl = self.cl or {}
	local enabled = false
	if type( data ) == "table" then
		enabled = data.enabled and true or false
	else
		enabled = data and true or false
	end
	self.cl.rfsGrowthOverlay = enabled
	if self.player == sm.localPlayer.getPlayer() then
		RfsFarming.cl_setLocalGrowthOverlay( enabled )
		-- Keep Game /menu GUI in sync when open (Game owns the GUI host).
		pcall( function()
			local game = _G.g_rfsGame
			if game and game.cl then
				game.cl.rfsGrowthOverlay = enabled
				if type( RfsMenuGui ) == "table" and game.cl.rfsMenuGui then
					RfsMenuGui.refresh( game )
				end
			end
		end )
		if type( data ) == "table" and data.msg then
			sm.gui.chatMessage( "[RFS] " .. tostring( data.msg ) )
		end
	end
end

function Player.sv_rfs_guiPref( self, params )
	if type( RfsGuiPrefs ) ~= "table" then
		return
	end
	self.sv = self.sv or {}
	local prefs = self.sv.rfsGuiPrefs or RfsGuiPrefs.load( self.player )
	prefs = RfsGuiPrefs.toggle( prefs, params and params.key )
	prefs = RfsGuiPrefs.save( self.player, prefs )
	self.sv.rfsGuiPrefs = prefs
	self.network:sendToClient( self.player, "cl_rfs_guiPrefState", prefs )
end

function Player.sv_rfs_paintPrefsSave( self, params )
	if type( RfsPaintPalette ) ~= "table" or not RfsPaintPalette.savePersisted then
		return
	end
	self.sv = self.sv or {}
	local data = RfsPaintPalette.savePersisted( self.player, params or {} )
	self.sv.rfsPaintPrefs = data
	self.network:sendToClient( self.player, "cl_rfs_paintPrefsState", data )
end

function Player.cl_rfs_paintPrefsState( self, data )
	if type( data ) ~= "table" then
		return
	end
	_G.g_rfsPaintPersist = data
	self.cl = self.cl or {}
	self.cl.rfsPaintPrefs = data
	pcall( function()
		if type( RfsPaintGui ) == "table" and RfsPaintGui.applyPersisted then
			local host = _G.g_rfsPaintToolLocal or _G.g_rfsGame
			RfsPaintGui.applyPersisted( host, data )
		end
	end )
end

function Player.cl_rfs_guiPrefState( self, data )
	if type( RfsGuiPrefs ) == "table" then
		data = RfsGuiPrefs.applyClient( data )
	end
	self.cl = self.cl or {}
	self.cl.rfsGuiPrefs = data
	if self.player == sm.localPlayer.getPlayer() then
		pcall( function()
			local game = _G.g_rfsGame
			if game and game.cl then
				game.cl.rfsGuiPrefs = data
				if type( RfsMenuGui ) == "table" and game.cl.rfsMenuGui then
					RfsMenuGui.refresh( game )
				end
			end
		end )
	end
end

function Player.sv_rfs_toggleFly( self )
	local character = self.player:getCharacter()
	if character == nil or not sm.exists( character ) then
		return
	end

	self.sv.rfsFly = not self.sv.rfsFly
	character:setSwimming( self.sv.rfsFly )
	character:setDiving( self.sv.rfsFly )

	if not self.sv.rfsFly then
		character.movementSpeedFraction = 1
		if character.publicData then
			character.publicData.waterMovementSpeedFraction = 1
		end
		self.network:sendToClient( self.player, "cl_rfs_setSpeed", 1 )
	end

	self.network:sendToClient( self.player, "cl_rfs_flyState", self.sv.rfsFly )
end

function Player.cl_rfs_flyState( self, enabled )
	self.cl = self.cl or {}
	self.cl.rfsFly = enabled and true or false
	if self.player == sm.localPlayer.getPlayer() then
		g_rfs_clientFly = self.cl.rfsFly
		sm.gui.chatMessage( "Fly Mode: " .. tostring( enabled ) )
	end
end

function Player.cl_rfs_setSpeed( self, speed )
	local character = self.player:getCharacter()
	if character ~= nil and sm.exists( character ) then
		character.movementSpeedFraction = speed
		if character.clientPublicData then
			character.clientPublicData.waterMovementSpeedFraction = speed
		end
	end
end

local function rfs_applyFlySpeed( character )
	local speed = character:isSprinting() and 20.0 or 3.5
	character.movementSpeedFraction = speed
	return speed
end

-- ========== /map (Nutt atlas when available, else top-down camera) ==========

function Player.sv_rfs_mapToggle( self )
	-- Client decides: Nutt World Map fullscreen atlas, or original lock camera.
	self.network:sendToClient( self.player, "cl_rfs_mapToggleTry" )
end

function Player.cl_rfs_mapToggleTry( self )
	if self.player ~= sm.localPlayer.getPlayer() then
		return
	end
	if self.cl and self.cl.rfsMapOpen then
		self.network:sendToServer( "sv_rfs_mapClose" )
		return
	end
	if type( RfsMiniMap ) == "table" then
		if RfsMiniMap.toggleBigMap() then
			print( "[RFS] /map toggle -> Nutt World Map atlas" )
			return
		end
		-- Nutt is the Map phase: wait for terrain/atlas instead of dropping to camera.
		if RfsMiniMap.nuttLoaded() then
			if RfsMiniMap.pending() then
				sm.gui.chatMessage( "[RFS] Map atlas still loading — try /map again in a moment." )
				print( "[RFS] /map deferred: Nutt hosted but atlas not ready" )
				return
			end
		end
	end
	self.network:sendToServer( "sv_rfs_mapToggleCamera" )
end

function Player.cl_rfs_nuttMapClose( self )
	if type( RfsMiniMap ) == "table" then
		RfsMiniMap.closeBigMap()
	end
end

function Player.sv_rfs_mapToggleCamera( self )
	print( "[RFS] /map toggle  open=" .. tostring( self.sv.rfsMapOpen ) )
	if self.sv.rfsMapOpen then
		local tick = sm.game.getCurrentTick()
		local openedAt = self.sv.rfsMapOpenTick or 0
		if ( tick - openedAt ) < RFS_MAP_OPEN_DEBOUNCE_TICKS then
			print( "[RFS] /map toggle ignored (debounce - just opened)" )
			self.network:sendToClient( self.player, "cl_rfs_mapMsg",
				"Map still opening - wait a moment, or use E/Esc / /mapclose to close" )
			return
		end
		self:sv_rfs_mapClose( "toggle" )
	else
		self:sv_rfs_mapOpen()
	end
end

function Player.sv_rfs_mapOpen( self )
	local character = self.player:getCharacter()
	if character == nil or not sm.exists( character ) then
		print( "[RFS] /map open failed: no character" )
		self.network:sendToClient( self.player, "cl_rfs_mapMsg", "Map failed: no character" )
		return
	end
	if character:isDowned() then
		print( "[RFS] /map open failed: downed" )
		self.network:sendToClient( self.player, "cl_rfs_mapMsg", "Map failed: character is downed" )
		return
	end

	if self.sv.rfsMapShape and sm.exists( self.sv.rfsMapShape ) then
		pcall( function()
			local ia = self.sv.rfsMapShape.interactable
			if ia then
				sm.event.sendToInteractable( ia, "sv_n_markClosing" )
			end
			self.sv.rfsMapShape:destroyShape( 0 )
		end )
		self.sv.rfsMapShape = nil
	end

	local worldPos = character.worldPosition
	-- Spawn below the player (keeps the lock body out of the way) - placed below the player
	local pos = worldPos - sm.vec3.new( 0, 0, 20 )
	local ok, shape = pcall( sm.shape.createPart, RFS_MAP_LOCK_UUID, pos, sm.quat.identity(), false, true )
	if not ok or not shape or not sm.exists( shape ) then
		print( "[RFS] /map createPart failed: " .. tostring( shape ) )
		self.network:sendToClient( self.player, "cl_rfs_mapMsg",
			"Map part spawn failed (" .. tostring( shape ) .. ") - using fallback camera" )
		self.sv.rfsMapOpen = true
		self.sv.rfsMapOpenTick = sm.game.getCurrentTick()
		self.sv.rfsMapAwaitingClient = false
		self.sv.rfsMapUsingPart = false
		self.network:sendToClient( self.player, "cl_rfs_mapFallbackOpen", {
			x = worldPos.x, y = worldPos.y, z = worldPos.z + 96
		} )
		return
	end

	local interactable = shape.interactable
	if not interactable then
		print( "[RFS] /map createPart ok but no interactable - destroying" )
		pcall( function() shape:destroyShape( 0 ) end )
		self.network:sendToClient( self.player, "cl_rfs_mapMsg",
			"Map failed: part has no interactable - using fallback camera" )
		self.sv.rfsMapOpen = true
		self.sv.rfsMapOpenTick = sm.game.getCurrentTick()
		self.sv.rfsMapAwaitingClient = false
		self.sv.rfsMapUsingPart = false
		self.network:sendToClient( self.player, "cl_rfs_mapFallbackOpen", {
			x = worldPos.x, y = worldPos.y, z = worldPos.z + 96
		} )
		return
	end

	self.sv.rfsMapShape = shape
	self.sv.rfsMapOpen = true
	self.sv.rfsMapOpenTick = sm.game.getCurrentTick()
	self.sv.rfsMapAwaitingClient = true
	self.sv.rfsMapUsingPart = true
	pcall( function() character:setImmovable( true ) end )

	-- Handshake step 1: tell client the part is spawned; client confirms before lock/camera bind
	self.network:sendToClient( self.player, "cl_rfs_mapAwaitLock", {
		x = worldPos.x,
		y = worldPos.y,
		height = RFS_MAP_HEIGHT,
		zoom = RFS_MAP_DEFAULT_ZOOM
	} )
	print( "[RFS] /map part spawned - awaiting client ready" )
	self.network:sendToClient( self.player, "cl_rfs_mapMsg", "Map: lock part spawned, syncing to client..." )
end

-- Client confirmed part/network path is ready -> now bind lock + camera (step 2)
function Player.sv_rfs_mapClientReady( self )
	if not self.sv.rfsMapOpen then
		print( "[RFS] /map clientReady ignored: map not open" )
		return
	end
	local shape = self.sv.rfsMapShape
	if not shape or not sm.exists( shape ) or not shape.interactable then
		print( "[RFS] /map clientReady: shape missing - fallback" )
		self.sv.rfsMapAwaitingClient = false
		self.sv.rfsMapUsingPart = false
		local character = self.player:getCharacter()
		local wp = character and character.worldPosition or sm.vec3.new( 0, 0, 0 )
		self.network:sendToClient( self.player, "cl_rfs_mapMsg", "Map: lock lost after spawn - fallback camera" )
		self.network:sendToClient( self.player, "cl_rfs_mapFallbackOpen", {
			x = wp.x, y = wp.y, z = wp.z + 96
		} )
		return
	end

	self.sv.rfsMapAwaitingClient = false
	local character = self.player:getCharacter()
	local wp = character and character.worldPosition or sm.vec3.new( 0, 0, 0 )
	sm.event.sendToInteractable( shape.interactable, "sv_n_setOwner", {
		player = self.player,
		x = wp.x,
		y = wp.y,
		height = RFS_MAP_HEIGHT,
		zoom = RFS_MAP_DEFAULT_ZOOM
	} )
	print( "[RFS] /map clientReady -> setOwner on lock part" )
end

function Player.sv_rfs_mapClose( self, reason )
	reason = reason or "close"
	print( "[RFS] /map close (" .. tostring( reason ) .. ")" )
	self.network:sendToClient( self.player, "cl_rfs_nuttMapClose" )
	local wasOpen = self.sv.rfsMapOpen
	local shape = self.sv.rfsMapShape
	self.sv.rfsMapShape = nil
	self.sv.rfsMapOpen = false
	self.sv.rfsMapAwaitingClient = false
	self.sv.rfsMapUsingPart = false

	local character = self.player:getCharacter()
	if character and sm.exists( character ) then
		pcall( function() character:setImmovable( false ) end )
	end

	if shape and sm.exists( shape ) then
		pcall( function()
			local ia = shape.interactable
			if ia then
				sm.event.sendToInteractable( ia, "sv_n_markClosing" )
			end
			shape:destroyShape( 0 )
		end )
	end

	if wasOpen or shape then
		self.network:sendToClient( self.player, "cl_rfs_mapClosed", { reason = reason } )
	end
end

function Player.sv_rfs_mapPartDestroyed( self )
	if not self.sv.rfsMapOpen and not self.sv.rfsMapShape then
		return
	end
	print( "[RFS] /map part destroyed unexpectedly" )
	self.sv.rfsMapShape = nil
	self.sv.rfsMapOpen = false
	self.sv.rfsMapAwaitingClient = false
	self.sv.rfsMapUsingPart = false
	local character = self.player:getCharacter()
	if character and sm.exists( character ) then
		pcall( function() character:setImmovable( false ) end )
	end
	self.network:sendToClient( self.player, "cl_rfs_mapClosed", { reason = "part_destroyed" } )
end

function Player.cl_rfs_mapAwaitLock( self, params )
	self.cl = self.cl or {}
	self.cl.rfsMapOpen = true
	self.cl.rfsMapFallback = false
	self.cl.rfsMapLockReady = false
	self.cl.rfsMapHeight = ( params and params.height ) or RFS_MAP_HEIGHT
	self.cl.rfsMapZoom = ( params and params.zoom ) or RFS_MAP_DEFAULT_ZOOM
	local x = ( params and params.x ) or 0
	local y = ( params and params.y ) or 0
	local z = math.max( 12, self.cl.rfsMapHeight - self.cl.rfsMapZoom )
	self.cl.rfsMapCamPos = sm.vec3.new( x, y, z )
	g_rfs_mapFocus = self.cl.rfsMapCamPos
	g_rfs_mapZoom = self.cl.rfsMapZoom
	g_rfs_mapHeight = self.cl.rfsMapHeight

	-- Start forcing camera immediately while lock replicates (one-shot alone is ignored)
	self:cl_rfs_applyMapCamera()
	print( "[RFS] /map client awaitLock - confirming to server" )
	self.network:sendToServer( "sv_rfs_mapClientReady" )
end

function Player.cl_rfs_mapLockReady( self, params )
	self.cl = self.cl or {}
	self.cl.rfsMapLockReady = true
	self.cl.rfsMapOpen = true
	self.cl.rfsMapFallback = false
	if params then
		self.cl.rfsMapHeight = params.height or self.cl.rfsMapHeight
		self.cl.rfsMapZoom = params.zoom or self.cl.rfsMapZoom
		if params.x and params.y and params.z then
			self.cl.rfsMapCamPos = sm.vec3.new( params.x, params.y, params.z )
			g_rfs_mapFocus = self.cl.rfsMapCamPos
		end
	end
	print( "[RFS] /map client lock ready" )
end

function Player.cl_rfs_mapFallbackOpen( self, params )
	self.cl = self.cl or {}
	self.cl.rfsMapOpen = true
	self.cl.rfsMapFallback = true
	self.cl.rfsMapLockReady = false
	local character = self.player:getCharacter()
	local pos = character and character.worldPosition or sm.vec3.new( 0, 0, 0 )
	local x = ( params and params.x ) or pos.x
	local y = ( params and params.y ) or pos.y
	local z = ( params and params.z ) or ( pos.z + 96 )
	self.cl.rfsMapCamPos = sm.vec3.new( x, y, z )
	self.cl.rfsMapHeight = z + RFS_MAP_DEFAULT_ZOOM
	self.cl.rfsMapZoom = RFS_MAP_DEFAULT_ZOOM
	g_rfs_mapFocus = self.cl.rfsMapCamPos
	local ok, err = pcall( function()
		self:cl_rfs_applyMapCamera()
	end )
	if ok then
		print( "[RFS] /map fallback camera active" )
	else
		sm.gui.chatMessage( "[RFS] Map failed to open." )
		print( "[RFS] /map fallback failed: " .. tostring( err ) )
		self.cl.rfsMapOpen = false
		self.cl.rfsMapFallback = false
	end
end

function Player.cl_rfs_applyMapCamera( self )
	local focus = g_rfs_mapFocus or self.cl.rfsMapCamPos
	if not focus then
		return
	end
	local dir = sm.vec3.new( 0, 0, -1 )
	if sm.camera.getCameraState() ~= sm.camera.state.cutsceneTP then
		sm.camera.setCameraState( sm.camera.state.cutsceneTP )
	end
	sm.camera.setDirection( dir )
	sm.camera.setPosition( focus )
	sm.render.setCinematic( true )
	if self.player.clientPublicData then
		self.player.clientPublicData.interactableCameraData = {
			hideGui = false,
			cameraState = sm.camera.state.cutsceneTP,
			cameraPosition = focus,
			cameraDirection = dir,
			cameraFov = sm.camera.getDefaultFov(),
			lockedControls = false
		}
	end
	self.cl.rfsMapCamPos = focus
end

function Player.cl_rfs_mapClosed( self, params )
	self.cl = self.cl or {}
	self.cl.rfsMapOpen = false
	self.cl.rfsMapFallback = false
	self.cl.rfsMapLockReady = false
	self.cl.rfsMapCamPos = nil
	g_rfs_mapFocus = nil
	g_rfs_mapLockReady = false
	local character = self.player:getCharacter()
	if character and sm.exists( character ) then
		pcall( function() character:setLockingInteractable( nil ) end )
	end
	if self.player.clientPublicData then
		self.player.clientPublicData.interactableCameraData = nil
	end
	pcall( function()
		sm.camera.setCameraState( sm.camera.state.default )
		sm.render.setCinematic( false )
		sm.localPlayer.setLockedControls( false )
	end )
	local reason = params and params.reason
	print( "[RFS] /map closed reason=" .. tostring( reason ) )
end

function Player.cl_rfs_mapMsg( self, msg )
	-- Keep real failures in chat; drop routine status spam.
	local s = tostring( msg or "" )
	if string.find( string.lower( s ), "fail", 1, true )
		or string.find( string.lower( s ), "error", 1, true ) then
		sm.gui.chatMessage( "[RFS] " .. s )
	end
	print( "[RFS] /map msg: " .. s )
end

function Player.cl_rfs_gameModeSpectator( self, data )
	self.cl = self.cl or {}
	local active = false
	if type( data ) == "table" then
		active = data.active == true
	else
		active = data and true or false
	end
	local changed = self.cl.rfsGameModeSpectator ~= active
	self.cl.rfsGameModeSpectator = active
	if self.player == sm.localPlayer.getPlayer() then
		pcall( function()
			sm.localPlayer.setLockedControls( active )
		end )
		pcall( function()
			sm.camera.setCameraState( sm.camera.state.default )
		end )
		if active and changed and data and data.msg then
			sm.gui.chatMessage( "[RFS] " .. tostring( data.msg ) )
		end
	end
end

function Player.client_onCancel( self )
	if self.cl and self.cl.rfsMapOpen then
		if self.cl.rfsMapFallback then
			self:cl_rfs_mapClosed( { reason = "cancel" } )
			self.network:sendToServer( "sv_rfs_mapClose" )
			return
		end
		self.network:sendToServer( "sv_rfs_mapClose" )
		return
	end
	SurvivalPlayer.client_onCancel( self )
end

function Player.server_onFixedUpdate( self, dt )
	SurvivalPlayer.server_onFixedUpdate( self, dt )

	do
		local id = nil
		pcall( function()
			id = self.player.id
		end )
		if id == nil then
			pcall( function()
				id = self.player:getId()
			end )
		end
		local st = id ~= nil and _G.g_rfsRegenByPlayer and _G.g_rfsRegenByPlayer[tostring( id )]
		if st and st.locked then
			self.sv = self.sv or {}
			self.sv.rfsInRegen = true
			if type( self.sv.velocityBuffer ) == "table" then
				local zero = sm.vec3.zero()
				for i = 1, 8 do
					self.sv.velocityBuffer[i] = zero
				end
			end
			-- HP comes from sv_e_rfsDeepSleepHeal (pod sendToPlayer). Do not also
			-- apply from g_rfsRegenByPlayer — interactable _G is not this VM.
		elseif st and st.locked == false and self.sv then
			self.sv.rfsInRegen = false
		end
	end

	do
		local tick = sm.game.getCurrentTick()
		local carrying = type( RfsCarry ) == "table" and RfsCarry.playerIsCarrying( self.player )
		if carrying or ( tick % 40 ) == 0 then
			pcall( function()
				RfsCarry.ensureHooks()
			end )
		end
	end

	pcall( function()
		if type( RfsGameMode ) == "table" and RfsGameMode.processPendingRestore then
			RfsGameMode.processPendingRestore( self )
		end
	end )

	if self.sv and self.sv.rfsMapOpen then
		local character = self.player:getCharacter()
		local dead = ( character == nil ) or ( not sm.exists( character ) ) or character:isDowned()
		local tick = sm.game.getCurrentTick()
		local grace = ( tick - ( self.sv.rfsMapOpenTick or 0 ) ) < RFS_MAP_SHAPE_GRACE_TICKS
		if dead then
			self:sv_rfs_mapClose( "downed" )
		elseif self.sv.rfsMapUsingPart and not grace then
			local shapeGone = ( self.sv.rfsMapShape == nil ) or ( not sm.exists( self.sv.rfsMapShape ) )
			if shapeGone then
				self:sv_rfs_mapClose( "shape_gone" )
			end
		end
	end

	if not ( self.sv and self.sv.rfsFly ) then
		return
	end

	local character = self.player:getCharacter()
	if not character or not sm.exists( character ) then
		return
	end

	if not character:isSwimming() or not character:isDiving() then
		character:setSwimming( true )
		character:setDiving( true )
	end

	local speed = rfs_applyFlySpeed( character )
	if character.publicData then
		character.publicData.waterMovementSpeedFraction = speed
	end
	self.network:sendToClient( self.player, "cl_rfs_setSpeed", speed )

	pcall( function()
		sm.event.sendToPlayer( self.player, "sv_e_debug", { breath = 100 } )
	end )
end

function Player.client_onUpdate( self, dt )
	SurvivalPlayer.client_onUpdate( self, dt )

	if self.player == sm.localPlayer.getPlayer() then
		local tick = sm.game.getCurrentTick()
		local carrying = type( RfsCarry ) == "table" and RfsCarry.localIsCarrying()
		if carrying or ( tick % 40 ) == 0 then
			pcall( function()
				RfsCarry.ensureHooks()
			end )
		end
		pcall( function()
			if type( RfsSoilPlacement ) == "table" and RfsSoilPlacement.client_tickHandPickup then
				RfsSoilPlacement.client_tickHandPickup()
			end
		end )
		pcall( function()
			if type( RfsBlockOverlay ) == "table" and RfsBlockOverlay.update then
				RfsBlockOverlay.update( self )
			end
		end )
		RfsHud.update( self )
		pcall( function()
			if type( RfsHealthBars ) == "table" and RfsHealthBars.ensureHooks then
				RfsHealthBars.ensureHooks()
			end
		end )
		if self.cl and self.cl.rfsGameModeSpectator then
			pcall( function()
				sm.localPlayer.setLockedControls( true )
			end )
		end
	end

	-- Force top-down camera every frame while map is open (continuous camera set)
	if self.cl and self.cl.rfsMapOpen and self.player == sm.localPlayer.getPlayer() then
		if g_rfs_mapLockReady then
			self.cl.rfsMapLockReady = true
		end
		if g_rfs_mapFocus then
			self.cl.rfsMapCamPos = g_rfs_mapFocus
		end
		pcall( function()
			self:cl_rfs_applyMapCamera()
		end )
	end

	if not ( self.cl and self.cl.rfsFly ) then
		return
	end

	local character = self.player:getCharacter()
	if not character or not sm.exists( character ) then
		return
	end

	if not character:isSwimming() or not character:isDiving() then
		character:setSwimming( true )
		character:setDiving( true )
	end

	local speed = rfs_applyFlySpeed( character )
	if character.clientPublicData then
		character.clientPublicData.waterMovementSpeedFraction = speed
	end
end

-- Chemical Regeneration Station: 0.25 HP per tick while locked in the tube.
-- Do not pass Interactable userdata through sm.event (it drops the whole heal).
-- Warp/snap must not run every tick: shock damage from the velocity buffer
-- cancels the heal. Collision while flagged in-tube is ignored.

local RFS_REGEN_UUID = "6f391c5b-82d4-4e17-9a60-c1d5e8f2a4b7"

local function rfsInRegenStation( self )
	if self.sv and self.sv.rfsInRegen then
		return true
	end
	local id = nil
	pcall( function()
		id = self.player.id
	end )
	if id == nil then
		pcall( function()
			id = self.player:getId()
		end )
	end
	local st = id ~= nil and _G.g_rfsRegenByPlayer and _G.g_rfsRegenByPlayer[tostring( id )]
	if st and st.locked then
		return true
	end
	local char = self.player and self.player:getCharacter()
	if not char or not sm.exists( char ) then
		return false
	end
	local ok = false
	pcall( function()
		local ia = char:getLockingInteractable()
		if ia and sm.exists( ia ) and ia.shape then
			ok = string.lower( tostring( ia.shape.uuid ) ) == RFS_REGEN_UUID
		end
	end )
	return ok
end

function Player.sv_e_rfsRegenLock( self, params )
	self.sv = self.sv or {}
	self.sv.rfsInRegen = params and params.on and true or false
end

function Player.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
	if rfsInRegenStation( self ) then
		return
	end
	BasePlayer.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
end

function Player.sv_takeDamage( self, damage, source, typeUuid )
	if rfsInRegenStation( self ) and ( source == "shock" or source == "impact" ) then
		return
	end
	local adjustedDamage = math.max( 0, math.floor( tonumber( damage ) or 0 ) )
	if adjustedDamage <= 0 then
		SurvivalPlayer.sv_takeDamage( self, adjustedDamage, source, typeUuid )
		return
	end
	local gm = ( type( RfsGameMode ) == "table" and RfsGameMode.snapshot and RfsGameMode.snapshot() ) or {}
	local takenMult = 1
	if type( RfsGameMode ) == "table" and RfsGameMode.playerDamageTakenMultiplier then
		takenMult = tonumber( RfsGameMode.playerDamageTakenMultiplier() ) or 1
	end
	adjustedDamage = math.max( 1, math.floor( adjustedDamage * takenMult + 0.5 ) )
	local hp = 0
	if self.sv and self.sv.saved and type( self.sv.saved.stats ) == "table" then
		hp = tonumber( self.sv.saved.stats.hp ) or 0
	end
	local fatal = hp > 0 and adjustedDamage >= hp
	local restore = nil
	if fatal and ( gm.mode == "easy" or gm.mode == "hard" ) then
		if type( RfsGameMode ) == "table" and RfsGameMode.prepareDeathInventory then
			restore = RfsGameMode.prepareDeathInventory( self.player, gm.mode )
		end
	end
	SurvivalPlayer.sv_takeDamage( self, adjustedDamage, source, typeUuid )
	if fatal then
		if gm.hardcore == true then
			if restore and gm.mode == "easy" then
				pcall( function()
					if type( RfsGameMode ) == "table" and RfsGameMode.restoreInventory then
						RfsGameMode.restoreInventory( self.player, restore.snapshot )
					end
				end )
			elseif restore and gm.mode == "hard" then
				pcall( function()
					if type( RfsGameMode ) == "table" and RfsGameMode.applyHardLoadout then
						RfsGameMode.applyHardLoadout( self.player )
					end
				end )
			end
			if type( RfsGameMode ) == "table" and RfsGameMode.enterSpectator then
				RfsGameMode.enterSpectator( self.player )
			end
		elseif restore then
			self.sv = self.sv or {}
			self.sv.rfsGameModePendingRestore = restore
		end
	end
end

function Player.sv_e_rfsDeepSleepHeal( self, params )
	if not self.sv or not self.sv.saved or type( self.sv.saved.stats ) ~= "table" then
		return
	end
	if self.sv.saved.isConscious == false then
		return
	end
	local amount = tonumber( params and params.amount ) or 0.25
	if amount <= 0 then
		return
	end
	local stats = self.sv.saved.stats
	local hp = tonumber( stats.hp ) or 0
	local maxhp = tonumber( stats.maxhp ) or 100
	local applied = hp > 0 and hp < maxhp
	if applied then
		stats.hp = math.min( maxhp, hp + amount )
		pcall( function()
			self.network:setClientData( self.sv.saved )
		end )
		local tick = 0
		pcall( function()
			tick = sm.game.getCurrentTick() or 0
		end )
		if ( tick % 8 ) == 0 or stats.hp >= maxhp then
			pcall( function()
				self.storage:save( self.sv.saved )
			end )
		end
	end
	pcall( function()
		if self.player.publicData then
			self.player.publicData.rfsNeedHeal = applied and true or false
		end
	end )
	pcall( function()
		local char = self.player and self.player:getCharacter()
		local ia = char and sm.exists( char ) and char:getLockingInteractable()
		if ia and sm.exists( ia ) then
			sm.event.sendToInteractable( ia, "sv_e_rfsHealApplied", { applied = applied } )
		end
	end )
	local shapeId = tonumber( params and params.shapeId )
	if shapeId and shapeId ~= 0 then
		local pod = _G.g_rfsHealPods and _G.g_rfsHealPods[shapeId]
		if pod and type( pod.sv_e_rfsHealApplied ) == "function" then
			pcall( function()
				pod:sv_e_rfsHealApplied( { applied = applied } )
			end )
		end
	end
end

-- GenSettings PVP: Survival vanilla ignores player→player damage; enable when ON.
local function rfsPvpEnabled()
	if type( RfsFeatures ) == "table" and type( RfsFeatures.pvpEnabled ) == "function" then
		return RfsFeatures.pvpEnabled() == true
	end
	return _G.g_rfsPvp == true
end

function Player.server_onProjectile( self, hitPos, hitTime, hitVelocity, projectileName, attacker, damage, userData, hitNormal, projectileUuid )
	if type( attacker ) == "Player" and attacker ~= self.player and rfsPvpEnabled() then
		local dmg = tonumber( damage ) or 0
		if dmg > 0 then
			self:sv_takeDamage( dmg, "pvp", projectileUuid )
		end
		if self.player.character and self.player.character:isTumbling() and hitVelocity then
			local n = hitVelocity:normalize()
			if n then
				ApplyKnockback( self.player.character, n, 2000 )
			end
		end
	end
	BasePlayer.server_onProjectile( self, hitPos, hitTime, hitVelocity, projectileName, attacker, damage, userData, hitNormal, projectileUuid )
end

function Player.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if type( attacker ) == "Player" and attacker ~= self.player and rfsPvpEnabled() then
		local dmg = tonumber( damage ) or 0
		if dmg > 0 then
			self:sv_takeDamage( dmg, "pvp" )
		end
	end
	BasePlayer.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
end
