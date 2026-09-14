-- RfsFarmTabletTool.lua — Farmers Tablet as a true TOOL (handheld, not placeable).
-- Held mesh: eat-tool arms + skinned tablet DAE (same pattern as GPS / vanilla Eat).
-- Opens the shared Farmers Tablet menu on E (use), same as the Farm Screen. The engine never
-- delivers the Use key directly to client_onEquippedUpdate, so E is handled by the reliable
-- Player.client_onInteract hook in RfsHandheldLcd plus a guarded per-frame pressed-key poll
-- here (same fallback RfsPaintTool uses). LMB/RMB pass through (false, false) to avoid
-- double-open — the shared RfsHandheldLcd.tryOpenFarmTablet latch keeps one open per press.

dofile( "$CONTENT_DATA/Scripts/game/RfsHeldTool.lua" )

RfsFarmTabletTool = class()

local TOOL_UUID = "b7c8d9e0-1f2a-4b3c-8d5e-6f7a8b9c0d1e"
local RFS_LID = "29c99287-1213-48c7-9471-19a4a5c12247"
local HELD_FP = "$CONTENT_" .. RFS_LID .. "/Tools/rfs_farmers_tablet_held_v1.rend"
local HELD_TP = "$CONTENT_" .. RFS_LID .. "/Tools/rfs_farmers_tablet_held_tp_v1.rend"

sm.tool.preloadRenderables( { HELD_FP, HELD_TP } )

local function holdingThisTool()
	local item = nil
	pcall( function()
		item = sm.localPlayer.getActiveItem()
	end )
	return string.find( string.lower( tostring( item or "" ) ), TOOL_UUID, 1, true ) ~= nil
end

-- E key state from the engine (same guarded fallback RfsPaintTool uses — the API
-- is undocumented, so only use it when present; the Player Interact hook is the
-- primary E path).
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

function RfsFarmTabletTool.client_onCreate( self )
end

function RfsFarmTabletTool.client_onRefresh( self )
	self.equipped = true
	RfsHeldTool.setup( self, HELD_FP, HELD_TP )
end

function RfsFarmTabletTool.client_onEquip( self )
	self.equipped = true
	RfsHeldTool.setup( self, HELD_FP, HELD_TP )
end

function RfsFarmTabletTool.client_onUnequip( self )
	self.equipped = false
	RfsHeldTool.unequip( self )
end

function RfsFarmTabletTool.client_onUpdate( self, dt )
	RfsHeldTool.update( self, dt )
end

function RfsFarmTabletTool.server_onCreate( self )
end

function RfsFarmTabletTool.client_onEquippedUpdate( self, primaryState, secondaryState )
	if not holdingThisTool() then
		return false, false
	end
	-- Menu opens on E (Use) exactly like the Farm Screen — RfsHandheldLcd consumes the
	-- Player Interact / Use callbacks while this tool is equipped and requests the shared
	-- tablet GUI. The engine does not deliver Use to tool scripts, so also edge-detect it
	-- each frame from the pressed-key API when available (guarded; same RfsPaintTool trick).
	-- Tools cannot see LMB / RMB claims here, so return false, false so nothing double-opens.
	pcall( function()
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "Farmers Tablet" )
	end )
	local down = useKeyHeld()
	if down and not self._rfsTabletUseHeld then
		-- Only open via the fallback poll if we're not looking at a Character /
		-- Harvestable / Player (those own E).  Shape interactables (chests, screens)
		-- are still given first dibs by the engine before Player.client_onInteract.
		pcall( function()
			if type( RfsHandheldLcd ) == "table" and RfsHandheldLcd.tryOpenFarmTablet then
				if type( RfsHandheldLcd.lookingAtInteractable ) == "function" then
					if not RfsHandheldLcd.lookingAtInteractable() then
						RfsHandheldLcd.tryOpenFarmTablet()
					end
				else
					RfsHandheldLcd.tryOpenFarmTablet()
				end
			end
		end )
	end
	self._rfsTabletUseHeld = down and true or false
	return false, false
end

print( "[RFS] RfsFarmTabletTool loaded" )
