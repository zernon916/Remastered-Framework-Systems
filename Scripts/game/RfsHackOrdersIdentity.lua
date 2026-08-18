-- RfsHackOrdersIdentity.lua
-- VOLATILE: Orders color / names / rename apply.
-- FROZEN: battery spend, caps, hijack HP, E/queueOpen, SHOW RANGE host.
--
-- Game.lua is a no-world script. Color/rename RPCs that only mutate Game's
-- allies[] never reach unit saved.color / nametags. HijackHost has a world
-- and can unitByKey. Always register() even when publicData.rfsPlayerAlly
-- already made isAlly() true (0818-k miss).

RfsHackOrdersIdentity = RfsHackOrdersIdentity or {}

local function unitKeyOf( unit )
	if not unit then
		return nil
	end
	local id = nil
	pcall( function()
		id = unit.id
	end )
	if id ~= nil then
		return tostring( id )
	end
	return tostring( unit )
end

local function liveTypeOf( unit )
	local t = nil
	pcall( function()
		local char = unit and unit.character
		if char and sm.exists( char ) then
			t = tostring( char:getCharacterType() )
		end
	end )
	return t
end

local WIDGET_NAME_IDS = {
	NameEdit = true,
	NameLabel = true,
	BtnRename = true,
	Title = true,
	Status = true,
	Hint = true,
	Footer = true,
	CloseButton = true,
}

function RfsHackOrdersIdentity.sanitizeName( name )
	name = tostring( name or "" ):gsub( "^%s+", "" ):gsub( "%s+$", "" )
	if name == "" then
		return ""
	end
	if WIDGET_NAME_IDS[name] or string.match( name, "^BotName%d+$" )
		or string.match( name, "^ModeDrop%d+$" ) or string.match( name, "^SeedDrop%d+$" ) then
		return ""
	end
	if #name > 24 then
		name = string.sub( name, 1, 24 )
	end
	return name
end

local function isGenericName( name )
	name = tostring( name or "" )
	if name == "" or name == "Bot" then
		return true
	end
	if string.match( name, "^Bot%s+%d+$" ) then
		return true
	end
	if string.find( name, "^Inf ", 1 ) or string.find( name, "^Ally ", 1 ) then
		return true
	end
	if type( RfsBotHijack ) == "table" and type( RfsBotHijack.parseTypeNumberName ) == "function" then
		local label = RfsBotHijack.parseTypeNumberName( name )
		if label == "Bot" then
			return true
		end
	end
	return false
end

function RfsHackOrdersIdentity.localRowReady( unit )
	if type( RfsBotHijack ) ~= "table" or type( RfsBotHijack.allies ) ~= "table" then
		return false
	end
	local uk = unitKeyOf( unit )
	if not uk then
		return false
	end
	local info = RfsBotHijack.allies[uk]
	if type( info ) ~= "table" or info.controlled ~= true then
		return false
	end
	if not isGenericName( info.displayName ) then
		return true
	end
	-- Generic "Bot N": retry only if live type can produce a real label.
	local t = info.unitType or info.type or liveTypeOf( unit )
	if type( RfsBotHijack.shortTypeName ) == "function" and t then
		local want = nil
		pcall( function()
			want = RfsBotHijack.shortTypeName( t )
		end )
		if want and want ~= "" and want ~= "Bot" then
			return false
		end
	end
	return true
end

function RfsHackOrdersIdentity.pushName( unit )
	if not unit or type( RfsBotHijack ) ~= "table" or type( RfsBotHijack.pushTag ) ~= "function" then
		return
	end
	local uk = unitKeyOf( unit )
	local info = uk and RfsBotHijack.allies and RfsBotHijack.allies[uk]
	local text = nil
	if type( info ) == "table" and type( RfsBotHijack.identityTagText ) == "function" then
		pcall( function()
			text = RfsBotHijack.identityTagText( info )
		end )
	end
	if not text or text == "" or isGenericName( text ) then
		local t = ( info and ( info.unitType or info.type ) ) or liveTypeOf( unit )
		local typeName = "Bot"
		if type( RfsBotHijack.shortTypeName ) == "function" then
			pcall( function()
				typeName = RfsBotHijack.shortTypeName( t ) or "Bot"
			end )
		end
		local n = info and tonumber( info.displayIndex ) or nil
		local custom = info and info.customName and RfsHackOrdersIdentity.sanitizeName( info.customName ) or ""
		custom = custom:gsub( "%s+[Bb]ot%s*$", "" ):gsub( "%s+$", "" )
		if custom ~= "" then
			text = custom
		else
			text = n and ( typeName .. " " .. tostring( n ) ) or typeName
		end
	end
	if text and text ~= "" then
		pcall( RfsBotHijack.pushTag, unit, text, "name" )
	end
