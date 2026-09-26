# Runaway Script

A Roblox script for the game **Runaways**, built with [vindUI Reborn](https://github.com/Skinny-yz/vindUI-Test). Provides NPC killing, movement utilities, teleport tools, and an automated "GET 5 STARS" run.

> **Disclaimer:** This is a cheat/exploit script. Using it may violate the game's Terms of Service and could get your account banned. Use at your own risk.

> **Credit:** Original script by [100percent-imcooked-367](https://codeberg.org/100percent-imcooked-367) (Discord ID `1330435022921924619`). This repo is a readability + UI-modified version only.

---

## Features

**Combat**
- **KillAll NPCs** — Continuously damages every NPC in `workspace.NPCs` until dead. Toggle on/off.

**Movement**
- **Walk Speed** — Slider (1–100) that scales your horizontal movement via `TranslateBy`, independent of the Humanoid's `WalkSpeed`.
- **NoClip** — Disables collision on all character parts. Includes an anti-void fallback: if you drop more than 100 studs below your last safe position, it raycasts downward and snaps you back onto solid ground.
- **Inf Jump** — Lets you jump mid-air by changing the Humanoid state on every jump request.

**Teleport**
- **Goto FinalDoor** — Teleports to a hard-coded position near the final door, waits, then walks up to the prompt and fires it.
- **Choose a Vehicle / Teleport to Vehicle** — Dropdown populated with every model/part in `workspace.Vehicles`. Teleports you 5 studs above the selected vehicle.

**Automation**
- **GET 5 STARS** — Runs the full multi-stage completion script:
  1. Repeatedly fires `GameManager.Replay` and simulates touch interest on every cash/loot sensor.
  2. Clears the PawnShop area (breaks glass, damages NPCs, opens locked buildings).
  3. Teleports through a list of Z-axis checkpoints (read from the HUD if available, otherwise a hard-coded list).
  4. Teleports past the final door.
  5. Returns you to your original position.

---

## Requirements

- A Roblox executor with `loadstring`, `HttpGet`, `gethui`/`syn.protect_gui`, `firetouchinterest`, and `fireproximityprompt` support (e.g. Synapse, Script-Ware, Krnl, Fluxus, Delta, or any modern executor).
- A working internet connection (the script pulls the UI library from GitHub at runtime).

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

Built on vindUI Reborn, with two tab groups:

Tab Group Tab Contents
RUNAWAYS Home KillAll NPCs, Walk Speed, NoClip, Inf Jump, Goto FinalDoor, GET 5 STARS
TELEPORT Vehicles Vehicle dropdown + teleport button

The window title is "RUNAWAYS" and includes a startup intro animation (skippable).

---

Notes & known quirks

· KillAll NPCs matches descendants named "Humanoid" and passes them to the damage remote. This mirrors the game's internal naming and is not the same as FindFirstChildOfClass("Humanoid").
· NoClip anti-void only triggers when you fall 100+ studs. Shallow falls are ignored, so small drops won't teleport you around.
· The Goto FinalDoor position is hard-coded to a specific map coordinate. It will break if the game's map is updated.
· GET 5 STARS reads checkpoint Z-values from HudGui.Distance.Progress if available; otherwise it falls back to {2500, 22000, 45000, 83700}.
· workspace.NPCs, workspace.Vehicles, and workspace.Map.Buildings.CustomsFinal are accessed directly without WaitForChild. If the game renames any of these, the corresponding feature will error.

---

Credits

· Original script: 100percent-imcooked-367 — Discord user ID 1330435022921924619
· Original file: Runaway.lua on Codeberg

```lua
loadstring(game:HttpGet("https://codeberg.org/100percent-imcooked-367/Scripts/raw/branch/main/Script/Runaway.lua"))()
```

This repository is only a modified version of the original script above. The changes are:

· Reformatted and de-obfuscated for readability (readable variable names, proper indentation, logical sectioning)
· Ported from the original Toraisme-modded UI to vindUI Reborn
· Fixed several shadowing bugs from the original mangled version (walk-speed slider, NoClip connection/lastSafeCFrame, anti-void raycast, vehicle dropdown selection, GET 5 STARS variable collisions)

All game logic, remote calls, and behavior are preserved from the original. Credit for the underlying script belongs entirely to the original author.

---

License

No license. Personal use only. Do whatever.
