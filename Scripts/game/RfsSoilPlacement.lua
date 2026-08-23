-- RfsSoilPlacement.lua
-- FROZEN: Soil Bag placement + RMB rect batch pickup + terrain/block drag.
-- Footprint: vanilla 3x3x1 subdiv units (SoilBag size/size_2); cell index = floor(gridPos/3).
-- Do not edit for hack/beacon/chem/orders work. Bump RFS_PACK_STAMP if shipped.

RfsSoilPlacement = RfsSoilPlacement or {}

pcall( function()
	dofile( "$SURVIVAL_DATA/Scripts/game/survival_harvestable.lua" )
end )

-- cos(~15°) — same steepness gate as vanilla SoilBag.
local FLAT_NORMAL_Z = 0.96592583

local SOIL_SIZE = sm.vec3.new( 3, 3, 1 )
local SOIL_SIZE_HALF = sm.vec3.new( 1, 1, 0 )

local TERRAIN_PLACEMENT_MASK = bit.bor(
	sm.physics.filter.dynamicBody,
	sm.physics.filter.waterArea,
	sm.physics.filter.terrainAsset,
	sm.physics.filter.harvestable,
	sm.physics.filter.staticBody,
	sm.physics.filter.voxelTerrain
)

-- Body/lift tops: omit staticBody so the platform itself is allowed.
local BLOCK_SOIL_MASK = bit.bor(
	sm.physics.filter.dynamicBody,
	sm.physics.filter.waterArea,
	sm.physics.filter.terrainAsset,
	sm.physics.filter.harvestable,
	sm.physics.filter.voxelTerrain
)

-- Per-cell block/lift sample during LMB drag (raycast down at each cell center).
local BLOCK_SAMPLE_MASK = bit.bor(
	sm.physics.filter.dynamicBody,
	sm.physics.filter.staticBody,
	sm.physics.filter.terrainAsset,
	sm.physics.filter.harvestable,
	sm.physics.filter.voxelTerrain
)

-- Per-cell terrain sample during LMB drag (raycast down at each cell center).
local TERRAIN_SAMPLE_MASK = bit.bor(
	sm.physics.filter.terrainSurface,
	sm.physics.filter.voxelTerrain
)
local TERRAIN_RAY_UP = 50
local TERRAIN_RAY_DOWN = 100

-- Fixed orientation (no random yaw on place).
local FIXED_SOIL_ROT = sm.quat.new( 0.70710678, 0, 0, 0.70710678 )

local function soilAllowedInWorld()
	local world = sm.localPlayer.getWorld()
	if not world then
		return false
	end
	if not world.clientPublicData then
		return false
	end
	if world.clientPublicData.allowSoilPlacement then
		return true
	end
	return false
end

local function dirtOnBlocksActive()
	if type( RfsFarming ) == "table" and type( RfsFarming.dirtOnBlocksActive ) == "function" then
		return RfsFarming.dirtOnBlocksActive()
	end
	return ( _G.g_rfsDirtOnBlocks == true ) and RfsSettings and RfsSettings.cheatsEnabled()
end

local function fastPlaceActive()
	if type( RfsFarming ) == "table" and type( RfsFarming.fastPlaceActive ) == "function" then
		return RfsFarming.fastPlaceActive()
	end
	return ( _G.g_rfsFastPlace == true ) and RfsSettings and RfsSettings.cheatsEnabled()
end

local function fastPickupActive()
	if type( RfsFarming ) == "table" and type( RfsFarming.fastPickupActive ) == "function" then
		return RfsFarming.fastPickupActive()
	end
	return ( _G.g_rfsFastPickup == true ) and RfsSettings and RfsSettings.cheatsEnabled()
end

-- Canonical subdiv corner from world center (vanilla SoilBag round-trip).
function RfsSoilPlacement.gridPosFromWorldPos( worldPos )
	if not worldPos or type( worldPos.x ) ~= "number" then
		return nil, nil
	end
	local ratio = sm.construction.constants.subdivideRatio
	local invRatio = 1 / ratio
	return math.floor( worldPos.x * invRatio - SOIL_SIZE.x * 0.5 + 1e-4 ),
		math.floor( worldPos.y * invRatio - SOIL_SIZE.y * 0.5 + 1e-4 )
end

-- gridZ is subdiv units (vanilla SoilBag a.z); XY/Z all convert through subdivideRatio.
function RfsSoilPlacement.worldPosFromGridPos( gridPosX, gridPosY, gridZ )
	local ratio = sm.construction.constants.subdivideRatio
	local zSubdiv = gridZ or 0
	return sm.vec3.new(
		( gridPosX + SOIL_SIZE.x * 0.5 ) * ratio,
		( gridPosY + SOIL_SIZE.y * 0.5 ) * ratio,
		zSubdiv * ratio + ( SOIL_SIZE.z * ratio ) * 0.5
	)
end

-- Drag/pickup rect index only; snap gridPos within a cell may be cell*3 .. cell*3+2.
function RfsSoilPlacement.gridPosXYForCell( cellX, cellY )
	return cellX * SOIL_SIZE.x, cellY * SOIL_SIZE.y
end

function RfsSoilPlacement.gridPosFromCell( cellX, cellY, gridZ )
	return sm.vec3.new(
		cellX * SOIL_SIZE.x,
		cellY * SOIL_SIZE.y,
		gridZ or 0
	)
end

-- Single snap source: cell corner gridPos + terrain subdiv Z (vanilla SoilBag round-trip).
function RfsSoilPlacement.worldPosForTerrainCell( cellX, cellY, gridZ )
	local gridPosX, gridPosY = RfsSoilPlacement.gridPosXYForCell( cellX, cellY )
	return RfsSoilPlacement.worldPosFromGridPos( gridPosX, gridPosY, gridZ )
end

-- Flat drag rect: expand in cell index space only; lock plane Z/normal from drag-start anchor.
function RfsSoilPlacement.worldPosForAnchoredFlatCell( cellX, cellY, anchor )
	if not anchor then
		return nil
	end
	if anchor.fromBody then
		local base = RfsSoilPlacement.worldPosFromCell( cellX, cellY, 0 )
		local anchorZ = anchor.worldPos and anchor.worldPos.z or anchor.refWorldZ
		if anchorZ == nil then
			return base
		end
		return sm.vec3.new( base.x, base.y, anchorZ )
	end
	if anchor.gridZ ~= nil then
		return RfsSoilPlacement.worldPosForTerrainCell( cellX, cellY, anchor.gridZ )
	end
	return nil
end

function RfsSoilPlacement.worldPosFromCell( cellX, cellY, gridZ )
	local gridPos = RfsSoilPlacement.gridPosFromCell( cellX, cellY, gridZ )
	return RfsSoilPlacement.worldPosFromGridPos( gridPos.x, gridPos.y, gridPos.z )
end

function RfsSoilPlacement.cellFromSubdiv( rawGridX, rawGridY )
	return math.floor( rawGridX / SOIL_SIZE.x ), math.floor( rawGridY / SOIL_SIZE.y )
end

function RfsSoilPlacement.cellFromWorldPos( worldPos )
	local gridX, gridY = RfsSoilPlacement.gridPosFromWorldPos( worldPos )
	if gridX == nil or gridY == nil then
		return nil, nil
	end
	return RfsSoilPlacement.cellFromSubdiv( gridX, gridY )
end

function RfsSoilPlacement.canonicalTerrainPos( worldPos )
	if not worldPos or type( worldPos.x ) ~= "number" then
		return worldPos
	end
	local cellX, cellY = RfsSoilPlacement.cellFromWorldPos( worldPos )
	if cellX == nil or cellY == nil then
		return worldPos
	end
	local ratio = sm.construction.constants.subdivideRatio
	local gridZ = worldPos.z / ratio - SOIL_SIZE.z * 0.5
	return RfsSoilPlacement.worldPosForTerrainCell( cellX, cellY, gridZ )
end

-- Vanilla SoilBag terrain snap (3x3 subdiv grid); cellX/Y index non-overlapping drag rects only.
function RfsSoilPlacement.snapTerrainSoil( result )
	local ratio = sm.construction.constants.subdivideRatio
	local subdiv = sm.construction.constants.subdivisions
	local groundPointOffset = -( sm.construction.constants.subdivideRatio_2 - 0.04 + sm.construction.constants.shapeSpacing + 0.005 )
	local pointLocal = result.pointLocal + result.normalLocal * groundPointOffset
	local a = pointLocal * subdiv
	local gridPos = sm.vec3.new( math.floor( a.x ), math.floor( a.y ), a.z ) - SOIL_SIZE_HALF
	local worldPos = gridPos * ratio + ( SOIL_SIZE * ratio ) * 0.5
	local cellX = math.floor( gridPos.x / SOIL_SIZE.x )
	local cellY = math.floor( gridPos.y / SOIL_SIZE.y )
	if g_survivalDev then
		local dbgKey = tostring( cellX ) .. "," .. tostring( cellY ) .. "," .. tostring( gridPos.x ) .. "," .. tostring( gridPos.y )
		if RfsSoilPlacement._dbgSoilSnapKey ~= dbgKey then
			RfsSoilPlacement._dbgSoilSnapKey = dbgKey
			print( string.format(
				"[RFS] soil snap cell=%d,%d gridPos=%.0f,%.0f world=%.2f,%.2f",
				cellX, cellY, gridPos.x, gridPos.y, worldPos.x, worldPos.y
			) )
		end
	end
	return worldPos, result.normalWorld, cellX, cellY, a.z
end

