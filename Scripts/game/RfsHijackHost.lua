-- World-bound host for hijack. Game.lua cannot call sm.unit.getAllUnits().
-- Created on the overworld so unit scans are legal.

dofile( "$CONTENT_DATA/Scripts/game/RfsBotHijack.lua" )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsHackTether.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsHackApply.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsChemStation.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsHackOrdersIdentity.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsHackReload.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsHackUnitSandbox.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsBotOrders.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsFeatures.lua" )
end )

RfsHijackHost = class( nil )

function RfsHijackHost.server_onCreate( self )
	_G.g_rfsHijackHost = self
	pcall( function()
		if type( RfsHackReload ) == "table" and RfsHackReload.resetLoadWindow then
			RfsHackReload.resetLoadWindow( self.world )
		end
	end )
	pcall( function()
		if type( RfsHackTether ) == "table" and RfsHackTether.ensureHooks then
			RfsHackTether.ensureHooks()
		end
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
	-- After load, unit classes re-dofile vanilla melee. Re-wrap every 10 ticks (not every tick).
	if ( tick % 10 ) == 0 then
		pcall( function()
			if type( RfsHackTether ) == "table" and RfsHackTether.ensureHooks then
				RfsHackTether.ensureHooks()
			end
			RfsBotHijack.ensureHooks()
		end )
	end
	-- Beacon countdown env cannot register into this world's allies[]. Drain
	-- apply-on-zero from publicData (engine-shared) and sm.storage (throttled scan).
	if type( RfsHackApply ) == "table" then
		if ( tick % 2 ) == 0 and type( RfsHackApply.consumePublicFlags ) == "function" then
			pcall( RfsHackApply.consumePublicFlags, self.world )
		end
		if type( RfsHackApply.drainStorageQueue ) == "function" then
			pcall( RfsHackApply.drainStorageQueue, self.world )
		end
	end
	if ( tick % 10 ) == 0 and type( RfsBotHijack ) == "table" then
		pcall( function()
			RfsBotHijack.tick( self.world )
		end )
	end
	-- Collect/Farm/Oil must tick here: Game.lua cannot unit:addContainer / getAllBodies.
	pcall( function()
		if type( RfsBotOrders ) == "table" and RfsBotOrders.sv_think then
			RfsBotOrders.sv_think( dt, self )
		end
	end )
	pcall( function()
		if type( RfsHackReload ) == "table" and RfsHackReload.tick then
			RfsHackReload.tick( self.world )
		end
	end )
end

function RfsHijackHost.sv_e_rfsApplyHack( self, params )
	params = params or {}
	if type( RfsHackApply ) == "table" and type( RfsHackApply.payloadHasDevice ) == "function"
		and not RfsHackApply.payloadHasDevice( params ) then
		return
	end
	local unit = params.unit
	if ( not unit or not sm.exists( unit ) ) and params.unitKey and type( RfsBotHijack ) == "table" then
		local okU, u = pcall( RfsBotHijack.unitByKey, params.unitKey, self.world )
		if okU then
			unit = u
		end
	end
	params.playerAlly = true
	if unit and type( RfsHackApply ) == "table" then
		if type( RfsHackApply.applyInThisEnv ) == "function" then
			pcall( RfsHackApply.applyInThisEnv, unit, params.ownerId or params.owner or 0, params )
		end
		-- Re-fire from this world env so the unit class handler (Select's sandbox) runs.
		pcall( function()
			sm.event.sendToUnit( unit, "sv_e_rfsApplyHack", params )
		end )
		if type( RfsHackOrdersIdentity ) == "table" and type( RfsHackOrdersIdentity.pushName ) == "function" then
			pcall( RfsHackOrdersIdentity.pushName, unit )
		end
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

function RfsHijackHost.sv_e_rfsOrdersIdentity( self, params )
	params = params or {}
	params.world = self.world
	local kind = tostring( params.kind or "color" )
	if type( RfsHackOrdersIdentity ) ~= "table" then
		return
	end
	if kind == "rename" then
		pcall( RfsHackOrdersIdentity.applyRename, params )
	elseif kind == "order" then
		pcall( RfsHackOrdersIdentity.applyOrder, params )
	else
		pcall( RfsHackOrdersIdentity.applyColor, params )
	end
end

function RfsHijackHost.sv_e_rfsKillBots( self, params )
	params = params or {}
	local radius = tonumber( params.radius ) or 30
	if radius <= 0 then
		radius = 30
	end
	local origin = params.origin
	if type( origin ) ~= "table" or origin.x == nil then
		return
	end
	local r2 = radius * radius
	local killed = 0
	local seen = {}
	local function isBotChar( char )
		if type( RfsBotHijack ) == "table" and type( RfsBotHijack.isKillbotCharacter ) == "function" then
			local ok, yes = pcall( RfsBotHijack.isKillbotCharacter, char )
			if ok then
				return yes and true or false
			end
		end
		if type( RfsBotHijack ) == "table" and type( RfsBotHijack.isRobotCharacter ) == "function" then
			local ok, yes = pcall( RfsBotHijack.isRobotCharacter, char )
			return ok and yes and true or false
		end
		return true
	end
	local function destroyUnit( unit )
		if not unit or not sm.exists( unit ) then
			return
		end
		local id = nil
		pcall( function()
			id = tostring( unit.id )
		end )
		if id and seen[id] then
			return
		end
		if id then
			seen[id] = true
		end
		local char = nil
		pcall( function()
			char = unit.character
		end )
		if char and sm.exists( char ) then
			local isP = false
			pcall( function()
				isP = char:isPlayer() and true or false
			end )
			if isP then
				return
			end
			if not isBotChar( char ) then
				return
			end
		end
		pcall( function()
			unit:destroy()
		end )
		killed = killed + 1
	end
	local function inRangeChar( char )
		local ok = false
		pcall( function()
			if char and sm.exists( char ) then
				local p = char.worldPosition
				local dx = p.x - origin.x
				local dy = p.y - origin.y
				local dz = p.z - origin.z
				ok = ( dx * dx + dy * dy + dz * dz ) <= r2
			end
		end )
		return ok
	end
	local list = nil
	pcall( function()
		list = sm.unit.getAllUnits( self.world )
	end )
	if type( list ) ~= "table" then
		pcall( function()
			if g_unitManager and type( g_unitManager.sv_getAllUnits ) == "function" then
				list = g_unitManager:sv_getAllUnits()
			end
		end )
	end
	if type( list ) == "table" then
		for _, unit in pairs( list ) do
			if unit and sm.exists( unit ) then
				local char = nil
				pcall( function()
					char = unit.character
				end )
				if inRangeChar( char ) then
					destroyUnit( unit )
				end
			end
		end
	end
	pcall( function()
		for _, character in ipairs( sm.character.getAllCharacters() ) do
			if sm.exists( character ) and not character:isPlayer() and inRangeChar( character ) then
				local unit = nil
				pcall( function()
					unit = character:getUnit()
				end )
				if unit and sm.exists( unit ) then
					destroyUnit( unit )
				end
			end
		end
	end )
	pcall( function()
		sm.gui.chatMessage( "[RFS] killed " .. tostring( killed ) .. " within " .. tostring( radius ) )
	end )
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

function RfsHijackHost.sv_e_rfsDeepSleepWorldSkip( self, params )
	if type( RfsDeepSleepTime ) == "table" and RfsDeepSleepTime.worldSkip then
		RfsDeepSleepTime.worldSkip( self, params )
	end
end
