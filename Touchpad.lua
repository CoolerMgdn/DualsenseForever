local _, CK = ...
local L = CK.L

-- Fork CoolerMgdn: the DualSense touchpad, its four corners.
--
-- Ported from Improved Forever's Touchpad.lua by markg (MIT,
-- https://github.com/markgravity/ImprovedForever), so one addon does it all.
--
-- A click on the pad runs the action of the corner the finger is in: a
-- window of the game, a spell, an item, a macro or one of ours. With L1, R1,
-- L2 or R2 held, the corner's action of that layer.
--
-- Why a click and not a swipe: on Forever a game window opened from addon
-- code is tainted, and only presses of real buttons are passed on. The pad
-- click is a real button (PADBACK): it clicks a secure button whose snippet
-- reads the finger (GetGamePadState, mapped stick 4) and runs a macro
-- ("/click <the game's own button for that window>"). Inside a real press it
-- is a real click: the window opens untainted, in combat too.
--
-- The mouse mode: a button of the player's (the mic button, when the game
-- passes it on) turns it on and off. In it the touchpad is a mouse: the
-- game's touch cursor follows the finger, a click on the left half is the
-- left mouse button, on the right half the right one (the game's cursor
-- click buttons, GamePadCursorLeftClick / RightClick, given the pad's click
-- on the side the finger is on). The corners' actions rest meanwhile.
local T = {}
CK.Touchpad = T

local PAD_STICK = 4       -- the pad's finger, as a stick (no name for it on Forever)
local KEY = "PADBACK"     -- the game's name of the pad's click
local MODIFIERS = { "", "SHIFT-", "CTRL-", "ALT-", "CTRL-SHIFT-", "ALT-SHIFT-", "CTRL-ALT-", "CTRL-ALT-SHIFT-" }
local CURSOR_CVAR = "GamePadTouchCursorEnable"
local LEFT_CVAR, RIGHT_CVAR = "GamePadCursorLeftClick", "GamePadCursorRightClick"

