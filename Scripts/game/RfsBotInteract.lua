-- RfsBotInteract.lua
-- VOLATILE: allied bot E (Commands / Storage) + look-at fallback.
-- Character client_canInteract / client_onInteract (ensureCharHooks) is primary;
-- Game raycast + Player Use is fallback when SM never calls unit/char interact.
-- Paint tool must not be swallowed by bot E.

RfsBotInteract = RfsBotInteract or {}

local LOOK_RANGE = 7
local PAINT_TOOL = "a8f4c2d1-1b39-4bc1-9b50-0f2a6d7e3c91"
-- Legacy parallel Color Painter uuid (removed; keep passthrough if leftover in old saves).
local RFS_COLOR_PAINTER_LEGACY = "f3a91c2e-8b4d-4e71-9c6a-2d5f8e1b0a47"
local AIM_LOOK_RANGE = 7

function RfsBotInteract.holdingPaintTool()
	local item = nil
	pcall( function()
		item = sm.localPlayer.getActiveItem()
	end )
	local s = string.lower( tostring( item or "" ) )
	if s == "" then
		return false
	end
	if string.find( s, PAINT_TOOL, 1, true ) or string.find( s, RFS_COLOR_PAINTER_LEGACY, 1, true ) then
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

local function lookedShape()
	local shape = nil
	pcall( function()
		local hit, result = sm.localPlayer.getLatestRaycast()
		if hit and result and result.type == "body" and type( result.getShape ) == "function" then
			shape = result:getShape()
		end
	end )
	if shape and sm.exists( shape ) then
		return shape
	end
	pcall( function()
		local hit, result = sm.localPlayer.getRaycast( AIM_LOOK_RANGE )
		if not hit or type( result ) ~= "table" then
			return
		end
		if result.type == "body" and type( result.getShape ) == "function" then
			shape = result:getShape()
		elseif result.shape and sm.exists( result.shape ) then
			shape = result.shape
		elseif type( result.getShape ) == "function" then
			shape = result:getShape()
		end
	end )
	if shape and sm.exists( shape ) then
		return shape
	end
	return nil
end

local function shapeToInteractable( shape )
	if not shape or not sm.exists( shape ) then
		return nil
	end
	local ia = nil
	pcall( function()
		ia = shape.interactable or ( type( shape.getInteractable ) == "function" and shape:getInteractable() or nil )
	end )
	if ia and sm.exists( ia ) then
		return ia
	end
	return nil
end

local function isDefaultBearing( shape, interactable )
	if not shape or not interactable then
		return false
	end
	local isBearing = false
	pcall( function()
		local t = interactable:getType()
		isBearing = ( t == "bearing" or t == 1 or tostring( t ) == "bearing" )
	end )
	if not isBearing then
		return false
	end
	if type( RfsAimModes ) ~= "table" or type( RfsAimModes.colorToHex ) ~= "function" or type( RfsAimModes.isDefaultBearing ) ~= "function" then
		return false
	end
	local hex = nil
	pcall( function()
		hex = RfsAimModes.colorToHex( shape:getColor() )
	end )
	return hex and RfsAimModes.isDefaultBearing( hex ) and true or false
end

local function aimCoreHostFromBearing( bearingIa )
	if not bearingIa or not sm.exists( bearingIa ) then
		return nil
	end
	if type( RfsAimLinks ) ~= "table" or type( RfsAimCore ) ~= "table" or type( RfsAimCore.clientHostFor ) ~= "function" then
		return nil
	end
	for _, ia in ipairs( RfsAimLinks.connectedInteractables( bearingIa ) ) do
		if ia and sm.exists( ia ) then
			local key = nil
			local pd = nil
			pcall( function()
				pd = ia:getPublicData()
			end )
			if type( pd ) == "table" and type( pd.aimTurning ) == "table" then
				local host = RfsAimCore.clientHostFor( ia )
				if host then
					return host
				end
			end
		end
	end
	return nil
end

function RfsBotInteract.tryOpenAimTurningFromLook()
	local shape = lookedShape()
	local ia = shapeToInteractable( shape )
	if not ia then
		return false
	end
	if not isDefaultBearing( shape, ia ) then
		return false
	end
	local host = aimCoreHostFromBearing( ia )
	if not host or type( RfsAimTurningGui ) ~= "table" then
		return false
	end
	RfsAimTurningGui.open( host )
	return true
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
			if self.player == sm.localPlayer.getPlayer() and type( RfsBotInteract ) == "table" then
				-- Paint gun owns E → mode cycle via Player.client_onInteract.
				-- Do not cycle here (client_onAction rarely fires; double-step if it does).
				if RfsBotInteract.holdingPaintTool() then
					return true
				elseif RfsBotInteract.tryOpenAimTurningFromLook() then
					return true
				elseif RfsBotInteract.tryOpenFromLook( self ) then
					return true
				end
			end
		end
		if orig then
			return orig( self, action, state )
		end
	end
	Player._rfsBotInteract = true
end

-- Install as soon as Player exists (Custom Game loads Player after these dofiles sometimes).
pcall( function()
	if type( Player ) == "table" then
		RfsBotInteract.ensurePlayerHook()
	end
end )

print( "[RFS] RfsBotInteract loaded (VOLATILE bot E + look fallback; paint E via Interact)" )
