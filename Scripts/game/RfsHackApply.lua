-- RfsHackApply.lua
-- OWNER: countdown → convert apply, and unit/world-sandbox ally adopt.
-- VOLATILE apply glue. FROZEN spend is RfsHackPower. FROZEN hijack HP is RfsHackTether.
-- Last known-good convert: rush-base 75abb2f (convertUnit at remainTicks<=0, register
-- in THIS env, clear HACK tag, do not start another hack). Spend once per SUCCESS
-- only — never rush-base spendOne every tick while remainTicks<=0.
--
-- Countdown + tag live in the beacon interactable Lua env. RobotSelectTarget /
-- unit saved.color live in the world/unit env (HijackHost). Beacon register() is
-- not the table Select reads. 0818-b cleared the HACK tag and fired RPCs, but
-- never flipped the unit self (saved.playerAlly + register + setColor + standDown).
-- 0818-c: persistTint / saved.color ran; Select isAlly / standDown / hostility did not
-- because isAlly only read THIS env's allies[] (register miss). 0818-d: publicData
-- rfsPlayerAlly is the team bus Select reads.

RfsHackApply = RfsHackApply or {}

local STORAGE_Q = "RFS_HACK_APPLY_Q"

-- [unitKey] = beaconKey. One convert attempt per field visit. Cleared when the
-- bot leaves coverage so a later walk-in can retry. Prevents the 0818-a re-hack loop.
RfsHackApply._done = RfsHackApply._done or {}

local function unitKeyOf( unit )
	if not unit then
		return nil
	end
	local uk = nil
	pcall( function()
		uk = tostring( unit.id )
	end )
	if uk and uk ~= "" then
		return uk
	end
	return tostring( unit )
end

function RfsHackApply.markDone( unit, bkey )
	local k = unitKeyOf( unit )
	if k then
		RfsHackApply._done[k] = tostring( bkey or "" )
	end
end

function RfsHackApply.isDone( unit )
	local k = unitKeyOf( unit )
	return k ~= nil and RfsHackApply._done[k] ~= nil
end

function RfsHackApply.clearDone( unit )
	local k = unitKeyOf( unit )
	if k then
		RfsHackApply._done[k] = nil
	end
end

function RfsHackApply.hasLiveBeacon()
	if type( RfsBotHijack ) ~= "table" or type( RfsBotHijack.beacons ) ~= "table" then
		return false
	end
	for _, rec in pairs( RfsBotHijack.beacons ) do
		if rec and rec.pos and rec.powered then
			return true
		end
	end
	return false
end

function RfsHackApply.optsFrom( rec, bkey, need, unit )
	local mode = ( rec and rec.canInfect ) and "infected" or "tethered"
	local workKey = bkey
	if type( RfsBotHijack ) == "table" and type( RfsBotHijack.orderDomainMasterKey ) == "function" then
		pcall( function()
			workKey = RfsBotHijack.orderDomainMasterKey( bkey ) or bkey
		end )
	end
	local unitType = nil
	pcall( function()
		local char = unit and unit.character
		if char and sm.exists( char ) then
			unitType = tostring( char:getCharacterType() )
		end
	end )
	return {
		mode = mode,
		beaconKey = bkey,
		workBeaconKey = workKey,
		hackBeaconKey = bkey,
		hijackTicks = ( rec and rec.hijackTicks ) or need,
		playerAlly = true,
		unitType = unitType,
	}
end

local function payloadFrom( ownerId, opts )
	opts = opts or {}
	return {
		playerAlly = true,
		owner = ownerId or 0,
		ownerId = ownerId or 0,
		mode = opts.mode,
		beaconKey = opts.beaconKey,
		workBeaconKey = opts.workBeaconKey,
		hackBeaconKey = opts.hackBeaconKey or opts.beaconKey,
		hijackTicks = opts.hijackTicks,
		allyColor = opts.allyColor,
		displayName = opts.displayName,
		displayIndex = opts.displayIndex,
		customName = opts.customName,
		unitType = opts.unitType,
		firstSeenTick = opts.firstSeenTick,
		rfsOrder = opts.rfsOrder or opts.order,
	}
