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
local NAME_HOME = "GPSModHome"
-- Prefs: server sm.storage is authoritative ($USER_DATA json fails in Custom Game).
local SETTINGS_PATHS = {
	CC .. "/minimap_settings.json",
}

Waypoint.COLORS = { "red", "green", "blue", "yellow", "orange" }
local HEX = { red = "e13c32ff", green = "50cd5aff", blue = "468cffff",
              yellow = "f0dc46ff", orange = "ff962dff" }
local HOME_HEX = "4f6cffff"
-- compass icon = vanilla beacon glyph 23 (X-cross, "marks the spot") from
-- the registered BeaconCompassIconMap imageset: the engine resolution-
-- switches AND tints it exactly like real beacon icons (Eric v65: baked
-- 42px png looked rasterized next to them; vanilla pipeline = always crisp)
local GLYPH = "23"
-- Beacon house glyph (same index as BeaconIconMap "5")
local GLYPH_HOME = "5"

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

local function loadSettingsTable()
	for _, path in ipairs( SETTINGS_PATHS ) do
		local ok, st = pcall( sm.json.open, path )
		if ok and type( st ) == "table" then
			return st
		end
	end
	return {}
end

local function saveSettingsTable( all )
	local saved = false
	local lastErr = nil
	for _, path in ipairs( SETTINGS_PATHS ) do
		local ok, err = pcall( sm.json.save, all, path )
		if ok then
			saved = true
		else
			lastErr = err
		end
	end
	if not saved then
		print( "[RFS] GPS settings save failed (minimap pos/size will not persist): " .. tostring( lastErr ) )
	end
	return saved
end

function Waypoint.readSettings()
	return loadSettingsTable()
end

function Waypoint.loadWorld( hud )
	local c = hud.cl
	if not c.worldId then
		return
	end
	local st = loadSettingsTable()
	local wid = tostring( c.worldId )
	local w = st.worlds and st.worlds[wid]
	if type( w ) == "table" then
		c.waypoint = w.wp
		c.farmMarkers = w.farms
		-- false = explicitly cleared; missing key = migrate legacy flat base
		if w.base == false then
			c.baseMarker = nil
		elseif type( w.base ) == "table" and w.base.x then
			c.baseMarker = w.base
		elseif type( st.base ) == "table" and st.base.x then
			c.baseMarker = st.base
		else
			c.baseMarker = nil
		end
	else
		-- one-time migration from legacy flat keys
		if type( st.wp ) == "table" and st.wp.x then
			c.waypoint = st.wp
		end
		if type( st.base ) == "table" and st.base.x then
			c.baseMarker = st.base
		end
		if type( st.farms ) == "table" then
			c.farmMarkers = st.farms
		end
	end
	local mem = _G.g_rfsMapMarkersLocal
	if mem then
		if not c.waypoint and type( mem.wp ) == "table" and mem.wp.x then
			c.waypoint = mem.wp
		end
		if not c.baseMarker and type( mem.base ) == "table" and mem.base.x then
			c.baseMarker = mem.base
		end
	end
	if c.waypoint or c.baseMarker then
		c.wantCompassSync = true
	end
	_G.g_rfsMapMarkersLocal = {
		wp = c.waypoint,
		base = c.baseMarker,
	}
	-- MP: pull shared home/waypoint from the host (overrides local-only file).
	Waypoint.requestShared()
end

-- Queue server sync on the GPS tool's own update tick (avoid sandbox/network context bugs).
local function queueMapMarker( action, x, y )
	local payload = { action = action, x = x, y = y }
	local hud = _G.g_minimapHud
	if hud and hud.cl then
		hud.cl.pendingMapMarker = payload
		hud.cl.wantMapMarkerSave = true
		return
	end
	pcall( function()
		local game = _G.g_rfsGame
		if game and game.network and game.network.sendToServer then
			game.network:sendToServer( "sv_rfs_mapMarker", payload )
		end
	end )
end

local function queueGpsPrefsSave( c )
	if not c then
		return
	end
	local payload = {
		pos = c.posIdx,
		posl = c.lastPos,
		zoom = c.zoomIdx,
		size = c.sizeIdx,
		wpc = c.wpColor,
	}
	local hud = _G.g_minimapHud
	if hud and hud.cl then
		hud.cl.pendingGpsPrefs = payload
		hud.cl.wantGpsPrefsSave = true
		return
	end
	pcall( function()
		local game = _G.g_rfsGame
		if game and game.network and game.network.sendToServer then
			game.network:sendToServer( "sv_rfs_gpsPrefsSet", payload )
		end
	end )
