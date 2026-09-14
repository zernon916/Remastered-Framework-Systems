-- RfsFarmTabletGui.lua — VOLATILE Farmers Tablet GUI (seed-icon plot grid).

RfsFarmTabletGui = RfsFarmTabletGui or {}

local LAYOUT = "$CONTENT_DATA/Gui/menu/layouts/Rfs_FarmTablet.layout"
local VIEW_W = 10
local VIEW_H = 8
local VIEW_N = VIEW_W * VIEW_H
local KIT_PREFIXES = {
	"$CONTENT_DATA/Gui/menu/images/farmtablet/",
}
local BAG_BY_SEED = {
	["eb1ef696-5c05-4662-9e47-fe1e0875ff84"] = "bag_potato.png",
	["38e41fb5-dd50-4294-829d-a517f0282fed"] = "bag_tomato.png",
	["9c82a525-8a8b-4483-9595-505aaa042486"] = "bag_carrot.png",
	["64051718-a3f1-422b-bda3-277efa0c4545"] = "bag_redbeet.png",
	["1c6756ca-3a60-4dcb-a5d1-353edf818308"] = "bag_broccoli.png",
	["9edb6f7c-fb44-4348-a1c4-8afb41b92d8a"] = "bag_pineapple.png",
	["4b6d2bee-d0f1-4e56-96f0-d2596388cad2"] = "bag_blueberry.png",
	["bee966b0-b5e5-41da-b992-5d363ab85ae4"] = "bag_orange.png",
	["22beade5-38ca-47b4-a2ee-32403f58a862"] = "bag_banana.png",
	["9a3e478c-2224-44fa-887c-239965bd05ad"] = "soil_light.png",
}

local function setKitImage( gui, widget, file )
	if not gui or not widget or not file then
		return false
	end
	for _, prefix in ipairs( KIT_PREFIXES ) do
		local ok = pcall( function()
			gui:setImage( widget, prefix .. file )
		end )
		if ok then
			pcall( function()
				gui:setVisible( widget, true )
			end )
			return true
		end
	end
	return false
end

local function setTabletOpenFlag( open )
	_G.g_rfsFarmTabletOpen = open and true or false
end

local function hideRfsHud( hidden )
	-- Never touch sm.localPlayer.getPlayer() here — that is engine userdata
	-- (Unknown member 'cl'). RFS HUD lives on the Player SCRIPT; the open flag
	-- makes RfsHud.update hide it. Optionally hide Game-hosted HUD if present.
	local game = _G.g_rfsGame
	if type( game ) == "table" and type( game.cl ) == "table" and game.cl.rfsHud then
		pcall( function() game.cl.rfsHud:setHidden( hidden ) end )
	end
end

local function closeGui( host )
	host = host or _G.g_rfsGame
	if not host then
		setTabletOpenFlag( false )
		hideRfsHud( false )
		pcall( function()
			if type( RfsHandheldLcd ) == "table" and RfsHandheldLcd.clearFarmTabletOpenRequest then
				RfsHandheldLcd.clearFarmTabletOpenRequest()
			end
		end )
		return
	end
	host.cl = host.cl or {}
	local gui = host.cl.rfsFarmTabletGui
	host.cl.rfsFarmTabletGui = nil
	host.cl.rfsFarmTabletFarms = nil
	host.cl.rfsFarmTabletIndex = nil
	host.cl.rfsFarmTabletWantOpen = nil
	host.cl.rfsFarmTabletScrollX = nil
	host.cl.rfsFarmTabletScrollY = nil
	setTabletOpenFlag( false )
	hideRfsHud( false )
	pcall( function()
		if type( RfsHandheldLcd ) == "table" and RfsHandheldLcd.clearFarmTabletOpenRequest then
			RfsHandheldLcd.clearFarmTabletOpenRequest()
		end
	end )
	if gui then
		pcall( function() gui:close() end )
		pcall( function() gui:destroy() end )
	end
end

