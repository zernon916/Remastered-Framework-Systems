-- RfsHackReload.lua
-- VOLATILE: re-hook allied bots after world save/load.
-- FROZEN: spend, caps, hijack HP math, E/open path, SHOW RANGE host.
--
-- After reload, unit class scripts re-dofile vanilla server_onMelee in the
-- unit sandbox. HijackHost/Game ensureHooks do not run inside that sandbox,
-- so sledge (Character attacker) hits nothing and Select may skip the ally
-- branch until allies[] is re-registered. Scan once post-load and poke each
-- saved ally via sv_e_rfsRestoreAfterLoad (runs IN the unit env).

RfsHackReload = RfsHackReload or {}

local UNIT_CLASSES = {
	"TotebotGreenUnit", "TotebotBlueUnit", "TotebotRedUnit", "TotebotLeafUnit",
	"TotebotYellowUnit", "HaybotUnit", "FarmbotUnit", "TapebotUnit",
	"MinerbotUnit", "CablebotUnit", "LootbotUnit", "SeedbotUnit",
	"BaseTotebotUnit", "TrashbotUnit",
}

local SCAN_TICKS = 200
local SCAN_INTERVAL = 4
local RESTORE_RPC = "sv_e_rfsRestoreAfterLoad"

local function eachUnit( world, fn )
	local list = nil
	if g_unitManager and type( g_unitManager.sv_getAllUnits ) == "function" then
		pcall( function()
			list = g_unitManager:sv_getAllUnits()
		end )
	end
	if type( list ) ~= "table" then
		pcall( function()
			if world ~= nil then
				list = sm.unit.getAllUnits( world )
			else
				list = sm.unit.getAllUnits()
			end
		end )
	end
	if type( list ) ~= "table" then
		return
	end
	for _, u in pairs( list ) do
		if u and sm.exists( u ) then
			fn( u )
		end
	end
end

local function publicAllyFlag( unit )
	local flagged = false
	pcall( function()
		local char = unit.character
		if char and sm.exists( char ) and type( char.publicData ) == "table" and char.publicData.rfsPlayerAlly then
			flagged = true
		end
	end )
	if flagged then
		return true
	end
	pcall( function()
		if type( unit.publicData ) == "table" and unit.publicData.rfsPlayerAlly then
			flagged = true
		end
	end )
	return flagged
end

function RfsHackReload.restoreUnitSelf( self )
	if type( self ) ~= "table" then
		return false
	end
	pcall( function()
		if type( RfsHackUnitSandbox ) ~= "table" then
			dofile( "$CONTENT_DATA/Scripts/game/RfsHackUnitSandbox.lua" )
		end
		if type( RfsHackUnitSandbox ) == "table" and RfsHackUnitSandbox.ensureDamage then
			RfsHackUnitSandbox.ensureDamage()
		elseif type( RfsHackTether ) == "table" and RfsHackTether.ensureHooks then
			RfsHackTether.ensureHooks()
		end
		if type( RfsBotHijack ) == "table" and RfsBotHijack.ensureHooks then
			RfsBotHijack.ensureHooks()
		end
	end )
	local ok = false
	if type( RfsHackApply ) == "table" and type( RfsHackApply.restoreFromSaved ) == "function" then
		ok = RfsHackApply.restoreFromSaved( self ) and true or false
	end
	if self.saved and type( self.saved.rfsOrder ) == "table" and self.unit and sm.exists( self.unit ) then
		pcall( function()
			sm.event.sendToUnit( self.unit, "sv_e_rfsOrder", self.saved.rfsOrder )
		end )
	end
	if type( RfsBotHijack ) == "table" and type( RfsBotHijack.standDown ) == "function" then
		pcall( RfsBotHijack.standDown, self )
	end
	return ok
end

