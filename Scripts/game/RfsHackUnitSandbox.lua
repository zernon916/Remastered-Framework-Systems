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
	-- 0851-r: live hack parked — do not re-dofile hijack into the unit sandbox.
	return
end

function RfsHackUnitSandbox.ensureDamage()
	return
end

print( "[RFS] RfsHackUnitSandbox loaded (unit-env damage bootstrap, parked)" )
