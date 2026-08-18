-- RfsDeepSleepPod.lua — Chemical Regeneration Station (player-facing name).
-- Internal class/uuid unchanged. Colba mesh. Standing lock in the tube.
-- Spend: RfsHealPower only. Do not edit RfsHackPower.
-- Always setActive(false). Do not parent FX/ShapeRenderable onto this interactable.

RfsDeepSleepPod = class( nil )
RfsDeepSleepPod.maxParentCount = 3
RfsDeepSleepPod.maxChildCount = 255
RfsDeepSleepPod.connectionInput = sm.interactable.connectionType.logic + sm.interactable.connectionType.electricity + sm.interactable.connectionType.chemical
RfsDeepSleepPod.connectionOutput = sm.interactable.connectionType.logic
RfsDeepSleepPod.colorNormal = sm.color.new( 0x4aa3c7ff )
RfsDeepSleepPod.colorHighlight = sm.color.new( 0x7ec8e6ff )
RfsDeepSleepPod.connectIcon = "electrical"

local BOX_Y_BLOCKS = 17
local BLOCK_M = 0.25
local STAND_Y_M = -1.225
local EXIT_FORWARD = 1.624
local EXIT_LIFT = 0.4

local FILL_CHEM = 10
local FILL_TICKS = 60 -- ~1.5 s rising purple
local DRAIN_TICKS = 40 -- ~1 s empty after soak
local HEAL_PER_TICK = 0.25
local HEAL_CHEM_EVERY = 40 -- 1 chem / s while they still need HP
local HEAL_POWER_EVERY = 80 -- 1 battery / 2 s = 5 batteries / ~10 s (or 5000 milli)

-- chemfill_v10 native XZ is the circular BASE (~5.2 blocks / 0.65 m radius).
-- Want fill inside the glass: 3 blocks diameter = 0.75 m (radius 0.375 m).
local FILL_MESH_RADIUS_M = 0.650
local FILL_DIAMETER_BLOCKS = 3
local FILL_RADIUS_M = FILL_DIAMETER_BLOCKS * BLOCK_M * 0.5
local FILL_XZ_SCALE = FILL_RADIUS_M / FILL_MESH_RADIUS_M
local FILL_HEIGHT_M = 2.255
local FILL_BOTTOM_Y_M = -1.197
local FILL_UUID = sm.uuid.new( "a7e3c91f-6b24-4d80-8e15-2c9f4a0b7d63" )

local RFS_CG = "$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247"
local function rfsDofile( rel )
	local paths = { RFS_CG .. "/" .. rel, "$CONTENT_DATA/" .. rel }
	for _, p in ipairs( paths ) do
		local ok = pcall( function()
			dofile( p )
		end )
		if ok then
			return true
		end
	end
	return false
end
rfsDofile( "Scripts/game/RfsRecharge.lua" )
rfsDofile( "Scripts/game/RfsHealPower.lua" )
rfsDofile( "Scripts/game/RfsDeepSleepTime.lua" )

local LOGIC = sm.interactable.connectionType.logic
local ELEC = sm.interactable.connectionType.electricity
local CHEM = sm.interactable.connectionType.chemical
local TITLE = "Chemical Regeneration Station"
local SNAP_IF_DRIFT_M = 0.5

_G.g_rfsHealPods = _G.g_rfsHealPods or {}

local function shapeIdOf( self )
	local id = 0
	pcall( function()
		id = tonumber( self.shape.id ) or tonumber( self.shape:getId() ) or 0
	end )
	return id
end

local function registerPod( self )
	local id = shapeIdOf( self )
	if id ~= 0 then
		_G.g_rfsHealPods[id] = self
	end
end

local function unregisterPod( self )
	local id = shapeIdOf( self )
	if id ~= 0 then
		_G.g_rfsHealPods[id] = nil
	end
end

local function tellRegenLock( player, on )
	if not player or not sm.exists( player ) then
		return
	end
	pcall( function()
		sm.event.sendToPlayer( player, "sv_e_rfsRegenLock", { on = on and true or false } )
	end )
end

