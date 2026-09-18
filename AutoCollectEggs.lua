--[[
    ❄️ Frost Hub - Auto Collect Eggs (WindUI Edition)
    Advanced gameplay automation & testing system with multi-modal movement engines.
    
    Features:
    - Built on WindUI with acrylic blur, custom themes, tabs, and smooth animations
    - Multiple Movement Systems:
        • Walk (Pathfinding) - Intelligent obstacle & fence avoidance
        • Walk (Direct) - Straight-line speed walk
        • Tween (Smooth) - Gliding CFrame interpolation with anti-fall & noclip
    - Speed Controls: Configurable from 1 to 400 studs/s for both walk and tween
    - Legitimate interaction triggers & server-validated carried states (player.Basket)
    - Auto plot detection & deposit validation
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
    MovementMode = "Walk (Pathfinding)", -- "Walk (Pathfinding)", "Walk (Direct)", "Tween (Smooth)"
    WalkSpeed = 24,                      -- 1 to 400
    TweenSpeed = 85,                     -- 1 to 400 studs/s
    NoclipOnTween = true,
    AutoJump = true,
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
    ActiveTween = nil,
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
-- MULTI-MODE MOVEMENT SYSTEM
--------------------------------------------------------------------------------
local function moveToPoint(targetPos)
    local hrp = getHRP()
    local hum = getHumanoid()
    if not hrp or not hum then return false end

    local mode = Config.MovementMode

    ----------------------------------------------------------------------------
    -- MODE 1: TWEEN (Smooth CFrame Glide)
    ----------------------------------------------------------------------------
    if mode == "Tween (Smooth)" then
        local adjustedTarget = targetPos + Vector3.new(0, 2.5, 0)
        local distance = (hrp.Position - adjustedTarget).Magnitude
        if distance <= Config.MaxInteractDistance then return true end

        local speed = math.clamp(tonumber(Config.TweenSpeed) or 85, 1, 400)
        local duration = math.clamp(distance / speed, 0.05, 45)

        -- Noclip during tween if enabled
        local noclipConn = nil
        if Config.NoclipOnTween then
            noclipConn = RunService.Stepped:Connect(function()
                local char = LocalPlayer.Character
                if char then
                    for _, part in ipairs(char:GetDescendants()) do
                        if part:IsA("BasePart") and part.CanCollide then
                            part.CanCollide = false
                        end
                    end
                end
            end)
        end

        local tween = TweenService:Create(hrp, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
            CFrame = CFrame.new(adjustedTarget)
        })
        State.ActiveTween = tween
        tween:Play()

        local completed = false
        local conn = tween.Completed:Connect(function()
            completed = true
        end)

        while State.Enabled and not completed do
            hrp.AssemblyLinearVelocity = Vector3.zero
            task.wait(0.04)
        end

        if conn then conn:Disconnect() end
        if noclipConn then noclipConn:Disconnect() end
        if State.ActiveTween then
            State.ActiveTween:Cancel()
            State.ActiveTween = nil
        end
        return (hrp.Position - targetPos).Magnitude <= (Config.MaxInteractDistance + 3)

    ----------------------------------------------------------------------------
    -- MODE 2: WALK (Direct MoveTo)
    ----------------------------------------------------------------------------
    elseif mode == "Walk (Direct)" then
        hum.WalkSpeed = math.clamp(tonumber(Config.WalkSpeed) or 24, 1, 400)
        hum:MoveTo(targetPos)

        local start = os.clock()
        local lastPos = hrp.Position
        local lastCheck = os.clock()

        while State.Enabled do
            local dist = (hrp.Position - targetPos).Magnitude
            if dist <= Config.MaxInteractDistance then break end

            if os.clock() - lastCheck >= 0.5 then
                if (hrp.Position - lastPos).Magnitude < 0.6 and Config.AutoJump then
                    hum.Jump = true
                end
                lastPos = hrp.Position
                lastCheck = os.clock()
            end

            if os.clock() - start > 15 then break end
            task.wait(0.05)
        end
        return (hrp.Position - targetPos).Magnitude <= (Config.MaxInteractDistance + 3)

    ----------------------------------------------------------------------------
    -- MODE 3: WALK (Pathfinding with obstacle avoidance)
    ----------------------------------------------------------------------------
    else
        hum.WalkSpeed = math.clamp(tonumber(Config.WalkSpeed) or 24, 1, 400)

        local path = PathfindingService:CreatePath({
            AgentRadius = Config.AgentRadius,
            AgentHeight = Config.AgentHeight,
            AgentCanJump = Config.AgentCanJump,
            AgentCanClimb = Config.AgentCanClimb,
            WaypointSpacing = Config.WaypointSpacing
        })

        local success = pcall(function()
            path:ComputeAsync(hrp.Position, targetPos)
        end)

        if not success or path.Status ~= Enum.PathStatus.Success then
            hum:MoveTo(targetPos)
            local fallbackStart = os.clock()
            while State.Enabled and (hrp.Position - targetPos).Magnitude > Config.MaxInteractDistance do
                if os.clock() - fallbackStart > 4 then break end
                task.wait(0.1)
            end
            return (hrp.Position - targetPos).Magnitude <= (Config.MaxInteractDistance + 3)
        end

        local waypoints = path:GetWaypoints()
        for _, waypoint in ipairs(waypoints) do
            if not State.Enabled then return false end

            if waypoint.Action == Enum.PathWaypointAction.Jump and Config.AutoJump then
                hum.Jump = true
            end

            hum:MoveTo(waypoint.Position)

            local moveStart = os.clock()
            local lastPos = hrp.Position
            local lastStuckCheck = os.clock()

            while State.Enabled do
                local dist = (hrp.Position - waypoint.Position).Magnitude
                if dist <= 3.5 or (hrp.Position - targetPos).Magnitude <= Config.MaxInteractDistance then
                    break
                end

                if os.clock() - lastStuckCheck >= 0.5 then
                    local moved = (hrp.Position - lastPos).Magnitude
                    if moved < 0.6 and Config.AutoJump then
                        hum.Jump = true
                        hum:MoveTo(waypoint.Position + Vector3.new(math.random(-1, 1), 0, math.random(-1, 1)))
                    end
                    lastPos = hrp.Position
                    lastStuckCheck = os.clock()
                end

                if os.clock() - moveStart > Config.StuckThresholdSeconds then
                    break
                end

                task.wait(0.05)
            end
        end

        return (hrp.Position - targetPos).Magnitude <= (Config.MaxInteractDistance + 3)
    end
end

--------------------------------------------------------------------------------
-- INTERACTION HELPERS
--------------------------------------------------------------------------------
local function triggerPrompt(prompt)
    if not prompt or not prompt.Parent then return false end

    if typeof(fireproximityprompt) == "function" then
        fireproximityprompt(prompt)
        return true
    end

    pcall(function()
        prompt:InputHoldBegin()
        task.wait((prompt.HoldDuration or 0.2) + 0.05)
        prompt:InputHoldEnd()
    end)
    return true
end

--------------------------------------------------------------------------------
-- CORE STATE MACHINE LOOP
--------------------------------------------------------------------------------
local updateStatusUI -- Forward declaration

local function runCollectionLoop()
    while State.Enabled do
        -- 1. Check if carrying an egg already
        if getCarriedCount() > 0 then
            State.CurrentStatus = "Delivering Carried Egg to Plot..."
            updateStatusUI()

            local depositPos = getDepositTargetPosition()
            if depositPos then
                moveToPoint(depositPos)
            end

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
                task.wait(0.4)
            end
        end

        if not State.Enabled then break end

        -- 2. Select closest eligible egg
        State.CurrentStatus = "Scanning for Available Eggs..."
        State.TargetEggName = "None"
        updateStatusUI()

        local available = getAvailableEggs()
        if #available == 0 then
            State.CurrentStatus = "No Eggs Found, Retrying..."
            updateStatusUI()
            task.wait(Config.ScanRetryDelay)
            continue
        end

        local target = available[1]
        State.TargetEggName = target.Name
        State.CurrentStatus = string.format("Moving to %s (%.0f studs)", target.Name, target.Distance)
        updateStatusUI()

        -- 3. Move player to target
        local arrived = moveToPoint(target.Part.Position)
        if not State.Enabled then break end

        if not target.Model.Parent or not target.Prompt.Parent or not target.Prompt.Enabled then
            State.CurrentStatus = "Egg Claimed / Despawned, Retrying..."
            updateStatusUI()
            task.wait(0.3)
            continue
        end

        -- 4. Trigger collection
        State.CurrentStatus = string.format("Collecting %s...", target.Name)
        updateStatusUI()

        local preCount = getCarriedCount()
        triggerPrompt(target.Prompt)

        -- 5. Confirm carried state
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
            task.wait(0.4)
            continue
        end

        -- 6. Navigate to deposit plot
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

        -- 7. Confirm deposit
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
            task.wait(0.3)
        end
    end

    State.CurrentStatus = "Stopped"
    State.TargetEggName = "None"
    updateStatusUI()
end

--------------------------------------------------------------------------------
-- WINDUI MODERN HUD CREATION
--------------------------------------------------------------------------------
-- Cleanup any older instances
pcall(function()
    if gethui then
        for _, c in ipairs(gethui():GetChildren()) do
            if string.find(c.Name, "Frost") or string.find(c.Name, "WindUI") then c:Destroy() end
        end
    end
    for _, c in ipairs(CoreGui:GetChildren()) do
        if string.find(c.Name, "Frost") or string.find(c.Name, "WindUI") then c:Destroy() end
    end
end)

local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

local Window = WindUI:CreateWindow({
    Title = "Frost Hub | Auto Collect",
    Icon = "snowflake",
    Author = "Prototyping & Testing Suite",
    Folder = "FrostHub",
    Size = UDim2.fromOffset(560, 420),
    MinSize = Vector2.new(480, 340),
    MaxSize = Vector2.new(800, 580),
    Transparent = true,
    Theme = "Dark",
    Resizable = true,
    SideBarWidth = 175,
    HideSearchBar = true,
})

--------------------------------------------------------------------------------
-- TAB 1: AUTO COLLECT
--------------------------------------------------------------------------------
local MainTab = Window:Tab({
    Title = "Auto Collect",
    Icon = "egg"
})

local MainSection = MainTab:Section({
    Title = "Automation Engine",
    Opened = true
})

local ToggleAuto = MainSection:Toggle({
    Title = "Auto Collect Eggs",
    Desc = "Automates scanning, approaching, collecting, and plot depositing",
    Value = false,
    Callback = function(state)
        State.Enabled = state
        if state then
            if State.CurrentTask then task.cancel(State.CurrentTask) end
            State.CurrentTask = task.spawn(runCollectionLoop)
            WindUI:Notify({
                Title = "Auto Collect Enabled",
                Content = "Engine active using " .. Config.MovementMode,
                Duration = 2.5,
                Icon = "play"
            })
        else
            if State.CurrentTask then
                task.cancel(State.CurrentTask)
                State.CurrentTask = nil
            end
            if State.ActiveTween then
                State.ActiveTween:Cancel()
                State.ActiveTween = nil
            end
            pcall(function() getHumanoid().WalkSpeed = 16 end)
            State.CurrentStatus = "Stopped"
            State.TargetEggName = "None"
            updateStatusUI()
            WindUI:Notify({
                Title = "Auto Collect Stopped",
                Content = "Movement and tasks cancelled.",
                Duration = 2,
                Icon = "square"
            })
        end
    end
})

local StatusParagraph = MainSection:Paragraph({
    Title = "Live Activity Status",
    Desc = "Status: Idle\nTarget: None\nEggs Collected: 0\nActive Engine: Walk (Pathfinding)"
})

updateStatusUI = function()
    pcall(function()
        StatusParagraph:SetDesc(string.format(
            "Status: %s\nTarget: %s\nEggs Collected: %d\nActive Engine: %s",
            State.CurrentStatus,
            State.TargetEggName,
            State.EggsCollected,
            Config.MovementMode
        ))
    end)
end

local ActionsSection = MainTab:Section({
    Title = "Manual Triggers",
    Opened = true
})

ActionsSection:Button({
    Title = "Deposit Carried Eggs",
    Desc = "Immediately moves to player plot to deposit any carried eggs",
    Callback = function()
        task.spawn(function()
            local depositPos = getDepositTargetPosition()
            if depositPos then
                WindUI:Notify({
                    Title = "Navigating to Plot",
                    Content = "Moving to your plot deposit area...",
                    Duration = 2,
                    Icon = "home"
                })
                moveToPoint(depositPos)
            end
        end)
    end
})

ActionsSection:Button({
    Title = "Reset Statistics",
    Desc = "Resets the session collected eggs counter to 0",
    Callback = function()
        State.EggsCollected = 0
        updateStatusUI()
        WindUI:Notify({
            Title = "Stats Reset",
            Content = "Collected egg counter reset to 0.",
            Duration = 2,
            Icon = "rotate-ccw"
        })
    end
})

--------------------------------------------------------------------------------
-- TAB 2: MOVEMENT ENGINE
--------------------------------------------------------------------------------
local MoveTab = Window:Tab({
    Title = "Movement",
    Icon = "zap"
})

local MoveSection = MoveTab:Section({
    Title = "Movement Systems",
    Opened = true
})

MoveSection:Dropdown({
    Title = "Movement Mode",
    Desc = "Choose between intelligent pathfinding, direct sprint, or smooth CFrame tween glide",
    Values = { "Walk (Pathfinding)", "Walk (Direct)", "Tween (Smooth)" },
    Value = "Walk (Pathfinding)",
    Callback = function(selected)
        Config.MovementMode = selected
        updateStatusUI()
        WindUI:Notify({
            Title = "Movement System Updated",
            Content = "Switched to " .. selected,
            Duration = 2,
            Icon = "settings-2"
        })
    end
})

local WalkSpeedSlider = MoveSection:Slider({
    Title = "Walk Speed",
    Desc = "Movement speed applied to Humanoid for Walk modes (1 to 400)",
    Value = {
        Min = 1,
        Max = 400,
        Default = 24
    },
    Step = 1,
    Callback = function(val)
        Config.WalkSpeed = val
        pcall(function()
            if State.Enabled and Config.MovementMode ~= "Tween (Smooth)" then
                getHumanoid().WalkSpeed = val
            end
        end)
    end
})

local TweenSpeedSlider = MoveSection:Slider({
    Title = "Tween Speed",
    Desc = "Gliding speed in studs per second for Tween mode (1 to 400)",
    Value = {
        Min = 1,
        Max = 400,
        Default = 85
    },
    Step = 1,
    Callback = function(val)
        Config.TweenSpeed = val
    end
})

local OptionsSection = MoveTab:Section({
    Title = "Movement Modifiers",
    Opened = true
})

OptionsSection:Toggle({
    Title = "Noclip During Tween",
    Desc = "Disables player collision during tweening to prevent snagging on walls/trees",
    Value = true,
    Callback = function(state)
        Config.NoclipOnTween = state
    end
})

OptionsSection:Toggle({
    Title = "Auto Jump Obstacles",
    Desc = "Automatically jumps when approaching hurdles or when stuck during walk",
    Value = true,
    Callback = function(state)
        Config.AutoJump = state
    end
})

--------------------------------------------------------------------------------
-- TAB 3: SETTINGS & HUD CUSTOMIZATION
--------------------------------------------------------------------------------
local SettingsTab = Window:Tab({
    Title = "Settings",
    Icon = "settings"
})

local AppearanceSection = SettingsTab:Section({
    Title = "Window Controls",
    Opened = true
})

AppearanceSection:Slider({
    Title = "HUD Scale",
    Desc = "Adjust size of the entire HUD (80% to 150%)",
    Value = {
        Min = 80,
        Max = 150,
        Default = 100
    },
    Step = 5,
    Callback = function(scalePercent)
        pcall(function()
            Window:SetUIScale(scalePercent / 100)
        end)
    end
})

AppearanceSection:Button({
    Title = "Center Window",
    Desc = "Re-centers the Frost Hub window on your screen",
    Callback = function()
        Window:SetToTheCenter()
    end
})

AppearanceSection:Button({
    Title = "Toggle Acrylic Blur",
    Desc = "Toggles background glassmorphism blur effect",
    Callback = function()
        pcall(function()
            WindUI:ToggleAcrylic(not WindUI:GetTransparency())
        end)
    end
})

local InfoSection = SettingsTab:Section({
    Title = "About Frost Hub",
    Opened = true
})

InfoSection:Paragraph({
    Title = "Frost Hub v2.0 - Automation Prototype",
    Desc = "Built with WindUI for ultra-smooth responsiveness.\nPress RightShift or RightControl to toggle the window."
})

-- Global Keybind to toggle HUD
UserInputService.InputBegan:Connect(function(input, processed)
    if not processed and (input.KeyCode == Enum.KeyCode.RightControl or input.KeyCode == Enum.KeyCode.RightShift) then
        Window:Toggle()
    end
end)

print("❄️ [Frost Hub] WindUI Multi-Engine Suite initialized.")
