-- RfsHackV1Fight.lua
-- VOLATILE: vanilla unit AI. No orders/stay/recall.
-- saved.friendly is NOT used — that early-returns RobotSelectTarget and they never fight.
-- Stolen bots hunt other hostile robots (the wave), not the player as default aggro.
-- Survival ignores unit-vs-unit melee/tape; we APPLY those hits (no absorb, no immunity).
--
-- Flee root cause (raid-only v1): onApply only flipped raider=false, then still ran vanilla
-- RobotSelectTarget (player aggro) and a weak post-retarget. With no hostile lock and
-- leftover raidPosition/home at spawn, bots path/avoid away from the fight. Fix:
-- full standDown + skip vanilla Select for stolen + hunt hostiles in range.

RfsHackV1Fight = RfsHackV1Fight or {}

local HUNT_RANGE = 40
local TAG_EVERY = 20
local ALLY_TINT_HEX = "3dff8aff"
local UNIT_CLASSES = {
	"HaybotUnit", "FarmbotUnit", "TapebotUnit",
	"TotebotGreenUnit", "TotebotRedUnit", "TotebotYellowUnit",
	"TotebotBlueUnit", "TotebotLeafUnit",
}

local function isPlayerChar( char )
	if not char then
		return false
	end
	local isP = false
	pcall( function()
		isP = char:isPlayer() and true or false
	end )
	return isP
end

local function isRobotChar( char )
	if type( RfsHackV1Convert ) == "table" and RfsHackV1Convert.isHackableRobot then
		return RfsHackV1Convert.isHackableRobot( char )
	end
	return false
end

local function isStolenUnit( unit )
	if type( RfsHackV1Registry ) == "table" then
		return RfsHackV1Registry.isAlly( unit ) and true or false
	end
	return false
end

local function stolenSelf( self )
	return type( self ) == "table" and self.saved and self.saved.rfsHackV1BeaconKey and self.saved.rfsHackV1BeaconKey ~= ""
end

local function normalizeHex( hex )
	if hex == nil then
		return nil
	end
	local s = string.lower( tostring( hex ):gsub( "^#", "" ):gsub( "%s+", "" ) )
	if s == "" then
		return nil
	end
	if not string.match( s, "^%x%x%x%x%x%x%x%x$" ) and not string.match( s, "^%x%x%x%x%x%x$" ) then
		return nil
	end
	if #s == 6 then
		s = s .. "ff"
	end
	return s
end

local function colorFromHex( hex )
	hex = normalizeHex( hex )
	if not hex then
		return nil
	end
	local col
	local ok = pcall( function()
		col = sm.color.new( hex )
	end )
	if ok and col then
		return col
	end
	ok = pcall( function()
		col = sm.color.new( "#" .. hex )
	end )
	if ok and col then
		return col
	end
	return nil
end

local function colorToHex( col )
	if col == nil then
		return nil
	end
	if type( col ) == "string" then
		return normalizeHex( col )
	end
	local hex = nil
	pcall( function()
		if type( col.getHexStr ) == "function" then
			local h = col:getHexStr()
			if type( h ) == "string" and #h >= 6 then
				hex = normalizeHex( h )
			end
		end
	end )
	if hex then
		return hex
	end
	pcall( function()
		hex = normalizeHex( tostring( col ) )
	end )
	return hex
end

