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
for _, guiName in ipairs({ "AutoLeadSettingsUI", "AutoLeadOverlay" }) do
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
    AutoLead = true,
    AutoBallistic = rememberedSettings.AutoBallistic == true,
    InfiniteAmmo = rememberedSettings.InfiniteAmmo == true,
    TurretSpeedEnabled = rememberedSettings.TurretSpeedEnabled == true,
    TurretSpeedMultiplier = math.clamp(tonumber(rememberedSettings.TurretSpeedMultiplier) or 1, 0.25, 3),
    TankRapidFire = rememberedSettings.TankRapidFire == true,
    RapidFireMultiplier = math.clamp(tonumber(rememberedSettings.RapidFireMultiplier) or 2, 1, 5),
    StaffNotifications = rememberedSettings.StaffNotifications ~= false,
    CreatorNotifications = rememberedSettings.CreatorNotifications ~= false,
    EnemyTankESP = rememberedSettings.EnemyTankESP ~= false,
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

            -- Keep the cursor movable for mouse-pointed shots. RMB temporarily
            -- locks it for camera rotation, then releases it when RMB is let go.
            local looking = UserInputService:GetFocusedTextBox() == nil
                and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
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
            settingToggle(aimAssist, "Auto Lead", "AutoLead", "Steer shots toward the selected point.")
            settingToggle(aimAssist, "Auto Ballistic", "AutoBallistic", "Prefer a clear high arc within the gun's elevation limits.")
            local aimTarget = aimTab:Section({ Name = "Targeting", Side = 2 })
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
            settingToggle(path, "Shot Confirmation", "ShotStatus", "Distinguish clicks, launch, impact, and rejected shots.")
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
            settingToggle(espTargets, "Enemy Tank Highlight", "EnemyTankESP", "Highlight nearby enemy tanks without labels.")
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
local function solveBallistic(startPos, targetPos, speed, g, highArc)
    local diff = targetPos - startPos
    if diff.Magnitude < 0.1 then return Vector3.new(0, 1, 0), false end
    if speed <= 0 then return diff.Unit, false end
    local distXZ = Vector3.new(diff.X, 0, diff.Z).Magnitude
    local diffY = diff.Y
    if distXZ < 0.1 then
        return Vector3.new(0, diffY >= 0 and 1 or -1, 0), true
    end

    local gMag = math.abs(g)
    if gMag < 1e-4 then return diff.Unit, true, math.atan2(diffY, distXZ) end
    local v2 = speed * speed
    local v4 = v2 * v2
    local disc = v4 - gMag * (gMag * distXZ * distXZ + 2 * diffY * v2)
    local dirXZ = Vector3.new(diff.X, 0, diff.Z).Unit

    if disc >= 0 then
        local sqrtDisc = math.sqrt(disc)
        local tanTheta
        if highArc then
            tanTheta = (v2 + sqrtDisc) / (gMag * distXZ)
        else
            tanTheta = (v2 - sqrtDisc) / (gMag * distXZ)
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

local function pathReachesTarget(startPos, targetPos, direction, speed, gravityY, drag, params)
    local offset = targetPos - startPos
    local horizontalDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude
    local horizontalSpeed = Vector3.new(direction.X, 0, direction.Z).Magnitude * speed
    if horizontalDistance < 0.1 or horizontalSpeed < 0.1 then return false end
    local d = math.max(tonumber(drag) or 0, 0)
    local flightTime
    if d > 1e-5 then
        local remaining = 1 - d * horizontalDistance / horizontalSpeed
        if remaining <= 0 then return false end
        flightTime = -math.log(remaining) / d
    else
        flightTime = horizontalDistance / horizontalSpeed
    end
    if flightTime > 60 then return false end
    local horizontalDirection = Vector3.new(direction.X, 0, direction.Z).Unit
    local steps = math.clamp(math.ceil(flightTime / 0.25), 8, 48)
    local previous = startPos
    local tolerance = math.max(12, horizontalDistance * 0.002)
    for i = 1, steps do
        local t = flightTime * i / steps
        local distance = d > 1e-5 and horizontalSpeed * (1 - math.exp(-d * t)) / d or horizontalSpeed * t
        local nextPos = startPos + horizontalDirection * distance
            + Vector3.yAxis * (direction.Y * speed * t + 0.5 * gravityY * t * t)
        local hit = workspace:Raycast(previous, nextPos - previous, params)
        if hit then return (hit.Position - targetPos).Magnitude <= tolerance end
        previous = nextPos
    end
    return (previous - targetPos).Magnitude <= tolerance
