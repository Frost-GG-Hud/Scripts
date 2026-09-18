# ❄️ Frost Hub - Scripts Repository

Collection of gameplay automation, testing, and utility Luau scripts for Roblox.

---

## 🥚 Auto Collect Eggs

A legitimate prototype gameplay testing feature that automates the egg collection and deposit loop using standard Roblox movement and interaction mechanics:

1. **Egg Detection**: Queries server-spawned eggs (RenderedEggs / ActiveEggs) and selects eligible targets based on proximity and interactive state.
2. **Natural Pathfinding**: Navigates using PathfindingService and Humanoid:MoveTo with jump handling and stuck detection.
3. **Legitimate Interaction**: Triggers the egg's ProximityPrompt without bypassing validation.
4. **Carried State Validation**: Awaits server confirmation via player.Basket.
5. **Deposit Navigation**: Paths player to their designated plot baseplate.
6. **Deposit Confirmation**: Confirms basket clearance on deposit and repeats.

### 🚀 Load Script

`lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Frost-GG-Hud/Scripts/main/AutoCollectEggs.lua"))()
`

### 🎮 Controls
- **Toggle Button**: Click the switch in the UI to enable / disable.
- **Toggle UI**: Press RightControl to show or hide the HUD.
- **Draggable Window**: Drag anywhere on the title bar to reposition.