local function publish( self )
	local batteries = 0
	local recharge = 0
	pcall( function()
		batteries = RfsHealPower.totalBatteries( RfsHealPower.elecContainers( self ) )
		recharge = RfsHealPower.totalRechargeBatteries( self )
	end )
	local data = {
		powered = self.sv.powered and true or false,
		healing = self.sv.healing and true or false,
		filling = self.sv.phase == "fill",
		draining = self.sv.phase == "drain",
		patients = self.sv.occupant and 1 or 0,
		batteries = batteries,
		recharge = recharge,
		fill = self.sv.fill or 0,
		needChem = self.sv.needChem and true or false,
		needPower = ( not self.sv.powered ) and true or false,
	}
	pcall( function()
		self.network:setClientData( data )
	end )
	pcall( function()
		self.interactable:setPublicData( data )
	end )
	pcall( function()
		self.interactable:setActive( false )
	end )
end

local function occupantOk( self )
	local p = self.sv and self.sv.occupant
	if p and sm.exists( p ) then
		return p
	end
	return nil
end

local function standWorldPos( self )
	local origin = self.shape.worldPosition
	local rot = self.shape.worldRotation
	local up = rot * sm.vec3.new( 0, 1, 0 )
	return origin + up * STAND_Y_M
end

local function exitWorldPos( self )
	local origin = self.shape.worldPosition
	local rot = self.shape.worldRotation
	local front = rot * sm.vec3.new( 0, 0, 1 )
	local up = rot * sm.vec3.new( 0, 1, 0 )
	local halfY = BOX_Y_BLOCKS * BLOCK_M * 0.5
	return origin + front * EXIT_FORWARD - up * halfY + sm.vec3.new( 0, 0, EXIT_LIFT )
end

local function characterOf( player )
	local char = nil
	pcall( function()
		char = player and ( player.character or player:getCharacter() )
	end )
	if char and sm.exists( char ) then
		return char
	end
	return nil
end

local function freezeCharacter( player, frozen )
	local char = characterOf( player )
	if not char then
		return
	end
	pcall( function()
		char:setImmovable( frozen and true or false )
	end )
end

local function warpPlayer( player, pos )
	if not player or not pos then
		return
	end
	local char = characterOf( player )
	if not char then
		return
	end
	pcall( function()
		char:setWorldPosition( pos )
	end )
end

local function occupantDrifted( player, pos )
	if not player or not pos then
		return false
	end
	local char = characterOf( player )
	if not char then
		return true
	end
	local far = false
	pcall( function()
		local delta = char.worldPosition - pos
		far = delta:length() > SNAP_IF_DRIFT_M
	end )
	return far
end

local function beginDrain( self )
	self.sv.phase = "drain"
	self.sv.drainFrom = math.max( tonumber( self.sv.fill ) or 0, 0.02 )
	self.sv.drainTick = 0
	self.sv.fillPaid = false
	self.sv.healAcc = 0
	self.sv.chemAcc = 0
	self.sv.needHeal = nil
end

function RfsDeepSleepPod.server_onCreate( self )
	self.sv = self.sv or {}
	self.sv.powered = false
	self.sv.healing = false
	self.sv.patients = 0
	self.sv.drainAcc = 0
	self.sv.fill = 0
	self.sv.phase = "idle"
	self.sv.occupant = nil
	self.sv.fillPaid = false
	self.sv.fillTick = 0
	self.sv.healAcc = 0
	self.sv.chemAcc = 0
	self.sv.needHeal = true
	self.sv.needChem = false
	self.sv.loaded = true
	registerPod( self )
	pcall( function()
		self.interactable:setActive( false )
	end )
	publish( self )
end

function RfsDeepSleepPod.server_onDestroy( self )
	if self.sv and self.sv.loaded then
		tellRegenLock( self.sv.occupant, false )
		freezeCharacter( self.sv.occupant, false )
		pcall( function()
			if g_respawnManager then
				g_respawnManager:sv_destroyBed( self.shape )
			end
		end )
		self.sv.loaded = false
	end
	unregisterPod( self )
end

