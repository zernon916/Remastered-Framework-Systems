-- RfsCraftStationGui.lua — Crafting Station menu matching the CRAFT/UPGRADES mockup.
-- Tabs, categories, 7x4 learned-craft grid, active queue with cancel, recipe-viewer
-- slots, craft speed, ingredients, typed qty, ADD TO QUEUE + RECYCLE button.

RfsCraftStationGui = RfsCraftStationGui or {}

local LAYOUT = "$CONTENT_DATA/Gui/menu/layouts/Rfs_CraftStation.layout"
local PAGE = 28
local COLS = 7
local ROWS = 4
local QUEUE_ROWS = 4
local MAX_ORDER = 999
local TAB_CRAFT = "craft"
local TAB_UPGRADE = "upgrade"
local TAB_RECYCLE = "recycle"
local CAT_ALL = "all"
local CAT_BUTTONS = {
	{ id = CAT_ALL, widget = "CatAll" },
	{ id = "tool", widget = "CatTool" },
	{ id = "block", widget = "CatBlock" },
	{ id = "interactive", widget = "CatInteractive" },
	{ id = "part", widget = "CatPart" },
	{ id = "consumable", widget = "CatConsumable" },
}
local WIDGET_IDS = {
	SearchEdit = true,
	QtyEdit = true,
	ScrollBar = true,
	QueueScrollBar = true,
	MainPanel = true,
	Root = true,
	PanelGrid = true,
	PanelQueue = true,
	PanelBottom = true,
	PanelCats = true,
	ArtUpgrade = true,
	BgPanel = true,
	SpeedBar = true,
}

local KIT_PREFIXES = {
	"$CONTENT_DATA/Gui/menu/images/craftstation/",
	"$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247/Gui/menu/images/craftstation/",
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

local function setWirelessArt( gui, online )
	if not gui then
		return
	end
	setKitImage( gui, "ArtWireless", "status_wireless_online.png" )
	setKitImage( gui, "ArtWirelessOff", "status_wireless_offline.png" )
	pcall( function()
		gui:setVisible( "ArtWireless", online == true )
		gui:setVisible( "ArtWirelessOff", online ~= true )
		gui:setVisible( "StatusLine", false )
	end )
end

local function sliderValue( ... )
	for i = 1, select( "#", ... ) do
		local v = select( i, ... )
		if type( v ) == "number" then
			return v
		end
	end
	return 0
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

local function searchTextFromArgs( ... )
	local text
	for i = 1, select( "#", ... ) do
		local v = select( i, ... )
		if type( v ) == "string" and v ~= "" and not WIDGET_IDS[v] then
			text = v
		end
	end
	return text
end

local function clampQty( n )
	n = math.floor( tonumber( n ) or 1 )
	if n < 1 then
		n = 1
	elseif n > MAX_ORDER then
		n = MAX_ORDER
	end
	return n
end

local function bindOne( gui, method, widget, cb )
	pcall( function()
		gui[method]( gui, widget, cb )
	end )
end

local function bindStation( gui )
	if not gui then
		return
	end
	bindOne( gui, "setButtonCallback", "CloseButton", "cl_rfs_cs_close" )
	bindOne( gui, "setButtonCallback", "TabCraft", "cl_rfs_cs_tabCraft" )
	bindOne( gui, "setButtonCallback", "TabRecycle", "cl_rfs_cs_tabRecycle" )
	bindOne( gui, "setButtonCallback", "TabUpgrade", "cl_rfs_cs_tabUpgrade" )
	bindOne( gui, "setSliderCallback", "ScrollBar", "cl_rfs_cs_scroll" )
	bindOne( gui, "setSliderCallback", "QueueScrollBar", "cl_rfs_cs_queueScroll" )
	bindOne( gui, "setSliderCallback", "SpeedBar", "cl_rfs_cs_speed" )
	bindOne( gui, "setMouseWheelCallback", "ScrollBar", "cl_rfs_cs_wheel" )
	bindOne( gui, "setMouseWheelCallback", "MainPanel", "cl_rfs_cs_wheel" )
	bindOne( gui, "setMouseWheelCallback", "PanelGrid", "cl_rfs_cs_wheel" )
	bindOne( gui, "setMouseWheelCallback", "ArtGrid", "cl_rfs_cs_wheel" )
	bindOne( gui, "setMouseWheelCallback", "QueueScrollBar", "cl_rfs_cs_queueWheel" )
	bindOne( gui, "setMouseWheelCallback", "PanelQueue", "cl_rfs_cs_queueWheel" )
	bindOne( gui, "setTextChangedCallback", "SearchEdit", "cl_rfs_cs_search" )
	bindOne( gui, "setTextAcceptedCallback", "SearchEdit", "cl_rfs_cs_search" )
	bindOne( gui, "setTextChangedCallback", "QtyEdit", "cl_rfs_cs_qty" )
	bindOne( gui, "setTextAcceptedCallback", "QtyEdit", "cl_rfs_cs_qty" )
	bindOne( gui, "setButtonCallback", "BtnPlus", "cl_rfs_cs_plus" )
	bindOne( gui, "setButtonCallback", "BtnMinus", "cl_rfs_cs_minus" )
	bindOne( gui, "setButtonCallback", "BtnCraft", "cl_rfs_cs_craft" )
	bindOne( gui, "setButtonCallback", "BtnUpgrade", "cl_rfs_cs_upgrade" )
	bindOne( gui, "setButtonCallback", "CatAll", "cl_rfs_cs_catAll" )
	bindOne( gui, "setButtonCallback", "CatTool", "cl_rfs_cs_catTool" )
	bindOne( gui, "setButtonCallback", "CatBlock", "cl_rfs_cs_catBlock" )
	bindOne( gui, "setButtonCallback", "CatInteractive", "cl_rfs_cs_catInteractive" )
	bindOne( gui, "setButtonCallback", "CatPart", "cl_rfs_cs_catPart" )
	bindOne( gui, "setButtonCallback", "CatConsumable", "cl_rfs_cs_catConsumable" )
	pcall( function()
		gui:setOnCloseCallback( "cl_rfs_cs_closed" )
	end )
	for i = 0, PAGE - 1 do
		bindOne( gui, "setButtonCallback", "Cell" .. i, "cl_rfs_cs_pick" )
		bindOne( gui, "setMouseWheelCallback", "Cell" .. i, "cl_rfs_cs_wheel" )
		bindOne( gui, "setMouseWheelCallback", "Icon" .. i, "cl_rfs_cs_wheel" )
	end
	for i = 0, 4 do
		bindOne( gui, "setButtonCallback", "UpgSlot" .. i, "cl_rfs_cs_pickUpgrade" )
	end
	for i = 0, QUEUE_ROWS - 1 do
		bindOne( gui, "setButtonCallback", "QCancel" .. i, "cl_rfs_cs_cancel" )
	end
	for i = 0, 3 do
		bindOne( gui, "setButtonCallback", "ViewSlot" .. i, "cl_rfs_cs_viewSlot" )
	end
end

local function activeStation()
	local host = _G.g_rfsGame
	local st = host and host.cl and host.cl.rfsCraftStationPart
	if st then
		return st
	end
	return _G.g_rfsCraftStationGuiHost
end

local function closeGui( station )
	station.cl = station.cl or {}
	local gui = station.cl.csGui
	station.cl.csGui = nil
	if gui then
		pcall( function() gui:close() end )
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
			gui:setVisible( widget, true )
			gui:setImage( widget, uuidStr )
		end )
	end
