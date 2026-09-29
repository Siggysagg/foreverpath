-- Pure Lua 5.1. No game API calls. All scores are illustrative stat points.
local _, NS = ...
local E = {}
NS.Engine = E
E.profiles = {
    strength = { label = "Strength", weights = { ITEM_MOD_STRENGTH_SHORT = 1, ITEM_MOD_STAMINA_SHORT = 0.5, RESISTANCE0_NAME = 0.02 } },
    agility = { label = "Agility", weights = { ITEM_MOD_AGILITY_SHORT = 1, ITEM_MOD_STAMINA_SHORT = 0.5, RESISTANCE0_NAME = 0.02 } },
    intellect = { label = "Intellect", weights = { ITEM_MOD_INTELLECT_SHORT = 1, ITEM_MOD_SPIRIT_SHORT = 0.3, ITEM_MOD_STAMINA_SHORT = 0.5, RESISTANCE0_NAME = 0.01 } },
}
local function normalized(value)
    return type(value) == "string" and string.lower(value) or ""
end

-- Imported profiles are optional data. Matching is exact on class, the selected spec
-- (any spec when none is chosen) and inclusive level interval.
function E.SelectStatProfile(class, level, spec)
    local data = NS.StatWeights
    if type(data) ~= "table" or type(data.profiles) ~= "table" or type(level) ~= "number" then return nil end
    for _, profile in ipairs(data.profiles) do
        if normalized(profile.class) == normalized(class) and (spec == nil or normalized(profile.spec) == normalized(spec))
            and type(profile.minLevel) == "number" and type(profile.maxLevel) == "number"
            and level >= profile.minLevel and level <= profile.maxLevel and type(profile.weights) == "table" then
            return profile
        end
    end
    return nil
end

