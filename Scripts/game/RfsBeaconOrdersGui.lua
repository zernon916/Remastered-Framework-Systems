-- RfsBeaconOrdersGui.lua — Beacon Orders GUI (Rest/Defend/Farm/Collect/Oil + ally color)
-- Author: DemonsDen126
-- Opened from powered Hack/Control/Infection beacons when home allies exist.
-- Hay: Rest|Defend|Farm + seed picker. Tote: Rest|Defend|Collect.
-- Waterbot (Totebot Blue): Rest|Defend|Collect Oil. Others: Rest|Defend.
-- Color: click number (BotName) to select; Color drop applies to selected, or all listed if none.
-- Return: Orders dropdown; selected bot, or all listed if none, walk to their hack device.

RfsBeaconOrdersGui = RfsBeaconOrdersGui or {}

pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsFarming.lua" )
end )

local LAYOUT = "$CONTENT_DATA/Gui/Layouts/Rfs_BeaconOrders.layout"
local ROWS = 8
local SCROLL_STEP = 1 -- one ally row per wheel/button tick
-- ~0.5s settle after Close before createGui (40Hz ≈ 20 ticks).
local REOPEN_SETTLE_TICKS = 20
local MODE_ITEMS_DEFAULT = { "Rest", "Defend", "Return", "Stay", "Recall" }
local MODE_ITEMS_HAY = { "Rest", "Defend", "Return", "Stay", "Recall", "Farm" }
local MODE_ITEMS_TOTE = { "Rest", "Defend", "Return", "Stay", "Recall", "Collect" }
local MODE_ITEMS_WATER = { "Rest", "Defend", "Return", "Stay", "Recall", "Collect Oil" }
-- Stable superset for all ModeDrop slots. Return stays walk-to-hack-device.
-- Never recreateDropDown while scrolling — that wiped the painted list in 3.5d.
local MODE_ITEMS_ALL = { "Rest", "Defend", "Return", "Stay", "Recall", "Sentry", "Farm", "Collect", "Collect Oil" }

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
-- Survival Seedbot: one character UUID for every crate crop (seedType is unit data).
-- tomato/potato/carrot/redbeet/banana/blueberry/orange/broccoli/pineapple.
-- Cotton + pigmentflower (paint) have no seedbot character — do not invent UUIDs.
local UUID_SEEDBOT_STRS = {
	"4fbefe2d-83c7-4859-982e-1720f04079a3",
}
local UUID_SEEDBOT = UUID_SEEDBOT_STRS[1]
-- HACK 3.5f: icon + number on existing rows (additive paint only).
-- Prefer RFS copies of Survival NodeIcons. Avoid icon_farmraid_compass_bot.png —
-- that sprite itself looks like the red-triangle error placeholder.
-- If every setImage path fails → hide ImageBox and use letter+number (H1/T2).

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
	-- SM DropDown may pass caption, extra whitespace, or a 0/1-based index.
	if type( label ) == "number" then
		local idx = math.floor( label )
		if COLOR_PRESETS[idx] then
			return COLOR_PRESETS[idx].hex
		end
		if idx >= 0 and COLOR_PRESETS[idx + 1] then
			return COLOR_PRESETS[idx + 1].hex
		end
		return nil
	end
	local s = tostring( label or "" ):gsub( "^%s+", "" ):gsub( "%s+$", "" )
	if s == "" then
		return nil
	end
	local lower = string.lower( s )
	for _, p in ipairs( COLOR_PRESETS ) do
		if p.label == s or string.lower( p.label ) == lower then
			return p.hex
		end
	end
	local idx = tonumber( s )
	if idx then
		idx = math.floor( idx )
		if COLOR_PRESETS[idx] then
			return COLOR_PRESETS[idx].hex
		end
		if idx >= 0 and COLOR_PRESETS[idx + 1] then
			return COLOR_PRESETS[idx + 1].hex
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
	if mode == "return" then
		return "Return"
	end
	if mode == "stay" then
		return "Stay"
	end
	if mode == "recall" then
		return "Recall"
	end
	if mode == "sentry" then
		return "Sentry"
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
	if label == "return" or label == "home" then
		return "return"
	end
	if label == "stay" or label == "leash" then
		return "stay"
	end
	if label == "recall" then
		return "recall"
	end
	if label == "sentry" then
		return "sentry"
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
	-- Seed UUID before generic "farm" — crate-tray farmer is Seed, not Farm.
	-- unit_seedbot is often nil in this sandbox; hardcoded UUID strings still match.
	local seedG = rawget( _G, "unit_seedbot" )
	local isSeed = ( seedG and sameUuid( typeRaw, seedG ) ) or false
	for i = 1, #UUID_SEEDBOT_STRS do
		if sameUuid( typeRaw, UUID_SEEDBOT_STRS[i] ) then
			isSeed = true
			break
		end
	end
	if isSeed or string.find( s, "seedbot", 1, true ) or string.find( s, "seed", 1, true ) then
		return "seed"
	end
	if string.find( s, "farmbot", 1, true )
		or ( string.find( s, "farm", 1, true ) and not string.find( s, "farmer", 1, true ) ) then
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

