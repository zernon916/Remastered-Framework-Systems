-- RfsHackStatusOverlay.lua
-- VOLATILE: floating HACK status over the beacon (RfsHackText / RfsGrowText).
-- Line 1 = raid/power status. Lines 2–3 = Connected / Add module lists (limits).
-- Do not mix into RfsHackPower spend rates.

RfsHackStatusOverlay = RfsHackStatusOverlay or {}

local FX_NAMES = { "RfsHackText", "RfsGrowText", "DebugText" }
local TEXT_FACE = sm.vec3.new( 0, 1, 0 )
local WORLD_UP = sm.vec3.new( 0, 0, 1 )
local AABB_PAD = 0.45
local LINE_GAP = 0.28

local MAX_BRICK = 1
local MAX_ANTENNA = 2
local MAX_LOCK = 1

local COL_NO_POWER = sm.color.new( 1.0, 0.28, 0.22 )
local COL_STANDBY = sm.color.new( 0.55, 0.85, 1.0 )
local COL_ARMED = sm.color.new( 1.0, 0.78, 0.18 )
local COL_ENGAGED = sm.color.new( 1.0, 0.45, 0.12 )
local COL_OFF = sm.color.new( 0.65, 0.65, 0.65 )
local COL_CONN = sm.color.new( 0.45, 0.95, 0.55 )
local COL_NEED = sm.color.new( 0.95, 0.85, 0.35 )

local function clampCount( n, maxN )
	n = tonumber( n ) or 0
	if n < 0 then
		n = 0
	end
	if n > maxN then
		n = maxN
	end
	return n
end

local function moduleCounts( pd )
	local m = ( type( pd ) == "table" and type( pd.modules ) == "table" ) and pd.modules or {}
	return {
		brick = clampCount( m.brick, MAX_BRICK ),
		antenna = clampCount( m.antenna, MAX_ANTENNA ),
		lock = clampCount( m.lock, MAX_LOCK ),
	}
end

-- Status color/label only (line 1).
function RfsHackStatusOverlay.statusFrom( pd )
	pd = pd or {}
	if pd.disabled then
		return "HACK: OFF", COL_OFF
	end
	if not pd.powered then
		return "HACK: NO POWER", COL_NO_POWER
	end
	local converting = tonumber( pd.converting ) or 0
	if pd.raid and converting > 0 then
		return "HACK: ENGAGED", COL_ENGAGED
	end
	if pd.raid then
		return "HACK: ARMED", COL_ARMED
	end
	return "HACK: STANDBY", COL_STANDBY
end

