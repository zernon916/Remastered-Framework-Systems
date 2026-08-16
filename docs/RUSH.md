# Rush — remaining phases

**Open this file when the user says `Rush`.** Until then: documentation only. Do not implement phases from this list unless the user says **Rush**.

Author: Zernon916  
Written: 2026-08-16  
Sources: `PHASES.md`, `HIJACK_ROADMAP.txt`, `COMMANDS.txt`, `PENDING_FIXES.md`, `GITHUB.md`, `docs/wiki/*`, `description.json`

This is the back-burner queue. Agents and the user **move items between the four lists** below. Do not invent extra phases. Do not execute while another agent is repairing the Orders menu.

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
| **Nutt credit only when MiniMap ships** | Workshop **3780282057**. Credit Nutt in Steam / `description.json` **and** in-game/docs **when Phase 6 is implemented**, not before. Do not copy that mod until permission is confirmed. |
| **Do not stomp NOW Orders GUI** | See **NOW / not Rush**. Battery spend, E open/close, and thin SHOW RANGE are frozen. |
| **Intelligentia optional** | RFS remains the AI host. Official skip paste is `AUTHOR_SNIPPET/Intelligentia_ally_skip.lua` — optional, not a Rush phase. |

Typical local test dest: `C:\sm\RFS`. Workshop content dest (only after SM is quit, and only if that is the pack being tested): `C:\Steam\steamapps\workshop\content\387990\3782487760`.

---

## NOW / not Rush

**Do not treat the current Orders GUI repair as a Rush phase.** Another agent is repairing an invisible Orders menu. Rush must **not** stomp:

- **Battery** spend / circuit (`RfsHackBeacon` consume path — user called it perfect)
- **E open/close** — `queueOpen`, E, `cl_rfs_ordersOpen`, do not recreate GUI on the E frame
- **SHOW RANGE thin** — user likes the thin Game-hosted ring; do not thicken, recolor, or rehost range FX onto the beacon electrical net
- In-flight items: **rebind** (select / color / SHOW RANGE on every list refresh), **Return**, **Seed nametags** (`Seed N` not `Bot N`), **CLEAR MASTER** persist, **Master-off split later** (parked; do not “fix” re-split as part of Rush)
- GitHub issues **#15–#20** (and still-open **#6** SHOW RANGE): [Color](https://github.com/zernon916/Remastered-Framework-Systems/issues/15), [Select](https://github.com/zernon916/Remastered-Framework-Systems/issues/16), [Seed names](https://github.com/zernon916/Remastered-Framework-Systems/issues/17), [Return](https://github.com/zernon916/Remastered-Framework-Systems/issues/18), [#19 list 1 of N](https://github.com/zernon916/Remastered-Framework-Systems/issues/19), [#20 Defend/Hay/Tote/Water](https://github.com/zernon916/Remastered-Framework-Systems/issues/20)

Off-limits for Rush until the user says the Orders menu is stable: `Gui/Layouts/Rfs_BeaconOrders.layout`, `Scripts/game/RfsBeaconOrdersGui.lua`, `Scripts/game/RfsBotHijack.lua`, `Scripts/game/RfsHijackHost.lua`, `Scripts/game/interactables/RfsHackBeacon.lua`, `Scripts/Game.lua` (Orders RPC / range viz / E bind). Later Rush phases that need those files (Stay / Recall / `/botorder` / RAID filter / naming) **wait** until NOW is done, then touch them without regressing the bullets above.

Shipped Phase 3 jobs (M1–M5 Rest/Defend/Farm/Collect/Oil, Master/Slave, colors, usable E) stay as-is. Rush does not re-implement them.

---

## 1. TO BE EXECUTED

Remaining phases **not started or not finished**. Implement in this order. After implement, move the item to **TO BE TESTED**.

---

### R1 — Phase 2/5 full polish (identity + RAID)

**Source:** `PHASES.md` remaining **Phase 2/5 full polish**; `HIJACK_ROADMAP.txt` Phase 2 full / Phase 5 full; `PENDING_FIXES.md` §3a–3c; wiki [[Known-Issues]]; `COMMANDS.txt` hijack polish.

