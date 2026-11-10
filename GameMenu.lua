local _, CK = ...
local L = CK.L

---------------------------------------------------------------------------
-- Fork CoolerMgdn (asked): "Easy Controller" in the game's main menu, after
-- Shop - one more way to open the settings. The game builds its menu's
-- buttons anew each time it opens (GameMenuFrame:InitButtons, AddButton);
-- ours is added after it, then put in its place by its layout index (the
-- order the menu lays its buttons out in), between Shop and AddOns. Its
-- click closes the menu, then opens ours.
---------------------------------------------------------------------------
local GM = {}
CK.GameMenu = GM

local function shopText()
    return BLIZZARD_STORE or "Shop"
end

-- The button whose text is this one, in the menu's pool
local function buttonOf(menu, label)
    if not (menu.buttonPool and menu.buttonPool.EnumerateActive) then return nil end
    for b in menu.buttonPool:EnumerateActive() do
        local t = b.GetText and b:GetText()
        if t == label then return b end
    end
end

function GM:Add(menu)
    if not (menu and menu.AddButton) then return end
    local ok, ours = pcall(menu.AddButton, menu, "DualSense Forever", function()
        if HideUIPanel then pcall(HideUIPanel, menu) else menu:Hide() end
        if CK.Config and CK.Config.Open then
            C_Timer.After(0, function() CK.Config:Open() end)
        end
    end)
    if not ok then
        if CK.Flight then CK.Flight:Note("game menu: our button refused (%s)", tostring(ours)) end
        return
    end
    -- Its place: just after Shop (before the gap to AddOns), when the menu
    -- lays its buttons out by index
    local shop = buttonOf(menu, shopText())
    ours = (type(ours) == "table" and ours) or buttonOf(menu, "DualSense Forever")
    if shop and ours and shop.layoutIndex and ours.layoutIndex then
        ours.layoutIndex = shop.layoutIndex + 0.5
        -- (the space Shop had under it: after ours now)
        if shop.bottomPadding ~= nil then
            ours.bottomPadding, shop.bottomPadding = shop.bottomPadding, ours.bottomPadding
        end
        if menu.MarkDirty then pcall(menu.MarkDirty, menu) end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    local menu = GameMenuFrame
    if not menu then return end
    if menu.InitButtons then
        hooksecurefunc(menu, "InitButtons", function(self) GM:Add(self) end)
    elseif CK.Flight then
        CK.Flight:Note("game menu: no InitButtons on this client, no button of ours")
    end
end)
