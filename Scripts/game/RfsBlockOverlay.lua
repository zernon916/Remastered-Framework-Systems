-- RfsBlockOverlay.lua — best-effort creation / look-at health overlay.
-- Scrap Mechanic custom games do not expose per-block HP. This scans nearby
-- bodies and the crosshair shape, then draws HUD + world text + a hover
-- highlight so the overlay is actually visible. Mass/shape-count is a proxy,
-- not engine durability.

RfsBlockOverlay = RfsBlockOverlay or {}

local SCAN_RANGE = 18
local LOOK_RANGE = 12
local MAX_LABELS = 6
local SCAN_EVERY = 8
local FX_NAMES = { "RfsBlockText", "RfsGrowText", "RfsHackText" }
local MAP_LOCK = "9a1528a6-acd2-44db-8050-b2f493362191"

local pool = { look = nil, near = {} }

-- Default OFF (grass/terrain spam during HACK testing). /menu toggle still works.
-- Overlay look-at-on-harvestables is a known bug — refine later, do not "fix" here.
local function overlayOn()
	if type( RfsGuiPrefs ) == "table" and RfsGuiPrefs.client then
		local p = RfsGuiPrefs.client()
		if p and p.blockOverlay == true then
			return true
		end
	end
	return false
end

local function destroyFx( fx )
	if not fx then
		return
	end
	pcall( function()
		if sm.exists( fx ) then
			fx:stop()
			fx:destroy()
		end
	end )
end

local function makeFx()
	for _, name in ipairs( FX_NAMES ) do
		local ok, created = pcall( sm.effect.createEffect, name )
		if ok and created then
			pcall( function()
				created:setParameter( "anchor", "CENTER" )
				created:start()
			end )
			return created
		end
	end
	return nil
end

local function ensureFx( slot )
	local fx = slot
	local alive = false
	pcall( function()
		alive = fx and sm.exists( fx )
	end )
	if alive then
		return fx
	end
	return makeFx()
end

local function hideFx( fx )
	if not fx then
		return
	end
	pcall( function()
		if sm.exists( fx ) then
			fx:setParameter( "TextContent", "" )
			if fx:isPlaying() then
				fx:stop()
			end
		end
	end )
end

local function showFx( fx, pos, text, color )
	if not fx or not pos then
		return
	end
	pcall( function()
		fx:setParameter( "TextContent", text )
		fx:setParameter( "Color", color )
		fx:setPosition( pos )
		if not fx:isPlaying() then
			fx:start()
		end
	end )
end

local function skipShape( shape )
	if not shape or not sm.exists( shape ) then
		return true
	end
	local skip = false
	pcall( function()
		skip = string.lower( tostring( shape:getShapeUuid() ) ) == MAP_LOCK
	end )
	return skip
end

local function creationStats( body )
	if not body or not sm.exists( body ) then
		return nil
	end
	local bodies = { body }
	pcall( function()
		bodies = body:getCreationBodies() or bodies
	end )
	local shapes = 0
	local mass = 0
	local pos = sm.vec3.new( 0, 0, 0 )
	local n = 0
	local dynamic = false
	local id = nil
	for _, b in ipairs( bodies ) do
		if b and sm.exists( b ) then
			n = n + 1
			pcall( function()
				mass = mass + ( b:getMass() or 0 )
				if b:isDynamic() then
					dynamic = true
				end
				pos = pos + b.worldPosition
				if not id then
					id = b.id
				end
				local sh = b:getShapes()
				if type( sh ) == "table" then
					shapes = shapes + #sh
				end
			end )
		end
	end
	if n <= 0 then
		return nil
	end
	return {
		id = id,
		shapes = shapes,
		mass = mass,
		pos = pos * ( 1 / n ) + sm.vec3.new( 0, 0, 1.1 ),
		dynamic = dynamic,
		bodies = n,
	}
end

local function proxyColor( stats )
	if not stats then
		return sm.color.new( 0.85, 0.85, 0.85, 1.0 )
	end
	if stats.dynamic then
		return sm.color.new( 1.00, 0.50, 0.12, 1.0 )
	end
	if ( stats.shapes or 0 ) <= 4 then
		return sm.color.new( 1.00, 0.88, 0.18, 1.0 )
	end
	return sm.color.new( 0.28, 0.92, 0.38, 1.0 )
end

local function proxyLabel( stats, prefix )
	if not stats then
		return prefix or ""
	end
	local kind = stats.dynamic and "move" or "static"
	return string.format( "%s%d shp · %d kg · %s",
		prefix or "", stats.shapes or 0, math.floor( ( stats.mass or 0 ) + 0.5 ), kind )
end

