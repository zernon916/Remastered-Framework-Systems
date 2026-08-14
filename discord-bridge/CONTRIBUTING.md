# Contributing — `discord-bridge/`

How this folder fits a **clean GitHub** copy of Recipe Framework Survival.

## What this folder is

Standalone Node helper beside the Scrap Mechanic host (Windows / Linux; macOS OK for bot-only). It does **not** change framework Lua hooks (`ModRecipeScan`, `RfsQuest`, etc.). In-game Streamer polling is `Scripts/game/RfsStreamer.lua`; this package writes the Discord vote drop file. Prefer explicit `DROP_PATH` so Lua and Node agree across OSes.

## Keep the repo clean

| Commit | Do not commit |
|--------|----------------|
| `.env.example` | `.env` (tokens, real channel/role IDs) |
| `config/allowlist.json` (default units/items) | Personal Discord secrets |
| `inbox/*.example.json` / `*.example.jsonl` | `inbox/vote.json`, `inbox/chat.jsonl` |
| `src/`, docs, `package.json` / lockfile | `node_modules/` |

Root `.gitignore` and `discord-bridge/.gitignore` ignore secrets and runtime inbox files while keeping examples.

## Editable allowlist

`config/allowlist.json` is **meant to be edited by the host** and is safe to commit as a default list (no tokens). Prefer committing shared unit/item aliases; keep server-specific Discord IDs in `.env` only (`VOTE_CHANNEL_ID`, `STREAMER_ROLE_ID`, …).

**In-game:** `/gensettings` STREAMER section previews counts and can **Reload** / cycle unit names. It does **not** replace editing JSON. Optional override: `$USER_DATA/rfs_discord_bridge/allowlist.json` (same path order as `RfsStreamer.lua`).

## Phase A / B / C

- Votes (`/vote` → `vote.json`) are the supported vote path (`RfsStreamer.lua`).
- **Chat relay (wired):** `src/chat-relay.js` appends `inbox/chat.jsonl` and writes `inbox/chat_inbox.json` when `CHAT_RELAY_ENABLED=true` (+ `CHAT_CHANNEL_ID`).
- **In-game:** `Scripts/game/RfsChatRelay.lua` polls `chat_inbox.json` when `/gensettings` → Discord chat relay is ON (`streamerChatRelayEnabled`, default false). Do not overwrite `vote.json` with chat lines. Keep tokens out of git.
- **Vote resolve (Phase C):** `RfsStreamer.lua` writes `vote_result.json`; `src/vote-resolve.js` announces to `RESULT_CHANNEL_ID` or `VOTE_CHANNEL_ID`.

## PRs / hygiene checklist

1. No `.env`, tokens, or personal webhook URLs.
2. Docs match `src/index.js`, `register-commands.js`, `vote-resolve.js`, `RfsStreamer.lua`, and `RfsChatRelay.lua`.
3. Examples only under `inbox/*example*`.
4. No Steam Workshop push from this GitHub hygiene workflow.
