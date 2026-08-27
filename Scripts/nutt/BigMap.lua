-- World Map: big map screen (M4 MVP). Interactive fullscreen world map on
-- Vendored into Remastered Framework Survival with permission. Credit: Nutt
-- (Steam Workshop 3780282057).
-- the mini/big atlas tiers with pan/zoom buttons, POI labels and
-- click-to-set-waypoint. This file only defines the BigMap module; the gui
-- is owned by MinimapHud (its class receives the onClick callbacks) which
-- dofile()s this and delegates. Opened with Q while holding the GPS tool.
--
-- Engine rules honored (see auto-memory minimap-workshop-mod):
-- clicks need NeedMouse=true on EVERY ancestor; children clip to the direct
-- parent rect (the viewport panel crops map cells for free); ImageResource
-- is fixed per widget (pool per atlas resource, toggle Visible); onClickData
-- is runtime-mutable (vanilla LogBook does it).

BigMap = {}

-- jsonGui ImageTexture / IconMap do not resolve $CONTENT_DATA (blank tiles/icons).
local CC = "$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247"
local NILUUID = "00000000000000000000000000000000"

-- big tier bakes only r0; cell rotation r (90 deg CCW steps) is applied via
-- RotatingSkinAngle. Sign unverified in-game: if close-up tiles look rotated
-- the wrong way, flip ROTSIGN.
local ROTSIGN = -1
-- CONTINUOUS zoom (Eric 8/8): scale = px per cell, wheel steps 1.15x.
-- mini tier (baked rotations) below MINI_MAX, big tier (r0+RotatingSkin)
-- above. Pool caps sized for the worst case at MINSCALE with the
-- biome-fallback overflow redirect.
local MINSCALE, MAXSCALE = 8, 110
-- Default open zoom (px/cell). Lower = more world visible.
local DEFAULT_SCALE = 16
local MARKER = 22
local POILABELS = 24
local BM_UI_REV = 26
local LEGEND_W = 188
local INFO_W = 188
local POI_ICON_CAP = 256
local MARK_ROWS = 7
-- Beacon-derived PNG tiles (scaled); ImageTexture scales correctly — BeaconIconMap
-- ImageBox clips the 66px sheet cell and looks stuck in the corner.
local HOME_BLUE = "0.31 0.42 1.0" -- ~BEACON_COLORS[1] 4F6CFF
local TEX_HOME = "rfs_bcn_home_b1.png"
-- Top filter row (under north pan): icon-only buttons.
local POI_CATS = {
	{ key = "mines", cap = "Mine/Lab", tex = "rfs_bcn_mine_b1.png", dot = "orange" },
	{ key = "warehouses", cap = "Warehouse", tex = "rfs_bcn_gear_b1.png", dot = "yellow" },
	{ key = "ruins", cap = "Ruin", tex = "rfs_bcn_ruin_b1.png", dot = "red" },
	{ key = "farms", cap = "Farm", tex = "rfs_bcn_flower_b1.png", dot = "green" },
	{ key = "chem", cap = "Chem/Oil", tex = "rfs_bcn_bang_b1.png", dot = "blue" },
	{ key = "hideout", cap = "Hideout", tex = "rfs_bcn_farmer_b1.png", dot = "orange" },
}

-- Survival grow-lab overworld entrance tile UUIDs (6 unique entrance tiles;
-- wiki lists Growlab 1–7 — some seeds reuse a tile type). These ARE the
-- Grow Labs, not mines.
local GROWLAB_UUID = {
	["e70e6ba129a340a49ec3cc2ed60a69c9"] = true, -- dungeon quest
	["d159bbf67b8740738da7c6cc3b85e4b5"] = true, -- entrance / desert 256_07
	["312e8d1cde9c479d861acace1cb480f7"] = true, -- burnt forest 256_03
	["b5b956c1bab04bbeabb0e0ab8d3f1fab"] = true, -- forest 256_04
	["08f0037b92334fe8b7e1c1a0c4a2913b"] = true, -- chemical
	["8e1538ae61694053b9aed80258c6fb3b"] = true, -- water
}

-- Real underground / excavation access (not Grow Lab entrances).
local MINE_ENTRANCE_UUID = {
	["3d8544c664394fa498f0ca6d172af467"] = true, -- overworld→underground elevator
}

local function truncLabel( s, n )
	s = tostring( s or "" )
	if #s <= n then return s end
	return string.sub( s, 1, n - 3 ) .. "..."
end

-- Drill-filter subtype: Grow Lab vs real mine/elevator entrance.
local function poiMineKind( label, uid )
	local id = ( string.gsub( tostring( uid or "" ), "%-", "" ) )
	if GROWLAB_UUID[id] then return "growlab" end
	if MINE_ENTRANCE_UUID[id] then return "mine" end
	local l = string.lower( tostring( label or "" ) )
	if string.find( l, "growlab", 1, true ) or string.find( l, "grow lab", 1, true ) then
		return "growlab"
	end
	-- Every minidungeon overworld entrance tile is a Grow Lab.
	if string.find( l, "minidungeon", 1, true )
		and string.find( l, "entrance", 1, true ) then
		return "growlab"
	end
	if string.find( l, "elevator", 1, true )
		or string.find( l, "excavation", 1, true )
		or string.find( l, "mine entrance", 1, true ) then
		return "mine"
	end
	return nil
end

local function poiCatFromLabel( label, uid )
	local id = ( string.gsub( tostring( uid or "" ), "%-", "" ) )
	if GROWLAB_UUID[id] then return "mines" end
	if MINE_ENTRANCE_UUID[id] then return "mines" end
	local l = string.lower( tostring( label or "" ) )
	if string.find( l, "minidungeon", 1, true )
		or ( string.find( l, "dungeon", 1, true ) and string.find( l, "entrance", 1, true ) )
		or string.find( l, "growlab", 1, true )
		or string.find( l, "grow lab", 1, true )
		or string.find( l, "mine entrance", 1, true )
		or string.find( l, "overworld to underground", 1, true )
		or ( string.find( l, "excavation", 1, true ) and string.find( l, "island", 1, true ) ) then
		return "mines"
	end
	if string.find( l, "warehouse", 1, true ) then return "warehouses" end
	if string.find( l, "ruin", 1, true ) then return "ruins" end
	if string.find( l, "farming patch", 1, true ) then return "farms" end
	if string.find( l, "chemical plant", 1, true )
		or string.find( l, "schematic station", 1, true )
		or string.find( l, "chemical lake", 1, true )
		or string.find( l, "oil lake", 1, true )
		or string.find( l, "oil pool", 1, true ) then
		return "chem"
	end
	if string.find( l, "hideout", 1, true ) then return "hideout" end
	return nil
end

local function poiDisplayLabel( a )
	if a and a.mineKind == "growlab" then return "Grow Lab" end
	if a and a.mineKind == "mine" then return "MINE" end
	if a and a.cat == "mines" then return "Grow Lab" end
	return truncLabel( a and a.label, 22 )
end

local function poiDotForKey( key )
	for _, c in ipairs( POI_CATS ) do
		if c.key == key then return c.dot end
	end
	return "red"
end

local function poiDotForAnchor( a )
	local l = string.lower( tostring( a and a.label or "" ) )
	if string.find( l, "oil lake", 1, true ) or string.find( l, "oil pool", 1, true ) then
		return "orange"
	end
	if a and a.mineKind == "growlab" then
		return "green"
	end
	if a and a.mineKind == "mine" then
		return "orange"
	end
	if a and a.cat == "mines" then
		return "green"
	end
	return poiDotForKey( a and a.cat )
end

-- Short "what to expect" copy for the hover tip.
local function poiExpect( label, cat, a )
	local l = string.lower( tostring( label or "" ) )
	local kind = a and a.mineKind
	if string.find( l, "oil lake", 1, true ) or string.find( l, "oil pool", 1, true ) then
		return "Oil site", "Harvest crude oil for fuel and crafting."
	end
	if string.find( l, "chemical lake", 1, true ) then
		return "Chemical lake", "Toxic water — chem resources nearby. Caution."
	end
	if string.find( l, "chemical plant", 1, true ) then
		return "Chemical plant", "Industrial site. Expect chem loot and hazards."
	end
	if string.find( l, "schematic station", 1, true ) then
		return "Schematic station", "Unlock crafting recipes here."
	end
	if kind == "growlab" or ( cat == "mines" and kind ~= "mine" ) then
		return "Grow Lab", "Underground grow lab. Keyed rooms, bots, and loot."
	end
	if kind == "mine" then
		return "MINE", "Underground / excavation access."
	end
	if cat == "warehouses" then
		return "Warehouse", "Large loot run. Expect farmbots and locked rooms."
	end
	if cat == "ruins" then
		return "Ruin", "Overworld ruin. Scrap, bots, and side paths."
	end
	if cat == "farms" then
		return "Farming patch", "Soil / crop area for planting."
	end
	if cat == "hideout" then
		return "Hideout", "Trader farmer. Schematics and trades."
	end
	return truncLabel( label, 22 ), "Point of interest on this seed."
end
local TIERS = {
	{ px = 32, tier = "mini" },
}
-- SOLID map paints WhiteSkin flats (Xaero-ish). Atlas cell pools only for
-- non-solid fallback. dims = legend filter; shades = hillshade.
local POOLCAP = {
	-- Keep total widgets near the known-good ~6k range (dr flood broke at ~10k).
	{ per = 200, roads = 500, dims = 1200, flats = 1600, shades = 1200,
	  tiles = 1800 },
}
local POOL_BUILD_STEP = 96
local DRAGEND = 0.25

local function stripDashes(s)
	return (string.gsub(s, "%-", ""))
end

