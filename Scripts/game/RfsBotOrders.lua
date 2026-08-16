-- RfsBotOrders.lua — Rest / Defend (M1) + Hay Farm (M2) + Tote Collect (M3) + Water Oil (M4).
-- Home beacon + jobRadius (tier 16/32/48). Oil search 1.5× when perm-infect Waterbot.
-- Author: DemonsDen126

pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsFeatures.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsBotHijack.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsBotOrdersCollect.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsBotOrdersOil.lua" )
end )

RfsBotOrders = RfsBotOrders or {}

RfsBotOrders.MODE_REST = "rest"
RfsBotOrders.MODE_DEFEND = "defend"
RfsBotOrders.MODE_FARM = "farm" -- M2
RfsBotOrders.MODE_COLLECT = "collect" -- M3
RfsBotOrders.MODE_OIL = "oil" -- M4
RfsBotOrders.MODE_RETURN = "return" -- walk to converting hack device
RfsBotOrders.MODE_STAY = "stay" -- leash / stay near beacon job range
RfsBotOrders.MODE_RECALL = "recall" -- walk to Orders home beacon (not hack device)
RfsBotOrders.MODE_SENTRY = "sentry" -- tapebot ranged sentry

local DEFAULT_MODE = RfsBotOrders.MODE_DEFEND
local DEFAULT_RANGE = 16
local THINK_EVERY = 10 -- ticks
local OIL_RADIUS_MUL = 1.5 -- M4 permanently infected Waterbot only

RfsBotOrders._lastThink = RfsBotOrders._lastThink or -1

local function hackableOn()
	if type( RfsFeatures ) == "table" and type( RfsFeatures.hackableRobotsEnabled ) == "function" then
		local ok, v = pcall( RfsFeatures.hackableRobotsEnabled )
		if ok then
			return v and true or false
		end
	end
	return true
end

local function unitKey( unit )
	if not unit then
		return nil
	end
	local id = nil
	pcall( function()
		id = unit.id
	end )
	if id ~= nil then
		return tostring( id )
	end
	return tostring( unit )
end

local function nowTick()
	local now = 0
	pcall( function()
		now = sm.game.getCurrentTick()
	end )
	return now
end

local function normalizeMode( mode )
	mode = string.lower( tostring( mode or "" ) )
	if mode == "rest" or mode == "idle" or mode == "standdown" then
		return RfsBotOrders.MODE_REST
	end
	if mode == "defend" or mode == "defence" or mode == "guard" then
		return RfsBotOrders.MODE_DEFEND
	end
	if mode == "farm" or mode == "harvest" then
		return RfsBotOrders.MODE_FARM
	end
	if mode == "collect" or mode == "loot" then
		return RfsBotOrders.MODE_COLLECT
	end
	if mode == "oil" or mode == "collectoil" or mode == "collect oil" then
		return RfsBotOrders.MODE_OIL
	end
	if mode == "stay" or mode == "leash" then
		return RfsBotOrders.MODE_STAY
	end
	if mode == "recall" then
		return RfsBotOrders.MODE_RECALL
	end
	if mode == "sentry" then
		return RfsBotOrders.MODE_SENTRY
	end
	if mode == "return" or mode == "home" then
		return RfsBotOrders.MODE_RETURN
	end
	return nil
end

local function allyInfo( unit )
	if type( RfsBotHijack ) ~= "table" or type( RfsBotHijack.allies ) ~= "table" then
		return nil, nil
	end
	local key = unitKey( unit )
	if not key then
		return nil, nil
	end
	return RfsBotHijack.allies[key], key
end

local function beaconLive( rec )
	if type( RfsBotHijack ) == "table" and type( RfsBotHijack.beaconLive ) == "function" then
		local ok, live = pcall( RfsBotHijack.beaconLive, rec )
		if ok then
			return live and true or false
		end
	end
	if not rec then
		return false
	end
	if rec.powered then
		return true
	end
	local now = nowTick()
	return rec.powerHoldUntil ~= nil and now < rec.powerHoldUntil
end

