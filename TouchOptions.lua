local _, CK = ...
local L = CK.L

-- Fork CoolerMgdn: the Touchpad tab of the configuration panel
-- (Touchpad.lua): the switch, the corners and their L1 / R1 / L2 / R2
-- layers, the mouse mode, the corners on screen (TouchOverlay.lua), the
-- light bar, the buttons' test.
local Config = CK.Config
local T = CK.Touchpad

-- After Gamepad
table.insert(Config.TABS, 3, "touchpad")

local function s() return CK.db.settings.touch end

local function regionName(region) return L["TOUCH_R_" .. region:upper()] end

-- The layers' names on the pad in hand (L1... on a PlayStation pad)
local function layerName(layer)
    return CK:GlyphMarkup(layer, 18)
end

-- The picker for a corner's action: the game's windows, ours, spells,
-- items, macros. set(action) with what was chosen
local function pick(page, kicker, title, current, set)
    local M = CK.Mapping
    page:OpenPicker({
        kicker = kicker, title = title, rows = 8, current = current,
        lists = {
            { label = L.TOUCH_LIST_WINDOWS, entries = function()
                local list = { { action = "none", name = L.TOUCH_NOTHING, icon = T.Icon("none") } }
                for _, e in ipairs(T.WindowEntries(false)) do list[#list + 1] = e end
                return list
            end },
            { label = L.TOUCH_LIST_OURS, entries = function() return T.WindowEntries(true) end },
            { label = L.MAP_TAB_SPELLS, entries = function() return M:Catalog("spells", true) end },
            { label = L.MAP_TAB_ITEMS, entries = function() return M:Catalog("items", true) end },
            { label = L.MAP_TAB_MACROS, entries = function() return M:Catalog("macros", true) end },
        },
        marked = function(e) return e.action == current end,
        onChoose = function(e)
            page.picker:Close()
            set(e.action)
            Config:Toast(format(L.TOUCH_TOAST_SET, title, T.Label(e.action)))
            Config:Render()
        end,
    })
end

-- A row per corner: A picks its action, X clears it
local function cornerRow(b, page, id, label, kicker, get, set, extra)
    local row = {
        id = id, label = label, verb = L.V_CHANGE, tip = L.TIP_TOUCH_CORNER,
        text = function() return T.Label(get()) end,
        onA = function() pick(page, kicker, label, get(), set) end,
        onX = function() set("none") end, xVerb = L.V_EMPTY,
    }
    for k, v in pairs(extra or {}) do row[k] = v end
    return b.value(row)
end

-- Why the click isn't ours, said at the top of the tab
local function statusText()
    local why = T.Blocked()
    if why == "other" then return L.TOUCH_STATUS_OTHER end
    if why == "pad" then return L.TOUCH_STATUS_PAD end
    if why == "off" then return L.TOUCH_STATUS_OFF end
    return L.TOUCH_STATUS_ON
end

local function generalRows(b)
    local t = s()
    b.header(L.SEC_TOUCH)
    b.info(statusText)
    b.module({ id = "t_on", off = L.OFF_TOUCH, sub = L.OFF_TOUCH_SUB, label = L.LBL_TOUCH_ON, tip = L.TIP_TOUCH_ON,
        get = function() return t.enabled end,
        set = function(v)
            t.enabled = v
            T:Apply()
        end })
    b.header(L.HDR_TOUCH_TOOLS)
    b.button({ id = "t_test", label = L.LBL_PADTEST, tip = L.TIP_PADTEST, verb = L.V_TEST,
        func = function()
            T:PadTest()
            Config:Toast(L.TOAST_PADTEST)
        end })
    b.button({ id = "t_probe", label = L.LBL_TOUCH_PROBE, tip = L.TIP_TOUCH_PROBE, verb = L.V_TEST,
        func = function() T:Probe() end })
end

local function cornerRows(b, page)
    local t = s()
    b.header(L.SEC_TOUCH_CORNERS)
    for _, region in ipairs(T.REGIONS) do
        local name = regionName(region)
        cornerRow(b, page, "t_c_" .. region, name, L.SEC_TOUCH_CORNERS,
            function() return t.regions[region] end,
            function(a) T.SetRegionAction(region, a) end,
            { preview = function(c) CK.ConfigKit.Preview.Touch(c, t.regions, region, L.PREVIEW_TOUCH_BASE) end,
              onY = function() T.ToggleOff(region) end, yVerb = T.IsOff(region) and L.V_ON or L.V_OFF,
              text = function()
                  if T.IsOff(region) then return L.TOUCH_OFF_TAG end
                  return T.Label(t.regions[region])
              end })
    end
    b.info(L.TOUCH_OFF_INFO)
end

local function layerRows(b, page)
    b.header(L.SEC_TOUCH_LAYERS)
    b.info(L.TOUCH_LAYERS_INFO)
    for _, layer in ipairs(T.LAYER_LIST) do
        b.header(format(L.HDR_TOUCH_LAYER, layerName(layer)))
        for _, region in ipairs(T.REGIONS) do
            local name = regionName(region)
            cornerRow(b, page, "t_l_" .. layer .. region, name, format(L.HDR_TOUCH_LAYER, layerName(layer)),
                function() return T.LayerAction(region, layer) end,
                function(a) T.SetLayerAction(region, layer, a) end,
                { indent = true, disabled = T.IsOff(region),
                  preview = function(c)
                      local m = {}
                      for _, r in ipairs(T.REGIONS) do m[r] = T.LayerAction(r, layer) end
                      CK.ConfigKit.Preview.Touch(c, m, region, format(L.HDR_TOUCH_LAYER, layerName(layer)))
                  end })
        end
    end
end

-- The mouse mode: its button learned (the mic button...), the chat's word
local function mouseRows(b)
    local t = s()
    b.header(L.SEC_TOUCH_MOUSE)
    b.info(L.TOUCH_MOUSE_INFO)
    b.value({ id = "t_mkey", label = L.LBL_TOUCH_MOUSE_KEY, tip = L.TIP_TOUCH_MOUSE_KEY, verb = L.V_KEY,
        text = function()
            if T.learning then return L.TOUCH_MOUSE_KEY_WAIT end
            return t.mouseKey and (CK.Mapping.KeyLabel(t.mouseKey) or t.mouseKey) or L.TOUCH_MOUSE_KEY_NONE
        end,
        onA = function()
            T.learning = true
            T:LearnMouseKey(function()
                T.learning = nil
                Config:Render()
            end)
        end,
        onX = function() T:ForgetMouseKey() end, xVerb = L.V_REMOVE })
    b.check({ id = "t_msay", label = L.LBL_TOUCH_MOUSE_SAY, tip = L.TIP_TOUCH_MOUSE_SAY,
        get = function() return t.mouseSay end, set = function(v) t.mouseSay = v end })
    if not T.MouseSupported() then b.info(L.TOUCH_MOUSE_NO_CLICK) end
    b.check({ id = "t_mdt", label = L.LBL_TOUCH_DOUBLE_RIGHT, tip = L.TIP_TOUCH_DOUBLE_RIGHT,
        disabled = not T.MouseSupported(),
        get = function() return t.doubleTapRight == true end, set = function(v) T.SetDoubleTap(v) end })
end

-- The corners on screen
local function overlayRows(b)
    local t = s()
    local O = CK.TouchOverlay
    b.header(L.SEC_TOUCH_OVERLAY)
    b.check({ id = "t_ov", label = L.LBL_TOUCH_OVERLAY, tip = L.TIP_TOUCH_OVERLAY,
        get = function() return t.overlay end,
        set = function(v)
            t.overlay = v
            O:Refresh()
        end })
    local off = not t.overlay
    b.check({ id = "t_ovbags", label = L.LBL_TOUCH_OVERLAY_BAGS, indent = true, disabled = off,
        tip = L.TIP_TOUCH_OVERLAY_BAGS,
        get = function() return t.overlayBags end,
        set = function(v)
            t.overlayBags = v
            O:Refresh()
        end })
    b.slider({ id = "t_ovx", label = L.LBL_TOUCH_OVERLAY_X, indent = true, disabled = off, tip = L.TIP_TOUCH_OVERLAY_POS,
        min = -900, max = 900, stepSize = 10, get = function() return t.overlayX end,
        set = function(v)
            t.overlayX = v
            O:Refresh()
        end })
    b.slider({ id = "t_ovy", label = L.LBL_TOUCH_OVERLAY_Y, indent = true, disabled = off, tip = L.TIP_TOUCH_OVERLAY_POS,
        min = 0, max = 1000, stepSize = 10, get = function() return t.overlayY end,
        set = function(v)
            t.overlayY = v
            O:Refresh()
        end })
    b.slider({ id = "t_ovs", label = L.LBL_TOUCH_OVERLAY_SCALE, indent = true, disabled = off, tip = L.TIP_TOUCH_OVERLAY_POS,
        min = 0.5, max = 2, stepSize = 0.1, fmt = function(v) return format("%d%%", v * 100 + 0.5) end,
        get = function() return t.overlayScale end,
        set = function(v)
            t.overlayScale = v
            O:Refresh()
        end })
end

local function lightRows(b)
    local t = s()
    b.header(L.SEC_TOUCH_LIGHT)
    if not T.LightSupported() then
        b.info(L.TOUCH_LIGHT_NONE)
        return
    end
    b.choice({ id = "t_light", preview = function(c) CK.ConfigKit.Preview.Light(c) end, label = L.TOUCH_LIGHT, tip = L.TIP_TOUCH_LIGHT,
        text = function() return L["TOUCH_LIGHT_" .. (t.light or "off"):upper()] end,
        step = function(d)
            local modes, i = T.LightModes(), 1
            for n, m in ipairs(modes) do
                if m == t.light then i = n end
            end
            T:SetLight(modes[(i - 1 + d) % #modes + 1])
        end })
    b.button({ id = "t_lprobe", label = L.LBL_TOUCH_LIGHT_PROBE, tip = L.TIP_TOUCH_LIGHT_PROBE, verb = L.V_TEST,
        func = function() T:LightProbe() end })
    b.info(L.TOUCH_LIGHT_INFO)
    if T.HealthHidden() then b.info(L.TOUCH_LIGHT_NO_HEALTH) end
    -- Fork CoolerMgdn: notifications, each event on or off
    b.check({ id = "t_lnotify", label = L.LBL_TOUCH_NOTIFY, tip = L.TIP_TOUCH_NOTIFY,
        disabled = not T.LightSupported(),
        get = function() return t.lightNotify == true end,
        set = function(v) t.lightNotify = v and true or false end })
    for _, key in ipairs(T.NOTIFY_KEYS) do
        b.check({ id = "t_ln_" .. key, label = L["TOUCH_NOTIFY_" .. key:upper()], indent = true,
            tip = L.TIP_TOUCH_NOTIFY_EVENT, disabled = not (T.LightSupported() and t.lightNotify),
            get = function() return not (t.notifyOff and t.notifyOff[key]) end,
            set = function(v)
                t.notifyOff = t.notifyOff or {}
                t.notifyOff[key] = (not v) or nil
                if v then T.flashing = nil; T:Notify(key) end
            end })
    end
end

Config.pages.touchpad = Config.NewRailPage({
    key = "touchpad",
    sections = {
        { key = "general", label = L.SEC_TOUCH, tip = L.TIP_SEC_TOUCH, rows = generalRows },
        { key = "corners", label = L.SEC_TOUCH_CORNERS, tip = L.TIP_SEC_TOUCH_CORNERS, rows = cornerRows },
        { key = "layers", label = L.SEC_TOUCH_LAYERS, tip = L.TOUCH_LAYERS_INFO, rows = layerRows },
        { key = "mouse", label = L.SEC_TOUCH_MOUSE, tip = L.TOUCH_MOUSE_INFO, rows = mouseRows },
        { key = "overlay", label = L.SEC_TOUCH_OVERLAY, tip = L.TIP_TOUCH_OVERLAY, rows = overlayRows },
        { key = "light", label = L.SEC_TOUCH_LIGHT, tip = L.TIP_TOUCH_LIGHT, rows = lightRows },
    },
})
