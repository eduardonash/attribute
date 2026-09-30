--[[
    ===================================================================
    ATTRIBUTE // MULTICREW TANK COMBAT — PROJECTILE BALLISTICS & AUTO-LEAD
    Target: Multicrew Tank Combat (Place: 95721658376580)
    Engine: Roblox Luau (Executor Context 8)
    ===================================================================
]]

if _G.AutoLeadAssistUnload then
    pcall(_G.AutoLeadAssistUnload)
end

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lp = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- The settings menu belongs to VibeUI; this ScreenGui only owns the small
-- bottom-left impact readout. Clear overlays from older script versions too.
for _, guiName in ipairs({ "AutoLeadSettingsUI", "AutoLeadOverlay", "AttributeTankOverlay", "AttributeShellFocusOverlay" }) do
    local prev = lp:WaitForChild("PlayerGui"):FindFirstChild(guiName)
    if prev then prev:Destroy() end
    local prevCg = game:GetService("CoreGui"):FindFirstChild(guiName)
    if prevCg then prevCg:Destroy() end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoLeadOverlay"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 999999

-- Render callbacks must not write labels beneath protected CoreGui/gethui
-- containers. Keep this ordinary gameplay overlay accessible in PlayerGui.
screenGui.Parent = lp:WaitForChild("PlayerGui")

local THEME = {
    Background = Color3.fromRGB(20, 22, 26),
    CardBg = Color3.fromRGB(28, 30, 36),
    Border = Color3.fromRGB(45, 48, 57),
    TextPrimary = Color3.fromRGB(241, 242, 246),
    TextSecondary = Color3.fromRGB(144, 149, 164),
    TextHeader = Color3.fromRGB(155, 161, 176),
    ToggleActive = Color3.fromRGB(135, 110, 255),
    ToggleInactive = Color3.fromRGB(48, 51, 60),
    Knob = Color3.fromRGB(255, 255, 255),
    SliderTrack = Color3.fromRGB(38, 41, 50),
    SliderFill = Color3.fromRGB(135, 110, 255),
    TrajectoryBore = Color3.fromRGB(155, 48, 255),  -- Purple for true barrel bore arc
    TrajectoryLead = Color3.fromRGB(0, 230, 118),   -- Neon green for auto-lead curve
    ImpactMarkerBore = Color3.fromRGB(200, 80, 255),
    ImpactMarkerLead = Color3.fromRGB(0, 255, 130),
    BlastClear = Color3.fromRGB(65, 210, 255),
    BlastOccupied = Color3.fromRGB(70, 235, 165),
    BlastBlocked = Color3.fromRGB(255, 90, 125),
    FlightStart = Color3.fromRGB(65, 225, 255),
    FlightEnd = Color3.fromRGB(177, 135, 255),
    PathPending = Color3.fromRGB(82, 95, 121),
    Ink = Color3.fromRGB(12, 16, 26)
}

local function stylePanel(panel)
    panel.BackgroundTransparency = 1
    panel.BorderSizePixel = 0
    for _, child in ipairs(panel:GetChildren()) do
        if child:IsA("UIStroke") or child:IsA("UIGradient") or child:IsA("UICorner") then child:Destroy() end
    end
    if panel:IsA("TextLabel") then
        -- A faint backing improves readability without restoring opaque cards.
        panel.BackgroundColor3 = THEME.Ink
        panel.BackgroundTransparency = 0.72
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 4)
        corner.Parent = panel
        panel.TextColor3 = Color3.fromRGB(245, 248, 255)
        panel.TextStrokeColor3 = THEME.Ink
        panel.TextStrokeTransparency = 0.15
    end
end

local rememberedSettings = _G.AutoLeadAssistRemembered or {}
local function normalizeFocusKey(value)
    local text = tostring(value)
    local name = text:match("Enum%.KeyCode%.([%w_]+)$")
    if name and name ~= "Unknown" and name ~= "Backspace" then
        local ok,key=pcall(function() return Enum.KeyCode[name] end)
        if ok then return key end
    end
    name = text:match("Enum%.UserInputType%.(MouseButton[123])$")
    if name then return Enum.UserInputType[name] end
    return nil
end
local adaptiveAim = rememberedSettings.AdaptiveAim
if adaptiveAim == nil then
    adaptiveAim = rememberedSettings.AutoLead ~= false or rememberedSettings.AutoBallistic == true
end
local Settings = {
    EnableAutoLead = true,
    ShowBallistic = false,
    ExplosionRadius = true,
    ShowDistance = true,
    FlightTimer = true,
    OwnShellHighlight = rememberedSettings.OwnShellHighlight ~= false,
    ShotProgress = rememberedSettings.ShotProgress ~= false,
    ShotStatus = rememberedSettings.ShotStatus ~= false,
    Trajectory = true,
    AdaptiveAim = adaptiveAim == true,
    ShellRedirection = rememberedSettings.ShellRedirection == true,
    ShellFocusKey = normalizeFocusKey(rememberedSettings.ShellFocusKey) or Enum.UserInputType.MouseButton2,
    ShellVisibilityCheck = rememberedSettings.ShellVisibilityCheck == true,
    ShellFocusRadius = math.clamp(tonumber(rememberedSettings.ShellFocusRadius) or 60, 5, 250),
    ShellFocusCircle = rememberedSettings.ShellFocusCircle ~= false,
    ShellFocusTracer = rememberedSettings.ShellFocusTracer ~= false,
    ShellFocusHighlight = rememberedSettings.ShellFocusHighlight ~= false,
    ShellFocusColor = typeof(rememberedSettings.ShellFocusColor) == "Color3" and rememberedSettings.ShellFocusColor
        or Color3.fromRGB(255, 209, 90),
    ArtilleryAutoLay = rememberedSettings.ArtilleryAutoLay ~= false,
    InfiniteAmmo = rememberedSettings.InfiniteAmmo == true,
    TurretSpeedEnabled = rememberedSettings.TurretSpeedEnabled == true,
    TurretSpeedMultiplier = math.clamp(tonumber(rememberedSettings.TurretSpeedMultiplier) or 1, 0.25, 3),
    TankRapidFire = rememberedSettings.TankRapidFire == true,
    RapidFireMultiplier = math.clamp(tonumber(rememberedSettings.RapidFireMultiplier) or 2, 1, 5),
    StaffNotifications = rememberedSettings.StaffNotifications ~= false,
    CreatorNotifications = rememberedSettings.CreatorNotifications ~= false,
    EnemyTankESP = rememberedSettings.EnemyTankESP ~= false,
    TankBoxes = false,
    TankNames = false,
    TankClass = false,
    TankDistance = false,
    TankDistanceFade = true,
    HelicopterESP = false,
    TankOccupiedOnly = false,
    TankTeamCheck = true,
    ModuleOutline = false,
    ModuleLineThickness = math.floor(math.clamp(tonumber(rememberedSettings.ModuleLineThickness) or 1, 1, 5) + 0.5),
    ModuleFilled = false,
    ModuleEngine = true,
    ModuleAmmo = true,
    ModuleDistance = 400,
    ModuleEngineColor = Color3.fromRGB(224, 224, 85),
    ModuleAmmoColor = Color3.fromRGB(238, 238, 245),
    NoGrass = false,
    NoTrees = false,
    ZeroEnemyArmor = rememberedSettings.ZeroEnemyArmor ~= false,
    PlayerESP = rememberedSettings.PlayerESP ~= false,
    ESPBoxes = rememberedSettings.ESPBoxes ~= false,
    ESPNames = rememberedSettings.ESPNames ~= false,
    ESPHealth = rememberedSettings.ESPHealth ~= false,
    ESPColorIndex = math.floor(math.clamp(tonumber(rememberedSettings.ESPColorIndex) or 1, 1, 4)),
    ESPMaxDistance = math.clamp(tonumber(rememberedSettings.ESPMaxDistance) or 4400, 0, 50000),
    AimSource = "Mouse",
    Freecam = false,
    FreecamClickTP = false, -- Always opt in after loading; never teleport a seated character.
    DisableFiringShake = rememberedSettings.DisableFiringShake ~= false,
    DisableExplosionShake = rememberedSettings.DisableExplosionShake ~= false,
    FreecamSpeed = math.clamp(tonumber(rememberedSettings.FreecamSpeed) or 3.5, 0.5, 20),
    FreecamKey = rememberedSettings.FreecamKey or Enum.KeyCode.V,
    Zoom = false,
    ZoomFOV = math.clamp(tonumber(rememberedSettings.ZoomFOV) or 25, 10, 70),
    ZoomKey = rememberedSettings.ZoomKey or Enum.KeyCode.Z
}
_G.AutoLeadAssistRemembered = Settings
local function isAdaptiveAimActive()
    return Settings.EnableAutoLead and Settings.AdaptiveAim and not Settings.ShellRedirection
end

-- Suppress only the visual muzzle-recoil presets. Explosion effects, physical
-- recoil, firing logic and camera navigation remain owned by the game.
local firingShake = { originals = {}, keys = { "RecoilShake", "RecoilShake2", "RecoilShake3" } }
function firingShake.restore()
    if firingShake.presets then
        for key, value in pairs(firingShake.originals) do
            -- Do not overwrite a later change made by another owner.
            if firingShake.presets[key] == 0 then firingShake.presets[key] = value end
        end
    end
    firingShake.originals = {}
    firingShake.active = false
end
function firingShake.set(enabled)
    Settings.DisableFiringShake = enabled == true
    firingShake.restore()
    firingShake.error = nil
    if not Settings.DisableFiringShake then return end
    local ok, err = pcall(function()
        local modules = ReplicatedStorage:FindFirstChild("TankModules")
        local module = modules and modules:FindFirstChild("vfxHandler")
        assert(module, "Firing shake module unavailable")
        local presets = require(module).CamShakerPresets
        assert(type(presets) == "table", "Firing shake presets unavailable")
        firingShake.presets = presets
        for _, key in ipairs(firingShake.keys) do
            assert(type(presets[key]) == "number", "Unknown firing shake preset: " .. key)
        end
        for _, key in ipairs(firingShake.keys) do
            firingShake.originals[key] = presets[key]
            presets[key] = 0
        end
        firingShake.active = true
    end)
    if not ok then
        firingShake.restore()
        firingShake.error = tostring(err)
        warn("[AutoLead] Firing shake suppression unavailable: " .. tostring(err))
    end
end
firingShake.set(Settings.DisableFiringShake)

function firingShake.restoreExplosions()
    local control = firingShake.explosions
    if not control then return end
    control.enabled = false
    if control.module.ShakeCam == control.shake then control.module.ShakeCam = control.originalShake end
    if control.module.ShakeCamFromMass == control.mass then control.module.ShakeCamFromMass = control.originalMass end
    firingShake.explosions = nil
end
function firingShake.setExplosions(enabled)
    Settings.DisableExplosionShake = enabled == true
    firingShake.restoreExplosions()
    firingShake.explosionError = nil
    if not Settings.DisableExplosionShake then return end
    local ok, err = pcall(function()
        local modules = ReplicatedStorage:FindFirstChild("TankModules")
        local module = modules and modules:FindFirstChild("vfxHandler")
        assert(module, "Explosion shake module unavailable")
        local vfx = require(module)
        assert(type(vfx.ShakeCam) == "function" and type(vfx.ShakeCamFromMass) == "function",
            "Explosion shake functions unavailable")
        local control = { module = vfx, enabled = true,
            originalShake = vfx.ShakeCam, originalMass = vfx.ShakeCamFromMass }
        control.shake = function(preset, ...)
            if control.enabled and (preset == nil or preset == "Explosion" or preset == "SmallExplosion") then return end
            return control.originalShake(preset, ...)
        end
        -- Shell impacts and flybys share this visual-only helper. Suppress
        -- scheduling new shake impulses, not explosion particles or damage.
        control.mass = function(...)
            if control.enabled then return end
            return control.originalMass(...)
        end
        firingShake.explosions = control
        vfx.ShakeCam, vfx.ShakeCamFromMass = control.shake, control.mass
    end)
    if not ok then
        firingShake.restoreExplosions()
        firingShake.explosionError = tostring(err)
        warn("[AutoLead] Explosion shake suppression unavailable: " .. tostring(err))
    end
end
firingShake.setExplosions(Settings.DisableExplosionShake)

-- The active visualizer applies spring rotation after source-level effects.
-- With both categories disabled, also neutralize delayed/uncategorized impulses
-- at this one presentation callback. Never freeze the camera or disable input.
function firingShake.restoreSink()
    local sink = firingShake.sink
    if sink then
        sink.enabled = false
        if sink.owner.RSFunction == sink.callback then sink.owner.RSFunction = sink.original end
    end
    firingShake.sink = nil
end
function firingShake.attachSink(owner)
    firingShake.restoreSink()
    local sink = { owner = owner, original = owner.RSFunction, enabled = true }
    sink.callback = function(offset)
        if sink.enabled and Settings.DisableFiringShake and Settings.DisableExplosionShake then
            local ok, err = pcall(function()
                owner.mainSpring.Target = Vector3.zero
                owner.mainSpring.Position = Vector3.zero
                owner.mainSpring.Velocity = Vector3.zero
            end)
            if not ok then
                firingShake.sinkError = tostring(err)
                sink.enabled = false -- Fail once, not every render frame.
            else
                offset = Vector3.zero
            end
        end
        return sink.original(offset)
    end
    owner.RSFunction = sink.callback
    firingShake.sink = sink
end
function firingShake.refreshSink()
    if os.clock() < (firingShake.nextCheck or 0) then return end
    firingShake.nextCheck = os.clock() + 2
    if not (Settings.DisableFiringShake and Settings.DisableExplosionShake) then return end
    local scripts = lp:FindFirstChild("PlayerScripts")
    local visualizer = scripts and scripts:FindFirstChild("ClientVisualizer")
    if firingShake.sink and firingShake.visualizer == visualizer then return end
    if not visualizer or not getconnections or not debug.getupvalues then return end
    local event = visualizer:FindFirstChild("shake")
    if not event or not event:IsA("BindableEvent") then return end
    local ok, err = pcall(function()
        local module = require(ReplicatedStorage.TankModules.vfxHandler)
        for _, connection in ipairs(getconnections(event.Event)) do
            if connection.Function then
                for _, value in pairs(debug.getupvalues(connection.Function)) do
                    if type(value) == "table" and getmetatable(value) == module.camShaker
                        and type(rawget(value, "RSFunction")) == "function"
                        and type(rawget(value, "mainSpring")) == "table" then
                        firingShake.attachSink(value)
                        firingShake.visualizer = visualizer
                        return
                    end
                end
            end
        end
    end)
    if not ok then firingShake.sinkError = tostring(err) end
end

local ESP_COLORS = {
    { name = "RED", color = Color3.fromRGB(255, 90, 125) },
    { name = "CYAN", color =Color3.fromRGB(65, 210, 255) },
    { name = "YELLOW", color = Color3.fromRGB(255, 209, 115) },
    { name = "PURPLE", color = Color3.fromRGB(177, 135, 255) }
}

local function getESPColor()
    return ESP_COLORS[Settings.ESPColorIndex].color
end

-- ===================================================================
-- FREECAM & INPUT ISOLATION CONTROLLER
-- ===================================================================

local ContextActionService = game:GetService("ContextActionService")
local FREECAM_ACTION_NAME = "AutoLeadFreecamSinkAction"
local FREECAM_RENDER_NAME = "AutoLeadFreecamLateStep"
local ZOOM_RENDER_NAME = "AutoLeadZoomLateStep"
local FREECAM_PRIORITY = 2000000

local freecamActive = false
local freecamCFrame = CFrame.new()
local freecamRotX = 0 -- Yaw (radians)
local freecamRotY = 0 -- Pitch (radians)
local freecamTargetRotX = 0
local freecamTargetRotY = 0
local freecamVelocity = Vector3.new()
local originalCamType = workspace.CurrentCamera and workspace.CurrentCamera.CameraType or Enum.CameraType.Custom
local originalSubject = workspace.CurrentCamera and workspace.CurrentCamera.CameraSubject or nil
local zoomCamera = nil
local originalZoomFOV = nil
local zoomState = { base = nil, applied = nil }

function zoomState.restore(cam)
    if not cam or cam ~= zoomState.owner or not zoomState.base then return end
    -- The late lens is presentation-only. Restore its saved input before the
    -- next input/camera update, never infer ownership from changing angles.
    cam.CFrame = zoomState.base
    if zoomState.sourceFOV then cam.FieldOfView = zoomState.sourceFOV end
    zoomState.base, zoomState.applied, zoomState.owner, zoomState.sourceFOV = nil, nil, nil, nil
end

function zoomState.lensRotation(wideRay, narrowRay)
    -- Shortest rotation maps the narrow cursor ray onto the wide cursor ray
    -- without the extra roll of multiplying two world-up lookAt frames.
    local axis = narrowRay:Cross(wideRay)
    local sine = axis.Magnitude
    if sine < 1e-7 then return CFrame.identity end
    return CFrame.fromAxisAngle(axis / sine, math.atan2(sine, math.clamp(narrowRay:Dot(wideRay), -1, 1)))
end

local function setZoom(enabled)
    zoomState.restore(zoomCamera)
    Settings.Zoom = enabled == true
    pcall(function() RunService:UnbindFromRenderStep(ZOOM_RENDER_NAME) end)
    pcall(function() RunService:UnbindFromRenderStep(ZOOM_RENDER_NAME .. "Restore") end)
    if not Settings.Zoom then
        if zoomCamera and originalZoomFOV then
            pcall(function()
                zoomCamera.FieldOfView = originalZoomFOV
                zoomState.restore(zoomCamera)
            end)
        end
        zoomCamera, originalZoomFOV = nil, nil
        zoomState.base, zoomState.applied = nil, nil
        return
    end
    -- Remove our previous lens transform before the game's camera runs. This
    -- prevents cursor-follow rotation accumulating on itself outside freecam.
    RunService:BindToRenderStep(ZOOM_RENDER_NAME .. "Restore", Enum.RenderPriority.First.Value - 1, function()
        if zoomCamera and zoomCamera == workspace.CurrentCamera then
            zoomState.restore(zoomCamera)
        end
    end)
    RunService:BindToRenderStep(ZOOM_RENDER_NAME, FREECAM_PRIORITY + 1, function()
        local cam = workspace.CurrentCamera
        if not cam then return end
        if cam ~= zoomCamera then
            if zoomCamera and originalZoomFOV then
                pcall(function()
                    zoomState.restore(zoomCamera)
                    zoomCamera.FieldOfView = originalZoomFOV
                end)
            end
            zoomCamera = cam
            originalZoomFOV = cam.FieldOfView
        end
        local base = freecamActive and freecamCFrame or cam.CFrame
        -- Camera controllers can legitimately change FOV while moving/seating.
        originalZoomFOV = cam.FieldOfView
        local mouse = UserInputService:GetMouseLocation()
        local viewport = cam.ViewportSize
        if viewport.X < 1 or viewport.Y < 1 then return end
        mouse = Vector2.new(math.clamp(mouse.X, 0, viewport.X), math.clamp(mouse.Y, 0, viewport.Y))
        -- Use engine projection for aspect ratio/FOV mode, with viewport pixels.
        cam.CFrame = base
        cam.FieldOfView = originalZoomFOV
        local wideRay = base:VectorToObjectSpace(cam:ViewportPointToRay(mouse.X, mouse.Y).Direction)
        cam.FieldOfView = Settings.ZoomFOV
        local narrowRay = base:VectorToObjectSpace(cam:ViewportPointToRay(mouse.X, mouse.Y).Direction)
        -- Zoom around the cursor: the point under it stays under it while the
        -- magnified view follows its position across the original viewport.
        zoomState.base = base
        zoomState.owner, zoomState.sourceFOV = cam, originalZoomFOV
        zoomState.applied = (base * zoomState.lensRotation(wideRay, narrowRay)):Orthonormalize()
        cam.CFrame = zoomState.applied
        cam.FieldOfView = Settings.ZoomFOV
    end)
end

-- Restore the original flight controls. These keys are isolated from the
-- vehicle while freecam is on; switch freecam off to drive normally.
local SINK_KEYS = {
    Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
    Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.Space, Enum.KeyCode.LeftControl,
    Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Up, Enum.KeyCode.Down
}

local lastStreamRequestPos = nil
local lastStreamRequestTime = 0
local streamRequestPending = false

local function requestFreecamStream(position)
    local now = os.clock()
    if streamRequestPending or (now - lastStreamRequestTime < 2.5) then return end
    if lastStreamRequestPos and (position - lastStreamRequestPos).Magnitude < 128 then return end
    lastStreamRequestTime = now
    lastStreamRequestPos = position
    streamRequestPending = true
    task.spawn(function()
        -- Roblox still decides what is available to stream. This is a best-
        -- effort request for the camera area, not a permanent replication focus.
        pcall(function() lp:RequestStreamAroundAsync(position, 2) end)
        streamRequestPending = false
    end)
end

local function freecamSinkCallback(actionName, inputState, inputObject)
    return Enum.ContextActionResult.Sink
end

local triggerDirectFire = nil -- Assigned below after weapon hooks are ready

local function freecamMouseLookAllowed()
    -- A focus hold must not also warp the cursor or rotate the view. Arrow-key
    -- look remains available; choosing a keyboard focus key restores RMB look.
    local focusOwnsRMB = Settings.ShellRedirection
        and Settings.ShellFocusKey == Enum.UserInputType.MouseButton2
    return not focusOwnsRMB and UserInputService:GetFocusedTextBox() == nil
        and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
end

local function setFreecam(enabled)
    local cam = workspace.CurrentCamera
    if not cam then return end

    if enabled then
        if freecamActive then return end
        freecamActive = true
        originalCamType = cam.CameraType
        originalSubject = cam.CameraSubject

        if Settings.Zoom then zoomState.restore(cam) end
        freecamCFrame = cam.CFrame
        local rx, ry, _ = freecamCFrame:ToOrientation()
        freecamRotY = rx
        freecamRotX = ry
        freecamTargetRotY = rx
        freecamTargetRotX = ry
        freecamVelocity = Vector3.new()

        cam.CameraType = Enum.CameraType.Scriptable
        lastStreamRequestPos = nil
        lastStreamRequestTime = 0
        requestFreecamStream(freecamCFrame.Position)

        -- Absorb flight keys so driver/chassis controls do not also respond.
        pcall(function()
            ContextActionService:BindActionAtPriority(
                FREECAM_ACTION_NAME,
                freecamSinkCallback,
                false,
                FREECAM_PRIORITY,
                table.unpack(SINK_KEYS)
            )
        end)

        -- Run after every normal camera/occlusion controller so terrain and
        -- vehicle camera scripts cannot clamp or overwrite the freecam CFrame.
        pcall(function()
            RunService:UnbindFromRenderStep(FREECAM_RENDER_NAME)
        end)

        RunService:BindToRenderStep(FREECAM_RENDER_NAME, FREECAM_PRIORITY, function(dt)
            if not Settings.Freecam or not freecamActive then return end

            -- MTC can replace CurrentCamera during a seat change.
            cam = workspace.CurrentCamera or cam
            cam.CameraType = Enum.CameraType.Scriptable

            -- RMB belongs either to focus or camera look, never both.
            local looking = freecamMouseLookAllowed()
            local desiredMouseBehavior = looking and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
            if UserInputService.MouseBehavior ~= desiredMouseBehavior then
                UserInputService.MouseBehavior = desiredMouseBehavior
            end
            if looking then
                local delta = UserInputService:GetMouseDelta()
                freecamTargetRotX = freecamTargetRotX - delta.X * 0.003
                freecamTargetRotY = math.clamp(freecamTargetRotY - delta.Y * 0.003, -math.rad(89), math.rad(89))
            end
            -- Arrow keys provide a fallback if another MTC control captures RMB.
            local turnRate = 1.8 * math.min(dt, 0.1)
            if UserInputService:IsKeyDown(Enum.KeyCode.Left) then freecamTargetRotX = freecamTargetRotX + turnRate end
            if UserInputService:IsKeyDown(Enum.KeyCode.Right) then freecamTargetRotX = freecamTargetRotX - turnRate end
            if UserInputService:IsKeyDown(Enum.KeyCode.Up) then freecamTargetRotY = math.clamp(freecamTargetRotY + turnRate, -math.rad(89), math.rad(89)) end
            if UserInputService:IsKeyDown(Enum.KeyCode.Down) then freecamTargetRotY = math.clamp(freecamTargetRotY - turnRate, -math.rad(89), math.rad(89)) end

            local baseSpeed = (Settings.FreecamSpeed or 3.5) * 60
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
                baseSpeed = baseSpeed * 2.5
            elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) then
                baseSpeed = baseSpeed * 0.3
            end
            local fwd = 0
            local right = 0
            local up = 0

            if UserInputService:IsKeyDown(Enum.KeyCode.W) then fwd = fwd + 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then fwd = fwd - 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then right = right + 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then right = right - 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.E) or UserInputService:IsKeyDown(Enum.KeyCode.Space) then up = up + 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.Q) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then up = up - 1 end

            local smoothing = 1 - math.exp(-12 * math.min(dt, 0.1))
            freecamRotX = freecamRotX + (freecamTargetRotX - freecamRotX) * smoothing
            freecamRotY = freecamRotY + (freecamTargetRotY - freecamRotY) * smoothing

            local rotCFrame = CFrame.Angles(0, freecamRotX, 0) * CFrame.Angles(freecamRotY, 0, 0)
            local moveInput = rotCFrame.LookVector * fwd + rotCFrame.RightVector * right + Vector3.new(0, 1, 0) * up
            if moveInput.Magnitude > 1 then
                moveInput = moveInput.Unit
            end
            local targetVelocity = moveInput * baseSpeed
            freecamVelocity = freecamVelocity:Lerp(targetVelocity, smoothing)
            local moveDelta = freecamVelocity * dt
            local newPos = freecamCFrame.Position + moveDelta

            freecamCFrame = CFrame.new(newPos) * rotCFrame
            cam.CFrame = freecamCFrame
            cam.Focus = freecamCFrame * CFrame.new(0, 0, -48)
            requestFreecamStream(newPos)
        end)
    else
        if not freecamActive then return end
        freecamActive = false

        pcall(function()
            RunService:UnbindFromRenderStep(FREECAM_RENDER_NAME)
        end)
        pcall(function()
            ContextActionService:UnbindAction(FREECAM_ACTION_NAME)
        end)

        cam.CameraType = originalCamType or Enum.CameraType.Custom
        if originalSubject then
            cam.CameraSubject = originalSubject
        else
            local char = lp.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then cam.CameraSubject = hum end
        end
        -- Do not restore a stale lock captured from the game's camera mode.
        -- Leaving freecam always hands back a movable cursor.
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end
end

-- VibeUI owns the settings menu; this script keeps only the impact HUD in
-- AutoLeadOverlay. A failed library fetch does not disable aiming or visuals.
local vibeUi = nil
local extras = { alive = true, edits = {}, roleCache = {}, pending = {}, notified = {} }
function extras.notify(message)
    if not extras.alive then return end
    if vibeUi and type(vibeUi.Notification) == "function" then
        local ok = pcall(function()
            vibeUi:Notification({ Title = "Attribute", Description = message, Duration = 4, Sound = "" })
        end)
        if ok then return end
    end
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Attribute", Text = message, Duration = 7
        })
    end)
end
local uiInsertConn = nil
local freecamHint = nil
local freecamToggleHandle = nil
local zoomToggleHandle = nil
local function setFreecamHint(message)
    if freecamHint then
        pcall(function() freecamHint:Set(message) end)
    end
end

