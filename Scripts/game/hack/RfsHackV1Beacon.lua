-- RfsHackV1Beacon.lua
-- VOLATILE: tick only. E / list GUI disabled (bots are unnamed and short-lived).

RfsHackV1Beacon = RfsHackV1Beacon or {}

function RfsHackV1Beacon.serverTick( self )
	if type( RfsHackV1Convert ) == "table" then
		RfsHackV1Convert.tickBeacon( self )
	end
end

function RfsHackV1Beacon.canInteract( self )
	return false
end

function RfsHackV1Beacon.onBeaconInteract( self, character, state )
end

function RfsHackV1Beacon.svOpen( self, params, player )
end
