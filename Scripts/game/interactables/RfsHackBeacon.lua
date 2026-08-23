-- RfsHackBeacon.lua — thin interactable shell.
-- OWNER: class + connections. Apply/convert is RfsHackApply (not this file). Spend / caps / save / range / Orders live in extra files.
-- FROZEN spend is RfsHackPower (idle = no drain; 40*56 / 40*36 / 40*22). Do not retune here.
-- SHOW RANGE is Game-hosted RfsRangeViz via RfsHackRange. Never parent FX onto this interactable.

RfsHackBeacon = class( nil )
-- High parent/child so Battery + logic + radio modules attach directly (no long chains).
RfsHackBeacon.maxParentCount = 255
RfsHackBeacon.maxChildCount = 255
-- Logic + electricity. Lua spends 1 bat; always setActive(false) so the engine
-- does not treat this as a motor. Elec out lets modules hang as children.
RfsHackBeacon.connectionInput = sm.interactable.connectionType.logic + sm.interactable.connectionType.electricity
RfsHackBeacon.connectionOutput = sm.interactable.connectionType.logic + sm.interactable.connectionType.electricity
RfsHackBeacon.colorNormal = sm.color.new( 0xd02525ff )
RfsHackBeacon.colorHighlight = sm.color.new( 0xff6a6aff )
RfsHackBeacon.connectIcon = "electrical"

-- Prefer Custom Game pack (workshop/local RFS). B&P "RFS Beacons" loads this
-- file with $CONTENT_DATA = the parts mod, which historically shipped a stale
-- copy and has no hijack/orders scripts — so CG id must win.
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
pcall( function()
	dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )
end )
pcall( function()
	dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
end )
rfsDofile( "Scripts/game/RfsHackPower.lua" )
rfsDofile( "Scripts/game/RfsHackCaps.lua" )
rfsDofile( "Scripts/game/RfsRadioStation.lua" )
rfsDofile( "Scripts/game/RfsHackSave.lua" )
rfsDofile( "Scripts/game/RfsHackRange.lua" )
rfsDofile( "Scripts/game/RfsHackStatusOverlay.lua" )
rfsDofile( "Scripts/game/RfsBotHijack.lua" )
rfsDofile( "Scripts/game/RfsBotInventory.lua" )
rfsDofile( "Scripts/game/RfsHackApply.lua" )
rfsDofile( "Scripts/game/RfsHackReload.lua" )
rfsDofile( "Scripts/game/RfsHackTether.lua" )
rfsDofile( "Scripts/game/RfsFeatures.lua" )
rfsDofile( "Scripts/game/RfsBeaconOrdersGui.lua" )
rfsDofile( "Scripts/game/RfsHackOrdersList.lua" )
rfsDofile( "Scripts/game/RfsHackOrdersGui.lua" )
rfsDofile( "Scripts/game/hack/RfsHackV1.lua" )

-- uuid → base tier. Live range/cap/hold come from RfsRadioStation.bonuses.
local TIERS = {
	["b4e8c1a0-7d2f-4a91-9c3e-29f1a8d6b5e7"] = {
		name = "Hack Beacon",
		range = 30,
		canInfect = false,
		hijackTicks = 40 * 8, -- convert telegraph / legacy; hold is holdSec
		infectTicks = 0,
		holdSec = 8,
		ringColor = sm.color.new( 0.95, 0.35, 0.12, 1.0 ),
	},
	-- Legacy Aim Core / Station Core uuid: same Hack tier if an old save still has it.
	["c2f158b0-4d7e-4a19-9c6b-8e3a1f50d247"] = {
		name = "Hack Beacon",
		range = 30,
		canInfect = false,
		hijackTicks = 40 * 8,
		infectTicks = 0,
		holdSec = 8,
		ringColor = sm.color.new( 0.95, 0.35, 0.12, 1.0 ),
	},
}

