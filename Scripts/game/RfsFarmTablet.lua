-- RfsFarmTablet.lua — scan / cluster player farms for the Farmers Tablet GUI.
-- Gap rule: farmland within Chebyshev distance <= 10 stays one farm
-- (more than 9 empty cells between = separate). Range: 100 m of player.

RfsFarmTablet = RfsFarmTablet or {}

pcall( function()
	dofile( "$SURVIVAL_DATA/Scripts/game/survival_harvestable.lua" )
end )

local RANGE = 100
local MERGE_DIST = 10

local SOIL_UUID = ""
pcall( function() SOIL_UUID = string.lower( tostring( hvs_soil ) ) end )

-- Bare soil shows the soil-bag item icon in the tablet grid.
local SOILBAG_UUID = "9a3e478c-2224-44fa-887c-239965bd05ad"

local function addCrop( map, uuid, code, name, growing, mature, seedUuid )
	if uuid == nil then
		return
	end
	map[string.lower( tostring( uuid ) )] = {
		code = code,
		name = name,
		growing = growing and true or false,
		mature = mature and true or false,
		seed = seedUuid,
	}
end

-- Seed UUIDs match RfsFarming plantable list / Survival items.
local CROP = {}
addCrop( CROP, hvs_growing_blueberry, "Bl", "Blueberry", true, false, "4b6d2bee-d0f1-4e56-96f0-d2596388cad2" )
addCrop( CROP, hvs_growing_banana, "Ba", "Banana", true, false, "22beade5-38ca-47b4-a2ee-32403f58a862" )
addCrop( CROP, hvs_growing_redbeet, "Rb", "Redbeet", true, false, "64051718-a3f1-422b-bda3-277efa0c4545" )
addCrop( CROP, hvs_growing_carrot, "Ca", "Carrot", true, false, "9c82a525-8a8b-4483-9595-505aaa042486" )
addCrop( CROP, hvs_growing_tomato, "To", "Tomato", true, false, "38e41fb5-dd50-4294-829d-a517f0282fed" )
addCrop( CROP, hvs_growing_orange, "Or", "Orange", true, false, "bee966b0-b5e5-41da-b992-5d363ab85ae4" )
addCrop( CROP, hvs_growing_potato, "Po", "Potato", true, false, "eb1ef696-5c05-4662-9e47-fe1e0875ff84" )
addCrop( CROP, hvs_growing_pineapple, "Pi", "Pineapple", true, false, "9edb6f7c-fb44-4348-a1c4-8afb41b92d8a" )
addCrop( CROP, hvs_growing_broccoli, "Br", "Broccoli", true, false, "1c6756ca-3a60-4dcb-a5d1-353edf818308" )
addCrop( CROP, hvs_growing_cotton, "Co", "Cotton", true, false, "93c27ab2-4930-4654-ba1c-bcfe35e966f6" )
addCrop( CROP, hvs_growing_chili, "Ch", "Chili", true, false, "8883e0ee-8a6e-423a-a4e0-583d9bf105bd" )
addCrop( CROP, hvs_growing_pigmentflower, "Pg", "Pigment", true, false, "c44b27da-88cf-4e17-b872-6236a1172688" )
addCrop( CROP, hvs_mature_blueberry, "Bl", "Blueberry", false, true, "4b6d2bee-d0f1-4e56-96f0-d2596388cad2" )
addCrop( CROP, hvs_mature_banana, "Ba", "Banana", false, true, "22beade5-38ca-47b4-a2ee-32403f58a862" )
addCrop( CROP, hvs_mature_redbeet, "Rb", "Redbeet", false, true, "64051718-a3f1-422b-bda3-277efa0c4545" )
addCrop( CROP, hvs_mature_carrot, "Ca", "Carrot", false, true, "9c82a525-8a8b-4483-9595-505aaa042486" )
addCrop( CROP, hvs_mature_tomato, "To", "Tomato", false, true, "38e41fb5-dd50-4294-829d-a517f0282fed" )
addCrop( CROP, hvs_mature_orange, "Or", "Orange", false, true, "bee966b0-b5e5-41da-b992-5d363ab85ae4" )
addCrop( CROP, hvs_mature_potato, "Po", "Potato", false, true, "eb1ef696-5c05-4662-9e47-fe1e0875ff84" )
addCrop( CROP, hvs_mature_pineapple, "Pi", "Pineapple", false, true, "9edb6f7c-fb44-4348-a1c4-8afb41b92d8a" )
addCrop( CROP, hvs_mature_broccoli, "Br", "Broccoli", false, true, "1c6756ca-3a60-4dcb-a5d1-353edf818308" )
addCrop( CROP, hvs_mature_cotton, "Co", "Cotton", false, true, "93c27ab2-4930-4654-ba1c-bcfe35e966f6" )
addCrop( CROP, hvs_mature_chili, "Ch", "Chili", false, true, "8883e0ee-8a6e-423a-a4e0-583d9bf105bd" )
addCrop( CROP, hvs_mature_pigmentflower, "Pg", "Pigment", false, true, "c44b27da-88cf-4e17-b872-6236a1172688" )

