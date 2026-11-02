--!strict
-- NexusDataStore v8.4.1 neon-horizon restart UI: GIF-inspired background and frame-synced motion.
-- Install this LocalScript in ReplicatedFirst and set STORE_NAME to the DataStore Name.
local STORE_NAME = "PlayerData"
local REDUCED_MOTION = false -- Set true to disable continuous animations and shorten transitions.
local BACKGROUND_IMAGE_ID = "" -- Optional exact PNG: upload neon_nexus_data_horizon.png to Roblox, then use "rbxassetid://<id>".
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local arriving = TeleportService:GetArrivingTeleportGui()
local guiName = "NexusRestartGui_" .. STORE_NAME
local readyAttribute = "NexusDataStoreProfileReady_" .. STORE_NAME
local errorAttribute = "NexusDataStoreProfileError_" .. STORE_NAME
local accent = Color3.fromRGB(86, 191, 255)
local successAccent = Color3.fromRGB(101, 236, 186)
local dangerAccent = Color3.fromRGB(255, 129, 151)
local warningAccent = Color3.fromRGB(255, 200, 109)
local violetAccent = Color3.fromRGB(172, 133, 255)
local normal = Color3.fromRGB(230, 242, 255)
local muted = Color3.fromRGB(157, 179, 207)
local panelColor = Color3.fromRGB(17, 31, 55)
local stateTextFade = TweenInfo.new(0.48, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local accentEase = TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local infoEase = TweenInfo.new(0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local fadeEase = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local activeGui: ScreenGui? = nil
local stage: CanvasGroup? = nil
local banner: CanvasGroup? = nil
local panel: Frame? = nil
local bannerText: TextLabel? = nil
local bannerTimer: TextLabel? = nil
local title: TextLabel? = nil
local statusText: TextLabel? = nil
local description: TextLabel? = nil
local phaseLabel: TextLabel? = nil
local progressTrack: Frame? = nil
local phaseFill: Frame? = nil
local accentLine: Frame? = nil
local statusOrb: Frame? = nil
local phaseSteps: {TextLabel} = {}
local statusTweens: {Tween} = {}
local activePresentation = "hidden"
local currentStatus = "idle"
local restartAt = 0
local arrivalMode = false
local lastMessage = ""
local transitionToken = 0
local fadeTween: Tween? = nil
local slideTween: Tween? = nil
local bannerTween: Tween? = nil
local viewportConnection: RBXScriptConnection? = nil
local renderConnection: RBXScriptConnection? = nil
local arrivalReadyConnection: RBXScriptConnection? = nil
local arrivalErrorConnection: RBXScriptConnection? = nil
local renderStep: ((number) -> ())? = nil
local ambientGlow: Frame? = nil
local secondaryGlow: Frame? = nil
local haloGradientRef: UIGradient? = nil
local progressShine: UIGradient? = nil
local bannerPulse: Frame? = nil
local animationClock = 0
local countdownAccumulator = 0
local lastCountdownSeconds = -1
local averageFrameTime = 1 / 60
local slowFrameDuration = 0
local recoveryDuration = 0
local lightweightEffects = false
local diagnosticsAccumulator = 0
local horizonRays: {{Line: Frame, StartX: number}} = {}
local horizonScan: Frame? = nil
local horizonRing: UIGradient? = nil
local horizonArc: UIGradient? = nil

local function corner(parent: Instance, radius: number)
    local item = Instance.new("UICorner")
    item.CornerRadius = UDim.new(radius, 0)
    item.Parent = parent
end

local function stroke(parent: Instance, color: Color3, opacity: number)
    local item = Instance.new("UIStroke")
    item.Thickness = 1
    item.Color = color
    item.Transparency = opacity
    item.Parent = parent
end

local function textLabel(parent: Instance, name: string, value: string, font: Enum.Font, color: Color3, pos: UDim2, size: UDim2, alignment: Enum.TextXAlignment?): TextLabel
    local item = Instance.new("TextLabel")
    item.Name = name
    item.Position = pos
    item.Size = size
    item.BackgroundTransparency = 1
    item.Text = value
    item.Font = font
    item.TextColor3 = color
    item.TextScaled = true
    item.TextWrapped = true
    item.TextXAlignment = alignment or Enum.TextXAlignment.Center
    item.TextYAlignment = Enum.TextYAlignment.Center
    item.Parent = parent
    return item
end

local function cancelStatusTweens()
    for _, tween in ipairs(statusTweens) do tween:Cancel() end
    table.clear(statusTweens)
end

local function animateState(object: Instance, properties: {[string]: any}, info: TweenInfo?)
    if REDUCED_MOTION then
        for key, value in pairs(properties) do (object :: any)[key] = value end
        return
    end
    local tween = TweenService:Create(object, info or accentEase, properties)
    table.insert(statusTweens, tween)
    tween:Play()
end

local function phaseColor(status: string): Color3
    if status == "ready" or status == "arriving" then return successAccent end
    if status == "retrying" or status == "teleport-retrying" then return warningAccent end
    if status == "error" then return dangerAccent end
    return accent
end

-- Build the cyan/violet digital horizon using Roblox UI objects. An uploaded
-- Roblox image asset can replace the generated scenery for an exact art match.
-- All positions/sizes remain scale-based; the perspective rays reflow on resize.
local function horizonFrame(parent: Instance, name: string, pos: UDim2, size: UDim2, color: Color3, transparency: number): Frame
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.Position = pos
    frame.Size = size
    frame.BackgroundColor3 = color
    frame.BackgroundTransparency = transparency
    frame.BorderSizePixel = 0
    frame.Parent = parent
    return frame
end

local function buildHorizon(backdrop: Frame)
    backdrop.ClipsDescendants = true
    if BACKGROUND_IMAGE_ID ~= "" then
        local image = Instance.new("ImageLabel")
        image.Name = "NeonHorizonImage"
        image.Position = UDim2.fromScale(0, 0)
        image.Size = UDim2.fromScale(1, 1)
        image.BackgroundTransparency = 1
        image.BorderSizePixel = 0
        image.ScaleType = Enum.ScaleType.Crop
        image.Image = BACKGROUND_IMAGE_ID
        image.Parent = backdrop
    else
        local floor = horizonFrame(backdrop, "PerspectiveGridFloor", UDim2.fromScale(0, 0.645), UDim2.fromScale(1, 0.355), Color3.fromRGB(7, 22, 45), 0.13)
        local floorGradient = Instance.new("UIGradient")
        floorGradient.Rotation = 90
        floorGradient.Color = ColorSequence.new(Color3.fromRGB(9, 48, 89), Color3.fromRGB(4, 15, 35))
        floorGradient.Parent = floor
        for index = 1, 10 do
            local distance = (index / 10) ^ 1.45
            local y = 0.645 + distance * 0.355
            horizonFrame(backdrop, "GridY" .. index, UDim2.fromScale(0, y), UDim2.fromScale(1, 0.0014),
                Color3.fromRGB(32, 142, 245), 0.69 + distance * 0.12)
        end
        for index = 0, 12 do
            local start = index / 12
            local line = horizonFrame(backdrop, "GridX" .. index, UDim2.fromScale(0.5, 0.82), UDim2.fromScale(0.45, 0.0015),
                Color3.fromRGB(41, 160, 255), 0.68)
            line.AnchorPoint = Vector2.new(0.5, 0.5)
            table.insert(horizonRays, {Line = line, StartX = start})
        end
        local horizonGlow = horizonFrame(backdrop, "HorizonGlow", UDim2.fromScale(0, 0.627), UDim2.fromScale(1, 0.042),
            Color3.fromRGB(21, 105, 199), 0.84)
        local glowGradient = Instance.new("UIGradient")
        glowGradient.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.16, 0.2),
            NumberSequenceKeypoint.new(0.84, 0.2),
            NumberSequenceKeypoint.new(1, 1),
        })
        glowGradient.Parent = horizonGlow
        horizonFrame(backdrop, "HorizonLine", UDim2.fromScale(0, 0.645), UDim2.fromScale(1, 0.002),
            Color3.fromRGB(56, 183, 255), 0.26)
        -- The far-off data towers mirror the silhouettes in the preview background.
        local towers = {
            {0.035, 0.15, 0.040}, {0.105, 0.27, 0.053}, {0.207, 0.11, 0.038},
            {0.786, 0.17, 0.036}, {0.865, 0.27, 0.058}, {0.948, 0.12, 0.035},
        }
        for index, spec in ipairs(towers) do
            local x, height, width = spec[1], spec[2], spec[3]
            local tower = horizonFrame(backdrop, "DataTower" .. index, UDim2.fromScale(x, 0.645 - height), UDim2.fromScale(width, height),
                Color3.fromRGB(16, 48, 91), 0.49)
            tower.ClipsDescendants = true
            local towerGradient = Instance.new("UIGradient")
            towerGradient.Rotation = 90
            towerGradient.Color = ColorSequence.new(Color3.fromRGB(22, 69, 130), Color3.fromRGB(8, 28, 59))
            towerGradient.Parent = tower
            horizonFrame(tower, "Edge", UDim2.fromScale(0, 0), UDim2.fromScale(0.027, 1), Color3.fromRGB(34, 172, 255), 0.15)
            for bar = 1, 3 do
                horizonFrame(tower, "Light" .. bar, UDim2.fromScale(0.18, 0.24 * bar), UDim2.fromScale(0.58, 0.009),
                    Color3.fromRGB(34, 173, 255), 0.2 + bar * 0.1)
            end
        end
        -- Star/data points: deterministic positions, zero per-frame creation.
        for index = 1, 27 do
            local x = (index * 0.61803398875) % 1
            local y = (index * 0.41421356237) % 0.56
            local dot = horizonFrame(backdrop, "DataStar" .. index, UDim2.fromScale(x, y), UDim2.fromScale(0.0016, 0.0029),
                Color3.fromRGB(71, 191, 255), 0.18 + (index % 4) * 0.15)
            corner(dot, 1)
        end
        local ring = horizonFrame(backdrop, "HorizonHUDRing", UDim2.fromScale(0.72, -0.12), UDim2.fromScale(0.47, 0.7),
            Color3.fromRGB(25, 73, 137), 1)
        corner(ring, 1)
        local ringStroke = Instance.new("UIStroke")
        ringStroke.Color = Color3.fromRGB(51, 166, 255)
        ringStroke.Thickness = 1.5
        ringStroke.Transparency = 0.69
        ringStroke.Parent = ring
        local ringGradient = Instance.new("UIGradient")
        ringGradient.Color = ColorSequence.new(Color3.fromRGB(31, 105, 221), Color3.fromRGB(74, 203, 255))
        ringGradient.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.27, 0.3),
            NumberSequenceKeypoint.new(0.65, 0.7),
            NumberSequenceKeypoint.new(1, 1),
        })
        ringGradient.Parent = ringStroke
        horizonRing = ringGradient
        local arc = horizonFrame(backdrop, "FloorLightArc", UDim2.fromScale(0.05, 0.69), UDim2.fromScale(0.9, 0.52),
            Color3.fromRGB(41, 171, 255), 1)
        corner(arc, 1)
        local arcStroke = Instance.new("UIStroke")
        arcStroke.Thickness = 2
        arcStroke.Color = Color3.fromRGB(61, 184, 255)
        arcStroke.Transparency = 0.58
        arcStroke.Parent = arc
        local arcGradient = Instance.new("UIGradient")
        arcGradient.Color = ColorSequence.new(Color3.fromRGB(35, 116, 244), Color3.fromRGB(180, 91, 255))
        arcGradient.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.9),
            NumberSequenceKeypoint.new(0.35, 0.15),
            NumberSequenceKeypoint.new(0.72, 0.45),
            NumberSequenceKeypoint.new(1, 0.95),
        })
        arcGradient.Parent = arcStroke
        horizonArc = arcGradient
    end
    -- The subtle moving light sweep also runs over a supplied Roblox image asset.
    horizonScan = horizonFrame(backdrop, "HorizonScan", UDim2.fromScale(-0.15, 0.643), UDim2.fromScale(0.25, 0.003),
        Color3.fromRGB(93, 212, 255), 0.42)
    local scanGradient = Instance.new("UIGradient")
    scanGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.04), NumberSequenceKeypoint.new(1, 1),
    })
    scanGradient.Parent = horizonScan
