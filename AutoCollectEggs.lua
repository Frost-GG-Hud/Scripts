--[[
    ❄️ Frost Hub - Auto Collect Eggs Feature Prototype
    Legitimate gameplay automation testing system for Roblox experiences.
    
    Gameplay Loop:
    1. Detect available eggs from server-spawned state (RenderedEggs / ActiveEggs).
    2. Select closest eligible egg.
    3. Navigate player to egg using PathfindingService & Humanoid:MoveTo.
    4. Trigger the normal ProximityPrompt collection interaction.
    5. Wait for server confirmation of carried state (player.Basket).
    6. Navigate player to designated plot deposit area.
    7. Trigger deposit on plot entry and confirm basket cleared.
    8. Loop continuously while feature is enabled.
--]]

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------
local Config = {
    AgentRadius = 2.0,
    AgentHeight = 5.0,
    AgentCanJump = true,
    AgentCanClimb = true,
    WaypointSpacing = 4.0,
    MaxInteractDistance = 10.0,
    StuckThresholdSeconds = 2.0,
    CarriedWaitTimeout = 5.0,
    DepositWaitTimeout = 10.0,
    ScanRetryDelay = 1.5,
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local State = {
    Enabled = false,
    CurrentStatus = "Idle",
    TargetEggName = "None",
    EggsCollected = 0,
    StartTime = os.clock(),
    CurrentTask = nil,
}

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------
local function getCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getHumanoid()
    local char = getCharacter()
    return char:WaitForChild("Humanoid", 5)
end

local function getHRP()
    local char = getCharacter()
    return char:WaitForChild("HumanoidRootPart", 5)
end

-- Locates the player's personal plot (deposit area)
local function getPlayerPlot()
    local plotsFolder = workspace:FindFirstChild("Plots")
    if not plotsFolder then return nil end

    for _, plot in ipairs(plotsFolder:GetChildren()) do
        if plot:GetAttribute("NestsOwnerLoaded") == LocalPlayer.UserId then
            return plot
        end
        local ownerAttr = plot:GetAttribute("Owner") or plot:GetAttribute("OwnerUserId")
        if ownerAttr == LocalPlayer.UserId or ownerAttr == LocalPlayer.Name then
            return plot
        end
    end
    return nil
end

-- Gets the deposit position within the player's plot
local function getDepositTargetPosition()
    local plot = getPlayerPlot()
    if not plot then return nil end

    local baseplate = plot:FindFirstChild("Baseplate")
    if baseplate and baseplate:IsA("BasePart") then
        return baseplate.Position + Vector3.new(0, 3, 0)
    end

    local pivot = plot:GetPivot()
    return pivot.Position + Vector3.new(0, 3, 0)
end

-- Checks if player is already inside their own plot baseplate bounds
local function isInsideOwnPlot()
    local plot = getPlayerPlot()
    if not plot then return false end

    local baseplate = plot:FindFirstChild("Baseplate")
    local hrp = getHRP()
    if not baseplate or not hrp then return false end

    local rel = baseplate.CFrame:PointToObjectSpace(hrp.Position)
    local halfX = baseplate.Size.X / 2
    local halfZ = baseplate.Size.Z / 2
    return math.abs(rel.X) <= halfX and math.abs(rel.Z) <= halfZ
end

-- Queries server-provided eggs from RenderedEggs
local function getAvailableEggs()
    local eggsFolder = workspace:FindFirstChild("RenderedEggs")
    if not eggsFolder then return {} end

    local hrp = getHRP()
    if not hrp then return {} end

    local list = {}
    for _, eggModel in ipairs(eggsFolder:GetChildren()) do
        if eggModel:IsA("Model") then
            local primary = eggModel.PrimaryPart or eggModel:FindFirstChildWhichIsA("BasePart")
            local prompt = eggModel:FindFirstChildWhichIsA("ProximityPrompt", true)

            if primary and prompt and prompt.Enabled then
                local dist = (primary.Position - hrp.Position).Magnitude
                table.insert(list, {
                    Model = eggModel,
                    Part = primary,
                    Prompt = prompt,
                    Distance = dist,
                    Name = eggModel.Name
                })
            end
        end
    end

    table.sort(list, function(a, b)
        return a.Distance < b.Distance
    end)

    return list
end

-- Checks how many eggs are currently in the player's carried basket
local function getCarriedCount()
    local basket = LocalPlayer:FindFirstChild("Basket")
    if basket then
        return #basket:GetChildren()
    end
    return 0
end

--------------------------------------------------------------------------------
-- MOVEMENT / PATHFINDING SYSTEM
--------------------------------------------------------------------------------
local function moveToPoint(targetPos)
    local hrp = getHRP()
    local hum = getHumanoid()
    if not hrp or not hum then return false end

    local path = PathfindingService:CreatePath({
        AgentRadius = Config.AgentRadius,
        AgentHeight = Config.AgentHeight,
        AgentCanJump = Config.AgentCanJump,
        AgentCanClimb = Config.AgentCanClimb,
        WaypointSpacing = Config.WaypointSpacing
    })

    local success, err = pcall(function()
        path:ComputeAsync(hrp.Position, targetPos)
    end)

    if not success or path.Status ~= Enum.PathStatus.Success then
        -- Fallback direct MoveTo if pathfinding couldn't solve directly
        hum:MoveTo(targetPos)
        local fallbackStart = os.clock()
        while State.Enabled and (hrp.Position - targetPos).Magnitude > 4 do
            if os.clock() - fallbackStart > 3 then break end
            task.wait(0.1)
        end
        return (hrp.Position - targetPos).Magnitude <= 5
    end

    local waypoints = path:GetWaypoints()
    for idx, waypoint in ipairs(waypoints) do
        if not State.Enabled then return false end

        -- Jump when path requires it or if climbing ledge
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            hum.Jump = true
        end

        hum:MoveTo(waypoint.Position)

        local moveStart = os.clock()
        local lastPos = hrp.Position
        local lastStuckCheck = os.clock()

        while State.Enabled do
            local dist = (hrp.Position - waypoint.Position).Magnitude
            if dist <= 3.5 then
                break
            end

            -- Stuck detection
            if os.clock() - lastStuckCheck >= 0.5 then
                local moved = (hrp.Position - lastPos).Magnitude
                if moved < 0.6 then
                    -- Player is stuck on an obstacle, attempt a hop/unjam
                    hum.Jump = true
                    hum:MoveTo(waypoint.Position + Vector3.new(math.random(-1, 1), 0, math.random(-1, 1)))
                end
                lastPos = hrp.Position
                lastStuckCheck = os.clock()
            end

            if os.clock() - moveStart > Config.StuckThresholdSeconds then
                -- Timeout on this waypoint, continue to next
                break
            end

            task.wait(0.05)
        end
    end

    return (hrp.Position - targetPos).Magnitude <= 5
end

--------------------------------------------------------------------------------
-- INTERACTION HELPERS
--------------------------------------------------------------------------------
local function triggerPrompt(prompt)
    if not prompt or not prompt.Parent then return false end

    -- Use executor fireproximityprompt if supported
    if typeof(fireproximityprompt) == "function" then
        fireproximityprompt(prompt)
        return true
    end

    -- Standard Roblox engine simulation
    pcall(function()
        prompt:InputHoldBegin()
        task.wait((prompt.HoldDuration or 0.2) + 0.05)
        prompt:InputHoldEnd()
    end)
    return true
end

--------------------------------------------------------------------------------
-- CORE COLLECTION STATE MACHINE
--------------------------------------------------------------------------------
local updateStatusUI -- Forward declaration for UI updater

local function runCollectionLoop()
    while State.Enabled do
        -- 1. Check if already carrying an egg (e.g. from previous run or interruption)
        if getCarriedCount() > 0 then
            State.CurrentStatus = "Delivering to Deposit Plot..."
            updateStatusUI()

            local depositPos = getDepositTargetPosition()
            if depositPos then
                moveToPoint(depositPos)
            end

            -- Confirm deposit succeeded
            local waitStart = os.clock()
            State.CurrentStatus = "Confirming Deposit..."
            updateStatusUI()

            while State.Enabled and getCarriedCount() > 0 and os.clock() - waitStart < Config.DepositWaitTimeout do
                task.wait(0.2)
            end

            if getCarriedCount() == 0 then
                State.EggsCollected = State.EggsCollected + 1
                State.CurrentStatus = "Deposited Successfully!"
                updateStatusUI()
                task.wait(0.5)
            end
        end

        if not State.Enabled then break end

        -- 2. Select eligible egg from server-provided state
        State.CurrentStatus = "Scanning for Eligible Eggs..."
        State.TargetEggName = "None"
        updateStatusUI()

        local available = getAvailableEggs()
        if #available == 0 then
            State.CurrentStatus = "No Eggs Found, Rescanning..."
            updateStatusUI()
            task.wait(Config.ScanRetryDelay)
            continue
        end

        local target = available[1]
        State.TargetEggName = target.Name
        State.CurrentStatus = string.format("Approaching %s (%.0f studs)", target.Name, target.Distance)
        updateStatusUI()

        -- 3. Move player to the egg using pathfinding
        local targetPos = target.Part.Position
        local arrived = moveToPoint(targetPos)
        if not State.Enabled then break end

        -- Verify egg still exists and is interactive
        if not target.Model.Parent or not target.Prompt.Parent or not target.Prompt.Enabled then
            State.CurrentStatus = "Egg Despawned / Claimed, Retrying..."
            updateStatusUI()
            task.wait(0.3)
            continue
        end

        -- 4. Trigger collection interaction
        State.CurrentStatus = string.format("Collecting %s...", target.Name)
        updateStatusUI()

        local preCount = getCarriedCount()
        triggerPrompt(target.Prompt)

        -- 5. Wait for confirmation of carried state
        local waitCarriedStart = os.clock()
        local confirmedCarried = false
        while State.Enabled and os.clock() - waitCarriedStart < Config.CarriedWaitTimeout do
            if getCarriedCount() > preCount then
                confirmedCarried = true
                break
            end
            task.wait(0.1)
        end

        if not confirmedCarried and getCarriedCount() == preCount then
            State.CurrentStatus = "Collection Retrying..."
            updateStatusUI()
            task.wait(0.5)
            continue
        end

        -- 6. Navigate to designated deposit area
        State.CurrentStatus = "Carrying to Plot Deposit..."
        updateStatusUI()

        local depositPos = getDepositTargetPosition()
        if not depositPos then
            State.CurrentStatus = "Plot Not Found!"
            updateStatusUI()
            task.wait(2)
            continue
        end

        moveToPoint(depositPos)
        if not State.Enabled then break end

        -- 7. Confirm deposit succeeded
        State.CurrentStatus = "Depositing Egg..."
        updateStatusUI()

        local depositStart = os.clock()
        while State.Enabled and getCarriedCount() > 0 and os.clock() - depositStart < Config.DepositWaitTimeout do
            task.wait(0.2)
        end

        if getCarriedCount() == 0 then
            State.EggsCollected = State.EggsCollected + 1
            State.CurrentStatus = "Deposit Confirmed! (+1)"
            updateStatusUI()
            task.wait(0.4)
        else
            State.CurrentStatus = "Deposit Pending..."
            updateStatusUI()
            task.wait(0.5)
        end
    end

    State.CurrentStatus = "Idle"
    State.TargetEggName = "None"
    updateStatusUI()
end

--------------------------------------------------------------------------------
-- MODERN FROST-THEMED UI
--------------------------------------------------------------------------------
-- Cleanup previous instances if running
pcall(function()
    if gethui then
        for _, c in ipairs(gethui():GetChildren()) do
            if c.Name == "FrostHub_AutoCollectEggs" then c:Destroy() end
        end
    end
    for _, c in ipairs(CoreGui:GetChildren()) do
        if c.Name == "FrostHub_AutoCollectEggs" then c:Destroy() end
    end
    if LocalPlayer:FindFirstChild("PlayerGui") then
        for _, c in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
            if c.Name == "FrostHub_AutoCollectEggs" then c:Destroy() end
        end
    end
end)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "FrostHub_AutoCollectEggs"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

pcall(function()
    if syn and syn.protect_gui then
        syn.protect_gui(ScreenGui)
        ScreenGui.Parent = CoreGui
    elseif gethui then
        ScreenGui.Parent = gethui()
    else
        ScreenGui.Parent = CoreGui
    end
end)
if not ScreenGui.Parent then
    ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

-- Main Window Card
local MainCard = Instance.new("Frame")
MainCard.Name = "MainCard"
MainCard.Size = UDim2.fromOffset(300, 230)
MainCard.Position = UDim2.new(0.04, 0, 0.28, 0)
MainCard.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
MainCard.BorderSizePixel = 0
MainCard.Active = true
MainCard.ClipsDescendants = true
MainCard.Parent = ScreenGui

-- UI Scaling Controller (Enables resizing/expanding HUD)
local CardScale = Instance.new("UIScale")
CardScale.Scale = 1.0
CardScale.Parent = MainCard

local CardCorner = Instance.new("UICorner")
CardCorner.CornerRadius = UDim.new(0, 14)
CardCorner.Parent = MainCard

local CardStroke = Instance.new("UIStroke")
CardStroke.Color = Color3.fromRGB(35, 75, 125)
CardStroke.Thickness = 1.4
CardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
CardStroke.Parent = MainCard

-- Header Title Bar
local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 42)
Header.BackgroundColor3 = Color3.fromRGB(20, 28, 44)
Header.BorderSizePixel = 0
Header.Parent = MainCard

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 14)
HeaderCorner.Parent = Header

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Name = "Title"
TitleLabel.Size = UDim2.new(1, -78, 1, 0)
TitleLabel.Position = UDim2.fromOffset(14, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "❄️ Frost Hub | Auto Collect"
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextSize = 13
TitleLabel.TextColor3 = Color3.fromRGB(220, 238, 255)
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = Header

-- Top-Right Controls Container (Resize / Close)
local HeaderControls = Instance.new("Frame")
HeaderControls.Name = "HeaderControls"
HeaderControls.Size = UDim2.fromOffset(60, 26)
HeaderControls.AnchorPoint = Vector2.new(1, 0.5)
HeaderControls.Position = UDim2.new(1, -8, 0.5, 0)
HeaderControls.BackgroundTransparency = 1
HeaderControls.Parent = Header

local ControlsLayout = Instance.new("UIListLayout")
ControlsLayout.FillDirection = Enum.FillDirection.Horizontal
ControlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
ControlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
ControlsLayout.SortOrder = Enum.SortOrder.LayoutOrder
ControlsLayout.Padding = UDim.new(0, 5)
ControlsLayout.Parent = HeaderControls

-- Resize Button (Makes HUD bigger)
local SizeBtn = Instance.new("TextButton")
SizeBtn.Name = "SizeButton"
SizeBtn.Size = UDim2.fromOffset(26, 26)
SizeBtn.BackgroundColor3 = Color3.fromRGB(28, 38, 58)
SizeBtn.AutoButtonColor = false
SizeBtn.Text = "⤢"
SizeBtn.Font = Enum.Font.GothamBold
SizeBtn.TextSize = 13
SizeBtn.TextColor3 = Color3.fromRGB(170, 210, 255)
SizeBtn.LayoutOrder = 1
SizeBtn.Parent = HeaderControls

local SizeCorner = Instance.new("UICorner")
SizeCorner.CornerRadius = UDim.new(0, 6)
SizeCorner.Parent = SizeBtn

local SizeStroke = Instance.new("UIStroke")
SizeStroke.Color = Color3.fromRGB(45, 68, 105)
SizeStroke.Thickness = 1
SizeStroke.Parent = SizeBtn

-- Close Button (Closes HUD)
local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseButton"
CloseBtn.Size = UDim2.fromOffset(26, 26)
CloseBtn.BackgroundColor3 = Color3.fromRGB(28, 38, 58)
CloseBtn.AutoButtonColor = false
CloseBtn.Text = "✕"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 11
CloseBtn.TextColor3 = Color3.fromRGB(170, 210, 255)
CloseBtn.LayoutOrder = 2
CloseBtn.Parent = HeaderControls

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

local CloseStroke = Instance.new("UIStroke")
CloseStroke.Color = Color3.fromRGB(45, 68, 105)
CloseStroke.Thickness = 1
CloseStroke.Parent = CloseBtn

-- Content Container
local Content = Instance.new("Frame")
Content.Name = "Content"
Content.Size = UDim2.new(1, -20, 1, -50)
Content.Position = UDim2.fromOffset(10, 46)
Content.BackgroundTransparency = 1
Content.Parent = MainCard

local UIList = Instance.new("UIListLayout")
UIList.SortOrder = Enum.SortOrder.LayoutOrder
UIList.Padding = UDim.new(0, 8)
UIList.Parent = Content

-- 1. Main Toggle Button Row
local ToggleRow = Instance.new("TextButton")
ToggleRow.Name = "ToggleRow"
ToggleRow.Size = UDim2.new(1, 0, 0, 42)
ToggleRow.BackgroundColor3 = Color3.fromRGB(24, 32, 50)
ToggleRow.AutoButtonColor = false
ToggleRow.Text = ""
ToggleRow.Parent = Content

local ToggleRowCorner = Instance.new("UICorner")
ToggleRowCorner.CornerRadius = UDim.new(0, 8)
ToggleRowCorner.Parent = ToggleRow

local ToggleStroke = Instance.new("UIStroke")
ToggleStroke.Color = Color3.fromRGB(40, 60, 95)
ToggleStroke.Thickness = 1
ToggleStroke.Parent = ToggleRow

local ToggleLabel = Instance.new("TextLabel")
ToggleLabel.Size = UDim2.new(1, -60, 1, 0)
ToggleLabel.Position = UDim2.fromOffset(12, 0)
ToggleLabel.BackgroundTransparency = 1
ToggleLabel.Text = "Auto Collect Eggs"
ToggleLabel.Font = Enum.Font.GothamSemibold
ToggleLabel.TextSize = 13
ToggleLabel.TextColor3 = Color3.fromRGB(240, 246, 255)
ToggleLabel.TextXAlignment = Enum.TextXAlignment.Left
ToggleLabel.Parent = ToggleRow

-- Switch Pill Indicator
local SwitchPill = Instance.new("Frame")
SwitchPill.Size = UDim2.fromOffset(40, 22)
SwitchPill.AnchorPoint = Vector2.new(1, 0.5)
SwitchPill.Position = UDim2.new(1, -10, 0.5, 0)
SwitchPill.BackgroundColor3 = Color3.fromRGB(45, 55, 75)
SwitchPill.BorderSizePixel = 0
SwitchPill.Parent = ToggleRow

local PillCorner = Instance.new("UICorner")
PillCorner.CornerRadius = UDim.new(1, 0)
PillCorner.Parent = SwitchPill

local SwitchKnob = Instance.new("Frame")
SwitchKnob.Size = UDim2.fromOffset(16, 16)
SwitchKnob.AnchorPoint = Vector2.new(0, 0.5)
SwitchKnob.Position = UDim2.new(0, 3, 0.5, 0)
SwitchKnob.BackgroundColor3 = Color3.fromRGB(200, 215, 235)
SwitchKnob.BorderSizePixel = 0
SwitchKnob.Parent = SwitchPill

local KnobCorner = Instance.new("UICorner")
KnobCorner.CornerRadius = UDim.new(1, 0)
KnobCorner.Parent = SwitchKnob

-- 2. Status Box
local StatusBox = Instance.new("Frame")
StatusBox.Name = "StatusBox"
StatusBox.Size = UDim2.new(1, 0, 0, 38)
StatusBox.BackgroundColor3 = Color3.fromRGB(20, 26, 40)
StatusBox.BorderSizePixel = 0
StatusBox.Parent = Content

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 8)
StatusCorner.Parent = StatusBox

