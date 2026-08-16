# Install

## Requirements

1. **ModDatabase** (Steam Workshop fileId `2504530003`)  
   - Subscribe / keep installed.  
   - Do **not** enable it as a manual world mod. RFS uses it only to discover other mods' `description.json` paths.
2. **World Map** by Nutt (Steam Workshop fileId `3780282057`)  
   - Subscribe / keep installed for the MiniMap HUD and `/map` atlas.  
   - Do **not** enable it as a world mod (RFS hosts the HUD; enabling the B&P would duplicate the ring and auto-grant a GPS).
3. This **Custom Game** pack (Workshop `3782487760` or a local clone under Scrap Mechanic Custom Games).
4. Optional Blocks & Parts:
   - **RFS Beacons** — Hack / Control / Infection shapes (required for beacon gameplay)
   - Intelligentia, Scrap Computers, etc. as desired

## Create a world

1. Scrap Mechanic → **Custom Game** → Remastered / Recipe Framework Survival
2. Create a new world
3. In world Mods, enable the B&P packs you want (especially **RFS Beacons**)
4. Load in. Use `/mods` to see scan results

## Beacons without cheats

Hideout trades (Farmers currency) when RFS Beacons B&P is enabled:

| Beacon | Range | Hideout cost |
|--------|-------|--------------|
| Hack | 16 m | 20 Farmers |
| Control | 32 m | 50 Farmers |
| Infection | 48 m | 120 Farmers |

Craftbot also lists **Hack Beacon** (1 Metal placeholder). Control / Infection stay hideout-only.

## Framework-only mode

In pack `rfs_settings.json`:

```json
{ "frameworkOnly": true, "cheats": false, "setupQuestTab": false }
```

Turns off default cheat/quest UI while keeping store hooks, quest API wrappers, and hijack hooks. Per-world toggles still use host `/gensettings`.

## Local / GitHub play

Clone https://github.com/zernon916/Remastered-Framework-Systems and place (or symlink) the pack where Scrap Mechanic expects Custom Games. Local sync path used by the author: `C:\sm\RFS`.
