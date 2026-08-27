-- RfsRecipeViewerGui.lua — VOLATILE craft planner for Recipe Viewer tool.
-- QUEUE tab: dense craftbot-style icon grid, qty DEC/INC.
-- RECIPES tab: materials + craft time for the selected unlocked item.
-- Must be opened via Game.client_onUpdate deferral so callbacks bind to Game.

RfsRecipeViewerGui = RfsRecipeViewerGui or {}

local LAYOUT = "$CONTENT_DATA/Gui/Layouts/Rfs_RecipeViewer.layout"
local PAGE = 50
local TAB_QUEUE = "queue"
local TAB_RECIPES = "recipes"
local CAT_ALL = "all"
local CAT_BUTTONS = {
	{ id = CAT_ALL, widget = "CatAll", label = "ALL" },
	{ id = "tool", widget = "CatTool", label = "TOOLS" },
	{ id = "block", widget = "CatBlock", label = "BLOCKS" },
	{ id = "interactive", widget = "CatInteractive", label = "INTERACTIVE" },
	{ id = "part", widget = "CatPart", label = "PARTS" },
	{ id = "consumable", widget = "CatConsumable", label = "CONSUMABLE" },
}

local function closeGui( host )
	host.cl = host.cl or {}
	local gui = host.cl.rfsRecipeViewerGui
	host.cl.rfsRecipeViewerGui = nil
	if gui then
		pcall( function() gui:close() end )
	end
end

local function queueMapFromSnap( snap )
	local map = {}
	if type( snap ) == "table" and type( snap.crafts ) == "table" then
		for _, craft in ipairs( snap.crafts ) do
			if craft and craft.itemId then
				map[tostring( craft.itemId )] = math.max( 0, math.floor( tonumber( craft.qty ) or 0 ) )
			end
		end
	end
	return map
end

local function localQueueMap( host )
	host.cl = host.cl or {}
	if type( host.cl.rfsRecipeViewerQueue ) ~= "table" then
		host.cl.rfsRecipeViewerQueue = queueMapFromSnap( _G.g_rfsCraftQueueClientSnap )
	end
	return host.cl.rfsRecipeViewerQueue
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
	itemId = tostring( itemId or "" )
	local sets = g_craftingRecipeSets or {}
	for _, set in pairs( sets ) do
		if type( set ) == "table" and type( set.recipes ) == "table" and set.recipes[itemId] then
			return set.recipes[itemId]
		end
	end
	return nil
end

local function applyButtonLabels( gui )
	if not gui then
		return
	end
	pcall( function()
		gui:setText( "CloseButton", "X" )
		gui:setText( "TabQueue", "QUEUE" )
		gui:setText( "TabRecipes", "RECIPES" )
		gui:setText( "BtnPrev", "PREV" )
		gui:setText( "BtnNext", "NEXT" )
		gui:setText( "BtnClear", "CLEAR QUEUE" )
		gui:setText( "BtnMinus", "DEC" )
		gui:setText( "BtnPlus", "INC" )
		gui:setText( "QueueHint", "Unlocked Craftbot recipes. Filter like Craftbot. Click to queue." )
		gui:setText( "QueueFooter", "Queued crafts paint on the quest tracker (max 6 lines)." )
		gui:setText( "RecipeHint", "Materials and craft time for the selected unlocked Craftbot recipe." )
		gui:setText( "IngHeader", "MATERIALS" )
		for _, cat in ipairs( CAT_BUTTONS ) do
			gui:setText( cat.widget, cat.label )
		end
	end )
end

local function filteredList( host )
	local all = host.cl and host.cl.rfsRecipeViewerList or {}
	local cat = host.cl and host.cl.rfsRecipeViewerCategory or CAT_ALL
	if cat == CAT_ALL or cat == nil or cat == "" then
		return all
	end
	local out = {}
	for _, row in ipairs( all ) do
		local c = row.category
		if not c and type( RfsCraftQueue ) == "table" and RfsCraftQueue.itemCategory then
			c = RfsCraftQueue.itemCategory( row.itemId )
			row.category = c
		end
		if tostring( c or "part" ) == cat then
			out[#out + 1] = row
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
			gui:setText( cat.widget, cat.label )
		end )
	end
end

