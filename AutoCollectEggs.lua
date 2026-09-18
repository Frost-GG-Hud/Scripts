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

if getgenv and getgenv().FrostHubCleanup then
    pcall(getgenv().FrostHubCleanup)
end

local ScriptRunId = HttpService:GenerateGUID(false)
if getgenv then
    getgenv().FrostHubRunId = ScriptRunId
end

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
    local str
    if num >= 1e12 then
        str = string.format("%.1fT", num / 1e12)
    elseif num >= 1e9 then
        str = string.format("%.1fB", num / 1e9)
    elseif num >= 1e6 then
        str = string.format("%.1fM", num / 1e6)
    elseif num >= 1e3 then
        str = string.format("%.1fK", num / 1e3)
    else
        return tostring(math.floor(num))
    end
    return string.gsub(str, "%.0([KMBT])", "%1")
end

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------
local Config = {
    MovementMode = "Teleport & Tween Return", -- Teleport to egg, collect, tween back to base
    Speed = 60,                          -- Movement speed for return Tween (0 to 350)
    NoclipOnTween = true,
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
    EggRegisterWait = 1.5,               -- Wait 1-2s at egg after teleporting before collecting
    -- Egg Luck Filtering
    CollectByLuck = false,
    CollectByValue = false,              -- Backwards-compatible alias
    MinLuck = 1000000,                   -- Default 1m (1,000,000 Luck)
    MinLuckString = "1m",
    MinValue = 1000000,                  -- Backwards-compatible alias
    MinValueString = "1m",
    -- Egg ESP Configuration
    ESPEnabled = false,
    ESPMinLuck = 0,
    ESPMinLuckString = "0",
    -- Webhook Configuration
    WebhookEnabled = false,
    WebhookURL = "",
    OneAlertPerEgg = true,               -- Strictly one notification per egg (default enabled)
    IncludeFarmerStats = true,           -- Automatically included by default
    EggNotifications = true,             -- Send egg stats when egg is collected and deposited
    WeatherNotifications = true,         -- Send weather event & change notifications
}