end

local function makeInterface(): ScreenGui
    local screen = Instance.new("ScreenGui")
    screen.Name = guiName
    screen:SetAttribute("StoreName", STORE_NAME)
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 1000
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local overlay = Instance.new("CanvasGroup")
    overlay.Name = "Stage"
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.BackgroundTransparency = 1
    overlay.GroupTransparency = 1
    overlay.Visible = false
    overlay.Parent = screen
    stage = overlay

    local backdrop = Instance.new("Frame")
    backdrop.Name = "Backdrop"
    backdrop.Size = UDim2.fromScale(1, 1)
    backdrop.BackgroundColor3 = Color3.fromRGB(8, 13, 26)
    backdrop.BackgroundTransparency = 0.07
    backdrop.BorderSizePixel = 0
    backdrop.Parent = overlay
    local backgroundGradient = Instance.new("UIGradient")
    backgroundGradient.Rotation = 35
    backgroundGradient.Color = ColorSequence.new(Color3.fromRGB(8, 13, 26), Color3.fromRGB(20, 40, 69))
    backgroundGradient.Parent = backdrop

    buildHorizon(backdrop)

    local glow = Instance.new("Frame")
    glow.Name = "AmbientGlow"
    glow.AnchorPoint = Vector2.new(0.5, 0.5)
    glow.Position = UDim2.fromScale(0.82, 0.24)
    glow.Size = UDim2.fromScale(0.5, 0.52)
    glow.BackgroundColor3 = Color3.fromRGB(26, 94, 162)
    glow.BackgroundTransparency = 0.83
    glow.BorderSizePixel = 0
    glow.Parent = backdrop
    corner(glow, 1)
    ambientGlow = glow

    local secondGlow = Instance.new("Frame")
    secondGlow.Name = "SecondaryGlow"
    secondGlow.AnchorPoint = Vector2.new(0.5, 0.5)
    secondGlow.Position = UDim2.fromScale(0.16, 0.78)
    secondGlow.Size = UDim2.fromScale(0.31, 0.43)
    secondGlow.BackgroundColor3 = Color3.fromRGB(100, 54, 173)
    secondGlow.BackgroundTransparency = 0.91
    secondGlow.BorderSizePixel = 0
    secondGlow.Parent = backdrop
    corner(secondGlow, 1)
    secondaryGlow = secondGlow

    local main = Instance.new("Frame")
    main.Name = "Panel"
    main.AnchorPoint = Vector2.new(0.5, 0.5)
    main.Position = UDim2.fromScale(0.5, 0.55)
    main.Size = UDim2.fromScale(0.86, 0.47)
    main.BackgroundColor3 = panelColor
    main.BackgroundTransparency = 0.035
    main.BorderSizePixel = 0
    main.Parent = overlay
    corner(main, 0.055)
    stroke(main, Color3.fromRGB(79, 119, 163), 0.35)
    panel = main
    local mainGradient = Instance.new("UIGradient")
    mainGradient.Color = ColorSequence.new(Color3.fromRGB(20, 37, 62), Color3.fromRGB(13, 24, 44))
    mainGradient.Rotation = 105
    mainGradient.Parent = main

    local highlight = Instance.new("Frame")
    highlight.Name = "AccentLine"
    highlight.Size = UDim2.fromScale(0.25, 0.012)
    highlight.Position = UDim2.fromScale(0.375, 0)
    highlight.BackgroundColor3 = accent
    highlight.BorderSizePixel = 0
    highlight.Parent = main
    corner(highlight, 1)
    accentLine = highlight


    -- Circular animated data-core gives each state its own visual identity.
    local core = Instance.new("Frame")
    core.Name = "DataCore"
    core.AnchorPoint = Vector2.new(0.5, 0.5)
    core.Position = UDim2.fromScale(0.19, 0.355)
    core.Size = UDim2.fromScale(0.16, 0.24)
    core.BackgroundColor3 = Color3.fromRGB(25, 55, 87)
    core.BackgroundTransparency = 0.28
    core.BorderSizePixel = 0
    core.Parent = main
    local coreRatio = Instance.new("UIAspectRatioConstraint")
    coreRatio.AspectRatio = 1
    coreRatio.Parent = core
    corner(core, 1)
    stroke(core, Color3.fromRGB(92, 188, 247), 0.18)
    local coreHalo = Instance.new("Frame")
    coreHalo.Name = "Halo"
    coreHalo.AnchorPoint = Vector2.new(0.5, 0.5)
    coreHalo.Position = UDim2.fromScale(0.5, 0.5)
    coreHalo.Size = UDim2.fromScale(0.85, 0.85)
    coreHalo.BackgroundTransparency = 1
    coreHalo.Parent = core
    corner(coreHalo, 1)
    local haloStroke = Instance.new("UIStroke")
    haloStroke.Thickness = 2
    haloStroke.Color = accent
    haloStroke.Transparency = 0.12
    haloStroke.Parent = coreHalo
    local haloGradient = Instance.new("UIGradient")
    haloGradient.Color = ColorSequence.new(accent, violetAccent)
    haloGradient.Rotation = 0
    haloGradient.Parent = haloStroke
    haloGradientRef = haloGradient
    local coreIcon = textLabel(core, "Icon", "◆", Enum.Font.GothamBold, normal, UDim2.fromScale(0.2, 0.18), UDim2.fromScale(0.6, 0.64))
    coreIcon.TextTransparency = 0.05
    statusOrb = core


    local tag = textLabel(main, "Eyebrow", "NEXUS  /  SERVER MIGRATION", Enum.Font.GothamBold, accent, UDim2.fromScale(0.12, 0.10), UDim2.fromScale(0.76, 0.085))
    tag.TextTransparency = 0.03

    title = textLabel(main, "Title", "Server update scheduled", Enum.Font.GothamBold, normal, UDim2.fromScale(0.32, 0.245), UDim2.fromScale(0.58, 0.18), Enum.TextXAlignment.Left)
    statusText = textLabel(main, "Status", "Preparing to migrate...", Enum.Font.GothamMedium, accent, UDim2.fromScale(0.31, 0.445), UDim2.fromScale(0.59, 0.095), Enum.TextXAlignment.Left)
    description = textLabel(main, "Description", "Your progress stays protected while the server updates.", Enum.Font.Gotham, muted, UDim2.fromScale(0.12, 0.565), UDim2.fromScale(0.76, 0.123))

    -- Three-stage timeline shows only server-confirmed milestones, never a made-up percentage.
    local stepNames = {"01   SAVE", "02   TRANSFER", "03   RESTORE"}
    table.clear(phaseSteps)
    for index, label in ipairs(stepNames) do
        local item = textLabel(main, "Step" .. index, label, Enum.Font.GothamBold, muted,
            UDim2.fromScale(0.105 + (index - 1) * 0.275, 0.735),
            UDim2.fromScale(0.24, 0.085))
        item.BackgroundTransparency = 0.6
        item.BackgroundColor3 = Color3.fromRGB(38, 67, 103)
        corner(item, 0.25)
        table.insert(phaseSteps, item)
    end

    phaseLabel = textLabel(main, "Phase", "CHECKING PROFILE", Enum.Font.GothamBold, muted, UDim2.fromScale(0.11, 0.845), UDim2.fromScale(0.78, 0.052), Enum.TextXAlignment.Left)

    local bar = Instance.new("Frame")
    bar.Name = "ProgressTrack"
    bar.Size = UDim2.fromScale(0.78, 0.023)
    bar.Position = UDim2.fromScale(0.11, 0.934)
    bar.BackgroundColor3 = Color3.fromRGB(43, 68, 101)
    bar.BorderSizePixel = 0
    bar.ClipsDescendants = true
    bar.Parent = main
    corner(bar, 1)
    progressTrack = bar

    local fill = Instance.new("Frame")
    fill.Name = "PhaseFill"
    fill.Size = UDim2.fromScale(0.22, 1)
    fill.Position = UDim2.fromScale(0, 0)
    fill.BorderSizePixel = 0
    fill.BackgroundColor3 = accent
    fill.Parent = bar
    corner(fill, 1)
    phaseFill = fill

    local shine = Instance.new("UIGradient")
    shine.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, accent),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(225, 245, 255)),
        ColorSequenceKeypoint.new(1, violetAccent),
    })
    shine.Parent = fill
    progressShine = shine

    local notice = Instance.new("CanvasGroup")
    notice.Name = "Banner"
    notice.AnchorPoint = Vector2.new(0.5, 0)
    notice.Position = UDim2.fromScale(0.5, -0.11)
    notice.Size = UDim2.fromScale(0.82, 0.085)
    notice.BackgroundColor3 = Color3.fromRGB(16, 33, 56)
    notice.GroupTransparency = 1
    notice.Visible = false
    notice.Parent = screen
    corner(notice, 0.25)
    stroke(notice, Color3.fromRGB(76, 142, 189), 0.45)
    banner = notice

    local orb = Instance.new("Frame")
    orb.Name = "Pulse"
    orb.AnchorPoint = Vector2.new(0.5, 0.5)
    orb.Position = UDim2.fromScale(0.075, 0.5)
    orb.Size = UDim2.fromScale(0.035, 0.34)
    orb.BorderSizePixel = 0
    orb.BackgroundColor3 = accent
    orb.BackgroundTransparency = 0.05
    orb.Parent = notice
    corner(orb, 1)
    bannerPulse = orb

    bannerText = textLabel(notice, "Message", "SERVER UPDATE SCHEDULED", Enum.Font.GothamBold, normal, UDim2.fromScale(0.13, 0.12), UDim2.fromScale(0.59, 0.76), Enum.TextXAlignment.Left)
    bannerTimer = textLabel(notice, "Timer", "01:00", Enum.Font.GothamBold, accent, UDim2.fromScale(0.76, 0.12), UDim2.fromScale(0.18, 0.76), Enum.TextXAlignment.Right)
    return screen
