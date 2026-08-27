-- RfsCraftQueue.lua — per-player craft planner queue + quest-tracker paint.
-- VOLATILE. Handheld Recipe Viewer queues unlocked crafts; inventory gains
-- advance counts. Max 6 lines on the vanilla Quest Tracker HUD.

RfsCraftQueue = RfsCraftQueue or {}

local QUEST_NAME = "quest_rfs_craft_queue"
local QUEST_TITLE = "Craft Queue"
local MAX_TRACKER_LINES = 6
local VIEWER_UUID = "f0e9d8c7-b6a5-4321-9c8d-7e6f5a4b3c2d"

RfsCraftQueue.QUEST_NAME = QUEST_NAME
RfsCraftQueue.VIEWER_UUID = VIEWER_UUID

-- playerId -> { crafts = { { itemId, qty, have } }, needs = { [uuid] = { need, have, name } } }
local queues = {}

local function playerIdOf( player )
	if not player then
		return nil
	end
	local id
	pcall( function()
		id = player:getId()
	end )
	return id
end

local function itemDisplayName( uuidStr )
	local title
	pcall( function()
		local u = sm.uuid.new( uuidStr )
		title = sm.shape.getShapeTitle( u )
	end )
	if type( title ) == "string" and title ~= "" and title ~= "not found" then
		return title
	end
	pcall( function()
		local u = sm.uuid.new( uuidStr )
		if sm.item and sm.item.getDisplayName then
			title = sm.item.getDisplayName( u )
		end
	end )
	if type( title ) == "string" and title ~= "" then
		return title
	end
	return tostring( uuidStr ):sub( 1, 8 )
end

local function findRecipe( itemId )
	itemId = tostring( itemId )
	local sets = g_craftingRecipeSets or {}
	for _, set in pairs( sets ) do
		if type( set ) == "table" and type( set.recipes ) == "table" then
			local r = set.recipes[itemId]
			if type( r ) == "table" then
				return r
			end
		end
		if type( set ) == "table" and type( set.recipesByIndex ) == "table" then
			for _, r in ipairs( set.recipesByIndex ) do
				if type( r ) == "table" and tostring( r.itemId ) == itemId then
					return r
				end
			end
		end
	end
	return nil
end

function RfsCraftQueue.findRecipe( itemId )
	return findRecipe( itemId )
end

-- Craftbot filter types: tool / block / interactive / part / consumable
function RfsCraftQueue.itemCategory( itemId )
	itemId = tostring( itemId or "" )
	if itemId == "" then
		return "part"
	end
	local u
	pcall( function() u = sm.uuid.new( itemId ) end )
	if not u then
		return "part"
	end
	-- Prefer C++ icon type (same signal Craftbot tabs use).
	local iconType
	pcall( function()
		local _r, _g, _n, _k, t = sm.gui.getItemIconFromUuid( u )
		if type( t ) == "string" and t ~= "" then
			iconType = string.lower( t )
		end
	end )
	if iconType == "tool" or iconType == "block" or iconType == "interactive"
		or iconType == "part" or iconType == "consumable" then
		return iconType
	end
	local isTool, isBlock, isJoint = false, false, false
	pcall( function() isTool = sm.item.isTool( u ) == true end )
	if isTool then
		return "tool"
	end
	pcall( function() isBlock = sm.item.isBlock( u ) == true end )
	if isBlock then
		return "block"
	end
	local edible
	pcall( function()
		if sm.item.getEdible then
			edible = sm.item.getEdible( u )
		end
	end )
	if edible ~= nil then
		return "consumable"
	end
	local plantable
	pcall( function()
		if sm.item.getPlantable then
			plantable = sm.item.getPlantable( u )
		end
	end )
	if plantable ~= nil then
		return "consumable"
	end
	-- Interactables / joints → interactive; remaining parts stay "part".
	pcall( function() isJoint = sm.item.isJoint( u ) == true end )
	if isJoint then
		return "part"
	end
	local hasInteractable = false
	pcall( function()
		if sm.item.getFeatureData then
			local fd = sm.item.getFeatureData( u )
			if type( fd ) == "table" and ( fd.interactable or fd.scripted ) then
				hasInteractable = true
			end
		end
	end )
	if hasInteractable then
		return "interactive"
	end
	-- Shape with interactable component often still reports as part via isPart.
	local isPart = false
	pcall( function() isPart = sm.item.isPart( u ) == true end )
	if isPart then
		-- Heuristic: survival interactive titles often live under interactive filter.
		-- Without icon type, default remaining non-block non-tool to part (matches Craftbot leftovers).
		return "part"
	end
	return "part"
