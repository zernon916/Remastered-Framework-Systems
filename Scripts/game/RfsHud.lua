-- RfsHud.lua — always-on top-center clock + compass HUD for Recipe Framework Survival
-- Author: DemonsDen126
-- Original clock + compass HUD implementation.

RfsHud = RfsHud or {}

local LAYOUT = "$CONTENT_DATA/Gui/Layouts/Rfs_Hud.layout"
local CARDINALS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

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

function RfsHud.ensure( host )
	host.cl = host.cl or {}
	if host.cl.rfsHud then
		return host.cl.rfsHud
	end
	local ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT, false, {
		isHud = true,
		isInteractive = false,
		needsCursor = false
	} )
	if not ok or not gui then
		print( "[RFS] HUD create failed: " .. tostring( gui ) )
		return nil
	end
	host.cl.rfsHud = gui
	pcall( function() gui:open() end )
	print( "[RFS] HUD opened (clock + compass)" )
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
end