-- Raycast terrain at cell center; snap Z from hit, XY from canonical cell gridPos (matches cursor ghost).
function RfsSoilPlacement.sampleTerrainAtCell( cellX, cellY, refWorldZ )
	local basePos = RfsSoilPlacement.worldPosFromCell( cellX, cellY, 0 )
	local x, y = basePos.x, basePos.y

	local zRef = refWorldZ
	if not zRef then
		pcall( function()
			local player = sm.localPlayer.getPlayer()
			if player then
				local char = player:getCharacter()
				if char then
					zRef = char.worldPosition.z
				end
			end
		end )
	end
	zRef = zRef or 20

	local hit, result = sm.physics.raycast(
		sm.vec3.new( x, y, zRef + TERRAIN_RAY_UP ),
		sm.vec3.new( x, y, zRef - TERRAIN_RAY_DOWN ),
		nil,
		TERRAIN_SAMPLE_MASK
	)
	if not hit or not result then
		return nil
	end
	if result.type ~= "terrainSurface" and result.type ~= "voxelTerrain" then
		return nil
	end
	if not result.pointLocal or not result.normalLocal then
		return nil
	end

	local _, normalWorld, _, _, gridZ = RfsSoilPlacement.snapTerrainSoil( result )
	local worldPos = RfsSoilPlacement.worldPosForTerrainCell( cellX, cellY, gridZ )
	local flat = RfsSoilPlacement.isFlatSurface( normalWorld )
	local blocked = RfsSoilPlacement.isPlacementBlocked( worldPos, false, normalWorld )
	return {
		pos = worldPos,
		normal = normalWorld,
		cellX = cellX,
		cellY = cellY,
		gridZ = gridZ,
		flat = flat,
		blocked = blocked,
	}
end

-- Raycast body/lift at a 3x3 cell center; snapWorldSoilPos + BLOCK_SOIL_MASK contact gate.
function RfsSoilPlacement.sampleBlockAtCell( cellX, cellY, refWorldZ )
	local basePos = RfsSoilPlacement.worldPosFromCell( cellX, cellY, 0 )
	local x, y = basePos.x, basePos.y

	local zRef = refWorldZ
	if not zRef then
		pcall( function()
			local player = sm.localPlayer.getPlayer()
			if player then
				local char = player:getCharacter()
				if char then
					zRef = char.worldPosition.z
				end
			end
		end )
	end
	zRef = zRef or 20

	local hit, result = sm.physics.raycast(
		sm.vec3.new( x, y, zRef + TERRAIN_RAY_UP ),
		sm.vec3.new( x, y, zRef - TERRAIN_RAY_DOWN ),
		nil,
		BLOCK_SAMPLE_MASK
	)
	if not hit or not result then
		return nil
	end
	if result.type ~= "body" and result.type ~= "lift" then
		return nil
	end
	if not result.pointWorld or not result.normalWorld then
		return nil
	end

	local normalWorld = result.normalWorld
	local worldPos = RfsSoilPlacement.snapWorldSoilPos( result.pointWorld, normalWorld )
	local flat = RfsSoilPlacement.isFlatSurface( normalWorld )
	local blocked = RfsSoilPlacement.isPlacementBlocked( worldPos, true, normalWorld )
	return {
		pos = worldPos,
		normal = normalWorld,
		flat = flat,
		blocked = blocked,
		fromBody = true,
	}
end

-- Body/lift tops: half-ratio lift, XY grid snap, keep Z from surface (pre-0820-g working path).
function RfsSoilPlacement.snapWorldSoilPos( pointWorld, normalWorld )
	local ratio = sm.construction.constants.subdivideRatio
	local worldPos = pointWorld + normalWorld * ( ratio * 0.5 )
	worldPos = sm.vec3.new(
		math.floor( worldPos.x / ratio + 0.5 ) * ratio,
		math.floor( worldPos.y / ratio + 0.5 ) * ratio,
		worldPos.z
	)
	return worldPos
end

function RfsSoilPlacement.gridKey( gridX, gridY )
	return tostring( gridX ) .. "," .. tostring( gridY )
end

function RfsSoilPlacement.isFlatSurface( normalWorld )
	return normalWorld and normalWorld.z >= FLAT_NORMAL_Z
end

local function secondaryPickupActive( secondaryState )
	return secondaryState == sm.tool.interactState.start
		or secondaryState == sm.tool.interactState.hold
end

-- Survival tools.json SoilBag tool uuid (distinct from obj_consumable_soilbag item uuid).
local SOIL_TOOL_UUID = sm.uuid.new( "3ef5412a-7044-45ae-9592-9ce86bd99081" )

local SOIL_PREVIEW_UUID = sm.uuid.new( "42c8e4fc-0c38-4aa8-80ea-1835dd982d7c" )
local SOIL_PREVIEW_SCALE = sm.vec3.new(
	sm.construction.constants.subdivideRatio,
	sm.construction.constants.subdivideRatio,
	sm.construction.constants.subdivideRatio
)
local SOIL_PREVIEW_ROT = sm.quat.angleAxis( math.pi * 0.5, sm.vec3.new( 1, 0, 0 ) )

local function clearDragPreviews( self )
	if not self._rfsSoilDragPreviews then
		return
	end
	for _, fx in ipairs( self._rfsSoilDragPreviews ) do
		if fx:isPlaying() then
			fx:stop()
		end
	end
end

local function syncDragPreviews( self, dragCells, pickupMode )
	if not dragCells then
		clearDragPreviews( self )
		return
	end

	self._rfsSoilDragPreviews = self._rfsSoilDragPreviews or {}
	local idx = 0
	for _, cell in pairs( dragCells ) do
		idx = idx + 1
		local fx = self._rfsSoilDragPreviews[idx]
		if not fx then
			fx = sm.effect.createEffect( "ShapeRenderable" )
			fx:setParameter( "uuid", SOIL_PREVIEW_UUID )
			fx:setParameter( "visualization", true )
			fx:setScale( SOIL_PREVIEW_SCALE )
			self._rfsSoilDragPreviews[idx] = fx
		end
		fx:setPosition( cell.pos )
		fx:setRotation( SOIL_PREVIEW_ROT )
		local previewColor = "Lift Valid"
		if pickupMode then
			previewColor = "Lift Invalid"
		elseif cell.flat == false or cell.blocked then
			previewColor = "Lift Invalid"
		end
		fx:setParameter( "visualizationColor", previewColor )
		if not fx:isPlaying() then
			fx:start()
		end
	end
	for i = idx + 1, #self._rfsSoilDragPreviews do
		if self._rfsSoilDragPreviews[i]:isPlaying() then
			self._rfsSoilDragPreviews[i]:stop()
		end
	end
end

local function rebuildTerrainDragRect( self, startCell, curCellX, curCellY )
	if not startCell or curCellX == nil or curCellY == nil then
		return
	end
	local minX = math.min( startCell.cellX, curCellX )
	local maxX = math.max( startCell.cellX, curCellX )
	local minY = math.min( startCell.cellY, curCellY )
	local maxY = math.max( startCell.cellY, curCellY )
	local refWorldZ = startCell.refWorldZ
	local flatDrag = startCell.flat ~= false and startCell.gridZ ~= nil
	local anchorNormal = startCell.normal or sm.vec3.new( 0, 0, 1 )
	local dragCells = {}
	for cx = minX, maxX do
		for cy = minY, maxY do
			local gridKey = RfsSoilPlacement.gridKey( cx, cy )
			if flatDrag then
				local worldPos = RfsSoilPlacement.worldPosForAnchoredFlatCell( cx, cy, startCell )
				local blocked = RfsSoilPlacement.isPlacementBlocked( worldPos, false, anchorNormal )
				dragCells[gridKey] = {
					pos = worldPos,
					normal = anchorNormal,
					gridZ = startCell.gridZ,
					flat = true,
					blocked = blocked,
					fromBody = false,
				}
			else
				local sample = RfsSoilPlacement.sampleTerrainAtCell( cx, cy, refWorldZ )
				if sample and sample.pos then
					dragCells[gridKey] = {
						pos = sample.pos,
						normal = sample.normal,
						gridZ = sample.gridZ,
						flat = sample.flat,
						blocked = sample.blocked,
						fromBody = false,
					}
				else
					local gridPosX, gridPosY = RfsSoilPlacement.gridPosXYForCell( cx, cy )
					local pos = RfsSoilPlacement.worldPosFromGridPos(
						gridPosX,
						gridPosY,
						startCell.gridZ or 0
					)
					dragCells[gridKey] = {
						pos = pos,
						flat = false,
						blocked = true,
						fromBody = false,
					}
				end
			end
		end
	end
	self._rfsSoilDragCells = dragCells
end

local function rebuildBlockDragRect( self, startCell, curCellX, curCellY, refWorldZ )
	if not startCell or curCellX == nil or curCellY == nil then
		return
	end
	local minX = math.min( startCell.cellX, curCellX )
	local maxX = math.max( startCell.cellX, curCellX )
	local minY = math.min( startCell.cellY, curCellY )
	local maxY = math.max( startCell.cellY, curCellY )
	local zRef = refWorldZ or startCell.refWorldZ
	local flatDrag = startCell.flat ~= false
		and ( startCell.worldPos or startCell.refWorldZ )
	local anchorNormal = startCell.normal or sm.vec3.new( 0, 0, 1 )
	local dragCells = {}
	for cx = minX, maxX do
		for cy = minY, maxY do
			local gridKey = RfsSoilPlacement.gridKey( cx, cy )
			if flatDrag then
				local worldPos = RfsSoilPlacement.worldPosForAnchoredFlatCell( cx, cy, startCell )
				local blocked = RfsSoilPlacement.isPlacementBlocked( worldPos, true, anchorNormal )
				dragCells[gridKey] = {
					pos = worldPos,
					normal = anchorNormal,
					flat = true,
					blocked = blocked,
					fromBody = true,
				}
			else
				local sample = RfsSoilPlacement.sampleBlockAtCell( cx, cy, zRef )
				if sample and sample.pos then
					dragCells[gridKey] = {
						pos = sample.pos,
						normal = sample.normal,
						flat = sample.flat,
						blocked = sample.blocked,
						fromBody = true,
					}
				else
					local pos = RfsSoilPlacement.worldPosFromCell( cx, cy, 0 )
					dragCells[gridKey] = {
						pos = pos,
						flat = false,
						blocked = true,
						fromBody = true,
					}
				end
			end
		end
	end
	self._rfsSoilDragCells = dragCells