end

-- Push home/waypoint to the server so every client map/compass updates.
local function broadcastShared( action, x, y )
	queueMapMarker( action, x, y )
end

function Waypoint.requestShared()
	local hud = _G.g_minimapHud
	if hud and hud.cl then
		hud.cl.wantMapMarkerGet = true
		return
	end
	pcall( function()
		local game = _G.g_rfsGame
		if game and game.network and game.network.sendToServer then
			game.network:sendToServer( "sv_rfs_mapMarkerGet", {} )
		end
	end )
end

-- Apply host-broadcast markers. Does not re-broadcast (avoids echo loops).
-- base/wp: table = set; false = explicit clear; nil = leave local alone (join race / partial).
function Waypoint.applyShared( hud, markers )
	if not hud then
		hud = _G.g_minimapHud
	end
	if not hud or not hud.cl or type( markers ) ~= "table" then
		-- Join race: Game may sync before MinimapHud owns g_minimapHud.
		if type( markers ) == "table" then
			_G.g_rfsMapMarkersPending = markers
		end
		return
	end
	local c = hud.cl
	c._rfsMarkerApplying = true
	if markers.wp == false then
		c.waypoint = nil
	elseif type( markers.wp ) == "table" and markers.wp.x and markers.wp.y then
		c.waypoint = { x = markers.wp.x, y = markers.wp.y }
	end
	if markers.base == false then
		c.baseMarker = nil
	elseif type( markers.base ) == "table" and markers.base.x and markers.base.y then
		c.baseMarker = { x = markers.base.x, y = markers.base.y }
	end
	_G.g_rfsMapMarkersLocal = {
		wp = c.waypoint,
		base = c.baseMarker,
	}
	c.wantCompassSync = true
	c._rfsMarkerApplying = false
	_G.g_rfsMapMarkersPending = nil
end

-- Apply any markers queued before the MiniMap HUD existed.
function Waypoint.flushPending( hud )
	local pending = _G.g_rfsMapMarkersPending
	if type( pending ) ~= "table" then
		local game = _G.g_rfsGame
		if type( game ) == "table" and type( game.cl ) == "table" then
			pending = game.cl.rfsMapMarkersPending
		end
	end
	if type( pending ) == "table" then
		Waypoint.applyShared( hud or _G.g_minimapHud, pending )
	end
end

-- Cap remote player icons (BigMap / MiniMap / compass).
Waypoint.MAX_REMOTE_PLAYERS = 8
local PLAYER_COMPASS_HEX = "46c8ffff"
local GLYPH_PLAYER = "1"
local NAME_PLAYER_PREFIX = "GPSModPly_"

local function remotePlayerDisplayName( p )
	local name = nil
	if p then
		pcall( function() name = p:getName() end )
		if ( not name or name == "" ) and p.name then
			name = p.name
		end
	end
	if type( name ) ~= "string" or name == "" then
		name = "Player"
	end
	if #name > 16 then
		name = string.sub( name, 1, 14 ) .. ".."
	end
	return name
end

-- Iterate other players with a live character. fn( player, pos, dirOrNil, displayName )
function Waypoint.eachRemotePlayer( fn )
	if type( fn ) ~= "function" then
		return
	end
	local localId = nil
	pcall( function()
		local lp = sm.localPlayer.getPlayer()
		if lp then localId = lp.id end
	end )
	local all = nil
	pcall( function() all = sm.player.getAllPlayers() end )
	if type( all ) ~= "table" then
		return
	end
	local n = 0
	for _, p in pairs( all ) do
		if n >= Waypoint.MAX_REMOTE_PLAYERS then
			break
		end
		if p and ( localId == nil or p.id ~= localId ) then
			local char = nil
			pcall( function() char = p.character end )
			if not char then
				pcall( function() char = p:getCharacter() end )
			end
			local pos = nil
			if char then
				pcall( function()
					if sm.exists( char ) then
						pos = char.worldPosition
					end
				end )
			end
			if pos then
				local dir = nil
				pcall( function() dir = char.direction end )
				if not dir then
					pcall( function() dir = char:getDirection() end )
				end
				n = n + 1
				fn( p, pos, dir, remotePlayerDisplayName( p ) )
			end
		end
	end
end