T.REGIONS = { "upleft", "upright", "downleft", "downright" }
-- The layers the settings offer (the engine takes any mix: "LBRT"...)
T.LAYER_LIST = { "LB", "RB", "LT", "RT" }
local HELD_ORDER = { "LB", "RB", "LT", "RT" }
local HELD_KEY = { LB = "PADLSHOULDER", RB = "PADRSHOULDER", LT = "PADLTRIGGER", RT = "PADRTRIGGER" }
T.LAYERS = {}
for mask = 1, 15 do
    local name = ""
    for i, part in ipairs(HELD_ORDER) do
        if math.floor(mask / 2 ^ (i - 1)) % 2 == 1 then name = name .. part end
    end
    T.LAYERS[#T.LAYERS + 1] = name
end

local function settings()
    return CK.db and CK.db.settings.touch
end
T.Settings = settings

---------------------------------------------------------------------------
-- Actions: a window ("character", "bags"...), one of ours ("ec_keyboard"),
-- or "spell:<id>", "item:<id>", "macro:<name>"; "none": nothing
---------------------------------------------------------------------------
local R = "gamepad-radial-icon-"
local WINDOWS = {
    { key = "character", radial = { R .. "character" }, icon = "Interface\\Icons\\INV_Chest_Cloth_17",
        buttons = { "CharacterMicroButton" } },
    { key = "bags", radial = { R .. "bags" }, icon = "Interface\\Icons\\INV_Misc_Bag_08",
        buttons = { "MainMenuBarBackpackButton", "BagsBarBackpackButton" } },
    { key = "spellbook", radial = { R .. "spellbook" }, icon = "Interface\\Icons\\INV_Misc_Book_09",
        buttons = { "SpellbookMicroButton", "PlayerSpellsMicroButton" } },
    { key = "talents", radial = { R .. "talents" }, icon = "Interface\\Icons\\Ability_Marksmanship",
        buttons = { "TalentMicroButton", "PlayerSpellsMicroButton" } },
    { key = "professions", radial = { R .. "professions" }, icon = "Interface\\Icons\\Trade_BlackSmithing",
        buttons = { "ProfessionMicroButton" } },
    { key = "questlog", radial = { R .. "quests" }, icon = "Interface\\Icons\\INV_Misc_Book_08",
        buttons = { "QuestLogMicroButton" } },
    { key = "map", icon = "Interface\\Icons\\INV_Misc_Map_01",
        buttons = { "WorldMapMicroButton", "MiniMapWorldMapButton", "QuestLogMicroButton" } },
    { key = "gamemenu", radial = { R .. "gamemenu" }, icon = "Interface\\Icons\\INV_Misc_Gear_01",
        buttons = { "MainMenuMicroButton" } },
    { key = "social", radial = { R .. "social", R .. "friends" }, icon = "Interface\\Icons\\INV_Misc_GroupLooking",
        buttons = { "SocialsMicroButton", "FriendsMicroButton", "QuickJoinToastButton" } },
    { key = "guild", radial = { R .. "communities", R .. "guild" }, icon = "Interface\\Icons\\INV_BannerPVP_02",
        buttons = { "CommunitiesMicroButton", "GuildMicroButton" } },
    { key = "groupfinder", radial = { R .. "groupfinder", R .. "lfg", R .. "dungeonfinder" },
        icon = "Interface\\Icons\\INV_Misc_Eye_01", buttons = { "LFGMicroButton", "LFDMicroButton", "GroupFinderMicroButton" } },
    { key = "collections", radial = { R .. "collections" }, icon = "Interface\\Icons\\Ability_Mount_RidingHorse",
        buttons = { "CollectionsMicroButton" } },
    { key = "achievements", icon = "Interface\\Icons\\INV_Misc_Note_01", buttons = { "AchievementMicroButton" } },
    { key = "pvp", radial = { R .. "pvp" }, icon = "Interface\\Icons\\Ability_DualWield",
        buttons = { "PVPMicroButton", "HonorMicroButton" } },
    { key = "calendar", radial = { R .. "calendar" }, icon = "Interface\\Icons\\INV_Misc_Note_02",
        buttons = { "GameTimeFrame", "CalendarMicroButton" } },
    { key = "minimap", radial = { R .. "minimap", R .. "minimapsettings", R .. "tracking" },
        icon = "Interface\\Icons\\INV_Misc_Map_01", buttons = { "MiniMapTrackingButton", "MiniMapTracking", "MinimapTrackingButton" } },
    { key = "shop", radial = { R .. "shop", R .. "store" }, icon = "Interface\\Icons\\WoW_Store",
        buttons = { "StoreMicroButton" } },
    -- Ours: a button of this addon each, clicked the same way
    { key = "ec_keyboard", ours = true, icon = "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up",
        buttons = { "ControllerKeyboardTouchKeyboard" } },
    { key = "ec_phrases", ours = true, icon = "Interface\\GossipFrame\\GossipGossipIcon",
        buttons = { "ControllerKeyboardTouchPhrases" } },
    { key = "ec_config", ours = true, icon = "Interface\\Icons\\INV_Gizmo_02",
        buttons = { "ControllerKeyboardTouchConfig" } },
    { key = "ec_lightbar", ours = true, icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
        buttons = { "ControllerKeyboardTouchLightbar" } },
    -- (its press runs /reload itself: a /click to a button of ours is lost
    -- on key-down presses, the button answering only its release)
    { key = "reload", ours = true, macro = "/reload", icon = "Interface\\Icons\\Spell_Nature_Reincarnation",
        buttons = { "ControllerKeyboardTouchReload" } },
}
local WINDOW = {}
for _, w in ipairs(WINDOWS) do WINDOW[w.key] = w end
T.WINDOWS = WINDOWS

-- A button of ours that a corner clicks: fn once per press. Registered for
-- both edges: a /click sends one of them, a key binding both (acted on the
-- press, its release let go).
local function pressButton(name, fn)
    local b = CK.NewFrame("Button", name, UIParent)
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetScript("OnClick", function(self, _, down)
        if down then
            self.pressed = true
        elseif self.pressed then
            self.pressed = false
            return
        end
        fn()
    end)
    return b
end

pressButton("ControllerKeyboardTouchKeyboard", function() ControllerKeyboard_Toggle() end)
pressButton("ControllerKeyboardTouchPhrases", function()
    if CK.Phrases and CK.Phrases.Toggle then CK.Phrases:Toggle() end
end)
pressButton("ControllerKeyboardTouchConfig", function() ControllerKeyboard_OpenConfig() end)
pressButton("ControllerKeyboardTouchLightbar", function() T:CycleLight() end)
pressButton("ControllerKeyboardTouchReload", function() ReloadUI() end)

local function hasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function windowButton(key)
    local w = WINDOW[key]
    for _, name in ipairs(w and w.buttons or {}) do
        local b = _G[name]
        if type(b) == "table" and b.Click then return name end
    end
end

function T.IsWindow(action) return WINDOW[action] ~= nil end
function T.IsBound(action) return type(action) == "string" and action ~= "none" end

function T.Label(action)
    if not T.IsBound(action) then return L.TOUCH_NOTHING end
    local w = WINDOW[action]
    if w then
        local name = L["TOUCH_W_" .. action:upper()]
        return windowButton(action) and name or (name .. " " .. L.TOUCH_NOT_HERE)
    end
    return CK.Mapping:ActionName(action) or action
end

function T.Icon(action)
    if not T.IsBound(action) then return "Interface\\Buttons\\UI-GroupLoot-Pass-Up" end
    local w = WINDOW[action]
    if w then
        for _, atlas in ipairs(w.radial or {}) do
            if hasAtlas(atlas) then return { atlas = atlas } end
        end
        return w.icon
    end
    return CK.Mapping:ActionIcon(action)
end

-- What the secure click runs for an action, or nil
function T.Macro(action)
    if not T.IsBound(action) then return nil end
    local kind, value = action:match("^(%a+):(.+)$")
    if kind == "spell" then
        local cast = CK.Mapping.SpellCast(value)
        return cast and ("/cast " .. cast)
    elseif kind == "item" then
        return "/use item:" .. value
    elseif kind == "macro" then
        local _, _, body = GetMacroInfo(value)
        return body
    end
    local w = WINDOW[action]
    if w and w.macro then return w.macro end
    local name = windowButton(action)
    return name and ("/click " .. name)
end

-- The windows a corner can open, for the picker (ours: this addon's)
function T.WindowEntries(ours)
    local list = {}
    for _, w in ipairs(WINDOWS) do
        if (w.ours or false) == (ours or false) and windowButton(w.key) then
            list[#list + 1] = { action = w.key, name = T.Label(w.key), icon = T.Icon(w.key) }
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function T.RegionAction(region) return settings().regions[region] end
function T.SetRegionAction(region, action)
    settings().regions[region] = action or "none"
    T:Apply()
end

function T.LayerAction(region, layer)
    local layers = settings().layers
    return layers[layer] and layers[layer][region]
end
function T.SetLayerAction(region, layer, action)
    local layers = settings().layers
    layers[layer] = layers[layer] or {}
    layers[layer][region] = action or "none"
    T:Apply()
end

-- What a corner runs with a layer held: the layer's action, else (none set
-- for that layer) its own, as the secure click does
function T.EffectiveAction(region, layer)
    local s = settings()
    if T.IsOff(region) then return nil end
    local held = layer and layer ~= "" and s.layers[layer] and s.layers[layer][region]
    if T.IsBound(held) then return held end
    return s.regions[region]
end

function T.IsOff(region)
    return settings().off[region] == true
end
function T.ToggleOff(region)
    local off = settings().off
    off[region] = not off[region] or nil
    T:Apply()
end

-- A PlayStation controller in hand (or its glyphs picked): only it has a
-- touchpad; on the others the same button is View / Minus, left to the game
function T.IsPlayStation()
    return CK:GlyphStyle() == "playstation"
end

-- Improved Forever on too: its touchpad corners would fight ours for the
-- pad's click; ours stay off until it is turned off
function T.OtherAddon()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return loaded and loaded("ImprovedForever") and true or false
end

-- The controller in use: the active one, else the first the game knows
local function deviceID()
    local GP = C_GamePad
    if not GP then return nil end
    local id = GP.GetActiveDeviceID and GP.GetActiveDeviceID()
    if id then return id end
    local all = GP.GetAllDeviceIDs and GP.GetAllDeviceIDs()
    return type(all) == "table" and all[1] or nil
end
T.DeviceID = deviceID

local function mappedState()
    local id = deviceID()
    local state = id and C_GamePad.GetDeviceMappedState and C_GamePad.GetDeviceMappedState(id)
    return type(state) == "table" and state or nil
end

-- Where the finger is on the pad now, or nil
function T.FingerPosition()
    local state = mappedState()
    local stick = state and state.sticks and state.sticks[PAD_STICK]
    if stick then return stick.x or 0, stick.y or 0 end
end

local function padIndex(button)
    local index = C_GamePad and C_GamePad.ButtonBindingToIndex and C_GamePad.ButtonBindingToIndex(button)
    return index and index + 1 or nil
end

-- The shoulders / triggers held now, as a layer ("LT", "LBRT"...), or ""
function T.HeldLayer()
    local state = mappedState()
    local pad = state and state.buttons
    if not pad then return "" end
    local name = ""
    for _, part in ipairs(HELD_ORDER) do
        local i = padIndex(HELD_KEY[part])
        if i and pad[i] then name = name .. part end
    end
    return name
end

-- The corner a finger position falls in (the secure snippet's own test):
-- one turned off gives its area to the corner beside it, then the one
-- above / below it
function T.RegionAt(x, y)
    local h, v = x > 0 and "right" or "left", y > 0 and "up" or "down"
    local beside = v .. (h == "right" and "left" or "right")
    local across = (v == "up" and "down" or "up") .. h
    for _, name in ipairs({ v .. h, beside, across }) do
        if not T.IsOff(name) then return name end
    end
end

---------------------------------------------------------------------------
-- The secure click
---------------------------------------------------------------------------
local click = CK.NewFrame("Button", "ControllerKeyboardTouchClick", UIParent,
    "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
click:SetSize(1, 1)
click:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -20, 20)
click:RegisterForClicks("AnyDown", "AnyUp")
click:SetAttribute("ec-stick", PAD_STICK)

-- Acts on the press or the release, whichever ActionButtonUseKeyDown makes
-- action buttons fire on, and once per click (the pad's left and right
-- halves are two raw buttons that both report as a click). The secure
-- environment has no GetTime: a "held" flag does the debouncing.
SecureHandlerWrapScript(click, "OnClick", click, [[
    self:SetAttribute("type", nil)
    local keydown = (self:GetAttribute("ec-keydown") or 1) == 1
    if down then
        if self:GetAttribute("ec-held") then
            return false
        end
        self:SetAttribute("ec-held", true)
        self:SetAttribute("ec-region", nil)
        if not keydown then
            return false
        end
    else
        if not self:GetAttribute("ec-held") then
            return false
        end
        self:SetAttribute("ec-held", nil)
        if keydown then
            return false
        end
    end
    local state = GetGamePadState()
    local stick = state and state.sticks and state.sticks[self:GetAttribute("ec-stick")]
    local x, y = stick and stick.x or 0, stick and stick.y or 0
    local h, v = x > 0 and "right" or "left", y > 0 and "up" or "down"
    local order = newtable(v .. h, v .. (h == "right" and "left" or "right"),
        (v == "up" and "down" or "up") .. h)
    local region
    for _, name in ipairs(order) do
        if not self:GetAttribute("ec-off-" .. name) then
            region = name
            break
        end
    end
    if not region then
        return false
    end
    self:SetAttribute("ec-region", region)
    -- L1 / R1 / L2 / R2 held: the corner's action of that layer, if any
    local pad = state and state.buttons
    local lb, rb = self:GetAttribute("ec-lb"), self:GetAttribute("ec-rb")
    local lt, rt = self:GetAttribute("ec-lt"), self:GetAttribute("ec-rt")
    if pad then
        local layer = ((lb and pad[lb]) and "LB" or "") .. ((rb and pad[rb]) and "RB" or "")
            .. ((lt and pad[lt]) and "LT" or "") .. ((rt and pad[rt]) and "RT" or "")
        local layered = layer ~= "" and self:GetAttribute("ec-lmacro-" .. layer .. "-" .. region)
        if layered then
            self:SetAttribute("macrotext", layered)
            self:SetAttribute("type", "macro")
            return
        end
    end
    local macro = self:GetAttribute("ec-macro-" .. region)
    if not macro then
        return false
    end
    self:SetAttribute("macrotext", macro)
    self:SetAttribute("type", "macro")
]])

click:SetScript("PostClick", function(self, _, down)
    local s = settings()
    if not (s and s.debug) then return end
    -- (only a press that ran something: the corner it found is kept after)
    local tapped = self:GetAttribute("type") == "macro" and self:GetAttribute("ec-region")
    if tapped then
        CK:Print("touch: %s -> %s", L["TOUCH_R_" .. tapped:upper()], T.Label(s.regions[tapped]))
    end
end)

---------------------------------------------------------------------------
-- The mouse mode's button: a secure button too, so it works in combat (it
-- only flips an attribute of the click; the cursor's settings follow in
-- plain code, PostClick)
---------------------------------------------------------------------------
local toggle = CK.NewFrame("Button", "ControllerKeyboardTouchMouseToggle", UIParent,
    "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
toggle:SetSize(1, 1)
toggle:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -20, 20)
toggle:RegisterForClicks("AnyDown", "AnyUp")
SecureHandlerSetFrameRef(toggle, "click", click)
-- Fork CoolerMgdn (asked): with something of the Gamepad tab on that button
-- (its router: Mapping.lua, "ec-short"), a short press runs it (on the
-- release, the layer of the triggers held) and a long one (HoldClock.lua,
-- about half a second) turns the mouse mode on or off, in combat too; with
-- nothing there, any press.
toggle:SetAttribute("type", "click")
toggle:SetAttribute("useOnKeyDown", false)
-- No clock in the secure code (GetTime is nil there in Forever): the press
-- is timed by the clock of HoldClock.lua (the state driver's looks, in
-- combat too), read on the release
SecureHandlerWrapScript(toggle, "OnClick", toggle, [[
    -- Never "return false": the click goes on (as "LeftButton" it runs
    -- nothing), so PreClick / PostClick see every press and release
    local c = self:GetFrameRef("click")
    if not self:GetAttribute("ec-short") then
        if down then c:SetAttribute("ec-mouse", not c:GetAttribute("ec-mouse") or nil) end
        return
    end
    if down then
        self:SetAttribute("ec-lp-ticks", 0)
        self:SetAttribute("ec-lp-on", true)
        local clock = self:GetFrameRef("ec-clock")
        if clock then clock:SetAttribute("state-eclp", "tick") end
        return
    end
    self:SetAttribute("ec-lp-on", nil)
    if (self:GetAttribute("ec-lp-ticks") or 0) >= (self:GetAttribute("ec-lp-n") or 3) then
        c:SetAttribute("ec-mouse", not c:GetAttribute("ec-mouse") or nil)
        return
    end
    -- The layer: the triggers held now
    local st = GetGamePadState()
    local pad = st and st.buttons
    local lt, rt = self:GetAttribute("ec-lt"), self:GetAttribute("ec-rt")
    local layer = ((pad and lt and pad[lt]) and "LT" or "") .. ((pad and rt and pad[rt]) and "RT" or "")
    if not self:GetAttribute("ec-has-" .. layer) then return end
    return "ecshort" .. layer
]])
toggle:SetScript("PreClick", function(self, _, down)
    if not down then return end
    T.micHeld = true
    if not self:GetAttribute("ec-short") then return end
    -- Felt and seen: let go now for the mouse mode
    if CK.HoldClock then
        CK.HoldClock:Feel(self, function()
            if CK.TouchOverlay and CK.TouchOverlay.Refresh then CK.TouchOverlay:Refresh() end
        end)
    end
end)
toggle:SetScript("PostClick", function(self, _, down)
    if CK.Flight then pcall(CK.Flight.Mic, CK.Flight, self, down) end
    if down == false then T.micHeld = nil end
    if T.MouseMode() ~= (T.shownMouse or false) then T:MouseModeChanged() end
end)

-- Mapping.lua, after binding: the button's router (its short press), when
-- the mouse mode's button has something of the Gamepad tab
function T:SyncMouseShort()
    if InCombatLockdown() then return end
    local s = settings()
    local key = s and s.mouseKey
    local M, input = CK.Mapping, nil
    if key and M and M.ShortTarget then
        for _, i in ipairs(M.INPUTS) do
            if M:InputKey(i) == key then input = i end
        end
    end
    local any = false
    for _, layer in ipairs(M and M.LAYERS or {}) do
        local target = input and T.HoldsKey(key) and M:ShortTarget(input, layer) or nil
        toggle:SetAttribute("*clickbutton-ecshort" .. layer, target)
        toggle:SetAttribute("ec-has-" .. layer, target and true or nil)
        if target then any = true end
    end
    toggle:SetAttribute("ec-lt", M and M.padIndex and M.padIndex("PADLTRIGGER") or nil)
    toggle:SetAttribute("ec-rt", M and M.padIndex and M.padIndex("PADRTRIGGER") or nil)
    toggle:SetAttribute("ec-short", any or nil)
    if any and CK.HoldClock then CK.HoldClock:Attach(toggle) end
end

-- Mapping.lua: a key the mouse mode's button takes (its router isn't bound
-- there: the toggle clicks it on a short press)
function T.HoldsKey(key)
    local s = settings()
    return s ~= nil and s.mouseKey ~= nil and s.mouseKey == key and T.Blocked() == nil
end

function T.MouseMode()
    return click:GetAttribute("ec-mouse") and true or false
end

---------------------------------------------------------------------------
-- The game's settings the pad changes while it is ours, each given back
---------------------------------------------------------------------------
local function getCVar(name)
    local getter = (C_CVar and C_CVar.GetCVar) or GetCVar
    local ok, value = pcall(getter, name)
    return ok and value or nil
end

local function setCVar(name, value)
    local setter = (C_CVar and C_CVar.SetCVar) or SetCVar
    return pcall(setter, name, value)
end

-- A setting changed by us: what the player had kept (in the saved settings,
-- in case the game closes before it is given back); want nil gives it back
local function hold(name, want)
    local s = settings()
    s.saved = s.saved or {}
    local current = getCVar(name)
    if current == nil then return false end
    if want ~= nil then
        if current ~= want then
            if s.saved[name] == nil then s.saved[name] = current end
            setCVar(name, want)
        end
    elseif s.saved[name] ~= nil then
        local was = s.saved[name]
        s.saved[name] = nil
        if current ~= was then setCVar(name, was) end
    end
    return true
end

local function giveBackAll()
    local s = settings()
    for name in pairs(s.saved or {}) do hold(name, nil) end
end

-- The game's setting that puts its cursor back in the middle
local KEEP_CURSOR = { "GamePadCursorCentering" }

-- The mouse buttons in the mode. The game's touch cursor clicks itself: a
-- tap on the pad is its left click (GamePadTouchTap...), the right one
-- with GamePadTouchTapRightClick on. Its cursor click buttons
-- (GamePadCursorLeftClick / RightClick) are the stick cursor's only: R1 /
-- L1 given them did nothing (checked in game). Create pressed before a tap
-- (held, the game hid its cursor) was found odd: so a tap is the left
-- button, a second tap right after it the right one (asked). The game
-- takes each tap itself, at once: the first of a double tap stays a left
-- click; once it is made, the game's tap is a right click for a moment.
local TAP_RIGHT = "GamePadTouchTapRightClick"
local TAP_MAX = 0.35      -- longer than this on the pad: not a tap (a slide)
local SETTLE = 0.06       -- after a tap, before the next one is a right click
local WINDOW = 0.45       -- the second tap starts within this
local AFTER = 0.2         -- the right click made: then left clicks again

local tapWatch = CK.NewFrame("Frame")
tapWatch:Hide()
local tap = {}
local function rightOff()
    T.rightArmed = nil
    hold(TAP_RIGHT, nil)
end
tapWatch:SetScript("OnUpdate", function(_, elapsed)
    local x, y = T.FingerPosition()
    local touching = x and (math.abs(x) > 0.02 or math.abs(y) > 0.02) or false
    tap.t = (tap.t or 0) + elapsed
    if tap.state == "down" then
        if not touching then
            -- A short touch: a tap (the left click). A second one, as a right click
            if tap.second then
                tap.state, tap.t = "done", 0
            elseif tap.t <= TAP_MAX then
                tap.state, tap.t = "settle", 0
            else
                tap.state = nil
            end
        end
    elseif tap.state == "settle" then
        if touching then
            tap.state, tap.t, tap.second = "down", 0, nil
        elseif tap.t >= SETTLE then
            tap.state, tap.t = "armed", 0
            T.rightArmed = true
            hold(TAP_RIGHT, "1")
        end
    elseif tap.state == "armed" then
        if touching then
            tap.state, tap.t, tap.second = "down", 0, true
        elseif tap.t >= WINDOW then
            tap.state = nil
            rightOff()
        end
    elseif tap.state == "done" then
        if tap.t >= AFTER then
            tap.state, tap.second = nil, nil
            rightOff()
        end
    elseif touching then
        tap.state, tap.t, tap.second = "down", 0, nil
    end
end)

-- Experimental, off by default (asked): the game's setting changed after
-- each tap was the first suspect of a taint popup
function T.DoubleTapOn()
    local s = settings()
    return s and s.doubleTapRight == true and T.MouseSupported()
end

function T.SetDoubleTap(v)
    local s = settings()
    if not s then return end
    s.doubleTapRight = v and true or false
    if InCombatLockdown() then return end
    wipe(tap)
    rightOff()
    tapWatch:SetShown(T.MouseMode() and T.Blocked() == nil and T.DoubleTapOn() or false)
    if CK.TouchOverlay then CK.TouchOverlay:Refresh() end
end

function T.MouseSupported()
    return getCVar(TAP_RIGHT) ~= nil
end

function T:MouseModeChanged()
    T.shownMouse = T.MouseMode()
    local on = T.MouseMode() and T.Blocked() == nil
    if on then
        hold(CURSOR_CVAR, "1")
        for _, name in ipairs(KEEP_CURSOR) do hold(name, "0") end
        if not T.MouseSupported() then CK:Print(L.TOUCH_MOUSE_NO_CLICK) end
        wipe(tap)
        tapWatch:SetShown(T.DoubleTapOn() or false)
    else
        tapWatch:Hide()
        wipe(tap)
        rightOff()
        -- (an earlier version gave them R1 / L1)
        hold(LEFT_CVAR, nil)
        hold(RIGHT_CVAR, nil)
        for _, name in ipairs(KEEP_CURSOR) do hold(name, nil) end
        -- The touch cursor off again while the corners are ours
        hold(CURSOR_CVAR, T.Blocked() == nil and "0" or nil)
    end
    if CK.TouchOverlay then CK.TouchOverlay:Refresh() end
    local s = settings()
    if s and s.mouseSay ~= false then
        CK:Print(on and (T.DoubleTapOn() and L.TOUCH_MOUSE_ON_DT or L.TOUCH_MOUSE_ON) or L.TOUCH_MOUSE_OFF)
    end
end

-- Out of combat only: the mode off (a /reload, the touchpad turned off)
local function mouseOff()
    if click:GetAttribute("ec-mouse") then
        click:SetAttribute("ec-mouse", nil)
        T:MouseModeChanged()
    end
end

---------------------------------------------------------------------------
-- When the click is ours
---------------------------------------------------------------------------
-- A window of the game's gamepad UI open: the click is the game's then
-- (TOGGLEUIFOCUS, moving the pad onto the window and back)
local function windowsShown()
    local manager = _G.GamepadMode and GamepadMode.FrameControlsManager
    return manager ~= nil and type(manager.shownFrames) == "table" and #manager.shownFrames > 0
end

-- Our own windows that take the pad (the chat keyboard, the panel...)
local function oursOpen()
    if CK.IsOpen and CK:IsOpen() then return true end
    if CK.Phrases and CK.Phrases.IsOpen and CK.Phrases:IsOpen() then return true end
    if ControllerKeyboardWheel and ControllerKeyboardWheel:IsShown() then return true end
    if CK.Config and CK.Config:IsOpen() then return true end
    if CK.Guide and CK.Guide.IsOpen and CK.Guide:IsOpen() then return true end
    return false
end
T.OursOpen = oursOpen

T.pending = false
T.bound = false

-- Why the click is ours or not: nil when it is, else a reason key
function T.Blocked()
    local s = settings()
    if not s or not s.enabled then return "off" end
    if T.OtherAddon() then return "other" end
    if not T.IsPlayStation() then return "pad" end
    return nil
end

function T:Apply()
    local s = settings()
    if not s then return end
    if InCombatLockdown() then
        self.pending = true
        return
    end
    self.pending = false
    click:SetAttribute("ec-keydown", getCVar("ActionButtonUseKeyDown") == "0" and 0 or 1)
    click:SetAttribute("ec-lb", padIndex("PADLSHOULDER"))
    click:SetAttribute("ec-rb", padIndex("PADRSHOULDER"))
    click:SetAttribute("ec-lt", padIndex("PADLTRIGGER"))
    click:SetAttribute("ec-rt", padIndex("PADRTRIGGER"))
    for _, region in ipairs(T.REGIONS) do
        local off = T.IsOff(region)
        click:SetAttribute("ec-off-" .. region, off or nil)
        click:SetAttribute("ec-macro-" .. region, not off and T.Macro(s.regions[region]) or nil)
        for _, layer in ipairs(T.LAYERS) do
            local held = s.layers[layer] and s.layers[layer][region]
            click:SetAttribute("ec-lmacro-" .. layer .. "-" .. region, not off and T.Macro(held) or nil)
        end
    end
    -- (Fork CoolerMgdn: through the bindings' one place, Binds.lua)
    CK.Binds:Register("touch-click", click, 30, true, { label = "touchpad" })
    CK.Binds:Register("touch-mouse", toggle, 31, true, { label = "mouse mode" })
    CK.Binds:Clear("touch-click")
    CK.Binds:Clear("touch-mouse")
    local blocked = T.Blocked()
    if blocked then mouseOff() end
    -- Ours only while the game has the pad's focus (no window of its, none
    -- of ours); through combat whatever is open, as the other bindings
    local free = not windowsShown() or UnitAffectingCombat("player")
    local ours = blocked == nil and free and not oursOpen()
    if ours then
        for _, modifier in ipairs(MODIFIERS) do
            CK.Binds:Set("touch-click", modifier .. KEY, "click", click:GetName(), "LeftButton")
        end
    end
    -- The mouse mode's button: wherever the pad is the game's or ours
    local mouseKey = blocked == nil and s.mouseKey or nil
    if mouseKey and not oursOpen() then
        for _, modifier in ipairs(MODIFIERS) do
            CK.Binds:Set("touch-mouse", modifier .. mouseKey, "click", toggle:GetName(), "LeftButton")
        end
    end
    -- Fork CoolerMgdn: its short press (what the Gamepad tab put there)
    self:SyncMouseShort()
    self.bound = ours
    -- The touch cursor off while the corners are ours (a finger on a corner
    -- would show it), the player's own once they aren't. Changed only when
    -- that changes, never as windows open and close: a setting of the
    -- game's changed by an addon while its gamepad windows are open taints
    -- them (reported: the game blocked SetPreferredGamepadInteractTarget,
    -- ClearTarget... with the map and the bags open)
    local corners = blocked == nil
    if corners ~= self.cornersOn and not T.MouseMode() then
        self.cornersOn = corners
        hold(CURSOR_CVAR, corners and "0" or nil)
    end
    if CK.TouchOverlay then CK.TouchOverlay:Refresh() end
end

-- /ec touch debug: why the click is or isn't ours
function T:Probe()
    local s = settings()
    local x, y = T.FingerPosition()
    CK:Print("touch: %s -> %s, blocked: %s, game window: %s, ours open: %s, pending: %s, mouse: %s (%s)",
        KEY, tostring(GetBindingAction(KEY, true)), tostring(T.Blocked()), tostring(windowsShown()),
        tostring(oursOpen()), tostring(self.pending), tostring(T.MouseMode()), tostring(s.mouseKey))
    CK:Print("touch: finger %s, %s, corner: %s, held: %s, cursor: %s, clicks: %s / %s", tostring(x), tostring(y),
        tostring(x and T.RegionAt(x, y)), T.HeldLayer(), tostring(getCVar(CURSOR_CVAR)),
        tostring(getCVar(LEFT_CVAR)), tostring(getCVar(RIGHT_CVAR)))
    -- The game's cursor settings this client has, with their values (what
    -- the mouse mode may change)
    if C_Console and C_Console.GetAllCommands then
        local list = {}
        for _, c in ipairs(C_Console.GetAllCommands() or {}) do
            local name = type(c) == "table" and c.command
            if type(name) == "string" and (name:find("^GamePadCursor") or name:find("^GamePadTouch")) then
                list[#list + 1] = name .. "=" .. tostring(getCVar(name))
            end
        end
        table.sort(list)
        if #list > 0 then CK:Print("touch: %s", table.concat(list, ", ")) end
    end
    s.debug = not s.debug
    CK:Print("touch debug: %s", s.debug and L.ON or L.OFF)
end

---------------------------------------------------------------------------
-- The mouse mode's button, learned: the next button pressed
---------------------------------------------------------------------------
local learner
local NOT_LEARNED = { PADBACK = true, PADLSHOULDER = true, PADRSHOULDER = true, PADLTRIGGER = true, PADRTRIGGER = true }

function T:LearnMouseKey(onDone)
    if InCombatLockdown() then return CK:BlockedByCombat() end
    learner = learner or CK.NewFrame("Frame", nil, UIParent)
    learner:SetAllPoints(UIParent)
    learner:EnableGamePadButton(true)
    learner.left = 10
    learner:SetScript("OnUpdate", function(self, elapsed)
        self.left = self.left - elapsed
        if self.left <= 0 then
            self:Hide()
            CK:Print(L.TOUCH_LEARN_NONE)
            if onDone then onDone(nil) end
        end
    end)
    learner:SetScript("OnGamePadButtonDown", function(self, button)
        if NOT_LEARNED[button] then return CK:Print(L.TOUCH_LEARN_REFUSED, CK.Mapping.KeyLabel(button)) end
        self:Hide()
        settings().mouseKey = button
        CK:Print(L.TOUCH_LEARN_DONE, button)
        T:Apply()
        -- Fork CoolerMgdn: the key's own bindings left to the toggle
        CK.Mapping:Apply()
        if onDone then onDone(button) end
    end)
    learner:Show()
    CK:Print(L.TOUCH_LEARN_START)
end

function T:ForgetMouseKey()
    if InCombatLockdown() then return CK:BlockedByCombat() end
    settings().mouseKey = nil
    mouseOff()
    T:Apply()
    CK.Mapping:Apply()
end

---------------------------------------------------------------------------
-- Improved Forever's corners, taken once while it is on (its saved
-- settings load only with it)
---------------------------------------------------------------------------
local IF_WINDOWS = { peekmap = "map", nodes = "none", journal = "none", icmenu = "none", wiki = "none",
    fishcollection = "none", recentloot = "none", destroy = "none", legacy = "none", buffs = "none", clock = "none" }

