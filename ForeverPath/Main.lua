local addonName, NS = ...
NS.demo, NS.dialogOpen, NS.tipRevision = false, false, 0
local pending, initialized, lastEventRefresh = false, false, nil
local function message(text) print("|cff42dbbdForeverPath:|r " .. text) end
function NS.Refresh()
    if not initialized then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local state
    if NS.demo then
        local s = NS.Demo.state
        s.profile, s.goal = NS.settings.profile or "strength", NS.settings.goal
        state = { rows = NS.Engine.Rank(NS.Demo.graph,NS.Demo.targets,s) }
    else
        local ok, result = pcall(NS.Client.Snapshot)
        if ok then state = result else
            NS.Client.errors.last = tostring(result)
            state = { rows = {}, message = "Client data unavailable. Copy Diagnostics for investigation." }
        end
    end
    local dismissed = NS.settings.dismissedTip
    if type(dismissed) == "table" and state.rows then
        local visible = {}
        for _, row in ipairs(state.rows) do
            if row.id ~= dismissed.id then visible[#visible + 1] = row end
        end
        state.rows = visible
    end
    NS.UI.Render(state)
end
function NS.DismissTip(row)
    if type(row) == "string" then row = { id = row } end
    if type(row) ~= "table" or type(row.id) ~= "string" or not NS.settings then return end
    NS.settings.dismissedTip = { id = row.id, questID = row.questID, slotIndexes = row.slotIndexes }
    NS.Refresh()
end
local function invalidateDismissedTip(event, arg1)
    local dismissed = NS.settings.dismissedTip
    if type(dismissed) ~= "table" then return end
    if event == "PLAYER_LEVEL_UP" then
        NS.settings.dismissedTip = nil
    elseif event == "PLAYER_EQUIPMENT_CHANGED" and type(arg1) == "number" and type(dismissed.slotIndexes) == "table" then
        for _, slot in ipairs(dismissed.slotIndexes) do
            if slot == arg1 then NS.settings.dismissedTip = nil; return end
        end
    elseif (event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN") and dismissed.questID == arg1 then
        NS.settings.dismissedTip = nil
    end
end
function NS.QueueRefresh()
    if pending or not initialized then return end
    local seconds = tonumber(NS.settings.tipThrottleSeconds) or 10
    if seconds < 0 then seconds = 10 end
    local now = GetTime and GetTime() or 0
    local delay = lastEventRefresh and math.max(0, seconds - (now - lastEventRefresh)) or 0.2
    pending = true
    local function refresh()
        pending = false
        lastEventRefresh = GetTime and GetTime() or now
        NS.Refresh()
    end
    if C_Timer and C_Timer.After then C_Timer.After(delay, refresh) else refresh() end
end
function NS.SetDemo(value)
    NS.demo = value
    if value and not NS.settings.profile then NS.settings.profile = "strength" end
    NS.Refresh()
end
function NS.CycleProfile()
    local nextProfile = { strength = "agility", agility = "intellect", intellect = "strength" }
    NS.settings.profile = nextProfile[NS.settings.profile] or "strength"
    NS.Refresh()
end
function NS.SetSpec(spec)
    if type(spec) ~= "string" or spec == "" then return false end
    NS.settings.spec = spec
    NS.Refresh()
    return true
end
function NS.SetGoal(goal)
    if not NS.Engine.goals[goal] then return false end
    NS.settings.goal = goal
    NS.Refresh()
    return true
end
function NS.CycleGoal()
    local nextGoal = { balanced = "leveling", leveling = "gear", gear = "professions", professions = "balanced" }
    NS.SetGoal(nextGoal[NS.settings.goal] or "balanced")
end
local events = CreateFrame("Frame")
local function register(event)
    local ok = pcall(events.RegisterEvent,events,event)
    if not ok then NS.Client.rejectedEvents[#NS.Client.rejectedEvents+1] = event end
end
register("ADDON_LOADED")
events:SetScript("OnEvent",function(_,event,arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        ForeverPathDB = type(ForeverPathDB) == "table" and ForeverPathDB or {}
        NS.settings = ForeverPathDB
        if not NS.Engine.profiles[NS.settings.profile] then NS.settings.profile = nil end
        if not NS.Engine.goals[NS.settings.goal] then NS.settings.goal = "balanced" end
        if type(NS.settings.tipThrottleSeconds) ~= "number" or NS.settings.tipThrottleSeconds < 0 then NS.settings.tipThrottleSeconds = 10 end
        initialized = true
        for _, name in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_LEVEL_UP","PLAYER_EQUIPMENT_CHANGED","BAG_UPDATE_DELAYED",
            "QUEST_DETAIL","QUEST_PROGRESS","QUEST_COMPLETE","QUEST_FINISHED","QUEST_LOG_UPDATE","QUEST_ACCEPTED","QUEST_TURNED_IN",
            "GET_ITEM_INFO_RECEIVED","ITEM_DATA_LOAD_RESULT","PLAYER_REGEN_ENABLED","ZONE_CHANGED_NEW_AREA"}) do register(name) end
        message("Loaded. /fp shows what to do next; open a quest dialogue to compare rewards.")
        NS.QueueRefresh()
        return
    end
    if event == "QUEST_DETAIL" or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
        NS.dialogOpen = true; NS.Client.requested = {}
    elseif event == "QUEST_FINISHED" then NS.dialogOpen = false; NS.Client.requested = {}
    elseif event == "PLAYER_LEVEL_UP" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "QUEST_LOG_UPDATE" or event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN" then
        invalidateDismissedTip(event, arg1)
    elseif event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
        if not NS.Client.requested[arg1] then return end
    end
    NS.QueueRefresh()
end)
SLASH_FOREVERPATH1, SLASH_FOREVERPATH2 = "/fp", "/foreverpath"
SlashCmdList.FOREVERPATH = function(input)
    if not initialized then return end
    NS.UI.Create()
    local command, argument = string.lower(input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    if command == "demo" then NS.SetDemo(true); NS.UI.frame:Show()
    elseif command == "live" then NS.SetDemo(false); NS.UI.frame:Show()
    elseif command == "diag" then NS.UI.Diagnostics()
    elseif command == "compact" then NS.UI.ToggleCompact()
    elseif command == "reset" then NS.settings.position = nil; NS.UI.Create(); NS.UI.frame:ClearAllPoints(); NS.UI.frame:SetPoint("CENTER")
    elseif command == "goal" then
        if NS.SetGoal(argument) then message("Goal: " .. argument) else message("Goal must be leveling, gear, professions or balanced.") end
    elseif command == "spec" then
        if NS.SetSpec(argument) then message("Spec: " .. argument) else message("Spec must not be empty.") end
    elseif command == "help" then message("/fp | demo | live | diag | compact | reset | goal <leveling|gear|professions|balanced> | spec <name>. Demo data is fictional; live scores omit effects and set bonuses; ambiguous one-hand weapons need manual comparison.")
    else NS.UI.Toggle() end
end