local function lookKind( shape )
	local kind = "Part"
	pcall( function()
		local uuid = shape:getShapeUuid()
		if sm.item.isBlock( uuid ) then
			kind = "Block"
		end
	end )
	return kind
end

local function clearAll()
	hideFx( pool.look )
	for i = 1, MAX_LABELS do
		hideFx( pool.near[i] )
	end
end

function RfsBlockOverlay.destroy()
	destroyFx( pool.look )
	pool.look = nil
	for i = 1, MAX_LABELS do
		destroyFx( pool.near[i] )
		pool.near[i] = nil
	end
end

function RfsBlockOverlay.update( host )
	host.cl = host.cl or {}
	if not overlayOn() then
		host.cl.rfsBlockHud = nil
		clearAll()
		return
	end

	local player = host.player
	if not player or player ~= sm.localPlayer.getPlayer() then
		return
	end
	local character = player.character
	if not character or not sm.exists( character ) then
		host.cl.rfsBlockHud = nil
		clearAll()
		return
	end

	local origin = character.worldPosition
	local hud = "Look: —  (no per-block HP API; creation mass / shape count)"
	local lookStats = nil
	local lookShape = nil
	local hitPos = nil

	pcall( function()
		local hit, result = sm.localPlayer.getRaycast( LOOK_RANGE )
		if not hit or not result then
			return
		end
		if result.type == "body" then
			lookShape = result:getShape()
			if skipShape( lookShape ) then
				lookShape = nil
				return
			end
			hitPos = result.pointWorld
			local body = lookShape:getBody()
			lookStats = creationStats( body )
			hud = string.format( "Look: %s  |  %s", lookKind( lookShape ), proxyLabel( lookStats ) )
		elseif result.type == "harvestable" then
			hud = "Look: harvestable  (plants use Growth Time overlay)"
		elseif result.type == "character" then
			hud = "Look: unit  (HP bars are overhead)"
		elseif result.type == "terrainSurface" or result.type == "voxelTerrain" then
			hud = "Look: terrain"
		end
	end )

	host.cl.rfsBlockHud = hud

	pool.look = ensureFx( pool.look )
	if lookStats and lookStats.pos then
		showFx( pool.look, lookStats.pos + sm.vec3.new( 0, 0, 0.35 ),
			proxyLabel( lookStats, "HP~ " ), proxyColor( lookStats ) )
		pcall( function()
			if lookShape and hitPos then
				local gridPos = nil
				pcall( function()
					if lookShape.getClosestBlockLocalPosition then
						gridPos = lookShape:getClosestBlockLocalPosition( hitPos )
					end
				end )
				if gridPos then
					sm.visualization.setBlockVisualization( gridPos, lookStats.dynamic, lookShape )
				end
			end
		end )
	else
		hideFx( pool.look )
	end

	local tick = sm.game.getCurrentTick()
	if ( tick % SCAN_EVERY ) ~= 0 and host.cl.rfsBlockNear then
		local cached = host.cl.rfsBlockNear
		for i = 1, MAX_LABELS do
			pool.near[i] = ensureFx( pool.near[i] )
			local row = cached[i]
			if row then
				showFx( pool.near[i], row.pos, row.text, row.color )
			else
				hideFx( pool.near[i] )
			end
		end
		return
	end

	local nearby = {}
	pcall( function()
		local bodies = sm.body.getAllBodies()
		if type( bodies ) ~= "table" then
			return
		end
		local seen = {}
		for _, body in ipairs( bodies ) do
			if body and sm.exists( body ) then
				local st = creationStats( body )
				if st and st.id and not seen[st.id] then
					seen[st.id] = true
					local d2 = ( st.pos - origin ):length2()
					if d2 <= ( SCAN_RANGE * SCAN_RANGE ) then
						if lookStats and lookStats.id == st.id then
							-- look-at label already covers this creation
						else
							nearby[#nearby + 1] = { dist2 = d2, stats = st }
						end
					end
				end
			end
			if #nearby >= 24 then
				break
			end
		end
		table.sort( nearby, function( a, b ) return a.dist2 < b.dist2 end )
	end )

	local cached = {}
	for i = 1, MAX_LABELS do
		pool.near[i] = ensureFx( pool.near[i] )
		local row = nearby[i]
		if row and row.stats then
			cached[i] = {
				pos = row.stats.pos,
				text = proxyLabel( row.stats ),
				color = proxyColor( row.stats ),
			}
			showFx( pool.near[i], cached[i].pos, cached[i].text, cached[i].color )
		else
			hideFx( pool.near[i] )
		end
	end
	host.cl.rfsBlockNear = cached
end

print( "[RFS] RfsBlockOverlay loaded (creation mass/shape-count proxy)" )
