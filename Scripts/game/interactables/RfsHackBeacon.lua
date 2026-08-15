-- RfsHackBeacon.lua — computer source for hijacked robots.
-- Wire a Battery container (electricity). Optional logic switch as on/off.
-- Unpowered / out of range → tethered bots revert. Infection Beacon can submit permanently.

RfsHackBeacon = class( nil )
RfsHackBeacon.maxParentCount = 2
RfsHackBeacon.maxChildCount = 255
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
rfsDofile( "Scripts/game/RfsBotHijack.lua" )
rfsDofile( "Scripts/game/RfsFeatures.lua" )
rfsDofile( "Scripts/game/RfsBeaconOrdersGui.lua" )

local BATTERY_UUID = sm.uuid.new( "910a7f2c-52b0-46eb-8873-ad13255539af" )
if type( ITEMS ) == "table" and ITEMS.obj_consumable_battery then
	BATTERY_UUID = ITEMS.obj_consumable_battery
end
local LOGIC = sm.interactable.connectionType.logic
local ELEC = sm.interactable.connectionType.electricity

local function band( a, b )
	if type( bit ) == "table" and type( bit.band ) == "function" then
		return bit.band( a, b )
	end
	return a % ( b * 2 ) >= b and b or 0
end

-- uuid → tier. Infect ticks = game ticks in an Infection Beacon field to go permanent.
-- Battery drain (work only): 1 Battery every drainEvery ticks while tethered bots
-- are linked OR auto-hijack is converting. Idle powered = no drain (same idea as
-- ElectricEngine at rest / PlasmaDrill with logic off). Cadence vs PlasmaDrill
-- (2400 pts/bat @ 1/tick ≈ 60 s/bat while drilling): Hack ≈ drill, higher tiers faster.
local TIERS = {
	["b4e8c1a0-7d2f-4a91-9c3e-29f1a8d6b5e7"] = {
		name = "Hack Beacon",
		range = 16,
		canInfect = false,
		hijackTicks = 40 * 8,
		infectTicks = 0,
		drainEvery = 40 * 56, -- ~56 s/bat while working (~PlasmaDrill)
		ringColor = sm.color.new( 0.95, 0.35, 0.12, 1.0 ),
	},
	["c5f9d2b1-8e30-4ba2-ad4f-30a2b9e7c6f8"] = {
		name = "Control Beacon",
		range = 32,
		canInfect = false,
		hijackTicks = 40 * 5,
		infectTicks = 0,
		drainEvery = 40 * 36, -- ~36 s/bat while working
		ringColor = sm.color.new( 0.95, 0.55, 0.10, 1.0 ),
	},
	["d6a0e3c2-9f41-4cb3-be50-41b3c0f8d709"] = {
		name = "Infection Beacon",
		range = 48,
		canInfect = true,
		hijackTicks = 40 * 3,
		infectTicks = 40 * 8,
		drainEvery = 40 * 22, -- ~22 s/bat while working
		ringColor = sm.color.new( 0.55, 0.95, 0.25, 1.0 ),
	},
}

local function tierOf( shape )
	local id = tostring( shape.uuid )
	return TIERS[id] or TIERS["b4e8c1a0-7d2f-4a91-9c3e-29f1a8d6b5e7"]
end

local function beaconKey( shape )
	local id = nil
	pcall( function() id = shape.id end )
	if id ~= nil then
		return tostring( id )
	end
	return tostring( shape )
end

local function batteryCount( container )
	if not container or not sm.exists( container ) then
		return 0
	end
	local ok, qty = pcall( sm.container.totalQuantity, container, BATTERY_UUID )
	if ok and type( qty ) == "number" then
		return qty
	end
	return 0
end