local function formatRemain( ticks )
	local secs = math.max( 0, math.ceil( ( ticks or 0 ) / 40 ) )
	local m = math.floor( secs / 60 )
	local s = secs % 60
	if m >= 60 then
		local h = math.floor( m / 60 )
		m = m % 60
		return string.format( "%d:%02d:%02d", h, m, s )
	end
	return string.format( "%d:%02d", m, s )
end

local function cellXY( pos )
	return math.floor( ( pos.x or 0 ) + 0.5 ), math.floor( ( pos.y or 0 ) + 0.5 )
end

local function chebyshev( ax, ay, bx, by )
	local dx = math.abs( ax - bx )
	local dy = math.abs( ay - by )
	if dx > dy then
		return dx
	end
	return dy
end

local function unionFindParent( parent, i )
	while parent[i] ~= i do
		parent[i] = parent[parent[i]]
		i = parent[i]
	end
	return i
end

local function unionFindMerge( parent, a, b )
	local ra, rb = unionFindParent( parent, a ), unionFindParent( parent, b )
	if ra ~= rb then
		parent[rb] = ra
	end
end

function RfsFarmTablet.clusterFarms( cells, playerX, playerY )
	if type( cells ) ~= "table" or #cells == 0 then
		return {}
	end
	local n = #cells
	local parent = {}
	for i = 1, n do
		parent[i] = i
	end
	for i = 1, n do
		for j = i + 1, n do
			if chebyshev( cells[i].x, cells[i].y, cells[j].x, cells[j].y ) <= MERGE_DIST then
				unionFindMerge( parent, i, j )
			end
		end
	end
	local buckets = {}
	local order = {}
	for i = 1, n do
		local root = unionFindParent( parent, i )
		if not buckets[root] then
			buckets[root] = {}
			order[#order + 1] = root
		end
		buckets[root][#buckets[root] + 1] = cells[i]
	end
	local farms = {}
	for _, root in ipairs( order ) do
		local list = buckets[root]
		local minX, maxX = list[1].x, list[1].x
		local minY, maxY = list[1].y, list[1].y
		local sumX, sumY = 0, 0
		for _, c in ipairs( list ) do
			if c.x < minX then minX = c.x end
			if c.x > maxX then maxX = c.x end
			if c.y < minY then minY = c.y end
			if c.y > maxY then maxY = c.y end
			sumX = sumX + c.x
			sumY = sumY + c.y
		end
		farms[#farms + 1] = {
			cells = list,
			minX = minX, maxX = maxX, minY = minY, maxY = maxY,
			cx = sumX / #list, cy = sumY / #list,
		}
	end
	local ox = tonumber( playerX ) or 0
	local oy = tonumber( playerY ) or 0
	table.sort( farms, function( a, b )
		local da = ( a.cx - ox ) * ( a.cx - ox ) + ( a.cy - oy ) * ( a.cy - oy )
		local db = ( b.cx - ox ) * ( b.cx - ox ) + ( b.cy - oy ) * ( b.cy - oy )
		return da < db
	end )
	for i, f in ipairs( farms ) do
		f.id = i
		f.label = string.format( "Farm %d (%d)", i, #f.cells )
	end
	return farms
end

function RfsFarmTablet.avgLines( farm )
	if not farm or type( farm.cells ) ~= "table" then
		return ""
	end
	local sums, counts, names = {}, {}, {}
	for _, c in ipairs( farm.cells ) do
		if c.kind == "growing" and c.remain and c.remain > 0 and c.code and c.code ~= "" then
			sums[c.code] = ( sums[c.code] or 0 ) + c.remain
			counts[c.code] = ( counts[c.code] or 0 ) + 1
			names[c.code] = c.name or c.code
		end
	end
	local rows = {}
	for code, sum in pairs( sums ) do
		local n = counts[code] or 1
		rows[#rows + 1] = {
			code = code,
			name = names[code] or code,
			avg = sum / n,
			count = n,
		}
	end
	table.sort( rows, function( a, b )
		return a.avg < b.avg
	end )
	local lines = {}
	for _, r in ipairs( rows ) do
		if r.count > 1 then
			lines[#lines + 1] = string.format( "%s %s ×%d avg %s", r.code, r.name, r.count, formatRemain( r.avg ) )
		else
			lines[#lines + 1] = string.format( "%s %s  %s", r.code, r.name, formatRemain( r.avg ) )
		end
	end
	if #lines == 0 then
		return "(no growing crops)"
	end
	return table.concat( lines, "\n" )
end

function RfsFarmTablet.gridText( farm, maxW, maxH )
	maxW = maxW or 18
	maxH = maxH or 12
	if not farm or type( farm.cells ) ~= "table" or #farm.cells == 0 then
		return "(empty)"
	end
	local minX, maxX, minY, maxY = farm.minX, farm.maxX, farm.minY, farm.maxY
	local w = maxX - minX + 1
	local h = maxY - minY + 1
	local x0, y0 = minX, minY
	if w > maxW then
		local mid = math.floor( ( minX + maxX ) * 0.5 )
		x0 = mid - math.floor( maxW * 0.5 )
		w = maxW
	end
	if h > maxH then
		local mid = math.floor( ( minY + maxY ) * 0.5 )
		y0 = mid - math.floor( maxH * 0.5 )
		h = maxH
	end
	local grid = {}
	for yy = 0, h - 1 do
		grid[yy] = {}
		for xx = 0, w - 1 do
			grid[yy][xx] = "·"
		end
	end
	for _, c in ipairs( farm.cells ) do
		local xx = c.x - x0
		local yy = c.y - y0
		if xx >= 0 and yy >= 0 and xx < w and yy < h then
			local mark = "·"
			if c.kind == "soil" then
				mark = "[]"
			elseif c.code and #c.code > 0 then
				-- Two-letter crop code when possible (Ca/Po/…); else first char.
				mark = string.sub( c.code, 1, 2 )
			else
				mark = "?"
			end
			grid[yy][xx] = mark
		end
	end
	local lines = {}
	for yy = h - 1, 0, -1 do
		local row = {}
		for xx = 0, w - 1 do
			local cell = grid[yy][xx]
			if #cell == 1 then
				cell = cell .. " "
			end
			row[#row + 1] = cell
			if xx < w - 1 then
				row[#row + 1] = " "
			end
		end
		lines[#lines + 1] = table.concat( row )
	end
	return table.concat( lines, "\n" )
end

local function remainFromClientTable( cx, cy )
	local byId = _G.g_rfsGrowById
	if type( byId ) ~= "table" then
		return nil
	end
	for _, e in pairs( byId ) do
		if type( e ) == "table" and e.x and e.y then
			if math.floor( e.x + 0.5 ) == cx and math.floor( e.y + 0.5 ) == cy then
				return e.remain
			end
		end
	end
	return nil
end

function RfsFarmTablet.mergeClientRemains( cells )
	if type( cells ) ~= "table" then
		return cells
	end
	for _, c in ipairs( cells ) do
		if c.kind == "growing" then
			c.remain = remainFromClientTable( c.x, c.y )
		end
	end
	return cells
end

--- Gather soil/crops within RANGE of `pos`. Soft ownership vs `player` (optional).
function RfsFarmTablet.gatherCellsAt( pos, world, player )
	local cells = {}
	if not pos then
		return cells
	end
	local all = nil
	pcall( function()
		if world then
			all = sm.harvestable.getAllHarvestables( world )
		end
	end )
	if type( all ) ~= "table" then
		pcall( function()
			all = sm.harvestable.getAllHarvestables()
		end )
	end
	if type( all ) ~= "table" then
		return cells
	end

	local range2 = RANGE * RANGE
	local candidates = {}
	local anyMarked = false

	for _, h in pairs( all ) do
		if h and sm.exists( h ) then
			local hp = nil
			pcall( function() hp = h:getPosition() end )
			if not hp then
				pcall( function() hp = h.worldPosition end )
			end
			if hp then
				local dx = ( hp.x or 0 ) - ( pos.x or 0 )
				local dy = ( hp.y or 0 ) - ( pos.y or 0 )
				local dz = ( hp.z or 0 ) - ( pos.z or 0 )
				if ( dx * dx + dy * dy + dz * dz ) <= range2 then
					local uid = nil
					pcall( function() uid = h:getUuid() end )
					if not uid then
						pcall( function() uid = h.uuid end )
					end
					if uid then
						local uidLow = string.lower( tostring( uid ) )
						local cx, cy = cellXY( hp )
						local kind, code, name, seed = nil, "", "", nil
						local isSoil = false
						pcall( function()
							if type( RfsFarming ) == "table" and RfsFarming.isSoilUuid then
								isSoil = RfsFarming.isSoilUuid( uid ) == true
							end
						end )
						if not isSoil and SOIL_UUID ~= "" and uidLow == SOIL_UUID then
							isSoil = true
						end
						if isSoil then
							kind, code, name, seed = "soil", "", "Soil", SOILBAG_UUID
						else
							local info = CROP[uidLow]
							if info then
								kind = info.growing and "growing" or "mature"
								code = info.code
								name = info.name
								seed = info.seed
							end
						end
						if kind then
							local marked = false
							if type( RfsFarmSoilOwners ) == "table" and RfsFarmSoilOwners.isPlayerPlaced then
								marked = RfsFarmSoilOwners.isPlayerPlaced( hp ) == true
							end
							if marked then
								anyMarked = true
							end
							candidates[#candidates + 1] = {
								x = cx, y = cy,
								z = math.floor( ( hp.z or 0 ) + 0.5 ),
								kind = kind, code = code, name = name, seed = seed,
								marked = marked,
								pos = hp,
							}
						end
					end
				end
			end
		end
	end

	for _, c in ipairs( candidates ) do
		if ( not anyMarked ) or c.marked then
			cells[#cells + 1] = {
				x = c.x, y = c.y, z = c.z,
				kind = c.kind, code = c.code, name = c.name, seed = c.seed,
			}
			if player and not c.marked and c.pos then
				pcall( function()
					if type( RfsFarmSoilOwners ) == "table" and RfsFarmSoilOwners.mark then
						RfsFarmSoilOwners.mark( c.pos, player )
					end
				end )
			end
		end
	end
	return cells
end

function RfsFarmTablet.gatherCells( player )
	if not player then
		return {}
	end
	local char = nil
	pcall( function() char = player.character or player:getCharacter() end )
	if not char or not sm.exists( char ) then
		return {}
	end
	local pos = nil
	pcall( function() pos = char.worldPosition or char:getWorldPosition() end )
	if not pos then
		return {}
	end
	local world = nil
	pcall( function() world = char:getWorld() end )
	return RfsFarmTablet.gatherCellsAt( pos, world, player )
end

--- Face lines for Farm Screen: nearest farm avg times (max `maxLines`).
function RfsFarmTablet.nearestFarmFaceLines( pos, world, player, maxLines )
	maxLines = maxLines or 4
	local cells = RfsFarmTablet.gatherCellsAt( pos, world, player )
	pcall( function()
		if type( RfsFarmTablet.mergeClientRemains ) == "function" then
			cells = RfsFarmTablet.mergeClientRemains( cells )
		end
	end )
	local farms = RfsFarmTablet.clusterFarms( cells, pos and pos.x, pos and pos.y ) or {}
	if #farms == 0 then
		return { "NO FARM", "IN RANGE", "", "" }
	end
	local farm = farms[1]
	local avg = RfsFarmTablet.avgLines( farm ) or ""
	local lines = {}
	lines[1] = string.format( "FARM %d (%d)", farm.id or 1, farm.cells and #farm.cells or 0 )
	for part in string.gmatch( avg, "[^\n]+" ) do
		if #lines >= maxLines then
			break
		end
		local code, t = string.match( part, "^(%S+)%s.-avg%s+(%S+)%s*$" )
		if code and t then
			lines[#lines + 1] = code .. " " .. t
		else
			local code2, t2 = string.match( part, "^(%S+)%s+%S+%s+(%S+)%s*$" )
			if code2 and t2 then
				lines[#lines + 1] = code2 .. " " .. t2
			else
				lines[#lines + 1] = string.sub( part, 1, 22 )
			end
		end
	end
	if #lines == 1 then
		lines[2] = "(no growing)"
	end
	while #lines < maxLines do
		lines[#lines + 1] = ""
	end
	return lines
end

function RfsFarmTablet.buildPayload( player )
	local cells = RfsFarmTablet.gatherCells( player )
	local px, py = 0, 0
	pcall( function()
		local char = player.character or player:getCharacter()
		local pos = char and ( char.worldPosition or char:getWorldPosition() )
		if pos then
			px, py = pos.x or 0, pos.y or 0
		end
	end )
	return {
		cells = cells,
		range = RANGE,
		count = #cells,
		playerX = px,
		playerY = py,
	}
end

RfsFarmTablet.formatRemain = formatRemain
RfsFarmTablet.RANGE = RANGE

print( "[RFS] RfsFarmTablet loaded" )