end

-- Engine-shared across Lua sandboxes (same channel as rfsHackable). Beacon
-- writes this at countdown 0; unit think / HijackHost consume it.
function RfsHackApply.writePublicOrder( unit, order )
	if not unit or type( order ) ~= "table" then
		return
	end
	local packed = {
		mode = order.mode,
		seedUuid = order.seedUuid,
		beaconKey = order.beaconKey,
		owner = order.owner,
		dest = type( order.dest ) == "table" and order.dest or nil,
		leash = tonumber( order.leash ),
	}
	local function merge( pd )
		if type( pd ) ~= "table" then
			pd = {}
		end
		pd.rfsPlayerAlly = true
		if type( pd.rfsAllyInfo ) ~= "table" then
			pd.rfsAllyInfo = {}
		end
		pd.rfsAllyInfo.rfsOrder = packed
		pd.rfsAllyInfo.order = packed
		pd.rfsOrder = packed
		return pd
	end
	pcall( function()
		local char = unit.character
		if char and sm.exists( char ) then
			char.publicData = merge( char.publicData )
		end
	end )
	pcall( function()
		unit.publicData = merge( unit.publicData )
	end )
end

function RfsHackApply.writePublicApply( unit, ownerId, opts )
	if not unit then
		return
	end
	local payload = payloadFrom( ownerId, opts )
	local function stamp( pd )
		if type( pd ) ~= "table" then
			pd = {}
		end
		pd.rfsHackApply = payload
		pd.rfsPlayerAlly = true
		-- Sticky identity for Orders list. Game sandbox never gets allies[]
		-- after 0818-d (isAlly is already true from this flag). clearPublicApply
		-- must not wipe this — only the one-shot rfsHackApply blob.
		pd.rfsAllyInfo = payload
		return pd
	end
	pcall( function()
		local char = unit.character
		if char and sm.exists( char ) then
			char.publicData = stamp( char.publicData )
		end
	end )
	pcall( function()
		unit.publicData = stamp( unit.publicData )
	end )
end

-- Real convert identity: a powered-device finish (beaconKey) or cheat/infected.
-- Bare rfsPlayerAlly / { playerAlly = true } is the 0818-w autohack stamp — not enough.
function RfsHackApply.payloadHasDevice( payload )
	if type( payload ) ~= "table" then
		return false
	end
	if payload.beaconKey ~= nil and tostring( payload.beaconKey ) ~= "" then
		return true
	end
	if payload.workBeaconKey ~= nil and tostring( payload.workBeaconKey ) ~= "" then
		return true
	end
	if payload.hackBeaconKey ~= nil and tostring( payload.hackBeaconKey ) ~= "" then
		return true
	end
	local mode = string.lower( tostring( payload.mode or payload.playerAllyMode or "" ) )
	return mode == "infected"
end

function RfsHackApply.savedHasDevice( saved )
	if type( saved ) ~= "table" then
		return false
	end
	return RfsHackApply.payloadHasDevice( {
		beaconKey = saved.playerAllyBeacon,
		workBeaconKey = saved.playerAllyWorkBeacon,
		hackBeaconKey = saved.rfsHackBeacon,
		mode = saved.playerAllyMode,
	} )
end

-- Beacon one-shot blob or sticky rfsAllyInfo with a device/infected identity.
-- Do NOT treat leftover rfsPlayerAlly as a convert payload (instant global ally).
function RfsHackApply.readPublicApply( unit )
	if not unit then
		return nil
	end
	local payload = nil
	local function take( pd )
		if type( pd ) ~= "table" then
			return nil
		end
		if type( pd.rfsHackApply ) == "table" and RfsHackApply.payloadHasDevice( pd.rfsHackApply ) then
			return pd.rfsHackApply
		end
		if type( pd.rfsAllyInfo ) == "table" and RfsHackApply.payloadHasDevice( pd.rfsAllyInfo ) then
			return pd.rfsAllyInfo
		end
		return nil
	end
	pcall( function()
		local char = unit.character
		if char and sm.exists( char ) then
			payload = take( char.publicData )
		end
	end )
	if payload then
		return payload
	end
	pcall( function()
		payload = take( unit.publicData )
	end )
	return payload
