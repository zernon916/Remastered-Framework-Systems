-- RfsCorn.lua — placed corn stack quantity for Recipe Framework Survival
-- Author: DemonsDen126
-- Vanilla corn shapes are qty 1. RFS force-place can stamp a full inventory stack
-- onto one shape so Wocs can eat the whole stack at once.

RfsCorn = class()

dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )

local CORN_UUID = obj_resource_corn

function RfsCorn.server_onCreate( self )
	self.sv = self.storage:load() or {}
	local qty = 1
	local armKey = _G.g_rfsPendingCornArmKey
	local pending = _G.g_rfsPendingCornQty
	if type( pending ) == "number" and pending > 0 then
		qty = math.floor( pending )
		_G.g_rfsPendingCornQty = nil
		_G.g_rfsPendingCornArmKey = nil
	elseif type( self.sv.qty ) == "number" and self.sv.qty > 1 then
		qty = math.floor( self.sv.qty )
	end
	-- Prefer per-player arm if still fresh (engine place may land after pending clear).
	pcall( function()
		local arms = _G.g_rfsCornArmByPlayer
		if not arms then
			return
		end
		local bestKey, bestArm = nil, nil
		local now = sm.game.getCurrentTick()
		for key, arm in pairs( arms ) do
			if type( arm ) == "table" and type( arm.qty ) == "number" and arm.qty > 0 then
				if not arm.tick or ( now - arm.tick ) <= 80 then
					if not bestArm or arm.qty > bestArm.qty then
						bestKey, bestArm = key, arm
					end
				end
			end
		end
		if bestArm and bestArm.qty > qty then
			qty = math.floor( bestArm.qty )
			armKey = bestKey
		elseif bestArm and not armKey then
			armKey = bestKey
			qty = math.max( qty, math.floor( bestArm.qty ) )
		end
	end )
	pcall( function()
		local map = _G.g_rfsCornQtyById
		local id = self.shape and self.shape.id
		if map and id ~= nil and type( map[id] ) == "number" and map[id] > qty then
			qty = math.floor( map[id] )
		end
	end )
	if qty < 1 then
		qty = 1
	elseif qty > 20 then
		qty = 20
	end
	self.sv.qty = qty
	self.storage:save( self.sv )
	self:sv_syncPublic()
	pcall( function()
		if type( RfsFarming ) == "table" and type( RfsFarming.sv_onCornStackPlaced ) == "function" then
			RfsFarming.sv_onCornStackPlaced( armKey, self.shape, qty )
		end
	end )
end

-- Force-place stamps qty after createPart (pending alone can race / miss).
function RfsCorn.sv_n_setQty( self, params )
	local qty = type( params ) == "table" and tonumber( params.qty ) or nil
	if not qty or qty < 1 then
		return
	end
	self.sv = self.sv or {}
	self.sv.qty = math.floor( qty )
	self.storage:save( self.sv )
	self:sv_syncPublic()
	pcall( function()
		_G.g_rfsCornQtyById = _G.g_rfsCornQtyById or {}
		if self.shape and self.shape.id ~= nil then
			_G.g_rfsCornQtyById[self.shape.id] = self.sv.qty
		end
	end )
end

function RfsCorn.sv_syncPublic( self )
	local qty = self.sv.qty or 1
	if self.interactable and sm.exists( self.interactable ) then
		self.interactable:setPublicData( { rfsCornQty = qty } )
	end
	pcall( function()
		self.network:setClientData( { qty = qty } )
	end )
end

function RfsCorn.sv_getQty( self )
	return math.max( 1, math.floor( self.sv and self.sv.qty or 1 ) )
end

-- Called by Woc hook before destroyShape; returns corn count consumed.
function RfsCorn.sv_consumeStack( self )
	local qty = self:sv_getQty()
	self.sv.qty = 0
	self.storage:save( self.sv )
	self:sv_syncPublic()
	return qty
end

function RfsCorn.client_onCreate( self )
	self.cl = self.cl or {}
end

function RfsCorn.client_onClientDataUpdate( self, data )
	self.cl = self.cl or {}
	if type( data ) == "table" and data.qty then
		self.cl.qty = data.qty
	end
end

function RfsCorn.client_canInteract( self )
	local qty = 1
	if self.cl and type( self.cl.qty ) == "number" and self.cl.qty > 0 then
		qty = math.floor( self.cl.qty )
	end
	-- Client must not call getPublicData (server-only → sandbox violation spam).
	if self.interactable and sm.exists( self.interactable ) then
		pcall( function()
			local pd = nil
			if type( self.interactable.getClientPublicData ) == "function" then
				pd = self.interactable:getClientPublicData()
			end
			if type( pd ) == "table" and type( pd.rfsCornQty ) == "number" and pd.rfsCornQty > 0 then
				qty = math.max( qty, math.floor( pd.rfsCornQty ) )
			end
		end )
	end
	local key = sm.gui.getKeyBinding( "Use", true )
	if qty > 1 then
		sm.gui.setInteractionText( "", key, "Pick up Corn x" .. tostring( qty ) )
	else
		sm.gui.setInteractionText( "", key, "#{INTERACTION_PICK_UP} Corn" )
	end
	return true
end

function RfsCorn.client_onInteract( self, character, state )
	if state == true then
		self.network:sendToServer( "sv_n_pickup" )
	end
end

function RfsCorn.sv_n_pickup( self, player )
	if not player or not sm.exists( self.shape ) then
		return
	end
	local qty = self:sv_getQty()
	local inv = player:getInventory()
	if not inv then
		return
	end
	local ok = false
	pcall( function()
		if sm.container.beginTransaction() then
			sm.container.collect( inv, CORN_UUID, qty, true )
			ok = sm.container.endTransaction() == true
		end
	end )
	if ok then
		self.shape:destroyShape()
	end
end

---------------------------------------------------------------------------
-- Helpers used by Eat / Woc hooks (no interactable instance required)
---------------------------------------------------------------------------

function RfsCorn.getShapeQty( shape )
	if not shape or not sm.exists( shape ) then
		return 1
	end
	local qty = 1
	pcall( function()
		local ia = shape:getInteractable()
		if ia and sm.exists( ia ) then
			local pd = ia:getPublicData()
			if type( pd ) == "table" and type( pd.rfsCornQty ) == "number" and pd.rfsCornQty > 0 then
				qty = math.floor( pd.rfsCornQty )
			end
		end
	end )
	if qty <= 1 then
		pcall( function()
			local map = _G.g_rfsCornQtyById
			local id = shape.id
			if map and id ~= nil and type( map[id] ) == "number" and map[id] > 0 then
				qty = math.floor( map[id] )
			end
		end )
	end
	return math.max( 1, qty )
end

function RfsCorn.consumeShapeQty( shape )
	-- Read qty first, then clear via event / registry (destroyShape follows in Woc hook).
	local qty = RfsCorn.getShapeQty( shape )
	pcall( function()
		local ia = shape:getInteractable()
		if ia and sm.exists( ia ) then
			sm.event.sendToInteractable( ia, "sv_consumeStack" )
		end
	end )
	pcall( function()
		local map = _G.g_rfsCornQtyById
		local id = shape.id
		if map and id ~= nil then
			map[id] = nil
		end
	end )
	return math.max( 1, qty )
end