local function snapshotPreHackHex( self )
	self.saved = self.saved or {}
	local ally = normalizeHex( ALLY_TINT_HEX )
	local candidates = {
		self.saved.rfsHackV1PrevColor,
		self.saved.color,
	}
	local char = self.unit and self.unit.character
	if char and sm.exists( char ) then
		pcall( function()
			candidates[#candidates + 1] = char.color
		end )
		pcall( function()
			if char.getColor then
				candidates[#candidates + 1] = char:getColor()
			end
		end )
	end
	for i = 1, #candidates do
		local hex = colorToHex( candidates[i] )
		if hex and hex ~= ally then
			return hex
		end
	end
	return nil
end

function RfsHackV1Fight.allyTintHex()
	return ALLY_TINT_HEX
end

function RfsHackV1Fight.applyTint( self, hex )
	if not stolenSelf( self ) and not ( type( self ) == "table" and self.unit ) then
		return
	end
	hex = normalizeHex( hex ) or ALLY_TINT_HEX
	local col = colorFromHex( hex )
	if not col then
		return
	end
	self.saved = self.saved or {}
	-- Capture pre-hack color ONCE before any ally tint. Second applyTint used to
	-- see saved.color already green and store green as PrevColor → sticky tint.
	if self.saved.rfsHackV1PrevColor == nil then
		local prevHex = snapshotPreHackHex( self )
		if prevHex then
			self.saved.rfsHackV1PrevColor = prevHex
		end
	end
	self.saved.rfsAllyColor = hex
	self.saved.color = col
	self.isDirty = true
	local char = self.unit and self.unit.character
	if char and sm.exists( char ) then
		pcall( function()
			char:setColor( col )
		end )
		pcall( function()
			char.color = col
		end )
	end
end

function RfsHackV1Fight.clearTint( self )
	if type( self ) ~= "table" then
		return
	end
	self.saved = self.saved or {}
	local prevHex = colorToHex( self.saved.rfsHackV1PrevColor )
	local prev = prevHex and colorFromHex( prevHex ) or nil
	if not prev and self.saved.rfsHackV1PrevColor ~= nil and type( self.saved.rfsHackV1PrevColor ) ~= "string" then
		prev = self.saved.rfsHackV1PrevColor
	end
	self.saved.rfsAllyColor = nil
	self.saved.rfsHackV1PrevColor = nil
	self.saved.color = prev
	self.isDirty = true
	local char = self.unit and self.unit.character
	if char and sm.exists( char ) and prev then
		pcall( function()
			char:setColor( prev )
		end )
		pcall( function()
			char.color = prev
		end )
	end
end

-- Abort raid wall-smash / plot pathing so stolen bots do not walk spawn→home or smash the base.
function RfsHackV1Fight.standDown( self )
	if type( self ) ~= "table" then
		return
	end
	self.saved = self.saved or {}
	local dirty = false
	local raidKey = self.saved.raidKey
	if raidKey and self.unit then
		pcall( function()
			if type( RaidManager ) == "table" and RaidManager.Sv_RemoveRaider then
				RaidManager.Sv_RemoveRaider( raidKey, self.unit )
			end
		end )
		self.saved.raidKey = nil
		dirty = true
	end
	if self.saved.raider then
		self.saved.raider = false
		dirty = true
	end
	if self.saved.raidPosition ~= nil then
		self.saved.raidPosition = nil
		dirty = true
	end
	if self.saved.raidCenter ~= nil then
		self.saved.raidCenter = nil
		dirty = true
	end
	if self.saved.destroyShapes then
		self.saved.destroyShapes = false
		dirty = true
	end
	if self.saved.randomPlotTarget ~= nil then
		self.saved.randomPlotTarget = nil
		dirty = true
	end
	if dirty then
		self.isDirty = true
	end
	pcall( function()
		if self.pathingState and self.pathingState.sv_setRaider then
			self.pathingState:sv_setRaider( false )
		end
	end )
	local char = self.unit and self.unit.character
	if char and sm.exists( char ) then
		self.homePosition = char.worldPosition
	end
	local smash = self.currentState
		and ( self.currentState == self.breachState
			or self.currentState == self.voxelBreachState
			or self.currentState == self.raidPathingState
			or self.currentState == self.raidRepositionState
			or self.currentState == self.raidFlee )
	if smash then
		pcall( function()
			if self.currentState and self.currentState.stop then
				self.currentState:stop()
			end
		end )
		self.currentState = self.idleState or self.pathingState or self.currentState
		pcall( function()
			if self.currentState and self.currentState.start then
				self.currentState:start()
			end
		end )
	end
end

function RfsHackV1Fight.retarget( self )
	if not stolenSelf( self ) or not self.unit then
		return
	end
	local myChar = self.unit.character
	if not myChar or not sm.exists( myChar ) then
		return
	end
	-- Keep raid smash aborted while held.
	if self.saved.raider or self.saved.raidPosition or self.saved.raidKey then
		RfsHackV1Fight.standDown( self )
	end
	local tgt = self.target
	if tgt and isPlayerChar( tgt ) then
		self.target = nil
		tgt = nil
	end
	if tgt and sm.exists( tgt ) then
		local alreadyRobot = false
		pcall( function()
			alreadyRobot = isRobotChar( tgt ) and true or false
		end )
		if alreadyRobot then
			local stolenTgt = false
			pcall( function()
				local pd = tgt.publicData
				stolenTgt = type( pd ) == "table" and type( pd.rfsHackV1 ) == "table" and pd.rfsHackV1.ally == true
			end )
			if stolenTgt then
				self.target = nil
			else
				-- Keep combat heat so approach/attack states stay engaged.
				if self.combatTicks and self.combatTicksBerserk then
					self.combatTicks = math.max( self.combatTicks, self.combatTicksBerserk )
				end
				return
			end
		else
			self.target = nil
		end
	end
	local pos = myChar.worldPosition
	local world = myChar:getWorld()
	local units
	local heightMul = 3.75
	pcall( function()
		if HEIGHT_DISTANCE_MULTIPLIER then
			heightMul = HEIGHT_DISTANCE_MULTIPLIER
		end
	end )
	pcall( function()
		units = sm.unit.getUnitsInRange( world, pos, HUNT_RANGE, heightMul )
	end )
	if type( units ) ~= "table" then
		pcall( function()
			units = sm.unit.getAllUnits( world )
		end )
	end
	if type( units ) ~= "table" then
		self.target = nil
		self.lastTargetPosition = nil
		return
	end
	local best, bestD2
	local maxD2 = HUNT_RANGE * HUNT_RANGE
	for i = 1, #units do
		local u = units[i]
		if u and u ~= self.unit and sm.exists( u ) then
			local char = u.character
			if char and sm.exists( char ) and isRobotChar( char ) and not isStolenUnit( u ) then
				local d2 = ( char.worldPosition - pos ):length2()
				if d2 <= maxD2 and ( not bestD2 or d2 < bestD2 ) then
					best = char
					bestD2 = d2
				end
			end
		end
	end
	if best then
		self.target = best
		self.lastTargetPosition = best.worldPosition
		if self.combatTicks and self.combatTicksBerserk then
			self.combatTicks = math.max( self.combatTicks, self.combatTicksBerserk )
		end
	else
		self.target = nil
		self.lastTargetPosition = nil
	end
end

function RfsHackV1Fight.pulseTag( self )
	if not stolenSelf( self ) or not self.unit then
		return
	end
	if type( RfsHackV1Unhack ) == "table" then
		if RfsHackV1Unhack.isPending and RfsHackV1Unhack.isPending( self.unit ) then
			return
		end
		if RfsHackV1Unhack.isFusing and RfsHackV1Unhack.isFusing( self.unit ) then
			return
		end
	end
	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick() or 0
	end )
	local last = tonumber( self._rfsHackV1TagTick ) or -TAG_EVERY
	if ( tick - last ) < TAG_EVERY then
		return
	end
	self._rfsHackV1TagTick = tick
	local unhackAt = tonumber( self.saved and self.saved.rfsHackV1UnhackAt )
	if not unhackAt and type( RfsHackV1Registry ) == "table" and RfsHackV1Registry.read then
		local blob = RfsHackV1Registry.read( self.unit )
		unhackAt = blob and tonumber( blob.unhackAt )
	end
	local text = "HACKED"
	if type( RfsHackV1Hold ) == "table" and RfsHackV1Hold.releaseTagText then
		text = RfsHackV1Hold.releaseTagText( unhackAt, tick )
	elseif unhackAt then
		local left = math.max( 0, math.ceil( ( unhackAt - tick ) / 40 ) )
		text = string.format( "HACKED %d:%02d", math.floor( left / 60 ), left % 60 )
	end
	if type( RfsHackV1Convert ) == "table" and RfsHackV1Convert.pushTag then
		RfsHackV1Convert.pushTag( self.unit, text )
	end
end

local function unitShouldHurt( self, attacker )
	if type( attacker ) ~= "Unit" then
		return false
	end
	if stolenSelf( self ) then
		return true
	end
	return isStolenUnit( attacker )
end

local function applyUnitHit( self, attacker, damage, impact, hitPos )
	if not self or not attacker then
		return
	end
	pcall( function()
		if self.sv_addStagger and self.staggerMelee then
			self:sv_addStagger( self.staggerMelee )
		end
	end )
	pcall( function()
		if self.eventTarget == nil then
			local ac = attacker.character
			if ac and sm.exists( ac ) then
				self.eventTarget = ac
			end
		end
	end )
	pcall( function()
		if self.combatTicks and self.combatTicksBerserk then
			self.combatTicks = math.max( self.combatTicks, self.combatTicksBerserk )
		end
	end )
	pcall( function()
		self:sv_takeDamage( damage, impact, hitPos )
	end )
end

local function stampRaidPulse( self )
	if type( self ) ~= "table" or not self.saved then
		return
	end
	if not ( self.saved.raider or self.saved.raidKey ) then
		return
	end
	local char = self.unit and self.unit.character
	if not char or not sm.exists( char ) then
		return
	end
	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick() or 0
	end )
	pcall( function()
		local pd = char.publicData
		if type( pd ) ~= "table" then
			pd = {}
		end
		pd.rfsRaidPulse = tick
		char.publicData = pd
	end )
