-- RfsHandheldHackGui.lua — VOLATILE small menu (Follow / Defend) for handheld tool.

RfsHandheldHackGui = RfsHandheldHackGui or {}

local LAYOUT = "$CONTENT_DATA/Gui/Layouts/Rfs_HandheldHack.layout"

local function closeGui( host )
	host.cl = host.cl or {}
	local gui = host.cl.rfsHandheldGui
	host.cl.rfsHandheldGui = nil
	if gui then
		pcall( function() gui:close() end )
	end
end

function RfsHandheldHackGui.open( host, opts )
	opts = opts or {}
	host.cl = host.cl or {}
	local unitKey = opts.unitKey and tostring( opts.unitKey ) or nil
	if not unitKey or unitKey == "" then
		return
	end
	closeGui( host )
	host.cl.rfsHandheldUnitKey = unitKey
	local ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT, false, {
		isHud = false,
		isInteractive = true,
		needsCursor = true,
	} )
	if not ok or not gui then
		ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT, false )
	end
	if not ok or not gui then
		sm.gui.chatMessage( "[RFS] Handheld menu failed" )
		return
	end
	host.cl.rfsHandheldGui = gui
	pcall( function()
		gui:setButtonCallback( "CloseButton", "cl_rfs_handheldClose" )
		gui:setButtonCallback( "BtnFollow", "cl_rfs_handheldFollow" )
		gui:setButtonCallback( "BtnDefend", "cl_rfs_handheldDefend" )
		gui:setOnCloseCallback( "cl_rfs_handheldClosed" )
		gui:open()
	end )
end

function RfsHandheldHackGui.close( host )
	closeGui( host )
end

function RfsHandheldHackGui.sendOrder( host, mode )
	local unitKey = host and host.cl and host.cl.rfsHandheldUnitKey
	closeGui( host )
	if not unitKey or not host or not host.network then
		return
	end
	host.network:sendToServer( "sv_rfs_handheldOrder", {
		unitKey = unitKey,
		mode = mode,
		player = sm.localPlayer.getPlayer(),
	} )
end

print( "[RFS] RfsHandheldHackGui loaded" )
