-- RfsRechargeBox.lua — 5 slots, stackSize 1. Each cell = 20 vanilla batteries.
-- Electricity in (solar) + electricity out (Deep Sleep Pod / devices).
-- Charge lives per inserted cell. Empty slots stay empty.
-- Always setActive(false). Do not gulp pipeGraph.

RfsRechargeBox = class( nil )
RfsRechargeBox.maxParentCount = 255
RfsRechargeBox.maxChildCount = 255
RfsRechargeBox.connectionInput = sm.interactable.connectionType.electricity
RfsRechargeBox.connectionOutput = sm.interactable.connectionType.electricity
RfsRechargeBox.colorNormal = sm.color.new( 0xffca1aff )
RfsRechargeBox.colorHighlight = sm.color.new( 0xffe27aff )
RfsRechargeBox.connectIcon = "electrical"
RfsRechargeBox.connectIconScale = 0.75

local RFS_CG = "$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247"
local LAYOUT = "$CONTENT_DATA/Gui/Layouts/Rfs_RechargeBox.layout"
local LAYOUT_CG = RFS_CG .. "/Gui/Layouts/Rfs_RechargeBox.layout"
local function rfsDofile( rel )
	local paths = { RFS_CG .. "/" .. rel, "$CONTENT_DATA/" .. rel }
	for _, p in ipairs( paths ) do
		local ok = pcall( function()
			dofile( p )
		end )
		if ok then
			return true
		end
	end
	return false
end
rfsDofile( "Scripts/game/RfsRecharge.lua" )

local function shapeKey( shape )
	local id = nil
	pcall( function()
		id = shape.id
	end )
	if id ~= nil then
		return tostring( id )
	end
	return tostring( shape )
end

local function cellMilli()
	return ( type( RfsRecharge ) == "table" and RfsRecharge.FULL_MILLI ) or 20000
end

local function boxSlots()
	return ( type( RfsRecharge ) == "table" and RfsRecharge.BOX_SLOTS ) or 5
end

local function boxStack()
	return ( type( RfsRecharge ) == "table" and RfsRecharge.BOX_STACK ) or 1
end

local function emptyUuid()
	if type( RfsRecharge ) == "table" and RfsRecharge.itemUuid then
		return RfsRecharge.itemUuid()
	end
	return sm.uuid.new( "8b513e7d-a4f6-4039-bc82-e3f70a4b6d9e" )
end

local function fullUuid()
	if type( RfsRecharge ) == "table" and RfsRecharge.itemFullUuid then
		return RfsRecharge.itemFullUuid()
	end
	return sm.uuid.new( "a0d8469f-c618-425b-de14-06203d7e90c1" )
end

local function isCellId( id )
	if type( RfsRecharge ) == "table" and RfsRecharge.isCellId then
		return RfsRecharge.isCellId( id )
	end
	return false
end

local function uuidStr( u )
	if type( RfsRecharge ) == "table" and RfsRecharge.uuidStr then
		return RfsRecharge.uuidStr( u )
	end
	return string.lower( tostring( u or "" ) )
end

local function cellCountOf( self )
	local n = 0
	pcall( function()
		n = RfsRecharge.boxCellCount( self.interactable )
	end )
	n = tonumber( n ) or 0
	if n < 0 then
		n = 0
	end
	local slots = boxSlots()
	if n > slots then
		n = slots
	end
	return n
end

local function getBoxContainer( self )
	local container = nil
	pcall( function()
		container = self.shape.interactable:getContainer( 0 )
	end )
	return container
end

local function slotItemId( container, slot )
	if not container or not sm.exists( container ) then
		return nil
	end
	local item = nil
	pcall( function()
		item = container:getItem( slot )
	end )
	if type( item ) ~= "table" then
		return nil
	end
	local qty = tonumber( item.quantity ) or 0
	if qty < 1 then
		return nil
	end
	local id = uuidStr( item.uuid )
	if isCellId( id ) then
		return id
	end
	return nil
end

local function swapSlotUuid( container, slot, fromUuid, toUuid )
	if not container or not fromUuid or not toUuid then
		return
	end
	pcall( function()
		if sm.container.beginTransaction() then
			sm.container.spendFromSlot( container, slot, fromUuid, 1, true )
			sm.container.collectToSlot( container, slot, toUuid, 1, true )
			if not sm.container.endTransaction() then
				sm.container.abortTransaction()
			end
		end
	end )
end

