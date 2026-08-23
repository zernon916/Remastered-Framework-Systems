-- RfsSolarPanel.lua — placeable solar. Electricity ONLY to Rechargeable Battery Box.
-- Optional logic parent (switch). Always setActive(false). Does not touch Hack spend.

RfsSolarPanel = class( nil )
RfsSolarPanel.maxParentCount = 1
RfsSolarPanel.maxChildCount = 255
-- Logic in only (blocks vanilla BatteryContainer → solar). Elec out; non-box wires severed.
RfsSolarPanel.connectionInput = sm.interactable.connectionType.logic
RfsSolarPanel.connectionOutput = sm.interactable.connectionType.electricity
RfsSolarPanel.colorNormal = sm.color.new( 0x1a6db5ff )
RfsSolarPanel.colorHighlight = sm.color.new( 0x4aa3e6ff )
RfsSolarPanel.connectIcon = "electrical"

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
rfsDofile( "Scripts/game/RfsRecharge.lua" )

local LOGIC = sm.interactable.connectionType.logic
local ELEC = sm.interactable.connectionType.electricity
-- Rechargeable Battery Box only (not vanilla Battery Container da4833fd-…).
local RECHARGE_BOX_UUID = "9c624f8e-b507-414a-cd93-f4081b5c7eaf"

local function band( a, b )
	if type( bit ) == "table" and type( bit.band ) == "function" then
		return bit.band( a, b )
	end
	return a % ( b * 2 ) >= b and b or 0
end

local function uuidStr( u )
	local s = string.lower( tostring( u or "" ) )
	local m = string.match( s, "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x" )
	return m or s
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
	return switches == 0
end

local function rechargeBoxUuid()
	if type( RfsRecharge ) == "table" and type( RfsRecharge.BOX_UUID ) == "string" then
		return string.lower( RfsRecharge.BOX_UUID )
	end
	return RECHARGE_BOX_UUID
end

-- Keep electricity wires only to Rechargeable Battery Box. Cut everything else
-- (vanilla Battery Container, engines, beacons, chem, …) including old saves.
local function severNonRechargeElecLinks( self )
	local ia = self and self.interactable
	if not ia or not sm.exists( ia ) then
		return
	end
	local boxId = rechargeBoxUuid()
	local function checkAndCut( other, solarIsChild )
		if not other or not sm.exists( other ) then
			return
		end
		local id = nil
		pcall( function()
			local shape = other.shape or other:getShape()
			if shape then
				id = uuidStr( shape.uuid )
			end
		end )
		if id == boxId then
			return
		end
		pcall( function()
			if solarIsChild then
				sm.interactable.disconnect( other, ia )
			else
				sm.interactable.disconnect( ia, other )
			end
		end )
		pcall( function()
			if type( ia.disconnect ) == "function" then
				ia:disconnect( other )
			end
		end )
		pcall( function()
			if type( other.disconnect ) == "function" then
				other:disconnect( ia )
			end
		end )
	end
	pcall( function()
		for _, p in ipairs( ia:getParents( ELEC ) or {} ) do
			checkAndCut( p, true )
		end
	end )
	pcall( function()
		for _, c in ipairs( ia:getChildren( ELEC ) or {} ) do
			checkAndCut( c, false )
		end
	end )
end

