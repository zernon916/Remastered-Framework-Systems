-- RfsHackV1Host.lua
-- VOLATILE: world scriptable object so RobotSelectTarget wrap lives in the unit Lua env.
-- No per-tick convert (beacon owns that). Tick is empty.

dofile( "$CONTENT_DATA/Scripts/game/hack/RfsHackV1.lua" )

RfsHackV1Host = class( nil )

function RfsHackV1Host.server_onCreate( self )
	_G.g_rfsHackV1Host = self
	if type( RfsHackV1 ) == "table" then
		RfsHackV1.ensureUnitEnv()
	end
end

function RfsHackV1Host.server_onDestroy( self )
	if _G.g_rfsHackV1Host == self then
		_G.g_rfsHackV1Host = nil
	end
end

function RfsHackV1Host.server_onFixedUpdate( self, dt )
	if type( RfsHackV1Tick ) == "table" and RfsHackV1Tick.hostPulse then
		RfsHackV1Tick.hostPulse()
	end
end