end

local function clearPublicApplyTable( pd, keepAlly )
	if type( pd ) ~= "table" then
		return
	end
	if type( pd.rfsHackApply ) == "table" and type( pd.rfsAllyInfo ) ~= "table"
		and RfsHackApply.payloadHasDevice( pd.rfsHackApply ) then
		pd.rfsAllyInfo = pd.rfsHackApply
	end
	pd.rfsHackApply = nil
	if keepAlly then
		pd.rfsPlayerAlly = true
	else
		pd.rfsPlayerAlly = nil
		pd.rfsAllyInfo = nil
		pd.rfsOrder = nil
		pd.rfsHackApply = nil
	end
end

function RfsHackApply.clearPublicApply( unit, keepAlly )
	if not unit then
		return
	end
	if keepAlly == nil then
		keepAlly = true
	end
	pcall( function()
		local char = unit.character
		if char and sm.exists( char ) then
			clearPublicApplyTable( char.publicData, keepAlly )
		end
	end )
	pcall( function()
		clearPublicApplyTable( unit.publicData, keepAlly )
	end )
end

-- Drop the 0818-w leftover stamp so wild bots are hostile again (still hackable).
-- Do not unregister()/ban — that would lock them out of a later in-range convert.
function RfsHackApply.wipeFalseAlly( self )
	if type( self ) ~= "table" or not self.unit then
		return false
	end
	self.saved = self.saved or {}
	self.saved.playerAlly = nil
	self.saved.playerAllyMode = nil
	self.saved.playerAllyBeacon = nil
	self.saved.playerAllyWorkBeacon = nil
	self.saved.rfsHackBeacon = nil
	self.saved.rfsOrder = nil
	self.saved.friendly = nil
	self.isDirty = true
	pcall( RfsHackApply.clearPublicApply, self.unit, false )
	pcall( RfsHackApply.clearDone, self.unit )
	if type( RfsBotHijack ) == "table" and type( RfsBotHijack.allies ) == "table" then
		pcall( function()
			RfsBotHijack.allies[tostring( self.unit.id )] = nil
		end )
	end
	return true
end

local function persistTint( self, hex )
	if type( self ) ~= "table" or not hex then
		return
	end
	self.saved = self.saved or {}
	self.saved.rfsAllyColor = hex
	local col = nil
	pcall( function()
		col = sm.color.new( hex )
	end )
	if not col then
		pcall( function()
			col = sm.color.new( "#" .. tostring( hex ) )
		end )
	end
	if col then
		self.saved.color = col
		pcall( function()
			local char = self.unit and self.unit.character
			if char and sm.exists( char ) then
				char:setColor( col )
				char.color = col
			end
		end )
	end
end

-- Convert in WHICHEVER env this file is running. rush-base: convertUnit then
-- allies[] row with controlled=true so isAlly sticks here. "already ally" is success.
-- Adopt path uses register() directly so host-env canHackOnto (no beacon row) cannot
-- block the unit flip.
function RfsHackApply.applyInThisEnv( unit, ownerId, opts )
	if not unit then
		return false
	end
	local exists = true
	pcall( function()
		exists = sm.exists( unit ) ~= false
	end )
	if not exists then
		return false
	end
	if type( RfsBotHijack ) ~= "table" then
		return false
	end
	-- 0818-d isAlly can be true from publicData.rfsPlayerAlly alone. Still
	-- register() so THIS env gets displayName / controlled for Orders + nametags.
	opts = opts or {}
	opts.playerAlly = true
	-- Skip convertUnit cap/hackable gates on adopt — register() is the ally row.
	if type( RfsBotHijack.register ) == "function" then
		pcall( RfsBotHijack.register, unit, ownerId or 0, opts )
	end
	if type( RfsBotHijack.isAlly ) == "function" and RfsBotHijack.isAlly( unit ) then
		return true
	end
	if type( RfsBotHijack.convertUnit ) == "function" then
		pcall( function()
			RfsBotHijack.convertUnit( unit, ownerId or 0, opts )
		end )
	end
	if type( RfsBotHijack.isAlly ) == "function" and RfsBotHijack.isAlly( unit ) then
		return true
	end
	return false
