-- RfsChemStation.lua
-- FROZEN: Chemical Regeneration Station — consolidated owner module.
-- Power/spend, enter/exit/heal orchestration, container discovery, exit safety.
-- Do not edit for hack/beacon/orders/range work. Bump RFS_PACK_STAMP if shipped.
--
-- VOLATILE section at file bottom: solo night skip (RfsDeepSleepTime compat).

RfsChemStation = RfsChemStation or {}

local RFS_CG = "$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247"
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

pcall( function()
	dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )
end )
pcall( function()
	dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
end )
rfsDofile( "Scripts/game/RfsRecharge.lua" )

-- =============================================================================
-- FROZEN: Power / chem spend (formerly RfsHealPower.lua)
-- =============================================================================

local Power = {}

-- Avoid double-loading two potentially-stale copies of RfsRecharge.
-- (Workshop/Roaming copy vs $CONTENT_DATA). The last one loaded would win
-- and could desync uuid filters + recharge-box publicData fields.

local BATTERY_UUID = sm.uuid.new( "910a7f2c-52b0-46eb-8873-ad13255539af" )
if type( ITEMS ) == "table" and ITEMS.obj_consumable_battery then
	BATTERY_UUID = ITEMS.obj_consumable_battery
end
Power.BATTERY_UUID = BATTERY_UUID

local CHEM_UUID = sm.uuid.new( "f74c2891-79a9-45e0-982e-4896651c2e25" )
if type( ITEMS ) == "table" and ITEMS.obj_consumable_chemical then
	CHEM_UUID = ITEMS.obj_consumable_chemical
end
Power.CHEM_UUID = CHEM_UUID
Power.CHEM_STACK = 20
Power.FILL_CHEM = 10

local LOGIC = sm.interactable.connectionType.logic
local ELEC = sm.interactable.connectionType.electricity
local CHEM = sm.interactable.connectionType.chemical
Power.LOGIC = LOGIC
Power.ELEC = ELEC
Power.CHEM = CHEM

-- Heal 1→100% ≈ 400 ticks at 0.25 HP/tick. 5 batteries over that = every 80 ticks.
-- 1 cell = 20 batteries; spendOne takes 1000 milli = 1 battery, so 5 spends = 1/4 cell.
-- Do not copy Hack's 40*56 interval here.
Power.DRAIN_EVERY = 80

function Power.band( a, b )
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
Power.batteryCount = batteryCount

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
	-- Some interactables (notably vanilla battery banks and chemical tanks
	-- behind certain connection wrappers) keep their real container on the
	-- shape's interactable rather than on the wrapper interactable itself.
	-- Replicate HackPower's fallback.
	local okShape, shape = pcall( function()
		return ia.shape or ia:getShape()
	end )
	if okShape and shape and sm.exists( shape ) then
		for _, idx in ipairs( { 0, 1 } ) do
			local ok2, c2 = pcall( function()
				return shape.interactable:getContainer( idx )
			end )
			if ok2 then
				addContainer( list, seen, c2 )
			end
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

function Power.elecContainers( self )
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

function Power.totalBatteries( containers )
	local n = 0
	for _, c in ipairs( containers or {} ) do
		n = n + batteryCount( c )
	end
	return n
end

function Power.spendBatteries( containers, count )
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

function Power.logicAllows( self )
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

function Power.fuelConsumptionOn()
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

function Power.totalRechargeBatteries( self )
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

function Power.spendRechargeOne( self )
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

function Power.canSpendOne( self )
	if not Power.fuelConsumptionOn() then
		return true
	end
	if Power.totalRechargeBatteries( self ) > 0 then
		return true
	end
	if Power.isPowered( self ) then
		return true
	end
	return Power.totalBatteries( Power.elecContainers( self ) ) > 0
end

function Power.spendOne( self )
	if not Power.fuelConsumptionOn() then
		return true
	end
	if Power.spendRechargeOne( self ) then
		return true
	end
	return Power.spendBatteries( Power.elecContainers( self ), 1 )
end

function Power.isPowered( self )
	if not Power.logicAllows( self ) then
		return false
	end
	if Power.totalRechargeBatteries( self ) > 0 then
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
	if Power.totalBatteries( Power.elecContainers( self ) ) > 0 then
		return true
	end
	if not Power.fuelConsumptionOn() then
		return true
	end
	return false
end

function Power.playerInventory( player )
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
Power.chemInContainer = chemInContainer

local function isChemicalNode( ia )
	if not ia or not sm.exists( ia ) then
		return false
	end
	local okOut, hasOut = pcall( function()
		return ia:hasOutputType( CHEM )
	end )
	if okOut and hasOut then
		return true
	end
	local okIn, hasIn = pcall( function()
		return ia:hasInputType( CHEM )
	end )
	return okIn and hasIn and true or false
end

