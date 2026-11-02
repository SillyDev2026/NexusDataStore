--!strict
-- Install as a LocalScript under ReplicatedFirst. No GUI objects need to be created in Studio.
-- The store name must match NexusDataStore.new({Name = "PlayerData"}).
local STORE_NAME = "PlayerData"
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local arriving = TeleportService:GetArrivingTeleportGui()
local activeGui: ScreenGui? = nil
local statusLabel: TextLabel? = nil
local detailLabel: TextLabel? = nil
local titleLabel: TextLabel? = nil
local restartAt = 0
local currentStatus = "idle"
local closed = false

local function createGui(): ScreenGui
    local gui = Instance.new("ScreenGui")
    gui.Name = "NexusRestartGui"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 1000
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local screen = Instance.new("Frame")
    screen.Name = "Background"
    screen.Size = UDim2.fromScale(1, 1)
    screen.BackgroundColor3 = Color3.fromRGB(10, 15, 30)
    screen.BorderSizePixel = 0
    screen.Parent = gui
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new(Color3.fromRGB(10, 15, 30), Color3.fromRGB(23, 39, 69))
    gradient.Rotation = 45
    gradient.Parent = screen

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.fromScale(0.86, 0.36)
    panel.BackgroundColor3 = Color3.fromRGB(20, 29, 47)
    panel.BorderSizePixel = 0
    panel.Parent = screen
    local constraint = Instance.new("UISizeConstraint")
    constraint.MaxSize = Vector2.new(540, 310)
    constraint.MinSize = Vector2.new(220, 170)
    constraint.Parent = panel
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.065, 0)
    corner.Parent = panel
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1
    stroke.Color = Color3.fromRGB(67, 90, 126)
    stroke.Transparency = 0.35
    stroke.Parent = panel

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Padding = UDim.new(0.045, 0)
    layout.Parent = panel

    local tag = Instance.new("TextLabel")
    tag.Name = "Tag"
    tag.Size = UDim2.fromScale(0.85, 0.12)
    tag.BackgroundTransparency = 1
    tag.Font = Enum.Font.GothamBold
    tag.Text = "NEXUS  /  SERVER UPDATE"
    tag.TextColor3 = Color3.fromRGB(91, 185, 255)
    tag.TextScaled = true
    tag.Parent = panel

    local heading = Instance.new("TextLabel")
    heading.Name = "Title"
    heading.Size = UDim2.fromScale(0.88, 0.25)
    heading.BackgroundTransparency = 1
    heading.Font = Enum.Font.GothamBold
    heading.Text = "Server restarting"
    heading.TextColor3 = Color3.fromRGB(245, 249, 255)
    heading.TextScaled = true
    heading.TextWrapped = true
    heading.Parent = panel

    local state = Instance.new("TextLabel")
    state.Name = "Status"
    state.Size = UDim2.fromScale(0.86, 0.14)
    state.BackgroundTransparency = 1
    state.Font = Enum.Font.GothamMedium
    state.Text = "Preparing your progress..."
    state.TextColor3 = Color3.fromRGB(180, 219, 252)
    state.TextScaled = true
    state.TextWrapped = true
    state.Parent = panel

    local details = Instance.new("TextLabel")
    details.Name = "Details"
    details.Size = UDim2.fromScale(0.85, 0.22)
    details.BackgroundTransparency = 1
    details.Font = Enum.Font.Gotham
    details.Text = "You will be moved automatically when Roblox restarts the server."
    details.TextColor3 = Color3.fromRGB(166, 179, 200)
    details.TextScaled = true
    details.TextWrapped = true
    details.Parent = panel

    local indicator = Instance.new("Frame")
    indicator.Name = "Indicator"
    indicator.Size = UDim2.fromScale(0.75, 0.023)
    indicator.BackgroundColor3 = Color3.fromRGB(44, 59, 84)
    indicator.BorderSizePixel = 0
    indicator.Parent = panel
    local progress = Instance.new("Frame")
    progress.Name = "Motion"
    progress.Size = UDim2.fromScale(0.2, 1)
    progress.BackgroundColor3 = Color3.fromRGB(45, 170, 255)
    progress.BorderSizePixel = 0
    progress.Parent = indicator
    local moving = TweenService:Create(progress, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Position = UDim2.fromScale(0.8, 0)})
    moving:Play()
    return gui
