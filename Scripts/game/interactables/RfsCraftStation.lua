-- RfsCraftStation.lua — RTI Crafting Station (6x5x4) — REAL CRAFTING v2.
-- E opens its OWN menu (RfsCraftStationGui): learned crafts + search/scroll,
-- station queue, qty +/- or typed, CRAFT adds to queue. Upgrade slots in the
-- top chrome (Component Kits). U toggles Wireless. Tiers (5) set slots/speed.
-- Ingredients pull from LEFT first, then RIGHT. Output goes RIGHT first, then
-- LEFT (operator front = opposite the dual LCDs). If every attached chest is
-- full the queue pauses (no ground dump).
-- ticks even if the E-menu is closed. One queue slot = one order line
-- (any quantity of one item). Base machine has 4 slots.
--
-- NOTE: standalone interactable; does NOT patch vanilla Craftbot.

RfsCraftStation = class( nil )
RfsCraftStation.maxParentCount = 255
RfsCraftStation.maxChildCount = 255
RfsCraftStation.connectionInput = sm.interactable.connectionType.logic + sm.interactable.connectionType.electricity
RfsCraftStation.connectionOutput = sm.interactable.connectionType.logic + sm.interactable.connectionType.electricity
RfsCraftStation.colorNormal = sm.color.new( 0xdf7f01ff )
RfsCraftStation.colorHighlight = sm.color.new( 0xffb84dff )
RfsCraftStation.connectIcon = "logic"

local RFS_CG = "$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247"
local STATION_UUID = "c8d7e6f5-a4b3-42c1-9d0e-8f7a6b5c4d3e"

-- Upgrade tiers (per-station). Every upgrade adds two queue slots. Tier 2
-- unlocks the adjustable speed control; later tiers raise its server-side cap
-- from 100% up to 250% at max tier.
local TIERS = {
	{ level = 1, slots = 4,  maxSpeed = 1.00, range = 25,  cost = 0,  kits = 0 },
	{ level = 2, slots = 6,  maxSpeed = 1.25, range = 25,  cost = 5,  kits = 5 },
	{ level = 3, slots = 8,  maxSpeed = 1.75, range = 50,  cost = 10, kits = 10 },
	{ level = 4, slots = 10, maxSpeed = 2.00, range = 75,  cost = 15, kits = 15 },
	{ level = 5, slots = 12, maxSpeed = 2.50, range = 100, cost = 25, kits = 25 },
}
for _, info in ipairs( TIERS ) do info.speed = info.maxSpeed end
RfsCraftStation.TIERS = TIERS
local MAX_TIER = #TIERS
local MAX_ORDER = 999
local COMPONENT_UUID = "5530e6a0-4748-4926-b134-50ca9ecb9dcf"
local SWEETENER_UUID = "b41de15e-a136-425a-a730-889b58cf4466"

local function rfsDofile( rel )
	local paths = { RFS_CG .. "/" .. rel, "$CONTENT_DATA/" .. rel }
	for _, p in ipairs( paths ) do
		local ok = pcall( function()
			dofile( p )
		end )
		if ok then
			return true
		end
	end
	return false
end
rfsDofile( "Scripts/game/RfsCraftQueue.lua" )
rfsDofile( "Scripts/game/RfsCraftStationNet.lua" )
rfsDofile( "Scripts/game/RfsCraftStationGui.lua" )

-- ==========================================================================
-- Crafting Station — REAL CRAFTING ENGINE (server)
--
-- Design contract (kept small to dodge the SM client-script line/size limits):
--   * Ingredients: left+right piped/welded containers + player inventory.
--   * Output:      right container first, then +X port eject; wait if jammed.
--   * Recipe shape compat: RFS recipes use ingredientList{itemId,quantity},
--                  vanilla craftbot json uses {itemId,quantity} too; support
--                  BOTH (also tolerate {uuid,amount} rows if any slip in).
-- ==========================================================================

local function lc( v ) return string.lower( tostring( v or "" ) ) end
local isRecipeUnlocked
local getInputContainers
local storageIsFull

local function tierInfo( self )
	self.sv = self.sv or {}
	local t = math.max( 1, math.min( MAX_TIER, tonumber( self.sv.tier ) or 1 ) )
	return TIERS[t], t
end

local function usedSlots( st )
	st = st or {}
	st.sv = st.sv or {}
	return #( st.sv.crafts or {} ) + #( st.sv.recycles or {} )
end

local function jobRemaining( entry )
	return math.max( 1, math.floor( tonumber( entry and entry.count ) or 1 ) )
end

local function jobTotal( entry )
	local remaining = jobRemaining( entry )
	return math.max( remaining, math.floor( tonumber( entry and ( entry.total or entry.batchTotal ) ) or remaining ) )
end

