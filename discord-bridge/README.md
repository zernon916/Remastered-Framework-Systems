# RFS Discord Bridge Ã¢â‚¬â€ host guide (Streamer mode)

Scrap Mechanic Lua **cannot** make HTTP requests. This Node.js bot runs on the **same PC as the SM host**, connects to Discord, and writes vote JSON to a **local drop file**. In-game `Scripts/game/RfsStreamer.lua` polls that file when **Streamer mode** is on and applies spawn/give via existing Survival cheat paths.

```text
Discord /vote  â†’  Node bridge  â†’  vote.json (disk)  â†’  RfsStreamer.sv_think  â†’  spawn / give
                                                                              â†“
                                                                    vote_result.json
                                                                              â†“
                                                         Node vote-resolve  â†’  Discord channel
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
git clone https://github.com/zernon916/Recipe-Framework-Systems.git
cd Recipe-Framework-Systems\discord-bridge
copy .env.example .env
npm install
npm run register
```

**Option A — keep the bot running yourself:**

```bat
npm start
```

**Option B — one-click Start from in-game `/gensettings` → Discord tab:**

```bat
npm run watch
```

Run `npm run watch` once at Windows login. Lua **cannot** launch Node; the Discord tab only writes `$USER_DATA/rfs_discord_bridge/start_request.json` / `stop_request.json`. The watcher polls that folder and runs `npm start` / stops the child.

This `discord-bridge` folder is **GitHub-only** — it is **not** included in the Steam Workshop / `C:\sm\RFS` mod pack.

Then in-game: host world → **`/gensettings`** → **STREAMERS** tab → Streamer ON → Discord `/vote action:spawn unit:farmbot amount:1`.

---

## In-game `/gensettings` tabs

| Tab | Contents |
|-----|----------|
| **MAIN** | Cheats, hack devices (beacons), anchor / area loader |
| **FEATURES** | Hackable robots, RFS quests content |
| **STREAMERS** | Streamer mode, vote cooldown, vote announce, allowlist summary / reload / unit cycle |
| **DISCORD** | Discord→game chat relay, Start/Stop bot request files, DROP path hint |

---

## 1. Create a Discord server + bot

### Server

1. Discord Ã¢â€ â€™ **+** Ã¢â€ â€™ **Create My Own** Ã¢â€ â€™ make a private server for your stream / SM host.
2. Create a **vote** text channel (and optionally a **chat-relay** channel).
3. Create a **Streamer** (or viewer) role if you want role-gated votes.
4. Enable **Developer Mode** (Settings Ã¢â€ â€™ Advanced) so you can copy IDs.

### Bot (Developer Portal)