end

local function solveDraggedArcs(startPos, targetPos, speed, gravityY, drag, minPitch, maxPitch)
    local offset = targetPos - startPos
    local horizontal = Vector3.new(offset.X, 0, offset.Z)
    local range = horizontal.Magnitude
    if range < 0.1 or speed <= 0 then return nil, nil end
    local unit = horizontal.Unit
    local lowLimit = math.max(minPitch, math.rad(-89))
    local highLimit = math.min(maxPitch, math.rad(89))
    local function heightError(pitch)
        local vx = speed * math.cos(pitch)
        local remaining = 1 - drag * range / vx
        if remaining <= 0 then return nil end
        local t = -math.log(remaining) / drag
        if t > 60 then return nil end
        return speed * math.sin(pitch) * t + 0.5 * gravityY * t * t - offset.Y
    end
    local roots = {}
    local lastPitch, lastError = lowLimit, heightError(lowLimit)
    for i = 1, 48 do
        local pitch = lowLimit + (highLimit - lowLimit) * i / 48
        local err = heightError(pitch)
        if lastError and err and lastError * err <= 0 then
            local a, b, fa = lastPitch, pitch, lastError
            for _ = 1, 18 do
                local mid = (a + b) * 0.5
                local fm = heightError(mid)
                if not fm then break end
                if fa * fm <= 0 then b = mid else a, fa = mid, fm end
            end
            local root = (a + b) * 0.5
            roots[#roots + 1] = { direction = (unit * math.cos(root) + Vector3.yAxis * math.sin(root)).Unit, pitch = root }
        end
        lastPitch, lastError = pitch, err
    end
    return roots[1], #roots > 1 and roots[#roots] or nil
end

local function getLaunchDirection(startPos, targetPos, targetPart, speed, gravityY, drag,
    artilleryMode, preferHigh, boreDir, minPitch, maxPitch, params)
    local offset = targetPos - startPos
    if offset.Magnitude < 0.1 then return nil, "unreachable" end
    if not targetPart then
        -- Open sky has a bearing but no finite coordinate to land a shell on.
        if artilleryMode and boreDir then
            local horizontal = Vector3.new(offset.X, 0, offset.Z)
            if horizontal.Magnitude < 0.1 then return boreDir, "barrel" end
            local vertical = math.clamp(boreDir.Y, -0.999, 0.999)
            return (horizontal.Unit * math.sqrt(1 - vertical * vertical) + Vector3.yAxis * vertical).Unit, "barrel"
        end
        return offset.Unit, "bearing"
    end

    local lowDir, lowPossible, lowPitch = solveBallistic(startPos, targetPos, speed, gravityY, false)
    if not artilleryMode then
        return lowPossible and lowDir or nil, lowPossible and "low" or "Target exceeds ammunition range"
    end
    local highDir, highPossible, highPitch = solveBallistic(startPos, targetPos, speed, gravityY, true)
    if not lowPossible and not highPossible and (not drag or drag <= 1e-5) then
        return nil, "Target exceeds ammunition range"
    end
    if drag and drag > 1e-5 then
        local draggedLow, draggedHigh = solveDraggedArcs(startPos, targetPos, speed, gravityY,
            drag, minPitch, maxPitch)
        lowDir, lowPitch, lowPossible = draggedLow and draggedLow.direction,
            draggedLow and draggedLow.pitch, draggedLow ~= nil
        highDir, highPitch, highPossible = draggedHigh and draggedHigh.direction,
            draggedHigh and draggedHigh.pitch, draggedHigh ~= nil
    end
    local margin = math.rad(0.25)
    local lowLegal = lowPossible and lowPitch and lowPitch >= minPitch - margin and lowPitch <= maxPitch + margin
    local highLegal = highPossible and highPitch and highPitch >= minPitch - margin and highPitch <= maxPitch + margin
    local function clear(direction)
        return pathReachesTarget(startPos, targetPos, direction, speed, gravityY, drag, params)
    end
    if preferHigh and highLegal and clear(highDir) then return highDir, "high" end
    -- Automatic selection is distance/clearance based, independent of camera
    -- mode and current barrel angle. A high arc does not extend maximum range.
    if lowLegal and clear(lowDir) then return lowDir, "low" end
    if highLegal and clear(highDir) then return highDir, "high" end
    if not highLegal and not lowLegal then return nil, "target outside gun elevation" end
    -- Retain a display-only candidate so an obstruction can shorten the red
    -- preview instead of making it jump to the unrelated bore trajectory.
    return nil, "trajectory blocked", (preferHigh and highLegal and highDir)
        or (lowLegal and lowDir) or (highLegal and highDir)
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
    local distance = (endPos - startPos).Magnitude
    local handleLimit = math.max(distance * 3, 500)
    preview.beam.CurveSize0 = math.min(startVelocity.Magnitude * flightTime / 3, handleLimit)
    preview.beam.CurveSize1 = math.min(endVelocity.Magnitude * flightTime / 3, handleLimit)
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
    blastZone.Transparency = 1
    blastDistance.gui.Enabled = false
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
    borePreview.beam.Enabled = false
    leadPreview.beam.Enabled = false
    hideBlastZone()
    impactHud.Visible = false
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
    local pos = startPos
    local vel = initialVel
    local totalTime = 0
    local collisionStride = math.max(1, math.ceil(maxSteps / 48))
    local castStart = pos
    local castCount = 0
    local lastCastIndex = 0

    for i = 1, maxSteps do
        local nextPos
        if not drag or drag <= 0 then
            local t = (i * dt)
            nextPos = startPos + initialVel * t + Vector3.yAxis * (0.5 * gravityY * t * t)
            vel = initialVel + Vector3.yAxis * (gravityY * t)
        else
            vel = vel + Vector3.new(0, gravityY * dt, 0)
            vel = vel - vel * drag * dt * Vector3.new(1, 0, 1)
            nextPos = pos + vel * dt
        end
        pos = nextPos
        totalTime = totalTime + dt
        if i % collisionStride == 0 or i == maxSteps then
            castCount = castCount + 1
            local hit = workspace:Raycast(castStart, nextPos - castStart, params)
            if hit then
                local castDistance = (nextPos - castStart).Magnitude
                local fraction = castDistance > 0 and math.clamp((hit.Position - castStart).Magnitude / castDistance, 0, 1) or 1
                local impactTime = totalTime - (i - lastCastIndex) * dt * (1 - fraction)
                return hit.Position, hit, impactTime, castCount, vel
            end
            castStart = nextPos
            lastCastIndex = i
        end
    end

    return pos, nil, totalTime, castCount, vel
end

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
    if not Settings.EnableAutoLead or not (Settings.Trajectory or Settings.ShowBallistic
        or Settings.ExplosionRadius or Settings.ShowDistance or Settings.FlightTimer) then
        hideVisuals()
        visualDiagnostics.blastVisible = false
        visualDiagnostics.blastColor = nil
        visualDiagnostics.blastOccupied = false
        visualDiagnostics.plannedAim = false
        visualDiagnostics.assistReady = false
        visualDiagnostics.hit = nil
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
    local flightTime = targetPart and math.clamp(
        (horizontalRange > 0.1 and horizontalRange / math.max(horizontalSpeed, 1) or estTime) + 0.65,
        0.7, 60
    ) or math.clamp(6500 / math.max(muzzleSpeed, 1), 2, 12)
    if aimCache.arc == "barrel" or previewDirection == nil then
        -- A nearby cursor pixel is only a bearing in artillery mode. Preview
        -- the shell's natural airborne time instead of stopping at that pixel.
        -- An invalid finite aim also needs enough time to find the true bore
        -- impact, so its red area can join the physical trajectory endpoint.
        local gravityMagnitude = math.max(math.abs(gravityY), 1)
        local airborneTime = 2 * math.max(previewVelocity.Y, 0) / gravityMagnitude
        flightTime = math.clamp(math.max(flightTime, airborneTime + 3), 3, 60)
    end
    -- Coarse preview integration; the firing aim is calculated separately.
    -- Collision rays still cover each batch of steps to find the impact.
    local simSteps = math.clamp(math.ceil(flightTime / 0.18), 8, 120)
    local simDt = flightTime / simSteps

    local aimRequested = Settings.AutoLead or Settings.AutoBallistic
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
            local displayTime = leadHit and leadTime or math.max(0.05,
                horizontalRange / math.max(horizontalSpeed, 1))
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
    espStats.tanks = 0
    local vehicles = workspace:FindFirstChild("SpawnedVehicles")
    if Settings.EnemyTankESP and vehicles and lp.Team and lp.Team.Name ~= "Neutral" then
        local candidates = {}
        local myColor = lp.TeamColor.Name
        for _, veh in ipairs(vehicles:GetChildren()) do
            local enemyTeam = veh:GetAttribute("Team")
            local class = veh:GetAttribute("VehicleGeneralClass")
            if veh:IsA("Model") and veh:GetAttribute("Type") == "Tank"
                and enemyTeam and tostring(enemyTeam) ~= myColor
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
            local highlight = tankHighlights[veh]
            if not highlight then
                highlight = Instance.new("Highlight")
                highlight.Name = "AutoLeadEnemyTank"
                highlight.Adornee = veh
                highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                highlight.FillTransparency = 0.94
                highlight.OutlineTransparency = 0.08
                highlight.Parent = visualContainer
                tankHighlights[veh] = highlight
            end
            highlight.FillColor = getESPColor()
            highlight.OutlineColor = getESPColor()
            seen[veh] = true
            espStats.tanks = espStats.tanks + 1
        end
    end
    for veh, highlight in pairs(tankHighlights) do
        if not seen[veh] then
            highlight:Destroy()
            tankHighlights[veh] = nil
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
    local origin = camera.CFrame.Position
    if now - lastPlayerScan >= 0.25 then
        lastPlayerScan = now
        scanEnemyPlayers(origin)
    end
    updatePlayerDrawings(camera)
    if now - lastTankScan >= 0.75 then
        lastTankScan = now
        scanEnemyTanks(origin)
    end
    if now - lastArmorScan >= 1.5 then
        lastArmorScan = now
        scanEnemyArmor()
    end
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
    local w = entry.weapon
    local duration = math.max(entry.predictedTime or 0, 2 * math.max(entry.initialVelocity.Y, 0) / math.max(math.abs(w.gravity), 1) + 3)
    duration = math.min(duration, tonumber(state.Lifetime) or 60, 60)
    local steps = math.clamp(math.ceil(duration / 0.18), 8, 120)
    local finish, hit, time, _, endVelocity = traceTrajectory(entry.start, entry.initialVelocity,
        w.gravity, w.drag, getTrajectoryParams(entry.vehicle), steps, duration / steps)
    entry.expectedTime, entry.expectedEnd, entry.expectedHit = time, finish, hit ~= nil
    -- A full forecast is retained, but completed geometry comes from observed
    -- movement. Pixel-width segments avoid subpixel world-Beam stippling.
    local p0, p3 = entry.start, finish
    local p1 = p0 + entry.initialVelocity * (time / 3)
    local p2 = p3 - endVelocity * (time / 3)
    entry.samples, entry.pathLength = { { point = p0, length = 0 } }, 0
    for i = 1, 48 do
        local t = i / 48
        local u = 1 - t
        local point = p0 * u^3 + p1 * (3*u*u*t) + p2 * (3*u*t*t) + p3 * t^3
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

shotTracker.hud = Instance.new("TextLabel")
shotTracker.hud.Name = "ShotStatus"
shotTracker.hud.AnchorPoint = Vector2.new(0, 1)
shotTracker.hud.Position = UDim2.new(0, 14, 1, -70)
shotTracker.hud.Size = UDim2.fromOffset(360, 62)
shotTracker.hud.BackgroundColor3 = THEME.Background
shotTracker.hud.BackgroundTransparency = 0.25
shotTracker.hud.BorderSizePixel = 0
shotTracker.hud.TextColor3 = THEME.TextPrimary
shotTracker.hud.TextSize = 13
shotTracker.hud.Font = Enum.Font.GothamMedium
shotTracker.hud.TextWrapped = true
shotTracker.hud.Parent = screenGui
stylePanel(shotTracker.hud)
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
    local point, visible = cam:WorldToViewportPoint(position)
    local adorn = entry.shellAdornee
    local usable = entry.shellHighlight and adorn and adorn.Parent ~= nil
        and adorn.Transparency < 1 and adorn.LocalTransparencyModifier < 1 and point.Z > 0
    if usable then
        local pixels = adorn.Size.Magnitude * cam.ViewportSize.Y
            / (2 * math.tan(math.rad(cam.FieldOfView) / 2) * math.max(point.Z, 0.1))
        usable = pixels >= 3
    end
    if entry.shellHighlight then
        entry.shellHighlight.Enabled = Settings.OwnShellHighlight and usable == true
    end
    entry.shellMarker.Visible = Settings.OwnShellHighlight and not usable and visible and point.Z > 0
    entry.shellMarker.Position = UDim2.fromOffset(point.X, point.Y)
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
            local elapsed = math.max(0.001, now - entry.started)
            local position = state.position
            -- Detect crossing the predicted impact point between observed
            -- samples; don't wait for a pooled projectile's delayed removal.
            local travel = position - entry.lastPosition
            local t = math.clamp((entry.expectedEnd - entry.lastPosition):Dot(travel)
                / math.max(travel:Dot(travel), 1e-8), 0, 1)
            local arrivalDistance = (entry.lastPosition + travel * t - entry.expectedEnd).Magnitude
            local arrived = entry.expectedHit and elapsed >= entry.expectedTime * 0.5
                and arrivalDistance <= 8
            if (position - entry.lastPosition).Magnitude > 0.05 then
                entry.lastPosition, entry.lastMoved = position, now
                entry.status = "AIRBORNE"
            end
            entry.progress = math.max(entry.progress or 0, shotTracker.projectProgress(entry, position))
            entry.elapsed = elapsed
            entry.eta = math.max(0, entry.expectedTime - elapsed)
            if state.destroy or arrived then
                entry.finished = now
                entry.status = state.hitray and "IMPACT OBSERVED" or "FLIGHT ENDED"
                if state.visualOnly then
                    entry.impactError = arrived and arrivalDistance or (position - entry.expectedEnd).Magnitude
                    if entry.impactError <= math.max(12, math.min(50, entry.initialVelocity.Magnitude * 0.05)) then
                        entry.status, entry.progress, entry.eta = "ARRIVAL OBSERVED", 1, 0
                    else
                        entry.status = "FLIGHT ENDED BEFORE TARGET"
                    end
                end
                if state.hitray then
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
            if not entry.finished and elapsed > math.clamp(tonumber(state.Lifetime) or 60, 1, 60) + 2 then
                entry.finished, entry.status = now, "TRACKING ENDED"
                shotTracker.announce(entry, entry.status, "No impact confirmation")
            end
        end
        if state and not entry.finished then
            local show = Settings.ShotProgress
            shotTracker.drawFlight(entry, workspace.CurrentCamera)
            entry.zone.Transparency = show and 0.48 or 1
            entry.targetHud.Enabled = show and Settings.ShowDistance
            blastDistance.scaleLabel(entry.targetHud, entry.targetText, entry.expectedEnd)
            if now >= (entry.nextLabel or 0) then
                entry.nextLabel = now + 0.05
                local meters = (entry.expectedEnd - entry.start).Magnitude / 2.7777778
                local eta = entry.eta and entry.eta > 0.05 and string.format("ETA ~%.1fs", entry.eta) or "ETA unavailable"
                entry.targetText.Text = string.format("%.0f m  ·  %s  ·  %.0f%%", meters, eta, (entry.progress or 0) * 100)
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
    local text = shotTracker.message .. "\n" .. shotTracker.detail
    if latest then
        text = text .. "\n" .. string.format("%s  ·  flight %.1fs  ·  %.0f%%",
            latest.status, latest.elapsed or 0, (latest.progress or 0) * 100)
    end
    shotTracker.hud.Visible = Settings.ShotStatus and (#shotTracker.entries > 0
        or shotTracker.requested ~= nil or now - (shotTracker.messageAt or 0) < 2)
    if shotTracker.hud.Text ~= text then shotTracker.hud.Text = text end
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
    local indirectMode = Settings.AutoLead or Settings.AutoBallistic or artilleryMode
    local minPitch, maxPitch = getTurretPitchLimits(wData and wData.turret)
    local idealLaunchDir, arc, previewDir = getLaunchDirection(startPos, predictedTarget, targetPart, speed,
        gravityY, drag, indirectMode, Settings.AutoBallistic,
        boreDir, minPitch, maxPitch, getClearanceParams(veh))
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

-- The game gunner controller consumes this Vector3Value as a world-space
-- turret target. Only borrow it while we own the gunner seat, and yield if
-- another game system writes a different nonzero target.
local slaveTargetValue, slaveLastValue, slaveLastWrite = nil, nil, 0
local function releaseArtillerySlave()
    if slaveTargetValue and slaveTargetValue.Parent and slaveLastValue
        and (slaveTargetValue.Value - slaveLastValue).Magnitude < 0.01 then
        slaveTargetValue.Value = Vector3.zero
    end
    slaveTargetValue, slaveLastValue, slaveLastWrite = nil, nil, 0
end
local function updateArtillerySlave(wData, startPos, direction, arc)
    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    local seat = hum and hum.SeatPart
    local control = wData and wData.turret and wData.turret:FindFirstChild("Control")
    local shouldSlave = Settings.Freecam and freecamActive and wData and wData.weapon
        and wData.weapon:GetAttribute("ARTY") == true and control and control.Value == seat
        and seat ~= nil and direction ~= nil and (arc == "high" or arc == "low")
    if not shouldSlave then releaseArtillerySlave(); return false end

    local infoObject = wData.turret:FindFirstChild("TurretInfo")
    local infoOk, turretInfo = pcall(require, infoObject)
    if not infoOk or not turretInfo or not turretInfo.FCS then
        -- Legacy guns do not read TargetPos. Avoid direct weld manipulation:
        -- it is not validated against their normal controller or replication.
        releaseArtillerySlave()
        return false
    end

    local ngd = game:GetService("ReplicatedFirst"):FindFirstChild("NewGuiData")
    local gunner = ngd and ngd:FindFirstChild("Gunner")
    local weapons = gunner and gunner:FindFirstChild("Weapons")
    local data = weapons and weapons:FindFirstChild("Data")
    local targetValue = data and data:FindFirstChild("TargetPos")
    if not targetValue or not targetValue:IsA("Vector3Value") then
        releaseArtillerySlave()
        return false
    end
    if slaveTargetValue and slaveTargetValue ~= targetValue then releaseArtillerySlave() end
    if targetValue.Value.Magnitude > 0.01
        and (not slaveLastValue or (targetValue.Value - slaveLastValue).Magnitude > 0.01) then
        releaseArtillerySlave()
        return false
    end
    local virtualTarget = startPos + direction * 4000
    if not slaveLastValue or (virtualTarget - slaveLastValue).Magnitude > 2 then
        if os.clock() - slaveLastWrite >= 0.05 then
            targetValue.Value = virtualTarget
            slaveTargetValue, slaveLastValue, slaveLastWrite = targetValue, virtualTarget, os.clock()
        end
    end
    return slaveTargetValue == targetValue
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
            aimCache.reason = "no active weapon"
            return
        end
        local muzzle = weapon.muzzle
        local startPos = weapon.firePoint and weapon.firePoint.WorldPosition or muzzle.Position
        aimCache.startPos, aimCache.tankVelocity = startPos, muzzle.AssemblyLinearVelocity
        local boreDir = getBoreForwardDirection(weapon)
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
        local slewing = arc == "high" and direction ~= nil
            and aimCache.alignment < math.cos(math.rad(3))
        aimCache.clearance = direction ~= nil and not slewing
        local unsafe = aimCache.alignment < MIN_BARREL_ALIGNMENT
        aimCache.reason = not direction and arc or slewing and
            (aimCache.turretSlaveActive and "turret slewing to target arc" or "aim barrel to target arc")
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
extras.tick = RunService.Heartbeat:Connect(function()
    if not extras.alive or os.clock() < (extras.nextTick or 0) then return end
    extras.nextTick = os.clock() + 0.25
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
            sentAt = os.clock(), predictedTime = visualDiagnostics.flightTime
        } or nil
        if Settings.EnableAutoLead and (Settings.AutoLead or Settings.AutoBallistic) and bulletData
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
            shotTracker.serial = shotTracker.serial + 1
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
    -- An unavailable assist must not disable the normal weapon. Match native
    -- gunner clicks: fire along the bore until the requested arc is ready.
    local aimDirection = Settings.EnableAutoLead and (Settings.AutoLead or Settings.AutoBallistic)
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
        clickTeleport = Settings.FreecamClickTP,
        heldFire = { active = next(heldFire.inputs) ~= nil, busy = heldFire.busy == true },
        autoLead = Settings.AutoLead,
        autoBallistic = Settings.AutoBallistic,
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
            backend = playerEsp and "esp-lib.lua" or "unavailable", error = espStats.error,
            playerEnabled = Settings.PlayerESP, tankEnabled = Settings.EnemyTankESP,
            boxesEnabled = Settings.ESPBoxes },
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
    if vibeUi then pcall(function() vibeUi:Unload() end) end
    if screenGui then screenGui:Destroy() end
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
