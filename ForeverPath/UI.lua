local _, NS = ...
local U = {}
NS.UI = U
-- Design tokens: every color the UI renders comes from this one table (UPGRADE_PLAN spor D).
U.theme = {
    accent = {0.30, 0.72, 1.00}, muted = {0.64, 0.70, 0.78}, border = {0.18, 0.27, 0.38}, text = {0.90, 0.93, 0.98},
    green = {0.37, 0.84, 0.55}, red = {0.88, 0.42, 0.42}, yellow = {0.93, 0.78, 0.36}, gray = {0.58, 0.63, 0.70},
}
-- Verdict colors: the green/red pair also differs in lightness so hue alone never carries the meaning.
U.theme.verdict = {
    ["Do next"] = U.theme.accent, ["Then"] = U.theme.gray, ["Optional"] = U.theme.gray, ["Ready when you are"] = U.theme.gray,
    ["Side quest"] = U.theme.green, ["Upgrade reward"] = U.theme.green, ["Opens a chain"] = U.theme.accent,
    ["In your log"] = U.theme.yellow, ["Skip"] = U.theme.red, ["Waiting"] = U.theme.yellow,
    ["Higher stat score"] = U.theme.green, ["No stat gain"] = U.theme.gray, ["Cannot use"] = U.theme.red,
    ["Manual comparison"] = U.theme.gray, ["No stat comparison"] = U.theme.gray, ["Inspect"] = U.theme.accent,
    ["Waiting for data"] = U.theme.yellow, ["Waiting for equipped data"] = U.theme.yellow,
}
local accent, muted, border = U.theme.accent, U.theme.muted, U.theme.border
local function verdictColor(verdict)
    local c = U.theme.verdict[verdict] or U.theme.accent
    return c[1], c[2], c[3]
end
U.panels = {}

local function opacity() return tonumber(NS.settings and NS.settings.opacity) or 0.85 end
local function paint(f)
    if f.SetBackdropColor then f:SetBackdropColor(0.025, 0.035, 0.055, opacity() * (f.alphaScale or 1)) end
end
-- alphaScale: cards and overlays sit lighter than the window they are in.
local function panel(parent, name, width, height, alphaScale)
    local f = CreateFrame("Frame", name, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(width, height)
    f.alphaScale = alphaScale
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        f:SetBackdropBorderColor(border[1], border[2], border[3], 0.9)
    end
    paint(f)
    U.panels[#U.panels + 1] = f
    return f
end
local function label(parent, text, size, x, y, width)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f:SetFont(STANDARD_TEXT_FONT, size)
    f:SetPoint("TOPLEFT", x, y)
    f:SetWidth(width)
    f:SetJustifyH("LEFT")
    f:SetTextColor(unpack(U.theme.text))
    f:SetText(text)
    return f
end
local function button(parent, text, x, y, width, action, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height or 28); b:SetPoint("TOPLEFT", x, y)
    local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.09, 0.13, 0.17, 0.85)
    local title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("CENTER"); title:SetTextColor(unpack(accent)); title:SetText(text)
    b.title = title
    b:SetScript("OnEnter", function() bg:SetColorTexture(0.13, 0.24, 0.30, 0.95) end)
    b:SetScript("OnLeave", function() bg:SetColorTexture(0.09, 0.13, 0.17, 0.85) end)
    b:SetScript("OnClick", action)
    return b
end
local function fadeIn(f)
    f:Show()
    if UIFrameFadeIn then UIFrameFadeIn(f, 0.15, 0, 1) end
end
-- Micro-animation (UI-07): eases `apply(frame, value)` from `from` to `to` over
-- `duration` seconds on the frame's own OnUpdate. No libraries, no AnimationGroup:
-- with animations off, or without OnUpdate/GetTime, the end state applies instantly.
local function animate(f, apply, from, to, duration)
    if type(apply) ~= "function" or not f then return end
    if NS.settings.animations == false or not (f.SetScript and GetTime) then
        apply(f, to)
        return
    end
    local start = GetTime()
    f:SetScript("OnUpdate", function(self)
        local progress = math.min(1, (GetTime() - start) / (duration or 0.2))
        apply(self, from + (to - from) * progress)
        if progress >= 1 then self:SetScript("OnUpdate", nil) end
    end)
end
local function draggable(f, key)
    f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); U.Remember(self, key) end)
end

-- Positions are saved as absolute TOPLEFT offsets: re-anchoring to another frame (Minimap) or the
-- client's layout cache can otherwise shift a frame after /reload.
function U.Remember(frame, key)
    local left, top = frame:GetLeft(), frame:GetTop()
    if left and top then NS.settings[key] = { "TOPLEFT", "BOTTOMLEFT", left, top } end
    if frame.SetUserPlaced then frame:SetUserPlaced(false) end
end
function U.Restore(frame, key, ...)
    local pos = NS.settings[key]
    frame:ClearAllPoints()
    if type(pos) == "table" and type(pos[1]) == "string" and type(pos[2]) == "string" and type(pos[3]) == "number" and type(pos[4]) == "number"
        and pcall(frame.SetPoint, frame, pos[1], UIParent, pos[2], pos[3], pos[4]) then return end
    frame:ClearAllPoints()
    frame:SetPoint(...)
end

