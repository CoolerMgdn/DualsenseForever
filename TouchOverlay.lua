local _, CK = ...
local L = CK.L

-- Fork CoolerMgdn: the touchpad's corners on screen, as the game shows its
-- gamepad bar: the four actions where they sit on the pad, those of the
-- layer held (L1 / R1 / L2 / R2) while it is held, the corner under the
-- finger lit. In the mouse mode: its two buttons. Optional (Touchpad tab).
local O = {}
CK.TouchOverlay = O

local K = CK.ConfigKit
local KC = K.C
local T = CK.Touchpad

local W, H, ICON = 132, 76, 30
local SPOT = {
    upleft = { -W / 4, H / 4 - 4 }, upright = { W / 4, H / 4 - 4 },
    downleft = { -W / 4, -H / 4 - 4 }, downright = { W / 4, -H / 4 - 4 },
}

local function s() return CK.db and CK.db.settings.touch end

local function build()
    if O.frame then return O.frame end
    local f = CK.NewFrame("Frame", "ControllerKeyboardTouchOverlay", UIParent)
    f:SetSize(W, H + 16)
    f:SetFrameStrata("LOW")
    f:Hide()
    -- The pad: a rounded box, its quarters split
    local pad = CK.NewFrame("Frame", nil, f)
    pad:SetSize(W, H)
    pad:SetPoint("BOTTOM")
    f.box = K.Box(pad, 4, 1, "BACKGROUND")
    f.box:SetPoints(pad)
    f.box:SetColors(KC.boxBg, 0.78, KC.boxEdge, 0.9)
    local v = K.Solid(pad, KC.line1, 0.9, "BORDER")
    v:SetWidth(1)
    v:SetPoint("TOP", 0, -6)
    v:SetPoint("BOTTOM", 0, 6)
    local h = K.Solid(pad, KC.line1, 0.9, "BORDER")
    h:SetHeight(1)
    h:SetPoint("LEFT", 6, 0)
    h:SetPoint("RIGHT", -6, 0)
    f.split = h
    f.pad = pad
    f.cells = {}
    for region, spot in pairs(SPOT) do
        local c = {}
        c.lit = K.RoundIcon(pad, ICON + 6, "ARTWORK")
        c.lit:SetDrawLayer("ARTWORK", 1)
        c.lit:SetColorTexture(KC.focus[1], KC.focus[2], KC.focus[3], 0.9)
        c.lit:SetPoint("CENTER", pad, "CENTER", spot[1], spot[2] + 4)
        c.lit:Hide()
        c.icon = K.RoundIcon(pad, ICON, "ARTWORK")
        c.icon:SetDrawLayer("ARTWORK", 2)
        c.icon:SetPoint("CENTER", c.lit, "CENTER")
        -- On the bags' corner: how full they are
        c.count = pad:CreateFontString(nil, "OVERLAY")
        c.count:SetFont(CK:GetFontPath(), 11, "OUTLINE")
        c.count:SetPoint("BOTTOM", c.icon, "BOTTOM", 0, -3)
        c.count:Hide()
        f.cells[region] = c
    end
    -- The mouse mode: its two buttons' names, each half
    f.mouseL = K.Text(pad, 15, KC.cream, "OVERLAY")
    f.mouseL:SetPoint("CENTER", pad, "CENTER", -W / 4, 0)
    f.mouseR = K.Text(pad, 15, KC.cream, "OVERLAY")
    f.mouseR:SetPoint("CENTER", pad, "CENTER", W / 4, 0)
    -- Above it: the layer held, or the mode
    f.title = K.Text(f, 13, KC.title, "OVERLAY")
    f.title:SetPoint("BOTTOM", pad, "TOP", 0, 2)
    f:SetScript("OnUpdate", function(self, elapsed)
        self.wait = (self.wait or 0) - elapsed
        if self.wait > 0 then return end
        self.wait = 0.05
        O:Update()
    end)
    O.frame = f
    return f
end

