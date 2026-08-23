-- RfsHackV1Convert.lua
-- VOLATILE: convert hostile robot (raid-only). Vanilla AI + hunt remaining hostiles.
-- Do not set saved.friendly (that skips all targeting). No Orders, no hijack LIVE.
-- Stolen bots skip RobotSelectTarget and only hunt hostiles (see RfsHackV1Fight).

RfsHackV1Convert = RfsHackV1Convert or {}

local TICK_EVERY = 16

local TYPE_UUID = {
	["c8bfb8f3-7efc-49ac-875a-eb85ac0614db"] = "Haybot",
	["9f4fde94-312f-4417-b13b-84029c5d6b52"] = "Farmbot",
	["04761b4a-a83e-4736-b565-120bc776edb2"] = "Tapebot",
	["c3d31c47-0c9b-4b07-9bd4-8f022dc4333e"] = "Tapebot",
	["97efd943-d176-479a-a6f4-46373327ddcd"] = "Tapebot",
	["9dbbd2fb-7726-4e8f-8eb4-0dab228a561d"] = "Tapebot",
	["fcb2e8ce-ca94-45e4-a54b-b5acc156170b"] = "Tapebot",
	["68d3b2f3-ed4b-4967-9d22-8ee6f555df63"] = "Tapebot",
	["c68914f8-d769-4638-9071-f7dbd1d97351"] = "Tapebot",
	["f3ded3f4-ddf9-441d-83f1-28b8cf2c7581"] = "Tapebot",
	["54a06cf0-c035-41a5-b19e-158496d35586"] = "Tapebot",
	["58992f50-ca36-44e1-8c47-4996d89d6a9a"] = "Totebot",
	["8984bdbf-521e-4eed-b3c4-2b5e287eb879"] = "Totebot",
	["55fd93fa-09ed-4a26-bfa1-4601694d5127"] = "Totebot",
	["9360d346-3ff2-4925-a068-660cf5dd5267"] = "Totebot",
	["2dea48a4-6a79-11ed-a1eb-0242ac120002"] = "Totebot",
}

local UNIT_CLASSES = {
	"HaybotUnit", "FarmbotUnit", "TapebotUnit",
	"TotebotGreenUnit", "TotebotRedUnit", "TotebotYellowUnit",
	"TotebotBlueUnit", "TotebotLeafUnit",
}

local function typeLabel( char )
	local t = nil
	pcall( function()
		t = tostring( char:getCharacterType() or "" )
	end )
	if not t or t == "" then
		return nil
	end
	local mapped = TYPE_UUID[t] or TYPE_UUID[string.lower( t )]
	if mapped then
		return mapped
	end
	local lower = string.lower( t )
	if string.find( lower, "haybot", 1, true ) then
		return "Haybot"
	end
	if string.find( lower, "farmbot", 1, true ) then
		return "Farmbot"
	end
	if string.find( lower, "tapebot", 1, true ) then
		return "Tapebot"
	end
	if string.find( lower, "totebot", 1, true ) then
		return "Totebot"
	end
	if type( g_robots ) == "table" then
		for _, uuid in ipairs( g_robots ) do
			if t == tostring( uuid ) or t == uuid then
				return "Bot"
			end
		end
	end
	return nil
end

local function isHackableRobot( char )
	if not char or not sm.exists( char ) then
		return false
	end
	local isP = false
	pcall( function()
		isP = char:isPlayer() and true or false
	end )
	if isP then
		return false
	end
	return typeLabel( char ) ~= nil
end

function RfsHackV1Convert.typeLabel( char )
	return typeLabel( char )
end

function RfsHackV1Convert.isHackableRobot( char )
	return isHackableRobot( char )
end

local function devicesOn()
	if type( RfsFeatures ) == "table" and type( RfsFeatures.hackDevicesEnabled ) == "function" then
		local ok, v = pcall( RfsFeatures.hackDevicesEnabled )
		if ok then
			return v and true or false
		end
	end
	return true
end

local function robotsOn()
	if type( RfsFeatures ) == "table" and type( RfsFeatures.hackableRobotsEnabled ) == "function" then
		local ok, v = pcall( RfsFeatures.hackableRobotsEnabled )
		if ok then
			return v and true or false
		end
	end
	return true
end

local function applyOnUnitSelf( self, params )
	if type( self ) ~= "table" then
		return
	end
	self.saved = self.saved or {}
	self.saved.friendly = false
	if params and params.beaconKey then
		self.saved.rfsHackV1BeaconKey = tostring( params.beaconKey )
	end
	self.isDirty = true
	self.target = nil
	self.lastTargetPosition = nil
	self.eventTarget = nil
end

