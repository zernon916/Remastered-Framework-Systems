-- RfsRadioAntenna.lua — Radio Antenna. Connection Tool to Hack Beacon only.

RfsRadioAntenna = class( nil )
RfsRadioAntenna.colorNormal = sm.color.new( 0x6b705cff )
RfsRadioAntenna.colorHighlight = sm.color.new( 0x9aa080ff )

pcall( function() dofile( "$CONTENT_DATA/Scripts/game/RfsRadioStation.lua" ) end )
if type( RfsRadioStation ) == "table" and RfsRadioStation.applyModuleClass then
	RfsRadioStation.applyModuleClass( RfsRadioAntenna, "Radio Antenna — Connection Tool to Hack Beacon (+10 range each, max 2)" )
else
	RfsRadioAntenna.maxParentCount = 1
	RfsRadioAntenna.maxChildCount = 1
	RfsRadioAntenna.connectionInput = sm.interactable.connectionType.electricity
	RfsRadioAntenna.connectionOutput = sm.interactable.connectionType.electricity
	RfsRadioAntenna.connectIcon = "electrical"
end

print( "[RFS] RfsRadioAntenna loaded" )
