-- RfsHackBeacon.lua — thin interactable shell.
-- OWNER: class + connections. Apply/convert is RfsHackApply (not this file). Spend / caps / save / range / Orders live in extra files.
-- FROZEN spend is RfsHackPower (idle = no drain; 40*56 / 40*36 / 40*22). Do not retune here.
-- SHOW RANGE is Game-hosted RfsRangeViz via RfsHackRange. Never parent FX onto this interactable.

RfsHackBeacon = class( nil )
RfsHackBeacon.maxParentCount = 2
RfsHackBeacon.maxChildCount = 255
-- Logic + electricity like PlasmaDrill / rush-base. Lua spends 1 bat; always
-- setActive(false) so the engine does not treat this as a motor.
RfsHackBeacon.connectionInput = sm.interactable.connectionType.logic + sm.interactable.connectionType.electricity
RfsHackBeacon.connectionOutput = sm.interactable.connectionType.logic
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
rfsDofile( "Scripts/game/RfsHackSave.lua" )
rfsDofile( "Scripts/game/RfsHackRange.lua" )
rfsDofile( "Scripts/game/RfsBotHijack.lua" )
rfsDofile( "Scripts/game/RfsBotInventory.lua" )
rfsDofile( "Scripts/game/RfsHackApply.lua" )
rfsDofile( "Scripts/game/RfsHackTether.lua" )
rfsDofile( "Scripts/game/RfsFeatures.lua" )
rfsDofile( "Scripts/game/RfsBeaconOrdersGui.lua" )
rfsDofile( "Scripts/game/RfsHackOrdersList.lua" )
rfsDofile( "Scripts/game/RfsHackOrdersGui.lua" )

-- uuid → tier. Infect ticks = game ticks in an Infection Beacon field to go permanent.
-- Battery drain lives in RfsHackPower.DRAIN_EVERY. Caps live in RfsHackCaps.
local TIERS = {
	["b4e8c1a0-7d2f-4a91-9c3e-29f1a8d6b5e7"] = {
		name = "Hack Beacon",
		range = 16,
		canInfect = false,
		hijackTicks = 40 * 8,
		infectTicks = 0,
		ringColor = sm.color.new( 0.95, 0.35, 0.12, 1.0 ),
	},
	["c5f9d2b1-8e30-4ba2-ad4f-30a2b9e7c6f8"] = {
		name = "Control Beacon",
		range = 32,
		canInfect = false,
		hijackTicks = 40 * 5,
		infectTicks = 0,
		ringColor = sm.color.new( 0.95, 0.55, 0.10, 1.0 ),
	},
	["d6a0e3c2-9f41-4cb3-be50-41b3c0f8d709"] = {
		name = "Infection Beacon",
		range = 48,
		canInfect = true,
		hijackTicks = 40 * 3,
		infectTicks = 40 * 8,
		ringColor = sm.color.new( 0.55, 0.95, 0.25, 1.0 ),
	},
	-- Station Core visual swap uuid: keep identical hack behavior/menu binding.
	["c2f158b0-4d7e-4a19-9c6b-8e3a1f50d247"] = {
		name = "Hack Beacon",
		range = 16,
		canInfect = false,
		hijackTicks = 40 * 8,
		infectTicks = 0,
		ringColor = sm.color.new( 0.95, 0.35, 0.12, 1.0 ),
	},
}