local function setIcon( gui, widget, uuidStr )
	if not gui or not widget then
		return
	end
	if not uuidStr or uuidStr == "" then
		pcall( function() gui:setVisible( widget, false ) end )
		return
	end
	local ok = false
	pcall( function()
		gui:setVisible( widget, true )
		gui:setIconImage( widget, sm.uuid.new( uuidStr ) )
		ok = true
	end )
	if not ok then
		pcall( function()
			local resource, group, name = sm.gui.getItemIconFromUuid( sm.uuid.new( uuidStr ) )
			if resource and group and name then
				gui:setItemIcon( widget, resource, group, name )
				gui:setVisible( widget, true )
				ok = true
			end
		end )
	end
	if not ok then
		pcall( function() gui:setVisible( widget, false ) end )
	end
end

local function farmSize( farm )
	if not farm then
		return 0, 0
	end
	local w = ( farm.maxX or 0 ) - ( farm.minX or 0 ) + 1
	local h = ( farm.maxY or 0 ) - ( farm.minY or 0 ) + 1
	if w < 1 then w = 1 end
	if h < 1 then h = 1 end
	return w, h
end

local function maxScroll( farm )
	local fw, fh = farmSize( farm )
	return math.max( 0, fw - VIEW_W ), math.max( 0, fh - VIEW_H )
end

local function centerScroll( host, farm )
	local maxX, maxY = maxScroll( farm )
	host.cl.rfsFarmTabletScrollX = math.floor( maxX * 0.5 )
	host.cl.rfsFarmTabletScrollY = math.floor( maxY * 0.5 )
end

local function clampScroll( host, farm )
	local maxX, maxY = maxScroll( farm )
	local sx = tonumber( host.cl.rfsFarmTabletScrollX ) or 0
	local sy = tonumber( host.cl.rfsFarmTabletScrollY ) or 0
	if sx < 0 then sx = 0 end
	if sy < 0 then sy = 0 end
	if sx > maxX then sx = maxX end
	if sy > maxY then sy = maxY end
	host.cl.rfsFarmTabletScrollX = sx
	host.cl.rfsFarmTabletScrollY = sy
	return sx, sy, maxX, maxY
end

local function clearPlot( gui )
	for i = 0, VIEW_N - 1 do
		pcall( function()
			gui:setVisible( "Plot" .. i, true )
			gui:setText( "Plot" .. i, "" )
		end )
		setIcon( gui, "PlotIcon" .. i, nil )
	end
end

local function paintPlot( host, farm )
	local gui = host.cl.rfsFarmTabletGui
	if not gui then
		return
	end
	if not farm or type( farm.cells ) ~= "table" then
		clearPlot( gui )
		pcall( function() gui:setText( "ScrollLabel", "" ) end )
		return
	end

	local sx, sy, maxX, maxY = clampScroll( host, farm )
	local lookup = {}
	for _, c in ipairs( farm.cells ) do
		lookup[tostring( c.x ) .. "," .. tostring( c.y )] = c
	end

	local n = 0
	for row = 0, VIEW_H - 1 do
		for col = 0, VIEW_W - 1 do
			local wx = ( farm.minX or 0 ) + sx + col
			-- Top of UI = north (higher world Y), matching old ASCII grid.
			local wy = ( farm.maxY or 0 ) - sy - row
			local cell = lookup[tostring( wx ) .. "," .. tostring( wy )]
			local seed = cell and cell.seed or nil
			pcall( function()
				gui:setVisible( "Plot" .. n, true )
				gui:setText( "Plot" .. n, "" )
			end )
			local bag = nil
			if seed then
				bag = BAG_BY_SEED[string.lower( tostring( seed ) )]
			end
			if bag then
				setKitImage( gui, "PlotIcon" .. n, bag )
			elseif seed then
				setIcon( gui, "PlotIcon" .. n, seed )
			else
				setKitImage( gui, "PlotIcon" .. n, "slot_off.png" )
			end
			n = n + 1
		end
	end

	local fw, fh = farmSize( farm )
	pcall( function()
		gui:setText( "ScrollLabel", string.format( "%dx%d  @%d,%d", fw, fh, sx, sy ) )
	end )
	-- Silence unused when farm fits viewport.
	if maxX == 0 and maxY == 0 then
		pcall( function()
			gui:setText( "ScrollLabel", string.format( "%dx%d", fw, fh ) )
		end )
	end
end