end

function RfsHackOrdersIdentity.adopt( unit, opts )
	if not unit then
		return false
	end
	opts = opts or {}
	opts.playerAlly = true
	if not opts.unitType then
		opts.unitType = liveTypeOf( unit )
	end
	if type( RfsHackApply ) == "table" and type( RfsHackApply.applyInThisEnv ) == "function" then
		pcall( RfsHackApply.applyInThisEnv, unit, opts.owner or opts.ownerId or 0, opts )
	elseif type( RfsBotHijack ) == "table" and type( RfsBotHijack.register ) == "function" then
		pcall( RfsBotHijack.register, unit, opts.owner or opts.ownerId or 0, opts )
	end
	RfsHackOrdersIdentity.pushName( unit )
	return RfsHackOrdersIdentity.localRowReady( unit )
		or ( type( RfsBotHijack ) == "table" and type( RfsBotHijack.isAlly ) == "function" and RfsBotHijack.isAlly( unit ) )
end

local function resolveUnit( key, world )
	key = tostring( key or "" )
	if key == "" or type( RfsBotHijack ) ~= "table" then
		return nil
	end
	if type( RfsBotHijack.unitByKey ) == "function" then
		local ok, u = pcall( RfsBotHijack.unitByKey, key, world )
		if ok and u then
			return u
		end
	end
	return nil
end