local UtilitiesConfig = {
    AutoIndex = false,
    AutoRebirth = false,
    AutoHatchLuck = false,
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
    if not Config.EggNotifications then return end
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
-- WEATHER MONITOR & NOTIFICATION SUBSYSTEM
--------------------------------------------------------------------------------
local WeatherChangedConnection = nil
local LastWeatherSignature = nil

local WEATHER_METADATA = {
    Thunder = {
        DisplayName = "Thunderstorm",
        Icon = "⚡",
        Color = 0xf1c40f,
        Mutation = "Shocked Mutation",
        DefaultChance = "60%",
        DefaultDesc = "Grants Shocked Mutation to eggs struck in the map"
    },
    Volt = {
        DisplayName = "Volt Tempest",
        Icon = "🔋",
        Color = 0x2ecc71,
        Mutation = "Volted Mutation",
        DefaultChance = "30%",
        DefaultDesc = "Grants Volted Mutation to eggs struck in the map"
    },
    Raging = {
        DisplayName = "Raging Inferno",
        Icon = "🔥",
        Color = 0xe67e22,
        Mutation = "Rage Mutation",
        DefaultChance = "6%",
        DefaultDesc = "Grants Rage Mutation to eggs struck in the map"
    },
    Dreadful = {
        DisplayName = "Dreadful Void",
        Icon = "🌌",
        Color = 0x8e44ad,
        Mutation = "Void Mutation",
        DefaultChance = "3%",
        DefaultDesc = "Grants Void Mutation to eggs struck in the map"
    },
    Eternal = {
        DisplayName = "Eternal Storm",
        Icon = "✨",
        Color = 0xe74c3c,
        Mutation = "Eternal Mutation",
        DefaultChance = "1%",
        DefaultDesc = "Grants Eternal Mutation to eggs struck in the map"
    },
    Gigantuar = {
        DisplayName = "Gigantuar Event",
        Icon = "🗿",
        Color = 0x1abc9c,
        Mutation = "Giant Size",
        DefaultChance = "Special Event",
        DefaultDesc = "Eggs struck in the map become giant or colossal"
    }
}

pcall(function()
    local gd = ReplicatedStorage:FindFirstChild("GameData")
    local wMod = gd and gd:FindFirstChild("Weather")
    local weatherReq = wMod and require(wMod)
    if weatherReq and weatherReq.Data then
        for wName, wVal in pairs(weatherReq.Data) do
            if WEATHER_METADATA[wName] then
                if wVal.Description then
                    WEATHER_METADATA[wName].DefaultDesc = wVal.Description
                end
                if wVal.Chance then
                    WEATHER_METADATA[wName].DefaultChance = tostring(wVal.Chance) .. "%"
                end
            else
                WEATHER_METADATA[wName] = {
                    DisplayName = tostring(wName),
                    Icon = "🌪️",
                    Color = 0x3498db,
                    Mutation = tostring(wVal.MutationGranted or "Special Mutation"),
                    DefaultChance = tostring(wVal.Chance or "?") .. "%",
                    DefaultDesc = tostring(wVal.Description or "Special weather event active")
                }
            end
        end
    end
end)

local function getActiveWeathers()
    local ServerData = ReplicatedStorage:FindFirstChild("ServerData")
    if not ServerData then return {} end
    local raw = ServerData:GetAttribute("ActiveWeathers")
    if not raw or raw == "" or raw == "[]" then return {} end

    local success, list = pcall(function()
        return HttpService:JSONDecode(raw)
    end)

    if success and type(list) == "table" then
        return list
    end
    return {}
end

local function getWeatherSignature(list)
    if not list or #list == 0 then
        return "CLEAR"
    end
    local parts = {}
    for _, item in ipairs(list) do
        table.insert(parts, tostring(item.Type) .. "@" .. tostring(item.EndsAt or 0))
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

local function sendWeatherWebhook(eventType, currentList)
    if not Config.WebhookEnabled or Config.WebhookURL == "" then return end
    if not Config.WeatherNotifications then return end

    currentList = currentList or getActiveWeathers()
    eventType = eventType or "Current Weather"

    -- Update last known signature
    LastWeatherSignature = getWeatherSignature(currentList)

    local embed = {
        footer = { text = "❄️ Frost Hub • Live Weather Radar" },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }

    if #currentList == 0 then
        -- Clear skies / No active storms
        if eventType == "Weather Cleared" or eventType == "Cleared" then
            embed.title = "☀️ Weather Cleared • Clear Skies"
            embed.description = "The active storm has dissipated. Map weather has returned to **Clear Skies**."
        else
            embed.title = "☀️ Current Weather • Clear Skies"
            embed.description = "No active weather storms in the server. Standard egg spawns and clear visibility."
        end
        embed.color = 0x3498db -- Bright Sky Blue
        embed.fields = {
            { name = "🌤️ Condition", value = "Clear Skies (Calm)", inline = true },
            { name = "🌪️ Active Storms", value = "None (0)", inline = true },
            { name = "🧬 Egg Mutations", value = "Standard Hatch", inline = true },
            { name = "👤 Farmer", value = string.format("%s (@%s)", LocalPlayer.DisplayName, LocalPlayer.Name), inline = true },
            { name = "🗺️ Map", value = "Ride A Pet", inline = true },
            { name = "⏱️ Server Time", value = os.date("!%H:%M:%S UTC"), inline = true },
        }
    else
        -- One or more active weather storms
        local primary = currentList[1]
        local pType = tostring(primary.Type or "Unknown")
        local meta = WEATHER_METADATA[pType] or {
            DisplayName = pType,
            Icon = "🌪️",
            Color = 0x9b59b6,
            Mutation = "Special Mutation",
            DefaultChance = "Unknown",
            DefaultDesc = "Active weather storm on the map."
        }

        local stormNames = {}
        for _, w in ipairs(currentList) do
            local itemType = tostring(w.Type or "Unknown")
            local itemMeta = WEATHER_METADATA[itemType]
            local icon = itemMeta and itemMeta.Icon or "🌪️"
            table.insert(stormNames, icon .. " " .. itemType)
        end
        local stormTitle = table.concat(stormNames, " + ")

        if eventType == "Weather Event Started" or eventType == "Started" then
            embed.title = string.format("%s Weather Event Started: %s!", meta.Icon, stormTitle)
            embed.description = string.format("A new storm has begun! Grants **%s** to eggs struck in the map.", meta.Mutation)
        elseif eventType == "Weather Changed" or eventType == "Changed" then
            embed.title = string.format("%s Weather Changed: %s!", meta.Icon, stormTitle)
            embed.description = string.format("Server weather conditions shifted! Now experiencing **%s**.", meta.DisplayName)
        else
            embed.title = string.format("%s Current Weather: %s", meta.Icon, stormTitle)
            embed.description = string.format("Server weather status report: **%s** is currently active.", meta.DisplayName)
        end

        embed.color = meta.Color
        embed.fields = {}

        for idx, storm in ipairs(currentList) do
            local sType = tostring(storm.Type or "Unknown")
            local sMeta = WEATHER_METADATA[sType] or {
                DisplayName = sType,
                Icon = "🌪️",
                Mutation = "Special Mutation",
                DefaultChance = "Unknown",
                DefaultDesc = "Active weather storm."
            }
            local endsAt = tonumber(storm.EndsAt)
            local durationStr = "Indefinite / Unknown"
            if endsAt and endsAt > 0 then
                local remaining = math.max(0, endsAt - os.time())
                durationStr = string.format("<t:%d:R> (%s left)", endsAt, formatElapsedTime(remaining))
            end

            local prefix = (#currentList > 1) and string.format("[%d] ", idx) or ""
            table.insert(embed.fields, {
                name = string.format("%s%s %s Storm", prefix, sMeta.Icon, sMeta.DisplayName),
                value = sMeta.DefaultDesc,
                inline = false
            })
            table.insert(embed.fields, {
                name = "🧬 Mutation Granted",
                value = string.format("**%s**", sMeta.Mutation),
                inline = true
            })
            table.insert(embed.fields, {
                name = "🎲 Spawn Chance",
                value = sMeta.DefaultChance,
                inline = true
            })
            table.insert(embed.fields, {
                name = "⏳ Duration Left",
                value = durationStr,
                inline = true
            })
        end

        table.insert(embed.fields, {
            name = "👤 Farmer",
            value = string.format("%s (@%s)", LocalPlayer.DisplayName, LocalPlayer.Name),
            inline = true
        })
        table.insert(embed.fields, {
            name = "🗺️ Map",
            value = "Ride A Pet",
            inline = true
        })
        table.insert(embed.fields, {
            name = "⏱️ Server Time",
            value = os.date("!%H:%M:%S UTC"),
            inline = true
        })
    end

    sendDiscordWebhook(embed)
end

local function handleWeatherChanged()
    if not Config.WebhookEnabled or not Config.WeatherNotifications or Config.WebhookURL == "" then
        return
    end

    local currentList = getActiveWeathers()
    local newSig = getWeatherSignature(currentList)

    if LastWeatherSignature == nil then
        LastWeatherSignature = newSig
        return
    end

    if newSig == LastWeatherSignature then
        return
    end

    local oldSig = LastWeatherSignature
    LastWeatherSignature = newSig

    local eventType
    if newSig == "CLEAR" then
        eventType = "Weather Cleared"
    elseif oldSig == "CLEAR" then
        eventType = "Weather Event Started"
    else
        eventType = "Weather Changed"
    end

    sendWeatherWebhook(eventType, currentList)
end

-- Connect attribute signal and spawn watchdog
pcall(function()
    local ServerData = ReplicatedStorage:WaitForChild("ServerData", 5)
    if ServerData then
        WeatherChangedConnection = ServerData:GetAttributeChangedSignal("ActiveWeathers"):Connect(function()
            handleWeatherChanged()
        end)
    end
end)

task.spawn(function()
    while true do
        if getgenv and getgenv().FrostHubRunId ~= ScriptRunId then break end
        if Config.WebhookEnabled and Config.WeatherNotifications and Config.WebhookURL ~= "" then
            pcall(handleWeatherChanged)
        end
        task.wait(3)
    end
end)

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
-- MOVEMENT SYSTEMS (TELEPORT TO EGG & TWEEN RETURN TO BASE)
--------------------------------------------------------------------------------
local function teleportTo(targetPos)
    local hrp = getHRP()
    local char = getCharacter()
    if not hrp then return false end

    if State.ActiveTween then
        pcall(function()
            State.ActiveTween:Cancel()
        end)
        State.ActiveTween = nil
    end

    local adjustedTarget = targetPos + Vector3.new(0, 2.5, 0)
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        hrp.CFrame = CFrame.new(adjustedTarget)
        if char then
            char:PivotTo(CFrame.new(adjustedTarget))
        end
    end)
    return true
end

local function moveToPoint(targetPos)
    local hrp = getHRP()
    local hum = getHumanoid()
    if not hrp or not hum then return false end

    local adjustedTarget = targetPos + Vector3.new(0, 2.5, 0)
    local distance = (hrp.Position - adjustedTarget).Magnitude
    if distance <= Config.MaxInteractDistance then return true end

    -- Track current destination for instant speed adjustments
    State.CurrentTargetPos = targetPos

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

    while State.Enabled do
        local currentSpeed = math.clamp(tonumber(Config.Speed) or 60, 0, 350)
        if currentSpeed <= 0 then
            while State.Enabled and (tonumber(Config.Speed) or 0) <= 0 do
                task.wait(0.1)
            end
            if not State.Enabled then break end
            currentSpeed = math.clamp(tonumber(Config.Speed) or 60, 0, 350)
        end

        local currentDist = (hrp.Position - adjustedTarget).Magnitude
        if currentDist <= Config.MaxInteractDistance then break end

        local duration = math.clamp(currentDist / currentSpeed, 0.05, 45)
        local tween = TweenService:Create(hrp, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
            CFrame = CFrame.new(adjustedTarget)
        })
        State.ActiveTween = tween
        tween:Play()

        local speedChanged = false
        local lastSpeed = currentSpeed
        local playbackState = nil

        local conn = tween.Completed:Connect(function(playback)
            playbackState = playback or Enum.PlaybackState.Completed
        end)

        while State.Enabled and not playbackState do
            hrp.AssemblyLinearVelocity = Vector3.zero
            local checkSpeed = math.clamp(tonumber(Config.Speed) or 60, 0, 350)
            if checkSpeed ~= lastSpeed then
                speedChanged = true
                break
            end
            task.wait(0.04)
        end

        if conn then conn:Disconnect() end
        if State.ActiveTween then
            State.ActiveTween:Cancel()
            State.ActiveTween = nil
        end

        if not speedChanged then
            break
        end
    end

    if noclipConn then noclipConn:Disconnect() end
    if State.ActiveTween then
        State.ActiveTween:Cancel()
        State.ActiveTween = nil
    end
    State.CurrentTargetPos = nil
    return (hrp.Position - targetPos).Magnitude <= (Config.MaxInteractDistance + 4)
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
                task.wait(1.0)
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
        State.CurrentStatus = string.format("Teleporting to %s [Luck: %s]...", target.Name, formatValueString(target.Luck))
        updateStatusUI()

        -- 3. Teleport player directly to assigned egg
        teleportTo(target.Part.Position)
        State.CurrentStatus = string.format("Arrived at %s, registering...", target.Name)
        updateStatusUI()
        task.wait(Config.EggRegisterWait or 1.5)
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

        -- 6. Tween back to player's base plot
        State.CurrentStatus = "Tweening back to Plot Base..."
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

        -- Wait 1 second at the player's plot before teleporting to the next assigned egg
        task.wait(1.0)
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
    -- 1. Read directly from game's EggCycle service (exact native egg countdown, zero GUI tampering, zero blur)
    local secRemaining = nil
    pcall(function()
        local gs = ReplicatedStorage:FindFirstChild("GameServices")
        if gs and gs:FindFirstChild("EggCycle") then
            local ec = require(gs.EggCycle)
            if ec and ec.SecondsRemaining then
                secRemaining = ec.SecondsRemaining()
            end
        end
    end)
    if secRemaining and type(secRemaining) == "number" then
        local sec = math.max(0, math.floor(secRemaining))
        return string.format("%dm %02ds", math.floor(sec / 60), sec % 60)
    end

    -- 2. Fallback: query DayNight service if available
    local dn = nil
    pcall(function()
        local gs = ReplicatedStorage:FindFirstChild("GameServices")
        if gs and gs:FindFirstChild("DayNight") then
            dn = require(gs.DayNight)
        end
    end)
    if dn and dn.SecondsUntilNextPhase then
        local sec = math.max(0, math.floor(dn.SecondsUntilNextPhase()))
        return string.format("%dm %02ds", math.floor(sec / 60), sec % 60)
    end

    -- 3. Passive read of EggTracker Timer without ever modifying Visible or Position
    local text = ""
    pcall(function()
        local et = LocalPlayer.PlayerGui:FindFirstChild("Main")
            and LocalPlayer.PlayerGui.Main:FindFirstChild("EggTracker")
        if et and et:FindFirstChild("Timer") then
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

    return "0m 00s"
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

    local RARITY_TIER_WEIGHT = {
        Ethereal  = 7,
        Divine    = 6,
        Mythic    = 5,
        Legendary = 4,
        Epic      = 3,
        Rare      = 2,
        Common    = 1,
    }

    table.sort(list, function(a, b)
        local tierA = RARITY_TIER_WEIGHT[a.Rarity] or 0
        local tierB = RARITY_TIER_WEIGHT[b.Rarity] or 0
        if tierA ~= tierB then
            return tierA > tierB
        end
        local luckA = a.Luck or 0
        local luckB = b.Luck or 0
        if luckA ~= luckB then
            return luckA > luckB
        end
        return tostring(a.Name) < tostring(b.Name)
    end)

    return list
end

local function setUIFont(obj, weight)
    weight = weight or Enum.FontWeight.Medium
    pcall(function()
        obj.FontFace = Font.new("rbxassetid://12187365364", weight, Enum.FontStyle.Normal)
    end)
    if not obj.FontFace or tostring(obj.FontFace.Family) == "" then
        obj.Font = (weight == Enum.FontWeight.Bold or weight == Enum.FontWeight.SemiBold) and Enum.Font.GothamBold or Enum.Font.GothamMedium
    end
end

local EggPanel = {
    Gui = nil,
    MainFrame = nil,
    IsOpen = false,
    SearchQuery = "",
    ActiveFilter = "All",
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

    local parentGui = LocalPlayer:WaitForChild("PlayerGui")

    local gui = Instance.new("ScreenGui")
    gui.Name = "FrostHub_EggPanelGui"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Enabled = false
    gui.Parent = parentGui
    self.Gui = gui

    local main = Instance.new("Frame")
    main.Name = "MainFrame"
    main.Size = UDim2.new(0, 420, 0, 540)
    main.Position = UDim2.new(0.5, 60, 0.5, -270)
    main.BackgroundColor3 = Color3.fromRGB(16, 16, 16)
    main.BackgroundTransparency = 0.04
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.Parent = gui
    self.MainFrame = main

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 16)
    mainCorner.Parent = main

    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = Color3.fromRGB(255, 255, 255)
    mainStroke.Transparency = 0.92
    mainStroke.Thickness = 1
    mainStroke.Parent = main

    -- Background texture matching WindUI
    local bgImg = Instance.new("ImageLabel")
    bgImg.Name = "Background"
    bgImg.Size = UDim2.new(1, 0, 1, 0)
    bgImg.BackgroundTransparency = 1
    bgImg.Image = "rbxassetid://89641024074289"
    bgImg.ImageColor3 = Color3.fromRGB(16, 16, 16)
    bgImg.ImageTransparency = 0.15
    bgImg.BorderSizePixel = 0
    bgImg.Parent = main

    -- 1. Top Bar (Draggable, matching WindUI topbar layout & height)
    local topBar = Instance.new("Frame")
    topBar.Name = "Topbar"
    topBar.Size = UDim2.new(1, 0, 0, 52)
    topBar.BackgroundTransparency = 1
    topBar.BorderSizePixel = 0
    topBar.Parent = main

    local topIcon = Instance.new("ImageLabel")
    topIcon.Name = "TopIcon"
    topIcon.Size = UDim2.new(0, 22, 0, 22)
    topIcon.Position = UDim2.new(0, 14, 0.5, -11)
    topIcon.BackgroundTransparency = 1
    topIcon.Image = "rbxassetid://117851493400222"
    topIcon.ImageColor3 = Color3.fromRGB(161, 161, 170)
    topIcon.Parent = topBar

    local topTitle = Instance.new("TextLabel")
    topTitle.Name = "Title"
    topTitle.Text = "Frost Hub | Egg Panel"
    topTitle.Size = UDim2.new(1, -110, 0, 20)
    topTitle.Position = UDim2.new(0, 44, 0, 8)
    topTitle.BackgroundTransparency = 1
    topTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    topTitle.TextSize = 16
    topTitle.TextXAlignment = Enum.TextXAlignment.Left
    setUIFont(topTitle, Enum.FontWeight.SemiBold)
    topTitle.Parent = topBar

    local topSub = Instance.new("TextLabel")
    topSub.Name = "Author"
    topSub.Text = "Live Radar & Reset Tracker"
    topSub.Size = UDim2.new(1, -110, 0, 16)
    topSub.Position = UDim2.new(0, 44, 0, 28)
    topSub.BackgroundTransparency = 1
    topSub.TextColor3 = Color3.fromRGB(161, 161, 170)
    topSub.TextSize = 13
    topSub.TextXAlignment = Enum.TextXAlignment.Left
    setUIFont(topSub, Enum.FontWeight.Medium)
    topSub.Parent = topBar

    local topDivider = Instance.new("Frame")
    topDivider.Name = "Divider"
    topDivider.Size = UDim2.new(1, 0, 0, 1)
    topDivider.Position = UDim2.new(0, 0, 0, 52)
    topDivider.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
    topDivider.BorderSizePixel = 0
    topDivider.Parent = main

    -- Close button matching WindUI window controls
    local closeBtn = Instance.new("ImageButton")
    closeBtn.Name = "CloseButton"
    closeBtn.Size = UDim2.new(0, 36, 0, 36)
    closeBtn.Position = UDim2.new(1, -48, 0.5, -18)
    closeBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.BackgroundTransparency = 1
    closeBtn.Parent = topBar

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 8)
    closeCorner.Parent = closeBtn

    local closeIcon = Instance.new("ImageLabel")
    closeIcon.Name = "CloseIcon"
    closeIcon.Size = UDim2.new(0, 16, 0, 16)
    closeIcon.Position = UDim2.new(0.5, -8, 0.5, -8)
    closeIcon.BackgroundTransparency = 1
    closeIcon.Image = "rbxassetid://110786993356448"
    closeIcon.ImageColor3 = Color3.fromRGB(161, 161, 170)
    closeIcon.Parent = closeBtn

    closeBtn.MouseEnter:Connect(function()
        closeBtn.BackgroundTransparency = 0.88
        closeIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
    end)
    closeBtn.MouseLeave:Connect(function()
        closeBtn.BackgroundTransparency = 1
        closeIcon.ImageColor3 = Color3.fromRGB(161, 161, 170)
    end)
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
    subBar.Size = UDim2.new(1, -28, 0, 32)
    subBar.Position = UDim2.new(0, 14, 0, 64)
    subBar.BackgroundTransparency = 1
    subBar.Parent = main

    local logsBtn = Instance.new("TextButton")
    logsBtn.Name = "EggLogsButton"
    logsBtn.Text = ""
    logsBtn.Size = UDim2.new(0, 105, 1, 0)
    logsBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
    logsBtn.BorderSizePixel = 0
    logsBtn.Parent = subBar

    local logsCorner = Instance.new("UICorner")
    logsCorner.CornerRadius = UDim.new(0, 8)
    logsCorner.Parent = logsBtn

    local logsStroke = Instance.new("UIStroke")
    logsStroke.Color = Color3.fromRGB(46, 46, 52)
    logsStroke.Thickness = 1
    logsStroke.Parent = logsBtn

    local logsIcon = Instance.new("ImageLabel")
    logsIcon.Name = "LogsIcon"
    logsIcon.Size = UDim2.new(0, 14, 0, 14)
    logsIcon.Position = UDim2.new(0, 10, 0.5, -7)
    logsIcon.BackgroundTransparency = 1
    logsIcon.Image = "rbxassetid://113179976918783"
    logsIcon.ImageColor3 = Color3.fromRGB(161, 161, 170)
    logsIcon.Parent = logsBtn

    local logsText = Instance.new("TextLabel")
    logsText.Name = "LogsText"
    logsText.Text = "Egg Logs"
    logsText.Size = UDim2.new(1, -32, 1, 0)
    logsText.Position = UDim2.new(0, 28, 0, 0)
    logsText.BackgroundTransparency = 1
    logsText.TextColor3 = Color3.fromRGB(255, 255, 255)
    logsText.TextSize = 12.5
    setUIFont(logsText, Enum.FontWeight.SemiBold)
    logsText.Parent = logsBtn

    logsBtn.MouseEnter:Connect(function()
        logsBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 46)
        logsStroke.Color = Color3.fromRGB(60, 60, 70)
    end)
    logsBtn.MouseLeave:Connect(function()
        logsBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
        logsStroke.Color = Color3.fromRGB(46, 46, 52)
    end)

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
    resetLabel.RichText = true
    resetLabel.Text = '<font color="rgb(161,161,170)">Next Reset: </font><font color="rgb(255,255,255)"><b>Loading...</b></font>'
    resetLabel.Size = UDim2.new(1, -115, 1, 0)
    resetLabel.Position = UDim2.new(0, 115, 0, 0)
    resetLabel.BackgroundTransparency = 1
    resetLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    resetLabel.TextSize = 13
    resetLabel.TextXAlignment = Enum.TextXAlignment.Right
    setUIFont(resetLabel, Enum.FontWeight.SemiBold)
    resetLabel.Parent = subBar
    self.ResetLabel = resetLabel

    -- 3. Search Bar
    local searchFrame = Instance.new("Frame")
    searchFrame.Name = "SearchFrame"
    searchFrame.Size = UDim2.new(1, -28, 0, 34)
    searchFrame.Position = UDim2.new(0, 14, 0, 106)
    searchFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
    searchFrame.Parent = main

    local searchCorner = Instance.new("UICorner")
    searchCorner.CornerRadius = UDim.new(0, 8)
    searchCorner.Parent = searchFrame

    local searchStroke = Instance.new("UIStroke")
    searchStroke.Color = Color3.fromRGB(40, 40, 46)
    searchStroke.Thickness = 1
    searchStroke.Parent = searchFrame

    local searchIcon = Instance.new("ImageLabel")
    searchIcon.Name = "SearchIcon"
    searchIcon.Size = UDim2.new(0, 15, 0, 15)
    searchIcon.Position = UDim2.new(0, 10, 0.5, -7.5)
    searchIcon.BackgroundTransparency = 1
    searchIcon.Image = "rbxassetid://121018724060431"
    searchIcon.ImageColor3 = Color3.fromRGB(140, 140, 150)
    searchIcon.Parent = searchFrame

    local searchBox = Instance.new("TextBox")
    searchBox.Name = "SearchBox"
    searchBox.Text = "" -- Ensure empty string so only the placeholder displays
    searchBox.Size = UDim2.new(1, -88, 1, 0)
    searchBox.Position = UDim2.new(0, 32, 0, 0)
    searchBox.BackgroundTransparency = 1
    searchBox.PlaceholderText = "Search egg or rarity..."
    searchBox.PlaceholderColor3 = Color3.fromRGB(140, 140, 150)
    searchBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    searchBox.TextSize = 12.5
    searchBox.TextXAlignment = Enum.TextXAlignment.Left
    searchBox.ClearTextOnFocus = false
    setUIFont(searchBox, Enum.FontWeight.Medium)
    searchBox.Parent = searchFrame
    self.SearchBox = searchBox

    searchBox.Focused:Connect(function()
        searchStroke.Color = Color3.fromRGB(0, 145, 255)
    end)
    searchBox.FocusLost:Connect(function()
        searchStroke.Color = Color3.fromRGB(40, 40, 46)
    end)

    local clearBtn = Instance.new("TextButton")
    clearBtn.Name = "ClearButton"
    clearBtn.Text = "Clear"
    clearBtn.Size = UDim2.new(0, 44, 0, 22)
    clearBtn.Position = UDim2.new(1, -50, 0.5, -11)
    clearBtn.BackgroundColor3 = Color3.fromRGB(34, 34, 40)
    clearBtn.TextColor3 = Color3.fromRGB(180, 180, 190)
    clearBtn.TextSize = 11
    setUIFont(clearBtn, Enum.FontWeight.Medium)
    clearBtn.Parent = searchFrame

    local clearCorner = Instance.new("UICorner")
    clearCorner.CornerRadius = UDim.new(0, 6)
    clearCorner.Parent = clearBtn

    clearBtn.MouseEnter:Connect(function()
        clearBtn.BackgroundColor3 = Color3.fromRGB(44, 44, 52)
    end)
    clearBtn.MouseLeave:Connect(function()
        clearBtn.BackgroundColor3 = Color3.fromRGB(34, 34, 40)
    end)

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
    filterScroll.Size = UDim2.new(1, -28, 0, 28)
    filterScroll.Position = UDim2.new(0, 14, 0, 148)
    filterScroll.BackgroundTransparency = 1
    filterScroll.ScrollBarThickness = 0
    filterScroll.CanvasSize = UDim2.new(0, 520, 0, 0)
    filterScroll.ScrollingDirection = Enum.ScrollingDirection.X
    filterScroll.Parent = main

    local filterLayout = Instance.new("UIListLayout")
    filterLayout.FillDirection = Enum.FillDirection.Horizontal
    filterLayout.SortOrder = Enum.SortOrder.LayoutOrder
    filterLayout.Padding = UDim.new(0, 6)
    filterLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    filterLayout.Parent = filterScroll

    -- Ordered: "All" first, then highest rarity to lowest (Ethereal down to Common)
    local filters = { "All", "Ethereal", "Divine", "Mythic", "Legendary", "Epic", "Rare", "Common" }
    self.FilterButtons = {}

    for i, fName in ipairs(filters) do
        local pill = Instance.new("TextButton")
        pill.Name = "Pill_" .. fName
        pill.Text = fName
        pill.LayoutOrder = i
        pill.Size = UDim2.new(0, (fName == "All" or fName == "Any") and 46 or 64, 0, 26)
        pill.TextSize = 11
        pill.BorderSizePixel = 0
        pill.Parent = filterScroll

        local pCorner = Instance.new("UICorner")
        pCorner.CornerRadius = UDim.new(0, 8)
        pCorner.Parent = pill

        local pStroke = Instance.new("UIStroke")
        pStroke.Thickness = 1
        pStroke.Parent = pill

        self.FilterButtons[fName] = { Button = pill, Stroke = pStroke }

        local function updatePillVisual()
            if self.ActiveFilter == fName then
                pill.BackgroundColor3 = Color3.fromRGB(0, 145, 255)
                pStroke.Color = Color3.fromRGB(0, 145, 255)
                pill.TextColor3 = Color3.fromRGB(255, 255, 255)
                setUIFont(pill, Enum.FontWeight.SemiBold)
            else
                pill.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
                pStroke.Color = Color3.fromRGB(38, 38, 44)
                pill.TextColor3 = Color3.fromRGB(161, 161, 170)
                setUIFont(pill, Enum.FontWeight.Medium)
            end
        end
        updatePillVisual()

        pill.MouseEnter:Connect(function()
            if self.ActiveFilter ~= fName then
                pill.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
            end
        end)
        pill.MouseLeave:Connect(function()
            if self.ActiveFilter ~= fName then
                pill.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
            end
        end)

        pill.MouseButton1Click:Connect(function()
            self.ActiveFilter = fName
            for name, item in pairs(self.FilterButtons) do
                local isActive = (name == fName)
                item.Button.BackgroundColor3 = isActive and Color3.fromRGB(0, 145, 255) or Color3.fromRGB(24, 24, 28)
                item.Stroke.Color = isActive and Color3.fromRGB(0, 145, 255) or Color3.fromRGB(38, 38, 44)
                item.Button.TextColor3 = isActive and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(161, 161, 170)
                setUIFont(item.Button, isActive and Enum.FontWeight.SemiBold or Enum.FontWeight.Medium)
            end
            self:RenderCards()
        end)
    end

    -- 5. Card Container (Vertical ScrollingFrame)
    local cardScroll = Instance.new("ScrollingFrame")
    cardScroll.Name = "CardScroll"
    cardScroll.Size = UDim2.new(1, -28, 1, -196)
    cardScroll.Position = UDim2.new(0, 14, 0, 184)
    cardScroll.BackgroundTransparency = 1
    cardScroll.ScrollBarThickness = 4
    cardScroll.ScrollBarImageColor3 = Color3.fromRGB(65, 65, 75)
    cardScroll.ScrollBarImageTransparency = 0.3
    cardScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    cardScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    cardScroll.Parent = main
    self.CardScroll = cardScroll

    local cardLayout = Instance.new("UIListLayout")
    cardLayout.Padding = UDim.new(0, 6)
    cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
    cardLayout.Parent = cardScroll

    pcall(function()
        self:Refresh()
    end)
