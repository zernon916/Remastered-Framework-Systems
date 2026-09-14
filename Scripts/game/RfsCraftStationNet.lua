-- RfsCraftStationNet.lua — Recipe Viewer pairing + station loop + remote fill.
-- Max 4 paired viewers per station. Priority 1 fills first. Logic-linked
-- stations (max 3) pool queue slots.

RfsCraftStationNet = RfsCraftStationNet or {}

local STATION_UUID = "c8d7e6f5-a4b3-42c1-9d0e-8f7a6b5c4d3e"
local MAX_PAIRS = 4
local MAX_LOOP = 3

local function playerIdOf( player )
	local id
	pcall( function()
		id = player:getId()
	end )
	return id
end

local function playerById( id )
	if id == nil then
		return nil
	end
	local found
	pcall( function()
		for _, p in ipairs( sm.player.getAllPlayers() or {} ) do
			if p and p:getId() == id then
				found = p
				return
			end
		end
	end )
	return found
end

local function playerName( player )
	local n = "Player"
	pcall( function()
		n = player:getName() or n
	end )
	return tostring( n )
end

local function stationUuidOf( st )
	local u
	pcall( function()
		u = tostring( st.shape:getShapeUuid() )
	end )
	return u
end

function RfsCraftStationNet.isStation( st )
	return st and stationUuidOf( st ) == STATION_UUID
end

local function stationBag()
	local bag = _G.g_rfsCraftStations
	if type( bag ) == "table" and next( bag ) ~= nil then
		return bag
	end
	local game = _G.g_rfsGame
	if game and game.sv and type( game.sv.rfsCraftStations ) == "table" then
		return game.sv.rfsCraftStations
	end
	return bag or {}
end

local function interactableOf( st )
	local inter
	pcall( function()
		inter = st.interactable
	end )
	return inter
end

local INTERACT_RANGE = 8

local function stationRange( st )
	local range = 0
	pcall( function()
		local info = RfsCraftStation.TIERS[math.max( 1, tonumber( st.sv.tier ) or 1 )]
		range = info and tonumber( info.range ) or 0
	end )
	if range <= 0 then
		range = INTERACT_RANGE
	end
	return range
end

function RfsCraftStationNet.inRange( st, player )
	if not st or not st.sv or st.sv.wireless ~= true or not player then
		return false, 0, 0
	end
	local dist
	pcall( function()
		dist = ( st.shape.worldPosition - player.character.worldPosition ):length()
	end )
	if not dist then
		return false, 0, stationRange( st )
	end
	local range = stationRange( st )
	return ( dist <= range or dist <= INTERACT_RANGE ), dist, range
end

function RfsCraftStationNet.nearestWireless( player )
	local pos
	pcall( function()
		pos = player and player.character and player.character.worldPosition
	end )
	local best, bestDist = nil, math.huge
	for st, _ in pairs( stationBag() ) do
		if st and st.sv and st.sv.wireless == true then
			local ok, dist = RfsCraftStationNet.inRange( st, player )
			if ok and dist and dist < bestDist then
				best, bestDist = st, dist
			end
		end
	end
	return best
end

function RfsCraftStationNet.findPaired( player )
	local id
	pcall( function()
		id = player and player:getId()
	end )
	if not id then
		return nil
	end
	for st, _ in pairs( stationBag() ) do
		if st and st.sv and type( st.sv.pairs ) == "table" then
			for _, row in ipairs( st.sv.pairs ) do
				if row.id == id then
					return st, row
				end
			end
		end
	end
	return nil
end

function RfsCraftStationNet.stationByShapeId( shapeId )
	shapeId = tonumber( shapeId )
	if not shapeId then
		return nil
	end
	for st, _ in pairs( stationBag() ) do
		local id
		pcall( function()
			id = st.shape:getId()
		end )
		if id == shapeId then
			return st
		end
	end
	return nil
end