local function tierOf( shape )
	local id = tostring( shape.uuid )
	local t = TIERS[id] or TIERS["b4e8c1a0-7d2f-4a91-9c3e-29f1a8d6b5e7"]
	local out = {}
	for k, v in pairs( t ) do
		out[k] = v
	end
	out.hackCap = ( type( RfsHackCaps ) == "table" and RfsHackCaps.forUuid( id ) ) or 2
	out.drainEvery = ( type( RfsHackPower ) == "table" and RfsHackPower.drainEvery( id ) ) or ( 40 * 56 )
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
	local data = {
		powered = ( not disabled ) and self.sv.powered and true or false,
		disabled = disabled,
		range = t.range,
		name = t.name,
		canInfect = t.canInfect and true or false,
		linked = extra and extra.linked or 0,
		converting = extra and extra.converting or 0,
		homeAllies = ( extra and extra.homeAllies ~= nil ) and extra.homeAllies or homeAllies,
		batteries = extra and extra.batteries or 0,
		wired = extra and extra.wired and true or false,
		hijackSec = extra and extra.hijackSec or ( ( t.hijackTicks or 320 ) / 40 ),
		raid = extra and extra.raid and true or false,
		raidRange = extra and extra.raidRange or t.range,
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
	self.sv.tier = tierOf( self.shape )
	self.sv.powered = false
	self.sv.drainAcc = 0
	self.sv.key = beaconKey( self.shape )
	pcall( function()
		self.interactable:setActive( false )
	end )
	if type( RfsBotHijack ) == "table" and self.sv.key then
		RfsBotHijack.beaconScripts = RfsBotHijack.beaconScripts or {}
		RfsBotHijack.beaconScripts[tostring( self.sv.key )] = self
	end
	if type( RfsHackTether ) == "table" then
		pcall( function()
			RfsHackTether.ensureHooks()
		end )
	end
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
	self.sv.tier = self.sv.tier or tierOf( self.shape )
	local shape = self.shape
	if not shape or not sm.exists( shape ) then
		return
	end
	-- Every tick, not only publish (every 10). Never an electrical motor load.
	pcall( function()
		self.interactable:setActive( false )
	end )
	self.sv.key = self.sv.key or beaconKey( shape )
	if type( RfsBotHijack ) == "table" and self.sv.key then
		RfsBotHijack.beaconScripts = RfsBotHijack.beaconScripts or {}
		RfsBotHijack.beaconScripts[tostring( self.sv.key )] = self
	end
	local devicesOn = hackDevicesOn()
	local wasPowered = self.sv.powered and true or false

	if not devicesOn then
		self.sv.powered = false
		self.sv.drainAcc = 0
		if type( RfsBotHijack ) == "table" and self.sv.key then
			pcall( function()
				RfsBotHijack.unregisterBeacon( self.sv.key )
			end )
			pcall( function()
				RfsBotHijack.ensureHooks()
			end )
		end
		local tickOff = 0
		pcall( function()
			tickOff = sm.game.getCurrentTick()
		end )
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
	local linked = 0
	local converting = 0
	if type( RfsBotHijack ) == "table" then
		local world = nil
		pcall( function()
			world = shape.body:getWorld()
		end )
		local ownerId = 0
		pcall( function()
			local players = sm.player.getAllPlayers()
			if players and players[1] then
				ownerId = players[1].id or 0
			end
		end )
		pcall( function()
			RfsBotHijack.registerBeacon( self.sv.key, {
				key = self.sv.key,
				pos = shape.worldPosition,
				world = world,
				range = t.range,
				canInfect = t.canInfect,
				hackCap = t.hackCap or ( type( RfsHackCaps ) == "table" and RfsHackCaps.forUuid( tostring( shape.uuid ) ) ) or 2,
				hijackTicks = t.hijackTicks or ( 40 * 8 ),
				infectTicks = t.infectTicks,
				powered = self.sv.powered,
				name = t.name,
				ownerId = ownerId,
				role = self.sv.role or "independent",
				masterKey = self.sv.masterKey,
				canSpendOne = function()
					return RfsHackPower.canSpendOne( self )
				end,
				spendOne = function()
					-- Safety net: at most 1 Lua battery per 20 ticks (0.5 s) per beacon.
					self.sv = self.sv or {}
					local now = 0
					pcall( function()
						now = sm.game.getCurrentTick()
					end )
					local last = tonumber( self.sv.luaSpendTick )
					if last and ( now - last ) < 20 then
						return false
					end
					local ok = RfsHackPower.spendOne( self, true )
					if ok then
						self.sv.luaSpendTick = now
					end
					return ok
				end,
			} )
		end )
		if RfsBotHijack.applyBeaconRoleState then
			local prevRole = self.sv.role
			local prevMaster = self.sv.masterKey
			local newRole, newMaster = RfsBotHijack.applyBeaconRoleState(
				self.sv.key,
				self.sv.role,
				self.sv.masterKey
			)
			self.sv.role = newRole or "independent"
			self.sv.masterKey = newMaster
			if prevRole ~= self.sv.role or tostring( prevMaster or "" ) ~= tostring( newMaster or "" ) then
				if type( RfsHackSave ) == "table" then
					RfsHackSave.saveRole( self )
				end
			end
		end
		if world then
			pcall( function()
				RfsBotHijack.ensureHooks()
				local tnow = sm.game.getCurrentTick()
				if ( tnow % 10 ) == 0 then
					RfsBotHijack.tick( world )
				else
					RfsBotHijack.tickAuto( world )
				end
			end )
		end
		pcall( function()
			linked = RfsBotHijack.linkedCount( self.sv.key ) or 0
		end )
		pcall( function()
			converting = RfsBotHijack.pendingCount( self.sv.key ) or 0
		end )
		local working = self.sv.powered and ( linked > 0 or converting > 0 )
		RfsHackPower.tickWorkDrain( self, working )
	end

	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick()
	end )
	if self.sv.powered ~= wasPowered or ( tick % 10 ) == 0 then
		local boxes = RfsHackPower.elecContainers( self )
		local inRaid = false
		local raidRange = t.range
		pcall( function()
			if type( RfsBotHijack ) ~= "table" or not RfsBotHijack.areaHasRaid then
				return
			end
			local w = nil
			pcall( function()
				w = shape.body:getWorld()
			end )
			inRaid = RfsBotHijack.areaHasRaid( shape.worldPosition, w )
			if inRaid and RfsBotHijack.effectiveRange then
				raidRange = RfsBotHijack.effectiveRange( { range = t.range, pos = shape.worldPosition, world = w } )
			end
		end )
		publish( self, {
			linked = linked,
			converting = converting,
			batteries = RfsHackPower.totalBatteries( boxes ),
			wired = #boxes > 0,
			hijackSec = ( t.hijackTicks or 320 ) / 40,
			raid = inRaid,
			raidRange = raidRange,
			homeAllies = ( type( RfsBotHijack ) == "table" and RfsBotHijack.homeAllyCount and RfsBotHijack.homeAllyCount( self.sv.key ) ) or 0,
		} )
		if type( RfsBotHijack ) == "table" and RfsBotHijack.isRangeVisible
			and self.sv.key and RfsBotHijack.isRangeVisible( self.sv.key ) then
			if type( RfsHackRange ) == "table" then
				RfsHackRange.push( self, true, { tier = t } )
			end
		end
	end
	if type( RfsBotHijack ) == "table" and RfsBotHijack.pullAnnounce then
		local msg = RfsBotHijack.pullAnnounce()
		if msg then
			pcall( function()
				self.network:sendToClients( "cl_rfsMsg", msg )
			end )
		end
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
	pcall( function()
		if type( RfsBotHijack ) == "table" and RfsBotHijack.ensureCharHooks then
			RfsBotHijack.ensureCharHooks()
		end
	end )
	if type( RfsHackRange ) == "table" then
		RfsHackRange.tearDownBeacon( self )
	end
