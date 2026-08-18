-- RfsRecharge.lua
-- VOLATILE: rechargeable battery item/box + solar charge curve.
-- One rechargeable item = 20 vanilla batteries of energy (FULL_MILLI = 20 * 1000).
-- Empty uuid = 0 charge; Full uuid = FULL_MILLI. Box: 5 slots, stackSize 1.
-- Charge lives per inserted cell (empty slots stay empty). Solar fills 1 cell / day at 100%.
-- Does not touch RfsHackPower / Hack beacon spend.

RfsRecharge = RfsRecharge or {}

pcall( function()
	dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
end )
pcall( function()
	dofile( "$GAME_DATA/Scripts/game/managers/WeatherManager.lua" )
end )

RfsRecharge.ITEM_UUID = "8b513e7d-a4f6-4039-bc82-e3f70a4b6d9e"
-- Full cell is a second shape so /unlimited can spawn Empty vs Full. Same mesh.
RfsRecharge.ITEM_FULL_UUID = "a0d8469f-c618-425b-de14-06203d7e90c1"
RfsRecharge.BOX_UUID = "9c624f8e-b507-414a-cd93-f4081b5c7eaf"
RfsRecharge.SOLAR_UUID = "7a402d6c-93e5-4f28-ab71-d2e6f9a3b5c8"
RfsRecharge.DEEPSLEEP_UUID = "6f391c5b-82d4-4e17-9a60-c1d5e8f2a4b7"

RfsRecharge.BATTERIES_PER_CELL = 20
RfsRecharge.MILLI_PER_BATTERY = 1000
RfsRecharge.FULL_MILLI = RfsRecharge.BATTERIES_PER_CELL * RfsRecharge.MILLI_PER_BATTERY
RfsRecharge.BOX_SLOTS = 5
RfsRecharge.BOX_STACK = 1

local TICKS_PER_DAY = 1440 * 40
pcall( function()
	if type( DAYCYCLE_TIME_TICKS ) == "number" and DAYCYCLE_TIME_TICKS > 0 then
		TICKS_PER_DAY = DAYCYCLE_TIME_TICKS
	end
end )
RfsRecharge.TICKS_PER_DAY = TICKS_PER_DAY

local DAWN = 0.21
local NIGHT = 0.875
pcall( function()
	if type( DAYCYCLE_DAWN ) == "number" then
		DAWN = DAYCYCLE_DAWN
	end
	if type( DAYCYCLE_NIGHT ) == "number" then
		NIGHT = DAYCYCLE_NIGHT
	end
end )

local ELEC = sm.interactable.connectionType.electricity
RfsRecharge.ELEC = ELEC

local weatherCfg = nil
local function weatherConditions()
	if weatherCfg then
		return weatherCfg
	end
	local ok, cfg = pcall( sm.json.open, "$GAME_DATA/Weather/main.weather" )
	if ok and type( cfg ) == "table" and type( cfg.conditions ) == "table" then
		weatherCfg = cfg.conditions
	else
		weatherCfg = {}
	end
	return weatherCfg
end

function RfsRecharge.itemUuid()
	return sm.uuid.new( RfsRecharge.ITEM_UUID )
end

function RfsRecharge.itemFullUuid()
	return sm.uuid.new( RfsRecharge.ITEM_FULL_UUID )
end

function RfsRecharge.cellFilterUuids()
	return { RfsRecharge.itemUuid(), RfsRecharge.itemFullUuid() }
end

function RfsRecharge.isCellId( id )
	id = RfsRecharge.uuidStr( id )
	return id == RfsRecharge.ITEM_UUID or id == RfsRecharge.ITEM_FULL_UUID
end

function RfsRecharge.isFullCellId( id )
	return RfsRecharge.uuidStr( id ) == RfsRecharge.ITEM_FULL_UUID
end

function RfsRecharge.sunUp()
	local tod = 0.5
	pcall( function()
		tod = sm.game.getTimeOfDay() or 0.5
	end )
	return tod >= DAWN and tod < NIGHT, tod
end

function RfsRecharge.isRaining()
	local raining = false
	pcall( function()
		if type( WeatherManager ) == "table" and WeatherManager.Sv_IsRaining then
			raining = WeatherManager.Sv_IsRaining() and true or false
		end
	end )
	return raining
end

