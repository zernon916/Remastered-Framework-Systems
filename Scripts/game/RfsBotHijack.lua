-- RfsBotHijack.lua — beacons are the computer source for hijacked robots.
-- Author idea (DemonsDen126): keep the beacon powered or lose control;
-- stronger beacons reach further; Infection Beacon can permanently submit a bot.
-- Original RFS. Wraps Survival RobotSelectTarget.

pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsFeatures.lua" )
end )

RfsBotHijack = RfsBotHijack or {}

local ALLY_COLOR = sm.color.new( "3dff8aff" )
local INFECT_COLOR = sm.color.new( "1aff6aff" )
local DEFAULT_RANGE = 16
local ALLY_AGGRO_RANGE = 40
local HOSTILE_VS_ALLY_RANGE = 28
local RAID_RANGE_MUL = 0.5
-- Survival terrain cell / "tile" (RaidManager loadCellWithHandle, RfsAreaLoader).
-- tileX = math.floor( worldPos.x / 64 ), tileY = math.floor( worldPos.y / 64 )
local RAID_CELL_SIZE = 64
RfsBotHijack.RAID_CELL_SIZE = RAID_CELL_SIZE
local RAID_JAM_CHECK_TICKS = 80 -- 2 s
local RAID_JAM_CHANCE = 0.18 -- fight through the hack during a raid
local FIGHT_EXPLODE_CHANCE = 0.30 -- of those breakouts, this many self-destruct
local POWER_HOLD_TICKS = 40 -- 1 s: beacon power cannot flicker off
local OUT_STREAK_TICKS = 40 -- 1 s truly out of range before DROP starts
local IN_STREAK_TICKS = 20 -- 0.5 s stably back in range to cancel DROP
local TAG_CHANNEL = 7 -- unused; tags go through cl_e_rfsTag RPC
-- Red totebot explode, turned down. Farmbot (BIG RED) × 1.25 only.
local RED_LEVEL = 4
local RED_RADIUS = 1.7
local RED_IMPULSE_R = 3.3
local RED_IMPULSE = 14
local RED_DAMAGE = 19
local BIG_RED_MUL = 1.25
local UUID_FARMBOT = sm.uuid.new( "9f4fde94-312f-4417-b13b-84029c5d6b52" )
local UUID_HAYBOT = sm.uuid.new( "c8bfb8f3-7efc-49ac-875a-eb85ac0614db" )
local UUID_TAPEBOT = sm.uuid.new( "04761b4a-a83e-4736-b565-120bc776edb2" )
local UUID_TAPEBOT_RED = sm.uuid.new( "c3d31c47-0c9b-4b07-9bd4-8f022dc4333e" )
local UUID_TAPEBOT_YELLOW = sm.uuid.new( "97efd943-d176-479a-a6f4-46373327ddcd" )
local UUID_TAPEBOT_TAPED = {
	sm.uuid.new( "9dbbd2fb-7726-4e8f-8eb4-0dab228a561d" ),
	sm.uuid.new( "fcb2e8ce-ca94-45e4-a54b-b5acc156170b" ),
	sm.uuid.new( "68d3b2f3-ed4b-4967-9d22-8ee6f555df63" ),
}
local UUID_TAPEBOT_GREEN = {
	sm.uuid.new( "c68914f8-d769-4638-9071-f7dbd1d97351" ),
	sm.uuid.new( "f3ded3f4-ddf9-441d-83f1-28b8cf2c7581" ),
	sm.uuid.new( "54a06cf0-c035-41a5-b19e-158496d35586" ),
}
local UUID_MINERBOT = sm.uuid.new( "92da8324-3cfe-4529-ac1c-c71facda50a3" )
local UUID_CABLEBOT = sm.uuid.new( "b837888a-0480-4a34-bc34-d72261a14385" )
local UUID_TOTEBOT_BLUE = sm.uuid.new( "58992f50-ca36-44e1-8c47-4996d89d6a9a" )
local UUID_TOTEBOT_GREEN = sm.uuid.new( "8984bdbf-521e-4eed-b3c4-2b5e287eb879" )
local UUID_TOTEBOT_LEAF = sm.uuid.new( "55fd93fa-09ed-4a26-bfa1-4601694d5127" )
local UUID_TOTEBOT_RED = sm.uuid.new( "9360d346-3ff2-4925-a068-660cf5dd5267" )
local UUID_TOTEBOT_YELLOW = sm.uuid.new( "2dea48a4-6a79-11ed-a1eb-0242ac120002" )
-- Phase 2 lite: infected/ally slowly convert nearby hostiles (not farm orders).
local CHAIN_RANGE = 10
local CHAIN_NEED_TICKS = 40 * 15 -- ~15 s
local IDENTITY_TAG_EVERY = 80 -- 2 s nametag refresh when idle
-- Domain default ally tint (last Orders color pick) + stable Type N indices.
RfsBotHijack.domainAllyColor = RfsBotHijack.domainAllyColor or {} -- [masterKey] = hex
RfsBotHijack.domainSeq = RfsBotHijack.domainSeq or {} -- [masterKey] = { next=N, byUnit={ [uk]=n } }

local function hackableRobotsOn()
	if type( RfsFeatures ) == "table" and type( RfsFeatures.hackableRobotsEnabled ) == "function" then
		local ok, v = pcall( RfsFeatures.hackableRobotsEnabled )
		if ok then
			return v and true or false
		end
	end
	return true
end

-- Default ON = current (miner/cable in g_robots stay hijackable). Host can opt out.
local function undergroundBotsOn()
	if type( RfsFeatures ) == "table" and type( RfsFeatures.hackUndergroundBotsEnabled ) == "function" then
		local ok, v = pcall( RfsFeatures.hackUndergroundBotsEnabled )
		if ok then
			return v and true or false
		end
	end
	return true
end

RfsBotHijack.allies = RfsBotHijack.allies or {} -- [unitKey] = record
RfsBotHijack.beacons = RfsBotHijack.beacons or {} -- [beaconKey] = record
RfsBotHijack.pending = RfsBotHijack.pending or {} -- [unitKey] = { startTick, need, beaconKey, text }
RfsBotHijack.banned = RfsBotHijack.banned or {} -- [unitKey] = true, raid breakout, until death
RfsBotHijack.chain = RfsBotHijack.chain or {} -- [hostileKey] = { startTick, need, sourceKey, text }
RfsBotHijack.chainSkip = RfsBotHijack.chainSkip or {} -- [unitKey] = true, leftover/failed convert, no retry
-- Client range ring opt-in (server mirrors onto beacon clientData.showRange).
RfsBotHijack.rangeVisible = RfsBotHijack.rangeVisible or {} -- [beaconKey] = true
-- Live interactable script refs (same Lua env) so Game RPCs can ask the beacon.
RfsBotHijack.beaconScripts = RfsBotHijack.beaconScripts or {} -- [beaconKey] = interactable self
RfsBotHijack._hooked = false
RfsBotHijack._autoTick = -1

local function unitKey( unit )
	if not unit then
		return nil
	end
	local id = nil
	pcall( function() id = unit.id end )
	if id ~= nil then
		return tostring( id )
	end
	return tostring( unit )
end

local function charTypeStr( char )
	if not char then
		return nil
	end
	local ok, t = pcall( function()
		return tostring( char:getCharacterType() )
	end )
	if ok then
		return t
	end
	return nil
end

local function charColorHex( char )
	if not char or not sm.exists( char ) then
		return nil
	end
	local hex = nil
	pcall( function()
		local c = char.color
		if c then
			hex = tostring( c )
		end
	end )
	return hex
end

local function applyColor( char, color )
	if not char or not sm.exists( char ) or not color then
		return
	end
	pcall( function()
		char:setColor( color )
	end )
end