local function typeStrOf( unit )
	local info = allyInfo( unit )
	if info and ( info.unitType or info.type ) then
		return tostring( info.unitType or info.type )
	end
	local t = nil
	pcall( function()
		if unit and unit.character and sm.exists( unit.character ) then
			t = tostring( unit.character:getCharacterType() )
		end
	end )
	return t
end

-- Survival has no unit_waterbot; Totebot Blue is the aquatic / oil-role robot.
local UUID_TOTEBOT_BLUE = "58992f50-ca36-44e1-8c47-4996d89d6a9a"
local UUID_HAYBOT = "c8bfb8f3-7efc-49ac-875a-eb85ac0614db"
local UUID_FARMBOT = "9f4fde94-312f-4417-b13b-84029c5d6b52"

local function sameUuid( a, b )
	if a == nil or b == nil then
		return false
	end
	return string.lower( tostring( a ) ) == string.lower( tostring( b ) )
end

local function isWaterbotType( typeStr )
	typeStr = tostring( typeStr or "" )
	if unit_waterbot and sameUuid( typeStr, unit_waterbot ) then
		return true
	end
	-- Survival water-capable tote (blue) owns Collect Oil (M4), not small Collect.
	if unit_totebot_blue and sameUuid( typeStr, unit_totebot_blue ) then
		return true
	end
	if sameUuid( typeStr, UUID_TOTEBOT_BLUE ) then
		return true
	end
	local lower = string.lower( typeStr )
	if string.find( lower, "waterbot", 1, true ) or string.find( lower, "water_bot", 1, true ) then
		return true
	end
	if string.find( lower, "water", 1, true ) and not string.find( lower, "tote", 1, true ) then
		return true
	end
	return false
end

local function isTotebotType( typeStr )
	typeStr = tostring( typeStr or "" )
	-- Blue / waterbot role is Oil-only (not M3 Collect).
	if isWaterbotType( typeStr ) then
		return false
	end
	local toteGlobals = {
		unit_totebot_green, unit_totebot_red, unit_totebot_yellow, unit_totebot_leaf,
	}
	for _, u in ipairs( toteGlobals ) do
		if u and sameUuid( typeStr, u ) then
			return true
		end
	end
	-- g_totebots may include blue; skip those already classified as water.
	if type( g_totebots ) == "table" then
		for _, u in ipairs( g_totebots ) do
			if u and sameUuid( typeStr, u ) and not isWaterbotType( tostring( u ) ) then
				return true
			end
		end
	end
	local lower = string.lower( typeStr )
	return string.find( lower, "tote", 1, true ) ~= nil
end

local function isHaybotType( typeStr )
	typeStr = tostring( typeStr or "" )
	local lower = string.lower( typeStr )
	-- Farmbot / Big Red is NOT hay — hay owns Farm (M2).
	if unit_farmbot and sameUuid( typeStr, unit_farmbot ) then
		return false
	end
	if sameUuid( typeStr, UUID_FARMBOT ) then
		return false
	end
	if string.find( lower, "farmbot", 1, true ) or string.find( lower, "farm bot", 1, true ) then
		return false
	end
	if unit_haybot and sameUuid( typeStr, unit_haybot ) then
		return true
	end
	if sameUuid( typeStr, UUID_HAYBOT ) then
		return true
	end
	return string.find( lower, "hay", 1, true ) ~= nil
end

local function isInfected( unit )
	local info = allyInfo( unit )
	return info and info.mode == "infected"
end

local function isTapebotType( typeStr )
	typeStr = tostring( typeStr or "" )
	local lower = string.lower( typeStr )
	if string.find( lower, "tape", 1, true ) then
		return true
	end
	if unit_tapebot and sameUuid( typeStr, unit_tapebot ) then
		return true
	end
	return false
end

-- Expose type helpers for GUI / hijack short names.
RfsBotOrders.isWaterbotType = isWaterbotType
RfsBotOrders.isTotebotType = isTotebotType
RfsBotOrders.isHaybotType = isHaybotType
RfsBotOrders.isTapebotType = isTapebotType

