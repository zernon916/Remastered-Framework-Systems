-- RfsHackRange.lua
-- OWNER: SHOW RANGE / RfsRangeViz (Game-hosted, no interactable host).
-- VOLATILE: ring look. MUST NOT add electrical load (no ShapeRenderable / blk_lights on the beacon).
-- Beacon client only tears down leftovers. Game.lua ticks RfsRangeViz.

RfsHackRange = RfsHackRange or {}
rfsHackRange = RfsHackRange

local WORLD_UP = sm.vec3.new( 0, 0, 1 )
local RING_FX = "RfsRangeLine"
local RING_MESH_M = 1.0
local RING_HOVER = 0.375 -- 1.5 blocks above ground
local RING_THICK = 0.10
local RING_HUB = 0.45
local RING_CHORD = 2.0
local RING_SEG_MIN = 32
local RING_SEG_MAX = 64
local RING_RADIALS = 4
local RING_DEFAULT_COLOR = sm.color.new( 0.95, 0.35, 0.12, 1.0 )

local function cl_destroyRangeFxList( list )
	if type( list ) ~= "table" then
		return
	end
	for _, fx in ipairs( list ) do
		pcall( function()
			if fx and sm.exists( fx ) then
				fx:stop()
				fx:destroy()
			end
		end )
	end
end

function RfsHackRange.tearDownBeacon( self )
	if not self or not self.cl then
		return
	end
	if self.cl.rangeRing then
		local ring = self.cl.rangeRing
		if type( ring ) == "table" and ring.segs then
			cl_destroyRangeFxList( ring.segs )
			cl_destroyRangeFxList( ring.radials )
		else
			cl_destroyRangeFxList( ring )
		end
		self.cl.rangeRing = nil
	end
	self.cl.ringRange = nil
	self.cl.ringSegN = nil
end

local function vizGroundZ( x, y, fallbackZ )
	local hit, result
	local ok = pcall( function()
		hit, result = sm.physics.raycast(
			sm.vec3.new( x, y, fallbackZ + 24 ),
			sm.vec3.new( x, y, fallbackZ - 80 )
		)
	end )
	if ok and hit and result and result.pointWorld then
		return result.pointWorld.z
	end
	return fallbackZ
end

local function vizQuatAlignZ( dir )
	if not dir or dir:length2() < 1e-12 then
		return sm.quat.identity()
	end
	dir = dir:normalize()
	local d = WORLD_UP:dot( dir )
	if d > 0.9995 then
		return sm.quat.identity()
	end
	if d < -0.9995 then
		return sm.quat.angleAxis( math.pi, sm.vec3.new( 1, 0, 0 ) )
	end
	local ok, q = pcall( sm.vec3.getRotation, WORLD_UP, dir )
	if ok and q then
		return q
	end
	return sm.quat.identity()
end

local function vizApplyLine( fx, from, to, color, world )
	if not fx then
		return
	end
	local delta = to - from
	local length = delta:length()
	if length < 0.05 then
		length = 0.05
		delta = WORLD_UP * 0.05
	end
	local dir = delta * ( 1 / length )
	local mid = ( from + to ) * 0.5
	local rot = vizQuatAlignZ( dir )
	local sx = RING_THICK / RING_MESH_M
	local sz = length / RING_MESH_M
	pcall( function()
		if world then
			fx:setWorld( world )
		end
		if color then
			fx:setParameter( "Color", color )
			fx:setParameter( "color", color )
		end
		fx:setScale( sm.vec3.new( sx, sx, sz ) )
		fx:setPosition( mid )
		fx:setRotation( rot )
		if not fx:isPlaying() then
			fx:start()
		end
	end )
end

local function vizCreateLineFx( world )
	-- Unhosted world FX only. Never ShapeRenderable plastic — that welded onto the net.
	local ok, fx = pcall( sm.effect.createEffect, RING_FX )
	if not ( ok and fx ) then
		return nil
	end
	pcall( function()
		if world then
			fx:setWorld( world )
		end
	end )
	return fx
end

local function vizSegCount( range )
	local n = math.floor( ( 2 * math.pi * range ) / RING_CHORD + 0.5 )
	if n < RING_SEG_MIN then n = RING_SEG_MIN end
	if n > RING_SEG_MAX then n = RING_SEG_MAX end
	return n
end

local function vizTblColor( tbl )
	if type( tbl ) == "table" and tbl.r ~= nil then
		local ok, c = pcall( sm.color.new, tbl.r, tbl.g, tbl.b, tbl.a or 1 )
		if ok and c then
			return c
		end
	end
	return RING_DEFAULT_COLOR
