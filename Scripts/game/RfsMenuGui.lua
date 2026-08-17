-- RfsMenuGui.lua — /menu player GUI for Recipe Framework Survival
-- Author: DemonsDen126
-- Style skins match Recipe Radar / Rfs_Setup (BackgroundInteractableWide, PrimaryButton).

RfsMenuGui = RfsMenuGui or {}

local LAYOUT = "$CONTENT_DATA/Gui/Layouts/Rfs_Menu.layout"

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
	gui:setText( "BtnGrowthOverlay", "Growth Time: " .. ( overlay and "ON" or "OFF" ) )
	pcall( function()
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

	gui:setText( "Status", string.format(
		"Map + Growth + GUI (yours only) | crop=%s names=%s blocks=%s",
		overlay and "ON" or "OFF",
		names and "ON" or "OFF",
		blockOn and "ON" or "OFF"
	) )
end

function RfsMenuGui.bind( host, gui )
	host.cl = host.cl or {}
	host.cl.rfsMenuGui = gui

	gui:setButtonCallback( "CloseButton", "cl_rfs_menuClose" )
	gui:setButtonCallback( "BtnMap", "cl_rfs_menuMap" )
	gui:setButtonCallback( "BtnGrowthOverlay", "cl_rfs_menuToggleGrowthOverlay" )
	gui:setButtonCallback( "BtnNames", "cl_rfs_menuToggleNames" )
	gui:setButtonCallback( "BtnBigRed", "cl_rfs_menuToggleBigRed" )
	gui:setButtonCallback( "BtnBlockOverlay", "cl_rfs_menuToggleBlockOverlay" )
	gui:setButtonCallback( "BtnEnemyHp", "cl_rfs_menuCycleEnemyHp" )
	gui:setButtonCallback( "BtnNeutralHp", "cl_rfs_menuCycleNeutralHp" )
	gui:setOnCloseCallback( "cl_rfs_menuClose" )
end

function RfsMenuGui.open( host )
	if host.cl and host.cl.rfsMenuGui then
		pcall( function() host.cl.rfsMenuGui:close() end )
		host.cl.rfsMenuGui = nil
	end

	local ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT )
	if not ok or not gui then
		sm.gui.chatMessage( "[RFS] Failed to open /menu GUI" )
		print( "[RFS] menu GUI create failed: " .. tostring( gui ) )
		return
	end

	RfsMenuGui.bind( host, gui )
	RfsMenuGui.refresh( host )
	gui:open()
	sm.gui.chatMessage( "RFS Menu opened" )
end

function RfsMenuGui.close( host )
	local gui = host.cl and host.cl.rfsMenuGui
	if gui then
		pcall( function() gui:close() end )
	end
	if host.cl then
		host.cl.rfsMenuGui = nil
	end
end
