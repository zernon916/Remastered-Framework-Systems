-- RfsMenuGui.lua — /menu player GUI for Recipe Framework Survival
-- Author: DemonsDen126
-- Style skins match Recipe Radar / Rfs_Setup (BackgroundInteractableWide, PrimaryButton).

RfsMenuGui = RfsMenuGui or {}

local LAYOUT = "$CONTENT_DATA/Gui/Layouts/Rfs_Menu.layout"

local function growthOn( host )
	if host and host.cl and host.cl.rfsGrowthOverlay ~= nil then
		return host.cl.rfsGrowthOverlay and true or false
	end
	return _G.g_rfsGrowthOverlay == true
end

local function guiPrefs( host )
	if host and host.cl and type( host.cl.rfsGuiPrefs ) == "table" then
		return host.cl.rfsGuiPrefs
	end
	if type( RfsGuiPrefs ) == "table" and RfsGuiPrefs.client then
		return RfsGuiPrefs.client()
	end
	return { names = true, bigRed = false, enemyHp = "red", neutralHp = "green" }
end

local function titleCase( s )
	s = tostring( s or "" )
	if s == "" then
		return s
	end
	return string.upper( string.sub( s, 1, 1 ) ) .. string.sub( s, 2 )
end

local function cheatsOn( host )
	local cheats = RfsSettings.cheatsEnabled()
	if host and host.cl and host.cl.rfsMenuCheats ~= nil then
		return host.cl.rfsMenuCheats and true or false
	end
	return cheats
end

function RfsMenuGui.refreshCheats( host )
	local gui = host.cl and host.cl.rfsMenuGui
	if not gui then return end

	local invLimited = limitedOn()
	local fly = flyOn()
	local god = godOn()

	gui:setText( "BtnInventory", "Inventory: " .. ( invLimited and "Limited" or "Unlimited" ) )
	gui:setText( "BtnFly", "Fly: " .. ( fly and "ON" or "OFF" ) )
	gui:setText( "BtnGod", "God: " .. ( god and "ON" or "OFF" ) )

	pcall( function()
		gui:setButtonState( "BtnInventory", invLimited )
		gui:setButtonState( "BtnFly", fly )
		gui:setButtonState( "BtnGod", god )
	end )

	gui:setText( "CheatsStatus", "Inventory | Fly | God" )
	gui:setText( "CheatsFooter", "Also: /fly /god /limited /unlimited" )
end

function RfsMenuGui.refresh( host )
	local gui = host.cl and host.cl.rfsMenuGui
	if not gui then return end

	local tab = host.cl and host.cl.rfsMenuTab or "main"
	local main = tab ~= "cheats"
	local cheats = tab == "cheats"

	pcall( function()
		gui:setVisible( "MainTab", main )
		gui:setVisible( "CheatsTab", cheats )
	end )
	pcall( function()
		gui:setButtonState( "TabMain", main )
		gui:setButtonState( "TabCheats", cheats )
	end )

	local overlay = growthOn( host )
	-- Growth Time HUD retired — hide button (Farmers Tablet replaces it).
	pcall( function()
		gui:setVisible( "BtnGrowthOverlay", false )
	end )
	pcall( function()
		gui:setText( "BtnGrowthOverlay", "Growth Time: OFF" )
		gui:setButtonState( "BtnGrowthOverlay", false )
	end )

	local prefs = guiPrefs( host )
	local names = prefs.names ~= false
	local bigRed = prefs.bigRed and true or false
	pcall( function()
		gui:setText( "BtnNames", "Names: " .. ( names and "ON" or "OFF" ) )
		gui:setButtonState( "BtnNames", names )
		gui:setText( "BtnBigRed", "Big Red: " .. ( bigRed and "ON" or "OFF" ) )
		gui:setButtonState( "BtnBigRed", bigRed )
		gui:setText( "BtnEnemyHp", "Enemy bar: " .. titleCase( prefs.enemyHp ) )
		gui:setText( "BtnNeutralHp", "Neutral bar: " .. titleCase( prefs.neutralHp ) )
	end )

	if cheats then
		RfsMenuGui.refreshCheats( host )
	else
		gui:setText( "MainStatus", "Per-player options -- available to everyone" )
		gui:setText( "MenuHint", string.format(
			"Map: /map atlas (Nutt) or camera fallback. Farm times: Farmers Tablet. Names: world tags on/off. Big Red: farmbots show Big Red instead of Farm. Enemy/Neutral colors tint RFS tags."
		) )
	end
end

function RfsMenuGui.showTab( host, tab )
	local gui = host.cl and host.cl.rfsMenuGui
	if not gui then return end

	host.cl.rfsMenuTab = ( tab == "cheats" ) and "cheats" or "main"
	RfsMenuGui.refresh( host )
end

function RfsMenuGui.bind( host, gui )
	host.cl = host.cl or {}
	host.cl.rfsMenuGui = gui
	host.cl.rfsMenuTab = host.cl.rfsMenuTab or "main"

	gui:setButtonCallback( "CloseButton", "cl_rfs_menuClose" )
	gui:setButtonCallback( "TabMain", "cl_rfs_menuTabMain" )
	gui:setButtonCallback( "TabCheats", "cl_rfs_menuTabCheats" )
	gui:setButtonCallback( "BtnMap", "cl_rfs_menuMap" )
	gui:setButtonCallback( "BtnGrowthOverlay", "cl_rfs_menuToggleGrowthOverlay" )
	gui:setButtonCallback( "BtnNames", "cl_rfs_menuToggleNames" )
	gui:setButtonCallback( "BtnBigRed", "cl_rfs_menuToggleBigRed" )
	gui:setButtonCallback( "BtnEnemyHp", "cl_rfs_menuCycleEnemyHp" )
	gui:setButtonCallback( "BtnNeutralHp", "cl_rfs_menuCycleNeutralHp" )
	gui:setOnCloseCallback( "cl_rfs_menuClose" )
end

function RfsMenuGui.open( host, tab )
	if host.cl and host.cl.rfsMenuGui then
		pcall( function() host.cl.rfsMenuGui:close() end )
		host.cl.rfsMenuGui = nil
	end

	local ok, gui = pcall( sm.gui.createGuiFromLayout, LAYOUT )
	if not ok or not gui then
		sm.gui.chatMessage( "[RFS] Failed to open /menu GUI" )
		print( "[RFS] menu GUI create failed: " .. tostring( gui ) )
		return
	end

	RfsMenuGui.bind( host, gui )
	RfsMenuGui.showTab( host, tab or host.cl and host.cl.rfsMenuTab or "main" )
	RfsMenuGui.refresh( host )
	gui:open()
end

function RfsMenuGui.close( host )
	local gui = host.cl and host.cl.rfsMenuGui
	if gui then
		pcall( function() gui:close() end )
	end
	if host.cl then
		host.cl.rfsMenuGui = nil
		host.cl.rfsMenuTab = nil
	end
end