local function tierOf( shape, beacon )
	local id = tostring( shape.uuid )
	local t = TIERS[id] or TIERS["b4e8c1a0-7d2f-4a91-9c3e-29f1a8d6b5e7"]
	local out = {}
	for k, v in pairs( t ) do
		out[k] = v
	end
	out.hackCap = ( type( RfsHackCaps ) == "table" and RfsHackCaps.forUuid( id ) ) or 4
	out.holdSec = tonumber( out.holdSec ) or 8
	out.drainEvery = ( type( RfsHackPower ) == "table" and RfsHackPower.drainEvery( id ) ) or ( 40 * 56 )
	if beacon and type( RfsRadioStation ) == "table" and RfsRadioStation.bonuses then
		local ok, b = pcall( RfsRadioStation.bonuses, beacon )
		if ok and type( b ) == "table" then
			out.range = tonumber( b.range ) or out.range
			out.hackCap = tonumber( b.cap ) or out.hackCap
			out.holdSec = tonumber( b.holdSec ) or out.holdSec
			out.modules = {
				brick = tonumber( b.brick ) or 0,
				antenna = tonumber( b.antenna ) or 0,
				lock = tonumber( b.lock ) or 0,
			}
		end
	end
	return out
end

local function beaconKey( shape )
	local id = nil
	pcall( function() id = shape.id end )
	if id ~= nil then
		return tostring( id )
	end
	return tostring( shape )
end

local function hackDevicesOn()
	if type( RfsFeatures ) == "table" and type( RfsFeatures.hackDevicesEnabled ) == "function" then
		local ok, v = pcall( RfsFeatures.hackDevicesEnabled )
		if ok then
			return v and true or false
		end
	end
	return true
end

local function hackableRobotsOn()
	if type( RfsFeatures ) == "table" and type( RfsFeatures.hackableRobotsEnabled ) == "function" then
		local ok, v = pcall( RfsFeatures.hackableRobotsEnabled )
		if ok then
			return v and true or false
		end
	end
	return true
end

local function publish( self, extra )
	local t = self.sv.tier or tierOf( self.shape )
	local disabled = not hackDevicesOn()
	local homeAllies = 0
	if type( RfsBotHijack ) == "table" and RfsBotHijack.homeAllyCount and self.sv and self.sv.key then
		pcall( function()
			homeAllies = RfsBotHijack.homeAllyCount( self.sv.key ) or 0
		end )
	end
	local role = "independent"
	local masterKey = nil
	if type( RfsBotHijack ) == "table" and RfsBotHijack.effectiveBeaconRole and self.sv and self.sv.key then
		pcall( function()
			role, masterKey = RfsBotHijack.effectiveBeaconRole( self.sv.key )
		end )
	else
		role = self.sv and self.sv.role or "independent"
		masterKey = self.sv and self.sv.masterKey or nil
	end
	local powered = ( not disabled ) and self.sv.powered and true or false
	local converting = extra and extra.converting or ( tonumber( self.sv and self.sv.converting ) or 0 )
	local raid = extra and extra.raid
	if raid == nil then
		raid = self.sv and self.sv._rfsHackV1WasRaid and true or false
	end
	local powerReason = extra and extra.powerReason
	if powerReason == nil and ( not powered ) and type( RfsHackPower ) == "table" and RfsHackPower.powerFailReason then
		pcall( function()
			powerReason = RfsHackPower.powerFailReason( self )
		end )
	end
	local statusLine = nil
	if type( RfsHackStatusOverlay ) == "table" and RfsHackStatusOverlay.lineFrom then
		statusLine = select( 1, RfsHackStatusOverlay.lineFrom( {
			disabled = disabled,
			powered = powered,
			raid = raid and true or false,
			converting = converting,
			modules = t.modules,
		} ) )
	end
	local data = {
		powered = powered,
		disabled = disabled,
		range = t.range,
		name = t.name,
		hackCap = tonumber( t.hackCap ) or 4,
		holdSec = tonumber( t.holdSec ) or 8,
		modules = t.modules,
		canInfect = t.canInfect and true or false,
		linked = extra and extra.linked or 0,
		converting = converting,
		homeAllies = ( extra and extra.homeAllies ~= nil ) and extra.homeAllies or homeAllies,
		batteries = extra and extra.batteries or 0,
		wired = extra and extra.wired and true or false,
		hijackSec = extra and extra.hijackSec or ( tonumber( t.holdSec ) or ( ( t.hijackTicks or 320 ) / 40 ) ),
		raid = raid and true or false,
		raidRange = extra and extra.raidRange or t.range,
		powerReason = powerReason,
		statusLine = statusLine,
		beaconKey = self.sv and self.sv.key or nil,
		role = role,
		masterKey = masterKey,
		showRange = ( type( RfsBotHijack ) == "table" and RfsBotHijack.isRangeVisible
			and self.sv and self.sv.key and RfsBotHijack.isRangeVisible( self.sv.key ) ) and true or false,
	}
	pcall( function()
		self.network:setClientData( data )
	end )
	pcall( function()
		self.interactable:setPublicData( data )
	end )
	-- Always inactive: Lua tickWorkDrain is the only spend (1 bat / 56/36/22s
	-- while linked/converting). Wiring is real; the engine must not motor-drain.
	pcall( function()
		self.interactable:setActive( false )
	end )
