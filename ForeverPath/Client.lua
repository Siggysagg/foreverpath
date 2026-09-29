local _, NS = ...
local C = { requested = {}, errors = {}, rejectedEvents = {} }
NS.Client = C
-- Maps client inventory types to logical slots for the pure comparison engine.
local slots = {
    INVTYPE_HEAD = {{ key = "head", index = 1 }}, INVTYPE_NECK = {{ key = "neck", index = 2 }},
    INVTYPE_SHOULDER = {{ key = "shoulder", index = 3 }}, INVTYPE_CHEST = {{ key = "chest", index = 5 }},
    INVTYPE_ROBE = {{ key = "chest", index = 5 }}, INVTYPE_WAIST = {{ key = "waist", index = 6 }},
    INVTYPE_LEGS = {{ key = "legs", index = 7 }}, INVTYPE_FEET = {{ key = "feet", index = 8 }},
    INVTYPE_WRIST = {{ key = "wrist", index = 9 }}, INVTYPE_HAND = {{ key = "hands", index = 10 }},
    INVTYPE_FINGER = {{ key = "finger1", index = 11 }, { key = "finger2", index = 12 }},
    INVTYPE_CLOAK = {{ key = "back", index = 15 }},
    INVTYPE_WEAPONMAINHAND = {{ key = "mainhand", index = 16 }},
    INVTYPE_WEAPONOFFHAND = {{ key = "offhand", index = 17 }},
    INVTYPE_2HWEAPON = {{ key = "mainhand", index = 16 }, { key = "offhand", index = 17 }, replaces = "all"},
}
local function api(namespace, method, fallback)
    return namespace and namespace[method] or _G[fallback or method]
end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local result = { pcall(fn, ...) }
    if not result[1] then C.errors.last = tostring(result[2]); return nil end
    -- Keep tuple holes by returning individual positions used by this adapter.
    return result[2],result[3],result[4],result[5],result[6],result[7],result[8],result[9],result[10],result[11],result[12],result[13]
end
function C.Request(itemID)
    if not itemID or C.requested[itemID] then return end
    C.requested[itemID] = true
    call(api(C_Item, "RequestLoadItemDataByID"), itemID)
end
function C.ReadItem(link)
    if not link then return nil end
    local name, _, _, _, _, _, _, _, location, texture = call(api(C_Item, "GetItemInfo"), link)
    local stats = call(api(C_Item, "GetItemStats"), link)
    if not name or type(stats) ~= "table" then
        C.Request(tonumber(string.match(link, "item:(%d+)")))
        return nil
    end
    return { name = name, location = location, texture = texture, stats = stats, link = link }
