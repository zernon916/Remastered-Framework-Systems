-- RfsGameMode.lua -- WORLD-persisted GenSettings game mode / lock state
-- Author: DemonsDen126

RfsGameMode = RfsGameMode or {}

local STORAGE_KEY = { "rfs", "gameMode" }
local LOCK_WINDOW_SEC = 5 * 60
local MODE_ORDER = { "easy", "normal", "hard" }
local MODE_LABEL = {
	easy = "Easy",
	normal = "Normal",
	hard = "Hard",
}

local function nowSec()
	local ts = 0
	pcall( function()
		ts = os.time and os.time() or 0
	end )
	return math.max( 0, math.floor( tonumber( ts ) or 0 ) )
end

local function normalizeMode( v )
	local mode = tostring( v or "normal" ):lower()
	if mode == "easy" or mode == "normal" or mode == "hard" then
		return mode
	end
	return "normal"
end

local function modeIndex( mode )
	mode = normalizeMode( mode )
	for i, name in ipairs( MODE_ORDER ) do
		if name == mode then
			return i
		end
	end
	return 2
end

local function publishGlobals()
	_G.g_rfsGameMode = RfsGameMode.snapshot()
end

local function readStoredState( data )
	local state = {
		mode = nil,
		hardcore = false,
		selected = false,
		locked = false,
		lockStartedAt = nil,
		lockDeadlineAt = nil,
	}
	local missingMode = true
	if type( data ) == "table" then
		if data.mode ~= nil then
			state.mode = normalizeMode( data.mode )
			missingMode = false
		end
		if data.hardcore ~= nil then
			state.hardcore = data.hardcore and true or false
		end
		if data.selected ~= nil then
			state.selected = data.selected and true or false
		end
		if data.locked ~= nil then
			state.locked = data.locked and true or false
		end
		if data.lockStartedAt ~= nil then
			state.lockStartedAt = math.max( 0, math.floor( tonumber( data.lockStartedAt ) or 0 ) )
		end
		if data.lockDeadlineAt ~= nil then
			state.lockDeadlineAt = math.max( 0, math.floor( tonumber( data.lockDeadlineAt ) or 0 ) )
		end
	end

	local now = nowSec()
	if state.mode == nil then
		state.mode = "normal"
	end
	if state.lockStartedAt == nil then
		state.lockStartedAt = now
	end
	if not state.selected then
		state.lockStartedAt = nil
		state.lockDeadlineAt = nil
	elseif state.lockDeadlineAt == nil then
		state.lockDeadlineAt = state.lockStartedAt + LOCK_WINDOW_SEC
	end
	if state.selected and not state.locked and state.lockDeadlineAt <= now then
		state.locked = true
	end

	return state, missingMode
end

local function getInventory( player )
	if not player then
		return nil
	end
	local inv = nil
	pcall( function()
		inv = player:getInventory()
	end )
	return inv
end

function RfsGameMode.load( force )
	if RfsGameMode.state and not force then
		return RfsGameMode.state, RfsGameMode.needsPrompt == true
	end
	local ok, data = pcall( sm.storage.load, STORAGE_KEY )
	local state, missingMode = readStoredState( ok and data or nil )
	RfsGameMode.state = state
	RfsGameMode.needsPrompt = missingMode == true
	publishGlobals()
	if missingMode and sm.isServerMode then
		RfsGameMode.save()
	end
	return state, missingMode
end

function RfsGameMode.save()
	local state = RfsGameMode.state or RfsGameMode.load()
	local payload = {
		mode = normalizeMode( state.mode ),
		hardcore = state.hardcore == true,
		selected = state.selected == true,
		locked = state.locked == true,
		lockStartedAt = state.selected == true and math.max( 0, math.floor( tonumber( state.lockStartedAt ) or nowSec() ) ) or nil,
		lockDeadlineAt = state.selected == true and math.max( 0, math.floor( tonumber( state.lockDeadlineAt ) or ( nowSec() + LOCK_WINDOW_SEC ) ) ) or nil,
	}
	pcall( sm.storage.save, STORAGE_KEY, payload )
	publishGlobals()
	return state