-- Imported specs for this class and level, in data order (used by the Profile button).
function E.SpecsFor(class, level)
    local specs, seen = {}, {}
    local data = NS.StatWeights
    if type(data) ~= "table" or type(data.profiles) ~= "table" or type(level) ~= "number" then return specs end
    for _, profile in ipairs(data.profiles) do
        if normalized(profile.class) == normalized(class) and profile.spec and not seen[normalized(profile.spec)]
            and (profile.minLevel or 0) <= level and level <= (profile.maxLevel or math.huge) then
            seen[normalized(profile.spec)] = true
            specs[#specs + 1] = profile.spec
        end
    end
    return specs
end

-- New players never pick a profile: fall back to a sensible one for their class.
local CLASS_DEFAULT = { WARRIOR = "strength", PALADIN = "strength", SHAMAN = "strength", HUNTER = "agility",
    ROGUE = "agility", DRUID = "agility", MAGE = "intellect", PRIEST = "intellect", WARLOCK = "intellect" }

function E.ProfileFor(class, level, spec, fallbackName)
    return E.SelectStatProfile(class, level, spec) or E.profiles[fallbackName]
        or E.profiles[CLASS_DEFAULT[string.upper(class or "")] or ""]
end
-- Goal weights are intentionally explicit and deterministic. XP is normalized
-- per 100 points, gear is the selected profile's stat delta, and unlockValue
-- is a bounded, caller-supplied profession value normalized per 10 points.
E.goals = {
    balanced = { xp = 1, gear = 2, professions = 1 },
    leveling = { xp = 3, gear = 0.5, professions = 0.25 },
    gear = { xp = 0.25, gear = 4, professions = 0.25 },
    professions = { xp = 0.25, gear = 0.5, professions = 4 },
}
function E.StatScore(stats, weights)
    if type(stats) ~= "table" then return nil end
    local sum = 0
    for stat, weight in pairs(weights) do sum = sum + (tonumber(stats[stat]) or 0) * weight end
    return sum
end

-- Pure comparison for runtime reward data. The client adapter supplies slot names
-- and cached item stats; false means an equipped item exists but is not loaded.
function E.CompareReward(reward, equipped, profileName)
    local out = { verdict = "Waiting for data", confidence = "low" }
    local profile = type(profileName) == "table" and profileName or E.profiles[profileName]
    if not profile or type(reward) ~= "table" or type(reward.stats) ~= "table" or not next(reward.stats) then return out end
    if type(reward.slots) ~= "table" or not next(reward.slots) then return out end
    equipped = type(equipped) == "table" and equipped or {}
    local currentScore, comparedSlot
    if reward.replaces == "all" then
        currentScore, comparedSlot = 0, table.concat(reward.slots, "+")
        for _, slot in ipairs(reward.slots) do
            local current = equipped[slot]
            if current == false or (current ~= nil and (type(current) ~= "table" or not next(current))) then return out end
            currentScore = currentScore + (current and E.StatScore(current, profile.weights) or 0)
        end
    else
        for _, slot in ipairs(reward.slots) do
            local current = equipped[slot]
            if current == false or (current ~= nil and (type(current) ~= "table" or not next(current))) then return out end
            local score = current and E.StatScore(current, profile.weights) or 0
            if not currentScore or score < currentScore then currentScore, comparedSlot = score, slot end
        end
    end
    local rewardScore = E.StatScore(reward.stats, profile.weights)
    if rewardScore == nil then return out end
    out.delta, out.comparedSlot, out.confidence = rewardScore - currentScore, comparedSlot, "high"
    out.verdict = out.delta > 0 and "Higher stat score" or "No stat gain"
    return out
end

-- NextQuests: which imported quests can this character take right now, and which are worth it.
-- Pure: the client adapter supplies completed/in-log quest IDs, equipped stats and reward slots.
local function questNumber(ref)
    if type(ref) == "number" then return ref end
    return tonumber(string.match(tostring(ref or ""), "(%d+)$"))
end

local RACE_ALIAS = { SCOURGE = "UNDEAD" }
local function allowed(node, player)
    local myRace = string.upper(player.race or "")
    myRace = RACE_ALIAS[myRace] or myRace
    local listed, match = false, false
    for _, race in ipairs(node.races or {}) do
        if race == "HORDE_ONLY" then
            if player.faction ~= "Horde" then return false end
        elseif race == "ALLIANCE_ONLY" then
            if player.faction ~= "Alliance" then return false end
        else
            listed = true
            if string.upper(race) == myRace then match = true end
        end
    end
    -- A race list (e.g. ORC, TROLL) limits the quest to those races; an unknown player race keeps it.
    if listed and not match and myRace ~= "" then return false end
    if type(node.classes) == "table" and #node.classes > 0 then
        for _, class in ipairs(node.classes) do
            if string.upper(class) == string.upper(player.class or "") then return true end
        end
        return false
    end
    return true
end

-- signals (optional): { quests = { [questID] = { order, classes? } } } from speedrun guides (RXP).
local function guideTakes(signal, player)
    if not signal then return false end
    if type(signal.classes) ~= "table" or #signal.classes == 0 then return true end
    for _, class in ipairs(signal.classes) do
        if string.upper(class) == string.upper(player.class or "") then return true end
    end
    return false
end

function E.NextQuests(quests, player, profile, goalName, signals)
    local completed, inLog, level = player.completed or {}, player.inLog or {}, player.level or 0
    local signalled = signals and signals.quests or {}
    -- Generated data uses string keys ("4641"); accept numbers too.
    local guided = setmetatable({}, { __index = function(_, id) return signalled[id] or signalled[tostring(id)] end })
    -- A zone counts as guide-covered when any of its quests appears in a guide; only there is "not taken" a signal.
    local covered = {}
    for id, node in pairs(quests) do
        local questID = node.questID or questNumber(id)
        if node.zone and questID and guided[questID] then covered[node.zone] = true end
    end
    local goal = E.goals[goalName] or E.goals.balanced
    local children = {}
    for id, node in pairs(quests) do
        if allowed(node, player) then
            for _, required in ipairs(node.requires or {}) do
                children[required] = children[required] or {}
                children[required][#children[required] + 1] = id
            end
        end
    end
    local function unlocks(id, seen)
        local count = 0
        for _, child in ipairs(children[id] or {}) do
            if not seen[child] then seen[child] = true; count = count + 1 + unlocks(child, seen) end
        end
        return count
    end
    local rows = {}
    for id, node in pairs(quests) do
        local questID = node.questID or questNumber(id)
        local ready = questID and allowed(node, player) and not completed[questID] and (node.minLevel or 0) <= level
        for _, required in ipairs(node.requires or {}) do
            if ready and not completed[questNumber(required)] then ready = false end
        end
        if ready then
            local row = { id = "next:" .. questID, questID = questID, title = node.title or ("Quest " .. questID),
                kind = "quest", reasons = {}, gearGain = 0, unlocks = unlocks(id, {}) }
            local uncompared = false
            for _, reward in ipairs(node.rewards or {}) do
                local slotInfo = (player.itemSlots or {})[reward.itemID]
                local hasStats = type(reward.stats) == "table" and next(reward.stats) ~= nil
                if hasStats and slotInfo then
                    local result = E.CompareReward({ slots = slotInfo.slots, replaces = slotInfo.replaces, stats = reward.stats },
                        player.equipped or {}, profile)
                    if result.confidence ~= "high" then uncompared = true
                    elseif result.delta > row.gearGain then row.gearGain, row.bestReward = result.delta, reward end
                elseif hasStats then
                    uncompared = true
                end
            end
            local levelGap = level - (node.minLevel or level)
            local here = (player.mapID and node.position and node.position.map == player.mapID)
                or (not node.position and node.zone and node.zone == player.zone)
            -- Deterministic: gear delta, follow-up chain length and level fit, weighted by the chosen goal.
            -- Chain value is capped: a 22-quest chain is good, not twice as good as an 11-quest one.
            row.score = row.gearGain * goal.gear + math.min(row.unlocks, 10) * 1.5 * goal.xp
                + math.max(0, 3 - math.max(0, levelGap)) * 0.5 * goal.xp
            row.here = here and true or false
            if here then row.reasons[#row.reasons + 1] = "In your zone"
            elseif player.mapID and node.zone then row.reasons[#row.reasons + 1] = "In " .. node.zone end
            if row.bestReward then
                row.reasons[#row.reasons + 1] = string.format("Reward: %s (+%.1f for you)", row.bestReward.title or "item", row.gearGain)
            elseif uncompared then
                row.reasons[#row.reasons + 1] = "Has gear rewards; reward not compared yet"
            end
            if row.unlocks > 0 then row.reasons[#row.reasons + 1] = string.format("Opens %d follow-up quest%s", row.unlocks, row.unlocks == 1 and "" or "s") end
            local guideSkips = false
            if guideTakes(guided[questID], player) then
                row.score = row.score + 2 * goal.xp
                row.reasons[#row.reasons + 1] = "Speedrun guides take this"
            elseif node.zone and covered[node.zone] then
                guideSkips = true
                row.score = row.score - goal.xp
                row.reasons[#row.reasons + 1] = "Speedrun guides skip this"
            end
            if node.position and node.position.x and node.position.y then
                row.reasons[#row.reasons + 1] = string.format("Quest giver at %.1f, %.1f", node.position.x, node.position.y)
            end
            if inLog[questID] then
                row.verdict = "In your log"
            elseif levelGap >= 6 and row.gearGain == 0 and row.unlocks == 0 and not uncompared then
                row.verdict, row.score = "Skip", -1
                row.reasons[#row.reasons + 1] = "Low level for you, no upgrade and no follow-up"
            elseif guideSkips and row.gearGain == 0 and row.unlocks == 0 and not uncompared then
                row.verdict = "Skip"
            end
            rows[#rows + 1] = row
        end
    end
    -- Travel matters most for new players: quests in the current zone always come first.
    table.sort(rows, function(a, b)
        local skipA, skipB = a.verdict == "Skip", b.verdict == "Skip"
        if skipA ~= skipB then return skipB end
        if a.here ~= b.here then return a.here end
        if a.score == b.score then return a.questID < b.questID end
        return a.score > b.score
    end)
    local first = true
    for _, row in ipairs(rows) do
        if not row.verdict then
            row.verdict = first and "Do next" or (row.gearGain > 0 and "Upgrade reward") or (row.unlocks > 0 and "Opens a chain") or "Optional"
            first = false
        end
    end
    return rows
end
