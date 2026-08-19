-- RfsBotInteract.lua
-- VOLATILE: allied bot E (Commands / Storage) + look-at fallback.
-- Character client_canInteract / client_onInteract (ensureCharHooks) is primary;
-- Game raycast + Player Use is fallback when SM never calls unit/char interact.
-- Paint tool must not be swallowed by bot E.

RfsBotInteract = RfsBotInteract or {}

local LOOK_RANGE = 7
local PAINT_TOOL = "c60b9627-fc2b-4319-97c5-05921cb976c6"
local PAINT_OBJ = "731c6a84-7ae7-439d-a620-128076f9985c"

function RfsBotInteract.holdingPaintTool()
	local item = nil
	pcall( function()
		item = sm.localPlayer.getActiveItem()
	end )
	local s = string.lower( tostring( item or "" ) )
	if s == "" then
		return false
	end
	if string.find( s, PAINT_TOOL, 1, true ) or string.find( s, PAINT_OBJ, 1, true ) then
		return true
	end
	return false
end

local function vecFromPublic( char )
	if not char then
		return false, nil
	end
	local flagged = false
	local blob = nil
	pcall( function()
		local pd = char.publicData
		if type( pd ) == "table" then
			if pd.rfsPlayerAlly then
				flagged = true
			end
			if type( pd.rfsAllyInfo ) == "table" then
				blob = pd.rfsAllyInfo
			end
		end
	end )
	return flagged, blob
end

function RfsBotInteract.isAllyCharacter( char )
	local ok = vecFromPublic( char )
	return ok and true or false
end

local function titleForChar( char, blob )
	if blob and blob.customName and tostring( blob.customName ) ~= "" then
		return tostring( blob.customName )
	end
	if blob and blob.displayName and tostring( blob.displayName ) ~= "" then
		return tostring( blob.displayName )
	end
	return "BOT"
end

function RfsBotInteract.tryOpen( host, char, charScript )
	if RfsBotInteract.holdingPaintTool() then
		return false
	end
	if not char or not RfsBotInteract.isAllyCharacter( char ) then
		return false
	end
	local _, blob = vecFromPublic( char )
	local unitKey = nil
	local title = titleForChar( char, blob )
	pcall( function()
		local u = char:getUnit()
		unitKey = u and tostring( u.id ) or nil
	end )
	local game = host or _G.g_rfsGame
	if game and type( game.cl_rfs_botActionOpen ) == "function" then
		local ok = pcall( function()
			game:cl_rfs_botActionOpen( {
				unitKey = unitKey,
				title = title,
				charScript = charScript,
			} )
		end )
		if ok then
			return true
		end
	end
	if charScript and charScript.network then
		pcall( function()
			charScript.network:sendToServer( "sv_e_rfsBotAction", {
				unitKey = unitKey,
				title = title,
				player = sm.localPlayer.getPlayer(),
			} )
		end )
		return true
	end
	return false
end

function RfsBotInteract.raycastAllyChar()
	local hit, result = false, nil
	pcall( function()
		hit, result = sm.localPlayer.getRaycast( LOOK_RANGE )
	end )
	if not hit or type( result ) ~= "table" then
		return nil
	end
	if result.type ~= "Character" or not result.character then
		return nil
	end
	local char = result.character
	if not RfsBotInteract.isAllyCharacter( char ) then
		return nil
	end
	return char
end

function RfsBotInteract.clientTick( host )
	host = host or _G.g_rfsGame
	if not host or not host.cl then
		return
	end
	if host.cl.rfsBotActionGui then
		host.cl.rfsBotLookChar = nil
		return
	end
	if RfsBotInteract.holdingPaintTool() then
		host.cl.rfsBotLookChar = nil
		return
	end
	local char = RfsBotInteract.raycastAllyChar()
	host.cl.rfsBotLookChar = char
	if char then
		local _, blob = vecFromPublic( char )
		pcall( function()
			sm.gui.setInteractionText(
				"",
				sm.gui.getKeyBinding( "Use", true ),
				"Commands / Storage — " .. titleForChar( char, blob )
			)
		end )
	end
end

function RfsBotInteract.tryOpenFromLook( playerScript )
	if RfsBotInteract.holdingPaintTool() then
		return false
	end
	local char = RfsBotInteract.raycastAllyChar()
	if not char then
		char = playerScript and playerScript.cl and playerScript.cl.rfsBotLookChar
	end
	if not char then
		return false
	end
	return RfsBotInteract.tryOpen( _G.g_rfsGame, char, nil )
end

function RfsBotInteract.ensurePlayerHook()
	if type( Player ) ~= "table" or Player._rfsBotInteract then
		return
	end
	local orig = Player.client_onAction
	function Player.client_onAction( self, action, state )
		if state and action == sm.interactable.actions.use then
			if self.player == sm.localPlayer.getPlayer()
				and type( RfsBotInteract ) == "table"
				and not RfsBotInteract.holdingPaintTool()
				and RfsBotInteract.tryOpenFromLook( self ) then
				return true
			end
		end
		if orig then
			return orig( self, action, state )
		end
	end
	Player._rfsBotInteract = true
end

print( "[RFS] RfsBotInteract loaded (VOLATILE bot E + look fallback; paint tool passthrough)" )
