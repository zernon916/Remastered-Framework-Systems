-- RfsHackPower.lua
-- OWNER: hacked-device battery spend / circuit helpers.
-- FROZEN: work timer. Idle powered = no drain. Work = 1 battery every 40*56 / 40*36 / 40*22
-- ticks (Hack / Control / Infection) while tethered bots are linked OR auto-hijack is converting.
-- Spend is Lua sm.container.spend of exactly 1. Never TryConsumePowerResource / pipeGraph / setActive.
-- Finder: electricity-connected parents/children (battery box → cable → beacon). Not welded/nearby.

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
local UUID_CORE = "c2f158b0-4d7e-4a19-9c6b-8e3a1f50d247"

-- Bit-identical to rush-base RfsHackBeacon TIERS.drainEvery.
RfsHackPower.DRAIN_EVERY = {
	[UUID_HACK] = 40 * 56, -- ~56 s/bat while working (~PlasmaDrill)
	[UUID_CTRL] = 40 * 36, -- ~36 s/bat while working
	[UUID_INFE] = 40 * 22, -- ~22 s/bat while working
	[UUID_CORE] = 40 * 56, -- Station Core visual swap follows Hack Beacon timing
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

	-- Rechargeable Battery Box: stored energy lives in interactable publicData
	-- (chargeMilli) and is not a vanilla battery UUID inside the box slots.
	-- Treat 1 vanilla battery as MILLI_PER_BATTERY milli.
	if type( RfsRecharge ) == "table"
		and type( RfsRecharge.isBoxInteractable ) == "function"
		and RfsRecharge.isBoxInteractable( container ) then
		local pd = nil
		pcall( function()
			pd = container:getPublicData()
		end )
		local milli = tonumber( pd and pd.chargeMilli ) or 0
		if milli < 1 and type( pd and pd.slotMilli ) == "table" then
			-- Fallback for older saves: aggregate slot milli.
			local slots = tonumber( RfsRecharge.BOX_SLOTS ) or 5
			for i = 1, slots do
				milli = milli + ( tonumber( ( pd.slotMilli or {} )[i] ) or 0 )
			end
		end
		local mpb = tonumber( RfsRecharge.MILLI_PER_BATTERY ) or 1000
		if mpb < 1 then
			return 0
		end
		return math.floor( milli / mpb + 0.0001 )
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
	-- Direct containers only. pipeGraph.getMatchingPipedContainers walks the
	-- whole creation and is how TryConsumePowerResource dumps a battery box.
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
	-- rush-base 75abb2f: containers on electricity-connected parents/children.
	-- Player wires Battery container → electricity cable → beacon. No radius search.
	local list, seen, seenIa = {}, {}, {}
	local function consider( ia )
		if not ia or not sm.exists( ia ) then
			return
		end
		local id = tostring( ia )
		if seenIa[id] then
			return
		end
		seenIa[id] = true
		if isElectricityNode( ia ) then
			-- Add rechargeable battery *box interactables* as "power sources".
			-- Their energy is in publicData (chargeMilli), not as vanilla batteries in the box slots.
			pcall( function()
				if type( RfsRecharge ) == "table"
					and type( RfsRecharge.isBoxInteractable ) == "function"
					and RfsRecharge.isBoxInteractable( ia ) then
					addContainer( list, seen, ia )
				end
			end )
			containersFromInteractable( ia, list, seen )
		end
	end
	pcall( function()
		for _, p in ipairs( self.interactable:getParents() or {} ) do
			consider( p )
		end
	end )
	pcall( function()
		for _, p in ipairs( self.interactable:getParents( ELEC ) or {} ) do
			consider( p )
		end
	end )
	pcall( function()
		for _, c in ipairs( self.interactable:getChildren() or {} ) do
			consider( c )
		end
	end )
	pcall( function()
		for _, c in ipairs( self.interactable:getChildren( ELEC ) or {} ) do
			consider( c )
		end
	end )
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
	-- Hard rule: never spend a stack (we spend exactly 1 battery worth per event),
	-- but allow callers to ask for N batteries by repeating N single-battery spends.
	count = tonumber( count ) or 0
	if count <= 0 then
		return true
	end
	local milliPerBattery = tonumber( RfsRecharge and RfsRecharge.MILLI_PER_BATTERY ) or 1000
	if milliPerBattery < 1 then
		milliPerBattery = 1000
	end

	local function spendOne( src )
		-- Rechargeable Battery Box spend: drain chargeMilli by 1 battery worth.
		if type( RfsRecharge ) == "table"
			and type( RfsRecharge.isBoxInteractable ) == "function"
			and RfsRecharge.isBoxInteractable( src )
			and type( RfsRecharge.spendMilliOn ) == "function" then
			local ok, sent = pcall( function()
				return RfsRecharge.spendMilliOn( src, milliPerBattery )
			end )
			return ok and sent and true or false
		end

		-- Vanilla battery container spend.
		if batteryCount( src ) < 1 then
			return false
		end
		local spent = false
		local okTx = pcall( function()
			if sm.container.beginTransaction() then
				local n = sm.container.spend( src, BATTERY_UUID, 1, false )
				if n == 1 and sm.container.endTransaction() then
					spent = true
				else
					sm.container.abortTransaction()
				end
			end
		end )
		if not ( okTx and spent ) then
			local ok, n = pcall( sm.container.spend, src, BATTERY_UUID, 1, true )
			spent = ok and ( n == 1 or n == true ) and true or false
		end
		return spent and true or false
	end

	for _ = 1, count do
		local spent = false
		for _, src in ipairs( containers or {} ) do
			if batteryCount( src ) >= 1 then
				if spendOne( src ) then
					spent = true
					break
				end
			end
		end
		if not spent then
			return false
		end
	end
	return true
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

function RfsHackPower.canSpendOne( self )
	if not RfsHackPower.fuelConsumptionOn() then
		return true
	end
	return RfsHackPower.totalBatteries( RfsHackPower.elecContainers( self ) ) > 0
end

-- force=true: convert/hijack (1 bat per bot). false/nil: work-drain interval only.
-- Always exactly 1 via spendBatteries. Never TryConsumePowerResource.
function RfsHackPower.spendOne( self, force )
	if not RfsHackPower.fuelConsumptionOn() then
		return true
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
	if RfsHackPower.totalBatteries( RfsHackPower.elecContainers( self ) ) > 0 then
		return true
	end
	-- Creative / fuel off: no box required. Do not call CanSpendFromConnectedContainer
	-- (pipe-graph walk; companion of TryConsumePowerResource).
	if not RfsHackPower.fuelConsumptionOn() then
		return true
	end
	return false
end

-- Work drain: tethered bots linked OR auto-hijack converting. Idle = none.
-- Lua 0 is truthy — never let every=0 spend every tick.
function RfsHackPower.tickWorkDrain( self, working )
	self.sv = self.sv or {}
	if not working then
		self.sv.drainAcc = 0
		self.sv.powered = RfsHackPower.isPowered( self )
		return self.sv.powered and true or false
	end
	local uuid = nil
	pcall( function()
		uuid = tostring( self.shape.uuid )
	end )
	local every = RfsHackPower.drainEvery( uuid )
	if type( every ) ~= "number" or every < ( 40 * 22 ) then
		every = 40 * 56
	end
	self.sv.drainAcc = ( self.sv.drainAcc or 0 ) + 1
	if self.sv.drainAcc >= every then
		self.sv.drainAcc = 0
		if not RfsHackPower.spendOne( self, false ) then
			self.sv.powered = false
		else
			self.sv.powered = RfsHackPower.isPowered( self )
		end
	else
		self.sv.powered = RfsHackPower.isPowered( self )
	end
	return self.sv.powered and true or false
end

print( "[RFS] RfsHackPower loaded (0817-i wired; lua spend = 1 bat / 56s work only)" )
