-- RfsHackV1Fence.lua
-- VOLATILE: leave powered beacon range → 2s unhack telegraph. Range from beacon tier + modules.

RfsHackV1Fence = RfsHackV1Fence or {}

function RfsHackV1Fence.check( ctx )
	if type( ctx ) ~= "table" or type( RfsHackV1Registry ) ~= "table" then
		return
	end
	local rows = RfsHackV1Registry.listAllies( ctx.key, ctx.world )
	local pos = ctx.pos
	local maxD2 = tonumber( ctx.maxD2 ) or 0
	local powered = ctx.powered and true or false
	for i = 1, #rows do
		local row = rows[i]
		if row and row.unit and row.character and sm.exists( row.character ) then
			local leave = not powered
			if not leave and pos then
				leave = ( row.character.worldPosition - pos ):length2() > maxD2
			end
			if leave and type( RfsHackV1Unhack ) == "table" and RfsHackV1Unhack.begin then
				RfsHackV1Unhack.begin( row.unit, { beaconKey = ctx.key, world = ctx.world } )
			end
		end
	end
end

print( "[RFS] RfsHackV1Fence loaded (full device range)" )
