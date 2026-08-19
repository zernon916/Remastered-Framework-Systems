-- RfsHarvestableSoil.lua — harvestable VM bootstrap (server Logic Task per soil tile).
-- Vanilla soil script + RFS server_onRemoved pickup block in this VM.

dofile( "$SURVIVAL_DATA/Scripts/game/harvestable/HarvestableSoil.lua" )

RfsSoilPlacement = RfsSoilPlacement or {}
RfsSoilPlacement._harvestableBootOnly = true

pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsSoilPlacement.lua" )
end )

if type( RfsSoilPlacement ) == "table" and RfsSoilPlacement.ensureHarvestableSoilHooks then
	RfsSoilPlacement.ensureHarvestableSoilHooks()
end
