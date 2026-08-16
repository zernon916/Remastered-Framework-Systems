-- Recipe Framework Survival owned copy (vanilla HideoutTrader + original merge hook)
-- HideoutTrader.lua --
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile("$SURVIVAL_DATA/Scripts/game/characters/shared_animation.lua" )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsBotHijack.lua" )
end )


dofile( "$GAME_DATA/Scripts/game/managers/TileStorageManager.lua" )

-- Vanilla Survival trades only. Extra RFS/mod rows merge in memory from hideout_trades.json.
-- Do not load or write $CONTENT_DATA/CraftingRecipes/hideout.json (checksum / Survival dirtying).
local function rfsLoadHideoutTradeData()
	local path = "$SURVIVAL_DATA/CraftingRecipes/hideout.json"
	local ok, data = pcall( sm.json.open, path )
	if ok and type( data ) == "table" then
		return data
	end
	ok, data = pcall( dofile, path )
	if ok and type( data ) == "table" then
		return data
	end
	print( "[RFS HideoutTrader] Survival hideout.json missing — starting with empty TradeData" )
	return {}
end

local TradeData = rfsLoadHideoutTradeData()

-- RFS: hideout shop pays with Farmers (caged farmer / farmerball), except seed
-- SKUs: spend 1 matching produce crate, get 80 seeds. Vanilla hideout.json uses
-- produce CRATES for many costs; those icons look like loose veggies in the UI.
local FARMERS_ITEM_ID = "8d601982-4608-4d5e-bb9e-e4041486f7c7"
-- Beacon titles/icons only if the B&P shape exists on THIS peer. Missing mods are stripped
-- from the shop (no vanilla-icon ghost / "BLOCK NOT FOUND" rows).
local RFS_BEACON_UI = {
	["b4e8c1a0-7d2f-4a91-9c3e-29f1a8d6b5e7"] = {
		title = "Hack Beacon",
		desc = "16 m computer. Wire a Battery container. Keep powered or tethered robots revert.",
		icon = "9f0f56e8-2c31-4d83-996c-d00a9b296c3f",
	},
	["c5f9d2b1-8e30-4ba2-ad4f-30a2b9e7c6f8"] = {
		title = "Control Beacon",
		desc = "32 m computer. Wire a Battery container. Keep powered or tethered robots revert.",
		icon = "8f7fd0e7-c46e-4944-a414-7ce2437bb30f",
	},
	["d6a0e3c2-9f41-4cb3-be50-41b3c0f8d709"] = {
		title = "Infection Beacon",
		desc = "48 m computer. E infects permanently. Tethered bots in the field ~8 s also submit.",
		icon = "1d4793af-cb66-4628-804a-9d7404712643",
	},
	["f8c2a5e4-1b63-4ed5-9072-63d5e2f0f92b"] = {
		title = "Ally Factory",
		desc = "200 Farmers. E spends Metal+Battery to spawn a player ally. U cycles tote/hay/tape/farm. Army cap 16.",
		icon = "9f0f56e8-2c31-4d83-996c-d00a9b296c3f",
	},
}
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
local function rfsLookupItemIcon( itemId )
	local ok, resource, group, name = pcall( function()
		return sm.gui.getItemIconFromUuid( sm.uuid.new( tostring( itemId ) ) )
	end )
	if ok and type( name ) == "string" and name ~= "" and name ~= "Empty" and type( resource ) == "string" and resource ~= "" then
		return true, resource, group, name
	end
	return false
end
local function rfsIconForTrade( itemId )
	local id = tostring( itemId )
	if not rfsItemPresentOnPeer( id ) then
		return false
	end
	local ok, resource, group, name = rfsLookupItemIcon( id )
	if ok then
		return true, resource, group, name
	end
	-- Shape exists; icon atlas may still be missing. Beacon-only vanilla icon, never a ghost row.
	local meta = RFS_BEACON_UI[id]
	if meta then
		return rfsLookupItemIcon( meta.icon )
	end
	return false
end
local function rfsTradeTitleDesc( itemId, uuid )
	local meta = RFS_BEACON_UI[tostring( itemId )]
	if meta then
		return meta.title, meta.desc
	end
	local title, desc = "", ""
	pcall( function()
		title = sm.shape.getShapeTitle( uuid ) or ""
	end )
	pcall( function()
		desc = sm.shape.getShapeDescription( uuid ) or ""
	end )
	return title, desc
end
local function rfsPreviewItemId( itemId )
	local meta = RFS_BEACON_UI[tostring( itemId )]
	if meta then
		local okTitle, title = pcall( sm.shape.getShapeTitle, sm.uuid.new( tostring( itemId ) ) )
		if okTitle and type( title ) == "string" and title ~= "" and not string.find( string.lower( title ), "not found", 1, true ) then
			return tostring( itemId )
		end
		return meta.icon
	end
	return tostring( itemId )
end
-- Produce CRATE UUIDs from Survival survival_items.lua (not loose produce).
-- Packing-station crates only: banana, blueberry, orange, pineapple, carrot,
-- redbeet, tomato, broccoli. No inventory crate for potato / cotton / chili / paint.
local CRATE_BANANA = "0bc74539-df8a-47c7-aad8-d55d809a01e4"
local CRATE_BLUEBERRY = "e77d9577-589a-446b-96c1-f6d0d7495489"
local CRATE_ORANGE = "c10a77d5-3357-4cb4-8113-a2cbe69c7ff2"
local CRATE_PINEAPPLE = "bc69cb3b-7e0c-4c36-805d-f8d89fcfced3"
local CRATE_CARROT = "9cd8288c-5a19-479f-af47-9eb55230ade2"
local CRATE_REDBEET = "628fd350-577d-413f-82a8-7f08a83de3d8"
local CRATE_TOMATO = "1dcd74ca-39ba-4b00-a36a-3381b25055f4"
local CRATE_BROCCOLI = "99477093-e819-4199-b62a-fda6143aae89"
local PRODUCE_CRATE_IDS = {
	[CRATE_BANANA] = true,
	[CRATE_BLUEBERRY] = true,
	[CRATE_ORANGE] = true,
	[CRATE_PINEAPPLE] = true,
	[CRATE_CARROT] = true,
	[CRATE_REDBEET] = true,
	[CRATE_TOMATO] = true,
	[CRATE_BROCCOLI] = true,
}
-- Hideout seed listings: spend 1 crate, get 80 seeds. Matching crate when it exists.
-- Potato / cotton / paint / chili have no crate SKU — closest vacuum crate (not Farmers).
local SEED_TRADE_QTY = 80
local SEED_CRATE_COST = {
	["38e41fb5-dd50-4294-829d-a517f0282fed"] = CRATE_TOMATO, -- tomato
	["9c82a525-8a8b-4483-9595-505aaa042486"] = CRATE_CARROT, -- carrot
	["64051718-a3f1-422b-bda3-277efa0c4545"] = CRATE_REDBEET, -- redbeet
	["22beade5-38ca-47b4-a2ee-32403f58a862"] = CRATE_BANANA, -- banana
	["4b6d2bee-d0f1-4e56-96f0-d2596388cad2"] = CRATE_BLUEBERRY, -- blueberry
	["bee966b0-b5e5-41da-b992-5d363ab85ae4"] = CRATE_ORANGE, -- orange
	["1c6756ca-3a60-4dcb-a5d1-353edf818308"] = CRATE_BROCCOLI, -- broccoli
	["9edb6f7c-fb44-4348-a1c4-8afb41b92d8a"] = CRATE_PINEAPPLE, -- pineapple
	["eb1ef696-5c05-4662-9e47-fe1e0875ff84"] = CRATE_CARROT, -- potato: no crate → carrot crate
	["93c27ab2-4930-4654-ba1c-bcfe35e966f6"] = CRATE_BANANA, -- cotton: no crate → banana crate
	["c44b27da-88cf-4e17-b872-6236a1172688"] = CRATE_BLUEBERRY, -- paint: no crate → blueberry crate
	["8883e0ee-8a6e-423a-a4e0-583d9bf105bd"] = CRATE_TOMATO, -- chili: no crate → tomato crate
}
local RFS_EXTRA_UNLOCK_SEEDS = {
	"eb1ef696-5c05-4662-9e47-fe1e0875ff84", -- potato (not in Survival hideout.json)
	"93c27ab2-4930-4654-ba1c-bcfe35e966f6", -- cotton
	"c44b27da-88cf-4e17-b872-6236a1172688", -- pigmentflower
}
local function rfsApplySeedCrateTrades( trades )
	if type( trades ) ~= "table" then
		return
	end
	local seen = {}
	for _, trade in ipairs( trades ) do
		if type( trade ) == "table" and trade.itemId then
			local id = tostring( trade.itemId )
			local crate = SEED_CRATE_COST[id]
			if crate then
				trade.quantity = SEED_TRADE_QTY
				trade.craftTime = trade.craftTime or 0
				trade.schematic = false
				trade.ingredientList = { { itemId = crate, quantity = 1 } }
				seen[id] = true
			end
		end
	end
	for id, crate in pairs( SEED_CRATE_COST ) do
		if not seen[id] then
			trades[#trades + 1] = {
				itemId = id,
				quantity = SEED_TRADE_QTY,
				craftTime = 0,
				schematic = false,
				ingredientList = { { itemId = crate, quantity = 1 } },
			}
			-- Unlock runs after DefaultUnlockedTradesSet is built (RFS_EXTRA_UNLOCK_SEEDS).
		end
	end
end
local function rfsConvertTradeCostsToFarmers( trades )
	if type( trades ) ~= "table" then
		return
	end
	rfsApplySeedCrateTrades( trades )
	local converted = 0
	for _, trade in ipairs( trades ) do
		if type( trade ) == "table" and type( trade.ingredientList ) == "table" then
			local seedId = trade.itemId and tostring( trade.itemId ) or ""
			if not SEED_CRATE_COST[seedId] then
				local farmersQty = 0
				local hadOther = false
				for _, ing in ipairs( trade.ingredientList ) do
					if ing and ing.itemId then
						local id = tostring( ing.itemId )
						local qty = tonumber( ing.quantity ) or 1
						if id == FARMERS_ITEM_ID then
							farmersQty = farmersQty + qty
						elseif PRODUCE_CRATE_IDS[id] then
							farmersQty = farmersQty + qty
							hadOther = true
						else
							-- Non-crate / non-farmer cost → fold into Farmers 1:1 (RFS policy)
							farmersQty = farmersQty + qty
							hadOther = true
						end
					end
				end
				if hadOther or #trade.ingredientList == 0 then
					if farmersQty < 1 then
						farmersQty = 1
					end
					trade.ingredientList = { { itemId = FARMERS_ITEM_ID, quantity = farmersQty } }
					converted = converted + 1
				elseif #trade.ingredientList > 1 then
					-- Multiple farmer lines → collapse
					trade.ingredientList = { { itemId = FARMERS_ITEM_ID, quantity = math.max( 1, farmersQty ) } }
					converted = converted + 1
				end
			end
		end
	end
	if converted > 0 then
		print( "[RFS HideoutTrader] Converted " .. tostring( converted ) .. " trades to Farmers-only costs" )
	end
end

rfsConvertTradeCostsToFarmers( TradeData )

local TutorialActivationDropOffDistance = 40.0
local TutorialActivationTraderDistance = 15.0

local DefaultUnlockedTrades = {
	ITEMS.obj_consumable_sunshake,
	ITEMS.obj_consumable_soilbag,
	ITEMS.obj_seed_tomato
}
local DefaultListToSet = function( list )
	local result = {}
	for _, itemUuid in ipairs( list ) do
		result[tostring( itemUuid )] = true
	end
	return result
end

local function RemoveUnusedItemSlotProperties( Widget )
	Widget.onMouseWheel = nil
	for _, value in ipairs( Widget.Childs ) do
		value.onMouseWheel = nil
	end
end

