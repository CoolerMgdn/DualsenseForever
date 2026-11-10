local _, CK = ...
local L = CK.L

-- The guide (asked): screens over the configuration panel, shown once on a
-- new install, again from Home > Guide, /ec welcome or the game menu.
-- Every choice is the panel's own setting, saved at once; the guide has no
-- "cancel all" (a rerun can start from scratch, behind a confirm). It is a
-- layer over the panel's window (the panel keeps the pad and passes the
-- presses here), with its own header and help bar.
--
-- Fork CoolerMgdn, 2.0 (asked, its prototype approved): screens by name,
-- the path through them chosen on the way: quick (the controller, the
-- wheels, two comforts, the addon's look) or detailed (all of it), and the
-- controller's branch: a DualSense (its touchpad's corners, light, Create
-- and the mic; an Edge's back buttons) or the others (paddles and touchpads,
-- as before). After an update, "What's new" once, the guide offered.
--
-- Modes: "normal"; "identify" (the back paddles, then the touchpad buttons
-- turned on, each pressed when asked); "bind" (a wheel's key: the button or
-- combination pressed next); "preview" (the gamepad bar's size, the window
-- made small at the top of the screen so the bar shows behind it);
-- "confirm" (start from scratch?).
local G = {}
CK.Guide = G

local K = CK.ConfigKit
local KC = K.C
local TEX = K.TEX
local W, H = 820, 580
local VERSION = 2
local MAX_DOTS = 10
-- The classes that heal
local HEALERS = { PRIEST = true, DRUID = true, SHAMAN = true, PALADIN = true }
local IDENTIFY_WAIT = 5
local BIND_WAIT = 10

local function settings() return CK.db.settings end
local function C() return CK.Config end
local function M() return CK.Mapping end
local function P() return CK.Paddles end
local function Wheel() return CK.ConsumableWheel end
local function Touch() return CK.Touchpad end
local function touchSettings() return CK.db.settings.touch end

-- The screens, and the order they are built in
G.SCREENS = { "whatsnew", "welcome", "controller", "dualsense", "paddles", "bar", "keyboard", "wheels", "comfort",
    "look", "done" }
G.BUILD = {}
-- The quick way by default, each time it opens
G.quick = true

local function indexOf(list, v)
    for i, x in ipairs(list) do
        if x == v then return i end
    end
end

---------------------------------------------------------------------------
-- Drawing helpers: places from the top left, as the design gives them
---------------------------------------------------------------------------
local function at(region, parent, x, y, w, h)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    if w then region:SetWidth(w) end
    if h then region:SetHeight(h) end
    return region
end

-- Friz (titles, labels)
local function text(parent, size, color, x, y)
    local fs = K.Text(parent, size, color)
    if x then at(fs, parent, x, y) end
    return fs
end

-- The chat's font (help texts), wrapped in its width
local function help(parent, size, color, x, y, w)
    local fs = K.ChatText(parent, size or 14, color or KC.help)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    if x then at(fs, parent, x, y) end
    if w then
        fs:SetWidth(w)
        fs:SetWordWrap(true)
    end
    return fs
end