end

function RfsGameMode.applySnapshot( data )
	if type( data ) ~= "table" then
		return RfsGameMode.snapshot()
	end
	local state = RfsGameMode.state or {}
	if data.mode ~= nil then
		state.mode = normalizeMode( data.mode )
	end
	if data.hardcore ~= nil then
		state.hardcore = data.hardcore and true or false
	end
	if data.locked ~= nil then
		state.locked = data.locked and true or false
	end
	if data.lockStartedAt ~= nil then
		state.lockStartedAt = math.max( 0, math.floor( tonumber( data.lockStartedAt ) or 0 ) )
	end
	if data.lockDeadlineAt ~= nil then
		state.lockDeadlineAt = math.max( 0, math.floor( tonumber( data.lockDeadlineAt ) or 0 ) )
	end
	RfsGameMode.state = state
	publishGlobals()
	return RfsGameMode.snapshot()
end

function RfsGameMode.snapshot()
	local state = RfsGameMode.state or RfsGameMode.load()
	local now = nowSec()
	local locked = state.locked == true
	local deadline = math.max( 0, math.floor( tonumber( state.lockDeadlineAt ) or 0 ) )
	local remaining = 0
	if not locked and deadline > now then
		remaining = deadline - now
	end
	local mode = normalizeMode( state.mode )
	return {
		mode = mode,
		modeLabel = MODE_LABEL[mode] or "Normal",
		hardcore = state.hardcore == true,
		selected = state.selected == true,
		locked = locked,
		lockStartedAt = state.selected == true and math.max( 0, math.floor( tonumber( state.lockStartedAt ) or now ) ) or nil,
		lockDeadlineAt = state.selected == true and ( deadline > 0 and deadline or nil ) or nil,
		lockRemainingSec = state.selected == true and remaining or 0,
		countdownActive = ( state.selected == true and not locked and remaining > 0 ),
	}
end

function RfsGameMode.modeLabel( mode )
	mode = normalizeMode( mode )
	return MODE_LABEL[mode] or "Normal"
end

function RfsGameMode.isLocked()
	return RfsGameMode.snapshot().locked == true
end

function RfsGameMode.isHardcore()
	return RfsGameMode.snapshot().hardcore == true
end

function RfsGameMode.currentMode()
	return RfsGameMode.snapshot().mode
end

function RfsGameMode.countdownText()
	local snap = RfsGameMode.snapshot()
	if snap.locked or not snap.countdownActive then
		return nil
	end
	local sec = tonumber( snap.lockRemainingSec ) or 0
	local mins = math.floor( sec / 60 )
	local rem = sec % 60
	return string.format( "%02d:%02d", mins, rem )
end

function RfsGameMode.playerDamageTakenMultiplier()
	local mode = RfsGameMode.currentMode()
	if mode == "easy" then
		return 2 / 3
	elseif mode == "hard" then
		return 1.5
	end
	return 1
end

function RfsGameMode.playerDamageOutputMultiplier()
	local mode = RfsGameMode.currentMode()
	if mode == "easy" then
		return 2
	elseif mode == "hard" then
		return 0.5
	end
	return 1
end

function RfsGameMode.ensurePromptNeeded()
	local _, missing = RfsGameMode.load()
	local snap = RfsGameMode.snapshot()
	return missing == true or snap.selected ~= true
end

