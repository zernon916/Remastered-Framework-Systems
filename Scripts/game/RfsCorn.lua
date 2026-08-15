-- RfsCorn.lua — corn stack quantity helpers for Recipe Framework Survival
-- Author: DemonsDen126
-- Corn force-build uses the same itemStack path as seeds. Qty is
-- shape.stackedAmount so Wocs can eat the whole stack at once.

RfsCorn = RfsCorn or {}

function RfsCorn.getShapeQty( shape )
	if not shape or not sm.exists( shape ) then
		return 1
	end
	local qty = 1
	pcall( function()
		if type( shape.stackedAmount ) == "number" and shape.stackedAmount > 0 then
			qty = math.floor( shape.stackedAmount )
		end
	end )
	if qty <= 1 then
		pcall( function()
			local ia = shape:getInteractable()
			if ia and sm.exists( ia ) then
				local pd = ia:getPublicData()
				if type( pd ) == "table" and type( pd.rfsCornQty ) == "number" and pd.rfsCornQty > 0 then
					qty = math.floor( pd.rfsCornQty )
				end
			end
		end )
	end
	if qty <= 1 then
		pcall( function()
			local map = _G.g_rfsCornQtyById
			local id = shape.id
			if map and id ~= nil and type( map[id] ) == "number" and map[id] > 0 then
				qty = math.floor( map[id] )
			end
		end )
	end
	return math.max( 1, qty )
end

function RfsCorn.consumeShapeQty( shape )
	local qty = RfsCorn.getShapeQty( shape )
	pcall( function()
		local map = _G.g_rfsCornQtyById
		local id = shape.id
		if map and id ~= nil then
			map[id] = nil
		end
	end )
	return math.max( 1, qty )
end
