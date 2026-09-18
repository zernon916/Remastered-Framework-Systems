-- RfsChestFilterWorld.lua — world-row of filter item icons in front of RfsChest.
-- Matches Active strip: up to 7 icons. Empty allowlist = no GUI.
-- Billboard WorldIconGui = always upright; position uses gravity-aware longest side face.

RfsChestFilterWorld = RfsChestFilterWorld or {}

local LAYOUT = "$CONTENT_DATA/Gui/menu/layouts/Rfs_ChestFilterWorld.layout"
local LAYOUT_UUID = "$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247/Gui/menu/layouts/Rfs_ChestFilterWorld.layout"
local ICON_N = 7
local ICON_W = 180
local ICON_H = 28
local BLOCK_M = 0.25
local OUT_M = 0.5 * BLOCK_M
local SHOW_DIST = 48
local WORLD_UP = sm.vec3.new( 0, 0, 1 )
-- Large chest shapeset fallback (full meters).
local FALLBACK_FULL = sm.vec3.new( 5 * BLOCK_M, 3 * BLOCK_M, 4 * BLOCK_M )

local function destroyGui( chest )
	if not chest or not chest.cl then
		return
	end
	local gui = chest.cl.filterWorldGui
	if gui then
		pcall( function() gui:close() end )
		pcall( function() gui:destroy() end )
	end
	chest.cl.filterWorldGui = nil
	chest.cl.filterWorldSig = nil
end

local function withinShowDist( pos )
	local ok = true
	pcall( function()
		local cam = sm.camera.getPosition()
		ok = ( cam - pos ):length2() <= ( SHOW_DIST * SHOW_DIST )
	end )
	return ok
end

local function fullExtents( shape )
	local fx, fy, fz = FALLBACK_FULL.x, FALLBACK_FULL.y, FALLBACK_FULL.z
	pcall( function()
		if type( shape.getBoundingBox ) == "function" then
			local box = shape:getBoundingBox()
			if box and box.x and box.x > 0.01 then
				fx = math.abs( box.x )
				fy = math.abs( box.y )
				fz = math.abs( box.z )
				-- Some builds return half-extents; large chest full ~1.25/0.75/1.
				if fx < 0.9 and fy < 0.9 and fz < 0.9 then
					fx, fy, fz = fx * 2, fy * 2, fz * 2
				end
			end
		end
	end )
	return fx, fy, fz
end

-- Gravity-aware longest side face; offset OUT_M past the face center.
local function frontAnchor( shape )
	local origin = shape.worldPosition
	local rot = shape.worldRotation
	local fx, fy, fz = fullExtents( shape )
	local hx, hy, hz = fx * 0.5, fy * 0.5, fz * 0.5
	local camPos = nil
	pcall( function()
		camPos = sm.camera.getPosition()
	end )

	local axes = {
		{ localAx = sm.vec3.new( 1, 0, 0 ), half = hx, area = fy * fz },
		{ localAx = sm.vec3.new( 0, 1, 0 ), half = hy, area = fx * fz },
		{ localAx = sm.vec3.new( 0, 0, 1 ), half = hz, area = fx * fy },
	}

	local best = nil
	local function consider( localN, half, area, allowVertical )
		local worldN = rot * localN
		local upright = math.abs( worldN:dot( WORLD_UP ) )
		if ( not allowVertical ) and upright > 0.7 then
			return
		end
		local towardCam = 0
		local facePos = origin + ( rot * ( localN * half ) )
		if camPos then
			local toCam = camPos - facePos
			if toCam:length2() > 1e-8 then
				towardCam = worldN:dot( toCam:normalize() )
			end
		end
		-- Prefer large area, then more horizontal, then facing camera.
		local score = area * 1000 + ( 1 - upright ) * 10 + towardCam
		if not best or score > best.score then
			best = {
				score = score,
				localN = localN,
				worldN = worldN,
				half = half,
				facePos = facePos,
			}
		end
	end

	for _, ax in ipairs( axes ) do
		consider( ax.localAx, ax.half, ax.area, false )
		consider( ax.localAx * -1, ax.half, ax.area, false )
	end
	if not best then
		for _, ax in ipairs( axes ) do
			consider( ax.localAx, ax.half, ax.area, true )
			consider( ax.localAx * -1, ax.half, ax.area, true )
		end
	end
	if not best then
		return origin + WORLD_UP * ( hz + OUT_M )
	end
	return best.facePos + best.worldN * OUT_M
