-- RfsHealPower.lua — thin re-export. Owner: RfsChemStation.lua (FROZEN power section).
-- Do not add logic here; edit RfsChemStation.lua only.

local RFS_CG = "$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247"
local function rfsDofile( rel )
	local paths = { RFS_CG .. "/" .. rel, "$CONTENT_DATA/" .. rel }
	for _, p in ipairs( paths ) do
		local ok = pcall( function()
			dofile( p )
		end )
		if ok then
			return true
		end
	end
	return false
end
rfsDofile( "Scripts/game/RfsChemStation.lua" )

RfsHealPower = RfsHealPower or ( RfsChemStation and RfsChemStation.power ) or {}

print( "[RFS] RfsHealPower loaded (re-export -> RfsChemStation)" )
