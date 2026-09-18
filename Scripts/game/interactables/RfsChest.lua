-- RfsChest.lua — hijacked Large Chest (plain + vacuum craft UUIDs).
-- E = open inventory. U = filter menu (upgrade-panel art).
-- Logic-powered: vacuum ground loot into this network; route / sort by filters.
-- Empty filter list = accept all. Non-empty = allowlist (setFilters + Lua checks).

dofile( "$SURVIVAL_DATA/Scripts/game/survival_harvestable.lua" )
pcall( function()
	dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
end )

RfsChest = class( nil )
RfsChest.maxParentCount = 1
RfsChest.maxChildCount = 0
RfsChest.poseWeightCount = 1
RfsChest.connectionInput = sm.interactable.connectionType.logic
RfsChest.colorNormal = sm.color.new( 0xdf7f01ff )
RfsChest.colorHighlight = sm.color.new( 0xffa020ff )

local AreaTriggerSize = 6
local SORT_EVERY = 20
local NIL_UUID = "00000000-0000-0000-0000-000000000000"

local function uuidStr( u )
	if u == nil then
		return nil
	end
	return string.lower( tostring( u ) )
end

local function isNilUuid( u )
	local s = uuidStr( u )
	return ( not s ) or s == "" or s == NIL_UUID
end

