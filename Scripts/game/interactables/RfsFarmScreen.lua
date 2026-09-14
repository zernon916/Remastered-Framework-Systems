-- RfsFarmScreen.lua — Extra Large LCD face shows nearest farm avg times.
-- VOLATILE. Face text is client-scanned (needs local grow timers). E opens tablet GUI.

RfsFarmScreen = class( nil )
RfsFarmScreen.maxParentCount = 1
RfsFarmScreen.maxChildCount = 0
RfsFarmScreen.connectionInput = sm.interactable.connectionType.logic
RfsFarmScreen.connectionOutput = sm.interactable.connectionType.none
RfsFarmScreen.colorNormal = sm.color.new( 0x4caf50ff )
RfsFarmScreen.colorHighlight = sm.color.new( 0x81c784ff )
RfsFarmScreen.connectIcon = "logic"

local SCAN_TICKS = 40
local LINES = 4

local function logicAllows( self )
	local parents = nil
	pcall( function()
		parents = self.interactable:getParents()
	end )
	if type( parents ) ~= "table" or #parents == 0 then
		return true
	end
	for _, p in ipairs( parents ) do
		local active = false
		pcall( function() active = p:isActive() end )
		if active then
			return true
		end
	end
	return false
end

local function screenPos( self )
	local pos = nil
	pcall( function()
		pos = self.shape.worldPosition
	end )
	return pos
end

local function screenWorld( self )
	local world = nil
	pcall( function()
		world = self.shape:getBody():getWorld()
	end )
	if not world then
		pcall( function()
			world = self.shape:getWorld()
		end )
	end
	return world
end

function RfsFarmScreen.server_onCreate( self )
	self.sv = {}
	-- Logic gate only — face times are client-side (grow timers live on client).
	pcall( function()
		self.network:setClientData( { logicOn = true } )
	end )
end

function RfsFarmScreen.server_onFixedUpdate( self )
	local on = logicAllows( self )
	self.sv = self.sv or {}
	if self.sv.lastLogic == on then
		return
	end
	self.sv.lastLogic = on
	pcall( function()
		self.network:setClientData( { logicOn = on and true or false } )
	end )
end

function RfsFarmScreen.client_onCreate( self )
	self.cl = {
		logicOn = true,
		lines = { "FARM", "SCREEN", "", "" },
		effects = {},
	}
	local spacing = 0.14 * 0.78
	local scale = sm.vec3.new( 1.2 * 0.62, 1.2 * 0.62, 1.2 * 0.62 )
	local asg = sm.vec3.new( 0.0, 0.0, 0.9 )
	local offsetZ = 0.1517
	local offsetY = 0.025
	for i = 1, LINES do
		local fx = nil
		pcall( function()
			fx = sm.effect.createEffect( "Textsign - Text", self.interactable )
		end )
		if fx then
			local yOff = offsetY + ( ( LINES - 1 ) * spacing * 0.5 ) - ( ( i - 1 ) * spacing )
			pcall( function()
				fx:setOffsetPosition( sm.vec3.new( 0, yOff, offsetZ ) )
				fx:setScale( scale )
				fx:setParameter( "ASG", asg )
				fx:start()
			end )
			self.cl.effects[i] = fx
		end
	end
	self:cl_updateLook()
end

function RfsFarmScreen.client_onClientDataUpdate( self, data )
	self.cl = self.cl or { effects = {} }
	if type( data ) == "table" and data.logicOn ~= nil then
		self.cl.logicOn = data.logicOn and true or false
	end
	self:cl_updateLook()
end

function RfsFarmScreen.cl_updateLook( self )
	if not self.cl or type( self.cl.effects ) ~= "table" then
		return
	end
	local lines = self.cl.lines or {}
	if self.cl.logicOn == false then
		lines = { "LOGIC", "OFF", "", "" }
	end
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
end

function RfsFarmScreen.client_onDestroy( self )
	if self.cl and type( self.cl.effects ) == "table" then
		for _, fx in ipairs( self.cl.effects ) do
			pcall( function()
				fx:stop()
				fx:destroy()
			end )
		end
	end
end

function RfsFarmScreen.client_canInteract( self )
	if self.cl and self.cl.logicOn == false then
		sm.gui.setInteractionText( "", "", "Farm Screen  (logic off)" )
		return true
	end
	sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "Farm Screen — open tablet" )
	return true
end

function RfsFarmScreen.client_onInteract( self, character, state )
	if state ~= true then
		return
	end
	if self.cl and self.cl.logicOn == false then
		return
	end
	local game = _G.g_rfsGame
	if game and game.network then
		game.cl = game.cl or {}
		game.cl.rfsFarmTabletWantOpen = { source = "screen" }
		pcall( function()
			game.network:sendToServer( "sv_rfs_farmTabletRequestOpen", {} )
		end )
	elseif type( RfsFarmTabletGui ) == "table" and RfsFarmTabletGui.open then
		RfsFarmTabletGui.open( nil, {} )
	end
end

function RfsFarmScreen.client_onFixedUpdate( self )
	if not self.cl then
		return
	end
	if self.cl.logicOn == false then
		self:cl_updateLook()
		return
	end
	local tick = 0
	pcall( function() tick = sm.game.getCurrentTick() end )
	if ( tick % SCAN_TICKS ) ~= 0 then
		return
	end
	local pos = screenPos( self )
	local world = screenWorld( self )
	local lines = { "NO FARM", "IN RANGE", "", "" }
	pcall( function()
		if type( RfsFarmTablet ) == "table" and RfsFarmTablet.nearestFarmFaceLines then
			lines = RfsFarmTablet.nearestFarmFaceLines( pos, world, nil, LINES ) or lines
		end
	end )
	self.cl.lines = lines
	self:cl_updateLook()
end

print( "[RFS] RfsFarmScreen loaded" )
