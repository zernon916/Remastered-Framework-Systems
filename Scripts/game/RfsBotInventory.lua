-- RfsBotInventory.lua
-- VOLATILE: ally unit containers + U/tinker-open. Hooked after hijack convert.
-- Does not change hijack HP / damage / spend / Orders E-open on the beacon.
-- Survival units support unit:addContainer (see BabyWocUnit). Tinker on the bot
-- opens the same chest GUI as a vanilla container. E on the bot is rename.

RfsBotInventory = RfsBotInventory or {}

RfsBotInventory.INDEX = 0

-- Totebot 3, Hay 1, Farmbot 15, Tapebot / explosive / bubble 1, Woc 1, Seedbot 10.
local SLOTS_BY_KIND = {
	tote = 3,
	water = 3,
	hay = 1,
	farm = 15,
	tape = 1,
	bubble = 1,
	woc = 1,
	seed = 10,
}

local function uuidStr( u )
	if u == nil then
		return nil
	end
	return string.lower( tostring( u ) )
end

local function charTypeOf( unit )
	local t = nil
	pcall( function()
		local char = unit and unit.character
		if char and sm.exists( char ) then
			t = tostring( char:getCharacterType() )
		end
	end )
	return t
end

local function kindOf( unit )
	local typeStr = charTypeOf( unit )
	if type( RfsBotHijack ) == "table" and type( RfsBotHijack.shortTypeName ) == "function" then
		local name = nil
		pcall( function()
			name = RfsBotHijack.shortTypeName( typeStr )
		end )
		name = string.lower( tostring( name or "" ) )
		if name == "tote" then return "tote" end
		if name == "water" then return "water" end
		if name == "hay" then return "hay" end
		if name == "farm" then return "farm" end
		if name == "tape" then return "tape" end
		if name == "bubble" then return "bubble" end
		if name == "seed" then return "seed" end
		if name == "woc" then return "woc" end
	end
	local lower = string.lower( tostring( typeStr or "" ) )
	if string.find( lower, "farmbot", 1, true ) then return "farm" end
	if string.find( lower, "hay", 1, true ) then return "hay" end
	if string.find( lower, "seed", 1, true ) then return "seed" end
	if string.find( lower, "woc", 1, true ) then return "woc" end
	if string.find( lower, "tape", 1, true ) and string.find( lower, "green", 1, true ) then
		return "bubble"
	end
	if string.find( lower, "tape", 1, true ) then return "tape" end
	if string.find( lower, "water", 1, true ) then return "water" end
	if string.find( lower, "tote", 1, true ) then return "tote" end
	return "tape"
end

function RfsBotInventory.slotsFor( unit )
	local kind = kindOf( unit )
	return SLOTS_BY_KIND[kind] or 1
end

function RfsBotInventory.get( unit )
	if not unit then
		return nil
	end
	local c = nil
	pcall( function()
		if sm.exists( unit ) then
			c = unit:getContainer( RfsBotInventory.INDEX )
		end
	end )
	if c and sm.exists( c ) then
		return c
	end
	return nil
end

-- Server: create the unit container once after convert. Safe to call often.
function RfsBotInventory.sv_ensure( unit )
	if not unit then
		return nil
	end
	local exists = false
	pcall( function()
		exists = sm.exists( unit )
	end )
	if not exists then
		return nil
	end
	local c = RfsBotInventory.get( unit )
	if c then
		return c
	end
	local slots = RfsBotInventory.slotsFor( unit )
	pcall( function()
		c = unit:addContainer( RfsBotInventory.INDEX, slots )
	end )
	if c and sm.exists( c ) then
		return c
	end
	return RfsBotInventory.get( unit )
end

local function containerSize( c )
	local n = nil
	pcall( function() n = c.size end )
	if type( n ) == "number" then
		return n
	end
	pcall( function() n = c:getSize() end )
	if type( n ) == "number" then
		return n
	end
	pcall( function() n = sm.container.getSize( c ) end )
	if type( n ) == "number" then
		return n
	end
	return 0
end

