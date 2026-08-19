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
local MINSCALE, MAXSCALE = 26, 110
-- MINI TIER ONLY (v37): the RotatingSkin big tier garbled at arbitrary
-- sizes (v31 - the last clean build - kept those widgets at exactly their
-- creation size; every arbitrary-size build since garbled). Plain ImageBox
-- resize is proven safe (minimap rim does it every frame). Mini frames are
-- 64px: slightly soft above ~64px/cell - correctness over crispness.
local TIERS = {
	{ px = 32, tier = "mini" },
}
-- with pruned render trees (v31) pool size no longer costs FPS - sized so
-- overflow is impossible (city tiles stack 64 subcells into ONE resource)
local POOLCAP = {
	{ per = 1100, roads = 220 },
}
-- 0851-d: spread ~1320 pool widgets across frames during background prebuild
-- (GPS open burst was ~1554 widgets in one frame).
local POOL_BUILD_STEP = 72
local MARKER = 22
local POILABELS = 24
-- seconds without a new drag sample that count as "the button was released".
-- Matched to the ghost's own 0.25 s freshness window so the committed pin
-- appears on exactly the frame the ghost disappears (BUG-5).
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
	for ti, T in ipairs(TIERS) do
		local pool = { byRes = {}, roads = {}, used = {}, roadsUsed = 0 }
		bm.pools[ti] = pool
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
		if q.kind == "cell" then
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

		-- viewport (clips its children = the map cells)
		local VW, VH = vw - 160, vh - 110
		local vx, vy = 80, 64
		bm.VW, bm.VH = VW, VH

		-- NeedMouse=true ONLY on clickables + their ancestor chain (root/view/
		-- cells/buttons): any other pick-enabled widget SWALLOWS the picks -
		-- v19's fullscreen backdrop ate every click (buttons dead, map stuck)
		local root = W("BMRoot", "Widget", "PanelEmpty", 0, 0, vw, vh)
		local back = W("BMBack", "Widget", "WhiteSkin", 0, 0, vw, vh,
			{ Colour = "0 0 0", Alpha = 0.8, NeedMouse = false })
		local view = W("BMView", "Widget", "PanelEmpty", vx, vy, VW, VH, {
			onMouseWheel = "cl_bm_wheel" })
		root.Childs = { back, view }
		bm.view = view

		-- water backdrop (stretched water frame; water cells are never drawn)
		local waterRes = c.atlas.mini["water_r0"].res
		bm.water = W("BMWater", "ImageBox", "ImageBox",
			0, 0, VW, VH, { ImageResource = waterRes, ImageGroup = waterRes,
			  ImageName = "water_r0", NeedMouse = false })
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
		vx, 18, 340, 30, {
		  -- players see the public version only (Eric). The build number that
		  -- ties a report to an exact ship still goes to the stats file and to
		  -- the bm_events "session" marker written on every map open - and to
		  -- the title itself in the dev copy (titleFor).
		  Caption = titleFor(c),
		  FontName = "SM_HeaderLarge_Medium",
		  TextAlign = "Left", TextShadow = true, NeedMouse = false })
	-- minimap show/hide, mirrored with Q's hidden stop (pos 5 IS hidden -
	-- one shared state). Caption shows the CURRENT state; a click flips it.
	local mmb = btn("BMMini", (c.posIdx == 5) and "MINIMAP: OFF" or "MINIMAP: ON",
		vx + VW - 448, 16, 152)
	root.Childs[#root.Childs + 1] = mmb
	bm.mmBtn = mmb
	root.Childs[#root.Childs + 1] = btn("BMZoomOut", "-", vx + VW - 288, 16, 48)
	root.Childs[#root.Childs + 1] = btn("BMZoomIn", "+", vx + VW - 232, 16, 48)
	root.Childs[#root.Childs + 1] = btn("BMYou", "YOU", vx + VW - 176, 16, 64)
	root.Childs[#root.Childs + 1] = btn("BMClose", "CLOSE [E]", vx + VW - 104, 16, 104, "PrimaryButton")
	-- arrows hug their map edge exactly like the top bar hugs the map top
	-- (0px gap), centered along each side
	root.Childs[#root.Childs + 1] = btnPan("BMPanW", "arrow_left_b1.png", vx - 48, vy + math.floor((VH - 48) / 2))
	root.Childs[#root.Childs + 1] = btnPan("BMPanE", "arrow_right_b1.png", vx + VW, vy + math.floor((VH - 48) / 2))
	root.Childs[#root.Childs + 1] = btnPan("BMPanN", "arrow_up_b1.png", vx + math.floor((VW - 48) / 2), vy - 48)
	root.Childs[#root.Childs + 1] = btnPan("BMPanS", "arrow_down_b1.png", vx + math.floor((VW - 48) / 2), vy + VH)

	-- waypoint controls (Eric v66 feedback): OFF the map, in the strip below
	-- it, right-aligned - mirroring how CLOSE sits in the strip above. 5
	-- always-visible color dot buttons; the SELECTED color shows the teardrop
	-- pin (circle-height, Eric v66) instead of the flat circle. CLEAR
	-- WAYPOINT greys via a dark overlay child and no-ops while no waypoint
	-- exists.
	local clrW = 190
	local clrX = vx + VW - clrW
	local wpY = vy + VH
	local dotX = clrX - 12 - (5 * 46 - 6)
	bm.colDot = {}
	for i, col in ipairs(Waypoint.COLORS) do
		local b = W("BMWpCol_" .. col, "Button", "StyledButtonLarge",
			dotX + (i - 1) * 46, wpY + 4, 40, 40,
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
	bm.vx, bm.vy = vx, vy

	bm.root = root
	bm.clickMap = {}

	-- OVERLAY GUI (gui2): within-gui z-order against the tile pools is a
	-- texture-batching lottery (Eric v71: drag ghost behind some tiles) -
	-- marker/pin/ghost VISUALS get render-only copies in a HUD-layer gui
	-- that reliably draws above this screen gui (the vanilla health bar
	-- proves HUD layers > screen guis). Originals stay in the interactive
	-- gui for clicks + viewport clipping; update() mirrors positions and
	-- hides overlay copies at the viewport edge (gui2 has no clip parent).
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
						local p = poi[stripDashes(tostring(uid))]
						if p and (not xrow or (xrow[wx] or 0) == 0)
						     and (not yrow or (yrow[wx] or 0) == 0) then
							anchors[#anchors + 1] = { label = p.label, tier = p.tier or 1,
								sx = p.sx or 1,
								cx = wx + (p.sx or 1) / 2, cy = wy + (p.sy or 1) / 2 }
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
	bm.scale = math.max(MINSCALE, math.min(MAXSCALE, bm.scale or 34))
	bm.tierIdx = 1
	local T = TIERS[bm.tierIdx]
	local px = bm.scale
	local pxi = math.max(2, math.floor(px + 0.5))
	local pool = bm.pools[bm.tierIdx]
	pool.used = {}
	pool.roadsUsed = 0
	bm.clickMap = {}
	-- placed registry for the smooth-pan reposition pass (v35)
	bm.placed = {}
	bm.refillCx, bm.refillCy = bm.cx, bm.cy
	local VW, VH = bm.VW, bm.VH
	local x0 = math.floor(bm.cx - VW / (2 * px)) - 1
	local x1 = math.ceil(bm.cx + VW / (2 * px)) + 1
	local y0 = math.floor(bm.cy - VH / (2 * px)) - 1
	local y1 = math.ceil(bm.cy + VH / (2 * px)) + 1
	local skipped = 0
	-- EXACT ABUTMENT (v40): each cell's width/height = neighbor edge minus
	-- own edge. Rounding scale once (pxi) left 1px gaps at fractional scales
	-- (spacing 79, width 78) with the cyan water backdrop showing through -
	-- Eric's "tile borders at some zoom levels".
	local function edgeX(wx) return math.floor(VW / 2 + (wx - bm.cx) * px + 0.5) end
	local function edgeY(wy) return math.floor(VH / 2 - (wy - bm.cy) * px + 0.5) end
	local function assign(f, sx, sy, w, h, wx, wy)
		local lst = pool.byRes[f.res]
		if not lst then return false end
		local u = (pool.used[f.res] or 0) + 1
		if u > #lst then return false end
		-- a widget pinned by an active drag keeps its assignment (recycling
		-- the pressed widget kills the engine's drag session)
		local cw = lst[u]
		if cw and cw.Name == bm.pinName then
			u = u + 1
			cw = lst[u]
			if not cw then return false end
		end
		pool.used[f.res] = u
		bm.placed[#bm.placed + 1] = { w = cw, wx = wx, wy = wy, rs = T.rotskin }
		cw.Visible = true
		-- THE LINE the v34 refactor dropped (five builds of "garbled tiles"):
		-- without it every widget renders its creation-time default frame
		cw.ImageName = f.name
		cw.x = sx; cw.y = sy
		-- +1 DRAW OVERLAP (8/14): logical abutment is exact (v40), but the
		-- engine scales this 1280x720-logical gui to physical pixels PER
		-- WIDGET, and at fractional scales (1080p = 1.5x) neighbors can round
		-- 1 physical px apart - crawling background lines between tiles.
		-- Overlapping the draw rect by 1 logical px covers any such gap;
		-- layout math (edges, clickMap) stays on the exact values.
		cw.width = w + 1; cw.height = h + 1
		if T.rotskin then
			cw.RotatingSkinAngle = (f.rot or 0) * ROTSIGN * (math.pi / 2)
			cw.RotatingSkinCenterX = math.floor((w + 1) / 2)
			cw.RotatingSkinCenterY = math.floor((h + 1) / 2)
		end
		bm.clickMap[cw.Name] = { x = wx, y = wy }
		return true
	end
	local atlas = hud.cl.atlas
	for wy = y0, y1 do
		for wx = x0, x1 do
			local f, flags, real = BigMap.resolve(hud, wx, wy, T.tier)
			if f then
				local sx = edgeX(wx)
				local sy = edgeY(wy + 1)
				local w = edgeX(wx + 1) - sx
				local h = edgeY(wy) - sy
				local done = assign(f, sx, sy, w, h, wx, wy)
				if not done then
					-- primary pool saturated (monotile region): degrade to
					-- the biome-tint frame, which lives in a different pool
					local t = math.floor((flags or 0) / 4096) % 16
					local fbName, tbl
					if T.tier == "mini" then
						fbName = (t >= 1 and t <= 8) and ("biome_" .. t .. "_r0") or "unknown_r0"
						tbl = atlas.mini
					else
						fbName = (t >= 1 and t <= 8) and ("biome_" .. t) or "unknown"
						tbl = atlas.big
					end
					local h2 = tbl[fbName]
					if h2 and h2.res ~= f.res then
						done = assign({ res = h2.res, name = fbName, rot = 0 }, sx, sy, w, h, wx, wy)
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
					bm.placed[#bm.placed + 1] = { w = ov, wx = wx, wy = wy }
				end
			end
		end
	end
	bm.skipped = skipped
	-- hide leftovers (both tiers; the inactive tier hides fully)
	for ti = 1, #TIERS do
		local p = bm.pools[ti]
		for res, lst in pairs(p.byRes) do
			local u = (ti == bm.tierIdx and (pool.used[res] or 0)) or 0
			for i = u + 1, #lst do lst[i].Visible = false end
		end
		local ru = (ti == bm.tierIdx) and pool.roadsUsed or 0
		for i = ru + 1, #p.roads do p.roads[i].Visible = false end
	end
	-- POI labels: only sized landmarks (829 raw anchors in a typical world -
	-- unfiltered is label soup). Region view: 4+ cell tiles; close-up: 2+.
	local minSx = (bm.scale >= 40) and 2 or 4
	local li = 0
	for _, a in ipairs(bm.anchors or {}) do
		if (a.sx or 1) >= minSx and li < #bm.poiLabels then
			local sx = VW / 2 + (a.cx - bm.cx) * px
			local sy = VH / 2 - (a.cy - bm.cy) * px
			if sx > -80 and sx < VW + 80 and sy > -20 and sy < VH + 20 then
				li = li + 1
				local tb = bm.poiLabels[li]
				tb.Visible = true
				tb.Caption = a.label
				tb.x = math.floor(sx - 70)
				tb.y = math.floor(sy - 9)
				bm.placed[#bm.placed + 1] = { w = tb, ax = a.cx, ay = a.cy, lbl = true }
			end
		end
	end
	for i = li + 1, #bm.poiLabels do bm.poiLabels[i].Visible = false end

	-- PRUNED render tree (v31): render(root) cost is proportional to the
	-- tree handed over, NOT to visible pixels - only used widgets go in.
	-- A drag-pinned widget is always included (once) so the engine keeps
	-- its drag session alive.
	local pinW = bm.pinName and bm.widgetByName and bm.widgetByName[bm.pinName]
	local vc = { bm.water }
	for res, lst in pairs(pool.byRes) do
		for i = 1, (pool.used[res] or 0) do
			if lst[i] ~= pinW then vc[#vc + 1] = lst[i] end
		end
	end
	for i = 1, pool.roadsUsed do vc[#vc + 1] = pool.roads[i] end
	for i = 1, li do vc[#vc + 1] = bm.poiLabels[i] end
	if pinW then vc[#vc + 1] = pinW end
	vc[#vc + 1] = bm.marker
	-- all color pins + placement ghosts stay in the tree (10 widgets):
	-- visibility is per-frame state in update(), no refill needed to appear
	for _, col in ipairs(Waypoint.COLORS) do
		vc[#vc + 1] = bm.wpPins[col]
		vc[#vc + 1] = bm.wpGhost[col]
	end
	bm.view.Childs = vc
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
	local px = bm.scale or 34
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
	local dotCol = string.match(name, "^BMWpCol_(%a+)$")
	if dotCol then
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
		bm.scale = math.min(MAXSCALE, (bm.scale or 34) * 1.3)
	elseif name == "BMZoomOut" then
		bm.scale = math.max(MINSCALE, (bm.scale or 34) / 1.3)
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
-- wheel: single fire (prop on the view only), delta = 2nd arg (±120)
function BigMap.wheel(hud, name, delta)
	local bm = hud.cl.bm
	if not (bm and bm.open) then return end
	local dir = (tonumber(delta) or 120) >= 0 and 1 or -1
	bm.scale = math.max(MINSCALE, math.min(MAXSCALE,
		(bm.scale or 34) * (1.15 ^ dir)))
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
			-- exact abutment during pans too: edges recomputed per cell, so
			-- boundary rounding can never open 1px gaps (+1 draw overlap for
			-- the engine's PHYSICAL per-widget rounding, same as assign)
			local sx = floor(VW / 2 + (p.wx - bm.cx) * px + 0.5)
			local sy = floor(VH / 2 - (p.wy - bm.cy + 1) * px + 0.5)
			p.w.x = sx
			p.w.y = sy
			p.w.width = floor(VW / 2 + (p.wx + 1 - bm.cx) * px + 0.5) - sx + 1
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
		(bm.scale or 34) * (1.15 ^ (dir or 1))))
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
	-- click diagnostics straight to bm_events.json too: the 30s stats cadence
	-- lost v65's wpdbg to a quit (stats had wpdbg=null despite a click)
	evlog(hud, "click", dbg.used or (dbg.noSample and "noSample" or "miss"),
		dbg.drags, dbg.hovers)
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
	Waypoint.set(hud, wx * 64, wy * 64)
	BigMap.syncWpUi(hud)
	return true
end