function U.SetOpacity(value)
    NS.settings.opacity = value
    for _, f in ipairs(U.panels) do paint(f) end
end

function U.Create()
    if U.frame then return end
    local f = panel(UIParent, "ForeverPathWindow", 740, 540)
    U.frame = f
    f:SetFrameStrata("DIALOG")
    f:SetScale(math.min(1, UIParent:GetWidth()/780, UIParent:GetHeight()/580))
    draggable(f, "position")
    U.Restore(f, "position", "CENTER")
    table.insert(UISpecialFrames, "ForeverPathWindow")
    local stripe = f:CreateTexture(nil,"ARTWORK"); stripe:SetPoint("TOPLEFT",1,-1); stripe:SetSize(738,3); stripe:SetColorTexture(unpack(accent))
    label(f,"FOREVERPATH",22,24,-24,440)
    U.subtitle = label(f,"Your next step, explained.",12,24,-54,500); U.subtitle:SetTextColor(unpack(muted))
    button(f,"Setup",398,-20,90,function() U.Setup() end)
    button(f,"Settings",494,-20,88,function() U.Settings() end)
    button(f,"Diagnostics",588,-20,110,function() U.Diagnostics() end)
    button(f,"X",704,-20,34,function() f:Hide() end)
    U.banner = label(f,"",13,24,-88,690)
    U.context = label(f,"",12,24,-111,690); U.context:SetTextColor(unpack(muted))
    U.profile = button(f,"Choose profile",24,-138,230,function() NS.CycleProfile() end)
    U.goal = button(f,"Playstyle: Balanced",266,-138,220,function() NS.CycleStyle() end)
    button(f,"Compact",498,-138,106,function() U.ToggleCompact() end)
    U.refresh = button(f,"Refresh",616,-138,100,function() NS.Refresh() end)
    -- Route position: label + fill bar between the controls and the card list.
    U.progressLabel = label(f,"",11,24,-170,664); U.progressLabel:SetTextColor(unpack(muted))
    U.progress = CreateFrame("Frame",nil,f)
    U.progress:SetPoint("TOPLEFT",24,-184); U.progress:SetSize(664,6)
    U.progress.background = U.progress:CreateTexture(nil,"BACKGROUND")
    U.progress.background:SetAllPoints(); U.progress.background:SetColorTexture(0.05,0.08,0.12,0.9)
    U.progress.fill = U.progress:CreateTexture(nil,"ARTWORK")
    U.progress.fill:SetPoint("TOPLEFT"); U.progress.fill:SetHeight(6); U.progress.fill:SetTexture(unpack(accent))
    U.progress:Hide()
    -- Hero (NAA-01): the one next step, big. Sits between the route progress and
    -- the card list; U.Render fills it from the first "Do next" row (or rows[1]).
    U.hero = panel(f, "ForeverPathHero", 664, 90, 0.8)
    U.hero:SetPoint("TOPLEFT", 24, -198)
    if U.hero.SetBackdropBorderColor then U.hero:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.9) end
    U.hero.title = label(U.hero, "", 20, 16, -14, 524)
    U.hero.reason = label(U.hero, "", 12, 16, -46, 524); U.hero.reason:SetTextColor(unpack(muted))
    U.hero.way = button(U.hero, "Show way", 552, -12, 96, function() if U.hero.row then NS.Nav.Pin(U.hero.row) end end, 26)
    U.hero.distance = label(U.hero, "", 12, 552, -46, 96); U.hero.distance:SetTextColor(unpack(accent))
    local heroElapsed = 0
    U.hero:SetScript("OnUpdate", function(_, delta)
        heroElapsed = heroElapsed + (delta or 0)
        if heroElapsed >= 0.25 then heroElapsed = 0; U.UpdateHeroDistance() end
    end)
    U.hero:Hide()
    -- Upgrade finder section (spor C): best available quest reward per slot.
    U.upgradeHeader = label(f,"UPGRADES AVAILABLE NOW",12,24,-304,664)
    U.upgradeHeader:SetTextColor(unpack(U.theme.green))
    U.upgradeSlots = {}
    U.upgradeDetails = {}
    for i = 1, 3 do
        U.upgradeSlots[i] = label(f,"",12,24,-318 - (i - 1) * 16,90)
        U.upgradeSlots[i]:SetTextColor(unpack(U.theme.green))
        U.upgradeDetails[i] = label(f,"",12,118,-318 - (i - 1) * 16,570)
    end
    U.upgradeHeader:Hide()
    local scroll = CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",24,-296); scroll:SetPoint("BOTTOMRIGHT",-40,40)
    U.child = CreateFrame("Frame",nil,scroll); U.child:SetSize(664,1); scroll:SetScrollChild(U.child)
    U.scroll, U.cards = scroll, {}
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = meta and meta("ForeverPath", "Version") or ""
    U.footer = label(f,"ForeverPath " .. tostring(version or "") .. " | /fp help | Route: RestedXP | Quests: AllTheThings",11,24,-502,690)
    U.footer:SetTextColor(unpack(muted))
    U.sessionLine = label(f,"",11,24,-516,690)
    U.sessionLine:SetTextColor(unpack(U.theme.green))
    U.cpuLine = label(f,"",11,24,-530,690)
    U.cpuLine:SetTextColor(unpack(muted))
    f:Hide()
