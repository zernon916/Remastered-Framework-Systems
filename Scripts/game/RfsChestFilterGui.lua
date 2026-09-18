-- RfsChestFilterGui.lua — U-menu for Large Chest item filters.
-- Reuses craft-station upgrade panel background art.

RfsChestFilterGui = RfsChestFilterGui or {}

local LAYOUT = "$CONTENT_DATA/Gui/menu/layouts/Rfs_ChestFilter.layout"
local PAGE = 28
local COLS = 7
local ACTIVE = 7
local KIT_PREFIXES = {
	"$CONTENT_DATA/Gui/menu/images/craftstation/",
	"$CONTENT_DATA/Gui/menu/images/",
	"$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247/Gui/menu/images/craftstation/",
	"$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247/Gui/menu/images/",
}
local CAT_ALL = "all"
local CAT_BUTTONS = {
	{ id = CAT_ALL, widget = "CatAll", art = "ArtCatAll", on = "pill_all_on.png", off = "pill_all_off.png" },
	{ id = "tool", widget = "CatTool", art = "ArtCatTool", on = "pill_tools_on.png", off = "pill_tools_off.png" },
	{ id = "block", widget = "CatBlock", art = "ArtCatBlock", on = "pill_blocks_on.png", off = "pill_blocks_off.png" },
	{ id = "interactive", widget = "CatInteractive", art = "ArtCatInteractive", on = "pill_interactive_on.png", off = "pill_interactive_off.png" },
	{ id = "part", widget = "CatPart", art = "ArtCatPart", on = "pill_parts_on.png", off = "pill_parts_off.png" },
	{ id = "consumable", widget = "CatConsumable", art = "ArtCatConsumable", on = "pill_consumable_on.png", off = "pill_consumable_off.png" },
}

local function hostOf( chest )
	return chest or _G.g_rfsChestFilterHost
end

local function bindOne( gui, method, widget, cb )
	pcall( function()
		gui[method]( gui, widget, cb )
	end )
end

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

local function raiseScroll( gui )
	-- setImage restacks ArtScrollHost (and its ScrollBar child) above ArtUpgBg.
	paintKitImage( gui, "ArtScrollHost", "scroll_host.png" )
	pcall( function()
		gui:setVisible( "ArtScrollHost", true )
		gui:setVisible( "ScrollBar", true )
	end )
end

local function lastNumber( ... )
	local n
	for i = 1, select( "#", ... ) do
		local v = select( i, ... )
		if type( v ) == "table" then
			v = v.ratio or v.value or v.position or v[1]
		end
		v = tonumber( v )
		if v then
			n = v
		end
	end
	return n
end

local function clampScroll( chest, listLen )
	listLen = tonumber( listLen ) or 0
	local maxScroll = math.max( 0, listLen - PAGE )
	local scroll = math.max( 0, math.min( maxScroll, math.floor( tonumber( chest.cl.filterScroll ) or 0 ) ) )
	-- Snap to row starts so wheel/page feel like Craftbot.
	scroll = math.floor( scroll / COLS ) * COLS
	if scroll > maxScroll then
		scroll = math.max( 0, maxScroll - ( maxScroll % COLS ) )
	end
	chest.cl.filterScroll = scroll
	return scroll, maxScroll
end

local function setIcon( gui, widget, uuidStr )
	if not gui or not widget then
		return
	end
	if not uuidStr or uuidStr == "" then
		pcall( function()
			gui:setVisible( widget, false )
		end )
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
		if not name or name == "" or name == "not found" then
			name = sm.item.getDisplayName( sm.uuid.new( uuidStr ) )
		end
	end )
	return tostring( name or uuidStr )
end

local function uuidStr( u )
	if u == nil then
		return nil
	end
	return string.lower( tostring( u ) )
end

