-- RfsHealthBars.lua — custom unit HP bars (engine bars cannot be recolored).
-- Enemy/Neutral /menu colors tint these billboards. Allied/hacked bots use Neutral.

RfsHealthBars = RfsHealthBars or {}

local FX_NAMES = { "RfsHpBar", "RfsHackText", "RfsGrowText" }
local SEND_EVERY = 20 -- 0.5 s at 40 tick/s

local UNIT_CLASSES = {
	"TotebotGreenUnit", "TotebotBlueUnit", "TotebotRedUnit", "TotebotLeafUnit",
	"TotebotYellowUnit", "HaybotUnit", "FarmbotUnit", "TapebotUnit",
	"MinerbotUnit", "CablebotUnit", "LootbotUnit", "SeedbotUnit",
	"BaseTotebotUnit", "TrashbotUnit", "ScannerbotUnit",
	"WocUnit", "GlobUnit", "BabyWocUnit",
}

local CHAR_CLASSES = {
	"BaseEnemyCharacter",
	"TotebotCharacter", "TotebotRedCharacter", "TotebotBlueCharacter",
	"TotebotYellowCharacter", "TotebotLeafCharacter", "HaybotCharacter",
	"FarmbotCharacter", "TapebotCharacter", "MinerbotCharacter",
	"CablebotCharacter", "LootbotCharacter", "SeedbotCharacter",
	"TrashbotCharacter", "ScannerbotCharacter",
	"WocCharacter", "GlobCharacter", "BabyWocCharacter",
}

local ANIMAL = {
	WocUnit = true, GlobUnit = true, BabyWocUnit = true,
}

local function barText( frac )
	frac = math.max( 0, math.min( 1, tonumber( frac ) or 0 ) )
	local filled = math.floor( frac * 10 + 0.5 )
	if filled > 10 then filled = 10 end
	local s = "["
	for i = 1, 10 do
		s = s .. ( i <= filled and "#" or "-" )
	end
	return s .. string.format( "] %d%%", math.floor( frac * 100 + 0.5 ) )
end

local function barColor( ally, frac )
	local prefs = nil
	if type( RfsGuiPrefs ) == "table" and RfsGuiPrefs.client then
		prefs = RfsGuiPrefs.client()
	end
	local name = "red"
	if ally then
		name = ( prefs and prefs.neutralHp ) or "green"
	else
		name = ( prefs and prefs.enemyHp ) or "red"
	end
	local col = nil
	if type( RfsGuiPrefs ) == "table" and RfsGuiPrefs.hpColor then
		col = RfsGuiPrefs.hpColor( name )
	end
	if not col then
		col = sm.color.new( ally and 0.28 or 1.0, ally and 0.92 or 0.18, ally and 0.38 or 0.18, 1.0 )
	end
	if ( tonumber( frac ) or 1 ) < 0.35 then
		return sm.color.new( 1.00, 0.18, 0.12, 1.0 )
	end
	return col
end

local function destroyHpFx( self )
	if self and self.cl and self.cl.rfsHpFx then
		pcall( function()
			if sm.exists( self.cl.rfsHpFx ) then
				self.cl.rfsHpFx:stop()
				self.cl.rfsHpFx:destroy()
			end
		end )
		self.cl.rfsHpFx = nil
	end
end

function RfsHealthBars.cl_apply( self, data )
	if not self then
		return
	end
	self.cl = self.cl or {}
	if type( data ) ~= "table" then
		return
	end
	local maxhp = tonumber( data.maxhp ) or 0
	if maxhp <= 0 then
		destroyHpFx( self )
		self.cl.rfsHp = nil
		return
	end
	local hp = tonumber( data.hp ) or 0
	local frac = tonumber( data.frac )
	if not frac then
		frac = hp / maxhp
	end
	local ally = data.ally and true or false
	self.cl.rfsHp = { hp = hp, maxhp = maxhp, frac = frac, ally = ally }
	local text = barText( frac )
	local color = barColor( ally, frac )

	local fx = self.cl.rfsHpFx
	local alive = false
	pcall( function()
		alive = fx and sm.exists( fx )
	end )
	if not alive then
		for _, name in ipairs( FX_NAMES ) do
			local ok, created = pcall( sm.effect.createEffect, name, self.character, nil, sm.effect.axis.all )
			if not ( ok and created ) then
				ok, created = pcall( sm.effect.createEffect, name, self.character )
			end
			if ok and created then
				fx = created
				break
			end
		end
		if fx then
			self.cl.rfsHpFx = fx
			pcall( function()
				local h = 1.55
				pcall( function()
					h = ( self.character:getHeight() or 1.2 ) + 0.28
				end )
				fx:setOffsetPosition( sm.vec3.new( 0, 0, h ) )
				fx:start()
			end )
		end
	end
	if fx then
		pcall( function()
			fx:setParameter( "TextContent", text )
			fx:setParameter( "Color", color )
			if not fx:isPlaying() then
				fx:start()
			end
		end )
	end