function RfsDeepSleepPod.server_onUnload( self )
	if self.sv and self.sv.loaded then
		pcall( function()
			if g_respawnManager then
				g_respawnManager:sv_updateBed( self.shape )
			end
		end )
		self.sv.loaded = false
	end
end

function RfsDeepSleepPod.sv_activateBed( self, character )
	if not character then
		return
	end
	pcall( function()
		if g_respawnManager then
			g_respawnManager:sv_registerBed( self.shape, character )
		end
	end )
end

function RfsDeepSleepPod.sv_e_rfsSkipDrain( self, params )
	local ticks = tonumber( params and params.ticks ) or 0
	if ticks <= 0 or not self.sv then
		return
	end
	if self.sv.phase ~= "heal" or not self.sv.powered then
		return
	end
	if type( RfsHealPower ) ~= "table" or type( RfsHealPower.spendOne ) ~= "function" then
		return
	end
	local every = tonumber( RfsHealPower.DRAIN_EVERY ) or HEAL_POWER_EVERY
	if every < 1 then
		every = HEAL_POWER_EVERY
	end
	local n = math.floor( ticks / every )
	for _ = 1, n do
		if not RfsHealPower.spendOne( self ) then
			self.sv.powered = false
			break
		end
	end
	publish( self )
end

function RfsDeepSleepPod.sv_n_tryEnter( self, params, player )
	if not player or not sm.exists( player ) then
		return
	end
	if occupantOk( self ) then
		if occupantOk( self ) == player then
			self:sv_n_tryExit( nil, player )
		else
			pcall( function()
				sm.gui.chatMessage( "[RFS] " .. TITLE .. ": station in use." )
			end )
		end
		return
	end
	if ( self.sv.phase == "drain" ) and ( ( self.sv.fill or 0 ) > 0.02 ) then
		pcall( function()
			sm.gui.chatMessage( "[RFS] " .. TITLE .. ": tank is draining." )
		end )
		return
	end
	if type( RfsHealPower ) ~= "table" or not RfsHealPower.hasChem( player, FILL_CHEM, self ) then
		self.sv.needChem = true
		publish( self )
		pcall( function()
			sm.gui.chatMessage( "[RFS] " .. TITLE .. ": need " .. tostring( FILL_CHEM ) .. " Chemicals to fill." )
		end )
		return
	end
	local spent, src = RfsHealPower.spendChem( player, FILL_CHEM, self )
	if not spent then
		self.sv.needChem = true
		publish( self )
		return
	end
	self.sv.needChem = false
	self.sv.occupant = player
	self.sv.phase = "fill"
	self.sv.fill = 0
	self.sv.fillTick = 0
	self.sv.fillPaid = true
	self.sv.fillPaidSrc = src
	self.sv.healAcc = 0
	self.sv.chemAcc = 0
	self.sv.needHeal = true
	local char = nil
	pcall( function()
		char = player.character or player:getCharacter()
	end )
	self:sv_activateBed( char )
	tellRegenLock( player, true )
	freezeCharacter( player, true )
	warpPlayer( player, standWorldPos( self ) )
	self.network:sendToClient( player, "cl_n_lock", { enter = true } )
	publish( self )
end

function RfsDeepSleepPod.sv_n_tryExit( self, params, player )
	local occ = occupantOk( self )
	if not occ or ( player and occ ~= player ) then
		return
	end
	if self.sv.phase == "fill" and self.sv.fillPaid then
		RfsHealPower.refundChem( occ, FILL_CHEM, self, self.sv.fillPaidSrc )
		self.sv.fillPaid = false
		self.sv.fillPaidSrc = nil
	end
	local pos = exitWorldPos( self )
	tellRegenLock( occ, false )
	freezeCharacter( occ, false )
	warpPlayer( occ, pos )
	self.network:sendToClient( occ, "cl_n_lock", { enter = false, x = pos.x, y = pos.y, z = pos.z } )
	self.sv.occupant = nil
	self.sv.healing = false
	beginDrain( self )
	publish( self )
end

function RfsDeepSleepPod.sv_e_rfsHealApplied( self, params )
	if type( params ) == "table" then
		self.sv.needHeal = params.applied and true or false
	end
end

