local ADDON, CK = ...

---------------------------------------------------------------------------
-- Fork CoolerMgdn: the flight recorder (the idea: ControllerForever's
-- Flight.lua and TaintWatch.lua, its author's code free to reuse). Always
-- on (/ec flight off stops it). The game writes the saved settings by
-- itself at every logout, /reload and exit, so one file holds what led to
-- a problem:
--   WTF\Account\<account>\SavedVariables\DualsenseForever.lua,
--   ControllerKeyboardDB.flight: the last 600 lines
-- What goes in: the presses on our routers (the layer, tap or hold), the
-- mic's button, the keyboard opened and closed, our bindings set again,
-- your casts, red errors, fights, blocked / forbidden actions (anyone's),
-- and the moment a value the game's gamepad code reads turns ours
-- ("TAINT", the game's own issecurevariable names the addon), with our
-- lines on the stack when one of our calls did it.
-- Nothing of the game's is changed: reads, and hooksecurefunc only.
---------------------------------------------------------------------------
local F = {}
CK.Flight = F

F.CAP = 600
local pending = {}      -- lines noted before the saved settings loaded

local function off()
    return CK.db and CK.db.settings and CK.db.settings.flightOff == true
end

local function store()
    local db = CK.db
    if not db then return nil end
    if type(db.flight) ~= "table" then db.flight = {} end
    return db.flight
end

function F:Note(text, ...)
    if off() then return end
    if select("#", ...) > 0 then
        local ok, s = pcall(format, text, ...)
        text = ok and s or tostring(text)
    end
    local line = format("%s %.1f %s", date and date("%H:%M:%S") or "?", GetTime and GetTime() or 0,
        tostring(text):gsub("\n", " / "):sub(1, 300))
    local log = store()
    if not log then
        if #pending < 100 then pending[#pending + 1] = line end
        return
    end
    if #pending > 0 then
        for _, p in ipairs(pending) do log[#log + 1] = p end
        wipe(pending)
    end
    log[#log + 1] = line
    while #log > F.CAP do table.remove(log, 1) end
end

local function note(...) pcall(F.Note, F, ...) end

local function layerName(layer)
    if layer == nil then return "-" end
    if layer == "" then return "alone" end
    return tostring(layer)
end

---------------------------------------------------------------------------
-- Our buttons (Mapping.lua's routers, Touchpad.lua's mic toggle): PostClick
---------------------------------------------------------------------------
function F:Press(r, button, down)
    if off() then return end
    local id = r.ckInput or r:GetName() or "?"
    if down ~= false then
        local held = r:GetAttribute("ck-lp")
        r.ecFlightHold = held
        if held then
            note("press %s %s: %s, waits for hold or tap", id, tostring(button), layerName(held))
        else
            local layer = r:GetAttribute("ck-pressed")
            note("press %s %s: %s", id, tostring(button), layer and layerName(layer) or "nothing of ours / the game's")
        end
    elseif r.ecFlightHold then
        local t, n = r:GetAttribute("ec-lp-ticks") or 0, r:GetAttribute("ec-lp-n") or 3
        note("release %s: %s %s (%d/%d)", id, layerName(r.ecFlightHold), t >= n and "HOLD" or "tap", t, n)
        r.ecFlightHold = nil
    end
end

function F:Mic(t, down)
    if off() then return end
    if down ~= false then return end
    local ticks, n = t:GetAttribute("ec-lp-ticks") or 0, t:GetAttribute("ec-lp-n") or 3
    local short = t:GetAttribute("ec-short")
    note("mic released: %s, mouse mode %s", short and ((ticks >= n and "long" or "short") .. format(" (%d/%d)", ticks, n))
        or "toggle", CK.Touchpad and CK.Touchpad.MouseMode() and "on" or "off")
end

---------------------------------------------------------------------------
-- The game's gamepad state turning ours (TaintWatch)
---------------------------------------------------------------------------
local function footerOf(frame)
    if type(frame) ~= "table" then return nil end
    local ft = rawget(frame, "gamepadFooter") or rawget(frame, "footer")
    return type(ft) == "table" and ft or nil
end

local function roots()
    local util = rawget(_G, "GamepadSharedUtility")
    local mode = rawget(_G, "GamepadMode")
    local main = rawget(_G, "GamepadMainActionBarFrame")
    return {
        BindingMgr = type(util) == "table" and util.InputBindingManager or nil,
        Focus = type(mode) == "table" and mode.FrameControlsManager or nil,
        PageUnit = type(main) == "table" and main.PageUnit or nil,
        SmartNav = rawget(_G, "SmartNavigation"),
        ChatFooter = footerOf(rawget(_G, "ChatFrame1")),
        LootFooter = footerOf(rawget(_G, "LootFrame")),
        BagsFooter = footerOf(rawget(_G, "ContainerFrameCombinedBags")),
        Targeting = rawget(_G, "GamepadTargetLogic"),
    }
end

local KEYS = {
    BindingMgr = { "currentCoreBindingActive", "assumeCoreBindingsUsable", "coreSet", "bindingSetStack", "activeBindings" },
    Focus = { "focusedFrame", "fallThroughCatcherActive", "shownFrames", "isUIFocused", "suspendedFrame", "isPopupFrame" },
    PageUnit = { "activeBar", "actionBars", "overrideBars", "currentPage", "currentPageNum", "appliedStyle" },
    SmartNav = { "activeInfo", "currentButton", "bindingActive", "activePanels", "currentDirections" },
    Targeting = { "activeTargetFilter", "wasModifierUsed" },
}
local FOOTER_KEYS = { "isShown", "promptedBindingsActive", "bindings", "promptedBindingsByKey" }
KEYS.ChatFooter, KEYS.LootFooter, KEYS.BagsFooter = FOOTER_KEYS, FOOTER_KEYS, FOOTER_KEYS
-- Lists: each entry too
local LISTS = { bindingSetStack = true, activeBindings = true, shownFrames = true, activePanels = true,
    overrideBars = true, actionBars = true }
-- The chat's globals the gamepad UI reads
local GLOBALS = { "ACTIVE_CHAT_EDIT_BOX", "LAST_ACTIVE_CHAT_EDIT_BOX" }

local function ourStack()
    local stack = debugstack and debugstack(3, 30, 0) or ""
    local ours = {}
    for line in stack:gmatch("[^\n]+") do
        if line:find(ADDON, 1, true) and not line:find("Flight.lua", 1, true) and #ours < 5 then
            ours[#ours + 1] = (line:gsub("^.-AddOns[/\\]" .. ADDON .. "[/\\]", ""))
        end
    end
    return ours
end

local function ours(secure, by)
    return secure == false and type(by) == "string" and by:find(ADDON, 1, true) ~= nil
end

local noted = {}
F.taints = 0
function F:Check(where)
    if off() or type(issecurevariable) ~= "function" then return 0 end
    local hits = 0
    local function look(label, t, k)
        local ok, secure, by
        if t == nil then
            ok, secure, by = pcall(issecurevariable, k)
        else
            ok, secure, by = pcall(issecurevariable, t, k)
        end
        local bad = ok and ours(secure, by)
        if bad and not noted[label] then
            noted[label] = true
            hits = hits + 1
            F.taints = F.taints + 1
            local stack = ourStack()
            note("TAINT %s at %s%s", label, tostring(where), #stack > 0 and (" | ours: " .. table.concat(stack, " < ")) or "")
        elseif not bad and noted[label] then
            noted[label] = nil
        end
    end
    for root, t in pairs(roots()) do
        if type(t) == "table" and KEYS[root] then
            for _, k in ipairs(KEYS[root]) do
                look(root .. "." .. k, t, k)
                local inner = LISTS[k] and rawget(t, k)
                if type(inner) == "table" then
                    for ik in pairs(inner) do look(root .. "." .. k .. "." .. tostring(ik), inner, ik) end
                end
            end
        end
    end
    for _, k in ipairs(GLOBALS) do look(k, nil, k) end
    return hits
end

local function check(where) pcall(F.Check, F, where) end

-- One of the game's gamepad calls with a line of ours on its stack: noted
-- (the first source found, Fields.lua's ClearFocus, ran exactly so)
local hooked = {}
local function hookCalls(t, label, names)
    if type(t) ~= "table" or not hooksecurefunc then return end
    for _, name in ipairs(names) do
        local key = label .. "." .. name
        if not hooked[key] and type(t[name]) == "function" then
            hooked[key] = true
            pcall(hooksecurefunc, t, name, function()
                if off() then return end
                local stack = ourStack()
                if #stack > 0 then note("OUR CALL %s | ours: %s", key, table.concat(stack, " < ")) end
                check(key)
            end)
        end
    end
end

local function hookAll()
    local r = roots()
    hookCalls(r.BindingMgr, "BindingMgr", { "SetNewActiveKey", "AddSet", "RemoveSet", "PushSet", "PopSet",
        "ActivateSet", "DeactivateSet", "RefreshBindings", "SetCoreBindingActive" })
    hookCalls(r.SmartNav, "SmartNav", { "HandlePanelOpen", "SetActiveFrame", "ActivateBinding", "ShowCursor" })
    for _, label in ipairs({ "ChatFooter", "LootFooter", "BagsFooter" }) do
        hookCalls(r[label], label, { "ShowAndActivateBindings", "HideAndDeactivateBindings", "RefreshPromptedBindingsActive" })
    end
    if hooksecurefunc then
        for _, name in ipairs({ "ShowUIPanel", "HideUIPanel", "CloseAllWindows", "CloseSpecialWindows" }) do
            if not hooked[name] and type(rawget(_G, name)) == "function" then
                hooked[name] = true
                pcall(hooksecurefunc, name, function(frame)
                    if off() then return end
                    local stack = ourStack()
                    if #stack > 0 then
                        local fname = type(frame) == "table" and frame.GetName and frame:GetName() or tostring(frame)
                        note("OUR WINDOW CALL %s %s | ours: %s", name, tostring(fname), table.concat(stack, " < "))
                    end
                end)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function spellName(id)
    if issecretvalue and issecretvalue(id) then return "?" end
    local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or (GetSpellInfo and GetSpellInfo(id))
    if issecretvalue and issecretvalue(n) then return "?" end
    return tostring(n or "?") .. " (" .. tostring(id) .. ")"
end

local watch = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "UI_ERROR_MESSAGE", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "LOOT_CLOSED", "GOSSIP_CLOSED",
    "MERCHANT_CLOSED", "UPDATE_BINDINGS", "GAME_PAD_ACTIVE_CHANGED" }) do
    pcall(watch.RegisterEvent, watch, event)
end
for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_SUCCEEDED" }) do
    pcall(watch.RegisterUnitEvent, watch, event, "player")
end

local function wrap(name, describe)
    local fn = CK[name]
    if type(fn) ~= "function" then return end
    CK[name] = function(self, ...)
        note(describe(...))
        local r = { fn(self, ...) }
        check("CK:" .. name)
        return unpack(r)
    end
end

watch:SetScript("OnEvent", function(_, event, a, b, c, d)
    if off() and event ~= "PLAYER_LOGIN" then return end
    if event == "PLAYER_LOGIN" then
        local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
        local _, class = UnitClass("player")
        note("---- login %s %s %s level %s, %s", tostring(getMeta and getMeta(ADDON, "Version")),
            GetLocale and GetLocale() or "?", tostring(class), tostring(UnitLevel("player")),
            CK.Mapping and CK.Mapping.PlayStation and CK.Mapping.PlayStation() and "PlayStation pad" or "pad")
        pcall(hookAll)
        -- Ours: the keyboard opened / closed
        wrap("Open", function(eb) return "keyboard open on " .. tostring(eb and eb.GetName and eb:GetName() or eb) end)
        wrap("OpenStandalone", function() return "keyboard open (own)" end)
        wrap("Close", function(reason) return "keyboard close " .. tostring(reason) end)
        -- A light net: every 2 s, out of the busy paths
        C_Timer.NewTicker(2, function() check("net") end)
        C_Timer.After(5, function() pcall(hookAll) end)
    elseif event == "PLAYER_LOGOUT" then
        note("---- logout / reload")
    elseif event == "PLAYER_REGEN_DISABLED" then
        note("fight starts")
        check(event)
    elseif event == "PLAYER_REGEN_ENABLED" then
        note("fight ends")
    elseif event == "UI_ERROR_MESSAGE" then
        if not (issecretvalue and issecretvalue(b)) then note("error: %s", tostring(b)) end
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        note("%s %s %s%s", event == "ADDON_ACTION_BLOCKED" and "BLOCKED" or "FORBIDDEN", tostring(a), tostring(b),
            a == ADDON and " (OURS)" or "")
        check(event)
    elseif event == "UNIT_SPELLCAST_SENT" then
        note("cast sent %s", spellName(d))
    elseif event == "UNIT_SPELLCAST_FAILED" then
        note("cast failed %s", spellName(c))
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        note("cast done %s", spellName(c))
    elseif event == "GAME_PAD_ACTIVE_CHANGED" then
        note("gamepad active: %s", tostring(a))
    else
        check(event)
    end
end)

---------------------------------------------------------------------------
-- /ec flight [n | clear | on | off]
---------------------------------------------------------------------------
function F:Slash(arg)
    local s = CK.db.settings
    arg = (arg or ""):lower()
    if arg == "off" or arg == "on" then
        s.flightOff = arg == "off" or nil
        CK:Print(CK.L.FLIGHT_STATE, arg == "off" and CK.L.OFF or CK.L.ON)
        return
    end
    local log = store() or {}
    if arg == "clear" then
        wipe(log)
        wipe(noted)
        F.taints = 0
        CK:Print(CK.L.FLIGHT_CLEARED)
        return
    end
    local n = math.max(1, math.min(200, tonumber(arg) or 25))
    CK:Print(CK.L.FLIGHT_HEADER, math.min(n, #log), #log, F.taints)
    for i = math.max(1, #log - n + 1), #log do
        local line = log[i]
        if line:find("TAINT", 1, true) or line:find("OUR ", 1, true) or line:find("(OURS)", 1, true) then
            line = "|cffff6060" .. line .. "|r"
        end
        DEFAULT_CHAT_FRAME:AddMessage("  " .. line)
    end
end
