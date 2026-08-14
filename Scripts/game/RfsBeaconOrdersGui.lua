-- RfsBeaconOrdersGui.lua — Beacon Orders GUI (Rest/Defend/Farm/Collect/Oil + ally color)
-- Author: DemonsDen126
-- Opened from powered Hack/Control/Infection beacons when home allies exist.
-- Hay: Rest|Defend|Farm + seed picker. Tote: Rest|Defend|Collect.
-- Waterbot (Totebot Blue): Rest|Defend|Collect Oil. Others: Rest|Defend.
-- Color: click bot name to select; Color drop applies to selected, or all listed if none.

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

-- Full-body presets (RRGGBBAA). Ally Green / Infect Green match RfsBotHijack defaults.
local COLOR_PRESETS = {
	{ label = "Ally Green", hex = "3dff8aff" },
	{ label = "Infect Green", hex = "1aff6aff" },
	{ label = "Blue", hex = "3d9effff" },
	{ label = "Cyan", hex = "3dffffff" },
	{ label = "Yellow", hex = "ffe03dff" },
	{ label = "Orange", hex = "ff8a3dff" },
	{ label = "Magenta", hex = "ff3dffff" },
	{ label = "White", hex = "ffffffff" },
	{ label = "Red", hex = "ff3d3dff" },
}

local UUID_TOTEBOT_BLUE = "58992f50-ca36-44e1-8c47-4996d89d6a9a"

-- Fallback range ring drawn on the Game client when the beacon interactable
-- cannot see Game's _G.g_rfsBeaconRangeVisible (separate script sandbox).
local RING_BLOCK = sm.uuid.new( "073f92af-f37e-4aff-96b3-d66284d5081c" )
local RING_SEG_SPACING = 1.75
local RING_SEG_MIN = 24
local RING_SEG_MAX = 72

local function destroyHostRangeRing( host )
	local ring = host.cl and host.cl.rfsOrdersRangeRing
	if type( ring ) ~= "table" then
		return
	end
	for _, fx in ipairs( ring ) do
		pcall( function()
			if fx and sm.exists( fx ) then
				fx:stop()
				fx:destroy()
			end
		end )
	end
	host.cl.rfsOrdersRangeRing = nil
end

local function groundZ( x, y, fallbackZ )
	local hit, result
	local ok = pcall( function()
		hit, result = sm.physics.raycast(
			sm.vec3.new( x, y, fallbackZ + 24 ),
			sm.vec3.new( x, y, fallbackZ - 80 )
		)
	end )
	if ok and hit and result and result.pointWorld then
		return result.pointWorld.z + 0.06
	end
	return fallbackZ
end

