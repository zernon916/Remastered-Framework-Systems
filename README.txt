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
   MiniMap/atlas by Nutt is bundled. If you already have World Map
   (Workshop 3780282057), do NOT enable it as a world mod (double HUD).

How to start a world
--------------------
1) Scrap Mechanic → Custom Game → Recipe Framework Survival
2) Create new world
3) Enable Blocks & Parts mods you want (Intelligentia, etc.)
4) Load in — check the log / use /mods for scan results

Quick host commands
-------------------
  /menu              open player menu (map + per-player growth overlay) — all players
  /setup             open host setup GUI (Main / Quest / Inventory / Farming)
  /gensettings       open host gen settings (tabs: MAIN / FEATURES / STREAMERS / DISCORD)
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
  /hijacklist        count tethered vs infected allies
  /givehack          Give Hack Beacon (cheat)
  /unhijack [range]  Release nearest owned ally (host can release any; not a raid ban)

Bot hijack — beacon computer
----------------------------
Hack Beacon: connect a Battery or Recharge box, optional logic switch.
Raid-only. Base: 30 blocks, cap 4, hold 8 s.
  Radio Battery Brick ×1: +10 range, +1 cap
  Radio Antenna ×2: +10 range each
  Radio Lock ×1: +3 cap, +3 s hold
  Hideout: Hack Beacon schematic 10 Farmers

Tethered = green. Infected = deeper green, no beacon needed.
Allies can slowly chain-convert nearby hostiles. See HIJACK_ROADMAP.txt

Digital Signs
-------------
Craftbot: Digital Sign / Large / Extra Large (1 Metal placeholder each).
Press E to type text. Optional logic switch: no wire = always show; switch off = hide.
No battery. Vanilla Survival textsigns still exist and are not logic-connectable.

Inventory LCD (craftbot, 1 Metal each): S / L / XL. Shows a chest's item names and
counts. Weld the LCD onto or next to the chest, or connect LCD → chest with the
Connect tool. Small shows one stack (name + amount) and cycles; L/XL list more
rows and scroll. Optional logic switch hides the face. Not a computer.

Always-on HUD
-------------
Top-center game clock and facing compass (N/NE/E/…). Lower-right weapon ammo count.
Corner MiniMap HUD (Nutt World Map, Workshop 3780282057, bundled) while you walk.

Map — complete
--------------
Always-on MiniMap HUD (upper-left). Research/craft Nutt's GPS (Metal Block +
Circuit + Component Kit + Glass), then LMB to open the atlas (E / Esc / CLOSE
to exit). Do not enable World Map as a world mod if you already have it.
Reload tip: exit to menu and reload the world after updating this Custom Game so Scripts/Objects refresh.

Streamer / Discord (optional)
-----------------------------
GitHub: https://github.com/zernon916/Recipe-Framework-Systems
Discord: https://discord.gg/DfjDMRx9ab
Host /gensettings → STREAMERS / DISCORD tabs. In-game Streamer uses file drops under
%USER_DATA%/rfs_discord_bridge. The Discord/Streamer companion is NOT in the Steam Workshop pack —
clone discord-bridge/ from GitHub (link above) and run separately.
Then configure .env, npm install, and npm run watch. See discord-bridge/README.md.

Performance
-----------
Recipe scan avoids shapeset fileExists spam for quieter console / faster loads.

See COMMANDS.txt for the full list.

Currency
--------
Hideout schematic trades use Farmers (farmerball):
  8d601982-4608-4d5e-bb9e-e4041486f7c7
