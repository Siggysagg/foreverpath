# ForeverPath

<!-- foreverpath:download -->
## ⬇️ Download — v0.7.2

- **Direct download:** [ForeverPath.zip](https://github.com/Siggysagg/foreverpath/releases/latest/download/ForeverPath.zip) — unzip and copy the `ForeverPath` folder into `Interface/AddOns`.
- **WowUp (auto-updates):** Get Addons → **Install from URL** → `https://github.com/Siggysagg/foreverpath`
- **Browse the files:** the addon itself is in the [`ForeverPath/`](https://github.com/Siggysagg/foreverpath/tree/main/ForeverPath) folder of this repository.
<!-- /foreverpath:download -->

**A lightweight progression guide for WoW Forever.**

ForeverPath tells you what to do next while you level — and explains why. It follows
your route, compares quest rewards against your equipped gear, and updates its
recommendations as your character changes. Everything runs locally inside the game.

> **Status:** `v0.7.2` — early testing release for WoW Forever.

## What it does

- A clear **NOW panel**: your next route step with objective progress and distance
- **Dungeon leveling** playstyle, including your own imported route (`/fp route`)
- **Share your route** with friends as a pasteable string
- **Upgrade finder**: the best available quest reward per gear slot, in percent
- Quest reward comparison with your equipped gear, in the quest dialog
- The **why** behind every recommendation, with visible sources and confidence
- Session stats (XP/hour, time to level) and a CPU meter — built to stay cheap
- Plays styles: Speedrun, Balanced, Gear first, Story, Dungeon

## Install

1. **WowUp (auto-updates):** Get Addons → **Install from URL** → paste this repository's URL.
2. **Manual:** download `ForeverPath.zip` from Releases, unzip, and copy the `ForeverPath`
   folder into `Interface/AddOns/`.
3. Start the game and type `/fp`.

## Notes

- Runs entirely locally: no live AI requests or external services while you play.
- No player names or account data are collected; `/fp diag` output is safe to share.
- Built for the WoW Forever client; report issues in the Forever Discord channel.
