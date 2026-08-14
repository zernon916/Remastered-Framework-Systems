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

pcall( function()
	dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )
end )
pcall( function()
	dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsBotHijack.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsFeatures.lua" )
end )

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
	local data = {
		powered = ( not disabled ) and self.sv.powered and true or false,
		disabled = disabled,
		range = t.range,
		name = t.name,
		canInfect = t.canInfect and true or false,
		linked = extra and extra.linked or 0,
		batteries = extra and extra.batteries or 0,
		wired = extra and extra.wired and true or false,
		hijackSec = extra and extra.hijackSec or ( ( t.hijackTicks or 320 ) / 40 ),
		raid = extra and extra.raid and true or false,
		raidRange = extra and extra.raidRange or t.range,
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

function RfsHackBeacon.server_onCreate( self )
	self.sv = self.sv or {}
	self.sv.tier = tierOf( self.shape )
	self.sv.powered = false
	self.sv.drainAcc = 0
	self.sv.key = beaconKey( self.shape )
end

function RfsHackBeacon.server_onDestroy( self )
	if type( RfsBotHijack ) == "table" and self.sv and self.sv.key then
		RfsBotHijack.unregisterBeacon( self.sv.key )
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
				spendOne = function()
					return spendOneBattery( self )
				end,
			} )
		end )
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
		} )
	end
	if ( tick % 2 ) == 0 and type( RfsBotHijack ) == "table" and RfsBotHijack.pendingTagList then
		pcall( function()
			self.network:sendToClients( "cl_botTags", RfsBotHijack.pendingTagList() )
		end )
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

local function cl_updateOverheads()
	local now = 0
	pcall( function()
		now = sm.game.getCurrentTick()
	end )
	if now == g_clBotFxTick then
		return
	end
	g_clBotFxTick = now

	local units = {}
	pcall( function()
		units = sm.unit.getAllUnits() or {}
	end )
	local live = {}
	for _, u in ipairs( units ) do
		if sm.exists( u ) and u.character and sm.exists( u.character ) then
			live[tostring( u.id )] = u
		end
	end

	local seen = {}
	for key, row in pairs( g_clBotTags ) do
		local text = cl_cleanText( row and row.text )
		if text ~= "" then
			local unit = live[key]
			local pos = nil
			if unit then
				pos = cl_headPos( unit.character )
			elseif row.x and row.y and row.z then
				pos = sm.vec3.new( row.x, row.y, row.z ) + WORLD_UP * 1.85
			end
			if pos then
				seen[key] = true
				local fx = cl_ensureFx( key )
				if fx then
					local kind = cl_kindOf( row )
					local col = TAG_COLORS[kind] or TAG_COLORS.hack
					pcall( function()
						if unit then
							local world = unit.character:getWorld()
							if world then
								fx:setWorld( world )
							end
						end
						fx:setParameter( "TextContent", text )
						fx:setParameter( "Color", col )
						fx:setPosition( pos )
						fx:setRotation( cl_billboard( pos ) )
						if not fx:isPlaying() then
							fx:start()
						end
					end )
				end
			end
		end
	end
	for key, _ in pairs( g_clBotFx ) do
		if not seen[key] then
			cl_destroyFx( key )
		end
	end
	-- HUD fallback — world text on NPCs is unreliable; this always shows.
	local hud = nil
	local hudD = nil
	local myPos = nil
	pcall( function()
		myPos = sm.localPlayer.getPlayer().character.worldPosition
	end )
	for key, row in pairs( g_clBotTags ) do
		local text = cl_cleanText( row and row.text )
		if text ~= "" then
			local d2 = 0
			if myPos and row.x and row.y and row.z then
				local p = sm.vec3.new( row.x, row.y, row.z )
				d2 = ( p - myPos ):length2()
			end
			if hud == nil or d2 < hudD then
				hud = text
				hudD = d2
			end
		end
	end
	if hud then
		pcall( function()
			sm.gui.displayAlertText( hud, 1 )
		end )
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
	sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), verb .. " " .. rangeTxt .. " / " .. tostring( sec ) .. "s  (E skip)  " .. tostring( nBat ) .. " Battery" )
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

function RfsHackBeacon.client_onInteract( self, character, state )
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
	for _, row in ipairs( hostiles ) do
		if converted >= have then
			break
		end
		local ok = RfsBotHijack.convertUnit( row.unit, ownerId, {
			mode = mode,
			beaconKey = key,
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
