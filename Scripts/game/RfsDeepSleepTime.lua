-- RfsDeepSleepTime.lua
-- VOLATILE: solo night skip to 5 AM + crop/solar/drain simulation.
-- No multiplayer vote-to-sleep. MP (2+ players) sets respawn only.
-- Does not retune RfsHackPower.drainEvery. Spend uses existing spendOne.

RfsDeepSleepTime = RfsDeepSleepTime or {}

pcall( function()
	dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsRecharge.lua" )
end )
pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsHealPower.lua" )
end )

local FIVE_AM = 5 / 24
local NIGHT = 0.875
pcall( function()
	if type( DAYCYCLE_NIGHT ) == "number" then
		NIGHT = DAYCYCLE_NIGHT
	end
end )

local TICKS_PER_DAY = 1440 * 40
pcall( function()
	if type( DAYCYCLE_TIME_TICKS ) == "number" and DAYCYCLE_TIME_TICKS > 0 then
		TICKS_PER_DAY = DAYCYCLE_TIME_TICKS
	end
end )

local SOLAR_UUID = "7a402d6c-93e5-4f28-ab71-d2e6f9a3b5c8"
local DEEPSLEEP_UUID = "6f391c5b-82d4-4e17-9a60-c1d5e8f2a4b7"
local BEACON_UUIDS = {
	["b4e8c1a0-7d2f-4a91-9c3e-29f1a8d6b5e7"] = true,
	["c5f9d2b1-8e30-4ba2-ad4f-30a2b9e7c6f8"] = true,
	["d6a0e3c2-9f41-4cb3-be50-41b3c0f8d709"] = true,
}

local function uuidStr( u )
	local s = string.lower( tostring( u or "" ) )
	local m = string.match( s, "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x" )
	return m or s
end

local function playerCount()
	local n = 0
	pcall( function()
		local all = sm.player.getAllPlayers() or {}
		n = #all
	end )
	return n
end

function RfsDeepSleepTime.isNight( tod )
	tod = tonumber( tod )
	if not tod then
		pcall( function()
			tod = sm.game.getTimeOfDay()
		end )
	end
	tod = tonumber( tod ) or 0.5
	local wrapped = tod - math.floor( tod )
	return wrapped >= NIGHT or wrapped < FIVE_AM
end

function RfsDeepSleepTime.soloOk()
	return playerCount() <= 1
end

local function wrappedTod( game )
	local tod = 0.5
	pcall( function()
		if game and game.sv and game.sv.time and game.sv.time.timeOfDay then
			tod = tonumber( game.sv.time.timeOfDay ) or tod
		else
			tod = sm.game.getTimeOfDay() or tod
		end
	end )
	return tod, tod - math.floor( tod )
end

-- Ticks from now until next 5 AM. 0 if not night.
function RfsDeepSleepTime.skipTicks( game )
	if not RfsDeepSleepTime.isNight( select( 1, wrappedTod( game ) ) ) then
		return 0, nil
	end
	local tod, wrapped = wrappedTod( game )
	local delta
	if wrapped >= FIVE_AM then
		delta = ( 1 - wrapped ) + FIVE_AM
	else
		delta = FIVE_AM - wrapped
	end
	if delta < 0 then
		delta = 0
	end
	local ticks = math.floor( delta * TICKS_PER_DAY + 0.5 )
	local nextTod = math.floor( tod )
	if wrapped >= FIVE_AM then
		nextTod = nextTod + 1
	end
	nextTod = nextTod + FIVE_AM
	return ticks, nextTod
end

