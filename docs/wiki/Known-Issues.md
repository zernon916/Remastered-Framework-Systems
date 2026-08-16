# Known issues

Open polish only. Do not treat these as shipped features. Sources: `PENDING_FIXES.md`, `HIJACK_ROADMAP.txt`, `COMMANDS.txt`.

WIP note (2026-08-15): local **HACK 3.10** — not all on GitHub (push freeze).  
Orders checklist: `HIJACK_ROADMAP.txt` Phase 3 (`[DONE]` / `[NEXT]` / `[FUTURE]`).

## [NEXT] — verify during HACK 3.10

- Confirm Orders: open + list fill + icons/H1 fallback + close/reopen + Prev/Next safe
- SHOW RANGE ground ring (Game-hosted; menu no longer dies)
- List click Select; Color selected or all (tint must stick)
- Seedbot nametag **Seed N** (not Bot N)
- Return order (walk to converting hack device)
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

## Pathfinding & painted chests — **[DONE]** (Phase 3.5)

Farm / Collect / Oil walk to chests; doorway side-step if line of sight is blocked. Paint yellow = seeds, green = produce, other/unpainted = drop-off. Chests on the beacon creation or logic-connected to the beacon are assigned. Cross-ref: `HIJACK_ROADMAP.txt` Phase 3.5.

## Menu tab: GUI visuals — **[DONE]** (Phase 3.6)

Player `/menu` GUI section: Names on/off, Farmbots as **Big Red**, enemy/neutral color cycle. Custom HP billboards on units (engine HP bars cannot be recolored). Block/creation overlay is best-effort look-at HUD + world text (mass/shape-count; no per-block HP API). Cross-ref: `HIJACK_ROADMAP.txt` Phase 3.6.

## Map — **complete** (Phase 6)

Always-on corner MiniMap while walking is part of the Map phase; `/map` / `/rfsmap` / `/menu` Map open the full atlas. Terrain map by **Nutt** (Workshop **3780282057** World Map) — credited in Steam / `description.json` / in-game chat. Subscribe to World Map; do **not** enable it as a world mod. Fallback if that content is missing: original RfsHud (clock + compass + **ammo**) and lock-camera `/map`. Beacon/ally letter markers later. Cross-ref: `HIJACK_ROADMAP.txt` Phase 6, `PHASES.md`, `PENDING_FIXES.md` §6.

## Digital Signs — **[DONE minimum]** (Phase 7)

Craftbot **Digital Sign** S / L / XL. Press **E** to type text (Survival Digital Sign GUI). Optional logic switch: no parent = always show; wired + off = hide. Logic output follows display-on. No battery. Vanilla Survival textsigns stay non-logic.

Gaps (spec was high-level only): no ON/OFF dual messages; no Hideout trade; no dedicated MyGUI layout.

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
