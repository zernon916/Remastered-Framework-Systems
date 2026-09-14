-- RFS overworld terrain: vanilla generation, but roadside wreck slots always
-- place a vehicle. Vanilla variant 01 is cones-only (weight 60 / 136 ≈ empty).
dofile( "$SURVIVAL_DATA/Scripts/terrain/terrain_overworld.lua" )

prefabTable["gameplay_prefabs/random_abandoned_vehicle"] = {
	{ "$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_02.prefab", 1 },
	{ "$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_03.prefab", 10 },
	{ "$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_04.prefab", 5 },
	{ "$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_05.prefab", 10 },
	{ "$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_06.prefab", 5 },
	{ "$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_07.prefab", 10 },
	{ "$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_08.prefab", 5 },
	{ "$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_09.prefab", 10 },
	{ "$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_10.prefab", 5 },
	{ "$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_11.prefab", 10 },
	{ "$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_12.prefab", 5 }
}
