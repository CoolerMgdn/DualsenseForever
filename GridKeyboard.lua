local _, CK = ...
local L = CK.L

---------------------------------------------------------------------------
-- Fork CoolerMgdn: input method "grid" (asked: the PS5 on-screen keyboard
-- the player is used to). Keys in rows, one of them highlighted: the D-pad
-- or the left stick moves it, A (cross) types it. As on the PS5: square
-- erases, triangle is a space, L2 shift (twice quickly: caps lock), R3 the
-- next layer (the layout's letters, the other alphabet, the symbols), R2
-- sends, L1 / R1 move the cursor in the text (the channels: down from the
-- bottom row). Under the keys no keys but what the pad's
-- buttons do, each with its glyph (as on the PS5; no help band). Up from the
-- top row: the suggestions; down from the bottom row: the channels (the
-- Quests chip). The PS5's gyro typing (L3 + R3) is left out (asked).
---------------------------------------------------------------------------
CK.Methods = CK.Methods or {}
local COLS, PITCH, KEY_H, ROW_PITCH = 12, 48, 40, 44
local AREA_W = COLS * PITCH - 4
local HINT_Y, HINT_H = 4 * ROW_PITCH, 30
local M = {
    key = "grid", width = 600, areaWidth = AREA_W, height = 4 * ROW_PITCH + HINT_H,
    -- Input.lua / UI.lua: R2 sends (A types), the D-pad is ours, no mouse
    -- row (its keys are the hints, clickable) and no help band
    enterKey = "PADRTRIGGER", ownDpad = true, noMouseRow = true, noHelp = true,
}
CK.Methods.grid = M

M.buttons = {
    PADDUP = "GridUp",
    PADDDOWN = "GridDown",
    PADDLEFT = "GridLeft",
    PADDRIGHT = "GridRight",
    PAD1 = "GridPress",
    PAD3 = "Backspace",
    PAD4 = "Space",
    PADLTRIGGER = "ToggleShift",
    PADRSTICK = "GridNextLayer",
    PADLSHOULDER = "CaretLeft",
    PADRSHOULDER = "CaretRight",
}

function M:Help() return {} end

---------------------------------------------------------------------------
-- Layouts: 4 rows of 12 characters. A row is a string, cut in UTF-8
-- characters.
---------------------------------------------------------------------------
local ROWS = {
    qwerty    = { "1234567890@#", "qwertyuiop-/", "asdfghjkl'\":", "zxcvbnm,.?!_" },
    azerty    = { "1234567890@#", "azertyuiop-/", "qsdfghjklm'\"", "wxcvbn,.?!:_" },
    qwertz    = { "1234567890@#", "qwertzuiopü/", "asdfghjklöä'", "yxcvbnmß,.?!" },
    qwerty_es = { "1234567890@#", "qwertyuiop-/", "asdfghjklñ'\"", "zxcvbnm,.?!¿" },
    qwerty_it = { "1234567890@#", "qwertyuiopè/", "asdfghjklò'à", "zxcvbnm,.?!ù" },
    jcuken    = { "1234567890-?", "йцукенгшщзхъ", "фывапролджэё", "ячсмитьбю.,!" },
    -- Row 3: the language's 12 accents (CK:Accents()); no "|" (the chat's escape)
    symbols   = { "!?@#$%&*()-+", "=/\\:;\"'<>[]_", false, "~^{}€£°§«»…¿" },
    -- Fork CoolerMgdn (asked): a field for numbers (gold, silver, copper,
    -- an amount): a number pad, nothing else ("_": no key there)
    digits    = { "____789_____", "____456_____", "____123_____", "_____0______" },
}
-- What R3 shows it goes to
local LAYER_NAME = { jcuken = "АБВ", symbols = "@#:" }

