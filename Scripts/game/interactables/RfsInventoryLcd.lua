-- RfsInventoryLcd.lua — chest inventory readout (not a computer).
-- Face shows item name + count. Small = one stack (ITEM / xAMT). L/XL list more
-- rows and scroll when the chest has extra stacks.
-- Bind (first match): logic child/parent with a container, else welded/adjacent
-- chest on the same creation. Optional logic switch hides the face.
-- LCD logic output stays inactive so wiring LCD→chest does not trigger loot vacuum.
-- Does not touch Orders / MiniMap / Hideout / factory UUID / text Digital Signs.

RfsInventoryLcd = class( nil )
RfsInventoryLcd.maxParentCount = 255
RfsInventoryLcd.maxChildCount = 255
RfsInventoryLcd.connectionInput = sm.interactable.connectionType.logic
RfsInventoryLcd.connectionOutput = sm.interactable.connectionType.logic
RfsInventoryLcd.colorNormal = sm.color.new( 0x1aad9aff )
RfsInventoryLcd.colorHighlight = sm.color.new( 0x4ad4c4ff )
RfsInventoryLcd.connectIcon = "logic"

local LOGIC = sm.interactable.connectionType.logic
local NIL_UUID = "00000000-0000-0000-0000-000000000000"
local ADJACENT = 3.6
local SCAN_TICKS = 8
local DEFAULT_SCROLL = 80

local CHEST_FALLBACK = {
	obj_container_chest = "ad35f7e6-af8f-40fa-aef4-77d827ac8a8a",
	obj_container_smallchest = "fcfae5e2-1df9-47d8-bb9a-30bec9b5b1f5",
	obj_container_tinychest = "7527cf2e-1705-4214-9d07-3dc374957e25",
	obj_container_XXL_chest = "9601f2ca-9552-48b0-afc1-b0f200461114",
}

local chestSet = nil
local nameCache = {}

local function band( a, b )
	if type( bit ) == "table" and type( bit.band ) == "function" then
		return bit.band( a, b )
	end
	return a
end

local function uuidStr( u )
	if u == nil then
		return nil
	end
	return string.lower( tostring( u ) )
end

local function isNilUuid( u )
	local s = uuidStr( u )
	return ( not s ) or s == "" or s == NIL_UUID
end

local function rebuildChestSet()
	chestSet = {}
	for name, fallback in pairs( CHEST_FALLBACK ) do
		local g = _G[name]
		if g ~= nil then
			chestSet[uuidStr( g )] = true
		end
		chestSet[string.lower( fallback )] = true
	end
end

local function isKnownChest( shape )
	if not chestSet then
		rebuildChestSet()
	end
	if not shape or not sm.exists( shape ) then
		return false
	end
	local uid = nil
	pcall( function()
		uid = shape.uuid or shape:getShapeUuid()
	end )
	return uid and chestSet[uuidStr( uid )] and true or false
end

local function containerOf( ia )
	if not ia or not sm.exists( ia ) then
		return nil
	end
	for _, idx in ipairs( { 0, 1 } ) do
		local ok, c = pcall( function()
			return ia:getContainer( idx )
		end )
		if ok and c and sm.exists( c ) then
			return c
		end
	end
	return nil
end

local function shapeOf( ia )
	if not ia then
		return nil
	end
	local shape = nil
	pcall( function()
		shape = ia.shape or ia:getShape()
	end )
	if shape and sm.exists( shape ) then
		return shape
	end
	return nil
end

local function nodePos( ia, fallback )
	local shape = shapeOf( ia )
	if shape then
		local ok, pos = pcall( function()
			return shape.worldPosition
		end )
		if ok and pos then
			return pos
		end
	end
	return fallback
end

local function prettyName( uuid )
	local key = uuidStr( uuid ) or ""
	if nameCache[key] then
		return nameCache[key]
	end
	local n = nil
	pcall( function()
		n = sm.shape.getShapeTitle( uuid )
	end )
	if type( n ) ~= "string" or n == "" then
		n = "Item"
	elseif string.sub( n, 1, 2 ) == "#{" then
		local inner = n:match( "%{(.+)%}" ) or n
		inner = inner:gsub( "^INVENTORY_", "" ):gsub( "^ITEM_", "" ):gsub( "_", " " )
		n = inner:gsub( "(%a)([%w]*)", function( a, rest )
			return string.upper( a ) .. string.lower( rest )
		end )
	end
	nameCache[key] = n
	return n
end