local function capMilli( self )
	local n = cellCountOf( self )
	local one = cellMilli()
	if n < 1 then
		return 0
	end
	return n * one
end

local function sumSlots( self )
	local sum = 0
	local slots = boxSlots()
	self.sv.slotMilli = self.sv.slotMilli or {}
	for i = 1, slots do
		sum = sum + ( tonumber( self.sv.slotMilli[i] ) or 0 )
	end
	return sum
end

local function syncSlots( self )
	local container = getBoxContainer( self )
	local slots = boxSlots()
	local one = cellMilli()
	self.sv.slotMilli = self.sv.slotMilli or {}
	self.sv.slotOcc = self.sv.slotOcc or {}
	local empty = emptyUuid()
	local full = fullUuid()
	for i = 0, slots - 1 do
		local idx = i + 1
		local id = slotItemId( container, i )
		local occ = id ~= nil
		local was = self.sv.slotOcc[idx] and true or false
		if occ and not was then
			if id == uuidStr( full ) then
				self.sv.slotMilli[idx] = one
			else
				self.sv.slotMilli[idx] = 0
			end
		elseif not occ then
			self.sv.slotMilli[idx] = 0
		end
		self.sv.slotOcc[idx] = occ
		local m = tonumber( self.sv.slotMilli[idx] ) or 0
		if occ then
			if m < 0 then
				m = 0
			end
			if m > one then
				m = one
			end
			self.sv.slotMilli[idx] = m
			local wantFull = m >= one
			local isFull = id == uuidStr( full )
			if wantFull and not isFull then
				swapSlotUuid( container, i, empty, full )
			elseif ( not wantFull ) and isFull then
				swapSlotUuid( container, i, full, empty )
			end
		else
			self.sv.slotMilli[idx] = 0
		end
	end
	self.sv.chargeMilli = sumSlots( self )
end

local function publish( self )
	local has = false
	local cells = 0
	pcall( function()
		has = RfsRecharge.boxHasCell( self.interactable )
		cells = cellCountOf( self )
	end )
	if cells < 1 then
		has = false
	end
	local cap = capMilli( self )
	if cap < 1 then
		cap = cellMilli()
	end
	local data = {
		chargeMilli = self.sv.chargeMilli or 0,
		hasCell = has and true or false,
		cellCount = cells,
		full = cap,
		slotMilli = {},
	}
	local slots = boxSlots()
	self.sv.slotMilli = self.sv.slotMilli or {}
	for i = 1, slots do
		data.slotMilli[i] = tonumber( self.sv.slotMilli[i] ) or 0
	end
	pcall( function()
		self.network:setClientData( data )
	end )
	pcall( function()
		self.interactable:setPublicData( data )
	end )
	pcall( function()
		self.interactable:setActive( false )
	end )
end

local function ensureContainer( self )
	local slots = boxSlots()
	local stack = boxStack()
	local container = nil
	pcall( function()
		container = self.shape.interactable:getContainer( 0 )
	end )
	if not container then
		pcall( function()
			container = self.shape:getInteractable():addContainer( 0, slots, stack )
		end )
	end
	if container then
		local size = nil
		pcall( function()
			size = container:getSize()
		end )
		if type( size ) ~= "number" then
			pcall( function()
				size = sm.container.getSize( container )
			end )
		end
		if type( size ) == "number" and size ~= slots then
			pcall( function()
				sm.container.resize( container, slots )
			end )
			pcall( function()
				container:resize( slots )
			end )
		end
		local filters = nil
		pcall( function()
			filters = RfsRecharge.cellFilterUuids()
		end )
		if type( filters ) == "table" then
			pcall( function()
				container:setFilters( filters )
			end )
		end
	end
	return container
end

local function migratePool( self, saved )
	local slots = boxSlots()
	self.sv.slotMilli = {}
	self.sv.slotOcc = {}
	local container = getBoxContainer( self )
	if type( saved ) == "table" and type( saved.slotMilli ) == "table" then
		for i = 1, slots do
			self.sv.slotMilli[i] = tonumber( saved.slotMilli[i] ) or 0
		end
	end
	for i = 0, slots - 1 do
		self.sv.slotOcc[i + 1] = slotItemId( container, i ) ~= nil
	end
	syncSlots( self )
	if type( saved ) == "table" and saved.slotMilli == nil then
		local pool = tonumber( saved.chargeMilli ) or 0
		if pool > 0 then
			local one = cellMilli()
			for i = 1, slots do
				if self.sv.slotOcc[i] and pool > 0 then
					local give = pool
					if give > one then
						give = one
					end
					self.sv.slotMilli[i] = give
					pool = pool - give
				end
			end
			self.sv.chargeMilli = sumSlots( self )
			syncSlots( self )
		end
	end