local function applyTime( game, nextTod )
	if not game or not game.sv or not game.sv.time then
		return false
	end
	game.sv.time.timeOfDay = nextTod
	pcall( function()
		if game.sv.syncTimer and game.sv.syncTimer.ticks then
			game.sv.syncTimer.count = game.sv.syncTimer.ticks
		end
	end )
	pcall( function()
		local ch = ( type( STORAGE_CHANNEL_TIME ) == "number" and STORAGE_CHANNEL_TIME ) or 16
		sm.storage.save( ch, game.sv.time )
	end )
	pcall( function()
		game:sv_updateClientData()
	end )
	local frac = nextTod - math.floor( nextTod )
	pcall( function()
		sm.game.setTimeOfDay( frac )
	end )
	pcall( function()
		if WeatherManager and WeatherManager.Get then
			local w = WeatherManager.Get()
			if w and w.sv_setTimeOfDay then
				w:sv_setTimeOfDay( frac )
			end
		end
	end )
	return true
end

function RfsDeepSleepTime.skipFromGame( game, params )
	params = params or {}
	if not RfsDeepSleepTime.soloOk() then
		pcall( function()
			sm.gui.chatMessage( "[RFS] Chemical Regeneration Station: respawn set. Night skip is solo-only (vote parked)." )
		end )
		return false, "mp"
	end
	local ticks, nextTod = RfsDeepSleepTime.skipTicks( game )
	if not ticks or ticks <= 0 or not nextTod then
		pcall( function()
			sm.gui.chatMessage( "[RFS] Chemical Regeneration Station: respawn set (daytime, no skip)." )
		end )
		return false, "day"
	end
	local ok = applyTime( game, nextTod )
	if not ok then
		pcall( function()
			sm.gui.chatMessage( "[RFS] Chemical Regeneration Station: time skip API missing; respawn still set." )
		end )
		return false, "noapi"
	end
	pcall( function()
		if type( RfsFarming ) == "table" and RfsFarming.advanceGrowthTicks then
			RfsFarming.advanceGrowthTicks( game, ticks )
		end
	end )
	pcall( function()
		local host = nil
		if game.sv_rfs_ensureHijackHost then
			host = game:sv_rfs_ensureHijackHost()
		end
		if host then
			sm.event.sendToScriptableObject( host, "sv_e_rfsDeepSleepWorldSkip", {
				ticks = ticks,
				podHealing = params.healing and true or false,
			} )
		end
	end )
	pcall( function()
		sm.gui.chatMessage( "[RFS] Chemical Regeneration Station: skipped night to 5 AM (" .. tostring( ticks ) .. " ticks)." )
	end )
	return true, ticks
end

local function sendToShape( shape, name, payload )
	if not shape or not sm.exists( shape ) then
		return
	end
	pcall( function()
		local ia = shape.interactable or shape:getInteractable()
		if ia and sm.exists( ia ) then
			sm.event.sendToInteractable( ia, name, payload )
		end
	end )
end

function RfsDeepSleepTime.worldSkip( host, params )
	params = params or {}
	local ticks = tonumber( params.ticks ) or 0
	if ticks <= 0 then
		return
	end
	local bodies = {}
	pcall( function()
		bodies = sm.body.getAllBodies() or {}
	end )
	if type( bodies ) ~= "table" or #bodies == 0 then
		pcall( function()
			if host and host.world and host.world.getAllBodies then
				bodies = host.world:getAllBodies() or {}
			end
		end )
	end
	if type( bodies ) ~= "table" then
		return
	end
	for _, body in ipairs( bodies ) do
		if body and sm.exists( body ) then
			local shapes = nil
			pcall( function()
				shapes = body:getShapes() or body:getCreationShapes()
			end )
			if type( shapes ) == "table" then
				for _, shape in ipairs( shapes ) do
					if shape and sm.exists( shape ) then
						local id = uuidStr( shape.uuid )
						if id == SOLAR_UUID then
							sendToShape( shape, "sv_e_rfsSkipCharge", { ticks = ticks } )
						elseif BEACON_UUIDS[id] then
							sendToShape( shape, "sv_e_rfsSkipDrain", { ticks = ticks } )
						elseif id == DEEPSLEEP_UUID and params.podHealing then
							sendToShape( shape, "sv_e_rfsSkipDrain", { ticks = ticks } )
						end
					end
				end
			end
		end
	end
end

print( "[RFS] RfsDeepSleepTime loaded (solo 5 AM skip; no MP vote)" )
