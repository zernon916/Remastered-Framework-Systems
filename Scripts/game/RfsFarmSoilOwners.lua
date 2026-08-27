-- RfsFarmSoilOwners.lua — mark player-placed soil cells for Farmers Tablet.
-- World storage: cellKey -> playerId. Unmarked / world soil is ignored by the tablet.

RfsFarmSoilOwners = RfsFarmSoilOwners or {}

local STORAGE_KEY = { "rfs", "farmSoilOwners" }

local function loadMap()
	local ok, data = pcall( sm.storage.load, STORAGE_KEY )
	if ok and type( data ) == "table" then
		return data
	end
	return {}
end

local function saveMap( map )
	pcall( sm.storage.save, STORAGE_KEY, map or {} )
end

function RfsFarmSoilOwners.cellKey( pos )
	if not pos or type( pos.x ) ~= "number" then
		return nil
	end
	-- XY only: soil → crop harvestables can shift Z slightly; farms are 2D.
	return string.format( "%d:%d",
		math.floor( pos.x + 0.5 ),
		math.floor( pos.y + 0.5 ) )
end

function RfsFarmSoilOwners.mark( pos, player )
	local key = RfsFarmSoilOwners.cellKey( pos )
	if not key or not player then
		return
	end
	local pid = nil
	pcall( function() pid = player.id end )
	if pid == nil then
		pcall( function() pid = player:getId() end )
	end
	if pid == nil then
		return
	end
	local map = loadMap()
	map[key] = tostring( pid )
	saveMap( map )
end

function RfsFarmSoilOwners.clear( pos )
	local key = RfsFarmSoilOwners.cellKey( pos )
	if not key then
		return
	end
	local map = loadMap()
	if map[key] ~= nil then
		map[key] = nil
		saveMap( map )
	end
end

function RfsFarmSoilOwners.getOwner( pos )
	local key = RfsFarmSoilOwners.cellKey( pos )
	if not key then
		return nil
	end
	local map = loadMap()
	return map[key]
end

function RfsFarmSoilOwners.isPlayerPlaced( pos )
	return RfsFarmSoilOwners.getOwner( pos ) ~= nil
end

print( "[RFS] RfsFarmSoilOwners loaded" )
