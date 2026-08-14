-- RfsAreaLoader.lua — Area Loader (radio-like).
-- Pins the device's world cell with World:loadCellWithHandle while powered.
-- Cell streaming is all-or-nothing: units/bots in that cell may still exist/run.
-- Do not strip units. Wire a Battery container; optional logic switch.

RfsAreaLoader = class( nil )
RfsAreaLoader.maxParentCount = 2
RfsAreaLoader.maxChildCount = 0
RfsAreaLoader.connectionInput = sm.interactable.connectionType.logic + sm.interactable.connectionType.electricity
RfsAreaLoader.connectionOutput = sm.interactable.connectionType.none
RfsAreaLoader.colorNormal = sm.color.new( 0x3a8fd4ff )
RfsAreaLoader.colorHighlight = sm.color.new( 0x6ec0ffff )
RfsAreaLoader.connectIcon = "electrical"

-- One Scrap Mechanic terrain cell (64 m × 64 m).
RfsAreaLoader.CELL_SIZE = 64
-- Light drain: 1 Battery about every 60 s while pinned (40 ticks/s).
RfsAreaLoader.DRAIN_EVERY = 40 * 60

pcall( function()
	dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsFeatures.lua" )
end )

local BATTERY_UUID = sm.uuid.new( "910a7f2c-52b0-46eb-8873-ad13255539af" )
if type( ITEMS ) == "table" and ITEMS.obj_consumable_battery then
	BATTERY_UUID = ITEMS.obj_consumable_battery
end
local LOGIC = sm.interactable.connectionType.logic
local ELEC = sm.interactable.connectionType.electricity

local function batteryCount( container )
	if not container or not sm.exists( container ) then
		return 0
	end
	local ok, qty = pcall( sm.container.totalQuantity, container, BATTERY_UUID )
	if ok and type( qty ) == "number" then
		return qty
	end
	return 0
end