local function slotItem( c, index )
	local item = nil
	pcall( function()
		item = c:getItem( index )
	end )
	if type( item ) ~= "table" then
		pcall( function()
			item = sm.container.getItem( c, index )
		end )
	end
	if type( item ) ~= "table" then
		return nil, 0
	end
	local uuid = item.uuid
	local qty = tonumber( item.quantity ) or 0
	if not uuid or qty < 1 then
		return nil, 0
	end
	local nilUuid = nil
	pcall( function()
		nilUuid = sm.uuid.getNil()
	end )
	if nilUuid and uuid == nilUuid then
		return nil, 0
	end
	return uuid, qty
end

function RfsBotInventory.isEmpty( c )
	if not c or not sm.exists( c ) then
		return true
	end
	local empty = true
	pcall( function()
		empty = c:isEmpty() and true or false
	end )
	if empty == false then
		return false
	end
	local size = containerSize( c )
	for i = 0, size - 1 do
		local uuid, qty = slotItem( c, i )
		if uuid and qty > 0 then
			return false
		end
	end
	return true
end

-- True when every slot has a stack (Collect should dump). Partial stacks still count as occupied.
function RfsBotInventory.isFull( c )
	if not c or not sm.exists( c ) then
		return true
	end
	local size = containerSize( c )
	if size < 1 then
		return true
	end
	for i = 0, size - 1 do
		local uuid, qty = slotItem( c, i )
		if not uuid or qty < 1 then
			return false
		end
	end
	return true
end

function RfsBotInventory.collect( c, uuid, qty )
	qty = math.floor( tonumber( qty ) or 0 )
	if not c or not sm.exists( c ) or not uuid or qty < 1 then
		return false
	end
	local ok = false
	pcall( function()
		if sm.container.beginTransaction() then
			ok = sm.container.collect( c, uuid, qty, true ) and true or false
			if ok then
				sm.container.endTransaction()
			else
				sm.container.abortTransaction()
			end
		end
	end )
	return ok
end

function RfsBotInventory.spend( c, uuid, qty )
	qty = math.floor( tonumber( qty ) or 0 )
	if not c or not sm.exists( c ) or not uuid or qty < 1 then
		return false
	end
	local ok = false
	pcall( function()
		if sm.container.beginTransaction() then
			local n = sm.container.spend( c, uuid, qty, false )
			ok = n == qty
			if ok then
				ok = sm.container.endTransaction() and true or false
			else
				sm.container.abortTransaction()
			end
		end
	end )
	if ok then
		return true
	end
	pcall( function()
		ok = sm.container.spend( c, uuid, qty, true ) and true or false
	end )
	return ok
end

function RfsBotInventory.isSeedUuid( uuid )
	if not uuid then
		return false
	end
	if type( RfsFarming ) == "table" and type( RfsFarming.isPlantableSeed ) == "function" then
		local ok, v = pcall( RfsFarming.isPlantableSeed, uuid )
		if ok and v then
			return true
		end
	end
	local s = uuidStr( uuid ) or ""
	local lower = string.lower( tostring( uuid ) )
	if string.find( lower, "seed", 1, true ) then
		return true
	end
	-- Survival seed UUIDs (same set as Collect allowlist).
	local seeds = {
		"22beade5-38ca-47b4-a2ee-32403f58a862",
		"4b6d2bee-d0f1-4e56-96f0-d2596388cad2",
		"bee966b0-b5e5-41da-b992-5d363ab85ae4",
		"9edb6f7c-fb44-4348-a1c4-8afb41b92d8a",
		"9c82a525-8a8b-4483-9595-505aaa042486",
		"64051718-a3f1-422b-bda3-277efa0c4545",
		"38e41fb5-dd50-4294-829d-a517f0282fed",
		"1c6756ca-3a60-4dcb-a5d1-353edf818308",
		"eb1ef696-5c05-4662-9e47-fe1e0875ff84",
		"93c27ab2-4930-4654-ba1c-bcfe35e966f6",
		"c44b27da-88cf-4e17-b872-6236a1172688",
		"8883e0ee-8a6e-423a-a4e0-583d9bf105bd",
	}
	for i = 1, #seeds do
		if s == seeds[i] then
			return true
		end
	end
	return false
end

local function tryCollectChest( container, uuid, qty )
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
		if tryCollectChest( container, uuid, n ) then
			return n
		end
		if n == 1 then
			return 0
		end
		n = math.floor( n / 2 )
	end
	return 0