-- Normalize stored RRGGBBAA hex (optional leading #).
local function normalizeColorHex( hex )
	if hex == nil then
		return nil
	end
	local s = string.lower( tostring( hex ):gsub( "^#", "" ):gsub( "%s+", "" ) )
	if s == "" then
		return nil
	end
	if not string.match( s, "^%x%x%x%x%x%x%x%x$" ) and not string.match( s, "^%x%x%x%x%x%x$" ) then
		return nil
	end
	if #s == 6 then
		s = s .. "ff"
	end
	return s
end

-- Custom allyColor overrides infect/ally defaults once the player picks a tint.
local function allyVisualColor( info )
	if type( info ) == "table" then
		local hex = normalizeColorHex( info.allyColor )
		if hex then
			local ok, col = pcall( sm.color.new, hex )
			if ok and col then
				return col
			end
		end
		if info.mode == "infected" then
			return INFECT_COLOR
		end
	end
	return ALLY_COLOR
end

local function applyAllyVisualColor( char, info )
	applyColor( char, allyVisualColor( info ) )
end

local function sameWorld( a, b )
	local ok = true
	pcall( function()
		ok = ( a == b )
	end )
	return ok
end

-- Game.lua is a no-world script: sm.unit.getAllUnits() with no args throws.
-- World/unit/interactable scripts may omit world. Always prefer an explicit world.
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

local function worldOfPlayer( player )
	if not player then
		return nil
	end
	local world = nil
	pcall( function()
		local char = player.character
		if char and sm.exists( char ) then
			world = char:getWorld()
		end
	end )
	return world
end

function RfsBotHijack.robotTypeSet()
	local set = {}
	if type( g_robots ) == "table" then
		for _, uuid in ipairs( g_robots ) do
			set[tostring( uuid )] = true
		end
	end
	return set
end

function RfsBotHijack.isRobotCharacter( char )
	if not char then
		return false
	end
	local okPlayer, isP = pcall( function()
		return char:isPlayer()
	end )
	if okPlayer and isP then
		return false
	end
	local okT, t = pcall( function()
		return char:getCharacterType()
	end )
	if not okT or not t then
		return false
	end
	if type( g_robots ) == "table" then
		for _, uuid in ipairs( g_robots ) do
			if t == uuid or tostring( t ) == tostring( uuid ) then
				return true
			end
		end
	end
	return RfsBotHijack.robotTypeSet()[tostring( t )] == true
end

function RfsBotHijack.isUndergroundBotCharacter( char )
	if not char then
		return false
	end
	local t = nil
	pcall( function()
		t = char:getCharacterType()
	end )
	if not t then
		return false
	end
	local miner = unit_minerbot or UUID_MINERBOT
	local cable = unit_cablebot or UUID_CABLEBOT
	return t == miner or t == UUID_MINERBOT or tostring( t ) == tostring( miner )
		or t == cable or t == UUID_CABLEBOT or tostring( t ) == tostring( cable )
end

local function uuidKey( v )
	if v == nil then
		return ""
	end
	local s = string.lower( tostring( v ) )
	local hex = string.match( s, "(%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x)" )
	return hex or s
end

local function sameTypeUuid( typeStr, uuid )
	if typeStr == nil or uuid == nil then
		return false
	end
	local a, b = uuidKey( typeStr ), uuidKey( uuid )
	if a ~= "" and b ~= "" and a == b then
		return true
	end
	return tostring( typeStr ) == tostring( uuid )
end

local function inUuidList( typeStr, list )
	if type( list ) ~= "table" then
		return false
	end
	for _, u in ipairs( list ) do
		if sameTypeUuid( typeStr, u ) then
			return true
		end
	end
	return false
end

-- Survival character UUID / name → Orders kind (hay/tote/water/farmbot/tape/bubble/…).
function RfsBotHijack.classifyBotKind( typeStr, displayName )
	local typeRaw = tostring( typeStr or "" )
	local s = string.lower( typeRaw .. " " .. tostring( displayName or "" ) )
	local hay = unit_haybot or UUID_HAYBOT
	local farm = unit_farmbot or UUID_FARMBOT
	local blue = unit_totebot_blue or UUID_TOTEBOT_BLUE
	local tape = unit_tapebot or UUID_TAPEBOT
	local miner = unit_minerbot or UUID_MINERBOT
	local cable = unit_cablebot or UUID_CABLEBOT
	-- Water / Totebot Blue before generic tote.
	if sameTypeUuid( typeRaw, blue ) or sameTypeUuid( typeRaw, unit_waterbot )
		or string.find( s, "waterbot", 1, true )
		or ( string.find( s, "water", 1, true ) and not string.find( s, "tote", 1, true ) ) then
		return "water"
	end
	if sameTypeUuid( typeRaw, farm ) or string.find( s, "farmbot", 1, true )
		or ( string.find( s, "farm", 1, true ) and not string.find( s, "tote", 1, true ) ) then
		return "farmbot"
	end
	if sameTypeUuid( typeRaw, hay ) or string.find( s, "haybot", 1, true )
		or string.find( s, "hay", 1, true ) then
		return "hay"
	end
	local toteUuids = {
		unit_totebot_green or UUID_TOTEBOT_GREEN,
		unit_totebot_red or UUID_TOTEBOT_RED,
		unit_totebot_yellow or UUID_TOTEBOT_YELLOW,
		unit_totebot_leaf or UUID_TOTEBOT_LEAF,
		UUID_TOTEBOT_GREEN, UUID_TOTEBOT_RED, UUID_TOTEBOT_YELLOW, UUID_TOTEBOT_LEAF,
	}
	if inUuidList( typeRaw, toteUuids ) or string.find( s, "tote", 1, true ) then
		return "tote"
	end
	-- Green tapebot = Bubble before Paint tapebot.
	local greens = {
		rawget( _G, "unit_tapebot_green_1" ),
		rawget( _G, "unit_tapebot_green_2" ),
		rawget( _G, "unit_tapebot_green_3" ),
	}
	if inUuidList( typeRaw, greens ) or inUuidList( typeRaw, UUID_TAPEBOT_GREEN )
		or string.find( s, "bubble", 1, true )
		or ( string.find( s, "tape", 1, true ) and string.find( s, "green", 1, true ) ) then
		return "bubble"
	end
	local tapes = {
		tape, UUID_TAPEBOT, UUID_TAPEBOT_RED, UUID_TAPEBOT_YELLOW,
		unit_tapebot_red, unit_tapebot_yellow,
		rawget( _G, "unit_tapebot_taped_1" ),
		rawget( _G, "unit_tapebot_taped_2" ),
		rawget( _G, "unit_tapebot_taped_3" ),
	}
	if inUuidList( typeRaw, tapes ) or inUuidList( typeRaw, UUID_TAPEBOT_TAPED )
		or string.find( s, "tapebot", 1, true ) or string.find( s, "tape", 1, true )
		or string.find( s, "paint", 1, true ) then
		return "tape"
	end
	if sameTypeUuid( typeRaw, miner ) or string.find( s, "miner", 1, true ) then
		return "miner"
	end
	if sameTypeUuid( typeRaw, cable ) or string.find( s, "cable", 1, true ) then
		return "cable"
	end
	if string.find( s, "loot", 1, true ) then
		return "loot"
	end
	if string.find( s, "seed", 1, true ) then
		return "seed"
	end
	if string.find( s, "trash", 1, true ) then
		return "trash"
	end
	if string.find( s, "scan", 1, true ) then
		return "scan"
	end
	return "other"
end

function RfsBotHijack.typeLetterFor( kind, displayName )
	kind = tostring( kind or "other" )
	if kind == "hay" then return "H" end
	if kind == "tote" then return "T" end
	if kind == "water" then return "W" end
	if kind == "farmbot" or kind == "farm" then return "F" end
	if kind == "tape" or kind == "paint" then return "P" end
	if kind == "bubble" then return "B" end
	if kind == "miner" then return "M" end
	if kind == "cable" then return "C" end
	if kind == "loot" then return "L" end
	if kind == "seed" then return "S" end
	local name = tostring( displayName or "" )
	local ch = string.match( name, "([%a])" )
	if ch then
		return string.upper( ch )
	end
	return "U"
end

-- Short world/list labels: Tote / Hay / Farm / Tape / Water / …
local function shortTypeName( typeStr )
	local kind = RfsBotHijack.classifyBotKind( typeStr, nil )
	if kind == "farmbot" then return "Farm" end
	if kind == "hay" then return "Hay" end
	if kind == "tape" then return "Tape" end
	if kind == "bubble" then return "Bubble" end
	if kind == "miner" then return "Miner" end
	if kind == "cable" then return "Cable" end
	if kind == "water" then return "Water" end
	if kind == "tote" then return "Tote" end
	if kind == "loot" then return "Loot" end
	if kind == "seed" then return "Seed" end
	if kind == "trash" then return "Trash" end
	if kind == "scan" then return "Scan" end
	return "Bot"
end

local function parseTypeNumberName( name )
	name = tostring( name or "" )
	local label, num = string.match( name, "^([%a]+)%s+(%d+)$" )
	if label and num then
		return label, tonumber( num )
	end
	return nil, nil
end

local function isLegacyDisplayName( name )
	name = tostring( name or "" )
	if name == "" then
		return true
	end
	if string.find( name, "^Inf ", 1 ) or string.find( name, "^Ally ", 1 ) then
		return true
	end
	if string.find( name, "Bot%-", 1 ) then
		return true
	end
	local label, num = parseTypeNumberName( name )
	return not ( label and num )
end

local function namingDomainKey( beaconKey )
	beaconKey = beaconKey and tostring( beaconKey ) or nil
	if not beaconKey or beaconKey == "" then
		return "_"
	end
	local master = beaconKey
	if type( RfsBotHijack.orderDomainMasterKey ) == "function" then
		pcall( function()
			master = RfsBotHijack.orderDomainMasterKey( beaconKey ) or beaconKey
		end )
	end
	return tostring( master or beaconKey )
end

local function allocDomainIndex( domainKey, unitKey, prefer )
	domainKey = tostring( domainKey or "_" )
	unitKey = tostring( unitKey or "" )
	if unitKey == "" then
		return tonumber( prefer ) or 1
	end
	local slot = RfsBotHijack.domainSeq[domainKey]
	if type( slot ) ~= "table" then
		slot = { next = 1, byUnit = {} }
		RfsBotHijack.domainSeq[domainKey] = slot
	end
	slot.byUnit = slot.byUnit or {}
	if slot.byUnit[unitKey] then
		return slot.byUnit[unitKey]
	end
	local n = tonumber( prefer )
	if not n or n < 1 then
		n = tonumber( slot.next ) or 1
	end
	-- Avoid collisions with already-assigned indices.
	local used = {}
	for _, v in pairs( slot.byUnit ) do
		used[tonumber( v ) or 0] = true
	end
	while used[n] do
		n = n + 1
	end
	slot.byUnit[unitKey] = n
	if n >= ( tonumber( slot.next ) or 1 ) then
		slot.next = n + 1
	end
	return n
end

local function domainColorFor( beaconKey )
	local dk = namingDomainKey( beaconKey )
	local hex = normalizeColorHex( RfsBotHijack.domainAllyColor[dk] )
	if hex then
		return hex
	end
	local rec = RfsBotHijack.beacons[dk]
	if rec then
		hex = normalizeColorHex( rec.allyColor )
		if hex then
			return hex
		end
	end
	if beaconKey and tostring( beaconKey ) ~= dk then
		rec = RfsBotHijack.beacons[tostring( beaconKey )]
		if rec then
			return normalizeColorHex( rec.allyColor )
		end
	end
	return nil
end

function RfsBotHijack.setDomainAllyColor( beaconKey, colorHex )
	local hex = normalizeColorHex( colorHex )
	if not hex then
		return false
	end
	local dk = namingDomainKey( beaconKey )
	RfsBotHijack.domainAllyColor[dk] = hex
	local domain = { [dk] = true }
	if type( RfsBotHijack.orderDomainKeys ) == "function" then
		pcall( function()
			domain = RfsBotHijack.orderDomainKeys( beaconKey ) or domain
		end )
	end
	for key, _ in pairs( domain ) do
		local rec = RfsBotHijack.beacons[tostring( key )]
		if rec then
			rec.allyColor = hex
		end
	end
	return true, hex
end

function RfsBotHijack.getDomainAllyColor( beaconKey )
	return domainColorFor( beaconKey )
end

-- World nametag + Orders identity: "Tote 1", "Hay 2", … (stable per domain).
local function makeDisplayName( unit, typeStr, opts )
	opts = opts or {}
	local base = shortTypeName( typeStr )
	local uk = unitKey( unit )
	local domainKey = namingDomainKey( opts.workBeaconKey or opts.beaconKey or opts.domainKey )
	local prefer = tonumber( opts.displayIndex )
	if not prefer and opts.displayName then
		local _, n = parseTypeNumberName( opts.displayName )
		prefer = n
	end
	local idx = allocDomainIndex( domainKey, uk, prefer )
	return base .. " " .. tostring( idx ), idx, base
end

local function nowTick()
	local now = 0
	pcall( function()
		now = sm.game.getCurrentTick()
	end )
	return now
end

-- Persist identity on the unit's own saved table (reload-safe).
local function pushIdentityToUnit( unit, identity )
	if not unit or not sm.exists( unit ) or type( identity ) ~= "table" then
		return
	end
	pcall( function()
		sm.event.sendToUnit( unit, "sv_e_rfsIdentity", identity )
	end )
end

local function clearIdentityOnUnit( unit )
	if not unit or not sm.exists( unit ) then
		return
	end
	pcall( function()
		sm.event.sendToUnit( unit, "sv_e_rfsIdentity", { clear = true } )
	end )
end

function RfsBotHijack.isAlly( unit )
	local key = unitKey( unit )
	local info = key and RfsBotHijack.allies[key]
	return info ~= nil and info.controlled == true
end

function RfsBotHijack.isDoomed( unit )
	local key = unitKey( unit )
	if not key then
		return false
	end
	if RfsBotHijack.jams and RfsBotHijack.jams[key] then
		return true
	end
	local info = RfsBotHijack.allies[key]
	return info ~= nil and info.doomed == true
end

function RfsBotHijack.ban( unit )
	local key = unitKey( unit )
	if key then
		RfsBotHijack.banned = RfsBotHijack.banned or {}
		-- Keep the unit ref so prune() can confirm destroy; never store only a bool.
		RfsBotHijack.banned[key] = unit or true
	end
end

local function publishHackable( unit, hackable )
	if not unit then
		return
	end
	local flag = hackable and true or false
	pcall( function()
		local char = unit.character
		if char and sm.exists( char ) then
			if type( char.publicData ) == "table" then
				char.publicData.rfsHackable = flag
			else
				char.publicData = { rfsHackable = flag }
			end
		end
	end )
	pcall( function()
		if type( unit.publicData ) == "table" then
			unit.publicData.rfsHackable = flag
		end
	end )
end

local function applyUnhackableToSelf( self )
	if not self then
		return
	end
	self.saved = self.saved or {}
	self.saved.rfsHackable = false
	self.saved.playerAlly = nil
	self.saved.playerAllyMode = nil
	self.saved.playerAllyBeacon = nil
	self.saved.playerAllyOwner = nil
	self.saved.rfsDisplayName = nil
	self.saved.rfsUnitType = nil
	self.saved.rfsBotType = nil
	self.saved.rfsTypeLetter = nil
	self.saved.rfsFirstSeenTick = nil
	self.saved.rfsAllyColor = nil
	self.saved.friendly = false
	self.isDirty = true
	if self.unit then
		RfsBotHijack.ban( self.unit )
		publishHackable( self.unit, false )
	end
end

-- Default true/nil = hackable. False is permanent until this unit dies.
function RfsBotHijack.isHackable( unit )
	if not unit then
		return false
	end
	local key = unitKey( unit )
	if key and RfsBotHijack.banned and RfsBotHijack.banned[key] then
		return false
	end
	local no = false
	pcall( function()
		local char = unit.character
		if char and sm.exists( char ) then
			local pd = char.publicData
			if type( pd ) == "table" and pd.rfsHackable == false then
				no = true
			end
		end
	end )
	if no then
		return false
	end
	pcall( function()
		if type( unit.publicData ) == "table" and unit.publicData.rfsHackable == false then
			no = true
		end
	end )
	if no then
		return false
	end
	return true
end

function RfsBotHijack.setHackable( unit, hackable )
	if not unit then
		return
	end
	if hackable == false then
		RfsBotHijack.ban( unit )
		publishHackable( unit, false )
		pcall( function()
			sm.event.sendToUnit( unit, "sv_e_rfsSetHackable", { hackable = false } )
		end )
	end
end

-- Raid breakout: never hackable again until this unit dies.
-- Short peacetime lockout only blocks 1-tick re-grab flicker.
function RfsBotHijack.isLockedOut( unit )
	if RfsBotHijack.isDoomed( unit ) then
		return true
	end
	if unit and not RfsBotHijack.isHackable( unit ) then
		return true
	end
	local key = unitKey( unit )
	if not key then
		return false
	end
	if RfsBotHijack.banned and RfsBotHijack.banned[key] then
		return true
	end
	RfsBotHijack.lockout = RfsBotHijack.lockout or {}
	local untilTick = RfsBotHijack.lockout[key]
	if not untilTick then
		return false
	end
	local now = 0
	pcall( function()
		now = sm.game.getCurrentTick()
	end )
	if now >= untilTick then
		RfsBotHijack.lockout[key] = nil
		return false
	end
	return true
end

function RfsBotHijack.isAllyCharacter( char, world )
	if not char or not sm.exists( char ) then
		return false
	end
	local okP, isP = pcall( function()
		return char:isPlayer()
	end )
	if okP and isP then
		return false
	end
	if not world then
		pcall( function()
			world = char:getWorld()
		end )
	end
	for _, u in ipairs( allUnits( world ) ) do
		if sm.exists( u ) and u.character == char then
			return RfsBotHijack.isAlly( u )
		end
	end
	return false
end

_G.g_rfsIsPlayerAlly = function( unit )
	return RfsBotHijack.isAlly( unit )
end
_G.g_rfsPlayerAllies = RfsBotHijack.allies

function RfsBotHijack.publishGlobals()
	_G.g_rfsIsPlayerAlly = function( unit )
		return RfsBotHijack.isAlly( unit )
	end
	_G.g_rfsPlayerAllies = RfsBotHijack.allies
end

local function worldIdOf( world )
	if world == nil then
		return nil
	end
	local id = nil
	pcall( function()
		id = world.id
	end )
	if id ~= nil then
		return id
	end
	if type( world ) == "number" then
		return world
	end
	return nil
end

-- Survival farm-raid "tile" = one terrain cell (64 m × 64 m), same formula
-- RaidManager uses for loadCellWithHandle: math.floor(pos.x / 64), math.floor(pos.y / 64).
-- Raid origin = raid.center (crop / farm-plot centroid). Fallback: attackPosition,
-- then last on-tile raider note. Vanilla RAID_RADIUS is 96 m (spans neighbor cells);
-- RFS raid effects use the origin cell only.
function RfsBotHijack.tileCoords( pos )
	if not pos or pos.x == nil or pos.y == nil then
		return nil, nil
	end
	return math.floor( pos.x / RAID_CELL_SIZE ), math.floor( pos.y / RAID_CELL_SIZE )
end

local function sameRaidTile( a, b )
	local ax, ay = RfsBotHijack.tileCoords( a )
	local bx, by = RfsBotHijack.tileCoords( b )
	return ax ~= nil and ax == bx and ay == by
end

local function raidIsActive( raid )
	if type( raid ) ~= "table" then
		return false
	end
	if raid.timeoutTick then
		return true
	end
	local ad = raid.attackData
	if type( ad ) ~= "table" then
		return false
	end
	if ad.spawnPositions then
		return true
	end
	if ad.attackTick then
		local now = 0
		pcall( function()
			now = sm.game.getCurrentTick()
		end )
		-- Same window as the on-screen incoming raid warning (~60 s).
		if now >= ( ad.attackTick - 40 * 60 ) then
			return true
		end
	end
	return false
end

-- Prefer raid.center — that is the cell RaidManager pins with loadCellWithHandle.
local function raidOriginPos( raid )
	if type( raid ) ~= "table" then
		return nil
	end
	if raid.center then
		return raid.center
	end
	local ad = raid.attackData
	if type( ad ) == "table" and ad.attackPosition then
		return ad.attackPosition
	end
	return nil
end

local function collectRaidOrigins( wid, probePos )
	local origins = {}
	if wid and g_raidManager then
		pcall( function()
			local raids = g_raidManager.sv.saved.worldRaids[wid]
			if type( raids ) ~= "table" then
				return
			end
			for _, raid in pairs( raids ) do
				if raidIsActive( raid ) then
					local origin = raidOriginPos( raid )
					if origin then
						origins[#origins + 1] = origin
					end
				end
			end
		end )
	end
	if #origins == 0 and wid and g_raidManager and probePos
		and type( g_raidManager.sv_getRaidAtPosition ) == "function" then
		local ok, raid = pcall( function()
			return g_raidManager:sv_getRaidAtPosition( wid, probePos )
		end )
		if ok and raidIsActive( raid ) then
			local origin = raidOriginPos( raid )
			if origin then
				origins[#origins + 1] = origin
			end
		end
	end
	if #origins == 0 then
		local note = RfsBotHijack._raidNote
		if note and note.pos then
			local now = 0
			pcall( function()
				now = sm.game.getCurrentTick()
			end )
			if note.tick and ( now - note.tick ) <= 80 then
				local nwid = note.wid
				if not ( nwid and wid and nwid ~= wid ) then
					origins[#origins + 1] = note.pos
				end
			end
		end
	end
	return origins
end

-- True only when pos is on the SAME 64 m cell as an active raid origin.
function RfsBotHijack.areaHasRaid( pos, world )
	if not pos then
		return false
	end
	local origins = collectRaidOrigins( worldIdOf( world ), pos )
	for i = 1, #origins do
		if sameRaidTile( pos, origins[i] ) then
			return true
		end
	end
	return false
end

-- True when a raid is active in this world but pos is on a different cell.
-- Off-tile allies keep hack / jobs; no jam, raid DROP, or raid unhack.
function RfsBotHijack.outsideRaidTile( pos, world )
	if not pos then
		return false
	end
	local origins = collectRaidOrigins( worldIdOf( world ), pos )
	if #origins == 0 then
		return false
	end
	for i = 1, #origins do
		if sameRaidTile( pos, origins[i] ) then
			return false
		end
	end
	return true
end

function RfsBotHijack.noteRaid( pos, world )
	if not pos then
		return
	end
	local origins = collectRaidOrigins( worldIdOf( world ), pos )
	if #origins > 0 then
		local onTile = false
		for i = 1, #origins do
			if sameRaidTile( pos, origins[i] ) then
				onTile = true
				break
			end
		end
		if not onTile then
			return
		end
	end
	local now = 0
	pcall( function()
		now = sm.game.getCurrentTick()
	end )
	RfsBotHijack._raidNote = { pos = pos, wid = worldIdOf( world ), tick = now }
end

function RfsBotHijack.announce( msg )
	RfsBotHijack._announce = tostring( msg or "" )
end

function RfsBotHijack.pullAnnounce()
	local m = RfsBotHijack._announce
	RfsBotHijack._announce = nil
	if m and m ~= "" then
		return m
	end
	return nil
end

function RfsBotHijack.effectiveRange( rec )
	local r = tonumber( rec and rec.range ) or DEFAULT_RANGE
	if rec and rec.pos and RfsBotHijack.areaHasRaid( rec.pos, rec.world ) then
		r = r * RAID_RANGE_MUL
	end
	return r
end

local function beaconLive( rec )
	if not rec then
		return false
	end
	if rec.powered then
		return true
	end
	local now = 0
	pcall( function()
		now = sm.game.getCurrentTick()
	end )
	return rec.powerHoldUntil ~= nil and now < rec.powerHoldUntil
end

-- Public for RfsBotOrders job-radius / home-beacon checks.
function RfsBotHijack.beaconLive( rec )
	return beaconLive( rec )
end

-- ---------------------------------------------------------------------------
-- Master / Slave beacon groups
--
-- role = independent | master | slave (per powered hack device).
-- Player sets Master on one device (Orders GUI). That Master forces other
-- powered hack beacons within its range into Slave mode (one Master per
-- linked group; claiming Master demotes any other Master in range).
--
-- Slaves share the Master's order domain: Orders list / homeAllyCount /
-- new workBeaconKey assignments use the Master's key (plus every slave key
-- in the group) so allies hijacked on a nearby device still appear when
-- opening Orders on any linked beacon. Tether/power still uses each device's
-- own beaconKey; only the ally/order pool is aggregated.
-- ---------------------------------------------------------------------------

local function normalizeBeaconRole( role )
	role = string.lower( tostring( role or "independent" ) )
	if role == "master" or role == "slave" then
		return role
	end
	return "independent"
end

local function beaconRecsInMasterRange( masterRec, otherRec )
	if not masterRec or not otherRec or not masterRec.pos or not otherRec.pos then
		return false
	end
	if masterRec.world and otherRec.world and masterRec.world ~= otherRec.world then
		return false
	end
	local r = tonumber( masterRec.range ) or DEFAULT_RANGE
	return ( masterRec.pos - otherRec.pos ):length2() <= ( r * r )
end

function RfsBotHijack.registerBeacon( key, rec )
	if not key or type( rec ) ~= "table" then
		return
	end
	key = tostring( key )
	local now = 0
	pcall( function()
		now = sm.game.getCurrentTick()
	end )
	local prev = RfsBotHijack.beacons[key]
	if rec.powered then
		rec.powerHoldUntil = now + POWER_HOLD_TICKS
	elseif prev and prev.powerHoldUntil then
		rec.powerHoldUntil = prev.powerHoldUntil
	end
	-- Preserve Master/Slave fields when caller omits them for a tick.
	if rec.role == nil and prev and prev.role ~= nil then
		rec.role = prev.role
	end
	if rec.masterKey == nil and prev and prev.masterKey ~= nil then
		rec.masterKey = prev.masterKey
	end
	if rec.allyColor == nil and prev and prev.allyColor ~= nil then
		rec.allyColor = prev.allyColor
	end
	rec.role = normalizeBeaconRole( rec.role )
	if rec.role ~= "slave" then
		rec.masterKey = nil
	elseif rec.masterKey then
		rec.masterKey = tostring( rec.masterKey )
	end
	-- Apply pending claimMaster / demote before publishing the live record.
	RfsBotHijack.pendingRole = RfsBotHijack.pendingRole or {}
	local pending = RfsBotHijack.pendingRole[key]
	if type( pending ) == "table" then
		rec.role = normalizeBeaconRole( pending.role )
		rec.masterKey = pending.masterKey and tostring( pending.masterKey ) or nil
		if rec.role ~= "slave" then
			rec.masterKey = nil
		end
		rec._roleDirty = true
		RfsBotHijack.pendingRole[key] = nil
	end
	RfsBotHijack.beacons[key] = rec
end

function RfsBotHijack.unregisterBeacon( key )
	if key then
		RfsBotHijack.beacons[tostring( key )] = nil
	end
end

-- Effective role for listing/linking (slaves are computed from live Masters in range).
function RfsBotHijack.effectiveBeaconRole( beaconKey )
	beaconKey = tostring( beaconKey or "" )
	local rec = RfsBotHijack.beacons[beaconKey]
	if not rec then
		return "independent", nil
	end
	local stored = normalizeBeaconRole( rec.role )
	if stored == "master" and beaconLive( rec ) then
		return "master", nil
	end
	-- Forced slave: any live Master in range claims this device.
	for mk, m in pairs( RfsBotHijack.beacons ) do
		if mk ~= beaconKey and normalizeBeaconRole( m.role ) == "master" and beaconLive( m ) then
			if beaconRecsInMasterRange( m, rec ) and beaconLive( rec ) then
				return "slave", tostring( mk )
			end
		end
	end
	return "independent", nil
end

-- Master key for order/ally domain (self if independent or master).
function RfsBotHijack.orderDomainMasterKey( beaconKey )
	beaconKey = tostring( beaconKey or "" )
	local role, masterKey = RfsBotHijack.effectiveBeaconRole( beaconKey )
	if role == "slave" and masterKey then
		return masterKey
	end
	return beaconKey
end

-- Keys whose home allies appear when opening Orders on beaconKey.
function RfsBotHijack.orderDomainKeys( beaconKey )
	beaconKey = tostring( beaconKey or "" )
	local keys = {}
	if beaconKey == "" then
		return keys
	end
	local masterKey = RfsBotHijack.orderDomainMasterKey( beaconKey )
	keys[masterKey] = true
	keys[beaconKey] = true
	local masterRec = RfsBotHijack.beacons[masterKey]
	if masterRec and normalizeBeaconRole( masterRec.role ) == "master" and beaconLive( masterRec ) then
		for k, rec in pairs( RfsBotHijack.beacons ) do
			if k ~= masterKey and beaconLive( rec ) and beaconRecsInMasterRange( masterRec, rec ) then
				keys[tostring( k )] = true
			end
		end
	end
	return keys
end

-- Rebind orphan / out-of-domain allies onto the Master (or Independent) home key.
-- Includes bots still on old Independent keys of beacons now in this Master's range,
-- and owned bots physically inside the domain with no usable home key.
function RfsBotHijack.migrateDomainAllies( beaconKey, ownerFilterId )
	beaconKey = tostring( beaconKey or "" )
	if beaconKey == "" then
		return 0
	end
	local domain = RfsBotHijack.orderDomainKeys( beaconKey )
	local masterKey = RfsBotHijack.orderDomainMasterKey( beaconKey ) or beaconKey
	local masterRec = RfsBotHijack.beacons[masterKey]
	local n = 0
	for key, info in pairs( RfsBotHijack.allies ) do
		if info and info.controlled then
			if ownerFilterId ~= nil and tostring( info.owner ) ~= tostring( ownerFilterId ) then
				-- skip
			else
				local home = RfsBotHijack.homeBeaconKey( info )
				local inDomain = home ~= nil and domain[home] == true
				if not inDomain then
					local adopt = false
					-- Home points at a live beacon currently inside this Master's range
					-- (orphan Independent key before SET MASTER).
					if home and masterRec and beaconLive( masterRec ) then
						local homeRec = RfsBotHijack.beacons[home]
						if homeRec and beaconLive( homeRec ) and beaconRecsInMasterRange( masterRec, homeRec ) then
							adopt = true
						end
					end
					-- Physically inside a domain beacon's range (incl. no home /hijack orphans).
					if not adopt then
						local unit = RfsBotHijack.unitByKey( key )
						if unit and sm.exists( unit ) and unit.character and sm.exists( unit.character ) then
							for dk, _ in pairs( domain ) do
								local drec = RfsBotHijack.beacons[dk]
								if drec and beaconLive( drec ) and drec.pos then
									local okWorld = true
									if drec.world then
										pcall( function()
											okWorld = ( unit.character:getWorld() == drec.world )
										end )
									end
									if okWorld then
										local r = tonumber( drec.range ) or DEFAULT_RANGE
										local d2 = ( unit.character.worldPosition - drec.pos ):length2()
										if d2 <= r * r then
											adopt = true
											break
										end
									end
								end
							end
						end
					end
					if adopt then
						info.workBeaconKey = tostring( masterKey )
						local ord = info.rfsOrder or info.order
						if type( ord ) == "table" then
							ord.beaconKey = info.workBeaconKey
							info.rfsOrder = ord
							info.order = ord
						end
						local unit = RfsBotHijack.unitByKey( key )
						if unit and sm.exists( unit ) then
							pushIdentityToUnit( unit, {
								owner = info.owner,
								displayName = info.displayName,
								unitType = info.unitType or info.type,
								firstSeenTick = info.firstSeenTick,
								mode = info.mode,
								beaconKey = info.beaconKey,
								workBeaconKey = info.workBeaconKey,
								allyColor = info.allyColor,
								playerAlly = true,
							} )
						end
						n = n + 1
					end
				end
			end
		end
	end
	if n > 0 then
		RfsBotHijack.publishGlobals()
	end
	return n
end

function RfsBotHijack.setRangeVisible( beaconKey, show )
	beaconKey = tostring( beaconKey or "" )
	if beaconKey == "" then
		return false
	end
	RfsBotHijack.rangeVisible = RfsBotHijack.rangeVisible or {}
	if show then
		RfsBotHijack.rangeVisible[beaconKey] = true
	else
		RfsBotHijack.rangeVisible[beaconKey] = nil
	end
	return true
end

function RfsBotHijack.isRangeVisible( beaconKey )
	beaconKey = tostring( beaconKey or "" )
	local map = RfsBotHijack.rangeVisible
	return beaconKey ~= "" and type( map ) == "table" and map[beaconKey] == true
end

-- Player claims Master on beaconKey. Demotes other Masters in range to Independent
-- (they become Slaves via effectiveBeaconRole while in range).
function RfsBotHijack.claimMaster( beaconKey )
	beaconKey = tostring( beaconKey or "" )
	local rec = RfsBotHijack.beacons[beaconKey]
	if not rec or not beaconLive( rec ) then
		return false, "beacon gone or unpowered"
	end
	RfsBotHijack.pendingRole = RfsBotHijack.pendingRole or {}
	for k, other in pairs( RfsBotHijack.beacons ) do
		if k ~= beaconKey and normalizeBeaconRole( other.role ) == "master" then
			if beaconRecsInMasterRange( rec, other ) or beaconRecsInMasterRange( other, rec ) then
				other.role = "independent"
				other.masterKey = nil
				other._roleDirty = true
				RfsBotHijack.pendingRole[tostring( k )] = { role = "independent" }
			end
		end
	end
	rec.role = "master"
	rec.masterKey = nil
	rec._roleDirty = true
	RfsBotHijack.pendingRole[beaconKey] = { role = "master" }
	-- Pull orphan Independent homes (and in-range owned allies) onto this Master.
	pcall( function()
		RfsBotHijack.migrateDomainAllies( beaconKey )
	end )
	return true, "master"
end

function RfsBotHijack.clearMaster( beaconKey )
	beaconKey = tostring( beaconKey or "" )
	local rec = RfsBotHijack.beacons[beaconKey]
	if not rec then
		return false, "beacon gone"
	end
	rec.role = "independent"
	rec.masterKey = nil
	rec._roleDirty = true
	RfsBotHijack.pendingRole = RfsBotHijack.pendingRole or {}
	RfsBotHijack.pendingRole[beaconKey] = { role = "independent" }
	return true, "independent"
end

-- Sync persisted role onto the live beacon record after register (and accept demotes).
function RfsBotHijack.applyBeaconRoleState( beaconKey, role, masterKey )
	beaconKey = tostring( beaconKey or "" )
	local rec = RfsBotHijack.beacons[beaconKey]
	if not rec then
		return role or "independent", masterKey
	end
	if rec._roleDirty then
		rec._roleDirty = nil
		return normalizeBeaconRole( rec.role ), rec.masterKey
	end
	role = normalizeBeaconRole( role )
	rec.role = role
	if role == "slave" and masterKey then
		rec.masterKey = tostring( masterKey )
	else
		rec.masterKey = nil
	end
	-- Recompute effective slave for non-masters so storage can catch up.
	local effRole, effMaster = RfsBotHijack.effectiveBeaconRole( beaconKey )
	if role ~= "master" then
		return effRole, effMaster
	end
	return "master", nil
end

-- fullRange=true: already-hacked bots keep the beacon's real range (no raid 50% flicker).
function RfsBotHijack.coveringBeacon( unit, fullRange )
	if not unit or not sm.exists( unit ) or not unit.character or not sm.exists( unit.character ) then
		return nil
	end
	local pos = unit.character.worldPosition
	local world = nil
	pcall( function()
		world = unit.character:getWorld()
	end )
	local function rangeOf( rec )
		if fullRange then
			return tonumber( rec.range ) or DEFAULT_RANGE
		end
		return RfsBotHijack.effectiveRange( rec )
	end
	local preferred = nil
	local key = unitKey( unit )
	local info = key and RfsBotHijack.allies[key]
	if info and info.beaconKey then
		preferred = tostring( info.beaconKey )
	end
	local prefRec = preferred and RfsBotHijack.beacons[preferred]
	if prefRec and beaconLive( prefRec ) and prefRec.pos then
		local okWorld = true
		if world and prefRec.world then
			okWorld = sameWorld( world, prefRec.world )
		end
		if okWorld then
			local d2 = ( prefRec.pos - pos ):length2()
			local r = rangeOf( prefRec )
			if d2 <= r * r then
				return prefRec, preferred
			end
		end
	end
	local best, bestKey, bestD2 = nil, nil, nil
	for bkey, rec in pairs( RfsBotHijack.beacons ) do
		if rec and beaconLive( rec ) and rec.pos then
			local okWorld = true
			if world and rec.world then
				okWorld = sameWorld( world, rec.world )
			end
			if okWorld then
				local d2 = ( rec.pos - pos ):length2()
				local r = rangeOf( rec )
				if d2 <= r * r and ( bestD2 == nil or d2 < bestD2 ) then
					best = rec
					bestKey = bkey
					bestD2 = d2
				end
			end
		end
	end
	return best, bestKey
end

function RfsBotHijack.register( unit, ownerId, opts )
	if not unit or not sm.exists( unit ) then
		return false
	end
	local key = unitKey( unit )
	if not key then
		return false
	end
	opts = opts or {}
	local char = unit.character
	local t = charTypeStr( char )
	local prev = RfsBotHijack.allies[key]
	local mode = opts.mode or ( prev and prev.mode ) or "tethered"
	local orig = ( prev and prev.origColor ) or charColorHex( char )
	local firstSeen = opts.firstSeenTick or ( prev and prev.firstSeenTick ) or nowTick()
	local unitType = opts.unitType or ( prev and prev.unitType ) or t
	local beaconKey = opts.beaconKey or ( prev and prev.beaconKey )
	-- Sticky home for Rest/Defend/Farm jobs (survives infect / tether hops).
	local workBeaconKey = opts.workBeaconKey or ( prev and prev.workBeaconKey ) or beaconKey
	if workBeaconKey then
		workBeaconKey = tostring( workBeaconKey )
	end
	local order = opts.order or opts.rfsOrder or ( prev and ( prev.order or prev.rfsOrder ) )
	local allyColor = normalizeColorHex( opts.allyColor )
		or ( prev and normalizeColorHex( prev.allyColor ) )
		or domainColorFor( workBeaconKey or beaconKey )
	local displayName = opts.displayName or ( prev and prev.displayName )
	local displayIndex = tonumber( opts.displayIndex ) or ( prev and tonumber( prev.displayIndex ) )
	if displayName and isLegacyDisplayName( displayName ) then
		displayName = nil
		displayIndex = nil
	end
	if not displayName then
		displayName, displayIndex = makeDisplayName( unit, unitType or t, {
			beaconKey = beaconKey,
			workBeaconKey = workBeaconKey,
			displayIndex = displayIndex,
			displayName = prev and prev.displayName,
		} )
	else
		local _, n = parseTypeNumberName( displayName )
		displayIndex = displayIndex or n
		if displayIndex then
			allocDomainIndex( namingDomainKey( workBeaconKey or beaconKey ), key, displayIndex )
		end
	end
	local charName = nil
	pcall( function()
		if char and sm.exists( char ) and char.getName then
			charName = char:getName()
		end
	end )
	local botType = opts.botType or ( prev and prev.botType )
		or RfsBotHijack.classifyBotKind( unitType or t, displayName or charName )
	local typeLetter = opts.typeLetter or ( prev and prev.typeLetter )
		or RfsBotHijack.typeLetterFor( botType, displayName or charName )
	RfsBotHijack.allies[key] = {
		type = t,
		unitType = unitType,
		botType = botType,
		typeLetter = typeLetter,
		owner = ownerId or ( prev and prev.owner ),
		mode = mode,
		beaconKey = beaconKey,
		workBeaconKey = workBeaconKey,
		order = order,
		rfsOrder = order, -- alias for RfsBotOrders / saved.rfsOrder naming
		origColor = orig,
		allyColor = allyColor,
		infectAcc = ( prev and prev.infectAcc ) or 0,
		hijackTicks = tonumber( opts.hijackTicks ) or ( prev and prev.hijackTicks ) or 320,
		controlled = true,
		displayName = displayName,
		displayIndex = displayIndex,
		firstSeenTick = firstSeen,
		lastTagTick = prev and prev.lastTagTick or 0,
	}
	if char and sm.exists( char ) then
		applyAllyVisualColor( char, RfsBotHijack.allies[key] )
	end
	pushIdentityToUnit( unit, {
		owner = RfsBotHijack.allies[key].owner,
		displayName = displayName,
		displayIndex = displayIndex,
		unitType = unitType,
		botType = botType,
		typeLetter = typeLetter,
		firstSeenTick = firstSeen,
		mode = mode,
		beaconKey = RfsBotHijack.allies[key].beaconKey,
		workBeaconKey = RfsBotHijack.allies[key].workBeaconKey,
		allyColor = allyColor,
		playerAlly = true,
	} )
	RfsBotHijack.publishGlobals()
	return true
end

function RfsBotHijack.unregister( unit )
	-- Loss of ally status: never hackable again until death.
	if unit and sm.exists( unit ) then
		RfsBotHijack.setHackable( unit, false )
	end
	local key = unitKey( unit )
	if key then
		RfsBotHijack.allies[key] = nil
		if RfsBotHijack.drops then
			RfsBotHijack.drops[key] = nil
		end
		if RfsBotHijack.jams then
			RfsBotHijack.jams[key] = nil
		end
		if RfsBotHijack.pending then
			RfsBotHijack.pending[key] = nil
		end
		if RfsBotHijack.chain then
			RfsBotHijack.chain[key] = nil
		end
	end
end

function RfsBotHijack.revert( unit )
	if not unit or not sm.exists( unit ) then
		return
	end
	local key = unitKey( unit )
	local info = key and RfsBotHijack.allies[key]
	local char = unit.character
	if info and info.origColor and char and sm.exists( char ) then
		local okCol, col = pcall( sm.color.new, info.origColor )
		if okCol and col then
			applyColor( char, col )
		end
	end
	if key then
		RfsBotHijack.jams = RfsBotHijack.jams or {}
		RfsBotHijack.jams[key] = nil
		if not ( RfsBotHijack.banned and RfsBotHijack.banned[key] ) then
			local now = 0
			pcall( function()
				now = sm.game.getCurrentTick()
			end )
			RfsBotHijack.lockout = RfsBotHijack.lockout or {}
			RfsBotHijack.lockout[key] = now + 40
		end
	end
	RfsBotHijack.ban( unit )
	RfsBotHijack.setHackable( unit, false )
	RfsBotHijack.unregister( unit )
	pcall( function()
		sm.event.sendToUnit( unit, "sv_e_receiveTarget", { targetCharacter = nil, sendingUnit = unit } )
	end )
	RfsBotHijack.publishGlobals()
end

function RfsBotHijack.prune( world )
	local keep = {}
	local live = {}
	for _, u in ipairs( allUnits( world ) ) do
		if sm.exists( u ) then
			live[unitKey( u )] = u
		end
	end
	for key, info in pairs( RfsBotHijack.allies ) do
		if live[key] then
			keep[key] = info
		end
	end
	RfsBotHijack.allies = keep
	if RfsBotHijack.banned then
		local nextBan = {}
		for key, v in pairs( RfsBotHijack.banned ) do
			local unit = live[key]
			if unit then
				-- Still in this world's scan — keep and refresh the ref.
				nextBan[key] = unit or v
			else
				-- Missing from this scan is NOT proof of death (other world / empty getAllUnits).
				-- Only drop the ban when we have a unit ref and sm.exists is confirmed false.
				local confirmedDead = false
				if v and v ~= true then
					local ok, exists = pcall( sm.exists, v )
					if ok and exists == false then
						confirmedDead = true
					end
				end
				if not confirmedDead then
					nextBan[key] = v
				end
			end
		end
		RfsBotHijack.banned = nextBan
	end
	RfsBotHijack.publishGlobals()
end

-- Refresh tether vs infection. Call from Game.server_onFixedUpdate.
function RfsBotHijack.tick( world )
	RfsBotHijack.ensureHooks()
	RfsBotHijack.tickAuto( world )
	RfsBotHijack.prune( world )
	local now = 0
	pcall( function()
		now = sm.game.getCurrentTick()
	end )
	local live = {}
	for _, u in ipairs( allUnits( world ) ) do
		if sm.exists( u ) then
			live[unitKey( u )] = u
		end
	end
	local drop = {}
	for key, info in pairs( RfsBotHijack.allies ) do
		local unit = live[key]
		if not unit then
			drop[#drop + 1] = key
		else
			RfsBotHijack._tickRaidJam( unit, key, info, now )
			if info.doomed or ( RfsBotHijack.jams and RfsBotHijack.jams[key] ) then
				info.controlled = true
				info.doomed = true
			elseif info.mode == "infected" then
				info.controlled = true
				if unit.character and sm.exists( unit.character ) then
					applyAllyVisualColor( unit.character, info )
				end
			else
				local rec, bkey = RfsBotHijack.coveringBeacon( unit, true )
				if rec and bkey then
					info.controlled = true
					info.beaconKey = bkey
					if rec.hijackTicks then
						info.hijackTicks = rec.hijackTicks
					end
					if rec.canInfect then
						info.infectAcc = ( info.infectAcc or 0 ) + 10 -- tick is ~every 10 game ticks
						local need = tonumber( rec.infectTicks ) or 320
						if info.infectAcc >= need then
							info.mode = "infected"
							info.workBeaconKey = info.workBeaconKey or info.beaconKey or bkey
							info.beaconKey = nil
							info.infectAcc = 0
							-- Keep Type N identity; only mode changes.
							if not info.displayName or isLegacyDisplayName( info.displayName ) then
								info.displayName, info.displayIndex = makeDisplayName( unit, info.unitType or info.type, {
									workBeaconKey = info.workBeaconKey,
									beaconKey = bkey,
									displayIndex = info.displayIndex,
								} )
							end
							if not info.allyColor then
								info.allyColor = domainColorFor( info.workBeaconKey or bkey )
							end
							local ord = info.rfsOrder or info.order
							if type( ord ) == "table" then
								ord.beaconKey = info.workBeaconKey
								info.rfsOrder = ord
								info.order = ord
							end
							pushIdentityToUnit( unit, {
								owner = info.owner,
								displayName = info.displayName,
								displayIndex = info.displayIndex,
								unitType = info.unitType or info.type,
								botType = info.botType,
								typeLetter = info.typeLetter,
								firstSeenTick = info.firstSeenTick,
								mode = "infected",
								workBeaconKey = info.workBeaconKey,
								allyColor = info.allyColor,
								playerAlly = true,
							} )
							if unit.character and sm.exists( unit.character ) then
								applyAllyVisualColor( unit.character, info )
							end
						end
					else
						info.infectAcc = 0
						if unit.character and sm.exists( unit.character ) then
							applyAllyVisualColor( unit.character, info )
						end
					end
				end
				-- Out of range / unpowered: DROP countdown in tickAuto. Infected never drop here.
			end
			-- Idle nametag (skip while HACK/DROP/CHAIN tags are active).
			local busy = ( RfsBotHijack.pending and RfsBotHijack.pending[key] )
				or ( RfsBotHijack.drops and RfsBotHijack.drops[key] )
				or ( RfsBotHijack.jams and RfsBotHijack.jams[key] )
			if not busy and info.controlled and info.displayName then
				local last = info.lastTagTick or 0
				if ( now - last ) >= IDENTITY_TAG_EVERY then
					info.lastTagTick = now
					RfsBotHijack.pushTag( unit, info.displayName, "name" )
				end
			end
		end
	end
	for _, key in ipairs( drop ) do
		RfsBotHijack.allies[key] = nil
	end
	RfsBotHijack.publishGlobals()
end

local function closestOtherRobotCharacter( selfUnit, wantAlly, maxRange )
	if not selfUnit or not selfUnit.character then
		return nil
	end
	local myPos = selfUnit.character.worldPosition
	local myWorld = selfUnit.character:getWorld()
	local best, bestD2 = nil, nil
	local maxD2 = ( maxRange or ALLY_AGGRO_RANGE ) * ( maxRange or ALLY_AGGRO_RANGE )
	for _, u in ipairs( allUnits( myWorld ) ) do
		if sm.exists( u ) and u ~= selfUnit and u.character and sm.exists( u.character ) then
			local okWorld = true
			pcall( function()
				okWorld = ( u.character:getWorld() == myWorld )
			end )
			if okWorld and RfsBotHijack.isRobotCharacter( u.character ) then
				local isA = RfsBotHijack.isAlly( u )
				if isA == wantAlly then
					local d2 = ( u.character.worldPosition - myPos ):length2()
					if d2 <= maxD2 and ( bestD2 == nil or d2 < bestD2 ) then
						best = u.character
						bestD2 = d2
					end
				end
			end
		end
	end
	return best
end

function RfsBotHijack.convertUnit( unit, ownerId, opts )
	if not hackableRobotsOn() then
		return false, "hackable robots disabled by host"
	end
	if not unit or not sm.exists( unit ) then
		return false, "gone"
	end
	if not unit.character or not RfsBotHijack.isRobotCharacter( unit.character ) then
		return false, "not a robot"
	end
	if RfsBotHijack.isUndergroundBotCharacter( unit.character ) and not undergroundBotsOn() then
		return false, "underground bots disabled by host"
	end
	if not RfsBotHijack.isHackable( unit ) then
		return false, "not hackable"
	end
	if RfsBotHijack.isDoomed( unit ) then
		return false, "doomed"
	end
	if RfsBotHijack.isLockedOut( unit ) then
		return false, "locked out"
	end
	if RfsBotHijack.isAlly( unit ) then
		return false, "already ally"
	end
	opts = opts or {}
	if not opts.firstSeenTick then
		opts.firstSeenTick = nowTick()
	end
	if not opts.unitType then
		opts.unitType = charTypeStr( unit.character )
	end
	-- Inherit domain Orders color so fresh hijacks match listed allies.
	if not opts.allyColor then
		opts.allyColor = domainColorFor( opts.workBeaconKey or opts.beaconKey )
	end
	if opts.displayName and isLegacyDisplayName( opts.displayName ) then
		opts.displayName = nil
	end
	if not opts.displayName then
		local name, idx = makeDisplayName( unit, opts.unitType, opts )
		opts.displayName = name
		opts.displayIndex = idx
	end
	RfsBotHijack.register( unit, ownerId, opts )
	-- Captured raiders leave the raid list immediately (same as destroy).
	pcall( function()
		sm.event.sendToUnit( unit, "sv_e_rfsLeaveRaid", {} )
	end )
	pcall( function()
		if type( RfsBotOrders ) == "table" and RfsBotOrders.ensureDefaultOrder then
			RfsBotOrders.ensureDefaultOrder( unit, ownerId, opts )
		end
	end )
	pcall( function()
		sm.event.sendToUnit( unit, "sv_e_receiveTarget", { targetCharacter = nil, sendingUnit = unit } )
	end )
	local mode = opts.mode or "tethered"
	local info = RfsBotHijack.allies[unitKey( unit )]
	if info and info.displayName then
		RfsBotHijack.pushTag( unit, info.displayName, "name" )
	end
	return true, ( charTypeStr( unit.character ) or "robot" ) .. " (" .. mode .. ")"
end

-- Voluntary release (Phase 5 lite). Does NOT ban / lock like raid releaseHack.
function RfsBotHijack.releaseVoluntary( unit )
	if not unit or not sm.exists( unit ) then
		return false, "gone"
	end
	local key = unitKey( unit )
	local info = key and RfsBotHijack.allies[key]
	local char = unit.character
	if info and info.origColor and char and sm.exists( char ) then
		local okCol, col = pcall( sm.color.new, info.origColor )
		if okCol and col then
			applyColor( char, col )
		end
	end
	RfsBotHijack.pushTag( unit, "" )
	clearIdentityOnUnit( unit )
	if key then
		RfsBotHijack.allies[key] = nil
		if RfsBotHijack.drops then
			RfsBotHijack.drops[key] = nil
		end
		if RfsBotHijack.jams then
			RfsBotHijack.jams[key] = nil
		end
		if RfsBotHijack.pending then
			RfsBotHijack.pending[key] = nil
		end
		if RfsBotHijack.chain then
			RfsBotHijack.chain[key] = nil
		end
		if RfsBotHijack.chainSkip then
			RfsBotHijack.chainSkip[key] = nil
		end
		-- Clear peacetime lockout only; never touch raid bans.
		if RfsBotHijack.lockout then
			RfsBotHijack.lockout[key] = nil
		end
	end
	pcall( function()
		sm.event.sendToUnit( unit, "sv_e_receiveTarget", { targetCharacter = nil, sendingUnit = unit } )
	end )
	RfsBotHijack.publishGlobals()
	return true, "released"
end

function RfsBotHijack.unhijackNearest( player, range, world, allowAny )
	range = tonumber( range ) or DEFAULT_RANGE
	if not player or not player.character then
		return 0, "no player"
	end
	world = world or worldOfPlayer( player )
	if not world then
		return 0, "no world on player"
	end
	local pos = player.character.worldPosition
	local ownerId = nil
	pcall( function()
		ownerId = player.id
	end )
	local best, bestD2 = nil, nil
	local maxD2 = range * range
	for _, u in ipairs( allUnits( world ) ) do
		if sm.exists( u ) and u.character and sm.exists( u.character ) and RfsBotHijack.isAlly( u ) then
			local info = RfsBotHijack.allies[unitKey( u )]
			local okOwner = allowAny or ( info and info.owner ~= nil and tostring( info.owner ) == tostring( ownerId ) )
			if okOwner then
				local okWorld = true
				pcall( function()
					okWorld = ( u.character:getWorld() == world )
				end )
				if okWorld then
					local d2 = ( u.character.worldPosition - pos ):length2()
					if d2 <= maxD2 and ( bestD2 == nil or d2 < bestD2 ) then
						best = u
						bestD2 = d2
					end
				end
			end
		end
	end
	if not best then
		return 0, allowAny and "no ally robot in range" or "no owned ally in range"
	end
	local label = charTypeStr( best.character ) or "robot"
	local ok, why = RfsBotHijack.releaseVoluntary( best )
	if ok then
		return 1, label
	end
	return 0, tostring( why )
end

function RfsBotHijack.convertNearest( player, range, world )
	if not hackableRobotsOn() then
		return 0, "hackable robots disabled by host"
	end
	range = tonumber( range ) or DEFAULT_RANGE
	if not player or not player.character then
		return 0, "no player"
	end
	local pos = player.character.worldPosition
	world = world or worldOfPlayer( player )
	if not world then
		return 0, "no world on player"
	end
	local units = allUnits( world )
	if #units == 0 then
		return 0, "world unit scan empty (range " .. tostring( range ) .. ")"
	end
	local best, bestD2 = nil, nil
	local maxD2 = range * range
	for _, u in ipairs( units ) do
		if sm.exists( u ) and u.character and sm.exists( u.character ) then
			if RfsBotHijack.isRobotCharacter( u.character ) and not RfsBotHijack.isAlly( u ) and RfsBotHijack.isHackable( u )
				and not ( RfsBotHijack.isUndergroundBotCharacter( u.character ) and not undergroundBotsOn() ) then
				local okWorld = true
				pcall( function()
					okWorld = ( u.character:getWorld() == world )
				end )
				if okWorld then
					local d2 = ( u.character.worldPosition - pos ):length2()
					if d2 <= maxD2 and ( bestD2 == nil or d2 < bestD2 ) then
						best = u
						bestD2 = d2
					end
				end
			end
		end
	end
	if not best then
		return 0, "no hostile robot in range"
	end
	-- Chat /hijack is a cheat: permanent infection (no beacon required).
	local ok, label = RfsBotHijack.convertUnit( best, player.id, { mode = "infected" } )
	if ok then
		return 1, label
	end
	return 0, tostring( label )
end

function RfsBotHijack.convertInRange( originPos, world, range, ownerId, opts )
	range = tonumber( range ) or DEFAULT_RANGE
	local n = 0
	local maxD2 = range * range
	for _, u in ipairs( allUnits( world ) ) do
		if sm.exists( u ) and u.character and sm.exists( u.character ) then
			if RfsBotHijack.isRobotCharacter( u.character ) and not RfsBotHijack.isAlly( u ) and RfsBotHijack.isHackable( u )
				and not ( RfsBotHijack.isUndergroundBotCharacter( u.character ) and not undergroundBotsOn() ) then
				local okWorld = true
				pcall( function()
					okWorld = ( u.character:getWorld() == world )
				end )
				if okWorld then
					local d2 = ( u.character.worldPosition - originPos ):length2()
					if d2 <= maxD2 then
						local ok = RfsBotHijack.convertUnit( u, ownerId, opts )
						if ok then
							n = n + 1
						end
					end
				end
			end
		end
	end
	return n
end

function RfsBotHijack.count( world )
	RfsBotHijack.prune( world )
	local n, tethered, infected = 0, 0, 0
	for _, info in pairs( RfsBotHijack.allies ) do
		if info.controlled then
			n = n + 1
			if info.mode == "infected" then
				infected = infected + 1
			else
				tethered = tethered + 1
			end
		end
	end
	return n, tethered, infected
end

local function capturePos( rec, unit )
	if not rec or not unit or not unit.character or not sm.exists( unit.character ) then
		return
	end
	pcall( function()
		local p = unit.character.worldPosition
		rec.x = p.x
		rec.y = p.y
		rec.z = p.z
	end )
end

local function kindFromText( text )
	text = tostring( text or "" )
	if string.find( text, "JAM", 1, true ) or string.find( text, "BOOM", 1, true ) then
		return "jam"
	end
	if string.find( text, "DROP", 1, true ) then
		return "drop"
	end
	if string.find( text, "NO BAT", 1, true ) then
		return "nobat"
	end
	if string.find( text, "CHAIN", 1, true ) then
		return "chain"
	end
	-- Type N nametags (Tote 1) — anything else with letters+number is still a name.
	if parseTypeNumberName( text ) then
		return "name"
	end
	if string.find( text, "Ally ", 1, true ) or string.find( text, "Inf ", 1, true ) then
		return "name"
	end
	return "hack"
end

function RfsBotHijack.pushTag( unit, text, kind )
	if not unit or not sm.exists( unit ) or not unit.character or not sm.exists( unit.character ) then
		return
	end
	RfsBotHijack.ensureCharHooks()
	text = tostring( text or "" )
	kind = kind or kindFromText( text )
	pcall( function()
		sm.event.sendToCharacter( unit.character, "sv_e_rfsTag", { text = text, kind = kind } )
	end )
end

local function setUnitTag( unit, text, kind )
	RfsBotHijack.pushTag( unit, text, kind )
end

function RfsBotHijack.clearUnitTag( unit )
	setUnitTag( unit, "" )
end

function RfsBotHijack.cl_destroyCharTag( self )
	if self and self.cl and self.cl.rfsTagFx then
		pcall( function()
			if sm.exists( self.cl.rfsTagFx ) then
				self.cl.rfsTagFx:stop()
				self.cl.rfsTagFx:destroy()
			end
		end )
		self.cl.rfsTagFx = nil
	end
end

function RfsBotHijack.cl_applyCharTag( self, data )
	if not self then
		return
	end
	self.cl = self.cl or {}
	local text = data and tostring( data.text or "" ) or ""
	local kind = ( data and data.kind ) or kindFromText( text )
	local prev = self.cl.rfsLastTag
	-- Skip no-op re-applies (client_onUpdate used to recreate FX every frame).
	if prev and prev.text == text and prev.kind == kind and text ~= "" then
		local fx = self.cl.rfsTagFx
		local alive = false
		pcall( function()
			alive = fx and sm.exists( fx ) and fx:isPlaying()
		end )
		if alive then
			return
		end
	end
	self.cl.rfsLastTag = { text = text, kind = kind }
	if text == "" then
		RfsBotHijack.cl_destroyCharTag( self )
		-- Clear Survival character debug text channel so animation labels
		-- (e.g. "Balanced") cannot stack with leftover RFS fallbacks.
		pcall( function()
			sm.gui.setCharacterDebugText( self.character, "" )
		end )
		return
	end
	local fx = self.cl.rfsTagFx
	local alive = false
	pcall( function()
		alive = fx and sm.exists( fx )
	end )
	if not alive then
		-- Never use vanilla DebugText — it shares the character debug channel
		-- with Survival animation labels and causes overlapping "Balanced"/etc.
		local names = { "RfsHackText", "RfsGrowText" }
		for _, name in ipairs( names ) do
			local ok, created = pcall( sm.effect.createEffect, name, self.character, nil, sm.effect.axis.all )
			if not ( ok and created ) then
				ok, created = pcall( sm.effect.createEffect, name, self.character )
			end
			if not ( ok and created ) then
				ok, created = pcall( sm.effect.createEffect, name, self.character, "jnt_head" )
			end
			if ok and created then
				fx = created
				break
			end
		end
		if fx then
			self.cl.rfsTagFx = fx
			pcall( function()
				local h = 1.35
				pcall( function()
					h = self.character:getHeight()
				end )
				fx:setOffsetPosition( sm.vec3.new( 0, 0, h ) )
				fx:start()
			end )
		end
	end
	local colors = {
		hack = sm.color.new( 1.0, 0.72, 0.08, 1.0 ),
		drop = sm.color.new( 1.0, 0.28, 0.12, 1.0 ),
		jam = sm.color.new( 1.0, 0.18, 0.18, 1.0 ),
		nobat = sm.color.new( 1.0, 0.35, 0.15, 1.0 ),
		name = sm.color.new( 0.35, 0.95, 0.55, 1.0 ),
		chain = sm.color.new( 0.75, 0.95, 0.35, 1.0 ),
	}
	if fx then
		pcall( function()
			fx:setParameter( "TextContent", text )
			fx:setParameter( "Color", colors[kind] or colors.hack )
			if not fx:isPlaying() then
				fx:start()
			end
		end )
	end
	-- Intentionally no setCharacterDebugText fallback (dual text / Balanced overlap).
end

function RfsBotHijack.ensureCharHooks()
	local function wrapClientData( cls )
		if type( cls ) ~= "table" then
			return
		end
		function cls.sv_e_rfsTag( self, params )
			pcall( function()
				self.network:sendToClients( "cl_e_rfsTag", params or { text = "" } )
			end )
		end
		function cls.cl_e_rfsTag( self, params )
			RfsBotHijack.cl_applyCharTag( self, params )
		end
		function cls.sv_e_rfsUnmarkRaid( self, params )
			pcall( function()
				self.network:sendToClients( "cl_e_rfsUnmarkRaid", params or {} )
			end )
		end
		function cls.cl_e_rfsUnmarkRaid( self, params )
			self.cl = self.cl or {}
			local raidKey = ( params and params.raidKey ) or self.cl.raidKey
			if raidKey and self.character then
				pcall( function()
					if type( RaidManager ) == "table" and RaidManager.Cl_RemoveTrackedRaidEnemy then
						RaidManager.Cl_RemoveTrackedRaidEnemy( raidKey, self.character )
					end
				end )
			end
			self.cl.raidKey = nil
			self.cl.markedRaider = nil
		end
		if cls._rfsTagRpc then
			return
		end
		local origU = cls.client_onUpdate
		cls.client_onUpdate = function( self, dt )
			if origU then
				origU( self, dt )
			end
			-- Re-seat FX only if lost; do not recreate every frame.
			local tag = self.cl and self.cl.rfsLastTag
			if tag and tag.text and tag.text ~= "" then
				local fx = self.cl.rfsTagFx
				local alive = false
				pcall( function()
					alive = fx and sm.exists( fx )
				end )
				if not alive then
					RfsBotHijack.cl_applyCharTag( self, tag )
				end
			end
		end
		local origD = cls.client_onDestroy
		cls.client_onDestroy = function( self )
			RfsBotHijack.cl_destroyCharTag( self )
			if origD then
				origD( self )
			end
		end
		cls._rfsTagRpc = true
	end
	wrapClientData( _G.BaseEnemyCharacter )
	local names = {
		"TotebotCharacter", "TotebotRedCharacter", "TotebotBlueCharacter",
		"TotebotYellowCharacter", "TotebotLeafCharacter", "HaybotCharacter",
		"FarmbotCharacter", "TapebotCharacter", "MinerbotCharacter",
		"CablebotCharacter", "LootbotCharacter", "SeedbotCharacter",
		"TrashbotCharacter", "ScannerbotCharacter",
	}
	for _, name in ipairs( names ) do
		wrapClientData( _G[name] )
	end
end

-- Drop this unit from RaidManager as if destroyed (capture / convert / stand-down).
-- Must run BEFORE clearing saved.raidKey — otherwise RobotOnDestroy never removes them
-- and the raid timer keeps running with "ghost" enemies.
function RfsBotHijack.leaveRaidList( self )
	if not self or not self.saved then
		return false
	end
	local raidKey = self.saved.raidKey
	if not raidKey then
		return false
	end
	local unit = self.unit
	if unit and sm.exists( unit ) then
		pcall( function()
			if type( RaidManager ) == "table" and RaidManager.Sv_RemoveRaider then
				RaidManager.Sv_RemoveRaider( raidKey, unit )
			end
		end )
		-- Clear client raid compass / tracked enemy while the bot is still alive.
		pcall( function()
			local char = unit.character
			if char and sm.exists( char ) then
				sm.event.sendToCharacter( char, "sv_e_rfsUnmarkRaid", { raidKey = raidKey } )
			end
		end )
	end
	self.saved.raidKey = nil
	return true
end

-- Abort raid wall-smash. Raiders keep punching creations until raider/raidPosition is cleared.
-- Captured/hijacked bots also leave the raid list here (same as destroy).
function RfsBotHijack.standDown( self )
	if not self then
		return
	end
	self.saved = self.saved or {}
	local dirty = false
	if self.saved.raidKey then
		RfsBotHijack.leaveRaidList( self )
		dirty = true
	end
	if self.saved.raider then
		self.saved.raider = false
		dirty = true
	end
	if self.saved.raidPosition ~= nil then
		self.saved.raidPosition = nil
		dirty = true
	end
	if self.saved.raidCenter ~= nil then
		self.saved.raidCenter = nil
		dirty = true
	end
	if self.saved.destroyShapes then
		self.saved.destroyShapes = false
		dirty = true
	end
	if self.saved.randomPlotTarget ~= nil then
		self.saved.randomPlotTarget = nil
		dirty = true
	end
	if dirty then
		self.isDirty = true
	end
	pcall( function()
		if self.pathingState and self.pathingState.sv_setRaider then
			self.pathingState:sv_setRaider( false )
		end
	end )
	local smash = self.currentState
		and ( self.currentState == self.breachState
			or self.currentState == self.voxelBreachState
			or self.currentState == self.raidPathingState
			or self.currentState == self.raidRepositionState )
	if smash then
		self.currentState = self.idleState or self.pathingState or self.currentState
	end
end

-- Hostiles / workers pulled onto raid pathing off the origin cell: drop raid AI.
-- Allies always standDown separately. Capture/destroy still uses leaveRaidList.
function RfsBotHijack.clearOffTileRaidAi( self )
	if not self or not self.saved or not self.saved.raider then
		return
	end
	if self.unit and RfsBotHijack.isAlly( self.unit ) then
		return
	end
	local pos = nil
	local world = nil
	pcall( function()
		if self.unit and self.unit.character then
			pos = self.unit.character.worldPosition
			world = self.unit.character:getWorld()
		end
	end )
	if pos and RfsBotHijack.outsideRaidTile( pos, world ) then
		RfsBotHijack.standDown( self )
	end
end

function RfsBotHijack.isFarmbot( unit )
	if not unit or not unit.character or not sm.exists( unit.character ) then
		return false
	end
	local t = nil
	pcall( function()
		t = unit.character:getCharacterType()
	end )
	if not t then
		return false
	end
	local farm = unit_farmbot or UUID_FARMBOT
	return t == farm or t == UUID_FARMBOT or tostring( t ) == tostring( farm )
end

-- Red-tote self-destruct, damage turned down. Farmbot only gets ×1.25.
function RfsBotHijack.popUnit( unit )
	if not unit or not sm.exists( unit ) then
		return
	end
	local char = unit.character
	local pos = nil
	local col = nil
	pcall( function()
		if char and sm.exists( char ) then
			pos = char.worldPosition
			col = char:getColor()
		end
	end )
	local mul = RfsBotHijack.isFarmbot( unit ) and BIG_RED_MUL or 1.0
	local level = math.floor( RED_LEVEL * mul + 0.5 )
	local radius = RED_RADIUS * mul
	local impR = RED_IMPULSE_R * mul
	local imp = RED_IMPULSE * mul
	local dmg = RED_DAMAGE * mul
	RfsBotHijack.pushTag( unit, "" )
	RfsBotHijack.unregister( unit )
	if pos then
		pcall( function()
			sm.physics.explode( pos, level, radius, impR, imp, "Totebotred - Explosion", nil, col and { Color = col } or nil, nil, dmg )
		end )
	end
	pcall( function()
		unit:destroy()
	end )
end

-- Raid hack-loss: banned until death. 30% red-tote pop (farmbot 1.25×).
-- Off the raid tile: no-op (keep hack). Voluntary unhijack uses releaseVoluntary.
function RfsBotHijack.releaseHack( unit, duringRaid )
	if not unit or not sm.exists( unit ) then
		return
	end
	local pos = nil
	local world = nil
	pcall( function()
		pos = unit.character.worldPosition
		world = unit.character:getWorld()
	end )
	if duringRaid and pos and RfsBotHijack.outsideRaidTile( pos, world ) then
		return
	end
	if duringRaid and not ( pos and RfsBotHijack.areaHasRaid( pos, world ) ) then
		duringRaid = false
	end
	RfsBotHijack.ban( unit )
	RfsBotHijack.setHackable( unit, false )
	if duringRaid then
		RfsBotHijack.ban( unit )
		if math.random() <= FIGHT_EXPLODE_CHANCE then
			if RfsBotHijack.isFarmbot( unit ) then
				RfsBotHijack.announce( "FARM BOT OVERLOAD" )
			else
				RfsBotHijack.announce( "SCRAMBLE POP" )
			end
			RfsBotHijack.popUnit( unit )
			return
		end
		RfsBotHijack.announce( "HACK BROKEN — locked" )
	end
	RfsBotHijack.revert( unit )
end

RfsBotHijack.jams = RfsBotHijack.jams or {}

function RfsBotHijack._tickRaidJam( unit, key, info, now )
	if not unit or not info then
		return
	end
	RfsBotHijack.jams = RfsBotHijack.jams or {}
	local pos = nil
	local world = nil
	pcall( function()
		pos = unit.character.worldPosition
		world = unit.character:getWorld()
	end )
	if pos and RfsBotHijack.outsideRaidTile( pos, world ) then
		RfsBotHijack.jams[key] = nil
		info.doomed = nil
		info.raidCheckTick = nil
		return
	end
	if RfsBotHijack.jams[key] or info.doomed then
		RfsBotHijack.jams[key] = nil
		info.doomed = nil
		RfsBotHijack.releaseHack( unit, true )
		return
	end
	local inRaid = pos and RfsBotHijack.areaHasRaid( pos, world )
	if not inRaid then
		info.raidCheckTick = nil
		return
	end
	local last = info.raidCheckTick or 0
	if now - last < RAID_JAM_CHECK_TICKS then
		return
	end
	info.raidCheckTick = now
	if math.random() <= RAID_JAM_CHANCE then
		RfsBotHijack.releaseHack( unit, true )
	end
end

-- Auto-hijack hostiles inside a powered beacon field. 40 ticks = 1 s.
-- Call from a world script (beacon / hideout). Deduped to once per game tick.
function RfsBotHijack.tickAuto( world )
	local now = 0
	pcall( function()
		now = sm.game.getCurrentTick()
	end )
	if now == RfsBotHijack._autoTick then
		return
	end
	RfsBotHijack._autoTick = now
	RfsBotHijack.pending = RfsBotHijack.pending or {}

	local live = {}
	for _, u in ipairs( allUnits( world ) ) do
		if sm.exists( u ) then
			live[unitKey( u )] = u
		end
	end

	-- Host disabled hackable robots: skip auto-hijack / convert tick; clear pending.
	-- Ally maintenance (signal loss / raid jam) and ensureHooks stay active.
	if not hackableRobotsOn() then
		for key, pend in pairs( RfsBotHijack.pending ) do
			local unit = live[key]
			if unit then
				setUnitTag( unit, "" )
			end
		end
		RfsBotHijack.pending = {}
		RfsBotHijack._tickChainConvert( live, now )
		RfsBotHijack._tickSignalLoss( live, now )
		for key, info in pairs( RfsBotHijack.allies or {} ) do
			local unit = live[key]
			if unit and sm.exists( unit ) then
				RfsBotHijack._tickRaidJam( unit, key, info, now )
			end
		end
		return
	end

	local nextPending = {}
	for key, pend in pairs( RfsBotHijack.pending ) do
		local unit = live[key]
		if unit and sm.exists( unit ) and not RfsBotHijack.isAlly( unit ) and not RfsBotHijack.isLockedOut( unit ) and RfsBotHijack.isHackable( unit ) then
			local rec, bkey = RfsBotHijack.coveringBeacon( unit )
			local need = rec and ( tonumber( rec.hijackTicks ) or 320 ) or 0
			if rec and rec.powered and need > 0 then
				if pend.beaconKey ~= bkey then
					pend.startTick = now
					pend.beaconKey = bkey
					pend.need = need
				end
				pend.need = need
				local elapsed = now - ( pend.startTick or now )
				local remainTicks = pend.need - elapsed
				if remainTicks <= 0 then
					local spent = true
					if type( rec.spendOne ) == "function" then
						local okSpend, result = pcall( rec.spendOne )
						spent = okSpend and result and true or false
					end
					if spent then
						local mode = rec.canInfect and "infected" or "tethered"
						local workKey = bkey
						if type( RfsBotHijack.orderDomainMasterKey ) == "function" then
							pcall( function()
								workKey = RfsBotHijack.orderDomainMasterKey( bkey ) or bkey
							end )
						end
						RfsBotHijack.convertUnit( unit, rec.ownerId or 0, {
							mode = mode,
							beaconKey = bkey,
							workBeaconKey = workKey,
							hijackTicks = rec.hijackTicks or need,
						} )
						setUnitTag( unit, "" )
					else
						pend.text = "NO BAT"
						capturePos( pend, unit )
						setUnitTag( unit, "NO BAT", "nobat" )
						pend.startTick = now - ( pend.need - 1 )
						nextPending[key] = pend
					end
				else
					local sec = remainTicks / 40
					pend.text = string.format( "HACK %.1f", sec )
					capturePos( pend, unit )
					setUnitTag( unit, pend.text, "hack" )
					nextPending[key] = pend
				end
			else
				setUnitTag( unit, "" )
			end
		elseif unit then
			setUnitTag( unit, "" )
		end
	end

	for key, unit in pairs( live ) do
		if not nextPending[key] and not RfsBotHijack.isAlly( unit ) and not RfsBotHijack.isLockedOut( unit ) and RfsBotHijack.isHackable( unit ) then
			if unit.character and sm.exists( unit.character ) and RfsBotHijack.isRobotCharacter( unit.character ) then
				if not ( RfsBotHijack.isUndergroundBotCharacter( unit.character ) and not undergroundBotsOn() ) then
					local rec, bkey = RfsBotHijack.coveringBeacon( unit )
					local need = rec and ( tonumber( rec.hijackTicks ) or 0 ) or 0
					if rec and rec.powered and need > 0 then
						local pend = {
							startTick = now,
							need = need,
							beaconKey = bkey,
							text = string.format( "HACK %.1f", need / 40 ),
						}
						capturePos( pend, unit )
						nextPending[key] = pend
						setUnitTag( unit, pend.text, "hack" )
						RfsBotHijack.announce( pend.text )
					end
				end
			end
		end
	end

	RfsBotHijack.pending = nextPending
	RfsBotHijack._tickChainConvert( live, now )
	RfsBotHijack._tickSignalLoss( live, now )
	for key, info in pairs( RfsBotHijack.allies or {} ) do
		local unit = live[key]
		if unit and sm.exists( unit ) then
			RfsBotHijack._tickRaidJam( unit, key, info, now )
		end
	end
end

RfsBotHijack.drops = RfsBotHijack.drops or {} -- [unitKey] = { startTick, need, text }

-- CHAIN 0.0 = convert finished the countdown but did not complete. Never leave
-- that debug tag up, and never retry forever (that froze AI on raid-list leftovers).
local function chainTagOwnedByOther( key )
	return ( RfsBotHijack.pending and RfsBotHijack.pending[key] )
		or ( RfsBotHijack.drops and RfsBotHijack.drops[key] )
		or ( RfsBotHijack.jams and RfsBotHijack.jams[key] )
end

local abortChainGhost

local function isChainSkipped( key )
	return key ~= nil and RfsBotHijack.chainSkip and RfsBotHijack.chainSkip[key] == true
end

-- Leftover / failed convert: never restart the CHAIN overlay on this unit.
local function skipChainUnit( unit )
	if not unit then
		return
	end
	local key = unitKey( unit )
	if key then
		RfsBotHijack.chainSkip = RfsBotHijack.chainSkip or {}
		RfsBotHijack.chainSkip[key] = true
		if RfsBotHijack.chain then
			RfsBotHijack.chain[key] = nil
		end
	end
	-- Persist: remnant leftover stays unhackable across save so CHAIN does not restart.
	RfsBotHijack.setHackable( unit, false )
	abortChainGhost( unit )
end

local function finishChainAsAlly( unit )
	if not unit or not sm.exists( unit ) then
		return
	end
	pcall( function()
		sm.event.sendToUnit( unit, "sv_e_rfsLeaveRaid", {} )
	end )
	pcall( function()
		if type( RfsBotOrders ) == "table" and RfsBotOrders.ensureDefaultOrder then
			local info = RfsBotHijack.allies[unitKey( unit )]
			RfsBotOrders.ensureDefaultOrder( unit, info and info.owner or 0, info or {} )
		end
	end )
	pcall( function()
		sm.event.sendToUnit( unit, "sv_e_receiveTarget", { targetCharacter = nil, sendingUnit = unit } )
	end )
	local info = RfsBotHijack.allies[unitKey( unit )]
	if info and info.displayName then
		setUnitTag( unit, info.displayName, "name" )
	elseif not chainTagOwnedByOther( unitKey( unit ) ) then
		setUnitTag( unit, "" )
	end
end

abortChainGhost = function( unit )
	if not unit or not sm.exists( unit ) then
		return
	end
	if RfsBotHijack.isAlly( unit ) then
		finishChainAsAlly( unit )
		return
	end
	if not chainTagOwnedByOther( unitKey( unit ) ) then
		setUnitTag( unit, "" )
	end
	-- Partial convert leftover (playerAlly / raid stand-down) without ally record.
	clearIdentityOnUnit( unit )
	pcall( function()
		sm.event.sendToUnit( unit, "sv_e_receiveTarget", { targetCharacter = nil, sendingUnit = unit } )
	end )
end

-- Light chain convert: allies/infected slowly convert nearby hostiles.
-- Respects hackableRobots, underground flag, raid bans/lockouts. Skips new chains in raid.
function RfsBotHijack._tickChainConvert( live, now )
	RfsBotHijack.chain = RfsBotHijack.chain or {}
	-- One-shot after load: leftover lime CHAIN 0.0 tags from a stalled convert.
	-- Allies get their name back; ghosts get the debug tag cleared. No mass-wipe.
	if not RfsBotHijack._chainTagSweep then
		local nLive = 0
		for _ in pairs( live ) do
			nLive = nLive + 1
		end
		if nLive > 0 then
			RfsBotHijack._chainTagSweep = true
			for key, unit in pairs( live ) do
				if unit and sm.exists( unit ) then
					if RfsBotHijack.isAlly( unit ) then
						local info = RfsBotHijack.allies[key]
						if info and info.displayName then
							setUnitTag( unit, info.displayName, "name" )
						end
					elseif not chainTagOwnedByOther( key ) then
						setUnitTag( unit, "" )
					end
				end
			end
		end
	end
	if not hackableRobotsOn() then
		for key, ch in pairs( RfsBotHijack.chain ) do
			local unit = live[key]
			if unit then
				abortChainGhost( unit )
			end
		end
		RfsBotHijack.chain = {}
		return
	end
	local nextChain = {}
	local claimed = {}
	for key, info in pairs( RfsBotHijack.allies or {} ) do
		if info and info.controlled and not info.doomed then
			local src = live[key]
			if src and sm.exists( src ) and src.character and sm.exists( src.character ) then
				local pos = src.character.worldPosition
				local world = nil
				pcall( function()
					world = src.character:getWorld()
				end )
				if pos and not RfsBotHijack.areaHasRaid( pos, world ) then
					local best, bestD2 = nil, nil
					local maxD2 = CHAIN_RANGE * CHAIN_RANGE
					for hkey, u in pairs( live ) do
						if not claimed[hkey] and sm.exists( u ) and u ~= src and u.character and sm.exists( u.character ) then
							if RfsBotHijack.isRobotCharacter( u.character )
								and not RfsBotHijack.isAlly( u )
								and RfsBotHijack.isHackable( u )
								and not RfsBotHijack.isLockedOut( u )
								and not isChainSkipped( hkey )
								and not ( RfsBotHijack.pending and RfsBotHijack.pending[hkey] )
								and not ( RfsBotHijack.isUndergroundBotCharacter( u.character ) and not undergroundBotsOn() )
							then
								local d2 = ( u.character.worldPosition - pos ):length2()
								if d2 <= maxD2 and ( bestD2 == nil or d2 < bestD2 ) then
									best = u
									bestD2 = d2
								end
							end
						end
					end
					if best then
						local hkey = unitKey( best )
						claimed[hkey] = true
						local ch = RfsBotHijack.chain[hkey]
						if not ch or ch.sourceKey ~= key then
							ch = {
								startTick = now,
								need = CHAIN_NEED_TICKS,
								sourceKey = key,
								text = string.format( "CHAIN %.1f", CHAIN_NEED_TICKS / 40 ),
							}
						end
						local elapsed = now - ( ch.startTick or now )
						local remain = ch.need - elapsed
						-- Convert once. Fail / remnant leftover → skip retries (no looping CHAIN tag).
						if remain <= 2 or elapsed > ( ch.need or CHAIN_NEED_TICKS ) + 40 then
							local opts = {
								mode = ( info.mode == "infected" ) and "infected" or "tethered",
								beaconKey = ( info.mode ~= "infected" ) and info.beaconKey or nil,
								workBeaconKey = info.workBeaconKey or info.beaconKey,
								hijackTicks = info.hijackTicks,
							}
							local ok, converted = pcall( RfsBotHijack.convertUnit, best, info.owner or 0, opts )
							if ( ok and converted ) or RfsBotHijack.isAlly( best ) then
								RfsBotHijack.chainSkip = RfsBotHijack.chainSkip or {}
								RfsBotHijack.chainSkip[hkey] = true
								finishChainAsAlly( best )
							else
								skipChainUnit( best )
							end
						else
							ch.text = string.format( "CHAIN %.1f", remain / 40 )
							capturePos( ch, best )
							setUnitTag( best, ch.text, "chain" )
							nextChain[hkey] = ch
						end
					end
				end
			end
		end
	end
	for key, ch in pairs( RfsBotHijack.chain ) do
		if not nextChain[key] then
			local unit = live[key]
			if unit then
				if RfsBotHijack.isAlly( unit ) then
					finishChainAsAlly( unit )
				elseif not chainTagOwnedByOther( key ) then
					setUnitTag( unit, "" )
				end
			end
		end
	end
	RfsBotHijack.chain = nextChain
end

-- Tethered bots: same 8/5/3s as the beacon that held them, then they revert.
-- Infected (permanent) bots ignore signal loss.
function RfsBotHijack._tickSignalLoss( live, now )
	RfsBotHijack.drops = RfsBotHijack.drops or {}
	local nextDrops = {}
	local toRelease = {}
	for key, info in pairs( RfsBotHijack.allies or {} ) do
		if info and info.mode ~= "infected" and not info.doomed and not ( RfsBotHijack.jams and RfsBotHijack.jams[key] ) then
			local unit = live[key]
			if unit and sm.exists( unit ) then
				local pos = nil
				local world = nil
				pcall( function()
					pos = unit.character.worldPosition
					world = unit.character:getWorld()
				end )
				-- Raid on another tile: keep hack, cancel DROP, keep working.
				if pos and RfsBotHijack.outsideRaidTile( pos, world ) then
					info.outStreak = 0
					info.controlled = true
					if RfsBotHijack.drops then
						RfsBotHijack.drops[key] = nil
					end
				else
				-- Already-hacked bots use FULL beacon range so raid 50% cannot flicker them.
				local rec, bkey = RfsBotHijack.coveringBeacon( unit, true )
				local covered = rec ~= nil
				if covered then
					info.outStreak = 0
					info.inStreak = ( info.inStreak or 0 ) + 1
					info.controlled = true
					info.beaconKey = bkey
					if rec.hijackTicks then
						info.hijackTicks = rec.hijackTicks
					end
					local d = RfsBotHijack.drops[key]
					if d then
						-- Stay in DROP until stably back in range — no 1-tick cancel.
						if ( info.inStreak or 0 ) >= IN_STREAK_TICKS then
							setUnitTag( unit, "" )
						else
							local remain = d.need - ( now - ( d.startTick or now ) )
							if remain <= 0 then
								toRelease[#toRelease + 1] = unit
							else
								d.text = string.format( "DROP %.1f", remain / 40 )
								capturePos( d, unit )
								setUnitTag( unit, d.text, "drop" )
								nextDrops[key] = d
							end
						end
					end
				else
					info.inStreak = 0
					info.outStreak = ( info.outStreak or 0 ) + 1
					info.controlled = true
					local d = RfsBotHijack.drops[key]
					if not d then
						if ( info.outStreak or 0 ) >= OUT_STREAK_TICKS then
							local need = tonumber( info.hijackTicks ) or 320
							d = {
								startTick = now,
								need = need,
								text = string.format( "DROP %.1f", need / 40 ),
							}
							RfsBotHijack.announce( d.text .. " — out of range" )
						end
					end
					if d then
						local remain = d.need - ( now - ( d.startTick or now ) )
						if remain <= 0 then
							toRelease[#toRelease + 1] = unit
						else
							d.text = string.format( "DROP %.1f", remain / 40 )
							capturePos( d, unit )
							setUnitTag( unit, d.text, "drop" )
							nextDrops[key] = d
						end
					end
				end
				end
			end
		end
	end
	RfsBotHijack.drops = nextDrops
	for _, unit in ipairs( toRelease ) do
		local skip = false
		local inRaid = false
		pcall( function()
			local p = unit.character.worldPosition
			local w = unit.character:getWorld()
			if RfsBotHijack.outsideRaidTile( p, w ) then
				skip = true
			else
				inRaid = RfsBotHijack.areaHasRaid( p, w )
			end
		end )
		if not skip then
			RfsBotHijack.releaseHack( unit, inRaid )
		end
	end
end

local function tagPos( rec )
	if rec and rec.x and rec.y and rec.z then
		return rec.x, rec.y, rec.z
	end
	return nil, nil, nil
end

function RfsBotHijack.pendingTagList()
	local rows = {}
	for key, pend in pairs( RfsBotHijack.pending or {} ) do
		local kind = "hack"
		local t = pend.text or ""
		if string.find( t, "NO BAT", 1, true ) then
			kind = "nobat"
		end
		local x, y, z = tagPos( pend )
		rows[#rows + 1] = { key = tostring( key ), text = t, kind = kind, x = x, y = y, z = z }
	end
	for key, drop in pairs( RfsBotHijack.drops or {} ) do
		local x, y, z = tagPos( drop )
		rows[#rows + 1] = { key = tostring( key ), text = drop.text or "DROP", kind = "drop", x = x, y = y, z = z }
	end
	for key, jam in pairs( RfsBotHijack.jams or {} ) do
		local x, y, z = tagPos( jam )
		rows[#rows + 1] = { key = tostring( key ), text = jam.text or "JAM", kind = "jam", x = x, y = y, z = z }
	end
	return rows
end

function RfsBotHijack.linkedCount( beaconKey )
	if not beaconKey then
		return 0
	end
	beaconKey = tostring( beaconKey )
	local n = 0
	for _, info in pairs( RfsBotHijack.allies ) do
		if info.controlled and info.mode ~= "infected" and tostring( info.beaconKey ) == beaconKey then
			n = n + 1
		end
	end
	return n
end

-- Home beacon for jobs/orders (survives infection tether clear).
function RfsBotHijack.homeBeaconKey( info )
	if type( info ) ~= "table" then
		return nil
	end
	if info.workBeaconKey ~= nil then
		return tostring( info.workBeaconKey )
	end
	local ord = info.rfsOrder or info.order
	if type( ord ) == "table" and ord.beaconKey ~= nil then
		return tostring( ord.beaconKey )
	end
	if info.beaconKey ~= nil then
		return tostring( info.beaconKey )
	end
	return nil
end

-- Same ally set as Orders GUI / listHomeAllies (Master domain + orphan migrate + in-range).
function RfsBotHijack.homeAllyCount( beaconKey )
	if not beaconKey then
		return 0
	end
	local rows = nil
	pcall( function()
		rows = RfsBotHijack.listHomeAllies( tostring( beaconKey ), nil )
	end )
	if type( rows ) == "table" then
		return #rows
	end
	return 0
end

-- Resolve unit for Orders RPCs. Prefer UnitManager — Game.lua has no world context
-- and bare sm.unit.getAllUnits() throws there.
function RfsBotHijack.unitByKey( key, world )
	key = tostring( key or "" )
	if key == "" then
		return nil
	end
	if g_unitManager and type( g_unitManager.sv_getAllUnits ) == "function" then
		local ok, units = pcall( function()
			return g_unitManager:sv_getAllUnits()
		end )
		if ok and type( units ) == "table" then
			for _, u in pairs( units ) do
				if u and sm.exists( u ) and unitKey( u ) == key then
					return u
				end
			end
		end
	end
	if not world then
		pcall( function()
			local game = _G.g_rfsGame
			if game and game.sv and game.sv.saved then
				world = game.sv.saved.overworld
			end
		end )
	end
	for _, u in ipairs( allUnits( world ) ) do
		if sm.exists( u ) and unitKey( u ) == key then
			return u
		end
	end
	return nil
end

-- Rows for Beacon Orders GUI. ownerFilterId = nil means all (host).
-- Uses Master/Slave order domain so nearby linked beacons share the ally pool.
-- Falls back to in-range owned allies when domain homes are empty/orphaned, and
-- migrates those homes onto the domain master so Color/orders keep working.
function RfsBotHijack.listHomeAllies( beaconKey, ownerFilterId )
	beaconKey = tostring( beaconKey or "" )
	local rows = {}
	if beaconKey == "" then
		return rows
	end
	-- Adopt orphans before listing (Master / Independent open path).
	pcall( function()
		RfsBotHijack.migrateDomainAllies( beaconKey, ownerFilterId )
	end )
	local domain = RfsBotHijack.orderDomainKeys and RfsBotHijack.orderDomainKeys( beaconKey ) or { [beaconKey] = true }
	local matched = {}

	local function ownerOk( info )
		return ownerFilterId == nil or tostring( info.owner ) == tostring( ownerFilterId )
	end

	local function appendRow( key, info )
		if matched[key] then
			return
		end
		local ord = info.rfsOrder or info.order
		local orderMode = "defend"
		if type( ord ) == "table" and ord.mode then
			orderMode = tostring( ord.mode )
		end
		local seedUuid = nil
		if type( ord ) == "table" and ord.seedUuid ~= nil then
			seedUuid = tostring( ord.seedUuid )
		end
		local liveType, liveName = nil, nil
		local unit = RfsBotHijack.unitByKey( key )
		if unit and sm.exists( unit ) and unit.character and sm.exists( unit.character ) then
			liveType = charTypeStr( unit.character )
			pcall( function()
				if unit.character.getName then
					liveName = unit.character:getName()
				end
			end )
		end
		local name = tostring( info.displayName or liveName or shortTypeName( info.unitType or info.type or liveType ) or "Bot" )
		local botType = info.botType
			or RfsBotHijack.classifyBotKind( info.unitType or info.type or liveType, name )
		if ( not botType or botType == "other" ) and liveType then
			botType = RfsBotHijack.classifyBotKind( liveType, liveName or name )
		end
		info.botType = botType
		local typeLetter = info.typeLetter
			or RfsBotHijack.typeLetterFor( botType, name or liveName )
		info.typeLetter = typeLetter
		rows[#rows + 1] = {
			key = tostring( key ),
			name = name,
			displayIndex = tonumber( info.displayIndex ),
			unitType = info.unitType ~= nil and tostring( info.unitType ) or ( info.type ~= nil and tostring( info.type ) or ( liveType and tostring( liveType ) or nil ) ),
			type = info.type ~= nil and tostring( info.type ) or nil,
			botType = botType,
			typeLetter = typeLetter,
			kind = botType,
			mode = orderMode,
			seedUuid = seedUuid,
			owner = info.owner,
			allyMode = info.mode ~= nil and tostring( info.mode ) or nil,
			allyColor = info.allyColor ~= nil and tostring( info.allyColor ) or nil,
		}
		matched[key] = true
	end

	for key, info in pairs( RfsBotHijack.allies ) do
		if info and info.controlled and ownerOk( info ) then
			local home = RfsBotHijack.homeBeaconKey( info )
			local match = home ~= nil and domain[home] == true
			if not match and home == nil and info.beaconKey and domain[tostring( info.beaconKey )] then
				match = true
			end
			if match then
				appendRow( key, info )
			end
		end
	end

	-- Fallback: still empty → any owned ally inside a domain beacon's range
	-- (covers /hijack orphans and pre-Master Independent homes that missed migrate).
	if #rows == 0 then
		for key, info in pairs( RfsBotHijack.allies ) do
			if info and info.controlled and ownerOk( info ) and not matched[key] then
				local unit = RfsBotHijack.unitByKey( key )
				local inRange = false
				if unit and sm.exists( unit ) and unit.character and sm.exists( unit.character ) then
					for dk, _ in pairs( domain ) do
						local drec = RfsBotHijack.beacons[dk]
						if drec and beaconLive( drec ) and drec.pos then
							local okWorld = true
							if drec.world then
								pcall( function()
									okWorld = ( unit.character:getWorld() == drec.world )
								end )
							end
							if okWorld then
								local r = tonumber( drec.range ) or DEFAULT_RANGE
								local d2 = ( unit.character.worldPosition - drec.pos ):length2()
								if d2 <= r * r then
									inRange = true
									break
								end
							end
						end
					end
				end
				if inRange then
					local masterKey = RfsBotHijack.orderDomainMasterKey( beaconKey ) or beaconKey
					info.workBeaconKey = tostring( masterKey )
					appendRow( key, info )
				end
			end
		end
	end

	-- Last resort intentionally omitted: listing every ally on every beacon would
	-- mix unrelated bases. In-range fallback above covers orphan homes.

	table.sort( rows, function( a, b )
		return tostring( a.name ) < tostring( b.name )
	end )
	return rows
end

-- Persist saved.rfsOrder = { mode, beaconKey, owner }. Host or owner.
function RfsBotHijack.setOrder( unitOrKey, order, player, allowHost )
	local unit = unitOrKey
	local key = nil
	if type( unitOrKey ) == "string" or type( unitOrKey ) == "number" then
		key = tostring( unitOrKey )
		unit = RfsBotHijack.unitByKey( key )
	else
		key = unitKey( unit )
	end
	if not key or not unit or not sm.exists( unit ) then
		return false, "bot gone"
	end
	local info = RfsBotHijack.allies[key]
	if not info or not info.controlled then
		return false, "not an ally"
	end
	local playerId = nil
	pcall( function()
		playerId = player and player.id
	end )
	local isOwner = playerId ~= nil and info.owner ~= nil and tostring( info.owner ) == tostring( playerId )
	if not isOwner and not allowHost then
		return false, "not owner"
	end
	order = order or {}
	-- Pass mode through; RfsBotOrders.setOrder validates type matrix (Collect=tote M3, Farm=hay M2, Oil=water M4).
	local mode = string.lower( tostring( order.mode or "rest" ) )
	local home = RfsBotHijack.homeBeaconKey( info ) or order.beaconKey
	local saved = {
		mode = mode,
		seedUuid = order.seedUuid,
		beaconKey = home and tostring( home ) or nil,
		owner = info.owner,
	}
	if type( RfsBotOrders ) == "table" and type( RfsBotOrders.setOrder ) == "function" then
		return RfsBotOrders.setOrder( unit, saved )
	end
	-- Fallback without RfsBotOrders: allow Rest/Defend/Collect/Farm/Oil strings.
	if mode ~= "defend" and mode ~= "rest" and mode ~= "collect" and mode ~= "farm" and mode ~= "oil" then
		mode = "rest"
	end
	saved.mode = mode
	info.rfsOrder = saved
	info.order = saved
	if home then
		info.workBeaconKey = info.workBeaconKey or tostring( home )
	end
	pcall( function()
		sm.event.sendToUnit( unit, "sv_e_rfsOrder", saved )
	end )
	return true, saved
end

-- Persist full-body ally tint (character:setColor). Host or owner.
-- unitKey nil → all listed home allies in the beacon order domain (owner-filtered for non-host).
function RfsBotHijack.setAllyColor( unitOrKey, colorHex, player, allowHost )
	local hex = normalizeColorHex( colorHex )
	if not hex then
		return false, "bad color"
	end
	local unit = unitOrKey
	local key = nil
	if type( unitOrKey ) == "string" or type( unitOrKey ) == "number" then
		key = tostring( unitOrKey )
		unit = RfsBotHijack.unitByKey( key )
	else
		key = unitKey( unit )
	end
	if not key then
		return false, "no bot"
	end
	local info = RfsBotHijack.allies[key]
	if not info or not info.controlled then
		return false, "not an ally"
	end
	local playerId = nil
	pcall( function()
		playerId = player and player.id
	end )
	local isOwner = playerId ~= nil and info.owner ~= nil and tostring( info.owner ) == tostring( playerId )
	if not isOwner and not allowHost then
		return false, "not owner"
	end
	info.allyColor = hex
	if unit and sm.exists( unit ) and unit.character and sm.exists( unit.character ) then
		applyAllyVisualColor( unit.character, info )
	end
	pushIdentityToUnit( unit, {
		owner = info.owner,
		displayName = info.displayName,
		unitType = info.unitType or info.type,
		firstSeenTick = info.firstSeenTick,
		mode = info.mode,
		beaconKey = info.beaconKey,
		workBeaconKey = info.workBeaconKey,
		allyColor = hex,
		playerAlly = true,
	} )
	return true, hex
end

function RfsBotHijack.setAllyColorDomain( beaconKey, colorHex, player, allowHost, unitKeyOnly )
	local hex = normalizeColorHex( colorHex )
	if not hex then
		return false, "bad color", 0
	end
	beaconKey = tostring( beaconKey or "" )
	if beaconKey == "" then
		return false, "no beacon", 0
	end
	-- Remember as domain default so newly hijacked bots inherit it.
	RfsBotHijack.setDomainAllyColor( beaconKey, hex )
	if unitKeyOnly and tostring( unitKeyOnly ) ~= "" then
		local ok, result = RfsBotHijack.setAllyColor( tostring( unitKeyOnly ), hex, player, allowHost )
		return ok, result, ok and 1 or 0
	end
	local ownerFilter = nil
	if not allowHost then
		pcall( function()
			ownerFilter = player and player.id
		end )
	end
	local rows = RfsBotHijack.listHomeAllies( beaconKey, ownerFilter ) or {}
	local n = 0
	local lastErr = nil
	for _, row in ipairs( rows ) do
		if row and row.key then
			local ok, err = RfsBotHijack.setAllyColor( tostring( row.key ), hex, player, allowHost )
			if ok then
				n = n + 1
			else
				lastErr = err
			end
		end
	end
	-- Domain color is set even if the list is empty (next hijack still inherits).
	if n == 0 and not unitKeyOnly then
		return true, hex, 0
	end
	if n == 0 then
		return false, lastErr or "no bots", 0
	end
	return true, hex, n
end

RfsBotHijack.allyVisualColor = allyVisualColor
RfsBotHijack.normalizeColorHex = normalizeColorHex
RfsBotHijack.shortTypeName = shortTypeName
RfsBotHijack.parseTypeNumberName = parseTypeNumberName

-- Hostiles currently mid auto-hijack under this beacon (for battery work-drain).
function RfsBotHijack.pendingCount( beaconKey )
	if not beaconKey then
		return 0
	end
	beaconKey = tostring( beaconKey )
	local n = 0
	for _, pend in pairs( RfsBotHijack.pending or {} ) do
		if pend and tostring( pend.beaconKey ) == beaconKey then
			n = n + 1
		end
	end
	return n
end

---------------------------------------------------------------------------
-- Vanilla wraps (unit_util.lua globals)
---------------------------------------------------------------------------

function RfsBotHijack.ensureHooks()
	-- Character text hooks must run on the CLIENT too. Unit globals
	-- (RobotSelectTarget) only exist on the server — don't skip char hooks.
	RfsBotHijack.ensureCharHooks()
	if type( RobotSelectTarget ) ~= "function" or type( InitRobotParams ) ~= "function" then
		return false
	end
	if RfsBotHijack._hooked
		and RobotSelectTarget == RfsBotHijack._wrappedSelect
		and InitRobotParams == RfsBotHijack._wrappedInit then
		-- Unit classes load when the first bot spawns — keep retrying damage wraps.
		RfsBotHijack.ensureDamageHooks()
		RfsBotHijack.ensureUnitHooks()
		RfsBotHijack.ensureCharHooks()
		return true
	end

	if not RfsBotHijack._origSelect then
		RfsBotHijack._origSelect = RobotSelectTarget
	end
	if not RfsBotHijack._origInit then
		RfsBotHijack._origInit = InitRobotParams
	end
	if not RfsBotHijack._origFindAllies then
		RfsBotHijack._origFindAllies = FindAllies
	end
	if not RfsBotHijack._origShare then
		RfsBotHijack._origShare = ShareTarget
	end

	function RfsBotHijack._wrappedInit( self )
		RfsBotHijack._origInit( self )
		self.saved = self.saved or {}
		if self.saved.rfsHackable == nil then
			self.saved.rfsHackable = true
		end
		if self.saved.rfsHackable == false then
			applyUnhackableToSelf( self )
			if self.unit then
				RfsBotHijack.unregister( self.unit )
			end
			return
		end
		if self.params and self.params.playerAlly then
			self.saved.playerAlly = true
			self.saved.friendly = false
			self.saved.playerAllyMode = self.params.playerAllyMode or "infected"
			if self.params.playerAllyOwner ~= nil then
				self.saved.playerAllyOwner = self.params.playerAllyOwner
			end
			if self.params.rfsDisplayName then
				self.saved.rfsDisplayName = self.params.rfsDisplayName
			end
			if self.params.rfsUnitType then
				self.saved.rfsUnitType = self.params.rfsUnitType
			end
			if self.params.rfsBotType then
				self.saved.rfsBotType = self.params.rfsBotType
			end
			if self.params.rfsTypeLetter then
				self.saved.rfsTypeLetter = self.params.rfsTypeLetter
			end
			if self.params.rfsFirstSeenTick then
				self.saved.rfsFirstSeenTick = self.params.rfsFirstSeenTick
			end
		end
		if self.saved and self.saved.playerAlly and self.unit then
			local mode = self.saved.playerAllyMode or "infected"
			RfsBotHijack.register( self.unit, self.saved.playerAllyOwner, {
				mode = mode,
				beaconKey = self.saved.playerAllyBeacon,
				workBeaconKey = self.saved.playerAllyWorkBeacon or self.saved.playerAllyBeacon,
				rfsOrder = self.saved.rfsOrder,
				displayName = self.saved.rfsDisplayName,
				displayIndex = self.saved.rfsDisplayIndex,
				unitType = self.saved.rfsUnitType,
				botType = self.saved.rfsBotType,
				typeLetter = self.saved.rfsTypeLetter,
				firstSeenTick = self.saved.rfsFirstSeenTick,
				allyColor = self.saved.rfsAllyColor,
			} )
			self.saved.friendly = false
			pcall( function()
				applyAllyVisualColor( self.unit.character, RfsBotHijack.allies[unitKey( self.unit )] )
			end )
			pcall( function()
				if type( RfsBotOrders ) == "table" and RfsBotOrders.ensureDefaultOrder then
					RfsBotOrders.ensureDefaultOrder( self.unit, self.saved.playerAllyOwner, {
						beaconKey = self.saved.playerAllyBeacon,
						workBeaconKey = self.saved.playerAllyWorkBeacon or self.saved.playerAllyBeacon,
					} )
				end
			end )
		end
	end

	function RfsBotHijack._wrappedFindAllies( self, outUnits, allyRange )
		RfsBotHijack._origFindAllies( self, outUnits, allyRange )
		if type( outUnits ) ~= "table" then
			return
		end
		local selfAlly = self.unit and RfsBotHijack.isAlly( self.unit ) or false
		local filtered = {}
		for _, allyUnit in ipairs( outUnits ) do
			local otherAlly = RfsBotHijack.isAlly( allyUnit )
			if selfAlly == otherAlly then
				filtered[#filtered + 1] = allyUnit
			end
		end
		for i = #outUnits, 1, -1 do
			outUnits[i] = nil
		end
		for i, u in ipairs( filtered ) do
			outUnits[i] = u
		end
	end

	function RfsBotHijack._wrappedSelect( self, allyRange, dt )
		self.saved = self.saved or {}
		if self.saved.rfsHackable == false then
			applyUnhackableToSelf( self )
			if self.unit and RfsBotHijack.isAlly( self.unit ) then
				RfsBotHijack.unregister( self.unit )
			end
			RfsBotHijack._origSelect( self, allyRange, dt )
			if self.unit and not ( self.saved and self.saved.friendly ) then
				local allyChar = closestOtherRobotCharacter( self.unit, true, HOSTILE_VS_ALLY_RANGE )
				if allyChar and sm.exists( allyChar ) then
					self.target = allyChar
					self.lastTargetPosition = allyChar.worldPosition
				end
			end
			return
		end
		local isAlly = self.unit and RfsBotHijack.isAlly( self.unit )
		if not isAlly and self.saved and self.saved.playerAlly and self.unit then
			-- Saved convert, but beacon dropped them — clear persist and go hostile.
			-- Never restore ally if this bot already lost hack.
			if self.saved.rfsHackable == false or not RfsBotHijack.isHackable( self.unit ) then
				applyUnhackableToSelf( self )
			else
				local info = RfsBotHijack.allies[unitKey( self.unit )]
				if info and info.mode == "infected" then
					RfsBotHijack.register( self.unit, self.saved.playerAllyOwner, {
						mode = "infected",
						beaconKey = self.saved.playerAllyBeacon,
					} )
					isAlly = true
				else
					-- Leftover convert / chain / raid-list cleanup: not an ally anymore.
					self.saved.playerAlly = nil
					self.saved.playerAllyMode = nil
					self.saved.playerAllyBeacon = nil
					self.saved.playerAllyWorkBeacon = nil
					self.saved.friendly = false
					self.isDirty = true
					clearIdentityOnUnit( self.unit )
					pcall( function()
						sm.event.sendToUnit( self.unit, "sv_e_receiveTarget", { targetCharacter = nil, sendingUnit = self.unit } )
					end )
					if not chainTagOwnedByOther( unitKey( self.unit ) ) then
						setUnitTag( self.unit, "" )
					end
				end
			end
		end

		if self.saved and self.saved.raider and self.unit and self.unit.character then
			pcall( function()
				RfsBotHijack.noteRaid( self.unit.character.worldPosition, self.unit.character:getWorld() )
			end )
		end

		if isAlly then
			if self.saved.rfsHackable == false or ( self.unit and not RfsBotHijack.isHackable( self.unit ) ) then
				applyUnhackableToSelf( self )
				if self.unit then
					RfsBotHijack.unregister( self.unit )
				end
				RfsBotHijack._origSelect( self, allyRange, dt )
				return
			end
			self.saved = self.saved or {}
			local info = self.unit and RfsBotHijack.allies[unitKey( self.unit )]
			self.saved.playerAlly = true
			self.saved.friendly = false
			self.saved.playerAllyMode = info and info.mode or "tethered"
			self.saved.playerAllyBeacon = info and info.beaconKey
			self.saved.playerAllyWorkBeacon = info and info.workBeaconKey
			self.saved.playerAllyOwner = info and info.owner
			self.saved.rfsDisplayName = info and info.displayName
			self.saved.rfsDisplayIndex = info and info.displayIndex
			self.saved.rfsUnitType = info and ( info.unitType or info.type )
			self.saved.rfsBotType = info and info.botType
			self.saved.rfsTypeLetter = info and info.typeLetter
			self.saved.rfsFirstSeenTick = info and info.firstSeenTick
			self.saved.rfsAllyColor = info and info.allyColor
			if info and type( info.order ) == "table" then
				self.saved.rfsOrder = info.order
			elseif info and type( info.rfsOrder ) == "table" then
				self.saved.rfsOrder = info.rfsOrder
			end
			self.isDirty = true
			-- Stalled CHAIN 0.0 leftover: drop chain row and restore name + Defend AI.
			local uk = self.unit and unitKey( self.unit )
			if uk and RfsBotHijack.chain and RfsBotHijack.chain[uk] then
				RfsBotHijack.chain[uk] = nil
				finishChainAsAlly( self.unit )
			end
			RfsBotHijack.standDown( self )
			if self.unit and self.unit.character then
				applyAllyVisualColor( self.unit.character, info )
			end
			self.eventTarget = nil
			-- Rest/Defend job clamp (RfsBotOrders). Fallback = legacy full aggro.
			local handled = false
			if type( RfsBotOrders ) == "table" and type( RfsBotOrders.applySelect ) == "function" then
				local okApply, did = pcall( RfsBotOrders.applySelect, self )
				handled = okApply and did and true or false
			end
			if not handled then
				local hostile = closestOtherRobotCharacter( self.unit, false, ALLY_AGGRO_RANGE )
				if hostile and sm.exists( hostile ) then
					self.target = hostile
					self.lastTargetPosition = hostile.worldPosition
				else
					self.target = nil
					self.lastTargetPosition = nil
				end
			end
			return
		end

		RfsBotHijack._origSelect( self, allyRange, dt )
		pcall( function()
			RfsBotHijack.clearOffTileRaidAi( self )
		end )

		if self.unit and not ( self.saved and self.saved.friendly ) then
			local allyChar = closestOtherRobotCharacter( self.unit, true, HOSTILE_VS_ALLY_RANGE )
			if allyChar and sm.exists( allyChar ) then
				local preferAlly = true
				if self.target and sm.exists( self.target ) then
					local okP, isP = pcall( function()
						return self.target:isPlayer()
					end )
					if not ( okP and isP ) then
						local dAlly = ( allyChar.worldPosition - self.unit.character.worldPosition ):length2()
						local dCur = ( self.target.worldPosition - self.unit.character.worldPosition ):length2()
						preferAlly = dAlly <= dCur
					end
				end
				if preferAlly then
					self.target = allyChar
					self.lastTargetPosition = allyChar.worldPosition
				end
			end
		end
	end

	RobotSelectTarget = RfsBotHijack._wrappedSelect
	InitRobotParams = RfsBotHijack._wrappedInit
	if type( FindAllies ) == "function" then
		FindAllies = RfsBotHijack._wrappedFindAllies
	end
	RfsBotHijack.ensureDamageHooks()
	RfsBotHijack.ensureUnitHooks()
	RfsBotHijack.ensureCharHooks()
	RfsBotHijack._hooked = true
	print( "[RFS] Bot hijack hooks installed (HACK 3.5k)" )
	return true
end

-- Survival's server_onMelee / onProjectile / onCollision ignore Unit attackers
-- (`if not SurvivalGame then teamOpponent = ...`). Allies vs hostiles must still hit.
local _rfsDmgWrapped = _rfsDmgWrapped or {}

local function unitFromAttacker( attacker )
	if not attacker then
		return nil
	end
	local okEx, exists = pcall( sm.exists, attacker )
	if okEx and exists == false then
		return nil
	end
	local t = type( attacker )
	if t == "Unit" then
		return attacker
	end
	if t == "Character" then
		local ok, u = pcall( function()
			return attacker:getUnit()
		end )
		if ok and u then
			return u
		end
	end
	return nil
end

local function opposingFactions( unitA, unitB )
	if not unitA or not unitB then
		return false
	end
	return RfsBotHijack.isAlly( unitA ) ~= RfsBotHijack.isAlly( unitB )
end

local function applyFactionDamage( self, damage, impact, hitPos )
	if type( self.sv_takeDamage ) ~= "function" then
		return
	end
	damage = tonumber( damage ) or 10
	if damage <= 0 then
		damage = 10
	end
	impact = impact or sm.vec3.new( 0, 0, 1 )
	hitPos = hitPos or ( self.unit and self.unit.character and self.unit.character.worldPosition )
	pcall( function()
		if self.sv_addStagger then
			self:sv_addStagger( 0.35 )
		end
	end )
	pcall( function()
		self:sv_takeDamage( damage, impact, hitPos )
	end )
end

function RfsBotHijack.ensureUnitHooks()
	local classNames = {
		"TotebotGreenUnit", "TotebotBlueUnit", "TotebotRedUnit", "TotebotLeafUnit",
		"TotebotYellowUnit", "HaybotUnit", "FarmbotUnit", "TapebotUnit",
		"MinerbotUnit", "CablebotUnit", "LootbotUnit", "SeedbotUnit",
		"BaseTotebotUnit", "TrashbotUnit",
	}
	for _, className in ipairs( classNames ) do
		local cls = _G[className]
		if type( cls ) == "table" then
			if not cls._rfsHackableRpc then
				function cls.sv_e_rfsSetHackable( self, params )
					self.saved = self.saved or {}
					if params and params.hackable == false then
						applyUnhackableToSelf( self )
					elseif self.saved.rfsHackable ~= false then
						self.saved.rfsHackable = true
						if self.unit then
							publishHackable( self.unit, true )
						end
					end
				end
				function cls.sv_e_rfsIdentity( self, params )
					self.saved = self.saved or {}
					if params and params.clear then
						self.saved.playerAlly = nil
						self.saved.playerAllyMode = nil
						self.saved.playerAllyBeacon = nil
						self.saved.playerAllyWorkBeacon = nil
						self.saved.playerAllyOwner = nil
						self.saved.rfsDisplayName = nil
						self.saved.rfsDisplayIndex = nil
						self.saved.rfsUnitType = nil
						self.saved.rfsBotType = nil
						self.saved.rfsTypeLetter = nil
						self.saved.rfsFirstSeenTick = nil
						self.saved.rfsAllyColor = nil
						self.saved.rfsOrder = nil
						self.saved.friendly = false
						self.isDirty = true
						return
					end
					if type( params ) ~= "table" then
						return
					end
					if params.playerAlly then
						self.saved.playerAlly = true
						self.saved.friendly = false
					end
					if params.mode then
						self.saved.playerAllyMode = params.mode
					end
					if params.beaconKey ~= nil then
						self.saved.playerAllyBeacon = params.beaconKey
					end
					if params.workBeaconKey ~= nil then
						self.saved.playerAllyWorkBeacon = params.workBeaconKey
					end
					if params.owner ~= nil then
						self.saved.playerAllyOwner = params.owner
					end
					if params.displayName then
						self.saved.rfsDisplayName = params.displayName
					end
					if params.displayIndex ~= nil then
						self.saved.rfsDisplayIndex = tonumber( params.displayIndex )
					end
					if params.unitType then
						self.saved.rfsUnitType = params.unitType
					end
					if params.botType then
						self.saved.rfsBotType = params.botType
					end
					if params.typeLetter then
						self.saved.rfsTypeLetter = params.typeLetter
					end
					if params.firstSeenTick then
						self.saved.rfsFirstSeenTick = params.firstSeenTick
					end
					if params.allyColor ~= nil then
						local hex = normalizeColorHex( params.allyColor )
						self.saved.rfsAllyColor = hex
					end
					if type( params.rfsOrder ) == "table" then
						self.saved.rfsOrder = params.rfsOrder
					end
					self.isDirty = true
				end
				function cls.sv_e_rfsLeaveRaid( self, params )
					RfsBotHijack.standDown( self )
				end
				cls._rfsHackableRpc = true
			elseif not cls.sv_e_rfsLeaveRaid then
				function cls.sv_e_rfsLeaveRaid( self, params )
					RfsBotHijack.standDown( self )
				end
			end
			if not cls._rfsOrderRpc then
				function cls.sv_e_rfsOrder( self, params )
					self.saved = self.saved or {}
					if type( params ) ~= "table" then
						return
					end
					if params.clear then
						self.saved.rfsOrder = nil
						self.isDirty = true
						return
					end
					self.saved.rfsOrder = {
						mode = params.mode,
						seedUuid = params.seedUuid,
						beaconKey = params.beaconKey,
						owner = params.owner,
					}
					if params.beaconKey ~= nil and self.saved.playerAllyWorkBeacon == nil then
						self.saved.playerAllyWorkBeacon = params.beaconKey
					end
					self.isDirty = true
					-- Mirror into ally table (setOrder also sends this event).
					if self.unit then
						local key = nil
						pcall( function()
							key = tostring( self.unit.id )
						end )
						if key and RfsBotHijack.allies and RfsBotHijack.allies[key] then
							RfsBotHijack.allies[key].rfsOrder = self.saved.rfsOrder
							RfsBotHijack.allies[key].order = self.saved.rfsOrder
							if params.beaconKey and not RfsBotHijack.allies[key].workBeaconKey then
								RfsBotHijack.allies[key].workBeaconKey = tostring( params.beaconKey )
							end
						end
					end
				end
				cls._rfsOrderRpc = true
			end
			if type( cls.server_onUnitUpdate ) == "function" and not cls._rfsUnitHooked then
				local orig = cls.server_onUnitUpdate
				cls.server_onUnitUpdate = function( self, dt )
					self.saved = self.saved or {}
					if self.saved.rfsHackable == nil then
						self.saved.rfsHackable = true
					end
					if self.saved.rfsHackable == false then
						applyUnhackableToSelf( self )
						if self.unit and RfsBotHijack.isAlly( self.unit ) then
							RfsBotHijack.unregister( self.unit )
						end
					end
					if self.saved and self.saved.raider then
						pcall( function()
							RfsBotHijack.noteRaid( self.unit.character.worldPosition, self.unit.character:getWorld() )
						end )
					end
					local result = orig( self, dt )
					if self.unit and RfsBotHijack.isAlly( self.unit ) then
						if self.saved.rfsHackable == false then
							RfsBotHijack.unregister( self.unit )
						else
							RfsBotHijack.standDown( self )
						end
					else
						pcall( function()
							RfsBotHijack.clearOffTileRaidAi( self )
						end )
					end
					return result
				end
				cls._rfsUnitHooked = true
			end
		end
	end
end

function RfsBotHijack.ensureDamageHooks()
	local classNames = {
		"TotebotGreenUnit", "TotebotBlueUnit", "TotebotRedUnit", "TotebotLeafUnit",
		"TotebotYellowUnit", "HaybotUnit", "FarmbotUnit", "TapebotUnit",
		"MinerbotUnit", "CablebotUnit", "LootbotUnit", "SeedbotUnit",
		"BaseTotebotUnit", "TrashbotUnit",
	}

	local function wrapFn( cls, name, make )
		local orig = cls[name]
		if type( orig ) ~= "function" then
			return
		end
		if _rfsDmgWrapped[orig] then
			cls[name] = _rfsDmgWrapped[orig]
			return
		end
		local wrapped = make( orig )
		_rfsDmgWrapped[orig] = wrapped
		_rfsDmgWrapped[wrapped] = wrapped
		cls[name] = wrapped
	end

	for _, className in ipairs( classNames ) do
		local cls = _G[className]
		if type( cls ) == "table" then
			wrapFn( cls, "server_onMelee", function( orig )
				return function( self, hitPos, attacker, damage, power, hitDirection )
					local atk = unitFromAttacker( attacker )
					if atk and self.unit and opposingFactions( self.unit, atk ) then
						local impact = hitDirection
						if impact then
							impact = impact * 6
						end
						applyFactionDamage( self, damage, impact, hitPos )
						return
					end
					return orig( self, hitPos, attacker, damage, power, hitDirection )
				end
			end )

			wrapFn( cls, "server_onProjectile", function( orig )
				return function( self, hitPos, hitTime, hitVelocity, extra, attacker, damage, userData, hitNormal, projectileUuid )
					local atk = unitFromAttacker( attacker )
					if atk and self.unit and opposingFactions( self.unit, atk ) then
						local impact = nil
						if hitVelocity then
							pcall( function()
								impact = hitVelocity:normalize() * 6
							end )
						end
						applyFactionDamage( self, damage, impact, hitPos )
						return
					end
					return orig( self, hitPos, hitTime, hitVelocity, extra, attacker, damage, userData, hitNormal, projectileUuid )
				end
			end )

			-- Collision is every physics tick — don't turn body-checks into instakill.
			-- Melee + tape shots are the real faction hits.
		end
	end
end