local function addContainer( list, seen, container )
	if not container or not sm.exists( container ) then
		return
	end
	local id = tostring( container )
	pcall( function()
		id = tostring( container:getId() )
	end )
	if seen[id] then
		return
	end
	seen[id] = true
	list[#list + 1] = container
end

local function containersFromInteractable( ia, list, seen )
	if not ia or not sm.exists( ia ) then
		return
	end
	if type( sm.pipeGraph ) == "table" and type( sm.pipeGraph.getMatchingPipedContainers ) == "function" then
		local okPipe, piped = pcall( sm.pipeGraph.getMatchingPipedContainers, ia )
		if okPipe and type( piped ) == "table" then
			for _, c in ipairs( piped ) do
				addContainer( list, seen, c )
			end
		end
	end
	for _, idx in ipairs( { 0, 1 } ) do
		local ok, c = pcall( function()
			return ia:getContainer( idx )
		end )
		if ok then
			addContainer( list, seen, c )
		end
	end
end

local function isElectricityNode( ia )
	if not ia or not sm.exists( ia ) then
		return false
	end
	local ok, has = pcall( function()
		return ia:hasOutputType( ELEC )
	end )
	if ok and has then
		return true
	end
	local okIn, hasIn = pcall( function()
		return ia:hasInputType( ELEC )
	end )
	return okIn and hasIn and true or false
end

local function elecContainers( self )
	local list, seen = {}, {}
	local nodes = {}
	pcall( function()
		for _, p in ipairs( self.interactable:getParents() or {} ) do
			nodes[#nodes + 1] = p
		end
	end )
	pcall( function()
		for _, c in ipairs( self.interactable:getChildren() or {} ) do
			nodes[#nodes + 1] = c
		end
	end )
	for _, ia in ipairs( nodes ) do
		containersFromInteractable( ia, list, seen )
	end
	return list
end

local function totalBatteries( containers )
	local n = 0
	for _, c in ipairs( containers ) do
		n = n + batteryCount( c )
	end
	return n
end

local function spendOneBattery( containers )
	for _, container in ipairs( containers ) do
		if batteryCount( container ) > 0 then
			local ok = pcall( sm.container.spend, container, BATTERY_UUID, 1, true )
			if ok then
				return true
			end
		end
	end
	return false
end

local function logicAllows( self )
	local parents = {}
	pcall( function()
		parents = self.interactable:getParents( LOGIC ) or {}
	end )
	local switches = 0
	for _, p in ipairs( parents ) do
		if p and sm.exists( p ) then
			local isLogic = false
			pcall( function()
				isLogic = p:hasOutputType( LOGIC ) and not p:hasOutputType( ELEC )
			end )
			if isLogic then
				switches = switches + 1
				local ok, active = pcall( function()
					return p:isActive()
				end )
				if ok and active then
					return true
				end
			end
		end
	end
	return switches == 0
end

local function fuelConsumptionOn()
	local on = true
	pcall( function()
		on = sm.game.getEnableFuelConsumption()
	end )
	return on
end

local function areaLoaderOn()
	if type( RfsFeatures ) == "table" and type( RfsFeatures.areaLoaderEnabled ) == "function" then
		local ok, v = pcall( RfsFeatures.areaLoaderEnabled )
		if ok then
			return v and true or false
		end
	end
	return true
end

local function hasElectricityNeighbor( self )
	local lists = {}
	pcall( function()
		lists[#lists + 1] = self.interactable:getParents() or {}
	end )
	pcall( function()
		lists[#lists + 1] = self.interactable:getChildren() or {}
	end )
	for _, group in ipairs( lists ) do
		for _, ia in ipairs( group ) do
			if isElectricityNode( ia ) then
				return true
			end
		end
	end
	return false
end

local function containerHasAnything( container )
	if not container or not sm.exists( container ) then
		return false
	end
	local okEmpty, empty = pcall( function()
		return container:isEmpty()
	end )
	if okEmpty then
		return not empty
	end
	return batteryCount( container ) > 0
end

local function isPowered( self )
	if not logicAllows( self ) then
		return false
	end
	local containers = elecContainers( self )
	if totalBatteries( containers ) > 0 then
		return true
	end
	for _, c in ipairs( containers ) do
		if containerHasAnything( c ) then
			return true
		end
	end
	if hasElectricityNeighbor( self ) then
		if #containers == 0 or not fuelConsumptionOn() then
			return true
		end
	end
	return false
end

local function cellCoords( self )
	local pos = self.shape.worldPosition
	local size = RfsAreaLoader.CELL_SIZE
	return math.floor( pos.x / size ), math.floor( pos.y / size )
end

local function releasePin( self )
	local handle = self.sv and self.sv.loadHandle
	if handle then
		pcall( function()
			handle:release()
		end )
	end
	if self.sv then
		self.sv.loadHandle = nil
		self.sv.pinned = false
	end
end

local function acquirePin( self )
	if not self.shape or not sm.exists( self.shape ) then
		return false
	end
	local world = nil
	pcall( function()
		world = self.shape:getWorld()
	end )
	if not world or not sm.exists( world ) then
		return false
	end
	if type( world.loadCellWithHandle ) ~= "function" then
		return false
	end
	local x, y = cellCoords( self )
	local ok, handle = pcall( function()
		return world:loadCellWithHandle( x, y, nil )
	end )
	if not ok or handle == nil then
		return false
	end
	self.sv.loadHandle = handle
	self.sv.pinned = true
	self.sv.cellX = x
	self.sv.cellY = y
	return true
end

local function publish( self )
	local disabled = not areaLoaderOn()
	local data = {
		powered = ( not disabled ) and self.sv.powered and true or false,
		pinned = ( not disabled ) and self.sv.pinned and true or false,
		disabled = disabled,
		batteries = self.sv.batteries or 0,
		cellX = self.sv.cellX,
		cellY = self.sv.cellY,
	}
	pcall( function()
		self.network:setClientData( data )
	end )
	pcall( function()
		self.interactable:setPublicData( data )
	end )
	pcall( function()
		self.interactable:setActive( ( not disabled ) and self.sv.powered and self.sv.pinned and true or false )
	end )
	pcall( function()
		self.interactable:setPoseWeight( 0, ( not disabled ) and self.sv.powered and self.sv.pinned and 1 or 0 )
	end )
end

local function syncPowerAndPin( self )
	local containers = elecContainers( self )
	self.sv.batteries = totalBatteries( containers )

	-- Host disabled: never pin cells / never drain for loading.
	if not areaLoaderOn() then
		self.sv.powered = false
		releasePin( self )
		return
	end

	self.sv.powered = isPowered( self )

	if self.sv.powered then
		if not self.sv.loadHandle then
			acquirePin( self )
		end
	else
		releasePin( self )
	end
end

function RfsAreaLoader.server_onCreate( self )
	self.sv = {
		powered = false,
		pinned = false,
		loadHandle = nil,
		drainAcc = 0,
		batteries = 0,
		cellX = nil,
		cellY = nil,
	}
	syncPowerAndPin( self )
	publish( self )
end

function RfsAreaLoader.server_onDestroy( self )
	releasePin( self )
end

function RfsAreaLoader.server_onFixedUpdate( self )
	if not self.sv then
		return
	end

	local wasPowered = self.sv.powered and true or false
	local wasPinned = self.sv.pinned and true or false
	syncPowerAndPin( self )

	if self.sv.powered and self.sv.pinned and fuelConsumptionOn() then
		self.sv.drainAcc = ( self.sv.drainAcc or 0 ) + 1
		if self.sv.drainAcc >= RfsAreaLoader.DRAIN_EVERY then
			self.sv.drainAcc = 0
			local containers = elecContainers( self )
			if totalBatteries( containers ) > 0 then
				spendOneBattery( containers )
			end
			syncPowerAndPin( self )
		end
	else
		self.sv.drainAcc = 0
	end

	if self.sv.powered ~= wasPowered or self.sv.pinned ~= wasPinned or ( sm.game.getCurrentTick() % 20 ) == 0 then
		publish( self )
	end
end

function RfsAreaLoader.client_onCreate( self )
	self.cl = { powered = false, pinned = false, batteries = 0 }
end

function RfsAreaLoader.client_onClientDataUpdate( self, data )
	if type( data ) ~= "table" then
		return
	end
	self.cl.powered = data.powered and true or false
	self.cl.pinned = data.pinned and true or false
	self.cl.disabled = data.disabled and true or false
	self.cl.batteries = data.batteries or 0
	self.cl.cellX = data.cellX
	self.cl.cellY = data.cellY
	pcall( function()
		self.interactable:setPoseWeight( 0, ( self.cl.powered and self.cl.pinned ) and 1 or 0 )
	end )
end

function RfsAreaLoader.client_canInteract( self )
	local pd = self.cl or {}
	if pd.disabled then
		sm.gui.setInteractionText( "", "", "Disabled by host" )
		return true
	end
	if pd.powered and pd.pinned then
		sm.gui.setInteractionText(
			"",
			"",
			"Streaming this cell (64 m). Units may still exist.  " .. tostring( pd.batteries or 0 ) .. " Battery"
		)
	elseif pd.powered then
		sm.gui.setInteractionText( "", "", "Powered — waiting for cell pin…" )
	else
		sm.gui.setInteractionText( "", "", "Connect FROM Battery container TO this (optional switch)" )
	end
	return true
end
