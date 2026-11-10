local _, CK = ...
local L = CK.L

---------------------------------------------------------------------------
-- Fork CoolerMgdn (asked): FPS and ping on the screen (Comfort > FPS and
-- ping). Together - in a row or a column, at one place - or apart, each at
-- its own place. A place: a corner or a side's middle, or free (moved with
-- the mouse while "Move with the mouse" is on, or step by step from the
-- settings with the pad). Coloured as they are good: FPS green from 60,
-- yellow from 30, red below; ping green under 100 ms, yellow under 200, red
-- above. Read twice a second.
---------------------------------------------------------------------------
local P = {}
CK.Perf = P

P.PLACES = { "TOPLEFT", "TOP", "TOPRIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT", "FREE" }
P.ARRANGE = { "row", "column", "apart" }
P.SIZES = { 10, 11, 12, 13, 14, 16, 18, 20, 24 }
local DEF = { enabled = false, fps = true, ping = true, arrange = "row", place = "TOPRIGHT", pingPlace = "BOTTOMRIGHT",
    size = 13 }
local MARGIN, EVERY, STEP = 8, 0.5, 10

local function settings()
    local s = CK.db.settings
    if type(s.perf) ~= "table" then s.perf = {} end
    local t = s.perf
    for k, v in pairs(DEF) do
        if t[k] == nil then t[k] = v end
    end
    if type(t.free) ~= "table" then t.free = {} end
    return t
end
P.Settings = settings

local frames = {}       -- group (row, column), fps, ping (apart)

local function rgb(c) return format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end
local GOOD, OK, BAD = { 0.3, 0.9, 0.3 }, { 1, 0.82, 0 }, { 1, 0.3, 0.25 }

local function fpsText()
    local fps = math.floor((GetFramerate and GetFramerate() or 0) + 0.5)
    local c = fps >= 60 and GOOD or (fps >= 30 and OK or BAD)
    return rgb(c) .. format(L.PERF_FPS, fps) .. "|r"
end

local function pingText()
    local home, world = 0, 0
    if GetNetStats then
        local _, _, h, w = GetNetStats()
        home, world = tonumber(h) or 0, tonumber(w) or 0
    end
    local ms = math.max(home, world)
    local c = ms < 100 and GOOD or (ms < 200 and OK or BAD)
    return rgb(c) .. format(L.PERF_MS, ms) .. "|r"
end

-- Which frame keeps which place setting, and its free spot's key
local PLACE_OF = { group = "place", fps = "place", ping = "pingPlace" }

local function frame(key)
    local fr = frames[key]
    if fr then return fr end
    fr = CreateFrame("Frame", "ControllerKeyboardPerf_" .. key, UIParent)
    fr:SetFrameStrata("HIGH")
    fr:SetSize(60, 16)
    fr:SetClampedToScreen(true)
    fr:SetMovable(true)
    fr:RegisterForDrag("LeftButton")
    fr.key = key
    fr.mark = fr:CreateTexture(nil, "BACKGROUND")
    fr.mark:SetPoint("TOPLEFT", -4, 3)
    fr.mark:SetPoint("BOTTOMRIGHT", 4, -3)
    fr.mark:SetColorTexture(1, 0.82, 0, 0.25)
    fr.mark:Hide()
    fr.text = fr:CreateFontString(nil, "OVERLAY")
    fr.text:SetPoint("CENTER")
    fr:SetScript("OnDragStart", function(self) if P.unlocked then self:StartMoving() end end)
    fr:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        P:Keep(self)
    end)
    fr:Hide()
    frames[key] = fr
    return fr
end

