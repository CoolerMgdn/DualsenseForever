local _, CK = ...
local L = CK.L

---------------------------------------------------------------------------
-- Fork CoolerMgdn: quick bank moves (the idea and the way: ControllerForever's
-- BankMove.lua, its author's code free to reuse). At a banker each item
-- took four steps (A picks it up, LT to the other window, the D-pad to a
-- free slot, A puts it down). With the bank open, out of combat, the game's
-- cursor on an item in your bags or in the bank: X moves it to the other
-- side in one press ("X: To bank" / "X: To bags" beside it). The press is
-- the game's own right-click on that slot (a mouse's right-click there):
-- X clicks a secure button of ours, type "click", aimed at the slot the
-- cursor is on, with the right button. The cursor is followed with a hook
-- (reads only); X is bound only while it is on such a slot.
---------------------------------------------------------------------------
local BM = {}
CK.BankMove = BM

local KEY = "PAD3"
local button, owner, hint
local current           -- the game's slot button the cursor is on

local function on()
    -- (our gamepad bags at the bank move items themselves: Bags.lua)
    if CK.Bags and CK.Bags.open and CK.Bags.bankMode then return false end
    return CK.db and CK.db.settings.bankMove ~= false
end

local function bankOpen()
    return BankFrame and BankFrame:IsShown() and true or false
end

-- "bank" (a bank slot), "bags" (one of your bags'), or nil
local function sideOf(b)
    if type(b) ~= "table" or not b.GetName then return nil end
    local ok, name = pcall(b.GetName, b)
    name = ok and name or ""
    if name:find("^BankFrameItem%d+$") then return "bank" end
    local parent = b.GetParent and b:GetParent()
    local bag = b.GetBagID and select(2, pcall(b.GetBagID, b))
    if type(bag) ~= "number" and parent and parent.GetID then bag = parent:GetID() end
    if type(bag) == "number" then
        if bag == -1 or bag > (NUM_BAG_SLOTS or 4) then return "bank" end
        if bag >= 0 and (name:find("^ContainerFrame") or (parent and parent.GetName and (parent:GetName() or ""):find("^ContainerFrame"))) then
            return "bags"
        end
    end
    return nil
end

local function hasItem(b)
    local icon = b.icon or b.Icon or (b.GetName and _G[(b:GetName() or "") .. "IconTexture"])
    if icon and icon.IsShown and not icon:IsShown() then return false end
    local tex = icon and icon.GetTexture and icon:GetTexture()
    return tex ~= nil
end

function BM:Build()
    if button then return end
    button = CK.NewFrame("Button", "ControllerKeyboardBankMove", UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyDown")
    button:SetAttribute("useOnKeyDown", true)
    button:SetAttribute("type", "click")
    button:Hide()
    button:HookScript("OnClick", function()
        if CK.Flight then CK.Flight:Note("bank move: %s", tostring(current and current:GetName())) end
    end)
    owner = CK.NewFrame("Frame")
    CK.Binds:Register("bankmove", owner, 40, true, { label = "bank move" })
    hint = CK.NewFrame("Frame", nil, UIParent)
    hint:SetFrameStrata("TOOLTIP")
    hint:SetSize(120, 22)
    hint.bg = hint:CreateTexture(nil, "BACKGROUND")
    hint.bg:SetAllPoints()
    hint.bg:SetColorTexture(0, 0, 0, 0.75)
    hint.glyph = hint:CreateTexture(nil, "ARTWORK")
    hint.glyph:SetSize(18, 18)
    hint.glyph:SetPoint("LEFT", 4, 0)
    hint.text = hint:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint.text:SetPoint("LEFT", hint.glyph, "RIGHT", 4, 0)
    hint:Hide()
end

function BM:Update()
    if InCombatLockdown() or not owner then return end
    local side = on() and bankOpen() and current and current:IsVisible() and hasItem(current) and sideOf(current)
    if side then
        button:SetAttribute("clickbutton", current)
        CK.Binds:Set("bankmove", KEY, "click", button:GetName(), "RightButton")
        CK:SetGlyph(hint.glyph, "X")
        hint.text:SetText(side == "bags" and L.BANK_TO_BANK or L.BANK_TO_BAGS)
        hint:SetWidth((hint.text:GetStringWidth() or 60) + 30)
        hint:ClearAllPoints()
        hint:SetPoint("TOPLEFT", current, "BOTTOMRIGHT", -6, 6)
        hint:Show()
    else
        button:SetAttribute("clickbutton", nil)
        CK.Binds:Clear("bankmove")
        hint:Hide()
    end
end

local hooked = false
local function hook()
    if hooked or not (SmartNavigation and SmartNavigation.SelectButton) then return end
    hooked = true
    hooksecurefunc(SmartNavigation, "SelectButton", function(_, b)
        current = b
        if bankOpen() then C_Timer.After(0, function() BM:Update() end) end
    end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        BM:Build()
        hook()
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        -- The fight: X back to what it is without us (set out of one only)
        if owner then CK.Binds:Clear("bankmove") end
        if hint then hint:Hide() end
        return
    end
    if event == "BANKFRAME_CLOSED" then current = nil end
    hook()
    C_Timer.After(0.05, function() BM:Update() end)
end)
