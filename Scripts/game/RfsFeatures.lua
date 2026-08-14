-- RfsFeatures.lua — WORLD-persisted feature / block / cheat flags (sm.storage)
-- Author: DemonsDen126
-- Pack defaults: rfs_settings.json. World override via /gensettings (host).
-- NEVER gates ModRecipeScan, RfsQuest API, or store/progression inject hooks.

RfsFeatures = RfsFeatures or {}

local STORAGE_KEY = { "rfs", "features" }
-- Legacy key used briefly by parallel scaffold; migrated on load.
local LEGACY_STORAGE_KEY = { "rfs", "genFeatures" }

local DEFAULT_STREAMER_COOLDOWN_SEC = 10
local STREAMER_COOLDOWN_STEPS = { 5, 10, 15, 20, 30 }

local function packCheatsDefault()
	if type( RfsSettings ) == "table" and type( RfsSettings.get ) == "function" then
		local cfg = RfsSettings.get()
		if type( cfg ) == "table" then
			return cfg.cheats ~= false
		end
	end
	return true
end

local function packFrameworkOnly()
	if type( RfsSettings ) == "table" and type( RfsSettings.frameworkOnly ) == "function" then
		return RfsSettings.frameworkOnly() == true
	end
	return false
end

local function normalizeStreamerCooldownSec( v )
	local n = tonumber( v )
	if not n then
		return DEFAULT_STREAMER_COOLDOWN_SEC
	end
	n = math.floor( n )
	if n < 0 then
		n = 0
	elseif n > 300 then
		n = 300
	end
	return n
end

local function defaultsFromPack()
	return {
		cheats = nil, -- nil until world override; readers use packCheatsDefault()
		cheatsOverride = false,
		hackDevices = true,
		areaLoader = true,
		hackableRobots = true,
		streamerMode = true,
		streamerCooldownSec = DEFAULT_STREAMER_COOLDOWN_SEC,
		streamerAnnounce = true,
		streamerChatRelay = false,
		rfsQuests = true,
	}
end

local function applyLoadedTable( cfg, data )
	if type( data ) ~= "table" then
		return cfg
	end
	if data.cheats ~= nil then
		cfg.cheats = data.cheats and true or false
		cfg.cheatsOverride = true
	end
	if data.hackDevices ~= nil then
		cfg.hackDevices = data.hackDevices and true or false
	end
	if data.areaLoader ~= nil then
		cfg.areaLoader = data.areaLoader and true or false
	end
	if data.hackableRobots ~= nil then
		cfg.hackableRobots = data.hackableRobots and true or false
	end
	if data.streamerMode ~= nil then
		cfg.streamerMode = data.streamerMode and true or false
	end
	if data.streamerCooldownSec ~= nil then
		cfg.streamerCooldownSec = normalizeStreamerCooldownSec( data.streamerCooldownSec )
	end
	if data.streamerAnnounce ~= nil then
		cfg.streamerAnnounce = data.streamerAnnounce and true or false
	end
	if data.streamerChatRelay ~= nil then
		cfg.streamerChatRelay = data.streamerChatRelay and true or false
	end
	if data.rfsQuests ~= nil then
		cfg.rfsQuests = data.rfsQuests and true or false
	end
	return cfg
end

local function publishGlobals()
	_G.g_rfsFeatures = RfsFeatures.state
	_G.g_rfsGenSettings = RfsFeatures.snapshot()
	_G.g_rfsStreamerMode = RfsFeatures.streamerModeEnabled()
end

function RfsFeatures.load( force )
	if RfsFeatures.state and not force then
		return RfsFeatures.state
	end
	local cfg = defaultsFromPack()
	local ok, data = pcall( sm.storage.load, STORAGE_KEY )
	if ok and type( data ) == "table" then
		applyLoadedTable( cfg, data )
	else
		local okLegacy, legacy = pcall( sm.storage.load, LEGACY_STORAGE_KEY )
		if okLegacy and type( legacy ) == "table" then
			applyLoadedTable( cfg, legacy )
		end
	end
	RfsFeatures.state = cfg
	publishGlobals()
	print( string.format(
		"[RFS] features loaded cheats=%s(override=%s) hackDevices=%s areaLoader=%s hackableRobots=%s streamer=%s cd=%ss announce=%s chatRelay=%s rfsQuests=%s",
		tostring( RfsFeatures.cheatsEnabled() ),
		tostring( cfg.cheatsOverride ),
		tostring( cfg.hackDevices ),
		tostring( cfg.areaLoader ),
		tostring( cfg.hackableRobots ),
		tostring( cfg.streamerMode ),
		tostring( cfg.streamerCooldownSec ),
		tostring( cfg.streamerAnnounce ),
		tostring( cfg.streamerChatRelay ),
		tostring( cfg.rfsQuests )
	) )
	return cfg
end