local function addContainer( list, seen, container )
	if not container or not sm.exists( container ) then
		return
	end
	local id = tostring( container )
	pcall( function()
		id = tostring( container:getId() )
	end )
	if seen[id] then
		return
	end
	seen[id] = true
	list[#list + 1] = container
end

local function containersFromInteractable( ia, list, seen )
	if not ia or not sm.exists( ia ) then
		return
	end
	if type( sm.pipeGraph ) == "table" and type( sm.pipeGraph.getMatchingPipedContainers ) == "function" then
		local okPipe, piped = pcall( sm.pipeGraph.getMatchingPipedContainers, ia )
		if okPipe and type( piped ) == "table" then
			for _, c in ipairs( piped ) do
				addContainer( list, seen, c )
			end
		end
	end
	for _, idx in ipairs( { 0, 1 } ) do
		local ok, c = pcall( function()
			return ia:getContainer( idx )
		end )
		if ok then
			addContainer( list, seen, c )
		end
	end
	local okShape, shape = pcall( function()
		return ia.shape or ia:getShape()
	end )
	if okShape and shape and sm.exists( shape ) then
		local ok2, c2 = pcall( function()
			return shape.interactable:getContainer( 0 )
		end )
		if ok2 then
			addContainer( list, seen, c2 )
		end
	end
end

local function isElectricityNode( ia )
	if not ia or not sm.exists( ia ) then
		return false
	end
	local ok, has = pcall( function()
		return ia:hasOutputType( ELEC )
	end )
	if ok and has then
		return true
	end
	local okIn, hasIn = pcall( function()
		return ia:hasInputType( ELEC )
	end )
	return okIn and hasIn and true or false
end

local function elecContainers( self )
	local list, seen = {}, {}
	local nodes = {}
	pcall( function()
		for _, p in ipairs( self.interactable:getParents() or {} ) do
			nodes[#nodes + 1] = p
		end
	end )
	pcall( function()
		for _, c in ipairs( self.interactable:getChildren() or {} ) do
			nodes[#nodes + 1] = c
		end
	end )
	for _, ia in ipairs( nodes ) do
		containersFromInteractable( ia, list, seen )
	end
	return list
end

local function totalBatteries( containers )
	local n = 0
	for _, c in ipairs( containers ) do
		n = n + batteryCount( c )
	end
	return n
end

local function spendBatteries( containers, count )
	local left = count
	for _, container in ipairs( containers ) do
		if left <= 0 then
			break
		end
		local have = batteryCount( container )
		local take = math.min( have, left )
		if take > 0 then
			-- Prefer transaction spend (vanilla util path); fall back to direct.
			local spent = false
			local okTx = pcall( function()
				if sm.container.beginTransaction() then
					local n = sm.container.spend( container, BATTERY_UUID, take, false )
					if n == take and sm.container.endTransaction() then
						spent = true
					else
						sm.container.abortTransaction()
					end
				end
			end )
			if not ( okTx and spent ) then
				local ok = pcall( sm.container.spend, container, BATTERY_UUID, take, true )
				spent = ok and true or false
			end
			if spent then
				left = left - take
			end
		end
	end
	return left == 0
end

local function logicAllows( self )
	local parents = {}
	pcall( function()
		parents = self.interactable:getParents( LOGIC ) or {}
	end )
	local switches = 0
	for _, p in ipairs( parents ) do
		if p and sm.exists( p ) then
			local isLogic = false
			pcall( function()
				isLogic = p:hasOutputType( LOGIC ) and not p:hasOutputType( ELEC )
			end )
			if isLogic then
				switches = switches + 1
				local ok, active = pcall( function()
					return p:isActive()
				end )
				if ok and active then
					return true
				end
			end
		end
	end
	return switches == 0
end

local function fuelConsumptionOn()
	local on = true
	pcall( function()
		on = sm.game.getEnableFuelConsumption()
	end )
	return on
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

-- Real 1-battery spend matching ElectricEngine / PlasmaDrill (TryConsumePowerResource).
local function spendOneBattery( self )
	if not fuelConsumptionOn() then
		return true
	end
	if type( TryConsumePowerResource ) == "function" then
		local ok, result = pcall( TryConsumePowerResource, self.interactable, BATTERY_UUID, ELEC, 1 )
		-- PowerConsumeType.resource == 2 (util.lua); also accept boolean true.
		if ok and ( result == 2 or result == true or ( type( PowerConsumeType ) == "table" and result == PowerConsumeType.resource ) ) then
			return true
		end
	end
	return spendBatteries( elecContainers( self ), 1 )
end

local function hasElectricityNeighbor( self )
	local lists = {}
	pcall( function()
		lists[#lists + 1] = self.interactable:getParents() or {}
	end )
	pcall( function()
		lists[#lists + 1] = self.interactable:getChildren() or {}
	end )
	for _, group in ipairs( lists ) do
		for _, ia in ipairs( group ) do
			if isElectricityNode( ia ) then
				return true
			end
		end
	end
	return false
end

local function containerHasAnything( container )
	if not container or not sm.exists( container ) then
		return false
	end
	local okEmpty, empty = pcall( function()
		return container:isEmpty()
	end )
	if okEmpty then
		return not empty
	end
	local okSize, size = pcall( function()
		return container:getSize()
	end )
	if okSize and type( size ) == "number" then
		for i = 0, size - 1 do
			local okItem, item = pcall( function()
				return container:getItem( i )
			end )
			if okItem and item and item.quantity and item.quantity > 0 then
				return true
			end
		end
	end
	return batteryCount( container ) > 0
end

local function isPowered( self )
	if not logicAllows( self ) then
		return false
	end
	-- Fuel/battery consumption off (creative): wire to electricity is enough.
	if not fuelConsumptionOn() then
		return hasElectricityNeighbor( self ) or totalBatteries( elecContainers( self ) ) > 0
	end
	local containers = elecContainers( self )
	if totalBatteries( containers ) > 0 then
		return true
	end
	if type( CanSpendFromConnectedContainer ) == "function" then
		local parents = {}
		pcall( function()
			parents = self.interactable:getParents() or {}
		end )
		for _, p in ipairs( parents ) do
			local ok, can = pcall( CanSpendFromConnectedContainer, p, BATTERY_UUID, 1 )
			if ok and can then
				return true
			end
		end
	end
	-- No Batteries left → unpowered (do not fake-power on empty wire).
	return false
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
		homeAllies = ( extra and extra.homeAllies ~= nil ) and extra.homeAllies or homeAllies,
		batteries = extra and extra.batteries or 0,
		wired = extra and extra.wired and true or false,
		hijackSec = extra and extra.hijackSec or ( ( t.hijackTicks or 320 ) / 40 ),
		raid = extra and extra.raid and true or false,
		raidRange = extra and extra.raidRange or t.range,
		beaconKey = self.sv and self.sv.key or nil,
		role = role,
		masterKey = masterKey,
		-- Orders GUI SHOW RANGE — mirrored from RfsBotHijack.rangeVisible (Game client
		-- and interactable client may not share the same _G table).
		showRange = ( type( RfsBotHijack ) == "table" and RfsBotHijack.isRangeVisible
			and self.sv and self.sv.key and RfsBotHijack.isRangeVisible( self.sv.key ) ) and true or false,
	}
	pcall( function()
		self.network:setClientData( data )
	end )
	pcall( function()
		self.interactable:setPublicData( data )
	end )
	pcall( function()
		self.interactable:setActive( self.sv.powered and true or false )
	end )
end

local function saveBeaconRole( self )
	if not self or not self.storage then
		return
	end
	pcall( function()
		self.storage:save( {
			role = self.sv and self.sv.role or "independent",
			masterKey = self.sv and self.sv.masterKey or nil,
		} )
	end )
end

function RfsHackBeacon.server_onCreate( self )
	self.sv = self.sv or {}
	local loaded = nil
	pcall( function()
		loaded = self.storage:load()
	end )
	if type( loaded ) == "table" then
		self.sv.role = loaded.role or "independent"
		self.sv.masterKey = loaded.masterKey
	else
		self.sv.role = "independent"
		self.sv.masterKey = nil
	end
	self.sv.tier = tierOf( self.shape )
	self.sv.powered = false
	self.sv.drainAcc = 0
	self.sv.key = beaconKey( self.shape )
	if type( RfsBotHijack ) == "table" and self.sv.key then
		RfsBotHijack.beaconScripts = RfsBotHijack.beaconScripts or {}
		RfsBotHijack.beaconScripts[tostring( self.sv.key )] = self
	end
end

function RfsHackBeacon.server_onDestroy( self )
	if type( RfsBotHijack ) == "table" and self.sv and self.sv.key then
		local key = tostring( self.sv.key )
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
	self.sv = self.sv or {}
	self.sv.tier = self.sv.tier or tierOf( self.shape )
	local shape = self.shape
	if not shape or not sm.exists( shape ) then
		return
	end
	self.sv.key = self.sv.key or beaconKey( shape )
	if type( RfsBotHijack ) == "table" and self.sv.key then
		RfsBotHijack.beaconScripts = RfsBotHijack.beaconScripts or {}
		RfsBotHijack.beaconScripts[tostring( self.sv.key )] = self
	end
	local devicesOn = hackDevicesOn()
	local wasPowered = self.sv.powered and true or false

	-- Host disabled: shape may still exist (B&P pack) but RFS hijack behavior no-ops.
	-- Hooks stay installed elsewhere; do not spend battery.
	if not devicesOn then
		self.sv.powered = false
		self.sv.drainAcc = 0
		if type( RfsBotHijack ) == "table" and self.sv.key then
			pcall( function()
				RfsBotHijack.unregisterBeacon( self.sv.key )
			end )
			-- Keep hooks warm; HijackHost still ticks allies when robots feature is on.
			pcall( function()
				RfsBotHijack.ensureHooks()
			end )
		end
		local tickOff = 0
		pcall( function()
			tickOff = sm.game.getCurrentTick()
		end )
		if wasPowered or ( tickOff % 10 ) == 0 then
			local boxes = elecContainers( self )
			publish( self, {
				linked = 0,
				batteries = totalBatteries( boxes ),
				wired = #boxes > 0,
			} )
		end
		return
	end

	self.sv.powered = isPowered( self )
	local t = self.sv.tier
	local linked = 0
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
				hijackTicks = t.hijackTicks or ( 40 * 8 ),
				infectTicks = t.infectTicks,
				powered = self.sv.powered,
				name = t.name,
				ownerId = ownerId,
				role = self.sv.role or "independent",
				masterKey = self.sv.masterKey,
				spendOne = function()
					return spendOneBattery( self )
				end,
			} )
		end )
		-- Accept claimMaster demotes / compute Slave while a Master is in range.
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
				saveBeaconRole( self )
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
		local converting = 0
		pcall( function()
			converting = RfsBotHijack.pendingCount( self.sv.key ) or 0
		end )
		-- Work drain: tethered bots linked OR auto-hijack converting. Idle = none.
		local working = self.sv.powered and ( linked > 0 or converting > 0 )
		if working then
			self.sv.drainAcc = ( self.sv.drainAcc or 0 ) + 1
			if self.sv.drainAcc >= ( t.drainEvery or 1200 ) then
				self.sv.drainAcc = 0
				if not spendOneBattery( self ) then
					self.sv.powered = false
				else
					self.sv.powered = isPowered( self )
				end
			end
		else
			self.sv.drainAcc = 0
		end
	end

	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick()
	end )
	if self.sv.powered ~= wasPowered or ( tick % 10 ) == 0 then
		local boxes = elecContainers( self )
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
			batteries = totalBatteries( boxes ),
			wired = #boxes > 0,
			hijackSec = ( t.hijackTicks or 320 ) / 40,
			raid = inRaid,
			raidRange = raidRange,
			homeAllies = ( type( RfsBotHijack ) == "table" and RfsBotHijack.homeAllyCount and RfsBotHijack.homeAllyCount( self.sv.key ) ) or 0,
		} )
	end
	if ( tick % 2 ) == 0 and type( RfsBotHijack ) == "table" and RfsBotHijack.pendingTagList then
		-- Tags render via character RfsHackText only (no duplicate beacon world FX).
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

