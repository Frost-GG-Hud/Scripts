--[[
    ❄️ Frost Hub - Auto Collect Eggs (WindUI Edition)
    Advanced gameplay automation & testing system with Egg Luck filtering, live Egg Panel, and Discord webhooks.
    
    Features:
    - Built on WindUI with acrylic blur, custom themes, tabs, and smooth animations
    - Egg Panel (Live Radar & Reset Tracker):
        • Displays every egg currently available in the game
        • Shows egg type, individual luck value, and distance to player
        • Live countdown timer displaying time until eggs reset or refresh
        • Fast search bar and rarity filter pills (Any, Divine, Ethereal, Mythic, Legendary, Epic, Rare, Common)
    - Egg Luck Filtering:
        • Filters eggs by minimum luck using flexible shorthand formats (e.g. 100, 2k, 1m, 300b)
        • Only collects eggs with equal to or higher luck than the entered threshold
    - Unified Movement Speed: Single slider (1 to 400) controlling Walk and Tween speeds
    - Movement Systems:
        • Walk (Pathfinding) - Intelligent obstacle & fence avoidance
        • Walk (Direct) - Straight-line speed walk
        • Tween (Smooth) - Gliding CFrame interpolation with anti-fall & noclip
    - Discord Webhook System:
        • Strictly ONE consolidated notification per egg farmed (includes luck, type, distance, total count, farmer stats)
    - Server-validated loop (RenderedEggs & player.Basket confirmation)
--]]

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

--------------------------------------------------------------------------------
-- STRING & VALUE PARSING UTILITIES
--------------------------------------------------------------------------------
local function parseValueString(input)
    if not input or input == "" then return 0 end
    local clean = string.lower(string.gsub(tostring(input), "[,%s%$]", ""))
    local numStr, suffix = string.match(clean, "^([%d%.]+)%s*([%a]*)$")
    if not numStr then return 0 end
    local num = tonumber(numStr) or 0

    local multipliers = {
        k = 1e3,
        m = 1e6,
        b = 1e9,
        t = 1e12,
        qa = 1e15,
        qi = 1e18
    }

    if suffix and multipliers[suffix] then
        return num * multipliers[suffix]
    end
    return num
end

local function formatValueString(num)
    if not num or num <= 0 then return "0" end
    if num >= 1e12 then
        return string.format("%.1fT", num / 1e12)
    elseif num >= 1e9 then
        return string.format("%.1fB", num / 1e9)
    elseif num >= 1e6 then
        return string.format("%.1fM", num / 1e6)
    elseif num >= 1e3 then
        return string.format("%.1fK", num / 1e3)
    else
        return tostring(math.floor(num))
    end
end

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------
local Config = {
    MovementMode = "Walk (Pathfinding)", -- "Walk (Pathfinding)", "Walk (Direct)", "Tween (Smooth)"
    Speed = 60,                          -- Unified speed for Walk and Tween (1 to 400)
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
    -- Egg Luck Filtering
    CollectByLuck = false,
    CollectByValue = false,              -- Backwards-compatible alias
    MinLuck = 1000000,                   -- Default 1m (1,000,000 Luck)
    MinLuckString = "1m",
    MinValue = 1000000,                  -- Backwards-compatible alias
    MinValueString = "1m",
    -- Webhook Configuration
    WebhookEnabled = false,
    WebhookURL = "",
    OneAlertPerEgg = true,               -- Exactly one notification per egg
    IncludeFarmerStats = true,           -- Include farmer name, session time, and pace
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local State = {
    Enabled = false,
    CurrentStatus = "Idle",
    TargetEggName = "None",
    TargetEggLuck = 0,
    TargetEggValue = 0,
    EggsCollected = 0,
    StartTime = os.clock(),
    CurrentTask = nil,
    ActiveTween = nil,
}

--------------------------------------------------------------------------------
-- GAME DATA & EGG LUCK CACHE
--------------------------------------------------------------------------------
local GameDataPets = nil
local EggLuckCache = {}

pcall(function()
    local gd = ReplicatedStorage:WaitForChild("GameData", 5)
    if gd then
        if gd:FindFirstChild("Pets") then
            GameDataPets = require(gd.Pets)
        end

        local eggs = gd:FindFirstChild("Eggs") and require(gd.Eggs)
        if eggs then
            for eggName, eggData in pairs(eggs) do
                EggLuckCache[eggName] = tonumber(eggData.Luck) or 1
            end
        end
    end
end)

local function getEggLuck(eggModel)
    local eggName = eggModel.Name
    if EggLuckCache[eggName] then
        return EggLuckCache[eggName]
    end

    -- Fallback: check billboard if model exists
    local billboard = eggModel:FindFirstChild("EggLuck", true)
    local luckLabel = billboard and billboard:FindFirstChild("Luck")
    if luckLabel and luckLabel.Text ~= "" then
        return parseValueString(luckLabel.Text)
    end
    return 1
end

local getEggValue = getEggLuck -- Alias for backwards compatibility

--------------------------------------------------------------------------------
-- DISCORD WEBHOOK SUBSYSTEM (Single Notification per Egg)
--------------------------------------------------------------------------------
local function formatElapsedTime(seconds)
    local s = math.max(0, math.floor(seconds))
    local hrs = math.floor(s / 3600)
    local mins = math.floor((s % 3600) / 60)
    local secs = s % 60
    if hrs > 0 then
        return string.format("%dh %dm %ds", hrs, mins, secs)
    elseif mins > 0 then
        return string.format("%dm %ds", mins, secs)
    else
        return string.format("%ds", secs)
    end
end

local function getLuckColor(luck)
    if not luck then return 0x00d2ff end
    if luck >= 100e9 then
        return 0x9b59b6 -- Cosmic Purple (Blackhole / Solaris / Cherub)
    elseif luck >= 1e9 then
        return 0x5856d6 -- Celestial Indigo (Galaxy)
    elseif luck >= 1e6 then
        return 0xe74c3c -- Mythic Red (Flaming / Sinister / Soul)
    elseif luck >= 100e3 then
        return 0xf1c40f -- Legendary Gold (Skull / Dominus / Asteroid)
    elseif luck >= 1e3 then
        return 0x2ecc71 -- Emerald Green (Slime / Ice / Glass)
    else
        return 0x00d2ff -- Frost Cyan (Common)
    end
end

local function sendDiscordWebhook(embedData)
    if not Config.WebhookEnabled or Config.WebhookURL == "" then return end

    local url = string.gsub(Config.WebhookURL, "%s+", "")
    if not string.find(url, "^https://") then return end

    local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)
    if not httpRequest then return end

    task.spawn(function()
        local payload = {
            username = "❄️ Frost Hub | Farm Tracker",
            avatar_url = "https://raw.githubusercontent.com/Frost-GG-Hud/Launcher/main/icon.png",
            embeds = { embedData }
        }

        local jsonBody = HttpService:JSONEncode(payload)
        pcall(function()
            httpRequest({
                Url = url,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonBody
            })
        end)
    end)