-- Shown: asked for, and the pad's click ours to give
function O:ShouldShow()
    local t = s()
    return t and t.overlay and T.Blocked() == nil or false
end

-- The settings changed (an action, the place, the mode)
function O:Refresh()
    if not CK.db then return end
    local t = s()
    if not self:ShouldShow() then
        if self.frame then self.frame:Hide() end
        return
    end
    local f = build()
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", UIParent, "BOTTOM", t.overlayX or 0, t.overlayY or 20)
    f:SetScale(t.overlayScale or 1)
    self.layer = nil
    f:Show()
    self:Update()
end

local LAYER_GLYPH = { LB = "LB", RB = "RB", LT = "LT", RT = "RT" }

-- The bags' slots: used, all, free (the plain bags only: a profession's
-- bag takes only its own goods, as the game's backpack count does)
function O.BagSpace()
    local C = C_Container
    local numSlots = C and C.GetContainerNumSlots or GetContainerNumSlots
    local numFree = C and C.GetContainerNumFreeSlots or GetContainerNumFreeSlots
    if not (numSlots and numFree) then return nil end
    local total, free = 0, 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local slots = numSlots(bag) or 0
        local empty, family = numFree(bag)
        if slots > 0 and (family == nil or family == 0) then
            total = total + slots
            free = free + (empty or 0)
        end
    end
    return total - free, total, free
end

local bagEvents = CK.NewFrame("Frame")
bagEvents:RegisterEvent("BAG_UPDATE_DELAYED")
bagEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(bagEvents.RegisterEvent, bagEvents, "BAG_CONTAINER_UPDATE")
bagEvents:SetScript("OnEvent", function() O.bagsDirty = true end)

function O:Update()
    local f = self.frame
    if not (f and f:IsShown()) then return end
    local mouse = T.MouseMode()
    local layer = T.HeldLayer()
    -- The actions: drawn again only when the layer changes
    local armed = T.rightArmed or false
    if layer ~= self.layer or mouse ~= self.mouse or armed ~= self.armed then
        self.layer, self.mouse, self.armed = layer, mouse, armed
        self.bagsDirty = true
        for region, c in pairs(f.cells) do
            local action = T.EffectiveAction(region, layer)
            c.action = action
            CK.Paddles.SetIcon(c.icon, T.Icon(action))
            c.icon:SetDesaturated(not T.IsBound(action))
            c.icon:SetAlpha(T.IsBound(action) and 1 or 0.35)
        end
        f.mouseL:Hide()
        f.mouseR:Hide()
        local parts = {}
        for part in layer:gmatch("%u%u") do parts[#parts + 1] = CK:GlyphMarkup(LAYER_GLYPH[part], 16) end
        local title = table.concat(parts, " + ")
        if mouse then
            local m = T.rightArmed and L.TOUCH_MOUSE_ARMED or (T.DoubleTapOn() and L.TOUCH_MOUSE_TITLE_DT or L.TOUCH_MOUSE_TITLE)
            title = title ~= "" and (m .. "   " .. title) or m
        end
        f.title:SetText(title)
    end
    -- How full the bags are, on the corner that opens them
    if self.bagsDirty then
        self.bagsDirty = false
        local show = s().overlayBags
        local used, total, free
        if show then used, total, free = O.BagSpace() end
        for _, c in pairs(f.cells) do
            local on = show and c.action == "bags" and total and total > 0
            c.count:SetShown(on or false)
            if on then
                c.count:SetText(used .. "/" .. total)
                local color = free <= 2 and KC.danger or (free <= 5 and KC.focus or KC.white)
                c.count:SetTextColor(color[1], color[2], color[3])
            end
        end
    end
    -- The corner (or half) under the finger
    local x, y = T.FingerPosition()
    local touching = x and (math.abs(x) > 0.02 or math.abs(y) > 0.02)
    -- (in the mouse mode the finger moves the cursor: no corner lit)
    local under = touching and not mouse and T.RegionAt(x, y)
    for region, c in pairs(f.cells) do c.lit:SetShown(region == under) end
end
