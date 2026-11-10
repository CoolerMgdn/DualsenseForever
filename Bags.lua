local _, CK = ...
local L = CK.L

---------------------------------------------------------------------------
-- Fork CoolerMgdn: our bags, compact (asked: ControllerForever's Controller
-- Bags, its Simple layout, in its look; its author's code free to reuse:
-- Inv.lua, Inv_Simple.lua, Kit_Grid.lua, Kit_Look.lua and its window art).
--
-- A small window where the game's bags open (bottom right, about their
-- size): a slim header (Bags, the free slots, your gold), every item at
-- once in one grid, in sections (New, Quest, Use, Gear, Trade Goods,
-- Other, Junk) each with a small label, the free slots as one wide tile,
-- and two lines of hints. The lit item's tooltip is the game's, beside it.
--     D-pad          move               A        pick up / put down
--     X              the item's job: the game's own right-click on its
--                    slot (use, equip, open, read), as the game
--     Y              more (split, search, destroy)
--     LB / RB        the previous / next section
--     R3             search (the addon's keyboard)
--     B              put back what you hold, else close the bags
--
-- An option (Comfort > Bags), off at first. Nothing of the game's is
-- hidden, moved or written on (the taint we met twice): its bags stay open
-- under ours, faded by an animation owned by a frame of ours; X and B
-- click the game's own buttons through secure buttons of ours, set out of
-- combat. Ours stays shut (the game's bags as they are) at a vendor, the
-- bank, the mail, trade, an auction house, the character window, while a
-- spell waits for an item, and in combat (stage 1: it closes as a fight
-- starts, the game's bags come back).
---------------------------------------------------------------------------
local B = {}
CK.Bags = B

local TEX = "Interface\\AddOns\\DualsenseForever\\textures\\bags\\"
local COLOR = {
    text = { 0.949, 0.933, 0.902 }, light = { 0.831, 0.808, 0.769 }, grey = { 0.659, 0.635, 0.604 },
    focus = { 1, 0.886, 0.627 }, gold = { 1, 0.82, 0.36 }, goldDim = { 0.7, 0.54, 0.26 },
    good = { 0.247, 0.831, 0.416 }, warn = { 0.949, 0.702, 0.239 }, bad = { 0.898, 0.325, 0.239 },
}
local PAD, HEAD, HINT, GAP = 14, 44, 52, 6
local MIN_W, MAX_W, MIN_H = 380, 560, 200
local TILE, TILE_GAP, TILE_MIN = 36, 4, 28
local LABEL_H, SECTION_GAP = 18, 6
local CORNER, BAND = 64, 16
-- Fork CoolerMgdn (asked): the game's look (its bag window): its slot size,
-- its spacing; the room its frame takes (title bar and search above, the
-- money bar below)
local GTILE, GGAP = 37, 5
-- (GHINTS: the room kept under the window for the hints' box - with a
-- message over its hints it is about this tall: found off the screen at 64)
local GLEFT, GRIGHT, GTOP, GMONEY, GHINTS = 8, 8, 52, 24, 104
local GCOLS = 10
local GPAD = 5          -- room round the slots inside their scroll (their light not cut)
local HINT_GLYPH = 20   -- the hints' glyphs, as the game's
local HINT_FONT, HINT_GAP, HINT_PAD = 12, 16, 12
local MENU_ROW, MENU_PAD = 30, 8   -- Y's menu: its rows, the room above and under them
local GAME_GOLD, GAME_GREY = { 1, 0.82, 0 }, { 0.5, 0.5, 0.5 }
local QUICKSLOT = 64 / 37   -- the game's slot frame (UI-Quickslot2) over a 37 px button
local PREFIXES = { "", "SHIFT-", "CTRL-", "ALT-", "CTRL-SHIFT-", "ALT-SHIFT-", "ALT-CTRL-", "ALT-CTRL-SHIFT-" }
local POLL = 0.1

local function settings() return CK.db.settings end
local function on() return CK.db and settings().ownBags == true end

-- The look (ControllerForever's Controller Bags options, all of them)
B.LOOK_DEFAULTS = { layout = "blizzard", order = "kind", itemLevel = true, levelQuality = false, marks = true, newGlow = true,
    junkCoin = true, edgeColor = "quality", edgeSize = 2, coinLetters = false, scale = 1, emptySlots = false,
    bgAlpha = 1 }
B.ORDERS = { "kind", "bags", "one" }
-- (Fork CoolerMgdn, asked: "blizzard", the game's own bag window's look,
-- the default)
B.LAYOUTS = { "blizzard", "compact", "full" }
B.EDGE_COLORS = { "quality", "accent", "black" }
B.EDGE_SIZES = { 1, 2, 3 }
local function look()
    local s = settings()
    if type(s.bagsLook) ~= "table" then s.bagsLook = {} end
    local t = s.bagsLook
    for k, v in pairs(B.LOOK_DEFAULTS) do
        if t[k] == nil then t[k] = v end
    end
    -- Fork CoolerMgdn: the game's look given once to those who had one
    -- already (asked: it is the default)
    if not t.gameLookGiven then
        t.gameLookGiven = true
        t.layout = "blizzard"
    end
    return t
end
B.Look = look

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

local function shown(name)
    local f = _G[name]
    if type(f) ~= "table" or type(f.IsShown) ~= "function" then return false end
    local ok, s = pcall(f.IsShown, f)
    return ok and s and true or false
end

local function bagsShown()
    if shown("ContainerFrameCombinedBags") then return true end
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        if shown("ContainerFrame" .. i) then return true end
    end
    return false
end

local function font(fs, size)
    pcall(fs.SetFont, fs, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
end

local function text(parent, size, color, justify, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", "GameFontNormal")
    font(fs, size)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    local c = color or COLOR.text
    fs:SetTextColor(c[1], c[2], c[3])
    return fs
end

local function paint(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

local function qualityColor(q)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return { c.r, c.g, c.b } end
    return { 1, 1, 1 }
end

local function fold(s)
    s = tostring(s or "")
    if CaseAccentInsensitiveParse then
        local ok, r = pcall(CaseAccentInsensitiveParse, s)
        if ok and r then return r end
    end
    return CK.Normalize and CK.Normalize(s) or s:lower()
end

---------------------------------------------------------------------------
-- The items, read and grouped (Inv.lua's)
---------------------------------------------------------------------------
B.KINDS = { "new", "quest", "use", "gear", "trade", "other", "junk" }
B.KIND_ICON = {
    new = TEX .. "P_Star", quest = "Interface\\GossipFrame\\AvailableQuestIcon", use = "Interface\\Icons\\INV_Potion_51",
    gear = "Interface\\Icons\\INV_Shirt_White_01", trade = "Interface\\Icons\\INV_Fabric_Linen_01",
    other = "Interface\\Icons\\INV_Misc_Bag_07", junk = "Interface\\MoneyFrame\\UI-CopperIcon",
}

local function itemOf(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if type(info) ~= "table" or not info.itemID then return nil end
    local item = { bag = bag, slot = slot, key = bag .. ":" .. slot, itemID = info.itemID, link = info.hyperlink,
        icon = info.iconFileID, count = tonumber(info.stackCount) or 1, quality = info.quality,
        locked = info.isLocked and true or false, hasLoot = info.hasLoot and true or false,
        readable = info.isReadable and true or false, noValue = info.hasNoValue and true or false,
        bound = info.isBound and true or false }
    local _, _, _, equipLoc, icon, classID, subclassID = C_Item.GetItemInfoInstant(item.itemID)
    item.classID, item.subclassID, item.equipLoc = classID, subclassID, equipLoc
    item.icon = item.icon or icon
    local getInfo = C_Item.GetItemInfo or GetItemInfo
    local name, _, quality, level, _, _, subType, _, _, _, sellPrice = getInfo(item.link or item.itemID)
    item.name = name or (item.link and item.link:match("%[(.-)%]")) or ("item " .. item.itemID)
    item.sellPrice, item.subType, item.level = tonumber(sellPrice), subType, tonumber(level)
    item.quality = item.quality or quality
    local q = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
    if type(q) == "table" then
        item.quest = (q.isQuestItem or q.questID) and true or false
        item.questStart = q.questID and not q.isActive and true or false
    end
    item.new = C_NewItems and C_NewItems.IsNewItem and C_NewItems.IsNewItem(bag, slot) and true or false
    item.spell = (C_Item.GetItemSpell or GetItemSpell)(item.itemID) ~= nil
    local start, duration, enable = C_Container.GetContainerItemCooldown(bag, slot)
    if tonumber(duration) and duration > 1.5 and enable ~= 0 and enable ~= false then
        item.cooldown = { start = tonumber(start) or 0, duration = duration }
    end
    return item
end

-- A bag's picture, for its empty slots (the backpack's own; the bank's none)
local function bagPicture(bag)
    if bag == 0 then return "Interface\\Buttons\\Button-Backpack-Up" end
    if bag and bag > 0 and C_Container and C_Container.ContainerIDToInventoryID then
        local ok, inv = pcall(C_Container.ContainerIDToInventoryID, bag)
        local tex = ok and inv and GetInventoryItemTexture("player", inv)
        if tex then return tex end
    end
end
B.BagPicture = bagPicture

local function isGear(item)
    local loc = item.equipLoc
    return (item.classID == 2 or item.classID == 4) and type(loc) == "string" and loc ~= ""
        and loc ~= "INVTYPE_NON_EQUIP_IGNORE" and loc ~= "INVTYPE_BAG"
end

function B.kindOf(item)
    if item.new then return "new" end
    if item.quest or item.classID == 12 then return "quest" end
    if item.quality == 0 then return "junk" end
    if isGear(item) then return "gear" end
    if item.classID == 0 or item.hasLoot or item.readable or item.classID == 9 or item.spell then return "use" end
    if item.classID == 7 or item.classID == 5 or item.classID == 3 then return "trade" end
    return "other"
end

local SLOT_ORDER = { INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_CLOAK = 4, INVTYPE_CHEST = 5,
    INVTYPE_ROBE = 5, INVTYPE_BODY = 6, INVTYPE_TABARD = 7, INVTYPE_WRIST = 8, INVTYPE_HAND = 9, INVTYPE_WAIST = 10,
    INVTYPE_LEGS = 11, INVTYPE_FEET = 12, INVTYPE_FINGER = 13, INVTYPE_TRINKET = 14, INVTYPE_2HWEAPON = 15,
    INVTYPE_WEAPON = 16, INVTYPE_WEAPONMAINHAND = 16, INVTYPE_WEAPONOFFHAND = 17, INVTYPE_SHIELD = 17, INVTYPE_HOLDABLE = 17,
    INVTYPE_RANGED = 18, INVTYPE_RANGEDRIGHT = 18, INVTYPE_THROWN = 18, INVTYPE_RELIC = 19 }
local function bagOrder(a, b) if a.bag ~= b.bag then return a.bag < b.bag end return a.slot < b.slot end
local function byName(a, b)
    if a.name ~= b.name then return tostring(a.name) < tostring(b.name) end
    return bagOrder(a, b)
end
local SORT = {
    new = bagOrder, quest = bagOrder, other = byName,
    use = function(a, b)
        if a.itemID ~= b.itemID then
            if (a.subType or "") ~= (b.subType or "") then return tostring(a.subType or "") < tostring(b.subType or "") end
            return byName(a, b)
        end
        return bagOrder(a, b)
    end,
    gear = function(a, b)
        local sa, sb = SLOT_ORDER[a.equipLoc] or 30, SLOT_ORDER[b.equipLoc] or 30
        if sa ~= sb then return sa < sb end
        local la, lb = a.level or 0, b.level or 0
        if la ~= lb then return la > lb end
        return byName(a, b)
    end,
    trade = function(a, b)
        if a.total ~= b.total then return (a.total or 0) > (b.total or 0) end
        return byName(a, b)
    end,
    junk = function(a, b)
        local va, vb = (a.sellPrice or 0) * a.count, (b.sellPrice or 0) * b.count
        if va ~= vb then return va > vb end
        return byName(a, b)
    end,
}

-- Your bags' ids, the bank's (its own slots, then its bags)
-- (Fork CoolerMgdn: the reagent bag's slot too - Forever puts a profession
-- bag there, found: a mining bag's ore missing)
function B.BagIds()
    local ids = {}
    local last = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0)
    for bag = 0, last do ids[#ids + 1] = bag end
    return ids
end

function B.BankIds()
    local ids = { BANK_CONTAINER or -1 }
    local E = Enum and Enum.BagIndex
    local first = (E and E.BankBag_1) or ((NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0) + 1)
    for bag = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do ids[#ids + 1] = bag end
    return ids
end

-- Your bags (and the bank at a banker): { sections = { { id, title, tiles } }, free, total }
function B:Read()
    self.model = self:ReadPane(B.BagIds(), false)
    self.bankModel = self.bankMode and self:ReadPane(B.BankIds(), true) or nil
    return self.model
end

function B:ReadPane(ids, bank)
    local items, free, total = {}, {}, 0
    local totals = {}
    local slots = {}        -- every slot in the bags' order: its item, or empty
    for _, bag in ipairs(ids) do
        local _, family = C_Container.GetContainerNumFreeSlots(bag)
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            total = total + 1
            local ok, item = pcall(itemOf, bag, slot)
            if ok and item then
                items[#items + 1] = item
                totals[item.itemID] = (totals[item.itemID] or 0) + item.count
                slots[#slots + 1] = { item = item }
            else
                if (family or 0) == 0 then free[#free + 1] = { bag = bag, slot = slot } end
                slots[#slots + 1] = { bag = bag, slot = slot }
            end
        end
    end
    local words = {}
    for w in fold(self.search or ""):gmatch("%S+") do words[#words + 1] = w end
    local order = look().order
    local byKind, byBag, kept = {}, {}, {}
    for _, item in ipairs(items) do
        item.total = totals[item.itemID]
        local keep = true
        if #words > 0 then
            local name = fold(item.name)
            for _, w in ipairs(words) do
                if not name:find(w, 1, true) then keep = false break end
            end
        end
        if keep then
            kept[#kept + 1] = item
            local kind = B.kindOf(item)
            byKind[kind] = byKind[kind] or {}
            table.insert(byKind[kind], item)
            byBag[item.bag] = byBag[item.bag] or {}
            table.insert(byBag[item.bag], item)
        end
    end
    local sections = {}
    local function tilesOf(list)
        local tiles = {}
        for _, item in ipairs(list) do tiles[#tiles + 1] = self:TileOf(item) end
        return tiles
    end
    local empties = order == "one" and look().emptySlots and #words == 0
    if empties then
        -- Fork CoolerMgdn (asked): every slot, the empty ones too, as the
        -- game's own bag window shows them
        local tiles = {}
        for _, s in ipairs(slots) do
            if s.item then
                tiles[#tiles + 1] = self:TileOf(s.item)
            else
                tiles[#tiles + 1] = { key = "e" .. s.bag .. ":" .. s.slot, empty = true, bag = s.bag, slot = s.slot,
                    picture = bagPicture(s.bag) }
            end
        end
        sections[#sections + 1] = { id = "all", title = bank and L.BAGS_BANK or L.BAGS_TITLE, tiles = tiles }
    elseif order == "one" then
        -- One bag: every item as the bags hold them, backpack first, no sections
        sections[#sections + 1] = { id = "all", title = bank and L.BAGS_BANK or L.BAGS_TITLE, tiles = tilesOf(kept) }
    elseif order == "bags" then
        -- Bag by bag: each bag in turn, its name over it
        for _, bag in ipairs(ids) do
            local list = byBag[bag]
            if list then
                local name = bag == 0 and (BACKPACK_TOOLTIP or L.BAGS_BACKPACK)
                    or (bank and bag == (BANK_CONTAINER or -1) and L.BAGS_BANK)
                    or (C_Container.GetBagName and C_Container.GetBagName(bag)) or format(L.BAGS_BAG_N, bag)
                sections[#sections + 1] = { id = "bag" .. bag, title = name, tiles = tilesOf(list) }
            end
        end
    else
        for _, kind in ipairs(B.KINDS) do
            local list = byKind[kind]
            if list then
                table.sort(list, SORT[kind])
                sections[#sections + 1] = { id = kind, title = L["BAGS_KIND_" .. kind:upper()], tiles = tilesOf(list) }
            end
        end
    end
    -- The free slots: one wide tile (A on it: what you hold goes in the first)
    if #words == 0 and not empties then
        sections[#sections + 1] = { id = "free", title = L.BAGS_KIND_FREE,
            tiles = { { key = "free", wide = true, free = true, n = #free, text = format(L.BAGS_FREE_N, #free) } } }
    end
    return { sections = sections, free = free, total = total, used = #items }
end

function B:TileOf(item)
    local lk = look()
    local tile = { key = item.key, icon = item.icon, count = item.count, quality = item.quality, item = item,
        dim = item.locked, cooldown = item.cooldown }
    tile.new = item.new and lk.newGlow
    tile.mark = (item.quest or item.classID == 12) and "quest" or (lk.junkCoin and item.quality == 0 and "junk") or nil
    -- Upgrade marks: a green arrow on gear better than what you wear, a
    -- red X on gear you can wear that is worse
    local U = CK.Upgrades
    if lk.marks and isGear(item) and U and U.IsUpgrade and item.link then
        local ok, up, waiting = pcall(U.IsUpgrade, U, item.bag, item.slot, item.link)
        if ok and up == true then
            tile.verdict = "up"
        elseif ok and not waiting and U.Wearable then
            local okW, can = pcall(U.Wearable, item.bag, item.slot)
            if okW and can then tile.verdict = "down" end
        end
    end
    if lk.itemLevel and isGear(item) and item.level and item.level > 1 then
        tile.level = item.level
        tile.levelColor = lk.levelQuality and (item.quality or 0) >= 2 and qualityColor(item.quality) or nil
    end
    return tile
end

---------------------------------------------------------------------------
-- The game's windows ours works beside (asked: each with a switch of its
-- own under the main one, Comfort > Bags): there the game's own right-click
-- on a bag item sells it, attaches it, trades it, posts it; the Character
-- window takes gear from the bags. L2 goes over to that window (ours stays,
-- dimmed; the game's cursor there), R2 comes back (ControllerForever's
-- Inv.lua visit / comeBack).
---------------------------------------------------------------------------
B.WHERE = {
    { key = "vendor", frames = { "MerchantFrame" } },
    { key = "mail", frames = { "SendMailFrame", "MailFrame", "OpenMailFrame" } },
    { key = "trade", frames = { "TradeFrame" } },
    { key = "auction", frames = { "AuctionHouseFrame", "AuctionFrame" } },
    { key = "character", frames = { "CharacterFrame" } },
}

local function allowed(key)
    local at = settings().bagsAt
    return not (type(at) == "table" and at[key] == false)
end

-- The game's window open beside ours now (its key), and whether it is
-- switched on (else ours stays shut there)
function B.Where()
    for _, w in ipairs(B.WHERE) do
        for _, name in ipairs(w.frames) do
            if shown(name) then return w.key, allowed(w.key) end
        end
    end
    return nil
end

local WHERE_X = { vendor = "BAGS_X_SELL", mail = "BAGS_X_ATTACH", trade = "BAGS_X_TRADE", auction = "BAGS_X_POST" }

-- What X does on it (the game's right-click): its word, or nil; second:
-- true when the game would only say no (a vendor won't buy it, a bound
-- item can't be mailed, traded or posted)
function B.xLabel(item, where)
    if not item then return nil end
    local word = where and WHERE_X[where]
    if word then
        if where == "vendor" then
            if item.noValue or (item.sellPrice or 0) <= 0 then return L.BAGS_X_NOSELL, true end
            return L[word]
        end
        if item.bound then return L.BAGS_X_BOUND, true end
        return L[word]
    end
    if item.questStart then return L.BAGS_X_QUEST end
    if item.hasLoot then return L.BAGS_X_OPEN end
    if item.readable then return L.BAGS_X_READ end
    if isGear(item) or item.equipLoc == "INVTYPE_BAG" then return L.BAGS_X_EQUIP end
    if item.classID == 9 then return L.BAGS_X_LEARN end
    if item.spell then return L.BAGS_X_USE end
    return nil
end

---------------------------------------------------------------------------
-- The window (Kit_Look.lua's, the CF menu's ornate frame: Menu.lua
-- look.ornateFrame; its art in textures\bags). Two layouts, as Controller
-- Bags has them (Look > Window):
--   compact  a small window where the game's bags open, all items in one
--            grid with small labels, the game's tooltip beside it
--   full     a big window in the middle: the sections in a column at the
--            left, the items, the lit item's card at the right
-- At a banker (its own switch): the full window, the bank at the left and
-- your bags at the right (ControllerForever's Inv_Bank.lua).
---------------------------------------------------------------------------
local f
local panes = {}        -- [1] your bags, [2] the bank: { scroll, content, tiles, heads, title }
local FULL = { w = 1000, h = 640, column = 176, detail = 300, gap = 14, head = 60 }

local function ornate(owner)
    local back = owner:CreateTexture(nil, "BACKGROUND", nil, -8)
    back:SetAllPoints(owner)
    back:SetTexture(TEX .. "W_Back")
    owner.back = back
    local shade = owner:CreateTexture(nil, "BACKGROUND", nil, -7)
    shade:SetAllPoints(owner)
    shade:SetColorTexture(1, 1, 1, 1)
    if shade.SetGradient and CreateColor then
        pcall(shade.SetGradient, shade, "VERTICAL", CreateColor(0.01, 0.012, 0.02, 0.38), CreateColor(0.02, 0.025, 0.04, 0.12))
    else
        shade:SetColorTexture(0.01, 0.012, 0.02, 0.3)
    end
    local function edge(p1, p2, coords, horizontal)
        local t = owner:CreateTexture(nil, "OVERLAY", nil, 4)
        t:SetTexture(TEX .. "W_Edge")
        t:SetPoint(p1[1], owner, p1[1], p1[2], p1[3])
        t:SetPoint(p2[1], owner, p2[1], p2[2], p2[3])
        if horizontal then t:SetHeight(BAND) else t:SetWidth(BAND) end
        t:SetTexCoord(unpack(coords))
    end
    edge({ "TOPLEFT", CORNER, 0 }, { "TOPRIGHT", -CORNER, 0 }, { 0, 1, 0, 1 }, true)
    edge({ "BOTTOMLEFT", CORNER, 0 }, { "BOTTOMRIGHT", -CORNER, 0 }, { 0, 1, 1, 0 }, true)
    edge({ "TOPLEFT", 0, -CORNER }, { "BOTTOMLEFT", 0, CORNER }, { 0, 0, 1, 0, 0, 1, 1, 1 }, false)
    edge({ "TOPRIGHT", 0, -CORNER }, { "BOTTOMRIGHT", 0, CORNER }, { 0, 1, 1, 1, 0, 0, 1, 0 }, false)
    for _, spec in ipairs({ { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 },
        { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 } }) do
        local c = owner:CreateTexture(nil, "OVERLAY", nil, 5)
        c:SetTexture(TEX .. "W_Corner")
        c:SetSize(CORNER, CORNER)
        c:SetPoint(spec[1], owner, spec[1], 0, 0)
        c:SetTexCoord(spec[2], spec[3], spec[4], spec[5])
    end
end

-- A card (Menu.lua look.cardFrame): a dark panel, a thin gold line, small
-- ornaments in its corners
local function card(owner)
    local bg = owner:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetAllPoints()
    bg:SetColorTexture(0.03, 0.03, 0.04, 0.8)
    local lines = {}
    for i, spec in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local line = owner:CreateTexture(nil, "BORDER")
        line:SetPoint(spec[1], owner, spec[1])
        line:SetPoint(spec[2], owner, spec[2])
        if spec[3] then line:SetHeight(1) else line:SetWidth(1) end
        line:SetColorTexture(COLOR.goldDim[1], COLOR.goldDim[2], COLOR.goldDim[3], 0.9)
        lines[i] = line
    end
    for _, spec in ipairs({ { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 },
        { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 } }) do
        local c = owner:CreateTexture(nil, "ARTWORK", nil, 6)
        c:SetTexture(TEX .. "C_Corner")
        c:SetSize(22, 22)
        c:SetPoint(spec[1], owner, spec[1], 0, 0)
        c:SetTexCoord(spec[2], spec[3], spec[4], spec[5])
    end
    owner.cardBg = bg
end

-- The scene: the middle of its 2:1 picture, as wide as the window is
local function scene(w, h)
    local half = math.min(0.5, (w / math.max(1, h)) / 4)
    f.back:SetTexCoord(0.5 - half, 0.5 + half, 0, 1)
end

local function edges(owner, layer)
    local lines = {}
    for i, spec in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local line = owner:CreateTexture(nil, layer or "OVERLAY")
        line:SetPoint(spec[1], owner, spec[1])
        line:SetPoint(spec[2], owner, spec[2])
        line.h = spec[3]
        lines[i] = line
    end
    function lines.set(c, a, w)
        for _, line in ipairs(lines) do
            line:SetColorTexture(c[1], c[2], c[3], a or 1)
            if line.h then line:SetHeight(w) else line:SetWidth(w) end
        end
    end
    return lines
end

-- One tile's parts (Kit_Grid.lua's tileButton), in a pane
local function tileButton(pane, k)
    local b = pane.tiles[k]
    if b then return b end
    b = CK.NewFrame("Button", nil, pane.content)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.glow = b:CreateTexture(nil, "BACKGROUND", nil, 0)
    b.glow:SetTexture(TEX .. "T_Glow")
    b.glow:SetPoint("TOPLEFT", -10, 10)
    b.glow:SetPoint("BOTTOMRIGHT", 10, -10)
    b.glow:Hide()
    b.bg = b:CreateTexture(nil, "BACKGROUND", nil, 2)
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.03, 0.035, 0.05, 0.92)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.edge = edges(b, "OVERLAY")
    b.shade = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.shade:SetAllPoints(b.icon)
    b.shade:SetColorTexture(0, 0, 0, 0.6)
    b.cool = text(b, 14, COLOR.text, "CENTER")
    b.cool:SetPoint("CENTER")
    b.count = text(b, 15, COLOR.text, "RIGHT")
    b.count:SetPoint("BOTTOMRIGHT", -3, 3)
    b.level = text(b, 12, COLOR.text)
    b.level:SetPoint("BOTTOMLEFT", 3, 3)
    b.mark = b:CreateTexture(nil, "OVERLAY", nil, 6)
    b.mark:SetSize(16, 16)
    b.mark:SetPoint("CENTER", b, "TOPRIGHT", -3, -3)
    b.up = b:CreateTexture(nil, "OVERLAY", nil, 7)
    b.up:SetSize(16, 16)
    b.up:SetPoint("TOPRIGHT", 2, 2)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("bags-greenarrow") then
        b.up:SetAtlas("bags-greenarrow")
    else
        b.up:SetTexture("Interface\\AddOns\\DualsenseForever\\textures\\ck_tri")
        b.up:SetTexCoord(0, 1, 1, 0)
        b.up:SetVertexColor(0.25, 1, 0.25)
    end
    b.newGlow = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.newGlow:SetPoint("TOPLEFT", -6, 6)
    b.newGlow:SetPoint("BOTTOMRIGHT", 6, -6)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("bags-glow-white") then
        b.newGlow:SetAtlas("bags-glow-white")
    else
        b.newGlow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    end
    b.newGlow:SetBlendMode("ADD")
    b.wide = text(b, 15, COLOR.text, "CENTER")
    b.wide:SetPoint("CENTER")
    -- Fork CoolerMgdn: the game's look - its slot frame, its empty slot, its
    -- rounded quality border, its light (ItemButtonTemplate's own textures)
    b.gNormal = b:CreateTexture(nil, "BORDER", nil, 1)
    b.gNormal:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    b.gNormal:SetPoint("CENTER", 0, -1)
    b.gEmpty = b:CreateTexture(nil, "BACKGROUND", nil, 3)
    b.gEmpty:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    b.gEmpty:SetAllPoints()
    b.gBorder = b:CreateTexture(nil, "OVERLAY", nil, 0)
    b.gBorder:SetAllPoints()
    b.gHl = b:CreateTexture(nil, "OVERLAY", nil, 3)
    b.gHl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    b.gHl:SetBlendMode("ADD")
    b.gHl:SetAllPoints()
    -- The light on the lit slot: its rounded frame, gold, glowing
    b.gLit = b:CreateTexture(nil, "OVERLAY", nil, 4)
    b.gLit:SetTexture("Interface\\Common\\WhiteIconFrame")
    b.gLit:SetVertexColor(1, 0.82, 0.2)
    b.gLit:SetBlendMode("ADD")
    b.gLit:SetPoint("TOPLEFT", -2, 2)
    b.gLit:SetPoint("BOTTOMRIGHT", 2, -2)
    for _, t in ipairs({ b.gNormal, b.gEmpty, b.gBorder, b.gHl, b.gLit }) do t:Hide() end
    b:SetScript("OnClick", function(self, mouse)
        if not self.cell then return end
        if B.index ~= self.cell then
            B:Focus(self.cell)
        elseif mouse == "LeftButton" then
            B:PressA()
        end
    end)
    b:SetScript("OnEnter", function(self) if self.cell then B:Focus(self.cell) end end)
    pane.tiles[k] = b
    return b
end

local MARK_FILE = { quest = "Interface\\GossipFrame\\AvailableQuestIcon", junk = "Interface\\MoneyFrame\\UI-CopperIcon" }

local function cooldownLeft(cd)
    if type(cd) ~= "table" then return 0 end
    local start, duration = cd.start or 0, cd.duration or 0
    if start == 0 or duration <= 1.5 then return 0 end
    return math.max(0, start + duration - GetTime())
end

local function cooldownText(left)
    if left <= 0 then return "" end
    if left >= 3600 then return format("%dh", math.ceil(left / 3600)) end
    if left >= 60 then return format("%dm", math.ceil(left / 60)) end
    return format("%d", math.ceil(left))
end

-- The game's glow on a new item, by its quality
local NEW_GLOW = { [2] = "bags-glow-green", [3] = "bags-glow-blue", [4] = "bags-glow-purple", [5] = "bags-glow-orange" }

-- The game's look on a tile (B.gameLook, set by the layout): its parts on,
-- ours off; false: ours back
local function gameParts(b, tile, lit, size)
    -- (the free slots' tile: one of the game's empty slots, its number on it)
    local game = B.gameLook and (not tile.wide or tile.free)
    b.gNormal:SetShown(game and true or false)
    b.gEmpty:SetShown(game and (tile.empty or tile.free) and true or false)
    b.gHl:SetShown(game and lit and true or false)
    b.gLit:SetShown(game and lit and true or false)
    b.gBorder:Hide()
    b.icon:ClearAllPoints()
    if not game then
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.bg:Show()
        return false
    end
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0, 1, 0, 1)
    b.bg:SetShown(false)
    b.gNormal:SetSize(size * QUICKSLOT, size * QUICKSLOT)
    if not tile.empty then
        local item = tile.item
        if item and (item.quest or item.classID == 12) then
            b.gBorder:SetTexture("Interface\\ContainerFrame\\UI-Icon-QuestBorder")
            b.gBorder:SetVertexColor(1, 1, 1)
            b.gBorder:Show()
        elseif (tile.quality or 0) >= 2 then
            local c = qualityColor(tile.quality)
            b.gBorder:SetTexture("Interface\\Common\\WhiteIconFrame")
            b.gBorder:SetVertexColor(c[1], c[2], c[3])
            b.gBorder:Show()
        end
    end
    return true
end

local function drawTile(b, tile, lit, size)
    local w = (tile.wide and not B.gameLook) and (size * 3 + (B.tileGap or TILE_GAP) * 2) or size
    b:SetSize(w, size)
    local game = gameParts(b, tile, lit, size)
    b.icon:SetShown(not tile.wide and not tile.empty)
    b.wide:SetShown(tile.wide and true or false)
    b.mark:Hide()
    b.up:Hide()
    b.newGlow:Hide()
    b.shade:Hide()
    b.cool:SetText("")
    b.count:SetText("")
    b.level:SetText("")
    local k = size / TILE
    font(b.count, math.max(12, 15 * k))
    -- (the game's count: its number font, outlined)
    if game then pcall(b.count.SetFont, b.count, "Fonts\\ARIALN.TTF", math.max(12, 14 * k), "OUTLINE") end
    if tile.wide then
        b.wide:SetText(game and tostring(tile.n or "") or tile.text or "")
        paint(b.wide, lit and COLOR.focus or COLOR.light)
    elseif not tile.empty then
        b.icon:SetTexture(tile.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        b.icon:SetDesaturated(tile.dim and true or false)
        if (tile.count or 1) > 1 then b.count:SetText(tile.count) end
        if tile.level then
            b.level:SetText(tile.level)
            paint(b.level, tile.levelColor or COLOR.text)
        end
        local left = cooldownLeft(tile.cooldown)
        if left > 0 then
            b.shade:Show()
            b.cool:SetText(cooldownText(left))
        end
        if tile.verdict == "up" then
            b.up:Show()
        elseif tile.verdict == "down" then
            b.mark:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
            b.mark:Show()
        elseif tile.mark then
            b.mark:SetTexture(MARK_FILE[tile.mark])
            b.mark:Show()
        elseif tile.new and not game then
            b.mark:SetTexture(TEX .. "P_Star")
            b.mark:Show()
        end
        if tile.new then
            -- (the game's look: its glow on the slot itself, in the item's
            -- quality's colour; ours: a white one round it)
            b.newGlow:ClearAllPoints()
            if game then
                b.newGlow:SetAllPoints()
                local atlas = NEW_GLOW[tile.quality or 1] or "bags-glow-white"
                if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then b.newGlow:SetAtlas(atlas) end
            else
                b.newGlow:SetPoint("TOPLEFT", -6, 6)
                b.newGlow:SetPoint("BOTTOMRIGHT", 6, -6)
                if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("bags-glow-white") then
                    b.newGlow:SetAtlas("bags-glow-white")
                end
            end
            b.newGlow:Show()
        end
    end
    if game then
        -- The game's slot frame is its edge; the light its rounded one
        b.edge.set(COLOR.gold, 0, 1)
        b.glow:Hide()
    elseif lit then
        b.edge.set(COLOR.gold, 1, 3)
        b.glow:Show()
    else
        local lk = look()
        local e
        if tile.wide or tile.empty then
            e = COLOR.goldDim
        elseif lk.edgeColor == "accent" then
            e = COLOR.gold
        elseif lk.edgeColor == "black" then
            e = { 0, 0, 0 }
        else
            e = ((tile.quality or 1) >= 2 and qualityColor(tile.quality)) or { 0.32, 0.29, 0.24 }
        end
        b.edge.set(e, (tile.wide or tile.empty) and 0.4 or 1, tile.wide and 2 or (tonumber(lk.edgeSize) or 2))
        b.glow:Hide()
    end
    b:SetAlpha(tile.dim and 0.45 or 1)
    -- (the game's look: an empty slot shows its bag's picture, dim and grey)
    if game and tile.empty and tile.picture then
        b.gEmpty:Hide()
        b.icon:SetTexture(tile.picture)
        b.icon:SetDesaturated(true)
        b.icon:SetVertexColor(0.55, 0.55, 0.55)
        b.icon:SetAlpha(0.6)
        b.icon:Show()
    else
        b.icon:SetVertexColor(1, 1, 1)
        b.icon:SetAlpha(1)
    end
end

local function headLine(pane, i)
    local h = pane.heads[i]
    if h then return h end
    h = CK.NewFrame("Frame", nil, pane.content)
    h.title = text(h, 13, COLOR.gold)
    h.title:SetPoint("BOTTOMLEFT", 2, 2)
    pane.heads[i] = h
    return h
end

local function newPane()
    local p = { tiles = {}, heads = {} }
    p.scroll = CK.NewFrame("ScrollFrame", nil, f)
    p.content = CK.NewFrame("Frame", nil, p.scroll)
    p.content:SetSize(10, 10)
    p.scroll:SetScrollChild(p.content)
    p.scroll:EnableMouseWheel(true)
    p.scroll:SetScript("OnMouseWheel", function(self, d)
        local max = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - d * 40)))
    end)
    p.title = text(f, 15, COLOR.gold)
    p.title:Hide()
    return p
end

function B:Build()
    if f then return end
    f = CK.NewFrame("Frame", "ControllerKeyboardBags", UIParent)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:Hide()
    ornate(f)
    -- (our ornate frame's parts, hidden in the game's look)
    f.ornateParts = { f:GetRegions() }
    -- The header: a bag, "Bags", the free slots; your gold at the right
    local hd = CK.NewFrame("Frame", nil, f)
    hd:SetPoint("TOPLEFT")
    hd:SetPoint("TOPRIGHT")
    hd.band = hd:CreateTexture(nil, "BACKGROUND", nil, -6)
    hd.band:SetColorTexture(0, 0, 0, 0.35)
    hd.line = hd:CreateTexture(nil, "ARTWORK")
    hd.line:SetHeight(1)
    hd.line:SetColorTexture(COLOR.goldDim[1], COLOR.goldDim[2], COLOR.goldDim[3], 0.8)
    hd.logo = hd:CreateTexture(nil, "ARTWORK")
    hd.logo:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
    hd.logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    hd.title = text(hd, 20, COLOR.gold)
    hd.title:SetPoint("LEFT", hd.logo, "RIGHT", 8, 0)
    hd.status = text(hd, 14, COLOR.light)
    hd.status:SetPoint("LEFT", hd.title, "RIGHT", 10, -1)
    hd.gold = text(hd, 16, COLOR.text, "RIGHT")
    f.header = hd
    -- Your bags, the bank
    panes[1] = newPane()
    panes[2] = newPane()
    -- The full window's sections column
    local col = CK.NewFrame("Frame", nil, f)
    card(col)
    col.rows = {}
    col:Hide()
    f.column = col
    -- The full window's item card
    local d = CK.NewFrame("Frame", nil, f)
    card(d)
    d.icon = d:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(44, 44)
    d.icon:SetPoint("TOPLEFT", 14, -14)
    d.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    d.name = text(d, 17, COLOR.text)
    d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 10, -2)
    d.name:SetPoint("RIGHT", d, "RIGHT", -12, 0)
    d.name:SetWordWrap(true)
    d.name:SetMaxLines(2)
    d.lines = {}
    d:Hide()
    f.detail = d
    -- The hints, two lines
    f.legend = text(f, 14, COLOR.light, "CENTER")
    f.legend:SetWordWrap(true)
    f.legend:SetSpacing(4)
    -- The message line (holding an item, nothing found...)
    f.msg = text(f, 13, COLOR.warn, "CENTER")
    -- Y: more, at the lit item: as the game's item menu (asked: ours stood
    -- out) - dark, a gold edge with its glow, the lit row a gold band with
    -- the game's arrow at it, its hints in a box of their own under it
    local okM, m = pcall(CreateFrame, "Frame", nil, f, "TooltipBackdropTemplate")
    if okM and m then
        if m.NineSlice then
            if m.NineSlice.SetCenterColor then pcall(m.NineSlice.SetCenterColor, m.NineSlice, 0.02, 0.02, 0.02, 0.95) end
            if m.NineSlice.SetBorderColor then pcall(m.NineSlice.SetBorderColor, m.NineSlice, 0.86, 0.68, 0.2, 1) end
        elseif m.SetBackdropColor then
            pcall(m.SetBackdropColor, m, 0.02, 0.02, 0.02, 0.95)
            pcall(m.SetBackdropBorderColor, m, 0.86, 0.68, 0.2, 1)
        end
    else
        m = CK.NewFrame("Frame", nil, f)
        card(m)
        m.cardBg:SetColorTexture(0.02, 0.02, 0.02, 0.95)
    end
    m:SetSize(200, 60)
    m:SetFrameStrata("DIALOG")
    m:SetClampedToScreen(true)
    local mg = CK.NewFrame("Frame", nil, m)
    mg:SetPoint("TOPLEFT", -14, 14)
    mg:SetPoint("BOTTOMRIGHT", 14, -14)
    mg:SetFrameLevel(m:GetFrameLevel() + 5)
    local mslice = CK.UIKit.nineSlice(mg, "ck_glow9", 64, 64, 24, 24, "OVERLAY")
    mslice:SetFile("ck_glow9")
    mslice:SetVertexColor(1, 0.82, 0.2)
    for _, p in ipairs(mslice.parts) do p:SetBlendMode("ADD") end
    m.arrow = mg:CreateTexture(nil, "OVERLAY", nil, 7)
    m.arrow:SetTexture("Interface\\AddOns\\DualsenseForever\\textures\\ck_tri")
    m.arrow:SetSize(26, 26)
    m.arrow:SetRotation(math.pi / 2)
    m.arrow:SetVertexColor(1, 0.82, 0.2)
    m.rows = {}
    -- (its hints: A select, B close, the game's way)
    local okF, ft = pcall(CreateFrame, "Frame", nil, m, "TooltipBackdropTemplate")
    if not (okF and ft) then
        ft = CK.NewFrame("Frame", nil, m)
        local fbg = ft:CreateTexture(nil, "BACKGROUND")
        fbg:SetAllPoints()
        fbg:SetColorTexture(0.09, 0.09, 0.09, 0.92)
    elseif ft.NineSlice then
        if ft.NineSlice.SetCenterColor then pcall(ft.NineSlice.SetCenterColor, ft.NineSlice, 0.09, 0.09, 0.09, 0.92) end
        if ft.NineSlice.SetBorderColor then pcall(ft.NineSlice.SetBorderColor, ft.NineSlice, 0.62, 0.62, 0.62, 1) end
    end
    ft:SetPoint("TOPLEFT", m, "BOTTOMLEFT", 0, -6)
    ft:SetHeight(HINT_GLYPH + 2 * HINT_PAD)
    ft.items = {}
    for i, it in ipairs({ { "A", L.BAGS_MENU_PICK }, { "B", L.V_CLOSE } }) do
        local g = ft:CreateTexture(nil, "ARTWORK")
        g:SetSize(HINT_GLYPH, HINT_GLYPH)
        local w = text(ft, HINT_FONT + 2, GAME_GOLD)
        w:SetText(it[2])
        ft.items[i] = { key = it[1], glyph = g, word = w }
    end
    m.foot = ft
    m:Hide()
    f.more = m
    -- Dimmed while the game's window beside it has the controller
    f.cover = CK.NewFrame("Frame", nil, f)
    f.cover:SetAllPoints(f)
    f.cover:SetFrameLevel(f:GetFrameLevel() + 40)
    local ct = f.cover:CreateTexture(nil, "OVERLAY")
    ct:SetAllPoints()
    ct:SetColorTexture(0, 0, 0, 0.45)
    f.cover:Hide()
    self:BuildGame()
    self:BuildKeys()
end

-- Fork CoolerMgdn (asked): the game's own bag window read, its look copied
-- (it is there, faded under ours: only read, never changed): the layout of
-- its frame (its thin edge, its small portrait ring), its portrait's place
-- and size. Once, when it has been laid out (its first open). Said in the
-- flight recorder.
function B:CopyGameBags()
    local g = f and f.blizz
    if not g or g.copied then return end
    local src = _G.ContainerFrameCombinedBags
    if not (src and src.GetWidth and (src:GetWidth() or 0) > 0) then return end
    g.copied = true
    local ns = src.NineSlice
    local layout = ns and (ns.layoutType or (ns.GetAttribute and ns:GetAttribute("layoutType"))) or src.layoutType
    local applied = false
    if type(layout) == "string" and NineSliceUtil and NineSliceUtil.ApplyLayoutByName and g.NineSlice then
        applied = pcall(NineSliceUtil.ApplyLayoutByName, g.NineSlice, layout)
    end
    local pb = src.PortraitButton or (src.PortraitContainer and src.PortraitContainer.portrait) or src.portrait
    local pw, ph, point, rel, rpoint, x, y
    if pb and pb.GetSize then
        pw, ph = pb:GetSize()
        point, rel, rpoint, x, y = pb:GetPoint(1)
    end
    if CK.Flight then
        CK.Flight:Note("bags look: game's frame %s (%s), portrait %s %sx%s at %s %s %s / %s", tostring(layout),
            applied and "copied" or "not copied", tostring(pb and pb.GetName and pb:GetName() or (pb and "found") or "none"),
            tostring(pw), tostring(ph), tostring(point), tostring(rpoint), tostring(x), tostring(y))
    end
    -- What it is anchored to, found on ours: the frame, a part of its
    -- edge (the corner holding the ring: found so), or a part of the frame
    local function ours(region)
        if region == nil or region == src then return g end
        if ns and g.NineSlice then
            for k, v in pairs(ns) do
                if v == region and type(k) == "string" and g.NineSlice[k] then return g.NineSlice[k] end
            end
        end
        for k, v in pairs(src) do
            if v == region and type(k) == "string" and type(g[k]) == "table" and g[k].GetObjectType then return g[k] end
        end
    end
    local anchor = ours(rel)
    if CK.Flight then CK.Flight:Note("bags look: portrait anchored to %s, found on ours: %s",
        tostring(rel and rel.GetDebugName and rel:GetDebugName() or rel), anchor and "yes" or "no") end
    if pw and pw > 8 and point and anchor then
        local pc = g.portraitFrame
        pc:ClearAllPoints()
        pc:SetPoint(point, anchor, rpoint or point, x or 0, y or 0)
        -- (the backpack round: the button's smaller side)
        local d = math.min(pw, ph)
        pc:SetSize(d, d)
        g.portraitDisc:SetSize(d + 4, d + 4)
        -- The game's frame has its ring: ours not drawn over it
        if applied then g.portraitRing:Hide() end
    end
end

-- Fork CoolerMgdn (asked): the game's own bag window's look - its frame
-- (ButtonFrameTemplate), the backpack in its portrait with the free slots,
-- its search field, its money bar; the light around it beside a game window
-- (its arrow), R2 at its foot while the controller is over there. Nothing of
-- the game's own bags is used: a template of its, made for ours.
function B:BuildGame()
    local ok, g = pcall(CreateFrame, "Frame", nil, f, "ButtonFrameTemplate")
    if not (ok and g) then return end
    g:SetAllPoints(f)
    g:EnableMouse(false)
    g:SetFrameLevel(f:GetFrameLevel())
    if ButtonFrameTemplate_HideButtonBar then pcall(ButtonFrameTemplate_HideButtonBar, g) end
    if g.Inset then g.Inset:Hide() end
    -- An opaque ground under the game's
    local under = g:CreateTexture(nil, "BACKGROUND", nil, -8)
    under:SetPoint("TOPLEFT", 3, -3)
    under:SetPoint("BOTTOMRIGHT", -3, 3)
    under:SetColorTexture(0.05, 0.05, 0.06, 1)
    g.under = under
    local title = COMBINED_BAG_TITLE or L.BAGS_TITLE
    if g.SetTitle then pcall(g.SetTitle, g, title) elseif g.TitleText then g.TitleText:SetText(title) end
    -- No portrait of the template's (its ring is a corner of its frame,
    -- too big for the small backpack, asked): its plain corner instead, a
    -- small ring of our own (the game's round button ring) put over it
    local portrait = g.portrait or g.Portrait or (g.PortraitContainer and g.PortraitContainer.portrait)
    if ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, g) end
    if g.PortraitContainer then g.PortraitContainer:Hide() end
    if portrait then portrait:Hide() end
    local close = g.CloseButton
    if close then
        close:SetScript("OnClick", function()
            if CloseAllBags then pcall(CloseAllBags) end
            B:Close("button")
        end)
    end
    local over = CK.NewFrame("Frame", nil, g)
    over:SetAllPoints(g)
    -- (over the portrait's own frame, which the game raises high)
    -- (above every frame of the template: its ring is drawn by its edge's
    -- frame, raised high)
    local top = g:GetFrameLevel()
    for _, child in ipairs({ g:GetChildren() }) do
        if child ~= over and child.GetFrameLevel then top = math.max(top, child:GetFrameLevel()) end
        for _, sub in ipairs({ child:GetChildren() }) do
            if sub.GetFrameLevel then top = math.max(top, sub:GetFrameLevel()) end
        end
    end
    over:SetFrameLevel(top + 10)
    -- The backpack: 38 px, round, on a dark disc, in a gold ring (the
    -- minimap buttons' ring: 53 px round a 20 px icon, at its 7 / 6 px);
    -- where the game's own bag window is read (B:CopyGameBags), its frame
    -- and its portrait's place and size instead
    local S = 38
    local pc = CK.NewFrame("Frame", nil, over)
    pc:SetSize(S, S)
    pc:SetPoint("CENTER", g, "TOPLEFT", 20, -18)
    local disc = pc:CreateTexture(nil, "BACKGROUND")
    disc:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    disc:SetVertexColor(0, 0, 0, 1)
    disc:SetPoint("CENTER")
    disc:SetSize(S + 6, S + 6)
    local icon = pc:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    if SetPortraitToTexture then
        pcall(SetPortraitToTexture, icon, "Interface\\Icons\\INV_Misc_Bag_08")
    else
        icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
    end
    local k = S / 20
    local ring = pc:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(53 * k, 53 * k)
    ring:SetPoint("TOPLEFT", icon, "TOPLEFT", -7 * k, 6 * k)
    g.portraitFrame, g.portraitRing, g.portraitDisc, g.portraitIcon = pc, ring, disc, icon
    -- The free slots, on the backpack's lower part
    g.freeText = text(pc, 12, COLOR.text, "CENTER", "OVERLAY")
    g.freeText:SetDrawLayer("OVERLAY", 7)
    g.freeText:SetPoint("CENTER", pc, "BOTTOM", 0, 7)
    -- The search field (the addon's keyboard types in it: R3)
    local okS, sb = pcall(CreateFrame, "EditBox", nil, g, "SearchBoxTemplate")
    if okS and sb then
        sb:SetAutoFocus(false)
        sb:EnableMouse(false)
        if sb.EnableKeyboard then sb:EnableKeyboard(false) end
        sb:ClearFocus()
        g.search = sb
    else
        sb = CK.NewFrame("Frame", nil, g)
        local bg = sb:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.5)
        g.searchLabel = text(sb, 12, COLOR.grey)
        g.searchLabel:SetPoint("LEFT", 8, 0)
    end
    sb:SetHeight(20)
    sb:SetPoint("TOPLEFT", g, "TOPLEFT", 62, -27)
    sb:SetPoint("TOPRIGHT", g, "TOPRIGHT", -10, -27)
    -- The money bar
    local mb = CK.NewFrame("Frame", nil, g)
    mb:SetPoint("BOTTOMLEFT", 6, 5)
    mb:SetPoint("BOTTOMRIGHT", -6, 5)
    mb:SetHeight(GMONEY - 6)
    local mbg = mb:CreateTexture(nil, "BACKGROUND")
    mbg:SetAllPoints()
    mbg:SetColorTexture(0, 0, 0, 0.55)
    edges(mb, "BORDER").set(COLOR.goldDim, 0.8, 1)
    g.moneyText = text(mb, 13, COLOR.text, "RIGHT")
    g.moneyText:SetPoint("RIGHT", -8, 0)
    -- The light around it (a soft rounded glow, nine-sliced: ck_glow9),
    -- its arrow at the portrait (the game's focus)
    local gl = CK.NewFrame("Frame", nil, g)
    gl:SetPoint("TOPLEFT", -16, 16)
    gl:SetPoint("BOTTOMRIGHT", 16, -16)
    gl:SetFrameLevel(g:GetFrameLevel() + 19)
    local slice = CK.UIKit.nineSlice(gl, "ck_glow9", 64, 64, 24, 24, "OVERLAY")
    slice:SetFile("ck_glow9")
    slice:SetVertexColor(1, 0.82, 0.2)
    for _, p in ipairs(slice.parts) do p:SetBlendMode("ADD") end
    gl:Hide()
    g.glow = gl
    g.arrow = over:CreateTexture(nil, "OVERLAY")
    g.arrow:SetTexture("Interface\\AddOns\\DualsenseForever\\textures\\ck_tri")
    g.arrow:SetSize(24, 24)
    g.arrow:SetRotation(math.pi / 2)
    g.arrow:SetVertexColor(1, 0.82, 0.2)
    g.arrow:SetPoint("RIGHT", g, "TOPLEFT", -10, -32)
    g.arrow:Hide()
    -- R2 at its foot: back to it from the game's window
    g.back = text(over, 13, COLOR.text, "CENTER")
    -- (on the frame's lower edge, as the game puts it)
    g.back:SetPoint("CENTER", g, "BOTTOM", 0, 10)
    g.back:SetText(CK:GlyphMarkup("RT", 30))
    g.back:Hide()
    -- The hints: a box of their own under the window (the game's tooltip)
    local okH, hb = pcall(CreateFrame, "Frame", nil, f, "TooltipBackdropTemplate")
    if not (okH and hb) then
        hb = CK.NewFrame("Frame", nil, f)
        local hbg = hb:CreateTexture(nil, "BACKGROUND")
        hbg:SetAllPoints()
        hbg:SetColorTexture(0.03, 0.03, 0.04, 0.92)
        edges(hb, "BORDER").set(COLOR.goldDim, 0.8, 1)
    end
    hb:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -4)
    hb:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -4)
    hb:SetHeight(GHINTS)
    -- (the game's hint box: dark grey, a light grey edge)
    if hb.NineSlice then
        if hb.NineSlice.SetCenterColor then pcall(hb.NineSlice.SetCenterColor, hb.NineSlice, 0.09, 0.09, 0.09, 0.92) end
        if hb.NineSlice.SetBorderColor then pcall(hb.NineSlice.SetBorderColor, hb.NineSlice, 0.62, 0.62, 0.62, 1) end
    elseif hb.SetBackdropColor then
        pcall(hb.SetBackdropColor, hb, 0.09, 0.09, 0.09, 0.92)
        pcall(hb.SetBackdropBorderColor, hb, 0.62, 0.62, 0.62, 1)
    end
    g.hintMsg = text(hb, HINT_FONT, COLOR.warn, "CENTER")
    g.hintMsg:SetWordWrap(true)
    g.hintMsg:SetPoint("TOP", hb, "TOP", 0, -10)
    g.hintText = text(hb, 14, COLOR.light, "CENTER")
    g.hintText:SetWordWrap(true)
    g.hintText:SetSpacing(4)
    g.hintLines = {}
    hb:Hide()
    g.hints = hb
    g:Hide()
    f.blizz = g
end

local function columnRow(i)
    local col = f.column
    local r = col.rows[i]
    if r then return r end
    r = CK.NewFrame("Button", nil, col)
    r:SetHeight(30)
    r.bg = r:CreateTexture(nil, "BACKGROUND", nil, 2)
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3], 0.16)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 8, 0)
    r.label = text(r, 14, COLOR.text)
    r.label:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.label:SetPoint("RIGHT", -34, 0)
    r.count = text(r, 13, COLOR.light, "RIGHT")
    r.count:SetPoint("RIGHT", -10, 0)
    r:SetScript("OnClick", function(self) B:JumpTo(self.section) end)
    col.rows[i] = r
    return r
end

local function moreRow(i)
    local m = f.more
    local r = m.rows[i]
    if r then return r end
    r = CK.NewFrame("Button", nil, m)
    r:SetHeight(MENU_ROW)
    r:SetPoint("TOPLEFT", 5, -MENU_PAD - (i - 1) * MENU_ROW)
    r:SetPoint("TOPRIGHT", -5, -MENU_PAD - (i - 1) * MENU_ROW)
    -- (the lit row: a gold band fading out to the right, as the game's)
    r.bg = r:CreateTexture(nil, "BACKGROUND", nil, 2)
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, 1)
    local okG = CreateColor and pcall(r.bg.SetGradient, r.bg, "HORIZONTAL",
        CreateColor(0.93, 0.7, 0.12, 0.95), CreateColor(0.35, 0.24, 0.04, 0.35))
    if not okG then r.bg:SetColorTexture(0.85, 0.64, 0.12, 0.6) end
    r.label = text(r, 16, COLOR.text)
    r.label:SetPoint("LEFT", 12, 0)
    r:SetScript("OnClick", function() B.moreIndex = i; B:MoreChoose() end)
    m.rows[i] = r
    return r
end

local function detailLine(i)
    local d = f.detail
    local fs = d.lines[i]
    if fs then return fs end
    fs = text(d, 13, COLOR.light)
    fs:SetWordWrap(true)
    d.lines[i] = fs
    return fs
end

---------------------------------------------------------------------------
-- Laying out
---------------------------------------------------------------------------
-- Where the game's bags are (Inv_Simple.lua's measure)
local function gameRect()
    local ui = UIParent:GetEffectiveScale()
    local l, r, b, t
    local names = { "ContainerFrameCombinedBags" }
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do names[#names + 1] = "ContainerFrame" .. i end
    for _, name in ipairs(names) do
        local fr = _G[name]
        if fr and fr.IsShown and fr:IsShown() then
            pcall(function()
                local k = fr:GetEffectiveScale() / ui
                local fl, frr, fb, ft = fr:GetLeft(), fr:GetRight(), fr:GetBottom(), fr:GetTop()
                fl, frr, fb, ft = CK.Plain(fl), CK.Plain(frr), CK.Plain(fb), CK.Plain(ft)
                if not (fl and frr and fb and ft) then return end
                fl, frr, fb, ft = fl * k, frr * k, fb * k, ft * k
                l, r = math.min(l or fl, fl), math.max(r or frr, frr)
                b, t = math.min(b or fb, fb), math.max(t or ft, ft)
            end)
        end
    end
    if not (l and r and b and t) or r - l < 50 then
        local right = UIParent:GetWidth() - 20
        return right - 430, right, CONTAINER_OFFSET_Y or 85
    end
    return l, r, b
end

-- Where every tile of a pane goes for a width and a tile size
local function arrange(sections, width, size, labels, gap)
    local TILE_GAP = gap or TILE_GAP
    local cells, headsAt = {}, {}
    local perRow = math.max(3, math.floor((width + TILE_GAP) / (size + TILE_GAP)))
    local y = 0
    for si, s in ipairs(sections) do
        headsAt[si] = y
        if labels then y = y + LABEL_H end
        local col, row = 0, 0
        for _, tile in ipairs(s.tiles) do
            local span = (tile.wide and not B.gameLook) and 3 or 1
            if col + span > perRow and col > 0 then col, row = 0, row + 1 end
            cells[#cells + 1] = { tile = tile, section = si, x = col * (size + TILE_GAP), y = y + row * (size + TILE_GAP),
                span = span }
            col = col + span
        end
        y = y + (row + 1) * (size + TILE_GAP) + SECTION_GAP
    end
    return cells, headsAt, y
end

function B:FullMode()
    return self.bankMode or look().layout == "full"
end

-- Fork CoolerMgdn: the game's look (not at the bank: its own big window)
function B:GameLook()
    return not self.bankMode and look().layout == "blizzard" and f and f.blizz ~= nil
end

local function placeHeader(height, pad)
    local hd = f.header
    hd:SetHeight(height)
    hd.band:ClearAllPoints()
    hd.band:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
    hd.band:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -6)
    hd.band:SetHeight(height - 8)
    hd.line:ClearAllPoints()
    hd.line:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -height + 1)
    hd.line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, -height + 1)
    local big = height > HEAD
    hd.logo:SetSize(big and 30 or 22, big and 30 or 22)
    hd.logo:ClearAllPoints()
    hd.logo:SetPoint("LEFT", hd, "TOPLEFT", pad + 2, -height / 2 - 1)
    font(hd.title, big and 26 or 20)
    font(hd.gold, big and 18 or 16)
    hd.gold:ClearAllPoints()
    hd.gold:SetPoint("RIGHT", hd, "TOPRIGHT", -pad - 2, -height / 2 - 1)
end

local function placeBottom(pad)
    f.legend:ClearAllPoints()
    f.legend:SetPoint("BOTTOMLEFT", pad, 10)
    f.legend:SetPoint("BOTTOMRIGHT", -pad, 10)
    f.msg:ClearAllPoints()
    f.msg:SetPoint("BOTTOMLEFT", pad, HINT + 2)
    f.msg:SetPoint("BOTTOMRIGHT", -pad, HINT + 2)
end

function B:Layout()
    local lk = look()
    local sc = math.max(0.8, math.min(1.1, tonumber(lk.scale) or 1))
    f:SetScale(sc)
    local full = self:FullMode()
    local models = { self.model, self.bankMode and self.bankModel or nil }
    local cells = {}
    -- Fork CoolerMgdn: the game's look or ours (its frame, or our ornate one)
    local game = self:GameLook()
    B.gameLook, B.tileGap = game, game and GGAP or TILE_GAP
    if f.blizz then f.blizz:SetShown(game and true or false) end
    for _, t in ipairs(f.ornateParts or {}) do t:SetShown(not game) end
    f.header:SetShown(not game)
    panes[1].labels = true
    panes[1].pad, panes[2].pad = 0, 0
    -- (the game's look: the hints in a box under the window)
    f.legend:SetShown(not game)
    f.msg:SetShown(not game)
    if f.blizz then f.blizz.hints:Hide() end
    f.column:SetShown(full and not self.bankMode)
    f.detail:SetShown(full)
    f.more:ClearAllPoints()
    if full then
        local W, H = FULL.w, FULL.h
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 30 / sc)
        f:SetSize(W, H)
        placeHeader(FULL.head, PAD + 4)
        placeBottom(PAD + 4)
        local top = FULL.head + GAP + 4
        local bottom = HINT + 22
        local bodyH = H - top - bottom
        local left = PAD + 4
        if not self.bankMode then
            f.column:ClearAllPoints()
            f.column:SetPoint("TOPLEFT", left, -top)
            f.column:SetSize(FULL.column, bodyH)
            left = left + FULL.column + FULL.gap
        end
        f.detail:ClearAllPoints()
        f.detail:SetPoint("TOPRIGHT", -(PAD + 4), -top)
        f.detail:SetSize(FULL.detail, bodyH)
        local mainW = W - left - FULL.detail - FULL.gap - (PAD + 4)
        local n = self.bankMode and 2 or 1
        local paneW = (mainW - (n - 1) * FULL.gap) / n
        for p = 1, 2 do
            local pane = panes[p]
            local on = models[p] ~= nil
            pane.scroll:SetShown(on)
            pane.title:SetShown(on and self.bankMode)
            if on then
                -- (the bank at the left, your bags at the right)
                local slot = self.bankMode and (p == 2 and 0 or 1) or 0
                local x = left + slot * (paneW + FULL.gap)
                local titleH = self.bankMode and 24 or 0
                pane.title:ClearAllPoints()
                pane.title:SetPoint("TOPLEFT", f, "TOPLEFT", x + 2, -top)
                pane.title:SetText(p == 2 and L.BAGS_BANK or L.BAGS_TITLE)
                pane.scroll:ClearAllPoints()
                pane.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(top + titleH))
                pane.scroll:SetSize(paneW, bodyH - titleH)
                local pc, ph, h = arrange(models[p].sections, paneW, TILE, true)
                pane.cells, pane.headsAt, pane.size = pc, ph, TILE
                pane.content:SetSize(paneW, h)
            end
        end
        f.more:SetPoint("TOPRIGHT", f.detail, "TOPRIGHT", 0, 0)
        scene(W, H)
    elseif game then
        -- The game's look: where the game's bags are, in its frame (the
        -- labels of the groups inside; none when it is one bag)
        local l, r, b = gameRect()
        r, b, l = r / sc, b / sc, l / sc
        -- (room under it for the hints' box)
        b = math.max(b, GHINTS + 10)
        local maxH = math.max(MIN_H, UIParent:GetHeight() / sc - b - 20)
        local bottom = GMONEY + 4
        local labels = lk.order ~= "one"
        -- Ten slots a row, as the game's own bag window (fewer only when the
        -- screen is too narrow for them)
        local cols = math.max(3, math.min(GCOLS, math.floor((r - 20 - GLEFT - GRIGHT + GGAP) / (GTILE + GGAP))))
        local size, pc, ph, h, inner = GTILE
        repeat
            inner = cols * size + (cols - 1) * GGAP
            pc, ph, h = arrange(self.model.sections, inner, size, labels, GGAP)
            -- (the last row's gap and the sections' end left out: the money
            -- bar right under the slots, as the game's)
            h = math.max(size, h - GGAP - SECTION_GAP)
            if GTOP + h + bottom <= maxH or size <= TILE_MIN then break end
            size = size - 2
        until false
        local H = math.min(maxH, GTOP + h + bottom)
        local W = GLEFT + GRIGHT + inner
        f:ClearAllPoints()
        f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", r, b)
        f:SetSize(W, H)
        local pane = panes[1]
        pane.scroll:Show()
        pane.title:Hide()
        pane.scroll:ClearAllPoints()
        pane.scroll:SetPoint("TOPLEFT", GLEFT - GPAD, -(GTOP - GPAD))
        pane.scroll:SetPoint("BOTTOMRIGHT", -(GRIGHT - GPAD), bottom - GPAD)
        pane.cells, pane.headsAt, pane.size, pane.labels, pane.pad = pc, ph, size, labels, GPAD
        pane.content:SetSize(inner + 2 * GPAD, h + 2 * GPAD)
        panes[2].scroll:Hide()
        panes[2].title:Hide()
        f.more:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", -6, 0)
    else
        -- Compact: where the game's bags are, as wide, as tall as the room
        local l, r, b = gameRect()
        r, b, l = r / sc, b / sc, l / sc
        local W = math.floor(math.max(MIN_W, math.min(MAX_W, r - l)) + 0.5)
        local maxH = math.max(MIN_H, UIParent:GetHeight() / sc - b - 20)
        local inner = W - 2 * PAD
        local size, pc, ph, h = TILE
        repeat
            pc, ph, h = arrange(self.model.sections, inner, size, true)
            if HEAD + GAP + h + HINT <= maxH or size <= TILE_MIN then break end
            size = size - 2
        until false
        local H = math.min(maxH, HEAD + GAP + h + HINT + 4)
        f:ClearAllPoints()
        f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", r, b)
        f:SetSize(W, H)
        placeHeader(HEAD, PAD)
        placeBottom(PAD)
        local pane = panes[1]
        pane.scroll:Show()
        pane.title:Hide()
        pane.scroll:ClearAllPoints()
        pane.scroll:SetPoint("TOPLEFT", PAD, -(HEAD + GAP))
        pane.scroll:SetPoint("BOTTOMRIGHT", -PAD, HINT)
        pane.cells, pane.headsAt, pane.size = pc, ph, size
        pane.content:SetSize(inner, h)
        panes[2].scroll:Hide()
        panes[2].title:Hide()
        f.more:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", -6, 0)
        scene(W, H)
    end
    -- One list of cells over both panes (the bank's after yours)
    for p = 1, 2 do
        if models[p] and panes[p].cells then
            for k, c in ipairs(panes[p].cells) do
                c.pane, c.k = p, k
                cells[#cells + 1] = c
            end
        end
    end
    self.cells = cells
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
function B:LitItem()
    local cell = self.cells and self.cells[self.index]
    return cell and cell.tile.item, cell and cell.tile, cell
end

function B:Draw()
    if not (f and self.model and self.cells) then return end
    local model = self.model
    local hd = f.header
    hd.title:SetText(self.bankMode and L.BAGS_BANK_TITLE or L.BAGS_TITLE)
    hd.status:SetText(format(L.BAGS_FREE_OF, #model.free, model.total))
    hd.gold:SetText(B.Money(GetMoney()))
    local litCell = self.cells[self.index]
    local models = { self.model, self.bankModel }
    -- the section labels, the tiles, pane by pane
    local seen = {}
    for p = 1, 2 do
        local pane, m = panes[p], models[p]
        if m and pane.cells and pane.scroll:IsShown() and pane.labels == false then
            for _, h in ipairs(pane.heads) do h:Hide() end
            seen[p] = 0
        elseif m and pane.cells and pane.scroll:IsShown() then
            for i, s in ipairs(m.sections) do
                local hl = headLine(pane, i)
                hl:ClearAllPoints()
                hl:SetPoint("TOPLEFT", pane.content, "TOPLEFT", pane.pad or 0, -((pane.headsAt[i] or 0) + (pane.pad or 0)))
                hl:SetSize(pane.content:GetWidth(), LABEL_H)
                local n = 0
                for _, t in ipairs(s.tiles) do if not t.wide then n = n + 1 end end
                -- (no "·": the game's Cyrillic font hasn't it, a square showed)
                hl.title:SetText(s.id == "free" and s.title or format("%s  |cffd4cec4%d|r", s.title, n))
                local lit = litCell and litCell.pane == p and litCell.section == i
                paint(hl.title, lit and COLOR.focus or COLOR.gold)
                hl:Show()
            end
            for i = #m.sections + 1, #pane.heads do pane.heads[i]:Hide() end
            seen[p] = 0
        end
    end
    for i, cell in ipairs(self.cells) do
        local pane = panes[cell.pane]
        local b = tileButton(pane, cell.k)
        b.cell = i
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", pane.content, "TOPLEFT", cell.x + (pane.pad or 0), -(cell.y + (pane.pad or 0)))
        drawTile(b, cell.tile, i == self.index, pane.size)
        b:Show()
        if i == self.index then self.litButton = b end
        seen[cell.pane] = math.max(seen[cell.pane] or 0, cell.k)
    end
    for p = 1, 2 do
        local pane = panes[p]
        for k = (seen[p] or 0) + 1, #pane.tiles do pane.tiles[k]:Hide() end
        if not seen[p] then for _, h in ipairs(pane.heads) do h:Hide() end end
    end
    if self:FullMode() then
        self:DrawColumn()
        self:DrawDetail()
    end
    -- the hints
    local item = self:LitItem()
    local G = function(k) return CK:GlyphMarkup(k, 18) end
    local holding = CursorHasItem and CursorHasItem()
    local fight = InCombatLockdown()
    local parts = { G("A") .. " " .. (holding and L.BAGS_PUT or L.BAGS_PICK) }
    -- (the same as items, row by row: the game's look draws them itself)
    local rows = { { { keys = { "A" }, text = holding and L.BAGS_PUT or L.BAGS_PICK } }, {} }
    local where = B.Where()
    local x, no
    if self.bankMode then
        if item then x = litCell.pane == 2 and L.BAGS_TO_BAGS or L.BAGS_TO_BANK end
    else
        x, no = B.xLabel(item, where)
    end
    if x and not holding then
        parts[#parts + 1] = G("X") .. " " .. (no and ("|cff8c8c8c" .. x .. "|r") or x)
        table.insert(rows[1], { keys = { "X" }, text = x, grey = no })
    end
    if not fight then
        parts[#parts + 1] = G("Y") .. " " .. L.BAGS_MORE
        table.insert(rows[1], { keys = { "Y" }, text = L.BAGS_MORE })
    end
    local back = (holding and not fight) and L.BAGS_PUT_BACK or L.V_CLOSE
    parts[#parts + 1] = G("B") .. " " .. back
    table.insert(rows[1], { keys = { "B" }, text = back })
    -- (sections only where there are some; one bag: L3 sorts instead)
    local one = look().order == "one"
    local second = one and (G("LS") .. " " .. L.BAGS_SORT) or (G("LB") .. G("RB") .. " " .. L.BAGS_SECTIONS)
    if one then
        table.insert(rows[2], { keys = { "LS" }, text = L.BAGS_SORT })
    else
        table.insert(rows[2], { keys = { "LB", "RB" }, text = L.BAGS_SECTIONS })
    end
    if not fight then
        second = second .. "    " .. G("RS") .. " " .. L.BAGS_SEARCH
        table.insert(rows[2], { keys = { "RS" }, text = L.BAGS_SEARCH })
    end
    if self.bankMode then
        second = second .. "    " .. G("LT") .. G("RT") .. " " .. L.BAGS_SIDES
        table.insert(rows[2], { keys = { "LT", "RT" }, text = L.BAGS_SIDES })
    elseif where and not fight then
        second = second .. "    " .. G("LT") .. " " .. L["BAGS_WIN_" .. where:upper()]
        table.insert(rows[2], { keys = { "LT" }, text = L["BAGS_WIN_" .. where:upper()] })
    end
    self.hintRows = rows
    f.legend:SetText(table.concat(parts, "    ") .. "\n" .. second)
    -- the message
    if self.visit then
        f.msg:SetText(format(L.BAGS_VISITING, G("RT")))
    elseif fight then
        -- (the buttons as their glyphs: a DualSense has no A / B)
        local g = function(k) return CK:GlyphMarkup(k, 14) end
        f.msg:SetText(format(L.BAGS_FIGHT, g("A"), g("X"), g("B")))
    elseif self.message then
        f.msg:SetText(self.message)
    elseif self.search and self.search ~= "" then
        f.msg:SetText(format(L.BAGS_SEARCHING, self.search))
    elseif holding then
        local g = function(k) return CK:GlyphMarkup(k, 14) end
        f.msg:SetText(format(L.BAGS_HOLDING, g("A"), g("B")))
    else
        f.msg:SetText("")
    end
    self:DrawGame()
    self:DrawHeld()
    self:Tooltip()
    self:DrawMore()
end

-- Fork CoolerMgdn: the item held, over the lit slot's corner (found: the
-- game draws it where the mouse was left - with a pad, fixed somewhere -
-- and an addon can't move the mouse: ours goes with the light)
function B:DrawHeld()
    local h = f.held
    if not h then
        h = CK.NewFrame("Frame", nil, f)
        h:SetFrameStrata("TOOLTIP")
        h:SetSize(30, 30)
        h.icon = h:CreateTexture(nil, "ARTWORK")
        h.icon:SetAllPoints()
        h.edge = h:CreateTexture(nil, "OVERLAY")
        h.edge:SetTexture("Interface\\Common\\WhiteIconFrame")
        h.edge:SetAllPoints()
        h:Hide()
        f.held = h
    end
    local kind, id = GetCursorInfo()
    local b = self.litButton
    if kind ~= "item" or not (b and b:IsShown()) or self.visit then
        h:Hide()
        return
    end
    local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
    h.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local _, _, quality = (C_Item.GetItemInfo or GetItemInfo)(id)
    local c = qualityColor(quality or 1)
    h.edge:SetVertexColor(c[1], c[2], c[3])
    local size = math.floor((b:GetWidth() or 36) * 0.8 + 0.5)
    h:SetSize(size, size)
    h:ClearAllPoints()
    h:SetPoint("CENTER", b, "TOPRIGHT", -2, -2)
    h:Show()
end

-- Fork CoolerMgdn: the game's look's own parts - the free slots on the
-- portrait, the search, the gold; beside a game window (a vendor, the mail,
-- the character...) the light on the window the controller is in, as the
-- game does it: ours glows with its arrow, or shows R2 (back to it) while
-- the controller is over there
function B:DrawGame()
    local g = f and f.blizz
    if not (g and self:GameLook()) then return end
    if not g.copied then self:CopyGameBags() end
    g.freeText:SetText(format("(%d)", #self.model.free))
    local a = math.max(0.3, math.min(1, tonumber(look().bgAlpha) or 1))
    g.under:SetAlpha(a)
    if g.Bg then g.Bg:SetAlpha(a) end
    g.moneyText:SetText(B.Money(GetMoney()))
    local query = self.search or ""
    if g.search and g.search.GetText and g.search:GetText() ~= query then g.search:SetText(query) end
    if g.searchLabel then
        g.searchLabel:SetText(query ~= "" and query or (SEARCH or L.BAGS_SEARCH))
    end
    local beside = B.Where() ~= nil
    local here = beside and not self.visit
    local away = beside and self.visit and true or false
    g.glow:SetShown(here)
    g.arrow:SetShown(here)
    g.back:SetShown(away)
    -- The hints in their box under the window (the game's way); none while
    -- the controller is in the game's window (R2 at the window's foot)
    local hb = g.hints
    hb:SetShown(not away)
    if away then return end
    local msg = f.msg:GetText() or ""
    local w = f:GetWidth() - 2 * HINT_PAD
    g.hintMsg:SetWidth(w)
    g.hintMsg:SetText(msg)
    g.hintMsg:SetShown(msg ~= "")
    g.hintText:Hide()
    -- Each hint: its glyphs then its word, both on one middle line (the
    -- game's hints); each row centred in the box, the box as wide as its
    -- widest row
    local y = msg ~= "" and (HINT_PAD + g.hintMsg:GetStringHeight() + 6) or HINT_PAD
    local used, widest = 0, 0
    for _, row in ipairs(self.hintRows or {}) do
        if #row > 0 then
            used = used + 1
            local line = g.hintLines[used]
            if not line then
                line = CK.NewFrame("Frame", nil, hb)
                line:SetHeight(HINT_GLYPH)
                line.items = {}
                g.hintLines[used] = line
            end
            local x = 0
            for i, it in ipairs(row) do
                local item = line.items[i]
                if not item then
                    item = { glyphs = {}, word = text(line, HINT_FONT, GAME_GOLD) }
                    line.items[i] = item
                end
                for k = #it.keys + 1, #item.glyphs do item.glyphs[k]:Hide() end
                if i > 1 then x = x + HINT_GAP end
                for k, key in ipairs(it.keys) do
                    local t = item.glyphs[k]
                    if not t then
                        t = line:CreateTexture(nil, "ARTWORK")
                        t:SetSize(HINT_GLYPH, HINT_GLYPH)
                        item.glyphs[k] = t
                    end
                    pcall(CK.SetGlyph, CK, t, key)
                    t:ClearAllPoints()
                    t:SetPoint("LEFT", line, "LEFT", x, 0)
                    t:Show()
                    x = x + HINT_GLYPH + 1
                end
                item.word:SetText(it.text or "")
                paint(item.word, it.grey and GAME_GREY or GAME_GOLD)
                item.word:ClearAllPoints()
                item.word:SetPoint("LEFT", line, "LEFT", x + 4, 0)
                item.word:Show()
                x = x + 4 + item.word:GetStringWidth()
            end
            for i = #row + 1, #line.items do
                for _, t in ipairs(line.items[i].glyphs) do t:Hide() end
                line.items[i].word:Hide()
            end
            line:SetWidth(math.max(1, x))
            line:ClearAllPoints()
            line:SetPoint("TOP", hb, "TOP", 0, -y)
            line:Show()
            widest = math.max(widest, x)
            y = y + HINT_GLYPH + 6
        end
    end
    for i = used + 1, #g.hintLines do g.hintLines[i]:Hide() end
    hb:SetHeight(y - 6 + HINT_PAD)
end

-- The full window's sections column: each with its picture and count
function B:DrawColumn()
    local col = f.column
    if not col:IsShown() then return end
    local cell = self.cells[self.index]
    local y = -10
    for i, s in ipairs(self.model.sections) do
        local r = columnRow(i)
        r.section = i
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 6, y)
        r:SetPoint("TOPRIGHT", -6, y)
        r.icon:SetTexture(B.KIND_ICON[s.id] or (s.id == "free" and "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
            or "Interface\\Icons\\INV_Misc_Bag_08")
        r.label:SetText(s.title)
        local n = 0
        for _, t in ipairs(s.tiles) do if not t.wide then n = n + 1 end end
        r.count:SetText(s.id == "free" and #self.model.free or n)
        local lit = cell and cell.pane == 1 and cell.section == i
        r.bg:SetShown(lit)
        paint(r.label, lit and COLOR.focus or COLOR.text)
        r:Show()
        y = y - 32
    end
    for i = #self.model.sections + 1, #col.rows do col.rows[i]:Hide() end
end

-- The full window's card: the lit item as the game describes it, how many
-- you have, what a vendor pays, what X does
function B:DrawDetail()
    local d = f.detail
    local item, tile, cell = self:LitItem()
    for _, fs in ipairs(d.lines) do fs:Hide() end
    if not item then
        d.icon:SetTexture(tile and tile.wide and "Interface\\PaperDoll\\UI-Backpack-EmptySlot" or nil)
        d.name:SetText(tile and tile.wide and tile.text or "")
        paint(d.name, COLOR.light)
        return
    end
    d.icon:SetTexture(item.icon)
    d.name:SetText(item.name)
    paint(d.name, qualityColor(item.quality))
    local n, y = 0, -70
    local function add(s, c, size)
        n = n + 1
        local fs = detailLine(n)
        font(fs, size or 13)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", d, "TOPLEFT", 14, y)
        fs:SetPoint("RIGHT", d, "RIGHT", -12, 0)
        fs:SetText(s)
        paint(fs, c or COLOR.light)
        fs:Show()
        y = y - (fs:GetStringHeight() or 14) - 4
    end
    -- the game's own tooltip lines (its first is the name, above)
    local data = C_TooltipInfo and C_TooltipInfo.GetBagItem and C_TooltipInfo.GetBagItem(item.bag, item.slot)
    if type(data) == "table" and type(data.lines) == "table" then
        for i = 2, math.min(#data.lines, 16) do
            local line = data.lines[i]
            local left = line and line.leftText
            if type(left) == "string" and left ~= "" and not (issecretvalue and issecretvalue(left)) then
                local c = line.leftColor
                local col = c and (c.GetRGB and { c:GetRGB() } or { c.r or 1, c.g or 1, c.b or 1 }) or COLOR.light
                local right = line.rightText
                if type(right) == "string" and right ~= "" and not (issecretvalue and issecretvalue(right)) then
                    left = left .. "   " .. right
                end
                add(left, col)
            end
        end
    end
    y = y - 6
    local count = C_Item.GetItemCount or GetItemCount
    local inBags = count(item.itemID) or 0
    local all = count(item.itemID, true) or inBags
    add(format(L.BAGS_HAVE, inBags, math.max(0, all - inBags)), COLOR.text)
    if (item.sellPrice or 0) > 0 and not item.noValue then
        add(format(L.BAGS_VENDOR, B.Money(item.sellPrice * item.count)), COLOR.text)
    end
end

-- The lit item's tooltip, the compact window's: the game's, beside ours
function B:Tooltip()
    local item = self:LitItem()
    if not (item and f:IsShown()) or self.more or self.visit or self:FullMode() then
        if GameTooltip:GetOwner() == f then GameTooltip:Hide() end
        return
    end
    GameTooltip:SetOwner(f, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", -6, 0)
    GameTooltip:SetBagItem(item.bag, item.slot)
    GameTooltip:Show()
end

-- Gold, silver, copper with their coins (GetCoinTextureString gave plain
-- copper in this client), or as letters (an option)
function B.Money(copper)
    copper = tonumber(copper) or 0
    local g, sv, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local letters = look().coinLetters
    local LETTER = { Gold = { L.COIN_G, "ffd700" }, Silver = { L.COIN_S, "c7c7cf" }, Copper = { L.COIN_C, "eda55f" } }
    local function coin(n, file)
        if letters then return format("%d|cff%s%s|r", n, LETTER[file][2], LETTER[file][1]) end
        return format("%d|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t", n, file)
    end
    local parts = {}
    if g > 0 then parts[#parts + 1] = coin(g, "Gold") end
    if g > 0 or sv > 0 then parts[#parts + 1] = coin(sv, "Silver") end
    parts[#parts + 1] = coin(c, "Copper")
    return table.concat(parts, " ")
end

-- The lit tile in sight (its pane scrolls with it)
function B:ScrollTo()
    local cell = self.cells and self.cells[self.index]
    if not cell then return end
    local pane = panes[cell.pane]
    local pad = pane.pad or 0
    local top = cell.y - (pane.labels == false and 0 or LABEL_H)
    local bottom = cell.y + pane.size + 2 * pad
    local view = pane.scroll:GetHeight()
    local now = pane.scroll:GetVerticalScroll() or 0
    if top < now then now = math.max(0, top) end
    -- (with room round the slots, none more: the whole bag fits at once)
    if bottom > now + view then now = bottom - view + (pad > 0 and 0 or 4) end
    pane.scroll:SetVerticalScroll(math.max(0, now))
end

---------------------------------------------------------------------------
-- Moving: worked out for every tile at each layout (out of combat), kept
-- on a secure frame of ours; the D-pad, LB / RB and LT / RT are secure
-- buttons whose snippet moves the light there - so it moves in combat too
-- (ControllerForever's Inv_Fight.lua idea; our wheels do the same). The
-- light read back in plain code draws it.
---------------------------------------------------------------------------
local nav

local function neighbor(cells, i, dir, size)
    local cur = cells[i]
    if not cur then return nil end
    local function samePane(c) return c.pane == cur.pane end
    if dir == "left" or dir == "right" then
        local step = dir == "left" and -1 or 1
        local j = i + step
        if cells[j] and samePane(cells[j]) then return j end
        -- (round the pane's ends)
        local first, last
        for k, c in ipairs(cells) do
            if samePane(c) then
                first = first or k
                last = k
            end
        end
        return step < 0 and last or first
    end
    if dir == "up" or dir == "down" then
        local cx = cur.x + (cur.span * size) / 2
        local step = dir == "up" and -1 or 1
        local rowY, best, bestD
        local j = i
        while true do
            j = j + step
            local c = cells[j]
            if not (c and samePane(c)) then break end
            if c.y ~= cur.y then
                if not rowY then rowY = c.y end
                if c.y ~= rowY then break end
                local d = math.abs((c.x + (c.span * size) / 2) - cx)
                if not bestD or d < bestD then best, bestD = j, d end
            end
        end
        return best
    end
    if dir == "lb" or dir == "rb" then
        -- the previous / next section's first tile (round), in the pane
        local sections = {}
        for k, c in ipairs(cells) do
            if samePane(c) and not sections[c.section] then sections[c.section] = k end
        end
        local n = 0
        for s in pairs(sections) do n = math.max(n, s) end
        local want = cur.section + (dir == "lb" and -1 or 1)
        for _ = 1, n do
            if want < 1 then want = n elseif want > n then want = 1 end
            if sections[want] then return sections[want] end
            want = want + (dir == "lb" and -1 or 1)
        end
        return nil
    end
    if dir == "lt" or dir == "rt" then
        -- the other pane (the bank's: LT; yours: RT), the nearest by height
        local want = dir == "lt" and 2 or 1
        if cur.pane == want then return nil end
        local best, bestD
        for k, c in ipairs(cells) do
            if c.pane == want then
                local d = math.abs(c.y - cur.y) * 3 + math.abs(c.x - cur.x)
                if not bestD or d < bestD then best, bestD = k, d end
            end
        end
        return best
    end
end

B.DIRS = { "up", "down", "left", "right", "lb", "rb", "lt", "rt" }

local NAV = [[
    local i = owner:GetAttribute("ec-lit") or 1
    local n = owner:GetAttribute("ec-" .. self:GetAttribute("ec-dir") .. "-" .. i)
    if n then owner:SetAttribute("ec-lit", n) end
    return false
]]
-- X: the lit tile's own macro ("/click <the game's slot button> RightButton")
local XCLICK = [[
    local i = owner:GetAttribute("ec-lit") or 1
    if not owner:GetAttribute("ec-x-" .. i) then return false end
    return "g" .. i
]]
-- B: our keys go, in combat too (the bags close: the game's backpack button)
local CLOSE = [[
    owner:ClearBindings()
    owner:SetAttribute("ec-cleared", true)
]]

-- The tables (out of combat): each tile's neighbours, what X clicks
function B:Tables()
    if InCombatLockdown() or not nav then return end
    local cells = self.cells or {}
    local where = B.Where()
    for i = 1, math.max(#cells, self.tableCount or 0) do
        local cell = cells[i]
        for _, dir in ipairs(B.DIRS) do
            nav:SetAttribute("ec-" .. dir .. "-" .. i, cell and neighbor(cells, i, dir, panes[cell.pane].size) or nil)
        end
        local text, use
        local item = cell and cell.tile.item
        if item and not self.bankMode then
            local label, no = B.xLabel(item, where)
            if label and not no then
                if where == "auction" then
                    -- The auction house takes it through its own slot
                    -- button's right-click (its own handling)
                    local button = ContainerFrameUtil_GetItemButtonAndContainer
                        and ContainerFrameUtil_GetItemButtonAndContainer(item.bag, item.slot)
                    local name = type(button) == "table" and button.GetName and button:GetName()
                    if name then text = "/click " .. name .. " RightButton" end
                else
                    -- Fork CoolerMgdn: the item used straight from its bag
                    -- and slot, as the game's right-click does (sold at a
                    -- vendor, worn, attached, traded, used): the game's
                    -- combined bags' slot buttons have no name to click
                    -- (found: X on trousers at a vendor did nothing)
                    use = item.bag .. " " .. item.slot
                end
            end
        end
        nav:SetAttribute("ec-x-" .. i, (text or use) and true or nil)
        self.xButton:SetAttribute("*type-g" .. i, use and "item" or "macro")
        self.xButton:SetAttribute("*item-g" .. i, use)
        self.xButton:SetAttribute("*macrotext-g" .. i, text)
    end
    self.tableCount = #cells
end

-- The light moved (by the secure snippets, or set here out of combat)
function B:Lit(i)
    if not (self.cells and self.cells[i]) then return end
    self.index = i
    self.message = nil
    self:ScrollTo()
    self:Draw()
end

function B:Focus(i)
    if not (self.cells and self.cells[i]) then return end
    if InCombatLockdown() then return end
    if nav:GetAttribute("ec-lit") == i then return self:Lit(i) end
    nav:SetAttribute("ec-lit", i)
end

function B:JumpTo(section)
    if InCombatLockdown() then return end
    for i, c in ipairs(self.cells or {}) do
        if c.pane == 1 and c.section == section then return self:Focus(i) end
    end
end

-- The menu's moves (Y open: the D-pad is plain then)
function B:Move(dir)
    if self.more then return self:MoreMove(dir) end
end

---------------------------------------------------------------------------
-- The buttons
---------------------------------------------------------------------------
function B:PressA()
    if self.more then return self:MoreChoose() end
    local item, tile, cell = self:LitItem()
    -- Fork CoolerMgdn: an empty slot shown (the game's look, one bag): what
    -- you hold goes there
    if tile and tile.empty then
        if CursorHasItem() then C_Container.PickupContainerItem(tile.bag, tile.slot) end
        return
    end
    if tile and tile.wide then
        if not CursorHasItem() then return end
        local m = cell.pane == 2 and self.bankModel or self.model
        local spot = m and m.free[1]
        if spot then C_Container.PickupContainerItem(spot.bag, spot.slot) end
        return
    end
    if not item then return end
    if item.locked and not CursorHasItem() then return end
    C_Container.PickupContainerItem(item.bag, item.slot)
end

function B:PressBack()
    if self.more then
        self.more = nil
        self:Bind()
        self:Draw()
        return
    end
    if CursorHasItem() then ClearCursor() end
end

-- At the bank, X: to the other side - a stack of it with room first, else
-- the first free slot (the server's own order); two pick ups, as A's
function B:MoveOver()
    local item, _, cell = self:LitItem()
    if not item or item.locked or CursorHasItem() then return end
    local toBank = cell.pane == 1
    local ids = toBank and B.BankIds() or B.BagIds()
    local maxStack = select(8, (C_Item.GetItemInfo or GetItemInfo)(item.itemID)) or 1
    local spot
    for _, bag in ipairs(ids) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == item.itemID and not info.isLocked
                and (info.stackCount or 1) + item.count <= maxStack then
                spot = spot or { bag = bag, slot = slot }
            end
        end
    end
    if not spot then
        local m = toBank and self.bankModel or self.model
        spot = m and m.free[1]
    end
    if not spot then
        self.message = toBank and L.BAGS_BANK_FULL or L.BAGS_FULL
        self:Draw()
        return
    end
    C_Container.PickupContainerItem(item.bag, item.slot)
    C_Container.PickupContainerItem(spot.bag, spot.slot)
    if CK.Flight then CK.Flight:Note("bags: %s %s", item.name, toBank and "to the bank" or "to the bags") end
end

-- The look after this one (Y: more)
function B.NextLayout()
    local now, at = look().layout, 1
    for i, v in ipairs(B.LAYOUTS) do if v == now then at = i end end
    return B.LAYOUTS[at % #B.LAYOUTS + 1]
end

-- X at a vendor: the lit item sold - picked up, sold from the cursor (the
-- game's own way for an item held over its window); nothing when the vendor
-- won't buy it
function B:Sell()
    if InCombatLockdown() or CursorHasItem() then return end
    local item = self:LitItem()
    if not item or item.locked then return end
    local _, no = B.xLabel(item, "vendor")
    if no then return end
    C_Container.PickupContainerItem(item.bag, item.slot)
    if CursorHasItem() then
        if SellCursorItem then SellCursorItem() end
        -- (not sold: back where it was)
        if CursorHasItem() then ClearCursor() end
    end
    if CK.Flight then CK.Flight:Note("bags sell %s", tostring(item.name)) end
end

-- L3: the game's own sort of your bags (out of combat; at the bank, its
-- own too); the window follows as they change
function B:Sort()
    if InCombatLockdown() or CursorHasItem() then return end
    local sort = C_Container and C_Container.SortBags or SortBags
    if self.bankMode then sort = C_Container and C_Container.SortBankBags or SortBankBags or sort end
    if sort then pcall(sort) end
    self.message = L.BAGS_SORTED
    self:Draw()
end

-- The game's own windows ours gives its keys to while they're up: its
-- stack split (D-pad: how many, A, B) and its "bind to the bar" (a press
-- of the buttons wanted)
local bindDialog, splitDialog   -- ours "pin to the bar" and split (B:BindToBar, B:OpenSplit)
local function gameDialogOpen()
    if splitDialog and splitDialog:IsShown() then return true end
    if bindDialog and bindDialog:IsShown() then return true end
    return false
end

-- An item that does something when used (a potion, a scroll, a bandage...):
-- the game's menu offers it for the bar
local function usable(item)
    local spell = C_Item and C_Item.GetItemSpell or GetItemSpell
    return spell and spell(item.itemID) ~= nil
end

-- Y: more - as the game's item menu: bind (a usable item), split (a
-- stack), destroy; search clear while there's one. Search is R3's, the
-- look is the settings' (asked: both off this list)
function B:MoreList()
    local item = self:LitItem()
    local list = {}
    if item and not item.locked then
        if usable(item) and CK.Mapping and CK.Mapping.PlaceInSlot then
            list[#list + 1] = { id = "bind", label = L.BAGS_BIND }
        end
        if item.count > 1 then
            if C_Container.SplitContainerItem then
                list[#list + 1] = { id = "split", label = L.BAGS_SPLIT }
            else
                -- (no game's split to drive: the old two)
                local half = math.floor(item.count / 2)
                if half > 1 then list[#list + 1] = { id = "half", label = format(L.BAGS_SPLIT_HALF, half) } end
                list[#list + 1] = { id = "one", label = L.BAGS_SPLIT_ONE }
            end
        end
        list[#list + 1] = { id = "destroy", label = L.BAGS_DESTROY }
    end
    if self.search and self.search ~= "" then list[#list + 1] = { id = "clear", label = L.BAGS_SEARCH_CLEAR } end
    return list
end

function B:OpenMore()
    if CursorHasItem() or InCombatLockdown() then return end
    local list = self:MoreList()
    if #list == 0 then return end
    self.more = list
    self.moreIndex = 1
    self:Bind()
    self:Draw()
end

function B:DrawMore()
    local m = f.more
    if not self.more then
        m:Hide()
        return
    end
    local widest = 120
    for i, e in ipairs(self.more) do
        local r = moreRow(i)
        r.label:SetText(e.label)
        paint(r.label, COLOR.text)
        r.bg:SetShown(i == self.moreIndex)
        r:Show()
        widest = math.max(widest, r.label:GetStringWidth())
    end
    for i = #self.more + 1, #m.rows do m.rows[i]:Hide() end
    m:SetSize(math.ceil(widest) + 48, 2 * MENU_PAD + #self.more * MENU_ROW)
    -- at the lit item, its arrow at the lit row (else beside the window)
    -- (the lit item's button on screen: its cell's data has no frame)
    local tile = self.litButton
    m:ClearAllPoints()
    if tile and tile.IsVisible and tile:IsVisible() then
        m:SetPoint("TOPLEFT", tile, "TOPRIGHT", 22, MENU_PAD)
    else
        m:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", -22, 0)
    end
    local lit = m.rows[self.moreIndex]
    m.arrow:ClearAllPoints()
    m.arrow:SetPoint("RIGHT", lit, "LEFT", 2, 0)
    -- its hints, in their box under it
    local ft, x = m.foot, HINT_PAD
    for i, it in ipairs(ft.items) do
        if i > 1 then x = x + HINT_GAP end
        pcall(CK.SetGlyph, CK, it.glyph, it.key)
        it.glyph:ClearAllPoints()
        it.glyph:SetPoint("LEFT", ft, "LEFT", x, 0)
        x = x + HINT_GLYPH + 5
        it.word:ClearAllPoints()
        it.word:SetPoint("LEFT", ft, "LEFT", x, 0)
        x = x + it.word:GetStringWidth()
    end
    ft:SetWidth(math.max(m:GetWidth(), x + HINT_PAD))
    m:Show()
end

local function backdrop(fr, center, border)
    if fr.NineSlice then
        if fr.NineSlice.SetCenterColor then pcall(fr.NineSlice.SetCenterColor, fr.NineSlice, unpack(center)) end
        if fr.NineSlice.SetBorderColor then pcall(fr.NineSlice.SetBorderColor, fr.NineSlice, unpack(border)) end
    elseif fr.SetBackdropColor then
        pcall(fr.SetBackdropColor, fr, unpack(center))
        pcall(fr.SetBackdropBorderColor, fr, unpack(border))
    end
end

local function boxFrame(parent)
    local ok, fr = pcall(CreateFrame, "Frame", nil, parent, "TooltipBackdropTemplate")
    if ok and fr then return fr end
    fr = CK.NewFrame("Frame", nil, parent)
    local bg = fr:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.03, 0.03, 0.04, 0.95)
    return fr
end

-- Split: a window as the game's own (its look: the amount between two
-- arrows, D-pad how many, A OK, B cancel), ours - the game's opened by an
-- addon runs tainted (its focus code blocked, as its bind window's was).
-- The split part comes on the cursor, A puts it down.
function B:StopSplit(n)
    local d = splitDialog
    if not (d and d:IsShown()) then return end
    d:Hide()
    if d.EnableGamePadButton then d:EnableGamePadButton(false) end
    d:EnableKeyboard(false)
    if n and n > 0 and not InCombatLockdown() then C_Container.SplitContainerItem(d.bag, d.slot, n) end
    if self.open then
        self:Bind()
        self:Draw()
    end
end

function B:OpenSplit(item, tile)
    if InCombatLockdown() then return end
    local d = splitDialog
    if not d then
        d = boxFrame(UIParent)
        backdrop(d, { 0.02, 0.02, 0.02, 0.95 }, { 0.86, 0.68, 0.2, 1 })
        d:SetFrameStrata("FULLSCREEN_DIALOG")
        d:SetSize(190, 60)
        d:SetClampedToScreen(true)
        local gl = CK.NewFrame("Frame", nil, d)
        gl:SetPoint("TOPLEFT", -14, 14)
        gl:SetPoint("BOTTOMRIGHT", 14, -14)
        local sl = CK.UIKit.nineSlice(gl, "ck_glow9", 64, 64, 24, 24, "OVERLAY")
        sl:SetFile("ck_glow9")
        sl:SetVertexColor(1, 0.82, 0.2)
        for _, part in ipairs(sl.parts) do part:SetBlendMode("ADD") end
        -- the amount in its dark field, an arrow each side
        local field = boxFrame(d)
        backdrop(field, { 0, 0, 0, 1 }, { 0.86, 0.68, 0.2, 1 })
        field:SetPoint("TOPLEFT", 26, -12)
        field:SetPoint("BOTTOMRIGHT", -26, 12)
        field:SetFrameLevel(d:GetFrameLevel() + 2)
        d.amount = text(field, 18, COLOR.text, "RIGHT")
        d.amount:SetPoint("RIGHT", -14, 0)
        d.left = d:CreateTexture(nil, "OVERLAY")
        d.left:SetTexture("Interface/AddOns/DualsenseForever/textures/ck_tri")
        d.left:SetSize(16, 16)
        d.left:SetRotation(-math.pi / 2)
        d.left:SetPoint("LEFT", 6, 0)
        d.right = d:CreateTexture(nil, "OVERLAY")
        d.right:SetTexture("Interface/AddOns/DualsenseForever/textures/ck_tri")
        d.right:SetSize(16, 16)
        d.right:SetRotation(math.pi / 2)
        d.right:SetPoint("RIGHT", -6, 0)
        -- its hints under it: A OK, D-pad how many, B cancel
        local ft = boxFrame(d)
        backdrop(ft, { 0.09, 0.09, 0.09, 0.92 }, { 0.62, 0.62, 0.62, 1 })
        ft:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -6)
        ft:SetHeight(HINT_GLYPH + 2 * HINT_PAD)
        ft.items = {}
        for k, it in ipairs({ { "A", OKAY or "OK" }, { "DPAD_LR", L.BAGS_SPLIT_AMOUNT }, { "B", CANCEL or L.V_BACK } }) do
            ft.items[k] = { key = it[1], glyph = ft:CreateTexture(nil, "ARTWORK"), word = text(ft, HINT_FONT + 2, GAME_GOLD) }
            ft.items[k].glyph:SetSize(HINT_GLYPH, HINT_GLYPH)
            ft.items[k].word:SetText(it[2])
        end
        d.foot = ft
        local function show(self)
            self.amount:SetText(self.n)
            self.left:SetVertexColor(1, 0.82, 0.2, self.n > 1 and 1 or 0.3)
            self.right:SetVertexColor(1, 0.82, 0.2, self.n < self.max - 1 and 1 or 0.3)
        end
        d.show = show
        d:SetScript("OnGamePadButtonDown", function(self, button)
            -- (held long: a step each repeat, the game's own repeat)
            if button == "PADDLEFT" then self.n = math.max(1, self.n - 1)
            elseif button == "PADDRIGHT" then self.n = math.min(self.max - 1, self.n + 1)
            elseif button == "PADDDOWN" then self.n = math.max(1, self.n - 10)
            elseif button == "PADDUP" then self.n = math.min(self.max - 1, self.n + 10)
            elseif button == "PAD1" then return B:StopSplit(self.n)
            elseif button == "PAD2" then return B:StopSplit(nil)
            end
            show(self)
        end)
        d:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then B:StopSplit(nil)
            elseif key == "ENTER" then B:StopSplit(self.n)
            elseif key == "LEFT" then self.n = math.max(1, self.n - 1); show(self)
            elseif key == "RIGHT" then self.n = math.min(self.max - 1, self.n + 1); show(self)
            end
        end)
        d:SetScript("OnEvent", function() B:StopSplit(nil) end)
        d:RegisterEvent("PLAYER_REGEN_DISABLED")
        d:Hide()
        splitDialog = d
    end
    d.bag, d.slot, d.max, d.n = item.bag, item.slot, item.count, 1
    d:ClearAllPoints()
    if tile and tile.IsVisible and tile:IsVisible() then
        d:SetPoint("BOTTOMLEFT", tile, "TOPLEFT", 0, 8)
    else
        d:SetPoint("CENTER", f, "CENTER")
    end
    local ft, x = d.foot, HINT_PAD
    for k, it in ipairs(ft.items) do
        if k > 1 then x = x + HINT_GAP end
        pcall(CK.SetGlyph, CK, it.glyph, it.key)
        it.glyph:ClearAllPoints()
        it.glyph:SetPoint("LEFT", ft, "LEFT", x, 0)
        x = x + HINT_GLYPH + 5
        it.word:ClearAllPoints()
        it.word:SetPoint("LEFT", ft, "LEFT", x, 0)
        x = x + it.word:GetStringWidth()
    end
    ft:SetWidth(x + HINT_PAD)
    d:SetWidth(math.max(190, x + HINT_PAD))
    d.show(d)
    self:ReleaseKeys()
    d:Show()
    d:EnableKeyboard(true)
    d:SetPropagateKeyboardInput(false)
    if d.EnableGamePadButton then d:EnableGamePadButton(true) end
end

-- Bind: as the game's own "pin to the bar" (press the buttons wanted),
-- but ours: the game's window opened by an addon runs tainted, its Back
-- and its edit then blocked (reported: ADDON_ACTION_FORBIDDEN
-- SetPreferredGamepadInteractTarget, B and Y dead in it). The press read
-- here, its slot the game's bar's (Mapping), the item placed as the
-- game's own editor does it.
local GLYPH_OF = { UP = "DPAD_UP", DOWN = "DPAD_DOWN", LEFT = "DPAD_LEFT", RIGHT = "DPAD_RIGHT" }

function B:StopBind(result)
    local d = bindDialog
    if not (d and d:IsShown()) then return end
    d:Hide()
    if d.EnableGamePadButton then d:EnableGamePadButton(false) end
    d:EnableKeyboard(false)
    if result then self.message = result end
    if self.open then
        self:Bind()
        self:Draw()
    end
end

function B:BindToBar(item)
    local M = CK.Mapping
    if not (M and M.NativeSlot and M.PlaceInSlot) or InCombatLockdown() then return end
    local d = bindDialog
    if not d then
        d = boxFrame(UIParent)
        backdrop(d, { 0.02, 0.02, 0.02, 0.95 }, { 0.86, 0.68, 0.2, 1 })
        d:SetFrameStrata("FULLSCREEN_DIALOG")
        d:SetSize(560, 190)
        d:SetPoint("TOP", UIParent, "TOP", 0, -120)
        local gl = CK.NewFrame("Frame", nil, d)
        gl:SetPoint("TOPLEFT", -14, 14)
        gl:SetPoint("BOTTOMRIGHT", 14, -14)
        local sl = CK.UIKit.nineSlice(gl, "ck_glow9", 64, 64, 24, 24, "OVERLAY")
        sl:SetFile("ck_glow9")
        sl:SetVertexColor(1, 0.82, 0.2)
        for _, part in ipairs(sl.parts) do part:SetBlendMode("ADD") end
        -- its title in a plate of its own on the top edge, as the game's
        local plate = boxFrame(d)
        backdrop(plate, { 0, 0, 0, 1 }, { 0.86, 0.68, 0.2, 1 })
        plate:SetSize(400, 40)
        plate:SetPoint("CENTER", d, "TOP", 0, 0)
        plate:SetFrameLevel(d:GetFrameLevel() + 6)
        d.title = text(plate, 20, GAME_GOLD, "CENTER")
        d.title:SetPoint("CENTER")
        d.title:SetText(L.BAGS_BIND_TITLE)
        d.ask = text(d, 17, COLOR.text, "CENTER")
        d.ask:SetPoint("TOP", 0, -38)
        d.ask:SetPoint("LEFT", 16, 0)
        d.ask:SetPoint("RIGHT", -16, 0)
        d.ask:SetWordWrap(true)
        d.ask:SetText(L.BAGS_BIND_ASK)
        d.name = text(d, 19, GAME_GOLD, "CENTER")
        d.name:SetPoint("TOP", d.ask, "BOTTOM", 0, -14)
        d.icon = d:CreateTexture(nil, "ARTWORK")
        d.icon:SetSize(42, 42)
        d.icon:SetPoint("TOP", d.name, "BOTTOM", 0, -8)
        d.note = text(d, 13, COLOR.warn, "CENTER")
        d.note:SetPoint("BOTTOM", 0, 10)
        -- its hints under it: B back
        local ft = boxFrame(d)
        backdrop(ft, { 0.09, 0.09, 0.09, 0.92 }, { 0.62, 0.62, 0.62, 1 })
        ft:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -6)
        ft:SetHeight(HINT_GLYPH + 2 * HINT_PAD)
        d.backGlyph = ft:CreateTexture(nil, "ARTWORK")
        d.backGlyph:SetSize(HINT_GLYPH, HINT_GLYPH)
        d.backGlyph:SetPoint("LEFT", HINT_PAD, 0)
        d.backWord = text(ft, HINT_FONT + 2, GAME_GOLD)
        d.backWord:SetPoint("LEFT", d.backGlyph, "RIGHT", 5, 0)
        d.backWord:SetText(L.V_BACK)
        d.foot = ft
        -- the press: the triggers held make its layer; B alone backs out
        d.held = {}
        d:SetScript("OnGamePadButtonDown", function(self, button)
            if button == "PADLTRIGGER" or button == "PADRTRIGGER" then
                self.held[button] = true
                return
            end
            -- (a trigger that is a modifier may come as its modifier only)
            local MOD_DOWN = { SHIFT = IsShiftKeyDown, CTRL = IsControlKeyDown, ALT = IsAltKeyDown }
            for _, t in ipairs({ "PADLTRIGGER", "PADRTRIGGER" }) do
                local mod = M:TriggerModifier(t)
                if mod and MOD_DOWN[mod] and MOD_DOWN[mod]() then self.held[t] = true end
            end
            local layer = (self.held.PADLTRIGGER and "LT" or "") .. (self.held.PADRTRIGGER and "RT" or "")
            if button == "PAD2" and layer == "" then return B:StopBind(nil) end
            local input
            for _, it in ipairs(M.INPUTS) do
                if not it.layer and M:InputKey(it) == button then input = it break end
            end
            local slot = input and M:NativeSlot(input, layer)
            if not slot then
                self.note:SetText(L.BAGS_BIND_NO)
                return
            end
            if M:PlaceInSlot(slot, "item:" .. self.itemID) then
                local keys = {}
                if self.held.PADLTRIGGER then keys[#keys + 1] = CK:GlyphMarkup("LT", 16) end
                if self.held.PADRTRIGGER then keys[#keys + 1] = CK:GlyphMarkup("RT", 16) end
                keys[#keys + 1] = CK:GlyphMarkup(GLYPH_OF[input.id] or input.id, 16)
                B:StopBind(format(L.BAGS_BIND_DONE, self.itemName or "", table.concat(keys, " + ")))
            else
                self.note:SetText(L.BAGS_BIND_NO)
            end
        end)
        d:SetScript("OnGamePadButtonUp", function(self, button) self.held[button] = nil end)
        d:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then B:StopBind(nil) end
        end)
        d:SetScript("OnEvent", function() B:StopBind(nil) end)
        d:RegisterEvent("PLAYER_REGEN_DISABLED")
        d:Hide()
        bindDialog = d
    end
    d.itemID, d.itemName = item.itemID, item.name
    d.name:SetText(item.name or "")
    d.icon:SetTexture(item.icon)
    d.note:SetText("")
    pcall(CK.SetGlyph, CK, d.backGlyph, "B")
    d.foot:SetWidth(HINT_PAD * 2 + HINT_GLYPH + 5 + d.backWord:GetStringWidth())
    wipe(d.held)
    -- (its keys: the buttons come here, not to the bags or the game)
    self:ReleaseKeys()
    d:Show()
    d:EnableKeyboard(true)
    d:SetPropagateKeyboardInput(false)
    if d.EnableGamePadButton then d:EnableGamePadButton(true) end
    if CK.Flight then CK.Flight:Note("bags: bind %s to the bar", tostring(item.name)) end
end

function B:MoreMove(dir)
    if dir == "UP" then self.moreIndex = (self.moreIndex - 2) % #self.more + 1 end
    if dir == "DOWN" then self.moreIndex = self.moreIndex % #self.more + 1 end
    self:Draw()
end

function B:MoreChoose()
    local e = self.more and self.more[self.moreIndex]
    if not e then return end
    local item = self:LitItem()
    local tile = self.litButton
    self.more = nil
    if e.id == "bind" and item then
        self:Draw()
        return self:BindToBar(item)
    elseif e.id == "split" and item then
        self:Draw()
        return self:OpenSplit(item, tile)
    elseif e.id == "half" and item then
        C_Container.SplitContainerItem(item.bag, item.slot, math.floor(item.count / 2))
    elseif e.id == "one" and item then
        C_Container.SplitContainerItem(item.bag, item.slot, 1)
    elseif e.id == "search" then
        return self:Search()
    elseif e.id == "clear" then
        self.search = nil
        self:Refresh()
    elseif e.id == "layout" then
        look().layout = B.NextLayout()
        self:Refresh()
    elseif e.id == "destroy" and item then
        -- The game's own "Destroy it?" popup (only inside a real press:
        -- this one, A's)
        local obj = Item and Item.CreateFromBagAndSlot and Item:CreateFromBagAndSlot(item.bag, item.slot)
        local guid = obj and obj.GetItemGUID and obj:GetItemGUID()
        if guid and C_Item.ConfirmDeleteItem then
            pcall(C_Item.ConfirmDeleteItem, guid)
        else
            C_Container.PickupContainerItem(item.bag, item.slot)
            if DeleteCursorItem then pcall(DeleteCursorItem) end
        end
    end
    self:Bind()
    self:Draw()
end

-- L2: over to the game's window beside ours (its cursor there: the game's
-- own LT / RT go between its windows); ours stays on screen, dimmed
function B:Visit()
    if self.visit or self.bankMode or not B.Where() or InCombatLockdown() then return end
    if CursorHasItem() then return end
    self.visit = true
    self.more = nil
    self:FadeGame(true)
    if not self:GameLook() then f.cover:Show() end
    self:Bind()
    self:Draw()
    if CK.Flight then CK.Flight:Note("bags: over to %s", tostring(B.Where())) end
end

-- R2 (or the window closing): back to ours, on the same item
function B:ComeBack()
    if not self.visit then return end
    self.visit = nil
    f.cover:Hide()
    self:FadeGame(true)
    if not InCombatLockdown() then
        self:Bind()
        self:Tables()
    end
    self:Draw()
end

-- R3 / Y > Search: the addon's keyboard; the items whose name has every word
function B:Search()
    if not CK.OpenPrompt or InCombatLockdown() then return end
    self:ReleaseKeys()
    self.typing = true
    local ok = CK:OpenPrompt(L.BAGS_SEARCH, self.search or "", function(text)
        B.typing = nil
        B.search = (text and text ~= "") and text or nil
        C_Timer.After(0, function()
            if B.open then
                B:Refresh()
                B:Bind()
            end
        end)
    end)
    if not ok then
        self.typing = nil
        self:Bind()
    end
end

---------------------------------------------------------------------------
-- Keys: ours over the game's bags while ours is open (priority), owned by
-- the secure frame (B clears them in combat too), given back as it closes,
-- a game popup shows, or the keyboard opens
---------------------------------------------------------------------------
local plain, secure = {}, {}

local function plainButton(name, fn)
    local b = CK.NewFrame("Button", "ControllerKeyboardBags" .. name, UIParent)
    b:Hide()
    b:RegisterForClicks("AnyDown")
    b:SetScript("OnClick", function() if B.open then fn() end end)
    plain[name] = b
    return b
end

local function secureButton(name, snippet)
    local b = CK.NewFrame("Button", "ControllerKeyboardBags" .. name, UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyDown")
    b:SetAttribute("useOnKeyDown", true)
    b:Hide()
    if snippet then SecureHandlerWrapScript(b, "OnClick", nav, snippet) end
    secure[name] = b
    return b
end

function B:BuildKeys()
    nav = CK.NewFrame("Frame", "ControllerKeyboardBagsNav", UIParent, "SecureHandlerBaseTemplate")
    -- (its keys through the bindings' one place, Binds.lua: layered, as B
    -- clears them in its secure code, in combat too)
    CK.Binds:Register("bags", nav, 50, true, { layered = true, label = "bags" })
    nav:SetAttribute("ec-lit", 1)
    nav:HookScript("OnAttributeChanged", function(_, name, value)
        if type(name) == "string" and name:lower() == "ec-lit" and B.open then B:Lit(value) end
    end)
    for _, dir in ipairs(B.DIRS) do
        local b = secureButton("Nav" .. dir, NAV)
        b:SetAttribute("ec-dir", dir)
    end
    plainButton("Up", function() B:Move("UP") end)
    plainButton("Down", function() B:Move("DOWN") end)
    plainButton("A", function() B:PressA() end)
    plainButton("Y", function() if B.more then B:PressBack() else B:OpenMore() end end)
    plainButton("R3", function() B:Search() end)
    -- Fork CoolerMgdn (asked): L3 sorts the bags (the game's own sort; one
    -- bag only, where there are no sections)
    plainButton("Sort", function() B:Sort() end)
    plainButton("Sell", function() B:Sell() end)
    plainButton("Back", function() B:PressBack() end)
    plainButton("Noop", function() end)
    plainButton("Visit", function() B:Visit() end)
    plainButton("ComeBack", function() B:ComeBack() end)
    plainButton("MoveOver", function() B:MoveOver() end)
    -- X: the lit tile's "/click <the game's own slot button> RightButton"
    -- (its right-click, as the game: use, equip, sell...), in combat too
    local x = secureButton("X", XCLICK)
    x:SetAttribute("type", "macro")
    x:HookScript("OnClick", function()
        if CK.Flight then
            local item = B:LitItem()
            CK.Flight:Note("bags X on %s", tostring(item and item.name))
        end
    end)
    self.xButton = x
    -- B: the game's backpack button, as its own click: the bags close
    local close = secureButton("Close", CLOSE)
    close:SetAttribute("type", "macro")
    close:SetAttribute("macrotext", "/click MainMenuBarBackpackButton")
    self.closeButton = close
end

local function popupOpen()
    for i = 1, 4 do
        local p = _G["StaticPopup" .. i]
        if p and p:IsVisible() then return true end
    end
    return gameDialogOpen()
end

function B:ReleaseKeys()
    if nav and not InCombatLockdown() then CK.Binds:Clear("bags") end
    self.bound = nil
end

function B:Bind()
    if InCombatLockdown() or not nav then return end
    CK.Binds:Clear("bags")
    nav:SetAttribute("ec-cleared", nil)
    self.bound = nil
    if not self.open or self.typing or popupOpen() then return end
    local function bind(key, button, mouse)
        for _, prefix in ipairs(PREFIXES) do
            CK.Binds:Set("bags", prefix .. key, "click", button:GetName(), mouse or "LeftButton")
        end
    end
    -- Over in the game's window: only R2 is ours (back)
    if self.visit then
        bind("PADRTRIGGER", plain.ComeBack)
        self.bound = true
        self.boundHolding = CursorHasItem() and true or false
        self.boundCheck = GetBindingAction("PADRTRIGGER", true)
        self.boundKey = "PADRTRIGGER"
        return
    end
    local holding = CursorHasItem() and true or false
    if self.more then
        bind("PADDUP", plain.Up)
        bind("PADDDOWN", plain.Down)
        bind("PADDLEFT", plain.Noop)
        bind("PADDRIGHT", plain.Noop)
        bind("PADLSHOULDER", plain.Noop)
        bind("PADRSHOULDER", plain.Noop)
        bind("PAD3", plain.Noop)
        bind("PADLTRIGGER", plain.Noop)
        bind("PADRTRIGGER", plain.Noop)
    else
        bind("PADDUP", secure.Navup)
        bind("PADDDOWN", secure.Navdown)
        bind("PADDLEFT", secure.Navleft)
        bind("PADDRIGHT", secure.Navright)
        bind("PADLSHOULDER", secure.Navlb)
        bind("PADRSHOULDER", secure.Navrb)
        if holding then
            bind("PAD3", plain.Noop)
        elseif self.bankMode then
            bind("PAD3", plain.MoveOver)
        elseif B.Where() == "vendor" then
            -- (out of combat: a vendor doesn't buy in a fight anyway)
            bind("PAD3", plain.Sell)
        else
            bind("PAD3", self.xButton)
        end
    end
    bind("PAD1", plain.A)
    bind("PAD4", plain.Y)
    bind("PADRSTICK", plain.R3)
    if look().order == "one" and not self.more then bind("PADLSTICK", plain.Sort) end
    bind("PAD2", (self.more or holding) and plain.Back or self.closeButton)
    if self.bankMode and not self.more then
        bind("PADLTRIGGER", secure.Navlt)
        bind("PADRTRIGGER", secure.Navrt)
    elseif B.Where() and not self.more then
        -- A game window beside ours: L2 goes over to it
        bind("PADLTRIGGER", plain.Visit)
        bind("PADRTRIGGER", plain.Noop)
    elseif not self.more then
        -- (the game's LT / RT would move its cursor in its faded windows)
        bind("PADLTRIGGER", plain.Noop)
        bind("PADRTRIGGER", plain.Noop)
    end
    self.bound = true
    self.boundHolding = holding
    self.boundCheck = GetBindingAction("PAD1", true)
    self.boundKey = "PAD1"
    self.boundWhere = B.Where()
end

---------------------------------------------------------------------------
-- The game's bags faded under ours (an animation owned by a frame of ours:
-- nothing set on them; stopping it puts them back - ControllerForever's
-- Skins.lua fadeMaker)
---------------------------------------------------------------------------
local fadeOwner
local fades = {}

local function fadeOne(region)
    fadeOwner = fadeOwner or CK.NewFrame("Frame")
    local fade = fades[region]
    if not fade then
        local group = fadeOwner:CreateAnimationGroup()
        local anim = group:CreateAnimation("Alpha")
        if not (anim and anim.SetTarget) then return end
        anim:SetTarget(region)
        anim:SetDuration(3600)
        anim:SetFromAlpha(0)
        anim:SetToAlpha(0)
        group:SetLooping("REPEAT")
        fade = group
        fades[region] = fade
    end
    if not fade:IsPlaying() then fade:Play() end
end

function B:FadeGame(on)
    if not on then
        for _, group in pairs(fades) do group:Stop() end
        return
    end
    local list = { ContainerFrameCombinedBags }
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do list[#list + 1] = _G["ContainerFrame" .. i] end
    -- (the bank: its own window under the two panes)
    if self.bankMode then list[#list + 1] = BankFrame end
    local pointer = SmartNavigation and type(SmartNavigation.Pointer) == "table" and SmartNavigation.Pointer.GetObjectType
        and SmartNavigation.Pointer
    if pointer then
        if self.visit then
            if fades[pointer] then fades[pointer]:Stop() end
        else
            list[#list + 1] = pointer
        end
    end
    for _, region in ipairs(list) do
        if type(region) == "table" and region.GetObjectType then pcall(fadeOne, region) end
    end
    if not self.bankMode and BankFrame and fades[BankFrame] then fades[BankFrame]:Stop() end
end

---------------------------------------------------------------------------
-- Open, close, follow the game's bags
---------------------------------------------------------------------------
B.BLOCKERS = { "GuildBankFrame", "LootFrame", "GossipFrame", "QuestFrame" }

local function bankOpen() return shown("BankFrame") end

function B:Blocked()
    for _, name in ipairs(B.BLOCKERS) do
        if shown(name) then return name end
    end
    if bankOpen() and not allowed("bank") then return "bank" end
    local where, ok = B.Where()
    if where and not ok then return where end
    if SpellIsTargeting and SpellIsTargeting() then return "targeting" end
    if CK.Config and CK.Config.IsOpen and CK.Config:IsOpen() then return "config" end
    if ControllerKeyboardWheel and ControllerKeyboardWheel:IsShown() then return "wheel" end
    if CK.IsOpen and CK:IsOpen() and not self.typing then return "keyboard" end
    return nil
end

-- In combat the tiles stay where they are (the secure tables can't
-- change): each one's slot read again, an item gone shows an empty slot
function B:RefreshInPlace()
    for _, cell in ipairs(self.cells or {}) do
        local old = cell.tile.item
        if old then
            local ok, item = pcall(itemOf, old.bag, old.slot)
            if ok and item then
                local t = self:TileOf(item)
                t.key = cell.tile.key
                cell.tile = t
            else
                cell.tile = { key = cell.tile.key, empty = true, item = nil }
                cell.tile.item = nil
            end
        end
    end
    self:Draw()
end

function B:Refresh()
    if not self.open then return end
    if InCombatLockdown() then
        self.dirty = true
        return self:RefreshInPlace()
    end
    self.dirty = nil
    local keep = self.cells and self.cells[self.index] and self.cells[self.index].tile.key
    self:Read()
    self:Layout()
    local at = 1
    for i, c in ipairs(self.cells) do
        if c.tile.key == keep then at = i end
    end
    self:Tables()
    if nav:GetAttribute("ec-lit") == at then self:Lit(at) else nav:SetAttribute("ec-lit", at) end
    self:Bind()
end

function B:Open()
    if self.open or InCombatLockdown() then return end
    self:Build()
    self.open = true
    self.more, self.message = nil, nil
    self.bankMode = bankOpen() and allowed("bank") or nil
    self.index = 1
    self:Read()
    self:Layout()
    self:FadeGame(true)
    f:Show()
    self:Tables()
    if nav:GetAttribute("ec-lit") == 1 then self:Lit(1) else nav:SetAttribute("ec-lit", 1) end
    self:Bind()
    if CK.Flight then CK.Flight:Note("bags open (%d items%s)", self.model.used, self.bankMode and ", bank" or "") end
end

function B:Close(why)
    if not self.open then return end
    self.open = false
    self.more, self.visit, self.message = nil, nil, nil
    if f then f.cover:Hide() end
    if not InCombatLockdown() then self:ReleaseKeys() end
    self:FadeGame(false)
    if f then f:Hide() end
    if GameTooltip:GetOwner() == f then GameTooltip:Hide() end
    if CK.Flight then CK.Flight:Note("bags close (%s)", tostring(why)) end
end

-- Ten times a second: the game's bags shown or not, a window that keeps
-- ours shut, a popup, the cursor (B's job)
function B:Tick()
    if not CK.db or self.typing then return end
    local fight = InCombatLockdown()
    -- (closed in combat by the game, our keys still set: given back now)
    if not self.open and self.bound and not fight then self:ReleaseKeys() end
    local blocked = self:Blocked()
    local want = on() and bagsShown() and not blocked
    if want and not self.open then
        -- (not in combat: our keys can't be set then)
        if not fight then self:Open() end
    elseif not want and self.open then
        if fight then
            -- (in combat: on screen until it ends, or B took our keys)
            if not bagsShown() then self:Close("closed in combat") end
        else
            self:Close(not bagsShown() and "closed" or (blocked or "off"))
        end
    elseif self.open and not fight then
        -- the bank opened or closed under it: the other window
        if (bankOpen() and allowed("bank") or nil) ~= self.bankMode then
            self.bankMode = bankOpen() and allowed("bank") or nil
            self:FadeGame(true)
            return self:Refresh()
        end
        if self.dirty then self:Refresh() end
        local holding = CursorHasItem() and true or false
        local popup = popupOpen()
        local where = B.Where()
        if self.visit and not where then self:ComeBack() end
        if popup and self.bound then
            self:ReleaseKeys()
        elseif not popup and (not self.bound or holding ~= self.boundHolding or (not self.visit and where ~= self.boundWhere)
            or (GetBindingAction(self.boundKey or "PAD1", true) ~= self.boundCheck and GetTime() - (self.reboundAt or 0) > 1)) then
            -- (the game's own keys put back over ours: once a second at most)
            self.reboundAt = GetTime()
            if where ~= self.boundWhere then self:Tables() end
            self:Bind()
            self:Draw()
        end
        self:FadeGame(true)
    end
end

local ticker = CK.NewFrame("Frame")
local elapsed = 0
ticker:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < POLL then return end
    elapsed = 0
    B:Tick()
end)

local events = CreateFrame("Frame")
for _, event in ipairs({ "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "PLAYER_MONEY",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GET_ITEM_INFO_RECEIVED", "CURSOR_CHANGED",
    "PLAYER_EQUIPMENT_CHANGED", "PLAYERBANKSLOTS_CHANGED" }) do
    pcall(events.RegisterEvent, events, event)
end
local queued
events:SetScript("OnEvent", function(_, event)
    if not B.open then return end
    if event == "PLAYER_REGEN_DISABLED" then
        -- (fires just before the lockdown: the menu, the keyboard and a
        -- visit end; the window stays, its secure keys work in combat)
        if B.visit then B:ComeBack() end
        if B.more then B.more = nil; B:Bind() end
        B:Draw()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        B:Refresh()
        return
    end
    if event == "CURSOR_CHANGED" or event == "PLAYER_MONEY" or event == "BAG_UPDATE_COOLDOWN" then
        B:Draw()
        return
    end
    if queued then return end
    queued = true
    C_Timer.After(0.05, function()
        queued = nil
        B:Refresh()
    end)
end)

-- Comfort > Bags (Options.lua)
function B.Rows(b)
    local s = settings()
    b.header(L.SEC_BAGS)
    b.module({ id = "bags_own", off = L.OFF_BAGS, sub = L.OFF_BAGS_SUB, label = L.LBL_OWN_BAGS, tip = L.TIP_OWN_BAGS,
        get = function() return s.ownBags == true end,
        set = function(v)
            s.ownBags = v and true or false
            if not v then B:Close("off") end
        end })
    local places = {}
    for _, w in ipairs(B.WHERE) do places[#places + 1] = w.key end
    places[#places + 1] = "bank"
    for _, key in ipairs(places) do
        b.check({ id = "bags_at_" .. key, label = L["LBL_BAGS_AT_" .. key:upper()], indent = true,
            disabled = not s.ownBags, tip = key == "bank" and L.TIP_BAGS_AT_BANK or L.TIP_BAGS_AT,
            get = function() return allowed(key) end,
            set = function(v)
                if type(s.bagsAt) ~= "table" then s.bagsAt = {} end
                s.bagsAt[key] = v and true or false
            end })
    end
    -- The look (ControllerForever's options)
    local lk = look()
    local off = not s.ownBags
    local function changed() if B.open then B:Refresh() end end
    local function cycle(key, list, d)
        local at = 1
        for i, v in ipairs(list) do if v == lk[key] then at = i end end
        lk[key] = list[(at - 1 + d) % #list + 1]
        changed()
    end
    b.header(L.HDR_BAGS_LOOK)
    b.choice({ id = "bags_layout", preview = function(c) CK.ConfigKit.Preview.Bags(c) end, label = L.LBL_BAGS_LAYOUT, disabled = off, tip = L.TIP_BAGS_LAYOUT,
        text = function() return L["BAGS_LAYOUT_" .. lk.layout:upper()] end,
        step = function(d) cycle("layout", B.LAYOUTS, d) end })
    b.choice({ id = "bags_order", preview = function(c) CK.ConfigKit.Preview.Bags(c) end, label = L.LBL_BAGS_ORDER, disabled = off, tip = L.TIP_BAGS_ORDER,
        text = function() return L["BAGS_ORDER_" .. lk.order:upper()] end,
        step = function(d) cycle("order", B.ORDERS, d) end })
    -- Fork CoolerMgdn (asked): one bag: its empty slots one by one
    b.check({ id = "bags_empty", label = L.LBL_BAGS_EMPTY, indent = true, disabled = off or lk.order ~= "one",
        tip = L.TIP_BAGS_EMPTY,
        get = function() return lk.emptySlots end, set = function(v) lk.emptySlots = v; changed() end })
    b.check({ id = "bags_ilvl", label = L.LBL_BAGS_ILVL, disabled = off, tip = L.TIP_BAGS_ILVL,
        get = function() return lk.itemLevel end, set = function(v) lk.itemLevel = v; changed() end })
    b.choice({ id = "bags_ilvlc", label = L.LBL_BAGS_ILVL_COLOR, indent = true, disabled = off or not lk.itemLevel,
        tip = L.TIP_BAGS_ILVL_COLOR,
        text = function() return lk.levelQuality and L.BAGS_QUALITY or L.BAGS_WHITE end,
        step = function() lk.levelQuality = not lk.levelQuality; changed() end })
    b.check({ id = "bags_marks", label = L.LBL_BAGS_MARKS, disabled = off, tip = L.TIP_BAGS_MARKS,
        get = function() return lk.marks end, set = function(v) lk.marks = v; changed() end })
    b.check({ id = "bags_glow", label = L.LBL_BAGS_GLOW, disabled = off, tip = L.TIP_BAGS_GLOW,
        get = function() return lk.newGlow end, set = function(v) lk.newGlow = v; changed() end })
    b.check({ id = "bags_junk", label = L.LBL_BAGS_JUNK, disabled = off, tip = L.TIP_BAGS_JUNK,
        get = function() return lk.junkCoin end, set = function(v) lk.junkCoin = v; changed() end })
    b.choice({ id = "bags_edge", preview = function(c) CK.ConfigKit.Preview.Bags(c) end, label = L.LBL_BAGS_EDGE, disabled = off, tip = L.TIP_BAGS_EDGE,
        text = function() return L["BAGS_EDGE_" .. lk.edgeColor:upper()] end,
        step = function(d) cycle("edgeColor", B.EDGE_COLORS, d) end })
    b.choice({ id = "bags_edges", preview = function(c) CK.ConfigKit.Preview.Bags(c) end, label = L.LBL_BAGS_EDGE_SIZE, indent = true, disabled = off, tip = L.TIP_BAGS_EDGE_SIZE,
        text = function() return L["BAGS_EDGE_SIZE_" .. tostring(lk.edgeSize)] end,
        step = function(d) cycle("edgeSize", B.EDGE_SIZES, d) end })
    b.check({ id = "bags_letters", label = L.LBL_BAGS_LETTERS, disabled = off, tip = L.TIP_BAGS_LETTERS,
        get = function() return lk.coinLetters end, set = function(v) lk.coinLetters = v; changed() end })
    -- Fork CoolerMgdn (asked): the game's look: its ground's transparency
    b.choice({ id = "bags_alpha", label = L.LBL_BAGS_ALPHA, disabled = off or lk.layout ~= "blizzard", tip = L.TIP_BAGS_ALPHA,
        text = function() return format("%d %%", math.floor((tonumber(lk.bgAlpha) or 1) * 100 + 0.5)) end,
        step = function(d)
            lk.bgAlpha = math.max(0.3, math.min(1, math.floor(((tonumber(lk.bgAlpha) or 1) + d * 0.05) * 100 + 0.5) / 100))
            changed()
        end })
    b.choice({ id = "bags_scale", label = L.LBL_BAGS_SCALE, disabled = off, tip = L.TIP_BAGS_SCALE,
        text = function() return format("%d %%", math.floor((tonumber(lk.scale) or 1) * 100 + 0.5)) end,
        step = function(d)
            lk.scale = math.max(0.8, math.min(1.1, math.floor(((tonumber(lk.scale) or 1) + d * 0.05) * 100 + 0.5) / 100))
            changed()
        end })
end