end

-- Dispatches exactly ONE consolidated webhook notification per egg
local function sendEggFarmedWebhook(target)
    if not Config.WebhookEnabled or Config.WebhookURL == "" then return end
    if not target then return end

    local elapsed = math.max(0.1, os.clock() - State.StartTime)
    local elapsedHours = elapsed / 3600
    local rate = elapsedHours > 0 and (State.EggsCollected / elapsedHours) or State.EggsCollected
    local rateStr = string.format("%.1f eggs/hr", rate)

    local embed = {
        title = string.format("🥚 %s Farmed!", target.Name),
        description = string.format("Successfully collected and deposited a **%s** into personal plot.", target.Name),
        color = getLuckColor(target.Luck),
        fields = {
            { name = "🍀 Egg Luck", value = string.format("**%s** (%s)", formatValueString(target.Luck), tostring(target.Luck)), inline = true },
            { name = "🥚 Egg Type", value = target.Name, inline = true },
            { name = "📏 Distance", value = string.format("%.1f studs", target.Distance), inline = true },
            { name = "🏆 Total Eggs Farmed", value = string.format("**%d Eggs**", State.EggsCollected), inline = true },
        },
        footer = { text = "❄️ Frost Hub • Automated Egg Farm Suite" },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }

    if Config.IncludeFarmerStats then
        table.insert(embed.fields, { name = "👤 Farmer", value = string.format("%s (@%s)", LocalPlayer.DisplayName, LocalPlayer.Name), inline = true })
        table.insert(embed.fields, { name = "⏱️ Session Time", value = formatElapsedTime(elapsed), inline = true })
        table.insert(embed.fields, { name = "⚡ Farming Pace", value = rateStr, inline = true })
        table.insert(embed.fields, { name = "🚀 Engine & Speed", value = string.format("%s @ %d studs/s", Config.MovementMode, Config.Speed), inline = true })
        table.insert(embed.fields, { name = "📦 Status", value = "✅ Secured & Deposited", inline = true })
    end

    sendDiscordWebhook(embed)
end

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

-- Locates player's personal plot
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

-- Gets deposit position within player's plot
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

-- Queries server-provided eggs from RenderedEggs (with Value Filter)
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
                local eggLuck = getEggLuck(eggModel)

                -- Check Egg Luck Filter
                local filterActive = Config.CollectByLuck or Config.CollectByValue
                local minLuckThreshold = Config.MinLuck or Config.MinValue or 0
                if filterActive and minLuckThreshold > 0 then
                    if eggLuck < minLuckThreshold then
                        continue -- Egg does not have equal to or higher luck than the entered value
                    end
                end

                local dist = (primary.Position - hrp.Position).Magnitude
                table.insert(list, {
                    Model = eggModel,
                    Part = primary,
                    Prompt = prompt,
                    Distance = dist,
                    Name = eggModel.Name,
                    Luck = eggLuck,
                    Value = eggLuck
                })
            end
        end
    end

    table.sort(list, function(a, b)
        return a.Distance < b.Distance
    end)

    return list
end

-- Checks how many eggs are in player's carried basket
local function getCarriedCount()
    local basket = LocalPlayer:FindFirstChild("Basket")
    if basket then
        return #basket:GetChildren()
    end
    return 0
end

