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
    local byName, fits, fitSet = {}, {}, {}
    for _, guide in ipairs(routes and routes.guides or {}) do
        -- Notes-only guides carry no steps and must never enter the chain.
        if guide.steps and guide.steps[1] then
            byName[guide.name] = guide
            if R.TagsMatch(guide.only, player) and (guide.group == "dungeon") == wantDungeon then
                fits[#fits + 1] = guide
                fitSet[guide] = true
            end
        end
    end
    -- Dungeon leveling before the first dungeon guide (level < 13): the dungeon
    -- chain is empty. Fall back to the normal leveling route so the player still
    -- gets a path (#177) — the dungeon guides take over when they fit.
    if wantDungeon then
        local level = player.level or 1
        local hasFittingDungeon = false
        for _, guide in ipairs(fits) do
            if level >= guide.minLevel and level <= guide.maxLevel + 2 then hasFittingDungeon = true break end
        end
        if not hasFittingDungeon then
            fits, fitSet = {}, {}
            for _, guide in ipairs(routes and routes.guides or {}) do
                if guide.steps and guide.steps[1] and R.TagsMatch(guide.only, player) and guide.group ~= "dungeon" then
                    fits[#fits + 1] = guide
                    fitSet[guide] = true
                end
            end
        end
    end
    local function preferred(guide) return not guide.defaultfor or R.TagsMatch(guide.defaultfor, player) end
    local start
    for _, guide in ipairs(fits) do
        if guide.defaultfor and R.TagsMatch(guide.defaultfor, player) and (not start or guide.minLevel < start.minLevel) then start = guide end
    end
    if not start then
        for _, guide in ipairs(fits) do
            if preferred(guide) and (not start or guide.minLevel < start.minLevel
                or (guide.minLevel == start.minLevel and guide.name < start.name)) then
                start = guide
            end
        end
    end
    local chain, seen, current = {}, {}, start
    while current and not seen[current] do
        seen[current] = true
        chain[#chain + 1] = current
        local following
        for _, link in ipairs(current.next or {}) do
            local guide = byName[link.to]
            if not following and guide and fitSet[guide]
                and R.TagsMatch(link.only, player) and R.TagsMatch(guide.only, player) then following = guide end
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
    local initiallyInLog = {}
    for q, value in pairs(sim.inLog) do if value then initiallyInLog[q] = true end end
    local requires = {}
    for _, node in pairs(quests) do
        if type(node) == "table" and node.questID then requires[node.questID] = node.requires end
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
        elseif step.a == "turnin" then
            if not sim.inLog[q] or (initiallyInLog[q] and not sim.ready[q]) then return false end
            sim.completed[q], sim.inLog[q] = true, nil
        else
            return false
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
        if type(node) == "table" and node.questID == q then return node.title end
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
        if type(node) == "table" and node.questID then positions[node.questID] = node.position end
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
        row.isDungeonStep = entry.guide.group == "dungeon"
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

-- Custom routes (ROUTE-01): the player's own RestedXP-format text, parsed at runtime.
-- Pure Lua 5.1, the same subset the offline importer handles, minus world coordinates
-- (.goto with /instance needs the build-time DB2 table). Map-percent .goto works.
local function customTag(line)
    local tail = string.match(line, "<<(.*)")
    if not tail then return "" end
    tail = string.match(tail, "^(.-)%-%-") or tail
    tail = string.gsub(tail, "^%s+", "")
    tail = string.gsub(tail, "%s+$", "")
    tail = string.gsub(tail, "%s+", " ")
    return string.upper(tail)
end

local function customBoth(first, second)
    if first ~= "" and second ~= "" then return first .. " " .. second end
    return first ~= "" and first or second
end

function R.ParseCustomGuides(text)
    local guides, titles = {}, {}
    if type(text) ~= "string" then return guides, titles end
    for block in string.gmatch(text, "RegisterGuide%(%s*%[%[(.-)%]%]") do
        local guide = { name = nil, minLevel = 1, maxLevel = 60, steps = {} }
        local level, stepTag, step, sawStep = nil, "", nil, false
        local function flush()
            if not step then return end
            for _, entry in ipairs(step.quests) do
                local out = { a = entry[1], q = entry[2], level = level or guide.minLevel }
                local tags = customBoth(stepTag, entry[3])
                if tags ~= "" then out.only = tags end
                if step.map then out.map, out.x, out.y = step.map, step.x, step.y end
                if step.npc then out.npc = step.npc end
                guide.steps[#guide.steps + 1] = out
            end
        end
        for line in string.gmatch(block, "[^\r\n]+") do
            line = string.gsub(line, "^%s+", "")
            line = string.gsub(line, "%s+$", "")
            if string.sub(line, 1, 4) == "step" then
                flush()
                stepTag, step = customTag(line), { quests = {} }
                sawStep = true
            elseif not sawStep and string.sub(line, 1, 2) == "<<" and guide.only == nil then
                guide.only = customTag(line)
            elseif string.sub(line, 1, 6) == "#name " then
                guide.name = string.sub(line, 7)
                local a, b = string.match(guide.name, "^(%d+)%-(%d+)")
                if a then guide.minLevel, guide.maxLevel = tonumber(a), tonumber(b) end
            elseif string.sub(line, 1, 12) == "#defaultfor " then
                guide.defaultfor = string.upper(string.match(string.sub(line, 13), "^[^<<]*"))
            elseif string.sub(line, 1, 7) == "#group " and string.find(line, "Dungeon") then
                guide.group = "dungeon"
            elseif string.sub(line, 1, 6) == "#next " then
                for name in string.gmatch(string.match(string.sub(line, 7), "^[^<<]*") or "", "[^;]+") do
                    if string.find(name, "%S") then
                        guide.next = guide.next or {}
                        guide.next[#guide.next + 1] = { to = string.match(name, "([^\\]+)$") }
                    end
                end
            elseif step and not string.find(" " .. (stepTag or "") .. " ", "%sSKIP%s") then
                local action, questID = string.match(line, "^%.([%a]+)%s+(%d+)")
                if action == "accept" or action == "turnin" or action == "complete" then
                    local stepTitle = string.match(line, ">>(.-)%s*<<") or string.match(line, ">>?(.*)")
                    local name = string.match(line, ">>%s*Accept%s+(.+)$") or string.match(line, ">>%s*Turn in%s+(.+)$")
                    if name then
                        name = string.match(name, "^(.-)%s*<<") or name
                        titles[tonumber(questID)] = name
                    end
                    step.quests[#step.quests + 1] = { action, tonumber(questID), customTag(line) }
                else
                    local mapID, x, y = string.match(line, "^%.goto%s+(%d+),([%d%.%-]+),([%d%.%-]+)$")
                    if mapID then
                        step.map, step.x, step.y = tonumber(mapID), tonumber(x), tonumber(y)
                    elseif string.sub(line, 1, 8) == ".target " and step.npc == nil then
                        step.npc = string.match(string.gsub(string.sub(line, 9), "::%d+", ""), "^[^<<,]+")
                    elseif string.sub(line, 1, 4) == ".xp " then
                        local xpLevel = tonumber(string.match(line, "^%.xp%s+(%d+)"))
                        if xpLevel and (not level or xpLevel > level) then level = xpLevel end
                    end
                end
            end
        end
        flush()
        if guide.name and string.match(guide.name, "^%d+%-%d+") then
            guides[#guides + 1] = guide
        end
    end
    return guides, titles
end

-- !FP:1! import string (#264): versioned, strict and data-only. The legacy FP1@
-- grammar stays frozen for old strings; only !FP:1! validates hard, fails on
-- the first bad record and never touches the Lua loader.
local FP1_PREFIX = "!FP:1!"
local MAX_TEXT = 65536
local MAX_GUIDES, MAX_STEPS, MAX_NOTES = 50, 3000, 300
local MAX_NAME, MAX_TEXT_FIELD = 48, 160
local TAG_PATTERN = "^[%a!/ ]*$"

-- Store and activate the player's pasted route; custom guides win over imported
-- guides with the same name, so "my launch route" always beats the shipped one.
function R.SetCustomRoute(text)
    if type(text) == "string" and string.sub(text, 1, #FP1_PREFIX) == FP1_PREFIX then
        -- A strict versioned share string: all-or-nothing decode.
        local guides, titles, meta = R.DecodeRoute(text)
        if not guides then
            R.customGuides, R.customTitles, R.customMeta = {}, {}, nil
            R.customActive = false
            return nil, titles
        end
        R.customGuides, R.customTitles, R.customMeta = guides, titles, meta
    elseif type(text) == "string" and string.sub(text, 1, 4) == "FP1@" then
        -- A legacy share string: decode it instead of parsing guide text.
        R.customGuides, R.customTitles = R.DecodeRoute(text) or {}, {}
        R.customMeta = nil
    else
        R.customGuides, R.customTitles = R.ParseCustomGuides(text)
        R.customMeta = nil
    end
    R.customActive = #R.customGuides > 0
    return R.customGuides, R.customTitles
end

function R.CustomRouteStats()
    local guides, steps = R.customGuides or {}, 0
    for _, guide in ipairs(guides) do steps = steps + #guide.steps end
    return #guides, steps
end

-- Free-text notes from the imported route for guides covering this level. They are
-- checklist content only: they never enter the recommendation chain below.
function R.NotesFor(level)
    local notes = {}
    level = tonumber(level) or 1
    for _, guide in ipairs(R.customGuides or {}) do
        if guide.notes and #guide.notes > 0
            and level >= (guide.minLevel or 1) and level <= (guide.maxLevel or 60) then
            for _, note in ipairs(guide.notes) do notes[#notes + 1] = note end
        end
    end
    return notes
end

function R.ActiveRoutes()
    local routes = NS.Routes
    if not R.customActive then return routes end
    local merged = { guides = {}, titles = {}, provenance = routes and routes.provenance, customRoute = true }
    for _, guide in ipairs((routes and routes.guides) or {}) do merged.guides[#merged.guides + 1] = guide end
    for id, title in pairs((routes and routes.titles) or {}) do merged.titles[id] = title end
    local byName = {}
    for _, guide in ipairs(merged.guides) do byName[guide.name] = guide end
    for _, guide in ipairs(R.customGuides) do
        if byName[guide.name] then
            for index, existing in ipairs(merged.guides) do
                if existing.name == guide.name then merged.guides[index] = guide break end
            end
        else
            merged.guides[#merged.guides + 1] = guide
        end
        byName[guide.name] = guide
    end
    for id, title in pairs(R.customTitles or {}) do merged.titles[id] = title end
    return merged
end

-- Route sharing (SHARE-01): pack the parsed custom guides into one pasteable ASCII
-- string and back. Format: FP1@guide@guide, guide = fields;fields|step|step,
-- step = a;q;level;only;map;x;y;npc. Text fields escape the separators.
local SHARE_PREFIX = "FP1@"

local function shareEscape(text)
    text = string.gsub(tostring(text or ""), "\\", "\\\\")
    text = string.gsub(text, "@", "\\A")
    text = string.gsub(text, ";", "\\S")
    text = string.gsub(text, "|", "\\P")
    text = string.gsub(text, ",", "\\C")
    return text
end

local function shareUnescape(text)
    -- Decode each escape once; an escaped backslash must not start another escape.
    local escapes = { A = "@", S = ";", P = "|", C = ",", ["\\"] = "\\" }
    return (string.gsub(text, "\\(.)", function(code) return escapes[code] or ("\\" .. code) end))
end

local STEP_FIELDS = { "a", "q", "level", "only", "map", "x", "y", "npc" }

-- Split on ';' keeping empty fields (gmatch "[^;]+" would drop them and shift
-- every later field whenever an optional one is absent).
local function splitFields(part)
    local fields = {}
    for field in string.gmatch(part .. ";", "(.-);") do fields[#fields + 1] = field end
    return fields
end

local function numberOrEmpty(value)
    if type(value) == "number" then return string.format("%.3f", value):gsub("0+$", ""):gsub("%.$", "") end
    return ""
end

-- !FP:1! helpers: display-string sanitizer, strict integer parsing and a record
-- splitter that keeps empty segments so corrupt pastes are seen, not skipped.

-- Display strings keep | out of FontStrings: control bytes are dropped and the
-- escape-decoded | becomes /, so |T...|t and |Hitem...|h can never render.
local function sanitizeText(text)
    text = string.gsub(tostring(text or ""), "%c", "")
    text = string.gsub(text, "|", "/")
    return text
end

local function strictInt(value, min, max, what, index)
    if not string.match(value, "^%d+$") then
        return nil, string.format("Record %d: %s must be a whole number", index, what)
    end
    local n = tonumber(value)
    if n < min or n > max then
        return nil, string.format("Record %d: %s must be between %d and %d", index, what, min, max)
    end
    return n
end

-- Split records on literal | keeping empty segments, so a corrupt paste is seen
-- (and rejected) instead of silently shifted by gmatch's empty-skip.
local function splitRecords(body)
    local records, start = {}, 1
    while true do
        local sep = string.find(body, "|", start, true)
        if not sep then
            records[#records + 1] = string.sub(body, start)
            break
        end
        records[#records + 1] = string.sub(body, start, sep - 1)
        start = sep + 1
    end
    return records
end

local function strictDecode(text)
    if #text > MAX_TEXT then return nil, "Route string is too long (over 65536 characters)" end
    local records = splitRecords(string.sub(text, #FP1_PREFIX + 1))
    local total = #records
    if total < 2 then return nil, "Route string is truncated or corrupted (missing end record)" end
    local declared = string.match(records[total], "^E;(%d+)$")
    if not declared then return nil, "Route string is truncated or corrupted (missing end record)" end
    if tonumber(declared) ~= total - 1 then
        return nil, string.format("Route string is truncated or corrupted (end record says %s, found %d records)",
            declared, total - 1)
    end
    local metaFields = splitFields(records[1])
    if metaFields[1] ~= "M" or #metaFields ~= 4 then
        return nil, "Record 1: route must start with the M name record"
    end
    local name = sanitizeText(shareUnescape(metaFields[2]))
    if name == "" then return nil, "Record 1: route name is required" end
    if #name > MAX_NAME then return nil, string.format("Record 1: route name is too long (max %d)", MAX_NAME) end
    local meta = { name = name }
    for _, entry in ipairs({ { "author", 3 }, { "sourceId", 4 } }) do
        local key, position = entry[1], entry[2]
        local value = sanitizeText(shareUnescape(metaFields[position]))
        if #value > MAX_NAME then
            return nil, string.format("Record 1: route %s is too long (max %d)", key, MAX_NAME)
        end
        if value ~= "" then meta[key] = value end
    end
    local guides, titles, current, stepCount, noteCount = {}, {}, nil, 0, 0
    for index = 2, total - 1 do
        local record = records[index]
        if record == "" then
            return nil, string.format("Record %d: empty record (corrupted string)", index)
        elseif string.sub(record, 1, 5) == "step:" then
            if not current then return nil, string.format("Record %d: step outside a guide", index) end
            local fields = splitFields(record)
            if #fields ~= 8 then return nil, string.format("Record %d: step record is malformed", index) end
            local action = string.sub(fields[1], 6)
            if action ~= "accept" and action ~= "turnin" and action ~= "complete" then
                return nil, string.format("Record %d: unknown step action '%s'", index, sanitizeText(action))
            end
            local q, err = strictInt(fields[2], 1, 99999, "quest id", index)
            if not q then return nil, err end
            local step = { a = action, q = q }
            if fields[3] ~= "" then
                local level, levelErr = strictInt(fields[3], 1, 60, "level", index)
                if not level then return nil, levelErr end
                step.level = level
            end
            if fields[4] ~= "" then
                local only = shareUnescape(fields[4])
                if not string.match(only, TAG_PATTERN) then
                    return nil, string.format("Record %d: step tag has invalid characters", index)
                end
                step.only = only
            end
            if fields[5] ~= "" then
                local map, mapErr = strictInt(fields[5], 1, 99999, "map id", index)
                if not map then return nil, mapErr end
                step.map = map
            end
            for _, key in ipairs({ "x", "y" }) do
                local value = fields[key == "x" and 6 or 7]
                if value ~= "" then
                    if not string.match(value, "^%d+%.?%d*$") or tonumber(value) > 100 then
                        return nil, string.format("Record %d: %s must be a number from 0 to 100", index, key)
                    end
                    step[key] = tonumber(value)
                end
            end
            if fields[8] ~= "" then
                local npc = sanitizeText(shareUnescape(fields[8]))
                if #npc > MAX_TEXT_FIELD then
                    return nil, string.format("Record %d: npc name is too long (max %d)", index, MAX_TEXT_FIELD)
                end
                step.npc = npc
            end
            stepCount = stepCount + 1
            if stepCount > MAX_STEPS then
                return nil, string.format("Record %d: too many steps (max %d)", index, MAX_STEPS)
            end
            current.steps[#current.steps + 1] = step
        elseif string.sub(record, 1, 6) == "title:" then
            local fields = splitFields(record)
            if #fields ~= 2 then return nil, string.format("Record %d: title record is malformed", index) end
            local q, err = strictInt(string.sub(fields[1], 7), 1, 99999, "quest id", index)
            if not q then return nil, err end
            local title = sanitizeText(shareUnescape(fields[2]))
            if #title > MAX_TEXT_FIELD then
                return nil, string.format("Record %d: title is too long (max %d)", index, MAX_TEXT_FIELD)
            end
            titles[q] = title
        elseif string.sub(record, 1, 5) == "note:" then
            if not current then return nil, string.format("Record %d: note outside a guide", index) end
            local note = sanitizeText(shareUnescape(string.sub(record, 6)))
            if #note > MAX_TEXT_FIELD then
                return nil, string.format("Record %d: note is too long (max %d)", index, MAX_TEXT_FIELD)
            end
            noteCount = noteCount + 1
            if noteCount > MAX_NOTES then
                return nil, string.format("Record %d: too many notes (max %d)", index, MAX_NOTES)
            end
            current.notes = current.notes or {}
            current.notes[#current.notes + 1] = note
        elseif string.sub(record, 1, 2) == "E;" then
            return nil, string.format("Record %d: unexpected end record before the last position", index)
        elseif string.match(record, "^%d") then
            local fields = splitFields(record)
            if #fields ~= 7 then return nil, string.format("Record %d: guide record is malformed", index) end
            local guideName = sanitizeText(shareUnescape(fields[1]))
            if not string.match(guideName, "^%d+%-%d+ ") then
                return nil, string.format("Record %d: guide name must start with '<min>-<max> '", index)
            end
            if #guideName > MAX_NAME then
                return nil, string.format("Record %d: guide name is too long (max %d)", index, MAX_NAME)
            end
            local minLevel, maxLevel = tonumber(fields[2]), tonumber(fields[3])
            if not minLevel or not maxLevel or string.find(fields[2] .. fields[3], "[^%d]")
                or minLevel < 1 or minLevel > 999 or maxLevel < 1 or maxLevel > 999 then
                return nil, string.format("Record %d: guide levels must be numbers", index)
            end
            if minLevel > maxLevel then
                return nil, string.format("Record %d: guide min level exceeds max level", index)
            end
            local guide = { name = guideName, minLevel = minLevel, maxLevel = maxLevel, next = {}, steps = {} }
            for _, key in ipairs({ "only", "defaultfor", "group" }) do
                local tag = shareUnescape(fields[key == "only" and 4 or key == "defaultfor" and 5 or 6])
                if tag ~= "" then
                    if not string.match(tag, TAG_PATTERN) then
                        return nil, string.format("Record %d: guide tag has invalid characters", index)
                    end
                    guide[key] = tag
                end
            end
            for to in string.gmatch(fields[7], "[^,]+") do
                local link = sanitizeText(shareUnescape(to))
                if #link > MAX_NAME then
                    return nil, string.format("Record %d: next link name is too long (max %d)", index, MAX_NAME)
                end
                guide.next[#guide.next + 1] = { to = link }
            end
            guides[#guides + 1] = guide
            if #guides > MAX_GUIDES then
                return nil, string.format("Record %d: too many guides (max %d)", index, MAX_GUIDES)
            end
            current = guide
        else
            return nil, string.format("Record %d was made by a newer version of ForeverPath", index)
        end
    end
    return guides, titles, meta
end

-- Encode the active custom route as a versioned !FP:1! string: an M header, then
-- guides with their steps and notes, then quest titles, then the E record count
-- that catches truncated pastes. Legacy FP1@ is decode-only.
function R.EncodeRoute(guides, titles, meta)
    guides = guides or R.customGuides
    if type(guides) ~= "table" or #guides == 0 then return nil end
    titles = titles or R.customTitles
    meta = meta or R.customMeta or { name = "My route" }
    local records, count = {}, 0
    local function emit(record)
        records[#records + 1] = record
        count = count + 1
    end
    emit("M;" .. table.concat({
        shareEscape(meta.name or "My route"), shareEscape(meta.author or ""), shareEscape(meta.sourceId or ""),
    }, ";"))
    for _, guide in ipairs(guides) do
        local nexts = {}
        for _, link in ipairs(guide.next or {}) do nexts[#nexts + 1] = shareEscape(link.to) end
        emit(table.concat({
            shareEscape(guide.name), tostring(guide.minLevel or 1), tostring(guide.maxLevel or 60),
            shareEscape(guide.only), shareEscape(guide.defaultfor), shareEscape(guide.group),
            table.concat(nexts, ","),
        }, ";"))
        for _, step in ipairs(guide.steps or {}) do
            emit("step:" .. table.concat({
                tostring(step.a), tostring(step.q), tostring(step.level or ""),
                shareEscape(step.only), tostring(step.map or ""),
                numberOrEmpty(step.x), numberOrEmpty(step.y), shareEscape(step.npc),
            }, ";"))
        end
        for _, note in ipairs(guide.notes or {}) do emit("note:" .. shareEscape(note)) end
    end
    local questIds = {}
    for q in pairs(titles or {}) do questIds[#questIds + 1] = q end
    table.sort(questIds, function(a, b) return tostring(a) < tostring(b) end)
    for _, q in ipairs(questIds) do emit("title:" .. tostring(q) .. ";" .. shareEscape(titles[q])) end
    emit("E;" .. count)
    local encoded = FP1_PREFIX .. table.concat(records, "|")
    -- Never hand out a string our own importer would reject (RXP parsing is more lenient).
    local ok, err = strictDecode(encoded)
    if not ok then return nil, "Cannot share this route: " .. tostring(err) end
    return encoded
end

-- Legacy FP1@ decode, frozen (SHARE-01/SEC-01): no titles, no validation beyond
-- the known-action filter, silently drops bad steps. Kept only for old strings.
local function legacyDecode(text)
    if type(text) ~= "string" or string.sub(text, 1, #SHARE_PREFIX) ~= SHARE_PREFIX then return nil end
    local guides = {}
    local current
    for part in string.gmatch(string.sub(text, #SHARE_PREFIX + 1), "[^|]+") do
        local fields = splitFields(part)
        if string.sub(part, 1, 5) == "step:" and current then
            local step = {}
            -- fields[1] is "step:<action>"; the remaining fields follow STEP_FIELDS order.
            step.a = string.sub(fields[1], 6)
            -- SEC-01: only accept known actions from share strings
            if step.a ~= "accept" and step.a ~= "turnin" and step.a ~= "complete" then
                step.a = nil
            end
            for index, key in ipairs(STEP_FIELDS) do
                if key ~= "a" then
                    local value = fields[index]
                    if value ~= nil and value ~= "" then
                        if key == "q" or key == "level" or key == "map"
                            or key == "x" or key == "y" then step[key] = tonumber(value)
                        else step[key] = shareUnescape(value) end
                    end
                end
            end
            if step.a and step.q then current.steps[#current.steps + 1] = step end
        else
            current = { name = shareUnescape(fields[1] or ""), minLevel = tonumber(fields[2]) or 1,
                maxLevel = tonumber(fields[3]) or 60, only = shareUnescape(fields[4] or ""),
                defaultfor = shareUnescape(fields[5] or ""), group = shareUnescape(fields[6] or ""),
                next = {}, steps = {} }
            if current.only == "" then current.only = nil end
            if current.defaultfor == "" then current.defaultfor = nil end
            if current.group == "" then current.group = nil end
            for to in string.gmatch(fields[7] or "", "[^,]+") do
                current.next[#current.next + 1] = { to = shareUnescape(to) }
            end
            if current.name ~= "" then guides[#guides + 1] = current end
        end
    end
    return guides
end

-- Dispatch by prefix: legacy FP1@ (frozen), strict !FP:1! (guides, titles, meta or
-- nil, errorMessage), a newer !FP:n! (refused), anything else is not a share string.
function R.DecodeRoute(text)
    if type(text) ~= "string" then return nil end
    if string.sub(text, 1, #SHARE_PREFIX) == SHARE_PREFIX then return legacyDecode(text) end
    if string.sub(text, 1, #FP1_PREFIX) == FP1_PREFIX then return strictDecode(text) end
    if string.match(text, "^!FP:%d+!") then
        return nil, "This route was made by a newer version of ForeverPath"
    end
    return nil
end