-- Compass icons for remote players (throttled by caller). Keeps icons for movers.
function Waypoint.syncRemotePlayersCompass( hud )
	if not hud or not hud.cl then
		return
	end
	local c = hud.cl
	-- Resolve compass backend once (do not call compassSync — it clears when no wp/home).
	if not c.compass then
		local okW, wmm = pcall( function() return WorldMarkerManager end )
		local okG, g = pcall( function() return g_compassHud end )
		if okW and type( wmm ) == "table" and wmm.Cl_CreateOrUpdateMarker and okG and g then
			c.compass = { mode = "wmm" }
		elseif okG and g then
			c.compass = { mode = "vanilla", gui = g }
		else
			local okC, own = pcall( sm.gui.createCompassHudGui )
			if okC and own then
				c.compass = { mode = "own", gui = own }
			else
				c.compass = { mode = "none" }
			end
		end
	end
	if c.compass.mode == "none" then
		return
	end
	local okc, char = pcall( function()
		return sm.localPlayer.getPlayer():getCharacter()
	end )
	if not okc or not char then
		return
	end
	local okw, world = pcall( function() return char:getWorld() end )
	if not okw or not world then
		return
	end
	local okCol, color = pcall( function() return sm.color.new( PLAYER_COMPASS_HEX ) end )
	c.compass.playerFlags = c.compass.playerFlags or {}
	local seen = {}
	Waypoint.eachRemotePlayer( function( player, pos, _dir )
		local id = tostring( player.id or "?" )
		local name = NAME_PLAYER_PREFIX .. id
		seen[name] = true
		local flagKey = "ply_" .. id
		local ok, err = compassShowIcon( c, name, flagKey, pos, world, GLYPH_PLAYER,
			okCol and color or nil, nil )
		if ok then
			c.compass.playerFlags[name] = flagKey
		elseif err then
			c.compassDbg = c.compassDbg or {}
			c.compassDbg.plyErr = tostring( err )
		end
	end )
	for name, flagKey in pairs( c.compass.playerFlags ) do
		if not seen[name] then
			compassHideIcon( c, name, flagKey )
			c.compass.playerFlags[name] = nil
			c.compass[flagKey] = nil
		end
	end
	local anyRemote = next( seen ) ~= nil
	if anyRemote and c.compass.mode == "own" and not c.compass.opened then
		pcall( function() c.compass.gui:open() end )
		c.compass.opened = true
	end
end

-- Push minimap layout prefs to server (pos 5 = hidden).
local function syncGpsPrefsToServer( c )
	queueGpsPrefsSave( c )
end

-- Apply server-stored minimap prefs (pos 5 = hidden survives relog).
function Waypoint.applyGpsPrefs( hud, prefs )
	if not hud or not hud.cl or type( prefs ) ~= "table" then
		return false
	end
	local c = hud.cl
	c._rfsGpsPrefsApplied = true
	local changed = false
	if type( prefs.pos ) == "number" and prefs.pos >= 1 and prefs.pos <= 5 then
		c.posIdx = math.floor( prefs.pos )
		changed = true
	end
	if type( prefs.posl ) == "number" and prefs.posl >= 1 and prefs.posl <= 4 then
		c.lastPos = math.floor( prefs.posl )
		changed = true
	end
	if type( prefs.zoom ) == "number" and prefs.zoom >= 1 then
		c.zoomIdx = math.floor( prefs.zoom )
		changed = true
	end
	if type( prefs.size ) == "number" and prefs.size >= 1 and prefs.size <= 3 then
		c.sizeIdx = math.floor( prefs.size )
		changed = true
	end
	if type( prefs.wpc ) == "string" and Waypoint.valid( prefs.wpc ) then
		c.wpColor = prefs.wpc
		changed = true
	end
	if changed and hud.cl_rebuildGui then
		pcall( function() hud:cl_rebuildGui() end )
	end
	return changed
end

function Waypoint.requestGpsPrefs()
	local hud = _G.g_minimapHud
	if hud and hud.cl then
		hud.cl.wantGpsPrefsGet = true
		return
	end
	pcall( function()
		local game = _G.g_rfsGame
		if game and game.network and game.network.sendToServer then
			game.network:sendToServer( "sv_rfs_gpsPrefsGet", {} )
		end
	end )
end

