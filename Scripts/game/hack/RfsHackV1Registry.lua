-- RfsHackV1Registry.lua
-- VOLATILE: ally names — single source of truth (unit publicData.rfsHackV1, written once).

RfsHackV1Registry = RfsHackV1Registry or {}

RfsHackV1Registry._seq = RfsHackV1Registry._seq or {}

function RfsHackV1Registry.unitKey( unit )
	if not unit then
		return nil
	end
	local id = nil
	pcall( function()
		id = tostring( unit.id )
	end )
	if id and id ~= "" then
		return id
	end
	return nil
end

function RfsHackV1Registry.read( unit )
	if not unit then
		return nil
	end
	local blob = nil
	pcall( function()
		local char = unit.character
		if char and sm.exists( char ) then
			local pd = char.publicData
			if type( pd ) == "table" and type( pd.rfsHackV1 ) == "table" then
				blob = pd.rfsHackV1
			end
		end
	end )
	if blob then
		return blob
	end
	pcall( function()
		local pd = unit.publicData
		if type( pd ) == "table" and type( pd.rfsHackV1 ) == "table" then
			blob = pd.rfsHackV1
		end
	end )
	return blob
end

function RfsHackV1Registry.isAlly( unit )
	local blob = RfsHackV1Registry.read( unit )
	return blob ~= nil and blob.ally == true
end

function RfsHackV1Registry.write( unit, blob )
	if not unit or type( blob ) ~= "table" then
		return
	end
	local function stamp( pd )
		if type( pd ) ~= "table" then
			pd = {}
		end
		pd.rfsHackV1 = blob
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

function RfsHackV1Registry.writeOnce( unit, blob )
	if RfsHackV1Registry.read( unit ) then
		return
	end
	RfsHackV1Registry.write( unit, blob )
end

function RfsHackV1Registry.clear( unit )
	if not unit then
		return
	end
	local function wipe( pd )
		if type( pd ) == "table" then
			pd.rfsHackV1 = nil
		end
		return pd
	end
	pcall( function()
		local char = unit.character
		if char and sm.exists( char ) then
			char.publicData = wipe( char.publicData )
		end
	end )
	pcall( function()
		unit.publicData = wipe( unit.publicData )
	end )
end

function RfsHackV1Registry.observeName( name )
	name = tostring( name or "" )
	local label, n = string.match( name, "^(%S+)%s+(%d+)$" )
	if not label or not n then
		return
	end
	n = tonumber( n ) or 0
	local seq = RfsHackV1Registry._seq
	if n > ( seq[label] or 0 ) then
		seq[label] = n
	end
end

function RfsHackV1Registry.allocName( typeLabel )
	typeLabel = tostring( typeLabel or "Bot" )
	if typeLabel == "" then
		typeLabel = "Bot"
	end
	local seq = RfsHackV1Registry._seq
	seq[typeLabel] = ( seq[typeLabel] or 0 ) + 1
	return typeLabel .. " " .. tostring( seq[typeLabel] )
end

function RfsHackV1Registry.allyCount( beaconKey )
	beaconKey = tostring( beaconKey or "" )
	local n = 0
	local units = nil
	pcall( function()
		units = sm.unit.getAllUnits()
	end )
	if type( units ) ~= "table" then
		return 0
	end
	for i = 1, #units do
		local u = units[i]
		if u and sm.exists( u ) then
			local blob = RfsHackV1Registry.read( u )
			if blob and blob.ally and tostring( blob.beaconKey or "" ) == beaconKey then
				n = n + 1
			end
		end
	end
	return n
end

-- Valid living allies for this beacon (dead units omitted).
function RfsHackV1Registry.listNames( beaconKey, world )
	local rows = RfsHackV1Registry.listAllies( beaconKey, world )
	local names = {}
	for i = 1, #rows do
		local blob = RfsHackV1Registry.read( rows[i].unit )
		local n = blob and ( blob.name or blob.typeLabel ) or nil
		if n and n ~= "" then
			names[#names + 1] = tostring( n )
		end
	end
	return names
end

function RfsHackV1Registry.listAllies( beaconKey, world )
	beaconKey = tostring( beaconKey or "" )
	local units = nil
	if world then
		pcall( function()
			units = sm.unit.getAllUnits( world )
		end )
	end
	if type( units ) ~= "table" then
		pcall( function()
			units = sm.unit.getAllUnits()
		end )
	end
	local rows = {}
	if type( units ) ~= "table" then
		return rows
	end
	for i = 1, #units do
		local u = units[i]
		if u and sm.exists( u ) then
			local char = u.character
			if char and sm.exists( char ) then
				local blob = RfsHackV1Registry.read( u )
				if blob and blob.ally and tostring( blob.beaconKey or "" ) == beaconKey then
					rows[#rows + 1] = {
						unit = u,
						character = char,
					}
				end
			end
		end
	end
	return rows
end
