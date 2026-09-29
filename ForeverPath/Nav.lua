-- Arrow to the current step, a map waypoint (Blizzard user waypoint) and TomTom when installed.
-- Every client call is guarded: missing APIs degrade to "Open your map", never to a Lua error.
local _, NS = ...
local N = {}
NS.Nav = N

-- Pure: world x grows north, y grows west; facing 0 = north, counterclockwise (GetPlayerFacing).
function N.Bearing(px, py, tx, ty, facing)
    local dx, dy = tx - px, ty - py
    return math.atan2(dy, dx) - (facing or 0), math.sqrt(dx * dx + dy * dy)
end

local function world(map, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    if not ok or type(pos) ~= "table" then return nil end
    if pos.GetXY then return continent, pos:GetXY() end
    return continent, pos.x, pos.y
end

local function playerWorld()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not map then return nil end
    local okPos, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not okPos or type(pos) ~= "table" then return nil end
    local x, y = pos.x, pos.y
    if pos.GetXY then x, y = pos:GetXY() end
    return world(map, x, y)
end

local function create()
    if N.frame then return N.frame end
    local f = CreateFrame("Frame", "ForeverPathArrow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    N.frame = f
    f:SetSize(210, 58)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        f:SetBackdropColor(0.02, 0.03, 0.05, 0.6)
        f:SetBackdropBorderColor(0.18, 0.27, 0.38, 0.8)
    end
    f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if NS.UI and NS.UI.Remember then NS.UI.Remember(self, "arrowPosition") end
    end)
    if NS.UI and NS.UI.Restore then NS.UI.Restore(f, "arrowPosition", "TOP", UIParent, "TOP", 0, -200)
    else f:SetPoint("TOP", UIParent, "TOP", 0, -200) end
    f.arrow = f:CreateTexture(nil, "ARTWORK")
    f.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    f.arrow:SetSize(42, 42); f.arrow:SetPoint("LEFT", 8, 0)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.text:SetPoint("LEFT", 56, 0); f.text:SetWidth(146); f.text:SetJustifyH("LEFT")
    local elapsed = 0
    f:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + (delta or 0)
        if elapsed >= 0.05 then elapsed = 0; N.Update() end
    end)
    return f
end

local function key(target) return target and string.format("%s:%.1f:%.1f", target.map, target.x, target.y) end

function N.SetTarget(target, title)
    if not target or not target.map then N.target = nil; if N.frame then N.frame:Hide() end; return end
    if N.target and key(N.target) == key(target) then N.target.title = title; return end
    N.target = { map = target.map, x = target.x, y = target.y, title = title }
    local x, y = target.x / 100, target.y / 100
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        pcall(function()
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(target.map, x, y))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        end)
    end
    if TomTom and TomTom.AddWaypoint then
        if N.tomtom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, N.tomtom) end
        local ok, uid = pcall(TomTom.AddWaypoint, TomTom, target.map, x, y, { title = title, persistent = false, minimap = true, world = true })
        N.tomtom = ok and uid or nil
    end
    create():Show()
    N.Update()
end

function N.Update()
    local f, target = N.frame, N.target
    if not f or not target then return end
    local title = target.title or "Next step"
    local continent, tx, ty = world(target.map, target.x / 100, target.y / 100)
    local playerContinent, px, py = playerWorld()
    if not tx or not px or continent ~= playerContinent then
        f.arrow:Hide()
        f.text:SetText(title .. "\nOpen your map (M): waypoint set")
        return
    end
    local ok, facing = pcall(GetPlayerFacing)
    local angle, distance = N.Bearing(px, py, tx, ty, ok and facing or 0)
    if distance < 10 then
        f.arrow:Hide()
        f.text:SetText(title .. "\nYou are there")
        return
    end
    f.arrow:Show()
    f.arrow:SetRotation(angle)
    f.text:SetText(string.format("%s\n%d yd", title, math.floor(distance + 0.5)))
end

-- The arrow follows the top step; a card's "Show way" pins that step until it is done.
function N.Pin(row)
    N.pinned = row and row.id or nil
    if row then N.SetTarget(row.target, row.title) end
end

function N.Follow(rows)
    if NS.settings and NS.settings.arrow == false then N.SetTarget(nil); return end
    local chosen
    for _, row in ipairs(rows or {}) do
        if row.target and row.id == N.pinned then chosen = row end
    end
    if not chosen then
        N.pinned = nil
        for _, row in ipairs(rows or {}) do
            if row.target then chosen = row; break end
        end
    end
    N.SetTarget(chosen and chosen.target, chosen and chosen.title)
end
