-- RfsBotOrdersCollect.lua — Milestone 3 Tote Collect job (small loose items → chests).
-- Pickup: (1) Survival hvs_loot harvestables  (2) single-shape dynamic loose parts.
-- Author: DemonsDen126
--
-- COLLECT ALLOWLIST (small items only — no bodies / large harvestables / chests):
--   Components & kits: component, multicomponent, circuitboard, glue, battery, gas,
--                      chemical, fertilizer, inkammo, glowstick, cableroll, extinguisher
--   Bags: soilbag
--   Seeds: banana, blueberry, orange, pineapple, carrot, redbeet, tomato, broccoli,
--          potato, cotton, pigmentflower, chili
--   Ores / resources: residueore, quartz, coralium, nimbolium, lemonium, sapphire,
--                     crystal (+ refined*), silica, mud, cotton, flower, beewax, ember,
--                     crudeoil, corn
-- Excluded on purpose: plantables (produce), steak/food, propane tanks, containers,
-- LostItems bags, trees/geysers/farmable harvestables, multi-shape creations.

RfsBotOrdersCollect = RfsBotOrdersCollect or {}

pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsBotPath.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsBotInventory.lua" )
end )

local CARRY_SLOTS = 8
local CARRY_MAX_STACK = 40
local PICKUPS_PER_TICK = 3
local DEPOSITS_PER_TICK = 4

-- Fallback UUIDs when Survival ITEMS / globals are unavailable at load time.
local FALLBACK = {
	-- components / kits
	obj_consumable_component = "5530e6a0-4748-4926-b134-50ca9ecb9dcf",
	obj_consumable_multicomponent = "b41de15e-a136-425a-a730-889b58cf4466",
	obj_resource_circuitboard = "f152e4df-bc40-44fb-8d20-3b3ff70cdfe3",
	obj_consumable_glue = "36335664-6e61-4d44-9876-54f9660a8565",
	obj_consumable_battery = "910a7f2c-52b0-46eb-8873-ad13255539af",
	obj_consumable_gas = "d4d68946-aa03-4b8f-b1af-96b81ad4e305",
	obj_consumable_chemical = "f74c2891-79a9-45e0-982e-4896651c2e25",
	obj_consumable_fertilizer = "ac0b5b0a-14e1-4b31-8944-0a351fbfcc67",
	obj_consumable_inkammo = "c7322cd1-3158-41d9-b15a-eff2f2f8d9f7",
	obj_consumable_glowstick = "3a3280e4-03b6-4a4d-9e02-e348478213c9",
	obj_consumables_cableroll = "48f39ccd-1013-4d54-b8ad-e0aebeb88867",
	obj_consumable_extinguisher = "d2fab7ef-21db-4681-a22a-cd4f278fc355",
	-- bags
	obj_consumable_soilbag = "9a3e478c-2224-44fa-887c-239965bd05ad",
	-- seeds
	obj_seed_banana = "22beade5-38ca-47b4-a2ee-32403f58a862",
	obj_seed_blueberry = "4b6d2bee-d0f1-4e56-96f0-d2596388cad2",
	obj_seed_orange = "bee966b0-b5e5-41da-b992-5d363ab85ae4",
	obj_seed_pineapple = "9edb6f7c-fb44-4348-a1c4-8afb41b92d8a",
	obj_seed_carrot = "9c82a525-8a8b-4483-9595-505aaa042486",
	obj_seed_redbeet = "64051718-a3f1-422b-bda3-277efa0c4545",
	obj_seed_tomato = "38e41fb5-dd50-4294-829d-a517f0282fed",
	obj_seed_broccoli = "1c6756ca-3a60-4dcb-a5d1-353edf818308",
	obj_seed_potato = "eb1ef696-5c05-4662-9e47-fe1e0875ff84",
	obj_seed_cotton = "93c27ab2-4930-4654-ba1c-bcfe35e966f6",
	obj_seed_pigmentflower = "c44b27da-88cf-4e17-b872-6236a1172688",
	obj_seed_chili = "8883e0ee-8a6e-423a-a4e0-583d9bf105bd",
	-- ores / resources
	obj_resource_residueore = "0f6d1667-ddf8-4ca9-b290-8bd3ec9b038b",
	obj_resource_quartz = "c108d189-87ff-41d1-8d61-667769924a34",
	obj_resource_coralium = "3be58cc4-04b4-455d-a9c3-8a8fd262b6d6",
	obj_resource_nimbolium = "903871bd-e71f-4681-ad56-8bf180fe4da9",
	obj_resource_lemonium = "c5444340-52d3-44ff-bd27-c1800dd8ea7e",
	obj_resource_sapphire = "b23f64dd-8182-4d73-90bf-6ccb9dd24d4d",
	obj_resource_crystal = "84fdb4ca-46cd-424b-b608-0998741941dc",
	obj_resource_refinedcoralium = "41db3e10-7b8f-4ff3-81f3-4f240f1f3cce",
	obj_resource_refinednimbolium = "d69139ee-5b7f-479a-b9c1-6549017a1ea1",
	obj_resource_refinedlemonium = "bd4b7d66-9d4b-433e-bff9-410cb5baafc3",
	obj_resource_refinedsapphire = "847af9bd-21ae-4d16-971f-5c8378e83f51",
	obj_resource_refinedcrystal = "a0fbc5ac-4e77-4119-b6e9-f3b6f8fbcb66",
	obj_resource_silica = "f554be5a-2012-4d2d-9a10-776d31aa1fd7",
	obj_resource_mud = "e28c88fc-bd6d-4b03-a799-c0d39f0a799e",
	obj_resource_cotton = "3440440b-d362-4473-aa03-b7c41e1fe7ad",
	obj_resource_flower = "c9396a42-67c3-4fa3-b682-31428ff9eced",
	obj_resource_beewax = "fcf0958c-084d-4854-9b1b-b06594b4262a",
	obj_resource_ember = "267e0c93-62e3-45ad-9470-a14035cb9ca4",
	obj_resource_crudeoil = "1147e59d-6940-42b4-840b-07f05054f5e0",
	obj_resource_corn = "fe8bfeba-850b-4827-9785-10e2468c9c23",
}