local function clip( text, maxChars )
	text = tostring( text or "" )
	maxChars = tonumber( maxChars ) or 18
	if #text <= maxChars then
		return text
	end
	return string.sub( text, 1, maxChars )
end

local function snapshot( container )
	local byUuid, order = {}, {}
	if not container or not sm.exists( container ) then
		return order
	end
	local size = 0
	pcall( function()
		size = container:getSize() or 0
	end )
	for i = 0, size - 1 do
		local item = nil
		pcall( function()
			item = container:getItem( i )
		end )
		if type( item ) == "table" and item.uuid and not isNilUuid( item.uuid ) then
			local qty = tonumber( item.quantity ) or 0
			if qty > 0 then
				local k = uuidStr( item.uuid )
				if k then
					if not byUuid[k] then
						byUuid[k] = { uuid = item.uuid, qty = 0, name = prettyName( item.uuid ) }
						order[#order + 1] = byUuid[k]
					end
					byUuid[k].qty = byUuid[k].qty + qty
				end
			end
		end
	end
	table.sort( order, function( a, b )
		if a.qty ~= b.qty then
			return a.qty > b.qty
		end
		return tostring( a.name ) < tostring( b.name )
	end )
	return order
end

local function gatherNodes( self )
	local nodes = {}
	pcall( function()
		for _, c in ipairs( self.interactable:getChildren() or {} ) do
			nodes[#nodes + 1] = c
		end
	end )
	pcall( function()
		for _, p in ipairs( self.interactable:getParents() or {} ) do
			nodes[#nodes + 1] = p
		end
	end )
	return nodes
end

local function logicSwitchOn( self )
	local parents = {}
	pcall( function()
		parents = self.interactable:getParents( LOGIC ) or {}
	end )
	local switches = 0
	for _, p in ipairs( parents ) do
		if p and sm.exists( p ) then
			-- Container parents are binds, not display switches.
			if not containerOf( p ) then
				local isLogic = false
				pcall( function()
					isLogic = p:hasOutputType( LOGIC )
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
	end
	return switches == 0
end

local function scoreCandidate( ia, myPos, myShape )
	local shape = shapeOf( ia )
	if shape and myShape and shape == myShape then
		return nil
	end
	local container = containerOf( ia )
	if not container then
		return nil
	end
	local dist = 99
	local pos = nodePos( ia, myPos )
	if pos and myPos then
		pcall( function()
			dist = ( pos - myPos ):length()
		end )
	end
	local bonus = 0
	if isKnownChest( shape ) then
		bonus = -20
	else
		local sz = 0
		pcall( function()
			sz = container:getSize() or 0
		end )
		if sz < 4 then
			bonus = 8
		end
	end
	return bonus + dist, container, shape
end

local function creationShapes( self )
	local shapes = {}
	pcall( function()
		shapes = self.shape:getBody():getCreationShapes() or {}
	end )
	if type( shapes ) ~= "table" or #shapes == 0 then
		pcall( function()
			shapes = self.shape:getBody():getShapes() or {}
		end )
	end
	return shapes
end

local function findBound( self )
	local myShape = self.shape
	local myPos = nil
	pcall( function()
		myPos = myShape.worldPosition
	end )
	local bestScore, bestContainer = nil, nil

	local function consider( ia )
		local score, container = scoreCandidate( ia, myPos, myShape )
		if score and container and ( not bestScore or score < bestScore ) then
			bestScore = score
			bestContainer = container
		end
	end

	for _, ia in ipairs( gatherNodes( self ) ) do
		consider( ia )
	end
	if bestContainer then
		return bestContainer, "wire"
	end

	for _, shape in ipairs( creationShapes( self ) ) do
		if shape and sm.exists( shape ) and shape ~= myShape then
			local dist = 99
			pcall( function()
				if myPos and shape.worldPosition then
					dist = ( shape.worldPosition - myPos ):length()
				end
			end )
			if dist <= ADJACENT then
				local ia = nil
				pcall( function()
					ia = shape.interactable or shape:getInteractable()
				end )
				consider( ia )
			end
		end
	end
	if bestContainer then
		return bestContainer, "weld"
	end
	return nil, nil
end

local function cfg( self )
	local d = self.data or {}
	return {
		lines = math.max( 1, tonumber( d.lines ) or 2 ),
		maxChars = tonumber( d.maxChars ) or 16,
		instruction = d.instructionStyle and true or false,
		scrollTicks = tonumber( d.scrollTicks ) or DEFAULT_SCROLL,
		effectName = d.effectName or "Textsign - Text",
		maxTextWidth = tonumber( d.maxTextWidth ) or 88,
		oversizeScale = tonumber( d.oversizeScale ) or 0.625,
		offsetZ = ( d.offsetPosition and tonumber( d.offsetPosition.z ) ) or 0.1517,
		offsetY = ( d.offsetPosition and tonumber( d.offsetPosition.y ) ) or 0.025,
		scale = d.scale or { x = 1.2, y = 1.2, z = 1.2 },
		asg = d.asg or { a = 0.0, s = 0.0, g = 0.9 },
		lineSpacing = tonumber( d.lineSpacing ) or 0.18,
	}
end

local function visibleLines( items, offset, spec )
	local out = {}
	if spec.instruction then
		if #items < 1 then
			return { "EMPTY", "" }
		end
		local idx = ( ( offset or 0 ) % #items ) + 1
		local it = items[idx]
		out[1] = clip( it.name, spec.maxChars )
		out[2] = clip( "x" .. tostring( it.qty ), spec.maxChars )
		return out
	end
	local n = spec.lines
	if #items < 1 then
		out[1] = "EMPTY"
		for i = 2, n do
			out[i] = ""
		end
		return out
	end
	local start = ( offset or 0 ) % #items
	for i = 1, n do
		local it = items[( ( start + i - 1 ) % #items ) + 1]
		if it then
			out[i] = clip( tostring( it.qty ) .. "x " .. it.name, spec.maxChars )
		else
			out[i] = ""
		end
	end
	-- Do not wrap-repeat when everything already fits.
	if #items <= n then
		for i = #items + 1, n do
			out[i] = ""
		end
	end
	return out
end

local function publish( self )
	if not self.sv then
		return
	end
	local data = {
		logicOn = self.sv.logicOn and true or false,
		bound = self.sv.bound and true or false,
		how = self.sv.how or "",
		total = self.sv.total or 0,
		lines = self.sv.lines or { "NO CHEST" },
	}
	local key = tostring( data.logicOn ) .. "|" .. tostring( data.bound ) .. "|" .. tostring( data.total ) .. "|" .. table.concat( data.lines, "\n" )
	if key == self.sv.lastKey then
		return
	end
	self.sv.lastKey = key
	pcall( function()
		self.network:setClientData( data )
	end )
	pcall( function()
		self.interactable:setActive( false )
	end )
end

function RfsInventoryLcd.server_onCreate( self )
	self.sv = {
		logicOn = true,
		bound = false,
		how = "",
		total = 0,
		lines = { "NO CHEST" },
		offset = 0,
		tick = 0,
		scroll = 0,
		lastKey = nil,
	}
	self.sv.logicOn = logicSwitchOn( self )
	publish( self )
end

function RfsInventoryLcd.server_onFixedUpdate( self )
	if not self.sv then
		return
	end
	pcall( function()
		self.interactable:setActive( false )
	end )
	self.sv.tick = ( self.sv.tick or 0 ) + 1
	self.sv.scroll = ( self.sv.scroll or 0 ) + 1
	local spec = cfg( self )
	local on = logicSwitchOn( self )
	if self.sv.tick % SCAN_TICKS ~= 0 and on == self.sv.logicOn then
		return
	end
	self.sv.logicOn = on
	local container, how = findBound( self )
	local items = snapshot( container )
	self.sv.bound = container ~= nil
	self.sv.how = how or ""
	self.sv.total = #items
	local window = spec.instruction and 1 or spec.lines
	if #items > window then
		if ( self.sv.scroll or 0 ) >= spec.scrollTicks then
			self.sv.scroll = 0
			self.sv.offset = ( self.sv.offset or 0 ) + 1
		end
	else
		self.sv.offset = 0
		self.sv.scroll = 0
	end
	if not on then
		local blank = {}
		for i = 1, spec.lines do
			blank[i] = ""
		end
		self.sv.lines = blank
	elseif not self.sv.bound then
		local miss = { "NO CHEST" }
		for i = 2, spec.lines do
			miss[i] = ""
		end
		self.sv.lines = miss
	else
		self.sv.lines = visibleLines( items, self.sv.offset, spec )
	end
	publish( self )
end

function RfsInventoryLcd.client_onCreate( self )
	self.cl = {
		logicOn = true,
		bound = false,
		how = "",
		total = 0,
		lines = { "NO CHEST" },
		effects = {},
	}
	local spec = cfg( self )
	local n = spec.lines
	local spacing = spec.lineSpacing
	if n >= 4 then
		spacing = spacing * 0.78
	end
	local scaleMul = 1.0
	if n >= 4 then
		scaleMul = 0.62
	elseif n >= 3 then
		scaleMul = 0.72
	elseif n >= 2 then
		scaleMul = 0.82
	end
	local scale = sm.vec3.new( spec.scale.x * scaleMul, spec.scale.y * scaleMul, spec.scale.z * scaleMul )
	local asg = sm.vec3.new( spec.asg.a, spec.asg.s, spec.asg.g )
	for i = 1, n do
		local fx = nil
		pcall( function()
			fx = sm.effect.createEffect( spec.effectName, self.interactable )
		end )
		if fx then
			local yOff = spec.offsetY + ( ( n - 1 ) * spacing * 0.5 ) - ( ( i - 1 ) * spacing )
			pcall( function()
				fx:setOffsetPosition( sm.vec3.new( 0, yOff, spec.offsetZ ) )
				fx:setScale( scale )
				fx:setParameter( "ASG", asg )
				fx:start()
			end )
			self.cl.effects[i] = fx
		end
	end
	self.cl.scale = scale
	self:cl_updateLook()
end

function RfsInventoryLcd.client_onClientDataUpdate( self, data )
	self.cl = self.cl or { effects = {} }
	if type( data ) == "table" then
		self.cl.logicOn = data.logicOn and true or false
		self.cl.bound = data.bound and true or false
		self.cl.how = data.how or ""
		self.cl.total = tonumber( data.total ) or 0
		self.cl.lines = data.lines or { "NO CHEST" }
	end
	self:cl_updateLook()
end

function RfsInventoryLcd.cl_updateLook( self )
	if not self.cl or type( self.cl.effects ) ~= "table" then
		return
	end
	local lines = self.cl.lines or {}
	local col = nil
	pcall( function()
		col = self.shape.color
	end )
	for i, fx in ipairs( self.cl.effects ) do
		if fx then
			pcall( function()
				fx:stop()
				if col then
					fx:setParameter( "Color", col )
				end
				fx:setParameter( "TextContent", lines[i] or "" )
				fx:start()
			end )
		end
	end
	self.cl.currentColor = col
end

function RfsInventoryLcd.client_onFixedUpdate( self )
	if not self.cl then
		return
	end
	local col = nil
	pcall( function()
		col = self.shape.color
	end )
	if col and col ~= self.cl.currentColor then
		self:cl_updateLook()
	end
end

function RfsInventoryLcd.client_onDestroy( self )
	if self.cl and type( self.cl.effects ) == "table" then
		for _, fx in ipairs( self.cl.effects ) do
			if fx then
				pcall( function()
					fx:stop()
					fx:destroy()
				end )
			end
		end
	end
end

function RfsInventoryLcd.client_getAvailableParentConnectionCount( self, connectionType )
	if band( connectionType, LOGIC ) ~= 0 then
		local n = 0
		pcall( function()
			n = #( self.interactable:getParents( LOGIC ) or {} )
		end )
		return math.max( 0, ( self.maxParentCount or 255 ) - n )
	end
	return 0
end

function RfsInventoryLcd.client_getAvailableChildConnectionCount( self, connectionType )
	if band( connectionType, LOGIC ) ~= 0 then
		local n = 0
		pcall( function()
			n = #( self.interactable:getChildren( LOGIC ) or {} )
		end )
		return math.max( 0, ( self.maxChildCount or 255 ) - n )
	end
	return 0
end

function RfsInventoryLcd.client_canInteract( self )
	local cl = self.cl or {}
	if cl.logicOn == false then
		sm.gui.setInteractionText( "", "", "Inventory LCD  (logic off — hidden)" )
	elseif not cl.bound then
		sm.gui.setInteractionText( "", "", "Inventory LCD  — weld to a chest or connect LCD → chest" )
	elseif ( cl.total or 0 ) < 1 then
		sm.gui.setInteractionText( "", "", "Inventory LCD  — chest empty" )
	else
		local how = cl.how == "wire" and "wired" or "welded"
		local extra = ( cl.total or 0 ) > 1 and ( "  " .. tostring( cl.total ) .. " stacks" ) or ""
		sm.gui.setInteractionText( "", "", "Inventory LCD  (" .. how .. extra .. ")" )
	end
	return true
end

print( "[RFS] RfsInventoryLcd loaded" )
