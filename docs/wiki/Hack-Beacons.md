# Hack beacons

Beacons are the **computer source** for hijacked robots. Wire a **Battery** container (electricity). Optional logic switch as on/off.

## Tiers

| Beacon | Range | Notes |
|--------|-------|--------|
| Hack (red) | 16 m | Tether only |
| Control | 32 m | Faster tether |
| Infection | 48 m | Can permanently submit (infected) |

- **Tethered** allies need a powered beacon in range or they DROP and revert.
- **Infected** allies stay loyal without beacon power (sticky home still used for Orders).
- Unpowered / out of range → tethered bots revert. Infection does not.

Battery drain runs while tethered bots are linked **or** auto-hijack is converting. Idle powered = no drain.

## Interact

| Input | When powered | Effect |
|-------|----------------|--------|
| **E** | Yes | Opens **Beacon Orders** GUI |
| **Tinker** | Always | Mass hijack in range (spends Batteries) |
| **E** | No | Same as Tinker (hijack) |

Auto-hijack also converts hostiles that stand in a powered field (progress tag HACK).

## Orders GUI (E)

- Status line: beacon name, ally count, role (Independent / Master / Slave), shape key
- Bot list with mode dropdowns (and seed picker for Hay Farm)
- **SET MASTER** / **CLEAR MASTER**
- **SHOW RANGE** / **HIDE RANGE** — ground range ring
- **Color** dropdown — tint selected bot, or all listed domain allies if none selected
- **CLOSE** — closes the GUI (bound on the Game client so buttons work)

## Master / Slave

- **SET MASTER** on one powered device. Other powered hack beacons in its range become **Slaves**.
- Orders list and new `workBeaconKey` homes share the Master's **order domain** (Master key + linked Slave keys).
- One Master per linked group. **CLEAR MASTER** returns Independent.
- Allies hijacked before Master was set can be migrated onto the Master when you claim Master or open Orders.

## Ally colors

Presets: Ally Green, Infect Green, Blue, Cyan, Yellow, Orange, Magenta, White, Red.  
Persists on the unit (`rfsAllyColor` / ally record). Click a bot name to select before applying.

## Related commands

`/givehack`, `/hijack`, `/hijacklist`, `/unhijack` — see [Commands](Commands).
