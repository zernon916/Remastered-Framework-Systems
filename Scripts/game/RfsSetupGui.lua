-- RfsSetupGui.lua — /setup tabbed GUI for Recipe Framework Survival
-- Author: DemonsDen126
-- Style skins match Recipe Radar (BackgroundInteractableWide, InventoryTab, PrimaryButton).

RfsSetupGui = RfsSetupGui or {}

local LAYOUT = "$CONTENT_DATA/Gui/Layouts/Rfs_Setup.layout"
local QUEST_ROWS = 6

local function flyOn()
	return g_rfs_clientFly == true
end

local function godOn()
	return g_godMode == true
end

local function limitedOn()
	local ok, limited = pcall( sm.game.getLimitedInventory )
	if ok then
		return limited and true or false
	end
	return true
end

function RfsSetupGui.refreshMain( host )
	local gui = host.cl and host.cl.rfsSetupGui
	if not gui then return end

	local cheats = RfsSettings.cheatsEnabled()
	pcall( function()
		gui:setVisible( "BtnInventory", cheats )
		gui:setVisible( "BtnFly", cheats )
		gui:setVisible( "BtnGod", cheats )
	end )

	if not cheats then
		if RfsSettings.frameworkOnly() then
			gui:setText( "Status", "Framework-only (cheats + Quest tab OFF; hooks on)" )
		else
			gui:setText( "Status", "Cheats OFF (rfs_settings.json)" )
		end
		return
	end

	local invLabel = limitedOn() and "Inventory: Limited" or "Inventory: Unlimited"
	local flyLabel = "Fly: " .. ( flyOn() and "ON" or "OFF" )
	local godLabel = "God: " .. ( godOn() and "ON" or "OFF" )

	gui:setText( "BtnInventory", invLabel )
	gui:setText( "BtnFly", flyLabel )
	gui:setText( "BtnGod", godLabel )
	gui:setText( "Status", string.format( "%s  |  %s  |  %s", invLabel, flyLabel, godLabel ) )
end

