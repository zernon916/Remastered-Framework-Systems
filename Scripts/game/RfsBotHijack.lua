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
local UUID_MINERBOT = sm.uuid.new( "92da8324-3cfe-4529-ac1c-c71facda50a3" )
local UUID_CABLEBOT = sm.uuid.new( "b837888a-0480-4a34-bc34-d72261a14385" )
-- Phase 2 lite: infected/ally slowly convert nearby hostiles (not farm orders).
local CHAIN_RANGE = 10
local CHAIN_NEED_TICKS = 40 * 15 -- ~15 s
local IDENTITY_TAG_EVERY = 80 -- 2 s nametag refresh when idle

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

local function shortTypeName( typeStr )
	typeStr = tostring( typeStr or "robot" )
	-- Prefer readable tail of UUID-looking strings; Survival often uses unit_* globals.
	if unit_farmbot and tostring( typeStr ) == tostring( unit_farmbot ) then
		return "Farmbot"
	end
	if unit_haybot and tostring( typeStr ) == tostring( unit_haybot ) then
		return "Haybot"
	end
	if unit_tapebot and tostring( typeStr ) == tostring( unit_tapebot ) then
		return "Tapebot"
	end
	if unit_minerbot and tostring( typeStr ) == tostring( unit_minerbot ) then
		return "Minerbot"
	end
	if unit_cablebot and tostring( typeStr ) == tostring( unit_cablebot ) then
		return "Cablebot"
	end
	-- Totebot Blue = Waterbot (Collect Oil M4). Check before generic tote.
	local blue = unit_totebot_blue or sm.uuid.new( "58992f50-ca36-44e1-8c47-4996d89d6a9a" )
	if blue and ( typeStr == tostring( blue ) or string.lower( typeStr ) == string.lower( tostring( blue ) ) ) then
		return "Waterbot"
	end
	if unit_waterbot and tostring( typeStr ) == tostring( unit_waterbot ) then
		return "Waterbot"
	end
	if string.find( typeStr, "waterbot", 1, true ) or string.find( typeStr, "Waterbot", 1, true ) then
		return "Waterbot"
	end
	if string.find( typeStr, "tote", 1, true ) or string.find( typeStr, "Tote", 1, true ) then
		return "Totebot"
	end
	if #typeStr > 8 then
		return "Bot-" .. string.sub( typeStr, -4 )
	end
	return typeStr
end

local function makeDisplayName( unit, typeStr, mode )
	local prefix = ( mode == "infected" ) and "Inf" or "Ally"
	local base = shortTypeName( typeStr )
	local idTail = ""
	pcall( function()
		if unit and unit.id ~= nil then
			idTail = "-" .. tostring( unit.id % 1000 )
		end
	end )
	return prefix .. " " .. base .. idTail
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
	self.saved.rfsFirstSeenTick = nil
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

-- True while the on-screen farm raid is incoming or dropping on this area.
function RfsBotHijack.areaHasRaid( pos, world )
	if not pos then
		return false
	end
	local wid = worldIdOf( world )
	if wid and type( RaidManager ) == "table" and type( RaidManager.Sv_AreaHasActiveRaid ) == "function" then
		local ok, active = pcall( RaidManager.Sv_AreaHasActiveRaid, pos, wid )
		if ok and active then
			return true
		end
	end
	if wid and g_raidManager and type( g_raidManager.sv_getRaidAtPosition ) == "function" then
		local ok, raid = pcall( function()
			return g_raidManager:sv_getRaidAtPosition( wid, pos )
		end )
		if ok and type( raid ) == "table" then
			if raid.timeoutTick then
				return true
			end
			local ad = raid.attackData
			if type( ad ) == "table" then
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
			end
		end
	end
	-- Fallback: a raider unit was seen nearby this second (walls getting hit).
	local note = RfsBotHijack._raidNote
	if note and note.pos and pos then
		local now = 0
		pcall( function()
			now = sm.game.getCurrentTick()
		end )
		if note.tick and ( now - note.tick ) <= 80 then
			local same = true
			local nwid = note.wid
			if nwid and wid and nwid ~= wid then
				same = false
			end
			if same then
				local d2 = 0
				pcall( function()
					d2 = ( pos - note.pos ):length2()
				end )
				if d2 <= 96 * 96 then
					return true
				end
			end
		end
	end
	return false
end

function RfsBotHijack.noteRaid( pos, world )
	if not pos then
		return
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
	RfsBotHijack.beacons[key] = rec
end

