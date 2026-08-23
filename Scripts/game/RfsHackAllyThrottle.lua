-- RfsHackAllyThrottle.lua
-- VOLATILE: per-hacked-ally tick budgets (tags, publicData flag scan, color, aggro).
-- FROZEN: hijack HP/damage is RfsHackTether. DROP+death Orders drop is RfsHackOrdersDrop.
-- Spend/caps/Orders open/SHOW RANGE host: do not touch from this file.

RfsHackAllyThrottle = RfsHackAllyThrottle or {}

RfsHackAllyThrottle.TAG_EVERY = 80 -- 2 s identity nametag RPC (was 0.5 s + every think)
RfsHackAllyThrottle.FLAGS_EVERY = 20 -- consumePublicFlags; HACK finish still writes immediately
RfsHackAllyThrottle.DAMAGE_ENSURE_EVERY = 40 -- unit-env damage wrap retry (not every think)
RfsHackAllyThrottle.AGGRO_EVERY = 10 -- cache allUnits scans from ally/hostile Select
RfsHackAllyThrottle.COLOR_EVERY = 20
RfsHackAllyThrottle.CHAR_HOOKS_EVERY = 80

function RfsHackAllyThrottle.now()
	local t = 0
	pcall( function()
		t = sm.game.getCurrentTick() or 0
	end )
	return t
end

function RfsHackAllyThrottle.due( slot, every )
	every = tonumber( every ) or 20
	if every < 1 then
		every = 1
	end
	local now = RfsHackAllyThrottle.now()
	RfsHackAllyThrottle._last = RfsHackAllyThrottle._last or {}
	local last = tonumber( RfsHackAllyThrottle._last[slot] ) or -every
	if ( now - last ) < every then
		return false
	end
	RfsHackAllyThrottle._last[slot] = now
	return true
end

print( "[RFS] RfsHackAllyThrottle loaded (0851-p per-ally budgets)" )
