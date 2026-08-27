-- RfsRecipeViewerTool.lua — handheld craft planner (vanilla small LCD look).
-- VOLATILE. Always-unlocked Craftbot tool. Opens recipe queue GUI.

RfsRecipeViewerTool = class()

local TOOL_UUID = "f0e9d8c7-b6a5-4321-9c8d-7e6f5a4b3c2d"
-- Vanilla Survival small text-sign LCD (same mesh as Inventory LCD small).
local HELD_REND = "$SURVIVAL_DATA/Objects/Renderable/interactive/obj_interactive_textsign_small.rend"

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
	return string.find( tostring( item or "" ), TOOL_UUID, 1, true ) ~= nil
end

function RfsRecipeViewerTool.client_onCreate( self )
	applyHeldRenderables( self )
end

function RfsRecipeViewerTool.client_onEquip( self )
	applyHeldRenderables( self )
end

function RfsRecipeViewerTool.server_onCreate( self )
end

function RfsRecipeViewerTool.client_onEquippedUpdate( self, primaryState, secondaryState )
	if not holdingThisTool() then
		return false, false
	end
	pcall( function()
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Create", true ), "Recipe Viewer" )
	end )
	-- primaryState 1 = press. Defer GUI open to Game update so callbacks bind to Game.
	if primaryState == 1 or primaryState == true then
		local game = _G.g_rfsGame
		if game then
			game.cl = game.cl or {}
			game.cl.rfsRecipeViewerWantOpen = {}
		elseif type( RfsRecipeViewerGui ) == "table" and RfsRecipeViewerGui.open then
			RfsRecipeViewerGui.open( nil, {} )
		end
	end
	return false, false
end

print( "[RFS] RfsRecipeViewerTool loaded (vanilla LCD)" )
