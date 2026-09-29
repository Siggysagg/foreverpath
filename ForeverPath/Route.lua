-- Pure Lua 5.1. The RestedXP route for this character, plus side quests in the current zone.
local _, NS = ...
local R = {}
NS.Route = R

local RACE_ALIAS = { SCOURGE = "UNDEAD" }
local CLASSES = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true,
    MAGE = true, WARLOCK = true, DRUID = true }
local RACES = { HUMAN = true, DWARF = true, NIGHTELF = true, GNOME = true, ORC = true, UNDEAD = true, TAUREN = true,
    TROLL = true, SKYBORNE = true }
local NEVER = { SKIP = true, SOD = true }  -- skip steps, Season of Discovery steps

local function token(player, word)
    local race = string.upper(player.race or "")
    race = RACE_ALIAS[race] or race
    if word == "HORDE" or word == "ALLIANCE" then return string.upper(player.faction or "") == word end
    if CLASSES[word] then return string.upper(player.class or "") == word end
    if RACES[word] then return race == word end
    if NEVER[word] then return false end
    return true  -- unknown tags (era, typos) never hide a step
end

-- RXP tags: space = and, slash = or, ! = not.
function R.TagsMatch(expr, player)
    if not expr or expr == "" then return true end
    for group in string.gmatch(expr, "%S+") do
        local negate = string.sub(group, 1, 1) == "!"
        if negate then group = string.sub(group, 2) end
        local any = false
        for word in string.gmatch(group, "[^/]+") do
            if token(player, word) then any = true end
        end
        if any == negate then return false end
    end
    return true
end

