local _, NS = ...
local U = {}
NS.UI = U
local accent = {0.30, 0.72, 1.00}
local muted = {0.64, 0.70, 0.78}
local warning = {1.00, 0.68, 0.30}
local function panel(parent, name, width, height)
    local f = CreateFrame("Frame", name, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(width, height)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        f:SetBackdropColor(0.025, 0.035, 0.055, 0.98)
        f:SetBackdropBorderColor(0.18, 0.27, 0.38, 1)
    end
    return f
end
local function label(parent, text, size, x, y, width)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f:SetFont(STANDARD_TEXT_FONT, size)
    f:SetPoint("TOPLEFT", x, y)
    f:SetWidth(width)
    f:SetJustifyH("LEFT")
    f:SetTextColor(0.90, 0.93, 0.98)
    f:SetText(text)
    return f
end
local function button(parent, text, x, y, width, action)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 30); b:SetPoint("TOPLEFT", x, y)
    local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.09, 0.13, 0.17, 1)
    local title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("CENTER"); title:SetTextColor(unpack(accent)); title:SetText(text)
    b.title = title
    b:SetScript("OnEnter", function() bg:SetColorTexture(0.13,0.22,0.25,1) end)
    b:SetScript("OnLeave", function() bg:SetColorTexture(0.09,0.13,0.17,1) end)
    b:SetScript("OnClick", action)
    return b
end
function U.Create()
    if U.frame then return end
    local f = panel(UIParent, "ForeverPathWindow", 740, 570)
    U.frame = f
    f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
    f:SetScale(math.min(1, UIParent:GetWidth()/780, UIParent:GetHeight()/610))
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        NS.settings.position = {p, rp, x, y}
    end)
    local pos = NS.settings.position
    if type(pos) == "table" and type(pos[1]) == "string" and type(pos[2]) == "string" and type(pos[3]) == "number" and type(pos[4]) == "number" then
        local ok = pcall(function() f:ClearAllPoints(); f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) end)
        if not ok then f:ClearAllPoints(); f:SetPoint("CENTER") end
    end
    table.insert(UISpecialFrames, "ForeverPathWindow")
    local stripe = f:CreateTexture(nil,"ARTWORK"); stripe:SetPoint("TOPLEFT",1,-1); stripe:SetSize(738,3); stripe:SetColorTexture(unpack(accent))
    label(f,"FOREVERPATH",22,24,-24,440)
    U.subtitle = label(f,"Your next step, explained.",12,24,-54,660); U.subtitle:SetTextColor(unpack(muted))
    button(f,"X",682,-18,34,function() f:Hide() end)
    button(f,"Live rewards",24,-88,140,function() NS.SetDemo(false) end)
    button(f,"Demo paths",172,-88,140,function() NS.SetDemo(true) end)
    button(f,"Diagnostics",552,-88,164,function() U.Diagnostics() end)
    U.banner = label(f,"",13,24,-138,690)
    U.context = label(f,"",12,24,-163,690)
    U.profile = button(f,"Choose profile",24,-190,230,function() NS.CycleProfile() end)
    U.goal = button(f,"Goal: balanced",266,-190,220,function() NS.CycleGoal() end)
    button(f,"Compact",498,-190,106,function() U.ToggleCompact() end)
    button(f,"Refresh",616,-190,100,function() NS.Refresh() end)
    local scroll = CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",24,-237); scroll:SetPoint("BOTTOMRIGHT",-40,52)
    U.child = CreateFrame("Frame",nil,scroll); U.child:SetSize(664,1); scroll:SetScrollChild(U.child)
    U.scroll, U.cards = scroll, {}
    U.footer = label(f,"Prototype 0.1.0 | /fp | Experimental stat weights",11,24,-539,690)
    f:Hide()
end
local function card(index)
    if U.cards[index] then return U.cards[index] end
    local f = panel(U.child,nil,664,116)
    f:SetPoint("TOPLEFT",0,-(index-1)*126)
    f.title = label(f,"",15,16,-14,460)
    f.badge = label(f,"",11,458,-16,190); f.badge:SetJustifyH("RIGHT"); f.badge:SetTextColor(unpack(accent))
    f.body = label(f,"",12,16,-41,630); f.body:SetHeight(62); f.body:SetJustifyV("TOP")
    f:EnableMouse(true)
    f:SetScript("OnEnter",function(self)
        if self.link and GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetHyperlink(self.link); GameTooltip:Show() end
    end)
    f:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
    U.cards[index] = f
    return f
