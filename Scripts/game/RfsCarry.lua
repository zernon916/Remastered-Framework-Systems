-- RfsCarry.lua — Anti-dupe is a short place cooldown, not a permanent carry lock.
-- Vanilla CarryTool.client_onEquippedUpdate does not consume LMB for large pickups
-- (craftbot, seed crate, …), so the previously selected hand item can still place/use.
-- After a successful place, ignore further place for 0.5s (20 ticks at 40Hz).
-- Drop/throw of carried units must still go through; never swallow server drop.

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

local function containerOccupied( container )
	if not container then
		return false
	end
	local empty = true
	pcall( function()
		empty = container:isEmpty()
	end )
	if empty then
		return false
	end
	-- Phantom occupy (no slot 0 item): do not lock place/drop forever.
	local item = nil
	pcall( function()
		item = container:getItem( 0 )
	end )
	return itemUuidOk( item )
end

function RfsCarry.playerIsCarrying( player )
	if not player then
		return false
	end
	local carry = nil
	pcall( function()
		carry = player:getCarry()
	end )
	return containerOccupied( carry )
end

function RfsCarry.localIsCarrying()
	local carry = nil
	pcall( function()
		carry = sm.localPlayer.getCarry()
	end )
	return containerOccupied( carry )
end

local function toolOwner( self )
	local player = nil
	pcall( function()
		player = self.tool:getOwner()
	end )
	return player
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

-- Bind drop/insert to the server carry slot. Ignore client-supplied item identity.
local function bindServerCarryItem( params, player )
	if type( params ) ~= "table" then
		return false
	end
	local carry, item = carrySlot0( player )
	if not carry or not item then
		return false
	end
	params.containerA = carry
	params.itemA = item.uuid
	params.quantityA = 1
	return true
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

	wrapIfChanged( CarryTool, "client_onEquippedUpdate", "_rfsCarryEqWrap", "_rfsCarryEqOrig",
		function( orig )
			return function( self, primaryState, secondaryState, ... )
				local c1, c2 = false, false
				if orig then
					c1, c2 = orig( self, primaryState, secondaryState, ... )
				end
				c1 = c1 and true or false
				c2 = c2 and true or false
				-- Orig already sent drop/place. Honor that; never force-consume RMB.
				if c1 then
					RfsCarry.markPlace()
				end
				-- After a successful place, ignore further PLACE for 0.5s (anti-dupe).
				if RfsCarry.placeLocked() then
					c1 = true
				end
				-- While a real carry item is held, do not let unconsumed LMB clone the hotbar.
				if RfsCarry.localIsCarrying() then
					c1 = true
				end
				return c1, c2
			end
		end )

	wrapIfChanged( CarryTool, "sv_n_dropCarry", "_rfsCarryDropWrap", "_rfsCarryDropOrig",
		function( orig )
			return function( self, params, player )
				bindServerCarryItem( params, player )
				return orig( self, params, player )
			end
		end )

	wrapIfChanged( CarryTool, "sv_n_sendItem", "_rfsCarrySendWrap", "_rfsCarrySendOrig",
		function( orig )
			return function( self, params, player )
				bindServerCarryItem( params, player )
				return orig( self, params, player )
			end
		end )

	wrapIfChanged( CarryTool, "sv_n_sendItemToHarvestable", "_rfsCarrySendHvsWrap", "_rfsCarrySendHvsOrig",
		function( orig )
			return function( self, params, player )
				bindServerCarryItem( params, player )
				return orig( self, params, player )
			end
		end )

	if type( Sv_DropCarry ) == "function" then
		if Sv_DropCarry ~= RfsCarry._svDropWrap then
			RfsCarry._svDropOrig = Sv_DropCarry
			RfsCarry._svDropWrap = function( params )
				local player = params and params.player or nil
				bindServerCarryItem( params, player )
				return RfsCarry._svDropOrig( params )
			end
			Sv_DropCarry = RfsCarry._svDropWrap
		end
	end

	if not CarryTool._rfsCarryHardened then
		CarryTool._rfsCarryHardened = true
		print( "[RFS] CarryTool place cooldown 0.5s (drop always reaches vanilla)" )
	end
	return true
end

-- Client: other tools skip PLACE during the 0.5s cooldown (equip-race dupe window).
-- Do not consume input for the whole carry — that permanently stuck craftbot drop.
-- Skip Eat/SoilBag equipped-update — RfsFarming owns those pointers.
local HAND_USE_CLIENT = {
	"ResourceTool", "Planter", "Fertilizer", "Bucket", "Glowstick",
	"Feeder", "ClayTool", "KeyTool", "Cornade", "Sledgehammer",
}

local function wrapHandEquippedUpdate( cls )
	wrapIfChanged( cls, "client_onEquippedUpdate", "_rfsCarryHandEqWrap", "_rfsCarryHandEqOrig",
		function( orig )
			return function( self, primaryState, secondaryState, ... )
				if RfsCarry.placeLocked() then
					return true, false
				end
				local c1, c2 = orig( self, primaryState, secondaryState, ... )
				if c1 then
					RfsCarry.markPlace()
				end
				return c1, c2
			end
		end )
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
	-- Wrap only classes the engine already loaded (currently equipped / used).
	-- Do not dofile tool scripts here — that can reset vanilla class tables.
	for _, name in ipairs( HAND_USE_CLIENT ) do
		local cls = _G[name]
		if type( cls ) == "table" then
			wrapHandEquippedUpdate( cls )
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
