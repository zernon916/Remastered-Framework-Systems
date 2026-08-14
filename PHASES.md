# RFS phases

High-level status for Recipe Framework Survival (menus, Streamer, Discord bridge).  
Author: DemonsDen126

---

## DONE

- **Menus / GenSettings host split** — host `/setup` + `/gensettings`; player `/menu`; world feature flags via `RfsFeatures` / `RfsGenGui`
- **Phase A — Discord bot** — `discord-bridge` (`/ping`, `/vote`, allowlist, channel/role locks, drop file)
- **Phase B — Streamer harden + chat relay** — `RfsStreamer` host-only spawn/give, cooldown, allowlist, consume; Discord → game chat (`chat-relay.js` + `RfsChatRelay.lua`)
- **Phase C — vote resolve + allowlist UI** — `vote_result.json` + `vote-resolve.js`; `/gensettings` allowlist summary / reload / unit cycle
- **Phase D — game → Discord chat outbox** — `/say` + `/d` → `chat_outbox.json` → `chat-outbox.js` → `CHAT_CHANNEL_ID` (gated by Streamer + chat relay)

---

## REMAINING (unfinished only)

- **Phase E** — Steam Workshop push (full menus / streamer / discord batch) — only when the user asks
- **Phase F** — critical items from `PENDING_FIXES.md` if any remain

### Phase F note (from `PENDING_FIXES.md`, 2026-08-13)

- Client Craftbot extras GUI — **DONE** (already shipped)
- Cotton in autumn — investigated, **not an RFS fix**
- Other parked items — **none**

No critical open fixes listed there for a Phase F pass right now.

---

## GitHub

Push from the Desktop GitHub folder `C:\Users\benko\Desktop\RecipeFrameworkSurvival` when the user asks (see `GITHUB.md`). No Steam / Fant from the doc workflow.