end
function U.Render(state)
    U.Create()
    U.lastState = state
    local mode = NS.demo and "DEMO - INVENTED EXAMPLE DATA" or (state.mode == "next" and "LIVE - WHAT TO DO NEXT" or "LIVE - QUEST DIALOGUE REWARDS")
    U.banner:SetText(mode)
    if NS.demo then U.banner:SetTextColor(unpack(warning)) else U.banner:SetTextColor(unpack(accent)) end
    U.context:SetText(NS.demo and "Example character: level 15 | Blacksmithing 75 | Budget 2g" or
        string.format("Level %s | %s | %s quests | %s",state.level or "?",state.zone or "?",state.questCount or 0,state.questTitle or "Next quests for you"))
    local profile = NS.Engine.profiles[NS.settings.profile]
    U.profile.title:SetText("Profile: " .. (state.profileLabel or (profile and profile.label) or "automatic"))
    U.goal.title:SetText("Goal: " .. (NS.settings.goal or "balanced"))
    U.goal:SetEnabled(true)
    local rows = state.rows or {}
    for i = 1, math.max(1,#rows) do
        local row = rows[i]
        local c = card(i)
        c.title:SetText(row and row.title or "Ready when you are")
        c.badge:SetText(row and row.verdict or "Waiting")
        c.body:SetText(row and table.concat(row.reasons or {},"\n") or state.message or "No suggestions yet.")
        c.link = row and row.link or nil
        c:Show()
    end
    for i = math.max(1,#rows)+1,#U.cards do U.cards[i]:Hide() end
    U.child:SetHeight(math.max(1,#rows)*126)
    local offset = U.scroll:GetVerticalScroll()
    U.scroll:SetVerticalScroll(math.min(offset,math.max(0,U.child:GetHeight()-U.scroll:GetHeight())))
    if U.hud then
        local first = rows[1]
        local prefix = NS.demo and "DEMO | SYNTHETIC | " or "LIVE | "
        local text = prefix .. (first and (first.title .. "\n" .. first.verdict) or state.message or "No suggestion")
        if U.hud.lastText ~= text then
            U.hud.text:SetText(text)
            U.hud.lastText = text
        end
    end
end
function U.Toggle()
    U.Create()
    if U.frame:IsShown() then U.frame:Hide() else U.frame:Show(); NS.Refresh() end
end
function U.ToggleCompact()
    if not U.hud then
        local h = panel(UIParent,"ForeverPathCompact",330,78)
        U.hud = h
        if Minimap then
            -- Anchor the compact tip card to the real Minimap frame instead of a
            -- fixed UIParent offset. A fixed offset can land under/over the
            -- minimap once UI scale, minimap size or minimap skin differ from
            -- the assumed default (reported: overlap with the minimap at UI
            -- scale 0.8). Anchoring to Minimap:GetBottom() keeps the card
            -- clear of it at any scale or position.
            h:SetPoint("TOP", Minimap, "BOTTOM", 0, -18)
        else
            h:SetPoint("TOP", UIParent, "TOP", 0, -120)
        end
        h:SetClampedToScreen(true)
        h:SetMovable(true); h:EnableMouse(true); h:RegisterForDrag("LeftButton")
        h:SetScript("OnDragStart",h.StartMoving)
        h:SetScript("OnDragStop",function(self)
            self:StopMovingOrSizing()
            local p, _, rp, x, y = self:GetPoint()
            NS.settings.compactPosition = {p, rp, x, y}
        end)
        local pos = NS.settings.compactPosition
        if type(pos) == "table" and type(pos[1]) == "string" and type(pos[2]) == "string" and type(pos[3]) == "number" and type(pos[4]) == "number" then
            local ok = pcall(function() h:ClearAllPoints(); h:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) end)
            if not ok then h:ClearAllPoints(); h:SetPoint("TOP", Minimap or UIParent, Minimap and "BOTTOM" or "TOP", 0, Minimap and -18 or -120) end
        end
        h.text = label(h,"",12,14,-14,274); h.text:SetHeight(52); h.text:SetJustifyV("TOP")
        h.dismiss = button(h,"Hide",230,-6,60,function() local row = U.lastState and U.lastState.rows and U.lastState.rows[1]; if row then NS.DismissTip(row) end end)
        button(h,"X",294,-6,28,function() h:Hide() end)
        h:Hide()
    end
    if U.hud:IsShown() then U.hud:Hide() else U.hud:Show(); NS.Refresh() end
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