-- single writer for the settings file: every save carries the full state
-- (the old zoom-only save dropped the persisted waypoint)
function Waypoint.save( hud )
	local c = hud.cl
	local all = loadSettingsTable()
	all.zoom = c.zoomIdx
	all.wpc = c.wpColor
	all.pos = c.posIdx
	all.posl = c.lastPos
	all.size = c.sizeIdx
	all.poiFilters = c.poiFilters
	all.worlds = all.worlds or {}
	local wid = c.worldId and tostring( c.worldId ) or nil
	if wid then
		local prev = ( type( all.worlds[wid] ) == "table" ) and all.worlds[wid] or {}
		local wentry = {
			wp = c.waypoint,
			farms = c.farmMarkers,
		}
		-- Never write base=false unless the player explicitly cleared home.
		if c._rfsMarkerClearBase then
			wentry.base = false
		elseif c.baseMarker and c.baseMarker.x then
			wentry.base = c.baseMarker
		elseif type( prev.base ) == "table" then
			wentry.base = prev.base
		elseif prev.base == false then
			wentry.base = false
		end
		all.worlds[wid] = wentry
		if c.baseMarker and c.baseMarker.x then
			all.base = c.baseMarker
		elseif c._rfsMarkerClearBase then
			all.base = false
		end
		if c.waypoint then
			all.wp = c.waypoint
		end
	else
		all.wp = c.waypoint
		if c.baseMarker and c.baseMarker.x then
			all.base = c.baseMarker
		elseif c._rfsMarkerClearBase then
			all.base = false
		end
		all.farms = c.farmMarkers
	end
	saveSettingsTable( all )
	syncGpsPrefsToServer( c )
end

function Waypoint.set( hud, x, y )
	local c = hud.cl
	c.waypoint = { x = x, y = y }
	_G.g_rfsMapMarkersLocal = { wp = c.waypoint, base = c.baseMarker }
	Waypoint.save(hud)
	c.wantCompassSync = true
	if not c._rfsMarkerApplying then
		broadcastShared( "setWp", x, y )
	end
end

function Waypoint.clear( hud )
	local c = hud.cl
	c.waypoint = nil
	_G.g_rfsMapMarkersLocal = { wp = nil, base = c.baseMarker }
	Waypoint.save(hud)
	c.wantCompassSync = true
	if not c._rfsMarkerApplying then
		broadcastShared( "clearWp" )
	end
end

function Waypoint.setColor( hud, col )
	if not Waypoint.valid(col) then return end
	local c = hud.cl
	c.wpColor = col
	Waypoint.save(hud)
	c.wantCompassSync = true            -- icon image follows the color
end

function Waypoint.setBase( hud, x, y )
	local c = hud.cl
	c.baseMarker = { x = x, y = y }
	_G.g_rfsMapMarkersLocal = { wp = c.waypoint, base = c.baseMarker }
	Waypoint.save(hud)
	c.wantCompassSync = true
	if not c._rfsMarkerApplying then
		broadcastShared( "setBase", x, y )
	end
end

function Waypoint.clearBase( hud )
	local c = hud.cl
	c.baseMarker = nil
	c._rfsMarkerClearBase = true
	_G.g_rfsMapMarkersLocal = { wp = c.waypoint, base = nil }
	Waypoint.save(hud)
	c._rfsMarkerClearBase = nil
	c.wantCompassSync = true
	if not c._rfsMarkerApplying then
		broadcastShared( "clearBase" )
	end
end

function Waypoint.setFarm( hud, col, x, y )
	if not Waypoint.valid(col) then return end
	local c = hud.cl
	c.farmMarkers = c.farmMarkers or {}
	c.farmMarkers[col] = { x = x, y = y }
	Waypoint.save(hud)
end

function Waypoint.clearFarm( hud, col )
	local c = hud.cl
	if c.farmMarkers then
		c.farmMarkers[col] = nil
	end
	Waypoint.save(hud)
end

function Waypoint.togglePoiFilter( hud, key )
	local c = hud.cl
	c.poiFilters = c.poiFilters or {}
	c.poiFilters[key] = not c.poiFilters[key]
	Waypoint.save(hud)
	return c.poiFilters[key]
end

