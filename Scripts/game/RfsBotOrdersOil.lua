-- RfsBotOrdersOil.lua — Milestone 4 Waterbot Collect Oil job.
-- Pickup: oil geyser harvestables + crudeoil loot/loose parts → chests.
-- Search radius may be 1.5× (perm-infect); deposit always uses base beacon range.
-- Author: DemonsDen126
--
-- OIL ALLOWLIST:
--   obj_resource_crudeoil (loose shapes + loot contents)
--   Mature oil geysers (hvs_farmables_oilgeyser) → crudeoil into carry, leave growing
-- Excluded: oil buckets (tools), growing geysers, gas cans, chemical buckets.

RfsBotOrdersOil = RfsBotOrdersOil or {}

pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsBotPath.lua" )
end )

local CARRY_SLOTS = 8
local CARRY_MAX_STACK = 40
local PICKUPS_PER_TICK = 2
local DEPOSITS_PER_TICK = 4
local GEYSER_QTY_MIN = 1
local GEYSER_QTY_MAX = 4

local FALLBACK = {
	obj_resource_crudeoil = "1147e59d-6940-42b4-840b-07f05054f5e0",
}

local CHEST_FALLBACK = {
	obj_container_chest = "ad35f7e6-af8f-40fa-aef4-77d827ac8a8a",
	obj_container_smallchest = "fcfae5e2-1df9-47d8-bb9a-30bec9b5b1f5",
	obj_container_tinychest = "7527cf2e-1705-4214-9d07-3dc374957e25",
	obj_container_XXL_chest = "9601f2ca-9552-48b0-afc1-b0f200461114",
}

-- Mature oil geyser (player interact harvests crudeoil).
local OIL_GEYSER_FALLBACK = "2ab8edca-9cfe-4b1c-9f57-5092f94ea890"
local GROWING_GEYSER_FALLBACK = "b6a26689-d803-49cc-a6e8-7f2b66dfb54d"
local LOOT_HVS = {
	"97fe0cf2-0591-4e98-9beb-9186f4fd83c8", -- hvs_loot
}

local allowSet = nil
local chestSet = nil
local lootHvsSet = nil
local geyserSet = nil
local crudeUuid = nil
local growingGeyserUuid = nil

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
	local fb = FALLBACK[name] or CHEST_FALLBACK[name]
	if fb then
		local ok, u = pcall( sm.uuid.new, fb )
		if ok then
			return u
		end
	end
	return nil
end

local function rebuildSets()
	allowSet = {}
	crudeUuid = resolveNamed( "obj_resource_crudeoil" )
	local cs = uuidStr( crudeUuid )
	if cs then
		allowSet[cs] = true
	end

	chestSet = {}
	for name in pairs( CHEST_FALLBACK ) do
		local u = resolveNamed( name )
		local s = uuidStr( u )
		if s then
			chestSet[s] = true
		end
	end

	lootHvsSet = {}
	local hvs = rawget( _G, "hvs_loot" )
	if hvs then
		lootHvsSet[uuidStr( hvs )] = true
	end
	for _, s in ipairs( LOOT_HVS ) do
		lootHvsSet[string.lower( s )] = true
	end

	geyserSet = {}
	local geyser = rawget( _G, "hvs_farmables_oilgeyser" )
	if not geyser then
		local ok, u = pcall( sm.uuid.new, OIL_GEYSER_FALLBACK )
		if ok then
			geyser = u
		end
	end
	if geyser then
		geyserSet[uuidStr( geyser )] = true
	end

	growingGeyserUuid = rawget( _G, "hvs_farmables_growing_oilgeyser" )
	if not growingGeyserUuid then
		local ok, u = pcall( sm.uuid.new, GROWING_GEYSER_FALLBACK )
		if ok then
			growingGeyserUuid = u
		end
	end
end

function RfsBotOrdersOil.isAllowlisted( uuid )
	if not allowSet then
		rebuildSets()
	end
	local s = uuidStr( uuid )
	return s ~= nil and allowSet[s] == true
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

local function inRadius( pos, center, radius )
	if not pos or not center or not radius then
		return false
	end
	local d2 = ( pos - center ):length2()
	return d2 <= ( radius * radius )
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

local function geyserQty()
	-- Mirror OilGeyser randomStackAmount(1,2,4) without depending on Survival util.
	local roll = math.random()
	if roll < 0.45 then
		return GEYSER_QTY_MIN
	end
	if roll < 0.80 then
		return 2
	end
	return GEYSER_QTY_MAX
end

---------------------------------------------------------------------------
-- Find oil sources / chests
---------------------------------------------------------------------------

