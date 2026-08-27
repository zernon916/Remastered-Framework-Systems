-- RfsHud.lua — always-on top-center clock + compass HUD for Recipe Framework Survival
-- Author: DemonsDen126
-- Original clock + compass HUD implementation.
-- Tool ammo readout restored here: this always-on HUD sits on the default HUD layer
-- and hides the engine weapon ammo number, so we draw remaining ammo ourselves.
-- Ammo sits on the selected hotbar action slot (outlined). Hidden while seated (vehicle later).

pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsRecharge.lua" )
end )

RfsHud = RfsHud or {}

local LAYOUT = "$CONTENT_DATA/Gui/Layouts/Rfs_Hud.layout"
local CARDINALS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

-- Vanilla Survival tool UUIDs → ammo item UUID (spudgun/gatling/shotgun = potatoes).
local POTATO = sm.uuid.new( "bfcfac34-db0f-42d6-bd0c-74a7a5c95e82" )
local FIREAMMO = sm.uuid.new( "68a58472-368d-4b09-ad36-9093f11d76ae" )
local CLAY = sm.uuid.new( "6395a2f1-4169-4a7e-be15-a9864cb6ce7e" )
local EXTINGUISHER = sm.uuid.new( "d2fab7ef-21db-4681-a22a-cd4f278fc355" )
local AMMO_BY_TOOL = {
	["c5ea0c2f-185b-48d6-b4df-45c386a575cc"] = POTATO,       -- Spud Gun
	["f6250bf4-9726-406f-a29a-945c06e460e5"] = POTATO,       -- Spud Shotgun
	["9fde0601-c2ba-4c70-8d5c-2a7a9fdd122b"] = POTATO,       -- Potato Gatling
	["d51ec758-057b-4263-bd16-7a731e149480"] = POTATO,       -- Scrap Spud Gun
	["a2a2bb33-a841-4b23-88da-b758063d9206"] = FIREAMMO,     -- Spud Launcher
	["6993e5df-6852-4e84-88ae-df49f765e784"] = CLAY,         -- Clay Gun
	["2c7e0586-2534-44cc-9f4b-e28c436446b6"] = EXTINGUISHER, -- Extinguisher
}

local function compassFromDirection( dir )
	if not dir then
		return "—"
	end
	local x, y = dir.x or 0, dir.y or 0
	local len = math.sqrt( x * x + y * y )
	if len < 1e-5 then
		return "—"
	end
	x, y = x / len, y / len
	-- Scrap Mechanic: +Y is forward/north on the horizontal plane.
	local deg = math.deg( math.atan2( x, y ) )
	if deg < 0 then
		deg = deg + 360
	end
	local idx = math.floor( ( deg + 22.5 ) / 45 ) % 8 + 1
	return string.format( "%s %d°", CARDINALS[idx], math.floor( deg + 0.5 ) % 360 )
end

local HOTBAR_SLOTS = 10

local function hideAllAmmoSlots( gui )
	for i = 0, HOTBAR_SLOTS - 1 do
		pcall( function() gui:setVisible( "RfsAmmoSlot" .. i, false ) end )
		-- Legacy corner panel name (pre-hotbar layout).
		pcall( function() gui:setVisible( "RfsAmmoPanel", false ) end )
	end
end

local function playerInVehicle()
	local seated = false
	pcall( function()
		local player = sm.localPlayer.getPlayer()
		local char = player and player.character
		if char and sm.exists( char ) and char.getLockingInteractable then
			local ia = char:getLockingInteractable()
			seated = ia ~= nil and sm.exists( ia )
		end
	end )
	return seated
end

local function selectedHotbarSlotIndex()
	local slot = 0
	pcall( function()
		slot = tonumber( sm.localPlayer.getSelectedHotbarSlot() ) or 0
	end )
	slot = math.floor( slot )
	-- Survival hotbar indices are 0..9. If a build returns 1..10, normalize.
	if slot == HOTBAR_SLOTS then
		slot = HOTBAR_SLOTS - 1
	elseif slot > HOTBAR_SLOTS - 1 then
		slot = slot % HOTBAR_SLOTS
	elseif slot < 0 then
		slot = 0
	end
	return slot