local function typeLetter( kind )
	kind = tostring( kind or "other" )
	if kind == "hay" then return "H" end
	if kind == "tote" then return "T" end
	if kind == "water" then return "W" end
	if kind == "seed" then return "S" end
	if kind == "farmbot" then return "F" end
	if kind == "tape" then return "Tp" end
	if kind == "miner" then return "M" end
	if kind == "cable" then return "C" end
	return "B"
end

local function kindDisplayName( kind )
	kind = tostring( kind or "other" )
	if kind == "hay" then return "Hay" end
	if kind == "tote" then return "Tote" end
	if kind == "water" then return "Water" end
	if kind == "seed" then return "Seed" end
	if kind == "farmbot" then return "Farm" end
	if kind == "tape" then return "Tape" end
	if kind == "miner" then return "Miner" end
	if kind == "cable" then return "Cable" end
	return "Bot"
end

local function rowDisplayIndex( row )
	if not row then
		return nil
	end
	local n = tonumber( row.displayIndex )
	if n then
		return n
	end
	local name = tostring( row.name or "" )
	local num = string.match( name, "(%d+)$" )
	return tonumber( num )
end

local function selectedSet( host )
	host.cl = host.cl or {}
	if type( host.cl.rfsOrdersSelected ) ~= "table" then
		host.cl.rfsOrdersSelected = {}
	end
	return host.cl.rfsOrdersSelected
end

local function isRowSelected( host, key )
	if not key then
		return false
	end
	local set = host.cl and host.cl.rfsOrdersSelected
	return type( set ) == "table" and set[tostring( key )] == true
end

