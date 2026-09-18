# ❄️ Frost Hub - Scripts Repository

Advanced gameplay automation, testing, and webhook integration suite for Roblox.

---

## 🥚 Auto Collect Eggs (WindUI Edition)

A high-performance prototyping system built on [WindUI](https://github.com/Footagesus/WindUI) with acrylic glassmorphism, responsive sidebar tabs, unified speed control, Egg Luck filtering, and Discord webhooks.

### ✨ Features
- **ℹ️ Information Tab (Primary Landing Tab)**:
  - Automatically selected and opened immediately upon entering a valid script key.
  - **Hub Version**: Current hub version `V 0.1`.
  - **License & Key Validity**: Live remaining key duration formatted dynamically in days, hours, and minutes, or permanent `Lifetime (Permanent - Never Expires)` display with instant recalculation button.
  - **Discord Community**: Direct invite to our official Discord server (`https://discord.gg/xGfTjURZVb`) with a 1-click clipboard copy button.
  - **Support & Tutorials**: Fast access to support tickets and directions to the key tutorial in `#get-script-key`.
  - **Farmer & Session Details**: Displays player username, display name, account age, place ID, and quick keybind reference.
- **💎 WindUI Interface**: Dark acrylic glassmorphism, fluid micro-animations, resizable window, and notifications.
- **🤖 Automation (formerly Auto Collect)**:
  - Full hands-free farming loop: scans eggs, walks/tweens to target, interacts, and deposits at your plot.
  - **🍀 Egg Luck Filtering**: Filter eggs by minimum luck using flexible shorthand (e.g., `100`, `2k`, `1m`, `300b`) so only high-value targets are collected.
  - Live activity status indicator tracking current state, target, speed, and collected count.
- **🧭 Egg Panel & Live ESP (Positioned below Movement)**:
  - Dedicated **Egg Panel** tab located directly below the **Movement** tab.
  - **Egg ESP (Live 3D World Markers)**:
    - Renders real-time floating 3D `BillboardGui` markers directly above eggs across the map.
    - Displays each egg's **Type / Name**, **Luck Value** (e.g. `20K`, `3M`, `1.5B Luck`), and **live Distance from Player** in studs (updating at 4Hz).
    - Color-coded borders matching rarity tiers (Common, Rare, Epic, Legendary, Mythic, Divine, Ethereal).
  - **ESP Manager (Minimum Luck Filter)**:
    - Allows setting an exact minimum luck threshold using text formats (e.g. `20k`, `100k`, `1m`, `300b`).
    - Hides all eggs with luck lower than the specified threshold, rendering ESP only for high-tier eggs (e.g., entering `20K` hides all $< 20\text{K}$ eggs and displays only $\ge 20\text{K}$ luck eggs).
  - **Standalone Egg Panel Modal**:
    - Real-time catalog of all eggs currently spawned across the entire map with luck values, rarity, and live reset countdown (`Next Reset: Xm Ys`).
    - In-game eggs reset on a fixed cycle (~5 minutes) which is tracked down to the second.
    - Eggs collected or despawned automatically vanish in real time.
    - Instant filter pills (`All`, `Ethereal`, `Divine`, `Mythic`, `Legendary`, `Epic`, `Rare`, `Common`) and real-time search box.
- **🛠️ Utilities (NEW)**:
  - **Shops**:
    - **Open Gear Shop**: Directly opens the in-game Gear Shop menu anywhere on the map to purchase radars and gear.
    - **Open Food Shop**: Directly opens the in-game Food Shop menu to purchase pet food (Grass, Bone, Meat, Magic Apple, Dragonfruit).
  - **Automation**:
    - **Auto Collect Index**: Continuously and automatically claims available Index pet discovery rewards.
    - **Auto Rebirth**: Automatically checks both Cash and Pet requirements against game data (`Rebirths` and `General.RebirthRequirements`) before triggering Rebirth, completely eliminating notification spam when requirements are unmet.
    - **Auto Upgrade Hatch Luck**: Automatically buys Hatch Luck upgrades on your plot whenever affordable.
- **⚡ Unified Speed Control (1 to 400)**:
  - Single **Movement Speed** slider that automatically governs both **Walk** (`Humanoid.WalkSpeed`) and **Tween** (studs/s glide) navigation.
- **🚀 Movement Engines**:
  - **Walk (Pathfinding)**: PathfindingService with smart fence/gate routing and auto-jumping.
  - **Walk (Direct)**: Direct line-of-sight sprint towards target.
  - **Tween (Smooth)**: CFrame interpolation with anti-gravity stabilization and optional noclip.
- **🔔 Discord Webhook Integration**:
  - Dedicated **Webhook** tab to enter your channel's webhook URL with a **Test Webhook Notification** button.
  - **Default Safeguards & Stats**:
    - **Strictly One Alert Per Egg**: Default policy prevents duplicate alerts or spam.
    - **Automatic Farmer Statistics**: Farmer DisplayName/Username, session elapsed time, farming pace (`eggs/hr`), engine, and speed are automatically bundled.
  - **🥚 Egg Notifications**:
    - Toggle to enable or disable egg farming embeds.
    - When enabled, sends comprehensive stats whenever an egg is collected and deposited.
    - When disabled, egg alerts are suppressed while keeping other alerts active.
  - **🌦️ Weather Notifications**:
    - Sends an initial **Current Weather Report** embed as soon as the webhook starts or is enabled.
    - Continuously tracks live server storms (`ServerData.ActiveWeathers`) and sends instantaneous notifications on every weather event (e.g. Thunderstorm, Volt Tempest, Raging Inferno, Dreadful Void, Eternal Storm, Gigantuar).
    - Sends dynamic alerts when weather changes between storms or when skies clear.
    - Displays granted egg mutations, storm rarity/chance, and live countdown timer until storm expiration (`<t:EndsAt:R>`).

### 🤖 Discord Bot Commands & Key System

The official Frost Hub Discord Bot manages community keys and announcements:
- **🎁 `/claim key`**: Available to **everyone**. Claims a free **6-hour key** in <#1550589425497542676>. Each key remains valid for 6 hours; once expired, users simply run `/claim key` again.
- **ℹ️ `/info [channel]`**: Sends official script info to a selected channel (color `#86C9E6`), directs users to `<#1550589425497542676>` to claim their free 6-hour key, and attaches an interactive **Supported Games** button displaying `Ride a Pet`.
- **🔑 `/create key <length>`**: Generate keys with custom durations (Admin restricted).
- **📋 `/keys [filter]`**: View all active, expired, and revoked keys with audit data (Admin restricted).
- **🚫 `/revoke key <key>`**: Instantly revoke keys with immediate GitHub sync and in-game cutoff (Admin restricted).

### 📥 Load Script

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Frost-GG-Hud/Scripts/main/AutoCollectEggs.lua"))()
```

### 🎮 Controls
- **Toggle Window**: Press `RightControl` or `RightShift` to show or hide the HUD.
- **Resize Window**: Drag the bottom-right resize handle or adjust **HUD Scale** in Settings.
- **Move Window**: Drag anywhere on the title header.

