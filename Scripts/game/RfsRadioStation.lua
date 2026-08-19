-- RfsRadioStation.lua — VOLATILE stub: mid tier needs brick + antenna wired to Hack Beacon core.
-- Cap 4 / longer range when BOTH present on same logic net (not implemented this pass).

RfsRadioStation = RfsRadioStation or {}

local UUID_BRICK = "d9e3b1a0-2b6c-4d8e-9f1a-0c4d5e6f7a8b"
local UUID_ANTENNA = "ca2d0a9f-1a5b-4c7d-8e09-fb3a4b5c6d7e"
local UUID_LOCK = "bb1c098e-094a-4b6c-7d08-ea293a4b5c6d"
local UUID_HACK = "b4e8c1a0-7d2f-4a91-9c3e-29f1a8d6b5e7"

function RfsRadioStation.partUuid( kind )
	if kind == "brick" then return UUID_BRICK end
	if kind == "antenna" then return UUID_ANTENNA end
	if kind == "lock" then return UUID_LOCK end
	if kind == "core" then return UUID_HACK end
	return nil
end

-- Stub: returns false until wiring pass completes.
function RfsRadioStation.midTierActive( _beaconScript )
	return false
end

print( "[RFS] RfsRadioStation loaded (stub brick+antenna wired mid tier)" )
