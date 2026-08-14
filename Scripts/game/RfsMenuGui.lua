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

function RfsMenuGui.refresh( host )
	local gui = host.cl and host.cl.rfsMenuGui
	if not gui then return end

	local overlay = growthOn( host )
	gui:setText( "BtnGrowthOverlay", "Growth Time: " .. ( overlay and "ON" or "OFF" ) )
	pcall( function()
		gui:setButtonState( "BtnGrowthOverlay", overlay )
	end )
	gui:setText( "Status", string.format(
		"Map + Growth Time (yours only) | overlay=%s",
		overlay and "ON" or "OFF"
	) )
end

function RfsMenuGui.bind( host, gui )
	host.cl = host.cl or {}
	host.cl.rfsMenuGui = gui

	gui:setButtonCallback( "CloseButton", "cl_rfs_menuClose" )
	gui:setButtonCallback( "BtnMap", "cl_rfs_menuMap" )
	gui:setButtonCallback( "BtnGrowthOverlay", "cl_rfs_menuToggleGrowthOverlay" )
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