end

local function vizTblVec( tbl )
	if type( tbl ) ~= "table" or tbl.x == nil then
		return nil
	end
	local ok, v = pcall( sm.vec3.new, tbl.x, tbl.y, tbl.z or 0 )
	if ok then
		return v
	end
	return nil
end

local function vizWorld()
	local world = nil
	pcall( function()
		local p = sm.localPlayer.getPlayer()
		if p and p.character then
			world = p.character:getWorld()
		end
	end )
	return world
end

RfsRangeViz = RfsRangeViz or {}

function RfsRangeViz.destroyKey( host, key )
	if not host or not host.cl or type( host.cl.rfsRangeByKey ) ~= "table" then
		return
	end
	key = tostring( key or "" )
	local rec = host.cl.rfsRangeByKey[key]
	if type( rec ) ~= "table" then
		host.cl.rfsRangeByKey[key] = nil
		return
	end
	cl_destroyRangeFxList( rec.segs )
	cl_destroyRangeFxList( rec.radials )
	host.cl.rfsRangeByKey[key] = nil
end

function RfsRangeViz.destroyAll( host )
	if not host or not host.cl or type( host.cl.rfsRangeByKey ) ~= "table" then
		return
	end
	for key, _ in pairs( host.cl.rfsRangeByKey ) do
		RfsRangeViz.destroyKey( host, key )
	end
end

-- Drop Game-hosted ring for one beacon id (pickup / harvest / destroy).
function RfsRangeViz.hideKey( host, key )
	key = tostring( key or "" )
	if key == "" or not host then
		return
	end
	host.cl = host.cl or {}
	if type( host.cl.rfsRangeWant ) == "table" then
		host.cl.rfsRangeWant[key] = nil
	end
	RfsRangeViz.destroyKey( host, key )
end

-- Same-env Game client: nil rfsRangeWant so tick cannot keep the ring up.
function RfsHackRange.hideOnGame( key )
	key = tostring( key or "" )
	if key == "" then
		return
	end
	pcall( function()
		_G.g_rfsBeaconRangeVisible = _G.g_rfsBeaconRangeVisible or {}
		_G.g_rfsBeaconRangeVisible[key] = nil
	end )
	if type( RfsBotHijack ) == "table" and RfsBotHijack.setRangeVisible then
		pcall( function()
			RfsBotHijack.setRangeVisible( key, false )
		end )
	end
	local game = _G.g_rfsGame
	if game and type( RfsRangeViz ) == "table" and RfsRangeViz.hideKey then
		RfsRangeViz.hideKey( game, key )
	end
end

-- Beacon sandbox often has no g_rfsGame. sendToGame reaches Game.lua.
function RfsHackRange.notifyGameOff( key )
	key = tostring( key or "" )
	if key == "" then
		return
	end
	RfsHackRange.hideOnGame( key )
	pcall( function()
		sm.event.sendToGame( "sv_rfs_rangeOff", { key = key } )
	end )
end

local function vizSeat( rec, center, range, color, world )
	if type( rec ) ~= "table" or type( rec.segs ) ~= "table" then
		return
	end
	local z = ( rec.groundZ or vizGroundZ( center.x, center.y, center.z ) ) + RING_HOVER
	local n = rec.segN or #rec.segs
	local col = color or RING_DEFAULT_COLOR
	for i = 1, #rec.segs do
		local a0 = ( ( i - 1 ) / n ) * math.pi * 2
		local a1 = ( i / n ) * math.pi * 2
		local from = sm.vec3.new( center.x + math.cos( a0 ) * range, center.y + math.sin( a0 ) * range, z )
		local to = sm.vec3.new( center.x + math.cos( a1 ) * range, center.y + math.sin( a1 ) * range, z )
		vizApplyLine( rec.segs[i], from, to, col, world )
	end
	local radials = rec.radials or {}
	for i = 1, #radials do
		local ang = ( ( i - 1 ) / RING_RADIALS ) * math.pi * 2
		local cang, sang = math.cos( ang ), math.sin( ang )
		local hub = sm.vec3.new( center.x + cang * RING_HUB, center.y + sang * RING_HUB, z )
		local rim = sm.vec3.new( center.x + cang * range, center.y + sang * range, z )
		vizApplyLine( radials[i], hub, rim, col, world )
	end
	rec.center = center
end

