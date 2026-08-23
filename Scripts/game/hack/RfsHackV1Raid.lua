-- RfsHackV1Raid.lua
-- VOLATILE: Survival farm-raid detect + extra break/explode spice while hacked.
-- Convert is raid-only (see Tick). Timer always wins over RNG. No chain.
--
-- Beacon interactable sandbox cannot see Game's g_raidManager. Game publishes a
-- compact probe into sm.storage; isActive reads that (plus live APIs when present).

RfsHackV1Raid = RfsHackV1Raid or {}

local PROBE_KEY = { "rfs", "hackV1RaidProbe" }
local RAID_RADIUS = 96.0
local RAID_RADIUS2 = RAID_RADIUS * RAID_RADIUS
local INCOMING_TICKS = 40 * 60

-- One math.random per ally per slow tick. Better device = safer.
-- Per 16-tick (~0.4s) while hacked during raid:
--   cap 2: 1.5% break, 0.40% explode
--   cap 4: 0.8% break, 0.20% explode
--   cap 6: 0.4% break, 0.10% explode
local RATES = {
	[2] = { brk = 0.015, boom = 0.004 },
	[4] = { brk = 0.008, boom = 0.002 },
	[6] = { brk = 0.004, boom = 0.001 },
}

local function ratesForCap( cap )
	cap = tonumber( cap ) or 2
	if cap >= 6 then
		return RATES[6]
	end
	if cap >= 4 then
		return RATES[4]
	end
	return RATES[2]
end

local function worldIdOf( world )
	local worldId
	pcall( function()
		if world then
			worldId = world.id
		end
	end )
	return worldId
end

local function raidTableActive( raid, now )
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
		now = tonumber( now ) or 0
		-- Same window as the on-screen incoming raid warning (~60 s).
		if now >= ( tonumber( ad.attackTick ) - INCOMING_TICKS ) then
			return true
		end
	end
	return false
end

local function posNearRaid( pos, raid )
	if not pos or type( raid ) ~= "table" or not raid.center then
		return false
	end
	local d2 = nil
	pcall( function()
		d2 = ( pos - raid.center ):length2()
	end )
	return d2 ~= nil and d2 <= RAID_RADIUS2
end

local function probeHasRaid( probe, pos, worldId )
	if type( probe ) ~= "table" or type( probe.zones ) ~= "table" or not pos then
		return false
	end
	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick() or 0
	end )
	-- Stale probe (Game not ticking this copy): ignore.
	if probe.tick and ( tick - tonumber( probe.tick ) ) > ( 40 * 5 ) then
		return false
	end
	for i = 1, #probe.zones do
		local z = probe.zones[i]
		if type( z ) == "table" and z.center then
			local sameWorld = true
			if worldId ~= nil and z.wid ~= nil and z.wid ~= worldId then
				sameWorld = false
			end
			if sameWorld then
				local d2 = nil
				pcall( function()
					d2 = ( pos - z.center ):length2()
				end )
				local r2 = tonumber( z.r2 ) or RAID_RADIUS2
				if d2 ~= nil and d2 <= r2 then
					return true
				end
			end
		end
	end
	return false
end

local function storageRaidActive( pos, worldId )
	local saved
	local ch = ( type( STORAGE_CHANNEL_RAIDMANAGER ) == "number" and STORAGE_CHANNEL_RAIDMANAGER ) or 45
	pcall( function()
		saved = sm.storage.load( ch )
	end )
	if type( saved ) ~= "table" or type( saved.worldRaids ) ~= "table" then
		return false
	end
	local now = 0
	pcall( function()
		now = sm.game.getCurrentTick() or 0
	end )
	local function scanWorld( raids )
		if type( raids ) ~= "table" then
			return false
		end
		for _, raid in pairs( raids ) do
			if raidTableActive( raid, now ) and posNearRaid( pos, raid ) then
				return true
			end
		end
		return false
	end
	if worldId ~= nil then
		if scanWorld( saved.worldRaids[worldId] ) then
			return true
		end
		if scanWorld( saved.worldRaids[tostring( worldId )] ) then
			return true
		end
	end
	-- worldId missing / mismatched key type: still honor any overlapping zone.
	for _, raids in pairs( saved.worldRaids ) do
		if scanWorld( raids ) then
			return true
		end
	end
	return false
end