function RfsHackOrdersIdentity.applyColor( params )
	params = params or {}
	local hex = params.colorHex and tostring( params.colorHex ) or nil
	if type( RfsBotHijack ) == "table" and type( RfsBotHijack.normalizeColorHex ) == "function" then
		hex = RfsBotHijack.normalizeColorHex( hex )
	end
	if not hex then
		return false, "bad color", 0
	end
	local beaconKey = params.beaconKey and tostring( params.beaconKey ) or nil
	if beaconKey and type( RfsBotHijack ) == "table" and type( RfsBotHijack.setDomainAllyColor ) == "function" then
		pcall( RfsBotHijack.setDomainAllyColor, beaconKey, hex )
	end
	local keys = {}
	if params.unitKey and tostring( params.unitKey ) ~= "" then
		keys[#keys + 1] = tostring( params.unitKey )
	end
	if type( params.unitKeys ) == "table" then
		for _, k in ipairs( params.unitKeys ) do
			if k ~= nil and tostring( k ) ~= "" then
				keys[#keys + 1] = tostring( k )
			end
		end
	end
	local player = params.player
	local allowHost = params.allowHost and true or false
	local world = params.world
	local n = 0
	local lastErr = nil
	for _, key in ipairs( keys ) do
		local unit = resolveUnit( key, world )
		if unit then
			RfsHackOrdersIdentity.adopt( unit, {
				playerAlly = true,
				beaconKey = beaconKey,
				workBeaconKey = beaconKey,
				hackBeaconKey = beaconKey,
				allyColor = hex,
				owner = player and player.id or 0,
				unitType = liveTypeOf( unit ),
			} )
		end
		local ok, err = false, "no bot"
		if type( RfsBotHijack ) == "table" and type( RfsBotHijack.setAllyColor ) == "function" then
			ok, err = RfsBotHijack.setAllyColor( unit or key, hex, player, allowHost )
		end
		if ( not ok ) and unit then
			pcall( function()
				sm.event.sendToUnit( unit, "sv_e_rfsIdentity", {
					playerAlly = true,
					allyColor = hex,
					beaconKey = beaconKey,
					workBeaconKey = beaconKey,
				} )
			end )
			ok = true
		end
		if ok then
			n = n + 1
			if unit then
				RfsHackOrdersIdentity.pushName( unit )
			end
		else
			lastErr = err
		end
	end
	if n == 0 then
		return false, lastErr or "no bots", 0
	end
	return true, hex, n
end

function RfsHackOrdersIdentity.applyOrder( params )
	params = params or {}
	local keys = {}
	if params.unitKey and tostring( params.unitKey ) ~= "" then
		keys[#keys + 1] = tostring( params.unitKey )
	end
	if type( params.unitKeys ) == "table" then
		for _, k in ipairs( params.unitKeys ) do
			if k ~= nil and tostring( k ) ~= "" then
				keys[#keys + 1] = tostring( k )
			end
		end
	end
	local dest = nil
	if type( params.dest ) == "table" and params.dest.x ~= nil then
		dest = {
			x = tonumber( params.dest.x ) or 0,
			y = tonumber( params.dest.y ) or 0,
			z = tonumber( params.dest.z ) or 0,
		}
	end
	local mode = string.lower( tostring( params.mode or "rest" ) )
	local beaconKey = params.beaconKey and tostring( params.beaconKey ) or nil
	local leash = tonumber( params.leash )
	if not leash then
		if mode == "stay" or mode == "sentry" then
			leash = math.max( 4, ( tonumber( params.range ) or 16 ) * 0.35 )
		elseif mode == "recall" then
			leash = 6
		else
			leash = 3
		end
	end
	local player = params.player
	local allowHost = params.allowHost and true or false
	local world = params.world
	local n = 0
	local last = nil
	for _, key in ipairs( keys ) do
		local unit = resolveUnit( key, world )
		if unit then
			RfsHackOrdersIdentity.adopt( unit, {
				playerAlly = true,
				beaconKey = beaconKey,
				workBeaconKey = beaconKey,
				owner = player and player.id or 0,
				unitType = liveTypeOf( unit ),
			} )
		end
		local packed = {
			mode = mode,
			seedUuid = params.seedUuid,
			beaconKey = beaconKey,
			owner = player and player.id,
			dest = dest,
			leash = leash,
		}
		local ok, result = false, "no bot"
		if unit and type( RfsBotHijack ) == "table" and type( RfsBotHijack.setOrder ) == "function" then
			ok, result = RfsBotHijack.setOrder( unit, packed, player, allowHost )
		elseif type( RfsBotHijack ) == "table" and type( RfsBotHijack.setOrder ) == "function" then
			ok, result = RfsBotHijack.setOrder( key, packed, player, allowHost )
		end
		if unit then
			pcall( function()
				sm.event.sendToUnit( unit, "sv_e_rfsOrder", packed )
			end )
			ok = true
			result = packed
		end
		if ok then
			n = n + 1
			last = result
		end
	end
	if n == 0 then
		return false, "no bot", 0
	end
	return true, last, n
end

function RfsHackOrdersIdentity.applyRename( params )
	params = params or {}
	local name = RfsHackOrdersIdentity.sanitizeName( params.name )
	params.name = name
	local keys = {}
	if params.unitKey and tostring( params.unitKey ) ~= "" then
		keys[#keys + 1] = tostring( params.unitKey )
	end
	if type( params.unitKeys ) == "table" then
		for _, k in ipairs( params.unitKeys ) do
			if k ~= nil and tostring( k ) ~= "" then
				keys[#keys + 1] = tostring( k )
			end
		end
	end
	local player = params.player
	local allowHost = params.allowHost and true or false
	local world = params.world
	local n = 0
	for _, key in ipairs( keys ) do
		local unit = resolveUnit( key, world )
		if unit then
			RfsHackOrdersIdentity.adopt( unit, {
				playerAlly = true,
				beaconKey = params.beaconKey,
				customName = name ~= "" and name or false,
				owner = player and player.id or 0,
				unitType = liveTypeOf( unit ),
			} )
		end
		local ok = false
		if type( RfsBotHijack ) == "table" and type( RfsBotHijack.setCustomName ) == "function" then
			ok = RfsBotHijack.setCustomName( unit or key, name, player, allowHost )
		end
		if ( not ok ) and unit then
			pcall( function()
				sm.event.sendToUnit( unit, "sv_e_rfsSetCustomName", {
					name = name,
					playerId = player and player.id,
					allowHost = allowHost,
				} )
			end )
			ok = true
		end
		if ok then
			n = n + 1
			if unit then
				RfsHackOrdersIdentity.pushName( unit )
			end
		end
	end
	return n
end

print( "[RFS] RfsHackOrdersIdentity loaded (VOLATILE color/names/rename/orders)" )
