-- RfsRadioStation.lua — VOLATILE
-- Hack Beacon modules (wire logic/electricity to the beacon):
--   Radio Battery Brick ×1 → +10 range, +1 cap
--   Radio Antenna ×2 → +10 range each
--   Radio Lock ×1 → +3 cap, +3 s hold
-- Base beacon (no modules): range 30, cap 4, hold 8 s. Raid-only convert is RfsHackV1.

RfsRadioStation = RfsRadioStation or {}

local UUID_BRICK = "d9e3b1a0-2b6c-4d8e-9f1a-0c4d5e6f7a8b"
local UUID_ANTENNA = "ca2d0a9f-1a5b-4c7d-8e09-fb3a4b5c6d7e"
local UUID_LOCK = "bb1c098e-094a-4b6c-7d08-ea293a4b5c6d"
local UUID_HACK = "b4e8c1a0-7d2f-4a91-9c3e-29f1a8d6b5e7"

RfsRadioStation.UUID_BRICK = UUID_BRICK
RfsRadioStation.UUID_ANTENNA = UUID_ANTENNA
RfsRadioStation.UUID_LOCK = UUID_LOCK
RfsRadioStation.UUID_HACK = UUID_HACK

RfsRadioStation.BASE_RANGE = 30
RfsRadioStation.BASE_CAP = 4
RfsRadioStation.BASE_HOLD_SEC = 8

RfsRadioStation.MAX_BRICK = 1
RfsRadioStation.MAX_ANTENNA = 2
RfsRadioStation.MAX_LOCK = 1

RfsRadioStation.BRICK_RANGE = 10
RfsRadioStation.BRICK_CAP = 1
RfsRadioStation.ANTENNA_RANGE = 10
RfsRadioStation.LOCK_CAP = 3
RfsRadioStation.LOCK_HOLD_SEC = 3

local LOGIC = sm.interactable.connectionType.logic
local ELEC = sm.interactable.connectionType.electricity

local function uuidStr( u )
	local s = string.lower( tostring( u or "" ) )
	local m = string.match( s, "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x" )
	return m or s
end

local function shapeUuid( ia )
	if not ia or not sm.exists( ia ) then
		return nil
	end
	local id = nil
	pcall( function()
		local shape = ia.shape or ia:getShape()
		if shape and sm.exists( shape ) then
			id = uuidStr( shape.uuid )
		end
	end )
	return id
end

function RfsRadioStation.partUuid( kind )
	if kind == "brick" then
		return UUID_BRICK
	end
	if kind == "antenna" then
		return UUID_ANTENNA
	end
	if kind == "lock" then
		return UUID_LOCK
	end
	if kind == "core" then
		return UUID_HACK
	end
	return nil
end

function RfsRadioStation.kindOfUuid( id )
	id = uuidStr( id )
	if id == UUID_BRICK then
		return "brick"
	end
	if id == UUID_ANTENNA then
		return "antenna"
	end
	if id == UUID_LOCK then
		return "lock"
	end
	return nil
end

local function disconnectPair( a, b )
	if not a or not b or not sm.exists( a ) or not sm.exists( b ) then
		return
	end
	pcall( function()
		sm.interactable.disconnect( a, b )
	end )
	pcall( function()
		sm.interactable.disconnect( b, a )
	end )
	pcall( function()
		if type( a.disconnect ) == "function" then
			a:disconnect( b )
		end
	end )
	pcall( function()
		if type( b.disconnect ) == "function" then
			b:disconnect( a )
		end
	end )
end

function RfsRadioStation.isHackBeaconInteractable( ia )
	local id = shapeUuid( ia )
	return id == UUID_HACK or id == "c2f158b0-4d7e-4a19-9c6b-8e3a1f50d247"
end

