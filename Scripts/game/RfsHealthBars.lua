-- RfsHealthBars.lua — 2D WorldIconGui Minecraft-style HP icon row + name.
-- Keep GUI alive; engine setRequireLineOfSight handles walls.
-- Only open icons within SHOW_DIST so stream-in works (don't exhaust GUI slots at load).

RfsHealthBars = RfsHealthBars or {}

local LAYOUT = "$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247/Gui/menu/layouts/Rfs_HpWorld.layout"
local LAYOUT_FALLBACK = "$CONTENT_DATA/Gui/menu/layouts/Rfs_HpWorld.layout"
local IMG_BASE = "$CONTENT_DATA/Gui/menu/images/"
local SEND_EVERY = 20
-- Wide enough for up to 10 side-by-side pips.
local ICON_W = 220
local ICON_H = 48
local PIP_N = 10
local SHOW_DIST = 56
local WORLD_UP = sm.vec3.new( 0, 0, 1 )

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

local UNIT_LABEL = {
	TotebotGreenUnit = "Tote", TotebotBlueUnit = "Tote", TotebotRedUnit = "Tote",
	TotebotLeafUnit = "Tote", TotebotYellowUnit = "Tote", BaseTotebotUnit = "Tote",
	HaybotUnit = "Hay", FarmbotUnit = "Farm", TapebotUnit = "Tape",
	MinerbotUnit = "Miner", CablebotUnit = "Cable", LootbotUnit = "Loot",
	SeedbotUnit = "Seed", TrashbotUnit = "Trash", ScannerbotUnit = "Scan",
	WocUnit = "Woc", GlobUnit = "Glob", BabyWocUnit = "Baby Woc",
}

local function namesEnabled()
	if type( RfsGuiPrefs ) ~= "table" or not RfsGuiPrefs.client then
		return true
	end
	local prefs = RfsGuiPrefs.client()
	return not ( prefs and prefs.names == false )
end

local function displayLabel( raw )
	raw = tostring( raw or "" )
	if raw == "" then
		return ""
	end
	local prefs = type( RfsGuiPrefs ) == "table" and RfsGuiPrefs.client and RfsGuiPrefs.client() or nil
	if prefs and prefs.bigRed then
		raw = raw:gsub( "^Farm$", "Big Red" ):gsub( "^Farm ", "Big Red " )
	end
	return raw
end

local function barColor( ally, frac )
	local prefs = type( RfsGuiPrefs ) == "table" and RfsGuiPrefs.client and RfsGuiPrefs.client() or nil
	local name = ally and ( ( prefs and prefs.neutralHp ) or "green" ) or ( ( prefs and prefs.enemyHp ) or "red" )
	local col = type( RfsGuiPrefs ) == "table" and RfsGuiPrefs.hpColor and RfsGuiPrefs.hpColor( name ) or nil
	if ( tonumber( frac ) or 1 ) < 0.35 then
		return sm.color.new( 1.00, 0.18, 0.12, 1.0 )
	end
	if col then
		return col
	end
	if ally then
		return sm.color.new( 0.28, 0.92, 0.38, 1.0 )
	end
	return sm.color.new( 1.0, 0.22, 0.18, 1.0 )
end

local function destroyGui( self )
	if not self or not self.cl then
		return
	end
	local gui = self.cl.rfsHpGui
	if gui then
		pcall( function() gui:close() end )
		pcall( function() gui:destroy() end )
	end
	self.cl.rfsHpGui = nil
	self.cl.rfsHpPipSkins = nil
	-- Legacy cleanup
	local function kill( fx )
		pcall( function()
			if fx and sm.exists( fx ) then
				fx:stop()
				fx:destroy()
			end
		end )
	end
	kill( self.cl.rfsHpBack )
	kill( self.cl.rfsHpFill )
	kill( self.cl.rfsHpNameFx )
	kill( self.cl.rfsHpMeterFx )
	kill( self.cl.rfsHpFx )
	self.cl.rfsHpBack = nil
	self.cl.rfsHpFill = nil
	self.cl.rfsHpNameFx = nil
	self.cl.rfsHpMeterFx = nil
	self.cl.rfsHpFx = nil
end

local function withinShowDist( pos )
	local ok = true
	pcall( function()
		local cam = sm.camera.getPosition()
		ok = ( cam - pos ):length2() <= ( SHOW_DIST * SHOW_DIST )
	end )
	return ok
end

local function ensureGui( self )
	local gui = self.cl.rfsHpGui
	if gui then
		return gui
	end
	local created = nil
	pcall( function()
		created = sm.gui.createWorldIconGui( ICON_W, ICON_H, LAYOUT, false )
	end )
	if not created then
		pcall( function()
			created = sm.gui.createWorldIconGui( ICON_W, ICON_H, LAYOUT_FALLBACK, false )
		end )
	end
	if not created then
		pcall( function()
			created = sm.gui.createWorldIconGui( ICON_W, ICON_H )
		end )
	end
	if not created then
		return nil
	end
	-- Engine hides through walls — do NOT destroy on our own raycast.
	pcall( function()
		created:setRequireLineOfSight( true )
	end )
	pcall( function()
		created:open()
	end )
	self.cl.rfsHpGui = created
	self.cl.rfsHpPipSkins = nil
	return created
end

-- Always up to 10 icons: each pip = 10% of that unit's max HP.
-- Damage hides icons from the right (Minecraft-style).
local function pipCounts( hp, maxhp )
	hp = math.max( 0, tonumber( hp ) or 0 )
	maxhp = math.max( 0, tonumber( maxhp ) or 0 )
	if maxhp <= 0 then
		return 0, 0
	end
	local pipsMax = PIP_N
	local filled = 0
	if hp > 0 then
		filled = math.min( pipsMax, math.max( 1, math.ceil( ( hp / maxhp ) * pipsMax ) ) )
	end
	return pipsMax, filled
end

-- Stable nut/bolt or steak/milk per pip index (does not reshuffle on damage).
local function pipSkinPath( animal, pipIndex, seed )
	seed = tonumber( seed ) or 0
	local pick = ( seed + pipIndex * 17 + ( animal and 3 or 0 ) ) % 2
	local file
	if animal then
		file = ( pick == 0 ) and "hp_steak.png" or "hp_milk.png"
	else
		file = ( pick == 0 ) and "hp_nut.png" or "hp_bolt.png"
	end
	return IMG_BASE .. file
end

local function applyPips( self, gui, hp, maxhp, animal )
	local _, filled = pipCounts( hp, maxhp )
	local seed = 0
	pcall( function()
		local char = self.character
		if char and char.id then
			seed = tonumber( char.id ) or 0
		end
	end )
	local skins = self.cl.rfsHpPipSkins
	local animalKey = animal and 1 or 0
	if type( skins ) ~= "table" or skins.animal ~= animalKey or skins.seed ~= seed then
		skins = { animal = animalKey, seed = seed, paths = {} }
		for i = 0, PIP_N - 1 do
			skins.paths[i] = pipSkinPath( animal, i, seed )
		end
		self.cl.rfsHpPipSkins = skins
	end
	for i = 0, PIP_N - 1 do
		local name = "HpPip" .. tostring( i )
		local on = i < filled
		if on then
			pcall( function()
				gui:setImage( name, skins.paths[i] )
			end )
		end
		pcall( function()
			gui:setVisible( name, on )
		end )
	end
end

local function barHeight( character )
	local h = 0.85
	pcall( function()
		-- getHeight() is the top of the capsule. Target just above the back,
		-- ~halfway up — not head+padding (that put the billboard near the compass).
		local full = character:getHeight() or 1.2
		h = full * 0.52
	end )
	return h
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
		destroyGui( self )
		self.cl.rfsHp = nil
		return
	end
	local hp = tonumber( data.hp ) or 0
	local frac = tonumber( data.frac ) or ( hp / maxhp )
	frac = math.max( 0, math.min( 1, frac ) )
	local ally = data.ally and true or false
	local animal = data.animal and true or false
	local label = tostring( data.label or ( self.cl.rfsHp and self.cl.rfsHp.label ) or "" )
	-- Preserve animal from prior push if a frac-only damage update omitted it.
	if data.animal == nil and self.cl.rfsHp and self.cl.rfsHp.animal then
		animal = true
	end
	self.cl.rfsHp = { hp = hp, maxhp = maxhp, frac = frac, ally = ally, animal = animal, label = label }

	local char = self.character
	if not char or not sm.exists( char ) then
		return
	end
	local base = nil
	pcall( function() base = char.worldPosition end )
	if not base then
		return
	end
	local pos = base + WORLD_UP * barHeight( char )
	local world = nil
	pcall( function() world = char:getWorld() end )
	local color = barColor( ally, frac )
	local showName = displayLabel( label )

	-- Distance gate: create/update only when near. Far units drop GUI but keep cache
	-- so walking up recreates (fixes "not in LOS at load").
	if not withinShowDist( pos ) then
		if self.cl.rfsHpGui then
			destroyGui( self )
			self.cl.rfsHp = { hp = hp, maxhp = maxhp, frac = frac, ally = ally, animal = animal, label = label }
		end
		return
	end

	local gui = ensureGui( self )
	if not gui then
		return
	end

	pcall( function()
		gui:setWorldPosition( pos, world )
	end )

	applyPips( self, gui, hp, maxhp, animal )

	if showName == "" or not namesEnabled() then
		pcall( function()
			gui:setText( "HpName", "" )
			gui:setVisible( "HpName", false )
		end )
	else
		pcall( function()
			gui:setVisible( "HpName", true )
			gui:setText( "HpName", showName )
		end )
		pcall( function()
			gui:setColor( "HpName", color )
		end )
	end
end

local function wrapCharacter( cls )
	if type( cls ) ~= "table" then
		return false
	end
	if not cls._rfsHpCharRpc then
		cls._rfsHpCharRpc = true
		function cls.sv_e_rfsHp( self, params )
			pcall( function()
				self.network:sendToClients( "cl_e_rfsHp", params or {} )
			end )
		end
		function cls.cl_e_rfsHp( self, params )
			RfsHealthBars.cl_apply( self, params )
		end
	end
	if cls._rfsHpChar then
		return true
	end
	local origDmg = cls.cl_n_updateDamage
	if origDmg then
		cls.cl_n_updateDamage = function( self, params )
			origDmg( self, params )
			local frac = params and tonumber( params.damage )
			if frac then
				local prev = self.cl and self.cl.rfsHp
				local maxhp = prev and tonumber( prev.maxhp ) or 1
				if maxhp <= 0 then
					maxhp = 1
				end
				-- Vanilla damage param is remaining HP fraction (0..1).
				local hp = frac * maxhp
				RfsHealthBars.cl_apply( self, {
					hp = hp, maxhp = maxhp, frac = frac,
					ally = prev and prev.ally or false,
					animal = prev and prev.animal or false,
					label = prev and prev.label or "",
				} )
			end
		end
	end
	local origU = cls.client_onUpdate
	cls.client_onUpdate = function( self, dt )
		if origU then
			origU( self, dt )
		end
		if self.cl and self.cl.rfsHp then
			RfsHealthBars.cl_apply( self, self.cl.rfsHp )
		end
	end
	local origD = cls.client_onDestroy
	cls.client_onDestroy = function( self )
		destroyGui( self )
		if origD then
			origD( self )
		end
	end
	cls._rfsHpChar = true
	return true
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
		if not ally and type( RfsHackV1Registry ) == "table" and RfsHackV1Registry.isAlly then
			ally = RfsHackV1Registry.isAlly( self.unit ) and true or false
		end
		if not ally and self.saved then
			ally = self.saved.playerAlly and true or false
		end
	end )
	return ally