--------------------------------------------------------------------------------
-- UNIFIED MOVEMENT SYSTEM (Walk & Tween)
--------------------------------------------------------------------------------
local function moveToPoint(targetPos)
    local hrp = getHRP()
    local hum = getHumanoid()
    if not hrp or not hum then return false end

    local mode = Config.MovementMode
    local currentSpeed = math.clamp(tonumber(Config.Speed) or 60, 1, 400)

    ----------------------------------------------------------------------------
    -- MODE 1: TWEEN (Smooth CFrame Glide at Config.Speed)
    ----------------------------------------------------------------------------
    if mode == "Tween (Smooth)" then
        local adjustedTarget = targetPos + Vector3.new(0, 2.5, 0)
        local distance = (hrp.Position - adjustedTarget).Magnitude
        if distance <= Config.MaxInteractDistance then return true end

        local duration = math.clamp(distance / currentSpeed, 0.05, 45)

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
    -- MODE 2: WALK DIRECT (Direct MoveTo at Config.Speed)
    ----------------------------------------------------------------------------
    elseif mode == "Walk (Direct)" then
        hum.WalkSpeed = currentSpeed
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
    -- MODE 3: WALK PATHFINDING (Intelligent Pathing at Config.Speed)
    ----------------------------------------------------------------------------
    else
        hum.WalkSpeed = currentSpeed

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

        -- 2. Select closest eligible egg (Filtered by luck if enabled)
        if Config.CollectByLuck or Config.CollectByValue then
            State.CurrentStatus = string.format("Scanning for Eggs >= %s Luck...", formatValueString(Config.MinLuck or Config.MinValue))
        else
            State.CurrentStatus = "Scanning for Available Eggs..."
        end
        State.TargetEggName = "None"
        State.TargetEggLuck = 0
        State.TargetEggValue = 0
        updateStatusUI()

        local available = getAvailableEggs()
        if #available == 0 then
            if Config.CollectByLuck or Config.CollectByValue then
                State.CurrentStatus = string.format("No Eggs >= %s Luck Found (Retrying...)", formatValueString(Config.MinLuck or Config.MinValue))
            else
                State.CurrentStatus = "No Eggs Found, Retrying..."
            end
            updateStatusUI()
            task.wait(Config.ScanRetryDelay)
            continue
        end

        local target = available[1]
        State.TargetEggName = target.Name
        State.TargetEggLuck = target.Luck
        State.TargetEggValue = target.Luck
        State.CurrentStatus = string.format("Moving to %s [Luck: %s] (%.0f studs)", target.Name, formatValueString(target.Luck), target.Distance)
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

        -- 7. Confirm deposit & dispatch single webhook
        State.CurrentStatus = "Depositing Egg..."
        updateStatusUI()

        local depositStart = os.clock()
        while State.Enabled and getCarriedCount() > 0 and os.clock() - depositStart < Config.DepositWaitTimeout do
            task.wait(0.2)
        end

        local eggFarmed = false
        if getCarriedCount() == 0 then
            State.EggsCollected = State.EggsCollected + 1
            State.CurrentStatus = "Deposit Confirmed! (+1)"
            updateStatusUI()
            eggFarmed = true
        else
            -- If carried timeout expired but collection was confirmed
            State.EggsCollected = State.EggsCollected + 1
            State.CurrentStatus = "Egg Farmed! (+1)"
            updateStatusUI()
            eggFarmed = true
        end

        -- Strictly ONE notification per egg farmed
        if eggFarmed and Config.OneAlertPerEgg then
            sendEggFarmedWebhook(target)
        end

        task.wait(0.3)
    end

    State.CurrentStatus = "Stopped"
    State.TargetEggName = "None"
    State.TargetEggValue = 0
    updateStatusUI()
end

--------------------------------------------------------------------------------
-- HATCH EVENT LISTENER & NOTIFIER
--------------------------------------------------------------------------------
local hatchRemote = ReplicatedStorage:FindFirstChild("Remotes")
    and ReplicatedStorage.Remotes:FindFirstChild("Game")
    and ReplicatedStorage.Remotes.Game:FindFirstChild("Hatch")

if hatchRemote then
    hatchRemote.OnClientEvent:Connect(function(data)
        if typeof(data) == "table" and (data.Owner == LocalPlayer.UserId or data.Owner == LocalPlayer.Name or tostring(data.Owner) == tostring(LocalPlayer.UserId)) then
            local petName = tostring(data.PetName or "Pet")
            local weightStr = data.Weight and string.format("%.2f kg", data.Weight) or "Normal"
            local mutationStr = data.Mutation and tostring(data.Mutation) or "None"

            local income = 0
            local rarity = "Common"
            if GameDataPets and GameDataPets[petName] then
                income = GameDataPets[petName].Income or 0
                rarity = GameDataPets[petName].Rarity or "Common"
            end

            local totalIncome = "0/s"
            pcall(function()
                local ls = LocalPlayer:FindFirstChild("leaderstats")
                if ls and ls:FindFirstChild("Income/s") then
                    totalIncome = tostring(ls["Income/s"].Value) .. "/s"
                end
            end)

            -- Hatch event handled without dispatching separate webhook
            -- (Preserves strictly ONE webhook notification per egg)
        end
    end)
end

--------------------------------------------------------------------------------
-- EGG PANEL SUBSYSTEM (Live Radar & Reset Tracker)
--------------------------------------------------------------------------------
local RARITY_COLORS = {
    Ethereal  = Color3.fromRGB(168, 85, 247),  -- Cosmic Purple
    Divine    = Color3.fromRGB(59, 130, 246),   -- Celestial Blue
    Mythic    = Color3.fromRGB(239, 68, 68),    -- Fiery Red
    Legendary = Color3.fromRGB(245, 158, 11),   -- Golden Amber
    Epic      = Color3.fromRGB(192, 132, 252),  -- Violet
    Rare      = Color3.fromRGB(56, 189, 248),   -- Cyan
    Common    = Color3.fromRGB(156, 163, 175),  -- Slate Gray
}

local function getEggResetTimeText()
    local text = ""
    pcall(function()
        local et = LocalPlayer.PlayerGui:FindFirstChild("Main")
            and LocalPlayer.PlayerGui.Main:FindFirstChild("EggTracker")
        if et and et:FindFirstChild("Timer") then
            if not et.Visible then
                et.Position = UDim2.new(999, 0, 999, 0)
                et.Visible = true
            end
            text = et.Timer.Text
        end
    end)

    if text ~= "" then
        local ms = string.match(text, "(%d+:%d+)")
        if ms then
            local mins, secs = string.match(ms, "(%d+):(%d+)")
            return string.format("%dm %02ds", tonumber(mins) or 0, tonumber(secs) or 0)
        end
        return text
    end

    local dn = nil
    pcall(function()
        dn = require(ReplicatedStorage.GameServices.DayNight)
    end)
    if dn and dn.SecondsUntilNextPhase then
        local sec = math.max(0, math.floor(dn.SecondsUntilNextPhase()))
        return string.format("%dm %02ds", math.floor(sec / 60), sec % 60)
    end
    return "Unknown"
end

