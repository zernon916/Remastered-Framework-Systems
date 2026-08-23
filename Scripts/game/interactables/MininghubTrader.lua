-- Recipe Framework Survival owned copy (vanilla MininghubTrader + original merge hook)

dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$GAME_DATA/Scripts/game/managers/TileStorageManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/ProgressionManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/DialogManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_logs.lua" )
dofile("$SURVIVAL_DATA/Scripts/game/characters/shared_animation.lua" )

local TradeData = dofile( "$SURVIVAL_DATA/CraftingRecipes/mininghubTrader.json" )


local function rfsItemPresentOnPeer( itemId )
	local id = tostring( itemId or "" )
	if id == "" then
		return false
	end
	local okUuid, uuid = pcall( sm.uuid.new, id )
	if not okUuid or not uuid then
		return false
	end
	local exists = false
	pcall( function()
		if sm.shape.uuidExists and sm.shape.uuidExists( uuid ) then
			exists = true
		end
	end )
	if not exists then
		pcall( function()
			if sm.tool and sm.tool.uuidExists and sm.tool.uuidExists( uuid ) then
				exists = true
			end
		end )
	end
	if not exists then
		return false
	end
	local title = nil
	pcall( function()
		title = sm.shape.getShapeTitle( uuid )
	end )
	if type( title ) == "string" then
		local lower = string.lower( title )
		if title == "" or string.find( lower, "not found", 1, true ) then
			return false
		end
	end
	return true
end

