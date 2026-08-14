-- RfsChatRelay.lua — Discord → in-game chat (Phase B).
-- Host polls chat drop files when streamerChatRelayEnabled(); vote path untouched.
-- SM sm.json.open cannot parse JSONL, so the Node bridge also writes chat_inbox.json
-- (JSON { messages = [...] }). Offset is the processed message index in sm.storage.
-- Author: DemonsDen126

RfsChatRelay = RfsChatRelay or {}

local RFS_LOCAL_ID = "29c99287-1213-48c7-9471-19a4a5c12247"
local POLL_INTERVAL = 0.5 -- seconds
local MAX_PER_TICK = 4
local MAX_CONTENT_LEN = 180
local STORAGE_KEY = { "rfs", "chatRelayOffset" }

-- Prefer writable USER_DATA (same roots as RfsStreamer vote paths).
-- chat_inbox.json = JSON companion for Lua; chat.jsonl = append log (Node / tooling).
local CHAT_INBOX_PATHS = {
	"$USER_DATA/rfs_discord_bridge/chat_inbox.json",
	"$TEMP_DATA/rfs_discord_bridge/chat_inbox.json",
	"$CONTENT_DATA/discord-bridge/inbox/chat_inbox.json",
	"$CONTENT_" .. RFS_LOCAL_ID .. "/discord-bridge/inbox/chat_inbox.json",
}

local function relayOn()
	if type( RfsFeatures ) == "table" then
		if RfsFeatures.streamerChatRelayEnabled then
			local ok, en = pcall( RfsFeatures.streamerChatRelayEnabled )
			if ok then
				return en == true
			end
		end
		-- Alias if GenSettings uses streamerChatRelay()
		if RfsFeatures.streamerChatRelay then
			local ok2, en2 = pcall( RfsFeatures.streamerChatRelay )
			if ok2 then
				return en2 == true
			end
		end
	end
	return false
end

local function loadOffset()
	local ok, data = pcall( sm.storage.load, STORAGE_KEY )
	if ok and type( data ) == "table" then
		return {
			path = tostring( data.path or "" ),
			index = math.max( 0, math.floor( tonumber( data.index ) or 0 ) ),
			lastId = tostring( data.lastId or "" ),
		}
	end
	return { path = "", index = 0, lastId = "" }
end

local function saveOffset( state )
	pcall( sm.storage.save, STORAGE_KEY, {
		path = tostring( state.path or "" ),
		index = math.max( 0, math.floor( tonumber( state.index ) or 0 ) ),
		lastId = tostring( state.lastId or "" ),
	} )
end

local function normalizeMessages( data )
	if type( data ) ~= "table" then
		return nil
	end
	-- Preferred: { messages = [ ... ] } or { lines = [ ... ] }
	if type( data.messages ) == "table" then
		return data.messages
	end
	if type( data.lines ) == "table" then
		return data.lines
	end
	-- Bare JSON array
	if data[1] ~= nil or ( next( data ) == nil ) then
		local n = #data
		if n >= 0 and ( n == 0 or type( data[1] ) == "table" ) then
			return data
		end
	end
	-- Single message object
	if data.content or data.text or data.author or data.user then
		return { data }
	end
	return nil
end

local function openChatInbox()
	for _, path in ipairs( CHAT_INBOX_PATHS ) do
		local exists = true
		if sm.json.fileExists then
			local okEx, ex = pcall( sm.json.fileExists, path )
			exists = ( not okEx ) or ex == true
		end
		if exists then
			local ok, data = pcall( sm.json.open, path )
			if ok then
				local msgs = normalizeMessages( data )
				if msgs then
					return msgs, path
				end
			end
		end
	end
	return nil, nil
end

local function authorOf( entry )
	local a = entry.author or entry.user or entry.authorTag or entry.name or ""
	a = tostring( a ):gsub( "%s+", " " ):match( "^%s*(.-)%s*$" ) or ""
	if a == "" then
		a = "Discord"
	end
	if #a > 32 then
		a = a:sub( 1, 29 ) .. "..."
	end
	return a
end

local function contentOf( entry )
	local c = entry.content or entry.text or entry.message or ""
	c = tostring( c ):gsub( "%s+", " " ):match( "^%s*(.-)%s*$" ) or ""
	if c == "" then
		return ""
	end
	if #c > MAX_CONTENT_LEN then
		c = c:sub( 1, MAX_CONTENT_LEN - 3 ) .. "..."
	end
	return c
end

local function shouldSkip( entry )
	if type( entry ) ~= "table" then
		return true
	end
	local dir = string.lower( tostring( entry.direction or "in" ) )
	if dir == "out" then
		return true
	end
	return contentOf( entry ) == ""
end

local function broadcast( line )
	pcall( function()
		sm.gui.chatMessage( line )
	end )
end

function RfsChatRelay.sv_think( dt, game )
	if not sm.isHost then
		return
	end
	if not relayOn() then
		return
	end

	RfsChatRelay._accum = ( RfsChatRelay._accum or 0 ) + ( tonumber( dt ) or 0 )
	if RfsChatRelay._accum < POLL_INTERVAL then
		return
	end
	RfsChatRelay._accum = 0

	local messages, path = openChatInbox()
	if not messages then
		return
	end

	local state = RfsChatRelay._offset or loadOffset()
	RfsChatRelay._offset = state

	-- Path change or truncated inbox → reset cursor
	local count = #messages
	if state.path ~= path or state.index > count then
		state.path = path
		state.index = count -- skip backlog on first see / truncate
		state.lastId = ""
		saveOffset( state )
		return
	end

	local sent = 0
	local startIndex = state.index
	while state.index < count and sent < MAX_PER_TICK do
		local nextIdx = state.index + 1
		local entry = messages[nextIdx]
		state.index = nextIdx

		if not shouldSkip( entry ) then
			local id = tostring( entry.id or "" )
			if id == "" or id ~= state.lastId then
				local line = "[Discord] " .. authorOf( entry ) .. ": " .. contentOf( entry )
				broadcast( line )
				if id ~= "" then
					state.lastId = id
				end
				sent = sent + 1
			end
		end
	end

	if state.index ~= startIndex or state.path ~= path then
		state.path = path
		saveOffset( state )
	end
end
