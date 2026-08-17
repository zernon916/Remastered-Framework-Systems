-- RfsHud.lua — always-on top-center clock + compass HUD for Recipe Framework Survival
-- Author: DemonsDen126
-- Original clock + compass HUD implementation.
-- Tool ammo readout restored here: this always-on HUD sits on the default HUD layer
-- and hides the engine weapon ammo number, so we draw remaining ammo ourselves.
-- Phase 6 Map (Nutt): MiniMap uses the upper-left corner (off chat); ammo stays lower-right.

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

local function updateAmmo( gui )
	local ammoUuid = nil
	pcall( function()
		local item = sm.localPlayer.getActiveItem()
		if item then
			ammoUuid = AMMO_BY_TOOL[string.lower( tostring( item ) )]
		end
	end )
	if not ammoUuid then
		pcall( function() gui:setVisible( "RfsAmmoPanel", false ) end )
		return
	end
	local count = 0
	pcall( function()
		local inv = sm.localPlayer.getInventory()
		if inv then
			count = sm.container.totalQuantity( inv, ammoUuid ) or 0
		end
	end )
	pcall( function()
		gui:setVisible( "RfsAmmoPanel", true )
		gui:setText( "RfsAmmoText", tostring( count ) )
	end )
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

function RfsHud.ensure( host )
	host.cl = host.cl or {}
	if host.cl.rfsHud then
		return host.cl.rfsHud
	end
	-- Middle layer keeps clock/compass/ammo above the MiniMap ring HUD.
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
	print( "[RFS] HUD opened (clock + compass + ammo)" )
	return gui
end

function RfsHud.update( host )
	local gui = RfsHud.ensure( host )
	if not gui then
		return
	end

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
end
