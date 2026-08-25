-- RfsBiomeMap.lua — stylized biome ids for BigMap / MinimapHud (no DLL).
-- Uses terrain flags + poi_names labels (autumn / lake / mountain).
-- BigMap paints flat colours (Xaero-inspired). Coast is derived from neighbors.

RfsBiomeMap = RfsBiomeMap or {}

local NILUUID = "00000000000000000000000000000000"
local LID = "29c99287-1213-48c7-9471-19a4a5c12247"

RfsBiomeMap.SOLID = true
RfsBiomeMap.SOLID_MINIMAP = false
RfsBiomeMap.SINGLE_CELL_MINIMAP = true

-- Paint ids: 0 water, 1-8 biomes, 9 unknown, 10 coast (derived).
RfsBiomeMap.COLORS = {
	[0]  = "0.14 0.38 0.82", -- Ocean / lake (clear blue)
	[1]  = "0.42 0.76 0.30", -- Meadow
	[2]  = "0.16 0.46 0.18", -- Forest
	[3]  = "0.76 0.70 0.36", -- Farmland
	[4]  = "0.90 0.58 0.16", -- Autumn
	[5]  = "0.88 0.80 0.50", -- Desert
	[6]  = "0.26 0.24 0.22", -- Burned
	[7]  = "0.50 0.55 0.40", -- spare
	[8]  = "0.58 0.60 0.64", -- Mountain (stone grey — not blue)
	[9]  = "0.38 0.40 0.36", -- Unknown
	[10] = "0.72 0.68 0.42", -- Coast (sandy shore next to water)
}

RfsBiomeMap.LEGEND = {
	{ id = 0,  label = "Water",    color = RfsBiomeMap.COLORS[0] },
	{ id = 10, label = "Coast",    color = RfsBiomeMap.COLORS[10] },
	{ id = 1,  label = "Meadow",   color = RfsBiomeMap.COLORS[1] },
	{ id = 2,  label = "Forest",   color = RfsBiomeMap.COLORS[2] },
	{ id = 3,  label = "Farmland", color = RfsBiomeMap.COLORS[3] },
	{ id = 4,  label = "Autumn",   color = RfsBiomeMap.COLORS[4] },
	{ id = 5,  label = "Desert",   color = RfsBiomeMap.COLORS[5] },
	{ id = 6,  label = "Burned",   color = RfsBiomeMap.COLORS[6] },
	{ id = 8,  label = "Mountain", color = RfsBiomeMap.COLORS[8] },
}

local autumnUids, lakeUids, mountainUids = nil, nil, nil

local function stripDashes( s )
	return ( tostring( s ):gsub( "%-", "" ) )
end

local function ensureTags()
	if autumnUids then
		return
	end
	autumnUids, lakeUids, mountainUids = {}, {}, {}
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
			print( "[RFS] RfsBiomeMap tags: autumn/lake/mountain uids loaded" )
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
	if autumnUids[uidStr] then
		return 4
	end
	if mountainUids[uidStr] then
		return 8
	end
	local flags = ( td.flags and td.flags[wy] and td.flags[wy][wx] ) or 0
	local t = math.floor( flags / 4096 ) % 16
	-- Flag biome 8 is the cyan shelf in the old atlas (= ocean rim), NOT stone.
	-- Treat as water; true mountains come only from mountain-labeled POIs above.
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

print( "[RFS] RfsBiomeMap v4 — flag8=water; mountains from labels only" )
return RfsBiomeMap
