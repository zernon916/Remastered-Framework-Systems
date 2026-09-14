-- RfsRecipeViewerGui.lua — recipes + remote queue on one screen.
-- ALL / category tabs show learned recipes. Ingredient counts come from inventory.
-- ADD TO REMOTE QUEUE stores jobs on the tablet. SEND TO CRAFTER pushes them.

RfsRecipeViewerGui = RfsRecipeViewerGui or {}

local LAYOUT = "$CONTENT_DATA/Gui/menu/layouts/Rfs_RecipeViewer.layout"
local PAGE = 24
local COLS = 6
local ROWS = 4
local QUEUE_ROWS = 6
local MAX_REMOTE = 6
local CAT_ALL = "all"
local KIT_PREFIXES = {
	"$CONTENT_DATA/Gui/menu/images/tablet/",
	"$CONTENT_DATA/Gui/menu/images/craftstation/",
}

local CAT_BUTTONS = {
	{ id = CAT_ALL, widget = "CatAll", on = "category_all_gold.png", off = "category_all_gold.png" },
	{ id = "tool", widget = "CatTool", on = "category_tools.png", off = "category_tools.png" },
	{ id = "block", widget = "CatBlock", on = "category_blocks.png", off = "category_blocks.png" },
	{ id = "interactive", widget = "CatInteractive", on = "category_interactive.png", off = "category_interactive.png" },
	{ id = "part", widget = "CatPart", on = "category_parts.png", off = "category_parts.png" },
	{ id = "consumable", widget = "CatConsumable", on = "category_consumable.png", off = "category_consumable.png" },
}

-- Layout ImageTexture is an editor hint. In-game these ImageBoxes stay blank
-- until setImage. setImage also restacks the widget to the front of its parent,
-- so covering wells live in their own wrapper and we paint back-to-front.
local function paintKitImage( gui, widget, file )
	if not gui or not widget or not file then
		return false
	end
	for _, prefix in ipairs( KIT_PREFIXES ) do
		local ok = pcall( function()
			gui:setImage( widget, prefix .. file )
		end )
		if ok then
			return true
		end
	end
	return false
end

local function setKitImage( gui, widget, file )
	if paintKitImage( gui, widget, file ) then
		pcall( function()
			gui:setVisible( widget, true )
		end )
		return true
	end
	return false
end

local function lastNumber( ... )
	local n
	for i = 1, select( "#", ... ) do
		local v = tonumber( select( i, ... ) )
		if v then
			n = v
		end
	end
	return n
end

local function bindOne( gui, method, widget, cb )
	pcall( function()
		gui[method]( gui, widget, cb )
	end )
end

