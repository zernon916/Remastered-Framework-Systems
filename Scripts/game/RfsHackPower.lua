-- RfsHackPower.lua
-- OWNER: hacked-device battery spend / circuit helpers.
-- FROZEN: battery spend. Do not change rates/idle rules unless the user explicitly asks.
-- Idle powered = no drain. Work = 1 battery every 40*56 / 40*36 / 40*22 ticks
-- (Hack / Control / Infection) while tethered bots are linked OR auto-hijack is converting.

RfsHackPower = RfsHackPower or {}
rfsHackPower = RfsHackPower

pcall( function()
	dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )
end )
pcall( function()
	dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
end )

local BATTERY_UUID = sm.uuid.new( "910a7f2c-52b0-46eb-8873-ad13255539af" )
if type( ITEMS ) == "table" and ITEMS.obj_consumable_battery then
	BATTERY_UUID = ITEMS.obj_consumable_battery
end
RfsHackPower.BATTERY_UUID = BATTERY_UUID

local LOGIC = sm.interactable.connectionType.logic
local ELEC = sm.interactable.connectionType.electricity
RfsHackPower.LOGIC = LOGIC
RfsHackPower.ELEC = ELEC

local UUID_HACK = "b4e8c1a0-7d2f-4a91-9c3e-29f1a8d6b5e7"
local UUID_CTRL = "c5f9d2b1-8e30-4ba2-ad4f-30a2b9e7c6f8"
local UUID_INFE = "d6a0e3c2-9f41-4cb3-be50-41b3c0f8d709"

-- Bit-identical to rush-base RfsHackBeacon TIERS.drainEvery.
RfsHackPower.DRAIN_EVERY = {
	[UUID_HACK] = 40 * 56, -- ~56 s/bat while working (~PlasmaDrill)
	[UUID_CTRL] = 40 * 36, -- ~36 s/bat while working
	[UUID_INFE] = 40 * 22, -- ~22 s/bat while working
}

function RfsHackPower.band( a, b )
	if type( bit ) == "table" and type( bit.band ) == "function" then
		return bit.band( a, b )
	end
	return a % ( b * 2 ) >= b and b or 0
end

function RfsHackPower.drainEvery( uuid )
	return RfsHackPower.DRAIN_EVERY[tostring( uuid or "" )] or ( 40 * 56 )
end

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
RfsHackPower.batteryCount = batteryCount

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
	local okShape, shape = pcall( function()
		return ia.shape or ia:getShape()
	end )
	if okShape and shape and sm.exists( shape ) then
		local ok2, c2 = pcall( function()
			return shape.interactable:getContainer( 0 )
		end )
		if ok2 then
			addContainer( list, seen, c2 )
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

function RfsHackPower.elecContainers( self )
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

function RfsHackPower.totalBatteries( containers )
	local n = 0
	for _, c in ipairs( containers or {} ) do
		n = n + batteryCount( c )
	end
	return n
end

function RfsHackPower.spendBatteries( containers, count )
	local left = count
	for _, container in ipairs( containers or {} ) do
		if left <= 0 then
			break
		end
		local have = batteryCount( container )
		local take = math.min( have, left )
		if take > 0 then
			local spent = false
			local okTx = pcall( function()
				if sm.container.beginTransaction() then
					local n = sm.container.spend( container, BATTERY_UUID, take, false )
					if n == take and sm.container.endTransaction() then
						spent = true
					else
						sm.container.abortTransaction()
					end
				end
			end )
			if not ( okTx and spent ) then
				local ok = pcall( sm.container.spend, container, BATTERY_UUID, take, true )
				spent = ok and true or false
			end
			if spent then
				left = left - take
			end
		end
	end
	return left == 0
end

function RfsHackPower.logicAllows( self )
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

function RfsHackPower.fuelConsumptionOn()
	local on = true
	pcall( function()
		on = sm.game.getEnableFuelConsumption()
	end )
	return on
end

function RfsHackPower.spendOne( self )
	if not RfsHackPower.fuelConsumptionOn() then
		return true
	end
	if type( TryConsumePowerResource ) == "function" then
		local ok, result = pcall( TryConsumePowerResource, self.interactable, BATTERY_UUID, ELEC, 1 )
		if ok and ( result == 2 or result == true or ( type( PowerConsumeType ) == "table" and result == PowerConsumeType.resource ) ) then
			return true
		end
	end
	return RfsHackPower.spendBatteries( RfsHackPower.elecContainers( self ), 1 )
end

function RfsHackPower.hasElectricityNeighbor( self )
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

function RfsHackPower.isPowered( self )
	if not RfsHackPower.logicAllows( self ) then
		return false
	end
	if not RfsHackPower.fuelConsumptionOn() then
		return RfsHackPower.hasElectricityNeighbor( self )
			or RfsHackPower.totalBatteries( RfsHackPower.elecContainers( self ) ) > 0
	end
	local containers = RfsHackPower.elecContainers( self )
	if RfsHackPower.totalBatteries( containers ) > 0 then
		return true
	end
	if type( CanSpendFromConnectedContainer ) == "function" then
		local parents = {}
		pcall( function()
			parents = self.interactable:getParents() or {}
		end )
		for _, p in ipairs( parents ) do
			local ok, can = pcall( CanSpendFromConnectedContainer, p, BATTERY_UUID, 1 )
			if ok and can then
				return true
			end
		end
	end
	return false
end

-- Work drain: tethered bots linked OR auto-hijack converting. Idle = none.
function RfsHackPower.tickWorkDrain( self, working )
	self.sv = self.sv or {}
	if not working then
		self.sv.drainAcc = 0
		return self.sv.powered and true or false
	end
	local uuid = nil
	pcall( function()
		uuid = tostring( self.shape.uuid )
	end )
	local every = RfsHackPower.drainEvery( uuid )
	self.sv.drainAcc = ( self.sv.drainAcc or 0 ) + 1
	if self.sv.drainAcc >= ( every or 1200 ) then
		self.sv.drainAcc = 0
		if not RfsHackPower.spendOne( self ) then
			self.sv.powered = false
		else
			self.sv.powered = RfsHackPower.isPowered( self )
		end
	end
	return self.sv.powered and true or false
end

print( "[RFS] RfsHackPower loaded (frozen battery spend)" )