end

-- Unit env: the flip rush-base used that Select actually reads — saved.playerAlly,
-- register() in THIS allies[], character:setColor / saved.color, standDown, clear target.
function RfsHackApply.applyOnUnitSelf( self, params )
	if type( self ) ~= "table" or not self.unit then
		return false
	end
	params = params or {}
	self.saved = self.saved or {}
	if params.playerAlly or self.saved.playerAlly then
		self.saved.playerAlly = true
		self.saved.friendly = false
	end
	if not self.saved.playerAlly then
		return false
	end
	if params.mode then
		self.saved.playerAllyMode = params.mode
	end
	if params.beaconKey ~= nil then
		self.saved.playerAllyBeacon = params.beaconKey
	end
	if params.workBeaconKey ~= nil then
		self.saved.playerAllyWorkBeacon = params.workBeaconKey
	end
	if params.hackBeaconKey ~= nil then
		self.saved.rfsHackBeacon = params.hackBeaconKey
	end
	if params.owner ~= nil then
		self.saved.playerAllyOwner = params.owner
	elseif params.ownerId ~= nil then
		self.saved.playerAllyOwner = params.ownerId
	end
	if params.displayName then
		self.saved.rfsDisplayName = params.displayName
	end
	if params.displayIndex ~= nil then
		self.saved.rfsDisplayIndex = tonumber( params.displayIndex )
	end
	if params.customName ~= nil and params.customName ~= false and params.customName ~= "" then
		self.saved.rfsCustomName = tostring( params.customName )
	end
	if params.unitType then
		self.saved.rfsUnitType = params.unitType
	end
	if params.firstSeenTick then
		self.saved.rfsFirstSeenTick = params.firstSeenTick
	end
	if params.allyColor ~= nil then
		self.saved.rfsAllyColor = params.allyColor
	end
	if type( params.rfsOrder ) == "table" then
		self.saved.rfsOrder = params.rfsOrder
	end
	self.isDirty = true
	local opts = {
		mode = params.mode or self.saved.playerAllyMode or "tethered",
		beaconKey = params.beaconKey or self.saved.playerAllyBeacon,
		workBeaconKey = params.workBeaconKey or self.saved.playerAllyWorkBeacon or self.saved.playerAllyBeacon,
		hackBeaconKey = params.hackBeaconKey or self.saved.rfsHackBeacon,
		rfsOrder = params.rfsOrder or self.saved.rfsOrder,
		displayName = params.displayName or self.saved.rfsDisplayName,
		displayIndex = params.displayIndex or self.saved.rfsDisplayIndex,
		customName = params.customName or self.saved.rfsCustomName,
		unitType = params.unitType or self.saved.rfsUnitType,
		firstSeenTick = params.firstSeenTick or self.saved.rfsFirstSeenTick,
		allyColor = params.allyColor or self.saved.rfsAllyColor,
		hijackTicks = params.hijackTicks,
		playerAlly = true,
	}
	local ownerId = params.owner or params.ownerId or self.saved.playerAllyOwner
	local ok = RfsHackApply.applyInThisEnv( self.unit, ownerId, opts )
	if type( RfsBotHijack ) == "table" and type( RfsBotHijack.standDown ) == "function" then
		pcall( RfsBotHijack.standDown, self )
	end
	self.target = nil
	self.lastTargetPosition = nil
	self.eventTarget = nil
	pcall( function()
		sm.event.sendToUnit( self.unit, "sv_e_receiveTarget", { targetCharacter = nil, sendingUnit = self.unit } )
	end )
	pcall( function()
		sm.event.sendToUnit( self.unit, "sv_e_rfsLeaveRaid", {} )
	end )
	local hex = opts.allyColor or self.saved.rfsAllyColor
	if not hex and type( RfsBotHijack ) == "table" and RfsBotHijack.allies then
		pcall( function()
			local rec = RfsBotHijack.allies[tostring( self.unit.id )]
			if rec and rec.allyColor then
				hex = rec.allyColor
			end
		end )
	end
	persistTint( self, hex or "3dff8aff" )
	pcall( function()
		if type( RfsBotHijack ) == "table" and type( RfsBotHijack.pushTag ) == "function" then
			local rec = nil
			pcall( function()
				rec = RfsBotHijack.allies and RfsBotHijack.allies[tostring( self.unit.id )]
			end )
			local info = rec or {
				displayName = opts.displayName or self.saved.rfsDisplayName,
				displayIndex = opts.displayIndex or self.saved.rfsDisplayIndex,
				customName = opts.customName or self.saved.rfsCustomName,
				unitType = opts.unitType or self.saved.rfsUnitType,
			}
			if ( not info.displayName or info.displayName == "" ) and type( RfsBotHijack.shortTypeName ) == "function" then
				local t = nil
				pcall( function()
					t = tostring( self.unit.character:getCharacterType() )
				end )
				info.displayName = RfsBotHijack.shortTypeName( t or info.unitType )
				info.unitType = t or info.unitType
			end
			RfsBotHijack.pushTag( self.unit, RfsBotHijack.identityTagText( info ), "name" )
		end
	end )
	pcall( function()
		local char = self.unit and self.unit.character
		if char and sm.exists( char ) then
			local pd = char.publicData
			if type( pd ) ~= "table" then
				pd = {}
			end
			pd.rfsPlayerAlly = true
			char.publicData = pd
		end
	end )
	pcall( function()
		if self.unit then
			local pd = self.unit.publicData
			if type( pd ) ~= "table" then
				pd = {}
			end
			pd.rfsPlayerAlly = true
			self.unit.publicData = pd
		end
	end )
	-- Color already stuck on 0818-c. Return true so Select takes the ally branch
	-- even when register() could not write THIS env's allies[].
	RfsHackApply.markDone( self.unit, opts.hackBeaconKey or opts.beaconKey )
	return true