end

local function updateAmmo( gui )
	hideAllAmmoSlots( gui )
	if playerInVehicle() then
		return
	end
	local ammoUuid = nil
	pcall( function()
		local item = sm.localPlayer.getActiveItem()
		if item then
			ammoUuid = AMMO_BY_TOOL[string.lower( tostring( item ) )]
		end
	end )
	if not ammoUuid then
		return
	end
	local count = 0
	pcall( function()
		local inv = sm.localPlayer.getInventory()
		if inv then
			count = sm.container.totalQuantity( inv, ammoUuid ) or 0
		end
	end )
	local slot = selectedHotbarSlotIndex()
	pcall( function()
		gui:setVisible( "RfsAmmoSlot" .. slot, true )
		gui:setText( "RfsAmmoText" .. slot, tostring( count ) )
	end )
end

local function updateChargeBar( gui )
	local frac = nil
	pcall( function()
		if type( RfsRecharge ) == "table" and RfsRecharge.heldChargeFrac then
			frac = RfsRecharge.heldChargeFrac()
		end
	end )
	if frac == nil then
		local item = nil
		pcall( function()
			item = sm.localPlayer.getActiveItem()
		end )
		local s = string.lower( tostring( item or "" ) )
		if string.find( s, "a0d8469f-c618-425b-de14-06203d7e90c1", 1, true ) then
			frac = 1
		elseif string.find( s, "8b513e7d-a4f6-4039-bc82-e3f70a4b6d9e", 1, true ) then
			frac = 0
		end
	end
	if frac == nil then
		pcall( function()
			gui:setVisible( "RfsChargePanel", false )
		end )
		return
	end
	local pct = 0
	pcall( function()
		gui:setVisible( "RfsChargePanel", true )
	end )
	if type( RfsRecharge ) == "table" and RfsRecharge.applyChargePips then
		pct = RfsRecharge.applyChargePips( gui, "RfsChargePip", frac )
	else
		pct = math.floor( ( tonumber( frac ) or 0 ) * 100 + 0.5 )
		for i = 0, 9 do
			pcall( function()
				gui:setVisible( "RfsChargePip" .. tostring( i ), i < math.floor( ( tonumber( frac ) or 0 ) * 10 ) )
			end )
		end
	end
	pcall( function()
		gui:setText( "RfsChargeLabel", string.format( "Charge %d%%", pct ) )
	end )
end

local function updatePaintBar( gui )
	local state = nil
	pcall( function()
		if type( RfsPaintTool ) == "table" and RfsPaintTool.cl_paintChargeHudState then
			state = RfsPaintTool.cl_paintChargeHudState()
		end
	end )
	if type( state ) ~= "table" then
		pcall( function()
			gui:setVisible( "RfsPaintPanel", false )
		end )
		return
	end
	local frac = tonumber( state.frac ) or ( ( tonumber( state.charges ) or 0 ) / 100 )
	if frac < 0 then
		frac = 0
	elseif frac > 1 then
		frac = 1
	end
	local filled = 0
	local pct = math.floor( frac * 100 + 0.5 )
	pcall( function()
		if type( RfsRecharge ) == "table" and RfsRecharge.chargePips then
			filled, pct = RfsRecharge.chargePips( frac )
		else
			filled = math.floor( frac * 10 + 0.0001 )
		end
	end )
	local col = nil
	pcall( function()
		if type( RfsPaintPalette ) == "table" and RfsPaintPalette.colorFromHex then
			col = RfsPaintPalette.colorFromHex( state.hex )
		end
	end )
	if not col then
		pcall( function()
			col = sm.color.new( "ffffff" )
		end )
	end
	pcall( function()
		gui:setVisible( "RfsPaintPanel", true )
		gui:setText( "RfsPaintLabel", string.format( "Ink %d%%", pct ) )
	end )
	for i = 0, 9 do
		local name = "RfsPaintPip" .. tostring( i )
		local on = i < filled
		pcall( function()
			gui:setVisible( name, on )
		end )
		if on then
			pcall( function()
				gui:setButtonState( name, true )
				if col then
					gui:setColor( name, col )
				end
			end )
		else
			pcall( function()
				gui:setButtonState( name, false )
			end )
		end
	end
