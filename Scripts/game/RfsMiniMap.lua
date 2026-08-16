-- RfsMiniMap.lua — Phase 6 MiniMap helpers (Nutt World Map 3780282057).
-- AutoTool class lives in RfsMiniMapTool.lua so Player.lua can dofile this
-- without loading Nutt's tool class twice.

RfsMiniMap = RfsMiniMap or {}

function RfsMiniMap.available()
	return g_rfsNuttMap == true
		and g_minimapHud ~= nil
		and type( BigMap ) == "table"
end

function RfsMiniMap.isBigMapOpen()
	local hud = g_minimapHud
	return hud and hud.cl and hud.cl.bm and hud.cl.bm.open == true
end

function RfsMiniMap.toggleBigMap()
	local hud = g_minimapHud
	if not hud or type( BigMap ) ~= "table" then
		return false
	end
	if RfsMiniMap.isBigMapOpen() then
		local ok = pcall( function() hud:cl_bmToggle() end )
		return ok
	end
	local c = hud.cl
	if not ( c and c.ready and c.atlas ) then
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
