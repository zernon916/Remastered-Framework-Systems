# Rush — remaining phases

**Open this file when the user says `Rush`.** Until then: documentation only. Do not implement phases from this list unless the user says **Rush**.

Author: Zernon916  
Written: 2026-08-16  
Updated: 2026-08-16 (all implementable Rush phases merged; waiting on playtest)  
Sources: `PHASES.md`, `HIJACK_ROADMAP.txt`, `COMMANDS.txt`, `PENDING_FIXES.md`, `GITHUB.md`, `docs/wiki/*`, `description.json`

This is the back-burner queue. Agents and the user **move items between the four lists** below. Do not invent extra phases.

**Restore point:** tag `rush-base` = `75abb2f0b7d5fdd97cad7a89547413efb0a796e1`. Revert a phase with `git revert <phase-commit>` or `git checkout rush-base -- <files>`. Independent branches still exist.

---

## How to execute Rush

When the user says **Rush**, work **TO BE EXECUTED from top to bottom** (one phase at a time):

1. Implement the next item in **TO BE EXECUTED**.
2. Local copy to `C:\sm\RFS` (and Workshop `3782487760` only if that is the live test pack) **only if Scrap Mechanic is not running** — quit `ScrapMechanic.exe` first. Then tell the user they can relaunch **Custom Game** to test.
3. Remove the item from **TO BE EXECUTED** and put it in **TO BE TESTED**.
4. Wait for the user to playtest.
5. If testing finds bugs: **stay in TO BE TESTED** until bugs are worked out.
6. If testing is good: move to **PENDING DONE**.
7. When **TO BE TESTED** is empty, **retest everything in PENDING DONE**, then move those items to **FINAL DONE**.

Do **not** git commit, steamcmd, or Workshop-publish unless the user explicitly asks. Phase E is gated (see that item).

---

## Frozen constraints (every Rush phase)

Apply these on every implement / copy / test cycle:

| Rule | Detail |
|------|--------|
| **No Fant** | Original RFS on Axolot Survival template. Do not copy, patch, or reuse Fant Mod files, scripts, or assets. |
| **No `g_survivalDev`** | Never force Survival's `g_survivalDev`. Cheats bind separately (`rfs_bindCommands`). Setting that flag breaks Survival tutorial / quest startup. |
| **Quit SM before local copy** | Before any copy to `C:\sm\RFS` or `C:\Steam\steamapps\workshop\content\387990\3782487760`, fully quit Scrap Mechanic (`ScrapMechanic.exe`). Do not force-kill unrelated Steam. After copy, user relaunches to test. |
| **Custom Game, not Mod Tool Test** | Playtest via Scrap Mechanic → **Custom Game** (Remastered / Recipe Framework Survival). Do not use Mod Tool Test as the play path. |
| **discord-bridge GitHub-only** | Companion lives at https://github.com/zernon916/Remastered-Framework-Systems (`discord-bridge/`). Older name `Recipe-Framework-Systems` redirects. **Not** in Steam / Workshop / local-backup packs. In-game Streamer still polls `%USER_DATA%/rfs_discord_bridge`. |
| **No Steam / Fant from doc workflow** | Push git from Desktop `C:\Users\benko\Desktop\RecipeFrameworkSurvival` only when the user asks (`GITHUB.md`). |
| **Nutt MiniMap credit shipped** | Workshop **3780282057**. Credit Nutt in Steam / `description.json` **and** in-game/docs. Subscribe World Map; do **not** enable it as a world mod. |
| **Do not stomp Orders GUI** | Battery spend, E open/close (`queueOpen` / `cl_rfs_ordersOpen`), and thin SHOW RANGE stay frozen. |
| **Intelligentia optional** | RFS remains the AI host. Official skip paste is `AUTHOR_SNIPPET/Intelligentia_ally_skip.lua` — optional, not a Rush phase. |

Typical local test dest: `C:\sm\RFS`. Workshop content dest (only after SM is quit, and only if that is the pack being tested): `C:\Steam\steamapps\workshop\content\387990\3782487760`. Roaming dest: `%AppData%\Axolot Games\Scrap Mechanic\User\User_76561198019395152\Mods\RemasteredFrameworkSurvival`.

---

## 1. TO BE EXECUTED

Remaining phases **not started or not finished**. Implement in this order. After implement, move the item to **TO BE TESTED**.

### R8 — Phase E — Steam Workshop push (gated)

**Source:** `PHASES.md` remaining **Phase E**.

**What “done” means:** Full menus / streamer / discord-batch **Workshop publish** of pack `3782487760` when the **user asks**.

**Likely files / tools:** steamcmd workflow the user already uses; `description.json` (Nutt MiniMap credit shipped); do **not** pack `discord-bridge/` into Workshop.

**Frozen extra:** **Do not steamcmd or Workshop-push unless the user explicitly asks for Phase E.** GitHub push is also ask-only (`GITHUB.md`). No `git push origin` unless asked.

---

## 2. TO BE TESTED

Implemented, waiting for the user to playtest. Bugs keep the item here until fixed. Testing good → **PENDING DONE**.