end

local function resetPickupDrag( self )
	self._rfsSoilPickupDragging = false
	self._rfsSoilPickupStartCell = nil
	self._rfsSoilPickupDragCells = nil
end

local function rebuildPickupDragRect( self, startCell, curCellX, curCellY, gridZ )
	if not startCell or curCellX == nil or curCellY == nil then
		return
	end
	local minX = math.min( startCell.cellX, curCellX )
	local maxX = math.max( startCell.cellX, curCellX )
	local minY = math.min( startCell.cellY, curCellY )
	local maxY = math.max( startCell.cellY, curCellY )
	local z = gridZ or startCell.gridZ or 0
	local dragCells = {}
	for cx = minX, maxX do
		for cy = minY, maxY do
			local gridKey = RfsSoilPlacement.gridKey( cx, cy )
			local gridPosX = cx * SOIL_SIZE.x
			local gridPosY = cy * SOIL_SIZE.y
			dragCells[gridKey] = {
				pos = RfsSoilPlacement.worldPosFromGridPos( gridPosX, gridPosY, z ),
			}
		end
	end
	self._rfsSoilPickupDragCells = dragCells
end

local function flushPickupDragBatch( self )
	local startCell = self._rfsSoilPickupStartCell
	local dragCells = self._rfsSoilPickupDragCells
	resetPickupDrag( self )
	clearDragPreviews( self )
	if not startCell then
		return
	end

	local minCellX, maxCellX = startCell.cellX, startCell.cellX
	local minCellY, maxCellY = startCell.cellY, startCell.cellY
	if dragCells then
		for _, cell in pairs( dragCells ) do
			local cx, cy = RfsSoilPlacement.cellFromWorldPos( cell.pos )
			if cx ~= nil and cy ~= nil then
				minCellX = math.min( minCellX, cx )
				maxCellX = math.max( maxCellX, cx )
				minCellY = math.min( minCellY, cy )
				maxCellY = math.max( maxCellY, cy )
			end
		end
	end

	-- Must use tool network RPC (sendToGame runs sv_e_* on client VM → sandbox violation).
	pcall( function()
		if self.network and self.network.sendToServer then
			self.network:sendToServer( "sv_n_pickupSoilBatch", {
				minCellX = minCellX,
				maxCellX = maxCellX,
				minCellY = minCellY,
				maxCellY = maxCellY,
			} )
		else
			if g_survivalDev then
				print( string.format(
					"[RFS] hand pickup flush sv_e_rfsPickupSoilBatch %d..%d,%d..%d",
					minCellX, maxCellX, minCellY, maxCellY
				) )
			end
			sendPickupBatchViaGame( {
				minCellX = minCellX,
				maxCellX = maxCellX,
				minCellY = minCellY,
				maxCellY = maxCellY,
			} )
		end
	end )
	pcall( function()
		if type( setTpAnimation ) == "function" and self.tpAnimations then
			setTpAnimation( self.tpAnimations, "pickup", 0.001 )
		end
	end )
end

local function raycastSoilHarvestable( result )
	if not result or result.type ~= "harvestable" then
		return nil
	end
	local hvs = nil
	pcall( function()
		if type( result.getHarvestable ) == "function" then
			hvs = result:getHarvestable()
		elseif result.harvestable and sm.exists( result.harvestable ) then
			hvs = result.harvestable
		end
	end )
	if not hvs or not sm.exists( hvs ) then
		return nil
	end
	local uid = nil
	pcall( function()
		uid = hvs:getUuid()
	end )
	if not uid then
		return nil
	end
	if hvs_soil and uid == hvs_soil then
		return hvs
	end
	if type( RfsFarming ) == "table" and type( RfsFarming.isSoilUuid ) == "function" then
		if RfsFarming.isSoilUuid( uid ) then
			return hvs
		end
	elseif hvs_soil and tostring( uid ) == tostring( hvs_soil ) then
		return hvs
	end
	return nil
end

local function raycastTargetsSoil( result )
	if not result then
		return false
	end
	if result.type == "harvestable" then
		return raycastSoilHarvestable( result ) ~= nil
	end
	return false
end

local function soilHarvestableWorldPos( result )
	if not result then
		return nil
	end
	local hvs = raycastSoilHarvestable( result )
	if hvs then
		local pos = nil
		pcall( function()
			pos = hvs:getPosition()
		end )
		if pos then
			return pos
		end
	end
	if result.pointWorld and type( result.pointWorld.x ) == "number" then
		return result.pointWorld
	end
	return nil
end

local function pickupRayCastSoilCell()
	local valid, result = sm.localPlayer.getLatestRaycast()
	if not valid or not result or not raycastTargetsSoil( result ) then
		return nil
	end
	local pos = soilHarvestableWorldPos( result )
	if not pos then
		return nil
	end
	local cellX, cellY = RfsSoilPlacement.cellFromWorldPos( pos )
	if cellX == nil or cellY == nil then
		return nil
	end
	local gridPosX, gridPosY = RfsSoilPlacement.gridPosFromWorldPos( pos )
	return { cellX = cellX, cellY = cellY, gridPosX = gridPosX, gridPosY = gridPosY }
end

-- Expand pickup rect over terrain or soil under the cursor (same 3x3 cell grid as place).
local function pickupDragRayCastCell()
	local valid, result = sm.localPlayer.getLatestRaycast()
	if not valid or not result then
		return nil
	end
	if raycastTargetsSoil( result ) then
		local pos = soilHarvestableWorldPos( result )
		if not pos then
			return nil
		end
		local cellX, cellY = RfsSoilPlacement.cellFromWorldPos( pos )
		return { cellX = cellX, cellY = cellY }
	end
	if result.type == "terrainSurface" then
		local _, _, cellX, cellY, gridZ = RfsSoilPlacement.snapTerrainSoil( result )
		local groundPointOffset = -( sm.construction.constants.subdivideRatio_2 - 0.04 + sm.construction.constants.shapeSpacing + 0.005 )
		local pointLocal = result.pointLocal + result.normalLocal * groundPointOffset
		local a = pointLocal * sm.construction.constants.subdivisions
		local gridPosX = math.floor( a.x ) - SOIL_SIZE_HALF.x
		local gridPosY = math.floor( a.y ) - SOIL_SIZE_HALF.y
		return { cellX = cellX, cellY = cellY, gridPosX = gridPosX, gridPosY = gridPosY, gridZ = gridZ }
	end
	return nil
end

local function flushTerrainDragBatch( self )
	local dragCells = self._rfsSoilDragCells
	self._rfsSoilDragCells = nil
	self._rfsSoilDragStartCell = nil
	self._rfsSoilDragging = false
	clearDragPreviews( self )
	if not dragCells then
		return
	end

	local slot = sm.localPlayer.getSelectedHotbarSlot()
	local sent = 0
	-- sv_n_putSoil is registered on SoilBag at class load; runtime sv_n_putSoilBatch is not.
	for _, cell in pairs( dragCells ) do
		if cell.pos and type( cell.pos.x ) == "number" then
			if cell.fromBody == true or ( cell.flat ~= false and not cell.blocked ) then
				self.network:sendToServer( "sv_n_putSoil", {
					pos = cell.pos,
					slot = slot,
					fromBody = cell.fromBody == true,
				} )
				sent = sent + 1
			end
		end
	end
	if sent > 0 then
		self:putSoil()
	end
end


-- SoilBag often emits start/stop without hold; latch held between them.
local function updatePrimaryHeldLatch( self, primaryState )
	if primaryState == sm.tool.interactState.start
		or primaryState == sm.tool.interactState.hold then
		self._rfsSoilPrimaryHeld = true
	elseif primaryState == sm.tool.interactState.stop then
		self._rfsSoilPrimaryHeld = false
	end
	return self._rfsSoilPrimaryHeld == true
end

local function updateSecondaryHeldLatch( self, secondaryState )
	if secondaryState == sm.tool.interactState.start
		or secondaryState == sm.tool.interactState.hold then
		self._rfsSoilSecondaryHeld = true
	elseif secondaryState == sm.tool.interactState.stop then
		self._rfsSoilSecondaryHeld = false
	end
	return self._rfsSoilSecondaryHeld == true
end

local function clearPlacementDragState( self )
	self._rfsSoilDragging = false
	self._rfsSoilDragKey = nil
	self._rfsSoilDragStartCell = nil
	self._rfsSoilDragCells = nil
	self._rfsSoilPrimaryHeld = false
end

local function resetTerrainDrag( self )
	self._rfsSoilDragging = false
	self._rfsSoilDragKey = nil
	self._rfsSoilDragStartCell = nil
	self._rfsSoilDragCells = nil
end

-- Terrain: start arms drag; stop is handled by flushTerrainDragBatch (do not clear cells here).
local function updateTerrainDragLatch( self, primaryState, fromBody )
	if fromBody then
		resetTerrainDrag( self )
		return false
	end
	if primaryState == sm.tool.interactState.start then
		self._rfsSoilDragging = true
	end
	return self._rfsSoilDragging == true and self._rfsSoilPrimaryHeld == true
