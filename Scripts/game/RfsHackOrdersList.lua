-- RfsHackOrdersList.lua
-- VOLATILE: Orders list + names (rows for Stay/Recall/etc.).
-- FROZEN: E / queueOpen / cl_rfs_ordersOpen — not this file.
--
-- Why the menu was empty after 0818-d: tryFinish writes publicData.rfsPlayerAlly
-- BEFORE convertUnit/register. isAlly then returns true from that flag, so
-- convertUnit skips allies[] in every sandbox. Team/Select work; listHomeAllies
-- does not. Game.sv_rfs_ordersList cannot see the beacon's beaconScripts table
-- (separate Lua env). Read the same publicData bus the team fix uses.

RfsHackOrdersList = RfsHackOrdersList or {}

pcall( function()
	dofile( "$CONTENT_DATA/Scripts/game/RfsHackOrdersDrop.lua" )
end )

local function ownerFilterFor( player )
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
	if allowHost or not player then
		return nil
	end
	local id = nil
	pcall( function()
		id = player.id
	end )
	return id
end

local function eachUnit( world, fn )
	if g_unitManager and type( g_unitManager.sv_getAllUnits ) == "function" then
		local ok, units = pcall( function()
			return g_unitManager:sv_getAllUnits()
		end )
		if ok and type( units ) == "table" then
			for _, u in pairs( units ) do
				if u and sm.exists( u ) then
					fn( u )
				end
			end
			return
		end
	end
	if type( RfsBotHijack ) == "table" and type( RfsBotHijack.unitByKey ) == "function" then
		-- unitByKey already prefers UnitManager; still need a list. Fall through.
	end
	local list = nil
	if world ~= nil then
		pcall( function()
			list = sm.unit.getAllUnits( world )
		end )
	end
	if type( list ) ~= "table" then
		pcall( function()
			list = sm.unit.getAllUnits()
		end )
	end
	if type( list ) ~= "table" then
		return
	end
	for _, u in pairs( list ) do
		if u and sm.exists( u ) then
			fn( u )
		end
	end
end

local function unitWorld( player )
	local world = nil
	pcall( function()
		local game = _G.g_rfsGame
		if game and game.sv and game.sv.saved then
			world = game.sv.saved.overworld
		end
	end )
	pcall( function()
		local char = player and player.character
		if char and sm.exists( char ) then
			world = char:getWorld()
		end
	end )
	return world
end

local function publicBlob( unit )
	local flagged = false
	local blob = nil
	pcall( function()
		local char = unit.character
		if char and sm.exists( char ) and type( char.publicData ) == "table" then
			local pd = char.publicData
			if pd.rfsPlayerAlly then
				flagged = true
			end
			if type( pd.rfsAllyInfo ) == "table" then
				blob = pd.rfsAllyInfo
			elseif not blob and type( pd.rfsHackApply ) == "table" then
				blob = pd.rfsHackApply
			end
			if type( blob ) == "table" and not blob.rfsOrder and type( pd.rfsOrder ) == "table" then
				blob = blob
				blob.rfsOrder = pd.rfsOrder
			elseif flagged and not blob and type( pd.rfsOrder ) == "table" then
				blob = { playerAlly = true, rfsOrder = pd.rfsOrder }
			end
		end
	end )
	pcall( function()
		if type( unit.publicData ) == "table" then
			local pd = unit.publicData
			if pd.rfsPlayerAlly then
				flagged = true
			end
			if not blob and type( pd.rfsAllyInfo ) == "table" then
				blob = pd.rfsAllyInfo
			elseif not blob and type( pd.rfsHackApply ) == "table" then
				blob = pd.rfsHackApply
			end
			if type( blob ) == "table" and not blob.rfsOrder and type( pd.rfsOrder ) == "table" then
				blob.rfsOrder = pd.rfsOrder
			elseif flagged and not blob and type( pd.rfsOrder ) == "table" then
				blob = { playerAlly = true, rfsOrder = pd.rfsOrder }
			end
		end
	end )
	if not flagged then
		return nil
	end
	return blob or { playerAlly = true }
end

local function blobHomeKey( blob )
	if type( blob ) ~= "table" then
		return nil
	end
	if blob.workBeaconKey ~= nil then
		return tostring( blob.workBeaconKey )
	end
	if blob.hackBeaconKey ~= nil then
		return tostring( blob.hackBeaconKey )
	end
	if blob.beaconKey ~= nil then
		return tostring( blob.beaconKey )
	end
	return nil
end