function RfsHackV1Convert.ensureUnitEnv()
	RfsHackV1Convert.ensureCharHooks()
	-- Unit classes load on first spawn — always retry Apply/Fight wraps.
	-- Early `_unitEnv` used to skip forever → no pulseTag / no hold countdown.
	for i = 1, #UNIT_CLASSES do
		local cls = _G[UNIT_CLASSES[i]]
		if type( cls ) == "table" and not cls._rfsHackV1Apply then
			cls._rfsHackV1Apply = true
			if type( RfsHackV1Persist ) == "table" then
				cls.sv_e_rfsHackV1Apply = RfsHackV1Persist.onApply
				cls.sv_e_rfsHackV1Revert = RfsHackV1Persist.onRevert
				cls.sv_e_rfsHackV1Sync = RfsHackV1Persist.onSync
			else
				cls.sv_e_rfsHackV1Apply = applyOnUnitSelf
			end
		end
	end
	if type( RfsHackV1Fight ) == "table" then
		RfsHackV1Fight.ensureUnitEnv()
	end
	if RfsHackV1Convert._unitEnv then
		return
	end
	if type( InitRobotParams ) == "function" and not RfsHackV1Convert._origInit then
		RfsHackV1Convert._origInit = InitRobotParams
		InitRobotParams = function( self )
			RfsHackV1Convert._origInit( self )
			if type( RfsHackV1Persist ) == "table" then
				RfsHackV1Persist.hydrateSelf( self )
			elseif type( self ) == "table" then
				self.saved = self.saved or {}
				if self.saved.rfsHackV1BeaconKey then
					self.saved.friendly = false
				end
			end
		end
	end
	if type( RobotSelectTarget ) == "function" and not RfsHackV1Convert._origSelect then
		RfsHackV1Convert._origSelect = RobotSelectTarget
		RobotSelectTarget = function( self, allyRange, dt )
			if type( self ) == "table" then
				self.saved = self.saved or {}
				if self.saved.rfsHackV1BeaconKey then
					if not self._rfsHackV1Hydrated and type( RfsHackV1Persist ) == "table" then
						RfsHackV1Persist.hydrateSelf( self )
					end
					-- Skip vanilla Select for stolen bots (it locks onto the player /
					-- crops). Hunt hostiles only — same pattern as live hijack allies.
					if type( RfsHackV1Fight ) == "table" then
						RfsHackV1Fight.retarget( self )
					end
					return
				end
			end
			return RfsHackV1Convert._origSelect( self, allyRange, dt )
		end
	end
	if RfsHackV1Convert._origInit and RfsHackV1Convert._origSelect then
		RfsHackV1Convert._unitEnv = true
	end
end

-- 0852-k: tags must ride Character.network (same pattern as hijack sv_e_rfsTag).
-- Game.sendToClients with a Character ref does not serialize → empty client, no text.
-- RfsBotHijack.LIVE is false in v1, so hijack char hooks never install.
local CHAR_CLASSES = {
	"BaseEnemyCharacter",
	"TotebotCharacter", "TotebotGreenCharacter", "TotebotRedCharacter", "TotebotBlueCharacter",
	"TotebotYellowCharacter", "TotebotLeafCharacter", "HaybotCharacter",
	"FarmbotCharacter", "TapebotCharacter", "MinerbotCharacter",
	"CablebotCharacter", "LootbotCharacter", "SeedbotCharacter",
	"TrashbotCharacter", "ScannerbotCharacter",
}

local function destroyTagFx( self )
	local fx = self and self.cl and self.cl.rfsHackV1TagFx
	if not fx then
		return
	end
	pcall( function()
		if sm.exists( fx ) then
			fx:stop()
			fx:destroy()
		end
	end )
	self.cl.rfsHackV1TagFx = nil
	self.cl.rfsHackV1TagOnHead = nil
end

