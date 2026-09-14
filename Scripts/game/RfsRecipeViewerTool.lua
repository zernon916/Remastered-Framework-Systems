-- RfsRecipeViewerTool.lua — Recipe Viewer as a true TOOL (handheld, not placeable).
-- Opens the shared Recipe Viewer menu on E (Use), same pattern as Farmers Tablet.
-- The engine does not deliver Use to client_onEquippedUpdate, so E is handled by
-- Player.client_onInteract in RfsHandheldLcd plus a guarded pressed-key poll here.

dofile( "$CONTENT_DATA/Scripts/game/RfsHeldTool.lua" )

RfsRecipeViewerTool = class()

local TOOL_UUID = "f0e9d8c7-b6a5-4321-9c8d-7e6f5a4b3c2d"
local RFS_LID = "29c99287-1213-48c7-9471-19a4a5c12247"
local HELD_FP = "$CONTENT_" .. RFS_LID .. "/Tools/rfs_mobile_crafting_tablet_held_v1.rend"
local HELD_TP = "$CONTENT_" .. RFS_LID .. "/Tools/rfs_mobile_crafting_tablet_held_tp_v1.rend"

sm.tool.preloadRenderables( { HELD_FP, HELD_TP } )

local function holdingThisTool()
	local item = nil
	pcall( function()
		item = sm.localPlayer.getActiveItem()
	end )
	return string.find( string.lower( tostring( item or "" ) ), TOOL_UUID, 1, true ) ~= nil
end

local function useKeyHeld()
	local down = false
	pcall( function()
		if type( sm.localPlayer.getPressedKeys ) == "function" then
			local keys = sm.localPlayer.getPressedKeys()
			if type( keys ) == "table" then
				for _, k in ipairs( keys ) do
					local s = string.lower( tostring( k ) )
					if s == "e" or s == "use" or string.find( s, "use", 1, true ) then
						down = true
						return
					end
				end
			end
		end
	end )
	return down
end

function RfsRecipeViewerTool.client_onCreate( self )
end

function RfsRecipeViewerTool.client_onRefresh( self )
	self.equipped = true
	RfsHeldTool.setup( self, HELD_FP, HELD_TP )
end

function RfsRecipeViewerTool.client_onEquip( self )
	self.equipped = true
	RfsHeldTool.setup( self, HELD_FP, HELD_TP )
end

function RfsRecipeViewerTool.client_onUnequip( self )
	self.equipped = false
	RfsHeldTool.unequip( self )
end

function RfsRecipeViewerTool.client_onUpdate( self, dt )
	RfsHeldTool.update( self, dt )
end

function RfsRecipeViewerTool.server_onCreate( self )
end

function RfsRecipeViewerTool.client_onEquippedUpdate( self, primaryState, secondaryState )
	if not holdingThisTool() then
		return false, false
	end
	pcall( function()
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "Mobile Crafting Tablet" )
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Tinker", true ), "Look at station to link" )
	end )
	local down = useKeyHeld()
	if down and not self._rfsViewerUseHeld then
		pcall( function()
			if type( RfsHandheldLcd ) == "table" and RfsHandheldLcd.tryOpenRecipeViewer then
				local blocked = false
				if type( RfsHandheldLcd.lookingAtInteractable ) == "function" then
					blocked = RfsHandheldLcd.lookingAtInteractable()
				end
				if type( RfsHandheldLcd.lookingAtCraftStation ) == "function" then
					blocked = blocked or RfsHandheldLcd.lookingAtCraftStation()
				end
				if not blocked then
					RfsHandheldLcd.tryOpenRecipeViewer()
				end
			end
		end )
	end
	self._rfsViewerUseHeld = down and true or false
	return false, false
end

print( "[RFS] RfsRecipeViewerTool loaded (E opens Mobile Crafting Tablet)" )
