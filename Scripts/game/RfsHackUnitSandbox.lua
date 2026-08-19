-- RfsHackUnitSandbox.lua
-- VOLATILE: bootstrap hijack damage hooks inside the unit Lua sandbox after save/load.
-- Unit env re-dofiles vanilla server_onMelee; world HijackHost ensureHooks does not run here.

RfsHackUnitSandbox = RfsHackUnitSandbox or {}

local function dofileContent( path )
	pcall( function()
		dofile( path )
	end )
end

function RfsHackUnitSandbox.ensureModules()
	dofileContent( "$CONTENT_DATA/Scripts/game/RfsHackTether.lua" )
	dofileContent( "$CONTENT_DATA/Scripts/game/RfsHackApply.lua" )
	dofileContent( "$CONTENT_DATA/Scripts/game/RfsBotHijack.lua" )
end

function RfsHackUnitSandbox.ensureDamage()
	RfsHackUnitSandbox.ensureModules()
	if type( RfsHackTether ) == "table" and type( RfsHackTether.ensureHooks ) == "function" then
		pcall( RfsHackTether.ensureHooks )
	end
end

print( "[RFS] RfsHackUnitSandbox loaded (unit-env damage bootstrap)" )
