-- RfsHackV1Timer.lua
-- VOLATILE: 4.0s convert countdown. Nametag ~4/sec during convert only. No chain.

RfsHackV1Timer = RfsHackV1Timer or {}

local CONVERT_TICKS = 40 * 4
local TAG_EVERY = 10

RfsHackV1Timer._jobs = RfsHackV1Timer._jobs or {}

local function unitKey( unit )
	if type( RfsHackV1Registry ) == "table" then
		return RfsHackV1Registry.unitKey( unit )
	end
	return nil
end

function RfsHackV1Timer.isBusy( unit )
	local k = unitKey( unit )
	return k and RfsHackV1Timer._jobs[k] ~= nil
end

function RfsHackV1Timer.countForBeacon( beaconKey )
	beaconKey = tostring( beaconKey or "" )
	local n = 0
	for _, job in pairs( RfsHackV1Timer._jobs ) do
		if job and tostring( job.beaconKey or "" ) == beaconKey then
			n = n + 1
		end
	end
	return n
end

function RfsHackV1Timer.cancelUnit( unit )
	local k = unitKey( unit )
	if k then
		RfsHackV1Timer._jobs[k] = nil
	end
	if unit and type( RfsHackV1Convert ) == "table" and RfsHackV1Convert.clearTag then
		RfsHackV1Convert.clearTag( unit )
	end
end

function RfsHackV1Timer.cancelBeacon( beaconKey )
	beaconKey = tostring( beaconKey or "" )
	for k, job in pairs( RfsHackV1Timer._jobs ) do
		if job and tostring( job.beaconKey or "" ) == beaconKey then
			if job.unit and type( RfsHackV1Convert ) == "table" and RfsHackV1Convert.clearTag then
				RfsHackV1Convert.clearTag( job.unit )
			end
			RfsHackV1Timer._jobs[k] = nil
		end
	end
end

function RfsHackV1Timer.begin( unit, beaconKey, cap, holdSec )
	if not unit or not sm.exists( unit ) then
		return false
	end
	if RfsHackV1Timer.isBusy( unit ) then
		return false
	end
	if type( RfsHackV1Registry ) == "table" and RfsHackV1Registry.isAlly( unit ) then
		return false
	end
	local k = unitKey( unit )
	if not k then
		return false
	end
	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick() or 0
	end )
	RfsHackV1Timer._jobs[k] = {
		unit = unit,
		beaconKey = tostring( beaconKey or "" ),
		cap = tonumber( cap ) or 4,
		holdSec = tonumber( holdSec ) or 8,
		startTick = tick,
		endTick = tick + CONVERT_TICKS,
		lastTag = -TAG_EVERY,
	}
	return true
end

function RfsHackV1Timer.pulse( beacon, tick, pos, maxD2 )
	tick = tonumber( tick ) or 0
	local key = tostring( beacon and beacon.sv and beacon.sv.key or "" )
	local done = {}
	local drop = {}
	for k, job in pairs( RfsHackV1Timer._jobs ) do
		if job and tostring( job.beaconKey or "" ) == key then
			local unit = job.unit
			local alive = unit and sm.exists( unit )
			local char = alive and unit.character
			if not alive or not char or not sm.exists( char ) then
				drop[#drop + 1] = k
			else
				local inRange = true
				if pos and maxD2 then
					inRange = ( char.worldPosition - pos ):length2() <= maxD2
				end
				if not inRange then
					if type( RfsHackV1Convert ) == "table" and RfsHackV1Convert.clearTag then
						RfsHackV1Convert.clearTag( unit )
					end
					drop[#drop + 1] = k
				elseif tick >= job.endTick then
					done[#done + 1] = job
					drop[#drop + 1] = k
				elseif ( tick - job.lastTag ) >= TAG_EVERY then
					job.lastTag = tick
					local left = math.max( 0, ( job.endTick - tick ) / 40 )
					if type( RfsHackV1Convert ) == "table" then
						RfsHackV1Convert.pushTag( unit, string.format( "HACK %.1f", left ) )
					end
				end
			end
		end
	end
	for i = 1, #drop do
		RfsHackV1Timer._jobs[drop[i]] = nil
	end
	for i = 1, #done do
		local job = done[i]
		if type( RfsHackV1Convert ) == "table" then
			RfsHackV1Convert.convertUnit( job.unit, job.beaconKey, job.cap, job.holdSec )
		end
	end
end

print( "[RFS] RfsHackV1Timer loaded (4.0s convert)" )