local CHEST_FALLBACK = {
	obj_container_chest = "ad35f7e6-af8f-40fa-aef4-77d827ac8a8a",
	obj_container_smallchest = "fcfae5e2-1df9-47d8-bb9a-30bec9b5b1f5",
	obj_container_tinychest = "7527cf2e-1705-4214-9d07-3dc374957e25",
	obj_container_XXL_chest = "9601f2ca-9552-48b0-afc1-b0f200461114",
}

local ALLOW_KEYS = {}
for k in pairs( FALLBACK ) do
	ALLOW_KEYS[#ALLOW_KEYS + 1] = k
end

local LOOT_HVS = {
	"97fe0cf2-0591-4e98-9beb-9186f4fd83c8", -- hvs_loot
}

local allowSet = nil -- map uuid-string → true
local chestSet = nil
local lootHvsSet = nil

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
	for _, name in ipairs( ALLOW_KEYS ) do
		local u = resolveNamed( name )
		local s = uuidStr( u )
		if s and s ~= "" and s ~= "00000000-0000-0000-0000-000000000000" then
			allowSet[s] = true
		end
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
end

function RfsBotOrdersCollect.isAllowlisted( uuid )
	if not allowSet then
		rebuildSets()
	end
	local s = uuidStr( uuid )
	return s ~= nil and allowSet[s] == true
end

function RfsBotOrdersCollect.allowlistNames()
	return ALLOW_KEYS
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

---------------------------------------------------------------------------
-- Find loot / chests
---------------------------------------------------------------------------

local function findLootHarvestables( world, homePos, radius, preferPos )
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
			local ok = false
			local uid = nil
			pcall( function()
				uid = hvs:getUuid()
			end )
			if uid and lootHvsSet[uuidStr( uid )] then
				local pub = nil
				pcall( function()
					pub = hvs.publicData
				end )
				if type( pub ) == "table" and not pub.harvested and pub.uuid and RfsBotOrdersCollect.isAllowlisted( pub.uuid ) then
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

local function findLooseShapes( homePos, radius, preferPos )
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
				-- Single-shape loose drops only (skip multi-shape creations / bodies).
				if type( shapes ) == "table" and #shapes == 1 then
					local shape = shapes[1]
					if shape and sm.exists( shape ) then
						local suid = nil
						pcall( function()
							suid = shape:getShapeUuid()
						end )
						if suid and RfsBotOrdersCollect.isAllowlisted( suid ) then
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

local function pickupOne( entry, container )
	if not entry or not container then
		return false
	end
	if type( RfsBotInventory ) == "table" and RfsBotInventory.isFull and RfsBotInventory.isFull( container ) then
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
		local ok = false
		if type( RfsBotInventory ) == "table" and RfsBotInventory.collect then
			ok = RfsBotInventory.collect( container, entry.uuid, entry.qty )
		end
		if not ok then
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
		local ok = false
		if type( RfsBotInventory ) == "table" and RfsBotInventory.collect then
			ok = RfsBotInventory.collect( container, entry.uuid, 1 )
		end
		if not ok then
			return false
		end
		pcall( function()
			shape:destroyShape()
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
	-- Try full amount, then peel by half until one fits (chest space limited).
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
-- Job tick for one tote ally
---------------------------------------------------------------------------

local function migrateCarryIntoContainer( info, container )
	local carry = type( info ) == "table" and info.rfsCarry
	if type( carry ) ~= "table" or #carry < 1 or not container then
		return
	end
	local i = 1
	while i <= #carry do
		local slot = carry[i]
		local qty = tonumber( slot and slot.qty ) or 0
		if qty < 1 or not slot.uuid then
			table.remove( carry, i )
		elseif type( RfsBotInventory ) == "table" and RfsBotInventory.collect
			and RfsBotInventory.collect( container, slot.uuid, qty ) then
			table.remove( carry, i )
		else
			i = i + 1
		end
	end
end

function RfsBotOrdersCollect.sv_tickAlly( unit, info, homeRec, radius )
	if not unit or not sm.exists( unit ) or type( info ) ~= "table" or not homeRec or not homeRec.pos then
		return
	end
	if not allowSet then
		rebuildSets()
	end
	local container = nil
	if type( RfsBotInventory ) == "table" and RfsBotInventory.sv_ensure then
		container = RfsBotInventory.sv_ensure( unit )
	end
	if not container then
		return
	end
	migrateCarryIntoContainer( info, container )
	local botPos = nil
	pcall( function()
		if unit.character and sm.exists( unit.character ) then
			botPos = unit.character.worldPosition
		end
	end )
	local world = botWorld( unit )
	local homePos = homeRec.pos
	local full = type( RfsBotInventory ) == "table" and RfsBotInventory.isFull and RfsBotInventory.isFull( container )
	local empty = type( RfsBotInventory ) == "table" and RfsBotInventory.isEmpty and RfsBotInventory.isEmpty( container )

	-- Prefer dump when inventory is full (blue gathered / green seed / other overflow).
	if full or not empty then
		if full then
			if type( RfsBotInventory ) == "table" and RfsBotInventory.sv_dumpToChests then
				RfsBotInventory.sv_dumpToChests( unit, info, homeRec, radius, botPos or homePos )
			end
			if type( RfsBotInventory ) == "table" and RfsBotInventory.isFull and RfsBotInventory.isFull( container ) then
				return
			end
		end
	end

	-- Pickup pass: walk to nearest loot/loose item in beacon range, then scoop.
	local picked = 0
	local loot = findLootHarvestables( world, homePos, radius, botPos or homePos )
	local loose = findLooseShapes( homePos, radius, botPos or homePos )
	local target = loot[1] or loose[1]
	if target and type( RfsBotPath ) == "table" and RfsBotPath.ensureNear then
		if not RfsBotPath.ensureNear( unit, info, target ) then
			return
		end
	end
	for _, entry in ipairs( loot ) do
		if picked >= PICKUPS_PER_TICK or ( type( RfsBotInventory ) == "table" and RfsBotInventory.isFull( container ) ) then
			break
		end
		if pickupOne( entry, container ) then
			picked = picked + 1
		end
	end
	if picked < PICKUPS_PER_TICK and not ( type( RfsBotInventory ) == "table" and RfsBotInventory.isFull( container ) ) then
		for _, entry in ipairs( loose ) do
			if picked >= PICKUPS_PER_TICK or ( type( RfsBotInventory ) == "table" and RfsBotInventory.isFull( container ) ) then
				break
			end
			if pickupOne( entry, container ) then
				picked = picked + 1
			end
		end
	end

	-- Idle dump if carrying anything and no more nearby pickups this tick.
	if picked == 0 and type( RfsBotInventory ) == "table" and not RfsBotInventory.isEmpty( container ) then
		RfsBotInventory.sv_dumpToChests( unit, info, homeRec, radius, botPos or homePos )
	elseif type( RfsBotPath ) == "table" and RfsBotPath.clearWalk then
		RfsBotPath.clearWalk( info )
	end
end

print( "[RFS] RfsBotOrdersCollect loaded (Tote Collect M3 → unit inventory → colored chests)" )