-- True if this unit type may run the mode (Rest/Defend always; Collect = tote; Farm = hay; Oil = water).
local function modeAllowedForType( mode, typeStr )
	mode = normalizeMode( mode )
	if not mode then
		return false
	end
	if mode == RfsBotOrders.MODE_REST or mode == RfsBotOrders.MODE_DEFEND or mode == RfsBotOrders.MODE_RETURN
		or mode == RfsBotOrders.MODE_STAY or mode == RfsBotOrders.MODE_RECALL then
		return true
	end
	if mode == RfsBotOrders.MODE_SENTRY then
		return isTapebotType( typeStr )
	end
	if mode == RfsBotOrders.MODE_COLLECT then
		return isTotebotType( typeStr )
	end
	if mode == RfsBotOrders.MODE_FARM then
		return isHaybotType( typeStr )
	end
	if mode == RfsBotOrders.MODE_OIL then
		return isWaterbotType( typeStr )
	end
	return false
end

-- M2 unlock (also set by RfsBotOrdersFarm.install).
RfsBotOrders.farmModeEnabled = true
RfsBotOrders.oilModeEnabled = true

---------------------------------------------------------------------------
-- Home beacon / job radius
---------------------------------------------------------------------------

function RfsBotOrders.homeBeaconKey( unit )
	local info = allyInfo( unit )
	if not info then
		return nil
	end
	if type( RfsBotHijack ) == "table" and type( RfsBotHijack.homeBeaconKey ) == "function" then
		local ok, key = pcall( RfsBotHijack.homeBeaconKey, info )
		if ok and key then
			return tostring( key )
		end
	end
	local key = info.workBeaconKey or ( info.order and info.order.beaconKey ) or ( info.rfsOrder and info.rfsOrder.beaconKey ) or info.beaconKey
	if key then
		return tostring( key )
	end
	return nil
end

function RfsBotOrders.homeBeacon( unit )
	if type( RfsBotHijack ) ~= "table" or type( RfsBotHijack.beacons ) ~= "table" then
		return nil, nil
	end
	local key = RfsBotOrders.homeBeaconKey( unit )
	if key then
		local rec = RfsBotHijack.beacons[key]
		if rec then
			return rec, key
		end
	end
	-- Migration: allies converted before workBeaconKey existed.
	if type( RfsBotHijack.coveringBeacon ) == "function" then
		local rec, bkey = RfsBotHijack.coveringBeacon( unit, true )
		if rec and bkey then
			return rec, tostring( bkey )
		end
	end
	return nil, nil
end

function RfsBotOrders.homeBeaconReady( unit )
	local rec, key = RfsBotOrders.homeBeacon( unit )
	if not rec or not key then
		return false, nil, nil
	end
	if not beaconLive( rec ) then
		return false, rec, key
	end
	if not rec.pos then
		return false, rec, key
	end
	return true, rec, key
end

-- Base beacon tier range (chest deposit always uses this, even for Oil).
function RfsBotOrders.depositRadius( unit )
	local rec = RfsBotOrders.homeBeacon( unit )
	return tonumber( rec and rec.range ) or DEFAULT_RANGE
end

-- Job / search radius = beacon tier range. Oil 1.5× for permanently infected Waterbot.
function RfsBotOrders.jobRadius( unit, mode )
	local r = RfsBotOrders.depositRadius( unit )
	mode = normalizeMode( mode ) or RfsBotOrders.getOrderMode( unit )
	if mode == RfsBotOrders.MODE_OIL and isInfected( unit ) and isWaterbotType( typeStrOf( unit ) ) then
		r = r * OIL_RADIUS_MUL
	end
	return r
end

---------------------------------------------------------------------------
-- Order read / write (ally table + unit.saved.rfsOrder)
---------------------------------------------------------------------------

function RfsBotOrders.getOrder( unit )
	local info = allyInfo( unit )
	if not info then
		return nil
	end
	if type( info.order ) == "table" then
		return info.order
	end
	if type( info.rfsOrder ) == "table" then
		return info.rfsOrder
	end
	return nil
end

function RfsBotOrders.getOrderMode( unit )
	local order = RfsBotOrders.getOrder( unit )
	local mode = order and normalizeMode( order.mode )
	if mode then
		return mode
	end
	return DEFAULT_MODE
