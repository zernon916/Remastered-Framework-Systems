# RFS pending fixes

Author: Zernon916  
Workshop: 3782487760  
Date: 2026-08-15  
SM: 1.0.5  

WIP note: local **HACK 3.13** — 3.11 open + PREV/NEXT never setVisible; not all on GitHub (push freeze).  
Scan tags: `[DONE]` / `[NEXT]` / `[FUTURE]`. Source of truth for Orders: `HIJACK_ROADMAP.txt` Phase 3.

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

## 3) Phase 3 Orders / Beacon GUI — DONE vs NEXT vs FUTURE

### [DONE] (through HACK 3.10 — local)

- M1 Rest/Defend + beacon Orders GUI
- M2 Hay Farm / M3 Tote Collect / M4 Waterbot Collect Oil
- Master/Slave beacons; color presets (domain + new hijacks inherit)
- `usable:true` E on beacons; raid list clear on destroy/capture
- Nametag half size; type+number world tags; Orders icon+number (NodeIcons / H1 fallback)
- Orders open/close/reopen + list fill (HACK 3.5+ / 3.9 path)
- SHOW RANGE no longer kills menu (ring visibility still [NEXT])
- Prev/Next layout-visible (no setVisible); pageDelta no-ops on 1 page (HACK 3.13)

### [NEXT] — verify / testing now

- Confirm HACK 3.13: open + list + icons/H1 + close/reopen + Prev/Next safe
- SHOW RANGE ground ring actually visible (parked; menu-safe already)
- Empty-list / reopen regressions — watch during test
- Nametag numbers (issue #2) / bot naming UI — still polish (also §3a/3b)
- RAID out of farm range — still open (also §3c)

### [FUTURE] — end of phase / later (do not build during 3.10)

- Stay / Recall / `/botorder` / tapebot Sentry — **shipped** (R2)
- Phase 3.5 pathfinding & painted chests (§4) — **shipped** (R3)
- Phase 3.6 Menu GUI tab (§5) — **shipped** (R4 + map-complete: HP bars + block overlay)
- Phase 6 Map (§6) — **complete** (Nutt 3780282057 atlas + MiniMap HUD; ammo + camera fallback)
- Phase 7 Digital Signs (§7) — **minimum shipped** (Craftbot S/L/XL; logic hide)

See `HIJACK_ROADMAP.txt` Phase 3 checklist for the full scannable list.

---

## 3.4) Orders SHOW RANGE ring — **[NEXT]** (parked polish)

**[DONE]:** SHOW RANGE click must **not** destroy/close the Orders menu
(button caption toggles only).

**[NEXT]:** ground range ring does not reliably draw/clear. Needs a proper fix
(beacon clientData ring and/or safe Game fallback) without tearing down the
Orders GUI.

Do **not** treat range ring as shipped until this is closed.

**[FUTURE] after SHOW RANGE:** Recall bots; Stay in area. See Phase 3 [FUTURE].

---

## 3a–3c) Hijack / Phase 2–5 polish — **[NEXT]/OPEN]** (doc only)

Logged in `HIJACK_ROADMAP.txt` under Phase 2 full / Phase 5 full. Do not treat as shipped.

### 3a) Numbers above bots — **[NEXT]** (Phase 2 identity / nametag)

Nametag/number display above hijacked bots is incomplete or not showing.
Phase 2 lite claims overhead via `pushTag` (idle name; HACK/DROP/CHAIN priority) —
verify numbers + idle identity actually render on clients.
(World type+number tags / half-size landed in Orders polish; issue-#2-style numbers still open.)

### 3b) Bot naming — **[NEXT]** (Phase 2 richer identity UI / rename)

Need a way to name bots:
- Allowed: **E on bot** to create/set a name, **OR** rename via **hack device**
- Names should show above the head **with the numbers** (same overhead as 3a)

### 3c) RAID range filter — **[NEXT]** (Phase 5 raid callouts / raid behavior)

Bots that are **out of range of farms** should **NOT** be affected by the RAID
stuff that was added. Keep out-of-range farm bots out of RAID behavior
(jam / range mul / raid notes in `RfsBotHijack`).

---

## 4) Pathfinding & painted chests — **[DONE]** (Phase 3.5)

Shipped on `rush/r3`. Farm / Collect / Oil walk to chests; doorway side-step if LOS blocked. Yellow = seeds, green = produce, other = drop-off. Assigned = same creation as the beacon or logic-connected.

## 5) Menu tab: GUI (visuals) — **[DONE]** (Phase 3.6)

Shipped on `/menu` (not Beacon Orders). Names on/off, Big Red, enemy/neutral colors.
Custom unit HP billboards use those colors (engine HP bars cannot be recolored).
Block/creation overlay is best-effort: look-at HUD + world text + nearby labels
using shape count / mass (SM has no per-block HP API). Toggle: `/menu` Block overlay.

---

## 6) Map — **complete** (Phase 6)

Logged in `HIJACK_ROADMAP.txt` under **Phase 6**. Status: **complete on `rush/map-complete`** (Nutt World Map Workshop **3780282057**). MiniMap HUD is part of this phase, not a sidecar.

**Path:** RFS autoTool hosts Nutt's HUD from `$CONTENT_58df2b8e-...` (subscribe, do not enable as a world mod). `/map` / `/rfsmap` / `/menu` Map open the atlas. Credit Nutt in Steam / `description.json` / in-game. **Fallback:** original RfsHud (clock + compass + ammo) and lock-camera `/map` if Nutt content is missing. Do not cover lower-right ammo. Beacon/ally letters later.

---

## 7) Digital Signs — **[DONE minimum]** (Phase 7)

Shipped on `rush/digital-signs`. Spec was high-level only.

- Craftbot Digital Sign S / L / XL show editable text (Survival textsign face)
- Optional logic switch: unpowered logic hides text; no parent = always on
- Logic output follows display-on
- Inventory LCD S / L / XL (`rush/signs-lcd`): item name + count from a welded/adjacent or logic-wired chest. Small = one stack (instruction readout); L/XL list rows and scroll. LCD output stays inactive so chest loot-vacuum is not triggered. Text Digital Signs keep UUID `f8c2a5e4-…`. Factory UUID untouched.
- Gaps: no ON/OFF dual messages; no Hideout trade; vanilla Survival signs stay non-logic
