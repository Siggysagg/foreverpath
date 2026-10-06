local _, NS = ...
local U = {}
NS.UI = U
-- Design tokens (UPGRADE_PLAN spor D): every color the UI renders comes from this
-- one table. Roles, not moods: bg < bgCard < bgRaised for depth, text > textDim >
-- textMuted for hierarchy, one accent family, and the semantic colors carry only
-- meaning (green = good/ready, yellow = waiting, red = cannot use).
U.theme = {
    accent       = {0.30, 0.72, 1.00},
    accentDim    = {0.13, 0.34, 0.52},   -- glow, separators, primary-button fill
    bg           = {0.02, 0.03, 0.05},   -- window base
    bgCard       = {0.055, 0.075, 0.11}, -- cards and list rows
    bgRaised     = {0.085, 0.11, 0.155}, -- buttons and the hero panel
    bgTrack      = {0.05, 0.08, 0.12},   -- progress track, recessed wells
    border       = {0.16, 0.22, 0.30},
    borderAlpha  = 0.55,
    borderStrong = {0.32, 0.44, 0.56},   -- hover edges
    text         = {0.95, 0.97, 1.00},
    textDim      = {0.80, 0.85, 0.92},
    textMuted    = {0.62, 0.68, 0.78},
    muted        = {0.62, 0.68, 0.78},   -- legacy alias (kept: older call sites/tests)
    green = {0.35, 0.85, 0.55}, red = {0.92, 0.45, 0.45}, yellow = {0.95, 0.80, 0.40}, gray = {0.58, 0.63, 0.70},
}
-- Type scale: one size per role — window title 18, page titles 16, the NOW
-- headline 14, body 12, hints and metadata 11, chips and tab glyphs 10.
U.type = { title = 18, page = 16, headline = 14, body = 12, small = 11, tiny = 10 }
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

