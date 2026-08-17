-- RfsMiniMapTool.lua — Map phase autoTool (HUD MiniMap + Nutt atlas host).
-- Vendored Nutt World Map (Workshop 3780282057) HUD + atlas under $CONTENT_DATA.
-- Credit: Nutt. Do not also enable World Map as a world mod (double HUD / GPS grant).
-- Full atlas opens from the crafted GPS (SpikeHand LMB), not chat.
-- Fallback: this tool stays inert; RfsHud clock/compass/ammo remain.
-- One MiniMap only: this wrapper hosts MinimapHud; never also run Nutt as a world mod.

RfsMiniMapTool = class()

local NUTT = "$CONTENT_DATA"

g_rfsNuttMap = false
g_rfsNuttMapErr = nil

local function probeNutt()
	local ok, idx = pcall( sm.json.open, NUTT .. "/Scripts/nutt/data/atlas_index.json" )
	if not ok or type( idx ) ~= "table" or type( idx.mini ) ~= "table" then
		return false, "atlas_index missing (" .. tostring( idx ) .. ")"
	end
	local ok2, err2 = pcall( function()
		dofile( NUTT .. "/Scripts/nutt/MinimapHud.lua" )
	end )
	if not ok2 then
		return false, tostring( err2 )
	end
	if type( MinimapHud ) ~= "table" then
		return false, "MinimapHud class missing"
	end
	return true
end

do
	local ok, err = probeNutt()
	g_rfsNuttMap = ok and true or false
	g_rfsNuttMapErr = ok and nil or err
	if _G then
		_G.g_rfsNuttMap = g_rfsNuttMap
		_G.g_rfsNuttMapErr = g_rfsNuttMapErr
	end
	if ok then
		print( "[RFS] Map: Nutt World Map HUD + atlas vendored (3780282057)" )
	else
		print( "[RFS] Map: Nutt atlas unavailable (" .. tostring( err ) .. ") — clock/compass/ammo" )
	end
end

-- Nutt posIdx: 1=BL (covers chat) 2=BR (covers ammo) 3=TR 4=TL 5=hidden.
-- Always-on HUD starts upper-left so it does not cover the chat box or ammo.
local MINIMAP_TL = 4
local function pinUpperLeft( self )
	local c = self.cl
	if not c then
		return
	end
	if c.posIdx == 5 then
		c.lastPos = MINIMAP_TL
		return
	end
	c.posIdx = MINIMAP_TL
	c.lastPos = MINIMAP_TL
end

-- Embedding blit: jsonGui ImageBox can V-flip each ResourceImageSet frame.
-- ImageCoord height < 0 undoes that in frame space (64px mini atlas cells).
-- Keep Flip=V + negative-height UV together (they are one sample, not two
-- rotations). Atlas is now $CONTENT_DATA; do not also apply RotatingSkin on
-- mini baked rN frames — remapRotName picks the matching atlas_index key.
local TILE_PX = 64
local TILE_UV = "0 " .. tostring( TILE_PX ) .. " " .. tostring( TILE_PX ) .. " -" .. tostring( TILE_PX )
local function flipTileBlit( w )
	if type( w ) ~= "table" then
		return
	end
	-- Same UV every refill so neighbors share one sample rect (no mixed Flip).
	if w.ImageCoord == TILE_UV and w.Flip == "V" then
		return
	end
	w.ImageCoord = TILE_UV
	w.Flip = "V"
end

local function flipHudTiles( hud )
	local c = hud and hud.cl
	if not c then
		return
	end
	if type( c.cells ) == "table" then
		for _, per in pairs( c.cells ) do
			if type( per ) == "table" then
				for _, cw in pairs( per ) do
					flipTileBlit( cw )
				end
			end
		end
	end
	if type( c.overlays ) == "table" then
		for _, ov in pairs( c.overlays ) do
			flipTileBlit( ov )
		end
	end
	if type( c.rim ) == "table" then
		for _, slices in pairs( c.rim ) do
			if type( slices ) == "table" then
				for _, sl in pairs( slices ) do
					if type( sl ) == "table" then
						if type( sl.per ) == "table" then
							for _, cw in pairs( sl.per ) do
								flipTileBlit( cw )
							end
						end
						flipTileBlit( sl.ov )
					end
				end
			end
		end
	end
	local bm = c.bm
	if bm and type( bm.pools ) == "table" then
		for _, pool in pairs( bm.pools ) do
			if type( pool ) == "table" then
				if type( pool.byRes ) == "table" then
					for _, lst in pairs( pool.byRes ) do
						if type( lst ) == "table" then
							for i = 1, #lst do
								flipTileBlit( lst[i] )
							end
						end
					end
				end
				if type( pool.roads ) == "table" then
					for i = 1, #pool.roads do
						flipTileBlit( pool.roads[i] )
					end
				end
			end
		end
	end