end

-- Unit think: adopt only a real device/infected identity. Never default every
-- unit to playerAlly (0818-w autohack: server_onUnitUpdate called this always).
function RfsHackApply.pullPublicOntoUnit( self )
	if type( self ) ~= "table" or not self.unit then
		return false
	end
	self.saved = self.saved or {}
	local ready = false
	if type( RfsHackOrdersIdentity ) == "table" and type( RfsHackOrdersIdentity.localRowReady ) == "function" then
		ready = RfsHackOrdersIdentity.localRowReady( self.unit )
	elseif type( RfsBotHijack ) == "table" and RfsBotHijack.allies then
		local rec = RfsBotHijack.allies[unitKeyOf( self.unit )]
		ready = rec and rec.controlled and rec.displayName and rec.displayName ~= "Bot" and not tostring( rec.displayName ):match( "^Bot%s+%d+$" )
	end
	local params = RfsHackApply.readPublicApply( self.unit )
	if type( params ) ~= "table" and self.saved.playerAlly then
		params = {
			playerAlly = true,
			displayName = self.saved.rfsDisplayName,
			displayIndex = self.saved.rfsDisplayIndex,
			customName = self.saved.rfsCustomName,
			unitType = self.saved.rfsUnitType,
			allyColor = self.saved.rfsAllyColor,
			beaconKey = self.saved.playerAllyBeacon,
			workBeaconKey = self.saved.playerAllyWorkBeacon,
			hackBeaconKey = self.saved.rfsHackBeacon,
			mode = self.saved.playerAllyMode,
			owner = self.saved.playerAllyOwner,
		}
	end
	if type( params ) ~= "table" or not RfsHackApply.payloadHasDevice( params ) then
		local leftover = self.saved.playerAlly and true or false
		pcall( function()
			local char = self.unit.character
			local pd = ( char and sm.exists( char ) and char.publicData ) or self.unit.publicData
			if type( pd ) == "table" and ( pd.rfsPlayerAlly or type( pd.rfsHackApply ) == "table" ) then
				leftover = true
			end
		end )
		if leftover then
			RfsHackApply.wipeFalseAlly( self )
		end
		return false
	end
	if ready then
		if type( RfsHackOrdersIdentity ) == "table" and type( RfsHackOrdersIdentity.pushName ) == "function" then
			pcall( RfsHackOrdersIdentity.pushName, self.unit )
		end
		return true
	end
	params.playerAlly = true
	if not params.unitType then
		pcall( function()
			params.unitType = tostring( self.unit.character:getCharacterType() )
		end )
	end
	return RfsHackApply.applyOnUnitSelf( self, params )