-- ----------------------------------------------------------- compass -------
-- called from MinimapHud.client_onUpdate (owning script's own context) while
-- hud.cl.wantCompassSync is set. Returns true when the sync is complete (or
-- permanently impossible) so the caller can clear the flag; false = retry.
local function compassWorldPos( c, char, x, y )
	local z = 0
	pcall(function() z = char.worldPosition.z end)
	pcall(function()
		local e = c.td and c.td.elevation
		local row = e and e[math.floor(y / 64)]
		local v = row and row[math.floor(x / 64)]
		if type(v) == "number" then z = v end
	end)
	local okv, pos = pcall(sm.vec3.new, x, y, z)
	if okv then return pos end
	return nil
end

local function compassHideIcon( c, name, flagKey )
	if c.compass.mode == "wmm" then
		if c.compass[flagKey] then
			pcall(function() WorldMarkerManager.Cl_HideMarker(name) end)
		end
	elseif c.compass.gui then
		pcall(function() c.compass.gui:setVisible(name, false) end)
	end
end

local function compassShowIcon( c, name, flagKey, pos, world, glyph, color, imgFallback )
	if c.compass.mode == "wmm" then
		local ok, err = pcall(function()
			WorldMarkerManager.Cl_CreateOrUpdateMarker(name, {
				effect = "Beacon",
				position = pos,
				world = world,
				compassItemIcon = { resource = "BeaconCompassIconMap",
					group = "BeaconCompassIconMap", name = glyph },
				compassColor = color,
				color = color,
				compassOnly = true,
				activate = true,
			})
		end)
		c.compass[flagKey] = c.compass[flagKey] or ok
		return ok, err
	end
	local gui = c.compass.gui
	if not gui then return false, "no gui" end
	if not c.compass[flagKey] then
		local ok = pcall(function() gui:compassAddIcon(name) end)
		if not ok then return false, "compassAddIcon" end
		c.compass[flagKey] = true
	end
	local okII = pcall(function()
		gui:setItemIcon(name, "BeaconCompassIconMap", "BeaconCompassIconMap", glyph)
	end)
	if okII then
		if color then pcall(function() gui:setColor(name, color) end) end
	elseif imgFallback then
		pcall(function() gui:setImage(name, imgFallback) end)
	end
	pcall(function() gui:compassSetIconWorldPosition(name, pos, world) end)
	pcall(function() gui:setVisible(name, true) end)
	return true, nil
end

function Waypoint.compassSync( hud )
	local c = hud.cl
	local dbg = c.compassDbg or {}
	c.compassDbg = dbg

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
	local home = c.baseMarker
	local col = Waypoint.valid(c.wpColor) and c.wpColor or "red"
	local any = (wp ~= nil) or (home and home.x and home.y)

	if not any then
		compassHideIcon(c, NAME, "added")
		compassHideIcon(c, NAME_HOME, "homeAdded")
		-- Do not close own compass while remote-player icons may still be active.
		local hasRemote = c.compass.playerFlags and next( c.compass.playerFlags ) ~= nil
		if c.compass.mode == "own" and c.compass.opened and not hasRemote then
			pcall(function() c.compass.gui:close() end)
			c.compass.opened = false
		end
		dbg.state = "hidden"
		return true
	end

	local okc, char = pcall(function()
		return sm.localPlayer.getPlayer():getCharacter()
	end)
	if not okc or char == nil then return false end
	local okw, world = pcall(function() return char:getWorld() end)
	if not okw or world == nil then return false end

	local okCol, color = pcall(function() return sm.color.new(HEX[col]) end)
	local okHomeCol, homeColor = pcall(function() return sm.color.new(HOME_HEX) end)

	if wp then
		local pos = compassWorldPos(c, char, wp.x, wp.y)
		if not pos then return true end
		local img = Waypoint.compassFile(col)
		local ok, err = compassShowIcon(c, NAME, "added", pos, world, GLYPH,
			okCol and color or nil, img)
		if not ok then dbg.err = tostring(err) end
	else
		compassHideIcon(c, NAME, "added")
	end

	if home and home.x and home.y then
		local pos = compassWorldPos(c, char, home.x, home.y)
		if pos then
			local ok, err = compassShowIcon(c, NAME_HOME, "homeAdded", pos, world,
				GLYPH_HOME, okHomeCol and homeColor or nil, nil)
			if not ok then dbg.homeErr = tostring(err) end
			dbg.home = "shown"
		end
	else
		compassHideIcon(c, NAME_HOME, "homeAdded")
		dbg.home = "hidden"
	end

	if c.compass.mode == "own" and not c.compass.opened then
		pcall(function() c.compass.gui:open() end)
		c.compass.opened = true
	end
	dbg.state = wp and ("shown " .. col) or "home-only"
	return true
end