function RfsBotHijack.unregisterBeacon( key )
	if key then
		RfsBotHijack.beacons[tostring( key )] = nil
	end
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
	local displayName = opts.displayName or ( prev and prev.displayName ) or makeDisplayName( unit, t, mode )
	local unitType = opts.unitType or ( prev and prev.unitType ) or t
	local beaconKey = opts.beaconKey or ( prev and prev.beaconKey )
	-- Sticky home for Rest/Defend/Farm jobs (survives infect / tether hops).
	local workBeaconKey = opts.workBeaconKey or ( prev and prev.workBeaconKey ) or beaconKey
	if workBeaconKey then
		workBeaconKey = tostring( workBeaconKey )
	end
	local order = opts.order or opts.rfsOrder or ( prev and ( prev.order or prev.rfsOrder ) )
	RfsBotHijack.allies[key] = {
		type = t,
		unitType = unitType,
		owner = ownerId or ( prev and prev.owner ),
		mode = mode,
		beaconKey = beaconKey,
		workBeaconKey = workBeaconKey,
		order = order,
		rfsOrder = order, -- alias for RfsBotOrders / saved.rfsOrder naming
		origColor = orig,
		infectAcc = ( prev and prev.infectAcc ) or 0,
		hijackTicks = tonumber( opts.hijackTicks ) or ( prev and prev.hijackTicks ) or 320,
		controlled = true,
		displayName = displayName,
		firstSeenTick = firstSeen,
		lastTagTick = prev and prev.lastTagTick or 0,
	}
	if char and sm.exists( char ) then
		applyColor( char, mode == "infected" and INFECT_COLOR or ALLY_COLOR )
	end
	pushIdentityToUnit( unit, {
		owner = RfsBotHijack.allies[key].owner,
		displayName = displayName,
		unitType = unitType,
		firstSeenTick = firstSeen,
		mode = mode,
		beaconKey = RfsBotHijack.allies[key].beaconKey,
		workBeaconKey = RfsBotHijack.allies[key].workBeaconKey,
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
					applyColor( unit.character, INFECT_COLOR )
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
							info.displayName = makeDisplayName( unit, info.unitType or info.type, "infected" )
							local ord = info.rfsOrder or info.order
							if type( ord ) == "table" then
								ord.beaconKey = info.workBeaconKey
								info.rfsOrder = ord
								info.order = ord
							end
							pushIdentityToUnit( unit, {
								owner = info.owner,
								displayName = info.displayName,
								unitType = info.unitType or info.type,
								firstSeenTick = info.firstSeenTick,
								mode = "infected",
								workBeaconKey = info.workBeaconKey,
								playerAlly = true,
							} )
							if unit.character and sm.exists( unit.character ) then
								applyColor( unit.character, INFECT_COLOR )
							end
						end
					else
						info.infectAcc = 0
						if unit.character and sm.exists( unit.character ) then
							applyColor( unit.character, ALLY_COLOR )
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
	if not opts.displayName then
		opts.displayName = makeDisplayName( unit, opts.unitType, opts.mode or "tethered" )
	end
	RfsBotHijack.register( unit, ownerId, opts )
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
	self.cl.rfsLastTag = { text = text, kind = data and data.kind }
	if text == "" then
		RfsBotHijack.cl_destroyCharTag( self )
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
		local names = { "RfsHackText", "RfsGrowText", "DebugText" }
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
	local kind = ( data and data.kind ) or kindFromText( text )
	if fx then
		pcall( function()
			fx:setParameter( "TextContent", text )
			fx:setParameter( "Color", colors[kind] or colors.hack )
			if not fx:isPlaying() then
				fx:start()
			end
		end )
	end
	pcall( function()
		sm.gui.setCharacterDebugText( self.character, text )
	end )
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
		if cls._rfsTagRpc then
			return
		end
		local origU = cls.client_onUpdate
		cls.client_onUpdate = function( self, dt )
			if origU then
				origU( self, dt )
			end
			local tag = self.cl and self.cl.rfsLastTag
			if tag and tag.text and tag.text ~= "" then
				RfsBotHijack.cl_applyCharTag( self, tag )
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

-- Abort raid wall-smash. Raiders keep punching creations until raider/raidPosition is cleared.
function RfsBotHijack.standDown( self )
	if not self then
		return
	end
	self.saved = self.saved or {}
	local dirty = false
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
	if self.saved.raidKey ~= nil then
		self.saved.raidKey = nil
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
function RfsBotHijack.releaseHack( unit, duringRaid )
	if not unit or not sm.exists( unit ) then
		return
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
	if RfsBotHijack.jams[key] or info.doomed then
		RfsBotHijack.jams[key] = nil
		info.doomed = nil
		RfsBotHijack.releaseHack( unit, true )
		return
	end
	local pos = nil
	local world = nil
	pcall( function()
		pos = unit.character.worldPosition
		world = unit.character:getWorld()
	end )
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
						RfsBotHijack.convertUnit( unit, rec.ownerId or 0, {
							mode = mode,
							beaconKey = bkey,
							workBeaconKey = bkey,
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

-- Light chain convert: allies/infected slowly convert nearby hostiles.
-- Respects hackableRobots, underground flag, raid bans/lockouts. Skips new chains in raid.
function RfsBotHijack._tickChainConvert( live, now )
	RfsBotHijack.chain = RfsBotHijack.chain or {}
	if not hackableRobotsOn() then
		for key, ch in pairs( RfsBotHijack.chain ) do
			local unit = live[key]
			if unit then
				setUnitTag( unit, "" )
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
						if remain <= 0 then
							local opts = {
								mode = ( info.mode == "infected" ) and "infected" or "tethered",
								beaconKey = ( info.mode ~= "infected" ) and info.beaconKey or nil,
								workBeaconKey = info.workBeaconKey or info.beaconKey,
								hijackTicks = info.hijackTicks,
							}
							local ok = RfsBotHijack.convertUnit( best, info.owner or 0, opts )
							setUnitTag( best, "" )
							if not ok then
								-- Keep trying next tick if convert failed for a soft reason.
								ch.startTick = now - ( ch.need - 40 )
								capturePos( ch, best )
								nextChain[hkey] = ch
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
			if unit and not RfsBotHijack.isAlly( unit ) then
				-- Clear stale chain tag unless pending/drop owns the tag.
				if not ( RfsBotHijack.pending and RfsBotHijack.pending[key] )
					and not ( RfsBotHijack.drops and RfsBotHijack.drops[key] ) then
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
	RfsBotHijack.drops = nextDrops
	for _, unit in ipairs( toRelease ) do
		local inRaid = false
		pcall( function()
			inRaid = RfsBotHijack.areaHasRaid( unit.character.worldPosition, unit.character:getWorld() )
		end )
		RfsBotHijack.releaseHack( unit, inRaid )
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

function RfsBotHijack.homeAllyCount( beaconKey )
	if not beaconKey then
		return 0
	end
	beaconKey = tostring( beaconKey )
	local n = 0
	for _, info in pairs( RfsBotHijack.allies ) do
		if info.controlled and RfsBotHijack.homeBeaconKey( info ) == beaconKey then
			n = n + 1
		end
	end
	return n
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
function RfsBotHijack.listHomeAllies( beaconKey, ownerFilterId )
	beaconKey = tostring( beaconKey or "" )
	local rows = {}
	if beaconKey == "" then
		return rows
	end
	for key, info in pairs( RfsBotHijack.allies ) do
		if info and info.controlled and RfsBotHijack.homeBeaconKey( info ) == beaconKey then
			if ownerFilterId == nil or tostring( info.owner ) == tostring( ownerFilterId ) then
				local ord = info.rfsOrder or info.order
				local orderMode = "defend"
				if type( ord ) == "table" and ord.mode then
					orderMode = tostring( ord.mode )
				end
				rows[#rows + 1] = {
					key = tostring( key ),
					name = info.displayName or shortTypeName( info.unitType or info.type ),
					unitType = info.unitType or info.type,
					type = info.type,
					mode = orderMode,
					seedUuid = ( type( ord ) == "table" and ord.seedUuid ) or nil,
					owner = info.owner,
					allyMode = info.mode,
				}
			end
		end
	end
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
				unitType = self.saved.rfsUnitType,
				firstSeenTick = self.saved.rfsFirstSeenTick,
			} )
			self.saved.friendly = false
			pcall( function()
				self.unit.character:setColor( mode == "infected" and INFECT_COLOR or ALLY_COLOR )
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
					self.saved.playerAlly = nil
					self.saved.playerAllyMode = nil
					self.saved.playerAllyBeacon = nil
					self.saved.friendly = false
					self.isDirty = true
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
			self.saved.rfsUnitType = info and ( info.unitType or info.type )
			self.saved.rfsFirstSeenTick = info and info.firstSeenTick
			if info and type( info.order ) == "table" then
				self.saved.rfsOrder = info.order
			elseif info and type( info.rfsOrder ) == "table" then
				self.saved.rfsOrder = info.rfsOrder
			end
			self.isDirty = true
			RfsBotHijack.standDown( self )
			if self.unit and self.unit.character then
				applyColor( self.unit.character, ( info and info.mode == "infected" ) and INFECT_COLOR or ALLY_COLOR )
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
	print( "[RFS] Bot hijack hooks installed (beacon computer / infect)" )
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
						self.saved.rfsUnitType = nil
						self.saved.rfsFirstSeenTick = nil
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
					if params.unitType then
						self.saved.rfsUnitType = params.unitType
					end
					if params.firstSeenTick then
						self.saved.rfsFirstSeenTick = params.firstSeenTick
					end
					if type( params.rfsOrder ) == "table" then
						self.saved.rfsOrder = params.rfsOrder
					end
					self.isDirty = true
				end
				cls._rfsHackableRpc = true
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
					if self.unit and RfsBotHijack.isAlly( self.unit ) then
						if self.saved.rfsHackable == false then
							RfsBotHijack.unregister( self.unit )
						else
							RfsBotHijack.standDown( self )
						end
					end
					return orig( self, dt )
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