local StatusText = Instance.new("TextLabel")
StatusText.Name = "StatusText"
StatusText.Size = UDim2.new(1, -20, 1, 0)
StatusText.Position = UDim2.fromOffset(10, 0)
StatusText.BackgroundTransparency = 1
StatusText.Text = "Status: Idle"
StatusText.Font = Enum.Font.GothamMedium
StatusText.TextSize = 12
StatusText.TextColor3 = Color3.fromRGB(130, 185, 255)
StatusText.TextXAlignment = Enum.TextXAlignment.Left
StatusText.Parent = StatusBox

-- 3. Stats Row
local StatsRow = Instance.new("Frame")
StatsRow.Name = "StatsRow"
StatsRow.Size = UDim2.new(1, 0, 0, 48)
StatsRow.BackgroundTransparency = 1
StatsRow.Parent = Content

local StatsLayout = Instance.new("UIGridLayout")
StatsLayout.CellSize = UDim2.new(0.485, 0, 1, 0)
StatsLayout.CellPadding = UDim2.new(0.03, 0, 0, 0)
StatsLayout.Parent = StatsRow

-- Stat 1: Collected
local StatCol = Instance.new("Frame")
StatCol.BackgroundColor3 = Color3.fromRGB(20, 26, 40)
StatCol.BorderSizePixel = 0
StatCol.Parent = StatsRow
local StatColCorner = Instance.new("UICorner")
StatColCorner.CornerRadius = UDim.new(0, 8)
StatColCorner.Parent = StatCol

