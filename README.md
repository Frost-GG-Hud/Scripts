# ❄️ Frost Hub - Scripts Repository

Advanced gameplay automation, testing, and webhook integration suite for Roblox.

---

## 🥚 Auto Collect Eggs (WindUI Edition)

A high-performance prototyping system built on [WindUI](https://github.com/Footagesus/WindUI) with acrylic glassmorphism, responsive sidebar tabs, unified speed control, Egg Luck filtering, and Discord webhooks.

### ✨ Features
- **ℹ️ Information Tab (Primary Landing Tab)**:
  - Automatically selected and opened immediately upon entering a valid script key.
  - **Hub Version**: Current hub version `V 0.1`.
  - **License & Key Validity**: Live remaining key duration formatted dynamically in days, hours, minutes, and seconds, updating automatically in real time (or permanent `Lifetime` display).
  - **Discord Community**: Direct invite to our official Discord server (`https://discord.gg/xGfTjURZVb`) with a 1-click clipboard copy button.
  - **Support & Tutorials**: Fast access to support tickets and directions to the key tutorial in `#get-script-key`.
  - **Farmer & Session Details**: Displays player username, display name, account age, place ID, and quick keybind reference with sleek typographic symbols.
- **💎 WindUI Interface**: Dark acrylic glassmorphism, fluid micro-animations, resizable window, and notifications.
- **🤖 Automation (Auto Collect Eggs)**:
  - Smooth round-trip farming loop: tweens to the assigned egg, collects it instantly upon arrival, tweens back to your plot base, and immediately repeats with the next egg.
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
- **⚡ Instant Movement Speed Control (0 to 350 studs/s)**:
  - Responsive **Movement Speed** slider (0 to 350 studs/s) that applies changes instantly to live tween navigation without requiring a restart or refresh.
- **🚀 Pure Tween Navigation Engine**:
  - Smooth CFrame interpolation with anti-gravity stabilization and noclip as the standard engine for round-trip farming (tween to egg, instant collect, tween to base, and immediate loop repeat).
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
- **📁 Configurations (Dedicated Management Tab)**:
  - Completely separate tab on the sidebar for managing unlimited custom profiles independently.
  - **◈ Configuration Overview**: Live profile inspector displaying active configuration name, profile count, disk storage status (`FrostHub/configurations.json`), and last saved timestamp.
  - **Dropdown Profile Selector**: Instant dropdown listing all saved configuration profiles.
  - **📂 Load Configuration**: Restores and applies all 15 active settings, sliders, toggles, filters, ESP parameters, and webhooks for the selected profile in 1 click.
  - **💾 Create & Save Configuration**: Enter any profile name and save your complete current setup. Automatically registers in the profile manager.
  - **✏️ Rename Configuration**: Seamlessly rename existing saved profiles with instant validation and dropdown synchronization.
  - **🗑️ Delete Configuration**: Remove outdated configurations with automatic fallback to keep your list clean and organized.
  - **No Auto-Load On Rejoin**: Configurations are never loaded automatically upon rejoining—giving players total control over when and what to load.


### 🤖 Discord Bot Commands & Key System

The official Frost Hub Discord Bot manages community keys and announcements:
- **🎁 `/claim key`**: Available to **everyone**. DMs the user with their personal **6-hour key** in <#1550589425497542676>. Automatically sends a follow-up DM when the key expires after 6 hours reminding them to claim a new one. Enforces a strict **one key per 6 hours** cooldown per user (bypassed by role ID `1550567704925044858`).
- **🛡️ `,verifysetup`**: Sends the official verification embed with **Add Bot to Your App** and **Verify & Claim Roles** buttons directly into channel `<#1550596467075452968>`. Pings `<@&1549092244374421554>` and grants the Member and Section roles upon clicking verify, with support tickets directed to `<#1549104953463803934>` and successful verifications logged in `<#1549394258644176917>`. (Admin/Authorized restricted).
- **ℹ️ `,info [#channel]`**: Sends official script info to a selected channel (e.g. `,info #general`), directs users to `<#1550589425497542676>` to claim their free 6-hour key, links support tickets to `<#1549104953463803934>`, and attaches an interactive **Supported Games** button displaying `Ride a Pet`. If run in or directed to the verification channel, automatically deploys verification setup.
- **🔑 `,ck [@user] <duration>`**: Generate keys with custom durations (e.g. `,ck 7 days`, `,ck 24h`, `,ck lifetime` or `,ck @user 1w`). When pinging a user (e.g. `,ck @Pinguser 1w`), automatically delivers the key and instructions directly to their DMs, and sends the key embed to the channel so they still have access to it even if messages get deleted. Syncs immediately to GitHub and logs creation to `<#1550571106497470584>`. Restricted to role ID `1550567704925044858`.
- **📋 `,keys [filter]`**: View all keys in a public embed with interactive **Previous** and **Next** page swipe buttons. Supports filters: `,keys active` (active keys only), `,keys revoked` (revoked keys only), `,keys expired` (expired keys only), or `,keys` (all keys). Restricted to role ID `1550567704925044858`.
- **🚫 `,rk <key>`**: Instantly revoke a script key with immediate GitHub sync and in-game cutoff (e.g. `,rk 423432423` or `,rk FROST-XXXX`). Restricted to role ID `1550567704925044858`.

### 📥 Load Script

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Frost-GG-Hud/Scripts/main/AutoCollectEggs.lua"))()
```

### 🎮 Controls & Minimized Mode
- **Minimize Window (− Button)**: Click the **`−`** minus button in the top right corner of the title bar to minimize the GUI into a sleek, floating **Frost Hub Logo Box** styled in the exact same matching grey color as the other GUI elements.
- **Reopen Window**: Click the floating Frost Hub logo box anytime to reopen the GUI, or press `RightControl` / `RightShift`.
- **Draggable Logo Box**: Freely drag the floating Frost Hub logo box to any convenient position on your screen. Hover effects smoothly highlight the logo and border.
- **Toggle Window (Keybind)**: Press `RightControl` or `RightShift` to show or hide the HUD.
- **Resize Window**: Drag the bottom-right resize handle or adjust **HUD Scale** in Settings.
- **Move Window**: Drag anywhere on the title header.