local DefaultUnlockedTradesSet = DefaultListToSet( DefaultUnlockedTrades )
for _, id in ipairs( RFS_EXTRA_UNLOCK_SEEDS ) do
	DefaultUnlockedTradesSet[id] = true
end

local DefaultUnlockedSchematicTrades = {
	ITEMS.obj_interactive_logicgate,
	ITEMS.obj_interactive_timer,
	ITEMS.obj_interactive_sensor_01,
	ITEMS.obj_interactive_ladder,
	ITEMS.obj_interactive_driversaddle_01,
	ITEMS.obj_interactive_saddle_01,
	ITEMS.jnt_suspensionsport_bearing_01,
	ITEMS.jnt_suspensionoffroad_bearing_01,
	ITEMS.blk_lights,
	ITEMS.blk_armoredglass,
	ITEMS.blk_carpet,
	ITEMS.obj_structure_concretefoundation01,
	ITEMS.obj_structure_concretefoundation02,
	ITEMS.obj_structure_concretepillar,
	ITEMS.obj_structure_concretebarrier02,
	ITEMS.obj_structure_concretebarrier
}
local DefaultUnlockedSchematicTradesSet = DefaultListToSet( DefaultUnlockedSchematicTrades )

local DefaultUnlockedCosmeticTrades = {
	CUSTOMIZATIONS.outfit_hat_farmer_hat,
	CUSTOMIZATIONS.outfit_torso_farmer_jacket,
	CUSTOMIZATIONS.outfit_gloves_farmer_gloves,
	CUSTOMIZATIONS.outfit_legs_farmer_pants,
	CUSTOMIZATIONS.outfit_shoes_farmer_shoes,
	CUSTOMIZATIONS.outfit_backpack_farmer_backpack
}
local DefaultUnlockedCosmeticTradesSet = DefaultListToSet( DefaultUnlockedCosmeticTrades )

-- Vanilla hideout.json has ZERO cosmetic shop rows (outfits unlock via deposit rewards).
-- Inject Survival's default farmer set + tradegroup unlockCosmetic (Woc) set as Farmers trades
-- so the hideout shop actually lists cosmetics.
local RFS_EXTRA_COSMETIC_TRADE_IDS = {
	"7a616a77-2c3f-4910-a6d9-adbea26a0408", -- outfit_hat_woc_hat
	"26ea8bfc-3e79-4eb2-9ee0-ad1c59373c7b", -- outfit_torso_woc_jacket
	"cc8af283-9b55-4c41-87fd-615992d5a117", -- outfit_gloves_woc_gloves
	"2971e6a7-dd15-453e-a433-3adc41993f5c", -- outfit_legs_woc_pants
	"818a4485-68f2-4a97-91b1-845ec70c6985", -- outfit_shoes_woc_shoes
	"71eccd0e-2d37-479f-8e9f-1005440b9f6f", -- outfit_backpack_woc_backpack
}

local function rfsEnsureCosmeticTradeRows()
	local seen = {}
	for _, t in ipairs( TradeData ) do
		if t and t.itemId then
			seen[tostring( t.itemId )] = true
			-- Repair missing cosmetic flag if this UUID is a known outfit trade
			if t.cosmetic == nil and DefaultUnlockedCosmeticTradesSet[tostring( t.itemId )] then
				t.cosmetic = true
				t.schematic = false
			end
		end
	end
	local added = 0
	local function addCosmetic( uuidOrId, cost, defaultUnlock )
		local id = tostring( uuidOrId )
		if seen[id] then
			if defaultUnlock then
				DefaultUnlockedCosmeticTradesSet[id] = true
			end
			return
		end
		TradeData[#TradeData + 1] = {
			itemId = id,
			quantity = 1,
			craftTime = 0,
			cosmetic = true,
			schematic = false,
			ingredientList = { { itemId = FARMERS_ITEM_ID, quantity = cost or 1 } },
		}
		seen[id] = true
		added = added + 1
		if defaultUnlock then
			DefaultUnlockedCosmeticTradesSet[id] = true
		end
	end
	for _, u in ipairs( DefaultUnlockedCosmeticTrades ) do
		addCosmetic( u, 1, true )
	end
	for _, id in ipairs( RFS_EXTRA_COSMETIC_TRADE_IDS ) do
		-- Visible in shop (Farmers); mirrors Survival deposit unlock cosmetics
		addCosmetic( id, 2, true )
	end
	if added > 0 then
		print( "[RFS HideoutTrader] Injected " .. tostring( added ) .. " cosmetic hideout trades (Farmers)" )
	end
end

rfsEnsureCosmeticTradeRows()