end

-- Dump bot inventory into color-matched chests: green=seed, blue=gathered, other=overflow.
-- Returns moved stack-ops. Walks to the first matching chest via RfsBotPath.ensureNear.
function RfsBotInventory.sv_dumpToChests( unit, info, homeRec, radius, preferPos )
	local c = RfsBotInventory.sv_ensure( unit )
	if not c or RfsBotInventory.isEmpty( c ) then
		return 0
	end
	local homePos = homeRec and homeRec.pos
	if not homePos or not radius then
		return 0
	end
	if type( RfsBotPath ) ~= "table" or type( RfsBotPath.findChests ) ~= "function" then
		return 0
	end
	local seedChests = RfsBotPath.findChests( homePos, radius, preferPos, RfsBotPath.ROLE_SEED, homeRec )
	local gatherChests = RfsBotPath.findChests( homePos, radius, preferPos, RfsBotPath.ROLE_PRODUCE, homeRec )
	local overflow = RfsBotPath.findChests( homePos, radius, preferPos, RfsBotPath.ROLE_DROP, homeRec )
	local firstUuid = nil
	local sizePeek = containerSize( c )
	for i = 0, sizePeek - 1 do
		local uuid, qty = slotItem( c, i )
		if uuid and qty > 0 then
			firstUuid = uuid
			break
		end
	end
	local first
	if firstUuid and RfsBotInventory.isSeedUuid( firstUuid ) then
		first = seedChests[1] or overflow[1] or gatherChests[1]
	else
		first = gatherChests[1] or overflow[1] or seedChests[1]
	end
	if type( RfsBotPath.ensureNear ) == "function" and first then
		if not RfsBotPath.ensureNear( unit, info, first ) then
			return 0
		end
	end
	local function chain( primary, extra )
		local out = {}
		for _, row in ipairs( primary or {} ) do
			out[#out + 1] = row
		end
		for _, row in ipairs( extra or {} ) do
			out[#out + 1] = row
		end
		return out
	end
	local seedTargets = chain( seedChests, overflow )
	local gatherTargets = chain( gatherChests, overflow )
	local moved = 0
	local size = containerSize( c )
	for i = 0, size - 1 do
		if moved >= 4 then
			break
		end
		local uuid, qty = slotItem( c, i )
		if uuid and qty > 0 then
			local targets = RfsBotInventory.isSeedUuid( uuid ) and seedTargets or gatherTargets
			local remaining = qty
			for _, chest in ipairs( targets or {} ) do
				while remaining > 0 and moved < 4 do
					-- Spend from bot first so a failed chest collect cannot dupe.
					local n = remaining
					local took = false
					while n >= 1 do
						if RfsBotInventory.spend( c, uuid, n ) then
							took = true
							break
						end
						if n == 1 then
							break
						end
						n = math.floor( n / 2 )
					end
					if not took then
						break
					end
					local stored = depositInto( chest.container, uuid, n )
					if stored < n then
						local refund = n - stored
						if refund > 0 then
							RfsBotInventory.collect( c, uuid, refund )
						end
					end
					if stored < 1 then
						break
					end
					remaining = remaining - stored
					moved = moved + 1
				end
				if remaining < 1 or moved >= 4 then
					break
				end
			end
		end
	end
	return moved
end

function RfsBotInventory.cl_openFromCharacter( charScript )
	if not charScript then
		return false
	end
	local unit = nil
	pcall( function()
		unit = charScript.character and charScript.character:getUnit()
	end )
	local c = RfsBotInventory.get( unit )
	if not c then
		return false
	end
	local gui = nil
	pcall( function()
		gui = sm.gui.createContainerGui( true )
		gui:setText( "UpperName", "Bot inventory" )
		gui:setContainer( "UpperGrid", c )
		gui:setText( "LowerName", "#{INVENTORY_TITLE}" )
		gui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
		pcall( function()
			gui:setOnCloseCallback( "cl_e_rfsInvClose" )
		end )
		gui:open()
	end )
	if gui then
		charScript.cl = charScript.cl or {}
		charScript.cl.rfsInvGui = gui
		return true
	end
	return false
end

print( "[RFS] RfsBotInventory loaded (ally U-inventory)" )
