# Known issues

Open polish only. Do not treat these as shipped features. Sources: `PENDING_FIXES.md`, `HIJACK_ROADMAP.txt`, `COMMANDS.txt`.

## Nametag numbers (OPEN)

Idle identity / numbers above hijacked bots are incomplete or missing. Phase 2 lite claimed overhead via `pushTag` (idle name; HACK/DROP/CHAIN priority). Numbers still need verification on clients.

## Bot naming / rename UI (OPEN)

No shipped way yet to set a custom bot name via:

- **E on bot**, or
- rename through the hack device / Orders GUI

Desired: names show above the head **with** the numbers.

## RAID farm-range filter (OPEN)

Bots that are **out of range of farms** should **not** be affected by RAID jam / range mul / raid notes. Still open in Phase 5 polish.

## Pathfinding & painted chests (FUTURE — Phase 3.5)

Not started. Farm / Collect / Oil still use vanilla unit AI navigation. Planned: reliable pathfinding through doorways to chests, plus painted / assigned chests (color roles + optional connection tool to beacon Orders domain). Cross-ref: `HIJACK_ROADMAP.txt` Phase 3.5, `PENDING_FIXES.md` §4, [[Bot-Orders]].

## Cotton in autumn

Not an RFS bug. Vanilla places world cotton in autumn forest interiors; easy to miss (small scale / short view distance). See `PENDING_FIXES.md` section 2.

## Recently fixed (this pack)

- Beacon Orders menu open / close binding (Game client RPC)
- Empty ally list on Master / Independent Orders (domain migrate + beacon-built list + in-range fallback)
- SHOW RANGE / HIDE RANGE (networked `showRange` + Game-client ring fallback)
- Ally color presets UI

Quit Scrap Mechanic fully and reload the Workshop / `C:\sm\RFS` pack after syncing before testing.