end

local function stopTransitions()
    if fadeTween then fadeTween:Cancel(); fadeTween = nil end
    if slideTween then slideTween:Cancel(); slideTween = nil end
    if bannerTween then bannerTween:Cancel(); bannerTween = nil end
end

local function applyResponsiveLayout()
    if not stage or not banner or not panel then return end
    local view = stage.AbsoluteSize
    if view.X <= 0 or view.Y <= 0 then return end
    local ratio = view.X / view.Y
    if ratio < 0.85 then
        panel.Size = UDim2.fromScale(0.88, 0.43)
        banner.Size = UDim2.fromScale(0.9, 0.073)
    elseif ratio < 1.45 then
        panel.Size = UDim2.fromScale(0.76, 0.5)
        banner.Size = UDim2.fromScale(0.72, 0.088)
    elseif view.Y < 560 then
        panel.Size = UDim2.fromScale(0.59, 0.71)
        banner.Size = UDim2.fromScale(0.56, 0.115)
    else
        panel.Size = UDim2.fromScale(0.58, 0.5)
        banner.Size = UDim2.fromScale(0.48, 0.085)
    end
end

local function ensureInterface()
    if activeGui then return end
    local screen = makeInterface()
    activeGui = screen
    screen.Parent = playerGui
    applyResponsiveLayout()
    if stage then
        viewportConnection = stage:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyResponsiveLayout)
    end
    -- Connected only when UI exists; Roblox calls this once per rendered frame.
    if not renderConnection and renderStep then renderConnection = RunService.PreRender:Connect(renderStep) end
