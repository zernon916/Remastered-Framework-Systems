# Commands

Host / single-player unless noted. Chat cheats default from `rfs_settings.json` (`"cheats": true`). Host `/gensettings` can override per world.

Full list: pack file `COMMANDS.txt`.

## Everyone

| Command | What it does |
|---------|----------------|
| `/menu` | Player menu (Map, growth, HP bars, block overlay) |
| `/help` / `/commands` | Command summary |
| `/map` / `/rfsmap` | Full atlas (Nutt World Map) when subscribed; else top-down camera |
| `/mapclose` | Close atlas / map camera |

**Phase 3.6 GUI (shipped):** `/menu` Names, Big Red, Enemy/Neutral HP billboard colors, block/creation overlay. Engine HP bars cannot be recolored. Overlay is mass/shape-count (no per-block HP API). See [[Known-Issues]] / `HIJACK_ROADMAP.txt`.

**Phase 6 Map (complete):** MiniMap HUD is part of the map, not a sidecar. Always-on corner HUD while you walk; `/map` / `/rfsmap` / `/menu` Map open Nutt's full atlas. Credit **Nutt** / Workshop [3780282057](https://steamcommunity.com/sharedfiles/filedetails/?id=3780282057). Subscribe to **World Map** and do **not** enable it as a world mod. If that pack is missing, original clock/compass/ammo HUD and lock-camera `/map` stay. Beacon/ally letter markers later. See [[Known-Issues]] / `HIJACK_ROADMAP.txt`.

**Digital Signs** (Phase 7 minimum): Craftbot Digital Sign S/L/XL. E to edit text. Optional logic switch hides the face. **Inventory LCD** S/L/XL: weld to a chest or connect LCD → chest to show item + count (L/XL scroll). See [[Known-Issues]].

## Host setup

| Command | What it does |
|---------|----------------|
| `/setup` | World setup GUI (Main / Farming / Quest / Inventory) |
| `/gensettings` | Gen settings tabs: MAIN / FEATURES / STREAMERS / DISCORD |

## Hijack

| Command | What it does |
|---------|----------------|
| `/hijack [range]` | Cheat: permanently infect nearest hostile robot (default 16 m) |
| `/hijacklist` | Count tethered vs infected allies |
| `/unhijack [range]` | Release nearest owned ally (default 16 m). Host may release any. Not a raid ban. |
| `/givehack` | Give Hack + Control + Infection Beacons (needs RFS Beacons B&P) |

## Shops / currency (cheats)

| Command | What it does |
|---------|----------------|
| `/tshop` | Open Farmers Hideout trader remotely |
| `/mshop` | Open Mining Hub trader remotely |
| `/farmers [qty]` | Give Farmers (default 10) |
| `/unlockmodded` | Unlock scanned mod Craftbot recipes |
| `/mods` | Show scanned mod sources |

## Dev / survival (when cheats on)

Examples: `/god`, `/fly`, host `/unlimited` (unlocks **everyone** — chat warns), `/limited`, `/die`, `/unstuck`, `/sethp`, `/timeofday`, `/weather`, `/clearinv`, `/cleanup`, `/killall`, `/give`, `/spawn`, `/goto`, quest cmds (`/questlist`, `/startquest`, `/completequest`, …).

Also available from Survival when bound: `/kick`, `/ban`, `/stopraid`, `/disableraids`, etc.
