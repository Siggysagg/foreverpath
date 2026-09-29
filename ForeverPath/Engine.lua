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

-- A target includes all unfinished AND prerequisites exactly once.
-- An unknown dependency is never treated as a zero-cost prerequisite.
function E.Remaining(graph, target, completed)
    local result, seen, active = {}, {}, {}
    local function visit(id)
        if completed[id] or seen[id] then return true end
        if active[id] then return nil, "Dependency cycle: " .. id end
        local node = graph[id]
        if not node then return nil, "Missing dependency: " .. id end
        active[id] = true
        for _, parent in ipairs(node.requires or {}) do
            local ok, err = visit(parent)
            if not ok then return nil, err end
        end
        active[id], seen[id] = nil, true
        result[#result + 1] = node
        return true
    end
    local ok, err = visit(target)
    if not ok then return nil, err end
    return result
end

function E.Evaluate(graph, target, state)
    local root = graph[target]
    local out = { id = target, title = root and root.title or target, kind = root and root.kind or "quest", reasons = {}, verified = true }
    local nodes, err = E.Remaining(graph, target, state.completed or {})
    if not nodes then out.verdict = "Needs data"; out.reasons[1] = err; return out end
    if #nodes == 0 then out.verdict = "Complete"; return out end
    local profile = E.profiles[state.profile]
    if not profile then out.verdict = "Choose profile"; return out end
    local scores = {}
    for slot, stats in pairs(state.equipped or {}) do scores[slot] = E.StatScore(stats, profile.weights) or 0 end
    local minutes, xp, gold, gear, unlocks = 0, 0, 0, 0, 0
    local uncertain, blocked = false, false
    for _, node in ipairs(nodes) do
        if node.faction and node.faction ~= state.faction then blocked = true; out.reasons[#out.reasons + 1] = "Faction requirement" end
        if node.minLevel and node.minLevel > (state.level or 0) then blocked = true; out.reasons[#out.reasons + 1] = "Requires level " .. node.minLevel end
        if node.profession and ((state.professions or {})[node.profession] or 0) < (node.skill or 0) then blocked = true; out.reasons[#out.reasons + 1] = "Profession skill required" end
        if node.group and not state.grouped then blocked = true; out.reasons[#out.reasons + 1] = "Group required" end
        if node.minutes == nil or node.costGold == nil or node.xp == nil or not node.dependenciesKnown or not node.rewardsKnown then uncertain = true end
        if node.evidence ~= "verified" then out.verified = false end
        minutes, xp, gold = minutes + (node.minutes or 0), xp + (node.xp or 0), gold + (node.costGold or 0)
        unlocks = unlocks + (node.unlockValue or 0)
        local function gain(item)
            if not item.slot or not item.stats then uncertain = true; return 0 end
            return math.max(0, E.StatScore(item.stats, profile.weights) - (scores[item.slot] or 0))
        end
        local function equip(item)
            local delta = gain(item)
            if delta > 0 then scores[item.slot] = E.StatScore(item.stats, profile.weights); gear = gear + delta end
        end
        -- Guaranteed rewards may stack; choices are mutually exclusive.
        for _, item in ipairs(node.rewards or {}) do equip(item) end
        local best, bestGain
        for _, item in ipairs(node.choices or {}) do
            local delta = gain(item)
            if not bestGain or delta > bestGain then best, bestGain = item, delta end
        end
        if best then equip(best) end
    end
    if gold > (state.gold or 0) then blocked = true; out.reasons[#out.reasons + 1] = "Above available gold budget" end
    out.minutes, out.xp, out.costGold, out.gearGain, out.steps = minutes, xp, gold, gear, #nodes
    if blocked then out.verdict = "Not available"; return out end
    if uncertain then out.verdict = "Needs data"; out.reasons[#out.reasons + 1] = "Incomplete rewards, costs or prerequisites"; return out end
    local goal = E.goals[state.goal] or E.goals.balanced
    out.score = (gear * goal.gear + xp / 100 * goal.xp + unlocks / 10 * goal.professions) / math.max(1, minutes)
    out.verdict = "Consider"
    if gear == 0 and xp == 0 and unlocks == 0 and root.downstreamKnown then out.verdict = "Low priority" end
    out.reasons[#out.reasons + 1] = string.format("+%.1f stat points | %d XP | %d remaining steps", gear, xp, #nodes)
    out.reasons[#out.reasons + 1] = string.format("Estimated %d min | %.1fg cost", minutes, gold)
    if not root.downstreamKnown then out.reasons[#out.reasons + 1] = "Later unlocks unknown: no skip advice" end
    return out
end
function E.Rank(graph, targets, state)
    local rows = {}
    for _, id in ipairs(targets) do rows[#rows + 1] = E.Evaluate(graph, id, state) end
    table.sort(rows, function(a, b)
        if a.score == b.score then return a.id < b.id end
        return (a.score or -1) > (b.score or -1)
    end)
    if rows[1] and rows[1].score and rows[1].score > 0 then rows[1].verdict = "First suggestion" end
    return rows
end

-- NextQuests: which imported quests can this character take right now, and which are worth it.
-- Pure: the client adapter supplies completed/in-log quest IDs, equipped stats and reward slots.
local function questNumber(ref)
    if type(ref) == "number" then return ref end
    return tonumber(string.match(tostring(ref or ""), "(%d+)$"))
end

local function allowed(node, player)
    for _, race in ipairs(node.races or {}) do
        if race == "HORDE_ONLY" and player.faction ~= "Horde" then return false end
        if race == "ALLIANCE_ONLY" and player.faction ~= "Alliance" then return false end
    end
    if type(node.classes) == "table" and #node.classes > 0 then
        for _, class in ipairs(node.classes) do
            if string.upper(class) == string.upper(player.class or "") then return true end
        end
        return false
    end
    return true
end

function E.NextQuests(quests, player, profile, goalName)
    local completed, inLog, level = player.completed or {}, player.inLog or {}, player.level or 0
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
            -- Deterministic: gear delta, follow-up chain length and level fit, weighted by the chosen goal.
            row.score = row.gearGain * goal.gear + row.unlocks * 1.5 * goal.xp + math.max(0, 3 - math.max(0, levelGap)) * 0.5 * goal.xp
            if row.bestReward then
                row.reasons[#row.reasons + 1] = string.format("Reward: %s (+%.1f for you)", row.bestReward.title or "item", row.gearGain)
            elseif uncompared then
                row.reasons[#row.reasons + 1] = "Has gear rewards; reward not compared yet"
            end
            if row.unlocks > 0 then row.reasons[#row.reasons + 1] = string.format("Opens %d follow-up quest%s", row.unlocks, row.unlocks == 1 and "" or "s") end
            if node.position and node.position.x and node.position.y then
                row.reasons[#row.reasons + 1] = string.format("Quest giver at %.1f, %.1f", node.position.x, node.position.y)
            end
            if inLog[questID] then
                row.verdict = "In your log"
            elseif levelGap >= 6 and row.gearGain == 0 and row.unlocks == 0 and not uncompared then
                row.verdict, row.score = "Skip", -1
                row.reasons[#row.reasons + 1] = "Low level for you, no upgrade and no follow-up"
            end
            rows[#rows + 1] = row
        end
    end
    table.sort(rows, function(a, b)
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