end

-- True when this uuid has a Craftbot (or RFS craftbot extras) recipe row.
local function isCraftbotRecipeId( itemId )
	itemId = tostring( itemId or "" )
	if itemId == "" then
		return false
	end
	local sets = g_craftingRecipeSets or {}
	for setName, set in pairs( sets ) do
		local name = tostring( setName or "" )
		local isCraftbot = ( name == "craftbot_rfs_mods" ) or ( string.match( name, "^craftbot_" ) ~= nil )
		if isCraftbot and type( set ) == "table" then
			if type( set.recipes ) == "table" and set.recipes[itemId] then
				return true
			end
			if type( set.recipesByIndex ) == "table" then
				for _, r in ipairs( set.recipesByIndex ) do
					if type( r ) == "table" and tostring( r.itemId ) == itemId then
						return true
					end
				end
			end
		end
	end
	return false
end

-- Match what Craftbot shows as craftable: RecipeManager unlock, or RFS always-available.
function RfsCraftQueue.isRecipeKnown( itemId )
	itemId = tostring( itemId or "" )
	if itemId == "" or itemId == VIEWER_UUID then
		return false
	end
	if not isCraftbotRecipeId( itemId ) then
		return false
	end
	local locks = _G.g_rfsCraftbotSchematicLocks or {}
	local always = _G.g_rfsCraftbotAlwaysAvailable or {}
	if always[itemId] and not locks[itemId] then
		return true
	end
	local unlocked = false
	pcall( function()
		if RecipeManager and RecipeManager.Cl_IsUnlocked then
			unlocked = RecipeManager.Cl_IsUnlocked( itemId ) == true
		end
	end )
	if unlocked then
		return true
	end
	pcall( function()
		if RecipeManager and RecipeManager.Sv_IsUnlocked then
			unlocked = RecipeManager.Sv_IsUnlocked( itemId ) == true
		end
	end )
	return unlocked == true
end