end

local function card(index)
    if U.cards[index] then return U.cards[index] end
    local f = panel(U.child,nil,664,110,0.7)
    f.icon = f:CreateTexture(nil,"ARTWORK")
    f.icon:SetSize(34,34); f.icon:SetPoint("TOPLEFT",12,-10)
    f.icon:SetTexCoord(0.08,0.92,0.08,0.92); f.icon:Hide()
    f.title = label(f,"",15,54,-12,400)
    f.badge = label(f,"",11,458,-14,190); f.badge:SetJustifyH("RIGHT")
    f.body = label(f,"",12,54,-38,480); f.body:SetJustifyV("TOP")
    f.way = button(f,"Show way",548,-38,100,function() if f.row then NS.Nav.Pin(f.row) end end, 24)
    f:EnableMouse(true)
    f:SetScript("OnEnter",function(self)
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.9) end
        if self.link and GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetHyperlink(self.link); GameTooltip:Show() end
    end)
    f:SetScript("OnLeave",function(self)
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(border[1], border[2], border[3], 0.9) end
        if GameTooltip then GameTooltip:Hide() end
    end)
    -- Clicking a card asks "says who?": the provenance popover (spor B).
    f:SetScript("OnMouseUp",function(self) if self.row then U.Provenance(self.row, self) end end)
    U.cards[index] = f
    return f
end

