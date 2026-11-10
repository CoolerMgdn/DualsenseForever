local _, CK = ...

---------------------------------------------------------------------------
-- Fork CoolerMgdn: a clock for the secure code, so a long press is told
-- from a short one in combat too (the idea and the way: ControllerForever's
-- LongPress.lua, its author's code free to reuse).
--
-- The secure snippets get no clock (GetTime is nil there: found, the mic's
-- snippet failed). The game's state driver looks at its drivers five times
-- a second, in combat too (SecureStateDriver.lua, every 0.2 s). The driver
-- here always says "idle"; a button held for its hold sets the clock's
-- state to "tick", so the driver's next look is a change and runs the
-- clock's snippet, which counts one look on every button held ("ec-lp-on")
-- and sets "tick" again while one still counts. HC:Ticks() looks (3: 0.4 -
-- 0.6 s) make a hold, read by the button itself on its release. Nothing
-- runs while nothing is held.
--
-- A client (a router of Mapping.lua, the mic's toggle of Touchpad.lua):
--   on its press   ec-lp-on = true, ec-lp-ticks = 0,
--                  frameref "ec-clock": SetAttribute("state-eclp", "tick")
--   on its release ec-lp-on = nil; held = ec-lp-ticks >= ec-lp-n
-- Fork CoolerMgdn: a double press (a router's) the same way: ec-db-on set on
-- the first press, ec-db-ticks counted up to ec-db-n (then ec-db-on goes);
-- a second press with ec-db-on still set is a double press.
---------------------------------------------------------------------------
local HC = {}
CK.HoldClock = HC

HC.DEFAULT_TICKS = 3
-- A double press: the second within this many looks (2: 0.2 - 0.4 s)
HC.DOUBLE_TICKS = 2
HC.MIN_TICKS, HC.MAX_TICKS = 2, 5

local BODY = [[
    if newstate ~= "idle" then return end
    local again = false
    local limit = self:GetAttribute("ec-ticks") or 3
    for i = 1, self:GetAttribute("ec-n") or 0 do
        local c = self:GetFrameRef("ec-c" .. i)
        if c and c:GetAttribute("ec-lp-on") then
            local t = (c:GetAttribute("ec-lp-ticks") or 0) + 1
            c:SetAttribute("ec-lp-ticks", t)
            if t < limit then again = true end
        end
        if c and c:GetAttribute("ec-db-on") then
            local t = (c:GetAttribute("ec-db-ticks") or 0) + 1
            c:SetAttribute("ec-db-ticks", t)
            if t < (c:GetAttribute("ec-db-n") or 2) then
                again = true
            else
                c:SetAttribute("ec-db-on", nil)
            end
        end
    end
    if again then self:SetAttribute("state-eclp", "tick") end
]]

local clock
local clients = {}      -- frame -> its index on the clock

-- How many looks make a hold (Home > Gamepad, "Long press")
function HC:Ticks()
    local s = CK.db and CK.db.settings
    local t = math.floor(tonumber(s and s.holdTicks) or HC.DEFAULT_TICKS)
    return math.max(HC.MIN_TICKS, math.min(HC.MAX_TICKS, t))
end

-- The time it stands for, as shown: "0.4 - 0.6 s"
function HC:Range()
    local t = self:Ticks()
    return (t - 1) * 0.2, t * 0.2
end

-- Made once, out of combat
function HC:Frame()
    if clock then return clock end
    if InCombatLockdown() then return nil end
    clock = CK.NewFrame("Frame", "ControllerKeyboardHoldClock", UIParent, "SecureHandlerStateTemplate")
    clock:SetAttribute("ec-n", 0)
    clock:SetAttribute("ec-ticks", self:Ticks())
    clock:SetAttribute("_onstate-eclp", BODY)
    RegisterStateDriver(clock, "eclp", "idle")
    return clock
end

-- A secure button timed by the clock (out of combat). False: not now.
function HC:Attach(frame)
    if not frame or InCombatLockdown() then return false end
    local c = self:Frame()
    if not c then return false end
    if not clients[frame] then
        local n = (c:GetAttribute("ec-n") or 0) + 1
        SecureHandlerSetFrameRef(c, "ec-c" .. n, frame)
        c:SetAttribute("ec-n", n)
        clients[frame] = n
    end
    SecureHandlerSetFrameRef(frame, "ec-clock", c)
    frame:SetAttribute("ec-lp-n", self:Ticks())
    frame:SetAttribute("ec-db-n", HC.DOUBLE_TICKS)
    return true
end

-- The hold's length changed: on the clock and every client (out of combat)
function HC:Apply()
    if InCombatLockdown() or not clock then return end
    local t = self:Ticks()
    clock:SetAttribute("ec-ticks", t)
    for frame in pairs(clients) do frame:SetAttribute("ec-lp-n", t) end
end

function HC:SetTicks(t)
    if not (CK.db and CK.db.settings) then return end
    CK.db.settings.holdTicks = math.max(HC.MIN_TICKS, math.min(HC.MAX_TICKS, t))
    self:Apply()
end

-- Plain code: a client held long enough now (feedback only: the press
-- itself is decided by the secure code)
function HC.Held(frame)
    if not frame then return false end
    return (frame:GetAttribute("ec-lp-on") and (frame:GetAttribute("ec-lp-ticks") or 0)
        >= (frame:GetAttribute("ec-lp-n") or HC.DEFAULT_TICKS)) and true or false
end

-- Felt and seen: one short tick of the motors as a held button becomes a
-- hold (onHeld), and onRelease once it is let go after that. Polled while
-- it is down; nothing runs otherwise.
local watching = {}
function HC:Feel(frame, onHeld, onRelease)
    if watching[frame] then watching[frame]:Cancel() end
    local held, started = false, GetTime()
    local ticker
    ticker = C_Timer.NewTicker(0.05, function()
        local on = frame:GetAttribute("ec-lp-on")
        if not on or GetTime() - started > 60 then
            ticker:Cancel()
            watching[frame] = nil
            if held and onRelease then pcall(onRelease) end
            return
        end
        if not held and HC.Held(frame) then
            held = true
            if CK.Vibration and CK.Vibration.Play then pcall(CK.Vibration.Play, CK.Vibration, "tick", nil, 1) end
            if onHeld then pcall(onHeld) end
        end
    end)
    watching[frame] = ticker
end

---------------------------------------------------------------------------
-- Seen (asked): while a button is held past its hold, its picture on the
-- game's gamepad bar (or our extra button) shows the hold's action, and
-- goes back once it is let go. A plain frame of ours over it: nothing of
-- the game's is touched.
---------------------------------------------------------------------------
local SQUARE = { UP = true, DOWN = true, LEFT = true, RIGHT = true }
local cover

local function coverFrame()
    if cover then return cover end
    cover = CK.NewFrame("Frame", nil, UIParent)
    cover:SetFrameStrata("HIGH")
    cover:Hide()
    cover.icon = cover:CreateTexture(nil, "ARTWORK")
    cover.icon:SetAllPoints()
    cover.mask = cover:CreateMaskTexture()
    cover.mask:SetAllPoints(cover.icon)
    cover.mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    cover.glow = cover:CreateTexture(nil, "OVERLAY")
    cover.glow:SetPoint("TOPLEFT", -5, 5)
    cover.glow:SetPoint("BOTTOMRIGHT", 5, -5)
    if CK.Paddles and CK.Paddles.atlasOr then
        CK.Paddles.atlasOr(cover.glow, "gamepad-actionbar-circleslot-border-selected", "Interface\\Minimap\\MiniMap-TrackingBorder")
    end
    cover.glow:SetVertexColor(1, 0.85, 0.3)
    return cover
end

-- The frame showing an input in a layer now: the game's bar button (in a
-- stance, the stance bar's), else our extra button
local function shownButton(input, layer)
    local M = CK.Mapping
    local f
    if input.bar then
        f = M.LAYER_BAR[layer] and (M:LiveBarButton(input, layer) or M:NativeBarButton(input, layer))
    else
        local extra = CK.Paddles and CK.Paddles.frame and CK.Paddles.frame.buttons
        f = extra and extra[input.id]
        f = f and f.visual or f
    end
    if f and f.IsVisible and f:IsVisible() then return f end
end

function HC:ShowHold(router)
    if not (CK.db and CK.db.settings.holdIcon ~= false) then return end
    local M = CK.Mapping
    local input = router and router.ckInput and M.BY_ID[router.ckInput]
    local layer = router and router:GetAttribute("ck-lp")
    if not (input and layer) then return end
    local action = M:GetHold(input.id, layer)
    local icon = action and M:ActionIcon(action)
    local target = icon and shownButton(input, layer)
    if not target then return end
    local c = coverFrame()
    local area = target.icon or target
    c:ClearAllPoints()
    c:SetAllPoints(area)
    c:SetFrameLevel((target:GetFrameLevel() or 1) + 10)
    if CK.Paddles and CK.Paddles.SetIcon then CK.Paddles.SetIcon(c.icon, icon) else c.icon:SetTexture(icon) end
    local square = SQUARE[input.id]
    if square then c.icon:RemoveMaskTexture(c.mask) else c.icon:AddMaskTexture(c.mask) end
    c.glow:SetShown(not square)
    c:Show()
end

function HC:HideHold()
    if cover then cover:Hide() end
end
