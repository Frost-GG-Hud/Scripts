# ❄️ Frost Hub - Scripts Repository

Advanced gameplay automation, testing, and webhook integration suite for Roblox.

---

## 🥚 Auto Collect Eggs (WindUI Edition)

A high-performance prototyping system built on [WindUI](https://github.com/Footagesus/WindUI) with acrylic glassmorphism, responsive sidebar tabs, unified speed control, Egg Luck filtering, and Discord webhooks.

### ✨ Features
- **💎 WindUI Interface**: Dark acrylic glassmorphism, fluid micro-animations, resizable window, and notifications.
- **🧭 Egg Panel & Live ESP (Positioned below Movement)**:
  - Dedicated **Egg Panel** tab located directly below the **Movement** tab.
  - **Egg ESP (Live 3D World Markers)**:
    - Renders real-time floating 3D `BillboardGui` markers directly above eggs in the game world.
    - Displays each egg's **Type / Name**, **Luck Value** (e.g. `20K`, `3M`, `1.5B Luck`), and **live Distance from Player** in studs (updating at 4Hz).
    - Color-coded borders matching rarity tiers (Common, Rare, Epic, Legendary, Mythic, Divine, Ethereal).
  - **ESP Manager (Minimum Luck Filter)**:
    - Allows setting an exact minimum luck threshold using text formats (e.g. `20k`, `100k`, `1m`, `300b`).
    - Hides all eggs with luck lower than the specified threshold, rendering ESP only for high-tier eggs (e.g., entering `20K` hides all $< 20\text{K}$ eggs and displays only $\ge 20\text{K}$ luck eggs).
    - Quick-cycle **ESP Manager Presets** button (All Eggs, 20K+, 100K+, 1M+, 50M+, 1B+).
    - Live **Egg ESP Status** counter showing visible markers vs total map eggs.
  - **Standalone Egg Panel Modal**:
    - **Every Available Egg**: Real-time catalog of all eggs currently spawned across the entire map.
    - **Individual Egg Luck**: Exact and shorthand luck values for each egg (e.g., `1K`, `250K`, `1M`, `3M`, `1.5B`, `100B Luck`).
    - **Egg Type & Rarity Tier**: Egg type name, rarity category, live count on the map, and distance to the player in studs.
    - **Live Reset Countdown**: Real-time second-by-second timer showing the exact time remaining until eggs reset/refresh (`Next Reset: Xm Ys`).
    - **Differential Reconciliation**: Eggs that are collected or despawn automatically vanish from the panel in real time without needing to reopen the panel.
    - **Instant Filter & Search**: Quick-filter pills (`All`, `Ethereal`, `Divine`, `Mythic`, `Legendary`, `Epic`, `Rare`, `Common`) and real-time search box.
- **🍀 Egg Luck Filtering**:
  - Toggle **Collect by Luck** directly in the **Auto Collect** tab.
  - Set a minimum luck threshold using the **Egg Luck** input box with flexible shorthand formats (e.g., `100`, `2k`, `1m`, `300b`).
  - Each egg on the map has its own luck value (e.g. Slime Egg = 1k, Skull Egg = 250k, Flaming Egg = 1m, Sinister Egg = 3m, Galaxy Egg = 1.5b, Blackhole Egg = 100b).
  - The system filters out any eggs with less than the entered luck value and only collects eggs with equal to or higher luck (e.g., entering `1m` collects only eggs with $\ge 1,000,000$ luck).
- **⚡ Unified Speed Control (1 to 400)**:
  - Single **Movement Speed** slider that automatically governs both **Walk** (`Humanoid.WalkSpeed`) and **Tween** (studs/s glide) navigation.
- **🚀 Movement Engines**:
  - **Walk (Pathfinding)**: PathfindingService with smart fence/gate routing and auto-jumping.
  - **Walk (Direct)**: Direct line-of-sight sprint towards target.
  - **Tween (Smooth)**: CFrame interpolation with anti-gravity stabilization and optional noclip.
- **🔔 Discord Webhook Integration (Single Alert per Egg)**:
  - Dedicated **Webhook** tab to enter your channel's webhook URL.
  - Test button to verify connection.
  - **Single Notification Policy**: Dispatches strictly **one consolidated webhook notification per egg farmed**, eliminating duplicate alerts.
  - **Comprehensive Embed Data**:
    - **🍀 Egg Luck**: Formatted luck multiplier and exact value (e.g. `1.5B (1500000000)`).
    - **🥚 Egg Type**: Precise name of the collected egg.
    - **📏 Distance**: Travel distance from pickup position to target.
    - **🏆 Total Eggs Farmed**: Accurate running count of eggs farmed in the current session.
    - **👤 Farmer Info**: In-game DisplayName and Username (ideal for multi-account farming).
    - **⏱️ Session Time & Pace**: Active session duration and real-time farming rate (`eggs/hr`).
    - **🚀 Movement Diagnostics**: Active engine and speed used.
    - **🎨 Dynamic Luck Theming**: Embed color dynamically shifts according to egg rarity and luck tier.

### 📥 Load Script

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Frost-GG-Hud/Scripts/main/AutoCollectEggs.lua"))()
```

### 🎮 Controls
- **Toggle Window**: Press `RightControl` or `RightShift` to show or hide the HUD.
- **Resize Window**: Drag the bottom-right resize handle or adjust **HUD Scale** in Settings.
- **Move Window**: Drag anywhere on the title header.
