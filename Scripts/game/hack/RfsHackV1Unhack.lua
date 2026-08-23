-- RfsHackV1Unhack.lua
-- VOLATILE: drop ally (registry + saved flag). 2s UNHACK telegraph, not a name. No list. No chain.
-- Raid-end mass release: immediate (no telegraph). 33% → 2s SELF DESTRUCT fuse then boom.
-- Mid-raid spice explode (opts.explode) stays instant — fuse is raid-end chance only.

RfsHackV1Unhack = RfsHackV1Unhack or {}

local UNHACK_TICKS = 40 * 2
local FUSE_TICKS = 40 * 2
local TAG_EVERY = 20
local RAID_END_EXPLODE = 0.33

RfsHackV1Unhack._jobs = RfsHackV1Unhack._jobs or {}
RfsHackV1Unhack._fuseJobs = RfsHackV1Unhack._fuseJobs or {}

local function unitKey( unit )
	if type( RfsHackV1Registry ) == "table" then
		return RfsHackV1Registry.unitKey( unit )
	end
	return nil
end

local function nowTick()
	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick() or 0
	end )
	return tick
end

local function explodeDestroy( unit )
	if not unit or not sm.exists( unit ) then
		return
	end
	local pos
	pcall( function()
		local char = unit.character
		if char and sm.exists( char ) then
			pos = char.worldPosition
		end
	end )
	if pos then
		pcall( function()
			sm.physics.explode( pos, 5, 4.0, 4.0, 15, "Totebotred - Explosion" )
		end )
	end
	pcall( function()
		unit:destroy()
	end )
end

function RfsHackV1Unhack.telegraphTicks()
	return UNHACK_TICKS
end

function RfsHackV1Unhack.isPending( unit )
	local k = unitKey( unit )
	return k and RfsHackV1Unhack._jobs[k] ~= nil
end

function RfsHackV1Unhack.isFusing( unit )
	local k = unitKey( unit )
	return k and RfsHackV1Unhack._fuseJobs[k] ~= nil
end

function RfsHackV1Unhack.refreshList( beaconKey, world )
end

function RfsHackV1Unhack.begin( unit, opts )
	opts = opts or {}
	if not unit or not sm.exists( unit ) then
		return false
	end
	if RfsHackV1Unhack.isPending( unit ) or RfsHackV1Unhack.isFusing( unit ) then
		return false
	end
	local k = unitKey( unit )
	if not k then
		return false
	end
	local tick = nowTick()
	RfsHackV1Unhack._jobs[k] = {
		unit = unit,
		beaconKey = tostring( opts.beaconKey or "" ),
		world = opts.world,
		endTick = tick + UNHACK_TICKS,
		lastTag = -TAG_EVERY,
	}
	return true
end

-- Raid-end 33%: keep ally until boom; overhead SELF DESTRUCT countdown.
function RfsHackV1Unhack.beginFuse( unit, opts )
	opts = opts or {}
	if not unit or not sm.exists( unit ) then
		return false
	end
	local k = unitKey( unit )
	if not k then
		return false
	end
	if RfsHackV1Unhack._fuseJobs[k] then
		return false
	end
	-- Drop pending UNHACK telegraph if any — fuse owns the tag now.
	RfsHackV1Unhack._jobs[k] = nil
	local tick = nowTick()
	RfsHackV1Unhack._fuseJobs[k] = {
		unit = unit,
		beaconKey = tostring( opts.beaconKey or "" ),
		world = opts.world,
		endTick = tick + FUSE_TICKS,
		lastTag = -TAG_EVERY,
	}
	if type( RfsHackV1Convert ) == "table" and RfsHackV1Convert.pushTag then
		RfsHackV1Convert.pushTag( unit, "SELF DESTRUCT 2.0" )
	end
	return true
end

