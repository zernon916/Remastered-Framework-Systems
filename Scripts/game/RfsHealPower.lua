-- RfsHealPower.lua
-- OWNER: Chemical Regeneration Station (RfsDeepSleepPod) spend helpers.
-- Replicates Hack spend pattern in a NEW file. Do not edit RfsHackPower / drainEvery.
-- Idle powered = no drain. Heal work = 1 battery (or 1000 milli) every DRAIN_EVERY
-- ticks while they still need HP. 5 batteries / ~10 s => DRAIN_EVERY = 80.
-- Chem: connected Chemical Container (connectionType.chemical), else player inventory.
-- Fill is 10 up front (pod refunds if they leave during fill).
-- Finder: electricity-connected parents/children. Never pipeGraph / TryConsumePowerResource.

RfsHealPower = RfsHealPower or {}

pcall( function()
	dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )
end )
pcall( function()
	dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
end )

local RFS_CG = "$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247"
pcall( function()
	dofile( RFS_CG .. "/Scripts/game/RfsRecharge.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsRecharge.lua" )
end )

local BATTERY_UUID = sm.uuid.new( "910a7f2c-52b0-46eb-8873-ad13255539af" )
if type( ITEMS ) == "table" and ITEMS.obj_consumable_battery then
	BATTERY_UUID = ITEMS.obj_consumable_battery
end
RfsHealPower.BATTERY_UUID = BATTERY_UUID

local CHEM_UUID = sm.uuid.new( "f74c2891-79a9-45e0-982e-4896651c2e25" )
if type( ITEMS ) == "table" and ITEMS.obj_consumable_chemical then
	CHEM_UUID = ITEMS.obj_consumable_chemical
end
RfsHealPower.CHEM_UUID = CHEM_UUID
RfsHealPower.CHEM_STACK = 20
RfsHealPower.FILL_CHEM = 10

local LOGIC = sm.interactable.connectionType.logic
local ELEC = sm.interactable.connectionType.electricity
local CHEM = sm.interactable.connectionType.chemical
RfsHealPower.LOGIC = LOGIC
RfsHealPower.ELEC = ELEC
RfsHealPower.CHEM = CHEM

-- Heal 1→100% ≈ 400 ticks at 0.25 HP/tick. 5 batteries over that = every 80 ticks.
-- 1 cell = 20 batteries; spendOne takes 1000 milli = 1 battery, so 5 spends = 1/4 cell.
-- Do not copy Hack's 40*56 interval here.
RfsHealPower.DRAIN_EVERY = 80

function RfsHealPower.band( a, b )
	if type( bit ) == "table" and type( bit.band ) == "function" then
		return bit.band( a, b )
	end
	return a % ( b * 2 ) >= b and b or 0
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
RfsHealPower.batteryCount = batteryCount

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

function RfsHealPower.elecContainers( self )
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

function RfsHealPower.totalBatteries( containers )
	local n = 0
	for _, c in ipairs( containers or {} ) do
		n = n + batteryCount( c )
	end
	return n
end

function RfsHealPower.spendBatteries( containers, count )
	if tonumber( count ) ~= 1 then
		return false
	end
	for _, container in ipairs( containers or {} ) do
		if batteryCount( container ) >= 1 then
			local spent = false
			local okTx = pcall( function()
				if sm.container.beginTransaction() then
					local n = sm.container.spend( container, BATTERY_UUID, 1, false )
					if n == 1 and sm.container.endTransaction() then
						spent = true
					else
						sm.container.abortTransaction()
					end
				end
			end )
			if not ( okTx and spent ) then
				local ok, n = pcall( sm.container.spend, container, BATTERY_UUID, 1, true )
				spent = ok and ( n == 1 or n == true ) and true or false
			end
			if spent then
				return true
			end
		end
	end
	return false
end

function RfsHealPower.logicAllows( self )
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

function RfsHealPower.fuelConsumptionOn()
	local on = true
	pcall( function()
		on = sm.game.getEnableFuelConsumption()
	end )
	return on
end

local function rechargeMilli( ia )
	if not ia or not sm.exists( ia ) then
		return 0
	end
	local milli = 0
	pcall( function()
		local script = RfsRecharge.scriptFor( ia )
		if script and script.sv then
			milli = tonumber( script.sv.chargeMilli ) or milli
		end
	end )
	pcall( function()
		local pd = ia:getPublicData()
		if type( pd ) == "table" and pd.chargeMilli ~= nil then
			milli = tonumber( pd.chargeMilli ) or milli
		end
	end )
	return milli
end