end

local function enqueueWorldApply( unitKey, ownerId, opts )
	if not unitKey or unitKey == "" then
		return
	end
	opts = opts or {}
	pcall( function()
		local q = sm.storage.load( STORAGE_Q )
		if type( q ) ~= "table" then
			q = {}
		end
		q[#q + 1] = {
			unitKey = tostring( unitKey ),
			ownerId = ownerId or 0,
			mode = opts.mode,
			beaconKey = opts.beaconKey,
			workBeaconKey = opts.workBeaconKey,
			hackBeaconKey = opts.hackBeaconKey,
			hijackTicks = opts.hijackTicks,
			playerAlly = true,
			unitType = opts.unitType,
			displayName = opts.displayName,
			displayIndex = opts.displayIndex,
			customName = opts.customName,
			allyColor = opts.allyColor,
		}
		sm.storage.save( STORAGE_Q, q )
	end )
end

-- World/unit env (HijackHost tick): drain beacon-enqueued converts into THIS allies[].
function RfsHackApply.drainStorageQueue( world )
	local q = nil
	pcall( function()
		q = sm.storage.load( STORAGE_Q )
	end )
	if type( q ) ~= "table" or #q == 0 then
		return 0
	end
	local keep = {}
	local n = 0
	for _, row in ipairs( q ) do
		local applied = false
		if type( row ) == "table" and row.unitKey and type( RfsBotHijack ) == "table" then
			local unit = nil
			if type( RfsBotHijack.unitByKey ) == "function" then
				local okU, u = pcall( RfsBotHijack.unitByKey, row.unitKey, world )
				if okU then
					unit = u
				end
			end
			if unit then
				if not RfsHackApply.payloadHasDevice( row ) then
					applied = true
				else
				applied = RfsHackApply.applyInThisEnv( unit, row.ownerId or 0, row ) and true or false
				if applied then
					n = n + 1
					pcall( function()
						sm.event.sendToUnit( unit, "sv_e_rfsApplyHack", row )
					end )
					if type( RfsHackOrdersIdentity ) == "table" and type( RfsHackOrdersIdentity.pushName ) == "function" then
						pcall( RfsHackOrdersIdentity.pushName, unit )
					end
				end
				end
			end
		end
		if not applied and type( row ) == "table" then
			row._tries = ( tonumber( row._tries ) or 0 ) + 1
			if row._tries < 40 then
				keep[#keep + 1] = row
			end
		end
	end
	pcall( function()
		sm.storage.save( STORAGE_Q, keep )
	end )
	return n
end

-- Host/unit env: character.publicData written by the beacon at countdown 0.
function RfsHackApply.consumePublicFlags( world )
	if type( RfsBotHijack ) ~= "table" then
		return 0
	end
	local n = 0
	local list = nil
	if g_unitManager and type( g_unitManager.sv_getAllUnits ) == "function" then
		pcall( function()
			list = g_unitManager:sv_getAllUnits()
		end )
	end
	if type( list ) ~= "table" then
		pcall( function()
			if world ~= nil then
				list = sm.unit.getAllUnits( world )
			else
				list = sm.unit.getAllUnits()
			end
		end )
	end
	if type( list ) ~= "table" then
		return 0
	end
	for _, unit in pairs( list ) do
		if unit and sm.exists( unit ) then
			local oneShot = nil
			local sticky = nil
			pcall( function()
				local char = unit.character
				local pd = ( char and sm.exists( char ) and char.publicData ) or unit.publicData
				if type( pd ) == "table" then
					if type( pd.rfsHackApply ) == "table" then
						oneShot = pd.rfsHackApply
					end
					if type( pd.rfsAllyInfo ) == "table" then
						sticky = pd.rfsAllyInfo
					end
				end
			end )
			local payload = nil
			if type( oneShot ) == "table" and RfsHackApply.payloadHasDevice( oneShot ) then
				payload = oneShot
			elseif type( sticky ) == "table" and RfsHackApply.payloadHasDevice( sticky ) then
				payload = sticky
			else
				-- Leftover rfsPlayerAlly / empty one-shot: do not convert; wipe the flag.
				if type( oneShot ) == "table" or type( sticky ) == "table" then
					pcall( RfsHackApply.clearPublicApply, unit, false )
				else
					pcall( function()
						local char = unit.character
						local pd = ( char and sm.exists( char ) and char.publicData ) or unit.publicData
						if type( pd ) == "table" and pd.rfsPlayerAlly and not RfsHackApply.payloadHasDevice( pd.rfsAllyInfo ) then
							RfsHackApply.clearPublicApply( unit, false )
						end
					end )
				end
			end
			if type( payload ) == "table" then
				payload.playerAlly = true
				local ready = false
				if type( RfsHackOrdersIdentity ) == "table" and type( RfsHackOrdersIdentity.localRowReady ) == "function" then
					ready = RfsHackOrdersIdentity.localRowReady( unit )
				end
				-- Device one-shot always apply. Sticky identity only if THIS env still lacks Type N.
				if oneShot or not ready then
					if not payload.unitType then
						pcall( function()
							payload.unitType = tostring( unit.character:getCharacterType() )
						end )
					end
					if RfsHackApply.applyInThisEnv( unit, payload.ownerId or payload.owner or 0, payload ) then
						n = n + 1
					end
					pcall( function()
						sm.event.sendToUnit( unit, "sv_e_rfsApplyHack", payload )
					end )
					if type( RfsHackOrdersIdentity ) == "table" and type( RfsHackOrdersIdentity.pushName ) == "function" then
						pcall( RfsHackOrdersIdentity.pushName, unit )
					end
				end
				if oneShot then
					RfsHackApply.clearPublicApply( unit, true )
				end
			end
		end
	end
	return n
end

local function fireUnitAndWorldApply( unit, ownerId, opts, uk )
	local payload = {
		owner = ownerId,
		ownerId = ownerId,
		mode = opts.mode,
		beaconKey = opts.beaconKey,
		workBeaconKey = opts.workBeaconKey,
		hackBeaconKey = opts.hackBeaconKey,
		hijackTicks = opts.hijackTicks,
		playerAlly = true,
		unitType = opts.unitType,
		displayName = opts.displayName,
		displayIndex = opts.displayIndex,
		customName = opts.customName,
		allyColor = opts.allyColor,
	}
	pcall( function()
		sm.event.sendToUnit( unit, "sv_e_rfsApplyHack", payload )
	end )
	pcall( function()
		sm.event.sendToUnit( unit, "sv_e_rfsIdentity", payload )
	end )
	pcall( function()
		sm.event.sendToGame( "sv_rfs_hackApply", {
			unitKey = uk,
			ownerId = ownerId,
			mode = opts.mode,
			beaconKey = opts.beaconKey,
			workBeaconKey = opts.workBeaconKey,
			hackBeaconKey = opts.hackBeaconKey,
			hijackTicks = opts.hijackTicks,
			playerAlly = true,
			unitType = opts.unitType,
			displayName = opts.displayName,
			displayIndex = opts.displayIndex,
			customName = opts.customName,
			allyColor = opts.allyColor,
		} )
	end )
	enqueueWorldApply( uk, ownerId, opts )
end

-- Beacon-env: remaining countdown is 0. rush-base always called convertUnit then
-- cleared the tag. Local isAlly/isDone is NOT the unit flip — still sendToUnit.
-- Spend once after the first finish only (not every tick while remainTicks<=0).
-- Returns "ok" | "nobat" | "cap" | "retry"
function RfsHackApply.tryFinish( unit, rec, bkey, need )
	if not rec or not unit then
		return "retry"
	end
	local exists = true
	pcall( function()
		exists = sm.exists( unit ) ~= false
	end )
	if not exists then
		return "retry"
	end
	local alreadyAlly = type( RfsBotHijack ) == "table" and type( RfsBotHijack.isAlly ) == "function" and RfsBotHijack.isAlly( unit )
	local alreadyDone = RfsHackApply.isDone( unit )
	if not alreadyAlly then
		if type( RfsBotHijack ) == "table" and type( RfsBotHijack.canHackOnto ) == "function" then
			local okC, capOk = pcall( RfsBotHijack.canHackOnto, bkey, unit )
			if okC and not capOk then
				return "cap"
			end
		end
		local canPay = true
		if type( rec.canSpendOne ) == "function" then
			local okCan, resultCan = pcall( rec.canSpendOne )
			canPay = okCan and resultCan and true or false
		end
		if not canPay then
			return "nobat"
		end
	end
	local opts = RfsHackApply.optsFrom( rec, bkey, need, unit )
	local ownerId = rec.ownerId or 0
	local uk = unitKeyOf( unit )

	-- Cross-sandbox: unit think reads character.publicData even if sendToUnit drops.
	RfsHackApply.writePublicApply( unit, ownerId, opts )
	-- Rush-base: always convertUnit at zero (ignore return; "already ally" is success).
	if type( RfsBotHijack ) == "table" and type( RfsBotHijack.convertUnit ) == "function" then
		pcall( RfsBotHijack.convertUnit, unit, ownerId, opts )
	end
	pcall( RfsHackApply.applyInThisEnv, unit, ownerId, opts )
	-- Unit env: saved.playerAlly + register + standDown + saved.color (Select's table).
	fireUnitAndWorldApply( unit, ownerId, opts, uk )
	RfsHackApply.markDone( unit, bkey )

	if not alreadyDone and type( rec.spendOne ) == "function" then
		pcall( rec.spendOne )
	end
	-- One convert attempt: clear HACK tag. tickAuto must not start another countdown.
	return "ok"
end

-- World/unit env: identity RPC must register() here or Select never sees isAlly.
function RfsHackApply.adoptOnUnit( self, params )
	return RfsHackApply.applyOnUnitSelf( self, params )
end

-- World/unit env: saved.playerAlly without a local allies[] row is a sandbox miss,
-- not "beacon dropped them". Re-register tethered AND infected.
function RfsHackApply.restoreFromSaved( self )
	if type( self ) ~= "table" or not self.unit or type( self.saved ) ~= "table" then
		return false
	end
	if self.saved.rfsHackable == false then
		return false
	end
	if type( RfsBotHijack ) == "table" and type( RfsBotHijack.isHackable ) == "function" and not RfsBotHijack.isHackable( self.unit ) then
		return false
	end
	if self.saved.playerAlly then
		self.saved.friendly = false
		local adopt = {
			playerAlly = true,
			owner = self.saved.playerAllyOwner,
			mode = self.saved.playerAllyMode or "tethered",
			beaconKey = self.saved.playerAllyBeacon,
			workBeaconKey = self.saved.playerAllyWorkBeacon or self.saved.playerAllyBeacon,
			hackBeaconKey = self.saved.rfsHackBeacon,
			rfsOrder = self.saved.rfsOrder,
			displayName = self.saved.rfsDisplayName,
			displayIndex = self.saved.rfsDisplayIndex,
			customName = self.saved.rfsCustomName,
			unitType = self.saved.rfsUnitType,
			firstSeenTick = self.saved.rfsFirstSeenTick,
			allyColor = self.saved.rfsAllyColor,
		}
		if not RfsHackApply.payloadHasDevice( adopt ) then
			return RfsHackApply.wipeFalseAlly( self )
		end
		return RfsHackApply.applyOnUnitSelf( self, adopt )
	end
	return RfsHackApply.pullPublicOntoUnit( self )
end

print( "[RFS] RfsHackApply loaded (0818-x device convert)" )

pcall( function()
	if type( RfsHackOrdersIdentity ) ~= "table" then
		dofile( "$CONTENT_DATA/Scripts/game/RfsHackOrdersIdentity.lua" )
	end
end )