local function chars(s)
    local t = {}
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do t[#t + 1] = ch end
    return t
end

-- Under the keys: glyph + action, clickable with the mouse (R2's carries the
-- secure Send button)
local HINTS = {
    { k = "CARET", glyph = "LB", glyph2 = "RB" },
    { k = "SHIFT", glyph = "LT" }, { k = "LAYER", glyph = "RS" }, { k = "SPACE", glyph = "Y" },
    { k = "BACK", glyph = "X" }, { k = "SEND", glyph = "RT" },
}

local COLOR = {
    char = { 1, 0.82, 0 }, special = { 0.85, 0.79, 0.63 }, lit = { 1, 0.94, 0.78 },
    hover = { 1, 0.96, 0.85 }, pressed = { 0, 0, 0 },
}
local PRESSED_TIME = 0.12
-- Left stick: a push past STICK_ON moves once, held it repeats
local STICK_ON, STICK_OFF, STICK_DELAY, STICK_RATE = 0.55, 0.35, 0.38, 0.09

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
local function buildKey(parent, x, y, w)
    local K = CK.UIKit
    local b = CK.NewFrame("Button", nil, parent)
    K.place(b, parent, x, y, w, KEY_H)
    b.base = K.nineSlice(b, "ck_sk_key_normal", 128, 64, 12, 12, "BORDER")
    b.file = "ck_sk_key_normal"
    b.cx, b.w = x + w / 2, w
    b.label = K.text(b, 18)
    b.label:SetPoint("CENTER", 0, 1)
    b:SetScript("OnClick", function() M:Flash(b); M:PressKey(b) end)
    b:SetScript("OnEnter", function() M.hover = b; M:Update() end)
    b:SetScript("OnLeave", function() M.hover = nil; M:Update() end)
    return b
end

function M:Build(area)
    local K = CK.UIKit
    self.sets = {}
    for name, rows in pairs(ROWS) do
        local set = CK.NewFrame("Frame", nil, area)
        set:SetAllPoints()
        set.rows = {}
        for r = 1, 4 do
            local row = {}
            local list = rows[r] and chars(rows[r])
            for c = 1, COLS do
                local key = buildKey(set, (c - 1) * PITCH, (r - 1) * ROW_PITCH, PITCH - 4)
                if list then key.char = list[c] else key.acc = c end
                if name == "digits" and key.char == "_" then key.char, key.none = nil, true end
                row[c] = key
            end
            set.rows[r] = row
        end
        set:Hide()
        self.sets[name] = set
    end

    -- The hints: five equal slots, glyph then label, centred in each
    self.hints = {}
    local slot = AREA_W / #HINTS
    for i, def in ipairs(HINTS) do
        local h = CK.NewFrame("Button", nil, area)
        K.place(h, area, (i - 1) * slot, HINT_Y + 2, slot, HINT_H - 4)
        h.k = def.k
        h.glyphKey = def.glyph
        h.glyph = h:CreateTexture(nil, "ARTWORK")
        h.glyph:SetSize(20, 20)
        local last = h.glyph
        if def.glyph2 then
            h.glyphKey2 = def.glyph2
            h.glyph2 = h:CreateTexture(nil, "ARTWORK")
            h.glyph2:SetSize(20, 20)
            h.glyph2:SetPoint("LEFT", h.glyph, "RIGHT", 1, 0)
            last = h.glyph2
        end
        h.label = K.text(h, 13)
        h.label:SetPoint("LEFT", last, "RIGHT", 4, 0)
        h:SetScript("OnClick", function()
            if def.k == "CARET" then CK:CaretRight()
            elseif def.k == "SHIFT" then CK:ToggleShift()
            elseif def.k == "LAYER" then CK:GridNextLayer()
            elseif def.k == "SPACE" then CK:Space()
            elseif def.k == "BACK" then CK:Backspace() end
        end)
        h:SetScript("OnEnter", function() M.hover = h; M:Update() end)
        h:SetScript("OnLeave", function() M.hover = nil; M:Update() end)
        self.hints[i] = h
    end
    self:UpdateGlyphs()

    -- Repeats of a held left stick
    self.ticker = CK.NewFrame("Frame", nil, area)
    self.ticker:Hide()
    self.ticker:SetScript("OnUpdate", function()
        local now = GetTime()
        if M.stickDir and now >= M.stickAt then
            M.stickAt = now + STICK_RATE
            M:Move(M.stickDir)
        end
    end)
    self:Reset()
end

function M:UpdateGlyphs()
    for _, h in ipairs(self.hints or {}) do
        CK:SetGlyph(h.glyph, h.glyphKey)
        if h.glyph2 then CK:SetGlyph(h.glyph2, h.glyphKey2) end
    end
end

---------------------------------------------------------------------------
-- Layers: the layout's letters, the other alphabet (ЙЦУКЕН <-> QWERTY),
-- the symbols (CK.state.layer, shared with the other methods)
---------------------------------------------------------------------------
local function mainLayout()
    local k = CK.db.settings.kbLayout
    return ROWS[k] and k or "qwerty"
end

local function otherLayout()
    return mainLayout() == "jcuken" and "qwerty" or "jcuken"
end

function M:LayerName()
    if CK.fieldNumeric then return "digits" end
    if CK.state.layer == "symbols" then return "symbols" end
    return self.alt and otherLayout() or mainLayout()
end

function M:ActiveSet()
    return self.sets[self:LayerName()]
end

-- R3: letters -> other alphabet -> symbols -> letters
function CK:GridNextLayer()
    if self:GetMethod() ~= M or self.fieldNumeric then return end
    if self.state.layer == "symbols" then
        M.alt = false
        self:ToggleSymbols()
    elseif not M.alt then
        M.alt = true
        self:UpdateMethod()
    else
        M.alt = false
        self:ToggleSymbols()
    end
end

local function nextLayerName()
    if CK.state.layer == "symbols" then return mainLayout() end
    if not M.alt then return otherLayout() end
    return "symbols"
end

function M:Current()
    local set = self.sets and self:ActiveSet()
    local row = set and set.rows[self.row]
    return row and row[self.col]
end

-- The number pad's gaps: the highlight on the nearest key of its row
function M:Fix()
    local set = self.sets and self:ActiveSet()
    local row = set and set.rows[self.row]
    if not (row and row[self.col] and row[self.col].none) then return end
    for d = 1, COLS do
        for _, c in ipairs({ self.col - d, self.col + d }) do
            if row[c] and not row[c].none then
                self.col = c
                return
            end
        end
    end
end

function M:Reset()
    self.zone, self.row, self.col, self.wantX = "keys", 2, 1, PITCH / 2
    self.alt, self.stickDir = false, nil
    if self.ticker then self.ticker:Hide() end
end

---------------------------------------------------------------------------
-- Moving the highlight
---------------------------------------------------------------------------
local function hasSuggestions()
    local n = #(CK.state.suggestions or {})
    return n > 0 or (CK.PhrasesChipShown and CK:PhrasesChipShown()) or (CK.InQuestList and CK:InQuestList())
end

function M:Move(dir)
    if not self.sets then return end
    if self.zone == "sugg" then
        if dir == "down" then self.zone = "keys"
        elseif dir == "left" then CK:NavPrev()
        elseif dir == "right" then CK:NavNext() end
    elseif self.zone == "chan" then
        if dir == "up" then
            self.zone = "keys"
            CK:SetActiveRow("suggestions")
        elseif dir == "left" then CK:PrevChannel()
        elseif dir == "right" then CK:NextChannel() end
    elseif dir == "left" or dir == "right" then
        local set = self:ActiveSet()
        for _ = 1, COLS do
            self.col = (self.col - 1 + (dir == "left" and -1 or 1)) % COLS + 1
            if not set.rows[self.row][self.col].none then break end
        end
    elseif dir == "up" then
        if self.row > 1 then
            self.row = self.row - 1
        elseif hasSuggestions() then
            self.zone = "sugg"
        end
    elseif dir == "down" then
        if self.row < 4 then
            self.row = self.row + 1
        elseif not CK.field then
            self.zone = "chan"
            CK:FocusChannels()
        end
    end
    self:Fix()
    self:Update()
    CK:UpdateRows()
end

function CK:GridUp() M:Move("up") end
function CK:GridDown() M:Move("down") end
function CK:GridLeft() M:Move("left") end
function CK:GridRight() M:Move("right") end

function M:OnLeftStick(x, y)
    local len = math.sqrt(x * x + y * y)
    local dir
    if len >= STICK_ON or (self.stickDir and len >= STICK_OFF) then
        if math.abs(x) > math.abs(y) then
            dir = x < 0 and "left" or "right"
        else
            dir = y > 0 and "up" or "down"
        end
    end
    if dir == self.stickDir then return end
    self.stickDir = dir
    if dir then
        self:Move(dir)
        self.stickAt = GetTime() + STICK_DELAY
        self.ticker:Show()
    else
        self.ticker:Hide()
    end
end

---------------------------------------------------------------------------
-- Typing
---------------------------------------------------------------------------
function M:PressKey(key)
    if key and key.char then CK:TypeChar(key.char) end
end

function M:Flash(key)
    if not key then return end
    local untilTime = GetTime() + PRESSED_TIME
    key.pressedUntil = untilTime
    self:Update()
    C_Timer.After(PRESSED_TIME, function()
        if key.pressedUntil == untilTime then key.pressedUntil = nil end
        if M.sets then M:Update() end
    end)
end

-- A: the highlighted key; on the suggestions, insert the one chosen; on the
-- channels, confirm (the Quests chip: its list) and come back to the keys
function CK:GridPress()
    if self:GetMethod() ~= M then return end
    if M.zone == "sugg" then
        self:AcceptSuggestion()
        if not self:InQuestList() then M.zone = "keys" end
    elseif M.zone == "chan" then
        self:RowSelect()
        M.zone = "keys"
    else
        local key = M:Current()
        M:Flash(key)
        M:PressKey(key)
    end
    M:Update()
    self:UpdateRows()
end

-- Input.lua (PositionSendButton): the secure Send button over R2's hint
-- (the last one)
function M:SendAnchor()
    return self.hints and self.hints[#self.hints]
end

function M:SendHover(on)
    self.hover = on and self:SendAnchor() or nil
    self:Update()
end

-- UI.lua (UpdateRows): the channels as for the other methods (D-pad down,
-- then left / right); the suggestions: D-pad up to reach them, then left /
-- right
function M:RowGlyphs(f)
    if CK.state.activeRow == "channels" then return end
    local inSugg = self.zone == "sugg"
    f.sbarSlice:SetVertexColor(1, 1, 1)
    for _, b in ipairs(f.sugg) do b:SetAlpha(1) end
    f.phrasesChip:SetAlpha(1)
    CK:SetGlyph(f.lbGlyph, inSugg and "DPAD_LEFT" or "DPAD_UP")
    CK:SetGlyph(f.rbGlyph, "DPAD_RIGHT")
    f.rbGlyph:SetShown(inSugg)
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------
local HINT_LABEL = { CARET = "GRID_CURSOR", SHIFT = "SHIFT", SPACE = "SPACE", BACK = "BACKSPACE", SEND = "GRID_HELP_SEND" }

function M:Update()
    if not self.sets then return end
    local state = CK.state
    self:Fix()
    local set = self:ActiveSet()
    for _, s in pairs(self.sets) do s:SetShown(s == set) end
    local current = self.zone == "keys" and set.rows[self.row][self.col] or nil
    local accents = CK:Accents()
    local now = GetTime()

    for _, keys in ipairs(set.rows) do
        for _, key in ipairs(keys) do
            local pressed = key.pressedUntil and now < key.pressedUntil
            local file = pressed and "ck_sk_key_pressed"
                or (key == current and "ck_sk_key_target_l")
                or (key == self.hover and "ck_sk_key_hover")
                or "ck_sk_key_normal"
            if file ~= key.file then
                key.base:SetFile(file)
                key.file = file
            end
            if key.acc then key.char = accents[key.acc] end
            key:SetShown(not key.none)
            key.label:SetText(key.char and CK:DisplayChar(key.char) or "")
            local color = pressed and COLOR.pressed or (key == current and COLOR.lit)
                or (key == self.hover and COLOR.hover) or COLOR.char
            key.label:SetTextColor(unpack(color))
            key.label:SetShadowColor(0, 0, 0, pressed and 0 or 1)
        end
    end

    local shiftOn = state.shift or state.caps
    for _, h in ipairs(self.hints) do
        if h.k == "LAYER" then
            local to = nextLayerName()
            h.label:SetText(LAYER_NAME[to] or "ABC")
        else
            h.label:SetText(L[HINT_LABEL[h.k]])
        end
        -- Centre glyph + label in the slot
        local w = (h.glyph2 and 49 or 24) + (h.label:GetStringWidth() or 0)
        h.glyph:ClearAllPoints()
        h.glyph:SetPoint("LEFT", h, "CENTER", -w / 2, 0)
        local lit = (h.k == "SHIFT" and shiftOn) or h == self.hover
        h.label:SetTextColor(unpack(lit and COLOR.lit or COLOR.special))
    end
end