end

local function setPresentation(kind: string, immediate: boolean?)
    ensureInterface()
    if not stage or not banner or not panel or kind == activePresentation then return end
    transitionToken += 1
    local token = transitionToken
    stopTransitions()
    activePresentation = kind
    local showStage = kind == "full"
    local showBanner = kind == "banner"
    if REDUCED_MOTION then
        stage.Visible = showStage
        stage.GroupTransparency = showStage and 0 or 1
        panel.Position = UDim2.fromScale(0.5, 0.5)
        banner.Visible = showBanner
        banner.GroupTransparency = showBanner and 0 or 1
        banner.Position = UDim2.fromScale(0.5, showBanner and 0.06 or -0.11)
        return
    end
    if showStage then
        stage.Visible = true
        if not immediate then
            stage.GroupTransparency = 1
            panel.Position = UDim2.fromScale(0.5, 0.55)
        end
        fadeTween = TweenService:Create(stage, fadeEase, {GroupTransparency = 0})
        slideTween = TweenService:Create(panel, infoEase, {Position = UDim2.fromScale(0.5, 0.5)})
        fadeTween:Play()
        slideTween:Play()
    elseif stage.Visible then
        local oldStage = stage
        local out = TweenService:Create(oldStage, fadeEase, {GroupTransparency = 1})
        fadeTween = out
        out.Completed:Connect(function()
            if transitionToken == token and oldStage.Parent then oldStage.Visible = false end
        end)
        out:Play()
    end
    if showBanner then
        banner.Visible = true
        if not immediate then
            banner.GroupTransparency = 1
            banner.Position = UDim2.fromScale(0.5, -0.11)
        end
        bannerTween = TweenService:Create(banner, fadeEase, {GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.06)})
        bannerTween:Play()
    elseif banner.Visible then
        local oldBanner = banner
        local out = TweenService:Create(oldBanner, fadeEase, {GroupTransparency = 1, Position = UDim2.fromScale(0.5, -0.11)})
        bannerTween = out
        out.Completed:Connect(function()
            if transitionToken == token and oldBanner.Parent then oldBanner.Visible = false end
        end)
        out:Play()
    end
