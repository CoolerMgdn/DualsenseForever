local _, CK = ...
local L = CK.L

---------------------------------------------------------------------------
-- Fork CoolerMgdn: actions that pick what they do by themselves (the idea:
-- ControllerForever's Potions.lua and Fishing.lua, its author's code free
-- to reuse). Put on any button like a spell ("auto:<id>", the Gamepad tab's
-- Macros list, "Ours"):
--   auto:heal  a Healthstone ready in the bags, else the best healing potion
--   auto:mana  a mana gem ready, else the best mana potion
--   auto:fish  the fishing pole on; pressed again, the weapons worn before
--   auto:reload  the interface reloaded (/reload, the game's own command)
--   auto:screenshot  a screenshot (/run Screenshot(): tried, it works)
--   auto:follow  following the target (/follow)
-- (the game's own functions for those can't run with a trigger held)
-- Each is a secure button running a macro text, so it works in combat; what
-- the text says is worked out out of combat (bags, cooldowns, gear changed,
-- and as a fight ends): in combat it keeps the last.
---------------------------------------------------------------------------
local A = {}
CK.Auto = A

A.LIST = { "heal", "mana", "fish", "reload", "screenshot", "follow" }
A.ICONS = {
    heal = "Interface\\Icons\\INV_Potion_54",
    mana = "Interface\\Icons\\INV_Potion_76",
    fish = "Interface\\Icons\\Trade_Fishing",
    -- (the touchpad's "Reload the interface" uses the same picture)
    reload = "Interface\\Icons\\Spell_Nature_Reincarnation",
    -- (the same pictures as the game's functions in the Game list)
    screenshot = "Interface\\Icons\\INV_Misc_Spyglass_03",
    follow = "Interface\\Icons\\Ability_Tracking",
}

local tracked = {}      -- secure button -> its auto id (Mapping.lua's)
A.current = {}          -- id -> { text, item (its picture) }

local ITEM_WEAPON, POLE = 2, 20

local function isPole(id)
    if not id then return false end
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
    return classID == ITEM_WEAPON and subClassID == POLE
end

local function charKey()
    return (UnitName("player") or "?") .. "-" .. (GetNormalizedRealmName and GetNormalizedRealmName() or "?")
end

local function fishDB()
    local db = CK.db
    if type(db.fishWeapons) ~= "table" then db.fishWeapons = {} end
    local k = charKey()
    if type(db.fishWeapons[k]) ~= "table" then db.fishWeapons[k] = {} end
    return db.fishWeapons[k]
end

local function ready(id)
    local start, duration = C_Container.GetItemCooldown(id)
    if CK.Plain then start, duration = CK.Plain(start), CK.Plain(duration) end
    return not (start and duration and start > 0 and duration > 1.5 and start + duration - GetTime() > 1)
end

-- The best of a kind in the bags (ConsumableWheel.lua's kinds), ready first
local function best(kinds)
    local W = CK.ConsumableWheel
    local found = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id and not found[id] then
                local ok, cat = pcall(W.Category, id)
                local order = ok and cat and kinds[cat]
                local rank = order and W.Rank and W.Rank(id)
                if rank then found[id] = { id = id, order = order, rank = rank, ready = ready(id) } end
            end
        end
    end
    local pick
    for _, e in pairs(found) do
        if not pick then
            pick = e
        else
            -- Ready before cooling down; then the kind's order; then the best
            local better = (e.ready and not pick.ready)
                or (e.ready == pick.ready and (e.order < pick.order or (e.order == pick.order and e.rank > pick.rank)))
            if better then pick = e end
        end
    end
    return pick and pick.id
end

local KINDS = {
    heal = { healthstone = 1, healthPotion = 2 },
    mana = { manaGem = 1, manaPotion = 2 },
}

local function bestPole()
    local pick, level
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local id = C_Container.GetContainerItemID(bag, slot)
            if isPole(id) then
                local _, _, _, ilvl = (C_Item.GetItemInfo or GetItemInfo)(id)
                if not pick or (ilvl or 0) > level then pick, level = id, ilvl or 0 end
            end
        end
    end
    return pick
end

-- What each one does now: { text, item }
function A:Compute(id)
    if id == "heal" or id == "mana" then
        local item = best(KINDS[id])
        return { text = item and ("/use item:" .. item) or "", item = item }
    elseif id == "fish" then
        local main = GetInventoryItemID("player", 16)
        local w = fishDB()
        if isPole(main) then
            if not w.main then return { text = "", item = main } end
            local text = "/equipslot 16 item:" .. w.main
            if w.off then text = text .. "\n/equipslot 17 item:" .. w.off end
            return { text = text, item = w.main }
        end
        local pole = bestPole()
        return { text = pole and ("/equipslot 16 item:" .. pole) or "", item = pole }
    elseif id == "reload" then
        return { text = "/reload" }
    elseif id == "screenshot" then
        return { text = "/run Screenshot()" }
    elseif id == "follow" then
        return { text = "/follow" }
    end
    return { text = "" }
end

-- The weapons to put back, noted whenever the gear changes (no pole on)
function A:NoteWeapons()
    local main = GetInventoryItemID("player", 16)
    if not main or isPole(main) then return end
    local w = fishDB()
    w.main, w.off = main, GetInventoryItemID("player", 17)
end

function A:Refresh()
    if not CK.db or InCombatLockdown() then
        self.pending = true
        return
    end
    self.pending = nil
    self:NoteWeapons()
    for _, id in ipairs(A.LIST) do self.current[id] = self:Compute(id) end
    for b, id in pairs(tracked) do
        if b.ckAuto == id then b:SetAttribute("macrotext", self.current[id].text) end
    end
    if CK.Paddles and CK.Paddles.frame then CK.Paddles:Refresh(true) end
end

-- Mapping.lua: a secure button made to run one (out of combat)
function A:Setup(b, id)
    tracked[b] = id
    b.ckAuto = id
    b:SetAttribute("type", "macro")
    local now = self.current[id] or self:Compute(id)
    self.current[id] = now
    b:SetAttribute("macrotext", now.text)
end

function A:Name(id)
    return L["AUTO_" .. id:upper()] or id
end

function A:Icon(id)
    local now = self.current[id]
    local item = now and now.item
    return item and C_Item.GetItemIconByID(item) or A.ICONS[id]
end

local f = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "PLAYER_REGEN_ENABLED",
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP" }) do
    pcall(f.RegisterEvent, f, event)
end
local queued
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" and not A.pending then return end
    if queued then return end
    queued = true
    C_Timer.After(event == "PLAYER_LOGIN" and 2 or 0.3, function()
        queued = nil
        A:Refresh()
    end)
end)
