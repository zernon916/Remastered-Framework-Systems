-- Game.lua - Recipe Framework Survival Custom Game
-- Based on Axolot Survival Custom Game template + original RFS scan/commands.

dofile( "$SURVIVAL_DATA/Scripts/game/SurvivalGame.lua" )
dofile( "$CONTENT_DATA/Scripts/game/RfsSettings.lua" )
dofile( "$CONTENT_DATA/Scripts/game/RfsFeatures.lua" )
dofile( "$CONTENT_DATA/Scripts/game/RfsQuest.lua" )
dofile( "$CONTENT_DATA/Scripts/game/RfsInventory.lua" )
dofile( "$CONTENT_DATA/Scripts/game/RfsFarming.lua" )
dofile( "$CONTENT_DATA/Scripts/game/RfsBotHijack.lua" )
dofile( "$CONTENT_DATA/Scripts/game/RfsBotOrders.lua" )
dofile( "$CONTENT_DATA/Scripts/game/interactables/RfsHackBeacon.lua" )
dofile( "$CONTENT_DATA/Scripts/game/interactables/RfsAreaLoader.lua" )
dofile( "$CONTENT_DATA/Scripts/game/interactables/RfsDigitalSign.lua" )
dofile( "$CONTENT_DATA/Scripts/game/interactables/RfsFactory.lua" )
dofile( "$CONTENT_DATA/Scripts/game/ModRecipeScan.lua" )
dofile( "$CONTENT_DATA/Scripts/game/RfsSetupGui.lua" )
dofile( "$CONTENT_DATA/Scripts/game/RfsGenGui.lua" )
dofile( "$CONTENT_DATA/Scripts/game/RfsBeaconOrdersGui.lua" )
pcall( function() dofile( "$CONTENT_DATA/Scripts/game/RfsMenuGui.lua" ) end )
dofile( "$CONTENT_DATA/Scripts/game/RfsStreamer.lua" )
dofile( "$CONTENT_DATA/Scripts/game/RfsChatRelay.lua" )
dofile( "$CONTENT_DATA/Scripts/game/RfsChatOutbox.lua" )

-- Unique class name (config.json gameScript.class). Avoids collisions with a generic "Game".
RecipeFrameworkSurvival = class( SurvivalGame )
Game = RecipeFrameworkSurvival -- alias for older tooling / cache
-- Engine reads this class field when creating player inventories (vanilla Survival = 40).
RecipeFrameworkSurvival.defaultInventorySize = 40

local FARMERS_UUID = sm.uuid.new( "8d601982-4608-4d5e-bb9e-e4041486f7c7" )
local RFS_HIDEOUT_TRADER_UUID = sm.uuid.new( "614c3193-13da-40f4-9b03-37f26e760fd6" )
local RFS_MININGHUB_TRADER_UUID = sm.uuid.new( "90762ac2-5082-461d-9028-480d38a7da10" )
local RFS_HIJACK_HOST_UUID = sm.uuid.new( "a7c3e91f-2b48-4d6a-9e15-6f8d0c1a2b3c" )

-- Host checks: client uses sm.isHost; server RPCs compare sender to first connected player.
local function rfsClientIsHost()
	local ok, v = pcall( function() return sm.isHost end )
	return ok and v and true or false
end

-- Chat-list /setup: host, or a client the engine marks as admin (if those flags exist).
local function rfsClientIsAdmin()
	if rfsClientIsHost() then
		return true
	end
	local p = nil
	pcall( function() p = sm.localPlayer.getPlayer() end )
	if not p then
		return false
	end
	local ok, v = pcall( function()
		if p.hasAdminRights then
			return p:hasAdminRights()
		end
		if type( p.isAdmin ) == "function" then
			return p:isAdmin()
		end
		if p.isAdmin then
			return true
		end
		if p.clientIsAdmin then
			return p.clientIsAdmin and true or false
		end
		return false
	end )
	return ok and v and true or false
end

local function rfsServerPlayerIsHost( player )
	if not player then
		return false
	end
	local all = nil
	pcall( function() all = sm.player.getAllPlayers() end )
	if type( all ) ~= "table" or not all[1] then
		return false
	end
	local host = all[1]
	local hid, pid = nil, nil
	pcall( function() hid = host.id end )
	pcall( function() pid = player.id end )
	if hid ~= nil and pid ~= nil then
		return hid == pid
	end
	return host == player
end

-- Server: host, or a connected player the engine marks as admin (same flags as rfsClientIsAdmin).
local function rfsServerPlayerIsAdmin( player )
	if rfsServerPlayerIsHost( player ) then
		return true
	end
	if not player then
		return false
	end
	local ok, v = pcall( function()
		if player.hasAdminRights then
			return player:hasAdminRights()
		end
		if type( player.isAdmin ) == "function" then
			return player:isAdmin()
		end
		if player.isAdmin then
			return true
		end
		if player.clientIsAdmin then
			return player.clientIsAdmin and true or false
		end
		return false
	end )
	return ok and v and true or false
end

local function rfsServerDenyTo( self, player, msg )
	if player then
		pcall( function()
			self.network:sendToClient( player, "client_showMessage", msg )
		end )
	end
end

-- Chat cheats: host or admin, and cheats setting on. Nil player is denied (not an RPC sender).
local function rfsServerAllowCheat( self, player )
	if not rfsServerPlayerIsAdmin( player ) then
		rfsServerDenyTo( self, player, "[RFS] Cheats are host/admin only." )
		return false
	end
	if not RfsSettings.cheatsEnabled() then
		rfsServerDenyTo( self, player, "[RFS] Cheats are OFF (pack or /gensettings)." )
		return false
	end
	return true
end

local function rfsOpenPlayerMenu( game )
	if type( RfsMenuGui ) ~= "table" then
		pcall( function() dofile( "$CONTENT_DATA/Scripts/game/RfsMenuGui.lua" ) end )
	end
	if type( RfsMenuGui ) == "table" and type( RfsMenuGui.open ) == "function" then
		RfsMenuGui.open( game )
		return true
	end
	sm.gui.chatMessage( "[RFS] /menu â€” player menu not ready yet (RfsMenuGui)." )
	return false
end

-- Never persist hideout.json (Survival or CG). Extra trades merge in memory only.
-- Never persist Workshop/CG craftbot_other_rfs.json (keep published stub []).
-- Never persist $SURVIVAL_DATA CraftingRecipes JSON. Those writes cause INVALID CHECKSUM.
do
	local _rfsJsonSave = sm.json.save
	sm.json.save = function( data, path, ... )
		local p = tostring( path or "" )
		local norm = p:gsub( "\\", "/" )
		if string.find( norm, "hideout.json", 1, true ) then
			print( "[RFS] blocked sm.json.save(" .. p .. ") â€” hideout merge is in-memory only" )
			return
		end
		if string.find( norm, "craftbot_other_rfs.json", 1, true ) then
			print( "[RFS] blocked sm.json.save(" .. p .. ") â€” workshop craftbot stub stays []" )
			return
		end
		if string.find( norm, "CraftingRecipes", 1, true ) then
			if string.find( norm, "$SURVIVAL_DATA", 1, true ) or string.find( norm, "/Survival/CraftingRecipes", 1, true ) then
				print( "[RFS] blocked sm.json.save(" .. p .. ") â€” Survival craftbot JSON is read-only" )
				return
			end
		end
		return _rfsJsonSave( data, path, ... )
	end
end

-- JSON-safe copy so GUI / hook keep string UUIDs after LoadCraftingRecipes mutates in place.
local function rfsJsonSafeCopy( value )
	local t = type( value )
	if t == "table" then
		local out = {}
		for k, v in pairs( value ) do
			local nk = k
			if type( k ) ~= "string" and type( k ) ~= "number" then
				nk = tostring( k )
			end
			out[nk] = rfsJsonSafeCopy( v )
		end
		return out
	elseif t == "string" or t == "number" or t == "boolean" then
		return value
	elseif value == nil then
		return nil
	else
		return tostring( value )
	end
end

local function rfsPathHas( path, needle )
	return string.find( tostring( path or "" ):gsub( "\\", "/" ), needle, 1, true ) ~= nil
end

-- addGridItemsFromFile reads a real file in C++. Write a per-peer local copy that is
-- NOT Workshop and NOT Survival CraftingRecipes. Each peer writes at load.
local RFS_CRAFTBOT_LOCAL_CANDIDATES = {
	"$USER_DATA/Cache/rfs_craftbot_other.json",
	"$USER_DATA/rfs_craftbot_other.json",
	"$TEMP_DATA/rfs_craftbot_other.json",
	"$SURVIVAL_DATA/LocalBlueprints/rfs_craftbot_other.json"
}

local function rfsSaveCraftbotLocal( mergedSafe )
	for _, path in ipairs( RFS_CRAFTBOT_LOCAL_CANDIDATES ) do
		local okSave = pcall( function()
			sm.json.save( mergedSafe, path )
		end )
		if okSave then
			local okOpen, data = pcall( sm.json.open, path )
			if okOpen and type( data ) == "table" and #data == #mergedSafe then
				print( "[RFS] craftbot_other GUI file saved " .. path )
				return path
			end
		end
	end
	print( "[RFS] craftbot_other GUI file save failed â€” relying on sm.json.open hook" )
	return nil
end

-- Last resort: point Crafter GUI at the local merged path without editing Survival Crafter.lua.
local function rfsWrapCrafterRecipeGrid()
	if _G.g_rfsCrafterGridWrapped then
		return
	end
	if type( Crafter ) ~= "table" or type( Crafter.cl_updateRecipeGrid ) ~= "function" then
		return
	end
	_G.g_rfsCrafterGridWrapped = true
	local orig = Crafter.cl_updateRecipeGrid
	Crafter.cl_updateRecipeGrid = function( self, ... )
		if g_craftingRecipeSets and g_craftingRecipeSets.craftbot_other then
			local guiPath = _G.g_rfsCraftbotOtherGuiPath
			if type( guiPath ) == "string" and guiPath ~= "" then
				g_craftingRecipeSets.craftbot_other.path = guiPath
			end
		end
		return orig( self, ... )
	end
	print( "[RFS] wrapped Crafter.cl_updateRecipeGrid" )
end

-- Find a loaded trader interactable by shape UUID (client or server bodies).
local function rfsFindInteractableByShapeUuid( shapeUuid )
	local bodies = sm.body.getAllBodies()
	for _, body in ipairs( bodies ) do
		if sm.exists( body ) then
			local shapes = body:getShapes()
			for _, shape in ipairs( shapes ) do
				if sm.exists( shape ) and shape:getShapeUuid() == shapeUuid then
					local ia = shape:getInteractable()
					if ia and sm.exists( ia ) then
						return ia
					end
				end
			end
		end
	end
	return nil
end

-- Open registered trader, or fall back to body scan + sendToInteractable.
local function rfsClientOpenTraderShop( registryKey, shapeUuid, label )
	local trader = _G[registryKey]
	if trader and trader.interactable and sm.exists( trader.interactable ) and trader.cl_rfs_openShop then
		return trader:cl_rfs_openShop( { force = true } ) and true or false
	end
	local ia = rfsFindInteractableByShapeUuid( shapeUuid )
	if ia then
		local ok = pcall( function()
			sm.event.sendToInteractable( ia, "cl_rfs_openShop", { force = true } )
		end )
		return ok
	end
	sm.gui.chatMessage( "[RFS] " .. label .. " not loaded â€” visit once (or fly closer) so the cell loads, then retry" )
	return false
end

-- Main-story follow-ups used by /completequest and /setup Quest DONE.
-- Mirrors Survival CompleteQuest / dialog-activator chains.
local RFS_QUEST_NEXT = {
	quest_tutorial = "quest_mechanicstation",
	quest_mechanicstation = "quest_mystery_call",
	quest_mystery_call = "quest_feed_the_farmers",
	quest_feed_the_farmers = "quest_clear_minidungeon",
	quest_clear_minidungeon = "quest_trader_tracking",
	quest_find_recording = "quest_clear_warehouse",
	quest_clear_warehouse = "quest_warehouse_destruction",
	quest_warehouse_destruction = "quest_save_watchtower",
	quest_save_watchtower = "quest_rebuild_watchtower",
	quest_rebuild_watchtower = "quest_find_excavation",
	quest_find_excavation = "quest_activate_mininghub",
	quest_activate_mininghub = "quest_vault_1",
	quest_vault_1 = "quest_mysterious_signal",
	quest_mysterious_signal = "quest_vault_2",
	quest_vault_2 = "quest_vault_3",
	quest_scrapyard = "quest_vault_3",
	quest_vault_3 = "quest_station_2",
	quest_station_2 = "quest_bosstrain",
	quest_bosstrain = "quest_endgame",
}

-- Survival DelayedScriptableActivation (quest_util CompleteQuest next-quest path).
local RFS_DELAYED_QUEST_ACTIVATOR = sm.uuid.new( "d9458830-7899-4dd5-aae9-703cf9d46782" )
local RFS_LOG_MECHANICSTATION = "29d72e47-8eac-4fb9-95b1-ecccc06ff84f"

-- Force client tracker + markers. Cl_OnQuestCreated only auto-tracks if the main slot
-- is empty; completing the previous quest in the same frame often leaves that slot busy.
local function rfsForceTrackQuest( questName )
	if not g_questManagerServer or not questName then
		return
	end
	pcall( function()
		g_questManagerServer.network:sendToClients( "cl_trackQuest", questName )
	end )
end

-- After Survival's delayed activator fires, force-track so markers/HUD appear even if
-- Cl_OnQuestCreated lost the main-quest auto-track race.
local function rfsScheduleForceTrack( self, questName, tickDelay )
	self.sv = self.sv or {}
	self.sv.rfsPendingQuestTracks = self.sv.rfsPendingQuestTracks or {}
	self.sv.rfsPendingQuestTracks[#self.sv.rfsPendingQuestTracks + 1] = {
		name = questName,
		atTick = sm.game.getServerTick() + math.max( ( tickDelay or 0 ) + 5, 10 )
	}
end

-- Vanilla handoff: spawn DelayedScriptableActivation so TryActivateQuest runs after
-- prior quest client teardown (tracker slot free Ã¢â€ â€™ markers / HUD appear).
local function rfsQueueNextQuestActivation( self, completedName, nextName )
	local delaySec = 1
	pcall( function()
		if type( GetRewardDelay ) == "function" then
			delaySec = GetRewardDelay( completedName )
		end
	end )
	-- Minimum ~0.5s so Sv_CompleteQuest client untrack can finish before activate.
	local tickDelay = math.max( math.floor( ( delaySec or 1 ) * 40 ), 20 )
	sm.scriptableObject.createScriptableObject( RFS_DELAYED_QUEST_ACTIVATOR, {
		questName = nextName,
		tickDelay = tickDelay,
		hidden = false
	} )
	rfsScheduleForceTrack( self, nextName, tickDelay )
	return tickDelay
end

-- Tutorial teaches logbook waypoint via log_mechanicstation (not a quest marker).
local function rfsGrantTutorialStationLog()
	local uuid = ( LOGS and LOGS.log_mechanicstation ) or RFS_LOG_MECHANICSTATION
	if LogEntryManager and LogEntryManager.Sv_AddLog then
		pcall( function() LogEntryManager.Sv_AddLog( uuid ) end )
	end
	if LogEntryManager and LogEntryManager.Sv_SetLogHighlight then
		pcall( function() LogEntryManager.Sv_SetLogHighlight( uuid, true ) end )
	end
	return uuid
end

local function rfsMsg( self, msg )
	self.network:sendToClients( "client_showMessage", tostring( msg ) )
end