end

local function attach(gui: ScreenGui)
    activeGui = gui
    local panel = gui:WaitForChild("Background"):WaitForChild("Panel")
    statusLabel = panel:WaitForChild("Status") :: TextLabel
    detailLabel = panel:WaitForChild("Details") :: TextLabel
    titleLabel = panel:WaitForChild("Title") :: TextLabel
    gui.Parent = playerGui
end

local function show()
    if closed then return end
    if not activeGui then attach(createGui()) end
    if activeGui then activeGui.Enabled = true end
end

local function hide()
    closed = true
    if activeGui then activeGui:Destroy(); activeGui = nil end
end

local function update(status: string, target: number, message: string)
    if status == "idle" then return end
    currentStatus = status
    restartAt = target
    show()
    if not titleLabel or not statusLabel or not detailLabel then return end
    if status == "arriving" then
        titleLabel.Text = "Connecting to new server"
        statusLabel.Text = "Securing your profile session..."
        detailLabel.Text = "Your previous session lock must be released before progress loads."
    elseif status == "scheduled" then
        titleLabel.Text = "Server update incoming"
        statusLabel.Text = "Preparing to migrate..."
        detailLabel.Text = message
    elseif status == "saving" then
        titleLabel.Text = "Saving your progress"
        statusLabel.Text = "Please stay in the game"
        detailLabel.Text = "Final profile saves are being prepared before Roblox moves this server."
    elseif status == "retrying" then
        titleLabel.Text = "Securing your progress"
        statusLabel.Text = "Retrying a save request..."
        detailLabel.Text = "A DataStore request needs another attempt. Your session remains protected."
    elseif status == "ready" then
        titleLabel.Text = "Update is ready"
        statusLabel.Text = "Latest progress saved"
        detailLabel.Text = "Roblox will automatically move you to an updated game server."
    elseif status == "error" then
        titleLabel.Text = "Unable to load profile"
        statusLabel.Text = "Please reconnect"
        detailLabel.Text = "Your profile is locked or the data service is unavailable. No replacement save was made."
    end
end

if arriving and arriving:IsA("ScreenGui") and arriving.Name == "NexusRestartGui" then
    ReplicatedFirst:RemoveDefaultLoadingScreen()
    attach(arriving)
    update("arriving", 0, "")
    task.spawn(function()
        while not closed do
            if player:GetAttribute("NexusDataStoreProfileReady") == true then
                hide()
                return
            end
            local loadError = player:GetAttribute("NexusDataStoreProfileError")
            if loadError ~= nil then
                update("error", 0, "")
                return
            end
            task.wait(0.25)
        end
    end)
end

task.spawn(function()
    local remote = ReplicatedStorage:WaitForChild("NexusDataStoreRestart_" .. STORE_NAME, 30)
    if not remote or not remote:IsA("RemoteEvent") then return end
    local function sync()
        local status = remote:GetAttribute("Status")
        if typeof(status) ~= "string" or status == "idle" then return end
        local when = remote:GetAttribute("RestartAt")
        local message = remote:GetAttribute("Message")
        update(status, typeof(when) == "number" and when or 0, typeof(message) == "string" and message or "")
        if activeGui then pcall(TeleportService.SetTeleportGui, TeleportService, activeGui) end
    end
    remote.OnClientEvent:Connect(function(status, when, message)
        if typeof(status) ~= "string" then return end
        update(status, typeof(when) == "number" and when or 0, typeof(message) == "string" and message or "")
        if activeGui then pcall(TeleportService.SetTeleportGui, TeleportService, activeGui) end
    end)
    sync()
end)

task.spawn(function()
    while not closed do
        if currentStatus == "scheduled" and statusLabel and restartAt > 0 then
            local seconds = math.max(0, restartAt - DateTime.now().UnixTimestamp)
            statusLabel.Text = string.format("Restart in %02d:%02d", math.floor(seconds / 60), seconds % 60)
        end
        task.wait(1)
    end
end)
