# RFS Discord Bridge â€” host guide (Streamer mode)

Scrap Mechanic Lua **cannot** make HTTP requests. This Node.js bot runs on the **same PC as the SM host**, connects to Discord, and writes vote JSON to a **local drop file**. In-game `Scripts/game/RfsStreamer.lua` polls that file when **Streamer mode** is on and applies spawn/give via existing Survival cheat paths.

```text
Discord /vote  â†’  Node bridge  â†’  vote.json (disk)  â†’  RfsStreamer.sv_think  â†’  spawn / give
```

Framework Lua hooks stay unchanged. This folder is only the external bridge.

---

## Prerequisites

| Requirement | Notes |
|-------------|--------|
| **Node.js LTS** | `>=18` (`package.json` `engines`). Install from [nodejs.org](https://nodejs.org/). |
| Scrap Mechanic host | Same machine as this process. |
| Recipe Framework Survival | Local Custom Game (e.g. `C:\sm\RFS`) or Workshop install. |
| Discord application | Bot token + invite with slash commands. |

---

## Quick start

```bat
cd discord-bridge
copy .env.example .env
npm install
npm run register
npm start
```

Then in-game: host world â†’ **`/gensettings`** â†’ **Streamer ON** â†’ Discord `/vote action:spawn unit:farmbot amount:1`.

---

## 1. Create a Discord server + bot

### Server

1. Discord â†’ **+** â†’ **Create My Own** â†’ make a private server for your stream / SM host.
2. Create a **vote** text channel (and optionally a **chat-relay** channel).
3. Create a **Streamer** (or viewer) role if you want role-gated votes.
4. Enable **Developer Mode** (Settings â†’ Advanced) so you can copy IDs.

### Bot (Developer Portal)

1. [Discord Developer Portal](https://discord.com/developers/applications) â†’ **New Application**.
2. **Bot** â†’ Add Bot â†’ **Reset Token** â†’ `DISCORD_TOKEN`.
3. If you will use chat relay later: Bot â†’ Privileged Gateway Intents â†’ enable **Message Content Intent**.
4. OAuth2 â†’ URL Generator:
   - Scopes: `bot`, `applications.commands`
   - Permissions: **Use Application Commands** (Send Messages optional; needed if the bot replies in channels)
5. Open the generated invite URL and add the bot to your server.
6. **Application ID** â†’ `CLIENT_ID` (legacy alias `DISCORD_CLIENT_ID` still works).
7. Right-click server â†’ **Copy Server ID** â†’ `GUILD_ID` (legacy `DISCORD_GUILD_ID`). Guild slash registration is instant; global can take up to ~1h.

### Copy role / channel IDs into `.env`

| Discord UI | `.env` key |
|------------|------------|
| Right-click vote channel â†’ Copy Channel ID | `VOTE_CHANNEL_ID` |
| Right-click streamer role â†’ Copy Role ID | `STREAMER_ROLE_ID` |
| Right-click chat channel â†’ Copy Channel ID | `CHAT_CHANNEL_ID` (Phase A relay stub) |

**Never commit `.env` or real tokens.**

---

## 2. Install & `.env`

```bat
cd discord-bridge
copy .env.example .env
npm install
```

Essential keys:

```env
DISCORD_TOKEN=
CLIENT_ID=
GUILD_ID=

# Local writable pack (typical SM host Custom Game path):
DROP_PATH=C:\sm\RFS\discord-bridge\inbox\vote.json

# Optional gates (src/permissions.js â€” see below)
VOTE_CHANNEL_ID=
STREAMER_ROLE_ID=
ALLOW_EVERYONE_VOTES=false
VOTE_COOLDOWN_SEC=15

# Chat relay Phase A stub (file drop only; in-game = Phase B)
CHAT_RELAY_ENABLED=false
CHAT_CHANNEL_ID=
```

If `DROP_PATH` is empty, the bot writes `discord-bridge/inbox/vote.json` (default in `src/index.js`).

### Optional vote locks (`src/permissions.js`)

Wired into `/vote` via `canVote()` in `src/index.js` (cooldown stays in index).

| Env | Behavior |
|-----|----------|
| `VOTE_CHANNEL_ID` | If set, `/vote` only in that channel. |
| `STREAMER_ROLE_ID` | If set and `ALLOW_EVERYONE_VOTES` is not `true`, require this role. |
| `ALLOW_EVERYONE_VOTES` | Default `false`. Set `true` to skip the role check. |
| `VOTE_COOLDOWN_SEC` | Per-user cooldown in `index.js` (default `15`). |

If `STREAMER_ROLE_ID` is unset, role checks are skipped (channel lock and cooldown still apply).

---

## 3. DROP_PATH â€” local `C:\sm\RFS` vs Workshop

### Prefer writable AppData (Workshop-safe)

Workshop `$CONTENT_*` is often **read-only**. Prefer USER_DATA â€” `RfsStreamer.lua` polls it **first**:

```text
%AppData%\Axolot Games\Scrap Mechanic\User\User_<steamid>\rfs_discord_bridge\vote.json
```

Create `rfs_discord_bridge` if needed, set that absolute path as `DROP_PATH`.

### Local Custom Game (`C:\sm\RFS`)

When the pack is a writable folder such as `C:\sm\RFS`:

```env
DROP_PATH=C:\sm\RFS\discord-bridge\inbox\vote.json
```

### Exact paths `RfsStreamer.lua` tries (in order)

From `Scripts/game/RfsStreamer.lua` (`VOTE_PATHS`):

| # | SM path | Typical Windows meaning |
|---|---------|-------------------------|
| 1 | `$USER_DATA/rfs_discord_bridge/vote.json` | `%AppData%\Axolot Games\Scrap Mechanic\User\User_<id>\rfs_discord_bridge\vote.json` |
| 2 | `$TEMP_DATA/rfs_discord_bridge\vote.json` | SM temp user data + same relative folder |
| 3 | `$CONTENT_DATA/discord-bridge/inbox/vote.json` | Active content root â†’ `discord-bridge\inbox\vote.json` |
| 4 | `$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247/discord-bridge/inbox/vote.json` | RFS pack `localId` content folder |

Point `DROP_PATH` at **one** file the host can read. Prefer **#1** when Workshop content is read-only; use **#3/#4** for a local writable `C:\sm\RFS` install.

---

## 4. Register commands & start

| Script | Action |
|--------|--------|
| `npm run register` | Deploy `/ping` and `/vote` (`src/register-commands.js`) |
| `npm start` | Run the bot; also re-registers when `CLIENT_ID` is set |
| `npm run clean` | Delete `inbox/vote.json`, `inbox/chat.jsonl`, and `inbox/chat_inbox.json` |

```bat
npm run register
npm start
```

Keep `npm start` running while you host. Startup logs the resolved drop path, cooldown, and `ALLOW_EVERYONE_VOTES`.

---

## 5. Enable Streamer in-game

1. Host a **Recipe Framework Survival** world.
2. Open **`/gensettings`** (host-only) â†’ turn **Streamer** **ON**.
3. `RfsFeatures.streamerModeEnabled()` gates polling; off â†’ votes ignored (safe no-op).
4. Only the **host** runs `RfsStreamer.sv_think` (~0.5s).

---

## 6. Test: `/vote` â†’ Farmbot

Units/items must appear in `config/allowlist.json` (reloaded on each vote).

```text
/vote action:spawn unit:farmbot amount:1
```

Bridge writes atomically (temp â†’ rename), for example:

```json
{
  "id": "â€¦",
  "action": "spawn",
  "unit": "farmbot",
  "item": null,
  "amount": 1,
  "source": "discord",
  "voter": "discordUserId",
  "createdAt": "2026-08-14T14:00:00.000Z",
  "ts": 1710000000000,
  "quantity": 1
}
```

Within ~0.5s, host chat should show `[RFS] Streamer vote: spawn farmbot` and a Farmbot near the host.

**Give** (alias or UUID from allowlist):

```text
/vote action:give item:farmers amount:5
```

### `/vote` options

| Option | Required | Description |
|--------|----------|-------------|
| `action` | yes | `spawn` or `give` |
| `unit` | for spawn | Allowlisted alias (default `farmbot`) |
| `item` | for give | Allowlisted alias or UUID |
| `amount` | no | 1â€“20 (default 1) |

---

## Allowlist

Edit `config/allowlist.json` on the host (no bot restart required â€” reloaded per vote):

- `units[]` â€” spawn aliases (`farmbot`, `haybot`, â€¦)
- `items[]` â€” `{ "alias", "uuid", "name?" }` for give

Aliases must also be understood by `RfsStreamer.lua` (`UNIT_ALIAS`) or be a raw unit UUID.

---

## Drop JSON schema

| Field | Notes |
|-------|--------|
| `id` | UUID / unique id â€” RfsStreamer skips repeats |
| `action` | `"spawn"` \| `"give"` |
| `unit` / `item` | Spawn alias or give UUID |
| `amount` | Count |
| `source` | `"discord"` |
| `voter` | Discord user snowflake |
| `createdAt` | ISO-8601 |
| Legacy | `ts`, `uuid` (give), `quantity` â€” still written for older readers |

`RfsStreamer.lua` accepts `item`/`uuid`, `amount`/`quantity`, `unit`/`unitName`/`name`.

---

## Safety

- Missing file / Streamer off / not host â†’ no-op.
- Unknown unit/item â†’ Discord rejects before write; bad in-file votes skipped.
- Per-user cooldown; optional channel/role gates.
- `.env` gitignored â€” never commit tokens.
- Standalone package (not shared with other Discord bots). No Steam push from this workflow.

---

## Chat relay (Discord → game)

`src/chat-relay.js` is attached from `src/index.js`. When `CHAT_RELAY_ENABLED=true` and `CHAT_CHANNEL_ID` is set, non-bot messages in that channel append to `inbox/chat.jsonl` and refresh `inbox/chat_inbox.json` (JSON companion for Lua — Scrap Mechanic cannot `sm.json.open` JSONL). Enable **Message Content Intent** in the Developer Portal.

| Env | Behavior |
|-----|----------|
| `CHAT_RELAY_ENABLED` | Default `false`. Set `true` to listen. |
| `CHAT_CHANNEL_ID` | Required to actually listen; if unset while enabled → safe no-op. |
| `CHAT_RELAY_PATH` | Optional absolute path (default `inbox/chat.jsonl`). Companion is sibling `chat_inbox.json`. |

**In-game:** `/gensettings` → **Discord chat relay: ON** (`RfsFeatures.streamerChatRelayEnabled()`, default OFF). Host-only `RfsChatRelay.sv_think` polls ~0.5s.

### Exact paths `RfsChatRelay.lua` tries (in order)

| # | SM path |
|---|---------|
| 1 | `$USER_DATA/rfs_discord_bridge/chat_inbox.json` |
| 2 | `$TEMP_DATA/rfs_discord_bridge/chat_inbox.json` |
| 3 | `$CONTENT_DATA/discord-bridge/inbox/chat_inbox.json` |
| 4 | `$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247/discord-bridge/inbox/chat_inbox.json` |

Point `CHAT_RELAY_PATH` at the matching `chat.jsonl` next to that inbox (same folder as vote). Prefer USER_DATA when Workshop content is read-only.

**Message format (in-game):** `[Discord] name: message` via `sm.gui.chatMessage`. JSON fields: `author`/`user`, `content`/`text`, `ts`, `id`. Empty / `direction:"out"` skipped; long text truncated; rate-limited per tick.

- Example lines: `inbox/chat.example.jsonl`
- Runtime `inbox/chat.jsonl` / `chat_inbox.json` are gitignored
- Vote path (`vote.json` / `RfsStreamer`) is unchanged

See `CONTRIBUTING.md`.

---

## Layout

```text
discord-bridge/
  package.json
  .env.example          ← commit
  .env                  ← do not commit
  .gitignore
  README.md
  CONTRIBUTING.md
  config/
    allowlist.json      ← host-editable; safe to commit defaults
  src/
    index.js            ← /ping + /vote + optional chat relay
    register-commands.js
    permissions.js      ← VOTE_CHANNEL_ID / STREAMER_ROLE_ID / ALLOW_EVERYONE_VOTES
    chat-relay.js       ← Discord → chat.jsonl + chat_inbox.json
  inbox/
    vote.example.json
    chat.example.jsonl
    vote.json / chat.jsonl / chat_inbox.json   ← runtime only
Scripts/game/
  RfsFeatures.lua
  RfsStreamer.lua
  RfsChatRelay.lua
```

Also: root `COMMANDS.txt` / `MODDER_API.txt` point here for Streamer / Discord.
