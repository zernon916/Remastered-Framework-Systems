-- RfsBiomeMap.lua — stylized biome ids for BigMap / MinimapHud (no DLL).
-- Uses terrain flags + poi_names labels (autumn / burnt / lake / mountain).
-- Paint ids match Survival TYPE_* (see celldata.lua).

RfsBiomeMap = RfsBiomeMap or {}

local NILUUID = "00000000000000000000000000000000"
local LID = "29c99287-1213-48c7-9471-19a4a5c12247"

RfsBiomeMap.SOLID = true
RfsBiomeMap.SOLID_MINIMAP = false
RfsBiomeMap.SINGLE_CELL_MINIMAP = true
-- BigMap solid paint extras (minimap atlas unchanged).
RfsBiomeMap.ROADS = true              -- atlas road_N overlay (1 widget / cell)
RfsBiomeMap.TILES = true              -- Gui/MapTiles curved edge PNGs when zoomed in
RfsBiomeMap.TILE_MIN_PX = 18          -- below this: merged flat colours (no tile art)
RfsBiomeMap.ROUNDED = false           -- old bulge overlays removed
RfsBiomeMap.ROAD_LEGEND_ID = 11
RfsBiomeMap.ROAD_UPHILL_EPS = 1.0

-- Paint ids match Survival celldata terrain types (TYPE_*).
-- 0 water, 1-6 biomes, 8 lake→water, 9 unknown, 10 coast (derived).
RfsBiomeMap.COLORS = {
	[0]  = "0.14 0.38 0.82", -- Ocean / lake (clear blue)
	[1]  = "0.42 0.76 0.30", -- Meadow
	[2]  = "0.16 0.46 0.18", -- Forest
	[3]  = "0.88 0.80 0.50", -- Desert (TYPE_DESERT)
	[4]  = "0.76 0.70 0.36", -- Field / Farmland (TYPE_FIELD)
	[5]  = "0.26 0.24 0.22", -- Burned (TYPE_BURNTFOREST)
	[6]  = "0.90 0.58 0.16", -- Autumn (TYPE_AUTUMNFOREST)
	[7]  = "0.50 0.55 0.40", -- spare
	[8]  = "0.58 0.60 0.64", -- Mountain (stone grey — not blue; POI-only)
	[9]  = "0.38 0.40 0.36", -- Unknown
	[10] = "0.72 0.68 0.42", -- Coast (sandy shore next to water)
	[11] = "0.12 0.12 0.12", -- Roads (legend swatch)
}

RfsBiomeMap.LEGEND = {
	{ id = 0,  label = "Water",    color = RfsBiomeMap.COLORS[0] },
	{ id = 10, label = "Coast",    color = RfsBiomeMap.COLORS[10] },
	{ id = 1,  label = "Meadow",   color = RfsBiomeMap.COLORS[1] },
	{ id = 2,  label = "Forest",   color = RfsBiomeMap.COLORS[2] },
	{ id = 3,  label = "Desert",   color = RfsBiomeMap.COLORS[3] },
	{ id = 4,  label = "Farmland", color = RfsBiomeMap.COLORS[4] },
	{ id = 5,  label = "Burned",   color = RfsBiomeMap.COLORS[5] },
	{ id = 6,  label = "Autumn",   color = RfsBiomeMap.COLORS[6] },
	{ id = 8,  label = "Mountain", color = RfsBiomeMap.COLORS[8] },
	{ id = 11, label = "Roads",    color = RfsBiomeMap.COLORS[11] },
}

local autumnUids, lakeUids, mountainUids, burnedUids = nil, nil, nil, nil

local function stripDashes( s )
	return ( tostring( s ):gsub( "%-", "" ) )
end

local function ensureTags()
	if autumnUids then
		return
	end
	autumnUids, lakeUids, mountainUids, burnedUids = {}, {}, {}, {}
	local paths = {
		"$CONTENT_DATA/Scripts/nutt/data/poi_names.json",
		"$CONTENT_" .. LID .. "/Scripts/nutt/data/poi_names.json",
	}
	for _, path in ipairs( paths ) do
		local ok, poi = pcall( sm.json.open, path )
		if ok and type( poi ) == "table" then
			for uid, info in pairs( poi ) do
				local label = type( info ) == "table" and string.lower( tostring( info.label or "" ) ) or ""
				local key = stripDashes( uid )
				if string.find( label, "autumn", 1, true ) then
					autumnUids[key] = true
				end
				if string.find( label, "burnt", 1, true ) or string.find( label, "burned", 1, true ) then
					burnedUids[key] = true
				end
				-- Lakes / named water on land tiles (Chemical Lake, Random Lake, …)
				if string.find( label, "lake", 1, true )
					or string.find( label, "pond", 1, true )
					or string.find( label, "water front", 1, true )
					or ( string.find( label, "water", 1, true ) and not string.find( label, "waterfall", 1, true ) )
				then
					lakeUids[key] = true
				end
				if string.find( label, "mountain", 1, true ) then
					mountainUids[key] = true
				end
			end
			print( "[RFS] RfsBiomeMap tags: autumn/burned/lake/mountain uids loaded" )
			return
		end
	end
