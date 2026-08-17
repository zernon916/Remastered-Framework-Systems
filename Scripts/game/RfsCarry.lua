-- RfsCarry.lua — VOLATILE: never wrap CarryTool LMB/RMB (that blocked Craftbot drop/place).
-- Vanilla lift drop/place for large items. Optional anti-dupe is server-only: ignore a
-- second identical big-item place RPC within 0.5s. Do not consume client clicks.

RfsCarry = RfsCarry or {}

-- 0.5s at Survival 40Hz. Short window is the anti-dupe; then place works again.
local PLACE_COOLDOWN_TICKS = 20

local function currentTick()
	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick()
	end )
	return tick
end

function RfsCarry.resetPlaceLock()
	RfsCarry._clUnlockTick = 0
end

function RfsCarry.markPlace()
	RfsCarry._clUnlockTick = currentTick() + PLACE_COOLDOWN_TICKS
end

function RfsCarry.placeLocked()
	local unlock = RfsCarry._clUnlockTick or 0
	return unlock > 0 and currentTick() < unlock
end

local function playerIdOf( player )
	if not player then
		return nil
	end
	local id = nil
	pcall( function()
		id = player.id
	end )
	return id
end

local function uuidKey( uuid )
	if not uuid then
		return nil
	end
	local s = nil
	pcall( function()
		s = tostring( uuid )
	end )
	return s
end

local function itemUuidOk( item )
	if not item or not item.uuid then
		return false
	end
	local nilUuid = nil
	pcall( function()
		nilUuid = sm.uuid.getNil()
	end )
	if nilUuid and item.uuid == nilUuid then
		return false
	end
	return true
end

-- True only for a real lift that does not go in inventory: units/characters,
-- harvestables, multi-shapes, large interactables (Craftbot, refinery, …).
-- False for empty carry, tools (hammer/guns), and inventory blocks.
local function itemIsBigLift( item )
	if not itemUuidOk( item ) then
		return false
	end
	local uuid = item.uuid

	local isTool = false
	pcall( function()
		isTool = sm.item.isTool( uuid )
	end )
	if isTool then
		return false
	end

	local isBlock = false
	pcall( function()
		isBlock = sm.item.isBlock( uuid )
	end )
	if isBlock then
		return false
	end

	local charShape = nil
	pcall( function()
		charShape = sm.item.getCharacterShape( uuid )
	end )
	if charShape then
		return true
	end

	local isMulti = false
	pcall( function()
		isMulti = sm.item.isMultiShape( uuid )
	end )
	if isMulti then
		return true
	end

	local isHvs = false
	pcall( function()
		if type( sm.item.isHarvestablePart ) == "function" then
			isHvs = sm.item.isHarvestablePart( uuid )
		end
	end )
	if isHvs then
		return true
	end

	local size = nil
	pcall( function()
		size = sm.item.getShapeSize( uuid )
	end )
	if size then
		local vol = math.abs( ( size.x or 0 ) * ( size.y or 0 ) * ( size.z or 0 ) )
		if vol > 1 then
			return true
		end
	end

	return false
end

local function carrySlot0( player )
	if not player then
		return nil, nil
	end
	local carry = nil
	pcall( function()
		carry = player:getCarry()
	end )
	if not carry then
		return nil, nil
	end
	local item = nil
	pcall( function()
		item = carry:getItem( 0 )
	end )
	if not itemUuidOk( item ) then
		return carry, nil
	end
	return carry, item
end

local function localCarryItem()
	local carry = nil
	pcall( function()
		carry = sm.localPlayer.getCarry()
	end )
	if not carry then
		return nil
	end
	local item = nil
	pcall( function()
		item = carry:getItem( 0 )
	end )
	if not itemUuidOk( item ) then
		return nil
	end
	return item
end

function RfsCarry.playerIsCarrying( player )
	if not player then
		return false
	end
	local _, item = carrySlot0( player )
	return itemIsBigLift( item )
end

function RfsCarry.localIsCarrying()
	return itemIsBigLift( localCarryItem() )
end

-- Server only. First identical big-item place always goes through; a second within 0.5s is ignored.
local function svIgnoreDuplicateBigPlace( player )
	local _, item = carrySlot0( player )
	if not itemIsBigLift( item ) then
		return false
	end
	local id = playerIdOf( player )
	local u = uuidKey( item.uuid )
	if not id or not u then
		return false
	end
	RfsCarry._svPlace = RfsCarry._svPlace or {}
	local rec = RfsCarry._svPlace[id]
	local tick = currentTick()
	if rec and rec.uuid == u and rec.unlock and tick < rec.unlock then
		return true
	end
	RfsCarry._svPlace[id] = { uuid = u, unlock = tick + PLACE_COOLDOWN_TICKS }
	return false
end

local function toolOwner( self )
	local player = nil
	pcall( function()
		player = self.tool:getOwner()
	end )
	return player
end

local function unwrapIfOurs( cls, key, wrapKey, origKey )
	if type( cls ) ~= "table" then
		return
	end
	if cls[origKey] and ( cls[key] == cls[wrapKey] or cls[wrapKey] ) then
		cls[key] = cls[origKey]
	end
	cls[wrapKey] = nil
	cls[origKey] = nil
