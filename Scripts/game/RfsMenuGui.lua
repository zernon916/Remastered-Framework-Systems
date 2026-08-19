-- RfsMenuGui.lua — /menu player GUI for Recipe Framework Survival
-- VOLATILE: /menu widgets + open. Do not mix with RfsHackPower spend.
-- Author: DemonsDen126
-- Style skins match Recipe Radar / Rfs_Setup (BackgroundInteractableWide, PrimaryButton).
-- Open path: createGui (needsCursor) → bind → open → refresh.
-- Refresh/setButtonState before open() is the cursor-only / world-still-visible half-open.

RfsMenuGui = RfsMenuGui or {}

local LAYOUT = "$CONTENT_DATA/Gui/Layouts/Rfs_Menu.layout"
local GUI_OPTS = { isHud = false, isInteractive = true, needsCursor = true }

local function createMenuGui()
	local ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT, false, GUI_OPTS )
	if ok and gui then
		return gui
	end
	ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT, false )
	if ok and gui then
		return gui
	end
	ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT )
	if ok and gui then
		return gui
	end
	return nil, gui
end

local function growthOn( host )
	if host and host.cl and host.cl.rfsGrowthOverlay ~= nil then
		return host.cl.rfsGrowthOverlay and true or false
	end
	return _G.g_rfsGrowthOverlay == true
end

local function guiPrefs( host )
	if host and host.cl and type( host.cl.rfsGuiPrefs ) == "table" then
		return host.cl.rfsGuiPrefs
	end
	if type( RfsGuiPrefs ) == "table" and RfsGuiPrefs.client then
		return RfsGuiPrefs.client()
	end
	return { names = true, bigRed = false, enemyHp = "red", neutralHp = "green", blockOverlay = false }
end

local function titleCase( s )
	s = tostring( s or "" )
	if s == "" then
		return s
	end
	return string.upper( string.sub( s, 1, 1 ) ) .. string.sub( s, 2 )
end

function RfsMenuGui.refresh( host )
	local gui = host.cl and host.cl.rfsMenuGui
	if not gui then return end

	local overlay = growthOn( host )
	pcall( function()
		gui:setText( "BtnGrowthOverlay", "Growth Time: " .. ( overlay and "ON" or "OFF" ) )
		gui:setButtonState( "BtnGrowthOverlay", overlay )
	end )

	local prefs = guiPrefs( host )
	local names = prefs.names ~= false
	local bigRed = prefs.bigRed and true or false
	local blockOn = prefs.blockOverlay == true
	pcall( function()
		gui:setText( "BtnNames", "Names: " .. ( names and "ON" or "OFF" ) )
		gui:setButtonState( "BtnNames", names )
		gui:setText( "BtnBigRed", "Big Red: " .. ( bigRed and "ON" or "OFF" ) )
		gui:setButtonState( "BtnBigRed", bigRed )
		gui:setText( "BtnBlockOverlay", "Block overlay: " .. ( blockOn and "ON" or "OFF" ) )
		gui:setButtonState( "BtnBlockOverlay", blockOn )
		gui:setText( "BtnEnemyHp", "Enemy bar: " .. titleCase( prefs.enemyHp ) )
		gui:setText( "BtnNeutralHp", "Neutral bar: " .. titleCase( prefs.neutralHp ) )
	end )

	pcall( function()
		gui:setText( "Status", string.format(
			"Map + Growth + GUI (yours only) | crop=%s names=%s blocks=%s",
			overlay and "ON" or "OFF",
			names and "ON" or "OFF",
			blockOn and "ON" or "OFF"
		) )
	end )
	-- Hint text lives in Lua: MyGUI XML treats apostrophes as quote delimiters
	-- (Nutt's in the layout aborted createGui: incorrect attribute line 67).
	pcall( function()
		gui:setText( "MenuHint", "Map: always-on MiniMap (upper-left). Full atlas: research/craft Nutt GPS, then LMB. Growth Time: yours only. Block overlay: nearby creation mass/shape-count (SM has no per-block HP). Names: world tags. Big Red: farmbots. Enemy/Neutral colors tint real HP billboards and RFS tags (engine HP bars cannot be recolored)." )
	end )
end

function RfsMenuGui.bind( host, gui )
	host.cl = host.cl or {}
	host.cl.rfsMenuGui = gui

	-- Each bind is pcall'd so a missing widget cannot abort before gui:open().
	pcall( function() gui:setButtonCallback( "CloseButton", "cl_rfs_menuClose" ) end )
	pcall( function() gui:setButtonCallback( "BtnMap", "cl_rfs_menuMap" ) end )
	pcall( function() gui:setButtonCallback( "BtnGrowthOverlay", "cl_rfs_menuToggleGrowthOverlay" ) end )
	pcall( function() gui:setButtonCallback( "BtnNames", "cl_rfs_menuToggleNames" ) end )
	pcall( function() gui:setButtonCallback( "BtnBigRed", "cl_rfs_menuToggleBigRed" ) end )
	pcall( function() gui:setButtonCallback( "BtnBlockOverlay", "cl_rfs_menuToggleBlockOverlay" ) end )
	pcall( function() gui:setButtonCallback( "BtnEnemyHp", "cl_rfs_menuCycleEnemyHp" ) end )
	pcall( function() gui:setButtonCallback( "BtnNeutralHp", "cl_rfs_menuCycleNeutralHp" ) end )
	pcall( function() gui:setOnCloseCallback( "cl_rfs_menuClose" ) end )
end

function RfsMenuGui.open( host )
	host.cl = host.cl or {}
	if host.cl.rfsMenuGui then
		local old = host.cl.rfsMenuGui
		host.cl.rfsMenuGui = nil
		pcall( function() old:setOnCloseCallback( "cl_rfs_menuCloseStale" ) end )
		pcall( function() old:close() end )
		pcall( function() old:destroy() end )
	end

	local gui, err = createMenuGui()
	if not gui then
		sm.gui.chatMessage( "[RFS] Failed to open /menu GUI" )
		print( "[RFS] menu GUI create failed: " .. tostring( err ) )
		return
	end

	RfsMenuGui.bind( host, gui )
	-- Open before refresh: setText/setButtonState before open() left cursor-only.
	gui:open()
	pcall( function()
		RfsMenuGui.refresh( host )
	end )
	sm.gui.chatMessage( "RFS Menu opened" )
end

function RfsMenuGui.close( host )
	local gui = host.cl and host.cl.rfsMenuGui
	if gui then
		pcall( function() gui:setOnCloseCallback( "cl_rfs_menuCloseStale" ) end )
		pcall( function() gui:close() end )
		pcall( function() gui:destroy() end )
	end
	if host.cl then
		host.cl.rfsMenuGui = nil
	end
end