local StatColTitle = Instance.new("TextLabel")
StatColTitle.Size = UDim2.new(1, 0, 0, 18)
StatColTitle.Position = UDim2.fromOffset(0, 4)
StatColTitle.BackgroundTransparency = 1
StatColTitle.Text = "COLLECTED"
StatColTitle.Font = Enum.Font.GothamBold
StatColTitle.TextSize = 9
StatColTitle.TextColor3 = Color3.fromRGB(110, 140, 175)
StatColTitle.Parent = StatCol

local StatColValue = Instance.new("TextLabel")
StatColValue.Name = "Value"
StatColValue.Size = UDim2.new(1, 0, 0, 22)
StatColValue.Position = UDim2.fromOffset(0, 20)
StatColValue.BackgroundTransparency = 1
StatColValue.Text = "0"
StatColValue.Font = Enum.Font.GothamBold
StatColValue.TextSize = 16
StatColValue.TextColor3 = Color3.fromRGB(255, 255, 255)
StatColValue.Parent = StatCol

-- Stat 2: Target
local StatTarget = Instance.new("Frame")
StatTarget.BackgroundColor3 = Color3.fromRGB(20, 26, 40)
StatTarget.BorderSizePixel = 0
StatTarget.Parent = StatsRow
local StatTargetCorner = Instance.new("UICorner")
StatTargetCorner.CornerRadius = UDim.new(0, 8)
StatTargetCorner.Parent = StatTarget

