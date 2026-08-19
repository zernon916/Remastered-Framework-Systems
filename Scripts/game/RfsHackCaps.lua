-- RfsHackCaps.lua
-- OWNER: per-device hijack caps.
-- FROZEN: 2 / 4 / 6 (Hack / Control / Infection). User tested — do not change unless asked.

RfsHackCaps = RfsHackCaps or {}
rfsHackCaps = RfsHackCaps

local UUID_HACK = "b4e8c1a0-7d2f-4a91-9c3e-29f1a8d6b5e7"
local UUID_CTRL = "c5f9d2b1-8e30-4ba2-ad4f-30a2b9e7c6f8"
local UUID_INFE = "d6a0e3c2-9f41-4cb3-be50-41b3c0f8d709"
local UUID_CORE = "c2f158b0-4d7e-4a19-9c6b-8e3a1f50d247"

RfsHackCaps.BY_UUID = {
	[UUID_HACK] = 2,
	[UUID_CTRL] = 4,
	[UUID_INFE] = 6,
	[UUID_CORE] = 2,
}

function RfsHackCaps.forUuid( uuid )
	return RfsHackCaps.BY_UUID[tostring( uuid or "" )] or 2
end

function RfsHackCaps.forRange( range )
	range = tonumber( range ) or 16
	if range >= 48 then
		return 6
	end
	if range >= 32 then
		return 4
	end
	return 2
end

print( "[RFS] RfsHackCaps loaded (frozen 2/4/6)" )
