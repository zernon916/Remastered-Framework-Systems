-- RfsSolarPanel.lua — placeable solar. Charges connected rechargeable boxes only.
-- Electricity cable like beacons (parents/children). Not a weld scan.
-- Always setActive(false). Does not touch Hack spend.

RfsSolarPanel = class( nil )
RfsSolarPanel.maxParentCount = 255
RfsSolarPanel.maxChildCount = 255
RfsSolarPanel.connectionInput = sm.interactable.connectionType.logic + sm.interactable.connectionType.electricity
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

local function band( a, b )
	if type( bit ) == "table" and type( bit.band ) == "function" then
		return bit.band( a, b )
	end
	return a % ( b * 2 ) >= b and b or 0
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
	publish( self )
end

function RfsSolarPanel.server_onFixedUpdate( self )
	if not self.sv then
		return
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
		if whole >= 1 then
			self.sv.frac = self.sv.frac - whole
			for _, ia in ipairs( RfsRecharge.connectedBoxes( self ) ) do
				local has = false
				pcall( function()
					has = RfsRecharge.boxHasCell( ia )
				end )
				if has then
					boxes = boxes + 1
					RfsRecharge.addMilliOn( ia, whole )
				end
			end
		else
			pcall( function()
				boxes = #( RfsRecharge.connectedBoxes( self ) or {} )
			end )
		end
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
		sm.gui.setInteractionText( "", "", "Solar Panel — off (logic)" )
		return true
	end
	local pct = math.floor( ( tonumber( pd.rate ) or 0 ) * 100 + 0.5 )
	sm.gui.setInteractionText(
		"",
		"",
		"Solar Panel — " .. tostring( pct ) .. "% (" .. tostring( pd.label or "" ) .. ")"
	)
	return true
end

function RfsSolarPanel.client_getAvailableParentConnectionCount( self, connectionType )
	if band( connectionType, ELEC ) ~= 0 then
		local n = 0
		pcall( function()
			n = #( self.interactable:getParents( ELEC ) or {} )
		end )
		return 255 - n
	end
	if band( connectionType, LOGIC ) ~= 0 then
		local n = 0
		pcall( function()
			n = #( self.interactable:getParents( LOGIC ) or {} )
		end )
		return 1 - n
	end
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
	for _, ia in ipairs( RfsRecharge.connectedBoxes( self ) ) do
		local has = false
		pcall( function()
			has = RfsRecharge.boxHasCell( ia )
		end )
		if has then
			RfsRecharge.addMilliOn( ia, milli )
		end
	end
end

print( "[RFS] RfsSolarPanel loaded" )