-- Collapse legacy per-unit rows (same batchId, no count) into one job.
local function normalizeJobs( list )
	local out = {}
	for _, entry in ipairs( list or {} ) do
		if type( entry ) == "table" and entry.itemId then
			local n = math.max( 1, math.floor( tonumber( entry.count ) or 1 ) )
			local tot = math.max( n, math.floor( tonumber( entry.total or entry.batchTotal ) or n ) )
			local last = out[#out]
			local legacyUnit = entry.count == nil
			if last and legacyUnit
				and tostring( last.itemId ) == tostring( entry.itemId )
				and last.batchId ~= nil and entry.batchId ~= nil
				and last.batchId == entry.batchId then
				last.count = ( last.count or 1 ) + n
				last.total = math.max( last.total or last.count, tot, last.count )
				last.batchTotal = last.total
			else
				entry.count = n
				entry.total = tot
				entry.batchTotal = tot
				out[#out + 1] = entry
			end
		end
	end
	return out
end

local function findJobByItem( list, itemId )
	itemId = tostring( itemId or "" )
	for _, entry in ipairs( list or {} ) do
		if entry and tostring( entry.itemId ) == itemId then
			return entry
		end
	end
	return nil
end

local function findOpenCraftJob( root, itemId )
	itemId = tostring( itemId or "" )
	local members = { root }
	if type( RfsCraftStationNet ) == "table" and RfsCraftStationNet.loopMembers then
		members = RfsCraftStationNet.loopMembers( root ) or members
	end
	for _, st in ipairs( members ) do
		local entry = findJobByItem( st.sv and st.sv.crafts, itemId )
		if entry then
			return st, entry
		end
	end
	return nil, nil
end

local function serverCanUseStation( self, player )
	if not self or not self.shape or not player then return false end
	local ok, allowed = pcall( function()
		local character = player.character
		return character ~= nil and ( character.worldPosition - self.shape.worldPosition ):length() <= 8
	end )
	return ok and allowed == true
end

local function serverIsPairedViewer( self, player )
	if not self or not self.sv or self.sv.wireless ~= true or not player then return false end
	local id
	pcall( function() id = player:getId() end )
	for _, row in ipairs( self.sv.pairs or {} ) do
		if row.id == id then return true end
	end
	return false
end

local function serverCanRemoteCraft( self, params, player )
	if serverIsPairedViewer( self, player ) then return true end
	local root
	pcall( function() root = RfsCraftStationNet.stationByShapeId( params and params.remoteRootId ) end )
	if not root or not serverIsPairedViewer( root, player ) then return false end
	for _, member in ipairs( RfsCraftStationNet.loopMembers( root ) or {} ) do
		if member == self then return true end
	end
	return false
end

function RfsCraftStation.server_onCreate( self )
	self.sv = self.sv or {}
	self.sv.tier = self.sv.tier and tonumber( self.sv.tier ) or 1
	local wireless = self.sv.wireless == true or tostring( self.sv.wireless or "" ) == "true"
	self.sv.wireless = wireless
	self.sv.crafts = type( self.sv.crafts ) == "table" and self.sv.crafts or {}
	self.sv.recycles = type( self.sv.recycles ) == "table" and self.sv.recycles or {}
	self.sv.speedSetting = tonumber( self.sv.speedSetting )
	self.sv.clientDirty = true
	self.sv.storageDirty = false
	self.sv.lastStorageSave = 0
	-- Load persisted state (tier + craft queue survive unload)
	pcall( function()
		local saved = self.storage and self.storage:load()
		if type( saved ) == "table" then
			self.sv.tier = math.max( 1, math.min( MAX_TIER, tonumber( saved.tier ) or 1 ) )
			if saved.wireless ~= nil then
				self.sv.wireless = saved.wireless == true or tostring( saved.wireless ) == "true"
			end
			if type( saved.crafts ) == "table" then
				self.sv.crafts = saved.crafts
			end
			if type( saved.recycles ) == "table" then
				self.sv.recycles = saved.recycles
			end
			if type( saved.pairs ) == "table" then
				self.sv.pairs = saved.pairs
			end
			if saved.speedSetting ~= nil then
				self.sv.speedSetting = tonumber( saved.speedSetting ) or 1
			end
		end
	end )
	self.sv.crafts = normalizeJobs( self.sv.crafts )
	self.sv.recycles = normalizeJobs( self.sv.recycles )
	for _, entry in ipairs( self.sv.recycles ) do
		if entry.prepaid == nil then
			if entry.paid == nil then
				entry.prepaid = jobRemaining( entry )
			else
				entry.prepaid = 0
			end
		end
	end
	-- Legacy saves had no speedSetting; tier 5 previously ran at a fixed 2x.
	if self.sv.speedSetting == nil then self.sv.speedSetting = self.sv.tier >= 5 and 2 or 1 end
	local info = TIERS[self.sv.tier] or TIERS[1]
	self.sv.speedSetting = math.max( 1, math.min( info.maxSpeed or 1, self.sv.speedSetting ) )
	_G.g_rfsCraftStations = _G.g_rfsCraftStations or {}
	_G.g_rfsCraftStations[self] = true
	pcall( function()
		local game = _G.g_rfsGame
		if game then
			game.sv = game.sv or {}
			game.sv.rfsCraftStations = game.sv.rfsCraftStations or {}
			game.sv.rfsCraftStations[self] = true
		end
	end )
	self:sv_syncClients()
end

function RfsCraftStation.server_onDestroy( self )
	pcall( function()
		local bag = _G.g_rfsCraftStations
		if type( bag ) == "table" then
			bag[self] = nil
		end
		local game = _G.g_rfsGame
		if game and game.sv and type( game.sv.rfsCraftStations ) == "table" then
			game.sv.rfsCraftStations[self] = nil
		end
	end )
end

-- Persist tier + craft queue.
function RfsCraftStation.sv_saveStorage( self, force )
	if not self.storage then
		return
	end
	self.sv.storageDirty = true
	if not force and ( sm.game.getServerTick() - ( self.sv.lastStorageSave or 0 ) ) < 2000 then
		return
	end
	self.sv.lastStorageSave = sm.game.getServerTick()
	self.sv.storageDirty = false
	pcall( function()
		self.storage:save( {
			tier = self.sv.tier,
			wireless = self.sv.wireless == true,
			speedSetting = self.sv.speedSetting,
			pairs = self.sv.pairs,
			crafts = self.sv.crafts,
			recycles = self.sv.recycles,
		} )
	end )
end

-- Client data: tier, slots/speed, power, wireless, craft queue snapshot.
function RfsCraftStation.sv_syncClients( self )
	self.sv.clientDirty = false
	local info = tierInfo( self )
	local powered = self:sv_isPowered()
	local crafts = {}
	for _, entry in ipairs( self.sv.crafts or {} ) do
		crafts[#crafts + 1] = {
			itemId = entry.itemId,
			time = entry.time,
			craftTime = entry.craftTime,
			waiting = entry.waiting == true,
			count = jobRemaining( entry ),
			total = jobTotal( entry ),
			batchId = entry.batchId,
			batchTotal = jobTotal( entry ),
			ownerId = entry.ownerId,
		}
	end
	local pairStatus = {}
	for _, row in ipairs( self.sv.pairs or {} ) do
		local online = false
		pcall( function()
			for _, p in ipairs( sm.player.getAllPlayers() or {} ) do if p:getId() == row.id then online = true break end end
		end )
		pairStatus[#pairStatus + 1] = { id = row.id, name = row.name, prio = row.prio, online = online }
	end
	local recycles = {}
	for _, entry in ipairs( self.sv.recycles or {} ) do
		recycles[#recycles + 1] = {
			itemId = entry.itemId,
			time = entry.time,
			craftTime = entry.craftTime,
			waiting = entry.waiting == true,
			count = jobRemaining( entry ),
			total = jobTotal( entry ),
			batchId = entry.batchId,
			batchTotal = jobTotal( entry ),
			ownerId = entry.ownerId,
		}
	end
	pcall( function()
		self.network:setClientData( {
			tier = self.sv.tier,
			slots = info.slots,
			speed = self.sv.speedSetting,
			maxSpeed = info.maxSpeed,
			speedUnlocked = self.sv.tier >= 2,
			range = info.range,
			wireless = self.sv.wireless == true,
			storageFull = storageIsFull( self ) == true,
			powered = powered,
			pairs = pairStatus,
			loopSlots = ( type( RfsCraftStationNet ) == "table" and RfsCraftStationNet.pooledSlots( self ) ) or info.slots,
			crafts = crafts,
			recycles = recycles,
		} )
	end )
end

-- TEMP: no power required so queue/craft can be tested. Wire check comes back later.
function RfsCraftStation.sv_isPowered( self )
	return true
end

function RfsCraftStation.client_onCreate( self )
	self.cl = self.cl or {}
	self.cl.tier = 1
	self.cl.wireless = false
	self.cl.storageFull = false
	self.cl.screenPose = 0
	self.cl.csRange = 0
	_G.g_rfsCraftStationsCl = _G.g_rfsCraftStationsCl or {}
	_G.g_rfsCraftStationsCl[self] = true
	self:cl_updateLook()
end

function RfsCraftStation.client_onRefresh( self )
	self:client_onCreate()
end

function RfsCraftStation.client_onDestroy( self )
	pcall( function()
		local bag = _G.g_rfsCraftStationsCl
		if type( bag ) == "table" then
			bag[self] = nil
		end
	end )
	pcall( function()
		if self.cl and self.cl.fxTop then self.cl.fxTop:destroy() end
	end )
	pcall( function()
		if self.cl and self.cl.fxBot then self.cl.fxBot:destroy() end
	end )
end

function RfsCraftStation.client_onClientDataUpdate( self, data )
	self.cl = self.cl or {}
	if type( data ) == "table" then
		if data.tier then
			self.cl.tier = tonumber( data.tier ) or 1
		end
		if data.slots then
			self.cl.csSlots = tonumber( data.slots ) or 2
		end
		if data.speed then
			self.cl.csSpeed = tonumber( data.speed ) or 1
		end
		self.cl.csMaxSpeed = tonumber( data.maxSpeed ) or 1
		self.cl.csSpeedUnlocked = data.speedUnlocked == true
		if data.range ~= nil then
			self.cl.csRange = tonumber( data.range ) or 0
		end
		if data.crafts ~= nil and type( data.crafts ) == "table" then
			self.cl.csCrafts = data.crafts
		end
		if data.recycles ~= nil and type( data.recycles ) == "table" then
			self.cl.csRecycles = data.recycles
		end
		if data.powered ~= nil then
			self.cl.csPowered = data.powered == true
		end
		if data.wireless ~= nil then
			self.cl.wireless = data.wireless == true or tostring( data.wireless ) == "true"
		end
		if data.storageFull ~= nil then
			self.cl.storageFull = data.storageFull == true
		end
		if type( data.pairs ) == "table" then
			self.cl.csPairs = data.pairs
		end
		if data.loopSlots ~= nil then
			self.cl.csLoopSlots = tonumber( data.loopSlots ) or self.cl.csSlots
		end
	end
	if self.cl.wireless == nil then
		self.cl.wireless = false
	end
	self.cl.csTier = tonumber( self.cl.tier ) or 1
	self:cl_updateLook()
	pcall( function() RfsCraftStationGui.refresh( self ) end )
end

local SCREEN_ANIM = "int_screen_rotate"
local SLIDER_ANIM = "int_slider"
local ANIM_NAMES = { SCREEN_ANIM, SLIDER_ANIM }

function RfsCraftStation.cl_applyLights( self )
	if not self or not self.interactable then
		return
	end
	local storageFull = self.cl and self.cl.storageFull == true
	local wirelessOn = self.cl and self.cl.wireless == true
	local frame = 0
	if storageFull then
		frame = frame + 2
	end
	if wirelessOn then
		frame = frame + 1
	end
	pcall( function()
		self.interactable:setUvFrameIndex( frame )
	end )
end

function RfsCraftStation.cl_updateLook( self )
	self.cl = self.cl or {}
	self.cl.tier = tonumber( self.cl.tier ) or 1
	local speed = tonumber( self.cl.csSpeed ) or 1
	local slider = math.max( 0, math.min( 1, ( speed - 1 ) / 1.5 ) )
	self:cl_applyAnims( slider, self.cl.screenPose )
	self:cl_applyLights()
end

function RfsCraftStation.cl_enableAnims( self )
	for _, name in ipairs( ANIM_NAMES ) do
		pcall( function()
			self.interactable:setAnimEnabled( name, true )
		end )
	end
end

function RfsCraftStation.cl_applyAnims( self, sliderPose, screenPose )
	self:cl_enableAnims()
	if sliderPose ~= nil then
		pcall( function()
			self.interactable:setAnimProgress( SLIDER_ANIM, sliderPose )
		end )
	end
	if screenPose ~= nil then
		-- Progress 0 = closed (flush). Progress 1 = open (~160°). Clip is cropped
		-- to that swing so it cannot keep spinning.
		pcall( function()
			self.interactable:setAnimProgress( SCREEN_ANIM, math.max( 0, math.min( 1, screenPose ) ) )
		end )
	end
end

local SCREEN_NEAR = 7.5
local SCREEN_SPEED = 0.12

local function cl_playerNear( self, range )
	local near = false
	pcall( function()
		local c = sm.localPlayer.getPlayer().character
		near = ( c.worldPosition - self.shape.worldPosition ):length() <= range
	end )
	return near == true
end

function RfsCraftStation.client_onUpdate( self, dt )
	self.cl = self.cl or {}
	dt = tonumber( dt ) or 0.016
	-- Screen opens only when a player is nearby; closes when they leave.
	local want = cl_playerNear( self, SCREEN_NEAR ) and 1 or 0
	local cur = tonumber( self.cl.screenPose ) or 0
	local step = math.max( 0.001, dt ) * SCREEN_SPEED
	if math.abs( want - cur ) < 0.002 then
		cur = want
	elseif want > cur then
		cur = math.min( want, cur + step )
	else
		cur = math.max( want, cur - step )
	end
	self.cl.screenPose = cur
	local speed = tonumber( self.cl.csSpeed ) or 1
	local slider = math.max( 0, math.min( 1, ( speed - 1 ) / 1.5 ) )
	self:cl_applyAnims( slider, cur )
	self:cl_applyLights()
	pcall( function()
		if self.cl.csGui and type( RfsCraftStationGui ) == "table" and RfsCraftStationGui.poll then
			RfsCraftStationGui.poll( self )
		end
	end )
end

function RfsCraftStation.sv_n_requestStationState( self, params, player )
	if not serverCanUseStation( self, player ) then return end
	self:sv_syncClients()
	local learned, availability, countIds = {}, {}, {}
	local always = _G.g_rfsCraftbotAlwaysAvailable or {}
	for setName, set in pairs( g_craftingRecipeSets or {} ) do
		if setName == "craftbot_rfs_mods" or string.match( tostring( setName ), "^craftbot_" ) then
			for _, recipe in ipairs( set.recipesByIndex or {} ) do
				local id = tostring( recipe.itemId or "" )
				if id ~= "" then
					countIds[id] = true
					if isRecipeUnlocked( id ) or always[id] then learned[id] = true end
				end
				for _, ing in ipairs( recipe.ingredientList or {} ) do countIds[tostring( ing.itemId )] = true end
			end
		end
	end
	local function addQty( target, id )
		local n = 0
		pcall( function() n = sm.container.totalQuantity( target, sm.uuid.new( id ) ) or 0 end )
		availability[id] = ( availability[id] or 0 ) + ( tonumber( n ) or 0 )
	end
	for _, container in ipairs( getInputContainers( self, player ) ) do
		local target = container
		pcall( function()
			if type( container ) == "Shape" then
				local idx = 0
				pcall( function()
					local n = container.getShapeOutputContainerIndex and container:getShapeOutputContainerIndex()
					if n and n >= 0 then idx = n end
				end )
				target = container:getInteractable():getContainer( idx )
			end
		end )
		for id, _ in pairs( countIds ) do
			addQty( target, id )
		end
	end
	self.network:sendToClient( player, "cl_n_stationUiState", { learned = learned, availability = availability } )
end

function RfsCraftStation.cl_n_stationUiState( self, data )
	self.cl = self.cl or {}
	self.cl.csLearned = type( data ) == "table" and data.learned or {}
	self.cl.csAvailability = type( data ) == "table" and data.availability or {}
	self.cl.csList = nil
	pcall( function() RfsCraftStationGui.refresh( self ) end )
end

function RfsCraftStation.client_canInteract( self )
	self.cl = self.cl or {}
	local on = self.cl.wireless == true
	local info = on and "Remote Crafting: ON" or "Remote Crafting: OFF"
	sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "Crafting Station" )
	local viewer = type( RfsHandheldLcd ) == "table" and RfsHandheldLcd.wieldingRecipeViewer and RfsHandheldLcd.wieldingRecipeViewer()
	if viewer then
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Tinker", true ), "Link Mobile Crafting Tablet" )
	else
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Tinker", true ), info )
	end
	return true
end

function RfsCraftStation.client_canTinker( self, character )
	return true
end

function RfsCraftStation.client_onInteract( self, character, state )
	if state ~= true then
		return
	end
	self:cl_openStationGui()
end

-- Open on this part (same idea as vanilla/Fant crafters: GUI is owned by the interactable).
function RfsCraftStation.cl_openStationGui( self )
	if type( RfsCraftStationGui ) ~= "table" then
		rfsDofile( "Scripts/game/RfsCraftStationGui.lua" )
	end
	if type( RfsCraftStationGui ) ~= "table" or not RfsCraftStationGui.attach then
		pcall( function()
			sm.gui.chatMessage( "[RFS] Crafting Station menu missing" )
		end )
		return
	end
	local layout = "$CONTENT_DATA/Gui/menu/layouts/Rfs_CraftStation.layout"
	local ok, gui = pcall( sm.gui.createGuiFromLayout, layout, true, {
		isHud = false,
		isInteractive = true,
		needsCursor = true,
	} )
	if not ok or not gui then
		ok, gui = pcall( sm.gui.createGuiFromLayout, layout, true )
	end
	if not ok or not gui then
		pcall( function()
			sm.gui.chatMessage( "[RFS] Crafting Station menu failed to create" )
		end )
		return
	end
	self.cl = self.cl or {}
	_G.g_rfsCraftStationGuiHost = self
	local game = _G.g_rfsGame
	if game then
		game.cl = game.cl or {}
		game.cl.rfsCraftStationPart = self
	end
	RfsCraftStationGui.attach( self, gui )
end

local function csFwd( name, ... )
	if type( RfsCraftStationGui ) == "table" and RfsCraftStationGui[name] then
		RfsCraftStationGui[name]( ... )
	end
end

function RfsCraftStation.cl_rfs_cs_close( self ) _G.g_rfsCraftStationGuiHost = self; csFwd( "closeActive" ) end
function RfsCraftStation.cl_rfs_cs_closed( self ) _G.g_rfsCraftStationGuiHost = self; csFwd( "closeActive" ) end
function RfsCraftStation.cl_rfs_cs_tabCraft( self ) _G.g_rfsCraftStationGuiHost = self; csFwd( "tabCraft" ) end
function RfsCraftStation.cl_rfs_cs_tabRecycle( self ) _G.g_rfsCraftStationGuiHost = self; csFwd( "tabRecycle" ) end
function RfsCraftStation.cl_rfs_cs_tabUpgrade( self ) _G.g_rfsCraftStationGuiHost = self; csFwd( "tabUpgrade" ) end
function RfsCraftStation.cl_rfs_cs_catAll( self ) _G.g_rfsCraftStationGuiHost = self; csFwd( "catAll" ) end
function RfsCraftStation.cl_rfs_cs_catTool( self ) _G.g_rfsCraftStationGuiHost = self; csFwd( "catTool" ) end
function RfsCraftStation.cl_rfs_cs_catBlock( self ) _G.g_rfsCraftStationGuiHost = self; csFwd( "catBlock" ) end
function RfsCraftStation.cl_rfs_cs_catInteractive( self ) _G.g_rfsCraftStationGuiHost = self; csFwd( "catInteractive" ) end
function RfsCraftStation.cl_rfs_cs_catPart( self ) _G.g_rfsCraftStationGuiHost = self; csFwd( "catPart" ) end
function RfsCraftStation.cl_rfs_cs_catConsumable( self ) _G.g_rfsCraftStationGuiHost = self; csFwd( "catConsumable" ) end
function RfsCraftStation.cl_rfs_cs_search( self, ... ) _G.g_rfsCraftStationGuiHost = self; csFwd( "search", ... ) end
function RfsCraftStation.cl_rfs_cs_scroll( self, ... ) _G.g_rfsCraftStationGuiHost = self; csFwd( "scroll", ... ) end
function RfsCraftStation.cl_rfs_cs_wheel( self, ... ) _G.g_rfsCraftStationGuiHost = self; csFwd( "wheel", ... ) end
function RfsCraftStation.cl_rfs_cs_queueScroll( self, ... ) _G.g_rfsCraftStationGuiHost = self; csFwd( "queueScroll", ... ) end
function RfsCraftStation.cl_rfs_cs_queueWheel( self, ... ) _G.g_rfsCraftStationGuiHost = self; csFwd( "queueWheel", ... ) end
function RfsCraftStation.cl_rfs_cs_speed( self, ... ) _G.g_rfsCraftStationGuiHost = self; csFwd( "speed", ... ) end
function RfsCraftStation.cl_rfs_cs_pick( self, buttonName ) _G.g_rfsCraftStationGuiHost = self; csFwd( "pick", buttonName ) end
function RfsCraftStation.cl_rfs_cs_plus( self ) _G.g_rfsCraftStationGuiHost = self; csFwd( "plus" ) end
function RfsCraftStation.cl_rfs_cs_minus( self ) _G.g_rfsCraftStationGuiHost = self; csFwd( "minus" ) end
function RfsCraftStation.cl_rfs_cs_craft( self ) _G.g_rfsCraftStationGuiHost = self; csFwd( "craft" ) end
function RfsCraftStation.cl_rfs_cs_upgrade( self ) _G.g_rfsCraftStationGuiHost = self; csFwd( "upgrade" ) end
function RfsCraftStation.cl_rfs_cs_qty( self, ... ) _G.g_rfsCraftStationGuiHost = self; csFwd( "qty", ... ) end
function RfsCraftStation.cl_rfs_cs_pickUpgrade( self, buttonName ) _G.g_rfsCraftStationGuiHost = self; csFwd( "pickUpgrade", buttonName ) end
function RfsCraftStation.cl_rfs_cs_cancel( self, buttonName ) _G.g_rfsCraftStationGuiHost = self; csFwd( "cancel", buttonName ) end
function RfsCraftStation.cl_rfs_cs_viewSlot( self, buttonName ) _G.g_rfsCraftStationGuiHost = self; csFwd( "viewSlot", buttonName ) end

-- U (Tinker): with the tablet equipped this PAIRS. Without it, toggles Remote Crafting.
function RfsCraftStation.client_onTinker( self, character, state )
	if state ~= true then
		return
	end
	local tablet = type( RfsHandheldLcd ) == "table" and RfsHandheldLcd.wieldingRecipeViewer and RfsHandheldLcd.wieldingRecipeViewer()
	if tablet and self.network then
		self.network:sendToServer( "sv_n_pairViewer", {} )
		return
	end
	if self.network then
		self.network:sendToServer( "sv_rfs_toggleWireless", {} )
	end
end

function RfsCraftStation.cl_n_rfsPairTablet( self, params )
	if self.network then
		self.network:sendToServer( "sv_n_pairViewer", params or {} )
	end
end

function RfsCraftStation.sv_rfs_toggleWireless( self, params, player )
	if not serverCanUseStation( self, player ) then return end
	self.sv = self.sv or {}
	local on = self.sv.wireless == true or tostring( self.sv.wireless or "" ) == "true"
	self.sv.wireless = not on
	self:sv_saveStorage( true )
	self:sv_syncClients()
end

-- Upgrade the station via GUI. Costs Component Kits from the caller's inventory
-- (Component Kits: T2=5, T3=10, T4=15, T5=25).
function RfsCraftStation.sv_n_upgradeStation( self, params, player )
	if not serverCanUseStation( self, player ) then return end
	self.sv = self.sv or {}
	self.sv.tier = tonumber( self.sv.tier ) or 1
	if self.sv.tier >= MAX_TIER then
		return
	end
	local nextTier = TIERS[self.sv.tier + 1]
	local kits = tonumber( nextTier.kits ) or tonumber( nextTier.cost ) or 0
	if kits <= 0 then
		self.sv.tier = self.sv.tier + 1
		self:sv_saveStorage( true )
		self:sv_syncClients()
		return
	end
	local inv = nil
	pcall( function() inv = player:getInventory() end )
	if not inv then
		return
	end
	local kitUuid = sm.uuid.new( COMPONENT_UUID )
	local avail = 0
	pcall( function()
		avail = sm.container.totalQuantity( inv, kitUuid )
	end )
	if ( tonumber( avail ) or 0 ) < kits then
		pcall( function()
			sm.gui.chatMessage( string.format( "[RFS] Upgrade needs %d Component Kits", kits ) )
		end )
		return
	end
	sm.container.beginTransaction()
	local ok = pcall( function()
		sm.container.spend( inv, kitUuid, kits, true )
	end )
	if not ok then
		sm.container.endTransaction()
		return
	end
	if not sm.container.endTransaction() then
		return
	end
	self.sv.tier = self.sv.tier + 1
	self:sv_saveStorage( true )
	self:sv_syncClients()
	pcall( function()
		sm.gui.chatMessage( string.format( "[RFS] Crafting Station upgraded to tier %d", self.sv.tier ) )
	end )
end

function RfsCraftStation.sv_n_setCraftSpeed( self, params, player )
	if not serverCanUseStation( self, player ) then return end
	self.sv = self.sv or {}
	local info, tier = tierInfo( self )
	if tier < 2 then return end
	local step = math.max( 0, math.min( 6, math.floor( tonumber( params and params.step ) or 0 ) ) )
	local requested = 1 + step * 0.25
	self.sv.speedSetting = math.max( 1, math.min( info.maxSpeed or 1, requested ) )
	self:sv_saveStorage( true )
	self:sv_syncClients()
end

-- Legacy alias (old Components-based path) now routes to the kit upgrade.
RfsCraftStation.sv_rfs_upgrade = RfsCraftStation.sv_n_upgradeStation

-- =========================================================================
-- Crafting engine (vanilla Crafter.sv_craft pattern, station-local queue)
-- =========================================================================

local function findRecipeFor( itemId )
	local r
	pcall( function() r = RfsCraftQueue.findRecipe( itemId ) end )
	if type( r ) ~= "table" then
		local sets = g_craftingRecipeSets or {}
		itemId = tostring( itemId )
		for _, set in pairs( sets ) do
			if type( set ) == "table" and type( set.recipes ) == "table" and set.recipes[itemId] then
				r = set.recipes[itemId]
				break
			end
		end
	end
	return type( r ) == "table" and r or nil
end

isRecipeUnlocked = function( itemId )
	local ok = false
	pcall( function()
		if sm.isServerMode() and RecipeManager and RecipeManager.Sv_IsUnlocked then
			ok = RecipeManager.Sv_IsUnlocked( itemId ) == true
		end
	end )
	if ok then
		return true
	end
	local always = _G.g_rfsCraftbotAlwaysAvailable
	if type( always ) == "table" and always[tostring( itemId )] then
		return true
	end
	return false
end

local function copyRecipe( recipe )
	local copy = {
		itemId = tostring( recipe.itemId ),
		quantity = tonumber( recipe.quantity ) or 1,
		craftTime = math.ceil( tonumber( recipe.craftTime ) or 0 ),
		ingredientList = {},
	}
	for _, ing in ipairs( recipe.ingredientList or {} ) do
		copy.ingredientList[#copy.ingredientList + 1] = {
			itemId = tostring( ing.itemId ),
			quantity = tonumber( ing.quantity ) or 1,
		}
	end
	if type( recipe.extras ) == "table" then
		copy.extras = {}
		for _, ex in ipairs( recipe.extras ) do
			copy.extras[#copy.extras + 1] = {
				itemId = tostring( ex.itemId ),
				quantity = tonumber( ex.quantity ) or 1,
			}
		end
	end
	return copy
end

local function asContainer( obj )
	if obj == nil then
		return nil
	end
	if type( obj ) == "Container" then
		return obj
	end
	local target
	if type( obj ) == "Shape" then
		pcall( function()
			if GetPipeGraphObjectContainer then
				target = GetPipeGraphObjectContainer( obj )
			end
		end )
		if type( target ) ~= "Container" then
			pcall( function()
				target = obj:getInteractable():getContainer()
			end )
		end
		if type( target ) ~= "Container" then
			pcall( function()
				target = obj:getInteractable():getContainer( 0 )
			end )
		end
	else
		pcall( function()
			if obj.getContainer then
				target = obj:getContainer()
			elseif obj.getInteractable then
				target = obj:getInteractable():getContainer()
			else
				target = obj
			end
		end )
	end
	if type( target ) == "Container" then
		return target
	end
	return nil
end

local function addContainer( list, seen, obj )
	local c = asContainer( obj )
	if c == nil then
		return
	end
	local key = tostring( c )
	if seen[key] then
		return
	end
	seen[key] = true
	list[#list + 1] = c
end

local function localXOf( self, worldPos )
	local origin, axis
	pcall( function()
		origin = self.shape.worldPosition
		axis = self.shape.xAxis
	end )
	if not origin or not axis or not worldPos then
		return 0
	end
	-- Operator stands at the real front (opposite the dual LCDs). From that
	-- view, visual right is -X, so flip the part's +X axis.
	return -( worldPos - origin ):dot( axis )
end

-- Left = visual left / +X input. Right = visual right / -X output.
local function gatherSideContainers( self )
	local left, right, extra, seenL, seenR, seenX = {}, {}, {}, {}, {}, {}
	local function place( shape, obj, preferRight )
		local lx
		pcall( function()
			if shape and shape.worldPosition then
				lx = localXOf( self, shape.worldPosition )
			end
		end )
		if lx == nil then
			if preferRight == true then
				addContainer( right, seenR, obj )
			elseif preferRight == false then
				addContainer( left, seenL, obj )
			else
				addContainer( extra, seenX, obj )
			end
			return
		end
		if lx >= 0 then
			addContainer( right, seenR, obj )
		else
			addContainer( left, seenL, obj )
		end
	end
	pcall( function()
		for _, s in ipairs( sm.pipeGraph.getInputContainers( self.shape ) or {} ) do
			place( s, s, false )
		end
	end )
	pcall( function()
		for _, s in ipairs( sm.pipeGraph.getOutputContainers( self.shape ) or {} ) do
			place( s, s, true )
		end
	end )
	pcall( function()
		for _, c in ipairs( sm.pipeGraph.getMatchingPipedContainers( self.interactable ) or {} ) do
			place( nil, c, nil )
		end
	end )
	pcall( function()
		local seenPipe = {}
		local stack = { self.shape }
		while #stack > 0 do
			local s = table.remove( stack )
			local id
			pcall( function() id = s:getId() end )
			id = id or tostring( s )
			if s and not seenPipe[id] then
				seenPipe[id] = true
				if s ~= self.shape then
					place( s, s, nil )
				end
				local nbs
				pcall( function()
					nbs = s:getPipedNeighbours()
				end )
				for _, n in ipairs( nbs or {} ) do
					stack[#stack + 1] = n
				end
			end
		end
	end )
	pcall( function()
		for _, s in ipairs( self.shape:getBody():getShapes() or {} ) do
			if s ~= self.shape then
				local c
				pcall( function()
					c = s:getInteractable():getContainer()
				end )
				if c then
					place( s, c, nil )
				end
			end
		end
	end )
	return left, right, extra
end

getInputContainers = function( self, player )
	local left, right, extra = gatherSideContainers( self )
	local list, seen = {}, {}
	for _, c in ipairs( left ) do
		addContainer( list, seen, c )
	end
	for _, c in ipairs( extra ) do
		addContainer( list, seen, c )
	end
	for _, c in ipairs( right ) do
		addContainer( list, seen, c )
	end
	if player then
		local inv
		pcall( function()
			inv = player:getInventory()
		end )
		addContainer( list, seen, inv )
	end
	return list
end

local function playerById( id )
	if id == nil then
		return nil
	end
	local found
	pcall( function()
		for _, p in ipairs( sm.player.getAllPlayers() or {} ) do
			if p and p:getId() == id then
				found = p
				return
			end
		end
	end )
	return found
end

local function spendIngredients( self, recipe, player )
	sm.container.beginTransaction()
	local containers = getInputContainers( self, player )
	for _, ingredient in ipairs( recipe.ingredientList ) do
		local consumeCount = tonumber( ingredient.quantity ) or 1
		local ingUuid = sm.uuid.new( ingredient.itemId )
		for _, container in ipairs( containers ) do
			if consumeCount > 0 then
				local spent = 0
				pcall( function()
					spent = sm.container.spend( container, ingUuid, consumeCount, false ) or 0
				end )
				consumeCount = consumeCount - ( tonumber( spent ) or 0 )
			else
				break
			end
		end
		if consumeCount > 0 then
			sm.container.abortTransaction()
			return false
		end
	end
	return sm.container.endTransaction()
end

local function tryCollectInto( container, items, quantities )
	if type( container ) ~= "Container" then
		return false
	end
	for i, item in ipairs( items ) do
		local qty = quantities[i] or 1
		local fits = true
		pcall( function()
			if sm.container.canCollect then
				local result = sm.container.canCollect( container, item, qty )
				if result == false then
					fits = false
				end
			end
		end )
		if not fits then
			return false
		end
	end
	sm.container.beginTransaction()
	for i, item in ipairs( items ) do
		pcall( function()
			sm.container.collect( container, item, quantities[i] or 1, true )
		end )
	end
	return sm.container.endTransaction() == true
end

local function outputContainers( self )
	local left, right, extra = gatherSideContainers( self )
	local list, seen = {}, {}
	for _, c in ipairs( right ) do
		addContainer( list, seen, c )
	end
	for _, c in ipairs( extra ) do
		addContainer( list, seen, c )
	end
	for _, c in ipairs( left ) do
		addContainer( list, seen, c )
	end
	return list
end

local function containerIsFull( container )
	if container == nil then
		return true
	end
	local size = 0
	pcall( function()
		size = tonumber( container.size ) or 0
	end )
	if size < 1 then
		pcall( function()
			size = container:getSize() or 0
		end )
	end
	if size < 1 then
		pcall( function()
			size = sm.container.getSize( container ) or 0
		end )
	end
	if size < 1 then
		return false
	end
	for i = 0, size - 1 do
		local item
		pcall( function()
			item = container:getItem( i )
		end )
		if type( item ) ~= "table" then
			pcall( function()
				item = sm.container.getItem( container, i )
			end )
		end
		local qty = 0
		if type( item ) == "table" then
			qty = tonumber( item.quantity ) or 0
		end
		if qty < 1 then
			return false
		end
	end
	return true
end

storageIsFull = function( self )
	local left, right, extra = gatherSideContainers( self )
	if #left + #right + #extra == 0 then
		return true
	end
	for _, c in ipairs( right ) do
		if not containerIsFull( c ) then
			return false
		end
	end
	for _, c in ipairs( extra ) do
		if not containerIsFull( c ) then
			return false
		end
	end
	for _, c in ipairs( left ) do
		if not containerIsFull( c ) then
			return false
		end
	end
	return true
end

local function ejectAtRightPort( self, items, quantities )
	local pos, axis
	pcall( function()
		axis = self.shape.xAxis * -1
		pos = self.shape.worldPosition + axis * 2.0
	end )
	if not pos then
		return false
	end
	local loot = {}
	for i, item in ipairs( items ) do
		loot[#loot + 1] = { uuid = item, quantity = quantities[i] or 1 }
	end
	if type( SpawnLoot ) == "function" then
		local ok = pcall( SpawnLoot, self.shape, loot, pos, nil, 2, axis )
		if ok then
			return true
		end
	end
	local lootUuid = sm.uuid.new( "45209992-1a59-479e-a446-57140b605836" )
	local vel = ( axis or sm.vec3.new( 1, 0, 0 ) ) * 4
	for _, row in ipairs( loot ) do
		local ok = pcall( function()
			sm.projectile.shapeCustomProjectileAttack( { lootUid = row.uuid, lootQuantity = row.quantity }, lootUuid, 0, sm.vec3.new( 0, 0, 0 ), vel, self.shape, 0 )
		end )
		if not ok then
			return false
		end
	end
	return #loot > 0
end

local function collectToOutput( self, recipe )
	local items = { sm.uuid.new( recipe.itemId ) }
	local quantities = { recipe.quantity or 1 }
	if type( recipe.extras ) == "table" then
		for _, extra in ipairs( recipe.extras ) do
			items[#items + 1] = sm.uuid.new( extra.itemId )
			quantities[#quantities + 1] = extra.quantity or 1
		end
	end
	local list = outputContainers( self )
	for _, container in ipairs( list ) do
		if tryCollectInto( container, items, quantities ) then
			return true
		end
	end
	local shape
	pcall( function()
		shape = sm.pipeGraph.getContainerShapeToCollectTo( self.shape, items, quantities )
	end )
	if shape then
		return tryCollectInto( asContainer( shape ), items, quantities )
	end
	return false
end

local function spendFromObj( obj, uuid, left )
	if left <= 0 or obj == nil then
		return left
	end
	local target = obj
	pcall( function()
		if type( obj ) == "Shape" then
			local idx = 0
			pcall( function()
				local n = obj.getShapeOutputContainerIndex and obj:getShapeOutputContainerIndex()
				if n and n >= 0 then idx = n end
			end )
			target = obj:getInteractable():getContainer( idx )
		end
	end )
	local spent = 0
	pcall( function()
		spent = sm.container.spend( target, uuid, left, false ) or 0
	end )
	if spent == true then
		spent = left
	end
	return left - ( tonumber( spent ) or 0 )
end

local function spendItem( self, itemId, qty, player )
	qty = math.max( 1, math.floor( tonumber( qty ) or 1 ) )
	local uuid = sm.uuid.new( tostring( itemId ) )
	sm.container.beginTransaction()
	local left = qty
	for _, container in ipairs( getInputContainers( self, player ) ) do
		if left <= 0 then
			break
		end
		local spent = 0
		pcall( function()
			spent = sm.container.spend( container, uuid, left, false ) or 0
		end )
		if spent == true then
			spent = left
		end
		left = left - ( tonumber( spent ) or 0 )
	end
	if left > 0 then
		sm.container.abortTransaction()
		return false
	end
	return sm.container.endTransaction()
end

local function collectIngredients( self, recipe )
	if type( recipe ) ~= "table" then
		return false
	end
	local items, quantities = {}, {}
	for _, ing in ipairs( recipe.ingredientList or {} ) do
		if ing and ing.itemId then
			items[#items + 1] = sm.uuid.new( ing.itemId )
			quantities[#quantities + 1] = math.max( 1, math.floor( tonumber( ing.quantity ) or 1 ) )
		end
	end
	if #items == 0 then
		return true
	end
	local list = outputContainers( self )
	for _, container in ipairs( list ) do
		if tryCollectInto( container, items, quantities ) then
			return true
		end
	end
	local shape
	pcall( function()
		shape = sm.pipeGraph.getContainerShapeToCollectTo( self.shape, items, quantities )
	end )
	if shape then
		return tryCollectInto( asContainer( shape ), items, quantities )
	end
	return false
end

local function refundItem( player, itemId, qty )
	if not player or not itemId then
		return
	end
	local inv
	pcall( function() inv = player:getInventory() end )
	if not inv then
		return
	end
	sm.container.beginTransaction()
	pcall( function()
		sm.container.collect( inv, sm.uuid.new( itemId ), math.max( 1, math.floor( tonumber( qty ) or 1 ) ), true )
	end )
	sm.container.endTransaction()
end

-- Server: queue a craft. One slot = one item type; qty lives on that job.
-- Ingredients are taken when each unit starts, not up front.
function RfsCraftStation.sv_n_craftStation( self, params, player )
	local remote = params and params.remote == true
	if not serverCanUseStation( self, player ) and not ( remote and serverCanRemoteCraft( self, params, player ) ) then
		pcall( function()
			sm.gui.chatMessage( "[RFS] Add to Queue: too far or no player" )
		end )
		return 0
	end
	self.sv = self.sv or {}
	self.sv.crafts = type( self.sv.crafts ) == "table" and self.sv.crafts or {}
	local qty = math.max( 1, math.min( MAX_ORDER, math.floor( tonumber( params and params.qty ) or 1 ) ) )
	local itemId = tostring( params and params.itemId or "" )
	if itemId == "" then
		pcall( function() sm.gui.chatMessage( "[RFS] Add to Queue: no recipe" ) end )
		return 0
	end
	local recipe = findRecipeFor( itemId )
	if not recipe then
		pcall( function() sm.gui.chatMessage( "[RFS] Add to Queue: no recipe" ) end )
		return 0
	end
	if type( RfsCraftQueue ) ~= "table" or not RfsCraftQueue.isRecipeKnown( itemId ) then
		pcall( function() sm.gui.chatMessage( "[RFS] Could not queue (full or locked)" ) end )
		return 0
	end
	if not isRecipeUnlocked( recipe.itemId ) then
		pcall( function() sm.gui.chatMessage( "[RFS] Recipe is locked" ) end )
		return 0
	end
	local dest, existing = findOpenCraftJob( self, itemId )
	if not dest then
		dest = self
		if type( RfsCraftStationNet ) == "table" and RfsCraftStationNet.pickFillStation then
			local pick, free = RfsCraftStationNet.pickFillStation( self )
			if pick and free > 0 then
				dest = pick
			end
		end
	end
	dest.sv = dest.sv or {}
	dest.sv.crafts = type( dest.sv.crafts ) == "table" and dest.sv.crafts or {}
	local destInfo = dest == self and tierInfo( self ) or tierInfo( dest )
	local made = 0
	if existing then
		existing.count = jobRemaining( existing ) + qty
		existing.total = jobTotal( existing ) + qty
		existing.batchTotal = existing.total
		made = qty
	else
		if usedSlots( dest ) >= ( destInfo.slots or 4 ) then
			pcall( function()
				sm.gui.chatMessage( "[RFS] Could not queue (full or locked)" )
			end )
			return 0
		end
		local copy = copyRecipe( recipe )
		local effectiveSpeed = math.max( 1, math.min( destInfo.maxSpeed or 1, tonumber( dest.sv.speedSetting ) or 1 ) )
		local craftTime = math.ceil( copy.craftTime * 40 / effectiveSpeed )
		dest.sv.crafts[#dest.sv.crafts + 1] = {
			itemId = copy.itemId,
			recipe = copy,
			time = -1,
			craftTime = craftTime,
			waiting = true,
			paid = false,
			loop = false,
			count = qty,
			total = qty,
			batchId = ( sm.game.getServerTick() or 0 ) .. "_" .. itemId,
			batchTotal = qty,
			ownerId = player and player:getId() or nil,
		}
		made = qty
	end
	if made > 0 then
		self:sv_saveStorage()
		self:sv_syncClients()
		if dest ~= self and dest.sv_saveStorage then
			dest:sv_saveStorage()
			dest:sv_syncClients()
		end
		pcall( function()
			sm.gui.chatMessage( string.format( "[RFS] Queued %d", made ) )
		end )
	end
	return made
end

local function refundRecipe( player, recipe )
	if not player or type( recipe ) ~= "table" then
		return
	end
	local inv
	pcall( function() inv = player:getInventory() end )
	if not inv then
		return
	end
	sm.container.beginTransaction()
	for _, ing in ipairs( recipe.ingredientList or {} ) do
		pcall( function()
			sm.container.collect( inv, sm.uuid.new( ing.itemId ), tonumber( ing.quantity ) or 1, true )
		end )
	end
	sm.container.endTransaction()
end

function RfsCraftStation.sv_n_cancelStation( self, params, player )
	if not serverCanUseStation( self, player ) then return end
	self.sv = self.sv or {}
	self.sv.crafts = type( self.sv.crafts ) == "table" and self.sv.crafts or {}
	local index = math.floor( tonumber( params and params.index ) or 0 )
	if index < 1 or index > #self.sv.crafts then
		return
	end
	local playerId
	pcall( function() playerId = player:getId() end )
	local entry = self.sv.crafts[index]
	-- Legacy saved rows have no owner. They remain cancellable for save
	-- compatibility, but only newly queued rows carry a refund recipient.
	if entry and ( entry.ownerId == nil or entry.ownerId == playerId ) then
		if entry.ownerId == playerId and entry.paid == true then
			refundRecipe( player, entry.recipe )
		end
		table.remove( self.sv.crafts, index )
	end
	self:sv_saveStorage()
	self:sv_syncClients()
end

function RfsCraftStation.sv_n_recycleStation( self, params, player )
	params = params or {}
	player = player or params.player
	if not serverCanUseStation( self, player ) then
		pcall( function()
			sm.gui.chatMessage( "[RFS] Recycle: too far or no player" )
		end )
		return 0
	end
	self.sv = self.sv or {}
	self.sv.recycles = type( self.sv.recycles ) == "table" and self.sv.recycles or {}
	local info = tierInfo( self )
	local qty = math.max( 1, math.min( MAX_ORDER, math.floor( tonumber( params and params.qty ) or 1 ) ) )
	local itemId = tostring( params and params.itemId or "" )
	if itemId == "" then
		pcall( function() sm.gui.chatMessage( "[RFS] Recycle: no recipe" ) end )
		return 0
	end
	local recipe = findRecipeFor( itemId )
	if not recipe then
		pcall( function() sm.gui.chatMessage( "[RFS] Recycle: no recipe" ) end )
		return 0
	end
	local existing = findJobByItem( self.sv.recycles, itemId )
	local made = 0
	if existing then
		existing.count = jobRemaining( existing ) + qty
		existing.total = jobTotal( existing ) + qty
		existing.batchTotal = existing.total
		made = qty
	else
		if usedSlots( self ) >= ( info.slots or 4 ) then
			pcall( function()
				sm.gui.chatMessage( "[RFS] Could not queue (full or locked)" )
			end )
			return 0
		end
		local effectiveSpeed = math.max( 1, math.min( info.maxSpeed or 1, tonumber( self.sv.speedSetting ) or 1 ) )
		-- Recycle takes the same time as crafting that item, plus 3 seconds.
		local craftTime = math.max( 40, math.ceil( ( ( tonumber( recipe.craftTime ) or 1 ) + 3 ) * 40 / effectiveSpeed ) )
		self.sv.recycles[#self.sv.recycles + 1] = {
			itemId = itemId,
			recipe = copyRecipe( recipe ),
			time = -1,
			craftTime = craftTime,
			waiting = true,
			paid = false,
			count = qty,
			total = qty,
			batchId = ( sm.game.getServerTick() or 0 ) .. "_r_" .. itemId,
			batchTotal = qty,
			ownerId = player and player:getId() or nil,
		}
		made = qty
	end
	if made > 0 then
		self:sv_saveStorage()
		self:sv_syncClients()
		pcall( function()
			sm.gui.chatMessage( string.format( "[RFS] Recycle queued %d", made ) )
		end )
	end
	return made
end

function RfsCraftStation.sv_n_cancelRecycle( self, params, player )
	if not serverCanUseStation( self, player ) then return end
	self.sv = self.sv or {}
	self.sv.recycles = type( self.sv.recycles ) == "table" and self.sv.recycles or {}
	local index = math.floor( tonumber( params and params.index ) or 0 )
	if index < 1 or index > #self.sv.recycles then
		return
	end
	local playerId
	pcall( function() playerId = player:getId() end )
	local entry = self.sv.recycles[index]
	if entry and ( entry.ownerId == nil or entry.ownerId == playerId ) then
		if entry.ownerId == playerId then
			local remaining = jobRemaining( entry )
			local refundQty = 0
			if entry.paid == true then
				refundQty = 1
			elseif entry.paid == nil then
				refundQty = remaining
			end
			refundQty = refundQty + math.max( 0, math.floor( tonumber( entry.prepaid ) or 0 ) )
			if refundQty > 0 then
				refundItem( player, entry.itemId, refundQty )
			end
		end
		table.remove( self.sv.recycles, index )
	end
	self:sv_saveStorage()
	self:sv_syncClients()
end

function RfsCraftStation.sv_n_pairViewer( self, params, player )
	params = params or {}
	player = player or params.player
	if not player and params.playerId then
		local want = tonumber( params.playerId )
		pcall( function()
			for _, p in ipairs( sm.player.getAllPlayers() or {} ) do
				if p:getId() == want then
					player = p
					return
				end
			end
		end )
	end
	if player then
		pcall( function()
			local dist = ( player.character.worldPosition - self.shape.worldPosition ):length()
			if dist and dist <= 16 then
				self.sv.wireless = true
			end
		end )
	end
	local ok, why = false, "net"
	if type( RfsCraftStationNet ) == "table" then
		ok, why = RfsCraftStationNet.sv_pair( self, player )
	end
	self:sv_saveStorage( true )
	self:sv_syncClients()
	pcall( function()
		sm.gui.chatMessage( "[RFS] Pair " .. tostring( why or ok ) )
	end )
	local snap = {}
	pcall( function()
		snap = RfsCraftStationNet.pairSnapshot( self, player )
	end )
	pcall( function()
		local pid
		if player then
			pid = player:getId()
		end
		sm.event.sendToGame( "sv_rfs_craftPairForward", { playerId = pid, snap = snap } )
	end )
	if player and _G.g_rfsGame and _G.g_rfsGame.network then
		pcall( function()
			_G.g_rfsGame.network:sendToClient( player, "cl_rfs_craftPairSync", snap )
		end )
	end
end

function RfsCraftStation.sv_n_setPairPrio( self, params, player )
	local ok = false
	if type( RfsCraftStationNet ) == "table" then
		ok = RfsCraftStationNet.sv_setPrio( self, player, params and params.prio ) == true
	end
	self:sv_saveStorage( true )
	self:sv_syncClients()
	if player and _G.g_rfsGame and _G.g_rfsGame.network then
		_G.g_rfsGame.network:sendToClient( player, "cl_rfs_craftPairSync", RfsCraftStationNet.pairSnapshot( self, player ) )
	end
	pcall( function()
		if ok then
			sm.gui.chatMessage( string.format( "[RFS] Queue priority %d", math.floor( tonumber( params and params.prio ) or 0 ) ) )
		else
			sm.gui.chatMessage( "[RFS] PAIR a Crafting Station before setting priority" )
		end
	end )
end

function RfsCraftStation.sv_n_sendRemote( self, params, player )
	local n = 0
	if type( RfsCraftStationNet ) == "table" then
		n = RfsCraftStationNet.sv_fillRemote( self ) or 0
	end
	pcall( function()
		sm.gui.chatMessage( string.format( "[RFS] Remote craft queued %d", n ) )
	end )
end

-- Server: tick the craft queue even if nobody has the E-menu open.
-- Game.lua pulses every station once per server tick; do not also tick from
-- server_onFixedUpdate or recycle/craft both run twice as fast.
function RfsCraftStation.sv_tickQueue( self )
	self.sv = self.sv or {}
	self.sv.crafts = type( self.sv.crafts ) == "table" and self.sv.crafts or {}
	local pulse = _G.g_rfsCraftPulse
	if pulse == nil then
		pulse = sm.game.getServerTick() or 0
	end
	if self.sv.queuePulse == pulse then
		return
	end
	self.sv.queuePulse = pulse
	local tick = sm.game.getServerTick() or 0
	self.sv.queueTickAt = tick
	self.sv.recycles = type( self.sv.recycles ) == "table" and self.sv.recycles or {}
	local full = storageIsFull( self )
	if self.sv.storageFull ~= full then
		self.sv.storageFull = full
		self.sv.clientDirty = true
	end
	if #self.sv.crafts == 0 and #self.sv.recycles == 0 then
		if self.sv.clientDirty or ( tick % 10 ) == 0 then
			self:sv_syncClients()
		end
		return
	end
	if not self:sv_isPowered() then
		if self.sv.clientDirty then
			self:sv_syncClients()
		end
		return
	end
	local finished = false
	for idx = #self.sv.crafts, 1, -1 do
		local entry = self.sv.crafts[idx]
		if entry then
			if entry.recipe == nil and entry.itemId then
				entry.recipe = findRecipeFor( entry.itemId )
			end
			local recipe = entry.recipe
			local craftTime = math.max( 1, tonumber( entry.craftTime ) or 40 )
			if entry.time == nil then
				entry.time = -1
			end
			if entry.paid == nil then
				entry.paid = true
			end
			local owner = playerById( entry.ownerId )
			if recipe and entry.paid ~= true then
				if spendIngredients( self, recipe, owner ) then
					entry.paid = true
					entry.waiting = false
					entry.time = -1
					entry.startedTick = tick
					self.sv.clientDirty = true
				elseif not entry.waiting then
					entry.waiting = true
					self.sv.clientDirty = true
				end
			end
			if entry.paid == true and entry.startedTick ~= tick and entry.time < craftTime then
				entry.time = entry.time + 1
				if entry.waiting then
					entry.waiting = false
					self.sv.clientDirty = true
				end
			end
			if entry.paid == true and entry.startedTick ~= tick and entry.time >= craftTime then
				if recipe and collectToOutput( self, recipe ) then
					local remaining = jobRemaining( entry ) - 1
					if remaining > 0 then
						entry.count = remaining
						entry.paid = false
						entry.time = -1
						entry.waiting = true
					elseif entry.loop == true then
						entry.paid = false
						entry.time = -1
						entry.waiting = true
						if spendIngredients( self, recipe, owner ) then
							entry.paid = true
							entry.waiting = false
							entry.startedTick = tick
						end
					else
						table.remove( self.sv.crafts, idx )
					end
					finished = true
					self.sv.clientDirty = true
				elseif not entry.waiting then
					entry.waiting = true
					self.sv.clientDirty = true
				end
			end
		end
	end
	for idx = #self.sv.recycles, 1, -1 do
		local entry = self.sv.recycles[idx]
		if entry then
			if entry.recipe == nil and entry.itemId then
				entry.recipe = findRecipeFor( entry.itemId )
			end
			local craftTime = math.max( 1, tonumber( entry.craftTime ) or 40 )
			if entry.time == nil then
				entry.time = -1
			end
			if entry.prepaid == nil then
				if entry.paid == nil then
					entry.prepaid = jobRemaining( entry )
				else
					entry.prepaid = 0
				end
			end
			local owner = playerById( entry.ownerId )
			if entry.paid ~= true then
				if ( tonumber( entry.prepaid ) or 0 ) > 0 then
					entry.prepaid = ( tonumber( entry.prepaid ) or 0 ) - 1
					entry.paid = true
					entry.waiting = false
					entry.time = -1
					entry.startedTick = tick
					self.sv.clientDirty = true
				elseif spendItem( self, entry.itemId, 1, owner ) then
					entry.paid = true
					entry.waiting = false
					entry.time = -1
					entry.startedTick = tick
					self.sv.clientDirty = true
				elseif not entry.waiting then
					entry.waiting = true
					self.sv.clientDirty = true
				end
			end
			if entry.paid == true and entry.startedTick ~= tick and entry.time < craftTime then
				entry.time = entry.time + 1
				if entry.waiting then
					entry.waiting = false
					self.sv.clientDirty = true
				end
			end
			if entry.paid == true and entry.startedTick ~= tick and entry.time >= craftTime then
				if entry.recipe and collectIngredients( self, entry.recipe ) then
					local remaining = jobRemaining( entry ) - 1
					if remaining > 0 then
						entry.count = remaining
						entry.paid = false
						entry.time = -1
						entry.waiting = true
					else
						table.remove( self.sv.recycles, idx )
					end
					finished = true
					self.sv.clientDirty = true
				elseif not entry.waiting then
					entry.waiting = true
					self.sv.clientDirty = true
				end
			end
		end
	end
	if finished then
		self:sv_saveStorage()
	end
	local full = storageIsFull( self )
	if self.sv.storageFull ~= full then
		self.sv.storageFull = full
		self.sv.clientDirty = true
	end
	if self.sv.clientDirty or ( tick % 10 ) == 0 then
		self:sv_syncClients()
	end
end

function RfsCraftStation.server_onFixedUpdate( self )
	-- Queue is pulsed from RecipeFrameworkSurvival.server_onFixedUpdate.
end

-- Client GUI (binds cl_cs_* callbacks onto this class).
-- GUI is loaded from Game.lua so this interactable stays under SM script limits.

print( "[RFS] RfsCraftStation loaded (6x5x4; E menu + U wireless + per-station tiers)" )