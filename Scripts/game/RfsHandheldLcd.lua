-- RfsHandheldLcd.lua — Recipe Viewer + Farmers Tablet handheld tools.
-- E (Use) opens Recipe Viewer when that tool is equipped, or Farmers Tablet
-- when the tablet is equipped. Player.client_onInteract is the reliable E path;
-- tool scripts also poll Use as a fallback. Latches prevent double-open.

RfsHandheldLcd = RfsHandheldLcd or {}

local RECIPE_VIEWER_UUID = "f0e9d8c7-b6a5-4321-9c8d-7e6f5a4b3c2d"
local FARM_TABLET_UUID = "b7c8d9e0-1f2a-4b3c-8d5e-6f7a8b9c0d1e"

local function uuidMatches( a, b )
	return a and b and string.lower( tostring( a ) ) == string.lower( tostring( b ) )
end

local function activeHotbarUuid()
	local active = nil
	pcall( function()
		active = sm.localPlayer.getActiveItem()
	end )
	if active then
		return active
	end
	local slot = nil
	pcall( function()
		slot = sm.localPlayer.getSelectedHotbarSlot()
	end )
	if slot == nil then
		return nil
	end
	local inv = nil
	pcall( function()
		inv = sm.localPlayer.getInventory()
	end )
	if not inv then
		return nil
	end
	local ok, item = pcall( function()
		return inv:getItem( slot )
	end )
	if ok and item and item.uuid then
		return item.uuid
	end
	return nil
end

function RfsHandheldLcd.wieldingRecipeViewer()
	return uuidMatches( activeHotbarUuid(), RECIPE_VIEWER_UUID )
end

function RfsHandheldLcd.wieldingFarmTablet()
	return uuidMatches( activeHotbarUuid(), FARM_TABLET_UUID )
end

function RfsHandheldLcd.tryOpenRecipeViewer()
	local game = _G.g_rfsGame
	local gui = game and game.cl and game.cl.rfsRecipeViewerGui
	if gui then
		return false
	end
	_G.g_rfsRecipeViewerOpen = false
	if game and game.cl and game.cl.rfsRecipeViewerWantOpen ~= nil then
		return false
	end
	RfsHandheldLcd._rfsRecipeViewerOpenRequested = true
	if game then
		game.cl = game.cl or {}
		game.cl.rfsRecipeViewerWantOpen = { source = "viewer-e" }
	elseif type( RfsRecipeViewerGui ) == "table" and RfsRecipeViewerGui.open then
		RfsHandheldLcd._rfsRecipeViewerOpenRequested = nil
		RfsRecipeViewerGui.open( nil, {} )
	end
	return true
end

function RfsHandheldLcd.clearRecipeViewerOpenRequest()
	RfsHandheldLcd._rfsRecipeViewerOpenRequested = nil
end

-- X-ray ahead: if the crosshair is on a Character / Harvestable / Player let E do
-- THAT instead of opening the tablet.
--
-- WHY no shape check: In SM every Shape has an Interactable, even plain blocks, so
-- checking shape.interactable always returns true and blocks E on walls/ground —
-- that was the original bug.  Shape interactables (chests, screens, crafting stns)
-- are handled by the engine BEFORE Player.client_onInteract fires: if they claim E,
-- our hook never runs.  So we only need to defer E for non-shape entities here.
-- The tool's per-frame poll (RfsFarmTabletTool) also calls this guard so it doesn't
-- steal E from bots/harvestables while the tablet is in hand.
function RfsHandheldLcd.lookingAtInteractable()
	local look = false
	pcall( function()
		local hit, result = sm.localPlayer.getLatestRaycast()
		if not hit or type( result ) ~= "table" then
			return
		end
		local t = tostring( result.type or "" )
		if t == "Character" or t == "Harvestable" or t == "Player" then
			look = true
		end
	end )
	return look
end