-- Modules may sit as parent OR child of the Hack Beacon (Connection Tool
-- direction varies). Keep only Hack Beacon links; cut module↔module / engines.
function RfsRadioStation.severModuleForeignLinks( moduleScript )
	local ia = moduleScript and moduleScript.interactable
	if not ia or not sm.exists( ia ) then
		return
	end
	local beacons = {}
	local function noteBeacon( other )
		if other and sm.exists( other ) and RfsRadioStation.isHackBeaconInteractable( other ) then
			beacons[#beacons + 1] = other
		end
	end
	pcall( function()
		for _, p in ipairs( ia:getParents() or {} ) do
			if RfsRadioStation.isHackBeaconInteractable( p ) then
				noteBeacon( p )
			else
				disconnectPair( ia, p )
			end
		end
	end )
	pcall( function()
		for _, c in ipairs( ia:getChildren() or {} ) do
			if RfsRadioStation.isHackBeaconInteractable( c ) then
				noteBeacon( c )
			else
				disconnectPair( ia, c )
			end
		end
	end )
	-- At most one beacon wire per module.
	for i = 2, #beacons do
		disconnectPair( ia, beacons[i] )
	end
end

local function neighborKey( other )
	if not other or not sm.exists( other ) then
		return nil
	end
	local key = nil
	pcall( function()
		local shape = other.shape or other:getShape()
		if shape and sm.exists( shape ) and shape.id ~= nil then
			key = "s:" .. tostring( shape.id )
		end
	end )
	if not key then
		key = "ia:" .. tostring( other )
	end
	return key
end

-- Direct neighbors of the beacon that are radio modules (parent or child).
function RfsRadioStation.collectModules( beacon )
	local out = { brick = {}, antenna = {}, lock = {} }
	local ia = beacon and beacon.interactable
	if not ia or not sm.exists( ia ) then
		return out
	end
	local seen = {}
	local function consider( other )
		if not other or not sm.exists( other ) then
			return
		end
		local key = neighborKey( other )
		if not key or seen[key] then
			return
		end
		seen[key] = true
		local kind = RfsRadioStation.kindOfUuid( shapeUuid( other ) )
		if kind and out[kind] then
			out[kind][#out[kind] + 1] = other
		end
	end
	pcall( function()
		for _, p in ipairs( ia:getParents( ELEC ) or {} ) do
			consider( p )
		end
	end )
	pcall( function()
		for _, c in ipairs( ia:getChildren( ELEC ) or {} ) do
			consider( c )
		end
	end )
	pcall( function()
		for _, p in ipairs( ia:getParents( LOGIC ) or {} ) do
			consider( p )
		end
	end )
	pcall( function()
		for _, c in ipairs( ia:getChildren( LOGIC ) or {} ) do
			consider( c )
		end
	end )
	pcall( function()
		for _, p in ipairs( ia:getParents() or {} ) do
			consider( p )
		end
	end )
	pcall( function()
		for _, c in ipairs( ia:getChildren() or {} ) do
			consider( c )
		end
	end )
	return out
end

-- Drop extras over MAX_* (keeps earliest connections).
function RfsRadioStation.enforceLimits( beacon )
	local ia = beacon and beacon.interactable
	if not ia or not sm.exists( ia ) then
		return
	end
	local mods = RfsRadioStation.collectModules( beacon )
	local limits = {
		brick = RfsRadioStation.MAX_BRICK,
		antenna = RfsRadioStation.MAX_ANTENNA,
		lock = RfsRadioStation.MAX_LOCK,
	}
	for kind, list in pairs( mods ) do
		local maxN = limits[kind] or 0
		for i = maxN + 1, #list do
			disconnectPair( ia, list[i] )
		end
	end
end

function RfsRadioStation.counts( beacon )
	RfsRadioStation.enforceLimits( beacon )
	local mods = RfsRadioStation.collectModules( beacon )
	return {
		brick = math.min( #mods.brick, RfsRadioStation.MAX_BRICK ),
		antenna = math.min( #mods.antenna, RfsRadioStation.MAX_ANTENNA ),
		lock = math.min( #mods.lock, RfsRadioStation.MAX_LOCK ),
	}
end

function RfsRadioStation.bonuses( beacon )
	local c = RfsRadioStation.counts( beacon )
	local rangeAdd = ( c.brick * RfsRadioStation.BRICK_RANGE ) + ( c.antenna * RfsRadioStation.ANTENNA_RANGE )
	local capAdd = ( c.brick * RfsRadioStation.BRICK_CAP ) + ( c.lock * RfsRadioStation.LOCK_CAP )
	local holdAdd = c.lock * RfsRadioStation.LOCK_HOLD_SEC
	return {
		brick = c.brick,
		antenna = c.antenna,
		lock = c.lock,
		range = RfsRadioStation.BASE_RANGE + rangeAdd,
		cap = RfsRadioStation.BASE_CAP + capAdd,
		holdSec = RfsRadioStation.BASE_HOLD_SEC + holdAdd,
		rangeAdd = rangeAdd,
		capAdd = capAdd,
		holdAdd = holdAdd,
	}
end

-- True when brick+antenna mid-tier flavor is present (legacy name).
function RfsRadioStation.midTierActive( beacon )
	local b = RfsRadioStation.bonuses( beacon )
	return ( b.brick >= 1 and b.antenna >= 1 )
end

print( "[RFS] RfsRadioStation loaded (brick/antenna/lock bonuses live)" )

-- Electricity in+out so Connection Tool works either direction with the beacon.
-- severModuleForeignLinks keeps only Hack Beacon; drops module↔module.
function RfsRadioStation.applyModuleClass( classTable, prompt )
	if type( classTable ) ~= "table" then
		return
	end
	local function band( a, b )
		if type( bit ) == "table" and type( bit.band ) == "function" then
			return bit.band( a, b )
		end
		return a % ( b * 2 ) >= b and b or 0
	end
	classTable.maxParentCount = 1
	classTable.maxChildCount = 1
	classTable.connectionInput = sm.interactable.connectionType.electricity
	classTable.connectionOutput = sm.interactable.connectionType.electricity
	classTable.connectIcon = "electrical"

	function classTable.server_onCreate( self )
		pcall( function()
			RfsRadioStation.severModuleForeignLinks( self )
		end )
	end

	function classTable.server_onFixedUpdate( self )
		if ( sm.game.getCurrentTick() % 8 ) ~= 0 then
			return
		end
		pcall( function()
			RfsRadioStation.severModuleForeignLinks( self )
		end )
	end

	function classTable.client_onCreate( self ) end

	function classTable.client_canInteract( self )
		sm.gui.setInteractionText( "", "", tostring( prompt or "Radio module — Connection Tool to Hack Beacon" ) )
		return true
	end

	function classTable.client_getAvailableParentConnectionCount( self, connectionType )
		local ELEC = sm.interactable.connectionType.electricity
		if band( connectionType, ELEC ) == 0 then
			return 0
		end
		local n = 0
		pcall( function()
			n = #( self.interactable:getParents( ELEC ) or {} )
		end )
		return math.max( 0, 1 - n )
	end

	function classTable.client_getAvailableChildConnectionCount( self, connectionType )
		local ELEC = sm.interactable.connectionType.electricity
		if band( connectionType, ELEC ) == 0 then
			return 0
		end
		local n = 0
		pcall( function()
			n = #( self.interactable:getChildren( ELEC ) or {} )
		end )
		return math.max( 0, 1 - n )
	end
end
