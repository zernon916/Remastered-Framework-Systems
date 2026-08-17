-- RfsGpsTool.lua — host Nutt's GPS hand tool (SpikeHand) as a craftable item.
-- jsonGui atlas clicks bind to the script whose call chain opened the map.
-- LMB on this tool calls MinimapHud:cl_bmOpen, so callbacks land here (Nutt's
-- SpikeHand.cl_bm_btn / cell / wheel / …). Atlas/HUD are vendored; do not also
-- enable World Map as a world mod if you already have it (double HUD).

RfsGpsTool = class()

local NUTT = "$CONTENT_DATA"

local ok, err = pcall( function()
	dofile( NUTT .. "/Scripts/nutt/SpikeHand.lua" )
end )
if ok and type( SpikeHand ) == "table" then
	RfsGpsTool = SpikeHand
	print( "[RFS] GPS: Nutt SpikeHand hosted (craft / research, LMB opens atlas)" )
else
	function RfsGpsTool.client_onCreate( self )
		print( "[RFS] GPS: Nutt SpikeHand unavailable (" .. tostring( err ) .. ")" )
	end
	function RfsGpsTool.client_onEquippedUpdate( self )
		return false, false
	end
end