function RfsCraftQueue.listKnownRecipes()
	local out = {}
	local seen = {}
	local sets = g_craftingRecipeSets or {}
	-- Craftbot sets only (vanilla craftbot_* + RFS craftbot_rfs_mods). Skip cookbot/workbench/etc.
	local ordered = {}
	for setName, set in pairs( sets ) do
		local name = tostring( setName or "" )
		if name == "craftbot_rfs_mods" or string.match( name, "^craftbot_" ) then
			ordered[#ordered + 1] = { name = name, set = set }
		end
	end
	table.sort( ordered, function( a, b )
		return a.name < b.name
	end )
	for _, entry in ipairs( ordered ) do
		local list = entry.set and entry.set.recipesByIndex
		if type( list ) == "table" then
			for _, r in ipairs( list ) do
				if type( r ) == "table" and r.itemId then
					local id = tostring( r.itemId )
					if not seen[id] and RfsCraftQueue.isRecipeKnown( id ) then
						seen[id] = true
						out[#out + 1] = {
							itemId = id,
							name = itemDisplayName( id ),
							quantity = tonumber( r.quantity ) or 1,
							category = RfsCraftQueue.itemCategory( id ),
						}
					end
				end
			end
		end
	end
	table.sort( out, function( a, b )
		return tostring( a.name ) < tostring( b.name )
	end )
	return out
end

local function countInContainer( container, uuidStr )
	local n = 0
	pcall( function()
		local u = sm.uuid.new( uuidStr )
		n = sm.container.totalQuantity( container, u ) or 0
	end )
	return tonumber( n ) or 0
end

local function playerInventory( player )
	local inv
	pcall( function()
		inv = player:getInventory()
	end )
	return inv
end

local function rebuildNeeds( q, player )
	q.needs = {}
	for _, craft in ipairs( q.crafts ) do
		local recipe = findRecipe( craft.itemId )
		if recipe then
			local qty = tonumber( craft.qty ) or 1
			for _, ing in ipairs( recipe.ingredientList or {} ) do
				local iid = tostring( ing.itemId )
				local need = ( tonumber( ing.quantity ) or 1 ) * qty
				local row = q.needs[iid]
				if not row then
					row = { need = 0, have = 0, name = itemDisplayName( iid ) }
					q.needs[iid] = row
				end
				row.need = row.need + need
			end
		end
	end
	local inv = player and playerInventory( player )
	if inv then
		for iid, row in pairs( q.needs ) do
			row.have = math.min( row.need, countInContainer( inv, iid ) )
		end
		for _, craft in ipairs( q.crafts ) do
			local have = countInContainer( inv, craft.itemId )
			craft.have = math.min( tonumber( craft.qty ) or 1, have )
		end
	end
end

function RfsCraftQueue.get( player )
	local id = playerIdOf( player )
	if not id then
		return nil
	end
	return queues[id]
end

function RfsCraftQueue.snapshot( player )
	local q = RfsCraftQueue.get( player )
	if not q then
		return { crafts = {}, needs = {}, lines = {} }
	end
	return {
		crafts = q.crafts,
		needs = q.needs,
		lines = RfsCraftQueue.buildTrackerLines( q ),
	}
end

function RfsCraftQueue.buildTrackerLines( q )
	local lines = {}
	if not q then
		return lines
	end
	-- Craft targets first
	for i, craft in ipairs( q.crafts or {} ) do
		local need = tonumber( craft.qty ) or 1
		local have = tonumber( craft.have ) or 0
		lines[#lines + 1] = {
			name = "craft_" .. i,
			text = string.format( "%d/%d Craft: %s", have, need, itemDisplayName( craft.itemId ) ),
			complete = have >= need,
			index = #lines + 1,
			prio = 0,
			remain = need - have,
		}
	end
	-- Ingredients by remaining desc
	local ings = {}
	for iid, row in pairs( q.needs or {} ) do
		ings[#ings + 1] = {
			iid = iid,
			need = row.need,
			have = row.have,
			name = row.name or itemDisplayName( iid ),
			remain = math.max( 0, ( row.need or 0 ) - ( row.have or 0 ) ),
		}
	end
	table.sort( ings, function( a, b )
		if a.remain ~= b.remain then
			return a.remain > b.remain
		end
		return tostring( a.name ) < tostring( b.name )
	end )
	local room = MAX_TRACKER_LINES - #lines
	local shown = 0
	local hidden = 0
	for _, ing in ipairs( ings ) do
		if room > 1 or ( room == 1 and shown + 1 >= #ings - hidden ) then
			if shown < room then
				lines[#lines + 1] = {
					name = "ing_" .. ing.iid,
					text = string.format( "%d/%d %s", ing.have, ing.need, ing.name ),
					complete = ing.have >= ing.need,
					index = #lines + 1,
				}
				shown = shown + 1
			else
				hidden = hidden + 1
			end
		else
			hidden = hidden + 1
		end
	end
	if hidden > 0 and #lines < MAX_TRACKER_LINES then
		lines[#lines + 1] = {
			name = "more",
			text = string.format( "+%d more materials…", hidden ),
			complete = false,
			index = #lines + 1,
		}
	elseif hidden > 0 and #lines >= MAX_TRACKER_LINES then
		-- Replace last ingredient with summary if needed
		lines[MAX_TRACKER_LINES] = {
			name = "more",
			text = string.format( "+%d more materials…", hidden + 1 ),
			complete = false,
			index = MAX_TRACKER_LINES,
		}
	end
	while #lines > MAX_TRACKER_LINES do
		table.remove( lines )
	end
	return lines
end

function RfsCraftQueue.add( player, itemId, qty )
	itemId = tostring( itemId or "" )
	qty = math.max( 1, math.floor( tonumber( qty ) or 1 ) )
	if not player or itemId == "" then
		return false, "bad args"
	end
	if not RfsCraftQueue.isRecipeKnown( itemId ) then
		return false, "recipe locked"
	end
	if not findRecipe( itemId ) then
		return false, "no recipe"
	end
	local id = playerIdOf( player )
	if not id then
		return false, "no player"
	end
	local q = queues[id]
	if not q then
		q = { crafts = {}, needs = {} }
		queues[id] = q
	end
	local merged = false
	for _, craft in ipairs( q.crafts ) do
		if craft.itemId == itemId then
			craft.qty = ( tonumber( craft.qty ) or 1 ) + qty
			merged = true
			break
		end
	end
	if not merged then
		q.crafts[#q.crafts + 1] = { itemId = itemId, qty = qty, have = 0 }
	end
	rebuildNeeds( q, player )
	RfsCraftQueue._notifyClients( player )
	return true
end

-- Absolute quantity (0 removes the craft line). Used by Recipe Viewer +/−.
function RfsCraftQueue.set( player, itemId, qty )
	itemId = tostring( itemId or "" )
	qty = math.floor( tonumber( qty ) or 0 )
	if not player or itemId == "" then
		return false, "bad args"
	end
	if qty <= 0 then
		local id = playerIdOf( player )
		local q = id and queues[id]
		if not q then
			return true
		end
		local keep = {}
		for _, craft in ipairs( q.crafts ) do
			if craft.itemId ~= itemId then
				keep[#keep + 1] = craft
			end
		end
		q.crafts = keep
		if #q.crafts == 0 then
			queues[id] = nil
		else
			rebuildNeeds( q, player )
		end
		RfsCraftQueue._notifyClients( player )
		return true
	end
	if not RfsCraftQueue.isRecipeKnown( itemId ) then
		return false, "recipe locked"
	end
	if not findRecipe( itemId ) then
		return false, "no recipe"
	end
	local id = playerIdOf( player )
	if not id then
		return false, "no player"
	end
	local q = queues[id]
	if not q then
		q = { crafts = {}, needs = {} }
		queues[id] = q
	end
	local found = false
	for _, craft in ipairs( q.crafts ) do
		if craft.itemId == itemId then
			craft.qty = qty
			found = true
			break
		end
	end
	if not found then
		q.crafts[#q.crafts + 1] = { itemId = itemId, qty = qty, have = 0 }
	end
	rebuildNeeds( q, player )
	RfsCraftQueue._notifyClients( player )
	return true
end

function RfsCraftQueue.clear( player )
	local id = playerIdOf( player )
	if not id then
		return false
	end
	queues[id] = nil
	RfsCraftQueue._notifyClients( player )
	return true
end

function RfsCraftQueue.onInventoryGain( player, uuidStr, diff )
	diff = tonumber( diff ) or 0
	if diff <= 0 or not player then
		return
	end
	uuidStr = tostring( uuidStr or "" )
	local q = RfsCraftQueue.get( player )
	if not q then
		return
	end
	local changed = false
	local row = q.needs[uuidStr]
	if row and row.have < row.need then
		row.have = math.min( row.need, row.have + diff )
		changed = true
	end
	for _, craft in ipairs( q.crafts ) do
		if craft.itemId == uuidStr then
			local need = tonumber( craft.qty ) or 1
			local have = tonumber( craft.have ) or 0
			if have < need then
				craft.have = math.min( need, have + diff )
				changed = true
			end
		end
	end
	if changed then
		-- Drop finished crafts
		local keep = {}
		for _, craft in ipairs( q.crafts ) do
			if ( tonumber( craft.have ) or 0 ) < ( tonumber( craft.qty ) or 1 ) then
				keep[#keep + 1] = craft
			end
		end
		q.crafts = keep
		if #q.crafts == 0 then
			queues[playerIdOf( player )] = nil
		else
			rebuildNeeds( q, player )
		end
		RfsCraftQueue._notifyClients( player )
	end
end

function RfsCraftQueue._notifyClients( player )
	local game = g_survivalDev or nil
	-- Prefer SurvivalGame / RFS game instance
	if type( _G.g_rfsGame ) == "table" and _G.g_rfsGame.network then
		game = _G.g_rfsGame
	end
	local snap = RfsCraftQueue.snapshot( player )
	if game and game.network and player then
		pcall( function()
			game.network:sendToClient( player, "cl_rfs_craftQueueSync", snap )
		end )
	elseif game and game.network then
		pcall( function()
			game.network:sendToClients( "cl_rfs_craftQueueSync", snap )
		end )
	end
	-- Client-local paint if we're already on client
	pcall( function()
		RfsCraftQueue.cl_applyTracker( snap )
	end )
end

function RfsCraftQueue.cl_applyTracker( snap )
	snap = snap or {}
	local lines = snap.lines or {}
	local hud
	pcall( function()
		if g_questManagerClient and g_questManagerClient.cl then
			hud = g_questManagerClient.cl.trackerHud
		end
	end )
	if not hud then
		return
	end
	if not lines or #lines == 0 then
		pcall( function()
			hud:untrackQuest( QUEST_NAME )
		end )
		return
	end
	pcall( function()
		hud:trackQuest( QUEST_NAME, QUEST_TITLE, false, lines, nil )
	end )
end

function RfsCraftQueue.installTrackerWrap()
	if RfsCraftQueue._wrapped then
		return
	end
	if type( QuestManager ) ~= "table" or type( QuestManager.cl_updateQuestTracker ) ~= "function" then
		return
	end
	local prev = QuestManager.cl_updateQuestTracker
	function QuestManager.cl_updateQuestTracker( self )
		prev( self )
		local snap = _G.g_rfsCraftQueueClientSnap
		if type( snap ) == "table" then
			RfsCraftQueue.cl_applyTracker( snap )
		end
	end
	RfsCraftQueue._wrapped = true
	print( "[RFS] RfsCraftQueue tracker wrap installed" )
end

print( "[RFS] RfsCraftQueue loaded" )
