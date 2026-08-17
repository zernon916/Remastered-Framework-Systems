-- World Map: waypoint state + compass tracking (M5). Pure module like
-- Vendored into Remastered Framework Survival with permission. Credit: Nutt
-- (Steam Workshop 3780282057).
-- BigMap: dofile'd by MinimapHud, operates on hud.cl, testable offline with
-- a mocked sm. UX contract (Eric 8/8): click sets, click elsewhere replaces,
-- click on the pin removes, CLEAR button removes; 5 colors (default red)
-- applied to the big-map pin, minimap pin, minimap ring and compass icon.
--
-- Compass: the vanilla bar is Lua-driven (sm.gui.createCompassHudGui,
-- SurvivalGame.lua:213) and LogBook.lua:1666 sets compass-only waypoint
-- markers exactly like ours. Three routes, best first:
--   wmm     game-script globals visible -> the REAL bar via WorldMarkerManager
--   vanilla g_compassHud visible        -> direct icon calls on the real bar
--   own     mod-created CompassHudGui   -> our own instance (opened only
--                                          while a waypoint is active)
-- Every call is pcall'd: the compass is a bonus layer and must never take
-- the minimap down. Results land in hud.cl.compassDbg -> minimap_stats.json.

Waypoint = {}

-- jsonGui ImageTexture does not resolve $CONTENT_DATA (blank waypoint icons).
local CC = "$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247"
local NAME = "GPSModWaypoint"

Waypoint.COLORS = { "red", "green", "blue", "yellow", "orange" }
local HEX = { red = "e13c32ff", green = "50cd5aff", blue = "468cffff",
              yellow = "f0dc46ff", orange = "ff962dff" }
-- compass icon = vanilla beacon glyph 23 (X-cross, "marks the spot") from
-- the registered BeaconCompassIconMap imageset: the engine resolution-
-- switches AND tints it exactly like real beacon icons (Eric v65: baked
-- 42px png looked rasterized next to them; vanilla pipeline = always crisp)
local GLYPH = "23"

function Waypoint.valid( col )
	for _, c in ipairs(Waypoint.COLORS) do
		if c == col then return true end
	end
	return false
end

function Waypoint.pinFile( col )
	return CC .. "/Gui/gps_marker_" .. (Waypoint.valid(col) and col or "red") .. "_b1.png"
end

-- compass badge variant (Eric v64): white arrow glyph + pale inner border,
-- styled like the vanilla compass icons; map pins keep the plain art
function Waypoint.compassFile( col )
	return CC .. "/Gui/compass_wp_" .. (Waypoint.valid(col) and col or "red") .. "_b1.png"
end

-- single writer for the settings file: every save carries the full state
-- (the old zoom-only save dropped the persisted waypoint)
function Waypoint.save( hud )
	local c = hud.cl
	pcall(sm.json.save, { zoom = c.zoomIdx, wp = c.waypoint, wpc = c.wpColor,
		pos = c.posIdx, posl = c.lastPos, size = c.sizeIdx },
		CC .. "/minimap_settings.json")
end

function Waypoint.set( hud, x, y )
	local c = hud.cl
	c.waypoint = { x = x, y = y }
	Waypoint.save(hud)
	c.wantCompassSync = true
end

function Waypoint.clear( hud )
	local c = hud.cl
	c.waypoint = nil
	Waypoint.save(hud)
	c.wantCompassSync = true
end

function Waypoint.setColor( hud, col )
	if not Waypoint.valid(col) then return end
	local c = hud.cl
	c.wpColor = col
	Waypoint.save(hud)
	c.wantCompassSync = true            -- icon image follows the color
end