local TEXT_FACE = sm.vec3.new( 0, 1, 0 )
local WORLD_UP = sm.vec3.new( 0, 0, 1 )
local OVERHEAD_FX = { "RfsHackText", "RfsGrowText", "DebugText" }
local TAG_COLORS = {
	hack = sm.color.new( 1.0, 0.72, 0.08, 1.0 ),
	drop = sm.color.new( 1.0, 0.28, 0.12, 1.0 ),
	jam = sm.color.new( 1.0, 0.18, 0.18, 1.0 ),
	nobat = sm.color.new( 1.0, 0.35, 0.15, 1.0 ),
}
-- Ground range outline: ring of ShapeRenderable pegs (blk_lights). Readable polygon.
local RING_BLOCK = sm.uuid.new( "073f92af-f37e-4aff-96b3-d66284d5081c" ) -- blk_lights
local RING_SEG_SPACING = 1.75 -- meters along circumference
local RING_SEG_MIN = 24
local RING_SEG_MAX = 72
local g_clBotTags = {}
local g_clBotFx = {}
local g_clBotFxTick = -1
local g_clBeaconN = 0

local function cl_destroyRangeRing( self )
	if not self or not self.cl or not self.cl.rangeRing then
		return
	end
	for _, fx in ipairs( self.cl.rangeRing ) do
		pcall( function()
			if fx and sm.exists( fx ) then
				fx:stop()
				fx:destroy()
			end
		end )
	end
	self.cl.rangeRing = nil
	self.cl.ringRange = nil
