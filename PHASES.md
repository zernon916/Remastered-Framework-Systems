# RFS phases

High-level status for Recipe Framework Survival (menus, Streamer, Discord bridge, hijack).  
Author: Zernon916

---

## DONE

- **Menus / GenSettings host split** — host `/setup` + `/gensettings`; player `/menu`; world feature flags via `RfsFeatures` / `RfsGenGui`
- **GenSettings tabs** — MAIN / FEATURES / STREAMERS / DISCORD; Discord Start writes `$USER_DATA/rfs_discord_bridge/start_request.json` only (Lua cannot spawn Node)
- **Phase A - Discord bot** - `discord-bridge` on GitHub only (https://github.com/zernon916/Recipe-Framework-Systems); not shipped in Steam/Workshop packs
- **Phase B — Streamer harden + chat relay** — `RfsStreamer` host-only spawn/give, cooldown, allowlist, consume; Discord → game chat (`chat-relay.js` + `RfsChatRelay.lua`)
- **Phase C — vote resolve + allowlist UI** — `vote_result.json` + `vote-resolve.js`; `/gensettings` allowlist summary / reload / unit cycle
- **Phase D — game → Discord chat outbox** — `/say` + `/d` → `chat_outbox.json` → `chat-outbox.js` → `CHAT_CHANNEL_ID` (gated by Streamer + chat relay)
- **Phase F — hijack one-pass (lite)** — identity persist + nametag; light chain convert; `/unhijack` voluntary release; underground miner/cable flag (default ON). Docs honesty for Hideout Control/Infection (50/120 Farmers). See `HIJACK_ROADMAP.txt`.
- **Phase 7 — Digital Signs (minimum)** — Craftbot logic-connectable signs (S/L/XL) that show editable text. Optional logic switch hides the face. Inventory LCD S/L/XL show chest item + count (weld or LCD→chest). Does not scramble Phase 3.
- **Phase 6 — MiniMap (HUD)** — Nutt World Map HUD + `/map` atlas (Workshop 3780282057); original HUD/camera fallback; Nutt credited. Beacon/ally letters later.
- **Phase 3.5 — Pathfinding & painted chests** — Farm/Collect/Oil walk to chests (doorway side-step). Yellow=seeds, green=produce, other=drop-off. Same-creation or logic-connected chests are assigned to that beacon.
- **Phase 3.6 — Menu GUI visuals** — `/menu` Names / Big Red / enemy+neutral tag colors. Block health overlay cut (no SM API).

---

## CUT (not shipping)

- **Phase 4 — Ally Factory — CUT** — not worth the lag. Unwired from the playable pack (`rush/cut-factories`). Digital Signs unchanged. Hideout crate→80 seed trades kept.

---

## REMAINING (unfinished only)

- **Phase E** — Steam Workshop push (full menus / streamer / discord batch) — only when the user asks

### Phase F note (from `PENDING_FIXES.md`, 2026-08-13)

- Client Craftbot extras GUI — **DONE** (already shipped)
- Cotton in autumn — investigated, **not an RFS fix**
- Hijack one-pass lite — **DONE** (this pass)
- Other parked items — **none**

---

## Discord companion (GitHub only)

`discord-bridge` is **not** included in Steam / Workshop / local-backup packs.
Clone and run it from: https://github.com/zernon916/Recipe-Framework-Systems (`discord-bridge/`).
In-game Streamer / chat relay still use `%USER_DATA%/rfs_discord_bridge` file drops;
bot + `npm run watch` run separately from the GitHub clone.


## GitHub

Push from the Desktop GitHub folder `C:\Users\benko\Desktop\RecipeFrameworkSurvival` when the user asks (see `GITHUB.md`). No Steam / Fant from the doc workflow.