end

function RfsBiomeMap.colorForId( id )
	id = math.floor( tonumber( id ) or 0 )
	return RfsBiomeMap.COLORS[id] or RfsBiomeMap.COLORS[9]
end

--- Base cell class before coast derivation.
--- 0=water/ocean/lake, 1-8=biome, 9=unknown.
function RfsBiomeMap.cellId( td, wx, wy )
	if not td or not td.bounds or not td.uid then
		return 0
	end
	ensureTags()
	local b = td.bounds
	if wx < b.xMin or wx > b.xMax or wy < b.yMin or wy > b.yMax then
		return 0
	end
	local uidRow = td.uid[wy]
	local uid = uidRow and uidRow[wx]
	local uidStr = uid and stripDashes( tostring( uid ) ) or NILUUID
	if uidStr == NILUUID then
		return 0 -- open ocean / empty
	end
	-- Named lake / water tiles (landlocked water you can see on the map)
	if lakeUids[uidStr] then
		return 0
	end
	-- Named POIs win over terrain flags (autumn vs burnt camping/ruins).
	if autumnUids[uidStr] then
		return 6 -- TYPE_AUTUMNFOREST
	end
	if burnedUids[uidStr] then
		return 5 -- TYPE_BURNTFOREST
	end
	if mountainUids[uidStr] then
		return 8
	end
	local flags = ( td.flags and td.flags[wy] and td.flags[wy][wx] ) or 0
	local t = math.floor( flags / 4096 ) % 16
	-- Flag biome 8 is TYPE_LAKE / cyan shelf in the old atlas — treat as water.
	-- True mountains come only from mountain-labeled POIs above.
	if t == 8 then
		return 0
	end
	if t >= 1 and t <= 7 then
		return t
	end
	return 9
end

