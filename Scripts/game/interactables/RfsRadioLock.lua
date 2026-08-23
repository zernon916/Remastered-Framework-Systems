-- RfsRadioLock.lua — Radio Lock. Connection Tool to Hack Beacon only.

RfsRadioLock = class( nil )
RfsRadioLock.colorNormal = sm.color.new( 0x4a4f44ff )
RfsRadioLock.colorHighlight = sm.color.new( 0x7a8070ff )

pcall( function() dofile( "$CONTENT_DATA/Scripts/game/RfsRadioStation.lua" ) end )
if type( RfsRadioStation ) == "table" and RfsRadioStation.applyModuleClass then
	RfsRadioStation.applyModuleClass( RfsRadioLock, "Radio Lock — Connection Tool to Hack Beacon (+3 bots, +3 s hold, max 1)" )
else
	RfsRadioLock.maxParentCount = 1
	RfsRadioLock.maxChildCount = 1
	RfsRadioLock.connectionInput = sm.interactable.connectionType.electricity
	RfsRadioLock.connectionOutput = sm.interactable.connectionType.electricity
	RfsRadioLock.connectIcon = "electrical"
end

print( "[RFS] RfsRadioLock loaded" )