end

local function clearInterface()
    transitionToken += 1
    if viewportConnection then viewportConnection:Disconnect(); viewportConnection = nil end
    stopTransitions()
    cancelStatusTweens()
    if renderConnection then renderConnection:Disconnect(); renderConnection = nil end
    if arrivalReadyConnection then arrivalReadyConnection:Disconnect(); arrivalReadyConnection = nil end
    if arrivalErrorConnection then arrivalErrorConnection:Disconnect(); arrivalErrorConnection = nil end
    animationClock = 0
    countdownAccumulator = 0
    lastCountdownSeconds = -1
    averageFrameTime = 1 / 60
    slowFrameDuration = 0
    recoveryDuration = 0
    diagnosticsAccumulator = 0
    lightweightEffects = false
    if activeGui then activeGui:Destroy() end
    activeGui, stage, banner, panel = nil, nil, nil, nil
    bannerText, bannerTimer, title, statusText, description = nil, nil, nil, nil, nil
    phaseLabel, progressTrack, phaseFill, accentLine, statusOrb = nil, nil, nil, nil, nil
    ambientGlow, secondaryGlow, haloGradientRef, progressShine, bannerPulse = nil, nil, nil, nil, nil
    table.clear(phaseSteps)
    currentStatus, activePresentation, restartAt, lastMessage = "idle", "hidden", 0, ""