function RfsDeepSleepPod.server_onFixedUpdate( self )
	if not self.sv then
		return
	end
	registerPod( self )
	if self.sv.loaded then
		local prevWorld = self.sv.currentWorld
		pcall( function()
			self.sv.currentWorld = self.shape.body:getWorld()
		end )
		if prevWorld ~= nil and self.sv.currentWorld ~= prevWorld then
			pcall( function()
				if g_respawnManager then
					g_respawnManager:sv_updateBed( self.shape )
				end
			end )
		end
	end

	local powered = false
	pcall( function()
		powered = RfsHealPower.isPowered( self )
	end )

	local occ = occupantOk( self )
	if self.sv.occupant and not occ then
		tellRegenLock( self.sv.occupant, false )
		freezeCharacter( self.sv.occupant, false )
		self.sv.occupant = nil
		self.sv.healing = false
		if self.sv.phase == "fill" and self.sv.fillPaid then
			self.sv.fillPaid = false
		end
		if self.sv.phase == "fill" or self.sv.phase == "heal" then
			beginDrain( self )
		end
	end
	occ = occupantOk( self )

	if occ and ( self.sv.phase == "fill" or self.sv.phase == "heal" ) then
		freezeCharacter( occ, true )
		local stand = standWorldPos( self )
		-- Warp only if they drifted. Every-tick setWorldPosition filled the
		-- fall-velocity buffer and shock damage ate the 0.25 HP heal ticks.
		if occupantDrifted( occ, stand ) then
			warpPlayer( occ, stand )
		end
	end

	if self.sv.phase == "fill" and occ then
		self.sv.fillTick = ( self.sv.fillTick or 0 ) + 1
		self.sv.fill = math.min( 1, self.sv.fillTick / FILL_TICKS )
		if self.sv.fillTick >= FILL_TICKS then
			self.sv.fill = 1
			self.sv.phase = "heal"
			self.sv.fillPaid = false
			self.sv.needHeal = true
			self.sv.healAcc = 0
			self.sv.chemAcc = 0
			local nPlayers = 0
			pcall( function()
				nPlayers = #( sm.player.getAllPlayers() or {} )
			end )
			if nPlayers <= 1 and type( RfsDeepSleepTime ) == "table" then
				pcall( function()
					sm.event.sendToGame( "sv_e_rfsDeepSleepSkip", { healing = true } )
				end )
			elseif nPlayers > 1 then
				pcall( function()
					sm.gui.chatMessage( "[RFS] " .. TITLE .. ": respawn set. Night skip is solo-only." )
				end )
			end
		end
	end

	local working = false
	if self.sv.phase == "heal" and occ then
		if powered then
			local need = self.sv.needHeal
			if need == nil then
				need = true
			end
			pcall( function()
				sm.event.sendToPlayer( occ, "sv_e_rfsDeepSleepHeal", {
					amount = HEAL_PER_TICK,
					shapeId = shapeIdOf( self ),
				} )
			end )
			if need then
				working = true
				self.sv.chemAcc = ( self.sv.chemAcc or 0 ) + 1
				if self.sv.chemAcc >= HEAL_CHEM_EVERY then
					self.sv.chemAcc = 0
					if not RfsHealPower.spendChem( occ, 1, self ) then
						self.sv.needChem = true
						working = false
					else
						self.sv.needChem = false
					end
				end
			end
		end
	end

	if type( RfsHealPower ) == "table" then
		if working then
			self.sv.healAcc = ( self.sv.healAcc or 0 ) + 1
			local every = tonumber( RfsHealPower.DRAIN_EVERY ) or HEAL_POWER_EVERY
			if every < 1 then
				every = HEAL_POWER_EVERY
			end
			if self.sv.healAcc >= every then
				self.sv.healAcc = 0
				if not RfsHealPower.spendOne( self ) then
					powered = false
				else
					powered = RfsHealPower.isPowered( self )
				end
			end
		else
			self.sv.healAcc = 0
			powered = RfsHealPower.isPowered( self )
		end
	end

	if self.sv.phase == "drain" then
		self.sv.drainTick = ( self.sv.drainTick or 0 ) + 1
		local from = tonumber( self.sv.drainFrom ) or 1
		local t = math.min( 1, self.sv.drainTick / DRAIN_TICKS )
		self.sv.fill = from * ( 1 - t )
		if t >= 1 then
			self.sv.fill = 0
			self.sv.phase = "idle"
		end
	end

	self.sv.powered = powered
	self.sv.healing = working and powered
	self.sv.patients = occ and 1 or 0
	pcall( function()
		self.interactable:setActive( false )
	end )
	if ( sm.game.getCurrentTick() % 4 ) == 0 or working or self.sv.phase ~= "idle" then
		publish( self )
	end
