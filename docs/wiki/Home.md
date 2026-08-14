# Remastered Framework Survival

**Author:** Zernon916  
**Discord:** https://discord.gg/DfjDMRx9ab  
**GitHub:** https://github.com/zernon916/Remastered-Framework-Systems  
**Steam Workshop:** fileId `3782487760`

A Scrap Mechanic Survival Chapter 2 **Custom Game** that hijacks hostile robots via powered Hack / Control / Infection beacons, adds host menus and farming tools, and ships store/quest hooks so other Blocks & Parts mods can inject shops and unlockable recipes.

Display name on GitHub: **Remastered Framework Survival** (repo: `Remastered-Framework-Systems`). In-game / Workshop pack names may still say Recipe Framework Survival (RFS).

## Wiki pages

| Page | For |
|------|-----|
| [Install](Install) | ModDatabase, custom game world, RFS Beacons B&P |
| [Commands](Commands) | `/setup`, `/menu`, `/gensettings`, hijack, shops, cheats |
| [Hack-Beacons](Hack-Beacons) | Beacon tiers, power, E Orders, Tinker, Master/Slave, range, color |
| [Bot-Orders](Bot-Orders) | Rest / Defend / Farm / Collect / Oil |
| [Known-Issues](Known-Issues) | Open polish (nametags, rename, RAID farm-range) |
| [Modder-Hooks](Modder-Hooks) | Store / quest / feature flags (see also `MODDER_API.txt`) |
| [Discord-Streamer](Discord-Streamer) | GitHub-only companion bot (not in Workshop) |

## Quick start

1. Subscribe to **ModDatabase** (keep installed; do **not** enable as a world mod).
2. Custom Game → create a world with this pack.
3. Enable Blocks & Parts you want (e.g. **RFS Beacons**, Intelligentia).
4. Host: `/givehack` (or Hideout trades) → wire a **Battery** → **E** on a powered beacon for Orders.

## What ships today

- Powered beacon hijack (tethered + Infection permanent submit)
- Beacon Orders GUI: Rest/Defend, Hay Farm, Tote Collect, Waterbot Collect Oil, ally color presets
- Master/Slave beacon linking + SHOW/HIDE range ring
- Host `/setup` + `/gensettings`, player `/menu` + `/map`
- Modder store merge (Craftbot / Hideout / Mining Hub) and `RfsQuest` wrappers

This wiki matches **current shipped code**, not the full hijack roadmap.
