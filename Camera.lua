local _, CK = ...
local L = CK.L

---------------------------------------------------------------------------
-- Fork CoolerMgdn: camera views (the idea and the settings: ControllerForever's
-- Camera.lua, its author's code free to reuse; DynamicCam's shoulder views).
--   game    the game's own (nothing touched)
--   right   over the right shoulder
--   left    over the left shoulder
--   action  over the shoulder, the view tilting with what's ahead
-- The game's own ActionCam settings (test_camera...). With the gamepad the
-- game keeps "Keep Character Centered" on, which cancels any shoulder
-- offset: a view turns it off on the game's temporary layer (the gamepad's
-- own), again whenever the gamepad comes back. Indoors (an option, on): the
-- game's own camera, the shoulder view bumped into walls. The first time a
-- test_ setting changes, the game asks about its experimental features:
-- Accept keeps them (Disable puts them all back).
-- Settings change only when the view, an option, the gamepad or indoors /
-- outdoors changes (never on a window opening: those were suspected of
-- taint before).
---------------------------------------------------------------------------
local Cam = {}
CK.Camera = Cam

Cam.VIEWS = { "game", "right", "left", "action" }
Cam.SHOULDERS = { "small", "medium", "large", "huge" }
Cam.SHOULDER = { small = 0.8, medium = 1.2, large = 2.0, huge = 3.0 }
local TEMP = { CameraKeepCharacterCentered = true, CameraReduceUnexpectedMovement = true }
local TOUCHED = { "test_cameraOverShoulder", "test_cameraDynamicPitch", "test_cameraHeadMovementStrength",
    "test_cameraTargetFocusEnemyEnable" }

local function settings()
    local s = CK.db.settings
    if type(s.camera) ~= "table" then s.camera = {} end
    local c = s.camera
    if c.view == nil then c.view = "game" end
    if c.shoulder == nil then c.shoulder = "medium" end
    if c.indoorsCalm == nil then c.indoorsCalm = true end
    return c
end
Cam.Settings = settings

local function getCVar(name)
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    local ok, v = pcall(get, name)
    return ok and v or nil
end

local function setCVar(name, value)
    if getCVar(name) == value then return end
    if TEMP[name] and C_CVar and C_CVar.SetTempCVar then
        if pcall(C_CVar.SetTempCVar, name, value) then return end
    end
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    pcall(set, name, value)
end

local function indoors()
    return IsIndoors and IsIndoors() and true or false
end

-- What the view sets
function Cam:Plan()
    local c = settings()
    local view = c.view
    local plan = {}
    if view == "game" then
        -- Given back once (what the view had changed), then left alone
        if not c.changed then return nil end
        plan.test_cameraOverShoulder = "0"
        plan.test_cameraDynamicPitch = "0"
        plan.test_cameraHeadMovementStrength = "0"
        plan.test_cameraTargetFocusEnemyEnable = "0"
        plan.CameraKeepCharacterCentered = "1"
        return plan
    end
    local calm = c.indoorsCalm and indoors()
    self.wasIndoors = calm
    local d = Cam.SHOULDER[c.shoulder] or 1.2
    plan.test_cameraOverShoulder = calm and "0" or format("%.1f", (view == "left" and -1 or 1) * d)
    plan.test_cameraDynamicPitch = (view == "action" and not calm) and "1" or "0"
    plan.test_cameraHeadMovementStrength = (c.headMove and not calm) and "1" or "0"
    plan.test_cameraTargetFocusEnemyEnable = (c.targetFocus and not calm) and "1" or "0"
    plan.CameraKeepCharacterCentered = calm and "1" or "0"
    plan.CameraReduceUnexpectedMovement = "0"
    return plan
end

function Cam:Apply()
    if not CK.db then return end
    local plan = self:Plan()
    if not plan then return end
    for name, value in pairs(plan) do setCVar(name, value) end
    local c = settings()
    c.changed = c.view ~= "game" or nil
    if CK.Flight then CK.Flight:Note("camera: %s%s", c.view, self.wasIndoors and " (indoors, calm)" or "") end
end

function Cam:SetView(view)
    settings().view = view
    self:Apply()
end

function Cam:Step(key, list, d)
    local c = settings()
    local at = 1
    for i, v in ipairs(list) do if v == c[key] then at = i end end
    c[key] = list[(at - 1 + d) % #list + 1]
    self:Apply()
end

function Cam:Name(view)
    return L["CAM_" .. view:upper()] or view
end

-- Indoors / outdoors: the calm view on or off
function Cam:CheckIndoors()
    local c = settings()
    if c.view == "game" or not c.indoorsCalm then return end
    if indoors() ~= (self.wasIndoors and true or false) then self:Apply() end
end

local f = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "GAME_PAD_ACTIVE_CHANGED", "ZONE_CHANGED_INDOORS",
    "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA" }) do
    pcall(f.RegisterEvent, f, event)
end
f:SetScript("OnEvent", function(_, event)
    if not CK.db then return end
    if event == "PLAYER_ENTERING_WORLD" or event == "GAME_PAD_ACTIVE_CHANGED" then
        -- (the gamepad puts its own Keep Character Centered back: after it)
        C_Timer.After(1, function() Cam:Apply() end)
    else
        Cam:CheckIndoors()
    end
end)
-- Caves and buildings without a zone event: a light look every 2 s, only
-- with a view on
C_Timer.NewTicker(2, function()
    if CK.db and settings().view ~= "game" then Cam:CheckIndoors() end
end)

-- Home > Gamepad (MapWindow.lua's rows)
function Cam.Rows(b)
    local c = settings()
    b.header(L.HDR_CAMERA)
    b.choice({ id = "cam_view", label = L.LBL_CAM_VIEW, tip = L.TIP_CAM_VIEW,
        text = function() return Cam:Name(settings().view) end,
        step = function(d) Cam:Step("view", Cam.VIEWS, d) end })
    b.choice({ id = "cam_shoulder", label = L.LBL_CAM_SHOULDER, indent = true, disabled = c.view == "game",
        tip = L.TIP_CAM_SHOULDER,
        text = function() return L["CAM_SH_" .. settings().shoulder:upper()] end,
        step = function(d) Cam:Step("shoulder", Cam.SHOULDERS, d) end })
    b.check({ id = "cam_head", label = L.LBL_CAM_HEAD, indent = true, disabled = c.view == "game", tip = L.TIP_CAM_HEAD,
        get = function() return settings().headMove == true end,
        set = function(v) settings().headMove = v; Cam:Apply() end })
    b.check({ id = "cam_focus", label = L.LBL_CAM_FOCUS, indent = true, disabled = c.view == "game", tip = L.TIP_CAM_FOCUS,
        get = function() return settings().targetFocus == true end,
        set = function(v) settings().targetFocus = v; Cam:Apply() end })
    b.check({ id = "cam_indoors", label = L.LBL_CAM_INDOORS, indent = true, disabled = c.view == "game", tip = L.TIP_CAM_INDOORS,
        get = function() return settings().indoorsCalm ~= false end,
        set = function(v) settings().indoorsCalm = v; Cam:Apply() end })
end