end

function EggPanel:RenderCards()
    if not self.CardScroll then return end

    local eggs = self.LastEggList or {}
    local query = self.SearchQuery or ""
    local filter = self.ActiveFilter or "All"
    local isAll = (filter == "All" or filter == "Any")

    local activeCardNames = {}
    local visibleCount = 0

    for i, egg in ipairs(eggs) do
        local matchesFilter = isAll or (string.lower(egg.Rarity) == string.lower(filter))
        local matchesSearch = (query == "")
            or string.find(string.lower(egg.Name), query, 1, true)
            or string.find(string.lower(egg.Rarity), query, 1, true)

        if matchesFilter and matchesSearch then
            visibleCount = visibleCount + 1
            local cardName = "EggCard_" .. egg.Name
            activeCardNames[cardName] = true

            local card = self.CardScroll:FindFirstChild(cardName)
            if card then
                -- Card already exists: update dynamic count, distance, and layout order in-place
                card.LayoutOrder = i
                local sub = card:FindFirstChild("SubLabel")
                if sub then
                    sub.Text = string.format("%s • x%d In World • %d studs", egg.Rarity, egg.Count, egg.Distance)
                end
                local badge = card:FindFirstChild("LuckBadge")
                local valLbl = badge and badge:FindFirstChild("LuckValueLabel")
                if valLbl then
                    valLbl.Text = formatValueString(egg.Luck) .. " Luck"
                end
            else
                -- Create new card
                card = Instance.new("Frame")
                card.Name = cardName
                card.Size = UDim2.new(1, 0, 0, 58)
                card.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
                card.BorderSizePixel = 0
                card.LayoutOrder = i
                card.Parent = self.CardScroll

                local cCorner = Instance.new("UICorner")
                cCorner.CornerRadius = UDim.new(0, 10)
                cCorner.Parent = card

                local cStroke = Instance.new("UIStroke")
                cStroke.Color = Color3.fromRGB(38, 38, 44)
                cStroke.Thickness = 1
                cStroke.Parent = card

                card.MouseEnter:Connect(function()
                    card.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
                    cStroke.Color = Color3.fromRGB(52, 52, 60)
                end)
                card.MouseLeave:Connect(function()
                    card.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
                    cStroke.Color = Color3.fromRGB(38, 38, 44)
                end)

                -- Left vertical color accent bar
                local accent = Instance.new("Frame")
                accent.Name = "RarityAccent"
                accent.Size = UDim2.new(0, 3.5, 1, -16)
                accent.Position = UDim2.new(0, 5, 0, 8)
                accent.BackgroundColor3 = RARITY_COLORS[egg.Rarity] or Color3.fromRGB(0, 145, 255)
                accent.BorderSizePixel = 0
                accent.Parent = card
                local aCorner = Instance.new("UICorner")
                aCorner.CornerRadius = UDim.new(0, 2)
                aCorner.Parent = accent

                -- Egg Thumbnail Image
                local iconHolder = Instance.new("Frame")
                iconHolder.Name = "IconHolder"
                iconHolder.Size = UDim2.new(0, 40, 0, 40)
                iconHolder.Position = UDim2.new(0, 15, 0.5, -20)
                iconHolder.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
                iconHolder.BorderSizePixel = 0
                iconHolder.Parent = card
                local iconCorner = Instance.new("UICorner")
                iconCorner.CornerRadius = UDim.new(0, 8)
                iconCorner.Parent = iconHolder

                local iconStroke = Instance.new("UIStroke")
                iconStroke.Color = Color3.fromRGB(44, 44, 52)
                iconStroke.Thickness = 1
                iconStroke.Parent = iconHolder

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
                nameLabel.Name = "NameLabel"
                nameLabel.Text = egg.Name
                nameLabel.Size = UDim2.new(1, -180, 0, 20)
                nameLabel.Position = UDim2.new(0, 66, 0, 9)
                nameLabel.BackgroundTransparency = 1
                nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                nameLabel.TextSize = 13
                nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                setUIFont(nameLabel, Enum.FontWeight.SemiBold)
                nameLabel.Parent = card

                local subLabel = Instance.new("TextLabel")
                subLabel.Name = "SubLabel"
                subLabel.Text = string.format("%s • x%d In World • %d studs", egg.Rarity, egg.Count, egg.Distance)
                subLabel.Size = UDim2.new(1, -180, 0, 16)
                subLabel.Position = UDim2.new(0, 66, 0, 29)
                subLabel.BackgroundTransparency = 1
                subLabel.TextColor3 = Color3.fromRGB(161, 161, 170)
                subLabel.TextSize = 10.5
                subLabel.TextXAlignment = Enum.TextXAlignment.Left
                setUIFont(subLabel, Enum.FontWeight.Medium)
                subLabel.Parent = card

                -- Right-aligned Luck Value Badge
                local luckValueBadge = Instance.new("Frame")
                luckValueBadge.Name = "LuckBadge"
                luckValueBadge.Size = UDim2.new(0, 100, 0, 20)
                luckValueBadge.Position = UDim2.new(1, -108, 0, 9)
                luckValueBadge.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
                luckValueBadge.BorderSizePixel = 0
                luckValueBadge.Parent = card

                local badgeCorner = Instance.new("UICorner")
                badgeCorner.CornerRadius = UDim.new(0, 6)
                badgeCorner.Parent = luckValueBadge

                local badgeStroke = Instance.new("UIStroke")
                badgeStroke.Color = Color3.fromRGB(48, 48, 58)
                badgeStroke.Thickness = 1
                badgeStroke.Parent = luckValueBadge

                local luckValueLabel = Instance.new("TextLabel")
                luckValueLabel.Name = "LuckValueLabel"
                luckValueLabel.Text = formatValueString(egg.Luck) .. " Luck"
                luckValueLabel.Size = UDim2.new(1, 0, 1, 0)
                luckValueLabel.BackgroundTransparency = 1
                luckValueLabel.TextColor3 = Color3.fromRGB(56, 189, 248)
                luckValueLabel.TextSize = 11.5
                setUIFont(luckValueLabel, Enum.FontWeight.SemiBold)
                luckValueLabel.Parent = luckValueBadge

                local tierLabel = Instance.new("TextLabel")
                tierLabel.Name = "TierLabel"
                tierLabel.Text = "Tier " .. egg.Rarity
                tierLabel.Size = UDim2.new(0, 100, 0, 16)
                tierLabel.Position = UDim2.new(1, -108, 0, 30)
                tierLabel.BackgroundTransparency = 1
                tierLabel.TextColor3 = Color3.fromRGB(140, 140, 150)
                tierLabel.TextSize = 9.5
                tierLabel.TextXAlignment = Enum.TextXAlignment.Right
                setUIFont(tierLabel, Enum.FontWeight.Medium)
                tierLabel.Parent = card
            end
        end
    end

    -- Automatically remove any cards for eggs that are no longer on the map
    for _, child in ipairs(self.CardScroll:GetChildren()) do
        if child:IsA("Frame") and string.sub(child.Name, 1, 8) == "EggCard_" then
            if not activeCardNames[child.Name] then
                child:Destroy()
            end
        end
    end

    -- Empty state handling
    local empty = self.CardScroll:FindFirstChild("EmptyLabel")
    if visibleCount == 0 then
        if not empty then
            empty = Instance.new("TextLabel")
            empty.Name = "EmptyLabel"
            empty.Text = "No eggs matching criteria."
            empty.Size = UDim2.new(1, 0, 0, 40)
            empty.BackgroundTransparency = 1
            empty.TextColor3 = Color3.fromRGB(140, 140, 150)
            empty.TextSize = 12
            setUIFont(empty, Enum.FontWeight.Medium)
            empty.Parent = self.CardScroll
        end
    else
        if empty then
            empty:Destroy()
        end
    end