function RfsHackV1Unhack.pulse( beacon, tick )
	tick = tonumber( tick ) or 0
	local key = tostring( beacon and beacon.sv and beacon.sv.key or "" )
	local done = {}
	local drop = {}
	for k, job in pairs( RfsHackV1Unhack._jobs ) do
		if job and ( key == "" or tostring( job.beaconKey or "" ) == key ) then
			local unit = job.unit
			if not unit or not sm.exists( unit ) then
				drop[#drop + 1] = k
			elseif tick >= job.endTick then
				done[#done + 1] = job
				drop[#drop + 1] = k
			elseif ( tick - job.lastTag ) >= TAG_EVERY then
				job.lastTag = tick
				local left = math.max( 0, ( job.endTick - tick ) / 40 )
				if type( RfsHackV1Convert ) == "table" and RfsHackV1Convert.pushTag then
					RfsHackV1Convert.pushTag( unit, string.format( "UNHACK %.1f", left ) )
				end
			end
		end
	end
	for i = 1, #drop do
		RfsHackV1Unhack._jobs[drop[i]] = nil
	end
	for i = 1, #done do
		local job = done[i]
		RfsHackV1Unhack.unit( job.unit, { beaconKey = job.beaconKey, world = job.world } )
	end
end

-- Raid-end fuse countdowns (must run after raid ends — Tick early-returns before pulse).
function RfsHackV1Unhack.pulseFuse( tick )
	tick = tonumber( tick ) or 0
	local done = {}
	local drop = {}
	for k, job in pairs( RfsHackV1Unhack._fuseJobs ) do
		if not job then
			drop[#drop + 1] = k
		else
			local unit = job.unit
			if not unit or not sm.exists( unit ) then
				drop[#drop + 1] = k
			elseif tick >= job.endTick then
				done[#done + 1] = job
				drop[#drop + 1] = k
			elseif ( tick - job.lastTag ) >= TAG_EVERY then
				job.lastTag = tick
				local left = math.max( 0, ( job.endTick - tick ) / 40 )
				if type( RfsHackV1Convert ) == "table" and RfsHackV1Convert.pushTag then
					RfsHackV1Convert.pushTag( unit, string.format( "SELF DESTRUCT %.1f", left ) )
				end
			end
		end
	end
	for i = 1, #drop do
		RfsHackV1Unhack._fuseJobs[drop[i]] = nil
	end
	for i = 1, #done do
		local job = done[i]
		RfsHackV1Unhack.unit( job.unit, {
			beaconKey = job.beaconKey,
			world = job.world,
			explode = true,
		} )
	end
end

function RfsHackV1Unhack.unit( unit, opts )
	opts = opts or {}
	if not unit or not sm.exists( unit ) then
		return
	end
	local k = unitKey( unit )
	if k then
		RfsHackV1Unhack._jobs[k] = nil
		RfsHackV1Unhack._fuseJobs[k] = nil
	end
	if type( RfsHackV1Timer ) == "table" and RfsHackV1Timer.cancelUnit then
		RfsHackV1Timer.cancelUnit( unit )
	end
	if type( RfsHackV1Registry ) == "table" and RfsHackV1Registry.clear then
		RfsHackV1Registry.clear( unit )
	end
	pcall( function()
		-- Instant so clearTint runs before optional explode destroy.
		if sm.event.types and sm.event.types.instant then
			sm.event.sendToUnit( unit, "sv_e_rfsHackV1Revert", {}, sm.event.types.instant )
		else
			sm.event.sendToUnit( unit, "sv_e_rfsHackV1Revert", {} )
		end
	end )
	if type( RfsHackV1Convert ) == "table" and RfsHackV1Convert.clearTag then
		RfsHackV1Convert.clearTag( unit )
	end
	-- Instant boom only (mid-raid spice / fuse expiry). Raid-end 33% uses beginFuse first.
	if opts.explode then
		explodeDestroy( unit )
	end
end

-- Immediate release of every ally on this beacon. opts.raidEnd → 33% get SELF DESTRUCT fuse.
function RfsHackV1Unhack.allForBeacon( beaconKey, world, opts )
	opts = opts or {}
	beaconKey = tostring( beaconKey or "" )
	for k, job in pairs( RfsHackV1Unhack._jobs ) do
		if job and tostring( job.beaconKey or "" ) == beaconKey then
			RfsHackV1Unhack._jobs[k] = nil
		end
	end
	if type( RfsHackV1Registry ) ~= "table" then
		return
	end
	local explodeChance = nil
	if opts.raidEnd then
		explodeChance = tonumber( opts.explodeChance ) or RAID_END_EXPLODE
	elseif opts.explodeChance then
		explodeChance = tonumber( opts.explodeChance )
	end
	local rows = RfsHackV1Registry.listAllies( beaconKey, world )
	for i = 1, #rows do
		local row = rows[i]
		if row and row.unit then
			-- Already on a fuse — leave them alone (periodic sweep must not clean-release).
			if RfsHackV1Unhack.isFusing( row.unit ) then
				-- keep counting down
			elseif explodeChance and explodeChance > 0 and math.random() < explodeChance then
				RfsHackV1Unhack.beginFuse( row.unit, {
					beaconKey = beaconKey,
					world = world,
				} )
			else
				RfsHackV1Unhack.unit( row.unit, {
					beaconKey = beaconKey,
					world = world,
				} )
			end
		end
	end
end

-- Catch sticky bots: registry cleared but unit.saved.rfsHackV1BeaconKey still set.
function RfsHackV1Unhack.forceSyncWorld( world )
	local units = nil
	if world then
		pcall( function()
			units = sm.unit.getAllUnits( world )
		end )
	end
	if type( units ) ~= "table" then
		pcall( function()
			units = sm.unit.getAllUnits()
		end )
	end
	if type( units ) ~= "table" then
		return
	end
	for i = 1, #units do
		local u = units[i]
		if u and sm.exists( u ) then
			pcall( function()
				sm.event.sendToUnit( u, "sv_e_rfsHackV1Sync", {} )
			end )
		end
	end
end

print( "[RFS] RfsHackV1Unhack loaded (0852-p release color + fuse)" )