1. [Discord Developer Portal](https://discord.com/developers/applications) Ã¢â€ â€™ **New Application**.
2. **Bot** Ã¢â€ â€™ Add Bot Ã¢â€ â€™ **Reset Token** Ã¢â€ â€™ `DISCORD_TOKEN`.
3. If you will use chat relay later: Bot Ã¢â€ â€™ Privileged Gateway Intents Ã¢â€ â€™ enable **Message Content Intent**.
4. OAuth2 Ã¢â€ â€™ URL Generator:
   - Scopes: `bot`, `applications.commands`
   - Permissions: **Use Application Commands** (Send Messages optional; needed if the bot replies in channels)
5. Open the generated invite URL and add the bot to your server.
6. **Application ID** Ã¢â€ â€™ `CLIENT_ID` (legacy alias `DISCORD_CLIENT_ID` still works).
7. Right-click server Ã¢â€ â€™ **Copy Server ID** Ã¢â€ â€™ `GUILD_ID` (legacy `DISCORD_GUILD_ID`). Guild slash registration is instant; global can take up to ~1h.

### Copy role / channel IDs into `.env`

| Discord UI | `.env` key |
|------------|------------|
| Right-click vote channel â†’ Copy Channel ID | `VOTE_CHANNEL_ID` |
| Right-click result channel (optional) â†’ Copy Channel ID | `RESULT_CHANNEL_ID` (Phase C; falls back to vote channel) |
| Right-click streamer role â†’ Copy Role ID | `STREAMER_ROLE_ID` |
| Right-click chat channel â†’ Copy Channel ID | `CHAT_CHANNEL_ID` (Discord â†’ game relay) |

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

# Optional gates (src/permissions.js Ã¢â‚¬â€ see below)
VOTE_CHANNEL_ID=
# Phase C: vote apply/reject announce (optional; falls back to VOTE_CHANNEL_ID)
RESULT_CHANNEL_ID=
STREAMER_ROLE_ID=
ALLOW_EVERYONE_VOTES=false
VOTE_COOLDOWN_SEC=15

# Chat relay (Discord â†’ file â†’ in-game when /gensettings relay ON)
CHAT_RELAY_ENABLED=false
CHAT_CHANNEL_ID=
```

If `DROP_PATH` is empty, the bot writes `discord-bridge/inbox/vote.json` (default in `src/index.js`).

### Optional vote locks (`src/permissions.js`)

Wired into `/vote` via `canVote()` in `src/index.js` (cooldown stays in index).

| Env | Behavior |
|-----|----------|
| `VOTE_CHANNEL_ID` | If set, `/vote` only in that channel. Also fallback for Phase C result announces. |
| `RESULT_CHANNEL_ID` | Optional Phase C announce channel for apply/reject (`vote_result.json`). |
| `STREAMER_ROLE_ID` | If set and `ALLOW_EVERYONE_VOTES` is not `true`, require this role. |
| `ALLOW_EVERYONE_VOTES` | Default `false`. Set `true` to skip the role check. |
| `VOTE_COOLDOWN_SEC` | Per-user cooldown in `index.js` (default `15`). |

If `STREAMER_ROLE_ID` is unset, role checks are skipped (channel lock and cooldown still apply).

---

## 3. DROP_PATH Ã¢â‚¬â€ local `C:\sm\RFS` vs Workshop

### Prefer writable AppData (Workshop-safe)

Workshop `$CONTENT_*` is often **read-only**. Prefer USER_DATA Ã¢â‚¬â€ `RfsStreamer.lua` polls it **first**:

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
| 3 | `$CONTENT_DATA/discord-bridge/inbox/vote.json` | Active content root Ã¢â€ â€™ `discord-bridge\inbox\vote.json` |
| 4 | `$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247/discord-bridge/inbox/vote.json` | RFS pack `localId` content folder |

Point `DROP_PATH` at **one** file the host can read. Prefer **#1** when Workshop content is read-only; use **#3/#4** for a local writable `C:\sm\RFS` install.

---

## 4. Register commands & start

| Script | Action |
|--------|--------|
| `npm run register` | Deploy `/ping` and `/vote` (`src/register-commands.js`) |
| `npm start` | Run the bot; also re-registers when `CLIENT_ID` is set |
| `npm run watch` | Poll `$USER_DATA/rfs_discord_bridge/start_request.json` / `stop_request.json` and spawn/stop the bot (for `/gensettings` Discord tab) |
| `npm run clean` | Delete inbox runtime JSON files |

```bat
npm run register
npm run watch
```

Keep `npm run watch` (or `npm start`) running while you host. Startup logs the resolved drop path, cooldown, and `ALLOW_EVERYONE_VOTES`.

---

## 5. Enable Streamer in-game

1. Host a **Recipe Framework Survival** world.
2. Open **`/gensettings`** (host-only) → **STREAMERS** → turn **Streamer mode** **ON**.
3. Optional: **DISCORD** tab → chat relay ON; **Start Discord bot** if `npm run watch` is already running.
4. `RfsFeatures.streamerModeEnabled()` gates polling; off → votes ignored (safe no-op).
5. Only the **host** runs `RfsStreamer.sv_think` (~0.5s).

---

## 6. Test: `/vote` → Farmbot

Units/items must appear in `config/allowlist.json` (Lua caches after load; use `/gensettings` â†’ Reload allowlist after edits).

```text
/vote action:spawn unit:farmbot amount:1
```

Bridge writes atomically (temp Ã¢â€ â€™ rename), for example:

```json
{
  "id": "Ã¢â‚¬Â¦",
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
| `amount` | no | 1Ã¢â‚¬â€œ20 (default 1) |

---

## Allowlist

**Full edit remains JSON** (no in-game list editor):

1. Pack / content default: `discord-bridge/config/allowlist.json`
2. Optional host override (checked first by `RfsStreamer.lua`): `$USER_DATA/rfs_discord_bridge/allowlist.json` (then `$TEMP_DATA/â€¦`, then content paths)

### Phase C â€” preview / reload in `/gensettings`

Host **`/gensettings` → STREAMERS** shows:

| Control | Behavior |
|---------|----------|
| **Allowlist: Units: N \| Items: M (file\|builtin)** | Summary from the same load paths as `RfsStreamer` |
| **Reload allowlist** | Clears the Lua cache and re-reads the file (or builtin defaults) |
| **Unit: name (i/n)** | Cycles unit aliases for a quick preview (not an editor) |

Edit the JSON on disk, then press **Reload allowlist** (Node also reloads `config/allowlist.json` on each `/vote`). Bot restart is not required.

- `units[]` â€” spawn aliases (`farmbot`, `haybot`, â€¦)
- `items[]` â€” `{ "alias", "uuid", "name?" }` for give

Aliases must also be understood by `RfsStreamer.lua` (`UNIT_ALIAS`) or be a raw unit UUID.

---

## Drop JSON schema

| Field | Notes |
|-------|--------|
| `id` | UUID / unique id Ã¢â‚¬â€ RfsStreamer skips repeats |
| `action` | `"spawn"` \| `"give"` |
| `unit` / `item` | Spawn alias or give UUID |
| `amount` | Count |
| `source` | `"discord"` |
| `voter` | Discord user snowflake |
| `createdAt` | ISO-8601 |
| Legacy | `ts`, `uuid` (give), `quantity` Ã¢â‚¬â€ still written for older readers |

`RfsStreamer.lua` accepts `item`/`uuid`, `amount`/`quantity`, `unit`/`unitName`/`name`.

---

## Vote resolve feedback (Phase C â€” game â†’ Discord)

After a successful apply or a **permanent** reject (not allowlisted / unknown unit), `RfsStreamer.lua` writes `vote_result.json` next to the consumed vote (same bridge roots; prefers the folder of the vote file, then `$USER_DATA/rfs_discord_bridge/â€¦`).

```json
{
  "id": "<voteId>",
  "ok": true,
  "action": "spawn",
  "detail": "spawned farmbot x1",
  "error": null,
  "ts": "2026-08-14T15:00:00Z"
}
```

`src/vote-resolve.js` (attached from `index.js`) polls that file ~1s. On a new `id` it posts once:

- `âœ… Streamer: spawned farmbot x1`
- `âŒ Streamer: unit not allowlisted`

Then marks the file `consumed: true` (and remembers the last id) so restarts do not spam.

| Env | Behavior |
|-----|----------|
| `RESULT_CHANNEL_ID` | Optional announce channel. |
| `VOTE_CHANNEL_ID` | Fallback when `RESULT_CHANNEL_ID` is empty. |
| `RESULT_PATH` | Optional absolute path to `vote_result.json` (default: sibling of `DROP_PATH`). |

**Host enable:** set `VOTE_CHANNEL_ID` and/or `RESULT_CHANNEL_ID`, point `DROP_PATH` at the same folder Lua uses for votes, keep Streamer ON, restart `npm start`. Example file: `inbox/vote_result.example.json`.

Transient failures (no player / spawn error) leave the vote file and do **not** write a result until apply or permanent reject.

---

## Safety

- Missing file / Streamer off / not host Ã¢â€ â€™ no-op.
- Unknown unit/item Ã¢â€ â€™ Discord rejects before write; bad in-file votes skipped.
- Per-user cooldown; optional channel/role gates.
- `.env` gitignored Ã¢â‚¬â€ never commit tokens.
- Standalone package (not shared with other Discord bots). No Steam push from this workflow.

---

## Chat relay (Discord â†’ game)

`src/chat-relay.js` is attached from `src/index.js`. When `CHAT_RELAY_ENABLED=true` and `CHAT_CHANNEL_ID` is set, non-bot messages in that channel append to `inbox/chat.jsonl` and refresh `inbox/chat_inbox.json` (JSON companion for Lua â€” Scrap Mechanic cannot `sm.json.open` JSONL). Enable **Message Content Intent** in the Developer Portal.

| Env | Behavior |
|-----|----------|
| `CHAT_RELAY_ENABLED` | Default `false`. Set `true` to listen. |
| `CHAT_CHANNEL_ID` | Required to actually listen; if unset while enabled â†’ safe no-op. |
| `CHAT_RELAY_PATH` | Optional absolute path (default `inbox/chat.jsonl`). Companion is sibling `chat_inbox.json`. |

**In-game:** `/gensettings` → **DISCORD** → **Discord chat relay: ON** (`RfsFeatures.streamerChatRelayEnabled()`, default OFF). Host-only `RfsChatRelay.sv_think` polls ~0.5s.

### Exact paths `RfsChatRelay.lua` tries (in order)
  RfsChatOutbox.lua

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
  .env.example          â† commit
  .env                  â† do not commit
  .gitignore
  README.md
  CONTRIBUTING.md
  config/
    allowlist.json      â† host-editable; safe to commit defaults
  src/
    index.js            ← /ping + /vote + optional chat relay + vote resolve
    start-watcher.js    ← poll USER_DATA start/stop_request.json (GitHub-only; npm run watch)
    register-commands.js
    permissions.js      ← VOTE_CHANNEL_ID / STREAMER_ROLE_ID / ALLOW_EVERYONE_VOTES
    chat-relay.js       ← Discord → chat.jsonl + chat_inbox.json
    chat-outbox.js      ← game → Discord (Phase D)
    vote-resolve.js     ← vote_result.json → Discord announce
  inbox/
    vote.example.json
    vote_result.example.json
    chat.example.jsonl
    vote.json / vote_result.json / chat.jsonl / chat_inbox.json / chat_outbox.json   ← runtime only
Scripts/game/
  RfsFeatures.lua
  RfsStreamer.lua
  RfsChatRelay.lua
  RfsChatOutbox.lua
```

**Not in Steam Workshop / `C:\sm\RFS`:** this entire `discord-bridge/` folder. Clone from GitHub for the bot + watcher.

Also: root `COMMANDS.txt` / `MODDER_API.txt` / `PHASES.md` point here for Streamer / Discord.


## Chat outbox (game → Discord, Phase D)

Scrap Mechanic cannot hook freeform player chat. Use **`/say your message`** or **`/d your message`** in-game.

| Piece | Role |
|-------|------|
| `Scripts/game/RfsChatOutbox.lua` | Host writes `$USER_DATA/rfs_discord_bridge/chat_outbox.json` (and CONTENT fallbacks) as `{ messages:[{id,author,content,ts,source:"game",direction:"out"}] }` |
| `src/chat-outbox.js` | Polls outbox ~1s, posts to `CHAT_CHANNEL_ID` (or `OUT_CHANNEL_ID`), tracks last `id` |
| Gate | **Streamer ON** + **Discord chat relay ON** in `/gensettings` **DISCORD** tab (`streamerChatRelay`) |

**Bot env:** `CHAT_OUTBOX_ENABLED` defaults to follow `CHAT_RELAY_ENABLED` when unset. Set `CHAT_OUTBOX_PATH` if the outbox is under USER_DATA (same folder as `vote.json`).

**Loop safety:** Lua tags `direction:"out"` / `source:"game"`; bot skips `direction:"in"`, `source:"discord"`, `[Discord]` prefixes, and Discord bot authors (relay ignores bots). Bot posts are not re-ingested into the game inbox.