local function refreshView( host )
	host = host or _G.g_rfsGame
	if not host or not host.cl then
		return
	end
	local gui = host.cl.rfsFarmTabletGui
	if not gui then
		return
	end
	local farms = host.cl.rfsFarmTabletFarms or {}
	local idx = host.cl.rfsFarmTabletIndex or 1
	if #farms == 0 then
		pcall( function()
			gui:setText( "FarmLabel", "No farms within 100" )
			gui:setText( "AvgText", "" )
			gui:setText( "ScrollLabel", "" )
		end )
		clearPlot( gui )
		return
	end
	if idx < 1 then idx = 1 end
	if idx > #farms then idx = #farms end
	host.cl.rfsFarmTabletIndex = idx
	local farm = farms[idx]
	if host.cl.rfsFarmTabletScrollX == nil or host.cl.rfsFarmTabletScrollY == nil then
		centerScroll( host, farm )
	else
		clampScroll( host, farm )
	end
	pcall( function()
		gui:setText( "FarmLabel", string.format( "%s   (%d / %d)", farm.label or "Farm", idx, #farms ) )
		gui:setText( "AvgText", RfsFarmTablet.avgLines( farm ) )
	end )
	paintPlot( host, farm )
end

local function applyScan( host, payload )
	host = host or _G.g_rfsGame
	if not host or not host.cl or not host.cl.rfsFarmTabletGui then
		return
	end
	local cells = payload and payload.cells or {}
	if type( RfsFarmTablet ) == "table" and RfsFarmTablet.mergeClientRemains then
		cells = RfsFarmTablet.mergeClientRemains( cells )
	end
	local farms = {}
	if type( RfsFarmTablet ) == "table" and RfsFarmTablet.clusterFarms then
		farms = RfsFarmTablet.clusterFarms( cells, payload and payload.playerX, payload and payload.playerY ) or {}
	end
	host.cl.rfsFarmTabletFarms = farms
	host.cl.rfsFarmTabletIndex = 1
	host.cl.rfsFarmTabletScrollX = nil
	host.cl.rfsFarmTabletScrollY = nil
	refreshView( host )
end

function RfsFarmTabletGui.open( host, data )
	host = host or _G.g_rfsGame
	if not host then
		sm.gui.chatMessage( "[RFS] Farmers Tablet: no game host" )
		pcall( function()
			if type( RfsHandheldLcd ) == "table" and RfsHandheldLcd.clearFarmTabletOpenRequest then
				RfsHandheldLcd.clearFarmTabletOpenRequest()
			end
		end )
		return
	end
	host.cl = host.cl or {}
	-- Match Recipe Viewer: always close then recreate.
	closeGui( host )
	host.cl = host.cl or {}

	local ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT, true, {
		isHud = false,
		isInteractive = true,
		needsCursor = true,
	} )
	if not ok or not gui then
		ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT, true )
	end
	if not ok or not gui then
		ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT )
	end
	if not ok or not gui then
		sm.gui.chatMessage( "[RFS] Farmers Tablet menu failed: " .. tostring( gui ) )
		print( "[RFS] FarmTablet create failed: " .. tostring( gui ) )
		return
	end

	host.cl.rfsFarmTabletGui = gui
	host.cl.rfsFarmTabletScrollX = nil
	host.cl.rfsFarmTabletScrollY = nil
	setTabletOpenFlag( true )
	hideRfsHud( true )
	pcall( function()
		if type( RfsHandheldLcd ) == "table" and RfsHandheldLcd.clearFarmTabletOpenRequest then
			RfsHandheldLcd.clearFarmTabletOpenRequest()
		end
	end )

	pcall( function()
		gui:setButtonCallback( "CloseButton", "cl_rfs_farmTabletClose" )
		gui:setButtonCallback( "FarmPrev", "cl_rfs_farmTabletPrev" )
		gui:setButtonCallback( "FarmNext", "cl_rfs_farmTabletNext" )
		gui:setButtonCallback( "RefreshButton", "cl_rfs_farmTabletRefresh" )
		gui:setButtonCallback( "ScrollUp", "cl_rfs_farmTabletScrollUp" )
		gui:setButtonCallback( "ScrollDown", "cl_rfs_farmTabletScrollDown" )
		gui:setButtonCallback( "ScrollLeft", "cl_rfs_farmTabletScrollLeft" )
		gui:setButtonCallback( "ScrollRight", "cl_rfs_farmTabletScrollRight" )
		gui:setOnCloseCallback( "cl_rfs_farmTabletClosed" )
		gui:setText( "Title", "FARMERS TABLET" )
		gui:setText( "CloseButton", "" )
		gui:setText( "FarmPrev", "" )
		gui:setText( "FarmNext", "" )
		gui:setText( "RefreshButton", "" )
		gui:setText( "PlotTitle", "FARM PLOTS" )
		gui:setText( "AvgTitle", "FARM SUMMARY" )
		gui:setText( "Hint", "Seed bags = crops. Soil pile = bare soil. Scroll for large farms." )
		gui:setText( "ScrollUp", "" )
		gui:setText( "ScrollDown", "" )
		gui:setText( "ScrollLeft", "" )
		gui:setText( "ScrollRight", "" )
		gui:setText( "FarmLabel", "Scanning..." )
		gui:setText( "AvgText", "" )
		gui:setText( "ScrollLabel", "" )
		setKitImage( gui, "BgPanel", "panel_bg.png" )
		setKitImage( gui, "ArtPlotWell", "panel_wide.png" )
		setKitImage( gui, "ArtSummaryWell", "panel_side.png" )
		setKitImage( gui, "ArtClose", "btn_close.png" )
		setKitImage( gui, "ArtPrev", "btn_prev_off.png" )
		setKitImage( gui, "ArtNext", "btn_next_off.png" )
		setKitImage( gui, "ArtRefresh", "btn_refresh_on.png" )
		setKitImage( gui, "ArtScrollUp", "scroll_up.png" )
		setKitImage( gui, "ArtLeft", "btn_left_off.png" )
		setKitImage( gui, "ArtDown", "btn_down_off.png" )
		setKitImage( gui, "ArtRight", "btn_right_off.png" )
		pcall( function()
			gui:setVisible( "ArtPrevOn", false )
			gui:setVisible( "ArtNextOn", false )
			gui:setVisible( "ArtRefreshOff", false )
		end )
		clearPlot( gui )
		gui:open()
	end )

	pcall( function()
		sm.gui.chatMessage( "[RFS] Farmers Tablet open" )
	end )
	pcall( function()
		host.network:sendToServer( "sv_rfs_farmTabletScan", {} )
	end )
