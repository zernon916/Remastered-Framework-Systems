-- RfsFarmTabletTool.lua — handheld Farmers Tablet.
-- Open path mirrors Recipe Viewer exactly, plus server→client open (reliable).

RfsFarmTabletTool = class()

local TOOL_UUID = "b7c8d9e0-1f2a-4b3c-8d5e-6f7a8b9c0d1e"
local RFS_LID = "29c99287-1213-48c7-9471-19a4a5c12247"
local LCD_TOOL_PREVIEW = "$CONTENT_" .. RFS_LID .. "/Objects/Renderable/rfs_lcd_tool_drop.rend"

local function applyHeldRenderables( self )
	if not self.tool then
		return
	end
	local list = { LCD_TOOL_PREVIEW }
	pcall( function() self.tool:setTpRenderables( list ) end )
	pcall( function() self.tool:setFpRenderables( list ) end )
end

local function holdingThisTool()
	local item = nil
	pcall( function()
		item = sm.localPlayer.getActiveItem()
	end )
	return string.find( string.lower( tostring( item or "" ) ), TOOL_UUID, 1, true ) ~= nil
end

function RfsFarmTabletTool.client_onCreate( self )
	applyHeldRenderables( self )
end

function RfsFarmTabletTool.client_onEquip( self )
	applyHeldRenderables( self )
end

function RfsFarmTabletTool.server_onCreate( self )
end

function RfsFarmTabletTool.client_onEquippedUpdate( self, primaryState, secondaryState )
	if not holdingThisTool() then
		return false, false
	end
	pcall( function()
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Create", true ), "Farmers Tablet" )
	end )
	-- Same gate as Recipe Viewer (primaryState 1 / true). Also accept interactState.start.
	local start = nil
	pcall( function() start = sm.tool.interactState.start end )
	local pressed = ( primaryState == 1 ) or ( primaryState == true )
		or ( start ~= nil and primaryState == start )
	if pressed then
		local game = _G.g_rfsGame
		if game then
			game.cl = game.cl or {}
			game.cl.rfsFarmTabletWantOpen = {}
			-- Reliable path: server echoes open to this client (binds on Game).
			pcall( function()
				game.network:sendToServer( "sv_rfs_farmTabletRequestOpen", {} )
			end )
		elseif type( RfsFarmTabletGui ) == "table" and RfsFarmTabletGui.open then
			RfsFarmTabletGui.open( nil, {} )
		end
	end
	return false, false
end

print( "[RFS] RfsFarmTabletTool loaded" )
