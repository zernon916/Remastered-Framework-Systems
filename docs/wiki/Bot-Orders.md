# Bot Orders

Opened with **E** on a **powered** Hack / Control / Infection beacon. Modes depend on bot type.

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

See [Hack-Beacons](Hack-Beacons). Color apply uses the same listed domain allies as the Orders list.