end

function RfsDeepSleepPod.client_onCreate( self )
	self.cl = { powered = false, healing = false, fill = 0, pendingExit = 0, locked = false }
end

function RfsDeepSleepPod.client_onDestroy( self )
	if self.cl and self.cl.locked then
		local player = sm.localPlayer.getPlayer()
		local character = player and player:getCharacter()
		if character and sm.exists( character ) then
			pcall( function()
				character:setImmovable( false )
			end )
			pcall( function()
				character:setLockingInteractable( nil )
			end )
		end
		self.cl.locked = false
	end
	if self.cl and self.cl.fillFx then
		pcall( function()
			self.cl.fillFx:stop()
		end )
		pcall( function()
			self.cl.fillFx:destroy()
		end )
		self.cl.fillFx = nil
	end
end

local function cl_snapCharacter( character, pos )
	if not character or not pos then
		return
	end
	pcall( function()
		character:setWorldPosition( pos )
	end )
	pcall( function()
		character:setImmovable( true )
	end )
end

function RfsDeepSleepPod.cl_n_lock( self, params )
	local player = sm.localPlayer.getPlayer()
	local character = player and player:getCharacter()
	if not character or not sm.exists( character ) then
		return
	end
	self.cl = self.cl or {}
	if params and params.enter then
		self.cl.locked = true
		self.cl.pendingExit = 0
		pcall( function()
			character:setLockingInteractable( self.interactable )
		end )
		pcall( function()
			character:setImmovable( true )
		end )
		cl_snapCharacter( character, standWorldPos( self ) )
	else
		self.cl.locked = false
		pcall( function()
			character:setImmovable( false )
		end )
		pcall( function()
			character:setLockingInteractable( nil )
		end )
		if params and params.x then
			pcall( function()
				character:setWorldPosition( sm.vec3.new( params.x, params.y, params.z ) )
			end )
		else
			pcall( function()
				character:setWorldPosition( exitWorldPos( self ) )
			end )
		end
		self.cl.pendingExit = 8
	end
end

function RfsDeepSleepPod.cl_updateFillFx( self )
	local fill = tonumber( self.cl and self.cl.fill ) or 0
	if fill < 0.02 then
		if self.cl.fillFx then
			pcall( function()
				self.cl.fillFx:stop()
			end )
			pcall( function()
				self.cl.fillFx:destroy()
			end )
			self.cl.fillFx = nil
		end
		return
	end
	if not self.cl.fillFx then
		local fx = nil
		pcall( function()
			fx = sm.effect.createEffect( "ShapeRenderable" )
			fx:setParameter( "uuid", FILL_UUID )
			fx:setParameter( "color", sm.color.new( 0x7a28c8ff ) )
		end )
		self.cl.fillFx = fx
	end
	local fx = self.cl.fillFx
	if not fx then
		return
	end
	local origin = self.shape.worldPosition
	local rot = self.shape.worldRotation
	local up = rot * sm.vec3.new( 0, 1, 0 )
	local h = FILL_HEIGHT_M * fill
	pcall( function()
		fx:setPosition( origin + up * ( FILL_BOTTOM_Y_M + h * 0.5 ) )
		fx:setRotation( rot )
		fx:setScale( sm.vec3.new( FILL_XZ_SCALE, math.max( fill, 0.02 ), FILL_XZ_SCALE ) )
		fx:start()
	end )
end

