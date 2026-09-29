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
-- Objective progress ("Kolkar 3/5") for a quest in the log. Classic Era 1.15 documents
-- C_QuestLog.GetQuestObjectives; on a client without it this returns nil and cards stay as they are.
function C.Objectives(questID)
    local get = api(C_QuestLog, "GetQuestObjectives")
    if type(get) ~= "function" or not questID then return nil end
    local ok, objectives = pcall(get, questID)
    if not ok or type(objectives) ~= "table" then
        if not ok then C.errors.last = tostring(objectives) end
        return nil
    end
    return #objectives > 0 and objectives or nil
end
-- Pure: one readable line from client objective records. Counted goals show "text done/required";
-- goals without a count (progress bars, flags) show their text alone.
function C.FormatObjectives(objectives)
    if type(objectives) ~= "table" then return nil end
    local parts = {}
    for _, objective in ipairs(objectives) do
        if type(objective) == "table" and objective.text then
            local required = tonumber(objective.numRequired) or 0
            if required > 0 then
                parts[#parts + 1] = string.format("%s %d/%d", tostring(objective.text), tonumber(objective.numFulfilled) or 0, required)
            else
                parts[#parts + 1] = tostring(objective.text)
            end
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end
-- Texture for a reward we only know by item ID (imported data); asks the client to load
-- missing item data so GET_ITEM_INFO_RECEIVED triggers the next refresh with the texture.
function C.ItemTexture(itemID)
    if not itemID then return nil end
    local _, _, _, _, _, _, _, _, _, texture = call(api(C_Item, "GetItemInfo"), itemID)
    if type(texture) ~= "string" and type(texture) ~= "number" then C.Request(itemID) end
    return texture or nil
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
    C.profileLabel = state.profileLabel
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

-- Event-driven quest-log cache (#101): completed/inLog/ready are built by ONE full scan per
-- session and then updated from events only. Main.lua marks single quests dirty on
-- QUEST_ACCEPTED/QUEST_TURNED_IN and the whole log on QUEST_LOG_UPDATE, so a plain refresh
-- after the build makes no per-quest client calls at all.
C.questState = { completed = {}, inLog = {}, ready = {} }
-- API-call counters since load, shown in Diagnostics (PERF-01 acceptance).
C.stats = { fullScans = 0, flagged = 0, logIndex = 0, logReads = 0 }

function C.MarkQuestDirty(questID)
    if type(questID) ~= "number" then return end
    local state = C.questState
    state.dirty = state.dirty or {}
    state.dirty[questID] = true
end

function C.MarkLogDirty()
    C.questState.dirtyLog = true
end

-- Quest IDs currently in the log, read from the log itself instead of probing every imported
-- quest. Prefers C_QuestLog.GetQuestIDForLogIndex, falls back to the Classic global
-- GetQuestLogTitle (title, level, tag, isHeader, collapsed, isComplete, frequency, questID).
-- Returns nil when this client offers no way to enumerate the log.
local function loggedQuestIDs()
    local byIndex = api(C_QuestLog, "GetQuestIDForLogIndex")
    local logTitle = api(C_QuestLog, "GetQuestLogTitle")
    if type(byIndex) ~= "function" and type(logTitle) ~= "function" then return nil end
    local _, count = call(C_QuestLog and C_QuestLog.GetNumQuestLogEntries or GetNumQuestLogEntries)
    local ids = {}
    for index = 1, tonumber(count) or 0 do
        local questID = tonumber(call(byIndex, index))
        if not questID and type(logTitle) == "function" then
            local _, _, _, isHeader, _, _, _, fromTitle = call(logTitle, index)
            if isHeader ~= true then questID = tonumber(fromTitle) end
        end
        if questID and questID ~= 0 then ids[#ids + 1] = questID end
    end
    return ids
end

-- One quest re-checked end to end: flagged state, log membership and readiness.
local function recheckQuest(state, questID, isDone, logIndex, isReady)
    C.stats.flagged = C.stats.flagged + 1
    state.completed[questID] = call(isDone, questID) and true or nil
    C.stats.logIndex = C.stats.logIndex + 1
    local index = call(logIndex, questID)
    if index and index ~= 0 then
        state.inLog[questID] = true
        state.ready[questID] = call(isReady, questID) and true or nil
    else
        state.inLog[questID], state.ready[questID] = nil, nil
    end
end

-- Brings the cache up to date before rows are planned. known maps imported quest IDs to true;
-- quests outside the database are ignored exactly like a full scan would ignore them.
function C.SyncQuestState(known, isDone, logIndex, isReady)
    local state = C.questState
    if not state.built then  -- Session build: today's logic, run once.
        C.stats.fullScans = C.stats.fullScans + 1
        for questID in pairs(known) do
            C.stats.flagged = C.stats.flagged + 1
            if call(isDone, questID) then state.completed[questID] = true end
            C.stats.logIndex = C.stats.logIndex + 1
            local index = call(logIndex, questID)
            if index and index ~= 0 then
                state.inLog[questID] = true
                if call(isReady, questID) then state.ready[questID] = true end
            end
        end
        state.built, state.dirty, state.dirtyLog = true, nil, nil
        return
    end
    for questID in pairs(state.dirty or {}) do  -- QUEST_ACCEPTED/QUEST_TURNED_IN payloads
        if known[questID] then recheckQuest(state, questID, isDone, logIndex, isReady) end
    end
    state.dirty = nil
    if not state.dirtyLog then return end
    state.dirtyLog = nil  -- QUEST_LOG_UPDATE: rebuild inLog/ready from the log itself.
    local ids, seen = loggedQuestIDs(), {}
    C.stats.logReads = C.stats.logReads + 1
    if ids then
        for _, questID in ipairs(ids) do
            if known[questID] then
                seen[questID] = true
                state.inLog[questID] = true
                state.ready[questID] = call(isReady, questID) and true or nil
            end
        end
    else
        -- Client without log enumeration: probe imported quests like the build scan,
        -- but leave IsQuestFlaggedCompleted out of it.
        for questID in pairs(known) do
            C.stats.logIndex = C.stats.logIndex + 1
            local index = call(logIndex, questID)
            if index and index ~= 0 then
                seen[questID] = true
                state.inLog[questID] = true
                state.ready[questID] = call(isReady, questID) and true or nil
            end
        end
    end
    -- A quest that left the log since the last look may have been turned in without an
    -- event; that is the only case where a log reread consults IsQuestFlaggedCompleted.
    for questID in pairs(state.inLog) do
        if not seen[questID] then
            state.inLog[questID], state.ready[questID] = nil, nil
            C.stats.flagged = C.stats.flagged + 1
            if call(isDone, questID) then state.completed[questID] = true end
        end
    end
end

-- Live "what should I do now": imported quests filtered and ranked for this character.
function C.NextQuests(state, profile)
    state.mode = "next"
    local data, known = {}, {}
    for zoneName, zone in pairs(NS.Quests or {}) do
        for id, node in pairs(zone) do node.zone = node.zone or zoneName; data[id] = node end
    end
    for _, node in pairs(data) do if node.questID then known[node.questID] = true end end
    local logIndex = api(C_QuestLog, "GetLogIndexForQuestID", "GetQuestLogIndexByID")
    local titleFor = api(C_QuestLog, "GetTitleForQuestID")
    local instant = api(C_Item, "GetItemInfoInstant")
    local isReady = api(C_QuestLog, "IsComplete", "IsQuestComplete")
    local mapInfo = C_Map and C_Map.GetMapInfo
    local _, race = call(UnitRace, "player")
    C.SyncQuestState(known, api(C_QuestLog, "IsQuestFlaggedCompleted"), logIndex, isReady)
    local player = { level = state.level, class = state.class, faction = call(UnitFactionGroup, "player"), race = race,
        mapID = C_Map and call(C_Map.GetBestMapForUnit, "player") or nil, zone = state.zone,
        completed = C.questState.completed, inLog = C.questState.inLog, ready = C.questState.ready,
        equipped = {}, itemSlots = {} }
    player.zoneName = function(map)
        local info = call(mapInfo, map)
        return type(info) == "table" and info.name or nil
    end
    for _, node in pairs(data) do
        local questID = node.questID
        if questID then
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
    local rows = profile and NS.Route.Plan(data, NS.Routes, player, profile, NS.settings.style) or {}
    state.upgrades = profile and NS.Engine.BestUpgrades(NS.Route.lastAvailable or {}, player, profile) or {}
    local verb = { accept = "Accept: ", turnin = "Turn in: ", complete = "Complete: " }
    for _, row in ipairs(rows) do
        local title = call(titleFor, row.questID)
        if type(title) == "string" and title ~= "" then row.title = (verb[row.action] or "") .. title
        else call(api(C_QuestLog, "RequestLoadQuestByID"), row.questID) end  -- QUEST_DATA_LOAD_RESULT refreshes
        row.objectives = C.Objectives(row.questID)
        if row.objectives then
            local line = C.FormatObjectives(row.objectives)
            if line then table.insert(row.reasons, 1, line) end
        end
        row.iconItemID = row.bestReward and row.bestReward.itemID or nil
        row.icon = row.iconItemID and C.ItemTexture(row.iconItemID) or row.texture or nil
        row.slotIndexes = {}
    end
    state.rows = rows
    if #rows == 0 then
        state.message = next(data) and "No route step or quest in this zone fits your character right now (route: RestedXP guides, quests: AllTheThings). Open a quest dialogue to compare its rewards."
            or "No quest database installed. Open a quest dialogue to compare its rewards."
    end
    return state
end

function C.Diagnostics()
    local version, build, _, interface = call(GetBuildInfo)
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local lines = { "ForeverPath " .. tostring(meta and meta("ForeverPath", "Version") or "?"), "Client: " .. tostring(version) .. " build " .. tostring(build),
        "Interface: " .. tostring(interface),
        "Profile: " .. tostring(C.profileLabel or NS.settings.spec or NS.settings.profile or "automatic"), "Expected interface: 16001 (unverified in game)",
        "API availability:" }
    local checks = {
        { "C_Item.GetItemInfo / GetItemInfo", api(C_Item, "GetItemInfo") },
        { "C_Item.GetItemStats / GetItemStats", api(C_Item, "GetItemStats") },
        { "RequestLoadItemDataByID", api(C_Item, "RequestLoadItemDataByID") },
        { "GetQuestItemLink", GetQuestItemLink }, { "GetQuestItemInfo", GetQuestItemInfo },
        { "GetNumQuestChoices", GetNumQuestChoices }, { "GetNumQuestRewards", GetNumQuestRewards },
        { "GetInventoryItemLink", GetInventoryItemLink }, { "GetInventoryItemID", GetInventoryItemID },
        { "C_QuestLog.GetQuestObjectives", api(C_QuestLog, "GetQuestObjectives") },
        { "C_Timer.After", C_Timer and C_Timer.After },
    }
    for _, entry in ipairs(checks) do lines[#lines+1] = entry[1] .. ": " .. (type(entry[2]) == "function" and "yes" or "missing") end
    lines[#lines+1] = "Unavailable events: " .. table.concat(C.rejectedEvents, ", ")
    lines[#lines+1] = "Last adapter error: " .. tostring(C.errors.last or "none")
    lines[#lines+1] = "Quest database: AllTheThings Forever zones (Data/Quests.lua)"
    lines[#lines+1] = string.format("Quest state cache: %d full scan(s) this session, %d flagged + %d log-index calls, %d log read(s) since load",
        C.stats.fullScans, C.stats.flagged, C.stats.logIndex, C.stats.logReads)
    if NS.UI and NS.UI.CompactDiagnostics then lines[#lines+1] = NS.UI.CompactDiagnostics() end
    lines[#lines+1] = "No player name, realm or account ID collected. Review error text before sharing."
    return table.concat(lines, "\n")
end
