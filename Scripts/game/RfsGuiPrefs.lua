-- RfsGuiPrefs.lua — Phase 3.6 /menu visual prefs (per player).
-- Names on/off, Big Red farmbot label, enemy/neutral nametag tint.
-- Block health overlay: no SM custom-game API — cut (see docs/RUSH.md UNSURE).

RfsGuiPrefs = RfsGuiPrefs or {}

local STORAGE_KEY_PREFIX = "guiPrefs"

RfsGuiPrefs.HP_CYCLE = { "red", "orange", "yellow", "green", "cyan", "blue", "white", "magenta" }

local HP_COLORS = {
	red = sm.color.new( 1.00, 0.18, 0.18, 1.0 ),
	orange = sm.color.new( 1.00, 0.50, 0.12, 1.0 ),
	yellow = sm.color.new( 1.00, 0.88, 0.18, 1.0 ),
	green = sm.color.new( 0.28, 0.92, 0.38, 1.0 ),
	cyan = sm.color.new( 0.25, 0.90, 0.95, 1.0 ),
	blue = sm.color.new( 0.30, 0.50, 1.00, 1.0 ),
	white = sm.color.new( 0.95, 0.95, 0.95, 1.0 ),
	magenta = sm.color.new( 0.92, 0.28, 0.85, 1.0 ),
}

local function defaults()
	return {
		names = true,
		bigRed = false,
		enemyHp = "red",
		neutralHp = "green",
	}
end

local function storageKey( player )
	local id = "0"
	pcall( function()
		if player and player.id then
			id = tostring( player.id )
		end
	end )
	return { "rfs", STORAGE_KEY_PREFIX, id }
end

local function normalize( data )
	local d = defaults()
	if type( data ) ~= "table" then
		return d
	end
	if data.names ~= nil then
		d.names = data.names and true or false
	end
	if data.bigRed ~= nil then
		d.bigRed = data.bigRed and true or false
	end
	local function hp( v, fallback )
		v = string.lower( tostring( v or "" ) )
		if HP_COLORS[v] then
			return v
		end
		return fallback
	end
	d.enemyHp = hp( data.enemyHp, d.enemyHp )
	d.neutralHp = hp( data.neutralHp, d.neutralHp )
	return d
end

function RfsGuiPrefs.hpColor( name )
	name = string.lower( tostring( name or "" ) )
	return HP_COLORS[name] or HP_COLORS.green
end

function RfsGuiPrefs.load( player )
	local data = nil
	pcall( function()
		data = sm.storage.load( storageKey( player ) )
	end )
	return normalize( data )
end

function RfsGuiPrefs.save( player, prefs )
	prefs = normalize( prefs )
	pcall( function()
		sm.storage.save( storageKey( player ), prefs )
	end )
	return prefs
end

function RfsGuiPrefs.applyClient( prefs )
	prefs = normalize( prefs )
	g_rfsGuiPrefs = prefs
	return prefs
end

function RfsGuiPrefs.client()
	if type( g_rfsGuiPrefs ) == "table" then
		return normalize( g_rfsGuiPrefs )
	end
	return defaults()
end

function RfsGuiPrefs.toggle( prefs, key )
	prefs = normalize( prefs )
	if key == "names" then
		prefs.names = not prefs.names
	elseif key == "bigRed" then
		prefs.bigRed = not prefs.bigRed
	elseif key == "enemyHp" or key == "neutralHp" then
		local cur = prefs[key]
		local idx = 1
		for i, name in ipairs( RfsGuiPrefs.HP_CYCLE ) do
			if name == cur then
				idx = i
				break
			end
		end
		idx = ( idx % #RfsGuiPrefs.HP_CYCLE ) + 1
		prefs[key] = RfsGuiPrefs.HP_CYCLE[idx]
	end
	return prefs
end

print( "[RFS] RfsGuiPrefs loaded (Phase 3.6 visuals)" )