end

function RfsHackV1Fight.ensureUnitEnv()
	for i = 1, #UNIT_CLASSES do
		local cls = _G[UNIT_CLASSES[i]]
		if type( cls ) == "table" and not cls._rfsHackV1Fight then
			cls._rfsHackV1Fight = true
			local origMelee = cls.server_onMelee
			cls.server_onMelee = function( self, hitPos, attacker, damage, power, hitDirection )
				if unitShouldHurt( self, attacker ) then
					local impact = hitDirection
					pcall( function()
						impact = hitDirection * 6
					end )
					applyUnitHit( self, attacker, damage, impact, hitPos )
				end
				if origMelee then
					return origMelee( self, hitPos, attacker, damage, power, hitDirection )
				end
			end
			local origProj = cls.server_onProjectile
			cls.server_onProjectile = function( self, hitPos, hitTime, hitVelocity, n, attacker, damage, userData, hitNormal, projectileUuid )
				if unitShouldHurt( self, attacker ) and damage and damage > 0 then
					local impact
					pcall( function()
						impact = hitVelocity:normalize() * 6
					end )
					applyUnitHit( self, attacker, damage, impact, hitPos )
				end
				if origProj then
					return origProj( self, hitPos, hitTime, hitVelocity, n, attacker, damage, userData, hitNormal, projectileUuid )
				end
			end
			local origFU = cls.server_onFixedUpdate
			cls.server_onFixedUpdate = function( self, dt )
				local t = 0
				pcall( function()
					t = sm.game.getCurrentTick() or 0
				end )
				if ( t % 16 ) == 0 then
					stampRaidPulse( self )
				end
				if stolenSelf( self ) then
					if ( t % 20 ) == 0 then
						RfsHackV1Fight.pulseTag( self )
					end
					if ( t % 40 ) == 0 then
						RfsHackV1Fight.applyTint( self, self.saved and self.saved.rfsAllyColor or ALLY_TINT_HEX )
					end
				end
				if origFU then
					return origFU( self, dt )
				end
			end
		end
	end
end

print( "[RFS] RfsHackV1Fight loaded (0852-p tint restore + hold timer tag)" )