end

-- Engine may omit forceBuildActive during drag multi-place; probe + sticky latch.
local function probeForceBuildFlag()
	local ok, v = pcall( function()
		if type( sm.localPlayer.isForceBuilding ) == "function" then
			return sm.localPlayer.isForceBuilding()
		end
		if type( sm.localPlayer.getForceBuilding ) == "function" then
			return sm.localPlayer.getForceBuilding()
		end
		return nil
	end )
	if ok and v then
		return true
	end
	ok, v = pcall( function()
		if type( sm.build ) == "table" and type( sm.build.isForceBuilding ) == "function" then
			return sm.build.isForceBuilding()
		end
		return nil
	end )
	return ok and v == true
end

-- Sticky only while LMB is held so mid-drag omitted forceBuild flags do not abort place.
-- Clearing on stop alone left the latch stuck and ate every subsequent Soil Bag start.
local function isForceBuildMode( self, forceBuildActive, primaryState )
	local active = forceBuildActive == true or probeForceBuildFlag()
	if active then
		self._rfsForceBuildLatch = true
		return true
	end
	if self._rfsForceBuildLatch then
		if primaryState == sm.tool.interactState.hold
			or self._rfsSoilPrimaryHeld == true then
			return true
		end
		self._rfsForceBuildLatch = false
	end
	return false
end

function RfsSoilPlacement.soilBagItemUuid()
	local soilItem = obj_consumable_soilbag
	pcall( function()
		if ITEMS and ITEMS.obj_consumable_soilbag then
			soilItem = ITEMS.obj_consumable_soilbag
		end
	end )
	return soilItem
end

function RfsSoilPlacement.soilBagToolUuid()
	return SOIL_TOOL_UUID
end

local function uuidMatches( a, b )
	return a and b and tostring( a ) == tostring( b )
end

function RfsSoilPlacement.localPlayerWieldsSoilBag()
	local soilItem = RfsSoilPlacement.soilBagItemUuid()
	local soilTool = RfsSoilPlacement.soilBagToolUuid()
	local activeItem = nil
	pcall( function()
		activeItem = sm.localPlayer.getActiveItem()
	end )
	if uuidMatches( activeItem, soilItem ) or uuidMatches( activeItem, soilTool ) then
		return true
	end
	local slot = nil
	pcall( function()
		slot = sm.localPlayer.getSelectedHotbarSlot()
	end )
	if slot ~= nil then
		local inv = nil
		pcall( function()
			inv = sm.localPlayer.getInventory()
		end )
		if inv then
			local ok, item = pcall( function()
				return inv:getItem( slot )
			end )
			if ok and item and uuidMatches( item.uuid, soilItem ) then
				return true
			end
		end
	end
	return false
end

function RfsSoilPlacement.playerKey( player )
	if not player then
		return nil
	end
	local id = nil
	pcall( function()
		id = player.id
	end )
	if id ~= nil then
		return tostring( id )
	end
	return tostring( player )
end

function RfsSoilPlacement.setServerPickupBlock( player, block )
	local key = RfsSoilPlacement.playerKey( player )
	if not key then
		return
	end
	RfsSoilPlacement._serverPickupBlock = RfsSoilPlacement._serverPickupBlock or {}
	if block then
		RfsSoilPlacement._serverPickupBlock[key] = true
	else
		RfsSoilPlacement._serverPickupBlock[key] = nil
	end
	-- Game.sv is readable from harvestable Logic Task VMs (per-player RMB block flag).
	pcall( function()
		local game = sm.game.getCurrentGame()
		if game then
			game.sv = game.sv or {}
			game.sv.rfsSoilPickupBlock = game.sv.rfsSoilPickupBlock or {}
			if block then
				game.sv.rfsSoilPickupBlock[key] = true
			else
				game.sv.rfsSoilPickupBlock[key] = nil
			end
		end
	end )
end

function RfsSoilPlacement.isServerPickupBlocked( player )
	local key = RfsSoilPlacement.playerKey( player )
	if not key then
		return false
	end
	local blocked = false
	pcall( function()
		local game = sm.game.getCurrentGame()
		if game and game.sv and game.sv.rfsSoilPickupBlock and game.sv.rfsSoilPickupBlock[key] then
			blocked = true
		end
	end )
	if blocked then
		return true
	end
	RfsSoilPlacement._serverPickupBlock = RfsSoilPlacement._serverPickupBlock or {}
	return RfsSoilPlacement._serverPickupBlock[key] == true
end

function RfsSoilPlacement.setClientPickupBlock( tool, block )
	_G.g_rfsSoilPickupBlockClient = block == true
	if tool and tool.network then
		pcall( function()
			tool.network:sendToServer( "sv_n_soilPickupBlock", {
				block = block == true,
			} )
		end )
	elseif block ~= nil then
		pcall( function()
			local game = sm.game.getCurrentGame()
			local player = sm.localPlayer.getPlayer()
			if game and game.network and player then
				game.network:sendToServer( "sv_e_rfsSoilPickupBlock", {
					player = player,
					block = block == true,
				} )
			end
		end )
	end
end

local function activeHotbarItemUuid()
	local uuid = nil
	pcall( function()
		uuid = sm.localPlayer.getActiveItem()
	end )
	if uuid and uuid ~= sm.uuid.getNil() then
		return uuid
	end
	local slot = nil
	pcall( function()
		slot = sm.localPlayer.getSelectedHotbarSlot()
	end )
	if slot == nil then
		return nil
	end
	pcall( function()
		local inv = sm.localPlayer.getInventory()
		if inv then
			local item = inv:getItem( slot )
			if item and item.uuid and item.uuid ~= sm.uuid.getNil() then
				uuid = item.uuid
			end
		end
	end )
	return uuid
end

function RfsSoilPlacement.localPlayerCanSoilHandPickup()
	if RfsSoilPlacement.localPlayerWieldsSoilBag() then
		return false
	end
	if type( RfsCarry ) == "table" and type( RfsCarry.localIsCarrying ) == "function" then
		if RfsCarry.localIsCarrying() then
			return false
		end
	end
	local uuid = activeHotbarItemUuid()
	if not uuid then
		return true
	end
	local isTool = false
	pcall( function()
		isTool = sm.item.isTool( uuid )
	end )
	if isTool then
		return false
	end
	local isBlock = false
	pcall( function()
		isBlock = sm.item.isBlock( uuid )
	end )
	return isBlock == true
end

function RfsSoilPlacement.playerCanSoilHandPickup( player )
	if RfsSoilPlacement.playerWieldsSoilBag( player ) then
		return false
	end
	if type( RfsCarry ) == "table" and type( RfsCarry.playerIsCarrying ) == "function" then
		if RfsCarry.playerIsCarrying( player ) then
			return false
		end
	end
	local inv = nil
	pcall( function()
		inv = player:getInventory()
	end )
	if not inv then
		return false
	end
	local sel = nil
	pcall( function()
		sel = player:getSelectedHotbarSlot()
	end )
	if sel == nil then
		return true
	end
	local item = nil
	pcall( function()
		item = inv:getItem( sel )
	end )
	if not item or not item.uuid or item.uuid == sm.uuid.getNil() then
		return true
	end
	local isTool = false
	pcall( function()
		isTool = sm.item.isTool( item.uuid )
	end )
	if isTool then
		return false
	end
	local isBlock = false
	pcall( function()
		isBlock = sm.item.isBlock( item.uuid )
	end )
	return isBlock == true
end

function RfsSoilPlacement.localBlocksVanillaSoilPickup()
	if RfsSoilPlacement.localPlayerWieldsSoilBag() then
		return fastPickupActive()
	end
	return _G.g_rfsSoilPickupBlockClient == true
		or RfsSoilPlacement._handPickupAttackHeld == true
end

function RfsSoilPlacement.playerBlocksVanillaSoilPickup( player )
	if RfsSoilPlacement.playerWieldsSoilBag( player ) then
		return fastPickupActive()
	end
	return RfsSoilPlacement.isServerPickupBlocked( player )
end

local function sendPickupBatchViaGame( params )
	pcall( function()
		local game = sm.game.getCurrentGame()
		local player = sm.localPlayer.getPlayer()
		if game and game.network and player and type( params ) == "table" then
			game.network:sendToServer( "sv_e_rfsPickupSoilBatch", {
				player = player,
				minCellX = params.minCellX,
				maxCellX = params.maxCellX,
				minCellY = params.minCellY,
				maxCellY = params.maxCellY,
			} )
		end
	end )
end

function RfsSoilPlacement.destroySoilHarvestableAfterCollect( hvs )
	if not hvs or not sm.exists( hvs ) then
		return false
	end
	local ok = false
	pcall( function()
		sm.event.sendToHarvestable( hvs, "sv_e_rfsBatchPickupDestroy", {} )
		ok = true
	end )
	if ok then
		return true
	end
	pcall( function()
		if sm.exists( hvs ) then
			hvs:destroy()
		end
	end )
	return true
end