local function findOilLootHarvestables( world, homePos, radius, preferPos )
	local out = {}
	if not homePos or not radius then
		return out
	end
	if not allowSet then
		rebuildSets()
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
			if uid and lootHvsSet[uuidStr( uid )] then
				local pub = nil
				pcall( function()
					pub = hvs.publicData
				end )
				if type( pub ) == "table" and not pub.harvested and pub.uuid and RfsBotOrdersOil.isAllowlisted( pub.uuid ) then
					local pos = nil
					pcall( function()
						pos = hvs:getPosition()
					end )
					if pos and inRadius( pos, homePos, radius ) then
						local d2 = preferPos and ( pos - preferPos ):length2() or 0
						out[#out + 1] = {
							kind = "hvs",
							hvs = hvs,
							uuid = pub.uuid,
							qty = math.max( 1, tonumber( pub.quantity ) or 1 ),
							pos = pos,
							d2 = d2,
						}
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

local function findOilGeysers( world, homePos, radius, preferPos )
	local out = {}
	if not homePos or not radius then
		return out
	end
	if not geyserSet then
		rebuildSets()
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
			if uid and geyserSet[uuidStr( uid )] then
				local harvested = false
				pcall( function()
					local pub = hvs.publicData
					if type( pub ) == "table" and pub.harvested then
						harvested = true
					end
				end )
				if not harvested then
					local pos = nil
					pcall( function()
						pos = hvs.worldPosition or hvs:getPosition()
					end )
					if pos and inRadius( pos, homePos, radius ) then
						local d2 = preferPos and ( pos - preferPos ):length2() or 0
						out[#out + 1] = {
							kind = "geyser",
							hvs = hvs,
							uuid = crudeUuid,
							qty = geyserQty(),
							pos = pos,
							d2 = d2,
						}
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

local function findLooseOilShapes( homePos, radius, preferPos )
	local out = {}
	if not homePos or not radius then
		return out
	end
	if not allowSet then
		rebuildSets()
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
			local dyn = false
			pcall( function()
				dyn = body:isDynamic()
			end )
			if dyn then
				local shapes = nil
				pcall( function()
					shapes = body:getShapes()
				end )
				if type( shapes ) == "table" and #shapes == 1 then
					local shape = shapes[1]
					if shape and sm.exists( shape ) then
						local suid = nil
						pcall( function()
							suid = shape:getShapeUuid()
						end )
						if suid and RfsBotOrdersOil.isAllowlisted( suid ) then
							local pos = nil
							pcall( function()
								pos = shape.worldPosition or body.worldPosition
							end )
							if pos and inRadius( pos, homePos, radius ) then
								local d2 = preferPos and ( pos - preferPos ):length2() or 0
								out[#out + 1] = {
									kind = "shape",
									shape = shape,
									uuid = suid,
									qty = 1,
									pos = pos,
									d2 = d2,
								}
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

local function findChests( homePos, radius, preferPos, role, homeRec )
	if type( RfsBotPath ) == "table" and type( RfsBotPath.findChests ) == "function" then
		return RfsBotPath.findChests( homePos, radius, preferPos, role or "drop", homeRec )
	end
	local out = {}
	if not homePos or not radius then
		return out
	end
	if not chestSet then
		rebuildSets()
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
									out[#out + 1] = {
										container = container,
										pos = pos,
										d2 = d2,
									}
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

---------------------------------------------------------------------------
-- Pickup / deposit
---------------------------------------------------------------------------

local function pickupOne( entry, carry )
	if not entry or carryFull( carry ) then
		return false
	end
	if entry.kind == "hvs" then
		local hvs = entry.hvs
		if not hvs or not sm.exists( hvs ) then
			return false
		end
		local pub = nil
		pcall( function()
			pub = hvs.publicData
		end )
		if type( pub ) == "table" and pub.harvested then
			return false
		end
		if not carryAdd( carry, entry.uuid, entry.qty ) then
			return false
		end
		pcall( function()
			if type( pub ) == "table" then
				pub.harvested = true
			end
		end )
		pcall( function()
			hvs:destroy()
		end )
		return true
	end
	if entry.kind == "shape" then
		local shape = entry.shape
		if not shape or not sm.exists( shape ) then
			return false
		end
		if not carryAdd( carry, entry.uuid, 1 ) then
			return false
		end
		pcall( function()
			shape:destroyShape()
		end )
		return true
	end
	if entry.kind == "geyser" then
		local hvs = entry.hvs
		if not hvs or not sm.exists( hvs ) or not crudeUuid then
			return false
		end
		local qty = math.max( 1, tonumber( entry.qty ) or geyserQty() )
		if not carryAdd( carry, crudeUuid, qty ) then
			return false
		end
		local pos, rot = nil, nil
		pcall( function()
			pos = hvs.worldPosition or hvs:getPosition()
			rot = hvs.worldRotation or hvs:getRotation()
		end )
		pcall( function()
			local pub = hvs.publicData
			if type( pub ) == "table" then
				pub.harvested = true
			end
		end )
		pcall( function()
			sm.effect.playEffect( "Oilgeyser - Picked", pos )
		end )
		-- Leave a growing geyser (matches Survival OilGeyser.sv_n_harvest).
		if growingGeyserUuid and pos then
			pcall( function()
				sm.harvestable.createHarvestable( growingGeyserUuid, pos, rot )
			end )
		end
		pcall( function()
			sm.harvestable.destroy( hvs )
		end )
		pcall( function()
			if sm.exists( hvs ) then
				hvs:destroy()
			end
		end )
		return true
	end
	return false
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