-- Guides in play order: the start guide for this race, then #next links, then the next fitting guide.
-- The dungeon playstyle follows RXP's dungeon guide group; every other style excludes it.
function R.Chain(routes, player, style)
    local wantDungeon = style == "dungeon"
    local byName, fits = {}, {}
    for _, guide in ipairs(routes and routes.guides or {}) do
        byName[guide.name] = guide
        if R.TagsMatch(guide.only, player) and (guide.group == "dungeon") == wantDungeon then
            fits[#fits + 1] = guide
        end
    end
    local function preferred(guide) return not guide.defaultfor or R.TagsMatch(guide.defaultfor, player) end
    local start
    for _, guide in ipairs(fits) do
        if guide.defaultfor and R.TagsMatch(guide.defaultfor, player) and (not start or guide.minLevel < start.minLevel) then start = guide end
    end
    local chain, seen, current = {}, {}, start
    while current and not seen[current] do
        seen[current] = true
        chain[#chain + 1] = current
        local following
        for _, link in ipairs(current.next or {}) do
            local guide = byName[link.to]
            if not following and guide and R.TagsMatch(link.only, player) and R.TagsMatch(guide.only, player) then following = guide end
        end
        if not following then
            for _, guide in ipairs(fits) do
                if not seen[guide] and preferred(guide) and guide.minLevel >= current.maxLevel - 2
                    and (not following or guide.minLevel < following.minLevel) then following = guide end
            end
        end
        current = following
    end
    return chain
end

-- Walks the route like playing it: accepting puts a quest in the (simulated) log, completing makes it
-- ready, turning in finishes it. A step shows when it is the next real thing to do in that walk.
local function walker(player, quests)
    local sim = { completed = {}, inLog = {}, ready = {} }
    for key in pairs(sim) do for q, v in pairs(player[key] or {}) do sim[key][q] = v end end
    local requires = {}
    for _, node in pairs(quests) do
        if node.questID then requires[node.questID] = node.requires end
    end
    return function(step)
        local q = step.q
        if sim.completed[q] then return false end
        if step.a == "accept" then
            if sim.inLog[q] then return false end
            for _, ref in ipairs(requires[q] or {}) do
                local id = tonumber(string.match(tostring(ref), "(%d+)$"))
                if id and not sim.completed[id] then return false end
            end
            sim.inLog[q] = true
        elseif step.a == "complete" then
            if not sim.inLog[q] or sim.ready[q] then return false end
            sim.ready[q] = true
        else
            if not sim.inLog[q] then return false end
            sim.completed[q], sim.inLog[q] = true, nil
        end
        return true
    end
end

local VERB = { accept = "Accept", turnin = "Turn in", complete = "Complete" }

local function titleOf(routes, quests, q)
    local titles = routes and routes.titles or {}
    local title = titles[q] or titles[tostring(q)]
    if title then return title end
    for _, node in pairs(quests) do
        if node.questID == q then return node.title end
    end
    return "Quest " .. q
end

local function levelReason(expected, level)
    if not expected then return nil end
    if level < expected - 1 then
        return string.format("Guide expects level %d here; you are %d. Kill mobs on the way or do side quests", expected, level)
    elseif level > expected + 3 then
        return string.format("You are ahead of the guide (level %d expected)", expected)
    end
    return string.format("Right level for you (guide: %d)", expected)
end

-- style: speed | balanced | gear | story. See Plan for what each shows.
R.styles = { speed = "leveling", balanced = "balanced", gear = "gear", story = "balanced", dungeon = "leveling" }
R.labels = { speed = "Speedrun", balanced = "Balanced", gear = "Gear", story = "Story", dungeon = "Dungeon" }
R.order = { "speed", "balanced", "gear", "story", "dungeon" }

function R.Plan(quests, routes, player, profile, style, limit)
    style = R.styles[style] and style or "balanced"
    limit = limit or 5
    local chain = R.Chain(routes, player, style)
    local level = player.level or 1
    local inRoute, signals, positions = {}, { quests = {} }, {}
    for _, node in pairs(quests) do
        if node.questID then positions[node.questID] = node.position end
    end
    local steps, walk = {}, walker(player, quests)
    for _, guide in ipairs(chain) do
        local mine = {}
        for _, step in ipairs(guide.steps or {}) do
            if R.TagsMatch(step.only, player) then
                mine[#mine + 1] = step
                if step.a == "accept" then inRoute[step.q], signals.quests[step.q] = true, { order = #mine } end
            end
        end
        if level <= guide.maxLevel + 2 then
            for index, step in ipairs(mine) do
                if #steps < limit and walk(step) then steps[#steps + 1] = { step = step, guide = guide, index = index, total = #mine } end
            end
        end
    end
    -- Quest facts (rewards, follow-ups) for every quest this character can take now, keyed by quest ID.
    local goal = R.styles[style]
    local available = NS.Engine.NextQuests(quests, player, profile, goal, style ~= "story" and signals or nil)
    local facts = {}
    for _, row in ipairs(available) do facts[row.questID] = row end
    local rows = {}
    for i, entry in ipairs(steps) do
        local step, fact = entry.step, facts[entry.step.q]
        local position = step.map and { map = step.map, x = step.x, y = step.y } or (step.a == "accept" and positions[step.q]) or nil
        local row = { id = "route:" .. step.a .. ":" .. step.q, questID = step.q, action = step.a,
            title = VERB[step.a] .. ": " .. titleOf(routes, quests, step.q), verdict = i == 1 and "Do next" or "Then",
            reasons = {}, slotIndexes = {},
            stepIndex = entry.index, stepTotal = entry.total, guideName = entry.guide.name }
        if fact and fact.bestReward then row.bestReward = fact.bestReward end
        if position and position.map then row.target = { map = position.map, x = position.x, y = position.y } end
        local where = step.npc and ("Talk to " .. step.npc) or (step.a == "complete" and "Do the objectives" or nil)
        if row.target then
            local zone = player.zoneName and player.zoneName(row.target.map)
            local place = string.format("%.1f, %.1f%s", row.target.x or 0, row.target.y or 0, zone and (" in " .. zone) or "")
            where = where and (where .. " at " .. place) or ("At " .. place)
        end
        if where then row.reasons[#row.reasons + 1] = where end
        row.reasons[#row.reasons + 1] = string.format("RestedXP route: %s, step %d of %d", entry.guide.name, entry.index, entry.total)
        row.reasons[#row.reasons + 1] = levelReason(step.level, level)
        if fact and fact.bestReward then
            row.reasons[#row.reasons + 1] = string.format("Reward: %s (+%.1f for you)", fact.bestReward.title or "item", fact.gearGain)
        end
        if step.a == "accept" and fact and fact.unlocks > 0 then
            row.reasons[#row.reasons + 1] = string.format("Opens %d follow-up quest%s", fact.unlocks, fact.unlocks == 1 and "" or "s")
        end
        rows[#rows + 1] = row
    end
    -- Side quests: only where you are, never duplicating the route.
    local side = {}
    for _, fact in ipairs(available) do
        local keep = fact.here and not inRoute[fact.questID]
        if style == "speed" or style == "dungeon" then keep = keep and fact.gearGain > 0
        elseif style == "gear" then keep = keep and (fact.gearGain > 0 or fact.verdict ~= "Skip")
        elseif style == "balanced" then keep = keep and fact.verdict ~= "Skip" end
        if keep then
            fact.action = nil
            local position = positions[fact.questID]
            if position then fact.target = { map = position.map, x = position.x, y = position.y } end
            -- Without a route step, the best side quest is the next thing to do.
            if fact.verdict == "Do next" and #rows > 0 then fact.verdict = fact.gearGain > 0 and "Upgrade reward" or "Side quest" end
            side[#side + 1] = fact
        end
    end
    for i = 1, math.min(#side, style == "story" and 10 or 5) do rows[#rows + 1] = side[i] end
    -- Expose the full available-quest facts so callers can derive other views (the
    -- upgrade finder) without re-walking the database or changing Plan's signature.
    R.lastAvailable = available
    return rows
end
