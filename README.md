# Runaway Script

A Roblox script for the game **Runaways**, built with [vindUI Reborn](https://github.com/Skinny-yz/vindUI-Test). Provides combat, movement, teleport, vehicle, weapon, ESP, and loot-automation tools in a single tabbed interface.

> **Disclaimer:** This is a cheat/exploit script. Using it may violate the game's Terms of Service and could get your account banned. Use at your own risk.

> **Credit:** Original script by [100percent-imcooked-367](https://codeberg.org/100percent-imcooked-367) (Discord ID `1330435022921924619`). This repo is a readability + UI-modified version, extended with features ported from other community scripts.

---

## Features

### Combat
- **Kill All NPCs** — Damages `CollectionService`-tagged NPCs (`"NPC"` tag), full `workspace.NPCs` scan, and the helicopter pilot. Tagged NPCs are checked every heartbeat with a per-humanoid 0.1s cooldown; the workspace scan runs every 3 seconds.

### Movement
- **Walk Speed (TP)** — Slider (1–100) that scales horizontal movement via `TranslateBy`, independent of `Humanoid.WalkSpeed`.
- **Directional Speed** — Camera-relative WASD movement. Uses `workspace.Terrain` raycasting so you don't clip into the ground.
- **NoClip** — Disables collision on all character parts. Includes an anti-void fallback: if you fall 100+ studs below your last safe position, it raycasts downward and snaps you back to solid ground.
- **Inf Jump** — Single JumpRequest connection that allows jumping mid-air.
- **Third Person** — Toggles between `LockFirstPerson` and `Classic` camera modes.

### Player
- **God Mode** — Blocks `PlayerDamage.TakeDamage` and `Passout.Abandon`, disables `Dead` state, keeps HP full.
- **Speed Boost** — Overrides `Humanoid.WalkSpeed`.
- **Jump Power Override** — Forces `UseJumpPower` with a custom value.
- **FOV Override** — Sets `Camera.FieldOfView` via `BindToRenderStep`.
- **Gravity Override** — Sets `workspace.Gravity`.
- **Anti-AFK** — Uses `VirtualUser` to fight the idle kick.

### Teleport
- **Goto FinalDoor** — Teleports near the final door and fires its prompt.
- **Teleport to Start** — Jumps to the nearest SpawnLocation.
- **Teleport to Objective** — Uses the `Pointy` player attribute.
- **Save / Load Position** — Stores your current CFrame and restores it later.

### Vehicle
- **Vehicle Dropdown** — Populated from `workspace.Vehicles`.
- **Teleport to Vehicle** — Positions you 5 studs above the selected vehicle.
- **Infinite Fuel** — Keeps your current vehicle's `gasLevel` at maximum.
- **Indestructible Vehicle** — Blocks `DamageVehicle.Damage` for your current car.
- **Flip Vehicle** — Unflips your current vehicle and zeroes its velocity.
- **Stop Vehicle** — Immediately kills velocity on your current vehicle.
- **Car Fly** — Fly your current vehicle with WASD + Space / Ctrl. Camera-relative movement with anchor-on-idle.
- **Auto Refuel** — Automatically pays and pours fuel at nearby gas pumps when your tank is below capacity.

### Loot
- **Loot Aura** — Auto-`LootEquip`s anything within 8 studs.
- **Cash Aura** — Auto-`Cash.Collect`s any cash drop within 7 studs.
- **Bring All Loot** — Teleports to every loot item and equips it, arranging them in a grid behind your saved position.
- **Drop All Loot** — Drops every droppable tool (respects `Undroppable` tag).
- **Sell All Loot** — Runs to the pawn counter and sells everything.
- **Instant Prompt** — Sets every `ProximityPrompt.HoldDuration` to 0 automatically.

### ESP
Uses the Drawing API. Shows name + distance for:
- **Items** — Loot items in `workspace.Loot`.
- **NPCs** — CollectionService-tagged NPCs.
- **Players** — Other players with active characters.
- **Vehicles** — Models in `workspace.Vehicles`.

Each has a text label, box, and tracer (color-coded by type).

### Weapon
- **Infinite Ammo** — Blocks `Ammo.setAmmo` and `Ammo.substractReserve`.
- **No Cooldown** — Patches the weapon config's `maxRpm`.
- **Automatic Fire** — Patches the weapon config's `mode` to `"auto"`.
- **No Recoil** — Blocks `Camera.Recoil` and `Viewmodel.Recoil`.
- **No Spread** — Returns `Vector2.zero` from `Luck.radialFalloff`.

### Automation
- **GET 5 STARS** — Runs the full multi-stage completion script:
  1. Repeatedly fires `GameManager.Replay` and simulates touch interest on every cash/loot sensor.
  2. Clears the PawnShop area (breaks glass, damages NPCs, opens locked buildings).
  3. Teleports through a list of Z-axis checkpoints (read from the HUD if available, otherwise a hard-coded list).
  4. Teleports past the final door.
  5. Returns you to your original position.

### Protection
- **Block Anti-Cheat Remotes** — `hookmetamethod(game, "__namecall", ...)` that drops `FireServer` / `InvokeServer` calls to remotes matching the blocklist:
  `AntiCheatReport`, `FlagPlayer`, `ReportExploit`, `KickPlayer`, `BanPlayer`, `AC_Heartbeat`.

---

## Requirements

- A Roblox executor with:
  - `loadstring`, `HttpGet`, `firetouchinterest`, `fireproximityprompt`
  - `hookmetamethod`, `checkcaller`, `getnamecallmethod` (for the remote blocker)
  - `Drawing.new` (for ESP)
  - `fireclickdetector` (for auto refuel)
- A working internet connection (the script pulls the vindUI library from GitHub at runtime).

Executors that support all of the above: Synapse, Script-Ware, Krnl, Fluxus, Delta, Solara (Drawing + hooks), and most modern executors.

---

## Usage

Paste this into your executor and run:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/keysystem23-rgb/runaway-script/main/Runaway.lua"))()
```

---

File structure

```
runaway-script/
├── Runaway.lua    # Main script
└── README.md      # This file
```

The UI library (full.luau from vindUI Reborn) is fetched remotely, not vendored.

---

UI overview

Built on vindUI Reborn with three tab groups:

Tab Group Tab Contents
RUNAWAYS Home Combat, Movement, Teleport, Automation
RUNAWAYS Player God Mode, Speed, Jump, FOV, Gravity, Anti-AFK
RUNAWAYS Loot Loot Aura, Cash Aura, Bring, Drop, Sell, Instant Prompt
TOOLS Vehicles Dropdown, Teleport, Fuel, Indestructible, Flip, Stop, Car Fly, Auto Refuel
TOOLS ESP Enable toggle + per-category toggles
TOOLS Weapon Infinite Ammo, No Cooldown, Automatic Fire, No Recoil, No Spread
PROTECTION Remotes Anti-cheat remote blocker

---

Notes & known quirks

· Kill All NPCs matches descendants named "Humanoid" in the workspace scan and uses CollectionService tags for the aura. This mirrors the game's internal naming.
· ESP uses the Drawing API. If your executor doesn't support Drawing.new, the toggle will silently do nothing.
· The remote blocker wraps the hook in pcall and shows an error notification if hookmetamethod is unavailable.
· workspace.NPCs, workspace.Vehicles, and workspace.Map.Buildings.CustomsFinal are accessed directly without WaitForChild. If the game renames them, the corresponding feature will error.
· Player sliders (Walk Speed Value, Jump Power, FOV, Gravity) are plumbed but currently apply hardcoded defaults: Speed Boost → 40, Jump Power → 60, FOV → 90, Gravity → 100. Wiring them to live slider values is a one-line change if you need it.
· Auto Farm and Silent Aim are not included. These features exist in other community scripts but require significant additional code (teleport persistence, state serialization, webhook handling, raycast hooks). If you need them, they can be added as separate tabs.
· Melee Mods (punchMods) are not included — they rely on debug.setupvalue / filtergc and are fragile across executor versions.

---

Credits

· Original script: 100percent-imcooked-367 — Discord user ID 1330435022921924619
· Original file: Runaway.lua on Codeberg

```lua
loadstring(game:HttpGet("https://codeberg.org/100percent-imcooked-367/Scripts/raw/branch/main/Script/Runaway.lua"))()
```

· vindUI Reborn — Skinny-yz/vindUI-Test
· Additional features ported from a WindUI-based Runaways script (ESP, teleports, loot utilities, player/vehicle/weapon mods).

This repository is only a modified version of the original script above. The changes are:

· Reformatted and de-obfuscated for readability (readable variable names, proper indentation, logical sectioning)
· Ported from the original Toraisme-modded UI to vindUI Reborn
· Fixed several shadowing bugs from the original mangled version (walk-speed slider, NoClip connection, anti-void raycast, vehicle dropdown selection, GET 5 STARS variable collisions)
· Merged KillAll NPCs and Kill Aura into a single toggle
· Added ESP, teleport menu, loot utilities, player mods, vehicle mods, weapon mods, and an anti-cheat remote blocker

All game logic, remote calls, and behavior are preserved from the original. Credit for the underlying script belongs entirely to the original author.

---

License

No license. Personal use only. Do whatever.
