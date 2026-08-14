Recipe Framework Survival — Player README
========================================
Author: Zernon916

What this is
------------
A Survival Chapter 2 Custom Game that lets Blocks & Parts mods inject:
  - Craftbot recipes (unlockable schematics — not auto-unlocked)
  - Farmers Hideout schematic trades (Farmers currency)
  - Mining Hub trades
  - Optional loot table entries

Intelligentia and other B&P mods stay separate. Enable them as world mods.

Requirements
------------
1) Subscribe to ModDatabase (Steam Workshop fileId 2504530003).
   Keep it installed. Do NOT enable it as a manual world mod.
2) This Custom Game: Recipe Framework Survival.

How to start a world
--------------------
1) Scrap Mechanic → Custom Game → Recipe Framework Survival
2) Create new world
3) Enable Blocks & Parts mods you want (Intelligentia, etc.)
4) Load in — check the log / use /mods for scan results

Quick host commands
-------------------
  /menu              open player menu (map + per-player growth overlay)
  /setup             open setup GUI (Main / Quest / Inventory size tabs; cheats gate Inventory)
  /map               top-down live camera map (toggle)
  /help              command summary
  /fly               toggle fly-like climbing mode
  /farmers 10        Farmers for Hideout testing
  /tshop             Open Farmers Hideout trader (remote, no walk)
  /mshop             Open Mining Hub trader (remote, no walk)
  /unlockmodded      unlock scanned mod craftbot recipes
  /questlist         list quests
  /mods              show scanned mod sources
  /hijack [range]    permanently infect nearest hostile robot (cheat)
  /givehack          Give a Hack Beacon (cheat)

Bot hijack — beacon computer
----------------------------
Hack Beacon (red): connect a Battery container, optional logic switch, press E
to hijack nearby hostiles (1 Battery each, 16 m). Lose power/range → they revert.

  Craftbot: 1 Metal (easy placeholder — recipe will get harder later)
  Hideout:  20 Farmers (item purchase, not a schematic)

Tethered = green. Infected = deeper green, no beacon needed.
See HIJACK_ROADMAP.txt for factories / identities / farm orders.

Always-on HUD
-------------
Top-center game clock and facing compass (N/NE/E/…). Visible without opening /setup.

Map (/map)
----------
Chat `/map` opens a top-down cutscene camera over the live world (not a craftable tool).
WASD pans, scroll zooms, RMB/LMB recenters on you, E or Esc closes (or `/map` again).
Reload tip: exit to menu and reload the world after updating this Custom Game so Scripts/Objects refresh.

See COMMANDS.txt for the full list.

Currency
--------
Hideout schematic trades use Farmers (farmerball):
  8d601982-4608-4d5e-bb9e-e4041486f7c7

