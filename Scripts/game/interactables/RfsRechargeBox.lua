-- RfsRechargeBox.lua — 5 slots, stackSize 1. One rechargeable cell per slot.
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
	return boxSlots() * cellMilli()
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
			-- One craftable uuid. Convert leftover Full uuid in-place.
			if id == uuidStr( full ) then
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
	local data = {
		chargeMilli = self.sv.chargeMilli or 0,
		hasCell = has and true or false,
		cellCount = cells,
		full = cap,
		boxCap = cap,
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

local function ensureContainer( self, setFiltersNow )
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
		if setFiltersNow == true then
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
	-- Convert legacy full-cell contents before we apply filters that
	-- only advertise the base Rechargeable Battery uuid.
	ensureContainer( self, false )
	migratePool( self, saved )
	-- After syncSlots/migration, lock filters down to base-only uuids.
	pcall( function()
		local container = getBoxContainer( self )
		if container and container.setFilters then
			local filters = RfsRecharge.cellFilterUuids()
			if type( filters ) == "table" then
				container:setFilters( filters )
			end
		end
	end )
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

-- Defined as a local upvalue so client_onCreate / client_onClientDataUpdate
-- can call it (those functions are declared before the implementation below).
-- (Some log runs call the client entrypoints before the implementation
-- below executes, so keep a harmless stub available up-front.)
refreshSideBars = refreshSideBars or function( self ) end

function RfsRechargeBox.client_onCreate( self )
	self.cl = { chargeMilli = 0, hasCell = false, cellCount = 0, full = 0, slotMilli = {} }
	refreshSideBars( self )
end

function RfsRechargeBox.client_onClientDataUpdate( self, data )
	if type( data ) == "table" then
		self.cl = data
		self:cl_refreshChargeGui()
		refreshSideBars( self )
	end
end

local function closeChargeOverlay( self )
	if self.guiCharge then
		pcall( function()
			self.guiCharge:close()
			self.guiCharge:destroy()
		end )
		self.guiCharge = nil
	end
end

-- C++ createBatteryContainerGui binds ItemBox slots. createGuiFromLayout does not —
-- that was the blank panel (Charge 0% painted, UpperGrid never became a container).
local function openChargeGui( self, container )
	local gui = nil
	pcall( function()
		gui = sm.gui.createBatteryContainerGui( true )
	end )
	if not gui then
		gui = sm.gui.createContainerGui( true )
	end
	gui:setText( "UpperName", "Rechargeable Battery" )
	gui:setContainer( "UpperGrid", container )
	pcall( function()
		gui:setText( "LowerName", "#{INVENTORY_TITLE}" )
	end )
	gui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
	pcall( function()
		gui:setOnCloseCallback( "cl_e_onClose" )
	end )
	-- Selection → refresh inspect info panel (box slot or backpack cell while GUI open).
	pcall( function()
		gui:setGridItemClickedCallback( "UpperGrid", "cl_e_onUpperClicked" )
	end )
	pcall( function()
		gui:setGridItemClickedCallback( "LowerGrid", "cl_e_onLowerClicked" )
	end )
	pcall( function()
		gui:setGridMouseFocusCallback( "UpperGrid", "cl_e_onUpperFocus" )
	end )
	pcall( function()
		gui:setGridMouseFocusCallback( "LowerGrid", "cl_e_onLowerFocus" )
	end )
	pcall( function()
		gui:setGridItemChangedCallback( "UpperGrid", "cl_e_onUpperChanged" )
	end )
	gui:open()
	return gui
end

local function openChargeOverlay()
	local overlay = nil
	local function tryLayout( path, opts )
		if overlay then
			return
		end
		local ok, created = pcall( sm.gui.createGuiFromLayout, path, false, opts )
		if ok and created then
			overlay = created
		end
	end
	-- Non-interactive HUD so it sits beside the battery GUI without stealing clicks.
	local hudOpts = { isHud = true, isInteractive = false, needsCursor = false }
	tryLayout( LAYOUT, hudOpts )
	tryLayout( LAYOUT_CG, hudOpts )
	if overlay then
		pcall( function()
			overlay:open()
		end )
	end
	return overlay
end

local function inspectFrac( self )
	local pd = self.cl or {}
	local src = self.clInspectSource or "box"
	if src == "inv" then
		local f = tonumber( self.clInspectFrac )
		if f ~= nil then
			return f, "inv"
		end
	end
	local slot = tonumber( self.clInspectSlot )
	if slot and slot >= 1 then
		if type( RfsRecharge ) == "table" and RfsRecharge.slotChargeFracFromData then
			return RfsRecharge.slotChargeFracFromData( pd, slot ), "box"
		end
	end
	if type( RfsRecharge ) == "table" and RfsRecharge.boxChargeFracFromData then
		return RfsRecharge.boxChargeFracFromData( pd ), "box"
	end
	local milli = tonumber( pd.chargeMilli ) or 0
	local cap = tonumber( pd.full ) or cellMilli()
	if cap < 1 or ( tonumber( pd.cellCount ) or 0 ) < 1 or not pd.hasCell then
		return 0, "box"
	end
	return milli / cap, "box"
end

local function setInspectBox( self, slotIndex1 )
	self.clInspectSource = "box"
	self.clInspectFrac = nil
	if slotIndex1 ~= nil then
		self.clInspectSlot = tonumber( slotIndex1 )
	else
		self.clInspectSlot = nil
	end
end

local function setInspectInv( self, frac )
	self.clInspectSource = "inv"
	self.clInspectFrac = tonumber( frac ) or 0
end

local function sideBarFrame( self )
	-- World UV bars: total stored / (5 * cell max). One full cell = 1 bar.
	local pd = self.cl or {}
	local cells = tonumber( pd.cellCount ) or 0
	local has = pd.hasCell and cells >= 1
	local frac = 0
	if type( RfsRecharge ) == "table" and RfsRecharge.boxChargeFracFromData then
		frac = RfsRecharge.boxChargeFracFromData( pd )
	else
		frac = boxChargeFrac( self )
	end
	if ( tonumber( pd.chargeMilli ) or 0 ) > 0 then
		has = true
	end
	if type( RfsRecharge ) == "table" and RfsRecharge.sideBarFrame then
		return RfsRecharge.sideBarFrame( frac, has )
	end
	local slots = 5
	if not has then
		return slots
	end
	local lit = math.ceil( frac * slots )
	if frac > 0 and lit < 1 then
		lit = 1
	end
	if frac >= 1 then
		lit = slots
	end
	return slots - lit
end

refreshSideBars = function( self )
	local frame = sideBarFrame( self )
	pcall( function()
		self.interactable:setUvFrameIndex( frame )
	end )
end

local function boxChargeFrac( self )
	local pd = self.cl or {}
	if type( RfsRecharge ) == "table" and RfsRecharge.boxChargeFracFromData then
		return RfsRecharge.boxChargeFracFromData( pd )
	end
	local milli = tonumber( pd.chargeMilli ) or 0
	local cap = tonumber( pd.full ) or cellMilli()
	if cap < 1 then
		return 0
	end
	if ( tonumber( pd.cellCount ) or 0 ) >= 1 and pd.hasCell then
		return milli / cap
	end
	return 0
end

local function hideVanillaBatteryMeter( gui )
	if not gui then
		return
	end
	for _, name in ipairs( {
		"ChargeMeter",
		"BatteryMeter",
		"UpperCharge",
		"ChargeText",
		"BatteryText",
	} ) do
		pcall( function()
			gui:setVisible( name, false )
		end )
	end
end

function RfsRechargeBox.cl_refreshChargeGui( self )
	if not self.gui and not self.guiCharge then
		return
	end
	local pd = self.cl or {}
	local cells = tonumber( pd.cellCount ) or 0
	local hasBoxCell = pd.hasCell and cells >= 1
	local frac, src = inspectFrac( self )
	-- Empty box / no selection → 0% bars off.
	if src == "box" and not hasBoxCell then
		frac = 0
	end
	local pct = 0
	if type( RfsRecharge ) == "table" and RfsRecharge.chargePips then
		_, pct = RfsRecharge.chargePips( frac )
	else
		pct = math.floor( frac * 100 + 0.5 )
	end
	-- Keep box title stable (no floating "Charge 100%" title).
	if self.gui then
		hideVanillaBatteryMeter( self.gui )
		pcall( function()
			self.gui:setText( "UpperName", "Rechargeable Battery" )
		end )
	end
	local info = self.guiCharge
	if not info then
		return
	end
	pcall( function()
		info:setVisible( "BoxChargeRoot", true )
	end )
	pcall( function()
		info:setVisible( "ChargeTrack", true )
	end )
	local nameCaption = "Empty"
	local desc = "No cell in the box. Insert a Rechargeable Battery to store charge."
	if src == "inv" then
		nameCaption = "Rechargeable Battery"
		desc = "Charge is stored in the Rechargeable Battery Box, not on the backpack item."
	elseif hasBoxCell then
		nameCaption = "Rechargeable Battery"
		local slot = tonumber( self.clInspectSlot )
		if slot and slot >= 1 then
			desc = string.format( "Slot %d charge. Solar fills cells in the box; devices drain them.", slot )
		else
			desc = string.format(
				"Box total %d%% (%d cell%s). Click a slot to inspect one cell.",
				pct,
				cells,
				cells == 1 and "" or "s"
			)
		end
	end
	pcall( function()
		info:setText( "InfoItemName", nameCaption )
	end )
	pcall( function()
		info:setText( "InfoDesc", desc )
	end )
	-- Tiny pct under the bar (secondary). Primary meter = pips / ProgressBar.
	pcall( function()
		info:setText( "ChargePctLabel", string.format( "%d%%", pct ) )
	end )
	if type( RfsRecharge ) == "table" then
		if RfsRecharge.applyChargePips then
			pct = RfsRecharge.applyChargePips( info, "ChargePip", frac )
		end
		if RfsRecharge.applyChargeBar then
			RfsRecharge.applyChargeBar( info, "ChargeBar", frac )
		end
	end
end

local function uuidFromClickData( data )
	if type( data ) ~= "table" then
		return nil
	end
	local u = data.uuid or data.itemId or data.id
	if u == nil and type( data.item ) == "table" then
		u = data.item.uuid
	end
	return u
end

function RfsRechargeBox.cl_e_onUpperClicked( self, gridName, index, data )
	setInspectBox( self, ( tonumber( index ) or 0 ) + 1 )
	self:cl_refreshChargeGui()
end

function RfsRechargeBox.cl_e_onUpperFocus( self, gridName, index, data )
	setInspectBox( self, ( tonumber( index ) or 0 ) + 1 )
	self:cl_refreshChargeGui()
end

function RfsRechargeBox.cl_e_onUpperChanged( self, gridName, index, data )
	setInspectBox( self )
	self:cl_refreshChargeGui()
	refreshSideBars( self )
end

function RfsRechargeBox.cl_e_onLowerClicked( self, gridName, index, data )
	local id = uuidStr( uuidFromClickData( data ) )
	local frac = nil
	if type( RfsRecharge ) == "table" and RfsRecharge.uuidChargeFrac then
		frac = RfsRecharge.uuidChargeFrac( id )
	elseif isCellId( id ) then
		frac = ( id == uuidStr( fullUuid() ) ) and 1 or 0
	end
	if frac ~= nil then
		setInspectInv( self, frac )
	else
		setInspectBox( self )
	end
	self:cl_refreshChargeGui()
end

function RfsRechargeBox.cl_e_onLowerFocus( self, gridName, index, data )
	self:cl_e_onLowerClicked( gridName, index, data )
end

function RfsRechargeBox.client_onInteract( self, character, state )
	if state ~= true then
		return
	end
	local container = self.shape.interactable:getContainer( 0 )
	if not container then
		return
	end
	closeChargeOverlay( self )
	setInspectBox( self )
	self.gui = openChargeGui( self, container )
	self.guiCharge = openChargeOverlay()
	self:cl_refreshChargeGui()
	refreshSideBars( self )
end

function RfsRechargeBox.cl_e_onClose( self )
	self.gui = nil
	self.clInspectSource = nil
	self.clInspectFrac = nil
	self.clInspectSlot = nil
	closeChargeOverlay( self )
end

function RfsRechargeBox.client_onDestroy( self )
	if self.gui then
		pcall( function()
			self.gui:close()
			self.gui:destroy()
		end )
		self.gui = nil
	end
	closeChargeOverlay( self )
end

function RfsRechargeBox.client_onUpdate( self, dt )
	if self.gui or self.guiCharge then
		self:cl_refreshChargeGui()
	end
	refreshSideBars( self )
end

function RfsRechargeBox.client_canInteract( self )
	local pd = self.cl or {}
	local cells = tonumber( pd.cellCount ) or 0
	if not pd.hasCell or cells < 1 then
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "Rechargeable Battery Box (empty)" )
		return true
	end
	local pct = 0
	if type( RfsRecharge ) == "table" and RfsRecharge.boxChargePctFromData then
		pct = RfsRecharge.boxChargePctFromData( pd )
	else
		local full = tonumber( pd.full ) or cellMilli()
		local milli = tonumber( pd.chargeMilli ) or 0
		if full > 0 then
			pct = math.floor( ( milli / full ) * 100 + 0.5 )
		end
	end
	sm.gui.setInteractionText(
		"",
		sm.gui.getKeyBinding( "Use", true ),
		string.format( "Rechargeable Battery Box %d%%", pct )
	)
	return true
end

function RfsRechargeBox.client_canTinker( self, character )
	local pd = self.cl or {}
	local cells = tonumber( pd.cellCount ) or 0
	local key = sm.gui.getKeyBinding( "Tinker", true )
	if not pd.hasCell or cells < 1 then
		sm.gui.setInteractionText( "", key, "Rechargeable Battery Box — empty (0% charge)" )
		return true
	end
	local pct = 0
	if type( RfsRecharge ) == "table" and RfsRecharge.boxChargePctFromData then
		pct = RfsRecharge.boxChargePctFromData( pd )
	else
		pct = math.floor( boxChargeFrac( self ) * 100 + 0.5 )
	end
	sm.gui.setInteractionText( "", key, string.format( "Rechargeable Battery Box — %d%% charge", pct ) )
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

print( "[RFS] RfsRechargeBox loaded (5 slots; inspect per-slot + aggregate side bars)" )