end

-- Survival yaw 1 = 90° CCW; Nutt bakes rN as CCW but BigMap.ROTSIGN = -1 for
-- live rotate. Using baked r{cellRot} as-is swaps r1/r3 (180° vs neighbors).
local function remapRotName( name )
	if type( name ) ~= "string" then
		return name
	end
	local base, r = string.match( name, "^(.*)_r(%d)$" )
	if not base or not r then
		return name
	end
	r = tonumber( r )
	if not r then
		return name
	end
	return base .. "_r" .. tostring( ( 4 - r ) % 4 )
end

if g_rfsNuttMap and MinimapHud then
	RfsMiniMapTool = MinimapHud
	-- GPS is crafted / researched — never auto-grant Nutt's tool.
	RfsMiniMapTool.server_onFixedUpdate = function( self ) end

	local origFrameFor = RfsMiniMapTool.cl_frameFor
	if origFrameFor then
		function RfsMiniMapTool.cl_frameFor( self, wx, wy, rot )
			local frame, flags, real = origFrameFor( self, wx, wy, rot )
			if type( frame ) == "table" and type( frame.name ) == "string" then
				local key = remapRotName( frame.name )
				if key ~= frame.name then
					local hit = self.cl and self.cl.atlas and self.cl.atlas.mini and self.cl.atlas.mini[key]
					if hit then
						frame = { res = hit.res, name = key }
					end
				end
			end
			return frame, flags, real
		end
	end

	if type( BigMap ) == "table" and type( BigMap.resolve ) == "function" then
		local origResolve = BigMap.resolve
		function BigMap.resolve( hud, wx, wy, tierName )
			local f, flags, real = origResolve( hud, wx, wy, tierName )
			if type( f ) == "table" and type( f.name ) == "string" and tierName == "mini" then
				local key = remapRotName( f.name )
				if key ~= f.name then
					local atlas = hud and hud.cl and hud.cl.atlas
					local hit = atlas and atlas.mini and atlas.mini[key]
					if hit then
						f = { res = hit.res, name = key, rot = 0 }
					end
				end
			end
			return f, flags, real
		end
		local origBmBuild = BigMap.build
		function BigMap.build( hud )
			local ok = origBmBuild( hud )
			flipHudTiles( hud )
			return ok
		end
		local origBmRefill = BigMap.refill
		function BigMap.refill( hud )
			origBmRefill( hud )
			flipHudTiles( hud )
		end
	end

	local origCreate = RfsMiniMapTool.client_onCreate
	function RfsMiniMapTool.client_onCreate( self )
		if origCreate then
			origCreate( self )
		end
		pinUpperLeft( self )
		if _G then
			_G.g_minimapHud = g_minimapHud or self
		end
	end

	local origInit = RfsMiniMapTool.cl_init
	if origInit then
		function RfsMiniMapTool.cl_init( self )
			origInit( self )
			pinUpperLeft( self )
			if _G then
				_G.g_minimapHud = self
			end
			if not self.cl then
				return
			end
			if not self.cl.rfsNuttCredit then
				self.cl.rfsNuttCredit = true
				pcall( function()
					sm.gui.chatMessage( "[RFS] Map: World Map by Nutt (Workshop 3780282057). Upper-left MiniMap on. Craft/research the GPS to open the atlas. Do not enable World Map as a world mod if you already have it (double HUD)." )
				end )
			end
		end
	end

	local origBuild = RfsMiniMapTool.cl_buildGui
	if origBuild then
		function RfsMiniMapTool.cl_buildGui( self )
			pinUpperLeft( self )
			origBuild( self )
			flipHudTiles( self )
		end
	end
else
	function RfsMiniMapTool.client_onCreate( self )
		print( "[RFS] Map autoTool: Nutt content not loaded; clock/compass/ammo" )
	end
end