end

function EggPanel:Refresh()
    self.LastEggList = getActiveEggData()
    self.NextResetText = getEggResetTimeText()

    if self.ResetLabel then
        self.ResetLabel.Text = string.format(
            '<font color="rgb(161,161,170)">Next Reset: </font><font color="rgb(255,255,255)"><b>%s</b></font>',
            self.NextResetText
        )
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
    if self.SearchBox then
        self.SearchBox.Text = ""
        self.SearchQuery = ""
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
    local thisRunId = ScriptRunId

    -- Real-time egg spawn and collection listeners on workspace.RenderedEggs
    local eggsFolder = workspace:FindFirstChild("RenderedEggs")
    if eggsFolder then
        eggsFolder.ChildAdded:Connect(function()
            if self.IsOpen then
                pcall(function() self:Refresh() end)
            end
        end)
        eggsFolder.ChildRemoved:Connect(function()
            if self.IsOpen then
                pcall(function() self:Refresh() end)
            end
        end)
    end

    -- Real-time second-by-second timer countdown and distance radar
    task.spawn(function()
        while true do
            if getgenv and getgenv().FrostHubRunId ~= thisRunId then break end
            pcall(function()
                self:Refresh()
            end)
            task.wait(1)
        end
    end)
end

--------------------------------------------------------------------------------
-- EGG ESP SUBSYSTEM (3D World Overlays & Filtering)
--------------------------------------------------------------------------------
local EggESP = {
    Enabled = false,
    MinLuck = 0,
    ActiveMarkers = {}, -- [eggModel] = { Gui = BillboardGui, Part = BasePart, EggName = string, Luck = number, Rarity = string, DistLabel = TextLabel, LuckText = string }
    Holder = nil,
    UpdateTask = nil,
    Listeners = {},
    StatusParagraph = nil,
}

function EggESP:GetHolder()
    if not self.Holder or not self.Holder.Parent then
        local pgui = LocalPlayer:WaitForChild("PlayerGui")
        local existing = pgui:FindFirstChild("FrostHub_ESP_Holder")
        if existing then
            self.Holder = existing
        else
            local holder = Instance.new("Folder")
            holder.Name = "FrostHub_ESP_Holder"
            holder.Parent = pgui
            self.Holder = holder
        end
    end
    return self.Holder
end

function EggESP:CreateMarker(eggModel)
    if not eggModel or not eggModel:IsA("Model") then return end
    if self.ActiveMarkers[eggModel] then return end

    local part = eggModel.PrimaryPart or eggModel:FindFirstChild("Handle") or eggModel:FindFirstChildWhichIsA("BasePart")
    if not part then return end

    local eggName = eggModel.Name
    local GameDataEggs = nil
    pcall(function()
        local gd = ReplicatedStorage:FindFirstChild("GameData")
        if gd and gd:FindFirstChild("Eggs") then
            GameDataEggs = require(gd.Eggs)
        end
    end)
    local gData = GameDataEggs and GameDataEggs[eggName]
    local luck = gData and gData.Luck or EggLuckCache[eggName] or 1
    local rarity = gData and gData.Rarity or "Common"
    local rarityColor = RARITY_COLORS[rarity] or Color3.fromRGB(0, 145, 255)
    local luckText = formatValueString(luck) .. " Luck"

    local holder = self:GetHolder()
    local bb = Instance.new("BillboardGui")
    bb.Name = "ESP_" .. eggName
    bb.Adornee = part
    bb.Size = UDim2.new(0, 145, 0, 38)
    bb.StudsOffset = Vector3.new(0, 2.8, 0)
    bb.AlwaysOnTop = true
    bb.MaxDistance = 5000
    bb.Enabled = self.Enabled and (luck >= self.MinLuck)
    bb.Parent = holder

    local bg = Instance.new("Frame")
    bg.Name = "Background"
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
    bg.BackgroundTransparency = 0.2
    bg.BorderSizePixel = 0
    bg.Parent = bb

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = bg

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1
    stroke.Color = rarityColor
    stroke.Parent = bg

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Text = eggName
    nameLabel.Size = UDim2.new(1, -8, 0, 18)
    nameLabel.Position = UDim2.new(0, 4, 0, 2)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = rarityColor
    nameLabel.TextSize = 11
    nameLabel.TextXAlignment = Enum.TextXAlignment.Center
    setUIFont(nameLabel, Enum.FontWeight.SemiBold)
    nameLabel.Parent = bg

    local hrp = getHRP()
    local initialDist = hrp and (part.Position - hrp.Position).Magnitude or 0
    local distLabel = Instance.new("TextLabel")
    distLabel.Name = "DistLabel"
    distLabel.RichText = true
    distLabel.Text = string.format('<font color="rgb(56,189,248)">%s</font> <font color="rgb(161,161,170)">•</font> <font color="rgb(255,255,255)"><b>%d studs</b></font>', luckText, math.floor(initialDist))
    distLabel.Size = UDim2.new(1, -8, 0, 16)
    distLabel.Position = UDim2.new(0, 4, 0, 19)
    distLabel.BackgroundTransparency = 1
    distLabel.TextSize = 9.5
    distLabel.TextXAlignment = Enum.TextXAlignment.Center
    setUIFont(distLabel, Enum.FontWeight.Medium)
    distLabel.Parent = bg

    self.ActiveMarkers[eggModel] = {
        Gui = bb,
        Part = part,
        EggName = eggName,
        Luck = luck,
        Rarity = rarity,
        DistLabel = distLabel,
        LuckText = luckText
    }
end

function EggESP:RemoveMarker(eggModel)
    local item = self.ActiveMarkers[eggModel]
    if item then
        if item.Gui then
            pcall(function() item.Gui:Destroy() end)
        end
        self.ActiveMarkers[eggModel] = nil
    end
end