-- Single latched entry point for the Farmers Tablet menu. Every E path lands
-- here — the handheld tool poll, the Player Interact hook AND the legacy Player
-- Use hook — so one E press can never double-open. The latch clears when the GUI
-- opens (RfsFarmTabletGui.open) or closes.
function RfsHandheldLcd.tryOpenFarmTablet()
	if _G.g_rfsFarmTabletOpen == true then
		return false
	end
	if RfsHandheldLcd._rfsFarmTabletOpenRequested then
		return false
	end
	-- NO lookingAtInteractable() guard here: when Player.client_onInteract fires,
	-- the engine has already determined nothing else claims E.  Shape interactables
	-- (chests, screens, bots) are given first dibs by the engine; we only get this
	-- callback as a fallback.  The tool's per-frame poll DOES guard itself via
	-- lookingAtInteractable() to avoid stealing E from nearby entities.
	RfsHandheldLcd._rfsFarmTabletOpenRequested = true
	local game = _G.g_rfsGame
	if game then
		game.cl = game.cl or {}
		game.cl.rfsFarmTabletWantOpen = { source = "tablet-e" }
		pcall( function()
			sm.gui.chatMessage( "[RFS] Farmers Tablet: E pressed — opening" )
			game.network:sendToServer( "sv_rfs_farmTabletRequestOpen", {} )
		end )
	elseif type( RfsFarmTabletGui ) == "table" and RfsFarmTabletGui.open then
		RfsFarmTabletGui.open( nil, {} )
	end
	return true
end

function RfsHandheldLcd.clearFarmTabletOpenRequest()
	RfsHandheldLcd._rfsFarmTabletOpenRequested = nil
end

-- Create (LMB) opens the Recipe Viewer only. The Farmers Tablet opens on E (Use) so it
-- behaves like the Farm Screen — see tryConsumeUseAction below.
function RfsHandheldLcd.tryConsumeCreateAction( action, state )
	if action ~= sm.interactable.actions.create then
		return false
	end
	if state ~= true then
		return false
	end
	if RfsHandheldLcd.wieldingRecipeViewer() then
		return RfsHandheldLcd.tryOpenRecipeViewer()
	end
	return false
end

-- E (Use) opens the Farmers Tablet menu while the tablet is equipped — the same menu the
-- Farm Screen opens on E. Delegates to the shared latched entry point so the tool's own
-- E poll and the Player Interact hook can't double-open on the same press.
function RfsHandheldLcd.tryConsumeUseAction( action, state )
	if action ~= sm.interactable.actions.use then
		return false
	end
	if state ~= true then
		return false
	end
	if RfsHandheldLcd.wieldingRecipeViewer() then
		return RfsHandheldLcd.tryOpenRecipeViewer()
	end
	if RfsHandheldLcd.wieldingFarmTablet() then
		return RfsHandheldLcd.tryOpenFarmTablet()
	end
	return false
end

-- The engine fires Player.client_onInteract when the Use key (E) is pressed and nothing
-- else consumes it — this is the reliable E path (Shape.onInteract gets it when a shape
-- is targeted; client_onAction rarely fires for Use). The tablet opens here.
function RfsHandheldLcd.ensurePlayerInteractHook()
	if type( Player ) ~= "table" then
		return false
	end
	local ourHook = RfsHandheldLcd._playerInteractHook
	if ourHook and Player.client_onInteract == ourHook then
		return true
	end
	local orig = Player.client_onInteract
	function RfsHandheldLcd._playerInteractHook( self, character, state )
		if state == true and self.player == sm.localPlayer.getPlayer() then
			if RfsHandheldLcd.wieldingRecipeViewer() then
				if not ( RfsHandheldLcd.lookingAtCraftStation and RfsHandheldLcd.lookingAtCraftStation() ) then
					if RfsHandheldLcd.tryOpenRecipeViewer() then
						return true
					end
				end
			end
			if RfsHandheldLcd.wieldingFarmTablet() then
				if RfsHandheldLcd.tryOpenFarmTablet() then
					return true
				end
			end
		end
		if orig then
			return orig( self, character, state )
		end
	end
	Player.client_onInteract = RfsHandheldLcd._playerInteractHook
	Player._rfsHandheldLcdInteractHook = true
	return true
end

local function pressedKeyBag()
	local bag = {}
	pcall( function()
		if type( sm.localPlayer.getPressedKeys ) ~= "function" then
			return
		end
		local keys = sm.localPlayer.getPressedKeys()
		if type( keys ) ~= "table" then
			return
		end
		for _, k in ipairs( keys ) do
			bag[string.lower( tostring( k ) )] = true
		end
	end )
	return bag
end

local function keyBagHas( bag, ... )
	for i = 1, select( "#", ... ) do
		local name = string.lower( tostring( select( i, ... ) ) )
		if bag[name] then
			return true
		end
		if #name >= 4 then
			for k, _ in pairs( bag ) do
				if string.find( k, name, 1, true ) then
					return true
				end
			end
		end
	end
	return false
end