end

local function cl_groundZ( x, y, fallbackZ )
	local hit, result
	local ok = pcall( function()
		hit, result = sm.physics.raycast(
			sm.vec3.new( x, y, fallbackZ + 24 ),
			sm.vec3.new( x, y, fallbackZ - 80 )
		)
	end )
	if ok and hit and result and result.pointWorld then
		return result.pointWorld.z + 0.06
	end
	return fallbackZ
end

local function cl_rebuildRangeRing( self, range, color )
	cl_destroyRangeRing( self )
	self.cl = self.cl or {}
	range = tonumber( range ) or 16
	if range < 1 then
		return
	end
	local shape = self.shape
	if not shape or not sm.exists( shape ) then
		return
	end
	local center = shape.worldPosition
	local n = math.floor( ( 2 * math.pi * range ) / RING_SEG_SPACING + 0.5 )
	if n < RING_SEG_MIN then n = RING_SEG_MIN end
	if n > RING_SEG_MAX then n = RING_SEG_MAX end
	local ring = {}
	local col = color or sm.color.new( 0.95, 0.35, 0.12, 1.0 )
	local scale = sm.vec3.new( 0.28, 0.28, 0.08 )
	local world = nil
	pcall( function()
		world = shape.body:getWorld()
	end )
	for i = 0, n - 1 do
		local ang = ( i / n ) * math.pi * 2
		local x = center.x + math.cos( ang ) * range
		local y = center.y + math.sin( ang ) * range
		local z = cl_groundZ( x, y, center.z )
		local ok, fx = pcall( sm.effect.createEffect, "ShapeRenderable" )
		if ok and fx then
			pcall( function()
				if world then
					fx:setWorld( world )
				end
				fx:setParameter( "uuid", RING_BLOCK )
				fx:setParameter( "color", col )
				fx:setScale( scale )
				fx:setPosition( sm.vec3.new( x, y, z ) )
				fx:setRotation( sm.quat.identity() )
				fx:start()
			end )
			ring[#ring + 1] = fx
		end
	end
	self.cl.rangeRing = ring
	self.cl.ringRange = range
end

local function cl_updateRangeRing( self )
	self.cl = self.cl or {}
	local pd = self.cl.pd or {}
	local key = nil
	pcall( function()
		key = self.shape and self.shape.id
	end )
	if key ~= nil then
		key = tostring( key )
	elseif pd.beaconKey then
		key = tostring( pd.beaconKey )
	end
	-- Range ring is opt-in via Orders GUI "Show Range". Prefer networked
	-- clientData.showRange (crosses Game↔interactable sandbox); fall back to _G.
	local show = false
	if pd.showRange == true then
		show = true
	else
		local showMap = _G.g_rfsBeaconRangeVisible
		show = key and type( showMap ) == "table" and showMap[tostring( key )] == true
	end
	if not show then
		cl_destroyRangeRing( self )
		return
	end
	local t = tierOf( self.shape )
	local range = tonumber( pd.range ) or t.range
	if pd.raid then
		range = tonumber( pd.raidRange ) or ( range * 0.5 )
	end
	local color = t.ringColor
	local shape = self.shape
	if not shape or not sm.exists( shape ) then
		return
	end
	local center = shape.worldPosition
	local moved = true
	if self.cl.ringCenter then
		local d = center - self.cl.ringCenter
		moved = d:length2() > 0.04 -- ~0.2 m
	end
	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick()
	end )
	local due = ( self.cl.ringTick or -999 ) + 20 <= tick -- 0.5 s
	if self.cl.ringRange ~= range or self.cl.rangeRing == nil then
		cl_rebuildRangeRing( self, range, color )
		self.cl.ringCenter = center
		self.cl.ringTick = tick
	elseif moved and due then
		-- Re-seat pegs when the beacon moves (lift / vehicle); skip every-frame raycasts.
		cl_rebuildRangeRing( self, range, color )
		self.cl.ringCenter = center
		self.cl.ringTick = tick
	end
