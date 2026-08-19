-- RfsBotPath.lua — Phase 3.5 painted chests + doorway approach for Farm/Collect/Oil.
-- Color roles (shape color, not hosted FX on the beacon electrical net):
--   green = seeds (seedbot dump / hay withdraw)
--   blue  = gathered material (tote Collect / hay Farm produce)
--   any other color = overflow extra space
-- Assigned: chest on the same creation as the home beacon, or logic-connected to it.
-- In-range colored chests also work. Do not parent renderables onto the beacon.

RfsBotPath = RfsBotPath or {}

RfsBotPath.ROLE_SEED = "seed"
RfsBotPath.ROLE_PRODUCE = "produce"
RfsBotPath.ROLE_DROP = "drop"
RfsBotPath.ROLE_ANY = "any"

local REACH = 3.6
local REACH2 = REACH * REACH
local APPROACH = 2.6

local CHEST_FALLBACK = {
	obj_container_chest = "ad35f7e6-af8f-40fa-aef4-77d827ac8a8a",
	obj_container_smallchest = "fcfae5e2-1df9-47d8-bb9a-30bec9b5b1f5",
	obj_container_tinychest = "7527cf2e-1705-4214-9d07-3dc374957e25",
	obj_container_XXL_chest = "9601f2ca-9552-48b0-afc1-b0f200461114",
}

local chestSet = nil

local function uuidStr( u )
	if u == nil then
		return nil
	end
	return string.lower( tostring( u ) )
end

local function rebuildChestSet()
	chestSet = {}
	for name, fallback in pairs( CHEST_FALLBACK ) do
		local g = _G[name]
		if g ~= nil then
			chestSet[uuidStr( g )] = true
		end
		chestSet[string.lower( fallback )] = true
	end
end

local function inRadius( pos, home, radius )
	if not pos or not home or not radius then
		return false
	end
	local d = pos - home
	return d:length2() <= ( radius * radius )
end

local function colorRole( col )
	if not col then
		return RfsBotPath.ROLE_DROP
	end
	local r, g, b = 0.5, 0.5, 0.5
	pcall( function()
		r = col.r or r
		g = col.g or g
		b = col.b or b
	end )
	-- Green paint = seeds (seedbot dump / hay withdraw).
	if g > 0.45 and g > ( r + 0.10 ) and g > ( b + 0.10 ) then
		return RfsBotPath.ROLE_SEED
	end
	-- Blue paint = gathered material (tote Collect / hay produce).
	if b > 0.45 and b > ( r + 0.10 ) and b > ( g + 0.10 ) then
		return RfsBotPath.ROLE_PRODUCE
	end
	-- Any other color = overflow extra space.
	return RfsBotPath.ROLE_DROP
end

local function beaconShape( homeRec )
	if type( homeRec ) ~= "table" then
		return nil
	end
	local key = homeRec.key
	if not key and type( RfsBotHijack ) == "table" then
		return nil
	end
	local script = nil
	pcall( function()
		script = RfsBotHijack.beaconScripts and RfsBotHijack.beaconScripts[tostring( key )]
	end )
	if script and script.shape and sm.exists( script.shape ) then
		return script.shape, script.interactable
	end
	return nil, nil
end

local function sameBody( a, b )
	if not a or not b then
		return false
	end
	local ab, bb = nil, nil
	pcall( function()
		ab = a:getBody()
		bb = b:getBody()
	end )
	return ab ~= nil and bb ~= nil and ab == bb
end

