-- RfsChatOutbox.lua — game → Discord chat outbox (Phase D).
-- SM has no freeform chat hook; /say and /d append to chat_outbox.json for the Node bot.
-- Gated: Streamer mode ON + Discord chat relay ON (RfsFeatures.streamerChatRelay).
-- Author: DemonsDen126

RfsChatOutbox = RfsChatOutbox or {}

local RFS_LOCAL_ID = "29c99287-1213-48c7-9471-19a4a5c12247"
local MAX_CONTENT_LEN = 400
local MAX_MESSAGES = 80

local OUTBOX_PATHS = {
	"$USER_DATA/rfs_discord_bridge/chat_outbox.json",
	"$TEMP_DATA/rfs_discord_bridge/chat_outbox.json",
	"$CONTENT_DATA/discord-bridge/inbox/chat_outbox.json",
	"$CONTENT_" .. RFS_LOCAL_ID .. "/discord-bridge/inbox/chat_outbox.json",
}

local function streamerOn()
	if type( RfsFeatures ) == "table" and RfsFeatures.streamerModeEnabled then
		local ok, en = pcall( RfsFeatures.streamerModeEnabled )
		if ok then
			return en == true
		end
	end
	return _G.g_rfsStreamerMode == true
end

local function relayOn()
	if type( RfsFeatures ) == "table" then
		if RfsFeatures.streamerChatRelayEnabled then
			local ok, en = pcall( RfsFeatures.streamerChatRelayEnabled )
			if ok then
				return en == true
			end
		end
		if RfsFeatures.streamerChatRelay then
			local ok2, en2 = pcall( RfsFeatures.streamerChatRelay )
			if ok2 then
				return en2 == true
			end
		end
	end
	return false
end

local function outboxEnabled()
	return streamerOn() and relayOn()
end

local function trim( s )
	return tostring( s or "" ):gsub( "%s+", " " ):match( "^%s*(.-)%s*$" ) or ""
end

local function playerName( player )
	if not player then
		return "Player"
	end
	local n = ""
	pcall( function()
		n = tostring( player:getName() or "" )
	end )
	n = trim( n )
	if n == "" then
		n = "Player"
	end
	if #n > 32 then
		n = n:sub( 1, 29 ) .. "..."
	end
	return n
end

local function makeId()
	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick() or 0
	end )
	return tostring( tick ) .. "-" .. tostring( math.random( 1000, 9999 ) )
end

local function loadOutbox( path )
	if sm.json.fileExists then
		local okEx, ex = pcall( sm.json.fileExists, path )
		if okEx and ex ~= true then
			return { version = 1, messages = {} }
		end
	end
	local ok, data = pcall( sm.json.open, path )
	if ok and type( data ) == "table" then
		local msgs = data.messages
		if type( msgs ) ~= "table" then
			msgs = {}
		end
		return { version = 1, messages = msgs }
	end
	return { version = 1, messages = {} }
end

local function writeOutbox( path, box )
	local msgs = box.messages or {}
	if #msgs > MAX_MESSAGES then
		local keep = {}
		for i = #msgs - MAX_MESSAGES + 1, #msgs do
			keep[#keep + 1] = msgs[i]
		end
		msgs = keep
	end
	local payload = {
		version = 1,
		updatedAt = os.time and os.time() or 0,
		messages = msgs,
	}
	local ok = pcall( sm.json.save, payload, path )
	return ok == true
end

--- Append one outbound chat line. Returns ok, info.
function RfsChatOutbox.append( author, content, meta )
	if not sm.isHost then
		return false, "host only"
	end
	if not outboxEnabled() then
		return false, "streamer+chat relay off"
	end
	content = trim( content )
	if content == "" then
		return false, "empty"
	end
	-- Avoid Discord→game→Discord loop (relay prefix / direction tags).
	if content:match( "^%[Discord%]" ) then
		return false, "skip discord echo"
	end
	if #content > MAX_CONTENT_LEN then
		content = content:sub( 1, MAX_CONTENT_LEN - 3 ) .. "..."
	end
	author = trim( author )
	if author == "" then
		author = "Player"
	end

	local entry = {
		id = makeId(),
		ts = ( os.time and os.time() or 0 ) * 1000,
		author = author,
		content = content,
		source = "game",
		direction = "out",
	}
	if type( meta ) == "table" then
		if meta.playerId then
			entry.playerId = tostring( meta.playerId )
		end
	end

	local wrote = nil
	for _, path in ipairs( OUTBOX_PATHS ) do
		local box = loadOutbox( path )
		box.messages = box.messages or {}
		box.messages[#box.messages + 1] = entry
		if writeOutbox( path, box ) then
			wrote = path
			break
		end
	end
	if not wrote then
		return false, "write failed"
	end
	return true, wrote
end

function RfsChatOutbox.enabled()
	return outboxEnabled()
end

--- Server entry from /say /d
function RfsChatOutbox.sv_fromPlayer( game, player, text )
	if not sm.isHost then
		return
	end
	if not outboxEnabled() then
		pcall( function()
			sm.gui.chatMessage( "[RFS] Game→Discord chat needs Streamer ON + Discord chat relay ON (/gensettings)." )
		end )
		return
	end
	local ok, info = RfsChatOutbox.append( playerName( player ), text, {
		playerId = player and player.id or nil,
	} )
	if ok then
		pcall( function()
			sm.gui.chatMessage( "[RFS] →Discord: " .. trim( text ) )
		end )
	else
		pcall( function()
			sm.gui.chatMessage( "[RFS] Chat outbox failed: " .. tostring( info ) )
		end )
	end
end
