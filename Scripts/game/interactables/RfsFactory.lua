-- RfsFactory.lua — Phase 4 ally factory (RFS part).
-- Spends Metal + Battery to sm.unit.createUnit(..., { playerAlly=true, ... }).
-- Capsules stay hostile. Factory is the ally spawner. Army size is capped.
-- Optional flavor is one machine cycling tote / hay barn / tape assembly / farm garage.
-- Do not auto-unlock Craftbot: Hideout Farmers item trade is the v1 acquire path.

RfsFactory = class( nil )
RfsFactory.maxParentCount = 2
RfsFactory.maxChildCount = 0
RfsFactory.connectionInput = sm.interactable.connectionType.logic + sm.interactable.connectionType.electricity
RfsFactory.connectionOutput = sm.interactable.connectionType.none
RfsFactory.colorNormal = sm.color.new( 0xb87333ff )
RfsFactory.colorHighlight = sm.color.new( 0xe0a05aff )
RfsFactory.connectIcon = "electrical"

RfsFactory.ALLY_CAP = 16
RfsFactory.FARMBOT_CAP = 2
RfsFactory.COOLDOWN_TICKS = 80 -- 2 s
RfsFactory.SHAPE_UUID = "2bf5d817-4e96-41f8-c3a5-96e815232c6e"

pcall( function()
	dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsBotHijack.lua" )
end )

local METAL_UUID = sm.uuid.new( "8aedf6c2-94e1-4506-89d4-a0227c552f1e" )
if type( obj_consumable_component ) ~= "nil" then
	METAL_UUID = obj_consumable_component
end
local BATTERY_UUID = sm.uuid.new( "910a7f2c-52b0-46eb-8873-ad13255539af" )
if type( ITEMS ) == "table" and ITEMS.obj_consumable_battery then
	BATTERY_UUID = ITEMS.obj_consumable_battery
elseif type( obj_consumable_battery ) ~= "nil" then
	BATTERY_UUID = obj_consumable_battery
end

local ALLY_COLOR = sm.color.new( "3dff8aff" )
local ALLY_COLOR_HEX = "3dff8a"
local LOGIC = sm.interactable.connectionType.logic
local ELEC = sm.interactable.connectionType.electricity

local TYPES = {
	{
		id = "totebot",
		label = "Tote line",
		unitGlobal = "unit_totebot_green",
		fallback = "8984bdbf-521e-4eed-b3c4-2b5e287eb879",
		metal = 4,
		battery = 2,
	},
	{
		id = "haybot",
		label = "Hay barn",
		unitGlobal = "unit_haybot",
		fallback = "c8bfb8f3-7efc-49ac-875a-eb85ac0614db",
		metal = 8,
		battery = 3,
	},
	{
		id = "tapebot",
		label = "Tape assembly",
		unitGlobal = "unit_tapebot",
		fallback = "04761b4a-a83e-4736-b565-120bc776edb2",
		metal = 6,
		battery = 2,
	},
	{
		id = "farmbot",
		label = "Farm garage",
		unitGlobal = "unit_farmbot",
		fallback = "9f4fde94-312f-4417-b13b-84029c5d6b52",
		metal = 16,
		battery = 8,
		farmbot = true,
	},
}

local function typeAt( index )
	index = tonumber( index ) or 1
	if index < 1 or index > #TYPES then
		index = 1
	end
	return TYPES[index], index
end

local function unitUuidFor( spec )
	if type( spec ) ~= "table" then
		return nil
	end
	local g = rawget( _G, spec.unitGlobal )
	if g ~= nil then
		return g
	end
	local ok, uuid = pcall( sm.uuid.new, spec.fallback )
	if ok then
		return uuid
	end
	return nil
end

local function qtyIn( container, uuid )
	if not container or not sm.exists( container ) or not uuid then
		return 0
	end
	local ok, n = pcall( sm.container.totalQuantity, container, uuid )
	if ok and type( n ) == "number" then
		return n
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

local function wiredContainers( self )
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

local function gatherSpendContainers( self, player )
	local list, seen = {}, {}
	for _, c in ipairs( wiredContainers( self ) ) do
		addContainer( list, seen, c )
	end
	if player then
		pcall( function()
			addContainer( list, seen, player:getInventory() )
		end )
	end
	return list
end

local function totalOf( containers, uuid )
	local n = 0
	for _, c in ipairs( containers ) do
		n = n + qtyIn( c, uuid )
	end
	return n
end

local function spendFrom( containers, uuid, amount )
	amount = math.floor( tonumber( amount ) or 0 )
	if amount <= 0 then
		return true
	end
	local left = amount
	for _, container in ipairs( containers ) do
		if left <= 0 then
			break
		end
		local have = qtyIn( container, uuid )
		if have > 0 then
			local take = math.min( have, left )
			local ok = pcall( sm.container.spend, container, uuid, take, true )
			if ok then
				left = left - take
			end
		end
	end
	return left <= 0
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

