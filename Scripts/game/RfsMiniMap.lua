-- RfsMiniMap.lua — Map phase helpers (Nutt World Map 3780282057).
-- HUD MiniMap + Nutt atlas are one phase. Atlas opens from the crafted GPS.
-- AutoTool class lives in RfsMiniMapTool.lua so Player.lua can dofile this
-- without loading Nutt's tool class twice.

RfsMiniMap = RfsMiniMap or {}

local NUTT = "$CONTENT_58df2b8e-a86f-44ed-b4f9-aa5b00b44162"

local function ensureViewSize( hud )
	local c = hud and hud.cl
	if not c then
		return
	end
	if c.vw and c.vh then
		return
	end
	c.vw, c.vh = 1280, 720
	pcall( function()
		if type( sm.jsonGui ) == "table" and sm.jsonGui.getViewSize then
			local a, b = sm.jsonGui.getViewSize()
			if type( a ) == "number" then
				c.vw, c.vh = a, b or 720
			end
		end
	end )
end

local function ensureAtlas( hud )
	local c = hud and hud.cl
	if not c then
		return
	end
	if type( c.atlas ) == "table" and type( c.atlas.mini ) == "table" then
		return
	end
	pcall( function()
		local ok, idx = pcall( sm.json.open, NUTT .. "/Scripts/data/atlas_index.json" )
		if ok and type( idx ) == "table" then
			c.atlas = idx
		end
	end )
end

function RfsMiniMap.nuttLoaded()
	return g_rfsNuttMap == true
end

function RfsMiniMap.available()
	return g_rfsNuttMap == true
		and g_minimapHud ~= nil
		and type( BigMap ) == "table"
end

function RfsMiniMap.isBigMapOpen()
	local hud = g_minimapHud
	return hud and hud.cl and hud.cl.bm and hud.cl.bm.open == true
end

-- True while Nutt is subscribed/hosted but terrain/atlas is not ready yet.
-- Callers should wait — do not drop to lock-camera while the Map phase is live.
function RfsMiniMap.pending()
	if not RfsMiniMap.nuttLoaded() then
		return false
	end
	if RfsMiniMap.available() then
		local hud = g_minimapHud
		local c = hud and hud.cl
		if c and c.ready and type( c.atlas ) == "table" then
			return false
		end
	end
	return true
end

function RfsMiniMap.toggleBigMap()
	local hud = g_minimapHud
	if not hud or type( BigMap ) ~= "table" then
		return false
	end
	hud.cl = hud.cl or {}
	ensureViewSize( hud )
	ensureAtlas( hud )
	if not hud.cl.ready and type( hud.cl_tryLoadTerrain ) == "function" then
		pcall( function() hud:cl_tryLoadTerrain() end )
	end
	if RfsMiniMap.isBigMapOpen() then
		local ok = pcall( function() hud:cl_bmToggle() end )
		return ok
	end
	local c = hud.cl
	if not ( c and c.ready and type( c.atlas ) == "table" ) then
		return false
	end
	local ok = pcall( function() hud:cl_bmToggle() end )
	return ok and RfsMiniMap.isBigMapOpen()
end

function RfsMiniMap.closeBigMap()
	local hud = g_minimapHud
	if not hud or type( BigMap ) ~= "table" then
		return
	end
	pcall( function() BigMap.close( hud ) end )
end