local function refreshTabs( host )
	local gui = host.cl and host.cl.rfsRecipeViewerGui
	if not gui then
		return
	end
	local tab = host.cl.rfsRecipeViewerTab or TAB_QUEUE
	local isQueue = tab == TAB_QUEUE
	pcall( function()
		gui:setVisible( "PanelQueue", isQueue )
		gui:setVisible( "PanelRecipes", not isQueue )
		gui:setButtonState( "TabQueue", isQueue )
		gui:setButtonState( "TabRecipes", not isQueue )
		gui:setText( "TabQueue", "QUEUE" )
		gui:setText( "TabRecipes", "RECIPES" )
	end )
end

local function refreshSelectedBar( host )
	local gui = host.cl and host.cl.rfsRecipeViewerGui
	if not gui then
		return
	end
	local selected = host.cl.rfsRecipeViewerSelected
	local qmap = localQueueMap( host )
	local qty = 0
	local name = "Select an item"
	if selected then
		qty = tonumber( qmap[selected] ) or 0
		local list = host.cl.rfsRecipeViewerList or {}
		for _, row in ipairs( list ) do
			if row.itemId == selected then
				name = tostring( row.name or selected )
				break
			end
		end
	end
	pcall( function()
		gui:setText( "SelectedName", name )
		gui:setText( "SelectedQty", tostring( qty ) )
		gui:setText( "BtnMinus", "DEC" )
		gui:setText( "BtnPlus", "INC" )
	end )
end

local function refreshRecipesTab( host )
	local gui = host.cl and host.cl.rfsRecipeViewerGui
	if not gui then
		return
	end
	local selected = host.cl.rfsRecipeViewerSelected
	if not selected then
		pcall( function()
			gui:setText( "RecipeName", "Select an item on QUEUE" )
			gui:setText( "RecipeTime", "" )
		end )
		setIcon( gui, "RecipeIcon", nil )
		for i = 0, 5 do
			setIcon( gui, "IngIcon" .. i, nil )
			pcall( function() gui:setText( "IngText" .. i, "" ) end )
		end
		return
	end
	local name = selected
	local list = host.cl.rfsRecipeViewerList or {}
	for _, row in ipairs( list ) do
		if row.itemId == selected then
			name = tostring( row.name or selected )
			break
		end
	end
	setIcon( gui, "RecipeIcon", selected )
	pcall( function() gui:setText( "RecipeName", name ) end )
	local recipe = findRecipe( selected )
	local craftTime = recipe and tonumber( recipe.craftTime ) or 0
	pcall( function()
		if craftTime > 0 and sm.gui.ticksToTimeString then
			gui:setText( "RecipeTime", "Craft time: " .. tostring( sm.gui.ticksToTimeString( craftTime * 40 ) ) )
		elseif craftTime > 0 then
			gui:setText( "RecipeTime", "Craft time ticks: " .. tostring( craftTime ) )
		else
			gui:setText( "RecipeTime", "" )
		end
	end )
	local ings = ( recipe and recipe.ingredientList ) or {}
	for i = 0, 5 do
		local ing = ings[i + 1]
		if ing then
			local iid = tostring( ing.itemId )
			local q = tonumber( ing.quantity ) or 1
			local iname = iid
			pcall( function()
				local u = sm.uuid.new( iid )
				local t = sm.shape.getShapeTitle( u )
				if type( t ) == "string" and t ~= "" and t ~= "not found" then
					iname = t
				end
			end )
			setIcon( gui, "IngIcon" .. i, iid )
			pcall( function()
				gui:setText( "IngText" .. i, string.format( "%d x %s", q, iname ) )
			end )
		else
			setIcon( gui, "IngIcon" .. i, nil )
			pcall( function() gui:setText( "IngText" .. i, "" ) end )
		end
	end
end

