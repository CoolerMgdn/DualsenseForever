local addonName, CK = ...
local L = CK.L

-- Fork CoolerMgdn (asked, its prototype approved): the settings exported as
-- a text string and imported from one (Profiles › Exchange). The game gives
-- addons no files and no clipboard: the string is shown selected for Ctrl+C,
-- and pasted with Ctrl+V into a field (a physical keyboard: our own keyboard
-- can't paste).
--
-- The string: "DSF1:" .. "P" (plain) or "Z" (deflated, when the client can)
-- .. ":" .. base64 .. ":" .. a checksum of what came before it. Inside, our
-- own serialization: s<len>:<bytes>, n<number>;, T, F, { key value ... }.
-- Only the settings each section names are read back (a string can't set
-- anything else), each of the type it has here.
--
-- Sections: buttons (the profile's buttons, its gamepad bar slots, the
-- trigger modifiers), wheels, touchpad, keyboard, phrases, comfort, look.
-- Never: the learned words, the fishing weapons, the paddles' keys, the
-- windows' places (each computer's and character's own).
--
-- An import keeps what it replaces (CK.db.exchangeUndo, the last one): undone
-- from the Profiles tab. It reloads the interface after: every module reads
-- its settings as they are then.
local X = {}
CK.Exchange = X

local K = CK.ConfigKit
local KC = K.C
local W = 820
local PREFIX = "DSF"
local FORMAT = 1

local function settings() return CK.db.settings end
local function C() return CK.Config end
local function Pr() return CK.Profiles end

local function copy(v)
    if type(v) ~= "table" then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = copy(x) end
    return c
end

---------------------------------------------------------------------------
-- Serialization
---------------------------------------------------------------------------
local function num(v)
    local s = tostring(v)
    if tonumber(s) ~= v then s = format("%.17g", v) end
    return "n" .. s .. ";"
end

local function ser(v, out, depth)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return false end
        out[#out + 1] = num(v)
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "table" and depth < 24 then
        out[#out + 1] = "{"
        for k, x in pairs(v) do
            local kt = type(k)
            if (kt == "string" or kt == "number") and type(x) ~= "function" and type(x) ~= "userdata" then
                local mark = #out
                if not (ser(k, out, depth + 1) and ser(x, out, depth + 1)) then
                    for i = #out, mark + 1, -1 do out[i] = nil end
                end
            end
        end
        out[#out + 1] = "}"
    else
        return false
    end
    return true
end

local function serialize(v)
    local out = {}
    ser(v, out, 0)
    return table.concat(out)
end

-- (errors: the string is broken)
local function parse(s, i, depth)
    if depth > 24 then error("deep") end
    local c = s:sub(i, i)
    if c == "s" then
        local colon = s:find(":", i + 1, true)
        local n = colon and tonumber(s:sub(i + 1, colon - 1))
        if not n or n < 0 then error("len") end
        local str = s:sub(colon + 1, colon + n)
        if #str ~= n then error("short") end
        return str, colon + n + 1
    elseif c == "n" then
        local semi = s:find(";", i + 1, true)
        local v = semi and tonumber(s:sub(i + 1, semi - 1))
        if not v then error("num") end
        return v, semi + 1
    elseif c == "T" then
        return true, i + 1
    elseif c == "F" then
        return false, i + 1
    elseif c == "{" then
        local t = {}
        i = i + 1
        while s:sub(i, i) ~= "}" do
            if i > #s then error("open") end
            local k, v
            k, i = parse(s, i, depth + 1)
            v, i = parse(s, i, depth + 1)
            if type(k) ~= "string" and type(k) ~= "number" then error("key") end
            t[k] = v
        end
        return t, i + 1
    end
    error("byte")
end

local function deserialize(s)
    local ok, v, nexti = pcall(parse, s, 1, 0)
    if not ok or nexti ~= #s + 1 then return nil end
    return v
end

---------------------------------------------------------------------------
-- Base64, the checksum, the compression (the client's, when it has it)
---------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, 64 do B64_INDEX[B64:byte(i)] = i - 1 end

local function encode64(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1, c2 = math.floor(n / 262144), math.floor(n / 4096) % 64
        local c3, c4 = math.floor(n / 64) % 64, n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

local function decode64(s)
    s = s:gsub("=+$", "")
    local out, n, bits = {}, 0, 0
    for i = 1, #s do
        local v = B64_INDEX[s:byte(i)]
        if not v then return nil end
        n, bits = n * 64 + v, bits + 6
        if bits >= 8 then
            bits = bits - 8
            local byte = math.floor(n / 2 ^ bits)
            out[#out + 1] = string.char(byte)
            n = n - byte * 2 ^ bits
        end
    end
    return table.concat(out)
end

local function checksum(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return format("%04x%04x", b, a)
end

local function deflateMethod()
    local E = C_EncodingUtil
    local M = Enum and Enum.CompressionMethod
    if E and E.CompressString and E.DecompressString and M and M.Deflate then return E, M.Deflate end
end

local function deflate(s)
    local E, method = deflateMethod()
    if not E then return nil end
    local ok, out = pcall(E.CompressString, s, method)
    return ok and type(out) == "string" and #out < #s and out or nil
end

local function inflate(s)
    local E, method = deflateMethod()
    if not E then return nil end
    local ok, out = pcall(E.DecompressString, s, method)
    return ok and type(out) == "string" and out or nil
end

function X.Encode(data)
    local raw = serialize(data)
    local packed = deflate(raw)
    local body = (packed and "Z" or "P") .. ":" .. encode64(packed or raw)
    local head = PREFIX .. FORMAT .. ":" .. body
    return head .. ":" .. checksum(head)
end

-- data, or nil and why: "empty", "notOurs", "newer", "broken", "noInflate"
function X.Decode(str)
    str = type(str) == "string" and str:gsub("%s+", "") or ""
    if str == "" then return nil, "empty" end
    local version, rest = str:match("^" .. PREFIX .. "(%d+):(.*)$")
    if not version then return nil, "notOurs" end
    if tonumber(version) > FORMAT then return nil, "newer" end
    local mode, body, sum = rest:match("^([PZ]):([%w%+/=]+):(%x+)$")
    if not mode or checksum(PREFIX .. version .. ":" .. mode .. ":" .. body) ~= sum then return nil, "broken" end
    local raw = decode64(body)
    if not raw then return nil, "broken" end
    if mode == "Z" then
        if not deflateMethod() then return nil, "noInflate" end
        raw = inflate(raw)
        if not raw then return nil, "broken" end
    end
    local data = deserialize(raw)
    if type(data) ~= "table" or type(data.sections) ~= "table" then return nil, "broken" end
    return data
end

---------------------------------------------------------------------------
-- The sections: the settings each one holds (dotted paths in settings)
---------------------------------------------------------------------------
local CVARS = { "GamePadEmulateShift", "GamePadEmulateCtrl", "GamePadEmulateAlt" }

-- "modules.*" / "features.*": every key there but those of other sections
local function under(prefix, but)
    return function()
        local list = {}
        for k in pairs(settings()[prefix] or {}) do
            if not but[k] then list[#list + 1] = prefix .. "." .. k end
        end
        return list
    end
end

X.SECTIONS = {
    { key = "buttons", paths = { "mapping", "replaced", "features.triggerToggle", "modules.mapping", "extraFree",
        "extraSymmetric", "badgePlace" }, cvars = true, slots = true },
    { key = "wheels", paths = { "wheel", "myWheels", "supplies" } },
    { key = "touch", paths = { "touch" } },
    { key = "keyboard", paths = { "modules.keyboard", "inputMethod", "kbLayout", "petalRings", "lang", "numSuggestions",
        "maxWords", "deadzone", "stickCurve", "magnet", "showLine", "showActions", "stickyChannel", "openFields",
        "autoOpen", "onlyWithGamepad", "learn", "invertY", "phrasesChip" } },
    { key = "phrases", paths = { "phrases" } },
    { key = "comfort", paths = { "vibration", "perf", "ownBags", "bagsAt", "camera", "automation", "minimapLabels",
        "reticle" }, more = { under("modules", { keyboard = true, mapping = true }), under("features", { triggerToggle = true }) } },
    { key = "look", paths = { "glyphStyle", "gameGlyphs", "nativeGlyphs", "configLook", "configScale", "bagsLook",
        "barScale", "barOffset", "font", "scale" } },
}

local function sectionOf(key)
    for _, sec in ipairs(X.SECTIONS) do
        if sec.key == key then return sec end
    end
end

local function pathsOf(sec)
    local list = {}
    for _, p in ipairs(sec.paths) do list[#list + 1] = p end
    for _, more in ipairs(sec.more or {}) do
        for _, p in ipairs(more()) do list[#list + 1] = p end
    end
    return list
end

local function getPath(path)
    local t = settings()
    for part in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end

local function setPath(path, v)
    local t = settings()
    local parts = {}
    for part in path:gmatch("[^%.]+") do parts[#parts + 1] = part end
    for i = 1, #parts - 1 do
        if type(t[parts[i]]) ~= "table" then t[parts[i]] = {} end
        t = t[parts[i]]
    end
    t[parts[#parts]] = v
end

-- A path a section may set: one it names, or one under its "*" (modules.x)
local function allowed(sec, path)
    for _, p in ipairs(sec.paths) do
        if p == path then return true end
    end
    if sec.key == "comfort" then
        local head, tail = path:match("^(%a+)%.([%w_]+)$")
        if head == "modules" then return tail ~= "keyboard" and tail ~= "mapping" end
        if head == "features" then return tail ~= "triggerToggle" end
    end
    return false
end

-- The value's type as this addon has it (the default's, else the current's)
local function typeOk(path, v)
    local def = CK.DEFAULTS
    for part in path:gmatch("[^%.]+") do def = type(def) == "table" and def[part] or nil end
    local want = def ~= nil and type(def) or (getPath(path) ~= nil and type(getPath(path))) or nil
    return want == nil or want == type(v)
end

-- The profile in use's slots (Profiles.lua): fresh
local function profileSlots()
    local P = Pr()
    local p = P and P:Profile()
    if not (p and type(p.data.slots) == "table") then return nil end
    if P.Slots and P.Slots.Snapshot then pcall(P.Slots.Snapshot, P.Slots, p.data.slots) end
    return p.data.slots
end

-- The sections picked, as they are now: { [path] = value }
function X.Collect(chosen)
    if CK.Profiles and CK.Profiles.Collect then CK.Profiles:Collect() end
    local out = {}
    for _, sec in ipairs(X.SECTIONS) do
        if chosen[sec.key] then
            local d = {}
            for _, path in ipairs(pathsOf(sec)) do
                local v = getPath(path)
                if v ~= nil then d[path] = copy(v) end
            end
            if sec.cvars then
                for _, name in ipairs(CVARS) do d["cvar." .. name] = GetCVar(name) or "" end
            end
            if sec.slots then d.slots = copy(profileSlots()) end
            out[sec.key] = d
        end
    end
    return out
end

local function myClass()
    local _, class = UnitClass("player")
    return class
end

function X.Payload(chosen)
    local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local P = Pr()
    return { v = FORMAT, addon = get and get(addonName, "Version") or "", class = myClass(),
        profile = P and select(2, P:ActiveSet()) or "", date = date("%Y-%m-%d"), sections = X.Collect(chosen) }
end

-- What a section holds, said short (export's right column)
function X.Count(key)
    local s = settings()
    local function size(t)
        local n = 0
        for _ in pairs(type(t) == "table" and t or {}) do n = n + 1 end
        return n
    end
    if key == "buttons" then return format(L.EX_COUNT_BUTTONS, size(s.mapping) + size(s.replaced)) end
    if key == "wheels" then
        local n = size(s.myWheels and s.myWheels.list)
        return n > 0 and format(L.EX_COUNT_WHEELS, n) or ""
    end
    if key == "keyboard" then
        return s.inputMethod == "stick" and L.METHOD_STICK or s.inputMethod == "grid" and L.METHOD_GRID or L.METHOD_WHEEL
    end
    if key == "phrases" then
        local n = size(s.phrases and (s.phrases.list or s.phrases))
        return n > 0 and format(L.EX_COUNT_PHRASES, n) or ""
    end
    if key == "look" then return L["CFG_LOOK_" .. K.LookOf(s.configLook):upper()] end
    return ""
end

---------------------------------------------------------------------------
-- Import
---------------------------------------------------------------------------
-- Another class's spells: the actions this character doesn't know
local function foreignOf(names)
    local P = Pr()
    return function(action)
        return names and P.ForeignSpell and P.ForeignSpell(action, names) or false
    end
end

-- A table of actions ({ key = "spell:1" ... }) taken from the string, its
-- other class's spells left as they are here
local function keepOwn(incoming, current, isForeign, skipped)
    if type(incoming) ~= "table" then return incoming end
    local out = {}
    for k, v in pairs(incoming) do
        if isForeign(v) then
            skipped.n = skipped.n + 1
        else
            out[k] = v
        end
    end
    for k, v in pairs(type(current) == "table" and current or {}) do
        if out[k] == nil and isForeign(incoming[k]) then out[k] = v end
    end
    return out
end

local function slotForeign(isForeign)
    return function(v)
        return type(v) == "table" and v.t == "spell" and isForeign("spell:" .. tostring(v.id))
    end
end

-- One section from the string into the settings
local function applySection(sec, d, opts, skipped)
    local isForeign = opts.skip and foreignOf(opts.names) or function() return false end
    for path, v in pairs(d) do
        if type(path) ~= "string" then
            -- (nothing: not ours)
        elseif path == "slots" then
            local P = Pr()
            local p = P and P:Profile()
            if sec.slots and p and type(v) == "table" then
                p.data.slots = keepOwn(v, p.data.slots, slotForeign(isForeign), skipped)
            end
        elseif path:match("^cvar%.") then
            local name = path:sub(6)
            if sec.cvars and tContains(CVARS, name) and type(v) == "string" then pcall(SetCVar, name, v) end
        elseif allowed(sec, path) and typeOk(path, v) then
            v = copy(v)
            if path == "mapping" or path == "replaced" then v = keepOwn(v, getPath(path), isForeign, skipped) end
            if path == "myWheels" and type(v) == "table" and type(v.list) == "table" then
                for _, w in ipairs(v.list) do
                    if type(w) == "table" and type(w.slots) == "table" then
                        w.slots = keepOwn(w.slots, nil, isForeign, skipped)
                    end
                end
            end
            setPath(path, v)
        end
    end
end

-- opts: { take = { [key] = true }, into = "current" | "new", skip = bool }.
-- Returns what was done: { sections = {...}, skipped = n, newSet = name }
function X.Apply(data, opts)
    if InCombatLockdown() then
        CK:BlockedByCombat()
        return nil
    end
    local P = Pr()
    local done = { sections = {}, skipped = 0 }
    local inProfile = (opts.take.buttons and data.sections.buttons) or (opts.take.wheels and data.sections.wheels)
    -- What it replaces, kept to undo it (the sections of a new profile: the
    -- old one is untouched)
    local keep = {}
    for key in pairs(opts.take) do
        if data.sections[key] and not (opts.into == "new" and (key == "buttons" or key == "wheels")) then keep[key] = true end
    end
    CK.db.exchangeUndo = { date = date("%Y-%m-%d %H:%M"), profile = data.profile, sections = X.Collect(keep) }
    if inProfile and opts.into == "new" and P then
        local id = P:CreateSet()
        if id then
            local name = type(data.profile) == "string" and data.profile ~= "" and data.profile or nil
            if name then P:RenameSet(id, name) end
            done.newSet = P:SetName(id)
        end
    end
    local names = opts.skip and P and P.KnownSpells and P.KnownSpells() or nil
    local skipped = { n = 0 }
    for _, sec in ipairs(X.SECTIONS) do
        local d = data.sections[sec.key]
        if opts.take[sec.key] and type(d) == "table" then
            applySection(sec, d, { skip = opts.skip and names ~= nil, names = names }, skipped)
            done.sections[#done.sections + 1] = sec.key
        end
    end
    done.skipped = skipped.n
    if P and P.Collect then P:Collect() end
    if P and P.Reread then pcall(P.Reread) end
    return done
end

-- The last import undone: what it replaced, back
function X.CanUndo()
    local u = CK.db and CK.db.exchangeUndo
    return type(u) == "table" and type(u.sections) == "table" and next(u.sections) ~= nil
end

function X.Undo()
    if not X.CanUndo() or CK:BlockedByCombat() then return end
    local u = CK.db.exchangeUndo
    local take = {}
    for key in pairs(u.sections) do take[key] = true end
    for _, sec in ipairs(X.SECTIONS) do
        if take[sec.key] then applySection(sec, u.sections[sec.key], {}, { n = 0 }) end
    end
    CK.db.exchangeUndo = nil
    local P = Pr()
    if P and P.Collect then P:Collect() end
    local reload = C_UI and C_UI.Reload or ReloadUI
    reload()
end

---------------------------------------------------------------------------
-- The window: a layer over the panel's (as the guide), built with the
-- guide's parts. Screens: export (the sections), exportStr (the string),
-- import (the field), importPick (what to take, where), importDone.
---------------------------------------------------------------------------
local Kit
local function kit() Kit = Kit or CK.Guide.Kit return Kit end

local TITLES = { export = "EX_T_EXPORT", exportStr = "EX_T_EXPORT", import = "EX_T_IMPORT", importPick = "EX_T_IMPORT",
    importDone = "EX_T_IMPORT" }
local CRUMBS = { export = "EX_C_SECTIONS", exportStr = "EX_C_STRING", import = "EX_C_PASTE", importPick = "EX_C_PICK",
    importDone = "EX_C_DONE" }
local STEP = { export = { 1, 2 }, exportStr = { 2, 2 }, import = { 1, 3 }, importPick = { 2, 3 }, importDone = { 3, 3 } }

-- A section's line: its box, name, what it holds, a word at its right
local function secRow(screen, parent, x, y, w, key, get, set, right)
    local U = kit()
    local f = U.frameAt(parent, "Button", x, y, w, 46)
    f.bg = U.box(f, KC.nowBg, 0, KC.focus, 0)
    f.boxFrame = U.frameAt(f, "Frame", 8, 13, 20, 20)
    f.box = K.Box(f.boxFrame, 3, 2, "ARTWORK")
    f.box:SetPoints(f.boxFrame)
    f.tick = f.boxFrame:CreateTexture(nil, "OVERLAY")
    f.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    f.tick:SetSize(26, 26)
    f.tick:SetPoint("CENTER")
    f.tick:SetVertexColor(unpack(KC.focus))
    f.label = U.text(f, 15, KC.cream, 38, 5)
    f.label:SetText(L["EX_SEC_" .. key:upper()])
    f.sub = U.help(f, 12, KC.help, 38, 25, w - 50 - 120)
    f.sub:SetWordWrap(false)
    f.sub:SetText(L["EX_SEC_" .. key:upper() .. "_TEXT"])
    f.right = U.help(f, 13, KC.grey)
    f.right:SetPoint("TOPRIGHT", -12, -15)
    f.right:SetWidth(120)
    f.right:SetJustifyH("RIGHT")
    f.right:SetWordWrap(false)
    local line = K.Solid(f, KC.line3, 1, "ARTWORK")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    local c = U.add(screen, { frame = f })
    function c.press()
        set(not get())
        return true
    end
    function c.verbA() return get() and L.GUIDE_UNTICK or L.GUIDE_TICK end
    function c.draw(self, focused)
        local live = U.enabled(self)
        local on = live and get() and true or false
        f.bg:SetColors(KC.nowBg, focused and 1 or 0, KC.focus, focused and 1 or 0)
        f.box:SetColors(KC.controlBg, 1, focused and KC.focus or KC.boxEdge, 1)
        f.tick:SetShown(on)
        f.label:SetTextColor(unpack(not live and KC.disabled or (focused and KC.focusText or KC.cream)))
        f:SetAlpha(live and 1 or 0.45)
        local r, color = right()
        f.right:SetText(r or "")
        f.right:SetTextColor(unpack(color or KC.grey))
    end
    return c
end

-- A text field with many lines (a scroll frame), its edge a control: A
-- puts the keyboard's focus in it
local function textField(screen, parent, x, y, w, h, onText)
    local U = kit()
    local f = U.frameAt(parent, "Button", x, y, w, h)
    f.bg = K.Box(f, 4, 1, "BACKGROUND")
    f.bg:SetPoints(f)
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(w - 40)
    edit:SetTextColor(unpack(KC.cream))
    scroll:SetScrollChild(edit)
    edit:SetScript("OnEscapePressed", function(e) e:ClearFocus() end)
    edit:SetScript("OnTextChanged", function(e, user) if onText then onText(e, user) end end)
    -- A click anywhere in the field: its text
    f:SetScript("OnMouseDown", function() edit:SetFocus() end)
    f.edit, f.scroll = edit, scroll
    local c = U.add(screen, { frame = f })
    function c.press()
        edit:SetFocus()
        if screen.sid == "exportStr" then edit:HighlightText() end
        return true
    end
    function c.verbA() return screen.sid == "exportStr" and L.EX_SELECT or L.EX_PASTE_HERE end
    function c.draw(_, focused)
        f.bg:SetColors({ 0.05, 0.04, 0.03 }, 1, (focused or edit:HasFocus()) and KC.focus or KC.line1, 1)
    end
    return c, edit
end

local function screenOf(self, sid)
    local s = { sid = sid, controls = {}, owner = self }
    s.frame = CK.NewFrame("Frame", nil, self.frame)
    s.frame:SetAllPoints(self.frame)
    s.frame:Hide()
    self.screens[sid] = s
    return s, s.frame
end

-- The import's state
local function errorText(why)
    return L["EX_ERR_" .. why:upper()], L["EX_ERR_" .. why:upper() .. "_TEXT"]
end

function X:Build()
    if self.frame then return end
    local U = kit()
    local panel = C().frame
    local o = CK.NewFrame("Frame", "DualsenseForeverExchange", panel)
    o:SetAllPoints(panel)
    o:SetFrameLevel(panel:GetFrameLevel() + 60)
    o:EnableMouse(true)
    K.Panel(o)
    o.kicker = U.text(o, 11, KC.dimGold, 24, 14)
    o.title = U.text(o, 22, KC.title, 24, 29)
    o.close = K.Button(o, 14)
    o.close:SetSize(30, 28)
    o.close:SetPoint("TOPRIGHT", -20, -18)
    o.close.label:SetText("X")
    o.close:SetScript("OnClick", function() X:Close() end)
    o.count = U.help(o, 14, KC.help)
    o.count:SetPoint("RIGHT", o.close, "LEFT", -12, 0)
    o.dots = {}
    for i = 1, 3 do o.dots[i] = o:CreateTexture(nil, "ARTWORK") end
    U.rule(o, 16, 62, W - 32)
    o.bar = CK.NewFrame("Frame", nil, o)
    o.bar:SetSize(W - 4, 46)
    o.bar:SetPoint("TOPLEFT", o, "TOPLEFT", 2, -532)
    local bg = K.Solid(o.bar, KC.panel, 1, "BACKGROUND")
    bg:SetAllPoints()
    U.rule(o.bar, 0, 0, W - 4)
    o.crumb = K.ChatText(o.bar, 13, KC.grey)
    o.crumb:SetPoint("LEFT", 22, 0)
    o.crumb:SetWordWrap(false)
    o.hints = {}
    self.frame = o
    self.screens = {}
    self:BuildExport()
    self:BuildExportString()
    self:BuildImport()
    self:BuildImportPick()
    self:BuildImportDone()
    o:Hide()
end

function X:BuildExport()
    local U = kit()
    local s, f = screenOf(self, "export")
    U.text(f, 16, KC.title, 24, 72):SetText(L.EX_WHAT)
    U.help(f, 13, KC.help, 24, 94, 460):SetText(L.EX_WHAT_HELP)
    for i, sec in ipairs(X.SECTIONS) do
        secRow(s, f, 24, 128 + (i - 1) * 46, 460, sec.key,
            function() return X.chosen[sec.key] end,
            function(v) X.chosen[sec.key] = v end,
            function() return X.Count(sec.key) end)
    end
    U.help(f, 12, KC.grey, 24, 128 + #X.SECTIONS * 46 + 8, 460):SetText(L.EX_NEVER)
    U.rule(f, 500, 72, 1, 444)
    U.text(f, 16, KC.title, 516, 72):SetText(L.EX_PROFILE)
    local card = U.frameAt(f, "Frame", 516, 98, 280, 116)
    U.box(card, KC.panel, 1, KC.line1, 1)
    s.rows = {}
    for i, key in ipairs({ "EX_ROW_PROFILE", "EX_ROW_CLASS", "EX_ROW_ADDON", "EX_ROW_SECTIONS" }) do
        U.help(card, 13, KC.grey, 14, 10 + (i - 1) * 22, 90):SetText(L[key])
        local v = U.help(card, 13, KC.cream2, 104, 10 + (i - 1) * 22, 166)
        v:SetWordWrap(false)
        s.rows[i] = v
    end
    local note = U.infoBox(f, 516, 228, 280, 96)
    U.help(note, 13, KC.cream2, 14, 10, 254):SetText(L.EX_KEYBOARD_ONLY)
    U.button(s, f, L.V_CLOSE, 516, 418, 280, 40, false, function() X:Close() end)
    s.make = U.button(s, f, L.EX_MAKE, 516, 468, 280, 40, true, function() X:MakeString() end)
    s.make.enabled = function()
        for _, v in pairs(X.chosen) do
            if v then return true end
        end
        return false
    end
    function s.render()
        local P = Pr()
        local n = 0
        for _, v in pairs(X.chosen) do if v then n = n + 1 end end
        local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
        s.rows[1]:SetText(P and select(2, P:ActiveSet()) or "")
        s.rows[2]:SetText(UnitClass("player") or "")
        s.rows[3]:SetText("DualSense Forever " .. (get and get(addonName, "Version") or ""))
        s.rows[4]:SetText(format(L.EX_OF, n, #X.SECTIONS))
    end
end

function X:BuildExportString()
    local U = kit()
    local s, f = screenOf(self, "exportStr")
    U.text(f, 16, KC.title, 24, 72):SetText(L.EX_READY)
    s.field, s.edit = textField(s, f, 24, 100, 772, 236, function(e, user)
        -- (read only: a key typed puts the string back)
        if user and X.str and e:GetText() ~= X.str then
            e:SetText(X.str)
            e:HighlightText()
        end
    end)
    s.info = U.help(f, 13, KC.grey, 24, 344, 772)
    local note = U.infoBox(f, 24, 372, 772, 76)
    U.text(note, 15, KC.info, 16, 10):SetText(L.EX_COPY)
    U.help(note, 13, KC.cream2, 16, 32, 740):SetText(L.EX_COPY_TEXT)
    U.button(s, f, L.V_BACK, 428, 468, 156, 40, false, function() X:Go("export") end)
    s.done = U.button(s, f, L.V_DONE, 596, 468, 200, 40, true, function() X:Close() end)
    function s.enter()
        s.edit:SetText(X.str or "")
        s.edit:SetFocus()
        s.edit:HighlightText()
        local names = {}
        for _, sec in ipairs(X.SECTIONS) do
            if X.chosen[sec.key] then names[#names + 1] = L["EX_SEC_" .. sec.key:upper()] end
        end
        s.info:SetText(format(L.EX_STRING_INFO, #(X.str or ""), table.concat(names, ", ")))
    end
    function s.leave() s.edit:ClearFocus() end
    function s.first() return s.done end
end

function X:BuildImport()
    local U = kit()
    local s, f = screenOf(self, "import")
    U.text(f, 16, KC.title, 24, 72):SetText(L.EX_PASTE)
    U.help(f, 13, KC.help, 24, 94, 772):SetText(L.EX_PASTE_HELP)
    s.field, s.edit = textField(s, f, 24, 122, 772, 170, function(e, user)
        if user then X:Read(e:GetText()) end
    end)
    s.wait = U.help(f, 13, KC.grey, 24, 304, 772)
    s.wait:SetText(L.EX_WAITING)
    s.bad = U.frameAt(f, "Frame", 24, 304, 772, 62)
    U.box(s.bad, { 0.29, 0.08, 0.05 }, 0.5, KC.danger, 0.8)
    s.badTitle = U.text(s.bad, 15, KC.warn, 16, 10)
    s.badText = U.help(s.bad, 13, KC.cream2, 16, 32, 740)
    s.good = U.infoBox(f, 24, 304, 772, 62)
    s.goodTitle = U.text(s.good, 15, KC.info, 16, 10)
    s.goodText = U.help(s.good, 13, KC.cream2, 16, 32, 740)
    U.button(s, f, L.V_CLOSE, 428, 468, 156, 40, false, function() X:Close() end)
    s.next = U.button(s, f, L.EX_NEXT, 596, 468, 200, 40, true, function() X:StartPick() end)
    s.next.enabled = function() return X.data ~= nil end
    function s.enter()
        s.edit:SetText(X.pasted or "")
        s.edit:SetFocus()
    end
    function s.leave() s.edit:ClearFocus() end
    function s.first() return s.field end
    function s.render()
        local d, why = X.data, X.why
        s.wait:SetShown(not d and (why == nil or why == "empty"))
        s.bad:SetShown(not d and why ~= nil and why ~= "empty")
        s.good:SetShown(d ~= nil)
        if d then
            local n = 0
            for _ in pairs(d.sections) do n = n + 1 end
            s.goodTitle:SetText(format(L.EX_READ_OK, tostring(d.profile or "")))
            s.goodText:SetText(format(L.EX_READ_INFO, X.ClassName(d.class), tostring(d.addon or ""), n)
                .. (d.class ~= myClass() and L.EX_OTHER_CLASS or ""))
        elseif why and why ~= "empty" then
            local title, text = errorText(why)
            s.badTitle:SetText(title)
            s.badText:SetText(text)
        end
    end
end

function X.ClassName(class)
    local names = LOCALIZED_CLASS_NAMES_MALE
    return names and names[class or ""] or tostring(class or "")
end

-- What takes the profile's place: buttons or wheels picked
local function inProfile()
    local d = X.data
    return d and ((X.take.buttons and d.sections.buttons) or (X.take.wheels and d.sections.wheels)) and true or false
end

local function otherClass()
    return X.data and X.data.class ~= myClass()
end

function X:BuildImportPick()
    local U = kit()
    local s, f = screenOf(self, "importPick")
    U.text(f, 16, KC.title, 24, 72):SetText(L.EX_TAKE)
    s.from = U.help(f, 13, KC.help, 24, 94, 460)
    for i, sec in ipairs(X.SECTIONS) do
        local c = secRow(s, f, 24, 120 + (i - 1) * 46, 460, sec.key,
            function() return X.take[sec.key] end,
            function(v) X.take[sec.key] = v end,
            function()
                if X.data and X.data.sections[sec.key] then return "" end
                return L.EX_NOT_IN, KC.disabled
            end)
        c.enabled = function() return X.data ~= nil and X.data.sections[sec.key] ~= nil end
    end
    U.rule(f, 500, 72, 1, 444)
    U.text(f, 16, KC.title, 516, 72):SetText(L.EX_WHERE)
    s.current = U.radio(s, f, 516, 98, 280, 54, L.EX_INTO_CURRENT, " ",
        function() return X.into ~= "new" end, function() X.into = "current" end)
    s.new = U.radio(s, f, 516, 158, 280, 54, L.EX_INTO_NEW, " ",
        function() return X.into == "new" end, function() X.into = "new" end)
    s.new.enabled = function()
        local P = Pr()
        return P ~= nil and #P:Sets() < P.MAX_SETS
    end
    s.current.shown, s.new.shown = inProfile, inProfile
    s.whereNote = U.help(f, 13, KC.grey, 516, 100, 280)
    s.whereNote:SetText(L.EX_WHERE_ALL)
    s.skip = U.check(s, f, 516, 222, 280, " ", L.EX_SKIP_HELP,
        function() return X.skip end, function(v) X.skip = v end)
    s.skip.shown = function() return otherClass() and inProfile() end
    s.undo = U.infoBox(f, 516, 306, 280, 92)
    U.help(s.undo, 13, KC.cream2, 14, 8, 254):SetText(L.EX_UNDO_NOTE)
    s.go = U.button(s, f, L.EX_IMPORT, 516, 468, 280, 40, true, function() X:DoImport() end)
    s.go.enabled = function()
        for key in pairs(X.data and X.data.sections or {}) do
            if X.take[key] then return true end
        end
        return false
    end
    function s.go.verbA() return L.EX_IMPORT end
    function s.first() return s.controls[1] end
    function s.render()
        local d = X.data
        if not d then return end
        s.from:SetText(format(L.EX_FROM, tostring(d.profile or ""), X.ClassName(d.class), tostring(d.addon or "")))
        local P = Pr()
        s.current.frame.sub:SetText(format(L.EX_INTO_CURRENT_TEXT, P and select(2, P:ActiveSet()) or ""))
        s.new.frame.sub:SetText(U.enabled(s.new) and format(L.EX_INTO_NEW_TEXT, tostring(d.profile or ""))
            or format(L.EX_INTO_NEW_FULL, P and P.MAX_SETS or 5))
        s.whereNote:SetShown(not inProfile())
        s.skip.frame.label:SetText(format(L.EX_SKIP, X.ClassName(d.class)))
    end
end

function X:BuildImportDone()
    local U = kit()
    local s, f = screenOf(self, "importDone")
    U.text(f, 16, KC.title, 24, 72):SetText(L.EX_DONE)
    s.lines = {}
    for i = 1, #X.SECTIONS do
        local y = 106 + (i - 1) * 28
        local d = U.diamond(f, 24, y + 6, KC.focus)
        local t = U.help(f, 14, KC.cream2, 40, y, 440)
        s.lines[i] = { d, t }
    end
    U.rule(f, 500, 72, 1, 444)
    s.where = U.help(f, 13, KC.cream2, 516, 74, 280)
    local note = U.infoBox(f, 516, 160, 280, 62)
    U.help(note, 13, KC.cream2, 14, 8, 254):SetText(L.EX_RELOAD_NOTE)
    s.reload = U.button(s, f, L.EX_RELOAD, 516, 468, 280, 40, true, function() X:Reload() end)
    function s.render()
        local done = X.done or { sections = {} }
        for i, line in ipairs(s.lines) do
            local key = done.sections[i]
            line[1]:SetShown(key ~= nil)
            line[2]:SetShown(key ~= nil)
            if key then
                line[2]:SetText(L["EX_SEC_" .. key:upper()]
                    .. ((key == "buttons" or key == "wheels") and done.skipped > 0 and format(L.EX_SKIPPED, done.skipped) or ""))
            end
        end
        local P = Pr()
        s.where:SetText(done.newSet and format(L.EX_DONE_NEW, done.newSet)
            or format(L.EX_DONE_CURRENT, P and select(2, P:ActiveSet()) or ""))
    end
end

---------------------------------------------------------------------------
-- Doing it
---------------------------------------------------------------------------
function X:MakeString()
    local ok, str = pcall(X.Encode, X.Payload(X.chosen))
    if not ok then
        C():Toast(L.EX_MAKE_FAILED, true)
        return
    end
    X.str = str
    self:Go("exportStr")
end

function X:Read(text)
    X.pasted = text
    X.data, X.why = X.Decode(text)
    self:Render()
end

function X:StartPick()
    if not X.data then return end
    X.take = {}
    for key in pairs(X.data.sections) do
        if sectionOf(key) then X.take[key] = true end
    end
    X.into, X.skip = "current", true
    self:Go("importPick")
end

function X:DoImport()
    local done = X.Apply(X.data, { take = X.take, into = inProfile() and X.into or "current",
        skip = otherClass() and X.skip })
    if not done then return end
    X.done = done
    self:Go("importDone")
end

function X:Reload()
    self:Leave()
    local reload = C_UI and C_UI.Reload or ReloadUI
    reload()
end

---------------------------------------------------------------------------
-- Moving through it (as the guide)
---------------------------------------------------------------------------
local function focusables(s)
    local U = kit()
    local list = {}
    for _, c in ipairs(s.controls) do
        if c.frame and U.shown(c) and U.enabled(c) then list[#list + 1] = c end
    end
    return list
end

function X:Current() return self.screens and self.screens[self.sid] end

function X:Focused()
    local s = self:Current()
    if not s then return nil end
    local list = focusables(s)
    for _, c in ipairs(list) do
        if c == s.focus then return c end
    end
    s.focus = list[1]
    return s.focus
end

function X:Move(d)
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

function X:Go(sid)
    local old = self:Current()
    if old and old.leave and old.sid ~= sid then old.leave() end
    self.sid = sid
    local s = self:Current()
    s.focus = s.first and s.first() or s.controls[1]
    self:Render()
    if s.enter then s.enter() end
end

function X:Click(c)
    if c.screen ~= self:Current() then return end
    local U = kit()
    if not (U.shown(c) and U.enabled(c)) then return end
    c.screen.focus = c
    if c.press then c:press() end
    self:Render()
end

-- X on the sections' screens: all, or none
function X:ToggleAll()
    local list, keys = self.sid == "export" and X.chosen or X.take, {}
    for _, sec in ipairs(X.SECTIONS) do
        if self.sid == "export" or (X.data and X.data.sections[sec.key]) then keys[#keys + 1] = sec.key end
    end
    local all = true
    for _, k in ipairs(keys) do
        if not list[k] then all = false end
    end
    for _, k in ipairs(keys) do list[k] = not all end
    self:Render()
end

function X:Back()
    if self.sid == "exportStr" then return self:Go("export") end
    if self.sid == "importPick" then return self:Go("import") end
    if self.sid == "importDone" then return self:Reload() end
    self:Close()
end

function X:Press(name)
    if not self.active then return end
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
    elseif name == "X" and (self.sid == "export" or self.sid == "importPick") then
        self:ToggleAll()
    elseif name == "B" then
        self:Back()
    end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
function X:Hints()
    local Hn = K.H
    local list = {}
    local c = self:Focused()
    list[#list + 1] = Hn({ "DPAD" }, L.V_CHOOSE, "DOWN")
    if c and c.press then list[#list + 1] = Hn({ "A" }, c.verbA and c:verbA() or L.V_CONFIRM, "A") end
    if self.sid == "export" or self.sid == "importPick" then list[#list + 1] = Hn({ "X" }, L.EX_ALL, "X") end
    local back = (self.sid == "exportStr" or self.sid == "importPick") and L.V_BACK
        or (self.sid == "importDone" and L.EX_RELOAD or L.V_CLOSE)
    list[#list + 1] = Hn({ "B" }, back, "B")
    return list
end

function X:RenderHelp()
    local o = self.frame
    local hints = self:Hints()
    local crumb, color = L.EX_CRUMB .. " › " .. L[CRUMBS[self.sid]], KC.grey
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

function X:RenderHeader()
    local o = self.frame
    o.kicker:SetText(K.Upper(L.EX_KICKER))
    o.title:SetText(L[TITLES[self.sid]])
    local at, n = STEP[self.sid][1], STEP[self.sid][2]
    o.count:SetText(format("%d / %d", at, n))
    local x = 0
    for i = 3, 1, -1 do
        local d = o.dots[i]
        d:SetShown(i <= n)
        if i <= n then
            local now, done = i == at, i < at
            local size = now and 10 or 8
            d:SetTexture(K.TEX .. ((now or done) and "ck_dot" or "ck_ring"))
            d:SetVertexColor(unpack(now and KC.focus or (done and KC.dimGold or KC.line1)))
            d:SetSize(size, size)
            d:ClearAllPoints()
            d:SetPoint("RIGHT", o.count, "LEFT", -10 - x, 0)
            x = x + size + 7
        end
    end
end

function X:Render()
    local o = self.frame
    if not (o and self.active) then return end
    local U = kit()
    self:RenderHeader()
    for sid, s in pairs(self.screens) do s.frame:SetShown(sid == self.sid) end
    local s = self:Current()
    if s.render then s.render() end
    local focused = self:Focused()
    for _, c in ipairs(s.controls) do
        if c.shown then c.frame:SetShown(U.shown(c)) end
        c:draw(c == focused)
    end
    self:RenderHelp()
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------
function X:IsOpen() return self.active and true or false end

-- mode: "export" or "import", over the panel (its Profiles tab)
function X:Open(mode)
    if CK:BlockedByCombat() then return end
    local Cfg = C()
    if not (Cfg.frame and Cfg.frame:IsShown()) then Cfg:Open() end
    if not (Cfg.frame and Cfg.frame:IsShown()) then return end
    if CK.Guide and CK.Guide:IsOpen() then return end
    Cfg:Disarm()
    self:Build()
    if not X.chosen then
        X.chosen = {}
        for _, sec in ipairs(X.SECTIONS) do X.chosen[sec.key] = true end
    end
    X.data, X.why, X.pasted, X.done = nil, nil, "", nil
    self.active = true
    self.frame:Show()
    Cfg.guide = self
    self:Go(mode == "import" and "import" or "export")
end

function X:Leave()
    if not self.active then return end
    local s = self:Current()
    if s and s.leave then s.leave() end
    self.active = false
    if self.frame then self.frame:Hide() end
    if C().guide == self then C().guide = nil end
end

-- Back to the panel's Profiles tab
function X:Close()
    self:Leave()
    C():Render()
end

-- The panel closed under it
function X:Closed()
    self:Leave()
end