function RfsHackReload.ensureRestoreHook()
	if RfsHackReload._restoreHooked then
		return
	end
	for _, className in ipairs( UNIT_CLASSES ) do
		local cls = _G[className]
		if type( cls ) == "table" and type( cls[RESTORE_RPC] ) ~= "function" then
			cls[RESTORE_RPC] = function( self, params )
				RfsHackReload.restoreUnitSelf( self )
			end
			cls._rfsRestoreHook = true
		end
	end
	RfsHackReload._restoreHooked = true
end

local function adoptInHostEnv( unit, world )
	if type( RfsHackApply ) ~= "table" or type( RfsHackApply.applyInThisEnv ) ~= "function" then
		return
	end
	local payload = nil
	if type( RfsHackApply.readPublicApply ) == "function" then
		payload = RfsHackApply.readPublicApply( unit )
	end
	if type( payload ) ~= "table" then
		return
	end
	payload.playerAlly = true
	pcall( function()
		RfsHackApply.applyInThisEnv( unit, payload.ownerId or payload.owner or 0, payload )
	end )
	pcall( function()
		sm.event.sendToUnit( unit, "sv_e_rfsApplyHack", payload )
	end )
end

local function loadWindowStartTick()
	local start = _G.rfsHackLoadTickAt
	if start == nil then
		start = RfsHackReload._loadTick
	end
	return tonumber( start ) or 0
end

function RfsHackReload.inLoadWindow()
	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick() or 0
	end )
	return ( tick - loadWindowStartTick() ) <= SCAN_TICKS
end

local function robotUnit( unit )
	if type( RfsBotHijack ) ~= "table" or type( RfsBotHijack.isRobotCharacter ) ~= "function" then
		return false
	end
	local ok, yes = pcall( function()
		local char = unit and unit.character
		return char and sm.exists( char ) and RfsBotHijack.isRobotCharacter( char )
	end )
	return ok and yes and true or false
end

function RfsHackReload.scanWorld( world )
	if type( RfsBotHijack ) == "table" and not RfsBotHijack.LIVE then
		return
	end
	RfsHackReload.ensureRestoreHook()
	RfsHackReload._restored = RfsHackReload._restored or {}
	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick() or 0
	end )
	local inLoad = RfsHackReload.inLoadWindow()
	eachUnit( world, function( unit )
		local key = nil
		pcall( function()
			key = tostring( unit.id )
		end )
		if not key or key == "" then
			return
		end
		local seen = RfsHackReload._restored[key]
		if seen and ( tick - ( tonumber( seen ) or 0 ) ) < SCAN_TICKS then
			return
		end
		local want = publicAllyFlag( unit )
		if not want and type( RfsBotHijack ) == "table" and type( RfsBotHijack.isAlly ) == "function" then
			pcall( function()
				want = RfsBotHijack.isAlly( unit ) and true or false
			end )
		end
		-- Post-load: beacon tickAuto can re-HACK before unit think restores saved.playerAlly.
		-- Poke every robot once so unit.saved + publicData.rfsAllyInfo exist before auto-hijack.
		if not want and inLoad and robotUnit( unit ) then
			want = true
		end
		if not want then
			return
		end
		RfsHackReload._restored[key] = tick
		adoptInHostEnv( unit, world )
		pcall( function()
			sm.event.sendToUnit( unit, RESTORE_RPC, {} )
		end )
	end )
end

function RfsHackReload.tick( world )
	if type( RfsBotHijack ) == "table" and not RfsBotHijack.LIVE then
		return
	end
	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick() or 0
	end )
	if tick - loadWindowStartTick() > SCAN_TICKS then
		return
	end
	if ( tick % SCAN_INTERVAL ) ~= 0 then
		return
	end
	RfsHackReload.scanWorld( world )
end

function RfsHackReload.resetLoadWindow( world )
	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick() or 0
	end )
	_G.rfsHackLoadTickAt = tick
	RfsHackReload._loadTick = tick
	RfsHackReload._restored = {}
	if not world then
		local host = _G.g_rfsHijackHost
		if type( host ) == "table" then
			world = host.world
		end
	end
	RfsHackReload.scanWorld( world )
end

print( "[RFS] RfsHackReload loaded (VOLATILE post-load ally restore)" )