function RfsSoilPlacement.playerWieldsSoilBag( player )
	if not player then
		return false
	end
	local soilItem = RfsSoilPlacement.soilBagItemUuid()
	local soilTool = RfsSoilPlacement.soilBagToolUuid()

	-- Server path: active equipped tool on character (colon API).
	local char = nil
	pcall( function()
		char = player:getCharacter()
	end )
	if char then
		local tool = nil
		pcall( function()
			tool = char:getActiveTool()
		end )
		if not tool then
			pcall( function()
				tool = char:getTool()
			end )
		end
		if tool and sm.exists( tool ) then
			local itemUuid = nil
			local toolUuid = nil
			pcall( function()
				itemUuid = tool:getItemUuid()
			end )
			pcall( function()
				toolUuid = tool:getUuid()
			end )
			if uuidMatches( itemUuid, soilItem ) or uuidMatches( toolUuid, soilTool ) then
				return true
			end
		end
	end

	-- Hotbar slot item (works client-side; safe no-op if API missing on server).
	local inv = nil
	pcall( function()
		inv = player:getInventory()
	end )
	if inv then
		local sel = nil
		pcall( function()
			sel = player:getSelectedHotbarSlot()
		end )
		if sel ~= nil then
			local ok, item = pcall( function()
				return inv:getItem( sel )
			end )
			if ok and item and uuidMatches( item.uuid, soilItem ) then
				return true
			end
		end
	end

	return false
end

function RfsSoilPlacement.isPlacementBlocked( worldPos, fromBody, normalWorld )
	if fromBody then
		return sm.physics.sphereHasContact( worldPos, 0.28, nil, nil, BLOCK_SOIL_MASK )
	end
	return sm.physics.sphereHasContact( worldPos, 0.375, nil, nil, TERRAIN_PLACEMENT_MASK )
end

function RfsSoilPlacement.constructionRayCast( self )
	if not soilAllowedInWorld() then
		self._rfsSoilFromBody = false
		self._rfsSoilGridX = nil
		self._rfsSoilGridY = nil
		return false
	end

	local valid, result = sm.localPlayer.getLatestRaycast()
	if not valid or not result then
		self._rfsSoilFromBody = false
		self._rfsSoilGridX = nil
		self._rfsSoilGridY = nil
		self._rfsSoilGridZ = nil
		return false
	end
	if raycastTargetsSoil( result ) then
		self._rfsSoilFromBody = false
		self._rfsSoilGridX = nil
		self._rfsSoilGridY = nil
		self._rfsSoilGridZ = nil
		return false
	end

	if result.type == "terrainSurface" then
		local snapPos, worldNormal, cellX, cellY, gridZ = RfsSoilPlacement.snapTerrainSoil( result )
		-- Cell-aligned XY for non-overlapping drag; Z from subdiv snap (same as vanilla).
		local worldPos = RfsSoilPlacement.worldPosForTerrainCell( cellX, cellY, gridZ )
		if not worldPos or type( worldPos.x ) ~= "number" then
			worldPos = snapPos
		end
		self._rfsSoilFromBody = false
		self._rfsSoilGridX = cellX
		self._rfsSoilGridY = cellY
		self._rfsSoilGridZ = gridZ
		return true, worldPos, worldNormal
	end

	if not dirtOnBlocksActive() then
		self._rfsSoilFromBody = false
		self._rfsSoilGridX = nil
		self._rfsSoilGridY = nil
		return false
	end
	if result.type ~= "body" and result.type ~= "lift" then
		self._rfsSoilFromBody = false
		self._rfsSoilGridX = nil
		self._rfsSoilGridY = nil
		return false
	end

	local normal = result.normalWorld
	if not normal then
		self._rfsSoilFromBody = false
		self._rfsSoilGridY = nil
		self._rfsSoilGridX = nil
		return false
	end

	local worldPos = RfsSoilPlacement.snapWorldSoilPos( result.pointWorld, normal )
	local cellX, cellY = RfsSoilPlacement.cellFromWorldPos( worldPos )
	self._rfsSoilFromBody = true
	self._rfsSoilGridX = cellX
	self._rfsSoilGridY = cellY
	self._rfsSoilGridZ = nil
	return true, worldPos, normal
end

function RfsSoilPlacement.client_onEquippedUpdate( self, primaryState, secondaryState, forceBuildActive )
	if not self.tool:isLocal() then
		return false, false
	end

	if not SoilBag._rfsSoilPlacementHooked then
		RfsSoilPlacement.ensureHooks()
	end

	if not self.effect then
		return false, false
	end

	if isForceBuildMode( self, forceBuildActive, primaryState ) then
		if self.effect and self.effect:isPlaying() then
			self.effect:stop()
		end
		clearPlacementDragState( self )
		clearDragPreviews( self )
		resetPickupDrag( self )
		return false, false
	end

	-- RMB rect batch pickup (fast pickup ON): claim secondary while RMB held so the
	-- engine never starts vanilla HarvestableSoil hold pickup. Flush batch on release
	-- only when a soil start cell was armed (tap = 1 cell, drag = rect).
	local fastPickup = fastPickupActive()
	local secondaryWasHeld = self._rfsSoilSecondaryHeld == true
	local secondaryHeld = updateSecondaryHeldLatch( self, secondaryState )
	local secondaryActive = fastPickup and (
		secondaryPickupActive( secondaryState )
		or secondaryHeld
		or ( secondaryState == sm.tool.interactState.stop and secondaryWasHeld )
	)

	if secondaryActive then
		if secondaryState == sm.tool.interactState.start then
			RfsSoilPlacement.setClientPickupBlock( self, true )
		end

		local cursorSoilCell = pickupRayCastSoilCell()
		if cursorSoilCell then
			self._rfsSoilCursorCell = cursorSoilCell
		end

		if secondaryState == sm.tool.interactState.start then
			local soilStartCell = cursorSoilCell or self._rfsSoilCursorCell
			if soilStartCell then
				self._rfsSoilPickupStartCell = soilStartCell
				self._rfsSoilPickupDragging = false
				self._rfsSoilPickupDragCells = nil
			end
		end

		local pickupArmed = self._rfsSoilPickupStartCell ~= nil
		local overSoil = cursorSoilCell ~= nil or self._rfsSoilCursorCell ~= nil
		if overSoil and not pickupArmed then
			self._rfsSoilPickupStartCell = cursorSoilCell or self._rfsSoilCursorCell
			pickupArmed = self._rfsSoilPickupStartCell ~= nil
		end

		if pickupArmed then
			local dragCell = pickupDragRayCastCell()
			if dragCell and dragCell.cellX ~= nil and dragCell.cellY ~= nil then
				if dragCell.cellX ~= self._rfsSoilPickupStartCell.cellX
					or dragCell.cellY ~= self._rfsSoilPickupStartCell.cellY then
					self._rfsSoilPickupDragging = true
				end
				rebuildPickupDragRect(
					self,
					self._rfsSoilPickupStartCell,
					dragCell.cellX,
					dragCell.cellY,
					dragCell.gridZ
				)
			elseif not self._rfsSoilPickupDragCells then
				rebuildPickupDragRect(
					self,
					self._rfsSoilPickupStartCell,
					self._rfsSoilPickupStartCell.cellX,
					self._rfsSoilPickupStartCell.cellY,
					self._rfsSoilPickupStartCell.gridZ
				)
			end
			syncDragPreviews( self, self._rfsSoilPickupDragCells, true )
		else
			clearDragPreviews( self )
		end

		if self.effect and self.effect:isPlaying() then
			self.effect:stop()
		end
		clearPlacementDragState( self )

		if secondaryState == sm.tool.interactState.stop then
			if pickupArmed then
				flushPickupDragBatch( self )
			else
				resetPickupDrag( self )
				clearDragPreviews( self )
			end
			RfsSoilPlacement.setClientPickupBlock( self, false )
		end

		return true, true
	end

	if not fastPickup and secondaryState == sm.tool.interactState.stop then
		resetPickupDrag( self )
		clearDragPreviews( self )
		RfsSoilPlacement.setClientPickupBlock( self, false )
	end

	if secondaryState == sm.tool.interactState.stop then
		RfsSoilPlacement.setClientPickupBlock( self, false )
		resetPickupDrag( self )
	end

	local primaryHeld = updatePrimaryHeldLatch( self, primaryState )
	local fastPlace = fastPlaceActive()

	local valid, worldPos, worldNormal = self:constructionRayCast()
	if not valid then
		if self.effect then
			self.effect:stop()
		end
		if primaryState == sm.tool.interactState.stop and self._rfsSoilDragging then
			flushTerrainDragBatch( self )
		end
		clearDragPreviews( self )
		return false, false
	end

	local fromBody = self._rfsSoilFromBody == true
	if fromBody then
		if fastPlace then
			if primaryState == sm.tool.interactState.start
				and not secondaryPickupActive( secondaryState ) then
				self._rfsSoilDragging = true
				self._rfsSoilDragCells = {}
				self._rfsSoilDragStartCell = nil
			end
		else
			resetTerrainDrag( self )
		end
	elseif fastPlace then
		updateTerrainDragLatch( self, primaryState, fromBody )
		if primaryState == sm.tool.interactState.start
			and not secondaryPickupActive( secondaryState ) then
			self._rfsSoilDragging = true
			self._rfsSoilDragCells = {}
			self._rfsSoilDragStartCell = nil
		end
	else
		resetTerrainDrag( self )
	end

	local flat = RfsSoilPlacement.isFlatSurface( worldNormal )
	local blocked = false
	if flat then
		blocked = RfsSoilPlacement.isPlacementBlocked( worldPos, fromBody, worldNormal )
	end
	local cellX = self._rfsSoilGridX
	local cellY = self._rfsSoilGridY
	local gridZ = self._rfsSoilGridZ
	if fromBody and ( cellX == nil or cellY == nil ) then
		cellX, cellY = RfsSoilPlacement.cellFromWorldPos( worldPos )
	end

	local dragHeld = self._rfsSoilDragging
		and ( primaryHeld or primaryState == sm.tool.interactState.stop )
	local blockDragActive = fastPlace and fromBody and dragHeld
	local terrainDragActive = fastPlace and not fromBody and dragHeld

	if blockDragActive or terrainDragActive then
		local keyBindingText = sm.gui.getKeyBinding( "Create", true )
		sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_PUT_SOIL}" )
		if cellX ~= nil and cellY ~= nil then
			if primaryState == sm.tool.interactState.start
				and not self._rfsSoilDragStartCell then
				self._rfsSoilDragStartCell = {
					cellX = cellX,
					cellY = cellY,
					gridZ = gridZ,
					refWorldZ = worldPos.z,
					worldPos = worldPos,
					normal = worldNormal,
					flat = flat,
					fromBody = fromBody,
				}
			end
			if self._rfsSoilDragStartCell then
				if fromBody then
					rebuildBlockDragRect(
						self,
						self._rfsSoilDragStartCell,
						cellX,
						cellY,
						worldPos.z
					)
				else
					rebuildTerrainDragRect(
						self,
						self._rfsSoilDragStartCell,
						cellX,
						cellY
					)
				end
			end
		end
		syncDragPreviews( self, self._rfsSoilDragCells )
		if self.effect then
			self.effect:setParameter( "visualization", true )
			self.effect:setPosition( worldPos )
			self.effect:setRotation( SOIL_PREVIEW_ROT )
			local previewColor = "Lift Valid"
			if not flat or blocked then
				previewColor = "Lift Invalid"
			end
			self.effect:setParameter( "visualizationColor", previewColor )
			if not self.effect:isPlaying() then
				self.effect:start()
			end
		end
	elseif not flat then
		sm.gui.setInteractionText( "#{INFO_TOO_STEEP}" )
		if self.effect then
			self.effect:setParameter( "visualization", true )
			self.effect:setPosition( worldPos )
			self.effect:setRotation( SOIL_PREVIEW_ROT )
			self.effect:setParameter( "visualizationColor", "Lift Invalid" )
		end
	else
		blocked = RfsSoilPlacement.isPlacementBlocked( worldPos, fromBody, worldNormal )
		if blocked then
			if self.effect then
				self.effect:setParameter( "visualization", true )
				self.effect:setPosition( worldPos )
				self.effect:setRotation( SOIL_PREVIEW_ROT )
				self.effect:setParameter( "visualizationColor", "Lift Invalid" )
			end
		else
			local keyBindingText = sm.gui.getKeyBinding( "Create", true )
			sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_PUT_SOIL}" )

			if fromBody or not fastPlace then
				-- Blocks/lifts or terrain with fast place OFF: single click on start.
				if primaryState == sm.tool.interactState.start
					and not secondaryPickupActive( secondaryState ) then
					self.network:sendToServer( "sv_n_putSoil", {
						pos = worldPos,
						slot = sm.localPlayer.getSelectedHotbarSlot(),
						fromBody = fromBody,
					} )
					self:putSoil()
				end
				if self.effect then
					self.effect:setParameter( "visualization", true )
					self.effect:setPosition( worldPos )
					self.effect:setRotation( SOIL_PREVIEW_ROT )
					self.effect:setParameter( "visualizationColor", "Lift Valid" )
				end
			elseif self.effect then
				self.effect:setParameter( "visualization", true )
				self.effect:setPosition( worldPos )
				self.effect:setRotation( SOIL_PREVIEW_ROT )
				self.effect:setParameter( "visualizationColor", "Lift Valid" )
			end
		end
	end

	if fastPlace and primaryState == sm.tool.interactState.stop and self._rfsSoilDragging then
		flushTerrainDragBatch( self )
	end

	local keyBindingText = sm.gui.getKeyBinding( "ForceBuild", true )
	sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_FORCE_BUILD}" )

	if not blockDragActive and not terrainDragActive then
		if self.effect and not self.effect:isPlaying() then
			self.effect:start()
		end
	end
	return true, false