end

local function cl_destroyFx( key )
	local rec = g_clBotFx[key]
	if rec and rec.fx then
		pcall( function()
			if sm.exists( rec.fx ) then
				rec.fx:stop()
				rec.fx:destroy()
			end
		end )
	end
	g_clBotFx[key] = nil
end

local function cl_destroyAllFx()
	for key, _ in pairs( g_clBotFx ) do
		cl_destroyFx( key )
	end
	g_clBotFx = {}
end

local function cl_billboard( worldPos )
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

local function cl_ensureFx( key )
	local rec = g_clBotFx[key]
	if rec and rec.fx then
		local ok = false
		pcall( function()
			ok = sm.exists( rec.fx ) and ( not rec.fx:hasHost() )
		end )
		if ok then
			return rec.fx
		end
		cl_destroyFx( key )
	end
	for _, name in ipairs( OVERHEAD_FX ) do
		local ok, created = pcall( sm.effect.createEffect, name )
		if ok and created then
			pcall( function()
				created:setParameter( "anchor", "CENTER" )
				created:start()
			end )
			g_clBotFx[key] = { fx = created, name = name, lastText = "" }
			return created
		end
	end
	return nil
end

local function cl_headPos( char )
	local pos = char.worldPosition
	local minA, maxA
	local okAabb = pcall( function()
		minA, maxA = char:getAabb()
	end )
	if okAabb and minA and maxA and maxA.z then
		return sm.vec3.new( ( minA.x + maxA.x ) * 0.5, ( minA.y + maxA.y ) * 0.5, maxA.z + 0.35 )
	end
	return pos + WORLD_UP * 1.85
end

local function cl_kindOf( row )
	if row and row.kind and row.kind ~= "" then
		return row.kind
	end
	local t = ( row and row.text ) or ""
	if string.find( t, "JAM", 1, true ) or string.find( t, "BOOM", 1, true ) then
		return "jam"
	end
	if string.find( t, "DROP", 1, true ) then
		return "drop"
	end
	if string.find( t, "NO BAT", 1, true ) then
		return "nobat"
	end
	return "hack"
end

local function cl_cleanText( text )
	text = tostring( text or "" )
	text = string.gsub( text, "^#%x%x%x%x%x%x", "" )
	return text
end

-- Forward decl: client helpers assigned below.
local cl_openOrders

-- World tags use character-attached RfsHackText only (RfsBotHijack.pushTag).
-- Beacon world FX duplicated HACK/DROP/name text and caused overlaps (incl. with
-- Survival character debug labels like "Balanced"). Keep stubs for RPC compat.
local function cl_updateOverheads()
	-- Tear down any leftover world FX from older HACK builds.
	if next( g_clBotFx ) ~= nil then
		cl_destroyAllFx()
	end
	g_clBotTags = {}
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
	g_clBeaconN = g_clBeaconN + 1
	pcall( function()
		if type( RfsBotHijack ) == "table" and RfsBotHijack.ensureCharHooks then
			RfsBotHijack.ensureCharHooks()
		end
	end )
	pcall( function()
		cl_updateRangeRing( self )
	end )
end

function RfsHackBeacon.client_onDestroy( self )
	cl_destroyRangeRing( self )
	g_clBeaconN = math.max( 0, g_clBeaconN - 1 )
	if g_clBeaconN <= 0 then
		cl_destroyAllFx()
		g_clBotTags = {}
	end
end

function RfsHackBeacon.client_onUpdate( self, dt )
	pcall( function()
		if type( RfsBotHijack ) == "table" and RfsBotHijack.ensureCharHooks then
			RfsBotHijack.ensureCharHooks()
		end
	end )
	cl_updateOverheads()
	pcall( function()
		cl_updateRangeRing( self )
	end )
end

function RfsHackBeacon.client_onFixedUpdate( self, dt )
	cl_updateOverheads()
end

function RfsHackBeacon.client_onClientDataUpdate( self, data )
	self.cl = self.cl or {}
	self.cl.pd = data or {}
	pcall( function()
		cl_updateRangeRing( self )
	end )
end