local function gatherConnectedInteractables( self )
	local list, seen = {}, {}
	local function addIa( ia )
		if not ia or not sm.exists( ia ) then
			return
		end
		local id = tostring( ia )
		pcall( function()
			id = tostring( ia:getId() )
		end )
		if seen[id] then
			return
		end
		seen[id] = true
		list[#list + 1] = ia
	end
	addIa( self and self.interactable or nil )
	pcall( function()
		for _, ia in ipairs( self.interactable:getParents() or {} ) do
			addIa( ia )
		end
	end )
	pcall( function()
		for _, ia in ipairs( self.interactable:getChildren() or {} ) do
			addIa( ia )
		end
	end )
	pcall( function()
		for _, ia in ipairs( self.interactable:getParents( CHEM ) or {} ) do
			addIa( ia )
		end
	end )
	pcall( function()
		for _, ia in ipairs( self.interactable:getChildren( CHEM ) or {} ) do
			addIa( ia )
		end
	end )
	return list
end

function Power.chemContainers( self )
	local list, seen = {}, {}
	for _, ia in ipairs( gatherConnectedInteractables( self ) ) do
		-- Deterministic source discovery:
		-- probe every connected interactable directly (typed wrappers may hide CHEM IO)
		-- then include any matching piped containers from that interactable.
		containersFromInteractable( ia, list, seen )
		pcall( function()
			local piped = sm.pipeGraph.getMatchingPipedContainers( ia )
			for _, c in ipairs( piped or {} ) do
				addContainer( list, seen, c )
			end
		end )
	end
	-- Keep a typed CHEM pass as additive-only guard for cases where this engine build
	-- reports CHEM containers only through type-gated parent/child wrappers.
	for _, ia in ipairs( gatherConnectedInteractables( self ) ) do
		if isChemicalNode( ia ) then
			pcall( function()
				local piped = sm.pipeGraph.getMatchingPipedContainers( ia )
				for _, c in ipairs( piped or {} ) do
					addContainer( list, seen, c )
				end
			end )
		end
	end
	if #list == 0 then
		-- Suppressed log to avoid per-tick spam when discovery truly fails.
		local key = tostring( self and self.interactable or "nil" )
		_G.g_rfsChemContainerLogOnce = _G.g_rfsChemContainerLogOnce or {}
		if not _G.g_rfsChemContainerLogOnce[key] then
			_G.g_rfsChemContainerLogOnce[key] = true
			print( "[RFS] chemContainers still empty (tank/container discovery failed)" )
		end
	end
	return list
end

function Power.totalConnectedChem( self )
	local n = 0
	for _, c in ipairs( Power.chemContainers( self ) ) do
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

function Power.spendConnectedChem( self, count )
	count = tonumber( count ) or 1
	if count < 1 then
		return false
	end
	if Power.totalConnectedChem( self ) < count then
		return false
	end
	local left = count
	for _, container in ipairs( Power.chemContainers( self ) ) do
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

function Power.refundConnectedChem( self, count )
	count = tonumber( count ) or 1
	if count < 1 then
		return false
	end
	for _, container in ipairs( Power.chemContainers( self ) ) do
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

function Power.chemCount( player )
	local inv = Power.playerInventory( player )
	if not inv or not sm.exists( inv ) then
		return 0
	end
	return chemInContainer( inv )
end

function Power.hasChem( player, count, self )
	count = tonumber( count ) or 1
	if self and Power.totalConnectedChem( self ) >= count then
		return true
	end
	return Power.chemCount( player ) >= count
end

function Power.spendChem( player, count, self )
	count = tonumber( count ) or 1
	if count < 1 then
		return false
	end
	if self and Power.spendConnectedChem( self, count ) then
		local key = tostring( self.interactable or "nil" ) .. "|pod"
		_G.g_rfsChemSpendLog = _G.g_rfsChemSpendLog or {}
		local now = 0
		pcall( function()
			now = tonumber( sm.game.getCurrentTick() ) or 0
		end )
		local prev = _G.g_rfsChemSpendLog[key] or -999999
		if ( now - prev ) >= 120 then
			_G.g_rfsChemSpendLog[key] = now
			print( "[RFS] chemSpend src=pod amount=" .. tostring( count ) )
		end
		return true, "pod"
	end
	local inv = Power.playerInventory( player )
	if not inv or not sm.exists( inv ) then
		return false
	end
	if Power.chemCount( player ) < count then
		return false
	end
	if spendFromOneContainer( inv, count ) then
		local pkey = "player"
		pcall( function()
			pkey = tostring( player.id or player:getId() )
		end )
		local key = pkey .. "|player"
		_G.g_rfsChemSpendLog = _G.g_rfsChemSpendLog or {}
		local now = 0
		pcall( function()
			now = tonumber( sm.game.getCurrentTick() ) or 0
		end )
		local prev = _G.g_rfsChemSpendLog[key] or -999999
		if ( now - prev ) >= 120 then
			_G.g_rfsChemSpendLog[key] = now
			print( "[RFS] chemSpend src=player amount=" .. tostring( count ) )
		end
		return true, "player"
	end
	return false
end

function Power.refundChem( player, count, self, src )
	count = tonumber( count ) or 1
	if count < 1 then
		return false
	end
	if src == "pod" and self and Power.refundConnectedChem( self, count ) then
		return true
	end
	if not player then
		return false
	end
	local inv = Power.playerInventory( player )
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
function Power.tickWorkDrain( self, working )
	self.sv = self.sv or {}
	if not working then
		self.sv.drainAcc = 0
		self.sv.powered = Power.isPowered( self )
		return self.sv.powered and true or false
	end
	local every = Power.DRAIN_EVERY
	if type( every ) ~= "number" or every < 1 then
		every = 80
	end
	self.sv.drainAcc = ( self.sv.drainAcc or 0 ) + 1
	if self.sv.drainAcc >= every then
		self.sv.drainAcc = 0
		if not Power.spendOne( self ) then
			self.sv.powered = false
		else
			self.sv.powered = Power.isPowered( self )
		end
	else
		self.sv.powered = Power.isPowered( self )
	end
	return self.sv.powered and true or false
end



-- =============================================================================
-- FROZEN: Pod orchestration (formerly RfsDeepSleepPod.lua business logic)
-- =============================================================================

local BOX_Y_BLOCKS = 17
local BLOCK_M = 0.25
local STAND_Y_M = 0.0 -- shapeset seat Hips offset (tube center; was -1.225 root_jnt floor snap)
local EXIT_FORWARD = 1.624
local EXIT_LIFT = 0.4

-- Exit stabilization tuning.
-- SM character ejection happens when the unfreeze happens while intersecting a collider.
-- We counter this by: (1) choosing a stable pad footprint, (2) clearing velocity, then
-- (3) unfreezing on both server and client.
local EXIT_PAD_XZ_OFFSET = 0.55
local EXIT_PAD_RAYCAST_UP = 24
local EXIT_PAD_RAYCAST_DOWN = 80
local EXIT_PAD_CLEARANCE_Z = 0.06
local EXIT_PAD_NODE_NAMES = {
	"exit",
	"Exit",
	"exitPoint",
	"ExitPoint",
	"mount",
	"Mount",
	"padExit",
	"PadExit",
}

local function standWorldPos( self )
	local origin = self.shape.worldPosition
	local rot = self.shape.worldRotation
	local up = rot * sm.vec3.new( 0, 1, 0 )
	return origin + up * STAND_Y_M
end

local function exitWorldPos( self )
	local origin = self.shape.worldPosition
	local rot = self.shape.worldRotation
	local front = rot * sm.vec3.new( 0, 0, 1 )
	local up = rot * sm.vec3.new( 0, 1, 0 )
	local halfY = BOX_Y_BLOCKS * BLOCK_M * 0.5
	return origin + front * EXIT_FORWARD - up * halfY + sm.vec3.new( 0, 0, EXIT_LIFT )
end

-- IMPORTANT: SM exit/wrap positions can intersect terrain/colliders.
-- When that happens, the physics solver "ejects" the character upward.
-- To keep exits stable, we raycast the intended exit footprint downwards
-- and place the character just above the first hit surface.
local function safeExitPos( self )
	local shape = self and self.shape
	if not shape then
		return nil
	end

	-- If the station model has an explicit exit/mount node, prefer it (lets content
	-- authors avoid collider overlap on the footprint).
	local namedPad = nil
	for _, nodeName in ipairs( EXIT_PAD_NODE_NAMES ) do
		pcall( function()
			if namedPad then
				return
			end
			-- Most robust API: node world position.
			if type( shape.getNodeWorldPosition ) == "function" then
				local p = shape:getNodeWorldPosition( nodeName )
				if p and type( p.z ) == "number" then
					namedPad = p
					return
				end
			end
		end )
		if namedPad then
			break
		end
	end

	local candidate = namedPad or exitWorldPos( self )
	if not candidate then
		return nil
	end

	-- If we had to fall back to geometry-based exitWorldPos, offset away from the
	-- station center so we don't land inside the pad's collider.
	local x, y, z = candidate.x, candidate.y, candidate.z
	if not namedPad then
		local origin = shape.worldPosition
		if origin and type( origin.x ) == "number" and type( x ) == "number" and type( y ) == "number" then
			local dx = x - origin.x
			local dy = y - origin.y
			local len = math.sqrt( dx * dx + dy * dy )
			if len > 0.0001 then
				dx = dx / len
				dy = dy / len
				x = x + dx * EXIT_PAD_XZ_OFFSET
				y = y + dy * EXIT_PAD_XZ_OFFSET
			end
		end
	end

	local hit, result
	local ok = pcall( function()
		-- Scrap Mechanic world "up" is Z (see other RFS raycasts using result.pointWorld.z).
		hit, result = sm.physics.raycast(
			sm.vec3.new( x, y, z + EXIT_PAD_RAYCAST_UP ),
			sm.vec3.new( x, y, z - EXIT_PAD_RAYCAST_DOWN )
		)
	end )
	if ok and hit and result and result.pointWorld and type( result.pointWorld.z ) == "number" then
		-- Slight clearance above the first hit surface prevents immediate re-penetration.
		return sm.vec3.new( x, y, result.pointWorld.z + EXIT_PAD_CLEARANCE_Z )
	end
	return sm.vec3.new( x, y, z )
end

local FILL_CHEM = 10
local FILL_TICKS = 140 -- ~3.5 s rising tank
local DRAIN_TICKS = 120 -- ~3 s empty after exit
local HEAL_PER_TICK = 0.25
local HEAL_CHEM_EVERY = 40 -- 1 chem / s while they still need HP
local HEAL_POWER_EVERY = 80 -- 1 battery / 2 s = 5 batteries / ~10 s (or 5000 milli)
-- Client watchdog: if exit RPC doesn't clear the client lock quickly enough,
-- trigger a force-exit escape hatch.
local EXIT_PENDING_TICKS = 25 -- ~1.0-1.5s depending on client tick rate
-- Emergency watchdog: if the client stays locked/immovable for too long
-- (e.g. jump/E callbacks stop firing), force unlock and force-exit.
local EXIT_LOCKED_WATCHDOG_TICKS = 50 -- ~2-4s depending on client tick rate (was 75)

-- chemfill_v10 is block-space (×4 bake from v9 meters). Placed parts get engine ×0.25.
-- ShapeRenderable does NOT: 1 mesh unit = 1 m, so scale must include BLOCK_M.
-- Glass (same SM meters as the colba): outer r ≈ 0.774 m, h ≈ 2.75 m, floor y ≈ -1.25 m.
-- 0819-f used 0.375/0.650 as if the mesh radius was already 0.65 m → ~3 m wide / ~9 m tall.
local FILL_MESH_RADIUS = 2.599492
local FILL_MESH_HEIGHT = 9.020000
local FILL_MESH_Y_MIN = -4.789301
local FILL_RADIUS_M = 0.56 -- diam 1.12 m / 4.5 blocks; inside 0.774 m glass with wall margin
local FILL_HEIGHT_M = 2.00 -- below glass top ~1.51 m and claws; above metal floor
local FILL_BOTTOM_Y_M = -1.18 -- just above hull floor -1.25 m / glass min ~-1.24 m; not the base
local FILL_XZ_SCALE = FILL_RADIUS_M / FILL_MESH_RADIUS
local FILL_Y_SCALE = FILL_HEIGHT_M / FILL_MESH_HEIGHT
local FILL_UUID = sm.uuid.new( "a7e3c91f-6b24-4d80-8e15-2c9f4a0b7d63" )

local LOGIC = sm.interactable.connectionType.logic
local ELEC = sm.interactable.connectionType.electricity
local CHEM = sm.interactable.connectionType.chemical
local TITLE = "Chemical Regeneration Station"

_G.g_rfsHealPods = _G.g_rfsHealPods or {}
_G.g_rfsRegenByPlayer = _G.g_rfsRegenByPlayer or {}

local function shapeIdOf( self )
	local id = 0
	pcall( function()
		id = tonumber( self.shape.id ) or tonumber( self.shape:getId() ) or 0
	end )
	return id
end

local function registerPod( self )
	local id = shapeIdOf( self )
	if id ~= 0 then
		_G.g_rfsHealPods[id] = self
	end
end

local function unregisterPod( self )
	local id = shapeIdOf( self )
	if id ~= 0 then
		_G.g_rfsHealPods[id] = nil
	end
end

local function playerKey( player )
	local id = nil
	pcall( function()
		id = player.id
	end )
	if id == nil then
		pcall( function()
			id = player:getId()
		end )
	end
	if id == nil then
		return nil
	end
	return tostring( id )
end

local function setRegenState( player, fields )
	local id = playerKey( player )
	if not id then
		return
	end
	local st = _G.g_rfsRegenByPlayer[id] or {}
	for k, v in pairs( fields ) do
		st[k] = v
	end
	_G.g_rfsRegenByPlayer[id] = st
end

local function tellRegenLock( player, on )
	if not player or not sm.exists( player ) then
		return
	end
	setRegenState( player, {
		locked = on and true or false,
		applyHeal = false,
	} )
	pcall( function()
		sm.event.sendToPlayer( player, "sv_e_rfsRegenLock", { on = on and true or false } )
	end )
end

local function publish( self )
	local batteries = 0
	local recharge = 0
	pcall( function()
		batteries = Power.totalBatteries( Power.elecContainers( self ) )
		recharge = Power.totalRechargeBatteries( self )
	end )
	local data = {
		powered = self.sv.powered and true or false,
		healing = self.sv.healing and true or false,
		filling = self.sv.phase == "fill",
		soaking = self.sv.soak and true or false,
		draining = self.sv.phase == "drain",
		patients = self.sv.occupant and 1 or 0,
		batteries = batteries,
		recharge = recharge,
		fill = self.sv.fill or 0,
		needChem = self.sv.needChem and true or false,
		needPower = ( not self.sv.powered ) and true or false,
	}
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

local function occupantOk( self )
	local p = self.sv and self.sv.occupant
	if p and sm.exists( p ) then
		return p
	end
	return nil
end

local function characterOf( player )
	local char = nil
	pcall( function()
		char = player and ( player.character or player:getCharacter() )
	end )
	if char and sm.exists( char ) then
		return char
	end
	return nil
end

local function freezeCharacter( player, frozen )
	local char = characterOf( player )
	if not char then
		return
	end
	pcall( function()
		char:setImmovable( frozen and true or false )
	end )
end

local function warpPlayer( player, pos )
	if not player or not pos then
		return
	end
	local char = characterOf( player )
	if not char then
		return
	end
	pcall( function()
		char:setWorldPosition( pos )
	end )
end

local function zeroCharacterVelocity( player )
	local char = characterOf( player )
	if not char then
		return
	end
	local zero = sm.vec3.zero()
	-- SM character velocity API can vary between versions/mod environments.
	-- Best-effort: never hard-crash the server.
	pcall( function() char:setVelocity( zero ) end )
	pcall( function() char:setLinearVelocity( zero ) end )
end

local function clearServerCharacterLock( player )
	local char = characterOf( player )
	if not char then
		return
	end
	pcall( function()
		char:setLockingInteractable( nil )
	end )
	pcall( function()
		char:setImmovable( false )
	end )
end

local function cl_resetCameraFromPod()
	pcall( function()
		if sm.camera.getCameraState() ~= sm.camera.state.default then
			sm.camera.setCameraState( sm.camera.state.default )
		end
	end )
end

-- Bed.lua pattern: seat ragdoll handles in-tube pose. Manual warp + setImmovable
-- fights the shapeset seat bone and causes enter "launch then snap to center".
local function cl_zeroCharacterVelocity( character )
	if not character or not sm.exists( character ) then
		return
	end
	local zero = sm.vec3.zero()
	pcall( function() character:setVelocity( zero ) end )
	pcall( function() character:setLinearVelocity( zero ) end )
end

local function cl_seatInPod( self, character )
	if not self or not character or not sm.exists( character ) then
		return
	end
	cl_zeroCharacterVelocity( character )
	pcall( function()
		character:setLockingInteractable( self.interactable )
	end )
	pcall( function()
		if self.interactable and sm.exists( self.interactable ) then
			self.interactable:setSeatCharacter( character )
		end
	end )
end

local function cl_unseatFromPod( self, character )
	if not character or not sm.exists( character ) then
		return
	end
	pcall( function()
		if self.interactable and sm.exists( self.interactable ) then
			local seated = self.interactable:getSeatCharacter()
			if seated == character then
				-- Bed/Seat toggle: second setSeatCharacter clears the seat.
				self.interactable:setSeatCharacter( character )
			end
		end
	end )
	pcall( function()
		character:setLockingInteractable( nil )
	end )
	pcall( function()
		character:setImmovable( false )
	end )
end

-- Player.lua reload helper: compute exit pad from shape alone (no pod self).
function RfsChemStation.exitPosForShape( shape )
	if not shape then
		return nil
	end
	local proxy = { shape = shape }
	return safeExitPos( proxy ) or exitWorldPos( proxy )
end

function RfsChemStation.cl_releasePlayerLocal( interactable, shape, pos )
	local player = sm.localPlayer.getPlayer()
	local character = player and player:getCharacter()
	if not character or not sm.exists( character ) then
		return
	end
	local proxy = interactable and { interactable = interactable, shape = shape or ( interactable.shape ) }
	if proxy then
		cl_unseatFromPod( proxy, character )
	else
		pcall( function()
			character:setLockingInteractable( nil )
		end )
		pcall( function()
			character:setImmovable( false )
		end )
	end
	if not pos and shape then
		pos = RfsChemStation.exitPosForShape( shape )
	end
	cl_zeroCharacterVelocity( character )
	if pos then
		pcall( function()
			character:setWorldPosition( pos )
		end )
	end
	cl_resetCameraFromPod()
end

local function doExit( self, reason )
	local occ = occupantOk( self )
	if not occ then
		return
	end

	local pos
	pcall( function()
		pos = safeExitPos( self ) or exitWorldPos( self )
	end )

	-- Authoritative exit warp on server; client cl_n_lock clears seat + camera.
	if pos then
		warpPlayer( occ, pos )
	end
	zeroCharacterVelocity( occ )
	clearServerCharacterLock( occ )
	tellRegenLock( occ, false )

	-- Server already snapped the character; don't keep re-snapping on the client.
	pcall( function()
		local p = { enter = false, reason = reason }
		if pos and type( pos.x ) == "number" and type( pos.y ) == "number" and type( pos.z ) == "number" then
			p.x = pos.x
			p.y = pos.y
			p.z = pos.z
		end
		self.network:sendToClient( occ, "cl_n_lock", p )
	end )

	self.sv.occupant = nil
	self.sv.healing = false
end

-- Best-effort unlock for the requesting player.
-- Used when the server refuses a normal exit (aborted) or when the client
-- watchdog escalates to a "force exit".
local function sv_unlockLockedPlayer( self, player, reason )
	if not player or not sm.exists( player ) or not self then
		return
	end
	local character = characterOf( player )
	if not character or not sm.exists( character ) then
		return
	end

	local ia
	pcall( function()
		ia = character:getLockingInteractable()
	end )
	-- Normal case: server sees the character locked by this station.
	-- Emergency case: some clients desync lockingInteractable; still unlock
	-- if the player is physically near the station tube.
	if ia ~= self.interactable then
		local nearTube = false
		pcall( function()
			local sp = standWorldPos( self )
			local cp = character.worldPosition
			if sp and cp and type( sp.x ) == "number" and type( cp.x ) == "number" then
				local dx = cp.x - sp.x
				local dy = cp.y - sp.y
				local dz = cp.z - sp.z
				local d2 = dx * dx + dy * dy + dz * dz
				local r = 4.0 -- meters, best-effort "inside tube"
				nearTube = d2 <= ( r * r )
			end
		end )
		if not nearTube then
			return
		end
	end

	clearServerCharacterLock( player )
	zeroCharacterVelocity( player )
	tellRegenLock( player, false )

	local pos = nil
	pcall( function()
		pos = safeExitPos( self ) or exitWorldPos( self )
	end )
	if pos then
		warpPlayer( player, pos )
	end

	-- Also clear client-side lock/prompt state with the same RPC the normal exit uses.
	pcall( function()
		local p = { enter = false, reason = reason }
		if pos and type( pos.x ) == "number" and type( pos.y ) == "number" and type( pos.z ) == "number" then
			p.x = pos.x
			p.y = pos.y
			p.z = pos.z
		end
		self.network:sendToClient( player, "cl_n_lock", p )
	end )
end

local function chatTo( self, player, msg )
	if not player or not msg then
		return
	end
	pcall( function()
		self.network:sendToClient( player, "cl_n_chat", { msg = msg } )
	end )
end

local function beginDrain( self )
	self.sv.phase = "drain"
	self.sv.drainFrom = math.max( tonumber( self.sv.fill ) or 0, 0.02 )
	self.sv.drainTick = 0
	self.sv.fillPaid = false
	self.sv.soak = false
	self.sv.healAcc = 0
	self.sv.chemAcc = 0
	self.sv.needHeal = nil
	self.sv.warnedNoPower = false
end

function RfsChemStation.server_onCreate( self )
	self.sv = self.sv or {}
	self.sv.powered = false
	self.sv.healing = false
	self.sv.patients = 0
	self.sv.drainAcc = 0
	self.sv.fill = 0
	self.sv.phase = "idle"
	self.sv.occupant = nil
	self.sv.fillPaid = false
	self.sv.soak = false
	self.sv.fillTick = 0
	self.sv.healAcc = 0
	self.sv.chemAcc = 0
	self.sv.needHeal = true
	self.sv.needChem = false
	self.sv.warnedNoPower = false
	self.sv.loaded = true
	self.sv.staleLockSweep = false
	registerPod( self )
	pcall( function()
		self.interactable:setActive( false )
	end )
	publish( self )
end

function RfsChemStation.server_onDestroy( self )
	if self.sv and self.sv.loaded then
		tellRegenLock( self.sv.occupant, false )
		freezeCharacter( self.sv.occupant, false )
		pcall( function()
			if g_respawnManager then
				g_respawnManager:sv_destroyBed( self.shape )
			end
		end )
		self.sv.loaded = false
	end
	unregisterPod( self )
end

function RfsChemStation.server_onUnload( self )
	if self.sv and self.sv.loaded then
		pcall( function()
			if g_respawnManager then
				g_respawnManager:sv_updateBed( self.shape )
			end
		end )
		self.sv.loaded = false
	end
end

function RfsChemStation.sv_activateBed( self, character )
	if not character then
		return
	end
	pcall( function()
		if g_respawnManager then
			g_respawnManager:sv_registerBed( self.shape, character )
		end
	end )
end

function RfsChemStation.sv_e_rfsSkipDrain( self, params )
	local ticks = tonumber( params and params.ticks ) or 0
	if ticks <= 0 or not self.sv then
		return
	end
	if self.sv.phase ~= "heal" or not self.sv.powered then
		return
	end
	if type( Power ) ~= "table" or type( Power.spendOne ) ~= "function" then
		return
	end
	local every = tonumber( Power.DRAIN_EVERY ) or HEAL_POWER_EVERY
	if every < 1 then
		every = HEAL_POWER_EVERY
	end
	local n = math.floor( ticks / every )
	for _ = 1, n do
		if not Power.spendOne( self ) then
			self.sv.powered = false
			break
		end
	end
	publish( self )
end

function RfsChemStation.sv_n_tryEnter( self, params, player )
	if not player or not sm.exists( player ) then
		return
	end
	if occupantOk( self ) then
		if occupantOk( self ) == player then
			self:sv_n_tryExit( nil, player )
		else
			pcall( function()
				sm.gui.chatMessage( "[RFS] " .. TITLE .. ": station in use." )
			end )
		end
		return
	end
	if ( self.sv.phase == "drain" ) and ( ( self.sv.fill or 0 ) > 0.02 ) then
		pcall( function()
			sm.gui.chatMessage( "[RFS] " .. TITLE .. ": tank is draining." )
		end )
		return
	end
	if type( Power ) ~= "table" or not Power.hasChem( player, FILL_CHEM, self ) then
		self.sv.needChem = true
		publish( self )
		chatTo( self, player, "[RFS] " .. TITLE .. ": need " .. tostring( FILL_CHEM ) .. " Chemicals to fill." )
		return
	end
	local spent, src = false, nil
	if type( Power.spendChem ) == "function" then
		spent, src = Power.spendChem( player, FILL_CHEM, self )
	end
	if not spent then
		self.sv.needChem = true
		publish( self )
		chatTo( self, player, "[RFS] " .. TITLE .. ": need " .. tostring( FILL_CHEM ) .. " Chemicals to fill." )
		return
	end
	self.sv.needChem = false
	self.sv.occupant = player
	self.sv.phase = "fill"
	self.sv.fill = 0
	self.sv.fillTick = 0
	self.sv.fillPaid = true
	self.sv.fillPaidSrc = src
	self.sv.soak = false
	self.sv.healAcc = 0
	self.sv.chemAcc = 0
	self.sv.needHeal = true
	self.sv.warnedNoPower = false
	local char = nil
	pcall( function()
		char = player.character or player:getCharacter()
	end )
	self:sv_activateBed( char )
	tellRegenLock( player, true )
	zeroCharacterVelocity( player )
	-- Client setSeatCharacter (Bed pattern) handles tube snap; server warp fights seat ragdoll.
	self.network:sendToClient( player, "cl_n_lock", { enter = true } )
	publish( self )
end

function RfsChemStation.sv_n_tryExit( self, params, player )
	if not player or not sm.exists( player ) then
		return
	end

	local occ = occupantOk( self )
	if not occ or occ ~= player then
		sv_unlockLockedPlayer( self, player, "exit_aborted" )
		return
	end
	if self.sv.phase == "fill" and self.sv.fillPaid then
		Power.refundChem( occ, FILL_CHEM, self, self.sv.fillPaidSrc )
	end
	self.sv.fillPaid = false
	self.sv.fillPaidSrc = nil
	self.sv.soak = false
	doExit( self, "exit" )
	beginDrain( self )
	publish( self )
end

function RfsChemStation.sv_n_forceExit( self, params, player )
	if not player or not sm.exists( player ) then
		return
	end

	local occ = occupantOk( self )
	local reason = ( params and params.reason and tostring( params.reason ) ) or "force_exit"

	-- If we are the true occupant, do a full exit transition.
	if occ and occ == player then
		if self.sv.phase == "fill" and self.sv.fillPaid then
			Power.refundChem( occ, FILL_CHEM, self, self.sv.fillPaidSrc )
		end
		self.sv.fillPaid = false
		self.sv.fillPaidSrc = nil
		self.sv.soak = false
		doExit( self, reason )
		beginDrain( self )
		publish( self )
		return
	end

	-- Otherwise: clear the requesting player's lock state if it is stuck.
	sv_unlockLockedPlayer( self, player, reason )
end

function RfsChemStation.sv_e_rfsHealApplied( self, params )
	if type( params ) ~= "table" then
		return
	end
	self.sv.needHeal = params.applied and true or false
	if params.applied == false and self.sv.phase == "heal" and self.sv.soak and occupantOk( self ) then
		doExit( self, "heal_complete" )
		beginDrain( self )
	end
end

function RfsChemStation.server_onFixedUpdate( self )
	if not self.sv then
		return
	end
	registerPod( self )
	if not self.sv.staleLockSweep then
		self.sv.staleLockSweep = true
		local occ = occupantOk( self )
		pcall( function()
			for _, player in ipairs( sm.player.getAllPlayers() or {} ) do
				if player and sm.exists( player ) and player ~= occ then
					local char = characterOf( player )
					local ia = char and char:getLockingInteractable()
					if ia and ia == self.interactable then
						sv_unlockLockedPlayer( self, player, "reload_stale_lock" )
					end
				end
			end
		end )
	end
	if self.sv.loaded then
		local prevWorld = self.sv.currentWorld
		pcall( function()
			self.sv.currentWorld = self.shape.body:getWorld()
		end )
		if prevWorld ~= nil and self.sv.currentWorld ~= prevWorld then
			pcall( function()
				if g_respawnManager then
					g_respawnManager:sv_updateBed( self.shape )
				end
			end )
		end
	end

	local powered = false
	pcall( function()
		powered = Power.isPowered( self )
	end )

	local occ = occupantOk( self )
	if self.sv.occupant and not occ then
		tellRegenLock( self.sv.occupant, false )
		freezeCharacter( self.sv.occupant, false )
		self.sv.occupant = nil
		self.sv.healing = false
		self.sv.fillPaid = false
		self.sv.soak = false
		if self.sv.phase == "fill" or self.sv.phase == "heal" then
			beginDrain( self )
		end
	end
	occ = occupantOk( self )
	if occ then
		setRegenState( occ, { locked = true } )
	end

	if self.sv.phase == "fill" and occ then
		self.sv.fillTick = ( self.sv.fillTick or 0 ) + 1
		self.sv.fill = math.min( 1, self.sv.fillTick / FILL_TICKS )
		if self.sv.fillTick >= FILL_TICKS then
			self.sv.fill = 1
			self.sv.needChem = false
			self.sv.soak = true
			self.sv.phase = "heal"
			self.sv.needHeal = true
			self.sv.healAcc = 0
			self.sv.chemAcc = 0
			-- Paid at tryEnter; clear flag so exit during heal does not refund.
			self.sv.fillPaid = false
			self.sv.fillPaidSrc = nil
			if not powered then
				self.sv.warnedNoPower = true
				chatTo( self, occ, "[RFS] " .. TITLE .. ": filled. Wire a Battery box or Rechargeable box to heal." )
			end
			local nPlayers = 0
			pcall( function()
				nPlayers = #( sm.player.getAllPlayers() or {} )
			end )
			chatTo( self, occ, "[RFS] " .. TITLE .. ": respawn location set." )
			if nPlayers <= 1 and type( Time ) == "table" then
				pcall( function()
					sm.event.sendToGame( "sv_e_rfsDeepSleepSkip", { healing = true, player = occ } )
				end )
			elseif nPlayers > 1 then
				chatTo( self, occ, "[RFS] " .. TITLE .. ": night skip is solo-only." )
			end
		end
	end

	local wasHealing = self.sv.healing and true or false
	local working = false
	if self.sv.phase == "heal" and self.sv.soak and occ then
		if powered then
			self.sv.warnedNoPower = false
			local need = self.sv.needHeal
			if need == nil then
				need = true
			end
			-- Interactable and Player do not share _G. H's applyHeal table never
			-- reached Player. Send primitives only (Interactable userdata drops the event).
			pcall( function()
				sm.event.sendToPlayer( occ, "sv_e_rfsDeepSleepHeal", {
					amount = HEAL_PER_TICK,
					shapeId = shapeIdOf( self ),
				} )
			end )
			setRegenState( occ, {
				locked = true,
				applyHeal = true,
				amount = HEAL_PER_TICK,
				shapeId = shapeIdOf( self ),
			} )
			if need then
				working = true
				self.sv.chemAcc = ( self.sv.chemAcc or 0 ) + 1
				if self.sv.chemAcc >= HEAL_CHEM_EVERY then
					self.sv.chemAcc = 0
					if not Power.spendChem( occ, 1, self ) then
						self.sv.needChem = true
						working = false
						doExit( self, "no_chem" )
						beginDrain( self )
						occ = nil
					else
						self.sv.needChem = false
					end
				end
			end
		else
			setRegenState( occ, { locked = true, applyHeal = false } )
			if not self.sv.warnedNoPower then
				self.sv.warnedNoPower = true
				chatTo( self, occ, "[RFS] " .. TITLE .. ": filled. Wire a Battery box or Rechargeable box to heal." )
			end
			if wasHealing then
				doExit( self, "no_power" )
				beginDrain( self )
				occ = nil
			end
		end
	elseif occ then
		setRegenState( occ, { locked = true, applyHeal = false } )
	end

	if type( Power ) == "table" then
		if working then
			self.sv.healAcc = ( self.sv.healAcc or 0 ) + 1
			local every = tonumber( Power.DRAIN_EVERY ) or HEAL_POWER_EVERY
			if every < 1 then
				every = HEAL_POWER_EVERY
			end
			if self.sv.healAcc >= every then
				self.sv.healAcc = 0
				if not Power.spendOne( self ) then
					powered = false
					-- Battery ran out mid-heal: release the occupant immediately.
					doExit( self, "no_power" )
					beginDrain( self )
					working = false
					occ = nil
				else
					powered = Power.isPowered( self )
				end
			end
		else
			self.sv.healAcc = 0
			powered = Power.isPowered( self )
		end
	end

	if self.sv.phase == "drain" then
		self.sv.drainTick = ( self.sv.drainTick or 0 ) + 1
		local from = tonumber( self.sv.drainFrom ) or 1
		local t = math.min( 1, self.sv.drainTick / DRAIN_TICKS )
		self.sv.fill = from * ( 1 - t )
		if t >= 1 then
			self.sv.fill = 0
			self.sv.phase = "idle"
		end
	end

	-- Backup: release occupant when heal finished but sv_e_rfsHealApplied RPC was lost.
	if self.sv.phase == "heal" and self.sv.soak and occ and self.sv.needHeal == false then
		doExit( self, "heal_complete" )
		beginDrain( self )
		occ = nil
	end

	self.sv.powered = powered
	self.sv.healing = working and powered
	self.sv.patients = occ and 1 or 0
	pcall( function()
		self.interactable:setActive( false )
	end )
	if ( sm.game.getCurrentTick() % 4 ) == 0 or working or self.sv.phase ~= "idle" then
		publish( self )
	end
end

function RfsChemStation.client_onCreate( self )
	self.cl = {
		powered = false,
		healing = false,
		fill = 0,
		pendingExit = 0,
		exitAttempted = false,
		exitAttemptTick = nil,
		locked = false,
		lockedAtTick = nil,
		exitWatchdogTriggered = false,
		forceExitSent = false,
		lastSafeExitPos = nil,
		lockedWatchdogCounter = 0,
		exitJustWarpedTick = nil,
		-- Block placement / tool modes sometimes suppress normal interaction text
		-- refresh; keep re-applying the exit prompt for a short window after forcing unlock.
		forceExitPromptUntilTick = nil,
	}
	-- After reload the pod forgets occupant but the character can still be locked in-tube.
	pcall( function()
		local player = sm.localPlayer.getPlayer()
		local character = player and player:getCharacter()
		if not character or not sm.exists( character ) then
			return
		end
		local ia = character:getLockingInteractable()
		if ia and sm.exists( ia ) and ia == self.interactable then
			local pos = safeExitPos( self ) or exitWorldPos( self )
			RfsChemStation.cl_releasePlayerLocal( self.interactable, self.shape, pos )
			self.cl.locked = false
			self.cl.pendingExit = 0
		end
	end )
end

function RfsChemStation.client_onDestroy( self )
	if self.cl and self.cl.locked then
		local player = sm.localPlayer.getPlayer()
		local character = player and player:getCharacter()
		if character and sm.exists( character ) then
			cl_unseatFromPod( self, character )
		end
		self.cl.locked = false
	end
	if self.cl and self.cl.fillFx then
		pcall( function()
			self.cl.fillFx:stop()
		end )
		pcall( function()
			self.cl.fillFx:destroy()
		end )
		self.cl.fillFx = nil
	end
end

function RfsChemStation.cl_n_lock( self, params )
	local player = sm.localPlayer.getPlayer()
	local character = player and player:getCharacter()
	if not character or not sm.exists( character ) then
		return
	end
	self.cl = self.cl or {}
	if params and params.enter then
		self.cl.locked = true
		self.cl.exitAttempted = false
		self.cl.exitAttemptTick = nil
		self.cl.exitWatchdogTriggered = false
		self.cl.forceExitSent = false
		self.cl.lockedWatchdogCounter = 0
		self.cl.lastSafeExitPos = nil
		pcall( function()
			self.cl.lockedAtTick = sm.game.getCurrentTick and sm.game.getCurrentTick() or nil
		end )
		self.cl.pendingExit = 0
		cl_seatInPod( self, character )
	else
		self.cl.locked = false
		self.cl.exitAttempted = false
		self.cl.exitAttemptTick = nil
		self.cl.exitWatchdogTriggered = false
		self.cl.forceExitSent = false
		self.cl.lockedAtTick = nil
		self.cl.lockedWatchdogCounter = 0

		self.cl.pendingExit = 0
		pcall( function()
			local tick = sm.game.getCurrentTick and sm.game.getCurrentTick() or 0
			self.cl.exitJustWarpedTick = tick
		end )
		cl_unseatFromPod( self, character )
		local exitPos = nil
		if params and params.x then
			exitPos = sm.vec3.new( params.x, params.y, params.z )
		else
			exitPos = safeExitPos( self ) or exitWorldPos( self )
		end
		cl_zeroCharacterVelocity( character )
		if exitPos then
			pcall( function()
				character:setWorldPosition( exitPos )
			end )
		end
		cl_resetCameraFromPod()
	end
end

function RfsChemStation.cl_updateFillFx( self )
	local fill = tonumber( self.cl and self.cl.fill ) or 0
	if fill < 0.02 then
		if self.cl.fillFx then
			pcall( function()
				self.cl.fillFx:stop()
			end )
			pcall( function()
				self.cl.fillFx:destroy()
			end )
			self.cl.fillFx = nil
		end
		return
	end
	if not self.cl.fillFx then
		local fx = nil
		pcall( function()
			fx = sm.effect.createEffect( "ShapeRenderable" )
			fx:setParameter( "uuid", FILL_UUID )
			fx:setParameter( "color", sm.color.new( 0x7a28c8ff ) )
		end )
		self.cl.fillFx = fx
	end
	local fx = self.cl.fillFx
	if not fx then
		return
	end
	local origin = self.shape.worldPosition
	local rot = self.shape.worldRotation
	local up = rot * sm.vec3.new( 0, 1, 0 )
	local yScale = math.max( fill, 0.02 ) * FILL_Y_SCALE
	pcall( function()
		fx:setPosition( origin + up * ( FILL_BOTTOM_Y_M - FILL_MESH_Y_MIN * yScale ) )
		fx:setRotation( rot )
		fx:setScale( sm.vec3.new( FILL_XZ_SCALE, yScale, FILL_XZ_SCALE ) )
		fx:start()
	end )
end

function RfsChemStation.client_onFixedUpdate( self )
	if not ( self.cl and self.cl.locked ) then
		return
	end
	local player = sm.localPlayer.getPlayer()
	local character = player and player:getCharacter()
	if not character or not sm.exists( character ) then
		return
	end
	-- Keep seat ragdoll attached; do not setImmovable (fights seat and causes ejection).
	pcall( function()
		if self.interactable and sm.exists( self.interactable ) then
			local seated = self.interactable:getSeatCharacter()
			if seated ~= character then
				cl_seatInPod( self, character )
			end
		end
	end )
end

local function cl_forceUnlock( self, reason )
	local player = sm.localPlayer.getPlayer()
	local character = player and player:getCharacter()
	if not character or not sm.exists( character ) then
		return
	end

	self.cl = self.cl or {}
	self.cl.pendingExit = 0
	self.cl.locked = false
	self.cl.exitAttempted = false
	self.cl.exitAttemptTick = nil
	self.cl.exitWatchdogTriggered = true
	self.cl.lockedAtTick = nil
	self.cl.lockedWatchdogCounter = 0

	-- Best-effort local unlock so movement / input immediately works.
	-- Server will still be responsible for the authoritative warp/exit.
	local pos = self.cl.lastSafeExitPos
	if not pos then
		pos = safeExitPos( self ) or exitWorldPos( self )
		self.cl.lastSafeExitPos = pos
	end
	cl_unseatFromPod( self, character )
	cl_zeroCharacterVelocity( character )
	if pos then
		pcall( function()
			character:setWorldPosition( pos )
		end )
	end
	cl_resetCameraFromPod()

	-- Restore interaction prompt so the user sees an immediate exit affordance.
	-- (If the station is still in regen/fill state, the engine will shortly refresh it.)
	pcall( function()
		sm.gui.setInteractionText( "", "", TITLE .. " — E / jump to exit" )
	end )

	-- Re-apply for a short time in case block placement / tool modes clear it.
	local tickNow = nil
	pcall( function()
		tickNow = sm.game.getCurrentTick and sm.game.getCurrentTick() or nil
	end )
	if type( tickNow ) == "number" then
		self.cl.forceExitPromptUntilTick = tickNow + 60
	end
end

function RfsChemStation.client_onUpdate( self, dt )
	-- Pod shell forwards top-level callbacks only; internal self: calls miss RfsChemStation.
	RfsChemStation.cl_updateFillFx( self )
	if not self.cl then
		return
	end
	-- If the pod is actively healing server-side, do NOT send any "force exit"
	-- RPC from watchdog recovery. Otherwise we can clear server healing state
	-- (no drain, no HP gain) even though the station is healthy.
	local healingActive = self.cl.healing and true or false

	-- Ensure exit prompt stays visible even in block placement/tool modes.
	do
		local untilTick = self.cl.forceExitPromptUntilTick
		if type( untilTick ) == "number" then
			local tickNow = nil
			pcall( function()
				tickNow = sm.game.getCurrentTick and sm.game.getCurrentTick() or nil
			end )
			if type( tickNow ) == "number" and tickNow <= untilTick then
				pcall( function()
					sm.gui.setInteractionText( "", "", TITLE .. " — E / jump to exit" )
				end )
			else
				self.cl.forceExitPromptUntilTick = nil
			end
		end
	end

	-- Emergency: if we stay locked/immovable for too long (and exit callbacks stop),
	-- unlock immediately. This prevents permanent "stuck in station" states.
	do
		if not self.cl.exitWatchdogTriggered then
			-- Only recover if this client currently thinks it's locked by this station.
			-- Avoids firing in unrelated "immovable" states.
			if not self.cl.locked then
				self.cl.lockedAtTick = nil
				self.cl.lockedWatchdogCounter = 0
				return
			end
			-- Critical gate: during normal healing we intentionally remain locked and immovable.
			-- Only run the "emergency" unlock if the player actually attempted to exit.
			if not self.cl.exitAttempted then
				self.cl.lockedAtTick = nil
				self.cl.lockedWatchdogCounter = 0
				return
			end
			-- Additional gate: only run while the exit handshake is pending.
			-- During normal healing `pendingExit` stays 0 (camera remains in-tube).
			local pending = ( self.cl.pendingExit or 0 )
			if pending <= 0 then
				self.cl.exitAttempted = false
				self.cl.exitAttemptTick = nil
				self.cl.lockedAtTick = nil
				self.cl.lockedWatchdogCounter = 0
				return
			end

			local player = sm.localPlayer.getPlayer()
			local character = player and player:getCharacter()

			local physLocked = false
			pcall( function()
				if character and sm.exists( character ) then
					physLocked = character:getImmovable() and true or false
				end
			end )

			-- Proximity helpers:
			-- We intentionally do NOT depend on lockingInteractable / occupant state.
			local tubeCenter = nil
			pcall( function()
				tubeCenter = standWorldPos( self )
			end )

			local camInTube = false
			pcall( function()
				local camPos = sm.camera.getPosition and sm.camera.getPosition() or nil
				if camPos and tubeCenter and type( tubeCenter.x ) == "number" and type( camPos.x ) == "number" then
					local dx = camPos.x - tubeCenter.x
					local dy = camPos.y - tubeCenter.y
					local dz = camPos.z - tubeCenter.z
					local d2 = dx * dx + dy * dy + dz * dz
					local r = 4.0 -- meters (must match sv_unlockLockedPlayer "near tube" fallback)
					camInTube = d2 <= ( r * r )

					-- Optional second centroid to cover "camera inside tube/front footprint" desyncs.
					-- (The primary tube center remains `standWorldPos(self)` for server parity.)
					if not camInTube then
						local ep = exitWorldPos( self )
						if ep and type( ep.x ) == "number" then
							local ddx = camPos.x - ep.x
							local ddy = camPos.y - ep.y
							local ddz = camPos.z - ep.z
							local dd2 = ddx * ddx + ddy * ddy + ddz * ddz
							camInTube = dd2 <= ( r * r )
						end
					end
				end
			end )

			local function triggerWatchdog( reason )
				-- Force client unlock regardless of pendingExit/prompt visibility.
				self.cl.exitWatchdogTriggered = true
				pcall( function()
					sm.gui.setInteractionText( "", "", TITLE .. " — E / jump to exit" )
				end )
				cl_forceUnlock( self, reason or "locked_watchdog_timeout" )

				if not self.cl.forceExitSent then
					self.cl.forceExitSent = true
					-- When actively healing, recover by client-unlocking only.
					-- Keep server regen/lock running until normal exit.
					if not healingActive then
						pcall( function()
							self.network:sendToServer( "sv_n_forceExit", { reason = reason or "locked_watchdog" } )
						end )
					end
				end
			end

			local tickNow = nil
			pcall( function()
				tickNow = sm.game.getCurrentTick and sm.game.getCurrentTick() or nil
			end )

			if type( tickNow ) == "number" then
				-- Measure timeout since the *exit attempt* (not since camera/immovable state
				-- started), so normal healing in-tube never arms this recovery path.
				if type( self.cl.exitAttemptTick ) ~= "number" then
					self.cl.exitAttemptTick = tickNow
				end
				local waited = tickNow - ( self.cl.exitAttemptTick or tickNow )
				if waited >= EXIT_LOCKED_WATCHDOG_TICKS then
					if physLocked then
						triggerWatchdog( "locked_watchdog_immovable" )
					elseif camInTube then
						triggerWatchdog( "locked_watchdog_camera" )
					else
						-- Evidence disappeared; disarm.
						self.cl.exitAttemptTick = nil
						self.cl.lockedAtTick = nil
						self.cl.lockedWatchdogCounter = 0
					end
				elseif not physLocked and not camInTube then
					-- Reset if we temporarily lost all stuck evidence.
					self.cl.exitAttemptTick = nil
					self.cl.lockedAtTick = nil
					self.cl.lockedWatchdogCounter = 0
				end
			else
				-- Fallback if tick API is unavailable for some reason.
				if physLocked or camInTube then
					self.cl.lockedWatchdogCounter = ( self.cl.lockedWatchdogCounter or 0 ) + 1
					if self.cl.lockedWatchdogCounter >= EXIT_LOCKED_WATCHDOG_TICKS then
						triggerWatchdog( physLocked and "locked_watchdog_immovable" or "locked_watchdog_camera" )
					end
				else
					self.cl.lockedWatchdogCounter = 0
					self.cl.lockedAtTick = nil
				end
			end
		end
	end

	local pending = ( self.cl.pendingExit or 0 )
	if pending <= 0 then
		return
	end

	-- While locked: count down and escalate to a forced unlock if we don't get
	-- the normal server "cl_n_lock enter=false" clearing message.
	if self.cl.locked then
		self.cl.pendingExit = pending - 1
		if ( self.cl.pendingExit or 0 ) <= 0 then
			cl_forceUnlock( self, "exit_watchdog_timeout" )
			if not self.cl.forceExitSent then
				self.cl.forceExitSent = true
				-- When actively healing, skip server forceExit; client unlock is
				-- enough to prevent permanent "stuck in tube" states.
				if not healingActive then
					pcall( function()
						self.network:sendToServer( "sv_n_forceExit", { reason = "exit_watchdog" } )
					end )
				end
			end
			self.cl.pendingExit = 0
		end
		return
	end

	-- Not locked: defensive snap while we wait for the server-provided warp.
	-- Defensive: if the server just warped us out, don't client-snap again even if
	-- some other code ever sets pendingExit.
	if type( self.cl.exitJustWarpedTick ) == "number" then
		local ok, tick = pcall( function()
			return sm.game.getCurrentTick and sm.game.getCurrentTick() or 0
		end )
		if ok and ( tick - self.cl.exitJustWarpedTick ) <= 2 then
			return
		end
	end

	self.cl.pendingExit = pending - 1
	local player = sm.localPlayer.getPlayer()
	local character = player and player:getCharacter()
	if character and sm.exists( character ) then
		pcall( function()
			-- Defensive: if pendingExit is ever set again, snap to the same stable footprint.
			local pos = safeExitPos( self ) or exitWorldPos( self )
			if pos then
				character:setWorldPosition( pos )
			end
		end )
	end
end

local function cl_applyServerRelease( self, reason )
	if not self.cl or not self.cl.locked then
		return
	end
	local player = sm.localPlayer.getPlayer()
	local character = player and player:getCharacter()
	if not character or not sm.exists( character ) then
		return
	end
	local pos = self.cl.lastSafeExitPos
	if not pos then
		pcall( function()
			pos = safeExitPos( self ) or exitWorldPos( self )
		end )
		self.cl.lastSafeExitPos = pos
	end
	RfsChemStation.cl_n_lock( self, {
		enter = false,
		reason = reason or "server_released",
		x = pos and pos.x,
		y = pos and pos.y,
		z = pos and pos.z,
	} )
end

function RfsChemStation.client_onClientDataUpdate( self, data )
	if type( data ) ~= "table" then
		return
	end
	self.cl = self.cl or {}
	self.cl.powered = data.powered and true or false
	self.cl.healing = data.healing and true or false
	self.cl.filling = data.filling and true or false
	self.cl.soaking = data.soaking and true or false
	self.cl.draining = data.draining and true or false
	self.cl.patients = data.patients or 0
	self.cl.batteries = data.batteries or 0
	self.cl.recharge = data.recharge or 0
	self.cl.fill = tonumber( data.fill ) or 0
	self.cl.needChem = data.needChem and true or false
	self.cl.needPower = data.needPower and true or false
	-- Heal-complete / auto-exit: server clears occupant while the client lock
	-- watchdog stays disarmed during healing (no exitAttempted).
	if self.cl.locked and ( data.patients or 0 ) == 0 and not data.filling and not data.healing then
		cl_applyServerRelease( self, "server_released" )
	end
end

function RfsChemStation.cl_n_chat( self, params )
	if params and params.msg then
		pcall( function()
			sm.gui.chatMessage( params.msg )
		end )
	end
end

function RfsChemStation.client_onInteract( self, character, state )
	if state == true then
		self.network:sendToServer( "sv_n_tryEnter" )
	end
end

function RfsChemStation.client_onAction( self, controllerAction, state )
	if state == true then
		if controllerAction == sm.interactable.actions.use or controllerAction == sm.interactable.actions.jump then
			if self.cl and self.cl.locked then
				-- Evidence that the player is trying to exit; emergency watchdog is allowed
				-- only after an actual exit attempt.
				self.cl.exitAttempted = true
				local tickNow = nil
				pcall( function()
					tickNow = sm.game.getCurrentTick and sm.game.getCurrentTick() or nil
				end )
				if type( tickNow ) == "number" then
					self.cl.exitAttemptTick = tickNow
				else
					self.cl.exitAttemptTick = nil
				end
				self.cl.lockedAtTick = nil
				self.cl.lockedWatchdogCounter = 0

				-- If the player spams exit while we are still waiting for the
				-- server to clear the client lock, escalate to force-exit.
				if ( self.cl.pendingExit or 0 ) > 0 then
					self.network:sendToServer( "sv_n_forceExit", { reason = "client_spam_exit" } )
					self.cl.pendingExit = 0
				else
					self.cl.pendingExit = EXIT_PENDING_TICKS
					self.network:sendToServer( "sv_n_tryExit" )
				end
			end
		end
	end
	return true
end

function RfsChemStation.client_canInteract( self )
	local pd = self.cl or {}
	if pd.filling then
		sm.gui.setInteractionText( "", "", TITLE .. " — filling (" .. tostring( FILL_CHEM ) .. " Chemicals)" )
	elseif pd.healing then
		sm.gui.setInteractionText( "", "", TITLE .. " — regenerating. E / jump to exit" )
	elseif pd.soaking and not pd.powered then
		sm.gui.setInteractionText( "", "", TITLE .. " — filled. Need power to heal. E / jump to exit" )
	elseif pd.soaking then
		sm.gui.setInteractionText( "", "", TITLE .. " — tank full. E / jump to exit" )
	elseif pd.draining then
		sm.gui.setInteractionText( "", "", TITLE .. " — tank draining" )
	elseif pd.needChem then
		sm.gui.setInteractionText( "", "", TITLE .. " — need " .. tostring( FILL_CHEM ) .. " Chemicals to fill" )
	elseif not pd.powered then
		sm.gui.setInteractionText( "", "", TITLE .. " — E to fill (10 Chemicals). Wire power to heal" )
	else
		sm.gui.setInteractionText( "", "", TITLE .. " — E to enter and fill (10 Chemicals)" )
	end
	return true
end

function RfsChemStation.client_getAvailableParentConnectionCount( self, connectionType )
	if type( Power ) ~= "table" then
		return 1
	end
	local function parentCount( kind )
		local n = 0
		pcall( function()
			n = #( self.interactable:getParents( kind ) or {} )
		end )
		return n
	end
	if Power.band( connectionType, CHEM ) ~= 0 then
		return math.max( 0, 1 - parentCount( CHEM ) )
	end
	if Power.band( connectionType, ELEC ) ~= 0 then
		return math.max( 0, 1 - parentCount( ELEC ) )
	end
	if Power.band( connectionType, LOGIC ) ~= 0 then
		return math.max( 0, 1 - parentCount( LOGIC ) )
	end
	return 0
end


-- =============================================================================
-- VOLATILE: Solo night skip (formerly RfsDeepSleepTime.lua)
-- =============================================================================

local Time = {}

pcall( function()
	dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsRecharge.lua" )
end )

local FIVE_AM = 5 / 24
local NIGHT = 0.875
pcall( function()
	if type( DAYCYCLE_NIGHT ) == "number" then
		NIGHT = DAYCYCLE_NIGHT
	end
end )

local TICKS_PER_DAY = 1440 * 40
pcall( function()
	if type( DAYCYCLE_TIME_TICKS ) == "number" and DAYCYCLE_TIME_TICKS > 0 then
		TICKS_PER_DAY = DAYCYCLE_TIME_TICKS
	end
end )

local SOLAR_UUID = "7a402d6c-93e5-4f28-ab71-d2e6f9a3b5c8"
local DEEPSLEEP_UUID = "6f391c5b-82d4-4e17-9a60-c1d5e8f2a4b7"
local BEACON_UUIDS = {
	["b4e8c1a0-7d2f-4a91-9c3e-29f1a8d6b5e7"] = true,
	["c5f9d2b1-8e30-4ba2-ad4f-30a2b9e7c6f8"] = true,
	["d6a0e3c2-9f41-4cb3-be50-41b3c0f8d709"] = true,
}

local function uuidStr( u )
	local s = string.lower( tostring( u or "" ) )
	local m = string.match( s, "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x" )
	return m or s
end

local function playerCount()
	local n = 0
	pcall( function()
		local all = sm.player.getAllPlayers() or {}
		n = #all
	end )
	return n
end

function Time.isNight( tod )
	tod = tonumber( tod )
	if not tod then
		pcall( function()
			tod = sm.game.getTimeOfDay()
		end )
	end
	tod = tonumber( tod ) or 0.5
	local wrapped = tod - math.floor( tod )
	return wrapped >= NIGHT or wrapped < FIVE_AM
end

function Time.soloOk()
	return playerCount() <= 1
end

local function wrappedTod( game )
	local tod = 0.5
	pcall( function()
		if game and game.sv and game.sv.time and game.sv.time.timeOfDay then
			tod = tonumber( game.sv.time.timeOfDay ) or tod
		else
			tod = sm.game.getTimeOfDay() or tod
		end
	end )
	return tod, tod - math.floor( tod )
end

-- Ticks from now until next 5 AM. 0 if not night.
function Time.skipTicks( game )
	if not Time.isNight( select( 1, wrappedTod( game ) ) ) then
		return 0, nil
	end
	local tod, wrapped = wrappedTod( game )
	local delta
	if wrapped >= FIVE_AM then
		delta = ( 1 - wrapped ) + FIVE_AM
	else
		delta = FIVE_AM - wrapped
	end
	if delta < 0 then
		delta = 0
	end
	local ticks = math.floor( delta * TICKS_PER_DAY + 0.5 )
	local nextTod = math.floor( tod )
	if wrapped >= FIVE_AM then
		nextTod = nextTod + 1
	end
	nextTod = nextTod + FIVE_AM
	return ticks, nextTod
end

local function applyTime( game, nextTod )
	if not game or not game.sv or not game.sv.time then
		return false
	end
	game.sv.time.timeOfDay = nextTod
	pcall( function()
		if game.sv.syncTimer and game.sv.syncTimer.ticks then
			game.sv.syncTimer.count = game.sv.syncTimer.ticks
		end
	end )
	pcall( function()
		local ch = ( type( STORAGE_CHANNEL_TIME ) == "number" and STORAGE_CHANNEL_TIME ) or 16
		sm.storage.save( ch, game.sv.time )
	end )
	pcall( function()
		game:sv_updateClientData()
	end )
	local frac = nextTod - math.floor( nextTod )
	pcall( function()
		sm.game.setTimeOfDay( frac )
	end )
	pcall( function()
		if WeatherManager and WeatherManager.Get then
			local w = WeatherManager.Get()
			if w and w.sv_setTimeOfDay then
				w:sv_setTimeOfDay( frac )
			end
		end
	end )
	return true
end

local function skipChat( game, player, msg )
	if not msg then
		return
	end
	if player and game and game.network then
		pcall( function()
			game.network:sendToClient( player, "client_showMessage", msg )
		end )
	elseif game and game.network then
		pcall( function()
			game.network:sendToClients( "client_showMessage", msg )
		end )
	end
end

function Time.skipFromGame( game, params )
	params = params or {}
	local player = params.player
	if not Time.soloOk() then
		skipChat( game, player, "[RFS] Chemical Regeneration Station: night skip is solo-only (vote parked)." )
		return false, "mp"
	end
	local ticks, nextTod = Time.skipTicks( game )
	if not ticks or ticks <= 0 or not nextTod then
		skipChat( game, player, "[RFS] Chemical Regeneration Station: daytime — no night skip." )
		return false, "day"
	end
	local ok = applyTime( game, nextTod )
	if not ok then
		skipChat( game, player, "[RFS] Chemical Regeneration Station: time skip API missing; respawn still set." )
		return false, "noapi"
	end
	pcall( function()
		if type( RfsFarming ) == "table" and RfsFarming.advanceGrowthTicks then
			RfsFarming.advanceGrowthTicks( game, ticks )
		end
	end )
	pcall( function()
		local host = nil
		if game.sv_rfs_ensureHijackHost then
			host = game:sv_rfs_ensureHijackHost()
		end
		if host then
			sm.event.sendToScriptableObject( host, "sv_e_rfsDeepSleepWorldSkip", {
				ticks = ticks,
				podHealing = params.healing and true or false,
			} )
		end
	end )
	skipChat( game, player, "[RFS] Chemical Regeneration Station: skipped night to 5 AM (" .. tostring( ticks ) .. " ticks)." )
	return true, ticks
end

local function sendToShape( shape, name, payload )
	if not shape or not sm.exists( shape ) then
		return
	end
	pcall( function()
		local ia = shape.interactable or shape:getInteractable()
		if ia and sm.exists( ia ) then
			sm.event.sendToInteractable( ia, name, payload )
		end
	end )
end

function Time.worldSkip( host, params )
	params = params or {}
	local ticks = tonumber( params.ticks ) or 0
	if ticks <= 0 then
		return
	end
	local bodies = {}
	pcall( function()
		bodies = sm.body.getAllBodies() or {}
	end )
	if type( bodies ) ~= "table" or #bodies == 0 then
		pcall( function()
			if host and host.world and host.world.getAllBodies then
				bodies = host.world:getAllBodies() or {}
			end
		end )
	end
	if type( bodies ) ~= "table" then
		return
	end
	for _, body in ipairs( bodies ) do
		if body and sm.exists( body ) then
			local shapes = nil
			pcall( function()
				shapes = body:getShapes() or body:getCreationShapes()
			end )
			if type( shapes ) == "table" then
				for _, shape in ipairs( shapes ) do
					if shape and sm.exists( shape ) then
						local id = uuidStr( shape.uuid )
						if id == SOLAR_UUID then
							sendToShape( shape, "sv_e_rfsSkipCharge", { ticks = ticks } )
						elseif BEACON_UUIDS[id] then
							sendToShape( shape, "sv_e_rfsSkipDrain", { ticks = ticks } )
						elseif id == DEEPSLEEP_UUID and params.podHealing then
							sendToShape( shape, "sv_e_rfsSkipDrain", { ticks = ticks } )
						end
					end
				end
			end
		end
	end
end



RfsChemStation.power = Power
RfsChemStation.time = Time
RfsHealPower = Power
RfsDeepSleepTime = Time

print( "[RFS] RfsChemStation loaded (FROZEN chem regen + VOLATILE night skip)" )
