local addonName, NS = ...
NS.dialogOpen, NS.tipRevision = false, 0
local pending, initialized, lastEventRefresh = false, false, nil
local function message(text) print("|cff42dbbdForeverPath:|r " .. text) end
function NS.Refresh()
    if not initialized then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local state
    local ok, result = pcall(NS.Client.Snapshot)
    if ok then state = result else
        NS.Client.errors.last = tostring(result)
        state = { rows = {}, message = "Client data unavailable. Copy Diagnostics for investigation." }
    end
    state.updated = date and date("%H:%M:%S") or nil
    local dismissed = NS.settings.dismissedTip
    if type(dismissed) == "table" and state.rows then
        local visible = {}
        for _, row in ipairs(state.rows) do
            if row.id ~= dismissed.id then visible[#visible + 1] = row end
        end
        state.rows = visible
    end
    NS.UI.Render(state)
    if state.mode ~= "rewards" then NS.Nav.Follow(state.rows) end
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
-- Imported spec weights win over the generic profiles, so cycle specs when the class has them.
function NS.CycleProfile()
    local _, class = UnitClass("player")
    local specs = NS.Engine.SpecsFor(class, UnitLevel("player"))
    if #specs > 0 then
        local current = 1
        for i, spec in ipairs(specs) do
            if string.lower(spec) == string.lower(NS.settings.spec or "") then current = i end
        end
        NS.settings.spec = specs[current % #specs + 1]
    else
        local nextProfile = { strength = "agility", agility = "intellect", intellect = "strength" }
        NS.settings.profile = nextProfile[NS.settings.profile] or "strength"
    end
    NS.Refresh()
end
function NS.SetSpec(spec)
    if type(spec) ~= "string" or spec == "" then return false end
    NS.settings.spec = spec
    NS.Refresh()
    return true
end
function NS.SetStyle(style)
    if not NS.Route.styles[style] then return false end
    NS.settings.style = style
    NS.Refresh()
    return true
end
function NS.CycleStyle()
    local order = NS.Route.order
    for i, style in ipairs(order) do
        if style == NS.settings.style then return NS.SetStyle(order[i % #order + 1]) end
    end
    NS.SetStyle("balanced")
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
        pcall(NS.MigrateSettings, NS.settings)
        if not NS.Engine.profiles[NS.settings.profile] then NS.settings.profile = nil end
        if not NS.Route.styles[NS.settings.style] then NS.settings.style = "balanced" end
        NS.settings.goal = nil
        if type(NS.settings.tipThrottleSeconds) ~= "number" or NS.settings.tipThrottleSeconds < 0 then NS.settings.tipThrottleSeconds = 10 end
        initialized = true
        for _, name in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_LEVEL_UP","PLAYER_EQUIPMENT_CHANGED","BAG_UPDATE_DELAYED",
            "QUEST_DETAIL","QUEST_PROGRESS","QUEST_COMPLETE","QUEST_FINISHED","QUEST_LOG_UPDATE","QUEST_ACCEPTED","QUEST_TURNED_IN",
            "GET_ITEM_INFO_RECEIVED","ITEM_DATA_LOAD_RESULT","PLAYER_REGEN_ENABLED","ZONE_CHANGED_NEW_AREA","QUEST_DATA_LOAD_RESULT"}) do register(name) end
        message("Loaded. /fp shows what to do next; open a quest dialogue to compare rewards.")
        NS.Route.SetCustomRoute(NS.settings.customRouteText)
        NS.UI.Minimap()
        NS.QueueRefresh()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        if not NS.settings.setupDone then NS.UI.Setup() end
        if NS.settings.compact ~= false then NS.UI.Compact(true) end
    end
    if event == "QUEST_DETAIL" or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
        NS.dialogOpen = true; NS.Client.requested = {}
    elseif event == "QUEST_FINISHED" then NS.dialogOpen = false; NS.Client.requested = {}
    elseif event == "PLAYER_LEVEL_UP" or event == "PLAYER_EQUIPMENT_CHANGED" then
        invalidateDismissedTip(event, arg1)
    elseif event == "QUEST_LOG_UPDATE" then
        invalidateDismissedTip(event, arg1)
        NS.Client.MarkLogDirty()  -- one log reread replaces the full per-quest scan (#101)
    elseif event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN" then
        invalidateDismissedTip(event, arg1)
        NS.Client.MarkQuestDirty(arg1)  -- arg1 is the quest ID; only it is rechecked (#101)
        if event == "QUEST_TURNED_IN" and NS.UI and NS.UI.Celebrate then NS.UI.Celebrate(arg1) end
    elseif event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
        if not NS.Client.requested[arg1] then return end
    end
    NS.QueueRefresh()
end)
-- Save-format versioning (spor G): every older SavedVariables blob becomes version 1
-- on load; future breaking changes run ordered migration steps from here. Idempotent
-- and guarded — a failed migration never blocks loading.
NS.SETTINGS_VERSION = 1

function NS.MigrateSettings(settings)
    if type(settings) ~= "table" then return settings end
    local version = tonumber(settings.version) or 0
    -- Migration steps run in order; each bumps the stored version. None yet (v1 is current).
    -- if version < 1 then ... ; settings.version = 1 ; version = 1 end
    settings.version = NS.SETTINGS_VERSION
    return settings
end

function NS.ImportRoute(text)
    text = type(text) == "string" and #text > 0 and text or nil
    NS.settings.customRouteText = text
    NS.Route.SetCustomRoute(text)
    local guides, steps = NS.Route.CustomRouteStats()
    local status = text and (guides .. " guide(s), " .. steps .. " step(s) imported - your route wins") or "Custom route removed"
    if NS.UI.routeWin then NS.UI.routeWin.status:SetText(status) end
    message(status)
    NS.Refresh()
end
function NS.ResetPositions()
    NS.settings.position, NS.settings.compactPosition, NS.settings.arrowPosition = nil, nil, nil
    NS.settings.minimapAngle = nil
    NS.UI.Create(); NS.UI.frame:ClearAllPoints(); NS.UI.frame:SetPoint("CENTER")
    if NS.UI.hud then NS.UI.Restore(NS.UI.hud, "compactPosition", "TOP", Minimap or UIParent, Minimap and "BOTTOM" or "TOP", 0, Minimap and -18 or -120) end
    if NS.Nav.frame then NS.UI.Restore(NS.Nav.frame, "arrowPosition", "TOP", UIParent, "TOP", 0, -200) end
    if NS.UI.minimap then NS.UI.PlaceMinimap() end
    NS.Refresh()
end
SLASH_FOREVERPATH1, SLASH_FOREVERPATH2 = "/fp", "/foreverpath"
SlashCmdList.FOREVERPATH = function(input)
    if not initialized then return end
    NS.UI.Create()
    local command, argument = string.lower(input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    if command == "diag" then NS.UI.Diagnostics()
    elseif command == "setup" then NS.UI.Setup()
    elseif command == "settings" then NS.UI.Settings()
    elseif command == "route" then NS.UI.RouteImport()
    elseif command == "stats" then
        local s = NS.Client.session or {}
        local stats = NS.Engine.SessionStats(s, GetTime and GetTime() or 0)
        message(string.format("This session: %d XP/h, %d quest(s) done%s",
            stats.xph or 0, stats.quests or 0, stats.toLevelText and (", " .. stats.toLevelText .. " to level") or ""))
    elseif command == "opacity" then
        local percent = tonumber(argument)
        if percent and percent >= 30 and percent <= 100 then NS.UI.SetOpacity(percent / 100); message("Opacity: " .. percent .. "%")
        else message("Opacity must be 30-100 (percent).") end
    elseif command == "arrow" then
        NS.settings.arrow = NS.settings.arrow == false
        message(NS.settings.arrow and "Arrow on: it follows your next step." or "Arrow off.")
        NS.Refresh()
    elseif command == "compact" then NS.UI.ToggleCompact()
    elseif command == "reset" then
        NS.ResetPositions()
    elseif command == "style" then
        if NS.SetStyle(argument) then message("Playstyle: " .. NS.Route.labels[argument]) else message("Playstyle must be speed, balanced, gear, story or dungeon.") end
    elseif command == "spec" then
        if NS.SetSpec(argument) then message("Spec: " .. argument) else message("Spec must not be empty.") end
    elseif command == "help" then message("/fp | setup | settings | route | stats | diag | compact | arrow | opacity <30-100> | reset | style <speed|balanced|gear|story|dungeon> | spec <name>. Scores omit effects and set bonuses; ambiguous one-hand weapons need manual comparison.")
    else NS.UI.Toggle() end
end