function RfsHandheldLcd.ctrlHeld()
	local bag = pressedKeyBag()
	if keyBagHas( bag, "lcontrol", "rcontrol", "left control", "right control", "leftctrl", "rightctrl", "ctrl", "control" ) then
		return true
	end
	for k, _ in pairs( bag ) do
		if string.find( k, "ctrl", 1, true ) or string.find( k, "control", 1, true ) then
			return true
		end
	end
	return false
end

function RfsHandheldLcd.uHeld()
	local bag = pressedKeyBag()
	if bag["u"] == true then
		return true
	end
	for k, _ in pairs( bag ) do
		if k == "u" or k == "key_u" or k == "keyboard_u" or k == "letter_u" then
			return true
		end
	end
	return false
end

function RfsHandheldLcd.lookingAtCraftStationShape()
	local shape
	pcall( function()
		local hit, result = sm.localPlayer.getLatestRaycast()
		if not hit then
			return
		end
		pcall( function()
			shape = result.getShape and result:getShape() or result.shape
		end )
		if shape and sm.exists( shape ) then
			if string.lower( tostring( shape:getShapeUuid() ) ) ~= "c8d7e6f5-a4b3-42c1-9d0e-8f7a6b5c4d3e" then
				shape = nil
			end
		else
			shape = nil
		end
	end )
	return shape
end

function RfsHandheldLcd.lookingAtCraftStation()
	return RfsHandheldLcd.lookingAtCraftStationShape() ~= nil
end

-- Client: tell the station itself to pair. Do not send a Player object across VMs.
function RfsHandheldLcd.pairLookingAtStation()
	local shape = RfsHandheldLcd.lookingAtCraftStationShape()
	if not shape then
		return nil
	end
	local shapeId
	pcall( function()
		shapeId = shape:getId()
	end )
	pcall( function()
		local ia = shape:getInteractable()
		if ia and sm.exists( ia ) then
			sm.event.sendToInteractable( ia, "cl_n_rfsPairTablet", {} )
		end
	end )
	return shapeId
end

-- Backup if U on the station did not fire. Look at the station with the tablet.
function RfsHandheldLcd.tryLinkCraftStation()
	if not RfsHandheldLcd.wieldingRecipeViewer() then
		return false
	end
	if not RfsHandheldLcd.lookingAtCraftStation() then
		return false
	end
	if not RfsHandheldLcd.uHeld() then
		return false
	end
	if RfsHandheldLcd._rfsLinkHeld then
		return false
	end
	RfsHandheldLcd._rfsLinkHeld = true
	pcall( function()
		sm.gui.chatMessage( "[RFS] Linking Mobile Crafting Tablet..." )
	end )
	local game = _G.g_rfsGame
	if game and type( RfsRecipeViewerGui ) == "table" and RfsRecipeViewerGui.pair then
		RfsRecipeViewerGui.pair( game )
		return true
	end
	RfsHandheldLcd.pairLookingAtStation()
	return true
end

function RfsHandheldLcd.client_tick()
	if RfsHandheldLcd.wieldingRecipeViewer() then
		pcall( function()
			sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "Mobile Crafting Tablet" )
			sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Tinker", true ), "Look at station to link" )
		end )
		if RfsHandheldLcd.uHeld() then
			RfsHandheldLcd.tryLinkCraftStation()
		else
			RfsHandheldLcd._rfsLinkHeld = nil
		end
		return
	end
	RfsHandheldLcd._rfsLinkHeld = nil
	if RfsHandheldLcd.wieldingFarmTablet() then
		pcall( function()
			sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "Farmers Tablet" )
		end )
	end
end

function RfsHandheldLcd.ensurePlayerActionHooks()
	if type( Player ) ~= "table" then
		return false
	end
	local ourHook = RfsHandheldLcd._playerCreateActionHook
	if ourHook and Player.client_onAction == ourHook then
		return true
	end
	local orig = Player.client_onAction
	function RfsHandheldLcd._playerCreateActionHook( self, action, state )
		if self.player == sm.localPlayer.getPlayer() then
			if RfsHandheldLcd.tryConsumeCreateAction( action, state ) then
				return true
			end
			if RfsHandheldLcd.tryConsumeUseAction( action, state ) then
				return true
			end
		end
		if orig then
			return orig( self, action, state )
		end
	end
	Player.client_onAction = RfsHandheldLcd._playerCreateActionHook
	Player._rfsHandheldLcdActionHook = true
	-- E (Use) via the reliable Player Interact callback (client_onAction rarely
	-- fires for Use on this engine).
	RfsHandheldLcd.ensurePlayerInteractHook()
	return true
end

print( "[RFS] RfsHandheldLcd loaded (E=Mobile Crafting Tablet or Farmers Tablet)" )
