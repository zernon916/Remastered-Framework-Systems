-- RfsQuest.lua — thin quest API for RFS + guest Blocks & Parts mods.
-- Wraps Survival QuestManager. Custom quest *scripts* still live as Survival-style
-- ScriptableObjects; this module is the safe entry point for activate / complete /
-- query / event subscribe from your mod or from RFS itself.

RfsQuest = RfsQuest or {}

RfsQuest._modHooks = RfsQuest._modHooks or {
	onActivate = {},
	onComplete = {},
}

local function qmReady()
	return type( QuestManager ) == "table"
end

---------------------------------------------------------------------------
-- Query
---------------------------------------------------------------------------

function RfsQuest.isActive( questName )
	if not qmReady() or not questName then
		return false
	end
	local ok, v = pcall( QuestManager.Sv_IsQuestActive, questName )
	return ok and v and true or false
end

function RfsQuest.isComplete( questName )
	if not qmReady() or not questName then
		return false
	end
	local ok, v = pcall( QuestManager.Sv_IsQuestComplete, questName )
	return ok and v and true or false
end

function RfsQuest.getStage( questName )
	if not qmReady() or not questName then
		return nil
	end
	local ok, v = pcall( QuestManager.Sv_GetQuestStage, questName )
	if ok then
		return v
	end
	return nil
end

function RfsQuest.getActive()
	if not qmReady() then
		return {}
	end
	local ok, list = pcall( QuestManager.Sv_GetActiveQuests )
	if ok and type( list ) == "table" then
		return list
	end
	return {}
end

---------------------------------------------------------------------------
-- Activate / complete (server)
---------------------------------------------------------------------------

function RfsQuest.activate( questName, additionalParams, hide )
	if not qmReady() or not questName then
		return false, "no QuestManager"
	end
	local ok, err = pcall( QuestManager.Sv_ActivateQuest, questName, additionalParams, hide )
	if not ok then
		return false, tostring( err )
	end
	RfsQuest._fire( "onActivate", questName )
	return true
end

function RfsQuest.tryActivate( questName, hide )
	if not qmReady() or not questName then
		return false
	end
	local ok = pcall( QuestManager.Sv_TryActivateQuest, questName, hide )
	if ok then
		RfsQuest._fire( "onActivate", questName )
	end
	return ok and true or false
end

function RfsQuest.complete( questName, hideCompletion )
	if not qmReady() or not questName then
		return false, "no QuestManager"
	end
	local ok, err = pcall( QuestManager.Sv_CompleteQuest, questName, hideCompletion )
	if not ok then
		return false, tostring( err )
	end
	RfsQuest._fire( "onComplete", questName )
	return true
end

function RfsQuest.abandon( questName )
	if not qmReady() or not questName then
		return false
	end
	return pcall( QuestManager.Sv_AbandonQuest, questName ) and true or false
end

---------------------------------------------------------------------------
-- Events / activators (pass-through)
---------------------------------------------------------------------------

function RfsQuest.subscribeEvent( event, subscriber, methodName )
	if not qmReady() then
		return false
	end
	return pcall( QuestManager.Sv_SubscribeEvent, event, subscriber, methodName )
end

function RfsQuest.unsubscribeEvent( event, subscriber )
	if not qmReady() then
		return false
	end
	return pcall( QuestManager.Sv_UnsubscribeEvent, event, subscriber )
end

function RfsQuest.sendEvent( event, params )
	if not qmReady() then
		return false
	end
	return pcall( QuestManager.Sv_SendEvent, event, params )
end

function RfsQuest.registerActivator( questName, activator )
	if not qmReady() then
		return false
	end
	return pcall( QuestManager.Sv_RegisterQuestActivator, questName, activator )
end

---------------------------------------------------------------------------
-- Mod hooks (simple callbacks — no ScriptableObject required)
---------------------------------------------------------------------------

-- fn( questName )
function RfsQuest.onActivate( fn )
	if type( fn ) == "function" then
		RfsQuest._modHooks.onActivate[#RfsQuest._modHooks.onActivate + 1] = fn
	end
end

function RfsQuest.onComplete( fn )
	if type( fn ) == "function" then
		RfsQuest._modHooks.onComplete[#RfsQuest._modHooks.onComplete + 1] = fn
	end
end

function RfsQuest._fire( kind, questName )
	local list = RfsQuest._modHooks[kind]
	if type( list ) ~= "table" then
		return
	end
	for _, fn in ipairs( list ) do
		pcall( fn, questName )
	end
end

-- Optional: load Quests/rfs_quests.json from a B&P mod (metadata only — names/notes).
-- Full Survival quests still need a quest ScriptableObject registered by the game.
function RfsQuest.loadModQuestMeta( contentLocalId )
	if not contentLocalId then
		return nil
	end
	local path = "$CONTENT_" .. tostring( contentLocalId ) .. "/Quests/rfs_quests.json"
	local ok, data = pcall( sm.json.open, path )
	if ok and type( data ) == "table" then
		return data
	end
	return nil
end

_G.RfsQuest = RfsQuest
