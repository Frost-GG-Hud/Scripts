# ❄️ Frost Hub - Scripts Repository

Advanced gameplay automation, testing, and webhook integration suite for Roblox.

---

## 🥚 Auto Collect Eggs (WindUI Edition)

A high-performance prototyping system built on [WindUI](https://github.com/Footagesus/WindUI) with acrylic glassmorphism, responsive sidebar tabs, unified speed control, Egg Luck filtering, and Discord webhooks.

### ✨ Features
- **💎 WindUI Interface**: Dark acrylic glassmorphism, fluid micro-animations, resizable window, and notifications.
- **🍀 Egg Luck Filtering (NEW)**:
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
