-- RfsHackCaps.lua
-- OWNER: per-device hijack caps.
-- Base Hack Beacon = 4. Radio Brick +1, Radio Lock +3 (see RfsRadioStation).

RfsHackCaps = RfsHackCaps or {}
rfsHackCaps = RfsHackCaps

local UUID_HACK = "b4e8c1a0-7d2f-4a91-9c3e-29f1a8d6b5e7"
local UUID_CORE = "c2f158b0-4d7e-4a19-9c6b-8e3a1f50d247"

RfsHackCaps.BASE = 4

RfsHackCaps.BY_UUID = {
	[UUID_HACK] = 4,
	[UUID_CORE] = 4,
}

function RfsHackCaps.forUuid( uuid )
	return RfsHackCaps.BY_UUID[tostring( uuid or "" )] or RfsHackCaps.BASE
end

function RfsHackCaps.forRange( range )
	return RfsHackCaps.BASE
end

-- Live cap for a beacon script (modules included).
function RfsHackCaps.forBeacon( beacon )
	if type( RfsRadioStation ) == "table" and RfsRadioStation.bonuses then
		local ok, b = pcall( RfsRadioStation.bonuses, beacon )
		if ok and type( b ) == "table" and tonumber( b.cap ) then
			return tonumber( b.cap )
		end
	end
	return RfsHackCaps.BASE
end

print( "[RFS] RfsHackCaps loaded (base 4 + radio modules)" )