local function eligibleBoxes( self )
	local list = {}
	if type( RfsRecharge ) ~= "table" or not RfsRecharge.connectedBoxes then
		return list
	end
	for _, ia in ipairs( RfsRecharge.connectedBoxes( self ) or {} ) do
		local has = false
		pcall( function()
			has = RfsRecharge.boxHasCell( ia )
		end )
		if has then
			list[#list + 1] = ia
		end
	end
	return list
end

-- Split whole milli evenly across N boxes (remainder to the first rem boxes).
local function splitMilliToBoxes( boxes, whole )
	local n = #boxes
	if n < 1 or whole < 1 then
		return
	end
	local base = math.floor( whole / n )
	local rem = whole - base * n
	for i = 1, n do
		local add = base
		if i <= rem then
			add = add + 1
		end
		if add > 0 then
			local ia = boxes[i]
			pcall( function()
				RfsRecharge.addMilliOn( ia, add )
			end )
		end
	end
end

local function publish( self )
	local data = {
		on = self.sv.on and true or false,
		rate = self.sv.rate or 0,
		label = self.sv.label or "",
		boxes = self.sv.boxes or 0,
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

function RfsSolarPanel.server_onCreate( self )
	self.sv = { on = false, rate = 0, label = "", boxes = 0, frac = 0 }
	pcall( function()
		self.interactable:setActive( false )
	end )
	severNonRechargeElecLinks( self )
	publish( self )
end

function RfsSolarPanel.server_onFixedUpdate( self )
	if not self.sv then
		return
	end
	-- Cut forbidden elec wires often so Connect-tool flashes do not stick.
	if ( sm.game.getCurrentTick() % 8 ) == 0 then
		severNonRechargeElecLinks( self )
	end
	local on = logicAllows( self )
	local rate, label = 0, "off"
	if on and type( RfsRecharge ) == "table" then
		rate, label = RfsRecharge.chargeRate()
	end
	self.sv.on = on
	self.sv.rate = rate
	self.sv.label = label or ""
	local boxes = 0
	if on and rate > 0 and type( RfsRecharge ) == "table" then
		local milli = RfsRecharge.milliPerTick( rate )
		self.sv.frac = ( self.sv.frac or 0 ) + milli
		local whole = math.floor( self.sv.frac )
		local eligible = eligibleBoxes( self )
		boxes = #eligible
		if whole >= 1 and boxes > 0 then
			self.sv.frac = self.sv.frac - whole
			splitMilliToBoxes( eligible, whole )
		elseif whole >= 1 then
			self.sv.frac = self.sv.frac - whole
		end
	else
		pcall( function()
			boxes = #( RfsRecharge.connectedBoxes( self ) or {} )
		end )
	end
	self.sv.boxes = boxes
	pcall( function()
		self.interactable:setActive( false )
	end )
	if ( sm.game.getCurrentTick() % 20 ) == 0 then
		publish( self )
	end
end

function RfsSolarPanel.client_onCreate( self )
	self.cl = { on = false, rate = 0, label = "", boxes = 0 }
end

function RfsSolarPanel.client_onClientDataUpdate( self, data )
	if type( data ) ~= "table" then
		return
	end
	self.cl = data
end

function RfsSolarPanel.client_canInteract( self )
	local pd = self.cl or {}
	if not pd.on then
		sm.gui.setInteractionText( "", "", "Solar Panel — off (logic) · Rechargeable Battery Box only" )
		return true
	end
	local pct = math.floor( ( tonumber( pd.rate ) or 0 ) * 100 + 0.5 )
	local n = tonumber( pd.boxes ) or 0
	local boxHint = n > 1 and ( " · split ×" .. tostring( n ) ) or ( n < 1 and " · wire Rechargeable Battery Box" or "" )
	sm.gui.setInteractionText(
		"",
		"",
		"Solar Panel — " .. tostring( pct ) .. "% (" .. tostring( pd.label or "" ) .. ")" .. boxHint
	)
	return true
end

function RfsSolarPanel.client_getAvailableParentConnectionCount( self, connectionType )
	if band( connectionType, LOGIC ) ~= 0 then
		local n = 0
		pcall( function()
			n = #( self.interactable:getParents( LOGIC ) or {} )
		end )
		return 1 - n
	end
	-- No electricity parents (blocks vanilla BatteryContainer → solar).
	return 0
end

function RfsSolarPanel.client_getAvailableChildConnectionCount( self, connectionType )
	if band( connectionType, ELEC ) ~= 0 then
		local n = 0
		pcall( function()
			n = #( self.interactable:getChildren( ELEC ) or {} )
		end )
		return 255 - n
	end
	return 0
end

function RfsSolarPanel.sv_e_rfsSkipCharge( self, params )
	local ticks = tonumber( params and params.ticks ) or 0
	if ticks <= 0 or not self.sv then
		return
	end
	if not logicAllows( self ) then
		return
	end
	if type( RfsRecharge ) ~= "table" then
		return
	end
	local rate = 0
	pcall( function()
		rate = select( 1, RfsRecharge.chargeRate() )
	end )
	rate = tonumber( rate ) or 0
	if rate <= 0 then
		return
	end
	local milli = 0
	pcall( function()
		milli = math.floor( RfsRecharge.milliPerTick( rate ) * ticks + 0.5 )
	end )
	if milli < 1 then
		return
	end
	local eligible = eligibleBoxes( self )
	if #eligible < 1 then
		return
	end
	self.sv.splitIdx = nil
	splitMilliToBoxes( eligible, milli )
end

print( "[RFS] RfsSolarPanel loaded (elec → Rechargeable Battery Box only; split charge)" )