function RfsDeepSleepPod.client_onFixedUpdate( self )
	if not ( self.cl and self.cl.locked ) then
		return
	end
	local player = sm.localPlayer.getPlayer()
	local character = player and player:getCharacter()
	if not character or not sm.exists( character ) then
		return
	end
	pcall( function()
		character:setImmovable( true )
	end )
	-- Do not snap every tick: that fights the server and looks like falling.
	local stand = standWorldPos( self )
	local far = false
	pcall( function()
		far = ( character.worldPosition - stand ):length() > SNAP_IF_DRIFT_M
	end )
	if far then
		cl_snapCharacter( character, stand )
	end
end

function RfsDeepSleepPod.client_onUpdate( self, dt )
	self:cl_updateFillFx()
	if not self.cl then
		return
	end
	if self.cl.locked then
		return
	end
	if ( self.cl.pendingExit or 0 ) <= 0 then
		return
	end
	self.cl.pendingExit = self.cl.pendingExit - 1
	local player = sm.localPlayer.getPlayer()
	local character = player and player:getCharacter()
	if character and sm.exists( character ) then
		pcall( function()
			character:setWorldPosition( exitWorldPos( self ) )
		end )
	end
end

function RfsDeepSleepPod.client_onClientDataUpdate( self, data )
	if type( data ) ~= "table" then
		return
	end
	self.cl = self.cl or {}
	self.cl.powered = data.powered and true or false
	self.cl.healing = data.healing and true or false
	self.cl.filling = data.filling and true or false
	self.cl.draining = data.draining and true or false
	self.cl.patients = data.patients or 0
	self.cl.batteries = data.batteries or 0
	self.cl.recharge = data.recharge or 0
	self.cl.fill = tonumber( data.fill ) or 0
	self.cl.needChem = data.needChem and true or false
	self.cl.needPower = data.needPower and true or false
end

function RfsDeepSleepPod.client_onInteract( self, character, state )
	if state == true then
		self.network:sendToServer( "sv_n_tryEnter" )
	end
end

function RfsDeepSleepPod.client_onAction( self, controllerAction, state )
	if state == true then
		if controllerAction == sm.interactable.actions.use or controllerAction == sm.interactable.actions.jump then
			self.network:sendToServer( "sv_n_tryExit" )
		end
	end
	return true
end

function RfsDeepSleepPod.client_canInteract( self )
	local pd = self.cl or {}
	if pd.filling then
		sm.gui.setInteractionText( "", "", TITLE .. " — filling (" .. tostring( FILL_CHEM ) .. " Chemicals)" )
	elseif pd.healing then
		sm.gui.setInteractionText( "", "", TITLE .. " — regenerating. E / jump to exit" )
	elseif pd.draining then
		sm.gui.setInteractionText( "", "", TITLE .. " — tank draining" )
	elseif pd.needChem then
		sm.gui.setInteractionText( "", "", TITLE .. " — need " .. tostring( FILL_CHEM ) .. " Chemicals to fill" )
	elseif not pd.powered then
		sm.gui.setInteractionText( "", "", TITLE .. " — E to fill (10 Chemicals). Wire power to heal" )
	else
		sm.gui.setInteractionText( "", "", TITLE .. " — E to enter and fill (10 Chemicals)" )
	end
	return true
end

function RfsDeepSleepPod.client_getAvailableParentConnectionCount( self, connectionType )
	if type( RfsHealPower ) ~= "table" then
		return 1
	end
	local function parentCount( kind )
		local n = 0
		pcall( function()
			n = #( self.interactable:getParents( kind ) or {} )
		end )
		return n
	end
	if RfsHealPower.band( connectionType, CHEM ) ~= 0 then
		return math.max( 0, 1 - parentCount( CHEM ) )
	end
	if RfsHealPower.band( connectionType, ELEC ) ~= 0 then
		return math.max( 0, 1 - parentCount( ELEC ) )
	end
	if RfsHealPower.band( connectionType, LOGIC ) ~= 0 then
		return math.max( 0, 1 - parentCount( LOGIC ) )
	end
	return 0
end

print( "[RFS] RfsDeepSleepPod loaded (Chemical Regeneration Station, center lock, heal ticks)" )