local function bindViewer( gui )
	if not gui then
		return
	end
	bindOne( gui, "setButtonCallback", "CloseButton", "cl_rfs_recipeViewerClose" )
	bindOne( gui, "setSliderCallback", "ScrollBar", "cl_rfs_recipeViewerScroll" )
	bindOne( gui, "setButtonCallback", "BtnScrollUp", "cl_rfs_recipeViewerScrollUp" )
	bindOne( gui, "setButtonCallback", "BtnScrollDown", "cl_rfs_recipeViewerScrollDown" )
	bindOne( gui, "setMouseWheelCallback", "Root", "cl_rfs_recipeViewerWheel" )
	bindOne( gui, "setMouseWheelCallback", "BgPanel", "cl_rfs_recipeViewerWheel" )
	bindOne( gui, "setMouseWheelCallback", "MainPanel", "cl_rfs_recipeViewerWheel" )
	bindOne( gui, "setMouseWheelCallback", "PanelRecipes", "cl_rfs_recipeViewerWheel" )
	bindOne( gui, "setMouseWheelCallback", "ArtSlots", "cl_rfs_recipeViewerWheel" )
	bindOne( gui, "setMouseWheelCallback", "PanelCells", "cl_rfs_recipeViewerWheel" )
	bindOne( gui, "setMouseWheelCallback", "ArtScrollWell", "cl_rfs_recipeViewerWheel" )
	bindOne( gui, "setMouseWheelCallback", "ArtScrollRecipes", "cl_rfs_recipeViewerWheel" )
	bindOne( gui, "setMouseWheelCallback", "ScrollBar", "cl_rfs_recipeViewerWheel" )
	bindOne( gui, "setButtonCallback", "BtnPair", "cl_rfs_recipeViewerPair" )
	bindOne( gui, "setButtonCallback", "BtnSend", "cl_rfs_recipeViewerSend" )
	bindOne( gui, "setButtonCallback", "BtnAddQueue", "cl_rfs_recipeViewerAddQueue" )
	bindOne( gui, "setButtonCallback", "BtnPrio1", "cl_rfs_recipeViewerPrio1" )
	bindOne( gui, "setButtonCallback", "BtnPrio2", "cl_rfs_recipeViewerPrio2" )
	bindOne( gui, "setButtonCallback", "BtnPrio3", "cl_rfs_recipeViewerPrio3" )
	bindOne( gui, "setButtonCallback", "BtnPrio4", "cl_rfs_recipeViewerPrio4" )
	bindOne( gui, "setButtonCallback", "BtnClear", "cl_rfs_recipeViewerClear" )
	bindOne( gui, "setButtonCallback", "BtnPlus", "cl_rfs_recipeViewerPlus" )
	bindOne( gui, "setButtonCallback", "BtnMinus", "cl_rfs_recipeViewerMinus" )
	bindOne( gui, "setButtonCallback", "CatAll", "cl_rfs_recipeViewerCatAll" )
	bindOne( gui, "setButtonCallback", "CatTool", "cl_rfs_recipeViewerCatTool" )
	bindOne( gui, "setButtonCallback", "CatBlock", "cl_rfs_recipeViewerCatBlock" )
	bindOne( gui, "setButtonCallback", "CatInteractive", "cl_rfs_recipeViewerCatInteractive" )
	bindOne( gui, "setButtonCallback", "CatPart", "cl_rfs_recipeViewerCatPart" )
	bindOne( gui, "setButtonCallback", "CatConsumable", "cl_rfs_recipeViewerCatConsumable" )
	pcall( function()
		gui:setOnCloseCallback( "cl_rfs_recipeViewerClosed" )
	end )
	for i = 0, PAGE - 1 do
		bindOne( gui, "setButtonCallback", "Cell" .. i, "cl_rfs_recipeViewerPick" )
		bindOne( gui, "setMouseWheelCallback", "Cell" .. i, "cl_rfs_recipeViewerWheel" )
		bindOne( gui, "setMouseWheelCallback", "Icon" .. i, "cl_rfs_recipeViewerWheel" )
	end
	for _, cat in ipairs( CAT_BUTTONS ) do
		bindOne( gui, "setMouseWheelCallback", cat.widget, "cl_rfs_recipeViewerWheel" )
		bindOne( gui, "setMouseWheelCallback", "Art" .. cat.widget, "cl_rfs_recipeViewerWheel" )
	end
	for i = 0, QUEUE_ROWS - 1 do
		bindOne( gui, "setButtonCallback", "QCancel" .. i, "cl_rfs_recipeViewerQCancel" )
	end
end

local function setViewerOpenFlag( open )
	_G.g_rfsRecipeViewerOpen = open and true or false
end

local function pairSnap( host )
	return ( host and host.cl and host.cl.rfsCraftPair ) or {}
end

local function wirelessOnline( host )
	local snap = pairSnap( host )
	return snap.connected == true or snap.wireless == true
end

local function isPaired( host )
	return pairSnap( host ).paired == true
end

local function canSend( host )
	local snap = pairSnap( host )
	return snap.paired == true and snap.connected == true
end

local function setWirelessArt( gui, host )
	if not gui then
		return
	end
	setKitImage( gui, "ArtWireless", "badge_wireless_online.png" )
	local on = wirelessOnline( host )
	pcall( function()
		gui:setVisible( "ArtWireless", on )
		gui:setVisible( "ArtWirelessOff", false )
	end )
end