end

local function updateGrowTable( gui )
	-- Plant timer HUD retired — Farmers Tablet owns grow times.
	pcall( function() gui:setVisible( "RfsGrowPanel", false ) end )
end

local function updateBlockOverlay( gui, host )
	local text = host and host.cl and host.cl.rfsBlockHud
	if type( text ) ~= "string" or text == "" then
		pcall( function() gui:setVisible( "RfsOverlayPanel", false ) end )
		return
	end
	pcall( function()
		gui:setVisible( "RfsOverlayPanel", true )
		gui:setText( "RfsOverlayText", text )
	end )
end

local function updateGameMode( gui )
	local snap = type( RfsGameMode ) == "table" and RfsGameMode.snapshot and RfsGameMode.snapshot() or nil
	if type( snap ) ~= "table" or snap.locked == true or snap.countdownActive ~= true then
		pcall( function() gui:setVisible( "RfsGameModePanel", false ) end )
		return
	end
	local remaining = math.max( 0, math.floor( tonumber( snap.lockRemainingSec ) or 0 ) )
	local mins = math.floor( remaining / 60 )
	local secs = remaining % 60
	local label = tostring( snap.modeLabel or "Normal" )
	if snap.hardcore then
		label = label .. " Hardcore"
	end
	pcall( function()
		gui:setVisible( "RfsGameModePanel", true )
		gui:setText( "RfsGameModeText", string.format( "%s locks in %02d:%02d", label, mins, secs ) )
	end )
end

function RfsHud.ensure( host )
	host.cl = host.cl or {}
	if host.cl.rfsHud then
		return host.cl.rfsHud
	end
	-- Middle layer keeps clock/compass/hotbar-ammo above the MiniMap ring HUD.
	local ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT, false, {
		isHud = true,
		isInteractive = false,
		needsCursor = false,
		layer = "Middle"
	} )
	if not ok or not gui then
		ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT, false, {
			isHud = true,
			isInteractive = false,
			needsCursor = false
		} )
	end
	if not ok or not gui then
		print( "[RFS] HUD create failed: " .. tostring( gui ) )
		return nil
	end
	host.cl.rfsHud = gui
	pcall( function() gui:open() end )
	print( "[RFS] HUD opened (clock + compass + hotbar ammo)" )
	return gui
end

function RfsHud.update( host )
	local gui = RfsHud.ensure( host )
	if not gui then
		return
	end

	-- Hide RFS HUD while Farmers Tablet (or similar fullscreen tool UI) is open.
	if _G.g_rfsFarmTabletOpen == true then
		pcall( function() gui:setHidden( true ) end )
		return
	end
	pcall( function() gui:setHidden( false ) end )

	local clock = "00:00"
	pcall( function()
		if getTimeOfDayString then
			clock = tostring( getTimeOfDayString() )
		elseif sm.game.getTimeOfDay then
			local tod = sm.game.getTimeOfDay() or 0
			local hour = ( tod * 24 ) % 24
			local minute = math.floor( ( hour % 1 ) * 60 )
			hour = math.floor( hour )
			clock = string.format( "%02d:%02d", hour, minute )
		end
	end )
	pcall( function() gui:setText( "RfsClockText", clock ) end )

	local compass = "—"
	local player = host.player
	if player and sm.exists( player ) then
		local character = player.character
		if character and sm.exists( character ) then
			local ok, dir = pcall( function() return character:getDirection() end )
			if ok then
				compass = compassFromDirection( dir )
			end
		end
	end
	pcall( function() gui:setText( "RfsCompassText", compass ) end )
	updateAmmo( gui )
	updateBlockOverlay( gui, host )
	updateGameMode( gui )
	updateChargeBar( gui )
	updatePaintBar( gui )
	updateGrowTable( gui )
end