local function normalize( list )
	local out = {}
	local seen = {}
	if type( list ) ~= "table" then
		return out
	end
	for _, v in ipairs( list ) do
		local id = uuidStr( type( v ) == "table" and ( v.uuid or v.itemId ) or v )
		if id and id ~= "" and id ~= "00000000-0000-0000-0000-000000000000" and not seen[id] then
			seen[id] = true
			out[#out + 1] = id
		end
	end
	table.sort( out )
	return out
end

local function closeGui( chest )
	chest = hostOf( chest )
	if not chest or not chest.cl then
		return
	end
	local gui = chest.cl.filterGui
	chest.cl.filterGui = nil
	if gui then
		pcall( function()
			gui:close()
		end )
	end
end

local function inventoryIds()
	local list = {}
	local seen = {}
	local inv = nil
	pcall( function()
		inv = sm.localPlayer.getInventory()
	end )
	if inv and sm.exists( inv ) then
		local size = 0
		pcall( function()
			size = inv:getSize() or 0
		end )
		for i = 0, math.max( 0, size - 1 ) do
			local item = nil
			pcall( function()
				item = inv:getItem( i )
			end )
			local id = item and uuidStr( item.uuid )
			if id and id ~= "00000000-0000-0000-0000-000000000000" and not seen[id] then
				seen[id] = true
				list[#list + 1] = id
			end
		end
	end
	return list, seen
end

local function itemCategory( id )
	local cat = "part"
	pcall( function()
		if type( RfsCraftQueue ) == "table" and RfsCraftQueue.itemCategory then
			cat = RfsCraftQueue.itemCategory( id ) or "part"
		end
	end )
	return tostring( cat or "part" )
end

-- Full Craftbot catalog (all recipes), not only unlocked / inventory.
local function buildCatalog( chest )
	chest.cl = chest.cl or {}
	local list = {}
	local seen = {}
	local function add( id, cat, name )
		id = uuidStr( id )
		if id and not seen[id] then
			seen[id] = true
			list[#list + 1] = {
				itemId = id,
				name = name or itemName( id ),
				category = cat or itemCategory( id ),
			}
		end
	end

	-- Keep current allowlist entries visible even if not in craftbot sets.
	for _, id in ipairs( normalize( chest.cl.filters ) ) do
		add( id )
	end

	pcall( function()
		if type( RfsCraftQueue ) == "table" and RfsCraftQueue.listAllCraftbotRecipes then
			local all = RfsCraftQueue.listAllCraftbotRecipes()
			if type( all ) == "table" then
				for _, row in ipairs( all ) do
					if type( row ) == "table" and row.itemId then
						add( row.itemId, row.category, row.name )
					end
				end
			end
		elseif type( RfsCraftQueue ) == "table" and RfsCraftQueue.listKnownRecipes then
			-- Fallback if older pack missing listAllCraftbotRecipes.
			local learned = RfsCraftQueue.listKnownRecipes()
			if type( learned ) == "table" then
				for _, row in ipairs( learned ) do
					if type( row ) == "table" and row.itemId then
						add( row.itemId, row.category, row.name )
					end
				end
			end
		end
	end )

	-- Inventory-only odds/ends still show up (loot not on craftbot).
	for _, id in ipairs( inventoryIds() ) do
		add( id )
	end

	local cat = chest.cl.filterCategory or CAT_ALL
	if cat ~= CAT_ALL then
		local filtered = {}
		for _, row in ipairs( list ) do
			local itemCat = row.category or itemCategory( row.itemId )
			row.category = itemCat
			if itemCat == cat then
				filtered[#filtered + 1] = row
			end
		end
		list = filtered
	end

	local search = string.lower( tostring( chest.cl.filterSearch or "" ) )
	if search ~= "" then
		local filtered = {}
		for _, row in ipairs( list ) do
			if string.find( string.lower( row.name ), search, 1, true )
				or string.find( row.itemId, search, 1, true ) then
				filtered[#filtered + 1] = row
			end
		end
		list = filtered
	end

	table.sort( list, function( a, b )
		return tostring( a.name ) < tostring( b.name )
	end )
	chest.cl.filterList = list
	return list
end

local function paintCategories( gui, chest )
	if not gui then
		return
	end
	local cur = ( chest and chest.cl and chest.cl.filterCategory ) or CAT_ALL
	for _, c in ipairs( CAT_BUTTONS ) do
		local on = ( c.id == cur )
		setKitImage( gui, c.art, on and c.on or c.off )
		pcall( function()
			gui:setVisible( c.widget, true )
			gui:setVisible( c.art, true )
		end )
	end
end

local function activeSet( chest )
	local set = {}
	for _, id in ipairs( normalize( chest.cl and chest.cl.filters ) ) do
		set[id] = true
	end
	return set
end

local function pushFilters( chest )
	chest = hostOf( chest )
	if not chest or not chest.network then
		return
	end
	chest.network:sendToServer( "sv_n_setFilters", {
		filters = normalize( chest.cl and chest.cl.filters ),
	} )
end

local function refresh( chest )
	chest = hostOf( chest )
	if not chest or not chest.cl or not chest.cl.filterGui then
		return
	end
	local gui = chest.cl.filterGui
	paintCategories( gui, chest )
	local list = buildCatalog( chest )
	local selected = activeSet( chest )
	local scroll, maxScroll = clampScroll( chest, #list )

	for i = 0, PAGE - 1 do
		local row = list[scroll + i + 1]
		local cell = "Cell" .. i
		local icon = "Icon" .. i
		local mark = "Mark" .. i
		if row then
			pcall( function()
				gui:setVisible( cell, true )
			end )
			setIcon( gui, icon, row.itemId )
			local on = selected[row.itemId] == true
			setKitImage( gui, mark, on and "capacity_checkbox_full.png" or "capacity_checkbox_empty.png" )
			pcall( function()
				gui:setVisible( mark, true )
			end )
		else
			pcall( function()
				gui:setVisible( cell, false )
				gui:setVisible( icon, false )
				gui:setVisible( mark, false )
			end )
		end
	end

	local filters = normalize( chest.cl.filters )
	for i = 0, ACTIVE - 1 do
		local id = filters[i + 1]
		local icon = "ActiveIcon" .. i
		local cell = "Active" .. i
		if id then
			pcall( function()
				gui:setVisible( cell, true )
			end )
			setIcon( gui, icon, id )
		else
			pcall( function()
				gui:setVisible( cell, false )
				gui:setVisible( icon, false )
			end )
		end
	end

	-- Title/Status stay bound for future use but stay visually hidden.
	pcall( function()
		gui:setText( "Title", "" )
		gui:setText( "Status", "" )
		gui:setVisible( "Title", false )
		gui:setVisible( "Status", false )
	end )
	pcall( function()
		if gui.setSliderData then
			gui:setSliderData( "ScrollBar", math.max( 1, maxScroll + 1 ), math.floor( scroll / COLS ) )
		end
		gui:setVisible( "ScrollBar", maxScroll > 0 )
		gui:setVisible( "ArtScrollHost", maxScroll > 0 )
	end )
	-- Re-raise after refresh setImage calls (marks / category pills).
	if maxScroll > 0 then
		raiseScroll( gui )
	end
end

local function bindGui( gui )
	bindOne( gui, "setButtonCallback", "CloseButton", "cl_rfs_chestFilterClose" )
	bindOne( gui, "setOnCloseCallback", "cl_rfs_chestFilterClosed" )
	bindOne( gui, "setButtonCallback", "BtnClear", "cl_rfs_chestFilterClear" )
	bindOne( gui, "setSliderCallback", "ScrollBar", "cl_rfs_chestFilterScroll" )
	bindOne( gui, "setMouseWheelCallback", "ScrollBar", "cl_rfs_chestFilterWheel" )
	bindOne( gui, "setMouseWheelCallback", "Root", "cl_rfs_chestFilterWheel" )
	bindOne( gui, "setMouseWheelCallback", "MainPanel", "cl_rfs_chestFilterWheel" )
	bindOne( gui, "setMouseWheelCallback", "ArtGrid", "cl_rfs_chestFilterWheel" )
	bindOne( gui, "setMouseWheelCallback", "HitGrid", "cl_rfs_chestFilterWheel" )
	bindOne( gui, "setMouseWheelCallback", "ArtCats", "cl_rfs_chestFilterWheel" )
	bindOne( gui, "setMouseWheelCallback", "HitCats", "cl_rfs_chestFilterWheel" )
	bindOne( gui, "setTextChangedCallback", "SearchBox", "cl_rfs_chestFilterSearch" )
	bindOne( gui, "setButtonCallback", "CatAll", "cl_rfs_chestFilterCatAll" )
	bindOne( gui, "setButtonCallback", "CatTool", "cl_rfs_chestFilterCatTool" )
	bindOne( gui, "setButtonCallback", "CatBlock", "cl_rfs_chestFilterCatBlock" )
	bindOne( gui, "setButtonCallback", "CatInteractive", "cl_rfs_chestFilterCatInteractive" )
	bindOne( gui, "setButtonCallback", "CatPart", "cl_rfs_chestFilterCatPart" )
	bindOne( gui, "setButtonCallback", "CatConsumable", "cl_rfs_chestFilterCatConsumable" )
	for i = 0, PAGE - 1 do
		bindOne( gui, "setButtonCallback", "Cell" .. i, "cl_rfs_chestFilterPick" )
		bindOne( gui, "setMouseWheelCallback", "Cell" .. i, "cl_rfs_chestFilterWheel" )
		bindOne( gui, "setMouseWheelCallback", "Icon" .. i, "cl_rfs_chestFilterWheel" )
	end
	for i = 0, ACTIVE - 1 do
		bindOne( gui, "setButtonCallback", "Active" .. i, "cl_rfs_chestFilterActive" )
	end
end

local function applyArt( gui )
	paintKitImage( gui, "ArtUpgBg", "upgrade_panel_bg.png" )
	if not setKitImage( gui, "ArtHeader", "storagefilterlogo.png" ) then
		pcall( function()
			gui:setImage( "ArtHeader", "$CONTENT_DATA/Gui/menu/images/storagefilterlogo.png" )
			gui:setVisible( "ArtHeader", true )
		end )
	end
	pcall( function()
		gui:setVisible( "ArtHeader", true )
	end )
	setKitImage( gui, "ArtClose", "btn_close_oct.png" )
	setKitImage( gui, "ArtClear", "btn_cancel.png" )
	for i = 0, PAGE - 1 do
		setKitImage( gui, "ArtCell" .. i, "slot_frame.png" )
	end
	for i = 0, ACTIVE - 1 do
		setKitImage( gui, "ArtActive" .. i, "slot_frame.png" )
	end
	paintCategories( gui, hostOf() )
	raiseScroll( gui )
	pcall( function()
		gui:setText( "CloseButton", "" )
		gui:setText( "BtnClear", "" )
		gui:setText( "Title", "" )
		gui:setText( "Status", "" )
		gui:setVisible( "Title", false )
		gui:setVisible( "Status", false )
		if gui.setSliderData then
			gui:setSliderData( "ScrollBar", 1, 0 )
		end
	end )
end

function RfsChestFilterGui.open( chest )
	if not chest then
		return
	end
	chest.cl = chest.cl or {}
	closeGui( chest )
	local ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT, true, {
		isHud = false,
		isInteractive = true,
		needsCursor = true,
	} )
	if not ok or not gui then
		ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT, true )
	end
	if not ok or not gui then
		pcall( function()
			sm.gui.chatMessage( "[RFS] Chest filter menu failed to create" )
		end )
		return
	end

	_G.g_rfsChestFilterHost = chest
	chest.cl.filterGui = gui
	chest.cl.filterScroll = chest.cl.filterScroll or 0
	chest.cl.filterSearch = chest.cl.filterSearch or ""
	chest.cl.filterCategory = chest.cl.filterCategory or CAT_ALL
	chest.cl.filters = normalize( chest.cl.filters )

	pcall( bindGui, gui )
	pcall( applyArt, gui )
	pcall( function()
		gui:open()
	end )
	pcall( bindGui, gui )
	pcall( applyArt, gui )
	chest.network:sendToServer( "sv_n_getFilters", {} )
	refresh( chest )
end

function RfsChestFilterGui.close( chest )
	closeGui( chest )
end

function RfsChestFilterGui.closeActive()
	local chest = hostOf()
	closeGui( chest )
	_G.g_rfsChestFilterHost = nil
end

function RfsChestFilterGui.onFilters( chest, filters )
	chest = hostOf( chest )
	if not chest or not chest.cl then
		return
	end
	chest.cl.filters = normalize( filters )
	if chest.cl.filterGui then
		refresh( chest )
	end
end

function RfsChestFilterGui.clearAll()
	local chest = hostOf()
	if not chest or not chest.cl then
		return
	end
	chest.cl.filters = {}
	pushFilters( chest )
	refresh( chest )
end

function RfsChestFilterGui.scroll( ... )
	local chest = hostOf()
	if not chest or not chest.cl then
		return
	end
	-- Slider reports row index; convert to item offset.
	local row = math.floor( lastNumber( ... ) or 0 )
	chest.cl.filterScroll = math.max( 0, row ) * COLS
	refresh( chest )
end

function RfsChestFilterGui.wheel( ... )
	local chest = hostOf()
	if not chest or not chest.cl then
		return
	end
	local delta = lastNumber( ... ) or 0
	if delta == 0 then
		return
	end
	-- Same sign convention as Craft Station: wheel down → next page.
	local step = ( delta < 0 ) and COLS or -COLS
	chest.cl.filterScroll = math.max( 0, ( chest.cl.filterScroll or 0 ) + step )
	refresh( chest )
end

function RfsChestFilterGui.search( widget, text )
	local chest = hostOf()
	if not chest or not chest.cl then
		return
	end
	chest.cl.filterSearch = tostring( text or "" )
	chest.cl.filterScroll = 0
	refresh( chest )
end

local function setCategory( category )
	local chest = hostOf()
	if not chest or not chest.cl then
		return
	end
	chest.cl.filterCategory = category or CAT_ALL
	chest.cl.filterScroll = 0
	refresh( chest )
end

function RfsChestFilterGui.catAll() setCategory( CAT_ALL ) end
function RfsChestFilterGui.catTool() setCategory( "tool" ) end
function RfsChestFilterGui.catBlock() setCategory( "block" ) end
function RfsChestFilterGui.catInteractive() setCategory( "interactive" ) end
function RfsChestFilterGui.catPart() setCategory( "part" ) end
function RfsChestFilterGui.catConsumable() setCategory( "consumable" ) end

local function toggleId( chest, id )
	id = uuidStr( id )
	if not id then
		return
	end
	local list = normalize( chest.cl.filters )
	local found = false
	local nextList = {}
	for _, f in ipairs( list ) do
		if f == id then
			found = true
		else
			nextList[#nextList + 1] = f
		end
	end
	if not found then
		-- Active strip + world icons show 7 slots (Active0-6).
		if #nextList >= ACTIVE then
			return
		end
		nextList[#nextList + 1] = id
	end
	chest.cl.filters = normalize( nextList )
	pushFilters( chest )
	refresh( chest )
end

function RfsChestFilterGui.pick( buttonName )
	local chest = hostOf()
	if not chest or not chest.cl then
		return
	end
	local idx = tonumber( string.match( tostring( buttonName or "" ), "(%d+)$" ) )
	if idx == nil then
		return
	end
	local list = chest.cl.filterList or buildCatalog( chest )
	local scroll = math.max( 0, math.floor( tonumber( chest.cl.filterScroll ) or 0 ) )
	local row = list[scroll + idx + 1]
	if row then
		toggleId( chest, row.itemId )
	end
end

function RfsChestFilterGui.pickActive( buttonName )
	local chest = hostOf()
	if not chest or not chest.cl then
		return
	end
	local idx = tonumber( string.match( tostring( buttonName or "" ), "(%d+)$" ) )
	if idx == nil then
		return
	end
	local filters = normalize( chest.cl.filters )
	local id = filters[idx + 1]
	if id then
		toggleId( chest, id )
	end
end

print( "[RFS] RfsChestFilterGui loaded" )
