-- World-bound host for hijack. Game.lua cannot call sm.unit.getAllUnits().
-- Created on the overworld so unit scans are legal.

dofile( "$CONTENT_DATA/Scripts/game/RfsBotHijack.lua" )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsFeatures.lua" )
end )

RfsHijackHost = class( nil )

function RfsHijackHost.server_onCreate( self )
	_G.g_rfsHijackHost = self
	pcall( function()
		RfsBotHijack.ensureHooks()
	end )
	print( "[RFS] Hijack host created (world script)" )
end

function RfsHijackHost.server_onDestroy( self )
	if _G.g_rfsHijackHost == self then
		_G.g_rfsHijackHost = nil
	end
end

function RfsHijackHost.server_onFixedUpdate( self, dt )
	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick()
	end )
	if ( tick % 10 ) == 0 and type( RfsBotHijack ) == "table" then
		pcall( function()
			-- Hooks always run; tickAuto internally skips convert when robots disabled.
			RfsBotHijack.ensureHooks()
			RfsBotHijack.tick( self.world )
		end )
	end
end

function RfsHijackHost.sv_e_hijack( self, params )
	params = params or {}
	local player = params.player
	local range = params.range or 16
	if type( RfsBotHijack ) ~= "table" then
		sm.gui.chatMessage( "[RFS] Hijack failed: RfsBotHijack not loaded" )
		return
	end
	RfsBotHijack.ensureHooks()
	if type( RfsFeatures ) == "table" and type( RfsFeatures.hackableRobotsEnabled ) == "function" then
		local ok, on = pcall( RfsFeatures.hackableRobotsEnabled )
		if ok and not on then
			sm.gui.chatMessage( "[RFS] Hijack failed: hackable robots disabled by host" )
			return
		end
	end
	local n, info = RfsBotHijack.convertNearest( player, range, self.world )
	if n and n > 0 then
		sm.gui.chatMessage( "[RFS] Infected " .. tostring( info ) .. " (allies=" .. tostring( RfsBotHijack.count( self.world ) ) .. ")" )
	else
		sm.gui.chatMessage( "[RFS] Hijack failed: " .. tostring( info ) .. " (range " .. tostring( range ) .. ")" )
	end
end

function RfsHijackHost.sv_e_hijackList( self, params )
	if type( RfsBotHijack ) ~= "table" then
		sm.gui.chatMessage( "[RFS] Ally robots: 0 (host not ready)" )
		return
	end
	RfsBotHijack.ensureHooks()
	local n, tethered, infected = RfsBotHijack.count( self.world )
	sm.gui.chatMessage( "[RFS] Ally robots: " .. tostring( n or 0 ) .. " (tethered " .. tostring( tethered or 0 ) .. ", infected " .. tostring( infected or 0 ) .. ")" )
end

function RfsHijackHost.sv_e_unhijack( self, params )
	params = params or {}
	if type( RfsBotHijack ) ~= "table" then
		sm.gui.chatMessage( "[RFS] Unhijack failed: RfsBotHijack not loaded" )
		return
	end
	RfsBotHijack.ensureHooks()
	local n, info = RfsBotHijack.unhijackNearest( params.player, params.range or 16, self.world, params.allowAny == true )
	if n and n > 0 then
		sm.gui.chatMessage( "[RFS] Released " .. tostring( info ) .. " (voluntary — still hackable)" )
	else
		sm.gui.chatMessage( "[RFS] Unhijack failed: " .. tostring( info ) )
	end
end