local function fromIF(action)
    if type(action) ~= "string" then return nil end
    if action:find("^emote:") then return "none" end
    if IF_WINDOWS[action] then return IF_WINDOWS[action] end
    if action:find(":", 1, true) or WINDOW[action] or action == "none" then return action end
    return "none"
end

function T:ImportImprovedForever()
    local s = settings()
    local db = _G.ImprovedForeverDB
    local touch = type(db) == "table" and type(db.touch) == "table" and db.touch
    if s.imported or not touch then return false end
    s.imported = true
    for _, region in ipairs(T.REGIONS) do
        local a = fromIF(type(touch.regions) == "table" and touch.regions[region])
        if a then s.regions[region] = a end
        if type(touch.off) == "table" and touch.off[region] then s.off[region] = true end
    end
    if type(touch.layers) == "table" then
        for layer, corners in pairs(touch.layers) do
            if type(corners) == "table" then
                s.layers[layer] = s.layers[layer] or {}
                for region, action in pairs(corners) do
                    local a = fromIF(action)
                    if a then s.layers[layer][region] = a end
                end
            end
        end
    end
    if touch.enabled == false then s.enabled = false end
    return true
end

---------------------------------------------------------------------------
-- The DualSense light bar: off, your health, your class's colour, red in
-- combat. The game's own call, when this client has it.
---------------------------------------------------------------------------
T.LIGHT_MODES = { "off", "health", "class", "combat" }

