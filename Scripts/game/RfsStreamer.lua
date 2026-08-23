-- RfsStreamer.lua — poll Discord bridge vote inbox; spawn/give when Streamer mode is on.
-- Lua cannot HTTP. External Node bot writes a local JSON file the host polls.
-- Phase B: host-only, allowlist, clamp, cooldown, consume vote file, safe pcall.
-- Phase C: after apply/permanent reject, write vote_result.json for Discord announce.
-- Author: DemonsDen126

RfsStreamer = RfsStreamer or {}

local RFS_LOCAL_ID = "29c99287-1213-48c7-9471-19a4a5c12247"
local POLL_INTERVAL = 0.5 -- seconds (only while an inbox file is readable)
local ABSENT_POLL_SEC = 120 -- missing vote.json: do not sm.json.open again for this long
local DEFAULT_COOLDOWN_SEC = 10
-- Soft bounds when RfsFeatures is missing; live values come from RfsFeatures.streamerCooldownSec().
local MIN_COOLDOWN_SEC = 0
local MAX_COOLDOWN_SEC = 300
local MIN_AMOUNT = 1
local MAX_AMOUNT = 20
-- Missing/unreadable bridge paths spam DirectoryManager if probed every poll; back off per path.
local OPEN_BACKOFF_MIN = 5
local OPEN_BACKOFF_MAX = 30

-- Prefer writable USER_DATA (Workshop content is often read-only). CONTENT paths work for local C:\sm\RFS.
local VOTE_PATHS = {
	"$TEMP_DATA/rfs_discord_bridge/vote.json",
	"$CONTENT_DATA/discord-bridge/inbox/vote.json",
	"$CONTENT_" .. RFS_LOCAL_ID .. "/discord-bridge/inbox/vote.json",
}

-- Phase C: resolve feedback for the Node bot (same bridge roots as votes).
local RESULT_PATHS = {
	"$TEMP_DATA/rfs_discord_bridge/vote_result.json",
	"$CONTENT_DATA/discord-bridge/inbox/vote_result.json",
	"$CONTENT_" .. RFS_LOCAL_ID .. "/discord-bridge/inbox/vote_result.json",
}

-- World override first, then pack config.
local ALLOWLIST_PATHS = {
	"$TEMP_DATA/rfs_discord_bridge/allowlist.json",
	"$CONTENT_DATA/discord-bridge/config/allowlist.json",
	"$CONTENT_" .. RFS_LOCAL_ID .. "/discord-bridge/config/allowlist.json",
}

-- Survival unit_* globals when present; farmbot UUID matches RfsBotHijack fallback.
local UNIT_ALIAS = {
	woc = "unit_woc",
	tapebot = "unit_tapebot",
	tb = "unit_tapebot",
	redtapebot = "unit_tapebot_red",
	rtb = "unit_tapebot_red",
	totebot = "unit_totebot_green",
	green = "unit_totebot_green",
	t = "unit_totebot_green",
	totered = "unit_totebot_red",
	red = "unit_totebot_red",
	tr = "unit_totebot_red",
	haybot = "unit_haybot",
	h = "unit_haybot",
	worm = "unit_worm",
	farmbot = "unit_farmbot",
	f = "unit_farmbot",
}

local FARMBOT_FALLBACK = sm.uuid.new( "9f4fde94-312f-4417-b13b-84029c5d6b52" )

-- Built-in defaults when allowlist.json is missing (mirrors discord-bridge/config/allowlist.json).
local DEFAULT_UNITS = {
	farmbot = true, f = true,
	haybot = true, h = true,
	totebot = true, green = true, t = true,
	totered = true, red = true, tr = true,
	tapebot = true, tb = true,
	redtapebot = true, rtb = true,
	woc = true, worm = true,
}

local DEFAULT_ITEMS = {
	farmers = "8d601982-4608-4d5e-bb9e-e4041486f7c7",
	battery = "910a7f2c-52b0-46eb-8873-ad13255539af",
	corn = "fe8bfeba-850b-4827-9785-10e2468c9c23",
}

