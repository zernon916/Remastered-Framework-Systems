-- RfsBedSleep.lua
-- All Survival Bed seats (+ Mattress override) skip night to 5 AM when solo.
-- Uses RfsDeepSleepTime / Chem Station time skip. Multiplayer vote stays parked.

RfsBedSleep = RfsBedSleep or {}

function RfsBedSleep.trySkipNight( character )
	local player = nil
	pcall( function()
		if character and sm.exists( character ) and character.getPlayer then
			player = character:getPlayer()
		end
	end )
	pcall( function()
		sm.event.sendToGame( "sv_e_rfsDeepSleepSkip", {
			player = player,
			healing = false,
			fromBed = true,
			quietFail = true,
		} )
	end )
end

function RfsBedSleep.ensureHooks()
	if type( Bed ) ~= "table" then
		pcall( function()
			dofile( "$SURVIVAL_DATA/Scripts/game/interactables/Bed.lua" )
		end )
	end
	if type( Bed ) ~= "table" then
		return false
	end

	if Bed._rfsBedSleepHooked
		and Bed.sv_activateBed == RfsBedSleep._svActivateHook then
		return true
	end

	if not RfsBedSleep._origSvActivate then
		RfsBedSleep._origSvActivate = Bed.sv_activateBed
	end

	function RfsBedSleep._svActivateHook( self, character )
		if RfsBedSleep._origSvActivate then
			RfsBedSleep._origSvActivate( self, character )
		end
		RfsBedSleep.trySkipNight( character )
	end

	Bed.sv_activateBed = RfsBedSleep._svActivateHook
	Bed._rfsBedSleepHooked = true

	if type( TutorialBed ) == "table" then
		TutorialBed.sv_activateBed = RfsBedSleep._svActivateHook
	end

	if not RfsBedSleep._hookLogged then
		RfsBedSleep._hookLogged = true
		print( "[RFS] RfsBedSleep hooked Bed.sv_activateBed (solo night skip)" )
	end
	return true
end

pcall( function()
	RfsBedSleep.ensureHooks()
end )

print( "[RFS] RfsBedSleep loaded" )