local function listedKeys( host )
	local keys = {}
	for _, row in ipairs( host.cl and host.cl.rfsOrdersRows or {} ) do
		if row and row.key then
			keys[#keys + 1] = tostring( row.key )
		end
	end
	return keys
end

local function pruneSelection( host )
	local set = selectedSet( host )
	local live = {}
	for _, row in ipairs( host.cl.rfsOrdersRows or {} ) do
		if row and row.key then
			live[tostring( row.key )] = true
		end
	end
	for k, _ in pairs( set ) do
		if not live[tostring( k )] then
			set[k] = nil
		end
	end
end

-- Selected keys, or all listed allies if none selected (Color / orders scope).
local function orderTargetKeys( host )
	local set = selectedSet( host )
	local keys = {}
	for k, v in pairs( set ) do
		if v then
			keys[#keys + 1] = tostring( k )
		end
	end
	if #keys > 0 then
		return keys
	end
	return listedKeys( host )
end

local function rowByKey( host, key )
	key = tostring( key or "" )
	for _, row in ipairs( host.cl and host.cl.rfsOrdersRows or {} ) do
		if row and tostring( row.key ) == key then
			return row
		end
	end
	return nil
end

-- Prefer RFS NodeIcon copies, then Survival paths / short names.
local function iconPathsForKind( kind )
	kind = tostring( kind or "other" )
	if kind == "hay" then
		return {
			"$CONTENT_DATA/Gui/Icons/rfs_icon_haybot.png",
			"$SURVIVAL_DATA/Gui/NodeIcons/HaybotIcon.png",
			"HaybotIcon.png",
		}
	end
	if kind == "tote" then
		return {
			"$CONTENT_DATA/Gui/Icons/rfs_icon_totebot.png",
			"$SURVIVAL_DATA/Gui/NodeIcons/TotebotYellowIcon.png",
			"TotebotYellowIcon.png",
		}
	end
	if kind == "water" then
		return {
			"$CONTENT_DATA/Gui/Icons/rfs_icon_waterbot.png",
			"$SURVIVAL_DATA/Gui/NodeIcons/TotebotBlueIcon.png",
			"TotebotBlueIcon.png",
		}
	end
	if kind == "seed" then
		return {
			"$CONTENT_DATA/Gui/Icons/rfs_icon_totebot.png",
			"$SURVIVAL_DATA/Gui/NodeIcons/TotebotYellowIcon.png",
			"TotebotYellowIcon.png",
		}
	end
	if kind == "farmbot" then
		return {
			"$CONTENT_DATA/Gui/Icons/rfs_icon_farmbot.png",
			"$SURVIVAL_DATA/Gui/NodeIcons/FarmbotIcon.png",
			"notification_warning_icon_farmbot.png",
			"icon_farmraid_raidmarkerboticon.png",
			"FarmbotIcon.png",
		}
	end
	if kind == "tape" then
		return {
			"$CONTENT_DATA/Gui/Icons/rfs_icon_tapebot.png",
			"$SURVIVAL_DATA/Gui/NodeIcons/TapebotIcon.png",
			"TapebotIcon.png",
		}
	end
	return {
		"$CONTENT_DATA/Gui/Icons/rfs_icon_bot.png",
		"$SURVIVAL_DATA/Gui/NodeIcons/TotebotYellowIcon.png",
		"icon_farmraid_raidmarkerboticon.png",
	}
end

-- True when setImage pcall accepts a candidate path.
local function setBotIcon( gui, widget, kind )
	local paths = iconPathsForKind( kind )
	for _, path in ipairs( paths ) do
		local ok = pcall( function()
			gui:setImage( widget, path )
		end )
		if ok then
			return true
		end
	end
	return false
end

-- Yellow field: "Seed 1" / "Tote 1". Keep type name even when the icon paints.
local function rowListLabel( row, selected, iconOk )
	local mark = selected and "● " or ""
	local n = rowDisplayIndex( row )
	local kindLabel = kindDisplayName( row and row.kind )
	local name = tostring( row and row.name or "" )
	local nameLabel, nameNum = string.match( name, "^([%a]+)%s+(%d+)$" )
	if nameLabel and nameNum and nameLabel ~= "Bot" then
		return mark .. name
	end
	if n then
		return mark .. kindLabel .. " " .. tostring( n )
	end
	if name ~= "" then
		return mark .. name
	end
	if iconOk then
		return mark .. kindLabel
	end
	return mark .. typeLetter( row and row.kind ) .. tostring( n or "?" )
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
	local scroll = host.cl and host.cl.rfsOrdersScroll or 0
	local abs = scroll + idx + 1
	return rows[abs], abs, idx
end

local function clampScroll( host, rows )
	local n = ( type( rows ) == "table" ) and #rows or 0
	local maxScroll = math.max( 0, n - ROWS )
	local scroll = math.floor( tonumber( host.cl.rfsOrdersScroll ) or 0 )
	if scroll > maxScroll then scroll = maxScroll end
	if scroll < 0 then scroll = 0 end
	host.cl.rfsOrdersScroll = scroll
	return scroll, maxScroll
end

local function syncScrollbar( host, gui, rows )
	local scroll, maxScroll = clampScroll( host, rows )
	-- setSliderData can re-enter the slider callback; ignore that echo.
	host.cl.rfsOrdersIgnoreSlider = true
	pcall( function()
		gui:setSliderData( "ScrollBar", math.max( 1, maxScroll + 1 ), scroll )
	end )
	host.cl.rfsOrdersIgnoreSlider = nil
	local n = #rows
	local first = ( n == 0 ) and 0 or ( scroll + 1 )
	local last = math.min( n, scroll + ROWS )
	pcall( function()
		if n == 0 then
			gui:setText( "ScrollLabel", "Allies 0" )
		elseif maxScroll <= 0 then
			gui:setText( "ScrollLabel", string.format( "Allies %d", n ) )
		else
			gui:setText( "ScrollLabel", string.format( "Allies %d-%d / %d", first, last, n ) )
		end
	end )
	return scroll, maxScroll
end

local function paintSlot( gui, host, i, row )
	local nameW = "BotName" .. i
	local iconW = "BotIcon" .. i
	local soonW = "Soon" .. i
	local dropW = "ModeDrop" .. i
	local seedW = "SeedDrop" .. i
	if not row then
		pcall( function() gui:setVisible( iconW, false ) end )
		pcall( function() gui:setText( nameW, "" ) end )
		pcall( function() gui:setText( soonW, "" ) end )
		pcall( function() gui:setVisible( nameW, false ) end )
		pcall( function() gui:setVisible( soonW, false ) end )
		-- Hide dropdowns for empty window slots. Safe because we never
		-- createDropDown again after bind (that combo wiped the list in 3.5d).
		pcall( function() gui:setVisible( dropW, false ) end )
		pcall( function() gui:setVisible( seedW, false ) end )
		return
	end
	local isSel = isRowSelected( host, row.key )
	-- Paint label first so a failed icon never leaves an empty row.
	local iconOk = false
	pcall( function() gui:setText( nameW, rowListLabel( row, isSel, false ) ) end )
	pcall( function() gui:setVisible( nameW, true ) end )
	-- Additive icon paint only — never recreateDropDown here.
	iconOk = setBotIcon( gui, iconW, row.kind )
	if iconOk then
		pcall( function() gui:setVisible( iconW, true ) end )
		pcall( function() gui:setText( nameW, rowListLabel( row, isSel, true ) ) end )
	else
		pcall( function() gui:setVisible( iconW, false ) end )
	end
	pcall( function() gui:setVisible( dropW, true ) end )
	-- Selection only — dropdown item list is fixed at bind (MODE_ITEMS_ALL).
	pcall( function()
		gui:setSelectedDropDownItem( dropW, modeLabel( row.mode ) )
	end )
	local showSeed = ( row.kind == "hay" and row.mode == "farm" )
	if showSeed then
		pcall( function() gui:setText( soonW, "" ) end )
		pcall( function() gui:setVisible( soonW, false ) end )
		pcall( function() gui:setVisible( seedW, true ) end )
		pcall( function()
			gui:setSelectedDropDownItem( seedW, seedLabelForUuid( row.seedUuid ) )
		end )
	else
		pcall( function() gui:setVisible( seedW, false ) end )
		local soon = soonText( row.kind )
		pcall( function() gui:setText( soonW, soon ) end )
		pcall( function() gui:setVisible( soonW, soon ~= "" ) end )
	end
end

-- In-place list paint from cached rfsOrdersRows. Scroll only changes offset.
-- Never destroy GUI, never clear ally rows, never createDropDown here.
function RfsBeaconOrdersGui.refresh( host )
	local gui = host.cl and host.cl.rfsOrdersGui
	if not gui then
		return
	end

	-- Same table reference — never replace/clear on scroll paint.
	local rows = host.cl.rfsOrdersRows
	if type( rows ) ~= "table" then
		rows = {}
		host.cl.rfsOrdersRows = rows
	end
	local scroll = syncScrollbar( host, gui, rows )

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
	pcall( function()
		gui:setText( "Status", string.format(
			"%s — %d ally(ies) | %s | key %s",
			tostring( beaconName ),
			#rows,
			roleTxt,
			tostring( key )
		) )
	end )
	pcall( function()
		gui:setText( "RoleLabel", "Role: " .. roleTxt )
	end )
	pcall( function()
		if role == "master" then
			gui:setText( "BtnMaster", "CLEAR MASTER" )
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

	pruneSelection( host )
	local names = {}
	for _, r in ipairs( rows ) do
		if r and isRowSelected( host, r.key ) then
			names[#names + 1] = rowListLabel( r, false, true )
		end
	end
	pcall( function()
		if #names == 0 then
			gui:setText( "ColorSelLabel", "None selected — applies to all" )
		elseif #names == 1 then
			gui:setText( "ColorSelLabel", "Selected: " .. names[1] )
		else
			gui:setText( "ColorSelLabel", "Selected: " .. table.concat( names, ", " ) )
		end
	end )

	-- Suppress Mode/Seed drop callbacks while we push selections into widgets.
	host.cl.rfsOrdersSuppressDrop = true
	for i = 0, ROWS - 1 do
		local abs = scroll + i + 1
		paintSlot( gui, host, i, rows[abs] )
	end
	host.cl.rfsOrdersSuppressDrop = nil
end

-- Scroll offset + in-place refresh only. Never open/close/clear rows / applyList.
function RfsBeaconOrdersGui.scrollDelta( host, delta )
	host.cl = host.cl or {}
	if not host.cl.rfsOrdersGui then
		return
	end
	local rows = host.cl.rfsOrdersRows or {}
	local maxScroll = math.max( 0, #rows - ROWS )
	if maxScroll <= 0 then
		return
	end
	local nextScroll = ( tonumber( host.cl.rfsOrdersScroll ) or 0 ) + ( tonumber( delta ) or 0 )
	if nextScroll < 0 then nextScroll = 0 end
	if nextScroll > maxScroll then nextScroll = maxScroll end
	if nextScroll == ( tonumber( host.cl.rfsOrdersScroll ) or 0 ) then
		return
	end
	host.cl.rfsOrdersScroll = nextScroll
	RfsBeaconOrdersGui.refresh( host )
end

-- Legacy name used by older Game.lua wiring; maps to one-row scroll steps.
function RfsBeaconOrdersGui.pageDelta( host, delta )
	RfsBeaconOrdersGui.scrollDelta( host, delta )
end

function RfsBeaconOrdersGui.onScrollChanged( host, pos )
	host.cl = host.cl or {}
	if host.cl.rfsOrdersIgnoreSlider then
		return
	end
	if not host.cl.rfsOrdersGui then
		return
	end
	local rows = host.cl.rfsOrdersRows or {}
	local maxScroll = math.max( 0, #rows - ROWS )
	local scroll = math.floor( tonumber( pos ) or 0 )
	if scroll < 0 then scroll = 0 end
	if scroll > maxScroll then scroll = maxScroll end
	if scroll == ( tonumber( host.cl.rfsOrdersScroll ) or 0 ) then
		return
	end
	host.cl.rfsOrdersScroll = scroll
	RfsBeaconOrdersGui.refresh( host )
end

function RfsBeaconOrdersGui.onMouseWheel( host, scrollValue )
	local v = tonumber( scrollValue ) or 0
	if v == 0 then
		return
	end
	-- positive wheel = scroll up (earlier allies)
	RfsBeaconOrdersGui.scrollDelta( host, ( v > 0 ) and -SCROLL_STEP or SCROLL_STEP )
end

-- Callbacks only. Do not createDropDown / setVisible-hide rows here — that ran
-- before gui:open() and left cursor capture with no drawn window.
function RfsBeaconOrdersGui.bind( host, gui )
	host.cl = host.cl or {}
	host.cl.rfsOrdersGui = gui
	host.cl.rfsOrdersScroll = host.cl.rfsOrdersScroll or 0
	host.cl.rfsOrdersRows = host.cl.rfsOrdersRows or {}
	host.cl.rfsOrdersDropsBound = nil

	-- Game-hosted callbacks (GUI opened on RecipeFrameworkSurvival).
	-- Separate OnClose so CloseButton → close() does not re-enter close.
	gui:setButtonCallback( "CloseButton", "cl_rfs_ordersClose" )
	gui:setButtonCallback( "BtnScrollUp", "cl_rfs_ordersScrollUp" )
	gui:setButtonCallback( "BtnScrollDown", "cl_rfs_ordersScrollDown" )
	gui:setButtonCallback( "BtnMaster", "cl_rfs_ordersMaster" )
	gui:setButtonCallback( "BtnRange", "cl_rfs_ordersRange" )
	gui:setButtonCallback( "BtnRename", "cl_rfs_ordersRename" )
	pcall( function()
		gui:setSliderCallback( "ScrollBar", "cl_rfs_ordersScrollChanged" )
	end )
	-- Best-effort mouse-wheel (safe if API unsupported).
	pcall( function()
		gui:setMouseWheelCallback( "MainPanel", "cl_rfs_ordersMouseWheel" )
	end )
	pcall( function()
		gui:setMouseWheelCallback( "ScrollBar", "cl_rfs_ordersMouseWheel" )
	end )
	gui:setOnCloseCallback( "cl_rfs_ordersOnClosed" )

	for i = 0, ROWS - 1 do
		pcall( function()
			gui:setButtonCallback( "BotName" .. i, "cl_rfs_ordersBot" .. i )
		end )
	end
end

-- First show only, AFTER gui:open(). Never call from refresh / scroll / paint.
local function bindDropDowns( host, gui )
	if not gui or host.cl.rfsOrdersDropsBound then
		return
	end
	host.cl.rfsOrdersDropsBound = true
	local seeds = seedLabels()
	local colors = colorLabels()
	-- Suppress before ColorDrop create/select — setSelectedDropDownItem fires
	-- the callback, and applying Ally Green on every open looked like Color was dead.
	host.cl.rfsOrdersSuppressDrop = true
	pcall( function()
		gui:createDropDown( "ColorDrop", "cl_rfs_ordersColor", colors )
	end )
	pcall( function()
		gui:setSelectedDropDownItem( "ColorDrop", "Ally Green" )
	end )
	for i = 0, ROWS - 1 do
		pcall( function()
			gui:createDropDown( "ModeDrop" .. i, "cl_rfs_ordersDrop" .. i, MODE_ITEMS_ALL )
		end )
		pcall( function()
			gui:createDropDown( "SeedDrop" .. i, "cl_rfs_ordersSeed" .. i, seeds )
		end )
		pcall( function()
			gui:setVisible( "SeedDrop" .. i, false )
		end )
	end
	host.cl.rfsOrdersSuppressDrop = nil
end

local function applyOpenMeta( host, opts )
	host.cl = host.cl or {}
	host.cl.rfsOrdersBeaconKey = tostring( opts.beaconKey )
	host.cl.rfsOrdersBeaconName = opts.beaconName or host.cl.rfsOrdersBeaconName or "Hack Beacon"
	host.cl.rfsOrdersRole = opts.role or host.cl.rfsOrdersRole or "independent"
	if opts.masterKey ~= nil then
		host.cl.rfsOrdersMasterKey = opts.masterKey
	end
	if opts.range ~= nil then
		host.cl.rfsOrdersRange = tonumber( opts.range ) or host.cl.rfsOrdersRange or 16
	end
	if type( opts.pos ) == "table" and opts.pos.x ~= nil then
		host.cl.rfsOrdersBeaconPos = {
			x = tonumber( opts.pos.x ) or 0,
			y = tonumber( opts.pos.y ) or 0,
			z = tonumber( opts.pos.z ) or 0,
		}
	end
end

local function currentTick()
	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick() or 0
	end )
	return tick
end

-- Only used after Close settle: delay createGui until the old window is dead.
function RfsBeaconOrdersGui.queueOpen( host, opts )
	host.cl = host.cl or {}
	opts = opts or {}
	if not opts.beaconKey then
		return
	end
	local tick = currentTick()
	local settle = tonumber( host.cl.rfsOrdersReopenAfterTick ) or 0
	local atTick = tick
	if settle > atTick then
		atTick = settle
	end
	host.cl.rfsOrdersOpenGen = ( tonumber( host.cl.rfsOrdersOpenGen ) or 0 ) + 1
	host.cl.rfsPendingOrdersGui = {
		data = opts,
		atTick = atTick,
		gen = host.cl.rfsOrdersOpenGen,
	}
end

-- 3.5e/3.5f: create → bind callbacks → open → dropdowns (first show) → refresh.
-- Host MUST be Game so Close/Master/Color callbacks resolve. No schedule maze.
function RfsBeaconOrdersGui.open( host, opts )
	opts = opts or {}
	if not opts.beaconKey then
		sm.gui.chatMessage( "[RFS] Orders: missing beacon key" )
		return
	end

	host.cl = host.cl or {}
	local tick = currentTick()
	local settle = tonumber( host.cl.rfsOrdersReopenAfterTick ) or 0
	if tick < settle then
		RfsBeaconOrdersGui.queueOpen( host, opts )
		return
	end

	if host.cl.rfsOrdersGui then
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

	-- Compare before applyOpenMeta overwrites the key (keeps cached rows on reopen).
	local prevKey = host.cl.rfsOrdersBeaconKey
	local sameBeacon = prevKey and opts.beaconKey
		and tostring( prevKey ) == tostring( opts.beaconKey )
	applyOpenMeta( host, opts )
	host.cl.rfsOrdersRange = tonumber( opts.range ) or host.cl.rfsOrdersRange or 16
	host.cl.rfsOrdersScroll = 0
	host.cl.rfsOrdersSelected = {}
	host.cl.rfsOrdersSelectedKey = nil
	if type( opts.rows ) == "table" and #opts.rows > 0 then
		host.cl.rfsOrdersRows = {}
		for _, row in ipairs( opts.rows ) do
			if row and row.key then
				host.cl.rfsOrdersRows[#host.cl.rfsOrdersRows + 1] = row
			end
		end
	elseif not sameBeacon then
		host.cl.rfsOrdersRows = {}
	else
		-- Reopen same beacon: keep prior ally cache (3.5c list fill).
		host.cl.rfsOrdersRows = host.cl.rfsOrdersRows or {}
	end
	host.cl.rfsPendingOrdersGui = nil
	host.cl.rfsOrdersReopenAfterTick = nil
	host.cl.rfsOrdersDropsBound = nil

	RfsBeaconOrdersGui.bind( host, gui )
	gui:open()
	bindDropDowns( host, gui )
	RfsBeaconOrdersGui.refresh( host )
	pcall( function()
		sm.gui.chatMessage( "[RFS] Orders opened (HACK 3.5f)" )
	end )

	if type( opts.rows ) == "table" and #opts.rows > 0 then
		RfsBeaconOrdersGui.applyList( host, {
			rows = opts.rows,
			beaconKey = opts.beaconKey,
			beaconName = opts.beaconName,
			role = opts.role,
			masterKey = opts.masterKey,
		} )
	elseif #( host.cl.rfsOrdersRows or {} ) == 0 and host.network and host.network.sendToServer then
		host.network:sendToServer( "sv_rfs_ordersList", {
			beaconKey = host.cl.rfsOrdersBeaconKey,
		} )
	end
end

-- Close: nil ref first (OnClose no-op), engine close, then ~0.5s reopen settle.
function RfsBeaconOrdersGui.close( host )
	host.cl = host.cl or {}
	destroyHostRangeRing( host )
	local gui = host.cl.rfsOrdersGui
	host.cl.rfsOrdersGui = nil
	host.cl.rfsPendingOrdersGui = nil
	host.cl.rfsOrdersDropsBound = nil
	host.cl.rfsOrdersReopenAfterTick = currentTick() + REOPEN_SETTLE_TICKS
	if gui then
		pcall( function() gui:close() end )
	end
end

-- Engine OnClose only — do not re-enter close or clear a queued reopen.
function RfsBeaconOrdersGui.onClosed( host )
	host.cl = host.cl or {}
	host.cl.rfsOrdersGui = nil
	host.cl.rfsOrdersDropsBound = nil
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

-- Soft range toggle: never destroy Orders GUI. Draw from Game (no beacon FX host).
function RfsBeaconOrdersGui.toggleRange( host )
	host.cl = host.cl or {}
	local gui = host.cl.rfsOrdersGui
	local key = host.cl.rfsOrdersBeaconKey
	if not key then
		return
	end
	key = tostring( key )
	_G.g_rfsBeaconRangeVisible = _G.g_rfsBeaconRangeVisible or {}
	local on = not ( _G.g_rfsBeaconRangeVisible[key] == true )
	_G.g_rfsBeaconRangeVisible[key] = on
	host.cl.rfsOrdersShowRange = on
	-- Immediate Game-client ring. Do not wait for beacon sandbox / g_rfsGame.
	host.cl.rfsRangeWant = host.cl.rfsRangeWant or {}
	local pos = host.cl.rfsOrdersBeaconPos
	if on and type( pos ) == "table" and pos.x ~= nil then
		host.cl.rfsRangeWant[key] = {
			key = key,
			show = true,
			range = tonumber( host.cl.rfsOrdersRange ) or 16,
			pos = { x = pos.x, y = pos.y, z = pos.z },
		}
	else
		host.cl.rfsRangeWant[key] = { key = key, show = false }
	end
	if host.network and host.network.sendToServer then
		pcall( function()
			host.network:sendToServer( "sv_rfs_ordersRange", {
				beaconKey = key,
				show = on,
				range = tonumber( host.cl.rfsOrdersRange ) or 16,
				pos = ( type( pos ) == "table" and pos.x ~= nil ) and {
					x = pos.x, y = pos.y, z = pos.z,
				} or nil,
			} )
		end )
	end
	if gui then
		pcall( function()
			gui:setText( "BtnRange", on and "HIDE RANGE" or "SHOW RANGE" )
		end )
	end
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
	-- Only replace the ally cache when a real rows table arrives.
	-- Never clear on nil/missing data (scroll must never lose N allies).
	if type( data ) == "table" and type( data.rows ) == "table" then
		local nextRows = {}
		for _, row in ipairs( data.rows ) do
			if row and row.key then
				local kind = botKind( row.unitType or row.type, row.name )
				local mode = modeValue( row.mode )
				if mode == "farm" and kind ~= "hay" then
					mode = "rest"
				end
				if mode == "collect" and kind ~= "tote" then
					mode = "rest"
				end
				if mode == "oil" and kind ~= "water" then
					mode = "rest"
				end
				if mode == "return" then
					mode = "return"
				end
				local n = tonumber( row.displayIndex )
				if not n then
					n = tonumber( string.match( tostring( row.name or "" ), "(%d+)$" ) )
				end
				local typeName = kindDisplayName( kind )
				local name = tostring( row.name or "" )
				local nameLabel = string.match( name, "^([%a]+)%s+%d+$" )
				if name == "" or nameLabel == "Bot" or string.match( name, "^%d+$" ) then
					name = n and ( typeName .. " " .. tostring( n ) ) or typeName
				end
				nextRows[#nextRows + 1] = {
					key = tostring( row.key ),
					name = name,
					displayIndex = n,
					unitType = row.unitType or row.type,
					kind = kind,
					mode = mode,
					seedUuid = row.seedUuid and tostring( row.seedUuid ) or nil,
					owner = row.owner,
					allyColor = row.allyColor and tostring( row.allyColor ) or nil,
					hackBeaconKey = row.hackBeaconKey and tostring( row.hackBeaconKey ) or nil,
				}
			end
		end
		host.cl.rfsOrdersRows = nextRows
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
	if data and data.beaconKey and not host.cl.rfsOrdersBeaconKey then
		host.cl.rfsOrdersBeaconKey = tostring( data.beaconKey )
	end
	if host.cl.rfsOrdersGui then
		RfsBeaconOrdersGui.refresh( host )
	end
end

function RfsBeaconOrdersGui.onBotClick( host, rowIdx )
	host.cl = host.cl or {}
	local rows = host.cl.rfsOrdersRows or {}
	local scroll = host.cl.rfsOrdersScroll or 0
	local abs = scroll + ( tonumber( rowIdx ) or 0 ) + 1
	local row = rows[abs]
	if not row or not row.key then
		return
	end
	local key = tostring( row.key )
	local set = selectedSet( host )
	if set[key] then
		set[key] = nil
	else
		set[key] = true
	end
	host.cl.rfsOrdersSelectedKey = nil
	for k, v in pairs( set ) do
		if v then
			host.cl.rfsOrdersSelectedKey = k
			break
		end
	end
	RfsBeaconOrdersGui.refresh( host )
end

function RfsBeaconOrdersGui.onColorDrop( host, value )
	host.cl = host.cl or {}
	if host.cl.rfsOrdersSuppressDrop then
		return
	end
	local hex = colorHexForLabel( value )
	if not hex then
		return
	end
	local beaconKey = host.cl.rfsOrdersBeaconKey
	if not beaconKey then
		return
	end
	host.cl.rfsOrdersColorLabel = colorLabelForHex( hex ) or tostring( value )
	local keys = orderTargetKeys( host )
	host.network:sendToServer( "sv_rfs_ordersSetColor", {
		beaconKey = beaconKey,
		unitKey = nil,
		unitKeys = keys,
		colorHex = hex,
		colorLabel = tostring( value ),
	} )
	local nSel = 0
	for _, v in pairs( selectedSet( host ) ) do
		if v then
			nSel = nSel + 1
		end
	end
	local scope = ( nSel > 0 ) and ( tostring( nSel ) .. " selected" ) or "all listed allies"
	local pretty = colorLabelForHex( hex ) or tostring( value )
	sm.gui.chatMessage( "[RFS] Color " .. tostring( pretty ) .. " → " .. scope )
end

function RfsBeaconOrdersGui.onRename( host )
	host.cl = host.cl or {}
	local gui = host.cl.rfsOrdersGui
	local name = ""
	pcall( function()
		name = gui:getText( "NameEdit" )
	end )
	name = tostring( name or "" ):gsub( "^%s+", "" ):gsub( "%s+$", "" )
	if name == "" then
		sm.gui.chatMessage( "[RFS] Type a name in the Name box, select bots, then RENAME." )
		return
	end
	local keys = orderTargetKeys( host )
	if #keys == 0 then
		sm.gui.chatMessage( "[RFS] No allies to rename." )
		return
	end
	host.network:sendToServer( "sv_rfs_ordersRename", {
		name = name,
		unitKeys = keys,
	} )
end

function RfsBeaconOrdersGui.onModeDrop( host, rowIdx, value )
	if host.cl and host.cl.rfsOrdersSuppressDrop then
		return
	end
	local rows = host.cl and host.cl.rfsOrdersRows or {}
	local scroll = host.cl and host.cl.rfsOrdersScroll or 0
	local abs = scroll + ( tonumber( rowIdx ) or 0 ) + 1
	local clicked = rows[abs]
	if not clicked or not clicked.key then
		return
	end
	local mode = modeValue( value )
	local keys = orderTargetKeys( host )
	if #keys == 0 then
		keys = { tostring( clicked.key ) }
	end
	local beaconKey = host.cl.rfsOrdersBeaconKey
	local sent = 0
	for _, k in ipairs( keys ) do
		local row = rowByKey( host, k ) or clicked
		if mode == "farm" and row.kind ~= "hay" then
			-- keep Farm/Collect/Oil disable rules
		elseif mode == "collect" and row.kind ~= "tote" then
		elseif mode == "oil" and row.kind ~= "water" then
		else
			if mode == "farm" and not row.seedUuid then
				local uuid = seedUuidForLabel( "Tomato" )
				row.seedUuid = uuid and tostring( uuid ) or nil
			end
			row.mode = mode
			host.network:sendToServer( "sv_rfs_ordersSet", {
				unitKey = k,
				mode = mode,
				seedUuid = row.seedUuid,
				beaconKey = beaconKey,
			} )
			sent = sent + 1
		end
	end
	if sent > 0 then
		RfsBeaconOrdersGui.refresh( host )
	end
end

function RfsBeaconOrdersGui.onSeedDrop( host, rowIdx, value )
	if host.cl and host.cl.rfsOrdersSuppressDrop then
		return
	end
	local rows = host.cl and host.cl.rfsOrdersRows or {}
	local scroll = host.cl and host.cl.rfsOrdersScroll or 0
	local abs = scroll + ( tonumber( rowIdx ) or 0 ) + 1
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
RfsBeaconOrdersGui.SCROLL_STEP = SCROLL_STEP
RfsBeaconOrdersGui.REOPEN_SETTLE_TICKS = REOPEN_SETTLE_TICKS
RfsBeaconOrdersGui.modeLabel = modeLabel
RfsBeaconOrdersGui.modeValue = modeValue
RfsBeaconOrdersGui.botKind = botKind
RfsBeaconOrdersGui.COLOR_PRESETS = COLOR_PRESETS
RfsBeaconOrdersGui.colorHexForLabel = colorHexForLabel
RfsBeaconOrdersGui.colorLabelForHex = colorLabelForHex
