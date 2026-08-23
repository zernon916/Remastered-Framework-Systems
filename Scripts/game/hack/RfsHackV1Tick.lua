-- RfsHackV1Tick.lua
-- VOLATILE: raid-only convert, fence, hold expire, raid-end mass unhack. No chain.

RfsHackV1Tick = RfsHackV1Tick or {}

local SLOW = 16
-- TEMP range test: toast at most every ~5s while diagnosing no-hack.
local DEBUG_EVERY = 40 * 5

local function devicesOn()
	if type( RfsFeatures ) == "table" and type( RfsFeatures.hackDevicesEnabled ) == "function" then
		local ok, v = pcall( RfsFeatures.hackDevicesEnabled )
		if ok then
			return v and true or false
		end
	end
	return true
end

local function robotsOn()
	if type( RfsFeatures ) == "table" and type( RfsFeatures.hackableRobotsEnabled ) == "function" then
		local ok, v = pcall( RfsFeatures.hackableRobotsEnabled )
		if ok then
			return v and true or false
		end
	end
	return true
end

local function resolveWorld( shape )
	local world
	pcall( function()
		world = shape:getBody():getWorld()
	end )
	if not world then
		pcall( function()
			world = shape.body:getWorld()
		end )
	end
	return world
end

-- Context from live beacon tier (modules applied on the beacon each tick).
local function context( beacon, tick )
	local shape = beacon.shape
	local world = resolveWorld( shape )
	local pos = shape.worldPosition
	local range = 30
	local cap = 4
	local holdSec = 8
	pcall( function()
		local t = beacon.sv and beacon.sv.tier
		if type( t ) == "table" then
			range = tonumber( t.range ) or range
			cap = tonumber( t.hackCap ) or cap
			holdSec = tonumber( t.holdSec ) or holdSec
		end
	end )
	return {
		beacon = beacon,
		shape = shape,
		world = world,
		pos = pos,
		range = range,
		maxD2 = range * range,
		key = tostring( beacon.sv.key or "" ),
		cap = cap,
		holdSec = holdSec,
		powered = beacon.sv.powered and true or false,
		tick = tick,
	}
end

local function debugMsg( beacon, msg )
	if not beacon or not beacon.network or not msg or msg == "" then
		return
	end
	pcall( function()
		beacon.network:sendToClients( "cl_rfsMsg", tostring( msg ) )
	end )
end

local function debugMaybe( beacon, tick, msg )
	local last = tonumber( beacon.sv and beacon.sv._rfsHackV1DbgTick ) or -DEBUG_EVERY
	if ( tick - last ) < DEBUG_EVERY then
		return
	end
	beacon.sv._rfsHackV1DbgTick = tick
	debugMsg( beacon, msg )
end

-- Count hackable hostiles in-range vs out-of-range (for TEMP range diagnosis).
local function countCandidates( ctx )
	local inRange, outRange = 0, 0
	if type( RfsHackV1Convert ) ~= "table" or not RfsHackV1Convert.isHackableRobot then
		return inRange, outRange
	end
	local units
	if ctx.world then
		pcall( function()
			units = sm.unit.getAllUnits( ctx.world )
		end )
	end
	if type( units ) ~= "table" then
		return inRange, outRange
	end
	for i = 1, #units do
		local u = units[i]
		if u and sm.exists( u ) then
			local char = u.character
			if char and sm.exists( char ) and RfsHackV1Convert.isHackableRobot( char ) then
				local blob = type( RfsHackV1Registry ) == "table" and RfsHackV1Registry.read( u )
				if not blob or not blob.ally then
					if type( RfsHackV1Timer ) ~= "table" or not RfsHackV1Timer.isBusy( u ) then
						local d2 = ( char.worldPosition - ctx.pos ):length2()
						if d2 <= ctx.maxD2 then
							inRange = inRange + 1
						else
							outRange = outRange + 1
						end
					end
				end
			end
		end
	end
	return inRange, outRange
end

