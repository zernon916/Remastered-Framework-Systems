-- RfsBotActionGui.lua
-- VOLATILE: ally bot E menu (Commands / Storage). Game-hosted so callbacks resolve.
-- Does not change beacon E / queueOpen / spend / caps / hijack HP / SHOW RANGE host.

RfsBotActionGui = RfsBotActionGui or {}

local LAYOUT = "$CONTENT_DATA/Gui/Layouts/Rfs_BotAction.layout"

local function closeGui( host )
	host.cl = host.cl or {}
	local gui = host.cl.rfsBotActionGui
	host.cl.rfsBotActionGui = nil
	if gui then
		pcall( function() gui:close() end )
	end
end

function RfsBotActionGui.open( host, opts )
	opts = opts or {}
	host.cl = host.cl or {}
	local unitKey = opts.unitKey and tostring( opts.unitKey ) or nil
	if not unitKey or unitKey == "" then
		return
	end
	closeGui( host )
	host.cl.rfsBotActionUnitKey = unitKey
	host.cl.rfsBotActionChar = opts.charScript
	host.cl.rfsBotActionTitle = opts.title and tostring( opts.title ) or "BOT"

	local ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT, false, {
		isHud = false,
		isInteractive = true,
		needsCursor = true,
	} )
	if not ok or not gui then
		ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT, false )
	end
	if not ok or not gui then
		ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT )
	end
	if not ok or not gui then
		sm.gui.chatMessage( "[RFS] Bot menu failed to open" )
		return
	end
	host.cl.rfsBotActionGui = gui
	pcall( function()
		gui:setText( "Title", host.cl.rfsBotActionTitle )
		gui:setButtonCallback( "CloseButton", "cl_rfs_botActionClose" )
		gui:setButtonCallback( "BtnCommands", "cl_rfs_botActionCommands" )
		gui:setButtonCallback( "BtnStorage", "cl_rfs_botActionStorage" )
		gui:setOnCloseCallback( "cl_rfs_botActionClosed" )
		gui:open()
	end )
end

function RfsBotActionGui.close( host )
	closeGui( host )
	if host and host.cl then
		host.cl.rfsBotActionChar = nil
	end
end

function RfsBotActionGui.onCommands( host )
	local unitKey = host and host.cl and host.cl.rfsBotActionUnitKey
	closeGui( host )
	if not unitKey then
		return
	end
	if host.network and host.network.sendToServer then
		host.network:sendToServer( "sv_rfs_botOpenOrders", {
			unitKey = unitKey,
			player = sm.localPlayer.getPlayer(),
		} )
	end
end

function RfsBotActionGui.onStorage( host )
	local charScript = host and host.cl and host.cl.rfsBotActionChar
	local unitKey = host and host.cl and host.cl.rfsBotActionUnitKey
	closeGui( host )
	local opened = false
	if charScript and type( RfsBotInventory ) == "table" and RfsBotInventory.cl_openFromCharacter then
		pcall( function()
			opened = RfsBotInventory.cl_openFromCharacter( charScript ) and true or false
		end )
	end
	if opened then
		return
	end
	if host and host.network and unitKey then
		host.network:sendToServer( "sv_rfs_botOpenStorage", {
			unitKey = unitKey,
			player = sm.localPlayer.getPlayer(),
		} )
	end
end

print( "[RFS] RfsBotActionGui loaded (VOLATILE bot E Commands/Storage)" )