end

function RfsRechargeBox.server_onCreate( self )
	self.sv = self.sv or {}
	local saved = nil
	pcall( function()
		saved = self.storage:load()
	end )
	ensureContainer( self )
	migratePool( self, saved )
	self.sv.key = shapeKey( self.shape )
	RfsRecharge.boxScripts = RfsRecharge.boxScripts or {}
	RfsRecharge.boxScripts[self.sv.key] = self
	_G.g_rfsRechargeBoxScripts = _G.g_rfsRechargeBoxScripts or {}
	_G.g_rfsRechargeBoxScripts[self.sv.key] = self
	pcall( function()
		self.interactable:setActive( false )
	end )
	publish( self )
end

function RfsRechargeBox.server_onDestroy( self )
	if self.sv and self.sv.key and type( RfsRecharge ) == "table" and RfsRecharge.boxScripts then
		RfsRecharge.boxScripts[self.sv.key] = nil
	end
end

function RfsRechargeBox.sv_save( self )
	pcall( function()
		self.storage:save( {
			chargeMilli = self.sv.chargeMilli or 0,
			slotMilli = self.sv.slotMilli or {},
		} )
	end )
end

function RfsRechargeBox.sv_addMilli( self, milli )
	milli = tonumber( milli ) or 0
	if milli <= 0 then
		return self.sv.chargeMilli or 0
	end
	syncSlots( self )
	local one = cellMilli()
	local slots = boxSlots()
	local left = milli
	for i = 1, slots do
		if left < 1 then
			break
		end
		if self.sv.slotOcc[i] then
			local cur = tonumber( self.sv.slotMilli[i] ) or 0
			if cur < one then
				local room = one - cur
				local add = left
				if add > room then
					add = room
				end
				self.sv.slotMilli[i] = cur + add
				left = left - add
			end
		end
	end
	syncSlots( self )
	self:sv_save()
	publish( self )
	return self.sv.chargeMilli
end

function RfsRechargeBox.sv_spendMilli( self, milli )
	milli = tonumber( milli ) or 0
	if milli <= 0 then
		return false
	end
	syncSlots( self )
	if ( self.sv.chargeMilli or 0 ) < milli then
		return false
	end
	local left = milli
	local slots = boxSlots()
	for i = 1, slots do
		if left < 1 then
			break
		end
		local cur = tonumber( self.sv.slotMilli[i] ) or 0
		if cur > 0 then
			local take = left
			if take > cur then
				take = cur
			end
			self.sv.slotMilli[i] = cur - take
			left = left - take
		end
	end
	if left > 0 then
		return false
	end
	syncSlots( self )
	self:sv_save()
	publish( self )
	return true
end

function RfsRechargeBox.sv_e_rfsSpendMilli( self, params )
	self:sv_spendMilli( params and params.milli )
end

function RfsRechargeBox.sv_e_rfsAddMilli( self, params )
	self:sv_addMilli( params and params.milli )
end

function RfsRechargeBox.server_onFixedUpdate( self )
	pcall( function()
		self.interactable:setActive( false )
	end )
	if ( sm.game.getCurrentTick() % 20 ) == 0 then
		local before = self.sv.chargeMilli or 0
		syncSlots( self )
		if ( self.sv.chargeMilli or 0 ) ~= before then
			self:sv_save()
		end
		publish( self )
	end
end

function RfsRechargeBox.client_onCreate( self )
	self.cl = { chargeMilli = 0, hasCell = false, cellCount = 0, full = 20000, slotMilli = {} }
end

function RfsRechargeBox.client_onClientDataUpdate( self, data )
	if type( data ) == "table" then
		self.cl = data
		self:cl_refreshChargeGui()
	end
end