function RfsHackBeacon.client_getAvailableParentConnectionCount( self, connectionType )
	if band( connectionType, ELEC ) ~= 0 then
		return 1 - #self.interactable:getParents( ELEC )
	end
	if band( connectionType, LOGIC ) ~= 0 then
		return 1 - #self.interactable:getParents( LOGIC )
	end
	return 0
end

function RfsHackBeacon.client_canInteract( self )
	local pd = ( self.cl and self.cl.pd ) or {}
	if not pd.name then
		pcall( function()
			local pub = self.interactable:getPublicData()
			if type( pub ) == "table" then
				pd = pub
			end
		end )
	end
	if pd.disabled then
		sm.gui.setInteractionText( "", "", "Disabled by host" )
		return true
	end
	local name = pd.name or "Hack Beacon"
	local range = pd.range or 16
	if not pd.powered then
		local hint = "no power — connect FROM Battery container TO this beacon"
		if pd.wired then
			hint = "Battery container is empty"
		end
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), name .. " — " .. hint )
		return true
	end
	local nBat = tonumber( pd.batteries ) or 0
	local sec = tonumber( pd.hijackSec ) or 8
	local verb = pd.canInfect and "Auto-infect" or "Auto-hijack"
	local rangeTxt = tostring( range ) .. " m"
	if pd.raid then
		rangeTxt = tostring( math.floor( ( tonumber( pd.raidRange ) or ( range * 0.5 ) ) + 0.5 ) ) .. " m RAID"
	end
	local homeN = tonumber( pd.homeAllies ) or 0
	local useKey = sm.gui.getKeyBinding( "Use", true )
	-- UX: powered → Orders (list + Master/Range). Tinker still hijacks.
	-- No rename/naming menu yet (PENDING Phase 2 polish).
	local role = tostring( pd.role or "independent" )
	local roleTxt = ""
	if role == "master" then
		roleTxt = " [MASTER]"
	elseif role == "slave" then
		roleTxt = " [SLAVE]"
	end
	if homeN > 0 then
		sm.gui.setInteractionText(
			"",
			useKey,
			"Orders (" .. tostring( homeN ) .. " allies)" .. roleTxt .. " — " .. name
		)
	else
		sm.gui.setInteractionText(
			"",
			useKey,
			verb .. " " .. rangeTxt .. roleTxt .. " — " .. tostring( nBat ) .. " Battery"
		)
	end
	return true
end

function RfsHackBeacon.client_canTinker( self, character )
	local pd = ( self.cl and self.cl.pd ) or {}
	if not pd.name then
		pcall( function()
			local pub = self.interactable:getPublicData()
			if type( pub ) == "table" then
				pd = pub
			end
		end )
	end
	if pd.disabled or not pd.powered then
		return false
	end
	local homeN = tonumber( pd.homeAllies ) or 0
	if homeN <= 0 then
		return false
	end
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
	local map = {}
	for _, row in ipairs( rows or {} ) do
		if row and row.key then
			map[tostring( row.key )] = {
				text = cl_cleanText( row.text ),
				kind = cl_kindOf( row ),
				x = row.x,
				y = row.y,
				z = row.z,
			}
		end
	end
	g_clBotTags = map
	cl_updateOverheads()
end

local function cl_beaconKey( self )
	local id = nil
	pcall( function()
		id = self.shape and self.shape.id
	end )
	if id ~= nil then
		return tostring( id )
	end
	local pd = self.cl and self.cl.pd
	if pd and pd.beaconKey then
		return tostring( pd.beaconKey )
	end
	return nil
end

