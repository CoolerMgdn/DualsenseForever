local _, CK = ...
local L = CK.L

-- Configuration, Gamepad tab (2.0, Claude Design handoff, "Écran Gamepad"):
-- the controller drawn over an Xbox controller's silhouette, each button
-- with what it does in the layer shown (alone, LT, RT, LT + RT), in five
-- states: the game's function, a slot of the game's gamepad bar, yours
-- (added, or replacing the game's), free, unavailable. A on a button opens
-- the lists picker on the right. Under the controller: identify the back
-- paddles, move the buttons, every replaced button given back to the game.
-- What shows next to the bar (W.DisplayRows) is set in Home > Gamepad.
local W = {}
CK.MapPage = W
CK.Config.pages.gamepad = W

local M, P, C = CK.Mapping, CK.Paddles, CK.Config
local K = CK.ConfigKit
local KC = K.C

local ZONE_W, PANEL_W, BODY_H = 480, 292, 424
local PAD_TOP, PAD_H = 40, 344
local SLOT, ICON, GLYPH = 44, 32, 20

-- Each button's centre on the silhouette, and the side of its glyph
local NODES = {
    { "LT", 40, 30 }, { "LB", 150, 30 }, { "RB", 320, 30 }, { "RT", 446, 30 },
    { "L3", 110, 100 }, { "SELECT", 206, 92 }, { "START", 274, 92 },
    { "Y", 380, 64 }, { "X", 328, 124 }, { "B", 432, 124 }, { "A", 380, 172 },
    { "UP", 182, 152 }, { "LEFT", 134, 200 }, { "RIGHT", 230, 200 }, { "DOWN", 182, 252 },
    { "R3", 312, 212 },
    { "L4", 34, 300 }, { "L5", 112, 300 }, { "R5", 376, 300 }, { "R4", 452, 300 },
    -- The touchpad buttons turned on: a row under the controller (drawn
    -- smaller then, see W:LayoutPad)
    { "TL1", 30, 385, true }, { "TL2", 86, 385, true }, { "TL3", 142, 385, true }, { "TL4", 198, 385, true },
    { "TR1", 282, 385, true }, { "TR2", 338, 385, true }, { "TR3", 394, 385, true }, { "TR4", 450, 385, true },
    -- Fork CoolerMgdn: a PlayStation pad's Create and mic (shown with its
    -- silhouette only, PS_NODES)
    { "CREATE", 240, 140 }, { "MIC", 240, 190 },
}
-- Fork CoolerMgdn: a DualSense drawn (ck_pad_ps, same size and style): the
-- D-pad and the face buttons up, the sticks side by side under them, the
-- touchpad in the middle (the game's Select: its corners, Touchpad tab),
-- Create and Options either side of it, the mic under it
-- (the D-pad and the face buttons as far apart as the Xbox drawing's, so
-- their names never meet)
local PS_NODES = {
    LT = { 40, 30 }, LB = { 150, 30 }, RB = { 330, 30 }, RT = { 440, 30 },
    SELECT = { 240, 72 }, CREATE = { 160, 104 }, START = { 320, 104 }, MIC = { 240, 184 },
    UP = { 78, 122 }, LEFT = { 32, 170 }, RIGHT = { 124, 170 }, DOWN = { 78, 218 },
    Y = { 402, 122 }, X = { 356, 170 }, B = { 448, 170 }, A = { 402, 218 },
    L3 = { 170, 236 }, R3 = { 310, 236 },
}
-- Their glyphs' side on the DualSense (else GLYPH_SIDE's)
local PS_GLYPH_SIDE = { L3 = "left", R3 = "right" }
for _, n in ipairs(NODES) do n.home = { n[2], n[3] } end
local TOUCH_SCALE = 0.8
-- The D-pad's four sit on the drawn cross: no glyph of their own; square,
-- like the game's gamepad bar draws them
local NO_GLYPH = { UP = true, DOWN = true, LEFT = true, RIGHT = true }
local SQUARE = NO_GLYPH
-- Select and Start are close: narrower names
local LABEL_W = { SELECT = 64, START = 64, CREATE = 64, MIC = 76, TL1 = 54, TL2 = 54, TL3 = 54, TL4 = 54, TR1 = 54, TR2 = 54, TR3 = 54, TR4 = 54 }
local GLYPH_SIDE = {
    SELECT = "top", START = "top", CREATE = "top", MIC = "top", Y = "top", B = "top", L4 = "top", L5 = "top", R4 = "top", R5 = "top",
    TL1 = "top", TL2 = "top", TL3 = "top", TL4 = "top", TR1 = "top", TR2 = "top", TR3 = "top", TR4 = "top",
    -- Fork CoolerMgdn (asked): Square and Cross on top too, like Triangle and
    -- Circle (their right side is where a double press's badge goes)
    X = "top", A = "top", RIGHT = "right",
}
local POS = {}
for _, n in ipairs(NODES) do POS[n[1]] = n end

local LAYER_KEYS = { [""] = {}, LT = { "LT" }, RT = { "RT" }, LTRT = { "LT", "+", "RT" } }
local SLOT_KINDS = { spell = true, item = true, macro = true }

local function settings() return CK.db.settings end

local function keyText(key)
    return key and (GetBindingText and GetBindingText(key) or key) or ""
end

---------------------------------------------------------------------------
-- What a button is in a layer: { state = "native" | "slot" | "yours" |
-- "free" | "off", name, icon, empty, slot, action, replaced, rep, why }
---------------------------------------------------------------------------
-- Fork CoolerMgdn: the Hold view (the layers row's last button): what each
-- button runs when held, in the layer shown (Mapping.lua M:GetHold)
-- (and the Double view: what a button runs pressed twice, M:GetDouble;
-- self.hold is "hold" or "double" while one of them is shown)
function W:HoldCell(input, layer)
    local action, why, none
    if self.hold == "double" then
        action, why, none = M:GetDouble(input.id, layer), M:DoubleBlocked(input, layer), L.MAP_DBL_OFF
    else
        action, why, none = M:GetHold(input.id, layer), M:HoldBlocked(input, layer), L.MAP_HOLD_OFF
    end
    if why then
        return { state = "off", name = action and M:ActionName(action) or none, why = why,
            action = action, hold = true }
    end
    if action then
        return { state = "yours", name = M:ActionName(action), icon = M:ActionIcon(action), action = action, hold = true }
    end
    return { state = "free", name = L.MAP_FREE, hold = true }
end

function W:Cell(input, layer)
    if self.hold then return self:HoldCell(input, layer) end
    -- The triggers: their bars' (alone), held in their own layers
    if input.layer then
        if layer == "" then
            local name, icon = M:NativeInfo(input, layer)
            return { state = "native", name = name, icon = icon }
        end
        return { state = "off", name = L.LBL_HELD, why = L.MAP_KEPT_TRIGGER }
    end
    -- Fork CoolerMgdn: on a PlayStation pad Select is the touchpad's click,
    -- its corners set in the Touchpad tab
    if input.id == "SELECT" and M.PlayStation() and CK.Touchpad and CK.Touchpad.Blocked() == nil then
        return { state = "off", name = L.MAP_TOUCHPAD, icon = { atlas = "gamepad-ps-touchpad-normal" },
            why = L.MAP_KEPT_TOUCHPAD }
    end
    -- (The mic button turning the touchpad's mouse mode on: a long press
    -- now, its short press runs what is put here: Touchpad.lua)
    -- Start and Select: the game's system buttons, in every layer
    if M.SYSTEM[input.id] then
        local name, icon = M:NativeInfo(input, "")
        if layer ~= "" then name, icon = L.MAP_GAME, nil end
        return { state = "off", name = name or L.MAP_GAME, icon = icon, why = L.MAP_KEPT_SYSTEM }
    end
    -- LB / RB with a trigger: the game's class and pet actions (LT + LB,
    -- RT + RB, both triggers); LT + RB and RT + LB can be replaced
    if (input.id == "LB" or input.id == "RB") and layer ~= "" and layer ~= M.CROSSED[input.id] then
        return { state = "off", name = L.MAP_GAME, why = L.MAP_KEPT_CLASS }
    end
    local state = M:State(input, layer)
    -- A button of the game's, replaced
    local replaced = M:Replaceable(input, layer) and M:GetReplaced(input.id, layer)
    if replaced then
        local rep = M:NativeInfo(input, layer)
        local cell = { name = M:ActionName(replaced), icon = M:ActionIcon(replaced), action = replaced,
            replaced = true, rep = rep or L.MAP_GAME }
        if layer ~= "" and not input.paddle and M.IsBoundAction(replaced) then
            -- A game function with a trigger: never run (kept from before)
            cell.state, cell.why = "off", L.MAP_BOUND_LAYER
        elseif M:OwnKeys() then
            cell.state = "yours"
        else
            cell.state, cell.why = "off", L.MAP_REPLACED_INACTIVE
        end
        return cell
    end
    if state == "locked" then
        if input.paddle and not M:InputKey(input) then
            return { state = "off", name = L.LBL_NO_KEY, why = L.MAP_PADDLE_NO_KEY }
        end
        if input.paddle then
            -- A shared key a game function takes
            local base = M:SharedLayers(layer)[1]
            local shown = M:EffectiveAction(input, layer)
            return { state = "off", name = M:ActionName(shown) or L.MAP_GAME,
                why = format(L.MAP_SHARED_LOCKED, K.ComboMarkup(input.id, base, 14), M:ActionName(M:Get(input.id, base)) or "") }
        end
        -- A face / D-pad button given a game function alone: the same. L3 /
        -- R3: freed with Nothing alone, as when the game's (given back, the
        -- game's autorun or ping would hold the layers still)
        if M:CommandAlone(input) then
            local stick = not input.bar
            local kept = M:GetReplaced(input.id, layer) or (stick and M:Get(input.id, layer)) or nil
            local slotName, slotIcon = M:NativeInfo(input, layer)
            local alone = M:ActionName(M:GetReplaced(input.id, "") or M:Get(input.id, "")) or L.MAP_GAME
            return { state = "off", name = kept and M:ActionName(kept) or (not stick and slotName) or L.MAP_GAME,
                icon = kept and M:ActionIcon(kept) or (not stick and slotIcon) or nil, action = kept, pick = true,
                lockedAlone = stick and "held" or "command", why = format(L.MAP_STICK_HELD, input.id, alone, input.id) }
        end
        -- L3 / R3 alone still the game's: its layers wait for it to be freed
        if M:StickHeld(input) then
            local kept = M:Get(input.id, layer) or M:GetReplaced(input.id, layer)
            local native = M:NativeInfo(input, "") or L.MAP_GAME
            return { state = "off", name = kept and M:ActionName(kept) or L.MAP_GAME, icon = kept and M:ActionIcon(kept),
                action = kept, pick = true, lockedAlone = "held", why = format(L.MAP_STICK_HELD, input.id, native, input.id) }
        end
        return { state = "off", name = L.MAP_GAME, why = L.MAP_LOCKED }
    end
    if state == "slot" then
        local slot = M:NativeSlot(input, layer)
        local name, icon = M:NativeInfo(input, layer)
        local empty = not P.SlotTexture(slot)
        return { state = "slot", name = empty and L.LBL_EMPTY or name, icon = icon, empty = empty, slot = slot }
    end
    if state == "native" then
        local name, icon = M:NativeInfo(input, layer)
        return { state = "native", name = name or L.MAP_GAME, icon = icon }
    end
    -- Free: the player's own, if any
    local action = M:Get(input.id, layer)
    -- Fork CoolerMgdn: Create / the mic keep one saved among the replaced
    -- buttons too, run and shown on the HUD (Paddles.ShownAction); with no
    -- game function under it now the cell is free, so it showed "Free"
    -- (found: L2 + Create's marks wheel)
    local psReplaced
    if not action and input.ps then
        action = M:GetReplaced(input.id, layer)
        psReplaced = action ~= nil or nil
    end
    if not settings().modules.mapping then
        return { state = "off", name = action and M:ActionName(action) or L.MAP_FREE, why = L.MAP_MODULE_OFF, action = action }
    end
    -- A game function left on a layer sharing the paddle's key: a spell, an
    -- item or a macro can take its place
    if action and M:Inactive(input, layer) then
        return { state = "off", name = M:ActionName(action), why = L.MAP_SHARED_INACTIVE, action = action, pick = true }
    end
    if action then
        return { state = "yours", name = M:ActionName(action), icon = M:ActionIcon(action), action = action,
            psReplaced = psReplaced }
    end
    return { state = "free", name = L.MAP_FREE }
end

-- The layer on screen: the triggers held, else the one picked
function W:ViewLayer()
    return self.heldLayer ~= "" and self.heldLayer or self.layer or ""
end

function W:Focused()
    return M.BY_ID[self.node]
end

-- With touchpad buttons on, the controller is drawn smaller and their row
-- fits under it
function W:LayoutPad()
    local area, touch = self.frame.area, M:AnyTouch()
    if area.touch == touch then return end
    area.touch = touch
    area:ClearAllPoints()
    if touch then
        area:SetScale(TOUCH_SCALE)
        area:SetPoint("TOP", self.frame.zone, "TOP", 0, -PAD_TOP / TOUCH_SCALE)
    else
        area:SetScale(1)
        area:SetPoint("TOPLEFT", self.frame.zone, "TOPLEFT", 0, -PAD_TOP)
    end
    -- The focus on a button turned off: back on A
    if not M:InputEnabled(M.BY_ID[self.node]) then self.node = "A" end
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
local function legendSwatch(parent, fill, ring, hatch)
    local s = CK.NewFrame("Frame", nil, parent)
    s:SetSize(12, 12)
    if hatch then
        local t = s:CreateTexture(nil, "ARTWORK")
        t:SetTexture(K.TEX .. "ck_hatch")
        t:SetAllPoints()
        t:SetAlpha(0.6)
        return s
    end
    local outer = s:CreateTexture(nil, "ARTWORK", nil, 0)
    outer:SetTexture(K.TEX .. "ck_dot")
    outer:SetAllPoints()
    outer:SetVertexColor(ring[1], ring[2], ring[3])
    local inner = s:CreateTexture(nil, "ARTWORK", nil, 1)
    inner:SetTexture(K.TEX .. "ck_dot")
    inner:SetSize(8, 8)
    inner:SetPoint("CENTER")
    local c = fill or KC.boxBg
    inner:SetVertexColor(c[1], c[2], c[3])
    if not fill then
        local plus = K.ChatText(s, 10, KC.dimGold)
        plus:SetPoint("CENTER", 0, 0)
        plus:SetText("+")
    end
    return s
end

-- The five states, at the bottom of the detail panel
local function buildLegend(detail)
    local g = CK.NewFrame("Frame", nil, detail)
    g:SetPoint("BOTTOMLEFT", 14, 14)
    g:SetPoint("BOTTOMRIGHT", -14, 14)
    g:SetHeight(64)
    local line = K.Solid(g, KC.line3, 1, "BORDER")
    line:SetPoint("TOPLEFT")
    line:SetPoint("TOPRIGHT")
    line:SetHeight(1)
    local items = {
        { L.TAG_GAME_FUNCTION, KC.legendGame, KC.legendRing },
        { L.TAG_GAME_SLOT, KC.legendSlot, KC.slot },
        { L.TAG_YOURS, KC.legendYours, KC.yours },
        { L.TAG_FREE, nil, KC.legendFree },
        { L.TAG_UNAVAILABLE, nil, nil, true },
    }
    local colW = (PANEL_W - 28 - 10) / 2
    for i, item in ipairs(items) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local sw = legendSwatch(g, item[2], item[3], item[4])
        sw:SetPoint("TOPLEFT", col * (colW + 10), -10 - row * 20)
        local label = K.ChatText(g, 12, KC.help)
        label:SetPoint("LEFT", sw, "RIGHT", 6, 0)
        label:SetWidth(colW - 18)
        label:SetWordWrap(false)
        label:SetText(item[1])
    end
    g:Hide()
    detail.legend = g
end

function W:BuildNode(area, n)
    local id, x, y = n[1], n[2], n[3]
    local node = CK.NewFrame("Frame", nil, area)
    node:SetSize(SLOT, SLOT)
    node:SetPoint("CENTER", area, "TOPLEFT", x, -y)
    node.input = M.BY_ID[id]
    node.slot = K.Slot(node, SLOT, ICON, SQUARE[id])
    node.slot:SetAllPoints()
    -- Its glyph, beside it (just over the slot's edge)
    node.glyph = K.Glyph(node, GLYPH)
    node.glyph:SetFrameLevel(node.slot:GetFrameLevel() + 3)
    node.glyph.none = NO_GLYPH[id]
    -- Fork CoolerMgdn: what a hold runs, top right of the slot (the taps'
    -- view): its icon in a gold ring, a small clock beside it
    local hb = CK.NewFrame("Frame", nil, node)
    hb:SetSize(20, 20)
    -- (clear of a glyph drawn over the slot: Y, B, the paddles)
    hb:SetPoint("CENTER", node, "TOPRIGHT", 2, -3)
    hb:SetFrameLevel(node.slot:GetFrameLevel() + 4)
    hb.bg = hb:CreateTexture(nil, "BACKGROUND")
    hb.bg:SetTexture(K.TEX .. "ck_dot")
    hb.bg:SetAllPoints()
    hb.bg:SetVertexColor(KC.boxBg[1], KC.boxBg[2], KC.boxBg[3])
    hb.icon = K.RoundIcon(hb, 16, "ARTWORK")
    hb.icon:SetPoint("CENTER")
    hb.ring = hb:CreateTexture(nil, "OVERLAY")
    hb.ring:SetTexture(K.TEX .. "ck_ring")
    hb.ring:SetAllPoints()
    hb.ring:SetVertexColor(KC.slot[1], KC.slot[2], KC.slot[3])
    hb.clock = hb:CreateTexture(nil, "OVERLAY", nil, 2)
    hb.clock:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    hb.clock:SetSize(10, 10)
    hb.clock:SetPoint("CENTER", hb, "TOPLEFT", 1, -1)
    hb:Hide()
    node.holdBadge = hb
    -- Fork CoolerMgdn: what a double press runs, bottom right, a "2" beside
    local db = CK.NewFrame("Frame", nil, node)
    db:SetSize(20, 20)
    db:SetPoint("CENTER", node, "BOTTOMRIGHT", 2, 3)
    db:SetFrameLevel(node.slot:GetFrameLevel() + 4)
    db.bg = db:CreateTexture(nil, "BACKGROUND")
    db.bg:SetTexture(K.TEX .. "ck_dot")
    db.bg:SetAllPoints()
    db.bg:SetVertexColor(KC.boxBg[1], KC.boxBg[2], KC.boxBg[3])
    db.icon = K.RoundIcon(db, 16, "ARTWORK")
    db.icon:SetPoint("CENTER")
    db.ring = db:CreateTexture(nil, "OVERLAY")
    db.ring:SetTexture(K.TEX .. "ck_ring")
    db.ring:SetAllPoints()
    db.ring:SetVertexColor(KC.slot[1], KC.slot[2], KC.slot[3])
    db.mark = K.Text(db, 11, KC.slot, "OVERLAY")
    db.mark:SetPoint("CENTER", db, "BOTTOMLEFT", 0, 1)
    db.mark:SetText("2")
    db:Hide()
    node.doubleBadge = db
    local side = GLYPH_SIDE[id] or "left"
    if side == "top" then
        node.glyph:SetPoint("BOTTOM", node, "TOP", 0, -2)
    elseif side == "right" then
        node.glyph:SetPoint("LEFT", node, "RIGHT", -3, 0)
    else
        node.glyph:SetPoint("RIGHT", node, "LEFT", 3, 0)
    end
    -- What it does, under it
    node.label = K.Text(area, 12, KC.cream)
    node.label:SetPoint("TOP", node, "BOTTOM", 0, -2)
    node.label:SetWidth(LABEL_W[id] or 76)
    node.label:SetJustifyH("CENTER")
    -- The extra buttons' row is narrow: their names on two lines
    if node.label.SetMaxLines then node.label:SetMaxLines(n[4] and 2 or 1) end
    if n[4] then node.label:SetWordWrap(true) end
    node.slot:SetScript("OnClick", function(_, button)
        if W.wizard or P:IsCapturing() then return end
        C:Disarm()
        W.zone, W.node = "pad", id
        if button == "RightButton" then
            W:Clear()
        elseif W.assign then
            W:AssignWheel()
        else
            W:Choose()
        end
    end)
    node.slot:SetScript("OnEnter", function(self)
        local cell = node.cell
        if cell and cell.state == "slot" and not cell.empty and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetAction(cell.slot)
            GameTooltip:Show()
        end
    end)
    node.slot:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return node
end

function W:Build(parent)
    local f = CK.NewFrame("Frame", nil, parent)
    f:SetAllPoints()
    f:Hide()
    self.frame = f

    -- Left: the layers, the controller, the actions
    local zone = CK.NewFrame("Frame", nil, f)
    zone:SetPoint("TOPLEFT")
    zone:SetSize(ZONE_W, BODY_H)
    f.zone = zone

    local layersRow = CK.NewFrame("Frame", nil, zone)
    layersRow:SetPoint("TOPLEFT")
    layersRow:SetSize(ZONE_W, 32)
    f.layers = {}
    for i, layer in ipairs(M.LAYERS) do
        local b = K.Button(layersRow, 15)
        b.layer = layer
        if layer == "" then
            b.label:SetText(L.MAP_ALONE)
        else
            b.glyphs = K.GlyphRow(b, 28)
            b.glyphs:SetFrameLevel(b:GetFrameLevel() + 2)
        end
        b.focusBox = K.Box(b, 4, 2, "OVERLAY")
        b.focusBox:SetPoints(b, -3)
        b.focusBox:SetColors(nil, nil, KC.focus, 1)
        b.focusBox:SetShown(false)
        b:SetScript("OnClick", function()
            if W.wizard or P:IsCapturing() then return end
            C:Disarm()
            W.layer, W.zone = layer, "layers"
            C:Render()
        end)
        f.layers[i] = b
    end
    -- Fork CoolerMgdn: Hold, a view of its own over the layer shown
    -- (and Double after it: what a double press runs)
    local function viewButton(kind, label)
        local b = K.Button(layersRow, 14)
        b.label:SetText(label)
        b.focusBox = K.Box(b, 4, 2, "OVERLAY")
        b.focusBox:SetPoints(b, -3)
        b.focusBox:SetColors(nil, nil, KC.focus, 1)
        b.focusBox:SetShown(false)
        b:SetScript("OnClick", function()
            if W.wizard or P:IsCapturing() then return end
            C:Disarm()
            W.zone, W.holdFocus = "layers", kind
            W:SetView(kind)
        end)
        return b
    end
    local hb = viewButton("hold", L.MAP_HOLD)
    f.holdButton = hb
    local db = viewButton("double", L.MAP_DOUBLE)
    f.doubleButton = db
    local row = {}
    for i, b in ipairs(f.layers) do row[i] = b end
    row[#row + 1] = hb
    row[#row + 1] = db
    K.LayoutRow(layersRow, row, { 0.9, 0.9, 0.9, 1.05, 1.2, 1.2 }, 6)

    -- The controller's silhouette (Claude Design, drawn at 2x: 960 x 688 of 1024)
    local area = CK.NewFrame("Frame", nil, zone)
    area:SetPoint("TOPLEFT", 0, -PAD_TOP)
    area:SetSize(ZONE_W, PAD_H)
    f.area = area
    local pad = area:CreateTexture(nil, "BACKGROUND")
    pad:SetTexture(K.TEX .. "ck_pad")
    pad:SetTexCoord(0, 960 / 1024, 0, 688 / 1024)
    pad:SetAllPoints()
    f.padTex = pad
    local back = K.Text(area, 13, KC.rail)
    back:SetPoint("TOP", area, "TOPLEFT", 240, -316)
    back:SetWidth(120)
    back:SetJustifyH("CENTER")
    back:SetText(L.MAP_BACK_ROW)
    f.backLabel = back
    f.nodes = {}
    for _, n in ipairs(NODES) do f.nodes[n[1]] = self:BuildNode(area, n) end

    -- Under it: identify the paddles, move the buttons, restore
    local actionsRow = CK.NewFrame("Frame", nil, zone)
    actionsRow:SetPoint("TOPLEFT", 0, -(PAD_TOP + PAD_H + 8))
    actionsRow:SetSize(ZONE_W, 32)
    f.actions = {}
    for i = 1, 3 do
        local b = K.Button(actionsRow, 13)
        b:SetScript("OnClick", function()
            if W.wizard or P:IsCapturing() then return end
            if i ~= 3 then C:Disarm() end
            W.zone, W.act = "actions", i
            W:Act(i)
        end)
        f.actions[i] = b
    end
    K.LayoutRow(actionsRow, f.actions, { 1.2, 1, 1 }, 6)

    -- Right: the detail panel, the picker or the paddles wizard in its place
    self.detail = K.Detail(f, PANEL_W, 26)
    self.detail:SetPoint("TOPRIGHT")
    self.detail:SetHeight(BODY_H)
    buildLegend(self.detail)
    self.picker = K.Picker(f, PANEL_W)
    self.picker:SetPoint("TOPRIGHT")
    self.picker:SetHeight(BODY_H)
    self:BuildWizard(f)
end

-- Identify the back paddles: one step after the other, in the right panel
function W:BuildWizard(f)
    local w = CK.NewFrame("Frame", nil, f)
    w:SetPoint("TOPRIGHT")
    w:SetSize(PANEL_W, BODY_H)
    w.box = K.Box(w, 4, 1, "BACKGROUND", 1)
    w.box:SetPoints(w)
    w.box:SetColors(KC.black, 0.72, KC.line1, 1)
    w.title = K.Text(w, 19, KC.title)
    w.title:SetPoint("TOPLEFT", 16, -16)
    w.title:SetWidth(PANEL_W - 32)
    w.title:SetWordWrap(true)
    w.steps = {}
    local rows = {}
    for r = 1, 3 do
        local row = CK.NewFrame("Frame", nil, w)
        row:SetPoint("TOPLEFT", w.title, "BOTTOMLEFT", 0, -14 - (r - 1) * 36)
        row:SetSize(PANEL_W - 32, 30)
        local list = {}
        for c = 1, 4 do
            local s = CK.NewFrame("Frame", nil, row)
            s.box = K.Box(s, 4, 1, "ARTWORK")
            s.box:SetPoints(s)
            s.label = K.ChatText(s, 13, KC.cream)
            s.label:SetPoint("CENTER", 0, 0)
            list[c] = s
            w.steps[#w.steps + 1] = s
        end
        K.LayoutRow(row, list, { 1, 1, 1, 1 }, 8)
        rows[r] = row
    end
    w.stepRows = rows
    w.stepsRow = rows[1]
    w.text = K.Text(w, 22, KC.focusText)
    w.text:SetPoint("TOPLEFT", rows[1], "BOTTOMLEFT", 0, -14)
    w.text:SetWidth(PANEL_W - 32)
    w.text:SetWordWrap(true)
    w.text:SetSpacing(8)
    w.hint = K.ChatText(w, 14, KC.cream2)
    w.hint:SetPoint("TOPLEFT", w.text, "BOTTOMLEFT", 0, -14)
    w.hint:SetWidth(PANEL_W - 32)
    w.hint:SetWordWrap(true)
    w.hint:SetSpacing(6)
    w:Hide()
    self.wizardFrame = w
end

local slotEvents = CreateFrame("Frame")
slotEvents:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
slotEvents:SetScript("OnEvent", function() W.slotsChanged = true end)

-- Opened on A, alone; back from placing the bar (resume), as it was
function W:Show(resume)
    if not resume then
        self.zone, self.node, self.layer, self.act = "pad", "A", "", 1
        self.wizard, self.assign = nil, nil
        self.hold, self.holdFocus = false, false
        if P:IsCapturing() then P:StopCapture(nil) end
        self.picker:Close()
    end
    self.heldLayer = ""
    self.frame:Show()
    -- Paddles given something to do, not identified: said once a session
    if not self.paddlesReminded then
        local ids = P:Unidentified()
        if #ids > 0 then
            self.paddlesReminded = true
            C:Toast(format(L.TOAST_PADDLES_NOT_SET, table.concat(ids, ", ")), true)
        end
    end
end

function W:Hide()
    self.wizard = nil
    if P:IsCapturing() then P:StopCapture(nil) end
    self.picker:Close()
    self.frame:Hide()
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local TAGS = {
    native = { "TAG_GAME_FUNCTION", "gameFn" }, slot = { "TAG_GAME_SLOT", "slot" }, yours = { "TAG_YOURS", "yours" },
    free = { "TAG_FREE", "grey" }, off = { "TAG_UNAVAILABLE", "off" },
}

function W:RenderNode(node, layer)
    local input = node.input
    local cell = self:Cell(input, layer)
    node.cell = cell
    local st = cell.state
    local focus = self.zone == "pad" and self.node == input.id
    if self.wizard then focus = input.id == P:Order()[self.wizard.step] end
    local look = { glow = focus }
    if st == "native" then
        -- No picture of its own: the button's glyph, if it has one
        local glyph = K.INPUT_GLYPH[input.id] or input.id
        look.icon = cell.icon or (K.IMAGE[glyph] and { glyph = glyph }) or nil
        look.discColor = KC.iconBg
    elseif st == "slot" then
        look.ring = KC.slot
        if cell.empty then
            look.plus = true
        else
            look.icon, look.discColor = cell.icon, KC.iconBg
        end
    elseif st == "yours" then
        look.icon, look.discColor = cell.icon, KC.iconBg
        look.ring, look.ringOut, look.mark = KC.yours, true, true
    elseif st == "free" then
        look.plus = true
    else
        look.hatch = true
    end
    node.slot:SetLook(look)
    node:SetAlpha(st == "off" and 0.45 or 1)
    node.label:SetAlpha(st == "off" and 0.45 or 1)
    if node.glyph.none then
        node.glyph:Hide()
    else
        node.glyph:Set(K.INPUT_GLYPH[input.id] or input.id)
    end
    node.label:SetText(cell.name or "")
    local color = focus and KC.focusText or ((st == "free" or cell.empty) and KC.grey)
        or (st == "native" and KC.help) or KC.cream
    node.label:SetTextColor(color[1], color[2], color[3])
    -- Fork CoolerMgdn: its hold (taps' view only; the Hold view shows it)
    local held = not self.hold and M:GetHold(input.id, layer)
    node.holdBadge:SetShown(held and true or false)
    if held then CK.Paddles.SetIcon(node.holdBadge.icon, M:ActionIcon(held)) end
    local double = not self.hold and M:GetDouble(input.id, layer)
    node.doubleBadge:SetShown(double and true or false)
    if double then CK.Paddles.SetIcon(node.doubleBadge.icon, M:ActionIcon(double)) end
end

-- Fork CoolerMgdn: the controller drawn as the one picked (Home › Look ›
-- Button glyphs, or the one in hand): a DualSense, its buttons where they
-- sit on it; the back paddles' caption only with a paddle shown
function W:ApplyStyle()
    local f = self.frame
    local ps = M.PlayStation()
    if f.ps ~= ps then
        f.ps = ps
        f.padTex:SetTexture(K.TEX .. (ps and "ck_pad_ps" or "ck_pad"))
        for _, n in ipairs(NODES) do
            local at = ps and PS_NODES[n[1]] or n.home
            n[2], n[3] = at[1], at[2]
            local node = f.nodes[n[1]]
            node:ClearAllPoints()
            node:SetPoint("CENTER", f.area, "TOPLEFT", n[2], -n[3])
            if PS_GLYPH_SIDE[n[1]] then
                local side = ps and PS_GLYPH_SIDE[n[1]] or GLYPH_SIDE[n[1]] or "left"
                node.glyph:ClearAllPoints()
                if side == "right" then
                    node.glyph:SetPoint("LEFT", node, "RIGHT", -3, 0)
                else
                    node.glyph:SetPoint("RIGHT", node, "LEFT", 3, 0)
                end
            end
        end
        -- The focus on a button this pad hasn't: back on A
        if not M:InputEnabled(M.BY_ID[self.node]) then self.node = "A" end
    end
    local paddles = false
    for _, id in ipairs({ "L4", "L5", "R4", "R5" }) do
        if M:InputEnabled(M.BY_ID[id]) then paddles = true end
    end
    f.backLabel:SetShown(paddles)
end

function W:ActionLabels()
    local n = M:ReplacedCount()
    return { L.LBL_IDENTIFY, L.LBL_PLACE_BAR,
        C:IsArmed("restore") and L.LBL_PRESS_AGAIN or (n > 0 and format(L.LBL_RESTORE_N, n) or L.LBL_RESTORE) }
end

function W:Render()
    self.frame:Show()
    local f = self.frame
    local layer = self:ViewLayer()
    for _, b in ipairs(f.layers) do
        local active = b.layer == layer
        b:SetState({ active = active })
        b.focusBox:SetShown(self.zone == "layers" and active and not self.picker:IsOpen())
        if b.glyphs then
            b.glyphs:Set(LAYER_KEYS[b.layer])
            b.glyphs:ClearAllPoints()
            b.glyphs:SetPoint("CENTER", b, "CENTER", 0, 0)
        end
    end
    local rowFocus = self.zone == "layers" and not self.picker:IsOpen()
    f.holdButton:SetState({ active = self.hold == "hold" })
    f.holdButton.focusBox:SetShown(rowFocus and self.holdFocus == "hold")
    f.doubleButton:SetState({ active = self.hold == "double" })
    f.doubleButton.focusBox:SetShown(rowFocus and self.holdFocus == "double")
    if self.holdFocus and self.zone == "layers" then
        for _, b in ipairs(f.layers) do b.focusBox:SetShown(false) end
    end
    self:LayoutPad()
    self:ApplyStyle()
    for _, node in pairs(f.nodes) do
        local on = M:InputEnabled(node.input)
        node:SetShown(on)
        node.label:SetShown(on)
        if on then self:RenderNode(node, layer) end
    end
    local labels = self:ActionLabels()
    local none = M:ReplacedCount() == 0
    for i, b in ipairs(f.actions) do
        b.label:SetText(labels[i])
        b:SetState({ focus = self.zone == "actions" and self.act == i and not self.picker:IsOpen() and not self.wizard,
            armed = i == 3 and C:IsArmed("restore"), disabled = i == 3 and none })
    end
    -- The right panel
    local w = self.wizardFrame
    w:SetShown(self.wizard ~= nil)
    if self.wizard then
        self.detail:Hide()
        self.picker:Hide()
        self:RenderWizard()
    elseif self.picker:IsOpen() then
        self.detail:Hide()
        self.picker:Show()
        self.picker:Render()
    else
        self.detail:Show()
        self.detail:Set(self:Detail(layer))
    end
end

function W:RenderWizard()
    local w, step = self.wizardFrame, self.wizard.step
    w.title:SetText(L.MAP_IDENTIFY)
    local order = P:Order()
    for i, s in ipairs(w.steps) do
        local done, now = i < step, i == step
        s:SetShown(order[i] ~= nil)
        s.box:SetColors(done and KC.doneBg or (now and KC.nowBg or KC.controlBg), 1,
            done and KC.done or (now and KC.focus or KC.line2), 1)
        s.label:SetText(order[i] or "")
        local c = (done or now) and KC.focusText or KC.eventOff
        s.label:SetTextColor(c[1], c[2], c[3])
    end
    -- The text under the last row used
    local rowsUsed = math.max(1, math.ceil(#order / 4))
    w.text:ClearAllPoints()
    w.text:SetPoint("TOPLEFT", w.stepRows[rowsUsed], "BOTTOMLEFT", 0, -14)
    w.text:SetText(format(L.MAP_WIZARD, order[step] or ""))
    w.hint:SetText(L.MAP_IDENTIFY_HINT)
end

function W:Detail(layer)
    if self.zone == "layers" and self.holdFocus == "double" then
        local n = CK.HoldClock.DOUBLE_TICKS
        return { title = L.MAP_DBL_TITLE, body = format(L.TIP_DOUBLE, (n - 1) * 0.2, n * 0.2) }
    end
    if self.zone == "layers" and self.holdFocus then
        local a, b = CK.HoldClock:Range()
        return { title = L.MAP_HOLD_TITLE, body = format(L.TIP_HOLD, a, b) }
    end
    if self.zone == "layers" then return { title = L.LBL_LAYERS, body = L.TIP_LAYERS } end
    if self.hold and self.zone == "pad" then
        local input = self:Focused()
        if not input then return {} end
        local cell = self:HoldCell(input, layer)
        local tag = TAGS[cell.state]
        local dbl = self.hold == "double"
        local title = cell.state == "off" and L.TAG_UNAVAILABLE
            or (cell.state == "free" and (dbl and L.MAP_DBL_FREE or L.MAP_HOLD_FREE)) or cell.name
        local body = cell.state == "off" and cell.why
            or (cell.state == "free" and (dbl and L.MAP_DBL_FREE_HINT or L.MAP_HOLD_FREE_HINT))
            or (dbl and L.MAP_DBL_ASSIGNED_HINT or L.MAP_HOLD_ASSIGNED_HINT)
        return { combo = K.ComboKeys(input.id, layer), title = title, tag = L[tag[1]], tagColor = KC[tag[2]],
            body = body, extra = dbl and L.MAP_DBL_EXTRA or L.MAP_HOLD_EXTRA, legend = true }
    end
    if self.zone == "actions" then
        local n = M:ReplacedCount()
        local list = {
            { title = L.MAP_IDENTIFY, body = L.MAP_IDENTIFY_HINT },
            { title = L.MAP_PLACE, body = L.MAP_PLACE_HINT },
            { title = n > 0 and format(L.MAP_RESTORE, n) or L.MAP_RESTORE_NONE, body = L.TIP_RESTORE },
        }
        return list[self.act]
    end
    local input = self:Focused()
    if not input then return {} end
    local cell = self:Cell(input, layer)
    local st = cell.state
    local tag = TAGS[st]
    local title = cell.name
    if st == "free" then title = L.MAP_FREE end
    if st == "off" then title = L.TAG_UNAVAILABLE end
    if st == "slot" and cell.empty then title = L.LBL_EMPTY_SLOT end
    local body
    local replaceable = M:Replaceable(input, layer)
    local replaceHint = replaceable and (M:CanOwnKeys() and L.MAP_REPLACE_HINT or L.MAP_REPLACE_NO_MOD)
    if st == "native" then
        body = input.layer and L.MAP_TRIGGER_HINT or replaceHint or L.MAP_NATIVE_HINT
    elseif st == "slot" then
        local kept = M:SlotKept(cell.slot)
        body = kept and (kept .. (replaceHint and ("\n\n" .. replaceHint) or ""))
            or (replaceable and M:CanOwnKeys() and L.MAP_SLOT_REPLACE_HINT) or replaceHint or L.MAP_SLOT_HINT
    elseif st == "yours" then
        body = cell.replaced and format(L.MAP_REPLACES, cell.rep) or L.MAP_ASSIGNED_HINT
    elseif st == "free" then
        body = L.MAP_FREE_HINT
    else
        body = cell.why
    end
    -- A shared key (the trigger no modifier): spells, items and macros
    if input.paddle and (st == "free" or st == "yours") and M:PaddleTabs(input, layer) == M.SHARED_TABS then
        body = body .. "\n\n" .. L.MAP_SHARED_HINT
    end
    local extra
    if input.paddle then
        if P:IsCapturing(input.id) then
            extra = L.MAP_PADDLE_PRESS
        elseif not P:Identified(input.id) then
            -- (its key never learned: said plainly, not the default's name)
            extra = L.MAP_PADDLE_NOT_SET
        elseif M:InputKey(input) then
            extra = format(L.MAP_PADDLE_KEY, keyText(M:InputKey(input)))
        end
    end
    -- Fork CoolerMgdn: its hold, said (the badge on the slot)
    local held = M:GetHold(input.id, layer)
    if held then
        local line = format(L.MAP_HOLD_LINE, M:ActionName(held) or "")
        extra = extra and (extra .. "\n" .. line) or line
    end
    local double = M:GetDouble(input.id, layer)
    if double then
        local line = format(L.MAP_DBL_LINE, M:ActionName(double) or "")
        extra = extra and (extra .. "\n" .. line) or line
    end
    return { combo = K.ComboKeys(input.id, layer), title = title, tag = L[tag[1]], tagColor = KC[tag[2]],
        body = body, extra = extra, legend = true }
end

---------------------------------------------------------------------------
-- Fork CoolerMgdn: where an action is (a wheel...): "Where is this button?"
-- rows on the other tabs (ConfigWindow's b.where). Its combinations (taps,
-- not holds), the first shown on this tab.
---------------------------------------------------------------------------
function W.Find(action)
    local s, found = settings(), {}
    for _, list in ipairs({ s.replaced or {}, s.mapping or {} }) do
        for key, a in pairs(list) do
            local id, layer = key:match("^([^:]+):(.*)$")
            local input = id and M.BY_ID[id]
            if a == action and input and not M.ExtraLayer(layer) and M:InputEnabled(input) then
                found[#found + 1] = { id = id, layer = layer }
            end
        end
    end
    table.sort(found, function(a, b)
        if a.layer ~= b.layer then return #a.layer < #b.layer or (#a.layer == #b.layer and a.layer < b.layer) end
        return a.id < b.id
    end)
    return found
end

function W.WhereText(action)
    local found = W.Find(action)
    if #found == 0 then return L.WHERE_NONE end
    local parts = {}
    for i = 1, math.min(2, #found) do parts[i] = K.ComboMarkup(found[i].id, found[i].layer, 16) end
    return table.concat(parts, ", ")
end

function W.GoTo(action)
    local hit = W.Find(action)[1]
    C:SetTab("gamepad")
    if hit then
        W.zone, W.node, W.layer, W.hold, W.holdFocus = "pad", hit.id, hit.layer, false, false
        C:Toast(format(L.TOAST_WHERE, M:ActionName(action) or ""))
    else
        C:Toast(L.TOAST_WHERE_NONE, true)
    end
    C:Render()
end

function W:Crumb()
    if self.assign then return format(L.CRUMB_ASSIGN, CK.MyWheels:Name(self.assign) or "") end
    local layer = self:ViewLayer()
    local name = layer == "" and L.MAP_ALONE
        or format(L.CRUMB_LAYER, (K.ComboMarkup("", layer, 14):gsub(" %+ $", "")))
    -- The character's profile being set, when it has more than one
    local profile = #CK.Profiles:Sets() > 1 and select(2, CK.Profiles:ActiveSet())
    if self.hold then name = name .. " › " .. (self.hold == "double" and L.MAP_DOUBLE or L.MAP_HOLD) end
    return L.TAB_GAMEPAD .. (profile and (" › " .. profile) or "") .. " › " .. name
end

function W:Help()
    local H = K.H
    if self.wizard then return { H({ "X" }, L.V_SKIP, "X"), H({ "B" }, L.V_CANCEL, "B") } end
    if P:IsCapturing() then return { H({ "B" }, L.V_CANCEL, "B") } end
    if self.picker:IsOpen() then return self.picker:Hints() end
    local tab = H({ "LB", "RB" }, L.V_TAB, "RB")
    if self.assign then
        return { H({ "DPAD" }, L.V_MOVE), H({ "A" }, L.V_ASSIGN_HERE, "A"), H({ "B" }, L.V_CANCEL, "B") }
    end
    if self.zone == "layers" then
        return { H({ "DPAD_LR" }, L.V_LAYER, "RIGHT"), H({ "DPAD" }, L.V_BUTTONS, "DOWN"), tab, H({ "B" }, L.V_CLOSE, "B") }
    end
    if self.zone == "actions" then
        return { H({ "DPAD" }, L.V_MOVE), H({ "A" }, L.V_SELECT, "A"), tab, H({ "B" }, L.V_BACK, "B") }
    end
    if self.zone == "pad" and self.hold then
        local input = self:Focused()
        local cell = input and self:HoldCell(input, self:ViewLayer()) or { state = "off" }
        local hints = { H({ "DPAD" }, L.V_MOVE) }
        if cell.state == "off" then
            if cell.why then hints[#hints + 1] = H({ "A" }, L.V_WHY, "A") end
        else
            hints[#hints + 1] = H({ "A" }, cell.state == "free" and L.V_ASSIGN or L.V_CHANGE, "A")
        end
        if cell.action then hints[#hints + 1] = H({ "X" }, L.V_REMOVE, "X") end
        -- (Y: Hold, then Double, then the taps)
        hints[#hints + 1] = H({ "Y" }, self.hold == "hold" and L.MAP_DOUBLE or L.V_TAPS, "Y")
        hints[#hints + 1] = tab
        hints[#hints + 1] = H({ "B" }, L.V_CLOSE, "B")
        return hints
    end
    local input = self:Focused()
    local cell = input and self:Cell(input, self:ViewLayer()) or { state = "off" }
    local hints = { H({ "DPAD" }, L.V_MOVE) }
    local layer = self:ViewLayer()
    local state = input and M:State(input, layer)
    local replace = input and M:Replaceable(input, layer) and M:CanOwnKeys()
    local canA = state == "free" or replace
        or (state == "slot" and not M:SlotKept(M:NativeSlot(input, layer)))
    if cell.lockedAlone then
        hints[#hints + 1] = H({ "A" }, L.V_UNLOCK, "A")
    elseif cell.state == "off" and cell.why then
        hints[#hints + 1] = H({ "A" }, L.V_WHY, "A")
    elseif cell.pick or (cell.state ~= "off" and input and canA) then
        hints[#hints + 1] = H({ "A" }, cell.state == "free" and L.V_ASSIGN or L.V_CHANGE, "A")
    end
    if cell.replaced then
        hints[#hints + 1] = H({ "X" }, L.V_GIVE_BACK, "X")
    elseif cell.state == "slot" and not cell.empty and not M:SlotKept(cell.slot) then
        hints[#hints + 1] = H({ "X" }, L.V_EMPTY, "X")
    elseif cell.action then
        hints[#hints + 1] = H({ "X" }, L.V_REMOVE, "X")
    end
    if input and input.paddle then
        hints[#hints + 1] = H({ "Y" }, L.V_KEY, "Y")
    else
        hints[#hints + 1] = H({ "Y" }, L.MAP_HOLD, "Y")
    end
    hints[#hints + 1] = tab
    hints[#hints + 1] = H({ "B" }, L.V_CLOSE, "B")
    return hints
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
-- The nearest button that way: the main axis counts, the gap across it
-- twice (a cone of about 65 degrees)
function W:Nearest(from, dir)
    local f = POS[from]
    if not f then return end
    local best, bestScore
    for _, n in ipairs(NODES) do
        if n[1] ~= from and M:InputEnabled(M.BY_ID[n[1]]) then
            local dx, dy = n[2] - f[2], n[3] - f[3]
            local main, cross
            if dir == "UP" then
                main, cross = -dy, dx
            elseif dir == "DOWN" then
                main, cross = dy, dx
            elseif dir == "LEFT" then
                main, cross = -dx, dy
            else
                main, cross = dx, dy
            end
            if main > 6 and math.abs(cross) <= main * 2.2 then
                local score = main + math.abs(cross) * 2
                if not bestScore or score < bestScore then best, bestScore = n[1], score end
            end
        end
    end
    return best
end

-- What a choice does: a spell, an item or a macro goes in a slot of the
-- game's bar (like the game's own editor); anything else replaces the
-- game's button; a free button takes it
function W:Put(input, layer, action)
    if self.hold == "double" then
        if M:DoubleBlocked(input, layer) then return false end
        if action ~= M.NOTHING and not M.HoldAction(action) then return false end
        M:SetDouble(input.id, layer, action)
        return true
    end
    if self.hold then
        if M:HoldBlocked(input, layer) then return false end
        if action ~= M.NOTHING and not M.HoldAction(action) then return false end
        M:SetHold(input.id, layer, action)
        return true
    end
    local state = M:State(input, layer)
    local kind = action:match("^(%a+):")
    if state == "slot" then
        local slot = M:NativeSlot(input, layer)
        if SLOT_KINDS[kind] and not M:SlotKept(slot) then
            if not M:PlaceInSlot(slot, action) then return false end
            if M:GetReplaced(input.id, layer) then M:SetReplaced(input.id, layer, nil) end
            return true
        end
    end
    if state == "slot" or state == "native" then
        if not (M:Replaceable(input, layer) and M:CanOwnKeys()) then return false end
        M:SetReplaced(input.id, layer, action)
        return true
    end
    if state == "free" then
        M:Set(input.id, layer, action)
        return true
    end
    return false
end

-- A layer locked by its button alone (L3's autorun, LB's targeting, a game
-- function the player put on X alone): A says why, and frees it on the spot
-- (reported: players saw "Game function" there and didn't know why)
function W:ExplainLocked(input, layer, cell)
    local held = cell.lockedAlone == "held"
    local entries = {
        { action = "free", icon = M:ActionIcon(M.NOTHING),
            name = format(held and L.MAP_FREE_NOTHING or L.MAP_FREE_GIVE_BACK, input.id) },
        { action = "choose", icon = 134400, name = format(L.MAP_FREE_CHOOSE, input.id) },
        { action = "keep", icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up", name = L.MAP_FREE_KEEP },
    }
    self.picker:Open({
        kicker = L.KICK_LOCKED,
        title = function() return K.ComboMarkup(input.id, layer, 16) .. " — " .. (cell.name or L.MAP_GAME) end,
        text = cell.why,
        lists = { { label = "", entries = function() return entries end } },
        rows = 3, chooseVerb = L.V_CHOOSE,
        onChoose = function(e)
            self.picker:Close()
            if e.action == "free" then
                local done
                if held then
                    done = self:Put(input, "", M.NOTHING)
                else
                    M:SetReplaced(input.id, "", nil)
                    done = true
                end
                if done then
                    C:Toast(format(L.TOAST_FREED, input.id))
                    -- The layer, free now: its choice right away
                    return self:ChooseIn(input, layer)
                end
                if UIErrorsFrame then UIErrorsFrame:AddMessage(L.MAP_REPLACE_NO_MOD, 1, 0.1, 0.1) end
            elseif e.action == "choose" then
                return self:ChooseIn(input, "")
            end
            C:Render()
        end,
        onBack = function()
            self.picker:Close()
            C:Render()
        end,
    })
    C:Render()
    if UIFrameFadeIn then UIFrameFadeIn(self.picker, 0.15, 0, 1) end
end

-- An unavailable cell that can't be freed: why, and OK
function W:ExplainOnly(input, layer, cell)
    self.picker:Open({
        kicker = L.KICK_LOCKED,
        title = function() return K.ComboMarkup(input.id, layer, 16) .. " — " .. (cell.name or L.MAP_GAME) end,
        text = cell.why,
        lists = { { label = "", entries = function() return { { action = "ok", name = L.V_OK, icon = 134400 } } end } },
        rows = 1, chooseVerb = L.V_OK,
        onChoose = function()
            self.picker:Close()
            C:Render()
        end,
        onBack = function()
            self.picker:Close()
            C:Render()
        end,
    })
    C:Render()
end

function W:Choose()
    local input = self:Focused()
    if not input then return end
    return self:ChooseIn(input, self:ViewLayer())
end

-- The picker for a button in a layer (the one in view, or the button alone
-- when freeing a layer)
-- Fork CoolerMgdn: what a button runs held (spells, items, macros, wheels,
-- the game's bar buttons: no game function, a router can't run one)
function W:ChooseHold(input, layer)
    local cell = self:HoldCell(input, layer)
    if cell.state == "off" then
        if cell.why then self:ExplainOnly(input, layer, cell) end
        return
    end
    local lists = {}
    for _, tab in ipairs(M.TABS) do
        lists[#lists + 1] = { key = tab, label = L["MAP_TAB_" .. tab:upper()], entries = function()
            local out = {}
            for _, e in ipairs(M:Catalog(tab, false, true)) do
                if e.header or e.action == M.NOTHING or M.HoldAction(e.action) then out[#out + 1] = e end
            end
            return out
        end }
    end
    local dbl = self.hold == "double"
    self.picker:Open({
        kicker = dbl and L.KICK_DOUBLE or L.KICK_HOLD,
        title = function() return K.ComboMarkup(input.id, layer, 16) .. " — " .. (dbl and L.MAP_DOUBLE or L.MAP_HOLD) end,
        lists = lists, current = cell.action, rows = 10,
        onChoose = function(e)
            self.picker:Close()
            if self:Put(input, layer, e.action) then
                if e.action == M.NOTHING then
                    C:Toast(L.TOAST_FN_REMOVED)
                else
                    C:Toast(format(dbl and L.TOAST_DBL_PAIR or L.TOAST_HOLD_PAIR, K.ComboMarkup(input.id, layer, 14), e.name or ""))
                end
            end
            C:Render()
        end,
        onBack = function()
            self.picker:Close()
            C:Render()
        end,
    })
    C:Render()
    if UIFrameFadeIn then UIFrameFadeIn(self.picker, 0.15, 0, 1) end
end

-- Y: the taps, then Hold, then Double, then the taps again
function W:ToggleHold()
    self:SetView(not self.hold and "hold" or (self.hold == "hold" and "double") or false)
end

-- One view ("hold", "double"; false: the taps); the one shown again: off
function W:SetView(kind)
    if kind and self.hold == kind then kind = false end
    self.hold = kind or false
    C:Toast(kind == "hold" and L.TOAST_HOLD_ON or (kind == "double" and L.TOAST_DBL_ON) or L.TOAST_HOLD_OFF)
    C:Render()
end

function W:ChooseIn(input, layer)
    if self.hold then return self:ChooseHold(input, layer) end
    local cell = self:Cell(input, layer)
    if cell.lockedAlone then return self:ExplainLocked(input, layer, cell) end
    if cell.state == "off" and not cell.pick then
        -- Any other unavailable cell (LT + LB, a trigger held, Start...):
        -- why, on A too
        if cell.why then self:ExplainOnly(input, layer, cell) end
        return
    end
    local state = M:State(input, layer)
    local replace = M:Replaceable(input, layer) and M:CanOwnKeys()
    local tabs, forSlot, slot
    if state == "slot" then
        slot = M:NativeSlot(input, layer)
        local kept = M:SlotKept(slot)
        if kept and not replace then
            if UIErrorsFrame then UIErrorsFrame:AddMessage(kept, 1, 0.1, 0.1) end
            return
        end
        tabs, forSlot = replace and M.TABS or M.SLOT_TABS, not replace
    elseif state == "free" then
        tabs = input.paddle and M:PaddleTabs(input, layer) or M.TABS
    elseif replace then
        tabs = M.TABS
    else
        -- The game's, and no free modifier to replace it
        if UIErrorsFrame and M:Replaceable(input, layer) then UIErrorsFrame:AddMessage(L.MAP_REPLACE_NO_MOD, 1, 0.1, 0.1) end
        return
    end
    local current = (replace and M:GetReplaced(input.id, layer)) or (slot and M:SlotAction(slot)) or M:Get(input.id, layer) or cell.action
    local lists = {}
    for _, tab in ipairs(tabs) do
        local noBound = layer ~= "" and not input.paddle
        lists[#lists + 1] = { key = tab, label = L["MAP_TAB_" .. tab:upper()], entries = function() return M:Catalog(tab, forSlot, noBound) end }
    end
    local name = cell.name or L.MAP_FREE
    self.picker:Open({
        kicker = L.KICK_ASSIGN_TO,
        title = function() return K.ComboMarkup(input.id, layer, 16) .. " — " .. name end,
        lists = lists, current = current, rows = 10,
        onChoose = function(e)
            self.picker:Close()
            if self:Put(input, layer, e.action) then
                if input.paddle and not P:Identified(input.id) then
                    C:Toast(format(L.TOAST_PADDLE_NOT_SET, input.id), true)
                else
                    C:Toast(format(L.TOAST_PAIR, K.ComboMarkup(input.id, layer, 14), e.name or ""))
                end
            end
            C:Render()
        end,
        onBack = function()
            self.picker:Close()
            C:Render()
        end,
    })
    C:Render()
    if UIFrameFadeIn then UIFrameFadeIn(self.picker, 0.15, 0, 1) end
end

-- X: the button given back to the game, the slot emptied, or ours removed
function W:Clear()
    local input = self:Focused()
    if not input or CK:BlockedByCombat() then return end
    local layer = self:ViewLayer()
    local cell = self:Cell(input, layer)
    if self.hold then
        if cell.action then
            if self.hold == "double" then M:SetDouble(input.id, layer, nil) else M:SetHold(input.id, layer, nil) end
            C:Toast(L.TOAST_FN_REMOVED)
        end
        C:Render()
        return
    end
    if cell.replaced then
        M:SetReplaced(input.id, layer, nil)
        C:Toast(L.TOAST_GIVEN_BACK)
    elseif cell.state == "slot" and not cell.empty then
        local kept = M:SlotKept(cell.slot)
        M:ClearSlot(cell.slot)
        if not kept then C:Toast(L.TOAST_SLOT_EMPTIED) end
    elseif cell.psReplaced then
        M:SetReplaced(input.id, layer, nil)
        C:Toast(L.TOAST_FN_REMOVED)
    elseif cell.action then
        M:Set(input.id, layer, nil)
        C:Toast(L.TOAST_FN_REMOVED)
    end
    C:Render()
end

-- Y on a back paddle: learn its key again
function W:LearnKey()
    local input = self:Focused()
    if not (input and input.paddle) then return end
    P:Capture(input.id, function(key)
        if key then C:Toast(format(L.TOAST_PAIR, input.id, keyText(key))) end
        if C:IsOpen() then C:Render() end
    end)
    C:Render()
end

-- Identify the back paddles: each one pressed in turn (X skips one)
function W:Identify()
    self.picker:Close()
    self.wizard = { step = 1 }
    self:WizardStep()
end

function W:WizardStep()
    local wizard = self.wizard
    if not wizard then return end
    local id = P:Order()[wizard.step]
    if not id then
        self.wizard = nil
        C:Toast(L.MAP_WIZARD_DONE)
        C:Render()
        return
    end
    self.node = id
    P:Capture(id, function(key)
        if W.wizard ~= wizard then return end
        if key then C:Toast(format(L.TOAST_PAIR, id, keyText(key))) end
        wizard.step = wizard.step + 1
        W:WizardStep()
    end)
    C:Render()
end

function W:Act(i)
    if i == 1 then
        self:Identify()
    elseif i == 2 then
        self.picker:Close()
        C:BeginPlacement()
        P:StartPlacement()
    elseif i == 3 then
        if M:ReplacedCount() == 0 or CK:BlockedByCombat() then return end
        if C:IsArmed("restore") then
            C:Disarm()
            M:RestoreGameButtons()
            C:Toast(L.TOAST_RESTORED)
        else
            C:Arm("restore")
        end
        C:Render()
        if C:IsArmed("restore") and UIFrameFadeIn then UIFrameFadeIn(self.frame.actions[3], 0.15, 0.3, 1) end
    end
end

-- From a wheel's editor: the next button chosen takes the wheel
function W:StartAssign(id)
    C:SetTab("gamepad")
    self.picker:Close()
    self.assign = id
    self.zone, self.node, self.layer = "pad", "A", ""
    C:Render()
end

function W:AssignWheel()
    local input = self:Focused()
    local id = self.assign
    if not (input and id) then return end
    local layer = self:ViewLayer()
    local cell = self:Cell(input, layer)
    if cell.state == "off" and not cell.pick then
        if cell.why and UIErrorsFrame then UIErrorsFrame:AddMessage(cell.why, 1, 0.1, 0.1) end
        return
    end
    if self:Put(input, layer, "wheel:" .. id) then
        self.assign = nil
        C:Toast(format(L.TOAST_ON, CK.MyWheels:Name(id) or "", K.ComboMarkup(input.id, layer, 14)))
    elseif UIErrorsFrame then
        local why = not M:Enabled() and L.MAP_MODULE_OFF or input.layer and L.MAP_TRIGGER_FIXED or L.MAP_REPLACE_NO_MOD
        UIErrorsFrame:AddMessage(why, 1, 0.1, 0.1)
    end
    C:Render()
end

---------------------------------------------------------------------------
-- The pad (the panel handles LB / RB and B when we don't)
---------------------------------------------------------------------------
local DIRS = { UP = true, DOWN = true, LEFT = true, RIGHT = true }

function W:Press(name)
    -- Identifying the paddles: X skips one, B stops
    if self.wizard then
        if name == "X" then
            P:StopCapture(nil)
        elseif name == "B" then
            self.wizard = nil
            P:StopCapture(nil)
            C:Render()
        end
        return true
    end
    -- Learning one paddle's key: B cancels
    if P:IsCapturing() then
        if name == "B" then P:StopCapture(nil) end
        C:Render()
        return true
    end
    if self.picker:IsOpen() then
        self.picker:Press(name)
        C:Render()
        return true
    end
    if name == "LB" or name == "RB" then return false end
    if self.zone == "layers" then
        -- Fork CoolerMgdn: the Hold button after the layers
        if self.holdFocus then
            if name == "LEFT" then
                self.holdFocus = self.holdFocus == "double" and "hold" or false
            elseif name == "RIGHT" then
                self.holdFocus = "double"
            elseif name == "A" then
                self:SetView(self.holdFocus)
                return true
            elseif name == "DOWN" then
                self.zone = "pad"
            elseif name == "B" then
                return false
            end
            C:Render()
            return true
        end
        if name == "RIGHT" and self.layer == M.LAYERS[#M.LAYERS] then
            self.holdFocus = "hold"
            C:Render()
            return true
        end
        if name == "LEFT" or name == "RIGHT" then
            local index = 1
            for i, layer in ipairs(M.LAYERS) do
                if layer == self.layer then index = i end
            end
            index = math.max(1, math.min(#M.LAYERS, index + (name == "LEFT" and -1 or 1)))
            self.layer = M.LAYERS[index]
        elseif name == "DOWN" or name == "A" then
            self.zone = "pad"
        elseif name == "B" then
            if self.assign then
                self.assign = nil
            else
                return false
            end
        end
        C:Render()
        return true
    end
    if self.zone == "actions" then
        if name == "LEFT" or name == "RIGHT" then
            self.act = math.max(1, math.min(#self.frame.actions, self.act + (name == "LEFT" and -1 or 1)))
        elseif name == "UP" or name == "B" then
            self.zone = "pad"
        elseif name == "A" then
            self:Act(self.act)
            return true
        end
        C:Render()
        return true
    end
    if DIRS[name] then
        local to = self:Nearest(self.node, name)
        if to then
            self.node = to
        elseif name == "UP" then
            self.zone = "layers"
        elseif name == "DOWN" and not self.assign then
            self.zone = "actions"
        end
        C:Render()
        return true
    end
    if self.assign then
        if name == "A" then
            self:AssignWheel()
        elseif name == "B" then
            self.assign = nil
            C:Render()
        end
        return true
    end
    if name == "A" then
        self:Choose()
    elseif name == "X" then
        self:Clear()
    elseif name == "Y" then
        local input = self:Focused()
        if input and input.paddle and not self.hold then
            self:LearnKey()
        else
            self:ToggleHold()
        end
    elseif name == "B" then
        return false
    end
    return true
end

function W:OnUpdate()
    -- A slot changed (placed from here, or by the game): drawn again
    if self.slotsChanged then
        self.slotsChanged = false
        C:Render()
    end
    -- Holding LT / RT shows their layer
    local held = P.HeldLayer()
    if held ~= self.heldLayer then
        self.heldLayer = held
        C:Render()
    end
end

---------------------------------------------------------------------------
-- Home > Gamepad: the gamepad bar, what shows next to it, RT as a modifier,
-- the touchpad buttons
---------------------------------------------------------------------------
local function displayRows(b)
    local s = settings()
    local f = s.features
    -- The module: the free buttons' functions, the paddles, the extra
    -- buttons and what shows next to the bar (the rows it turns on are
    -- greyed while it is off)
    local yours = 0
    for _ in pairs(s.mapping) do yours = yours + 1 end
    for _ in pairs(s.replaced) do yours = yours + 1 end
    b.module({ id = "m_map", off = L.OFF_MAPPING, sub = L.OFF_MAPPING_SUB, label = L.LBL_GAMEPAD_EXTRAS, status = format(L.STATUS_YOURS, yours), tip = L.MOD_MAPPING,
        get = function() return s.modules.mapping end,
        set = function(v)
            s.modules.mapping = v
            M:Apply()
            P:Apply()
        end,
        onY = function() C:SetTab("gamepad") end, yVerb = L.V_SETTINGS })
    local on = s.modules.mapping and true or false
    b.header(L.HDR_GAMEPAD_BAR)
    -- Its size: the game's whole gamepad bar, what the addon adds following
    b.choice({ id = "d_bar_size", label = L.LBL_BAR_SIZE, tip = L.TIP_BAR_SIZE,
        text = function() return format("%d %%", math.floor(P:BarScale() * 100 + 0.5)) end,
        step = function(d) P:ScaleBar(d) end })
    b.check({ id = "d_range", label = L.LBL_RANGE_TINT, tip = L.TIP_RANGE_TINT,
        get = function() return f.rangeTint == true end,
        set = function(v)
            f.rangeTint = v
            CK.Range:Apply()
        end })
    b.check({ id = "d_toggle", label = L.LBL_TRIGGER_TOGGLE, disabled = not on, tip = L.TIP_TRIGGER_TOGGLE,
        get = function() return f.triggerToggle == true end,
        set = function(v)
            f.triggerToggle = v
            M:Apply()
        end })
    b.check({ id = "d_toggle_combat", label = L.LBL_TOGGLE_COMBAT, indent = true,
        disabled = not (on and f.triggerToggle), tip = L.TIP_TOGGLE_COMBAT,
        get = function() return f.toggleCombatRelease == true end,
        set = function(v) f.toggleCombatRelease = v end })
    b.header(L.HDR_NEXT_TO_BAR)
    b.check({ id = "d_extra", label = L.LBL_EXTRA_BUTTONS, disabled = not on, tip = L.FEAT_EXTRA_DISPLAY,
        get = function() return f.extraDisplay end,
        set = function(v)
            f.extraDisplay = v
            P:Apply()
        end })
    b.check({ id = "d_sticks", label = L.LBL_L3_R3, indent = true, disabled = not (on and f.extraDisplay), tip = L.FEAT_SHOW_STICKS,
        get = function() return f.showSticks end,
        set = function(v)
            f.showSticks = v
            P:Apply()
        end })
    -- Fork CoolerMgdn: a PlayStation pad's Create and mic, with what they run
    if M.PlayStation() then
        b.check({ id = "d_padbtn", label = L.LBL_EXTRA_PAD_BUTTONS, indent = true,
            disabled = not (on and f.extraDisplay), tip = L.TIP_EXTRA_PAD_BUTTONS,
            get = function() return f.extraPadButtons ~= false end,
            set = function(v)
                f.extraPadButtons = v
                P:Apply()
            end })
    end
    b.check({ id = "d_free", label = L.LBL_FREE_PLACE, indent = true, disabled = not (on and f.extraDisplay), tip = L.TIP_FREE_PLACE,
        get = function() return s.extraFree end,
        set = function(v)
            -- Leaving it: each button on its nearest fixed place
            s.extraFree = v
            if not v then P:SnapAll() end
            P:Apply()
        end })
    b.choice({ id = "d_badge", label = L.LBL_BUTTON_NAMES, indent = true, disabled = not (on and f.extraDisplay), tip = L.OPT_BADGE,
        text = function() return L["BADGE_" .. (s.badgePlace or "outer"):upper()] end,
        step = function(d)
            local list, index = P.BADGE_PLACES, 1
            for i, key in ipairs(list) do
                if key == s.badgePlace then index = i end
            end
            s.badgePlace = list[(index - 1 + d) % #list + 1]
            P:Apply()
        end })
    -- Fork CoolerMgdn: how long a hold is (HoldClock.lua)
    b.choice({ id = "d_hold", label = L.LBL_HOLD_TIME, disabled = not on, tip = L.TIP_HOLD_TIME,
        text = function()
            local a, c = CK.HoldClock:Range()
            return format(L.HOLD_RANGE, a, c)
        end,
        step = function(d)
            if CK:BlockedByCombat() then return end
            CK.HoldClock:SetTicks(CK.HoldClock:Ticks() + d)
        end })
    b.check({ id = "d_holdicon", label = L.LBL_HOLD_ICON, indent = true, disabled = not on, tip = L.TIP_HOLD_ICON,
        get = function() return s.holdIcon ~= false end,
        set = function(v) s.holdIcon = v end })
    if M:CanBeModifier("PADRTRIGGER") then
        b.header(L.HDR_LAYERS)
        b.check({ id = "d_rt", label = L.LBL_RT_MODIFIER, tip = L.FEAT_RT_MODIFIER_TIP,
            get = function() return M:TriggerModifier("PADRTRIGGER") ~= nil end,
            set = function(v) M:SetTriggerModifier("PADRTRIGGER", v) end })
    end
end

-- Extra buttons (more buttons, or touchpads set as buttons): each one turned on here
local function touchRows(b)
    local s = settings()
    s.touchButtons = s.touchButtons or {}
    b.header(L.SEC_TOUCH)
    b.info(L.TIP_SEC_TOUCH)
    for _, side in ipairs({ "L", "R" }) do
        b.header(L["HDR_TOUCH_" .. side])
        for n = 1, 4 do
            local id = "T" .. side .. n
            b.check({ id = "t_" .. id, label = id, disabled = not s.modules.mapping, tip = L.TIP_SEC_TOUCH,
                get = function() return s.touchButtons[id] == true end,
                set = function(v)
                    s.touchButtons[id] = v or nil
                    M:Apply()
                    P:Apply()
                end })
        end
    end
end

-- Fork CoolerMgdn: Comfort > Handy: items for a spell, quick bank moves
function W.HandyRows(b)
    local s = settings()
    b.header(L.HDR_HANDY)
    b.check({ id = "h_itemt", label = L.LBL_ITEMT, tip = L.TIP_ITEMT,
        get = function() return s.itemTarget ~= false end,
        set = function(v) s.itemTarget = v; if CK.ItemTarget then CK.ItemTarget:Check() end end })
    b.check({ id = "h_bankmove", label = L.LBL_BANKMOVE, tip = L.TIP_BANKMOVE,
        get = function() return s.bankMove ~= false end,
        set = function(v) s.bankMove = v; if CK.BankMove then CK.BankMove:Update() end end })
end

function W.DisplayRows(b)
    displayRows(b)
    touchRows(b)
end