local function applyChrome( gui )
	if not gui then
		return
	end
	paintKitImage( gui, "BgPanel", "mobile_crafting_tablet_background_clean.png" )
	paintKitImage( gui, "ArtTitle", "title_mobile_crafting_tablet.png" )
	paintKitImage( gui, "ArtClose", "button_close_gold.png" )
	paintKitImage( gui, "ArtHint", "instruction_strip.png" )
	paintKitImage( gui, "ArtWireless", "badge_wireless_online.png" )
	paintKitImage( gui, "ArtWirelessOff", "badge_wireless_online.png" )
	paintKitImage( gui, "ArtStationBadge", "badge_station_1.png" )
	paintKitImage( gui, "ArtCraftPanel", "panel_craftable_gold_blank.png" )
	paintKitImage( gui, "ArtRemoteQueue", "panel_remote_queue_gold_blank.png" )
	paintKitImage( gui, "ArtSelected", "selected_recipe_blank.png" )
	paintKitImage( gui, "ArtAmount", "panel_amount_full.png" )
	for _, cat in ipairs( CAT_BUTTONS ) do
		paintKitImage( gui, "Art" .. cat.widget, cat.off )
	end
	for i = 0, PAGE - 1 do
		paintKitImage( gui, "ArtSlot" .. i, "slot_empty.png" )
	end
	for i = 0, QUEUE_ROWS - 1 do
		paintKitImage( gui, "ArtQRow" .. i, "queue_row_empty.png" )
		paintKitImage( gui, "ArtQX" .. i, "button_remove_red.png" )
	end
	paintKitImage( gui, "ArtMinus", "button_amount_minus.png" )
	paintKitImage( gui, "ArtPlus", "button_amount_plus.png" )
	paintKitImage( gui, "ArtAddQueue", "button_add_remote_queue_gold.png" )
	paintKitImage( gui, "ArtSend", "button_send_to_crafter.png" )
	paintKitImage( gui, "ArtPair", "button_pair_gold.png" )
	paintKitImage( gui, "ArtClear", "button_clear_queue.png" )
	paintKitImage( gui, "ArtPrio1", "button_station_1_gold.png" )
	paintKitImage( gui, "ArtPrio2", "button_station_2.png" )
	paintKitImage( gui, "ArtPrio3", "button_station_3.png" )
	paintKitImage( gui, "ArtPrio4", "button_station_4.png" )
	paintKitImage( gui, "ArtScrollRecipes", "scrollbar_recipes.png" )
	pcall( function()
		gui:setVisible( "Title", false )
		gui:setVisible( "ArtWireless", false )
		gui:setVisible( "ArtWirelessOff", false )
		gui:setVisible( "ArtStationBadge", false )
		gui:setVisible( "PanelRecipes", true )
		gui:setVisible( "PanelQueue", true )
		gui:setVisible( "PanelSelected", true )
		gui:setVisible( "PanelAmount", true )
		gui:setVisible( "ArtSlots", true )
		gui:setVisible( "ArtScrollWell", true )
		gui:setVisible( "ArtScrollRecipes", true )
		gui:setVisible( "ScrollBar", true )
		gui:setVisible( "BtnScrollUp", true )
		gui:setVisible( "BtnScrollDown", true )
		for i = 0, QUEUE_ROWS - 1 do
			gui:setVisible( "ArtQRow" .. i, true )
			gui:setVisible( "ArtQX" .. i, false )
		end
	end )
end

local function closeGui( host )
	setViewerOpenFlag( false )
	pcall( function()
		if type( RfsHandheldLcd ) == "table" and RfsHandheldLcd.clearRecipeViewerOpenRequest then
			RfsHandheldLcd.clearRecipeViewerOpenRequest()
		end
	end )
	if not host then
		return
	end
	host.cl = host.cl or {}
	local gui = host.cl.rfsRecipeViewerGui
	host.cl.rfsRecipeViewerGui = nil
	if gui then
		pcall( function() gui:close() end )
	end
end

local function queueList( host )
	local snap = host.cl and host.cl.rfsRecipeViewerQueueSnap
	if type( snap ) ~= "table" then
		snap = _G.g_rfsCraftQueueClientSnap
	end
	if type( snap ) == "table" and type( snap.crafts ) == "table" then
		return snap.crafts
	end
	return {}
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

local function findRecipe( itemId )
	if type( RfsCraftQueue ) == "table" and RfsCraftQueue.findRecipe then
		return RfsCraftQueue.findRecipe( itemId )
	end
	return nil
end

local function itemName( itemId )
	local title = tostring( itemId or "" )
	pcall( function()
		local t = sm.shape.getShapeTitle( sm.uuid.new( itemId ) )
		if type( t ) == "string" and t ~= "" and t ~= "not found" then
			title = t
		end
	end )
	return title
end

local function inventoryCount( uuidStr )
	local n = 0
	pcall( function()
		local inv = sm.localPlayer.getInventory()
		if inv and uuidStr and uuidStr ~= "" then
			n = sm.container.totalQuantity( inv, sm.uuid.new( tostring( uuidStr ) ) ) or 0
		end
	end )
	return tonumber( n ) or 0