end

local function wrapIfChanged( cls, key, wrapKey, origKey, makeWrap )
	if type( cls ) ~= "table" or type( cls[key] ) ~= "function" then
		return false
	end
	if cls[wrapKey] and cls[key] == cls[wrapKey] then
		return true
	end
	cls[origKey] = cls[key]
	cls[wrapKey] = makeWrap( cls[origKey] )
	cls[key] = cls[wrapKey]
	return true
end

function RfsCarry.ensureCarryToolHooks()
	if type( CarryTool ) ~= "table" then
		pcall( function()
			dofile( "$SURVIVAL_DATA/Scripts/game/tools/CarryTool.lua" )
		end )
	end
	if type( CarryTool ) ~= "table" then
		return false
	end

	-- Never consume LMB/RMB on CarryTool. Vanilla drop/place for Craftbot/refinery/units.
	unwrapIfOurs( CarryTool, "client_onEquippedUpdate", "_rfsCarryEqWrap", "_rfsCarryEqOrig" )
	unwrapIfOurs( CarryTool, "client_onEquippedUpdate", "_rfsCarry2EqWrap", "_rfsCarry2EqOrig" )

	-- Drop stays vanilla. Do not rebind or swallow drop RPCs.
	unwrapIfOurs( CarryTool, "sv_n_dropCarry", "_rfsCarryDropWrap", "_rfsCarryDropOrig" )
	if RfsCarry._svDropOrig and ( Sv_DropCarry == RfsCarry._svDropWrap or RfsCarry._svDropWrap ) then
		Sv_DropCarry = RfsCarry._svDropOrig
	end
	RfsCarry._svDropWrap = nil
	RfsCarry._svDropOrig = nil

	-- Unwrap old param-bind place wraps; optional anti-dupe is ignore-only (no client consume).
	unwrapIfOurs( CarryTool, "sv_n_sendItem", "_rfsCarrySendWrap", "_rfsCarrySendOrig" )
	unwrapIfOurs( CarryTool, "sv_n_sendItemToHarvestable", "_rfsCarrySendHvsWrap", "_rfsCarrySendHvsOrig" )

	wrapIfChanged( CarryTool, "sv_n_sendItem", "_rfsCarry3SendWrap", "_rfsCarry3SendOrig",
		function( orig )
			return function( self, params, player )
				if svIgnoreDuplicateBigPlace( player ) then
					return
				end
				return orig( self, params, player )
			end
		end )

	wrapIfChanged( CarryTool, "sv_n_sendItemToHarvestable", "_rfsCarry3SendHvsWrap", "_rfsCarry3SendHvsOrig",
		function( orig )
			return function( self, params, player )
				if svIgnoreDuplicateBigPlace( player ) then
					return
				end
				return orig( self, params, player )
			end
		end )

	if not CarryTool._rfsCarry3Hardened then
		CarryTool._rfsCarryHardened = true
		CarryTool._rfsCarry2Hardened = true
		CarryTool._rfsCarry3Hardened = true
		print( "[RFS] CarryTool LMB/RMB wrap removed; vanilla drop/place (server 0.5s duplicate place ignore)" )
	end
	return true
end

-- Client consume wraps on hand tools also ate LMB. Unwrap only; never re-wrap equipped-update.
local HAND_USE_CLIENT = {
	"ResourceTool", "Planter", "Fertilizer", "Bucket", "Glowstick",
	"Feeder", "ClayTool", "KeyTool", "Cornade",
}

-- Tools that must never have CarryTool/hand consume wraps (inventory-held, not lifts).
local NEVER_WRAP_CLIENT = {
	"Sledgehammer", "PotatoRifle", "PotatoShotgun", "PotatoGatling",
	"PotatoLauncher", "ScrapPotatoRifle", "ClayRifle", "ExtinguisherTool",
	"LogBook", "SurvivalLift",
}

local function unwrapHandEquippedUpdate( cls )
	unwrapIfOurs( cls, "client_onEquippedUpdate", "_rfsCarryHandEqWrap", "_rfsCarryHandEqOrig" )
	unwrapIfOurs( cls, "client_onEquippedUpdate", "_rfsCarry2HandEqWrap", "_rfsCarry2HandEqOrig" )
	unwrapIfOurs( cls, "client_onEquippedUpdate", "_rfsCarryEqWrap", "_rfsCarryEqOrig" )
	unwrapIfOurs( cls, "client_onEquippedUpdate", "_rfsCarry2EqWrap", "_rfsCarry2EqOrig" )
end

local function wrapSvRejectIfCarrying( cls, methodName )
	local wrapKey = "_rfsCarrySvWrap_" .. methodName
	local origKey = "_rfsCarrySvOrig_" .. methodName
	wrapIfChanged( cls, methodName, wrapKey, origKey,
		function( orig )
			return function( self, a, b, ... )
				local player = b
				if player == nil or type( player ) == "table" then
					player = toolOwner( self )
				end
				if RfsCarry.playerIsCarrying( player ) then
					return
				end
				return orig( self, a, b, ... )
			end
		end )