end

function RfsSoilPlacement.handPickupContext()
	local ctx = RfsSoilPlacement._handPickupCtx
	if ctx then
		return ctx
	end
	ctx = {
		network = {
			sendToServer = function( _, name, params )
				if name == "sv_n_pickupSoilBatch" then
					sendPickupBatchViaGame( params )
				end
			end,
		},
	}
	RfsSoilPlacement._handPickupCtx = ctx
	return ctx
end

-- Empty hand or hotbar block: RMB rect pickup over soil (fast pickup ON only).
function RfsSoilPlacement.client_updateHandPickupDrag( secondaryState )
	if not fastPickupActive() then
		return false, false
	end
	if not RfsSoilPlacement.localPlayerCanSoilHandPickup() then
		return false, false
	end

	RfsSoilPlacement.ensureHarvestableSoilHooks()

	local ctx = RfsSoilPlacement.handPickupContext()
	local secondaryWasHeld = ctx._rfsSoilSecondaryHeld == true
	local secondaryHeld = updateSecondaryHeldLatch( ctx, secondaryState )
	local secondaryActive = secondaryPickupActive( secondaryState )
		or secondaryHeld
		or ( secondaryState == sm.tool.interactState.stop and secondaryWasHeld )

	if not secondaryActive then
		if secondaryState == sm.tool.interactState.stop then
			RfsSoilPlacement.setClientPickupBlock( nil, false )
			resetPickupDrag( ctx )
		end
		return false, false
	end

	local cursorSoilCell = pickupRayCastSoilCell()
	if cursorSoilCell then
		ctx._rfsSoilCursorCell = cursorSoilCell
	end
	local overSoil = cursorSoilCell ~= nil or ctx._rfsSoilCursorCell ~= nil

	if secondaryState == sm.tool.interactState.start and overSoil then
		RfsSoilPlacement.setClientPickupBlock( nil, true )
		local soilStartCell = cursorSoilCell or ctx._rfsSoilCursorCell
		if soilStartCell then
			ctx._rfsSoilPickupStartCell = soilStartCell
			ctx._rfsSoilPickupDragging = false
			ctx._rfsSoilPickupDragCells = nil
		end
	end

	local pickupArmed = ctx._rfsSoilPickupStartCell ~= nil
	if overSoil and not pickupArmed then
		ctx._rfsSoilPickupStartCell = cursorSoilCell or ctx._rfsSoilCursorCell
		pickupArmed = ctx._rfsSoilPickupStartCell ~= nil
	end

	if pickupArmed then
		local dragCell = pickupDragRayCastCell()
		if dragCell and dragCell.cellX ~= nil and dragCell.cellY ~= nil then
			if dragCell.cellX ~= ctx._rfsSoilPickupStartCell.cellX
				or dragCell.cellY ~= ctx._rfsSoilPickupStartCell.cellY then
				ctx._rfsSoilPickupDragging = true
			end
			rebuildPickupDragRect(
				ctx,
				ctx._rfsSoilPickupStartCell,
				dragCell.cellX,
				dragCell.cellY,
				dragCell.gridZ
			)
		elseif not ctx._rfsSoilPickupDragCells then
			rebuildPickupDragRect(
				ctx,
				ctx._rfsSoilPickupStartCell,
				ctx._rfsSoilPickupStartCell.cellX,
				ctx._rfsSoilPickupStartCell.cellY,
				ctx._rfsSoilPickupStartCell.gridZ
			)
		end
		syncDragPreviews( ctx, ctx._rfsSoilPickupDragCells, true )
	else
		clearDragPreviews( ctx )
	end

	if secondaryState == sm.tool.interactState.stop then
		if pickupArmed then
			flushPickupDragBatch( ctx )
		else
			resetPickupDrag( ctx )
			clearDragPreviews( ctx )
		end
		RfsSoilPlacement.setClientPickupBlock( nil, false )
		return false, false
	end

	if pickupArmed or overSoil then
		return false, true
	end
	return false, false
end

function RfsSoilPlacement.carryToolEquippedUpdate( self, primaryState, secondaryState )
	-- CarryTool is the shoulder-carry slot, not empty hotbar / block hand (see client_tickHandPickup).
	if self.tool and self.tool:isLocal() and RfsSoilPlacement.localPlayerCanSoilHandPickup() then
		local claimPrimary, claimSecondary = RfsSoilPlacement.client_updateHandPickupDrag( secondaryState )
		if claimPrimary or claimSecondary then
			return claimPrimary, claimSecondary
		end
	end
	if RfsSoilPlacement._origCarryEquippedUpdate then
		return RfsSoilPlacement._origCarryEquippedUpdate( self, primaryState, secondaryState )
	end
	return false, false
end

-- Attack (RMB) from Player.client_onAction: consume before vanilla harvestable hold.
-- secondaryInteractBusy remains a fallback if the engine starts hold without action edges.
function RfsSoilPlacement.tryConsumeHandPickupAction( action, state )
	if action ~= sm.interactable.actions.attack then
		return false
	end
	if not fastPickupActive() then
		return false
	end
	if not RfsSoilPlacement.localPlayerCanSoilHandPickup() then
		if RfsSoilPlacement._handPickupAttackHeld or RfsSoilPlacement._handPickupAttackPrev then
			RfsSoilPlacement._handPickupAttackHeld = false
			RfsSoilPlacement._handPickupAttackPrev = false
			RfsSoilPlacement.setClientPickupBlock( nil, false )
		end
		return false
	end

	RfsSoilPlacement.ensureHarvestableSoilHooks()

	if state == true then
		local cell = pickupRayCastSoilCell()
		if not cell then
			return false
		end
		RfsSoilPlacement._handPickupAttackHeld = true
		RfsSoilPlacement._handPickupAttackPrev = true
		RfsSoilPlacement.setClientPickupBlock( nil, true )
		RfsSoilPlacement.client_updateHandPickupDrag( sm.tool.interactState.start )
		if g_survivalDev then
			print( string.format(
				"[RFS] hand pickup attack down cell=%d,%d",
				cell.cellX, cell.cellY
			) )
		end
		return true
	end

	if RfsSoilPlacement._handPickupAttackHeld or RfsSoilPlacement._handPickupAttackPrev then
		RfsSoilPlacement._handPickupAttackHeld = false
		RfsSoilPlacement._handPickupAttackPrev = false
		RfsSoilPlacement.client_updateHandPickupDrag( sm.tool.interactState.stop )
		if g_survivalDev then
			print( "[RFS] hand pickup attack up flush" )
		end
		return true
	end
	return false
