-- RfsSettings.lua — load $CONTENT_DATA/rfs_settings.json
-- Author: DemonsDen126
-- Pack/file defaults for new worlds. Live world overrides live in RfsFeatures (sm.storage).

RfsSettings = RfsSettings or {}

local SETTINGS_PATH = "$CONTENT_DATA/rfs_settings.json"

local defaults = {
	setupQuestTab = true,
	cheats = true,
	frameworkOnly = false,
}

local cached = nil

local function deepCopyDefaults()
	return {
		setupQuestTab = defaults.setupQuestTab,
		cheats = defaults.cheats,
		frameworkOnly = defaults.frameworkOnly,
	}
end

function RfsSettings.load( force )
	if cached and not force then
		return cached
	end
	local cfg = deepCopyDefaults()
	local ok, data = pcall( sm.json.open, SETTINGS_PATH )
	if ok and type( data ) == "table" then
		if data.frameworkOnly ~= nil then
			cfg.frameworkOnly = data.frameworkOnly and true or false
		elseif data.enableDefaultContent ~= nil then
			-- Inverse alias: enableDefaultContent=false → frameworkOnly=true
			cfg.frameworkOnly = not ( data.enableDefaultContent and true or false )
		end
		if data.setupQuestTab ~= nil then
			cfg.setupQuestTab = data.setupQuestTab and true or false
		end
		if data.cheats ~= nil then
			cfg.cheats = data.cheats and true or false
		end
		-- Framework-only: force cheat + quest tooling off. Hooks / scan / hijack stay on.
		-- Does NOT force beacons/area loader/robots off — use /gensettings for those.
		if cfg.frameworkOnly then
			cfg.cheats = false
			cfg.setupQuestTab = false
		end
	else
		print( "[RFS] rfs_settings.json missing or invalid — using defaults (cheats ON, quest tab ON)" )
	end
	cached = cfg
	_G.g_rfsSettings = cfg
	print( string.format(
		"[RFS] settings frameworkOnly=%s cheats=%s setupQuestTab=%s",
		tostring( cfg.frameworkOnly ),
		tostring( cfg.cheats ),
		tostring( cfg.setupQuestTab )
	) )
	return cfg
end

function RfsSettings.get()
	return cached or RfsSettings.load()
end

function RfsSettings.frameworkOnly()
	local cfg = RfsSettings.get()
	return cfg.frameworkOnly == true
end

function RfsSettings.defaultContentEnabled()
	return not RfsSettings.frameworkOnly()
end

function RfsSettings.cheatsEnabled()
	local cfg = RfsSettings.get()
	if cfg.frameworkOnly then
		return false
	end
	-- Prefer world RfsFeatures when loaded (host /gensettings override).
	if type( RfsFeatures ) == "table" and RfsFeatures.state ~= nil and type( RfsFeatures.cheatsEnabled ) == "function" then
		return RfsFeatures.cheatsEnabled()
	end
	return cfg.cheats ~= false
end

function RfsSettings.questTabEnabled()
	local cfg = RfsSettings.get()
	if cfg.frameworkOnly then
		return false
	end
	-- World flag can hide RFS quest UI without touching RfsQuest API.
	if type( RfsFeatures ) == "table" and RfsFeatures.state ~= nil and type( RfsFeatures.rfsQuestsEnabled ) == "function" then
		if not RfsFeatures.rfsQuestsEnabled() then
			return false
		end
	end
	return cfg.setupQuestTab ~= false
end