-- Map title. Release shows the public VERSION only (Eric's call); the dev copy
-- adds DEV and the internal BUILD, so a screenshot from the local test mod can
-- never be mistaken for the Workshop one. Read g_wmFlags at call time - see
-- Scripts/Flags.lua.
local function titleFor(c)
	local t = "WORLD MAP  v" .. tostring(c.version or "?")
	if g_wmFlags and g_wmFlags.DEV then
		t = t .. "  DEV b" .. tostring(c.build or "?")
	end
	return t
end

local function W(name, typ, skin, x, y, w, h, extra)
	local t = { Childs = {}, Name = name, Type = typ, Skin = skin,
	            NeedKey = false, NeedMouse = true, Visible = true,
	            x = x, y = y, width = w, height = h }
	if extra then for k, v in pairs(extra) do t[k] = v end end
	return t
end

-- Must be after local W. Scaled PNG tiles (not BeaconIconMap — that clips).
local function bcnTex( name, x, y, sz, file, colour )
	return W( name, "ImageBox", "ImageBox", x, y, sz, sz, {
		ImageTexture = CC .. "/Gui/" .. file,
		Colour = colour or "1 1 1",
		NeedMouse = false })
end

-- raw event logging (bm_events.json, capped ring buffer)
local function evlog(hud, tag, a, b, c2, d)
	local c = hud.cl
	c.bmLog = c.bmLog or {}
	local s = tag
	for _, v in ipairs({ a, b, c2, d }) do
		s = s .. " " .. type(v) .. "="
			.. tostring(type(v) == "table" and (v.Name or "?") or v)
	end
	c.bmLog[#c.bmLog + 1] = s
	if #c.bmLog > 80 then table.remove(c.bmLog, 1) end
	pcall(sm.json.save, { events = c.bmLog }, CC .. "/bm_events.json")
end

-- ------------------------------------------------------------- resolve -----
-- frame lookup for a world cell on a tier; nil = water/out of bounds (the
-- water backdrop shows through). Returns frameInfo, flags, isRealImagery.
function BigMap.resolve(hud, wx, wy, tierName)
	if type( RfsBiomeMap ) ~= "table" then
		pcall( function()
			dofile( "$CONTENT_DATA/Scripts/game/RfsBiomeMap.lua" )
		end )
		if type( RfsBiomeMap ) ~= "table" then
			pcall( function()
				dofile( "$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247/Scripts/game/RfsBiomeMap.lua" )
			end )
		end
	end
	-- Solid biome field (no atlas road collage).
	if type( RfsBiomeMap ) == "table" and RfsBiomeMap.SOLID then
		return RfsBiomeMap.resolveFrame( hud.cl.td, hud.cl.atlas, wx, wy, tierName or "mini" )
	end
	local td = hud.cl.td
	local b = td.bounds
	if wx < b.xMin or wx > b.xMax or wy < b.yMin or wy > b.yMax then return nil end
	local uidRow = td.uid[wy]
	local uid = uidRow and uidRow[wx]
	local uidStr = uid and stripDashes(tostring(uid)) or NILUUID
	if uidStr == NILUUID then return nil end
	local flags = (td.flags and td.flags[wy] and td.flags[wy][wx]) or 0
	local rot = (td.rotation and td.rotation[wy] and td.rotation[wy][wx]) or 0
	local xo = (td.xOffset and td.xOffset[wy] and td.xOffset[wy][wx]) or 0
	local yo = (td.yOffset and td.yOffset[wy] and td.yOffset[wy][wx]) or 0
	local atlas = hud.cl.atlas
	local t = math.floor(flags / 4096) % 16
	if tierName == "mini" then
		local key = uidStr .. "_" .. xo .. "_" .. yo .. "_r" .. rot
		local hit = atlas.mini[key]
		if hit then return { res = hit.res, name = key, rot = 0 }, flags, true end
		-- no-biome tiles tint meadow-green, not dark "unknown" (Eric v39)
		local fb = (t >= 1 and t <= 8) and ("biome_" .. t .. "_r0") or "biome_1_r0"
		local h2 = atlas.mini[fb] or atlas.mini["unknown_r0"]
		if not h2 then return nil end
		return { res = h2.res, name = fb, rot = 0 }, flags, false
	else
		local key = uidStr .. "_" .. xo .. "_" .. yo
		local hit = atlas.big[key]
		if hit then return { res = hit.res, name = key, rot = rot }, flags, true end
		local fb = (t >= 1 and t <= 8) and ("biome_" .. t) or "unknown"
		local h2 = atlas.big[fb] or atlas.big["unknown"]
		if not h2 then return nil end
		return { res = h2.res, name = fb, rot = 0 }, flags, false
	end
end

-- ------------------------------------------------------- pool build queue --
local function firstOfAtlas(atlas)
	local firstOf = { mini = {}, big = {}, roads = {} }
	for tier, tbl in pairs({ mini = atlas.mini, big = atlas.big, roads = atlas.roads }) do
		for name, v in pairs(tbl) do
			if not firstOf[tier][v.res] or name < firstOf[tier][v.res] then
				firstOf[tier][v.res] = name
			end
		end
	end
	return firstOf
end

function BigMap.queuePoolBuild(hud, firstOf)
	local bm = hud.cl.bm
	if bm.poolReady or bm.poolQueue then return end
	bm.poolQueue = {}
	bm.poolBuildIdx = 1
	bm.pools = {}
	bm.widgetByName = bm.widgetByName or {}
	local solid = type( RfsBiomeMap ) == "table" and RfsBiomeMap.SOLID
	local useTiles = solid and RfsBiomeMap.TILES
	local roadPaint = solid and RfsBiomeMap.ROADS
	for ti, T in ipairs(TIERS) do
		local pool = {
			byRes = {}, roads = {}, dims = {}, flats = {}, shades = {},
			tiles = {},
			used = {}, roadsUsed = 0, dimsUsed = 0, flatsUsed = 0, shadesUsed = 0,
			tilesUsed = 0,
		}
		bm.pools[ti] = pool
		if solid then
			for i = 1, ( POOLCAP[ti].flats or 0 ) do
				bm.poolQueue[#bm.poolQueue + 1] = { kind = "flat", ti = ti, T = T, i = i }
			end
			for i = 1, ( POOLCAP[ti].shades or 0 ) do
				bm.poolQueue[#bm.poolQueue + 1] = { kind = "shade", ti = ti, T = T, i = i }
			end
			for i = 1, ( POOLCAP[ti].dims or 0 ) do
				bm.poolQueue[#bm.poolQueue + 1] = { kind = "dim", ti = ti, T = T, i = i }
			end
			if useTiles then
				for i = 1, ( POOLCAP[ti].tiles or 0 ) do
					bm.poolQueue[#bm.poolQueue + 1] = { kind = "tile", ti = ti, T = T, i = i }
				end
			end
			if roadPaint then
				for i = 1, ( POOLCAP[ti].roads or 0 ) do
					bm.poolQueue[#bm.poolQueue + 1] = { kind = "road", ti = ti, T = T, i = i }
				end
			end
		else
			for res, first in pairs(firstOf[T.tier]) do
				for i = 1, POOLCAP[ti].per do
					bm.poolQueue[#bm.poolQueue + 1] = {
						kind = "cell", ti = ti, T = T, res = res, first = first, i = i }
				end
			end
			for i = 1, POOLCAP[ti].roads do
				bm.poolQueue[#bm.poolQueue + 1] = { kind = "road", ti = ti, T = T, i = i }
			end
		end
	end
end

function BigMap.flushPoolBuild(hud, budget)
	local bm = hud.cl.bm
	if not bm or not bm.poolQueue or not bm.view then return bm and bm.poolReady end
	budget = budget or POOL_BUILD_STEP
	local n = 0
	while bm.poolBuildIdx <= #bm.poolQueue and n < budget do
		local q = bm.poolQueue[bm.poolBuildIdx]
		bm.poolBuildIdx = bm.poolBuildIdx + 1
		n = n + 1
		local ti, T = q.ti, q.T
		local pool = bm.pools[ti]
		if q.kind == "flat" then
			local cw = W("bmf" .. ti .. "_" .. q.i, "Widget", "WhiteSkin",
				0, 0, T.px, T.px, {
					Colour = "0.3 0.3 0.3", Alpha = 1, Visible = false,
					NeedToolTip = true, onClick = "cl_bm_cell",
					onDrag = "cl_bm_curs", onToolTip = "cl_bm_hover" })
			bm.view.Childs[#bm.view.Childs + 1] = cw
			pool.flats[q.i] = cw
			bm.widgetByName[cw.Name] = cw
		elseif q.kind == "shade" then
			local ov = W("bms" .. ti .. "_" .. q.i, "Widget", "WhiteSkin",
				0, 0, T.px, T.px,
				{ Colour = "0 0 0", Alpha = 0.2, Visible = false, NeedMouse = false })
			bm.view.Childs[#bm.view.Childs + 1] = ov
			pool.shades[q.i] = ov
		elseif q.kind == "dim" then
			local ov = W("bmd" .. ti .. "_" .. q.i, "Widget", "WhiteSkin",
				0, 0, T.px, T.px,
				{ Colour = "0 0 0", Alpha = 0.55, Visible = false, NeedMouse = false })
			bm.view.Childs[#bm.view.Childs + 1] = ov
			pool.dims[q.i] = ov
		elseif q.kind == "cell" then
			local lst = pool.byRes[q.res]
			if not lst then lst = {}; pool.byRes[q.res] = lst end
			local extra = { ImageResource = q.res, ImageGroup = q.res,
				ImageName = q.first, Visible = false, NeedToolTip = true,
				onClick = "cl_bm_cell", onDrag = "cl_bm_curs", onToolTip = "cl_bm_hover" }
			local skin = "ImageBox"
			if T.rotskin then
				skin = "RotatingSkin"
				extra.RotatingSkinAngle = 0.0
				extra.RotatingSkinCenterX = math.floor(T.px / 2)
				extra.RotatingSkinCenterY = math.floor(T.px / 2)
			end
			local cw = W("bmc" .. ti .. "_" .. q.res .. "_" .. q.i, "ImageBox", skin,
				0, 0, T.px, T.px, extra)
			bm.view.Childs[#bm.view.Childs + 1] = cw
			lst[q.i] = cw
			bm.widgetByName[cw.Name] = cw
		elseif q.kind == "tile" then
			local cw = W( "bmtile" .. ti .. "_" .. q.i, "ImageBox", "ImageBox",
				0, 0, T.px, T.px, {
					ImageTexture = CC .. "/Gui/MapTiles/SolidMe.png",
					Colour = "1 1 1",
					Visible = false, NeedToolTip = true,
					onClick = "cl_bm_cell", onDrag = "cl_bm_curs", onToolTip = "cl_bm_hover" })
			bm.view.Childs[#bm.view.Childs + 1] = cw
			pool.tiles[q.i] = cw
			bm.widgetByName[cw.Name] = cw
		else
			local ov = W("bmo" .. ti .. "_" .. q.i, "ImageBox", "ImageBox",
				0, 0, T.px, T.px,
				{ ImageResource = "MMap_roads_0_0", ImageGroup = "MMap_roads_0_0",
				  ImageName = "road_1", Visible = false, NeedMouse = false })
			bm.view.Childs[#bm.view.Childs + 1] = ov
			pool.roads[q.i] = ov
		end
	end
	if bm.poolBuildIdx > #bm.poolQueue then
		bm.poolQueue = nil
		bm.poolReady = true
		return true
	end
	return false
end

function BigMap.prebuildStep(hud)
	local c = hud.cl
	if not (c and c.ready and c.atlas) then return end
	if c.bm and (c.bm.open or c.bm.poolReady) then return end
	if not c.vw then
		local okv, a, b2 = pcall(sm.jsonGui.getViewSize)
		if okv and type(a) == "number" then
			c.vw, c.vh = a, b2 or 720
		else
			c.vw, c.vh = 1280, 720
		end
	end
	BigMap.build(hud, POOL_BUILD_STEP)
end

-- --------------------------------------------------------------- build -----
function BigMap.build(hud, poolBudget)
	local c = hud.cl
	local bm = c.bm or {}
	c.bm = bm
	-- Pack sync can leave an old chrome tree in memory — rebuild legend/layout.
	if ( bm.uiRev or 0 ) ~= BM_UI_REV then
		bm.root = nil
		bm.root2 = nil
		bm.poolReady = false
		bm.poolQueue = nil
		bm.pools = nil
		bm.anchors = nil
		bm.scale = DEFAULT_SCALE
		bm.uiRev = BM_UI_REV
	end
	if bm.poolReady and bm.gui and bm.root then
		BigMap.syncWpUi(hud)
		return true
	end
	-- EXACT T10-proven recipe (SpikeAuto.lua:215/327 - clicks dispatched to
	-- a tool script): these options + gui:open() after the tree is built +
	-- per-frame render. WITHOUT open() the engine draws widgets and hover
	-- states but never binds the interaction session - buttons highlight,
	-- zero callbacks (v19-v23 saga).
	-- hidesHotbar: the waypoint row lives in the strip below the map (Eric
	-- v66) which the vanilla hotbar occupies - hide it while the map is open
	if not bm.gui then
		local ok, gui = pcall(sm.jsonGui.createGui,
			{ isHud = false, isInteractive = true, needsCursor = true,
			  hidesHotbar = true })
		if not ok then
			sm.gui.chatMessage("[minimap] big map createGui failed: " .. tostring(gui))
			return false
		end
		bm.gui = gui
	end
	-- BUG-4 (Eric 8/11): after CLEAR, reopening the map showed a pin with no
	-- waypoint set and CLEAR greyed out - and it only went away after a full
	-- set-then-clear cycle. That is the v34 signature exactly: engine widget
	-- state is cached BY NAME across gui destroy/recreate, and a re-created
	-- widget whose props already match the cached ones never has them applied.
	-- v35 fixed it for map cells with generation-stamped names; the pins and
	-- ghosts kept fixed names, so they kept the bug. One generation per map
	-- session makes every session's pin a brand-new widget. Flagged: it is a
	-- diagnosis-led guess until the wpui events confirm it (see BUGS.md).
	local vw, vh = c.vw or 1280, c.vh or 720
	bm.tierIdx = bm.tierIdx or 1

	if not bm.root then
		local gen = ((c.wpGen or 0) + 1) % 8
		c.wpGen = gen
		bm.gsfx = (g_wmFlags and g_wmFlags.WP_FRESH_NAMES) and ("_g" .. gen) or ""

		-- Layout: legend (left) | pan | map | pan | info (right).
		-- Top chrome = title row + north pan + POI filter row (above the map).
		local pan = 48
		local side = 16
		local POI_ROW_H = 42
		local topChrome = 58 + POI_ROW_H
		local botChrome = 52
		local vx = side + LEGEND_W + 8 + pan
		local vy = topChrome
		local VW = vw - vx - pan - 8 - INFO_W - side
		local VH = vh - topChrome - botChrome
		if VW < 400 then VW = math.max(320, vw - 200 - INFO_W) end
		if VH < 280 then VH = math.max(240, vh - 120) end
		bm.poiRowH = POI_ROW_H
		-- Outer frame size (chrome + pans); inner view is inset for rounded look.
		local frameW, frameH = VW, VH
		local inset = 8
		bm.frameW, bm.frameH = frameW, frameH
		bm.infoX = vx + frameW + pan + 8
		bm.infoY = vy
		bm.infoH = frameH

		-- NeedMouse=true ONLY on clickables + their ancestor chain (root/view/
		-- cells/buttons): any other pick-enabled widget SWALLOWS the picks -
		-- v19's fullscreen backdrop ate every click (buttons dead, map stuck)
		local root = W("BMRoot", "Widget", "PanelEmpty", 0, 0, vw, vh)
		local back = W("BMBack", "Widget", "WhiteSkin", 0, 0, vw, vh,
			{ Colour = "0 0 0", Alpha = 0.8, NeedMouse = false })
		local view = W("BMView", "Widget", "PanelEmpty",
			vx + inset, vy + inset, frameW - inset * 2, frameH - inset * 2, {
			onMouseWheel = "cl_bm_wheel" })
		-- Rounded dark chrome behind the map (inventory skins stretch with soft corners).
		root.Childs = {
			back,
			W( "BMMapChromeT", "Widget", "BackgroundDarkRoundedUpperRight",
				vx, vy, frameW, math.floor( frameH / 2 ), { NeedMouse = false } ),
			W( "BMMapChromeB", "Widget", "BackgroundDarkRoundedLowerLeft",
				vx, vy + math.floor( frameH / 2 ), frameW, frameH - math.floor( frameH / 2 ),
				{ NeedMouse = false } ),
			view,
		}
		bm.view = view
		bm.VW = frameW - inset * 2
		bm.VH = frameH - inset * 2
		VW, VH = bm.VW, bm.VH
		bm.vx, bm.vy = vx + inset, vy + inset
		-- Keep outer origin for chrome-aligned pans / title.
		bm.fx, bm.fy = vx, vy
		bm.frameW, bm.frameH = frameW, frameH

		-- water / ocean backdrop
		local solidPaint = type( RfsBiomeMap ) == "table" and RfsBiomeMap.SOLID
		if solidPaint then
			bm.water = W("BMWater", "Widget", "WhiteSkin",
				0, 0, VW, VH, {
					Colour = RfsBiomeMap.colorForId( 0 ), Alpha = 1, NeedMouse = false })
		else
			local waterRes = c.atlas.mini["water_r0"].res
			bm.water = W("BMWater", "ImageBox", "ImageBox",
				0, 0, VW, VH, { ImageResource = waterRes, ImageGroup = waterRes,
				  ImageName = "water_r0", NeedMouse = false })
		end
		view.Childs[#view.Childs + 1] = bm.water
	bm.poiLabels = {}
	for i = 1, POILABELS do
		local tb = W("bmpoi" .. i, "TextBox", "TextBox", 0, 0, 140, 18,
			{ Caption = "", FontName = "SM_HeaderTiny", TextAlign = "Center",
			  TextShadow = true, TextShadowColour = "0 0 0", Visible = false,
			  NeedMouse = false })
		view.Childs[#view.Childs + 1] = tb
		bm.poiLabels[i] = tb
	end

	-- player + waypoint markers (children of the viewport -> clipped)
	bm.marker = W("BMPlayer", "ImageBox", "RotatingSkin", 0, 0, MARKER, MARKER,
		{ ImageTexture = CC .. "/Gui/arrow.png", RotatingSkinAngle = 0.0,
		  RotatingSkinCenterX = math.floor(MARKER / 2),
		  RotatingSkinCenterY = math.floor(MARKER / 2), Visible = false,
		  NeedMouse = false })
	view.Childs[#view.Childs + 1] = bm.marker
	-- waypoint pins, one per color (Visible-toggled; the active pin is
	-- CLICKABLE - clicking the pin removes the waypoint, so it keeps
	-- NeedMouse and routes through the button handler by name)
	bm.wpPins = {}
	for _, col in ipairs(Waypoint.COLORS) do
		local p = W("BMWp_" .. col .. bm.gsfx, "ImageBox", "ImageBox", 0, 0, 20, 28,
			{ ImageTexture = CC .. "/Gui/gps_marker_" .. col .. "_b1.png",
			  Visible = false, onClick = "cl_bm_btn" })
		view.Childs[#view.Childs + 1] = p
		bm.wpPins[col] = p
	end
	-- live placement ghost: while the button is held and moving over the
	-- map (the only time the engine reports cursor coords), the active
	-- color's pin follows the cursor - release drops the waypoint exactly
	-- there. Makes press-drag-release the designed precision gesture.
	bm.wpGhost = {}
	for _, col in ipairs(Waypoint.COLORS) do
		local g = W("BMWpG_" .. col .. bm.gsfx, "ImageBox", "ImageBox", 0, 0, 20, 28,
			{ ImageTexture = CC .. "/Gui/gps_marker_" .. col .. "_b1.png",
			  Visible = false, NeedMouse = false })
		view.Childs[#view.Childs + 1] = g
		bm.wpGhost[col] = g
	end

	-- chrome (CLICKS-ONLY FINAL): title + buttons; pan buttons carry in-game
	-- arrow art (vanilla beacon glyph, 4 rotations) as non-pick children
	local function btn(name, cap, x, y, w2, skin)
		return W(name, "Button", "StyledButtonLarge", x, y, w2, 48,
			{ Caption = cap, FontName = "SM_Button", TextAlign = "Center",
			  onClick = "cl_bm_btn" })
	end
	local function btnPan(name, art, x, y)
		local b = W(name, "Button", "StyledButtonLarge", x, y, 48, 48,
			{ Caption = "", onPressed = "cl_bm_bdown", onReleased = "cl_bm_bup" })
		b.Childs = { W(name .. "i", "ImageBox", "ImageBox", 8, 8, 32, 32,
			{ ImageTexture = CC .. "/Gui/" .. art, NeedMouse = false }) }
		return b
	end
	root.Childs[#root.Childs + 1] = W("BMTitle", "TextBox", "TextBox",
		vx, 14, math.min(360, frameW - 460), 32, {
		  Caption = titleFor(c),
		  FontName = "SM_HeaderLarge_Medium",
		  TextAlign = "Left", TextShadow = true, NeedMouse = false })
	-- Top chrome: north pan centered; MINIMAP immediately LEFT of it (was
	-- overlapping when map narrowed for the right INFO panel).
	local panNX = vx + math.floor( ( frameW - 48 ) / 2 )
	local mmW = 152
	local mmb = btn( "BMMini", ( c.posIdx == 5 ) and "MINIMAP: OFF" or "MINIMAP: ON",
		panNX - 8 - mmW, 8, mmW )
	root.Childs[#root.Childs + 1] = mmb
	bm.mmBtn = mmb
	root.Childs[#root.Childs + 1] = btnPan( "BMPanN", "arrow_up_b1.png", panNX, 8 )
	-- Zoom / YOU / CLOSE stay on the right edge of the map frame.
	root.Childs[#root.Childs + 1] = btn("BMZoomOut", "-", vx + frameW - 288, 8, 48)
	root.Childs[#root.Childs + 1] = btn("BMZoomIn", "+", vx + frameW - 232, 8, 48)
	root.Childs[#root.Childs + 1] = btn("BMYou", "YOU", vx + frameW - 176, 8, 64)
	root.Childs[#root.Childs + 1] = btn("BMClose", "CLOSE [E]", vx + frameW - 104, 8, 104, "PrimaryButton")
	root.Childs[#root.Childs + 1] = btnPan("BMPanW", "arrow_left_b1.png", vx - pan, vy + math.floor((frameH - 48) / 2))
	root.Childs[#root.Childs + 1] = btnPan("BMPanE", "arrow_right_b1.png", vx + frameW, vy + math.floor((frameH - 48) / 2))
	root.Childs[#root.Childs + 1] = btnPan("BMPanS", "arrow_down_b1.png", vx + math.floor((frameW - 48) / 2), vy + frameH)

	-- POI filter row: ABOVE the map (was overlapping the viewport and vanished).
	do
		c.poiFilters = c.poiFilters or {}
		bm.poiBtns = {}
		bm.poiIconImgs = {}
		local rowY = vy - POI_ROW_H + 3
		local bw, gap = 40, 6
		local nBtn = #POI_CATS
		local total = nBtn * bw + ( nBtn - 1 ) * gap
		local rowX = vx + math.floor( ( frameW - total ) / 2 )
		for i, cat in ipairs( POI_CATS ) do
			local b = W( "BMPoi_" .. cat.key, "Button", "StyledButtonLarge",
				rowX + ( i - 1 ) * ( bw + gap ), rowY, bw, 36, {
					Caption = "", onClick = "cl_bm_btn" } )
			local ic = bcnTex( "BMPoiI_" .. cat.key, 4, 2, 32, cat.tex, "1 1 1" )
			b.Childs = { ic }
			root.Childs[#root.Childs + 1] = b
			bm.poiBtns[cat.key] = b
			bm.poiIconImgs[cat.key] = ic
		end
	end

	-- Legend panel (left): rounded inventory chrome + readable labels.
	do
		local lx, ly = side, vy
		local legH = frameH
		root.Childs[#root.Childs + 1] = W("BMLegChromeT", "Widget", "BackgroundDarkRoundedUpperRight",
			lx, ly, LEGEND_W, math.floor( legH / 2 ), { NeedMouse = false })
		root.Childs[#root.Childs + 1] = W("BMLegChromeB", "Widget", "BackgroundDarkRoundedLowerLeft",
			lx, ly + math.floor( legH / 2 ), LEGEND_W, legH - math.floor( legH / 2 ),
			{ NeedMouse = false })
		root.Childs[#root.Childs + 1] = W("BMLegTitle", "Button", "StyledButtonLarge",
			lx + 4, ly + 4, LEGEND_W - 8, 36, {
				Caption = "LEGEND", FontName = "SM_Button", TextAlign = "Center",
				NeedMouse = false })
		local rows = ( type( RfsBiomeMap ) == "table" and RfsBiomeMap.LEGEND ) or {}
		local rowY = ly + 48
		local rowH = 30
		bm.legBtns = {}
		bm.legLbs = {}
		for i, row in ipairs( rows ) do
			local b = W("BMLegPick_" .. i, "Button", "StyledButtonLarge",
				lx + 4, rowY, LEGEND_W - 8, rowH - 3, {
					Caption = "", onClick = "cl_bm_btn" })
			local col = row.color or ( RfsBiomeMap and RfsBiomeMap.colorForId( row.id ) ) or "0.5 0.5 0.5"
			local lb = W("BMLegLb_" .. i, "TextBox", "TextBox", 30, 3, LEGEND_W - 56, rowH - 9, {
				Caption = tostring( row.label or "" ),
				FontName = "SM_TextLabel", TextAlign = "Left VCenter",
				TextShadow = true, NeedMouse = false })
			b.Childs = {
				W("BMLegRim_" .. i, "Widget", "WhiteSkin", 6, 4, 20, 20, {
					Colour = "0.12 0.12 0.14", Alpha = 1, NeedMouse = false }),
				W("BMLegSw_" .. i, "Widget", "WhiteSkin", 7, 5, 18, 18, {
					Colour = col, Alpha = 1, NeedMouse = false }),
				lb,
			}
			root.Childs[#root.Childs + 1] = b
			bm.legBtns[i] = b
			bm.legLbs[i] = lb
			rowY = rowY + rowH
		end
		rowY = rowY + 10
		root.Childs[#root.Childs + 1] = W("BMLegMarkHd", "TextBox", "TextBox",
			lx + 10, rowY, LEGEND_W - 20, 18, {
				Caption = "MARKERS", FontName = "SM_HeaderTiny",
				TextAlign = "Left", TextShadow = true, NeedMouse = false })
		rowY = rowY + 20
		-- Scrollable marker directory (replaces dense POI text on the map).
		bm.markScroll = 0
		bm.markSel = nil
		local listH = MARK_ROWS * 26 + 4
		local listPanel = W( "BMMarkList", "Widget", "PanelEmpty",
			lx + 4, rowY, LEGEND_W - 8, listH, {
				NeedMouse = true, onMouseWheel = "cl_bm_wheel" } )
		listPanel.Childs = {
			W( "BMMarkListBgT", "Widget", "BackgroundDarkRoundedUpperRight",
				0, 0, LEGEND_W - 8, math.floor( listH / 2 ), { NeedMouse = false } ),
			W( "BMMarkListBgB", "Widget", "BackgroundDarkRoundedLowerLeft",
				0, math.floor( listH / 2 ), LEGEND_W - 8, listH - math.floor( listH / 2 ),
				{ NeedMouse = false } ),
		}
		bm.markRows = {}
		for i = 1, MARK_ROWS do
			local ry = 2 + ( i - 1 ) * 26
			local b = W( "BMMark_" .. i, "Button", "StyledButtonLarge",
				2, ry, LEGEND_W - 12, 24, {
					Caption = "", onClick = "cl_bm_btn" } )
			-- Light plate so black beacon glyphs stay visible on dark chrome.
			local plate = W( "BMMarkPlate_" .. i, "Widget", "WhiteSkin", 1, 1, 22, 22, {
				Colour = "0.92 0.92 0.95", Alpha = 1, NeedMouse = false } )
			local ic = bcnTex( "BMMarkI_" .. i, 2, 2, 20, "rfs_bcn_dot_b1.png", "1 1 1" )
			ic.Visible = false
			plate.Visible = false
			local lb = W( "BMMarkLb_" .. i, "TextBox", "TextBox", 26, 2, LEGEND_W - 52, 20, {
				Caption = "", FontName = "SM_TextLabel", TextAlign = "Left VCenter",
				TextShadow = true, NeedMouse = false })
			b.Childs = { plate, ic, lb }
			listPanel.Childs[#listPanel.Childs + 1] = b
			bm.markRows[i] = { btn = b, icon = ic, lb = lb, plate = plate }
		end
		root.Childs[#root.Childs + 1] = listPanel
		rowY = rowY + listH + 4
		-- Real arrow art (SM font has no ▲▼ — those rendered as boxed X).
		local upB = W( "BMMarkUp", "Button", "StyledButtonLarge",
			lx + 4, rowY, 40, 28, { Caption = "", onClick = "cl_bm_btn" } )
		upB.Childs = {
			W( "BMMarkUpI", "ImageBox", "ImageBox", 8, 2, 24, 24, {
				ImageTexture = CC .. "/Gui/arrow_up_b1.png", NeedMouse = false } )
		}
		local dnB = W( "BMMarkDn", "Button", "StyledButtonLarge",
			lx + 48, rowY, 40, 28, { Caption = "", onClick = "cl_bm_btn" } )
		dnB.Childs = {
			W( "BMMarkDnI", "ImageBox", "ImageBox", 8, 2, 24, 24, {
				ImageTexture = CC .. "/Gui/arrow_down_b1.png", NeedMouse = false } )
		}
		root.Childs[#root.Childs + 1] = upB
		root.Childs[#root.Childs + 1] = dnB
		bm.markCountLb = W( "BMMarkCnt", "TextBox", "TextBox",
			lx + 94, rowY + 4, LEGEND_W - 100, 20, {
				Caption = "", FontName = "SM_HeaderTiny",
				TextAlign = "Left", TextShadow = true, NeedMouse = false } )
		root.Childs[#root.Childs + 1] = bm.markCountLb
	end

	-- INFO panel (right): same chrome language as legend; click details live here
	-- (no floating tip over the map — that drew under tiles).
	do
		local ix = bm.infoX or ( vx + frameW + pan + 8 )
		local iy = bm.infoY or vy
		local infoH = bm.infoH or frameH
		root.Childs[#root.Childs + 1] = W( "BMInfoChromeT", "Widget", "BackgroundDarkRoundedUpperRight",
			ix, iy, INFO_W, math.floor( infoH / 2 ), { NeedMouse = false } )
		root.Childs[#root.Childs + 1] = W( "BMInfoChromeB", "Widget", "BackgroundDarkRoundedLowerLeft",
			ix, iy + math.floor( infoH / 2 ), INFO_W, infoH - math.floor( infoH / 2 ),
			{ NeedMouse = false } )
		root.Childs[#root.Childs + 1] = W( "BMInfoHd", "Button", "StyledButtonLarge",
			ix + 4, iy + 4, INFO_W - 8, 36, {
				Caption = "INFO", FontName = "SM_Button", TextAlign = "Center",
				NeedMouse = false } )
		bm.infoTitle = W( "BMInfoTitle", "TextBox", "TextBox",
			ix + 10, iy + 48, INFO_W - 20, 28, {
				Caption = "—", FontName = "SM_HeaderTiny", TextAlign = "Left",
				TextShadow = true, NeedMouse = false } )
		bm.infoBody = W( "BMInfoBody", "TextBox", "TextBox",
			ix + 10, iy + 80, INFO_W - 20, 120, {
				Caption = "Click a map marker\nor Markers list row.",
				FontName = "SM_TextLabel", TextAlign = "Left",
				TextShadow = true, NeedMouse = false } )
		bm.infoMeta = W( "BMInfoMeta", "TextBox", "TextBox",
			ix + 10, iy + 210, INFO_W - 20, 80, {
				Caption = "", FontName = "SM_HeaderTiny", TextAlign = "Left",
				TextShadow = true, NeedMouse = false } )
		root.Childs[#root.Childs + 1] = bm.infoTitle
		root.Childs[#root.Childs + 1] = bm.infoBody
		root.Childs[#root.Childs + 1] = bm.infoMeta
	end

	-- waypoint controls: farm | GAP | panS | GAP | … | home | red… | CLEAR
	-- Home sits immediately left of the red waypoint circle; pan gaps unchanged.
	local clrW = 190
	local clrX = vx + frameW - clrW
	local wpY = vy + frameH
	local panMidX = vx + math.floor( ( frameW - 48 ) / 2 )
	local gap = 28
	local homeW = 40
	local wpStride = 46
	local wpBlock = 5 * wpStride - 6
	local homeGap = 6
	local wpStart = clrX - 8 - wpBlock
	local homeX = wpStart - homeGap - homeW
	-- Keep home from eating into the south-pan clearance.
	local panRight = panMidX + 48 + gap
	if homeX < panRight then
		homeX = panRight
		wpStart = homeX + homeW + homeGap
	end
	bm.colDot = {}
	for i, col in ipairs(Waypoint.COLORS) do
		local b = W("BMWpCol_" .. col, "Button", "StyledButtonLarge",
			wpStart + (i - 1) * wpStride, wpY + 4, 40, 40,
			{ Caption = "", onClick = "cl_bm_btn" })
		local circ = W("BMWpColI_" .. col, "ImageBox", "ImageBox", 8, 8, 24, 24,
			{ ImageTexture = CC .. "/Gui/wpdot_" .. col .. "_b1.png",
			  NeedMouse = false })
		local pin = W("BMWpColP_" .. col, "ImageBox", "ImageBox", 10, 8, 19, 24,
			{ ImageTexture = CC .. "/Gui/gps_marker_" .. col .. "_b1.png",
			  NeedMouse = false, Visible = false })
		b.Childs = { circ, pin }
		bm.colDot[col] = { circ = circ, pin = pin }
		root.Childs[#root.Childs + 1] = b
	end
	local clr = W("BMWpClear", "Button", "StyledButtonLarge",
		clrX, wpY, clrW, 48,
		{ Caption = "CLEAR WAYPOINT", FontName = "SM_Button",
		  TextAlign = "Center", onClick = "cl_bm_btn" })
	bm.clearDim = W("BMWpClearDim", "Widget", "WhiteSkin", 0, 0, clrW, 48,
		{ Colour = "0 0 0", Alpha = 0.55, NeedMouse = false, Visible = true })
	clr.Childs = { bm.clearDim }
	root.Childs[#root.Childs + 1] = clr

	-- Blue home — immediately left of red wpdot.
	do
		local hb = W( "BMHome", "Button", "StyledButtonLarge",
			homeX, wpY + 4, homeW, 40, { Caption = "", onClick = "cl_bm_btn" } )
		local hic = bcnTex( "BMHomeI", 4, 4, 32, TEX_HOME, HOME_BLUE )
		hb.Childs = { hic }
		bm.homeBtn = hb
		bm.homeIcon = hic
		root.Childs[#root.Childs + 1] = hb
	end

	-- Farm seed pins: left of south pan, with a clear gap before the arrow.
	do
		local farmStride = 40
		local farmBlock = 5 * farmStride
		local farmX = panMidX - gap - farmBlock
		bm.farmBtns = {}
		for i, col in ipairs( Waypoint.COLORS ) do
			local b = W( "BMFarmCol_" .. col, "Button", "StyledButtonLarge",
				farmX + ( i - 1 ) * farmStride, wpY + 4, 36, 40,
				{ Caption = "", onClick = "cl_bm_btn" } )
			b.Childs = {
				W( "BMFarmI_" .. col, "ImageBox", "ImageBox", 6, 8, 24, 24, {
					ImageTexture = CC .. "/Gui/wpdot_" .. col .. "_b1.png",
					NeedMouse = false } )
			}
			bm.farmBtns[col] = b
			root.Childs[#root.Childs + 1] = b
		end
	end

	-- Base + farm markers inside the viewport (clickable to clear).
	bm.basePin = W( "BMBasePin" .. bm.gsfx, "ImageBox", "ImageBox", 0, 0, 32, 32, {
		ImageTexture = CC .. "/Gui/" .. TEX_HOME, Colour = HOME_BLUE,
		Visible = false, onClick = "cl_bm_btn" } )
	view.Childs[#view.Childs + 1] = bm.basePin
	bm.farmPins = {}
	for _, col in ipairs( Waypoint.COLORS ) do
		local p = W( "BMFarmPin_" .. col .. bm.gsfx, "ImageBox", "ImageBox", 0, 0, 20, 28, {
			ImageTexture = CC .. "/Gui/gps_marker_" .. col .. "_b1.png",
			Visible = false, onClick = "cl_bm_btn" } )
		view.Childs[#view.Childs + 1] = p
		bm.farmPins[col] = p
	end

	-- POI category icon pool (filter dots on map — hoverable for tip + list jump).
	bm.poiIcons = {}
	bm.poiIconMeta = {}
	for i = 1, POI_ICON_CAP do
		local ic = W( "BMPoiIc_" .. i, "ImageBox", "ImageBox", 0, 0, 20, 20, {
			ImageTexture = CC .. "/Gui/wpdot_red_b1.png",
			Visible = false, NeedMouse = true, NeedToolTip = true,
			onToolTip = "cl_bm_hover", onClick = "cl_bm_btn" } )
		view.Childs[#view.Childs + 1] = ic
		bm.poiIcons[i] = ic
	end

	-- Selection ring for marker-list pick (find without map text).
	bm.selRing = W( "BMSelRing" .. bm.gsfx, "ImageBox", "ImageBox", 0, 0, 22, 22, {
		ImageTexture = CC .. "/Gui/wpdot_sel_b1.png",
		Visible = false, NeedMouse = false } )
	view.Childs[#view.Childs + 1] = bm.selRing

	-- vx/vy already set to the inset view origin for cursor math.
	bm.root = root
	bm.clickMap = {}

	-- OVERLAY GUI (gui2): within-gui z-order against the tile pools is a
	-- texture-batching lottery (Eric v71: drag ghost behind some tiles) -
	-- marker/pin/ghost VISUALS get render-only copies in a HUD-layer gui
	-- that reliably draws above this screen gui (the vanilla health bar
	-- proves HUD layers > screen guis). Originals stay in the interactive
	-- gui for clicks + viewport clipping; update() mirrors positions and
	-- hides overlay copies at the viewport edge (gui2 has no clip parent).
	-- Marker details use the right INFO panel (not a floating tip).
	local ok2, gui2 = pcall(sm.jsonGui.createGui,
		{ isHud = true, isInteractive = false, needsCursor = false })
	if ok2 and gui2 then
		bm.gui2 = gui2
		local root2 = W("BMORoot", "Widget", "PanelEmpty", 0, 0, vw, vh,
			{ NeedMouse = false })
		bm.oMarker = W("BMOPlayer", "ImageBox", "RotatingSkin", 0, 0, MARKER, MARKER,
			{ ImageTexture = CC .. "/Gui/arrow.png", RotatingSkinAngle = 0.0,
			  RotatingSkinCenterX = math.floor(MARKER / 2),
			  RotatingSkinCenterY = math.floor(MARKER / 2),
			  Visible = false, NeedMouse = false })
		root2.Childs[#root2.Childs + 1] = bm.oMarker
		bm.oPins, bm.oGhosts = {}, {}
		for _, col in ipairs(Waypoint.COLORS) do
			local p2 = W("BMOWp_" .. col .. bm.gsfx, "ImageBox", "ImageBox", 0, 0, 20, 28,
				{ ImageTexture = CC .. "/Gui/gps_marker_" .. col .. "_b1.png",
				  Visible = false, NeedMouse = false })
			local g2 = W("BMOWpG_" .. col .. bm.gsfx, "ImageBox", "ImageBox", 0, 0, 20, 28,
				{ ImageTexture = CC .. "/Gui/gps_marker_" .. col .. "_b1.png",
				  Visible = false, NeedMouse = false })
			root2.Childs[#root2.Childs + 1] = p2
			root2.Childs[#root2.Childs + 1] = g2
			bm.oPins[col] = p2
			bm.oGhosts[col] = g2
		end
		bm.root2 = root2
	end
	end -- not bm.root

	if not bm.poolReady then
		if not bm.poolQueue then
			BigMap.queuePoolBuild(hud, firstOfAtlas(c.atlas))
		end
		local budget = poolBudget or 99999
		if not BigMap.flushPoolBuild(hud, budget) then
			return false
		end
	end

	-- POI anchors: any-seed - scan the CURRENT world's terrain for tiles
	-- whose uuid is in poi_names.json, anchored at subcell (0,0)
	if not bm.anchors then
		local anchors = {}
		local poi = c.poi or {}
		local td = c.td
		local b = td.bounds
		for wy = b.yMin, b.yMax do
			local row = td.uid[wy]
			local xrow = td.xOffset and td.xOffset[wy]
			local yrow = td.yOffset and td.yOffset[wy]
			if row then
				for wx = b.xMin, b.xMax do
					local uid = row[wx]
					if uid then
						local uidKey = stripDashes(tostring(uid))
						local p = poi[uidKey]
						if p and (not xrow or (xrow[wx] or 0) == 0)
						     and (not yrow or (yrow[wx] or 0) == 0) then
							local cat = poiCatFromLabel( p.label, uidKey )
							local mineKind = poiMineKind( p.label, uidKey )
							if cat == "mines" and not mineKind then
								mineKind = "growlab"
							end
							anchors[#anchors + 1] = {
								label = p.label, tier = p.tier or 1,
								sx = p.sx or 1, uid = uidKey,
								cx = wx + (p.sx or 1) / 2, cy = wy + (p.sy or 1) / 2,
								cat = cat, mineKind = mineKind }
						end
					end
				end
			end
		end
		bm.anchors = anchors
	end
	BigMap.syncWpUi(hud)
	return true
end

-- -------------------------------------------------------------- refill -----
function BigMap.refill(hud)
	local bm = hud.cl.bm
	bm.scale = math.max(MINSCALE, math.min(MAXSCALE, bm.scale or DEFAULT_SCALE))
	bm.tierIdx = 1
	local T = TIERS[bm.tierIdx]
	local px = bm.scale
	local pool = bm.pools[bm.tierIdx]
	pool.used = {}
	pool.roadsUsed = 0
	pool.dimsUsed = 0
	pool.flatsUsed = 0
	pool.shadesUsed = 0
	pool.tilesUsed = 0
	bm.clickMap = {}
	bm.placed = {}
	bm.refillCx, bm.refillCy = bm.cx, bm.cy
	local VW, VH = bm.VW, bm.VH
	local x0 = math.floor(bm.cx - VW / (2 * px)) - 1
	local x1 = math.ceil(bm.cx + VW / (2 * px)) + 1
	local y0 = math.floor(bm.cy - VH / (2 * px)) - 1
	local y1 = math.ceil(bm.cy + VH / (2 * px)) + 1
	local skipped = 0
	local solid = type( RfsBiomeMap ) == "table" and RfsBiomeMap.SOLID
	local roadPaint = solid and RfsBiomeMap.ROADS
	local useTiles = solid and RfsBiomeMap.TILES and px >= ( RfsBiomeMap.TILE_MIN_PX or 18 )
	local td = hud.cl.td
	local filt = bm.legendFilter
	local function cellDimmed( id, wx, wy )
		if filt == nil then return false end
		if type( RfsBiomeMap ) == "table" and RfsBiomeMap.cellMatchesLegend then
			return not RfsBiomeMap.cellMatchesLegend( filt, td, wx, wy, id )
		end
		return id ~= filt
	end
	local function edgeX(wx) return math.floor(VW / 2 + (wx - bm.cx) * px + 0.5) end
	local function edgeY(wy) return math.floor(VH / 2 - (wy - bm.cy) * px + 0.5) end

	-- Soft NW hillshade (skip pure water — keeps ocean clean).
	local function shadeAlpha( id, wx, wy, ww, wh )
		if id == 0 then return 0 end
		local e = RfsBiomeMap.elev( wx, wy )
		local eE = RfsBiomeMap.elev( wx + ww, wy )
		local eN = RfsBiomeMap.elev( wx, wy + wh )
		local slope = ( e - eE ) + ( e - eN )
		if slope >= 0 then
			-- lit face: mountains get a slight lighten via lower shade skip
			return 0
		end
		local a = -slope * 0.55
		if id == 8 then a = a * 1.25 end -- stronger relief on mountains
		if a < 0.06 then return 0 end
		if a > 0.38 then a = 0.38 end
		return a
	end

	local function placeOverlays( id, sx, sy, w, h, wx, wy, ww, wh )
		local sa = shadeAlpha( id, wx, wy, ww, wh )
		if sa > 0 and pool.shades and pool.shadesUsed < #pool.shades then
			pool.shadesUsed = pool.shadesUsed + 1
			local sh = pool.shades[pool.shadesUsed]
			sh.Visible = true
			sh.Alpha = sa
			sh.x = sx; sh.y = sy
			sh.width = w + 1; sh.height = h + 1
			bm.placed[#bm.placed + 1] = { w = sh, wx = wx, wy = wy, ww = ww, wh = wh, dim = true }
		end
		if filt ~= nil and cellDimmed( id, wx, wy ) and pool.dims and pool.dimsUsed < #pool.dims then
			pool.dimsUsed = pool.dimsUsed + 1
			local ov = pool.dims[pool.dimsUsed]
			ov.Visible = true
			ov.Alpha = 0.55
			ov.x = sx; ov.y = sy
			ov.width = w + 1; ov.height = h + 1
			bm.placed[#bm.placed + 1] = { w = ov, wx = wx, wy = wy, ww = ww, wh = wh, dim = true }
		end
	end

	local function assignFlat( id, sx, sy, w, h, wx, wy, ww, wh )
		ww = ww or 1
		wh = wh or 1
		if not pool.flats or pool.flatsUsed >= #pool.flats then return false end
		pool.flatsUsed = pool.flatsUsed + 1
		local cw = pool.flats[pool.flatsUsed]
		if cw and cw.Name == bm.pinName then
			if pool.flatsUsed >= #pool.flats then return false end
			pool.flatsUsed = pool.flatsUsed + 1
			cw = pool.flats[pool.flatsUsed]
		end
		bm.placed[#bm.placed + 1] = { w = cw, wx = wx, wy = wy, ww = ww, wh = wh }
		cw.Visible = true
		cw.Colour = RfsBiomeMap.colorForId( id )
		cw.Alpha = 1
		cw.x = sx; cw.y = sy
		cw.width = w + 1; cw.height = h + 1
		bm.clickMap[cw.Name] = { x = wx, y = wy }
		placeOverlays( id, sx, sy, w, h, wx, wy, ww, wh )
		return true
	end

	local function takeFlat()
		if not pool.flats or pool.flatsUsed >= #pool.flats then return nil end
		pool.flatsUsed = pool.flatsUsed + 1
		local cw = pool.flats[pool.flatsUsed]
		if cw and cw.Name == bm.pinName then
			if pool.flatsUsed >= #pool.flats then return nil end
			pool.flatsUsed = pool.flatsUsed + 1
			cw = pool.flats[pool.flatsUsed]
		end
		return cw
	end

	local function assignRoadOverlay( sx, sy, w, h, wx, wy, roadMask )
		roadMask = math.floor( tonumber( roadMask ) or 0 ) % 16
		if roadMask == 0 then return end
		if not pool.roads or pool.roadsUsed >= #pool.roads then return end
		pool.roadsUsed = pool.roadsUsed + 1
		local ov = pool.roads[pool.roadsUsed]
		ov.Visible = true
		ov.x = sx
		ov.y = sy
		ov.width = w + 1
		ov.height = h + 1
		ov.ImageName = "road_" .. roadMask
		bm.placed[#bm.placed + 1] = { w = ov, wx = wx, wy = wy, ww = 1, wh = 1, dim = true }
	end

	local function paintSolidCell( paintId, sx, sy, w, h, wx, wy, ww, wh, ids )
		ww = ww or 1
		wh = wh or 1
		local biomeId = ids[wy][wx]
		local roadMask = ( roadPaint and biomeId ~= 0 ) and RfsBiomeMap.roadMask( td, wx, wy ) or 0
		if useTiles and pool.tiles and pool.tilesUsed < #pool.tiles then
			local path = RfsBiomeMap.tileTexture( ids, wx, wy, x0, x1, y0, y1 )
			if path then
				pool.tilesUsed = pool.tilesUsed + 1
				local cw = pool.tiles[pool.tilesUsed]
				if cw and cw.Name == bm.pinName then
					if pool.tilesUsed >= #pool.tiles then return false end
					pool.tilesUsed = pool.tilesUsed + 1
					cw = pool.tiles[pool.tilesUsed]
				end
				bm.placed[#bm.placed + 1] = { w = cw, wx = wx, wy = wy, ww = ww, wh = wh }
				cw.Visible = true
				cw.ImageTexture = path
				cw.Colour = "1 1 1"
				cw.Alpha = 1
				cw.x = sx
				cw.y = sy
				cw.width = w + 1
				cw.height = h + 1
				bm.clickMap[cw.Name] = { x = wx, y = wy }
				placeOverlays( biomeId, sx, sy, w, h, wx, wy, ww, wh )
				if roadMask ~= 0 then
					assignRoadOverlay( sx, sy, w, h, wx, wy, roadMask )
				end
				return true
			end
		end
		local cw = takeFlat()
		if not cw then return false end
		bm.placed[#bm.placed + 1] = { w = cw, wx = wx, wy = wy, ww = ww, wh = wh }
		cw.Visible = true
		cw.Colour = RfsBiomeMap.colorForId( paintId )
		cw.Alpha = 1
		bm.clickMap[cw.Name] = { x = wx, y = wy }
		cw.x = sx
		cw.y = sy
		cw.width = w + 1
		cw.height = h + 1
		placeOverlays( biomeId, sx, sy, w, h, wx, wy, ww, wh )
		if roadMask ~= 0 then
			assignRoadOverlay( sx, sy, w, h, wx, wy, roadMask )
		end
		return true
	end

	local function assign(f, sx, sy, w, h, wx, wy, ww, wh)
		ww = ww or 1
		wh = wh or 1
		local lst = pool.byRes[f.res]
		if not lst then return false end
		local u = (pool.used[f.res] or 0) + 1
		if u > #lst then return false end
		local cw = lst[u]
		if cw and cw.Name == bm.pinName then
			u = u + 1
			cw = lst[u]
			if not cw then return false end
		end
		pool.used[f.res] = u
		bm.placed[#bm.placed + 1] = { w = cw, wx = wx, wy = wy, ww = ww, wh = wh, rs = T.rotskin }
		cw.Visible = true
		cw.ImageName = f.name
		cw.x = sx; cw.y = sy
		cw.width = w + 1; cw.height = h + 1
		if T.rotskin then
			cw.RotatingSkinAngle = (f.rot or 0) * ROTSIGN * (math.pi / 2)
			cw.RotatingSkinCenterX = math.floor((w + 1) / 2)
			cw.RotatingSkinCenterY = math.floor((h + 1) / 2)
		end
		bm.clickMap[cw.Name] = { x = wx, y = wy }
		placeOverlays( f.id or -1, sx, sy, w, h, wx, wy, ww, wh )
		return true
	end

	local atlas = hud.cl.atlas
	if solid then
		local perCell = useTiles
		local maxSide = 1
		if not perCell then
			if px < 10 then maxSide = 5
			elseif px < 14 then maxSide = 3
			elseif px < 22 then maxSide = 2
			end
		end
		local roadFilt = filt == ( RfsBiomeMap.ROAD_LEGEND_ID or 11 )
		local ids = {}
		for wy = y0, y1 do
			local row = {}
			ids[wy] = row
			for wx = x0, x1 do
				row[wx] = RfsBiomeMap.cellId( hud.cl.td, wx, wy )
			end
		end
		RfsBiomeMap.applyCoast( ids, x0, x1, y0, y1 )
		local function overlayRoadsRect( wx0, wy0, wx1, wy1 )
			if not roadPaint then return end
			for y = wy0, wy1 do
				for x = wx0, wx1 do
					if ids[y][x] ~= 0 then
						local rm = RfsBiomeMap.roadMask( td, x, y )
						if rm ~= 0 then
							local csx = edgeX( x )
							local csy = edgeY( y + 1 )
							local cw = edgeX( x + 1 ) - csx
							local ch = edgeY( y ) - csy
							assignRoadOverlay( csx, csy, cw, ch, x, y, rm )
						end
					end
				end
			end
		end
		local visited = {}
		local function vkey( wx, wy ) return wy * 65536 + wx end
		for wy = y0, y1 do
			for wx = x0, x1 do
				if not visited[vkey( wx, wy )] then
					local id = ids[wy][wx]
					if roadFilt and RfsBiomeMap.roadMask( td, wx, wy ) == 0 then
						visited[vkey( wx, wy )] = true
					elseif id == 0 and RfsBiomeMap.isOpenOcean( ids, wx, wy, x0, x1, y0, y1 ) then
						visited[vkey( wx, wy )] = true
					else
						local x2 = wx
						while x2 < x1 and ( x2 - wx + 1 ) < maxSide
							and ids[wy][x2 + 1] == id and not visited[vkey( x2 + 1, wy )] do
							x2 = x2 + 1
						end
						local y2 = wy
						while y2 < y1 and ( y2 - wy + 1 ) < maxSide do
							local okRow = true
							for x = wx, x2 do
								if ids[y2 + 1][x] ~= id or visited[vkey( x, y2 + 1 )] then
									okRow = false
									break
								end
							end
							if not okRow then break end
							y2 = y2 + 1
						end
						for y = wy, y2 do
							for x = wx, x2 do
								visited[vkey( x, y )] = true
							end
						end
						local ww, wh = x2 - wx + 1, y2 - wy + 1
						local sx = edgeX( wx )
						local sy = edgeY( wy + wh )
						local w = edgeX( wx + ww ) - sx
						local h = edgeY( wy ) - sy
						local paintId = id
						local done
						if perCell then
							done = paintSolidCell( paintId, sx, sy, w, h, wx, wy, ww, wh, ids )
						else
							done = assignFlat( paintId, sx, sy, w, h, wx, wy, ww, wh )
							if done and roadPaint and id ~= 0 then
								overlayRoadsRect( wx, wy, x2, y2 )
							end
						end
						if not done then
							skipped = skipped + 1
						end
					end
				end
			end
		end
	else
		for wy = y0, y1 do
			for wx = x0, x1 do
				local f, flags, real = BigMap.resolve(hud, wx, wy, T.tier)
				if f then
					local sx = edgeX(wx)
					local sy = edgeY(wy + 1)
					local w = edgeX(wx + 1) - sx
					local h = edgeY(wy) - sy
					local done = assign(f, sx, sy, w, h, wx, wy, 1, 1)
					if not done then
						local t = math.floor((flags or 0) / 4096) % 16
						local fbName = (t >= 1 and t <= 8) and ("biome_" .. t .. "_r0") or "unknown_r0"
						local h2 = atlas.mini[fbName]
						if h2 and h2.res ~= f.res then
							done = assign({ res = h2.res, name = fbName, rot = 0, id = t }, sx, sy, w, h, wx, wy, 1, 1)
						end
						if not done then skipped = skipped + 1 end
						if done then real = false end
					end
					local mask = math.floor((flags or 0) / 256) % 16
					if real == false and mask ~= 0 and pool.roadsUsed < #pool.roads then
						pool.roadsUsed = pool.roadsUsed + 1
						local ov = pool.roads[pool.roadsUsed]
						ov.Visible = true
						ov.x = sx; ov.y = sy
						ov.width = w + 1; ov.height = h + 1
						ov.ImageName = "road_" .. mask
						bm.placed[#bm.placed + 1] = { w = ov, wx = wx, wy = wy, ww = 1, wh = 1 }
					end
				end
			end
		end
	end
	bm.skipped = skipped
	for ti = 1, #TIERS do
		local p = bm.pools[ti]
		for res, lst in pairs(p.byRes) do
			local u = (ti == bm.tierIdx and (pool.used[res] or 0)) or 0
			for i = u + 1, #lst do lst[i].Visible = false end
		end
		local ru = (ti == bm.tierIdx) and pool.roadsUsed or 0
		for i = ru + 1, #(p.roads or {}) do p.roads[i].Visible = false end
		local du = (ti == bm.tierIdx) and (pool.dimsUsed or 0) or 0
		for i = du + 1, #(p.dims or {}) do p.dims[i].Visible = false end
		local fu = (ti == bm.tierIdx) and (pool.flatsUsed or 0) or 0
		for i = fu + 1, #(p.flats or {}) do p.flats[i].Visible = false end
		local su = (ti == bm.tierIdx) and (pool.shadesUsed or 0) or 0
		for i = su + 1, #(p.shades or {}) do p.shades[i].Visible = false end
		local tu = (ti == bm.tierIdx) and (pool.tilesUsed or 0) or 0
		for i = tu + 1, #(p.tiles or {}) do p.tiles[i].Visible = false end
	end
	-- No POI text soup on the map — names live in the MARKERS list.
	for i = 1, #bm.poiLabels do bm.poiLabels[i].Visible = false end
	local li = 0

	-- POI category icons (active filters only). Skip minSx gate — chem/oil
	-- lakes and plants are often sx 1–2 and must still place when filtered.
	-- Collect visible first, nearest-to-center wins when over POI_ICON_CAP
	-- (old south-first scan starved northern ruins).
	local filters = hud.cl.poiFilters or {}
	local anyPoi = false
	for _, cat in ipairs( POI_CATS ) do
		if filters[cat.key] then anyPoi = true break end
	end
	local ii = 0
	bm.poiIconMeta = {}
	if anyPoi and bm.poiIcons then
		local vis = {}
		local midX, midY = VW / 2, VH / 2
		for _, a in ipairs( bm.anchors or {} ) do
			if a.cat and filters[a.cat] then
				local sx = midX + ( a.cx - bm.cx ) * px
				local sy = midY - ( a.cy - bm.cy ) * px
				if sx > -20 and sx < VW + 20 and sy > -20 and sy < VH + 20 then
					local dx, dy = sx - midX, sy - midY
					vis[#vis + 1] = { a = a, sx = sx, sy = sy, d2 = dx * dx + dy * dy }
				end
			end
		end
		table.sort( vis, function( u, v ) return u.d2 < v.d2 end )
		local nPlace = math.min( #vis, #bm.poiIcons )
		for i = 1, nPlace do
			local v = vis[i]
			local ic = bm.poiIcons[i]
			ic.Visible = true
			ic.ImageTexture = CC .. "/Gui/wpdot_" .. poiDotForAnchor( v.a ) .. "_b1.png"
			ic.x = math.floor( v.sx - 10 )
			ic.y = math.floor( v.sy - 10 )
			bm.poiIconMeta[i] = v.a
			bm.placed[#bm.placed + 1] = { w = ic, ax = v.a.cx, ay = v.a.cy, lbl = true }
		end
		ii = nPlace
	end
	if bm.poiIcons then
		for i = ii + 1, #bm.poiIcons do
			bm.poiIcons[i].Visible = false
			bm.poiIconMeta[i] = nil
		end
	end

	-- Selection highlight from markers list.
	if bm.selRing then
		local sel = bm.markSel
		if sel and sel.cx and sel.cy then
			local sx = VW / 2 + ( sel.cx - bm.cx ) * px
			local sy = VH / 2 - ( sel.cy - bm.cy ) * px
			if sx > -30 and sx < VW + 30 and sy > -30 and sy < VH + 30 then
				bm.selRing.Visible = true
				bm.selRing.x = math.floor( sx - 11 )
				bm.selRing.y = math.floor( sy - 11 )
				bm.placed[#bm.placed + 1] = { w = bm.selRing, ax = sel.cx, ay = sel.cy, lbl = true }
			else
				bm.selRing.Visible = false
			end
		else
			bm.selRing.Visible = false
		end
	end

	local pinW = bm.pinName and bm.widgetByName and bm.widgetByName[bm.pinName]
	local vc = { bm.water }
	for i = 1, (pool.flatsUsed or 0) do
		if pool.flats[i] ~= pinW then vc[#vc + 1] = pool.flats[i] end
	end
	for i = 1, (pool.tilesUsed or 0) do
		if pool.tiles[i] ~= pinW then vc[#vc + 1] = pool.tiles[i] end
	end
	for res, lst in pairs(pool.byRes) do
		for i = 1, (pool.used[res] or 0) do
			if lst[i] ~= pinW then vc[#vc + 1] = lst[i] end
		end
	end
	for i = 1, (pool.shadesUsed or 0) do vc[#vc + 1] = pool.shades[i] end
	for i = 1, pool.roadsUsed do vc[#vc + 1] = pool.roads[i] end
	for i = 1, (pool.dimsUsed or 0) do vc[#vc + 1] = pool.dims[i] end
	for i = 1, li do vc[#vc + 1] = bm.poiLabels[i] end
	for i = 1, ii do vc[#vc + 1] = bm.poiIcons[i] end
	if pinW then vc[#vc + 1] = pinW end
	vc[#vc + 1] = bm.marker
	if bm.basePin then vc[#vc + 1] = bm.basePin end
	if bm.selRing and bm.selRing.Visible then vc[#vc + 1] = bm.selRing end
	for _, col in ipairs(Waypoint.COLORS) do
		vc[#vc + 1] = bm.wpPins[col]
		vc[#vc + 1] = bm.wpGhost[col]
		if bm.farmPins then vc[#vc + 1] = bm.farmPins[col] end
	end
	bm.view.Childs = vc
	BigMap.syncLegendUi(hud)
	BigMap.syncPoiUi(hud)
	BigMap.syncMarkList(hud)
end

-- ------------------------------------------------------------ open/close ---
function BigMap.toggle(hud)
	local c = hud.cl
	if c.bm and c.bm.open then BigMap.close(hud) else BigMap.open(hud) end
end

function BigMap.open(hud)
	local c = hud.cl
	if not (c.ready and c.atlas and c.vw) then return end
	if c.bm and c.bm.open then return end
	if not BigMap.build(hud, 99999) then return end
	local bm = c.bm
	local okc, char = pcall(function() return sm.localPlayer.getPlayer():getCharacter() end)
	if okc and char then
		bm.cx = char.worldPosition.x / 64
		bm.cy = char.worldPosition.y / 64
	else
		bm.cx, bm.cy = bm.cx or 0, bm.cy or 0
	end
	bm.open = true
	bm.age = 0
	-- a cursor sample must never survive a map session: bm.age restarts at 0
	-- here, so last session's sample would read as fresh and the first click of
	-- the new session would commit the waypoint at last session's coordinates.
	bm.lastCur = nil
	bm.wpSig = nil
	bm.panKey = { x = 0, y = 0 }
	-- session boundary in the event log: entries persist across sessions and
	-- old-build events read as current without this (v65 diagnosis trap)
	hud.cl.bmLog = {}
	evlog(hud, "session", "v" .. tostring(c.version or "?")
		.. " b" .. tostring(c.build or "?"))
	-- TEAR DOWN the minimap guis completely (not just hide): if callback
	-- dispatch is bound per script to a single gui, ours must be the only
	-- one alive. They rebuild automatically the frame after the map closes.
	hud:cl_rebuildGui()
	BigMap.refill(hud)
	-- CLICKS-ONLY, FINAL (Eric v57): the interactive cursor session and
	-- keyboard presses are mutually exclusive engine-side; cursor wins.
	-- All navigation is mouse: buttons (hold-glide arrows), wheel zoom,
	-- tile-click waypoints, Esc/CLOSE.
	pcall(function() bm.gui:open() end)
end

function BigMap.close(hud)
	local bm = hud.cl.bm
	if not bm then return end
	bm.open = false
	-- always release any spike lock (harmless when none spawned); the
	-- destroy request must go through MinimapHud's own context (scriptRef)
	pcall(function()
		sm.localPlayer.getPlayer():getCharacter():setLockingInteractable(nil)
	end)
	hud.cl.wantUnlock = true
	pcall(function() if bm.gui then bm.gui:close() end end)
	pcall(function() if bm.gui2 then bm.gui2:close() end end)
	-- 0851-d: keep cached widget pools between opens (close session only)
	-- the minimap unhides via the normal hide check next frame
end

-- engine hook (via MinimapHud.cl_onGuiClosed): Esc closed the gui
function BigMap.onClosed(hud)
	local bm = hud.cl.bm
	if bm and bm.open then
		bm.open = false
		pcall(function() if bm.gui then bm.gui:close() end end)
		pcall(function() if bm.gui2 then bm.gui2:close() end end)
	end
end

-- ------------------------------------------------------------- update ------
-- per frame while open (T10-proven cadence): markers + render. Engine-side
-- close (Esc) is detected via sm.gui.hasActiveGui() going false - rendering
-- after that would RE-OPEN the closed gui (v22 "closes then comes back"),
-- and without detection the minimap stayed hidden forever (v23).
function BigMap.update(hud, dt, char)
	local bm = hud.cl.bm
	if not (bm and bm.open and bm.gui) then return end
	bm.age = (bm.age or 0) + (dt or 0)
	-- 0851-d: cap jsonGui render (1100+ pool widgets) — full-rate pan/input,
	-- ~20 Hz paint so GPS open is not a sustained log/render flood.
	bm.rfsRenderT = (bm.rfsRenderT or 0) + (dt or 0)
	local doRender = bm.rfsRenderT >= 0.05
	if doRender then bm.rfsRenderT = 0 end
	-- engine-side close detection (Esc): the session going away flips
	-- hasActiveGui false; rendering after that would re-open the gui
	if bm.age > 0.5 then
		local okA, act = pcall(sm.gui.hasActiveGui)
		if okA and act == false then
			BigMap.onClosed(hud)
			return
		end
	end
	local px = bm.scale or DEFAULT_SCALE
	if char then
		local pos = char.worldPosition
		local sx = bm.VW / 2 + (pos.x / 64 - bm.cx) * px
		local sy = bm.VH / 2 - (pos.y / 64 - bm.cy) * px
		bm.marker.Visible = true
		bm.marker.x = math.floor(sx - MARKER / 2)
		bm.marker.y = math.floor(sy - MARKER / 2)
		local okd, dir = pcall(sm.camera.getDirection)
		if okd and dir then
			bm.marker.RotatingSkinAngle = math.atan2(dir.x, dir.y)
		end
	end
	local wp = hud.cl.waypoint
	local wpCol = Waypoint.valid(hud.cl.wpColor) and hud.cl.wpColor or "red"
	-- live placement ghost while drag coords are fresh (button held+moving)
	local cur = bm.lastCur
	local gx, gy
	if cur and (bm.age or 0) - cur.t < 0.25 then
		gx, gy = BigMap.curToView(hud, cur)
	end
	-- BUG-3 (Eric 8/11): dragging to MOVE an existing waypoint showed TWO
	-- identical pins - ghost and committed pin are the same art - and read as
	-- two waypoints. While a placement drag is live the ghost IS the waypoint
	-- being moved, so the committed pin hides. Gated on the sample coming from
	-- onDrag rather than merely being FRESH: onToolTip feeds the same sampler on
	-- a plain hover and must never blink the placed pin out. Recomputed per
	-- frame, so an abandoned gesture brings the pin back by itself.
	local placing = (gx ~= nil) and cur.drag == true
	-- BUG-5 (Eric 8/11): "sometimes when you release the button when dragging it
	-- doesnt set in the new position and jumps back its previous spot" - the
	-- commit never happened, so the hidden pin simply reappeared where it was.
	-- Both known ways for the release to produce no usable onClick need the same
	-- remedy, so this does not wait on knowing which one bites: MyGUI fires
	-- onClick only when press and release land on the SAME widget (any drag
	-- across a cell boundary would then produce none), and cellClick drops the
	-- commit when the released widget is missing from clickMap. A drag now
	-- commits ITSELF once the samples stop arriving, from the sample's own
	-- coordinates - no widget name, nothing to lose. Fires just before the
	-- ghost's own 0.25 s window closes, so the pin appears exactly as the ghost
	-- goes, and the sample is spent so onClick cannot re-commit it.
	-- CONFIRMED in-game by Eric on build 7 and promoted out of its flag.
	if cur and cur.drag and not placing
			and (bm.age or 0) - cur.t >= DRAGEND then
		if BigMap.commitAt(hud, cur) then
			wp = hud.cl.waypoint
		end
		bm.lastCur = nil
		cur = nil
	end
	for col, p in pairs(bm.wpPins) do
		if wp and col == wpCol and not placing then
			local sx = bm.VW / 2 + (wp.x / 64 - bm.cx) * px
			local sy = bm.VH / 2 - (wp.y / 64 - bm.cy) * px
			p.Visible = true
			p.x = math.floor(sx - 10)
			p.y = math.floor(sy - 26)
		else
			p.Visible = false
		end
	end
	-- Base house pin (centered on world point)
	if bm.basePin then
		local base = hud.cl.baseMarker
		if base and base.x then
			local sx = bm.VW / 2 + ( base.x / 64 - bm.cx ) * px
			local sy = bm.VH / 2 - ( base.y / 64 - bm.cy ) * px
			bm.basePin.Visible = true
			bm.basePin.x = math.floor( sx - 16 )
			bm.basePin.y = math.floor( sy - 16 )
		else
			bm.basePin.Visible = false
		end
	end
	-- Farm seed pins
	if bm.farmPins then
		local farms = hud.cl.farmMarkers or {}
		for col, p in pairs( bm.farmPins ) do
			local f = farms[col]
			if f and f.x then
				local sx = bm.VW / 2 + ( f.x / 64 - bm.cx ) * px
				local sy = bm.VH / 2 - ( f.y / 64 - bm.cy ) * px
				p.Visible = true
				p.x = math.floor( sx - 10 )
				p.y = math.floor( sy - 26 )
			else
				p.Visible = false
			end
		end
	end
	if bm.wpGhost then
		for col, g in pairs(bm.wpGhost) do
			if gx and col == wpCol then
				g.Visible = true
				g.x = math.floor(gx - 10)
				g.y = math.floor(gy - 26)
			else
				g.Visible = false
			end
		end
	end
	-- overlay mirrors (screen coords; hidden near the viewport edge since
	-- gui2 has no clipping parent - the clipped original still shows there)
	if bm.gui2 and bm.root2 then
		local function mirror(dst, src, w2, h2)
			if src.Visible and src.x >= -4 and src.x + w2 <= bm.VW + 4
			and src.y >= -6 and src.y + h2 <= bm.VH + 6 then
				dst.Visible = true
				dst.x = (bm.vx or 0) + src.x
				dst.y = (bm.vy or 0) + src.y
			else
				dst.Visible = false
			end
		end
		mirror(bm.oMarker, bm.marker, MARKER, MARKER)
		bm.oMarker.RotatingSkinAngle = bm.marker.RotatingSkinAngle
		for col, p in pairs(bm.wpPins) do mirror(bm.oPins[col], p, 20, 28) end
		for col, g in pairs(bm.wpGhost) do mirror(bm.oGhosts[col], g, 20, 28) end
		if doRender then
			pcall(function() bm.gui2:render(bm.root2) end)
		end
	end
	-- BUG-4 diagnosis channel. Logged on CHANGE only (a handful of entries per
	-- session, no per-frame cost) so a phantom pin can be attributed: if these
	-- say pin=false while Eric is looking at a pin, the engine is painting a
	-- widget we hid and WP_FRESH_NAMES is the right class of fix; if they say
	-- pin=true with wp=false, the bug is ours and it is in this function.
	local sig = "wp=" .. tostring(wp ~= nil) .. " col=" .. wpCol
		.. " pin=" .. tostring(bm.wpPins[wpCol] and bm.wpPins[wpCol].Visible)
		.. " ghost=" .. tostring(bm.wpGhost[wpCol] and bm.wpGhost[wpCol].Visible)
		.. " omirror=" .. tostring(bm.oPins and bm.oPins[wpCol]
			and bm.oPins[wpCol].Visible)
		.. " placing=" .. tostring(placing) .. " gsfx=" .. tostring(bm.gsfx)
	if sig ~= bm.wpSig then
		bm.wpSig = sig
		evlog(hud, "wpui", sig)
	end
	-- hold-to-glide: smooth per-frame pan while a pan button is held
	local pk = bm.panKey
	if pk and (pk.x ~= 0 or pk.y ~= 0) then
		local sp = (bm.VW * 0.45) / bm.scale * (dt or 0)
		BigMap.panBy(hud, pk.x * sp, pk.y * sp)
	end
	-- keyboard lerp: view glides toward the WASD target set by keystrokes
	if bm.tgtCx and (math.abs(bm.tgtCx - bm.cx) > 0.002
			or math.abs((bm.tgtCy or bm.cy) - bm.cy) > 0.002) then
		local k = math.min(1, (dt or 0) * 14)
		bm.cx = bm.cx + (bm.tgtCx - bm.cx) * k
		bm.cy = bm.cy + ((bm.tgtCy or bm.cy) - bm.cy) * k
		BigMap.reposition(hud)
		if math.abs(bm.cx - (bm.refillCx or bm.cx)) > 0.8
		or math.abs(bm.cy - (bm.refillCy or bm.cy)) > 0.8 then
			BigMap.refill(hud)
		end
	end
	if doRender then
		local okr = pcall(function() bm.gui:render(bm.root) end)
		if not okr then
			BigMap.onClosed(hud)
		end
	end
end

-- ------------------------------------------------------------- buttons -----
-- ops decoded from widget NAMES (jsonGui callbacks carry no data payload)
local BTN_PAN = {
	BMPanW = { -1, 0 }, BMPanE = { 1, 0 }, BMPanN = { 0, 1 }, BMPanS = { 0, -1 },
}

-- Legend selection captions ("> Meadow" while filtered).
function BigMap.syncLegendUi(hud)
	local bm = hud.cl.bm
	if not bm then return end
	if bm.legLbs then
		local rows = ( type( RfsBiomeMap ) == "table" and RfsBiomeMap.LEGEND ) or {}
		for i, row in ipairs( rows ) do
			local lb = bm.legLbs[i]
			if lb then
				local label = tostring( row.label or "" )
				if bm.legendFilter ~= nil and bm.legendFilter == row.id then
					lb.Caption = "> " .. label
				else
					lb.Caption = label
				end
			end
		end
	end
end

function BigMap.syncPoiUi(hud)
	local bm = hud.cl.bm
	if not bm then return end
	local filters = hud.cl.poiFilters or {}
	if bm.poiIconImgs then
		for _, cat in ipairs( POI_CATS ) do
			local ic = bm.poiIconImgs[cat.key]
			if ic then
				if filters[cat.key] then
					ic.Colour = "1 1 0.55"
				else
					ic.Colour = "0.55 0.55 0.55"
				end
			end
		end
	end
	if bm.homeIcon then
		if bm.placeMode == "base" then
			bm.homeIcon.Colour = "0.55 0.85 1.0"
		else
			bm.homeIcon.Colour = HOME_BLUE
		end
	end
end

function BigMap.buildMarkItems(hud)
	local bm = hud.cl.bm
	local items = {}
	items[#items + 1] = {
		kind = "you", label = "You", tex = "arrow.png", colour = "1 1 1" }
	local base = hud.cl.baseMarker
	if base and base.x and base.y then
		items[#items + 1] = {
			kind = "home", label = "Home", tex = TEX_HOME, colour = HOME_BLUE,
			cx = base.x / 64, cy = base.y / 64 }
	end
	local wp = hud.cl.waypoint
	if wp and wp.x and wp.y then
		items[#items + 1] = {
			kind = "wp", label = "Waypoint", tex = "rfs_bcn_dot_b1.png",
			colour = "1 0.35 0.35", cx = wp.x / 64, cy = wp.y / 64 }
	end
	local farms = hud.cl.farmMarkers or {}
	for _, col in ipairs( Waypoint.COLORS ) do
		local f = farms[col]
		if f and f.x and f.y then
			items[#items + 1] = {
				kind = "farm", label = "Farm (" .. col .. ")",
				tex = "rfs_bcn_flower_b1.png", colour = "0.55 1 0.55",
				cx = f.x / 64, cy = f.y / 64 }
		end
	end
	-- Current tracked quest only (not every Builder Quest / camping spot).
	pcall(function()
		local tracked = QuestManager.Cl_GetTrackedQuests and QuestManager.Cl_GetTrackedQuests()
		if type( tracked ) ~= "table" then return end
		for qName, qObj in pairs( tracked ) do
			local title = tostring( qName or "Quest" ):gsub( "^quest_", "" ):gsub( "_", " " )
			local cx, cy
			pcall(function()
				if sm.exists( qObj ) and qObj.getClientWaypoint then
					local wpos = qObj:getClientWaypoint()
					if wpos then
						cx = wpos.x / 64
						cy = wpos.y / 64
					end
				end
			end)
			if not cx then
				pcall(function()
					local data = QuestManager.Cl_GetQuestData and QuestManager.Cl_GetQuestData( qName )
					local pos = data and ( data.waypoint or data.position or data.pos )
					if pos and pos.x then
						cx = pos.x / 64
						cy = pos.y / 64
					end
				end)
			end
			if cx and cy then
				items[#items + 1] = {
					kind = "quest", label = truncLabel( title, 18 ),
					tex = "rfs_bcn_bang_b1.png", colour = "1 0.85 0.35",
					cx = cx, cy = cy }
				break -- one current quest only
			end
		end
	end)
	-- POI directory is driven by the top filter icons (not the full 800+ soup).
	local filters = hud.cl.poiFilters or {}
	local pois = {}
	for _, a in ipairs( bm.anchors or {} ) do
		if a.cat and filters[a.cat] then
			pois[#pois + 1] = a
		end
	end
	table.sort( pois, function( a, b )
		return tostring( a.label or "" ) < tostring( b.label or "" )
	end )
	for _, a in ipairs( pois ) do
		local tex = "rfs_bcn_dot_b1.png"
		for _, cat in ipairs( POI_CATS ) do
			if cat.key == a.cat then
				tex = cat.tex
				break
			end
		end
		items[#items + 1] = {
			kind = "poi", label = poiDisplayLabel( a ), rawLabel = a.label,
			tex = tex, colour = "1 1 1",
			cx = a.cx, cy = a.cy, cat = a.cat, mineKind = a.mineKind }
	end
	bm.markItems = items
	return items
end

function BigMap.syncMarkList(hud)
	local bm = hud.cl.bm
	if not ( bm and bm.markRows ) then return end
	local items = BigMap.buildMarkItems(hud)
	local n = #items
	local maxScroll = math.max( 0, n - MARK_ROWS )
	bm.markScroll = math.max( 0, math.min( maxScroll, bm.markScroll or 0 ) )
	local scroll = bm.markScroll
	if bm.markCountLb then
		bm.markCountLb.Caption = tostring( n ) .. " loc"
	end
	for i = 1, MARK_ROWS do
		local row = bm.markRows[i]
		local it = items[scroll + i]
		if it then
			row.btn.Visible = true
			row.icon.Visible = true
			if row.plate then row.plate.Visible = true end
			row.icon.ImageTexture = CC .. "/Gui/" .. it.tex
			row.icon.Colour = it.colour or "1 1 1"
			local sel = bm.markSel
			local isSel = sel and sel.cx == it.cx and sel.cy == it.cy
				and sel.label == it.label
			local name = truncLabel( it.label, 16 )
			if row.lb then
				row.lb.Caption = isSel and ( "> " .. name ) or name
			else
				row.btn.Caption = isSel and ( "> " .. name ) or name
			end
		else
			row.btn.Visible = false
			if row.lb then row.lb.Caption = "" end
			row.btn.Caption = ""
			row.icon.Visible = false
			if row.plate then row.plate.Visible = false end
		end
	end
end

function BigMap.markScrollBy(hud, delta)
	local bm = hud.cl.bm
	if not bm then return end
	local items = bm.markItems or BigMap.buildMarkItems(hud)
	local maxScroll = math.max( 0, #items - MARK_ROWS )
	bm.markScroll = math.max( 0, math.min( maxScroll, ( bm.markScroll or 0 ) + delta ) )
	BigMap.syncMarkList(hud)
end

function BigMap.goMark(hud, item)
	local bm = hud.cl.bm
	if not ( bm and item ) then return end
	if item.kind == "you" then
		local okc, char = pcall(function() return sm.localPlayer.getPlayer():getCharacter() end)
		if okc and char then
			bm.cx = char.worldPosition.x / 64
			bm.cy = char.worldPosition.y / 64
		end
		bm.markSel = nil
	elseif item.cx and item.cy then
		bm.cx, bm.cy = item.cx, item.cy
		bm.markSel = { cx = item.cx, cy = item.cy, label = item.label, kind = item.kind }
	else
		return
	end
	local b = hud.cl.td and hud.cl.td.bounds
	if b then
		bm.cx = math.max(b.xMin, math.min(b.xMax, bm.cx))
		bm.cy = math.max(b.yMin, math.min(b.yMax, bm.cy))
	end
	bm.tgtCx, bm.tgtCy = bm.cx, bm.cy
	BigMap.setInfoFromItem(hud, item)
	BigMap.refill(hud)
end

-- Right INFO panel (replaces floating tip that drew under the map).
function BigMap.setInfo(hud, title, body, meta)
	local bm = hud.cl.bm
	if not bm then return end
	if bm.infoTitle then bm.infoTitle.Caption = tostring( title or "—" ) end
	if bm.infoBody then bm.infoBody.Caption = tostring( body or "" ) end
	if bm.infoMeta then bm.infoMeta.Caption = tostring( meta or "" ) end
end

function BigMap.setInfoFromItem(hud, item)
	if not item then
		BigMap.setInfo(hud, "—", "Click a map marker\nor Markers list row.", "")
		return
	end
	if item.kind == "you" then
		BigMap.setInfo(hud, "You", "Your current position on this seed.", "")
		return
	end
	if item.kind == "home" then
		local meta = item.cx and string.format( "cell %.0f, %.0f", item.cx, item.cy ) or ""
		BigMap.setInfo(hud, "Home", "Saved home beacon. Blue house on the compass.", meta)
		return
	end
	if item.kind == "wp" then
		local meta = item.cx and string.format( "cell %.0f, %.0f", item.cx, item.cy ) or ""
		BigMap.setInfo(hud, "Waypoint", "Active travel pin. CLEAR removes it.", meta)
		return
	end
	if item.kind == "farm" then
		local meta = item.cx and string.format( "cell %.0f, %.0f", item.cx, item.cy ) or ""
		BigMap.setInfo(hud, item.label or "Farm", "Farm pin for planting runs.", meta)
		return
	end
	if item.kind == "quest" then
		local meta = item.cx and string.format( "cell %.0f, %.0f", item.cx, item.cy ) or ""
		BigMap.setInfo(hud, item.label or "Quest", "Tracked quest destination.", meta)
		return
	end
	if item.kind == "poi" then
		local title, body = poiExpect( item.rawLabel or item.label, item.cat, item )
		local meta = ""
		if item.cx and item.cy then
			meta = string.format( "cell %.0f, %.0f", item.cx, item.cy )
		end
		if item.rawLabel and item.rawLabel ~= title then
			meta = ( meta ~= "" and ( meta .. "\n" ) or "" ) .. truncLabel( item.rawLabel, 28 )
		end
		BigMap.setInfo(hud, title, body, meta)
		return
	end
	BigMap.setInfo(hud, item.label or "Marker", "", "")
end

-- Click a map POI dot: fill INFO + scroll Markers list to the matching row.
function BigMap.showPoiInfo(hud, anchor)
	local bm = hud.cl.bm
	if not ( bm and anchor ) then return end
	local title, body = poiExpect( anchor.label, anchor.cat, anchor )
	local meta = string.format( "cell %.0f, %.0f", anchor.cx or 0, anchor.cy or 0 )
	if anchor.label and poiDisplayLabel( anchor ) ~= truncLabel( anchor.label, 22 ) then
		meta = meta .. "\n" .. truncLabel( anchor.label, 28 )
	elseif anchor.label and title ~= truncLabel( anchor.label, 22 ) then
		meta = meta .. "\n" .. truncLabel( anchor.label, 28 )
	end
	BigMap.setInfo(hud, title, body, meta)
	bm.markSel = {
		cx = anchor.cx, cy = anchor.cy,
		label = poiDisplayLabel( anchor ), kind = "poi" }
	if bm.selRing then
		local px = bm.scale or DEFAULT_SCALE
		local sx = ( bm.VW or 0 ) / 2 + ( anchor.cx - bm.cx ) * px
		local sy = ( bm.VH or 0 ) / 2 - ( anchor.cy - bm.cy ) * px
		bm.selRing.Visible = true
		bm.selRing.x = math.floor( sx - 11 )
		bm.selRing.y = math.floor( sy - 11 )
	end
	local items = BigMap.buildMarkItems(hud)
	for i, it in ipairs( items ) do
		if it.kind == "poi" and it.cx == anchor.cx and it.cy == anchor.cy
			and ( it.rawLabel == anchor.label or it.label == poiDisplayLabel( anchor ) ) then
			bm.markScroll = math.max( 0, i - 1 )
			break
		end
	end
	BigMap.syncMarkList(hud)
end

-- Compat no-op (old tip path removed).
function BigMap.hidePoiTip( _hud ) end
function BigMap.showPoiTip(hud, anchor, _iconW)
	BigMap.showPoiInfo(hud, anchor)
end

-- waypoint control visuals: the selected color's dot swaps its flat circle
-- for the teardrop pin; dim overlay on CLEAR while there is nothing to clear
function BigMap.syncWpUi(hud)
	local bm = hud.cl.bm
	if not bm then return end
	local col = Waypoint.valid(hud.cl.wpColor) and hud.cl.wpColor or "red"
	if bm.colDot then
		for c2, d in pairs(bm.colDot) do
			d.pin.Visible = (c2 == col)
			d.circ.Visible = (c2 ~= col)
		end
	end
	if bm.clearDim then
		bm.clearDim.Visible = (hud.cl.waypoint == nil)
	end
	BigMap.syncLegendUi(hud)
end

function BigMap.button(hud, name)
	local bm = hud.cl.bm
	if not (bm and bm.open) then return end
	-- waypoint controls first: pin click removes, CLEAR removes (no-op when
	-- greyed), color dot recolors - none of these move the view (no refill)
	-- no anchor at the end: the pin name carries a per-session generation
	-- suffix ("BMWp_red_g3") when WP_FRESH_NAMES is on. "BMWpClear" and
	-- "BMWpCol_red" still cannot match - both need the underscore right after
	-- BMWp, which they do not have.
	local pinCol = string.match(name, "^BMWp_(%a+)")
	if pinCol or name == "BMWpClear" then
		if hud.cl.waypoint then
			Waypoint.clear(hud)
			BigMap.syncWpUi(hud)
		end
		return
	end
	if name == "BMBasePin" or ( bm.gsfx and name == "BMBasePin" .. bm.gsfx )
		or string.match( name, "^BMBasePin" ) then
		Waypoint.clearBase(hud)
		return
	end
	local farmPinCol = string.match( name, "^BMFarmPin_(%a+)" )
	if farmPinCol then
		Waypoint.clearFarm(hud, farmPinCol)
		return
	end
	local poiKey = string.match( name, "^BMPoi_(%a+)$" )
	if poiKey then
		Waypoint.togglePoiFilter(hud, poiKey)
		bm.placeMode = nil
		BigMap.refill(hud)
		return
	end
	local poiIc = tonumber( string.match( name, "^BMPoiIc_(%d+)$" ) )
	if poiIc and bm.poiIconMeta and bm.poiIconMeta[poiIc] then
		BigMap.showPoiInfo(hud, bm.poiIconMeta[poiIc])
		return
	end
	if name == "BMHome" or name == "BMBasePlace" then
		-- Blue home: place mode, or recenter on existing home.
		if bm.placeMode == "base" then
			bm.placeMode = nil
			BigMap.syncPoiUi(hud)
			return
		end
		local base = hud.cl.baseMarker
		if base and base.x and base.y then
			local near = math.abs( ( bm.cx or 0 ) - base.x / 64 ) < 2
				and math.abs( ( bm.cy or 0 ) - base.y / 64 ) < 2
			if near then
				bm.placeMode = "base"
				BigMap.syncPoiUi(hud)
			else
				BigMap.goMark(hud, {
					kind = "home", label = "Home",
					cx = base.x / 64, cy = base.y / 64 })
			end
			return
		end
		bm.placeMode = "base"
		BigMap.syncPoiUi(hud)
		return
	end
	if name == "BMMarkUp" then
		BigMap.markScrollBy(hud, -1)
		return
	end
	if name == "BMMarkDn" then
		BigMap.markScrollBy(hud, 1)
		return
	end
	local markRow = tonumber( string.match( name, "^BMMark_(%d+)$" ) )
	if markRow then
		local items = bm.markItems or BigMap.buildMarkItems(hud)
		local it = items[( bm.markScroll or 0 ) + markRow]
		if it then BigMap.goMark(hud, it) end
		return
	end
	local farmCol = string.match( name, "^BMFarmCol_(%a+)$" )
	if farmCol then
		if bm.placeMode == "farm_" .. farmCol then
			bm.placeMode = nil
		else
			bm.placeMode = "farm_" .. farmCol
		end
		BigMap.syncPoiUi(hud)
		return
	end
	local legIdx = tonumber( string.match( name, "^BMLegPick_(%d+)$" ) )
	if legIdx then
		local rows = ( type( RfsBiomeMap ) == "table" and RfsBiomeMap.LEGEND ) or {}
		local row = rows[legIdx]
		if row then
			if bm.legendFilter == row.id then
				bm.legendFilter = nil
			else
				bm.legendFilter = row.id
			end
			BigMap.refill(hud)
		end
		return
	end
	local dotCol = string.match(name, "^BMWpCol_(%a+)$")
	if dotCol then
		bm.placeMode = nil
		Waypoint.setColor(hud, dotCol)
		BigMap.syncWpUi(hud)
		return
	end
	if name == "BMClose" then
		BigMap.close(hud)
		return
	elseif name == "BMYou" then
		local okc, char = pcall(function() return sm.localPlayer.getPlayer():getCharacter() end)
		if okc and char then
			bm.cx = char.worldPosition.x / 64
			bm.cy = char.worldPosition.y / 64
		end
	elseif name == "BMMini" then
		hud:cl_mmToggle()
		if bm.mmBtn then
			bm.mmBtn.Caption = (hud.cl.posIdx == 5) and "MINIMAP: OFF" or "MINIMAP: ON"
		end
		-- falls through to the shared refill so the new caption renders
	elseif name == "BMZoomIn" then
		bm.scale = math.min(MAXSCALE, (bm.scale or DEFAULT_SCALE) * 1.3)
	elseif name == "BMZoomOut" then
		bm.scale = math.max(MINSCALE, (bm.scale or DEFAULT_SCALE) / 1.3)
	elseif BTN_PAN[name] then
		-- click fallback: small nudge (hold-to-glide is the primary path)
		bm.cx = bm.cx + BTN_PAN[name][1] * bm.VW * 0.10 / bm.scale
		bm.cy = bm.cy + BTN_PAN[name][2] * bm.VH * 0.10 / bm.scale
	else
		return
	end
	local b = hud.cl.td.bounds
	bm.cx = math.max(b.xMin, math.min(b.xMax, bm.cx))
	bm.cy = math.max(b.yMin, math.min(b.yMax, bm.cy))
	bm.tgtCx, bm.tgtCy = bm.cx, bm.cy
	BigMap.refill(hud)
end

-- --------------------------------------------------------- wheel + drag ----
-- arg shapes are undocumented: handlers pick out the numeric args
-- adaptively and log the raw shapes to bm_events.json (first few also to
-- chat) so the real contract can be read off Eric's session.
-- wheel: map zoom, or marker-list scroll when over BMMark*
function BigMap.wheel(hud, name, delta, c2, d)
	local bm = hud.cl.bm
	if not (bm and bm.open) then return end
	local wname = name
	if type( wname ) == "table" then wname = wname.Name end
	if type( wname ) ~= "string" then wname = nil end
	local dlt = tonumber( delta )
	if dlt == nil then dlt = tonumber( c2 ) end
	if dlt == nil then dlt = 120 end
	local dir = dlt >= 0 and 1 or -1
	if wname and ( string.find( wname, "^BMMark", 1, false )
		or wname == "BMMarkList" or wname == "BMMarkListBg" ) then
		BigMap.markScrollBy( hud, -dir )
		return
	end
	bm.scale = math.max(MINSCALE, math.min(MAXSCALE,
		(bm.scale or DEFAULT_SCALE) * (1.15 ^ dir)))
	BigMap.refill(hud)
end

-- smooth-pan reposition (v35): every placed widget knows its world anchor,
-- so panning just nudges x/y (sub-ms) - the expensive refill runs only when
-- the view drifts most of a cell. This is how a browser map pans.
function BigMap.reposition(hud)
	local bm = hud.cl.bm
	if not (bm and bm.placed) then return end
	local px = bm.scale
	local VW, VH = bm.VW, bm.VH
	local floor = math.floor
	for _, p in ipairs(bm.placed) do
		if p.lbl then
			p.w.x = floor(VW / 2 + (p.ax - bm.cx) * px - 70 + 0.5)
			p.w.y = floor(VH / 2 - (p.ay - bm.cy) * px - 9 + 0.5)
		else
			local ww = p.ww or 1
			local wh = p.wh or 1
			local sx = floor(VW / 2 + (p.wx - bm.cx) * px + 0.5)
			local sy = floor(VH / 2 - (p.wy + wh - bm.cy) * px + 0.5)
			p.w.x = sx
			p.w.y = sy
			p.w.width = floor(VW / 2 + (p.wx + ww - bm.cx) * px + 0.5) - sx + 1
			p.w.height = floor(VH / 2 - (p.wy - bm.cy) * px + 0.5) - sy + 1
		end
	end
end

-- drag-pan v32: coords-based again. Theory: onDrag(name, x, y, btn) DOES
-- track the cursor, but refill recycling the PRESSED widget killed the
-- engine's drag session mid-drag ("grabbed once then nothing"). The pressed
-- widget is now PINNED (kept assigned + in the tree) for the whole session.
-- Raw events logged (every 6th) to verify the coords ground truth.
function BigMap.drag(hud, name, x, y, btn)
	local bm = hud.cl.bm
	if not (bm and bm.open) then return end
	hud.cl.dragN = (hud.cl.dragN or 0) + 1
	if hud.cl.dragN % 6 == 1 then
		evlog(hud, "drag", name, x, y, btn)
	end
	if type(x) ~= "number" or type(y) ~= "number" then return end
	-- session = time-gap keyed ONLY: the event fires on whatever widget is
	-- under the cursor, so the NAME CHANGES mid-drag (v32 log) - keying the
	-- session on it reset the anchor every tile ("drags 1 tile at a time").
	-- Coords are screen-global and carry across widgets.
	local newSession = (bm.sinceDrag or 1) > 0.3
	bm.sinceDrag = 0
	if newSession then
		bm.pinName = name
		bm.pinWidget = bm.widgetByName and bm.widgetByName[name]
		bm.lastDX, bm.lastDY = x, y
		bm.dragAcc = 0
		return
	end
	local dx, dy = x - bm.lastDX, y - bm.lastDY
	if dx == 0 and dy == 0 then return end
	bm.lastDX, bm.lastDY = x, y
	bm.cx = bm.cx - dx / bm.scale
	bm.cy = bm.cy + dy / bm.scale
	local bnd = hud.cl.td.bounds
	bm.cx = math.max(bnd.xMin, math.min(bnd.xMax, bm.cx))
	bm.cy = math.max(bnd.yMin, math.min(bnd.yMax, bm.cy))
	-- pixel-smooth: nudge every placed widget now; re-tile only after most
	-- of a cell of drift (fresh tiles appear at the edges)
	BigMap.reposition(hud)
	if math.abs(bm.cx - (bm.refillCx or bm.cx)) > 0.8
	or math.abs(bm.cy - (bm.refillCy or bm.cy)) > 0.8 then
		BigMap.refill(hud)
	end
end

-- ------------------------------------------------- lock-part action API ----
-- called from GpsMapPart.client_onAction (raw controller actions while the
-- character is locked to the hidden part)
function BigMap.setPan(hud, x, y)
	local bm = hud.cl.bm
	if not (bm and bm.open) then return end
	bm.panKey = bm.panKey or { x = 0, y = 0 }
	if x ~= nil then bm.panKey.x = x end
	if y ~= nil then bm.panKey.y = y end
end

function BigMap.zoomStep(hud, dir)
	local bm = hud.cl.bm
	if not (bm and bm.open) then return end
	bm.scale = math.max(MINSCALE, math.min(MAXSCALE,
		(bm.scale or DEFAULT_SCALE) * (1.15 ^ (dir or 1))))
	BigMap.refill(hud)
end

function BigMap.centerOnPlayer(hud)
	local bm = hud.cl.bm
	if not (bm and bm.open) then return end
	local okc, char = pcall(function() return sm.localPlayer.getPlayer():getCharacter() end)
	if okc and char then
		bm.cx = char.worldPosition.x / 64
		bm.cy = char.worldPosition.y / 64
		bm.tgtCx, bm.tgtCy = bm.cx, bm.cy
		BigMap.refill(hud)
	end
end

function BigMap.waypointAtCenter(hud)
	local bm = hud.cl.bm
	if not (bm and bm.open) then return end
	Waypoint.set(hud, bm.cx * 64, bm.cy * 64)
	BigMap.syncWpUi(hud)
end

-- legacy button handlers (buttons removed in Fants mode; kept as no-ops for
-- any stale gui still dispatching)
function BigMap.btnDown(hud, name)
	local d = BTN_PAN[name]
	if d then BigMap.setPan(hud, d[1], d[2]) end
end

function BigMap.btnUp(hud, name)
	BigMap.setPan(hud, 0, 0)
end

-- shared smooth pan (buttons + WASD keys)
function BigMap.panBy(hud, dcx, dcy)
	local bm = hud.cl.bm
	if not (bm and bm.open) then return end
	local bnd = hud.cl.td.bounds
	bm.cx = math.max(bnd.xMin, math.min(bnd.xMax, bm.cx + dcx))
	bm.cy = math.max(bnd.yMin, math.min(bnd.yMax, bm.cy + dcy))
	bm.tgtCx, bm.tgtCy = bm.cx, bm.cy   -- direct pans cancel any pending lerp
	BigMap.reposition(hud)
	if math.abs(bm.cx - (bm.refillCx or bm.cx)) > 0.8
	or math.abs(bm.cy - (bm.refillCy or bm.cy)) > 0.8 then
		BigMap.refill(hud)
	end
end

-- WASD via the key-capture EditBox: each keystroke arrives as typed text
local KEYPAN = { w = { 0, 1 }, a = { -1, 0 }, s = { 0, -1 }, d = { 1, 0 } }

function BigMap.keys(hud, a, b, c2, d)
	local bm = hud.cl.bm
	if not (bm and bm.open) then return end
	-- arg shape varies by event: take the last non-empty STRING argument as
	-- the field text (widget name is also a string - text arrives after it)
	local text = nil
	for _, v in ipairs({ a, b, c2, d }) do
		if type(v) == "string" and #v > 0 and v ~= "BMKeys" then text = v end
	end
	if not text then return end
	local ch = string.lower(string.sub(text, -1))
	local dir = KEYPAN[ch]
	if dir then
		-- move a TARGET; update() lerps the view toward it every frame -
		-- discrete key-repeat ticks become smooth motion with no overshoot
		local step = 26 / bm.scale
		local bnd = hud.cl.td.bounds
		bm.tgtCx = math.max(bnd.xMin, math.min(bnd.xMax,
			(bm.tgtCx or bm.cx) + dir[1] * step))
		bm.tgtCy = math.max(bnd.yMin, math.min(bnd.yMax,
			(bm.tgtCy or bm.cy) + dir[2] * step))
	end
	-- clear the field so it never fills up
	if bm.keysBox then bm.keysBox.Caption = "" end
end

-- cursor position samplers. Drag events carry screen-global cursor coords
-- (v32 ground truth) but need button-held MOTION; onToolTip is the hover
-- probe (arg shape unknown - logged to bm_events.json, any two numerics are
-- treated as coords). Both feed bm.lastCur.
-- Cursor samples come from two events with different meanings: onDrag fires
-- only while a button is HELD and moving (the player is placing a waypoint
-- right now), onToolTip fires on a plain hover. Both give a usable position,
-- but only the drag one may hide the committed pin (BUG-3) - a hover must
-- never blink it out. The tag is what tells them apart downstream.
local function sample(hud, a, b, c2, d, fromDrag)
	local bm = hud.cl.bm
	if not (bm and bm.open) then return end
	local nums = {}
	for _, v in ipairs({ a, b, c2, d }) do
		if type(v) == "number" then nums[#nums + 1] = v end
	end
	if #nums >= 2 then
		bm.curN = (bm.curN or 0) + 1
		bm.lastCur = { x = nums[1], y = nums[2], t = bm.age or 0, drag = fromDrag }
	end
end

function BigMap.cursor(hud, a, b, c2, d)
	sample(hud, a, b, c2, d, true)
end

-- sampled cursor -> view-local logical coords; tries raw logical space
-- first, then physical-screen scaled (same dual-space rule as cellClick)
function BigMap.curToView(hud, cur)
	local bm = hud.cl.bm
	local vw, vh = hud.cl.vw or 1280, hud.cl.vh or 720
	local cands = { { cur.x, cur.y } }
	local okS, sw, sh = pcall(sm.gui.getScreenSize)
	if okS and type(sw) == "number" and sw > 0
			and type(sh) == "number" and sh > 0 then
		cands[#cands + 1] = { cur.x * vw / sw, cur.y * vh / sh }
	end
	for _, cd in ipairs(cands) do
		local lx, ly = cd[1] - (bm.vx or 0), cd[2] - (bm.vy or 0)
		if lx >= 0 and lx <= bm.VW and ly >= 0 and ly <= bm.VH then
			return lx, ly
		end
	end
	return nil
end

function BigMap.hover(hud, a, b, c2, d)
	local bm = hud.cl.bm
	if not (bm and bm.open) then return end
	bm.hovN = (bm.hovN or 0) + 1
	if bm.hovN <= 8 then
		evlog(hud, "hover", a, b, c2, d)
	end
	sample(hud, a, b, c2, d, false)      -- hover: position only, not a gesture
end

-- tile click: set the waypoint (replaces any existing one). Placement is
-- PRECISE when a fresh sampled cursor position lands on the clicked tile;
-- coords are tried in BOTH spaces (logical view units and physical screen
-- pixels scaled down), tile center is the fallback. v66 proved clean clicks
-- fire NO drag/hover events - v67 probes whether onClick ITSELF carries
-- cursor args beyond the widget name (never verified; extras logged, any
-- two numerics feed the sampler). Diagnostics -> wpDbg -> stats file.
function BigMap.cellClick(hud, name, e1, e2, e3, e4)
	local bm = hud.cl.bm
	local hit = bm and bm.clickMap and bm.clickMap[name]
	if not hit then
		-- BUG-5: this used to return in SILENCE, which is why a lost commit
		-- left no trace anywhere. A release can land on a widget that is not a
		-- pooled cell, or on one a mid-drag refill has since renamed.
		evlog(hud, "clickdrop", tostring(name))
		return
	end
	evlog(hud, "clickargs", e1, e2, e3, e4)
	local nums = {}
	for _, v in ipairs({ e1, e2, e3, e4 }) do
		if type(v) == "number" then nums[#nums + 1] = v end
	end
	if #nums >= 2 then
		bm.lastCur = { x = nums[1], y = nums[2], t = bm.age or 0 }
	end
	local x, y = hit.x * 64 + 32, hit.y * 64 + 32
	local cur = bm.lastCur
	local dbg = { drags = bm.curN or 0, hovers = bm.hovN or 0 }
	if cur and (bm.age or 0) - cur.t < 0.5 then
		local cands = { { cur.x, cur.y, "raw" } }
		local okS, sw, sh = pcall(sm.gui.getScreenSize)
		if okS and type(sw) == "number" and sw > 0
				and type(sh) == "number" and sh > 0 then
			cands[#cands + 1] = { cur.x * (hud.cl.vw or 1280) / sw,
				cur.y * (hud.cl.vh or 720) / sh, "scaled" }
		end
		for _, cd in ipairs(cands) do
			local wx = bm.cx + (cd[1] - (bm.vx or 0) - bm.VW / 2) / bm.scale
			local wy = bm.cy - (cd[2] - (bm.vy or 0) - bm.VH / 2) / bm.scale
			-- sanity: must land on (or a hair beyond) the clicked tile
			if wx >= hit.x - 0.25 and wx <= hit.x + 1.25
			and wy >= hit.y - 0.25 and wy <= hit.y + 1.25 then
				x, y = wx * 64, wy * 64
				dbg.used = cd[3]
				break
			end
		end
		if not dbg.used then
			dbg.miss = { cur.x, cur.y }   -- sampled but resolved off-tile
		end
	else
		dbg.noSample = true               -- no fresh cursor event at click
	end
	hud.cl.wpDbg = dbg
	evlog(hud, "click", dbg.used or (dbg.noSample and "noSample" or "miss"),
		dbg.drags, dbg.hovers)
	if bm.placeMode == "base" then
		Waypoint.setBase(hud, x, y)
		bm.placeMode = nil
		BigMap.syncPoiUi(hud)
		if dbg.used then bm.lastCur = nil end
		return
	end
	local farmPlace = bm.placeMode and string.match( bm.placeMode, "^farm_(%a+)$" )
	if farmPlace then
		Waypoint.setFarm(hud, farmPlace, x, y)
		bm.placeMode = nil
		BigMap.syncPoiUi(hud)
		if dbg.used then bm.lastCur = nil end
		return
	end
	Waypoint.set(hud, x, y)
	BigMap.syncWpUi(hud)
	-- EXPIRE ON USE (BUG-2's principle, and it stops the drag-end path below
	-- from committing the same gesture a second time): a sample that has been
	-- spent must not be reachable again. Only when it was actually used - an
	-- off-tile sample stays put so the miss keeps showing up in telemetry.
	if dbg.used then bm.lastCur = nil end
end

-- Commit a waypoint straight from a cursor sample, with NO widget name
-- involved: the sample's screen coordinates are all the information needed.
-- This is what lets a drag commit itself when no onClick ever arrives (BUG-5).
function BigMap.commitAt(hud, cur)
	local bm = hud.cl.bm
	if not (bm and bm.open) then return false end
	local lx, ly = BigMap.curToView(hud, cur)
	if not lx then return false end          -- released outside the map view
	local wx = bm.cx + (lx - bm.VW / 2) / bm.scale
	local wy = bm.cy - (ly - bm.VH / 2) / bm.scale
	local b = hud.cl.td and hud.cl.td.bounds
	if b then
		wx = math.max(b.xMin, math.min(b.xMax + 1, wx))
		wy = math.max(b.yMin, math.min(b.yMax + 1, wy))
	end
	hud.cl.wpDbg = { used = "dragEnd", drags = bm.curN or 0,
		hovers = bm.hovN or 0 }
	evlog(hud, "dragend", string.format("%.2f,%.2f", wx, wy))
	local x, y = wx * 64, wy * 64
	if bm.placeMode == "base" then
		Waypoint.setBase(hud, x, y)
		bm.placeMode = nil
		BigMap.syncPoiUi(hud)
		return true
	end
	local farmPlace = bm.placeMode and string.match( bm.placeMode, "^farm_(%a+)$" )
	if farmPlace then
		Waypoint.setFarm(hud, farmPlace, x, y)
		bm.placeMode = nil
		BigMap.syncPoiUi(hud)
		return true
	end
	Waypoint.set(hud, x, y)
	BigMap.syncWpUi(hud)
	return true
end