do
    local ok, loaded = pcall(function()
        local source = game:HttpGet("https://sirmemegithub.com/RealSlimShady2000/VibeUI/raw/branch/main/VibeUI.luau")
        local chunk, compileError = loadstring(source)
        assert(chunk, compileError)
        return chunk()
    end)
    if not ok or not loaded or type(loaded.Window) ~= "function" then
        warn("[AutoLead] VibeUI could not load: " .. tostring(loaded))
    else
        vibeUi = loaded
        local built, buildError = pcall(function()
            vibeUi.Config.Rounded = true
            vibeUi.Config.CustomCursor = false
            vibeUi.Config.NotificationSound = ""
            vibeUi:SetTheme({ Accent = THEME.ToggleActive })
            local window = vibeUi:Window({
                Title = "AutoLeadAssist",
                Size = UDim2.fromOffset(720, 520),
                Keybind = Enum.KeyCode.RightShift,
                Layout = "Side",
                Resizable = true
            })

            local function settingToggle(section, name, key, info)
                section:Toggle({
                    Name = name,
                    Flag = "ALA_" .. key,
                    Default = Settings[key],
                    Info = info,
                    Callback = function(value)
                        Settings[key] = value == true
                    end
                })
            end

            local aimTab = window:Tab({ Name = "Aim", Columns = 2 })
            local aimAssist = aimTab:Section({ Name = "Assist", Side = 1 })
            settingToggle(aimAssist, "Infinite Ammo / No Reload", "InfiniteAmmo",
                "Opt-in local reload suppression. Server ammo rules still apply; off by default.")
            settingToggle(aimAssist, "Enable Assist", "EnableAutoLead", "Master aiming and preview switch.")
            settingToggle(aimAssist, "Adaptive Aim", "AdaptiveAim",
                "Low arc first. Use a high lob only when the low trajectory fails clearance or gun limits. Never force high arcs.")
            settingToggle(aimAssist, "Freecam Artillery Auto-Elevation", "ArtilleryAutoLay",
                "Align both axes only for a selected high-arc fallback. Direct shots keep normal tracking; some native modes require the gunner optic active.")
            local aimTarget = aimTab:Section({ Name = "Targeting", Side = 2 })
            settingToggle(aimTarget, "Shell Redirection", "ShellRedirection",
                "Fire normally, then hold your lock key to steer an airborne shell. Pauses launch assists. RMB lock keeps the freecam cursor free: use arrow keys to look, or choose a keyboard lock key to retain RMB look.")
            local lockKeyHandle
            lockKeyHandle = aimTarget:Label("Lock-on Key (Hold)"):AddKeybind({
                Flag = "ALA_ShellFocusKey", Default = Settings.ShellFocusKey, Mode = "Hold",
                -- Raw input below handles hold/release and UI consumption; the
                -- library only owns rebinding, not a second activation handler.
                Callback = function() end,
                OnChanged = function(key, mode)
                    Settings.ShellFocusKey = normalizeFocusKey(key)
                    if lockKeyHandle and mode ~= "Hold" then lockKeyHandle:SetMode("Hold") end
                end
            })
            aimTarget:Button():Add("Reset Lock Key to RMB", function()
                Settings.ShellFocusKey = Enum.UserInputType.MouseButton2
                lockKeyHandle:Set({Key=Settings.ShellFocusKey,Mode="Hold"})
            end)
            settingToggle(aimTarget, "Target Visibility Check", "ShellVisibilityCheck",
                "Optional map sightline check; off by default to avoid targeting raycasts. Shell collisions are unchanged.")
            aimTarget:Slider({
                Name = "Player Focus Radius", Flag = "ALA_ShellFocusRadius",
                Min = 5, Max = 250, Default = Settings.ShellFocusRadius, Decimals = 1, Suffix = " px",
                Callback = function(value) Settings.ShellFocusRadius = math.clamp(value, 5, 250) end
            })
            settingToggle(aimTarget, "Focus FOV Circle", "ShellFocusCircle", "Thin circle showing the exact player focus radius.")
            settingToggle(aimTarget, "Focused Player Tracer", "ShellFocusTracer", "One thin tracer to the targeted player while holding the lock key.")
            settingToggle(aimTarget, "Focused Player Highlight", "ShellFocusHighlight", "Highlight the targeted player while holding the lock key.")
            aimTarget:Label("Focused Player Color"):AddColorpicker({ Default = Settings.ShellFocusColor,
                Flag = "ALA_ShellFocusColor", Callback = function(c) Settings.ShellFocusColor = c end })
            aimTarget:Dropdown({
                Name = "Aim Source",
                Flag = "ALA_AimSource",
                Items = { "Mouse", "Camera" },
                Default = Settings.AimSource,
                Callback = function(value)
                    if value == "Mouse" or value == "Camera" then Settings.AimSource = value end
                end
            })
            aimTarget:Paragraph({
                Name = "Barrel Safety",
                Content = "Near-backward shot directions are blocked. Freecam always aims with the mouse."
            })

            local trajectoryTab = window:Tab({ Name = "Trajectory", Columns = 2 })
            local path = trajectoryTab:Section({ Name = "Path", Side = 1 })
            settingToggle(path, "Trajectory Beam", "Trajectory", "Show the predicted collision-aware path.")
            settingToggle(path, "Barrel Path", "ShowBallistic", "Also show the unassisted barrel path.")
            settingToggle(path, "Own Shell Effect", "OwnShellHighlight", "Native shell outline, with a tiny hollow ring for distant or attachment-only shells.")
            settingToggle(path, "Shell Flight Progress", "ShotProgress", "Fill the launch path as the real shell travels.")
            settingToggle(path, "Shot Notifications", "ShotStatus", "UI-library notifications after an actual shot dispatch; rapid bursts are grouped.")
            local impact = trajectoryTab:Section({ Name = "Impact", Side = 2 })
            settingToggle(impact, "Explosion Radius", "ExplosionRadius", "Show a compact filled impact-zone cue.")
            settingToggle(impact, "Show Distance", "ShowDistance", "Show muzzle-to-zone distance beside the blast zone and in the HUD.")
            settingToggle(impact, "Flight Timer", "FlightTimer", "Show the predicted flight time.")

            local freecamTab = window:Tab({ Name = "Freecam", Columns = 2 })
            local freecamControls = freecamTab:Section({ Name = "Camera", Side = 1 })
            settingToggle(freecamControls, "Click Teleport (on foot)", "FreecamClickTP",
                "Off on load. In freecam, Alt + left-click visible ground to move your character. Never moves vehicles; server may reject movement.")
            freecamControls:Toggle({
                Name = "Disable Explosion Shake",
                Flag = "ALA_DisableExplosionShake",
                Default = Settings.DisableExplosionShake,
                Info = "Suppress explosion and shared shell-flyby camera shake; keep damage, sound and particles.",
                Callback = function(value) firingShake.setExplosions(value) end
            })
            freecamControls:Toggle({
                Name = "Disable Firing Shake",
                Flag = "ALA_DisableFiringShake",
                Default = Settings.DisableFiringShake,
                Info = "Suppress cannon muzzle camera shake; keep explosion effects and physical recoil.",
                Callback = function(value) firingShake.set(value) end
            })
            freecamToggleHandle = freecamControls:Toggle({
                Name = "Enable Freecam",
                Flag = "ALA_Freecam",
                Default = Settings.Freecam,
                Callback = function(value)
                    Settings.Freecam = value == true
                    setFreecam(Settings.Freecam)
                    if Settings.Freecam then window:SetOpen(false) end
                end
            })
            freecamControls:Label("Freecam Key"):AddKeybind({
                Flag = "ALA_FreecamKey",
                Default = Settings.FreecamKey,
                Mode = "Toggle",
                Callback = function()
                    local enabled = not Settings.Freecam
                    Settings.Freecam = enabled
                    setFreecam(enabled)
                    if freecamToggleHandle then freecamToggleHandle:Set(enabled) end
                    if enabled then window:SetOpen(false) end
                end,
                OnChanged = function(key)
                    local name = tostring(key):match("Enum%.KeyCode%.([%w_]+)$")
                    if name and Enum.KeyCode[name] then Settings.FreecamKey = Enum.KeyCode[name] end
                end
            })
            freecamControls:Slider({
                Name = "Flight Speed",
                Flag = "ALA_FreecamSpeed",
                Min = 0.5, Max = 20, Default = Settings.FreecamSpeed,
                Decimals = 0.1, Suffix = "x",
                Callback = function(value)
                    Settings.FreecamSpeed = math.clamp(tonumber(value) or 3.5, 0.5, 20)
                end
            })
            local zoomControls = freecamTab:Section({ Name = "Zoom", Side = 1 })
            zoomToggleHandle = zoomControls:Toggle({
                Name = "Enable Zoom",
                Flag = "ALA_Zoom",
                Default = Settings.Zoom,
                Callback = function(value)
                    setZoom(value)
                end
            })
            zoomControls:Label("Zoom Key"):AddKeybind({
                Flag = "ALA_ZoomKey",
                Default = Settings.ZoomKey,
                Mode = "Toggle",
                Callback = function()
                    local enabled = not Settings.Zoom
                    setZoom(enabled)
                    if zoomToggleHandle then zoomToggleHandle:Set(enabled) end
                end,
                OnChanged = function(key)
                    local name = tostring(key):match("Enum%.KeyCode%.([%w_]+)$")
                    if name and Enum.KeyCode[name] then Settings.ZoomKey = Enum.KeyCode[name] end
                end
            })
            zoomControls:Slider({
                Name = "Zoom Field of View",
                Flag = "ALA_ZoomFOV",
                Min = 10, Max = 70, Default = Settings.ZoomFOV,
                Decimals = 1, Suffix = "°",
                Callback = function(value)
                    Settings.ZoomFOV = math.clamp(tonumber(value) or 25, 10, 70)
                end
            })
            local freecamHelp = freecamTab:Section({ Name = "Controls", Side = 2 })
            freecamHelp:Paragraph({
                Name = "Movement",
                Content = "Enabling freecam closes this menu. WASD to fly, Q/E for height, hold RMB to look. Release RMB to point your cursor at a shot location."
            })
            freecamHint = freecamHelp:Label("F fires in either view; driver click uses direct fire when ready.")

            local espTab = window:Tab({ Name = "ESP", Columns = 2 })
            local espTargets = espTab:Section({ Name = "Targets", Side = 1 })
            settingToggle(espTargets, "Enemy Players", "PlayerESP", "Show nearby enemy player markers.")
            settingToggle(espTargets, "Player Names", "ESPNames", "Show only each enemy username.")
            settingToggle(espTargets, "Player Health Bar", "ESPHealth", "Show a slim bar beside each enemy.")
            settingToggle(espTargets, "Player Boxes", "ESPBoxes", "Draw a body-sized outline around each enemy player.")
            local espStyle = espTab:Section({ Name = "Style & Range", Side = 2 })
            local colorNames = {}
            for _, entry in ipairs(ESP_COLORS) do colorNames[#colorNames + 1] = entry.name end
            espStyle:Dropdown({
                Name = "Highlight Color",
                Flag = "ALA_ESPColor",
                Items = colorNames,
                Default = ESP_COLORS[Settings.ESPColorIndex].name,
                Callback = function(value)
                    for index, entry in ipairs(ESP_COLORS) do
                        if entry.name == value then Settings.ESPColorIndex = index; break end
                    end
                end
            })
            espStyle:Slider({
                Name = "ESP Distance",
                Flag = "ALA_ESPMaxDistance",
                Min = 0, Max = 50000,
                Default = Settings.ESPMaxDistance,
                Decimals = 1, Suffix = " studs",
                Callback = function(value)
                    Settings.ESPMaxDistance = math.clamp(tonumber(value) or 0, 0, 50000)
                end
            })
            espStyle:Paragraph({
                Name = "Distance",
                Content = "Drag the slider or click its value box to type a precise range in studs."
            })

            local tanks = espTab:Section({ Name = "Tank ESP", Side = 1 })
            for _, option in ipairs({
                {"Tank ESP", "EnemyTankESP"}, {"Box ESP", "TankBoxes"},
                {"Names", "TankNames"}, {"Vehicle Class", "TankClass"},
                {"Distance", "TankDistance"}, {"Distance Fade", "TankDistanceFade"},
                {"Helicopter ESP", "HelicopterESP"}, {"Occupied Only", "TankOccupiedOnly"},
                {"Team Check", "TankTeamCheck"}
            }) do settingToggle(tanks, option[1], option[2], "Uses the shared ESP distance limit.") end
            local modules = espTab:Section({ Name = "Tank Modules", Side = 2 })
            settingToggle(modules, "Outline", "ModuleOutline", "Outline actual streamed damage modules; not a penetration guarantee.")
            modules:Slider({ Name = "Outline Thickness", Min = 1, Max = 5, Decimals = 1,
                Default = Settings.ModuleLineThickness, Suffix = " px", Flag = "ALA_ModuleLineThickness",
                Callback = function(v)
                    Settings.ModuleLineThickness = math.floor(math.clamp(tonumber(v) or 1, 1, 5) + 0.5)
                end })
            settingToggle(modules, "Filled", "ModuleFilled", "Translucent module volumes, separate from the whole-tank highlight.")
            settingToggle(modules, "Engine", "ModuleEngine", "Mark the engine assembly.")
            settingToggle(modules, "Ammo", "ModuleAmmo", "Mark hull/turret ammo compartments.")
            modules:Label("Engine Color"):AddColorpicker({ Default = Settings.ModuleEngineColor,
                Flag = "ALA_ModuleEngineColor", Callback = function(c) Settings.ModuleEngineColor = c end })
            modules:Label("Ammo Color"):AddColorpicker({ Default = Settings.ModuleAmmoColor,
                Flag = "ALA_ModuleAmmoColor", Callback = function(c) Settings.ModuleAmmoColor = c end })
            modules:Slider({ Name = "Module Distance", Min = 0, Max = 50000, Decimals = 1,
                Default = Settings.ModuleDistance, Suffix = " studs", Flag = "ALA_ModuleDistance",
                Callback = function(v) Settings.ModuleDistance = math.clamp(tonumber(v) or 400, 0, 50000) end })
            local worldTab = window:Tab({ Name = "World", Columns = 1 })
            local foliage = worldTab:Section({ Name = "Foliage", Side = 1 })
            settingToggle(foliage, "No Grass", "NoGrass", "Hide terrain decoration and recognized grass meshes locally.")
            settingToggle(foliage, "No Trees", "NoTrees", "Hide recognized map trees locally. Collisions remain; restored on disable/unload.")

            local armorTab = window:Tab({ Name = "Armor", Columns = 2 })
            local armorControls = armorTab:Section({ Name = "Enemy Tanks", Side = 1 })
            settingToggle(armorControls, "Zero Enemy Armor", "ZeroEnemyArmor",
                "Set visible enemy ArmourValue and composite resistance to zero locally; restore on disable.")
            local armorNote = armorTab:Section({ Name = "Scope", Side = 2 })
            armorNote:Paragraph({
                Name = "Client-Side Limit",
                Content = "Only enemy tank values in this client are changed. Server-side damage rules may ignore them."
            })

            local vehicleTab = window:Tab({ Name = "Vehicle", Columns = 2 })
            local supply = vehicleTab:Section({ Name = "Supplies", Side = 1 })
            supply:Button():Add("Give Ammo Crate", function()
                if extras.requestSupply then extras.requestSupply("AmmoPallet", "ammo crate") end
            end)
            supply:Button():Add("Give Jerry Can", function()
                if extras.requestSupply then extras.requestSupply("Fuel", "jerry can") end
            end)
            supply:Paragraph({ Name = "Station required", Content = "Uses a nearby supply station within its normal pickup range. No remote spawning." })
            local tuning = vehicleTab:Section({ Name = "Turret & Firing", Side = 2 })
            settingToggle(tuning, "Turret Rotate Speed", "TurretSpeedEnabled", "Local occupied-turret speed override; restores on exit or disable.")
            tuning:Slider({ Name = "Turret Rotate Speed Slider", Min = 0.25, Max = 3,
                Default = Settings.TurretSpeedMultiplier, Decimals = 2, Suffix = "x",
                Callback = function(v) Settings.TurretSpeedMultiplier = math.clamp(tonumber(v) or 1, 0.25, 3) end })
            settingToggle(tuning, "Tank Rapid Fire", "TankRapidFire", "Hold left-click or F to repeat while seated. Release to stop. Server ammo/reload rules still apply.")
            tuning:Slider({ Name = "Rapid Fire Multiplier", Min = 1, Max = 5,
                Default = Settings.RapidFireMultiplier, Decimals = 1, Suffix = "x",
                Callback = function(v) Settings.RapidFireMultiplier = math.clamp(tonumber(v) or 2, 1, 5) end })
            local serverTab = window:Tab({ Name = "Server", Columns = 1 })
            local roles = serverTab:Section({ Name = "Group Roles", Side = 1 })
            settingToggle(roles, "Staff Detection", "StaffNotifications", "Notification only for verified Top Giun staff/developer role names.")
            settingToggle(roles, "Content Creator Check", "CreatorNotifications", "Notify when a Content Creator is present or joins.")
            roles:Button():Add("Check Current Server", function()
                if extras.scanRoles then extras.scanRoles(true) end
            end)
            roles:Paragraph({ Name = "Detection action: Notify", Content = "Group 32966202 only. No auto-leave or other automatic action. Role lookups may be cached by Roblox." })
            vibeUi:CreateSettingsPage(window)
            uiInsertConn = UserInputService.InputBegan:Connect(function(input, processed)
                if not processed and input.KeyCode == Enum.KeyCode.Insert then
                    window:SetOpen(not window.IsOpen)
                end
            end)
        end)
        if not built then
            warn("[AutoLead] VibeUI menu build failed: " .. tostring(buildError))
            if uiInsertConn then uiInsertConn:Disconnect(); uiInsertConn = nil end
            pcall(function() vibeUi:Unload() end)
            vibeUi = nil
            freecamHint = nil
        end
    end
end

-- ===================================================================
-- MTC ENGINE INTERFACE & BALLISTICS SOLVER
-- ===================================================================

local PHRST = ReplicatedStorage:WaitForChild("PHRST")
local ShellModules = {}
local GlobalConstants = {}
local defaultGravity = -49

pcall(function()
    ShellModules = require(PHRST:WaitForChild("ShellModules"))
end)
pcall(function()
    GlobalConstants = require(PHRST:WaitForChild("Shells"):WaitForChild("GlobalConstants"))
    if GlobalConstants.mtostud and GlobalConstants.ProjectileGravity then
        defaultGravity = -GlobalConstants.mtostud(GlobalConstants.ProjectileGravity)
    end
end)

local function getActiveTank()
    local veh = lp:FindFirstChild("InTank") and lp.InTank.Value
    if veh and veh:IsA("Model") then return veh end

    local char = lp.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local seatPart = humanoid and humanoid.SeatPart
    if seatPart then
        local cur = seatPart
        while cur and cur ~= workspace do
            if cur:IsA("Model") and (cur:FindFirstChild("Turrets") or cur:FindFirstChild("Muzzles") or cur:FindFirstChild("Chassis")) then
                return cur
            end
            cur = cur.Parent
        end
    end
    return nil
end

local function getActiveWeaponData(veh)
    if not veh then return nil end

    local char = lp.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local seatPart = humanoid and humanoid.SeatPart

    local turrets = veh:FindFirstChild("Turrets")
    local matchedTurret = nil

    if turrets then
        for _, t in ipairs(turrets:GetChildren()) do
            local ctrl = t:FindFirstChild("Control")
            if ctrl and ctrl.Value == seatPart then
                matchedTurret = t
                break
            end
        end
        if not matchedTurret then
            -- Prefer the main cannon when driving; some vehicles also have
            -- passenger machine-gun turrets earlier in GetChildren() order.
            local mainTurret = turrets:FindFirstChild("Turret1")
            if mainTurret and mainTurret:FindFirstChild("Weapons") and #mainTurret.Weapons:GetChildren() > 0 then
                matchedTurret = mainTurret
            end
            for _, t in ipairs(turrets:GetChildren()) do
                if matchedTurret then break end
                local weapons = t:FindFirstChild("Weapons")
                if weapons and #weapons:GetChildren() > 0 then
                    matchedTurret = t
                    break
                end
            end
            matchedTurret = matchedTurret or turrets:FindFirstChild("Turret1") or turrets:GetChildren()[1]
        end
    end

    local weaponFolder = nil

    pcall(function()
        local ngd = game:GetService("ReplicatedFirst"):FindFirstChild("NewGuiData")
        if ngd and ngd:FindFirstChild("Gunner") and ngd.Gunner:FindFirstChild("Weapons") and ngd.Gunner.Weapons:FindFirstChild("Data") then
            local curSel = ngd.Gunner.Weapons.Data:FindFirstChild("CurrentlySelected")
            if curSel and curSel.Value and curSel.Value:IsA("Folder")
                and matchedTurret and curSel.Value:IsDescendantOf(matchedTurret)
                and matchedTurret:FindFirstChild("Control") and matchedTurret.Control.Value == seatPart then
                weaponFolder = curSel.Value
            end
        end
    end)

    if not weaponFolder and matchedTurret and matchedTurret:FindFirstChild("Weapons") then
        local bestScore = -math.huge
        for _, w in ipairs(matchedTurret.Weapons:GetChildren()) do
            local loadedVal = w:FindFirstChild("CurrentlyLoaded")
            local muzzleObj = w:FindFirstChild("CurrentMuzzle")
            local muzzle = muzzleObj and muzzleObj.Value and muzzleObj.Value.Value
            if muzzle and loadedVal and loadedVal.Value ~= "Unloaded" and loadedVal.Value ~= "" then
                local shell = ShellModules[w.Name .. ":" .. loadedVal.Value] or {}
                local score = tonumber(shell.ShellMass) or 0
                if string.find(string.lower(w.Name), "smoke", 1, true) then score = -1 end
                if score > bestScore then
                    weaponFolder = w
                    bestScore = score
                end
            end
        end
        if not weaponFolder then
            for _, w in ipairs(matchedTurret.Weapons:GetChildren()) do
                local muzzleObj = w:FindFirstChild("CurrentMuzzle")
                local muzzle = muzzleObj and muzzleObj.Value and muzzleObj.Value.Value
                if muzzle then
                    weaponFolder = w
                    break
                end
            end
        end
    end

    -- Locate MainSight camera for forward orientation validation
    local mainSight = nil
    if matchedTurret and matchedTurret:FindFirstChild("Cameras") and matchedTurret.Cameras:FindFirstChild("MainSight") then
        local msObj = matchedTurret.Cameras.MainSight
        mainSight = msObj and msObj.Value
    end

    if not weaponFolder then
        local muzzlesFolder = veh:FindFirstChild("Muzzles")
        local muzzle = muzzlesFolder and (muzzlesFolder:FindFirstChild("Muzzle") or muzzlesFolder:GetChildren()[1])
        if muzzle then
            return {
                vehicle = veh,
                weapon = nil,
                weaponName = "Cannon",
                muzzle = muzzle,
                firePoint = muzzle:FindFirstChild("GunFirePoint1"),
                mainSight = mainSight,
                loaded = "Default",
                speed = 1200,
                gravity = defaultGravity,
                drag = 0,
                shellMass = 5,
                expMass = 2,
                shellType = "HE"
            }
        end
        return nil
    end

    local muzzleObj = weaponFolder:FindFirstChild("CurrentMuzzle")
    local muzzle = muzzleObj and muzzleObj.Value and muzzleObj.Value.Value
    if not muzzle then
        local muzzlesFolder = veh:FindFirstChild("Muzzles")
        muzzle = muzzlesFolder and (muzzlesFolder:FindFirstChild(weaponFolder.Name) or muzzlesFolder:FindFirstChild("Muzzle") or muzzlesFolder:GetChildren()[1])
    end
    if not muzzle then return nil end

    local firePoint = muzzle:FindFirstChild("GunFirePoint1")
    local loadedName = weaponFolder:FindFirstChild("CurrentlyLoaded") and weaponFolder.CurrentlyLoaded.Value
    if not loadedName or loadedName == "" or loadedName == "Unloaded" then
        local ammoFolder = weaponFolder:FindFirstChild("Ammo")
        if ammoFolder and #ammoFolder:GetChildren() > 0 then
            loadedName = ammoFolder:GetChildren()[1].Name
        else
            loadedName = "M1 shell"
        end
    end

    local shellKey = weaponFolder.Name .. ":" .. loadedName
    local shellData = ShellModules[shellKey] or ShellModules[loadedName] or ShellModules.Default or {}

    local muzzleSpeed = shellData.MuzzleSpeed or 1000
    local gravityY = shellData.Gravity or defaultGravity
    local drag = shellData.Drag or 0
    local expMass = shellData.ExplosiveMass or 0
    local shellMass = shellData.ShellMass or 1
    local shellType = shellData.ShellType or "HE"

    return {
        vehicle = veh,
        turret = matchedTurret,
        weapon = weaponFolder,
        weaponName = weaponFolder.Name,
        muzzle = muzzle,
        firePoint = firePoint,
        mainSight = mainSight,
        loaded = loadedName,
        shellData = shellData,
        speed = muzzleSpeed,
        gravity = gravityY,
        drag = drag,
        shellMass = shellMass,
        expMass = expMass,
        shellType = shellType
    }
end

-- Resolve True Forward Direction for any Tank Barrel
local function getBoreForwardDirection(wData)
    local forwardDir
    if wData.firePoint then
        forwardDir = wData.firePoint.WorldCFrame.LookVector
    elseif wData.mainSight then
        forwardDir = wData.mainSight.CFrame.LookVector
    else
        forwardDir = -wData.muzzle.CFrame.LookVector
    end

    -- Safety check against MainSight orientation: ensure positive forward alignment
    if wData.mainSight and forwardDir:Dot(wData.mainSight.CFrame.LookVector) < 0 then
        forwardDir = -forwardDir
    end

    return forwardDir
end

-- Exact Closed-Form Ballistics Solver: Solves launch unit vector to hit targetPos under gravity
local ballistics = { maxTime = 120 }
function ballistics.lifetime(shell)
    return math.clamp(tonumber(shell and shell.Lifetime) or 60, 0.1, ballistics.maxTime)
end
function ballistics.time(range, horizontalSpeed, drag)
    if range < 0.001 then return 0 end
    if horizontalSpeed <= 0.001 then return nil end
    local d = math.max(tonumber(drag) or 0, 0)
    if d <= 1e-5 then return range / horizontalSpeed end
    local remaining = 1 - d * range / horizontalSpeed
    if remaining <= 0 then return nil end
    return -math.log(remaining) / d
end
-- Shared continuous horizontal-drag model. Native variable-step physics can
-- still differ slightly, but selection, clearance and preview now agree.
function ballistics.sample(start, velocity, gravity, drag, t)
    local d = math.max(tonumber(drag) or 0, 0)
    local decay = d > 1e-5 and math.exp(-d*t) or 1
    local travel = d > 1e-5 and (1-decay)/d or t
    local horizontal = Vector3.new(velocity.X,0,velocity.Z)
    return start + horizontal*travel + Vector3.yAxis*(velocity.Y*t + 0.5*gravity*t*t),
        horizontal*decay + Vector3.yAxis*(velocity.Y + gravity*t)
end
function ballistics.steps(time, gravity, drag, speed)
    local acceleration = math.abs(gravity) + math.max(drag or 0,0)*speed
    local dt = math.min(0.25, math.sqrt(4/math.max(acceleration,1)))
    return math.clamp(math.ceil(time/dt), 8, 192)
end
local function solveBallistic(startPos, targetPos, speed, g, highArc)
    local diff = targetPos - startPos
    if diff.Magnitude < 0.1 then return Vector3.new(0, 1, 0), false end
    if speed <= 0 then return diff.Unit, false end
    local distXZ = Vector3.new(diff.X, 0, diff.Z).Magnitude
    local diffY = diff.Y
    if distXZ < 0.1 then
        local up = highArc or diffY >= 0
        local possible = diffY <= 0 or speed*speed >= 2*math.abs(g)*diffY
        return Vector3.new(0, up and 1 or -1, 0), possible, up and math.pi/2 or -math.pi/2
    end

    local gMag = math.abs(g)
    if gMag < 1e-4 then return diff.Unit, true, math.atan2(diffY, distXZ) end
    local v2 = speed * speed
    local v4 = v2 * v2
    local disc = v4 - gMag * (gMag * distXZ * distXZ + 2 * diffY * v2)
    local dirXZ = Vector3.new(diff.X, 0, diff.Z).Unit

    if disc >= -v4 * 1e-12 then
        local sqrtDisc = math.sqrt(math.max(0, disc))
        local tanTheta
        if highArc then
            tanTheta = (v2 + sqrtDisc) / (gMag * distXZ)
        else
            -- Rationalized minus root avoids cancellation for shallow shots.
            tanTheta = (gMag*distXZ*distXZ + 2*diffY*v2) / (distXZ*(v2 + sqrtDisc))
        end
        local theta = math.atan(tanTheta)
        return (dirXZ * math.cos(theta) + Vector3.new(0, math.sin(theta), 0)).Unit, true, theta
    else
        -- No ballistic solution: preserve the chosen mouse/camera bearing.
        -- A fixed 45-degree fallback sent unobstructed shots away from the cursor.
        return diff.Unit, false
    end
end

-- The target classes change much less often than the cursor. Cache only the
-- raycast filters; the ray origin/direction and actual hit are still read every
-- rendered frame so the preview does not lag behind mouse movement.
local shellRedirection = { players = {}, records = {}, candidates = {}, focused = nil, held = false,
    focusScans = 0, focusRays = 0, visualWrites = 0 }
local aimIncludeParams = RaycastParams.new()
aimIncludeParams.FilterType = Enum.RaycastFilterType.Include
aimIncludeParams.IgnoreWater = true
local aimWorldParams = RaycastParams.new()
aimWorldParams.FilterType = Enum.RaycastFilterType.Exclude
aimWorldParams.IgnoreWater = true
aimWorldParams.RespectCanCollide = true
local aimTargetCount = 0
local aimFilterVehicle = nil
local aimFilterCharacter = nil
local aimFilterUpdated = 0
local function refreshAimFilters(veh)
    local now = os.clock()
    if aimFilterVehicle == veh and aimFilterCharacter == lp.Character and now - aimFilterUpdated < 0.25 then
        return
    end
    aimFilterVehicle = veh
    aimFilterCharacter = lp.Character
    aimFilterUpdated = now
    local targets = {}
    local vehicles = workspace:FindFirstChild("SpawnedVehicles")
    if vehicles then
        for _, candidate in ipairs(vehicles:GetChildren()) do
            if candidate ~= veh then targets[#targets + 1] = candidate end
        end
    end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= lp and player.Character then targets[#targets + 1] = player.Character end
    end
    local spawnedPlayers = workspace:FindFirstChild("SpawnedPlayers")
    if spawnedPlayers then
        for _, candidate in ipairs(spawnedPlayers:GetChildren()) do
            if candidate ~= lp.Character then targets[#targets + 1] = candidate end
        end
    end
    aimTargetCount = #targets
    aimIncludeParams.FilterDescendantsInstances = targets
    aimWorldParams.FilterDescendantsInstances = { veh, lp.Character }
end

function shellRedirection.refreshPlayers(now)
    if now < (shellRedirection.nextRoster or 0) then return end
    shellRedirection.nextRoster = now + 0.5
    table.clear(shellRedirection.players)
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player ~= lp and player.Character
        local record = shellRedirection.records[player]
        if character and (not record or record.character ~= character or not record.part.Parent
            or not record.humanoid.Parent) then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            local part = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
                or character:FindFirstChild("HumanoidRootPart")
            record = humanoid and part and part:IsA("BasePart") and {
                player=player,character=character,humanoid=humanoid,part=part
            } or nil
            shellRedirection.records[player] = record
        end
        if character and record then shellRedirection.players[#shellRedirection.players+1] = record end
    end
    for player in pairs(shellRedirection.records) do
        if player.Parent ~= Players or not player.Character then shellRedirection.records[player] = nil end
    end
end
function shellRedirection.isEngaged()
    return Settings.ShellRedirection and shellRedirection.held and not shellRedirection.failed
        and not shellRedirection.destroyed
        and shellRedirection.heldKey == Settings.ShellFocusKey
        and UserInputService:GetFocusedTextBox() == nil
end
function shellRedirection.release()
    shellRedirection.held, shellRedirection.focused, shellRedirection.focusedPart = false,nil,nil
    shellRedirection.heldKey = nil
    shellRedirection.focusedRecord, shellRedirection.nextFocusScan = nil,nil
    if shellRedirection.active and lp:GetAttribute("AttributeShellRedirectOwner")==shellRedirection.owner then
        lp:SetAttribute("AttributeShellRedirectHeld",false)
        lp:SetAttribute("AttributeShellRedirectTargetId",nil)
    end
    if shellRedirection.visuals then
        shellRedirection.visuals.tracer.Visible = false
        shellRedirection.visuals.highlight.Enabled = false
        shellRedirection.visuals.highlight.Adornee = nil
    end
end
function shellRedirection.inputBegan(input, processed)
    local key = Settings.ShellFocusKey
    if Settings.ShellRedirection and key and not processed
        and (input.KeyCode==key or input.UserInputType==key)
        and UserInputService:GetFocusedTextBox()==nil then
        shellRedirection.held, shellRedirection.heldKey = true,key
    end
end
function shellRedirection.inputEnded(input)
    if shellRedirection.heldKey and (input.KeyCode==shellRedirection.heldKey
        or input.UserInputType==shellRedirection.heldKey) then shellRedirection.release() end
end
function shellRedirection.select(cam, pixel, origin)
    shellRedirection.focused = nil
    shellRedirection.focusedPart = nil
    shellRedirection.focusedRecord = nil
    if not shellRedirection.isEngaged() then return end
    shellRedirection.focusScans=(shellRedirection.focusScans or 0)+1
    local candidates = shellRedirection.candidates
    table.clear(candidates)
    local radiusSquared = Settings.ShellFocusRadius * Settings.ShellFocusRadius
    for _, record in ipairs(shellRedirection.players) do
        local player, part = record.player, record.part
        -- Validate cached membership every frame; death/respawn cannot retain a focus.
        if player.Parent == Players and player.Character == record.character
            and part.Parent and record.humanoid.Health > 0
            and not player.Neutral and player.Team ~= nil and player.Team ~= lp.Team then
            local point, visible = cam:WorldToViewportPoint(part.Position)
            local distance = (point.X-pixel.X)^2 + (point.Y-pixel.Y)^2
            if visible and point.Z > 0 and distance <= radiusSquared then
                -- No sightline check needs only the nearest projected enemy.
                local limit = Settings.ShellVisibilityCheck and 4 or 1
                local index = 1
                while candidates[index] and candidates[index].focusDistance <= distance do index += 1 end
                if index <= limit then
                    record.focusDistance=distance
                    table.insert(candidates,index,record)
                    if #candidates > limit then table.remove(candidates) end
                end
            end
        end
    end
    for _, record in ipairs(candidates) do
        local hit
        if Settings.ShellVisibilityCheck then
            shellRedirection.focusRays=(shellRedirection.focusRays or 0)+1
            hit = workspace:Raycast(origin,record.part.Position-origin,aimWorldParams)
        end
        if not hit or hit.Instance:IsDescendantOf(record.character) then
            shellRedirection.focused = record.player
            shellRedirection.focusedPart = record.part
            shellRedirection.focusedRecord = record
            return record.part.Position, record.part.AssemblyLinearVelocity, record.part, Vector3.yAxis
        end
    end
end

-- Runs inside each native projectile Actor, where the real simulation tables live.
-- The display Part is never used as a physics control surface.
shellRedirection.steerSource = [=[
local function steer(state, targetPosition, targetVelocity)
    if type(state) ~= "table" or state.replicate ~= true or state.Behavior ~= "Default"
        or state.destroy or state.hitray or state.physicalprojectile
        or typeof(state.position) ~= "Vector3" or typeof(state.position0) ~= "Vector3"
        or typeof(state.velocity) ~= "Vector3" then return false end
    if (state.position-state.position0).Magnitude < 15 then return false end
    local speed = state.velocity.Magnitude
    if speed < 1 or typeof(targetPosition) ~= "Vector3" or typeof(targetVelocity) ~= "Vector3" then return false end
    local offset = targetPosition-state.position
    if offset.Magnitude < 1 then return false end
    local time = math.min(offset.Magnitude/speed, 2)
    local desired = offset + targetVelocity*time
    if desired.Magnitude < 1 then return false end
    -- Preserve instantaneous speed; native integration still handles gravity,
    -- drag, ray collisions, lifetime and destruction on the following step.
    state.velocity = desired.Unit*speed
    return true
end
]=]
shellRedirection.actorSource = [=[
local actor = game:GetService("ReplicatedStorage").PHRST.Threads:FindFirstChild(@ACTOR@)
local players = game:GetService("Players")
local player = players.LocalPlayer
local owner = @OWNER@
if not actor or not player or player:GetAttribute("AttributeShellRedirectOwner") ~= owner then return end
local matches = filtergc("function", {Name="simulatebullet",IgnoreExecutor=false}, false)
local original, env
for _, fn in ipairs(matches or {}) do
    local candidate = getfenv(fn)
    if type(candidate)=="table" and candidate.simulatebullet==fn then
        if original then return end
        original,env = fn,candidate
    end
end
if not original then return end
@STEER@
local oldStatus = actor:GetAttribute("AttributeShellRedirectStatus")
local cached, connections = {},{}
local ownSeenAt = -math.huge
local startupAt = os.clock()
local function sampleTarget()
    if cached.Owner~=owner or cached.Held~=true or type(cached.TargetId)~="number" then
        cached.Position,cached.Velocity,cached.Part,cached.Target=nil,nil,nil,nil
        return
    end
    if not cached.Target or cached.Target.UserId~=cached.TargetId then
        cached.Target=players:GetPlayerByUserId(cached.TargetId)
        cached.Part,cached.Character,cached.Humanoid=nil,nil,nil
    end
    local target=cached.Target
    local character=target and target.Character
    if not target or target.Parent~=players or target.Neutral or not target.Team or target.Team==player.Team
        or not character then cached.Position,cached.Velocity=nil,nil;return end
    if cached.Character~=character or not cached.Part or not cached.Part.Parent then
        cached.Character=character
        cached.Part=character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
            or character:FindFirstChild("HumanoidRootPart")
        cached.Humanoid=character:FindFirstChildOfClass("Humanoid")
    end
    if not cached.Part or not cached.Humanoid or cached.Humanoid.Health<=0 then
        cached.Position,cached.Velocity=nil,nil;return
    end
    cached.Position,cached.Velocity=cached.Part.Position,cached.Part.AssemblyLinearVelocity
    cached.SampledAt=os.clock()
end
local function refreshTarget()
    local ok,err=pcall(sampleTarget)
    if not ok then cached.Error=tostring(err);cached.Position,cached.Velocity=nil,nil end
end
for _, key in ipairs({"Owner","Held","Heartbeat","TargetId","Shot","Initializing"}) do
    local attribute = "AttributeShellRedirect"..key
    cached[key] = player:GetAttribute(attribute)
    connections[#connections+1] = player:GetAttributeChangedSignal(attribute):Connect(function()
        local ok,value=pcall(player.GetAttribute,player,attribute)
        if ok then cached[key]=value else cached.Error=tostring(value) end
        if key~="Heartbeat" and key~="Initializing" then refreshTarget() end
    end)
end
refreshTarget()
local wrapper
wrapper = function(state, ...)
    -- Instance access belongs to the signal callbacks, never the native
    -- per-projectile hot path. Only the simulation table is touched here.
    if type(state)=="table" and state.replicate==true and state.Behavior=="Default"
        and not state.destroy and not state.hitray and not state.physicalprojectile
        and cached.Owner==owner and cached.Held==true and cached.Initializing~=true and not cached.Error
    then
        local now=os.clock()
        ownSeenAt=now
        if type(cached.Heartbeat)=="number" and now-cached.Heartbeat<0.75
            and cached.Position and cached.Velocity and now-(cached.SampledAt or -math.huge)<0.15 then
            -- Actor-local sampling avoids moving Vector3 broadcasts and smooths
            -- target motion between samples without touching Instances here.
            local position=cached.Position+cached.Velocity*math.clamp(now-(cached.SampledAt or now),0,0.1)
            local ok, err = pcall(steer,state,position,cached.Velocity)
            if not ok and not cached.Error then
                cached.Error=tostring(err)
            end
        end
    end
    return original(state, ...)
end
env.simulatebullet = wrapper
actor:SetAttribute("AttributeShellRedirectStatus",owner)
task.spawn(function()
    local errorPublished=false
    while player.Parent and actor.Parent and env.simulatebullet==wrapper do
        if cached.Error and not errorPublished then
            actor:SetAttribute("AttributeShellRedirectStatus", owner.."|error: "..cached.Error)
            errorPublished=true
        end
        local now=os.clock()
        if cached.Owner~=owner or type(cached.Heartbeat)~="number" then break end
        -- Serial Actor installation can take longer than the normal heartbeat
        -- lease. Allow bounded setup, then enforce the strict running lease.
        if cached.Initializing==true then
            if now-startupAt>=8 then break end
        elseif now-cached.Heartbeat>=0.75 then break end
        local sampling=cached.Held and cached.TargetId and os.clock()-ownSeenAt<0.15
        if sampling then refreshTarget() end
        task.wait(sampling and 1/30 or 0.1)
    end
    if env.simulatebullet==wrapper then env.simulatebullet=original end
    for _, connection in ipairs(connections) do connection:Disconnect() end
    if actor.Parent then
        local status = actor:GetAttribute("AttributeShellRedirectStatus")
        if type(status)=="string" and status:sub(1,#owner)==owner then
            actor:SetAttribute("AttributeShellRedirectStatus",oldStatus)
        end
    end
end)
]=]
shellRedirection.attributes = {"AttributeShellRedirectOwner","AttributeShellRedirectHeartbeat",
    "AttributeShellRedirectTargetId","AttributeShellRedirectHeld","AttributeShellRedirectShot",
    "AttributeShellRedirectInitializing"}
function shellRedirection.stop()
    if shellRedirection.originalAttributes and lp:GetAttribute("AttributeShellRedirectOwner")==shellRedirection.owner then
        for _, key in ipairs(shellRedirection.attributes) do
            lp:SetAttribute(key,shellRedirection.originalAttributes[key])
        end
    end
    shellRedirection.active, shellRedirection.focused, shellRedirection.focusedPart = false,nil,nil
    shellRedirection.ready = 0
    shellRedirection.originalAttributes = nil
end
function shellRedirection.update()
    if not Settings.ShellRedirection then
        if shellRedirection.active then shellRedirection.stop() end
        shellRedirection.failed, shellRedirection.error = nil,nil
        shellRedirection.reportedError = nil
        return
    end
    local now = os.clock()
    if not shellRedirection.active then
        if shellRedirection.failed then return end
        if type(getactors)~="function" or type(run_on_actor)~="function" then
            shellRedirection.error = "Executor cannot access projectile Actors"
            shellRedirection.failed = true
            return
        end
        shellRedirection.originalAttributes = {}
        for _,key in ipairs(shellRedirection.attributes) do shellRedirection.originalAttributes[key]=lp:GetAttribute(key) end
        shellRedirection.owner = "Attribute:"..tostring(now)
        shellRedirection.publishedShot, shellRedirection.heartbeatAt, shellRedirection.statusAt = nil,nil,nil
        lp:SetAttribute("AttributeShellRedirectInitializing",true)
        lp:SetAttribute("AttributeShellRedirectOwner",shellRedirection.owner)
        lp:SetAttribute("AttributeShellRedirectHeartbeat",now)
        shellRedirection.active, shellRedirection.actors = true,{}
        shellRedirection.installAt = now
        local ok,err = pcall(function()
            local phrst = ReplicatedStorage:FindFirstChild("PHRST")
            local threads = phrst and phrst:FindFirstChild("Threads")
            for _,actor in ipairs(getactors()) do
                if threads and actor.Parent==threads and actor:IsA("Actor") and #shellRedirection.actors<8 then
                    local code = shellRedirection.actorSource:gsub("@ACTOR@",function() return string.format("%q",actor.Name) end)
                        :gsub("@OWNER@",function() return string.format("%q",shellRedirection.owner) end)
                        :gsub("@STEER@",function() return shellRedirection.steerSource end)
                    local installed = pcall(run_on_actor,actor,code)
                    if installed then shellRedirection.actors[#shellRedirection.actors+1]=actor end
                end
            end
        end)
        if not ok or #shellRedirection.actors==0 then
            shellRedirection.error = not ok and tostring(err) or "No accessible projectile Actor"
            shellRedirection.failed = true
            shellRedirection.stop()
            return
        end
        -- Refresh after installation, not from the stale frame-entry clock.
        now=os.clock()
        shellRedirection.installAt=now
        shellRedirection.heartbeatAt=now
        lp:SetAttribute("AttributeShellRedirectHeartbeat",now)
        lp:SetAttribute("AttributeShellRedirectInitializing",false)
    end
    local engaged = shellRedirection.isEngaged() == true
    if lp:GetAttribute("AttributeShellRedirectHeld")~=engaged then lp:SetAttribute("AttributeShellRedirectHeld",engaged) end
    local focused = shellRedirection.focused
    local record=shellRedirection.focusedRecord
    local part=record and record.part
    local valid = engaged and record and focused==record.player and focused.Parent==Players
        and focused.Character==record.character and record.humanoid.Health>0 and part.Parent
    local targetId=valid and focused.UserId or nil
    if lp:GetAttribute("AttributeShellRedirectTargetId")~=targetId then lp:SetAttribute("AttributeShellRedirectTargetId",targetId) end
    local shot=shellRedirection.shotSerial or 0
    if shellRedirection.publishedShot~=shot then
        shellRedirection.publishedShot=shot
        lp:SetAttribute("AttributeShellRedirectShot",shot)
    end
    if now-(shellRedirection.heartbeatAt or -1)>=0.25 then
        shellRedirection.heartbeatAt=now
        lp:SetAttribute("AttributeShellRedirectHeartbeat",now)
    end
    if now-(shellRedirection.statusAt or -1)>=0.5 then
        shellRedirection.statusAt=now
        shellRedirection.ready = 0
        for _,actor in ipairs(shellRedirection.actors) do
            local status = actor:GetAttribute("AttributeShellRedirectStatus")
            if status==shellRedirection.owner then
                shellRedirection.ready+=1
            elseif type(status)=="string" and status:sub(1,#shellRedirection.owner)==shellRedirection.owner then
                shellRedirection.error = status
            end
        end
    end
    if shellRedirection.error or shellRedirection.ready==0 and now-shellRedirection.installAt>2 then
        shellRedirection.error = shellRedirection.error or "Projectile Actors did not confirm steering access"
        shellRedirection.failed = true
        shellRedirection.stop()
    end
end

function shellRedirection.assign(object, property, value)
    if object[property]~=value then
        object[property]=value
        shellRedirection.visualWrites=(shellRedirection.visualWrites or 0)+1
    end
end
function shellRedirection.draw(cam, pixel)
    local show = Settings.ShellRedirection and not shellRedirection.failed and UserInputService:GetFocusedTextBox()==nil
    local visuals = shellRedirection.visuals
    if not show then
        if visuals then
            shellRedirection.assign(visuals.gui,"Enabled",false)
            shellRedirection.assign(visuals.tracer,"Visible",false)
            shellRedirection.assign(visuals.highlight,"Enabled",false)
            shellRedirection.assign(visuals.highlight,"Adornee",nil)
        end
        return
    end
    if not visuals then
        visuals = {}
        shellRedirection.visuals = visuals
        visuals.gui = Instance.new("ScreenGui")
        visuals.gui.Name="AttributeShellFocusOverlay"
        visuals.gui.IgnoreGuiInset=true; visuals.gui.ResetOnSpawn=false
        visuals.gui.DisplayOrder=999998
        visuals.gui.Parent=lp.PlayerGui
        visuals.circle=Instance.new("Frame")
        visuals.circle.Name="FocusRadius"; visuals.circle.BackgroundTransparency=1
        visuals.circle.AnchorPoint=Vector2.new(0.5,0.5); visuals.circle.BorderSizePixel=0
        visuals.circle.Parent=visuals.gui
        local corner=Instance.new("UICorner")
        corner.CornerRadius=UDim.new(0.5,0); corner.Parent=visuals.circle
        visuals.stroke=Instance.new("UIStroke")
        visuals.stroke.Thickness=1; visuals.stroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
        visuals.stroke.Parent=visuals.circle
        visuals.tracer=Instance.new("Frame")
        visuals.tracer.Name="FocusedPlayerTracer"; visuals.tracer.BorderSizePixel=0
        visuals.tracer.AnchorPoint=Vector2.new(0.5,0.5); visuals.tracer.BackgroundTransparency=0.18
        visuals.tracer.Visible=false; visuals.tracer.Parent=visuals.gui
        visuals.highlight=Instance.new("Highlight")
        visuals.highlight.Name="AttributeFocusedPlayer"; visuals.highlight.Enabled=false
        visuals.highlight.FillTransparency=0.85; visuals.highlight.OutlineTransparency=0.15
        visuals.highlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
        visuals.highlight.Parent=workspace
    end
    shellRedirection.assign(visuals.gui,"Enabled",true)
    shellRedirection.assign(visuals.circle,"Visible",Settings.ShellFocusCircle)
    if visuals.pixel~=pixel then
        visuals.pixel=pixel
        visuals.circle.Position=UDim2.fromOffset(pixel.X,pixel.Y)
        shellRedirection.visualWrites+=1
    end
    if visuals.radius~=Settings.ShellFocusRadius then
        visuals.radius=Settings.ShellFocusRadius
        visuals.circle.Size=UDim2.fromOffset(visuals.radius*2,visuals.radius*2)
        shellRedirection.visualWrites+=1
    end
    local engaged = shellRedirection.isEngaged()
    local focused = engaged and shellRedirection.focused
    local part = focused and shellRedirection.focusedPart
    local point,visible
    if part and part.Parent and focused.Character and part:IsDescendantOf(focused.Character) then
        point,visible=cam:WorldToViewportPoint(part.Position)
    end
    local tracked = visible == true and point.Z>0
    local color=Settings.ShellFocusColor
    shellRedirection.assign(visuals.stroke,"Color",tracked and color or THEME.TextPrimary)
    shellRedirection.assign(visuals.stroke,"Transparency",engaged and 0.2 or 0.6)
    shellRedirection.assign(visuals.highlight,"Adornee",tracked and Settings.ShellFocusHighlight and focused.Character or nil)
    shellRedirection.assign(visuals.highlight,"FillColor",color)
    shellRedirection.assign(visuals.highlight,"OutlineColor",color)
    shellRedirection.assign(visuals.highlight,"Enabled",tracked and Settings.ShellFocusHighlight)
    shellRedirection.assign(visuals.tracer,"Visible",tracked and Settings.ShellFocusTracer)
    shellRedirection.assign(visuals.tracer,"BackgroundColor3",color)
    if visuals.tracer.Visible then
        local start=Vector2.new(cam.ViewportSize.X*0.5,cam.ViewportSize.Y-4)
        local finish=Vector2.new(point.X,point.Y)
        if visuals.lineStart~=start or visuals.lineEnd~=finish then
            visuals.lineStart,visuals.lineEnd=start,finish
            local delta=finish-start
            visuals.tracer.Position=UDim2.fromOffset((start.X+finish.X)*0.5,(start.Y+finish.Y)*0.5)
            visuals.tracer.Size=UDim2.fromOffset(delta.Magnitude,1)
            visuals.tracer.Rotation=math.deg(math.atan2(delta.Y,delta.X))
            shellRedirection.visualWrites+=3
        end
    end
end
function shellRedirection.frame(cam)
    if shellRedirection.destroyed then return end
    if not Settings.ShellRedirection and not shellRedirection.active and not shellRedirection.visuals
        and not shellRedirection.failed then return end
    local source = Settings.Freecam and freecamActive and "Mouse" or Settings.AimSource
    local pixel = source=="Mouse" and UserInputService:GetMouseLocation() or cam.ViewportSize*0.5
    local now=os.clock()
    if shellRedirection.held and shellRedirection.heldKey~=Settings.ShellFocusKey then
        shellRedirection.release()
    end
    if shellRedirection.isEngaged() then
        -- Membership/visibility acquisition is capped; current bounds are still
        -- checked each rendered frame so leaving the circle clears immediately.
        if not shellRedirection.nextFocusScan or now>=shellRedirection.nextFocusScan then
            shellRedirection.nextFocusScan=now+0.05
            shellRedirection.refreshPlayers(now)
            local origin
            if Settings.ShellVisibilityCheck then
                refreshAimFilters(getActiveTank())
                origin=cam:ViewportPointToRay(pixel.X,pixel.Y).Origin
            end
            shellRedirection.select(cam,pixel,origin)
        else
            local record=shellRedirection.focusedRecord
            local valid=record and record.player.Parent==Players and record.player.Character==record.character
                and record.part.Parent and record.humanoid.Health>0 and not record.player.Neutral
                and record.player.Team~=nil and record.player.Team~=lp.Team
            local point,visible
            if valid then point,visible=cam:WorldToViewportPoint(record.part.Position) end
            if not valid or not visible or point.Z<=0
                or (point.X-pixel.X)^2+(point.Y-pixel.Y)^2>Settings.ShellFocusRadius^2 then
                shellRedirection.focused,shellRedirection.focusedPart,shellRedirection.focusedRecord=nil,nil,nil
            end
        end
    else
        shellRedirection.focused,shellRedirection.focusedPart,shellRedirection.focusedRecord=nil,nil,nil
        shellRedirection.nextFocusScan=nil
    end
    shellRedirection.draw(cam,pixel)
end
function shellRedirection.destroy()
    shellRedirection.destroyed=true
    shellRedirection.release()
    shellRedirection.stop()
    for _, connection in ipairs({shellRedirection.began,shellRedirection.ended,shellRedirection.focusLost,shellRedirection.tick}) do
        if connection then connection:Disconnect() end
    end
    local visuals=shellRedirection.visuals
    if visuals then visuals.highlight:Destroy(); visuals.gui:Destroy(); shellRedirection.visuals=nil end
end

-- Prefer vehicles/characters even behind scenery, then use the visible map
-- point so shots at ground pixels have a finite ballistic target.
local function getAimTarget(aimSource, veh)
    local cam = workspace.CurrentCamera
    local mouse = lp:GetMouse()
    if not cam then return Vector3.new(0, 0, 0), Vector3.new(), nil, Vector3.new(0, 1, 0), Vector3.new(0, 0, -1) end

    -- Freecam left-click aims where the cursor points, regardless of the normal
    -- camera/mouse selector used by the vehicle camera.
    if Settings.Freecam and freecamActive then aimSource = "Mouse" end

    refreshAimFilters(veh)

    local origin, direction

    if aimSource == "Mouse" then
        local pixel = UserInputService:GetMouseLocation()
        local cursorRay = cam:ViewportPointToRay(pixel.X, pixel.Y)
        origin = cursorRay.Origin
        direction = cursorRay.Direction * 100000
    else
        origin = cam.CFrame.Position
        direction = cam.CFrame.LookVector * 100000
    end

    local ray = nil
    -- A freecam cursor selects the first visible world surface. The normal
    -- vehicle mode still prioritizes characters and vehicles through scenery.
    if aimTargetCount > 0 and not (Settings.Freecam and freecamActive) then
        local unit = direction.Unit
        local traveled = 0
        while traveled < direction.Magnitude do
            local length = math.min(10000, direction.Magnitude - traveled)
            ray = workspace:Raycast(origin + unit * traveled, unit * length, aimIncludeParams)
            if ray then break end
            traveled = traveled + length
        end
    end
    if not ray then
        local unit = direction.Unit
        local traveled = 0
        while traveled < direction.Magnitude do
            local length = math.min(10000, direction.Magnitude - traveled)
            ray = workspace:Raycast(origin + unit * traveled, unit * length, aimWorldParams)
            if ray then break end
            traveled = traveled + length
        end
    end
    if ray then
        local targetPos = ray.Position
        local targetPart = ray.Instance
        local targetVel = targetPart and targetPart:IsA("BasePart") and targetPart.AssemblyLinearVelocity or Vector3.new()
        return targetPos, targetVel, targetPart, ray.Normal, direction.Unit
    else
        -- An unobstructed sightline extends to the full aim range.
        return origin + direction, Vector3.new(), nil, Vector3.new(0, 1, 0), direction.Unit
    end
end

local turretPitchCache = setmetatable({}, { __mode = "k" })
local function getTurretPitchLimits(turret)
    local info = turret and turret:FindFirstChild("TurretInfo")
    if not info then return math.rad(-85), math.rad(85) end
    local limits = turretPitchCache[info]
    if not limits then
        local ok, data = pcall(require, info)
        local vertical = ok and data and data.anglelimits and data.anglelimits.vertical
        limits = {
            math.rad(vertical and tonumber(vertical[1]) or -85),
            math.rad(vertical and tonumber(vertical[2]) or 85)
        }
        turretPitchCache[info] = limits
    end
    return limits[1], limits[2]
end

local clearanceParams = RaycastParams.new()
clearanceParams.FilterType = Enum.RaycastFilterType.Exclude
clearanceParams.IgnoreWater = true
clearanceParams.RespectCanCollide = false
pcall(function() clearanceParams.CollisionGroup = "Projectile" end)
local clearanceVehicle, clearanceCharacter = nil, nil
local function getClearanceParams(veh)
    if clearanceVehicle ~= veh or clearanceCharacter ~= lp.Character then
        clearanceVehicle, clearanceCharacter = veh, lp.Character
        clearanceParams.FilterDescendantsInstances = { veh, lp.Character }
    end
    return clearanceParams
end

local function pathReachesTarget(startPos, targetPos, direction, speed, gravityY, drag, params, maxTime)
    local offset = targetPos - startPos
    local horizontalDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude
    local horizontalSpeed = Vector3.new(direction.X, 0, direction.Z).Magnitude * speed
    if horizontalDistance < 0.1 or horizontalSpeed < 0.1 then return false end
    local flightTime = ballistics.time(horizontalDistance,horizontalSpeed,drag)
    if not flightTime or flightTime > (maxTime or 60) then return false end
    local steps = ballistics.steps(flightTime,gravityY,drag,speed)
    local tolerance = math.max(12, horizontalDistance * 0.002)
    local finish = ballistics.trace(startPos,direction*speed,gravityY,drag,params,steps,flightTime/steps)
    return (finish-targetPos).Magnitude <= tolerance
end

local function solveDraggedArcs(startPos, targetPos, speed, gravityY, drag, minPitch, maxPitch, maxTime)
    local offset = targetPos - startPos
    local horizontal = Vector3.new(offset.X, 0, offset.Z)
    local range = horizontal.Magnitude
    if range < 0.1 or speed <= 0 then return nil, nil end
    local unit = horizontal.Unit
    -- Solve both physical roots before applying mechanical limits. A root
    -- outside the gun window must not cause the remaining high root to be
    -- incorrectly labelled as the low root.
    local minimumVX = drag*range/(1-math.exp(-drag*(maxTime or 60)))
    if minimumVX > speed then return nil, nil end
    local limit = math.acos(math.clamp(minimumVX/speed,0,1))
    local lowLimit, highLimit = -limit, limit
    local function heightError(pitch)
        local vx = speed * math.cos(pitch)
        local remaining = 1 - drag * range / vx
        if remaining <= 0 then return nil end
        local t = -math.log(remaining) / drag
        return speed * math.sin(pitch) * t + 0.5 * gravityY * t * t - offset.Y
    end
    local a,b = lowLimit,highLimit
    for _ = 1, 40 do
        local l,r = a+(b-a)/3,b-(b-a)/3
        if heightError(l) < heightError(r) then a=l else b=r end
    end
    local peak = (a+b)*0.5
    if heightError(peak) < -0.01 then return nil,nil end
    local function rootBetween(a,b)
        local fa,fb = heightError(a),heightError(b)
        if math.abs(fa) < 0.01 then b=a
        elseif math.abs(fb) < 0.01 then a=b
        elseif fa*fb > 0 then return nil end
        for _ = 1, 28 do
            local mid=(a+b)*0.5
            local fm=heightError(mid)
            if fa*fm <= 0 then b=mid else a,fa=mid,fm end
        end
        local pitch=(a+b)*0.5
        return { direction=(unit*math.cos(pitch)+Vector3.yAxis*math.sin(pitch)).Unit,pitch=pitch }
    end
    return rootBetween(lowLimit,peak),rootBetween(peak,highLimit)
end

local function getLaunchDirection(startPos, targetPos, targetPart, speed, gravityY, drag,
    preserveBarrelPitch, boreDir, minPitch, maxPitch, params, maxTime, up)
    local offset = targetPos - startPos
    if offset.Magnitude < 0.1 then return nil, "unreachable" end
    if not targetPart then
        -- Sky is a bearing, not a requested landing coordinate.
        if preserveBarrelPitch and boreDir then
            local horizontal = Vector3.new(offset.X,0,offset.Z)
            if horizontal.Magnitude < 0.1 then return boreDir,"barrel" end
            local vertical = math.clamp(boreDir.Y,-0.999,0.999)
            return (horizontal.Unit*math.sqrt(1-vertical*vertical)+Vector3.yAxis*vertical).Unit,"barrel"
        end
        return offset.Unit,"bearing"
    end

    local draggedLow,draggedHigh
    if drag and drag > 1e-5 then
        draggedLow,draggedHigh = solveDraggedArcs(startPos,targetPos,speed,gravityY,drag,minPitch,maxPitch,maxTime)
    end
    local range = Vector3.new(offset.X,0,offset.Z).Magnitude
    local margin = math.rad(0.25)
    local physical,legal,inLifetime = false,false,false
    local blockedPreview
    local function candidate(high)
        local direction,possible,pitch
        if drag and drag > 1e-5 then
            local root
            if high then root = draggedHigh else root = draggedLow end
            direction,possible,pitch = root and root.direction,root ~= nil,root and root.pitch
        else
            direction,possible,pitch = solveBallistic(startPos,targetPos,speed,gravityY,high)
        end
        if not possible or not direction then return nil end
        physical = true
        if up then pitch = math.asin(math.clamp(direction:Dot(up),-1,1)) end
        if not pitch or pitch < minPitch-margin or pitch > maxPitch+margin then return nil end
        legal = true
        local time = ballistics.time(range,Vector3.new(direction.X,0,direction.Z).Magnitude*speed,drag)
        if not time or time > (maxTime or 60) then return nil end
        inLifetime = true
        if pathReachesTarget(startPos,targetPos,direction,speed,gravityY,drag,params,maxTime) then
            return direction
        end
        blockedPreview = blockedPreview or direction
    end
    -- One policy for normal view and freecam. Return the clear low solution
    -- immediately; neither remembered settings nor barrel pitch can force high.
    local low = candidate(false)
    if low then return low,"low" end
    local high = candidate(true)
    if high then return high,"high" end
    if not physical then return nil,"Target exceeds ammunition range" end
    if not legal then return nil,"target outside gun elevation" end
    if not inLifetime then return nil,"flight exceeds ammunition lifetime" end
    -- Only display a collision-shortened candidate; never drive it or fire it.
    return nil,"trajectory blocked",blockedPreview
end

-- Canonical MTC Explosion Blast Radius Calculator
local blastDiameterCache = setmetatable({}, { __mode = "k" })
local function getExplosionRadius(shellData)
    if type(shellData) ~= "table" or not shellData.ExplosiveMass or shellData.ExplosiveMass <= 0 then
        return 0
    end
    if blastDiameterCache[shellData] ~= nil then return blastDiameterCache[shellData] end

    local diam = 0
    if GlobalConstants and type(GlobalConstants.GetExplosionDiameter) == "function" then
        diam = GlobalConstants.GetExplosionDiameter(shellData) * (shellData.blastradiusmult or 1)
    else
        local airDensity = (GlobalConstants and GlobalConstants.AirDensity) or 1.2
        local expConst = (GlobalConstants and GlobalConstants.ExplosiveConstant) or 0.07
        diam = math.min(1 / expConst * (shellData.ExplosiveMass / airDensity) ^ 0.3333333333333333 / 0.1, 500 * (shellData.ExpCapMult or 1)) * (shellData.blastradiusmult or 1)
    end

    if shellData.HESH then
        diam = diam * 0.8
    elseif shellData.ShellType == "HEAT" then
        diam = diam * 0.66
    end

    diam = math.max(0, diam)
    blastDiameterCache[shellData] = diam
    return diam
end

-- ===================================================================
-- VISUALIZERS (WORLD-SPACE BEAM PREVIEW)
-- ===================================================================

local visualContainer = Instance.new("Folder")
visualContainer.Name = "AutoLeadVisualizer"
visualContainer.Parent = workspace.Terrain

local beamAttachments = {}
local function makeTrajectoryBeam(name, color)
    local origin = Instance.new("Attachment")
    origin.Name = name .. "Origin"
    origin.Parent = workspace.Terrain
    local impact = Instance.new("Attachment")
    impact.Name = name .. "Impact"
    impact.Parent = workspace.Terrain
    beamAttachments[#beamAttachments + 1] = origin
    beamAttachments[#beamAttachments + 1] = impact
    local beam = Instance.new("Beam")
    beam.Name = name
    beam.Attachment0 = origin
    beam.Attachment1 = impact
    beam.Color = ColorSequence.new(color, color:Lerp(THEME.FlightEnd, 0.35))
    beam.Width0 = 0.12
    beam.Width1 = 0.18
    beam.Transparency = NumberSequence.new(0.14)
    beam.Segments = 20
    beam.FaceCamera = true
    beam.LightEmission = 0
    beam.Enabled = false
    beam.Parent = visualContainer
    local outline = beam:Clone()
    outline.Name = name .. "Outline"
    outline.Color = ColorSequence.new(THEME.Ink)
    outline.Transparency = NumberSequence.new(0.12)
    outline.ZOffset = -0.02
    outline.Parent = visualContainer
    beam:GetPropertyChangedSignal("Enabled"):Connect(function() outline.Enabled = beam.Enabled end)
    return { origin = origin, impact = impact, beam = beam, outline = outline, color = color }
end

local borePreview = makeTrajectoryBeam("BoreTrajectory", THEME.TrajectoryBore)
local leadPreview = makeTrajectoryBeam("LeadTrajectory", THEME.TrajectoryLead)

local function setBeamColor(preview, color)
    if preview.color ~= color then
        preview.beam.Color = ColorSequence.new(color, color:Lerp(THEME.FlightEnd, 0.35))
        preview.color = color
    end
end

local function tangentFrame(position, velocity)
    local tangent = velocity.Magnitude > 0.001 and velocity.Unit or Vector3.xAxis
    local reference = math.abs(tangent:Dot(Vector3.yAxis)) > 0.95 and Vector3.zAxis or Vector3.yAxis
    local back = tangent:Cross(reference).Unit
    local up = back:Cross(tangent).Unit
    return CFrame.fromMatrix(position, tangent, up, back)
end

local function showTrajectoryBeam(preview, startPos, endPos, startVelocity, endVelocity, flightTime)
    if not endPos or flightTime <= 0 then
        preview.beam.Enabled = false
        return
    end
    preview.origin.WorldCFrame = tangentFrame(startPos, startVelocity)
    preview.impact.WorldCFrame = tangentFrame(endPos, endVelocity)
    -- A short-range high lob can have a very tall apex. Distance-based handle
    -- clamping flattened these otherwise-valid arcs.
    preview.beam.CurveSize0 = startVelocity.Magnitude * flightTime / 3
    preview.beam.CurveSize1 = endVelocity.Magnitude * flightTime / 3
    preview.outline.CurveSize0 = preview.beam.CurveSize0
    preview.outline.CurveSize1 = preview.beam.CurveSize1
    preview.outline.Width0 = preview.beam.Width0 + 0.12
    preview.outline.Width1 = preview.beam.Width1 + 0.12
    preview.beam.Enabled = true
end

-- One thin, non-queryable disc is cheaper and less cluttered than perimeter
-- adornments. Its displayed radius is capped; the shell's actual blast radius
-- remains unchanged and is still used for the occupant check.
local blastZone = Instance.new("Part")
blastZone.Name = "BlastZone"
blastZone.Shape = Enum.PartType.Cylinder
blastZone.Anchored = true
blastZone.CanCollide = false
blastZone.CanTouch = false
blastZone.CanQuery = false
blastZone.CastShadow = false
blastZone.Material = Enum.Material.SmoothPlastic
blastZone.Color = THEME.BlastClear
blastZone.Transparency = 0.42
blastZone.Size = Vector3.new(0.12, 12, 12)
blastZone.Parent = visualContainer
blastZone.Transparency = 1

local blastDistance = {}
function blastDistance.scaleLabel(gui, label, position)
    local cam = workspace.CurrentCamera
    if not cam then return end
    local depth = math.max(1, -cam.CFrame:PointToObjectSpace(position).Z)
    local lens = math.tan(math.rad(70) / 2) / math.max(0.01, math.tan(math.rad(cam.FieldOfView) / 2))
    local size = math.clamp(18 * math.sqrt(120 * lens / depth), 11, 18)
    if math.abs(label.TextSize - size) > 0.05 then
        label.TextSize = size
        gui.Size = UDim2.fromOffset(260 * size / 14, 26 * size / 14)
    end
end
blastDistance.gui = Instance.new("BillboardGui")
blastDistance.gui.Name = "BlastDistance"
blastDistance.gui.Adornee = blastZone
blastDistance.gui.Size = UDim2.fromOffset(168, 25)
blastDistance.gui.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
blastDistance.gui.AlwaysOnTop = true
blastDistance.gui.Enabled = false
blastDistance.gui.Parent = visualContainer
blastDistance.text = Instance.new("TextLabel")
-- The billboard is only a positioning canvas. Its backing hugs the glyphs,
-- including when content or distance-based TextSize changes.
blastDistance.text.AutomaticSize = Enum.AutomaticSize.XY
blastDistance.text.Size = UDim2.fromOffset(0, 0)
blastDistance.text.AnchorPoint = Vector2.new(0.5, 0.5)
blastDistance.text.Position = UDim2.fromScale(0.5, 0.5)
blastDistance.text.TextWrapped = false
blastDistance.text.BackgroundTransparency = 1
blastDistance.text.Font = Enum.Font.GothamMedium
blastDistance.text.TextSize = 13
blastDistance.text.TextColor3 = Color3.new(1, 1, 1)
blastDistance.text.TextStrokeTransparency = 0.25
blastDistance.text.Parent = blastDistance.gui
stylePanel(blastDistance.text)
do
    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 3)
    padding.PaddingRight = UDim.new(0, 3)
    padding.PaddingTop = UDim.new(0, 1)
    padding.PaddingBottom = UDim.new(0, 1)
    padding.Parent = blastDistance.text
    blastDistance.text:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 2)
end

local blastOverlapParams = OverlapParams.new()
blastOverlapParams.FilterType = Enum.RaycastFilterType.Include
blastOverlapParams.MaxParts = 100
local blastOccupancyTime, blastOccupancyCenter, blastOccupancyRadius = 0, nil, 0
local blastOccupied = false
local function hasBlastOccupant(center, trueRadius, veh)
    local now = os.clock()
    if blastOccupancyCenter and now - blastOccupancyTime < 0.15
        and (blastOccupancyCenter - center).Magnitude < 4
        and math.abs(blastOccupancyRadius - trueRadius) < 1 then
        return blastOccupied
    end
    blastOccupancyTime, blastOccupancyCenter, blastOccupancyRadius = now, center, trueRadius
    local included = {}
    local vehicles = workspace:FindFirstChild("SpawnedVehicles")
    local characters = workspace:FindFirstChild("SpawnedPlayers")
    if vehicles then included[#included + 1] = vehicles end
    if characters then included[#included + 1] = characters end
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character and not (characters and player.Character:IsDescendantOf(characters)) then
            included[#included + 1] = player.Character
        end
    end
    if #included == 0 then blastOccupied = false; return false end
    blastOverlapParams.FilterDescendantsInstances = included
    local ownCharacter = lp.Character
    blastOccupied = false
    for _, part in ipairs(workspace:GetPartBoundsInRadius(center, trueRadius, blastOverlapParams)) do
        if not (veh and part:IsDescendantOf(veh))
            and not (ownCharacter and part:IsDescendantOf(ownCharacter)) then
            blastOccupied = true
            break
        end
    end
    return blastOccupied
end

-- Fixed HUD card; it no longer follows the cursor or world target.
local impactHud = Instance.new("Frame")
impactHud.Name = "ImpactInfoHUD"
impactHud.Size = UDim2.new(0, 230, 0, 50)
impactHud.AnchorPoint = Vector2.new(0, 1)
impactHud.Position = UDim2.new(0, 14, 1, -14)
impactHud.BackgroundTransparency = 1
impactHud.Visible = false
impactHud.Parent = screenGui

local infoCard = Instance.new("Frame")
infoCard.Size = UDim2.new(1, 0, 1, 0)
infoCard.BackgroundColor3 = THEME.Background
infoCard.BackgroundTransparency = 0.2
infoCard.BorderSizePixel = 0
infoCard.Parent = impactHud

local infoCorner = Instance.new("UICorner")
infoCorner.CornerRadius = UDim.new(0, 6)
infoCorner.Parent = infoCard

local infoStroke = Instance.new("UIStroke")
infoStroke.Color = THEME.Border
infoStroke.Thickness = 1
infoStroke.Parent = infoCard

local infoDistLabel = Instance.new("TextLabel")
infoDistLabel.Name = "DistLabel"
infoDistLabel.Size = UDim2.new(1, -12, 0, 22)
infoDistLabel.Position = UDim2.new(0, 6, 0, 3)
infoDistLabel.BackgroundTransparency = 1
infoDistLabel.TextColor3 = THEME.TextPrimary
infoDistLabel.TextSize = 13
infoDistLabel.Font = Enum.Font.GothamBold
infoDistLabel.TextXAlignment = Enum.TextXAlignment.Center
infoDistLabel.Text = "0m"
infoDistLabel.Parent = infoCard

local infoSubLabel = Instance.new("TextLabel")
infoSubLabel.Name = "SubLabel"
infoSubLabel.Size = UDim2.new(1, -12, 0, 18)
infoSubLabel.Position = UDim2.new(0, 6, 0, 25)
infoSubLabel.BackgroundTransparency = 1
infoSubLabel.TextColor3 = THEME.TextSecondary
infoSubLabel.TextSize = 11
infoSubLabel.Font = Enum.Font.GothamMedium
infoSubLabel.TextXAlignment = Enum.TextXAlignment.Center
infoSubLabel.Text = "HE // 0.00s"
infoSubLabel.Parent = infoCard
stylePanel(infoCard)
stylePanel(infoDistLabel)
stylePanel(infoSubLabel)

local function hideBlastZone()
    if blastZone.Transparency ~= 1 then blastZone.Transparency = 1 end
    if blastDistance.gui.Enabled then blastDistance.gui.Enabled = false end
end

local function showBlastZone(center, normal, trueRadius, color, distanceStuds, eta)
    normal = normal.Magnitude > 0.1 and normal.Unit or Vector3.yAxis
    local right = normal:Cross(Vector3.zAxis)
    if right.Magnitude < 0.1 then right = normal:Cross(Vector3.xAxis) end
    right = right.Unit
    local displayRadius = math.clamp(trueRadius, 6, 24)
    blastZone.Size = Vector3.new(0.12, displayRadius * 2, displayRadius * 2)
    blastZone.CFrame = CFrame.fromMatrix(center + normal * 0.18, normal, right)
    blastZone.Color = color
    blastZone.Transparency = 0.42
    blastDistance.gui.Enabled = Settings.ShowDistance and distanceStuds ~= nil
    if blastDistance.gui.Enabled then
        local text = string.format("%.0f m  ·  %s", distanceStuds / 2.7777778,
            eta and string.format("ETA ~%.1fs", eta) or "no valid arc")
        if blastDistance.text.Text ~= text then blastDistance.text.Text = text end
    end
    return displayRadius
end

local lastPreviewState = nil
local function hideVisuals()
    lastPreviewState = nil
    if borePreview.beam.Enabled then borePreview.beam.Enabled = false end
    if leadPreview.beam.Enabled then leadPreview.beam.Enabled = false end
    hideBlastZone()
    if impactHud.Visible then impactHud.Visible = false end
end

-- Reuse raycast settings while seated; allocating and configuring them every
-- rendered frame costs more than moving the two existing Beam attachments.
local trajectoryParams = RaycastParams.new()
trajectoryParams.FilterType = Enum.RaycastFilterType.Exclude
trajectoryParams.IgnoreWater = true
trajectoryParams.RespectCanCollide = false
pcall(function() trajectoryParams.CollisionGroup = "Projectile" end)
local trajectoryVehicle = nil
local trajectoryCharacter = nil
local function getTrajectoryParams(veh)
    local character = lp.Character
    if trajectoryVehicle ~= veh or trajectoryCharacter ~= character then
        trajectoryVehicle = veh
        trajectoryCharacter = character
        trajectoryParams.FilterDescendantsInstances = { veh, character }
    end
    return trajectoryParams
end

-- Follow the same physical path used for the preview, stopping at the first
-- collidable map hit. Raycasts are batched across a few fine physics steps.
local function traceTrajectory(startPos, initialVel, gravityY, drag, params, maxSteps, dt)
    local duration = maxSteps * dt
    local steps = ballistics.steps(duration,gravityY,drag,initialVel.Magnitude)
    local previous, previousTime = startPos, 0
    local velocity = initialVel
    for i = 1, steps do
        local t = duration*i/steps
        local point, nextVelocity = ballistics.sample(startPos,initialVel,gravityY,drag,t)
        local hit = workspace:Raycast(previous,point-previous,params)
        if hit then
            local fraction = math.clamp((hit.Position-previous).Magnitude/math.max((point-previous).Magnitude,1e-8),0,1)
            local impactTime = previousTime+(t-previousTime)*fraction
            local _, impactVelocity = ballistics.sample(startPos,initialVel,gravityY,drag,impactTime)
            return hit.Position,hit,impactTime,i,impactVelocity
        end
        previous,previousTime,velocity = point,t,nextVelocity
    end
    return previous,nil,duration,steps,velocity
end
ballistics.trace = traceTrajectory

-- Main Render Loop
local aimCache = { direction = nil, vehicle = nil, weapon = nil, targetPos = nil, updated = 0, reason = "waiting for weapon", alignment = 0, clearance = false }
local refreshAimCache = nil -- Assigned below; refresh before drawing each frame.
local visualDiagnostics = { finiteTarget = false, endpointError = nil, flightTime = 0, hit = nil, traceCount = 0 }
local previousVisualFrame = 0
local VISUAL_RENDER_NAME = "AutoLeadVisualLateStep"
RunService:BindToRenderStep(VISUAL_RENDER_NAME, FREECAM_PRIORITY + 2, function()
    local ok, failure = xpcall(function()
    local frameTime = os.clock()
    -- Presentation follows camera movement even when the ballistic cache hits.
    if blastDistance.gui.Enabled then
        blastDistance.scaleLabel(blastDistance.gui, blastDistance.text, blastZone.Position)
    end
    visualDiagnostics.frameMs = previousVisualFrame > 0 and (frameTime - previousVisualFrame) * 1000 or 0
    previousVisualFrame = frameTime
    if refreshAimCache then refreshAimCache() end
    if Settings.ShellRedirection or not Settings.EnableAutoLead or not (Settings.Trajectory or Settings.ShowBallistic
        or Settings.ExplosionRadius or Settings.ShowDistance or Settings.FlightTimer) then
        hideVisuals()
        visualDiagnostics.blastVisible = false
        visualDiagnostics.blastColor = nil
        visualDiagnostics.blastOccupied = false
        visualDiagnostics.plannedAim = false
        visualDiagnostics.assistReady = false
        visualDiagnostics.hit = nil
        visualDiagnostics.rays = 0
        visualDiagnostics.lastMs = 0
        visualDiagnostics.flightTime = 0
        return
    end
    -- The Beam is engine-rendered; refreshing its endpoint on the same frame as
    -- the cursor avoids the visible 15 Hz stepping of the old preview timer.
    local visualStartTime = os.clock()

    local veh = aimCache.vehicle
    local wData = aimCache.weapon
    if not veh or not wData or not aimCache.targetPos or os.clock() - aimCache.updated > 0.25 then
        hideVisuals()
        visualDiagnostics.blastVisible = false
        visualDiagnostics.blastColor = nil
        visualDiagnostics.blastOccupied = false
        visualDiagnostics.plannedAim = false
        visualDiagnostics.assistReady = false
        visualDiagnostics.hit = nil
        return
    end

    local firePoint = wData.firePoint
    local muzzle = wData.muzzle
    local startPos = firePoint and firePoint.WorldPosition or muzzle.Position
    local forwardDir = getBoreForwardDirection(wData)
    local tankVel = muzzle.AssemblyLinearVelocity

    local muzzleSpeed = wData.speed or 1200
    local gravityY = wData.gravity or defaultGravity
    local drag = wData.drag or 0

    local targetPos = aimCache.targetPos
    local targetVel = aimCache.targetVel
    local targetPart = aimCache.targetPart
    local previous = lastPreviewState
    local options = (Settings.Trajectory and 1 or 0) + (Settings.ShowBallistic and 2 or 0)
        + (Settings.ExplosionRadius and 4 or 0) + (Settings.ShowDistance and 8 or 0)
        + (Settings.FlightTimer and 16 or 0)
    -- If the mouse, barrel, target, and presentation controls are unchanged,
    -- retain the engine-rendered Beam. Moving the cursor invalidates this cache
    -- immediately; the 0.2-second timeout still catches moving obstacles.
    if previous and frameTime - previous.time < 0.2 and previous.vehicle == veh
        and previous.weapon == wData.weapon and previous.muzzle == muzzle
        and previous.loaded == wData.loaded and previous.arc == aimCache.arc
        and previous.reason == aimCache.reason and previous.targetPart == targetPart
        and previous.options == options and previous.speed == muzzleSpeed
        and previous.gravity == gravityY and previous.drag == drag
        and (previous.startPos - startPos).Magnitude < 0.001
        and (previous.forwardDir - forwardDir).Magnitude < 0.00001
        and (previous.tankVel - tankVel).Magnitude < 0.001
        and ((previous.direction == nil and aimCache.direction == nil)
            or (previous.direction and aimCache.direction
                and (previous.direction - aimCache.direction).Magnitude < 0.00001))
        and (previous.targetPos - targetPos).Magnitude < 0.001
        and (previous.targetVel - targetVel).Magnitude < 0.001 then
        return
    end
    lastPreviewState = {
        time = frameTime, vehicle = veh, weapon = wData.weapon, muzzle = muzzle,
        loaded = wData.loaded, arc = aimCache.arc, reason = aimCache.reason,
        targetPart = targetPart, options = options, speed = muzzleSpeed,
        gravity = gravityY, drag = drag, startPos = startPos,
        forwardDir = forwardDir, tankVel = tankVel,
        direction = aimCache.direction, targetPos = targetPos, targetVel = targetVel
    }
    visualDiagnostics.traceCount = visualDiagnostics.traceCount + 1
    local rayParams = getTrajectoryParams(veh)
    local targetOffset = targetPos - startPos
    local estDist = targetOffset.Magnitude
    local estTime = estDist / math.max(muzzleSpeed, 1)
    local predictedTarget = targetPos + targetVel * estTime
    local previewDirection = aimCache.direction or aimCache.previewDirection
    local idealInitialVel = previewDirection and (tankVel + previewDirection * muzzleSpeed) or nil
    local horizontalRange = Vector3.new(predictedTarget.X - startPos.X, 0, predictedTarget.Z - startPos.Z).Magnitude
    local previewVelocity = idealInitialVel or (tankVel + forwardDir * muzzleSpeed)
    local horizontalSpeed = Vector3.new(previewVelocity.X, 0, previewVelocity.Z).Magnitude
    local lifetime = ballistics.lifetime(wData.shellData)
    local targetTime = ballistics.time(horizontalRange,horizontalSpeed,drag)
    local flightTime = targetPart and math.min(lifetime,math.max(0.1,(targetTime or estTime)+0.65))
        or math.min(lifetime,math.clamp(6500/math.max(muzzleSpeed,1),2,12))
    if aimCache.arc == "barrel" or previewDirection == nil then
        -- A nearby cursor pixel is only a bearing in artillery mode. Preview
        -- the shell's natural airborne time instead of stopping at that pixel.
        -- An invalid finite aim also needs enough time to find the true bore
        -- impact, so its red area can join the physical trajectory endpoint.
        local gravityMagnitude = math.max(math.abs(gravityY), 1)
        local airborneTime = 2 * math.max(previewVelocity.Y, 0) / gravityMagnitude
        flightTime = math.min(lifetime,math.max(flightTime, airborneTime + 3))
    end
    -- Coarse preview integration; the firing aim is calculated separately.
    -- Collision rays still cover each batch of steps to find the impact.
    local simSteps = math.clamp(math.ceil(flightTime / 0.18), 8, 120)
    local simDt = flightTime / simSteps

    local aimRequested = isAdaptiveAimActive()
    local plannedAim = aimRequested and previewDirection ~= nil
    local assistedAim = aimRequested and aimCache.direction ~= nil and aimCache.reason == "ready"
    -- An invalid finite cursor target must not silently become the bore path.
    -- Keep its red target marker; show the bore only when explicitly enabled
    -- or when no assisted finite target is being requested.
    local invalidCursorTarget = aimRequested and not plannedAim and targetPart ~= nil
    local drawBore = Settings.ShowBallistic or not aimRequested
        or (not plannedAim and not targetPart)

    -- 1. Optional true barrel path. Invalid finite cursor targets do not
    -- automatically replace their requested preview with this path.
    local boreEnd, boreHit, boreTime, boreRays, boreEndVel = nil, nil, 0, 0, nil
    if drawBore then
        local initialBoreVel = tankVel + forwardDir * muzzleSpeed
        boreEnd, boreHit, boreTime, boreRays, boreEndVel = traceTrajectory(startPos, initialBoreVel, gravityY, drag, rayParams, simSteps, simDt)
        if Settings.Trajectory or Settings.ShowBallistic then
            showTrajectoryBeam(borePreview, startPos, boreEnd, initialBoreVel, boreEndVel, boreTime)
            setBeamColor(borePreview, aimRequested and not plannedAim and targetPart
                and THEME.BlastBlocked or THEME.TrajectoryBore)
        else
            borePreview.beam.Enabled = false
        end
    else
        borePreview.beam.Enabled = false
    end

    -- 2. Auto-lead impact cue uses the same world-space preview as the bore.
    local leadEnd, leadHit, leadTime, leadRays, leadEndVel = nil, nil, 0, 0, nil

    local leadDisplayEnd = nil
    if plannedAim then
        leadEnd, leadHit, leadTime, leadRays, leadEndVel = traceTrajectory(startPos, idealInitialVel, gravityY, drag, rayParams, simSteps, simDt)
        leadDisplayEnd = leadHit and leadEnd or (targetPart and predictedTarget or leadEnd)
        if Settings.Trajectory then
            local displayTime = leadHit and leadTime or math.min(lifetime,math.max(0.05,targetTime or leadTime))
            showTrajectoryBeam(leadPreview, startPos, leadDisplayEnd, idealInitialVel, leadEndVel, displayTime)
        else
            leadPreview.beam.Enabled = false
        end
    else
        leadPreview.beam.Enabled = false
    end

    local activeHit, activeEnd, activeTime
    if plannedAim then
        activeHit, activeEnd = leadHit, leadEnd
        activeTime = leadHit and leadTime or flightTime
    else
        activeHit, activeEnd = boreHit, boreEnd
        activeTime = boreHit and boreTime or flightTime
    end
    visualDiagnostics.finiteTarget = targetPart ~= nil
    visualDiagnostics.flightTime = activeTime
    visualDiagnostics.hit = activeHit and activeHit.Instance:GetFullName() or nil
    visualDiagnostics.endpointError = targetPart and activeEnd and (activeEnd - predictedTarget).Magnitude or nil
    visualDiagnostics.rays = boreRays + leadRays
    visualDiagnostics.plannedAim = plannedAim
    visualDiagnostics.assistReady = assistedAim

    -- Blue/green require both a clear path and local firing readiness. A
    -- mathematical solution alone must not advertise that the gun can fire.
    local blastRadius = getExplosionRadius(wData.shellData) * 0.5
    local blastPosition = invalidCursorTarget and predictedTarget or (plannedAim and leadDisplayEnd or boreEnd)
    local blastNormal = invalidCursorTarget and aimCache.hitNormal
        or (activeHit and activeHit.Normal) or aimCache.hitNormal or Vector3.yAxis
    local impactTolerance = math.max(12, horizontalRange * 0.002)
    local possible = assistedAim and activeHit ~= nil
        and (not targetPart or (activeHit.Position - predictedTarget).Magnitude <= impactTolerance)
    if not aimRequested and activeHit and targetPart then
        possible = not aimCache.fireBlock
            and (activeHit.Position - predictedTarget).Magnitude <= impactTolerance
    end
    visualDiagnostics.blastVisible = false
    visualDiagnostics.blastColor = nil
    visualDiagnostics.blastOccupied = false
    local occupied = possible and blastPosition and blastRadius > 0 and Settings.ExplosionRadius
        and hasBlastOccupant(blastPosition, blastRadius, veh) or false
    local state = not possible and "red" or occupied and "green" or "blue"
    local color = state == "red" and THEME.BlastBlocked
        or state == "green" and THEME.BlastOccupied or THEME.BlastClear
    visualDiagnostics.pathState = state
    if plannedAim and leadPreview.beam.Enabled then
        setBeamColor(leadPreview, color)
    elseif borePreview.beam.Enabled and not plannedAim then
        setBeamColor(borePreview, color)
    end
    if Settings.ExplosionRadius and blastRadius > 0 and blastPosition then
        visualDiagnostics.blastVisualRadius = showBlastZone(blastPosition, blastNormal, blastRadius, color,
            (blastPosition - startPos).Magnitude, plannedAim and activeTime or nil)
        visualDiagnostics.blastVisible = true
        visualDiagnostics.blastColor = state
        visualDiagnostics.blastOccupied = occupied
    else
        hideBlastZone()
        visualDiagnostics.blastVisualRadius = nil
    end
    if Settings.ShowDistance or Settings.FlightTimer then
        local distMeters = activeHit and (activeHit.Position - startPos).Magnitude / 2.7777778 or nil
        local offsetMeters = targetPart and activeEnd and (activeEnd - targetPos).Magnitude / 2.7777778 or nil
        if aimRequested and not assistedAim then
            infoDistLabel.Text = plannedAim and (aimCache.fireBlock and "WEAPON NOT READY"
                    or (not aimCache.direction and "PATH BLOCKED" or "ALIGN BARREL"))
                or (invalidCursorTarget and "NO VALID ARC TO CURSOR" or "NO VALID SHOT - BORE PATH")
            infoSubLabel.Text = aimCache.direction and plannedAim and not aimCache.fireBlock
                and string.format("Elevation %.1f° / %.1f°  |  turn %.1f°",
                    aimCache.barrelElevation or 0, aimCache.launchElevation or 0, aimCache.bearingError or 0)
                or aimCache.reason
        else
            if aimCache.arc == "barrel" then
                infoDistLabel.Text = distMeters
                    and string.format("BARREL %.1f°  IMPACT %.0fm", aimCache.barrelElevation or 0, distMeters)
                    or string.format("BARREL %.1f°  NO IMPACT", aimCache.barrelElevation or 0)
            elseif aimCache.arc == "high" then
                infoDistLabel.Text = distMeters
                    and string.format("LOB %.1f°  IMPACT %.0fm", aimCache.launchElevation or 0, distMeters)
                    or string.format("LOB %.1f°  NO IMPACT", aimCache.launchElevation or 0)
            else
                infoDistLabel.Text = distMeters and string.format("IMPACT %.0fm", distMeters) or "NO IMPACT IN PREVIEW"
            end
            infoSubLabel.Text = offsetMeters and string.format("Cursor offset %.0fm  |  %.2fs", offsetMeters, activeTime)
                or string.format("%s  |  %.2fs", wData.loaded, activeTime)
        end
        impactHud.Visible = true
    else
        impactHud.Visible = false
    end
    visualDiagnostics.lastMs = (os.clock() - visualStartTime) * 1000
    end, debug.traceback)
    if not ok then
        visualDiagnostics.error = tostring(failure)
        visualDiagnostics.stopped = true
        RunService:UnbindFromRenderStep(VISUAL_RENDER_NAME)
        pcall(hideVisuals)
        warn("AutoLead visual update stopped (reload after correcting): " .. tostring(failure))
    end
end)

-- Player ESP: isolated, commit-pinned fork of tulontop/esp-lib.lua.
-- Tank ESP continues to use Roblox Highlights independently.
local playerDrawings = {}
local tankHighlights = {}
local espStats = { players = 0, tanks = 0 }
espStats.timings = { frameMs=0, playerDrawMs=0, tankDrawMs=0, playerScanMs=0, tankScanMs=0, armorScanMs=0 }
-- WorldToViewportPoint pixels must not receive the top-bar/safe-area inset.
-- Keep this separate so the existing impact HUD layout is unchanged.
espStats.gui = Instance.new("ScreenGui")
espStats.gui.Name = "AttributeTankOverlay"
espStats.gui.IgnoreGuiInset = true
espStats.gui.ResetOnSpawn = false
espStats.gui.DisplayOrder = screenGui.DisplayOrder
espStats.gui.Parent = lp:WaitForChild("PlayerGui")
espStats.edges = {{1,2},{1,3},{1,5},{2,4},{2,6},{3,4},{3,7},{4,8},{5,6},{5,7},{6,8},{7,8}}
function espStats.newOutline()
    local group = Instance.new("Folder")
    group.Name = "ModuleOutline"
    group.Parent = espStats.gui
    local lines = {}
    for i = 1, 12 do
        local line = Instance.new("Frame")
        line.Name = "Edge"
        line.AnchorPoint = Vector2.new(0.5, 0.5)
        line.BorderSizePixel = 0
        line.Visible = false
        line.Parent = group
        lines[i] = line
    end
    return group, lines
end
function espStats.drawOutline(mark, part, camera, color, enabled)
    local points = mark.points
    if enabled then
        local i = 0
        for x = -1, 1, 2 do for y = -1, 1, 2 do for z = -1, 1, 2 do
            i = i + 1
            points[i] = camera:WorldToViewportPoint(part.CFrame:PointToWorldSpace(part.Size * Vector3.new(x,y,z) * 0.5))
        end end end
    end
    for i, edge in ipairs(espStats.edges) do
        local line = mark.lines[i]
        line.Visible = false
        if enabled then
            local a, b = points[edge[1]], points[edge[2]]
            if a.Z > 0.1 and b.Z > 0.1 then
                local start, delta = Vector2.new(a.X,a.Y), Vector2.new(b.X-a.X,b.Y-a.Y)
                local low, high = 0, 1
                local function clip(p, q)
                    if math.abs(p) < 1e-8 then return q >= 0 end
                    local t = q / p
                    if p < 0 then low = math.max(low,t) else high = math.min(high,t) end
                    return low <= high
                end
                local view = camera.ViewportSize
                if clip(-delta.X,start.X) and clip(delta.X,view.X-start.X)
                    and clip(-delta.Y,start.Y) and clip(delta.Y,view.Y-start.Y) then
                    local first, last = start + delta * low, start + delta * high
                    local d = last - first
                    if d.Magnitude >= 0.5 then
                        line.Position = UDim2.fromOffset((first.X+last.X)*0.5,(first.Y+last.Y)*0.5)
                        line.Size = UDim2.fromOffset(d.Magnitude, Settings.ModuleLineThickness)
                        line.Rotation = math.deg(math.atan2(d.Y,d.X))
                        line.BackgroundColor3 = color
                        line.BackgroundTransparency = 0.45
                        line.Visible = true
                    end
                end
            end
        end
    end
end
local playerEsp
local drawingAvailable = Drawing and type(Drawing.new) == "function"
if drawingAvailable then
    local ok, result = pcall(function()
        local source = game:HttpGet("https://raw.githubusercontent.com/eduardonash/esp-lib.lua/e44b14b4d642c8d24388d876204293e4f8a83389/source.lua")
        local chunk, err = loadstring(source)
        assert(chunk, err)
        return chunk({ isolated = true, manualUpdate = true, disableCorners = true, excludeAccessories = true })
    end)
    if ok then
        playerEsp = result
        playerEsp.box.padding = 1.03
        playerEsp.box.type = "normal"
        playerEsp.distance.enabled = false
        playerEsp.tracer.enabled = false
    else
        drawingAvailable = false
        espStats.error = tostring(result)
        warn("[Attribute] Player ESP unavailable: " .. tostring(result))
    end
end

local function createPlayerDrawing(character)
    playerEsp.add_box(character)
    playerEsp.add_healthbar(character)
    playerEsp.add_name(character)
    return { character = character }
end

local function removePlayerDrawing(tag)
    if playerEsp then playerEsp.remove(tag.character) end
end

local function scanEnemyPlayers(origin)
    local seen = {}
    espStats.players = 0
    if drawingAvailable and Settings.PlayerESP and lp.Team and lp.Team.Name ~= "Neutral" then
        local candidates = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= lp and player.Team and player.Team.Name ~= "Neutral" and player.Team ~= lp.Team then
                local character = player.Character
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                local head = character and character:FindFirstChild("Head")
                local root = character and character:FindFirstChild("HumanoidRootPart")
                if humanoid and humanoid.Health > 0 and head and root and head:IsDescendantOf(workspace) then
                    local distance = (head.Position - origin).Magnitude
                    if distance <= Settings.ESPMaxDistance then
                        candidates[#candidates + 1] = { player = player, head = head, root = root,
                            humanoid = humanoid, distance = distance }
                    end
                end
            end
        end
        table.sort(candidates, function(a, b) return a.distance < b.distance end)
        for i = 1, math.min(#candidates, 24) do
            local c = candidates[i]
            local tag = playerDrawings[c.player]
            if tag and tag.character ~= c.player.Character then
                removePlayerDrawing(tag)
                playerDrawings[c.player] = nil
                tag = nil
            end
            if not tag then tag = createPlayerDrawing(c.player.Character); playerDrawings[c.player] = tag end
            tag.head, tag.root, tag.humanoid = c.head, c.root, c.humanoid
            seen[c.player] = true
            espStats.players = espStats.players + 1
        end
    end
    for player, tag in pairs(playerDrawings) do
        if not seen[player] then
            removePlayerDrawing(tag)
            playerDrawings[player] = nil
        end
    end
end

local function updatePlayerDrawings(camera)
    if not playerEsp then return end
    local accent = getESPColor()
    playerEsp.box.enabled = Settings.PlayerESP and Settings.ESPBoxes
    playerEsp.box.fill, playerEsp.box.outline = accent, THEME.Ink
    playerEsp.name.enabled = Settings.PlayerESP and Settings.ESPNames
    playerEsp.name.fill, playerEsp.name.size = accent, 12
    playerEsp.healthbar.enabled = Settings.PlayerESP and Settings.ESPHealth
    playerEsp.healthbar.fill, playerEsp.healthbar.outline = THEME.BlastOccupied, THEME.Ink
    for player, tag in pairs(playerDrawings) do
        if not tag.humanoid or tag.humanoid.Health <= 0 or player.Character ~= tag.character then
            removePlayerDrawing(tag)
            playerDrawings[player] = nil
        end
    end
    playerEsp.update(camera)
end

local function scanEnemyTanks(origin)
    local seen = {}
    local moduleBudget = 32
    espStats.tanks = 0
    local vehicles = workspace:FindFirstChild("SpawnedVehicles")
    if Settings.EnemyTankESP and vehicles then
        local candidates = {}
        local myColor = lp.Team and lp.TeamColor.Name
        for _, veh in ipairs(vehicles:GetChildren()) do
            local enemyTeam = veh:GetAttribute("Team")
            local class = veh:GetAttribute("VehicleGeneralClass")
            local kind = tostring(veh:GetAttribute("Type") or ""):lower()
            local helicopter = kind == "helicopter" or kind == "heli"
                or tostring(veh:GetAttribute("VehicleClass") or ""):lower():find("helicopter", 1, true) ~= nil
            local teamAllowed = not Settings.TankTeamCheck or (myColor and lp.Team.Name ~= "Neutral"
                and enemyTeam and tostring(enemyTeam) ~= myColor)
            if veh:IsA("Model") and (kind == "tank" or Settings.HelicopterESP and helicopter)
                and teamAllowed and veh ~= getActiveTank()
                and (not Settings.TankOccupiedOnly or veh:GetAttribute("Occupied") == true)
                and class ~= "Transport" and not veh:GetAttribute("HeavyTransport") then
                local root = veh.PrimaryPart
                if root then
                    local distance = (root.Position - origin).Magnitude
                    if distance <= Settings.ESPMaxDistance then
                        candidates[#candidates + 1] = { vehicle = veh, distance = distance }
                    end
                end
            end
        end
        table.sort(candidates, function(a, b) return a.distance < b.distance end)
        for i = 1, math.min(#candidates, 16) do
            local veh = candidates[i].vehicle
            local tag = tankHighlights[veh]
            if not tag then
                local highlight = Instance.new("Highlight")
                highlight.Name = "AutoLeadEnemyTank"
                highlight.Adornee = veh
                highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                highlight.FillTransparency = 0.94
                highlight.OutlineTransparency = 0.08
                highlight.Parent = visualContainer
                local box = Instance.new("Frame")
                box.Name = "TankBounds"
                box.BackgroundTransparency = 1
                box.BorderSizePixel = 0
                box.Visible = false
                box.Parent = espStats.gui
                local stroke = Instance.new("UIStroke")
                stroke.Thickness = 1
                stroke.Parent = box
                local label = Instance.new("TextLabel")
                label.Name = "TankLabel"
                label.BackgroundTransparency = 1
                label.AnchorPoint = Vector2.new(0.5, 1)
                label.TextSize = 12
                label.Font = Enum.Font.GothamMedium
                label.TextStrokeTransparency = 0.25
                label.TextStrokeColor3 = Color3.new()
                label.Size = UDim2.fromOffset(260, 42)
                label.Parent = espStats.gui
                tag = { highlight = highlight, box = box, stroke = stroke, label = label, modules = {} }
                tankHighlights[veh] = tag
            end
            tag.root = veh.PrimaryPart
            local cf, size = veh:GetBoundingBox()
            tag.bounds, tag.size = tag.root.CFrame:ToObjectSpace(cf), size
            tag.name = tostring(veh:GetAttribute("VehicleDisplayName") or veh.Name)
            tag.class = tostring(veh:GetAttribute("VehicleClass") or veh:GetAttribute("VehicleGeneralClass") or "Unknown")
            tag.highlight.FillColor = getESPColor()
            tag.highlight.OutlineColor = getESPColor()
            -- Only geometry under verified DamageModules, never similarly named
            -- ammo inventory values or engine RemoteEvents.
            local keep = {}
            local damage = veh:FindFirstChild("DamageModules")
            if damage and candidates[i].distance <= Settings.ModuleDistance
                and (Settings.ModuleOutline or Settings.ModuleFilled) then
                local count = 0
                for _, model in ipairs(damage:GetChildren()) do
                    local name = model.Name:lower()
                    local kind = name == "engine" and "engine" or (name:find("ammo", 1, true) and "ammo")
                    if kind and (kind == "engine" and Settings.ModuleEngine or kind == "ammo" and Settings.ModuleAmmo) then
                        local parts = model:IsA("BasePart") and {model} or model:QueryDescendants("BasePart")
                        for _, part in ipairs(parts) do
                            if count >= 8 or moduleBudget <= 0 then break end
                            count = count + 1
                            moduleBudget = moduleBudget - 1
                            keep[part] = true
                            local mark = tag.modules[part]
                            if not mark then
                                local fill = Instance.new("BoxHandleAdornment")
                                fill.Adornee, fill.AlwaysOnTop, fill.ZIndex = part, true, 1
                                fill.Parent = visualContainer
                                local outline, lines = espStats.newOutline()
                                mark = { fill = fill, outline = outline, lines = lines, points = {} }
                                tag.modules[part] = mark
                            end
                            mark.kind = kind
                            mark.fill.Size = part.Size
                        end
                    end
                end
            end
            for part, mark in pairs(tag.modules) do
                if not keep[part] then mark.fill:Destroy(); mark.outline:Destroy(); tag.modules[part] = nil end
            end
            seen[veh] = true
            espStats.tanks = espStats.tanks + 1
        end
    end
    for veh, tag in pairs(tankHighlights) do
        if not seen[veh] then
            tag.highlight:Destroy()
            tag.box:Destroy()
            tag.label:Destroy()
            for _, mark in pairs(tag.modules) do mark.fill:Destroy(); mark.outline:Destroy() end
            tankHighlights[veh] = nil
        end
    end
end

-- Project only eight cached corners per tracked vehicle; no scene scans here.
function espStats.drawTanks(camera)
    local origin, viewport = camera.CFrame.Position, camera.ViewportSize
    for veh, tag in pairs(tankHighlights) do
        local live = Settings.EnemyTankESP and tag.root and tag.root.Parent and veh.Parent
        local distance = live and (tag.root.Position - origin).Magnitude or math.huge
        local visible = live and distance <= Settings.ESPMaxDistance
        local fade = Settings.TankDistanceFade and math.clamp(1 - distance / math.max(1, Settings.ESPMaxDistance), 0, 1) or 1
        tag.highlight.Enabled = visible == true
        tag.highlight.FillTransparency = 1 - 0.06 * fade
        tag.highlight.OutlineTransparency = 1 - 0.92 * fade
        tag.box.Visible, tag.label.Visible = false, false
        if visible and (Settings.TankBoxes or Settings.TankNames or Settings.TankClass or Settings.TankDistance) then
            local cf = tag.root.CFrame * tag.bounds
            local lo, hi, clipped = Vector2.new(math.huge, math.huge), Vector2.new(-math.huge, -math.huge), false
            for x = -1, 1, 2 do for y = -1, 1, 2 do for z = -1, 1, 2 do
                local p = camera:WorldToViewportPoint(cf:PointToWorldSpace(tag.size * Vector3.new(x, y, z) * 0.5))
                if p.Z <= 0.1 then clipped = true else
                    lo = Vector2.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y))
                    hi = Vector2.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y))
                end
            end end end
            if not clipped and hi.X >= 0 and hi.Y >= 0 and lo.X <= viewport.X and lo.Y <= viewport.Y then
                local color = getESPColor()
                tag.box.Position, tag.box.Size = UDim2.fromOffset(lo.X, lo.Y), UDim2.fromOffset(hi.X - lo.X, hi.Y - lo.Y)
                tag.box.Visible, tag.stroke.Color, tag.stroke.Transparency = Settings.TankBoxes, color, 1 - fade
                local text = {}
                if Settings.TankNames then text[#text+1] = tag.name end
                if Settings.TankClass then text[#text+1] = tag.class end
                if Settings.TankDistance then text[#text+1] = string.format("%.0f m", distance / 2.7777778) end
                tag.label.Text = table.concat(text, " · ")
                tag.label.Position = UDim2.fromOffset((lo.X + hi.X) * 0.5, math.max(42, lo.Y - 3))
                tag.label.TextColor3, tag.label.TextTransparency = color, 1 - fade
                tag.label.TextStrokeTransparency = 1 - 0.75 * fade
                tag.label.Visible = #text > 0
            end
        end
        for part, mark in pairs(tag.modules) do
            local show = visible and part.Parent ~= nil and distance <= Settings.ModuleDistance
                and (mark.kind == "engine" and Settings.ModuleEngine or mark.kind == "ammo" and Settings.ModuleAmmo)
            local color = mark.kind == "engine" and Settings.ModuleEngineColor or Settings.ModuleAmmoColor
            mark.fill.Visible = show == true and Settings.ModuleFilled
            espStats.drawOutline(mark, part, camera, color, show == true and Settings.ModuleOutline)
            mark.fill.Color3 = color
            mark.fill.Transparency = 1 - 0.24 * fade
            -- Module edges remain opaque within range; tank distance fading
            -- must not make the outline-only inspection mode unreadable.
        end
    end
end

-- Preserve original local armor data so changing teams, disabling the option,
-- and unloading cannot leave allied or previously scanned tanks modified.
local originalEnemyArmor = {}
local armorVehicleWatchers = {}
local armorStats = { vehicles = 0, values = 0 }
local ARMOR_ATTRIBUTES = { "HEAT", "Composite", "HEATComposite", "SlatArmour" }

local function restoreEnemyArmor(value, original)
    if not value.Parent then return end
    pcall(function()
        value.Value = original.value
        for name, oldValue in pairs(original.attributes) do
            value:SetAttribute(name, oldValue)
        end
    end)
end

local function zeroArmorValue(value, vehicle)
    if not value:IsA("NumberValue") or value.Name ~= "ArmourValue" then return end
    local original = originalEnemyArmor[value]
    if not original then
        original = { vehicle = vehicle, value = value.Value, attributes = {} }
        for _, name in ipairs(ARMOR_ATTRIBUTES) do
            local oldValue = value:GetAttribute(name)
            if oldValue ~= nil then original.attributes[name] = oldValue end
        end
        originalEnemyArmor[value] = original
    end
    if value.Value ~= 0 then value.Value = 0 end
    for name in pairs(original.attributes) do
        if value:GetAttribute(name) ~= 0 then value:SetAttribute(name, 0) end
    end
end

local function scanEnemyArmor()
    local vehicles = workspace:FindFirstChild("SpawnedVehicles")
    local myTeam = lp.Team and lp.Team.Name ~= "Neutral" and lp.TeamColor.Name or nil
    local activeVehicles = {}

    if Settings.ZeroEnemyArmor and vehicles and myTeam then
        for _, vehicle in ipairs(vehicles:GetChildren()) do
            if vehicle:IsA("Model") and vehicle:GetAttribute("Type") == "Tank"
                and vehicle:GetAttribute("Team") and tostring(vehicle:GetAttribute("Team")) ~= myTeam then
                activeVehicles[vehicle] = true
                if not armorVehicleWatchers[vehicle] then
                    armorVehicleWatchers[vehicle] = vehicle.DescendantAdded:Connect(function(child)
                        if Settings.ZeroEnemyArmor then zeroArmorValue(child, vehicle) end
                    end)
                    for _, child in ipairs(vehicle:GetDescendants()) do
                        zeroArmorValue(child, vehicle)
                    end
                end
            end
        end
    end

    for vehicle, connection in pairs(armorVehicleWatchers) do
        if not activeVehicles[vehicle] then
            connection:Disconnect()
            armorVehicleWatchers[vehicle] = nil
        end
    end

    armorStats.vehicles, armorStats.values = 0, 0
    for _ in pairs(armorVehicleWatchers) do armorStats.vehicles = armorStats.vehicles + 1 end
    for value, original in pairs(originalEnemyArmor) do
        if not activeVehicles[original.vehicle] or not value.Parent then
            restoreEnemyArmor(value, original)
            originalEnemyArmor[value] = nil
        else
            zeroArmorValue(value, original.vehicle)
            armorStats.values = armorStats.values + 1
        end
    end
end

local lastPlayerScan = 0
local lastTankScan = 0
local lastArmorScan = 0
RunService:BindToRenderStep("AttributePlayerESP", FREECAM_PRIORITY + 4, function()
    local now = os.clock()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local focusStarted=os.clock()
    local focusOK,focusError=pcall(shellRedirection.frame,camera)
    shellRedirection.frameMs=(os.clock()-focusStarted)*1000
    if not focusOK then
        shellRedirection.error=tostring(focusError); shellRedirection.failed=true
        pcall(shellRedirection.release); pcall(shellRedirection.stop)
        if shellRedirection.visuals then shellRedirection.visuals.gui.Enabled=false end
    end
    if shellRedirection.error and shellRedirection.error~=shellRedirection.reportedError then
        shellRedirection.reportedError=shellRedirection.error
        extras.notify("Shell Redirection unavailable: "..shellRedirection.error)
    end
    local origin = camera.CFrame.Position
    if now - lastPlayerScan >= 0.25 then
        lastPlayerScan = now
        local started=os.clock()
        scanEnemyPlayers(origin)
        espStats.timings.playerScanMs=(os.clock()-started)*1000
    end
    local started=os.clock()
    updatePlayerDrawings(camera)
    espStats.timings.playerDrawMs=(os.clock()-started)*1000
    started=os.clock()
    espStats.drawTanks(camera)
    espStats.timings.tankDrawMs=(os.clock()-started)*1000
    if now - lastTankScan >= 0.75 then
        lastTankScan = now
        started=os.clock()
        scanEnemyTanks(origin)
        espStats.timings.tankScanMs=(os.clock()-started)*1000
    end
    if now - lastArmorScan >= 1.5 then
        lastArmorScan = now
        started=os.clock()
        scanEnemyArmor()
        espStats.timings.armorScanMs=(os.clock()-started)*1000
    end
    espStats.timings.frameMs=(os.clock()-now)*1000
end)

-- ===================================================================
-- WEAPON FIRING HOOK (PROJECTILE MANIPULATION / SILENT AIM)
-- ===================================================================

local hookedWeaponModules = {}
local hookedWeaponHandler = nil
local oldFireWeapon = nil
-- Retain validated native shot codes when the UI script is re-executed in the
-- same session; weak vehicle keys prevent stale destroyed vehicles lingering.
local shotCodeByVehicle = _G.AutoLeadAssistShotCodes or setmetatable({}, { __mode = "k" })
_G.AutoLeadAssistShotCodes = shotCodeByVehicle
local lastDirectFireError = nil
local lastShotDiagnostics = nil
-- Hooks only enqueue Lua data. Instance work and projectile discovery run on
-- our render thread, outside the game's restricted firing context.
local shotTracker = { queue = {}, entries = {}, serial = 0, alive = true,
    message = "NO SHOT YET", detail = "Waiting for a confirmed projectile", sent = 0,
    attempts = 0, observed = 0, rejected = 0, candidates = {}, projectileNames = {} }
shotTracker.flightGui = Instance.new("ScreenGui")
shotTracker.flightGui.Name = "AttributeFlights"
shotTracker.flightGui.IgnoreGuiInset = true
shotTracker.flightGui.ResetOnSpawn = false
shotTracker.flightGui.DisplayOrder = screenGui.DisplayOrder - 1
shotTracker.flightGui.Parent = screenGui.Parent

function shotTracker.releaseCandidate(record)
    if record.motion then record.motion:Disconnect() end
    if record.parent then record.parent:Disconnect() end
    if shotTracker.candidates[record.part] == record then shotTracker.candidates[record.part] = nil end
end

function shotTracker.observePart(part)
    if not (part:IsA("BasePart") or part:IsA("Attachment")) or not shotTracker.projectileNames[part.Name]
        or os.clock() - (shotTracker.pendingSince or 0) > 1 then return end
    -- A pooled object can be reused before its previous shot marker expires.
    -- Retire its old callbacks before replacing the candidate record.
    local previous = shotTracker.candidates[part]
    if previous then
        previous.ended = true
        if previous.state then previous.state.destroy = true end
        shotTracker.releaseCandidate(previous)
    end
    local count = 0
    for _ in pairs(shotTracker.candidates) do count = count + 1 end
    if count >= 24 then return end
    local record = { part = part, born = os.clock() }
    shotTracker.candidates[part] = record
    local function sample()
        local position = part:IsA("Attachment") and part.WorldPosition or part.Position
        if math.abs(position.X) > 100000 or math.abs(position.Z) > 100000 then
            if record.first then
                record.ended = true
                if record.state then record.state.destroy = true end
                if record.motion then record.motion:Disconnect() end
                if record.parent then record.parent:Disconnect() end
            end
            return
        end
        local now = os.clock()
        if not record.first then
            record.first = position
            record.direction = (part:IsA("Attachment") and part.WorldCFrame or part.CFrame).LookVector
        end
        if record.position and now - (record.sampleTime or now) > 0.002 then
            record.velocity = (position - record.position) / (now - record.sampleTime)
        end
        record.position, record.sampleTime = position, now
        if record.state then
            record.state.position = position
            if record.velocity then record.state.velocity = record.velocity end
        end
    end
    record.motion = part:GetPropertyChangedSignal("CFrame"):Connect(sample)
    record.parent = part.AncestryChanged:Connect(function()
        if part.Parent ~= workspace.Terrain then
            record.ended = true
            if record.state then record.state.destroy = true end
            if record.motion then record.motion:Disconnect() end
            if record.parent then record.parent:Disconnect() end
        end
    end)
    sample()
end

do
    local phrst = ReplicatedStorage:FindFirstChild("PHRST")
    local shells = phrst and phrst:FindFirstChild("Shells")
    local templates = shells and shells:FindFirstChild("Bullets")
    if templates then
        for _, part in ipairs(templates:QueryDescendants("BasePart, Attachment")) do
            shotTracker.projectileNames[part.Name] = true
        end
    end
    -- PartCache:GetPart parents real shells here; ReturnPart removes them.
    -- Observe those transitions without hooking or searching projectile tables.
    shotTracker.partsAdded = workspace.Terrain.ChildAdded:Connect(shotTracker.observePart)
end

function shotTracker.request(source)
    if os.clock() - shotTracker.sent < 0.05 then return end
    if shotTracker.requested and os.clock() - shotTracker.requested < 0.1 then return end
    shotTracker.attempts = shotTracker.attempts + 1
    shotTracker.requested = os.clock()
    shotTracker.requestedAt = shotTracker.requested
    shotTracker.message = "INPUT RECEIVED"
    shotTracker.detail = "Waiting for the weapon; no launch confirmed"
end

function shotTracker.reject(reason)
    shotTracker.requested = nil
    shotTracker.messageAt = os.clock()
    shotTracker.message = "NOT FIRED"
    shotTracker.detail = tostring(reason or "No projectile created")
    shotTracker.rejected = shotTracker.rejected + 1
end

function shotTracker.announce(entry, message, detail)
    -- A prior shell finishing cannot overwrite a newer rejected input.
    if entry.attempt == shotTracker.attempts then
        shotTracker.message, shotTracker.detail = message, detail
        shotTracker.messageAt = os.clock()
        shotTracker.requested = nil
    end
end

function shotTracker.remove(entry)
    if entry.record then shotTracker.releaseCandidate(entry.record) end
    for _, item in ipairs(entry.visuals or {}) do item:Destroy() end
end

function shotTracker.attach(entry, state)
    entry.state = state
    entry.visuals = {}
    entry.start = state.position0
    entry.initialVelocity = state.velocity0
    entry.started = entry.sentAt
    if type(state.timefired) == "number" then
        entry.started = os.clock() - math.clamp(workspace:GetServerTimeNow() - state.timefired, 0, 60)
    end
    entry.lastPosition, entry.lastMoved = state.position, os.clock()
    entry.redirectionFlight = entry.redirectionFlight or Settings.ShellRedirection
    if entry.redirectionFlight then
        -- A steerable flight has no fixed impact/ETA forecast. Keep only the
        -- observed-shell marker; do not allocate 98 forecast segment Frames.
        entry.samples = {}
        shotTracker.makeFlightOverlay(entry)
    else
        local w = entry.weapon
        local duration = math.max(entry.predictedTime or 0, 2 * math.max(entry.initialVelocity.Y, 0) / math.max(math.abs(w.gravity), 1) + 3)
        duration = math.min(duration,ballistics.lifetime(state))
        local steps = math.clamp(math.ceil(duration / 0.18), 8, 120)
        local finish, hit, time, _, endVelocity = traceTrajectory(entry.start, entry.initialVelocity,
            w.gravity, w.drag, getTrajectoryParams(entry.vehicle), steps, duration / steps)
        entry.expectedTime, entry.expectedEnd, entry.expectedHit = time, finish, hit ~= nil
        -- A full forecast is retained, but completed geometry comes from observed
        -- movement. Pixel-width segments avoid subpixel world-Beam stippling.
        local p0 = entry.start
        entry.samples, entry.pathLength = { { point = p0, length = 0 } }, 0
        for i = 1, 48 do
            local point = ballistics.sample(entry.start,entry.initialVelocity,w.gravity,w.drag,time*i/48)
            if i == 48 then point = finish end
            entry.pathLength = entry.pathLength + (point - entry.samples[#entry.samples].point).Magnitude
            entry.samples[#entry.samples + 1] = { point = point, length = entry.pathLength }
        end
        shotTracker.makeFlightOverlay(entry)
        entry.zone = blastZone:Clone()
        entry.zone.Name = "ConfirmedShotTarget"
        entry.zone.Size = Vector3.new(0.12, 8, 8)
        local normal = hit and hit.Normal or Vector3.yAxis
        local right = normal:Cross(Vector3.zAxis)
        if right.Magnitude < 0.1 then right = normal:Cross(Vector3.xAxis) end
        entry.zone.CFrame = CFrame.fromMatrix(finish + normal * 0.24, normal, right.Unit)
        entry.zone.Color = THEME.FlightEnd
        entry.zone.Transparency = 0.48
        entry.zone.Parent = visualContainer
        entry.visuals[#entry.visuals + 1] = entry.zone
        entry.targetHud = blastDistance.gui:Clone()
        entry.targetHud.Name = "ConfirmedShotETA"
        entry.targetHud.Adornee = entry.zone
        entry.targetHud.Size = UDim2.fromOffset(190, 38)
        entry.targetHud.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0)
        entry.targetHud.Enabled = true
        entry.targetHud.Parent = visualContainer
        entry.targetText = entry.targetHud:FindFirstChildOfClass("TextLabel")
        -- Keep the cloned label's automatic, tightly padded text bounds.
        entry.visuals[#entry.visuals + 1] = entry.targetHud
    end
    entry.part = state.projectile or (state.physicalprojectile and state.physicalprojectile.proj)
    -- Outline only the real projectile; never create an enlarged proxy ball or
    -- adorn an attachment's ancestor model (which could be the entire tank).
    local adorn = entry.part
    if adorn and adorn:IsA("Attachment") then adorn = adorn.Parent end
    if adorn and adorn:IsA("BasePart") then
        entry.shellAdornee = adorn
        entry.shellHighlight = Instance.new("Highlight")
        entry.shellHighlight.Name = "OwnShellOutline"
        entry.shellHighlight.Adornee = adorn
        entry.shellHighlight.FillTransparency = 1
        entry.shellHighlight.OutlineTransparency = 0
        entry.shellHighlight.OutlineColor = THEME.FlightStart
        entry.shellHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        entry.shellHighlight.Enabled = false
        entry.shellHighlight.Parent = visualContainer
        entry.visuals[#entry.visuals + 1] = entry.shellHighlight
    end
    entry.status = "AIRBORNE"
    shotTracker.observed = shotTracker.observed + 1
    shotTracker.announce(entry, "SHELL LAUNCHED", "Own projectile observed at the muzzle")
end

function shotTracker.discover(entry)
    if not entry.launchPosition or not entry.launchVelocity then return false end
    local best, bestScore = nil, math.huge
    for _, record in pairs(shotTracker.candidates) do
        if not record.state and record.first and record.part.Name == entry.model
            and record.born >= entry.sentAt - 0.08 and record.born <= entry.sentAt + 1 then
            local offset = (record.first - entry.launchPosition).Magnitude
            local direction = record.direction
            local aligned = not direction or direction:Dot(entry.launchVelocity.Unit) > 0.85
            local maxOffset = math.max(16, entry.launchVelocity.Magnitude * 0.08)
            if aligned and offset <= maxOffset then
                local score = offset + math.abs(record.born - entry.sentAt) * 50
                if score < bestScore then best, bestScore = record, score end
            end
        end
    end
    if not best then return false end
    local state = {
        position0 = entry.launchPosition, velocity0 = entry.launchVelocity,
        position = best.position, velocity = best.velocity or entry.launchVelocity,
        projectile = best.part, Lifetime = entry.weapon.shellData and entry.weapon.shellData.Lifetime,
        timefired = entry.serverTime, destroy = best.ended == true, visualOnly = true
    }
    best.state, entry.record = state, best
    shotTracker.attach(entry, state)
    return true
end

do
    local notify = lp.PlayerGui:FindFirstChild("Notify")
    local event = notify and notify:FindFirstChild("Notification")
    if event and event:IsA("BindableEvent") then
        shotTracker.notification = event.Event:Connect(function(kind, message)
            if kind == "ERROR" and os.clock() - (shotTracker.requestedAt or 0) < 1.5 then
                shotTracker.gameError, shotTracker.gameErrorAt = tostring(message), os.clock()
                shotTracker.reject(message)
            end
        end)
    end
end

function shotTracker.makeFlightOverlay(entry)
    local layer = Instance.new("Frame")
    layer.Name = "ConfirmedFlight"
    layer.Size = UDim2.fromScale(1, 1)
    layer.BackgroundTransparency = 1
    layer.ClipsDescendants = true
    layer.Parent = shotTracker.flightGui
    entry.visuals[#entry.visuals + 1] = layer
    entry.layer, entry.lines, entry.traveled = layer, {}, { entry.start }
    entry.routePosition, entry.routeProgress = entry.start, 0
    for i = 1, #entry.samples do -- one extra segment for the moving split
        local border = Instance.new("Frame")
        border.AnchorPoint = Vector2.new(0.5, 0.5)
        border.BorderSizePixel = 0
        border.BackgroundColor3 = THEME.Ink
        border.BackgroundTransparency = 0.55
        border.Visible = false
        border.Parent = layer
        local line = Instance.new("Frame")
        line.AnchorPoint = Vector2.new(0.5, 0.5)
        line.Position = UDim2.fromScale(0.5, 0.5)
        line.Size = UDim2.new(1, 0, 0, 1)
        line.BorderSizePixel = 0
        line.Parent = border
        entry.lines[i] = { border = border, line = line }
    end
    local marker = Instance.new("Frame")
    marker.Name = "ObservedShell"
    marker.AnchorPoint = Vector2.new(0.5, 0.5)
    marker.Size = UDim2.fromOffset(5, 5)
    marker.BackgroundColor3 = THEME.FlightStart
    marker.BackgroundTransparency = 1
    marker.BorderSizePixel = 0
    marker.ZIndex = 3
    marker.Parent = layer
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = marker
    local stroke = Instance.new("UIStroke")
    stroke.Color, stroke.Thickness = THEME.FlightStart, 1
    stroke.Parent = marker
    entry.shellMarker = marker
end

-- Clip before sizing GUI lines, including crossings of the camera near plane.
function shotTracker.screenSegment(cam, a, b)
    local da = -cam.CFrame:PointToObjectSpace(a).Z
    local db = -cam.CFrame:PointToObjectSpace(b).Z
    if da < 0.1 and db < 0.1 then return end
    if da < 0.1 then a = a:Lerp(b, (0.1 - da) / (db - da))
    elseif db < 0.1 then b = a:Lerp(b, (0.1 - da) / (db - da)) end
    local pa, pb = cam:WorldToViewportPoint(a), cam:WorldToViewportPoint(b)
    local start = Vector2.new(pa.X, pa.Y)
    local delta = Vector2.new(pb.X - pa.X, pb.Y - pa.Y)
    local lo, hi = 0, 1
    local function clip(p, q)
        if math.abs(p) < 1e-8 then return q >= 0 end
        local t = q / p
        if p < 0 then lo = math.max(lo, t) else hi = math.min(hi, t) end
        return lo <= hi
    end
    local view = cam.ViewportSize
    if not clip(-delta.X, start.X) or not clip(delta.X, view.X - start.X)
        or not clip(-delta.Y, start.Y) or not clip(delta.Y, view.Y - start.Y) then return end
    return start + delta * lo, start + delta * hi
end

function shotTracker.drawFlight(entry, cam)
    if entry.redirectionFlight then shotTracker.drawShell(entry,cam); return end
    local n = #entry.samples - 1
    local progress = math.clamp(entry.progress or 0, 0, 0.9999)
    local position = entry.state.position
    -- Commit passed waypoints from measured motion, not the forecast curve.
    for i = math.floor(entry.routeProgress * n) + 1, math.floor(progress * n) do
        local alpha = math.clamp((i / n - entry.routeProgress)
            / math.max(progress - entry.routeProgress, 1e-8), 0, 1)
        entry.traveled[i + 1] = entry.routePosition:Lerp(position, alpha)
    end
    entry.routeProgress, entry.routePosition = progress, position
    local split = math.floor(progress * n) + 1
    local forecast = entry.samples[split].point:Lerp(entry.samples[split + 1].point, progress * n % 1)
    local correction = position - forecast
    local used = 0
    local function draw(a, b, complete, fraction)
        used = used + 1
        local item = entry.lines[used]
        local pa, pb = shotTracker.screenSegment(cam, a, b)
        item.border.Visible = Settings.ShotProgress and pa ~= nil
        if not item.border.Visible then return end
        local delta = pb - pa
        item.border.Position = UDim2.fromOffset((pa.X + pb.X) / 2, (pa.Y + pb.Y) / 2)
        item.border.Size = UDim2.fromOffset(math.max(delta.Magnitude, 0.1), 2)
        item.border.Rotation = math.deg(math.atan2(delta.Y, delta.X))
        item.line.BackgroundColor3 = complete and THEME.FlightStart:Lerp(THEME.FlightEnd, fraction)
            or Color3.fromRGB(207, 218, 232)
        item.line.BackgroundTransparency = complete and 0 or 0.5
    end
    for i = 1, split - 1 do
        draw(entry.traveled[i], entry.traveled[i + 1], true, i / n)
    end
    draw(entry.traveled[split], position, true, progress)
    local previous = position
    for i = split + 1, #entry.samples do
        -- Join the forecast to the observed shell without moving its target.
        local weight = math.clamp((1 - (i - 1) / n) / math.max(1 - progress, 1e-8), 0, 1)
        local point = entry.samples[i].point + correction * weight
        draw(previous, point, false, (i - 1) / n)
        previous = point
    end
    shotTracker.drawShell(entry,cam)
end
function shotTracker.drawShell(entry, cam)
    local point, visible = cam:WorldToViewportPoint(entry.state.position)
    local adorn = entry.shellAdornee
    local usable = entry.shellHighlight and adorn and adorn.Parent ~= nil
        and adorn.Transparency < 1 and adorn.LocalTransparencyModifier < 1 and point.Z > 0
    if usable then
        local pixels = adorn.Size.Magnitude * cam.ViewportSize.Y
            / (2 * math.tan(math.rad(cam.FieldOfView) / 2) * math.max(point.Z, 0.1))
        usable = pixels >= 3
    end
    if entry.shellHighlight then
        shellRedirection.assign(entry.shellHighlight,"Enabled",Settings.OwnShellHighlight and usable == true)
    end
    shellRedirection.assign(entry.shellMarker,"Visible",Settings.OwnShellHighlight and not usable and visible and point.Z > 0)
    if entry.shellMarker.Visible then
        shellRedirection.assign(entry.shellMarker,"Position",UDim2.fromOffset(point.X,point.Y))
    end
end

function shotTracker.projectProgress(entry, position)
    local closest, parameter = math.huge, 0
    for i = 2, #entry.samples do
        local a, b = entry.samples[i - 1], entry.samples[i]
        local delta = b.point - a.point
        local t = math.clamp((position - a.point):Dot(delta) / math.max(delta:Dot(delta), 1e-8), 0, 1)
        local error = (position - (a.point + delta * t)).Magnitude
        if error < closest then
            closest = error
            parameter = (i - 2 + t) / (#entry.samples - 1)
        end
    end
    return math.clamp(parameter, 0, 0.99)
end

RunService:BindToRenderStep("AutoLeadShotTracking", FREECAM_PRIORITY + 3, function()
    local now = os.clock()
    for _, entry in ipairs(shotTracker.queue) do
        if #shotTracker.entries >= 4 then shotTracker.remove(table.remove(shotTracker.entries, 1)) end
        entry.tries, entry.nextTry = 0, now
        table.insert(shotTracker.entries, entry)
        shotTracker.announce(entry, "SHOT SENT", "Weapon emitted a shot; acquiring its flight")
    end
    table.clear(shotTracker.queue)
    local latest
    for i = #shotTracker.entries, 1, -1 do
        local entry = shotTracker.entries[i]
        if not entry.state and not entry.finished and now >= entry.nextTry then
            entry.tries = entry.tries + 1
            local ok, found = pcall(shotTracker.discover, entry)
            if not ok then entry.discoveryError = tostring(found) end
            if not ok or not found then
                entry.nextTry = now
                if now - entry.sentAt > 1.5 then
                    entry.finished = now
                    shotTracker.announce(entry, "SHOT SENT · FLIGHT UNOBSERVED",
                        "The shot event ran; impact cannot be confirmed")
                end
            end
        end
        local state = entry.state
        if state and not entry.finished then
            if Settings.ShellRedirection and not entry.redirectionFlight then
                entry.redirectionFlight = true
                for _, line in ipairs(entry.lines or {}) do line.border.Visible=false end
                if entry.zone then entry.zone.Transparency=1 end
                if entry.targetHud then entry.targetHud.Enabled=false end
            end
            local elapsed = math.max(0.001, now - entry.started)
            local position = state.position
            -- Detect crossing the predicted impact point between observed
            -- samples; don't wait for a pooled projectile's delayed removal.
            local arrivalDistance, arrived
            if not entry.redirectionFlight then
                local travel = position - entry.lastPosition
                local t = math.clamp((entry.expectedEnd - entry.lastPosition):Dot(travel)
                    / math.max(travel:Dot(travel), 1e-8), 0, 1)
                arrivalDistance = (entry.lastPosition + travel * t - entry.expectedEnd).Magnitude
                arrived = entry.expectedHit and elapsed >= entry.expectedTime * 0.5 and arrivalDistance <= 8
            end
            if (position - entry.lastPosition).Magnitude > 0.05 then
                entry.lastPosition, entry.lastMoved = position, now
                entry.status = "AIRBORNE"
            end
            entry.progress = not entry.redirectionFlight
                and math.max(entry.progress or 0, shotTracker.projectProgress(entry, position)) or nil
            entry.elapsed = elapsed
            entry.eta = not entry.redirectionFlight and math.max(0, entry.expectedTime - elapsed) or nil
            if state.destroy or arrived then
                entry.finished = now
                entry.status = state.hitray and "IMPACT OBSERVED" or "FLIGHT ENDED"
                if state.visualOnly and not entry.redirectionFlight then
                    entry.impactError = arrived and arrivalDistance or (position - entry.expectedEnd).Magnitude
                    if entry.impactError <= math.max(12, math.min(50, entry.initialVelocity.Magnitude * 0.05)) then
                        entry.status, entry.progress, entry.eta = "ARRIVAL OBSERVED", 1, 0
                    else
                        entry.status = "FLIGHT ENDED BEFORE TARGET"
                    end
                end
                if state.hitray and not entry.redirectionFlight then
                    entry.impactError = (state.hitray.Position - entry.expectedEnd).Magnitude
                    if entry.impactError > math.max(12, entry.pathLength * 0.002) then
                        entry.status = "IMPACT BEFORE / AWAY FROM TARGET"
                    else
                        entry.progress, entry.eta = 1, 0
                    end
                end
                shotTracker.lastObserved = { status = entry.status, impactError = entry.impactError,
                    elapsed = elapsed, id = entry.id, progress = entry.progress }
                shotTracker.announce(entry, entry.status, arrived and "Observed shell reached the predicted endpoint"
                    or (state.visualOnly and "Projectile left the visible simulation" or "Confirmed from projectile state"))
            elseif now - entry.lastMoved > 1.5 then
                entry.finished, entry.status = now, "TRACKING LOST"
                entry.eta = nil
                shotTracker.announce(entry, entry.status, "No movement observed; flight visuals removed")
            end
            if not entry.finished and elapsed > ballistics.lifetime(state) + 2 then
                entry.finished, entry.status = now, "TRACKING ENDED"
                shotTracker.announce(entry, entry.status, "No impact confirmation")
            end
        end
        if state and not entry.finished then
            shotTracker.drawFlight(entry, workspace.CurrentCamera)
            if not entry.redirectionFlight then
                local show = Settings.ShotProgress
                entry.zone.Transparency = show and 0.48 or 1
                entry.targetHud.Enabled = show and Settings.ShowDistance
                blastDistance.scaleLabel(entry.targetHud, entry.targetText, entry.expectedEnd)
                if now >= (entry.nextLabel or 0) then
                    entry.nextLabel = now + 0.05
                    local meters = (entry.expectedEnd - entry.start).Magnitude / 2.7777778
                    local eta = entry.eta and entry.eta > 0.05 and string.format("ETA ~%.1fs", entry.eta) or "ETA unavailable"
                    entry.targetText.Text = string.format("%.0f m  ·  %s  ·  %.0f%%", meters, eta, (entry.progress or 0) * 100)
                end
            end
            latest = latest or entry
        end
        if entry.finished then
            shotTracker.remove(entry)
            table.remove(shotTracker.entries, i)
        end
    end
    for _, record in pairs(shotTracker.candidates) do
        if not record.state and now - record.born > 1.6 then shotTracker.releaseCandidate(record) end
    end
    if shotTracker.requested and now - shotTracker.requested > 1.25 then
        shotTracker.reject(aimCache.reason ~= "ready" and aimCache.reason or "No shot event received from weapon")
    end
    -- Flight ETA stays at the target. Dispatch notifications use VibeUI,
    -- rather than another persistent shot-status panel over the scene.
end)
local fireReadiness = { time = 0 }

function fireReadiness.check(veh, wData)
    local w = wData and wData.weapon
    if not w then return "Weapon unavailable" end
    local loaded = w:FindFirstChild("CurrentlyLoaded")
    if not loaded or loaded.Value == "" or loaded.Value == "Unloaded" then return "Reload / select ammunition" end
    local reload = w:FindFirstChild("ReloadEvent")
    if not reload or not reload:HasTag("noob") then return "Weapon not released for firing" end
    local mag = w:FindFirstChild("Mag")
    if mag and mag.Value < 1 then return "Magazine empty" end
    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    local control = wData.turret and wData.turret:FindFirstChild("Control")
    if not hum or not hum.SeatPart then return "No occupied weapon seat" end
    if not (control and control.Value == hum.SeatPart) and not shotCodeByVehicle[veh] then
        return "Driver fire needs this vehicle's gunner code"
    end
    if (wData.shellMass or 0) > 0.08 then
        local damage = veh:FindFirstChild("Values") and veh.Values:FindFirstChild("DamageModule")
        for _, name in ipairs({ "Barrel", "Breech" }) do
            local ref = w:FindFirstChild(name)
            local health = ref and ref.Value or (damage and wData.turret and damage:FindFirstChild(wData.turret.Name .. name))
            if health and health:IsA("ValueBase") then
                local maxHealth = health:GetAttribute("MaxHealth")
                if type(maxHealth) == "number" and health.Value <= maxHealth * 0.25 then
                    return name .. " damaged"
                end
            end
        end
    end
    local pos = wData.firePoint and wData.firePoint.WorldPosition or wData.muzzle.Position
    local frame = wData.firePoint and wData.firePoint.WorldCFrame or wData.muzzle.CFrame
    if fireReadiness.weapon == w and os.clock() - fireReadiness.time < 0.15
        and (fireReadiness.pos - pos).Magnitude < 0.2 and fireReadiness.frame.LookVector:Dot(frame.LookVector) > 0.99999 then
        return fireReadiness.reason
    end
    local reason
    local map = workspace:FindFirstChild("Map")
    local protectors = map and map:FindFirstChild("SpawnProtectors")
    if protectors and (w:GetAttribute("ARTY") or w:GetAttribute("NotInSpawn") or w.Name == "Smoke Grenade") then
        fireReadiness.overlap = fireReadiness.overlap or OverlapParams.new()
        fireReadiness.overlap.FilterType = Enum.RaycastFilterType.Include
        fireReadiness.overlap.FilterDescendantsInstances = { protectors }
        fireReadiness.overlap.MaxParts = 1
        local radius = (w:GetAttribute("ARTY") or w.Name == "Smoke Grenade") and 100 or 5
        if #workspace:GetPartBoundsInRadius(wData.muzzle.Position, radius, fireReadiness.overlap) > 0 then
            reason = "Move outside spawn protection"
        end
    end
    if not reason and hookedWeaponHandler and wData.firePoint and wData.mainSight then
        local ok, result = pcall(function()
            local spawnHit = hookedWeaponHandler.raycastSpawnProtection(frame, 15)
            if spawnHit and lp.Team and spawnHit.Instance.Name ~= lp.Team.Name then return "Enemy spawn protection" end
            local clip = hookedWeaponHandler.raycastBarrelClipping(frame, (wData.mainSight.Position - pos).Magnitude, veh)
            if clip then return "Barrel clipping an obstacle" end
        end)
        if ok then reason = result else reason = "Weapon clearance unavailable" end
    end
    fireReadiness.weapon, fireReadiness.time = w, os.clock()
    fireReadiness.pos, fireReadiness.frame, fireReadiness.reason = pos, frame, reason
    return reason
end

local function calculateShotDirection(veh, wData, startPos, tankVel, speed, gravityY, drag, boreDir)
    local targetPos, targetVel, targetPart, hitNormal, rayDirection = getAimTarget(Settings.AimSource, veh)
    -- Preserve close finite hits. The launch solver and firing bearing guard
    -- decide validity; target acquisition must never turn ground into sky.
    local estTime = (targetPos - startPos).Magnitude / math.max(speed, 1)
    local predictedTarget = targetPos + targetVel * estTime
    local artilleryMode = wData and wData.weapon and wData.weapon:GetAttribute("ARTY") == true
    local minPitch, maxPitch = getTurretPitchLimits(wData and wData.turret)
    local idealLaunchDir, arc, previewDir = getLaunchDirection(startPos, predictedTarget, targetPart, speed,
        gravityY, drag, artilleryMode,
        boreDir, minPitch, maxPitch, getClearanceParams(veh), ballistics.lifetime(wData.shellData),
        veh.PrimaryPart and veh.PrimaryPart.CFrame.UpVector or Vector3.yAxis)
    if not idealLaunchDir then
        local previewVelocity = previewDir and (previewDir * speed - tankVel)
        return nil, targetPos, targetVel, targetPart, hitNormal, arc,
            previewVelocity and previewVelocity.Magnitude > 1e-4 and previewVelocity.Unit or nil
    end
    if arc == "barrel" then
        return idealLaunchDir, targetPos, targetVel, targetPart, hitNormal, arc
    end
    local relativeVelocity = idealLaunchDir * speed - tankVel
    if relativeVelocity.Magnitude < 1e-4 then return nil end
    return relativeVelocity.Unit, targetPos, targetVel, targetPart, hitNormal, arc
end

local function getShotAlignment(boreDir, desiredDir)
    return boreDir:Dot(desiredDir)
end

-- Sideways cursor steering is allowed; only near-backward launch directions
-- are rejected because they can spawn a projectile through the turret.
local MIN_BARREL_ALIGNMENT = -0.1

-- Native sight commands steer through the game's own rate/limit/damage
-- controller. No weld writes, remote calls or mouse/camera substitution.
ballistics.slave = {}
function ballistics.commandError(bore, desired, up)
    local flatBore = bore-up*bore:Dot(up)
    local flatAim = desired-up*desired:Dot(up)
    local yaw = 0
    if flatBore.Magnitude > 0.001 and flatAim.Magnitude > 0.001 then
        yaw = math.atan2(-up:Dot(flatBore.Unit:Cross(flatAim.Unit)),
            math.clamp(flatBore.Unit:Dot(flatAim.Unit),-1,1))
    end
    local pitch = math.asin(math.clamp(desired:Dot(up),-1,1))
        - math.asin(math.clamp(bore:Dot(up),-1,1))
    local cap = math.rad(12) -- Per-command bound, NOT a solver elevation limit.
    return Vector2.new(math.clamp(yaw,-cap,cap),math.clamp(-pitch,-cap,cap))
end
local function releaseArtillerySlave(preserveFailure)
    local state = ballistics.slave
    if state.value and state.value.Parent and state.last
        and state.value.Value == state.last and state.value:GetAttribute("type") == "none" then
        state.value.Value = Vector3.zero
        state.value:SetAttribute("type",state.originalType)
    end
    local stalled, reason = state.stalled, state.reason
    table.clear(state)
    if preserveFailure then state.stalled, state.reason = stalled, reason end
end
local function updateArtillerySlave(wData, startPos, direction, arc)
    local state = ballistics.slave
    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    local seat = hum and hum.SeatPart
    local control = wData and wData.turret and wData.turret:FindFirstChild("Control")
    local shouldSlave = Settings.ArtilleryAutoLay and isAdaptiveAimActive()
        and Settings.Freecam and freecamActive and wData and wData.weapon
        and control and control.Value == seat and seat ~= nil
        and direction ~= nil and arc == "high"
    if not shouldSlave then releaseArtillerySlave(); return false end
    if state.stalled then
        if state.stalled:Dot(direction) > math.cos(math.rad(3)) then return false end
        state.stalled = nil
    end
    local ngd = game:GetService("ReplicatedFirst"):FindFirstChild("NewGuiData")
    local gunner = ngd and ngd:FindFirstChild("Gunner")
    local data = gunner and gunner:FindFirstChild("Data")
    local command = data and data:FindFirstChild("CmdAngle")
    if not command or not command:IsA("Vector3Value") then
        releaseArtillerySlave(); state.reason = "native angle command unavailable"; return false
    end
    if state.value and (state.value ~= command or state.weapon ~= wData.weapon) then releaseArtillerySlave() end
    if (state.last and (command.Value ~= state.last or command:GetAttribute("type") ~= "none"))
        or (not state.last and Vector2.new(command.Value.X,command.Value.Y).Magnitude > 0.0001) then
        releaseArtillerySlave(); state.reason = "another sight control owns aim"; return false
    end
    local bore = getBoreForwardDirection(wData)
    local root = wData.vehicle and wData.vehicle.PrimaryPart
    local error = math.deg(math.acos(math.clamp(bore:Dot(direction),-1,1)))
    local now = os.clock()
    if not state.direction or state.direction:Dot(direction) < math.cos(math.rad(3))
        or error < (state.bestError or math.huge)-0.05 then
        state.progressAt, state.bestError = now,error
    end
    if error > 3 and now-(state.progressAt or now) > 3 then
        state.stalled, state.reason = direction,"native aim not responding; enable gunner optic or aim manually"
        releaseArtillerySlave(true)
        return false
    end
    state.direction = direction
    if now-(state.writeAt or -1) >= 0.05 then
        local delta = error <= 0.15 and Vector2.zero
            or ballistics.commandError(bore,direction,root and root.CFrame.UpVector or Vector3.yAxis)
        if not state.value then state.originalType = command:GetAttribute("type") end
        state.value = command
        state.weapon = wData.weapon
        command:SetAttribute("type","none")
        state.last = Vector3.new(delta.X,delta.Y,now)
        command.Value = state.last
        state.writeAt = now
    end
    state.reason = error <= 3 and "aligned" or "native angle command pending"
    return true
end

-- MTC calls FireBullet from a restricted game-script thread. Resolve all
-- Instance/camera work on our render thread before the Beam and firing hook
-- consume the aim cache, so cursor and preview share the same frame of aim.
local lastAimHint = nil
local aimCacheConn = nil
refreshAimCache = function()
    local now = os.clock()
    local ok, err = pcall(function()
        local veh = getActiveTank()
        local weapon = veh and getActiveWeaponData(veh)
        if not weapon or not weapon.muzzle then
            releaseArtillerySlave()
            aimCache.direction = nil
            aimCache.previewDirection = nil
            aimCache.vehicle = nil
            aimCache.weapon = nil
            aimCache.targetPos = nil
            aimCache.clearance = false
            aimCache.fireBlock = "No active weapon"
            aimCache.waitForAlignment, aimCache.solutionBlocked = false, false
            aimCache.reason = "no active weapon"
            return
        end
        local muzzle = weapon.muzzle
        local startPos = weapon.firePoint and weapon.firePoint.WorldPosition or muzzle.Position
        aimCache.startPos, aimCache.tankVelocity = startPos, muzzle.AssemblyLinearVelocity
        local boreDir = getBoreForwardDirection(weapon)
        if Settings.ShellRedirection then
            -- Redirection is exclusively a post-launch operation. Keep just
            -- native fire/shot identity data; no mouse rays or ballistic solve.
            releaseArtillerySlave()
            aimCache.vehicle, aimCache.weapon, aimCache.updated = veh,weapon,now
            aimCache.direction, aimCache.previewDirection = boreDir,nil
            aimCache.targetPos, aimCache.targetVel, aimCache.targetPart, aimCache.hitNormal = nil,nil,nil,nil
            aimCache.arc, aimCache.alignment, aimCache.bearingError = "barrel",1,0
            aimCache.barrelElevation = math.deg(math.asin(math.clamp(boreDir.Y,-1,1)))
            aimCache.launchElevation = aimCache.barrelElevation
            aimCache.waitForAlignment, aimCache.solutionBlocked, aimCache.turretSlaveActive = false,false,false
            aimCache.fireBlock = fireReadiness.check(veh,weapon)
            aimCache.clearance, aimCache.reason = aimCache.fireBlock==nil,aimCache.fireBlock or "native fire; mid-air redirection"
            local hint = "Fire normally; hold your lock key for mid-air redirection"
            if hint ~= lastAimHint then setFreecamHint(hint); lastAimHint=hint end
            return
        end
        local direction, targetPos, targetVel, targetPart, hitNormal, arc, previewDirection = calculateShotDirection(veh, weapon, startPos, muzzle.AssemblyLinearVelocity, weapon.speed, weapon.gravity, weapon.drag, boreDir)
        aimCache.direction = direction
        aimCache.previewDirection = previewDirection
        aimCache.vehicle = veh
        aimCache.weapon = weapon
        aimCache.targetPos = targetPos
        aimCache.targetVel = targetVel
        aimCache.targetPart = targetPart
        aimCache.hitNormal = hitNormal
        aimCache.arc = arc
        aimCache.updated = now
        aimCache.alignment = direction and getShotAlignment(boreDir, direction) or 0
        aimCache.barrelElevation = math.deg(math.asin(math.clamp(boreDir.Y, -1, 1)))
        aimCache.launchElevation = direction and math.deg(math.asin(math.clamp(direction.Y, -1, 1))) or nil
        local flatBore = Vector3.new(boreDir.X, 0, boreDir.Z)
        local flatAim = direction and Vector3.new(direction.X, 0, direction.Z)
        aimCache.bearingError = flatAim and flatAim.Magnitude > 0.001 and flatBore.Magnitude > 0.001
            and math.deg(math.acos(math.clamp(flatAim.Unit:Dot(flatBore.Unit), -1, 1))) or 0
        aimCache.fireBlock = fireReadiness.check(veh, weapon)
        aimCache.turretSlaveActive = updateArtillerySlave(weapon, startPos, direction, arc)
        -- Low-arc correction has the same bearing guard in either camera.
        -- Only a selected high lob requires precise barrel alignment.
        local slewing = isAdaptiveAimActive() and arc == "high" and direction ~= nil
            and aimCache.alignment < math.cos(math.rad(3))
        aimCache.waitForAlignment = slewing
        aimCache.solutionBlocked = isAdaptiveAimActive()
            and targetPart ~= nil and direction == nil
        if aimCache.solutionBlocked and not aimCache.fireBlock then aimCache.fireBlock = arc end
        if slewing and not aimCache.fireBlock then
            aimCache.fireBlock = not aimCache.turretSlaveActive and ballistics.slave.reason
                or "Waiting for barrel azimuth/elevation alignment"
        end
        aimCache.clearance = direction ~= nil and not slewing
        local unsafe = aimCache.alignment < MIN_BARREL_ALIGNMENT
        aimCache.reason = not direction and arc or slewing and
            (aimCache.turretSlaveActive and "turret slewing to target arc" or ballistics.slave.reason or "aim barrel to target arc")
            or unsafe and "turn barrel toward cursor" or "ready"
        if aimCache.fireBlock then aimCache.reason = aimCache.fireBlock end
        local hint = not direction and arc or slewing and
            (aimCache.turretSlaveActive and "Wait for the gun to reach target arc"
                or "Adjust barrel to the target arc")
            or unsafe and "Turn barrel toward cursor before firing"
            or "RMB look, WASD fly, Q/E height; driver LMB/F fires"
        if hint ~= lastAimHint then
            setFreecamHint(hint)
            lastAimHint = hint
        end
    end)
    if not ok then
        releaseArtillerySlave()
        aimCache.direction = nil
        aimCache.weapon = nil
        aimCache.previewDirection = nil
        aimCache.waitForAlignment, aimCache.solutionBlocked = false, false
        aimCache.reason = tostring(err)
    end
    visualDiagnostics.aimMs = (os.clock() - now) * 1000
end

extras.staffRoles = { Moderator = true, ["Non TC Dev"] = true, ["Game Admin"] = true,
    ["TC Dev"] = true, Administrator = true, Holder = true }
function extras.classifyRole(role)
    return extras.staffRoles[role] and "staff" or (role == "Content Creator" and "creator" or nil)
end
function extras.queueRole(player, force)
    if player == lp or extras.pending[player] or not extras.alive then return end
    extras.pending[player] = true
    extras.roleQueue = extras.roleQueue or {}
    extras.roleQueue[#extras.roleQueue + 1] = { player = player, force = force }
    if extras.roleWorker then return end
    extras.roleWorker = true
    task.spawn(function()
        while extras.alive and #extras.roleQueue > 0 do
            local item = table.remove(extras.roleQueue, 1)
            local p = item.player
            if p.Parent == Players then
                local role = not item.force and extras.roleCache[p]
                local ok = true
                if not role then ok, role = pcall(p.GetRoleInGroup, p, 32966202) end
                if extras.alive and p.Parent == Players then
                    if ok then
                        extras.roleCache[p] = role
                        local category = extras.classifyRole(role)
                        local enabled = category == "staff" and Settings.StaffNotifications
                            or category == "creator" and Settings.CreatorNotifications
                        if enabled and (item.force or extras.notified[p] ~= role) then
                            extras.notified[p] = role
                            extras.notify(p.DisplayName .. " (@" .. p.Name .. ") — " .. role .. " is in this server")
                        end
                    else
                        extras.roleError = tostring(role)
                        if not extras.roleErrorShown then
                            extras.roleErrorShown = true
                            extras.notify("Some group checks failed; staff presence is unknown for those players.")
                        end
                    end
                end
            end
            extras.pending[p] = nil
            task.wait(0.2) -- one yielding lookup worker, not one per-frame scan
        end
        extras.roleWorker = false
    end)
end
function extras.scanRoles(force)
    for _, player in ipairs(Players:GetPlayers()) do extras.queueRole(player, force) end
    if force then extras.notify("Checking current players' Top Giun roles…") end
end
extras.joined = Players.PlayerAdded:Connect(function(player)
    if Settings.StaffNotifications or Settings.CreatorNotifications then extras.queueRole(player) end
end)
extras.left = Players.PlayerRemoving:Connect(function(player)
    extras.roleCache[player], extras.notified[player] = nil, nil
end)


function extras.requestSupply(stationName, label)
    if not extras.alive or os.clock() - (extras.supplyAt or 0) < 1 then return end
    extras.supplyAt = os.clock()
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local map = workspace:FindFirstChild("Map")
    local stations = map and map:FindFirstChild("ToolGivers")
    if not root or not stations then extras.notify("Supply stations or your character are unavailable."); return end
    if type(fireclickdetector) ~= "function" then extras.notify("Use the supply station directly; click activation is unavailable."); return end
    local nearest, distance = nil, math.huge
    for _, station in ipairs(stations:GetChildren()) do
        if station.Name == stationName and station:IsA("Model") then
            local detector = station:FindFirstChildOfClass("ClickDetector")
            local d = (station:GetPivot().Position - root.Position).Magnitude
            if detector and d <= detector.MaxActivationDistance and d < distance then
                nearest, distance = detector, d
            end
        end
    end
    if not nearest then extras.notify("Move within pickup range of a " .. label .. " supply station."); return end
    local ok = pcall(fireclickdetector, nearest)
    extras.notify(ok and ("Requested " .. label .. "; the station/server decides whether to grant it.")
        or "Station activation failed; use it directly.")
end

-- Reversible local table edits; neither helper emits shots or changes remotes.
function extras.restoreEdits()
    for _, edit in ipairs(extras.edits) do
        if rawget(edit.target, edit.key) == edit.applied then edit.target[edit.key] = edit.original end
    end
    table.clear(extras.edits)
end
function extras.tune(target, key, multiplier, inverse)
    if type(target) ~= "table" or type(rawget(target, key)) ~= "number" or target[key] <= 0 then return end
    if table.isfrozen and table.isfrozen(target) then return end
    local edit
    for _, candidate in ipairs(extras.edits) do
        if candidate.target == target and candidate.key == key then edit = candidate; break end
    end
    if not edit then
        edit = { target = target, key = key, original = target[key], applied = target[key] }
        extras.edits[#extras.edits + 1] = edit
    end
    edit.wanted = true
    if edit.conflict or target[key] ~= edit.applied then edit.conflict = true; return end
    edit.applied = inverse and math.max(0.05, edit.original / multiplier) or edit.original * multiplier
    target[key] = edit.applied
end
function extras.updateTuning()
    for _, edit in ipairs(extras.edits) do edit.wanted = false end
    local veh = (Settings.TurretSpeedEnabled or Settings.TankRapidFire) and getActiveTank()
    local w = veh and getActiveWeaponData(veh)
    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    local control = w and w.turret and w.turret:FindFirstChild("Control")
    if hum and hum.SeatPart and control and control.Value == hum.SeatPart then
        if Settings.TurretSpeedEnabled then
            local module = w.turret:FindFirstChild("TurretInfo")
            if module and module:IsA("ModuleScript") then
                local data = require(module)
                local function axes(config)
                    if type(config) ~= "table" then return end
                    extras.tune(config.horizontal, 3, Settings.TurretSpeedMultiplier)
                    extras.tune(config.vertical, 3, Settings.TurretSpeedMultiplier)
                end
                axes(data.anglelimits)
                axes(data.FCS)
                for _, optic in pairs(type(data.Cameras) == "table" and data.Cameras or {}) do
                    if type(optic) == "table" then axes(optic.FCS) end
                end
            end
        end
        if Settings.TankRapidFire then
            -- Native code uses RPM as a delay (RPM / MuzzleCount), not shots/minute.
            extras.tune(w.shellData, "RPM", Settings.RapidFireMultiplier, true)
        end
    end
    for i = #extras.edits, 1, -1 do
        local edit = extras.edits[i]
        if not edit.wanted then
            if edit.target[edit.key] == edit.applied then edit.target[edit.key] = edit.original end
            table.remove(extras.edits, i)
        end
    end
end
extras.foliage = { roots = {}, changed = setmetatable({}, { __mode = "k" }), queue = {}, head = 1 }
function extras.foliage.kind(part, root)
    local node = part
    while node and node ~= root do
        local name = node.Name:lower():gsub("[%s_%-]", "")
        if name:match("^grass") or name:match("^tallgrass") then return "grass" end
        if name:match("^pine") or name:match("^tree") or name:match("^oak")
            or name:match("^birch") or name:match("^palm") then return "tree" end
        node = node.Parent
    end
end
function extras.foliage.restore()
    local f = extras.foliage
    for part, old in pairs(f.changed) do
        pcall(function()
            if part.LocalTransparencyModifier == 1 then part.LocalTransparencyModifier = old end
        end)
    end
    table.clear(f.changed)
    table.clear(f.queue)
    f.head = 1
end
function extras.foliage.decoration(disabled)
    local f = extras.foliage
    if f.grass == disabled then return end
    f.grass = disabled
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if not terrain then return end
    local ok, err = pcall(function()
        local read, old = pcall(function() return terrain.Decoration end)
        if not read and gethiddenproperty then old = gethiddenproperty(terrain, "Decoration"); read = true end
        assert(read, "Terrain decoration is unavailable")
        if disabled then f.decorationOriginal = old end
        local target = f.decorationOriginal
        if disabled then target = false end
        if target == nil or (not disabled and old ~= false) then return end
        local wrote = pcall(function() terrain.Decoration = target end)
        if not wrote then
            assert(sethiddenproperty, "Terrain decoration cannot be changed by this client")
            sethiddenproperty(terrain, "Decoration", target)
        end
    end)
    if not ok then f.error = tostring(err); extras.notify("No Grass: terrain decoration unavailable; mesh grass still supported.") end
end
function extras.foliage.update()
    local f = extras.foliage
    f.decoration(Settings.NoGrass)
    local mode = tostring(Settings.NoGrass) .. tostring(Settings.NoTrees)
    if f.mode ~= mode then
        f.mode = mode
        f.restore()
        for root, conn in pairs(f.roots) do conn:Disconnect(); f.roots[root] = nil end
    end
    if not Settings.NoGrass and not Settings.NoTrees then return end
    local roots = {}
    local map = workspace:FindFirstChild("Map")
    local parts = map and map:FindFirstChild("MapParts")
    if parts then roots[parts] = true end
    for _, child in ipairs(workspace:GetChildren()) do
        if child.Name == "Destructibles" or child.Name == "BillboardLods" then roots[child] = true end
    end
    for root, conn in pairs(f.roots) do
        if not roots[root] then conn:Disconnect(); f.roots[root] = nil end
    end
    for root in pairs(roots) do
        if not f.roots[root] then
            f.roots[root] = root.DescendantAdded:Connect(function(part)
                if part:IsA("BasePart") then f.queue[#f.queue+1] = {part, root} end
            end)
            for _, part in ipairs(root:QueryDescendants("BasePart")) do f.queue[#f.queue+1] = {part, root} end
        end
    end
    for _ = 1, 300 do
        local item = f.queue[f.head]
        if not item then table.clear(f.queue); f.head = 1; break end
        f.head = f.head + 1
        local part, root = item[1], item[2]
        if part.Parent and part:IsDescendantOf(root) then
            local kind = f.kind(part, root)
            if kind == "tree" and Settings.NoTrees or kind == "grass" and Settings.NoGrass then
                if f.changed[part] == nil then f.changed[part] = part.LocalTransparencyModifier end
                part.LocalTransparencyModifier = 1
            end
        end
    end
end
function extras.flushShots()
    if not Settings.ShotStatus then extras.shotCount = 0; return end
    if (extras.shotCount or 0) == 0 or os.clock() < (extras.nextShotToast or 0) then return end
    local count = extras.shotCount
    extras.shotCount, extras.nextShotToast = 0, os.clock() + 1
    extras.notify(count == 1 and "Shell fired · local dispatch confirmed"
        or string.format("%d shells fired · local dispatches confirmed", count))
end
extras.tick = RunService.Heartbeat:Connect(function()
    if not extras.alive or os.clock() < (extras.nextTick or 0) then return end
    extras.nextTick = os.clock() + 0.25
    extras.flushShots()
    local foliageOK, foliageError = pcall(extras.foliage.update)
    if not foliageOK and extras.foliage.error ~= tostring(foliageError) then
        extras.foliage.error = tostring(foliageError)
        extras.notify("Foliage update unavailable: " .. tostring(foliageError))
    end
    local enabled = (Settings.StaffNotifications and "staff" or "") .. (Settings.CreatorNotifications and "creator" or "")
    if enabled ~= extras.roleMode then
        extras.roleMode = enabled
        if enabled ~= "" then extras.scanRoles(false) end
    end
    local ok, err = pcall(extras.updateTuning)
    if not ok then extras.tuningError = tostring(err); extras.restoreEdits() end
end)

local function hookSingleWeaponModule(wm)
    if not wm or wm._AutoLeadHooked or type(wm.FireBullet) ~= "function" then return end
    wm._AutoLeadHooked = true
    local oldFB = wm.FireBullet

    wm.FireBullet = function(self, bulletData, ...)
        local ownShot = bulletData and bulletData.replicate == true
        local trackedWeapon = aimCache.weapon
        local entry = ownShot and trackedWeapon and (bulletData.origin == trackedWeapon.muzzle
            or bulletData.origin2 == trackedWeapon.muzzle
            or bulletData.misc and bulletData.misc.weaponfolder == trackedWeapon.weapon) and {
            weapon = trackedWeapon, vehicle = aimCache.vehicle, attempt = shotTracker.attempts,
            sentAt = os.clock(), predictedTime = visualDiagnostics.flightTime,
            redirectionFlight = Settings.ShellRedirection
        } or nil
        if isAdaptiveAimActive() and bulletData
            and bulletData.replicate == true and bulletData.directions then
            local originalDirection = bulletData.directions[1]
            local shotState = { applied = false, reason = "not checked", originalDirection = tostring(originalDirection), freecam = freecamActive, arc = aimCache.arc, highArc = aimCache.arc == "high", time = os.clock() }
            lastShotDiagnostics = shotState
            local ok, err = pcall(function()
                local finalDir = aimCache.direction
                if not finalDir or os.clock() - aimCache.updated > 1 then
                    shotState.reason = "aim cache unavailable: " .. aimCache.reason
                    return
                end
                -- Redirecting a shell backward through its own vehicle makes it
                -- collide immediately. Preserve native fire until the barrel
                -- points roughly toward the mouse ray.
                if not aimCache.clearance or aimCache.alignment < MIN_BARREL_ALIGNMENT then
                    shotState.reason = "barrel bearing differs from cursor; native direction kept"
                    return
                end

                for i = 1, #bulletData.directions do
                    bulletData.directions[i] = finalDir
                end
                shotState.applied = true
                shotState.reason = "mouse direction assigned"
                shotState.sentDirection = tostring(bulletData.directions[1])
                shotState.shell = tostring(bulletData.name)
            end)
            if not ok then shotState.reason = tostring(err) end
        end
        if entry then
            entry.launchPosition = aimCache.startPos
            local direction = bulletData.directions and bulletData.directions[1]
            entry.launchVelocity = direction and direction * trackedWeapon.speed + (aimCache.tankVelocity or Vector3.zero)
            entry.model = trackedWeapon.shellData and trackedWeapon.shellData.OverrideProjectileModel or "Default"
        end
        if ownShot then shotTracker.pendingSince = os.clock() end
        local results = table.pack(oldFB(self, bulletData, ...))
        if ownShot and bulletData.id and bulletData.effectfired then
            -- A confirmed launch wakes the Actor sampler; merely hovering or
            -- pressing fire cannot create a continuous sampling workload.
            shellRedirection.shotSerial=(shellRedirection.shotSerial or 0)+1
            shotTracker.serial = shotTracker.serial + 1
            if Settings.ShotStatus then extras.shotCount = (extras.shotCount or 0) + 1 end
            shotTracker.sent = os.clock()
            shotTracker.requested = nil
            if entry then
                -- Snapshot identity after native dispatch; do not retain the
                -- mutable bulletData packet as the tracking key.
                entry.id, entry.origin, entry.origin2 = bulletData.id, bulletData.origin, bulletData.origin2
                entry.serverTime = bulletData.timefired
                shotTracker.queue[#shotTracker.queue + 1] = entry
            else
                shotTracker.message, shotTracker.detail = "SHOT SENT", "Tracking unavailable for this weapon"
            end
        end
        return table.unpack(results, 1, results.n)
    end

    table.insert(hookedWeaponModules, { wm = wm, orig = oldFB })
end

-- Native gunner controllers debit their own counters AFTER fireWeapon returns.
-- Capture the caller's actual state, never a fixed upvalue index or a GC scan.
local ammoReconcile = { restored = 0, skipped = 0 }
function ammoReconcile.capture(caller, weapon, vehicle)
    if not Settings.InfiniteAmmo or not debug.getupvalues or not caller then return end
    local values = debug.getupvalues(caller)
    local counters, owner
    for _, value in pairs(values) do
        if type(value) == "table" then
            local candidate = rawget(value, weapon.Name)
            if type(candidate) == "table" and type(rawget(candidate, "Mag")) == "number" then
                if counters and counters ~= candidate then return end -- ambiguous owner
                counters, owner = candidate, value
            end
        end
    end
    if not counters then return end -- direct/unsupported caller
    local mag = weapon:FindFirstChild("Mag")
    if not mag or mag.Parent ~= weapon or counters.Mag <= 0 or mag.Value ~= counters.Mag then return end
    local snapshot = { caller = caller, counters = counters,
        owner = owner, weapon = weapon, vehicle = vehicle, name = weapon.Name,
        mag = mag, count = counters.Mag, entries = {} }
    for key, value in pairs(counters) do
        if type(value) == "table" and type(rawget(value, "value")) == "number" then
            snapshot.entries[key] = { ref = value, count = value.value }
        end
    end
    snapshot.others = rawget(counters, "Others")
    return snapshot
end
function ammoReconcile.finish(snapshot, ammo)
    if not snapshot then return end
    task.defer(function()
        local ok, err = pcall(function()
            local s = snapshot
            if not shotTracker.alive or not Settings.InfiniteAmmo or getActiveTank() ~= s.vehicle
                or s.weapon.Parent == nil or s.mag.Parent ~= s.weapon
                or rawget(s.owner, s.name) ~= s.counters then return end
            local stillOwned = false
            for _, value in pairs(debug.getupvalues(s.caller)) do
                if value == s.owner then stillOwned = true; break end
            end
            -- A reload, another writer or overlapping burst must not be overwritten.
            if not stillOwned or s.counters.Mag ~= s.count - 1 or s.mag.Value ~= s.count - 1 then
                ammoReconcile.skipped = ammoReconcile.skipped + 1
                return
            end
            s.mag.Value = s.count
            s.counters.Mag = s.count
            local entry = s.entries[ammo]
            if entry and entry.count > 0 and rawget(s.counters, ammo) == entry.ref
                and entry.ref.value == entry.count - 1 then
                local folder = s.weapon:FindFirstChild("AmmoLimitFolder")
                local counter = folder and folder:FindFirstChild(ammo)
                if not counter or counter.Value == entry.count - 1 then
                    if counter then counter.Value = entry.count end
                    entry.ref.value = entry.count
                end
            elseif not entry and type(s.others) == "number" and s.others > 0
                and s.counters.Others == s.others - 1 then
                s.counters.Others = s.others
            end
            ammoReconcile.restored = ammoReconcile.restored + 1
        end)
        if not ok then ammoReconcile.error = tostring(err) end
    end)
end

-- One hold session, shared by native gunner clicks and direct repeat requests.
local heldFire = { inputs = {}, nextAttempt = 0, nextAllowed = 0 }
function heldFire.stop()
    table.clear(heldFire.inputs)
    heldFire.vehicle, heldFire.weapon, heldFire.seat = nil, nil, nil
end
function heldFire.interval()
    local w = heldFire.data
    local delay = w and w.shellData and tonumber(w.shellData.RPM) or 0.1
    local count = w and w.shellData and tonumber(w.shellData.MuzzleCount) or 1
    return math.max(0.1, delay / math.max(1, count))
end
function heldFire.matches(vehicle, weapon)
    return Settings.TankRapidFire and next(heldFire.inputs) ~= nil
        and heldFire.vehicle == vehicle and heldFire.weapon == weapon
end

local function installHooks()
    -- 1. Hook WeaponModule from ClientHandler environment
    pcall(function()
        local ch = ReplicatedStorage:FindFirstChild("ClientHandler")
        if ch and getsenv then
            local env = getsenv(ch)
            if env and env.WeaponModule then
                hookSingleWeaponModule(env.WeaponModule)
            end
        end
    end)

    -- 2. Hook WeaponHandler.fireWeapon to intercept all weapon fires and hook their weaponModule
    pcall(function()
        local wh = require(ReplicatedStorage:WaitForChild("TankModules"):WaitForChild("WeaponHandler"))
        if wh and not oldFireWeapon then
            oldFireWeapon = wh.fireWeapon
            hookedWeaponHandler = wh

            wh.fireWeapon = function(p56, p57, u58, p59, p60, p61, p62, p63)
                if isAdaptiveAimActive()
                    and aimCache.vehicle == p59 and aimCache.weapon and aimCache.weapon.weapon == u58
                    and (aimCache.waitForAlignment or aimCache.solutionBlocked) then
                    shotTracker.reject(aimCache.fireBlock or "No ready adaptive shot solution")
                    return false
                end
                local held = heldFire.matches(p59, u58)
                if held and (heldFire.busy or os.clock() < heldFire.nextAllowed) then return false end
                if held then heldFire.busy = true end
                shotTracker.request("Weapon handler")
                local before = shotTracker.serial
                if p56 then
                    pcall(hookSingleWeaponModule, p56)
                end
                if p59 and (type(p57) == "string" or type(p57) == "number") then
                    pcall(function() shotCodeByVehicle[p59] = p57 end)
                end
                -- Off preserves the native caller's reload flag, including nil.
                -- Do not use 'enabled and false or p60': false would fall through.
                local reloadAfterShot = p60
                if Settings.InfiniteAmmo then reloadAfterShot = false end
                local ammoSnapshot
                if Settings.InfiniteAmmo and debug.info then
                    local ok, snapshot = pcall(ammoReconcile.capture, debug.info(2, "f"), u58, p59)
                    if ok then ammoSnapshot = snapshot else ammoReconcile.error = tostring(snapshot) end
                end
                local call = table.pack(pcall(oldFireWeapon, p56, p57, u58, p59, reloadAfterShot, p61, p62, p63))
                if held then
                    heldFire.busy = false
                    if shotTracker.serial > before then
                        heldFire.nextAllowed = os.clock() + heldFire.interval()
                    end
                end
                if not call[1] then error(call[2], 0) end
                local results = table.pack(table.unpack(call, 2, call.n))
                if results[1] == true and shotTracker.serial > before then
                    ammoReconcile.finish(ammoSnapshot, results[2])
                end
                if shotTracker.serial == before then
                    shotTracker.reject(shotTracker.gameErrorAt and os.clock() - shotTracker.gameErrorAt < 0.2
                        and shotTracker.gameError or aimCache.fireBlock or "Game did not launch a projectile")
                end
                return table.unpack(results, 1, results.n)
            end
        end
    end)

end

pcall(installHooks)

-- Direct firing from driver or freecam without replacing native gunner clicks.
triggerDirectFire = function()
    shotTracker.request("Direct fire")
    lastDirectFireError = nil
    local veh = getActiveTank()
    if not veh then return false, "No active vehicle" end
    local wData = getActiveWeaponData(veh)
    if not wData or not wData.weapon or not hookedWeaponHandler then return false, "Weapon unavailable" end

    local ch = ReplicatedStorage:FindFirstChild("ClientHandler")
    local env = getsenv and getsenv(ch)
    local wm = env and env.WeaponModule
    if not wm then return false, "Weapon module unavailable" end

    -- MTC supplies p57 when its server grants the gunner role. The driver-role
    -- event has no code, so only reuse one observed for this same vehicle.
    -- Passing a Weapon Folder here previously caused ExpRay errors.
    local shotCode = shotCodeByVehicle[veh]
    if not shotCode then
        lastDirectFireError = "No valid shot code observed for this vehicle"
        setFreecamHint("Driver fire needs a gunner code for this vehicle")
        return false, lastDirectFireError
    end

    local mainSight = wData.mainSight or wData.muzzle
    local startPos = wData.firePoint and wData.firePoint.WorldPosition or wData.muzzle.Position
    local tankVel = wData.muzzle.AssemblyLinearVelocity
    local boreDir = getBoreForwardDirection(wData)
    refreshAimCache()
    if aimCache.fireBlock then
        lastDirectFireError = aimCache.fireBlock
        setFreecamHint(lastDirectFireError)
        return false, lastDirectFireError
    end
    -- Invalid finite targets and pending high arcs were rejected above.
    -- With assistance disabled, retain the normal bore direction.
    local aimDirection = isAdaptiveAimActive()
        and aimCache.reason == "ready" and aimCache.direction or boreDir
    local ok, fired = pcall(function()
        -- MTC inserts -p62 into bulletData.directions, so pass the negative
        -- desired launch direction. The FireBullet hook then refines it again.
        -- Direct shots request normal unloading; the wrapper suppresses it only
        -- when Infinite Ammo / No Reload is explicitly enabled.
        return hookedWeaponHandler.fireWeapon(wm, shotCode, wData.weapon, veh, true, nil, -aimDirection, mainSight)
    end)
    if not ok then
        lastDirectFireError = tostring(fired)
        return false, lastDirectFireError
    end
    if fired ~= true then lastDirectFireError = "Game rejected fire request" end
    return fired == true, fired == true and "Fired" or "Game rejected fire request"
end

_G.AutoLeadAssistDiagnostics = function()
    local veh = getActiveTank()
    local weapon = veh and getActiveWeaponData(veh)
    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    local targetPos, targetPart
    if veh then
        local pos, _, part = getAimTarget(Settings.AimSource, veh)
        targetPos, targetPart = pos, part
    end
    local cam = workspace.CurrentCamera
    local mouse = lp:GetMouse()
    local aimSource = Settings.Freecam and freecamActive and "Mouse" or Settings.AimSource
    local ngd = game:GetService("ReplicatedFirst"):FindFirstChild("NewGuiData")
    local sightAngle = ngd and ngd:FindFirstChild("Gunner") and ngd.Gunner:FindFirstChild("Data")
        and ngd.Gunner.Data:FindFirstChild("AngleIndicator")
        and ngd.Gunner.Data.AngleIndicator:FindFirstChild("Elevation")
    local startPos = weapon and (weapon.firePoint and weapon.firePoint.WorldPosition or weapon.muzzle.Position)
    return {
        seat = hum and hum.SeatPart and hum.SeatPart:GetFullName() or "none",
        turret = weapon and weapon.turret and weapon.turret.Name or "none",
        weapon = weapon and weapon.weaponName or "none",
        loaded = weapon and weapon.loaded or "none",
        freecam = freecamActive,
        artilleryControl = { enabled = Settings.ArtilleryAutoLay, reason = ballistics.slave.reason,
            commandOwned = ballistics.slave.value ~= nil, waitingForAlignment = aimCache.waitForAlignment == true },
        clickTeleport = Settings.FreecamClickTP,
        heldFire = { active = next(heldFire.inputs) ~= nil, busy = heldFire.busy == true },
        adaptiveAim = Settings.AdaptiveAim,
        adaptiveAimActive = isAdaptiveAimActive(),
        shellRedirection = { enabled = Settings.ShellRedirection, radiusPixels = Settings.ShellFocusRadius,
            lockKey = tostring(Settings.ShellFocusKey), visibilityCheck = Settings.ShellVisibilityCheck,
            launchAssistsSuspended = Settings.ShellRedirection,
            held = shellRedirection.held, engaged = shellRedirection.isEngaged() == true,
            focusedPlayer = shellRedirection.focused and shellRedirection.focused.Name or nil,
            transport = "actor-local target sampling",
            freecamRmbOwner = Settings.ShellRedirection and Settings.ShellFocusKey==Enum.UserInputType.MouseButton2
                and "target lock" or "camera look",
            updateMs = shellRedirection.updateMs,
            readyActors = shellRedirection.ready or 0, error = shellRedirection.error,
            focusScans = shellRedirection.focusScans, focusRays = shellRedirection.focusRays,
            visualWrites = shellRedirection.visualWrites, frameMs = shellRedirection.frameMs },
        infiniteAmmo = Settings.InfiniteAmmo,
        vehicleExtras = { localEdits = #extras.edits, error = extras.tuningError,
            turretSpeedEnabled = Settings.TurretSpeedEnabled, rapidFireEnabled = Settings.TankRapidFire },
        groupChecks = { groupId = 32966202, error = extras.roleError,
            staffEnabled = Settings.StaffNotifications, creatorEnabled = Settings.CreatorNotifications },
        ammoReconcile = { restored = ammoReconcile.restored, skipped = ammoReconcile.skipped,
            error = ammoReconcile.error },
        weaponHook = hookedWeaponHandler ~= nil,
        directFireReady = veh and shotCodeByVehicle[veh] ~= nil or false,
        directFireError = lastDirectFireError,
        lastShot = lastShotDiagnostics,
        preview = visualDiagnostics,
        esp = { players = espStats.players, tanks = espStats.tanks,
            timings = espStats.timings,
            backend = playerEsp and "esp-lib.lua" or "unavailable", error = espStats.error,
            playerEnabled = Settings.PlayerESP, tankEnabled = Settings.EnemyTankESP,
            boxesEnabled = Settings.ESPBoxes },
        foliage = { noGrass = Settings.NoGrass, noTrees = Settings.NoTrees,
            error = extras.foliage.error, pending = math.max(0, #extras.foliage.queue - extras.foliage.head + 1) },
        armor = { enabled = Settings.ZeroEnemyArmor, vehicles = armorStats.vehicles,
            values = armorStats.values, clientSideOnly = true },
        zoom = { enabled = Settings.Zoom, fov = Settings.ZoomFOV },
        firingShake = { enabled = Settings.DisableFiringShake, active = firingShake.active == true,
            error = firingShake.error },
        explosionShake = { enabled = Settings.DisableExplosionShake,
            active = firingShake.explosions ~= nil, error = firingShake.explosionError },
        cameraShakeSink = { active = firingShake.sink ~= nil and firingShake.sink.enabled == true
                and Settings.DisableFiringShake and Settings.DisableExplosionShake,
            error = firingShake.sinkError },
        shotTracking = { message = shotTracker.message, detail = shotTracker.detail,
            active = #shotTracker.entries, dispatched = shotTracker.serial,
            observed = shotTracker.observed, rejected = shotTracker.rejected, scanMs = shotTracker.lastScanMs,
            lastObserved = shotTracker.lastObserved,
            latest = shotTracker.entries[#shotTracker.entries] and {
                status = shotTracker.entries[#shotTracker.entries].status,
                progress = shotTracker.entries[#shotTracker.entries].progress,
                eta = shotTracker.entries[#shotTracker.entries].eta,
                target = tostring(shotTracker.entries[#shotTracker.entries].expectedEnd),
                discoveryError = shotTracker.entries[#shotTracker.entries].discoveryError,
                observed = shotTracker.entries[#shotTracker.entries].state ~= nil
            } or nil },
        aimCache = { ready = aimCache.reason == "ready", fireBlock = aimCache.fireBlock,
            bearingError = aimCache.bearingError, age = os.clock() - aimCache.updated, reason = aimCache.reason, alignment = aimCache.alignment, clearance = aimCache.clearance, arc = aimCache.arc, barrelElevation = aimCache.barrelElevation, launchElevation = aimCache.launchElevation, turretSlaveActive = aimCache.turretSlaveActive, direction = tostring(aimCache.direction) },
        sightElevation = sightAngle and sightAngle.Value or nil,
        blastRadius = weapon and getExplosionRadius(weapon.shellData) * 0.5 or 0,
        aimSource = aimSource,
        aimTarget = targetPart and targetPart:GetFullName() or "open sightline",
        aimDistance = startPos and targetPos and (targetPos - startPos).Magnitude or 0,
        mouseDirection = mouse and mouse.UnitRay and tostring(mouse.UnitRay.Direction) or "none",
        cameraDirection = cam and tostring(cam.CFrame.LookVector) or "none",
        launchDirection = aimCache.direction and tostring(aimCache.direction) or "none",
    }
end

_G.AutoLeadAssistSetFreecam = function(enabled)
    Settings.Freecam = enabled == true
    setFreecam(Settings.Freecam)
    if freecamToggleHandle then pcall(function() freecamToggleHandle:Set(Settings.Freecam) end) end
end

_G.AutoLeadAssistSetZoom = function(enabled)
    setZoom(enabled)
    if zoomToggleHandle then pcall(function() zoomToggleHandle:Set(Settings.Zoom) end) end
end

-- Actual surface hits only: no horizon-plane fallback and no vehicle movement.
function heldFire.clickTeleport()
    if not Settings.FreecamClickTP or not Settings.Freecam or not freecamActive then return end
    local character = lp.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or humanoid.SeatPart or humanoid.Sit or not root then
        setFreecamHint("Click teleport requires being on foot")
        return
    end
    local camera = workspace.CurrentCamera
    if not camera or os.clock() < (heldFire.nextTeleport or 0) then return end
    heldFire.nextTeleport = os.clock() + 0.5
    local mouse = UserInputService:GetMouseLocation()
    local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { character, visualContainer }
    params.RespectCanCollide = true
    local hit = workspace:Raycast(ray.Origin, ray.Direction * 15000, params)
    if not hit or hit.Normal.Y < 0.5 then
        setFreecamHint("Click visible ground, not a wall or sky")
        return
    end
    -- R6 HipHeight is zero; its leg height must also clear the ground.
    local leg = character:FindFirstChild("Left Leg")
    local height = humanoid.HipHeight + root.Size.Y * 0.5
        + (humanoid.RigType == Enum.HumanoidRigType.R6 and leg and leg.Size.Y or 0) + 0.5
    local target = hit.Position + Vector3.yAxis * height
    local clearance = workspace:Raycast(hit.Position + Vector3.yAxis * 0.1,
        Vector3.yAxis * (height + root.Size.Y), params)
    if clearance then setFreecamHint("Not enough headroom at that point"); return end
    heldFire.stop()
    character:PivotTo(CFrame.new(target - root.Position) * character:GetPivot())
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    setFreecamHint("Character moved; freecam stays in place")
end

-- A gunner's first mouse click stays native. Subsequent held requests share
-- the handler cooldown, so automatic native weapons do not get a second stream.
local lastDirectFireTime = 0
local freecamFireConn = UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe or UserInputService:GetFocusedTextBox() then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 and Settings.FreecamClickTP
        and Settings.Freecam and freecamActive
        and (UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)) then
        heldFire.clickTeleport()
        return
    end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.F then
        shotTracker.request("Input received")
        if Settings.TankRapidFire then
            local vehicle = getActiveTank()
            local w = vehicle and getActiveWeaponData(vehicle)
            local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
            if w and hum and hum.Health > 0 and hum.SeatPart then
                heldFire.vehicle, heldFire.weapon, heldFire.data, heldFire.seat = vehicle, w.weapon, w, hum.SeatPart
                heldFire.inputs[input.UserInputType == Enum.UserInputType.MouseButton1 and "mouse" or "key"] = true
                heldFire.nextAttempt = os.clock() + heldFire.interval()
            end
        end
    end
    local wantsDirectFire = input.KeyCode == Enum.KeyCode.F
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if gpe then return end -- clicking the settings UI is not firing
        local veh = getActiveTank()
        local weapon = veh and getActiveWeaponData(veh)
        local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
        local seat = hum and hum.SeatPart
        local control = weapon and weapon.turret and weapon.turret:FindFirstChild("Control")
        wantsDirectFire = veh ~= nil and weapon ~= nil and seat ~= nil
            and not (control and control.Value == seat)
    end
    if wantsDirectFire then
        local now = os.clock()
        if triggerDirectFire and now - lastDirectFireTime >= 0.08 then
            lastDirectFireTime = now
            local fired, reason = triggerDirectFire()
            if not fired then shotTracker.reject(reason) end
        end
    end
end)
heldFire.ended = UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then heldFire.inputs.mouse = nil end
    if input.KeyCode == Enum.KeyCode.F then heldFire.inputs.key = nil end
    if next(heldFire.inputs) == nil then heldFire.stop() end
end)
heldFire.focus = UserInputService.WindowFocusReleased:Connect(heldFire.stop)
shellRedirection.began=UserInputService.InputBegan:Connect(shellRedirection.inputBegan)
shellRedirection.ended=UserInputService.InputEnded:Connect(shellRedirection.inputEnded)
shellRedirection.focusLost=UserInputService.WindowFocusReleased:Connect(shellRedirection.release)
shellRedirection.tick=RunService.Heartbeat:Connect(function()
    -- Never fan out Actor state from the camera/render callback.
    local started=os.clock()
    local ok,err=pcall(shellRedirection.update)
    shellRedirection.updateMs=(os.clock()-started)*1000
    if not ok then
        shellRedirection.error=tostring(err);shellRedirection.failed=true
        pcall(shellRedirection.release);pcall(shellRedirection.stop)
    end
end)
heldFire.tick = RunService.Heartbeat:Connect(function()
    firingShake.refreshSink()
    if next(heldFire.inputs) == nil then return end
    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    local vehicle = getActiveTank()
    local w = vehicle and getActiveWeaponData(vehicle)
    if not Settings.TankRapidFire or UserInputService:GetFocusedTextBox() or not hum or hum.Health <= 0
        or not hum.SeatPart or hum.SeatPart ~= heldFire.seat or vehicle ~= heldFire.vehicle
        or not w or w.weapon ~= heldFire.weapon then heldFire.stop(); return end
    heldFire.data = w
    local now = os.clock()
    if heldFire.busy or now < heldFire.nextAttempt or now < heldFire.nextAllowed then return end
    heldFire.nextAttempt = now + heldFire.interval()
    local ok, fired, reason = pcall(triggerDirectFire)
    if not ok then heldFire.stop(); shotTracker.reject(tostring(fired))
    elseif not fired then shotTracker.reject(reason) end
end)

-- ===================================================================
-- SCRIPT UNLOAD / CLEANUP HANDLER
-- ===================================================================

_G.AutoLeadAssistUnload = function()
    extras.alive = false
    extras.tick:Disconnect()
    for _, conn in pairs(extras.foliage.roots) do conn:Disconnect() end
    extras.foliage.restore()
    extras.foliage.decoration(false)
    extras.joined:Disconnect()
    extras.left:Disconnect()
    extras.restoreEdits()
    shotTracker.alive = false
    shotTracker.flightGui:Destroy()
    if shotTracker.partsAdded then shotTracker.partsAdded:Disconnect() end
    for _, record in pairs(shotTracker.candidates) do shotTracker.releaseCandidate(record) end
    if shotTracker.notification then shotTracker.notification:Disconnect() end
    RunService:UnbindFromRenderStep("AutoLeadShotTracking")
    for _, entry in ipairs(shotTracker.entries) do shotTracker.remove(entry) end
    releaseArtillerySlave()
    if uiInsertConn then uiInsertConn:Disconnect() end
    shellRedirection.destroy()
    if vibeUi then pcall(function() vibeUi:Unload() end) end
    if screenGui then screenGui:Destroy() end
    espStats.gui:Destroy()
    if visualContainer then visualContainer:Destroy() end
    for _, attachment in ipairs(beamAttachments) do attachment:Destroy() end
    for _, tag in pairs(playerDrawings) do removePlayerDrawing(tag) end
    RunService:UnbindFromRenderStep(VISUAL_RENDER_NAME)
    if aimCacheConn then aimCacheConn:Disconnect() end
    RunService:UnbindFromRenderStep("AttributePlayerESP")
    if playerEsp then playerEsp.unload() end
    if freecamFireConn then freecamFireConn:Disconnect() end
    heldFire.stop()
    heldFire.ended:Disconnect()
    heldFire.focus:Disconnect()
    heldFire.tick:Disconnect()
    setZoom(false)
    for _, connection in pairs(armorVehicleWatchers) do connection:Disconnect() end
    for value, original in pairs(originalEnemyArmor) do
        restoreEnemyArmor(value, original)
        originalEnemyArmor[value] = nil
    end

    for _, entry in ipairs(hookedWeaponModules) do
        if entry.wm and entry.orig then
            entry.wm.FireBullet = entry.orig
            entry.wm._AutoLeadHooked = nil
        end
    end

    if hookedWeaponHandler and oldFireWeapon then
        hookedWeaponHandler.fireWeapon = oldFireWeapon
    end
    setFreecam(false)
    firingShake.restore()
    firingShake.restoreExplosions()
    firingShake.restoreSink()
    _G.AutoLeadAssistDiagnostics = nil
    _G.AutoLeadAssistSetFreecam = nil
    _G.AutoLeadAssistSetZoom = nil
end

print("[AutoLead] AutoLead & Ballistics Assist loaded successfully!")