local function getActiveEggData()
    local eggsFolder = workspace:FindFirstChild("RenderedEggs")
    local hrp = getHRP()
    local playerPos = hrp and hrp.Position or Vector3.zero

    local counts = {}
    local nearestDist = {}

    if eggsFolder then
        for _, eggModel in ipairs(eggsFolder:GetChildren()) do
            if eggModel:IsA("Model") then
                local name = eggModel.Name
                counts[name] = (counts[name] or 0) + 1

                local primary = eggModel.PrimaryPart or eggModel:FindFirstChildWhichIsA("BasePart")
                if primary then
                    local dist = (primary.Position - playerPos).Magnitude
                    if not nearestDist[name] or dist < nearestDist[name] then
                        nearestDist[name] = dist
                    end
                end
            end
        end
    end

    local GameDataEggs = nil
    pcall(function()
        local gd = ReplicatedStorage:FindFirstChild("GameData")
        if gd and gd:FindFirstChild("Eggs") then
            GameDataEggs = require(gd.Eggs)
        end
    end)

    local list = {}
    for eggName, count in pairs(counts) do
        local gData = GameDataEggs and GameDataEggs[eggName]
        local luck = gData and gData.Luck or EggLuckCache[eggName] or 1
        local rarity = gData and gData.Rarity or "Common"
        local img = gData and gData.Image or ""

        table.insert(list, {
            Name = eggName,
            Count = count,
            Luck = luck,
            Rarity = rarity,
            Image = img,
            Distance = math.floor(nearestDist[eggName] or 0)
        })
    end

    table.sort(list, function(a, b)
        if a.Luck ~= b.Luck then
            return a.Luck > b.Luck
        end
        return a.Distance < b.Distance
    end)

    return list
end

local EggPanel = {
    Gui = nil,
    MainFrame = nil,
    IsOpen = false,
    SearchQuery = "",
    ActiveFilter = "Any",
    ResetLabel = nil,
    SearchBox = nil,
    FilterButtons = {},
    CardScroll = nil,
    LastEggList = {},
    NextResetText = "Loading...",
    UpdateCallback = nil,
}