local function scanStart( ctx )
	if not ctx.powered or not devicesOn() or not robotsOn() then
		return
	end
	if type( RfsHackV1Convert ) ~= "table" or not RfsHackV1Convert.isHackableRobot then
		return
	end
	local units
	if ctx.world then
		pcall( function()
			units = sm.unit.getAllUnits( ctx.world )
		end )
	end
	if type( units ) ~= "table" then
		return
	end
	local converting = 0
	if type( RfsHackV1Timer ) == "table" then
		converting = RfsHackV1Timer.countForBeacon( ctx.key )
	end
	local used = converting
	local nearby = {}
	local outRange = 0
	for i = 1, #units do
		local u = units[i]
		if u and sm.exists( u ) then
			local char = u.character
			if char and sm.exists( char ) then
				local blob = type( RfsHackV1Registry ) == "table" and RfsHackV1Registry.read( u )
				local d2 = ( char.worldPosition - ctx.pos ):length2()
				if d2 <= ctx.maxD2 and type( RfsHackV1Persist ) == "table" and not blob then
					RfsHackV1Persist.touch( u )
				end
				if blob and blob.ally and tostring( blob.beaconKey or "" ) == ctx.key then
					used = used + 1
				elseif ( not blob or not blob.ally ) and RfsHackV1Convert.isHackableRobot( char ) then
					if type( RfsHackV1Timer ) ~= "table" or not RfsHackV1Timer.isBusy( u ) then
						if d2 <= ctx.maxD2 then
							nearby[#nearby + 1] = u
						else
							outRange = outRange + 1
						end
					end
				end
			end
		end
	end
	-- Overlay shows ARMED/ENGAGED; skip chat when raid+power with 0 candidates.
	if used >= ctx.cap then
		return
	end
	for i = 1, #nearby do
		if used >= ctx.cap then
			break
		end
		if type( RfsHackV1Timer ) == "table" and RfsHackV1Timer.begin( nearby[i], ctx.key, ctx.cap, ctx.holdSec ) then
			used = used + 1
		end
	end
end

function RfsHackV1Tick.serverTick( beacon )
	if not beacon or not beacon.sv then
		return
	end
	local shape = beacon.shape
	if not shape or not sm.exists( shape ) then
		return
	end
	if type( RfsHackV1Persist ) == "table" and RfsHackV1Persist.hostTick then
		RfsHackV1Persist.hostTick()
	end
	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick() or 0
	end )
	local world = resolveWorld( shape )
	if type( RfsHackV1 ) == "table" and RfsHackV1.spawnHost then
		pcall( RfsHackV1.spawnHost, world )
	end
	if type( RfsHackV1Convert ) == "table" then
		RfsHackV1Convert.ensureUnitEnv()
	end
	local ctx = context( beacon, tick )
	local raid = false
	if type( RfsHackV1Raid ) == "table" then
		raid = RfsHackV1Raid.isActive( ctx.pos, ctx.world ) and true or false
	end
	local was = beacon.sv._rfsHackV1WasRaid and true or false
	beacon.sv._rfsHackV1WasRaid = raid
	-- TEMP range test: powered but raid detector false → no convert (raid-only).
	-- Overlay shows STANDBY; skip chat spam.
	-- TEMP: raid detected but beacon not powered — overlay is primary (HACK: NO POWER).
	-- Rare chat only on first fail / reason change (~once per reason).
	if raid and not ctx.powered then
		local reason = "no power"
		if type( RfsHackPower ) == "table" and RfsHackPower.powerFailReason then
			pcall( function()
				reason = RfsHackPower.powerFailReason( beacon ) or reason
			end )
		end
		local prev = beacon.sv._rfsPowerFailReason
		if prev ~= reason then
			beacon.sv._rfsPowerFailReason = reason
			debugMaybe( beacon, tick, "hack: NO POWER (" .. tostring( reason ) .. ")" )
		end
	elseif ctx.powered then
		beacon.sv._rfsPowerFailReason = nil
	end
	-- TEMP: gensettings flags off while in raid.
	if raid and ctx.powered and ( tick % SLOW ) == 0 then
		if not devicesOn() or not robotsOn() then
			debugMaybe( beacon, tick, string.format(
				"hack: flags off (devices=%s robots=%s)",
				tostring( devicesOn() ), tostring( robotsOn() )
			) )
		end
	end
	if not raid then
		if type( RfsHackV1Timer ) == "table" then
			RfsHackV1Timer.cancelBeacon( ctx.key )
		end
		-- Raid just ended → force release every ally on this beacon (33% SELF DESTRUCT fuse).
		-- Periodic sweep (no explode) + sync catches sticky saved-only leftovers.
		if was then
			if type( RfsHackV1Unhack ) == "table" then
				RfsHackV1Unhack.allForBeacon( ctx.key, ctx.world, { raidEnd = true } )
				if RfsHackV1Unhack.forceSyncWorld then
					RfsHackV1Unhack.forceSyncWorld( ctx.world )
				end
			end
		elseif ( tick % SLOW ) == 0 then
			if type( RfsHackV1Unhack ) == "table" then
				RfsHackV1Unhack.allForBeacon( ctx.key, ctx.world )
				if RfsHackV1Unhack.forceSyncWorld then
					RfsHackV1Unhack.forceSyncWorld( ctx.world )
				end
			end
		end
		-- Fuse countdowns must tick after raid ends (this branch returns before pulse).
		if type( RfsHackV1Unhack ) == "table" and RfsHackV1Unhack.pulseFuse then
			RfsHackV1Unhack.pulseFuse( tick )
		end
		return
	end
	if type( RfsHackV1Timer ) == "table" then
		RfsHackV1Timer.pulse( beacon, tick, ctx.pos, ctx.maxD2 )
	end
	if type( RfsHackV1Unhack ) == "table" and RfsHackV1Unhack.pulse then
		RfsHackV1Unhack.pulse( beacon, tick )
	end
	if type( RfsHackV1Unhack ) == "table" and RfsHackV1Unhack.pulseFuse then
		RfsHackV1Unhack.pulseFuse( tick )
	end
	if ( tick % SLOW ) ~= 0 then
		return
	end
	if type( RfsHackV1Fence ) == "table" then
		RfsHackV1Fence.check( ctx )
	end
	if type( RfsHackV1Hold ) == "table" then
		RfsHackV1Hold.expire( ctx )
	end
	if type( RfsHackV1Raid ) == "table" then
		RfsHackV1Raid.spice( ctx )
	end
	scanStart( ctx )
end

function RfsHackV1Tick.hostPulse()
	if type( RfsHackV1Persist ) == "table" and RfsHackV1Persist.hostTick then
		RfsHackV1Persist.hostTick()
	end
end

print( "[RFS] RfsHackV1Tick loaded (raid-end force release + 33% SELF DESTRUCT fuse)" )