local function allyTotals()
	local n, farm = 0, 0
	if type( RfsBotHijack ) == "table" then
		if type( RfsBotHijack.prune ) == "function" then
			pcall( RfsBotHijack.prune )
		end
		if type( RfsBotHijack.count ) == "function" then
			local ok, total = pcall( RfsBotHijack.count )
			if ok and type( total ) == "number" then
				n = total
			end
		end
		for _, info in pairs( RfsBotHijack.allies or {} ) do
			if info and info.controlled then
				local t = string.lower( tostring( info.unitType or info.type or "" ) )
				if info.farmbot or string.find( t, "farmbot", 1, true ) or string.find( t, "9f4fde94", 1, true ) then
					farm = farm + 1
				end
			end
		end
	end
	return n, farm
end

local function playerNear( self, player )
	if not player or not player.character or not sm.exists( player.character ) then
		return false
	end
	if not self.shape or not sm.exists( self.shape ) then
		return false
	end
	local d = 99
	pcall( function()
		d = ( player.character.worldPosition - self.shape.worldPosition ):length()
	end )
	return d <= 8
end

local function tell( self, player, msg )
	msg = tostring( msg or "" )
	if msg == "" then
		return
	end
	if player then
		pcall( function()
			self.network:sendToClient( player, "cl_rfsMsg", msg )
		end )
	else
		pcall( function()
			self.network:sendToClients( "cl_rfsMsg", msg )
		end )
	end
end

local function spawnPosYaw( self )
	local pos = self.shape.worldPosition
	local dir = sm.vec3.new( 0, 1, 0 )
	pcall( function()
		if self.shape.at then
			dir = self.shape.at
		end
	end )
	pcall( function()
		if dir:length() > 0.05 then
			pos = pos + dir:normalize() * 2.5
		end
	end )
	pos = pos + sm.vec3.new( 0, 0, 0.75 )
	local yaw = 0
	pcall( function()
		yaw = math.atan2( dir.y, dir.x )
	end )
	return pos, yaw
end

local function createAllyUnit( uuid, pos, yaw, ownerId, spec )
	local params = {
		playerAlly = true,
		playerAllyMode = "infected",
		playerAllyOwner = ownerId,
		color = ALLY_COLOR,
		allyColor = ALLY_COLOR_HEX,
		tetherPoint = pos,
		rfsUnitType = spec and spec.id or nil,
	}
	local unit = nil
	local ok = pcall( function()
		unit = sm.unit.createUnit( uuid, pos, yaw, params )
	end )
	if not ok or not unit then
		ok = pcall( function()
			unit = sm.unit.createUnit( uuid, pos, yaw )
		end )
	end
	if unit and type( RfsBotHijack ) == "table" then
		local already = false
		if type( RfsBotHijack.isAlly ) == "function" then
			local okAlly, isAlly = pcall( RfsBotHijack.isAlly, unit )
			already = okAlly and isAlly == true
		end
		if ( not already ) and type( RfsBotHijack.convertUnit ) == "function" then
			pcall( RfsBotHijack.convertUnit, unit, ownerId, {
				mode = "infected",
				allyColor = ALLY_COLOR_HEX,
				unitType = spec and spec.id or nil,
			} )
		end
	end
	return unit
end

local function publish( self )
	local spec, idx = typeAt( self.sv and self.sv.typeIndex )
	local n, farm = allyTotals()
	local data = {
		typeIndex = idx,
		label = spec.label,
		metal = spec.metal,
		battery = spec.battery,
		allies = n,
		farmbots = farm,
		cap = RfsFactory.ALLY_CAP,
		farmCap = RfsFactory.FARMBOT_CAP,
		logicOff = not logicAllows( self ),
	}
	pcall( function()
		self.network:setClientData( data )
	end )
	pcall( function()
		self.interactable:setPublicData( data )
	end )
end

function RfsFactory.server_onCreate( self )
	local saved = nil
	pcall( function()
		saved = self.storage:load()
	end )
	if type( saved ) ~= "table" then
		saved = {}
	end
	local _, idx = typeAt( saved.typeIndex )
	self.sv = {
		typeIndex = idx,
		coolUntil = 0,
	}
	self.storage:save( { typeIndex = idx } )
	publish( self )
end

function RfsFactory.server_onFixedUpdate( self )
	if sm.game.getCurrentTick() % 20 == 0 then
		publish( self )
	end
end

function RfsFactory.sv_cycle( self, params, player )
	if player and not playerNear( self, player ) then
		return
	end
	local _, idx = typeAt( ( self.sv and self.sv.typeIndex or 1 ) + 1 )
	self.sv = self.sv or {}
	self.sv.typeIndex = idx
	pcall( function()
		self.storage:save( { typeIndex = idx } )
	end )
	publish( self )
	local spec = typeAt( idx )
	tell( self, player, "Factory: " .. spec.label )