--- After filling an ids grid, mark land next to water as coast (id 10).
function RfsBiomeMap.applyCoast( ids, x0, x1, y0, y1 )
	local coast = {}
	for wy = y0, y1 do
		for wx = x0, x1 do
			local id = ids[wy][wx]
			if id ~= 0 and id ~= 10 then
				local hit = false
				for dy = -1, 1 do
					for dx = -1, 1 do
						if dx ~= 0 or dy ~= 0 then
							local row = ids[wy + dy]
							if row and row[wx + dx] == 0 then
								hit = true
								break
							end
						end
					end
					if hit then break end
				end
				if hit then
					coast[#coast + 1] = { wx, wy }
				end
			end
		end
	end
	for _, c in ipairs( coast ) do
		ids[c[2]][c[1]] = 10
	end
end

--- True open ocean: water whose visible neighbours are all water (backdrop OK).
function RfsBiomeMap.isOpenOcean( ids, wx, wy, x0, x1, y0, y1 )
	if ids[wy][wx] ~= 0 then
		return false
	end
	for dy = -1, 1 do
		for dx = -1, 1 do
			if dx ~= 0 or dy ~= 0 then
				local nx, ny = wx + dx, wy + dy
				if nx < x0 or nx > x1 or ny < y0 or ny > y1 then
					-- off-view: treat as water so ocean edges don't explode the pool
				else
					local n = ids[ny][nx]
					if n ~= 0 then
						return false
					end
				end
			end
		end
	end
	return true
end

function RfsBiomeMap.frameName( id, tier )
	id = math.floor( tonumber( id ) or 0 )
	if id == 10 then
		-- coast uses farmland-ish atlas fallback for minimap only
		id = 3
	end
	if id <= 0 then
		return ( tier == "big" ) and "water" or "water_r0"
	end
	if id >= 1 and id <= 8 then
		if tier == "big" then
			return "biome_" .. id
		end
		return "biome_" .. id .. "_r0"
	end
	return ( tier == "big" ) and "unknown" or "unknown_r0"
end

function RfsBiomeMap.frameForId( atlas, id, tierName )
	tierName = tierName or "mini"
	local name = RfsBiomeMap.frameName( id, tierName )
	local tbl = ( tierName == "big" ) and atlas.big or atlas.mini
	local hit = tbl and tbl[name]
	if hit then
		return { res = hit.res, name = name, rot = 0, id = id }
	end
	local wname = ( tierName == "big" ) and "water" or "water_r0"
	local wh = tbl and tbl[wname]
	if wh then
		return { res = wh.res, name = wname, rot = 0, id = 0 }
	end
	return nil
end

function RfsBiomeMap.resolveFrame( td, atlas, wx, wy, tierName )
	tierName = tierName or "mini"
	local id = RfsBiomeMap.cellId( td, wx, wy )
	return RfsBiomeMap.frameForId( atlas, id, tierName ), 0, false
end

function RfsBiomeMap.elev( wx, wy )
	local n = math.sin( wx * 12.9898 + wy * 78.233 ) * 43758.5453
	return n - math.floor( n )
end

--- Neighbour paint id from pre-filled ids grid (off-view → sentinel).
function RfsBiomeMap.neighborId( ids, wx, wy, dx, dy, x0, x1, y0, y1 )
	local nx, ny = wx + dx, wy + dy
	if nx < x0 or nx > x1 or ny < y0 or ny > y1 then
		return -1
	end
	local row = ids[ny]
	if not row then
		return -1
	end
	return row[nx]
end

function RfsBiomeMap.edgeMask( ids, wx, wy, id, x0, x1, y0, y1 )
	local n = RfsBiomeMap.neighborId( ids, wx, wy, 0, 1, x0, x1, y0, y1 )
	local s = RfsBiomeMap.neighborId( ids, wx, wy, 0, -1, x0, x1, y0, y1 )
	local e = RfsBiomeMap.neighborId( ids, wx, wy, 1, 0, x0, x1, y0, y1 )
	local w = RfsBiomeMap.neighborId( ids, wx, wy, -1, 0, x0, x1, y0, y1 )
	return {
		N = n ~= id,
		S = s ~= id,
		E = e ~= id,
		W = w ~= id,
		idN = n, idE = e, idS = s, idW = w,
	}
end

function RfsBiomeMap.cornerMask( edge )
	return {
		NW = edge.N and edge.W,
		NE = edge.N and edge.E,
		SW = edge.S and edge.W,
		SE = edge.S and edge.E,
	}
end

function RfsBiomeMap.pickCurveColor( selfId, idA, idB, wx, wy, cornerKey )
	local candidates = { selfId }
	if idA ~= selfId and idA >= 0 then
		candidates[#candidates + 1] = idA
	end
	if idB ~= selfId and idB ~= idA and idB >= 0 then
		candidates[#candidates + 1] = idB
	end
	local ck = cornerKey or 0
	local h = ( wx * 73856093 + wy * 19349663 + ck * 83492791 ) % #candidates + 1
	return candidates[h]
end

function RfsBiomeMap.cornerRadiusPx( px )
	px = tonumber( px ) or 16
	local frac = RfsBiomeMap.CORNER_FRAC or 0.38
	local r = math.floor( px * frac + 0.5 )
	if r < 2 then r = 2 end
	local cap = math.floor( px * 0.48 + 0.5 )
	if r > cap then r = cap end
	return r
end

function RfsBiomeMap.roadMask( td, wx, wy )
	if not td or not td.flags then
		return 0
	end
	local row = td.flags[wy]
	if not row then
		return 0
	end
	local flags = row[wx] or 0
	return math.floor( flags / 256 ) % 16
end

--- N, E, S, W booleans from road mask (atlas junction index 1–15).
function RfsBiomeMap.roadDirs( mask )
	return false, false, false, false
end

function RfsBiomeMap.cellMatchesLegend( filt, td, wx, wy, biomeId )
	if filt == nil then
		return true
	end
	if filt == RfsBiomeMap.ROAD_LEGEND_ID then
		return RfsBiomeMap.roadMask( td, wx, wy ) ~= 0
	end
	return biomeId == filt
end

function RfsBiomeMap.elevationAt( td, wx, wy )
	if not td or not td.elevation then
		return nil
	end
	local row = td.elevation[wy]
	if not row then
		row = td.elevation[math.floor( wy / 64 )]
	end
	if not row then
		return nil
	end
	local v = row[wx]
	if v == nil then
		v = row[math.floor( wx / 64 )]
	end
	if type( v ) == "number" then
		return v
	end
	return nil
end

function RfsBiomeMap.isRoadUphill( td, wx, wy )
	if RfsBiomeMap.cellId( td, wx, wy ) == 8 then
		return true
	end
	local e0 = RfsBiomeMap.elevationAt( td, wx, wy )
	local eps = RfsBiomeMap.ROAD_UPHILL_EPS or 1.0
	if e0 then
		local eE = RfsBiomeMap.elevationAt( td, wx + 1, wy )
		local eN = RfsBiomeMap.elevationAt( td, wx, wy + 1 )
		if eE and ( eE - e0 ) >= eps then return true end
		if eN and ( eN - e0 ) >= eps then return true end
		return false
	end
	local eC = RfsBiomeMap.elev( wx, wy )
	local eE = RfsBiomeMap.elev( wx + 1, wy )
	local eN = RfsBiomeMap.elev( wx, wy + 1 )
	return ( eE - eC ) > 0.05 or ( eN - eC ) > 0.05
end

function RfsBiomeMap.roadBedId( td, wx, wy )
	if RfsBiomeMap.isRoadUphill( td, wx, wy ) then
		return 8
	end
	return 1
end

-- MapTiles naming: WaFo1_N_E.png = Water onto Forest, variant 1, north+east edges.
RfsBiomeMap.TILE_ABBR = {
	[0] = "Wa", [1] = "Me", [2] = "Fo", [3] = "De", [4] = "Fa",
	[5] = "Bu", [6] = "Au", [8] = "Mo", [10] = "Co",
}

local TILE_CC = "$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247/Gui/MapTiles/"

function RfsBiomeMap.tileAbbr( id )
	return RfsBiomeMap.TILE_ABBR[math.floor( tonumber( id ) or -1 )]
end

function RfsBiomeMap.solidTilePath( fillId )
	local a = RfsBiomeMap.tileAbbr( fillId )
	if not a then
		return nil
	end
	return TILE_CC .. "Solid" .. a .. ".png"
end

local function edgeSuffix( mask )
	local parts = {}
	if mask % 2 >= 1 then parts[#parts + 1] = "N" end
	if math.floor( mask / 2 ) % 2 >= 1 then parts[#parts + 1] = "E" end
	if math.floor( mask / 4 ) % 2 >= 1 then parts[#parts + 1] = "S" end
	if math.floor( mask / 8 ) % 2 >= 1 then parts[#parts + 1] = "W" end
	return table.concat( parts, "_" )
end

--- Shoreline tiles only: land/coast cells that touch water get Wa* edge art.
--- Water stays solid (never FoWa / MeWa — those looked "inverted").
--- Land–land biome edges stay solid (no FoMo curves on every border).
function RfsBiomeMap.tileTexture( ids, wx, wy, x0, x1, y0, y1 )
	local fill = ids[wy] and ids[wy][wx]
	if fill == nil then
		return nil
	end
	local fillA = RfsBiomeMap.tileAbbr( fill )
	if not fillA then
		return RfsBiomeMap.solidTilePath( 9 )
	end
	-- Ocean / lake: flat blue only.
	if fill == 0 then
		return TILE_CC .. "SolidWa.png"
	end
	local n = RfsBiomeMap.neighborId( ids, wx, wy, 0, 1, x0, x1, y0, y1 )
	local e = RfsBiomeMap.neighborId( ids, wx, wy, 1, 0, x0, x1, y0, y1 )
	local s = RfsBiomeMap.neighborId( ids, wx, wy, 0, -1, x0, x1, y0, y1 )
	local w = RfsBiomeMap.neighborId( ids, wx, wy, -1, 0, x0, x1, y0, y1 )
	local mask = 0
	local function consider( nid, bit )
		-- Only water edges get a curve into this land/coast cell.
		if nid == 0 then
			mask = mask + bit
		end
	end
	consider( n, 1 )
	consider( e, 2 )
	consider( s, 4 )
	consider( w, 8 )
	if mask == 0 then
		return TILE_CC .. "Solid" .. fillA .. ".png"
	end
	local var = ( wx * 7 + wy * 13 ) % 2 + 1
	return TILE_CC .. "Wa" .. fillA .. tostring( var ) .. "_" .. edgeSuffix( mask ) .. ".png"
end

print( "[RFS] RfsBiomeMap v10 — shoreline curves only (water solid)" )
return RfsBiomeMap