local function vizRebuild( host, key, center, range, color, world )
	RfsRangeViz.destroyKey( host, key )
	range = tonumber( range ) or 16
	if range < 1 or not center then
		return
	end
	local n = vizSegCount( range )
	local segs, radials = {}, {}
	for _ = 1, n do
		local fx = vizCreateLineFx( world )
		if fx then
			segs[#segs + 1] = fx
		end
	end
	for _ = 1, RING_RADIALS do
		local fx = vizCreateLineFx( world )
		if fx then
			radials[#radials + 1] = fx
		end
	end
	host.cl.rfsRangeByKey[key] = {
		segs = segs,
		radials = radials,
		range = range,
		segN = n,
		groundZ = vizGroundZ( center.x, center.y, center.z ),
	}
	vizSeat( host.cl.rfsRangeByKey[key], center, range, color, world )
end

function RfsRangeViz.tick( host, wantMap )
	if not host then
		return
	end
	host.cl = host.cl or {}
	host.cl.rfsRangeByKey = host.cl.rfsRangeByKey or {}
	wantMap = wantMap or host.cl.rfsRangeWant or {}
	local seen = {}
	local world = vizWorld()
	local tick = 0
	pcall( function()
		tick = sm.game.getCurrentTick()
	end )
	for key, want in pairs( wantMap ) do
		key = tostring( key )
		seen[key] = true
		if type( want ) ~= "table" or want.show ~= true then
			RfsRangeViz.destroyKey( host, key )
		else
			local center = vizTblVec( want.pos )
			local range = tonumber( want.range ) or 16
			if want.raid then
				range = tonumber( want.raidRange ) or ( range * 0.5 )
			end
			local color = vizTblColor( want.color )
			local rec = host.cl.rfsRangeByKey[key]
			local n = vizSegCount( range )
			if not center then
				RfsRangeViz.destroyKey( host, key )
			else
				local needBuild = rec == nil or rec.range ~= range or rec.segN ~= n
				if needBuild then
					vizRebuild( host, key, center, range, color, world )
					if host.cl.rfsRangeByKey[key] then
						host.cl.rfsRangeByKey[key].tick = tick
					end
				else
					local moved = true
					if rec.center then
						local d = center - rec.center
						moved = d:length2() > 0.04
					end
					local due = ( rec.tick or -999 ) + 8 <= tick
					if moved or due then
						if due then
							rec.groundZ = vizGroundZ( center.x, center.y, center.z )
						end
						vizSeat( rec, center, range, color, world )
						rec.tick = tick
					end
				end
			end
		end
	end
	for key, _ in pairs( host.cl.rfsRangeByKey ) do
		if not seen[tostring( key )] then
			RfsRangeViz.destroyKey( host, key )
		end
	end
end

-- Server: tell Game to draw/hide. Never spawn FX on the beacon interactable.
function RfsHackRange.push( self, show, opts )
	opts = opts or {}
	local key = self and self.sv and self.sv.key and tostring( self.sv.key ) or nil
	if not show then
		if key then
			RfsHackRange.notifyGameOff( key )
		end
		return
	end
	local game = _G.g_rfsGame
	if not ( game and game.network and key ) then
		return
	end
	local t = opts.tier or {}
	local pos = opts.pos
	if not pos then
		pcall( function()
			local p = self.shape and self.shape.worldPosition
			if p then
				pos = { x = p.x, y = p.y, z = p.z }
			end
		end )
	end
	local color = opts.color
	if not color and t.ringColor then
		pcall( function()
			color = { r = t.ringColor.r, g = t.ringColor.g, b = t.ringColor.b, a = t.ringColor.a }
		end )
	end
	local raid, raidRange = false, t.range or 16
	pcall( function()
		if type( RfsBotHijack ) == "table" and RfsBotHijack.areaHasRaid then
			local w = nil
			pcall( function()
				w = self.shape.body:getWorld()
			end )
			raid = RfsBotHijack.areaHasRaid( self.shape.worldPosition, w ) and true or false
			if raid and RfsBotHijack.effectiveRange then
				raidRange = RfsBotHijack.effectiveRange( {
					range = t.range,
					pos = self.shape.worldPosition,
					world = w,
				} )
			end
		end
	end )
	pcall( function()
		game.network:sendToClients( "cl_rfs_rangeViz", {
			key = key,
			show = true,
			range = t.range or 16,
			raid = raid,
			raidRange = raidRange,
			pos = pos,
			color = color,
		} )
	end )
end

print( "[RFS] RfsHackRange loaded (SHOW RANGE off the electrical net)" )