cl_openOrders = function( self )
	-- Pre-Close-fix (9cbdbc1): open immediately on Game so createGui owns
	-- Close/Master/Color. Do NOT open via beacon-sandbox RfsBeaconOrdersGui
	-- (that made Close dead). Server bounce is fallback only.
	local key = cl_beaconKey( self )
	local pd = ( self.cl and self.cl.pd ) or {}
	if not key then
		return
	end
	pcall( function()
		sm.gui.chatMessage( "[RFS] HACK 3.5f-orders" )
	end )
	local payload = {
		beaconKey = key,
		beaconName = pd.name or "Hack Beacon",
		role = pd.role or "independent",
		masterKey = pd.masterKey,
		range = tonumber( pd.range ) or 16,
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
	self.network:sendToServer( "sv_openOrdersGui", payload )
end

local function scheduleOrdersOpenOnGame( player, openData )
	if not player or type( openData ) ~= "table" or not openData.beaconKey then
		return false
	end
	local payload = {
		player = player,
		beaconKey = openData.beaconKey,
		beaconName = openData.beaconName,
		role = openData.role,
		masterKey = openData.masterKey,
		range = openData.range,
		rows = openData.rows,
		pos = openData.pos,
	}
	local game = _G.g_rfsGame
	if game and type( game.sv_rfs_ordersScheduleOpen ) == "function" then
		local ok = pcall( function()
			game:sv_rfs_ordersScheduleOpen( payload )
		end )
		if ok then
			return true
		end
	end
	local okEvent = pcall( function()
		sm.event.sendToGame( "sv_rfs_ordersScheduleOpen", payload )
	end )
	if okEvent then
		return true
	end
	-- Last resort: legacy open-for-player (also schedules on Game).
	okEvent = pcall( function()
		sm.event.sendToGame( "sv_rfs_ordersOpenForPlayer", payload )
	end )
	return okEvent and true or false
end

local function relayOrdersListToPlayer( player, listData )
	if not player or type( listData ) ~= "table" then
		return false
	end
	local game = _G.g_rfsGame
	if game and game.network and game.network.sendToClient then
		local ok = pcall( function()
			game.network:sendToClient( player, "cl_rfs_ordersList", listData )
		end )
		if ok then
			return true
		end
	end
	local okEvent = pcall( function()
		sm.event.sendToGame( "sv_rfs_ordersRelayToPlayer", {
			player = player,
			list = listData,
		} )
	end )
	return okEvent and true or false
end

local function buildOrdersListPayload( self, player )
	local key = self.sv and self.sv.key
	if not key then
		return { rows = {} }
	end
	local ownerFilter = nil
	local allowHost = false
	pcall( function()
		local all = sm.player.getAllPlayers()
		if type( all ) == "table" and all[1] and player then
			local host = all[1]
			local hid, pid = nil, nil
			pcall( function() hid = host.id end )
			pcall( function() pid = player.id end )
			if hid ~= nil and pid ~= nil then
				allowHost = ( hid == pid )
			else
				allowHost = ( host == player )
			end
		end
	end )
	if not allowHost and player then
		pcall( function()
			ownerFilter = player.id
		end )
	end
	local rows = {}
	if type( RfsBotHijack ) == "table" and RfsBotHijack.listHomeAllies then
		pcall( function()
			rows = RfsBotHijack.listHomeAllies( key, ownerFilter ) or {}
		end )
	end
	-- Prompt uses unfiltered domain count. If owner filter emptied the list but
	-- domain still has allies (host misdetect / id mismatch), match the prompt.
	if ( not rows or #rows == 0 ) and type( RfsBotHijack ) == "table" and RfsBotHijack.listHomeAllies then
		local unfiltered = {}
		pcall( function()
			unfiltered = RfsBotHijack.listHomeAllies( key, nil ) or {}
		end )
		if #unfiltered > 0 then
			rows = unfiltered
		end
	end
	-- Mirror listed allies into Game's RfsBotHijack so Color/setOrder RPCs
	-- (which run on Game) can resolve unit keys after a sandbox split.
	pcall( function()
		local snap = {}
		for _, row in ipairs( rows ) do
			if row and row.key and RfsBotHijack.allies then
				local info = RfsBotHijack.allies[tostring( row.key )]
				if info then
					snap[tostring( row.key )] = {
						type = info.type and tostring( info.type ) or nil,
						unitType = info.unitType and tostring( info.unitType ) or nil,
						owner = info.owner,
						mode = info.mode and tostring( info.mode ) or nil,
						beaconKey = info.beaconKey and tostring( info.beaconKey ) or nil,
						workBeaconKey = info.workBeaconKey and tostring( info.workBeaconKey ) or nil,
						controlled = true,
						displayName = info.displayName and tostring( info.displayName ) or nil,
						displayIndex = info.displayIndex ~= nil and tonumber( info.displayIndex ) or nil,
						allyColor = info.allyColor and tostring( info.allyColor ) or nil,
						rfsOrder = type( info.rfsOrder ) == "table" and {
							mode = info.rfsOrder.mode,
							seedUuid = info.rfsOrder.seedUuid and tostring( info.rfsOrder.seedUuid ) or nil,
							beaconKey = info.rfsOrder.beaconKey and tostring( info.rfsOrder.beaconKey ) or nil,
							owner = info.rfsOrder.owner,
						} or nil,
					}
				end
			end
		end
		if next( snap ) then
			sm.event.sendToGame( "sv_rfs_mirrorAllies", { allies = snap } )
		end
	end )
	local role, masterKey = "independent", nil
	if type( RfsBotHijack ) == "table" and RfsBotHijack.effectiveBeaconRole then
		pcall( function()
			role, masterKey = RfsBotHijack.effectiveBeaconRole( key )
		end )
	end
	local t = self.sv and self.sv.tier or tierOf( self.shape )
	return {
		rows = rows,
		beaconKey = tostring( key ),
		beaconName = t and t.name or "Hack Beacon",
		role = role,
		masterKey = masterKey,
	}
end

local function sv_sendOrdersOpen( self, player, params )
	if not player then
		return false
	end
	local t = self.sv and self.sv.tier or tierOf( self.shape )
	local listPayload = buildOrdersListPayload( self, player )
	local data = {
		beaconKey = self.sv and self.sv.key or ( params and params.beaconKey ),
		beaconName = ( params and params.beaconName ) or listPayload.beaconName or ( t and t.name ) or "Hack Beacon",
		role = listPayload.role or "independent",
		masterKey = listPayload.masterKey,
		range = t and t.range or 16,
		rows = listPayload.rows,
		pos = params and params.pos or nil,
	}
	if not data.pos then
		pcall( function()
			local pos = self.shape and self.shape.worldPosition
			if pos then
				data.pos = { x = pos.x, y = pos.y, z = pos.z }
			end
		end )
	end
	-- Immediate Game client open (pre-schedule era). No pending queue for happy path.
	local game = _G.g_rfsGame
	if game and game.network and game.network.sendToClient then
		local ok = pcall( function()
			game.network:sendToClient( player, "cl_rfs_ordersOpen", data )
		end )
		if ok then
			return true
		end
	end
	return scheduleOrdersOpenOnGame( player, data )
end

function RfsHackBeacon.sv_openOrdersGui( self, params, player )
	if not sv_sendOrdersOpen( self, player, params ) then
		pcall( function()
			self.network:sendToClients( "cl_rfsMsg", "Orders: Game host missing — reopen world / check custom game" )
		end )
	end
end

-- Game GUI refresh path: build list here (beacon env) when Game forwards the key.
function RfsHackBeacon.sv_ordersList( self, params, player )
	local listPayload = buildOrdersListPayload( self, player )
	relayOrdersListToPlayer( player, listPayload )
end

function RfsHackBeacon.sv_setShowRange( self, params, player )
	params = params or {}
	local key = self.sv and self.sv.key
	if not key then
		return
	end
	local show = params.show and true or false
	if type( RfsBotHijack ) == "table" and RfsBotHijack.setRangeVisible then
		RfsBotHijack.setRangeVisible( key, show )
	end
	-- Immediate clientData refresh so the ring appears without waiting a tick.
	pcall( function()
		publish( self, {} )
	end )
end

function RfsHackBeacon.sv_setMaster( self, params, player )
	if not self.sv or not self.sv.key then
		return
	end
	if type( RfsBotHijack ) ~= "table" or not RfsBotHijack.claimMaster then
		return
	end
	-- Ensure we are registered before claim.
	self.sv.role = "master"
	self.sv.masterKey = nil
	local ok, err = RfsBotHijack.claimMaster( self.sv.key )
	if ok then
		self.sv.role = "master"
		self.sv.masterKey = nil
		saveBeaconRole( self )
	end
	local result = {
		ok = ok and true or false,
		msg = ok and nil or tostring( err or "claim failed" ),
		master = ok and true or false,
	}
	local rolePayload = nil
	if ok then
		rolePayload = {
			beaconKey = self.sv.key,
			role = "master",
			masterKey = nil,
		}
	end
	local game = _G.g_rfsGame
	if game and player and game.network then
		pcall( function()
			game.network:sendToClient( player, "cl_rfs_ordersSetResult", result )
			if rolePayload then
				game.network:sendToClient( player, "cl_rfs_ordersRole", rolePayload )
			end
		end )
		return
	end
	if player then
		pcall( function()
			sm.event.sendToGame( "sv_rfs_ordersRelayToPlayer", {
				player = player,
				setResult = result,
				role = rolePayload,
			} )
		end )
	end
end

function RfsHackBeacon.client_onInteract( self, character, state )
	-- Pre-Close-fix (9cbdbc1): open on E-press. Panel stayed open that way.
	if not state then
		return
	end
	local pd = ( self.cl and self.cl.pd ) or {}
	if not pd.powered then
		return
	end
	local homeN = tonumber( pd.homeAllies ) or 0
	if homeN > 0 then
		cl_openOrders( self )
		return
	end
	self.network:sendToServer( "sv_hijack", {} )
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

	-- No convert / no battery spend when host disabled devices or hackable robots.
	if not hackDevicesOn() then
		self.network:sendToClients( "cl_hijackResult", { n = 0, range = t.range, name = t.name, disabled = true } )
		return
	end
	if not hackableRobotsOn() then
		self.network:sendToClients( "cl_hijackResult", { n = 0, range = t.range, name = t.name, disabled = true } )
		return
	end

	if not isPowered( self ) then
		self.network:sendToClients( "cl_hijackResult", { n = 0, range = t.range, name = t.name, noPower = true } )
		return
	end

	local sources = elecContainers( self )
	if player then
		local inv = nil
		pcall( function()
			inv = player:getInventory()
		end )
		if inv and sm.exists( inv ) and batteryCount( inv ) > 0 then
			sources[#sources + 1] = inv
		end
	end
	local have = totalBatteries( sources )
	if have < 1 then
		self.network:sendToClients( "cl_hijackResult", { n = 0, range = t.range, name = t.name, noBattery = true } )
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
	-- New allies home to the Master/Slave order domain (Master key when Slave).
	local workKey = key
	if type( RfsBotHijack.orderDomainMasterKey ) == "function" then
		pcall( function()
			workKey = RfsBotHijack.orderDomainMasterKey( key ) or key
		end )
	end
	for _, row in ipairs( hostiles ) do
		if converted >= have then
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
		-- Prefer vanilla connected-container spend; fall back to source list (incl. inventory).
		local left = converted
		for _ = 1, converted do
			if spendOneBattery( self ) then
				left = left - 1
			else
				break
			end
		end
		if left > 0 then
			spendBatteries( sources, left )
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
		sm.gui.chatMessage( "[RFS] " .. name .. " needs power — connect a Battery container (optional switch)" )
		return
	end
	if data and data.noBattery then
		sm.gui.chatMessage( "[RFS] " .. name .. " needs Batteries in the connected container" )
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