local StatTargetTitle = Instance.new("TextLabel")
StatTargetTitle.Size = UDim2.new(1, 0, 0, 18)
StatTargetTitle.Position = UDim2.fromOffset(0, 4)
StatTargetTitle.BackgroundTransparency = 1
StatTargetTitle.Text = "TARGET"
StatTargetTitle.Font = Enum.Font.GothamBold
StatTargetTitle.TextSize = 9
StatTargetTitle.TextColor3 = Color3.fromRGB(110, 140, 175)
StatTargetTitle.Parent = StatTarget

local StatTargetValue = Instance.new("TextLabel")
StatTargetValue.Name = "Value"
StatTargetValue.Size = UDim2.new(1, -6, 0, 22)
StatTargetValue.Position = UDim2.fromOffset(3, 20)
StatTargetValue.BackgroundTransparency = 1
StatTargetValue.Text = "None"
StatTargetValue.Font = Enum.Font.GothamBold
StatTargetValue.TextSize = 11
StatTargetValue.TextColor3 = Color3.fromRGB(100, 220, 255)
StatTargetValue.TextTruncate = Enum.TextTruncate.AtEnd
StatTargetValue.Parent = StatTarget

-- 4. Footer Note
local Footer = Instance.new("TextLabel")
Footer.Size = UDim2.new(1, 0, 0, 16)
Footer.BackgroundTransparency = 1
Footer.Text = "Press RightControl to toggle UI"
Footer.Font = Enum.Font.Gotham
Footer.TextSize = 10
Footer.TextColor3 = Color3.fromRGB(85, 115, 150)
Footer.Parent = Content

