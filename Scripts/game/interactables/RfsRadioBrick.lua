-- RfsRadioBrick.lua — station piece 5 (battery brick). Wiring stub via RfsRadioStation.

RfsRadioBrick = class( nil )
RfsRadioBrick.maxParentCount = 2
RfsRadioBrick.maxChildCount = 255
RfsRadioBrick.connectionInput = sm.interactable.connectionType.logic + sm.interactable.connectionType.electricity
RfsRadioBrick.connectionOutput = sm.interactable.connectionType.logic
RfsRadioBrick.colorNormal = sm.color.new( 0x6b705cff )
RfsRadioBrick.colorHighlight = sm.color.new( 0x9aa080ff )

pcall( function() dofile( "$CONTENT_DATA/Scripts/game/RfsRadioStation.lua" ) end )

function RfsRadioBrick.server_onCreate( self ) end
function RfsRadioBrick.client_onCreate( self ) end

print( "[RFS] RfsRadioBrick loaded" )
