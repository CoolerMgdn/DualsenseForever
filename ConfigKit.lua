local _, CK = ...
local L = CK.L

-- The 2.0 configuration panel's parts (Claude Design handoff, "Easy
-- Controller - Composants"): its colours and type, rounded boxes, gamepad
-- glyphs, the help bar's hints, the detail panel and the lists picker. The
-- pages (ConfigWindow.lua, Options.lua, MapWindow.lua, MyWheels.lua) are
-- made of them. Sizes are the handoff's, in UI pixels at scale 1.
local K = {}
CK.ConfigKit = K

local TEX = "Interface\\AddOns\\DualsenseForever\\textures\\"
K.TEX = TEX

local function hex(h)
    return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 }
end

K.C = {
    title = hex("F2C43C"), focus = hex("FFD24A"), dimGold = hex("C9A25A"), focusText = hex("FFF3D0"),
    cream = hex("EFE4C8"), cream2 = hex("D8CCB0"), tab = hex("E6DCC4"), rail = hex("CBBD9C"),
    help = hex("B9AB8C"), grey = hex("9D917A"), disabled = hex("6F6452"),
    bronze = hex("7A5D36"), line1 = hex("5A4630"), line2 = hex("4A3A26"), line3 = hex("3A2C1D"),
    control = hex("6B5235"), boxEdge = hex("7A6448"), boxOff = hex("4A3C2A"), arrowOff = hex("5A4C3A"),
    bg = hex("16110C"), controlBg = hex("0F0B07"), boxBg = hex("0B0805"), pressed = hex("2A1F12"),
    slot = hex("D9A93A"), yours = hex("5FC0D0"), info = hex("9FD8E2"), fill = hex("8A6A2A"),
    danger = hex("FF7A5C"), dangerBg = hex("4A140E"), dangerText = hex("FFE0D6"), warn = hex("F0A090"),
    eventOff = hex("7A6E5A"), inner = hex("2A1F14"), white = { 1, 1, 1 }, black = { 0, 0, 0 },
    -- The Gamepad screen's states, the wizard's steps, the wheels' dots
    gameFn = hex("8A8070"), off = hex("5A4C3A"), iconBg = hex("3E3A33"), iconFg = hex("CFC6B2"),
    doneBg = hex("2A3A1C"), done = hex("7AA04A"), nowBg = hex("3A2C12"), legendRing = hex("7A7060"),
    legendFree = hex("7A6A52"), legendGame = hex("4A463E"), legendSlot = hex("3A3020"), legendYours = hex("1C3236"),
    spell = hex("2F4A73"), item = hex("6B4A1C"), macro = hex("4F3466"), game = hex("4A463E"), bar = hex("5A4422"),
    emptyDot = hex("6B5A44"), panel = hex("120D08"),
    -- The game's own gold (GameFontNormal)
    gameGold = { 1, 0.82, 0 },
}
local C = K.C

---------------------------------------------------------------------------
-- Fork CoolerMgdn (asked): three looks for the settings window. "frame"
-- (the default): the game's own frame around the addon's own parts, type at
-- the game's sizes; "blizzard": the game's buttons too; "large": the addon's
-- own look, its big type (read from a sofa). Read once:
-- a change shows after a reload (Home › Look). Only the window's parts
-- follow it (the bags, the keyboard keep theirs).
---------------------------------------------------------------------------
function K.Look()
    if not K.look then
        local s = CK.db and CK.db.settings
        -- (kept once the settings are there: before that, the default)
        if not s then return "frame" end
        K.look = K.LookOf(s.configLook)
    end
    return K.look
end

K.LOOKS = { "frame", "blizzard", "large" }
-- A saved value, as one of them (anything else: the default)
function K.LookOf(value)
    for _, look in ipairs(K.LOOKS) do
        if value == look then return look end
    end
    return "frame"
end

-- The game's window around ours
function K.GameFrame()
    return K.Look() ~= "large"
end

-- The game's buttons
function K.Blizzard()
    return K.Look() == "blizzard"
end

-- Type at the game's sizes
function K.SmallType()
    return K.Look() ~= "large"
end

-- A region inside the settings window (or the window itself)
function K.InConfig(region)
    local f = CK.Config and CK.Config.frame
    local n = 0
    while region and f and n < 30 do
        if region == f then return true end
        region = region.GetParent and region:GetParent()
        n = n + 1
    end
    return false
end

-- A type size for the look: the game's sizes are about 0.82 of ours
K.TYPE_SCALE = 0.82
function K.FS(size, region)
    if K.SmallType() and (region == nil or K.InConfig(region)) then
        return math.max(9, math.floor(size * K.TYPE_SCALE + 0.5))
    end
    return size
end

---------------------------------------------------------------------------
-- Type: Friz Quadrata (or the font picked in Home > Look) for titles and
-- labels, the chat's font for help texts, counters and the crumb
---------------------------------------------------------------------------
function K.Text(parent, size, color, layer)
    local fs = CK.UIKit.text(parent, K.FS(size, parent), layer)
    fs:SetWordWrap(false)
    fs:SetJustifyH("LEFT")
    if color then fs:SetTextColor(unpack(color)) end
    return fs
end

local function chatFont()
    return (ChatFontNormal and ChatFontNormal:GetFont()) or STANDARD_TEXT_FONT or "Fonts\\ARIALN.TTF"
end