end

function RfsHackBeacon.server_onCreate( self )
	self.sv = self.sv or {}
	if type( RfsHackSave ) == "table" then
		RfsHackSave.load( self )
	else
		self.sv.role = "independent"
		self.sv.masterKey = nil
	end
	self.sv.tier = tierOf( self.shape, self )
	self.sv.powered = false
	self.sv.drainAcc = 0
	self.sv.key = beaconKey( self.shape )
	pcall( function()
		self.interactable:setActive( false )
	end )
	-- 0851-r: no RfsHackTether.ensureHooks / convert register.
end

function RfsHackBeacon.server_onDestroy( self )
	local key = self.sv and self.sv.key and tostring( self.sv.key ) or nil
	if not key then
		pcall( function()
			if self.shape then
				key = beaconKey( self.shape )
			end
		end )
	end
	if type( RfsHackRange ) == "table" then
		if key and RfsHackRange.notifyGameOff then
			RfsHackRange.notifyGameOff( key )
		elseif RfsHackRange.push then
			RfsHackRange.push( self, false, { tier = self.sv and self.sv.tier } )
		end
	end
	if type( RfsBotHijack ) == "table" and key then
		RfsBotHijack.unregisterBeacon( key )
		if RfsBotHijack.beaconScripts and RfsBotHijack.beaconScripts[key] == self then
			RfsBotHijack.beaconScripts[key] = nil
		end
		if RfsBotHijack.setRangeVisible then
			RfsBotHijack.setRangeVisible( key, false )
		end
	end
end

