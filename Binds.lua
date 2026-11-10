local _, CK = ...
local L = CK.L

---------------------------------------------------------------------------
-- Fork CoolerMgdn: one place for the addon's key bindings (the idea:
-- ControllerForever's Binds.lua, its author's code free to reuse).
--
-- Every module that binds pad keys out of combat does it through here, as a
-- claim: a name, a rank (who wins between us), the frame that owns its
-- bindings and whether they go over the game's (priority). For each key the
-- claim of the highest rank that wants it, among those of the same priority,
-- is the one bound; the others wait and get the key back by themselves when
-- it is let go (before, two of ours on one key: whichever bound last won,
-- and one module letting go could leave the key dead or someone else's).
--
--   rank  claim               what
--    10   mapping             the Gamepad tab's keys on free buttons
--    20   mapping-replaced    the game's buttons replaced (over the game)
--    30   touch-click         the touchpad's corners
--    31   touch-mouse         the mic's mouse mode
--    40   bankmove            X at the bank in the game's bags
--    50   bags                the gamepad bags (layered: see below)
--    60   itemtarget          the item list for a spell waiting
--    75   phrases             the quick phrases
--    80   keyboard            the chat keyboard
--    90   config              the configuration panel
--
-- The modules keep calling at the same moments as before; a call here acts
-- at once (out of combat), so nothing changes in when keys are set. In
-- combat nothing may change: what was asked is done as the fight ends.
-- "layered": a claim whose bindings a secure snippet of its own clears in
-- combat (the bags' B): it never takes a key from another of ours (else
-- that one's would be missing for the rest of the fight), it only sits over
-- them (priority).
-- Secure owners that bind in combat (the wheels, the trigger toggle) stay
-- their own; /ec owners names them too, from the button a key clicks.
---------------------------------------------------------------------------
local BD = {}
CK.Binds = BD

local claims, order = {}, {}
local pending = {}      -- keys to settle once the fight ends
BD.claims = claims

local function same(a, b)
    if a == nil or b == nil then return a == b end
    return a.kind == b.kind and a.target == b.target and a.mouse == b.mouse
end

-- What GetBindingAction(key, true) says for a value
local function actionOf(v)
    if not v then return nil end
    if v.kind == "click" then return "CLICK " .. v.target .. ":" .. (v.mouse or "LeftButton") end
    return v.target
end
BD.ActionOf = actionOf

-- The game's own call (BD.busy: Mapping's hooks on these know it's us)
local function raw(c, key, v)
    BD.busy = true
    if v == nil then
        SetOverrideBinding(c.owner, c.priority, key, nil)
    elseif v.kind == "click" then
        if v.mouse then
            SetOverrideBindingClick(c.owner, c.priority, key, v.target, v.mouse)
        else
            SetOverrideBindingClick(c.owner, c.priority, key, v.target)
        end
    else
        SetOverrideBinding(c.owner, c.priority, key, v.target)
    end
    BD.busy = false
end

-- A claim: name, owner frame, rank, priority (over the game), opts.layered,
-- opts.label (what /ec owners calls it)
function BD:Register(name, owner, rank, priority, opts)
    local c = claims[name]
    if not c then
        c = { name = name, wanted = {}, applied = {} }
        claims[name] = c
        order[#order + 1] = c
    end
    c.owner, c.rank, c.priority = owner, rank or 0, priority and true or false
    c.layered = opts and opts.layered or false
    c.label = opts and opts.label or name
    return c
end

function BD:Claim(name) return claims[name] end

-- Who of ours should have a key on this priority level (nil: none)
local function winner(key, priority)
    local win
    for _, c in ipairs(order) do
        if c.priority == priority and not c.layered and c.wanted[key] ~= nil and c.owner then
            if not win or c.rank >= win.rank then win = c end
        end
    end
    return win
end

-- Each claim of that priority: bound or not, as it should be
local function settle(key)
    if InCombatLockdown() then
        pending[key] = true
        return
    end
    pending[key] = nil
    for _, priority in ipairs({ true, false }) do
        local win = winner(key, priority)
        for _, c in ipairs(order) do
            if c.priority == priority and c.owner then
                local want = (c.layered or c == win) and c.wanted[key] or nil
                if not same(c.applied[key], want) then
                    if want == nil and c.applied[key] ~= nil and win and win ~= c and CK.Flight then
                        CK.Flight:Note("keys: %s goes from %s to %s", key, c.label, win.label)
                    end
                    raw(c, key, want)
                    c.applied[key] = want
                end
            end
        end
    end
end

-- A key of a claim: kind "click" (target = a button's name, mouse its mouse
-- button) or "command" (target = a binding command); kind nil: let go
function BD:Set(name, key, kind, target, mouse)
    local c = claims[name]
    if not (c and key) then return end
    if kind == nil or target == nil then
        c.wanted[key] = nil
    else
        c.wanted[key] = { kind = kind, target = target, mouse = mouse }
    end
    settle(key)
end

-- Every key of a claim let go (ClearOverrideBindings on its frame too:
-- anything set on it some other way goes), the others' back where they wait
function BD:Clear(name)
    local c = claims[name]
    if not (c and c.owner) then return end
    local keys = {}
    for key in pairs(c.wanted) do keys[key] = true end
    for key in pairs(c.applied) do keys[key] = true end
    wipe(c.wanted)
    if InCombatLockdown() then
        for key in pairs(keys) do pending[key] = true end
        return
    end
    BD.busy = true
    ClearOverrideBindings(c.owner)
    BD.busy = false
    wipe(c.applied)
    for key in pairs(keys) do settle(key) end
end

-- Its frame's bindings cleared by its own secure code (the bags' B in
-- combat): nothing of it is bound any more
function BD:Forget(name)
    local c = claims[name]
    if c then wipe(c.applied) end
end

-- A key a claim wants that another of ours holds (Mapping: not a key to
-- repair)
function BD:Suppressed(name, key)
    local c = claims[name]
    return c ~= nil and c.wanted[key] ~= nil and c.applied[key] == nil
end

-- The key's binding now is another claim's of ours (Mapping's repair:
-- not the game's, nothing to put back)
function BD:HeldByOther(name, key, action)
    action = action or (GetBindingAction and GetBindingAction(key, true))
    for _, c in ipairs(order) do
        if c.name ~= name and actionOf(c.applied[key]) == action then return true end
    end
    return false
end

-- Its keys as they are bound now (by key)
function BD:Applied(name)
    local c = claims[name]
    return c and c.applied or {}
end

-- The fight over: what waited is done
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
    local keys = {}
    for key in pairs(pending) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do settle(key) end
end)

---------------------------------------------------------------------------
-- /ec owners: each pad key, with each trigger layer, and who has it now
---------------------------------------------------------------------------
local PAD_KEYS = { "PAD1", "PAD2", "PAD3", "PAD4", "PAD5", "PAD6", "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT",
    "PADLSHOULDER", "PADRSHOULDER", "PADLTRIGGER", "PADRTRIGGER", "PADLSTICK", "PADRSTICK", "PADBACK", "PADFORWARD",
    "PADSOCIAL", "PADPADDLE1", "PADPADDLE2", "PADPADDLE3", "PADPADDLE4" }
local LAYERS = { { "", "" }, { "SHIFT-", "LT" }, { "ALT-", "RT" }, { "ALT-SHIFT-", "LT+RT" } }
-- Secure owners of ours, by the button a key clicks
local EXTERNAL = {
    { "^ControllerKeyboardWheel", "OWN_WHEELS" }, { "^ControllerKeyboardMyWheel", "OWN_WHEELS" },
    { "^ControllerKeyboardUsableToggle", "OWN_WHEELS" }, { "^ControllerKeyboardClassWheel", "OWN_WHEELS" },
    { "^ControllerKeyboardMarkWheel", "OWN_WHEELS" }, { "^ControllerKeyboardParty", "OWN_WHEELS" },
    { "^ControllerKeyboardToggle", "OWN_TOGGLE" }, { "^ControllerKeyboardBags", "OWN_BAGS" },
    { "^ControllerKeyboardRouteButton", "OWN_MAPPING" }, { "^ControllerKeyboardMapButton", "OWN_MAPPING" },
    { "^ControllerKeyboardBarRelay", "OWN_MAPPING" }, { "^ControllerKeyboard", "OWN_ADDON" },
}

-- Who has a key now: our claim's label, a secure owner of ours, the game
function BD:Owner(key)
    local action = GetBindingAction and GetBindingAction(key, true) or ""
    if action == "" then return nil, "" end
    for _, c in ipairs(order) do
        if actionOf(c.applied[key]) == action then return L["OWN_" .. c.name:upper():gsub("%-", "_")] or c.label, action end
    end
    local button = action:match("^CLICK ([^:]+)")
    if button then
        for _, e in ipairs(EXTERNAL) do
            if button:find(e[1]) then return L[e[2]] or e[2], action end
        end
    end
    return L.OWN_GAME, action
end

function BD:Report()
    CK:Print(L.OWNERS_HEADER)
    for _, key in ipairs(PAD_KEYS) do
        local parts = {}
        for _, layer in ipairs(LAYERS) do
            local who, action = self:Owner(layer[1] .. key)
            if who then
                local label = GetBindingText and GetBindingText(action, "BINDING_NAME_") or action
                if action:find("^CLICK ") then label = action:match("^CLICK ([^:]+)"):gsub("^ControllerKeyboard", "") end
                parts[#parts + 1] = format("%s%s|r %s (%s)", layer[2] == "" and "|cffffd100" or "|cff9d9a8c",
                    layer[2] == "" and "—" or layer[2], who, label)
            end
        end
        if #parts > 0 then
            local name = GetBindingText and GetBindingText(key, "KEY_") or key
            DEFAULT_CHAT_FRAME:AddMessage(format("  |cffffffff%s|r: %s", name, table.concat(parts, ", ")))
        end
    end
    -- Ours waiting (another of ours has the key)
    local waiting = {}
    for _, c in ipairs(order) do
        for key in pairs(c.wanted) do
            if c.applied[key] == nil and not c.layered then waiting[#waiting + 1] = key .. " (" .. c.label .. ")" end
        end
    end
    if #waiting > 0 then
        table.sort(waiting)
        DEFAULT_CHAT_FRAME:AddMessage("  " .. L.OWNERS_WAITING .. " " .. table.concat(waiting, ", "))
    end
end