function RfsHealPower.totalRechargeBatteries( self )
	local n = 0
	if type( RfsRecharge ) ~= "table" or not RfsRecharge.connectedBoxes then
		return 0
	end
	local need = ( type( RfsRecharge.MILLI_PER_BATTERY ) == "number" and RfsRecharge.MILLI_PER_BATTERY ) or 1000
	for _, ia in ipairs( RfsRecharge.connectedBoxes( self ) ) do
		local has = false
		pcall( function()
			has = RfsRecharge.boxHasCell( ia )
		end )
		pcall( function()
			local pd = ia:getPublicData()
			if type( pd ) == "table" and pd.hasCell then
				has = true
			end
		end )
		if has then
			n = n + math.floor( rechargeMilli( ia ) / need )
		end
	end
	return n
end

function RfsHealPower.spendRechargeOne( self )
	if type( RfsRecharge ) ~= "table" or not RfsRecharge.connectedBoxes then
		return false
	end
	local need = ( type( RfsRecharge.MILLI_PER_BATTERY ) == "number" and RfsRecharge.MILLI_PER_BATTERY ) or 1000
	for _, ia in ipairs( RfsRecharge.connectedBoxes( self ) ) do
		local has = false
		pcall( function()
			has = RfsRecharge.boxHasCell( ia )
		end )
		pcall( function()
			local pd = ia:getPublicData()
			if type( pd ) == "table" and pd.hasCell then
				has = true
			end
		end )
		if has and type( RfsRecharge.spendMilliOn ) == "function" and RfsRecharge.spendMilliOn( ia, need ) then
			return true
		end
	end
	return false
end

function RfsHealPower.canSpendOne( self )
	if not RfsHealPower.fuelConsumptionOn() then
		return true
	end
	if RfsHealPower.totalRechargeBatteries( self ) > 0 then
		return true
	end
	if RfsHealPower.isPowered( self ) then
		return true
	end
	return RfsHealPower.totalBatteries( RfsHealPower.elecContainers( self ) ) > 0
end

function RfsHealPower.spendOne( self )
	if not RfsHealPower.fuelConsumptionOn() then
		return true
	end
	if RfsHealPower.spendRechargeOne( self ) then
		return true
	end
	return RfsHealPower.spendBatteries( RfsHealPower.elecContainers( self ), 1 )
end

function RfsHealPower.isPowered( self )
	if not RfsHealPower.logicAllows( self ) then
		return false
	end
	if RfsHealPower.totalRechargeBatteries( self ) > 0 then
		return true
	end
	-- Wired recharge box: honor publicData milli when readable. If this env
	-- cannot see the pool, still allow spendOne to event the box.
	if type( RfsRecharge ) == "table" and RfsRecharge.connectedBoxes then
		for _, ia in ipairs( RfsRecharge.connectedBoxes( self ) ) do
			local has = false
			local sawPd = false
			local pdMilli = 0
			pcall( function()
				has = RfsRecharge.boxHasCell( ia )
			end )
			pcall( function()
				local pd = ia:getPublicData()
				if type( pd ) == "table" then
					if pd.hasCell then
						has = true
					end
					if pd.chargeMilli ~= nil then
						sawPd = true
						pdMilli = tonumber( pd.chargeMilli ) or 0
					end
				end
			end )
			if has then
				if sawPd then
					if pdMilli >= 1000 then
						return true
					end
				elseif rechargeMilli( ia ) >= 1000 then
					return true
				else
					return true
				end
			end
		end
	end
	if RfsHealPower.totalBatteries( RfsHealPower.elecContainers( self ) ) > 0 then
		return true
	end
	if not RfsHealPower.fuelConsumptionOn() then
		return true
	end
	return false
end

function RfsHealPower.playerInventory( player )
	local inv = nil
	pcall( function()
		inv = player:getInventory()
	end )
	return inv
end

local function chemInContainer( container )
	if not container or not sm.exists( container ) then
		return 0
	end
	local ok, qty = pcall( sm.container.totalQuantity, container, CHEM_UUID )
	if ok and type( qty ) == "number" then
		return qty
	end
	return 0
end
RfsHealPower.chemInContainer = chemInContainer

local function isChemicalNode( ia )
	if not ia or not sm.exists( ia ) then
		return false
	end
	local ok, has = pcall( function()
		return ia:hasOutputType( CHEM )
	end )
	return ok and has and true or false
end