**What “done” means:**

- **Numbers above bots** — idle identity + numbers actually render on clients (issue #2 style). Phase 2 lite claimed `pushTag`; world type+number tags exist but numbers still incomplete/missing.
- **Bot naming** — player can set a custom name via **E on bot** *or* rename through the hack device / Orders GUI. Names show above the head **with** the numbers.
- **RAID farm-range filter** — bots **out of range of farms** must **not** take RAID jam / range mul / raid notes (`RfsBotHijack`). Keep out-of-range farm bots out of RAID behavior.
- **Melee-on-hit chain flavor** — light extra flavor on melee hit (beyond the shipped ~15 s / 10 m chain convert). Respect `hackableRobots`, underground flag, no new chains in raid, never undo raid bans.
- **Richer raid help / callouts** — beyond Phase 5 lite; identity/release UI polish as needed.

**Likely files:** `Scripts/game/RfsBotHijack.lua`, `Scripts/game/RfsHijackHost.lua`, `Scripts/game/interactables/RfsHackBeacon.lua`, `Scripts/game/RfsBeaconOrdersGui.lua` (rename via device), `Scripts/Game.lua` (only if E-on-bot needs a client RPC — **after NOW is stable**).

**Frozen extra:** Do not start this while NOW Orders GUI is in flight. Do not change battery, E open/close, or thin range. Nametag work must keep Seed N / type+number behavior.

---

### R2 — Phase 3 leftovers (Stay / Recall / chat `/botorder` / tapebot sentry)

**Source:** `PHASES.md` remaining **Phase 3 — farm orders** (core M1–M5 already shipped; this is the unfinished tail); `HIJACK_ROADMAP.txt` Phase 3 `[FUTURE]`; `PENDING_FIXES.md` §3 `[FUTURE]`; wiki [[Bot-Orders]] / [[Known-Issues]] Recall/Stay.

**What “done” means:**

- **Stay in area** — Orders checkbox: leash / stay near beacon job range (16 / 32 / 48 m).
- **Recall bots** — order allies back to the beacon (distinct from shipped **Return**, which walks each bot to **its** converting hack device `hackBeaconKey`).
- **chat `/botorder`** — host/player chat path for the same order modes (optional if GUI is the source of truth; ship if it does not fight the GUI).
- **Tapebot ranged sentry** — per-type flavor from the roadmap (tapebot sentry; farmbot stays Rest+Defend / tank escort). Do not redo Hay Farm / Tote Collect / Waterbot Oil.

**Likely files:** `Scripts/game/RfsBotOrders.lua`, `Scripts/game/RfsBotOrdersFarm.lua`, `Scripts/game/RfsBotOrdersCollect.lua`, `Scripts/game/RfsBotOrdersOil.lua`, `Scripts/game/RfsBeaconOrdersGui.lua`, `Gui/Layouts/Rfs_BeaconOrders.layout`, `Scripts/Game.lua` (chat bind), `COMMANDS.txt` / wiki [[Bot-Orders]] when behavior ships.

**Frozen extra:** **After NOW is stable.** Do not restyle SHOW RANGE. Do not recreate Orders GUI on the E frame. Do not change battery spend. Return stays “walk to own hack device.”

---

### R3 — Phase 3.5 — pathfinding & painted chests

**Source:** `PHASES.md` **Phase 3.5**; `HIJACK_ROADMAP.txt` Phase 3.5; `PENDING_FIXES.md` §4; wiki [[Known-Issues]] / [[Bot-Orders]].

**What “done” means:**

- Bots find chests and go through doorways more reliably than vanilla unit AI chase (Farm / Collect / Oil jobs).
- Painted / assigned chests: color-coded roles (e.g. seeds vs veggies/fruits vs drop-off) and optional connection tool to assign chests to a beacon / Orders domain.
- Does not scramble shipped Phase 3 job modes.

**Likely files:** `Scripts/game/RfsBotOrders*.lua`, possible new `Scripts/game/RfsBotPath.lua` (or similar), chest paint / connect interactable under `Scripts/game/interactables/`, hijack/orders domain keys in `RfsBotHijack.lua` / `RfsHackBeacon.lua`.

**Frozen extra:** Place **before Phase 4 factories**. Do not replace job logic; improve navigation + deposit targeting. No Fant pathing assets.

---

### R4 — Phase 3.6 — Menu tab: GUI (visuals)

**Source:** `PHASES.md` **Phase 3.6**; `HIJACK_ROADMAP.txt` Phase 3.6; `PENDING_FIXES.md` §5; wiki [[Commands]] / [[Known-Issues]].

**What “done” means:**

Player or host visual prefs (prefer `/menu` or `/gensettings` FEATURES / GUI tab — **not** Beacon Orders):

1. **Names** — toggle names above bots (world nametags on/off).
2. **Big Red** — farmbots display as “Big Red” instead of generic Farm / type name.
3. **Health bar (Enemy)** — default red; color dropdown.
4. **Health bar (Neutral)** — default green; color dropdown (ally / neutral).
5. **Block health overlay** — green → red for damaged blocks. **Research / feasibility only:** ship only if SM API allows; else cut.

**Likely files:** `Scripts/game/RfsMenuGui.lua`, `Gui/Layouts/Rfs_Menu.layout`, and/or `Scripts/game/RfsGenGui.lua`, `Gui/Layouts/Rfs_GenSettings.layout`, `Scripts/game/RfsFeatures.lua`, `Scripts/game/RfsBotHijack.lua` (nametag gate), `Scripts/Game.lua` (tab bind). MiniMap toggle on this tab is **optional later** (Phase 6), not required here.

**Frozen extra:** After Phase 3.5 (roadmap). Does not block pathfinding or factories. Do not put these toggles on Beacon Orders.

---

### R5 — Phase 4 — factories

**Source:** `PHASES.md` **Phase 4**; `HIJACK_ROADMAP.txt` Phase 4.

**What “done” means:**

- Craftable factory interactable (Intelligentia **or** RFS part) that spends resources to `sm.unit.createUnit(uuid, pos, yaw, { playerAlly=true, color=..., tetherPoint=... })`.
- Capsules stay hostile (vanilla); factory is the ally spawner.
- Caps on army size.
- Optional flavor: tapebot assembly line, haybot “barn”, farmbot “garage”.

**Likely files:** new interactable under `Scripts/game/interactables/`, `CraftingRecipes/craftbot.json` and/or Hideout trades, `Scripts/game/RfsBotHijack.lua` (ally create / cap), `Scripts/Game.lua` (dofile), Beacons B&P only if a new shape lives there.

**Frozen extra:** After 3.5 (jobs navigate first). Do not auto-unlock recipes. Hideout currency stays Farmers. Optional Intelligentia restyle later; RFS remains AI host.

---

### R6 — Phase 6 — MiniMap (HUD)

**Source:** `PHASES.md` **Phase 6**; `HIJACK_ROADMAP.txt` Phase 6; `PENDING_FIXES.md` §6; `COMMANDS.txt` Map; wiki [[Known-Issues]] / [[Commands]]; `description.json` (credit **when shipped**).

**Status today:** PLANNED, **not in current build**. Clock + compass HUD (`RfsHud`) and locked `/map` camera only.

**What “done” means:**

- Always-on or toggle **corner HUD minimap** so the player can walk while it updates. Square/rounded widget is enough for v1.
- Refine existing `/map` as the full map (live camera). Optional: HUD click or `/menu` Map opens it. Keep lock/fallback polish.
- Markers: player (heading), powered beacons, allies. Letters later (H1/T2-style, after naming / Orders badges).
- Hide HUD map while chat/other GUIs are open (engine layering).
- **Preferred path:** after **permission from Nutt**, incorporate minimap + map from Steam Workshop **3780282057**. Then credit Nutt in Steam / `description.json` **and** in-game/docs. Do **not** rewrite Steam text until the feature ships.
- **Fallback:** if permission or code cannot ship, original RFS HUD schematic (biome/grid from `sm.storage.loadTerrainData`). Study 3780282057 approach only; **do not port** their scripts, layouts, tile-photo atlas, GPS tool, or assets.
- No GPS item required (`/map` exists). Fog of war / waypoints: not v1.

**Likely files:** `Scripts/game/RfsHud.lua`, `Gui/Layouts/Rfs_Hud.layout`, `Scripts/game/interactables/RfsMapLock.lua`, `Scripts/game/RfsMenuGui.lua`, `Scripts/Game.lua` / Player client tick, `description.json` + `STEAM_DESCRIPTION.txt` **only when shipping**, wiki [[Commands]] / `COMMANDS.txt` / `README.txt`.

**Frozen extra:**

- **WAITING ON PERMISSION** before any copy of 3780282057.
- Credit Nutt **when implemented**, not before.
- Do not replace `/map` with someone else's atlas screen on the fallback path.
- Optional size/corner prefs may share the Phase 3.6 GUI tab.
- After 3.6 on the roadmap; does **not** block factories or Orders.

---

### R8 — Phase E — Steam Workshop push (gated)

**Source:** `PHASES.md` remaining **Phase E**.

**What “done” means:** Full menus / streamer / discord-batch **Workshop publish** of pack `3782487760` when the **user asks**.

**Likely files / tools:** steamcmd workflow the user already uses; `description.json` (do not add Nutt credit unless Phase 6 shipped); do **not** pack `discord-bridge/` into Workshop.

**Frozen extra:** **Do not steamcmd or Workshop-push during Rush unless the user explicitly asks for Phase E.** GitHub push is also ask-only (`GITHUB.md`). This item stays in TO BE EXECUTED until that ask.

---

## 2. TO BE TESTED

Implemented, waiting for the user to playtest. Bugs keep the item here until fixed. Testing good → **PENDING DONE**.

### R7 — Phase 7 — Digital Signs (minimum)

Craftbot Digital Sign S/L/XL. E edits text via Survival Digital Sign GUI. Optional logic switch hides the face; logic output follows display-on. No battery. Isolated on `rush/digital-signs`.

**Gaps (spec was high-level only):** no ON/OFF dual messages; no Hideout trade; vanilla Survival textsigns stay non-logic; no dedicated MyGUI layout (reuses Survival `DigitalSign.gui`).

---

## 3. PENDING DONE

User tested, bugs worked out. When **TO BE TESTED** is empty, **retest all of this list**, then move to **FINAL DONE**.

_(empty)_

---

## 4. FINAL DONE

Retested after the queue emptied. Shipped / confirmed.

_(empty — use **Already shipped (not Rush)** below for historical DONE, not this list.)_

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
| Phase 3 jobs (M1–M5) | Rest/Defend, Hay Farm, Tote Collect, Waterbot Collect Oil, colors, Master/Slave, usable E, raid-list clear, icon+number list — **GUI still being repaired under NOW** |
| Phase 5 lite | `/unhijack`; `hackUndergroundBots`; ally FF gated |
| Craftbot extras | Client merge GUI — DONE (`PENDING_FIXES.md` §1) |
| Cotton in autumn | Investigated, **not an RFS fix** — do not Rush |

Optional, not a phase: Intelligentia `AUTHOR_SNIPPET/Intelligentia_ally_skip.lua`.

---

## Suggested Rush night order (short)

1. R1 Phase 2/5 polish (numbers, naming, RAID filter, melee-chain, raid callouts)  
2. R2 Phase 3 leftovers (Stay, Recall, `/botorder`, tapebot sentry)  
3. R3 Phase 3.5 pathfinding + painted chests  
4. R4 Phase 3.6 GUI visuals tab  
5. R5 Phase 4 factories  
6. R6 Phase 6 MiniMap (permission / Nutt credit / fallback)  
7. R7 Phase 7 Digital Signs — **TO BE TESTED** (this branch)  
8. R8 Phase E Workshop — **only if the user asks**

If NOW Orders GUI is still broken when Rush starts: **skip R1–R2** (they share hijack/Orders files) and start at **R3** only if those files are untouched — otherwise wait.

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
| `docs/wiki/Known-Issues.md` | Open polish + future phases |
| `description.json` | Steam blurb; Nutt credit **when MiniMap ships** |
