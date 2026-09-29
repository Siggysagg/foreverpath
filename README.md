# ForeverPath

<!-- foreverpath:download -->
## ⬇️ Download — v0.6.0

- **Direct download:** [ForeverPath.zip](https://github.com/Siggysagg/foreverpath/releases/latest/download/ForeverPath.zip) — unzip and copy the `ForeverPath` folder into `Interface/AddOns`.
- **WowUp (auto-updates):** Get Addons → **Install from URL** → `https://github.com/Siggysagg/foreverpath`
- **Browse the files:** the addon itself is in the [`ForeverPath/`](https://github.com/Siggysagg/foreverpath/tree/main/ForeverPath) folder of this repository.
<!-- /foreverpath:download -->

**A lightweight progression guide for WoW Forever.**

ForeverPath helps you make clearer next-step choices while you play. It gives compact, readable tips for quests, gear and professions, and updates recommendations as your character changes.

> **Status:** `v0.6.0` — early testing release for WoW Forever.

## What it does

- Shows a compact recommendation card during normal play
- Compares quest rewards with your equipped gear when the client provides enough information
- Supports goal styles for leveling, gear, professions and balanced progression
- Explains the main reason behind a recommendation
- Handles missing or uncertain data conservatively
- Includes a demo mode with clearly marked synthetic examples

ForeverPath runs locally inside the game. It does not make live AI requests or require an external service while you play.

## Install

1. Download the latest beta from [Releases](https://github.com/Siggysagg/foreverpath/releases).
2. Unzip the download.
3. Copy the `ForeverPath` folder into your WoW Forever `Interface/AddOns` folder.
4. Start the game and enable **ForeverPath** on the character selection screen.
5. Use `/fp` in-game to open the addon.

The beta is experimental. The exact supported client build and some in-game compatibility details are still being verified.

## Useful commands

```text
/fp              Open ForeverPath
/fp compact      Toggle the compact recommendation card
/fp demo         Show synthetic demo recommendations
/fp goal leveling
/fp goal gear
/fp goal professions
/fp goal balanced
```

## Feedback

Please report bugs and include:

- WoW Forever client build and language
- What you were doing when the issue appeared
- Any Lua error text
- The output of `/fp diag` when relevant

## License

The addon code is MIT licensed. Game-data files carry their own attribution and license information. See the license files included in the download.

This project is independent of Blizzard Entertainment.