function EggESP:UpdateFilter()
    local visibleCount = 0
    local totalMarkers = 0
    for eggModel, item in pairs(self.ActiveMarkers) do
        totalMarkers = totalMarkers + 1
        local isVisible = self.Enabled and (item.Luck >= self.MinLuck)
        if item.Gui then
            item.Gui.Enabled = isVisible
        end
        if isVisible then
            visibleCount = visibleCount + 1
        end
    end
    self:UpdateStatusUI(visibleCount, totalMarkers)
end

function EggESP:UpdateStatusUI(visibleCount, totalCount)
    if not self.StatusParagraph then return end
    pcall(function()
        local total = totalCount or 0
        local vis = visibleCount
        if not vis then
            vis = 0
            for _, item in pairs(self.ActiveMarkers) do
                if self.Enabled and (item.Luck >= self.MinLuck) then
                    vis = vis + 1
                end
                total = total + 1
            end
        end

        local filterText = self.MinLuck > 0 and (formatValueString(self.MinLuck) .. " Luck") or "All Eggs"
        self.StatusParagraph:SetDesc(string.format(
            "ESP Status: %s\nActive Filter: >= %s\nVisible Markers: %d / %d on map",
            self.Enabled and "Active" or "Disabled",
            filterText,
            vis,
            total
        ))
    end)
end

function EggESP:ScanAll()
    local eggsFolder = workspace:FindFirstChild("RenderedEggs")
    if eggsFolder then
        for _, eggModel in ipairs(eggsFolder:GetChildren()) do
            if eggModel:IsA("Model") then
                self:CreateMarker(eggModel)
            end
        end
    end
    self:UpdateFilter()
end

function EggESP:StartDistanceUpdater()
    if self.UpdateTask then return end
    self.UpdateTask = task.spawn(function()
        while self.Enabled do
            local hrp = getHRP()
            local playerPos = hrp and hrp.Position or Vector3.zero
            for eggModel, item in pairs(self.ActiveMarkers) do
                if not eggModel.Parent or not item.Part or not item.Part.Parent then
                    self:RemoveMarker(eggModel)
                elseif item.Gui and item.Gui.Enabled and item.DistLabel then
                    pcall(function()
                        local dist = (item.Part.Position - playerPos).Magnitude
                        item.DistLabel.Text = string.format(
                            '<font color="rgb(56,189,248)">%s</font> <font color="rgb(161,161,170)">•</font> <font color="rgb(255,255,255)"><b>%d studs</b></font>',
                            item.LuckText,
                            math.floor(dist)
                        )
                    end)
                end
            end
            task.wait(0.25)
        end
        self.UpdateTask = nil
    end)
end

function EggESP:SetEnabled(state)
    self.Enabled = state
    Config.ESPEnabled = state
    if state then
        self:ScanAll()
        self:StartDistanceUpdater()
    else
        if self.UpdateTask then
            pcall(task.cancel, self.UpdateTask)
            self.UpdateTask = nil
        end
        for _, item in pairs(self.ActiveMarkers) do
            if item.Gui then item.Gui.Enabled = false end
        end
    end
    self:UpdateFilter()
end

function EggESP:SetMinLuck(val, valStr)
    self.MinLuck = val
    Config.ESPMinLuck = val
    Config.ESPMinLuckString = valStr or formatValueString(val)
    self:UpdateFilter()
end

function EggESP:Init()
    local function hookFolder(folder)
        table.insert(self.Listeners, folder.ChildAdded:Connect(function(child)
            if child:IsA("Model") then
                task.defer(function()
                    self:CreateMarker(child)
                    self:UpdateFilter()
                end)
            end
        end))
        table.insert(self.Listeners, folder.ChildRemoved:Connect(function(child)
            if self.ActiveMarkers[child] then
                self:RemoveMarker(child)
                self:UpdateFilter()
            end
        end))
    end

    local eggsFolder = workspace:FindFirstChild("RenderedEggs")
    if eggsFolder then
        hookFolder(eggsFolder)
    else
        table.insert(self.Listeners, workspace.ChildAdded:Connect(function(child)
            if child.Name == "RenderedEggs" then
                hookFolder(child)
                if self.Enabled then
                    self:ScanAll()
                end
            end
        end))
    end
    if self.Enabled then
        self:ScanAll()
        self:StartDistanceUpdater()
    end
end

function EggESP:Destroy()
    self.Enabled = false
    if self.UpdateTask then
        pcall(task.cancel, self.UpdateTask)
        self.UpdateTask = nil
    end
    for _, conn in ipairs(self.Listeners) do
        pcall(function() conn:Disconnect() end)
    end
    self.Listeners = {}
    for _, item in pairs(self.ActiveMarkers) do
        if item.Gui then pcall(function() item.Gui:Destroy() end) end
    end
    self.ActiveMarkers = {}
    if self.Holder then
        pcall(function() self.Holder:Destroy() end)
        self.Holder = nil
    end
    local pgui = LocalPlayer:FindFirstChild("PlayerGui")
    if pgui then
        local old = pgui:FindFirstChild("FrostHub_ESP_Holder")
        if old then pcall(function() old:Destroy() end) end
    end
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
    if LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") then
        for _, c in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
            if string.find(c.Name, "FrostHub") then c:Destroy() end
        end
    end

    -- Clean up any residual Lighting blur and restore game's EggTracker state
    local Lighting = game:GetService("Lighting")
    local blur = Lighting:FindFirstChild("Blur")
    if blur and blur:IsA("BlurEffect") then
        blur.Enabled = false
    end
    local et = LocalPlayer.PlayerGui:FindFirstChild("Main") and LocalPlayer.PlayerGui.Main:FindFirstChild("EggTracker")
    if et then
        et.Visible = false
        if et.Position.X.Scale == 999 then
            et.Position = UDim2.new(0.5, -150, 0.5, -200)
        end
    end
end)

local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

--------------------------------------------------------------------------------
-- SCRIPT KEY SYSTEM VALIDATOR
--------------------------------------------------------------------------------
local function decodeB64(input)
    if crypt and crypt.base64decode then
        return crypt.base64decode(input)
    end
    if syn and syn.crypt and syn.crypt.base64 and syn.crypt.base64.decode then
        return syn.crypt.base64.decode(input)
    end
    local bs = {
        A=0,B=1,C=2,D=3,E=4,F=5,G=6,H=7,I=8,J=9,K=10,L=11,M=12,N=13,O=14,P=15,
        Q=16,R=17,S=18,T=19,U=20,V=21,W=22,X=23,Y=24,Z=25,a=26,b=27,c=28,d=29,
        e=30,f=31,g=32,h=33,i=34,j=35,k=36,l=37,m=38,n=39,o=40,p=41,q=42,r=43,
        s=44,t=45,u=46,v=47,w=48,x=49,y=50,z=51,["0"]=52,["1"]=53,["2"]=54,
        ["3"]=55,["4"]=56,["5"]=57,["6"]=58,["7"]=59,["8"]=60,["9"]=61,["+"]=62,["/"]=63
    }
    local out = {}
    local n = #input
    local i = 1
    while i <= n do
        local a = bs[input:sub(i, i)] or 0
        local b = bs[input:sub(i+1, i+1)] or 0
        local c = bs[input:sub(i+2, i+2)] or 0
        local d = bs[input:sub(i+3, i+3)] or 0
        local c1 = (a * 4) + math.floor(b / 16)
        local c2 = ((b % 16) * 16) + math.floor(c / 4)
        local c3 = ((c % 4) * 64) + d
        table.insert(out, string.char(c1))
        if input:sub(i+2, i+2) ~= "=" then table.insert(out, string.char(c2)) end
        if input:sub(i+3, i+3) ~= "=" then table.insert(out, string.char(c3)) end
        i = i + 4
    end
    return table.concat(out)
end

local _b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function encodeB64(data)
    if crypt and type(crypt.base64encode) == "function" then
        local s, r = pcall(crypt.base64encode, data)
        if s and r then return r end
    end
    local bytes = { string.byte(data, 1, #data) }
    local result = {}
    local len = #bytes
    for i = 1, len, 3 do
        local b1 = bytes[i]
        local b2 = bytes[i + 1]
        local b3 = bytes[i + 2]

        local c1 = math.floor(b1 / 4) + 1
        local c2 = ((b1 % 4) * 16) + (b2 and math.floor(b2 / 16) or 0) + 1
        local c3 = (b2 and ((b2 % 16) * 4) + (b3 and math.floor(b3 / 64) or 0) + 1) or nil
        local c4 = (b3 and (b3 % 64) + 1) or nil

        table.insert(result, _b64chars:sub(c1, c1))
        table.insert(result, _b64chars:sub(c2, c2))
        table.insert(result, c3 and _b64chars:sub(c3, c3) or "=")
        table.insert(result, c4 and _b64chars:sub(c4, c4) or "=")
    end
    return table.concat(result)
end

local _gh1 = "github_pat_11COSC7PY0ypW4gPvLQau2_"
local _gh2 = "NVSZYW0W3mhDEGcZNTu05q2QCdA39tQsAcjuwA5C2PZNYRCB3CI3MqNmn0g"
local GITHUB_AUTH_TOKEN = _gh1 .. _gh2

local function getDeviceHWID()
    local hwid = nil
    -- 1. Executor gethwid / get_hwid
    pcall(function()
        if type(gethwid) == "function" then
            hwid = gethwid()
        elseif type(get_hwid) == "function" then
            hwid = get_hwid()
        end
    end)
    -- 2. RbxAnalyticsService GetClientId (Universal Roblox Client ID)
    if not hwid or tostring(hwid) == "" then
        pcall(function()
            hwid = game:GetService("RbxAnalyticsService"):GetClientId()
        end)
    end
    -- 3. getgenv().gethwid
    if not hwid or tostring(hwid) == "" then
        pcall(function()
            if getgenv and type(getgenv().gethwid) == "function" then
                hwid = getgenv().gethwid()
            end
        end)
    end
    -- 4. Fallback: LocalPlayer UserId hash
    if not hwid or tostring(hwid) == "" then
        pcall(function()
            local lp = game:GetService("Players").LocalPlayer
            hwid = "DEV-" .. tostring(lp and lp.UserId or "CLIENT")
        end)
    end
    return hwid and string.gsub(tostring(hwid), "%s+", "") or "UNKNOWN_HWID"
end

local function bindKeyHWID(targetKey, hwid)
    local getUrl = "https://api.github.com/repos/Frost-GG-Hud/Scripts/contents/keys.json"
    local customReq = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request) or (delta and delta.request)
    if not customReq then
        return false
    end

    local localPlayerName = "Unknown"
    pcall(function()
        local lp = game:GetService("Players").LocalPlayer
        if lp then
            localPlayerName = lp.Name .. " (" .. tostring(lp.UserId) .. ")"
        end
    end)

    for attempt = 1, 2 do
        local sha = nil
        local currentKeys = nil

        pcall(function()
            local res = customReq({
                Url = getUrl,
                Method = "GET",
                Headers = {
                    ["Authorization"] = "Bearer " .. GITHUB_AUTH_TOKEN,
                    ["Accept"] = "application/vnd.github+json",
                    ["User-Agent"] = "FrostHub-HWID-System"
                }
            })
            local status = res and (res.StatusCode or res.Status)
            if status == 200 then
                local data = HttpService:JSONDecode(res.Body)
                if data and data.sha and data.content then
                    sha = data.sha
                    local cleanB64 = string.gsub(data.content, "%s+", "")
                    local decoded = decodeB64(cleanB64)
                    local parsed = HttpService:JSONDecode(decoded)
                    if parsed and parsed.keys then
                        currentKeys = parsed.keys
                    end
                end
            end
        end)

        if sha and currentKeys then
            local updated = false
            for _, entry in ipairs(currentKeys) do
                local k = string.gsub(string.upper(tostring(entry.key or "")), "%s+", "")
                if k == targetKey then
                    entry.hwid = hwid
                    entry.hwid_linked_at = os.time()
                    entry.hwid_user = localPlayerName
                    updated = true
                    break
                end
            end

            if updated then
                local newJson = HttpService:JSONEncode({ keys = currentKeys })
                local newB64 = encodeB64(newJson)
                local putSuccess = false

                pcall(function()
                    local putRes = customReq({
                        Url = getUrl,
                        Method = "PUT",
                        Headers = {
                            ["Authorization"] = "Bearer " .. GITHUB_AUTH_TOKEN,
                            ["Accept"] = "application/vnd.github+json",
                            ["Content-Type"] = "application/json",
                            ["User-Agent"] = "FrostHub-HWID-System"
                        },
                        Body = HttpService:JSONEncode({
                            message = "HWID lock key " .. targetKey,
                            content = newB64,
                            sha = sha,
                            branch = "main"
                        })
                    })
                    local code = putRes and (putRes.StatusCode or putRes.Status)
                    if code == 200 or code == 201 then
                        putSuccess = true
                    end
                end)

                if putSuccess then
                    return true
                end
            end
        end

        if attempt < 2 then
            task.wait(1)
        end
    end

    return false
end

local function fetchValidKeys()
    local jsonContent = nil
    local customReq = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request) or (delta and delta.request)

    -- Attempt 1: Authenticated GitHub API (high rate limit, 0s cache delay)
    if customReq then
        pcall(function()
            local res = customReq({
                Url = "https://api.github.com/repos/Frost-GG-Hud/Scripts/contents/keys.json",
                Method = "GET",
                Headers = {
                    ["Authorization"] = "Bearer " .. GITHUB_AUTH_TOKEN,
                    ["Accept"] = "application/vnd.github+json",
                    ["User-Agent"] = "FrostHub-KeySystem"
                }
            })
            local status = res and (res.StatusCode or res.Status)
            if status == 200 and res.Body and res.Body ~= "" then
                local data = HttpService:JSONDecode(res.Body)
                if data and data.content then
                    local cleanB64 = string.gsub(data.content, "%s+", "")
                    jsonContent = decodeB64(cleanB64)
                end
            end
        end)
    end

    -- Attempt 2: Unauthenticated GitHub API
    if not jsonContent or jsonContent == "" then
        pcall(function()
            local res = game:HttpGet("https://api.github.com/repos/Frost-GG-Hud/Scripts/contents/keys.json")
            if res and res ~= "" then
                local data = HttpService:JSONDecode(res)
                if data and data.content then
                    local cleanB64 = string.gsub(data.content, "%s+", "")
                    jsonContent = decodeB64(cleanB64)
                end
            end
        end)
    end

    -- Attempt 3: Fallback to raw GitHub
    if not jsonContent or jsonContent == "" then
        pcall(function()
            jsonContent = game:HttpGet("https://raw.githubusercontent.com/Frost-GG-Hud/Scripts/main/keys.json?t=" .. tostring(os.time()))
        end)
    end

    if not jsonContent or jsonContent == "" then return {} end
    local success, result = pcall(function()
        return HttpService:JSONDecode(jsonContent)
    end)
    if success and type(result) == "table" and result.keys then
        return result.keys
    end
    return {}