end

-- If home beacon missing/unpowered → force Rest (jobs cannot free-roam).
function RfsBotOrders.effectiveMode( unit )
	if not hackableOn() then
		return RfsBotOrders.MODE_REST
	end
	if type( RfsBotHijack ) ~= "table" or not RfsBotHijack.isAlly or not RfsBotHijack.isAlly( unit ) then
		return RfsBotOrders.MODE_REST
	end
	local mode = RfsBotOrders.getOrderMode( unit )
	-- Return walks to the converting device even if the Orders home is unpowered.
	if mode == RfsBotOrders.MODE_RETURN then
		return RfsBotOrders.MODE_RETURN
	end
	if mode == RfsBotOrders.MODE_RECALL then
		return RfsBotOrders.MODE_RECALL
	end
	if mode == RfsBotOrders.MODE_STAY then
		local ready = RfsBotOrders.homeBeaconReady( unit )
		if not ready then
			return RfsBotOrders.MODE_REST
		end
		return RfsBotOrders.MODE_STAY
	end
	if mode == RfsBotOrders.MODE_SENTRY then
		local ready = RfsBotOrders.homeBeaconReady( unit )
		if not ready then
			return RfsBotOrders.MODE_REST
		end
		local t = typeStrOf( unit )
		if modeAllowedForType( mode, t ) then
			return RfsBotOrders.MODE_SENTRY
		end
		return RfsBotOrders.MODE_DEFEND
	end
	local ready = RfsBotOrders.homeBeaconReady( unit )
	if not ready then
		return RfsBotOrders.MODE_REST
	end
	local t = typeStrOf( unit )
	if mode == RfsBotOrders.MODE_COLLECT and modeAllowedForType( mode, t ) then
		return RfsBotOrders.MODE_COLLECT
	end
	if mode == RfsBotOrders.MODE_FARM and modeAllowedForType( mode, t ) then
		return RfsBotOrders.MODE_FARM
	end
	if mode == RfsBotOrders.MODE_OIL and modeAllowedForType( mode, t ) then
		return RfsBotOrders.MODE_OIL
	end
	-- Wrong-type specialty modes → Defend combat clamp.
	if mode == RfsBotOrders.MODE_FARM or mode == RfsBotOrders.MODE_COLLECT or mode == RfsBotOrders.MODE_OIL then
		return RfsBotOrders.MODE_DEFEND
	end
	return mode
end

local function pushOrderToUnit( unit, order )
	if not unit or not sm.exists( unit ) or type( order ) ~= "table" then
		return
	end
	pcall( function()
		sm.event.sendToUnit( unit, "sv_e_rfsOrder", order )
	end )
end

function RfsBotOrders.setOrder( unit, order )
	if not hackableOn() then
		return false, "hackable robots disabled"
	end
	if not unit or not sm.exists( unit ) then
		return false, "gone"
	end
	local info, key = allyInfo( unit )
	if not info or not key then
		return false, "not ally"
	end
	order = type( order ) == "table" and order or {}
	local mode = normalizeMode( order.mode ) or DEFAULT_MODE
	local t = info.unitType or info.type or typeStrOf( unit )
	if not modeAllowedForType( mode, t ) then
		-- Wrong type / unshipped specialty → Rest (do not silently Defend Collect on a haybot).
		if mode ~= RfsBotOrders.MODE_DEFEND and mode ~= RfsBotOrders.MODE_REST then
			mode = RfsBotOrders.MODE_REST
		end
	end
	local beaconKey = order.beaconKey or info.workBeaconKey or info.beaconKey
	if beaconKey then
		beaconKey = tostring( beaconKey )
	end
	local packed = {
		mode = mode,
		seedUuid = order.seedUuid,
		beaconKey = beaconKey,
		owner = order.owner ~= nil and order.owner or info.owner,
	}
	info.order = packed
	info.rfsOrder = packed
	if beaconKey and not info.workBeaconKey then
		info.workBeaconKey = beaconKey
	end
	RfsBotHijack.allies[key] = info
	pushOrderToUnit( unit, packed )
	return true, packed
end