--------------------------------------------------------------------------------
-- UI LOGIC & DRAGGING
--------------------------------------------------------------------------------
updateStatusUI = function()
    StatusText.Text = "Status: " .. State.CurrentStatus
    StatColValue.Text = tostring(State.EggsCollected)
    StatTargetValue.Text = State.TargetEggName
end

local function setToggle(active)
    State.Enabled = active
    if active then
        TweenService:Create(SwitchPill, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(0, 180, 240)}):Play()
        TweenService:Create(SwitchKnob, TweenInfo.new(0.2), {Position = UDim2.new(1, -19, 0.5, 0), BackgroundColor3 = Color3.fromRGB(255, 255, 255)}):Play()
        TweenService:Create(ToggleStroke, TweenInfo.new(0.2), {Color = Color3.fromRGB(0, 180, 240)}):Play()

        if State.CurrentTask then
            task.cancel(State.CurrentTask)
        end
        State.CurrentTask = task.spawn(runCollectionLoop)
    else
        TweenService:Create(SwitchPill, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(45, 55, 75)}):Play()
        TweenService:Create(SwitchKnob, TweenInfo.new(0.2), {Position = UDim2.new(0, 3, 0.5, 0), BackgroundColor3 = Color3.fromRGB(200, 215, 235)}):Play()
        TweenService:Create(ToggleStroke, TweenInfo.new(0.2), {Color = Color3.fromRGB(40, 60, 95)}):Play()

        if State.CurrentTask then
            task.cancel(State.CurrentTask)
            State.CurrentTask = nil
        end
        State.CurrentStatus = "Stopped"
        State.TargetEggName = "None"
        updateStatusUI()
    end
