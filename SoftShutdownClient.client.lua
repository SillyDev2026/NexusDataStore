--!strict
-- NexusDataStore v8.2 cinematic restart UI: responsive scale-only layout, stage-aware motion.
-- Install this LocalScript in ReplicatedFirst and set STORE_NAME to the DataStore Name.
local STORE_NAME = "PlayerData"
local REDUCED_MOTION = false -- Set true to disable continuous animations and shorten transitions.
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

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
local moveEase = TweenInfo.new(1.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

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
local stageTweens: {Tween} = {}
local bannerTweens: {Tween} = {}

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

local function loopTween(object: Instance, config: TweenInfo, properties: {[string]: any}, bucket: {Tween})
    if REDUCED_MOTION then return end
    local tween = TweenService:Create(object, config, properties)
    table.insert(bucket, tween)
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
    if status == "retrying" then return warningAccent end
    if status == "error" then return dangerAccent end
    return accent
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

    -- Decorative grid: lightweight, no rendering loop or texture download.
    for index = 1, 9 do
        local gridLine = Instance.new("Frame")
        gridLine.Name = "GridX" .. index
        gridLine.Position = UDim2.fromScale(index / 10, 0)
        gridLine.Size = UDim2.fromScale(0.001, 1)
        gridLine.BackgroundColor3 = Color3.fromRGB(92, 148, 211)
        gridLine.BackgroundTransparency = 0.965
        gridLine.BorderSizePixel = 0
        gridLine.Parent = backdrop
    end
    for index = 1, 6 do
        local gridLine = Instance.new("Frame")
        gridLine.Name = "GridY" .. index
        gridLine.Position = UDim2.fromScale(0, index / 7)
        gridLine.Size = UDim2.fromScale(1, 0.001)
        gridLine.BackgroundColor3 = Color3.fromRGB(92, 148, 211)
        gridLine.BackgroundTransparency = 0.967
        gridLine.BorderSizePixel = 0
        gridLine.Parent = backdrop
    end

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
    loopTween(glow, TweenInfo.new(4.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
        Position = UDim2.fromScale(0.7, 0.33),
        BackgroundTransparency = 0.91,
    }, stageTweens)

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
    loopTween(secondGlow, TweenInfo.new(5.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
        Position = UDim2.fromScale(0.27, 0.67),
        BackgroundTransparency = 0.95,
    }, stageTweens)

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
    loopTween(highlight, TweenInfo.new(3.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Position = UDim2.fromScale(0.62, 0)}, stageTweens)

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
    loopTween(haloGradient, TweenInfo.new(8, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), {Rotation = 360}, stageTweens)
    local coreIcon = textLabel(core, "Icon", "◆", Enum.Font.GothamBold, normal, UDim2.fromScale(0.2, 0.18), UDim2.fromScale(0.6, 0.64))
    coreIcon.TextTransparency = 0.05
    statusOrb = core
    loopTween(core, TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {BackgroundTransparency = 0.56}, stageTweens)

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
    loopTween(fill, moveEase, {Position = UDim2.fromScale(0.78, 0)}, stageTweens)
    local shine = Instance.new("UIGradient")
    shine.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, accent),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(225, 245, 255)),
        ColorSequenceKeypoint.new(1, violetAccent),
    })
    shine.Parent = fill
    loopTween(shine, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Offset = Vector2.new(0.5, 0)}, stageTweens)

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
    loopTween(orb, TweenInfo.new(1.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {BackgroundTransparency = 0.8}, bannerTweens)

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
    for _, tween in ipairs(stageTweens) do if showStage then tween:Play() else tween:Pause() end end
    for _, tween in ipairs(bannerTweens) do if showBanner then tween:Play() else tween:Pause() end end
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
    for _, tween in ipairs(stageTweens) do tween:Cancel() end
    for _, tween in ipairs(bannerTweens) do tween:Cancel() end
    table.clear(stageTweens)
    table.clear(bannerTweens)
    if activeGui then activeGui:Destroy() end
    activeGui, stage, banner, panel = nil, nil, nil, nil
    bannerText, bannerTimer, title, statusText, description = nil, nil, nil, nil, nil
    phaseLabel, progressTrack, phaseFill = nil, nil, nil
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
        for _, label in ipairs({title, statusText, description, phaseLabel}) do
            label.TextTransparency = 0.65
            TweenService:Create(label, fadeEase, {TextTransparency = 0}):Play()
        end
    end
    local shade = status == "ready" and Color3.fromRGB(96, 227, 184) or (status == "error" and Color3.fromRGB(255, 139, 145) or accent)
    TweenService:Create(statusText, fadeEase, {TextColor3 = shade}):Play()
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
    task.spawn(function()
        while player.Parent == Players do
            if player:GetAttribute(readyAttribute) == true then
                arrivalMode = false
                clearInterface()
                return
            end
            local loadError = player:GetAttribute(errorAttribute)
            if loadError ~= nil and currentStatus ~= "error" then update("error", 0, "") end
            task.wait(0.25)
        end
    end)
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

task.spawn(function()
    while player.Parent == Players do
        if currentStatus == "scheduled" and restartAt > 0 then
            local seconds = secondsRemaining()
            if statusText then statusText.Text = seconds == 0 and "Moving to new server soon" or "Server restart in " .. countdown(seconds) end
            if bannerTimer then bannerTimer.Text = countdown(seconds) end
            if seconds <= 30 and activePresentation == "banner" then setPresentation("full") end
        end
        task.wait(0.35)
    end
end)
