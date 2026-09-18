# ❄️ Frost Hub - Scripts Repository

Advanced gameplay automation, testing, and webhook integration suite for Roblox.

---

## 🥚 Auto Collect Eggs (WindUI Edition)

A high-performance prototyping system built on [WindUI](https://github.com/Footagesus/WindUI) with acrylic glassmorphism, responsive sidebar tabs, unified speed control, and Discord webhooks:

### ✨ Features
- **🎨 WindUI Interface**: Dark acrylic glassmorphism, fluid micro-animations, resizable window, and notifications.
- **⚡ Unified Speed Control (1 to 400)**:
  - Single **Movement Speed** slider that automatically governs both **Walk** (Humanoid.WalkSpeed) and **Tween** (studs/s glide) navigation.
- **🏃 Movement Engines**:
  - **Walk (Pathfinding)**: PathfindingService with smart fence/gate routing and auto-jumping.
  - **Walk (Direct)**: Direct line-of-sight sprint towards target.
  - **Tween (Smooth)**: CFrame interpolation with anti-gravity stabilization and optional noclip.
- **🔔 Discord Webhook Integration**:
  - Dedicated **Webhook** tab to enter your channel's webhook URL.
  - Test button to verify connection.
  - **Egg Caught Alerts**: Sends egg type, distance, speed, and session count.
  - **Egg Deposited Alerts**: Confirms successful plot delivery.
  - **Hatch & Income Alerts**: Reports hatched pet name, rarity, income/s generated (from GameData.Pets), weight, and mutation.

### 🚀 Load Script

`lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Frost-GG-Hud/Scripts/main/AutoCollectEggs.lua"))()
`

### 🎮 Controls
- **Toggle Window**: Press RightControl or RightShift to show or hide the HUD.
- **Resize Window**: Drag the bottom-right resize handle or adjust **HUD Scale** in Settings.
- **Move Window**: Drag anywhere on the title header.