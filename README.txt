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
2) Subscribe to World Map by Nutt (Steam Workshop fileId 3780282057).
   Keep it installed. Do NOT enable it as a world mod (RFS hosts the HUD;
   enabling it as a B&P would duplicate the ring and auto-grant a GPS).
3) This Custom Game: Recipe Framework Survival.

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
  /givehack          Give Hack + Control + Infection Beacons (cheat; needs RFS Beacons B&P)
  /unhijack [range]  Release nearest owned ally (host can release any; not a raid ban)

Bot hijack — beacon computer
----------------------------
Hack / Control / Infection Beacons: connect a Battery container, optional logic switch.
Hack 16 m / Control 32 m / Infection 48 m (permanent submit). Lose power/range → tethered revert.

  Craftbot: Hack Beacon 1 Metal (placeholder)
  Hideout:  Hack 20 / Control 50 / Infection 120 Farmers (items, not schematics)
  Enable local Blocks & Parts mod "RFS Beacons" or hideout rows /givehack stay empty.

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
Corner MiniMap HUD (Nutt World Map, Workshop 3780282057) while you walk.
If World Map is not subscribed, clock/compass/ammo stay; MiniMap is skipped.

Map (/map)
----------
Chat `/map` or `/rfsmap` opens Nutt's full atlas when World Map is installed
(pan/zoom on the overlay; E / Esc / CLOSE / `/mapclose` to exit). No GPS item.
If Nutt content is missing, `/map` falls back to the original top-down camera
(WASD pan, scroll zoom, character locked). `/menu` Map uses the same toggle.
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