function RfsBotOrders.ensureDefaultOrder( unit, ownerId, opts )
	opts = opts or {}
	local info, key = allyInfo( unit )
	if not info or not key then
		return false
	end
	local workKey = opts.workBeaconKey or opts.beaconKey or info.workBeaconKey or info.beaconKey
	if workKey then
		info.workBeaconKey = tostring( workKey )
	end
	local ord = info.order or info.rfsOrder
	if type( ord ) ~= "table" or not normalizeMode( ord.mode ) then
		ord = {
			mode = DEFAULT_MODE,
			beaconKey = info.workBeaconKey,
			owner = ownerId ~= nil and ownerId or info.owner,
		}
	elseif info.workBeaconKey and not ord.beaconKey then
		ord.beaconKey = info.workBeaconKey
	end
	info.order = ord
	info.rfsOrder = ord
	RfsBotHijack.allies[key] = info
	pushOrderToUnit( unit, ord )
	return true
end

function RfsBotOrders.bindWorkBeacon( unit, beaconKey )
	local info, key = allyInfo( unit )
	if not info or not key or not beaconKey then
		return false
	end
	info.workBeaconKey = tostring( beaconKey )
	local ord = info.order or info.rfsOrder
	if type( ord ) == "table" then
		ord.beaconKey = info.workBeaconKey
		info.order = ord
		info.rfsOrder = ord
	end
	RfsBotHijack.allies[key] = info
	pcall( function()
		sm.event.sendToUnit( unit, "sv_e_rfsIdentity", {
			workBeaconKey = info.workBeaconKey,
			playerAlly = true,
		} )
	end )
	if type( ord ) == "table" then
		pushOrderToUnit( unit, ord )
	end
	return true
end

function RfsBotOrders.listHomeAllies( beaconKey, ownerFilterId )
	if type( RfsBotHijack ) == "table" and type( RfsBotHijack.listHomeAllies ) == "function" then
		local ok, rows = pcall( RfsBotHijack.listHomeAllies, beaconKey, ownerFilterId )
		if ok and type( rows ) == "table" then
			return rows
		end
	end
	return {}
end