local function inRangeOf( unit, pos, range )
	if type( pos ) ~= "table" or pos.x == nil then
		return false
	end
	local r = tonumber( range ) or 16
	local ok = false
	pcall( function()
		local char = unit.character
		if char and sm.exists( char ) then
			local p = char.worldPosition
			local dx = p.x - pos.x
			local dy = p.y - pos.y
			local dz = p.z - pos.z
			ok = ( dx * dx + dy * dy + dz * dz ) <= ( r * r )
		end
	end )
	return ok
end

local function orderModeFromInfo( info )
	local ord = info and ( info.rfsOrder or info.order ) or nil
	if type( ord ) == "table" and ord.mode and tostring( ord.mode ) ~= "" then
		return string.lower( tostring( ord.mode ) )
	end
	return nil
end

local function rowFromInfo( key, info )
	local orderMode = orderModeFromInfo( info ) or "defend"
	local ord = info and ( info.rfsOrder or info.order ) or nil
	local seedUuid = nil
	if type( ord ) == "table" and ord.seedUuid ~= nil then
		seedUuid = tostring( ord.seedUuid )
	end
	local name = nil
	if type( RfsBotHijack ) == "table" and type( RfsBotHijack.identityTagText ) == "function" then
		pcall( function()
			name = RfsBotHijack.identityTagText( info )
		end )
	end
	if not name or name == "" then
		name = tostring( info and ( info.displayName or info.customName ) or "Bot" )
	end
	return {
		key = tostring( key ),
		name = name,
		customName = info and info.customName ~= nil and tostring( info.customName ) or nil,
		displayIndex = info and tonumber( info.displayIndex ) or nil,
		unitType = info and ( info.unitType ~= nil and tostring( info.unitType ) or ( info.type ~= nil and tostring( info.type ) or nil ) ) or nil,
		type = info and info.type ~= nil and tostring( info.type ) or nil,
		mode = orderMode,
		seedUuid = seedUuid,
		owner = info and info.owner or nil,
		allyMode = info and info.mode ~= nil and tostring( info.mode ) or nil,
		allyColor = info and info.allyColor ~= nil and tostring( info.allyColor ) or nil,
		hackBeaconKey = info and info.hackBeaconKey ~= nil and tostring( info.hackBeaconKey ) or nil,
	}
end

local function unitTypeOf( unit )
	local t = nil
	pcall( function()
		local char = unit.character
		if char and sm.exists( char ) then
			t = tostring( char:getCharacterType() )
		end
	end )
	return t
end

local function adoptPublicAlly( unit, beaconKey, blob )
	if type( RfsBotHijack ) ~= "table" or type( RfsBotHijack.register ) ~= "function" then
		return false
	end
	local uk = nil
	pcall( function()
		uk = tostring( unit.id )
	end )
	if not uk or uk == "" then
		return false
	end
	if RfsBotHijack.allies and RfsBotHijack.allies[uk] and RfsBotHijack.allies[uk].controlled then
		-- Still register() so public-ally converts get a local row (do not skip).
	end
	blob = blob or {}
	local home = blobHomeKey( blob ) or tostring( beaconKey )
	local ownerId = blob.owner or blob.ownerId or 0
	local unitType = blob.unitType or unitTypeOf( unit )
	pcall( function()
		RfsBotHijack.register( unit, ownerId, {
			playerAlly = true,
			mode = blob.mode or "tethered",
			beaconKey = blob.beaconKey or home,
			workBeaconKey = blob.workBeaconKey or home,
			hackBeaconKey = blob.hackBeaconKey or blob.beaconKey or home,
			hijackTicks = blob.hijackTicks,
			allyColor = blob.allyColor,
			displayName = blob.displayName,
			displayIndex = blob.displayIndex,
			customName = blob.customName,
			unitType = unitType,
			firstSeenTick = blob.firstSeenTick,
			rfsOrder = blob.rfsOrder or blob.order,
		} )
	end )
	local info = RfsBotHijack.allies and RfsBotHijack.allies[uk]
	if info and type( RfsBotHijack.pushTag ) == "function" then
		pcall( function()
			RfsBotHijack.pushTag( unit, RfsBotHijack.identityTagText( info ), "name" )
		end )
	end
	return info and info.controlled and true or false
end