end

ToggleRow.MouseButton1Click:Connect(function()
    setToggle(not State.Enabled)
end)

-- Floating Open Pill (Allows reopening HUD when closed)
local FloatingPill = Instance.new("TextButton")
FloatingPill.Name = "FloatingOpenPill"
FloatingPill.Size = UDim2.fromOffset(132, 34)
FloatingPill.Position = UDim2.new(0.04, 0, 0.28, 0)
FloatingPill.BackgroundColor3 = Color3.fromRGB(18, 26, 42)
FloatingPill.AutoButtonColor = false
FloatingPill.Text = "❄️ Open HUD"
FloatingPill.Font = Enum.Font.GothamBold
FloatingPill.TextSize = 12
FloatingPill.TextColor3 = Color3.fromRGB(190, 230, 255)
FloatingPill.Visible = false
FloatingPill.Parent = ScreenGui

local PillCorner = Instance.new("UICorner")
PillCorner.CornerRadius = UDim.new(0, 10)
PillCorner.Parent = FloatingPill

local PillStroke = Instance.new("UIStroke")
PillStroke.Color = Color3.fromRGB(35, 75, 125)
PillStroke.Thickness = 1.2
PillStroke.Parent = FloatingPill

-- Dragging for Floating Pill
local pillDragging, pillDragStart, pillStartPos = false, nil, nil
FloatingPill.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        pillDragging = true
        pillDragStart = input.Position
        pillStartPos = FloatingPill.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                pillDragging = false
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if pillDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - pillDragStart
        FloatingPill.Position = UDim2.new(
            pillStartPos.X.Scale,
            pillStartPos.X.Offset + delta.X,
            pillStartPos.Y.Scale,
            pillStartPos.Y.Offset + delta.Y
        )
    end