local function sortedKeys( t )
	local keys = {}
	if type( t ) ~= "table" then return keys end
	local isArray = true
	for k, _ in pairs( t ) do
		if type( k ) ~= "number" then
			isArray = false
			break
		end
	end
	if isArray then
		for _, v in ipairs( t ) do
			keys[#keys + 1] = tostring( v )
		end
	else
		for k, _ in pairs( t ) do
			keys[#keys + 1] = tostring( k )
		end
	end
	table.sort( keys )
	return keys
end

function RfsSetupGui.buildQuestRows( host )
	host.cl = host.cl or {}
	local data = host.cl.rfsQuestData or { active = {}, completed = {}, available = {} }
	local rows = {}

	for _, name in ipairs( sortedKeys( data.active ) ) do
		rows[#rows + 1] = { name = name, status = "A" }
	end
	for _, name in ipairs( sortedKeys( data.available ) ) do
		rows[#rows + 1] = { name = name, status = "?" }
	end
	for _, name in ipairs( sortedKeys( data.completed ) ) do
		rows[#rows + 1] = { name = name, status = "C" }
	end

	host.cl.rfsQuestRows = rows
	host.cl.rfsQuestPage = host.cl.rfsQuestPage or 0
	local maxPage = math.max( 0, math.ceil( #rows / QUEST_ROWS ) - 1 )
	if host.cl.rfsQuestPage > maxPage then
		host.cl.rfsQuestPage = maxPage
	end
	if host.cl.rfsQuestPage < 0 then
		host.cl.rfsQuestPage = 0
	end
	return rows
end

function RfsSetupGui.refreshQuest( host )
	local gui = host.cl and host.cl.rfsSetupGui
	if not gui then return end

	local rows = RfsSetupGui.buildQuestRows( host )
	local page = host.cl.rfsQuestPage or 0
	local maxPage = math.max( 0, math.ceil( math.max( #rows, 1 ) / QUEST_ROWS ) - 1 )

	for i = 0, QUEST_ROWS - 1 do
		local row = rows[page * QUEST_ROWS + i + 1]
		local show = row ~= nil
		gui:setVisible( "QuestRow" .. i, show )
		gui:setVisible( "QuestInfo" .. i, show )
		gui:setVisible( "QuestStart" .. i, show )
		gui:setVisible( "QuestDone" .. i, show )
		if show then
			local label = string.format( "[%s] %s", row.status, row.name )
			if #label > 36 then
				label = string.sub( label, 1, 33 ) .. "..."
			end
			gui:setText( "QuestRow" .. i, label )
		else
			gui:setText( "QuestRow" .. i, "" )
		end
	end

	gui:setText( "QuestPage", string.format( "Page %d / %d  (%d quests)", page + 1, maxPage + 1, #rows ) )
	gui:setVisible( "QuestPrev", page > 0 )
	gui:setVisible( "QuestNext", page < maxPage )
end

function RfsSetupGui.refreshInvSize( host )
	local gui = host.cl and host.cl.rfsSetupGui
	if not gui then return end

	local curId = host.cl.rfsInvSizeId or "vanilla"
	local cur = RfsInventory.getOption( curId )
	for i, opt in ipairs( RfsInventory.OPTIONS ) do
		local widget = "InvSize" .. ( i - 1 )
		local mark = ( opt.id == cur.id ) and " [ON]" or ""
		gui:setText( widget, opt.label .. " (" .. tostring( opt.slots ) .. ")" .. mark )
		pcall( function()
			gui:setButtonState( widget, opt.id == cur.id )
		end )
	end
	gui:setText( "InvSizeStatus", string.format(
		"Current: %s — %d slots (10 wide). Choice saves with the world.",
		cur.label, cur.slots
	) )
end

function RfsSetupGui.refreshFarming( host )
	local gui = host.cl and host.cl.rfsSetupGui
	if not gui then return end

	local cheats = RfsSettings.cheatsEnabled()
	local watered = ( host.cl and host.cl.rfsAlwaysWatered ) or ( _G.g_rfsAlwaysWatered == true )
	local dirt = ( host.cl and host.cl.rfsDirtOnBlocks ) or ( _G.g_rfsDirtOnBlocks == true )
	local fastPlace = ( host.cl and host.cl.rfsFastPlace ) or ( _G.g_rfsFastPlace == true )
	local fastPickup = ( host.cl and host.cl.rfsFastPickup ) or ( _G.g_rfsFastPickup == true )

	pcall( function()
		gui:setVisible( "BtnInstantFarm", cheats )
		gui:setVisible( "BtnAlwaysWatered", cheats )
		gui:setVisible( "BtnDirtOnBlocks", cheats )
		gui:setVisible( "BtnFastPlace", cheats )
		gui:setVisible( "BtnFastPickup", cheats )
		-- Growth overlay moved to player /menu — never show here.
		gui:setVisible( "BtnGrowthOverlay", false )
	end )

	gui:setText( "BtnAlwaysWatered", "Always watered: " .. ( watered and "ON" or "OFF" ) )
	gui:setText( "BtnDirtOnBlocks", "Dirt on blocks: " .. ( dirt and "True" or "False" ) )
	gui:setText( "BtnFastPlace", "Fast place: " .. ( fastPlace and "ON" or "OFF" ) )
	gui:setText( "BtnFastPickup", "Fast pickup: " .. ( fastPickup and "ON" or "OFF" ) )
	pcall( function()
		gui:setButtonState( "BtnAlwaysWatered", watered )
		gui:setButtonState( "BtnDirtOnBlocks", dirt )
		gui:setButtonState( "BtnFastPlace", fastPlace )
		gui:setButtonState( "BtnFastPickup", fastPickup )
	end )

	local lines = {
		"Instant Farm: matures all loaded outdoor GrowingHarvestable crops (loaded cells, world-wide).",
		"Always watered: ticks Survival sv_e_waterSoil on soil + growing plants.",
		"Dirt on blocks: Soil Bag may place on body/lift tops (not only terrain). Harvestable stays world-fixed.",
		"Fast place: LMB drag rectangle batch soil placement (terrain follow or flat block/lift tops; release to place).",
		"Fast pickup: RMB drag rectangle batch soil pickup (red rect; soil bag, empty hand, or block).",
		"Growth Time overlay is a personal preference — use /menu (not /setup).",
		"Growbeds / wild farmables unchanged. Toggles save with the world (sm.storage).",
	}
	if not cheats then
		table.insert( lines, 1, "Cheats OFF — farming cheat toggles hidden." )
	end
	gui:setText( "FarmingStatus", table.concat( lines, "\n" ) )
	gui:setText( "Status", string.format(
		"Farming | watered=%s | dirtBlocks=%s | fastPlace=%s | fastPickup=%s | cheats=%s",
		watered and "ON" or "OFF",
		dirt and "True" or "False",
		fastPlace and "ON" or "OFF",
		fastPickup and "ON" or "OFF",
		cheats and "ON" or "OFF"
	) )
end

function RfsSetupGui.showTab( host, tab )
	local gui = host.cl and host.cl.rfsSetupGui
	if not gui then return end

	local questOk = RfsSettings.questTabEnabled()
	local cheats = RfsSettings.cheatsEnabled()
	if tab == "quest" and not questOk then
		tab = "main"
	end
	if tab == "invsize" and not cheats then
		tab = "main"
	end

	host.cl.rfsSetupTab = tab or "main"
	local t = host.cl.rfsSetupTab
	local main = t == "main"
	local quest = t == "quest"
	local inv = t == "invsize"
	local farm = t == "farming"

	gui:setVisible( "MainTab", main )
	gui:setVisible( "QuestTab", quest and questOk )
	gui:setVisible( "InvSizeTab", inv and cheats )
	gui:setVisible( "FarmingTab", farm )
	pcall( function()
		gui:setButtonState( "TabMain", main )
		gui:setButtonState( "TabQuest", quest )
		gui:setButtonState( "TabInvSize", inv )
		gui:setButtonState( "TabFarming", farm )
		gui:setVisible( "TabQuest", questOk )
		gui:setVisible( "TabInvSize", cheats )
		gui:setVisible( "TabFarming", true )
	end )

	if main then
		RfsSetupGui.refreshMain( host )
	elseif quest then
		RfsSetupGui.refreshQuest( host )
		host.network:sendToServer( "sv_rfs_setupQuestData" )
	elseif inv then
		host.network:sendToServer( "sv_rfs_invSizeGet" )
		RfsSetupGui.refreshInvSize( host )
	elseif farm then
		host.network:sendToServer( "sv_rfs_farmingGet" )
		RfsSetupGui.refreshFarming( host )
	end
end

function RfsSetupGui.bind( host, gui )
	host.cl = host.cl or {}
	host.cl.rfsSetupGui = gui
	host.cl.rfsSetupTab = host.cl.rfsSetupTab or "main"
	host.cl.rfsQuestPage = host.cl.rfsQuestPage or 0
	host.cl.rfsInvSizeId = host.cl.rfsInvSizeId or "vanilla"

	gui:setButtonCallback( "CloseButton", "cl_rfs_setupClose" )
	gui:setButtonCallback( "TabMain", "cl_rfs_setupTabMain" )
	gui:setButtonCallback( "TabQuest", "cl_rfs_setupTabQuest" )
	gui:setButtonCallback( "TabInvSize", "cl_rfs_setupTabInvSize" )
	gui:setButtonCallback( "TabFarming", "cl_rfs_setupTabFarming" )
	gui:setButtonCallback( "BtnInventory", "cl_rfs_setupToggleInventory" )
	gui:setButtonCallback( "BtnFly", "cl_rfs_setupToggleFly" )
	gui:setButtonCallback( "BtnGod", "cl_rfs_setupToggleGod" )
	gui:setButtonCallback( "QuestRefresh", "cl_rfs_setupQuestRefresh" )
	gui:setButtonCallback( "QuestPrev", "cl_rfs_setupQuestPrev" )
	gui:setButtonCallback( "QuestNext", "cl_rfs_setupQuestNext" )
	for i = 0, QUEST_ROWS - 1 do
		gui:setButtonCallback( "QuestRow" .. i, "cl_rfs_setupQuestSelect" )
		gui:setButtonCallback( "QuestInfo" .. i, "cl_rfs_setupQuestInfo" )
		gui:setButtonCallback( "QuestStart" .. i, "cl_rfs_setupQuestStart" )
		gui:setButtonCallback( "QuestDone" .. i, "cl_rfs_setupQuestDone" )
	end
	for i = 0, 4 do
		gui:setButtonCallback( "InvSize" .. i, "cl_rfs_setupInvSizeSelect" )
	end
	gui:setButtonCallback( "BtnInstantFarm", "cl_rfs_setupInstantFarm" )
	gui:setButtonCallback( "BtnAlwaysWatered", "cl_rfs_setupToggleAlwaysWatered" )
	gui:setButtonCallback( "BtnDirtOnBlocks", "cl_rfs_setupToggleDirtOnBlocks" )
	gui:setButtonCallback( "BtnFastPlace", "cl_rfs_setupToggleFastPlace" )
	gui:setButtonCallback( "BtnFastPickup", "cl_rfs_setupToggleFastPickup" )
	-- BtnGrowthOverlay left unbound — personal overlay lives in /menu
	gui:setOnCloseCallback( "cl_rfs_setupClose" )
end

function RfsSetupGui.open( host )
	local okHost, isHost = pcall( function() return sm.isHost end )
	if not ( okHost and isHost ) then
		sm.gui.chatMessage( "[RFS] /setup is host-only. Use /menu for personal options." )
		return
	end

	if host.cl and host.cl.rfsSetupGui then
		pcall( function() host.cl.rfsSetupGui:close() end )
		host.cl.rfsSetupGui = nil
	end

	local ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT )
	if not ok or not gui then
		sm.gui.chatMessage( "[RFS] Failed to open /setup GUI" )
		print( "[RFS] setup GUI create failed: " .. tostring( gui ) )
		return
	end

	RfsSetupGui.bind( host, gui )
	RfsSetupGui.showTab( host, "main" )
	gui:open()
	sm.gui.chatMessage( "RFS Setup opened" )
end

function RfsSetupGui.close( host )
	local gui = host.cl and host.cl.rfsSetupGui
	if gui then
		pcall( function() gui:close() end )
	end
	if host.cl then
		host.cl.rfsSetupGui = nil
	end
end

function RfsSetupGui.rowFromWidget( host, widgetName )
	local idx = tonumber( string.match( tostring( widgetName or "" ), "(%d+)$" ) )
	if idx == nil then return nil end
	local rows = host.cl and host.cl.rfsQuestRows or {}
	local page = host.cl and host.cl.rfsQuestPage or 0
	return rows[page * QUEST_ROWS + idx + 1]
end

function RfsSetupGui.setDetail( host, text )
	local gui = host.cl and host.cl.rfsSetupGui
	if gui then
		gui:setText( "QuestDetail", tostring( text or "" ) )
	end
end