end

function RfsCarry.ensureHandUseHooks()
	for _, name in ipairs( NEVER_WRAP_CLIENT ) do
		local cls = _G[name]
		if type( cls ) == "table" then
			unwrapIfOurs( cls, "client_onEquippedUpdate", "_rfsCarryHandEqWrap", "_rfsCarryHandEqOrig" )
			unwrapIfOurs( cls, "client_onEquippedUpdate", "_rfsCarry2HandEqWrap", "_rfsCarry2HandEqOrig" )
			unwrapIfOurs( cls, "client_onEquippedUpdate", "_rfsCarryEqWrap", "_rfsCarryEqOrig" )
			unwrapIfOurs( cls, "client_onEquippedUpdate", "_rfsCarry2EqWrap", "_rfsCarry2EqOrig" )
		end
	end

	-- Unwrap leftover client consume wraps. Do not dofile tool scripts here.
	for _, name in ipairs( HAND_USE_CLIENT ) do
		local cls = _G[name]
		if type( cls ) == "table" then
			unwrapHandEquippedUpdate( cls )
		end
	end

	local ResourceTool = _G.ResourceTool
	if type( ResourceTool ) == "table" then
		wrapSvRejectIfCarrying( ResourceTool, "sv_n_use" )
	end
	local Planter = _G.Planter
	if type( Planter ) == "table" then
		wrapSvRejectIfCarrying( Planter, "sv_n_plant" )
	end
	local Fertilizer = _G.Fertilizer
	if type( Fertilizer ) == "table" then
		wrapSvRejectIfCarrying( Fertilizer, "sv_n_fertilize" )
	end
	local Bucket = _G.Bucket
	if type( Bucket ) == "table" then
		wrapSvRejectIfCarrying( Bucket, "sv_n_onUse" )
	end
	local Glowstick = _G.Glowstick
	if type( Glowstick ) == "table" then
		wrapSvRejectIfCarrying( Glowstick, "sv_n_onThrowAnim" )
	end
	local Feeder = _G.Feeder
	if type( Feeder ) == "table" then
		wrapSvRejectIfCarrying( Feeder, "sv_n_feed" )
	end
	local ClayTool = _G.ClayTool
	if type( ClayTool ) == "table" then
		wrapSvRejectIfCarrying( ClayTool, "sv_n_buildClay" )
	end
	local KeyTool = _G.KeyTool
	if type( KeyTool ) == "table" then
		wrapSvRejectIfCarrying( KeyTool, "sv_n_use" )
	end
	local Cornade = _G.Cornade
	if type( Cornade ) == "table" then
		wrapSvRejectIfCarrying( Cornade, "sv_n_use" )
		wrapSvRejectIfCarrying( Cornade, "sv_n_spawn" )
		wrapSvRejectIfCarrying( Cornade, "sv_n_onUse" )
	end

	-- Eat / SoilBag: server RPCs only (Farming owns client_onEquippedUpdate).
	local Eat = _G.Eat
	if type( Eat ) == "table" then
		wrapSvRejectIfCarrying( Eat, "sv_n_startEat" )
		wrapSvRejectIfCarrying( Eat, "sv_n_stopEat" )
	end

	local SoilBag = _G.SoilBag
	if type( SoilBag ) == "table" then
		wrapSvRejectIfCarrying( SoilBag, "sv_n_putSoil" )
	end
end

local function inheritPlayerFn( key )
	if type( Player[key] ) == "function" then
		return true
	end
	local base = nil
	if type( SurvivalPlayer ) == "table" and type( SurvivalPlayer[key] ) == "function" then
		base = SurvivalPlayer[key]
	elseif type( BasePlayer ) == "table" and type( BasePlayer[key] ) == "function" then
		base = BasePlayer[key]
	end
	if base then
		Player[key] = base
		return true
	end
	return false
end

function RfsCarry.ensurePlayerClassHooks()
	if type( Player ) ~= "table" then
		return false
	end

	inheritPlayerFn( "sv_e_eat" )
	wrapIfChanged( Player, "sv_e_eat", "_rfsCarryEatWrap", "_rfsCarryEatOrig",
		function( orig )
			return function( self, edibleParams )
				if RfsCarry.playerIsCarrying( self.player ) then
					return
				end
				return orig( self, edibleParams )
			end
		end )

	inheritPlayerFn( "sv_n_exchangeItem" )

	wrapIfChanged( Player, "sv_n_exchangeItem", "_rfsCarryExWrap", "_rfsCarryExOrig",
		function( orig )
			return function( self, params )
				if RfsCarry.playerIsCarrying( self.player ) then
					return
				end
				return orig( self, params )
			end
		end )

	return true
end

function RfsCarry.ensureHooks()
	if RfsCarry._clUnlockTick == nil then
		RfsCarry.resetPlaceLock()
	end
	RfsCarry.ensureCarryToolHooks()
	RfsCarry.ensureHandUseHooks()
	RfsCarry.ensurePlayerClassHooks()
end