function RfsFeatures.save()
	local cfg = RfsFeatures.state or RfsFeatures.load()
	local payload = {
		hackDevices = cfg.hackDevices ~= false,
		areaLoader = cfg.areaLoader ~= false,
		hackableRobots = cfg.hackableRobots ~= false,
		streamerMode = cfg.streamerMode ~= false,
		streamerCooldownSec = normalizeStreamerCooldownSec( cfg.streamerCooldownSec ),
		streamerAnnounce = cfg.streamerAnnounce ~= false,
		streamerChatRelay = cfg.streamerChatRelay == true,
		rfsQuests = cfg.rfsQuests ~= false,
	}
	if cfg.cheatsOverride and cfg.cheats ~= nil then
		payload.cheats = cfg.cheats and true or false
	end
	pcall( sm.storage.save, STORAGE_KEY, payload )
	publishGlobals()
	return cfg
end

function RfsFeatures.get()
	return RfsFeatures.state or RfsFeatures.load()
end

function RfsFeatures.snapshot()
	return {
		cheats = RfsFeatures.cheatsEnabled(),
		cheatsOverride = ( RfsFeatures.get().cheatsOverride == true ),
		hackDevices = RfsFeatures.hackDevicesEnabled(),
		areaLoader = RfsFeatures.areaLoaderEnabled(),
		hackableRobots = RfsFeatures.hackableRobotsEnabled(),
		streamerMode = RfsFeatures.streamerModeEnabled(),
		streamerCooldownSec = RfsFeatures.streamerCooldownSec(),
		streamerAnnounce = RfsFeatures.streamerAnnounceEnabled(),
		streamerChatRelay = RfsFeatures.streamerChatRelayEnabled(),
		rfsQuests = RfsFeatures.rfsQuestsEnabled(),
	}
end

-- Apply a server snapshot on clients (no storage write).
function RfsFeatures.applySnapshot( data )
	if type( data ) ~= "table" then
		return RfsFeatures.get()
	end
	local cfg = RfsFeatures.state or defaultsFromPack()
	if data.cheatsOverride ~= nil then
		cfg.cheatsOverride = data.cheatsOverride and true or false
	elseif data.cheats ~= nil then
		cfg.cheatsOverride = true
	end
	if data.cheats ~= nil then
		cfg.cheats = data.cheats and true or false
	end
	if data.hackDevices ~= nil then
		cfg.hackDevices = data.hackDevices and true or false
	end
	if data.areaLoader ~= nil then
		cfg.areaLoader = data.areaLoader and true or false
	end
	if data.hackableRobots ~= nil then
		cfg.hackableRobots = data.hackableRobots and true or false
	end
	if data.streamerMode ~= nil then
		cfg.streamerMode = data.streamerMode and true or false
	end
	if data.streamerCooldownSec ~= nil then
		cfg.streamerCooldownSec = normalizeStreamerCooldownSec( data.streamerCooldownSec )
	end
	if data.streamerAnnounce ~= nil then
		cfg.streamerAnnounce = data.streamerAnnounce and true or false
	end
	if data.streamerChatRelay ~= nil then
		cfg.streamerChatRelay = data.streamerChatRelay and true or false
	end
	if data.rfsQuests ~= nil then
		cfg.rfsQuests = data.rfsQuests and true or false
	end
	RfsFeatures.state = cfg
	publishGlobals()
	return cfg
end

function RfsFeatures.cheatsEnabled()
	if packFrameworkOnly() then
		return false
	end
	local cfg = RfsFeatures.get()
	if cfg.cheatsOverride and cfg.cheats ~= nil then
		return cfg.cheats and true or false
	end
	return packCheatsDefault()
end

function RfsFeatures.setCheats( enabled )
	local cfg = RfsFeatures.get()
	cfg.cheats = enabled and true or false
	cfg.cheatsOverride = true
	RfsFeatures.save()
	return cfg.cheats
end

function RfsFeatures.hackDevicesEnabled()
	return RfsFeatures.get().hackDevices ~= false
end

function RfsFeatures.setHackDevicesEnabled( enabled )
	local cfg = RfsFeatures.get()
	cfg.hackDevices = enabled and true or false
	RfsFeatures.save()
	return cfg.hackDevices
end

function RfsFeatures.areaLoaderEnabled()
	return RfsFeatures.get().areaLoader ~= false
end

function RfsFeatures.setAreaLoaderEnabled( enabled )
	local cfg = RfsFeatures.get()
	cfg.areaLoader = enabled and true or false
	RfsFeatures.save()
	return cfg.areaLoader
end

function RfsFeatures.hackableRobotsEnabled()
	return RfsFeatures.get().hackableRobots ~= false
end

function RfsFeatures.setHackableRobotsEnabled( enabled )
	local cfg = RfsFeatures.get()
	cfg.hackableRobots = enabled and true or false
	RfsFeatures.save()
	return cfg.hackableRobots
end

function RfsFeatures.streamerModeEnabled()
	return RfsFeatures.get().streamerMode ~= false
end