-- Connected vs still-available (respects Brick 1 / Antenna 2 / Lock 1).
function RfsHackStatusOverlay.moduleLists( pd )
	local c = moduleCounts( pd )
	local connected = {}
	local available = {}

	if c.brick > 0 then
		connected[#connected + 1] = "Brick " .. tostring( c.brick ) .. "/" .. tostring( MAX_BRICK )
	end
	if c.antenna > 0 then
		connected[#connected + 1] = "Antenna " .. tostring( c.antenna ) .. "/" .. tostring( MAX_ANTENNA )
	end
	if c.lock > 0 then
		connected[#connected + 1] = "Lock " .. tostring( c.lock ) .. "/" .. tostring( MAX_LOCK )
	end

	local brickLeft = MAX_BRICK - c.brick
	local antLeft = MAX_ANTENNA - c.antenna
	local lockLeft = MAX_LOCK - c.lock
	if brickLeft > 0 then
		available[#available + 1] = "Brick"
	end
	if antLeft > 0 then
		if antLeft >= MAX_ANTENNA then
			available[#available + 1] = "Antenna x" .. tostring( MAX_ANTENNA )
		elseif antLeft == 1 then
			available[#available + 1] = "Antenna (1 left)"
		else
			available[#available + 1] = "Antenna x" .. tostring( antLeft )
		end
	end
	if lockLeft > 0 then
		available[#available + 1] = "Lock"
	end

	local connLine = "Connected: "
	if #connected > 0 then
		connLine = connLine .. table.concat( connected, ", " )
	else
		connLine = connLine .. "none"
	end

	local addLine = "Not connected: "
	if #available > 0 then
		addLine = addLine .. table.concat( available, ", " )
	else
		addLine = addLine .. "none (full)"
	end

	return connLine, addLine, c
end

-- Single-string fingerprint for publish / change detection.
function RfsHackStatusOverlay.lineFrom( pd )
	local status = select( 1, RfsHackStatusOverlay.statusFrom( pd ) )
	local conn, need = RfsHackStatusOverlay.moduleLists( pd )
	return status .. "\n" .. conn .. "\n" .. need
end

local function destroyFxList( list )
	if type( list ) ~= "table" then
		return
	end
	for i = 1, #list do
		local fx = list[i]
		pcall( function()
			if fx and sm.exists( fx ) then
				fx:stop()
				fx:destroy()
			end
		end )
		list[i] = nil
	end
end

local function destroyFx( self )
	destroyFxList( self.cl and self.cl.rfsStatusFxLines )
	local fx = self.cl and self.cl.rfsStatusFx
	if fx then
		pcall( function()
			if sm.exists( fx ) then
				fx:stop()
				fx:destroy()
			end
		end )
	end
	if self.cl then
		self.cl.rfsStatusFx = nil
		self.cl.rfsStatusFxName = nil
		self.cl.rfsStatusFxLines = nil
		self.cl.rfsStatusLast = nil
	end
end

local function billboardQuat( worldPos )
	local camDir = sm.camera.getDirection()
	local face = -camDir
	if face:length2() < 1e-8 then
		local toCam = sm.camera.getPosition() - worldPos
		if toCam:length2() < 1e-8 then
			return sm.quat.identity()
		end
		face = toCam:normalize()
	else
		face = face:normalize()
	end
	local up = sm.camera.getUp()
	if not up or up:length2() < 1e-8 then
		up = WORLD_UP
	end
	local upOnPlane = up - face * face:dot( up )
	if upOnPlane:length2() > 1e-6 then
		up = upOnPlane:normalize()
	end
	local rot = sm.vec3.getRotation( TEXT_FACE, face )
	local zNow = rot * WORLD_UP
	if zNow:length2() > 1e-8 and up:length2() > 1e-8 then
		local okRoll, roll = pcall( sm.vec3.getRotation, zNow:normalize(), up )
		if okRoll and roll then
			rot = roll * rot
		end
	end
	return rot
end

local function createOneFx( self )
	for _, name in ipairs( FX_NAMES ) do
		local ok, created = pcall( sm.effect.createEffect, name )
		if ok and created then
			pcall( function()
				local world = self.shape and self.shape:getBody() and self.shape:getBody():getWorld()
				if world then
					created:setWorld( world )
				end
				created:setParameter( "anchor", "CENTER" )
				created:start()
			end )
			return created, name
		end
	end
	return nil, nil
end

local function ensureFxLines( self )
	self.cl.rfsStatusFxLines = self.cl.rfsStatusFxLines or {}
	local lines = self.cl.rfsStatusFxLines
	local need = 3
	for i = 1, need do
		local fx = lines[i]
		local usable = false
		pcall( function()
			usable = fx and sm.exists( fx ) and ( not fx:hasHost() )
		end )
		if not usable then
			if fx then
				pcall( function()
					if sm.exists( fx ) then
						fx:stop()
						fx:destroy()
					end
				end )
			end
			lines[i] = createOneFx( self )
		end
	end
	return lines
end

local function worldPos( self )
	local shape = self.shape
	if not shape or not sm.exists( shape ) then
		return nil
	end
	local pos = shape.worldPosition
	local minAabb, maxAabb
	local okAabb = pcall( function()
		if type( shape.getAabb ) == "function" then
			minAabb, maxAabb = shape:getAabb()
		end
	end )
	if ( not okAabb or not minAabb or not maxAabb ) then
		pcall( function()
			local body = shape:getBody()
			if body and type( body.getAabb ) == "function" then
				minAabb, maxAabb = body:getAabb()
			end
		end )
	end
	if minAabb and maxAabb and minAabb.z and maxAabb.z then
		local x = ( minAabb.x + maxAabb.x ) * 0.5
		local y = ( minAabb.y + maxAabb.y ) * 0.5
		return sm.vec3.new( x, y, maxAabb.z ) + WORLD_UP * AABB_PAD
	end
	local lift = 1.55
	pcall( function()
		if type( shape.getBoundingBox ) == "function" then
			local box = shape:getBoundingBox()
			if box and box.z then
				lift = ( tonumber( box.z ) or 0.25 ) * 0.5 + 1.1
			end
		end
	end )
	return pos + WORLD_UP * lift
end

function RfsHackStatusOverlay.cl_destroy( self )
	if not self then
		return
	end
	self.cl = self.cl or {}
	destroyFx( self )
end

function RfsHackStatusOverlay.cl_update( self, dt )
	if not self or not self.shape or not sm.exists( self.shape ) then
		return
	end
	self.cl = self.cl or {}
	local pd = self.cl.pd
	if type( pd ) ~= "table" then
		pd = {}
		pcall( function()
			local pub = self.interactable:getPublicData()
			if type( pub ) == "table" then
				pd = pub
			end
		end )
	end

	local status, statusCol = RfsHackStatusOverlay.statusFrom( pd )
	local connLine, needLine = RfsHackStatusOverlay.moduleLists( pd )
	local texts = { status, connLine, needLine }
	local colors = { statusCol, COL_CONN, COL_NEED }

	local base = worldPos( self )
	if not base then
		return
	end
	local lines = ensureFxLines( self )
	local rot = billboardQuat( base )
	-- Stack downward from the top tag so Connected / Not connected stay readable.
	for i = 1, 3 do
		local fx = lines[i]
		if fx then
			local pos = base - WORLD_UP * ( ( i - 1 ) * LINE_GAP )
			pcall( function()
				fx:setParameter( "TextContent", texts[i] or "" )
				fx:setParameter( "Color", colors[i] or COL_STANDBY )
				fx:setPosition( pos )
				fx:setRotation( rot )
				if not fx:isPlaying() then
					fx:start()
				end
			end )
		end
	end
	self.cl.rfsStatusLast = table.concat( texts, " | " )
end

print( "[RFS] RfsHackStatusOverlay loaded (Connected / Not connected lists)" )
