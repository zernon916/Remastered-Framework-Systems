-- RfsHandheldHack.lua
-- VOLATILE: player handheld radio hack attempt (NOT beacon convert / station core).
-- Short range, chance-based Follow/Defend only, 10 s OOR revert. Does not touch frozen
-- beacon spend, caps, hijack HP, Orders queueOpen, or SHOW RANGE host.

RfsHandheldHack = RfsHandheldHack or {}

-- Documented tuning (player-facing in tool description).
RfsHandheldHack.RANGE = 8          -- blocks (~8 m)
RfsHandheldHack.OOR_SECONDS = 10
RfsHandheldHack.OOR_TICKS = 40 * RfsHandheldHack.OOR_SECONDS
RfsHandheldHack.SUCCESS_CHANCE = 0.40 -- 40% per attempt

local TOOL_UUID = "e8f4a2b1-3c7d-4e9f-8a2b-1d5e6f7a8b9c"

function RfsHandheldHack.toolUuid()
	return TOOL_UUID
end

function RfsHandheldHack.playerHasTool( player )
	local ok, item = pcall( function()
		if not player or not player.character then
			return nil
		end
		return sm.container.getHotbar( player, 0 )
	end )
	if not ok or not item then
		return false
	end
	local s = tostring( item or "" )
	return string.find( s, TOOL_UUID, 1, true ) ~= nil
end

local function unitKey( unit )
	if not unit then
		return nil
	end
	local ok, id = pcall( function()
		return tostring( unit.id )
	end )
	return ok and id or nil
end

local function dist2ToPlayer( unit, player )
	if not unit or not unit.character or not sm.exists( unit.character ) then
		return math.huge
	end
	if not player or not player.character or not sm.exists( player.character ) then
		return math.huge
	end
	local a = unit.character.worldPosition
	local b = player.character.worldPosition
	return ( a - b ):length2()
end

function RfsHandheldHack.inRange( unit, player )
	local r = tonumber( RfsHandheldHack.RANGE ) or 8
	return dist2ToPlayer( unit, player ) <= r * r
end

function RfsHandheldHack.tryHack( unit, player, orderMode )
	return false, "hack parked"
end
if false then
	if not unit or not sm.exists( unit ) then
		return false, "bot gone"
	end
	if not player then
		return false, "no player"
	end
	if not RfsHandheldHack.inRange( unit, player ) then
		return false, "too far"
	end
	if RfsBotHijack.isAlly( unit ) then
		return true, "already allied"
	end
	if math.random() > RfsHandheldHack.SUCCESS_CHANCE then
		return false, "hack failed"
	end
	orderMode = string.lower( tostring( orderMode or "follow" ) )
	if orderMode ~= "follow" and orderMode ~= "defend" then
		orderMode = "follow"
	end
	local ownerId = nil
	pcall( function()
		ownerId = player.id
	end )
	local ok, msg = RfsBotHijack.convertUnit( unit, ownerId, {
		mode = "handheld",
		playerAlly = true,
		playerHandheld = true,
		hackBeaconKey = nil,
		beaconKey = nil,
		workBeaconKey = nil,
	} )
	if not ok then
		return false, msg or "convert failed"
	end
	local key = unitKey( unit )
	if key and type( RfsBotHijack.setOrder ) == "function" then
		pcall( RfsBotHijack.setOrder, unit, {
			mode = orderMode,
			owner = ownerId,
		}, player, true )
	end
	if key and RfsBotHijack.allies and RfsBotHijack.allies[key] then
		RfsBotHijack.allies[key].handheldOwner = ownerId
		RfsBotHijack.allies[key].handheldMode = orderMode
		RfsBotHijack.allies[key].inRangeStreak = RfsHandheldHack.OOR_TICKS
		RfsBotHijack.allies[key].outStreak = 0
	end
	return true, orderMode
end

function RfsHandheldHack.serverTick()
	return
end
if false then
	if type( RfsBotHijack ) ~= "table" or not RfsBotHijack.allies then
		return
	end
	local r2 = ( tonumber( RfsHandheldHack.RANGE ) or 8 ) ^ 2
	local toRevert = {}
	for key, info in pairs( RfsBotHijack.allies ) do
		if info and info.mode == "handheld" and info.controlled and not info.doomed then
			local unit = RfsBotHijack.unitByKey and RfsBotHijack.unitByKey( key )
			if unit and sm.exists( unit ) then
				local owner = nil
				pcall( function()
					if info.handheldOwner and sm.player and sm.player.getPlayerById then
						owner = sm.player.getPlayerById( info.handheldOwner )
					end
				end )
				local inRange = false
				if owner and owner.character and sm.exists( owner.character ) then
					inRange = dist2ToPlayer( unit, owner ) <= r2
				end
				if inRange then
					info.outStreak = 0
					info.inRangeStreak = RfsHandheldHack.OOR_TICKS
				else
					info.outStreak = ( info.outStreak or 0 ) + 1
					info.inRangeStreak = math.max( 0, ( info.inRangeStreak or RfsHandheldHack.OOR_TICKS ) - 1 )
					if ( info.outStreak or 0 ) >= RfsHandheldHack.OOR_TICKS then
						toRevert[#toRevert + 1] = unit
					end
				end
			end
		end
	end
	for _, unit in ipairs( toRevert ) do
		if type( RfsBotHijack.revert ) == "function" then
			pcall( RfsBotHijack.revert, unit )
		elseif type( RfsBotHijack.releaseHack ) == "function" then
			pcall( RfsBotHijack.releaseHack, unit, false )
		end
	end
end

print( "[RFS] RfsHandheldHack loaded (VOLATILE player tool 8m 40% 10s OOR)" )