function RfsHealPower.chemContainers( self )
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
		if isChemicalNode( ia ) then
			containersFromInteractable( ia, list, seen )
			pcall( function()
				local piped = sm.pipeGraph.getMatchingPipedContainers( ia )
				for _, c in ipairs( piped or {} ) do
					addContainer( list, seen, c )
				end
			end )
		end
	end
	pcall( function()
		for _, p in ipairs( self.interactable:getParents() or {} ) do
			consider( p )
		end
	end )
	pcall( function()
		for _, p in ipairs( self.interactable:getParents( CHEM ) or {} ) do
			consider( p )
		end
	end )
	return list
end

function RfsHealPower.totalConnectedChem( self )
	local n = 0
	for _, c in ipairs( RfsHealPower.chemContainers( self ) ) do
		n = n + chemInContainer( c )
	end
	return n
end

local function spendFromOneContainer( container, count )
	if chemInContainer( container ) < count then
		return false
	end
	local spent = false
	pcall( function()
		if sm.container.beginTransaction() then
			local n = sm.container.spend( container, CHEM_UUID, count, false )
			if n == count and sm.container.endTransaction() then
				spent = true
			else
				sm.container.abortTransaction()
			end
		end
	end )
	if not spent then
		local ok, n = pcall( sm.container.spend, container, CHEM_UUID, count, true )
		spent = ok and ( n == count or n == true ) and true or false
	end
	return spent
end

function RfsHealPower.spendConnectedChem( self, count )
	count = tonumber( count ) or 1
	if count < 1 then
		return false
	end
	if RfsHealPower.totalConnectedChem( self ) < count then
		return false
	end
	local left = count
	for _, container in ipairs( RfsHealPower.chemContainers( self ) ) do
		local have = chemInContainer( container )
		if have > 0 then
			local take = math.min( have, left )
			if spendFromOneContainer( container, take ) then
				left = left - take
				if left <= 0 then
					return true
				end
			end
		end
	end
	return left <= 0
end

function RfsHealPower.refundConnectedChem( self, count )
	count = tonumber( count ) or 1
	if count < 1 then
		return false
	end
	for _, container in ipairs( RfsHealPower.chemContainers( self ) ) do
		local ok = false
		pcall( function()
			ok = sm.container.collect( container, CHEM_UUID, count, true ) and true or false
		end )
		if ok then
			return true
		end
	end
	return false
end

function RfsHealPower.chemCount( player )
	local inv = RfsHealPower.playerInventory( player )
	if not inv or not sm.exists( inv ) then
		return 0
	end
	return chemInContainer( inv )
end

function RfsHealPower.hasChem( player, count, self )
	count = tonumber( count ) or 1
	if self and RfsHealPower.totalConnectedChem( self ) >= count then
		return true
	end
	return RfsHealPower.chemCount( player ) >= count
end

function RfsHealPower.spendChem( player, count, self )
	count = tonumber( count ) or 1
	if count < 1 then
		return false
	end
	if self and RfsHealPower.spendConnectedChem( self, count ) then
		return true, "chem"
	end
	local inv = RfsHealPower.playerInventory( player )
	if not inv or not sm.exists( inv ) then
		return false
	end
	if RfsHealPower.chemCount( player ) < count then
		return false
	end
	if spendFromOneContainer( inv, count ) then
		return true, "inv"
	end
	return false
end

function RfsHealPower.refundChem( player, count, self, src )
	count = tonumber( count ) or 1
	if count < 1 then
		return false
	end
	if src == "chem" and self and RfsHealPower.refundConnectedChem( self, count ) then
		return true
	end
	if not player then
		return false
	end
	local inv = RfsHealPower.playerInventory( player )
	if not inv or not sm.exists( inv ) then
		return false
	end
	local ok = false
	pcall( function()
		ok = sm.container.collect( inv, CHEM_UUID, count, true ) and true or false
	end )
	return ok
end

-- Work drain: actually healing a player. Idle = none.
function RfsHealPower.tickWorkDrain( self, working )
	self.sv = self.sv or {}
	if not working then
		self.sv.drainAcc = 0
		self.sv.powered = RfsHealPower.isPowered( self )
		return self.sv.powered and true or false
	end
	local every = RfsHealPower.DRAIN_EVERY
	if type( every ) ~= "number" or every < 1 then
		every = 80
	end
	self.sv.drainAcc = ( self.sv.drainAcc or 0 ) + 1
	if self.sv.drainAcc >= every then
		self.sv.drainAcc = 0
		if not RfsHealPower.spendOne( self ) then
			self.sv.powered = false
		else
			self.sv.powered = RfsHealPower.isPowered( self )
		end
	else
		self.sv.powered = RfsHealPower.isPowered( self )
	end
	return self.sv.powered and true or false
end

print( "[RFS] RfsHealPower loaded (Chemical Regeneration Station; 5 batt / 10 s heal)" )
