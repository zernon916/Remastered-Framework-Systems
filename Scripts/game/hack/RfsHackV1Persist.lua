-- RfsHackV1Persist.lua
-- VOLATILE: unit.saved is source of truth after save/load. publicData is session cache.
-- No pet names. No chain. No Game.lua / beacon overlap.

RfsHackV1Persist = RfsHackV1Persist or {}

local function stampPublic( self )
	if type( self ) ~= "table" or not self.unit then
		return
	end
	self.saved = self.saved or {}
	local key = self.saved.rfsHackV1BeaconKey
	if not key or key == "" then
		return
	end
	local blob = {
		ally = true,
		beaconKey = tostring( key ),
		unhackAt = tonumber( self.saved.rfsHackV1UnhackAt ),
		cap = tonumber( self.saved.rfsHackV1Cap ) or 2,
	}
	local function applyPd( pd )
		if type( pd ) ~= "table" then
			pd = {}
		end
		pd.rfsHackV1 = blob
		return pd
	end
	pcall( function()
		local char = self.unit.character
		if char and sm.exists( char ) then
			char.publicData = applyPd( char.publicData )
		end
	end )
	pcall( function()
		self.unit.publicData = applyPd( self.unit.publicData )
	end )
end

local function clearPublic( self )
	local function wipe( pd )
		if type( pd ) == "table" then
			pd.rfsHackV1 = nil
		end
		return pd
	end
	pcall( function()
		local char = self.unit and self.unit.character
		if char and sm.exists( char ) then
			char.publicData = wipe( char.publicData )
		end
	end )
	pcall( function()
		if self.unit then
			self.unit.publicData = wipe( self.unit.publicData )
		end
	end )
end

function RfsHackV1Persist.onApply( self, params )
	if type( self ) ~= "table" then
		return
	end
	params = params or {}
	self.saved = self.saved or {}
	-- Do not set saved.friendly — that no-ops RobotSelectTarget (no wave fighting).
	self.saved.friendly = false
	self.saved.rfsHackV1Name = nil
	if params.beaconKey then
		self.saved.rfsHackV1BeaconKey = tostring( params.beaconKey )
	end
	if params.unhackAt then
		self.saved.rfsHackV1UnhackAt = tonumber( params.unhackAt )
	end
	if params.cap then
		self.saved.rfsHackV1Cap = tonumber( params.cap ) or 2
	end
	-- Full standDown: clearing only raider left raidPosition/home → bots path away ("flee").
	if type( RfsHackV1Fight ) == "table" and RfsHackV1Fight.standDown then
		RfsHackV1Fight.standDown( self )
	else
		self.saved.raider = false
	end
	if type( RfsHackV1Fight ) == "table" and RfsHackV1Fight.applyTint then
		RfsHackV1Fight.applyTint( self, RfsHackV1Fight.allyTintHex and RfsHackV1Fight.allyTintHex() or "3dff8aff" )
	end
	self.isDirty = true
	self.target = nil
	self.lastTargetPosition = nil
	self.eventTarget = nil
	self._rfsHackV1Hydrated = true
	stampPublic( self )
	if type( RfsHackV1Fight ) == "table" and RfsHackV1Fight.retarget then
		RfsHackV1Fight.retarget( self )
	end
	if type( RfsHackV1Convert ) == "table" and RfsHackV1Convert.pushTag and self.unit then
		local tick = 0
		pcall( function()
			tick = sm.game.getCurrentTick() or 0
		end )
		local holdText = "HACKED"
		if type( RfsHackV1Hold ) == "table" and RfsHackV1Hold.releaseTagText then
			holdText = RfsHackV1Hold.releaseTagText( self.saved.rfsHackV1UnhackAt, tick )
		end
		RfsHackV1Convert.pushTag( self.unit, holdText )
	end
end

function RfsHackV1Persist.onRevert( self, params )
	if type( self ) ~= "table" then
		return
	end
	self.saved = self.saved or {}
	self.saved.friendly = false
	self.saved.rfsHackV1Name = nil
	self.saved.rfsHackV1BeaconKey = nil
	self.saved.rfsHackV1UnhackAt = nil
	self.saved.rfsHackV1Cap = nil
	if type( RfsHackV1Fight ) == "table" and RfsHackV1Fight.clearTint then
		RfsHackV1Fight.clearTint( self )
	end
	self.isDirty = true
	self._rfsHackV1Hydrated = nil
	clearPublic( self )
	if self.unit and type( RfsHackV1Convert ) == "table" and RfsHackV1Convert.clearTag then
		RfsHackV1Convert.clearTag( self.unit )
	end
end

function RfsHackV1Persist.onSync( self, params )
	RfsHackV1Persist.hydrateSelf( self )
end

function RfsHackV1Persist.hydrateSelf( self )
	if type( self ) ~= "table" then
		return
	end
	self.saved = self.saved or {}
	self.saved.rfsHackV1Name = nil
	local key = self.saved.rfsHackV1BeaconKey
	if not key or key == "" then
		return
	end
	-- Raid-end SELF DESTRUCT fuse owns this unit until boom — do not revert/retag.
	if self.unit and type( RfsHackV1Unhack ) == "table" and RfsHackV1Unhack.isFusing
		and RfsHackV1Unhack.isFusing( self.unit ) then
		return
	end
	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick() or 0
	end )
	local unhackAt = tonumber( self.saved.rfsHackV1UnhackAt )
	local grace = 80
	if type( RfsHackV1Unhack ) == "table" and RfsHackV1Unhack.telegraphTicks then
		grace = RfsHackV1Unhack.telegraphTicks()
	end
	if unhackAt and tick >= unhackAt + grace then
		RfsHackV1Persist.onRevert( self )
		return
	end
	local raid = false
	if type( RfsHackV1Raid ) == "table" and RfsHackV1Raid.isActive then
		local pos, world
		pcall( function()
			local char = self.unit and self.unit.character
			if char and sm.exists( char ) then
				pos = char.worldPosition
				world = char:getWorld()
			end
		end )
		if pos then
			raid = RfsHackV1Raid.isActive( pos, world ) and true or false
		end
	end
	if not raid then
		RfsHackV1Persist.onRevert( self )
		return
	end
	self.saved.friendly = false
	if type( RfsHackV1Fight ) == "table" and RfsHackV1Fight.standDown then
		RfsHackV1Fight.standDown( self )
	else
		self.saved.raider = false
	end
	if type( RfsHackV1Fight ) == "table" and RfsHackV1Fight.applyTint then
		RfsHackV1Fight.applyTint( self, self.saved.rfsAllyColor or ( RfsHackV1Fight.allyTintHex and RfsHackV1Fight.allyTintHex() ) or "3dff8aff" )
	end
	self.isDirty = true
	stampPublic( self )
	self._rfsHackV1Hydrated = true
end

function RfsHackV1Persist.touch( unit )
	if not unit or not sm.exists( unit ) then
		return
	end
	pcall( function()
		sm.event.sendToUnit( unit, "sv_e_rfsHackV1Sync", {} )
	end )
end

function RfsHackV1Persist.nudgeWorld( world )
	local units
	if world then
		pcall( function()
			units = sm.unit.getAllUnits( world )
		end )
	end
	if type( units ) ~= "table" then
		return
	end
	for i = 1, #units do
		local u = units[i]
		if u and sm.exists( u ) then
			if not ( type( RfsHackV1Registry ) == "table" and RfsHackV1Registry.read( u ) ) then
				RfsHackV1Persist.touch( u )
			end
		end
	end
end

function RfsHackV1Persist.deferList( player, beaconKey, world )
end

function RfsHackV1Persist.hostTick()
end
