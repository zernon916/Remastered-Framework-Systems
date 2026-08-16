# Known issues

Open polish only. Do not treat these as shipped features. Sources: `PENDING_FIXES.md`, `HIJACK_ROADMAP.txt`, `COMMANDS.txt`.

WIP note (2026-08-15): local **HACK 3.10** — not all on GitHub (push freeze).  
Orders checklist: `HIJACK_ROADMAP.txt` Phase 3 (`[DONE]` / `[NEXT]` / `[FUTURE]`).

## [NEXT] — verify during HACK 3.10

- Confirm Orders: open + list fill + icons/H1 fallback + close/reopen + Prev/Next safe
- SHOW RANGE ground ring actually visible (menu no longer dies — ring polish parked)
- Empty-list / reopen regressions — watch during test

## Nametag numbers — **[NEXT]**

Idle identity / numbers above hijacked bots are incomplete or missing (issue #2 style). Phase 2 lite claimed overhead via `pushTag`. World type+number tags / half-size landed in Orders polish; issue-#2-style numbers still need verification.

## Bot naming / rename UI — **[NEXT]**

No shipped way yet to set a custom bot name via:

- **E on bot**, or
- rename through the hack device / Orders GUI

Desired: names show above the head **with** the numbers.

## RAID farm-range filter — **[NEXT]**

Bots that are **out of range of farms** should **not** be affected by RAID jam / range mul / raid notes. Still open in Phase 5 polish.

## Pathfinding & painted chests — **[FUTURE]** (Phase 3.5)

Not started. Farm / Collect / Oil still use vanilla unit AI navigation. Planned: reliable pathfinding through doorways to chests, plus painted / assigned chests (color roles + optional connection tool to beacon Orders domain). Cross-ref: `HIJACK_ROADMAP.txt` Phase 3.5, `PENDING_FIXES.md` §4, [[Bot-Orders]].

## Menu tab: GUI visuals — **[FUTURE]** (Phase 3.6)

Not started (do not build during HACK 3.10 testing). Planned player/host visual prefs — Names on/off, Farmbots as **"Big Red"**, enemy/neutral health-bar color dropdowns, and a block health overlay (green→red) only if SM exposes damage visuals. Menu home TBD (`/menu` or `/gensettings` FEATURES/GUI). Relates to Phase 2 nametag/naming polish and Orders type+number badges. Cross-ref: `HIJACK_ROADMAP.txt` Phase 3.6, `PENDING_FIXES.md` §5.

## MiniMap HUD — **[FUTURE]** (Phase 6)

**Planned, not in current build.** Do not implement or copy yet. Always-on or toggle corner HUD minimap; refine existing `/map` live camera; markers for player, beacons, allies (letters later). **Preferred path:** after permission from Nutt (Workshop **3780282057**), incorporate that minimap + map. Credit Nutt in Steam / `description.json` **and** in-game/docs **when implemented**. **Fallback:** original RFS HUD schematic if permission or code cannot ship — study approach only, no copy. Today we have clock+compass HUD and a locked top-down camera, not a walking HUD map. Cross-ref: `HIJACK_ROADMAP.txt` Phase 6, `PHASES.md`, `PENDING_FIXES.md` §6.

## Digital Signs — **[FUTURE]** (Phase 7)

Not started. Later systems stretch after MiniMap / factories. Flesh out later — not a full spec. Does not scramble shipped Phase 3.

- Can be connected to logic
- Can actually show information on them

Cross-ref: `HIJACK_ROADMAP.txt` Phase 7, `PENDING_FIXES.md` §7.

## Recall bots / Stay in area — **[FUTURE]** (end of Phase 3)

After SHOW RANGE ring polish: recall allies to beacon; Orders checkbox leash / stay near range. See `HIJACK_ROADMAP.txt` Phase 3 [FUTURE].

## Cotton in autumn

Not an RFS bug. Vanilla places world cotton in autumn forest interiors; easy to miss (small scale / short view distance). See `PENDING_FIXES.md` section 2.

## [DONE] recently (Orders / this pack — local HACK 3.10)

- M1–M5 jobs, Master/Slave, color presets, `usable:true` E on beacons
- Raid list clear on destroy/capture
- Nametag half size; type+number world tags; Orders icon+number (NodeIcons / H1 fallback)
- Orders open / close / reopen + list fill (HACK 3.5+ / 3.9)
- SHOW RANGE no longer kills menu (ring visibility still [NEXT])
- Prev/Next hide on 1 page (verify under [NEXT])
- Ally color presets UI; Craftbot client extras (earlier push)

Quit Scrap Mechanic fully and reload the Workshop / `C:\sm\RFS` pack after syncing before testing.
