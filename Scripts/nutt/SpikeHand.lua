-- GPS hand tool (production): LMB opens the world map, RMB cycles the
-- Vendored into Remastered Framework Survival with permission. Credit: Nutt
-- (Steam Workshop 3780282057).
-- minimap zoom, Q toggles the map. The gui callbacks below MUST live on
-- this class: jsonGui dispatch binds to the script whose call chain
-- created the gui, and the map opens from this tool's input handlers.
SpikeHand = class()

-- Runtime .rend / ImageTexture do not resolve $CONTENT_DATA.
local C = "$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247"

-- SANDBOX RULE, learned the hard way on build 8 (held_probe.json said
-- "Can't 'dofile' from a non root call site"): dofile works ONLY at file scope
-- during script load - never from inside a function. Both of these were in
-- client_onCreate at first, failed, and took the whole held-device chain with
-- them. Vanilla Eat.lua has its AnimationUtil dofile on line 1 for this reason.
-- Unguarded on purpose: pcall wrapping adds a call frame and is itself a
-- non-root call site. MinimapHud makes the identical Flags call and works.
dofile(C .. "/Scripts/nutt/Flags.lua")
-- animation helpers as globals: createTpAnimations / createFpAnimations /
-- setTpAnimation / setFpAnimation / swapFpAnimation / updateFpAnimations /
-- updateTpAnimations. A GAME_DATA path, so it resolves for mods.
dofile("$GAME_DATA/Scripts/game/AnimationUtil.lua")

