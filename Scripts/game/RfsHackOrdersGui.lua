-- RfsHackOrdersGui.lua
-- OWNER: beacon-side Orders open/list/payload. Widget GUI stays RfsBeaconOrdersGui.lua
--        (Rfs_BeaconOrders.layout). Known-good path: E → cl_openOrders → Game cl_rfs_ordersOpen
--        → RfsBeaconOrdersGui.open / createGui. Do not rewrite that open path — MOVE only.
-- VOLATILE: menus. Safe to edit without touching RfsHackPower spend.

RfsHackOrdersGui = RfsHackOrdersGui or {}
rfsHackOrdersGui = RfsHackOrdersGui

pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsBeaconOrdersGui.lua" )
end )

local function cl_beaconKey( self )
	local id = nil
	pcall( function()
		id = self.shape and self.shape.id
	end )
	if id ~= nil then
		return tostring( id )
	end
	local pd = self.cl and self.cl.pd
	if pd and pd.beaconKey then
		return tostring( pd.beaconKey )
	end
	return nil
end

-- Pre-Close-fix (9cbdbc1): open immediately on Game so createGui owns
-- Close/Master/Color. Do NOT open via beacon-sandbox RfsBeaconOrdersGui
-- (that made Close dead). Server bounce is fallback only.
function RfsHackOrdersGui.cl_openOrders( self )
	local key = cl_beaconKey( self )
	local pd = ( self.cl and self.cl.pd ) or {}
	if not key then
		return
	end
	pcall( function()
		sm.gui.chatMessage( "[RFS] HACK 3.5f-orders" )
	end )
	local payload = {
		beaconKey = key,
		beaconName = pd.name or "Hack Beacon",
		role = pd.role or "independent",
		masterKey = pd.masterKey,
		range = tonumber( pd.range ) or 16,
	}
	pcall( function()
		local pos = self.shape and self.shape.worldPosition
		if pos then
			payload.pos = { x = pos.x, y = pos.y, z = pos.z }
		end
	end )
	local game = _G.g_rfsGame
	if game and type( game.cl_rfs_ordersOpen ) == "function" then
		local ok = pcall( function()
			game:cl_rfs_ordersOpen( payload )
		end )
		if ok then
			return
		end
	end
	self.network:sendToServer( "sv_openOrdersGui", payload )
end

local function scheduleOrdersOpenOnGame( player, openData )
	if not player or type( openData ) ~= "table" or not openData.beaconKey then
		return false
	end
	local payload = {
		player = player,
		beaconKey = openData.beaconKey,
		beaconName = openData.beaconName,
		role = openData.role,
		masterKey = openData.masterKey,
		range = openData.range,
		rows = openData.rows,
		pos = openData.pos,
	}
	local game = _G.g_rfsGame
	if game and type( game.sv_rfs_ordersScheduleOpen ) == "function" then
		local ok = pcall( function()
			game:sv_rfs_ordersScheduleOpen( payload )
		end )
		if ok then
			return true
		end
	end
	local okEvent = pcall( function()
		sm.event.sendToGame( "sv_rfs_ordersScheduleOpen", payload )
	end )
	if okEvent then
		return true
	end
	okEvent = pcall( function()
		sm.event.sendToGame( "sv_rfs_ordersOpenForPlayer", payload )
	end )
	return okEvent and true or false
end

local function relayOrdersListToPlayer( player, listData )
	if not player or type( listData ) ~= "table" then
		return false
	end
	local game = _G.g_rfsGame
	if game and game.network and game.network.sendToClient then
		local ok = pcall( function()
			game.network:sendToClient( player, "cl_rfs_ordersList", listData )
		end )
		if ok then
			return true
		end
	end
	local okEvent = pcall( function()
		sm.event.sendToGame( "sv_rfs_ordersRelayToPlayer", {
			player = player,
			list = listData,
		} )
	end )
	return okEvent and true or false
end

