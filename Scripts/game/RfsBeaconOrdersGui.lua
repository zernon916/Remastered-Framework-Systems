-- RfsBeaconOrdersGui.lua — Beacon Orders GUI (Rest/Defend/Farm/Collect/Oil)
-- Author: DemonsDen126
-- Opened from powered Hack/Control/Infection beacons when home allies exist.
-- Hay: Rest|Defend|Farm + seed picker. Tote: Rest|Defend|Collect.
-- Waterbot (Totebot Blue): Rest|Defend|Collect Oil. Others: Rest|Defend.

RfsBeaconOrdersGui = RfsBeaconOrdersGui or {}

pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsFarming.lua" )
end )

local LAYOUT = "$CONTENT_DATA/Gui/Layouts/Rfs_BeaconOrders.layout"
local ROWS = 8
local MODE_ITEMS_DEFAULT = { "Rest", "Defend" }
local MODE_ITEMS_HAY = { "Rest", "Defend", "Farm" }
local MODE_ITEMS_TOTE = { "Rest", "Defend", "Collect" }
local MODE_ITEMS_WATER = { "Rest", "Defend", "Collect Oil" }

local UUID_TOTEBOT_BLUE = "58992f50-ca36-44e1-8c47-4996d89d6a9a"

local function modeLabel( mode )
	mode = string.lower( tostring( mode or "rest" ) )
	if mode == "defend" then
		return "Defend"
	end
	if mode == "farm" then
		return "Farm"
	end
	if mode == "collect" then
		return "Collect"
	end
	if mode == "oil" then
		return "Collect Oil"
	end
	return "Rest"
end

local function modeValue( label )
	label = string.lower( tostring( label or "rest" ) )
	if label == "defend" then
		return "defend"
	end
	if label == "farm" then
		return "farm"
	end
	if label == "collect" then
		return "collect"
	end
	if label == "oil" or label == "collect oil" or label == "collectoil" then
		return "oil"
	end
	return "rest"
end

local function sameUuid( a, b )
	if a == nil or b == nil then
		return false
	end
	return string.lower( tostring( a ) ) == string.lower( tostring( b ) )
end

local function botKind( typeStr, displayName )
	local typeRaw = tostring( typeStr or "" )
	local s = string.lower( typeRaw .. " " .. tostring( displayName or "" ) )
	-- Waterbot / Totebot Blue before generic tote (Oil vs Collect).
	if type( RfsBotOrders ) == "table" and type( RfsBotOrders.isWaterbotType ) == "function" then
		if RfsBotOrders.isWaterbotType( typeRaw ) or RfsBotOrders.isWaterbotType( displayName ) then
			return "water"
		end
	end
	local blue = rawget( _G, "unit_totebot_blue" )
	if ( blue and sameUuid( typeRaw, blue ) ) or sameUuid( typeRaw, UUID_TOTEBOT_BLUE ) then
		return "water"
	end
	if string.find( s, "waterbot", 1, true )
		or ( string.find( s, "water", 1, true ) and not string.find( s, "tote", 1, true ) )
		or string.find( s, "oil", 1, true ) then
		return "water"
	end
	if string.find( s, "farm", 1, true ) then
		return "farmbot"
	end
	if string.find( s, "hay", 1, true ) then
		return "hay"
	end
	if string.find( s, "tote", 1, true ) then
		return "tote"
	end
	if string.find( s, "tape", 1, true ) then
		return "tape"
	end
	if string.find( s, "miner", 1, true ) then
		return "miner"
	end
	if string.find( s, "cable", 1, true ) then
		return "cable"
	end
	return "other"
end

local function modeItemsForKind( kind )
	if kind == "hay" then
		return MODE_ITEMS_HAY
	end
	if kind == "tote" then
		return MODE_ITEMS_TOTE
	end
	if kind == "water" then
		return MODE_ITEMS_WATER
	end
	return MODE_ITEMS_DEFAULT
end

local function soonText( kind )
	if kind == "farmbot" then
		return "Rest|Defend"
	end
	return ""
end

local function seedLabels()
	if type( RfsFarming ) == "table" and RfsFarming.getSeedDropdownLabels then
		local ok, labels = pcall( RfsFarming.getSeedDropdownLabels )
		if ok and type( labels ) == "table" and #labels > 0 then
			return labels
		end
	end
	return { "Tomato", "Carrot", "Potato", "Redbeet", "Banana", "Blueberry", "Orange", "Pineapple", "Broccoli", "Cotton", "Chili", "Pigment Flower" }
end

local function seedLabelForUuid( uuid )
	if type( RfsFarming ) == "table" and RfsFarming.seedLabelFromUuid then
		local ok, name = pcall( RfsFarming.seedLabelFromUuid, uuid )
		if ok and name then
			return name
		end
	end
	return "Tomato"
end