local function collectModCraftbotPaths( scan )
	local paths = {}
	if scan and scan.craftPaths then
		for _, p in ipairs( scan.craftPaths ) do
			paths[#paths + 1] = p
		end
	end
	return paths
end

local function rfsResolveRewardUuid( reward )
	if type( reward ) ~= "table" then
		return nil
	end
	if reward.uuid then
		return tostring( reward.uuid )
	end
	if reward.item then
		return tostring( reward.item )
	end
	if reward.name and ITEMS and ITEMS[reward.name] then
		return tostring( ITEMS[reward.name] )
	end
	if reward.name and CUSTOMIZATIONS and CUSTOMIZATIONS[reward.name] then
		return tostring( CUSTOMIZATIONS[reward.name] )
	end
	return nil
end

-- Mirror Survival CompleteQuest reward path (GrantSchematics / GrantLogs / additional).
local function rfsGrantQuestRewards( self, questName )
	local rewards = nil
	pcall( function()
		rewards = QuestManager.Sv_GetQuestRewards( questName )
	end )

	local schematicCount, logCount, otherCount = 0, 0, 0
	if type( rewards ) == "table" then
		for _, reward in ipairs( rewards ) do
			if type( reward ) == "table" then
				if reward.type == "schematic" then
					schematicCount = schematicCount + 1
				elseif reward.type == "log" then
					logCount = logCount + 1
				elseif reward.type == "additionalReward" or reward.type == "item" then
					otherCount = otherCount + 1
				end
			end
		end
	end

	if type( GrantSchematics ) == "function" then
		pcall( GrantSchematics, questName )
	end
	-- Always unlock schematics explicitly. Safe if already unlocked.
	if type( rewards ) == "table" then
		for _, reward in ipairs( rewards ) do
			if type( reward ) == "table" and reward.type == "schematic" then
				local uuid = rfsResolveRewardUuid( reward )
				if uuid then
					pcall( function() RecipeManager.Sv_UnlockRecipe( uuid ) end )
				end
			end
		end
	end

	if type( GrantLogs ) == "function" then
		pcall( GrantLogs, questName )
	end
	if type( rewards ) == "table" and LogEntryManager and LogEntryManager.Sv_AddLog then
		for _, reward in ipairs( rewards ) do
			if type( reward ) == "table" and reward.type == "log" then
				local uuid = rfsResolveRewardUuid( reward )
				if uuid then
					pcall( function() LogEntryManager.Sv_AddLog( uuid ) end )
				end
			end
		end
	end

	if type( rewards ) == "table" then
		pcall( function()
			self:sv_e_grantAdditionalRewards( rewards )
		end )
	end

	return schematicCount, logCount, otherCount
end

-- QuestManager.Sv_CompleteQuest only writes completed state when the quest is active.
local function rfsForceMarkComplete( questName )
	if QuestManager.Sv_IsQuestComplete( questName ) then
		return
	end
	if not g_questManagerServer or not g_questManagerServer.sv or not g_questManagerServer.sv.saved then
		return
	end
	local saved = g_questManagerServer.sv.saved
	saved.completedQuests = saved.completedQuests or {}
	for _, existing in ipairs( saved.completedQuests ) do
		if existing == questName then
			return
		end
	end
	saved.completedQuests[#saved.completedQuests + 1] = questName
	pcall( function()
		g_questManagerServer.storage:save( saved )
		g_questManagerServer.network:setClientData( saved )
	end )
end

function RecipeFrameworkSurvival.server_onPlayerJoined( self, player, newPlayer )
	SurvivalGame.server_onPlayerJoined( self, player, newPlayer )
	pcall( function()
		local id = RfsInventory.getSavedOptionId()
		RfsInventory.applyGameDefault( RecipeFrameworkSurvival )
		RfsInventory.applyToPlayer( player, id )
	end )
end

function RecipeFrameworkSurvival.server_onCreate( self )
	-- Do NOT set g_survivalDev. Survival skips quest_tutorial / intro / builder guide
	-- when that flag is true (sv_n_loadingScreenLifted, cinematic, SurvivalPlayer).
	-- Cheats are bound separately in rfs_bindCommands (local cheats gate; do not set g_survivalDev).
	RfsSettings.load()
	RfsFeatures.load()
	RfsInventory.applyGameDefault( RecipeFrameworkSurvival )
	RfsFarming.load()
	SurvivalGame.server_onCreate( self )
	_G.g_rfsGame = self
	pcall( function() RfsFarming.ensureHooks() end )
	pcall( function() RfsBotHijack.ensureHooks() end )
	self.sv = self.sv or {}
	self.sv.rfsPendingQuestTracks = self.sv.rfsPendingQuestTracks or {}
	-- Expose quest API early for RFS + guest mods (_G.RfsQuest from RfsQuest.lua dofile).
	if type( RfsQuest ) == "table" then
		_G.RfsQuest = RfsQuest
	end
	print( "[RFS] server_onCreate (g_survivalDev left for normal quest flow; RfsQuest=" .. tostring( type( _G.RfsQuest ) ) .. ")" )
end

function RecipeFrameworkSurvival.sv_rfs_ensureHijackHost( self )
	if self.sv and self.sv.rfsHijackHost and sm.exists( self.sv.rfsHijackHost ) then
		return self.sv.rfsHijackHost
	end
	local world = self.sv and self.sv.saved and self.sv.saved.overworld
	if not world then
		return nil
	end
	local okExists, exists = pcall( sm.exists, world )
	if okExists and exists == false then
		pcall( sm.world.loadWorld, world )
	end
	local ok, so = pcall( function()
		return sm.scriptableObject.createScriptableObject( RFS_HIJACK_HOST_UUID, nil, world )
	end )
	if ok and so then
		self.sv.rfsHijackHost = so
		print( "[RFS] hijack host SO created" )
		return so
	end
	print( "[RFS] hijack host SO failed: " .. tostring( so ) )
	return nil
end

function RecipeFrameworkSurvival.server_onFixedUpdate( self, timeStep )
	SurvivalGame.server_onFixedUpdate( self, timeStep )
	pcall( function() RfsFarming.sv_tick( self ) end )
	pcall( function()
		if type( RfsStreamer ) == "table" and RfsStreamer.sv_think then
			RfsStreamer.sv_think( timeStep, self )
		end
	end )
	pcall( function()
		if type( RfsChatRelay ) == "table" and RfsChatRelay.sv_think then
			RfsChatRelay.sv_think( timeStep, self )
		end
	end )
	pcall( function()
		if type( RfsBotOrders ) == "table" and RfsBotOrders.sv_think then
			RfsBotOrders.sv_think( timeStep, self )
		end
	end )
	local tick = sm.game.getCurrentTick()
	-- Single pending Orders open: fire once after interact (next Game ticks).
	do
		local pend = self.sv and self.sv.rfsPendingOrdersOpen
		if pend and pend.player and type( pend.data ) == "table" then
			if tick >= ( tonumber( pend.atTick ) or 0 ) then
				self.sv.rfsPendingOrdersOpen = nil
				local okSend = pcall( function()
					self.network:sendToClient( pend.player, "cl_rfs_ordersOpen", pend.data )
				end )
				if not okSend then
					-- Retry once next tick if network rejected the payload.
					self.sv.rfsPendingOrdersOpen = {
						player = pend.player,
						atTick = tick + 1,
						data = pend.data,
						retried = true,
					}
					if not pend.retried then
						rfsMsg( self, "HACK 3.5f-orders open retry" )
					end
				end
			end
		end
	end
	if ( tick % 80 ) == 0 then
		pcall( function() RfsFarming.ensureHooks() end )
		pcall( function() RfsBotHijack.ensureHooks() end )
	end
	local pending = self.sv and self.sv.rfsPendingQuestTracks
	if not pending or #pending == 0 then
		return
	end
	local now = sm.game.getServerTick()
	local keep = {}
	local followUps = {}
	for _, job in ipairs( pending ) do
		if now >= ( job.atTick or 0 ) then
			if QuestManager.Sv_IsQuestActive( job.name ) then
				rfsForceTrackQuest( job.name )
				rfsMsg( self, "Next quest active + tracked: " .. tostring( job.name ) )
			elseif not QuestManager.Sv_IsQuestComplete( job.name ) then
				-- Activator may have failed; last-chance direct activate.
				pcall( function() QuestManager.Sv_ActivateQuest( job.name ) end )
				-- Activate is event-deferred; track a few ticks later when client has the SO.
				if not job.retry then
					followUps[#followUps + 1] = {
						name = job.name,
						atTick = now + 10,
						retry = true
					}
					rfsMsg( self, "Next quest fallback activate queued: " .. tostring( job.name ) )
				else
					rfsMsg( self, "Next quest still not active: " .. tostring( job.name ) )
				end
			else
				rfsMsg( self, "Next quest already complete (skipped): " .. tostring( job.name ) )
			end
		else
			keep[#keep + 1] = job
		end
	end
	for _, job in ipairs( followUps ) do
		keep[#keep + 1] = job
	end
	self.sv.rfsPendingQuestTracks = keep
end

function RecipeFrameworkSurvival.client_onCreate( self )
	SurvivalGame.client_onCreate( self )
	self.cl = self.cl or {}
	self.cl.rfsCmdsBound = false
	self.cl.rfsGrowthOverlay = false
	_G.g_rfsGame = self
	RfsFarming.ensureHooks()
	pcall( function() RfsBotHijack.ensureHooks() end )
	self:rfs_bindCommands()
	-- Pull world farming prefs + GenSettings feature flags
	pcall( function()
		self.network:sendToServer( "sv_rfs_farmingGet" )
	end )
	pcall( function()
		self.network:sendToServer( "sv_rfs_featuresGet" )
	end )
	pcall( rfsWrapCrafterRecipeGrid )
	print( "[RFS] client_onCreate host=" .. tostring( sm.isHost ) .. " craftbotMerged=" .. tostring( _G.g_rfsCraftbotMerged == true ) )
end

function RecipeFrameworkSurvival.client_onClientDataUpdate( self, clientData, channel )
	-- Honor Survival's dev flag from the server. Never force clientData.dev = true -
	-- that re-enabled g_survivalDev every packet and blocked auto quest start.
	if channel == 1 then
		if type( clientData ) == "table" then
			g_survivalDev = clientData.dev and true or false
			self.cl = self.cl or {}
			self.cl.gotoLocations = clientData.gotoLocations
		end
		-- RFS binder (not SurvivalGame.bindChatCommands) - cheats without g_survivalDev.
		-- Skip if already bound; rfs_bindCommands also no-ops when cheats gate unchanged.
		if not ( self.cl and self.cl.rfsCmdsBound ) then
			self:rfs_bindCommands()
		end
	elseif channel == 2 and type( clientData ) == "table" then
		self.cl = self.cl or {}
		self.cl.time = clientData.time
	end
end

function RecipeFrameworkSurvival.client_onUpdate( self, dt )
	SurvivalGame.client_onUpdate( self, dt )
	-- Fallback: if create/clientData paths skipped binding, catch it on first tick.
	if not ( self.cl and self.cl.rfsCmdsBound ) then
		self:rfs_bindCommands()
	end
	-- Beacon Orders: only deferred after Close settle (~0.5s). Normal open is immediate.
	do
		local pend = self.cl and self.cl.rfsPendingOrdersGui
		if pend and type( pend.data ) == "table" then
			local tick = sm.game.getCurrentTick()
			local settle = tonumber( self.cl.rfsOrdersReopenAfterTick ) or 0
			local readyAt = math.max( tonumber( pend.atTick ) or 0, settle )
			if tick >= readyAt then
				local gen = tonumber( pend.gen )
				self.cl.rfsPendingOrdersGui = nil
				if not ( gen and gen ~= tonumber( self.cl.rfsOrdersOpenGen ) )
					and type( RfsBeaconOrdersGui ) == "table"
					and type( RfsBeaconOrdersGui.open ) == "function" then
					RfsBeaconOrdersGui.open( self, pend.data )
				end
			end
		end
	end
	-- Character countdown hooks must run on the client (unit globals are server-only).
	pcall( function()
		if type( RfsBotHijack ) == "table" and RfsBotHijack.ensureCharHooks then
			RfsBotHijack.ensureCharHooks()
		end
	end )
	-- Re-apply Farming hooks if Survival reloaded tool/harvestable classes
	if ( sm.game.getCurrentTick() % 200 ) == 0 then
		pcall( function() RfsFarming.ensureHooks() end )
		pcall( function() RfsBotHijack.ensureHooks() end )
		pcall( rfsWrapCrafterRecipeGrid )
	end
	-- Keep /setup Main/Farming and /menu labels in sync after toggles / chat cmds
	if self.cl and self.cl.rfsSetupGui then
		if self.cl.rfsSetupRefreshAt and sm.game.getCurrentTick() >= self.cl.rfsSetupRefreshAt then
			self.cl.rfsSetupRefreshAt = nil
			if self.cl.rfsSetupTab == "main" then
				RfsSetupGui.refreshMain( self )
			elseif self.cl.rfsSetupTab == "farming" then
				RfsSetupGui.refreshFarming( self )
			end
		elseif self.cl.rfsSetupTab == "main" and ( sm.game.getCurrentTick() % 40 ) == 0 then
			RfsSetupGui.refreshMain( self )
		elseif self.cl.rfsSetupTab == "farming" and ( sm.game.getCurrentTick() % 40 ) == 0 then
			RfsSetupGui.refreshFarming( self )
		end
	end
	if self.cl and self.cl.rfsMenuGui and type( RfsMenuGui ) == "table" and ( sm.game.getCurrentTick() % 40 ) == 0 then
		RfsMenuGui.refresh( self )
	end
	if self.cl and self.cl.rfsGenGui and ( sm.game.getCurrentTick() % 40 ) == 0 then
		RfsGenGui.refresh( self )
	end
	pcall( function()
		if type( RfsRangeViz ) == "table" and RfsRangeViz.tick then
			RfsRangeViz.tick( self, self.cl and self.cl.rfsRangeWant )
		end
	end )
end

function RecipeFrameworkSurvival.loadCraftingRecipes( self )
	local recipeSets = sm.json.open( "$SURVIVAL_DATA/CraftingRecipes/craftbot/craftbot.json" )
	recipeSets.workbench = "$SURVIVAL_DATA/CraftingRecipes/workbench.json"
	recipeSets.portablecrafter = "$SURVIVAL_DATA/CraftingRecipes/portablecrafter.json"
	recipeSets.dispenser = "$SURVIVAL_DATA/CraftingRecipes/dispenser.json"
	recipeSets.cookbot = "$SURVIVAL_DATA/CraftingRecipes/cookbot.json"
	recipeSets.dressbot = "$SURVIVAL_DATA/CraftingRecipes/dressbot.json"
	recipeSets.mininghubDispenser = "$SURVIVAL_DATA/CraftingRecipes/mininghubDispenser.json"
	recipeSets.sawtable = "$SURVIVAL_DATA/CraftingRecipes/sawtable.json"

	-- Scan mods first so craftbot paths exist before LoadCraftingRecipes.
	local scan = ModRecipeScan.run()

	-- RFS Hideout: Hack Beacon for 20 Farmers (item, not schematic).
	do
		local okHide, hideCfg = pcall( sm.json.open, "$CONTENT_DATA/CraftingRecipes/hideout_trades.json" )
		if okHide and type( hideCfg ) == "table" then
			_G.g_extraHideoutTrades = _G.g_extraHideoutTrades or {}
			local list = hideCfg.trades or hideCfg
			local seenHide = {}
			for _, t in ipairs( _G.g_extraHideoutTrades ) do
				if t and t.itemId then
					seenHide[tostring( t.itemId )] = true
				end
			end
			if type( list ) == "table" then
				for _, raw in ipairs( list ) do
					if type( raw ) == "table" and raw.itemId then
						local id = tostring( raw.itemId )
						if not seenHide[id] then
							_G.g_extraHideoutTrades[#_G.g_extraHideoutTrades + 1] = raw
							seenHide[id] = true
						end
					end
				end
			end
			_G.g_hideoutExtraTradesDirty = true
			_G.g_hideoutExtraTradesMerged = false
		end
	end

	-- Merge mod craftbot arrays into craftbot_other so the vanilla Crafter GUI lists them
	-- (CraftbotRecipeSets is a fixed local list - injecting a new set name would not show).
	local merged = {}
	local seen = {}
	local otherPath = recipeSets.craftbot_other or "$SURVIVAL_DATA/CraftingRecipes/craftbot/craftbot_other.json"
	local okOther, otherJson = pcall( sm.json.open, otherPath )
	if okOther and type( otherJson ) == "table" then
		for _, recipe in ipairs( otherJson ) do
			if type( recipe ) == "table" and recipe.itemId then
				local id = tostring( recipe.itemId )
				if not seen[id] then
					merged[#merged + 1] = recipe
					seen[id] = true
				end
			end
		end
	end
	local modAdded = 0
	for _, path in ipairs( collectModCraftbotPaths( scan ) ) do
		local ok, json = pcall( sm.json.open, path )
		if ok and type( json ) == "table" then
			local list = json
			if json.craftbot_core or json.craftbot_beams then
				list = {}
				for _, subPath in pairs( json ) do
					if type( subPath ) == "string" then
						local okSub, sub = pcall( sm.json.open, subPath )
						if okSub and type( sub ) == "table" then
							for _, r in ipairs( sub ) do
								list[#list + 1] = r
							end
						end
					end
				end
			end
			for _, recipe in ipairs( list ) do
				if type( recipe ) == "table" and recipe.itemId then
					local id = tostring( recipe.itemId )
					if not seen[id] then
						merged[#merged + 1] = recipe
						seen[id] = true
						modAdded = modAdded + 1
					end
				end
			end
		end
	end

	-- RFS own recipes (Hack Beacon, etc.) â€” always-available, not schematic-locked.
	do
		local okRfs, rfsCraft = pcall( sm.json.open, "$CONTENT_DATA/CraftingRecipes/craftbot_rfs.json" )
		if okRfs and type( rfsCraft ) == "table" then
			for _, recipe in ipairs( rfsCraft ) do
				if type( recipe ) == "table" and recipe.itemId then
					local id = tostring( recipe.itemId )
					if not seen[id] then
						merged[#merged + 1] = recipe
						seen[id] = true
						modAdded = modAdded + 1
					end
					if g_unlockableCraftItems then
						g_unlockableCraftItems[id] = nil
					end
				end
			end
		end
	end

	-- Deep-copy BEFORE LoadCraftingRecipes mutates ingredient UUIDs in place.
	-- Hook + GUI file must keep string UUIDs.
	local mergedSafe = rfsJsonSafeCopy( merged )
	_G.g_rfsCraftbotMergedSafe = mergedSafe
	_G.g_rfsCraftbotMerged = true

	-- Serve merged craftbot recipes in-memory. Never sm.json.save into $CONTENT_DATA â€”
	-- that rewrites Workshop files on the host and breaks multiplayer checksums.
	local mergedPath = "$CONTENT_DATA/CraftingRecipes/craftbot_other_rfs.json"
	recipeSets.craftbot_other = mergedPath

	local hostFlag = false
	do
		local okHost, hostVal = pcall( function() return sm.isHost end )
		if okHost then
			hostFlag = hostVal and true or false
		end
	end
	print( "[RFS] craftbot_other in-memory merge modRecipes+=" .. tostring( modAdded ) .. " total=" .. tostring( #merged ) .. " host=" .. tostring( hostFlag ) )

	-- Survival's LoadCraftingRecipes unconditionally sm.json.open(hideout.json).
	-- If Survival's file is missing, return {} â€” do NOT write hideout.json to disk.
	-- Hook craftbot_other_rfs.json by filename suffix (engine may resolve $CONTENT_DATA).
	local SURV_HIDEOUT = "$SURVIVAL_DATA/CraftingRecipes/hideout.json"
	local _jsonOpen = sm.json.open
	sm.json.open = function( path, ... )
		if rfsPathHas( path, "craftbot_other_rfs.json" ) then
			return rfsJsonSafeCopy( _G.g_rfsCraftbotMergedSafe or mergedSafe )
		end
		local ok, result = pcall( _jsonOpen, path, ... )
		if ok then
			return result
		end
		if path == SURV_HIDEOUT then
			print( "[RFS] Survival hideout.json missing â€” empty trade list (in-memory only)" )
			return {}
		end
		error( result )
	end

	local okLoad, errLoad = pcall( LoadCraftingRecipes, recipeSets )
	if not okLoad then
		print( "[RFS] LoadCraftingRecipes failed: " .. tostring( errLoad ) )
		-- Keep world init alive so QuestManager / tutorial can still start.
		local okRetry, errRetry = pcall( LoadCraftingRecipes, {
			craftbot = "$SURVIVAL_DATA/CraftingRecipes/craftbot/craftbot.json",
			craftbot_other = recipeSets.craftbot_other or "$SURVIVAL_DATA/CraftingRecipes/craftbot/craftbot_other.json",
			workbench = recipeSets.workbench,
			portablecrafter = recipeSets.portablecrafter,
			dispenser = recipeSets.dispenser,
			cookbot = recipeSets.cookbot,
			dressbot = recipeSets.dressbot,
			mininghubDispenser = recipeSets.mininghubDispenser,
			sawtable = recipeSets.sawtable
		} )
		if not okRetry then
			print( "[RFS] LoadCraftingRecipes retry failed: " .. tostring( errRetry ) )
		end
	end
	-- Keep sm.json.open hooked: merged craftbot stays in-memory; never write hideout.json.

	-- C++ addGridItemsFromFile ignores the Lua hook. Point GUI at a local JSON-safe file.
	local guiPath = rfsSaveCraftbotLocal( mergedSafe )
	if not guiPath then
		guiPath = mergedPath
	end
	_G.g_rfsCraftbotOtherGuiPath = guiPath
	if g_craftingRecipeSets and g_craftingRecipeSets.craftbot_other then
		g_craftingRecipeSets.craftbot_other.path = guiPath
	end
	pcall( rfsWrapCrafterRecipeGrid )

	-- Re-apply unlockable marks after LoadCraftingRecipes resets g_unlockableCraftItems.
	-- Do NOT unlock - players keep schematic progression.
	if scan then
		for _, path in ipairs( collectModCraftbotPaths( scan ) ) do
			local ok, json = pcall( sm.json.open, path )
			if ok and type( json ) == "table" then
				for _, recipe in ipairs( json ) do
					if type( recipe ) == "table" and recipe.itemId then
						g_unlockableCraftItems[tostring( recipe.itemId )] = true
					end
				end
			end
		end
	end
	-- RFS own recipes stay always-available (Hack Beacon, etc.)
	do
		local okRfs, rfsCraft = pcall( sm.json.open, "$CONTENT_DATA/CraftingRecipes/craftbot_rfs.json" )
		if okRfs and type( rfsCraft ) == "table" then
			g_unlockableCraftItems = g_unlockableCraftItems or {}
			for _, recipe in ipairs( rfsCraft ) do
				if type( recipe ) == "table" and recipe.itemId then
					g_unlockableCraftItems[tostring( recipe.itemId )] = nil
				end
			end
		end
	end
end

-- Bind one chat command with pcall so a single failure cannot abort the rest.
-- Quiet by default: no OK spam. Reserved fails are swallowed; other fails print once.
function RecipeFrameworkSurvival.rfs_bindOne( self, name, args, desc )
	local ok, err = pcall( function()
		sm.game.bindChatCommand( name, args or {}, "cl_onChatCommand", desc or "" )
	end )
	if not ok then
		self.cl = self.cl or {}
		local errStr = tostring( err )
		local reserved = string.find( string.lower( errStr ), "reserved", 1, true ) ~= nil
		if reserved then
			if name == "/help" then
				self.cl.rfsHelpReserved = true
			else
				self.cl.rfsBindFailLogged = self.cl.rfsBindFailLogged or {}
				if not self.cl.rfsBindFailLogged[name] then
					self.cl.rfsBindFailLogged[name] = true
					print( "[RFS] bind " .. name .. " reserved: " .. errStr )
				end
			end
		else
			self.cl.rfsBindFailLogged = self.cl.rfsBindFailLogged or {}
			if not self.cl.rfsBindFailLogged[name] then
				self.cl.rfsBindFailLogged[name] = true
				print( "[RFS] bind " .. name .. " FAIL: " .. errStr )
			end
		end
	end
	return ok
end

-- Full command table. Bind cheats with a local gate; do NOT set g_survivalDev
-- (that flag disables Survival auto quest / tutorial startup). Never call SurvivalGame.bindChatCommands
-- (it can abort on nil g_unitSpawnNames).
function RecipeFrameworkSurvival.rfs_bindCommands( self )
	self.cl = self.cl or {}
	RfsSettings.load()
	local cheats = RfsSettings.cheatsEnabled()
	local admin = rfsClientIsAdmin()
	local host = rfsClientIsHost()
	-- Avoid full rebind storms from clientData / features sync when nothing changed.
	if self.cl.rfsCmdsBound and self.cl.rfsCmdsCheatsBound == cheats
		and self.cl.rfsCmdsAdminBound == admin and self.cl.rfsCmdsHostBound == host then
		return
	end

	if sm.isHost then
		self:rfs_bindOne( "/kick", { { "string", "player name", false } }, "Kick a player from server" )
		self:rfs_bindOne( "/ban", { { "string", "player name", false } }, "Ban a player from server" )
	end
	if rfsClientIsAdmin() then
		self:rfs_bindOne( "/setup", {}, "Open RFS host setup GUI (admin)" )
	end

	-- Player menu first. /help is often engine-reserved; a failed /help must not
	-- skip /menu. /menu itself can also be reserved (InGameMenu) — then /rfsmenu
	-- is the name that actually appears in the client's chat list.
	self:rfs_bindOne( "/menu", {}, "Open player menu (map and growth overlay)" )
	self:rfs_bindOne( "/rfsmenu", {}, "Open player menu (map and growth overlay)" )
	-- Always available (/help is often engine-reserved; skip after first reserved fail)
	if not self.cl.rfsHelpReserved then
		self:rfs_bindOne( "/help", {}, "List Recipe Framework Survival commands" )
	end
	self:rfs_bindOne( "/commands", {}, "Alias of /help" )
	self:rfs_bindOne( "/gensettings", {}, "Open RFS gen settings (host only)" )
	self:rfs_bindOne( "/map", {}, "Toggle top-down camera map (WASD pan, scroll zoom)" )
	self:rfs_bindOne( "/mapclose", {}, "Close top-down camera map" )
	self:rfs_bindOne( "/rfsmap", {}, "Alias of /map" )
	self:rfs_bindOne( "/mods", {}, "List scanned mod recipe sources" )

	-- Phase D: game → Discord (requires Streamer + chat relay in /gensettings)
	local sayArgs = {}
	for i = 1, 24 do
		sayArgs[i] = { "string", "w" .. tostring( i ), true }
	end
	self:rfs_bindOne( "/say", sayArgs, "Send chat to Discord (Streamer + chat relay)" )
	self:rfs_bindOne( "/d", sayArgs, "Alias of /say (game → Discord)" )
	self:rfs_bindOne( "/unhijack", { { "number", "range", true } }, "Release nearest owned ally robot (host can release any)" )
	self:rfs_bindOne( "/botname", { { "string", "name", false } }, "Rename nearest owned ally (or the bot you E'd)" )
	self:rfs_bindOne( "/botorder", { { "string", "mode", false } }, "Set order on nearest owned ally: rest/defend/stay/recall/return/farm/collect/oil/sentry" )

	-- Cheats in the chat list: host or admin only. Regular clients never see them.
	if cheats and admin then
		-- Survival cheat set
		self:rfs_bindOne( "/ammo", { { "int", "quantity", true } }, "Give ammo (default 100)" )
		self:rfs_bindOne( "/spudgun", {}, "Give the spudgun" )
		self:rfs_bindOne( "/gatling", {}, "Give the potato gatling gun" )
		self:rfs_bindOne( "/shotgun", {}, "Give the fries shotgun" )
		self:rfs_bindOne( "/sunshake", {}, "Give 1 sunshake" )
		self:rfs_bindOne( "/baguette", {}, "Give 1 revival baguette" )
		self:rfs_bindOne( "/keycard", {}, "Give 1 keycard" )
		self:rfs_bindOne( "/powercore", {}, "Give 1 powercore" )
		self:rfs_bindOne( "/components", { { "int", "quantity", true } }, "Give components (default 10)" )
		self:rfs_bindOne( "/glowsticks", { { "int", "quantity", true } }, "Give glowsticks (default 10)" )
		self:rfs_bindOne( "/foodplease", {}, "Give 5 of each edible type" )
		self:rfs_bindOne( "/seedsplease", {}, "Give seeds and soil" )
		self:rfs_bindOne( "/tumble", { { "bool", "enable", true } }, "Set tumble state" )
		self:rfs_bindOne( "/god", {}, "Mechanic characters take no damage" )
		-- /limited /unlimited: host-only bind. sm.game.setLimitedInventory is world-wide.
		if host then
			self:rfs_bindOne( "/limited", {}, "Keep world inventory limited (host)" )
			self:rfs_bindOne( "/unlimited", {}, "Host-only; world-wide flag is not applied (would unlock clients)" )
		end
		self:rfs_bindOne( "/timeofday", { { "number", "timeOfDay", true } }, "Set time of day 0..1" )
		self:rfs_bindOne( "/timeprogress", { { "bool", "enabled", true } }, "Enable or disable time progress" )

		local autocomplete = {}
		if type( g_unitSpawnNames ) == "table" then
			for k, _ in pairs( g_unitSpawnNames ) do
				autocomplete[#autocomplete + 1] = k
			end
		end
		self:rfs_bindOne( "/spawn", { { "string", "unitName", true, autocomplete }, { "int", "amount", true } }, "Spawn a unit" )
		self:rfs_bindOne( "/starterkit", { { "string", "name", true, { "start", "trashbot", "mechanic", "tutorial", "pipe", "food", "seed" } } }, "Spawn a starter kit" )
		self:rfs_bindOne( "/die", {}, "Kill the player" )
		self:rfs_bindOne( "/unstuck", {}, "Unstuck the player" )
		self:rfs_bindOne( "/sethp", { { "number", "hp", false } }, "Set player hp" )
		self:rfs_bindOne( "/setbreath", { { "number", "breath", false } }, "Set player breath" )
		self:rfs_bindOne( "/aggroall", {}, "All hostile units aware of player" )
		self:rfs_bindOne( "/stopraid", {}, "Cancel incoming raids" )
		self:rfs_bindOne( "/disableraids", { { "bool", "enabled", false } }, "Disable raids if true" )
		self:rfs_bindOne( "/noaggro", { { "bool", "enable", true } }, "Toggle player as a target" )
		self:rfs_bindOne( "/exportmultishape", {}, "Export a blueprint shape file" )

		self:rfs_bindOne( "/fly", {}, "Toggle fly mode (swim/dive freefly)" )
		self:rfs_bindOne( "/flymode", {}, "Alias of /fly" )
		self:rfs_bindOne( "/rfsfly", {}, "Alias of /fly" )
		self:rfs_bindOne( "/give", { { "string", "uuid", true }, { "int", "quantity", true } }, "Give item by UUID" )
		self:rfs_bindOne( "/farmers", { { "int", "quantity", true } }, "Give Farmers (default 10)" )
		self:rfs_bindOne( "/tshop", {}, "Open Farmers Hideout trader GUI (remote)" )
		self:rfs_bindOne( "/mshop", {}, "Open Mining Hub trader GUI (remote)" )
		self:rfs_bindOne( "/clearinv", {}, "Clear inventory" )
		self:rfs_bindOne( "/cleanup", { { "number", "radius", true } }, "Remove nearby loose bodies" )
		self:rfs_bindOne( "/killall", {}, "Destroy all units in the world" )
		self:rfs_bindOne( "/hijack", { { "number", "range", true } }, "Permanently infect nearest hostile robot (cheat)" )
		self:rfs_bindOne( "/hijacklist", {}, "Count tethered vs infected ally robots" )
		self:rfs_bindOne( "/givehack", {}, "Give Hack / Control / Infection Beacons" )
		self:rfs_bindOne( "/weather", { { "string", "name", true } }, "Print or set weather if supported" )
		self:rfs_bindOne( "/goto", { { "string", "location", true } }, "Teleport to start or marker" )
		self:rfs_bindOne( "/unlockrecipe", { { "string", "uuidOrName", false } }, "Unlock one craftbot recipe" )
		self:rfs_bindOne( "/unlockmodded", {}, "Unlock all scanned mod craftbot recipes" )
		self:rfs_bindOne( "/unlockvanilla", {}, "Unlock all vanilla unlockable craftbot recipes" )
		self:rfs_bindOne( "/questlist", {}, "List active / completed quests" )
		self:rfs_bindOne( "/rfsquestlist", {}, "Alias of /questlist" )
		self:rfs_bindOne( "/questinfo", { { "string", "name", true } }, "Short quest info" )
		self:rfs_bindOne( "/completequest", { { "string", "name", true } }, "Complete quest and grant schematic rewards" )
		self:rfs_bindOne( "/startquest", { { "string", "name", true } }, "Start / activate a quest" )
		self:rfs_bindOne( "/resetquest", { { "string", "name", true } }, "Abandon / reset quest if supported" )
	end

	self.cl.rfsCmdsBound = true
	self.cl.rfsCmdsCheatsBound = cheats
	self.cl.rfsCmdsAdminBound = admin
	self.cl.rfsCmdsHostBound = host
	if not self.cl.rfsCmdsReadyMsg then
		self.cl.rfsCmdsReadyMsg = true
		pcall( function()
			if RfsSettings.frameworkOnly() then
				sm.gui.chatMessage( "RFS framework-only: /menu /setup /gensettings /map /mods /help (cheats + quest UI OFF; hooks stay on)" )
			elseif cheats and admin then
				sm.gui.chatMessage( "RFS commands ready: /menu /setup /gensettings /map /fly /hijack /givehack /tshop /mods /help" )
			elseif cheats then
				sm.gui.chatMessage( "RFS commands ready: /menu /rfsmenu /map /mods /help (cheats host/admin only)" )
			else
				sm.gui.chatMessage( "RFS commands ready: /menu /setup /gensettings /map /mods /help (cheats OFF)" )
			end
		end )
		pcall( function()
			local title = sm.shape.getShapeTitle( sm.uuid.new( "b4e8c1a0-7d2f-4a91-9c3e-29f1a8d6b5e7" ) )
			local ok = type( title ) == "string" and title ~= "" and not string.find( string.lower( title ), "not found", 1, true )
			if not ok then
				sm.gui.chatMessage( "[RFS] Enable local mod 'RFS Beacons' in the Mods list so Hack/Control/Infection show in /unlimited." )
			end
		end )
		print( "[RFS] chat commands ready" )
	end
end

function RecipeFrameworkSurvival.bindChatCommands( self )
	-- Called by Survival clientData path when / if it reaches us.
	self:rfs_bindCommands()
end

function RecipeFrameworkSurvival.cl_onChatCommand( self, params )
	local cmd = params[1]
	local cheats = RfsSettings.cheatsEnabled()

	if cmd == "/help" or cmd == "/commands" then
		local lines
		local showCheats = cheats and rfsClientIsAdmin()
		if RfsSettings.frameworkOnly() then
			lines = {
				"RFS framework-only: /menu /setup(host) /gensettings(host) /map /mapclose /rfsmap /mods /say /d /unhijack /help",
				"Store scan + RfsQuest hooks stay on. Cheats/quest tooling forced off. Beacons/loader use /gensettings.",
			}
		elseif showCheats then
			lines = {
				"RFS: /menu /setup(host) /gensettings(host) /map /say /d /mapclose /rfsmap /fly /flymode /rfsfly /god /die /unstuck /sethp /setbreath",
				"/timeofday /timeprogress /weather /goto /spawn /give /farmers /tshop /mshop /components /ammo",
				"/foodplease /seedsplease /clearinv /cleanup /killall /hijack /hijacklist /givehack /unhijack /noaggro /aggroall",
				"/unlockrecipe /unlockmodded /unlockvanilla /mods",
				"/questlist /rfsquestlist /questinfo /completequest /startquest /resetquest /help",
				"Cheats are host/admin only. /limited /unlimited are host-only and do not unlock client inventories.",
			}
		else
			lines = {
				"RFS commands: /menu /rfsmenu /setup(admin) /gensettings(host) /map /mapclose /rfsmap /mods /say /d /unhijack /help",
				cheats and "Cheats are host/admin only." or "Toggle cheats in host /gensettings (or pack rfs_settings.json) for fly/give/quests/shops.",
			}
		end
		for _, line in ipairs( lines ) do
			sm.gui.chatMessage( line )
		end
		return
	end

	if cmd == "/menu" or cmd == "/rfsmenu" then
		rfsOpenPlayerMenu( self )
		return
	end

	if cmd == "/gensettings" then
		if not rfsClientIsHost() then
			sm.gui.chatMessage( "[RFS] /gensettings is host-only." )
			return
		end
		RfsGenGui.open( self )
		return
	end

	if cmd == "/setup" then
		if not rfsClientIsAdmin() then
			sm.gui.chatMessage( "[RFS] /setup is admin-only. Use /menu for personal options." )
			return
		end
		if RfsSettings.frameworkOnly() then
			sm.gui.chatMessage( "[RFS] Framework-only: /setup opens with cheats + Quest tab disabled. Use /menu for map + growth overlay." )
		end
		RfsSetupGui.open( self )
		return
	end

	if cmd == "/map" or cmd == "/rfsmap" then
		print( "[RFS] /map chat command received" )
		sm.gui.chatMessage( "[RFS] /map - requesting open/toggle..." )
		self.network:sendToServer( "sv_rfs_mapToggle", { player = sm.localPlayer.getPlayer() } )
		return
	end
	if cmd == "/mapclose" then
		print( "[RFS] /mapclose chat command received" )
		sm.gui.chatMessage( "[RFS] /mapclose - requesting close..." )
		self.network:sendToServer( "sv_rfs_mapClose", { player = sm.localPlayer.getPlayer() } )
		return
	end
	if cmd == "/mods" then
		self.network:sendToServer( "sv_rfs_listMods" )
		return
	end

	-- Phase D: game → Discord outbox (/say /d). Does not require cheats.
	if cmd == "/say" or cmd == "/d" then
		local parts = {}
		for i = 2, #params do
			local w = params[i]
			if w ~= nil and tostring( w ) ~= "" then
				parts[#parts + 1] = tostring( w )
			end
		end
		local text = table.concat( parts, " " )
		if text == "" then
			sm.gui.chatMessage( "[RFS] Usage: /say your message here  (needs Streamer + Discord chat relay)" )
			return
		end
		self.network:sendToServer( "sv_rfs_chatOutbox", {
			text = text,
			player = sm.localPlayer.getPlayer(),
		} )
		return
	end

	if cmd == "/unhijack" then
		sm.gui.chatMessage( "[RFS] /unhijack — releasing nearest owned ally..." )
		self.network:sendToServer( "sv_rfs_unhijack", {
			range = params[2] or 16,
			player = sm.localPlayer.getPlayer(),
		} )
		return
	end

	if cmd == "/botname" then
		local name = params[2]
		if type( name ) ~= "string" or name == "" then
			sm.gui.chatMessage( "[RFS] Usage: /botname <name>  (nearest owned ally, or E on a bot first)" )
			return
		end
		self.network:sendToServer( "sv_rfs_botRename", {
			name = name,
			player = sm.localPlayer.getPlayer(),
		} )
		return
	end

	if cmd == "/botorder" then
		local mode = params[2]
		if type( mode ) ~= "string" or mode == "" then
			sm.gui.chatMessage( "[RFS] Usage: /botorder rest|defend|stay|recall|return|farm|collect|oil|sentry" )
			return
		end
		self.network:sendToServer( "sv_rfs_botOrder", {
			mode = mode,
			player = sm.localPlayer.getPlayer(),
		} )
		return
	end

	if cmd == "/kick" or cmd == "/ban" then
		SurvivalGame.cl_onChatCommand( self, params )
		return
	end

	-- Everything below is a cheat (RFS or Survival). Host or admin only.
	if not rfsClientIsAdmin() then
		sm.gui.chatMessage( "[RFS] Cheats are host/admin only." )
		return
	end
	if not cheats then
		sm.gui.chatMessage( "[RFS] Cheats are OFF (pack or /gensettings)." )
		return
	end

	-- sm.game.setLimitedInventory is WORLD-WIDE (no per-player API). Never unlock clients.
	if cmd == "/unlimited" then
		if not rfsClientIsHost() then
			sm.gui.chatMessage( "[RFS] /unlimited is host-only." )
			return
		end
		sm.gui.chatMessage( "[RFS] /unlimited is a world-wide engine flag — not applied (would unlock all clients). Stay limited." )
		return
	end
	if cmd == "/limited" then
		if not rfsClientIsHost() then
			sm.gui.chatMessage( "[RFS] /limited is host-only." )
			return
		end
		self.network:sendToServer( "sv_setLimitedInventory", true )
		return
	end

	if cmd == "/fly" or cmd == "/flymode" or cmd == "/rfsfly" then
		self.network:sendToServer( "sv_rfs_toggleFly", { player = sm.localPlayer.getPlayer() } )
		return
	end
	if cmd == "/give" then
		self.network:sendToServer( "sv_rfs_give", { uuid = params[2], quantity = params[3] or 1 } )
		return
	end
	if cmd == "/farmers" then
		self.network:sendToServer( "sv_rfs_give", { uuid = tostring( FARMERS_UUID ), quantity = params[2] or 10 } )
		return
	end
	if cmd == "/tshop" then
		rfsClientOpenTraderShop( "g_rfsHideoutTrader", RFS_HIDEOUT_TRADER_UUID, "Farmers Hideout trader" )
		return
	end
	if cmd == "/mshop" then
		rfsClientOpenTraderShop( "g_rfsMininghubTrader", RFS_MININGHUB_TRADER_UUID, "Mining Hub trader" )
		return
	end
	if cmd == "/clearinv" then
		self.network:sendToServer( "sv_rfs_clearInv" )
		return
	end
	if cmd == "/cleanup" then
		self.network:sendToServer( "sv_rfs_cleanup", { radius = params[2] or 50 } )
		return
	end
	if cmd == "/killall" then
		self.network:sendToServer( "sv_rfs_killAll" )
		return
	end
	if cmd == "/hijack" then
		sm.gui.chatMessage( "[RFS] /hijack â€” looking for a hostile robot..." )
		self.network:sendToServer( "sv_rfs_hijack", {
			range = params[2] or 16,
			player = sm.localPlayer.getPlayer(),
		} )
		return
	end
	if cmd == "/hijacklist" then
		sm.gui.chatMessage( "[RFS] /hijacklist..." )
		self.network:sendToServer( "sv_rfs_hijackList", { player = sm.localPlayer.getPlayer() } )
		return
	end
	if cmd == "/givehack" then
		sm.gui.chatMessage( "[RFS] /givehack â€” spawning beacons..." )
		self.network:sendToServer( "sv_rfs_givehack", { player = sm.localPlayer.getPlayer() } )
		return
	end
	if cmd == "/weather" then
		self.network:sendToServer( "sv_rfs_weather", { name = params[2] } )
		return
	end
	if cmd == "/goto" then
		self.network:sendToServer( "sv_rfs_goto", { location = params[2] or "start" } )
		return
	end
	if cmd == "/unlockrecipe" then
		self.network:sendToServer( "sv_rfs_unlockRecipe", { key = params[2] } )
		return
	end
	if cmd == "/unlockmodded" then
		self.network:sendToServer( "sv_rfs_unlockModded" )
		return
	end
	if cmd == "/unlockvanilla" then
		self.network:sendToServer( "sv_rfs_unlockVanilla" )
		return
	end
	if cmd == "/questlist" or cmd == "/rfsquestlist" then
		self.network:sendToServer( "sv_rfs_questList" )
		return
	end
	if cmd == "/questinfo" then
		self.network:sendToServer( "sv_rfs_questInfo", { name = params[2] } )
		return
	end
	if cmd == "/completequest" then
		self.network:sendToServer( "sv_rfs_completeQuest", { name = params[2] } )
		return
	end
	if cmd == "/startquest" then
		self.network:sendToServer( "sv_rfs_startQuest", { name = params[2] } )
		return
	end
	if cmd == "/resetquest" then
		self.network:sendToServer( "sv_rfs_resetQuest", { name = params[2] } )
		return
	end

	SurvivalGame.cl_onChatCommand( self, params )
end

-- Survival cheat RPCs are world-wide and have no sender check. Gate host/admin here.
-- Streamer/internal calls pass player==nil; those skip the admin check on spawn only.

function RecipeFrameworkSurvival.sv_onChatCommand( self, params, player )
	local cmd = params and params[1]
	if cmd == "/kick" or cmd == "/ban" then
		if not rfsServerPlayerIsHost( player ) then
			rfsServerDenyTo( self, player, "[RFS] /kick and /ban are host-only." )
			return
		end
		SurvivalGame.sv_onChatCommand( self, params, player )
		return
	end
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	SurvivalGame.sv_onChatCommand( self, params, player )
end

function RecipeFrameworkSurvival.sv_giveItem( self, params, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	SurvivalGame.sv_giveItem( self, params )
end

function RecipeFrameworkSurvival.sv_switchGodMode( self, params, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	SurvivalGame.sv_switchGodMode( self )
end

-- sm.game.setLimitedInventory is WORLD-WIDE. Never set false (unlimited) — that unlocks every client.
-- /limited (true) is allowed for the host so the world can be locked back to limited.
function RecipeFrameworkSurvival.sv_setLimitedInventory( self, state, player )
	local unlimited = ( state == false or state == 0 )
	if unlimited then
		if player then
			rfsServerDenyTo( self, player, "[RFS] /unlimited is a world-wide engine flag — not applied (would unlock all clients). Stay limited." )
		end
		return
	end
	-- Locking to limited: host, or server-internal (starterkit / BaseWorld, player is nil).
	if player ~= nil then
		if not rfsServerPlayerIsHost( player ) then
			rfsServerDenyTo( self, player, "[RFS] /limited and /unlimited are host-only." )
			return
		end
		if not rfsServerAllowCheat( self, player ) then
			return
		end
	end
	SurvivalGame.sv_setLimitedInventory( self, true )
end

function RecipeFrameworkSurvival.sv_n_switchAggroMode( self, params, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	SurvivalGame.sv_n_switchAggroMode( self, params )
end

function RecipeFrameworkSurvival.sv_setTimeOfDay( self, timeOfDay, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	SurvivalGame.sv_setTimeOfDay( self, timeOfDay )
end

function RecipeFrameworkSurvival.sv_setTimeProgress( self, timeProgress, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	SurvivalGame.sv_setTimeProgress( self, timeProgress )
end

function RecipeFrameworkSurvival.sv_killPlayer( self, params, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	SurvivalGame.sv_killPlayer( self, params )
end

function RecipeFrameworkSurvival.sv_spawnUnit( self, params, player )
	-- Streamer vote spawn is server-internal (no RPC sender).
	if player ~= nil and not rfsServerAllowCheat( self, player ) then
		return
	end
	SurvivalGame.sv_spawnUnit( self, params )
end

-- ========== Server handlers ==========

function RecipeFrameworkSurvival.sv_rfs_toggleFly( self, params, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	local target = player
	if not target then
		return
	end
	sm.event.sendToPlayer( target, "sv_rfs_toggleFly" )
end

function RecipeFrameworkSurvival.sv_rfs_mapToggle( self, params, player )
	local target = player
	if params and params.player then
		target = params.player
	end
	target = target or sm.player.getAllPlayers()[1]
	if not target then
		print( "[RFS] /map server toggle: no player" )
		return
	end
	print( "[RFS] /map server toggle -> player" )
	sm.event.sendToPlayer( target, "sv_rfs_mapToggle" )
end

function RecipeFrameworkSurvival.sv_rfs_mapClose( self, params, player )
	local target = player
	if params and params.player then
		target = params.player
	end
	target = target or sm.player.getAllPlayers()[1]
	if not target then
		return
	end
	print( "[RFS] /mapclose server -> player" )
	sm.event.sendToPlayer( target, "sv_rfs_mapClose" )
end

function RecipeFrameworkSurvival.sv_rfs_give( self, params, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	player = player or sm.player.getAllPlayers()[1]
	if not player or not params or not params.uuid then
		rfsMsg( self, "Usage: /give <uuid> [qty]" )
		return
	end
	local ok, uuid = pcall( sm.uuid.new, tostring( params.uuid ) )
	if not ok or not uuid then
		rfsMsg( self, "Invalid UUID" )
		return
	end
	local qty = tonumber( params.quantity ) or 1
	sm.container.beginTransaction()
	sm.container.collect( player:getInventory(), uuid, qty, false )
	sm.container.endTransaction()
	rfsMsg( self, "Gave x" .. tostring( qty ) )
end

function RecipeFrameworkSurvival.sv_rfs_clearInv( self, _, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	player = player or sm.player.getAllPlayers()[1]
	if not player then return end
	local inv = player:getInventory()
	sm.container.beginTransaction()
	for i = 1, inv:getSize() do
		local item = inv:getItem( i - 1 )
		if item and item.uuid and not item.uuid:isNil() and item.quantity and item.quantity > 0 then
			sm.container.spend( inv, item.uuid, item.quantity, false )
		end
	end
	sm.container.endTransaction()
	rfsMsg( self, "Inventory cleared" )
end

function RecipeFrameworkSurvival.sv_rfs_cleanup( self, params, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	player = player or sm.player.getAllPlayers()[1]
	if not player or not player.character then return end
	local radius = tonumber( params and params.radius ) or 50
	local center = player.character.worldPosition
	local removed = 0
	local bodies = sm.body.getAllBodies()
	for _, body in ipairs( bodies ) do
		if sm.exists( body ) and body:isDynamic() then
			local pos = body.worldPosition
			if pos and ( pos - center ):length() <= radius then
				local shapes = body:getShapes()
				local onlyLoose = true
				for _, shape in ipairs( shapes ) do
					-- Keep creations that look interactable / large
					if shape:getBody():isDynamic() == false then
						onlyLoose = false
					end
				end
				if onlyLoose and #shapes <= 4 then
					for _, shape in ipairs( shapes ) do
						if sm.exists( shape ) then
							shape:destroyShape()
							removed = removed + 1
						end
					end
				end
			end
		end
	end
	rfsMsg( self, "Cleanup removed shapes~=" .. tostring( removed ) .. " r=" .. tostring( radius ) )
end

function RecipeFrameworkSurvival.sv_rfs_killAll( self, _, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	local killed = 0
	if g_unitManager and g_unitManager.sv_getAllUnits then
		local units = g_unitManager:sv_getAllUnits()
		if type( units ) == "table" then
			for _, unit in pairs( units ) do
				if sm.exists( unit ) then
					unit:destroy()
					killed = killed + 1
				end
			end
		end
	else
		-- Fallback: destroy characters that are not players
		for _, character in ipairs( sm.character.getAllCharacters() ) do
			if sm.exists( character ) and not character:isPlayer() then
				local unit = character:getUnit()
				if unit and sm.exists( unit ) then
					unit:destroy()
					killed = killed + 1
				end
			end
		end
	end
	rfsMsg( self, "Destroyed units~=" .. tostring( killed ) )
end

function RecipeFrameworkSurvival.sv_rfs_sendHijackEvent( self, event, payload )
	local trader = _G.g_rfsHideoutTraderSv
	if trader and trader.interactable and sm.exists( trader.interactable ) then
		local ok, err = pcall( function()
			sm.event.sendToInteractable( trader.interactable, event, payload )
		end )
		if ok then
			return true
		end
		rfsMsg( self, "Hijack send error: " .. tostring( err ) )
		return false
	end
	rfsMsg( self, "Hijack: hideout not loaded â€” use /tshop once, then retry" )
	return false
end

function RecipeFrameworkSurvival.sv_rfs_hijack( self, params, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	player = player or ( params and params.player ) or sm.player.getAllPlayers()[1]
	if type( RfsFeatures ) == "table" and type( RfsFeatures.hackableRobotsEnabled ) == "function" then
		local ok, on = pcall( RfsFeatures.hackableRobotsEnabled )
		if ok and not on then
			rfsMsg( self, "Hijack failed: hackable robots disabled by host" )
			return
		end
	end
	self:sv_rfs_sendHijackEvent( "sv_e_rfsHijack", { player = player, range = ( params and params.range ) or 16 } )
end

function RecipeFrameworkSurvival.sv_rfs_hijackList( self, params, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	player = player or ( params and params.player )
	self:sv_rfs_sendHijackEvent( "sv_e_rfsHijackList", { player = player } )
end

function RecipeFrameworkSurvival.sv_rfs_unhijack( self, params, player )
	player = player or ( params and params.player ) or sm.player.getAllPlayers()[1]
	local allowAny = rfsServerPlayerIsHost( player )
	self:sv_rfs_sendHijackEvent( "sv_e_rfsUnhijack", {
		player = player,
		range = ( params and params.range ) or 16,
		allowAny = allowAny,
	} )
end

function RecipeFrameworkSurvival.sv_rfs_botRenameLook( self, params, player )
	params = params or {}
	player = player or params.player
	if not player then
		return
	end
	self.sv = self.sv or {}
	self.sv.rfsRenameLook = self.sv.rfsRenameLook or {}
	local pid = nil
	pcall( function() pid = player.id end )
	local unitKey = params.unitKey and tostring( params.unitKey ) or nil
	if pid then
		self.sv.rfsRenameLook[pid] = unitKey
	end
	local name = ""
	if unitKey and type( RfsBotHijack ) == "table" and RfsBotHijack.allies then
		local info = RfsBotHijack.allies[unitKey]
		if info then
			name = tostring( info.customName or info.displayName or "" )
		end
	end
	self.network:sendToClient( player, "cl_rfs_botRenameOpen", {
		unitKey = unitKey,
		name = name,
	} )
end

function RecipeFrameworkSurvival.cl_rfs_botRenameOpen( self, data )
	data = data or {}
	self.cl = self.cl or {}
	self.cl.rfsRenameUnitKey = data.unitKey
	if self.cl.rfsRenameGui then
		pcall( function() self.cl.rfsRenameGui:close() end )
		self.cl.rfsRenameGui = nil
	end
	local ok, gui = pcall( sm.gui.createGuiFromLayout, "$CONTENT_DATA/Gui/Layouts/Rfs_BotRename.layout" )
	if not ok or not gui then
		sm.gui.chatMessage( "[RFS] Type /botname <name> to rename this bot." )
		return
	end
	self.cl.rfsRenameGui = gui
	pcall( function()
		gui:setText( "NameEdit", tostring( data.name or "" ) )
		gui:setButtonCallback( "CloseButton", "cl_rfs_botRenameClose" )
		gui:setButtonCallback( "BtnApply", "cl_rfs_botRenameApply" )
		gui:setOnCloseCallback( "cl_rfs_botRenameClose" )
		gui:open()
	end )
end

function RecipeFrameworkSurvival.cl_rfs_botRenameClose( self )
	local gui = self.cl and self.cl.rfsRenameGui
	if gui then
		pcall( function() gui:close() end )
	end
	if self.cl then
		self.cl.rfsRenameGui = nil
	end
end

function RecipeFrameworkSurvival.cl_rfs_botRenameApply( self )
	local gui = self.cl and self.cl.rfsRenameGui
	local name = ""
	pcall( function()
		name = gui:getText( "NameEdit" )
	end )
	self.network:sendToServer( "sv_rfs_botRename", {
		name = name,
		unitKey = self.cl and self.cl.rfsRenameUnitKey,
		player = sm.localPlayer.getPlayer(),
	} )
	self:cl_rfs_botRenameClose()
end

function RecipeFrameworkSurvival.sv_rfs_botRename( self, params, player )
	params = params or {}
	player = player or params.player
	if not player then
		return
	end
	local allowHost = rfsServerPlayerIsHost( player )
	local name = tostring( params.name or "" )
	local unitKey = params.unitKey and tostring( params.unitKey ) or nil
	if ( not unitKey or unitKey == "" ) and self.sv and self.sv.rfsRenameLook then
		local pid = nil
		pcall( function() pid = player.id end )
		unitKey = pid and self.sv.rfsRenameLook[pid] or nil
	end
	local ok, result = false, "no bot"
	if unitKey and unitKey ~= "" and type( RfsBotHijack ) == "table" and RfsBotHijack.setCustomName then
		ok, result = RfsBotHijack.setCustomName( unitKey, name, player, allowHost )
	elseif type( RfsBotHijack ) == "table" and RfsBotHijack.convertNearest then
		-- Nearest owned ally in 16 m.
		local best, bestD2 = nil, nil
		local origin = nil
		pcall( function()
			origin = player.character.worldPosition
		end )
		if origin and RfsBotHijack.allies then
			for key, info in pairs( RfsBotHijack.allies ) do
				if info and info.controlled then
					local isOwner = tostring( info.owner ) == tostring( player.id )
					if isOwner or allowHost then
						local u = RfsBotHijack.unitByKey( key )
						if u and sm.exists( u ) and u.character then
							local d2 = ( u.character.worldPosition - origin ):length2()
							if d2 <= 16 * 16 and ( bestD2 == nil or d2 < bestD2 ) then
								best = key
								bestD2 = d2
							end
						end
					end
				end
			end
		end
		if best then
			ok, result = RfsBotHijack.setCustomName( best, name, player, allowHost )
		end
	end
	pcall( function()
		self.network:sendToClient( player, "client_showMessage", ok and ( "[RFS] Named: " .. tostring( result ) ) or ( "[RFS] Rename failed: " .. tostring( result ) ) )
	end )
end

function RecipeFrameworkSurvival.sv_rfs_botOrder( self, params, player )
	params = params or {}
	player = player or params.player
	if not player then
		return
	end
	local allowHost = rfsServerPlayerIsHost( player )
	local mode = tostring( params.mode or "rest" )
	local origin = nil
	pcall( function()
		origin = player.character.worldPosition
	end )
	local best, bestD2 = nil, nil
	if origin and type( RfsBotHijack ) == "table" and RfsBotHijack.allies then
		for key, info in pairs( RfsBotHijack.allies ) do
			if info and info.controlled then
				local isOwner = tostring( info.owner ) == tostring( player.id )
				if isOwner or allowHost then
					local u = RfsBotHijack.unitByKey( key )
					if u and sm.exists( u ) and u.character then
						local d2 = ( u.character.worldPosition - origin ):length2()
						if d2 <= 32 * 32 and ( bestD2 == nil or d2 < bestD2 ) then
							best = key
							bestD2 = d2
						end
					end
				end
			end
		end
	end
	local ok, result = false, "no nearby ally"
	if best and type( RfsBotHijack ) == "table" and RfsBotHijack.setOrder then
		ok, result = RfsBotHijack.setOrder( best, { mode = mode }, player, allowHost )
	end
	pcall( function()
		self.network:sendToClient( player, "client_showMessage", ok and ( "[RFS] /botorder " .. mode ) or ( "[RFS] /botorder failed: " .. tostring( result ) ) )
	end )
end

function RecipeFrameworkSurvival.sv_rfs_givehack( self, params, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	player = player or ( params and params.player ) or sm.player.getAllPlayers()[1]
	if not player then
		rfsMsg( self, "Givehack failed: no player" )
		return
	end
	local inv = nil
	pcall( function()
		inv = player:getInventory()
	end )
	if not inv or not sm.exists( inv ) then
		rfsMsg( self, "Givehack failed: no inventory" )
		return
	end
	local uuids = {
		"b4e8c1a0-7d2f-4a91-9c3e-29f1a8d6b5e7",
		"c5f9d2b1-8e30-4ba2-ad4f-30a2b9e7c6f8",
		"d6a0e3c2-9f41-4cb3-be50-41b3c0f8d709",
	}
	local given, failed = 0, {}
	sm.container.beginTransaction()
	for _, id in ipairs( uuids ) do
		local okU, uuid = pcall( sm.uuid.new, id )
		if okU and uuid then
			local okC = pcall( sm.container.collect, inv, uuid, 1, false )
			if okC then
				given = given + 1
			else
				failed[#failed + 1] = id
			end
		else
			failed[#failed + 1] = id
		end
	end
	local okEnd = pcall( sm.container.endTransaction )
	if given > 0 and okEnd then
		rfsMsg( self, "Gave " .. tostring( given ) .. " beacon(s). Wire a Battery container. Optional switch." )
	else
		rfsMsg( self, "Givehack collected 0 â€” enable local Blocks & Parts mod 'RFS Beacons' in the world Mods list, then reload. failed=" .. tostring( #failed ) )
	end
end

function RecipeFrameworkSurvival.sv_rfs_weather( self, params, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	local wm = WeatherManager and WeatherManager.Get and WeatherManager.Get()
	if not wm then
		rfsMsg( self, "WeatherManager not available" )
		return
	end
	local name = params and params.name
	if name and wm.sv_setWeather then
		pcall( function() wm:sv_setWeather( name ) end )
		rfsMsg( self, "Weather set: " .. tostring( name ) )
	elseif name and wm.sv_e_setWeather then
		pcall( function() wm:sv_e_setWeather( name ) end )
		rfsMsg( self, "Weather set: " .. tostring( name ) )
	else
		rfsMsg( self, "Weather active (pass a name to try set). /timeofday still works." )
	end
end

function RecipeFrameworkSurvival.sv_rfs_goto( self, params, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	player = player or sm.player.getAllPlayers()[1]
	if not player or not player.character then return end
	local loc = string.lower( tostring( params and params.location or "start" ) )
	local destinations = {
		start = START_AREA_SPAWN_POINT,
		marker = SURVIVAL_DEV_SPAWN_POINT,
	}
	local pos = destinations[loc]
	if not pos and self.sv and self.sv.gotoLocations then
		-- Named player destinations are registered as lowercase names; no coords without Survival internals.
	end
	if not pos then
		rfsMsg( self, "Goto locations with coords: start, marker. Got: " .. loc )
		return
	end
	player.character:setWorldPosition( pos )
	rfsMsg( self, "Goto " .. loc )
end

function RecipeFrameworkSurvival.sv_rfs_unlockRecipe( self, params, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	local key = params and params.key
	if not key then
		rfsMsg( self, "Usage: /unlockrecipe <uuid|name>" )
		return
	end
	key = tostring( key )
	local uuid = key
	if ITEMS and ITEMS[key] then
		uuid = tostring( ITEMS[key] )
	end
	-- Fuzzy: match unlockable craft items by substring of uuid
	if g_unlockableCraftItems and not g_unlockableCraftItems[uuid] then
		for id, _ in pairs( g_unlockableCraftItems ) do
			if string.find( id, key, 1, true ) then
				uuid = id
				break
			end
		end
	end
	RecipeManager.Sv_UnlockRecipe( uuid )
	rfsMsg( self, "Unlocked " .. uuid )
end

function RecipeFrameworkSurvival.sv_rfs_unlockModded( self, _, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	local scan = ModRecipeScan.getLast()
	local n = 0
	if scan and scan.craftPaths then
		for _, path in ipairs( scan.craftPaths ) do
			local ok, json = pcall( sm.json.open, path )
			if ok and type( json ) == "table" then
				for _, recipe in ipairs( json ) do
					if recipe and recipe.itemId then
						RecipeManager.Sv_UnlockRecipe( tostring( recipe.itemId ), true )
						n = n + 1
					end
				end
			end
		end
	end
	rfsMsg( self, "Unlocked modded recipes: " .. tostring( n ) )
end

function RecipeFrameworkSurvival.sv_rfs_unlockVanilla( self, _, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	local n = 0
	if g_unlockableCraftItems then
		local scan = ModRecipeScan.getLast()
		local modIds = {}
		if scan and scan.craftPaths then
			for _, path in ipairs( scan.craftPaths ) do
				local ok, json = pcall( sm.json.open, path )
				if ok and type( json ) == "table" then
					for _, recipe in ipairs( json ) do
						if recipe and recipe.itemId then
							modIds[tostring( recipe.itemId )] = true
						end
					end
				end
			end
		end
		for id, _ in pairs( g_unlockableCraftItems ) do
			if not modIds[id] then
				RecipeManager.Sv_UnlockRecipe( id, true )
				n = n + 1
			end
		end
	end
	rfsMsg( self, "Unlocked vanilla unlockables: " .. tostring( n ) )
end

function RecipeFrameworkSurvival.sv_rfs_listMods( self )
	local scan = ModRecipeScan.getLast() or ModRecipeScan.run()
	rfsMsg( self, string.format(
		"RFS catalog=%d loaded=%d scanned=%d sources=%d craft=%d hide+=%d mine+=%d loot=%d",
		scan.modsCatalog or 0, scan.modsLoaded or 0, scan.modsScanned or 0,
		#( scan.sources or {} ), scan.craftRecipeCount or 0,
		scan.hideoutAdded or 0, scan.miningAdded or 0, scan.lootApplied or 0
	) )
	for _, s in ipairs( scan.sources or {} ) do
		rfsMsg( self, string.format(
			" - %s craft=%d hide=%d mine=%d loot=%d",
			s.name, s.craft, s.hideout, s.mining, s.loot
		) )
	end
end

function RecipeFrameworkSurvival.sv_rfs_chatOutbox( self, params, player )
	local text = ""
	if type( params ) == "table" then
		text = tostring( params.text or params.msg or params.message or "" )
		if ( not player or not sm.exists( player ) ) and params.player then
			player = params.player
		end
	end
	if type( RfsChatOutbox ) == "table" and RfsChatOutbox.sv_fromPlayer then
		RfsChatOutbox.sv_fromPlayer( self, player, text )
	end
end

function RecipeFrameworkSurvival.sv_rfs_questList( self, _, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	local active = QuestManager.Sv_GetActiveQuests and QuestManager.Sv_GetActiveQuests() or {}
	local completed = {}
	if g_questManagerServer and g_questManagerServer.sv and g_questManagerServer.sv.saved then
		completed = g_questManagerServer.sv.saved.completedQuests or {}
	end
	rfsMsg( self, "=== Active quests ===" )
	local acount = 0
	if type( active ) == "table" then
		for name, _ in pairs( active ) do
			rfsMsg( self, " * " .. tostring( name ) )
			acount = acount + 1
		end
	end
	if acount == 0 then
		rfsMsg( self, " (none)" )
	end
	rfsMsg( self, "=== Completed ===" )
	if type( completed ) == "table" and #completed > 0 then
		for _, name in ipairs( completed ) do
			rfsMsg( self, " * " .. tostring( name ) )
		end
	else
		rfsMsg( self, " (none)" )
	end
	-- Available = known quest data keys not active/complete (best-effort)
	if g_questManagerServer and g_questManagerServer.sv and g_questManagerServer.sv.questData then
		rfsMsg( self, "=== Available (not active/complete) ===" )
		local done = {}
		for _, name in ipairs( completed ) do done[name] = true end
		local shown = 0
		for name, _ in pairs( g_questManagerServer.sv.questData ) do
			if not done[name] and not ( active and active[name] ) then
				rfsMsg( self, " * " .. tostring( name ) )
				shown = shown + 1
				if shown >= 40 then
					rfsMsg( self, " ... truncated" )
					break
				end
			end
		end
	end
end

function RecipeFrameworkSurvival.sv_rfs_questInfo( self, params, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	local name = params and params.name
	if not name then
		rfsMsg( self, "Usage: /questinfo <name>" )
		return
	end
	name = tostring( name )
	local active = QuestManager.Sv_IsQuestActive( name )
	local complete = QuestManager.Sv_IsQuestComplete( name )
	local title = QuestManager.Sv_GetQuestTitle and QuestManager.Sv_GetQuestTitle( name ) or name
	local stage = QuestManager.Sv_GetQuestStage and QuestManager.Sv_GetQuestStage( name ) or nil
	rfsMsg( self, string.format( "%s | title=%s active=%s complete=%s stage=%s",
		name, tostring( title ), tostring( active ), tostring( complete ), tostring( stage ) ) )
	local rewards = QuestManager.Sv_GetQuestRewards and QuestManager.Sv_GetQuestRewards( name ) or nil
	if type( rewards ) == "table" then
		for _, reward in pairs( rewards ) do
			if type( reward ) == "table" then
				rfsMsg( self, " reward: " .. tostring( reward.type or "?" ) .. " " .. tostring( reward.name or reward.item or "" ) )
			end
		end
	end
end

function RecipeFrameworkSurvival.sv_rfs_completeQuest( self, params, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	local name = params and params.name
	if not name then
		rfsMsg( self, "Usage: /completequest <name>" )
		return
	end
	name = tostring( name )

	local wasActive = QuestManager.Sv_IsQuestActive( name ) and true or false
	local wasComplete = QuestManager.Sv_IsQuestComplete( name ) and true or false

	-- Same entry Survival quest scripts use to mark complete (notification + destroy active SO).
	QuestManager.Sv_CompleteQuest( name )
	if not wasComplete and not QuestManager.Sv_IsQuestComplete( name ) then
		rfsForceMarkComplete( name )
	end

	-- Survival CompleteQuest reward path (schematics / logs / additional item popups).
	local schematicCount, logCount, otherCount = rfsGrantQuestRewards( self, name )

	-- Tutorial Ã¢â€ â€™ mechanic station: vanilla grants log mid-quest (not via quest rewards) and
	-- highlights it so the logbook waypoint can be set. Cheat DONE skips those stages.
	local logNote = ""
	if name == "quest_tutorial" then
		local logUuid = rfsGrantTutorialStationLog()
		logNote = " | log_mechanicstation granted+highlighted (" .. tostring( logUuid ) .. ")"
	end

	local nextName = RFS_QUEST_NEXT[name]
	local nextNote = "none"
	if nextName then
		if QuestManager.Sv_IsQuestComplete( nextName ) then
			nextNote = nextName .. " (already complete â€” not activated)"
		elseif QuestManager.Sv_IsQuestActive( nextName ) then
			rfsForceTrackQuest( nextName )
			nextNote = nextName .. " (already active â€” forced tracker/markers)"
		else
			-- Do NOT call TryActivateQuest in the same frame as CompleteQuest: client main-quest
			-- tracker still holds the previous quest, so Cl_OnQuestCreated skips auto-track and
			-- MechanicStationQuest markers never show. Mirror Survival CompleteQuest instead.
			local ok, result = pcall( rfsQueueNextQuestActivation, self, name, nextName )
			if ok then
				nextNote = string.format(
					"%s (Survival delayed activator in %s ticks â€” tracker/markers follow)",
					nextName,
					tostring( result )
				)
			else
				-- Fallback: direct activate + forced track (still better than silent failure).
				pcall( function() QuestManager.Sv_ActivateQuest( nextName ) end )
				rfsForceTrackQuest( nextName )
				nextNote = nextName .. " (direct activate+track; delayed activator failed: " .. tostring( result ) .. ")"
			end
		end
	else
		nextNote = "none (no RFS_QUEST_NEXT entry)"
	end

	rfsMsg( self, string.format(
		"Completed %s (wasActive=%s) rewards: schematics=%d logs=%d items=%d | next=%s%s",
		name,
		tostring( wasActive ),
		schematicCount or 0,
		logCount or 0,
		otherCount or 0,
		nextNote,
		logNote
	) )
	if name == "quest_tutorial" and nextName == "quest_mechanicstation" then
		rfsMsg( self, "Open Logbook Ã¢â€ â€™ Mechanic Station log Ã¢â€ â€™ Set Waypoint for the compass marker (vanilla tutorial path)." )
	end
end

function RecipeFrameworkSurvival.sv_rfs_startQuest( self, params, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	local name = params and params.name
	if not name then
		rfsMsg( self, "Usage: /startquest <name>" )
		return
	end
	name = tostring( name )
	if QuestManager.Sv_IsQuestComplete( name ) then
		rfsMsg( self, "Cannot start " .. name .. " â€” already complete" )
		return
	end
	if QuestManager.Sv_IsQuestActive( name ) then
		rfsForceTrackQuest( name )
		rfsMsg( self, "Already active â€” forced tracker: " .. name )
		return
	end
	QuestManager.Sv_TryActivateQuest( name )
	rfsForceTrackQuest( name )
	rfsMsg( self, "Tried start + track " .. name )
end

function RecipeFrameworkSurvival.sv_rfs_resetQuest( self, params, player )
	if not rfsServerAllowCheat( self, player ) then
		return
	end
	local name = params and params.name
	if not name then
		rfsMsg( self, "Usage: /resetquest <name> - QuestManager has no public reset; abandoning if active." )
		return
	end
	name = tostring( name )
	if QuestManager.Sv_IsQuestActive( name ) then
		QuestManager.Sv_TryAbandonQuest( name )
		rfsMsg( self, "Abandoned (closest to reset): " .. name )
	else
		rfsMsg( self, "resetquest N/A for inactive/completed quests (no QuestManager.Sv_ResetQuest)." )
	end
end

-- ========== /setup GUI client callbacks ==========

function RecipeFrameworkSurvival.cl_rfs_setupClose( self )
	RfsSetupGui.close( self )
end

function RecipeFrameworkSurvival.cl_rfs_setupTabMain( self )
	RfsSetupGui.showTab( self, "main" )
end

function RecipeFrameworkSurvival.cl_rfs_setupTabQuest( self )
	if not RfsSettings.questTabEnabled() then
		sm.gui.chatMessage( "[RFS] Quest tab disabled (rfs_settings.json setupQuestTab=false)" )
		RfsSetupGui.showTab( self, "main" )
		return
	end
	RfsSetupGui.showTab( self, "quest" )
end

function RecipeFrameworkSurvival.cl_rfs_setupTabInvSize( self )
	if not RfsSettings.cheatsEnabled() then
		sm.gui.chatMessage( "[RFS] Inventory size tab requires cheats ON" )
		RfsSetupGui.showTab( self, "main" )
		return
	end
	RfsSetupGui.showTab( self, "invsize" )
end

function RecipeFrameworkSurvival.cl_rfs_setupTabFarming( self )
	RfsSetupGui.showTab( self, "farming" )
end

function RecipeFrameworkSurvival.cl_rfs_setupInstantFarm( self )
	if not RfsSettings.cheatsEnabled() then
		sm.gui.chatMessage( "[RFS] Instant Farm requires cheats ON" )
		return
	end
	self.network:sendToServer( "sv_rfs_farmingInstant" )
end

function RecipeFrameworkSurvival.cl_rfs_setupToggleAlwaysWatered( self )
	if not RfsSettings.cheatsEnabled() then
		sm.gui.chatMessage( "[RFS] Always watered requires cheats ON" )
		return
	end
	self.network:sendToServer( "sv_rfs_farmingSet", { toggle = "alwaysWatered" } )
end

function RecipeFrameworkSurvival.cl_rfs_setupToggleDirtOnBlocks( self )
	if not RfsSettings.cheatsEnabled() then
		sm.gui.chatMessage( "[RFS] Dirt on blocks requires cheats ON" )
		return
	end
	self.network:sendToServer( "sv_rfs_farmingSet", { toggle = "dirtOnBlocks" } )
end

-- ========== /menu GUI client callbacks ==========

function RecipeFrameworkSurvival.cl_rfs_menuClose( self )
	if type( RfsMenuGui ) == "table" then
		RfsMenuGui.close( self )
	end
end

function RecipeFrameworkSurvival.cl_rfs_menuMap( self )
	if type( RfsMenuGui ) == "table" then
		RfsMenuGui.close( self )
	end
	print( "[RFS] /menu Map button" )
	sm.gui.chatMessage( "[RFS] /map - requesting open/toggle..." )
	self.network:sendToServer( "sv_rfs_mapToggle", { player = sm.localPlayer.getPlayer() } )
end

function RecipeFrameworkSurvival.cl_rfs_menuToggleGrowthOverlay( self )
	self.network:sendToServer( "sv_rfs_toggleGrowthOverlay", { player = sm.localPlayer.getPlayer() } )
end

function RecipeFrameworkSurvival.sv_rfs_toggleGrowthOverlay( self, params, player )
	local target = player
	if params and params.player then
		target = params.player
	end
	target = target or sm.player.getAllPlayers()[1]
	if not target then
		return
	end
	sm.event.sendToPlayer( target, "sv_rfs_toggleGrowthOverlay" )
end

function RecipeFrameworkSurvival.cl_rfs_farmingSync( self, data )
	self.cl = self.cl or {}
	RfsFarming.cl_applyState( data )
	local snap = RfsFarming.snapshot()
	self.cl.rfsAlwaysWatered = snap.alwaysWatered
	self.cl.rfsDirtOnBlocks = snap.dirtOnBlocks
	-- Growth overlay is per-player; do not overwrite from world farming sync.
	if self.cl.rfsSetupGui and self.cl.rfsSetupTab == "farming" then
		RfsSetupGui.refreshFarming( self )
	end
	if data and data.msg then
		sm.gui.chatMessage( "[RFS] " .. tostring( data.msg ) )
	end
end

function RecipeFrameworkSurvival.sv_rfs_farmingBroadcast( self, msg )
	local payload = RfsFarming.snapshot()
	if msg then
		payload.msg = msg
	end
	self.network:sendToClients( "cl_rfs_farmingSync", payload )
end

function RecipeFrameworkSurvival.sv_rfs_farmingGet( self, _, player )
	player = player or sm.player.getAllPlayers()[1]
	if not player then return end
	local payload = RfsFarming.snapshot()
	self.network:sendToClient( player, "cl_rfs_farmingSync", payload )
end

function RecipeFrameworkSurvival.sv_rfs_farmingSet( self, params, player )
	player = player or sm.player.getAllPlayers()[1]
	if not rfsServerPlayerIsHost( player ) then
		return
	end
	local toggle = params and params.toggle
	local cfg = RfsFarming.get()
	local msg = nil

	if toggle == "alwaysWatered" or toggle == "dirtOnBlocks" then
		if not RfsSettings.cheatsEnabled() then
			if player then
				self.network:sendToClient( player, "cl_rfs_farmingSync", RfsFarming.snapshot() )
			end
			return
		end
	end

	if toggle == "alwaysWatered" then
		cfg.alwaysWatered = not cfg.alwaysWatered
		msg = "Always watered: " .. ( cfg.alwaysWatered and "ON" or "OFF" )
		if cfg.alwaysWatered then
			RfsFarming.sv_waterAll( self )
		end
	elseif toggle == "dirtOnBlocks" then
		cfg.dirtOnBlocks = not cfg.dirtOnBlocks
		msg = "Dirt on blocks: " .. ( cfg.dirtOnBlocks and "True" or "False" )
	elseif toggle == "growthOverlay" then
		-- Legacy: growth overlay moved to per-player /menu.
		if player then
			sm.event.sendToPlayer( player, "sv_rfs_toggleGrowthOverlay" )
		end
		return
	else
		return
	end

	RfsFarming.save()
	self:sv_rfs_farmingBroadcast( msg )
end

function RecipeFrameworkSurvival.sv_rfs_farmingInstant( self, _, player )
	player = player or sm.player.getAllPlayers()[1]
	if not rfsServerPlayerIsHost( player ) then
		return
	end
	if not RfsSettings.cheatsEnabled() then
		if player then
			local payload = RfsFarming.snapshot()
			payload.msg = "Cheats OFF â€” Instant Farm locked"
			self.network:sendToClient( player, "cl_rfs_farmingSync", payload )
		end
		return
	end
	local count = RfsFarming.sv_instantFarm( self )
	local msg = string.format( "Instant Farm matured ~%d growing crop(s) in loaded cells", count )
	rfsMsg( self, msg )
	if player then
		local payload = RfsFarming.snapshot()
		payload.msg = msg
		self.network:sendToClient( player, "cl_rfs_farmingSync", payload )
	end
end

function RecipeFrameworkSurvival.cl_rfs_setupInvSizeSelect( self, widgetName )
	if not RfsSettings.cheatsEnabled() then return end
	local idx = tonumber( string.match( tostring( widgetName or "" ), "(%d+)$" ) )
	if idx == nil then return end
	local opt = RfsInventory.OPTIONS[idx + 1]
	if not opt then return end
	self.network:sendToServer( "sv_rfs_invSizeSet", { id = opt.id } )
end

function RecipeFrameworkSurvival.cl_rfs_invSizeSync( self, data )
	self.cl = self.cl or {}
	self.cl.rfsInvSizeId = ( data and data.id ) or "vanilla"
	if self.cl.rfsSetupGui and self.cl.rfsSetupTab == "invsize" then
		RfsSetupGui.refreshInvSize( self )
	end
	if data and data.msg then
		sm.gui.chatMessage( "[RFS] " .. tostring( data.msg ) )
	end
end

function RecipeFrameworkSurvival.sv_rfs_invSizeGet( self, _, player )
	player = player or sm.player.getAllPlayers()[1]
	if not player then return end
	local id = RfsInventory.getSavedOptionId()
	self.network:sendToClient( player, "cl_rfs_invSizeSync", { id = id } )
end

function RecipeFrameworkSurvival.sv_rfs_invSizeSet( self, params, player )
	-- Host-only world inventory size.
	if not player then
		local all = nil
		pcall( function() all = sm.player.getAllPlayers() end )
		if type( all ) == "table" then
			for _, p in pairs( all ) do
				player = p
				break
			end
		end
	end
	if not player then return end
	if not rfsServerPlayerIsHost( player ) then
		return
	end
	if not RfsSettings.cheatsEnabled() then
		self.network:sendToClient( player, "cl_rfs_invSizeSync", {
			id = RfsInventory.getSavedOptionId(),
			msg = "Cheats OFF - inventory size locked"
		} )
		return
	end
	local id = params and params.id or "vanilla"
	local opt = RfsInventory.saveOptionId( id )
	RfsInventory.applyGameDefault( RecipeFrameworkSurvival )
	-- World setting: resize every connected player's personal inventory (host included).
	local applied, _, found = RfsInventory.applyToAllPlayers( opt.id, player )
	print( "[RFS] invSizeSet " .. opt.id .. " found=" .. tostring( found ) .. " applied=" .. tostring( applied ) )
	self.network:sendToClients( "cl_rfs_invSizeSync", {
		id = opt.id,
		msg = string.format( "Inventory %d slots applied to %d player(s)", opt.slots, applied )
	} )
end

function RecipeFrameworkSurvival.cl_rfs_setupToggleInventory( self )
	if not RfsSettings.cheatsEnabled() then return end
	if not rfsClientIsHost() then
		sm.gui.chatMessage( "[RFS] Inventory limited/unlimited is host-only." )
		return
	end
	local limited = true
	pcall( function() limited = sm.game.getLimitedInventory() end )
	if limited then
		-- World-wide flag: do not unlock every client.
		sm.gui.chatMessage( "[RFS] Unlimited inventory is a world-wide engine flag — not applied (would unlock all clients)." )
		return
	end
	self.network:sendToServer( "sv_setLimitedInventory", true )
	self.cl = self.cl or {}
	self.cl.rfsSetupRefreshAt = sm.game.getCurrentTick() + 8
end

function RecipeFrameworkSurvival.cl_rfs_setupToggleFly( self )
	if not RfsSettings.cheatsEnabled() then return end
	self.network:sendToServer( "sv_rfs_toggleFly", { player = sm.localPlayer.getPlayer() } )
	self.cl = self.cl or {}
	self.cl.rfsSetupRefreshAt = sm.game.getCurrentTick() + 8
end

function RecipeFrameworkSurvival.cl_rfs_setupToggleGod( self )
	if not RfsSettings.cheatsEnabled() then return end
	self.network:sendToServer( "sv_switchGodMode" )
	self.cl = self.cl or {}
	self.cl.rfsSetupRefreshAt = sm.game.getCurrentTick() + 8
end

function RecipeFrameworkSurvival.cl_rfs_setupQuestRefresh( self )
	self.network:sendToServer( "sv_rfs_setupQuestData" )
end

function RecipeFrameworkSurvival.cl_rfs_setupQuestPrev( self )
	self.cl = self.cl or {}
	self.cl.rfsQuestPage = math.max( 0, ( self.cl.rfsQuestPage or 0 ) - 1 )
	RfsSetupGui.refreshQuest( self )
end

function RecipeFrameworkSurvival.cl_rfs_setupQuestNext( self )
	self.cl = self.cl or {}
	self.cl.rfsQuestPage = ( self.cl.rfsQuestPage or 0 ) + 1
	RfsSetupGui.refreshQuest( self )
end

function RecipeFrameworkSurvival.cl_rfs_setupQuestSelect( self, widgetName )
	local row = RfsSetupGui.rowFromWidget( self, widgetName )
	if not row then return end
	RfsSetupGui.setDetail( self, string.format( "Selected: %s\nStatus: %s\nUse INFO / START / DONE.", row.name, row.status ) )
end

function RecipeFrameworkSurvival.cl_rfs_setupQuestInfo( self, widgetName )
	local row = RfsSetupGui.rowFromWidget( self, widgetName )
	if not row then return end
	self.network:sendToServer( "sv_rfs_setupQuestInfo", { name = row.name } )
end

function RecipeFrameworkSurvival.cl_rfs_setupQuestStart( self, widgetName )
	local row = RfsSetupGui.rowFromWidget( self, widgetName )
	if not row then return end
	self.network:sendToServer( "sv_rfs_startQuest", { name = row.name } )
	self.network:sendToServer( "sv_rfs_setupQuestData" )
end

function RecipeFrameworkSurvival.cl_rfs_setupQuestDone( self, widgetName )
	local row = RfsSetupGui.rowFromWidget( self, widgetName )
	if not row then return end
	self.network:sendToServer( "sv_rfs_completeQuest", { name = row.name } )
	self.network:sendToServer( "sv_rfs_setupQuestData" )
end

function RecipeFrameworkSurvival.cl_rfs_setupQuestData( self, data )
	self.cl = self.cl or {}
	self.cl.rfsQuestData = data or { active = {}, completed = {}, available = {} }
	if self.cl.rfsSetupGui then
		RfsSetupGui.refreshQuest( self )
	end
end

function RecipeFrameworkSurvival.cl_rfs_setupQuestInfoResult( self, text )
	RfsSetupGui.setDetail( self, text )
end

-- ========== /setup server ==========

function RecipeFrameworkSurvival.sv_rfs_setupQuestData( self, _, player )
	player = player or sm.player.getAllPlayers()[1]
	if not player then return end
	if not rfsServerPlayerIsHost( player ) then
		return
	end

	local active = {}
	local activeMap = QuestManager.Sv_GetActiveQuests and QuestManager.Sv_GetActiveQuests() or {}
	if type( activeMap ) == "table" then
		for name, _ in pairs( activeMap ) do
			active[#active + 1] = tostring( name )
		end
	end

	local completed = {}
	if g_questManagerServer and g_questManagerServer.sv and g_questManagerServer.sv.saved then
		local c = g_questManagerServer.sv.saved.completedQuests or {}
		if type( c ) == "table" then
			for _, name in ipairs( c ) do
				completed[#completed + 1] = tostring( name )
			end
			-- also support map-style
			if #completed == 0 then
				for name, _ in pairs( c ) do
					if type( name ) == "string" then
						completed[#completed + 1] = name
					end
				end
			end
		end
	end

	local done = {}
	for _, n in ipairs( completed ) do done[n] = true end
	local activeSet = {}
	for _, n in ipairs( active ) do activeSet[n] = true end

	local available = {}
	if g_questManagerServer and g_questManagerServer.sv and g_questManagerServer.sv.questData then
		for name, _ in pairs( g_questManagerServer.sv.questData ) do
			local n = tostring( name )
			if not done[n] and not activeSet[n] then
				available[#available + 1] = n
			end
		end
	end

	self.network:sendToClient( player, "cl_rfs_setupQuestData", {
		active = active,
		completed = completed,
		available = available
	} )
end

function RecipeFrameworkSurvival.sv_rfs_setupQuestInfo( self, params, player )
	player = player or sm.player.getAllPlayers()[1]
	if not rfsServerPlayerIsHost( player ) then
		return
	end
	local name = params and params.name
	if not name then
		return
	end
	name = tostring( name )
	local active = QuestManager.Sv_IsQuestActive( name )
	local complete = QuestManager.Sv_IsQuestComplete( name )
	local title = QuestManager.Sv_GetQuestTitle and QuestManager.Sv_GetQuestTitle( name ) or name
	local stage = QuestManager.Sv_GetQuestStage and QuestManager.Sv_GetQuestStage( name ) or nil
	local lines = {
		string.format( "%s", name ),
		string.format( "title=%s", tostring( title ) ),
		string.format( "active=%s  complete=%s  stage=%s", tostring( active ), tostring( complete ), tostring( stage ) ),
	}
	local rewards = nil
	pcall( function() rewards = QuestManager.Sv_GetQuestRewards( name ) end )
	if type( rewards ) == "table" then
		for _, reward in pairs( rewards ) do
			if type( reward ) == "table" then
				lines[#lines + 1] = "reward: " .. tostring( reward.type or "?" ) .. " " .. tostring( reward.name or reward.item or "" )
			end
		end
	end
	self.network:sendToClient( player, "cl_rfs_setupQuestInfoResult", table.concat( lines, "\n" ) )
end

-- ========== /gensettings GUI + world feature flags ==========

function RecipeFrameworkSurvival.cl_rfs_genClose( self )
	RfsGenGui.close( self )
end

function RecipeFrameworkSurvival.cl_rfs_genTabMain( self )
	RfsGenGui.showTab( self, "main" )
end

function RecipeFrameworkSurvival.cl_rfs_genTabFeatures( self )
	RfsGenGui.showTab( self, "features" )
end

function RecipeFrameworkSurvival.cl_rfs_genTabStreamer( self )
	RfsGenGui.showTab( self, "streamer" )
end

function RecipeFrameworkSurvival.cl_rfs_genTabDiscord( self )
	RfsGenGui.showTab( self, "discord" )
end

function RecipeFrameworkSurvival.cl_rfs_genToggleCheats( self )
	if not rfsClientIsHost() then return end
	self.network:sendToServer( "sv_rfs_featuresSet", { toggle = "cheats" } )
end

function RecipeFrameworkSurvival.cl_rfs_genToggleHackDevices( self )
	if not rfsClientIsHost() then return end
	self.network:sendToServer( "sv_rfs_featuresSet", { toggle = "hackDevices" } )
end

function RecipeFrameworkSurvival.cl_rfs_genToggleAreaLoader( self )
	if not rfsClientIsHost() then return end
	self.network:sendToServer( "sv_rfs_featuresSet", { toggle = "areaLoader" } )
end

function RecipeFrameworkSurvival.cl_rfs_genToggleHackableRobots( self )
	if not rfsClientIsHost() then return end
	self.network:sendToServer( "sv_rfs_featuresSet", { toggle = "hackableRobots" } )
end

function RecipeFrameworkSurvival.cl_rfs_genToggleHackUnderground( self )
	if not rfsClientIsHost() then return end
	self.network:sendToServer( "sv_rfs_featuresSet", { toggle = "hackUndergroundBots" } )
end

function RecipeFrameworkSurvival.cl_rfs_genToggleStreamerMode( self )
	if not rfsClientIsHost() then return end
	self.network:sendToServer( "sv_rfs_featuresSet", { toggle = "streamerMode" } )
end

function RecipeFrameworkSurvival.cl_rfs_genCycleStreamerCooldown( self )
	if not rfsClientIsHost() then return end
	self.network:sendToServer( "sv_rfs_featuresSet", { toggle = "streamerCooldownSec" } )
end

function RecipeFrameworkSurvival.cl_rfs_genToggleStreamerAnnounce( self )
	if not rfsClientIsHost() then return end
	self.network:sendToServer( "sv_rfs_featuresSet", { toggle = "streamerAnnounce" } )
end

function RecipeFrameworkSurvival.cl_rfs_genToggleStreamerChatRelay( self )
	if not rfsClientIsHost() then return end
	self.network:sendToServer( "sv_rfs_featuresSet", { toggle = "streamerChatRelay" } )
end

-- Lua cannot spawn Node/exe. Writes USER_DATA request for GitHub discord-bridge `npm run watch`.
function RecipeFrameworkSurvival.cl_rfs_genDiscordStartBot( self )
	if not rfsClientIsHost() then return end
	self.network:sendToServer( "sv_rfs_discordBotRequest", { action = "start" } )
end

function RecipeFrameworkSurvival.cl_rfs_genDiscordStopBot( self )
	if not rfsClientIsHost() then return end
	self.network:sendToServer( "sv_rfs_discordBotRequest", { action = "stop" } )
end

function RecipeFrameworkSurvival.cl_rfs_genReloadAllowlist( self )
	if not rfsClientIsHost() then return end
	self.network:sendToServer( "sv_rfs_allowlistReload" )
end

-- Client-only cycle of allowlisted unit names (preview; no JSON edit).
function RecipeFrameworkSurvival.cl_rfs_genCycleAllowlistUnit( self )
	if not rfsClientIsHost() then return end
	self.cl = self.cl or {}
	local info = self.cl.rfsAllowlistInfo
	local names = info and info.unitNames
	if type( names ) ~= "table" or #names == 0 then
		sm.gui.chatMessage( "[RFS] Allowlist empty — edit allowlist.json in GitHub discord-bridge clone or USER_DATA/rfs_discord_bridge, then Reload." )
		return
	end
	local idx = tonumber( self.cl.rfsAllowlistCycleIdx ) or 1
	idx = ( idx % #names ) + 1
	self.cl.rfsAllowlistCycleIdx = idx
	if self.cl.rfsGenGui then
		RfsGenGui.refresh( self )
	end
end

function RecipeFrameworkSurvival.cl_rfs_allowlistInfo( self, info )
	self.cl = self.cl or {}
	if type( info ) == "table" then
		self.cl.rfsAllowlistInfo = info
		self.cl.rfsAllowlistCycleIdx = 1
	end
	if self.cl.rfsGenGui then
		RfsGenGui.refresh( self )
	end
	if info and info.msg then
		sm.gui.chatMessage( "[RFS] " .. tostring( info.msg ) )
	end
end

function RecipeFrameworkSurvival.cl_rfs_genToggleRfsQuests( self )
	if not rfsClientIsHost() then return end
	self.network:sendToServer( "sv_rfs_featuresSet", { toggle = "rfsQuests" } )
end

function RecipeFrameworkSurvival.cl_rfs_featuresSync( self, data )
	self.cl = self.cl or {}
	if type( data ) == "table" and type( RfsFeatures ) == "table" and RfsFeatures.applySnapshot then
		RfsFeatures.applySnapshot( data )
	end
	-- Rebind only when cheats gate changed (or not yet bound). No OK spam either way.
	RfsSettings.load()
	local cheats = RfsSettings.cheatsEnabled()
	local admin = rfsClientIsAdmin()
	local host = rfsClientIsHost()
	if not self.cl.rfsCmdsBound or self.cl.rfsCmdsCheatsBound ~= cheats
		or self.cl.rfsCmdsAdminBound ~= admin or self.cl.rfsCmdsHostBound ~= host then
		self:rfs_bindCommands()
	end
	if self.cl.rfsGenGui then
		RfsGenGui.refresh( self )
	end
	if self.cl.rfsSetupGui then
		local tab = self.cl.rfsSetupTab or "main"
		RfsSetupGui.showTab( self, tab )
	end
	if data and data.msg then
		sm.gui.chatMessage( "[RFS] " .. tostring( data.msg ) )
	end
end

function RecipeFrameworkSurvival.sv_rfs_featuresBroadcast( self, msg )
	local payload = RfsFeatures.snapshot()
	if msg then
		payload.msg = msg
	end
	self.network:sendToClients( "cl_rfs_featuresSync", payload )
end

function RecipeFrameworkSurvival.sv_rfs_featuresGet( self, _, player )
	player = player or sm.player.getAllPlayers()[1]
	if not player then return end
	local payload = RfsFeatures.snapshot()
	self.network:sendToClient( player, "cl_rfs_featuresSync", payload )
end

function RecipeFrameworkSurvival.sv_rfs_featuresSet( self, params, player )
	player = player or sm.player.getAllPlayers()[1]
	if not rfsServerPlayerIsHost( player ) then
		return
	end
	local toggle = params and params.toggle
	local msg = nil

	if toggle == "cheats" then
		if RfsSettings.frameworkOnly() then
			msg = "frameworkOnly=true â€” cheats stay OFF"
		else
			local on = not RfsFeatures.cheatsEnabled()
			RfsFeatures.setCheats( on )
			msg = "Cheats: " .. ( on and "ON" or "OFF" )
		end
	elseif toggle == "hackDevices" then
		local on = not RfsFeatures.hackDevicesEnabled()
		RfsFeatures.setHackDevicesEnabled( on )
		msg = "Hack devices (beacons): " .. ( on and "ON" or "OFF" )
	elseif toggle == "areaLoader" then
		local on = not RfsFeatures.areaLoaderEnabled()
		RfsFeatures.setAreaLoaderEnabled( on )
		msg = "Anchor / Area loader: " .. ( on and "ON" or "OFF" )
	elseif toggle == "hackableRobots" then
		local on = not RfsFeatures.hackableRobotsEnabled()
		RfsFeatures.setHackableRobotsEnabled( on )
		msg = "Hackable robots: " .. ( on and "ON" or "OFF" )
	elseif toggle == "hackUndergroundBots" then
		local on = not RfsFeatures.hackUndergroundBotsEnabled()
		RfsFeatures.setHackUndergroundBotsEnabled( on )
		msg = "Underground miner/cable hijack: " .. ( on and "ON" or "OFF" )
	elseif toggle == "streamerMode" then
		local on = not RfsFeatures.streamerModeEnabled()
		RfsFeatures.setStreamerModeEnabled( on )
		msg = "Streamer mode: " .. ( on and "ON" or "OFF" )
	elseif toggle == "streamerCooldownSec" then
		local sec
		if params and params.value ~= nil then
			sec = RfsFeatures.setStreamerCooldownSec( params.value )
		else
			sec = RfsFeatures.cycleStreamerCooldownSec()
		end
		msg = "Streamer vote cooldown: " .. tostring( sec ) .. "s"
	elseif toggle == "streamerAnnounce" then
		local on = not RfsFeatures.streamerAnnounceEnabled()
		RfsFeatures.setStreamerAnnounceEnabled( on )
		msg = "Streamer vote announce: " .. ( on and "ON" or "OFF" )
	elseif toggle == "streamerChatRelay" then
		local on = not RfsFeatures.streamerChatRelayEnabled()
		RfsFeatures.setStreamerChatRelayEnabled( on )
		msg = "Discord chat relay: " .. ( on and "ON" or "OFF" )
	elseif toggle == "rfsQuests" then
		if RfsSettings.frameworkOnly() then
			msg = "frameworkOnly=true â€” RFS quest UI stays OFF"
		else
			local on = not RfsFeatures.rfsQuestsEnabled()
			RfsFeatures.setRfsQuestsEnabled( on )
			msg = "RFS quests content: " .. ( on and "ON" or "OFF" )
		end
	else
		return
	end

	self:sv_rfs_featuresBroadcast( msg )
end

local function rfsAllowlistInfoPayload( reload )
	local info = nil
	if type( RfsStreamer ) == "table" then
		if reload and RfsStreamer.reloadAllowlist then
			info = RfsStreamer.reloadAllowlist()
		elseif RfsStreamer.getAllowlistInfo then
			info = RfsStreamer.getAllowlistInfo()
		end
	end
	if type( info ) ~= "table" then
		info = { unitCount = 0, itemCount = 0, unitNames = {}, source = "builtin" }
	end
	return info
end

function RecipeFrameworkSurvival.sv_rfs_allowlistGet( self, _, player )
	player = player or sm.player.getAllPlayers()[1]
	if not player or not rfsServerPlayerIsHost( player ) then
		return
	end
	self.network:sendToClient( player, "cl_rfs_allowlistInfo", rfsAllowlistInfoPayload( false ) )
end

function RecipeFrameworkSurvival.sv_rfs_allowlistReload( self, _, player )
	player = player or sm.player.getAllPlayers()[1]
	if not player or not rfsServerPlayerIsHost( player ) then
		return
	end
	local info = rfsAllowlistInfoPayload( true )
	local src = info.source == "builtin" and "builtin defaults" or tostring( info.path or "file" )
	info.msg = string.format(
		"Allowlist reloaded — Units: %d | Items: %d (%s)",
		tonumber( info.unitCount ) or 0,
		tonumber( info.itemCount ) or 0,
		src
	)
	print( "[RFS] " .. info.msg )
	self.network:sendToClient( player, "cl_rfs_allowlistInfo", info )
end

-- Discord bot start/stop: USER_DATA only. Bot/watcher live on GitHub (not in Steam pack).
-- Lua cannot spawn Node — discord-bridge `npm run watch` polls these files.
local RFS_DISCORD_BOT_REQUEST_FILES = {
	start = "$USER_DATA/rfs_discord_bridge/start_request.json",
	stop = "$USER_DATA/rfs_discord_bridge/stop_request.json",
}

function RecipeFrameworkSurvival.sv_rfs_discordBotRequest( self, params, player )
	player = player or sm.player.getAllPlayers()[1]
	if not player or not rfsServerPlayerIsHost( player ) then
		return
	end
	local action = params and tostring( params.action or "" ):lower() or ""
	if action ~= "start" and action ~= "stop" then
		return
	end
	local path = RFS_DISCORD_BOT_REQUEST_FILES[action]
	local ts = 0
	pcall( function()
		ts = os.time and os.time() or 0
	end )
	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick() or 0
	end )
	local payload = {
		action = action,
		ts = ts,
		id = tostring( tick ) .. "-" .. tostring( math.random( 1000, 9999 ) ),
		source = "gensettings",
	}
	local wrote = pcall( sm.json.save, payload, path )
	local msg
	if wrote then
		if action == "start" then
			msg = "Start request written to USER_DATA/rfs_discord_bridge — clone discord-bridge from GitHub and run npm run watch"
		else
			msg = "Stop request written to USER_DATA/rfs_discord_bridge — watcher (npm run watch from GitHub clone) will stop the bot if running"
		end
		print( "[RFS] Discord bot " .. action .. " request → " .. tostring( path ) )
	else
		msg = "Failed to write Discord bot " .. action .. " request ($USER_DATA/rfs_discord_bridge)"
		print( "[RFS] " .. msg )
	end
	self.network:sendToClient( player, "cl_rfs_discordBotRequestResult", { ok = wrote, msg = msg, action = action } )
end

function RecipeFrameworkSurvival.cl_rfs_discordBotRequestResult( self, data )
	if data and data.msg then
		sm.gui.chatMessage( "[RFS] " .. tostring( data.msg ) )
	end
end

-- ========== Beacon Orders GUI (M1 Rest/Defend + M2 Hay Farm + M3 Tote Collect) ==========

function RecipeFrameworkSurvival.cl_rfs_ordersClose( self )
	if type( RfsBeaconOrdersGui ) == "table" then
		RfsBeaconOrdersGui.close( self )
	elseif self.cl then
		self.cl.rfsOrdersGui = nil
		self.cl.rfsPendingOrdersGui = nil
		local tick = 0
		pcall( function() tick = sm.game.getCurrentTick() or 0 end )
		self.cl.rfsOrdersReopenAfterTick = tick + 20
	end
end

function RecipeFrameworkSurvival.cl_rfs_ordersOnClosed( self )
	if type( RfsBeaconOrdersGui ) == "table" and RfsBeaconOrdersGui.onClosed then
		RfsBeaconOrdersGui.onClosed( self )
	elseif self.cl then
		self.cl.rfsOrdersGui = nil
	end
end

function RecipeFrameworkSurvival.cl_rfs_ordersScrollUp( self )
	if type( RfsBeaconOrdersGui ) == "table" and RfsBeaconOrdersGui.scrollDelta then
		RfsBeaconOrdersGui.scrollDelta( self, -( RfsBeaconOrdersGui.SCROLL_STEP or 1 ) )
	end
end

function RecipeFrameworkSurvival.cl_rfs_ordersScrollDown( self )
	if type( RfsBeaconOrdersGui ) == "table" and RfsBeaconOrdersGui.scrollDelta then
		RfsBeaconOrdersGui.scrollDelta( self, RfsBeaconOrdersGui.SCROLL_STEP or 1 )
	end
end

function RecipeFrameworkSurvival.cl_rfs_ordersScrollChanged( self, name, pos )
	if type( RfsBeaconOrdersGui ) == "table" and RfsBeaconOrdersGui.onScrollChanged then
		RfsBeaconOrdersGui.onScrollChanged( self, pos )
	end
end

function RecipeFrameworkSurvival.cl_rfs_ordersMouseWheel( self, name, scrollValue )
	if type( RfsBeaconOrdersGui ) == "table" and RfsBeaconOrdersGui.onMouseWheel then
		RfsBeaconOrdersGui.onMouseWheel( self, scrollValue )
	end
end

-- Legacy PREV/NEXT names (no longer in layout); keep as one-row scroll aliases.
function RecipeFrameworkSurvival.cl_rfs_ordersPrev( self )
	RecipeFrameworkSurvival.cl_rfs_ordersScrollUp( self )
end

function RecipeFrameworkSurvival.cl_rfs_ordersNext( self )
	RecipeFrameworkSurvival.cl_rfs_ordersScrollDown( self )
end

function RecipeFrameworkSurvival.cl_rfs_ordersMaster( self )
	if type( RfsBeaconOrdersGui ) == "table" and RfsBeaconOrdersGui.setMaster then
		RfsBeaconOrdersGui.setMaster( self )
	end
end

function RecipeFrameworkSurvival.cl_rfs_ordersRange( self )
	if type( RfsBeaconOrdersGui ) == "table" and RfsBeaconOrdersGui.toggleRange then
		RfsBeaconOrdersGui.toggleRange( self )
	end
end

-- Beacon SHOW RANGE circle. Drawn here (Game has no interactable host) so the
-- ring cannot weld onto the beacon's battery circuit.
function RecipeFrameworkSurvival.cl_rfs_rangeViz( self, data )
	self.cl = self.cl or {}
	self.cl.rfsRangeWant = self.cl.rfsRangeWant or {}
	if type( data ) ~= "table" or data.key == nil then
		return
	end
	self.cl.rfsRangeWant[tostring( data.key )] = data
end

function RecipeFrameworkSurvival.cl_rfs_ordersColor( self, value )
	if type( RfsBeaconOrdersGui ) == "table" and RfsBeaconOrdersGui.onColorDrop then
		RfsBeaconOrdersGui.onColorDrop( self, value )
	end
end

function RecipeFrameworkSurvival.cl_rfs_ordersRename( self )
	if type( RfsBeaconOrdersGui ) == "table" and RfsBeaconOrdersGui.onRename then
		RfsBeaconOrdersGui.onRename( self )
	end
end

-- Pre-Close-fix: open immediately on Game (createGui owned here so Close binds).
-- Only queues when a Close settle (~0.5s) is still active.
function RecipeFrameworkSurvival.cl_rfs_ordersOpen( self, data )
	self.cl = self.cl or {}
	if type( RfsBeaconOrdersGui ) ~= "table" or type( RfsBeaconOrdersGui.open ) ~= "function" then
		sm.gui.chatMessage( "[RFS] Orders GUI not loaded" )
		return
	end
	RfsBeaconOrdersGui.open( self, data or {} )
end

-- Beacon → Game: stash one pending open; server_onFixedUpdate sends it next ticks.
function RecipeFrameworkSurvival.sv_rfs_ordersScheduleOpen( self, params )
	params = params or {}
	local player = params.player
	if not player or not params.beaconKey then
		return
	end
	self.sv = self.sv or {}
	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick() or 0
	end )
	-- Plain-table payload only (sendToClient must serialize).
	local rows = {}
	if type( params.rows ) == "table" then
		for i, row in ipairs( params.rows ) do
			if type( row ) == "table" then
				rows[#rows + 1] = {
					key = row.key ~= nil and tostring( row.key ) or nil,
					name = row.name ~= nil and tostring( row.name ) or nil,
					displayIndex = row.displayIndex ~= nil and tonumber( row.displayIndex ) or nil,
					unitType = row.unitType ~= nil and tostring( row.unitType ) or nil,
					type = row.type ~= nil and tostring( row.type ) or nil,
					mode = row.mode ~= nil and tostring( row.mode ) or nil,
					seedUuid = row.seedUuid ~= nil and tostring( row.seedUuid ) or nil,
					owner = type( row.owner ) == "number" and row.owner
						or ( row.owner ~= nil and tonumber( row.owner ) or nil ),
					allyMode = row.allyMode ~= nil and tostring( row.allyMode ) or nil,
					allyColor = row.allyColor ~= nil and tostring( row.allyColor ) or nil,
				}
			end
			if i >= 64 then
				break
			end
		end
	end
	local pos = nil
	if type( params.pos ) == "table" and params.pos.x ~= nil then
		pos = {
			x = tonumber( params.pos.x ) or 0,
			y = tonumber( params.pos.y ) or 0,
			z = tonumber( params.pos.z ) or 0,
		}
	end
	self.sv.rfsPendingOrdersOpen = {
		player = player,
		atTick = tick + 2,
		data = {
			beaconKey = tostring( params.beaconKey ),
			beaconName = params.beaconName and tostring( params.beaconName ) or "Hack Beacon",
			role = params.role and tostring( params.role ) or "independent",
			masterKey = params.masterKey ~= nil and tostring( params.masterKey ) or nil,
			range = tonumber( params.range ) or 16,
			rows = rows,
			pos = pos,
		},
	}
end

-- Legacy name: schedule (do not sendToClient during beacon interact).
function RecipeFrameworkSurvival.sv_rfs_ordersOpenForPlayer( self, params )
	self:sv_rfs_ordersScheduleOpen( params )
end

function RecipeFrameworkSurvival.sv_rfs_ordersRelayToPlayer( self, params )
	params = params or {}
	local player = params.player
	if not player then
		return
	end
	if params.setResult then
		self.network:sendToClient( player, "cl_rfs_ordersSetResult", params.setResult )
	end
	if params.role then
		self.network:sendToClient( player, "cl_rfs_ordersRole", params.role )
	end
	if params.list then
		self.network:sendToClient( player, "cl_rfs_ordersList", params.list )
	end
end

-- Beacon env may differ from Game; merge serializable ally snapshots so Orders
-- set/color RPCs on Game can resolve the same unit keys the list just showed.
function RecipeFrameworkSurvival.sv_rfs_mirrorAllies( self, params )
	params = params or {}
	if type( RfsBotHijack ) ~= "table" then
		return
	end
	RfsBotHijack.allies = RfsBotHijack.allies or {}
	local snap = params.allies
	if type( snap ) ~= "table" then
		return
	end
	for key, info in pairs( snap ) do
		if key and type( info ) == "table" then
			local k = tostring( key )
			local prev = RfsBotHijack.allies[k] or {}
			RfsBotHijack.allies[k] = {
				type = info.type or prev.type,
				unitType = info.unitType or prev.unitType,
				owner = info.owner ~= nil and info.owner or prev.owner,
				mode = info.mode or prev.mode,
				beaconKey = info.beaconKey or prev.beaconKey,
				workBeaconKey = info.workBeaconKey or prev.workBeaconKey,
				controlled = true,
				displayName = info.displayName or prev.displayName,
				displayIndex = info.displayIndex ~= nil and tonumber( info.displayIndex ) or prev.displayIndex,
				allyColor = info.allyColor or prev.allyColor,
				rfsOrder = type( info.rfsOrder ) == "table" and info.rfsOrder or prev.rfsOrder,
				order = type( info.rfsOrder ) == "table" and info.rfsOrder or prev.order,
				origColor = prev.origColor,
				infectAcc = prev.infectAcc,
				hijackTicks = prev.hijackTicks,
				firstSeenTick = prev.firstSeenTick,
				lastTagTick = prev.lastTagTick,
			}
		end
	end
	pcall( function()
		RfsBotHijack.publishGlobals()
	end )
end

function RecipeFrameworkSurvival.cl_rfs_ordersList( self, data )
	if type( RfsBeaconOrdersGui ) == "table" then
		RfsBeaconOrdersGui.applyList( self, data )
	end
end

function RecipeFrameworkSurvival.cl_rfs_ordersRole( self, data )
	if type( RfsBeaconOrdersGui ) == "table" and RfsBeaconOrdersGui.applyRole then
		RfsBeaconOrdersGui.applyRole( self, data )
	end
end

function RecipeFrameworkSurvival.cl_rfs_ordersSetResult( self, data )
	if data and data.ok == false and data.msg then
		sm.gui.chatMessage( "[RFS] Order failed: " .. tostring( data.msg ) )
	elseif data and data.ok and data.master then
		sm.gui.chatMessage( "[RFS] Beacon set as Master — nearby powered devices become Slaves" )
	elseif data and data.ok and data.clearedMaster then
		sm.gui.chatMessage( "[RFS] Master cleared — device is Independent" )
	end
	if self.cl and self.cl.rfsOrdersBeaconKey then
		self.network:sendToServer( "sv_rfs_ordersList", {
			beaconKey = self.cl.rfsOrdersBeaconKey,
		} )
	end
end

-- DropDown callbacks ModeDrop0..7 / SeedDrop0..7 (createDropDown only passes value).
-- BotName0..7 select the row for Color apply.
for _rfsOrdersDropI = 0, 7 do
	local idx = _rfsOrdersDropI
	RecipeFrameworkSurvival["cl_rfs_ordersDrop" .. idx] = function( self, value )
		if type( RfsBeaconOrdersGui ) == "table" then
			RfsBeaconOrdersGui.onModeDrop( self, idx, value )
		end
	end
	RecipeFrameworkSurvival["cl_rfs_ordersSeed" .. idx] = function( self, value )
		if type( RfsBeaconOrdersGui ) == "table" and RfsBeaconOrdersGui.onSeedDrop then
			RfsBeaconOrdersGui.onSeedDrop( self, idx, value )
		end
	end
	RecipeFrameworkSurvival["cl_rfs_ordersBot" .. idx] = function( self, widgetName )
		if type( RfsBeaconOrdersGui ) == "table" and RfsBeaconOrdersGui.onBotClick then
			RfsBeaconOrdersGui.onBotClick( self, idx )
		end
	end
end

function RecipeFrameworkSurvival.sv_rfs_ordersList( self, params, player )
	params = params or {}
	local beaconKey = tostring( params.beaconKey or "" )
	if beaconKey == "" then
		self.network:sendToClient( player, "cl_rfs_ordersList", { rows = {} } )
		return
	end
	-- Prefer the live Hack Beacon interactable (authoritative allies table).
	if type( RfsBotHijack ) == "table" and type( RfsBotHijack.beaconScripts ) == "table" then
		local beacon = RfsBotHijack.beaconScripts[beaconKey]
		if beacon and type( beacon.sv_ordersList ) == "function" then
			pcall( function()
				beacon:sv_ordersList( params, player )
			end )
			return
		end
	end
	local allowHost = rfsServerPlayerIsHost( player )
	local ownerFilter = nil
	if not allowHost then
		pcall( function()
			ownerFilter = player and player.id
		end )
	end
	local rows = {}
	if type( RfsBotHijack ) == "table" and RfsBotHijack.listHomeAllies then
		rows = RfsBotHijack.listHomeAllies( beaconKey, ownerFilter ) or {}
	end
	-- Match interact prompt: if filtered list is empty but domain has allies, use full list.
	if ( not rows or #rows == 0 ) and type( RfsBotHijack ) == "table" and RfsBotHijack.listHomeAllies then
		local unfiltered = RfsBotHijack.listHomeAllies( beaconKey, nil ) or {}
		if #unfiltered > 0 then
			rows = unfiltered
		end
	end
	local beaconName, role, masterKey = nil, "independent", nil
	pcall( function()
		local rec = RfsBotHijack.beacons and RfsBotHijack.beacons[beaconKey]
		beaconName = rec and rec.name
		if RfsBotHijack.effectiveBeaconRole then
			role, masterKey = RfsBotHijack.effectiveBeaconRole( beaconKey )
		end
	end )
	self.network:sendToClient( player, "cl_rfs_ordersList", {
		rows = rows,
		beaconKey = beaconKey,
		beaconName = beaconName,
		role = role,
		masterKey = masterKey,
	} )
end

function RecipeFrameworkSurvival.sv_rfs_ordersRange( self, params, player )
	params = params or {}
	local beaconKey = tostring( params.beaconKey or "" )
	if beaconKey == "" then
		return
	end
	local show = params.show and true or false
	if type( RfsBotHijack ) == "table" and RfsBotHijack.setRangeVisible then
		RfsBotHijack.setRangeVisible( beaconKey, show )
	end
	-- Draw from Game (no interactable host). Never depend on beacon sandbox g_rfsGame.
	local pos = nil
	if type( params.pos ) == "table" and params.pos.x ~= nil then
		pos = {
			x = tonumber( params.pos.x ) or 0,
			y = tonumber( params.pos.y ) or 0,
			z = tonumber( params.pos.z ) or 0,
		}
	elseif type( RfsBotHijack ) == "table" and RfsBotHijack.beacons then
		local rec = RfsBotHijack.beacons[beaconKey]
		if rec and rec.pos then
			pcall( function()
				pos = {
					x = rec.pos.x,
					y = rec.pos.y,
					z = rec.pos.z,
				}
			end )
		end
	end
	local range = tonumber( params.range )
	if not range and type( RfsBotHijack ) == "table" and RfsBotHijack.beacons then
		local rec = RfsBotHijack.beacons[beaconKey]
		range = rec and tonumber( rec.range ) or nil
	end
	pcall( function()
		self.network:sendToClients( "cl_rfs_rangeViz", {
			key = beaconKey,
			show = show,
			range = range or 16,
			pos = pos,
		} )
	end )
	-- Persist showRange flag only. Beacon must not spawn FX (battery net weld).
	if type( RfsBotHijack ) == "table" and type( RfsBotHijack.beaconScripts ) == "table" then
		local beacon = RfsBotHijack.beaconScripts[beaconKey]
		if beacon and type( beacon.sv_setShowRange ) == "function" then
			pcall( function()
				beacon:sv_setShowRange( { show = show }, player )
			end )
		end
	end
end

function RecipeFrameworkSurvival.sv_rfs_ordersSetMaster( self, params, player )
	params = params or {}
	local beaconKey = tostring( params.beaconKey or "" )
	if beaconKey == "" or type( RfsBotHijack ) ~= "table" or not RfsBotHijack.claimMaster then
		self.network:sendToClient( player, "cl_rfs_ordersSetResult", { ok = false, msg = "no beacon" } )
		return
	end
	local ok, err = RfsBotHijack.claimMaster( beaconKey )
	self.network:sendToClient( player, "cl_rfs_ordersSetResult", {
		ok = ok and true or false,
		msg = ( not ok ) and tostring( err or "claim failed" ) or nil,
		master = ok and true or false,
	} )
	if ok then
		self.network:sendToClient( player, "cl_rfs_ordersRole", {
			beaconKey = beaconKey,
			role = "master",
			masterKey = nil,
		} )
	end
end

function RecipeFrameworkSurvival.sv_rfs_ordersClearMaster( self, params, player )
	params = params or {}
	local beaconKey = tostring( params.beaconKey or "" )
	if beaconKey == "" or type( RfsBotHijack ) ~= "table" or not RfsBotHijack.clearMaster then
		self.network:sendToClient( player, "cl_rfs_ordersSetResult", { ok = false, msg = "no beacon" } )
		return
	end
	local ok, err = RfsBotHijack.clearMaster( beaconKey )
	-- Persist Independent on the live beacon (Set Master already saves via claim + pendingRole).
	-- Do not re-query effectiveBeaconRole — that can snap the GUI back to Master/Slave
	-- before storage catches up. Do not migrate/re-split allies (later-bug).
	if ok and type( RfsBotHijack.beaconScripts ) == "table" then
		local beacon = RfsBotHijack.beaconScripts[beaconKey]
		if beacon then
			pcall( function()
				if type( beacon.sv_clearMaster ) == "function" then
					beacon:sv_clearMaster( { beaconKey = beaconKey }, player )
				else
					beacon.sv = beacon.sv or {}
					beacon.sv.role = "independent"
					beacon.sv.masterKey = nil
					if beacon.storage then
						beacon.storage:save( {
							role = "independent",
							masterKey = nil,
						} )
					end
				end
			end )
		end
	end
	self.network:sendToClient( player, "cl_rfs_ordersSetResult", {
		ok = ok and true or false,
		msg = ( not ok ) and tostring( err or "clear failed" ) or nil,
		clearedMaster = ok and true or false,
	} )
	if ok then
		self.network:sendToClient( player, "cl_rfs_ordersRole", {
			beaconKey = beaconKey,
			role = "independent",
			masterKey = nil,
		} )
	end
end

function RecipeFrameworkSurvival.sv_rfs_ordersSet( self, params, player )
	params = params or {}
	local unitKey = tostring( params.unitKey or "" )
	local mode = tostring( params.mode or "rest" )
	local beaconKey = params.beaconKey and tostring( params.beaconKey ) or nil
	local seedUuid = params.seedUuid and tostring( params.seedUuid ) or nil
	if unitKey == "" then
		self.network:sendToClient( player, "cl_rfs_ordersSetResult", { ok = false, msg = "no bot" } )
		return
	end
	local allowHost = rfsServerPlayerIsHost( player )
	-- Host-only set for world authority; owners may set their own bots.
	local ok, result = false, "hijack missing"
	if type( RfsBotHijack ) == "table" and RfsBotHijack.setOrder then
		ok, result = RfsBotHijack.setOrder( unitKey, {
			mode = mode,
			seedUuid = seedUuid,
			beaconKey = beaconKey,
		}, player, allowHost )
	end
	self.network:sendToClient( player, "cl_rfs_ordersSetResult", {
		ok = ok and true or false,
		msg = ( not ok ) and tostring( result ) or nil,
		mode = ok and ( type( result ) == "table" and result.mode or mode ) or nil,
		seedUuid = ok and ( type( result ) == "table" and result.seedUuid or seedUuid ) or nil,
		unitKey = unitKey,
	} )
end

function RecipeFrameworkSurvival.sv_rfs_ordersSetColor( self, params, player )
	params = params or {}
	local beaconKey = params.beaconKey and tostring( params.beaconKey ) or nil
	local unitKey = params.unitKey and tostring( params.unitKey ) or nil
	if unitKey == "" then
		unitKey = nil
	end
	local unitKeys = nil
	if type( params.unitKeys ) == "table" then
		unitKeys = {}
		for _, k in ipairs( params.unitKeys ) do
			if k ~= nil and tostring( k ) ~= "" then
				unitKeys[#unitKeys + 1] = tostring( k )
			end
		end
	end
	local colorHex = params.colorHex and tostring( params.colorHex ) or nil
	if not colorHex then
		self.network:sendToClient( player, "cl_rfs_ordersSetResult", { ok = false, msg = "no color" } )
		return
	end
	local allowHost = rfsServerPlayerIsHost( player )
	local ok, result, count = false, "hijack missing", 0
	if type( RfsBotHijack ) == "table" and RfsBotHijack.setAllyColorDomain then
		ok, result, count = RfsBotHijack.setAllyColorDomain( beaconKey, colorHex, player, allowHost, unitKey, unitKeys )
	end
	self.network:sendToClient( player, "cl_rfs_ordersSetResult", {
		ok = ok and true or false,
		msg = ( not ok ) and tostring( result ) or nil,
		colorHex = ok and colorHex or nil,
		colorCount = count,
		unitKey = unitKey,
	} )
end

function RecipeFrameworkSurvival.sv_rfs_ordersRename( self, params, player )
	params = params or {}
	player = player or params.player
	local name = tostring( params.name or "" )
	local allowHost = rfsServerPlayerIsHost( player )
	local keys = params.unitKeys
	local n = 0
	if type( keys ) == "table" and type( RfsBotHijack ) == "table" and RfsBotHijack.setCustomName then
		for _, k in ipairs( keys ) do
			local ok = RfsBotHijack.setCustomName( tostring( k ), name, player, allowHost )
			if ok then
				n = n + 1
			end
		end
	end
	pcall( function()
		self.network:sendToClient( player, "client_showMessage", "[RFS] Renamed " .. tostring( n ) .. " bot(s)" )
	end )
	if player then
		self:sv_rfs_ordersList( { beaconKey = params.beaconKey }, player )
	end
end
