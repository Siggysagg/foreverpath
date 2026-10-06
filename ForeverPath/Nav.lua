-- Arrow to the current step, and a map waypoint (Blizzard user waypoint). Our own arrow only; no TomTom.
-- Every client call is guarded: missing APIs degrade to "Open your map", never to a Lua error.
local _, NS = ...
local N = {}
NS.Nav = N

-- Pure: world x grows north, y grows west; facing 0 = north, counterclockwise (GetPlayerFacing).
function N.Bearing(px, py, tx, ty, facing)
    local dx, dy = tx - px, ty - py
    return math.atan2(dy, dx) - (facing or 0), math.sqrt(dx * dx + dy * dy)
end

-- Pure: one wording for a distance in yards everywhere (arrow text, hero panel).
function N.FormatDistance(yards)
    if not yards then return nil end
    if yards < 10 then return "You are there" end
    return string.format("%d yd", math.floor(yards + 0.5))
end

-- One reusable vector for map->world conversions (CreateVector2D would allocate every tick).
local scratch
local function world(map, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    scratch = scratch or CreateVector2D(0, 0)
    if scratch.SetXY then scratch:SetXY(x, y) else scratch.x, scratch.y = x, y end
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, map, scratch)
    if not ok or type(pos) ~= "table" then return nil end
    if pos.GetXY then return continent, pos:GetXY() end
    return continent, pos.x, pos.y
end

local function now() return GetTime and GetTime() or nil end

-- The player's map ID is cached; zone events clear it and it is re-queried at least once a second.
local function playerMap()
    local t = now()
    if N.mapId and t and N.mapAt and t - N.mapAt < 1 then return N.mapId end
    local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
    N.mapId, N.mapAt = ok and map or nil, t
    return N.mapId
end

-- Raw map position of the player: map, x, y (nil when unavailable).
local function playerRaw()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local map = playerMap()
    if not map then return nil end
    local okPos, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not okPos or type(pos) ~= "table" then return nil end
    local x, y = pos.x, pos.y
    if pos.GetXY then x, y = pos:GetXY() end
    return map, x, y
end

local function playerWorld(map, x, y)
    if not map then map, x, y = playerRaw() end
    if not map then return nil end
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
    local ev = CreateFrame("Frame")
    N.eventFrame = ev
    ev:RegisterEvent("ZONE_CHANGED_NEW_AREA"); ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function() N.mapId = nil; N.lx = nil end)
    local elapsed = 0
    f:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + (delta or 0)
        if elapsed >= 0.066 then elapsed = 0; N.Update() end
    end)
    return f
end

-- Target world coords are computed once and cached on the target; retried only while unavailable
-- (e.g. map data not ready at SetTarget time).
local function targetWorld(target)
    if not target.wx then
        target.wc, target.wx, target.wy = world(target.map, target.x / 100, target.y / 100)
    end
    return target.wc, target.wx, target.wy
end

local function setText(f, text)
    if N.lastText ~= text then N.lastText = text; f.text:SetText(text) end
end

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function validTarget(target)
    return type(target) == "table" and finite(target.map) and finite(target.x) and finite(target.y)
end

local function waypointValues(point)
    if type(point) ~= "table" then return nil end
    local map = point.uiMapID or point.mapID or point.map
    local position = point.position
    local x, y = point.x, point.y
    if type(position) == "table" then
        x, y = position.x, position.y
        if type(position.GetXY) == "function" then x, y = position:GetXY() end
    end
    return map, x, y
end

local function sameWaypoint(a, b)
    if a == b then return true end
    local am, ax, ay = waypointValues(a)
    local bm, bx, by = waypointValues(b)
    return am ~= nil and am == bm and ax == bx and ay == by
end

local function clearWaypoint()
    if not (N.waypoint and C_Map and C_Map.GetUserWaypoint and C_Map.ClearUserWaypoint) then
        N.waypoint = nil
        return
    end
    local ok, current = pcall(C_Map.GetUserWaypoint)
    if ok and sameWaypoint(current, N.waypoint) then
        pcall(C_Map.ClearUserWaypoint)
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, false)
        end
    end
    N.waypoint = nil
end

local function key(target) return string.format("%s:%.6f:%.6f", target.map, target.x, target.y) end

function N.SetTarget(target, title)
    -- A decoded share string can carry a map without x/y; arithmetic on nil would
    -- error every refresh, so anything without usable coordinates is no target.
    if not validTarget(target) then
        clearWaypoint()
        N.target, N.distanceText = nil, nil
        if N.frame then N.frame:Hide() end
        return
    end
    if N.target and key(N.target) == key(target) then N.target.title = title; return end
    N.target = { map = target.map, x = target.x, y = target.y, title = title }
    N.lastText, N.lastAngle, N.lx, N.distanceText = nil, nil, nil, nil
    targetWorld(N.target)
    local x, y = target.x / 100, target.y / 100
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        pcall(function()
            local point = UiMapPoint.CreateFromCoordinates(target.map, x, y)
            C_Map.SetUserWaypoint(point)
            N.waypoint = point
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        end)
    end
    create():Show()
    N.Update()
end

function N.Update()
    local f, target = N.frame, N.target
    if not f or not target then return end
    local title = target.title or "Next step"
    local continent, tx, ty = targetWorld(target)
    local map, rx, ry = playerRaw()
    local ok, facing = pcall(GetPlayerFacing)
    local t = now()
    -- Nothing moved or turned since the last full tick: skip, but recompute at least once a second.
    if t and N.lx ~= nil and map == N.lmap and rx == N.lx and ry == N.ly and facing == N.lf
        and N.lt and t - N.lt < 1 then return end
    local playerContinent, px, py = playerWorld(map, rx, ry)
    if not tx or not px or continent ~= playerContinent then
        N.lx, N.distanceText = nil, nil
        f.arrow:Hide()
        setText(f, title .. "\nOpen your map (M): waypoint set")
        return
    end
    N.lmap, N.lx, N.ly, N.lf, N.lt = map, rx, ry, facing, t
    local angle, distance = N.Bearing(px, py, tx, ty, ok and facing or 0)
    local text = N.FormatDistance(distance)
    N.distanceText = text
    local isArrived = text == "You are there"
    if isArrived then
        f.arrow:Hide()
        if not N.arrived then
            N.arrived = true
            if f.SetBackdropBorderColor then
                f:SetBackdropBorderColor(0.37, 0.84, 0.55, 0.9)
                if C_Timer and C_Timer.After then
                    C_Timer.After(1.0, function()
                        if f and f.SetBackdropBorderColor and N.arrived then
                            f:SetBackdropBorderColor(0.37, 0.84, 0.55, 0.4)
                        end
                    end)
                end
            end
        end
    else
        f.arrow:Show()
        if not N.lastAngle or math.abs(angle - N.lastAngle) > 0.02 then
            N.lastAngle = angle
            f.arrow:SetRotation(angle)
        end
        if N.arrived then
            N.arrived = false
            if f.SetBackdropBorderColor then
                f:SetBackdropBorderColor(0.12, 0.18, 0.26, 0.4)
            end
        end
    end
    setText(f, title .. "\n" .. text)
end

N.arrived = false

-- Reuse the arrow's guarded distance sample instead of repeating map conversions.
function N.DistanceText()
    return N.target and C_Map and N.distanceText or nil
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
        local top = rows and rows[1]  -- same step the panel shows; no coordinates means no arrow, never a later step's
        chosen = top and top.target and top or nil
    end
    N.SetTarget(chosen and chosen.target, chosen and chosen.title)
end