local function openChargeGui( self, container )
	local gui = nil
	local function tryLayout( path, opts )
		if gui then
			return
		end
		local ok, created = pcall( sm.gui.createGuiFromLayout, path, false, opts )
		if ok and created then
			gui = created
		end
	end
	tryLayout( LAYOUT, { needsCursor = true } )
	tryLayout( LAYOUT_CG, { needsCursor = true } )
	tryLayout( LAYOUT, false )
	tryLayout( LAYOUT_CG, false )
	if not gui then
		pcall( function()
			gui = sm.gui.createBatteryContainerGui( true )
		end )
	end
	if not gui then
		gui = sm.gui.createContainerGui( true )
	end
	pcall( function()
		gui:setText( "UpperName", "Rechargeable Battery" )
	end )
	pcall( function()
		gui:setText( "ChargeLabel", "Charge 0%" )
	end )
	pcall( function()
		gui:setContainer( "UpperGrid", container )
	end )
	pcall( function()
		gui:setText( "LowerName", "Backpack" )
	end )
	pcall( function()
		gui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
	end )
	pcall( function()
		gui:setOnCloseCallback( "cl_e_onClose" )
	end )
	pcall( function()
		gui:open()
	end )
	return gui
end

function RfsRechargeBox.cl_refreshChargeGui( self )
	if not self.gui then
		return
	end
	local pd = self.cl or {}
	local milli = tonumber( pd.chargeMilli ) or 0
	local cap = tonumber( pd.full ) or cellMilli()
	if cap < 1 then
		cap = cellMilli()
	end
	local frac = 0
	if ( tonumber( pd.cellCount ) or 0 ) >= 1 then
		frac = milli / cap
	end
	local pct = 0
	if type( RfsRecharge ) == "table" and RfsRecharge.applyChargePips then
		pct = RfsRecharge.applyChargePips( self.gui, "ChargePip", frac )
	else
		pct = math.floor( frac * 100 + 0.5 )
	end
	pcall( function()
		self.gui:setText( "ChargeLabel", string.format( "Charge %d%%", pct ) )
	end )
	pcall( function()
		self.gui:setVisible( "ChargeTrack", true )
	end )
end

function RfsRechargeBox.client_onInteract( self, character, state )
	if state ~= true then
		return
	end
	local container = self.shape.interactable:getContainer( 0 )
	if not container then
		return
	end
	self.gui = openChargeGui( self, container )
	self:cl_refreshChargeGui()
end

function RfsRechargeBox.cl_e_onClose( self )
	self.gui = nil
end

function RfsRechargeBox.client_onDestroy( self )
	if self.gui then
		pcall( function()
			self.gui:close()
			self.gui:destroy()
		end )
		self.gui = nil
	end
end

function RfsRechargeBox.client_onUpdate( self, dt )
	if self.gui then
		self:cl_refreshChargeGui()
	end
end

function RfsRechargeBox.client_canInteract( self )
	local pd = self.cl or {}
	local cells = tonumber( pd.cellCount ) or 0
	local full = tonumber( pd.full ) or cellMilli()
	local milli = tonumber( pd.chargeMilli ) or 0
	if not pd.hasCell or cells < 1 then
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "Rechargeable Battery Box (no cells)" )
		return true
	end
	if full < 1 then
		full = cellMilli()
	end
	local pct = math.floor( ( milli / full ) * 100 + 0.5 )
	sm.gui.setInteractionText(
		"",
		sm.gui.getKeyBinding( "Use", true ),
		string.format( "Rechargeable %d%%  (%d / %d cells)", pct, cells, boxSlots() )
	)
	return true
end

function RfsRechargeBox.client_getAvailableParentConnectionCount( self, connectionType )
	local elec = sm.interactable.connectionType.electricity
	local ok = false
	if type( bit ) == "table" and type( bit.band ) == "function" then
		ok = bit.band( connectionType, elec ) ~= 0
	else
		ok = type( connectionType ) == "number" and connectionType % ( elec * 2 ) >= elec
	end
	if ok then
		local n = 0
		pcall( function()
			n = #( self.interactable:getParents( elec ) or {} )
		end )
		return 255 - n
	end
	return 0
end

function RfsRechargeBox.client_getAvailableChildConnectionCount( self, connectionType )
	local elec = sm.interactable.connectionType.electricity
	local ok = false
	if type( bit ) == "table" and type( bit.band ) == "function" then
		ok = bit.band( connectionType, elec ) ~= 0
	else
		ok = type( connectionType ) == "number" and connectionType % ( elec * 2 ) >= elec
	end
	if ok then
		local n = 0
		pcall( function()
			n = #( self.interactable:getChildren( elec ) or {} )
		end )
		return 255 - n
	end
	return 0
end

print( "[RFS] RfsRechargeBox loaded (per-cell charge; empty slots stay empty)" )
