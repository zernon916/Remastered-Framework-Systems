-- RfsMiniMapTool.lua — always-on MiniMap autoTool.
-- Preferred path: host Nutt World Map (Steam Workshop 3780282057) HUD + atlas.
-- Credit: Nutt. Do not enable World Map as a world mod (duplicate HUD / GPS grant).
-- Fallback: this tool stays inert; RfsHud clock/compass/ammo and /map camera remain.
-- GPS item is not required — /map /rfsmap open Nutt's full map when this tool loaded.

RfsMiniMapTool = class()

local NUTT_LOCAL = "58df2b8e-a86f-44ed-b4f9-aa5b00b44162"
local NUTT = "$CONTENT_" .. NUTT_LOCAL

g_rfsNuttMap = false
g_rfsNuttMapErr = nil

local function probeNutt()
	local ok, idx = pcall( sm.json.open, NUTT .. "/Scripts/data/atlas_index.json" )
	if not ok or type( idx ) ~= "table" or type( idx.mini ) ~= "table" then
		return false, "atlas_index missing (" .. tostring( idx ) .. ")"
	end
	local ok2, err2 = pcall( function()
		dofile( NUTT .. "/Scripts/MinimapHud.lua" )
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
		print( "[RFS] MiniMap: Nutt World Map HUD loaded (3780282057)" )
	else
		print( "[RFS] MiniMap: Nutt HUD unavailable (" .. tostring( err ) .. ") — original HUD + /map camera" )
	end
end

-- Keep the ring off RfsHud lower-right ammo (pos 2 = bottom-right).
local function pinAwayFromAmmo( self )
	local c = self.cl
	if not c then
		return
	end
	if c.posIdx == 2 then
		c.posIdx = 1
		c.lastPos = 1
	end
end

if g_rfsNuttMap and MinimapHud then
	RfsMiniMapTool = MinimapHud
	-- /map already exists — do not auto-grant Nutt's GPS tool.
	RfsMiniMapTool.server_onFixedUpdate = function( self ) end

	local origCreate = RfsMiniMapTool.client_onCreate
	function RfsMiniMapTool.client_onCreate( self )
		if origCreate then
			origCreate( self )
		end
		pinAwayFromAmmo( self )
		if _G then
			_G.g_minimapHud = g_minimapHud or self
		end
	end

	local origInit = RfsMiniMapTool.cl_init
	if origInit then
		function RfsMiniMapTool.cl_init( self )
			origInit( self )
			pinAwayFromAmmo( self )
			if _G then
				_G.g_minimapHud = self
			end
			if not self.cl then
				return
			end
			if not self.cl.rfsNuttCredit then
				self.cl.rfsNuttCredit = true
				pcall( function()
					sm.gui.chatMessage( "[RFS] MiniMap HUD: World Map by Nutt (Workshop 3780282057). /map opens the full atlas." )
				end )
			end
		end
	end
else
	function RfsMiniMapTool.client_onCreate( self )
		print( "[RFS] MiniMap autoTool: Nutt content not loaded; original HUD fallback" )
	end
end