end

function RfsSoilPlacement.pollHandPickupAttackState()
	local attackHeld = RfsSoilPlacement._handPickupAttackHeld == true
	local busy = false
	pcall( function()
		busy = sm.localPlayer.secondaryInteractBusy()
	end )
	local held = attackHeld or busy
	local prev = RfsSoilPlacement._handPickupAttackPrev == true
		or RfsSoilPlacement._handPickupInteractBusy == true
	RfsSoilPlacement._handPickupAttackPrev = attackHeld
	RfsSoilPlacement._handPickupInteractBusy = busy
	if held and not prev then
		return sm.tool.interactState.start
	end
	if held then
		return sm.tool.interactState.hold
	end
	if prev and not held then
		return sm.tool.interactState.stop
	end
	return nil
end

function RfsSoilPlacement.client_tickHandPickup()
	RfsSoilPlacement.ensurePlayerHandPickupHooks()

	if not fastPickupActive() then
		if RfsSoilPlacement._handPickupAttackHeld
			or RfsSoilPlacement._handPickupInteractBusy
			or RfsSoilPlacement._handPickupAttackPrev then
			RfsSoilPlacement._handPickupAttackHeld = false
			RfsSoilPlacement._handPickupAttackPrev = false
			RfsSoilPlacement._handPickupInteractBusy = false
			resetPickupDrag( RfsSoilPlacement.handPickupContext() )
			clearDragPreviews( RfsSoilPlacement.handPickupContext() )
			RfsSoilPlacement.setClientPickupBlock( nil, false )
		end
		return
	end

	if not RfsSoilPlacement.localPlayerCanSoilHandPickup() then
		if RfsSoilPlacement._handPickupAttackHeld
			or RfsSoilPlacement._handPickupInteractBusy
			or RfsSoilPlacement._handPickupAttackPrev then
			RfsSoilPlacement._handPickupAttackHeld = false
			RfsSoilPlacement._handPickupAttackPrev = false
			RfsSoilPlacement._handPickupInteractBusy = false
			resetPickupDrag( RfsSoilPlacement.handPickupContext() )
			clearDragPreviews( RfsSoilPlacement.handPickupContext() )
			RfsSoilPlacement.setClientPickupBlock( nil, false )
		end
		return
	end

	RfsSoilPlacement.ensureHarvestableSoilHooks()

	if RfsSoilPlacement._handPickupAttackHeld then
		RfsSoilPlacement.client_updateHandPickupDrag( sm.tool.interactState.hold )
		return
	end

	local secondaryState = RfsSoilPlacement.pollHandPickupAttackState()
	if secondaryState == nil then
		return
	end
	RfsSoilPlacement.client_updateHandPickupDrag( secondaryState )
end

function RfsSoilPlacement.ensurePlayerHandPickupHooks()
	if type( Player ) ~= "table" then
		return false
	end
	local ourHook = RfsSoilPlacement._playerHandPickupActionHook
	if ourHook and Player.client_onAction == ourHook then
		return true
	end
	local orig = Player.client_onAction
	function RfsSoilPlacement._playerHandPickupActionHook( self, action, state )
		if self.player == sm.localPlayer.getPlayer() then
			if RfsSoilPlacement.tryConsumeHandPickupAction( action, state ) then
				return true
			end
		end
		if orig then
			return orig( self, action, state )
		end
	end
	Player.client_onAction = RfsSoilPlacement._playerHandPickupActionHook
	Player._rfsSoilHandPickupActionHook = true
	if g_survivalDev then
		print( "[RFS] RfsSoilPlacement hooked Player.client_onAction (hand soil Attack block)" )
	end
	return true
end

function RfsSoilPlacement.ensureCarryToolHooks()
	if type( CarryTool ) ~= "table" then
		pcall( function()
			dofile( "$SURVIVAL_DATA/Scripts/game/tools/CarryTool.lua" )
		end )
	end
	if type( CarryTool ) ~= "table" then
		return false
	end
	if CarryTool._rfsSoilHandPickupHooked
		and CarryTool.client_onEquippedUpdate == RfsSoilPlacement.carryToolEquippedUpdate then
		return true
	end
	if not RfsSoilPlacement._origCarryEquippedUpdate then
		RfsSoilPlacement._origCarryEquippedUpdate = CarryTool.client_onEquippedUpdate
	end
	CarryTool.client_onEquippedUpdate = RfsSoilPlacement.carryToolEquippedUpdate
	CarryTool._rfsSoilHandPickupHooked = true
	if not RfsSoilPlacement._carryToolHookLogged then
		RfsSoilPlacement._carryToolHookLogged = true
		print( "[RFS] RfsSoilPlacement hooked CarryTool (empty hand / block soil RMB rect pickup)" )
	end
	return true
end