function RfsHackBeacon.server_onFixedUpdate( self, dt )
	if type( RfsHackPower ) ~= "table" then
		return
	end
	self.sv = self.sv or {}
	-- Refresh modules often so wiring Brick/Antenna/Lock updates range/cap/hold live.
	self.sv.tier = tierOf( self.shape, self )
	local shape = self.shape
	if not shape or not sm.exists( shape ) then
		return
	end
	-- Every tick, not only publish (every 10). Never an electrical motor load.
	pcall( function()
		self.interactable:setActive( false )
	end )
	self.sv.key = self.sv.key or beaconKey( shape )
	local devicesOn = hackDevicesOn()
	local wasPowered = self.sv.powered and true or false

	if not devicesOn then
		self.sv.powered = false
		self.sv.drainAcc = 0
		if type( RfsBotHijack ) == "table" and self.sv.key then
			pcall( function()
				RfsBotHijack.unregisterBeacon( self.sv.key )
			end )
		end
		local tickOff = 0
		pcall( function()
			tickOff = sm.game.getCurrentTick()
		end )
		-- TEMP: gensettings Hack Devices off → v1 never ticks.
		if ( tickOff % ( 40 * 5 ) ) == 0 then
			pcall( function()
				self.network:sendToClients( "cl_rfsMsg", "hack: Hack Devices OFF in /gensettings" )
			end )
		end
		if wasPowered or ( tickOff % 10 ) == 0 then
			local boxes = RfsHackPower.elecContainers( self )
			publish( self, {
				linked = 0,
				converting = 0,
				batteries = RfsHackPower.totalBatteries( boxes ),
				wired = #boxes > 0,
			} )
		end
		return
	end

	self.sv.powered = RfsHackPower.isPowered( self )
	local t = self.sv.tier
	-- 0851-r: do not registerBeacon / tickAuto / convert. Idle work-drain stays off.
	RfsHackPower.tickWorkDrain( self, false )

	if type( RfsHackV1 ) == "table" then
		RfsHackV1.serverTick( self )
	end

	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick()
	end )
	local converting = tonumber( self.sv.converting ) or 0
	if type( RfsHackV1Timer ) == "table" and RfsHackV1Timer.countForBeacon and self.sv.key then
		pcall( function()
			converting = RfsHackV1Timer.countForBeacon( self.sv.key ) or converting
		end )
	end
	self.sv.converting = converting
	local raid = self.sv._rfsHackV1WasRaid and true or false
	local mods = ( t and t.modules ) or { brick = 0, antenna = 0, lock = 0 }
	local modSig = string.format( "%d:%d:%d", tonumber( mods.brick ) or 0, tonumber( mods.antenna ) or 0, tonumber( mods.lock ) or 0 )
	local statusLine = nil
	if type( RfsHackStatusOverlay ) == "table" and RfsHackStatusOverlay.lineFrom then
		statusLine = select( 1, RfsHackStatusOverlay.lineFrom( {
			disabled = false,
			powered = self.sv.powered and true or false,
			raid = raid,
			converting = converting,
			modules = mods,
		} ) )
	end
	local statusChanged = ( self.sv._rfsStatusLine ~= statusLine )
		or ( self.sv.powered ~= wasPowered )
		or ( self.sv._rfsStatusRaid ~= raid )
		or ( self.sv._rfsStatusConv ~= converting )
		or ( self.sv._rfsStatusMods ~= modSig )
	-- Publish ~1/s or on status / module change (overlay is primary feedback).
	if statusChanged or ( tick % 40 ) == 0 then
		self.sv._rfsStatusLine = statusLine
		self.sv._rfsStatusRaid = raid
		self.sv._rfsStatusConv = converting
		self.sv._rfsStatusMods = modSig
		local boxes = RfsHackPower.elecContainers( self )
		local reason = nil
		if not self.sv.powered then
			reason = RfsHackPower.powerFailReason( self )
		end
		publish( self, {
			linked = 0,
			converting = converting,
			batteries = RfsHackPower.totalBatteries( boxes ),
			wired = #boxes > 0,
			hijackSec = tonumber( t.holdSec ) or ( ( t.hijackTicks or 320 ) / 40 ),
			raid = raid,
			raidRange = t.range,
			powerReason = reason,
			homeAllies = 0,
		} )
	end
end

function RfsHackBeacon.cl_rfsMsg( self, msg )
	if msg and msg ~= "" then
		pcall( function()
			sm.gui.chatMessage( "[RFS] " .. tostring( msg ) )
			sm.gui.displayAlertText( tostring( msg ), 4 )
		end )
	end
end

function RfsHackBeacon.client_onCreate( self )
	self.cl = self.cl or {}
	self.cl.pd = self.cl.pd or {}
	pcall( function()
		if self.shape and self.shape.id then
			self.cl.beaconKey = tostring( self.shape.id )
		end
	end )
	if type( RfsHackRange ) == "table" then
		RfsHackRange.tearDownBeacon( self )
	end