-- Role matrix: Rest+Defend all. Farm = hay (M2). Collect = tote (M3). Oil = water/blue (M4).
function RfsBotOrders.modesForType( unitType )
	unitType = tostring( unitType or "" )
	local modes = { RfsBotOrders.MODE_REST, RfsBotOrders.MODE_DEFEND, RfsBotOrders.MODE_RETURN, RfsBotOrders.MODE_STAY, RfsBotOrders.MODE_RECALL }
	local soon = {}
	if isTapebotType( unitType ) then
		modes[#modes + 1] = RfsBotOrders.MODE_SENTRY
	end
	if isWaterbotType( unitType ) then
		modes[#modes + 1] = RfsBotOrders.MODE_OIL
	elseif isHaybotType( unitType ) then
		modes[#modes + 1] = RfsBotOrders.MODE_FARM
	elseif isTotebotType( unitType ) then
		modes[#modes + 1] = RfsBotOrders.MODE_COLLECT
	end
	return modes, soon
end

---------------------------------------------------------------------------
-- Select hook: Rest clears combat; Defend clamps chase to jobRadius
---------------------------------------------------------------------------

local function allUnits( world )
	if world ~= nil then
		local ok, list = pcall( function()
			return sm.unit.getAllUnits( world )
		end )
		if ok and type( list ) == "table" then
			return list
		end
	end
	local ok2, list2 = pcall( function()
		return sm.unit.getAllUnits()
	end )
	if ok2 and type( list2 ) == "table" then
		return list2
	end
	return {}
end

local function closestHostileInJobRadius( selfUnit, homePos, radius )
	if not selfUnit or not selfUnit.character or not homePos or not radius then
		return nil
	end
	local myWorld = nil
	pcall( function()
		myWorld = selfUnit.character:getWorld()
	end )
	local best, bestD2 = nil, nil
	local maxD2 = radius * radius
	for _, u in ipairs( allUnits( myWorld ) ) do
		if sm.exists( u ) and u ~= selfUnit and u.character and sm.exists( u.character ) then
			local okWorld = true
			pcall( function()
				okWorld = ( u.character:getWorld() == myWorld )
			end )
			if okWorld
				and type( RfsBotHijack ) == "table"
				and RfsBotHijack.isRobotCharacter
				and RfsBotHijack.isRobotCharacter( u.character )
				and not ( RfsBotHijack.isAlly and RfsBotHijack.isAlly( u ) ) then
				local pos = u.character.worldPosition
				local dHome2 = ( pos - homePos ):length2()
				if dHome2 <= maxD2 then
					local dBot2 = ( pos - selfUnit.character.worldPosition ):length2()
					if bestD2 == nil or dBot2 < bestD2 then
						best = u.character
						bestD2 = dBot2
					end
				end
			end
		end
	end
	return best
end

local function clearCombatTarget( self )
	self.target = nil
	self.lastTargetPosition = nil
	self.eventTarget = nil
	pcall( function()
		if self.unit and sm.exists( self.unit ) then
			sm.event.sendToUnit( self.unit, "sv_e_receiveTarget", {
				targetCharacter = nil,
				sendingUnit = self.unit,
			} )
		end
	end )
end

-- Called from RfsBotHijack._wrappedSelect when unit is ally (after standDown).
function RfsBotOrders.applySelect( self )
	if not self or not self.unit then
		return false
	end
	if not hackableOn() then
		clearCombatTarget( self )
		return true
	end
	local mode = RfsBotOrders.effectiveMode( self.unit )
	-- Rest + Collect + Farm + Oil + Return: stand down combat; jobs run in sv_think / unit drive.
	if mode == RfsBotOrders.MODE_REST
		or mode == RfsBotOrders.MODE_COLLECT
		or mode == RfsBotOrders.MODE_FARM
		or mode == RfsBotOrders.MODE_OIL
		or mode == RfsBotOrders.MODE_RETURN
		or mode == RfsBotOrders.MODE_STAY
		or mode == RfsBotOrders.MODE_RECALL then
		if type( RfsBotHijack ) == "table" and RfsBotHijack.standDown then
			RfsBotHijack.standDown( self )
		end
		clearCombatTarget( self )
		if mode == RfsBotOrders.MODE_RETURN and type( RfsBotHijack ) == "table"
			and type( RfsBotHijack.driveReturnToHackBeacon ) == "function" then
			pcall( RfsBotHijack.driveReturnToHackBeacon, self )
		end
		if mode == RfsBotOrders.MODE_RECALL and type( RfsBotHijack ) == "table"
			and type( RfsBotHijack.driveRecallToHome ) == "function" then
			pcall( RfsBotHijack.driveRecallToHome, self )
		end
		if mode == RfsBotOrders.MODE_STAY and type( RfsBotHijack ) == "table"
			and type( RfsBotHijack.driveStayAtHome ) == "function" then
			pcall( RfsBotHijack.driveStayAtHome, self )
		end
		if ( mode == RfsBotOrders.MODE_FARM
			or mode == RfsBotOrders.MODE_COLLECT
			or mode == RfsBotOrders.MODE_OIL )
			and type( RfsBotHijack ) == "table"
			and type( RfsBotHijack.driveJobWalk ) == "function" then
			pcall( RfsBotHijack.driveJobWalk, self )
		end
		return true
	end

	-- Defend / Sentry: ally combat vs hostiles, chase clamped to home beacon jobRadius.
	-- Sentry (tapebot) holds the outer ring and still shoots.
	local ready, rec = RfsBotOrders.homeBeaconReady( self.unit )
	if not ready or not rec or not rec.pos then
		if type( RfsBotHijack ) == "table" and RfsBotHijack.standDown then
			RfsBotHijack.standDown( self )
		end
		clearCombatTarget( self )
		return true
	end
	local radius = RfsBotOrders.jobRadius( self.unit, mode )
	local hostile = closestHostileInJobRadius( self.unit, rec.pos, radius )
	if hostile and sm.exists( hostile ) then
		self.target = hostile
		self.lastTargetPosition = hostile.worldPosition
	else
		clearCombatTarget( self )
		if mode == RfsBotOrders.MODE_SENTRY and type( RfsBotHijack ) == "table"
			and type( RfsBotHijack.driveStayAtHome ) == "function" then
			pcall( RfsBotHijack.driveStayAtHome, self )
		end
	end
	return true
end

---------------------------------------------------------------------------
-- Server tick
---------------------------------------------------------------------------

function RfsBotOrders.sv_think( timeStep, game )
	if not hackableOn() then
		return
	end
	if type( RfsBotHijack ) ~= "table" or type( RfsBotHijack.allies ) ~= "table" then
		return
	end
	local now = nowTick()
	if now == RfsBotOrders._lastThink then
		return
	end
	if ( now % THINK_EVERY ) ~= 0 then
		return
	end
	RfsBotOrders._lastThink = now

	for key, info in pairs( RfsBotHijack.allies ) do
		if info and info.controlled then
			-- Sticky home: once workBeaconKey is set it is not overwritten by tether hops.
			if not info.workBeaconKey and info.beaconKey then
				info.workBeaconKey = tostring( info.beaconKey )
			end
			local ord = info.order or info.rfsOrder
			if type( ord ) ~= "table" or not normalizeMode( ord.mode ) then
				ord = {
					mode = DEFAULT_MODE,
					beaconKey = info.workBeaconKey or info.beaconKey,
					owner = info.owner,
				}
			elseif info.workBeaconKey then
				ord.beaconKey = info.workBeaconKey
			end
			info.order = ord
			info.rfsOrder = ord
			RfsBotHijack.allies[key] = info

			-- Resolve live unit for Collect / Farm / Oil job ticks.
			local unit = nil
			if type( RfsBotHijack.unitByKey ) == "function" then
				pcall( function()
					unit = RfsBotHijack.unitByKey( key )
				end )
			end
			if unit and sm.exists( unit ) then
				local mode = RfsBotOrders.effectiveMode( unit )
				if mode == RfsBotOrders.MODE_COLLECT
					and type( RfsBotOrdersCollect ) == "table"
					and type( RfsBotOrdersCollect.sv_tickAlly ) == "function" then
					local ready, rec = RfsBotOrders.homeBeaconReady( unit )
					if ready and rec then
						local radius = RfsBotOrders.jobRadius( unit, mode )
						pcall( RfsBotOrdersCollect.sv_tickAlly, unit, info, rec, radius )
					end
				elseif mode == RfsBotOrders.MODE_FARM then
					local tickFarm = RfsBotOrders.sv_tickFarmAlly
					if type( tickFarm ) ~= "function"
						and type( RfsBotOrdersFarm ) == "table"
						and type( RfsBotOrdersFarm.sv_tickAlly ) == "function" then
						tickFarm = RfsBotOrdersFarm.sv_tickAlly
					end
					if type( tickFarm ) == "function" then
						local ready, rec = RfsBotOrders.homeBeaconReady( unit )
						if ready and rec then
							local radius = RfsBotOrders.jobRadius( unit, mode )
							pcall( tickFarm, unit, info, rec, radius )
						end
					end
				elseif mode == RfsBotOrders.MODE_OIL
					and type( RfsBotOrdersOil ) == "table"
					and type( RfsBotOrdersOil.sv_tickAlly ) == "function" then
					local ready, rec = RfsBotOrders.homeBeaconReady( unit )
					if ready and rec then
						local searchR = RfsBotOrders.jobRadius( unit, mode )
						local depositR = RfsBotOrders.depositRadius( unit )
						pcall( RfsBotOrdersOil.sv_tickAlly, unit, info, rec, searchR, depositR )
					end
				end
			end
		end
	end
end

-- Load Hay Farm after RfsBotOrders table exists (install wires sv_tickFarmAlly).
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsBotOrdersFarm.lua" )
end )
if type( RfsBotOrdersFarm ) == "table" and RfsBotOrdersFarm.install then
	pcall( RfsBotOrdersFarm.install )
end

print( "[RFS] RfsBotOrders loaded (Rest/Defend/Stay/Recall/Sentry + Farm M2 + Collect M3 + Oil M4 + Return)" )