local function depositInto( container, uuid, qty )
	qty = math.floor( tonumber( qty ) or 0 )
	if not container or not sm.exists( container ) or not uuid or qty < 1 then
		return 0
	end
	local n = qty
	while n >= 1 do
		if tryCollect( container, uuid, n ) then
			return n
		end
		if n == 1 then
			return 0
		end
		n = math.floor( n / 2 )
	end
	return 0
end

local function depositCarry( carry, chests )
	if type( carry ) ~= "table" or #carry < 1 or type( chests ) ~= "table" or #chests < 1 then
		return 0
	end
	local moved = 0
	local i = 1
	while i <= #carry and moved < DEPOSITS_PER_TICK do
		local slot = carry[i]
		local remaining = tonumber( slot.qty ) or 0
		if remaining < 1 or not slot.uuid then
			table.remove( carry, i )
		else
			local progress = false
			for _, chest in ipairs( chests ) do
				while remaining > 0 and moved < DEPOSITS_PER_TICK do
					local n = depositInto( chest.container, slot.uuid, remaining )
					if n < 1 then
						break
					end
					remaining = remaining - n
					moved = moved + 1
					progress = true
				end
				if remaining < 1 or moved >= DEPOSITS_PER_TICK then
					break
				end
			end
			slot.qty = remaining
			if remaining < 1 then
				table.remove( carry, i )
			else
				i = i + 1
				if not progress then
					break
				end
			end
		end
	end
	return moved
end

---------------------------------------------------------------------------
-- Job tick for one waterbot ally
-- searchRadius: may be 1.5× for perm-infect; depositRadius: always beacon tier range
---------------------------------------------------------------------------

function RfsBotOrdersOil.sv_tickAlly( unit, info, homeRec, searchRadius, depositRadius )
	if not unit or not sm.exists( unit ) or type( info ) ~= "table" or not homeRec or not homeRec.pos then
		return
	end
	if not allowSet then
		rebuildSets()
	end
	depositRadius = tonumber( depositRadius ) or tonumber( homeRec.range ) or 16
	searchRadius = tonumber( searchRadius ) or depositRadius
	local carry = carryOf( info )
	local botPos = nil
	pcall( function()
		if unit.character and sm.exists( unit.character ) then
			botPos = unit.character.worldPosition
		end
	end )
	local world = botWorld( unit )
	local homePos = homeRec.pos
	local prefer = botPos or homePos

	-- Prefer deposit when buffer is getting full (chests only in base beacon range).
	if carryFull( carry ) or ( #carry > 0 and carryCount( carry ) >= math.floor( CARRY_MAX_STACK * 0.75 ) ) then
		local chests = findChests( homePos, depositRadius, prefer, "produce", homeRec )
		if type( RfsBotPath ) == "table" and RfsBotPath.ensureNear and not RfsBotPath.ensureNear( unit, info, chests[1] ) then
			return
		end
		depositCarry( carry, chests )
		if carryFull( carry ) then
			return
		end
	end

	local picked = 0
	-- Geysers first (world oil nodes), then crudeoil loot bags, then loose crudeoil.
	local geysers = findOilGeysers( world, homePos, searchRadius, prefer )
	for _, entry in ipairs( geysers ) do
		if picked >= PICKUPS_PER_TICK or carryFull( carry ) then
			break
		end
		if pickupOne( entry, carry ) then
			picked = picked + 1
		end
	end
	if picked < PICKUPS_PER_TICK and not carryFull( carry ) then
		local loot = findOilLootHarvestables( world, homePos, searchRadius, prefer )
		for _, entry in ipairs( loot ) do
			if picked >= PICKUPS_PER_TICK or carryFull( carry ) then
				break
			end
			if pickupOne( entry, carry ) then
				picked = picked + 1
			end
		end
	end
	if picked < PICKUPS_PER_TICK and not carryFull( carry ) then
		local loose = findLooseOilShapes( homePos, searchRadius, prefer )
		for _, entry in ipairs( loose ) do
			if picked >= PICKUPS_PER_TICK or carryFull( carry ) then
				break
			end
			if pickupOne( entry, carry ) then
				picked = picked + 1
			end
		end
	end

	if #carry > 0 and picked == 0 then
		local chests = findChests( homePos, depositRadius, prefer, "produce", homeRec )
		if type( RfsBotPath ) == "table" and RfsBotPath.ensureNear and not RfsBotPath.ensureNear( unit, info, chests[1] ) then
			return
		end
		depositCarry( carry, chests )
	elseif type( RfsBotPath ) == "table" and RfsBotPath.clearWalk then
		RfsBotPath.clearWalk( info )
	end
end

print( "[RFS] RfsBotOrdersOil loaded (Waterbot Collect Oil M4)" )