end)

-- HUD Resizing Logic (Normal 1.0x -> Big 1.3x -> Extra Big 1.55x)
local scaleLevels = { 1.0, 1.3, 1.55 }
local currentScaleIndex = 1

SizeBtn.MouseButton1Click:Connect(function()
    currentScaleIndex = (currentScaleIndex % #scaleLevels) + 1
    local targetScale = scaleLevels[currentScaleIndex]

    TweenService:Create(CardScale, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Scale = targetScale
    }):Play()

    if currentScaleIndex == 1 then
        SizeBtn.Text = "⤢"
        SizeBtn.TextColor3 = Color3.fromRGB(170, 210, 255)
    else
        SizeBtn.Text = "⤡"
        SizeBtn.TextColor3 = Color3.fromRGB(0, 215, 255)
    end
end)

SizeBtn.MouseEnter:Connect(function()
    TweenService:Create(SizeBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(45, 65, 95)}):Play()
end)
SizeBtn.MouseLeave:Connect(function()
    TweenService:Create(SizeBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(28, 38, 58)}):Play()
end)

-- HUD Close Logic
local function closeHUD()
    local closeTween = TweenService:Create(CardScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
        Scale = 0.8
    })
    closeTween:Play()
    closeTween.Completed:Connect(function()
        MainCard.Visible = false
        CardScale.Scale = scaleLevels[currentScaleIndex]
    end)
    FloatingPill.Visible = true