local function normalizeFilterList( list )
	local out = {}
	local seen = {}
	if type( list ) ~= "table" then
		return out
	end
	for _, v in ipairs( list ) do
		local id = uuidStr( type( v ) == "table" and ( v.uuid or v.itemId or v.id ) or v )
		if id and not isNilUuid( id ) and not seen[id] then
			seen[id] = true
			out[#out + 1] = id
		end
	end
	table.sort( out )
	-- Cap at 7 — matches Active0-6 UI strip and world icon row.
	while #out > 7 do
		table.remove( out )
	end
	return out
end

local function filtersToUuids( list )
	local out = {}
	for _, id in ipairs( list or {} ) do
		local ok, u = pcall( sm.uuid.new, id )
		if ok and u then
			out[#out + 1] = u
		end
	end
	return out
end

local function getContainer( self )
	local container = nil
	pcall( function()
		container = self.shape.interactable:getContainer( 0 )
	end )
	if not container then
		pcall( function()
			container = self.interactable:getContainer( 0 )
		end )
	end
	return container
end

local function ensureContainer( self )
	local slots = 30
	pcall( function()
		slots = tonumber( self.data and self.data.slots ) or 30
	end )
	local container = getContainer( self )
	if not container then
		pcall( function()
			container = self.shape:getInteractable():addContainer( 0, slots )
		end )
	end
	return container
end

local function applyEngineFilters( self )
	local container = ensureContainer( self )
	if not container or not container.setFilters then
		return
	end
	local list = normalizeFilterList( self.sv and self.sv.filters )
	if #list == 0 then
		-- Empty allowlist: try clear so the chest accepts everything again.
		pcall( function()
			container:setFilters( {} )
		end )
		return
	end
	pcall( function()
		container:setFilters( filtersToUuids( list ) )
	end )
end

local function saveFilters( self )
	if not self.storage then
		return
	end
	pcall( function()
		self.storage:save( {
			filters = normalizeFilterList( self.sv and self.sv.filters ),
		} )
	end )
end

local function loadFilters( self )
	local saved = nil
	pcall( function()
		saved = self.storage and self.storage:load()
	end )
	self.sv = self.sv or {}
	if type( saved ) == "table" then
		self.sv.filters = normalizeFilterList( saved.filters )
	else
		self.sv.filters = {}
	end
end

local function acceptsUuid( filters, itemUuid )
	local list = normalizeFilterList( filters )
	if #list == 0 then
		return true
	end
	local id = uuidStr( itemUuid )
	if not id then
		return false
	end
	for _, f in ipairs( list ) do
		if f == id then
			return true
		end
	end
	return false
end

local function canCollectInto( container, itemUuid, qty )
	if not container or not sm.exists( container ) then
		return false
	end
	qty = math.max( 1, math.floor( tonumber( qty ) or 1 ) )
	local ok = false
	if sm.container.canCollect then
		local result = nil
		pcall( function()
			result = sm.container.canCollect( container, itemUuid, qty )
		end )
		if result == true or result == 1 or result == qty then
			ok = true
		end
	else
		ok = true
	end
	return ok
end

local CHEST_UUIDS = {
	["ad35f7e6-af8f-40fa-aef4-77d827ac8a8a"] = true,
	["e9efc008-8fae-4391-9ad1-6a62dbab5760"] = true,
	["fcfae5e2-1df9-47d8-bb9a-30bec9b5b1f5"] = true,
	["7527cf2e-1705-4214-9d07-3dc374957e25"] = true,
	["9601f2ca-9552-48b0-afc1-b0f200461114"] = true,
}

local function isChestLike( shape )
	if not shape or not sm.exists( shape ) then
		return false
	end
	local pub = nil
	pcall( function()
		local ia = shape:getInteractable()
		if ia then
			pub = ia:getPublicData()
		end
	end )
	if type( pub ) == "table" and pub.rfsChest == true then
		return true
	end
	local uid = nil
	pcall( function()
		uid = shape.uuid or shape:getShapeUuid()
	end )
	return uid and CHEST_UUIDS[uuidStr( uid )] == true
end

local function containerOfShape( shape )
	if not shape or not sm.exists( shape ) then
		return nil
	end
	local container = nil
	pcall( function()
		local ia = shape:getInteractable()
		if ia then
			container = ia:getContainer( 0 ) or ia:getContainer()
		end
	end )
	return container
end

local function scriptOfShape( shape )
	if not shape or not sm.exists( shape ) then
		return nil
	end
	local ia = nil
	pcall( function()
		ia = shape:getInteractable()
	end )
	if not ia then
		return nil
	end
	-- Prefer publicData set by RfsChest instances.
	local pub = nil
	pcall( function()
		pub = ia:getPublicData()
	end )
	if type( pub ) == "table" and pub.rfsChest == true then
		return pub
	end
	return nil
end

local function filtersOfShape( shape )
	local pub = scriptOfShape( shape )
	if type( pub ) == "table" then
		return normalizeFilterList( pub.filters )
	end
	return {}
end

local function gatherNetworkShapes( self )
	local shapes = {}
	local seen = {}
	local function add( shape )
		if not shape or not sm.exists( shape ) then
			return
		end
		local id = nil
		pcall( function()
			id = shape.id or tostring( shape )
		end )
		id = tostring( id or shape )
		if seen[id] then
			return
		end
		if not isChestLike( shape ) then
			return
		end
		if not containerOfShape( shape ) then
			return
		end
		seen[id] = true
		shapes[#shapes + 1] = shape
	end

	add( self.shape )

	pcall( function()
		for _, s in ipairs( sm.pipeGraph.getInputContainers( self.shape ) or {} ) do
			add( s )
		end
	end )
	pcall( function()
		for _, s in ipairs( sm.pipeGraph.getOutputContainers( self.shape ) or {} ) do
			add( s )
		end
	end )
	pcall( function()
		for _, s in ipairs( sm.pipeGraph.getMatchingPipedContainers( self.interactable ) or {} ) do
			add( s )
		end
	end )
	pcall( function()
		local q = { self.shape }
		local qi = 1
		local visited = {}
		while qi <= #q do
			local cur = q[qi]
			qi = qi + 1
			local cid = tostring( cur.id or cur )
			if not visited[cid] then
				visited[cid] = true
				add( cur )
				local neigh = nil
				pcall( function()
					neigh = cur:getPipedNeighbours()
				end )
				if type( neigh ) == "table" then
					for _, n in ipairs( neigh ) do
						q[#q + 1] = n
					end
				end
			end
		end
	end )
	-- Welded body fallback: only other Large/known chests on the same creation.
	pcall( function()
		local body = self.shape:getBody()
		if body then
			for _, s in ipairs( body:getShapes() or {} ) do
				add( s )
			end
		end
	end )

	return shapes
end

local function scoreDestination( shape, itemUuid, preferShape )
	local filters = filtersOfShape( shape )
	local filtered = #filters > 0
	if not acceptsUuid( filters, itemUuid ) then
		return nil
	end
	local container = containerOfShape( shape )
	if not canCollectInto( container, itemUuid, 1 ) then
		return nil
	end
	local score = 0
	if filtered then
		score = score + 100
	end
	if preferShape and shape == preferShape then
		score = score + 10
	end
	return score
end

local function findDestination( self, itemUuid, qty )
	local bestShape = nil
	local bestScore = -1
	for _, shape in ipairs( gatherNetworkShapes( self ) ) do
		local score = scoreDestination( shape, itemUuid, self.shape )
		if score and score > bestScore then
			local container = containerOfShape( shape )
			if canCollectInto( container, itemUuid, qty ) then
				bestScore = score
				bestShape = shape
			end
		end
	end
	if not bestShape then
		return nil, nil
	end
	return bestShape, containerOfShape( bestShape )
end

local function tryCollect( container, itemUuid, qty )
	if not container then
		return false
	end
	qty = math.max( 1, math.floor( tonumber( qty ) or 1 ) )
	sm.container.beginTransaction()
	sm.container.collect( container, itemUuid, qty, true )
	return sm.container.endTransaction() == true
end

local function tryMoveStack( fromContainer, toContainer, itemUuid, qty )
	if not fromContainer or not toContainer or fromContainer == toContainer then
		return 0
	end
	qty = math.max( 1, math.floor( tonumber( qty ) or 1 ) )
	if not canCollectInto( toContainer, itemUuid, qty ) then
		-- Try smaller chunks.
		local moved = 0
		for _ = 1, qty do
			if not canCollectInto( toContainer, itemUuid, 1 ) then
				break
			end
			sm.container.beginTransaction()
			local spent = sm.container.spend( fromContainer, itemUuid, 1, false ) or 0
			if spent < 1 then
				sm.container.abortTransaction()
				break
			end
			sm.container.collect( toContainer, itemUuid, 1, true )
			if sm.container.endTransaction() then
				moved = moved + 1
			else
				break
			end
		end
		return moved
	end
	sm.container.beginTransaction()
	local spent = sm.container.spend( fromContainer, itemUuid, qty, false ) or 0
	if spent < 1 then
		sm.container.abortTransaction()
		return 0
	end
	sm.container.collect( toContainer, itemUuid, spent, true )
	if sm.container.endTransaction() then
		return spent
	end
	return 0
end

local function syncPublic( self )
	pcall( function()
		self.interactable:setPublicData( {
			rfsChest = true,
			filters = normalizeFilterList( self.sv and self.sv.filters ),
		} )
	end )
end

local function ensureTrigger( self, on )
	if on then
		if self.sv.areaTrigger == nil then
			local size = sm.vec3.new( AreaTriggerSize, AreaTriggerSize, AreaTriggerSize )
			local filter = sm.areaTrigger.filter.harvestable
			self.sv.areaTrigger = sm.areaTrigger.createAttachedBox(
				self.interactable, size, sm.vec3.zero(), sm.quat.identity(), filter
			)
		end
	else
		if self.sv.areaTrigger then
			pcall( function()
				self.sv.areaTrigger:destroy()
			end )
			self.sv.areaTrigger = nil
		end
	end
end

local function vacuumTick( self )
	local parent = self.interactable:getSingleParent()
	local powered = parent and parent:isActive()
	ensureTrigger( self, powered == true )
	if not powered or not self.sv.areaTrigger then
		return
	end

	local areaContent = self.sv.areaTrigger:getContents()
	local looted = {}
	for _, result in ipairs( areaContent or {} ) do
		if sm.exists( result ) then
			local okUuid = false
			pcall( function()
				okUuid = result:getUuid() == hvs_loot
			end )
			if okUuid then
				local pubData = result.publicData
				if pubData and not pubData.harvested and pubData.uuid then
					local qty = math.max( 1, math.floor( tonumber( pubData.quantity ) or 1 ) )
					local destShape, destContainer = findDestination( self, pubData.uuid, qty )
					if destContainer and tryCollect( destContainer, pubData.uuid, qty ) then
						pubData.harvested = true
						looted[#looted + 1] = {
							uuid = pubData.uuid,
							pos = result:getPosition(),
						}
						pcall( function()
							result:destroy()
						end )
					end
				end
			end
		end
	end
	if #looted > 0 then
		self.network:sendToClients( "cl_n_looted", looted )
	end
end

local function sortTick( self )
	local parent = self.interactable:getSingleParent()
	if not ( parent and parent:isActive() ) then
		return
	end
	self.sv.sortTick = ( self.sv.sortTick or 0 ) + 1
	if ( self.sv.sortTick % SORT_EVERY ) ~= 0 then
		return
	end

	local network = gatherNetworkShapes( self )
	for _, shape in ipairs( network ) do
		local fromFilters = filtersOfShape( shape )
		local fromContainer = containerOfShape( shape )
		if fromContainer and sm.exists( fromContainer ) then
			local size = 0
			pcall( function()
				size = fromContainer:getSize() or 0
			end )
			for i = 0, math.max( 0, size - 1 ) do
				local item = nil
				pcall( function()
					item = fromContainer:getItem( i )
				end )
				if type( item ) == "table" and item.uuid and not isNilUuid( item.uuid ) then
					local qty = math.max( 1, math.floor( tonumber( item.quantity ) or 1 ) )
					local wantsStay = acceptsUuid( fromFilters, item.uuid )
					local filteredHere = #fromFilters > 0
					-- Move from unfiltered (or mismatched) toward a filtered match.
					local shouldMove = ( not filteredHere ) or ( not wantsStay )
					if shouldMove then
						local bestShape = nil
						local bestScore = -1
						for _, dest in ipairs( network ) do
							if dest ~= shape then
								local destFilters = filtersOfShape( dest )
								if #destFilters > 0 and acceptsUuid( destFilters, item.uuid ) then
									local score = scoreDestination( dest, item.uuid, nil ) or -1
									if score > bestScore then
										bestScore = score
										bestShape = dest
									end
								end
							end
						end
						if bestShape then
							tryMoveStack( fromContainer, containerOfShape( bestShape ), item.uuid, qty )
						end
					end
				end
			end
		end
	end
end

function RfsChest.server_onCreate( self )
	self.sv = self.sv or {}
	loadFilters( self )
	ensureContainer( self )
	applyEngineFilters( self )
	syncPublic( self )
	self.sv.playersLookingInChest = {}
end

function RfsChest.server_onDestroy( self )
	ensureTrigger( self, false )
end

function RfsChest.server_onFixedUpdate( self )
	vacuumTick( self )
	sortTick( self )
end

function RfsChest.sv_n_open( self, _, player )
	self.sv.playersLookingInChest = self.sv.playersLookingInChest or {}
	self.sv.playersLookingInChest[#self.sv.playersLookingInChest + 1] = player
	self.network:setClientData( #self.sv.playersLookingInChest > 0 )
end

function RfsChest.sv_n_close( self, _, player )
	for i = #( self.sv.playersLookingInChest or {} ), 1, -1 do
		local p = self.sv.playersLookingInChest[i]
		if p == player or not p or not p:isActive() then
			table.remove( self.sv.playersLookingInChest, i )
		end
	end
	self.network:setClientData( #( self.sv.playersLookingInChest or {} ) > 0 )
end

function RfsChest.sv_n_getFilters( self, _, player )
	self.network:sendToClient( player, "cl_n_filters", {
		filters = normalizeFilterList( self.sv.filters ),
	} )
end

function RfsChest.sv_n_setFilters( self, params, player )
	if type( params ) ~= "table" then
		return
	end
	self.sv.filters = normalizeFilterList( params.filters )
	applyEngineFilters( self )
	saveFilters( self )
	syncPublic( self )
	-- All clients need filters for the world icon row.
	self.network:sendToClients( "cl_n_filters", {
		filters = normalizeFilterList( self.sv.filters ),
	} )
end

function RfsChest.client_onCreate( self )
	self.cl = self.cl or {}
	self.cl.weight = 0
	self.cl.filters = {}
	-- Pull persisted filters so world icons appear without opening U-menu.
	pcall( function()
		self.network:sendToServer( "sv_n_getFilters", {} )
	end )
end

function RfsChest.client_onClientDataUpdate( self, isOpen )
	self.cl = self.cl or {}
	self.cl.isOpen = isOpen
end

function RfsChest.client_onDestroy( self )
	local gui = self.cl and self.cl.gui
	if gui then
		pcall( function()
			if gui:isActive() then
				gui:close()
			end
		end )
	end
	if self.cl then
		self.cl.gui = nil
	end
	if type( RfsChestFilterGui ) == "table" and RfsChestFilterGui.close then
		pcall( RfsChestFilterGui.close, self )
	end
	if type( RfsChestFilterWorld ) == "table" and RfsChestFilterWorld.destroy then
		pcall( RfsChestFilterWorld.destroy, self )
	end
end

function RfsChest.client_canInteract( self, character )
	sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "Open" )
	local n = #( self.cl and self.cl.filters or {} )
	local tip = ( n > 0 ) and ( "Filters (" .. tostring( n ) .. ")" ) or "Set Filters"
	sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Tinker", true ), tip )
	return true
end

function RfsChest.client_canTinker( self, character )
	return true
end

function RfsChest.client_onInteract( self, character, state )
	if state ~= true then
		return
	end
	local container = getContainer( self )
	if not container then
		return
	end
	local gui = sm.gui.createContainerGui( true )
	gui:setContainer( "UpperGrid", container )
	gui:setText( "LowerName", "#{INVENTORY_TITLE}" )
	gui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
	gui:setOnCloseCallback( "cl_e_onClose" )
	gui:open()
	self.cl.gui = gui
	self.network:sendToServer( "sv_n_open", true )
end

function RfsChest.cl_e_onClose( self )
	self.cl.gui = nil
	self.network:sendToServer( "sv_n_close" )
end

function RfsChest.client_onTinker( self, character, state )
	if state ~= true then
		return
	end
	if type( RfsChestFilterGui ) ~= "table" then
		pcall( function()
			dofile( "$CONTENT_DATA/Scripts/game/RfsChestFilterGui.lua" )
		end )
	end
	if type( RfsChestFilterGui ) == "table" and RfsChestFilterGui.open then
		RfsChestFilterGui.open( self )
	end
end

function RfsChest.client_canCarry( self )
	local container = getContainer( self )
	if container and sm.exists( container ) then
		local empty = true
		pcall( function()
			empty = container:isEmpty()
		end )
		return not empty
	end
	return false
end

function RfsChest.client_onRefresh( self )
	self.cl = self.cl or {}
	self.cl.effect = nil
end

function RfsChest.cl_n_filters( self, data )
	self.cl = self.cl or {}
	self.cl.filters = normalizeFilterList( data and data.filters )
	self.cl.filterWorldSig = nil
	if type( RfsChestFilterGui ) == "table" and RfsChestFilterGui.onFilters then
		RfsChestFilterGui.onFilters( self, self.cl.filters )
	end
	if type( RfsChestFilterWorld ) == "table" and RfsChestFilterWorld.update then
		pcall( RfsChestFilterWorld.update, self )
	end
end

function RfsChest.cl_n_looted( self, looted )
	self.cl = self.cl or {}
	self.cl.lootTrails = self.cl.lootTrails or {}
	for _, item in ipairs( looted or {} ) do
		local color = sm.color.new( 1, 1, 1 )
		pcall( function()
			color = sm.shape.getShapeTypeColor( item.uuid )
		end )
		pcall( function()
			sm.effect.playEffect(
				"LootProjectile - Hit",
				item.pos,
				sm.vec3.zero(),
				sm.quat.identity(),
				sm.vec3.one(),
				{ ["Color"] = color }
			)
		end )
		self.cl.lootTrails[#self.cl.lootTrails + 1] = {
			pos = item.pos + sm.vec3.new( 0, 0, 0.375 ),
			time = 0.25,
			color = color,
		}
	end
end

function RfsChest.client_onUpdate( self, dt )
	self.cl = self.cl or {}
	local isOpen = self.cl.isOpen
	if self.cl.lootTrails then
		for i = #self.cl.lootTrails, 1, -1 do
			local trail = self.cl.lootTrails[i]
			trail.time = trail.time - dt
			if trail.time <= 0 then
				if trail.effect then
					pcall( function()
						trail.effect:stopImmediate()
					end )
				end
				table.remove( self.cl.lootTrails, i )
			else
				if type( magicPositionInterpolation ) == "function" then
					trail.pos = magicPositionInterpolation( trail.pos, self.shape:getWorldPosition(), dt )
				else
					trail.pos = trail.pos + ( self.shape:getWorldPosition() - trail.pos ) * math.min( 1, dt * 8 )
				end
				if trail.effect == nil then
					pcall( function()
						trail.effect = sm.effect.createEffect( "LootProjectile - Attached" )
						trail.effect:start()
					end )
				end
				if trail.effect then
					pcall( function()
						trail.effect:setPosition( trail.pos )
					end )
				end
				isOpen = true
			end
		end
	end

	local weight = self.cl.weight or 0
	if isOpen then
		weight = math.min( weight + dt * 10.0, 1.0 )
	else
		weight = math.max( weight - dt * 10.0, 0.0 )
	end
	self.cl.weight = weight

	local parent = self.interactable:getSingleParent()
	if parent and parent:isActive() then
		if self.cl.effect == nil then
			pcall( function()
				self.cl.effect = sm.effect.createEffect( "Interactive - ChestLootsuction_active", self.shape )
				self.cl.effect:setOffsetPosition( sm.vec3.new( 0, -0.75, 0 ) )
				self.cl.effect:setOffsetRotation( sm.quat.rotNegX90() )
				self.cl.effect:start()
			end )
		end
		self.cl.time = ( self.cl.time or 0 ) + dt
		if self.cl.time > 1 and self.cl.effect then
			self.cl.time = self.cl.time % 1
			pcall( function()
				self.cl.effect:start()
			end )
		end
		weight = math.max( weight, 0.4 )
	else
		if self.cl.effect then
			pcall( function()
				self.cl.effect:stopImmediate()
			end )
			self.cl.effect = nil
		end
		self.cl.time = nil
	end

	pcall( function()
		self.shape.interactable:setPoseWeight( 0, weight )
	end )

	if type( RfsChestFilterWorld ) == "table" and RfsChestFilterWorld.update then
		pcall( RfsChestFilterWorld.update, self )
	end
end

-- Forward filter GUI button callbacks onto the active chest host.
local function filterFwd( name, ... )
	if type( RfsChestFilterGui ) == "table" and RfsChestFilterGui[name] then
		RfsChestFilterGui[name]( ... )
	end
end

function RfsChest.cl_rfs_chestFilterClose( self )
	_G.g_rfsChestFilterHost = self
	filterFwd( "closeActive" )
end
function RfsChest.cl_rfs_chestFilterClosed( self )
	_G.g_rfsChestFilterHost = self
	filterFwd( "closeActive" )
end
function RfsChest.cl_rfs_chestFilterClear( self )
	_G.g_rfsChestFilterHost = self
	filterFwd( "clearAll" )
end
function RfsChest.cl_rfs_chestFilterScroll( self, ... )
	_G.g_rfsChestFilterHost = self
	filterFwd( "scroll", ... )
end
function RfsChest.cl_rfs_chestFilterWheel( self, ... )
	_G.g_rfsChestFilterHost = self
	filterFwd( "wheel", ... )
end
function RfsChest.cl_rfs_chestFilterPick( self, buttonName )
	_G.g_rfsChestFilterHost = self
	filterFwd( "pick", buttonName )
end
function RfsChest.cl_rfs_chestFilterActive( self, buttonName )
	_G.g_rfsChestFilterHost = self
	filterFwd( "pickActive", buttonName )
end
function RfsChest.cl_rfs_chestFilterSearch( self, ... )
	_G.g_rfsChestFilterHost = self
	filterFwd( "search", ... )
end
function RfsChest.cl_rfs_chestFilterCatAll( self )
	_G.g_rfsChestFilterHost = self
	filterFwd( "catAll" )
end
function RfsChest.cl_rfs_chestFilterCatTool( self )
	_G.g_rfsChestFilterHost = self
	filterFwd( "catTool" )
end
function RfsChest.cl_rfs_chestFilterCatBlock( self )
	_G.g_rfsChestFilterHost = self
	filterFwd( "catBlock" )
end
function RfsChest.cl_rfs_chestFilterCatInteractive( self )
	_G.g_rfsChestFilterHost = self
	filterFwd( "catInteractive" )
end
function RfsChest.cl_rfs_chestFilterCatPart( self )
	_G.g_rfsChestFilterHost = self
	filterFwd( "catPart" )
end
function RfsChest.cl_rfs_chestFilterCatConsumable( self )
	_G.g_rfsChestFilterHost = self
	filterFwd( "catConsumable" )
end

print( "[RFS] RfsChest loaded (filterable Large Chest)" )
