-- RfsHackOrdersDrop.lua
-- VOLATILE: DROP-complete / death → forget allies[] + push open Orders to drop rows.
-- FROZEN: battery spend, caps, hijack HP/damage, E / queueOpen / cl_rfs_ordersOpen.
--
-- DROP 8.0 and death used to unhack only in HijackHost. Game allies[] and the
-- open Orders GUI kept ghost "Bot" rows. This module is the cross-sandbox notify.

RfsHackOrdersDrop = RfsHackOrdersDrop or {}

local function unitKeyOf( unit )
	if not unit then
		return nil
	end
	local k = nil
	pcall( function()
		k = tostring( unit.id )
	end )
	if k and k ~= "" then
		return k
	end
	return nil
end

local function homeKeyOf( info )
	if type( info ) ~= "table" then
		return nil
	end
	if type( RfsBotHijack ) == "table" and type( RfsBotHijack.homeBeaconKey ) == "function" then
		local h = nil
		pcall( function()
			h = RfsBotHijack.homeBeaconKey( info )
		end )
		if h and tostring( h ) ~= "" then
			return tostring( h )
		end
	end
	if info.workBeaconKey ~= nil then
		return tostring( info.workBeaconKey )
	end
	if info.beaconKey ~= nil then
		return tostring( info.beaconKey )
	end
	if info.hackBeaconKey ~= nil then
		return tostring( info.hackBeaconKey )
	end
	return nil
end

function RfsHackOrdersDrop.forgetLocal( key )
	key = tostring( key or "" )
	if key == "" then
		return
	end
	if type( RfsBotHijack ) ~= "table" then
		return
	end
	if type( RfsBotHijack.allies ) == "table" then
		RfsBotHijack.allies[key] = nil
	end
	if type( RfsBotHijack.drops ) == "table" then
		RfsBotHijack.drops[key] = nil
	end
	if type( RfsBotHijack.jams ) == "table" then
		RfsBotHijack.jams[key] = nil
	end
	if type( RfsBotHijack.pending ) == "table" then
		RfsBotHijack.pending[key] = nil
	end
	if type( RfsBotHijack.chain ) == "table" then
		RfsBotHijack.chain[key] = nil
	end
end

-- True only when we can prove the unit is gone/downed. Nil unitByKey is not death
-- (Game sandbox often cannot scan units).
function RfsHackOrdersDrop.rowIsDead( key )
	key = tostring( key or "" )
	if key == "" then
		return false
	end
	if type( RfsBotHijack ) ~= "table" or type( RfsBotHijack.unitByKey ) ~= "function" then
		return false
	end
	local unit = nil
	pcall( function()
		unit = RfsBotHijack.unitByKey( key )
	end )
	if not unit then
		return false
	end
	local exists = true
	pcall( function()
		exists = sm.exists( unit ) ~= false
	end )
	if not exists then
		return true
	end
	local char = nil
	pcall( function()
		char = unit.character
	end )
	if not char then
		return true
	end
	local charOk = false
	pcall( function()
		charOk = sm.exists( char ) ~= false
	end )
	if not charOk then
		return true
	end
	local downed = false
	pcall( function()
		downed = char:isDowned() and true or false
	end )
	return downed
end

function RfsHackOrdersDrop.unitLooksDead( unit )
	if not unit then
		return true
	end
	local exists = true
	pcall( function()
		exists = sm.exists( unit ) ~= false
	end )
	if not exists then
		return true
	end
	local char = nil
	pcall( function()
		char = unit.character
	end )
	if not char then
		return true
	end
	local charOk = false
	pcall( function()
		charOk = sm.exists( char ) ~= false
	end )
	if not charOk then
		return true
	end
	local downed = false
	pcall( function()
		downed = char:isDowned() and true or false
	end )
	return downed
end

function RfsHackOrdersDrop.notify( keys, beaconKeys )
	if type( keys ) ~= "table" or #keys == 0 then
		return
	end
	local uniq = {}
	local list = {}
	for _, k in ipairs( keys ) do
		k = tostring( k or "" )
		if k ~= "" and not uniq[k] then
			uniq[k] = true
			list[#list + 1] = k
		end
	end
	if #list == 0 then
		return
	end
	local beacons = {}
	local seenB = {}
	for _, b in ipairs( beaconKeys or {} ) do
		b = tostring( b or "" )
		if b ~= "" and not seenB[b] then
			seenB[b] = true
			beacons[#beacons + 1] = b
		end
	end
	local payload = { keys = list, beaconKeys = beacons }
	local game = _G.g_rfsGame
	if game and type( game.sv_rfs_ordersDropUnits ) == "function" then
		local ok = pcall( function()
			game:sv_rfs_ordersDropUnits( payload )
		end )
		if ok then
			return
		end
	end
	pcall( function()
		sm.event.sendToGame( "sv_rfs_ordersDropUnits", payload )
	end )
end

function RfsHackOrdersDrop.afterGone( key, info )
	key = tostring( key or "" )
	if key == "" then
		return
	end
	RfsHackOrdersDrop.forgetLocal( key )
	RfsHackOrdersDrop.notify( { key }, { homeKeyOf( info ) } )
end

function RfsHackOrdersDrop.afterGoneMany( pairsList )
	if type( pairsList ) ~= "table" or #pairsList == 0 then
		return
	end
	local keys, beacons = {}, {}
	for _, rec in ipairs( pairsList ) do
		local key = rec and tostring( rec.key or "" ) or ""
		if key ~= "" then
			RfsHackOrdersDrop.forgetLocal( key )
			keys[#keys + 1] = key
			local h = homeKeyOf( rec.info )
			if h then
				beacons[#beacons + 1] = h
			end
		end
	end
	RfsHackOrdersDrop.notify( keys, beacons )
end

-- DROP 8.0 / raid release / voluntary: unit still exists; unhack already ran.
function RfsHackOrdersDrop.afterUnhack( unit, info )
	local key = unitKeyOf( unit )
	if not key then
		return
	end
	RfsHackOrdersDrop.afterGone( key, info )
end

print( "[RFS] RfsHackOrdersDrop loaded (VOLATILE DROP/death → Orders drop+refresh)" )