end

local function unitLabel( self, className )
	local label = UNIT_LABEL[className] or ""
	pcall( function()
		if type( RfsHackV1Registry ) == "table" and RfsHackV1Registry.read and self.unit then
			local blob = RfsHackV1Registry.read( self.unit )
			if blob and blob.ally then
				local n = tostring( blob.name or blob.typeLabel or "" )
				if n ~= "" then
					label = n
				end
			end
		end
		if self.saved then
			local custom = tostring( self.saved.rfsCustomName or "" )
			local disp = tostring( self.saved.rfsDisplayName or self.saved.rfsHackV1Name or "" )
			if custom ~= "" then
				label = custom
			elseif disp ~= "" then
				label = disp
			end
		end
	end )
	return label
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
	RfsHealthBars.ensureHooks()
	local hp = tonumber( stats.hp ) or 0
	pcall( function()
		sm.event.sendToCharacter( char, "sv_e_rfsHp", {
			hp = hp,
			maxhp = maxhp,
			frac = hp / maxhp,
			ally = unitKindAlly( self, className ),
			animal = ANIMAL[className] and true or false,
			label = unitLabel( self, className ),
		} )
	end )
end

local function wrapUnit( cls, className )
	if type( cls ) ~= "table" then
		return false
	end
	local orig = cls.server_onFixedUpdate
	if type( orig ) ~= "function" then
		return false
	end
	if cls._rfsHpUnit then
		return true
	end
	cls.server_onFixedUpdate = function( self, dt )
		orig( self, dt )
		pcall( function()
			local tick = sm.game.getCurrentTick()
			local id = 0
			if self.unit and self.unit.id then
				id = tonumber( self.unit.id ) or 0
			end
			local age = tonumber( self._rfsHpAge ) or 0
			self._rfsHpAge = age + 1
			local every = ( age < 80 ) and 10 or SEND_EVERY
			if ( tick % every ) ~= ( id % every ) then
				return
			end
			pushHp( self, className )
		end )
	end
	local origC = cls.server_onCreate
	cls.server_onCreate = function( self )
		if origC then
			origC( self )
		end
		self._rfsHpAge = 0
		pcall( function() pushHp( self, className ) end )
	end
	cls._rfsHpUnit = true
	return true
end

function RfsHealthBars.ensureHooks()
	for _, name in ipairs( CHAR_CLASSES ) do
		wrapCharacter( _G[name] )
	end
	for _, name in ipairs( UNIT_CLASSES ) do
		wrapUnit( _G[name], name )
	end
end

print( "[RFS] RfsHealthBars loaded (10% HP pips + engine LOS)" )