---------------------------------------------------------------------------
-- Feature helpers (defaults if GenSettings / RfsFeatures keys not yet present)
---------------------------------------------------------------------------

local function streamerOn()
	if type( RfsFeatures ) == "table" and RfsFeatures.streamerModeEnabled then
		local ok, en = pcall( RfsFeatures.streamerModeEnabled )
		return ok and en == true
	end
	return false
end

local function cooldownSec()
	local n = nil
	if type( RfsFeatures ) == "table" then
		if type( RfsFeatures.streamerCooldownSec ) == "function" then
			local ok, v = pcall( RfsFeatures.streamerCooldownSec )
			if ok then
				n = tonumber( v )
			end
		elseif type( RfsFeatures.get ) == "function" then
			local ok, cfg = pcall( RfsFeatures.get )
			if ok and type( cfg ) == "table" then
				n = tonumber( cfg.streamerCooldownSec )
			end
		end
	end
	if not n then
		n = DEFAULT_COOLDOWN_SEC
	end
	n = math.floor( n )
	if n < MIN_COOLDOWN_SEC then
		n = MIN_COOLDOWN_SEC
	elseif n > MAX_COOLDOWN_SEC then
		n = MAX_COOLDOWN_SEC
	end
	return n
end

local function announceEnabled()
	if type( RfsFeatures ) == "table" then
		-- Prefer GenSettings API name from RfsFeatures; fall back to raw key / get().
		if type( RfsFeatures.streamerAnnounceEnabled ) == "function" then
			local ok, v = pcall( RfsFeatures.streamerAnnounceEnabled )
			if ok then
				return v ~= false
			end
		elseif type( RfsFeatures.streamerAnnounce ) == "function" then
			local ok, v = pcall( RfsFeatures.streamerAnnounce )
			if ok then
				return v ~= false
			end
		elseif type( RfsFeatures.get ) == "function" then
			local ok, cfg = pcall( RfsFeatures.get )
			if ok and type( cfg ) == "table" and cfg.streamerAnnounce ~= nil then
				return cfg.streamerAnnounce ~= false
			end
		end
	end
	return true
end

local function clampAmount( amount )
	local n = math.floor( tonumber( amount ) or 1 )
	if n < MIN_AMOUNT then
		n = MIN_AMOUNT
	elseif n > MAX_AMOUNT then
		n = MAX_AMOUNT
	end
	return n
end

---------------------------------------------------------------------------
-- Allowlist
---------------------------------------------------------------------------

local function builtInAllowlist()
	local units = {}
	for k, v in pairs( DEFAULT_UNITS ) do
		units[k] = v and true or nil
	end
	local itemsByAlias = {}
	local itemUuids = {}
	for alias, uuid in pairs( DEFAULT_ITEMS ) do
		local u = string.lower( tostring( uuid ) )
		itemsByAlias[alias] = u
		itemUuids[u] = true
	end
	return { units = units, itemsByAlias = itemsByAlias, itemUuids = itemUuids }
end

local function parseAllowlist( data )
	local al = builtInAllowlist()
	if type( data ) ~= "table" then
		return al
	end
	if type( data.units ) == "table" then
		local units = {}
		for _, name in ipairs( data.units ) do
			local key = string.lower( tostring( name or "" ) )
			if key ~= "" then
				units[key] = true
			end
		end
		-- Only replace defaults when file listed at least one unit.
		local any = false
		for _ in pairs( units ) do
			any = true
			break
		end
		if any then
			al.units = units
		end
	end
	if type( data.items ) == "table" then
		local itemsByAlias = {}
		local itemUuids = {}
		for _, entry in ipairs( data.items ) do
			if type( entry ) == "table" then
				local uuid = string.lower( tostring( entry.uuid or "" ) )
				local alias = string.lower( tostring( entry.alias or "" ) )
				if uuid ~= "" then
					itemUuids[uuid] = true
					if alias ~= "" then
						itemsByAlias[alias] = uuid
					end
				end
			elseif type( entry ) == "string" then
				local u = string.lower( entry )
				itemUuids[u] = true
			end
		end
		local any = false
		for _ in pairs( itemUuids ) do
			any = true
			break
		end
		if any then
			al.itemsByAlias = itemsByAlias
			al.itemUuids = itemUuids
		end
	end
	return al
