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
	dofile( "$CONTENT_DATA/Scripts/game/RfsHackAllyThrottle.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsChemStation.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsHackOrdersIdentity.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsHackOrdersDrop.lua" )
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
	-- 0851-r: live hack parked — no ensureHooks / unit wrap.
	print( "[RFS] Hijack host created (parked, no tick)" )
end

function RfsHijackHost.server_onDestroy( self )
	if _G.g_rfsHijackHost == self then
		_G.g_rfsHijackHost = nil
	end
end

function RfsHijackHost.server_onFixedUpdate( self, dt )
	-- 0851-r: live hack parked — no convert drain, unit scan, orders think, or hook rewrap.
	return
end

function RfsHijackHost.sv_e_rfsApplyHack( self, params )
	return
end

function RfsHijackHost.sv_e_hijack( self, params )
	return
end

function RfsHijackHost.sv_e_hijackList( self, params )
	return
end

function RfsHijackHost.sv_e_rfsOrdersIdentity( self, params )
	return
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
	return
end

function RfsHijackHost.sv_e_rfsDeepSleepWorldSkip( self, params )
	if type( RfsDeepSleepTime ) == "table" and RfsDeepSleepTime.worldSkip then
		RfsDeepSleepTime.worldSkip( self, params )
	end
end
