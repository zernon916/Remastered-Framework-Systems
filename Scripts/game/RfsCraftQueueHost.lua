-- RfsCraftQueueHost.lua — ScriptableObject: inventory gains → craft queue.
-- VOLATILE.

RfsCraftQueueHost = class()
RfsCraftQueueHost.isSaveObject = true

function RfsCraftQueueHost.server_onCreate( self )
	_G.g_rfsCraftQueueHost = self
	pcall( function()
		if QuestManager and QuestEvent and QuestManager.Sv_SubscribeEvent then
			QuestManager.Sv_SubscribeEvent( QuestEvent.InventoryChanges, self.scriptableObject, "sv_e_inventoryChanges" )
		end
	end )
	print( "[RFS] RfsCraftQueueHost subscribed InventoryChanges" )
end

function RfsCraftQueueHost.server_onDestroy( self )
	pcall( function()
		if QuestManager and QuestManager.Sv_UnsubscribeAllEvents then
			QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )
		end
	end )
	if _G.g_rfsCraftQueueHost == self then
		_G.g_rfsCraftQueueHost = nil
	end
end

local function playerFromContainer( container )
	if not container then
		return nil
	end
	local found
	pcall( function()
		for _, player in ipairs( sm.player.getAllPlayers() ) do
			local inv = player:getInventory()
			if inv and inv == container then
				found = player
				break
			end
			-- Some builds compare via getId
			if inv and container.getId and inv.getId and inv:getId() == container:getId() then
				found = player
				break
			end
		end
	end )
	return found
end

function RfsCraftQueueHost.sv_e_inventoryChanges( self, data )
	if type( RfsCraftQueue ) ~= "table" then
		return
	end
	local params = data and data.params or data
	if type( params ) ~= "table" then
		return
	end
	local container = params.container
	local changes = params.changes
	if type( changes ) ~= "table" then
		return
	end
	local player = playerFromContainer( container )
	if not player then
		return
	end
	for _, ch in ipairs( changes ) do
		if type( ch ) == "table" then
			local diff = tonumber( ch.difference ) or 0
			if diff > 0 then
				local uuidStr = tostring( ch.uuid or "" )
				-- Uuid userdata sometimes stringifies with braces; normalize
				uuidStr = uuidStr:gsub( "[{}]", "" )
				if uuidStr ~= "" then
					RfsCraftQueue.onInventoryGain( player, uuidStr, diff )
				end
			end
		end
	end
end

print( "[RFS] RfsCraftQueueHost class loaded" )
