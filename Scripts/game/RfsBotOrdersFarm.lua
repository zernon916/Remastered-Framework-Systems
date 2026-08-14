-- RfsBotOrdersFarm.lua — Milestone 2 Hay Farm job (seed plant / harvest / chest).
-- Haybot only. Never melee-destroys growing crops (uses MatureHarvestable bot harvest).
-- Author: DemonsDen126
--
-- Seed allowlist: Survival Planter.lua plantables (same 12 as sm.item.getPlantableUuids outdoor set).
-- See RfsFarming.getPlantableSeeds().

RfsBotOrdersFarm = RfsBotOrdersFarm or {}

pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsFarming.lua" )
end )

local CARRY_SLOTS = 8
local CARRY_MAX_STACK = 40
local ACTIONS_PER_TICK = 2
local SEED_WITHDRAW = 4 -- seeds pulled from chest per withdraw pass

local CHEST_FALLBACK = {
	obj_container_chest = "ad35f7e6-af8f-40fa-aef4-77d827ac8a8a",
	obj_container_smallchest = "fcfae5e2-1df9-47d8-bb9a-30bec9b5b1f5",
	obj_container_tinychest = "7527cf2e-1705-4214-9d07-3dc374957e25",
	obj_container_XXL_chest = "9601f2ca-9552-48b0-afc1-b0f200461114",
}

local chestSet = nil

local function uuidStr( u )
	if u == nil then
		return nil
	end
	return string.lower( tostring( u ) )
end

local function resolveNamed( name )
	local g = rawget( _G, name )
	if g ~= nil then
		return g
	end
	if type( ITEMS ) == "table" and ITEMS[name] ~= nil then
		return ITEMS[name]
	end
	local fb = CHEST_FALLBACK[name]
	if fb then
		local ok, u = pcall( sm.uuid.new, fb )
		if ok then
			return u
		end
	end
	return nil
end

local function rebuildChestSet()
	chestSet = {}
	for name in pairs( CHEST_FALLBACK ) do
		local u = resolveNamed( name )
		local s = uuidStr( u )
		if s then
			chestSet[s] = true
		end
	end
end

local function carryOf( info )
	if type( info ) ~= "table" then
		return nil
	end
	if type( info.rfsCarry ) ~= "table" then
		info.rfsCarry = {}
	end
	return info.rfsCarry
end

local function carryCount( carry )
	local n = 0
	for _, slot in ipairs( carry or {} ) do
		n = n + ( tonumber( slot.qty ) or 0 )
	end
	return n
end

local function carryFull( carry )
	return #( carry or {} ) >= CARRY_SLOTS or carryCount( carry ) >= CARRY_MAX_STACK
end

local function carryQty( carry, uuid )
	local s = uuidStr( uuid )
	local n = 0
	for _, slot in ipairs( carry or {} ) do
		if uuidStr( slot.uuid ) == s then
			n = n + ( tonumber( slot.qty ) or 0 )
		end
	end
	return n
end