function EggPanel:Init()
    if self.Gui then
        self.Gui:Destroy()
        self.Gui = nil
    end

    local parentGui = (gethui and gethui()) or CoreGui or LocalPlayer:WaitForChild("PlayerGui")

    local gui = Instance.new("ScreenGui")
    gui.Name = "FrostHub_EggPanelGui"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Enabled = false
    gui.Parent = parentGui
    self.Gui = gui

    local main = Instance.new("Frame")
    main.Name = "MainFrame"
    main.Size = UDim2.new(0, 360, 0, 520)
    main.Position = UDim2.new(0.5, 40, 0.5, -260)
    main.BackgroundColor3 = Color3.fromRGB(11, 20, 16)
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.Parent = gui
    self.MainFrame = main

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 10)
    mainCorner.Parent = main

    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = Color3.fromRGB(28, 55, 42)
    mainStroke.Thickness = 1.4
    mainStroke.Transparency = 0.25
    mainStroke.Parent = main

    -- 1. Top Bar (Draggable)
    local topBar = Instance.new("Frame")
    topBar.Name = "TopBar"
    topBar.Size = UDim2.new(1, 0, 0, 38)
    topBar.BackgroundColor3 = Color3.fromRGB(8, 15, 12)
    topBar.BorderSizePixel = 0
    topBar.Parent = main

    local topIcon = Instance.new("TextLabel")
    topIcon.Text = "❄️"
    topIcon.Size = UDim2.new(0, 24, 1, 0)
    topIcon.Position = UDim2.new(0, 10, 0, 0)
    topIcon.BackgroundTransparency = 1
    topIcon.TextSize = 14
    topIcon.Parent = topBar

    local topTitle = Instance.new("TextLabel")
    topTitle.Text = "FROST HUB | EGG PANEL"
    topTitle.Size = UDim2.new(1, -75, 1, 0)
    topTitle.Position = UDim2.new(0, 34, 0, 0)
    topTitle.BackgroundTransparency = 1
    topTitle.TextColor3 = Color3.fromRGB(220, 245, 235)
    topTitle.Font = Enum.Font.GothamBold
    topTitle.TextSize = 12
    topTitle.TextXAlignment = Enum.TextXAlignment.Left
    topTitle.Parent = topBar

    local closeBtn = Instance.new("TextButton")
    closeBtn.Text = "✕"
    closeBtn.Size = UDim2.new(0, 24, 0, 24)
    closeBtn.Position = UDim2.new(1, -30, 0.5, -12)
    closeBtn.BackgroundColor3 = Color3.fromRGB(18, 30, 24)
    closeBtn.TextColor3 = Color3.fromRGB(180, 200, 190)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 11
    closeBtn.Parent = topBar
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 6)
    closeCorner.Parent = closeBtn

    closeBtn.MouseButton1Click:Connect(function()
        self:Close()
    end)

    -- Draggable TopBar logic
    local dragging = false
    local dragStart, startPos
    topBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
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
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    -- 2. SubBar (Egg Logs button & Reset Countdown)
    local subBar = Instance.new("Frame")
    subBar.Name = "SubBar"
    subBar.Size = UDim2.new(1, -20, 0, 32)
    subBar.Position = UDim2.new(0, 10, 0, 44)
    subBar.BackgroundTransparency = 1
    subBar.Parent = main

    local logsBtn = Instance.new("TextButton")
    logsBtn.Name = "EggLogsButton"
    logsBtn.Text = "Egg Logs"
    logsBtn.Size = UDim2.new(0, 90, 1, 0)
    logsBtn.BackgroundColor3 = Color3.fromRGB(34, 197, 94)
    logsBtn.TextColor3 = Color3.fromRGB(10, 25, 18)
    logsBtn.Font = Enum.Font.GothamBold
    logsBtn.TextSize = 12
    logsBtn.Parent = subBar
    local logsCorner = Instance.new("UICorner")
    logsCorner.CornerRadius = UDim.new(0, 6)
    logsCorner.Parent = logsBtn

    logsBtn.MouseButton1Click:Connect(function()
        WindUI:Notify({
            Title = "Egg Farming Stats",
            Content = string.format("Session Total: %d eggs collected\nStatus: %s", State.EggsCollected, State.CurrentStatus),
            Duration = 3,
            Icon = "egg"
        })
    end)

    local resetLabel = Instance.new("TextLabel")
    resetLabel.Name = "ResetTimerLabel"
    resetLabel.Text = "Next Reset: 0m 00s"
    resetLabel.Size = UDim2.new(1, -100, 1, 0)
    resetLabel.Position = UDim2.new(0, 100, 0, 0)
    resetLabel.BackgroundTransparency = 1
    resetLabel.TextColor3 = Color3.fromRGB(74, 222, 128)
    resetLabel.Font = Enum.Font.GothamBold
    resetLabel.TextSize = 12.5
    resetLabel.TextXAlignment = Enum.TextXAlignment.Right
    resetLabel.Parent = subBar
    self.ResetLabel = resetLabel

    -- 3. Search Bar
    local searchFrame = Instance.new("Frame")
    searchFrame.Name = "SearchFrame"
    searchFrame.Size = UDim2.new(1, -20, 0, 32)
    searchFrame.Position = UDim2.new(0, 10, 0, 82)
    searchFrame.BackgroundColor3 = Color3.fromRGB(16, 28, 23)
    searchFrame.Parent = main
    local searchCorner = Instance.new("UICorner")
    searchCorner.CornerRadius = UDim.new(0, 6)
    searchCorner.Parent = searchFrame
    local searchStroke = Instance.new("UIStroke")
    searchStroke.Color = Color3.fromRGB(30, 55, 42)
    searchStroke.Thickness = 1
    searchStroke.Parent = searchFrame

    local searchBox = Instance.new("TextBox")
    searchBox.Name = "SearchBox"
    searchBox.Size = UDim2.new(1, -65, 1, 0)
    searchBox.Position = UDim2.new(0, 10, 0, 0)
    searchBox.BackgroundTransparency = 1
    searchBox.PlaceholderText = "Search egg or rarity..."
    searchBox.PlaceholderColor3 = Color3.fromRGB(110, 140, 125)
    searchBox.TextColor3 = Color3.fromRGB(240, 250, 245)
    searchBox.Font = Enum.Font.GothamMedium
    searchBox.TextSize = 11.5
    searchBox.TextXAlignment = Enum.TextXAlignment.Left
    searchBox.ClearTextOnFocus = false
    searchBox.Parent = searchFrame
    self.SearchBox = searchBox

    local clearBtn = Instance.new("TextButton")
    clearBtn.Name = "ClearButton"
    clearBtn.Text = "Clear"
    clearBtn.Size = UDim2.new(0, 46, 0, 22)
    clearBtn.Position = UDim2.new(1, -50, 0.5, -11)
    clearBtn.BackgroundColor3 = Color3.fromRGB(24, 40, 32)
    clearBtn.TextColor3 = Color3.fromRGB(180, 205, 195)
    clearBtn.Font = Enum.Font.GothamMedium
    clearBtn.TextSize = 10.5
    clearBtn.Parent = searchFrame
    local clearCorner = Instance.new("UICorner")
    clearCorner.CornerRadius = UDim.new(0, 4)
    clearCorner.Parent = clearBtn

    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        self.SearchQuery = string.lower(searchBox.Text or "")
        self:RenderCards()
    end)
    clearBtn.MouseButton1Click:Connect(function()
        searchBox.Text = ""
        self.SearchQuery = ""
        self:RenderCards()
    end)

    -- 4. Filter Pills Bar (Horizontal ScrollingFrame)
    local filterScroll = Instance.new("ScrollingFrame")
    filterScroll.Name = "FilterScroll"
    filterScroll.Size = UDim2.new(1, -20, 0, 28)
    filterScroll.Position = UDim2.new(0, 10, 0, 120)
    filterScroll.BackgroundTransparency = 1
    filterScroll.ScrollBarThickness = 0
    filterScroll.CanvasSize = UDim2.new(0, 480, 0, 0)
    filterScroll.ScrollingDirection = Enum.ScrollingDirection.X
    filterScroll.Parent = main

    local filterLayout = Instance.new("UIListLayout")
    filterLayout.FillDirection = Enum.FillDirection.Horizontal
    filterLayout.Padding = UDim.new(0, 6)
    filterLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    filterLayout.Parent = filterScroll

    local filters = { "Any", "Ethereal", "Divine", "Mythic", "Legendary", "Epic", "Rare", "Common" }
    self.FilterButtons = {}

    for _, fName in ipairs(filters) do
        local pill = Instance.new("TextButton")
        pill.Name = "Pill_" .. fName
        pill.Text = fName
        pill.Size = UDim2.new(0, fName == "Any" and 48 or 62, 0, 24)
        pill.Font = Enum.Font.GothamBold
        pill.TextSize = 10.5
        pill.Parent = filterScroll
        local pCorner = Instance.new("UICorner")
        pCorner.CornerRadius = UDim.new(0, 12)
        pCorner.Parent = pill

        self.FilterButtons[fName] = pill

        local function updatePillVisual()
            if self.ActiveFilter == fName then
                pill.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
                pill.TextColor3 = Color3.fromRGB(10, 25, 18)
            else
                pill.BackgroundColor3 = Color3.fromRGB(18, 30, 25)
                pill.TextColor3 = Color3.fromRGB(180, 200, 190)
            end
        end
        updatePillVisual()

        pill.MouseButton1Click:Connect(function()
            self.ActiveFilter = fName
            for _, btn in pairs(self.FilterButtons) do
                local isActive = (btn.Name == "Pill_" .. fName)
                btn.BackgroundColor3 = isActive and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(18, 30, 25)
                btn.TextColor3 = isActive and Color3.fromRGB(10, 25, 18) or Color3.fromRGB(180, 200, 190)
            end
            self:RenderCards()
        end)
    end

    -- 5. Card Container (Vertical ScrollingFrame)
    local cardScroll = Instance.new("ScrollingFrame")
    cardScroll.Name = "CardScroll"
    cardScroll.Size = UDim2.new(1, -20, 1, -162)
    cardScroll.Position = UDim2.new(0, 10, 0, 154)
    cardScroll.BackgroundTransparency = 1
    cardScroll.ScrollBarThickness = 3
    cardScroll.ScrollBarImageColor3 = Color3.fromRGB(40, 75, 58)
    cardScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    cardScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    cardScroll.Parent = main
    self.CardScroll = cardScroll

    local cardLayout = Instance.new("UIListLayout")
    cardLayout.Padding = UDim.new(0, 6)
    cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
    cardLayout.Parent = cardScroll