end

function RfsHackBeacon.client_onDestroy( self )
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
	pcall( function()
		if type( RfsBotHijack ) == "table" and RfsBotHijack.ensureCharHooks then
			RfsBotHijack.ensureCharHooks()
		end
	end )
	if type( RfsHackRange ) == "table" then
		RfsHackRange.tearDownBeacon( self )
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
	if type( RfsHackPower ) ~= "table" then
		return 0
	end
	local LOGIC = RfsHackPower.LOGIC
	local ELEC = RfsHackPower.ELEC
	if RfsHackPower.band( connectionType, ELEC ) ~= 0 then
		return 1 - #self.interactable:getParents( ELEC )
	end
	if RfsHackPower.band( connectionType, LOGIC ) ~= 0 then
		return 1 - #self.interactable:getParents( LOGIC )
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
	local pd = cl_pd( self )
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
	local pd = cl_pd( self )
	if pd.disabled then
		sm.gui.setInteractionText( "", "", "Disabled by host" )
		return true
	end
	local name = pd.name or "Hack Beacon"
	local homeN = tonumber( pd.homeAllies ) or 0
	local useKey = sm.gui.getKeyBinding( "Use", true )
	local role = tostring( pd.role or "independent" )
	local roleTxt = ""
	if role == "master" then
		roleTxt = " [MASTER]"
	elseif role == "slave" then
		roleTxt = " [SLAVE]"
	end
	if not pd.powered then
		local hint = "Orders (no power) - wire a Battery container"
		if pd.wired then
			hint = "Orders (no power) - Battery container is empty"
		end
		sm.gui.setInteractionText( "", useKey, hint .. roleTxt .. " - " .. name )
		return true
	end
	sm.gui.setInteractionText(
		"",
		useKey,
		"Orders (" .. tostring( homeN ) .. " allies)" .. roleTxt .. " - " .. name
	)
	return true