local function carryAdd( carry, uuid, qty )
	qty = math.floor( tonumber( qty ) or 0 )
	if qty < 1 or not uuid then
		return false
	end
	local s = uuidStr( uuid )
	for _, slot in ipairs( carry ) do
		if uuidStr( slot.uuid ) == s then
			slot.qty = ( tonumber( slot.qty ) or 0 ) + qty
			return true
		end
	end
	if #carry >= CARRY_SLOTS then
		return false
	end
	carry[#carry + 1] = { uuid = uuid, qty = qty }
	return true
end

local function carryTake( carry, uuid, qty )
	qty = math.floor( tonumber( qty ) or 0 )
	if qty < 1 or not uuid then
		return 0
	end
	local s = uuidStr( uuid )
	local taken = 0
	local i = 1
	while i <= #carry and taken < qty do
		local slot = carry[i]
		if uuidStr( slot.uuid ) == s then
			local have = tonumber( slot.qty ) or 0
			local need = qty - taken
			local n = math.min( have, need )
			slot.qty = have - n
			taken = taken + n
			if slot.qty <= 0 then
				table.remove( carry, i )
			else
				i = i + 1
			end
		else
			i = i + 1
		end
	end
	return taken
end

local function inRadius( pos, center, radius )
	if not pos or not center or not radius then
		return false
	end
	return ( pos - center ):length2() <= ( radius * radius )
end

local function botWorld( unit )
	local world = nil
	pcall( function()
		if unit and unit.character and sm.exists( unit.character ) then
			world = unit.character:getWorld()
		end
	end )
	return world
end

local function botPosOf( unit )
	local pos = nil
	pcall( function()
		if unit and unit.character and sm.exists( unit.character ) then
			pos = unit.character.worldPosition
		end
	end )
	return pos
end

local function resolveSeedUuid( order )
	if type( RfsFarming ) == "table" and RfsFarming.resolveSeedUuid then
		return RfsFarming.resolveSeedUuid( order and order.seedUuid )
	end
	return order and order.seedUuid or nil
end

---------------------------------------------------------------------------
-- Chests / harvestables in job radius
---------------------------------------------------------------------------

local function findChests( homePos, radius, preferPos )
	local out = {}
	if not homePos or not radius then
		return out
	end
	if not chestSet then
		rebuildChestSet()
	end
	local bodies = nil
	pcall( function()
		bodies = sm.body.getAllBodies()
	end )
	if type( bodies ) ~= "table" then
		return out
	end
	for _, body in ipairs( bodies ) do
		if body and sm.exists( body ) then
			local shapes = nil
			pcall( function()
				shapes = body:getShapes()
			end )
			if type( shapes ) == "table" then
				for _, shape in ipairs( shapes ) do
					if shape and sm.exists( shape ) then
						local suid = nil
						pcall( function()
							suid = shape:getShapeUuid()
						end )
						if suid and chestSet[uuidStr( suid )] then
							local ia = nil
							pcall( function()
								ia = shape:getInteractable()
							end )
							local container = nil
							if ia and sm.exists( ia ) then
								pcall( function()
									container = ia:getContainer( 0 )
								end )
							end
							if container and sm.exists( container ) then
								local pos = nil
								pcall( function()
									pos = shape.worldPosition
								end )
								if pos and inRadius( pos, homePos, radius ) then
									local d2 = preferPos and ( pos - preferPos ):length2() or 0
									out[#out + 1] = { container = container, pos = pos, d2 = d2 }
								end
							end
						end
					end
				end
			end
		end
	end
	table.sort( out, function( a, b )
		return ( a.d2 or 0 ) < ( b.d2 or 0 )
	end )
	return out
end

local function findSoil( world, homePos, radius, preferPos )
	local out = {}
	if type( RfsFarming ) ~= "table" or not RfsFarming.isSoilUuid then
		return out
	end
	local list = nil
	pcall( function()
		if world ~= nil then
			list = sm.harvestable.getAllHarvestables( world )
		else
			list = sm.harvestable.getAllHarvestables()
		end
	end )
	if type( list ) ~= "table" then
		return out
	end
	for _, hvs in pairs( list ) do
		if hvs and sm.exists( hvs ) then
			local uid = nil
			pcall( function()
				uid = hvs:getUuid()
			end )
			if uid and RfsFarming.isSoilUuid( uid ) then
				local pos = nil
				pcall( function()
					pos = hvs:getPosition()
				end )
				if pos and inRadius( pos, homePos, radius ) then
					local d2 = preferPos and ( pos - preferPos ):length2() or 0
					out[#out + 1] = { hvs = hvs, pos = pos, d2 = d2 }
				end
			end
		end
	end
	table.sort( out, function( a, b )
		return ( a.d2 or 0 ) < ( b.d2 or 0 )
	end )
	return out
end

local function findMature( world, homePos, radius, preferPos )
	local out = {}
	if type( RfsFarming ) ~= "table" or not RfsFarming.isMatureUuid then
		return out
	end
	local list = nil
	pcall( function()
		if world ~= nil then
			list = sm.harvestable.getAllHarvestables( world )
		else
			list = sm.harvestable.getAllHarvestables()
		end
	end )
	if type( list ) ~= "table" then
		return out
	end
	for _, hvs in pairs( list ) do
		if hvs and sm.exists( hvs ) then
			local uid = nil
			pcall( function()
				uid = hvs:getUuid()
			end )
			if uid and RfsFarming.isMatureUuid( uid ) then
				local pub = nil
				pcall( function()
					pub = hvs.publicData
				end )
				if type( pub ) == "table" and pub.harvested then
					-- skip
				else
					local pos = nil
					pcall( function()
						pos = hvs:getPosition()
					end )
					if pos and inRadius( pos, homePos, radius ) then
						local d2 = preferPos and ( pos - preferPos ):length2() or 0
						out[#out + 1] = { hvs = hvs, pos = pos, d2 = d2 }
					end
				end
			end
		end
	end
	table.sort( out, function( a, b )
		return ( a.d2 or 0 ) < ( b.d2 or 0 )
	end )
	return out
end

---------------------------------------------------------------------------
-- Container spend / deposit
---------------------------------------------------------------------------

local function trySpend( container, uuid, qty )
	local ok = false
	pcall( function()
		if sm.container.beginTransaction() then
			local n = sm.container.spend( container, uuid, qty, false )
			if n == qty then
				ok = sm.container.endTransaction() and true or false
				if not ok then
					sm.container.abortTransaction()
				end
			else
				sm.container.abortTransaction()
			end
		end
	end )
	if not ok then
		pcall( function()
			ok = sm.container.spend( container, uuid, qty, true ) and true or false
		end )
	end
	return ok
end

local function tryCollect( container, uuid, qty )
	local ok = false
	pcall( function()
		if sm.container.beginTransaction() then
			ok = sm.container.collect( container, uuid, qty, true ) and true or false
			if ok then
				sm.container.endTransaction()
			else
				sm.container.abortTransaction()
			end
		end
	end )
	return ok
end

local function withdrawSeeds( chests, seedUuid, carry, want )
	want = math.floor( tonumber( want ) or 1 )
	if want < 1 or not seedUuid or carryFull( carry ) then
		return 0
	end
	local got = 0
	for _, row in ipairs( chests or {} ) do
		if got >= want or carryFull( carry ) then
			break
		end
		local c = row.container
		if c and sm.exists( c ) then
			local have = 0
			pcall( function()
				have = sm.container.totalQuantity( c, seedUuid ) or 0
			end )
			local take = math.min( have, want - got )
			while take >= 1 do
				if trySpend( c, seedUuid, take ) then
					if carryAdd( carry, seedUuid, take ) then
						got = got + take
					else
						-- Refund if buffer rejected.
						pcall( function()
							sm.container.collect( c, seedUuid, take, true )
						end )
					end
					break
				end
				if take == 1 then
					break
				end
				take = math.floor( take / 2 )
			end
		end
	end
	return got
end

local function depositCarry( carry, chests )
	if type( carry ) ~= "table" or #carry < 1 or type( chests ) ~= "table" or #chests < 1 then
		return 0
	end
	local moved = 0
	local i = 1
	while i <= #carry and moved < ACTIONS_PER_TICK do
		local slot = carry[i]
		local remaining = tonumber( slot.qty ) or 0
		if remaining < 1 then
			table.remove( carry, i )
		else
			local deposited = 0
			for _, row in ipairs( chests ) do
				if remaining < 1 then
					break
				end
				local n = remaining
				while n >= 1 do
					if tryCollect( row.container, slot.uuid, n ) then
						deposited = deposited + n
						remaining = remaining - n
						moved = moved + 1
						break
					end
					if n == 1 then
						break
					end
					n = math.floor( n / 2 )
				end
			end
			slot.qty = remaining
			if remaining < 1 then
				table.remove( carry, i )
			else
				i = i + 1
			end
			if deposited < 1 then
				break
			end
		end
	end
	return moved
end

---------------------------------------------------------------------------
-- Job tick
---------------------------------------------------------------------------

function RfsBotOrdersFarm.sv_tickAlly( unit, info, homeRec, radius )
	if not unit or not sm.exists( unit ) or type( info ) ~= "table" or not homeRec or not homeRec.pos then
		return
	end
	if type( RfsFarming ) == "table" and RfsFarming.ensureBotFarmHooks then
		pcall( RfsFarming.ensureBotFarmHooks )
	end

	local order = info.order or info.rfsOrder or {}
	local seedUuid = resolveSeedUuid( order )
	if not seedUuid then
		return
	end
	-- Persist resolved seed so GUI / reloads stay stable.
	if order.seedUuid == nil or uuidStr( order.seedUuid ) ~= uuidStr( seedUuid ) then
		order.seedUuid = tostring( seedUuid )
		info.order = order
		info.rfsOrder = order
	end

	local carry = carryOf( info )
	local homePos = homeRec.pos
	local prefer = botPosOf( unit ) or homePos
	local world = botWorld( unit )
	local chests = findChests( homePos, radius, prefer )

	-- 1) Deposit when buffer is busy / full (harvest produce + leftover seeds).
	if carryFull( carry ) or ( #carry > 0 and carryCount( carry ) >= math.floor( CARRY_MAX_STACK * 0.6 ) ) then
		depositCarry( carry, chests )
		if carryFull( carry ) then
			return
		end
	end

	local actions = 0

	-- 2) Harvest mature outdoor crops in radius (player-loot rules via bot event — no melee smash).
	if not carryFull( carry ) then
		local mature = findMature( world, homePos, radius, prefer )
		for _, row in ipairs( mature ) do
			if actions >= ACTIONS_PER_TICK or carryFull( carry ) then
				break
			end
			if type( RfsFarming ) == "table" and RfsFarming.sv_botHarvest then
				local ok, loot = pcall( RfsFarming.sv_botHarvest, row.hvs )
				if ok and type( loot ) == "table" then
					for _, drop in ipairs( loot ) do
						if drop and drop.uuid and ( tonumber( drop.qty ) or 0 ) > 0 then
							carryAdd( carry, drop.uuid, drop.qty )
						end
					end
					actions = actions + 1
				end
			end
		end
	end

	-- 3) Plant selected seed on soil.
	if actions < ACTIONS_PER_TICK and carryQty( carry, seedUuid ) >= 1 then
		local soils = findSoil( world, homePos, radius, prefer )
		for _, row in ipairs( soils ) do
			if actions >= ACTIONS_PER_TICK then
				break
			end
			if carryTake( carry, seedUuid, 1 ) == 1 then
				local planted = false
				if type( RfsFarming ) == "table" and RfsFarming.sv_botPlant then
					local ok, did = pcall( RfsFarming.sv_botPlant, row.hvs, seedUuid )
					planted = ok and did and true or false
				end
				if planted then
					actions = actions + 1
				else
					carryAdd( carry, seedUuid, 1 )
				end
			end
		end
	end

	-- 4) Withdraw seeds from chests when buffer has none.
	if actions < ACTIONS_PER_TICK and carryQty( carry, seedUuid ) < 1 and not carryFull( carry ) then
		local got = withdrawSeeds( chests, seedUuid, carry, SEED_WITHDRAW )
		if got > 0 then
			actions = actions + 1
		end
	end

	-- 5) Idle deposit leftovers.
	if actions == 0 and #carry > 0 then
		depositCarry( carry, chests )
	end
end

-- Wire into RfsBotOrders.sv_think hook.
function RfsBotOrdersFarm.install()
	if type( RfsBotOrders ) ~= "table" then
		return false
	end
	RfsBotOrders.farmModeEnabled = true
	RfsBotOrders.sv_tickFarmAlly = RfsBotOrdersFarm.sv_tickAlly
	return true
end

RfsBotOrdersFarm.install()

print( "[RFS] RfsBotOrdersFarm loaded (Hay Farm M2)" )