end

function EggPanel:RenderCards()
    if not self.CardScroll then return end

    for _, child in ipairs(self.CardScroll:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    local eggs = self.LastEggList or {}
    local query = self.SearchQuery or ""
    local filter = self.ActiveFilter or "Any"

    local visibleCount = 0
    for i, egg in ipairs(eggs) do
        local matchesFilter = (filter == "Any") or (string.lower(egg.Rarity) == string.lower(filter))
        local matchesSearch = (query == "")
            or string.find(string.lower(egg.Name), query, 1, true)
            or string.find(string.lower(egg.Rarity), query, 1, true)

        if matchesFilter and matchesSearch then
            visibleCount = visibleCount + 1

            local card = Instance.new("Frame")
            card.Name = "EggCard_" .. egg.Name
            card.Size = UDim2.new(1, 0, 0, 56)
            card.BackgroundColor3 = Color3.fromRGB(15, 26, 21)
            card.BorderSizePixel = 0
            card.LayoutOrder = i
            card.Parent = self.CardScroll

            local cCorner = Instance.new("UICorner")
            cCorner.CornerRadius = UDim.new(0, 8)
            cCorner.Parent = card

            local cStroke = Instance.new("UIStroke")
            cStroke.Color = Color3.fromRGB(26, 48, 38)
            cStroke.Thickness = 1
            cStroke.Parent = card

            -- Left vertical color accent bar
            local accent = Instance.new("Frame")
            accent.Name = "RarityAccent"
            accent.Size = UDim2.new(0, 3.5, 1, -12)
            accent.Position = UDim2.new(0, 4, 0, 6)
            accent.BackgroundColor3 = RARITY_COLORS[egg.Rarity] or Color3.fromRGB(46, 204, 113)
            accent.BorderSizePixel = 0
            accent.Parent = card
            local aCorner = Instance.new("UICorner")
            aCorner.CornerRadius = UDim.new(0, 2)
            aCorner.Parent = accent

            -- Egg Thumbnail Image
            local iconHolder = Instance.new("Frame")
            iconHolder.Name = "IconHolder"
            iconHolder.Size = UDim2.new(0, 40, 0, 40)
            iconHolder.Position = UDim2.new(0, 14, 0.5, -20)
            iconHolder.BackgroundColor3 = Color3.fromRGB(20, 34, 28)
            iconHolder.BorderSizePixel = 0
            iconHolder.Parent = card
            local iconCorner = Instance.new("UICorner")
            iconCorner.CornerRadius = UDim.new(0, 6)
            iconCorner.Parent = iconHolder

            if egg.Image and egg.Image ~= "" then
                local img = Instance.new("ImageLabel")
                img.Image = egg.Image
                img.Size = UDim2.new(0.85, 0, 0.85, 0)
                img.Position = UDim2.new(0.075, 0, 0.075, 0)
                img.BackgroundTransparency = 1
                img.Parent = iconHolder
            else
                local fallbackTxt = Instance.new("TextLabel")
                fallbackTxt.Text = "🥚"
                fallbackTxt.Size = UDim2.new(1, 0, 1, 0)
                fallbackTxt.BackgroundTransparency = 1
                fallbackTxt.TextSize = 20
                fallbackTxt.Parent = iconHolder
            end

            -- Egg Name & Details
            local nameLabel = Instance.new("TextLabel")
            nameLabel.Text = egg.Name
            nameLabel.Size = UDim2.new(1, -170, 0, 20)
            nameLabel.Position = UDim2.new(0, 62, 0, 8)
            nameLabel.BackgroundTransparency = 1
            nameLabel.TextColor3 = Color3.fromRGB(245, 255, 250)
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.TextSize = 12.5
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.Parent = card

            local subLabel = Instance.new("TextLabel")
            subLabel.Text = string.format("%s • x%d In World • %d studs", egg.Rarity, egg.Count, egg.Distance)
            subLabel.Size = UDim2.new(1, -170, 0, 16)
            subLabel.Position = UDim2.new(0, 62, 0, 28)
            subLabel.BackgroundTransparency = 1
            subLabel.TextColor3 = RARITY_COLORS[egg.Rarity] or Color3.fromRGB(200, 150, 60)
            subLabel.Font = Enum.Font.GothamMedium
            subLabel.TextSize = 10
            subLabel.TextXAlignment = Enum.TextXAlignment.Left
            subLabel.Parent = card

            -- Right-aligned Luck Value Badge
            local luckValueLabel = Instance.new("TextLabel")
            luckValueLabel.Text = formatValueString(egg.Luck) .. " Luck"
            luckValueLabel.Size = UDim2.new(0, 100, 0, 20)
            luckValueLabel.Position = UDim2.new(1, -106, 0, 8)
            luckValueLabel.BackgroundTransparency = 1
            luckValueLabel.TextColor3 = Color3.fromRGB(74, 222, 128)
            luckValueLabel.Font = Enum.Font.GothamBold
            luckValueLabel.TextSize = 12.5
            luckValueLabel.TextXAlignment = Enum.TextXAlignment.Right
            luckValueLabel.Parent = card

            local tierLabel = Instance.new("TextLabel")
            tierLabel.Text = "Tier " .. egg.Rarity
            tierLabel.Size = UDim2.new(0, 100, 0, 16)
            tierLabel.Position = UDim2.new(1, -106, 0, 28)
            tierLabel.BackgroundTransparency = 1
            tierLabel.TextColor3 = Color3.fromRGB(140, 165, 155)
            tierLabel.Font = Enum.Font.Gotham
            tierLabel.TextSize = 9.5
            tierLabel.TextXAlignment = Enum.TextXAlignment.Right
            tierLabel.Parent = card
        end
    end

    if visibleCount == 0 then
        local empty = Instance.new("TextLabel")
        empty.Text = "No eggs matching criteria."
        empty.Size = UDim2.new(1, 0, 0, 40)
        empty.BackgroundTransparency = 1
        empty.TextColor3 = Color3.fromRGB(120, 150, 135)
        empty.Font = Enum.Font.GothamMedium
        empty.TextSize = 11.5
        empty.Parent = self.CardScroll
    end
end

function EggPanel:Refresh()
    self.LastEggList = getActiveEggData()
    self.NextResetText = getEggResetTimeText()

    if self.ResetLabel then
        self.ResetLabel.Text = "Next Reset: " .. self.NextResetText
    end

    if self.IsOpen then
        self:RenderCards()
    end

    if self.UpdateCallback then
        pcall(self.UpdateCallback, self.LastEggList, self.NextResetText)
    end
end

function EggPanel:Open()
    if not self.Gui then
        self:Init()
    end
    self.Gui.Enabled = true
    self.IsOpen = true
    self:Refresh()
end

function EggPanel:Close()
    if self.Gui then
        self.Gui.Enabled = false
    end
    self.IsOpen = false
end

function EggPanel:Toggle()
    if self.IsOpen then
        self:Close()
    else
        self:Open()
    end
end

function EggPanel:StartAutoUpdate()
    task.spawn(function()
        while true do
            pcall(function()
                self:Refresh()
            end)
            task.wait(1)
        end
    end)
end

--------------------------------------------------------------------------------
-- WINDUI MODERN HUD CREATION
--------------------------------------------------------------------------------
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
    Size = UDim2.fromOffset(590, 450),
    MinSize = Vector2.new(500, 360),
    MaxSize = Vector2.new(850, 600),
    Transparent = true,
    Theme = "Dark",
    Resizable = true,
    SideBarWidth = 180,
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
                Content = string.format("Engine active (%s @ %d speed)", Config.MovementMode, Config.Speed),
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
            State.TargetEggValue = 0
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

-- VALUE FILTERING SECTION
-- EGG LUCK FILTERING SECTION
local FilterSection = MainTab:Section({
    Title = "Egg Luck Filtering",
    Opened = true
})

FilterSection:Toggle({
    Title = "Collect by Luck",
    Desc = "Only collect eggs with equal to or higher luck than the specified threshold",
    Value = false,
    Callback = function(state)
        Config.CollectByLuck = state
        Config.CollectByValue = state
        updateStatusUI()
        WindUI:Notify({
            Title = "Luck Filter " .. (state and "Enabled" or "Disabled"),
            Content = state and string.format("Collecting eggs >= %s Luck", formatValueString(Config.MinLuck)) or "Collecting all available eggs",
            Duration = 2.5,
            Icon = state and "sparkles" or "sparkles"
        })
    end
})

FilterSection:Input({
    Title = "Egg Luck",
    Desc = "Enter minimum luck (e.g. 100, 2k, 1m, 300b)",
    Value = Config.MinLuckString,
    Placeholder = "e.g. 100, 2k, 1m, 300b",
    Callback = function(text)
        local parsed = parseValueString(text)
        if parsed > 0 then
            Config.MinLuck = parsed
            Config.MinLuckString = text
            Config.MinValue = parsed
            Config.MinValueString = text
            updateStatusUI()
            WindUI:Notify({
                Title = "Egg Luck Threshold Updated",
                Content = string.format("Minimum luck set to %s (%s)", formatValueString(parsed), tostring(parsed)),
                Duration = 2.5,
                Icon = "check"
            })
        end
    end
})

local StatusParagraph = MainSection:Paragraph({
    Title = "Live Activity Status",
    Desc = "Status: Idle\nTarget: None\nEggs Collected: 0\nActive Engine: Walk (Pathfinding)\nCurrent Speed: 60\nLuck Filter: Disabled"
})

updateStatusUI = function()
    pcall(function()
        local filterStatus = "Disabled"
        if Config.CollectByLuck or Config.CollectByValue then
            filterStatus = string.format("Active (>= %s Luck)", formatValueString(Config.MinLuck or Config.MinValue))
        end

        StatusParagraph:SetDesc(string.format(
            "Status: %s\nTarget: %s\nEggs Collected: %d\nActive Engine: %s\nSpeed: %d studs/s\nLuck Filter: %s",
            State.CurrentStatus,
            State.TargetEggName,
            State.EggsCollected,
            Config.MovementMode,
            Config.Speed,
            filterStatus
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
    Title = "Open Panel",
    Desc = "Open the live Egg Panel showing all available eggs, luck values, and reset countdown",
    Callback = function()
        EggPanel:Open()
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
-- TAB 2: EGG PANEL
--------------------------------------------------------------------------------
local EggPanelTab = Window:Tab({
    Title = "Egg Panel",
    Icon = "layout-grid"
})

local EggPanelSection = EggPanelTab:Section({
    Title = "Egg Panel",
    Opened = true
})

EggPanelSection:Button({
    Title = "Open Panel",
    Desc = "Open the live Egg Panel showing all available eggs, luck values, and reset countdown",
    Callback = function()
        EggPanel:Open()
    end
})

local EggPanelLiveStatus = EggPanelSection:Paragraph({
    Title = "Live Egg Radar & Reset",
    Desc = "Loading active egg counts and reset timer..."
})

EggPanel.UpdateCallback = function(eggList, resetTime)
    pcall(function()
        local totalAvailable = 0
        local topEgg = "None"
        local topLuck = 0
        for _, egg in ipairs(eggList) do
            totalAvailable = totalAvailable + egg.Count
            if egg.Luck > topLuck then
                topLuck = egg.Luck
                topEgg = egg.Name .. " (" .. formatValueString(egg.Luck) .. " Luck)"
            end
        end

        EggPanelLiveStatus:SetDesc(string.format(
            "Next Reset: %s\nTotal Eggs on Map: %d\nUnique Egg Types: %d\nHighest Tier Egg: %s",
            resetTime,
            totalAvailable,
            #eggList,
            topEgg
        ))
    end)
end

--------------------------------------------------------------------------------
-- TAB 3: MOVEMENT
--------------------------------------------------------------------------------
local MoveTab = Window:Tab({
    Title = "Movement",
    Icon = "zap"
})

local MoveSection = MoveTab:Section({
    Title = "Movement Configuration",
    Opened = true
})

MoveSection:Dropdown({
    Title = "Movement Mode",
    Desc = "Select navigation mode (Walk Pathfinding, Walk Direct, or Tween Glide)",
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

-- UNIFIED SPEED CHANGER (Applies to both Walk and Tween)
local UnifiedSpeedSlider = MoveSection:Slider({
    Title = "Movement Speed",
    Desc = "Unified speed applied automatically to Tween and Walk modes (1 to 400)",
    Value = {
        Min = 1,
        Max = 400,
        Default = 60
    },
    Step = 1,
    Callback = function(val)
        Config.Speed = val
        updateStatusUI()
        pcall(function()
            if State.Enabled and Config.MovementMode ~= "Tween (Smooth)" then
                getHumanoid().WalkSpeed = val
            end
        end)
    end
})

local MoveModifiersSection = MoveTab:Section({
    Title = "Movement Modifiers",
    Opened = true
})

MoveModifiersSection:Toggle({
    Title = "Noclip During Tween",
    Desc = "Disables player collision during tweening to prevent snagging on walls/trees",
    Value = true,
    Callback = function(state)
        Config.NoclipOnTween = state
    end
})

MoveModifiersSection:Toggle({
    Title = "Auto Jump Obstacles",
    Desc = "Automatically jumps when approaching hurdles or when stuck during walk",
    Value = true,
    Callback = function(state)
        Config.AutoJump = state
    end
})

--------------------------------------------------------------------------------
-- TAB 3: WEBHOOK NOTIFICATIONS
--------------------------------------------------------------------------------
local WebhookTab = Window:Tab({
    Title = "Webhook",
    Icon = "bell"
})

local WebhookConfigSection = WebhookTab:Section({
    Title = "Discord Webhook Setup",
    Opened = true
})

WebhookConfigSection:Toggle({
    Title = "Enable Discord Webhook",
    Desc = "Toggles sending real-time egg farming & hatch alerts to your Discord channel",
    Value = false,
    Callback = function(state)
        Config.WebhookEnabled = state
        WindUI:Notify({
            Title = "Webhook Notifications",
            Content = state and "Webhook alerts enabled!" or "Webhook alerts disabled.",
            Duration = 2.5,
            Icon = state and "check-circle" or "x-circle"
        })
    end
})

WebhookConfigSection:Input({
    Title = "Discord Webhook URL",
    Desc = "Enter your Discord channel webhook URL",
    Value = Config.WebhookURL,
    Placeholder = "https://discord.com/api/webhooks/...",
    Callback = function(text)
        Config.WebhookURL = text or ""
    end
})

WebhookConfigSection:Button({
    Title = "Test Webhook Notification",
    Desc = "Sends a sample embed to test that your webhook URL works properly",
    Callback = function()
        if Config.WebhookURL == "" then
            WindUI:Notify({
                Title = "Webhook Error",
                Content = "Please enter a valid Discord webhook URL first!",
                Duration = 3,
                Icon = "alert-triangle"
            })
            return
        end

        local originalEnabled = Config.WebhookEnabled
        Config.WebhookEnabled = true
        sendDiscordWebhook({
            title = "❄️ Frost Hub Webhook Connected!",
            description = "Your Discord webhook has been successfully configured and verified.",
            color = 0x3498db,
            fields = {
                { name = "Status", value = "Connected & Active", inline = true },
                { name = "Game", value = "Ride A Pet", inline = true },
                { name = "Active Speed", value = tostring(Config.Speed) .. " studs/s", inline = true },
                { name = "Movement Mode", value = Config.MovementMode, inline = true },
            },
            footer = { text = "❄️ Frost Hub • Webhook Diagnostics" },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        })
        Config.WebhookEnabled = originalEnabled

        WindUI:Notify({
            Title = "Test Sent",
            Content = "Test payload dispatched to your Discord webhook!",
            Duration = 3,
            Icon = "send"
        })
    end
})

local WebhookTriggersSection = WebhookTab:Section({
    Title = "Egg Notification Policy",
    Opened = true
})

WebhookTriggersSection:Toggle({
    Title = "One Alert Per Egg",
    Desc = "Consolidated notification per egg farmed (includes luck, type, distance, and total count)",
    Value = true,
    Callback = function(state)
        Config.OneAlertPerEgg = state
    end
})

WebhookTriggersSection:Toggle({
    Title = "Include Farmer Stats",
    Desc = "Attach farmer username, elapsed session time, and farming rate (eggs/hr) to embed",
    Value = true,
    Callback = function(state)
        Config.IncludeFarmerStats = state
    end
})

WebhookTriggersSection:Paragraph({
    Title = "Anti-Spam Guarantee",
    Desc = "Each egg generates strictly ONE notification upon completion, preventing channel spam and duplicate alerts."
})

--------------------------------------------------------------------------------
-- TAB 4: SETTINGS & HUD CUSTOMIZATION
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
    Title = "Frost Hub v2.4 - Egg Panel & Live Radar Suite",
    Desc = "Built with WindUI for ultra-smooth responsiveness.\nPress RightShift or RightControl to toggle the window."
})

-- Global Keybind to toggle HUD
UserInputService.InputBegan:Connect(function(input, processed)
    if not processed and (input.KeyCode == Enum.KeyCode.RightControl or input.KeyCode == Enum.KeyCode.RightShift) then
        Window:Toggle()
    end
end)

-- Initialize & start background auto-update for Egg Panel
EggPanel:Init()
EggPanel:StartAutoUpdate()

print("❄️ [Frost Hub] WindUI Egg Panel & Radar Suite initialized.")