end

function RfsFactory.sv_build( self, params, player )
	if not player or not playerNear( self, player ) then
		return
	end
	if not logicAllows( self ) then
		tell( self, player, "Factory off — turn on the logic switch" )
		return
	end
	local now = sm.game.getCurrentTick()
	self.sv = self.sv or {}
	if now < ( self.sv.coolUntil or 0 ) then
		tell( self, player, "Factory cooling down" )
		return
	end
	local spec, idx = typeAt( self.sv.typeIndex )
	self.sv.typeIndex = idx
	local uuid = unitUuidFor( spec )
	if not uuid then
		tell( self, player, "Factory: unknown unit type" )
		return
	end
	local n, farm = allyTotals()
	if n >= RfsFactory.ALLY_CAP then
		tell( self, player, "Army cap " .. tostring( RfsFactory.ALLY_CAP ) .. " reached" )
		return
	end
	if spec.farmbot and farm >= RfsFactory.FARMBOT_CAP then
		tell( self, player, "Farmbot cap " .. tostring( RfsFactory.FARMBOT_CAP ) .. " reached" )
		return
	end
	local ownerId = nil
	pcall( function()
		ownerId = player.id
	end )
	local containers = gatherSpendContainers( self, player )
	local haveM = totalOf( containers, METAL_UUID )
	local haveB = totalOf( containers, BATTERY_UUID )
	if haveM < spec.metal or haveB < spec.battery then
		tell( self, player, "Need " .. tostring( spec.metal ) .. " Metal + " .. tostring( spec.battery ) .. " Battery (wired chest or inventory)" )
		return
	end
	local pos, yaw = spawnPosYaw( self )
	local unit = createAllyUnit( uuid, pos, yaw, ownerId, spec )
	if not unit then
		tell( self, player, "Factory spawn failed" )
		return
	end
	spendFrom( containers, METAL_UUID, spec.metal )
	spendFrom( containers, BATTERY_UUID, spec.battery )
	self.sv.coolUntil = now + RfsFactory.COOLDOWN_TICKS
	publish( self )
	tell( self, player, "Built ally " .. spec.label .. " (" .. tostring( n + 1 ) .. "/" .. tostring( RfsFactory.ALLY_CAP ) .. ")" )
end

function RfsFactory.cl_rfsMsg( self, msg )
	pcall( function()
		sm.gui.displayAlertText( tostring( msg or "" ), 3 )
	end )
	pcall( function()
		sm.gui.chatMessage( tostring( msg or "" ) )
	end )
end

function RfsFactory.client_onCreate( self )
	self.cl = {
		typeIndex = 1,
		label = "Tote line",
		metal = 4,
		battery = 2,
		allies = 0,
		farmbots = 0,
		cap = RfsFactory.ALLY_CAP,
		farmCap = RfsFactory.FARMBOT_CAP,
		logicOff = false,
	}
end

function RfsFactory.client_onClientDataUpdate( self, data )
	if type( data ) ~= "table" then
		return
	end
	self.cl = self.cl or {}
	self.cl.typeIndex = data.typeIndex or 1
	self.cl.label = data.label or "Tote line"
	self.cl.metal = data.metal or 4
	self.cl.battery = data.battery or 2
	self.cl.allies = data.allies or 0
	self.cl.farmbots = data.farmbots or 0
	self.cl.cap = data.cap or RfsFactory.ALLY_CAP
	self.cl.farmCap = data.farmCap or RfsFactory.FARMBOT_CAP
	self.cl.logicOff = data.logicOff and true or false
end

function RfsFactory.client_canInteract( self )
	local pd = self.cl or {}
	local useKey = "E"
	local tinkKey = "U"
	pcall( function()
		useKey = sm.gui.getKeyBinding( "Use", true ) or useKey
	end )
	pcall( function()
		tinkKey = sm.gui.getKeyBinding( "Tinker", true ) or tinkKey
	end )
	if pd.logicOff then
		sm.gui.setInteractionText( "", useKey, "Factory off — turn on the logic switch" )
		return true
	end
	local capTxt = tostring( pd.allies or 0 ) .. "/" .. tostring( pd.cap or RfsFactory.ALLY_CAP )
	sm.gui.setInteractionText(
		tinkKey,
		"Cycle type",
		useKey,
		"Build " .. tostring( pd.label or "ally" ) .. " (" .. tostring( pd.metal or 0 ) .. " Metal + " .. tostring( pd.battery or 0 ) .. " Battery)  army " .. capTxt
	)
	return true
end

function RfsFactory.client_canTinker( self, character )
	return true
end

function RfsFactory.client_onInteract( self, character, state )
	if not state then
		return
	end
	self.network:sendToServer( "sv_build", {} )
end

function RfsFactory.client_onTinker( self, character, state )
	if not state then
		return
	end
	self.network:sendToServer( "sv_cycle", {} )
end
