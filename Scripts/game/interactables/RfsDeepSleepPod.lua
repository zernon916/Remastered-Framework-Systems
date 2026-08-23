-- RfsDeepSleepPod.lua — Chemical Regeneration Station (thin interactable shell).
-- All business logic lives in RfsChemStation.lua (FROZEN). Do not edit RfsHackPower.

RfsDeepSleepPod = class( nil )
RfsDeepSleepPod.maxParentCount = 3
RfsDeepSleepPod.maxChildCount = 255
RfsDeepSleepPod.connectionInput = sm.interactable.connectionType.logic + sm.interactable.connectionType.electricity + sm.interactable.connectionType.chemical
RfsDeepSleepPod.connectionOutput = sm.interactable.connectionType.logic
RfsDeepSleepPod.colorNormal = sm.color.new( 0x4aa3c7ff )
RfsDeepSleepPod.colorHighlight = sm.color.new( 0x7ec8e6ff )
RfsDeepSleepPod.connectIcon = "electrical"

local RFS_CG = "$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247"
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
rfsDofile( "Scripts/game/RfsChemStation.lua" )

local function fwd( name )
	return function( self, ... )
		local fn = RfsChemStation and RfsChemStation[name]
		if type( fn ) == "function" then
			return fn( self, ... )
		end
	end
end

RfsDeepSleepPod.server_onCreate = fwd( "server_onCreate" )
RfsDeepSleepPod.server_onDestroy = fwd( "server_onDestroy" )
RfsDeepSleepPod.server_onUnload = fwd( "server_onUnload" )
RfsDeepSleepPod.sv_activateBed = fwd( "sv_activateBed" )
RfsDeepSleepPod.sv_e_rfsSkipDrain = fwd( "sv_e_rfsSkipDrain" )
RfsDeepSleepPod.sv_n_tryEnter = fwd( "sv_n_tryEnter" )
RfsDeepSleepPod.sv_n_tryExit = fwd( "sv_n_tryExit" )
RfsDeepSleepPod.sv_n_forceExit = fwd( "sv_n_forceExit" )
RfsDeepSleepPod.sv_e_rfsRespawnRelease = fwd( "sv_e_rfsRespawnRelease" )
RfsDeepSleepPod.sv_e_rfsHealApplied = fwd( "sv_e_rfsHealApplied" )
RfsDeepSleepPod.server_onFixedUpdate = fwd( "server_onFixedUpdate" )
RfsDeepSleepPod.client_onCreate = fwd( "client_onCreate" )
RfsDeepSleepPod.client_onDestroy = fwd( "client_onDestroy" )
RfsDeepSleepPod.cl_n_lock = fwd( "cl_n_lock" )
RfsDeepSleepPod.client_onFixedUpdate = fwd( "client_onFixedUpdate" )
RfsDeepSleepPod.client_onUpdate = fwd( "client_onUpdate" )
RfsDeepSleepPod.client_onClientDataUpdate = fwd( "client_onClientDataUpdate" )
RfsDeepSleepPod.cl_n_chat = fwd( "cl_n_chat" )
RfsDeepSleepPod.client_onInteract = fwd( "client_onInteract" )
RfsDeepSleepPod.client_onAction = fwd( "client_onAction" )
RfsDeepSleepPod.client_canInteract = fwd( "client_canInteract" )
RfsDeepSleepPod.client_getAvailableParentConnectionCount = fwd( "client_getAvailableParentConnectionCount" )

print( "[RFS] RfsDeepSleepPod loaded (shell -> RfsChemStation)" )
