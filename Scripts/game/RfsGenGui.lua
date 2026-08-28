-- RfsGenGui.lua — /gensettings host-only world feature flags GUI (tabbed)
-- Author: DemonsDen126

RfsGenGui = RfsGenGui or {}

local LAYOUT = "$CONTENT_DATA/Gui/Layouts/Rfs_GenSettings.layout"

local function onOff( v )
	return v and "ON" or "OFF"
end

local function allowlistCycleLabel( host )
	local info = host.cl and host.cl.rfsAllowlistInfo
	local names = info and info.unitNames
	if type( names ) ~= "table" or #names == 0 then
		return "Unit: (none)"
	end
	local idx = tonumber( host.cl.rfsAllowlistCycleIdx ) or 1
	if idx < 1 or idx > #names then
		idx = 1
		host.cl.rfsAllowlistCycleIdx = 1
	end
	return string.format( "Unit: %s (%d/%d)", tostring( names[idx] ), idx, #names )
end

local function allowlistSummaryText( host )
	local info = host.cl and host.cl.rfsAllowlistInfo
	if type( info ) ~= "table" then
		return "Allowlist: Units: — | Items: — (loading…)"
	end
	local src = info.source == "builtin" and "builtin" or "file"
	return string.format(
		"Allowlist: Units: %d | Items: %d (%s)",
		tonumber( info.unitCount ) or 0,
		tonumber( info.itemCount ) or 0,
		src
	)
end

local GAME_MODE_HINTS = {
	easy = "Easy: -33% damage taken, x2 damage output, keep inventory.",
	normal = "Normal: stock Survival.",
	hard = "Hard: +50% damage taken, -50% damage output, no bag, hammer + lift only.",
}

local function gameModeHintText( gm )
	local mode = gm and gm.mode or "normal"
	return GAME_MODE_HINTS[mode] or GAME_MODE_HINTS.normal
end

local function gameModeStrings()
	local gm = ( type( RfsGameMode ) == "table" and RfsGameMode.snapshot and RfsGameMode.snapshot() ) or {}
	local label = tostring( gm.modeLabel or "Normal" )
	if gm.hardcore then
		label = label .. " Hardcore"
	end
	if gm.locked then
		label = label .. " (LOCKED)"
	end
	local prefix = gm.selected == true and "Game Mode: " or "Select Mode: "
	local status = "Click the mode button to cycle Easy -> Normal -> Hard. The first pick starts the 5-minute lock."
	if gm.selected == true and gm.locked then
		status = "Game Mode is LOCKED"
	elseif gm.selected == true and gm.countdownActive then
		local sec = math.max( 0, math.floor( tonumber( gm.lockRemainingSec ) or 0 ) )
		status = string.format( "Locking in %02d:%02d", math.floor( sec / 60 ), sec % 60 )
	end
	return gm, prefix .. label, status
end

local function refreshStatus( gui, snap )
	local cheats = snap.cheats == true
	local hackDev = snap.hackDevices ~= false
	local area = snap.areaLoader ~= false
	local robots = snap.hackableRobots ~= false
	local underground = snap.hackUndergroundBots ~= false
	local streamer = snap.streamerMode ~= false
	local cooldown = tonumber( snap.streamerCooldownSec ) or 10
	local announce = snap.streamerAnnounce ~= false
	local chatRelay = snap.streamerChatRelay == true
	local quests = snap.rfsQuests ~= false

	local fw = ( type( RfsSettings ) == "table" and RfsSettings.frameworkOnly and RfsSettings.frameworkOnly() )
	if fw then
		gui:setText( "Status", "frameworkOnly=true — cheats + RFS quest UI forced OFF (hooks stay on)" )
	else
		gui:setText( "Status", string.format(
			"World flags | cheats=%s | beacons=%s | loader=%s | robots=%s | ug=%s | streamer=%s/%ss | announce=%s | chat=%s | questsUI=%s",
			onOff( cheats ), onOff( hackDev ), onOff( area ), onOff( robots ), onOff( underground ),
			onOff( streamer ), tostring( cooldown ), onOff( announce ), onOff( chatRelay ), onOff( quests )
		) )
	end
end

function RfsGenGui.refresh( host )
	local gui = host.cl and host.cl.rfsGenGui
	if not gui then return end

	local snap = ( type( RfsFeatures ) == "table" and RfsFeatures.snapshot and RfsFeatures.snapshot() ) or {}
	local cheats = snap.cheats == true
	local hackDev = snap.hackDevices ~= false
	local area = snap.areaLoader ~= false
	local robots = snap.hackableRobots ~= false
	local underground = snap.hackUndergroundBots ~= false
	local streamer = snap.streamerMode ~= false
	local cooldown = tonumber( snap.streamerCooldownSec ) or 10
	local announce = snap.streamerAnnounce ~= false
	local chatRelay = snap.streamerChatRelay == true
	local quests = snap.rfsQuests ~= false
	local pvp = snap.pvp == true

	local gm, gmLabel, gmStatus = gameModeStrings()
	local tab = host.cl and host.cl.rfsGenTab or "main"

	gui:setText( "BtnCheats", "Cheats: " .. onOff( cheats ) )
	gui:setText( "BtnHackDevices", "Hack devices (beacons): " .. onOff( hackDev ) )
	gui:setText( "BtnAreaLoader", "Anchor / Area loader: " .. onOff( area ) )
	gui:setText( "BtnHackableRobots", "Hackable robots: " .. onOff( robots ) )
	gui:setText( "BtnHackUnderground", "Underground miner/cable: " .. onOff( underground ) )
	gui:setText( "BtnRfsQuests", "RFS quests content: " .. onOff( quests ) )
	gui:setText( "BtnPvp", "PVP: " .. onOff( pvp ) )
	gui:setText( "BtnStreamerMode", "Streamer mode: " .. onOff( streamer ) )
	gui:setText( "BtnStreamerCooldown", "Vote cooldown: " .. tostring( cooldown ) .. "s" )
	gui:setText( "BtnStreamerAnnounce", "Vote announce: " .. onOff( announce ) )
	gui:setText( "BtnStreamerChatRelay", "Discord chat relay: " .. onOff( chatRelay ) )
	gui:setText( "TextAllowlistSummary", allowlistSummaryText( host ) )
	gui:setText( "BtnStreamerAllowlistReload", "Reload allowlist" )
	gui:setText( "BtnStreamerAllowlistCycle", allowlistCycleLabel( host ) )
	gui:setText(
		"TextDiscordStatus",
		"DROP: $USER_DATA/rfs_discord_bridge/ — bot on host PC only. Clone discord-bridge from github.com/zernon916/Recipe-Framework-Systems and run npm run watch"
	)
	gui:setText( "BtnGameMode", gmLabel )
	gui:setText( "BtnGameHardcore", "Hardcore: " .. onOff( gm.hardcore == true ) )
	gui:setText( "TextGameModeStatus", gmStatus )
	gui:setText( "GameModeHint", gameModeHintText( gm ) )
	gui:setText( "BtnDiscordStartBot", "Start Discord bot" )
	gui:setText( "BtnDiscordStopBot", "Stop Discord bot" )

	pcall( function()
		gui:setButtonState( "BtnCheats", cheats )
		gui:setButtonState( "BtnHackDevices", hackDev )
		gui:setButtonState( "BtnAreaLoader", area )
		gui:setButtonState( "BtnHackableRobots", robots )
		gui:setButtonState( "BtnHackUnderground", underground )
		gui:setButtonState( "BtnRfsQuests", quests )
		gui:setButtonState( "BtnPvp", pvp )
		gui:setButtonState( "BtnStreamerMode", streamer )
		gui:setButtonState( "BtnStreamerAnnounce", announce )
		gui:setButtonState( "BtnStreamerChatRelay", chatRelay )
		gui:setButtonState( "BtnGameMode", gm.selected == true )
		gui:setButtonState( "BtnGameHardcore", gm.hardcore == true )
	end )

	refreshStatus( gui, snap )

	if tab == "quest" and type( RfsSetupGui ) == "table" then
		RfsSetupGui.refreshQuest( host )
	elseif tab == "invsize" and type( RfsSetupGui ) == "table" then
		RfsSetupGui.refreshInvSize( host )
	elseif tab == "farming" and type( RfsSetupGui ) == "table" then
		RfsSetupGui.refreshFarming( host )
	end
end

function RfsGenGui.showTab( host, tab )
	local gui = host.cl and host.cl.rfsGenGui
	if not gui then return end

	tab = tab or "main"
	host.cl.rfsGenTab = tab
	host.cl.rfsSetupTab = tab
	local t = host.cl.rfsGenTab
	local main = t == "main"
	local gamemode = t == "gamemode"
	local features = t == "features"
	local streamer = t == "streamer"
	local discord = t == "discord"
	local quest = t == "quest"
	local inv = t == "invsize"
	local farm = t == "farming"

	gui:setVisible( "MainTab", main )
	gui:setVisible( "GameModeTab", gamemode )
	gui:setVisible( "FeaturesTab", features )
	gui:setVisible( "StreamerTab", streamer )
	gui:setVisible( "DiscordTab", discord )
	gui:setVisible( "QuestTab", quest )
	gui:setVisible( "InvSizeTab", inv )
	gui:setVisible( "FarmingTab", farm )
	pcall( function()
		gui:setButtonState( "TabMain", main )
		gui:setButtonState( "TabGameMode", gamemode )
		gui:setButtonState( "TabFeatures", features )
		gui:setButtonState( "TabStreamer", streamer )
		gui:setButtonState( "TabDiscord", discord )
		gui:setButtonState( "TabQuest", quest )
		gui:setButtonState( "TabInvSize", inv )
		gui:setButtonState( "TabFarming", farm )
	end )

	if quest or inv or farm then
		if quest then
			if type( RfsSetupGui ) == "table" then
				RfsSetupGui.refreshQuest( host )
			end
			host.network:sendToServer( "sv_rfs_setupQuestData" )
		elseif inv then
			host.network:sendToServer( "sv_rfs_invSizeGet" )
			if type( RfsSetupGui ) == "table" then
				RfsSetupGui.refreshInvSize( host )
			end
		elseif farm then
			host.network:sendToServer( "sv_rfs_farmingGet" )
			if type( RfsSetupGui ) == "table" then
				RfsSetupGui.refreshFarming( host )
			end
		end
	end

	RfsGenGui.refresh( host )

	if gamemode then
		host.network:sendToServer( "sv_rfs_gameModeGet" )
	end
	if streamer then
		host.network:sendToServer( "sv_rfs_allowlistGet" )
	end
end

function RfsGenGui.bind( host, gui )
	host.cl = host.cl or {}
	host.cl.rfsGenGui = gui
	host.cl.rfsSetupGui = gui
	host.cl.rfsGenTab = host.cl.rfsGenTab or "main"
	host.cl.rfsSetupTab = host.cl.rfsSetupTab or host.cl.rfsGenTab

	gui:setButtonCallback( "CloseButton", "cl_rfs_genClose" )
	gui:setButtonCallback( "TabMain", "cl_rfs_genTabMain" )
	gui:setButtonCallback( "TabGameMode", "cl_rfs_genTabGameMode" )
	gui:setButtonCallback( "TabFeatures", "cl_rfs_genTabFeatures" )
	gui:setButtonCallback( "TabStreamer", "cl_rfs_genTabStreamer" )
	gui:setButtonCallback( "TabDiscord", "cl_rfs_genTabDiscord" )
	gui:setButtonCallback( "TabQuest", "cl_rfs_setupTabQuest" )
	gui:setButtonCallback( "TabInvSize", "cl_rfs_setupTabInvSize" )
	gui:setButtonCallback( "TabFarming", "cl_rfs_setupTabFarming" )
	gui:setButtonCallback( "BtnCheats", "cl_rfs_genToggleCheats" )
	gui:setButtonCallback( "BtnHackDevices", "cl_rfs_genToggleHackDevices" )
	gui:setButtonCallback( "BtnAreaLoader", "cl_rfs_genToggleAreaLoader" )
	gui:setButtonCallback( "BtnHackableRobots", "cl_rfs_genToggleHackableRobots" )
	gui:setButtonCallback( "BtnHackUnderground", "cl_rfs_genToggleHackUnderground" )
	gui:setButtonCallback( "BtnRfsQuests", "cl_rfs_genToggleRfsQuests" )
	gui:setButtonCallback( "BtnPvp", "cl_rfs_genTogglePvp" )
	gui:setButtonCallback( "BtnStreamerMode", "cl_rfs_genToggleStreamerMode" )
	gui:setButtonCallback( "BtnStreamerCooldown", "cl_rfs_genCycleStreamerCooldown" )
	gui:setButtonCallback( "BtnStreamerAnnounce", "cl_rfs_genToggleStreamerAnnounce" )
	gui:setButtonCallback( "BtnStreamerChatRelay", "cl_rfs_genToggleStreamerChatRelay" )
	gui:setButtonCallback( "BtnStreamerAllowlistReload", "cl_rfs_genReloadAllowlist" )
	gui:setButtonCallback( "BtnStreamerAllowlistCycle", "cl_rfs_genCycleAllowlistUnit" )
	gui:setButtonCallback( "BtnGameMode", "cl_rfs_genCycleGameMode" )
	gui:setButtonCallback( "BtnGameHardcore", "cl_rfs_genToggleGameHardcore" )
	gui:setButtonCallback( "BtnDiscordStartBot", "cl_rfs_genDiscordStartBot" )
	gui:setButtonCallback( "BtnDiscordStopBot", "cl_rfs_genDiscordStopBot" )
	gui:setButtonCallback( "QuestRefresh", "cl_rfs_setupQuestRefresh" )
	gui:setButtonCallback( "QuestPrev", "cl_rfs_setupQuestPrev" )
	gui:setButtonCallback( "QuestNext", "cl_rfs_setupQuestNext" )
	for i = 0, 5 do
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
	gui:setOnCloseCallback( "cl_rfs_genClose" )
end

function RfsGenGui.open( host, tab )
	local isHost = false
	if type( _G.rfsClientIsHost ) == "function" then
		isHost = _G.rfsClientIsHost() and true or false
	else
		local okHost, v = pcall( function()
			if type( sm.isHost ) == "function" then
				return sm.isHost()
			end
			return sm.isHost
		end )
		isHost = okHost and v and true or false
	end
	if not isHost then
		sm.gui.chatMessage( "[RFS] /gensettings is host-only." )
		return
	end

	if host.cl and host.cl.rfsGenGui then
		pcall( function() host.cl.rfsGenGui:close() end )
		host.cl.rfsGenGui = nil
	end

	local ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT )
	if not ok or not gui then
		sm.gui.chatMessage( "[RFS] Failed to open /gensettings GUI" )
		print( "[RFS] gen GUI create failed: " .. tostring( gui ) )
		return
	end

	RfsGenGui.bind( host, gui )
	local snap = ( type( RfsGameMode ) == "table" and RfsGameMode.snapshot and RfsGameMode.snapshot() ) or {}
	local startTab = tab or host.cl.rfsGenTab or ( snap.selected ~= true and "gamemode" or "main" )
	RfsGenGui.showTab( host, startTab )
	gui:open()
	host.network:sendToServer( "sv_rfs_featuresGet" )
	host.network:sendToServer( "sv_rfs_allowlistGet" )
end

function RfsGenGui.close( host )
	local gui = host.cl and host.cl.rfsGenGui
	if gui then
		pcall( function() gui:close() end )
	end
	if host.cl then
		host.cl.rfsGenGui = nil
		host.cl.rfsSetupGui = nil
		host.cl.rfsSetupTab = nil
		host.cl.rfsGenTab = nil
	end
end
