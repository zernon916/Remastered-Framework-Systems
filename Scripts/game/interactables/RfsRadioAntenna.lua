-- RfsRadioAntenna.lua — station piece 9 (long antenna). Wiring stub via RfsRadioStation.

RfsRadioAntenna = class( nil )
RfsRadioAntenna.maxParentCount = 2
RfsRadioAntenna.maxChildCount = 255
RfsRadioAntenna.connectionInput = sm.interactable.connectionType.logic + sm.interactable.connectionType.electricity
RfsRadioAntenna.connectionOutput = sm.interactable.connectionType.logic
RfsRadioAntenna.colorNormal = sm.color.new( 0x6b705cff )
RfsRadioAntenna.colorHighlight = sm.color.new( 0x9aa080ff )

pcall( function() dofile( "$CONTENT_DATA/Scripts/game/RfsRadioStation.lua" ) end )

function RfsRadioAntenna.server_onCreate( self ) end
function RfsRadioAntenna.client_onCreate( self ) end

print( "[RFS] RfsRadioAntenna loaded" )