local function buildHostRangeRing( host, range, color )
	destroyHostRangeRing( host )
	host.cl = host.cl or {}
	local pos = host.cl.rfsOrdersBeaconPos
	if type( pos ) ~= "table" or pos.x == nil then
		return
	end
	range = tonumber( range ) or tonumber( host.cl.rfsOrdersRange ) or 16
	if range < 1 then
		return
	end
	local n = math.floor( ( 2 * math.pi * range ) / RING_SEG_SPACING + 0.5 )
	if n < RING_SEG_MIN then n = RING_SEG_MIN end
	if n > RING_SEG_MAX then n = RING_SEG_MAX end
	local ring = {}
	local col = color or sm.color.new( 0.55, 0.95, 0.25, 1.0 )
	local scale = sm.vec3.new( 0.28, 0.28, 0.08 )
	for i = 0, n - 1 do
		local ang = ( i / n ) * math.pi * 2
		local x = pos.x + math.cos( ang ) * range
		local y = pos.y + math.sin( ang ) * range
		local z = groundZ( x, y, pos.z )
		local ok, fx = pcall( sm.effect.createEffect, "ShapeRenderable" )
		if ok and fx then
			pcall( function()
				fx:setParameter( "uuid", RING_BLOCK )
				fx:setParameter( "color", col )
				fx:setScale( scale )
				fx:setPosition( sm.vec3.new( x, y, z ) )
				fx:setRotation( sm.quat.identity() )
				fx:start()
			end )
			ring[#ring + 1] = fx
		end
	end
	host.cl.rfsOrdersRangeRing = ring
end

local function colorLabels()
	local out = {}
	for i, p in ipairs( COLOR_PRESETS ) do
		out[i] = p.label
	end
	return out
end

local function colorHexForLabel( label )
	label = tostring( label or "" )
	for _, p in ipairs( COLOR_PRESETS ) do
		if p.label == label then
			return p.hex
		end
	end
	return nil
end

local function colorLabelForHex( hex )
	if not hex then
		return nil
	end
	local h = string.lower( tostring( hex ):gsub( "^#", "" ) )
	for _, p in ipairs( COLOR_PRESETS ) do
		if string.lower( p.hex ) == h then
			return p.label
		end
	end
	return nil
end

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
	local role = string.lower( tostring( host.cl.rfsOrdersRole or "independent" ) )
	local roleTxt = "Independent"
	if role == "master" then
		roleTxt = "Master"
	elseif role == "slave" then
		local mk = host.cl.rfsOrdersMasterKey
		roleTxt = mk and ( "Slave of " .. tostring( mk ) ) or "Slave"
	end
	gui:setText( "Status", string.format(
		"%s — %d ally(ies) | %s | key %s",
		tostring( beaconName ),
		#rows,
		roleTxt,
		tostring( key )
	) )
	gui:setText( "PageLabel", string.format( "Page %d / %d", page + 1, maxPage + 1 ) )
	pcall( function()
		gui:setText( "RoleLabel", "Role: " .. roleTxt )
	end )
	pcall( function()
		if role == "master" then
			gui:setText( "BtnMaster", "CLEAR MASTER" )
		elseif role == "slave" then
			gui:setText( "BtnMaster", "SET MASTER" )
		else
			gui:setText( "BtnMaster", "SET MASTER" )
		end
	end )
	local showRange = false
	local map = _G.g_rfsBeaconRangeVisible
	if type( map ) == "table" and key and map[tostring( key )] == true then
		showRange = true
	end
	host.cl.rfsOrdersShowRange = showRange
	pcall( function()
		gui:setText( "BtnRange", showRange and "HIDE RANGE" or "SHOW RANGE" )
	end )

	local selectedKey = host.cl.rfsOrdersSelectedKey
	local selectedName = nil
	if selectedKey then
		for _, r in ipairs( rows ) do
			if r and tostring( r.key ) == tostring( selectedKey ) then
				selectedName = r.name or r.key
				break
			end
		end
		if not selectedName then
			host.cl.rfsOrdersSelectedKey = nil
			selectedKey = nil
		end
	end
	pcall( function()
		if selectedName then
			gui:setText( "ColorSelLabel", "Selected: " .. tostring( selectedName ) )
		else
			gui:setText( "ColorSelLabel", "None selected — applies to all" )
		end
	end )

	local seeds = seedLabels()

	for i = 0, ROWS - 1 do
		local abs = page * ROWS + i + 1
		local row = rows[abs]
		local nameW = "BotName" .. i
		local soonW = "Soon" .. i
		local dropW = "ModeDrop" .. i
		local seedW = "SeedDrop" .. i
		if row then
			local mark = ( selectedKey and tostring( row.key ) == tostring( selectedKey ) ) and "> " or ""
			gui:setText( nameW, mark .. tostring( row.name or row.key or "Bot" ) )
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

	-- Callbacks must resolve on the Game host (GUI is opened via Game client RPC).
	gui:setButtonCallback( "CloseButton", "cl_rfs_ordersClose" )
	gui:setButtonCallback( "BtnPrev", "cl_rfs_ordersPrev" )
	gui:setButtonCallback( "BtnNext", "cl_rfs_ordersNext" )
	gui:setButtonCallback( "BtnMaster", "cl_rfs_ordersMaster" )
	gui:setButtonCallback( "BtnRange", "cl_rfs_ordersRange" )
	-- Separate OnClose so CloseButton → close() does not re-enter close.
	gui:setOnCloseCallback( "cl_rfs_ordersOnClosed" )

	local seeds = seedLabels()
	local colors = colorLabels()
	pcall( function()
		gui:createDropDown( "ColorDrop", "cl_rfs_ordersColor", colors )
	end )
	pcall( function()
		gui:setSelectedDropDownItem( "ColorDrop", "Ally Green" )
	end )
	for i = 0, ROWS - 1 do
		pcall( function()
			gui:setButtonCallback( "BotName" .. i, "cl_rfs_ordersBot" .. i )
		end )
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
		local old = host.cl.rfsOrdersGui
		host.cl.rfsOrdersGui = nil
		pcall( function() old:close() end )
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
	host.cl.rfsOrdersRole = opts.role or "independent"
	host.cl.rfsOrdersMasterKey = opts.masterKey
	host.cl.rfsOrdersRange = tonumber( opts.range ) or 16
	host.cl.rfsOrdersBeaconPos = nil
	if type( opts.pos ) == "table" and opts.pos.x ~= nil then
		host.cl.rfsOrdersBeaconPos = {
			x = tonumber( opts.pos.x ) or 0,
			y = tonumber( opts.pos.y ) or 0,
			z = tonumber( opts.pos.z ) or 0,
		}
	end
	host.cl.rfsOrdersPage = 0
	host.cl.rfsOrdersRows = {}
	host.cl.rfsOrdersSelectedKey = nil

	RfsBeaconOrdersGui.bind( host, gui )
	-- Server may already include rows (beacon-built list); apply before refresh.
	if type( opts.rows ) == "table" and #opts.rows > 0 then
		RfsBeaconOrdersGui.applyList( host, {
			rows = opts.rows,
			beaconKey = opts.beaconKey,
			beaconName = opts.beaconName,
			role = opts.role,
			masterKey = opts.masterKey,
		} )
	else
		RfsBeaconOrdersGui.refresh( host )
	end
	gui:open()
	host.network:sendToServer( "sv_rfs_ordersList", {
		beaconKey = host.cl.rfsOrdersBeaconKey,
	} )
	sm.gui.chatMessage( "[RFS] Beacon Orders opened" )
end

function RfsBeaconOrdersGui.close( host )
	local gui = host.cl and host.cl.rfsOrdersGui
	destroyHostRangeRing( host )
	-- Nil first so OnClose callback is a no-op.
	if host.cl then
		host.cl.rfsOrdersGui = nil
	end
	if gui then
		pcall( function() gui:close() end )
	end
end

function RfsBeaconOrdersGui.onClosed( host )
	destroyHostRangeRing( host )
	if host.cl then
		host.cl.rfsOrdersGui = nil
	end
end

function RfsBeaconOrdersGui.applyRole( host, data )
	host.cl = host.cl or {}
	if data and data.beaconKey and host.cl.rfsOrdersBeaconKey
		and tostring( data.beaconKey ) ~= tostring( host.cl.rfsOrdersBeaconKey ) then
		return
	end
	if data and data.role then
		host.cl.rfsOrdersRole = data.role
	end
	if data then
		host.cl.rfsOrdersMasterKey = data.masterKey
	end
	RfsBeaconOrdersGui.refresh( host )
end

function RfsBeaconOrdersGui.toggleRange( host )
	host.cl = host.cl or {}
	local key = host.cl.rfsOrdersBeaconKey
	if not key then
		return
	end
	key = tostring( key )
	_G.g_rfsBeaconRangeVisible = _G.g_rfsBeaconRangeVisible or {}
	local on = not ( _G.g_rfsBeaconRangeVisible[key] == true )
	_G.g_rfsBeaconRangeVisible[key] = on
	host.cl.rfsOrdersShowRange = on
	-- Server mirrors onto beacon clientData.showRange so the interactable client
	-- (separate sandbox from Game GUI) actually draws/clears the ring.
	if host.network and host.network.sendToServer then
		pcall( function()
			host.network:sendToServer( "sv_rfs_ordersRange", {
				beaconKey = key,
				show = on,
			} )
		end )
	end
	-- Game-client fallback ring (works even when beacon never sees Game's _G).
	if on then
		buildHostRangeRing( host, host.cl.rfsOrdersRange )
	else
		destroyHostRangeRing( host )
	end
	RfsBeaconOrdersGui.refresh( host )
	sm.gui.chatMessage( on and "[RFS] Range shown" or "[RFS] Range hidden" )
end

function RfsBeaconOrdersGui.setMaster( host )
	host.cl = host.cl or {}
	local key = host.cl.rfsOrdersBeaconKey
	if not key then
		return
	end
	local role = string.lower( tostring( host.cl.rfsOrdersRole or "independent" ) )
	if role == "master" then
		host.network:sendToServer( "sv_rfs_ordersClearMaster", { beaconKey = key } )
	else
		host.network:sendToServer( "sv_rfs_ordersSetMaster", { beaconKey = key } )
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
					allyColor = row.allyColor and tostring( row.allyColor ) or nil,
				}
			end
		end
	end
	if data and data.beaconName then
		host.cl.rfsOrdersBeaconName = data.beaconName
	end
	if data and data.role then
		host.cl.rfsOrdersRole = data.role
	end
	if data and data.masterKey ~= nil then
		host.cl.rfsOrdersMasterKey = data.masterKey
	end
	RfsBeaconOrdersGui.refresh( host )
end

function RfsBeaconOrdersGui.onBotClick( host, rowIdx )
	host.cl = host.cl or {}
	local rows = host.cl.rfsOrdersRows or {}
	local page = host.cl.rfsOrdersPage or 0
	local abs = page * ROWS + ( tonumber( rowIdx ) or 0 ) + 1
	local row = rows[abs]
	if not row or not row.key then
		return
	end
	local key = tostring( row.key )
	if host.cl.rfsOrdersSelectedKey and tostring( host.cl.rfsOrdersSelectedKey ) == key then
		host.cl.rfsOrdersSelectedKey = nil
	else
		host.cl.rfsOrdersSelectedKey = key
	end
	RfsBeaconOrdersGui.refresh( host )
end

function RfsBeaconOrdersGui.onColorDrop( host, value )
	host.cl = host.cl or {}
	local hex = colorHexForLabel( value )
	if not hex then
		return
	end
	local beaconKey = host.cl.rfsOrdersBeaconKey
	if not beaconKey then
		return
	end
	local selected = host.cl.rfsOrdersSelectedKey
	host.network:sendToServer( "sv_rfs_ordersSetColor", {
		beaconKey = beaconKey,
		unitKey = selected,
		colorHex = hex,
		colorLabel = tostring( value ),
	} )
	local scope = selected and "selected bot" or "all listed allies"
	sm.gui.chatMessage( "[RFS] Color " .. tostring( value ) .. " → " .. scope )
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
RfsBeaconOrdersGui.COLOR_PRESETS = COLOR_PRESETS
RfsBeaconOrdersGui.colorHexForLabel = colorHexForLabel
RfsBeaconOrdersGui.colorLabelForHex = colorLabelForHex