function T.LightSupported()
    return C_GamePad and C_GamePad.SetLedColor ~= nil and CreateColor ~= nil
end

local lastLed, lastError
T.lightLog = {}
local function logLight(text)
    T.lightLog[#T.lightLog + 1] = text
    if #T.lightLog > 8 then table.remove(T.lightLog, 1) end
end

-- color: a ColorMixin (its values may be secret: the game's own health
-- colour curve), r, g, b: plain numbers
local function setLedColor(color, key)
    if key and key == lastLed then return end
    lastLed = key
    local ok, err = pcall(C_GamePad.SetLedColor, color)
    if not ok and err ~= lastError then
        lastError = err
        logLight("SetLedColor: " .. tostring(err))
    end
end

local function setLed(r, g, b)
    if not CreateColor then return end
    setLedColor(CreateColor(r, g, b), format("%.2f,%.2f,%.2f", r, g, b))
end

local function clearLed()
    lastLed = nil
    if C_GamePad and C_GamePad.ClearLedColor then pcall(C_GamePad.ClearLedColor) end
end

local function classColor()
    local _, class = UnitClass("player")
    local c = class and (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
    if c then return c.r, c.g, c.b end
    return 0.2, 0.4, 1
end

local function isSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end

-- Green, yellow at half, red when low
local function healthRGB(f)
    f = math.max(0, math.min(1, f))
    if f > 0.5 then return (1 - f) * 2, 1, 0 end
    return 1, f * 2, 0
end

-- The game's colour curve for a health it keeps secret from addons
local curve
local function healthCurve()
    if curve ~= nil then return curve or nil end
    curve = false
    if C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor then
        local ok, c = pcall(C_CurveUtil.CreateColorCurve)
        if ok and c then
            if c.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then
                pcall(c.SetType, c, Enum.LuaCurveType.Linear)
            end
            pcall(c.AddPoint, c, 0, CreateColor(1, 0, 0))
            pcall(c.AddPoint, c, 0.5, CreateColor(1, 1, 0))
            pcall(c.AddPoint, c, 1, CreateColor(0, 1, 0))
            curve = c
        end
    end
    return curve or nil
end

-- Forever keeps your health from addons (a secret value, out of combat
-- too: checked in game), and the light bar takes no secret colour (the
-- game's curve's refused: "bad argument"). The health mode then can't be:
-- not offered, and one picked before shows the combat mode's colours.
function T.HealthHidden()
    return isSecret(UnitHealth("player"))
end

function T.LightModes()
    if T.HealthHidden() then return { "off", "class", "combat" } end
    return T.LIGHT_MODES
end

local function updateHealth()
    local hp, max = UnitHealth("player"), UnitHealthMax("player")
    if type(hp) == "number" and type(max) == "number" and not isSecret(hp) and not isSecret(max) then
        if max <= 0 then return end
        return setLed(healthRGB(hp / max))
    end
    -- Secret: the percent, when it isn't
    if UnitHealthPercent then
        local ok, p = pcall(UnitHealthPercent, "player")
        if ok and type(p) == "number" and not isSecret(p) then
            return setLed(healthRGB(p > 1 and p / 100 or p))
        end
    end
    if lastError ~= "secret" then
        lastError = "secret"
        logLight("health: hidden by the game, combat colours instead")
    end
    return false
end

local function updateCombat()
    if UnitAffectingCombat("player") then setLed(1, 0, 0) else setLed(classColor()) end
end

---------------------------------------------------------------------------
-- Fork CoolerMgdn: notifications (asked): the light bar flashes a colour
-- of its own when something wants you (a whisper, a ready check, an
-- invite...), over whatever mode it is in, then goes back to it. The
-- events are the vibrations' (Vibration.lua: V:Fire calls T:Notify), so
-- they come whether the vibrations are on or not.
---------------------------------------------------------------------------
local NOTIFY = {
    whisper = { 1, 0.45, 0.95 },      -- the game's whisper pink
    invite = { 0.2, 0.55, 1 },
    lfg = { 0.2, 1, 0.3 },
    readyCheck = { 1, 0.85, 0 },
    rezSummon = { 0.6, 0.35, 1 },
    tradeDuel = { 1, 0.5, 0 },
    levelUp = { 1, 0.9, 0.4 },
    rareLoot = { 0.65, 0.25, 1 },
    bagsFull = { 1, 1, 1 },
}
T.NOTIFY_KEYS = { "whisper", "invite", "lfg", "readyCheck", "rezSummon", "tradeDuel", "levelUp", "rareLoot", "bagsFull" }
local BLINKS, ON_TIME, OFF_TIME = 3, 0.22, 0.16

function T:Notify(key)
    local color = NOTIFY[key]
    local s = CK.db and settings()
    if not (color and s and s.lightNotify and T.LightSupported()) then return end
    if s.notifyOff and s.notifyOff[key] then return end
    if T.flashing then return end
    T.flashing = true
    local step = 0
    local function tick()
        step = step + 1
        if step > BLINKS * 2 then
            T.flashing = nil
            lastLed = nil
            T:UpdateLight()
            return
        end
        if step % 2 == 1 then
            setLed(color[1], color[2], color[3])
            C_Timer.After(ON_TIME, tick)
        else
            setLed(0, 0, 0)
            C_Timer.After(OFF_TIME, tick)
        end
    end
    tick()
end

function T:UpdateLight()
    if not (CK.db and T.LightSupported()) or T.flashing then return end
    local mode = settings().light
    if mode == "health" then
        if updateHealth() == false then updateCombat() end
    elseif mode == "class" then
        setLed(classColor())
    elseif mode == "combat" then
        updateCombat()
    elseif lastLed then
        clearLed()
    end
end

function T:SetLight(mode)
    settings().light = mode
    lastLed, lastError = nil, nil
    if mode == "off" then clearLed() end
    self:UpdateLight()
end

function T:CycleLight()
    local modes, i = T.LightModes(), 1
    for n, m in ipairs(modes) do
        if m == settings().light then i = n end
    end
    local mode = modes[i % #modes + 1]
    self:SetLight(mode)
    CK:Print("%s: %s", L.TOUCH_LIGHT, L["TOUCH_LIGHT_" .. mode:upper()])
end

-- /ec light debug: what the light bar gets
function T:LightProbe()
    local hp, max = UnitHealth("player"), UnitHealthMax("player")
    CK:Print("light: api %s, mode %s, health %s / %s (secret: %s / %s), percent api: %s, curve: %s",
        tostring(T.LightSupported()), tostring(settings().light), isSecret(hp) and "?" or tostring(hp),
        isSecret(max) and "?" or tostring(max), tostring(isSecret(hp)), tostring(isSecret(max)),
        tostring(UnitHealthPercent ~= nil), tostring(healthCurve() ~= nil))
    lastLed = nil
    self:UpdateLight()
    CK:Print("light: last sent %s", tostring(lastLed))
    -- A plain colour, to see the call itself works (the mode's own again next)
    if T.LightSupported() then
        local ok, err = pcall(C_GamePad.SetLedColor, CreateColor(0.2, 0.4, 1))
        CK:Print("light: test colour (blue): %s", ok and "ok" or tostring(err))
        C_Timer.After(1.5, function()
            lastLed = nil
            T:UpdateLight()
        end)
    end
    for _, line in ipairs(T.lightLog) do CK:Print("light: %s", line) end
end

---------------------------------------------------------------------------
-- /ec padtest: every button press the game reports, by its name (the mic
-- button, Create...), and its raw number when the client gives them, for
-- 20 seconds or until typed again
---------------------------------------------------------------------------
local tester
function T:PadTest()
    if tester and tester:IsShown() then
        tester:Hide()
        return CK:Print(L.PADTEST_STOP)
    end
    tester = tester or CK.NewFrame("Frame", nil, UIParent)
    tester:SetAllPoints(UIParent)
    local GP = C_GamePad
    local id = deviceID()
    local raw = id and GP and GP.GetDeviceRawState and GP.GetDeviceRawState(id)
    local state = mappedState()
    CK:Print(L.PADTEST_START, tostring(type(raw) == "table" and raw.name or (state and state.name) or "?"),
        type(raw) == "table" and #(raw.rawButtons or {}) or 0, state and #(state.buttons or {}) or 0)
    -- The game's names: each press, as its own windows get them (the
    -- buttons still go on to the game)
    tester:EnableGamePadButton(true)
    if tester.SetPropagateGamePadInput then pcall(tester.SetPropagateGamePadInput, tester, true)
    elseif tester.SetPropagateKeyboardInput then pcall(tester.SetPropagateKeyboardInput, tester, true) end
    tester:SetScript("OnGamePadButtonDown", function(_, button)
        CK:Print(L.PADTEST_NAMED, tostring(button), CK.Mapping.KeyLabel(button) or "")
    end)
    -- The raw buttons, when this client gives them: a button with no name
    -- shows only there
    local before, left = {}, 20
    tester:SetScript("OnUpdate", function(self, elapsed)
        left = left - elapsed
        if left <= 0 then
            self:Hide()
            return CK:Print(L.PADTEST_STOP)
        end
        local dev = deviceID()
        local r = dev and GP and GP.GetDeviceRawState and GP.GetDeviceRawState(dev)
        if type(r) ~= "table" then return end
        for i, on in ipairs(r.rawButtons or {}) do
            if on and not before[i] then CK:Print(L.PADTEST_RAW, i) end
            before[i] = on
        end
    end)
    tester:Show()
end

---------------------------------------------------------------------------
-- Init: after the other modules (Chat.lua's PLAYER_LOGIN)
---------------------------------------------------------------------------
function T:Init()
    local s = settings()
    if not s then return end
    -- (the double taps: no longer)
    s.doubles = nil
    if T.OtherAddon() then
        if self:ImportImprovedForever() then CK:Print(L.TOUCH_IMPORTED) end
        if s.enabled then CK:Print(L.TOUCH_IF_ON) end
    end
    -- A DualSense's own buttons out of the paddles' places, once
    if not InCombatLockdown() and CK.Mapping:MigrateDualSense() then
        CK.Mapping:Apply()
        if CK.Paddles and CK.Paddles.Apply then CK.Paddles:Apply() end
        CK:Print(L.FORK_DUALSENSE_MOVED)
    end
    -- Saved from a game closed while they were ours: back to the player's
    giveBackAll()
    -- (an older version kept the touch cursor here)
    if s.savedCursor ~= nil then
        setCVar(CURSOR_CVAR, s.savedCursor)
        s.savedCursor = nil
    end
    self:Apply()
    self:UpdateLight()

    local events = CK.NewFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("CVAR_UPDATE")
    events:RegisterEvent("PLAYER_LOGOUT")
    events:RegisterUnitEvent("UNIT_HEALTH", "player")
    -- The group finder's "ready?" (no vibration of its own)
    pcall(events.RegisterEvent, events, "LFG_PROPOSAL_SHOW")
    events:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    for _, event in ipairs({ "GAME_PAD_ACTIVE_CHANGED", "GAME_PAD_CONNECTED", "GAME_PAD_DISCONNECTED" }) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event, name)
        -- Of the game's settings, only the key-down one changes the click
        -- (the cursor's, changed by the mouse mode, don't)
        if event == "CVAR_UPDATE" and type(name) == "string" and name:lower() ~= "actionbuttonusekeydown" then return end
        if event == "PLAYER_LOGOUT" then
            giveBackAll()
            return
        end
        if event == "LFG_PROPOSAL_SHOW" then return T:Notify("lfg") end
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then return T:UpdateLight() end
        if event == "PLAYER_REGEN_DISABLED" then return T:UpdateLight() end
        if event:find("^GAME_PAD") then
            lastLed = nil
            CK.labelCache = nil
            T:UpdateLight()
        end
        if event == "PLAYER_REGEN_ENABLED" then T:UpdateLight() end
        if T.pending or event == "CVAR_UPDATE" or event:find("^GAME_PAD") or event == "PLAYER_REGEN_ENABLED" then
            T:Apply()
        end
    end)

    -- A window opened or closed, ours or the game's: the click is ours or
    -- the game's again
    local last, wait = nil, 0
    events:SetScript("OnUpdate", function(_, elapsed)
        wait = wait - elapsed
        if wait > 0 then return end
        wait = 0.1
        local now = tostring(windowsShown()) .. tostring(oursOpen())
        if now ~= last then
            last = now
            if not InCombatLockdown() then T:Apply() else T.pending = true end
        end
    end)
end
