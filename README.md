# ❄️ Frost Hub - Scripts Repository

Advanced gameplay automation, testing, and utility Luau scripts for Roblox.

---

## 🥚 Auto Collect Eggs (WindUI Edition)

A high-performance prototyping system built on [WindUI](https://github.com/Footagesus/WindUI) with acrylic glassmorphism, responsive sidebar tabs, and multi-modal movement engines:

### ✨ Features
- **🎨 WindUI Design**: Translucent dark acrylic theme, tabbed navigation, smooth animations, resizable window, and notifications.
- **⚡ Multiple Movement Systems**:
  - **Walk (Pathfinding)**: Uses PathfindingService with waypoint tracking and automatic obstacle hopping.
  - **Walk (Direct)**: Straight-line speed sprint towards target.
  - **Tween (Smooth Glide)**: Smooth CFrame interpolation with anti-gravity stabilization and optional noclip.
- **🏎️ Configurable Speeds (1 to 400)**:
  - **Walk Speed Slider**: Adjusts Humanoid walk speed from 1 to 400 studs/s.
  - **Tween Speed Slider**: Configures glide speed from 1 to 400 studs/s.
- **🛡️ Server-Validated Loop**:
  - Detects eggs from server-replicated state (workspace.RenderedEggs).
  - Triggers standard ProximityPrompt collection.
  - Verifies carried state in player.Basket.
  - Automatically navigates to player's designated plot baseplate and confirms deposit.

### 🚀 Load Script

`lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Frost-GG-Hud/Scripts/main/AutoCollectEggs.lua"))()
`

### 🎮 Controls
- **Toggle Window**: Press RightControl or RightShift to show or hide the HUD.
- **Resize Window**: Drag the bottom-right resize handle or adjust **HUD Scale** in Settings.
- **Move Window**: Drag anywhere on the title header.