function RfsCraftStationNet.loopMembers( root )
	local list, seen = {}, {}
	if not root then
		return list
	end
	local queue = { root }
	while #queue > 0 and #list < MAX_LOOP do
		local st = table.remove( queue, 1 )
		if st and not seen[st] then
			seen[st] = true
			list[#list + 1] = st
			local inter = interactableOf( st )
			local links = {}
			pcall( function()
				for _, p in ipairs( inter:getParents() or {} ) do
					links[#links + 1] = p
				end
			end )
			pcall( function()
				for _, c in ipairs( inter:getChildren() or {} ) do
					links[#links + 1] = c
				end
			end )
			for _, otherInter in ipairs( links ) do
				for cand, _ in pairs( stationBag() ) do
					if cand ~= st and interactableOf( cand ) == otherInter and not seen[cand] then
						queue[#queue + 1] = cand
					end
				end
			end
		end
	end
	return list
end

function RfsCraftStationNet.pooledSlots( root )
	local n = 0
	for _, st in ipairs( RfsCraftStationNet.loopMembers( root ) ) do
		local slots = 4
		pcall( function()
			local info = RfsCraftStation.TIERS[math.max( 1, tonumber( st.sv.tier ) or 1 )]
			slots = info and info.slots or 4
		end )
		n = n + slots
	end
	return n
end

local function freeSlots( st )
	local info = RfsCraftStation.TIERS[math.max( 1, tonumber( st.sv and st.sv.tier ) or 1 )]
	local cap = info and info.slots or 4
	local crafts = type( st.sv.crafts ) == "table" and #st.sv.crafts or 0
	local recycles = type( st.sv.recycles ) == "table" and #st.sv.recycles or 0
	return math.max( 0, cap - crafts - recycles ), st
end

function RfsCraftStationNet.pickFillStation( root )
	local best, bestFree = nil, 0
	for _, st in ipairs( RfsCraftStationNet.loopMembers( root ) ) do
		local free = freeSlots( st )
		if free > bestFree then
			best, bestFree = st, free
		end
	end
	return best, bestFree
end

local function findStationWithCraft( root, itemId )
	itemId = tostring( itemId or "" )
	for _, st in ipairs( RfsCraftStationNet.loopMembers( root ) ) do
		for _, entry in ipairs( st.sv and st.sv.crafts or {} ) do
			if entry and tostring( entry.itemId ) == itemId then
				return st
			end
		end
	end
	return nil
end

function RfsCraftStationNet.renumber( pairs )
	for i, row in ipairs( pairs ) do
		row.prio = i
	end
	return pairs
end

function RfsCraftStationNet.sv_pair( station, player )
	if not station or not station.sv or not player then
		return false, "bad"
	end
	local nearby = false
	pcall( function()
		nearby = ( player.character.worldPosition - station.shape.worldPosition ):length() <= INTERACT_RANGE
	end )
	if station.sv.wireless ~= true and nearby then
		station.sv.wireless = true
	end
	if station.sv.wireless ~= true then
		return false, "wireless off"
	end
	station.sv.pairs = type( station.sv.pairs ) == "table" and station.sv.pairs or {}
	local id = playerIdOf( player )
	if not id then
		return false, "no player"
	end
	for _, row in ipairs( station.sv.pairs ) do
		if row.id == id then
			return true, "paired"
		end
	end
	for st, _ in pairs( stationBag() ) do
		if st ~= station and type( st.sv ) == "table" and type( st.sv.pairs ) == "table" then
			for i, row in ipairs( st.sv.pairs ) do
				if row.id == id then
					table.remove( st.sv.pairs, i )
					RfsCraftStationNet.renumber( st.sv.pairs )
					if st.sv_syncClients then
						st:sv_syncClients()
					end
					break
				end
			end
		end
	end
	if #station.sv.pairs >= MAX_PAIRS then
		return false, "full"
	end
	station.sv.pairs[#station.sv.pairs + 1] = {
		id = id,
		name = playerName( player ),
		prio = #station.sv.pairs + 1,
	}
	return true, "paired"
end

function RfsCraftStationNet.sv_setPrio( station, player, newPrio )
	if not station or not station.sv or not player then
		return false
	end
	station.sv.pairs = type( station.sv.pairs ) == "table" and station.sv.pairs or {}
	local id = playerIdOf( player )
	newPrio = math.max( 1, math.min( MAX_PAIRS, math.floor( tonumber( newPrio ) or 0 ) ) )
	local me
	for _, row in ipairs( station.sv.pairs ) do
		if row.id == id then
			me = row
			break
		end
	end
	if not me then
		return false
	end
	me.prio = newPrio
	return true
end

function RfsCraftStationNet.pairSnapshot( station, player )
	local pairs = station and station.sv and station.sv.pairs or {}
	local id = player and playerIdOf( player )
	local mine
	for _, row in ipairs( pairs ) do
		if row.id == id then
			mine = row
			break
		end
	end
	local connected, dist, range = false, 0, 0
	if station then
		connected, dist, range = RfsCraftStationNet.inRange( station, player )
	end
	return {
		paired = mine ~= nil,
		prio = mine and mine.prio or 0,
		count = #pairs,
		max = MAX_PAIRS,
		wireless = station and station.sv and station.sv.wireless == true,
		connected = connected == true and mine ~= nil,
		dist = dist,
		range = range,
		loop = #( RfsCraftStationNet.loopMembers( station ) ),
		slots = station and RfsCraftStationNet.pooledSlots( station ) or 0,
		names = ( function()
			local n = {}
			for _, row in ipairs( pairs ) do
				n[#n + 1] = { name = row.name, prio = row.prio }
			end
			return n
		end )(),
	}
end

function RfsCraftStationNet.tabletStatus( player )
	local paired = RfsCraftStationNet.findPaired( player )
	local near = RfsCraftStationNet.nearestWireless( player )
	local st = paired or near
	if not st then
		return {
			paired = false,
			prio = 0,
			count = 0,
			max = MAX_PAIRS,
			wireless = false,
			connected = false,
			names = {},
		}
	end
	return RfsCraftStationNet.pairSnapshot( st, player )
end

function RfsCraftStationNet.sv_fillRemote( root )
	if not root or not root.sv or root.sv.wireless ~= true then
		return 0
	end
	root.sv.pairs = type( root.sv.pairs ) == "table" and root.sv.pairs or {}
	local ordered = {}
	for _, row in ipairs( root.sv.pairs ) do
		ordered[#ordered + 1] = row
	end
	table.sort( ordered, function( a, b )
		return ( a.prio or 99 ) < ( b.prio or 99 )
	end )
	local made = 0
	local rootShapeId
	pcall( function() rootShapeId = root.shape:getId() end )
	for _, row in ipairs( ordered ) do
		local player = playerById( row.id )
		if player and type( RfsCraftQueue ) == "table" then
			local q = RfsCraftQueue.get( player )
			local crafts = q and q.crafts or {}
			local i = 1
			while i <= #crafts do
				local itemId = crafts[i] and crafts[i].itemId
				if not itemId then
					break
				end
				local dest = findStationWithCraft( root, itemId )
				if not dest then
					local free
					dest, free = RfsCraftStationNet.pickFillStation( root )
					if not dest or ( free or 0 ) <= 0 then
						return made
					end
				end
				local before = #( dest.sv.crafts or {} )
				local beforeCount = 0
				for _, e in ipairs( dest.sv.crafts or {} ) do
					if e and tostring( e.itemId ) == tostring( itemId ) then
						beforeCount = math.max( 1, math.floor( tonumber( e.count ) or 1 ) )
					end
				end
				local queued = 0
				if dest.sv_n_craftStation then
					queued = dest:sv_n_craftStation( { itemId = itemId, qty = 1, remote = true, remoteRootId = rootShapeId }, player ) or 0
				end
				local afterCount = 0
				for _, e in ipairs( dest.sv.crafts or {} ) do
					if e and tostring( e.itemId ) == tostring( itemId ) then
						afterCount = math.max( 1, math.floor( tonumber( e.count ) or 1 ) )
					end
				end
				local after = #( dest.sv.crafts or {} )
				if queued > 0 or after > before or afterCount > beforeCount then
					local left = ( tonumber( crafts[i].qty ) or 1 ) - 1
					RfsCraftQueue.set( player, itemId, left )
					q = RfsCraftQueue.get( player )
					crafts = q and q.crafts or {}
					made = made + 1
					i = 1
				else
					i = i + 1
				end
			end
		end
	end
	return made
end

print( "[RFS] RfsCraftStationNet loaded (pair 4 / loop 3 / priority fill)" )