-- ----------------------------------------------------------- compass -------
-- called from MinimapHud.client_onUpdate (owning script's own context) while
-- hud.cl.wantCompassSync is set. Returns true when the sync is complete (or
-- permanently impossible) so the caller can clear the flag; false = retry.
function Waypoint.compassSync( hud )
	local c = hud.cl
	local dbg = c.compassDbg or {}
	c.compassDbg = dbg

	-- resolve the compass access route once
	if not c.compass then
		local okW, wmm = pcall(function() return WorldMarkerManager end)
		local okG, g = pcall(function() return g_compassHud end)
		if okW and type(wmm) == "table" and wmm.Cl_CreateOrUpdateMarker
				and okG and g then
			c.compass = { mode = "wmm" }
		elseif okG and g then
			c.compass = { mode = "vanilla", gui = g }
		else
			local okC, own = pcall(sm.gui.createCompassHudGui)
			if okC and own then
				c.compass = { mode = "own", gui = own }
			else
				dbg.mode = "none"
				dbg.err = "createCompassHudGui: " .. tostring(own)
				c.compass = { mode = "none" }
			end
		end
		dbg.mode = c.compass.mode
	end
	if c.compass.mode == "none" then return true end

	local wp = c.waypoint
	local col = Waypoint.valid(c.wpColor) and c.wpColor or "red"

	-- ------------------------------------------------------------ hide -----
	if not wp then
		if c.compass.mode == "wmm" then
			if c.compass.added then
				pcall(function() WorldMarkerManager.Cl_HideMarker(NAME) end)
			end
		elseif c.compass.gui then
			pcall(function() c.compass.gui:setVisible(NAME, false) end)
			if c.compass.mode == "own" and c.compass.opened then
				pcall(function() c.compass.gui:close() end)
				c.compass.opened = false
			end
		end
		dbg.state = "hidden"
		return true
	end

	-- ------------------------------------------------------------ show -----
	local okc, char = pcall(function()
		return sm.localPlayer.getPlayer():getCharacter()
	end)
	if not okc or char == nil then return false end   -- retry next tick
	local okw, world = pcall(function() return char:getWorld() end)
	if not okw or world == nil then return false end

	-- z: cell elevation when the terrain grid carries one, else player z
	-- (the bar only needs bearing; z feeds the distance readout)
	local z = 0
	pcall(function() z = char.worldPosition.z end)
	pcall(function()
		local e = c.td and c.td.elevation
		local row = e and e[math.floor(wp.y / 64)]
		local v = row and row[math.floor(wp.x / 64)]
		if type(v) == "number" then z = v end
	end)
	local okv, pos = pcall(sm.vec3.new, wp.x, wp.y, z)
	if not okv then return true end

	local img = Waypoint.compassFile(col)
	local okCol, color = pcall(function() return sm.color.new(HEX[col]) end)

	if c.compass.mode == "wmm" then
		local ok, err = pcall(function()
			WorldMarkerManager.Cl_CreateOrUpdateMarker(NAME, {
				effect = "Beacon",          -- never started: compassOnly
				position = pos,
				world = world,
				compassItemIcon = { resource = "BeaconCompassIconMap",
					group = "BeaconCompassIconMap", name = GLYPH },
				compassColor = okCol and color or nil,
				color = okCol and color or nil,
				compassOnly = true,
				activate = true,
			})
		end)
		c.compass.added = c.compass.added or ok
		dbg.state = ok and ("shown " .. col) or "wmm err"
		if not ok then dbg.err = tostring(err) end
		return true
	end

	local gui = c.compass.gui
	if not c.compass.added then
		local ok = pcall(function() gui:compassAddIcon(NAME) end)
		if not ok then
			dbg.err = "compassAddIcon failed"
			c.compass.mode = "none"
			return true
		end
		c.compass.added = true
	end
	-- primary: tinted vanilla glyph (crisp at every resolution); fallback:
	-- our pre-colored badge png (no tint - it would just darken it)
	local okII = pcall(function()
		gui:setItemIcon(NAME, "BeaconCompassIconMap", "BeaconCompassIconMap", GLYPH)
	end)
	if okII then
		if okCol then pcall(function() gui:setColor(NAME, color) end) end
	else
		dbg.imgFallback = true
		pcall(function() gui:setImage(NAME, img) end)
	end
	pcall(function() gui:compassSetIconWorldPosition(NAME, pos, world) end)
	pcall(function() gui:setVisible(NAME, true) end)
	if c.compass.mode == "own" and not c.compass.opened then
		pcall(function() gui:open() end)
		c.compass.opened = true
	end
	dbg.state = "shown " .. col
	return true
end