end

local function secondsRemaining()
    return math.max(0, math.ceil(restartAt - DateTime.now().UnixTimestamp))
end

local function countdown(seconds: number): string
    local minutes = math.floor(seconds / 60)
    local remainder = seconds % 60
    return string.format("%02d:%02d", minutes, remainder)
end

-- Frame-linked motion: uses actual rendering delta, NOT a fixed 30/60/120Hz timer.
-- Roblox determines the effective FPS. This adapts to whatever frames the client renders.
renderStep = function(deltaTime: number)
    if player.Parent ~= Players then clearInterface(); return end
    if not activeGui or currentStatus == "idle" then return end
    if deltaTime <= 0 then return end

    local dt = math.min(deltaTime, 0.05)
    countdownAccumulator += dt
    if currentStatus == "scheduled" and restartAt > 0 and countdownAccumulator >= 0.15 then
        countdownAccumulator = 0
        local seconds = secondsRemaining()
        if seconds ~= lastCountdownSeconds then
            lastCountdownSeconds = seconds
            if statusText then statusText.Text = seconds == 0 and "Moving to new server soon" or "Server restart in " .. countdown(seconds) end
            if bannerTimer then bannerTimer.Text = countdown(seconds) end
            if seconds <= 30 and activePresentation == "banner" then setPresentation("full") end
        end
    end

    -- Low-pass frame-time measurement with time-based smoothing and hysteresis.
    -- These are observed rendered frames, not a guessed hardware refresh rate.
    if deltaTime < 0.2 then
        local alpha = 1 - math.exp(-dt * 2.4)
        averageFrameTime += (deltaTime - averageFrameTime) * alpha
        local observedFPS = 1 / math.max(averageFrameTime, 1 / 300)
        if observedFPS < 38 then
            slowFrameDuration += dt
            recoveryDuration = 0
        elseif observedFPS > 52 then
            recoveryDuration += dt
            slowFrameDuration = 0
        else
            slowFrameDuration = 0
            recoveryDuration = 0
        end
        if slowFrameDuration >= 1.4 then lightweightEffects = true end
        if recoveryDuration >= 2.5 then lightweightEffects = false end
        diagnosticsAccumulator += dt
        if diagnosticsAccumulator >= 2 and activeGui then
            diagnosticsAccumulator = 0
            activeGui:SetAttribute("ObservedRenderFPS", math.floor(observedFPS + 0.5))
            activeGui:SetAttribute("MotionQuality", REDUCED_MOTION and "reduced" or (lightweightEffects and "light" or "full"))
        end
    end

    if REDUCED_MOTION then return end

    -- Each visual phase advances in seconds, independent of rendered FPS.
    -- Cap a single step after long stalls to avoid visually snapping across the screen.
    animationClock = (animationClock + dt) % 10000
    local t = animationClock
    if activePresentation == "banner" and banner and banner.Visible then
        if bannerPulse then bannerPulse.BackgroundTransparency = 0.13 + 0.53 * (0.5 + 0.5 * math.sin(t * 4.1)) end
    elseif activePresentation == "full" and stage and stage.Visible and currentStatus ~= "error" then
        if haloGradientRef then haloGradientRef.Rotation = (t * 48) % 360 end
        if phaseFill then
            local sweep = 0.5 + 0.5 * math.sin(t * 2.9 - math.pi / 2)
            phaseFill.Position = UDim2.fromScale(sweep * 0.78, 0)
        end
        if statusOrb then statusOrb.BackgroundTransparency = 0.33 + 0.16 * (0.5 + 0.5 * math.sin(t * 2.1)) end
        if not lightweightEffects then
            if accentLine then accentLine.Position = UDim2.fromScale(0.375 + 0.245 * (0.5 + 0.5 * math.sin(t * 0.8)), 0) end
            if ambientGlow then
                ambientGlow.Position = UDim2.fromScale(0.76 + 0.06 * math.sin(t * 0.55), 0.28 + 0.05 * math.cos(t * 0.55))
                ambientGlow.BackgroundTransparency = 0.88 + 0.035 * math.sin(t * 0.7)
            end
            if secondaryGlow then
                secondaryGlow.Position = UDim2.fromScale(0.21 + 0.055 * math.sin(t * 0.43), 0.73 + 0.05 * math.cos(t * 0.43))
            end
            if progressShine then progressShine.Offset = Vector2.new(0.35 * math.sin(t * 1.5), 0) end
        end
    end