function RfsFeatures.setStreamerModeEnabled( enabled )
	local cfg = RfsFeatures.get()
	cfg.streamerMode = enabled and true or false
	RfsFeatures.save()
	return cfg.streamerMode
end

function RfsFeatures.streamerCooldownSec()
	return normalizeStreamerCooldownSec( RfsFeatures.get().streamerCooldownSec )
end

function RfsFeatures.setStreamerCooldownSec( sec )
	local cfg = RfsFeatures.get()
	cfg.streamerCooldownSec = normalizeStreamerCooldownSec( sec )
	RfsFeatures.save()
	return cfg.streamerCooldownSec
end

-- Cycle common cooldown presets (used by /gensettings button).
function RfsFeatures.cycleStreamerCooldownSec()
	local cur = RfsFeatures.streamerCooldownSec()
	local nextVal = STREAMER_COOLDOWN_STEPS[1]
	for i, step in ipairs( STREAMER_COOLDOWN_STEPS ) do
		if step == cur then
			nextVal = STREAMER_COOLDOWN_STEPS[( i % #STREAMER_COOLDOWN_STEPS ) + 1]
			break
		elseif cur < step then
			nextVal = step
			break
		end
	end
	return RfsFeatures.setStreamerCooldownSec( nextVal )
end

function RfsFeatures.streamerAnnounceEnabled()
	return RfsFeatures.get().streamerAnnounce ~= false
end

-- Alias for streamer vote consumers.
function RfsFeatures.streamerAnnounce()
	return RfsFeatures.streamerAnnounceEnabled()
end

function RfsFeatures.setStreamerAnnounceEnabled( enabled )
	local cfg = RfsFeatures.get()
	cfg.streamerAnnounce = enabled and true or false
	RfsFeatures.save()
	return cfg.streamerAnnounce
end

function RfsFeatures.streamerChatRelayEnabled()
	return RfsFeatures.get().streamerChatRelay == true
end

-- Alias for chat-relay consumers.
function RfsFeatures.streamerChatRelay()
	return RfsFeatures.streamerChatRelayEnabled()
end

function RfsFeatures.setStreamerChatRelayEnabled( enabled )
	local cfg = RfsFeatures.get()
	cfg.streamerChatRelay = enabled and true or false
	RfsFeatures.save()
	return cfg.streamerChatRelay
end

-- RFS-added quest UI only — never disables RfsQuest API / hooks.
function RfsFeatures.rfsQuestsEnabled()
	if packFrameworkOnly() then
		return false
	end
	return RfsFeatures.get().rfsQuests ~= false
end

function RfsFeatures.setRfsQuestsEnabled( enabled )
	local cfg = RfsFeatures.get()
	cfg.rfsQuests = enabled and true or false
	RfsFeatures.save()
	return cfg.rfsQuests
end

-- Convenience used by Game.lua GenSettings RPC path.
function RfsFeatures.set( key, value )
	if key == "cheats" then
		return RfsFeatures.setCheats( value )
	elseif key == "hackDevices" then
		return RfsFeatures.setHackDevicesEnabled( value )
	elseif key == "areaLoader" then
		return RfsFeatures.setAreaLoaderEnabled( value )
	elseif key == "hackableRobots" then
		return RfsFeatures.setHackableRobotsEnabled( value )
	elseif key == "streamerMode" then
		return RfsFeatures.setStreamerModeEnabled( value )
	elseif key == "streamerCooldownSec" then
		return RfsFeatures.setStreamerCooldownSec( value )
	elseif key == "streamerAnnounce" then
		return RfsFeatures.setStreamerAnnounceEnabled( value )
	elseif key == "streamerChatRelay" then
		return RfsFeatures.setStreamerChatRelayEnabled( value )
	elseif key == "rfsQuests" then
		return RfsFeatures.setRfsQuestsEnabled( value )
	end
	return RfsFeatures.snapshot()
end

function RfsFeatures.toggle( key )
	local cur = false
	if key == "cheats" then
		cur = RfsFeatures.cheatsEnabled()
	elseif key == "hackDevices" then
		cur = RfsFeatures.hackDevicesEnabled()
	elseif key == "areaLoader" then
		cur = RfsFeatures.areaLoaderEnabled()
	elseif key == "hackableRobots" then
		cur = RfsFeatures.hackableRobotsEnabled()
	elseif key == "streamerMode" then
		cur = RfsFeatures.streamerModeEnabled()
	elseif key == "streamerCooldownSec" then
		RfsFeatures.cycleStreamerCooldownSec()
		return RfsFeatures.snapshot()
	elseif key == "streamerAnnounce" then
		cur = RfsFeatures.streamerAnnounceEnabled()
	elseif key == "streamerChatRelay" then
		cur = RfsFeatures.streamerChatRelayEnabled()
	elseif key == "rfsQuests" then
		cur = RfsFeatures.rfsQuestsEnabled()
	else
		return RfsFeatures.snapshot()
	end
	RfsFeatures.set( key, not cur )
	return RfsFeatures.snapshot()
end