### R1 — Phase 2/5 polish (`rush/r1` `1ed3196`, merge `a21cd2a`)

Nametag numbers via `RfsHackText` plus `sm.gui.setCharacterDebugText` refresh. Custom names (`/botname`, E-on-bot rename, Orders NameEdit). `RfsBotHijack.allyIgnoresRaid` (farm/collect/oil outside home radius skip RAID jam/range mul). Melee-on-hit chain flavor (~5s). Raid jam callouts. Keep Seed N / type+number.

### R2 — Stay / Recall / `/botorder` / sentry (`rush/r2` `355eca4`, merge `b3b9b27`)

Modes `stay` / `recall` / `sentry`. Stay = leash at beacon tier 16/32/48. Recall = walk to Orders home (`workBeaconKey`), distinct from Return (hack device). `/botorder rest|defend|stay|recall|return|farm|collect|oil|sentry`. Tapebot Sentry in dropdown.

### R3 — Phase 3.5 pathfinding + painted chests (`rush/r3` `b9c0e9f`)

Farm / Collect / Oil walk to chests; doorway side-step if LOS blocked. Paint: **yellow = seeds**, **green = produce**, other/unpainted = drop-off. Assigned: same creation as the home beacon, or logic-connected to it. Does not scramble M1–M5 jobs.

### R4 — Phase 3.6 GUI visuals (`rush/r4` `45a039a`)

Player `/menu` GUI section (not Beacon Orders): Names on/off, Big Red farmbot label, Enemy/Neutral color cycle. **HP billboards** + **block overlay** completed on `rush/map-complete` `b6eb83f` (engine bars cannot be recolored; overlay is mass/shape-count).

### R6 — Phase 6 Map complete (`rush/map-complete` `b6eb83f`, prior HUD `rush/minimap` `24a3ad1` merge `7a89516`)