end

local DISCORD_INVITE_URL = "https://discord.gg/xGfTjURZVb"

local ValidatedKeyData = {
    Key = "FREEKEY-FROST-3432432-4324324",
    Duration = "Lifetime",
    ExpiresAt = nil,
    ValidatedAt = os.time()
}

local function formatKeyRemaining()
    if not ValidatedKeyData.ExpiresAt or ValidatedKeyData.ExpiresAt <= 0 then
        return "Lifetime"
    end
    local remaining = ValidatedKeyData.ExpiresAt - os.time()
    if remaining <= 0 then
        return "Expired"
    end
    local days = math.floor(remaining / 86400)
    local hours = math.floor((remaining % 86400) / 3600)
    local minutes = math.floor((remaining % 3600) / 60)
    local seconds = remaining % 60
    
    local parts = {}
    if days > 0 then
        table.insert(parts, string.format("%d day%s", days, days == 1 and "" or "s"))
    end
    if hours > 0 then
        table.insert(parts, string.format("%d hour%s", hours, hours == 1 and "" or "s"))
    end
    if minutes > 0 then
        table.insert(parts, string.format("%d minute%s", minutes, minutes == 1 and "" or "s"))
    end
    table.insert(parts, string.format("%d second%s", seconds, seconds == 1 and "" or "s"))
    return table.concat(parts, ", ")
end

local InfoTab = nil
local updateInfoSection = nil

local function validateFrostKey(inputKey)
    if not inputKey or inputKey == "" then return false end
    local cleanKey = string.gsub(string.upper(tostring(inputKey)), "%s+", "")
    local keysList = fetchValidKeys()
    local currentTime = os.time()

    for _, keyData in ipairs(keysList) do
        local k = string.gsub(string.upper(tostring(keyData.key or "")), "%s+", "")
        if k == cleanKey then
            if keyData.status and string.lower(keyData.status) == "revoked" then
                WindUI:Notify({
                    Title = "Key System",
                    Content = "This key has been revoked.",
                    Duration = 4,
                    Icon = "circle-alert"
                })
                return false
            end

            local expiresAt = tonumber(keyData.expires_at)
            if expiresAt and expiresAt > 0 then
                if currentTime > expiresAt then
                    WindUI:Notify({
                        Title = "Key System",
                        Content = "Key has expired! Use /create key in Discord.",
                        Duration = 4,
                        Icon = "clock-alert"
                    })
                    return false
                end
            end

            -- HWID Device Protection Check (Each key can only be linked to one device)
            local isExempt = (cleanKey == "FREEKEY-FROST-3432432-4324324" or keyData.unrestricted == true or keyData.hwid == "UNRESTRICTED")
            local currentHWID = getDeviceHWID()

            if not isExempt then
                local boundHWID = keyData.hwid
                if boundHWID and tostring(boundHWID) ~= "" and tostring(boundHWID) ~= "nil" and tostring(boundHWID) ~= "null" then
                    -- Key is already locked to a device
                    if tostring(boundHWID) ~= tostring(currentHWID) then
                        WindUI:Notify({
                            Title = "HWID Protection",
                            Content = "This key is locked to another device! Each key can only be used on 1 device.",
                            Duration = 5,
                            Icon = "shield-alert"
                        })
                        return false
                    end
                else
                    -- Key has not been locked to any device yet. Lock it to this device now!
                    keyData.hwid = currentHWID
                    task.spawn(function()
                        bindKeyHWID(cleanKey, currentHWID)
                    end)
                    pcall(function()
                        if writefile then
                            writefile("frosthub_" .. cleanKey .. ".hwid", currentHWID)
                        end
                    end)
                    WindUI:Notify({
                        Title = "Device Linked",
                        Content = "Key successfully locked to this device!",
                        Duration = 3,
                        Icon = "shield-check"
                    })
                end
            end

            if expiresAt and expiresAt > 0 then
                ValidatedKeyData.Key = cleanKey
                ValidatedKeyData.ExpiresAt = expiresAt
                ValidatedKeyData.Duration = "Temporary"
                ValidatedKeyData.ValidatedAt = currentTime
                local remaining = expiresAt - currentTime
                local days = math.floor(remaining / 86400)
                local hours = math.floor((remaining % 86400) / 3600)
                local mins = math.floor((remaining % 3600) / 60)
                local timeStr = days > 0 and string.format("%dd %dh", days, hours) or (hours > 0 and string.format("%dh %dm", hours, mins) or string.format("%dm", mins))
                WindUI:Notify({
                    Title = "Key System",
                    Content = "Access granted! Key valid for " .. timeStr .. ".",
                    Duration = 3,
                    Icon = "check-circle"
                })
                if updateInfoSection then
                    pcall(updateInfoSection)
                end
                task.defer(function()
                    pcall(function()
                        if InfoTab then
                            InfoTab:Select()
                        end
                    end)
                end)
                task.delay(0.5, function()
                    pcall(function()
                        if InfoTab then
                            InfoTab:Select()
                        end
                    end)
                end)
                return true
            else
                -- Lifetime key
                ValidatedKeyData.Key = cleanKey
                ValidatedKeyData.ExpiresAt = nil
                ValidatedKeyData.Duration = "Lifetime"
                ValidatedKeyData.ValidatedAt = currentTime
                WindUI:Notify({
                    Title = "Key System",
                    Content = "Access granted! Lifetime key verified.",
                    Duration = 3,
                    Icon = "check-circle"
                })
                if updateInfoSection then
                    pcall(updateInfoSection)
                end
                task.defer(function()
                    pcall(function()
                        if InfoTab then
                            InfoTab:Select()
                        end
                    end)
                end)
                task.delay(0.5, function()
                    pcall(function()
                        if InfoTab then
                            InfoTab:Select()
                        end
                    end)
                end)
                return true
            end
        end
    end

    WindUI:Notify({
        Title = "Key System",
        Content = "Invalid key. Generate one in Discord using /create key.",
        Duration = 4,
        Icon = "x-circle"
    })
    return false
end

pcall(function()
    if isfile and delfile then
        local oldKeyFiles = {
            "FrostHub/key.txt",
            "FrostHub/key.json",
            "FrostHub/keys.txt",
            "FrostHub/savedkey.txt",
            "WindUI/FrostHub/key.txt",
            "WindUI/FrostHub/key.json",
            "WindUI/key.txt"
        }
        for _, filePath in ipairs(oldKeyFiles) do
            if isfile(filePath) then
                delfile(filePath)
            end
        end
    end
end)

-- Key System customization: rename button to "Get discord invite", widen dialog for spacing, and notify on click
task.spawn(function()
    local handledButtons = {}
    local function setupKeySystem(desc)
        if desc:IsA("Frame") and desc.Size.X.Offset == 430 then
            desc.Size = UDim2.new(0, 500, 0, 0)
        end
        if desc:IsA("TextLabel") and (desc.Text == "Get key" or desc.Text == "Copy key") then
            desc.Text = "Get discord invite"
            local btn = desc:FindFirstAncestorWhichIsA("TextButton") or (desc.Parent and desc.Parent:FindFirstAncestorWhichIsA("TextButton"))
            if btn and not handledButtons[btn] then
                handledButtons[btn] = true
                btn.MouseButton1Click:Connect(function()
                    pcall(function()
                        local setclip = setclipboard or toclipboard or (syn and syn.write_clipboard)
                        if setclip then
                            setclip(DISCORD_INVITE_URL)
                        end
                    end)
                    WindUI:Notify({
                        Title = "Discord Invite Copied",
                        Content = "Discord invite link copied to clipboard!\nPaste it into your browser or a Discord channel and join the server to get the key for free.\n\nKey tutorial is available in the get script key channel in the Discord server.",
                        Duration = 8,
                        Icon = "link"
                    })
                end)
            end
        end
    end

    if WindUI.ScreenGui and WindUI.ScreenGui:FindFirstChild("KeySystem") then
        for _, desc in ipairs(WindUI.ScreenGui.KeySystem:GetDescendants()) do
            setupKeySystem(desc)
        end
        WindUI.ScreenGui.KeySystem.DescendantAdded:Connect(setupKeySystem)
    end
end)

local Window = WindUI:CreateWindow({
    Title = "Frost Hub | Automation",
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
    KeySystem = {
        KeyValidator = validateFrostKey,
        Title = "Frost Hub • Key System",
        Note = "Enter your key generated via Discord bot (/create key).\n• Join our Discord to get your key for free!\n• Key tutorial is available in the get script key channel in the Discord server.",
        URL = DISCORD_INVITE_URL,
        SaveKey = false,
    },
})

--------------------------------------------------------------------------------
-- TAB 1: INFORMATION
--------------------------------------------------------------------------------
InfoTab = Window:Tab({
    Title = "Information",
    Icon = "info"
})