-- Scan engine-shared rfsPlayerAlly and adopt into THIS env's allies[] so names
-- and later Stay/Recall RPCs resolve. Does not change how E opens the GUI.
local function collectFromPublic( beaconKey, player, opts )
	opts = opts or {}
	local rows = {}
	local ownerFilter = opts.ownerFilter
	beaconKey = tostring( beaconKey or "" )
	if beaconKey == "" then
		return rows
	end
	local matchedHome = {}
	local matchedRange = {}
	local matchedAny = {}
	eachUnit( opts.world or unitWorld( player ), function( unit )
		if type( RfsHackOrdersDrop ) == "table" and type( RfsHackOrdersDrop.unitLooksDead ) == "function" then
			local dead = false
			pcall( function()
				dead = RfsHackOrdersDrop.unitLooksDead( unit ) and true or false
			end )
			if dead then
				return
			end
		end
		local blob = publicBlob( unit )
		if not blob then
			return
		end
		local uk = nil
		pcall( function()
			uk = tostring( unit.id )
		end )
		if not uk or uk == "" then
			return
		end
		local home = blobHomeKey( blob )
		local rec = { unit = unit, blob = blob, key = uk }
		if home == beaconKey then
			matchedHome[#matchedHome + 1] = rec
		elseif inRangeOf( unit, opts.pos, opts.range ) then
			matchedRange[#matchedRange + 1] = rec
		else
			matchedAny[#matchedAny + 1] = rec
		end
	end )
	local pick = {}
	local seen = {}
	local function addPick( list )
		for _, rec in ipairs( list or {} ) do
			if rec and rec.key and not seen[rec.key] then
				seen[rec.key] = true
				pick[#pick + 1] = rec
			end
		end
	end
	-- Domain home ∪ in-range. Exclusive-pick dropped the second convert (0818-t).
	addPick( matchedHome )
	addPick( matchedRange )
	-- Last resort: converted allies with no leftover beaconKey on publicData.
	if #pick == 0 then
		addPick( matchedAny )
	end
	for _, rec in ipairs( pick ) do
		adoptPublicAlly( rec.unit, beaconKey, rec.blob )
		local info = RfsBotHijack.allies and RfsBotHijack.allies[rec.key]
		if info and info.controlled then
			if ownerFilter == nil or tostring( info.owner ) == tostring( ownerFilter ) then
				rows[#rows + 1] = rowFromInfo( rec.key, info )
			end
		else
			-- register missed; still list from the live unit type, not generic "Bot".
			local blob = rec.blob
			local typeName = "Bot"
			local liveType = unitTypeOf( rec.unit ) or blob.unitType
			if type( RfsBotHijack ) == "table" and type( RfsBotHijack.shortTypeName ) == "function" then
				pcall( function()
					typeName = RfsBotHijack.shortTypeName( liveType ) or "Bot"
				end )
			end
			if ( not typeName or typeName == "Bot" ) and liveType then
				local lower = string.lower( tostring( liveType ) )
				if string.find( lower, "tote", 1, true ) then
					typeName = "Tote"
				elseif string.find( lower, "hay", 1, true ) then
					typeName = "Hay"
				end
			end
			local n = tonumber( blob.displayIndex )
			local name = blob.displayName
			if not name or name == "" or name == "Bot" then
				name = n and ( typeName .. " " .. tostring( n ) ) or ( typeName ~= "Bot" and typeName or "Bot" )
			end
			if ownerFilter == nil or tostring( blob.owner or blob.ownerId ) == tostring( ownerFilter ) then
				rows[#rows + 1] = {
					key = rec.key,
					name = tostring( blob.customName or name ),
					customName = blob.customName and tostring( blob.customName ) or nil,
					displayIndex = n,
					unitType = blob.unitType and tostring( blob.unitType ) or nil,
					type = blob.unitType and tostring( blob.unitType ) or nil,
					mode = ( type( blob.rfsOrder ) == "table" and blob.rfsOrder.mode )
						or ( type( blob.order ) == "table" and blob.order.mode )
						or "defend",
					seedUuid = type( blob.rfsOrder ) == "table" and blob.rfsOrder.seedUuid or nil,
					owner = blob.owner or blob.ownerId,
					allyColor = blob.allyColor and tostring( blob.allyColor ) or nil,
					hackBeaconKey = blob.hackBeaconKey and tostring( blob.hackBeaconKey ) or nil,
				}
			end
		end
	end
	table.sort( rows, function( a, b )
		return tostring( a.name ) < tostring( b.name )
	end )
	return rows
end

function RfsHackOrdersList.collect( beaconKey, player, opts )
	opts = opts or {}
	beaconKey = tostring( beaconKey or "" )
	local rows = {}
	if beaconKey == "" then
		return rows
	end
	local ownerFilter = opts.ownerFilter
	if ownerFilter == nil and opts.allowHost ~= true then
		ownerFilter = ownerFilterFor( player )
	end
	-- Always adopt publicData allies into THIS env first so names/color/rename
	-- resolve even when listHomeAllies already returned generic "Bot" rows.
	opts.ownerFilter = ownerFilter
	local publicRows = collectFromPublic( beaconKey, player, opts )
	if type( RfsBotHijack ) == "table" and RfsBotHijack.listHomeAllies then
		pcall( function()
			rows = RfsBotHijack.listHomeAllies( beaconKey, ownerFilter ) or {}
		end )
		if ( not rows or #rows == 0 ) then
			local unfiltered = {}
			pcall( function()
				unfiltered = RfsBotHijack.listHomeAllies( beaconKey, nil ) or {}
			end )
			if #unfiltered > 0 then
				rows = unfiltered
			end
		end
	end
	if type( rows ) ~= "table" then
		rows = {}
	end
	if type( rows ) ~= "table" or #rows == 0 then
		rows = publicRows
		publicRows = {}
	end
	-- Merge publicData + Game/beacon allies[] + in-range. Do not drop public-only keys.
	local byKey = {}
	local merged = {}
	local function addRow( row )
		if not row or not row.key then
			return
		end
		local k = tostring( row.key )
		if k == "" then
			return
		end
		local name = tostring( row.name or "" )
		if type( RfsHackOrdersIdentity ) == "table" and type( RfsHackOrdersIdentity.sanitizeName ) == "function" then
			if row.customName then
				local sn = RfsHackOrdersIdentity.sanitizeName( row.customName )
				row.customName = ( sn ~= "" ) and sn or nil
			end
		end
		if not byKey[k] then
			byKey[k] = row
			merged[#merged + 1] = row
			return
		end
		local prev = byKey[k]
		local prevName = tostring( prev.name or "" )
		local prevCustom = prev.customName and tostring( prev.customName ) or ""
		local rowCustom = row.customName and tostring( row.customName ) or ""
		if ( prevName == "" or prevName == "Bot" or prevName:match( "^Bot%s+%d+$" ) ) and name ~= "" then
			prev.name = row.name
			prev.customName = prev.customName or row.customName
			prev.displayIndex = prev.displayIndex or row.displayIndex
			prev.unitType = prev.unitType or row.unitType
			prev.type = prev.type or row.type
		end
		-- Prefer explicit customName from either source; newer rename must win over stale listHomeAllies.
		if rowCustom ~= "" and ( prevCustom == "" or prevCustom ~= rowCustom ) then
			prev.customName = row.customName
			if row.name and tostring( row.name ) ~= "" then
				prev.name = row.name
			elseif rowCustom ~= "" then
				prev.name = rowCustom
			end
		elseif rowCustom == "" and prevCustom ~= "" then
			-- keep prev customName
		end
		local rowMode = row.mode and string.lower( tostring( row.mode ) ) or ""
		local prevMode = prev.mode and string.lower( tostring( prev.mode ) ) or ""
		if rowMode ~= "" and rowMode ~= "defend" and ( prevMode == "" or prevMode == "defend" ) then
			prev.mode = row.mode
			prev.seedUuid = row.seedUuid or prev.seedUuid
		elseif rowMode ~= "" and prevMode == "" then
			prev.mode = row.mode
		elseif rowMode ~= "" and rowMode ~= prevMode then
			-- publicData / later source wins so close/reopen shows the live command
			prev.mode = row.mode
			prev.seedUuid = row.seedUuid or prev.seedUuid
		end
	end
	if type( rows ) == "table" then
		for _, row in ipairs( rows ) do
			addRow( row )
		end
	end
	for _, row in ipairs( publicRows or {} ) do
		addRow( row )
	end
	table.sort( merged, function( a, b )
		return tostring( a.name or "" ) < tostring( b.name or "" )
	end )
	-- Dead / destroyed units must not stay as ghost "Bot" rows.
	if type( RfsHackOrdersDrop ) == "table" and type( RfsHackOrdersDrop.rowIsDead ) == "function" then
		local liveRows = {}
		for _, row in ipairs( merged ) do
			local dead = false
			pcall( function()
				dead = row and row.key and RfsHackOrdersDrop.rowIsDead( row.key )
			end )
			if not dead then
				liveRows[#liveRows + 1] = row
			end
		end
		merged = liveRows
	end
	return merged
end

print( "[RFS] RfsHackOrdersList loaded (VOLATILE list/names; publicData.rfsPlayerAlly fallback)" )
