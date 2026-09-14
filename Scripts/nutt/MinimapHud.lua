-- World Map: always-on minimap HUD (autoTool client script).
-- Vendored into Remastered Framework Survival with permission. Credit: Nutt
-- (Steam Workshop 3780282057). Performance and dev-telemetry ideas: KomiSanN
-- (MinimapHud.zip community contribution).
-- North-up scrolling cell grid from the packed atlas sheets, rotating player
-- arrow, water/biome/road fallbacks for unknown tiles. Works on any seed:
-- reads the world's cell grid client-side via sm.storage.loadTerrainData.

MinimapHud = class()

-- jsonGui ImageTexture / IconMap do not resolve $CONTENT_DATA (blank tiles/icons).
local C = "$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247"
local NILUUID = "00000000000000000000000000000000"

-- layout (sized from screen height at build time; see cl_buildGui)
local MARGIN = 24
local ROADMASK = 0x0F00
-- zoom = cells across the ring window. Biome mode: always 1 (current cell only).
local ZOOMS = { 1, 3, 4, 6, 9, 13 }
-- thin gold marquee only (Eric 8/8: thick gold "yuck", dark band rejected
-- too) - rim-tile pokes stay visible until real clipping (spike) is answered.
-- texture version + build number: the engine caches textures BY PATH beyond
-- mod\Cache, so changed artwork needs a new filename (bump with gen_bezels VER)
local BEZELVER = "b5"
-- VERSION = the mod's public semantic version (what a player sees, what release
-- notes talk about). BUILD = an internal monotonic counter that ship.py bumps on
-- every single ship; it exists purely so a report can be tied to an exact build.
-- Only VERSION shows in the big map title (Eric); BUILD reports itself through
-- minimap_stats.json and the bm_events "session" marker, which is enough to catch
-- "that run was actually an older build" (the v31/v34/v35 lesson).
-- NOTE: description.json's "version" is NOT this - it is a game-side integer
-- (0 there brings back the MODS OUTDATED launch warning) and must stay at 2.
local VERSION = "1.1.2"
local BUILD = 49
-- Mini atlas frames are baked as _r0.._r3. If roads/tiles look twisted vs
-- neighbors (classic collage), terrain.rotation sense != bake sense — flip.
-- Same idea as BigMap ROTSIGN for the r0+RotatingSkin tier.
local FLIP_CELL_ROT = true
-- vanilla StatusPanel: 196x86 bottom-left, health row at local y 42 ->
-- health bar top = vh - 44 (SurvivalPlayer.lua:425, StatusPanel.gui)
local HEALTHTOP = 44
local HEALTHGAP = 15

local function stripDashes(s)
	return (string.gsub(s, "%-", ""))
end

-- build flags (g_wmFlags) - release vs the generated dev copy. FIRST, so the
-- modules below can read it; see Scripts/Flags.lua before adding one.
dofile(C .. "/Scripts/nutt/Flags.lua")
-- big map module (module table BigMap; callbacks below delegate to it)
pcall( function()
	dofile( C .. "/Scripts/game/RfsBiomeMap.lua" )
end )
dofile(C .. "/Scripts/nutt/BigMap.lua")
-- waypoint state + compass tracking (module table Waypoint)
dofile(C .. "/Scripts/nutt/Waypoint.lua")

-- PROBE resolved (run 9): the engine drops a ResourceImageSet wholesale above
-- ~2.5-3.8k Index entries. Sheets now register as partitioned resources.
local PROBE = false

-- ------------------------------------------------------------- server ------
local GPSTOOL = "d96c2fe4-177b-49bb-be40-e4b1bcdd8f76"

-- SELF-HEALING GRANT (v77). The craftbot recipe can NOT be the obtainment path:
-- there is no engine-level mod recipe merge anywhere in the game. Every recipe
-- set is a hardcoded Lua table (SurvivalGame/CreativeGame loadCraftingRecipes),
-- and the only reason Fants' addon recipes craft is that HIS custom game scans
-- the third-party ModDatabase registry of published mod localIds and loads each
-- one's CraftingRecipes/craftbot.json itself. We are not in that registry and a
-- generic custom game does no scan at all, so the recipe stays shipped as a
-- bonus and the tool grants itself here instead.
--
-- Self-healing rather than once-per-player on purpose: a chat command to hand
-- the GPS back is impossible (bindChatCommand is a sandbox violation and is
-- absent from the mod API surface), so instead the server re-grants whenever
-- the tool is missing from the owner's inventory - lost, dropped, destroyed or
-- a brand new world all recover on their own within GRANT_PERIOD.
local GRANT_PERIOD = 200            -- ticks; 40/s -> check every 5 s