function RfsRecharge.cloudCoverage()
	local name = nil
	pcall( function()
		if W_weatherManagerServer and W_weatherManagerServer.sv then
			name = W_weatherManagerServer.sv.currentConditionName
		end
	end )
	if type( name ) ~= "string" then
		return 0, "Clear"
	end
	local cond = weatherConditions()[name]
	local cov = 0
	if type( cond ) == "table" then
		cov = tonumber( cond.cloudCoverage ) or 0
	end
	return cov, name
end

-- 100% sun+clear, 50% sun+cloudy, 25% night, 5% rain+night.
function RfsRecharge.chargeRate()
	local sun, _tod = RfsRecharge.sunUp()
	local raining = RfsRecharge.isRaining()
	if raining and not sun then
		return 0.05, "rain+night"
	end
	if not sun then
		return 0.25, "night"
	end
	local cov, name = RfsRecharge.cloudCoverage()
	local cloudy = ( cov >= 0.25 ) or raining or ( type( name ) == "string" and string.find( string.lower( name ), "cloud", 1, true ) ~= nil and name ~= "Clear" )
	-- Clouds01 is light haze (0.19) — treat as clear. Bigclouds / Rain = cloudy.
	if name == "Clouds01" and not raining then
		cloudy = false
	end
	if cloudy then
		return 0.50, "sun+cloudy"
	end
	return 1.00, "sun+clear"
end

function RfsRecharge.milliPerTick( rate )
	rate = tonumber( rate ) or 1
	return ( RfsRecharge.FULL_MILLI / RfsRecharge.TICKS_PER_DAY ) * rate
end

local function containerHasItem( container, uuid )
	if not container or not sm.exists( container ) then
		return false
	end
	local ok, qty = pcall( sm.container.totalQuantity, container, uuid )
	return ok and type( qty ) == "number" and qty >= 1
end

local function containerCellCount( container )
	if not container or not sm.exists( container ) then
		return 0
	end
	local n = 0
	for _, uuid in ipairs( RfsRecharge.cellFilterUuids() ) do
		local okq, qty = pcall( sm.container.totalQuantity, container, uuid )
		if okq and type( qty ) == "number" then
			n = n + qty
		end
	end
	return n
end

function RfsRecharge.boxCellCount( ia )
	if not ia or not sm.exists( ia ) then
		return 0
	end
	local n = 0
	for _, idx in ipairs( { 0, 1 } ) do
		local ok, c = pcall( function()
			return ia:getContainer( idx )
		end )
		if ok and c and sm.exists( c ) then
			n = n + containerCellCount( c )
		end
	end
	local slots = RfsRecharge.BOX_SLOTS or 5
	if n > slots then
		n = slots
	end
	if n < 0 then
		n = 0
	end
	return n
end

function RfsRecharge.boxHasCell( ia )
	if not ia or not sm.exists( ia ) then
		return false
	end
	for _, idx in ipairs( { 0, 1 } ) do
		local ok, c = pcall( function()
			return ia:getContainer( idx )
		end )
		if ok and c then
			for _, uuid in ipairs( RfsRecharge.cellFilterUuids() ) do
				if containerHasItem( c, uuid ) then
					return true, c
				end
			end
		end
	end
	return false, nil
end

function RfsRecharge.uuidStr( u )
	local s = string.lower( tostring( u or "" ) )
	local m = string.match( s, "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x" )
	return m or s
end

function RfsRecharge.isBoxInteractable( ia )
	if not ia or not sm.exists( ia ) then
		return false
	end
	local id = nil
	pcall( function()
		local shape = ia.shape or ia:getShape()
		if shape and sm.exists( shape ) then
			id = RfsRecharge.uuidStr( shape.uuid )
		end
	end )
	if id == RfsRecharge.BOX_UUID then
		return true
	end
	local pd = nil
	pcall( function()
		pd = ia:getPublicData()
	end )
	if type( pd ) == "table" and ( pd.chargeMilli ~= nil or pd.hasCell ) then
		return true
	end
	return false
end

RfsRecharge.boxScripts = RfsRecharge.boxScripts or {}
_G.g_rfsRechargeBoxScripts = _G.g_rfsRechargeBoxScripts or RfsRecharge.boxScripts

function RfsRecharge.scriptFor( ia )
	if not ia or not sm.exists( ia ) then
		return nil
	end
	local key = nil
	pcall( function()
		local shape = ia.shape or ia:getShape()
		if shape then
			key = tostring( shape.id )
		end
	end )
	if not key then
		return nil
	end
	local script = RfsRecharge.boxScripts[key]
	if script and script.sv then
		return script
	end
	local g = _G.g_rfsRechargeBoxScripts
	if type( g ) == "table" then
		script = g[key]
		if script and script.sv then
			return script
		end
	end
	return nil