-- Recipe Framework Survival: merge mod trades from _G.g_extraMiningHubTrades.
-- Strip missing-mod UUIDs so the shop never shows "BLOCK NOT FOUND" ghosts.
local function ensureExtraMiningTrades()
	local extraIds = {}
	if type( _G.g_extraMiningHubTrades ) == "table" then
		local keptExtras = {}
		local strippedExtras = 0
		for _, t in ipairs( _G.g_extraMiningHubTrades ) do
			if type( t ) == "table" and t.itemId then
				local id = tostring( t.itemId )
				extraIds[id] = true
				if t.cosmetic or rfsItemPresentOnPeer( id ) then
					keptExtras[#keptExtras + 1] = t
				else
					strippedExtras = strippedExtras + 1
				end
			end
		end
		_G.g_extraMiningHubTrades = keptExtras
		if strippedExtras > 0 then
			print( "[RFS MininghubTrader] stripped " .. tostring( strippedExtras ) .. " missing-mod extra trades" )
		end
	end
	do
		local kept = {}
		local stripped = 0
		for _, t in ipairs( TradeData ) do
			if type( t ) == "table" and t.itemId then
				local id = tostring( t.itemId )
				if ( t._rfs or extraIds[id] ) and ( not t.cosmetic ) and ( not rfsItemPresentOnPeer( id ) ) then
					stripped = stripped + 1
				else
					kept[#kept + 1] = t
				end
			else
				kept[#kept + 1] = t
			end
		end
		if stripped > 0 then
			for i = #TradeData, 1, -1 do
				TradeData[i] = nil
			end
			for i, t in ipairs( kept ) do
				TradeData[i] = t
			end
			print( "[RFS MininghubTrader] stripped " .. tostring( stripped ) .. " missing-mod shop rows" )
		end
	end
	if _G.g_miningHubExtraTradesMerged and not _G.g_miningHubExtraTradesDirty then
		return
	end
	local extras = _G.g_extraMiningHubTrades
	if type( extras ) ~= "table" or #extras == 0 then
		_G.g_miningHubExtraTradesMerged = true
		_G.g_miningHubExtraTradesDirty = false
		return
	end
	local seen = {}
	for _, t in ipairs( TradeData ) do
		if t and t.itemId then
			seen[tostring( t.itemId )] = true
		end
	end
	local added = 0
	local baseOrder = #TradeData
	for _, t in ipairs( extras ) do
		if type( t ) == "table" and t.itemId then
			local id = tostring( t.itemId )
			if ( not t.cosmetic ) and ( not rfsItemPresentOnPeer( id ) ) then
				-- Ghost: skip
			elseif not seen[id] then
				local entry = {
					itemId = id,
					quantity = t.quantity or 1,
					craftTime = t.craftTime or 0,
					ingredientList = t.ingredientList or {},
					schematic = t.schematic,
					cosmetic = t.cosmetic,
					extras = t.extras,
					order = baseOrder + added + 1,
					_rfs = true,
				}
				if entry.schematic == nil then
					entry.schematic = true
				end
				TradeData[#TradeData + 1] = entry
				seen[id] = true
				added = added + 1
			end
		end
	end
	_G.g_miningHubExtraTradesMerged = true
	_G.g_miningHubExtraTradesDirty = false
	if added > 0 then
		print( "[RFS MininghubTrader] Merged " .. tostring( added ) .. " mod trades" )
	end
end

local function Cl_IsMiningHubActivated()
	local miningHubActivated = QuestManager.Cl_IsQuestActive("quest_activate_mininghub") and QuestManager.Cl_GetQuestStage( "quest_activate_mininghub" )	
	local questCompleted = QuestManager.Cl_IsQuestComplete( "quest_activate_mininghub" )
	return miningHubActivated and miningHubActivated >= ActivateMininghubQuest.Stages.activate_pylon or questCompleted
end
for i, v in ipairs(TradeData) do
	v.order = i
end

local function getItemPriority( item )
	if item.logItem then return 0
	elseif item.schematic then return 0
	elseif item.cosmetic then return 0
	else return 0 end
end

local function RemoveUnusedItemSlotProperties( Widget )
	removeFromArray( Widget.Childs, function( widget )
		if widget.Type == "EffectBox" then
			return true
		end
	end )
	Widget.onMouseWheel = nil
	for _, value in ipairs(Widget.Childs) do
		value.onMouseWheel = nil
	end
end




table.sort(TradeData, function(a, b)
	local aPrio, bPrio = getItemPriority(a), getItemPriority(b)
	if aPrio == bPrio then
		return a.order < b.order
	end
	return aPrio < bPrio
end)
local ItemSlot = DeepCopy( dofile( "$SURVIVAL_DATA/Gui/JsonGuis/ItemSlot.gui" ) )

local ItemRootWidget = FindWidget( ItemSlot, "Item" )
local ItemImageWidget = FindWidget( ItemSlot, "Image" )
FindWidget( ItemSlot, "Quantity" ).Visible = false
FindWidget( ItemSlot, "KeyItem" ).Visible = false
FindWidget( ItemSlot, "Type").Visible = false

local ItemSlotSchematic = DeepCopy( dofile( "$SURVIVAL_DATA/Gui/JsonGuis/ItemSlotSchematic.gui" ) )

local ItemRootWidgetSchematic = FindWidget( ItemSlotSchematic, "Item" )
local ItemImageWidgetSchematic = FindWidget( ItemSlotSchematic, "Image" )

local ItemSlotCosmetic = DeepCopy( dofile( "$SURVIVAL_DATA/Gui/JsonGuis/ItemSlotCosmetic.gui" ) )
local ItemRootWidgetCosmetic = FindWidget( ItemSlotCosmetic, "Item" )
local ItemImageWidgetCosmetic = FindWidget( ItemSlotCosmetic, "Image" )

RemoveUnusedItemSlotProperties( ItemSlot )
RemoveUnusedItemSlotProperties( ItemSlotSchematic )
RemoveUnusedItemSlotProperties( ItemSlotCosmetic )

local TraderGui = {}
TraderGui.json = DeepCopy( dofile( "$SURVIVAL_DATA/Gui/JsonGuis/MininghubTrader.gui" ) )

TraderGui.MainPanel = FindWidget( TraderGui.json, "MainPanel" )
TraderGui.TradePanel = FindWidget( TraderGui.json, "TradePanel" )

TraderGui.AvailableAmountValue = FindWidget( TraderGui.MainPanel, "AvailableAmountValue" )

TraderGui.Preview = FindWidget( TraderGui.TradePanel, "Preview" )
TraderGui.Title = FindWidget( TraderGui.TradePanel, "Title" )
TraderGui.DescriptionBox = FindWidget( TraderGui.TradePanel, "DescriptionBox" )
TraderGui.CostValue = FindWidget( TraderGui.TradePanel, "CostValue" )

TraderGui.TradeIcon = FindWidget( TraderGui.TradePanel, "TradeIcon" )
TraderGui.TradeCount = FindWidget( TraderGui.TradePanel, "TradeCount" )
TraderGui.TradeButton = FindWidget( TraderGui.TradePanel, "TradeButton" )

TraderGui.Tabs = {
	Parts = FindWidget( TraderGui.MainPanel, "Parts" ),
	All = FindWidget( TraderGui.MainPanel, "All" ),
	Cosmetics = FindWidget( TraderGui.MainPanel, "Cosmetics" )
}
TraderGui.scrollView = FindWidget(TraderGui.MainPanel,"ItemContentPanel")

local CostTextColor = "#909292"
local TradeCountColor1 = "#9D8641"
local TradeCountColor2 = "#FFD44A"

local SufficientIngredientColor = "#A3CD46"
local InsufficientIngredientColor = "#F42B2B"


MininghubTrader = class( nil )

local OpenShutterDistance = 10.0
local CloseShutterDistance = 15.0

-- Quests that can ask the trader to hand over an access card ("vault quota key").
-- The active quest publishes clientPublicData.traderResponse == "give_access_card" and the card
-- log uuid in clientPublicData.traderCardLog.
local CardQuests = { "quest_activate_mininghub", "quest_vault_1", "quest_vault_2", "quest_vault_3" }

local filters = {
	Parts = function( tradeData )
		return tradeData.cosmetic
	end,
	All = function( tradeData )
		return false
	end,
	Cosmetics = function( tradeData )
		return tradeData.cosmetic == nil
	end
}


local function amountToString( amount )
	if amount >= 0 then
		return tostring( amount )
	else
		return tostring( "-" .. math.abs( amount ) )
	end
end

local ItemSlotSettings = {
	schematic = { 
		slotWidget = ItemSlotSchematic,
		itemRootWidget = ItemRootWidgetSchematic,
		imageWidget = ItemImageWidgetSchematic,
		getCaption = sm.shape.getShapeTitle,
		getDescription = sm.shape.getShapeDescription,
		getResourceGroupAndName = function( itemId )
			return sm.gui.getItemIconFromUuid( sm.uuid.new( itemId ))
		end,
		isUnlocked = function( self,itemId )
			return RecipeManager.Cl_IsUnlocked( itemId ) or self.cl.unlockedSchematic == itemId
		end
	},
	part = { 
	slotWidget = ItemSlot,
	itemRootWidget = ItemRootWidget,
	imageWidget = ItemImageWidget,
	getCaption = sm.shape.getShapeTitle,
	getDescription = sm.shape.getShapeDescription,

	getResourceGroupAndName = function( itemId )
			return sm.gui.getItemIconFromUuid( sm.uuid.new( itemId ))
		end,
	isUnlocked = function( self, itemId )
		return false
	end
	},
	cosmetic = { 
		slotWidget = ItemSlotCosmetic,
		itemRootWidget = ItemRootWidgetCosmetic,
		imageWidget = ItemImageWidgetCosmetic,
		getCaption = sm.localPlayer.getGarmentName,		
		getDescription = function (uuid) return "" end,
		getResourceGroupAndName = function( itemId )
			return "CustomizationIconMap", "CustomizationIconMap", tostring(itemId).."_male"
		end,
		isUnlocked = function( self, itemId )
			return sm.localPlayer.isGarmentUnlocked( sm.uuid.new( itemId ) ) or self.cl.unlockedCosmetic == itemId
		end
	},
	logItem = {
		slotWidget = ItemSlot,
		itemRootWidget = ItemRootWidget,
		imageWidget = ItemImageWidget,
		getCaption = sm.shape.getShapeTitle,
		getDescription = sm.shape.getShapeDescription,
		getResourceGroupAndName = function( itemId )
			return sm.gui.getItemIconFromUuid( sm.uuid.new( itemId ))
		end,
		isUnlocked = function( self, itemId ) 
			local log = LogEntryManager.Cl_GetLogFromItemUuid( itemId )
			if log then
				return LogEntryManager.Cl_HasLog( log )
			else
				sm.log.warning( "MininghubTrader: No log data found associated with item UUID "..tostring( itemId ) )
				return false
			end
		end
	}
}

function MininghubTrader.cl_updateGui( self )
	if self.cl.updateGui == false then
		return
	end
	local availableAmount = self.cl.vaultTotal - self.cl.spentTotal
	TraderGui.AvailableAmountValue.Caption = ( availableAmount >= 0 and SufficientIngredientColor or InsufficientIngredientColor )..amountToString( self.cl.vaultTotal - self.cl.spentTotal )
	-- trade options
	local filter = self.cl.activeTab 
	if self.cl.gui then
		TraderGui.scrollView.Childs = {}
		ensureExtraMiningTrades()
		local shopItemCount = 0

		local setupImageWidget = function(itemTypeSettings,itemId, tradeDataIndex )
			local resource,group, name = itemTypeSettings.getResourceGroupAndName( itemId )
			itemTypeSettings.imageWidget.ImageResource = resource
			itemTypeSettings.imageWidget.ImageGroup = group
			itemTypeSettings.imageWidget.ImageName = name
			itemTypeSettings.itemRootWidget.onClick = "cl_selectTrade"
			itemTypeSettings.itemRootWidget.onClickData = { tradeDataIndex = tradeDataIndex, shopIndex = #TraderGui.scrollView.Childs + 1 }
			table.insert(  TraderGui.scrollView.Childs,DeepCopy( itemTypeSettings.slotWidget ) )
		end
		for tradeDataIndex, tradeData in ipairs( TradeData ) do
			if tradeData._rfs and ( not tradeData.cosmetic ) and ( not rfsItemPresentOnPeer( tradeData.itemId ) ) then
				-- Skip missing-mod ghosts
			elseif(filters[filter] and not filters[filter]( tradeData )) then
				local itemTypeSettings = tradeData.schematic and ItemSlotSettings.schematic or tradeData.logItem and ItemSlotSettings.logItem or tradeData.cosmetic and ItemSlotSettings.cosmetic or ItemSlotSettings.part
				if not itemTypeSettings.isUnlocked(self,tradeData.itemId) then
					shopItemCount = shopItemCount + 1
					setupImageWidget(itemTypeSettings, tradeData.itemId, tradeDataIndex )
				end
			end
		end
		
		if shopItemCount == 0 then
			TraderGui.DescriptionBox.Caption = "No items available for trade"
		end
		local gridItems = TraderGui.scrollView.Childs
			
		for _, item in ipairs( gridItems ) do
			item.StateSelected = false
		end

		if self.cl.selectedItem ~= nil and self.cl.selectedItem.shopIndex then
			gridItems[self.cl.selectedItem.shopIndex].StateSelected = true
			TraderGui.TradePanel.Visible = true
			
			local displayTrade = TradeData[self.cl.selectedItem.tradeDataIndex]
			local itemTypeSettings = displayTrade.schematic and ItemSlotSettings.schematic or displayTrade.logItem and ItemSlotSettings.logItem or displayTrade.cosmetic and ItemSlotSettings.cosmetic or ItemSlotSettings.part
			local uuid = sm.uuid.new( displayTrade.itemId )
			
			local resource, group, name = itemTypeSettings.getResourceGroupAndName( displayTrade.itemId )
			TraderGui.TradeIcon.ImageResource = resource
			TraderGui.TradeIcon.ImageGroup = group
			TraderGui.TradeIcon.ImageName = name
			
			TraderGui.TradeCount.Caption = TradeCountColor1.."x"..TradeCountColor2..tostring( displayTrade.quantity )
			local calculatedTextWidth, _ = sm.gui.computeTextSize( TraderGui.TradeCount.Caption, TraderGui.TradeCount.FontName, TraderGui.TradeCount.TextAlign )
			TraderGui.TradeCount.width = calculatedTextWidth
			
			local sufficientIngredients = true

			local ingredient = displayTrade.ingredientList[1]
			
			if displayTrade.itemId == tostring( ITEMS.obj_controlstation_key01 ) then
				sufficientIngredients = self.cl.milestoneIndex >= 1
				TraderGui.CostValue.Caption = sufficientIngredients and CostTextColor.."Free" or InsufficientIngredientColor.."LOCKED"
			elseif displayTrade.itemId == tostring( ITEMS.obj_controlstation_key02 ) then
				sufficientIngredients = self.cl.milestoneIndex >= 2
				TraderGui.CostValue.Caption = sufficientIngredients and CostTextColor.."Free" or InsufficientIngredientColor.."LOCKED"
			elseif displayTrade.itemId == tostring( ITEMS.obj_controlstation_key03 ) then
				sufficientIngredients = self.cl.milestoneIndex >= 3
				TraderGui.CostValue.Caption = sufficientIngredients and CostTextColor.."Free" or InsufficientIngredientColor.."LOCKED"
			elseif ingredient then
				local ingredientUuid = sm.uuid.new( ingredient.itemId )
				assert( ingredientUuid == ITEMS.obj_resource_wonkstonks )

				local currentIngredientQty = self.cl.vaultTotal - self.cl.spentTotal
				local color = SufficientIngredientColor

				local sufficient = currentIngredientQty >= ingredient.quantity
				if not sufficient then
					color = InsufficientIngredientColor
				end
				sufficientIngredients = sufficientIngredients and sufficient

				TraderGui.CostValue.Caption = color..amountToString( ingredient.quantity )
			else
				TraderGui.CostValue.Caption = CostTextColor.."Free"
			end
			TraderGui.DescriptionBox.Caption = itemTypeSettings.getDescription( uuid )
			TraderGui.Title.Caption = itemTypeSettings.getCaption( uuid )
			TraderGui.Preview.ItemPreview = tostring( uuid )
			TraderGui.TradeButton.Enabled = sufficientIngredients
		else
			TraderGui.TradePanel.Visible = false
		end
	end

	self.cl.draw = true
	self.cl.updateGui = false
end

function MininghubTrader.server_onCreate( self )
	self.sv = {}
	self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.interactable )
	self.sv.saved = self.storage:load() or {}
	local saveDirty = self.sv.saved.hasInteracted == nil
	self.sv.saved.hasInteracted = self.sv.saved.hasInteracted == true
	local vaultTotal = ProgressionManager.Sv_GetVaultTotal()
	local spentTotal = TileStorageManager.Sv_GetValue( self.sv.tileStorageKey, "traderSpentTotal" ) or 0
	local milestoneIndex = TileStorageManager.Sv_GetValue( self.sv.tileStorageKey, "vaultMilestone" ) or 0
	self.network:setClientData( vaultTotal, 1 )
	self.network:setClientData( spentTotal, 2 )
	self.network:setClientData( milestoneIndex, 3 )
	self.network:setClientData( self.sv.saved.hasInteracted, 4 )
	if saveDirty then
		self.storage:save( self.sv.saved )
	end
	
end

function MininghubTrader.sv_n_questInteract( self )
	QuestManager.Sv_SendEvent( "axobot_interaction_complete" )
end

function MininghubTrader.sv_n_questGiveCard( self, params )
	local cardLog = ( params and params.card ) or LOGS.log_accesscard_01
	local uuid = sm.uuid.new( cardLog )
	if not LogEntryManager.Sv_HasLog( uuid ) then
		LogEntryManager.Sv_AddLog( uuid )
		QuestManager.Sv_SendEvent( "axobot_card_taken" )
		self.network:sendToClients( "cl_n_tradeCompleted", { unlockedLog = cardLog } )
	end
end

function MininghubTrader.sv_n_questClose( self )
	QuestManager.Sv_SendEvent( "axobot_gui_closed" )
end

function MininghubTrader.sv_n_firstInteract( self )
	if not self.sv.saved.hasInteracted then
		self.sv.saved.hasInteracted = true
		self.storage:save( self.sv.saved )
		self.network:setClientData( true, 4 )
	end
end


function MininghubTrader.server_onFixedUpdate( self )
	local vaultTotal = ProgressionManager.Sv_GetVaultTotal()
	local spentTotal = TileStorageManager.Sv_GetValue( self.sv.tileStorageKey, "traderSpentTotal" ) or 0
	local milestoneIndex = TileStorageManager.Sv_GetValue( self.sv.tileStorageKey, "vaultMilestone" ) or 0

	
	self.network:setClientData( vaultTotal, 1 )
	self.network:setClientData( spentTotal, 2 )
	self.network:setClientData( milestoneIndex, 3 )

end

-- Animation States
local char_vendor =
{
	Open = { nextAnimation = "Idle" },
	Close = { variation = { Rest = 0.8, Rest_special = 0.2  } },
	Idle = true,
	Rest = true,
	Confirm01 = { nextAnimation = "Idle" },
	Confirm02 = { nextAnimation = "Idle" },
	Offline = true,
	Rest_special = { variation = { Rest = 0.4, Rest_special = 0.6 } },
	Wakeup = { nextAnimation = "Idle" },
	Talk = true,
	aimbend_updown = { controlled = true, lerpSpeed = 1.0 / 15.0 },
	aimbend_leftright = { controlled = true, lerpSpeed = 1.0 / 15.0 },
	
}
-- Client

function MininghubTrader.client_onCreate( self )
	self.cl = {}
	-- RFS: register for /mshop remote open (real mining hub instance + vault state)
	_G.g_rfsMininghubTrader = self
	DialogManager.Cl_RegisterSpeaker( self.interactable, DialogSpeakerName.Axobot )
	self.cl.activeTab = "All"
	self.cl.minehubActivated = false
	self.cl.hasInteracted = false
	self.cl.animations = self.cl.animations or {}
	for name, data in pairs( char_vendor ) do
		local args = (type(data) == "table" and data) or nil
		INIT_ANIMATION( self.cl.animations, self.interactable, name, args )
	end

	self.cl.animator = CREATE_ANIMATOR( self.interactable,self.cl.animations )
	self.cl.animator:setCurrentAnimation( Cl_IsMiningHubActivated() and "Rest" or "Offline" )
	self.cl.animator:enableHeadTracking( {
	upDownAnim = "aimbend_updown",
    leftRightAnim = "aimbend_leftright",
    lookAtRange = OpenShutterDistance,
    lookFromOffset = sm.vec3.new(0,0.7,0.25),
    getLookAtPosition = function()
		if self.cl.user and self.cl.cameraNode then
			return self.cl.cameraNode.position
		end
		
		local closestPlayer = GetClosestPlayer( self.shape.worldPosition, OpenShutterDistance, self.shape.body:getWorld() )
		if closestPlayer then
			return closestPlayer.character.worldPosition + sm.vec3.new(0,0,0.5)
		end

		return nil
    end,
    isEnabled = function(animator)
        return animator.currentAnimation ~= "Offline"
    end
	} )
end

function MininghubTrader.client_onDestroy( self )
	if _G.g_rfsMininghubTrader == self then
		_G.g_rfsMininghubTrader = nil
	end
end

-- RFS chat /mshop — open shop GUI without proximity (same GUI path as E interact).
-- Skips mining-hub activation gate and access-card diversion for host testing
-- (always-on RFS cheats, same style as /farmers /give).
function MininghubTrader.cl_rfs_openShop( self, params )
	local player = sm.localPlayer.getPlayer()
	local character = player and player.character
	if not character then
		return false
	end
	if self.cl.user ~= nil and self.cl.user ~= player then
		sm.gui.chatMessage( "[RFS] Mining Hub shop is busy" )
		return false
	end
	if self.cl.user == player and self.cl.gui and sm.exists( self.cl.gui ) and not self.cl.gui:isHidden() then
		sm.gui.chatMessage( "[RFS] Mining Hub shop already open" )
		return true
	end

	if not self.cl.cameraNode then
		local x, y = getCell( self.shape:getWorldPosition().x, self.shape:getWorldPosition().y )
		for dx = -1, 1 do
			for dy = -1, 1 do
				local cameraNodes = sm.cell.getNodesByTag( x + dx, y + dy, "CAMERA" )
				if #cameraNodes > 0 then
					self.cl.cameraNode = cameraNodes[1]
					break
				end
			end
			if self.cl.cameraNode then
				break
			end
		end
	end
	-- Soft-fail camera: GUI can still open if cell camera tags are missing

	if not self.cl.hasInteracted then
		self.cl.hasInteracted = true
		self.network:sendToServer( "sv_n_firstInteract" )
		if self.cl.animator and self.cl.animator.currentAnimation == "Offline" then
			self.cl.animator:setCurrentAnimation( "Wakeup" )
		end
	end

	if self.cl.user == nil then
		character:setLockingInteractable( self.interactable )
		self.cl.user = player
	end

	self.cl.playerInventory = player:getInventory()
	if self.cl.gui == nil then
		self.cl.gui = sm.jsonGui.createGui( { handleKeySetup = "Hideout", name = "Hideout" } )
	else
		self.cl.gui:setHidden( false )
	end

	self.cl_selectTab( self, "All", nil )
	self.cl.updateGui = true
	return true
end

function MininghubTrader.client_onClientDataUpdate( self, clientData, channel )
	if channel == 1 then
		self.cl.vaultTotal = clientData
	elseif channel == 2 then
		self.cl.spentTotal = clientData
	elseif channel == 3 then
		self.cl.milestoneIndex = clientData
	elseif channel == 4 then
		self.cl.hasInteracted = clientData == true
	end
	if self.cl.gui and sm.exists( self.cl.gui ) and self.cl.gui:isActive() then
		self.cl.updateGui = true
	end
end

function MininghubTrader.cl_n_tradeCompleted( self, params )
	if self.cl.gui and sm.exists( self.cl.gui ) and self.cl.gui:isActive() then
		self.cl.updateGui = true
	end
	self.cl.unlockedSchematic = params.unlockedSchematic
	self.cl.unlockedLog = params.unlockedLog
	self.cl.unlockedCosmetic = params.unlockedCosmetic
	
	if self.cl.unlockedSchematic or self.cl.unlockedLog or self.cl.unlockedCosmetic then
		self.cl.selectedItem = nil -- shortcut to handle the item dissapearing from the list
	end
	self.cl.animator:setCurrentAnimationVariation( { Confirm01 = 0.7, Confirm02 = 0.3 } )
end

function MininghubTrader.client_onInteract( self, character, state )
	local mininghubActivated = Cl_IsMiningHubActivated()
	
	if state == true and mininghubActivated then
		-- (unlock the log + play the trade animation) instead of opening the shop GUI.
		local cardLog = nil
		for _, questName in ipairs( CardQuests ) do
			local quest = QuestManager.Cl_GetActiveQuest( questName )
			local questPublicData = quest and sm.exists( quest ) and quest.clientPublicData
			if questPublicData and questPublicData.traderResponse == "give_access_card" then
				cardLog = questPublicData.traderCardLog or tostring( LOGS.log_accesscard_01 )
				break
			end
		end
		if cardLog then
			if not self.cl.hasInteracted then
				self.cl.hasInteracted = true
				self.network:sendToServer( "sv_n_firstInteract" )
			end
			if self.cl.animator.currentAnimation == "Offline" then
				self.cl.animator:setCurrentAnimation( "Wakeup" )
			end
			self.network:sendToServer( "sv_n_questGiveCard", { card = cardLog } )
			return
		end

		if not self.cl.hasInteracted then
			self.cl.hasInteracted = true
			self.network:sendToServer( "sv_n_firstInteract" )
			if self.cl.animator.currentAnimation == "Offline" then
				self.cl.animator:setCurrentAnimation( "Wakeup" )
			end
		end
		
		local x, y = getCell( self.shape:getWorldPosition().x, self.shape:getWorldPosition().y )
		for dx = -1, 1 do
			for dy = -1, 1 do
				local cameraNodes = sm.cell.getNodesByTag( x + dx, y + dy, "CAMERA" )
				if #cameraNodes > 0 then
					self.cl.cameraNode = cameraNodes[1]
					break
				end
			end
			if self.cl.cameraNode then 
				break 
			end
		end
		assert( self.cl.cameraNode, "Failed to find camera node")
		if self.cl.user == nil then
			character:setLockingInteractable( self.interactable )
			self.cl.user = character:getPlayer()
		end
		if QuestManager.Cl_IsQuestActive( "quest_activate_mininghub" ) then
			self.network:sendToServer( "sv_n_questInteract" )
		end
		self.cl.playerInventory = character:getPlayer():getInventory()
		if self.cl.gui == nil then
			self.cl.gui = sm.jsonGui.createGui( { handleKeySetup = "Hideout", name = "Hideout" } )
		else
			self.cl.gui:setHidden( false )
		end

		self.cl_selectTab( self, "All", nil )
		self.cl.updateGui = true
	end

end

function MininghubTrader.client_canInteract( self )
	return true
end

function MininghubTrader.sv_n_trade( self, selectedItem, player )
	local tradeData = TradeData[selectedItem.tradeDataIndex]
	local isLogItem = tradeData.logItem or false
	
	local ingredients = tradeData.ingredientList
	local itemId = tradeData.itemId
	local qty = tradeData.quantity
	local schematic = tradeData.schematic
	local cosmetic = tradeData.cosmetic
	local extras = tradeData.extras

	local vaultTotal = ProgressionManager.Sv_GetVaultTotal()
	local spentTotal = TileStorageManager.Sv_GetValue( self.sv.tileStorageKey, "traderSpentTotal" ) or 0
	local balance = vaultTotal - spentTotal

	local ingredient = ingredients[1]
	local cost = 0
	if ingredient then
		local ingredientUuid = sm.uuid.new( ingredient.itemId )
		assert( ingredientUuid == ITEMS.obj_resource_wonkstonks )
		cost = ingredient.quantity
		if balance < cost then
			NotificationManager.Sv_Generic( "#{INFO_INSUFFICIENT_FUNDS}", 4, nil, player )
			return
		end
	end
	
	sm.container.beginTransaction()

	if not schematic and not isLogItem and not cosmetic then
		local inventory = player:getInventory()
		sm.container.collect( inventory, sm.uuid.new( itemId ), qty, true )
	end

	if not sm.container.endTransaction() then
		return --The player failed the trade transaction, abort
	end

	if schematic then
		RecipeManager.Sv_UnlockRecipe( tostring( itemId ) )
		if extras then
			for _, value in ipairs( extras ) do
				RecipeManager.Sv_UnlockRecipe( tostring( value.itemId ) )
			end
		end
	end

	if isLogItem then
		local log = LogEntryManager.Cl_GetLogFromItemUuid( itemId )
		if log then
			LogEntryManager.Sv_AddLog( log )
		end
	end

	if cosmetic then
		sm.event.sendToGame( "sv_e_grantAdditionalRewardsForPlayer", { rewardList = { { uuid = itemId, type = "additionalReward" } }, player = player } )
	end

	TileStorageManager.Sv_SetValue( self.sv.tileStorageKey, "traderSpentTotal", spentTotal + cost )

	self.network:sendToClients( "cl_n_tradeCompleted", { unlockedSchematic = schematic and itemId or nil, unlockedLog = isLogItem and itemId or nil, unlockedCosmetic = cosmetic and itemId or nil } )
end

function MininghubTrader.cl_onTradeClick( self, widgetName, data )
	if self.cl.selectedItem ~= nil then
		if self.cl.gui and sm.exists( self.cl.gui ) then
			local tradeButtonEffectBox = self.cl.gui:getWidget( "TradeButtonEffectBox" )
			if tradeButtonEffectBox then
				tradeButtonEffectBox:startEffect( "tradebutton" )
			end
			sm.effect.playEffect( "audio:event:/ui/trading/trade" )
		end
		self.network:sendToServer( "sv_n_trade", self.cl.selectedItem )
	end
end

function MininghubTrader.cl_selectTrade( self, widgetName, data )
	if self.cl.selectedItem == nil then
		self.cl.selectedItem = {}
	end

	local itemChanged = self.cl.selectedItem.shopIndex ~= data.shopIndex or 
						self.cl.selectedItem.tradeDataIndex ~= data.tradeDataIndex
	
	if itemChanged then
		self.cl.selectedItem = { 
			shopIndex = data.shopIndex,
			tradeDataIndex = data.tradeDataIndex
		}
		self.cl.updateGui = true
		self.cl.draw = true
	end
end

function MininghubTrader.cl_onClose( self )
	if QuestManager.Cl_IsQuestActive( "quest_activate_mininghub" ) then
		self.network:sendToServer( "sv_n_questClose" )
	end
	if self.cl.gui and sm.exists(self.cl.gui) then
		self.cl.gui:close()
		self.cl.gui = nil
	end
	if self.cl.user then
		self.cl.user.clientPublicData.interactableCameraData = nil
		self.cl.user.character:setLockingInteractable( nil )
		self.cl.user = nil
	end
end

function MininghubTrader.client_onUpdate( self, dt )
	self:cl_updateGui()
	if self.cl.draw and self.cl.gui and not self.cl.gui:isHidden() then
		self.cl.gui:render( TraderGui.json )
	end
	self.cl.draw = false	
	if self.cl.user == sm.localPlayer.getPlayer() then
		 UpdateVendorCamera(self, dt)
	end

	self:cl_handleWakeup()
	self:cl_handleOpenClose()
	self.cl.animator:update( dt )
end

function MininghubTrader.cl_selectTab(self, widgetName, data )
	
	for _, tab in pairs(TraderGui.Tabs) do
		tab.StateSelected = false
		local tabText = FindWidget(tab,"TabText")
		tabText.TextColour = "1 1 1 0.5"
	end

	
	self.cl.activeTab = widgetName
	local tab = TraderGui.Tabs[self.cl.activeTab]
	if tab then 
		tab.StateSelected = true
		local tabText = FindWidget(tab,"TabText")
		tabText.TextColour = "0 0 0 1"
		self.cl.selectedItem = {}
		self.cl.updateGui = true
	end
	
end

function MininghubTrader.cl_handleWakeup(self)
	local currentAnimation = self.cl.animator.currentAnimation
	local mininghubActivated = Cl_IsMiningHubActivated()
	if not mininghubActivated and currentAnimation ~= "Offline" then
		self.cl.animator:setCurrentAnimation( "Offline" )
		return
	end
	if mininghubActivated and not self.cl.hasInteracted then
		if currentAnimation ~= "Offline" then
			self.cl.animator:setCurrentAnimation( "Offline" )
		end
		return
	end
	if mininghubActivated and currentAnimation == "Offline" then
		if GetClosestPlayer( self.shape.worldPosition, OpenShutterDistance, self.shape.body:getWorld() ) ~= nil then
			self.cl.animator:setCurrentAnimation( "Wakeup" )
		end
	end
end

function MininghubTrader.cl_handleOpenClose( self )
	local currentAnimation = self.cl.animator.currentAnimation
	if currentAnimation == "Rest" then
		self.cl.animator.headTracking.lookAtRange = OpenShutterDistance
		if GetClosestPlayer( self.shape.worldPosition, OpenShutterDistance, self.shape.body:getWorld() ) ~= nil then
			self.cl.animator:setCurrentAnimation( "Open" )

		end
	elseif currentAnimation == "Idle" then
		self.cl.animator.headTracking.lookAtRange = CloseShutterDistance * 3
		if GetClosestPlayer( self.shape.worldPosition, CloseShutterDistance, self.shape.body:getWorld() ) == nil then
			self.cl.animator:setCurrentAnimation( "Close" )
		end	
	end

end


-- Dialog speaker callbacks
function MininghubTrader.cl_e_onDialogLine( self, params )
	self.cl.isTalking = true
	self.cl.animator:setCurrentAnimation( "Talk" )
end

function MininghubTrader.cl_e_onDialogEnd( self )
	self.cl.isTalking = false
	local currentAnim = self.cl.animator.currentAnimation

	if currentAnim == "Talk" then
		self.cl.animator:setCurrentAnimation( "Idle" )
	end
end

function MininghubTrader.cl_e_onDialogAbort( self )
	self.cl.isTalking = false
	local currentAnim = self.cl.animator.currentAnimation
	if currentAnim == "Talk" then
		self.cl.animator:setCurrentAnimation( "Idle" )
	end
end