end

function RfsHackBeacon.client_onDestroy( self )
	if type( RfsHackStatusOverlay ) == "table" and RfsHackStatusOverlay.cl_destroy then
		pcall( function()
			RfsHackStatusOverlay.cl_destroy( self )
		end )
	end
	local key = nil
	if self.cl and self.cl.beaconKey then
		key = tostring( self.cl.beaconKey )
	elseif self.cl and self.cl.pd and self.cl.pd.beaconKey then
		key = tostring( self.cl.pd.beaconKey )
	else
		pcall( function()
			if self.shape and self.shape.id then
				key = tostring( self.shape.id )
			end
		end )
	end
	if not key then
		pcall( function()
			if self.shape then
				key = beaconKey( self.shape )
			end
		end )
	end
	if type( RfsHackRange ) == "table" then
		RfsHackRange.tearDownBeacon( self )
		if key and RfsHackRange.notifyGameOff then
			RfsHackRange.notifyGameOff( key )
		end
	end
	-- Orders GUI is Game-hosted; close if this beacon's menu is still up.
	local game = _G.g_rfsGame
	if game and game.cl and game.cl.rfsOrdersGui and game.cl.rfsOrdersBeaconKey
		and key and tostring( game.cl.rfsOrdersBeaconKey ) == key
		and type( RfsBeaconOrdersGui ) == "table" and type( RfsBeaconOrdersGui.close ) == "function" then
		pcall( function()
			RfsBeaconOrdersGui.close( game )
		end )
	end
end

function RfsHackBeacon.client_onUpdate( self, dt )
	-- Floating HACK: STANDBY / ARMED / ENGAGED / NO POWER. Cheap billboard FX only.
	if type( RfsHackStatusOverlay ) == "table" and RfsHackStatusOverlay.cl_update then
		RfsHackStatusOverlay.cl_update( self, dt )
	end
end

function RfsHackBeacon.client_onFixedUpdate( self, dt )
end

function RfsHackBeacon.client_onClientDataUpdate( self, data )
	self.cl = self.cl or {}
	self.cl.pd = data or {}
	if data and data.beaconKey then
		self.cl.beaconKey = tostring( data.beaconKey )
	end
	if type( RfsHackRange ) == "table" then
		RfsHackRange.tearDownBeacon( self )
	end
end

function RfsHackBeacon.client_getAvailableParentConnectionCount( self, connectionType )
	local LOGIC = sm.interactable.connectionType.logic
	local ELEC = sm.interactable.connectionType.electricity
	local band = nil
	if type( RfsHackPower ) == "table" and RfsHackPower.band then
		band = RfsHackPower.band
	else
		band = function( a, b )
			if type( bit ) == "table" and type( bit.band ) == "function" then
				return bit.band( a, b )
			end
			return a % ( b * 2 ) >= b and b or 0
		end
	end
	-- Battery / Recharge / logic switch as parents.
	if band( connectionType, ELEC ) ~= 0 or band( connectionType, LOGIC ) ~= 0 then
		return 255
	end
	return 0
end

function RfsHackBeacon.client_getAvailableChildConnectionCount( self, connectionType )
	local LOGIC = sm.interactable.connectionType.logic
	local ELEC = sm.interactable.connectionType.electricity
	local band = nil
	if type( RfsHackPower ) == "table" and RfsHackPower.band then
		band = RfsHackPower.band
	else
		band = function( a, b )
			if type( bit ) == "table" and type( bit.band ) == "function" then
				return bit.band( a, b )
			end
			return a % ( b * 2 ) >= b and b or 0
		end
	end
	-- Radio modules (and other elec/logic children) hang off the beacon.
	if band( connectionType, ELEC ) ~= 0 or band( connectionType, LOGIC ) ~= 0 then
		return 255
	end
	return 0
end

