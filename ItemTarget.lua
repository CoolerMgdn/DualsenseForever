local _, CK = ...
local L = CK.L

---------------------------------------------------------------------------
-- Fork CoolerMgdn: enchants, oils, poisons, sharpening stones, Pick Lock,
-- Disenchant... (the idea and the way: ControllerForever's ItemTarget.lua,
-- its author's code free to reuse). Those spells leave a hand on the
-- cursor, waiting for a click on an item: with a gamepad, a long walk with
-- the game's cursor. While one waits (out of combat), a list of ours comes
-- up with the items it can go on, worn first, then the bags:
--     D-pad up / down   the item     left / right   a page
--     A                 put it on    B              cancel the spell
-- Nothing of ours casts or uses an item: A is a secure button of ours with
-- only "target-bag" / "target-slot" set, which the game's own secure code
-- turns into a click on that slot while a spell waits for an item
-- (SecureTemplates.lua); B is the secure "stop" action. A popup of the
-- game's ("Replace the enchant?") gets the pad's A / B back while it shows.
---------------------------------------------------------------------------
local IT = {}
CK.ItemTarget = IT

local ROWS, ROW_H, WIDTH = 8, 34, 340
local WEAPON, ARMOR = 2, 4
local DISENCHANT, PICK_LOCK = 13262, 1804
local NO_DISENCHANT = { INVTYPE_BODY = true, INVTYPE_TABARD = true, INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_AMMO = true }

local state = { list = {}, index = 1, top = 1 }
IT.state = state

local function on()
    return CK.db and CK.db.settings.itemTarget ~= false
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

local function waiting()
    return call(SpellIsTargeting) and (call(SpellCanTargetItem) or call(SpellCanTargetItemID)) and true or false
end

local function targetSpell()
    return C_Spell and call(C_Spell.GetTargetSpellID)
end

local function itemClass(id)
    local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
    return classID, subClassID, equipLoc
end

-- What the waiting spell is
local function kind()
    local id = targetSpell()
    if id == DISENCHANT then return "disenchant" end
    if id == PICK_LOCK then return "lockpick" end
    if C_Spell and call(C_Spell.TargetSpellIsEnchanting) then return "enchant" end
    if C_Spell and call(C_Spell.TargetSpellChecksItemCondition) then return "condition" end
    return "any"
end

local function matches(k, e)
    if not ItemLocation then return nil end
    local loc
    if e.bag then loc = call(ItemLocation.CreateFromBagAndSlot, ItemLocation, e.bag, e.slot)
    else loc = call(ItemLocation.CreateFromEquipmentSlot, ItemLocation, e.invSlot) end
    if not loc then return nil end
    local fn = k == "enchant" and C_Item.DoesItemMatchTargetEnchantingSpell
        or k == "condition" and C_Item.DoesItemMatchSpellItemCondition
    if type(fn) ~= "function" then return nil end
    local ok, fits = pcall(fn, loc)
    if not ok then return nil end
    return fits and true or false
end

local function locked(bag, slot)
    local data = C_TooltipInfo and call(C_TooltipInfo.GetBagItem, bag, slot)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return false end
    for _, line in ipairs(data.lines) do
        if type(line) == "table" and line.leftText == (LOCKED or "Locked") then return true end
    end
    return false
end

local function everything()
    local list = {}
    for slot = 1, 19 do
        local id = GetInventoryItemID("player", slot)
        if id then
            list[#list + 1] = { id = id, invSlot = slot, icon = GetInventoryItemTexture("player", slot),
                quality = GetInventoryItemQuality("player", slot), name = C_Item.GetItemNameByID(id), worn = true }
        end
    end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                list[#list + 1] = { id = info.itemID, bag = bag, slot = slot, icon = info.iconFileID, quality = info.quality,
                    name = info.itemName or C_Item.GetItemNameByID(info.itemID), count = info.stackCount }
            end
        end
    end
    return list
end

local function gather(k)
    local all, list = everything(), {}
    if k == "disenchant" then
        for _, e in ipairs(all) do
            local classID, _, equipLoc = itemClass(e.id)
            if e.bag and (e.quality or 0) >= 2 and (e.quality or 0) <= 4 and (classID == WEAPON or classID == ARMOR)
                and equipLoc and equipLoc ~= "" and not NO_DISENCHANT[equipLoc] then
                list[#list + 1] = e
            end
        end
        return list
    end
    if k == "lockpick" then
        for _, e in ipairs(all) do
            if e.bag and locked(e.bag, e.slot) then list[#list + 1] = e end
        end
        return list
    end
    if k ~= "any" then
        local said = false
        for _, e in ipairs(all) do
            local fits = matches(k, e)
            if fits ~= nil then said = true end
            if fits == nil and k == "enchant" then
                local classID = itemClass(e.id)
                fits = classID == WEAPON or classID == ARMOR
            end
            if fits then list[#list + 1] = e end
        end
        if #list > 0 or said then return list end
    end
    -- The game can't say: gear first, then the rest
    for _, e in ipairs(all) do
        local classID = itemClass(e.id)
        if classID == WEAPON or classID == ARMOR then list[#list + 1] = e end
    end
    for _, e in ipairs(all) do
        local classID = itemClass(e.id)
        if not (classID == WEAPON or classID == ARMOR) then list[#list + 1] = e end
    end
    return list
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local frame, apply, stop, owner

local function popupOpen()
    for i = 1, 4 do
        local p = _G["StaticPopup" .. i]
        if p and p:IsVisible() then return true end
    end
    return false
end

local function plainButton(name, fn)
    local b = CK.NewFrame("Button", name, UIParent)
    b:Hide()
    b:SetScript("OnClick", fn)
    return b
end

function IT:Build()
    if frame then return end
    frame = CK.NewFrame("Frame", "ControllerKeyboardItemTarget", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, 64 + ROWS * ROW_H)
    frame:SetPoint("RIGHT", UIParent, "CENTER", -120, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0.04, 0.03, 0.02, 0.92)
    frame:SetBackdropBorderColor(0.75, 0.6, 0.3, 1)
    frame:Hide()
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 14, -12)
    frame.title:SetPoint("TOPRIGHT", -14, -12)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)
    frame.rows = {}
    for i = 1, ROWS do
        local r = CK.NewFrame("Frame", nil, frame)
        r:SetSize(WIDTH - 20, ROW_H - 2)
        r:SetPoint("TOPLEFT", 10, -38 - (i - 1) * ROW_H)
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetColorTexture(1, 0.82, 0.3, 0.18)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(ROW_H - 6, ROW_H - 6)
        r.icon:SetPoint("LEFT", 3, 0)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -1)
        r.name:SetPoint("RIGHT", -6, 0)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.place = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.place:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 1)
        frame.rows[i] = r
    end
    frame.help = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.help:SetPoint("BOTTOM", 0, 10)
    -- A: the game's own click on the slot (secure), B: the spell stopped
    apply = CK.NewFrame("Button", "ControllerKeyboardItemTargetApply", UIParent, "SecureActionButtonTemplate")
    apply:RegisterForClicks("AnyDown")
    apply:SetAttribute("useOnKeyDown", true)
    apply:Hide()
    apply:HookScript("OnClick", function()
        if CK.Flight then CK.Flight:Note("item target: A on %s", tostring(state.list[state.index] and state.list[state.index].name)) end
        C_Timer.After(0.2, function() IT:Check() end)
    end)
    stop = CK.NewFrame("Button", "ControllerKeyboardItemTargetStop", UIParent, "SecureActionButtonTemplate")
    stop:RegisterForClicks("AnyDown")
    stop:SetAttribute("useOnKeyDown", true)
    stop:SetAttribute("type", "stop")
    stop:Hide()
    IT.moves = {
        up = plainButton("ControllerKeyboardItemTargetUp", function() IT:Move(-1) end),
        down = plainButton("ControllerKeyboardItemTargetDown", function() IT:Move(1) end),
        left = plainButton("ControllerKeyboardItemTargetLeft", function() IT:Move(-ROWS) end),
        right = plainButton("ControllerKeyboardItemTargetRight", function() IT:Move(ROWS) end),
    }
    owner = CK.NewFrame("Frame")
    CK.Binds:Register("itemtarget", owner, 60, true, { label = "item list" })
end

function IT:Aim()
    if InCombatLockdown() or not apply then return end
    local e = state.list[state.index]
    apply:SetAttribute("target-bag", e and e.bag or nil)
    apply:SetAttribute("target-slot", e and (e.bag and e.slot or e.invSlot) or nil)
end

function IT:Bind()
    if InCombatLockdown() or not owner then return end
    CK.Binds:Clear("itemtarget")
    if not frame:IsShown() or popupOpen() then return end
    local function click(key, b) CK.Binds:Set("itemtarget", key, "click", b:GetName(), "LeftButton") end
    click("PADDUP", IT.moves.up)
    click("PADDDOWN", IT.moves.down)
    click("PADDLEFT", IT.moves.left)
    click("PADDRIGHT", IT.moves.right)
    if state.list[state.index] then click("PAD1", apply) end
    click("PAD2", stop)
end

function IT:Move(d)
    local n = #state.list
    if n == 0 then return end
    if math.abs(d) == 1 then
        state.index = (state.index - 1 + d) % n + 1
    else
        state.index = math.max(1, math.min(n, state.index + d))
    end
    if state.index < state.top then state.top = state.index end
    if state.index >= state.top + ROWS then state.top = state.index - ROWS + 1 end
    self:Aim()
    self:Paint()
end

function IT:Paint()
    if not frame then return end
    local name = targetSpell() and C_Spell.GetSpellName(targetSpell()) or ""
    frame.title:SetText(format(L.ITEMT_TITLE, name or ""))
    for i, r in ipairs(frame.rows) do
        local e = state.list[state.top + i - 1]
        r:SetShown(e ~= nil)
        if e then
            r.icon:SetTexture(e.icon)
            local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality or 1]
            r.name:SetText(e.name or ("item:" .. e.id))
            if color then r.name:SetTextColor(color.r, color.g, color.b) end
            r.place:SetText(e.worn and L.ITEMT_WORN or ((e.count and e.count > 1) and format(L.ITEMT_BAG_N, e.count) or L.ITEMT_BAG))
            r.bg:SetShown(state.top + i - 1 == state.index)
        end
    end
    frame.help:SetText(#state.list == 0 and L.ITEMT_NONE or L.ITEMT_HELP)
end

function IT:Open()
    self:Build()
    state.list = gather(kind())
    state.index, state.top = 1, 1
    state.spell = targetSpell()
    frame:Show()
    self:Aim()
    self:Paint()
    self:Bind()
end

function IT:Close()
    if not frame or not frame:IsShown() then return end
    frame:Hide()
    state.list, state.spell = {}, nil
    if not InCombatLockdown() then
        self:Aim()
        CK.Binds:Clear("itemtarget")
    end
end

-- A spell waiting now, or not any more
function IT:Check()
    if InCombatLockdown() then return end
    if on() and waiting() then
        if not (frame and frame:IsShown()) or state.spell ~= targetSpell() then
            self:Open()
        else
            -- The bags changed (an item gone): the list again, same place
            local keep = state.index
            state.list = gather(kind())
            state.index = math.min(keep, math.max(1, #state.list))
            self:Aim()
            self:Paint()
            self:Bind()
        end
    else
        self:Close()
    end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "CURRENT_SPELL_CAST_CHANGED", "CURSOR_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "UNIT_INVENTORY_CHANGED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- The fight: the list and its keys go (they are set out of one only)
        if frame and frame:IsShown() then
            frame:Hide()
            CK.Binds:Clear("itemtarget")
        end
        return
    end
    C_Timer.After(0.05, function() IT:Check() end)
end)
-- The game's popup ("Replace the enchant?") gets the pad's A / B while up
local popupWas
C_Timer.NewTicker(0.25, function()
    if not (frame and frame:IsShown()) or InCombatLockdown() then return end
    local p = popupOpen()
    if p ~= popupWas then
        popupWas = p
        IT:Bind()
    end
    if not waiting() then IT:Close() end
end)
