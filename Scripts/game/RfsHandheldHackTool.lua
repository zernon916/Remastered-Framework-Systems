-- RfsHandheldHackTool.lua — player handheld military radio (chance hack, Follow/Defend).
-- VOLATILE. Not the Hack Beacon station core. Mesh: R&S Military radio (DTry, CC-BY-4.0).

RfsHandheldHackTool = class()

local LAYOUT = "$CONTENT_DATA/Gui/Layouts/Rfs_HandheldHack.layout"
local LOOK = 8
local HELD_REND = "$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247/Tools/radio_handheld_preview.rend"

local function applyHeldRenderables( self )
	if not self.tool then
		return
	end
	local list = { HELD_REND }
	pcall( function() self.tool:setTpRenderables( list ) end )
	pcall( function() self.tool:setFpRenderables( list ) end )
end

local function holdingThisTool()
	local item = nil
	pcall( function()
		item = sm.localPlayer.getActiveItem()
	end )
	local s = tostring( item or "" )
	if type( RfsHandheldHack ) == "table" and RfsHandheldHack.toolUuid then
		return string.find( s, RfsHandheldHack.toolUuid(), 1, true ) ~= nil
	end
	return string.find( s, "e8f4a2b1-3c7d-4e9f-8a2b-1d5e6f7a8b9c", 1, true ) ~= nil
end

local function raycastBot()
	local hit, result = false, nil
	pcall( function()
		hit, result = sm.localPlayer.getRaycast( LOOK )
	end )
	if not hit or type( result ) ~= "table" or result.type ~= "Character" or not result.character then
		return nil
	end
	local char = result.character
	local isBot = false
	pcall( function()
		isBot = char and not char:isPlayer()
	end )
	if not isBot then
		return nil
	end
	if type( RfsBotHijack ) == "table" and RfsBotHijack.isAlly and char:getUnit() then
		if RfsBotHijack.isAlly( char:getUnit() ) then
			return char, true
		end
	end
	return char, false
end

function RfsHandheldHackTool.client_onEquippedUpdate( self, primaryState, secondaryState )
	return false, false
end
if false then
	local char, isAlly = raycastBot()
	if char then
		pcall( function()
			if isAlly then
				sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "Commands — handheld bot" )
			else
				sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "Hack bot (40% chance)" )
			end
		end )
	end
	if primaryState and char then
		local unit = nil
		pcall( function()
			unit = char:getUnit()
		end )
		if unit then
			if isAlly then
				local game = _G.g_rfsGame
				local key = tostring( unit.id )
				local info = type( RfsBotHijack ) == "table" and RfsBotHijack.allies and RfsBotHijack.allies[key]
				if info and info.mode == "handheld" and game and type( game.cl_rfs_handheldOpen ) == "function" then
					pcall( function()
						game:cl_rfs_handheldOpen( { unitKey = key } )
					end )
				elseif game and type( game.cl_rfs_botActionOpen ) == "function" then
					pcall( function()
						game:cl_rfs_botActionOpen( { unitKey = key, title = "BOT" } )
					end )
				end
			else
				if self.network then
					self.network:sendToServer( "sv_rfs_handheldTryOpen", {
						unitKey = tostring( unit.id ),
						player = sm.localPlayer.getPlayer(),
					} )
				end
			end
		end
		return true, false
	end
	return false, false
end

function RfsHandheldHackTool.client_onCreate( self )
	applyHeldRenderables( self )
end

function RfsHandheldHackTool.client_onEquip( self )
	applyHeldRenderables( self )
end

function RfsHandheldHackTool.server_onCreate( self )
	self.sv = self.sv or {}
end

function RfsHandheldHackTool.sv_rfs_handheldTryOpen( self, params, player )
	return
end
if false then
	local unit = nil
	pcall( function()
		if type( RfsBotHijack ) == "table" and RfsBotHijack.unitByKey then
			unit = RfsBotHijack.unitByKey( tostring( params.unitKey ) )
		end
	end )
	if not unit or not sm.exists( unit ) then
		return
	end
	if type( RfsHandheldHack ) == "table" and not RfsHandheldHack.inRange( unit, player ) then
		return
	end
	self.network:sendToClient( player, "cl_rfs_handheldOpen", {
		unitKey = tostring( params.unitKey ),
	} )
end

print( "[RFS] RfsHandheldHackTool loaded (8m 40% Follow/Defend)" )