-- Client interact uses this so E matches the prompt. Empty cl.pd used to
-- swallow E while canInteract already fell back to publicData.
local function cl_pd( self )
	local pd = {}
	pcall( function()
		local pub = self.interactable:getPublicData()
		if type( pub ) == "table" then
			for k, v in pairs( pub ) do
				pd[k] = v
			end
		end
	end )
	local cd = self.cl and self.cl.pd
	if type( cd ) == "table" then
		for k, v in pairs( cd ) do
			if v ~= nil then
				pd[k] = v
			end
		end
	end
	return pd
end

local function cl_beaconKey( self )
	local id = nil
	pcall( function()
		id = self.shape and self.shape.id
	end )
	if id ~= nil then
		return tostring( id )
	end
	local pd = cl_pd( self )
	if pd.beaconKey then
		return tostring( pd.beaconKey )
	end
	return nil
end

-- rush-base 75abb2f / 3.5f: createGui on this E frame via Game host.
-- Do not require RfsHackOrdersGui — that split left E dead when the module
-- was nil in the beacon sandbox or g_rfsGame was missing.
-- E always opens Orders (empty list / unpowered still). Hijack is Tinker/U.
local function cl_openOrders( self )
	return
end
if false then
	local key = cl_beaconKey( self )
	if not key then
		pcall( function()
			sm.gui.chatMessage( "[RFS] Orders: beacon has no key yet" )
		end )
		return
	end
	pcall( function()
		sm.gui.chatMessage( "[RFS] HACK 3.5f-orders" )
	end )
	local notice = nil
	if not pd.powered then
		if pd.wired then
			notice = "No power: Battery container is empty. Orders still open."
		else
			notice = "No power: wire a Battery container (electricity). Orders still open."
		end
		pcall( function()
			sm.gui.chatMessage( "[RFS] " .. notice )
		end )
	elseif ( tonumber( pd.homeAllies ) or 0 ) <= 0 then
		notice = "No allies yet. Orders list is empty."
		pcall( function()
			sm.gui.chatMessage( "[RFS] " .. notice )
		end )
	end
	local payload = {
		beaconKey = key,
		beaconName = pd.name or "Hack Beacon",
		role = pd.role or "independent",
		masterKey = pd.masterKey,
		range = tonumber( pd.range ) or 16,
		notice = notice,
	}
	pcall( function()
		local pos = self.shape and self.shape.worldPosition
		if pos then
			payload.pos = { x = pos.x, y = pos.y, z = pos.z }
		end
	end )
	local game = _G.g_rfsGame
	if game and type( game.cl_rfs_ordersOpen ) == "function" then
		local ok = pcall( function()
			game:cl_rfs_ordersOpen( payload )
		end )
		if ok then
			return
		end
	end
	pcall( function()
		self.network:sendToServer( "sv_openOrdersGui", payload )
	end )
end

function RfsHackBeacon.client_canInteract( self )
	if type( RfsHackV1 ) == "table" then return RfsHackV1.canInteract( self ) end
	return false
end

function RfsHackBeacon.client_canTinker( self, character )
	return false
end

function RfsHackBeacon.cl_botTags( self, rows )
end

function RfsHackBeacon.sv_openOrdersGui( self, params, player )
	return
end

function RfsHackBeacon.sv_ordersList( self, params, player )
	return
end

function RfsHackBeacon.sv_setShowRange( self, params, player )
	return
end

function RfsHackBeacon.sv_setMaster( self, params, player )
	if type( RfsHackOrdersGui ) == "table" and type( RfsHackOrdersGui.sv_setMaster ) == "function" then
		return RfsHackOrdersGui.sv_setMaster( self, params, player )
	end
end

function RfsHackBeacon.sv_clearMaster( self, params, player )
	if type( RfsHackOrdersGui ) == "table" and type( RfsHackOrdersGui.sv_clearMaster ) == "function" then
		return RfsHackOrdersGui.sv_clearMaster( self, params, player )
	end
