-- RfsRadioLock.lua — station piece 10 (ampfilter lock). Persist conversion stub.

RfsRadioLock = class( nil )
RfsRadioLock.maxParentCount = 2
RfsRadioLock.maxChildCount = 255
RfsRadioLock.connectionInput = sm.interactable.connectionType.logic + sm.interactable.connectionType.electricity
RfsRadioLock.connectionOutput = sm.interactable.connectionType.logic
RfsRadioLock.colorNormal = sm.color.new( 0x4a4f44ff )
RfsRadioLock.colorHighlight = sm.color.new( 0x7a8070ff )

pcall( function() dofile( "$CONTENT_DATA/Scripts/game/RfsRadioStation.lua" ) end )

function RfsRadioLock.server_onCreate( self ) end
function RfsRadioLock.client_onCreate( self ) end

print( "[RFS] RfsRadioLock loaded (lock tier stub)" )