end

local function wrapCharacter( cls )
	if type( cls ) ~= "table" or cls._rfsHpChar then
		return
	end
	function cls.sv_e_rfsHp( self, params )
		pcall( function()
			self.network:sendToClients( "cl_e_rfsHp", params or {} )
		end )
	end
	function cls.cl_e_rfsHp( self, params )
		RfsHealthBars.cl_apply( self, params )
	end
	local origDmg = cls.cl_n_updateDamage
	if origDmg then
		cls.cl_n_updateDamage = function( self, params )
			origDmg( self, params )
			local frac = params and tonumber( params.damage )
			if frac then
				RfsHealthBars.cl_apply( self, { hp = frac, maxhp = 1, frac = frac, ally = false } )
			end
		end
	end
	local origU = cls.client_onUpdate
	cls.client_onUpdate = function( self, dt )
		if origU then
			origU( self, dt )
		end
		local hp = self.cl and self.cl.rfsHp
		if hp then
			local fx = self.cl.rfsHpFx
			local alive = false
			pcall( function()
				alive = fx and sm.exists( fx )
			end )
			if not alive then
				RfsHealthBars.cl_apply( self, hp )
			end
		end
	end
	local origD = cls.client_onDestroy
	cls.client_onDestroy = function( self )
		destroyHpFx( self )
		if origD then
			origD( self )
		end
	end
	cls._rfsHpChar = true
end

local function unitKindAlly( self, className )
	if ANIMAL[className] then
		return true
	end
	local ally = false
	pcall( function()
		if type( _G.g_rfsIsPlayerAlly ) == "function" and self.unit then
			ally = _G.g_rfsIsPlayerAlly( self.unit ) and true or false
		end
		if not ally and self.saved then
			ally = self.saved.playerAlly and true or false
		end
	end )
	return ally
end

local function pushHp( self, className )
	local stats = self.saved and self.saved.stats
	if type( stats ) ~= "table" then
		return
	end
	local maxhp = tonumber( stats.maxhp )
	if not maxhp or maxhp <= 0 then
		return
	end
	local char = self.unit and self.unit.character
	if not char or not sm.exists( char ) then
		return
	end
	local hp = tonumber( stats.hp ) or 0
	pcall( function()
		sm.event.sendToCharacter( char, "sv_e_rfsHp", {
			hp = hp,
			maxhp = maxhp,
			frac = hp / maxhp,
			ally = unitKindAlly( self, className ),
		} )
	end )
end

local function wrapUnit( cls, className )
	if type( cls ) ~= "table" or cls._rfsHpUnit then
		return
	end
	local orig = cls.server_onFixedUpdate
	cls.server_onFixedUpdate = function( self, dt )
		if orig then
			orig( self, dt )
		end
		pcall( function()
			local tick = sm.game.getCurrentTick()
			local id = 0
			if self.unit and self.unit.id then
				id = tonumber( self.unit.id ) or 0
			end
			if ( tick % SEND_EVERY ) ~= ( id % SEND_EVERY ) then
				return
			end
			pushHp( self, className )
		end )
	end
	cls._rfsHpUnit = true
end

function RfsHealthBars.ensureHooks()
	for _, name in ipairs( UNIT_CLASSES ) do
		wrapUnit( _G[name], name )
	end
	for _, name in ipairs( CHAR_CLASSES ) do
		wrapCharacter( _G[name] )
	end
end

print( "[RFS] RfsHealthBars loaded (custom unit HP bars)" )