-- Pure: one readable line per provenance record. No records means the row was read
-- live from the game client, which is its own kind of source.
local SOURCE_NAMES = { ATT = "AllTheThings", RXPGuides = "RestedXP Guides" }
function U.ProvenanceLines(row)
    local lines = {}
    local records = type(row) == "table" and row.provenance
    if type(records) == "table" then
        for _, p in ipairs(records) do
            if type(p) == "table" then
                local parts = {}
                local source = SOURCE_NAMES[p.source] or p.source
                if source then parts[#parts + 1] = tostring(source) end
                local commit = p.commit or p.attCommit
                if commit then parts[#parts + 1] = "commit " .. tostring(commit):sub(1, 7) end
                if p.build then parts[#parts + 1] = "build " .. tostring(p.build) end
                if p.retrieved then parts[#parts + 1] = "retrieved " .. tostring(p.retrieved) end
                if p.evidence and p.evidence ~= "verified" then
                    parts[#parts] = parts[#parts] .. " (" .. tostring(p.evidence) .. ")"
                end
                if #parts > 0 then lines[#lines + 1] = table.concat(parts, " · ") end
            end
        end
    end
    if #lines == 0 then lines[#lines + 1] = "Read live from the game client" end
    return lines
end

function U.Provenance(row, anchor)
    if not U.prov then
        local f = panel(UIParent, "ForeverPathProvenance", 340, 120, 0.9)
        U.prov = f
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetClampedToScreen(true)
        table.insert(UISpecialFrames, "ForeverPathProvenance")  -- Esc closes
        label(f, "SOURCE — why we trust this", 12, 14, -10, 300):SetTextColor(unpack(U.theme.green))
        U.prov.lines = {}
        for i = 1, 4 do U.prov.lines[i] = label(f, "", 12, 14, -28 - (i - 1) * 16, 310) end
        local hint = label(f, "Click the popover to close", 10, 14, -98, 300)
        hint:SetTextColor(unpack(muted))
        f:EnableMouse(true)
        f:SetScript("OnMouseUp", function(self) self:Hide() end)
    end
    local lines = U.ProvenanceLines(row)
    for i = 1, 4 do
        if lines[i] then U.prov.lines[i]:SetText(lines[i]); U.prov.lines[i]:Show() else U.prov.lines[i]:Hide() end
    end
    U.prov:ClearAllPoints()
    U.prov:SetPoint("TOPLEFT", anchor or UIParent, "TOPRIGHT", 8, 0)
    fadeIn(U.prov)
end

-- The hero explains the single next step: the first "Do next" row, falling back to
-- rows[1] so the panel still shows the top suggestion when no row has that verdict.
local function heroPick(rows, mode)
    if mode == "rewards" then return nil end
    for _, row in ipairs(rows) do
        if row.verdict == "Do next" then return row end
    end
    return rows[1]
end

-- Yards to the hero step, but only while the arrow actually points at that step:
-- when the followed or pinned step is a different row, a distance would describe
-- the wrong target, so the hero shows none.
local function heroDistance(row)
    if not (row and row.target and NS.Nav and NS.Nav.DistanceText) then return nil end
    local followed = NS.Nav.target
    if not followed or row.target.map ~= followed.map
        or math.abs((row.target.x or 0) - (followed.x or 0)) > 0.05
        or math.abs((row.target.y or 0) - (followed.y or 0)) > 0.05 then return nil end
    return NS.Nav.DistanceText()
end

function U.UpdateHeroDistance()
    if U.hero then U.hero.distance:SetText(heroDistance(U.hero.row) or "") end
end

-- Pure: compact text that never comes back empty. Long text is truncated with an
-- ellipsis so the card keeps its height; the distance chip joins the reason line.
function U.CompactText(row, message)
    local title, reason
    if type(row) == "table" then
        title = tostring(row.title or "Next step")
        reason = tostring((row.reasons or {})[1] or row.verdict or "")
    else
        title = "ForeverPath"
        reason = tostring(message or "")
    end
    if #reason == 0 then reason = "No suggestions for you here yet - open /fp" end
    if #title > 34 then title = string.sub(title, 1, 33) .. "..." end
    if #reason > 60 then reason = string.sub(reason, 1, 59) .. "..." end
    local distance = type(row) == "table" and row.target and heroDistance(row)
    if distance and #reason + #distance + 3 <= 63 then reason = reason .. " · " .. distance end
    return title, reason
end

-- Everything inside pcall: a client-specific error must leave a visible card,
-- never an empty one (BUG-01).
local function renderCompact(rows, state)
    local h = U.hud
    if not h then return end
    local first = rows[1]
    local ok, title, reason = pcall(U.CompactText, first, state.message)
    if not ok then
        title, reason = "Compact error", "Send us /fp diag"
        if NS.Client and NS.Client.errors then NS.Client.errors.last = "compact: " .. tostring(title) end
    end
    if h.title.lastText ~= title then
        h.title:SetText(title); h.title.lastText = title
        animate(h.title, function(target, value) target:SetAlpha(value) end, 0.35, 1, 0.15)
    end
    if h.reason.lastText ~= reason then
        h.reason:SetText(reason); h.reason.lastText = reason
        animate(h.reason, function(target, value) target:SetAlpha(value) end, 0.35, 1, 0.15)
    end
    local color = first and U.theme.verdict[first.verdict] or U.theme.accent
    h.stripe:SetColorTexture(color[1], color[2], color[3])
    local icon = first and (first.icon or first.texture)
    if icon and icon ~= "" then h.icon:SetTexture(icon); h.icon:Show() else h.icon:Hide() end
end

-- The upgrade section sits between the hero and the card list; when it is shown the
-- card list starts lower. Pure display selection: rows come from Engine.BestUpgrades.
local function renderUpgrades(state)
    local upgrades = (state.mode ~= "rewards" and type(state.upgrades) == "table") and state.upgrades or {}
    if #upgrades == 0 then
        U.upgradeHeader:Hide()
        for i = 1, 3 do U.upgradeSlots[i]:Hide(); U.upgradeDetails[i]:Hide() end
        U.scroll:ClearAllPoints(); U.scroll:SetPoint("TOPLEFT",24,-296)
        return
    end
    U.upgradeHeader:Show()
    for i = 1, 3 do
        local row = upgrades[i]
        if row then
            local detail = row.percent and string.format("+%d%%  %s (+%.1f)", row.percent, row.title, row.delta)
                or string.format("%s (+%.1f)", row.title, row.delta)
            if #detail > 92 then detail = string.sub(detail, 1, 91) .. "..." end
            if U.upgradeSlots[i].lastText ~= row.slot then U.upgradeSlots[i]:SetText(row.slot); U.upgradeSlots[i].lastText = row.slot end
            if U.upgradeDetails[i].lastText ~= detail then U.upgradeDetails[i]:SetText(detail); U.upgradeDetails[i].lastText = detail end
            U.upgradeSlots[i]:Show(); U.upgradeDetails[i]:Show()
        else
            U.upgradeSlots[i]:Hide(); U.upgradeDetails[i]:Hide()
        end
    end
    U.scroll:ClearAllPoints(); U.scroll:SetPoint("TOPLEFT",24,-372)
end

function U.Render(state)
    U.Create()
    U.lastState = state
    U.banner:SetText(state.mode == "rewards" and "QUEST DIALOGUE - COMPARE REWARDS" or "WHAT TO DO NEXT")
    U.context:SetText(string.format("Level %s | %s | %s quests in log | %s%s",state.level or "?",state.zone or "?",state.questCount or 0,
        state.questTitle or "Next quests for you", state.updated and (" | Updated " .. state.updated) or ""))
    local profile = NS.Engine.profiles[NS.settings.profile]
    U.profile.title:SetText("Profile: " .. (state.profileLabel or (profile and profile.label) or "automatic"))
    U.goal.title:SetText("Playstyle: " .. (NS.Route.labels[NS.settings.style] or "Balanced"))
    U.goal:SetEnabled(true)
    local rows = state.rows or {}
    local stepRow
    for _, row in ipairs(rows) do
        if row.stepTotal and row.stepTotal > 0 then stepRow = row break end
    end
    if stepRow then
        U.progress:Show()
        U.progressLabel:SetText(string.format("Route: %s — step %d of %d", stepRow.guideName or "?", stepRow.stepIndex or 0, stepRow.stepTotal))
        local target = 664 * math.min(1, math.max(0, (stepRow.stepIndex or 1) / stepRow.stepTotal))
        local key = stepRow.guideName .. ":" .. stepRow.stepIndex
        if U.progress.lastKey ~= key then
            animate(U.progress.fill, function(f, value) f:SetWidth(value) end, U.progress.lastWidth or 0, target, 0.4)
            U.progress.lastKey, U.progress.lastWidth = key, target
        end
    else
        U.progress:Hide()
        U.progressLabel:SetText("")
    end
    local hero = heroPick(rows, state.mode)
    if hero then
        if U.hero.lastRowId ~= hero.id then
            animate(U.hero.title, function(target, value) target:SetAlpha(value) end, 0.25, 1, 0.18)
            animate(U.hero.reason, function(target, value) target:SetAlpha(value) end, 0.25, 1, 0.18)
            U.hero.lastRowId = hero.id
        end
        U.hero.row = hero
        U.hero.title:SetText(hero.title or "")
        U.hero.reason:SetText((hero.reasons or {})[1] or "")
        if hero.target then U.hero.way:Show() else U.hero.way:Hide() end
        U.hero:Show()
        U.UpdateHeroDistance()
    else
        U.hero.row = nil
        U.hero:Hide()
    end
    local y = 0
    for i = 1, math.max(1,#rows) do
        local row = rows[i]
        local c = card(i)
        c.title:SetText(row and row.title or "Ready when you are")
        c.badge:SetText(row and row.verdict or "Waiting")
        c.badge:SetTextColor(verdictColor(row and row.verdict or "Waiting"))
        c.title:SetTextColor(unpack(row and row.verdict == "Skip" and U.theme.muted or U.theme.text))
        c.body:SetText(row and table.concat(row.reasons or {},"\n") or state.message or "No suggestions yet.")
        c.link = row and row.link or nil
        c.row = row
        if c.lastRowId ~= (row and row.id or nil) then
            animate(c, function(target, value) target:SetAlpha(value) end, 0, 1, 0.15)
            c.lastRowId = row and row.id or nil
        end
        if row and row.target then c.way:Show() else c.way:Hide() end
        -- The item icon (when known) sits left of the text; without one the text keeps the full width.
        local icon = row and (row.icon or row.texture)
        if icon and icon ~= "" then
            c.icon:SetTexture(icon); c.icon:Show()
            c.title:ClearAllPoints(); c.title:SetPoint("TOPLEFT",54,-12); c.title:SetWidth(400)
            c.body:ClearAllPoints(); c.body:SetPoint("TOPLEFT",54,-38); c.body:SetWidth(480)
        else
            c.icon:Hide()
            c.title:ClearAllPoints(); c.title:SetPoint("TOPLEFT",16,-12); c.title:SetWidth(440)
            c.body:ClearAllPoints(); c.body:SetPoint("TOPLEFT",16,-38); c.body:SetWidth(520)
        end
        -- Cards grow with their explanation instead of clipping it.
        local textHeight = c.body.GetStringHeight and c.body:GetStringHeight() or 56
        local height = 50 + math.max(28, textHeight)
        c.body:SetHeight(textHeight)
        c:SetHeight(height)
        c:ClearAllPoints(); c:SetPoint("TOPLEFT", 0, -y)
        y = y + height + 8
        c:Show()
    end
    for i = math.max(1,#rows)+1,#U.cards do U.cards[i]:Hide() end
    U.child:SetHeight(math.max(1, y))
    renderUpgrades(state)
    local offset = U.scroll:GetVerticalScroll()
    U.scroll:SetVerticalScroll(math.min(offset,math.max(0,U.child:GetHeight()-U.scroll:GetHeight())))
    renderCompact(rows, state)
    if U.sessionLine then
        local stats = NS.Engine.SessionStats(NS.Client.session, GetTime and GetTime() or 0)
        local text = string.format("Session: %d XP/h | %d quest(s) done", stats.xph or 0, stats.quests or 0)
        if stats.toLevelText then text = text .. " | " .. stats.toLevelText .. " to level" end
        if U.sessionLine.lastText ~= text then U.sessionLine:SetText(text); U.sessionLine.lastText = text end
    end
    if U.cpuLine then
        -- Throttled inside C.CPUTime; on refresh ticks only (never per frame).
        local seconds, note = NS.Client.CPUTime()
        local text = seconds and string.format("CPU: %.2fs since load", seconds) or ("CPU: " .. tostring(note or "unknown"))
        if U.cpuLine.lastText ~= text then U.cpuLine:SetText(text); U.cpuLine.lastText = text end
    end
end

function U.Toggle()
    U.Create()
    if U.frame:IsShown() then U.frame:Hide() else fadeIn(U.frame); NS.Refresh() end
end

-- The compact card stays open across sessions until it is closed with its X.
function U.Compact(show)
    if show and not U.hud then
        local h = panel(UIParent,"ForeverPathCompact",330,52,0.8)
        U.hud = h
        draggable(h, "compactPosition")
        if Minimap then U.Restore(h, "compactPosition", "TOP", Minimap, "BOTTOM", 0, -18)
        else U.Restore(h, "compactPosition", "TOP", UIParent, "TOP", 0, -120) end
        -- Verdict-colored status stripe: the card's state is readable before any text.
        h.stripe = h:CreateTexture(nil,"ARTWORK")
        h.stripe:SetSize(3,52); h.stripe:SetPoint("TOPLEFT",0,0)
        h.stripe:SetColorTexture(unpack(accent))
        h.icon = h:CreateTexture(nil,"ARTWORK")
        h.icon:SetSize(26,26); h.icon:SetPoint("TOPLEFT",12,-8)
        h.icon:SetTexCoord(0.08,0.92,0.08,0.92); h.icon:Hide()
        h.title = label(h,"ForeverPath",13,46,-7,200)
        h.reason = label(h,"",11,46,-25,200); h.reason:SetTextColor(unpack(muted))
        h.dismiss = button(h,"Hide",254,-6,44,function() local row = U.lastState and U.lastState.rows and U.lastState.rows[1]; if row then NS.DismissTip(row) end end, 20)
        h.close = button(h,"X",302,-6,22,function() U.Compact(false) end, 20)
        -- Clicking the card opens the main window; right-click dismisses the tip.
        h:SetScript("OnMouseUp",function(_, mouseButton)
            if mouseButton == "RightButton" then
                local row = U.lastState and U.lastState.rows and U.lastState.rows[1]
                if row then NS.DismissTip(row) end
            else U.Toggle() end
        end)
    end
    if not U.hud then return end
    NS.settings.compact = show and true or false
    if show then fadeIn(U.hud); NS.Refresh() else U.hud:Hide() end
end
function U.ToggleCompact()
    U.Compact(not (U.hud and U.hud:IsShown()))
end

-- Custom route import (ROUTE-01): paste your own RestedXP-format route; it stays
-- in this account's SavedVariables and wins over shipped guides.

-- Pure: a working, commented example in the exact format the parser accepts.
-- Doubling as living format documentation for the import window (ROUTE-02).
function U.RouteExample()
    return table.concat({
        "RXPGuides.RegisterGuide([[",
        "#group RestedXP Forever Dungeon Guide (H)   -- Dungeon group = dungeon playstyle",
        "<< Horde",
        "#name 10-20 My Launch Route",
        "#defaultfor Troll/Orc",
        "#next 20-30 The Next Leg",
        "",
        "step",
        "    .goto 1411,43.3,68.5    -- map id, x, y as map percent",
        "    >>Talk to Kaltunk",
        "    .accept 4641 >>Accept Your Place In The World",
        "    .target Kaltunk",
        "step",
        "    .xp 12",
        "    .turnin 4641 >>Turn in Your Place In The World",
        "]])",
        "\n",
    }, "\n")
end

function U.RouteImport()
    if not U.routeWin then
        local f = panel(UIParent, "ForeverPathRouteImport", 660, 440)
        U.routeWin = f
        f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetClampedToScreen(true)
        table.insert(UISpecialFrames, "ForeverPathRouteImport")
        label(f, "IMPORT YOUR ROUTE - RestedXP guide format", 16, 18, -20, 600)
        local hint = label(f, "Paste RegisterGuide blocks with .accept/.turnin/.complete steps. Map-percent .goto works (1411,43.3,68.5). Stays on this computer.", 11, 18, -44, 620)
        hint:SetTextColor(unpack(muted))
        button(f, "X", 610, -14, 30, function() f:Hide() end)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 18, -64); scroll:SetPoint("BOTTOMRIGHT", -36, -80)
        local edit = CreateFrame("EditBox", nil, scroll); f.edit = edit
        edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject(ChatFontNormal); edit:SetWidth(590); edit:SetHeight(280)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(edit)
        f.status = label(f, "", 12, 18, -384, 620); f.status:SetTextColor(unpack(U.theme.green))
        f.exampleBtn = button(f, "Insert example", 18, -404, 150, function() f.edit:SetText(U.RouteExample()) end)
        f.importBtn = button(f, "Import", 176, -404, 120, function() NS.ImportRoute(f.edit:GetText()) end)
        f.shareBtn = button(f, "Copy share string", 304, -404, 150, function()
            local shared = NS.Route.EncodeRoute()
            f.edit:SetText(shared or "No custom route to share yet - import one first")
        end)
        f.removeBtn = button(f, "Remove", 462, -404, 120, function() NS.ImportRoute(nil); f.edit:SetText("") end)
    end
    U.routeWin.edit:SetText(NS.settings.customRouteText or "")
    fadeIn(U.routeWin)
end

-- What the compact card last showed, for Diagnostics: makes "it showed nothing"
-- diagnosable from a /fp diag paste instead of guesswork (BUG-01).
function U.CompactDiagnostics()
    local h = U.hud
    if not h then return "Compact: not created" end
    local shown = h.IsShown and h:IsShown() and "shown" or "hidden"
    local state = U.lastState or {}
    local rows = state.rows or {}
    local first = rows[1]
    local titleText = h.title and ((h.title.GetText and h.title:GetText()) or h.title.text) or "?"
    return string.format("Compact: %s, mode %s, %d row(s), top '%s', title '%s' (%d chars), icon %s | STANDARD_TEXT_FONT: %s",
        shown, tostring(state.mode or "?"), #rows, tostring(first and first.title or "-"),
        tostring(titleText), #tostring(titleText),
        h.icon and h.icon:IsShown() and "yes" or "no",
        STANDARD_TEXT_FONT and "yes" or "MISSING")
end

local CHOICES = {
    { "speed", "Speedrun to 60", "Follow the RestedXP speedrun route. Side quests only when they give you a gear upgrade." },
    { "balanced", "Balanced", "The route, plus side quests with a good reward or a follow-up chain." },
    { "gear", "Gear first", "The route, plus every quest in your zone that improves your gear." },
    { "story", "The world as Blizzard made it", "The route as a guide, plus every quest and story in your zone. Nothing is marked Skip." },
    { "dungeon", "Dungeon leveling", "Follow the RestedXP dungeon routes (runs dungeons while leveling). Side quests only for gear upgrades." },
}
function U.Setup()
    if not U.setup then
        local f = panel(UIParent,"ForeverPathSetup",480,430)
        U.setup = f
        f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetPoint("CENTER")
        draggable(f, "setupPosition")
        table.insert(UISpecialFrames,"ForeverPathSetup")
        label(f,"How do you want to play?",18,22,-20,420)
        local hint = label(f,"You can change this any time with the Playstyle button or /fp style.",11,22,-46,436); hint:SetTextColor(unpack(muted))
        f.choices = {}
        for i, choice in ipairs(CHOICES) do
            local style = choice[1]
            local b = button(f,"",22,-72 - (i - 1) * 68,436,function()
                NS.SetStyle(style)
                NS.settings.setupDone = true
                f:Hide()
                if NS.settings.compact ~= false then U.Compact(true) end
            end, 60)
            b.title:ClearAllPoints(); b.title:SetPoint("TOPLEFT", 12, -10); b.title:SetText(choice[2])
            local desc = label(b,choice[3],11,12,-30,412); desc:SetTextColor(unpack(muted))
            f.choices[style] = b
        end
    end
    fadeIn(U.setup)
end

function U.Diagnostics()
    if not U.report then
        local f = panel(UIParent,"ForeverPathDiagnostics",660,440); U.report = f
        f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetClampedToScreen(true)
        table.insert(UISpecialFrames,"ForeverPathDiagnostics")
        label(f,"DIAGNOSTICS - Ctrl/Cmd+A, then copy",16,18,-20,600)
        button(f,"X",610,-14,30,function() f:Hide() end)
        local scroll = CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",18,-60); scroll:SetPoint("BOTTOMRIGHT",-36,24)
        local edit = CreateFrame("EditBox",nil,scroll); f.edit = edit
        edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject(ChatFontNormal); edit:SetWidth(590); edit:SetHeight(340)
        edit:SetScript("OnEscapePressed",function() f:Hide() end)
        scroll:SetScrollChild(edit)
    end
    U.report.edit:SetText(NS.Client.Diagnostics()); U.report:Show(); U.report.edit:SetFocus(); U.report.edit:HighlightText()
end

-- Settings panel: every /fp setting reachable without slash. Controls call the same
-- NS.SetStyle / NS.UI.SetOpacity functions as the slash commands (one source of truth).
local STYLE_LABELS = { speed = "Speedrun", balanced = "Balanced", gear = "Gear first", story = "Story" }

function U.SyncSettings(f)
    for style, b in pairs(f.styles) do
        local active = NS.settings.style == style
        b.title:SetTextColor(active and unpack(U.theme.accent) or unpack(U.theme.muted))
    end
    local _, class
    if UnitClass then _, class = UnitClass("player") end
    local specs = NS.Engine.SpecsFor(class or "", UnitLevel and UnitLevel("player") or 0)
    for _, b in ipairs(f.specButtons or {}) do b:Hide() end
    f.specButtons = {}
    if #specs > 0 then
        f.specLabel:SetText("Spec (stat weights): " .. (#specs + 1) .. " choices")
        for i, spec in ipairs(specs) do
            local b = button(f, spec, 22 + ((i - 1) % 4) * 108, -232 - math.floor((i - 1) / 4) * 32, 104, function()
                NS.SetSpec(spec); U.SyncSettings(f)
            end, 26)
            local active = string.lower(NS.settings.spec or "") == string.lower(spec)
            b.title:SetTextColor(active and unpack(U.theme.accent) or unpack(U.theme.muted))
            f.specButtons[#f.specButtons + 1] = b
        end
    else
        f.specLabel:SetText("Spec (stat weights): no imported specs for your class")
    end
    local anySpec = #specs == 0 or string.lower(NS.settings.spec or "") == ""
    f.autoSpec.title:SetTextColor(anySpec and unpack(U.theme.accent) or unpack(U.theme.muted))
    f.arrow.title:SetText("Arrow: " .. (NS.settings.arrow == false and "off" or "on"))
    f.compact.title:SetText("Tips card: " .. (NS.settings.compact == false and "off" or "on"))
    f.animations.title:SetText("Animations: " .. (NS.settings.animations == false and "off" or "on"))
    f.opacityValue:SetText(tostring(math.floor((NS.settings.opacity or 0.85) * 100 + 0.5)) .. "%")
    f.throttleValue:SetText(tostring(NS.settings.tipThrottleSeconds or 10) .. "s")
end

function U.Settings()
    if not U.settings then
        local f = panel(UIParent,"ForeverPathSettings",480,470)
        U.settings = f
        f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetPoint("CENTER"); f:SetClampedToScreen(true)
        draggable(f, "settingsPosition")
        table.insert(UISpecialFrames,"ForeverPathSettings")
        label(f,"Settings",18,22,-20,300)
        local hint = label(f,"Everything the slash commands do, without the slash.",11,22,-44,380)
        hint:SetTextColor(unpack(muted))
        button(f,"X",430,-14,30,function() f:Hide() end)
        label(f,"Playstyle",13,22,-76,240)
        f.styles = {}
        for i, style in ipairs(NS.Route.order) do
            local b = button(f, STYLE_LABELS[style] or style, 22 + (i - 1) * 92, -98, 88, function()
                NS.SetStyle(style); U.SyncSettings(f)
            end)
            f.styles[style] = b
        end
        f.specLabel = label(f,"",12,22,-140,436); f.specLabel:SetTextColor(unpack(muted))
        f.autoSpec = button(f,"Automatic",22,-160,104,function()
            NS.settings.spec = nil; NS.Refresh(); U.SyncSettings(f)
        end, 26)
        label(f,"Display",13,22,-200,240)
        f.arrow = button(f,"Arrow: on",22,-222,104,function()
            NS.settings.arrow = NS.settings.arrow == false
            NS.Refresh(); U.SyncSettings(f)
        end, 26)
        f.compact = button(f,"Tips card: on",134,-222,104,function()
            U.ToggleCompact(); U.SyncSettings(f)
        end, 26)
        f.animations = button(f,"Animations: on",22,-252,150,function()
            NS.settings.animations = NS.settings.animations == false
            U.SyncSettings(f)
        end, 26)
        label(f,"Opacity",12,258,-214,100)
        f.opacityMinus = button(f,"-",246,-222,22,function()
            U.SetOpacity(math.max(0.30, (NS.settings.opacity or 0.85) - 0.10)); U.SyncSettings(f)
        end, 26)
        f.opacityValue = label(f,"85%",12,272,-214,60)
        f.opacityPlus = button(f,"+",330,-222,22,function()
            U.SetOpacity(math.min(1.0, (NS.settings.opacity or 0.85) + 0.10)); U.SyncSettings(f)
        end, 26)
        label(f,"Tip delay",12,364,-214,100)
        f.throttleMinus = button(f,"-",352,-222,22,function()
            NS.settings.tipThrottleSeconds = math.max(0, (tonumber(NS.settings.tipThrottleSeconds) or 10) - 5)
            U.SyncSettings(f)
        end, 26)
        f.throttleValue = label(f,"10s",12,378,-214,44)
        f.throttlePlus = button(f,"+",430,-222,22,function()
            NS.settings.tipThrottleSeconds = math.min(60, (tonumber(NS.settings.tipThrottleSeconds) or 10) + 5)
            U.SyncSettings(f)
        end, 26)
        label(f,"Positions",13,22,-266,240)
        button(f,"Reset all window positions",22,-288,220,function()
            NS.ResetPositions(); U.SyncSettings(f)
        end, 26)
        local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
        local version = tostring(meta and meta("ForeverPath", "Version") or "")
        local sources = label(f,"ForeverPath " .. version .. " | Route: RestedXP | Quests: AllTheThings",11,22,-444,436)
        sources:SetTextColor(unpack(muted))
    end
    U.SyncSettings(U.settings)
    fadeIn(U.settings)
end

-- Minimap button: left-click the main window, right-click the tips card, drag around the ring.
-- The angle is stored in settings; the default (east side) stays clear of the compact card
-- that anchors directly below the minimap (the #17 lesson).
U.DEFAULT_MINIMAP_ANGLE = 0
local MINIMAP_RING = 80

-- Pure: button-center offset from the minimap center for an angle in degrees (0 = east).
function U.MinimapOffset(radius, angle)
    local radians = math.rad(angle)
    return math.cos(radians) * radius, math.sin(radians) * radius
end

function U.PlaceMinimap()
    local b = U.minimap
    if not b or not Minimap then return end
    local x, y = U.MinimapOffset(MINIMAP_RING, tonumber(NS.settings.minimapAngle) or U.DEFAULT_MINIMAP_ANGLE)
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function U.Minimap()
    if U.minimap or not Minimap then return U.minimap end
    local b = CreateFrame("Button", "ForeverPathMinimap", Minimap, BackdropTemplateMixin and "BackdropTemplate" or nil)
    U.minimap = b
    b:SetSize(30, 30)
    b:SetFrameStrata("MEDIUM")
    b:SetMovable(true)
    b:EnableMouse(true)
    b:RegisterForDrag("LeftButton")
    if b.SetBackdrop then
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        b:SetBackdropColor(0.02, 0.03, 0.05, 0.85)
        b:SetBackdropBorderColor(border[1], border[2], border[3], 0.9)
    end
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture("Interface\\Minimap\\MinimapArrow")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("CENTER")
    b:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then U.ToggleCompact() else U.Toggle() end
    end)
    -- Ring drag: while held, the button follows the cursor's angle around the minimap.
    b:SetScript("OnDragStart", function()
        b:SetScript("OnUpdate", function()
            if not (GetCursorPosition and Minimap.GetCenter and Minimap.GetEffectiveScale) then return end
            local okScale, scale = pcall(Minimap.GetEffectiveScale, Minimap)
            local okCursor, px, py = pcall(GetCursorPosition)
            local okCenter, cx, cy = pcall(Minimap.GetCenter, Minimap)
            if not (okScale and okCursor and okCenter) or not (scale and px and py and cx) then return end
            local angle = math.deg(math.atan2(py / scale - cy, px / scale - cx))
            NS.settings.minimapAngle = angle
            U.PlaceMinimap()
        end)
    end)
    b:SetScript("OnDragStop", function() b:SetScript("OnUpdate", nil) end)
    U.PlaceMinimap()
    return b
end