-- A frame let go where it is: its place is free, there
function P:Keep(fr)
    local s = settings()
    local x, y = fr:GetCenter()
    if not x then return end
    s.free[fr.key] = { x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
    s[PLACE_OF[fr.key]] = "FREE"
    self:Place()
    if CK.Config and CK.Config.IsOpen and CK.Config:IsOpen() and CK.Config.Render then CK.Config:Render() end
end

local function put(fr, place)
    fr:ClearAllPoints()
    if place == "FREE" then
        local spot = settings().free[fr.key]
        if spot then
            fr:SetPoint("CENTER", UIParent, "BOTTOMLEFT", spot.x, spot.y)
        else
            fr:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        end
        return
    end
    local x = place:find("LEFT") and MARGIN or (place:find("RIGHT") and -MARGIN or 0)
    local y = place:find("TOP") and -MARGIN or MARGIN
    fr:SetPoint(place, UIParent, place, x, y)
end

-- What each frame shows, its size, its place
function P:Place()
    local s = settings()
    local on = s.enabled and (s.fps or s.ping)
    local apart = s.arrange == "apart"
    local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    for _, key in ipairs({ "group", "fps", "ping" }) do
        local fr = frame(key)
        local shown = on and ((key == "group" and not apart) or (apart and key == "fps" and s.fps)
            or (apart and key == "ping" and s.ping))
        fr:SetShown(shown and true or false)
        if shown then
            pcall(fr.text.SetFont, fr.text, font, s.size or 13, "OUTLINE")
            fr.text:SetJustifyH(s.arrange == "column" and "RIGHT" or "CENTER")
            fr:EnableMouse(P.unlocked and true or false)
            fr.mark:SetShown(P.unlocked and true or false)
            put(fr, s[PLACE_OF[key]] or "TOPRIGHT")
        end
    end
    self:Update()
end

function P:Update()
    local s = settings()
    if not (s.enabled and (s.fps or s.ping)) then return end
    local f, p = s.fps and fpsText() or nil, s.ping and pingText() or nil
    if s.arrange == "apart" then
        if f then frames.fps.text:SetText(f) end
        if p then frames.ping.text:SetText(p) end
    else
        local sep = s.arrange == "column" and "\n" or "   "
        frames.group.text:SetText((f or "") .. ((f and p) and sep or "") .. (p or ""))
    end
    for _, key in ipairs({ "group", "fps", "ping" }) do
        local fr = frames[key]
        if fr and fr:IsShown() then
            fr:SetSize(math.max(20, fr.text:GetStringWidth() + 4), math.max(12, fr.text:GetStringHeight() + 2))
        end
    end
end

-- Moved with the mouse, or not
function P:SetUnlocked(on)
    self.unlocked = on and true or false
    self:Place()
end

-- A free place moved by a step (the pad: Comfort's rows)
function P:Nudge(key, dx, dy)
    local s = settings()
    local fr = frame(key)
    if s[PLACE_OF[key]] ~= "FREE" then
        -- (from where it is now)
        P:Keep(fr)
    end
    local spot = s.free[key] or { x = 0, y = 0 }
    spot.x, spot.y = spot.x + dx * STEP, spot.y + dy * STEP
    s.free[key] = spot
    self:Place()
end

local ticker
function P:Apply()
    self:Place()
    local s = settings()
    local on = s.enabled and (s.fps or s.ping)
    if on and not ticker then
        ticker = C_Timer.NewTicker(EVERY, function() P:Update() end)
    elseif not on and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

---------------------------------------------------------------------------
-- Comfort > FPS and ping (Options.lua)
---------------------------------------------------------------------------
local function cycle(list, now, d)
    local at = 1
    for i, v in ipairs(list) do if v == now then at = i end end
    return list[(at - 1 + d) % #list + 1]
end

function P.Rows(b)
    local s = settings()
    b.header(L.SEC_PERF)
    b.module({ id = "perf_on", off = L.OFF_PERF, label = L.LBL_PERF_ON, tip = L.TIP_PERF_ON,
        get = function() return s.enabled end,
        set = function(v)
            s.enabled = v and true or false
            P:Apply()
        end })
    local off = not s.enabled
    b.check({ id = "perf_fps", label = L.LBL_PERF_FPS, indent = true, disabled = off, tip = L.TIP_PERF_FPS,
        get = function() return s.fps end, set = function(v) s.fps = v; P:Apply() end })
    b.check({ id = "perf_ping", label = L.LBL_PERF_PING, indent = true, disabled = off, tip = L.TIP_PERF_PING,
        get = function() return s.ping end, set = function(v) s.ping = v; P:Apply() end })
    b.choice({ id = "perf_arrange", label = L.LBL_PERF_ARRANGE, disabled = off or not (s.fps and s.ping), tip = L.TIP_PERF_ARRANGE,
        text = function() return L["PERF_ARRANGE_" .. s.arrange:upper()] end,
        step = function(d) s.arrange = cycle(P.ARRANGE, s.arrange, d); P:Apply() end })
    local apart = s.arrange == "apart" and s.fps and s.ping
    local function placeRows(key, field, label)
        b.choice({ id = "perf_" .. field, label = label, disabled = off, tip = L.TIP_PERF_PLACE,
            text = function() return L["PERF_PLACE_" .. s[field]] end,
            step = function(d) s[field] = cycle(P.PLACES, s[field], d); P:Apply() end })
        if s[field] == "FREE" and not off then
            b.choice({ id = "perf_" .. key .. "_x", label = L.LBL_PERF_X, indent = true, tip = L.TIP_PERF_NUDGE,
                text = function() local p = s.free[key]; return p and tostring(p.x) or "-" end,
                step = function(d) P:Nudge(key, d, 0) end })
            b.choice({ id = "perf_" .. key .. "_y", label = L.LBL_PERF_Y, indent = true, tip = L.TIP_PERF_NUDGE,
                text = function() local p = s.free[key]; return p and tostring(p.y) or "-" end,
                step = function(d) P:Nudge(key, 0, d) end })
        end
    end
    if apart then
        placeRows("fps", "place", L.LBL_PERF_PLACE_FPS)
        placeRows("ping", "pingPlace", L.LBL_PERF_PLACE_PING)
    else
        placeRows("group", "place", L.LBL_PERF_PLACE)
    end
    b.check({ id = "perf_mouse", label = L.LBL_PERF_MOUSE, disabled = off, tip = L.TIP_PERF_MOUSE,
        get = function() return P.unlocked end, set = function(v) P:SetUnlocked(v) end })
    b.choice({ id = "perf_size", label = L.LBL_PERF_SIZE, disabled = off, tip = L.TIP_PERF_SIZE,
        text = function() return tostring(s.size) end,
        step = function(d) s.size = cycle(P.SIZES, s.size, d); P:Apply() end })
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function()
    if CK.db then P:Apply() end
end)