local function raiderPulseNearby( pos, world )
	if not pos then
		return false
	end
	local units
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
		return false
	end
	local now = 0
	pcall( function()
		now = sm.game.getCurrentTick() or 0
	end )
	for i = 1, #units do
		local u = units[i]
		if u and sm.exists( u ) then
			local char = u.character
			if char and sm.exists( char ) then
				local pulse
				pcall( function()
					local pd = char.publicData
					if type( pd ) == "table" then
						pulse = tonumber( pd.rfsRaidPulse )
					end
				end )
				if pulse and ( now - pulse ) <= 80 then
					local d2 = nil
					pcall( function()
						d2 = ( char.worldPosition - pos ):length2()
					end )
					if d2 ~= nil and d2 <= RAID_RADIUS2 then
						return true
					end
				end
			end
		end
	end
	return false
end

-- Game sandbox only: snapshot live RaidManager into shared storage for beacon ticks.
function RfsHackV1Raid.publishProbe()
	local zones = {}
	local now = 0
	pcall( function()
		now = sm.game.getCurrentTick() or 0
	end )
	local mgr = _G.g_raidManager
	if mgr and mgr.sv and type( mgr.sv.saved ) == "table" and type( mgr.sv.saved.worldRaids ) == "table" then
		for wid, raids in pairs( mgr.sv.saved.worldRaids ) do
			if type( raids ) == "table" then
				for _, raid in pairs( raids ) do
					if raidTableActive( raid, now ) and raid.center then
						zones[#zones + 1] = {
							wid = wid,
							center = raid.center,
							r2 = RAID_RADIUS2,
						}
					end
				end
			end
		end
	end
	pcall( function()
		sm.storage.save( PROBE_KEY, { tick = now, zones = zones } )
	end )
end

function RfsHackV1Raid.isActive( pos, world )
	if not pos then
		return false
	end
	local worldId = worldIdOf( world )

	if type( RaidManager ) == "table" and type( RaidManager.Sv_AreaHasActiveRaid ) == "function" then
		local ok, v = pcall( RaidManager.Sv_AreaHasActiveRaid, pos, worldId )
		if ok and v then
			return true
		end
	end
	if _G.g_raidManager then
		local mgr = _G.g_raidManager
		if type( mgr.sv_areaHasActiveRaid ) == "function" then
			local ok, v = pcall( function()
				return mgr:sv_areaHasActiveRaid( pos, worldId )
			end )
			if ok and v then
				return true
			end
		end
		-- Incoming window (Sv_AreaHasActiveRaid is timeoutTick-only).
		if type( mgr.sv_getRaidAtPosition ) == "function" and worldId ~= nil then
			local ok, raid = pcall( function()
				return mgr:sv_getRaidAtPosition( worldId, pos )
			end )
			local now = 0
			pcall( function()
				now = sm.game.getCurrentTick() or 0
			end )
			if ok and raidTableActive( raid, now ) then
				return true
			end
		end
	end

	local probe
	pcall( function()
		probe = sm.storage.load( PROBE_KEY )
	end )
	if probeHasRaid( probe, pos, worldId ) then
		return true
	end
	if storageRaidActive( pos, worldId ) then
		return true
	end
	if raiderPulseNearby( pos, world ) then
		return true
	end
	return false
end

function RfsHackV1Raid.spice( ctx )
	if type( ctx ) ~= "table" or type( RfsHackV1Registry ) ~= "table" then
		return
	end
	local rows = RfsHackV1Registry.listAllies( ctx.key, ctx.world )
	for i = 1, #rows do
		local row = rows[i]
		if row and row.unit and sm.exists( row.unit ) then
			local blob = RfsHackV1Registry.read( row.unit )
			local cap = ( blob and tonumber( blob.cap ) ) or ctx.cap or 2
			local r = ratesForCap( cap )
			local roll = math.random()
			if roll < r.boom then
				if type( RfsHackV1Unhack ) == "table" then
					RfsHackV1Unhack.unit( row.unit, { beaconKey = ctx.key, world = ctx.world, explode = true } )
				end
			elseif roll < ( r.boom + r.brk ) then
				if type( RfsHackV1Unhack ) == "table" then
					RfsHackV1Unhack.unit( row.unit, { beaconKey = ctx.key, world = ctx.world } )
				end
			end
		end
	end
end

print( "[RFS] RfsHackV1Raid loaded (probe + storage + incoming)" )