end

local function openHUD()
    FloatingPill.Visible = false
    MainCard.Visible = true
    CardScale.Scale = 0.85
    TweenService:Create(CardScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Scale = scaleLevels[currentScaleIndex]
    }):Play()
end

CloseBtn.MouseButton1Click:Connect(function()
    closeHUD()
end)

CloseBtn.MouseEnter:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {
        BackgroundColor3 = Color3.fromRGB(150, 35, 45),
        TextColor3 = Color3.fromRGB(255, 255, 255)
    }):Play()
    TweenService:Create(CloseStroke, TweenInfo.new(0.15), {Color = Color3.fromRGB(230, 60, 75)}):Play()
end)

CloseBtn.MouseLeave:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {
        BackgroundColor3 = Color3.fromRGB(28, 38, 58),
        TextColor3 = Color3.fromRGB(170, 210, 255)
    }):Play()
    TweenService:Create(CloseStroke, TweenInfo.new(0.15), {Color = Color3.fromRGB(45, 68, 105)}):Play()
end)

FloatingPill.MouseButton1Click:Connect(function()
    openHUD()
end)

FloatingPill.MouseEnter:Connect(function()
    TweenService:Create(FloatingPill, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(30, 42, 68)}):Play()
end)
FloatingPill.MouseLeave:Connect(function()
    TweenService:Create(FloatingPill, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(18, 26, 42)}):Play()
end)

-- Draggable implementation
local dragging, dragStart, startPos = false, nil, nil
Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = MainCard.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        MainCard.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

-- Hotkey to toggle UI visibility (RightControl)
UserInputService.InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.RightControl then
        if MainCard.Visible then
            closeHUD()
        else
            openHUD()
        end
    end
end)

print("❄️ [Frost Hub] Auto Collect Eggs prototype initialized successfully.")
