-- RfsInventory.lua — personal inventory size options for Recipe Framework Survival
-- Author: DemonsDen126
-- Uses Game.defaultInventorySize + sm.container.resize (Custom Game API).

RfsInventory = RfsInventory or {}

-- Survival personal inventory is 10-wide. Default size 40 = hotbar row + 3 bag rows.
local ROW = 10
local VANILLA_SLOTS = 40

-- Exactly five options (no +2 rows).
RfsInventory.OPTIONS = {
	{ id = "vanilla", label = "Vanilla",          extraRows = 0, slots = VANILLA_SLOTS },
	{ id = "p1",      label = "Vanilla + 1 row",  extraRows = 1, slots = VANILLA_SLOTS + ROW },
	{ id = "p3",      label = "Vanilla + 3 rows", extraRows = 3, slots = VANILLA_SLOTS + 3 * ROW },
	{ id = "p4",      label = "Vanilla + 4 rows", extraRows = 4, slots = VANILLA_SLOTS + 4 * ROW },
	{ id = "p5",      label = "Vanilla + 5 rows", extraRows = 5, slots = VANILLA_SLOTS + 5 * ROW },
}

local STORAGE_KEY = { "rfs", "inventorySizeOption" }

local function findOption( id )
	id = tostring( id or "vanilla" )
	for _, opt in ipairs( RfsInventory.OPTIONS ) do
		if opt.id == id then
			return opt
		end
	end
	return RfsInventory.OPTIONS[1]
end

function RfsInventory.getSavedOptionId()
	local ok, data = pcall( sm.storage.load, STORAGE_KEY )
	if ok and type( data ) == "string" and data ~= "" then
		return findOption( data ).id
	end
	if ok and type( data ) == "table" and data.id then
		return findOption( data.id ).id
	end
	return "vanilla"
end

function RfsInventory.saveOptionId( id )
	local opt = findOption( id )
	pcall( sm.storage.save, STORAGE_KEY, opt.id )
	return opt
end

function RfsInventory.getOption( id )
	return findOption( id )
end

function RfsInventory.slotsFor( id )
	return findOption( id ).slots
end

-- Apply defaultInventorySize for newly created players (class constant).
function RfsInventory.applyGameDefault( gameClass )
	local opt = findOption( RfsInventory.getSavedOptionId() )
	if gameClass then
		gameClass.defaultInventorySize = opt.slots
	end
	-- Engine reads the registered Game class field; keep aliases in sync.
	if RecipeFrameworkSurvival then
		RecipeFrameworkSurvival.defaultInventorySize = opt.slots
	end
	if Game then
		Game.defaultInventorySize = opt.slots
	end
	print( "[RFS] defaultInventorySize=" .. tostring( opt.slots ) .. " (" .. opt.label .. ")" )
	return opt
end

local function playerId( player )
	local id = nil
	pcall( function() id = player.id end )
	if id == nil then
		pcall( function() id = player:getId() end )
	end
	return id
end

-- sm.exists() is for shapes/bodies/characters/containers — not Player.
-- Survival never calls sm.exists(player); doing so made apply return false for everyone.
function RfsInventory.collectPlayers( extraPlayer )
	local seen = {}
	local list = {}
	local function add( p )
		if p == nil then
			return
		end
		local id = playerId( p )
		local key = id or tostring( p )
		if seen[key] then
			return
		end
		seen[key] = true
		list[#list + 1] = p
	end
	add( extraPlayer )
	local all = nil
	pcall( function() all = sm.player.getAllPlayers() end )
	if type( all ) == "table" then
		for _, p in pairs( all ) do
			add( p )
		end
	end
	return list
end

local function containerSize( inv )
	local cur = nil
	pcall( function() cur = inv.size end )
	if type( cur ) == "number" then
		return cur
	end
	pcall( function() cur = sm.container.getSize( inv ) end )
	if type( cur ) == "number" then
		return cur
	end
	pcall( function() cur = inv:getSize() end )
	if type( cur ) == "number" then
		return cur
	end
	return nil
end

-- Resize an existing player's personal inventory. Server only.
function RfsInventory.applyToPlayer( player, optionId )
	if player == nil then
		return false, "no player"
	end
	local opt = findOption( optionId )
	local inv = nil
	pcall( function() inv = player:getInventory() end )
	if not inv then
		print( "[RFS] inventory apply skipped: getInventory nil id=" .. tostring( playerId( player ) ) )
		return false, "no inventory"
	end
	local exists = true
	pcall( function() exists = sm.exists( inv ) end )
	if exists == false then
		print( "[RFS] inventory apply skipped: container missing id=" .. tostring( playerId( player ) ) )
		return false, "no inventory"
	end
	local cur = containerSize( inv )
	if cur == opt.slots then
		return true, opt
	end
	local ok, err = pcall( sm.container.resize, inv, opt.slots )
	if not ok then
		ok, err = pcall( function() inv:resize( opt.slots ) end )
	end
	if not ok then
		print( "[RFS] inventory resize failed: " .. tostring( err ) )
		return false, err
	end
	print( "[RFS] resized inventory " .. tostring( cur ) .. " -> " .. tostring( opt.slots ) .. " (" .. opt.label .. ")" )
	return true, opt
end

-- Host (extraPlayer) is always included; then every connected player.
function RfsInventory.applyToAllPlayers( optionId, extraPlayer )
	local opt = findOption( optionId )
	local players = RfsInventory.collectPlayers( extraPlayer )
	local applied = 0
	for _, p in ipairs( players ) do
		local ok = false
		pcall( function()
			ok = RfsInventory.applyToPlayer( p, opt.id )
		end )
		if ok then
			applied = applied + 1
		end
	end
	return applied, opt, #players
end