end

local function filteredList( host )
	local all = host.cl and host.cl.rfsRecipeViewerList or {}
	local cat = host.cl and host.cl.rfsRecipeViewerCategory or CAT_ALL
	local out = {}
	for _, row in ipairs( all ) do
		if row and row.itemId then
			local c = row.category
			if not c and type( RfsCraftQueue ) == "table" and RfsCraftQueue.itemCategory then
				c = RfsCraftQueue.itemCategory( row.itemId )
				row.category = c
			end
			if cat == CAT_ALL or cat == nil or cat == "" or tostring( c or "part" ) == cat then
				out[#out + 1] = row
			end
		end
	end
	return out
end

local function refreshCategoryTabs( host )
	local gui = host.cl and host.cl.rfsRecipeViewerGui
	if not gui then
		return
	end
	local cur = host.cl.rfsRecipeViewerCategory or CAT_ALL
	for _, cat in ipairs( CAT_BUTTONS ) do
		local on = cat.id == cur
		pcall( function()
			gui:setButtonState( cat.widget, on )
		end )
	end
end

local function refreshTabs( host )
	local gui = host.cl and host.cl.rfsRecipeViewerGui
	if not gui then
		return
	end
	pcall( function()
		gui:setVisible( "PanelRecipes", true )
		gui:setVisible( "PanelQueue", true )
		gui:setVisible( "ArtTabRecipes", false )
		gui:setVisible( "ArtTabQueue", false )
		gui:setVisible( "TabRecipes", false )
		gui:setVisible( "TabQueue", false )
	end )
end

local function refreshSelected( host )
	local gui = host.cl and host.cl.rfsRecipeViewerGui
	if not gui then
		return
	end
	local selected = host.cl.rfsRecipeViewerSelected
	local qty = math.max( 1, math.floor( tonumber( host.cl.rfsRecipeViewerQty ) or 1 ) )
	pcall( function()
		gui:setText( "SelectedQty", tostring( qty ) )
	end )
	if not selected then
		pcall( function()
			gui:setText( "SelName", "SELECT A RECIPE" )
			gui:setVisible( "SelIcon", false )
		end )
		for i = 0, 2 do
			setIcon( gui, "IngIcon" .. i, nil )
			pcall( function() gui:setText( "IngHave" .. i, "" ) end )
		end
		return
	end
	pcall( function()
		gui:setText( "SelName", string.upper( itemName( selected ) ) )
	end )
	setIcon( gui, "SelIcon", selected )
	local recipe = findRecipe( selected )
	local ings = ( recipe and recipe.ingredientList ) or {}
	for i = 0, 2 do
		local ing = ings[i + 1]
		if ing and ing.itemId then
			local need = ( tonumber( ing.quantity ) or 1 ) * qty
			local have = inventoryCount( ing.itemId )
			setIcon( gui, "IngIcon" .. i, tostring( ing.itemId ) )
			pcall( function()
				gui:setText( "IngHave" .. i, string.format( "%d/%d", have, need ) )
			end )
		else
			setIcon( gui, "IngIcon" .. i, nil )
			pcall( function() gui:setText( "IngHave" .. i, "" ) end )
		end
	end
end

local function refreshPairBar( host )
	local gui = host.cl and host.cl.rfsRecipeViewerGui
	if not gui then
		return
	end
	local snap = pairSnap( host )
	local paired = snap.paired == true
	local prio = tonumber( snap.prio ) or 0
	local n = math.max( 1, math.min( 4, prio > 0 and prio or 1 ) )
	setKitImage( gui, "ArtStationBadge", "badge_station_1.png" )
	if n == 1 then
		setKitImage( gui, "ArtStationBadge", "badge_station_1.png" )
	end
	pcall( function()
		if paired and snap.connected then
			gui:setText( "PairStatus", string.format( "LINKED  STATION %d", prio ) )
			gui:setVisible( "ArtStationBadge", true )
		elseif paired then
			gui:setText( "PairStatus", "PAIRED — OUT OF RANGE" )
			gui:setVisible( "ArtStationBadge", true )
		else
			gui:setText( "PairStatus", "" )
			gui:setVisible( "ArtStationBadge", false )
		end
	end )
	for i = 1, 4 do
		local on = paired and prio == i
		pcall( function()
			gui:setButtonState( "BtnPrio" .. i, on )
		end )
		if i == 1 then
			paintKitImage( gui, "ArtPrio1", "button_station_1_gold.png" )
		elseif i == 2 then
			paintKitImage( gui, "ArtPrio2", "button_station_2.png" )
		elseif i == 3 then
			paintKitImage( gui, "ArtPrio3", "button_station_3.png" )
		else
			paintKitImage( gui, "ArtPrio4", "button_station_4.png" )
		end
	end
	setWirelessArt( gui, host )
end

local function refreshQueue( host )
	local gui = host.cl and host.cl.rfsRecipeViewerGui
	if not gui then
		return
	end
	local crafts = queueList( host )
	pcall( function()
		gui:setText( "QueueLimit", string.format( "QUEUE LIMIT: %d / %d", #crafts, MAX_REMOTE ) )
	end )
	for i = 0, QUEUE_ROWS - 1 do
		local row = crafts[i + 1]
		if row and row.itemId then
			local need = math.max( 1, math.floor( tonumber( row.qty ) or 1 ) )
			local have = math.max( 0, math.floor( tonumber( row.have ) or 0 ) )
			pcall( function()
				gui:setVisible( "ArtQRow" .. i, true )
				gui:setVisible( "QName" .. i, true )
				gui:setVisible( "QAmt" .. i, true )
				gui:setVisible( "QCell" .. i, true )
				gui:setVisible( "ArtQX" .. i, true )
				gui:setVisible( "QCancel" .. i, true )
				gui:setText( "QName" .. i, string.upper( itemName( row.itemId ) ) )
				gui:setText( "QAmt" .. i, string.format( "AMOUNT: %d    %d / %d", need, have, need ) )
			end )
			setIcon( gui, "QIcon" .. i, tostring( row.itemId ) )
		else
			pcall( function()
				gui:setVisible( "ArtQRow" .. i, true )
				gui:setVisible( "QCell" .. i, false )
				gui:setVisible( "QIcon" .. i, false )
				gui:setVisible( "QCancel" .. i, false )
				gui:setVisible( "ArtQX" .. i, false )
				gui:setText( "QName" .. i, "" )
				gui:setText( "QAmt" .. i, "" )
			end )
		end
	end
end

local function refreshPage( host )
	local gui = host.cl and host.cl.rfsRecipeViewerGui
	if not gui then
		return
	end
	local list = filteredList( host )
	host.cl.rfsRecipeViewerFiltered = list
	local maxScroll = math.max( 0, math.ceil( #list / COLS ) - ROWS )
	local scroll = math.max( 0, math.min( maxScroll, math.floor( tonumber( host.cl.rfsRecipeViewerScroll ) or 0 ) ) )
	host.cl.rfsRecipeViewerScroll = scroll
	pcall( function()
		if not host.cl.rfsRecipeViewerIgnoreSlider then
			host.cl.rfsRecipeViewerIgnoreSlider = true
			gui:setSliderData( "ScrollBar", math.max( 1, maxScroll + 1 ), scroll )
			gui:setVisible( "ArtScrollWell", true )
			gui:setVisible( "ArtScrollRecipes", true )
			gui:setVisible( "ScrollBar", true )
			gui:setVisible( "BtnScrollUp", true )
			gui:setVisible( "BtnScrollDown", true )
			host.cl.rfsRecipeViewerIgnoreSlider = nil
		end
	end )
	local base = scroll * COLS
	local selected = host.cl.rfsRecipeViewerSelected
	for i = 0, PAGE - 1 do
		local row = list[base + i + 1]
		local cell = "Cell" .. i
		local icon = "Icon" .. i
		if row then
			pcall( function()
				gui:setButtonState( cell, selected == row.itemId )
				gui:setVisible( "ArtSlot" .. i, true )
				gui:setVisible( cell, true )
				gui:setVisible( icon, true )
			end )
			setIcon( gui, icon, row.itemId )
		else
			pcall( function()
				gui:setButtonState( cell, false )
				gui:setVisible( cell, false )
				gui:setVisible( icon, false )
				gui:setVisible( "ArtSlot" .. i, false )
			end )
		end
	end
	refreshPairBar( host )
	refreshSelected( host )
	refreshQueue( host )
	refreshTabs( host )
	refreshCategoryTabs( host )
end

function RfsRecipeViewerGui.open( host, opts )
	opts = opts or {}
	host = host or _G.g_rfsGame
	if not host then
		return
	end
	host.cl = host.cl or {}
	closeGui( host )
	pcall( function()
		if ( not g_craftingRecipeSets or not next( g_craftingRecipeSets ) ) and host.loadCraftingRecipes then
			host:loadCraftingRecipes()
		end
	end )
	local list = {}
	if type( RfsCraftQueue ) == "table" and RfsCraftQueue.listKnownRecipes then
		list = RfsCraftQueue.listKnownRecipes() or {}
	end
	host.cl.rfsRecipeViewerList = list
	host.cl.rfsRecipeViewerScroll = 0
	host.cl.rfsRecipeViewerTab = "recipes"
	host.cl.rfsRecipeViewerCategory = CAT_ALL
	host.cl.rfsRecipeViewerSelected = nil
	host.cl.rfsRecipeViewerQty = 1
	host.cl.rfsRecipeViewerQueueSnap = _G.g_rfsCraftQueueClientSnap
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
		setViewerOpenFlag( false )
		pcall( function()
			if type( RfsHandheldLcd ) == "table" and RfsHandheldLcd.clearRecipeViewerOpenRequest then
				RfsHandheldLcd.clearRecipeViewerOpenRequest()
			end
		end )
		sm.gui.chatMessage( "[RFS] Mobile Crafting Tablet menu failed" )
		return
	end
	host.cl.rfsRecipeViewerGui = gui
	local opened = pcall( function()
		gui:open()
	end )
	if not opened then
		host.cl.rfsRecipeViewerGui = nil
		setViewerOpenFlag( false )
		sm.gui.chatMessage( "[RFS] Mobile Crafting Tablet menu failed to open" )
		return
	end
	setViewerOpenFlag( true )
	pcall( function()
		if type( RfsHandheldLcd ) == "table" and RfsHandheldLcd.clearRecipeViewerOpenRequest then
			RfsHandheldLcd.clearRecipeViewerOpenRequest()
		end
	end )
	pcall( applyChrome, gui )
	pcall( bindViewer, gui )
	pcall( refreshPage, host )
	pcall( bindViewer, gui )
	if host.network then
		host.network:sendToServer( "sv_rfs_craftTabletStatus", {} )
	end
end

function RfsRecipeViewerGui.close( host )
	closeGui( host or _G.g_rfsGame )
end

function RfsRecipeViewerGui.onQueueSync( host, snap )
	host = host or _G.g_rfsGame
	if not host or not host.cl or not host.cl.rfsRecipeViewerGui then
		return
	end
	host.cl.rfsRecipeViewerQueueSnap = snap
	refreshPage( host )
end

function RfsRecipeViewerGui.onPairSync( host, snap )
	host = host or _G.g_rfsGame
	if not host or not host.cl then
		return
	end
	host.cl.rfsCraftPair = type( snap ) == "table" and snap or {}
	if host.cl.rfsRecipeViewerGui then
		refreshPairBar( host )
	end
end

function RfsRecipeViewerGui.search( host )
	refreshPage( host or _G.g_rfsGame )
end

function RfsRecipeViewerGui.scroll( host, name, value )
	host = host or _G.g_rfsGame
	if not host or not host.cl or host.cl.rfsRecipeViewerIgnoreSlider then
		return
	end
	local n = tonumber( value ) or lastNumber( name, value )
	host.cl.rfsRecipeViewerScroll = math.floor( n or 0 )
	refreshPage( host )
end

function RfsRecipeViewerGui.scrollBy( host, delta )
	host = host or _G.g_rfsGame
	if not host or not host.cl then
		return
	end
	local d = tonumber( delta ) or 0
	if d == 0 then
		return
	end
	host.cl.rfsRecipeViewerScroll = ( host.cl.rfsRecipeViewerScroll or 0 ) + d
	refreshPage( host )
end

function RfsRecipeViewerGui.wheel( host, name, scrollValue )
	host = host or _G.g_rfsGame
	if not host or not host.cl then
		return
	end
	local delta = tonumber( scrollValue ) or lastNumber( name, scrollValue ) or 0
	if delta == 0 then
		return
	end
	RfsRecipeViewerGui.scrollBy( host, delta < 0 and 1 or -1 )
end

function RfsRecipeViewerGui.pair( host )
	host = host or _G.g_rfsGame
	local shapeId
	pcall( function()
		if type( RfsHandheldLcd ) == "table" and RfsHandheldLcd.pairLookingAtStation then
			shapeId = RfsHandheldLcd.pairLookingAtStation()
		end
	end )
	if host and host.network then
		host.network:sendToServer( "sv_rfs_craftPair", { shapeId = shapeId } )
	end
end

function RfsRecipeViewerGui.send( host )
	host = host or _G.g_rfsGame
	if not host or not host.network then
		return
	end
	if not canSend( host ) then
		pcall( function()
			if isPaired( host ) then
				sm.gui.chatMessage( "[RFS] Out of wireless range — walk closer or PAIR again at the station" )
			else
				sm.gui.chatMessage( "[RFS] PAIR a Crafting Station first (look at it with the tablet and press U, or click PAIR)" )
			end
		end )
		return
	end
	host.network:sendToServer( "sv_rfs_craftSend", {} )
end

function RfsRecipeViewerGui.addQueue( host )
	host = host or _G.g_rfsGame
	if not host or not host.cl or not host.network then
		return
	end
	local id = host.cl.rfsRecipeViewerSelected
	if not id then
		pcall( function()
			sm.gui.chatMessage( "[RFS] Select a recipe, then ADD TO REMOTE QUEUE" )
		end )
		return
	end
	local qty = math.max( 1, math.floor( tonumber( host.cl.rfsRecipeViewerQty ) or 1 ) )
	host.network:sendToServer( "sv_rfs_craftQueueAdd", { itemId = id, qty = qty } )
end

function RfsRecipeViewerGui.setPrio( host, prio )
	host = host or _G.g_rfsGame
	if not host or not host.network then
		return
	end
	host.network:sendToServer( "sv_rfs_craftPrio", { prio = prio } )
end

function RfsRecipeViewerGui.setCategory( host, category )
	host = host or _G.g_rfsGame
	if not host or not host.cl then
		return
	end
	local ok = false
	for _, cat in ipairs( CAT_BUTTONS ) do
		if cat.id == category then
			ok = true
			break
		end
	end
	host.cl.rfsRecipeViewerCategory = ok and category or CAT_ALL
	host.cl.rfsRecipeViewerScroll = 0
	refreshPage( host )
end

function RfsRecipeViewerGui.setTab( host, tab )
	host = host or _G.g_rfsGame
	if host and host.cl then
		refreshTabs( host )
	end
end

function RfsRecipeViewerGui.pick( host, buttonName )
	host = host or _G.g_rfsGame
	if not host or not host.cl then
		return
	end
	local idx = tonumber( string.match( tostring( buttonName or "" ), "Cell(%d+)" ) )
	if idx == nil then
		return
	end
	local list = host.cl.rfsRecipeViewerFiltered or filteredList( host )
	local row = list[( host.cl.rfsRecipeViewerScroll or 0 ) * COLS + idx + 1]
	if not row or not row.itemId then
		return
	end
	host.cl.rfsRecipeViewerSelected = row.itemId
	refreshPage( host )
end

function RfsRecipeViewerGui.plus( host )
	host = host or _G.g_rfsGame
	if not host or not host.cl then
		return
	end
	host.cl.rfsRecipeViewerQty = math.min( 99, ( tonumber( host.cl.rfsRecipeViewerQty ) or 1 ) + 1 )
	refreshSelected( host )
end

function RfsRecipeViewerGui.minus( host )
	host = host or _G.g_rfsGame
	if not host or not host.cl then
		return
	end
	host.cl.rfsRecipeViewerQty = math.max( 1, ( tonumber( host.cl.rfsRecipeViewerQty ) or 1 ) - 1 )
	refreshSelected( host )
end

function RfsRecipeViewerGui.cancelRow( host, buttonName )
	host = host or _G.g_rfsGame
	if not host or not host.network then
		return
	end
	local idx = tonumber( string.match( tostring( buttonName or "" ), "QCancel(%d+)" ) )
	if idx == nil then
		return
	end
	local row = queueList( host )[idx + 1]
	if not row or not row.itemId then
		return
	end
	host.network:sendToServer( "sv_rfs_craftQueueSet", { itemId = row.itemId, qty = 0 } )
end

function RfsRecipeViewerGui.clear( host )
	host = host or _G.g_rfsGame
	if host and host.network then
		host.network:sendToServer( "sv_rfs_craftQueueClear", {} )
	end
	if host and host.cl then
		host.cl.rfsRecipeViewerQueueSnap = { crafts = {} }
		refreshQueue( host )
	end
end

print( "[RFS] RfsRecipeViewerGui loaded (combined tablet)" )
