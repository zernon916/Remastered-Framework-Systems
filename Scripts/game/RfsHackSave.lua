-- RfsHackSave.lua
-- OWNER: beacon storage (role / masterKey). Unit customName lives on hijack + Orders payload.
-- FROZEN: persistence shape. Do not retune spend from here.

RfsHackSave = RfsHackSave or {}
rfsHackSave = RfsHackSave

function RfsHackSave.load( self )
	self.sv = self.sv or {}
	local loaded = nil
	pcall( function()
		loaded = self.storage:load()
	end )
	if type( loaded ) == "table" then
		self.sv.role = loaded.role or "independent"
		self.sv.masterKey = loaded.masterKey
	else
		self.sv.role = "independent"
		self.sv.masterKey = nil
	end
end

function RfsHackSave.saveRole( self )
	if not self or not self.storage then
		return
	end
	pcall( function()
		self.storage:save( {
			role = self.sv and self.sv.role or "independent",
			masterKey = self.sv and self.sv.masterKey or nil,
		} )
	end )
end

print( "[RFS] RfsHackSave loaded (frozen beacon role persist)" )