end

function RfsFarmTabletGui.close( host )
	closeGui( host or _G.g_rfsGame )
end

function RfsFarmTabletGui.prev( host )
	host = host or _G.g_rfsGame
	if not host or not host.cl then return end
	local farms = host.cl.rfsFarmTabletFarms or {}
	if #farms == 0 then return end
	local idx = ( host.cl.rfsFarmTabletIndex or 1 ) - 1
	if idx < 1 then idx = #farms end
	host.cl.rfsFarmTabletIndex = idx
	host.cl.rfsFarmTabletScrollX = nil
	host.cl.rfsFarmTabletScrollY = nil
	refreshView( host )
end

function RfsFarmTabletGui.next( host )
	host = host or _G.g_rfsGame
	if not host or not host.cl then return end
	local farms = host.cl.rfsFarmTabletFarms or {}
	if #farms == 0 then return end
	local idx = ( host.cl.rfsFarmTabletIndex or 1 ) + 1
	if idx > #farms then idx = 1 end
	host.cl.rfsFarmTabletIndex = idx
	host.cl.rfsFarmTabletScrollX = nil
	host.cl.rfsFarmTabletScrollY = nil
	refreshView( host )
end

function RfsFarmTabletGui.refresh( host )
	host = host or _G.g_rfsGame
	if not host then return end
	pcall( function()
		host.network:sendToServer( "sv_rfs_farmTabletScan", {} )
	end )
end

function RfsFarmTabletGui.scroll( host, dx, dy )
	host = host or _G.g_rfsGame
	if not host or not host.cl then return end
	local farms = host.cl.rfsFarmTabletFarms or {}
	local idx = host.cl.rfsFarmTabletIndex or 1
	local farm = farms[idx]
	if not farm then return end
	local sx = tonumber( host.cl.rfsFarmTabletScrollX ) or 0
	local sy = tonumber( host.cl.rfsFarmTabletScrollY ) or 0
	host.cl.rfsFarmTabletScrollX = sx + ( dx or 0 )
	host.cl.rfsFarmTabletScrollY = sy + ( dy or 0 )
	refreshView( host )
end

function RfsFarmTabletGui.applyScan( host, payload )
	applyScan( host, payload )
end

print( "[RFS] RfsFarmTabletGui loaded" )
