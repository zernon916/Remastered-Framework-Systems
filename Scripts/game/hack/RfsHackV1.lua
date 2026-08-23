-- RfsHackV1.lua
-- VOLATILE: facade for hack v1 (team + name list). Do not mix into Game.lua / Orders / hijack.
-- Other files may only dofile this and call RfsHackV1.*.

dofile( "$CONTENT_DATA/Scripts/game/hack/RfsHackV1Registry.lua" )
dofile( "$CONTENT_DATA/Scripts/game/hack/RfsHackV1Raid.lua" )
dofile( "$CONTENT_DATA/Scripts/game/hack/RfsHackV1Persist.lua" )
dofile( "$CONTENT_DATA/Scripts/game/hack/RfsHackV1Unhack.lua" )
dofile( "$CONTENT_DATA/Scripts/game/hack/RfsHackV1Timer.lua" )
dofile( "$CONTENT_DATA/Scripts/game/hack/RfsHackV1Hold.lua" )
dofile( "$CONTENT_DATA/Scripts/game/hack/RfsHackV1Fence.lua" )
dofile( "$CONTENT_DATA/Scripts/game/hack/RfsHackV1Fight.lua" )
dofile( "$CONTENT_DATA/Scripts/game/hack/RfsHackV1Convert.lua" )
dofile( "$CONTENT_DATA/Scripts/game/hack/RfsHackV1ListGui.lua" )
dofile( "$CONTENT_DATA/Scripts/game/hack/RfsHackV1Beacon.lua" )
dofile( "$CONTENT_DATA/Scripts/game/hack/RfsHackV1Tick.lua" )

RfsHackV1 = RfsHackV1 or {}

local HOST_UUID = sm.uuid.new( "b8d4f02a-3c59-4e7b-af26-7e9e1d2c3b4d" )

function RfsHackV1.serverTick( self )
	if type( RfsHackV1Beacon ) == "table" then
		RfsHackV1Beacon.serverTick( self )
	end
end

function RfsHackV1.canInteract( self )
	if type( RfsHackV1Beacon ) == "table" then
		return RfsHackV1Beacon.canInteract( self )
	end
	return false
end

function RfsHackV1.onBeaconInteract( self, character, state )
	if type( RfsHackV1Beacon ) == "table" then
		RfsHackV1Beacon.onBeaconInteract( self, character, state )
	end
end

function RfsHackV1.svBeaconOpen( self, params, player )
	if type( RfsHackV1Beacon ) == "table" then
		RfsHackV1Beacon.svOpen( self, params, player )
	end
end

function RfsHackV1.clListOpen( host, data )
	if type( RfsHackV1ListGui ) == "table" then
		RfsHackV1ListGui.open( host, data )
	end
end

function RfsHackV1.clListClose( host )
	if type( RfsHackV1ListGui ) == "table" then
		RfsHackV1ListGui.close( host )
	end
end

function RfsHackV1.clTag( host, data )
	if type( RfsHackV1Convert ) == "table" then
		RfsHackV1Convert.clApplyTag( host, data )
	end
end

function RfsHackV1.ensureUnitEnv()
	if type( RfsHackV1Convert ) == "table" then
		RfsHackV1Convert.ensureUnitEnv()
	end
end

function RfsHackV1.spawnHost( world )
	if _G.g_rfsHackV1Host and sm.exists( _G.g_rfsHackV1Host ) then
		return _G.g_rfsHackV1Host
	end
	if not world then
		return nil
	end
	local so = nil
	pcall( function()
		so = sm.scriptableObject.createScriptableObject( HOST_UUID, {}, world )
	end )
	if so then
		_G.g_rfsHackV1Host = so
	end
	return so
end

print( "[RFS] RfsHackV1 loaded (0852-p-dev release color timer)" )