end

local function countKeys( t )
	local n = 0
	if type( t ) == "table" then
		for _ in pairs( t ) do
			n = n + 1
		end
	end
	return n
end

local function sortedKeys( t )
	local list = {}
	if type( t ) == "table" then
		for k in pairs( t ) do
			list[#list + 1] = tostring( k )
		end
	end
	table.sort( list )
	return list
end

local function loadAllowlistRaw()
	for _, path in ipairs( ALLOWLIST_PATHS ) do
		local ok, data = pcall( sm.json.open, path )
		if ok and type( data ) == "table" then
			return parseAllowlist( data ), path
		end
	end
	return builtInAllowlist(), nil
end

-- Cached allowlist for votes + /gensettings preview. Cleared by reloadAllowlist().
local function loadAllowlist()
	if type( RfsStreamer._allowlistCache ) == "table" then
		return RfsStreamer._allowlistCache, RfsStreamer._allowlistPath
	end
	local al, path = loadAllowlistRaw()
	RfsStreamer._allowlistCache = al
	RfsStreamer._allowlistPath = path
	return al, path
end

-- Host GenSettings: summary + sorted unit names for cycle preview.
function RfsStreamer.getAllowlistInfo()
	local al, path = loadAllowlist()
	local units = sortedKeys( al and al.units )
	local itemCount = countKeys( al and al.itemUuids )
	return {
		unitCount = #units,
		itemCount = itemCount,
		unitNames = units,
		path = path,
		source = path and "file" or "builtin",
	}
end

function RfsStreamer.reloadAllowlist()
	RfsStreamer._allowlistCache = nil
	RfsStreamer._allowlistPath = nil
	return RfsStreamer.getAllowlistInfo()
end

local function unitAllowed( al, name )
	local key = string.lower( tostring( name or "" ) )
	if key == "" then
		return false
	end
	return al.units[key] == true
end

local function resolveItemUuid( al, raw )
	if not raw or raw == "" then
		return nil
	end
	local key = string.lower( tostring( raw ) )
	if al.itemsByAlias[key] then
		return al.itemsByAlias[key]
	end
	if al.itemUuids[key] then
		return key
	end
	return nil
end

---------------------------------------------------------------------------
-- Unit / vote IO
---------------------------------------------------------------------------

local function resolveUnitUuid( name )
	if not name or name == "" then
		return nil
	end
	local key = string.lower( tostring( name ) )
	local gname = UNIT_ALIAS[key]
	if gname then
		local u = _G[gname]
		if u then
			return u
		end
	end
	if key == "farmbot" or key == "f" then
		return _G.unit_farmbot or FARMBOT_FALLBACK
	end
	local ok, uuid = pcall( sm.uuid.new, tostring( name ) )
	if ok and uuid and not uuid:isNil() then
		return uuid
	end
	return nil
end

local function tickPathBackoff( dt )
	local map = RfsStreamer._pathBackoff
	if type( map ) ~= "table" then
		return
	end
	dt = tonumber( dt ) or 0
	if dt <= 0 then
		return
	end
	for path, left in pairs( map ) do
		left = ( tonumber( left ) or 0 ) - dt
		if left <= 0 then
			map[path] = nil
		else
			map[path] = left
		end
	end
end

local function pathInBackoff( path )
	local map = RfsStreamer._pathBackoff
	return type( map ) == "table" and ( tonumber( map[path] ) or 0 ) > 0
end

-- Escalate 5 → 10 → 20 → 30s so missing vote.json is not opened every think.
local function markPathBackoff( path )
	if type( path ) ~= "string" or path == "" then
		return
	end
	RfsStreamer._pathBackoff = RfsStreamer._pathBackoff or {}
	RfsStreamer._pathFailCount = RfsStreamer._pathFailCount or {}
	local n = ( RfsStreamer._pathFailCount[path] or 0 ) + 1
	RfsStreamer._pathFailCount[path] = n
	local sec = OPEN_BACKOFF_MIN * ( 2 ^ math.min( n - 1, 3 ) )
	if sec > OPEN_BACKOFF_MAX then
		sec = OPEN_BACKOFF_MAX
	end
	local cur = tonumber( RfsStreamer._pathBackoff[path] ) or 0
	if sec > cur then
		RfsStreamer._pathBackoff[path] = sec
	end
end

local function clearPathBackoff( path )
	if type( path ) ~= "string" or path == "" then
		return
	end
	if type( RfsStreamer._pathBackoff ) == "table" then
		RfsStreamer._pathBackoff[path] = nil
	end
	if type( RfsStreamer._pathFailCount ) == "table" then
		RfsStreamer._pathFailCount[path] = nil
	end
end

-- Returns data, path, readable.
-- readable=true: at least one path opened (even if consumed). Never json.open a known-missing path.
local function openVote()
	local readable = false
	for _, path in ipairs( VOTE_PATHS ) do
		if pathInBackoff( path ) then
			-- Silent skip until backoff expires.
		else
			local ok, data = pcall( sm.json.open, path )
			if not ok then
				markPathBackoff( path )
			elseif type( data ) == "table" and data.consumed ~= true
				and ( data.action or data.unit or data.uuid or data.item ) then
				clearPathBackoff( path )
				return data, path, true
			else
				readable = true
				clearPathBackoff( path )
			end
		end
	end
	return nil, nil, readable
end

-- SM has no file delete API: write applied snapshot + overwrite vote with consumed marker.
local function consumeVote( path, data )
	if not path or path == "" then
		return
	end
	local appliedPath = tostring( path ):gsub( "vote%.json$", "vote.applied.json" )
	if appliedPath == path then
		appliedPath = path .. ".applied"
	end
	local snapshot = {}
	if type( data ) == "table" then
		for k, v in pairs( data ) do
			snapshot[k] = v
		end
	end
	snapshot.consumed = true
	snapshot.appliedTick = nil
	pcall( function()
		snapshot.appliedTick = sm.game.getCurrentTick()
	end )
	pcall( sm.json.save, snapshot, appliedPath )
	local marker = {
		consumed = true,
		id = type( data ) == "table" and data.id or nil,
		appliedTick = snapshot.appliedTick,
	}
	pcall( sm.json.save, marker, path )
end

local function resultTimestamp()
	local ts = nil
	pcall( function()
		if type( os ) == "table" and type( os.date ) == "function" then
			ts = os.date( "!%Y-%m-%dT%H:%M:%SZ" )
		end
	end )
	if type( ts ) == "string" and ts ~= "" then
		return ts
	end
	local tick = nil
	pcall( function()
		tick = sm.game.getCurrentTick()
	end )
	return tostring( tick or "" )
end

-- Drop vote_result.json for the Node bot (Discord announce). Prefer beside the
-- consumed vote (same root Node DROP_PATH uses), then USER_DATA / TEMP / CONTENT.
-- Overwrite is fine — SM has no delete API.
local function writeVoteResult( votePath, payload )
	if type( payload ) ~= "table" then
		return nil
	end
	local candidates = {}
	local seen = {}
	local function add( p )
		if type( p ) == "string" and p ~= "" and not seen[p] then
			seen[p] = true
			candidates[#candidates + 1] = p
		end
	end
	-- Same folder as the vote the bot wrote (Node polls sibling vote_result.json).
	if type( votePath ) == "string" and votePath ~= "" then
		local beside = tostring( votePath ):gsub( "vote%.json$", "vote_result.json" )
		if beside ~= votePath then
			add( beside )
		end
	end
	-- Fallback / Workshop-safe roots (USER_DATA first).
	for _, p in ipairs( RESULT_PATHS ) do
		add( p )
	end
	for _, path in ipairs( candidates ) do
		if pathInBackoff( path ) then
			-- Skip recently failed write roots.
		else
			local ok = pcall( sm.json.save, payload, path )
			if ok then
				clearPathBackoff( path )
				return path
			end
			markPathBackoff( path )
		end
	end
	return nil
end

local function emitVoteResult( votePath, data, okApply, errInfo, verb, detail )
	local action = string.lower( tostring( ( type( data ) == "table" and data.action ) or "spawn" ) )
	if action ~= "spawn" and action ~= "give" then
		action = tostring( ( type( data ) == "table" and data.action ) or action )
	end
	local id = ""
	if type( data ) == "table" then
		id = tostring( data.id or data.ts or data.createdAt or "" )
	end
	local detailStr = nil
	if okApply then
		detailStr = tostring( verb or "applied" )
		if detail and tostring( detail ) ~= "" then
			detailStr = detailStr .. " " .. tostring( detail )
		end
	end
	local body = {
		id = id ~= "" and id or nil,
		ok = okApply and true or false,
		action = action,
		detail = detailStr,
		error = okApply and nil or tostring( errInfo or "rejected" ),
		ts = resultTimestamp(),
	}
	local written = writeVoteResult( votePath, body )
	if written then
		print( "[RFS] vote_result written: " .. tostring( written ) )
	end
	-- Write failures: path backoff only — no per-tick print spam.
end

local function hostPlayer()
	local players = nil
	pcall( function()
		players = sm.player.getAllPlayers()
	end )
	if type( players ) == "table" and players[1] then
		return players[1]
	end
	return nil
end

local function chatFeedback( game, msg )
	msg = tostring( msg or "" )
	if msg == "" then
		return
	end
	if announceEnabled() and game and game.network and game.network.sendToClients then
		local ok = pcall( function()
			game.network:sendToClients( "client_showMessage", msg )
		end )
		if ok then
			return
		end
	end
	pcall( function()
		sm.gui.chatMessage( msg )
	end )
end

---------------------------------------------------------------------------
-- Spawn / give
---------------------------------------------------------------------------

local function spawnNearPlayer( game, unitUuid, amount )
	local player = hostPlayer()
	if not player or not player.character or not sm.exists( player.character ) then
		return false, "no player"
	end
	local character = player.character
	local world = character:getWorld()
	local pos = character.worldPosition
	pcall( function()
		local dir = character.direction
		if dir then
			pos = pos + dir * 4
		end
	end )
	local qty = clampAmount( amount )
	local params = {
		uuid = unitUuid,
		world = world,
		position = pos,
		yaw = 0.0,
		amount = qty,
	}
	-- Existing Survival cheat spawn path only.
	if game and game.sv_spawnUnit then
		local ok, err = pcall( function()
			game:sv_spawnUnit( params )
		end )
		if ok then
			return true, qty
		end
		return false, tostring( err )
	end
	local ok2, err2 = pcall( function()
		sm.event.sendToWorld( world, "sv_e_spawnUnit", params )
	end )
	if ok2 then
		return true, qty
	end
	return false, tostring( err2 )
end

local function giveItem( player, uuidStr, quantity )
	player = player or hostPlayer()
	if not player then
		return false, "no player"
	end
	local ok, uuid = pcall( sm.uuid.new, tostring( uuidStr ) )
	if not ok or not uuid or uuid:isNil() then
		return false, "bad uuid"
	end
	local qty = clampAmount( quantity )
	-- Same inventory path as RecipeFrameworkSurvival.sv_rfs_give
	local okGive, err = pcall( function()
		sm.container.beginTransaction()
		sm.container.collect( player:getInventory(), uuid, qty, false )
		sm.container.endTransaction()
	end )
	if okGive then
		return true, qty
	end
	return false, tostring( err )
end

local function applyVote( game, data, al )
	local action = string.lower( tostring( data.action or "spawn" ) )
	if action == "spawn" then
		local unitName = data.unit or data.unitName or data.name
		if not unitAllowed( al, unitName ) then
			return false, "unit not allowlisted", nil, nil
		end
		local uuid = resolveUnitUuid( unitName )
		if not uuid then
			return false, "unknown unit", nil, nil
		end
		local ok, info = spawnNearPlayer( game, uuid, data.amount or data.count or data.quantity or 1 )
		if ok then
			return true, nil, "spawned", tostring( unitName ) .. " x" .. tostring( info )
		end
		return false, info, nil, nil
	elseif action == "give" then
		local raw = data.item or data.uuid
		local itemUuid = resolveItemUuid( al, raw )
		if not itemUuid then
			return false, "item not allowlisted", nil, nil
		end
		local ok, info = giveItem( nil, itemUuid, data.amount or data.quantity or data.count or 1 )
		if ok then
			local label = tostring( raw or itemUuid )
			return true, nil, "gave", label .. " x" .. tostring( info )
		end
		return false, info, nil, nil
	end
	return false, "unknown action", nil, nil
end

---------------------------------------------------------------------------
-- Tick
---------------------------------------------------------------------------

function RfsStreamer.sv_think( dt, game )
	-- Outer guard: never crash the fixed-update tick.
	local okTick, errTick = pcall( function()
		if not sm.isHost then
			return
		end
		if not streamerOn() then
			return
		end

		dt = tonumber( dt ) or 0
		RfsStreamer._cdLeft = math.max( 0, ( RfsStreamer._cdLeft or 0 ) - dt )
		tickPathBackoff( dt )

		local absent = tonumber( RfsStreamer._absentLeft ) or 0
		if absent > 0 then
			RfsStreamer._absentLeft = absent - dt
			return
		end

		RfsStreamer._accum = ( RfsStreamer._accum or 0 ) + dt
		if RfsStreamer._accum < POLL_INTERVAL then
			return
		end
		RfsStreamer._accum = 0

		if ( RfsStreamer._cdLeft or 0 ) > 0 then
			return
		end

		local data, path, readable = openVote()
		if not data then
			if not readable then
				RfsStreamer._absentLeft = ABSENT_POLL_SEC
			end
			return
		end

		local id = tostring( data.id or data.ts or data.createdAt or "" )
		if id ~= "" and id == RfsStreamer._lastId then
			-- Already applied this id; keep file consumed if possible.
			return
		end

		local al = loadAllowlist()
		local okApply, info, verb, detail = applyVote( game, data, al )
		if okApply then
			RfsStreamer._lastId = id
			RfsStreamer._cdLeft = cooldownSec()
			pcall( consumeVote, path, data )
			pcall( emitVoteResult, path, data, true, nil, verb, detail )
			local msg = "Streamer vote: " .. tostring( verb or "applied" ) .. " " .. tostring( detail or "" )
			print( "[RFS] " .. msg .. " from " .. tostring( path ) )
			chatFeedback( game, "[RFS] " .. msg )
		else
			-- Permanent rejects: consume + track so we do not spin every poll.
			if info == "unknown unit" or info == "unknown action" or info == "bad uuid"
				or info == "unit not allowlisted" or info == "item not allowlisted" then
				RfsStreamer._lastId = id
				pcall( consumeVote, path, data )
				pcall( emitVoteResult, path, data, false, info, nil, nil )
				print( "[RFS] Streamer vote skipped: " .. tostring( info ) )
			else
				-- Transient (no player / spawn fail): leave file, retry after cooldown slice.
				print( "[RFS] Streamer vote deferred: " .. tostring( info ) )
				RfsStreamer._cdLeft = math.min( cooldownSec(), 3 )
			end
		end
	end )
	if not okTick then
		print( "[RFS] RfsStreamer.sv_think error: " .. tostring( errTick ) )
	end
end
