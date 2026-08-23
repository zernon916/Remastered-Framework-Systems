-- RfsRadioBrick.lua — Radio Battery Brick. Connection Tool to Hack Beacon only.

RfsRadioBrick = class( nil )
RfsRadioBrick.colorNormal = sm.color.new( 0x6b705cff )
RfsRadioBrick.colorHighlight = sm.color.new( 0x9aa080ff )

pcall( function() dofile( "$CONTENT_DATA/Scripts/game/RfsRadioStation.lua" ) end )
if type( RfsRadioStation ) == "table" and RfsRadioStation.applyModuleClass then
	RfsRadioStation.applyModuleClass( RfsRadioBrick, "Radio Battery Brick — Connection Tool to Hack Beacon (+10 range, +1 bot, max 1)" )
else
	RfsRadioBrick.maxParentCount = 1
	RfsRadioBrick.maxChildCount = 1
	RfsRadioBrick.connectionInput = sm.interactable.connectionType.electricity
	RfsRadioBrick.connectionOutput = sm.interactable.connectionType.electricity
	RfsRadioBrick.connectIcon = "electrical"
end

print( "[RFS] RfsRadioBrick loaded" )