end

function RfsHackBeacon.sv_hackListOpen( self, params, player )
	if type( RfsHackV1 ) == "table" then RfsHackV1.svBeaconOpen( self, params, player ) end
end

function RfsHackBeacon.client_onInteract( self, character, state )
	if type( RfsHackV1 ) == "table" then RfsHackV1.onBeaconInteract( self, character, state ) end
end

function RfsHackBeacon.client_onTinker( self, character, state )
	return
end

function RfsHackBeacon.sv_hijack( self, params, player )
	return
end
if false then
	RfsBotHijack.ensureHooks()
	local shape = self.shape
	if not shape or not sm.exists( shape ) then
		return
	end
	self.sv = self.sv or {}
	self.sv.tier = self.sv.tier or tierOf( shape )
	local t = self.sv.tier
	local key = self.sv.key or beaconKey( shape )

	if not hackDevicesOn() then
		self.network:sendToClients( "cl_hijackResult", { n = 0, range = t.range, name = t.name, disabled = true } )
		return
	end
	if not hackableRobotsOn() then
		self.network:sendToClients( "cl_hijackResult", { n = 0, range = t.range, name = t.name, disabled = true } )
		return
	end

	if not RfsHackPower.isPowered( self ) then
		self.network:sendToClients( "cl_hijackResult", { n = 0, range = t.range, name = t.name, noPower = true } )
		return
	end

	local sources = RfsHackPower.elecContainers( self )
	if player then
		local inv = nil
		pcall( function()
			inv = player:getInventory()
		end )
		if inv and sm.exists( inv ) and RfsHackPower.batteryCount( inv ) > 0 then
			sources[#sources + 1] = inv
		end
	end
	local have = RfsHackPower.totalBatteries( sources )
	if have < 1 then
		self.network:sendToClients( "cl_hijackResult", { n = 0, range = t.range, name = t.name, noBattery = true } )
		return
	end

	local cap = tonumber( t.hackCap ) or ( type( RfsHackCaps ) == "table" and RfsHackCaps.forUuid( tostring( shape.uuid ) ) ) or 2
	local used = 0
	if RfsBotHijack.hackedOntoCount then
		used = RfsBotHijack.hackedOntoCount( key ) or 0
	end
	if RfsBotHijack.pendingCount then
		used = used + ( RfsBotHijack.pendingCount( key ) or 0 )
	end
	local slots = cap - used
	if slots < 1 then
		self.network:sendToClients( "cl_hijackResult", {
			n = 0,
			range = t.range,
			name = t.name,
			atCap = true,
			cap = cap,
		} )
		return
	end

	local pos = shape.worldPosition
	local world = nil
	pcall( function()
		world = shape.body:getWorld()
	end )
	local ownerId = player and player.id or 0
	local useRange = t.range
	pcall( function()
		if RfsBotHijack.effectiveRange then
			useRange = RfsBotHijack.effectiveRange( { range = t.range, pos = pos, world = world } )
		end
	end )
	local maxD2 = useRange * useRange
	local hostiles = {}
	for _, u in ipairs( sm.unit.getAllUnits() ) do
		if sm.exists( u ) and u.character and sm.exists( u.character ) then
			if RfsBotHijack.isRobotCharacter( u.character ) and not RfsBotHijack.isAlly( u ) and RfsBotHijack.isHackable( u ) then
				local okWorld = true
				if world then
					pcall( function()
						okWorld = ( u.character:getWorld() == world )
					end )
				end
				if okWorld then
					local d2 = ( u.character.worldPosition - pos ):length2()
					if d2 <= maxD2 then
						hostiles[#hostiles + 1] = { unit = u, d2 = d2 }
					end
				end
			end
		end
	end
	table.sort( hostiles, function( a, b )
		return a.d2 < b.d2
	end )

	local mode = t.canInfect and "infected" or "tethered"
	local converted = 0
	local workKey = key
	if type( RfsBotHijack.orderDomainMasterKey ) == "function" then
		pcall( function()
			workKey = RfsBotHijack.orderDomainMasterKey( key ) or key
		end )
	end
	for _, row in ipairs( hostiles ) do
		if converted >= have or converted >= slots then
			break
		end
		local ok = RfsBotHijack.convertUnit( row.unit, ownerId, {
			mode = mode,
			beaconKey = key,
			workBeaconKey = workKey,
			hijackTicks = t.hijackTicks or 320,
		} )
		if ok then
			converted = converted + 1
		end
	end

	if converted > 0 then
		local left = converted
		for _ = 1, converted do
			if RfsHackPower.spendOne( self, true ) then
				left = left - 1
			else
				break
			end
		end
		if left > 0 then
			RfsHackPower.spendBatteries( sources, left )
		end
	end
	self.network:sendToClients( "cl_hijackResult", {
		n = converted,
		range = t.range,
		spent = converted,
		name = t.name,
		infected = t.canInfect and true or false,
	} )
end

function RfsHackBeacon.cl_hijackResult( self, data )
	local name = ( data and data.name ) or "Hack Beacon"
	if data and data.disabled then
		sm.gui.chatMessage( "[RFS] " .. name .. ": Disabled by host" )
		return
	end
	if data and data.noPower then
		sm.gui.chatMessage( "[RFS] " .. name .. " needs power — wire a Battery container (electricity) to the beacon (optional switch)" )
		return
	end
	if data and data.noBattery then
		sm.gui.chatMessage( "[RFS] " .. name .. " needs Batteries in the connected container" )
		return
	end
	if data and data.atCap then
		sm.gui.chatMessage( "[RFS] " .. name .. ": hack cap reached (" .. tostring( data.cap or 0 ) .. " bots on this beacon)" )
		return
	end
	local n = ( data and data.n ) or 0
	local range = ( data and data.range ) or 16
	local spent = ( data and data.spent ) or 0
	if n <= 0 then
		sm.gui.chatMessage( "[RFS] " .. name .. ": no hostile robots within " .. tostring( range ) .. " m" )
	elseif data.infected then
		sm.gui.chatMessage( "[RFS] " .. name .. ": permanently infected " .. tostring( n ) .. " robot(s) (−" .. tostring( spent ) .. " Battery)" )
	else
		sm.gui.chatMessage( "[RFS] " .. name .. ": linked " .. tostring( n ) .. " robot(s) (−" .. tostring( spent ) .. " Battery). Keep it powered or they revert." )
	end
end

-- Deep Sleep solo skip: drain in-use beacons by skipped ticks. Existing spendOne.
function RfsHackBeacon.sv_e_rfsSkipDrain( self, params )
	local ticks = tonumber( params and params.ticks ) or 0
	if ticks <= 0 or not self.sv then
		return
	end
	local linked, converting = 0, 0
	pcall( function()
		if type( RfsBotHijack ) == "table" then
			linked = RfsBotHijack.linkedCount( self.sv.key ) or 0
			converting = RfsBotHijack.pendingCount( self.sv.key ) or 0
		end
	end )
	local working = self.sv.powered and ( linked > 0 or converting > 0 )
	if not working then
		return
	end
	if type( RfsHackPower ) ~= "table" or type( RfsHackPower.spendOne ) ~= "function" then
		return
	end
	local uuid = nil
	pcall( function()
		uuid = tostring( self.shape.uuid )
	end )
	local every = 40 * 56
	pcall( function()
		every = RfsHackPower.drainEvery( uuid )
	end )
	if type( every ) ~= "number" or every < ( 40 * 22 ) then
		every = 40 * 56
	end
	local n = math.floor( ticks / every )
	for _ = 1, n do
		if not RfsHackPower.spendOne( self, true ) then
			self.sv.powered = false
			break
		end
	end
end
