-- RfsDigitalSign.lua — Phase 7 Digital Signs (documented minimum).
-- Logic-connectable signs that actually show information.
-- Subclasses Survival DigitalSign so E still opens the vanilla text GUI
-- and the face uses the Survival "Textsign - Text" effect.
-- Optional logic parent: no switch = always on; wired switch hides text when off.
-- Does not touch Orders / hijack / MiniMap / Hideout.

dofile( "$SURVIVAL_DATA/Scripts/game/interactables/DigitalSign.lua" )

RfsDigitalSign = class( DigitalSign )
RfsDigitalSign.maxParentCount = 255
RfsDigitalSign.maxChildCount = 255
RfsDigitalSign.connectionInput = sm.interactable.connectionType.logic
RfsDigitalSign.connectionOutput = sm.interactable.connectionType.logic
RfsDigitalSign.colorNormal = sm.color.new( 0xdf7f01ff )
RfsDigitalSign.colorHighlight = sm.color.new( 0xffb347ff )
RfsDigitalSign.connectIcon = "logic"

local LOGIC = sm.interactable.connectionType.logic

local function band( a, b )
	if type( bit ) == "table" and type( bit.band ) == "function" then
		return bit.band( a, b )
	end
	return a
end

-- Same convention as Area Loader / Hack Beacon: no logic parent = on;
-- any active logic parent = on; only inactive logic parents = off.
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
	if not self.sv then
		return
	end
	local saved = self.sv.saved or { selected = 1, text = "" }
	local on = self.sv.logicOn and true or false
	local data = {
		selected = saved.selected or 1,
		text = saved.text or "",
		logicOn = on,
	}
	pcall( function()
		self.network:setClientData( data )
	end )
	pcall( function()
		self.interactable:setPublicData( data )
	end )
	pcall( function()
		self.interactable:setActive( on )
	end )
end

function RfsDigitalSign.server_onCreate( self )
	DigitalSign.server_onCreate( self )
	self.sv.logicOn = logicAllows( self )
	publish( self )
end

function RfsDigitalSign.server_onFixedUpdate( self )
	if not self.sv then
		return
	end
	local on = logicAllows( self )
	if on ~= self.sv.logicOn then
		self.sv.logicOn = on
		publish( self )
	end
end

function RfsDigitalSign.sv_n_changeState( self, state )
	DigitalSign.sv_n_changeState( self, state )
	self.sv.logicOn = logicAllows( self )
	publish( self )
end

function RfsDigitalSign.client_onCreate( self )
	DigitalSign.client_onCreate( self )
	self.cl.logicOn = true
end

function RfsDigitalSign.client_onClientDataUpdate( self, data )
	self.cl = self.cl or {}
	if type( data ) == "table" and data.logicOn ~= nil then
		self.cl.logicOn = data.logicOn and true or false
	elseif self.cl.logicOn == nil then
		self.cl.logicOn = true
	end
	DigitalSign.client_onClientDataUpdate( self, data )
end

function RfsDigitalSign.cl_updateLook( self )
	if not self.cl then
		return
	end
	local st = self.cl.state
	local savedText = st and st.text
	if self.cl.logicOn == false and st then
		st.text = ""
	end
	DigitalSign.cl_updateLook( self )
	if st and savedText ~= nil then
		st.text = savedText
	end
end

function RfsDigitalSign.client_getAvailableParentConnectionCount( self, connectionType )
	if band( connectionType, LOGIC ) ~= 0 then
		local n = 0
		pcall( function()
			n = #( self.interactable:getParents( LOGIC ) or {} )
		end )
		return math.max( 0, ( self.maxParentCount or 255 ) - n )
	end
	return 0
end

function RfsDigitalSign.client_canInteract( self )
	local key = ""
	pcall( function()
		key = sm.gui.getKeyBinding( "Use", true )
	end )
	local text = ""
	if self.cl and self.cl.state then
		text = tostring( self.cl.state.text or "" )
	end
	if self.cl and self.cl.logicOn == false then
		sm.gui.setInteractionText( "", key, "Edit Digital Sign  (logic off — hidden)" )
	elseif text ~= "" then
		sm.gui.setInteractionText( "", key, "Edit Digital Sign  \"" .. text .. "\"" )
	else
		sm.gui.setInteractionText( "", key, "Edit Digital Sign  (optional logic switch)" )
	end
	return true
end