end

function RfsHackBeacon.client_canTinker( self, character )
	local pd = cl_pd( self )
	if pd.disabled or not pd.powered then
		return false
	end
	-- Hijack is U/Tinker (E always opens Orders, including empty).
	local nBat = tonumber( pd.batteries ) or 0
	local sec = tonumber( pd.hijackSec ) or 8
	local verb = pd.canInfect and "Auto-infect" or "Auto-hijack"
	local range = pd.range or 16
	local rangeTxt = tostring( range ) .. " m"
	if pd.raid then
		rangeTxt = tostring( math.floor( ( tonumber( pd.raidRange ) or ( range * 0.5 ) ) + 0.5 ) ) .. " m RAID"
	end
	sm.gui.setInteractionText(
		"",
		sm.gui.getKeyBinding( "Tinker", true ),
		verb .. " " .. rangeTxt .. " / " .. tostring( sec ) .. "s  " .. tostring( nBat ) .. " Battery"
	)
	return true
end

function RfsHackBeacon.cl_botTags( self, rows )
end

function RfsHackBeacon.sv_openOrdersGui( self, params, player )
	if type( RfsHackOrdersGui ) == "table" and type( RfsHackOrdersGui.sv_openOrdersGui ) == "function" then
		return RfsHackOrdersGui.sv_openOrdersGui( self, params, player )
	end
	params = params or {}
	pcall( function()
		sm.event.sendToGame( "sv_rfs_ordersScheduleOpen", {
			player = player,
			beaconKey = params.beaconKey or ( self.sv and self.sv.key ),
			beaconName = params.beaconName,
			role = params.role,
			masterKey = params.masterKey,
			range = params.range,
			rows = params.rows,
			pos = params.pos,
			notice = params.notice,
		} )
	end )
end

function RfsHackBeacon.sv_ordersList( self, params, player )
	if type( RfsHackOrdersGui ) == "table" and type( RfsHackOrdersGui.sv_ordersList ) == "function" then
		return RfsHackOrdersGui.sv_ordersList( self, params, player )
	end
end

function RfsHackBeacon.sv_setShowRange( self, params, player )
	if type( RfsHackOrdersGui ) == "table" and type( RfsHackOrdersGui.sv_setShowRange ) == "function" then
		return RfsHackOrdersGui.sv_setShowRange( self, params, player )
	end
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

function RfsHackBeacon.client_onInteract( self, character, state )
	-- Pre-Close-fix (9cbdbc1): open on E-press. Panel stayed open that way.
	if not state then
		return
	end
	local pd = cl_pd( self )
	if pd.disabled then
		pcall( function()
			sm.gui.chatMessage( "[RFS] Beacon disabled by host" )
		end )
		return
	end
	-- Always open Orders (empty / unpowered still). Hijack is Tinker/U.
	cl_openOrders( self )
end

function RfsHackBeacon.client_onTinker( self, character, state )
	if not state then
		return
	end
	self.network:sendToServer( "sv_hijack", {} )
end

function RfsHackBeacon.sv_hijack( self, params, player )
	if type( RfsBotHijack ) ~= "table" then
		return
	end
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