local InformationSection = InfoTab:Section({
    Title = "✦ Key Information",
    Opened = true
})

local KeyInfoParagraph = InformationSection:Paragraph({
    Title = "◈ License Key",
    Desc = "Loading key details..."
})

updateInfoSection = function()
    pcall(function()
        local keyText = (ValidatedKeyData.Key and ValidatedKeyData.Key ~= "") and ValidatedKeyData.Key or "Active Key"
        local durationStr = formatKeyRemaining()

        if KeyInfoParagraph then
            KeyInfoParagraph:SetDesc(string.format(
                "• Key: %s\n• Remaining Duration: %s",
                keyText,
                durationStr
            ))
        end
    end)
end

updateInfoSection()

-- Automatic real-time key remaining duration updater (every 1s)
task.spawn(function()
    while true do
        task.wait(1)
        if KeyInfoParagraph then
            pcall(updateInfoSection)
        end
    end
end)

local CommunitySection = InfoTab:Section({
    Title = "❖ Community & Support",
    Opened = true
})

CommunitySection:Paragraph({
    Title = "⟡ Official Community",
    Desc = "Join the official Frost Hub community for free keys, updates, giveaways, and developer announcements!\n\n• Server Link: " .. DISCORD_INVITE_URL
})

CommunitySection:Button({
    Title = "❐ Copy Discord Invite",
    Desc = "Copies " .. DISCORD_INVITE_URL .. " to your clipboard",
    Callback = function()
        pcall(function()
            local setclip = setclipboard or toclipboard or (syn and syn.write_clipboard)
            if setclip then
                setclip(DISCORD_INVITE_URL)
            end
        end)
        WindUI:Notify({
            Title = "Discord Invite Copied",
            Content = "Discord invite link copied to clipboard!\n" .. DISCORD_INVITE_URL .. "\nPaste it into your browser or Discord to join.",
            Duration = 5,
            Icon = "copy"
        })
    end
})

CommunitySection:Paragraph({
    Title = "✦ Support & Documentation",
    Desc = "• Need Help or Found a Bug? Open a support ticket in our Discord server.\n• Key Tutorial: Check out the step-by-step tutorial in the #get-script-key channel."
})

local SessionSection = InfoTab:Section({
    Title = "◈ Session & Player Overview",
    Opened = true
})

SessionSection:Paragraph({
    Title = "◆ Farmer Profile",
    Desc = string.format("• Player: %s (@%s)\n• User ID: %s\n• Account Age: %d days\n• Place ID: %s",
        LocalPlayer.DisplayName or LocalPlayer.Name,
        LocalPlayer.Name,
        tostring(LocalPlayer.UserId),
        LocalPlayer.AccountAge or 0,
        tostring(game.PlaceId)
    )
})

SessionSection:Paragraph({
    Title = "🎮 Controls & Shortcuts",
    Desc = "• Toggle Menu: RightControl or RightShift\n• Center Window: Settings Tab -> Center Window\n• Scale HUD: Settings Tab -> HUD Scale\n• Movement Speed: Adjust Return Tween speed instantly from 0 to 350 studs/s"
})

-- Automatically select Information Tab upon initial load
pcall(function()
    InfoTab:Select()
end)