-- Recipe Framework Survival: merge mod trades published on _G.g_extraHideoutTrades.
-- Must be defined AFTER DefaultUnlocked*Set locals (Lua upvalue scope — early defs hit nil globals).
-- Original Custom Game hook. Currency expected = Farmers (farmerball).
local function ensureExtraTrades()
	-- Local sets are upvalues (declared above). Never index as globals.
	local unlocked = DefaultUnlockedTradesSet
	local unlockedSchematic = DefaultUnlockedSchematicTradesSet
	local unlockedCosmetic = DefaultUnlockedCosmeticTradesSet
	if type( unlocked ) ~= "table" or type( unlockedSchematic ) ~= "table" or type( unlockedCosmetic ) ~= "table" then
		print( "[RFS HideoutTrader] ensureExtraTrades aborted — unlock sets missing (stale Cache/Raw? delete mod Cache\\Raw and reload)" )
		return
	end
	rfsEnsureCosmeticTradeRows()
	-- Always pull RFS hideout_trades.json on client+server (Game.lua scan is server-only).
	do
		_G.g_extraHideoutTrades = _G.g_extraHideoutTrades or {}
		local seenFile = {}
		for _, t in ipairs( _G.g_extraHideoutTrades ) do
			if t and t.itemId then
				seenFile[tostring( t.itemId )] = true
			end
		end
		local okCfg, hideCfg = pcall( sm.json.open, "$CONTENT_DATA/CraftingRecipes/hideout_trades.json" )
		if okCfg and type( hideCfg ) == "table" then
			local list = hideCfg.trades or hideCfg
			if type( list ) == "table" then
				for _, raw in ipairs( list ) do
					if type( raw ) == "table" and raw.itemId then
						local id = tostring( raw.itemId )
						if not seenFile[id] then
							_G.g_extraHideoutTrades[#_G.g_extraHideoutTrades + 1] = raw
							seenFile[id] = true
							_G.g_hideoutExtraTradesDirty = true
							_G.g_hideoutExtraTradesMerged = false
						end
					end
				end
			end
		end
	end
	-- Always strip missing-mod / missing-beacon rows on this peer (host and client).
	local extraIds = {}
	for id, _ in pairs( RFS_BEACON_UI ) do
		extraIds[id] = true
	end
	if type( _G.g_extraHideoutTrades ) == "table" then
		local keptExtras = {}
		local strippedExtras = 0
		for _, t in ipairs( _G.g_extraHideoutTrades ) do
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
		_G.g_extraHideoutTrades = keptExtras
		if strippedExtras > 0 then
			print( "[RFS HideoutTrader] stripped " .. tostring( strippedExtras ) .. " missing-mod extra trades" )
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
			print( "[RFS HideoutTrader] stripped " .. tostring( stripped ) .. " missing-mod shop rows" )
		end
	end
	if _G.g_hideoutExtraTradesMerged and not _G.g_hideoutExtraTradesDirty then
		return
	end
	local extras = _G.g_extraHideoutTrades
	if type( extras ) ~= "table" then
		extras = {}
	end
	local seen = {}
	for _, t in ipairs( TradeData ) do
		if t and t.itemId then
			seen[tostring( t.itemId )] = true
		end
	end
	local added = 0
	for _, t in ipairs( extras ) do
		if type( t ) == "table" and t.itemId then
			local id = tostring( t.itemId )
			local isCosmetic = t.cosmetic and true or false
			local isSchematic = ( t.schematic ~= false ) and ( not isCosmetic )
			if ( not isCosmetic ) and ( not rfsItemPresentOnPeer( id ) ) then
				-- Ghost: mod/shape not on this peer (e.g. RFS Beacons disabled).
			else
				if not seen[id] then
					local qty = 0
					for _, ing in ipairs( t.ingredientList or {} ) do
						qty = qty + ( tonumber( ing.quantity ) or 1 )
					end
					if qty < 1 then qty = 1 end
					local entry = {
						itemId = id,
						quantity = t.quantity or 1,
						craftTime = t.craftTime or 0,
						ingredientList = { { itemId = FARMERS_ITEM_ID, quantity = qty } },
						schematic = t.schematic,
						cosmetic = t.cosmetic,
						extras = t.extras,
						_rfs = true,
					}
					if isCosmetic then
						entry.cosmetic = true
						entry.schematic = false
					elseif entry.schematic == nil then
						entry.schematic = true
					end
					TradeData[#TradeData + 1] = entry
					seen[id] = true
					added = added + 1
				end
				if isCosmetic then
					unlockedCosmetic[id] = true
				elseif isSchematic then
					unlockedSchematic[id] = true
				else
					unlocked[id] = true
				end
			end
		end
	end
	if type( _G.g_extraHideoutSchematicUnlocks ) == "table" then
		for id, _ in pairs( _G.g_extraHideoutSchematicUnlocks ) do
			unlockedSchematic[tostring( id )] = true
		end
	end
	rfsConvertTradeCostsToFarmers( TradeData )
	rfsEnsureCosmeticTradeRows()
	_G.g_hideoutExtraTradesMerged = true
	_G.g_hideoutExtraTradesDirty = false
	if added > 0 then
		print( "[RFS HideoutTrader] Merged " .. tostring( added ) .. " mod trades" )
	end
end


local IngredientItem = dofile( "$SURVIVAL_DATA/Gui/JsonGuis/Hideout_IngredientItem.gui" )
local IngredientItemIcon = FindWidget( IngredientItem, "ItemIcon" )
local IngredientItemQuantity = FindWidget( IngredientItem, "Quantity" )
local IngredientItemTextColor = "#909090"
if IngredientItemQuantity and IngredientItemQuantity.TextColour then
	IngredientItemTextColor = '#'..string.sub( ColorFromGuiColor( IngredientItemQuantity.TextColour ):getHexStr(), 1, 6 )
end


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

local TraderUnlockGroups = dofile( "$SURVIVAL_DATA/ScriptJsonFiles/Trader/trader.tradegroup" )
local TraderQuestGroups = TraderUnlockGroups.questGroups
local TraderCyclicGroups = TraderUnlockGroups.cyclicGroups
local TraderTierUnlockGroups = TraderUnlockGroups.tierUnlockGroups

local TraderGui = {}
TraderGui.json = DeepCopy( dofile( "$SURVIVAL_DATA/Gui/JsonGuis/Hideout.gui" ) )

TraderGui.UnlockPanel = FindWidget( TraderGui.json, "UnlockPanel" )
TraderGui.MainPanel = FindWidget( TraderGui.json, "MainPanel" )
TraderGui.TradePanel = FindWidget( TraderGui.json, "TradePanel" )

TraderGui.CountPanel = FindWidget( TraderGui.MainPanel, "CountPanel" )
TraderGui.BananaCount = FindWidget( TraderGui.CountPanel, "BananaResourceCounter" )
TraderGui.BerryCount = FindWidget( TraderGui.CountPanel, "BlueberryResourceCounter" )
TraderGui.BroccoliCount = FindWidget( TraderGui.CountPanel, "BroccoliResourceCounter" )
TraderGui.OrangeCount = FindWidget( TraderGui.CountPanel, "OrangeResourceCounter" )
TraderGui.PineappleCount = FindWidget( TraderGui.CountPanel, "PineappleResourceCounter" )
TraderGui.BeetCount = FindWidget( TraderGui.CountPanel, "RedbeetResourceCounter" )
TraderGui.TomatoCount = FindWidget( TraderGui.CountPanel, "TomatoResourceCounter" )
TraderGui.CarrotCount = FindWidget( TraderGui.CountPanel, "CarrotResourceCounter" )
TraderGui.FarmerCount = FindWidget( TraderGui.MainPanel, "FarmerResourceCounter" )


TraderGui.Preview = FindWidget( TraderGui.TradePanel, "Preview" )
TraderGui.Title = FindWidget( TraderGui.TradePanel, "Title" )
TraderGui.DescriptionBox = FindWidget( TraderGui.TradePanel, "DescriptionBox" )
TraderGui.DescriptionHeader = FindWidget( TraderGui.TradePanel, "DescriptionHeader" )
TraderGui.DescriptionLine = FindWidget( TraderGui.TradePanel, "DescriptionLine" )
TraderGui.IngredientItems = FindWidget( TraderGui.TradePanel, "IngredientItems" )

TraderGui.TradeIcon = FindWidget( TraderGui.TradePanel, "TradeIcon" )
TraderGui.TradeCount = FindWidget( TraderGui.TradePanel, "TradeCount" )
TraderGui.TradeCountBG = FindWidget( TraderGui.TradePanel, "TradeCountBG" )
TraderGui.TradeCountSchematic = FindWidget( TraderGui.TradePanel, "TradeCountSchematic" )
TraderGui.TradeCountCosmetic = FindWidget( TraderGui.TradePanel, "TradeCountCosmetic" )
TraderGui.TradeButton = FindWidget( TraderGui.TradePanel, "TradeButton" )

TraderGui.FinalRewardImage = FindWidget( TraderGui.UnlockPanel, "FinalRewardImage" )
TraderGui.FinalRewardBG = FindWidget( TraderGui.UnlockPanel, "FinalRewardBG" )
TraderGui.FinalRewardEffectBox = FindWidget( TraderGui.UnlockPanel, "FinalRewardImageEffectBox" )

TraderGui.ResourceIcon = FindWidget( TraderGui.UnlockPanel, "ResourceIcon" )

TraderGui.BarBackground = FindWidget( TraderGui.UnlockPanel, "BarBackground" )
TraderGui.Bar = FindWidget( TraderGui.UnlockPanel, "Bar" )
TraderGui.Markers = FindWidget( TraderGui.UnlockPanel, "Markers" )

TraderGui.Marker = FindWidget( TraderGui.UnlockPanel, "Marker" )
TraderGui.RewardIconBG = FindWidget( TraderGui.UnlockPanel, "RewardIconBG" )
TraderGui.RewardIcon = FindWidget( TraderGui.UnlockPanel, "RewardIcon" )

TraderGui.ProgressButton = FindWidget( TraderGui.UnlockPanel, "ProgressButton" )
TraderGui.ProgressButtonEffectBox = FindWidget( TraderGui.ProgressButton, "ProgressButtonEffectBox" )

TraderGui.Markers.Childs = {}

TraderGui.scrollView = FindWidget( TraderGui.MainPanel, "ItemContentPanel" )

HideoutTrader = class( nil )
HideoutTrader.maxParentCount = 1
HideoutTrader.maxChildCount = 0
HideoutTrader.connectionInput = sm.interactable.connectionType.logic
HideoutTrader.connectionOutput = sm.interactable.connectionType.none
HideoutTrader.colorNormal = sm.color.new( 0xdeadbeef )
HideoutTrader.colorHighlight = sm.color.new( 0xdeadbeef )
HideoutTrader.VacuumTickTime = math.floor( 40 * 0.76 )

HideoutTrader.TradeCountColor1 = "#9D8641"
HideoutTrader.TradeCountColor2 = "#FFD44A"
HideoutTrader.ResourceCountGrey = "#595959"
HideoutTrader.GridItemSize = 74

HideoutTrader.SufficientIngredientColor = "#cff42b"
HideoutTrader.InsufficientIngredientColor = "#f42b2b"

TraderGui.DepositEventDuration = 2.4
TraderGui.BarAnimationDuration = 0.6

TraderGui.GroupChangeFadeDuration = 0.5
TraderGui.GroupChangeHideFinalRewardDelay = 1.5
TraderGui.GroupChangeResetBarDuration = 0.5

TraderGui.GroupChangeEffectDelay = 3.5
TraderGui.GroupChangeNewRewardDelay = TraderGui.GroupChangeEffectDelay + 1
TraderGui.GroupChangeDuration = TraderGui.GroupChangeNewRewardDelay + 1


local OpenShutterDistance = 7.0
local CloseShutterDistance = 9.0

local HideoutVacuumItems = {
	obj_crates_blueberry,
	obj_crates_banana,
	obj_crates_pineapple,
	obj_crates_orange,
	obj_crates_redbeet,
	obj_crates_carrot,
	obj_crates_tomato,
	obj_crates_broccoli,
	obj_survivalobject_farmerball
}

function HideoutTrader.resourceToImage( self, uuid )
	if uuid == obj_crates_banana then
		return "gui_hideout_vegtable_banana.png"

	elseif uuid == obj_crates_blueberry then
		return "gui_hideout_vegtable_blueberry.png"

	elseif uuid == obj_crates_orange then
		return "gui_hideout_vegtable_orange.png"

	elseif uuid == obj_crates_pineapple then
		return "gui_hideout_vegtable_pinapple.png"

	elseif uuid == obj_crates_carrot then
		return "gui_hideout_vegtable_carrot.png"

	elseif uuid == obj_crates_redbeet then
		return "gui_hideout_vegtable_redbeet.png"

	elseif uuid == obj_crates_tomato then
		return "gui_hideout_vegtable_tomato.png"

	elseif uuid == obj_crates_broccoli then
		return "gui_hideout_vegtable_broccoli.png"

	elseif uuid == obj_survivalobject_farmerball then
		return "gui_hideout_farmball.png"
	end

	return ""
end

function HideoutTrader.sv_saveInventory( self, container )
	local quantities = sm.container.quantity( container )
	local currentItems = {}
	for index,quantity in ipairs( quantities ) do
		if quantity > 0 then
			local itemUuid = sm.container.getItem( container, index - 1 )
			currentItems[tostring( itemUuid.uuid )] = quantity
		end
	end
	local traderInfo = sm.storage.load( STORAGE_CHANNEL_TRADER_INFORMATION ) or {}
	traderInfo.currentItems = currentItems
	sm.storage.save( STORAGE_CHANNEL_TRADER_INFORMATION, traderInfo )
end

function HideoutTrader.cl_updateResourceCounter( self, resourceCounter, quantity )
	local digits = {}
	digits[1] = resourceCounter.Childs[2].Childs[1]
	digits[2] = resourceCounter.Childs[2].Childs[2]
	digits[3] = resourceCounter.Childs[2].Childs[3]

	if quantity < 0  then
		quantity = 0
	end
	
	if quantity >= 999 then
		digits[1].Caption = "#FFFFFFF9"
		digits[2].Caption = "#FFFFFFF9"
		digits[3].Caption = "#FFFFFFF9"
	else
		local qtyString = tostring(quantity)
		local len = string.len( qtyString )

		if len == 1 then
			digits[1].Caption = self.ResourceCountGrey.."0"
			digits[2].Caption = self.ResourceCountGrey.."0"
			digits[3].Caption = qtyString
			return
		elseif len == 2 then
			digits[1].Caption = self.ResourceCountGrey.."0"
			digits[2].Caption = string.sub( qtyString, 1, 1 )
			digits[3].Caption = string.sub( qtyString, 2, 2 )
			return
		else
			for i = 1, 3, 1 do
				digits[i].Caption = string.sub( qtyString, i, i )
			end
		end
	end
end

function HideoutTrader.cl_updateGui( self )
	--main panel
	if self.cl.hideoutInventory == nil then
		self.cl.hideoutInventory = self.interactable:getContainer()
	end
	if self.cl.hideoutInventory then
		self:cl_updateResourceCounter( TraderGui.BananaCount, sm.container.totalQuantity( self.cl.hideoutInventory, obj_crates_banana ) )
		self:cl_updateResourceCounter( TraderGui.BerryCount, sm.container.totalQuantity( self.cl.hideoutInventory, obj_crates_blueberry ) )
		self:cl_updateResourceCounter( TraderGui.BroccoliCount, sm.container.totalQuantity( self.cl.hideoutInventory, obj_crates_broccoli ) )
		self:cl_updateResourceCounter( TraderGui.OrangeCount, sm.container.totalQuantity( self.cl.hideoutInventory, obj_crates_orange ) )
		self:cl_updateResourceCounter( TraderGui.PineappleCount, sm.container.totalQuantity( self.cl.hideoutInventory, obj_crates_pineapple ) )
		self:cl_updateResourceCounter( TraderGui.BeetCount, sm.container.totalQuantity( self.cl.hideoutInventory, obj_crates_redbeet ) )
		self:cl_updateResourceCounter( TraderGui.TomatoCount, sm.container.totalQuantity( self.cl.hideoutInventory, obj_crates_tomato ) )
		self:cl_updateResourceCounter( TraderGui.CarrotCount, sm.container.totalQuantity( self.cl.hideoutInventory, obj_crates_carrot ) )
		self:cl_updateResourceCounter( TraderGui.FarmerCount, sm.container.totalQuantity( self.cl.hideoutInventory, obj_survivalobject_farmerball ) )
	end

	-- trade options
	if self.cl.gui then
		TraderGui.scrollView.Childs = {}

		ensureExtraTrades()

		local function iconOk( itemId )
			return rfsIconForTrade( itemId )
		end

		local shopItemCount = 0
		for tradeDataIndex, tradeData in ipairs( TradeData ) do
			-- add trade option if it is unlocked
			if tradeData.schematic then
				local isWaiting = self.cl.newSchematicTrades and self.cl.newSchematicTrades[tradeData.itemId] == true
				if isWaiting == false or ( self.cl.depositEvent and self.cl.depositEvent.groupTimer > TraderGui.GroupChangeEffectDelay )  then
					local alreadyUnlocked = RecipeManager.Cl_IsUnlocked( tradeData.itemId ) == true or ( self.cl.unlockedItem == tradeData.itemId and self.cl.unlockedItemType == "schematic" )
					if ( not alreadyUnlocked ) and ( DefaultUnlockedSchematicTradesSet[tradeData.itemId] or self.cl.unlockState.unlockedSchematicTrades[tradeData.itemId] ) then
						local okIcon, resource, group, name = iconOk( tradeData.itemId )
						if not okIcon then
							-- Skip unknown / missing shapes ("BLOCK NOT FOUND")
						else
						shopItemCount = shopItemCount + 1
						if self.cl.unlockedItem and self.cl.selectedItem.shopIndex == shopItemCount then
							self.cl.selectedItem.tradeDataIndex = tradeDataIndex
						end

						ItemImageWidgetSchematic.ImageResource = resource
						ItemImageWidgetSchematic.ImageGroup = group
						ItemImageWidgetSchematic.ImageName = name
						ItemRootWidgetSchematic.onClick = "cl_selectTrade"
						ItemRootWidgetSchematic.onClickData = { shopIndex = shopItemCount, tradeDataIndex = tradeDataIndex }
	
						if isWaiting then
							ItemSlotSchematic.Childs[3].Effects[1].PlayState = "Auto play once"
							ItemSlotSchematic.Childs[3].CroppingWidget = "MainPanel" -- cropped by gridscrollview main panel
							self.cl.newSchematicTrades[tradeData.itemId] = nil
						else
							ItemSlotSchematic.Childs[3].Effects[1].PlayState = "Auto play off"
						end
	
						table.insert(TraderGui.scrollView.Childs,DeepCopy(ItemSlotSchematic) )
						end
					end
				end
			elseif tradeData.cosmetic then
				local isWaiting = self.cl.newCosmeticTrades and self.cl.newCosmeticTrades[tradeData.itemId] == true
				if isWaiting == false or ( self.cl.depositEvent and self.cl.depositEvent.groupTimer > TraderGui.GroupChangeEffectDelay )  then
					local alreadyUnlocked = sm.localPlayer.isGarmentUnlocked( sm.uuid.new( tradeData.itemId ) ) or ( self.cl.unlockedItem == tradeData.itemId and self.cl.unlockedItemType == "cosmetic" )
					if ( not alreadyUnlocked ) and ( DefaultUnlockedCosmeticTradesSet[tradeData.itemId] or self.cl.unlockState.unlockedCosmeticTrades[tradeData.itemId] ) then
						shopItemCount = shopItemCount + 1
						if self.cl.unlockedItem and self.cl.selectedItem.shopIndex == shopItemCount then
							self.cl.selectedItem.tradeDataIndex = tradeDataIndex
						end
						
						ItemImageWidgetCosmetic.ImageResource = "CustomizationIconMap"
						ItemImageWidgetCosmetic.ImageGroup = "CustomizationIconMap"
						ItemImageWidgetCosmetic.ImageName = tradeData.itemId.."_male"
						ItemRootWidgetCosmetic.onClick = "cl_selectTrade"
						ItemRootWidgetCosmetic.onClickData = { shopIndex = shopItemCount, tradeDataIndex = tradeDataIndex }
	
						if isWaiting then
							ItemSlotCosmetic.Childs[3].Effects[1].PlayState = "Auto play once"
							ItemSlotCosmetic.Childs[3].CroppingWidget = "MainPanel" -- cropped by gridscrollview main panel
							self.cl.newCosmeticTrades[tradeData.itemId] = nil
						else
							ItemSlotCosmetic.Childs[3].Effects[1].PlayState = "Auto play off"
						end
	
						table.insert(TraderGui.scrollView.Childs, DeepCopy(ItemSlotCosmetic) )
					end
				end
			else
				local isWaiting = self.cl.newTrades and self.cl.newTrades[tradeData.itemId] == true
				if isWaiting == false or ( self.cl.depositEvent and self.cl.depositEvent.groupTimer > TraderGui.GroupChangeEffectDelay ) then 
					if DefaultUnlockedTradesSet[tradeData.itemId] or self.cl.unlockState.unlockedTrades[tradeData.itemId] then
						local okIcon, resource, group, name = iconOk( tradeData.itemId )
						if okIcon then
						shopItemCount = shopItemCount + 1
						if self.cl.unlockedItem and self.cl.selectedItem.shopIndex == shopItemCount then
							self.cl.selectedItem.tradeDataIndex = tradeDataIndex
						end

						ItemImageWidget.ImageResource = resource
						ItemImageWidget.ImageGroup = group
						ItemImageWidget.ImageName = name
						ItemRootWidget.onClick = "cl_selectTrade"
						ItemRootWidget.onClickData = { shopIndex = shopItemCount, tradeDataIndex = tradeDataIndex }
						
						if isWaiting then
							ItemSlot.Childs[6].Effects[1].PlayState = "Auto play once"
							ItemSlot.Childs[6].CroppingWidget = "MainPanel" -- cropped by gridscrollview main panel
							self.cl.newTrades[tradeData.itemId] = nil
						else
							ItemSlot.Childs[6].Effects[1].PlayState = "Auto play off"
						end
	
						table.insert(TraderGui.scrollView.Childs,DeepCopy(ItemSlot) )
						end
					end
				end
			end
		end

	
		local gridItems = TraderGui.scrollView.Childs
		for _, item in ipairs( gridItems ) do
			item.StateSelected = false
		end
		

		if self.cl.selectedItem ~= nil and self.cl.selectedItem.shopIndex and self.cl.selectedItem.tradeDataIndex and gridItems[self.cl.selectedItem.shopIndex] then
			gridItems[self.cl.selectedItem.shopIndex].StateSelected = true
			TraderGui.TradePanel.Visible = true
			
			local displayTrade = TradeData[self.cl.selectedItem.tradeDataIndex]
			local uuid = sm.uuid.new( displayTrade.itemId )

			if displayTrade.cosmetic then
					TraderGui.DescriptionBox.Caption = ""
					TraderGui.Title.Caption = sm.localPlayer.getGarmentName( uuid )

					TraderGui.TradeCountBG.Visible = false
					TraderGui.TradeCountSchematic.Visible = false
					TraderGui.TradeCountCosmetic.Visible = true
					TraderGui.TradeIcon.ImageResource = "CustomizationIconMap"
					TraderGui.TradeIcon.ImageGroup = "CustomizationIconMap"
					TraderGui.TradeIcon.ImageName = displayTrade.itemId.."_male"
			else
				if displayTrade.schematic then
					TraderGui.TradeCountSchematic.Visible = true
					TraderGui.TradeCountCosmetic.Visible = false
					TraderGui.TradeCountBG.Visible = false
				else
					TraderGui.TradeCountSchematic.Visible = false
					TraderGui.TradeCountCosmetic.Visible = false
					TraderGui.TradeCountBG.Visible = true

					TraderGui.TradeCount.Caption = self.TradeCountColor1.."x"..self.TradeCountColor2..tostring( displayTrade.quantity )
					local calculatedTextWidth, _ = sm.gui.computeTextSize( TraderGui.TradeCount.Caption, TraderGui.TradeCount.FontName, TraderGui.TradeCount.TextAlign )
					TraderGui.TradeCount.width = calculatedTextWidth
				end

				local title, desc = rfsTradeTitleDesc( displayTrade.itemId, uuid )
				TraderGui.DescriptionBox.Caption = desc or ""
				TraderGui.Title.Caption = title or ""

				local okIcon, resource, group, name = rfsIconForTrade( displayTrade.itemId )
				if okIcon then
					TraderGui.TradeIcon.ImageResource = resource
					TraderGui.TradeIcon.ImageGroup = group
					TraderGui.TradeIcon.ImageName = name
				end
			end
			
			TraderGui.DescriptionBox.Visible = TraderGui.DescriptionBox.Caption ~= ""
			TraderGui.DescriptionHeader.Visible = TraderGui.DescriptionBox.Caption ~= ""
			TraderGui.DescriptionLine.Visible = TraderGui.DescriptionBox.Caption ~= ""

			local sufficientIngredients = true

			TraderGui.IngredientItems.Childs = {}
			for i, ingredient in ipairs( displayTrade.ingredientList ) do
				local ingredientUuid = sm.uuid.new( ingredient.itemId )

				local currentIngredientQty = sm.container.totalQuantity( self.cl.hideoutInventory, ingredientUuid )
				local color = HideoutTrader.SufficientIngredientColor

				local sufficient = currentIngredientQty >= ingredient.quantity
				if not sufficient then
					color = HideoutTrader.InsufficientIngredientColor
				end
				sufficientIngredients = sufficientIngredients and sufficient

				IngredientItemIcon.ImageTexture = self:resourceToImage( ingredientUuid )
				IngredientItemQuantity.Caption = color..currentIngredientQty..IngredientItemTextColor.." / "..ingredient.quantity
				TraderGui.IngredientItems.Childs[i] = DeepCopy( IngredientItem )
			end
			
			
			TraderGui.Preview.ItemPreview = rfsPreviewItemId( displayTrade.itemId )
			TraderGui.TradeButton.Enabled = sufficientIngredients





		else
			TraderGui.TradePanel.Visible = false
		end
	end

	if self.cl.unlockState then
		local currentGroup = self.cl.unlockState.currentGroup
		if self.cl.depositEvent and self.cl.depositEvent.groupTimer <= TraderGui.GroupChangeEffectDelay then
			currentGroup = self.cl.depositEvent.group
		end


		if self.cl.unlockState.currentStep >= currentGroup.steps and self.cl.unlockState.nextGroup == nil then
			TraderGui.UnlockPanel.Visible = false
		else
			TraderGui.UnlockPanel.Visible = true

			local stepOffset = TraderGui.BarBackground.height / currentGroup.steps

			local remainingSteps = currentGroup.steps - self.cl.unlockState.currentStep
			if self.cl.depositEvent and not (self.cl.depositEvent.groupTimer >= TraderGui.GroupChangeHideFinalRewardDelay) then
			 	remainingSteps = currentGroup.steps - self.cl.depositEvent.step
			end
			
			if self.cl.depositEvent then
				if self.cl.depositEvent.groupSwap and self.cl.depositEvent.groupTimer > 0 then
					local t = sm.util.easing( sm.util.easingFunctionIds.easeOutQuart, saturate( (self.cl.depositEvent.groupTimer - TraderGui.GroupChangeHideFinalRewardDelay ) / TraderGui.GroupChangeResetBarDuration ) )
					
					local y0 = TraderGui.BarBackground.y
					local y1 = TraderGui.BarBackground.y + TraderGui.BarBackground.height
					local y = lerp( y0, y1, t )
					TraderGui.Bar.y = round( y )
	
					local height0 = TraderGui.BarBackground.height
					local height1 = 0
					local height = lerp( height0, height1, t )
	
					TraderGui.Bar.height = round( height )
				else
					local t = sm.util.easing( sm.util.easingFunctionIds.easeOutCubic, saturate( self.cl.depositEvent.depositTimer / TraderGui.BarAnimationDuration ) )

					local y0 = TraderGui.BarBackground.y + stepOffset * ( self.cl.depositEvent.group.steps - self.cl.depositEvent.step ) -- from the step at event start
					local y1 = TraderGui.BarBackground.y + stepOffset * ( self.cl.depositEvent.group.steps - ( self.cl.depositEvent.step + 1 ) ) -- to currentStep
					if self.cl.depositEvent.groupSwap then
						y1 = y1 - TraderGui.FinalRewardBG.height / 2
					end

					local y = lerp( y0, y1, t )
					TraderGui.Bar.y = round( y )
	
					local height0 = stepOffset * self.cl.depositEvent.step
					local height1 = stepOffset * ( self.cl.depositEvent.step + 1 )
					if self.cl.depositEvent.groupSwap then
						height1 = height1 + TraderGui.FinalRewardBG.height / 2
					end



					local height = lerp( height0, height1, t )
	
					TraderGui.Bar.height = round( height )
				end
			else
				TraderGui.Bar.y = round( TraderGui.BarBackground.y + stepOffset * remainingSteps )
				TraderGui.Bar.height = round( stepOffset * self.cl.unlockState.currentStep )
			end

			local updateRewardMarker = function( reward, rewardWidget )
				local bgEffectBox = rewardWidget.Childs[1]

				if not ( reward.giveItem or reward.unlockCraftBot or reward.unlockCosmetic ) then
					sm.log.warning( "HideoutTrader: reward selected for display does not grant an item, schematic or cosmetic. Reorder the tradegroup so a displayable reward is first for this step. Step:", reward.step )
				end

				if reward.unlockCosmetic then
					rewardWidget.ImageTexture = "gui_hideout_bgitem_outfit.png"

					bgEffectBox.Effects[1].PlayState = "Stopped"

					rewardWidget.Childs[2].ImageResource = "CustomizationIconMap"
					rewardWidget.Childs[2].ImageGroup = "CustomizationIconMap"
					rewardWidget.Childs[2].ImageName = tostring( reward.item ).."_male" -- never unlocking hair/facial hair/face
				else
					if reward.unlockCraftBot then
						rewardWidget.ImageTexture = "gui_hideout_bgitem_blue.png"
						if self.cl.depositEvent then
							if self.cl.depositEvent.groupSwap then
								bgEffectBox.Effects[1].PlayState = ( self.cl.depositEvent.groupTimer > TraderGui.GroupChangeNewRewardDelay ) and "Auto playing" or "Stopped"
							else
								bgEffectBox.Effects[1].PlayState = ( reward.step > ( self.cl.depositEvent.step + 1 ) ) and "Auto playing" or "Stopped"
							end
						else
							bgEffectBox.Effects[1].PlayState = ( reward.step > ( currentGroup.steps - remainingSteps ) ) and "Auto playing" or "Stopped"
						end
					else
						rewardWidget.ImageTexture = "gui_hideout_bgitem_yellow.png"
						bgEffectBox.Effects[1].PlayState = "Stopped"
					end

					local resource, group, name = sm.gui.getItemIconFromUuid( reward.item )
					rewardWidget.Childs[2].ImageGroup = group
					rewardWidget.Childs[2].ImageName = name
					rewardWidget.Childs[2].ImageResource = resource
				end
			end

			local unlockedReward = false
			if #currentGroup.rewards > 0 then
				TraderGui.Markers.Childs = {}
				if currentGroup.steps > 1 then			
					for i = 1, currentGroup.steps - 1, 1 do
						TraderGui.Marker.Visibe = true
						if self.cl.depositEvent and self.cl.depositEvent.groupSwap then
						 	if self.cl.depositEvent.groupTimer > TraderGui.GroupChangeHideFinalRewardDelay then
								TraderGui.Marker.Visibe = false
						 	end
						end

						TraderGui.Marker.y = round( ( currentGroup.steps - i ) * stepOffset - TraderGui.Marker.height / 2 )
						if currentGroup.steps - i > remainingSteps - 1 then
							TraderGui.Marker.ImageTexture = "gui_hideout_progressionmarker_selected.png"
						else
							TraderGui.Marker.ImageTexture = "gui_hideout_progressionmarker_default.png"
						end
						TraderGui.Markers.Childs[i] = DeepCopy( TraderGui.Marker )
					end

					local rewardStepsSet = {}
					for i, reward in ipairs(currentGroup.rewards) do
						if reward.step ~= nil and TraderGui.Markers.Childs[reward.step] then
							if not rewardStepsSet[reward.step] then
								rewardStepsSet[reward.step] = true
							
								local y = TraderGui.Markers.Childs[reward.step].y - round( TraderGui.RewardIconBG.height / 2 )
								TraderGui.Markers.Childs[reward.step] = DeepCopy( TraderGui.RewardIconBG )

								local rewardMarker = TraderGui.Markers.Childs[reward.step]
								rewardMarker.y = y

								updateRewardMarker( reward, rewardMarker )

								

								local overlayEffectBox = rewardMarker.Childs[2].Childs[1]

								if self.cl.depositEvent then
									if self.cl.depositEvent.groupTimer <= 0.0 and self.cl.depositEvent.step + 1 == reward.step then
										unlockedReward = true

										if self.cl.depositEvent.depositTimer > 0 and TraderGui.Bar.y <= ( rewardMarker.y + rewardMarker.height + TraderGui.Markers.y ) then
											overlayEffectBox.Effects[1].PlayState = "Auto play once"
										end
									elseif self.cl.depositEvent.groupTimer > 0.0 then
										if self.cl.depositEvent.groupTimer > TraderGui.GroupChangeNewRewardDelay then
											rewardMarker.Alpha = 1
											rewardMarker.Childs[1].Alpha = 1
										elseif self.cl.depositEvent.groupTimer > TraderGui.GroupChangeEffectDelay then
											overlayEffectBox.Effects[2].PlayState = "Auto play once"
											rewardMarker.Alpha = 0
											rewardMarker.Childs[1].Alpha = 0
										else
											local alpha = 1 - saturate( (self.cl.depositEvent.groupTimer - TraderGui.GroupChangeHideFinalRewardDelay) / TraderGui.GroupChangeFadeDuration )
											rewardMarker.Alpha = alpha
											rewardMarker.Childs[1].Alpha = alpha
										end
									end
								end
							end
						end
					end
				end
			end

			if self.cl.depositEvent then
				-- no reward and not final fast forward to end of deposit event
				if (not unlockedReward) and self.cl.unlockState.currentStep < currentGroup.steps and self.cl.depositEvent.depositTimer >= TraderGui.BarAnimationDuration then
					self.cl.depositEvent.depositTimer = TraderGui.DepositEventDuration -- skip waiting for unlock reward effect
				end
			end

			for _, reward in ipairs(currentGroup.rewards) do
				if ( reward.step == nil or reward.step == currentGroup.steps ) and ( reward.giveItem or reward.unlockCraftBot or reward.unlockCosmetic ) then
					updateRewardMarker( reward, TraderGui.FinalRewardBG )
				end
			end

			TraderGui.FinalRewardImage.Alpha = 1
			TraderGui.FinalRewardEffectBox.Effects[2].PlayState = "Auto play off"
			TraderGui.FinalRewardEffectBox.Effects[1].PlayState = "Auto play off"

			if self.cl.depositEvent and self.cl.depositEvent.groupSwap then
				if self.cl.depositEvent.groupTimer > 0.0 then
					if self.cl.depositEvent.groupTimer > TraderGui.GroupChangeEffectDelay and self.cl.depositEvent.groupTimer < TraderGui.GroupChangeNewRewardDelay then
						TraderGui.FinalRewardEffectBox.Effects[2].PlayState = "Auto play once"
					end
					if self.cl.depositEvent.groupTimer > TraderGui.GroupChangeHideFinalRewardDelay and self.cl.depositEvent.groupTimer < TraderGui.GroupChangeNewRewardDelay then -- hide reward icon until effect has played for long enough
						TraderGui.FinalRewardBG.ImageTexture = "gui_hideout_bgitem_grey.png"
						TraderGui.FinalRewardImage.Alpha = 0
					end
				end
			
				if TraderGui.Bar.y <= ( TraderGui.FinalRewardBG.y + TraderGui.FinalRewardBG.height ) then
					TraderGui.FinalRewardEffectBox.Effects[1].PlayState = "Auto play once"
				end
			end

			local resourceUuid = sm.uuid.new( currentGroup.resource )
			TraderGui.ResourceIcon.ImageTexture = self:resourceToImage( resourceUuid )
			
			-- disable button during transition to next
			if self.cl.depositEvent then
				TraderGui.ProgressButton.StateSelected = false
				TraderGui.NeedMouse = false
				TraderGui.ProgressButton.Enabled = false
				TraderGui.ProgressButtonEffectBox.Effects[1].PlayState = "Stopped"
			else
				TraderGui.ProgressButton.StateSelected = false
				TraderGui.NeedMouse = true
				local buttonEnabled = false
				if self.cl.hideoutInventory then
					buttonEnabled = sm.container.totalQuantity( self.cl.hideoutInventory, resourceUuid ) > 0
				end

			


				
				buttonEnabled = buttonEnabled and self:cl_canCollectReward()

				TraderGui.ProgressButton.Enabled = buttonEnabled
				TraderGui.ProgressButtonEffectBox.Effects[1].PlayState = buttonEnabled and "Auto playing" or "Stopped"
			end
		end
	end

	self.cl.draw = true
	self.cl.updateGui = false
end

function HideoutTrader.sv_e_rfsHijack( self, params )
	params = params or {}
	if type( RfsBotHijack ) ~= "table" then
		sm.gui.chatMessage( "[RFS] Hijack failed: RfsBotHijack not loaded" )
		return
	end
	RfsBotHijack.ensureHooks()
	local world = nil
	pcall( function()
		world = self.shape.body:getWorld()
	end )
	local n, info = RfsBotHijack.convertNearest( params.player, params.range or 16, world )
	if n and n > 0 then
		sm.gui.chatMessage( "[RFS] Infected " .. tostring( info ) .. " (allies=" .. tostring( RfsBotHijack.count( world ) ) .. ")" )
	else
		sm.gui.chatMessage( "[RFS] Hijack failed: " .. tostring( info ) .. " (range " .. tostring( params.range or 16 ) .. ")" )
	end
end

function HideoutTrader.sv_e_rfsHijackList( self, params )
	if type( RfsBotHijack ) ~= "table" then
		sm.gui.chatMessage( "[RFS] Ally robots: 0" )
		return
	end
	RfsBotHijack.ensureHooks()
	local world = nil
	pcall( function()
		world = self.shape.body:getWorld()
	end )
	local n, tethered, infected = RfsBotHijack.count( world )
	sm.gui.chatMessage( "[RFS] Ally robots: " .. tostring( n or 0 ) .. " (tethered " .. tostring( tethered or 0 ) .. ", infected " .. tostring( infected or 0 ) .. ")" )
end

function HideoutTrader.sv_e_rfsUnhijack( self, params )
	params = params or {}
	if type( RfsBotHijack ) ~= "table" then
		sm.gui.chatMessage( "[RFS] Unhijack failed: RfsBotHijack not loaded" )
		return
	end
	RfsBotHijack.ensureHooks()
	local world = nil
	pcall( function()
		world = self.shape.body:getWorld()
	end )
	local n, info = RfsBotHijack.unhijackNearest( params.player, params.range or 16, world, params.allowAny == true )
	if n and n > 0 then
		sm.gui.chatMessage( "[RFS] Released " .. tostring( info ) .. " (voluntary — still hackable)" )
	else
		sm.gui.chatMessage( "[RFS] Unhijack failed: " .. tostring( info ) )
	end
end

function HideoutTrader.server_onCreate( self )
	self.sv = {}
	_G.g_rfsHideoutTraderSv = self
	pcall( function()
		if type( RfsBotHijack ) == "table" then
			RfsBotHijack.ensureHooks()
		end
	end )










	-- Storage
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}

		self.sv.saved.pendingRewards = {}
	end

	local shouldSave = false

	if self.sv.saved.unlockState == nil then
		self.sv.saved.unlockState = {
			questIndex = 1,
			currentGroup = TraderQuestGroups[1],
			
			currentStep = 0,
			cycleIndex = 0,
			cycleList = DeepCopy( TraderCyclicGroups ),
			unlockList = DeepCopy( TraderTierUnlockGroups ),

			unlockedTrades = {},
			unlockedSchematicTrades = {},
			unlockedCosmeticTrades = {}
		}
		self.sv.saved.unlockState.currentGroup.isQuest = true
		for _, group in ipairs( self.sv.saved.unlockState.cycleList ) do
			if group.recurring == false then
				group.completed = false
			end
		end
		for _, group in ipairs( self.sv.saved.unlockState.unlockList ) do
			group.completed = false
		end

		shouldSave = true
		local traderInfo = sm.storage.load( STORAGE_CHANNEL_TRADER_INFORMATION ) or {}
		traderInfo.tradeInfo = { currentGroup = self.sv.saved.unlockState.currentGroup, currentStep = self.sv.saved.unlockState.currentStep, questIndex = self.sv.saved.unlockState.questIndex }
		sm.storage.save( STORAGE_CHANNEL_TRADER_INFORMATION, traderInfo )
	end

	if self.sv.saved.unlockState then
		self.network:setClientData( self.sv.saved.unlockState, 2 )
	end

	if self.params then
		if self.params.vacuumInteractable then
			self.sv.saved.vacuumInteractable = self.params.vacuumInteractable
		end
		if self.params.buttonInteractable then
			self.sv.saved.buttonInteractable = self.params.buttonInteractable
		end
		if self.params.cameraNode then
			self.sv.saved.cameraNode = self.params.cameraNode
		end
		if self.params.dropzoneNode then
			self.sv.saved.dropzoneNode = self.params.dropzoneNode
		end
		shouldSave = true
	end

	-- Server
	if self.sv.saved.vacuumInteractable then
		self.sv.vacuumInteractable = self.sv.saved.vacuumInteractable
	else
		sm.log.info("Patching missing vacuum interactable, attempting to find it")
		self.sv.saved.vacuumInteractable = FindFirstInteractable( "d1840356-ad77-4505-a9a0-10d11a77986f" )
		assert( self.sv.saved.vacuumInteractable, "Failed to find vacuum interactable" )
		self.sv.vacuumInteractable = self.sv.saved.vacuumInteractable
		shouldSave = true
	end

	if self.sv.saved.buttonInteractable then
		self.sv.buttonInteractable = self.sv.saved.buttonInteractable
	else
		sm.log.info("Patching missing button interactable, attempting to find it")
		self.sv.saved.buttonInteractable = FindFirstInteractable( "712a5ebd-0793-49ba-b1ef-681a8fdceba6" )
		assert( self.sv.saved.buttonInteractable, "Failed to find button interactable" )
		self.sv.buttonInteractable = self.sv.saved.buttonInteractable
		shouldSave = true
	end

	if self.sv.saved.cameraNode then
		self.sv.cameraNode = self.sv.saved.cameraNode
	else
		sm.log.info("Patching missing camera node, attempting to find it")
		local x, y = getCell( self.shape:getWorldPosition().x, self.shape:getWorldPosition().y )
		local cameraNodes = sm.cell.getNodesByTag( x, y, "CAMERA" )
		self.sv.saved.cameraNode = cameraNodes[1]
		assert( self.sv.saved.cameraNode, "Failed to find camera node")
		self.sv.cameraNode = self.sv.saved.cameraNode
		shouldSave = true
	end

	if self.sv.saved.dropzoneNode then
		self.sv.dropzoneNode = self.sv.saved.dropzoneNode
	else
		sm.log.info("Patching missing dropzone node, attempting to find it")
		local x, y = getCell( self.shape:getWorldPosition().x, self.shape:getWorldPosition().y )
		local dropzoneNodes = sm.cell.getNodesByTag( x, y, "HIDEOUT_DROPZONE" )
		self.sv.saved.dropzoneNode = dropzoneNodes[1]
		assert( self.sv.saved.dropzoneNode, "Failed to find dropzone node")
		self.sv.dropzoneNode = self.sv.saved.dropzoneNode
		shouldSave = true
	end

	assert( self.sv.vacuumInteractable )
	assert( self.sv.buttonInteractable )
	assert( self.sv.cameraNode )
	assert( self.sv.dropzoneNode )

	if shouldSave then
		self.storage:save( self.sv.saved )
		shouldSave = false
	end

    self.sv.logAreaTrigger = sm.areaTrigger.createAttachedBox( self.shape, sm.vec3.new( 50, 11, 30 ), sm.vec3.new( 15, 5, 25 ), nil, sm.areaTrigger.filter.character )
    self.sv.logAreaTrigger:bindOnEnter( "sv_t_onLogAreaEnter", self )

	self.sv.playerAreaTrigger = sm.areaTrigger.createAttachedBox( self.shape, sm.vec3.new( 9.5, 8.5, 8.5 ), nil, nil, sm.areaTrigger.filter.character )
	self.sv.playerAreaTrigger:bindOnExit( "sv_t_playerLeave" )

	self:sv_init()
end

function HideoutTrader.sv_save( self )
	self.sv.saved.vacuumInteractable = self.sv.vacuumInteractable
	self.sv.saved.buttonInteractable = self.sv.buttonInteractable
	self.sv.saved.cameraNode = self.sv.cameraNode
	self.sv.saved.dropzoneNode = self.sv.dropzoneNode
	self.storage:save( self.sv.saved )
end

function HideoutTrader.server_onRefresh( self )
	self:sv_init()
end

function HideoutTrader.sv_init( self )

	self.sv.buttonInteractable:connect( self.interactable )

	local container = self.interactable:getContainer( 0 )
	if not container then
		container = self.interactable:addContainer( 0, 16 )
	end
	container:setFilters( HideoutVacuumItems )

	if self.sv.dropZoneArea then
		sm.areaTrigger.destroy( self.sv.dropZoneArea )
		self.areaTrigger = nil
	end

	if self.sv.dropzoneNode then
		local halfExtents = self.sv.dropzoneNode.scale * 0.5
		local filter = sm.areaTrigger.filter.dynamicBody + sm.areaTrigger.filter.staticBody
		self.sv.dropZoneArea = sm.areaTrigger.createBox( halfExtents, self.sv.dropzoneNode.position, self.sv.dropzoneNode.rotation, filter )
	end

	self.sv.vacuumTicks = 0
	self.sv.vacuumActive = false

	self.network:setClientData( { cameraNode = self.sv.cameraNode, vacuumInteractable = self.sv.vacuumInteractable } )

	self.network:setClientData( self.sv.saved.unlockState, 2 )
end

function HideoutTrader.sv_t_onLogAreaEnter( self, trigger, results )
	if TriggerResultContainsAnyPlayer( results ) then
		if not LogEntryManager.Sv_HasLog( LOGS.log_hideout ) then
			LogEntryManager.Sv_AddLog( LOGS.log_hideout )
		end
    end
end

function HideoutTrader.sv_t_playerLeave( self, trigger, results )
	if TriggerResultContainsAnyPlayer( results ) then
		QuestManager.Sv_SendEvent( QuestEvent.TraderLeaveArea )
	end
end

function HideoutTrader.sv_vacuumObject( self )
	local container = self.interactable:getContainer( 0 )
	if container == nil then
		return false
	end
	local contents = self.sv.dropZoneArea:getContents()
	for _, body in ipairs( contents ) do
		if sm.exists( body ) then
			for _, shape in ipairs( body:getShapes() ) do
				if sm.exists( shape ) then
					local shapeUuid = shape:getShapeUuid()
					if not sm.item.isBlock( shapeUuid ) then
						if isAnyOf( shapeUuid, HideoutVacuumItems ) then
							sm.container.beginTransaction()
							sm.container.collect( container, shapeUuid, 1, true )
							if sm.container.endTransaction() then
								QuestManager.Sv_SendEvent(QuestEvent.DeliverTraderCrate, { shapeUuid = shapeUuid })
								self.network:sendToClients("cl_n_addVacuumItem",{shapeUuid = shapeUuid,fromPosition = shape.worldPosition,fromRotation = shape.worldRotation})
								sm.shape.destroyShape(shape)
								self:sv_saveInventory(container)
								
								-- Quest Achievements
								if shapeUuid == obj_survivalobject_farmerball then
									sm.achievement.addi("8d601982-4608-4d5e-bb9e-e4041486f7c7", 1, nil)
								end

								
								return true
							end
						end
					end
				end
			end
		end
	end
	return false
end

function HideoutTrader.server_onFixedUpdate( self, timeStep )
	if type( RfsBotHijack ) == "table" then
		local tick = sm.game.getCurrentTick()
		if ( tick % 10 ) == 0 then
			pcall( function()
				RfsBotHijack.ensureHooks()
				RfsBotHijack.tick( self.shape.body:getWorld() )
			end )
		end
	end
	if self.sv.saved.pendingRewards and not IsEmptyTable( self.sv.saved.pendingRewards ) then
		local tick = sm.game.getCurrentTick()
		local anyRemoved = false
		
		removeFromArray( self.sv.saved.pendingRewards, function( pending )
			if ( tick - pending.rewardTick ) >= TraderGui.DepositEventDuration * 40 then
				if pending.reward.giveItem then
					if sm.exists( pending.reward.player ) then
						local inventory = pending.reward.player:getInventory()
						if not inventory then
							return false
						end
						sm.container.beginTransaction()
						sm.container.collect( inventory, sm.uuid.new( pending.reward.item ), pending.reward.amount, true )
						if not sm.container.endTransaction() then
							return false -- abort, do not remove from pending rewards
						end
					else -- if intended recipient does not exist. try to give to host player
						local hostPlayer = sm.player.getHostPlayer()
						if not hostPlayer then
							return false
						end
						local hostInventory = hostPlayer:getInventory()
						if not hostInventory then
							return false
						end
						sm.container.beginTransaction()
						sm.container.collect( hostInventory, sm.uuid.new( pending.reward.item ), pending.reward.amount, true )
						if not sm.container.endTransaction() then
							return false
						end
					end
				end

				-- these do not have a failure state
				if pending.reward.unlockCraftBot then
					RecipeManager.Sv_UnlockRecipe( tostring( pending.reward.item ) )
				end
				if pending.reward.unlockTrader then
					self.sv.saved.unlockState.unlockedTrades[ tostring( pending.reward.item ) ] = true
				end
				if pending.reward.unlockTraderSchematic then
					self.sv.saved.unlockState.unlockedSchematicTrades[ tostring( pending.reward.item ) ] = true
				end
				if pending.reward.unlockTraderCosmetic then
					self.sv.saved.unlockState.unlockedCosmeticTrades[ tostring( pending.reward.item ) ] = true
				end
				if pending.reward.unlockCosmetic then
					sm.event.sendToGame("sv_e_grantAdditionalRewards",
						{ { uuid = pending.reward.item, type = "additionalReward" } })
				end
				anyRemoved = true
				return true
			end
			return false
		end )

		if anyRemoved then
			self.storage:save( self.sv.saved )
			self.network:setClientData( self.sv.saved.unlockState, 2 )
		end
	end

	local buttonIsActive = false
	local parent = self.interactable:getSingleParent()
	if parent then
		buttonIsActive = parent:isActive()
	end

	if buttonIsActive and not self.sv.vacuumActive then
		self.sv.vacuumActive = self:sv_vacuumObject()
	end

	if self.sv.vacuumActive then
		self.sv.vacuumTicks = self.sv.vacuumTicks + 1
		if self.sv.vacuumTicks >= self.VacuumTickTime then
			self.sv.vacuumTicks = 0
			self.sv.vacuumActive = self:sv_vacuumObject()
		end
	end

	if self.sv.vacuumInteractable and sm.exists( self.sv.vacuumInteractable ) then
		self.sv.vacuumInteractable.active = self.sv.vacuumActive
	end
end

-- Client

function HideoutTrader.client_onCreate( self )
	self:cl_init()
	-- RFS: register for /tshop remote open (real hideout instance + unlock state)
	_G.g_rfsHideoutTrader = self
end

function HideoutTrader.client_onDestroy( self )
	if _G.g_rfsHideoutTrader == self then
		_G.g_rfsHideoutTrader = nil
	end
end

-- RFS chat /tshop — open shop GUI without proximity (same path as E interact).
-- Bypasses client_canInteract unlock gate (quest_feed_the_farmers) for host testing,
-- matching always-on RFS cheat commands like /farmers.
function HideoutTrader.cl_rfs_openShop( self, params )
	local player = sm.localPlayer.getPlayer()
	local character = player and player.character
	if not character then
		return false
	end
	if self.cl.user ~= nil and self.cl.user ~= player then
		sm.gui.chatMessage( "[RFS] Farmers Hideout shop is busy" )
		return false
	end
	if self.cl.user == player and self.cl.gui and sm.exists( self.cl.gui ) and not self.cl.gui:isHidden() then
		sm.gui.chatMessage( "[RFS] Farmers Hideout shop already open" )
		return true
	end
	self:client_onInteract( character, true )
	if self.cl.user == player then
		sm.gui.chatMessage( "[RFS] Farmers Hideout shop opened (/tshop)" )
		return true
	end
	return false
end

function HideoutTrader.client_onRefresh( self )
	if self.cl then
		if self.cl.user then
			self.cl.user.clientPublicData.interactableCameraData = nil
			self.cl.user.character:setLockingInteractable( nil )
			self.cl.user = nil

			self.cl.draw = false
			self.cl.gui:close()
			self.cl.gui = nil
		end
	end
	self:cl_init()
end

function HideoutTrader.client_onAction( self, action, state )
	if action == 17 then -- EKeyAction_Cancel
		self:cl_onClose()
		return true
	end
	return false
end

-- Animation States
local char_hideoutfarmer =
{
	Open = { nextAnimation = "Idle" },
	Close = { clampWhenFinished = true },
	Idle = true,
	Confirm01 = { nextAnimation = "Idle" },
	Confirm02 = { nextAnimation = "Idle" },
	Confirm03 = { nextAnimation = "Idle" },
	aimbend_updown = { controlled = true, lerpSpeed = 1.0 / 15.0 },
	aimbend_leftright = { controlled = true, lerpSpeed = 1.0 / 15.0 },
}

function HideoutTrader.cl_init( self )
	if self.cl == nil then
		self.cl = {}
	end
	if self.cl.vacuumItems == nil then
		self.cl.vacuumItems = {}
	end

	self.cl.newTrades = {}
	self.cl.newSchematicTrades = {}
	self.cl.newCosmeticTrades = {}

	self.cl.hideoutInventory = self.interactable:getContainer()
	self.cl.animations = self.cl.animations or {}

	-- Setup animations
	for name, data in pairs(char_hideoutfarmer) do 
		local args = (type(data) == "table" and data) or nil
		INIT_ANIMATION( self.cl.animations,self.interactable ,name, args )
	end	
	self.cl.animator = CREATE_ANIMATOR( self.interactable, self.cl.animations )
	local closeDuration = self.cl.animator:getDuration( "Close" )
	self.cl.animator:setCurrentAnimation( "Close", closeDuration )
	self.cl.animator:enableHeadTracking({
    upDownAnim = "aimbend_updown",
    leftRightAnim = "aimbend_leftright",
    lookAtRange = OpenShutterDistance,
	lookFromOffset = sm.vec3.new( 0, -0.5, 0 ),
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
})
end

function HideoutTrader.server_onDestroy( self )
	if _G.g_rfsHideoutTraderSv == self then
		_G.g_rfsHideoutTraderSv = nil
	end
	self.network:setClientData( nil ) -- used to avoid receiving client data from last load
end

function HideoutTrader.cl_n_addVacuumItem( self, params )
	if self.cl == nil then
		self.cl = {}
	end
	if self.cl.vacuumItems == nil then
		self.cl.vacuumItems = {}
	end

	local vacuumItem = {}
	vacuumItem.effect = sm.effect.createEffect( "ShapeRenderable" )
	vacuumItem.effect:setParameter( "uuid", params.shapeUuid )
	vacuumItem.effect:setPosition( params.fromPosition )
	vacuumItem.effect:setRotation( params.fromRotation )
	vacuumItem.effect:setScale( sm.vec3.new( 0.25, 0.25, 0.25 ) )
	vacuumItem.effect:start()
	vacuumItem.elapsedTime = 0.0
	vacuumItem.fromPosition = params.fromPosition
	vacuumItem.fromRotation = params.fromRotation
	sm.effect.playHostedEffect( "Hideout - PumpAudio", self.cl.vacuumInteractable, "suction3_jnt" )
	local vacuumPosition = self.cl.vacuumInteractable:getWorldBonePosition( "suction3_jnt" )
	vacuumItem.toRotation = sm.vec3.getRotation( sm.vec3.new( 0, -1, 0 ), ( vacuumItem.fromPosition - vacuumPosition ):normalize() )

	local shapeSize = sm.item.getShapeSize( params.shapeUuid )
	local maxSize = math.max( math.max( shapeSize.x, shapeSize.y ), shapeSize.z )
	vacuumItem.blockScale = sm.vec3.new( 0.25, 0.25, 0.25 ) / maxSize
	self.cl.vacuumItems[#self.cl.vacuumItems+1] = vacuumItem
end

function HideoutTrader.cl_unlockEffect( self )
	self.cl.finalUnlockEffectBox = self.cl.gui:getWidget( "FinalRewardImageEffectBox" )
	self.cl.finalUnlockEffectBox:startEffect( "unlock" )
	self.cl.finalUnlockEffect = self.cl.finalUnlockEffectBox:getEffect( "unlock" )
	assert( self.cl.finalUnlockEffect ~= nil )
end

function HideoutTrader.client_onClientDataUpdate( self, clientData, channel )

	if self.cl == nil then
		self.cl = {}
	end

	if channel == 1 and clientData ~= nil then
		self.cl.cameraNode = clientData.cameraNode
		self.cl.vacuumInteractable = clientData.vacuumInteractable
	elseif channel == 2 then
		if not self.cl.unlockState then
			-- initial receive
			self.cl.unlockState = clientData
		else
			if self.cl.gui then
				if self.cl.unlockState.unlockedTrades then
					for itemId, _ in pairs( clientData.unlockedTrades ) do
						if not self.cl.unlockState.unlockedTrades[itemId] then
							self.cl.newTrades[itemId] = true
						end
					end
					for itemId, _ in pairs( clientData.unlockedSchematicTrades ) do
						if not self.cl.unlockState.unlockedSchematicTrades[itemId] then
							self.cl.newSchematicTrades[itemId] = true
						end
					end
					for itemId, _ in pairs( clientData.unlockedCosmeticTrades ) do
						if not self.cl.unlockState.unlockedCosmeticTrades[itemId] then
							self.cl.newCosmeticTrades[itemId] = true
						end
					end
				end
	
				-- if gui is open and unlock state changes, play deposit animation
				if clientData.currentStep ~= self.cl.unlockState.currentStep then
					self.cl.depositEvent = {
						depositTime = TraderGui.DepositEventDuration,
						depositTimer = 0,
						groupTimer = 0,
						step = self.cl.unlockState.currentStep,
						group = self.cl.unlockState.currentGroup,
						groupSwap = ( self.cl.unlockState.currentStep + 1 ) == self.cl.unlockState.currentGroup.steps,
						groupChangeEffectPlayed = false
					}

					if self.cl.gui and not self.cl.gui:isHidden() then
						local remaining = self.cl.unlockState.currentGroup.steps - self.cl.unlockState.currentStep
						if remaining == 1 then
							sm.effect.playEffect( "audio:event:/ui/trading/deposit_up_3" )
						elseif remaining == 2 then
							sm.effect.playEffect( "audio:event:/ui/trading/deposit_up_2" )
						else
							sm.effect.playEffect( "audio:event:/ui/trading/deposit_up_1" )
						end
					end
						
					if self.cl.depositEvent.groupSwap then
						self.cl.depositEvent.depositTime = TraderGui.BarAnimationDuration
					end
				end
			end
			self.cl.unlockState = clientData
		end
	end
end

function HideoutTrader.cl_n_tradeCompleted( self, params )
	if self.cl.gui and sm.exists( self.cl.gui ) and self.cl.gui:isActive() then
		self.cl.updateGui = true
	end
	self.cl.unlockedItem = params.unlockedItem
	self.cl.unlockedItemType = params.unlockedItemType

	self.cl.animator:setCurrentAnimationVariation({ Confirm01 = 1, Confirm02 = 1, Confirm03 = 1 })
end

function HideoutTrader.client_onInteract( self, character, state )
	if state == true then
		if self.cl.user == nil then
			
			character:setLockingInteractable( self.interactable )
			self.cl.user = character:getPlayer()

			self.cl.playerInventory = character:getPlayer():getInventory()
			if self.cl.playerInventory == nil then
				sm.log.error( "HideoutTrader: Failed to get player inventory" )
				return
			end
			
			if self.cl.gui == nil then
				self.cl.gui = sm.jsonGui.createGui( { handleKeySetup = "Hideout", name = "Hideout" } )
			else
				self.cl.gui:setHidden( false )
			end

			self:cl_updateGui()

			self.cl.gui:render( TraderGui.json )
		end
	end
end

function HideoutTrader.cl_isTraderActive( self )





	if QuestManager.Cl_IsQuestComplete( "quest_feed_the_farmers" ) then
		return true
	end

	local quest = QuestManager.Cl_GetActiveQuest( "quest_feed_the_farmers" )
	if quest and quest.clientPublicData and quest.clientPublicData.traderUnlocked then
		return true
	end
	return false
end

function HideoutTrader.client_canInteract( self )
	return self:cl_isTraderActive()
end

function HideoutTrader.sv_n_trade( self, selectedItem, player )
	local ingredients = TradeData[selectedItem].ingredientList
	local itemId = TradeData[selectedItem].itemId
	local qty = TradeData[selectedItem].quantity
	local schematic = TradeData[selectedItem].schematic
	local cosmetic = TradeData[selectedItem].cosmetic
	local extras = TradeData[selectedItem].extras

	sm.container.beginTransaction()

	for i, collect in ipairs( ingredients ) do
		local itemUid = sm.uuid.new( collect.itemId )
		local container
		if isAnyOf( itemUid, HideoutVacuumItems ) then
			container = self.interactable:getContainer( 0 )
		else
			container = player:getInventory()
			if container == nil then
				sm.log.error( "HideoutTrader: Failed to get player inventory" )
				sm.container.abortTransaction()
				return
			end
		end
		local spend = true



		if spend then
			sm.container.spend( container, itemUid, collect.quantity, true )
		end
	end

	if not schematic and not cosmetic then
		local inventory = player:getInventory()
		if inventory == nil then
			sm.log.error( "HideoutTrader: Failed to get player inventory" )
			sm.container.abortTransaction()
			return
		end
		sm.container.collect( inventory, sm.uuid.new( itemId ), qty, true )
	end

	if not sm.container.endTransaction() then
		NotificationManager.Cl_AddGenericNotification( "#{INFO_INVENTORY_FULL}", 4 )
		return --The player failed the trade transaction, abort
	end
	
	local tradeCompletedParam = {}
	if schematic then
		RecipeManager.Sv_UnlockRecipe( tostring( itemId ) )
		if extras then
			for _, value in ipairs( extras ) do
				RecipeManager.Sv_UnlockRecipe( tostring( value.itemId ) )
			end
		end
		tradeCompletedParam.unlockedItem = itemId
		tradeCompletedParam.unlockedItemType = "schematic"
	elseif cosmetic then
		sm.event.sendToGame( "sv_e_grantAdditionalRewardsForPlayer", { rewardList = { { uuid = itemId, type = "additionalReward" } }, player = player } )
		tradeCompletedParam.unlockedItem = itemId
		tradeCompletedParam.unlockedItemType = "cosmetic"
	end
	self.network:sendToClients( "cl_n_tradeCompleted", tradeCompletedParam )
end

function HideoutTrader.sv_n_deposit( self, _, player )

	local unlockState = self.sv.saved.unlockState
	if unlockState then
		-- is there a reward for this step?
		local nextStep = unlockState.currentStep + 1
		local stepRewards = {}

		for _, reward in ipairs( unlockState.currentGroup.rewards ) do
			if reward.step == nextStep or ( reward.step == nil and nextStep == unlockState.currentGroup.steps ) then
				stepRewards[#stepRewards+1] = reward
			end
		end

		local container = self.interactable:getContainer( 0 )
		local turnInSucceeded = false
		local progressedToNextGroup = false
		if container then
			sm.container.beginTransaction()

			local spend = true



			if spend then
				sm.container.spend( container, sm.uuid.new( unlockState.currentGroup.resource ), 1, true )
			end

			if sm.container.endTransaction() then
				--success, spent resource, get rewards, advance step
				self:sv_saveInventory( container )

				turnInSucceeded = true
				for _, stepReward in ipairs( stepRewards ) do
					if self.sv.saved.pendingRewards == nil then
						self.sv.saved.pendingRewards = {}
					end
					table.insert( self.sv.saved.pendingRewards, { reward = stepReward, player = player, rewardTick = sm.game.getServerTick() } )
					if stepReward and stepReward.activateQuest and stepReward.activateQuest ~= "" then
						if stepReward.dialogUuid then
							local params = {
								questName = stepReward.activateQuest,
								prerequisiteQuestEvent = QuestEvent.TraderLeaveArea,
								prerequisiteTimeoutTicks = 5 * 40,
								dialogUuid = tostring( stepReward.dialogUuid ),
								dialogType = DialogType.Call,
								dialogSpeaker = DialogSpeakerName.Hubert,
								dialogEntry = "Start",
								prerequisiteQuest = stepReward.prerequisiteQuest,
								tickDelay = stepReward.dialogDelaySeconds and stepReward.dialogDelaySeconds * 40 or 0
							}
							params.dialogSpeaker = DialogSpeakerName[stepReward.speaker] or DialogSpeakerName.Hubert
							sm.scriptableObject.createScriptableObject( sm.uuid.new( "9dde94ad-6524-4e1d-9024-1210c0ab659d" ), params )
						end
					end
				end
				unlockState.currentStep = unlockState.currentStep + 1
			else
				print( "Trader error: insufficient deposit resources!" )
			end
		end

		local nextGroup = nil

		-- if final step, unlock and pick next group
		if unlockState.currentStep == unlockState.currentGroup.steps then
			if unlockState.currentGroup.completed == false then
				unlockState.currentGroup.completed = true
			end
			QuestManager.Sv_SendEvent( QuestEvent.TraderCompleteTrade )

			-- attempt to pick quest group
			if unlockState.questIndex < #TraderQuestGroups then
				unlockState.questIndex = unlockState.questIndex + 1
				if unlockState.questIndex <= #TraderQuestGroups then
					nextGroup = TraderQuestGroups[unlockState.questIndex]
					nextGroup.isQuest = true
				end
			else
				sm.achievement.seti( "77fb497e-5df0-40ee-a5c3-ce27e167f2f7", 1, nil )
			end


			-- attempt to pick tier unlock group
			if nextGroup == nil then
				for _, group in ipairs( unlockState.unlockList ) do
					if group.completed == false and group.tier <= 1 then
						nextGroup = group
						break
					end
				end
			end

			-- attempt to pick cycle group
			if nextGroup == nil then
				for i = 1, #unlockState.cycleList, 1 do
					-- step through cycle until we find one that is unlocked
					unlockState.cycleIndex = unlockState.cycleIndex + 1
					if unlockState.cycleIndex > #unlockState.cycleList then
						unlockState.cycleIndex = 1
					end
					local c = unlockState.cycleList[unlockState.cycleIndex]
					if ( c.tier <= 1 or c.tier == nil ) then
						if not ( c.recurring == false and c.completed == true ) then
							nextGroup = c
							break
						end
					end
				end
			end
		end

		if nextGroup then
			self.sv.saved.unlockState.currentGroup = nextGroup
			self.sv.saved.unlockState.currentStep = 0
		end

		self.network:setClientData( self.sv.saved.unlockState, 2 )

		self.storage:save( self.sv.saved )

		local traderInfo = sm.storage.load( STORAGE_CHANNEL_TRADER_INFORMATION ) or {}
		traderInfo.tradeInfo = { currentGroup = self.sv.saved.unlockState.currentGroup, currentStep = self.sv.saved.unlockState.currentStep, questIndex = self.sv.saved.unlockState.questIndex }
		sm.storage.save( STORAGE_CHANNEL_TRADER_INFORMATION, traderInfo )
		
		if turnInSucceeded then
			QuestManager.Sv_SendEvent( QuestEvent.TraderProgressTrade )
		end
		if progressedToNextGroup then
			QuestManager.Sv_SendEvent( QuestEvent.TraderCompleteTrade )
		end
	end
end

function HideoutTrader.cl_canCollectReward( self )
	local nextStep = self.cl.unlockState.currentStep + 1
	local rewardUuids = {}
	local rewardQuantities = {}
	for _, reward in ipairs( self.cl.unlockState.currentGroup.rewards ) do
		if reward.step == nextStep or ( reward.step == nil and nextStep == self.cl.unlockState.currentGroup.steps ) then
			if reward.giveItem then
				
				local alreadyExistsAtIdx = valueIndex( rewardUuids, reward.item )
				if alreadyExistsAtIdx == nil then
					rewardUuids[#rewardUuids+1] = reward.item
					rewardQuantities[#rewardQuantities+1] = reward.amount
				else
					rewardQuantities[alreadyExistsAtIdx] = rewardQuantities[alreadyExistsAtIdx] + reward.amount
				end

			end
		end
	end

	local inventory = sm.localPlayer.getPlayer():getInventory()
	if inventory == nil then
		sm.log.error( "HideoutTrader: Failed to get player inventory" )
		return false
	end

	return inventory:canCollectAll( rewardUuids, rewardQuantities )
end

function HideoutTrader.cl_onDepositClick( self, widgetName, data )
	if self.cl.depositEvent then
		return
	end

	if self.cl.gui then
		local buttonClickEffectBox = self.cl.gui:getWidget( "ProgressButtonEffectBox" )
		if buttonClickEffectBox then
			buttonClickEffectBox:startEffect( "ButtonClick" )
		end
		sm.effect.playEffect( "audio:event:/ui/trading/deposit" )
	end

	if self:cl_canCollectReward() then
		self.network:sendToServer( "sv_n_deposit" )
	else
		NotificationManager.Cl_AddGenericNotification( "#{INFO_INVENTORY_FULL}", 4 )
	end
end

function HideoutTrader.cl_onTradeClick( self, widgetName, data )
	if self.cl.selectedItem ~= nil then
		if self.cl.gui and sm.exists( self.cl.gui ) then
			local tradeButtonEffectBox = self.cl.gui:getWidget( "TradeButtonEffectBox" )
			if tradeButtonEffectBox then
				tradeButtonEffectBox:startEffect( "tradebutton" )
			end
			sm.effect.playEffect( "audio:event:/ui/trading/trade" )
		end
		self.network:sendToServer( "sv_n_trade", self.cl.selectedItem.tradeDataIndex )
	end
end

function HideoutTrader.cl_selectTrade( self, widgetName, data )
	if self.cl.selectedItem == nil then
		self.cl.selectedItem = {}
	end

	if self.cl.selectedItem.shopIndex ~= data.shopIndex or self.cl.selectedItem.tradeDataIndex ~= data.tradeDataIndex then
		self.cl.selectedItem = { shopIndex = data.shopIndex, tradeDataIndex = data.tradeDataIndex }
		self.cl.updateGui = true
		self.cl.draw = true
	end
end

function HideoutTrader.cl_onClose( self )
	if self.cl.user then
		self.cl.user.clientPublicData.interactableCameraData = nil
		self.cl.user.character:setLockingInteractable( nil )
		self.cl.user = nil

		self.cl.finalUnlockEffect = nil

		self.cl.draw = false

		if self.cl.depositEvent then
			self.cl.gui:setHidden( true )
		elseif self.cl.gui and sm.exists( self.cl.gui ) then
			self.cl.gui:close()
			self.cl.gui = nil
		end
	end
end

function HideoutTrader.client_onUpdate( self, dt )
	if self.cl.depositEvent then
		if self.cl.depositEvent.depositTimer < self.cl.depositEvent.depositTime then
			self.cl.depositEvent.depositTimer = self.cl.depositEvent.depositTimer + dt
			self.cl.updateGui = true
		elseif self.cl.depositEvent.groupSwap then
			if self.cl.depositEvent.groupTimer < TraderGui.GroupChangeDuration then
				self.cl.depositEvent.groupTimer = self.cl.depositEvent.groupTimer + dt
				self.cl.updateGui = true
				if self.cl.depositEvent.groupChangeEffectPlayed == false and self.cl.depositEvent.groupTimer >= TraderGui.GroupChangeEffectDelay then
					self.cl.depositEvent.groupChangeEffectPlayed = true
					if self.cl.gui and not self.cl.gui:isHidden() then
						sm.effect.playEffect( "audio:event:/ui/trading/update_store_inventory" )
					end
				end
			else
				self.cl.depositEvent = nil
				clearTable( self.cl.newTrades )
				clearTable( self.cl.newSchematicTrades )
				clearTable( self.cl.newCosmeticTrades )
				self.cl.updateGui = true
			end
		else
			self.cl.depositEvent = nil
			clearTable( self.cl.newTrades )
			clearTable( self.cl.newSchematicTrades )
			clearTable( self.cl.newCosmeticTrades )
			self.cl.updateGui = true
		end

		if self.cl.depositEvent == nil then
			if self.cl.gui and self.cl.gui:isHidden() then
				self.cl.gui:close()
				self.cl.gui = nil
			end
		end
	end


	if self.cl.unlockState.nextGroup then
		-- if there is an effect playing wait for it to finish before displaying next group
		if self.cl.finalUnlockEffect == nil or not self.cl.finalUnlockEffect:isPlaying() then
			self.cl.unlockState.currentGroup = self.cl.unlockState.nextGroup
			self.cl.unlockState.nextGroup = nil
			self.cl.unlockState.currentStep = 0
			self.cl.updateGui = true
		end
	end

	local container = self.interactable:getContainer( 0 )
	if container then
		local newRevision = container:getRevision()
		if self.cl.containerRevision ~= newRevision then
			self.cl.updateGui = true
		end
		self.cl.containerRevision = newRevision
	end

	if self.cl.updateGui then
		self:cl_updateGui()

		if self.cl.unlockedItem then
			if self.cl.unlockedItemType == "schematic" and RecipeManager.Cl_IsUnlocked( self.cl.unlockedItem ) then
					self.cl.unlockedItem = nil
					self.cl.unlockedItemType = nil
			elseif self.cl.unlockedItemType == "cosmetic" and sm.localPlayer.isGarmentUnlocked( sm.uuid.new( self.cl.unlockedItem ) ) then
				self.cl.unlockedItem = nil
				self.cl.unlockedItemType = nil
			end
		end
	end

	if self.cl.draw and self.cl.gui and not self.cl.gui:isHidden() then
		self.cl.gui:render( TraderGui.json )
	end
	self.cl.draw = false

	self:cl_openClose()
	self.cl.animator:update( dt )

	if self.cl.user == sm.localPlayer.getPlayer() then
		UpdateVendorCamera( self, dt )
	end

	local vacuumPosition = self.cl.vacuumInteractable:getWorldBonePosition( "suction3_jnt" )
	local arriveFraction = 1.1
	local vacuumTime = ( self.VacuumTickTime / 40 ) * arriveFraction
	local remainingVacuumItems = {}
	for _, vacuumItem in ipairs( self.cl.vacuumItems ) do
		vacuumItem.elapsedTime = vacuumItem.elapsedTime + dt
		if vacuumItem.elapsedTime >= vacuumTime then
			vacuumItem.effect:stop()
		else
			local windup = 0.6
			local progress = math.min( vacuumItem.elapsedTime / vacuumTime, 1.0 )
			if progress > windup then
				local windupProgress = ( ( progress - windup )/( 1 - windup ) )
				vacuumItem.effect:setPosition( sm.vec3.lerp( vacuumItem.fromPosition, vacuumPosition, windupProgress ) )
				vacuumItem.effect:setRotation( sm.quat.slerp( vacuumItem.fromRotation, vacuumItem.toRotation, windupProgress ) )
				vacuumItem.effect:setScale( sm.vec3.lerp( sm.vec3.new( 0.25, 0.25, 0.25 ), vacuumItem.blockScale, windupProgress ) )
			end
			remainingVacuumItems[#remainingVacuumItems+1] = vacuumItem
		end
	end
	self.cl.vacuumItems = remainingVacuumItems
end

function HideoutTrader.cl_openClose( self )
	local currentAnimation = self.cl.animator.currentAnimation
	if not self:cl_isTraderActive() then
		return
	end

	if currentAnimation == "Close" then
		if self.cl.animator:getElapsedTime() >= self.cl.animator:getDuration() then
			if GetClosestPlayer( self.shape.worldPosition, OpenShutterDistance, self.shape.body:getWorld() ) ~= nil then
				self.cl.animator:setCurrentAnimation( "Open" )
			end
		end
	end

	if currentAnimation == "Idle" then
		if GetClosestPlayer( self.shape.worldPosition, CloseShutterDistance, self.shape.body:getWorld() ) == nil then
			self.cl.animator:setCurrentAnimation( "Close" )
		end
	end
end

function HideoutTrader.sv_e_resetUnlockState( self )
	self.sv.saved.unlockState = {
		questIndex = 1,
		currentGroup = TraderQuestGroups[1],
		
		currentStep = 0,
		cycleIndex = 0,
		cycleList = DeepCopy( TraderCyclicGroups ),
		unlockList = DeepCopy( TraderTierUnlockGroups ),

		unlockedTrades = {},
		unlockedSchematicTrades = {},
		unlockedCosmeticTrades = {}
	}

	for _, group in ipairs( self.sv.saved.unlockState.cycleList ) do
		if group.recurring == false then
			group.completed = false
		end
	end
	for _, group in ipairs( self.sv.saved.unlockState.unlockList ) do
		group.completed = false
	end

	self.storage:save( self.sv.saved )

	self.network:setClientData( self.sv.saved.unlockState, 2 )
end