function RfsGameMode.serverTick()
	if not sm.isServerMode then
		return nil
	end
	local state = RfsGameMode.state or RfsGameMode.load()
	if state.selected ~= true or state.locked == true then
		return nil
	end
	local now = nowSec()
	if tonumber( state.lockDeadlineAt ) and now >= math.floor( tonumber( state.lockDeadlineAt ) or 0 ) then
		state.locked = true
		RfsGameMode.save()
		local snap = RfsGameMode.snapshot()
		local label = snap.modeLabel or "Normal"
		if snap.hardcore then
			label = label .. " Hardcore"
		end
		return {
			msg = string.format( "Game Mode locked: %s", label ),
			snapshot = snap,
		}
	end
	return nil
end

function RfsGameMode.cycleMode()
	local state = RfsGameMode.state or RfsGameMode.load()
	if state.locked then
		return RfsGameMode.snapshot(), false
	end
	state.selected = true
	if not state.lockStartedAt then
		local now = nowSec()
		state.lockStartedAt = now
		state.lockDeadlineAt = now + LOCK_WINDOW_SEC
	end
	state.mode = MODE_ORDER[( modeIndex( state.mode ) % #MODE_ORDER ) + 1]
	RfsGameMode.needsPrompt = false
	RfsGameMode.save()
	return RfsGameMode.snapshot(), true
end

function RfsGameMode.setMode( mode )
	local state = RfsGameMode.state or RfsGameMode.load()
	if state.locked then
		return RfsGameMode.snapshot(), false
	end
	state.selected = true
	if not state.lockStartedAt then
		local now = nowSec()
		state.lockStartedAt = now
		state.lockDeadlineAt = now + LOCK_WINDOW_SEC
	end
	state.mode = normalizeMode( mode )
	RfsGameMode.needsPrompt = false
	RfsGameMode.save()
	return RfsGameMode.snapshot(), true
end

function RfsGameMode.toggleHardcore()
	local state = RfsGameMode.state or RfsGameMode.load()
	if state.locked then
		return RfsGameMode.snapshot(), false
	end
	state.selected = true
	if not state.lockStartedAt then
		local now = nowSec()
		state.lockStartedAt = now
		state.lockDeadlineAt = now + LOCK_WINDOW_SEC
	end
	state.hardcore = not ( state.hardcore == true )
	RfsGameMode.needsPrompt = false
	RfsGameMode.save()
	return RfsGameMode.snapshot(), true
end

function RfsGameMode.setHardcore( enabled )
	local state = RfsGameMode.state or RfsGameMode.load()
	if state.locked then
		return RfsGameMode.snapshot(), false
	end
	state.selected = true
	if not state.lockStartedAt then
		local now = nowSec()
		state.lockStartedAt = now
		state.lockDeadlineAt = now + LOCK_WINDOW_SEC
	end
	state.hardcore = enabled and true or false
	RfsGameMode.needsPrompt = false
	RfsGameMode.save()
	return RfsGameMode.snapshot(), true
end

function RfsGameMode.snapshotInventory( player )
	local inv = getInventory( player )
	if not inv then
		return nil
	end
	local size = 0
	pcall( function()
		size = sm.container.getSize( inv ) or inv:getSize() or 0
	end )
	if size <= 0 then
		pcall( function()
			size = inv:getSize() or 0
		end )
	end
	local snapshot = {}
	for slot = 0, math.max( 0, size - 1 ) do
		local item = nil
		pcall( function()
			item = inv:getItem( slot )
		end )
		if type( item ) ~= "table" then
			pcall( function()
				item = sm.container.getItem( inv, slot )
			end )
		end
		if type( item ) == "table" and item.uuid and tonumber( item.quantity ) and tonumber( item.quantity ) > 0 then
			snapshot[#snapshot + 1] = {
				slot = slot,
				uuid = tostring( item.uuid ),
				quantity = math.floor( tonumber( item.quantity ) or 0 ),
				instance = item.instance,
			}
		end
	end
	return snapshot
end

function RfsGameMode.clearInventory( player )
	local inv = getInventory( player )
	if not inv then
		return false
	end
	pcall( function()
		sm.container.beginTransaction()
		inv:clear()
		sm.container.endTransaction()
	end )
	return true
end

function RfsGameMode.restoreInventory( player, snapshot )
	local inv = getInventory( player )
	if not inv then
		return false
	end
	pcall( function()
		sm.container.beginTransaction()
		inv:clear()
		if type( snapshot ) == "table" then
			for _, item in ipairs( snapshot ) do
				local uuid = item.uuid and sm.uuid.new( item.uuid ) or nil
				local qty = math.max( 0, math.floor( tonumber( item.quantity ) or 0 ) )
				if uuid and qty > 0 then
					if item.instance ~= nil then
						inv:setItem( item.slot or 0, uuid, qty, item.instance )
					else
						inv:setItem( item.slot or 0, uuid, qty )
					end
				end
			end
		end
		sm.container.endTransaction()
	end )
	return true
end

function RfsGameMode.applyHardLoadout( player )
	local inv = getInventory( player )
	if not inv then
		return false
	end
	pcall( function()
		sm.container.beginTransaction()
		inv:clear()
		inv:setItem( 0, tool_sledgehammer, 1 )
		inv:setItem( 1, tool_lift, 1 )
		sm.container.endTransaction()
	end )
	return true
end

function RfsGameMode.prepareDeathInventory( player, mode )
	mode = normalizeMode( mode )
	if mode == "easy" then
		local snapshot = RfsGameMode.snapshotInventory( player )
		RfsGameMode.clearInventory( player )
		return { kind = "easy", snapshot = snapshot }
	elseif mode == "hard" then
		RfsGameMode.clearInventory( player )
		return { kind = "hard" }
	end
	return nil
end

function RfsGameMode.processPendingRestore( playerScript )
	if not playerScript or not playerScript.sv then
		return false
	end
	local pending = playerScript.sv.rfsGameModePendingRestore
	if type( pending ) ~= "table" then
		return false
	end
	local player = playerScript.player
	if not player then
		return false
	end
	local char = nil
	pcall( function()
		char = player:getCharacter()
	end )
	if not char or not sm.exists( char ) or char:isDowned() then
		return false
	end
	if pending.kind == "easy" then
		RfsGameMode.restoreInventory( player, pending.snapshot )
	elseif pending.kind == "hard" then
		RfsGameMode.applyHardLoadout( player )
	end
	playerScript.sv.rfsGameModePendingRestore = nil
	pcall( function()
		sm.event.sendToPlayer( player, "cl_rfs_gameModeSpectator", { active = false } )
	end )
	return true
end

function RfsGameMode.enterSpectator( player )
	if not player then
		return false
	end
	local char = nil
	pcall( function()
		char = player:getCharacter()
	end )
	if char and sm.exists( char ) then
		pcall( function() char:setVisible( false ) end )
		pcall( function() char:setImmovable( true ) end )
		pcall( function() char:setDowned( true ) end )
	end
	pcall( function()
		player:setCharacter( nil )
	end )
	pcall( function()
		sm.event.sendToPlayer( player, "cl_rfs_gameModeSpectator", { active = true, msg = "Hardcore: spectator only. /unstuck will not respawn you." } )
	end )
	return true
end

function RfsGameMode.playerNeedsSpectator( player )
	local char = nil
	pcall( function()
		char = player and player:getCharacter()
	end )
	if not char then
		return true
	end
	local ok, downed = pcall( function() return char:isDowned() end )
	return ok and downed == true
end

function RfsGameMode.gameModeSummary()
	local snap = RfsGameMode.snapshot()
	local label = snap.modeLabel or "Normal"
	if snap.hardcore then
		label = label .. " Hardcore"
	end
	if snap.locked then
		return label .. " (LOCKED)"
	end
	if snap.countdownActive then
		local sec = tonumber( snap.lockRemainingSec ) or 0
		return string.format( "%s | locks in %02d:%02d", label, math.floor( sec / 60 ), sec % 60 )
	end
	return label
end
