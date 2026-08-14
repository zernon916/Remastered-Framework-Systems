-- RfsGenGui.lua — /gensettings host-only world feature flags GUI
-- Author: DemonsDen126

RfsGenGui = RfsGenGui or {}

local LAYOUT = "$CONTENT_DATA/Gui/Layouts/Rfs_GenSettings.layout"

local function onOff( v )
	return v and "ON" or "OFF"
end

function RfsGenGui.refresh( host )
	local gui = host.cl and host.cl.rfsGenGui
	if not gui then return end

	local snap = ( type( RfsFeatures ) == "table" and RfsFeatures.snapshot and RfsFeatures.snapshot() ) or {}
	local cheats = snap.cheats == true
	local hackDev = snap.hackDevices ~= false
	local area = snap.areaLoader ~= false
	local robots = snap.hackableRobots ~= false
	local streamer = snap.streamerMode ~= false
	local cooldown = tonumber( snap.streamerCooldownSec ) or 10
	local announce = snap.streamerAnnounce ~= false
	local chatRelay = snap.streamerChatRelay == true
	local quests = snap.rfsQuests ~= false

	gui:setText( "BtnCheats", "Cheats: " .. onOff( cheats ) )
	gui:setText( "BtnHackDevices", "Hack devices (beacons): " .. onOff( hackDev ) )
	gui:setText( "BtnAreaLoader", "Anchor / Area loader: " .. onOff( area ) )
	gui:setText( "BtnHackableRobots", "Hackable robots: " .. onOff( robots ) )
	gui:setText( "BtnRfsQuests", "RFS quests content: " .. onOff( quests ) )
	gui:setText( "BtnStreamerMode", "Streamer mode: " .. onOff( streamer ) )
	gui:setText( "BtnStreamerCooldown", "Vote cooldown: " .. tostring( cooldown ) .. "s" )
	gui:setText( "BtnStreamerAnnounce", "Vote announce: " .. onOff( announce ) )
	gui:setText( "BtnStreamerChatRelay", "Discord chat relay: " .. onOff( chatRelay ) )

	pcall( function()
		gui:setButtonState( "BtnCheats", cheats )
		gui:setButtonState( "BtnHackDevices", hackDev )
		gui:setButtonState( "BtnAreaLoader", area )
		gui:setButtonState( "BtnHackableRobots", robots )
		gui:setButtonState( "BtnRfsQuests", quests )
		gui:setButtonState( "BtnStreamerMode", streamer )
		gui:setButtonState( "BtnStreamerAnnounce", announce )
		gui:setButtonState( "BtnStreamerChatRelay", chatRelay )
	end )

	local fw = ( type( RfsSettings ) == "table" and RfsSettings.frameworkOnly and RfsSettings.frameworkOnly() )
	if fw then
		gui:setText( "Status", "frameworkOnly=true — cheats + RFS quest UI forced OFF (hooks stay on)" )
	else
		gui:setText( "Status", string.format(
			"World flags | cheats=%s | beacons=%s | loader=%s | robots=%s | streamer=%s/%ss | announce=%s | chat=%s | questsUI=%s",
			onOff( cheats ), onOff( hackDev ), onOff( area ), onOff( robots ),
			onOff( streamer ), tostring( cooldown ), onOff( announce ), onOff( chatRelay ), onOff( quests )
		) )
	end
end

function RfsGenGui.bind( host, gui )
	host.cl = host.cl or {}
	host.cl.rfsGenGui = gui

	gui:setButtonCallback( "CloseButton", "cl_rfs_genClose" )
	gui:setButtonCallback( "BtnCheats", "cl_rfs_genToggleCheats" )
	gui:setButtonCallback( "BtnHackDevices", "cl_rfs_genToggleHackDevices" )
	gui:setButtonCallback( "BtnAreaLoader", "cl_rfs_genToggleAreaLoader" )
	gui:setButtonCallback( "BtnHackableRobots", "cl_rfs_genToggleHackableRobots" )
	gui:setButtonCallback( "BtnRfsQuests", "cl_rfs_genToggleRfsQuests" )
	gui:setButtonCallback( "BtnStreamerMode", "cl_rfs_genToggleStreamerMode" )
	gui:setButtonCallback( "BtnStreamerCooldown", "cl_rfs_genCycleStreamerCooldown" )
	gui:setButtonCallback( "BtnStreamerAnnounce", "cl_rfs_genToggleStreamerAnnounce" )
	gui:setButtonCallback( "BtnStreamerChatRelay", "cl_rfs_genToggleStreamerChatRelay" )
	gui:setOnCloseCallback( "cl_rfs_genClose" )
end

function RfsGenGui.open( host )
	local okHost, isHost = pcall( function() return sm.isHost end )
	if not ( okHost and isHost ) then
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
	RfsGenGui.refresh( host )
	gui:open()
	host.network:sendToServer( "sv_rfs_featuresGet" )
	sm.gui.chatMessage( "RFS Gen Settings opened" )
end

function RfsGenGui.close( host )
	local gui = host.cl and host.cl.rfsGenGui
	if gui then
		pcall( function() gui:close() end )
	end
	if host.cl then
		host.cl.rfsGenGui = nil
	end
end