end

function RfsRecharge.spendMilliOn( ia, milli )
	milli = tonumber( milli ) or 0
	if milli <= 0 then
		return false
	end
	local script = RfsRecharge.scriptFor( ia )
	if script and type( script.sv_spendMilli ) == "function" then
		local ok, r = pcall( function()
			return script:sv_spendMilli( milli )
		end )
		if ok and r then
			return true
		end
	end
	local sawPd = false
	local pdMilli = 0
	pcall( function()
		local pd = ia:getPublicData()
		if type( pd ) == "table" and pd.chargeMilli ~= nil then
			sawPd = true
			pdMilli = tonumber( pd.chargeMilli ) or 0
		end
	end )
	-- Only refuse when this env can actually read the box pool. Missing
	-- publicData used to skip the spend event and leave Deep Sleep unpowered.
	if sawPd and pdMilli < milli then
		return false
	end
	local sent = false
	pcall( function()
		sm.event.sendToInteractable( ia, "sv_e_rfsSpendMilli", { milli = milli } )
		sent = true
	end )
	return sent
end

function RfsRecharge.addMilliOn( ia, milli )
	milli = tonumber( milli ) or 0
	if milli <= 0 then
		return 0
	end
	local script = RfsRecharge.scriptFor( ia )
	if script and type( script.sv_addMilli ) == "function" then
		local ok, r = pcall( function()
			return script:sv_addMilli( milli )
		end )
		if ok then
			return r
		end
	end
	pcall( function()
		sm.event.sendToInteractable( ia, "sv_e_rfsAddMilli", { milli = milli } )
	end )
	return 0
end

function RfsRecharge.connectedBoxes( self )
	local list, seenBox, seenIa = {}, {}, {}
	local start = self and self.interactable
	if not start or not sm.exists( start ) then
		return list
	end
	local queue = { start }
	local hops = 0
	while #queue > 0 and hops < 48 do
		local ia = table.remove( queue, 1 )
		if ia and sm.exists( ia ) then
			local key = tostring( ia )
			if not seenIa[key] then
				seenIa[key] = true
				hops = hops + 1
				if ia ~= start and RfsRecharge.isBoxInteractable( ia ) then
					if not seenBox[key] then
						seenBox[key] = true
						list[#list + 1] = ia
					end
				end
				local function enqueue( neighbors )
					for _, other in ipairs( neighbors or {} ) do
						if other and sm.exists( other ) and not seenIa[tostring( other )] then
							queue[#queue + 1] = other
						end
					end
				end
				pcall( function()
					enqueue( ia:getParents( ELEC ) )
				end )
				pcall( function()
					enqueue( ia:getChildren( ELEC ) )
				end )
				pcall( function()
					enqueue( ia:getParents() )
				end )
				pcall( function()
					enqueue( ia:getChildren() )
				end )
			end
		end
	end
	return list
end

function RfsRecharge.chargePips( frac )
	frac = tonumber( frac ) or 0
	if frac < 0 then
		frac = 0
	end
	if frac > 1 then
		frac = 1
	end
	local filled = math.floor( frac * 10 + 0.0001 )
	if frac > 0 and filled < 1 then
		filled = 0
	end
	if frac >= 1 then
		filled = 10
	end
	return filled, math.floor( frac * 100 + 0.5 )
end

function RfsRecharge.applyChargePips( gui, prefix, frac )
	if not gui then
		return 0
	end
	local filled, pct = RfsRecharge.chargePips( frac )
	prefix = tostring( prefix or "ChargePip" )
	for i = 0, 9 do
		pcall( function()
			gui:setVisible( prefix .. tostring( i ), i < filled )
		end )
	end
	return pct
end

function RfsRecharge.heldChargeFrac()
	local item = nil
	pcall( function()
		item = sm.localPlayer.getActiveItem()
	end )
	local id = RfsRecharge.uuidStr( item )
	if id == RfsRecharge.ITEM_FULL_UUID then
		return 1
	end
	if id == RfsRecharge.ITEM_UUID then
		return 0
	end
	return nil
end

print( "[RFS] RfsRecharge loaded (20-bat cell; empty/full; 1 day @ 100%)" )