end

local function update(status: string, target: number, message: string)
    if status == "idle" then return end
    local previousStatus = currentStatus
    currentStatus = status
    restartAt = target
    lastMessage = message
    if status == "arriving" then arrivalMode = true end
    local seconds = secondsRemaining()
    local presentation = status == "scheduled" and seconds > 30 and not arrivalMode and "banner" or "full"
    setPresentation(presentation)
    if not title or not statusText or not description or not phaseLabel then return end
    if status ~= previousStatus then
        cancelStatusTweens()
        for _, label in ipairs({title, statusText, description, phaseLabel}) do
            label.TextTransparency = REDUCED_MOTION and 0 or 0.9
            animateState(label, {TextTransparency = 0}, stateTextFade)
        end
        local shade = phaseColor(status)
        animateState(statusText, {TextColor3 = shade})
        if accentLine then animateState(accentLine, {BackgroundColor3 = shade}) end
        if statusOrb then animateState(statusOrb, {BackgroundColor3 = status == "error" and Color3.fromRGB(107, 38, 57) or Color3.fromRGB(25, 55, 87)}) end
        if phaseFill then animateState(phaseFill, {BackgroundColor3 = shade}) end

        -- Explicit stage transitions: save success is not proof of teleport or load success.
        local currentStep = (status == "ready" or status == "moving" or status == "teleport-retrying") and 2 or (status == "arriving" or status == "error") and 3 or 1
        for index, step in ipairs(phaseSteps) do
            local completed = index < currentStep
            local active = index == currentStep
            local tone = completed and successAccent or (active and shade or muted)
            animateState(step, {TextColor3 = tone, BackgroundTransparency = active and 0.18 or (completed and 0.4 or 0.74)})
        end

        if status == "error" and phaseFill then phaseFill.Position = UDim2.fromScale(0.39, 0) end
    end
    if status == "scheduled" then
        title.Text = "New update incoming"
        statusText.Text = "Server restart in " .. countdown(seconds)
        description.Text = message ~= "" and message or "Your progress is protected during the update."
        phaseLabel.Text = "PREPARING SERVER UPDATE"
        if bannerText then bannerText.Text = "SERVER UPDATE INCOMING" end
        if bannerTimer then bannerTimer.Text = countdown(seconds) end
    elseif status == "saving" then
        title.Text = "Saving your progress"
        statusText.Text = "Securing your latest changes..."
        description.Text = "Please stay connected while we prepare your profile for the new server."
        phaseLabel.Text = "PERSISTING PROFILE DATA"
    elseif status == "retrying" then
        title.Text = "Keeping progress safe"
        statusText.Text = "Retrying a save request..."
        description.Text = "The save service is busy. Your session remains protected while it retries."
        phaseLabel.Text = "RETRYING SECURE SAVE"
    elseif status == "ready" then
        title.Text = "Your progress is saved"
        statusText.Text = "Moving to updated server"
        description.Text = "The server is ready for Roblox to complete the restart."
        phaseLabel.Text = "AWAITING SERVER MIGRATION"
    elseif status == "moving" then
        title.Text = "Joining the updated server"
        statusText.Text = "Teleporting your party..."
        description.Text = "Saved player profiles are being transferred to a fresh server. Your progress stays in DataStore."
        phaseLabel.Text = "TRANSFERRING TO UPDATED SERVER"
    elseif status == "teleport-retrying" then
        title.Text = "Reconnecting players"
        statusText.Text = "Retrying the server transfer..."
        description.Text = "Teleport failed to start for one or more players. Saving is complete; retrying the connection."
        phaseLabel.Text = "RETRYING SERVER TRANSFER"
    elseif status == "arriving" then
        title.Text = "Welcome back"
        statusText.Text = "Acquiring your profile..."
        description.Text = "Checking your session lock and loading saved progress securely."
        phaseLabel.Text = "SYNCING PLAYER DATA"
    elseif status == "error" then
        title.Text = "Unable to load profile"
        statusText.Text = "Please reconnect"
        description.Text = "The data service or previous session lock is unavailable. Your progress was not overwritten."
        phaseLabel.Text = "PROFILE LOAD NOT COMPLETED"
    end