local function refreshPage( host )
	local gui = host.cl and host.cl.rfsRecipeViewerGui
	local list = filteredList( host )
	local page = host.cl and host.cl.rfsRecipeViewerPage or 0
	if not gui then
		return
	end
	host.cl.rfsRecipeViewerFiltered = list
	local maxPage = math.max( 0, math.ceil( #list / PAGE ) - 1 )
	if page > maxPage then
		page = maxPage
		host.cl.rfsRecipeViewerPage = page
	end
	local base = page * PAGE
	local qmap = localQueueMap( host )
	local selected = host.cl.rfsRecipeViewerSelected
	local totalAll = #( host.cl.rfsRecipeViewerList or {} )
	for i = 0, PAGE - 1 do
		local row = list[base + i + 1]
		local cell = "Cell" .. i
		local icon = "Icon" .. i
		local qtyW = "Qty" .. i
		if row then
			local q = tonumber( qmap[row.itemId] ) or 0
			local isSel = selected == row.itemId
			local queued = q > 0
			pcall( function()
				gui:setButtonState( cell, isSel or queued )
			end )
			setIcon( gui, icon, row.itemId )
			pcall( function()
				gui:setText( qtyW, q > 0 and tostring( q ) or "" )
				gui:setVisible( cell, true )
			end )
		else
			pcall( function()
				gui:setButtonState( cell, false )
				gui:setText( qtyW, "" )
				gui:setVisible( cell, false )
			end )
		end
	end
	local cat = host.cl.rfsRecipeViewerCategory or CAT_ALL
	local catLabel = string.upper( tostring( cat ) )
	pcall( function()
		gui:setText( "PageLabel", string.format(
			"Page %d / %d  (%d in %s / %d unlocked)",
			page + 1, maxPage + 1, #list, catLabel, totalAll
		) )
		gui:setText( "BtnPrev", "PREV" )
		gui:setText( "BtnNext", "NEXT" )
		gui:setText( "BtnClear", "CLEAR QUEUE" )
		gui:setText( "CloseButton", "X" )
	end )
	refreshSelectedBar( host )
	refreshRecipesTab( host )
	refreshTabs( host )
	refreshCategoryTabs( host )
end

local function sendSet( host, itemId, qty )
	if not host or not host.network or not itemId then
		return
	end
	qty = math.max( 0, math.floor( tonumber( qty ) or 0 ) )
	local qmap = localQueueMap( host )
	qmap[itemId] = qty
	if qty <= 0 then
		qmap[itemId] = nil
	end
	host.network:sendToServer( "sv_rfs_craftQueueSet", { itemId = itemId, qty = qty } )
	refreshPage( host )
end

function RfsRecipeViewerGui.open( host, opts )
	opts = opts or {}
	host = host or _G.g_rfsGame
	if not host then
		return
	end
	host.cl = host.cl or {}
	closeGui( host )
	local list = {}
	if type( RfsCraftQueue ) == "table" and RfsCraftQueue.listKnownRecipes then
		list = RfsCraftQueue.listKnownRecipes() or {}
	end
	host.cl.rfsRecipeViewerList = list
	host.cl.rfsRecipeViewerPage = 0
	host.cl.rfsRecipeViewerTab = TAB_QUEUE
	host.cl.rfsRecipeViewerCategory = CAT_ALL
	host.cl.rfsRecipeViewerSelected = nil
	host.cl.rfsRecipeViewerQueue = queueMapFromSnap( _G.g_rfsCraftQueueClientSnap )
	-- Match BeaconOrders: second arg true so interactive layout binds correctly.
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
		sm.gui.chatMessage( "[RFS] Recipe Viewer menu failed" )
		return
	end
	host.cl.rfsRecipeViewerGui = gui
	pcall( function()
		gui:setButtonCallback( "CloseButton", "cl_rfs_recipeViewerClose" )
		gui:setButtonCallback( "BtnPrev", "cl_rfs_recipeViewerPrev" )
		gui:setButtonCallback( "BtnNext", "cl_rfs_recipeViewerNext" )
		gui:setButtonCallback( "BtnClear", "cl_rfs_recipeViewerClear" )
		gui:setButtonCallback( "BtnPlus", "cl_rfs_recipeViewerPlus" )
		gui:setButtonCallback( "BtnMinus", "cl_rfs_recipeViewerMinus" )
		gui:setButtonCallback( "TabQueue", "cl_rfs_recipeViewerTabQueue" )
		gui:setButtonCallback( "TabRecipes", "cl_rfs_recipeViewerTabRecipes" )
		gui:setButtonCallback( "CatAll", "cl_rfs_recipeViewerCatAll" )
		gui:setButtonCallback( "CatTool", "cl_rfs_recipeViewerCatTool" )
		gui:setButtonCallback( "CatBlock", "cl_rfs_recipeViewerCatBlock" )
		gui:setButtonCallback( "CatInteractive", "cl_rfs_recipeViewerCatInteractive" )
		gui:setButtonCallback( "CatPart", "cl_rfs_recipeViewerCatPart" )
		gui:setButtonCallback( "CatConsumable", "cl_rfs_recipeViewerCatConsumable" )
		gui:setOnCloseCallback( "cl_rfs_recipeViewerClosed" )
		for i = 0, PAGE - 1 do
			gui:setButtonCallback( "Cell" .. i, "cl_rfs_recipeViewerPick" )
		end
		applyButtonLabels( gui )
		gui:open()
	end )
	refreshPage( host )
	pcall( function()
		sm.gui.chatMessage( string.format( "[RFS] Recipe Viewer: %d unlocked Craftbot recipes", #list ) )
	end )
end

function RfsRecipeViewerGui.close( host )
	closeGui( host or _G.g_rfsGame )
end

function RfsRecipeViewerGui.onQueueSync( host, snap )
	host = host or _G.g_rfsGame
	if not host or not host.cl or not host.cl.rfsRecipeViewerGui then
		return
	end
	host.cl.rfsRecipeViewerQueue = queueMapFromSnap( snap )
	refreshPage( host )
end

function RfsRecipeViewerGui.prev( host )
	host = host or _G.g_rfsGame
	if not host or not host.cl then
		return
	end
	host.cl.rfsRecipeViewerPage = math.max( 0, ( host.cl.rfsRecipeViewerPage or 0 ) - 1 )
	refreshPage( host )
end

function RfsRecipeViewerGui.next( host )
	host = host or _G.g_rfsGame
	if not host or not host.cl then
		return
	end
	local list = filteredList( host )
	local maxPage = math.max( 0, math.ceil( #list / PAGE ) - 1 )
	host.cl.rfsRecipeViewerPage = math.min( maxPage, ( host.cl.rfsRecipeViewerPage or 0 ) + 1 )
	refreshPage( host )
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
	host.cl.rfsRecipeViewerPage = 0
	host.cl.rfsRecipeViewerTab = TAB_QUEUE
	refreshPage( host )
end

function RfsRecipeViewerGui.setTab( host, tab )
	host = host or _G.g_rfsGame
	if not host or not host.cl then
		return
	end
	host.cl.rfsRecipeViewerTab = tab == TAB_RECIPES and TAB_RECIPES or TAB_QUEUE
	refreshTabs( host )
	if host.cl.rfsRecipeViewerTab == TAB_RECIPES then
		refreshRecipesTab( host )
	else
		refreshPage( host )
	end
end

function RfsRecipeViewerGui.pick( host, buttonName )
	host = host or _G.g_rfsGame
	if not host or not host.cl or not host.network then
		return
	end
	local idx = tonumber( string.match( tostring( buttonName or "" ), "Cell(%d+)" ) )
	if idx == nil then
		return
	end
	local list = host.cl.rfsRecipeViewerFiltered or filteredList( host )
	local page = host.cl.rfsRecipeViewerPage or 0
	local row = list[page * PAGE + idx + 1]
	if not row or not row.itemId then
		return
	end
	local id = row.itemId
	host.cl.rfsRecipeViewerSelected = id
	local qmap = localQueueMap( host )
	local cur = tonumber( qmap[id] ) or 0
	if cur <= 0 then
		sendSet( host, id, 1 )
	else
		refreshPage( host )
	end
end

function RfsRecipeViewerGui.plus( host )
	host = host or _G.g_rfsGame
	if not host or not host.cl then
		return
	end
	local id = host.cl.rfsRecipeViewerSelected
	if not id then
		return
	end
	local qmap = localQueueMap( host )
	local cur = tonumber( qmap[id] ) or 0
	sendSet( host, id, cur + 1 )
end

function RfsRecipeViewerGui.minus( host )
	host = host or _G.g_rfsGame
	if not host or not host.cl then
		return
	end
	local id = host.cl.rfsRecipeViewerSelected
	if not id then
		return
	end
	local qmap = localQueueMap( host )
	local cur = tonumber( qmap[id] ) or 0
	sendSet( host, id, math.max( 0, cur - 1 ) )
end

function RfsRecipeViewerGui.clear( host )
	host = host or _G.g_rfsGame
	if host and host.network then
		host.network:sendToServer( "sv_rfs_craftQueueClear", {} )
	end
	if host and host.cl then
		host.cl.rfsRecipeViewerQueue = {}
		refreshPage( host )
	end
end

print( "[RFS] RfsRecipeViewerGui loaded" )