--------------------------------------------------------------------------------
-- TAB 2: AUTOMATION
--------------------------------------------------------------------------------
local MainTab = Window:Tab({
    Title = "Automation",
    Icon = "sparkles"
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

-- MOVEMENT SPEED CHANGER (0 to 350 studs/s, applied instantly)
local UnifiedSpeedSlider = MoveSection:Slider({
    Title = "Return Tween Speed",
    Desc = "Adjust speed when tweening back to base (0 to 350 studs/s, applied instantly)",
    Value = {
        Min = 0,
        Max = 350,
        Default = 60
    },
    Step = 1,
    Callback = function(val)
        Config.Speed = val
        updateStatusUI()
        pcall(function()
            local hrp = getHRP()
            if State.Enabled and State.ActiveTween and State.CurrentTargetPos and hrp then
                State.ActiveTween:Cancel()
            end
            local hum = getHumanoid()
            if hum then
                hum.WalkSpeed = math.max(val, 16)
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

--------------------------------------------------------------------------------
-- TAB 4: EGG PANEL & ESP
--------------------------------------------------------------------------------
local EggPanelTab = Window:Tab({
    Title = "Egg Panel",
    Icon = "layout-grid"
})

local EggPanelSection = EggPanelTab:Section({
    Title = "Egg Panel & Live ESP",
    Opened = true
})

EggPanelSection:Button({
    Title = "Open Panel",
    Desc = "Open the live Egg Panel showing all available eggs, luck values, and reset countdown",
    Callback = function()
        EggPanel:Open()
    end
})

EggPanelSection:Toggle({
    Title = "Egg ESP",
    Desc = "Display real-time 3D markers on eggs with egg type, luck value, and distance",
    Value = Config.ESPEnabled,
    Callback = function(state)
        EggESP:SetEnabled(state)
        WindUI:Notify({
            Title = "Egg ESP " .. (state and "Enabled" or "Disabled"),
            Content = state and string.format("Displaying eggs with >= %s Luck", Config.ESPMinLuck > 0 and formatValueString(Config.ESPMinLuck) or "0") or "Egg ESP markers hidden",
            Duration = 2.5,
            Icon = state and "eye" or "eye-off"
        })
    end
})

EggPanelSection:Input({
    Title = "ESP Manager",
    Desc = "Set minimum luck filter (e.g. 100, 20k, 1m, 300b). Hides all eggs below this threshold",
    Value = Config.ESPMinLuckString,
    Placeholder = "e.g. 20k, 100k, 1m, 300b",
    Callback = function(text)
        local parsed = parseValueString(text)
        Config.ESPMinLuck = parsed
        Config.ESPMinLuckString = text
        EggESP:SetMinLuck(parsed, text)
        WindUI:Notify({
            Title = "ESP Manager Updated",
            Content = parsed > 0 and string.format("Showing eggs with >= %s Luck (hiding below)", formatValueString(parsed)) or "Showing all eggs on ESP",
            Duration = 2.5,
            Icon = "filter"
        })
    end
})

--------------------------------------------------------------------------------
-- TAB 5: UTILITIES
--------------------------------------------------------------------------------
local UtilitiesTab = Window:Tab({
    Title = "Utilities",
    Icon = "wrench"
})

local ShopsSection = UtilitiesTab:Section({
    Title = "Shops",
    Opened = true
})

ShopsSection:Button({
    Title = "Open Gear Shop",
    Desc = "Opens the in-game Gear Shop interface to purchase radars and equipment",
    Callback = function()
        pcall(function()
            local shop = LocalPlayer.PlayerGui:FindFirstChild("Main") and LocalPlayer.PlayerGui.Main:FindFirstChild("Shop")
            if shop then
                shop.Visible = true
                if shop:FindFirstChild("Holders") then
                    if shop.Holders:FindFirstChild("Gears") then shop.Holders.Gears.Visible = true end
                    if shop.Holders:FindFirstChild("Food") then shop.Holders.Food.Visible = false end
                end
                if shop:FindFirstChild("Header") and shop.Header:FindFirstChild("Title") then
                    shop.Header.Title.Text = "Gear Shop"
                end
            end
            local prompt = workspace:FindFirstChild("Stalls") and workspace.Stalls:FindFirstChild("Gears") and workspace.Stalls.Gears:FindFirstChild("Rick") and workspace.Stalls.Gears.Rick:FindFirstChild("Torso") and workspace.Stalls.Gears.Rick.Torso:FindFirstChildOfClass("ProximityPrompt")
            if prompt then fireproximityprompt(prompt) end
        end)
        WindUI:Notify({
            Title = "Gear Shop Opened",
            Content = "Gear Shop menu is now active.",
            Duration = 2,
            Icon = "shopping-bag"
        })
    end
})

ShopsSection:Button({
    Title = "Open Food Shop",
    Desc = "Opens the in-game Food Shop interface to purchase pet food (Grass, Bone, Meat, etc.)",
    Callback = function()
        pcall(function()
            local shop = LocalPlayer.PlayerGui:FindFirstChild("Main") and LocalPlayer.PlayerGui.Main:FindFirstChild("Shop")
            if shop then
                shop.Visible = true
                if shop:FindFirstChild("Holders") then
                    if shop.Holders:FindFirstChild("Food") then shop.Holders.Food.Visible = true end
                    if shop.Holders:FindFirstChild("Gears") then shop.Holders.Gears.Visible = false end
                end
                if shop:FindFirstChild("Header") and shop.Header:FindFirstChild("Title") then
                    shop.Header.Title.Text = "Food Shop"
                end
            end
            local prompt = workspace:FindFirstChild("Stalls") and workspace.Stalls:FindFirstChild("Food") and workspace.Stalls.Food:FindFirstChild("Tim") and workspace.Stalls.Food.Tim:FindFirstChild("HumanoidRootPart") and workspace.Stalls.Food.Tim.HumanoidRootPart:FindFirstChildOfClass("ProximityPrompt")
            if prompt then fireproximityprompt(prompt) end
        end)
        WindUI:Notify({
            Title = "Food Shop Opened",
            Content = "Food Shop menu is now active.",
            Duration = 2,
            Icon = "utensils"
        })
    end
})

local UtilsAutoSection = UtilitiesTab:Section({
    Title = "Automation",
    Opened = true
})

UtilsAutoSection:Toggle({
    Title = "Auto Collect Index",
    Desc = "Continuously and automatically claims available Index pet discovery rewards",
    Value = false,
    Callback = function(state)
        UtilitiesConfig.AutoIndex = state
        WindUI:Notify({
            Title = "Auto Collect Index",
            Content = state and "Auto claiming index rewards enabled!" or "Auto collect index disabled.",
            Duration = 2,
            Icon = state and "check" or "x"
        })
    end
})

UtilsAutoSection:Toggle({
    Title = "Auto Rebirth",
    Desc = "Automatically triggers Rebirth as soon as requirements (cash & pet) are met",
    Value = false,
    Callback = function(state)
        UtilitiesConfig.AutoRebirth = state
        WindUI:Notify({
            Title = "Auto Rebirth",
            Content = state and "Auto rebirth enabled!" or "Auto rebirth disabled.",
            Duration = 2,
            Icon = state and "check" or "x"
        })
    end
})

UtilsAutoSection:Toggle({
    Title = "Auto Upgrade Hatch Luck",
    Desc = "Automatically purchases Hatch Luck upgrades on your plot whenever affordable",
    Value = false,
    Callback = function(state)
        UtilitiesConfig.AutoHatchLuck = state
        WindUI:Notify({
            Title = "Auto Upgrade Hatch Luck",
            Content = state and "Auto upgrading hatch luck enabled!" or "Auto upgrade hatch luck disabled.",
            Duration = 2,
            Icon = state and "check" or "x"
        })
    end
})

local function getPlayerCash()
    local sd = LocalPlayer:FindFirstChild("SavedData")
    if sd and sd:FindFirstChild("Cash") and typeof(sd.Cash.Value) == "number" then
        return sd.Cash.Value
    end
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if ls and ls:FindFirstChild("Cash") and typeof(ls.Cash.Value) == "number" then
        return ls.Cash.Value
    end
    return 0
end

local function canPlayerRebirth()
    local rep = game:GetService("ReplicatedStorage")
    local gd = rep:FindFirstChild("GameData")
    if not gd then return false end

    local rebirthsMod = gd:FindFirstChild("Rebirths")
    local generalMod = gd:FindFirstChild("General")
    if not rebirthsMod or not generalMod then return false end

    local success1, rebirthsData = pcall(require, rebirthsMod)
    local success2, generalData = pcall(require, generalMod)
    if not success1 or not success2 or type(rebirthsData) ~= "table" or type(generalData) ~= "table" then
        return false
    end

    local sd = LocalPlayer:FindFirstChild("SavedData")
    local currentRebirths = 0
    if sd and sd:FindFirstChild("Rebirths") and typeof(sd.Rebirths.Value) == "number" then
        currentRebirths = sd.Rebirths.Value
    end

    local cap = rebirthsData.Cap or 6
    if currentRebirths >= cap then
        return false -- Max rebirths reached
    end

    local nextIndex = currentRebirths + 1

    -- 1. Cost requirement check
    local cost = nil
    if rebirthsData.RiggedCost and type(rebirthsData.RiggedCost) == "table" then
        cost = rebirthsData.RiggedCost[nextIndex]
    end
    if not cost and type(rebirthsData.GetCost) == "function" then
        pcall(function()
            cost = rebirthsData.GetCost(nextIndex)
        end)
    end
    if not cost then
        local init = rebirthsData.InitialCost or 1000000
        local mult = rebirthsData.CostMultiplier or 50
        cost = init * (mult ^ (nextIndex - 1))
    end

    local cash = getPlayerCash()
    if cash < (cost or math.huge) then
        return false -- Insufficient cash
    end

    -- 2. Pet requirement check
    local requiredPet = nil
    if generalData.RebirthRequirements and type(generalData.RebirthRequirements) == "table" then
        requiredPet = generalData.RebirthRequirements[nextIndex]
    end

    if requiredPet and requiredPet ~= "" then
        local ownedPetsStr = ""
        if sd and sd:FindFirstChild("OwnedPets") then
            ownedPetsStr = tostring(sd.OwnedPets.Value or "")
        end

        local hasPet = false
        -- Check exact comma-delimited match (e.g. ",Fox,")
        if string.find("," .. ownedPetsStr .. ",", "," .. requiredPet .. ",") then
            hasPet = true
        else
            -- Case-insensitive match across individual pet tokens
            local lowerReq = string.lower(string.gsub(requiredPet, "%s+", ""))
            for pet in string.gmatch(string.lower(ownedPetsStr), "([^,]+)") do
                if string.gsub(pet, "%s+", "") == lowerReq then
                    hasPet = true
                    break
                end
            end
        end

        -- Check equipped / character pets
        if not hasPet then
            local char = LocalPlayer.Character
            if char and char:FindFirstChild(requiredPet) then
                hasPet = true
            end
        end

        if not hasPet then
            return false -- Missing required pet
        end
    end

    return true
end

local lastRebirthAttempt = 0

local function getHatchLuckUpgradeDetails()
    local plot = getPlayerPlot() or (workspace:FindFirstChild("Plots") and workspace.Plots:FindFirstChild("Plot"))
    local pgui = LocalPlayer:FindFirstChild("PlayerGui")
    if not pgui then return nil end

    local maxBtn, maxCost
    local singleBtn, singleCost

    for _, g in ipairs(pgui:GetChildren()) do
        if g:IsA("SurfaceGui") and g.Adornee and (not plot or g.Adornee:IsDescendantOf(plot)) then
            if g.Name == "MaxUpgrade" or g.Name == "MaxUpgradeInput" then
                local btn = g:FindFirstChild("Purchase")
                if btn and btn:IsA("GuiButton") then maxBtn = btn end
                for _, d in ipairs(g:GetDescendants()) do
                    if d:IsA("TextLabel") and string.find(d.Text, "%$") then
                        local parsed = parseValueString(d.Text)
                        if parsed and parsed > 0 then
                            maxCost = parsed
                            break
                        end
                    end
                end
            elseif g.Name == "Upgrade" or g.Name == "UpgradeInput" then
                local btn = g:FindFirstChild("Purchase")
                if btn and btn:IsA("GuiButton") then singleBtn = btn end
                for _, d in ipairs(g:GetDescendants()) do
                    if d:IsA("TextLabel") and string.find(d.Text, "%$") then
                        local parsed = parseValueString(d.Text)
                        if parsed and parsed > 0 then
                            singleCost = parsed
                            break
                        end
                    end
                end
            end
        end
    end

    -- Fallback calculation via ReplicatedStorage.GameData.HatchLuck
    if not maxCost or maxCost <= 0 then
        pcall(function()
            local rep = game:GetService("ReplicatedStorage")
            local gd = rep:FindFirstChild("GameData")
            if gd and gd:FindFirstChild("HatchLuck") then
                local hl = require(gd.HatchLuck)
                local sd = LocalPlayer:FindFirstChild("SavedData")
                local curUpgrades = sd and sd:FindFirstChild("HatchUpgrades") and sd.HatchUpgrades.Value or 0
                if hl.GetPrice then
                    singleCost = singleCost or hl.GetPrice(curUpgrades)
                end
            end
        end)
    end

    return {
        MaxButton = maxBtn,
        MaxCost = maxCost,
        SingleButton = singleBtn,
        SingleCost = singleCost
    }
end

-- Background runner for Utilities automation
task.spawn(function()
    while true do
        if UtilitiesConfig.AutoIndex then
            pcall(function()
                local rep = game:GetService("ReplicatedStorage")
                local remote = rep:FindFirstChild("Remotes") and rep.Remotes:FindFirstChild("Game") and rep.Remotes.Game:FindFirstChild("ClaimIndexReward")
                if remote then remote:FireServer() end
                local claimBtn = LocalPlayer.PlayerGui:FindFirstChild("Main")
                    and LocalPlayer.PlayerGui.Main:FindFirstChild("Index")
                    and LocalPlayer.PlayerGui.Main.Index:FindFirstChild("PetProgress")
                    and LocalPlayer.PlayerGui.Main.Index.PetProgress:FindFirstChild("Claim")
                if claimBtn and claimBtn:IsA("GuiButton") and claimBtn.Visible then
                    if firesignal then firesignal(claimBtn.Activated) end
                end
            end)
        end
        if UtilitiesConfig.AutoRebirth then
            pcall(function()
                local now = os.clock()
                if now - lastRebirthAttempt < 3 then return end

                -- Strictly verify all requirements (cash & pet) before attempting rebirth
                if not canPlayerRebirth() then return end

                lastRebirthAttempt = now
                local rep = game:GetService("ReplicatedStorage")
                local remote = rep:FindFirstChild("Remotes") and rep.Remotes:FindFirstChild("Game") and rep.Remotes.Game:FindFirstChild("Rebirth")
                if remote then remote:FireServer() end
                local rebirthBtn = LocalPlayer.PlayerGui:FindFirstChild("Main")
                    and LocalPlayer.PlayerGui.Main:FindFirstChild("Rebirth")
                    and LocalPlayer.PlayerGui.Main.Rebirth:FindFirstChild("Rebirth")
                if rebirthBtn and rebirthBtn:IsA("GuiButton") and rebirthBtn.Visible then
                    if firesignal then firesignal(rebirthBtn.Activated) end
                end
            end)
        end
        if UtilitiesConfig.AutoHatchLuck then
            pcall(function()
                local cash = getPlayerCash()
                local details = getHatchLuckUpgradeDetails()
                if not details then return end

                -- Strictly verify the player has enough money before attempting to purchase the maximum Hatch Luck upgrade
                if details.MaxButton and details.MaxCost and cash >= details.MaxCost then
                    if firesignal then
                        firesignal(details.MaxButton.Activated)
                    else
                        local conns = getconnections and getconnections(details.MaxButton.Activated) or {}
                        for _, c in ipairs(conns) do pcall(c.Function) end
                    end
                elseif details.SingleButton and details.SingleCost and cash >= details.SingleCost then
                    if firesignal then
                        firesignal(details.SingleButton.Activated)
                    else
                        local conns = getconnections and getconnections(details.SingleButton.Activated) or {}
                        for _, c in ipairs(conns) do pcall(c.Function) end
                    end
                end
            end)
        end
        task.wait(1.5)
    end
end)

--------------------------------------------------------------------------------
-- TAB 6: WEBHOOK NOTIFICATIONS
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
    Desc = "Toggles sending real-time egg farming & weather alerts to your Discord channel",
    Value = false,
    Callback = function(state)
        Config.WebhookEnabled = state
        if state and Config.WeatherNotifications and Config.WebhookURL ~= "" then
            task.spawn(function()
                sendWeatherWebhook("Current Weather")
            end)
        end
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
        local wasEmpty = (Config.WebhookURL == "" or Config.WebhookURL == nil)
        Config.WebhookURL = text or ""
        if wasEmpty and Config.WebhookURL ~= "" and Config.WebhookEnabled and Config.WeatherNotifications then
            task.spawn(function()
                sendWeatherWebhook("Current Weather")
            end)
        end
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
                { name = "Egg Notifications", value = Config.EggNotifications and "Enabled" or "Disabled", inline = true },
                { name = "Weather Alerts", value = Config.WeatherNotifications and "Enabled" or "Disabled", inline = true },
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
    Title = "Notification Preferences",
    Opened = true
})

WebhookTriggersSection:Toggle({
    Title = "Egg Notifications",
    Desc = "Send egg stats whenever an egg is collected and deposited",
    Value = Config.EggNotifications,
    Callback = function(state)
        Config.EggNotifications = state
    end
})

WebhookTriggersSection:Toggle({
    Title = "Weather Notifications",
    Desc = "Send notification for each weather event and when weather changes",
    Value = Config.WeatherNotifications,
    Callback = function(state)
        Config.WeatherNotifications = state
        if state and Config.WebhookEnabled and Config.WebhookURL ~= "" then
            task.spawn(function()
                sendWeatherWebhook("Current Weather")
            end)
        end
    end
})

--------------------------------------------------------------------------------
-- TAB 7: SETTINGS & HUD CUSTOMIZATION
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


-- Global Keybind to toggle HUD
UserInputService.InputBegan:Connect(function(input, processed)
    if not processed and (input.KeyCode == Enum.KeyCode.RightControl or input.KeyCode == Enum.KeyCode.RightShift) then
        Window:Toggle()
    end
end)

-- Initialize & start background auto-update for Egg Panel and Egg ESP
pcall(function()
    EggPanel:Init()
    EggPanel:StartAutoUpdate()
    EggESP:Init()
end)

-- Register cleanup for future reloads
if getgenv then
    getgenv().FrostHubEggPanel = EggPanel
    getgenv().FrostHubEggESP = EggESP
    getgenv().FrostHubUtilitiesConfig = UtilitiesConfig
    getgenv().FrostHubCleanup = function()
        pcall(function()
            if UtilitiesConfig then
                UtilitiesConfig.AutoIndex = false
                UtilitiesConfig.AutoRebirth = false
                UtilitiesConfig.AutoHatchLuck = false
            end
            if EggESP then EggESP:Destroy() end
            if EggPanel and EggPanel.Gui then EggPanel.Gui:Destroy() end
            if WeatherChangedConnection then
                WeatherChangedConnection:Disconnect()
                WeatherChangedConnection = nil
            end
            if LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") then
                local old = LocalPlayer.PlayerGui:FindFirstChild("FrostHub_EggPanelGui")
                if old then old:Destroy() end
                local oldEsp = LocalPlayer.PlayerGui:FindFirstChild("FrostHub_ESP_Holder")
                if oldEsp then oldEsp:Destroy() end
            end
            local Lighting = game:GetService("Lighting")
            local blur = Lighting:FindFirstChildOfClass("BlurEffect") or Lighting:FindFirstChild("Blur")
            if blur and blur:IsA("BlurEffect") then blur.Enabled = false end
            local et = LocalPlayer.PlayerGui:FindFirstChild("Main") and LocalPlayer.PlayerGui.Main:FindFirstChild("EggTracker")
            if et then et.Visible = false end
        end)
    end
end

print("❄️ [Frost Hub] WindUI Egg Panel & Radar Suite initialized.")