end

local function itemName( uuidStr )
	local name = tostring( uuidStr or "" )
	pcall( function()
		name = sm.shape.getShapeTitle( sm.uuid.new( uuidStr ) )
	end )
	pcall( function()
		if name == "" or name == "not found" then
			name = sm.item.getDisplayName( sm.uuid.new( uuidStr ) )
		end
	end )
	return tostring( name or uuidStr )
end

local function filteredList( station )
	station.cl = station.cl or {}
	if type( station.cl.csList ) ~= "table" then
		local list = {}
		pcall( function()
			if type( RfsCraftQueue ) == "table" then
				local seen = {}
				local learned = station.cl.csLearned
				if type( RfsCraftQueue.listKnownRecipes ) == "function" then
					pcall( function()
						learned = RfsCraftQueue.listKnownRecipes( station.cl.csLearned )
					end )
				end
				if type( learned ) == "table" then
					local asList = learned[1] ~= nil
					if asList then
						for _, row in ipairs( learned ) do
							local id = type( row ) == "table" and ( row.itemId or row.uuid ) or row
							id = id and tostring( id ) or nil
							if id and not seen[id] then
								local recipe = RfsCraftQueue.findRecipe and RfsCraftQueue.findRecipe( id ) or row.recipe
								if recipe then
									seen[id] = true
									list[#list + 1] = { itemId = id, name = itemName( id ), recipe = recipe, category = RfsCraftQueue.itemCategory and RfsCraftQueue.itemCategory( id ) or "part" }
								end
							end
						end
					else
						for id, known in pairs( learned ) do
							local recipe = known and RfsCraftQueue.findRecipe and RfsCraftQueue.findRecipe( id ) or nil
							if recipe and not seen[id] then
								seen[id] = true
								list[#list + 1] = { itemId = id, name = itemName( id ), recipe = recipe, category = RfsCraftQueue.itemCategory and RfsCraftQueue.itemCategory( id ) or "part" }
							end
						end
					end
				end
				table.sort( list, function( a, b ) return string.lower( a.name ) < string.lower( b.name ) end )
			end
		end )
		station.cl.csList = list
	end
	local cat = station.cl.csCategory or CAT_ALL
	local q = string.lower( tostring( station.cl.csSearch or "" ) )
	local out = {}
	for _, row in ipairs( station.cl.csList ) do
		if row and row.itemId then
			local itemCat = row.category or "part"
			pcall( function()
				if not row.category then
					itemCat = RfsCraftQueue.itemCategory( row.itemId )
					row.category = itemCat
				end
			end )
			if cat == CAT_ALL or itemCat == cat then
				if q == "" then
					out[#out + 1] = row
				else
					local name = string.lower( tostring( row.name or "" ) )
					if name == "" then
						name = string.lower( itemName( row.itemId ) )
					end
					if string.find( name, q, 1, true ) or string.find( string.lower( tostring( row.itemId ) ), q, 1, true ) then
						out[#out + 1] = row
					end
				end
			end
		end
	end
	return out
end

local function selectedRecipe( station )
	station.cl = station.cl or {}
	local id = station.cl.csSelected
	if not id then
		return nil
	end
	for _, row in ipairs( filteredList( station ) ) do
		if row and tostring( row.itemId ) == tostring( id ) then
			return row
		end
	end
	local r
	pcall( function() r = RfsCraftQueue.findRecipe( id ) end )
	if type( r ) == "table" then
		return { itemId = id, recipe = r }
	end
	return nil
end

local function groupedQueue( crafts, kind )
	local groups = {}
	for i, entry in ipairs( crafts or {} ) do
		if entry and entry.itemId then
			local remaining = math.max( 1, math.floor( tonumber( entry.count ) or 1 ) )
			local total = math.max( remaining, math.floor( tonumber( entry.total or entry.batchTotal ) or remaining ) )
			groups[#groups + 1] = {
				kind = kind,
				itemId = tostring( entry.itemId ),
				batchId = entry.batchId,
				batchTotal = total,
				startIndex = i,
				lastIndex = i,
				count = remaining,
				time = tonumber( entry.time ) or -1,
				craftTime = tonumber( entry.craftTime ) or 1,
				waiting = entry.waiting == true,
			}
		end
	end
	return groups
end

local function craftableFromAvailability( recipe, availability )
	availability = availability or {}
	local n
	for _, ing in ipairs( recipe and recipe.ingredientList or {} ) do
		local need = tonumber( ing.quantity ) or 1
		if need <= 0 then
			return 0
		end
		local have = tonumber( availability[tostring( ing.itemId )] ) or 0
		local can = math.floor( have / need )
		if n == nil or can < n then
			n = can
		end
	end
	return math.max( 0, tonumber( n ) or 0 )
end

local function refreshTabs( station )
	local gui = station.cl and station.cl.csGui
	if not gui then
		return
	end
	local tab = station.cl.csTab or TAB_CRAFT
	if tab == TAB_RECYCLE then
		tab = TAB_CRAFT
		station.cl.csTab = TAB_CRAFT
	end
	local work = tab ~= TAB_UPGRADE
	local craft = tab == TAB_CRAFT
	pcall( function()
		gui:setButtonState( "TabCraft", craft )
		gui:setButtonState( "TabRecycle", false )
		gui:setButtonState( "TabUpgrade", not work )
		gui:setVisible( "PanelCats", work )
		gui:setVisible( "PanelGrid", work )
		gui:setVisible( "PanelQueue", work )
		gui:setVisible( "PanelBottom", work )
		gui:setVisible( "ArtUpgrade", not work )
		gui:setVisible( "ArtUpgBg", not work )
		gui:setVisible( "ArtTitle", work )
		gui:setVisible( "Title", false )
		gui:setVisible( "ScrollBar", work )
		gui:setVisible( "BtnUpgrade", false )
		for i = 0, 4 do
			gui:setVisible( "UpgSlot" .. i, not work )
		end
		gui:setVisible( "SearchEdit", work )
		pcall( function()
			gui:setVisible( "ArtSearch", work )
		end )
		gui:setText( "TabCraft", "" )
		gui:setText( "TabRecycle", "" )
		gui:setText( "TabUpgrade", "" )
		setKitImage( gui, "ArtTabCraft", craft and "tab_craft_on.png" or "tab_craft_off.png" )
		setKitImage( gui, "ArtTabRecycle", "tab_recycle_steel.png" )
		setKitImage( gui, "ArtTabUpgrade", work and "tab_upgrades_off.png" or "tab_upgrades_on.png" )
		pcall( function()
			gui:setVisible( "ArtCats", work )
			gui:setVisible( "ArtGrid", work )
			gui:setVisible( "ArtQueue", work )
			gui:setVisible( "ArtSearch", work )
			gui:setVisible( "ArtTabRecycle", work )
			gui:setVisible( "TabRecycle", work )
		end )
	end )
end

local function refreshGrid( station )
	local gui = station.cl and station.cl.csGui
	if not gui then
		return
	end
	local list = filteredList( station )
	local maxScroll = math.max( 0, math.ceil( #list / COLS ) - ROWS )
	local scroll = math.max( 0, math.min( maxScroll, math.floor( tonumber( station.cl.csScroll ) or 0 ) ) )
	station.cl.csScroll = scroll
	pcall( function()
		if not station.cl.csIgnoreSlider then
			station.cl.csIgnoreSlider = true
			gui:setSliderData( "ScrollBar", math.max( 1, maxScroll + 1 ), scroll )
			station.cl.csIgnoreSlider = nil
		end
	end )
	for i = 0, PAGE - 1 do
		local row = list[scroll * COLS + i + 1]
		if row and row.itemId then
			setIcon( gui, "Icon" .. i, tostring( row.itemId ) )
			pcall( function()
				gui:setVisible( "Cell" .. i, true )
				gui:setVisible( "ArtCell" .. i, true )
				gui:setVisible( "Icon" .. i, true )
				gui:setButtonState( "Cell" .. i, tostring( row.itemId ) == tostring( station.cl.csSelected ) )
			end )
		else
			pcall( function()
				gui:setVisible( "Cell" .. i, false )
				gui:setVisible( "ArtCell" .. i, false )
			end )
		end
	end
	local cat = station.cl.csCategory or CAT_ALL
	local catArt = {
		all = { on = "pill_on.png", off = "pill_blank_off.png" },
		tool = { on = "pill_tools_on.png", off = "pill_tools_off.png" },
		block = { on = "pill_blocks_on.png", off = "pill_blocks_off.png" },
		interactive = { on = "pill_interactive_on.png", off = "pill_interactive_off.png" },
		part = { on = "pill_parts_on.png", off = "pill_parts_off.png" },
		consumable = { on = "pill_consumable_on.png", off = "pill_consumable_off.png" },
	}
	for _, c in ipairs( CAT_BUTTONS ) do
		local art = catArt[c.id] or catArt.all
		local on = c.id == cat
		pcall( function()
			gui:setButtonState( c.widget, on )
			setKitImage( gui, "Art" .. c.widget, on and art.on or art.off )
		end )
	end
end

local function refreshDetail( station )
	local gui = station.cl and station.cl.csGui
	if not gui then
		return
	end
	local row = selectedRecipe( station )
	if not row then
		pcall( function()
			gui:setText( "SelectedName", "Select a recipe" )
			gui:setVisible( "SelectedIcon", false )
			gui:setText( "BtnCraft", "" )
		end )
		for i = 0, 3 do
			pcall( function()
				gui:setVisible( "IngIcon" .. i, false )
				gui:setText( "IngHave" .. i, "" )
			end )
		end
		return
	end
	setIcon( gui, "SelectedIcon", tostring( row.itemId ) )
	local recipe = row.recipe or {}
	pcall( function()
		if not row.recipe then
			recipe = RfsCraftQueue.findRecipe( row.itemId ) or {}
		end
	end )
	local haveItem = tonumber( station.cl.csAvailability and station.cl.csAvailability[tostring( row.itemId )] ) or 0
	local canCraft = craftableFromAvailability( recipe, station.cl.csAvailability )
	pcall( function()
		gui:setText( "SelectedName", string.format( "%s\nRecycle %d / Craft %d", itemName( row.itemId ), haveItem, canCraft ) )
		gui:setText( "BtnCraft", "" )
	end )
	local ings = recipe.ingredientList or {}
	local qty = station.cl.csQty or 1
	for i = 0, 3 do
		local ing = ings[i + 1]
		if ing and ing.itemId then
			local need = ( tonumber( ing.quantity ) or 1 ) * qty
			local iid = tostring( ing.itemId )
			local have = tonumber( station.cl.csAvailability and station.cl.csAvailability[iid] ) or 0
			setIcon( gui, "IngIcon" .. i, tostring( ing.itemId ) )
			pcall( function()
				gui:setText( "IngHave" .. i, string.format( "%d/%d", have, need ) )
			end )
		else
			pcall( function()
				gui:setVisible( "IngIcon" .. i, false )
				gui:setText( "IngHave" .. i, "" )
			end )
		end
	end
end

local function refreshQtyBox( station )
	local gui = station.cl and station.cl.csGui
	if not gui or not station.cl.csSyncQty then
		return
	end
	station.cl.csSyncQty = nil
	pcall( function()
		gui:setText( "QtyEdit", tostring( station.cl.csQty or 1 ) )
	end )
end

local function applyUpgradeCards( gui, tier )
	if not gui then
		return
	end
	tier = math.max( 1, math.min( 5, tonumber( tier ) or 1 ) )
	setKitImage( gui, "ArtUpgBg", "upgrade_panel_bg.png" )
	setKitImage( gui, "ArtUpgHeader", "header_station_upgrades.png" )
	for i = 0, 3 do
		local n = i + 1
		local owned = ( tier >= 5 ) or ( i < ( tier - 1 ) )
		local nextUp = ( tier < 5 ) and ( i == ( tier - 1 ) )
		if owned then
			setKitImage( gui, "ArtUpgCard" .. i, "upgrade_card_" .. n .. "_gold.png" )
			setKitImage( gui, "ArtUpgDone" .. i, "upgraded_tag.png" )
			pcall( function()
				gui:setVisible( "ArtUpgBtn" .. i, false )
				gui:setVisible( "ArtUpgLock" .. i, false )
			end )
		elseif nextUp then
			setKitImage( gui, "ArtUpgCard" .. i, "upgrade_card_" .. n .. "_regular.png" )
			setKitImage( gui, "ArtUpgBtn" .. i, "btn_upgrade_on.png" )
			pcall( function()
				gui:setVisible( "ArtUpgDone" .. i, false )
				gui:setVisible( "ArtUpgLock" .. i, false )
			end )
		else
			setKitImage( gui, "ArtUpgCard" .. i, "upgrade_card_" .. n .. "_regular.png" )
			setKitImage( gui, "ArtUpgLock" .. i, "btn_locked.png" )
			pcall( function()
				gui:setVisible( "ArtUpgBtn" .. i, false )
				gui:setVisible( "ArtUpgDone" .. i, false )
			end )
		end
	end
end

local function refreshUpgrade( station )
	local gui = station.cl and station.cl.csGui
	if not gui then
		return
	end
	local tier = tonumber( station.cl.csTier ) or 1
	pcall( function()
		gui:setText( "TierTitle", string.format( "TIER %d / %d", tier, 5 ) )
		gui:setText( "BtnUpgrade", "" )
	end )
	applyUpgradeCards( gui, tier )
	setKitImage( gui, "ArtUpgFooter", "status_current_capacity.png" )
	setKitImage( gui, "ArtUpgTablets", "status_connected_tablets.png" )
	setKitImage( gui, "ArtUpgCraftSpeed", "status_craft_speed.png" )
	for _, hideName in ipairs( {
		"ArtUpgHex", "ArtUpgStats", "ArtUpgSide", "ArtUpgKit", "ArtBtnUpgrade",
		"ArtUpgSlot0", "ArtUpgSlot1", "ArtUpgSlot2", "ArtUpgSlot3", "ArtUpgSlot4",
		"TierTitle", "UpgNextTitle", "KitsLabel", "UpgKitIcon", "BtnUpgrade",
	} ) do
		pcall( function()
			gui:setVisible( hideName, false )
		end )
	end
	for i = 0, 3 do
		pcall( function()
			gui:setVisible( "ArtUpgCard" .. i, true )
			gui:setButtonState( "UpgSlot" .. i, ( tier >= 5 ) or ( i < ( tier - 1 ) ) )
			gui:setText( "UpgSlot" .. i, "" )
			gui:setVisible( "UpgSlot" .. i, true )
		end )
	end
	pcall( function()
		gui:setVisible( "UpgSlot4", false )
		gui:setVisible( "ArtUpgHeader", true )
		gui:setVisible( "ArtUpgFooter", true )
		gui:setVisible( "ArtUpgTablets", true )
		gui:setVisible( "ArtUpgCraftSpeed", true )
		gui:setVisible( "TabletsLabel", true )
		gui:setVisible( "UpgSpeedLabel", true )
	end )
	local pairN = 0
	pcall( function()
		local pairs = station.cl.csPairs
		if type( pairs ) == "table" then
			pairN = #pairs
		end
	end )
	local speed = tonumber( station.cl.csSpeed ) or 1
	pcall( function()
		gui:setText( "TabletsLabel", string.format( "%d / %d", pairN, 4 ) )
		gui:setText( "UpgSpeedLabel", string.format( "%d%%", math.floor( speed * 100 + 0.5 ) ) )
	end )
	local nextInfo
	pcall( function() nextInfo = RfsCraftStation.TIERS[tier + 1] end )
	if nextInfo then
		pcall( function()
			gui:setText( "UpgNextTitle", string.format( "TIER %d", tier + 1 ) )
		end )
	else
		pcall( function()
			gui:setText( "UpgNextTitle", "MAX TIER" )
		end )
	end
	pcall( function()
		gui:setVisible( "ArtBtnUpgrade", false )
		gui:setVisible( "UpgKitIcon", false )
		gui:setVisible( "ArtUpgBg", true )
	end )
end

local Q_BAR_STEPS = 10
local Q_COLOR_CRAFT = nil
local Q_COLOR_RECYCLE = nil
pcall( function()
	Q_COLOR_CRAFT = sm.color.new( 0.22, 0.86, 0.32 )
	Q_COLOR_RECYCLE = sm.color.new( 0.92, 0.22, 0.18 )
end )

local function setQueueBar( gui, i, frac, show, kind )
	frac = math.max( 0, math.min( 100, tonumber( frac ) or 0 ) )
	local step = 0
	if show and frac > 0 then
		step = math.max( 1, math.min( Q_BAR_STEPS, math.ceil( frac / ( 100 / Q_BAR_STEPS ) ) ) )
	end
	local fillFile = ( kind == "recycle" ) and "bar_fill_red.png" or "bar_fill_green.png"
	local knobFile = ( kind == "recycle" ) and "bar_knob_red.png" or "bar_knob_green.png"
	for s = 1, Q_BAR_STEPS do
		local on = s == step
		pcall( function()
			if on then
				setKitImage( gui, "ArtQFill" .. i .. "_" .. s, fillFile )
				setKitImage( gui, "ArtQKnob" .. i .. "_" .. s, knobFile )
			end
			gui:setVisible( "ArtQFill" .. i .. "_" .. s, on )
			gui:setVisible( "ArtQKnob" .. i .. "_" .. s, on )
		end )
	end
	pcall( function()
		gui:setVisible( "QBar" .. i, false )
	end )
end

local function refreshQueue( station )
	local gui = station.cl and station.cl.csGui
	if not gui then
		return
	end
	local crafts = station.cl.csCrafts or {}
	local recycles = station.cl.csRecycles or {}
	local slots = tonumber( station.cl.csSlots ) or 4
	local groups = groupedQueue( crafts, "craft" )
	for _, g in ipairs( groupedQueue( recycles, "recycle" ) ) do
		groups[#groups + 1] = g
	end
	station.cl.csQueueGroups = groups
	local used = #crafts + #recycles
	local queueSpan = math.max( slots, #groups )
	local maxQueueScroll = math.max( 0, queueSpan - QUEUE_ROWS )
	local queueScroll = math.max( 0, math.min( maxQueueScroll, math.floor( tonumber( station.cl.csQueueScroll ) or 0 ) ) )
	station.cl.csQueueScroll = queueScroll
	pcall( function()
		gui:setText( "QueueTitle", string.format( "ACTIVE QUEUE  %d/%d", used, slots ) )
		station.cl.csIgnoreQueueSlider = true
		gui:setSliderData( "QueueScrollBar", math.max( 1, maxQueueScroll + 1 ), queueScroll )
		gui:setVisible( "QueueScrollBar", maxQueueScroll > 0 )
		station.cl.csIgnoreQueueSlider = nil
	end )
	for i = 0, QUEUE_ROWS - 1 do
		local slotIndex = queueScroll + i + 1
		local owned = slotIndex <= slots
		local g = groups[slotIndex]
		if g then
			setIcon( gui, "QItem" .. i, g.itemId )
			local frac = 0
			if ( g.time or -1 ) >= 0 and ( g.craftTime or 0 ) > 0 then
				frac = math.max( 0, math.min( 100, math.floor( 100 * ( g.time / g.craftTime ) ) ) )
			end
			if g.waiting then
				frac = 0
			end
			pcall( function()
				gui:setVisible( "ArtQIcon" .. i, true )
				gui:setVisible( "ArtQTrack" .. i, true )
				gui:setVisible( "ArtQCancel" .. i, true )
				gui:setText( "QCount" .. i, tostring( math.max( 0, g.count or 0 ) ) )
				pcall( function()
					local col = g.kind == "recycle" and Q_COLOR_RECYCLE or Q_COLOR_CRAFT
					if col then
						gui:setColor( "QCount" .. i, col )
					end
				end )
				gui:setVisible( "QCount" .. i, true )
				gui:setVisible( "QItem" .. i, true )
				gui:setVisible( "QCancel" .. i, true )
			end )
			setQueueBar( gui, i, frac, true, g.kind )
		else
			pcall( function()
				gui:setVisible( "ArtQIcon" .. i, owned )
				gui:setVisible( "ArtQTrack" .. i, owned )
				gui:setVisible( "ArtQCancel" .. i, false )
				gui:setVisible( "QItem" .. i, false )
				gui:setText( "QCount" .. i, "" )
				gui:setVisible( "QCancel" .. i, false )
			end )
			setQueueBar( gui, i, 0, owned )
		end
	end
	local pairs = station.cl.csPairs or {}
	local filled = {}
	if type( pairs ) == "table" then
		for _, row in ipairs( pairs ) do
			local p = tonumber( row.prio ) or 0
			if p >= 1 and p <= 4 then
				filled[p] = row.online == true
			end
		end
		if #pairs > 0 and not next( filled ) then
			for i = 1, math.min( 4, #pairs ) do
				filled[i] = true
			end
		end
	end
	for i = 0, 3 do
		local n = i + 1
		local on = filled[n] == true
		pcall( function()
			gui:setButtonState( "ViewSlot" .. i, on )
			gui:setText( "ViewSlot" .. i, "" )
		end )
		setKitImage( gui, "ArtView" .. i, on and ( "num_" .. n .. "_on.png" ) or ( "num_" .. n .. "_off.png" ) )
	end
	local speed = tonumber( station.cl.csSpeed ) or 1
	local maxSpeed = tonumber( station.cl.csMaxSpeed ) or 1
	pcall( function()
		station.cl.csIgnoreSpeedSlider = true
		-- 0 = 100% at the left, 100 = 250% at the right. Snap in 25% steps.
		local pct = math.max( 0, math.min( 100, math.floor( ( speed - 1 ) / 1.5 * 100 + 0.5 ) ) )
		gui:setSliderData( "SpeedBar", 101, pct )
		station.cl.csIgnoreSpeedSlider = nil
		gui:setText( "SpeedLabel", station.cl.csSpeedUnlocked and string.format( "CRAFT SPEED  %d%%", math.floor( speed * 100 + 0.5 ) ) or "CRAFT SPEED  LOCKED" )
	end )
	setWirelessArt( gui, station.cl.wireless == true )
end

local function refresh( station )
	local gui = station.cl and station.cl.csGui
	if not gui then
		return
	end
	refreshTabs( station )
	setWirelessArt( station.cl.csGui, station.cl.wireless == true )
	if ( station.cl.csTab or TAB_CRAFT ) ~= TAB_UPGRADE then
		refreshGrid( station )
		refreshDetail( station )
		refreshQtyBox( station )
		refreshQueue( station )
	else
		refreshUpgrade( station )
	end
	bindStation( gui )
end

local function installGameCancel()
	local fn = function( self, buttonName )
		RfsCraftStationGui.cancel( buttonName )
	end
	if type( RecipeFrameworkSurvival ) == "table" then
		RecipeFrameworkSurvival.cl_rfs_cs_cancel = fn
	end
	local host = _G.g_rfsGame
	if host then
		host.cl_rfs_cs_cancel = fn
	end
end

local function applyBg( gui )
	-- Photo + kit art on ImageBoxes only. Buttons stay empty hit-targets on top.
	local bgPaths = {
		"$CONTENT_DATA/Gui/menu/images/rfs_craftstation_bg.png",
		"$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247/Gui/menu/images/rfs_craftstation_bg.png",
	}
	for _, path in ipairs( bgPaths ) do
		local okBg = pcall( function()
			gui:setImage( "BgPanel", path )
		end )
		if okBg then
			break
		end
	end
	setKitImage( gui, "ArtSearch", "search.png" )
	setKitImage( gui, "ArtTabCraft", "tab_craft_on.png" )
	setKitImage( gui, "ArtTabRecycle", "tab_recycle_steel.png" )
	setKitImage( gui, "ArtTabUpgrade", "tab_upgrades_off.png" )
	setKitImage( gui, "ArtTitle", "title_crafting_station.png" )
	setWirelessArt( gui, false )
	setKitImage( gui, "ArtClose", "btn_cancel.png" )
	applyUpgradeCards( gui, 1 )
	setKitImage( gui, "ArtUpgFooter", "status_current_capacity.png" )
	setKitImage( gui, "ArtUpgTablets", "status_connected_tablets.png" )
	setKitImage( gui, "ArtUpgCraftSpeed", "status_craft_speed.png" )
	pcall( function()
		gui:setVisible( "ArtTitle", true )
		gui:setVisible( "Title", false )
		gui:setVisible( "StatusLine", false )
	end )
	setKitImage( gui, "ArtMinus", "btn_minus.png" )
	setKitImage( gui, "ArtPlus", "btn_plus.png" )
	setKitImage( gui, "ArtBtnCraft", "btn_addqueue.png" )
	pcall( function()
		gui:setVisible( "ArtSpeed", false )
	end )
	setKitImage( gui, "ArtSelected", "slot_frame.png" )
	setKitImage( gui, "ArtBtnUpgrade", "btn_upgrade_on.png" )
	pcall( function()
		gui:setText( "BtnCraft", "" )
		gui:setText( "CloseButton", "" )
		gui:setText( "BtnMinus", "" )
		gui:setText( "BtnPlus", "" )
	end )
	for i = 0, PAGE - 1 do
		setKitImage( gui, "ArtCell" .. i, "slot_frame.png" )
	end
	for i = 0, QUEUE_ROWS - 1 do
		setKitImage( gui, "ArtQIcon" .. i, "slot_frame.png" )
		setKitImage( gui, "ArtQTrack" .. i, "bar_track.png" )
		setKitImage( gui, "ArtQCancel" .. i, "btn_cancel.png" )
		for s = 1, Q_BAR_STEPS do
			setKitImage( gui, "ArtQFill" .. i .. "_" .. s, "bar_fill_green.png" )
			setKitImage( gui, "ArtQKnob" .. i .. "_" .. s, "bar_knob_green.png" )
			pcall( function()
				gui:setVisible( "ArtQFill" .. i .. "_" .. s, false )
				gui:setVisible( "ArtQKnob" .. i .. "_" .. s, false )
			end )
		end
		pcall( function()
			gui:setVisible( "QBar" .. i, false )
		end )
	end
	for i = 0, 3 do
		setKitImage( gui, "ArtIng" .. i, "slot_frame.png" )
		setKitImage( gui, "ArtView" .. i, "num_" .. ( i + 1 ) .. "_off.png" )
	end
	setKitImage( gui, "ArtCatAll", "pill_on.png" )
	setKitImage( gui, "ArtCatTool", "pill_tools_off.png" )
	setKitImage( gui, "ArtCatBlock", "pill_blocks_off.png" )
	setKitImage( gui, "ArtCatInteractive", "pill_interactive_off.png" )
	setKitImage( gui, "ArtCatPart", "pill_parts_off.png" )
	setKitImage( gui, "ArtCatConsumable", "pill_consumable_off.png" )
	for i = 0, 4 do
		setKitImage( gui, "ArtUpgSlot" .. i, i == 0 and "slot_frame.png" or "btn_locked.png" )
	end
	pcall( function()
		gui:setVisible( "ArtUpgrade", false )
		gui:setVisible( "ArtUpgBg", false )
	end )
end

function RfsCraftStationGui.attach( station, gui )
	if not station or not station.cl or not gui then
		return
	end
	closeGui( station )
	station.cl.csPage = 0
	station.cl.csScroll = 0
	station.cl.csQueueScroll = 0
	station.cl.csSearch = ""
	station.cl.csTab = TAB_CRAFT
	station.cl.csCategory = CAT_ALL
	station.cl.csQty = 1
	station.cl.csSyncQty = true
	station.cl.csList = nil
	station.cl.csRecipeRevision = -1
	pcall( installGameCancel )
	local host = _G.g_rfsGame
	if host then
		host.cl = host.cl or {}
		host.cl.rfsCraftStationPart = station
	end
	_G.g_rfsCraftStationGuiHost = station
	station.cl.csGui = gui
	pcall( bindStation, gui )
	applyBg( gui )
	local opened = pcall( function()
		gui:open()
	end )
	if not opened then
		station.cl.csGui = nil
		sm.gui.chatMessage( "[RFS] Crafting Station menu failed to open" )
		return
	end
	pcall( bindStation, gui )
	applyBg( gui )
	pcall( refresh, station )
	pcall( RfsCraftStationGui.poll, station )
	pcall( bindStation, gui )
end

function RfsCraftStationGui.open( station )
	if not station or not station.cl then
		pcall( function()
			sm.gui.chatMessage( "[RFS] Crafting Station menu: no station" )
		end )
		return
	end
	if station.cl_openStationGui then
		station:cl_openStationGui()
		return
	end
	local ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT, true, {
		isHud = false,
		isInteractive = true,
		needsCursor = true,
	} )
	if not ok or not gui then
		ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT, true )
	end
	if not ok or not gui then
		sm.gui.chatMessage( "[RFS] Crafting Station menu failed to create" )
		return
	end
	RfsCraftStationGui.attach( station, gui )
end

function RfsCraftStationGui.close( station )
	closeGui( station )
end

function RfsCraftStationGui.refresh( station )
	if station and station.cl and station.cl.csGui then
		refresh( station )
	end
end

function RfsCraftStationGui.poll( station )
	if not station or not station.cl or not station.cl.csGui then return end
	station.cl.csPollTicks = ( station.cl.csPollTicks or 0 ) + 1
	local revision = 0
	pcall( function() revision = RecipeManager.Cl_GetUnlockedRevision() or 0 end )
	if revision ~= ( station.cl.csRecipeRevision or -1 ) or station.cl.csPollTicks >= 40 then
		station.cl.csRecipeRevision = revision
		station.cl.csPollTicks = 0
		station.network:sendToServer( "sv_n_requestStationState", {} )
	end
	if station.cl.csPollTicks % 10 == 0 then refresh( station ) end
end

function RfsCraftStationGui.closeActive()
	local st = activeStation()
	if st then
		RfsCraftStationGui.close( st )
	end
	local host = _G.g_rfsGame
	if host and host.cl then
		host.cl.rfsCraftStationPart = nil
	end
	_G.g_rfsCraftStationGuiHost = nil
end

function RfsCraftStationGui.tabCraft()
	local self = activeStation()
	if not self then
		return
	end
	self.cl = self.cl or {}
	self.cl.csTab = TAB_CRAFT
	refresh( self )
end

function RfsCraftStationGui.tabRecycle()
	RfsCraftStationGui.recycle()
end

local function pickSelectedId( self )
	pcall( function()
		local box = self.cl.csGui:getText( "QtyEdit" )
		local n = tonumber( tostring( box or "" ):match( "^%s*(%d+)%s*$" ) )
		if n and n >= 1 then
			self.cl.csQty = clampQty( n )
		end
	end )
	local id = self.cl.csSelected
	if not id or id == "" then
		local list = filteredList( self )
		local row = list[( ( self.cl.csScroll or 0 ) * COLS ) + 1]
		if row and row.itemId then
			id = tostring( row.itemId )
			self.cl.csSelected = id
		end
	end
	return id
end

function RfsCraftStationGui.recycle()
	local self = activeStation()
	if not self or not self.cl or not self.network then
		pcall( function()
			sm.gui.chatMessage( "[RFS] Recycle: no station" )
		end )
		return
	end
	if self.cl.csTab == TAB_UPGRADE then
		self.cl.csTab = TAB_CRAFT
		refresh( self )
	end
	local id = pickSelectedId( self )
	if not id or id == "" then
		pcall( function()
			sm.gui.chatMessage( "[RFS] Select an item, then Recycle" )
		end )
		return
	end
	self.network:sendToServer( "sv_n_recycleStation", { itemId = id, qty = self.cl.csQty or 1 } )
	refresh( self )
end

function RfsCraftStationGui.tabUpgrade()
	local self = activeStation()
	if not self then
		return
	end
	self.cl = self.cl or {}
	self.cl.csTab = TAB_UPGRADE
	refresh( self )
end

local function setCategory( category )
	local self = activeStation()
	if not self then
		return
	end
	self.cl = self.cl or {}
	self.cl.csCategory = category
	self.cl.csScroll = 0
	if self.cl.csTab == TAB_UPGRADE then
		self.cl.csTab = TAB_CRAFT
	end
	refresh( self )
end

function RfsCraftStationGui.catAll() setCategory( "all" ) end
function RfsCraftStationGui.catTool() setCategory( "tool" ) end
function RfsCraftStationGui.catBlock() setCategory( "block" ) end
function RfsCraftStationGui.catInteractive() setCategory( "interactive" ) end
function RfsCraftStationGui.catPart() setCategory( "part" ) end
function RfsCraftStationGui.catConsumable() setCategory( "consumable" ) end

function RfsCraftStationGui.search( ... )
	local self = activeStation()
	if not self then
		return
	end
	self.cl = self.cl or {}
	local text = searchTextFromArgs( ... )
	if text == nil then
		for i = 1, select( "#", ... ) do
			if select( i, ... ) == "" then
				text = ""
				break
			end
		end
	end
	if text == nil then
		pcall( function()
			local box = self.cl.csGui:getText( "SearchEdit" )
			if type( box ) == "string" and not WIDGET_IDS[box] then
				text = box
			end
		end )
	end
	self.cl.csSearch = tostring( text or "" )
	self.cl.csScroll = 0
	refresh( self )
end

function RfsCraftStationGui.qty( ... )
	local self = activeStation()
	if not self then
		return
	end
	self.cl = self.cl or {}
	local text = searchTextFromArgs( ... )
	if text == nil then
		pcall( function()
			text = self.cl.csGui:getText( "QtyEdit" )
		end )
	end
	local n = tonumber( tostring( text or "" ):match( "^%s*(%d+)%s*$" ) )
	if n and n >= 1 then
		self.cl.csQty = clampQty( n )
		refresh( self )
	end
end

function RfsCraftStationGui.scroll( ... )
	local self = activeStation()
	if not self or not self.cl or self.cl.csIgnoreSlider then
		return
	end
	self.cl.csScroll = math.floor( lastNumber( ... ) or 0 )
	refresh( self )
end

function RfsCraftStationGui.wheel( ... )
	local self = activeStation()
	if not self then
		return
	end
	self.cl = self.cl or {}
	local delta = lastNumber( ... ) or 0
	if delta == 0 then
		return
	end
	self.cl.csScroll = ( self.cl.csScroll or 0 ) + ( delta < 0 and 1 or -1 )
	refresh( self )
end

function RfsCraftStationGui.queueScroll( ... )
	local self = activeStation()
	if not self or not self.cl or self.cl.csIgnoreQueueSlider then return end
	self.cl.csQueueScroll = math.floor( lastNumber( ... ) or 0 )
	refresh( self )
end

function RfsCraftStationGui.queueWheel( ... )
	local self = activeStation()
	if not self then return end
	local delta = lastNumber( ... ) or 0
	if delta ~= 0 then
		self.cl.csQueueScroll = ( self.cl.csQueueScroll or 0 ) + ( delta < 0 and 1 or -1 )
		refresh( self )
	end
end

function RfsCraftStationGui.speed( ... )
	local self = activeStation()
	if not self or not self.cl or self.cl.csIgnoreSpeedSlider then return end
	if not self.cl.csSpeedUnlocked then refresh( self ); return end
	local pct = math.max( 0, math.min( 100, math.floor( sliderValue( ... ) + 0.5 ) ) )
	local speed = 1 + ( pct / 100 ) * 1.5
	local maxSpeed = tonumber( self.cl.csMaxSpeed ) or 1
	speed = math.max( 1, math.min( maxSpeed, speed ) )
	local step = math.max( 0, math.min( 6, math.floor( ( speed - 1 ) / 0.25 + 0.5 ) ) )
	self.network:sendToServer( "sv_n_setCraftSpeed", { step = step } )
end

function RfsCraftStationGui.viewSlot( buttonName )
	local self = activeStation()
	if not self then
		return
	end
	local idx = tonumber( string.match( tostring( buttonName or "" ), "ViewSlot(%d+)" ) )
	if idx == nil then
		return
	end
	self.cl = self.cl or {}
	self.cl.csTabletSlot = idx + 1
	refresh( self )
end

function RfsCraftStationGui.pick( buttonName, ... )
	local self = activeStation()
	if not self then
		return
	end
	self.cl = self.cl or {}
	local blob = tostring( buttonName or "" )
	for i = 1, select( "#", ... ) do
		blob = blob .. " " .. tostring( select( i, ... ) )
	end
	local idx = tonumber( string.match( blob, "Cell(%d+)" ) )
	if idx == nil then
		return
	end
	local list = filteredList( self )
	local page = self.cl.csScroll or 0
	local row = list[page * COLS + idx + 1]
	if not row or not row.itemId then
		return
	end
	self.cl.csSelected = tostring( row.itemId )
	refresh( self )
end

function RfsCraftStationGui.pickUpgrade( buttonName )
	local idx = tonumber( string.match( tostring( buttonName or "" ), "UpgSlot(%d+)" ) )
	local self = activeStation()
	if not self or idx == nil then
		return
	end
	local tier = tonumber( self.cl and self.cl.csTier ) or 1
	if tier < 5 and idx == ( tier - 1 ) then
		RfsCraftStationGui.upgrade()
	end
end

function RfsCraftStationGui.cancel( buttonName )
	local self = activeStation()
	if not self or not self.network then
		return
	end
	local idx = tonumber( string.match( tostring( buttonName or "" ), "QCancel(%d+)" ) )
	if idx == nil then
		return
	end
	local g = self.cl.csQueueGroups and self.cl.csQueueGroups[( self.cl.csQueueScroll or 0 ) + idx + 1]
	if not g then
		return
	end
	if g.kind == "recycle" then
		self.network:sendToServer( "sv_n_cancelRecycle", { index = g.startIndex } )
		return
	end
	self.network:sendToServer( "sv_n_cancelStation", { index = g.startIndex } )
end

function RfsCraftStationGui.plus()
	local self = activeStation()
	if not self then
		return
	end
	self.cl = self.cl or {}
	self.cl.csQty = clampQty( ( self.cl.csQty or 1 ) + 1 )
	self.cl.csSyncQty = true
	refresh( self )
end

function RfsCraftStationGui.minus()
	local self = activeStation()
	if not self then
		return
	end
	self.cl = self.cl or {}
	self.cl.csQty = clampQty( ( self.cl.csQty or 1 ) - 1 )
	self.cl.csSyncQty = true
	refresh( self )
end

function RfsCraftStationGui.craft()
	local self = activeStation()
	if not self or not self.cl then
		pcall( function()
			sm.gui.chatMessage( "[RFS] Add to Queue: no station" )
		end )
		return
	end
	if not self.network then
		pcall( function()
			sm.gui.chatMessage( "[RFS] Add to Queue: no network" )
		end )
		return
	end
	local id = pickSelectedId( self )
	if not id or id == "" then
		pcall( function()
			sm.gui.chatMessage( "[RFS] Select a recipe, then Add to Queue" )
		end )
		return
	end
	self.network:sendToServer( "sv_n_craftStation", { itemId = id, qty = self.cl.csQty or 1 } )
	refresh( self )
end

function RfsCraftStationGui.upgrade()
	local self = activeStation()
	if self and self.network then
		self.network:sendToServer( "sv_n_upgradeStation", {} )
	end
end

print( "[RFS] RfsCraftStationGui loaded" )
