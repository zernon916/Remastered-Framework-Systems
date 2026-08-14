# RFS pending fixes

Author: Zernon916  
Workshop: 3782487760  
Date: 2026-08-13  
SM: 1.0.5  

---

## 1) Client Craftbot extras (GUI) — **DONE (this SteamCMD push)**

**Was:** Host Craftbot showed RFS/mod extras. Linux client only saw vanilla.

**Shipped in this push (`Scripts/Game.lua` `loadCraftingRecipes`):**

- Same in-memory merge on host and remote client (Survival already calls this on client if not host).
- Deep-copy recipes before `LoadCraftingRecipes` so GUI/hook keep string UUIDs.
- Hook `sm.json.open` by filename suffix `craftbot_other_rfs.json` (not exact `$CONTENT_DATA` equality).
- Reject `sm.json.save` of `hideout.json`, `craftbot_other_rfs.json`, and `$SURVIVAL_DATA` CraftingRecipes JSON.
- After merge, write a JSON-safe copy to a **local** path (`$USER_DATA` / `$TEMP_DATA` / LocalBlueprints fallback — not Workshop, not Survival craftbot JSON) and set `g_craftingRecipeSets.craftbot_other.path` there. Each peer writes locally.
- Wrap `Crafter.cl_updateRecipeGrid` from RFS (do not edit Survival `Crafter.lua`).
- Re-apply unlock flags: scanned mods unlockable; RFS Hack Beacon always visible. Control/Infection stay hideout-only.
- Log: `[RFS] craftbot_other in-memory merge modRecipes+=N total=M host=true/false`
- Published `CraftingRecipes/craftbot_other_rfs.json` stays stub `[]`.

**Also in this push:** hideout + mining hub strip missing-mod shop rows (no `BLOCK NOT FOUND` ghosts). Beacons are omitted if RFS Beacons B&P is not enabled on that peer. No hideout.json write.

---

## 2) Cotton in autumn — investigated, **not a fix**

Not an RFS bug. Do not change spawn data.

Vanilla 1.0.x **does** place world cotton in **autumn forest** (`TYPE_AUTUMNFOREST = 6`) as harvestable `hvs_farmables_cottonplant` (`c591d94b-d7d1-4305-a9dd-76ef06d6fb49`). Baked into tiles (no spawn-weight table). Interior `AutumnForest(1111)_01/_02` both have it. Missing only on edge variants `(0001)_01/_02` and `(0011)_04`. Meadow / forest / field / burnt: **zero** cotton (pigment flower is the meadow/forest plant).

RFS `harvestablesets.harvestabledb` is empty (no inject). Farming (`dirtOnBlocks` / `alwaysWatered` / overlay / Instant Farm) only targets **planted** `hvs_growing_cotton`, not world cotton plants. `loot.json` only adds chest weights.

Easy to miss: scale 0.25, `maxViewDistance` 15 m. Look at ground in **orange autumn forest interiors**, not golden fields or green meadows.

---

## 3) Other parked items

None.