end
function C.Snapshot()
    local version, build, _, interface = call(GetBuildInfo)
    local _, class = call(UnitClass, "player")
    local state = { level = call(UnitLevel, "player") or 0, class = class, zone = call(GetRealZoneText) or "Unknown zone",
        version = version or "unknown", build = build or "unknown", interface = interface or 0,
        questCount = 0, rows = {} }
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local _, quests = call(C_QuestLog.GetNumQuestLogEntries)
        state.questCount = quests or 0
    elseif GetNumQuestLogEntries then
        local _, quests = call(GetNumQuestLogEntries)
        state.questCount = quests or 0
    end
    state.questTitle = NS.dialogOpen and call(GetTitleText) or nil
    state.questID = NS.dialogOpen and call(GetQuestID) or nil
    local profile = NS.Engine.ProfileFor(state.class, state.level, NS.settings.spec, NS.settings.profile)
    state.profileLabel = profile and (profile.title or profile.label or profile.spec) or nil
    if not NS.dialogOpen then return C.NextQuests(state, profile) end
    if not GetQuestItemLink or not GetInventoryItemLink or not GetInventoryItemID then
        state.message = "Required item APIs unavailable. Open Diagnostics."; return state
    end
    if not profile then state.message = "Choose a stat profile below to compare rewards."; return state end
    state.mode = "rewards"
    for _, rewardType in ipairs({"choice", "reward"}) do
        local countAPI = rewardType == "choice" and GetNumQuestChoices or GetNumQuestRewards
        local count = call(countAPI) or 0
        for index = 1, math.min(count, 24) do
            local link = call(GetQuestItemLink, rewardType, index)
            local name, texture, _, _, usable, itemID = call(GetQuestItemInfo, rewardType, index)
            local row = { id = string.format("quest:%s:%s:%d:%s", tostring(state.questID or state.questTitle or "unknown"), rewardType, index, tostring(itemID or link or name or "unknown")),
                title = name or "Loading reward...", texture = texture, link = link, kind = rewardType, questID = state.questID, slotIndexes = {},
                verdict = "Inspect", reasons = { "Effects and set bonuses are not scored." } }
            local item = C.ReadItem(link)
            if not item then
                C.Request(itemID)
                row.verdict = "Waiting for data"
            elseif usable == false then
                row.verdict = "Cannot use"
            elseif not slots[item.location] then
                row.verdict = "Manual comparison"
                row.reasons[1] = "Trinkets and non-gear need manual inspection."
            elseif not next(item.stats) then
                row.verdict = "No stat comparison"
            else
                local equipped, rewardSlots, ready = {}, {}, true
                for _, target in ipairs(slots[item.location]) do
                    rewardSlots[#rewardSlots + 1] = target.key
                    row.slotIndexes[#row.slotIndexes + 1] = target.index
                    local existingLink = call(GetInventoryItemLink, "player", target.index)
                    local existingID = call(GetInventoryItemID, "player", target.index)
                    local existing = existingLink and C.ReadItem(existingLink)
                    if (existingID or existingLink) and not existing then
                        ready, equipped[target.key] = false, false
                        C.Request(existingID)
                    elseif existing then
                        equipped[target.key] = existing.stats
                    end
                end
                local comparison = NS.Engine.CompareReward({ slots = rewardSlots, replaces = slots[item.location].replaces, stats = item.stats }, equipped, profile)
                if comparison.confidence == "high" then
                    row.delta, row.verdict = comparison.delta, comparison.verdict
                    row.reasons[2] = string.format("%+.1f weighted points vs equipped slot", row.delta)
                    if usable == nil then row.reasons[3] = "Usability not confirmed by client" end
                elseif not ready then
                    row.verdict = "Waiting for equipped data"
                else
                    row.verdict = "No stat comparison"
                    row.reasons[1] = "Stats are incomplete; no recommendation is guessed."
                end
            end
            state.rows[#state.rows + 1] = row
        end
    end
    table.sort(state.rows, function(a,b)
        if a.delta == b.delta then return a.title < b.title end
        return (a.delta or -math.huge) > (b.delta or -math.huge)
    end)
    if #state.rows == 0 then state.message = "No item rewards exposed by this quest dialogue." end
    return state
end
-- Zones with an imported quest database (addon/ForeverPath/Data/*.lua).
local QUEST_DATA = { "Durotar" }

-- Live "what should I do now": imported quests filtered and ranked for this character.
function C.NextQuests(state, profile)
    state.mode = "next"
    local data = {}
    for _, name in ipairs(QUEST_DATA) do
        for id, node in pairs(NS[name] or {}) do data[id] = node end
    end
    local isDone = api(C_QuestLog, "IsQuestFlaggedCompleted")
    local logIndex = api(C_QuestLog, "GetLogIndexForQuestID", "GetQuestLogIndexByID")
    local titleFor = api(C_QuestLog, "GetTitleForQuestID")
    local instant = api(C_Item, "GetItemInfoInstant")
    local player = { level = state.level, class = state.class, faction = call(UnitFactionGroup, "player"),
        completed = {}, inLog = {}, equipped = {}, itemSlots = {} }
    for _, node in pairs(data) do
        local questID = node.questID
        if questID then
            if call(isDone, questID) then player.completed[questID] = true end
            local index = call(logIndex, questID)
            if index and index ~= 0 then player.inLog[questID] = true end
            for _, reward in ipairs(node.rewards or {}) do
                if reward.itemID and player.itemSlots[reward.itemID] == nil then
                    local _, _, _, equipLoc = call(instant, reward.itemID)
                    local targets = slots[equipLoc]
                    if targets then
                        local keys = {}
                        for _, target in ipairs(targets) do keys[#keys + 1] = target.key end
                        player.itemSlots[reward.itemID] = { slots = keys, replaces = targets.replaces }
                    end
                end
            end
        end
    end
    for _, targets in pairs(slots) do
        for _, target in ipairs(targets) do
            if player.equipped[target.key] == nil then
                local link = call(GetInventoryItemLink, "player", target.index)
                if link then
                    local item = C.ReadItem(link)
                    player.equipped[target.key] = item and item.stats or false
                end
            end
        end
    end
    local rows = profile and NS.Engine.NextQuests(data, player, profile, NS.settings.goal) or {}
    for _, row in ipairs(rows) do
        local title = call(titleFor, row.questID)
        if type(title) == "string" and title ~= "" then row.title = title end
        row.slotIndexes = {}
    end
    state.rows = rows
    if #rows == 0 then
        state.message = next(data) and "No quests from the ForeverPath database fit your character right now. Coverage so far: Horde, Durotar levels 1-12. Open a quest dialogue to compare its rewards."
            or "No quest database installed. Open a quest dialogue to compare its rewards."
    end
    return state
end

function C.Diagnostics()
    local version, build, _, interface = call(GetBuildInfo)
    local lines = { "ForeverPath 0.2.2-alpha", "Client: " .. tostring(version) .. " build " .. tostring(build),
        "Interface: " .. tostring(interface), "Mode: " .. (NS.demo and "synthetic demo" or "live"),
        "Profile: " .. tostring(NS.settings.profile or "none"), "Expected interface: 16001 (unverified in game)",
        "API availability:" }
    local checks = {
        { "C_Item.GetItemInfo / GetItemInfo", api(C_Item, "GetItemInfo") },
        { "C_Item.GetItemStats / GetItemStats", api(C_Item, "GetItemStats") },
        { "RequestLoadItemDataByID", api(C_Item, "RequestLoadItemDataByID") },
        { "GetQuestItemLink", GetQuestItemLink }, { "GetQuestItemInfo", GetQuestItemInfo },
        { "GetNumQuestChoices", GetNumQuestChoices }, { "GetNumQuestRewards", GetNumQuestRewards },
        { "GetInventoryItemLink", GetInventoryItemLink }, { "GetInventoryItemID", GetInventoryItemID },
        { "C_Timer.After", C_Timer and C_Timer.After },
    }
    for _, entry in ipairs(checks) do lines[#lines+1] = entry[1] .. ": " .. (type(entry[2]) == "function" and "yes" or "missing") end
    lines[#lines+1] = "Unavailable events: " .. table.concat(C.rejectedEvents, ", ")
    lines[#lines+1] = "Last adapter error: " .. tostring(C.errors.last or "none")
    lines[#lines+1] = "Live quest/crafting route database: not installed in this prototype"
    lines[#lines+1] = "No player name, realm or account ID collected. Review error text before sharing."
    return table.concat(lines, "\n")
end