local function logicLinked( beaconIa, chestIa )
	if not beaconIa or not chestIa or not sm.exists( beaconIa ) or not sm.exists( chestIa ) then
		return false
	end
	local lists = {}
	pcall( function()
		lists[#lists + 1] = beaconIa:getParents() or {}
		lists[#lists + 1] = beaconIa:getChildren() or {}
	end )
	for _, list in ipairs( lists ) do
		for _, other in ipairs( list ) do
			if other == chestIa then
				return true
			end
		end
	end
	return false
end

local function roleScore( row, want )
	local assigned = row.assigned and 1000 or 0
	local role = row.role or RfsBotPath.ROLE_DROP
	if want == RfsBotPath.ROLE_ANY or want == nil then
		return assigned + 100
	end
	if want == RfsBotPath.ROLE_SEED then
		if role == RfsBotPath.ROLE_SEED then
			return assigned + 300
		end
		if role == RfsBotPath.ROLE_DROP then
			return assigned + 180
		end
		return assigned + 8
	end
	if want == RfsBotPath.ROLE_PRODUCE then
		if role == RfsBotPath.ROLE_PRODUCE then
			return assigned + 300
		end
		if role == RfsBotPath.ROLE_DROP then
			return assigned + 180
		end
		return assigned + 8
	end
	-- drop-off / collect / oil
	if role == RfsBotPath.ROLE_DROP then
		return assigned + 300
	end
	if role == RfsBotPath.ROLE_PRODUCE then
		return assigned + 40
	end
	return assigned + 8
end

function RfsBotPath.findChests( homePos, radius, preferPos, role, homeRec )
	local out = {}
	if not homePos or not radius then
		return out
	end
	if not chestSet then
		rebuildChestSet()
	end
	local bShape, bIa = beaconShape( homeRec )
	local bodies = nil
	pcall( function()
		bodies = sm.body.getAllBodies()
	end )
	if type( bodies ) ~= "table" then
		return out
	end
	for _, body in ipairs( bodies ) do
		if body and sm.exists( body ) then
			local shapes = nil
			pcall( function()
				shapes = body:getShapes()
			end )
			if type( shapes ) == "table" then
				for _, shape in ipairs( shapes ) do
					if shape and sm.exists( shape ) then
						local suid = nil
						pcall( function()
							suid = shape:getShapeUuid()
						end )
						if suid and chestSet[uuidStr( suid )] then
							local ia = nil
							pcall( function()
								ia = shape:getInteractable()
							end )
							local container = nil
							if ia and sm.exists( ia ) then
								pcall( function()
									container = ia:getContainer( 0 )
								end )
							end
							if container and sm.exists( container ) then
								local pos = nil
								pcall( function()
									pos = shape.worldPosition
								end )
								if pos and inRadius( pos, homePos, radius ) then
									local col = nil
									pcall( function()
										col = shape.color or shape:getColor()
									end )
									local assigned = sameBody( shape, bShape ) or logicLinked( bIa, ia )
									local d2 = preferPos and ( pos - preferPos ):length2() or 0
									out[#out + 1] = {
										container = container,
										pos = pos,
										d2 = d2,
										role = colorRole( col ),
										assigned = assigned and true or false,
										shape = shape,
									}
								end
							end
						end
					end
				end
			end
		end
	end
	table.sort( out, function( a, b )
		local sa = roleScore( a, role )
		local sb = roleScore( b, role )
		if sa ~= sb then
			return sa > sb
		end
		return ( a.d2 or 0 ) < ( b.d2 or 0 )
	end )
	return out
end

local function rayBlocked( from, dest )
	if not from or not dest then
		return false
	end
	local hit, result = false, nil
	local ok = pcall( function()
		local up = sm.vec3.new( 0, 0, 1.1 )
		hit, result = sm.physics.raycast( from + up, dest + up )
	end )
	if not ( ok and hit and result ) then
		return false
	end
	local pt = result.pointWorld
	if not pt then
		return true
	end
	return ( pt - dest ):length2() > 4
end

function RfsBotPath.approachPos( from, dest )
	if not dest then
		return dest
	end
	if not from or not rayBlocked( from, dest ) then
		return dest
	end
	local offs = {
		{ APPROACH, 0 }, { -APPROACH, 0 }, { 0, APPROACH }, { 0, -APPROACH },
		{ APPROACH, APPROACH }, { APPROACH, -APPROACH },
		{ -APPROACH, APPROACH }, { -APPROACH, -APPROACH },
	}
	for _, o in ipairs( offs ) do
		local p = sm.vec3.new( dest.x + o[1], dest.y + o[2], dest.z )
		if not rayBlocked( from, p ) then
			return p
		end
	end
	return dest
end

function RfsBotPath.closeEnough( from, dest )
	if not from or not dest then
		return false
	end
	return ( from - dest ):length2() <= REACH2
end

function RfsBotPath.clearWalk( info )
	if type( info ) == "table" then
		info.jobWalkDest = nil
	end
end

function RfsBotPath.requestWalk( info, dest )
	if type( info ) == "table" then
		info.jobWalkDest = dest
	end
end

function RfsBotPath.botPos( unit )
	local pos = nil
	pcall( function()
		if unit and unit.character and sm.exists( unit.character ) then
			pos = unit.character.worldPosition
		end
	end )
	return pos
end

-- Walk toward a chest (doorway offset if LOS blocked). Return true when close
-- enough to deposit/withdraw this tick.
function RfsBotPath.ensureNear( unit, info, row )
	if type( row ) ~= "table" or not row.pos then
		RfsBotPath.clearWalk( info )
		return true
	end
	local from = RfsBotPath.botPos( unit )
	if not from then
		RfsBotPath.clearWalk( info )
		return true
	end
	local dest = RfsBotPath.approachPos( from, row.pos )
	if RfsBotPath.closeEnough( from, dest ) or RfsBotPath.closeEnough( from, row.pos ) then
		RfsBotPath.clearWalk( info )
		return true
	end
	RfsBotPath.requestWalk( info, dest )
	return false
end

print( "[RFS] RfsBotPath loaded (painted chests + doorway approach)" )