function MinimapHud.server_onCreate( self )
	self.sv = { done = false, tries = 0, tick = 0, grants = 0 }
	-- (v71 recipe-unlock storage injection REMOVED: sm.storage channels are
	-- DOMAIN-ISOLATED per mod - our load(49) sees the mod's own empty domain,
	-- never the game's RecipeManager data.)
end

function MinimapHud.server_onFixedUpdate( self )
	if not self.sv then return end
	self.sv.tick = ( self.sv.tick or 0 ) + 1
	if self.sv.tick < GRANT_PERIOD then return end
	self.sv.tick = 0
	self:sv_ensureGpsTool()
end

-- returns true when the owner ends up holding a GPS (already had one, or we
-- just put one in). Inventory writes are server-side only; runs per player in MP.
function MinimapHud.sv_ensureGpsTool( self )
	local ok, err = pcall( function()
		local player = self.tool:getOwner()
		if not player then return end
		local inv = player:getInventory()
		if not inv then return end
		local uuid = sm.uuid.new( GPSTOOL )
		if sm.container.totalQuantity( inv, uuid ) > 0 then
			self.sv.has = true
			return
		end
		self.sv.has = false
		if sm.container.beginTransaction() then
			sm.container.collect( inv, uuid, 1, false )
			if sm.container.endTransaction() then
				self.sv.has = true
				self.sv.grants = ( self.sv.grants or 0 ) + 1
			end
		end
	end )
	if not ok then
		self.sv.grantErr = tostring( err )   -- e.g. inventory full; retried next period
	end
	return ok and self.sv.has == true
end

-- hidden lock-part lifecycle (Fants pattern): spawned 20 m underground on
-- big-map open, the character locks to it so its client_onAction gets raw
-- WASD/wheel/click input; destroyed on close
local GPSLOCKPART = "9f2b7c44-5d1e-4a8f-b6c3-2e9d0a7f4b21"

function MinimapHud.sv_bm_spawnLock( self )
	-- server-side execution trace: written to a file the dev can read
	-- directly (server cannot chat)
	local dbg = { entered = true }
	local function trace()
		pcall(sm.json.save, dbg, "$CONTENT_DATA/sv_lock_debug.json")
	end
	if self.sv and self.sv.lockPart and sm.exists(self.sv.lockPart) then
		dbg.earlyReturn = "part already exists"
		trace()
		return
	end
	local okO, player = pcall(function() return self.tool:getOwner() end)
	dbg.ownerOk = okO
	dbg.owner = tostring(player)
	local ok, err = pcall(function()
		local char = player:getCharacter()
		dbg.char = tostring(char)
		self.sv = self.sv or {}
		self.sv.lockPart = sm.shape.createPart(sm.uuid.new(GPSLOCKPART),
			char.worldPosition - sm.vec3.new(0, 0, 20), sm.quat.identity(), false, true)
		dbg.part = tostring(self.sv.lockPart)
	end)
	dbg.createOk = ok
	dbg.createErr = tostring(err)
	trace()
	if ok and self.sv.lockPart then
		local okC, errC = pcall(function()
			self.network:sendToClient(player, "cl_bm_lockReady")
		end)
		dbg.replyOk = okC
		dbg.replyErr = tostring(errC)
		trace()
	else
		pcall(function()
			self.network:sendToClient(player, "cl_bm_lockFail", tostring(err))
		end)
	end
end

function MinimapHud.cl_bm_lockReady( self )
	self.network:sendToServer("sv_bm_bindPlayer")
end

function MinimapHud.cl_bm_lockFail( self, err )
end

function MinimapHud.sv_bm_bindPlayer( self )
	if self.sv and self.sv.lockPart and sm.exists(self.sv.lockPart) then
		sm.event.sendToInteractable(self.sv.lockPart.interactable,
			"sv_setPlayer", self.tool:getOwner())
	end
end

function MinimapHud.sv_bm_destroyLock( self )
	if self.sv and self.sv.lockPart and sm.exists(self.sv.lockPart) then
		pcall(function() self.sv.lockPart:destroyShape(0) end)
	end
	if self.sv then self.sv.lockPart = nil end
end

-- GPS tool client queues these; server forwards to Game.lua (tool network context).
function MinimapHud.sv_n_rfsMapMarker( self, params )
	sm.event.sendToGame( "sv_e_rfsMapMarker", params )
end

function MinimapHud.sv_n_rfsMapMarkerGet( self, params )
	local player = nil
	pcall( function() player = self.tool:getOwner() end )
	sm.event.sendToGame( "sv_e_rfsMapMarkerGet", { player = player } )
end

function MinimapHud.sv_n_rfsGpsPrefsSet( self, params )
	local player = nil
	pcall( function() player = self.tool:getOwner() end )
	params = type( params ) == "table" and params or {}
	params.player = player
	sm.event.sendToGame( "sv_e_rfsGpsPrefsSet", params )
end

function MinimapHud.sv_n_rfsGpsPrefsGet( self, params )
	local player = nil
	pcall( function() player = self.tool:getOwner() end )
	sm.event.sendToGame( "sv_e_rfsGpsPrefsGet", { player = player } )
end

-- (the GPS grant lives at the top of the server section - sv_ensureGpsTool.
-- CraftingRecipes/craftbot.json still ships, as a bonus for the custom games
-- that scan mod recipes themselves.)

-- MULTIPLAYER GATE (v2, build 43): MinimapHud is the autoTool, so every
-- player's tool is instantiated CLIENT-SIDE on every machine. Ungated (b41),
-- a remote player's instance built a SECOND full HUD centred on
-- sm.localPlayer: two cell grids at different per-instance zoom in one ring,
-- two arrows, mixed telemetry, guis that outlived the player who owned them.
-- Build 42 gated on self.tool:isLocal() - which fixed the HOST and NOT the
-- joining client (8/13: on the friend's machine the host's instance still
-- passed the gate, so isLocal() cannot be trusted there). Fants Map, the one
-- MP-proven autoTool, never gates on isLocal: every handler checks
-- self.tool:getOwner() == sm.localPlayer.getPlayer() at call time. Mirror
-- that: init ONLY on a positive owner match. A nil owner means "not resolved
-- yet, keep waiting" (client_onUpdate retries), never "assume local".
local function toolIsLocal( self )
	local ok, res = pcall(function()
		local owner = self.tool:getOwner()
		if owner == nil then return false end
		return owner == sm.localPlayer.getPlayer()
	end)
	return ok and res == true
end

-- positive evidence this instance belongs to ANOTHER player (nil owner is
-- NOT evidence - never tear down the real HUD on a transient nil)
local function toolIsRemote( self )
	local ok, res = pcall(function()
		local owner = self.tool:getOwner()
		if owner == nil then return false end
		return owner ~= sm.localPlayer.getPlayer()
	end)
	return ok and res == true
end

function MinimapHud.client_onCreate( self )
	if toolIsLocal(self) then
		self:cl_init()
	end
end

-- close everything this instance ever put on screen and return to the
-- uninitialized state. Runs on tool destroy (a leaving player's guis used to
-- stay frozen on everyone else's screen - the surviving second arrow, 8/13)
-- and on demotion (the self-heal below, when a join-time wrong answer let a
-- remote instance init).
function MinimapHud.cl_shutdown( self )
	local c = self.cl
	if c == nil then return end
	pcall(function() if c.gui then c.gui:close() end end)
	pcall(function() if c.gui3 then c.gui3:close() end end)
	local bm = c.bm
	if bm then
		pcall(function() if bm.gui then bm.gui:close() end end)
		pcall(function() if bm.gui2 then bm.gui2:close() end end)
	end
	if g_minimapHud == self then g_minimapHud = nil end
	self.cl = nil
end

function MinimapHud.client_onDestroy( self )
	self:cl_shutdown()
end

function MinimapHud.cl_init( self )
	-- MP diagnostics (shared globals across instances): inits > 1 in a
	-- session means the owner gate passed for more than one instance -
	-- exactly what a pasted stats blob needs to show if MP misbehaves again
	g_wmMpInits = (g_wmMpInits or 0) + 1
	self.cl = {
		ready = false, retryT = 0, td = nil, worldId = nil,
		gui = nil, root = nil, cells = nil, overlays = nil,
		baseX = nil, baseY = nil, hidden = false,
		statT = 0, dtMax = 0, frames = 0,
		probePage = 0, probeT = 0,
		zoomIdx = 1,
		wpColor = "red",
		-- minimap placement (Eric 8/14): posIdx 1-4 = BL/BR/TR/TL corner,
		-- 5 = hidden; lastPos = the corner to return to from hidden
		posIdx = 1, lastPos = 1, sizeIdx = 2,
	}
	local oks, st = pcall( function() return Waypoint.readSettings() end )
	if oks and type(st) == "table" then
		-- Biome single-cell mode: always 1 cell across (ignore saved zoom).
		if type( RfsBiomeMap ) == "table" and RfsBiomeMap.SINGLE_CELL_MINIMAP then
			self.cl.zoomIdx = 1
		elseif st.zoom and ZOOMS[st.zoom] then
			self.cl.zoomIdx = st.zoom
		end
		if type(st.wp) == "table" and st.wp.x then self.cl.waypoint = st.wp end
		if type(st.wpc) == "string" and Waypoint.valid(st.wpc) then
			self.cl.wpColor = st.wpc
		end
		if type(st.base) == "table" and st.base.x then self.cl.baseMarker = st.base end
		if type(st.farms) == "table" then self.cl.farmMarkers = st.farms end
		if type(st.poiFilters) == "table" then self.cl.poiFilters = st.poiFilters end
		if type(st.pos) == "number" and st.pos >= 1 and st.pos <= 5 then
			self.cl.posIdx = math.floor(st.pos)
		end
		if type(st.posl) == "number" and st.posl >= 1 and st.posl <= 4 then
			self.cl.lastPos = math.floor(st.posl)
		end
		if type(st.size) == "number" and st.size >= 1 and st.size <= 3 then
			self.cl.sizeIdx = math.floor(st.size)
		end
	end
	-- restore the compass icon for a persisted waypoint / home (runs once ready)
	if self.cl.waypoint or self.cl.baseMarker then self.cl.wantCompassSync = true end
	g_minimapHud = self                -- SpikeHand cycles debug view modes
	-- Flush host markers that arrived before this HUD existed (MP join race).
	pcall( function()
		if type( Waypoint ) == "table" and Waypoint.flushPending then
			Waypoint.flushPending( self )
		end
	end )
	-- MP shared markers (host-authoritative) — pull after local file restore
	pcall( function()
		if type( Waypoint ) == "table" and Waypoint.requestShared then
			Waypoint.requestShared()
		end
	end )
	pcall( function()
		if type( Waypoint ) == "table" and Waypoint.requestGpsPrefs then
			Waypoint.requestGpsPrefs()
		end
	end )
	pcall( function()
		local pending = _G.g_rfsGpsPrefsPending
		if type( pending ) == "table" and type( Waypoint ) == "table" and Waypoint.applyGpsPrefs then
			Waypoint.applyGpsPrefs( self, pending )
			_G.g_rfsGpsPrefsPending = nil
		end
	end )
	local okp, poi = pcall(sm.json.open, C .. "/Scripts/nutt/data/poi_names.json")
	if okp and type(poi) == "table" then self.cl.poi = poi end
	local ok, idx = pcall(sm.json.open, C .. "/Scripts/nutt/data/atlas_index.json")
	if ok and idx then
		self.cl.atlas = idx
	else
		sm.gui.chatMessage("[minimap] atlas index failed to load: " .. tostring(idx))
	end
	self.cl.debugMode = 0
	self.cl.build = BUILD              -- shown in the big map title
	self.cl.version = VERSION
	-- one-time API surface dump: hunting for a chat-open getter (map must
	-- hide under the chat box, which shares our bottom gui layer)
	local dump = {}
	for _, t in ipairs({ { "gui", sm.gui }, { "jsonGui", sm.jsonGui },
			{ "camera", sm.camera }, { "localPlayer", sm.localPlayer } }) do
		local keys = {}
		for k, v in pairs(t[2]) do keys[#keys + 1] = k .. ":" .. type(v) end
		table.sort(keys)
		dump[t[1]] = keys
	end
	if g_wmFlags and g_wmFlags.DEV then
		pcall(sm.json.save, dump, C .. "/api_dump.json")
	end
	-- recipe-merge probe: does the engine merge our CraftingRecipes/
	-- craftbot.json into the survival recipe set files the craftbot grid is
	-- populated from? Read each set from OUR context and search for the GPS
	-- uuid. -> stats 'recipeDbg' answers merged-where (or not at all).
	local rd = { sets = {} }
	local okE, en = pcall(function() return sm.game.getRecipesEnabled() end)
	rd.recipesEnabled = okE and en or ("err")
	local setNames = { "craftbot_core", "craftbot_manmade", "craftbot_small_pipes",
		"craftbot_pipes", "craftbot_generatorpipes", "craftbot_building",
		"craftbot_industrial", "craftbot_beams", "craftbot_plants",
		"craftbot_decor", "craftbot_other", "craftbot_lights",
		"craftbot_treasures", "craftbot_rewards" }
	for _, sn in ipairs(setNames) do
		local okR, j = pcall(sm.json.open,
			"$SURVIVAL_DATA/CraftingRecipes/craftbot/" .. sn .. ".json")
		if okR and type(j) == "table" then
			for _, r in ipairs(j) do
				if r.itemId == GPSTOOL then
					rd.sets[#rd.sets + 1] = sn
					break
				end
			end
		elseif not okR then
			rd.openFail = (rd.openFail or 0) + 1
		end
	end
	rd.found = #rd.sets > 0
	self.cl.recipeDbg = rd
	print("[minimap] created")
end

-- debug views (cycled by equipping SpikeHand):
--   0 normal | 1 every slot shows ITS resource's first frame | 2 partition
--   color map (flat color per resource, drawn from the proven 1_1 partition)
function MinimapHud.cl_debugCycle( self )
	local c = self.cl
	c.debugMode = (c.debugMode + 1) % 3
	if not c.firstOf and c.atlas then
		c.firstOf = {}
		for name, v in pairs(c.atlas.mini) do
			if not c.firstOf[v.res] or name < c.firstOf[v.res] then
				c.firstOf[v.res] = name
			end
		end
	end
	c.baseX = nil                      -- force refill in new mode
end

-- ---------------------------------------------------------------- terrain --
function MinimapHud.cl_tryLoadTerrain( self )
	local okw, wid = pcall(function()
		return sm.localPlayer.getPlayer():getCharacter():getWorld().id
	end)
	if not okw then return end
	local ok, td = pcall(sm.storage.loadTerrainData, wid)
	if ok and td and td.bounds and td.uid then
		self.cl.td = td
		self.cl.worldId = wid
		self.cl.ready = true
		Waypoint.loadWorld( self )
		pcall( function()
			if type( BigMap ) == "table" and BigMap.ensureViewSize then
				BigMap.ensureViewSize( self )
			end
		end )
		-- 0851-d: defer HUD widget burst until move or ~2.5s after terrain ready
		self.cl.deferActive = true
		self.cl.deferT = 0
		self.cl.deferPos = nil
		-- no chat output in normal operation (Eric 8/8) - build/seed go to
		-- the stats file instead; chat is reserved for errors only
	end
end

function MinimapHud.cl_frameFor( self, wx, wy, rot )
	-- Optional solid biomes on the corner HUD (default off — show atlas tiles).
	if type( RfsBiomeMap ) == "table" and RfsBiomeMap.SOLID_MINIMAP then
		local f, flags = RfsBiomeMap.resolveFrame( self.cl.td, self.cl.atlas, wx, wy, "mini" )
		if f then
			return f, flags or 0, false
		end
		return self:cl_fallback( "water", 0 ), 0, false
	end
	-- returns imageset resource + frame name for world cell (wx, wy)
	local td = self.cl.td
	local b = td.bounds
	if wx < b.xMin or wx > b.xMax or wy < b.yMin or wy > b.yMax then
		return self:cl_fallback("water", rot)
	end
	local uidRow = td.uid[wy]
	local uid = uidRow and uidRow[wx]
	local uidStr = uid and stripDashes(tostring(uid)) or NILUUID
	local flags = (td.flags and td.flags[wy] and td.flags[wy][wx]) or 0
	if uidStr == NILUUID then
		return self:cl_fallback("water", 0), flags
	end
	local cellRot = (td.rotation and td.rotation[wy] and td.rotation[wy][wx]) or 0
	cellRot = tonumber( cellRot ) or 0
	if FLIP_CELL_ROT then
		cellRot = ( 4 - ( cellRot % 4 ) ) % 4
	end
	local xo = (td.xOffset and td.xOffset[wy] and td.xOffset[wy][wx]) or 0
	local yo = (td.yOffset and td.yOffset[wy] and td.yOffset[wy][wx]) or 0
	local key = uidStr .. "_" .. xo .. "_" .. yo .. "_r" .. cellRot
	local hit = self.cl.atlas and self.cl.atlas.mini[key]
	if hit then
		return { res = hit.res, name = key }, flags, true
	end
	-- unknown/modded tile: biome tint (+ caller may stack a road overlay)
	local t = math.floor(flags / 4096) % 16
	local fb = (t >= 1 and t <= 8) and ("biome_" .. t) or "unknown"
	return self:cl_fallback(fb, 0), flags, false
end

function MinimapHud.cl_fallback( self, name, rot )
	local key = name .. "_r" .. (rot or 0)
	local hit = self.cl.atlas and self.cl.atlas.mini[key]
	if hit then return { res = hit.res, name = key } end
	return { res = "MISSING", name = key }
end

-- ------------------------------------------------------------------- gui ---
local function W(name, typ, skin, x, y, w, h, extra)
	local t = { Childs = {}, Name = name, Type = typ, Skin = skin,
	            NeedKey = false, NeedMouse = false, Visible = true,
	            x = x, y = y, width = w, height = h }
	if extra then for k, v in pairs(extra) do t[k] = v end end
	return t
end

function MinimapHud.cl_buildGui( self )
	-- isHud MUST be true: false makes a screen-type gui that steals input
	-- focus (WASD dead, Esc interacts with it) -- proven the hard way 8/8.
	-- layer = "Wallpaper": bottom of MyGUI_Layers.xml stack -> under the
	-- engine chat (chat sits on "Back", our default LuaHud* is above it,
	-- vanilla StatusPanel uses "Middle" higher still). If the map goes
	-- invisible with this, remove the layer option.
	local ok, gui = pcall(sm.jsonGui.createGui,
		{ isHud = true, isInteractive = false, needsCursor = false, layer = "Wallpaper" })
	if not ok then
		sm.gui.chatMessage("[minimap] createGui failed: " .. tostring(gui))
		return
	end
	self.cl.gui = gui

	-- getViewSize returns two NUMBERS (w, h) - run 4 crash: indexing a number
	local vw, vh = 1920, 1080
	local okv, a, b2 = pcall(sm.jsonGui.getViewSize)
	if okv and type(a) == "number" then
		vw, vh = a, b2 or vh
	elseif okv and a ~= nil then
		vw = a.x or a.width or vw
		vh = a.y or a.height or vh
	end
	self.cl.vw, self.cl.vh = vw, vh

	-- overlay-style proportions: zoom = cells across. Size presets (R on the
	-- GPS, Eric 8/14): medium = the original 22% of screen height
	local SIZEF = { 0.18, 0.22, 0.27 }
	local RING = math.floor(vh * SIZEF[self.cl.sizeIdx])
	local CELLPX = math.max(8, math.floor(RING / ZOOMS[self.cl.zoomIdx]))
	-- PHYSICAL-SCALE ROUNDING (8/14): the gui is laid out in LOGICAL 1280x720
	-- units (getViewSize, stats-confirmed at 1080p AND 1440p) and the engine
	-- scales each widget rect to physical pixels INDEPENDENTLY. At 1080p the
	-- scale is 1.5, so an ODD cell size lands on a half pixel and neighboring
	-- cells round apart: 1-physical-px background lines that crawl as the map
	-- scrolls (friend's 8/13 report, zoom 2 = 39px cells; 1440p = 2.0x and
	-- 4K = 3.0x are integer scales, which is why we never saw it). Even sizes
	-- map cleanly at every half-integer scale; the +1 draw overlap (OVERPX,
	-- below) covers the remaining fractional scales (1366x768 = 1.067x,
	-- 900p = 1.25x) where no size parity can help.
	CELLPX = CELLPX - (CELLPX % 2)
	self.cl.RING, self.cl.CELLPX = RING, CELLPX
	-- draw size only - ALL layout math stays on CELLPX. Neighbors overlap so
	-- physical-scale rounding (1080p 1.5x) cannot open a light seam while the
	-- map scrolls (floor(inner) crawls 1 logical px). +1 was not enough once
	-- scroll snap ate the budget; +2 keeps a continuous quilt under the ring.
	-- Sheets' 3px edge-extended padding hides the doubled edge column.
	local OVERPX = CELLPX + 2
	self.cl.OVERPX = OVERPX

	local n = math.ceil(RING / CELLPX) + 2
	self.cl.poolN = n
	-- placement presets (Q on the GPS, Eric 8/14): 1 = bottom-left (the
	-- original - ring bottom HEALTHGAP px above the vanilla health bar top,
	-- 8px ring extends ~6px past the aperture), 2 = bottom-right (same
	-- clearance line - the hotbar is bottom-CENTER and stays clear of a
	-- corner ring at every size), 3 = top-right, 4 = top-left (MARGIN + 8px
	-- bezel pad from the edges). 5 = hidden and never reaches this build.
	local p = self.cl.posIdx
	local fx0 = (p == 2 or p == 3) and (vw - MARGIN - RING) or MARGIN
	local fy0 = (p == 3 or p == 4) and (MARGIN + 8)
		or (vh - HEALTHTOP - HEALTHGAP - RING - 6)
	self.cl.fx0, self.cl.fy0 = fx0, fy0
	local frame = W("MapFrame", "Widget", "PanelEmpty", fx0, fy0, RING, RING)
	self.cl.frameW = frame
	local inner = W("MapInner", "Widget", "PanelEmpty",
		0, 0, n * CELLPX, n * CELLPX, { CroppingWidget = "MapFrame" })
	frame.Childs = { inner }
	self.cl.inner = inner
	-- one ImageBox per atlas RESOURCE per cell: changing a widget's
	-- ImageResource at runtime does not rebind (run 5) - toggle Visible
	-- instead. Resources are discovered from the index (partitioned sets).
	local seen, SHEETS = {}, {}
	for _, v in pairs(self.cl.atlas.mini) do
		if not seen[v.res] then
			seen[v.res] = true
			SHEETS[#SHEETS + 1] = v.res
		end
	end
	table.sort(SHEETS)
	self.cl.sheetNames = SHEETS
	self.cl.cells = {}
	self.cl.overlays = {}
	for j = 0, n - 1 do
		for i = 0, n - 1 do
			local per = {}
			for s, res in ipairs(SHEETS) do
				local initName, initVis = "water_r0", (s == 1)
				if PROBE and self.cl.probeGrid then
					local pg = self.cl.probeGrid[j * n + i]
					initName = pg and pg.name or "water_r0"
					initVis = (pg and pg.res == res) or false
				end
				local cw = W("c" .. s .. "_" .. i .. "_" .. j, "ImageBox", "ImageBox",
					i * CELLPX, j * CELLPX, OVERPX, OVERPX,
					{ ImageResource = res, ImageGroup = res,
					  ImageName = initName, Visible = initVis,
					  CroppingWidget = "MapFrame" })
				inner.Childs[#inner.Childs + 1] = cw
				per[res] = cw
			end
			self.cl.cells[j * n + i] = per
			local ov = W("o" .. i .. "_" .. j, "ImageBox", "ImageBox",
				i * CELLPX, j * CELLPX, OVERPX, OVERPX,
				{ ImageResource = "MMap_roads_0_0", ImageGroup = "MMap_roads_0_0",
				  ImageName = "road_1", Visible = false })
			inner.Childs[#inner.Childs + 1] = ov
			self.cl.overlays[j * n + i] = ov
		end
	end

	-- RIM CLIP POOL: the engine crops a child to its DIRECT parent's rect
	-- (spike v2, 8/8) - the grandparent chain is NOT applied (which is why
	-- cells never clipped to MapFrame through the oversized inner). Rim
	-- cells are therefore drawn inside thin slice-parents (direct children
	-- of MapFrame) whose rects follow the circle's horizontal chords
	-- (scanline circle fill): a pixel-perfect circular mask, no squash.
	-- slot count: cells crossing a circle ~ 2*pi*sqrt(2)*R/C (measured worst
	-- 14/20/28/40/56 across the zooms; the plain-perimeter formula undercounts)
	local nSlices = math.max(2, math.ceil(CELLPX / 4))
	local rimSlots = math.min(n * n,
		math.floor(2 * math.pi * 1.42 * (RING / 2) / CELLPX) + 6)
	self.cl.nSlices, self.cl.rimSlots = nSlices, rimSlots
	self.cl.rim = {}
	for s = 0, rimSlots - 1 do
		local slices = {}
		for k = 0, nSlices - 1 do
			local par = W("rp" .. s .. "_" .. k, "Widget", "PanelEmpty",
				0, 0, 1, 1, { Visible = false })
			local rper = {}
			for si, res in ipairs(SHEETS) do
				local cw = W("rc" .. s .. "_" .. k .. "_" .. si, "ImageBox", "ImageBox",
					0, 0, OVERPX, OVERPX,
					{ ImageResource = res, ImageGroup = res,
					  ImageName = "water_r0", Visible = false })
				par.Childs[#par.Childs + 1] = cw
				rper[res] = cw
			end
			local rov = W("ro" .. s .. "_" .. k, "ImageBox", "ImageBox",
				0, 0, OVERPX, OVERPX,
				{ ImageResource = "MMap_roads_0_0", ImageGroup = "MMap_roads_0_0",
				  ImageName = "road_1", Visible = false })
			par.Childs[#par.Childs + 1] = rov
			slices[k] = { par = par, per = rper, ov = rov }
			frame.Childs[#frame.Childs + 1] = par
		end
		self.cl.rim[s] = slices
	end

	-- ring + arrow + waypoint pin live in a SECOND gui (gui3, default layer)
	-- again: the v60 single-gui merge that put chat above the ring did not
	-- hold in-game (gremlin returned, Eric 8/8) - reverted; the GPS equip
	-- chat message was removed instead so nothing important sits under it.
	-- 8px gold marquee, identical at every zoom (covers the +-3px scanline
	-- residual of the rim clip slices)
	local pad = 8
	local plate = RING + 2 * pad
	-- ring color follows the active waypoint (Eric 8/8): one widget per ring
	-- variant, Visible toggled per frame (no runtime texture rebinds). Idle
	-- (no waypoint) = vanilla HUD dark gray 44,44,46 to match the health bar
	-- panel (Eric v67; replaced the gold marquee).
	local bezelSet = {}
	local bezelOrder = { "idle" }
	for _, col in ipairs(Waypoint.COLORS) do bezelOrder[#bezelOrder + 1] = col end
	for _, key in ipairs(bezelOrder) do
		local file = (key == "idle") and "bezel_ring_idle_b6.png"
			or ("bezel_ring_" .. key .. "_" .. BEZELVER .. ".png")
		bezelSet[key] = W("Bezel_" .. key, "ImageBox", "ImageBox",
			fx0 - pad, fy0 - pad, plate, plate,
			{ ImageTexture = C .. "/Gui/" .. file, Visible = (key == "idle") })
	end
	self.cl.bezelSet, self.cl.bezelOrder = bezelSet, bezelOrder
	-- Zoom-proportional arrow; single-cell atlas mode keeps it small (~70% cut).
	local ARROWF = { 0.13, 0.12, 0.18, 0.28, 0.35, 0.40 }
	local asz = math.max(8, math.floor(CELLPX * (ARROWF[self.cl.zoomIdx] or 0.13)))
	if type( RfsBiomeMap ) == "table" and RfsBiomeMap.SINGLE_CELL_MINIMAP then
		-- Absolute cap so one big cell doesn't revive the huge arrow.
		asz = math.min( asz, 14 )
	end
	local arrow = W("Arrow", "ImageBox", "RotatingSkin",
		fx0 + math.floor((RING - asz) / 2), fy0 + math.floor((RING - asz) / 2), asz, asz, {
			ImageTexture = C .. "/Gui/arrow.png",
			RotatingSkinAngle = 0.0,
			RotatingSkinCenterX = math.floor(asz / 2), RotatingSkinCenterY = math.floor(asz / 2) })
	self.cl.arrow = arrow
	-- minimap waypoint pin in the active color (one widget per color)
	local wpmSet = {}
	for _, col in ipairs(Waypoint.COLORS) do
		wpmSet[col] = W("WpMini_" .. col, "ImageBox", "ImageBox", -30, -30, 14, 20,
			{ ImageTexture = C .. "/Gui/gps_marker_" .. col .. "_b1.png", Visible = false })
	end
	self.cl.wpmSet = wpmSet
	-- Other players (MP): small arrows relative to local center (drawn above wp in gui3)
	local plySet = {}
	local plyNmSet = {}
	local maxP = ( type( Waypoint ) == "table" and Waypoint.MAX_REMOTE_PLAYERS ) or 8
	local psz = math.max( 8, math.floor( asz * 0.85 ) )
	self.cl.playerPinSize = psz
	for i = 1, maxP do
		plySet[i] = W( "PlyMini_" .. i, "ImageBox", "RotatingSkin", -40, -40, psz, psz, {
			ImageTexture = C .. "/Gui/arrow.png",
			RotatingSkinAngle = 0.0,
			RotatingSkinCenterX = math.floor( psz / 2 ),
			RotatingSkinCenterY = math.floor( psz / 2 ),
			Visible = false } )
		plyNmSet[i] = W( "PlyMiniNm_" .. i, "TextBox", "TextBox", -40, -40, 72, 14, {
			Caption = "", FontName = "SM_HeaderTiny", TextAlign = "Center",
			TextShadow = true, TextShadowColour = "0 0 0",
			Visible = false, NeedMouse = false } )
	end
	self.cl.playerPins = plySet
	self.cl.playerNames = plyNmSet

	local root = W("Root", "Widget", "PanelEmpty", 0, 0, vw, vh)
	root.Childs = { frame }
	self.cl.root = root

	local ok3, gui3 = pcall(sm.jsonGui.createGui,
		{ isHud = true, isInteractive = false, needsCursor = false })
	if ok3 and gui3 then
		self.cl.gui3 = gui3
		local root3 = W("Root3", "Widget", "PanelEmpty", 0, 0, vw, vh)
		local ch = {}
		for _, key in ipairs(bezelOrder) do ch[#ch + 1] = bezelSet[key] end
		ch[#ch + 1] = arrow
		for _, col in ipairs(Waypoint.COLORS) do ch[#ch + 1] = wpmSet[col] end
		for i = 1, maxP do
			ch[#ch + 1] = plySet[i]
			ch[#ch + 1] = plyNmSet[i]
		end
		root3.Childs = ch
		self.cl.root3 = root3
	end
end

function MinimapHud.cl_refill( self, bx, by )
	local n = self.cl.poolN
	local h = math.floor(n / 2)
	local diag = { s = {}, fb = 0, missKeys = {} }
	self.cl.active = self.cl.active or {}
	self.cl.activeName = self.cl.activeName or {}
	self.cl.ovActive = self.cl.ovActive or {}
	self.cl.ovName = self.cl.ovName or {}
	for j = 0, n - 1 do
		for i = 0, n - 1 do
			local wx = bx + i - h
			local wy = by + (n - 1 - j) - h        -- screen row 0 = north
			local frame, flags, real = self:cl_frameFor(wx, wy)
			if self.cl.debugMode == 1 and self.cl.firstOf and self.cl.firstOf[frame.res] then
				frame = { res = frame.res, name = self.cl.firstOf[frame.res] }
			elseif self.cl.debugMode == 2 then
				local pal = { ["MMap_mini_0_0"] = "biome_3_r0", ["MMap_mini_0_1"] = "biome_2_r0",
				              ["MMap_mini_1_0"] = "biome_8_r0", ["MMap_mini_1_1"] = "water_r0" }
				local ind = pal[frame.res]
				if ind then
					local hit = self.cl.atlas.mini[ind]
					frame = { res = hit.res, name = ind }
				end
			end
			local idx = j * n + i
			local per = self.cl.cells[idx]
			local matched = false
			for res, cw in pairs(per) do
				if res == frame.res then
					cw.ImageName = frame.name
					matched = true
				end
			end
			self.cl.active[idx] = matched and frame.res or nil
			self.cl.activeName[idx] = frame.name
			if not matched and #diag.missKeys < 6 then
				diag.missKeys[#diag.missKeys + 1] = tostring(frame.res) .. ":" .. tostring(frame.name)
			end
			diag.s[frame.res] = (diag.s[frame.res] or 0) + 1
			if real == false then diag.fb = diag.fb + 1 end
			local ov = self.cl.overlays[idx]
			local mask = math.floor((flags or 0) / 256) % 16
			local solidMm = type( RfsBiomeMap ) == "table" and RfsBiomeMap.SOLID_MINIMAP
			if ( not solidMm ) and (real == false) and mask ~= 0 then
				ov.ImageName = "road_" .. mask
				self.cl.ovActive[idx] = true
				self.cl.ovName[idx] = "road_" .. mask
			else
				self.cl.ovActive[idx] = false
			end
		end
	end
	self.cl.diag = diag
	self.cl.baseX, self.cl.baseY = bx, by
end

-- ---------------------------------------------------------------- zoom -----
-- Changing zoom changes CELLPX and therefore the pool size, so both guis are
-- torn down and rebuilt by the c.gui == nil path in client_onUpdate (rare
-- event, build cost is fine). c.hidden resets so the wrong-world check
-- re-applies setHidden to the fresh gui.
function MinimapHud.cl_rebuildGui( self )
	local c = self.cl
	pcall(function() if c.gui then c.gui:close() end end)
	pcall(function() if c.gui3 then c.gui3:close() end end)
	c.gui, c.root = nil, nil
	c.gui3, c.root3, c.renderErr3 = nil, nil, false
	c.cells, c.overlays, c.active, c.ovActive = nil, nil, nil, nil
	c.rim, c.activeName, c.ovName = nil, nil, nil
	c.bezelSet, c.bezelOrder, c.wpmSet, c.playerPins, c.playerNames = nil, nil, nil, nil, nil
	c.frameW, c.lastSig, c.lastTileSig, c.lastScrollSig, c.lastSig3, c.buildAge = nil, nil, nil, nil, nil, nil
	c.rfsRenderT = nil
	c.baseX, c.baseY = nil, nil
	c.hidden = false
	c.renderErr = false
	c.buildErr = false
end

-- no chat on zoom changes: the map itself is the feedback, and chat spam was
-- exactly what the map kept covering (Eric 8/8)
function MinimapHud.cl_applyZoom( self )
	Waypoint.save(self)                -- full state: zoom + waypoint + color
	self:cl_rebuildGui()
end

-- delta +1 = zoom in (fewer cells across), -1 = zoom out
function MinimapHud.cl_setZoom( self, delta )
	local c = self.cl
	if type( RfsBiomeMap ) == "table" and RfsBiomeMap.SINGLE_CELL_MINIMAP then
		-- Size cycle only via GPS R; zoom stays at 1 cell.
		if c.zoomIdx ~= 1 then
			c.zoomIdx = 1
			self:cl_applyZoom()
		end
		return
	end
	local idx = math.max(1, math.min(#ZOOMS, c.zoomIdx - delta))
	if idx == c.zoomIdx then return end
	c.zoomIdx = idx
	self:cl_applyZoom()
end

function MinimapHud.cl_zoomCycle( self )
	local c = self.cl
	if type( RfsBiomeMap ) == "table" and RfsBiomeMap.SINGLE_CELL_MINIMAP then
		c.zoomIdx = 1
		return
	end
	c.zoomIdx = c.zoomIdx % #ZOOMS + 1
	self:cl_applyZoom()
end

-- Q on the GPS (Eric 8/14): cycle minimap position BL - BR - TR - TL -
-- hidden. The hidden fifth stop doubles as hide/unhide; Q was freed up by
-- dropping the redundant big-map toggle (LMB opens it, E/Esc/CLOSE close it).
function MinimapHud.cl_posCycle( self )
	local c = self.cl
	c.posIdx = (c.posIdx or 1) % 5 + 1
	if c.posIdx <= 4 then c.lastPos = c.posIdx end
	Waypoint.save(self)
	self:cl_rebuildGui()
end

-- R on the GPS: cycle minimap size small / medium / large
function MinimapHud.cl_sizeCycle( self )
	local c = self.cl
	c.sizeIdx = (c.sizeIdx or 2) % 3 + 1
	Waypoint.save(self)
	self:cl_rebuildGui()
end

-- big-map MINIMAP button: flip between hidden and the last corner (shares
-- the Q state - pos 5 IS hidden, wherever it was set from)
function MinimapHud.cl_mmToggle( self )
	local c = self.cl
	if c.posIdx == 5 then
		c.posIdx = c.lastPos or 1
	else
		c.lastPos = c.posIdx
		c.posIdx = 5
	end
	Waypoint.save(self)
	self:cl_rebuildGui()
end

-- ------------------------------------------------------------- big map -----
-- gui callbacks dispatch to the OWNING script (this class); delegate to the
-- BigMap module. Opened/closed with Q on the GPS tool.
function MinimapHud.cl_bmToggle( self )
	BigMap.toggle(self)
end

function MinimapHud.cl_bmOpen( self )
	BigMap.open(self)
end

-- INSTRUMENTED (v23): every gui callback logs its tag + argument types to
-- chat and bm_events.json so the real dispatch contract can be read off.
-- Coercion handles both (self, name) and (self, widgetTable) shapes.
local function bmLog( self, tag, a, b )
	local c = self.cl
	c.bmLog = c.bmLog or {}
	local d = ""
	for _, v in ipairs({ a, b }) do
		d = d .. " " .. type(v) .. "="
			.. tostring(type(v) == "table" and (v.Name or "?") or v)
	end
	c.bmLog[#c.bmLog + 1] = tag .. d
	if #c.bmLog > 60 then table.remove(c.bmLog, 1) end
	pcall(sm.json.save, { events = c.bmLog }, C .. "/bm_events.json")
end

local function widgetName( a, b )
	if type(a) == "string" then return a end
	if type(a) == "table" and a.Name then return a.Name end
	if type(b) == "string" then return b end
	if type(b) == "table" and b.Name then return b.Name end
	return nil
end

function MinimapHud.cl_bm_btn( self, a, b )
	pcall(bmLog, self, "btn", a, b)
	local name = widgetName(a, b)
	if name then BigMap.button(self, name) end
end

function MinimapHud.cl_bm_cell( self, a, b, c2, d )
	pcall(bmLog, self, "cell", a, b)
	local name = widgetName(a, b)
	-- raw args forwarded: cellClick probes them for cursor coords (v67)
	if name then BigMap.cellClick(self, name, a, b, c2, d) end
end

-- key-event delegate on THIS class too (dispatch can bind to the opener
-- chain's class OR the gui owner - cover both, button-saga lesson)
function MinimapHud.cl_bm_keys( self, a, b, c2, d )
	BigMap.keys(self, a, b, c2, d)
end

-- cursor sampler delegates (precise waypoint placement)
function MinimapHud.cl_bm_curs( self, a, b, c2, d )
	BigMap.cursor(self, a, b, c2, d)
end

function MinimapHud.cl_bm_hover( self, a, b, c2, d )
	BigMap.hover(self, a, b, c2, d)
end

-- Pan arrows + mousewheel bind to the script that opened the GUI (MinimapHud
-- via GPS LMB / /map / /menu Map). SpikeHand has these too, but is not the owner.
function MinimapHud.cl_bm_bdown( self, a, b )
	local name = widgetName( a, b )
	if name then
		BigMap.btnDown( self, name )
	end
end

function MinimapHud.cl_bm_bup( self, a, b )
	BigMap.btnUp( self, widgetName( a, b ) )
end

function MinimapHud.cl_bm_wheel( self, a, b, c2, d )
	BigMap.wheel( self, a, b, c2, d )
end

-- engine close hook candidates (Esc / E) - both log + fold
function MinimapHud.cl_onGuiClosed( self, a, b )
	bmLog(self, "onGuiClosed", a, b)
	BigMap.onClosed(self)
end

function MinimapHud.client_onGuiClosed( self, a, b )
	bmLog(self, "client_onGuiClosed", a, b)
	BigMap.onClosed(self)
end

-- input event probes (wheel/drag discovery)
for _, ev in ipairs({ "Pressed", "Released", "MouseWheel" }) do
	MinimapHud["cl_bm_ev" .. ev] = function( self, a, b )
		bmLog(self, "ev" .. ev, a, b)
	end
end

-- ---------------------------------------------------------------- probe ----
-- STATIC probe: frames baked into the widget tree at creation, never mutated.
-- 9x9 grid split into labeled row bands:
--   rows 1-2 (top)    = sheet0 EARLY entries      rows 3-4 = sheet0 MIDDLE
--   rows 5-6          = sheet0 LATE entries       rows 7-9 = sheet1 EARLY
function MinimapHud.cl_buildProbeGrid( self )
	local function namesFor(res)
		local out = {}
		for name, v in pairs(self.cl.atlas.mini) do
			if v.res == res then out[#out + 1] = name end
		end
		table.sort(out)
		return out
	end
	local s0 = namesFor("MMap_mini_0")
	local s1 = namesFor("MMap_mini_1")
	local grid = {}
	local n = 9
	for j = 0, n - 1 do
		for i = 0, n - 1 do
			local k = j * n + i
			local name, res
			if j <= 1 then
				name = s0[1 + k]; res = "MMap_mini_0"                       -- early
			elseif j <= 3 then
				name = s0[math.floor(#s0 / 2) + k]; res = "MMap_mini_0"     -- middle
			elseif j <= 5 then
				name = s0[#s0 - 100 + (k - 36)]; res = "MMap_mini_0"        -- late
			else
				name = s1[1 + (k - 54)]; res = "MMap_mini_1"                -- sheet1
			end
			grid[k] = name and { name = name, res = res } or nil
		end
	end
	self.cl.probeGrid = grid
end

function MinimapHud.cl_probeUpdate( self, dt, char )
	local c = self.cl
	if not c.probeCentered then
		c.probeCentered = true
		local n = c.poolN
		c.inner.x = math.floor((c.RING - n * c.CELLPX) / 2)
		c.inner.y = math.floor((c.RING - n * c.CELLPX) / 2)
		for idx = 0, n * n - 1 do
			c.overlays[idx].Visible = false
		end
	end
	pcall(function() c.gui:render(c.root) end)
	-- position + resolved keys around the player -> ground-truth check offline
	c.statT = c.statT + dt
	if c.statT > 10 then
		c.statT = 0
		local pos = char.worldPosition
		local cx, cy = math.floor(pos.x / 64), math.floor(pos.y / 64)
		local around = {}
		for dy = -1, 1 do
			for dx = -1, 1 do
				local f = select(1, self:cl_frameFor(cx + dx, cy + dy))
				around[#around + 1] = (cx + dx) .. "," .. (cy + dy) .. "=" .. tostring(f.name)
			end
		end
		if g_wmFlags and g_wmFlags.DEV then
			pcall(sm.json.save, { probe = true, x = pos.x, y = pos.y,
				cell = cx .. "," .. cy, around = around }, C .. "/minimap_stats.json")
		end
	end
end

-- ---------------------------------------------------------------- update ---
function MinimapHud.client_onUpdate( self, dt )
	local c = self.cl
	if c == nil then
		-- uninitialized: remote player's instance (stays this way forever,
		-- one cheap check per frame) or our own tool before ownership
		-- resolved (initializes on the first frame the owner matches)
		if toolIsLocal(self) then
			self:cl_init()
		end
		return
	end

	-- MP self-heal: if this instance turns out to belong to ANOTHER player
	-- (a wrong answer during join let it init), tear it down - the corruption
	-- clears within seconds instead of lasting the session. The reclaim keeps
	-- input bound to the real local instance even if a wrong one grabbed
	-- g_minimapHud last.
	c.mpT = (c.mpT or 0) + dt
	if c.mpT > 2 then
		c.mpT = 0
		if toolIsRemote(self) then
			g_wmMpDemos = (g_wmMpDemos or 0) + 1
			self:cl_shutdown()
			return
		end
		if g_minimapHud ~= self then g_minimapHud = self end
	end

	if not c.ready then
		c.retryT = c.retryT + dt
		if c.retryT > 2 then
			c.retryT = 0
			self:cl_tryLoadTerrain()
		end
		return
	end

	-- deferred network sends: network objects are CONTEXT-BOUND (calling
	-- self.network from another script's callback chain = "Sandbox
	-- violation: mismatching scriptRef", v50) - callbacks set flags, this
	-- update loop (own context) performs the sends
	if c.wantLock then
		c.wantLock = nil
		pcall(function() self.network:sendToServer("sv_bm_spawnLock") end)
	end
	if c.wantUnlock then
		c.wantUnlock = nil
		pcall(function() self.network:sendToServer("sv_bm_destroyLock") end)
	end
	if c.wantMapMarkerSave and c.pendingMapMarker then
		local payload = c.pendingMapMarker
		c.wantMapMarkerSave = nil
		c.pendingMapMarker = nil
		pcall(function() self.network:sendToServer("sv_n_rfsMapMarker", payload) end)
	end
	if c.wantMapMarkerGet then
		c.wantMapMarkerGet = nil
		pcall(function() self.network:sendToServer("sv_n_rfsMapMarkerGet", {}) end)
	end
	if c.wantGpsPrefsSave and c.pendingGpsPrefs then
		local payload = c.pendingGpsPrefs
		c.wantGpsPrefsSave = nil
		c.pendingGpsPrefs = nil
		pcall(function() self.network:sendToServer("sv_n_rfsGpsPrefsSet", payload) end)
	end
	if c.wantGpsPrefsGet then
		c.wantGpsPrefsGet = nil
		pcall(function() self.network:sendToServer("sv_n_rfsGpsPrefsGet", {}) end)
	end

	-- compass icon sync (waypoint set/cleared/recolored): runs in THIS
	-- script's own context, throttled; must also run while the big map is
	-- open (that's where waypoints change), hence before the bm branch
	if c.wantCompassSync then
		c.compassT = (c.compassT or 1) + dt
		if c.compassT > 0.25 then
			c.compassT = 0
			local okS, done = pcall(Waypoint.compassSync, self)
			if not okS or done then c.wantCompassSync = nil end
		end
	end

	-- big map screen replaces the minimap while open. MUST come before the
	-- gui rebuild block: while the big map is up the minimap guis stay torn
	-- down (single-gui-per-script dispatch hypothesis, v25) and rebuild
	-- automatically the frame after it closes.
	if c.bm and c.bm.open then
		local okc2, char2 = pcall(function() return sm.localPlayer.getPlayer():getCharacter() end)
		BigMap.update(self, dt, okc2 and char2 or nil)
		return
	end

	-- user-hidden minimap (pos preset 5 - Q's fifth stop or the big-map
	-- MINIMAP button): guis stay torn down. Everything above still runs, so
	-- waypoints, the compass icon and the big map keep working while hidden.
	if c.posIdx == 5 then
		if c.gui ~= nil or c.gui3 ~= nil then self:cl_rebuildGui() end
		-- Hidden skips cl_buildGui (where vw is normally set) — warm atlas pool anyway.
		if c.ready and c.atlas then
			pcall( function() BigMap.prebuildStep( self ) end )
		end
		return
	end

	if c.gui == nil then
		-- 0851-d: lazy-init upper-left HUD — spread widget build; prebuild atlas
		-- pool during the wait (zoom/pos rebuild skips defer — deferActive false).
		if c.deferActive and c.posIdx ~= 5 then
			c.deferT = (c.deferT or 0) + dt
			BigMap.prebuildStep(self)
			local okd, ch = pcall(function()
				return sm.localPlayer.getPlayer():getCharacter()
			end)
			if okd and ch then
				local p = ch.worldPosition
				if not c.deferPos then
					c.deferPos = { x = p.x, y = p.y }
				end
				local dx = p.x - c.deferPos.x
				local dy = p.y - c.deferPos.y
				if dx * dx + dy * dy < 32 * 32 and c.deferT < 2.5 then
					return
				end
			elseif c.deferT < 2.5 then
				return
			end
			c.deferActive = false
		end
		if PROBE and not c.probeGrid then
			self:cl_buildProbeGrid()
		end
		local okb, err = pcall(self.cl_buildGui, self)
		if not okb then
			if not c.buildErr then
				c.buildErr = true
				sm.gui.chatMessage("[minimap] gui build failed: " .. tostring(err))
			end
			pcall(function() if c.gui then c.gui:close() end end)
			pcall(function() if c.gui3 then c.gui3:close() end end)
			c.gui, c.gui3, c.root3 = nil, nil, nil
			c.ready = false                -- retry loop will rebuild
			return
		end
		if c.gui == nil then c.ready = false; return end
	end

	local okc, char = pcall(function() return sm.localPlayer.getPlayer():getCharacter() end)
	if not okc or char == nil then return end

	if PROBE then
		self:cl_probeUpdate(dt, char)
		return
	end


	-- hide when not in the mapped world (underground / warehouse) or while
	-- any engine gui is active (chat box, logbook, containers): the chat
	-- box shares our bottom layer and cannot be layered above the map, so
	-- the map steps aside instead (sm.gui.hasActiveGui - undocumented, no
	-- vanilla usage; if the map NEVER shows, this counts our own HUD guis
	-- and must be reverted)
	local okw, wid = pcall(function() return char:getWorld().id end)
	local wrongWorld = okw and wid ~= c.worldId
	local okA, guiOpen = pcall(sm.gui.hasActiveGui)
	local hideAll = wrongWorld or (okA and guiOpen == true)
	if hideAll ~= c.hidden then
		c.hidden = hideAll
		pcall(function() c.gui:setHidden(hideAll) end)
		pcall(function() if c.gui3 then c.gui3:setHidden(hideAll) end end)
	end
	if hideAll then return end

	-- background atlas pool prebuild while minimap is up (spread ~1320 widgets)
	if not (c.bm and c.bm.poolReady) then
		BigMap.prebuildStep(self)
	end

	-- triple-crouch within ~2 s cycles ZOOM (debug views moved to the GPS
	-- hand tool: LMB/RMB = zoom in/out, Q = debug cycle)
	local okcr, crouch = pcall(function() return char:isCrouching() end)
	if okcr then
		c.crouchT = (c.crouchT or 0) + dt
		if crouch and not c.wasCrouch then
			if c.crouchT > 2 then c.crouchN = 0 end
			c.crouchT = 0
			c.crouchN = (c.crouchN or 0) + 1
			if c.crouchN >= 3 then
				c.crouchN = 0
				self:cl_zoomCycle()
				return                     -- guis torn down; rebuild next frame
			end
		end
		c.wasCrouch = crouch
	end

	local pos = char.worldPosition
	local cellX = math.floor(pos.x / 64)
	local cellY = math.floor(pos.y / 64)
	local fx = pos.x / 64 - cellX
	local fy = pos.y / 64 - cellY
	-- 0851-d: when standing still, run map paint at ~6 Hz instead of every frame
	c.buildAge = (c.buildAge or 0) + dt
	local warm = c.buildAge < 2
	local moving = cellX ~= c.prevCellX or cellY ~= c.prevCellY
		or math.abs(fx - (c.prevFx or fx)) > 0.02
		or math.abs(fy - (c.prevFy or fy)) > 0.02
	c.prevCellX, c.prevCellY = cellX, cellY
	c.prevFx, c.prevFy = fx, fy
	if not moving and not warm then
		c.idleT = (c.idleT or 0) + dt
		if c.idleT < 0.15 then return end
		c.idleT = 0
	else
		c.idleT = 0
	end
	if cellX ~= c.baseX or cellY ~= c.baseY then
		self:cl_refill(cellX, cellY)
	end

	-- smooth scroll: offset inner container by sub-cell fraction
	local n = c.poolN
	local h = math.floor(n / 2)
	local RING, CELLPX = c.RING, c.CELLPX
	-- base cell occupies slot row (n-1-h); the player's pixel inside the inner
	-- container is ((h+fx), (n-h-fy)) cells from its top-left. n-h == h+1 only
	-- for ODD n -- the old h+1 constant made even-n zoom levels scroll the map
	-- one cell south under the arrow (zoom parity bug, Eric 8/8)
	-- Round (not truncate) so crawl seams don't bias one direction under 1.5x.
	c.inner.x = math.floor(RING / 2 - (h + fx) * CELLPX + 0.5)
	c.inner.y = math.floor(RING / 2 - (n - h - fy) * CELLPX + 0.5)

	-- arrow follows camera heading (ring/arrow/pin render via gui3 below,
	-- gated by their own signature)
	local okd, dir = pcall(sm.camera.getDirection)
	if okd and dir then
		c.arrow.RotatingSkinAngle = math.atan2(dir.x, dir.y)
	end

	-- waypoint pin (active color): at its map position inside the ring,
	-- clamped to the rim as a direction indicator when out of range. The
	-- ring itself takes the waypoint color while one is active (gold idle).
	local wpCol = Waypoint.valid(c.wpColor) and c.wpColor or "red"
	local hasWp = c.waypoint ~= nil
	local wpm = c.wpmSet and c.wpmSet[wpCol]
	if c.wpmSet then
		for col, w in pairs(c.wpmSet) do
			if not (hasWp and col == wpCol) then w.Visible = false end
		end
	end
	if hasWp and wpm then
		local mx = (c.waypoint.x - pos.x) / 64 * CELLPX
		local my = -(c.waypoint.y - pos.y) / 64 * CELLPX
		local d = math.sqrt(mx * mx + my * my)
		local maxr = RING / 2 - 10
		if d > maxr and d > 0 then
			mx, my = mx * maxr / d, my * maxr / d
		end
		wpm.Visible = true
		wpm.x = c.fx0 + math.floor(RING / 2 + mx - 7 + 0.5)
		wpm.y = c.fy0 + math.floor(RING / 2 + my - 18 + 0.5)
	end
	-- Remote players on MiniMap (relative to local, clamped to rim)
	if c.playerPins then
		local psz = c.playerPinSize or 10
		local idx = 0
		local maxr = RING / 2 - 8
		if type( Waypoint ) == "table" and Waypoint.eachRemotePlayer then
			Waypoint.eachRemotePlayer( function( _p, rpos, dir, displayName )
				idx = idx + 1
				local pin = c.playerPins[idx]
				if not pin then return end
				local mx = ( rpos.x - pos.x ) / 64 * CELLPX
				local my = -( rpos.y - pos.y ) / 64 * CELLPX
				local d = math.sqrt( mx * mx + my * my )
				if d > maxr and d > 0 then
					mx, my = mx * maxr / d, my * maxr / d
				end
				pin.Visible = true
				pin.x = c.fx0 + math.floor( RING / 2 + mx - psz / 2 + 0.5 )
				pin.y = c.fy0 + math.floor( RING / 2 + my - psz / 2 + 0.5 )
				if dir then
					pin.RotatingSkinAngle = math.atan2( dir.x, dir.y )
				end
				local nm = c.playerNames and c.playerNames[idx]
				if nm then
					nm.Caption = tostring( displayName or "Player" )
					nm.Visible = true
					nm.x = c.fx0 + math.floor( RING / 2 + mx - 36 + 0.5 )
					nm.y = c.fy0 + math.floor( RING / 2 + my + psz / 2 - 1 + 0.5 )
				end
			end )
		end
		for i = idx + 1, #c.playerPins do
			c.playerPins[i].Visible = false
			if c.playerNames and c.playerNames[i] then
				c.playerNames[i].Visible = false
			end
		end
	end
	if c.bezelSet then
		for key, w in pairs(c.bezelSet) do
			w.Visible = (hasWp and key == wpCol) or (not hasWp and key == "idle")
		end
	end

	-- Remote players on compass (throttle ~4 Hz)
	c.rfsPlyCompassT = ( c.rfsPlyCompassT or 0 ) + dt
	if c.rfsPlyCompassT >= 0.25 then
		c.rfsPlyCompassT = 0
		pcall( function()
			if type( Waypoint ) == "table" and Waypoint.syncRemotePlayersCompass then
				Waypoint.syncRemotePlayersCompass( self )
			end
		end )
	end

	-- PERF (v31): gui:render(root) marshals the WHOLE tree every call
	-- (~7us/widget regardless of visibility, T3-T5). Two fixes: skip the
	-- entire pass + render when nothing moved (signature), and hand the
	-- engine a PRUNED tree containing only the widgets visible this frame.
	-- 0851-d: tile sig (base cell) vs scroll sig (inner offset) — sub-cell
	-- smooth scroll must not rerun the O(n^2) rim-clip pass every frame.
	-- Warmup retries scroll paint only (~20 Hz); must not force tileDirty.
	local scrollSig = c.inner.x .. ";" .. c.inner.y
	local tileSig = tostring(c.baseX) .. ";" .. tostring(c.baseY)
		.. ";" .. c.debugMode
	-- warmup: keep rendering for 2s after build - the very first render can
	-- land before atlas textures bind, leaving a blank map while stationary
	local tileDirty = tileSig ~= c.lastTileSig
	local scrollDirty = scrollSig ~= c.lastScrollSig
	c.rfsRenderT = (c.rfsRenderT or 0) + dt
	local doPaint = c.rfsRenderT >= 0.05
	-- Rim slices are MapFrame children (not under MapInner). Scrolling only
	-- the inner without re-laying rim left a visible tear/gap quilt while
	-- walking. Re-run the clip pass on scroll paints too (~20 Hz).
	local needLayout = tileDirty or ((scrollDirty or warm) and doPaint)
	if needLayout then
		c.lastTileSig = tileSig
		c.lastScrollSig = scrollSig
		c.lastSig = scrollSig .. ";" .. tileSig

	-- per-frame visibility: interior cells draw full-size in the grid pool;
	-- cells CROSSING the circle edge are hidden there and drawn instead in
	-- rim clip slices (thin parents whose rects follow the circle's chords -
	-- the engine crops children to the direct parent rect, spike v2). Result:
	-- a true circular mask, no squash, no pokes.
	local R = RING / 2 + 1
	local cc = RING / 2
	local R2 = R * R
	local rimUsed = 0
	local nSl = c.nSlices
	local liveIn = {}
	for idx = 0, n * n - 1 do
		local i = idx % n
		local j = math.floor(idx / n)
		local x0 = c.inner.x + i * CELLPX
		local y0 = c.inner.y + j * CELLPX
		local x1, y1 = x0 + CELLPX, y0 + CELLPX
		local nx = (cc < x0 and x0) or (cc > x1 and x1) or cc
		local ny = (cc < y0 and y0) or (cc > y1 and y1) or cc
		local ndx, ndy = nx - cc, ny - cc
		local act = c.active[idx]
		local per = c.cells[idx]
		local ov = c.overlays[idx]
		local fdx = math.max(cc - x0, x1 - cc)
		local fdy = math.max(cc - y0, y1 - cc)
		local outside = ndx * ndx + ndy * ndy > R2 or act == nil
		local interior = not outside and fdx * fdx + fdy * fdy <= R2
		local rimSlot = nil
		if not outside and not interior and rimUsed < c.rimSlots then
			rimSlot = c.rim[rimUsed]
			rimUsed = rimUsed + 1
		end
		-- grid pool: interior draws normally; rim-with-slot hides here;
		-- rim overflow degrades to a full-size draw (small poke, rare)
		local gridVis = interior or (not outside and rimSlot == nil)
		for res, cw in pairs(per) do
			local v = gridVis and res == act
			cw.Visible = v
			if v then liveIn[#liveIn + 1] = cw end
		end
		local vgo = gridVis and (c.ovActive[idx] == true)
		ov.Visible = vgo
		if vgo then liveIn[#liveIn + 1] = ov end
		if rimSlot then
			local name = c.activeName[idx]
			local vo = c.ovActive[idx] == true
			local cellRx = math.floor(x0 + 0.5)
			local cellRy = math.floor(y0 + 0.5)
			-- slice along the axis FACING the circle edge (long flat cuts
			-- otherwise show at top/bottom); midpoint chords center the
			-- residual error on the true circle: +-3px at every zoom
			-- (sim-verified), fully hidden under the 8px ring
			local vert = math.abs((y0 + y1) / 2 - cc) >= math.abs((x0 + x1) / 2 - cc)
			for k = 0, nSl - 1 do
				local sl = rimSlot[k]
				local sx0, sx1, sy0, sy1
				if vert then
					sy0 = y0 + k * CELLPX / nSl
					sy1 = y0 + (k + 1) * CELLPX / nSl
					local h2 = R2 - ((sy0 + sy1) / 2 - cc) ^ 2
					if h2 > 0 then
						local hw = math.sqrt(h2)
						sx0 = math.max(x0, cc - hw)
						sx1 = math.min(x1, cc + hw)
					end
				else
					sx0 = x0 + k * CELLPX / nSl
					sx1 = x0 + (k + 1) * CELLPX / nSl
					local h2 = R2 - ((sx0 + sx1) / 2 - cc) ^ 2
					if h2 > 0 then
						local hh = math.sqrt(h2)
						sy0 = math.max(y0, cc - hh)
						sy1 = math.min(y1, cc + hh)
					else
						sx0 = nil
					end
				end
				if sx0 and sy0 and sx1 - sx0 >= 1 and sy1 - sy0 >= 1 then
					local px = math.floor(sx0 + 0.5)
					local py = math.floor(sy0 + 0.5)
					local p = sl.par
					p.Visible = true
					p.x = px; p.y = py
					p.width = math.max(1, math.floor(sx1 + 0.5) - px)
					p.height = math.max(1, math.floor(sy1 + 0.5) - py)
					-- +2 overlap along the STACKING axis (match grid OVERPX budget
					-- so abutting rim strips do not open a light seam at 1.5x).
					if vert then
						p.height = p.height + 2
					else
						p.width = p.width + 2
					end
					local pc = {}
					for res, cw in pairs(sl.per) do
						local v = res == act
						cw.Visible = v
						if v then
							cw.ImageName = name
							cw.x = cellRx - px; cw.y = cellRy - py
							cw.width = c.OVERPX; cw.height = c.OVERPX
							pc[#pc + 1] = cw
						end
					end
					sl.ov.Visible = vo
					if vo then
						sl.ov.ImageName = c.ovName[idx]
						sl.ov.x = cellRx - px; sl.ov.y = cellRy - py
						sl.ov.width = c.OVERPX; sl.ov.height = c.OVERPX
						pc[#pc + 1] = sl.ov
					end
					sl.par.Childs = pc
				else
					sl.par.Visible = false
				end
			end
		end
	end
	-- park unused rim slots
	for s = rimUsed, c.rimSlots - 1 do
		local slices = c.rim[s]
		for k = 0, nSl - 1 do
			slices[k].par.Visible = false
		end
	end
	c.rimUsed = rimUsed

	-- pruned render tree: inner holds only visible cells; the frame holds
	-- inner + only the ACTIVE rim slice parents (each pruned to 1-2 childs)
	c.inner.Childs = liveIn
	local lf = { c.inner }
	for s = 0, rimUsed - 1 do
		local slices = c.rim[s]
		for k = 0, nSl - 1 do
			if slices[k].par.Visible then
				lf[#lf + 1] = slices[k].par
			end
		end
	end
	c.frameW.Childs = lf

		c.rfsRenderT = 0
		local okr, err = pcall(function() c.gui:render(c.root) end)
		if not okr and not c.renderErr then
			c.renderErr = true
			sm.gui.chatMessage("[minimap] render error: " .. tostring(err))
		end
	end

	-- ring/arrow/pin gui: tiny static tree, own signature (arrow angle
	-- quantized to ~3 degrees + pin position + ring/pin color state)
	if c.gui3 and c.root3 then
		local sig3 = math.floor((c.arrow.RotatingSkinAngle or 0) * 20)
			.. ";" .. tostring(hasWp and wpm and (wpCol .. ":" .. wpm.x .. "," .. wpm.y) or "-")
		if sig3 ~= c.lastSig3 or (warm and doPaint) then
			c.lastSig3 = sig3
			local okr3, err3 = pcall(function() c.gui3:render(c.root3) end)
			if not okr3 and not c.renderErr3 then
				c.renderErr3 = true
				sm.gui.chatMessage("[minimap] ring render error: " .. tostring(err3))
			end
		end
	end

	-- perf stats to file every 30 s (picked up by the dev monitor)
	c.frames = c.frames + 1
	c.dtMax = math.max(c.dtMax, dt)
	c.statT = c.statT + dt
	if c.statT > 30 then
		local around = {}
		if c.baseX then
			for dy = -1, 1 do
				for dx = -1, 1 do
					local f = select(1, self:cl_frameFor(c.baseX + dx, c.baseY + dy))
					around[#around + 1] = (c.baseX + dx) .. "," .. (c.baseY + dy)
						.. "=" .. tostring(f.res) .. ":" .. tostring(f.name)
				end
			end
		end
		if g_wmFlags and g_wmFlags.DEV then
			pcall(sm.json.save, { version = VERSION, build = BUILD,
				-- which COPY wrote this file. The dev mod writes to its own folder
				-- (mod-dev\minimap_stats.json) so the two can never overwrite each
				-- other, but the flag makes a pasted stats blob self-identifying.
				dev = true, flags = g_wmFlags,
				frames = c.frames, dtMax = c.dtMax, t = c.statT,
				ring = c.RING, cell = c.CELLPX, zoom = c.zoomIdx, diag = c.diag,
				pos = c.posIdx, size = c.sizeIdx,
				-- the LOGICAL view size the engine reports (~1280x720 even on 4K).
				-- Logged so another machine's resolution can be checked from a
				-- stats file instead of guessed at.
				vw = c.vw, vh = c.vh,
				rim = c.rimUsed, rimMax = c.rimSlots,
				-- MP gate diagnostics: inits should be 1; 2+ means the owner
				-- gate passed for another player's instance, demos counts
				-- self-heal teardowns that followed
				mp = { inits = g_wmMpInits or 0, demos = g_wmMpDemos or 0 },
				wp = c.waypoint, wpc = c.wpColor, compass = c.compassDbg,
				wpdbg = c.wpDbg, recipeDbg = c.recipeDbg,
				x = pos.x, y = pos.y, base = tostring(c.baseX) .. "," .. tostring(c.baseY),
				around = around },
				C .. "/minimap_stats.json")
		end
		c.statT = 0; c.frames = 0; c.dtMax = 0
	end
end
