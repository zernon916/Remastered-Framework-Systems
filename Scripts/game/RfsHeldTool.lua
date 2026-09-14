-- Shared in-hand setup copied from the working GPS (SpikeHand) / vanilla Eat.lua.
-- A held item is THREE renderables: male eat-tool arms + item position + skinned DAE.
-- File-scope dofile only (engine refuses dofile from inside a function).

dofile( "$GAME_DATA/Scripts/game/AnimationUtil.lua" )

RfsHeldTool = RfsHeldTool or {}

local ARMFP = "$SURVIVAL_DATA/Character/Char_Male/Animations/char_male_fp_eattool.rend"
local ARMTP = "$SURVIVAL_DATA/Character/Char_Male/Animations/char_male_tp_eattool.rend"
local POSFP = "$SURVIVAL_DATA/Character/Char_Tools/Char_eattool/char_eattool_fp.rend"
local POSTP = "$SURVIVAL_DATA/Character/Char_Tools/Char_eattool/char_eattool_tp.rend"

local TPMOVE = {
	idle = "Idle",
	runFwd = "Run_fwd",
	runBwd = "Run_bwd",
	sprint = "Sprint_fwd",
	sprintLeft = "Sprint_left",
	sprintRight = "Sprint_right",
	jump = "Jump",
	jumpUp = "Jump_up",
	jumpDown = "Jump_down",
	land = "Jump_land",
	landFwd = "Jump_land_fwd",
	landBwd = "Jump_land_bwd",
	landLeft = "Jump_land_left",
	landRight = "Jump_land_right",
	crouchIdle = "Crouch_idle",
	crouchFwd = "Crouch_fwd",
	crouchBwd = "Crouch_bwd",
}

sm.tool.preloadRenderables( { ARMTP, POSTP } )
sm.tool.preloadRenderables( { ARMFP, POSFP } )

function RfsHeldTool.setup( self, fpRend, tpRend )
	local function step( fn )
		local ok, err = pcall( fn )
		return ok, err
	end

	if type( createFpAnimations ) ~= "function" or type( updateTpAnimations ) ~= "function" then
		return
	end

	step( function()
		self.tool:setTpRenderables( { ARMTP, POSTP, tpRend } )
	end )
	step( function()
		self.tpAnimations = createTpAnimations( self.tool, {
			idle = { "Idle" },
			pickup = { "Pickup", { nextAnimation = "idle" } },
			putdown = { "Putdown" },
		} )
		for name, animation in pairs( TPMOVE ) do
			self.tool:setMovementAnimation( name, animation )
		end
		setTpAnimation( self.tpAnimations, "pickup", 0.0001 )
	end )

	if self.tool:isLocal() then
		local fpOk = step( function()
			self.tool:setFpRenderables( { ARMFP, POSFP, fpRend } )
		end )
		if not fpOk then
			step( function()
				self.tool:setFpRenderables( { fpRend } )
			end )
		end
		step( function()
			self.fpAnimations = createFpAnimations( self.tool, {
				idle = { "Idle", { looping = true } },
				sprintInto = { "Sprint_into", { nextAnimation = "sprintIdle", blendNext = 0.2 } },
				sprintIdle = { "Sprint_idle", { looping = true } },
				sprintExit = { "Sprint_exit", { nextAnimation = "idle", blendNext = 0 } },
				jump = { "Jump", { nextAnimation = "idle" } },
				land = { "Jump_land", { nextAnimation = "idle" } },
				equip = { "Pickup", { nextAnimation = "idle" } },
				unequip = { "Putdown" },
			} )
			swapFpAnimation( self.fpAnimations, "unequip", "equip", 0.2 )
		end )
	end

	self.heldOk = true
	self.blendTime = 0.2
	self.wasOnGround = true
end

function RfsHeldTool.update( self, dt )
	if not self.heldOk then
		return
	end
	pcall( function()
		if self.tool:isLocal() and self.fpAnimations then
			local isSprinting = self.tool:isSprinting()
			local isOnGround = self.tool:isOnGround()
			local cur = self.fpAnimations.currentAnimation
			if self.equipped then
				if isSprinting and cur ~= "sprintInto" and cur ~= "sprintIdle" then
					swapFpAnimation( self.fpAnimations, "sprintExit", "sprintInto", 0.0 )
				elseif not isSprinting and ( cur == "sprintIdle" or cur == "sprintInto" ) then
					swapFpAnimation( self.fpAnimations, "sprintInto", "sprintExit", 0.0 )
				end
				if not isOnGround and self.wasOnGround and cur ~= "jump" then
					swapFpAnimation( self.fpAnimations, "land", "jump", 0.02 )
				elseif isOnGround and not self.wasOnGround and cur ~= "land" then
					swapFpAnimation( self.fpAnimations, "jump", "land", 0.02 )
				end
			end
			self.wasOnGround = isOnGround
			updateFpAnimations( self.fpAnimations, self.equipped == true, dt )
		end
		if self.tpAnimations then
			updateTpAnimations( self.tpAnimations, self.equipped == true, dt )
		end
	end )
end

function RfsHeldTool.unequip( self )
	if not self.heldOk then
		return
	end
	pcall( function()
		setTpAnimation( self.tpAnimations, "putdown" )
		if self.tool:isLocal() and self.fpAnimations and self.fpAnimations.currentAnimation ~= "unequip" then
			swapFpAnimation( self.fpAnimations, "equip", "unequip", 0.2 )
		end
	end )
end