end

local function ensureGui( chest )
	local gui = chest.cl.filterWorldGui
	if gui then
		return gui
	end
	local created = nil
	pcall( function()
		created = sm.gui.createWorldIconGui( ICON_W, ICON_H, LAYOUT, false )
	end )
	if not created then
		pcall( function()
			created = sm.gui.createWorldIconGui( ICON_W, ICON_H, LAYOUT_UUID, false )
		end )
	end
	if not created then
		return nil
	end
	pcall( function()
		created:setRequireLineOfSight( true )
	end )
	pcall( function()
		created:open()
	end )
	chest.cl.filterWorldGui = created
	chest.cl.filterWorldSig = nil
	return created
end

local function setItemIcon( gui, widget, uuidStr )
	if not uuidStr or uuidStr == "" then
		return
	end
	local ok = pcall( function()
		gui:setIconImage( widget, sm.uuid.new( uuidStr ) )
	end )
	if ok then
		return
	end
	pcall( function()
		local path = sm.gui.getItemIconFromUuid( sm.uuid.new( uuidStr ) )
		if path then
			gui:setImage( widget, path )
		end
	end )
end

local function filtersSignature( filters )
	local parts = {}
	local n = math.min( ICON_N, #( filters or {} ) )
	for i = 1, n do
		parts[i] = tostring( filters[i] )
	end
	return table.concat( parts, ";" )
end

local function applyIcons( gui, filters, sig )
	local n = math.min( ICON_N, #( filters or {} ) )
	for i = 0, ICON_N - 1 do
		local name = "Icon" .. tostring( i )
		local id = filters[i + 1]
		if i < n and id then
			setItemIcon( gui, name, id )
			pcall( function()
				gui:setVisible( name, true )
			end )
		else
			pcall( function()
				gui:setVisible( name, false )
			end )
		end
	end
	return sig
end

function RfsChestFilterWorld.destroy( chest )
	destroyGui( chest )
end

function RfsChestFilterWorld.update( chest )
	if not chest or not chest.shape or not sm.exists( chest.shape ) then
		return
	end
	chest.cl = chest.cl or {}

	-- Prefer live publicData so all clients see filters without opening the menu.
	pcall( function()
		local pub = chest.interactable:getPublicData()
		if type( pub ) == "table" and type( pub.filters ) == "table" then
			local incoming = {}
			for _, v in ipairs( pub.filters ) do
				local id = string.lower( tostring( type( v ) == "table" and ( v.uuid or v.itemId or v.id ) or v ) )
				if id ~= "" and id ~= "00000000-0000-0000-0000-000000000000" then
					incoming[#incoming + 1] = id
				end
			end
			local cur = chest.cl.filters or {}
			local same = #incoming == #cur
			if same then
				for i = 1, #incoming do
					if incoming[i] ~= tostring( cur[i] ) then
						same = false
						break
					end
				end
			end
			if not same then
				chest.cl.filters = incoming
				chest.cl.filterWorldSig = nil
			end
		end
	end )

	local filters = chest.cl.filters or {}
	if type( filters ) ~= "table" or #filters == 0 then
		destroyGui( chest )
		return
	end

	local pos = frontAnchor( chest.shape )
	if not withinShowDist( pos ) then
		destroyGui( chest )
		return
	end

	local gui = ensureGui( chest )
	if not gui then
		return
	end

	local world = nil
	pcall( function()
		world = chest.shape:getWorld()
	end )
	pcall( function()
		gui:setWorldPosition( pos, world )
	end )

	local sig = filtersSignature( filters )
	if chest.cl.filterWorldSig ~= sig then
		chest.cl.filterWorldSig = applyIcons( gui, filters, sig )
	end
end

print( "[RFS] RfsChestFilterWorld loaded (7-icon front row)" )
