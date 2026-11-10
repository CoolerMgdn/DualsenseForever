local _, CK = ...
local L = CK.L

---------------------------------------------------------------------------
-- Fork CoolerMgdn: two more wheels, drawn and handled like the others
-- (ConsumableWheel.lua; the idea: ControllerForever's MarkWheel.lua and
-- ClassWheels.lua, its author's code free to reuse):
--   "wheel:marks"  the eight target marks on your target ("/tm"), and Clear
--                  on its second page (LB / RB)
--   "wheel:class"  what your class knows that you switch between: stances,
--                  forms, auras, seals and blessings, aspects and tracking,
--                  portals and teleports, pets, presences... found in the
--                  spell book by name (any language: the names come from the
--                  game, each spell's first rank), its best rank cast
-- The party wheel is there already (Gamepad tab, Party: a spell's wheel).
---------------------------------------------------------------------------
local CW = {}
CK.ClassWheels = CW

local SEGMENTS = 8

-- Kill order first: skull, cross, square, moon, triangle, diamond, circle, star
local MARKS = { 8, 7, 6, 5, 4, 3, 2, 1 }

function CW:MarkPages()
    local list = {}
    for _, i in ipairs(MARKS) do
        list[#list + 1] = { kind = "macrotext", text = "/tm " .. i, name = _G["RAID_TARGET_" .. i] or ("#" .. i),
            icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i }
    end
    local clear = { { kind = "macrotext", text = "/tm 0", name = RAID_TARGET_NONE or L.MARK_CLEAR,
        icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up" } }
    return { [1] = list, [2] = clear }
end

-- Each class's spells (one rank's ID: the name is what counts), in order
local CLASS_SPELLS = {
    WARRIOR = { 2457, 71, 2458, 6673, 469, 1161 },
    DRUID = { 5487, 9634, 768, 783, 1066, 24858, 33891, 33943, 40120, 1126, 467, 21849 },
    PALADIN = { 465, 7294, 19746, 19876, 19888, 19891, 20218, 32223,
        21084, 20154, 21082, 20164, 20165, 20166, 20375, 31801, 31892,
        19740, 19742, 20217, 1038, 19977, 20911 },
    HUNTER = { 13165, 13163, 5118, 13159, 20043, 13161, 34074, 1494, 19883, 19884, 19885, 19880, 19878, 19882, 19879,
        883, 2641, 982, 136, 6991, 1515 },
    MAGE = { 3561, 3562, 3563, 3565, 3566, 3567, 32271, 32272, 33690, 35715, 49359, 49358, 53140,
        10059, 11416, 11418, 11419, 11420, 11417, 32266, 32267, 33691, 35717, 49360, 49361, 53142,
        1459, 23028, 168, 7302, 6117, 30482 },
    WARLOCK = { 688, 697, 712, 691, 30146, 1122, 18540, 698, 29893, 687, 706, 28176, 6201, 693 },
    SHAMAN = { 2645, 8017, 8024, 8033, 8232, 51730, 324, 52127, 556 },
    PRIEST = { 1243, 21562, 14752, 27681, 976, 27683, 588, 15473, 2096, 1706 },
    ROGUE = { 1784, 1804, 2842 },
    DEATHKNIGHT = { 48266, 48263, 48265, 46584, 50977, 57330, 3714 },
}

local function spellName(id)
    local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or (GetSpellInfo and GetSpellInfo(id))
    -- (CK.Plain is for numbers: a name is checked here)
    if type(n) ~= "string" or (issecretvalue and issecretvalue(n)) then return nil end
    return n
end

-- The names wanted, in their order
local function wanted()
    local _, class = UnitClass("player")
    local order, byName = {}, {}
    for i, id in ipairs(CLASS_SPELLS[class] or {}) do
        local n = spellName(id)
        if n and not byName[n] then
            byName[n] = i
            order[#order + 1] = n
        end
    end
    return byName
end

-- What the spell book has of them (its best rank: the last one listed)
function CW:ClassSpells()
    local byName = wanted()
    local found = {}
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return {} end
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if info and not info.shouldHide then
            for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                local id = item and item.spellID
                local n = id and not item.isPassive and not item.isOffSpec and spellName(id)
                if n and byName[n] then found[n] = { kind = "spell", id = id, order = byName[n] } end
            end
        end
    end
    local list = {}
    for _, e in pairs(found) do list[#list + 1] = e end
    table.sort(list, function(a, b) return a.order < b.order end)
    return list
end

function CW:ClassPages()
    local pages = {}
    for n, e in ipairs(self:ClassSpells()) do
        local page = math.floor((n - 1) / SEGMENTS) + 1
        if page > 3 then break end
        pages[page] = pages[page] or {}
        pages[page][(n - 1) % SEGMENTS + 1] = e
    end
    return pages
end

CW.MARK_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"

function CW:ClassIcon()
    local _, class = UnitClass("player")
    local first = (CLASS_SPELLS[class] or {})[1]
    local icon = first and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(first)
    return icon or "Interface\\Icons\\INV_Misc_Book_09"
end