function RfsSoilPlacement.sv_pickupSoilBatchForPlayer( player, params, tool )
	if not player or type( params ) ~= "table" then
		return false
	end
	local okServer, serverMode = pcall( sm.isServerMode )
	if not okServer or not serverMode then
		return false
	end
	local minCellX = tonumber( params.minCellX )
	local maxCellX = tonumber( params.maxCellX )
	local minCellY = tonumber( params.minCellY )
	local maxCellY = tonumber( params.maxCellY )
	if not minCellX or not maxCellX or not minCellY or not maxCellY then
		return false
	end
	if minCellX > maxCellX then
		minCellX, maxCellX = maxCellX, minCellX
	end
	if minCellY > maxCellY then
		minCellY, maxCellY = maxCellY, minCellY
	end

	local world = nil
	pcall( function()
		local character = player:getCharacter()
		if character then
			world = character:getWorld()
		end
	end )
	if not world then
		pcall( function()
			world = sm.world.getCurrentWorld()
		end )
	end
	if not world then
		return false
	end

	local soilItem = obj_consumable_soilbag
	pcall( function()
		if ITEMS and ITEMS.obj_consumable_soilbag then
			soilItem = ITEMS.obj_consumable_soilbag
		end
	end )

	local toPickup = {}
	local ok, list = pcall( sm.harvestable.getAllHarvestables, world )
	if ok and type( list ) == "table" then
		for _, hvs in ipairs( list ) do
			if hvs and sm.exists( hvs ) then
				local uid = nil
				pcall( function()
					uid = hvs:getUuid()
				end )
				local isSoil = false
				if uid then
					if type( RfsFarming ) == "table" and type( RfsFarming.isSoilUuid ) == "function" then
						isSoil = RfsFarming.isSoilUuid( uid )
					elseif hvs_soil then
						isSoil = tostring( uid ) == tostring( hvs_soil )
					end
				end
				if isSoil then
					local pos = nil
					pcall( function()
						pos = hvs:getPosition()
					end )
					if pos then
						local cellX, cellY = RfsSoilPlacement.cellFromWorldPos( pos )
						if cellX
							and cellY
							and cellX >= minCellX
							and cellX <= maxCellX
							and cellY >= minCellY
							and cellY <= maxCellY then
							toPickup[#toPickup + 1] = hvs
						end
					end
				end
			end
		end
	end

	local container = player:getInventory()
	local picked = 0
	local inventoryFull = false
	for _, hvs in ipairs( toPickup ) do
		if sm.exists( hvs ) then
			if sm.container.beginTransaction() then
				sm.container.collect( container, soilItem, 1 )
				if sm.container.endTransaction() then
					picked = picked + 1
					RfsSoilPlacement.destroySoilHarvestableAfterCollect( hvs )
				else
					inventoryFull = true
					break
				end
			end
		end
	end

	if picked > 0 then
		print( string.format(
			"[RFS] soil pickup batch picked=%d cells=%d..%d,%d..%d player=%s",
			picked,
			minCellX,
			maxCellX,
			minCellY,
			maxCellY,
			tostring( RfsSoilPlacement.playerKey( player ) )
		) )
	end

	if inventoryFull then
		pcall( function()
			if tool and tool.network then
				tool.network:sendToClient( player, "cl_n_pickupInventoryFull", {} )
			else
				local game = sm.game.getCurrentGame()
				if game and game.network and player then
					game.network:sendToClient( player, "cl_n_rfsPickupInventoryFull", {} )
				elseif type( NotificationManager ) == "table" and NotificationManager.Cl_AddGenericNotification then
					NotificationManager.Cl_AddGenericNotification( "#{INFO_INVENTORY_FULL}", 4 )
				end
			end
		end )
	end
	return inventoryFull
end

function RfsSoilPlacement.sv_n_pickupSoilBatch( self, params, player )
	RfsSoilPlacement.sv_pickupSoilBatchForPlayer( player, params, self )
end

function RfsSoilPlacement.sv_n_soilPickupBlock( self, params, player )
	RfsSoilPlacement.setServerPickupBlock( player, params and params.block == true )
end

function RfsSoilPlacement.cl_n_pickupInventoryFull( self )
	pcall( function()
		if type( NotificationManager ) == "table" and NotificationManager.Cl_AddGenericNotification then
			NotificationManager.Cl_AddGenericNotification( "#{INFO_INVENTORY_FULL}", 4 )
		end
	end )
end

function RfsSoilPlacement.spendSoilBagFromInventory( player, preferredSlot )
	local soilItem = RfsSoilPlacement.soilBagItemUuid()
	sm.container.beginTransaction()
	if preferredSlot ~= nil then
		-- Match vanilla SoilBag.sv_n_putSoil (hotbar slot spend).
		sm.container.spendFromSlot( player:getInventory(), preferredSlot, soilItem, 1, true )
	else
		sm.container.spend( player:getInventory(), soilItem, 1, true )
	end
	return sm.container.endTransaction()
end

function RfsSoilPlacement.sv_n_putSoil( self, params, player )
	local placePos = params.pos
	if placePos and type( placePos.x ) == "number" then
		if params.fromBody then
			-- Reject overlap with other non-static bodies/harvestables (not the platform below).
			if sm.physics.sphereHasContact( placePos, 0.28, nil, nil, BLOCK_SOIL_MASK ) then
				return
			end
		else
			placePos = RfsSoilPlacement.canonicalTerrainPos( placePos )
		end
	end
	if RfsSoilPlacement.spendSoilBagFromInventory( player, params.slot ) then
		sm.harvestable.createHarvestable( hvs_soil, placePos, FIXED_SOIL_ROT )
		sm.effect.playEffect( "Plants - SoilbagUse", placePos, nil, FIXED_SOIL_ROT )
		self.network:sendToClients( "cl_n_putSoil", params )
	end
end

local function rfsSoilServerVm()
	local ok, serverMode = pcall( sm.isServerMode )
	return ok and serverMode == true
end

function RfsSoilPlacement.ensureHarvestableSoilHooks()
	return RfsSoilPlacement.ensureHarvestableHooks()
end

function RfsSoilPlacement.ensureHarvestableHooks()
	if type( HarvestableSoil ) ~= "table" then
		pcall( function()
			dofile( "$SURVIVAL_DATA/Scripts/game/harvestable/HarvestableSoil.lua" )
		end )
	end
	if type( HarvestableSoil ) ~= "table" then
		return false
	end

	if not RfsSoilPlacement._origHarvestableRemoved then
		RfsSoilPlacement._origHarvestableRemoved = HarvestableSoil.server_onRemoved
	end
	if not RfsSoilPlacement._harvestableRemovedHook then
		function RfsSoilPlacement._harvestableRemovedHook( self, player )
			if self.harvested then
				return
			end
			local blocked = RfsSoilPlacement.playerBlocksVanillaSoilPickup( player )
			if _G.g_survivalDev then
				print( "[RFS] HarvestableSoil.server_onRemoved blocked=" .. tostring( blocked ) )
			end
			if blocked then
				return
			end
			return RfsSoilPlacement._origHarvestableRemoved( self, player )
		end
	end

	if not HarvestableSoil.sv_e_rfsBatchPickupDestroy then
		function HarvestableSoil.sv_e_rfsBatchPickupDestroy( self )
			if sm.exists( self.harvestable ) then
				self.harvested = true
				self.harvestable:destroy()
			end
		end
	end

	if rfsSoilServerVm() then
		if HarvestableSoil.server_onRemoved == RfsSoilPlacement._harvestableRemovedHook
			and HarvestableSoil._rfsPickupInterceptServer then
			return true
		end
		HarvestableSoil.server_onRemoved = RfsSoilPlacement._harvestableRemovedHook
		HarvestableSoil._rfsPickupInterceptServer = true
		if not RfsSoilPlacement._harvestableHookLoggedServer then
			RfsSoilPlacement._harvestableHookLoggedServer = true
			print( "[RFS] RfsSoilPlacement hooked HarvestableSoil (server)" )
		end
		return true
	end

	if not RfsSoilPlacement._origHarvestableCanInteract then
		RfsSoilPlacement._origHarvestableCanInteract = HarvestableSoil.client_canInteract
	end
	if HarvestableSoil.client_onInteract and not RfsSoilPlacement._origHarvestableInteract then
		RfsSoilPlacement._origHarvestableInteract = HarvestableSoil.client_onInteract
	end
	if not RfsSoilPlacement._harvestableCanInteractHook then
		function RfsSoilPlacement._harvestableCanInteractHook( self )
			if RfsSoilPlacement.localBlocksVanillaSoilPickup() then
				return false
			end
			if fastPickupActive() and RfsSoilPlacement.localPlayerCanSoilHandPickup() then
				local pickUpPromptsEnabled = true
				pcall( function()
					pickUpPromptsEnabled = sm.game.getSettingBoolean( "PickUpPrompts" )
				end )
				if pickUpPromptsEnabled and not sm.localPlayer.secondaryInteractBusy() then
					sm.gui.setInteractionText(
						"",
						sm.gui.getKeyBinding( "Attack", true ),
						"#{INTERACTION_PICK_UP}"
					)
				end
				-- Must stay false (vanilla): true switches to Use interact and kills Attack-hold.
				return false
			end
			return RfsSoilPlacement._origHarvestableCanInteract( self )
		end
	end
	if not RfsSoilPlacement._harvestableInteractHook then
		function RfsSoilPlacement._harvestableInteractHook( self, character, state )
			if RfsSoilPlacement.localBlocksVanillaSoilPickup() then
				return true
			end
			if fastPickupActive() and RfsSoilPlacement.localPlayerCanSoilHandPickup() then
				local secondaryState = state
				if secondaryState == nil or secondaryState == false then
					secondaryState = sm.tool.interactState.start
				elseif secondaryState == true then
					secondaryState = sm.tool.interactState.hold
				end
				RfsSoilPlacement.client_updateHandPickupDrag( secondaryState )
				return true
			end
			if RfsSoilPlacement._origHarvestableInteract then
				return RfsSoilPlacement._origHarvestableInteract( self, character, state )
			end
		end
	end

	local patched = HarvestableSoil.server_onRemoved == RfsSoilPlacement._harvestableRemovedHook
		and HarvestableSoil.client_canInteract == RfsSoilPlacement._harvestableCanInteractHook
		and HarvestableSoil.client_onInteract == RfsSoilPlacement._harvestableInteractHook
	if patched and HarvestableSoil._rfsPickupInterceptClient then
		return true
	end

	HarvestableSoil.server_onRemoved = RfsSoilPlacement._harvestableRemovedHook
	HarvestableSoil.client_canInteract = RfsSoilPlacement._harvestableCanInteractHook
	HarvestableSoil.client_onInteract = RfsSoilPlacement._harvestableInteractHook
	HarvestableSoil._rfsPickupInterceptClient = true
	if not RfsSoilPlacement._harvestableHookLoggedClient then
		RfsSoilPlacement._harvestableHookLoggedClient = true
		print( "[RFS] RfsSoilPlacement hooked HarvestableSoil (RMB block: client_onInteract + server_onRemoved + canInteract)" )
	end
	return true
end

function RfsSoilPlacement.ensureHooks()
	RfsSoilPlacement.ensureHarvestableSoilHooks()
	RfsSoilPlacement.ensureCarryToolHooks()
	RfsSoilPlacement.ensurePlayerHandPickupHooks()
	if type( SoilBag ) ~= "table" then
		pcall( function()
			dofile( "$SURVIVAL_DATA/Scripts/game/tools/SoilBag.lua" )
		end )
	end
	if type( SoilBag ) ~= "table" then
		return false
	end

	-- Once per VM: Survival may replace the SoilBag class table; re-apply silently.
	if RfsSoilPlacement._soilBagHookedOnce
		and SoilBag._rfsSoilPlacementHooked
		and SoilBag.client_onEquippedUpdate == RfsSoilPlacement.client_onEquippedUpdate then
		return true
	end

	if not RfsSoilPlacement._origConstructionRayCast then
		RfsSoilPlacement._origConstructionRayCast = SoilBag.constructionRayCast
	end
	if not RfsSoilPlacement._origEquippedUpdate then
		RfsSoilPlacement._origEquippedUpdate = SoilBag.client_onEquippedUpdate
	end
	if not RfsSoilPlacement._origSvPutSoil then
		RfsSoilPlacement._origSvPutSoil = SoilBag.sv_n_putSoil
	end

	-- Never call _origEquippedUpdate — vanilla start-only place causes double tiles.
	SoilBag.constructionRayCast = RfsSoilPlacement.constructionRayCast
	SoilBag.client_onEquippedUpdate = RfsSoilPlacement.client_onEquippedUpdate
	SoilBag.sv_n_putSoil = RfsSoilPlacement.sv_n_putSoil
	SoilBag.sv_n_pickupSoilBatch = RfsSoilPlacement.sv_n_pickupSoilBatch
	SoilBag.sv_n_soilPickupBlock = RfsSoilPlacement.sv_n_soilPickupBlock
	SoilBag.cl_n_pickupInventoryFull = RfsSoilPlacement.cl_n_pickupInventoryFull
	SoilBag._rfsSoilPlacementHooked = true
	local first = not RfsSoilPlacement._soilBagHookedOnce
	RfsSoilPlacement._soilBagHookedOnce = true
	if first then
		print( "[RFS] RfsSoilPlacement hooked SoilBag (vanilla 3x3 subdiv snap, gridPos drag, pickup batch, fixed rot)" )
	end
	return true
end

if not RfsSoilPlacement._harvestableBootOnly then
	pcall( function()
		RfsSoilPlacement.ensureHooks()
	end )
	print( "[RFS] RfsSoilPlacement loaded (frozen soil drag batch place + pickup + terrain follow)" )
end