-- ------------------------------------------------------- HELD DEVICE -------
-- Holding the GPS in hand with the vanilla idle sway. GROUND TRUTH read out of
-- the game files, Survival/Scripts/game/tools/Eat.lua being the reference (it
-- is the tea/burger item Eric pointed at):
--
--   * a held item is THREE renderables in ONE list -
--       [ arm animation list, item POSITION animation, the item MESH ]
--     FP: char_male_fp_eattool.rend + char_eattool_fp.rend + <food>.rend
--
--   * THE ITEM MESH IS SKINNED. (The first read of this - ".rend has no
--     includes, so no rig" - was WRONG and cost builds 10-12.) The rig lives in
--     the SOURCE MESH: char_eattool_carrot.dae carries a <library_controllers>
--     skin controller and JOINT nodes jnt_right_weapon -> root_item, with the
--     mesh skinned 100% to root_item. tools/make_held_dae.py reproduces exactly
--     that, in Collada - the engine ignores FBX skinning (build 14). We still borrow EATTOOL over logbook: logbook's mesh really
--     deforms, eattool's items are rigid like ours.
--
--   * THE SWAY IS NOT PROCEDURAL - do not try to write one. It is the
--     borrowed rig's looping "Idle" animation, advanced by
--     updateFpAnimations() every frame. Borrow the rig, get the sway.
--
-- All verified in-game: a mod MAY reference $SURVIVAL_DATA renderables, and the
-- device is held with the vanilla sway (accepted build 33). Step results still go
-- to held_probe.json - keep it, it is what found nearly every one of these.
local ARMFP = "$SURVIVAL_DATA/Character/Char_Male/Animations/char_male_fp_eattool.rend"
local ARMTP = "$SURVIVAL_DATA/Character/Char_Male/Animations/char_male_tp_eattool.rend"
local POSFP = "$SURVIVAL_DATA/Character/Char_Tools/Char_eattool/char_eattool_fp.rend"
local POSTP = "$SURVIVAL_DATA/Character/Char_Tools/Char_eattool/char_eattool_tp.rend"
local DEVICE = C .. "/Tools/GpsDevice_held_v1.rend"
-- SEPARATE THIRD-PERSON MESH. A .rend has no transform field, so the hold pose
-- is baked into the mesh - one mesh cannot carry two poses, and the FP pose was
-- accepted on build 33 and must not move. The shared mesh is centred on the
-- joint origin, which is invisible in FP (the device hides the hand) but puts
-- the fist through the screen in third person. The TP bake is 25% smaller with
-- the joint at the device's BACK FACE, sitting on the orange bezel rather than
-- over the map face, and centred vertically so it covers the fingers. Four
-- bakes; Eric accepted the fourth on build 40.
local DEVICE_TP = C .. "/Tools/GpsDevice_held_tp_v5.rend"

-- TP names come from the same borrowed rig (Eat.lua's map, verbatim)
local TPMOVE = {
	idle = "Idle",
	runFwd = "Run_fwd", runBwd = "Run_bwd",
	sprint = "Sprint_fwd", sprintLeft = "Sprint_left", sprintRight = "Sprint_right",
	jump = "Jump", jumpUp = "Jump_up", jumpDown = "Jump_down",
	land = "Jump_land", landFwd = "Jump_land_fwd", landBwd = "Jump_land_bwd",
	landLeft = "Jump_land_left", landRight = "Jump_land_right",
	crouchIdle = "Crouch_idle", crouchFwd = "Crouch_fwd", crouchBwd = "Crouch_bwd",
}

-- Build 14's control experiment, kept as a note: a VANILLA carrot mesh wearing OUR
-- textures rendered while our FBX did not, which proved the rig, the list, the
-- textures and the paths were all fine and the mesh FILE was the fault.

-- PRELOAD AT FILE SCOPE, after every path above is declared (Lua locals do not
-- exist before their line, and preloading one above its own declaration silently
-- passes nil). Every vanilla tool preloads every list it will ever set.
pcall(sm.tool.preloadRenderables, { ARMTP, POSTP })
pcall(sm.tool.preloadRenderables, { ARMFP, POSFP })
pcall(sm.tool.preloadRenderables, { DEVICE })
pcall(sm.tool.preloadRenderables, { DEVICE_TP })

-- The in-hand pose was DERIVED, not swept: the eattool rig's root_item matrix
-- (item space -> camera space, read out of ani_char_eattool_fp_position.dae)
-- transposed to cancel it, then Y180 because camera -Z faces the viewer, then a
-- 10 degree tilt back. tools/make_held_dae.py bakes exactly that by default, so a
-- plain run reproduces the shipped mesh. BUMP THE _v SUFFIX on the dae/rend
-- whenever the mesh changes - the engine caches meshes by PATH.
-- FP and TP take DIFFERENT meshes. Confirmed in-game by Eric on build 40 and
-- promoted out of its flag.
local function items(tp)
	if tp then return { DEVICE_TP } end
	return { DEVICE }
end

local function listFor(rig, pos, tp)
	local t = { rig, pos }
	for _, v in ipairs(items(tp)) do t[#t + 1] = v end
	return t
end

-- CONFIRMED in-game by Eric on build 33 and promoted out of its flag.
local function held(self)
	return self.heldOk == true
end

-- RENDERABLES BELONG IN client_onEquip, NOT client_onCreate (build 9's other
-- mistake): Sledgehammer.client_onEquip and Eat's cl_updateEatRenderables both
-- set them on equip, and the order below is Sledgehammer's verbatim -
-- setTpRenderables, create animations, setTpAnimation, then setFpRenderables.
-- client_onRefresh calls this too so /refresh reloads behave.
function SpikeHand.cl_setupHeld( self )
	local p = { phase = self.heldPhase or "equip" }
	local function step(key, fn)
		local ok, err = pcall(fn)
		p[key] = ok and "ok" or tostring(err)
		return ok
	end
	local okUtil = step("animUtil", function()
		-- dofile'd at file scope above (it MUST be); this only confirms arrival
		assert(type(createFpAnimations) == "function", "helpers missing")
		assert(type(updateTpAnimations) == "function", "helpers missing")
	end)
	if okUtil then
		-- separate steps on purpose: if $SURVIVAL_DATA were refused to mods we
		-- would see it here rather than guess it from an empty hand
		step("tpRenderables", function()
			self.tool:setTpRenderables(listFor(ARMTP, POSTP, true))
		end)
		step("tpAnims", function()
			self.tpAnimations = createTpAnimations(self.tool, {
				idle = { "Idle" },
				pickup = { "Pickup", { nextAnimation = "idle" } },
				putdown = { "Putdown" },
			})
			for name, animation in pairs(TPMOVE) do
				self.tool:setMovementAnimation(name, animation)
			end
			setTpAnimation(self.tpAnimations, "pickup", 0.0001)
		end)
		if self.tool:isLocal() then
			step("fpRenderables", function()
				self.tool:setFpRenderables(listFor(ARMFP, POSFP))
			end)
			if p.fpRenderables ~= "ok" then
				-- our own mesh alone: no arms, no sway, but it separates "the
				-- borrowed rig is refused" from "setFpRenderables is refused"
				step("fpDeviceOnly", function()
					self.tool:setFpRenderables({ DEVICE })
				end)
			end
			step("fpAnims", function()
				self.fpAnimations = createFpAnimations(self.tool, {
					-- looping Idle = THE SWAY
					idle = { "Idle", { looping = true } },
					sprintInto = { "Sprint_into", { nextAnimation = "sprintIdle", blendNext = 0.2 } },
					sprintIdle = { "Sprint_idle", { looping = true } },
					sprintExit = { "Sprint_exit", { nextAnimation = "idle", blendNext = 0 } },
					jump = { "Jump", { nextAnimation = "idle" } },
					land = { "Jump_land", { nextAnimation = "idle" } },
					equip = { "Pickup", { nextAnimation = "idle" } },
					unequip = { "Putdown" },
				})
				swapFpAnimation(self.fpAnimations, "unequip", "equip", 0.2)
			end)
		end
	end
	self.heldOk = (p.fpRenderables == "ok") or (p.tpRenderables == "ok")
	self.blendTime = 0.2
	self.wasOnGround = true
	p.local_ = tostring(self.tool:isLocal())
	pcall(sm.json.save, p, C .. "/held_probe.json")
end

function SpikeHand.client_onCreate( self )
	self.heldPhase = "create"
end

function SpikeHand.client_onRefresh( self )
	self.heldPhase = "refresh"
	self:cl_setupHeld()
end

function SpikeHand.client_onUpdate( self, dt )
	if not held(self) then return end
	pcall(function()
		if self.tool:isLocal() and self.fpAnimations then
			-- sprint / jump state transitions, exactly as Eat.lua drives them
			local isSprinting = self.tool:isSprinting()
			local isOnGround = self.tool:isOnGround()
			local cur = self.fpAnimations.currentAnimation
			if self.equipped then
				if isSprinting and cur ~= "sprintInto" and cur ~= "sprintIdle" then
					swapFpAnimation(self.fpAnimations, "sprintExit", "sprintInto", 0.0)
				elseif not isSprinting and (cur == "sprintIdle" or cur == "sprintInto") then
					swapFpAnimation(self.fpAnimations, "sprintInto", "sprintExit", 0.0)
				end
				if not isOnGround and self.wasOnGround and cur ~= "jump" then
					swapFpAnimation(self.fpAnimations, "land", "jump", 0.02)
				elseif isOnGround and not self.wasOnGround and cur ~= "land" then
					swapFpAnimation(self.fpAnimations, "jump", "land", 0.02)
				end
			end
			self.wasOnGround = isOnGround
			updateFpAnimations(self.fpAnimations, self.equipped == true, dt)
		end
		if self.tpAnimations then
			updateTpAnimations(self.tpAnimations, self.equipped == true, dt)
		end
	end)
end

function SpikeHand.client_onEquip( self, animate )
	-- no equip chat (Eric 8/8): chat text can land behind the golden ring
	-- and the usage instructions live in the item description instead
	self.equipped = true
	self.heldPhase = "equip"
	self:cl_setupHeld()      -- renderables + animations, vanilla's own timing
end

function SpikeHand.client_onUnequip( self, animate )
	self.equipped = false
	if not held(self) then return end
	pcall(function()
		setTpAnimation(self.tpAnimations, "putdown")
		if self.tool:isLocal() and self.fpAnimations
				and self.fpAnimations.currentAnimation ~= "unequip" then
			swapFpAnimation(self.fpAnimations, "equip", "unequip", 0.2)
		end
	end)
end

function SpikeHand.client_onEquippedUpdate( self, primaryState, secondaryState, forceBuildActive )
	if g_minimapHud and not forceBuildActive then
		if primaryState == sm.tool.interactState.start then
			g_minimapHud:cl_bmOpen()
		end
		if secondaryState == sm.tool.interactState.start then
			g_minimapHud:cl_zoomCycle()
		end
	end
	return true, true
end

-- Q = cycle minimap position / hide (was: toggle the big map - redundant,
-- LMB opens it and E/Esc/CLOSE close it; repurposed Eric 8/14). No-op while
-- the big map is open: the minimap is torn down there, so there would be no
-- visible feedback (and the cursor session eats key presses anyway, v55).
function SpikeHand.client_onToggle( self )
	local hud = g_minimapHud
	if hud and hud.cl and not (hud.cl.bm and hud.cl.bm.open) then
		hud:cl_posCycle()
	end
	return true
end

-- R = cycle minimap size. client_onReload has never fired in this mod
-- before - the binding is proven by Fants Map's shipped code, but the first
-- dev run must confirm it reaches an autoTool-granted tool.
function SpikeHand.client_onReload( self )
	local hud = g_minimapHud
	if hud and hud.cl and not (hud.cl.bm and hud.cl.bm.open) then
		hud:cl_sizeCycle()
	end
	return true
end

-- ------------------------------------------------- big map gui callbacks ---
local function bmName( a, b )
	if type(a) == "string" then return a end
	if type(a) == "table" and a.Name then return a.Name end
	if type(b) == "string" then return b end
	if type(b) == "table" and b.Name then return b.Name end
	return nil
end

function SpikeHand.cl_bm_btn( self, a, b )
	local name = bmName(a, b)
	if name and g_minimapHud then BigMap.button(g_minimapHud, name) end
end

function SpikeHand.cl_bm_cell( self, a, b, c, d )
	local name = bmName(a, b)
	-- raw args forwarded: cellClick probes them for cursor coords (v67)
	if name and g_minimapHud then BigMap.cellClick(g_minimapHud, name, a, b, c, d) end
end

function SpikeHand.cl_bm_bdown( self, a, b )
	local name = bmName(a, b)
	if name and g_minimapHud then BigMap.btnDown(g_minimapHud, name) end
end

function SpikeHand.cl_bm_bup( self, a, b )
	if g_minimapHud then BigMap.btnUp(g_minimapHud, bmName(a, b)) end
end

function SpikeHand.cl_bm_wheel( self, a, b, c, d )
	if g_minimapHud then BigMap.wheel(g_minimapHud, a, b, c, d) end
end

function SpikeHand.cl_bm_keys( self, a, b, c, d )
	if g_minimapHud then BigMap.keys(g_minimapHud, a, b, c, d) end
end

function SpikeHand.cl_bm_drag( self, a, b, c, d )
	if g_minimapHud then BigMap.drag(g_minimapHud, a, b, c, d) end
end

function SpikeHand.cl_bm_curs( self, a, b, c, d )
	if g_minimapHud then BigMap.cursor(g_minimapHud, a, b, c, d) end
end

function SpikeHand.cl_bm_hover( self, a, b, c, d )
	if g_minimapHud then BigMap.hover(g_minimapHud, a, b, c, d) end
end

function SpikeHand.cl_onGuiClosed( self, a, b )
	if g_minimapHud then BigMap.onClosed(g_minimapHud) end
end