local function seedUuidForLabel( label )
	if type( RfsFarming ) == "table" and RfsFarming.seedUuidFromLabel then
		local ok, uuid = pcall( RfsFarming.seedUuidFromLabel, label )
		if ok and uuid then
			return tostring( uuid )
		end
	end
	return nil
end

function RfsBeaconOrdersGui.rowFromWidget( host, widgetName )
	local idx = tonumber( string.match( tostring( widgetName or "" ), "(%d+)$" ) )
	if idx == nil then
		return nil
	end
	local rows = host.cl and host.cl.rfsOrdersRows or {}
	local page = host.cl and host.cl.rfsOrdersPage or 0
	local abs = page * ROWS + idx + 1
	return rows[abs], abs, idx
end

function RfsBeaconOrdersGui.refresh( host )
	local gui = host.cl and host.cl.rfsOrdersGui
	if not gui then
		return
	end

	local rows = host.cl.rfsOrdersRows or {}
	local page = host.cl.rfsOrdersPage or 0
	local maxPage = math.max( 0, math.ceil( #rows / ROWS ) - 1 )
	if page > maxPage then
		page = maxPage
		host.cl.rfsOrdersPage = page
	end
	if page < 0 then
		page = 0
		host.cl.rfsOrdersPage = 0
	end

	local beaconName = host.cl.rfsOrdersBeaconName or "Beacon"
	local key = host.cl.rfsOrdersBeaconKey or "?"
	gui:setText( "Status", string.format(
		"%s — %d home ally(ies) | key %s",
		tostring( beaconName ),
		#rows,
		tostring( key )
	) )
	gui:setText( "PageLabel", string.format( "Page %d / %d", page + 1, maxPage + 1 ) )

	local seeds = seedLabels()

	for i = 0, ROWS - 1 do
		local abs = page * ROWS + i + 1
		local row = rows[abs]
		local nameW = "BotName" .. i
		local soonW = "Soon" .. i
		local dropW = "ModeDrop" .. i
		local seedW = "SeedDrop" .. i
		if row then
			gui:setText( nameW, tostring( row.name or row.key or "Bot" ) )
			gui:setVisible( nameW, true )
			gui:setVisible( dropW, true )
			pcall( function()
				gui:createDropDown( dropW, "cl_rfs_ordersDrop" .. i, modeItemsForKind( row.kind ) )
			end )
			pcall( function()
				gui:setSelectedDropDownItem( dropW, modeLabel( row.mode ) )
			end )

			local showSeed = ( row.kind == "hay" and row.mode == "farm" )
			if showSeed then
				gui:setText( soonW, "" )
				gui:setVisible( soonW, false )
				gui:setVisible( seedW, true )
				pcall( function()
					gui:createDropDown( seedW, "cl_rfs_ordersSeed" .. i, seeds )
				end )
				pcall( function()
					gui:setSelectedDropDownItem( seedW, seedLabelForUuid( row.seedUuid ) )
				end )
			else
				gui:setVisible( seedW, false )
				local soon = soonText( row.kind )
				gui:setText( soonW, soon )
				gui:setVisible( soonW, soon ~= "" )
			end
		else
			gui:setText( nameW, "" )
			gui:setText( soonW, "" )
			gui:setVisible( nameW, false )
			gui:setVisible( soonW, false )
			gui:setVisible( dropW, false )
			gui:setVisible( seedW, false )
		end
	end
end

function RfsBeaconOrdersGui.bind( host, gui )
	host.cl = host.cl or {}
	host.cl.rfsOrdersGui = gui
	host.cl.rfsOrdersPage = host.cl.rfsOrdersPage or 0
	host.cl.rfsOrdersRows = host.cl.rfsOrdersRows or {}

	gui:setButtonCallback( "CloseButton", "cl_rfs_ordersClose" )
	gui:setButtonCallback( "BtnPrev", "cl_rfs_ordersPrev" )
	gui:setButtonCallback( "BtnNext", "cl_rfs_ordersNext" )
	gui:setOnCloseCallback( "cl_rfs_ordersClose" )

	local seeds = seedLabels()
	for i = 0, ROWS - 1 do
		pcall( function()
			gui:createDropDown( "ModeDrop" .. i, "cl_rfs_ordersDrop" .. i, MODE_ITEMS_DEFAULT )
		end )
		pcall( function()
			gui:createDropDown( "SeedDrop" .. i, "cl_rfs_ordersSeed" .. i, seeds )
		end )
		pcall( function()
			gui:setVisible( "SeedDrop" .. i, false )
		end )
	end
end

function RfsBeaconOrdersGui.open( host, opts )
	opts = opts or {}
	if not opts.beaconKey then
		sm.gui.chatMessage( "[RFS] Orders: missing beacon key" )
		return
	end

	if host.cl and host.cl.rfsOrdersGui then
		pcall( function() host.cl.rfsOrdersGui:close() end )
		host.cl.rfsOrdersGui = nil
	end

	local ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT )
	if not ok or not gui then
		sm.gui.chatMessage( "[RFS] Failed to open Beacon Orders GUI" )
		print( "[RFS] orders GUI create failed: " .. tostring( gui ) )
		return
	end

	host.cl = host.cl or {}
	host.cl.rfsOrdersBeaconKey = tostring( opts.beaconKey )
	host.cl.rfsOrdersBeaconName = opts.beaconName or "Hack Beacon"
	host.cl.rfsOrdersPage = 0
	host.cl.rfsOrdersRows = {}

	RfsBeaconOrdersGui.bind( host, gui )
	RfsBeaconOrdersGui.refresh( host )
	gui:open()
	host.network:sendToServer( "sv_rfs_ordersList", {
		beaconKey = host.cl.rfsOrdersBeaconKey,
	} )
	sm.gui.chatMessage( "[RFS] Beacon Orders opened" )
end

function RfsBeaconOrdersGui.close( host )
	local gui = host.cl and host.cl.rfsOrdersGui
	if gui then
		pcall( function() gui:close() end )
	end
	if host.cl then
		host.cl.rfsOrdersGui = nil
	end
end

function RfsBeaconOrdersGui.applyList( host, data )
	host.cl = host.cl or {}
	host.cl.rfsOrdersRows = {}
	if type( data ) == "table" and type( data.rows ) == "table" then
		for _, row in ipairs( data.rows ) do
			if row and row.key then
				local kind = botKind( row.unitType or row.type, row.name )
				local mode = modeValue( row.mode )
				-- Soft-clamp: farm only on hay, collect only on tote, oil only on water.
				if mode == "farm" and kind ~= "hay" then
					mode = "rest"
				end
				if mode == "collect" and kind ~= "tote" then
					mode = "rest"
				end
				if mode == "oil" and kind ~= "water" then
					mode = "rest"
				end
				host.cl.rfsOrdersRows[#host.cl.rfsOrdersRows + 1] = {
					key = tostring( row.key ),
					name = row.name or ( "Bot " .. tostring( row.key ) ),
					unitType = row.unitType or row.type,
					kind = kind,
					mode = mode,
					seedUuid = row.seedUuid and tostring( row.seedUuid ) or nil,
					owner = row.owner,
				}
			end
		end
	end
	if data and data.beaconName then
		host.cl.rfsOrdersBeaconName = data.beaconName
	end
	RfsBeaconOrdersGui.refresh( host )
end

function RfsBeaconOrdersGui.onModeDrop( host, rowIdx, value )
	local rows = host.cl and host.cl.rfsOrdersRows or {}
	local page = host.cl and host.cl.rfsOrdersPage or 0
	local abs = page * ROWS + ( tonumber( rowIdx ) or 0 ) + 1
	local row = rows[abs]
	if not row or not row.key then
		return
	end
	local mode = modeValue( value )
	if mode == "farm" and row.kind ~= "hay" then
		return
	end
	if mode == "collect" and row.kind ~= "tote" then
		return
	end
	if mode == "oil" and row.kind ~= "water" then
		return
	end
	if mode == row.mode then
		return
	end
	row.mode = mode
	if mode == "farm" and not row.seedUuid then
		local uuid = seedUuidForLabel( "Tomato" )
		row.seedUuid = uuid and tostring( uuid ) or nil
	end
	host.network:sendToServer( "sv_rfs_ordersSet", {
		unitKey = row.key,
		mode = mode,
		seedUuid = row.seedUuid,
		beaconKey = host.cl.rfsOrdersBeaconKey,
	} )
	RfsBeaconOrdersGui.refresh( host )
end

function RfsBeaconOrdersGui.onSeedDrop( host, rowIdx, value )
	local rows = host.cl and host.cl.rfsOrdersRows or {}
	local page = host.cl and host.cl.rfsOrdersPage or 0
	local abs = page * ROWS + ( tonumber( rowIdx ) or 0 ) + 1
	local row = rows[abs]
	if not row or not row.key or row.kind ~= "hay" then
		return
	end
	local uuid = seedUuidForLabel( value )
	if not uuid then
		return
	end
	local s = tostring( uuid )
	if row.seedUuid and tostring( row.seedUuid ) == s and row.mode == "farm" then
		return
	end
	row.seedUuid = s
	row.mode = "farm"
	host.network:sendToServer( "sv_rfs_ordersSet", {
		unitKey = row.key,
		mode = "farm",
		seedUuid = s,
		beaconKey = host.cl.rfsOrdersBeaconKey,
	} )
end

RfsBeaconOrdersGui.ROWS = ROWS
RfsBeaconOrdersGui.modeLabel = modeLabel
RfsBeaconOrdersGui.modeValue = modeValue
RfsBeaconOrdersGui.botKind = botKind