end

-- Rebuild arriving UI so the current scale-based layout also replaces legacy v7/v8 teleport GUIs.
if arriving and arriving:IsA("ScreenGui") and (arriving.Name == guiName or (arriving.Name == "NexusRestartGui" and (arriving:GetAttribute("StoreName") == nil or arriving:GetAttribute("StoreName") == STORE_NAME))) then
    ReplicatedFirst:RemoveDefaultLoadingScreen()
    arriving:Destroy()
    update("arriving", 0, "")
    local function inspectArrivingProfile()
        if not arrivalMode then return end
        if player:GetAttribute(readyAttribute) == true then
            arrivalMode = false
            clearInterface()
            return
        end
        if player:GetAttribute(errorAttribute) ~= nil and currentStatus ~= "error" then update("error", 0, "") end
    end
    arrivalReadyConnection = player:GetAttributeChangedSignal(readyAttribute):Connect(inspectArrivingProfile)
    arrivalErrorConnection = player:GetAttributeChangedSignal(errorAttribute):Connect(inspectArrivingProfile)
    inspectArrivingProfile()
end

task.spawn(function()
    local remote = ReplicatedStorage:WaitForChild("NexusDataStoreRestart_" .. STORE_NAME, 30)
    if not remote or not remote:IsA("RemoteEvent") then return end
    local function receive(status: any, timestamp: any, message: any)
        if typeof(status) ~= "string" or status == "idle" or arrivalMode then return end
        update(status, typeof(timestamp) == "number" and timestamp or 0, typeof(message) == "string" and message or "")
        if activeGui then
            local ok, err = pcall(TeleportService.SetTeleportGui, TeleportService, activeGui)
            if not ok then warn("[NexusDataStore UI] Could not prepare teleport GUI:", err) end
        end
    end
    remote.OnClientEvent:Connect(receive)
    receive(remote:GetAttribute("Status"), remote:GetAttribute("RestartAt"), remote:GetAttribute("Message"))
end)