-- Streaks (MILE-01/#200): a death breaks the quest row. PLAYER_DEAD has no other
-- consumer, so one frame listens for it here and only raises a flag — every
-- decision about the streak lives in the pure Engine.Streak.
if CreateFrame then
    local deathFrame = CreateFrame("Frame")
    U.deathFrame = deathFrame
    pcall(deathFrame.RegisterEvent, deathFrame, "PLAYER_DEAD")
    deathFrame:SetScript("OnEvent", function() U.diedSinceLastQuest = true end)
end

local function opacity() return tonumber(NS.settings and NS.settings.opacity) or 0.85 end
local function paint(f)
    if f.SetBackdropColor then
        local bg = f.alphaScale and f.alphaScale < 1 and U.theme.bgCard or U.theme.bg
        f:SetBackdropColor(bg[1], bg[2], bg[3], opacity() * (f.alphaScale or 1))
    end
end
-- alphaScale: cards and overlays sit lighter than the window they are in.
local function panel(parent, name, width, height, alphaScale)
    local f = CreateFrame("Frame", name, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(width, height)
    f.alphaScale = alphaScale
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        f:SetBackdropBorderColor(U.theme.border[1], U.theme.border[2], U.theme.border[3], U.theme.borderAlpha or 0.55)
    end
    -- Depth layer: subtle top-light so panels read as surfaces, not flat fills
    local gradient = f:CreateTexture(nil, "BACKGROUND")
    gradient:SetPoint("TOPLEFT", 1, -1)
    gradient:SetPoint("TOPRIGHT", -1, -1)
    gradient:SetHeight(math.min(height * 0.3, 40))
    gradient:SetColorTexture(U.theme.accentDim[1], U.theme.accentDim[2], U.theme.accentDim[3], 0.08)
    paint(f)
    U.panels[#U.panels + 1] = f
    return f
end
-- Default text color follows the type scale: titles read brightest, body copy
-- slightly dimmer, hints and metadata the dimmest. Explicit SetTextColor wins.
local function label(parent, text, size, x, y, width)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f:SetFont(STANDARD_TEXT_FONT, size)
    f:SetPoint("TOPLEFT", x, y)
    f:SetWidth(width)
    f:SetJustifyH("LEFT")
    local default = size >= 14 and U.theme.text or (size >= 12 and U.theme.textDim or U.theme.textMuted)
    f:SetTextColor(unpack(default))
    f:SetText(text)
    return f
end
-- Section header: small caps-style label that opens a group of rows. Used instead
-- of ad-hoc header sizes so every group on every view reads the same way.
local function sectionHeader(parent, text, x, y, width, color)
    local f = label(parent, text, U.type.body, x, y, width)
    f:SetTextColor(unpack(color or U.theme.textMuted))
    return f
end
-- One button for the whole UI: ghost by default, `opts.primary` for the single
-- main action of a view. Hover lights the edge (accent for primary) and a native
-- HIGHLIGHT-layer glow; pressing offsets the label until release or pointer exit.
-- b.title stays the label handle (tests and callers read it).
local function button(parent, text, x, y, width, action, height, opts)
    local h = height or 26
    local primary = opts and opts.primary
    local small = opts and opts.small
    local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    b:SetSize(width, h); b:SetPoint("TOPLEFT", x, y)
    if b.SetBackdrop then
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        local fill = primary and U.theme.accentDim or U.theme.bgRaised
        b:SetBackdropColor(fill[1], fill[2], fill[3], primary and 0.45 or 0.85)
        local edge = primary and U.theme.accent or U.theme.border
        b:SetBackdropBorderColor(edge[1], edge[2], edge[3], primary and 0.8 or U.theme.borderAlpha)
    end
    local glow = b:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    glow:SetColorTexture(U.theme.accentDim[1], U.theme.accentDim[2], U.theme.accentDim[3], 0.22)
    local title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetFont(STANDARD_TEXT_FONT, small and U.type.tiny or U.type.body)
    b.titleAnchor = {"CENTER", 0, 0}
    title:SetPoint(unpack(b.titleAnchor))
    title:SetTextColor(unpack(primary and U.theme.text or accent))
    title:SetText(text)
    b.title = title
    local function press(down)
        local anchor = b.titleAnchor
        title:ClearAllPoints()
        title:SetPoint(anchor[1], anchor[2] + (down and 1 or 0), anchor[3] - (down and 1 or 0))
    end
    b:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton == "LeftButton" then press(true) end
    end)
    b:SetScript("OnMouseUp", function() press(false) end)
    b:SetScript("OnHide", function() press(false) end)
    b:SetScript("OnEnter", function(self)
        if self.SetBackdropBorderColor then
            local edge = primary and U.theme.accent or U.theme.borderStrong
            self:SetBackdropBorderColor(edge[1], edge[2], edge[3], 0.9)
        end
    end)
    b:SetScript("OnLeave", function(self)
        press(false)
        if self.SetBackdropBorderColor then
            local edge = primary and U.theme.accent or U.theme.border
            self:SetBackdropBorderColor(edge[1], edge[2], edge[3], primary and 0.8 or U.theme.borderAlpha)
        end
    end)
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
    -- Texture widgets do not support OnUpdate scripts (client error reported in
    -- #177): probe once; if the handler is rejected, apply the end state directly.
    local start = GetTime()
    local handler = function(self)
        local progress = math.min(1, (GetTime() - start) / (duration or 0.2))
        apply(self, from + (to - from) * progress)
        if progress >= 1 then self:SetScript("OnUpdate", nil) end
    end
    if not pcall(f.SetScript, f, "OnUpdate", handler) then
        apply(f, to)
    end
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

-- One inner content measure: cards, hero, progress bar and the scroll area share
-- the same width so every view lines up on the same grid (was 664/676/696 mixed).
local INNER_W = 664

function U.Create()
    if U.frame then return end
    local f = panel(UIParent, "ForeverPathWindow", 780, 560)
    U.frame = f
    f:SetFrameStrata("DIALOG")
    f:SetScale(tonumber(NS.settings.scale) or math.min(1, UIParent:GetWidth()/820, UIParent:GetHeight()/600))
    draggable(f, "position")
    U.Restore(f, "position", "CENTER")
    table.insert(UISpecialFrames, "ForeverPathWindow")

    -- Brand moment: gradient accent stripe across the top edge
    local stripe = f:CreateTexture(nil,"ARTWORK"); stripe:SetPoint("TOPLEFT",1,-1); stripe:SetSize(778,3)
    stripe:SetColorTexture(U.theme.accentDim[1], U.theme.accentDim[2], U.theme.accentDim[3], 0.8)
    if stripe.SetGradientAlpha then
        pcall(stripe.SetGradientAlpha, stripe, "HORIZONTAL",
            U.theme.accent[1], U.theme.accent[2], U.theme.accent[3], 0.9,
            U.theme.accentDim[1], U.theme.accentDim[2], U.theme.accentDim[3], 0.0)
    end
    label(f,"FOREVERPATH",U.type.title,60,-20,300)
    button(f,"X",744,-20,30,function() f:Hide() end)

    -- LEFT SIDEBAR: vertical tab navigation; the active tab gets an accent rail
    local SIDEBAR_X, SIDEBAR_W = 4, 44
    f.tabs = {}
    f.tabContent = {}
    f.tabBars = {}
    local TABS = {
        { id = "now",       label = "NOW",      icon = "◆" },
        { id = "upgrades",  label = "GEAR",      icon = "⚡" },
        { id = "route",     label = "ROUTE",     icon = "▸" },
        { id = "settings",  label = "SETTINGS",  icon = "⚙" },
    }
    for i, tab in ipairs(TABS) do
        local b = button(f, tab.icon, SIDEBAR_X, -60 - (i - 1) * 52, SIDEBAR_W, function()
            U.SetActiveTab(tab.id)
        end, 44)
        local bar = b:CreateTexture(nil, "OVERLAY")
        bar:SetPoint("TOPLEFT", 0, 0)
        bar:SetSize(3, 44)
        bar:SetColorTexture(unpack(U.theme.accent))
        bar:Hide()
        f.tabBars[tab.id] = bar
        -- Tab label under icon
        local tabLabel = label(f, tab.label, U.type.tiny, SIDEBAR_X, -60 - (i - 1) * 52 - 36, SIDEBAR_W + 4)
        tabLabel:SetJustifyH("CENTER")
        f.tabs[tab.id] = b
        f.tabs[tab.id .. "_label"] = tabLabel
    end
    -- Sidebar separator (vertical line between rail and content)
    local sidebarLine = f:CreateTexture(nil, "ARTWORK")
    sidebarLine:SetPoint("TOPLEFT", SIDEBAR_X + SIDEBAR_W + 4, -50)
    sidebarLine:SetWidth(1); sidebarLine:SetHeight(480)
    sidebarLine:SetColorTexture(U.theme.border[1], U.theme.border[2], U.theme.border[3], 0.5)

    -- CONTENT AREA: each tab gets a container frame, shown/hidden by SetActiveTab
    local CONTENT_X = SIDEBAR_X + SIDEBAR_W + 16

    -- "NOW" tab content: the working view
    local now = CreateFrame("Frame", nil, f)
    now:SetPoint("TOPLEFT", CONTENT_X, -50)
    now:SetSize(INNER_W + 32, 460)
    f.tabContent.now = now

    -- "UPGRADES" tab: full upgrade finder view
    local upg = CreateFrame("Frame", nil, f)
    upg:SetPoint("TOPLEFT", CONTENT_X, -50)
    upg:SetSize(INNER_W + 32, 460)
    f.tabContent.upgrades = upg
    label(upg, "UPGRADES AVAILABLE NOW", U.type.page, 0, -12, INNER_W):SetTextColor(unpack(U.theme.green))
    upg.subtitle = label(upg, "Best quest reward per gear slot, for your class and level.", U.type.small, 0, -36, INNER_W)
    upg.subtitle:SetTextColor(unpack(muted))
    -- One multiline fontstring (up to 8 upgrades); U.Render rewrites it only when the text changes.
    upg.list = label(upg, "", U.type.body, 0, -64, INNER_W)
    upg.list:SetJustifyV("TOP")
    U.gearList = upg.list

    -- "ROUTE" tab: route management
    local rte = CreateFrame("Frame", nil, f)
    rte:SetPoint("TOPLEFT", CONTENT_X, -50)
    rte:SetSize(INNER_W + 32, 460)
    f.tabContent.route = rte
    label(rte, "YOUR ROUTE", U.type.page, 0, -12, INNER_W)
    rte.subtitle = label(rte, "Import, share and manage your custom routes.", U.type.small, 0, -36, INNER_W)
    rte.subtitle:SetTextColor(unpack(muted))
    U.routeInfo = label(rte, "", U.type.body, 0, -64, INNER_W); U.routeInfo:SetTextColor(unpack(muted))
    button(rte, "Import / share route", 0, -92, 190, function() U.RouteImport() end, 26, { primary = true })
    U.routeStyle = button(rte, "Playstyle: Balanced", 200, -92, 190, function() NS.CycleStyle() end)

    -- "SETTINGS" tab: settings content (existing elements will be re-parented)
    local set = CreateFrame("Frame", nil, f)
    set:SetPoint("TOPLEFT", CONTENT_X, -50)
    set:SetSize(INNER_W + 32, 460)
    f.tabContent.settings = set
    label(set, "SETTINGS", U.type.page, 0, -12, INNER_W)
    button(set, "Open settings", 0, -48, 190, function() U.Settings() end)
    button(set, "Run setup again", 0, -84, 190, function() U.Setup() end)
    button(set, "Diagnostics", 0, -120, 190, function() U.Diagnostics() end)

    -- NOW tab: populate with existing UI elements (re-parented from f to now)
    U.banner = label(now,"",U.type.headline,0,-38,INNER_W)
    U.banner:SetTextColor(unpack(U.theme.accent))
    U.context = label(now,"",U.type.small,0,-61,INNER_W); U.context:SetTextColor(unpack(muted))
    U.profile = button(now,"Profile",0,-88,110,function() NS.CycleProfile() end)
    U.goal = button(now,"Playstyle: Balanced",116,-88,110,function() NS.CycleStyle() end)
    button(now,"Tips card",232,-88,90,function() U.ToggleCompact() end)
    U.refresh = button(now,"Refresh",328,-88,90,function() NS.Refresh() end)

    -- Route position
    U.progressLabel = label(now,"",U.type.small,0,-120,INNER_W); U.progressLabel:SetTextColor(unpack(muted))
    U.progress = CreateFrame("Frame",nil,now)
    U.progress:SetPoint("TOPLEFT",0,-134); U.progress:SetSize(INNER_W,6)
    U.progress.background = U.progress:CreateTexture(nil,"BACKGROUND")
    U.progress.background:SetAllPoints(); U.progress.background:SetColorTexture(U.theme.bgTrack[1],U.theme.bgTrack[2],U.theme.bgTrack[3],0.9)
    U.progress.fill = U.progress:CreateTexture(nil,"ARTWORK")
    U.progress.fill:SetPoint("TOPLEFT"); U.progress.fill:SetHeight(6)
    U.progress.fill:SetColorTexture(unpack(accent))
    U.progress:Hide()

    -- Upgrade section
    U.upgradeHeader = sectionHeader(now,"UPGRADES AVAILABLE NOW",0,-148,INNER_W,U.theme.green)
    U.upgradeSlots = {}
    U.upgradeDetails = {}
    for i = 1, 3 do
        U.upgradeSlots[i] = label(now,"",U.type.body,0,-162 - (i - 1) * 16,86)
        U.upgradeSlots[i]:SetTextColor(unpack(U.theme.green))
        U.upgradeDetails[i] = label(now,"",U.type.body,100,-162 - (i - 1) * 16,INNER_W - 104)
    end
    U.upgradeHeader:Hide()

    -- Hero panel: the single next step, with the primary "Show way" action
    U.hero = panel(now, "ForeverPathHero", INNER_W, 62)
    U.hero:SetPoint("TOPLEFT", 0, -218)
    U.hero.stripe = U.hero:CreateTexture(nil, "ARTWORK")
    U.hero.stripe:SetSize(3, 62); U.hero.stripe:SetPoint("TOPLEFT", 0, 0)
    U.hero.stripe:SetColorTexture(unpack(U.theme.accent))
    U.hero.title = label(U.hero, "", 15, 16, -8, INNER_W - 130)
    U.hero.reason = label(U.hero, "", U.type.body, 16, -34, INNER_W - 130); U.hero.reason:SetTextColor(unpack(muted))
    U.hero.way = button(U.hero, "Show way", INNER_W - 110, -14, 96, function() if U.hero.row then NS.Nav.Pin(U.hero.row) end end, 26, { primary = true })
    U.hero.distance = label(U.hero, "", U.type.small, INNER_W - 110, -44, 96); U.hero.distance:SetTextColor(unpack(accent))
    local heroElapsed = 0
    U.hero:SetScript("OnUpdate", function(_, delta)
        heroElapsed = heroElapsed + (delta or 0)
        if heroElapsed >= 0.25 then heroElapsed = 0; U.UpdateHeroDistance() end
    end)
    if U.hero.CreateTexture then
        local heroGlow = U.hero:CreateTexture(nil, "BACKGROUND")
        heroGlow:SetAllPoints()
        heroGlow:SetColorTexture(U.theme.accentDim[1], U.theme.accentDim[2], U.theme.accentDim[3], 0.06)
    end
    U.hero:Hide()
    -- Smart-tips line (TIPS-01): directly under the hero panel, above the card list.
    U.tipLine = label(now, "", U.type.small, 0, -281, INNER_W); U.tipLine:SetTextColor(unpack(U.theme.yellow))
    U.tipLine:Hide()

    -- Card list (scroll); the scrollbar band is the 32px right inset
    local scroll = CreateFrame("ScrollFrame",nil,now,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",0,-310); scroll:SetPoint("BOTTOMRIGHT",-32,10)
    U.child = CreateFrame("Frame",nil,scroll); U.child:SetSize(INNER_W,1); scroll:SetScrollChild(U.child)
    U.scroll, U.cards = scroll, {}

    -- Footer
    U.sessionLine = label(f,"",U.type.small,60,-530,696); U.sessionLine:SetTextColor(unpack(U.theme.green))
    U.cpuLine = label(f,"",U.type.small,60,-544,696); U.cpuLine:SetTextColor(unpack(muted))

    -- Default to "now" tab
    U.SetActiveTab(NS.settings.activeTab or "now")
    f:Hide()
end

function U.SetActiveTab(id)
    if not U.frame or not U.frame.tabContent then return end
    NS.settings.activeTab = id
    for tabId, content in pairs(U.frame.tabContent) do
        if tabId == id then content:Show() else content:Hide() end
    end
    for tabId, widget in pairs(U.frame.tabs) do
        if type(widget) == "table" and widget.title then -- a tab button
            local active = tabId == id
            local color = active and U.theme.accent or U.theme.textMuted
            widget.title:SetTextColor(color[1], color[2], color[3])
        elseif type(widget) == "table" and widget.SetTextColor then -- a tab label (font string)
            local labelTabId = string.gsub(tabId, "_label$", "")
            local color = labelTabId == id and U.theme.text or U.theme.textMuted
            widget:SetTextColor(color[1], color[2], color[3])
        end
    end
    for tabId, bar in pairs(U.frame.tabBars or {}) do
        if tabId == id then bar:Show() else bar:Hide() end
    end
end


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
    local _, _, note = U.EvidenceTag(row)
    if note then lines[#lines + 1] = note end
    return lines
end

-- Pure: muted "unverified" marker for rows resting on imported/estimated data; nil otherwise
-- (live and verified rows get no tag). Returns short ("~"), long ("~ unverified"), and the
-- one-line explanation.
local UNVERIFIED_NOTE = "Imported data, not yet confirmed in game"
function U.EvidenceTag(row)
    if type(row) ~= "table" or row.evidence ~= "estimated" then return nil end
    return "~", "~ unverified", UNVERIFIED_NOTE
end

function U.Provenance(row, anchor)
    if not U.prov then
        local f = panel(UIParent, "ForeverPathProvenance", 340, 136, 0.9)
        U.prov = f
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetClampedToScreen(true)
        table.insert(UISpecialFrames, "ForeverPathProvenance")  -- Esc closes
        label(f, "SOURCE — why we trust this", U.type.body, 14, -10, 300):SetTextColor(unpack(U.theme.green))
        U.prov.lines = {}
        for i = 1, 5 do U.prov.lines[i] = label(f, "", 12, 14, -28 - (i - 1) * 16, 310) end
        local hint = label(f, "Click the popover to close", 10, 14, -114, 300)
        hint:SetTextColor(unpack(muted))
        f:EnableMouse(true)
        f:SetScript("OnMouseUp", function(self) self:Hide() end)
    end
    local lines = U.ProvenanceLines(row)
    for i = 1, 5 do
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
    if not U.hero then return end
    local text = heroDistance(U.hero.row) or ""
    if U.hero.lastDistance ~= text then
        U.hero.lastDistance = text
        U.hero.distance:SetText(text)
    end
end

-- Pure: compact text that never comes back empty. Long text is truncated with an
-- ellipsis so the card keeps its height; the distance chip joins the reason line.
function U.CompactText(row, message)
    local title, reason
    if type(row) == "table" then
        title = tostring(row.title or "Next step")
        reason = tostring((row.reasons or {})[1] or row.verdict or "")
        -- Dungeon flow: explain WHY the player sees leveling quests in dungeon mode.
        if NS.settings.style == "dungeon" and not row.isDungeonStep then
            reason = "Leveling route (dungeon guides start at 13) · " .. reason
        end
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

-- Pure: the #198 chain line for a card. Rows with follow-ups get "→ Opens: <next
-- quest title>" when exactly one titled follow-up is known, else "→ Opens N
-- follow-ups". Nil for rows without follow-ups.
function U.ChainLine(row)
    if type(row) ~= "table" or not row.unlocks or row.unlocks <= 0 then return nil end
    if row.unlocks == 1 and row.next then return "→ Opens: " .. tostring(row.next) end
    return string.format("→ Opens %d follow-up%s", row.unlocks, row.unlocks == 1 and "" or "s")
end

-- Pure: the horizontal chain stripe text "this quest → next → next-next" (#198).
-- Nil unless the chain is unbranched (Engine's branching rows show a count instead).
-- One line only: long stripes are byte-truncated with "..." to keep the card layout.
function U.ChainText(row)
    if type(row) ~= "table" or type(row.chain) ~= "table" or #row.chain == 0 then return nil end
    local text = tostring(row.title or "Quest") .. " → " .. table.concat(row.chain, " → ")
    if #text > 84 then text = string.sub(text, 1, 83) .. "..." end
    return text
end

-- Pure: one nearby-giver line for the RADAR-01 (#199) section: "4.2 — Title".
-- The number is map percent (house rule: yards need a per-map scale, so none is
-- invented); the section header says so. Nil for non-table input; long lines are
-- byte-truncated with "..." like the other single-line texts.
function U.NearbyText(giver)
    if type(giver) ~= "table" then return nil end
    local text = string.format("%.1f — %s", tonumber(giver.distance) or 0, tostring(giver.title or "Quest"))
    if #text > 92 then text = string.sub(text, 1, 91) .. "..." end
    return text
end

local COMPACT_MAX_ROWS, COMPACT_ROW_H, COMPACT_HEAD_H = 3, 34, 18

-- Pure: how many step rows the compact list shows. Never 0: an empty state still
-- gets one row carrying the status message (BUG-01).
function U.CompactRowCount(rows)
    return math.max(1, math.min(COMPACT_MAX_ROWS, type(rows) == "table" and #rows or 0))
end

-- Pure: hover tooltip content for one step - title, every reason, then the source
-- lines. Each entry is { text, kind } with kind "title" | "reason" | "source".
function U.CompactTooltipLines(row)
    if type(row) ~= "table" then return {} end
    local lines = { { tostring(row.title or "Next step"), "title" } }
    for _, reason in ipairs(type(row.reasons) == "table" and row.reasons or {}) do
        lines[#lines + 1] = { tostring(reason), "reason" }
    end
    for _, source in ipairs(U.ProvenanceLines(row)) do lines[#lines + 1] = { source, "source" } end
    return lines
end

-- Row click: left pins the arrow to the step (only when it has a target; unknown
-- data never clears or invents the arrow), right dismisses the tip. Returns the
-- action taken for tests.
function U.CompactClick(row, mouseButton)
    if type(row) ~= "table" then return nil end
    if mouseButton == "RightButton" then
        if NS.DismissTip then NS.DismissTip(row); return "dismiss" end
    elseif row.target and NS.Nav and NS.Nav.Pin then
        NS.Nav.Pin(row); return "pin"
    end
    return nil
end

local function setCompactText(fs, text)
    if fs.lastText ~= text then
        fs:SetText(text); fs.lastText = text
        animate(fs, function(target, value) target:SetAlpha(value) end, 0.35, 1, 0.15)
    end
end

-- Everything inside pcall: a client-specific error must leave a visible card,
-- never an empty one (BUG-01). Row frames are pre-created once by U.Compact.
local function renderCompact(rows, state)
    local h = U.hud
    if not h then return end
    local count = U.CompactRowCount(rows)
    for i = 1, COMPACT_MAX_ROWS do
        local r = h.rows[i]
        local row = i <= count and rows[i] or nil
        if i > count then
            r:Hide(); r.row = nil
        else
            r.row = row
            r:Show()
            local ok, title, reason = pcall(U.CompactText, row, state.message)
            if not ok then
                -- On failure `title` holds the pcall error: log it before the
                -- placeholder replaces it, or Diagnostics says nothing useful.
                if NS.Client and NS.Client.errors then NS.Client.errors.last = "compact: " .. tostring(title) end
                title, reason = "Compact error", "Send us /fp diag"
            end
            setCompactText(r.title, title)
            r.tag:SetText(row and U.EvidenceTag(row) or "")
            if i == 1 and U.milestoneMessage then
                -- Milestones and streaks (MILE-01/#200): a fresh milestone takes over the
                -- first row's reason for one render (green); a live streak rides along
                -- when it fits the distance-chip budget. Wording comes from the engine.
                setCompactText(r.reason, U.milestoneMessage)
                r.reason:SetTextColor(U.theme.green[1], U.theme.green[2], U.theme.green[3])
            else
                r.reason:SetTextColor(muted[1], muted[2], muted[3])
                if i == 1 then
                    local streak = NS.Engine and NS.Engine.Streak and NS.Engine.Streak(U.streak or 0, U.diedSinceLastQuest) or nil
                    if streak and #reason + #streak + 3 <= 63 then reason = reason .. " · " .. streak end
                end
                setCompactText(r.reason, reason)
            end
            -- Current step (row 1): verdict stripe at full strength, brighter title and
            -- a soft highlight; the next steps sit dimmer.
            local color = row and U.theme.verdict[row.verdict] or U.theme.accent
            r.stripe:SetColorTexture(color[1], color[2], color[3], i == 1 and 1 or 0.5)
            local text = i == 1 and U.theme.text or U.theme.textDim
            r.title:SetTextColor(text[1], text[2], text[3])
            r.bg:SetColorTexture(1, 1, 1, i == 1 and 0.07 or 0)
            local icon = row and (row.icon or row.texture)
            if icon and icon ~= "" then r.icon:SetTexture(icon); r.icon:Show() else r.icon:Hide() end
        end
    end
    local height = COMPACT_HEAD_H + count * COMPACT_ROW_H + 2
    if h.rowCount ~= count then h.rowCount = count; h:SetHeight(height) end
    local locked = NS.settings.compactLocked and true or false
    local lockText = locked and "Unlock" or "Lock"
    if h.lock.title.lastText ~= lockText then h.lock.title:SetText(lockText); h.lock.title.lastText = lockText end
end

-- The upgrade section sits between the hero and the card list; when it is shown the
-- card list starts lower. Pure display selection: rows come from Engine.BestUpgrades.
local function renderUpgrades(state)
    local upgrades = (state.mode ~= "rewards" and type(state.upgrades) == "table") and state.upgrades or {}
    if #upgrades == 0 then
        U.upgradeHeader:Hide()
        for i = 1, 3 do U.upgradeSlots[i]:Hide(); U.upgradeDetails[i]:Hide() end
        U.scroll:ClearAllPoints(); U.scroll:SetPoint("TOPLEFT",0,-296); U.scroll:SetPoint("BOTTOMRIGHT",-32,10)
        return
    end
    U.upgradeHeader:Show()
    for i = 1, 3 do
        local row = upgrades[i]
        if row then
            local detail = row.percent and string.format("+%.0f%%  %s (+%.1f)", row.percent, row.title, row.delta)
                or string.format("%s (+%.1f)", row.title, row.delta)
            if #detail > 92 then detail = string.sub(detail, 1, 91) .. "..." end
            if U.upgradeSlots[i].lastText ~= row.slot then U.upgradeSlots[i]:SetText(row.slot); U.upgradeSlots[i].lastText = row.slot end
            if U.upgradeDetails[i].lastText ~= detail then U.upgradeDetails[i]:SetText(detail); U.upgradeDetails[i].lastText = detail end
            U.upgradeSlots[i]:Show(); U.upgradeDetails[i]:Show()
        else
            U.upgradeSlots[i]:Hide(); U.upgradeDetails[i]:Hide()
        end
    end
    U.scroll:ClearAllPoints(); U.scroll:SetPoint("TOPLEFT",0,-372); U.scroll:SetPoint("BOTTOMRIGHT",-32,10)
end

-- GEAR tab: every upgrade in state.upgrades (max 8), one multiline fontstring.
local function renderGear(state)
    if not U.gearList then return end
    local upgrades = type(state.upgrades) == "table" and state.upgrades or {}
    local lines = {}
    for i = 1, math.min(#upgrades, 8) do
        local row = upgrades[i]
        lines[#lines + 1] = string.format("%s: %s", tostring(row.slot or "?"), row.percent
            and string.format("+%.0f%%  %s (+%.1f)", row.percent, row.title or "?", row.delta or 0)
            or string.format("%s (+%.1f)", row.title or "?", row.delta or 0))
    end
    local text = #lines > 0 and table.concat(lines, "\n") or "No upgrades found for your class and level right now. Check back after new quest rewards or level-ups."
    if U.gearList.lastText ~= text then U.gearList:SetText(text); U.gearList.lastText = text end
end

-- RADAR-01 (#199): the NEARBY section sits at the top of the card list. Rows come
-- from Engine.NearbyGivers via state.nearby (pure data; rendering owns no logic)
-- and are rewritten only inside Render — never per frame. Clicking a row pins the
-- arrow and waypoint on that giver (NS.Nav.Pin), same as a card's "Show way".
local NEARBY_MAX = 5

local function nearbyRow(index)
    if U.nearbyRows[index] then return U.nearbyRows[index] end
    local f = CreateFrame("Button", nil, U.child)
    f:SetSize(664, 16)
    f.text = label(f, "", 12, 8, 0, 648)
    f.giver, f.map = nil, nil
    f:SetScript("OnClick", function(self)
        if self.giver and self.map then
            NS.Nav.Pin({ id = "nearby:" .. tostring(self.giver.questID),
                target = { map = self.map, x = self.giver.x, y = self.giver.y },
                title = self.giver.title })
        end
    end)
    f:SetScript("OnEnter", function(self)
        if self.text then self.text:SetTextColor(unpack(accent)) end
    end)
    f:SetScript("OnLeave", function(self)
        if self.text then self.text:SetTextColor(unpack(U.theme.textDim)) end
    end)
    U.nearbyRows[index] = f
    return f
end

-- Pure display: shows the header and at most NEARBY_MAX rows, hides the rest,
-- and returns the height the section consumed so the cards start below it.
local function renderNearby(state)
    local nearby = state.mode ~= "rewards" and type(state.nearby) == "table" and state.nearby or nil
    local givers = nearby and type(nearby.givers) == "table" and nearby.givers or {}
    if not U.nearbyHeader then
        U.nearbyHeader = label(U.child, "", 12, 0, 0, 664)
        U.nearbyHeader:SetTextColor(unpack(accent))
        U.nearbyRows = {}
        for i = 1, NEARBY_MAX do nearbyRow(i):SetPoint("TOPLEFT", 0, -18 - (i - 1) * 16) end
    end
    local shown = math.min(#givers, NEARBY_MAX)
    if shown == 0 then
        U.nearbyHeader:Hide()
        for i = 1, NEARBY_MAX do
            U.nearbyRows[i].giver, U.nearbyRows[i].map = nil, nil
            U.nearbyRows[i]:Hide()
        end
        return 0
    end
    if U.nearbyHeader.lastText ~= true then U.nearbyHeader:SetText("QUEST GIVERS NEARBY — distance in map %"); U.nearbyHeader.lastText = true end
    U.nearbyHeader:Show()
    for i = 1, NEARBY_MAX do
        local row, giver = U.nearbyRows[i], givers[i]
        if giver then
            local text = U.NearbyText(giver)
            if row.lastText ~= text then row.text:SetText(text); row.lastText = text end
            row.giver, row.map = giver, nearby.map
            row:Show()
        else
            row.giver, row.map = nil, nil
            row:Hide()
        end
    end
    return 18 + shown * 16 + 8
end


-- Card factory: each quest/recommendation row in the scroll list. The 3px verdict
-- stripe pins to the left edge and grows with the card; icon, title, verdict badge
-- and explanation sit on a shared grid with the rest of the UI.
local function card(index)
    if U.cards[index] then return U.cards[index] end
    local f = panel(U.child,nil,664,110,0.7)
    f.stripe = f:CreateTexture(nil,"ARTWORK")
    f.stripe:SetSize(3,110); f.stripe:SetPoint("TOPLEFT",0,0)
    f.stripe:SetColorTexture(unpack(U.theme.accent))
    f.icon = f:CreateTexture(nil,"ARTWORK")
    f.icon:SetSize(36,36); f.icon:SetPoint("TOPLEFT",12,-12)
    f.icon:SetTexCoord(0.08,0.92,0.08,0.92); f.icon:Hide()
    f.title = label(f,"",14,56,-12,392)
    f.badge = label(f,"",11,456,-15,192); f.badge:SetJustifyH("RIGHT")
    f.evidence = label(f,"",10,456,-4,192); f.evidence:SetJustifyH("RIGHT"); f.evidence:SetTextColor(unpack(muted))
    f.body = label(f,"",12,56,-36,560); f.body:SetJustifyV("TOP")
    -- CHAIN-01 (#198): horizontal chain stripe ("quest1 → quest2 → quest3"),
    -- accent-colored; anchored under the body during Render.
    f.chain = label(f,"",12,16,-56,560)
    f.chain:SetTextColor(unpack(accent))
    f.chain:Hide()
    f.way = button(f,"Show way",552,-38,100,function() if f.row then NS.Nav.Pin(f.row) end end, 24)
    f:EnableMouse(true)
    f:SetScript("OnEnter",function(self)
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.9) end
        if self.link and GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetHyperlink(self.link); GameTooltip:Show() end
    end)
    f:SetScript("OnLeave",function(self)
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(border[1], border[2], border[3], 0.4) end
        if GameTooltip then GameTooltip:Hide() end
    end)
    f:SetScript("OnMouseUp",function(self) if self.row then U.Provenance(self.row, self) end end)
    U.cards[index] = f
    return f
end

-- Milestones (MILE-01/#200): a green flash in the hero panel, same treatment as the
-- ding celebration (UX-03) — green border, green title, revert after 0.8s. The turn-
-- in ding already sounds; milestones add no second sound on top of it.
local function flashHero(message)
    if not (U.hero and U.hero:IsShown()) then return end
    if NS.settings.animations == false then return end
    if not (C_Timer and C_Timer.After) then return end  -- no timer: skip the flash, the card message still shows
    if U.hero.SetBackdropBorderColor then
        U.hero:SetBackdropBorderColor(U.theme.green[1], U.theme.green[2], U.theme.green[3], 0.9)
    end
    U.hero.title:SetText(message)
    U.hero.title:SetTextColor(U.theme.green[1], U.theme.green[2], U.theme.green[3])
    C_Timer.After(0.8, function()
        if U.hero and U.hero.title then
            U.hero.title:SetTextColor(unpack(U.theme.text))
            if U.hero.SetBackdropBorderColor then
                U.hero:SetBackdropBorderColor(U.theme.border[1], U.theme.border[2], U.theme.border[3], 0.9)
            end
            NS.Refresh()
        end
    end)
end

-- Milestones and streaks (MILE-01/#200): detects crossings between renders with
-- last-seen markers (the same pattern as every last* key in this file); the decision
-- and wording are pure (Engine.Milestones / Engine.Streak), rendering owns no logic.
-- A level-up names its own level; a quest event passes 0 so only quest points fire.
-- The streak counts quests since the last death; a death between quests restarts the
-- row at the next completion.
local function renderMilestones(state)
    U.milestoneMessage = nil
    local session = (NS.Client and NS.Client.session) or {}
    local questsDone = tonumber(session.questsDone) or 0
    local level = tonumber(state.level) or 0
    local result
    if U.lastLevel and level > U.lastLevel then
        result = NS.Engine.Milestones(questsDone, level)
    elseif U.lastQuests and questsDone > U.lastQuests then
        result = NS.Engine.Milestones(questsDone, 0)
    end
    if U.lastQuests and questsDone > U.lastQuests then
        if U.diedSinceLastQuest then U.streak, U.diedSinceLastQuest = 0, false end
        U.streak = (U.streak or 0) + (questsDone - U.lastQuests)
    end
    U.lastLevel, U.lastQuests = level, questsDone
    if result and result.isMilestone then
        U.milestoneMessage = result.message
        if result.kind == "quests" and result.next then
            U.milestoneMessage = string.format("%s · next: %d quests", result.message, result.next)
        end
        flashHero(result.message)
    end
    return U.milestoneMessage
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
    -- Smart-tips (TIPS-01): contextual hints below the hero panel
    local tips = state.tips or {}
    if #tips > 0 and state.mode ~= "rewards" then
        local tipText = table.concat(tips, "  |  ")
        if U.tipLine then
            tipText = "TIP: " .. tipText
            if U.tipLine.lastText ~= tipText then U.tipLine:SetText(tipText); U.tipLine.lastText = tipText end
            U.tipLine:Show()
        end
    elseif U.tipLine then
        U.tipLine:Hide()
    end
    if stepRow then
        U.progress:Show()
        local routeLabel = string.format("Route: %s — step %d of %d", stepRow.guideName or "?", stepRow.stepIndex or 0, stepRow.stepTotal)
        if NS.settings.style == "dungeon" and not stepRow.isDungeonStep then
            routeLabel = routeLabel .. "  (dungeon guides start at level 13)"
        end
        U.progressLabel:SetText(routeLabel)
        U.routeLabelText = routeLabel
        local target = INNER_W * math.min(1, math.max(0, (stepRow.stepIndex or 1) / stepRow.stepTotal))
        local key = stepRow.guideName .. ":" .. stepRow.stepIndex
        if U.progress.lastKey ~= key then
            animate(U.progress.fill, function(f, value) f:SetWidth(value) end, U.progress.lastWidth or 0, target, 0.4)
            U.progress.lastKey, U.progress.lastWidth = key, target
        end
    else
        U.progress:Hide()
        -- When quests are shown but no route covers the level range, say so instead
        -- of silently hiding the progress area (UX-02).
        if state.mode ~= "rewards" and #rows > 0 then
            U.progressLabel:SetText("Route: no guide covers your level range yet - zone quests below")
            U.routeLabelText = "Route: no guide covers your level range yet - zone quests below"
        else
            U.progressLabel:SetText("")
            U.routeLabelText = "No route progress yet."
        end
    end
    if U.routeInfo and U.routeInfo.lastText ~= U.routeLabelText then U.routeInfo:SetText(U.routeLabelText); U.routeInfo.lastText = U.routeLabelText end
    if U.routeStyle then U.routeStyle.title:SetText("Playstyle: " .. (NS.Route.labels[NS.settings.style] or "Balanced")) end
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
    -- RADAR-01 (#199): the nearby section consumes the top of the card list;
    -- the cards start below whatever it used (0 when hidden).
    local y = renderNearby(state)
    for i = 1, math.max(1,#rows) do
        local row = rows[i]
        local c = card(i)
        c.title:SetText(row and row.title or "Ready when you are")
        c.badge:SetText(row and row.verdict or "Waiting")
        local _, longTag = U.EvidenceTag(row)
        c.evidence:SetText(longTag or "")
        c.badge:SetTextColor(verdictColor(row and row.verdict or "Waiting"))
        c.title:SetTextColor(unpack(row and row.verdict == "Skip" and U.theme.muted or U.theme.text))
        -- UX-05: the stripe carries the verdict color. Skip de-emphasizes to muted,
        -- matching its gray title, instead of alarm-red.
        local color = row and U.theme.verdict[row.verdict] or U.theme.accent
        if row and row.verdict == "Skip" then color = U.theme.muted end
        c.stripe:SetColorTexture(color[1], color[2], color[3])
        -- CHAIN-01 (#198): the engine's plain "Opens N follow-up quest(s)" reason
        -- carries the same count as the arrow line, so swap rather than show both.
        local bodyLines = {}
        for _, reason in ipairs(row and row.reasons or {}) do
            if not (row.unlocks and row.unlocks > 0 and type(reason) == "string"
                and string.match(reason, "^Opens %d+ follow%-up quests?$")) then
                bodyLines[#bodyLines + 1] = reason
            end
        end
        local arrow = U.ChainLine(row)
        if arrow then bodyLines[#bodyLines + 1] = arrow end
        c.body:SetText(row and table.concat(bodyLines, "\n")
            or state.message
            or "Press Refresh after entering the world. If this stays empty, run /fp setup to pick a playstyle.")
        local chainText = U.ChainText(row)
        if chainText then
            c.chain:SetText(chainText)
            c.chain:ClearAllPoints()
            c.chain:SetPoint("TOPLEFT", c.body, "BOTTOMLEFT", 0, -2)
            c.chain:Show()
        else
            c.chain:Hide()
        end
        c.link = row and row.link or nil
        c.row = row
        if c.lastRowId ~= (row and row.id or nil) then
            animate(c, function(target, value) target:SetAlpha(value) end, 0, 1, 0.15)
            c.lastRowId = row and row.id or nil
        end
        if row and row.target then c.way:Show() else c.way:Hide() end
        -- Reserve a 12px gap before Show way; reclaim its space when hidden.
        local bodyRight = row and row.target and 540 or 616
        -- The item icon (when known) sits left of the text.
        local icon = row and (row.icon or row.texture)
        if icon and icon ~= "" then
            c.icon:SetTexture(icon); c.icon:Show()
            c.title:ClearAllPoints(); c.title:SetPoint("TOPLEFT",56,-12); c.title:SetWidth(392)
            c.body:ClearAllPoints(); c.body:SetPoint("TOPLEFT",56,-36); c.body:SetWidth(bodyRight - 56)
        else
            c.icon:Hide()
            c.title:ClearAllPoints(); c.title:SetPoint("TOPLEFT",16,-12); c.title:SetWidth(432)
            c.body:ClearAllPoints(); c.body:SetPoint("TOPLEFT",16,-36); c.body:SetWidth(bodyRight - 16)
        end
        -- Cards grow with their explanation instead of clipping it (the chain
        -- stripe from #198 grows the card by its own line).
        local textHeight = c.body.GetStringHeight and c.body:GetStringHeight() or 56
        local height = 50 + math.max(28, textHeight) + (chainText and 18 or 0)
        c.body:SetHeight(textHeight)
        c:SetHeight(height)
        c.stripe:SetHeight(height) -- the stripe grows and shrinks with the card
        c:ClearAllPoints(); c:SetPoint("TOPLEFT", 0, -y)
        y = y + height + 8
        c:Show()
    end
    for i = math.max(1,#rows)+1,#U.cards do U.cards[i]:Hide() end
    U.child:SetHeight(math.max(1, y))
    renderUpgrades(state)
    renderGear(state)
    local offset = U.scroll:GetVerticalScroll()
    U.scroll:SetVerticalScroll(math.min(offset,math.max(0,U.child:GetHeight()-U.scroll:GetHeight())))
    renderMilestones(state)
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
local function createCompactRow(h, i)
    local r = CreateFrame("Frame", nil, h)
    r:SetSize(330, COMPACT_ROW_H); r:SetPoint("TOPLEFT", 0, -(COMPACT_HEAD_H + (i - 1) * COMPACT_ROW_H))
    r:EnableMouse(true)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.stripe = r:CreateTexture(nil, "ARTWORK")
    r.stripe:SetSize(3, COMPACT_ROW_H); r.stripe:SetPoint("TOPLEFT", 0, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(24, 24); r.icon:SetPoint("TOPLEFT", 10, -5)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); r.icon:Hide()
    r.title = label(r, "", 12, 40, -3, 280)
    r.reason = label(r, "", 10, 40, -18, 285); r.reason:SetTextColor(unpack(muted))
    r.tag = label(r, "", 10, 290, -4, 32); r.tag:SetJustifyH("RIGHT"); r.tag:SetTextColor(unpack(muted))
    if r.title.SetWordWrap then r.title:SetWordWrap(false); r.reason:SetWordWrap(false) end
    r:SetScript("OnMouseUp", function(self, mouseButton) U.CompactClick(self.row, mouseButton) end)
    r:SetScript("OnEnter", function(self)
        if not (self.row and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for n, line in ipairs(U.CompactTooltipLines(self.row)) do
            local c = line[2] == "source" and U.theme.textDim or U.theme.text
            if n == 1 then GameTooltip:SetText(line[1], c[1], c[2], c[3])
            else GameTooltip:AddLine(line[1], c[1], c[2], c[3], true) end
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    -- Rows sit over the card: forward drags so the whole card moves (unless locked).
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnDragStart", function() if not NS.settings.compactLocked then h:StartMoving() end end)
    r:SetScript("OnDragStop", function() h:StopMovingOrSizing(); U.Remember(h, "compactPosition") end)
    return r
end

function U.Compact(show)
    if show and not U.hud then
        local h = panel(UIParent,"ForeverPathCompact",330,COMPACT_HEAD_H + COMPACT_ROW_H + 2,0.8)
        U.hud = h
        draggable(h, "compactPosition")
        h:SetScript("OnDragStart", function(self) if not NS.settings.compactLocked then self:StartMoving() end end)
        if Minimap then U.Restore(h, "compactPosition", "TOP", Minimap, "BOTTOM", 0, -18)
        else U.Restore(h, "compactPosition", "TOP", UIParent, "TOP", 0, -120) end
        h.rows = {}
        for i = 1, COMPACT_MAX_ROWS do h.rows[i] = createCompactRow(h, i) end
        -- Aliases for the first (current) row: Celebrate, diagnostics and tests read these.
        h.stripe, h.icon, h.title, h.reason = h.rows[1].stripe, h.rows[1].icon, h.rows[1].title, h.rows[1].reason
        label(h, "ForeverPath", U.type.tiny, 8, -3, 120)
        h.dismiss = button(h, "Hide", 196, -1, 40, function()
            local row = U.lastState and U.lastState.rows and U.lastState.rows[1]
            if row then NS.DismissTip(row) end
        end, 16, { small = true })
        h.lock = button(h, "Lock", 240, -1, 56, function()
            NS.settings.compactLocked = not NS.settings.compactLocked
            NS.Refresh()
        end, 16, { small = true })
        h.close = button(h, "X", 302, -1, 22, function() U.Compact(false) end, 16, { small = true })
        -- Header click opens the main window; right-click dismisses the current tip.
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
        label(f, "IMPORT YOUR ROUTE", U.type.page, 18, -20, 600)
        local hint = label(f, "Paste RegisterGuide blocks with .accept/.turnin/.complete steps. Map-percent .goto works (1411,43.3,68.5). Stays on this computer.", U.type.small, 18, -44, 620)
        hint:SetTextColor(unpack(muted))
        button(f, "X", 610, -14, 30, function() f:Hide() end)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 18, -64); scroll:SetPoint("BOTTOMRIGHT", -36, -80)
        local edit = CreateFrame("EditBox", nil, scroll); f.edit = edit
        edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject(ChatFontNormal); edit:SetWidth(590); edit:SetHeight(280)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(edit)
        f.status = label(f, "", U.type.body, 18, -384, 620); f.status:SetTextColor(unpack(U.theme.green))
        f.exampleBtn = button(f, "Insert example", 18, -404, 150, function() f.edit:SetText(U.RouteExample()) end)
        f.importBtn = button(f, "Import", 176, -404, 120, function() NS.ImportRoute(f.edit:GetText()) end, 26, { primary = true })
        f.shareBtn = button(f, "Copy share string", 304, -404, 150, function()
            local shared, err = NS.Route.EncodeRoute()
            f.edit:SetText(shared or err or "No custom route to share yet - import one first")
        end)
        f.removeBtn = button(f, "Remove", 462, -404, 120, function() NS.ImportRoute(nil); f.edit:SetText("") end)
    end
    U.routeWin.edit:SetText(NS.settings.customRouteText or "")
    fadeIn(U.routeWin)
end

-- Ding-feiring (UX-03): when the hero step's quest is turned in, flash green,
-- show DONE + session count, then fade to the next step. The compact card
-- celebrates the same turn-in (#208): green stripe and a Done! title, reverted
-- by the next render's verdict repaint. Respects the animations and sound
-- settings; without them it is an instant swap.
function U.Celebrate(questID)
    if not U.hero or not U.hero.row then return end
    if U.hero.row.questID ~= questID then return end
    local session = NS.Client.session or {}
    local stats = NS.Engine.SessionStats(session, GetTime and GetTime() or 0)
    local quests = stats.quests or 0
    local doneText = string.format("%s — DONE!  %d quest%s this session",
        tostring(U.hero.row.title or "Step"), quests, quests == 1 and "" or "s")
    if NS.settings.animations ~= false then
        -- Flash the hero panel green: set border, swap text, revert after 0.8s.
        if U.hero.SetBackdropBorderColor then
            U.hero:SetBackdropBorderColor(U.theme.green[1], U.theme.green[2], U.theme.green[3], 0.9)
        end
        U.hero.title:SetText(doneText)
        U.hero.title:SetTextColor(U.theme.green[1], U.theme.green[2], U.theme.green[3])
        -- Same celebration on the compact card (#208). The compact card can be
        -- closed, so a missing U.hud must never reach this path; renderCompact
        -- repaints the stripe with the verdict color on every render, and the
        -- cleared lastText forces the title back to the row even when the next
        -- render still shows the same quest.
        local h = U.hud
        if h and h.stripe and h.title then
            h.stripe:SetColorTexture(U.theme.green[1], U.theme.green[2], U.theme.green[3])
            h.title:SetText(string.format("✓ Done! %d quest%s", quests, quests == 1 and "" or "s"))
            h.title.lastText = nil
        end
        local function restore()
            if U.hero and U.hero.title then
                U.hero.title:SetTextColor(unpack(U.theme.text))
                if U.hero.SetBackdropBorderColor then
                    U.hero:SetBackdropBorderColor(U.theme.border[1], U.theme.border[2], U.theme.border[3], 0.9)
                end
                NS.Refresh()
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0.8, restore)
        else
            restore()
        end
    else
        -- Instant: just refresh to the next step.
        NS.Refresh()
    end
    if NS.settings.sounds ~= false and PlaySound then
        pcall(PlaySound, 828)  -- SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST is harsh; 828 is a soft ding
    end
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
-- Pure: the sanity line shown at the bottom of Setup. Green when data and client
-- basics are in place; the exact gap when they are not - a broken install should
-- be visible in the first five seconds, not discovered as "empty" (UX-01).
function U.SetupSanity()
    local questCount, guideCount = 0, 0
    for _, zone in pairs(NS.Quests or {}) do
        for _ in pairs(zone) do questCount = questCount + 1 end
    end
    for _ in ipairs((NS.Routes and NS.Routes.guides) or {}) do guideCount = guideCount + 1 end
    if questCount == 0 then
        return "Data problem: no quest database loaded - reinstall the ForeverPath folder", false
    end
    local missing = 0
    for _, name in ipairs({ "GetQuestID", "GetBuildInfo" }) do
        if type(_G[name]) ~= "function" then missing = missing + 1 end
    end
    if missing > 0 then
        return string.format("Client check: %d core API(s) missing - send /fp diag", missing), false
    end
    return string.format("Data loaded: %d guides, %d quests - ready", guideCount, questCount), true
end

-- 3-step onboarding wizard (UX-06): scale, playstyle, welcome. Each step
-- reveals the next; Esc closes (setup reappears on next login until done).
function U.Setup()
    if not U.setup then
        local f = panel(UIParent,"ForeverPathSetup",480,540)
        U.setup = f
        f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetPoint("CENTER")
        draggable(f, "setupPosition")
        table.insert(UISpecialFrames,"ForeverPathSetup")
        f.step = 1

        -- STEP indicator
        f.stepLabel = label(f,"Step 1 of 3 — Scale",U.type.page,22,-16,300)
        f.stepHint = label(f,"How big should the windows be? You can change this later with /fp settings.",U.type.small,22,-40,436)
        f.stepHint:SetTextColor(unpack(muted))

        -- STEP 1: Scale
        f.scaleRow = {}
        local scales = { {1.0,"100% — Normal"}, {0.8,"80% — Compact"}, {0.6,"60% — Small"} }
        for i, entry in ipairs(scales) do
            local value, text = entry[1], entry[2]
            local b = button(f, text, 22, -64 - (i - 1) * 40, 436, function()
                NS.settings.scale = value
                if f.SetScale then f:SetScale(value) end
                U.SetupStep(f, 2)
            end, 32)
            f.scaleRow[value] = b
        end

        -- STEP 2: Playstyle
        f.styleHeader = label(f,"Step 2 of 3 — Playstyle",U.type.page,22,-16,300)
        f.styleHint = label(f,"How do you want to level? You can change this any time.",U.type.small,22,-40,436)
        f.styleHint:SetTextColor(unpack(muted))
        f.choices = {}
        for i, choice in ipairs(CHOICES) do
            local style = choice[1]
            local b = button(f,"",22,-64 - (i - 1) * 58,436,function()
                NS.SetStyle(style)
                NS.settings.setupDone = true
                U.SetupStep(f, 3)
            end, 50)
            b.titleAnchor = {"TOPLEFT", 12, -8}
            b.title:ClearAllPoints(); b.title:SetPoint(unpack(b.titleAnchor)); b.title:SetText(choice[2])
            local desc = label(b,choice[3],U.type.tiny,12,-26,412); desc:SetTextColor(unpack(muted))
            f.choices[style] = b
        end

        -- STEP 3: Welcome / sanity
        f.welcomeHeader = label(f,"You are all set!",U.type.title,22,-16,300)
        f.welcomeText = label(f,"The small card under your map follows your next step.\nClick it for details, or type /fp for the full window.",U.type.body,22,-44,436)
        f.welcomeText:SetTextColor(unpack(muted))
        f.finishBtn = button(f,"Start playing",22,-100,436,function()
            f:Hide()
            if NS.settings.compact ~= false then U.Compact(true) end
            U.Toggle()
        end, 40, { primary = true })
        f.sanity = label(f,"",U.type.body,22,-154,436)

        U.SetupStep(f, 1)
    end
    local text, ok = U.SetupSanity()
    U.setup.sanity:SetText((ok and "|cff37d68c" or "|cffe08a3c") .. text .. "|r")
    fadeIn(U.setup)
end

function U.SetupStep(f, step)
    f.step = step
    local function show(element, visible)
        if visible then element:Show() else element:Hide() end
    end
    show(f.stepLabel, step == 1)
    show(f.stepHint, step == 1)
    for _, b in pairs(f.scaleRow) do show(b, step == 1) end
    show(f.styleHeader, step == 2)
    show(f.styleHint, step == 2)
    for _, b in pairs(f.choices) do show(b, step == 2) end
    show(f.welcomeHeader, step == 3)
    show(f.welcomeText, step == 3)
    show(f.finishBtn, step == 3)
    show(f.sanity, step == 3)
end

function U.Diagnostics()
    if not U.report then
        local f = panel(UIParent,"ForeverPathDiagnostics",660,440); U.report = f
        f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetClampedToScreen(true)
        table.insert(UISpecialFrames,"ForeverPathDiagnostics")
        label(f,"DIAGNOSTICS",U.type.page,18,-20,300)
        local hint = label(f,"Ctrl/Cmd+A, then copy — and send us /fp diag output.",U.type.small,18,-44,600)
        hint:SetTextColor(unpack(muted))
        button(f,"X",610,-14,30,function() f:Hide() end)
        local scroll = CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",18,-68); scroll:SetPoint("BOTTOMRIGHT",-36,24)
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

-- Pure: how far the Display section must move down when imported spec buttons are
-- shown (BUG-05/#186). Spec buttons fill rows of four, 26px tall on a 32px pitch
-- starting at y=-232; the Display label sits at y=-200, so with any specs present
-- the whole Display block moves down by rows*32+42 - below the last spec row with
-- 16px of air for every spec count. (A flat #specs*32+10 would still overlap for a
-- single imported spec: 42px clears nothing below y=-242.)
function U.SettingsDisplayOffset(specCount)
    local n = tonumber(specCount) or 0
    if n <= 0 then return 0 end
    return math.ceil(n / 4) * 32 + 42
end

-- BUG-05 (#186): re-place every Display-section element at its base position minus
-- the current offset, and grow the panel so the moved rows stay inside it.
local function placeDisplayRows(f, offset)
    for _, row in ipairs(f.displayRows) do
        row[1]:ClearAllPoints()
        row[1]:SetPoint("TOPLEFT", row[2], row[3] - offset)
    end
    f:SetHeight(f.baseHeight + offset)
end

function U.SyncSettings(f)
    for style, b in pairs(f.styles) do
        local color = NS.settings.style == style and U.theme.accent or U.theme.muted
        b.title:SetTextColor(color[1], color[2], color[3])
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
            local color = active and U.theme.accent or U.theme.muted
            b.title:SetTextColor(color[1], color[2], color[3])
            f.specButtons[#f.specButtons + 1] = b
        end
    else
        f.specLabel:SetText("Spec (stat weights): no imported specs for your class")
    end
    -- BUG-05 (#186): spec buttons used to land on top of the Arrow/Animations row;
    -- the whole Display block now moves below them (and back when specs disappear).
    if f.displayRows then
        local offset = U.SettingsDisplayOffset(#specs)
        if offset ~= f.displayOffset then
            f.displayOffset = offset
            placeDisplayRows(f, offset)
        end
    end
    local anySpec = #specs == 0 or string.lower(NS.settings.spec or "") == ""
    local color = anySpec and U.theme.accent or U.theme.muted
    f.autoSpec.title:SetTextColor(color[1], color[2], color[3])
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
        label(f,"Settings",U.type.page,22,-20,300)
        local hint = label(f,"Everything the slash commands do, without the slash.",U.type.small,22,-44,380)
        hint:SetTextColor(unpack(muted))
        button(f,"X",430,-14,30,function() f:Hide() end)
        sectionHeader(f,"PLAYSTYLE",22,-76,240)
        f.styles = {}
        for i, style in ipairs(NS.Route.order) do
            local b = button(f, STYLE_LABELS[style] or style, 22 + (i - 1) * 92, -98, 88, function()
                NS.SetStyle(style); U.SyncSettings(f)
            end)
            f.styles[style] = b
        end
        f.specLabel = label(f,"",U.type.body,22,-140,436); f.specLabel:SetTextColor(unpack(muted))
        f.autoSpec = button(f,"Automatic",22,-160,104,function()
            NS.settings.spec = nil; NS.Refresh(); U.SyncSettings(f)
        end, 26)
        f.displayLabel = sectionHeader(f,"DISPLAY",22,-200,240)
        f.arrow = button(f,"Arrow: on",22,-222,104,function()
            NS.settings.arrow = NS.settings.arrow == false
            NS.Refresh(); U.SyncSettings(f)
        end, 26)
        f.compact = button(f,"Tips card: on",134,-222,104,function()
            U.ToggleCompact(); U.SyncSettings(f)
        end, 26)
        f.animations = button(f,"Animations: on",22,-258,150,function()
            NS.settings.animations = NS.settings.animations == false
            U.SyncSettings(f)
        end, 26)
        -- BUG-03 (#179): each stepper gets its own row. A label's SetWidth box is the
        -- worst case for LEFT-justified text, so boxes that clear the buttons mean the
        -- rendered text clears them too; rows are 26px buttons on a 36px pitch.
        f.opacityLabel = label(f,"Opacity",12,22,-300,120)
        f.opacityMinus = button(f,"-",150,-294,22,function()
            U.SetOpacity(math.max(0.30, (NS.settings.opacity or 0.85) - 0.10)); U.SyncSettings(f)
        end, 26)
        f.opacityValue = label(f,"85%",12,178,-300,50)
        f.opacityPlus = button(f,"+",234,-294,22,function()
            U.SetOpacity(math.min(1.0, (NS.settings.opacity or 0.85) + 0.10)); U.SyncSettings(f)
        end, 26)
        f.throttleLabel = label(f,"Tip delay",12,22,-336,120)
        f.throttleMinus = button(f,"-",150,-330,22,function()
            NS.settings.tipThrottleSeconds = math.max(0, (tonumber(NS.settings.tipThrottleSeconds) or 10) - 5)
            U.SyncSettings(f)
        end, 26)
        f.throttleValue = label(f,"10s",12,178,-336,50)
        f.throttlePlus = button(f,"+",234,-330,22,function()
            NS.settings.tipThrottleSeconds = math.min(60, (tonumber(NS.settings.tipThrottleSeconds) or 10) + 5)
            U.SyncSettings(f)
        end, 26)
        f.positionsLabel = sectionHeader(f,"POSITIONS",22,-368,240)
        f.resetPositions = button(f,"Reset all window positions",22,-390,220,function()
            NS.ResetPositions(); U.SyncSettings(f)
        end, 26)
        local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
        local version = tostring(meta and meta("ForeverPath", "Version") or "")
        f.sources = label(f,"ForeverPath " .. version .. " | Route: RestedXP | Quests: AllTheThings",11,22,-444,436)
        f.sources:SetTextColor(unpack(muted))
        -- BUG-05 (#186): base positions of everything from the Display label down, so
        -- SyncSettings can move the whole block under the spec buttons via their y.
        f.displayRows = {
            { f.displayLabel, 22, -200 }, { f.arrow, 22, -222 }, { f.compact, 134, -222 },
            { f.animations, 22, -258 }, { f.opacityLabel, 22, -300 },
            { f.opacityMinus, 150, -294 }, { f.opacityValue, 178, -300 }, { f.opacityPlus, 234, -294 },
            { f.throttleLabel, 22, -336 }, { f.throttleMinus, 150, -330 },
            { f.throttleValue, 178, -336 }, { f.throttlePlus, 234, -330 },
            { f.positionsLabel, 22, -368 }, { f.resetPositions, 22, -390 },
            { f.sources, 22, -444 },
        }
        f.baseHeight = 470
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