local function applyCharTag( self, text )
	if not self then
		return
	end
	self.cl = self.cl or {}
	text = tostring( text or "" )
	local char = self.character
	if not char or not sm.exists( char ) then
		return
	end
	if text == "" then
		destroyTagFx( self )
		self.cl.rfsHackV1TagText = nil
		pcall( function()
			sm.gui.setCharacterDebugText( char, "" )
		end )
		return
	end
	-- Rebuild FX when the countdown string changes so TextContent cannot stick.
	local prevText = self.cl.rfsHackV1TagText
	if prevText and prevText ~= text then
		destroyTagFx( self )
	end
	self.cl.rfsHackV1TagText = text
	local fx = self.cl.rfsHackV1TagFx
	local alive = false
	pcall( function()
		alive = fx and sm.exists( fx )
	end )
	if not alive then
		-- Body-parented + height (hijack pattern). Head bone can bury the label.
		local names = { "RfsHackText", "RfsGrowText" }
		for i = 1, #names do
			local ok, created = pcall( sm.effect.createEffect, names[i], char, nil, sm.effect.axis.all )
			if not ( ok and created ) then
				ok, created = pcall( sm.effect.createEffect, names[i], char )
			end
			if not ( ok and created ) then
				ok, created = pcall( sm.effect.createEffect, names[i], char, "jnt_head" )
			end
			if ok and created then
				fx = created
				break
			end
		end
		if fx then
			self.cl.rfsHackV1TagFx = fx
			pcall( function()
				local h = 1.35
				pcall( function()
					h = char:getHeight()
				end )
				fx:setOffsetPosition( sm.vec3.new( 0, 0, h + 0.35 ) )
				fx:start()
			end )
		end
	end
	if fx then
		pcall( function()
			local h = 1.35
			pcall( function()
				h = char:getHeight()
			end )
			fx:setOffsetPosition( sm.vec3.new( 0, 0, h + 0.35 ) )
			fx:setParameter( "TextContent", text )
			fx:setParameter( "Color", sm.color.new( 1.0, 0.72, 0.08, 1.0 ) )
			if not fx:isPlaying() then
				fx:start()
			end
		end )
	end
	-- Fallback channel so countdown stays visible even if RfsHackText fails.
	pcall( function()
		sm.gui.setCharacterDebugText( char, text )
	end )
end

function RfsHackV1Convert.ensureCharHooks()
	-- Retry until Survival character classes exist (dofile order can race).
	for i = 1, #CHAR_CLASSES do
		local cls = _G[CHAR_CLASSES[i]]
		if type( cls ) == "table" and not cls._rfsHackV1TagRpc then
			cls._rfsHackV1TagRpc = true
			function cls.sv_e_rfsHackV1Tag( self, params )
				pcall( function()
					self.network:sendToClients( "cl_e_rfsHackV1Tag", params or { text = "" } )
				end )
			end
			function cls.cl_e_rfsHackV1Tag( self, params )
				applyCharTag( self, params and params.text )
			end
		end
	end
end

function RfsHackV1Convert.clearTag( unit )
	RfsHackV1Convert.pushTag( unit, "" )
end

function RfsHackV1Convert.pushTag( unit, name )
	if not unit or not sm.exists( unit ) then
		return
	end
	RfsHackV1Convert.ensureCharHooks()
	name = tostring( name or "" )
	local char = unit.character
	if not char or not sm.exists( char ) then
		return
	end
	pcall( function()
		sm.event.sendToCharacter( char, "sv_e_rfsHackV1Tag", { text = name } )
	end )
end

-- Legacy Game RPC path (kept for old clients / stamp bounce). Prefer pushTag.
function RfsHackV1Convert.clApplyTag( host, data )
	data = data or {}
	local name = tostring( data.name or data.text or "" )
	local char = data.character
	if char and sm.exists( char ) then
		pcall( function()
			sm.gui.setCharacterDebugText( char, name )
		end )
	end
end

function RfsHackV1Convert.convertUnit( unit, beaconKey, cap, holdSec )
	if not unit or not sm.exists( unit ) then
		return false
	end
	if type( RfsHackV1Registry ) ~= "table" then
		return false
	end
	if RfsHackV1Registry.isAlly( unit ) then
		return false
	end
	local char = unit.character
	if not char or not sm.exists( char ) then
		return false
	end
	local label = typeLabel( char )
	if not label then
		return false
	end
	cap = tonumber( cap ) or 4
	holdSec = tonumber( holdSec ) or 8
	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick() or 0
	end )
	local unhackAt = tick + ( 40 * holdSec )
	if type( RfsHackV1Hold ) == "table" and RfsHackV1Hold.unhackAtFromSeconds then
		unhackAt = RfsHackV1Hold.unhackAtFromSeconds( holdSec, tick )
	end
	local blob = {
		ally = true,
		beaconKey = tostring( beaconKey or "" ),
		typeLabel = label,
		unhackAt = unhackAt,
		cap = cap,
		holdSec = holdSec,
	}
	if RfsHackV1Registry.write then
		RfsHackV1Registry.write( unit, blob )
	else
		RfsHackV1Registry.writeOnce( unit, blob )
	end
	pcall( function()
		sm.event.sendToUnit( unit, "sv_e_rfsHackV1Apply", {
			beaconKey = tostring( beaconKey or "" ),
			unhackAt = unhackAt,
			cap = cap,
			holdSec = holdSec,
		} )
	end )
	local holdText = "HACKED"
	if type( RfsHackV1Hold ) == "table" and RfsHackV1Hold.releaseTagText then
		holdText = RfsHackV1Hold.releaseTagText( unhackAt, tick )
	end
	RfsHackV1Convert.pushTag( unit, holdText )
	return true
end

function RfsHackV1Convert.tickBeacon( beacon )
	if type( RfsHackV1Tick ) == "table" then
		RfsHackV1Tick.serverTick( beacon )
	end
end
