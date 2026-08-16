# Bot Orders

Opened with **E** on a **powered** Hack / Control / Infection beacon. Modes depend on bot type.

WIP note (2026-08-15): local **HACK 3.10** GUI polish — not all on GitHub (push freeze).  
Full checklist: `HIJACK_ROADMAP.txt` Phase 3 (`[DONE]` / `[NEXT]` / `[FUTURE]`).

## Status this phase

| Tag | What |
|-----|------|
| **[DONE]** | M1 Rest/Defend + Orders GUI; M2 Farm; M3 Collect; M4 Collect Oil; Master/Slave; color presets; `usable:true` E; raid list clear; nametag half-size + type+number world tags; Orders icon+number (NodeIcons / H1 fallback); open/close/reopen + list fill; SHOW RANGE no longer kills menu; Prev/Next hide on 1 page (verify) |
| **[NEXT]** | Confirm HACK 3.10 (open + list + icons/H1 + close/reopen + Prev/Next); SHOW RANGE ring actually visible; empty-list/reopen watch; nametag numbers / bot naming polish; RAID out of farm range |
| **[FUTURE]** | Recall bots + Stay in area; Phase 3.5 pathfinding & painted chests; Phase 3.6 Menu GUI tab (Names, Big Red, health bars, block overlay); Phase 6 MiniMap HUD (WAITING ON PERMISSION — do not implement copy; preferred Nutt/3780282057, fallback original RFS); Phase 7 Digital Signs (logic-connectable; show info — flesh out later); chat `/botorder` |

## Modes by type

| Bot | Modes |
|-----|--------|
| Haybot | Rest, Defend, **Farm** (+ seed dropdown) |
| Totebot (non-blue) | Rest, Defend, **Collect** |
| Waterbot (Totebot Blue) | Rest, Defend, **Collect Oil** |
| Farmbot / Big Red / others | Rest, Defend |

## Rest

Stand down. No combat / job chase from the order system.

## Defend

Combat vs hostiles, chase clamped to the home beacon **job radius** (16 / 32 / 48 m by tier).

## Farm (Haybot)

1. Set mode to **Farm** and pick a seed (Survival planter allowlist — tomato, carrot, potato, …).
2. Bot withdraws seeds from chests in home radius, plants soil, harvests mature crops via bot events (not melee smash), deposits carry buffer.

## Collect (Totebot)

Picks up allowlisted loot / loose parts in job radius (components/kits, soilbag, seeds, ores/resources) and deposits into chests.

## Collect Oil (Waterbot)

Searches oil geysers + crude oil loot/loose in job radius (perm-infect gets ×1.5 search). Deposits to chests in **base** beacon range. Stands down combat while on Oil (like Farm/Collect).

## Sticky home

Each ally has a sticky `workBeaconKey` home for jobs. Infection clears tether `beaconKey` but keeps the work home. Master domain aggregation shares the ally pool across linked beacons.

## Color

See [[Hack-Beacons]]. Color apply uses the same listed domain allies as the Orders list.

## [FUTURE] — pathfinding & painted chests (Phase 3.5)

Not shipped. Jobs today rely on vanilla unit AI best-effort navigation. Planned: more reliable pathfinding (chests, doorways) plus color-coded / connection-tool assigned chests (e.g. seeds vs veggies/fruits vs general drop-off). See `HIJACK_ROADMAP.txt` Phase 3.5 and [[Known-Issues]].
