-- RfsCorn.lua — placed corn stack quantity for Recipe Framework Survival
-- Author: DemonsDen126
-- Vanilla corn shapes are qty 1. RFS force-place can stamp a full inventory stack
-- onto one shape so Wocs can eat the whole stack at once.

RfsCorn = class()

dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )

local CORN_UUID = obj_resource_corn

function RfsCorn.server_onCreate( self )
	self.sv = self.storage:load() or {}
	local pending = _G.g_rfsPendingCornQty
	if type( pending ) == "number" and pending > 0 then
		self.sv.qty = math.floor( pending )
		_G.g_rfsPendingCornQty = nil
	elseif type( self.sv.qty ) ~= "number" or self.sv.qty < 1 then
		self.sv.qty = 1
	end
	self.storage:save( self.sv )
	self:sv_syncPublic()
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
	if self.interactable and sm.exists( self.interactable ) then
		local pd = self.interactable:getClientPublicData() or self.interactable:getPublicData()
		if type( pd ) == "table" and type( pd.rfsCornQty ) == "number" then
			qty = math.max( 1, math.floor( pd.rfsCornQty ) )
		end
	end
	if self.cl and self.cl.qty then
		qty = math.max( qty, self.cl.qty )
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
		ok = sm.container.collect( inv, CORN_UUID, qty, true )
	end )
	if not ok then
		pcall( function()
			ok = sm.container.collect( inv, CORN_UUID, qty )
		end )
	end
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