function RfsHackOrdersGui.buildListPayload( self, player )
	local key = self.sv and self.sv.key
	if not key then
		return { rows = {} }
	end
	local ownerFilter = nil
	local allowHost = false
	pcall( function()
		local all = sm.player.getAllPlayers()
		if type( all ) == "table" and all[1] and player then
			local host = all[1]
			local hid, pid = nil, nil
			pcall( function() hid = host.id end )
			pcall( function() pid = player.id end )
			if hid ~= nil and pid ~= nil then
				allowHost = ( hid == pid )
			else
				allowHost = ( host == player )
			end
		end
	end )
	if not allowHost and player then
		pcall( function()
			ownerFilter = player.id
		end )
	end
	local rows = {}
	if type( RfsBotHijack ) == "table" and RfsBotHijack.listHomeAllies then
		pcall( function()
			rows = RfsBotHijack.listHomeAllies( key, ownerFilter ) or {}
		end )
	end
	if ( not rows or #rows == 0 ) and type( RfsBotHijack ) == "table" and RfsBotHijack.listHomeAllies then
		local unfiltered = {}
		pcall( function()
			unfiltered = RfsBotHijack.listHomeAllies( key, nil ) or {}
		end )
		if #unfiltered > 0 then
			rows = unfiltered
		end
	end
	pcall( function()
		local snap = {}
		for _, row in ipairs( rows ) do
			if row and row.key and RfsBotHijack.allies then
				local info = RfsBotHijack.allies[tostring( row.key )]
				if info then
					snap[tostring( row.key )] = {
						type = info.type and tostring( info.type ) or nil,
						unitType = info.unitType and tostring( info.unitType ) or nil,
						owner = info.owner,
						mode = info.mode and tostring( info.mode ) or nil,
						beaconKey = info.beaconKey and tostring( info.beaconKey ) or nil,
						workBeaconKey = info.workBeaconKey and tostring( info.workBeaconKey ) or nil,
						controlled = true,
						displayName = info.displayName and tostring( info.displayName ) or nil,
						displayIndex = info.displayIndex ~= nil and tonumber( info.displayIndex ) or nil,
						customName = info.customName and tostring( info.customName ) or false,
						allyColor = info.allyColor and tostring( info.allyColor ) or nil,
						rfsOrder = type( info.rfsOrder ) == "table" and {
							mode = info.rfsOrder.mode,
							seedUuid = info.rfsOrder.seedUuid and tostring( info.rfsOrder.seedUuid ) or nil,
							beaconKey = info.rfsOrder.beaconKey and tostring( info.rfsOrder.beaconKey ) or nil,
							owner = info.rfsOrder.owner,
						} or nil,
					}
				end
			end
		end
		if next( snap ) then
			sm.event.sendToGame( "sv_rfs_mirrorAllies", { allies = snap } )
		end
	end )
	local role, masterKey = "independent", nil
	if type( RfsBotHijack ) == "table" and RfsBotHijack.effectiveBeaconRole then
		pcall( function()
			role, masterKey = RfsBotHijack.effectiveBeaconRole( key )
		end )
	end
	local t = self.sv and self.sv.tier
	return {
		rows = rows,
		beaconKey = tostring( key ),
		beaconName = t and t.name or "Hack Beacon",
		role = role,
		masterKey = masterKey,
	}
end

local function sv_sendOrdersOpen( self, player, params )
	if not player then
		return false
	end
	local t = self.sv and self.sv.tier
	local listPayload = RfsHackOrdersGui.buildListPayload( self, player )
	local data = {
		beaconKey = self.sv and self.sv.key or ( params and params.beaconKey ),
		beaconName = ( params and params.beaconName ) or listPayload.beaconName or ( t and t.name ) or "Hack Beacon",
		role = listPayload.role or "independent",
		masterKey = listPayload.masterKey,
		range = t and t.range or 16,
		rows = listPayload.rows,
		pos = params and params.pos or nil,
	}
	if not data.pos then
		pcall( function()
			local pos = self.shape and self.shape.worldPosition
			if pos then
				data.pos = { x = pos.x, y = pos.y, z = pos.z }
			end
		end )
	end
	local game = _G.g_rfsGame
	if game and game.network and game.network.sendToClient then
		local ok = pcall( function()
			game.network:sendToClient( player, "cl_rfs_ordersOpen", data )
		end )
		if ok then
			return true
		end
	end
	return scheduleOrdersOpenOnGame( player, data )
end

function RfsHackOrdersGui.sv_openOrdersGui( self, params, player )
	if not sv_sendOrdersOpen( self, player, params ) then
		pcall( function()
			self.network:sendToClients( "cl_rfsMsg", "Orders: Game host missing — reopen world / check custom game" )
		end )
	end
end

function RfsHackOrdersGui.sv_ordersList( self, params, player )
	local listPayload = RfsHackOrdersGui.buildListPayload( self, player )
	relayOrdersListToPlayer( player, listPayload )
end

function RfsHackOrdersGui.sv_setShowRange( self, params, player )
	params = params or {}
	local key = self.sv and self.sv.key
	if not key then
		return
	end
	local show = params.show and true or false
	if type( RfsBotHijack ) == "table" and RfsBotHijack.setRangeVisible then
		RfsBotHijack.setRangeVisible( key, show )
	end
	if type( RfsHackRange ) == "table" and RfsHackRange.push then
		RfsHackRange.push( self, show, { tier = self.sv and self.sv.tier } )
	end
end

function RfsHackOrdersGui.sv_setMaster( self, params, player )
	if not self.sv or not self.sv.key then
		return
	end
	if type( RfsBotHijack ) ~= "table" or not RfsBotHijack.claimMaster then
		return
	end
	self.sv.role = "master"
	self.sv.masterKey = nil
	local ok, err = RfsBotHijack.claimMaster( self.sv.key )
	if ok then
		self.sv.role = "master"
		self.sv.masterKey = nil
		if type( RfsHackSave ) == "table" then
			RfsHackSave.saveRole( self )
		end
	end
	local result = {
		ok = ok and true or false,
		msg = ok and nil or tostring( err or "claim failed" ),
		master = ok and true or false,
	}
	local rolePayload = nil
	if ok then
		rolePayload = {
			beaconKey = self.sv.key,
			role = "master",
			masterKey = nil,
		}
	end
	local game = _G.g_rfsGame
	if game and player and game.network then
		pcall( function()
			game.network:sendToClient( player, "cl_rfs_ordersSetResult", result )
			if rolePayload then
				game.network:sendToClient( player, "cl_rfs_ordersRole", rolePayload )
			end
		end )
		return
	end
	if player then
		pcall( function()
			sm.event.sendToGame( "sv_rfs_ordersRelayToPlayer", {
				player = player,
				setResult = result,
				role = rolePayload,
			} )
		end )
	end
end

function RfsHackOrdersGui.sv_clearMaster( self, params, player )
	if not self.sv or not self.sv.key then
		return
	end
	self.sv.role = "independent"
	self.sv.masterKey = nil
	if type( RfsBotHijack ) == "table" and RfsBotHijack.clearMaster then
		pcall( function()
			RfsBotHijack.clearMaster( self.sv.key )
		end )
	end
	if type( RfsHackSave ) == "table" then
		RfsHackSave.saveRole( self )
	end
end

print( "[RFS] RfsHackOrdersGui loaded (Orders open path moved, not rewritten)" )