local function image(parent, name, x, y, w, h, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(TEX .. name)
    at(t, parent, x, y, w, h)
    return t
end

-- A glow over its picture (same place and size), lit by its alpha
local function glow(parent, name, x, y, w, h)
    local t = image(parent, name, x, y, w, h, "OVERLAY")
    t:SetBlendMode("ADD")
    t:SetAlpha(0)
    return t
end

local function rule(parent, x, y, w, h)
    local t = K.Solid(parent, KC.line3, 1, "ARTWORK")
    at(t, parent, x, y, w or 1, h or 1)
    return t
end

-- A rounded box on a frame (edge 1 px)
local function box(frame, fill, fillAlpha, edge, edgeAlpha)
    local b = K.Box(frame, 4, 1, "BACKGROUND")
    b:SetPoints(frame)
    b:SetColors(fill, fillAlpha or 1, edge, edgeAlpha or 1)
    return b
end

local function frameAt(parent, kind, x, y, w, h)
    local f = CK.NewFrame(kind or "Frame", nil, parent)
    at(f, parent, x, y, w, h)
    return f
end

-- The focus look (gold edge) or the plain one
local function focusLook(b, focused)
    if focused then
        b:SetColors(KC.nowBg, 1, KC.focus, 1)
    else
        b:SetColors(KC.controlBg, 1, KC.line1, 1)
    end
end

---------------------------------------------------------------------------
-- Controls. Each: frame (a click is an A on it), draw(c, focused), and as
-- needed press(c) for A, adjust(c, delta) with lr = true (left / right
-- change it), enabled(c), shown(c) (hidden ones take no focus), verbA(c)
---------------------------------------------------------------------------
local function add(screen, c)
    screen.controls[#screen.controls + 1] = c
    c.screen = screen
    if c.frame then
        -- (the screen's owner: the guide, or a window built with its parts)
        c.frame:SetScript("OnClick", function() (screen.owner or G):Click(c) end)
    end
    return c
end

local function enabled(c)
    return not c.enabled or c.enabled(c) and true or false
end

local function shown(c)
    return not c.shown or c.shown(c) and true or false
end

-- A button of the panel's look (primary: the gold text when not focused)
local function button(screen, parent, label, x, y, w, h, primary, onPress)
    local b = K.Button(parent, h and h < 40 and 15 or 16)
    at(b, parent, x, y, w, h or 40)
    b.label:SetText(label)
    local c = add(screen, { frame = b, press = onPress })
    function c.verbA() return L.V_CONFIRM end
    function c.draw(self, focused)
        local live = enabled(self)
        b:SetState({ focus = focused, disabled = not live })
        if primary and live and not focused then b.label:SetTextColor(unpack(KC.title)) end
    end
    return c
end

-- A check box: its box (20 x 20), its label, its help under it
local function check(screen, parent, x, y, w, label, helpText, get, set)
    local f = frameAt(parent, "Button", x, y, w, 34)
    f.bg = box(f, KC.nowBg, 0, KC.focus, 0)
    f.boxFrame = frameAt(f, "Frame", 8, 7, 20, 20)
    f.box = K.Box(f.boxFrame, 3, 2, "ARTWORK")
    f.box:SetPoints(f.boxFrame)
    -- (on the box's own frame, over its fill, as the panel's)
    f.tick = f.boxFrame:CreateTexture(nil, "OVERLAY")
    f.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    f.tick:SetSize(26, 26)
    f.tick:SetPoint("CENTER", f.boxFrame, "CENTER", 0, 0)
    f.tick:SetVertexColor(unpack(KC.focus))
    f.label = text(f, 16, KC.cream, 38, 8)
    f.label:SetText(label)
    if helpText then
        f.help = help(f, 14, KC.help, 38, 30, w - 50)
        f.help:SetText(helpText)
    end
    local c = add(screen, { frame = f, get = get, set = set })
    function c.press(self)
        self.set(not self.get())
        return true
    end
    function c.verbA(self) return self.get() and L.GUIDE_UNTICK or L.GUIDE_TICK end
    function c.draw(self, focused)
        local on, live = self.get() and true or false, enabled(self)
        f.bg:SetColors(KC.nowBg, focused and 1 or 0, KC.focus, focused and 1 or 0)
        f.box:SetColors(KC.controlBg, 1, focused and KC.focus or KC.boxEdge, 1)
        f.tick:SetShown(on)
        f.label:SetTextColor(unpack(not live and KC.disabled or (focused and KC.focusText or KC.cream)))
        f:SetAlpha(live and 1 or 0.5)
        f:SetHeight(f.help and math.max(34, 30 + (f.help:GetStringHeight() or 0) + 8) or 34)
    end
    return c
end

-- An on / off switch: a pill 40 x 20, its knob right when on
local function switch(parent, x, y)
    local s = frameAt(parent, "Frame", x, y, 40, 20)
    s.pill = K.Box(s, 4, 1, "ARTWORK")
    s.pill:SetPoints(s)
    s.knob = s:CreateTexture(nil, "OVERLAY")
    s.knob:SetTexture(TEX .. "ck_dot")
    s.knob:SetSize(13, 13)
    function s:Set(on, focused)
        self.pill:SetColors(on and { 0.18, 0.14, 0.06 } or KC.controlBg, 1,
            focused and KC.focus or (on and KC.dimGold or KC.line1), 1)
        self.knob:SetVertexColor(unpack(on and KC.focus or KC.disabled))
        self.knob:ClearAllPoints()
        self.knob:SetPoint(on and "RIGHT" or "LEFT", self, on and "RIGHT" or "LEFT", on and -4 or 4, 0)
    end
    return s
end

-- A line with a label (and its help) and a switch at its right
local function switchLine(screen, parent, x, y, w, h, label, helpText, get, set)
    local f = frameAt(parent, "Button", x, y, w, h)
    f.bg = box(f, KC.nowBg, 0, KC.focus, 0)
    f.label = text(f, 16, KC.cream, 12, helpText and 8 or (h - 16) / 2)
    if helpText then
        f.help = help(f, 14, KC.help, 12, 30, w - 80)
        f.help:SetText(helpText)
    end
    f.sw = switch(f, w - 52, (h - 20) / 2)
    local c = add(screen, { frame = f, get = get, set = set })
    function c.press(self)
        self.set(not self.get())
        return true
    end
    function c.verbA(self) return self.get() and L.GUIDE_TURN_OFF or L.GUIDE_TURN_ON end
    function c.draw(self, focused)
        local on = self.get() and true or false
        f.bg:SetColors(KC.nowBg, focused and 1 or 0, KC.focus, focused and 1 or 0)
        f.sw:Set(on, focused)
        f.label:SetText(type(label) == "function" and label(on) or label)
        f.label:SetTextColor(unpack(focused and KC.focusText or KC.cream))
    end
    return c
end

-- < value >: left / right (or A) change it
local function selector(screen, parent, x, y, w, getText, step)
    local f = frameAt(parent, "Button", x, y, w, 32)
    f.bg = box(f, KC.controlBg, 1, KC.line1, 1)
    f.left = text(f, 16, KC.dimGold)
    f.left:SetPoint("LEFT", 10, 0)
    f.left:SetText("<")
    f.right = text(f, 16, KC.dimGold)
    f.right:SetPoint("RIGHT", -10, 0)
    f.right:SetText(">")
    f.value = text(f, 15, KC.cream)
    f.value:SetPoint("LEFT", 26, 0)
    f.value:SetPoint("RIGHT", -26, 0)
    f.value:SetJustifyH("CENTER")
    local c = add(screen, { frame = f, lr = true })
    function c.adjust(_, d)
        step(d)
        return true
    end
    function c.press()
        step(1)
        return true
    end
    function c.verbA() return L.V_CHANGE end
    function c.draw(self, focused)
        local live = enabled(self)
        focusLook(f.bg, focused)
        f.value:SetText(getText())
        f.value:SetTextColor(unpack(not live and KC.disabled or (focused and KC.focus or KC.cream)))
        f.left:SetTextColor(unpack(focused and KC.focus or KC.dimGold))
        f.right:SetTextColor(unpack(focused and KC.focus or KC.dimGold))
        f:SetAlpha(live and 1 or 0.4)
    end
    return c
end

local function stepIn(list, current, d)
    local index = 1
    for i, e in ipairs(list) do
        if e.key == current then index = i end
    end
    return list[(index - 1 + d) % #list + 1]
end

local function nameIn(list, current)
    for _, e in ipairs(list) do
        if e.key == current then return e.name end
    end
    return list[1].name
end
-- Fork CoolerMgdn: a "new" chip after a title (2.0's own parts)
local function newChip(parent, after)
    local f = CK.NewFrame("Frame", nil, parent)
    local b = K.Box(f, 3, 1, "ARTWORK")
    b:SetPoints(f)
    b:SetColors(KC.focus, 0.14, KC.focus, 0.8)
    local t = text(f, 10, KC.focus)
    t:SetPoint("CENTER", 0, 0)
    t:SetText(L.GUIDE_NEW)
    f:SetSize((t:GetStringWidth() or 30) + 12, 16)
    f:SetPoint("LEFT", after, "RIGHT", 8, 0)
    return f
end

-- A title with its "new" chip
local function newTitle(parent, size, x, y, label)
    local t = text(parent, size, KC.title, x, y)
    t:SetText(label)
    newChip(parent, t)
    return t
end

-- A choice of several (its ring lit when chosen), its line under the
-- name (sub), the four face buttons of a glyph style at its right
local function radio(screen, parent, x, y, w, h, label, sub, isOn, pick, glyphStyle)
    local r = frameAt(parent, "Button", x, y, w, h)
    r.bg = box(r, KC.controlBg, 1, KC.line1, 1)
    r.ring = r:CreateTexture(nil, "ARTWORK")
    r.ring:SetTexture(TEX .. "ck_ring")
    r.ring:SetSize(16, 16)
    r.dot = r:CreateTexture(nil, "OVERLAY")
    r.dot:SetTexture(TEX .. "ck_dot")
    r.dot:SetSize(8, 8)
    r.dot:SetPoint("CENTER", r.ring, "CENTER")
    r.dot:SetVertexColor(unpack(KC.focus))
    r.label = text(r, 16, KC.cream)
    if sub then
        r.ring:SetPoint("TOPLEFT", 14, -12)
        at(r.label, r, 40, 10)
        r.sub = help(r, 13, KC.help, 40, 32, w - 54 - (glyphStyle and 116 or 0))
        r.sub:SetText(sub)
    else
        r.ring:SetPoint("LEFT", 14, 0)
        r.label:SetPoint("LEFT", 40, 0)
    end
    r.label:SetText(label)
    if glyphStyle then
        -- A, B, X, Y (bottom, right, left, top) in that style
        r.glyphs = {}
        for i, key in ipairs({ "Y", "X", "B", "A" }) do
            local g = r:CreateTexture(nil, "ARTWORK")
            g:SetSize(22, 22)
            g:SetPoint("RIGHT", -14 - (i - 1) * 28, 0)
            r.glyphs[key] = g
        end
    end
    local c = add(screen, { frame = r, isOn = isOn })
    function c.press()
        pick()
        return true
    end
    function c.verbA() return L.V_CHOOSE end
    function c.draw(self, focused)
        local on, live = isOn() and true or false, enabled(self)
        focusLook(r.bg, focused)
        r.ring:SetVertexColor(unpack(on and KC.focus or KC.boxEdge))
        r.dot:SetShown(on)
        r.label:SetTextColor(unpack(not live and KC.disabled or (focused and KC.focus or KC.cream)))
        r:SetAlpha(live and 1 or 0.5)
        if r.glyphs then
            for key, g in pairs(r.glyphs) do CK:SetGlyph(g, key, glyphStyle) end
        end
    end
    return c
end

-- A selector with its label at its left
local function labeled(screen, parent, x, y, w, labelW, label, getText, step)
    local lab = help(parent, 14, KC.help, x, y + 8, labelW - 8)
    lab:SetText(label)
    local c = selector(screen, parent, x + labelW, y, w - labelW, getText, step)
    c.label = lab
    return c
end

-- An info box (blue edge)
local function infoBox(parent, x, y, w, h)
    local f = frameAt(parent, "Frame", x, y, w, h)
    box(f, KC.yours, 0.06, KC.info, 0.45)
    return f
end

local function diamond(parent, x, y, color)
    local d = parent:CreateTexture(nil, "ARTWORK")
    d:SetTexture(TEX .. "ck_diamond")
    d:SetVertexColor(unpack(color or KC.dimGold))
    at(d, parent, x, y, 8, 8)
    return d
end

-- Fork CoolerMgdn: the guide's parts, for the other windows built like it
-- (Exchange.lua). A screen given an owner sends its clicks there.
G.Kit = { at = at, text = text, help = help, image = image, rule = rule, box = box, frameAt = frameAt,
    focusLook = focusLook, add = add, enabled = enabled, shown = shown, button = button, check = check,
    selector = selector, radio = radio, labeled = labeled, infoBox = infoBox, diamond = diamond, newChip = newChip,
    newTitle = newTitle }

---------------------------------------------------------------------------
-- The controller (Fork CoolerMgdn, 2.0): picked on the guide's second step,
-- the path after it follows
---------------------------------------------------------------------------
local PADS = {
    { key = "dualsense", glyphs = "playstation" },
    { key = "xbox", glyphs = "xbox" },
    { key = "other", glyphs = "xbox" },
}

function G:PadKind()
    local k = settings().padKind
    if k == "dualsense" or k == "xbox" or k == "other" then return k end
    return M().PlayStation() and "dualsense" or "xbox"
end

function G:Edge()
    return self:PadKind() == "dualsense" and settings().dualsenseEdge == true
end

function G:SetPadKind(key)
    settings().padKind = key
    for _, pad in ipairs(PADS) do
        if pad.key == key then CK:PickGlyphStyle(pad.glyphs) end
    end
end

-- What the game says of the controller in use (nil: none, or unknown)
function G.Detected()
    local style = CK:GameLabelStyle()
    if style == "Shapes" then return "dualsense" end
    if style == "Letters" then return "xbox" end
end

-- The screens of this run, in order
function G:Path()
    local ds = self:PadKind() == "dualsense"
    local p = { "welcome", "controller" }
    if not self.quick then
        p[#p + 1] = ds and "dualsense" or "paddles"
        p[#p + 1] = "bar"
        p[#p + 1] = "keyboard"
    elseif ds and self:Edge() then
        p[#p + 1] = "dualsense"
    end
    for _, sid in ipairs({ "wheels", "comfort", "look", "done" }) do p[#p + 1] = sid end
    return p
end

---------------------------------------------------------------------------
-- The window: a layer over the panel's, its header and help bar
---------------------------------------------------------------------------
function G:Build()
    if self.frame then return end
    local panel = C().frame
    local o = CK.NewFrame("Frame", "ControllerKeyboardGuide", panel)
    o:SetAllPoints(panel)
    o:SetFrameLevel(panel:GetFrameLevel() + 60)
    o:EnableMouse(true)
    K.Panel(o)
    -- Header
    o.kicker = text(o, 11, KC.dimGold, 24, 14)
    o.title = text(o, 22, KC.title, 24, 29)
    o.close = K.Button(o, 14)
    o.close:SetSize(30, 28)
    o.close:SetPoint("TOPRIGHT", -20, -18)
    o.close.label:SetText("X")
    o.close:SetScript("OnClick", function() G:Later() end)
    o.count = help(o, 14, KC.help)
    o.count:SetPoint("RIGHT", o.close, "LEFT", -12, 0)
    o.dots = {}
    for i = 1, MAX_DOTS do o.dots[i] = o:CreateTexture(nil, "ARTWORK") end
    o.headRule = rule(o, 16, 62, W - 32)
    -- Help bar: the crumb on the left, the hints on the right
    o.bar = CK.NewFrame("Frame", nil, o)
    o.bar:SetSize(W - 4, 46)
    local bg = K.Solid(o.bar, KC.panel, 1, "BACKGROUND")
    bg:SetAllPoints()
    rule(o.bar, 0, 0, W - 4)
    o.crumb = K.ChatText(o.bar, 13, KC.grey)
    o.crumb:SetPoint("LEFT", 22, 0)
    o.crumb:SetWordWrap(false)
    o.hints = {}
    self.frame = o
    self.screens = {}
    for _, sid in ipairs(G.SCREENS) do
        local s = { sid = sid, controls = {} }
        s.frame = CK.NewFrame("Frame", nil, o)
        s.frame:SetAllPoints(o)
        s.frame:Hide()
        G.BUILD[sid](self, s, s.frame)
        self.screens[sid] = s
    end
    self:BuildPreview(o)
    self:BuildConfirm(o)
    o:SetScript("OnUpdate", function() G:OnUpdate() end)
    o:Hide()
end

---------------------------------------------------------------------------
-- What's new (after an update, once): what came, the guide offered
---------------------------------------------------------------------------
local WHATS_NEW = 10

G.BUILD.whatsnew = function(_, s, f)
    help(f, 14, KC.help, 24, 72, 772):SetText(L.GUIDE_WN_INTRO)
    for i = 1, WHATS_NEW do
        local x, y = i <= 5 and 24 or 428, 104 + ((i - 1) % 5) * 72
        diamond(f, x, y + 6, KC.focus)
        text(f, 15, KC.cream, x + 16, y):SetText(L["GUIDE_WN_" .. i])
        help(f, 13, KC.help, x + 16, y + 22, 352):SetText(L["GUIDE_WN_" .. i .. "_TEXT"])
    end
    rule(f, 24, 462, 772)
    help(f, 13, KC.grey, 24, 478, 380):SetText(L.GUIDE_WN_AGAIN)
    button(s, f, L.GUIDE_LATER, 428, 474, 156, 40, false, function() G:Later() end)
    s.take = button(s, f, L.GUIDE_TAKE, 596, 474, 200, 40, true, function() G:Go("welcome") end)
    function s.first() return s.take end
end

---------------------------------------------------------------------------
-- Welcome: quick or detailed; over the player's settings (a rerun), or
-- from scratch behind a confirm
---------------------------------------------------------------------------
local GLYPH_STYLES = {
    { key = "auto", name = L.GLYPH_AUTO },
    { key = "xbox", name = "Xbox" },
    { key = "playstation", name = "PlayStation" },
    { key = "switch", name = "Switch" },
}

G.BUILD.welcome = function(_, s, f)
    image(f, "ck_onb_welcome", 24, 72, 384, 192)
    for i = 1, 3 do
        local y = 276 + (i - 1) * 40
        diamond(f, 24, y + 6)
        help(f, 16, KC.cream, 40, y, 368):SetText(L["GUIDE_WELCOME2_" .. i])
    end
    -- The panel's shortcut
    local sc = frameAt(f, "Frame", 24, 404, 384, 58)
    box(sc, KC.controlBg, 1, KC.line3, 1)
    text(sc, 15, KC.cream2, 14, 10):SetText(L.GUIDE_SHORTCUT)
    s.shortcut = help(sc, 14, KC.help, 14, 33, 356)
    -- How: quick or detailed
    newTitle(f, 16, 428, 72, L.GUIDE_HOW)
    help(f, 14, KC.help, 428, 94, 368):SetText(L.GUIDE_HOW_HELP)
    s.quick = radio(s, f, 428, 122, 368, 72, L.GUIDE_QUICK, L.GUIDE_QUICK_TEXT,
        function() return G.quick end, function() G.quick = true end)
    radio(s, f, 428, 202, 368, 72, L.GUIDE_DETAILED, L.GUIDE_DETAILED_TEXT,
        function() return not G.quick end, function() G.quick = false end)
    -- A rerun: over the player's settings, from scratch behind a confirm
    local rb = infoBox(f, 428, 284, 368, 128)
    text(rb, 15, KC.info, 14, 12):SetText(L.GUIDE_RERUN)
    help(rb, 14, KC.cream2, 14, 36, 340):SetText(L.GUIDE_RERUN_TEXT)
    s.scratch = button(s, rb, L.GUIDE_SCRATCH, 14, 80, 340, 36, false, function() G:AskScratch() end)
    s.scratch.shown = function() return G.rerun end
    function s.scratch.verbA() return L.GUIDE_OPEN end
    -- The first time: the tip
    local tip = infoBox(f, 428, 284, 368, 128)
    text(tip, 15, KC.info, 14, 12):SetText(L.GUIDE_TIP)
    help(tip, 14, KC.cream2, 14, 36, 340):SetText(L.GUIDE_TIP_DS)
    button(s, f, L.GUIDE_LATER, 428, 468, 156, 40, false, function() G:Later() end)
    button(s, f, L.GUIDE_START, 596, 468, 200, 40, true, function() G:Next() end)
    function s.enter()
        local chord = settings().shortcut or CK.DEFAULT_SHORTCUT
        s.shortcut:SetText(format(L.GUIDE_SHORTCUT_KEYS, M():ChordLabel(chord)) .. L.GUIDE_SHORTCUT_MENU)
    end
    function s.first() return s.quick end
    function s.render()
        rb:SetShown(G.rerun and true or false)
        tip:SetShown(not G.rerun)
    end
end

---------------------------------------------------------------------------
-- Your controller: what the game found, the pick (its glyphs too), an Edge
---------------------------------------------------------------------------
G.BUILD.controller = function(_, s, f)
    text(f, 16, KC.title, 24, 72):SetText(L.GUIDE_PAD_TITLE)
    local det = frameAt(f, "Frame", 24, 98, 378, 58)
    det.bg = box(det, KC.panel, 1, KC.line1, 1)
    det.title = text(det, 15, KC.cream2, 14, 10)
    det.help = help(det, 13, KC.help, 14, 32, 350)
    s.pads = {}
    for i, pad in ipairs(PADS) do
        local up = pad.key:upper()
        s.pads[i] = radio(s, f, 24, 166 + (i - 1) * 62, 378, 56, L["GUIDE_PAD_" .. up], L["GUIDE_PAD_" .. up .. "_TEXT"],
            function() return G:PadKind() == pad.key end,
            function() G:SetPadKind(pad.key) end, pad.glyphs)
    end
    s.edge = check(s, f, 24, 362, 378, L.GUIDE_EDGE, L.GUIDE_EDGE_HELP,
        function() return settings().dualsenseEdge == true end,
        function(v) settings().dualsenseEdge = v and true or nil end)
    s.edge.shown = function() return G:PadKind() == "dualsense" end
    -- The pad (the Gamepad tab's picture), the paddles' for the others
    s.padPic = f:CreateTexture(nil, "ARTWORK")
    at(s.padPic, f, 428, 98, 368, 264)
    s.padPic:SetTexCoord(0, 960 / 1024, 0, 688 / 1024)
    s.otherPic = image(f, "ck_onb_paddles", 428, 128, 368, 184)
    s.note = help(f, 14, KC.help, 428, 372, 368)
    function s.first()
        for _, c in ipairs(s.pads) do
            if c.isOn() then return c end
        end
        return s.pads[1]
    end
    function s.render()
        local found, kind = G.Detected(), G:PadKind()
        if found then
            det.bg:SetColors(KC.yours, 0.06, KC.info, 0.45)
            det.title:SetTextColor(unpack(KC.info))
            det.title:SetText(format(L.GUIDE_PAD_FOUND, L["GUIDE_PAD_" .. found:upper()]))
            det.help:SetText(L.GUIDE_PAD_FOUND_HELP)
        else
            det.bg:SetColors(KC.panel, 1, KC.line1, 1)
            det.title:SetTextColor(unpack(KC.cream2))
            det.title:SetText(L.GUIDE_PAD_NONE)
            det.help:SetText(L.GUIDE_PAD_NONE_HELP)
        end
        s.otherPic:SetShown(kind == "other")
        s.padPic:SetShown(kind ~= "other")
        s.padPic:SetTexture(TEX .. (kind == "dualsense" and "ck_pad_ps" or "ck_pad"))
        s.note:SetText(kind ~= "dualsense" and L.GUIDE_PAD_NEXT_OTHER
            or (G:Edge() and L.GUIDE_PAD_NEXT_EDGE or L.GUIDE_PAD_NEXT_DS))
    end
end

---------------------------------------------------------------------------
-- The addon's look: its glyphs, its window (look and scale)
---------------------------------------------------------------------------
local CONFIG_LOOKS = { "frame", "blizzard", "large" }

G.BUILD.look = function(_, s, f)
    text(f, 16, KC.title, 24, 72):SetText(L.GUIDE_GLYPHS)
    help(f, 14, KC.help, 24, 94, 378):SetText(L.GUIDE_GLYPHS_HELP)
    s.radios = {}
    for n, style in ipairs(GLYPH_STYLES) do
        s.radios[n] = radio(s, f, 24, 122 + (n - 1) * 45, 378, 40, style.name, nil,
            function() return settings().glyphStyle == style.key end,
            function() CK:PickGlyphStyle(style.key) end, style.key)
    end
    local native = check(s, f, 24, 306, 378, L.GUIDE_NATIVE, L.GUIDE_NATIVE_HELP,
        function() return settings().nativeGlyphs == true end,
        function(v)
            settings().nativeGlyphs = v and true or false
            CK:UpdateGlyphs()
        end)
    native.enabled = function() return settings().gameGlyphs and true or false end
    newTitle(f, 16, 428, 72, L.GUIDE_WINDOW)
    for i, key in ipairs(CONFIG_LOOKS) do
        local up = key:upper()
        radio(s, f, 428, 100 + (i - 1) * 60, 368, 54, L["CFG_LOOK_" .. up], L["GUIDE_LOOK_" .. up],
            function() return K.LookOf(settings().configLook) == key end,
            function() settings().configLook = key end)
    end
    labeled(s, f, 428, 290, 368, 150, L.GUIDE_SCALE,
        function() return format("%d %%", C().Scale() * 100 + 0.5) end,
        function(d) C():SetScale(C().Scale() + d * 0.05) end)
    help(f, 13, KC.grey, 428, 330, 368):SetText(L.GUIDE_LOOK_NOTE)
    function s.first()
        for _, c in ipairs(s.radios) do
            if c.isOn() then return c end
        end
        return s.radios[1]
    end
end

---------------------------------------------------------------------------
-- The DualSense: its touchpad's corners, light, Create and the mic, an
-- Edge's back buttons
---------------------------------------------------------------------------
local CORNERS = { "windows", "current", "none" }
local CORNER_ORDER = { "upleft", "upright", "downleft", "downright" }
local WINDOW_CORNERS = { upleft = "character", upright = "bags", downleft = "questlog", downright = "map" }

-- The corners' pick: this run's, else read from the settings
function G:CornerPick()
    if self.cornerPick then return self.cornerPick end
    local t = touchSettings()
    if t.enabled == false then return "none" end
    for k, v in pairs(WINDOW_CORNERS) do
        if t.regions[k] ~= v then return "current" end
    end
    return "windows"
end

-- "current": the corners as they were when the guide opened
function G:SetCorners(key)
    if CK:BlockedByCombat() then return end
    local t, saved = touchSettings(), self.savedTouch
    t.regions = t.regions or {}
    if key == "windows" then
        t.enabled = true
        for k, v in pairs(WINDOW_CORNERS) do t.regions[k] = v end
    elseif key == "current" then
        t.enabled = true
        if saved then
            for _, k in ipairs(CORNER_ORDER) do t.regions[k] = saved.regions[k] end
        end
    else
        t.enabled = false
    end
    self.cornerPick = key
    Touch():Apply()
    if CK.TouchOverlay then CK.TouchOverlay:Refresh() end
end

-- Create and the mic: a few actions offered (nil: the game's own)
local CREATE_ACTIONS = { "wheel:usable", "wheel:consumables", "wheel:phrases", false }
local MIC_ACTIONS = { "cmd:CONTROLLERKEYBOARD_TOGGLE", "wheel:phrases", "wheel:marks", false }
local PS_NAMES = { ["wheel:usable"] = "USABLE_WHEEL_NAME", ["wheel:consumables"] = "WHEEL_NAME",
    ["wheel:phrases"] = "PHRASES_NAME", ["wheel:marks"] = "MARK_WHEEL_NAME",
    ["cmd:CONTROLLERKEYBOARD_TOGGLE"] = "LBL_CHAT_KEYBOARD" }

local function psAction(id) return M():Get(id, "") or M():GetReplaced(id, "") end

local function psName(id)
    local now = psAction(id)
    if not now then return L.GUIDE_PS_GAME end
    if PS_NAMES[now] then return L[PS_NAMES[now]] end
    return M():ActionName(now) or now
end

local function setPs(id, action)
    if CK:BlockedByCombat() then return end
    if not action then return M():Set(id, "", nil) end
    local page, input = CK.MapPage, M().BY_ID[id]
    local hold = page.hold
    page.hold = false
    local ok = page:Put(input, "", action)
    page.hold = hold
    if not ok then C():Toast(L.GUIDE_PS_REFUSED, true) end
end

local function stepPs(id, list, d)
    local now = psAction(id) or false
    local i = indexOf(list, now) or 0
    setPs(id, list[(i - 1 + d) % #list + 1])
end

-- The ask box (the paddles' and the Edge's)
local function askBox(f, x, y, w)
    local ask = frameAt(f, "Frame", x, y, w, 90)
    box(ask, KC.nowBg, 1, KC.focus, 1)
    ask.title = text(ask, 22, KC.focus, 16, 12)
    ask.help = help(ask, 14, KC.cream2, 16, 44, w - 32)
    ask.dots = {}
    ask:Hide()
    return ask
end

local function cornerLabel(action)
    if action == nil or action == "none" then return nil end
    local T = Touch()
    local ok, name = pcall(T.Label, action)
    return ok and type(name) == "string" and name or tostring(action)
end

G.BUILD.dualsense = function(_, s, f)
    newTitle(f, 16, 24, 72, L.GUIDE_CORNERS)
    -- The touchpad from above: its corners, what each opens
    local pad = frameAt(f, "Frame", 24, 98, 378, 100)
    box(pad, { 0.08, 0.067, 0.05 }, 1, KC.bronze, 1)
    s.quads = {}
    for i, key in ipairs(CORNER_ORDER) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local q = frameAt(pad, "Frame", 6 + col * 183, 6 + row * 44, 183, 44)
        q.bg = box(q, KC.focus, 0, KC.line3, 1)
        q.label = K.ChatText(q, 14, KC.cream)
        q.label:SetPoint(col == 0 and "LEFT" or "RIGHT", col == 0 and 14 or -14, 0)
        q.label:SetWordWrap(false)
        q.label:SetWidth(155)
        q.label:SetJustifyH(col == 0 and "LEFT" or "RIGHT")
        q.key = key
        s.quads[i] = q
    end
    for i, key in ipairs(CORNERS) do
        local up = key:upper()
        radio(s, f, 24, 206 + (i - 1) * 54, 378, 50, L["GUIDE_CORNERS_" .. up], L["GUIDE_CORNERS_" .. up .. "_TEXT"],
            function() return G:CornerPick() == key end,
            function() G:SetCorners(key) end)
    end
    local overlay = check(s, f, 24, 370, 378, L.LBL_TOUCH_OVERLAY, L.GUIDE_OVERLAY_HELP,
        function() return touchSettings().overlay and true or false end,
        function(v)
            touchSettings().overlay = v and true or false
            if CK.TouchOverlay then CK.TouchOverlay:Refresh() end
        end)
    overlay.enabled = function() return G:CornerPick() ~= "none" end
    -- The light
    text(f, 16, KC.title, 428, 72):SetText(L.GUIDE_LIGHT)
    labeled(s, f, 428, 98, 368, 150, L.GUIDE_LIGHT_MODE,
        function()
            local mode = touchSettings().light or "off"
            return L["TOUCH_LIGHT_" .. mode:upper()]
        end,
        function(d)
            local modes = Touch().LightModes()
            local i = indexOf(modes, touchSettings().light) or 1
            Touch():SetLight(modes[(i - 1 + d) % #modes + 1])
        end)
    -- Create and the mic: their glyph, where they are, their action
    text(f, 16, KC.title, 428, 146):SetText(L.GUIDE_PS_KEYS)
    local function psKey(y, id, where, list)
        local g = text(f, 16, KC.cream, 428, y + 2)
        g:SetText(K.ComboMarkup(id, "", 30))
        help(f, 12, KC.grey, 428, y + 36, 150):SetText(where)
        selector(s, f, 586, y, 210, function() return psName(id) end, function(d) stepPs(id, list, d) end)
    end
    psKey(172, "CREATE", L.GUIDE_CREATE_WHERE, CREATE_ACTIONS)
    psKey(222, "MIC", L.GUIDE_MIC_WHERE, MIC_ACTIONS)
    help(f, 12, KC.grey, 586, 258, 210):SetText(L.GUIDE_MIC_NOTE)
    -- An Edge's back buttons
    s.edgeTitle = text(f, 16, KC.title, 428, 290)
    s.edgeTitle:SetText(L.GUIDE_EDGE_TITLE)
    s.edgeHelp = help(f, 14, KC.help, 428, 314, 368)
    s.edgeHelp:SetText(L.GUIDE_EDGE_HOW)
    s.ask = askBox(f, 428, 314, 368)
    s.identify = button(s, f, L.GUIDE_EDGE_IDENTIFY, 428, 360, 260, 40, false,
        function() G:StartIdentify({ "L4", "R4" }) end)
    s.identify.shown = function() return G:Edge() and G.mode ~= "identify" end
    s.found = help(f, 14, KC.done, 428, 404, 368)
    s.noEdge = help(f, 13, KC.grey, 428, 294, 368)
    s.noEdge:SetText(L.GUIDE_EDGE_NONE)
    rule(f, 24, 440, 772)
    s.rt = check(s, f, 24, 448, 772, L.LBL_RT_MODIFIER, L.GUIDE_RT_HELP,
        function() return M():TriggerModifier("PADRTRIGGER") ~= nil end,
        function(v) M():SetTriggerModifier("PADRTRIGGER", v) end)
    s.rt.enabled = function() return M():CanBeModifier("PADRTRIGGER") and true or false end
    s.rt.shown = function() return G:Edge() end
    s.modNote = help(f, 13, KC.grey, 24, 454, 772)
    s.modNote:SetText(L.GUIDE_DS_MODIFIERS)
    function s.render()
        local pick, t = G:CornerPick(), touchSettings()
        for _, q in ipairs(s.quads) do
            local name = pick ~= "none" and cornerLabel(t.regions[q.key]) or nil
            q.label:SetText(name or "—")
            q.label:SetTextColor(unpack(name and KC.cream or KC.disabled))
            q.bg:SetColors(KC.focus, name and 0.18 or 0.02, name and KC.dimGold or KC.line3, 1)
        end
        local edge = G:Edge()
        s.edgeTitle:SetShown(edge)
        s.noEdge:SetShown(not edge)
        s.modNote:SetShown(not edge)
    end
end


---------------------------------------------------------------------------
-- 2. Back paddles and touchpads
---------------------------------------------------------------------------
-- (the pictures' full names: the packaging checks every one is shipped)
local PADDLE_GLOW = { L4 = "ck_onb_paddles_l4_glow", R4 = "ck_onb_paddles_r4_glow",
    L5 = "ck_onb_paddles_l5_glow", R5 = "ck_onb_paddles_r5_glow" }
local ZONES = { "up", "right", "down", "left" }
local ZONE_GLOW = { "ck_onb_touchpad_up_glow", "ck_onb_touchpad_right_glow", "ck_onb_touchpad_down_glow",
    "ck_onb_touchpad_left_glow" }

-- A touchpad on: its 4 buttons turned on
local function touchSide(side)
    local on = settings().touchButtons
    if type(on) ~= "table" then return false end
    for n = 1, 4 do
        if on["T" .. side .. n] ~= true then return false end
    end
    return true
end

local function setTouchSide(side, v)
    local s = settings()
    s.touchButtons = s.touchButtons or {}
    for n = 1, 4 do s.touchButtons["T" .. side .. n] = v or nil end
    M():Apply()
    P():Apply()
end

local function mappingOn() return settings().modules.mapping and true or false end

G.BUILD.paddles = function(_, s, f)
    text(f, 16, KC.title, 24, 72):SetText(L.GUIDE_PADDLES)
    image(f, "ck_onb_paddles", 24, 100, 400, 200)
    s.paddlesGlow = glow(f, "ck_onb_paddles_glow", 24, 100, 400, 200)
    s.paddleGlow = {}
    for id, name in pairs(PADDLE_GLOW) do
        s.paddleGlow[id] = glow(f, name, 24, 100, 400, 200)
    end
    s.paddlesHelp = help(f, 14, KC.help, 24, 308, 400)
    s.paddlesHelp:SetText(L.GUIDE_PADDLES_HELP)
    s.identify = button(s, f, L.GUIDE_IDENTIFY, 24, 360, 260, 40, false, function() G:StartIdentify() end)
    -- While identifying (2b): what is asked
    local ask = frameAt(f, "Frame", 24, 308, 400, 90)
    box(ask, KC.nowBg, 1, KC.focus, 1)
    ask.title = text(ask, 22, KC.focus, 16, 12)
    ask.help = help(ask, 14, KC.cream2, 16, 44, 368)
    ask.dots = {}
    ask:Hide()
    s.ask = ask
    -- What was recognised
    s.found = help(f, 14, KC.done, 24, 404, 400)
    -- Touchpads
    s.right = CK.NewFrame("Frame", nil, f)
    s.right:SetAllPoints(f)
    text(s.right, 16, KC.title, 448, 72):SetText(L.GUIDE_TOUCH)
    image(s.right, "ck_onb_touchpad", 448, 100, 160, 160)
    s.zoneGlow = {}
    for n, name in ipairs(ZONE_GLOW) do
        s.zoneGlow[n] = glow(s.right, name, 448, 100, 160, 160)
    end
    for i, side in ipairs({ "L", "R" }) do
        local c = check(s, s.right, 624, 112 + (i - 1) * 46, 172, L["GUIDE_TOUCH_" .. side], nil,
            function() return touchSide(side) end,
            function(v)
                setTouchSide(side, v)
                if v then G.zonesAt = GetTime() end
            end)
        c.enabled = mappingOn
    end
    help(s.right, 14, KC.help, 448, 272, 348):SetText(L.GUIDE_TOUCH_HELP)
    s.rule = rule(f, 24, 424, 772)
    s.rt = check(s, f, 24, 438, 772, L.LBL_RT_MODIFIER, L.GUIDE_RT_HELP,
        function() return M():TriggerModifier("PADRTRIGGER") ~= nil end,
        function(v) M():SetTriggerModifier("PADRTRIGGER", v) end)
    s.rt.enabled = function() return M():CanBeModifier("PADRTRIGGER") and true or false end
    function s.first() return s.identify end
end

---------------------------------------------------------------------------
-- 2b. Each paddle (then each touchpad button turned on) pressed when asked;
-- 5 seconds with nothing: the next one. X skips, B stops.
---------------------------------------------------------------------------
local function askHelp(id)
    local side, n = id:match("^T([LR])(%d)$")
    if side then
        return format(L.GUIDE_ASK_TOUCH, L["GUIDE_TOUCH_" .. side], L["GUIDE_ZONE_" .. ZONES[tonumber(n)]:upper()])
    end
    return L["GUIDE_ASK_" .. id] or ""
end

function G:StartIdentify(list)
    if CK:BlockedByCombat() then return end
    self.mode = "identify"
    -- (an Edge's: its two back buttons)
    self.queue = list or P():Order()
    self.queueAt = 1
    self.found = {}
    self:AskNext()
end

function G:AskNext()
    local id = self.queue[self.queueAt]
    if not id then return self:EndIdentify(true) end
    local asked = { id = id }
    self.asked, self.askedAt = asked, GetTime()
    P():Capture(id, function(key)
        if G.asked ~= asked then return end
        if key then G.found[#G.found + 1] = id end
        G.queueAt = G.queueAt + 1
        G:AskNext()
    end)
    self:Render()
end

function G:EndIdentify(done)
    self.asked = nil
    if P():IsCapturing() then P():StopCapture(nil) end
    self.mode = "normal"
    if done then
        C():Toast(#self.found > 0 and format(L.GUIDE_IDENTIFIED, table.concat(self.found, ", "))
            or L.GUIDE_IDENTIFIED_NONE, #self.found == 0)
    end
    self:Render()
end

---------------------------------------------------------------------------
-- 3. The gamepad bar
---------------------------------------------------------------------------
-- The size's slider: 70 to 150 %, the value saved before the preview marked
local function slider(screen, parent, x, y, w)
    local MIN, MAX = P().BAR_SCALE_MIN, P().BAR_SCALE_MAX
    local f = frameAt(parent, "Button", x, y, w, 64)
    f.bg = box(f, KC.controlBg, 1, KC.line1, 1)
    f.min = help(f, 14, KC.help)
    f.min:SetPoint("LEFT", 18, 0)
    f.min:SetText(format("%d %%", MIN * 100 + 0.5))
    f.value = text(f, 20, KC.focus)
    f.value:SetPoint("RIGHT", -18, 0)
    f.value:SetWidth(72)
    f.value:SetJustifyH("RIGHT")
    f.max = help(f, 14, KC.help)
    f.max:SetPoint("RIGHT", f.value, "LEFT", -16, 0)
    f.max:SetText(format("%d %%", MAX * 100 + 0.5))
    f.rail = CK.NewFrame("Frame", nil, f)
    f.rail:SetHeight(8)
    f.railBox = K.Box(f.rail, 3, 2, "ARTWORK")
    f.railBox:SetPoints(f.rail)
    f.railBox:SetColors(KC.controlBg, 1, KC.line1, 1)
    f.fill = K.Solid(f.rail, KC.fill, 1, "ARTWORK", 3)
    f.fill:SetPoint("LEFT", f.rail, "LEFT", 1, 0)
    f.fill:SetHeight(6)
    f.mark = K.Solid(f.rail, KC.boxEdge, 1, "ARTWORK", 4)
    f.mark:SetSize(1, 6)
    f.handle = f.rail:CreateTexture(nil, "OVERLAY")
    f.handle:SetTexture(TEX .. "ck_dot")
    f.handle:SetSize(20, 20)
    local c = add(screen, { frame = f, lr = true })
    function c.adjust(_, d)
        G:Preview(d)
        return true
    end
    function c.press()
        G:Preview(0)
        return true
    end
    function c.verbA() return L.GUIDE_PREVIEW end
    function c.draw(_, focused)
        focusLook(f.bg, focused)
        local k = P():BarScale()
        f.value:SetText(format("%d %%", k * 100 + 0.5))
        -- The rail between "70 %" and "150 %", its width worked out here (a
        -- width from its anchors may not be known yet the first time)
        local left = 18 + (f.min:GetStringWidth() or 0) + 16
        local width = math.max(40, w - left - (18 + 72 + 16 + (f.max:GetStringWidth() or 0) + 16))
        f.rail:ClearAllPoints()
        f.rail:SetPoint("LEFT", f, "LEFT", left, 0)
        f.rail:SetWidth(width)
        local t = (k - MIN) / (MAX - MIN)
        f.fill:SetWidth(math.max(1, (width - 2) * t))
        f.handle:ClearAllPoints()
        f.handle:SetPoint("CENTER", f.rail, "LEFT", width * t, 0)
        f.handle:SetVertexColor(unpack(focused and KC.focus or KC.dimGold))
        local saved = G.previewFrom or k
        f.mark:ClearAllPoints()
        f.mark:SetPoint("TOP", f.rail, "BOTTOMLEFT", width * (saved - MIN) / (MAX - MIN), -3)
    end
    return c
end

G.BUILD.bar = function(_, s, f)
    text(f, 16, KC.title, 24, 72):SetText(L.GUIDE_BAR_SIZE)
    s.slider = slider(s, f, 24, 100, 772)
    help(f, 14, KC.help, 24, 174, 772):SetText(L.GUIDE_BAR_SIZE_HELP)
    s.toggle = check(s, f, 24, 226, 496, L.LBL_TRIGGER_TOGGLE, L.GUIDE_TOGGLE_HELP,
        function() return settings().features.triggerToggle == true end,
        function(v)
            settings().features.triggerToggle = v
            M():Apply()
        end)
    s.toggle.enabled = mappingOn
    image(f, "ck_onb_toggle", 540, 214, 256, 128)
    s.toggleGlow = glow(f, "ck_onb_toggle_glow", 540, 214, 256, 128)
    -- Edit Mode's compact bar: what it is, the button turning it on (asked)
    local compact = frameAt(f, "Frame", 24, 364, 772, 150)
    box(compact, KC.yours, 0.06, KC.info, 0.45)
    text(compact, 16, KC.info, 16, 14):SetText(L.GUIDE_EDITMODE_TITLE)
    help(compact, 14, KC.cream2, 16, 40, 500):SetText(L.GUIDE_EDITMODE_TEXT)
    s.compact = button(s, compact, L.GUIDE_COMPACT_ON, 532, 44, 224, 38, false, function()
        G:SetCompact(not P().CompactBar())
    end)
    s.compact.shown = function() return G:CanSetCompact() end
    s.compactNote = help(compact, 12, KC.grey, 532, 90, 224)
    s.compactNote:SetText(L.GUIDE_COMPACT_RELOAD)
    function s.first() return s.slider end
    function s.render()
        local can = G:CanSetCompact()
        s.compact.frame:SetShown(can)
        s.compactNote:SetShown(can)
        s.compact.frame.label:SetText(P().CompactBar() and L.GUIDE_COMPACT_OFF or L.GUIDE_COMPACT_ON)
    end
end

---------------------------------------------------------------------------
-- 3c. The compact bar (asked): Edit Mode's setting of the gamepad bar
-- (system 30) in the layout in use. The game's Gamepad layout can't change:
-- a copy of it is made ("Easy Controller"), as Edit Mode does. Saved with
-- the game's own functions, then the interface reloaded: no Edit Mode frame
-- or method is used from here (its taint would spread to the bar), the
-- reload applies the layout as the game loads it.
---------------------------------------------------------------------------
local COMPACT_LAYOUT = "Easy Controller"

local function compactIds()
    local E = Enum
    return E and E.EditModeSystem and E.EditModeSystem.GamepadMainActionBar,
        E and E.EditModeGamepadMainActionBarSetting and E.EditModeGamepadMainActionBarSetting.Compact,
        E and E.InputDeviceInterfaceType and E.InputDeviceInterfaceType.Gamepad
end

local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = deepCopy(v) end
    return c
end

function G:CanSetCompact()
    local system, setting, gamepad = compactIds()
    return system ~= nil and setting ~= nil and gamepad ~= nil and C_EditMode ~= nil
        and C_EditMode.GetLayouts ~= nil and C_EditMode.SaveLayouts ~= nil
        and EditModePresetLayoutManager ~= nil and P().EditModeBar()
end

-- The layouts (the game's ones first, then the saved ones, as Edit Mode
-- keeps them) with the compact bar on or off in the one in use: { layouts,
-- activeLayout }, the index of that layout, whether it is new. nil and why
-- when it can't ("notGamepad": the layout in use isn't a gamepad one)
function G.CompactLayouts(on)
    local SYSTEM, COMPACT, GAMEPAD = compactIds()
    local PRESET = Enum.EditModeLayoutType.Preset
    local saved = C_EditMode.GetLayouts()
    local presets = EditModePresetLayoutManager:GetCopyOfPresetLayouts()
    local layouts = {}
    for _, l in ipairs(presets) do layouts[#layouts + 1] = l end
    for _, l in ipairs(saved.layouts or {}) do layouts[#layouts + 1] = l end
    local gamepadPreset
    for _, l in ipairs(presets) do
        if l.interfaceStyle == GAMEPAD then gamepadPreset = l end
    end
    local index, isNew = saved.activeLayout, false
    local target = layouts[index]
    if not (gamepadPreset and target and target.interfaceStyle == GAMEPAD) then return nil, "notGamepad" end
    if target.layoutType == PRESET then
        -- Ours from before, else a new copy of the Gamepad layout, put
        -- after the account's layouts (the character's if those are full)
        index = nil
        for i, l in ipairs(layouts) do
            if l.layoutType ~= PRESET and l.layoutName == COMPACT_LAYOUT and l.interfaceStyle == GAMEPAD then index = i end
        end
        if index then
            target = layouts[index]
        else
            local ACCOUNT, CHARACTER = Enum.EditModeLayoutType.Account, Enum.EditModeLayoutType.Character
            local max = Constants and Constants.EditModeConsts and Constants.EditModeConsts.EditModeMaxLayoutsPerType or 5
            local count, last = { [ACCOUNT] = 0, [CHARACTER] = 0 }, {}
            for i, l in ipairs(layouts) do
                if count[l.layoutType] then
                    count[l.layoutType] = count[l.layoutType] + 1
                    last[l.layoutType] = i
                end
            end
            local kind = count[ACCOUNT] < max and ACCOUNT or (count[CHARACTER] < max and CHARACTER) or nil
            if not kind then return nil, "full" end
            index = (last[kind] or (kind == CHARACTER and last[ACCOUNT]) or #presets) + 1
            target = deepCopy(gamepadPreset)
            target.layoutType, target.layoutName = kind, COMPACT_LAYOUT
            table.insert(layouts, index, target)
            isNew = true
        end
    end
    -- The bar in it (put back from the Gamepad layout if the game dropped it)
    local bar
    for _, sys in ipairs(target.systems) do
        if sys.system == SYSTEM then bar = sys end
    end
    if not bar then
        for _, sys in ipairs(gamepadPreset.systems) do
            if sys.system == SYSTEM then bar = deepCopy(sys) end
        end
        if not bar then return nil, "notGamepad" end
        target.systems[#target.systems + 1] = bar
    end
    local found
    for _, st in ipairs(bar.settings) do
        if st.setting == COMPACT then
            st.value = on and 1 or 0
            found = true
        end
    end
    if not found then bar.settings[#bar.settings + 1] = { setting = COMPACT, value = on and 1 or 0 } end
    return { layouts = layouts, activeLayout = saved.activeLayout }, index, isNew
end

-- Saved, the layout made the one in use, the interface reloaded; the guide
-- back at this step after it
function G:SetCompact(on)
    if CK:BlockedByCombat() then return end
    local info, index, isNew
    if self:CanSetCompact() then
        local ok, a, b, c = pcall(G.CompactLayouts, on)
        if ok then info, index, isNew = a, b, c end
    end
    if not info then
        return C():Toast(index == "notGamepad" and format(L.GUIDE_COMPACT_NOT_GAMEPAD, LAYOUT_STYLE_GAMEPAD or "Gamepad")
            or L.GUIDE_COMPACT_UNAVAILABLE, true)
    end
    C_EditMode.SaveLayouts(info)
    if isNew then
        C_EditMode.OnLayoutAdded(index, true, false)
    elseif index ~= info.activeLayout then
        C_EditMode.SetActiveLayout(index)
    end
    CK.db.onboarding = CK.db.onboarding or {}
    CK.db.onboarding.resume = self.sid
    CK.db.onboarding.quick = self.quick
    local reload = C_UI and C_UI.Reload or ReloadUI
    reload()
end

-- 3b: the window small, the bar's size changed live
function G:BuildPreview(o)
    local p = CK.NewFrame("Frame", nil, o)
    p:SetAllPoints(o)
    p:Hide()
    text(p, 18, KC.title, 24, 14):SetText(L.GUIDE_BAR_SIZE)
    p.count = help(p, 14, KC.help)
    p.count:SetPoint("TOPRIGHT", -24, -16)
    local s = { controls = {} }
    p.slider = slider(s, p, 24, 46, 772)
    self.previewScreen = s
    self.previewFrame = p
end

-- Is the game's gamepad bar in the top half of the screen?
local function barHigh()
    local bar = GamepadMainActionBarFrame
    if not (bar and bar.GetCenter) then return false end
    local _, y = bar:GetCenter()
    y = CK.Plain(y)
    local h = UIParent:GetHeight()
    if not (y and h and h > 0) then return false end
    y = y * (CK.Plain(bar:GetEffectiveScale()) or 1) / (UIParent:GetEffectiveScale() or 1)
    return y > h / 2
end

-- A size step (or A on the size): the window made small first, at the top
-- of the screen (at the bottom when the bar is up there)
function G:Preview(d)
    if self.mode ~= "preview" then
        if CK:BlockedByCombat() then return end
        self.mode = "preview"
        self.previewFrom = P():BarScale()
        local f = C().frame
        self.savedPoint = { f:GetPoint(1) }
        -- (the panel's own body and help bar stay out of the small window)
        f.body:Hide()
        f.bar:Hide()
        f:SetHeight(176)
        f:ClearAllPoints()
        if barHigh() then
            f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 24)
        else
            f:SetPoint("TOP", UIParent, "TOP", 0, -24)
        end
    end
    if d ~= 0 then P():ScaleBar(d) end
    self:Render()
end

-- A keeps the size, B puts back the one before; the window as it was
function G:EndPreview(keep)
    if self.mode ~= "preview" then return end
    if not keep and self.previewFrom then
        settings().barScale = self.previewFrom
        P():ApplyBarOffset()
    end
    self.mode, self.previewFrom = "normal", nil
    local f = C().frame
    f:SetHeight(H)
    f:ClearAllPoints()
    local p = self.savedPoint
    if p and p[1] then
        f:SetPoint(p[1], p[2] or UIParent, p[3] or p[1], p[4] or 0, p[5] or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    end
    f.body:Show()
    f.bar:Show()
    self:Render()
end

---------------------------------------------------------------------------
-- 4. The chat keyboard
---------------------------------------------------------------------------
local LAYOUTS = {
    { key = "azerty", name = "AZERTY" }, { key = "qwerty", name = "QWERTY" },
    { key = "qwertz", name = "QWERTZ" }, { key = "qwerty_es", name = "QWERTY (español)" },
    { key = "qwerty_it", name = "QWERTY (italiano)" },
    { key = "jcuken", name = "ЙЦУКЕН (русская)" },
}

local function keyboardOn() return settings().modules.keyboard and true or false end

local function stepLanguage(d)
    local key = CK:GetLanguage().key
    local index = 1
    for i, lang in ipairs(CK.LANGUAGES) do
        if lang.key == key then index = i end
    end
    CK:SetLanguage(CK.LANGUAGES[(index - 1 + d) % #CK.LANGUAGES + 1].key)
end

-- (2.0: the three ways side by side, the grid too)
local CW, CH = 252, 296

-- The grid's picture: its keys, one lit
local function gridArt(parent, x, y, w, h)
    local f = frameAt(parent, "Frame", x, y, w, h)
    local b = K.Box(f, 4, 1, "ARTWORK")
    b:SetPoints(f)
    b:SetColors({ 0.08, 0.067, 0.05 }, 1, KC.bronze, 1)
    local cols, rows = 10, 4
    local kw, kh = (w - 20) / cols, (h - 34) / rows
    for r = 0, rows - 1 do
        for c = 0, cols - 1 do
            local lit = r == 1 and c == 4
            local k = K.Solid(f, lit and KC.dimGold or KC.line3, 1, "OVERLAY")
            at(k, f, 10 + c * kw + 1, 10 + r * kh + 1, kw - 3, kh - 3)
        end
    end
    local space = K.Solid(f, KC.line3, 1, "OVERLAY")
    at(space, f, w / 2 - 50, h - 20, 100, 10)
    return f
end

G.BUILD.keyboard = function(_, s, f)
    s.module = switchLine(s, f, 24, 72, 772, 52, L.LBL_CHAT_KEYBOARD, L.GUIDE_KEYBOARD_HELP,
        keyboardOn,
        function(v)
            settings().modules.keyboard = v
            if not v then CK:Close("keyboard module off") end
        end)
    local function card(i, method, title, desc, art, isNew)
        local cf = frameAt(f, "Button", 24 + (i - 1) * (CW + 8), 132, CW, CH)
        cf.bg = K.Box(cf, 4, 2, "BACKGROUND")
        cf.bg:SetPoints(cf)
        if art then
            cf.art = image(cf, art, (CW - 96) / 2, 8, 96, 96)
        else
            cf.art = gridArt(cf, (CW - 150) / 2, 12, 150, 88)
        end
        if isNew then
            local anchor = cf:CreateTexture(nil, "ARTWORK")
            -- (under its text, over the options)
            at(anchor, cf, 6, CH - 100, 1, 1)
            newChip(cf, anchor)
        end
        cf.title = text(cf, 17, KC.title, 14, 110)
        cf.title:SetWidth(CW - 50)
        cf.title:SetWordWrap(false)
        cf.title:SetJustifyH("LEFT")
        cf.title:SetText(title)
        cf.ring = cf:CreateTexture(nil, "ARTWORK")
        cf.ring:SetTexture(TEX .. "ck_ring")
        cf.ring:SetSize(16, 16)
        cf.ring:SetPoint("TOPRIGHT", -14, -112)
        cf.dot = cf:CreateTexture(nil, "OVERLAY")
        cf.dot:SetTexture(TEX .. "ck_dot")
        cf.dot:SetSize(8, 8)
        cf.dot:SetPoint("CENTER", cf.ring, "CENTER")
        cf.dot:SetVertexColor(unpack(KC.focus))
        help(cf, 13, KC.cream2, 14, 136, CW - 28):SetText(desc)
        cf.note = help(cf, 12, KC.disabled, 14, CH - 40, CW - 28)
        cf.note:SetText(L.GUIDE_CARD_PICK)
        local c = add(s, { frame = cf, method = method, enabled = keyboardOn })
        function c.press(self)
            CK:SetInputMethod(self.method)
            return true
        end
        function c.verbA() return L.V_CHOOSE end
        function c.draw(self, focused)
            local chosen, live = settings().inputMethod == self.method, keyboardOn()
            if focused then
                cf.bg:SetColors({ 0.16, 0.13, 0.05 }, 1, KC.focus, 1)
            else
                cf.bg:SetColors(chosen and { 0.11, 0.08, 0.04 } or KC.controlBg, 1, chosen and KC.dimGold or KC.line1, 1)
            end
            cf.ring:SetVertexColor(unpack(chosen and KC.focus or KC.boxEdge))
            cf.dot:SetShown(chosen)
            cf.note:SetShown(not chosen)
            cf:SetAlpha(live and 1 or 0.35)
            cf.art:SetAlpha(chosen and 1 or 0.7)
        end
        return cf
    end
    local cards = {
        card(1, "wheel", L.METHOD_WHEEL, L.GUIDE_DAISY_TEXT, "ck_onb_daisywheel"),
        card(2, "stick", L.METHOD_STICK, L.GUIDE_SPLIT_TEXT, "ck_onb_splitkb"),
        card(3, "grid", L.METHOD_GRID, L.GUIDE_GRID_TEXT, nil, true),
    }
    -- The chosen card's options, at its bottom
    local function option(i, method, row, label, getText, step)
        local c = labeled(s, cards[i], 14, CH - 82 + row * 38, CW - 28, 70, label, getText, step)
        c.enabled = keyboardOn
        c.shown = function() return settings().inputMethod == method end
        return c
    end
    local function language() return CK:GetLanguage().name end
    local function layout() return (nameIn(LAYOUTS, settings().kbLayout):gsub(" %(.*%)$", "")) end
    local function stepLayout(d)
        settings().kbLayout = stepIn(LAYOUTS, settings().kbLayout, d).key
        CK:UpdateMethod()
    end
    s.options = {
        option(1, "wheel", 0, L.GUIDE_OPT_LOOK,
            function() return settings().petalRings and L.DW_LOOK_RINGS or L.DW_LOOK_PLAIN end,
            function()
                settings().petalRings = not settings().petalRings
                CK:UpdateMethod()
            end),
        option(1, "wheel", 1, L.GUIDE_OPT_HINTS, language, stepLanguage),
        option(2, "stick", 0, L.GUIDE_OPT_LAYOUT, layout, stepLayout),
        option(2, "stick", 1, L.GUIDE_OPT_HINTS, language, stepLanguage),
        option(3, "grid", 0, L.GUIDE_OPT_LAYOUT, layout, stepLayout),
        option(3, "grid", 1, L.GUIDE_OPT_HINTS, language, stepLanguage),
    }
    -- The quick phrases (asked: little used, their settings unclear): what
    -- they are, their key given here as a wheel's (they send without the
    -- keyboard too: never greyed with it)
    local qp = frameAt(f, "Frame", 24, 436, 772, 88)
    box(qp, KC.panel, 1, KC.line1, 1)
    local icon = qp:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(CK.Phrases and CK.Phrases.ICON or "Interface\\Icons\\UI_Chat")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    at(icon, qp, 16, 18, 48, 48)
    text(qp, 16, KC.title, 78, 10):SetText(L.PHRASES_NAME)
    help(qp, 13, KC.help, 78, 32, 456):SetText(L.GUIDE_PHRASES_TEXT)
    s.phrasesKey = button(s, qp, L.GUIDE_PICK_KEY, 552, 14, 204, 34, false, function() G:StartBind("wheel:phrases") end)
    s.phrasesLine = help(qp, 13, KC.help, 552, 54, 204)
    function s.first() return s.module end
    function s.render()
        local keys = G.KeysOf("wheel:phrases")
        if #keys > 0 then
            s.phrasesLine:SetText(format(L.GUIDE_KEY_IS, table.concat(keys, ", ", 1, math.min(2, #keys))))
            s.phrasesLine:SetTextColor(unpack(KC.cream2))
        else
            s.phrasesLine:SetText(L.GUIDE_NO_KEY)
            s.phrasesLine:SetTextColor(unpack(KC.disabled))
        end
    end
end


---------------------------------------------------------------------------
-- 5. The wheels, the healer's
---------------------------------------------------------------------------
-- The keys a wheel is on now ("UP", "LT + Y"...), as glyphs
local function keysOf(action)
    local found = {}
    for _, input in ipairs(M().INPUTS) do
        if M():InputEnabled(input) and not input.layer then
            for _, layer in ipairs(M().LAYERS) do
                if M():Get(input.id, layer) == action or M():GetReplaced(input.id, layer) == action then
                    found[#found + 1] = K.ComboMarkup(input.id, layer, 16)
                end
            end
        end
    end
    return found
end
G.KeysOf = keysOf

local function isHealer()
    local _, class = UnitClass("player")
    return HEALERS[class or ""] == true
end
-- (2.0: four wheels, the class's and the marks' too; any wheel can go on a
-- hold or a double press, said under them)
G.BUILD.wheels = function(_, s, f)
    s.cards = {}
    local function wheelCard(x, y, action, title, desc, art, icon, get, set, isNew)
        local cf = frameAt(f, "Frame", x, y, 378, 150)
        box(cf, KC.panel, 1, KC.line1, 1)
        if art then
            cf.art = image(cf, art, 12, 12, 68, 68)
        else
            local fr = frameAt(cf, "Frame", 16, 16, 60, 60)
            box(fr, KC.controlBg, 1, KC.line1, 1)
            cf.art = fr:CreateTexture(nil, "ARTWORK")
            cf.art:SetTexture(icon())
            cf.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            cf.art:SetSize(56, 56)
            cf.art:SetPoint("CENTER")
            cf.icon = icon
        end
        local t = text(cf, 16, KC.title, 92, 12)
        t:SetText(title)
        if isNew then newChip(cf, t) end
        help(cf, 13, KC.help, 92, 34, 272):SetText(desc)
        switchLine(s, cf, 84, 72, 286, 30, function(on) return on and L.GUIDE_WHEEL_ON or L.GUIDE_WHEEL_OFF end,
            nil, get, set)
        local key = button(s, cf, L.GUIDE_PICK_KEY, 92, 110, 150, 30, false, function() G:StartBind(action) end)
        key.enabled = get
        cf.keyLine = help(cf, 13, KC.help, 252, 116, 120)
        cf.keyLine:SetWordWrap(false)
        cf.action, cf.get = action, get
        s.cards[#s.cards + 1] = cf
    end
    local function wheelSet(key)
        return function(v)
            settings().wheel[key] = v
            Wheel():Fill()
        end
    end
    wheelCard(24, 72, "wheel:consumables", L.WHEEL_NAME, L.GUIDE_WHEEL_C_TEXT, "ck_onb_wheel_consumables", nil,
        function() return settings().wheel.enabled and true or false end, wheelSet("enabled"))
    wheelCard(418, 72, "wheel:usable", L.USABLE_WHEEL_NAME, L.GUIDE_WHEEL_U_TEXT, "ck_onb_wheel_usable", nil,
        function() return settings().wheel.usableEnabled ~= false end, wheelSet("usableEnabled"))
    wheelCard(24, 230, "wheel:class", L.CLASS_WHEEL_NAME, L.GUIDE_WHEEL_CL_TEXT, nil,
        function() return CK.ClassWheels:ClassIcon() end,
        function() return settings().wheel.classEnabled ~= false end, wheelSet("classEnabled"), true)
    wheelCard(418, 230, "wheel:marks", L.MARK_WHEEL_NAME, L.GUIDE_WHEEL_MK_TEXT, nil,
        function() return CK.ClassWheels.MARK_ICON end,
        function() return settings().wheel.markEnabled ~= false end, wheelSet("markEnabled"), true)
    -- How every wheel opens, said in full (asked: "Hold to show" wasn't
    -- clear); the stick that aims: Wheels > Opening
    check(s, f, 24, 388, 772, L.GUIDE_HOLD, L.GUIDE_HOLD_HELP,
        function() return settings().wheel.hold and true or false end,
        function(v)
            settings().wheel.hold = v
            Wheel():Fill()
        end)
    local more = infoBox(f, 24, 466, 772, 54)
    local t = text(more, 14, KC.info, 16, 8)
    t:SetText(L.GUIDE_MORE_TITLE)
    newChip(more, t)
    help(more, 13, KC.cream2, 16, 28, 740):SetText(isHealer() and L.GUIDE_MORE_HEALER or L.GUIDE_MORE_TEXT)
    function s.first() return s.controls[1] end
    function s.render()
        for _, card in ipairs(s.cards) do
            local keys = keysOf(card.action)
            if #keys > 0 then
                card.keyLine:SetText(format(L.GUIDE_KEY_IS, table.concat(keys, ", ", 1, math.min(2, #keys))))
                card.keyLine:SetTextColor(unpack(KC.cream2))
            else
                card.keyLine:SetText(L.GUIDE_NO_KEY)
                card.keyLine:SetTextColor(unpack(KC.disabled))
            end
            if card.icon then card.art:SetTexture(card.icon()) end
            card.art:SetAlpha(card.get() and 1 or 0.6)
        end
    end
end


---------------------------------------------------------------------------
-- 5b. A wheel's key: the button pressed next (LT / RT held for their
-- layers) or a paddle; B cancels. Put like the Gamepad tab puts a wheel.
---------------------------------------------------------------------------
-- Never a wheel's key: the triggers, Start, Select, the system button
local NOT_A_KEY = { PADLTRIGGER = true, PADRTRIGGER = true, PADFORWARD = true, PADBACK = true, PADSYSTEM = true,
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true, RMETA = true,
    UNKNOWN = true }

-- The input a key is: a gamepad button by its own key, a paddle or a
-- touchpad button turned on by the key it learned
local function inputOf(key)
    for _, input in ipairs(M().INPUTS) do
        if M():InputEnabled(input) and not input.layer and M():InputKey(input) == key then return input end
    end
end
G.InputOf = inputOf

-- The triggers, as the layer's letters
local TRIGGER_OF = { PADLTRIGGER = "LT", PADRTRIGGER = "RT" }
-- Alone, the game's own (jump, interact, inspect): never taken here, a
-- wrong layer read would replace them (B alone cancels)
local GAME_ALONE = { PAD1 = true, PAD3 = true, PAD4 = true }
-- LB and RB alone: the game's targeting, friendly and hostile (reported: LB
-- pressed first for "LB + A" took LB alone, the friendly targeting lost)
local SHOULDER = { PADLSHOULDER = true, PADRSHOULDER = true }

-- A trigger down on the controller itself (its buttons as the game maps them)
local function padHeld(button)
    local G2 = C_GamePad
    local id = G2 and G2.GetActiveDeviceID and G2.GetActiveDeviceID()
    local state = id and G2.GetDeviceMappedState and G2.GetDeviceMappedState(id)
    local index = state and state.buttons and G2.ButtonBindingToIndex and G2.ButtonBindingToIndex(button)
    return index ~= nil and state.buttons[index + 1] and true or false
end

-- The layer of the press: the triggers this wait saw go down (it keeps
-- them from the game, and from the trigger toggle), or held on the pad
function G:BindLayer()
    local held = self.bindHeld or {}
    local lt = held.LT or padHeld("PADLTRIGGER")
    local rt = held.RT or padHeld("PADRTRIGGER")
    return (lt and "LT" or "") .. (rt and "RT" or "")
end

-- The wait shown: by the guide, or by the panel's row that asked (`host`:
-- { render = fn, refused = fn(why) }; the minimap labels' button)
function G:BindRender()
    local host = self.bindHost
    if host then return host.render() end
    self:Render()
end

function G:StartBind(action, host)
    if CK:BlockedByCombat() then return end
    self.bindHost = host
    self.mode = "bind"
    self.binding = action
    self.bindAt = GetTime()
    self.bindHeld, self.bindWhy = {}, nil
    local f = self.capture
    if not f then
        f = CK.NewFrame("Frame", nil, UIParent)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetSize(1, 1)
        f:SetPoint("CENTER")
        if f.EnableGamePadButton then
            -- (false: the button stops here, not passed on to the game)
            f:SetScript("OnGamePadButtonDown", function(_, button)
                G:BindPressed(button)
                return false
            end)
            -- A trigger let go: its layer no more (its release ours too)
            f:SetScript("OnGamePadButtonUp", function(_, button)
                local t = TRIGGER_OF[button]
                if not t then return true end
                if G.bindHeld then G.bindHeld[t] = nil end
                return false
            end)
        end
        f:SetScript("OnKeyDown", function(_, key) G:BindPressed(key) end)
        f:Hide()
        self.capture = f
    end
    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(false)
    if f.EnableGamePadButton then f:EnableGamePadButton(true) end
    f:Show()
    self:BindRender()
end

function G:EndBind()
    local f = self.capture
    if f and f:IsShown() then
        f:Hide()
        if not InCombatLockdown() then
            f:EnableKeyboard(false)
            if f.EnableGamePadButton then f:EnableGamePadButton(false) end
        end
    end
    self.mode, self.binding, self.bindHeld, self.bindWhy = "normal", nil, nil, nil
    self:BindRender()
    self.bindHost = nil
end

-- Refused: why, kept in the help bar while it still waits (more time given)
function G:BindRefused(why)
    self.bindWhy = why
    self.bindAt = GetTime()
    if self.bindHost and self.bindHost.refused then self.bindHost.refused(why) end
    self:BindRender()
end

function G:BindPressed(key)
    if self.mode ~= "bind" then return end
    local trigger = TRIGGER_OF[key]
    if trigger then
        self.bindHeld[trigger] = true
        return
    end
    if NOT_A_KEY[key] then return end
    -- (its release, should it reach the panel's keys, is no press: B goes back)
    C():Swallow({ [key] = true })
    local layer = self:BindLayer()
    -- B alone cancels (reported: LT + RT + B cancelled); with a trigger, a key
    if key == "ESCAPE" or (key == "PAD2" and layer == "") then return self:EndBind() end
    local input = inputOf(key)
    if not input then return self:BindRefused(L.GUIDE_KEY_UNKNOWN) end
    local combo = K.ComboMarkup(input.id, layer, 14)
    if layer == "" and GAME_ALONE[key] then return self:BindRefused(format(L.GUIDE_KEY_ALONE, combo)) end
    if layer == "" and SHOULDER[key] then return self:BindRefused(format(L.GUIDE_KEY_SHOULDER, combo)) end
    local page = CK.MapPage
    local cell = page:Cell(input, layer)
    if cell.lockedAlone or (cell.state == "off" and not cell.pick) then
        return self:BindRefused(cell.why or format(L.GUIDE_KEY_REFUSED, combo))
    end
    if page:Put(input, layer, self.binding) then
        C():Toast(format(L.TOAST_ON, M():ActionName(self.binding) or "", combo))
        self:EndBind()
    else
        self:BindRefused(not M():Enabled() and L.MAP_MODULE_OFF
            or (not M():CanOwnKeys() and L.MAP_REPLACE_NO_MOD) or format(L.GUIDE_KEY_REFUSED, combo))
    end
end

---------------------------------------------------------------------------
-- 6. Comfort, and off you go
---------------------------------------------------------------------------
local COMFORT = {
    { label = "LBL_RANGE_TINT", help = "GUIDE_C_RANGE", icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
        get = function() return settings().features.rangeTint == true end,
        set = function(v)
            settings().features.rangeTint = v
            CK.Range:Apply()
        end },
    { label = "SEC_QUESTITEMS", help = "GUIDE_C_QUEST", icon = "Interface\\Icons\\INV_Misc_Note_01",
        get = function() return settings().modules.questItems and true or false end,
        set = function(v)
            settings().modules.questItems = v
            if v then
                CK.QuestItems:ScanBags()
                CK.QuestItems:ScanQuests()
            end
            CK.QuestItems:RefreshBorders()
        end },
    { label = "LBL_UPGRADES", help = "GUIDE_C_UPGRADES", icon = "Interface\\Icons\\INV_Chest_Chain_05",
        get = function() return settings().modules.upgrades and true or false end,
        set = function(v)
            settings().modules.upgrades = v
            CK.Upgrades:Refresh()
        end },
    { label = "LBL_SUPPLY_BUTTONS", help = "GUIDE_C_SUPPLIES", icon = "Interface\\Icons\\INV_Misc_Bag_08",
        get = function() return settings().supplies.enabled and true or false end,
        set = function(v)
            settings().supplies.enabled = v
            CK.Supplies:Refresh()
        end },
    { label = "GUIDE_C_JUNK_LABEL", help = "GUIDE_C_JUNK", icon = "Interface\\Icons\\INV_Misc_Coin_02",
        get = function() return settings().modules.sellJunk and settings().modules.autoRepair and true or false end,
        set = function(v)
            settings().modules.sellJunk = v
            settings().modules.autoRepair = v
        end },
    { label = "SEC_VIBRATIONS", help = "GUIDE_C_VIBRATIONS", icon = "Interface\\Icons\\Spell_Nature_Earthquake",
        get = function() return settings().vibration.enabled and true or false end,
        set = function(v)
            local V = CK.Vibration
            V:Settings().enabled = v
            if v then V:Play("pulse") else V:Stop() end
        end },
    { label = "LBL_STAY_SEATED", help = "GUIDE_C_SEATED", icon = "Interface\\Icons\\INV_Misc_Food_15",
        get = function() return settings().wheel.staySeated and true or false end,
        set = function(v)
            settings().wheel.staySeated = v
            if not v and Wheel().seated then Wheel().seated:Hide() end
        end },
}

-- A comfort line: its game icon, label and help, its box at the right
local function comfortRow(screen, parent, e)
    local f = frameAt(parent, "Button", 24, 100, 452, 54)
    f.bg = box(f, KC.nowBg, 0, KC.focus, 0)
    local frame = frameAt(f, "Frame", 14, 11, 32, 32)
    box(frame, KC.controlBg, 1, KC.line1, 1)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(e.icon)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetSize(28, 28)
    icon:SetPoint("CENTER")
    f.label = text(f, 15, KC.cream, 58, 8)
    f.label:SetText(L[e.label])
    f.help = help(f, 13, KC.help, 58, 27, 452 - 58 - 46)
    f.help:SetText(L[e.help])
    f.boxFrame = frameAt(f, "Frame", 452 - 14 - 20, 17, 20, 20)
    f.box = K.Box(f.boxFrame, 3, 2, "ARTWORK")
    f.box:SetPoints(f.boxFrame)
    -- (on the box's own frame, over its fill, as the panel's)
    f.tick = f.boxFrame:CreateTexture(nil, "OVERLAY")
    f.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    f.tick:SetSize(26, 26)
    f.tick:SetPoint("CENTER", f.boxFrame, "CENTER", 0, 0)
    f.tick:SetVertexColor(unpack(KC.focus))
    f.rule = K.Solid(f, KC.line3, 1, "ARTWORK")
    f.rule:SetPoint("BOTTOMLEFT", 0, 0)
    f.rule:SetPoint("BOTTOMRIGHT", 0, 0)
    f.rule:SetHeight(1)
    local c = add(screen, { frame = f, get = e.get, set = e.set })
    function c.press(self)
        self.set(not self.get())
        return true
    end
    function c.verbA(self) return self.get() and L.GUIDE_UNTICK or L.GUIDE_TICK end
    function c.draw(self, focused)
        local on = self.get() and true or false
        f.bg:SetColors(KC.nowBg, focused and 1 or 0, KC.focus, focused and 1 or 0)
        f.box:SetColors(KC.controlBg, 1, focused and KC.focus or KC.boxEdge, 1)
        f.tick:SetShown(on)
        f.label:SetTextColor(unpack(focused and KC.focusText or KC.cream))
        f:SetHeight(math.max(54, 27 + (f.help:GetStringHeight() or 0) + 10))
    end
    return c
end

-- The quick way: these two only
local QUICK_COMFORT = { GUIDE_C_JUNK_LABEL = true, SEC_VIBRATIONS = true }

-- The bags' view: one of ours, or the game's own
local BAG_VIEWS = { "blizzard", "compact", "full", "game" }

local function bagView()
    if settings().ownBags ~= true then return "game" end
    return CK.Bags.Look().layout
end

local function bagViewName(key)
    if key == "game" then return L.GUIDE_BAGS_GAME end
    return L["BAGS_LAYOUT_" .. key:upper()]
end

local function setBagView(key)
    local B = CK.Bags
    if key == "game" then
        settings().ownBags = false
        if B.open then B:Close("off") end
        return
    end
    settings().ownBags = true
    B.Look().layout = key
    if B.open then B:Refresh() end
end

-- FPS and ping: shown together or one of them
local PERF_PLACES = { "TOPLEFT", "TOP", "TOPRIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

local function perf()
    local s = settings()
    if type(s.perf) ~= "table" then s.perf = {} end
    return s.perf
end

local function perfShows(key)
    local t = perf()
    return t.enabled == true and t[key] ~= false
end

local function setPerf(key, v)
    local t = perf()
    if v and t.enabled ~= true then
        -- Turned on with this one alone
        t.enabled, t.fps, t.ping = true, false, false
    end
    t[key] = v and true or false
    if not t.fps and not t.ping then t.enabled = false end
    CK.Perf:Apply()
end

G.BUILD.comfort = function(_, s, f)
    text(f, 16, KC.title, 24, 72):SetText(L.GUIDE_COMFORT)
    s.rows = {}
    for i, e in ipairs(COMFORT) do
        local c = comfortRow(s, f, e)
        if not QUICK_COMFORT[e.label] then c.shown = function() return not G.quick end end
        s.rows[i] = c
    end
    s.more = help(f, 13, KC.grey, 24, 100, 452)
    s.more:SetText(L.GUIDE_COMFORT_MORE)
    rule(f, 492, 72, 1, 444)
    -- The bags
    newTitle(f, 16, 508, 72, L.GUIDE_BAGS)
    labeled(s, f, 508, 98, 288, 70, L.GUIDE_BAGS_VIEW,
        function() return bagViewName(bagView()) end,
        function(d)
            local i = indexOf(BAG_VIEWS, bagView()) or 1
            setBagView(BAG_VIEWS[(i - 1 + d) % #BAG_VIEWS + 1])
        end)
    local empty = check(s, f, 508, 138, 288, L.GUIDE_BAGS_EMPTY, L.GUIDE_BAGS_EMPTY_HELP,
        function()
            local lk = CK.Bags.Look()
            return lk.emptySlots and lk.order == "one" or false
        end,
        function(v)
            local lk = CK.Bags.Look()
            lk.emptySlots = v and true or false
            if v then lk.order = "one" end
            if CK.Bags.open then CK.Bags:Refresh() end
        end)
    empty.enabled = function() return settings().ownBags == true end
    -- FPS and ping
    newTitle(f, 16, 508, 236, L.GUIDE_PERF)
    check(s, f, 508, 262, 140, L.GUIDE_FPS, nil, function() return perfShows("fps") end,
        function(v) setPerf("fps", v) end)
    check(s, f, 656, 262, 140, L.GUIDE_PING, nil, function() return perfShows("ping") end,
        function(v) setPerf("ping", v) end)
    local place = labeled(s, f, 508, 306, 288, 70, L.GUIDE_PERF_WHERE,
        function() return L["PERF_PLACE_" .. (perf().place or "TOPRIGHT")] end,
        function(d)
            local t = perf()
            local i = indexOf(PERF_PLACES, t.place) or 0
            t.place = PERF_PLACES[(i - 1 + d) % #PERF_PLACES + 1]
            CK.Perf:Apply()
        end)
    place.enabled = function() return perfShows("fps") or perfShows("ping") end
    help(f, 13, KC.grey, 508, 346, 288):SetText(L.GUIDE_PERF_MORE)
    function s.first() return s.rows[5] end
    -- The rows one under the other, each as tall as its help
    function s.layout()
        local y = 100
        for _, c in ipairs(s.rows) do
            if shown(c) then
                at(c.frame, f, 24, y)
                y = y + c.frame:GetHeight()
            end
        end
        at(s.more, f, 24, y + 10)
        s.more:SetShown(G.quick)
    end
end

---------------------------------------------------------------------------
-- Done: what was set, off you go (a reload when the window's look changed)
---------------------------------------------------------------------------
local function lookChanged()
    return K.LookOf(settings().configLook) ~= K.Look()
end

local SUMMARY = 10

G.BUILD.done = function(_, s, f)
    text(f, 16, KC.title, 24, 72):SetText(L.GUIDE_SUMMARY)
    s.summary = {}
    for i = 1, SUMMARY do
        local y = 100 + (i - 1) * 28
        local key = help(f, 14, KC.grey, 24, y, 150)
        local value = help(f, 14, KC.cream2, 180, y)
        value:SetWidth(296)
        value:SetWordWrap(false)
        s.summary[i] = { key, value }
    end
    rule(f, 492, 72, 1, 444)
    image(f, "ck_onb_done", 584, 72, 128, 128)
    s.reload = infoBox(f, 508, 214, 288, 62)
    help(s.reload, 13, KC.cream2, 12, 8, 264):SetText(L.GUIDE_RELOAD_NOTE)
    button(s, f, L.GUIDE_PLACE_SPELLS, 508, 338, 288, 40, false, function() G:Finish("gamepad") end)
    s.finish = button(s, f, L.GUIDE_FINISH, 508, 388, 288, 40, true, function()
        local reload = lookChanged()
        G:Finish()
        if reload then
            local r = C_UI and C_UI.Reload or ReloadUI
            r()
        end
    end)
    help(f, 13, KC.grey, 508, 442, 288):SetText(L.GUIDE_AGAIN)
    function s.first() return s.finish end
    function s.render()
        local st = settings()
        local reload = lookChanged()
        s.reload:SetShown(reload)
        s.finish.frame.label:SetText(reload and L.GUIDE_FINISH_RELOAD or L.GUIDE_FINISH)
        local kind = G:PadKind()
        local ds = kind == "dualsense"
        local wheels = {}
        if st.wheel.enabled then wheels[#wheels + 1] = L.GUIDE_SUM_CONSUMABLES end
        if st.wheel.usableEnabled ~= false then wheels[#wheels + 1] = L.GUIDE_SUM_USABLE end
        if st.wheel.classEnabled ~= false then wheels[#wheels + 1] = L.GUIDE_SUM_CLASS end
        if st.wheel.markEnabled ~= false then wheels[#wheels + 1] = L.GUIDE_SUM_MARKS end
        local glyphs = nameIn(GLYPH_STYLES, st.glyphStyle) .. (st.nativeGlyphs and st.gameGlyphs and L.GUIDE_SUM_NATIVE or "")
        local look = L["CFG_LOOK_" .. K.LookOf(st.configLook):upper()] .. ", " .. format("%d %%", C().Scale() * 100 + 0.5)
        local lines = {
            { L.GUIDE_SUM_PAD, L["GUIDE_PAD_" .. kind:upper()] .. (G:Edge() and " Edge" or "") },
            { L.GUIDE_SUM_ICONS, glyphs },
            { L.GUIDE_SUM_WINDOW, look },
        }
        if ds then
            local pick = G:CornerPick()
            lines[#lines + 1] = { L.GUIDE_SUM_CORNERS, L["GUIDE_CORNERS_" .. pick:upper()]
                .. (pick ~= "none" and touchSettings().overlay and L.GUIDE_SUM_ON_SCREEN or "") }
            lines[#lines + 1] = { L.GUIDE_SUM_PS, psName("CREATE") .. " / " .. psName("MIC") }
        else
            local paddles, pads = 0, {}
            for _, id in ipairs(P().ORDER) do
                if P():Identified(id) then paddles = paddles + 1 end
            end
            for _, side in ipairs({ "L", "R" }) do
                if touchSide(side) then pads[#pads + 1] = L["GUIDE_TOUCH_" .. side] end
            end
            lines[#lines + 1] = { L.GUIDE_SUM_PADDLES, paddles > 0 and format(L.GUIDE_SUM_IDENTIFIED, paddles) or L.GUIDE_SUM_NONE }
            lines[#lines + 1] = { L.GUIDE_SUM_PADS, #pads > 0 and table.concat(pads, ", ") or L.GUIDE_SUM_NONE }
        end
        lines[#lines + 1] = { L.GUIDE_SUM_BAR, format("%d %%", P():BarScale() * 100 + 0.5) }
        lines[#lines + 1] = { L.GUIDE_SUM_KEYBOARD, not st.modules.keyboard and L.GUIDE_SUM_OFF
            or (st.inputMethod == "stick" and L.METHOD_STICK or st.inputMethod == "grid" and L.METHOD_GRID or L.METHOD_WHEEL) }
        lines[#lines + 1] = { L.GUIDE_SUM_WHEELS, #wheels > 0 and table.concat(wheels, ", ") or L.GUIDE_SUM_NONE }
        lines[#lines + 1] = { L.GUIDE_SUM_BAGS, bagViewName(bagView()) }
        local shows = {}
        if perfShows("fps") then shows[#shows + 1] = L.GUIDE_FPS end
        if perfShows("ping") then shows[#shows + 1] = L.GUIDE_SUM_PING end
        lines[#lines + 1] = { L.GUIDE_PERF, #shows > 0 and (table.concat(shows, L.GUIDE_SUM_AND) .. ", "
            .. L["PERF_PLACE_" .. (perf().place or "TOPRIGHT")]) or L.GUIDE_SUM_OFF }
        for i = 1, SUMMARY do
            local l = lines[i]
            s.summary[i][1]:SetText(l and l[1] or "")
            s.summary[i][2]:SetText(l and l[2] or "")
        end
    end
end

---------------------------------------------------------------------------
-- Start from scratch (a rerun, behind a confirm): the settings back to the
-- defaults, but the profiles, the keyboard's words, the quick phrases, the
-- places learned (paddles, touchpad buttons) and the controller's pick;
-- the interface reloaded, the guide back at the controller's step
---------------------------------------------------------------------------
local KEEP = { lang = true, kbLayout = true, inputMethod = true, petalRings = true, shortcut = true,
    configPos = true, configTab = true, configSection = true, paddles = true, touchButtons = true,
    extraPos = true, myWheels = true, padKind = true, dualsenseEdge = true, forkDualSense = true }

function G:BuildConfirm(o)
    local m = CK.NewFrame("Frame", nil, o)
    m:SetAllPoints(o)
    m:SetFrameLevel(o:GetFrameLevel() + 30)
    m:EnableMouse(true)
    local dim = K.Solid(m, { 0, 0, 0 }, 0.6, "BACKGROUND")
    dim:SetAllPoints()
    local b = frameAt(m, "Frame", 150, 150, 520, 250)
    box(b, KC.panel, 1, KC.danger, 1)
    text(b, 18, KC.title, 24, 18):SetText(L.GUIDE_SCRATCH_TITLE)
    help(b, 14, KC.cream2, 24, 50, 472):SetText(L.GUIDE_SCRATCH_TEXT)
    m.cancel = K.Button(b, 16)
    at(m.cancel, b, 24, 180, 200, 40)
    m.cancel.label:SetText(L.V_CANCEL)
    m.cancel:SetScript("OnClick", function() G:EndConfirm(false) end)
    m.ok = K.Button(b, 16)
    at(m.ok, b, 240, 180, 256, 40)
    m.ok.label:SetText(L.GUIDE_SCRATCH_OK)
    m.ok:SetScript("OnClick", function() G:EndConfirm(true) end)
    m:Hide()
    self.confirmFrame = m
end

function G:AskScratch()
    self.mode, self.confirmSel = "confirm", 0
    self:Render()
end

function G:EndConfirm(ok)
    if self.mode ~= "confirm" then return end
    self.mode = "normal"
    if ok then return self:StartFromScratch() end
    self:Render()
end

function G:StartFromScratch()
    if CK:BlockedByCombat() then return self:Render() end
    local s = settings()
    for k in pairs(CK.DEFAULTS) do
        if not KEEP[k] then s[k] = nil end
    end
    -- (theirs, not in the defaults: filled again as they load)
    s.bagsLook, s.perf, s.ownBags = nil, nil, nil
    CK.db.onboarding = CK.db.onboarding or {}
    CK.db.onboarding.resume = "controller"
    CK.db.onboarding.quick = self.quick
    local reload = C_UI and C_UI.Reload or ReloadUI
    reload()
end

---------------------------------------------------------------------------
-- Moving through it
---------------------------------------------------------------------------
local function focusables(s)
    local list = {}
    for _, c in ipairs(s.controls) do
        if c.frame and shown(c) and enabled(c) then list[#list + 1] = c end
    end
    return list
end

function G:Current() return self.screens and self.screens[self.sid] end

-- The control with the focus (the first one that can, if it can't)
function G:Focused()
    local s = self:Current()
    if not s then return nil end
    local list = focusables(s)
    for _, c in ipairs(list) do
        if c == s.focus then return c end
    end
    s.focus = list[1]
    return s.focus
end

function G:Move(d)
    local s = self:Current()
    local list = focusables(s)
    if #list == 0 then return end
    local current, index = self:Focused(), 1
    for i, c in ipairs(list) do
        if c == current then index = i end
    end
    s.focus = list[math.max(1, math.min(#list, index + d))]
    self:Render()
end

-- To a screen, its first control focused
function G:Go(sid)
    if not (self.screens and self.screens[sid]) then sid = "welcome" end
    self.sid = sid
    local s = self:Current()
    if s.enter then s.enter() end
    s.focus = s.first and s.first() or s.controls[1]
    self:Render()
end

-- Along the path: d = 1 the next screen, -1 the one before
function G:Step(d)
    local p = self:Path()
    local i = indexOf(p, self.sid)
    local to = i and p[i + d]
    if to then self:Go(to) end
end

function G:Next()
    if self.sid == "whatsnew" then return self:Go("welcome") end
    self:Step(1)
end

-- The first screen of the run (B there: later)
function G:AtStart()
    return self.sid == "whatsnew" or indexOf(self:Path(), self.sid) == 1
end

-- A control clicked with the mouse: focused, then as A
function G:Click(c)
    if self.mode ~= "normal" or c.screen ~= self:Current() or not (shown(c) and enabled(c)) then return end
    c.screen.focus = c
    if c.press then c:press() end
    self:Render()
end

function G:Press(name)
    if not self.active then return end
    if self.mode == "confirm" then
        if name == "LEFT" or name == "RIGHT" or name == "UP" or name == "DOWN" then
            self.confirmSel = self.confirmSel == 1 and 0 or 1
            self:Render()
        elseif name == "A" then
            self:EndConfirm(self.confirmSel == 1)
        elseif name == "B" then
            self:EndConfirm(false)
        end
        return
    end
    if self.mode == "identify" then
        if name == "B" then return self:EndIdentify(false) end
        if name == "X" then P():StopCapture(nil) end
        return
    end
    if self.mode == "bind" then
        if name == "B" then self:EndBind() end
        return
    end
    if self.mode == "preview" then
        if name == "LEFT" or name == "RIGHT" then
            self:Preview(name == "LEFT" and -1 or 1)
        elseif name == "A" then
            self:EndPreview(true)
        elseif name == "B" then
            self:EndPreview(false)
        end
        return
    end
    local c = self:Focused()
    if name == "UP" or name == "DOWN" then return self:Move(name == "UP" and -1 or 1) end
    if name == "LEFT" or name == "RIGHT" then
        local d = name == "LEFT" and -1 or 1
        if c and c.lr then
            c:adjust(d)
            return self:Render()
        end
        return self:Move(d)
    end
    if name == "A" then
        if c and c.press then
            c:press()
            self:Render()
        end
    elseif name == "LB" then
        if self.sid ~= "whatsnew" then self:Step(-1) end
    elseif name == "RB" then
        self:Next()
    elseif name == "B" then
        if self:AtStart() then return self:Later() end
        self:Step(-1)
    end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local TITLES = { whatsnew = "GUIDE_T_WHATSNEW", welcome = "GUIDE_T1", controller = "GUIDE_T_CONTROLLER",
    dualsense = "GUIDE_T_DUALSENSE", paddles = "GUIDE_T2", bar = "GUIDE_T3", keyboard = "GUIDE_T4",
    wheels = "GUIDE_T_WHEELS", comfort = "GUIDE_T_COMFORT", look = "GUIDE_T_LOOK", done = "GUIDE_T_DONE" }
local CRUMBS = { whatsnew = "GUIDE_C_WHATSNEW", welcome = "GUIDE_C1", controller = "GUIDE_C_CONTROLLER",
    dualsense = "GUIDE_C_DUALSENSE", paddles = "GUIDE_C2", bar = "GUIDE_C3", keyboard = "GUIDE_C4",
    wheels = "GUIDE_C5", comfort = "GUIDE_C6", look = "GUIDE_C_LOOK", done = "GUIDE_C_DONE" }

function G:Hints()
    local Hn = K.H
    if self.mode == "confirm" then
        return { Hn({ "DPAD_LR" }, L.V_CHOOSE, "RIGHT"), Hn({ "A" }, L.V_CONFIRM, "A"), Hn({ "B" }, L.V_CANCEL, "B") }
    end
    if self.mode == "identify" then return { Hn({ "X" }, L.V_SKIP, "X"), Hn({ "B" }, L.V_CANCEL, "B") } end
    if self.mode == "bind" then return { Hn({ "B" }, L.V_CANCEL, "B") } end
    if self.mode == "preview" then
        return { Hn({ "DPAD_LR" }, L.GUIDE_ADJUST, "RIGHT"), Hn({ "A" }, L.GUIDE_KEEP, "A"), Hn({ "B" }, L.V_CANCEL, "B") }
    end
    local list = {}
    local c = self:Focused()
    if c and c.lr then
        list[#list + 1] = Hn({ "DPAD_LR" }, L.GUIDE_ADJUST, "RIGHT")
    else
        list[#list + 1] = Hn({ "DPAD" }, L.V_CHOOSE, "DOWN")
    end
    if c and c.press then list[#list + 1] = Hn({ "A" }, c.verbA and c:verbA() or L.V_CONFIRM, "A") end
    if self.sid == "whatsnew" then
        list[#list + 1] = Hn({ "RB" }, L.GUIDE_TAKE, "RB")
        list[#list + 1] = Hn({ "B" }, L.GUIDE_LATER, "B")
        return list
    end
    local p = self:Path()
    local i = indexOf(p, self.sid) or 1
    if i == 1 then
        list[#list + 1] = Hn({ "RB" }, L.GUIDE_NEXT, "RB")
        list[#list + 1] = Hn({ "B" }, L.GUIDE_LATER, "B")
    else
        list[#list + 1] = Hn(i < #p and { "LB", "RB" } or { "LB" }, L.GUIDE_STEP, "LB")
        list[#list + 1] = Hn({ "B" }, L.V_BACK, "B")
    end
    return list
end

function G:Crumb()
    local here = L[CRUMBS[self.sid] or "GUIDE_C1"]
    if self.mode == "identify" then return L.GUIDE_CRUMB .. " › " .. here .. " › " .. L.GUIDE_IDENTIFYING end
    if self.mode == "bind" then return L.GUIDE_BIND_NOW end
    if self.mode == "preview" then return L.GUIDE_PREVIEW_LIVE end
    if self.mode == "confirm" then return L.GUIDE_SCRATCH_TITLE end
    if self.sid == "whatsnew" then return here end
    return L.GUIDE_CRUMB .. " › " .. here .. (self.quick and L.GUIDE_QUICK_MARK or "")
end

function G:RenderHelp()
    local o = self.frame
    local hints = self:Hints()
    local crumb, color = self:Crumb(), KC.grey
    if self.mode == "bind" and self.bindWhy then crumb, color = self.bindWhy, KC.warn end
    local toast = C().toast
    if toast then crumb, color = toast.text, toast.color end
    o.crumb:SetText(crumb)
    o.crumb:SetTextColor(unpack(color))
    local x = W - 4 - 20
    for i = #hints, 1, -1 do
        local h = o.hints[i]
        if not h then
            h = K.Hint(o.bar)
            o.hints[i] = h
        end
        h:Set(hints[i])
        h:ClearAllPoints()
        h:SetPoint("RIGHT", o.bar, "LEFT", x, 0)
        x = x - h:GetWidth() - 18
    end
    for i = #hints + 1, #o.hints do o.hints[i]:Hide() end
    o.crumb:SetWidth(math.max(10, x - 22))
end

-- The run's dots: done (gold), now (bright, bigger), to come (rings)
function G:RenderHeader()
    local o = self.frame
    local whatsnew = self.sid == "whatsnew"
    o.kicker:SetText(K.Upper(whatsnew and L.GUIDE_KICKER_NEW or L.GUIDE_KICKER))
    o.title:SetText(L[TITLES[self.sid] or "GUIDE_T1"])
    local p = self:Path()
    local pos = whatsnew and 0 or (indexOf(p, self.sid) or 1)
    local n = whatsnew and 0 or math.min(#p, MAX_DOTS)
    o.count:SetText(whatsnew and "" or format("%d / %d", pos, #p))
    local x = 0
    for i = MAX_DOTS, 1, -1 do
        local d = o.dots[i]
        if i > n then
            d:Hide()
        else
            local now, done = i == pos, i < pos
            local size = now and 10 or 8
            d:Show()
            d:SetTexture(TEX .. ((now or done) and "ck_dot" or "ck_ring"))
            d:SetVertexColor(unpack(now and KC.focus or (done and KC.dimGold or KC.line1)))
            d:SetSize(size, size)
            d:ClearAllPoints()
            d:SetPoint("RIGHT", o.count, "LEFT", -10 - x, 0)
            x = x + size + 7
        end
    end
end

function G:RenderConfirm()
    local m = self.confirmFrame
    local on = self.mode == "confirm"
    m:SetShown(on)
    if not on then return end
    m.cancel:SetState({ focus = self.confirmSel ~= 1 })
    m.ok:SetState({ focus = self.confirmSel == 1 })
    m.ok.label:SetTextColor(unpack(KC.dangerText))
end

function G:Render()
    local o = self.frame
    if not (o and self.active) then return end
    local preview = self.mode == "preview"
    self:RenderHeader()
    for _, part in ipairs({ o.kicker, o.title, o.count, o.close, o.headRule }) do part:SetShown(not preview) end
    if preview then
        for _, d in ipairs(o.dots) do d:Hide() end
    end
    self.previewFrame:SetShown(preview)
    for sid, s in pairs(self.screens) do s.frame:SetShown(not preview and sid == self.sid) end
    o.bar:ClearAllPoints()
    if preview then
        -- 3b: the size alone, the help bar under it
        o.bar:SetPoint("TOPLEFT", o, "TOPLEFT", 2, -128)
        local p = self:Path()
        self.previewFrame.count:SetText(format("%s — %d / %d", L.GUIDE_CRUMB, indexOf(p, self.sid) or 1, #p))
        self.previewScreen.controls[1]:draw(true)
    else
        o.bar:SetPoint("TOPLEFT", o, "TOPLEFT", 2, -532)
        local s = self:Current()
        if s.render then s.render() end
        local focused = self.mode == "normal" and self:Focused()
        for _, c in ipairs(s.controls) do
            if c.shown then
                local on = shown(c)
                c.frame:SetShown(on)
                if c.label then c.label:SetShown(on) end
            end
            c:draw(c == focused)
        end
        if s.layout then s.layout() end
        self:RenderStep(s)
    end
    self:RenderConfirm()
    self:RenderHelp()
end

-- The ask box's progress: one dot each
local function renderAsk(s)
    local G_ = G
    local identifying = G_.mode == "identify"
    s.ask:SetShown(identifying)
    s.found:SetText(G_.found and #G_.found > 0 and format(L.GUIDE_FOUND, table.concat(G_.found, ", ")) or "")
    s.found:SetShown(not identifying)
    local id = identifying and G_.asked and G_.asked.id
    if id then
        s.ask.title:SetText(format(L.GUIDE_PRESS, id))
        s.ask.help:SetText(askHelp(id) .. " " .. format(L.GUIDE_ASK_WAIT, IDENTIFY_WAIT))
        for i = 1, math.max(#G_.queue, #s.ask.dots) do
            local d = s.ask.dots[i]
            if not d and i <= #G_.queue then
                d = s.ask:CreateTexture(nil, "OVERLAY")
                s.ask.dots[i] = d
            end
            if d then
                d:SetShown(i <= #G_.queue)
                local now = i == G_.queueAt
                d:SetTexture(TEX .. (now and "ck_dot" or "ck_ring"))
                d:SetVertexColor(unpack(now and KC.focus or KC.boxEdge))
                d:SetSize(now and 10 or 8, now and 10 or 8)
                d:ClearAllPoints()
                d:SetPoint("CENTER", s.ask, "TOPRIGHT", -16 - (#G_.queue - i) * 14, -24)
            end
        end
    end
    return identifying, id
end

-- What a screen shows besides its controls
function G:RenderStep(s)
    if self.sid == "paddles" then
        local identifying, id = renderAsk(s)
        s.paddlesHelp:SetShown(not identifying)
        s.identify.frame:SetShown(not identifying)
        s.right:SetAlpha(identifying and 0.35 or 1)
        for pid, t in pairs(s.paddleGlow) do t:SetAlpha(pid == id and 1 or 0) end
        s.paddlesGlow:SetAlpha(identifying and 0 or 0.35)
    elseif self.sid == "dualsense" then
        local identifying = renderAsk(s)
        local edge = self:Edge()
        s.edgeHelp:SetShown(edge and not identifying)
        if not edge then
            s.ask:Hide()
            s.found:Hide()
        end
    elseif self.sid == "bar" then
        s.toggleGlow:SetAlpha(settings().features.triggerToggle and 1 or 0)
    end
end

-- Animations: the asked paddle's glow breathing, the touchpad's zones lit
-- in turn once ticked; the waits (5 s a paddle, 10 s a key)
function G:OnUpdate()
    if not self.active then return end
    local now = GetTime()
    if self.mode == "identify" and self.asked and self.askedAt and now - self.askedAt > IDENTIFY_WAIT then
        self.askedAt = nil
        P():StopCapture(nil)
        return
    end
    if self.mode == "bind" and self.bindAt and now - self.bindAt > BIND_WAIT then return self:EndBind() end
    local s = self:Current()
    if self.sid ~= "paddles" or not s then return end
    local pulse = 0.55 + 0.45 * math.sin(now * 4)
    if self.mode == "identify" and self.asked then
        local t = s.paddleGlow[self.asked.id]
        if t then t:SetAlpha(pulse) end
        local n = tonumber(self.asked.id:match("^T[LR](%d)$") or "")
        for i, z in ipairs(s.zoneGlow) do z:SetAlpha(n == i and pulse or 0) end
    else
        local t0 = self.zonesAt
        for i, z in ipairs(s.zoneGlow) do
            local lit = t0 and now - t0 < 1.2 and math.floor((now - t0) / 0.3) + 1 == i
            z:SetAlpha(lit and 1 or 0)
        end
    end
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------
function G:Seen()
    local o = CK.db and CK.db.onboarding
    return type(o) == "table" and o.seen == true
end

function G:SetSeen()
    if not CK.db then return end
    CK.db.onboarding = { seen = true, version = VERSION }
end

function G:IsOpen() return self.active and true or false end

-- The screens of the first guide, by their number (Home > Guide: 1; a
-- reload saved by an older version)
local OLD_STEPS = { "welcome", "paddles", "bar", "keyboard", "wheels", "comfort" }

local function screenOf(step)
    if type(step) == "number" then return OLD_STEPS[step] or "welcome" end
    if type(step) == "string" and indexOf(G.SCREENS, step) then return step end
    return "welcome"
end

-- At a screen ("welcome" by default), over the panel (opened for it, or
-- already open: Home > Guide). quick: the way it goes (the quick one if
-- not given, the detailed one for its own screens)
function G:Open(step, quick)
    if CK:BlockedByCombat() then return end
    local Cfg = C()
    self.fromPanel = Cfg.frame ~= nil and Cfg.frame:IsShown() and not Cfg.placing
    if not self.fromPanel then Cfg:Open() end
    if not (Cfg.frame and Cfg.frame:IsShown()) then return end
    Cfg:StopChordCapture(nil)
    Cfg:Disarm()
    self:Build()
    local sid = screenOf(step)
    self.active, self.mode = true, "normal"
    self.rerun = self:Seen()
    if quick ~= nil then
        self.quick = quick and true or false
    else
        self.quick = true
    end
    if not indexOf(self:Path(), sid) and sid ~= "whatsnew" then self.quick = false end
    -- The touchpad's corners as they were (the corners' "keep mine")
    local t = touchSettings()
    local regions = {}
    for _, k in ipairs(CORNER_ORDER) do regions[k] = t.regions and t.regions[k] end
    self.savedTouch, self.cornerPick = { enabled = t.enabled, regions = regions }, nil
    self.found = nil
    self.frame:Show()
    Cfg.guide = self
    self:Go(sid)
end

-- Its layer away: what it was doing ended, the panel's own pages back
function G:Leave()
    if not self.active then return end
    if self.mode == "identify" then self:EndIdentify(false) end
    if self.mode == "bind" then self:EndBind() end
    if self.mode == "preview" then self:EndPreview(true) end
    self.active, self.mode = false, "normal"
    if self.frame then self.frame:Hide() end
    if C().guide == self then C().guide = nil end
end

-- Done (Finish, Later, the window's X, B on the first step): seen. Opened
-- from the panel, back to it; else the panel closed (or on a tab of it:
-- "gamepad", to put spells)
function G:Finish(tab)
    self:SetSeen()
    local fromPanel = self.fromPanel
    self:Leave()
    if tab then
        C():SetTab(tab)
    elseif fromPanel then
        C():Render()
    else
        C():Close()
    end
end

function G:Later() self:Finish() end

-- The panel closed under it: by a fight, back at this screen once it's
-- over (not seen yet); by the player, as Later
function G:Closed(reason)
    if not self.active then return end
    if reason == "combat" then
        self.interrupted = not self:Seen() and self.sid or nil
    else
        self:SetSeen()
    end
    self:Leave()
end

-- Once the game is free (no game window with the pad, no fight), within
-- two minutes. overChat: typed in the chat (/ec welcome), the chat still
-- open doesn't stop it. firstTime: by itself (a new install, after a
-- fight), dropped once seen
function G:OpenWhenFree(step, overChat, firstTime, quick)
    local Cfg = C()
    local function ready()
        if InCombatLockdown() or Cfg.placing then return false end
        return (Cfg.frame ~= nil and Cfg.frame:IsShown()) or Cfg:GameIsFree(overChat)
    end
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    if not firstTime and ready() then
        -- (typed in the chat: once the game is done with the send)
        if overChat then
            C_Timer.After(0.15, function()
                if ready() and not G:IsOpen() then G:Open(step, quick) end
            end)
        else
            self:Open(step, quick)
        end
        return
    end
    local tries = 0
    self.ticker = C_Timer.NewTicker(0.5, function(ticker)
        tries = tries + 1
        if G:IsOpen() or (firstTime and G:Seen()) or tries > 240 then
            ticker:Cancel()
            G.ticker = nil
        elseif ready() then
            ticker:Cancel()
            G.ticker = nil
            G:Open(step, quick)
        end
    end)
end

function G:Init()
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(frame, event)
        if not CK.db then return end
        if event == "PLAYER_ENTERING_WORLD" then
            frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
            local ob = CK.db.onboarding
            local resume = ob and ob.resume
            if resume then
                -- Reloaded by the guide (the compact bar, from scratch):
                -- back at its screen, the same way
                local quick = ob.quick
                ob.resume, ob.quick = nil, nil
                C_Timer.After(2, function() G:OpenWhenFree(resume, false, false, quick) end)
            elseif not G:Seen() then
                -- The first login of a new install: a few seconds in
                C_Timer.After(3, function() G:OpenWhenFree("welcome", false, true) end)
            elseif (ob.version or 1) < VERSION then
                -- After an update: what's new, once
                C_Timer.After(3, function() G:OpenWhenFree("whatsnew") end)
            end
        elseif G.interrupted then
            local sid = G.interrupted
            G.interrupted = nil
            if not G:Seen() then C_Timer.After(1, function() G:OpenWhenFree(sid, false, true) end) end
        end
    end)
end
G:Init()