function K.ChatText(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(chatFont(), K.FS(size, parent), "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetJustifyH("LEFT")
    if color then fs:SetTextColor(unpack(color)) end
    return fs
end

-- Upper case, accented letters too (string.upper leaves UTF-8 alone): the
-- Latin-1 ones, U+00E0-U+00FE but the division sign
function K.Upper(text)
    local up = text:upper():gsub("\195([\160-\190])", function(c)
        if c == "\183" then return nil end
        return "\195" .. string.char(c:byte() - 32)
    end)
    -- Fork CoolerMgdn: the Cyrillic letters too (CK.Upper knows them)
    return (CK.Upper and CK.Upper(up) or up)
end

-- A solid colour texture
function K.Solid(parent, color, alpha, layer, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    t:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    return t
end

---------------------------------------------------------------------------
-- Rounded boxes: nine-slices of the ck_box textures (32 texels for 16 px,
-- corners of 4 px), tinted
---------------------------------------------------------------------------
function K.Slice(parent, file, layer, sub)
    local s = { parts = {} }
    local u = 8 / 32
    local cuts = { { 0, u }, { u, 1 - u }, { 1 - u, 1 } }
    for r = 1, 3 do
        for c = 1, 3 do
            local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
            t:SetTexture(TEX .. file)
            t:SetTexCoord(cuts[c][1], cuts[c][2], cuts[r][1], cuts[r][2])
            s.parts[#s.parts + 1] = t
        end
    end
    local tl, t, tr, l, m, rt, bl, b, br = unpack(s.parts)
    function s:SetPoints(region, inset)
        inset = inset or 0
        for _, p in ipairs(self.parts) do p:ClearAllPoints() end
        tl:SetPoint("TOPLEFT", region, "TOPLEFT", inset, -inset)
        tr:SetPoint("TOPRIGHT", region, "TOPRIGHT", -inset, -inset)
        bl:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", inset, inset)
        br:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", -inset, inset)
        for _, corner in ipairs({ tl, tr, bl, br }) do corner:SetSize(4, 4) end
        t:SetPoint("TOPLEFT", tl, "TOPRIGHT"); t:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
        b:SetPoint("TOPLEFT", bl, "TOPRIGHT"); b:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
        l:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); l:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
        rt:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); rt:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
        m:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT"); m:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
    end
    function s:SetColor(color, alpha)
        for _, p in ipairs(self.parts) do p:SetVertexColor(color[1], color[2], color[3], alpha or 1) end
    end
    function s:SetShown(shown)
        for _, p in ipairs(self.parts) do p:SetShown(shown) end
    end
    s:SetPoints(parent)
    return s
end

-- A filled box with an edge: radius 3 (edge 2) or 4 (edge 1 or 2)
function K.Box(parent, radius, edge, layer, sub)
    local box = { fill = K.Slice(parent, format("ck_box%d", radius), layer, sub) }
    if edge then box.line = K.Slice(parent, format("ck_box%d_line%d", radius, edge), layer, (sub or 0) + 1) end
    function box:SetPoints(region, inset)
        self.fill:SetPoints(region, inset)
        if self.line then self.line:SetPoints(region, inset) end
    end
    -- No colour: that part stays hidden (an edge alone, a fill alone)
    function box:SetColors(fill, fillAlpha, line, lineAlpha)
        self.noFill, self.noLine = fill == nil, line == nil
        self.fill:SetShown(fill ~= nil and not self.hidden)
        if fill then self.fill:SetColor(fill, fillAlpha) end
        if self.line then
            self.line:SetShown(line ~= nil and not self.hidden)
            if line then self.line:SetColor(line, lineAlpha) end
        end
    end
    function box:SetShown(shown)
        self.hidden = not shown
        self.fill:SetShown(shown and not self.noFill)
        if self.line then self.line:SetShown(shown and not self.noLine) end
    end
    return box
end

-- The window look (ConfigWindow) and its small panels (placement banners):
-- the stone tile, a 2 px bronze edge, a 1 px dark line inside it
function K.Panel(f)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetTexture(TEX .. "ck_panel_bg", "REPEAT", "REPEAT")
    bg:SetHorizTile(true)
    bg:SetVertTile(true)
    bg:SetAllPoints()
    local under = K.Solid(f, C.bg, 1, "BACKGROUND", -8)
    under:SetAllPoints()
    under:SetDrawLayer("BACKGROUND", -8)
    bg:SetDrawLayer("BACKGROUND", -7)
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
        { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
        local t = K.Solid(f, C.bronze, 1, "BORDER")
        t:SetPoint(e[1]); t:SetPoint(e[2])
        if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
    end
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, -2, nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 2, nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 2, 0, 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", -2, 0, 1, nil } }) do
        local t = K.Solid(f, C.inner, 1, "BORDER", 1)
        t:SetPoint(e[1], e[3], e[4]); t:SetPoint(e[2], e[3], e[4])
        if e[5] then t:SetWidth(e[5]) else t:SetHeight(e[6]) end
    end
end

---------------------------------------------------------------------------
-- Glyphs: the gamepad's buttons (Glyphs.lua: the game's atlases or ours),
-- a grey pill with its name for the others (Select, Start, the paddles)
---------------------------------------------------------------------------
local IMAGE = {
    A = true, B = true, X = true, Y = true, LB = true, RB = true, LT = true, RT = true, LS = true, RS = true,
    DPAD = true, DPAD_LR = true, DPAD_UP = true, DPAD_LEFT = true, DPAD_RIGHT = true, DPAD_DOWN = true,
}
K.IMAGE = IMAGE
-- The mapping's inputs, as glyph keys
K.INPUT_GLYPH = {
    L3 = "LS", R3 = "RS", UP = "DPAD_UP", DOWN = "DPAD_DOWN", LEFT = "DPAD_LEFT", RIGHT = "DPAD_RIGHT",
}
-- Fork CoolerMgdn: on a PlayStation pad the game's Select is the touchpad's
-- click (PADBACK), Create a button of its own (PADSOCIAL, the CREATE input)
-- and the mic too (PAD5): drawn with the game's own glyphs for them
local CHIP_TEXT = { SELECT = "Select", START = "Start", CREATE = "Share", MIC = "Mic" }
local CHIP_PS = { SELECT = CK.L.CHIP_TOUCHPAD, START = "Options", CREATE = "Create", MIC = CK.L.CHIP_MIC }
local CHIP_SWITCH = { SELECT = "-", START = "+", CREATE = "Capture" }
local PS_KEY = { SELECT = "PADBACK", START = "PADFORWARD", CREATE = "PADSOCIAL", MIC = "PAD5" }

-- The game's glyph for one of those, on a PlayStation pad, or nil
function K.PadGlyphAtlas(key)
    if not (PS_KEY[key] and CK.db and CK:GlyphStyle() == "playstation" and CK.PadAtlas) then return nil end
    return CK.PadAtlas(PS_KEY[key])
end

function K.ChipText(key)
    local style = CK.db and CK:GlyphStyle()
    if style == "playstation" and CHIP_PS[key] then return CHIP_PS[key] end
    if style == "switch" and CHIP_SWITCH[key] then return CHIP_SWITCH[key] end
    return CHIP_TEXT[key] or key
end

-- Fork CoolerMgdn (asked): the pad's glyphs smaller in the window's game
-- looks (its type is smaller too)
K.GLYPH_SCALE = 0.78
function K.GS(size, region)
    if K.SmallType() and K.InConfig(region) then
        return math.max(12, math.floor(size * K.GLYPH_SCALE + 0.5))
    end
    return size
end

function K.Glyph(parent, size)
    size = K.GS(size, parent)
    local g = CK.NewFrame("Frame", nil, parent)
    g:SetSize(size, size)
    g.size = size
    g.tex = g:CreateTexture(nil, "ARTWORK")
    g.tex:SetAllPoints()
    -- The pill: three pieces of ck_chip (rounded ends, a middle that stretches)
    local h = math.floor(size * 0.72 + 0.5)
    g.chip = {}
    for i, cut in ipairs({ { 0, 22 / 64 }, { 22 / 64, 42 / 64 }, { 42 / 64, 1 } }) do
        local t = g:CreateTexture(nil, "ARTWORK")
        t:SetTexture(TEX .. "ck_chip")
        t:SetTexCoord(cut[1], cut[2], 10 / 64, 54 / 64)
        t:SetHeight(h)
        g.chip[i] = t
    end
    g.chip[1]:SetPoint("LEFT")
    g.chip[1]:SetWidth(h / 2)
    g.chip[3]:SetPoint("RIGHT")
    g.chip[3]:SetWidth(h / 2)
    g.chip[2]:SetPoint("LEFT", g.chip[1], "RIGHT")
    g.chip[2]:SetPoint("RIGHT", g.chip[3], "LEFT")
    g.label = K.ChatText(g, math.max(9, math.floor(size * 0.38)), C.white)
    g.label:SetPoint("CENTER", 0, 0)
    g.label:SetJustifyH("CENTER")
    function g:Set(key)
        local atlas = not IMAGE[key] and K.PadGlyphAtlas(key)
        local image = IMAGE[key] or atlas ~= nil
        self.tex:SetShown(image)
        for _, t in ipairs(self.chip) do t:SetShown(not image) end
        self.label:SetShown(not image)
        if atlas then
            self.tex:SetTexCoord(0, 1, 0, 1)
            self.tex:SetAtlas(atlas)
            -- (the touchpad's glyph is wide: its own proportions)
            local info = C_Texture.GetAtlasInfo(atlas)
            local wide = info and info.height and info.height > 0 and info.width / info.height or 1
            self:SetWidth(self.size * math.max(1, wide))
        elseif image then
            CK:SetGlyph(self.tex, key)
            self:SetWidth(self.size)
        else
            self.label:SetText(K.ChipText(key))
            self:SetWidth(math.max(self.size * 0.75, self.label:GetStringWidth() + h * 0.6))
        end
        self:Show()
    end
    return g
end

-- A row of glyphs ("RT + A"): keys, "+" for a plus sign; returns its width
function K.GlyphRow(parent, size)
    local row = CK.NewFrame("Frame", nil, parent)
    row:SetSize(1, size)
    row.items = {}
    function row:Set(keys)
        local x = 0
        for i, key in ipairs(keys or {}) do
            local item = self.items[i]
            if not item then
                item = { glyph = K.Glyph(self, size), plus = K.Text(self, 16, C.cream) }
                item.plus:SetText("+")
                self.items[i] = item
            end
            item.glyph:ClearAllPoints()
            item.plus:ClearAllPoints()
            if key == "+" then
                item.glyph:Hide()
                item.plus:Show()
                item.plus:SetPoint("LEFT", x + 2, 0)
                x = x + item.plus:GetStringWidth() + 4
            else
                item.plus:Hide()
                item.glyph:Set(K.INPUT_GLYPH[key] or key)
                item.glyph:SetPoint("LEFT", x, 0)
                x = x + item.glyph:GetWidth() + 1
            end
        end
        for i = #(keys or {}) + 1, #self.items do
            self.items[i].glyph:Hide()
            self.items[i].plus:Hide()
        end
        self:SetWidth(math.max(1, x))
        return x
    end
    return row
end

-- A help bar hint: its glyph(s), then a short verb; a click presses its key
function K.Hint(parent)
    local h = CK.NewFrame("Button", nil, parent)
    h:SetHeight(30)
    h.glyphs = K.GlyphRow(h, 30)
    h.glyphs:SetPoint("LEFT")
    h.verb = K.Text(h, 15, C.cream)
    h:SetScript("OnClick", function(self) if self.press then CK.Config:ClickHint(self.press) end end)
    function h:Set(hint)
        local w = self.glyphs:Set(hint.keys)
        self.verb:ClearAllPoints()
        self.verb:SetPoint("LEFT", w + 6, 0)
        self.verb:SetText(hint.verb or "")
        self.press = hint.press
        self:SetWidth(w + 6 + self.verb:GetStringWidth())
        self:Show()
    end
    return h
end

---------------------------------------------------------------------------
-- A round icon (spell, item, macro...) cut by a circle
---------------------------------------------------------------------------
local function hasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- A square icon with the corners of the game's gamepad bar (its SquareMask)
function K.SquareIcon(parent, size, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetSize(size, size)
    if hasAtlas("SquareMask") then
        local mask = parent:CreateMaskTexture()
        mask:SetAllPoints(t)
        mask:SetAtlas("SquareMask")
        t:AddMaskTexture(mask)
    end
    return t
end

function K.RoundIcon(parent, size, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetSize(size, size)
    local mask = parent:CreateMaskTexture()
    mask:SetAllPoints(t)
    if hasAtlas("CircleMask") then
        mask:SetAtlas("CircleMask")
    else
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    t:AddMaskTexture(mask)
    return t
end

---------------------------------------------------------------------------
-- The detail panel (right): what has the focus, explained. From the top:
-- the glyphs of a combination (Gamepad), a title, a state tag (a dot and a
-- word), the help text, a cyan info line; a legend at the bottom (Gamepad)
---------------------------------------------------------------------------
function K.Detail(parent, width, comboSize)
    local d = CK.NewFrame("Frame", nil, parent)
    d:SetWidth(width)
    d.box = K.Box(d, 4, 1, "BACKGROUND", 1)
    d.box:SetPoints(d)
    d.box:SetColors(C.black, 0.72, C.line1, 1)
    local inner = width - 28
    d.combo = K.GlyphRow(d, comboSize or 34)
    d.title = K.Text(d, 19, C.title)
    d.title:SetWidth(inner)
    d.title:SetWordWrap(true)
    d.title:SetSpacing(5)
    d.dot = d:CreateTexture(nil, "ARTWORK")
    d.dot:SetTexture(TEX .. "ck_dot")
    d.dot:SetSize(10, 10)
    d.tag = K.ChatText(d, 13, C.cream)
    d.body = K.ChatText(d, 14, C.cream2)
    d.body:SetWidth(inner)
    d.body:SetWordWrap(true)
    d.body:SetSpacing(6)
    d.extra = K.ChatText(d, 14, C.info)
    d.extra:SetWidth(inner)
    d.extra:SetWordWrap(true)
    d.extra:SetSpacing(6)
    -- Fork CoolerMgdn: a preview at the bottom (content.preview = function(canvas))
    d.preview = CK.NewFrame("Frame", nil, d)
    d.preview:SetPoint("BOTTOMLEFT", 14, 14)
    d.preview:SetPoint("BOTTOMRIGHT", -14, 14)
    d.preview:SetHeight(K.PREVIEW_H)
    local pline = K.Solid(d.preview, C.line3, 1, "BORDER")
    pline:SetPoint("TOPLEFT")
    pline:SetPoint("TOPRIGHT")
    pline:SetHeight(1)
    d.preview.kicker = K.ChatText(d.preview, 11, C.grey)
    d.preview.kicker:SetPoint("TOPLEFT", 0, -7)
    d.preview.canvas = K.Canvas(d.preview, inner, K.PREVIEW_H - 24)
    d.preview.canvas:SetPoint("TOPLEFT", 0, -24)
    d.preview:Hide()
    -- content = { combo = { keys }, title, tag, tagColor, body, extra, preview }
    function d:Set(content)
        content = content or {}
        local last
        local function place(region, gap)
            region:ClearAllPoints()
            if last then
                region:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -(gap or 10))
            else
                region:SetPoint("TOPLEFT", self, "TOPLEFT", 14, -14)
            end
            last = region
        end
        self.combo:SetShown(content.combo ~= nil)
        if content.combo then
            self.combo:Set(content.combo)
            place(self.combo)
        end
        self.title:SetText(content.title or "")
        place(self.title)
        self.dot:SetShown(content.tag ~= nil)
        self.tag:SetShown(content.tag ~= nil)
        if content.tag then
            place(self.dot)
            local tc = content.tagColor or C.grey
            self.dot:SetVertexColor(tc[1], tc[2], tc[3])
            self.tag:ClearAllPoints()
            self.tag:SetPoint("LEFT", self.dot, "RIGHT", 8, 0)
            self.tag:SetText(content.tag)
        end
        self.body:SetShown(content.body ~= nil and content.body ~= "")
        if self.body:IsShown() then
            self.body:SetText(content.body)
            place(self.body)
        end
        self.extra:SetShown(content.extra ~= nil)
        if content.extra then
            self.extra:SetText(content.extra)
            place(self.extra)
        end
        -- A legend at the bottom (the Gamepad screen's states), set by its page
        if self.legend then self.legend:SetShown(content.legend and true or false) end
        -- The preview: the texts above it kept short enough to clear it
        local pv = content.preview
        self.preview:SetShown(pv ~= nil)
        if self.body.SetMaxLines then self.body:SetMaxLines(pv and 7 or 0) end
        if pv then
            self.preview.kicker:SetText(K.Upper(L.PREVIEW))
            self.preview.canvas:Reset()
            local ok, err = pcall(pv, self.preview.canvas)
            if not ok and CK.Flight then CK.Flight:Note("preview: %s", tostring(err)) end
        end
    end
    return d
end

---------------------------------------------------------------------------
-- Fork CoolerMgdn: a small canvas for the previews: plain or textured
-- rectangles, dots, texts and glyphs, from its top left corner, pooled
---------------------------------------------------------------------------
K.PREVIEW_H = 132

function K.Canvas(parent, width, height)
    local c = CK.NewFrame("Frame", nil, parent)
    c:SetSize(width, height)
    c.w, c.h = width, height
    c.tex, c.fs, c.glyphs = {}, {}, {}
    function c:Reset()
        for _, t in ipairs(self.tex) do t:Hide() end
        for _, f in ipairs(self.fs) do f:Hide() end
        for _, g in ipairs(self.glyphs) do g:Hide() end
        self.nt, self.nf, self.ng = 0, 0, 0
    end
    -- color = { r, g, b }; file: one of our textures (tinted); sub: its level
    function c:Rect(x, y, w, h, color, alpha, file, sub)
        self.nt = self.nt + 1
        local t = self.tex[self.nt]
        if not t then
            t = self:CreateTexture(nil, "ARTWORK")
            self.tex[self.nt] = t
        end
        t:SetDrawLayer("ARTWORK", sub or 0)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
        t:SetSize(math.max(1, w), math.max(1, h))
        t:SetTexCoord(0, 1, 0, 1)
        if file then
            t:SetTexture(TEX .. file)
            t:SetVertexColor(color[1], color[2], color[3], alpha or 1)
        else
            t:SetColorTexture(color[1], color[2], color[3], alpha or 1)
        end
        t:Show()
        return t
    end
    function c:Dot(cx, cy, size, color, alpha, sub)
        return self:Rect(cx - size / 2, cy - size / 2, size, size, color, alpha, "ck_dot", sub)
    end
    -- A 1 px frame round a rectangle
    function c:Frame(x, y, w, h, color, alpha, sub)
        self:Rect(x, y, w, 1, color, alpha, nil, sub)
        self:Rect(x, y + h - 1, w, 1, color, alpha, nil, sub)
        self:Rect(x, y, 1, h, color, alpha, nil, sub)
        self:Rect(x + w - 1, y, 1, h, color, alpha, nil, sub)
    end
    function c:Text(x, y, text, size, color, w, justify)
        self.nf = self.nf + 1
        local f = self.fs[self.nf]
        if not f then
            f = K.ChatText(self, 12, C.cream)
            f:SetWordWrap(false)
            self.fs[self.nf] = f
        end
        f:SetFont((ChatFontNormal and ChatFontNormal:GetFont()) or STANDARD_TEXT_FONT, K.FS(size or 12, self), "")
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
        f:SetWidth(w or 0)
        f:SetJustifyH(justify or "LEFT")
        local col = color or C.cream
        f:SetTextColor(col[1], col[2], col[3])
        f:SetText(text or "")
        f:Show()
        return f
    end
    function c:Glyph(x, y, key, size)
        self.ng = self.ng + 1
        local g = self.glyphs[self.ng]
        if not g or g.size ~= size then
            g = K.Glyph(self, size)
            self.glyphs[self.ng] = g
        end
        g:ClearAllPoints()
        g:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
        g:Set(key)
        return g
    end
    c:Reset()
    return c
end

---------------------------------------------------------------------------
-- Fork CoolerMgdn: the previews (a row's preview = function(canvas) ...)
---------------------------------------------------------------------------
local P = {}
K.Preview = P

local function rgb(h) return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 } end
local DARK, SCENE = rgb("15110C"), rgb("1C2418")

-- A vibration pattern: each motor's steps over time (left gold, right cyan)
function P.Vibration(c, pattern, on, intensity)
    local V = CK.Vibration
    local steps
    for _, p in ipairs(V and V.PATTERNS or {}) do
        if p.key == pattern then steps = p.steps end
    end
    steps = steps or {}
    intensity = intensity or 0.6
    local total = 0
    for _, s in ipairs(steps) do total = total + s[3] end
    local scale = (c.w - 26) / math.max(total, 0.3)
    c:Text(0, 26, "Л", 11, C.grey)
    c:Text(0, 64, "П", 11, C.grey)
    c:Rect(20, 40, c.w - 20, 1, C.line2)
    c:Rect(20, 78, c.w - 20, 1, C.line2)
    local x = 22
    for _, s in ipairs(steps) do
        local w = math.max(3, s[3] * scale - 2)
        if s[1] > 0 then
            local h = s[1] * 30 * intensity
            c:Rect(x, 40 - h, w, h, on and C.slot or C.off, 1, nil, 1)
        end
        if s[2] > 0 then
            local h = s[2] * 30 * intensity
            c:Rect(x, 78 - h, w, h, on and C.yours or C.off, 1, nil, 1)
        end
        x = x + s[3] * scale
    end
    local text = on and format(L.PREVIEW_VIB, L["VIB_P_" .. pattern:upper()] or pattern,
        (format("%.2f", total):gsub("%.", ",")), math.floor(intensity * 100 + 0.5)) or L.VIB_OFF
    c:Text(0, 88, text, 12, on and C.cream2 or C.eventOff, c.w)
end

-- The touchpad and its four corners, the one focused lit
function P.Touch(c, actions, focus, caption)
    local T = CK.Touchpad
    local W2, H2 = c.w, 84
    c:Rect(0, 0, W2, H2, rgb("1A1712"))
    c:Frame(0, 0, W2, H2, rgb("5A5040"))
    c:Rect(W2 / 2, 8, 1, H2 - 16, rgb("3A342A"))
    c:Rect(8, H2 / 2, W2 - 16, 1, rgb("3A342A"))
    local pos = { upleft = { 0, 0 }, upright = { 1, 0 }, downleft = { 0, 1 }, downright = { 1, 1 } }
    for region, p in pairs(pos) do
        local w, h = (W2 - 12) / 2, (H2 - 12) / 2
        local x, y = 6 + p[1] * w, 6 + p[2] * h
        local off = T and T.IsOff and T.IsOff(region)
        local on = region == focus
        if on then
            c:Rect(x + 1, y + 1, w - 2, h - 2, C.focus, 0.22, nil, 1)
            c:Frame(x + 1, y + 1, w - 2, h - 2, C.focus, 1, 2)
        end
        local a = actions and actions[region]
        local name = off and L.TOUCH_OFF_TAG or ((T and T.Label and T.Label(a)) or "")
        c:Text(x + 2, y + h / 2 - 7, name, 12, off and C.eventOff or (on and C.focusText or C.cream2), w - 4, "CENTER")
    end
    c:Text(0, 92, caption or "", 12, C.grey, c.w)
end

-- The pad's buttons in the style picked
function P.Glyphs(c)
    local keys = { "A", "B", "X", "Y", "LB", "RB", "LT", "RT", "LS", "RS", "DPAD" }
    for i, key in ipairs(keys) do
        local col, row = (i - 1) % 6, math.floor((i - 1) / 6)
        c:Glyph(col * 34, row * 36, key, 28)
    end
end

-- The reticle on a game-like ground
function P.Reticle(c)
    local r = CK.db.settings.reticle or {}
    local R = CK.Reticle
    c:Rect(0, 0, c.w, 78, SCENE)
    c:Frame(0, 0, c.w, 78, C.line2)
    local cx, cy = c.w / 2, 34
    local caption
    if r.mode == "color" then
        local col = (R.COLORS[r.color or 1] or R.COLORS[1]).rgb
        c:Dot(cx, cy, 9, col, 1, 1)
        caption = L.PREVIEW_RET_COLOR
    elseif r.mode == "cycle" then
        local n = 0
        for _, col in ipairs(R.COLORS) do
            if not col.fixed then
                c:Dot(cx - 37 + n * 15, cy, 8, col.rgb, 1, 1)
                n = n + 1
            end
        end
        caption = L.PREVIEW_RET_CYCLE
    elseif r.mode == "hidden" then
        caption = L.PREVIEW_RET_HIDDEN
    else
        c:Dot(cx, cy, 9, C.white, 1, 1)
        caption = L.PREVIEW_RET_GAME
    end
    c:Text(0, 86, caption, 12, C.grey, c.w)
end

-- The chat keyboard's input method
local GRID_ROWS = {
    jcuken = { "йцукенгшщз", "фывапролдж", "ячсмитьбюэ" },
    default = { "qwertyuiop", "asdfghjkl'", "zxcvbnm,.?" },
}
function P.Method(c)
    local s = CK.db.settings
    local m = s.inputMethod
    if m == "grid" then
        local rows = GRID_ROWS[s.kbLayout] or GRID_ROWS.default
        for y, line in ipairs(rows) do
            local x = 0
            for ch in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                local on = y == 2 and x == 3
                c:Rect(x * 20 + 1, (y - 1) * 19 + 1, 18, 17, on and C.focus or DARK, on and 0.3 or 1)
                c:Frame(x * 20 + 1, (y - 1) * 19 + 1, 18, 17, on and C.focus or C.line1, 1, 1)
                c:Text(x * 20 + 1, (y - 1) * 19 + 4, ch, 11, on and C.focusText or C.cream2, 18, "CENTER")
                x = x + 1
            end
        end
        c:Rect(1, 58, 198, 17, DARK)
        c:Frame(1, 58, 198, 17, C.line1, 1, 1)
        c:Text(1, 61, L.SPACE or "", 11, C.cream2, 198, "CENTER")
    elseif m == "wheel" then
        for i = 0, 7 do
            local a = i * math.pi / 4
            local x, y = c.w / 2 + 36 * math.sin(a), 40 - 30 * math.cos(a)
            c:Dot(x, y, 24, i == 1 and C.focus or C.line1, i == 1 and 0.6 or 1)
            c:Dot(x, y, 20, DARK, 1, 1)
        end
        c:Dot(c.w / 2, 40, 12, C.slot, 1, 2)
    else
        for side = 0, 1 do
            for y = 0, 2 do
                for x = 0, 4 do
                    c:Rect(side * 106 + x * 19 + 1, y * 22 + 6, 17, 19, DARK)
                    c:Frame(side * 106 + x * 19 + 1, y * 22 + 6, 17, 19, C.line1, 1, 1)
                end
            end
        end
    end
    local names = { wheel = L.METHOD_WHEEL, stick = L.METHOD_STICK, grid = L.METHOD_GRID }
    c:Text(0, 86, names[m] or "", 12, C.grey, c.w)
end

-- The bags' counters: their buttons, the way they go, their size
function P.Supplies(c)
    local s = CK.db.settings.supplies
    local S = CK.Supplies
    local size = ({ 26, 32, 38 })[s.size or 2] or 32
    local list = {}
    for _, r in ipairs(S:Resources()) do
        if r.cfg.on then list[#list + 1] = r end
    end
    local dir = s.layout or "right"
    local n = #list
    local step = size + 8
    local horiz = dir == "right" or dir == "left"
    local cx0 = c.w / 2 - (horiz and (n - 1) * step / 2 or 0)
    local cy0 = 40 - (horiz and 0 or (n - 1) * step / 2)
    for i, r in ipairs(list) do
        local k = (dir == "left" or dir == "up") and (n - i) or (i - 1)
        local cx = horiz and (cx0 + k * step) or cx0
        local cy = horiz and cy0 or (cy0 + k * step)
        local low, crit = r.count <= r.cfg.low, r.count <= r.cfg.critical
        local ring = crit and { 1, 0.12, 0.08 } or (low and { 1, 0.55, 0.1 } or C.slot)
        c:Dot(cx, cy, size + 4, ring)
        c:Dot(cx, cy, size, rgb("2A2014"), 1, 1)
        c:Text(cx - size / 2, cy + size / 2 - 14, tostring(r.count), 11, C.white, size, "CENTER")
    end
    if n == 0 then c:Text(0, 34, L.PREVIEW_SUP_NONE, 12, C.grey, c.w, "CENTER") end
    local sizes = { L.SIZE_SMALL, L.SIZE_NORMAL, L.SIZE_LARGE }
    c:Text(0, 88, (L["SUP_DIR_" .. dir:upper()] or "") .. " — " .. (sizes[s.size or 2] or ""), 12, C.grey, c.w)
end

-- The gamepad bags: compact or full, their edges
local QUALITY = { rgb("A335EE"), rgb("0070DD"), rgb("1EFF00"), rgb("9D9D9D"), rgb("FFFFFF") }
function P.Bags(c)
    local lk = CK.db.settings.bagsLook or {}
    local def = CK.Bags and CK.Bags.LOOK_DEFAULTS or {}
    local layout = lk.layout or def.layout or "compact"
    local edgeColor = lk.edgeColor or def.edgeColor or "quality"
    local edgeSize = lk.edgeSize or def.edgeSize or 2
    local full = layout == "full"
    local cols, n, sz = full and 7 or 8, full and 21 or 24, full and 17 or 20
    local x0 = full and 54 or (c.w - cols * (sz + 3)) / 2
    if full then
        local tabs = L.PREVIEW_BAG_TABS
        local i = 0
        for name in tabs:gmatch("[^,]+") do
            if i == 0 then c:Rect(0, 2 + i * 18, 46, 16, C.focus, 0.25) end
            c:Text(3, 4 + i * 18, name, 10, i == 0 and C.focusText or C.cream2, 44)
            i = i + 1
        end
    end
    for i = 0, n - 1 do
        local x, y = x0 + (i % cols) * (sz + 3), 2 + math.floor(i / cols) * (sz + 3)
        local empty = i % 5 == 4
        local edge = empty and C.line2 or (edgeColor == "quality" and QUALITY[i % #QUALITY + 1])
            or (edgeColor == "accent" and C.slot) or C.black
        c:Rect(x, y, sz, sz, edge)
        local e = empty and 1 or edgeSize
        c:Rect(x + e, y + e, sz - 2 * e, sz - 2 * e, empty and rgb("0D0A07") or rgb("4A3C26"), 1, nil, 1)
    end
    c:Text(0, 88, (L["BAGS_LAYOUT_" .. layout:upper()] or "") .. " — " .. (L["BAGS_ORDER_" .. (lk.order or "kind"):upper()] or ""),
        12, C.grey, c.w)
end

-- The DualSense light bar's colour, out of a fight and in one
function P.Light(c)
    local m = CK.db.settings.touch and CK.db.settings.touch.light or "off"
    local function bar(x, color, caption)
        c:Rect(x, 22, 88, 10, rgb("2A2620"))
        c:Rect(x + 2, 24, 84, 6, color, 1, nil, 1)
        c:Text(x, 40, caption, 12, C.grey, 88, "CENTER")
    end
    if m == "class" then
        local _, class = UnitClass("player")
        local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        bar(c.w / 2 - 44, cc and { cc.r, cc.g, cc.b } or rgb("C69B6D"), L.PREVIEW_LIGHT_CLASS)
    elseif m == "combat" then
        bar(6, rgb("3A3328"), L.PREVIEW_LIGHT_PEACE)
        bar(c.w - 94, rgb("FF2A1A"), L.PREVIEW_LIGHT_FIGHT)
    else
        bar(c.w / 2 - 44, rgb("D02020"), L.PREVIEW_LIGHT_GAME)
    end
end

---------------------------------------------------------------------------
-- The lists picker: in place of the detail panel, the same width. A kicker
-- and a title, its lists' tabs (LB / RB), then the entries with their
-- sections. def = { kicker, title, lists = { { label, entries = function()
-- return { { header } or { action, name, icon, sub } } end } }, onChoose =
-- function(entry), onBack = function(), marked = function(entry) (a cyan
-- diamond: already there), rows = 10, text = "..." (a notice under the
-- title, the entries below it) }
---------------------------------------------------------------------------
local PICK_ROW, PICK_HEAD = 32, 28

function K.Picker(parent, width)
    local p = CK.NewFrame("Frame", nil, parent)
    p:SetWidth(width)
    p:EnableMouseWheel(true)
    p.box = K.Box(p, 4, 1, "BACKGROUND", 1)
    p.box:SetPoints(p)
    p.box:SetColors(C.black, 0.72, C.line1, 1)
    p.kicker = K.ChatText(p, 12, C.grey)
    p.kicker:SetPoint("TOPLEFT", 12, -12)
    p.kicker:SetWidth(width - 24)
    p.title = K.Text(p, 17, C.title)
    p.title:SetPoint("TOPLEFT", p.kicker, "BOTTOMLEFT", 0, -3)
    p.title:SetWidth(width - 24)
    p.text = K.Text(p, 14, C.cream)
    p.text:SetWidth(width - 24)
    p.text:SetJustifyH("LEFT")
    p.text:SetWordWrap(true)
    p.text:Hide()
    p.tabs = {}
    p.rows = {}
    p:SetScript("OnMouseWheel", function(self, delta) self:Move(-delta * 3) end)
    p:Hide()

    -- Fork CoolerMgdn: search. A field under the lists' tabs (R3, or a
    -- click: the panel's text field, typed with the addon's keyboard); the
    -- list keeps the entries whose name has it, with their section titles
    p.search = CK.NewFrame("Button", nil, p)
    p.search:SetSize(width - 24, 26)
    p.search.box = K.Box(p.search, 4, 1, "ARTWORK")
    p.search.box:SetPoints(p.search)
    p.search.glyph = K.Glyph(p.search, 22)
    p.search.glyph:SetPoint("LEFT", 4, 0)
    p.search.text = K.ChatText(p.search, 14, C.eventOff)
    p.search.text:SetPoint("LEFT", 32, 0)
    p.search.text:SetPoint("RIGHT", -8, 0)
    p.search.text:SetWordWrap(false)
    p.search:SetScript("OnClick", function() p:AskSearch() end)

    function p:AskSearch()
        if not self.def then return end
        CK.Config:AskText({ kicker = L.V_SEARCH, title = L.SEARCH_FIELD, text = self.query or "", help = L.SEARCH_HELP,
            maxLetters = 30, onDone = function(text) self:SetQuery(text) end })
    end

    function p:SetQuery(text)
        text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        self.query = text ~= "" and text or nil
        if self.def then self:LoadList() end
        CK.Config:Render()
    end

    -- The list's entries the search keeps (case and Cyrillic letters folded)
    local function lower(s) return K.Upper(tostring(s or "")) end
    function p:Filtered(entries)
        if not self.query then return entries end
        local q, out, head = lower(self.query), {}, nil
        for _, e in ipairs(entries) do
            if e.header then
                head = e
            elseif lower(e.name):find(q, 1, true) then
                if head then
                    out[#out + 1] = head
                    head = nil
                end
                out[#out + 1] = e
            end
        end
        return out
    end

    local function tab(i)
        local t = p.tabs[i]
        if t then return t end
        t = CK.UIKit.buildButton(p, "", function() p:SetList(i) end)
        t.label:SetFont(CK:GetFontPath(), K.FS(13, p), "")
        t:SetHeight(28)
        p.tabs[i] = t
        return t
    end

    local function row(i)
        local r = p.rows[i]
        if r then return r end
        r = CK.NewFrame("Button", nil, p)
        r:SetSize(width - 24, PICK_ROW)
        r.sel = CK.UIKit.nineSlice(r, "ck_select", 128, 32, 10, 10, "ARTWORK")
        r.iconRing = K.Solid(r, C.control, 1, "ARTWORK", 1)
        r.icon = K.RoundIcon(r, 24, "ARTWORK")
        r.icon:SetDrawLayer("ARTWORK", 2)
        r.icon:SetPoint("LEFT", 6, 0)
        r.mark = r:CreateTexture(nil, "OVERLAY")
        r.mark:SetTexture(TEX .. "ck_diamond")
        r.mark:SetSize(8, 8)
        r.mark:SetVertexColor(C.yours[1], C.yours[2], C.yours[3])
        r.mark:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMLEFT", -3, -1)
        r.iconRing:Hide()
        r.label = K.Text(r, 15, C.cream)
        r.label:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.label:SetPoint("RIGHT", -6, 0)
        r.head = K.Text(r, 14, C.title)
        r.head:SetPoint("BOTTOMLEFT", 4, 3)
        r:SetScript("OnClick", function(self)
            if self.index then
                p.index = self.index
                p:Choose()
                CK.Config:Render()
            end
        end)
        r:SetScript("OnEnter", function(self)
            if self.index and p.index ~= self.index then
                p.index = self.index
                p:Render()
            end
        end)
        p.rows[i] = r
        return r
    end

    function p:Open(def)
        self.def = def
        self.query = nil
        self.list = def.list or 1
        self:LoadList()
        self:Show()
    end

    function p:Close()
        self.def = nil
        self:Hide()
    end

    function p:IsOpen() return self.def ~= nil end

    function p:LoadList()
        local list = self.def.lists[self.list]
        self.entries = self:Filtered(list and list.entries() or {})
        self.offset, self.index = 0, nil
        local current = self.def.current
        for i, e in ipairs(self.entries) do
            if not e.header and (not self.index or e.action == current) then
                self.index = i
                if e.action == current then break end
            end
        end
        self:Move(0)
    end

    function p:SetList(i)
        local n = #self.def.lists
        self.list = (i - 1) % n + 1
        self:LoadList()
    end

    -- More than 5 lists: their tabs on two rows (6 in one row were too
    -- narrow to read), one entry less below them
    local TAB_ROW = 32
    function p:TabRows()
        local n = self.def and #self.def.lists or 0
        return n > 5 and 2 or 1
    end

    function p:Rows()
        -- (one less for the search field)
        return (self.def and self.def.rows or 10) - (self:TabRows() - 1) - 1
    end

    -- Keep the entry (and the section title above it) in the window, with
    -- one entry of context at the edges
    function p:Move(delta)
        local entries, i = self.entries or {}, self.index
        if not i then return self:Render() end
        local step = delta < 0 and -1 or 1
        for _ = 1, math.abs(delta) do
            local j = i + step
            while entries[j] and entries[j].header do j = j + step end
            if entries[j] then i = j end
        end
        self.index = i
        local max = self:Rows()
        if i - 1 <= self.offset then self.offset = math.max(0, i - 2) end
        if self.offset > 0 and entries[self.offset] and entries[self.offset].header then
            self.offset = self.offset - 1
        end
        if i + 1 > self.offset + max then self.offset = math.min(#entries - max, i + 1 - max) end
        self.offset = math.max(0, self.offset)
        self:Render()
    end

    -- The previous / next section
    function p:Jump(step)
        local entries, headers = self.entries or {}, {}
        for i, e in ipairs(entries) do
            if e.header then headers[#headers + 1] = i end
        end
        if #headers < 2 then return self:Move(step * (self:Rows())) end
        local current = 0
        for n, h in ipairs(headers) do
            if h < (self.index or 0) then current = n end
        end
        local target = headers[current + step]
        if not target then return end
        self.index = target
        self:Move(1)
    end

    function p:Choose()
        local e = self.def and self.index and self.entries[self.index]
        if e and not e.header and self.def.onChoose then self.def.onChoose(e) end
    end

    function p:Press(name)
        if name == "UP" or name == "DOWN" then
            self:Move(name == "UP" and -1 or 1)
        elseif name == "LEFT" or name == "RIGHT" then
            self:Jump(name == "LEFT" and -1 or 1)
        elseif name == "LB" or name == "RB" then
            if #self.def.lists > 1 then self:SetList(self.list + (name == "LB" and -1 or 1)) end
        elseif name == "A" then
            self:Choose()
        elseif name == "R3" then
            self:AskSearch()
        elseif name == "X" then
            if self.query then self:SetQuery(nil) end
        elseif name == "B" then
            -- A search on: the whole list back first
            if self.query then
                self:SetQuery(nil)
            elseif self.def.onBack then
                self.def.onBack()
            end
        end
        return true
    end

    function p:Hints()
        local hints = { K.H({ "DPAD" }, L.V_MOVE), K.H({ "A" }, self.def.chooseVerb or L.V_CHOOSE, "A"),
            K.H({ "RS" }, L.V_SEARCH, "R3") }
        if self.query then hints[#hints + 1] = K.H({ "X" }, L.V_CLEAR, "X") end
        if #self.def.lists > 1 then hints[#hints + 1] = K.H({ "LB", "RB" }, L.V_LIST, "RB") end
        hints[#hints + 1] = K.H({ "B" }, L.V_BACK, "B")
        return hints
    end

    function p:Render()
        local def = self.def
        if not def then return end
        local kicker, title = def.kicker, def.title
        if type(kicker) == "function" then kicker = kicker() end
        if type(title) == "function" then title = title() end
        self.kicker:SetText(K.Upper(kicker or ""))
        self.title:SetText(title or "")
        -- The lists' tabs share the width (of a row)
        local n = #def.lists
        local tabRows = self:TabRows()
        local perRow = math.ceil(n / tabRows)
        local tw = (width - 24 - (perRow - 1) * 4) / perRow
        for i = 1, math.max(n, #self.tabs) do
            local t = tab(i)
            t:SetShown(n > 1 and i <= n)
            if i <= n then
                local col, line = (i - 1) % perRow, math.floor((i - 1) / perRow)
                t:SetWidth(tw)
                -- A long name is cut, never over its neighbour
                t.label:SetWidth(tw - 6)
                t.label:SetWordWrap(false)
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", self, "TOPLEFT", 12 + col * (tw + 4), -54 - line * TAB_ROW)
                t.label:SetText(def.lists[i].label)
                t:SetActive(i == self.list)
            end
        end
        local top = n > 1 and (-88 - (tabRows - 1) * TAB_ROW) or -54
        local text = def.text
        if type(text) == "function" then text = text() end
        self.text:SetShown(text ~= nil)
        if text then
            self.text:ClearAllPoints()
            self.text:SetPoint("TOPLEFT", self, "TOPLEFT", 12, top)
            self.text:SetText(text)
            top = top - self.text:GetStringHeight() - 12
        end
        -- The search field
        local s = self.search
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", self, "TOPLEFT", 12, top)
        s.box:SetColors(C.boxBg, 1, self.query and C.slot or C.control, 1)
        s.glyph:Set("RS")
        s.text:SetText(self.query or L.SEARCH_FIELD)
        s.text:SetTextColor(unpack(self.query and C.focusText or C.eventOff))
        top = top - 32
        local max = self:Rows()
        local y = top
        local shown = 0
        for i = 1, max + 1 do
            local e = self.entries[self.offset + i]
            local r = row(i)
            r.index = nil
            if e and shown < max then
                shown = shown + 1
                local h = e.header and PICK_HEAD or PICK_ROW
                r:SetHeight(h)
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", self, "TOPLEFT", 12, y)
                y = y - h
                r.head:SetShown(e.header ~= nil)
                r.label:SetShown(not e.header)
                r.icon:SetShown(not e.header)
                r.mark:SetShown(not e.header and def.marked and def.marked(e) or false)
                r.sel:SetShown(not e.header and self.offset + i == self.index)
                if e.header then
                    r.head:SetText(e.header)
                else
                    r.index = self.offset + i
                    CK.Paddles.SetIcon(r.icon, e.icon or 134400)
                    r.label:SetText(e.name .. (e.sub and ("  |cff9d9a8c" .. e.sub .. "|r") or ""))
                end
                r:Show()
            else
                r:Hide()
            end
        end
        for i = max + 2, #self.rows do self.rows[i]:Hide() end
        if #self.entries == 0 then
            local r = row(1)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", self, "TOPLEFT", 12, top)
            r:Show()
            r.head:Show()
            r.head:SetText(self.query and L.SEARCH_NONE or L.MAP_NOTHING)
            r.label:Hide()
            r.icon:Hide()
            r.mark:Hide()
            r.sel:SetShown(false)
        end
    end
    return p
end

-- A help bar hint: { keys, verb, press (the key a click presses) }
function K.H(keys, verb, press)
    return { keys = keys, verb = verb, press = press or keys[1] }
end

---------------------------------------------------------------------------
-- A button of the ck_btn textures. States: active (the focus, the open
-- tab), armed (a destructive one asking again: red), disabled (faded); the
-- mouse lights it up
---------------------------------------------------------------------------
function K.Button(parent, size)
    -- Fork CoolerMgdn: in the game's look, its own red button (its textures,
    -- its light under the mouse; ours lit while it is the focus or the tab)
    local blizzard = K.Blizzard() and K.InConfig(parent)
    local b
    if blizzard then
        local ok, made = pcall(CK.NewFrame, "Button", nil, parent, "UIPanelButtonTemplate")
        if ok and made then
            b = made
            if b.Text then b.Text:SetText("") end
            b:SetText("")
            b.blizzard = true
        end
    end
    b = b or CK.NewFrame("Button", nil, parent)
    b.slice = CK.UIKit.nineSlice(b, "ck_btn_normal", 128, 32, 6, 6, "ARTWORK")
    if b.blizzard then
        -- Lit: the game's own glow over it
        b.lit = b:CreateTexture(nil, "ARTWORK", nil, 1)
        b.lit:SetTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
        b.lit:SetTexCoord(0, 0.625, 0, 0.6875)
        b.lit:SetBlendMode("ADD")
        b.lit:SetAllPoints()
        b.lit:Hide()
    end
    b.armedBox = K.Box(b, 4, 2, "ARTWORK", 2)
    b.armedBox:SetPoints(b)
    b.armedBox:SetColors(C.dangerBg, 1, C.danger, 1)
    b.armedBox:SetShown(false)
    b.label = K.Text(b, size or 15, C.tab)
    b.label:SetPoint("LEFT", 6, 0)
    b.label:SetPoint("RIGHT", -6, 0)
    b.label:SetJustifyH("CENTER")
    b.state = {}
    function b:SetState(state)
        self.state = state or {}
        self:Render()
    end
    function b:Render()
        local st = self.state
        self.armedBox:SetShown(st.armed and true or false)
        self.slice:SetShown(not st.armed)
        if self.blizzard then
            -- The game's button under it; ours never drawn
            self.slice:SetShown(false)
            local on = st.active or st.focus
            if self.lit then self.lit:SetShown(on and not st.armed and true or false) end
            if st.armed then
                self.label:SetTextColor(unpack(C.dangerText))
            else
                -- The game's colours: gold, white when lit
                self.label:SetTextColor(unpack(st.disabled and C.disabled or (on and C.white or C.gameGold)))
            end
        elseif st.armed then
            self.label:SetTextColor(unpack(C.dangerText))
        else
            local on = st.active or st.focus
            self.slice:SetFile(on and "ck_btn_active" or (self.hover and not st.disabled and "ck_btn_hover" or "ck_btn_normal"))
            self.label:SetTextColor(unpack(st.disabled and C.disabled or (on and C.focus or C.tab)))
        end
        self:SetAlpha(st.disabled and 0.45 or 1)
    end
    b:SetScript("OnEnter", function(self)
        self.hover = true
        self:Render()
    end)
    b:SetScript("OnLeave", function(self)
        self.hover = false
        self:Render()
    end)
    b:Render()
    return b
end

-- Buttons side by side in a row frame, each sized by its share ("flex") of
-- the row's width, with a gap between them
function K.LayoutRow(row, buttons, flexes, gap)
    local total = 0
    for i = 1, #buttons do total = total + (flexes[i] or 1) end
    local room, x = row:GetWidth() - gap * (#buttons - 1), 0
    for i, b in ipairs(buttons) do
        local w = room * (flexes[i] or 1) / total
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
        b:SetSize(w, row:GetHeight())
        x = x + w + gap
    end
end

---------------------------------------------------------------------------
-- A round slot (ck_slot): the Gamepad screen's buttons (44, icon 32), the
-- wheel editor's slots (52, icon 38). An icon cut round on its dark disc,
-- a "+", stripes (unavailable), a coloured ring (a slot of the game's bar,
-- yours), a cyan diamond (yours), the focus glow, the target's dashed ring.
---------------------------------------------------------------------------
function K.Slot(parent, size, iconSize, square)
    -- Square (the D-pad's, like the game's gamepad bar) or round
    local sq = square and "_sq" or ""
    local s = CK.NewFrame("Button", nil, parent)
    s:SetSize(size, size)
    s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    s.bg = s:CreateTexture(nil, "BACKGROUND")
    s.bg:SetTexture(TEX .. "ck_slot" .. sq)
    s.bg:SetAllPoints()
    s.disc = s:CreateTexture(nil, "ARTWORK", nil, 0)
    s.disc:SetTexture(TEX .. (square and "ck_sqr" or "ck_dot"))
    s.disc:SetSize(iconSize, iconSize)
    s.disc:SetPoint("CENTER")
    s.icon = (square and K.SquareIcon or K.RoundIcon)(s, iconSize, "ARTWORK")
    s.icon:SetDrawLayer("ARTWORK", 1)
    s.icon:SetPoint("CENTER")
    s.hatch = s:CreateTexture(nil, "ARTWORK", nil, 2)
    s.hatch:SetTexture(TEX .. "ck_hatch" .. sq)
    s.hatch:SetSize(iconSize, iconSize)
    s.hatch:SetPoint("CENTER")
    s.plus = K.Text(s, size >= 52 and 20 or 18, C.dimGold, "OVERLAY")
    s.plus:SetPoint("CENTER", 0, 1)
    s.plus:SetJustifyH("CENTER")
    s.plus:SetText("+")
    -- The ring: its outer edge on the slot's (a slot of the game's bar), or
    -- 1 px out (yours)
    s.ring = s:CreateTexture(nil, "OVERLAY", nil, 0)
    s.ring:SetTexture(TEX .. "ck_ring" .. sq)
    s.ring:SetPoint("CENTER")
    s.ring:SetSize(size, size)
    -- Yours: a cyan diamond with a dark edge, bottom left
    s.markEdge = s:CreateTexture(nil, "OVERLAY", nil, 1)
    s.markEdge:SetTexture(TEX .. "ck_diamond")
    s.markEdge:SetVertexColor(C.boxBg[1], C.boxBg[2], C.boxBg[3])
    s.markEdge:SetSize(16, 16)
    s.markEdge:SetPoint("CENTER", s, "BOTTOMLEFT", 2.5, 5.5)
    s.mark = s:CreateTexture(nil, "OVERLAY", nil, 2)
    s.mark:SetTexture(TEX .. "ck_diamond")
    s.mark:SetVertexColor(C.yours[1], C.yours[2], C.yours[3])
    s.mark:SetSize(13, 13)
    s.mark:SetPoint("CENTER", s.markEdge, "CENTER")
    s.glow = s:CreateTexture(nil, "OVERLAY", nil, 3)
    s.glow:SetTexture(TEX .. "ck_slot_glow" .. sq)
    s.glow:SetBlendMode("ADD")
    s.glow:SetSize(math.floor(size * 1.46 + 0.5), math.floor(size * 1.46 + 0.5))
    s.glow:SetPoint("CENTER")
    s.dash = s:CreateTexture(nil, "OVERLAY", nil, 4)
    s.dash:SetTexture(TEX .. "ck_ring_dash")
    s.dash:SetVertexColor(C.focus[1], C.focus[2], C.focus[3])
    s.dash:SetSize(size + 10, size + 10)
    s.dash:SetPoint("CENTER")
    s.dash:Hide()
    s.size = size
    -- look = { icon, desaturate, discColor, plus, hatch, ring = color, ringOut, mark, glow, dash }
    function s:SetLook(look)
        local icon = look.icon
        CK.Paddles.SetIcon(self.icon, icon)
        self.icon:SetShown(icon ~= nil)
        self.icon:SetDesaturated(look.desaturate and true or false)
        local dc = look.discColor
        self.disc:SetShown(dc ~= nil)
        if dc then self.disc:SetVertexColor(dc[1], dc[2], dc[3]) end
        self.plus:SetShown(look.plus and true or false)
        self.hatch:SetShown(look.hatch and true or false)
        self.ring:SetShown(look.ring ~= nil)
        if look.ring then
            self.ring:SetVertexColor(look.ring[1], look.ring[2], look.ring[3])
            local r = look.ringOut and self.size + 2 or self.size
            self.ring:SetSize(r, r)
        end
        self.mark:SetShown(look.mark and true or false)
        self.markEdge:SetShown(look.mark and true or false)
        self.glow:SetShown(look.glow and true or false)
        self.dash:SetShown(look.dash and true or false)
    end
    return s
end

-- A layer and an input: glyph keys for a GlyphRow ("RT", "+", "A"), or a
-- text with the glyphs in it
function K.ComboKeys(inputId, layer)
    local keys = {}
    for _, trigger in ipairs({ "LT", "RT" }) do
        if layer:find(trigger, 1, true) then
            keys[#keys + 1] = trigger
            keys[#keys + 1] = "+"
        end
    end
    keys[#keys + 1] = inputId
    return keys
end

function K.ComboMarkup(inputId, layer, size)
    local parts = {}
    for _, key in ipairs(K.ComboKeys(inputId, layer)) do
        if key ~= "+" then
            local glyph = K.INPUT_GLYPH[key] or key
            parts[#parts + 1] = IMAGE[glyph] and CK:GlyphMarkup(glyph, size) or K.ChipText(key)
        end
    end
    return table.concat(parts, " + ")
end
