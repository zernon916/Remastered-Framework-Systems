-- RfsHandheldLcd.lua — Recipe Viewer + Farmers Tablet as inventory shapes (drop like recharge box).
-- VOLATILE. Handheld use via Player.client_onAction (Create); GUI opens on Game tick.

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

local function requestRecipeViewerOpen()
	local game = _G.g_rfsGame
	if game then
		game.cl = game.cl or {}
		game.cl.rfsRecipeViewerWantOpen = {}
	elseif type( RfsRecipeViewerGui ) == "table" and RfsRecipeViewerGui.open then
		RfsRecipeViewerGui.open( nil, {} )
	end
end

local function requestFarmTabletOpen()
	local game = _G.g_rfsGame
	if game then
		game.cl = game.cl or {}
		game.cl.rfsFarmTabletWantOpen = {}
		pcall( function()
			game.network:sendToServer( "sv_rfs_farmTabletRequestOpen", {} )
		end )
	elseif type( RfsFarmTabletGui ) == "table" and RfsFarmTabletGui.open then
		RfsFarmTabletGui.open( nil, {} )
	end
end

function RfsHandheldLcd.tryConsumeCreateAction( action, state )
	if action ~= sm.interactable.actions.create then
		return false
	end
	if state ~= true then
		return false
	end
	if RfsHandheldLcd.wieldingRecipeViewer() then
		requestRecipeViewerOpen()
		return true
	end
	if RfsHandheldLcd.wieldingFarmTablet() then
		requestFarmTabletOpen()
		return true
	end
	return false
end

function RfsHandheldLcd.client_tick()
	if RfsHandheldLcd.wieldingRecipeViewer() then
		pcall( function()
			sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Create", true ), "Recipe Viewer" )
		end )
		return
	end
	if RfsHandheldLcd.wieldingFarmTablet() then
		pcall( function()
			sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Create", true ), "Farmers Tablet" )
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
		end
		if orig then
			return orig( self, action, state )
		end
	end
	Player.client_onAction = RfsHandheldLcd._playerCreateActionHook
	Player._rfsHandheldLcdActionHook = true
	return true
end

print( "[RFS] RfsHandheldLcd loaded (shape drop + Create open)" )