**MiniMap HUD is the Map phase**, not a sidecar. Nutt World Map HUD while Workshop **3780282057** is subscribed (do **not** enable World Map as a world mod). `/map` / `/rfsmap` / `/menu` Map open the atlas. Original RfsHud clock/compass/**ammo** kept (ammo lower-right). Fallback: lock-camera `/map`. Credit Nutt in `description.json`. Player.lua keeps **both** pickup-dupe carry hooks and Map toggle.

### R7 — Phase 7 Digital Signs (`rush/digital-signs` `c96b042`, merge `e6329b4`) + Inventory LCD (`rush/signs-lcd` `00f87dd`)

Craftbot Digital Sign S/L/XL. E edits text. Optional logic switch hides the face. No battery. Digital Sign keeps `f8c2a5e4-…`.

Inventory LCD S/L/XL UUIDs `3c06e928` / `4d17fa39` / `5e280b4a`: chest item + count. Weld/adjacent or LCD→chest wire. Small cycles one stack; L/XL scroll. Factory UUID not reused.

### Rename persist (`rush/rename-bots` `3cd2a9c`)

Orders Name+RENAME and E-on-bot APPLY persist in unit save data. Keep `queueOpen` / E / `cl_rfs_ordersOpen` (do not recreate GUI on the E frame).

### Pickup-dupe harden (`rush/pickup-dupe` `216143c`, merge `9c7b9c6`)

Carry/use: LMB while carrying a large pickup cannot clone the hotbar item. Keep with MiniMap `Player.lua` merge.

### Hack-block leftovers (pre-Rush; still verify)

Do not “fix” as Rush. Playtest and report:

- GitHub **#15–#20** (Color, Select, Seed names, Return, list 1 of N, Defend/Hay/Tote/Water) and **#6** SHOW RANGE
- Select / Color stick after list refresh
- Return (walk to converting hack device)
- Seed nametags (`Seed N` not `Bot N`)
- CLEAR MASTER persist
- Thin SHOW RANGE (do not thicken / recolor / rehost onto the beacon electrical net)
- Multi-select
- Caps 2 / 4 / 6
- Master-off split (**parked** — do not “fix” re-split)
- Orders menu visible with cursor
- Battery spend unchanged
- E open/close: `queueOpen` / `cl_rfs_ordersOpen` (do not recreate GUI on the E frame)

---

## 3. PENDING DONE

User tested, bugs worked out. When **TO BE TESTED** is empty, **retest all of this list**, then move to **FINAL DONE**.

_(empty)_

---

## 4. FINAL DONE

Retested after the queue emptied. Shipped / confirmed.

_(empty — use **Already shipped (not Rush)** below for historical DONE, not this list.)_

---

## CUT (not shipping)

Dropped from the playable pack. Do not re-implement unless the user asks.

### R5 — Phase 4 factories — CUT (`rush/cut-factories` `f9026e4`)

**Not worth the lag.** Ally Factory unwired: no `RfsFactory`, no Hideout 200 Farmers listing, no factory shape. Digital Sign keeps `f8c2a5e4-…`. **Hideout 1 crate→80 seed trades kept.** Historical implement: `rush/factories` `46cf97e`, merge `1d5a861`.

---

## UNSURE / CHECK WITH ME

Do not silently drop or “fix” these:

- **Digital Signs:** no ON/OFF dual messages; no Hideout trade; vanilla Survival textsigns stay non-logic; reuses Survival `DigitalSign.gui` (no dedicated MyGUI layout)
- **Factories:** CUT — not worth the lag (`rush/cut-factories`). Do not restore unless asked. Crate→80 seed trades stay.
- **CHAIN:** melee flavor shipped in R1; larger CHAIN rewrite not done
- **MiniMap / Map:** letters / fog / GPS not v1; World Map must stay subscribed, not enabled as a world mod
- **Master-off split:** parked, do not “fix” as Rush
- **Block health overlay:** shipped best-effort (look-at HUD + world text + nearby creation mass/shape-count). SM has no per-block HP API — do not expect a damaged-block gradient
- **Unit HP bars:** custom billboards colored by Enemy/Neutral `/menu` settings (engine bars cannot be recolored). Allies/hacked bots use Neutral
- **Cotton in autumn:** not an RFS fix
- **Connection tool for chests:** no new tool; weld to beacon creation or Connect Tool logic to the beacon

---

## Already shipped (not Rush)

Do not re-open these as Rush phases. Sources: `PHASES.md` DONE, `HIJACK_ROADMAP.txt` Phase 1 / 2 lite / 3 `[DONE]` / 5 lite, `PENDING_FIXES.md`.

| Area | What shipped |
|------|----------------|
| Menus / GenSettings | Host `/setup` + `/gensettings`; player `/menu`; `RfsFeatures` / `RfsGenGui` (MAIN / FEATURES / STREAMERS / DISCORD) |
| Phase A | `discord-bridge` on GitHub only (not in Steam packs) |
| Phase B | Streamer harden + Discord → game chat (`RfsStreamer`, `chat-relay.js`, `RfsChatRelay.lua`) |
| Phase C | `vote_result.json` + vote-resolve; allowlist UI |
| Phase D | `/say` + `/d` → `chat_outbox.json` → Discord (gated) |
| Phase F / hijack lite | Identity persist + nametag hooks; light chain convert; `/unhijack`; underground miner/cable flag (default ON) |
| Phase 1 hijack | `/hijack`, `/hijacklist`, `/givehack`; Hack 16 / Control 32 / Infection 48; Hideout 20/50/120 Farmers; tether hop; cheat infect |
| Phase 3 jobs (M1–M5) | Rest/Defend, Hay Farm, Tote Collect, Waterbot Collect Oil, colors, Master/Slave, usable E, raid-list clear, icon+number list |
| Phase 5 lite | `/unhijack`; `hackUndergroundBots`; ally FF gated |
| Craftbot extras | Client merge GUI — DONE (`PENDING_FIXES.md` §1) |
| Cotton in autumn | Investigated, **not an RFS fix** — do not Rush |
| rush-base extras | Host/admin cheat gating, public `/rfsmenu`, hideout 1-crate→80 seed trades, weapon ammo HUD |

Optional, not a phase: Intelligentia `AUTHOR_SNIPPET/Intelligentia_ally_skip.lua`.

---

## Per-phase commits (this Rush)

| Item | Branch | Tip commit | Merge on main |
|------|--------|------------|---------------|
| Restore | `rush-base` tag | `75abb2f` | — |
| R1 Phase 2/5 | `rush/r1` | `1ed3196` | `a21cd2a` |
| R2 Stay/Recall | `rush/r2` | `355eca4` | `b3b9b27` |
| R3 pathfinding | `rush/r3` | `b9c0e9f` | (on main) |
| R4 GUI visuals | `rush/r4` | `45a039a` | (on main) |
| R5 factories | `rush/cut-factories` | `f9026e4` CUT | `f9026e4` (fast-forward) |
| R6 MiniMap HUD | `rush/minimap` | `24a3ad1` | `7a89516` |
| R6 Map complete | `rush/map-complete` | `b6eb83f` | `4366b97` |
| R7 Digital Signs | `rush/digital-signs` | `c96b042` | `e6329b4` |
| Inventory LCD | `rush/signs-lcd` | `00f87dd` | `b72e7c7` |
| Rename persist | `rush/rename-bots` | `3cd2a9c` | `00fa455` |
| Pickup-dupe | `rush/pickup-dupe` | `216143c` | `9c7b9c6` |
| R8 Phase E | — | — | gated |

---

## Pointers

| Doc | Role |
|-----|------|
| `PHASES.md` | High-level DONE vs remaining |
| `HIJACK_ROADMAP.txt` | Hijack / Orders / MiniMap / Signs detail |
| `PENDING_FIXES.md` | Open polish + parked SHOW RANGE |
| `COMMANDS.txt` | Player commands + Phase 3 status note |
| `GITHUB.md` | Git push from Desktop folder, ask-only |
| `docs/wiki/Home.md` | Wiki index (shipped vs roadmap) |
| `docs/wiki/Known-Issues.md` | Open polish + shipped 3.5 / 3.6 |
| `description.json` | Steam blurb; Nutt MiniMap credit shipped |
