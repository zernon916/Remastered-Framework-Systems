-- RfsHackV1Hold.lua
-- VOLATILE: timed unhack (defense, not standing army).
-- Base 8 s; Radio Lock adds +3 s (RfsRadioStation). Leave-range telegraph stays elsewhere.

RfsHackV1Hold = RfsHackV1Hold or {}

local TPS = 40
local BASE_SEC = 8

function RfsHackV1Hold.baseSeconds()
	return BASE_SEC
end

function RfsHackV1Hold.secondsFor( holdSec )
	holdSec = tonumber( holdSec )
	if holdSec and holdSec > 0 then
		return holdSec
	end
	return BASE_SEC
end

-- Legacy: ignore cap for duration; use holdSec when provided.
function RfsHackV1Hold.secondsForCap( _cap, holdSec )
	return RfsHackV1Hold.secondsFor( holdSec )
end

function RfsHackV1Hold.unhackAtFromSeconds( holdSec, now )
	now = tonumber( now ) or 0
	return now + ( RfsHackV1Hold.secondsFor( holdSec ) * TPS )
end

-- Legacy signature unhackAtTick(cap, now) → base 8 s. Prefer unhackAtFromSeconds.
function RfsHackV1Hold.unhackAtTick( _cap, now, holdSec )
	if holdSec ~= nil then
		return RfsHackV1Hold.unhackAtFromSeconds( holdSec, now )
	end
	return RfsHackV1Hold.unhackAtFromSeconds( BASE_SEC, now )
end

function RfsHackV1Hold.releaseTagText( unhackAt, tick, allyName )
	allyName = tostring( allyName or "" ):gsub( "^%s+", "" ):gsub( "%s+$", "" )
	unhackAt = tonumber( unhackAt )
	tick = tonumber( tick ) or 0
	if not unhackAt then
		if allyName ~= "" then
			return allyName
		end
		return "HACKED"
	end
	local left = math.max( 0, math.ceil( ( unhackAt - tick ) / TPS ) )
	local m = math.floor( left / 60 )
	local s = left % 60
	local timer = string.format( "%d:%02d", m, s )
	if allyName ~= "" then
		return allyName .. "  " .. timer
	end
	return "HACKED " .. timer
end

function RfsHackV1Hold.expire( ctx )
	if type( ctx ) ~= "table" or type( RfsHackV1Registry ) ~= "table" then
		return
	end
	local tick = tonumber( ctx.tick ) or 0
	local rows = RfsHackV1Registry.listAllies( ctx.key, ctx.world )
	for i = 1, #rows do
		local row = rows[i]
		if row and row.unit then
			local blob = RfsHackV1Registry.read( row.unit )
			local at = blob and tonumber( blob.unhackAt )
			if at and tick >= at then
				if type( RfsHackV1Unhack ) == "table" and RfsHackV1Unhack.begin then
					RfsHackV1Unhack.begin( row.unit, { beaconKey = ctx.key, world = ctx.world } )
				end
			end
		end
	end
end

print( "[RFS] RfsHackV1Hold loaded (base 8s + lock bonus)" )
