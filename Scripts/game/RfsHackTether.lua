-- RfsHackTether.lua
-- OWNER: hijacked-bot damage callbacks (player/shape hits must apply Survival orig).
-- FROZEN: hijack damage. Do not set invulnerable or strip hit callbacks unless the user explicitly asks.
-- Rush-base: hacked bots take melee/projectile/explosion damage. Player/Shape always call orig.
-- Unit-vs-unit faction wrap still applies Survival-ignored unit hits, then noteMeleeChain.

RfsHackTether = RfsHackTether or {}
rfsHackTether = RfsHackTether

local _wrapped = _wrapped or {}

local UNIT_CLASSES = {
	"TotebotGreenUnit", "TotebotBlueUnit", "TotebotRedUnit", "TotebotLeafUnit",
	"TotebotYellowUnit", "HaybotUnit", "FarmbotUnit", "TapebotUnit",
	"MinerbotUnit", "CablebotUnit", "LootbotUnit", "SeedbotUnit",
	"BaseTotebotUnit", "TrashbotUnit",
}

local function isPlayerAttacker( attacker )
	if type( attacker ) == "Player" then
		return true
	end
	if type( attacker ) == "Character" then
		local isP = false
		pcall( function()
			isP = attacker:isPlayer() and true or false
		end )
		return isP
	end
	return false
end

-- Player hammer (Shape), potato gun (Character), and direct Player hits must all
-- apply sv_takeDamage — vanilla orig ignores named allies for every player type.
local function isPlayerSideAttacker( attacker )
	if type( attacker ) == "Player" or type( attacker ) == "Shape" then
		return true
	end
	return isPlayerAttacker( attacker )
end

local function unitFromAttacker( attacker )
	if not attacker then
		return nil
	end
	local okEx, exists = pcall( sm.exists, attacker )
	if okEx and exists == false then
		return nil
	end
	local t = type( attacker )
	if t == "Player" or t == "Shape" then
		return nil
	end
	if t == "Unit" then
		return attacker
	end
	if t == "Character" then
		local isPlayer = false
		pcall( function()
			isPlayer = attacker:isPlayer() and true or false
		end )
		if isPlayer then
			return nil
		end
		local ok, u = pcall( function()
			return attacker:getUnit()
		end )
		if ok and u then
			return u
		end
	end
	return nil
end

local function opposingFactions( unitA, unitB )
	if not unitA or not unitB then
		return false
	end
	if type( RfsBotHijack ) ~= "table" or not RfsBotHijack.isAlly then
		return false
	end
	return RfsBotHijack.isAlly( unitA ) ~= RfsBotHijack.isAlly( unitB )
end

local function applyFactionDamage( self, damage, impact, hitPos )
	if type( self.sv_takeDamage ) ~= "function" then
		return
	end
	damage = tonumber( damage ) or 10
	if damage <= 0 then
		damage = 10
	end
	impact = impact or sm.vec3.new( 0, 0, 1 )
	hitPos = hitPos or ( self.unit and self.unit.character and self.unit.character.worldPosition )
	pcall( function()
		if self.sv_addStagger then
			self:sv_addStagger( 0.35 )
		end
	end )
	pcall( function()
		self:sv_takeDamage( damage, impact, hitPos )
	end )
end

local function wrapFn( cls, name, make )
	local orig = cls[name]
	if type( orig ) ~= "function" then
		return
	end
	local existing = _wrapped[orig]
	if existing then
		if cls[name] ~= existing then
			cls[name] = existing
		end
		return
	end
	local wrapped = make( orig )
	_wrapped[orig] = wrapped
	_wrapped[wrapped] = wrapped
	cls[name] = wrapped
end

function RfsHackTether.ensureHooks()
	for _, className in ipairs( UNIT_CLASSES ) do
		local cls = _G[className]
		if type( cls ) == "table" then
			wrapFn( cls, "server_onMelee", function( orig )
				return function( self, hitPos, attacker, damage, power, hitDirection )
					if isPlayerSideAttacker( attacker ) then
						pcall( orig, self, hitPos, attacker, damage, power, hitDirection )
						local impact = hitDirection
						if impact then
							impact = impact * 6
						end
						applyFactionDamage( self, damage, impact, hitPos )
						return
					end
					local atk = unitFromAttacker( attacker )
					if atk and self.unit and opposingFactions( self.unit, atk ) then
						local impact = hitDirection
						if impact then
							impact = impact * 6
						end
						applyFactionDamage( self, damage, impact, hitPos )
						pcall( function()
							if type( RfsBotHijack ) == "table" and RfsBotHijack.noteMeleeChain then
								RfsBotHijack.noteMeleeChain( atk, self.unit )
							end
						end )
						return
					end
					return orig( self, hitPos, attacker, damage, power, hitDirection )
				end
			end )

			wrapFn( cls, "server_onProjectile", function( orig )
				return function( self, hitPos, hitTime, hitVelocity, extra, attacker, damage, userData, hitNormal, projectileUuid )
					if isPlayerSideAttacker( attacker ) then
						pcall( orig, self, hitPos, hitTime, hitVelocity, extra, attacker, damage, userData, hitNormal, projectileUuid )
						local impact = nil
						if hitVelocity then
							pcall( function()
								impact = hitVelocity:normalize() * 6
							end )
						end
						applyFactionDamage( self, damage, impact, hitPos )
						return
					end
					local atk = unitFromAttacker( attacker )
					if atk and self.unit and opposingFactions( self.unit, atk ) then
						local impact = nil
						if hitVelocity then
							pcall( function()
								impact = hitVelocity:normalize() * 6
							end )
						end
						applyFactionDamage( self, damage, impact, hitPos )
						return
					end
					return orig( self, hitPos, hitTime, hitVelocity, extra, attacker, damage, userData, hitNormal, projectileUuid )
				end
			end )

			wrapFn( cls, "server_onExplosion", function( orig )
				return function( self, center, destructionLevel )
					return orig( self, center, destructionLevel )
				end
			end )
		end
	end
end

print( "[RFS] RfsHackTether loaded (frozen hijack damage)" )
