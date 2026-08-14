# RFS Discord Bridge — host guide (Streamer mode)

Scrap Mechanic Lua **cannot** make HTTP requests. This Node.js bot runs beside the **Scrap Mechanic host**, connects to Discord, and writes vote JSON to a **local drop file**. In-game `Scripts/game/RfsStreamer.lua` polls that file when **Streamer mode** is on and applies spawn/give via existing Survival cheat paths.

```text
Discord /vote  →  Node bridge  →  vote.json (disk)  →  RfsStreamer.sv_think  →  spawn / give
                                                                              ↓
                                                                    vote_result.json
                                                                              ↓
                                                         Node vote-resolve  →  Discord channel
```

Framework Lua hooks stay unchanged. This folder is only the external bridge.

**GitHub-only:** this `discord-bridge/` folder is **not** shipped in the Steam Workshop / `C:\sm\RFS` mod pack. Clone from [Recipe-Framework-Systems](https://github.com/zernon916/Recipe-Framework-Systems).

---

## Prerequisites

| Requirement | Notes |
|-------------|--------|
| **Node.js LTS** | `>=18` (`package.json` `engines`). Install from [nodejs.org](https://nodejs.org/). |
| Scrap Mechanic host | Usually **Windows**, or **Linux** (native / Proton). Same machine as the bot *unless* you only run Discord on another PC (Mac OK for bot-only; drop file must still reach the SM host). |
| Recipe Framework Survival | Local Custom Game or Workshop install. |
| Discord application | Bot token + invite with slash commands. |

### Platform notes (Scrap Mechanic vs this bot)

| OS | Scrap Mechanic | This Discord bot |
|----|----------------|------------------|
| **Windows** | Primary SM host | Full support (`npm start` / `npm run watch`) |
| **Linux** | Native or Steam Proton | Full support; set `DROP_PATH` (and optionally `RFS_BRIDGE_REQUEST_DIR`) to Proton/native USER_DATA |
| **macOS** | SM almost never runs here | Fine for **bot-only** Discord; put `DROP_PATH` on a path the Win/Linux SM host can read, or run the bot on the host PC instead |

Always prefer an explicit **`DROP_PATH`** env so the bot and Lua agree on one file.

---

## Quick start (all platforms)

```bash
git clone https://github.com/zernon916/Recipe-Framework-Systems.git
cd Recipe-Framework-Systems/discord-bridge
cp .env.example .env          # Windows cmd: copy .env.example .env
npm install
npm run register
```

**Option A — keep the bot running yourself:**

```bash
npm start
```

**Option B — one-click Start from in-game `/gensettings` → Discord tab:**

```bash
npm run watch
```

Run `npm run watch` once at login (or as a user service). Lua **cannot** launch Node; the Discord tab only writes `$USER_DATA/rfs_discord_bridge/start_request.json` / `stop_request.json`. The watcher polls that folder and spawns/stops `node src/index.js` via `child_process.spawn` (no `.bat` required).

Scripts (`start`, `watch`, `register`, `clean`) are plain `node` commands and work on Windows, Linux, and macOS. Optional Windows `.bat` / `.ps1` helpers are not required.

Then in-game: host world → **`/gensettings`** → **STREAMERS** tab → Streamer ON → Discord `/vote action:spawn unit:farmbot amount:1`.

---

## Windows / Linux / macOS setup

### Windows

1. Install [Node.js LTS](https://nodejs.org/).
2. Clone this repo and `cd discord-bridge`.
3. `copy .env.example .env` and fill `DISCORD_TOKEN`, `CLIENT_ID`, `GUILD_ID`.
4. Set `DROP_PATH` to a writable vote file Lua can read, for example:
   - USER_DATA (Workshop-safe):  
     `%AppData%\Axolot Games\Scrap Mechanic\User\User_<steamid>\rfs_discord_bridge\vote.json`
   - Local Custom Game pack:  
     `C:\sm\RFS\discord-bridge\inbox\vote.json` (only if that folder exists on the host; this GitHub folder is not inside Workshop)
5. `npm install` → `npm run register` → `npm start` or `npm run watch`.
6. For `/gensettings` Start/Stop: leave `npm run watch` running. Override scan with `RFS_BRIDGE_REQUEST_DIR` if needed.

### Linux

1. Install Node.js `>=18` (distro packages or [nodejs.org](https://nodejs.org/)).
2. Clone and `cd discord-bridge`; `cp .env.example .env`.
3. Prefer **`DROP_PATH`** pointing at the same file Proton/native SM uses. Common locations:
   - Native-style:  
     `~/.local/share/Axolot Games/Scrap Mechanic/User/User_<id>/rfs_discord_bridge/vote.json`
   - Steam Proton (appid **387990**):  
     `~/.steam/steam/steamapps/compatdata/387990/pfx/drive_c/users/steamuser/AppData/Roaming/Axolot Games/Scrap Mechanic/User/User_<id>/rfs_discord_bridge/vote.json`
   - Flatpak Steam often under:  
     `~/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/compatdata/387990/...`
4. Create the `rfs_discord_bridge` directory if missing; set the absolute path in `.env`.
5. `npm install` → `npm run register` → `npm start` or `npm run watch`.
6. Watcher auto-scans native + common Proton USER trees; set `RFS_BRIDGE_REQUEST_DIR` to skip scanning.

### macOS

1. Scrap Mechanic hosts are almost always **Windows or Linux**. You can still run this Node bot on a Mac for Discord connectivity.
2. Install Node.js LTS, clone, configure `.env` as above.
3. **`DROP_PATH` must be reachable by the SM host** (shared folder, sync, or run the bot on the host instead). Mac Application Support paths are rarely useful for SM.
4. `npm start` / `npm run register` work the same. `npm run watch` only helps if start/stop request files appear where the watcher looks — set `RFS_BRIDGE_REQUEST_DIR` (or `DROP_PATH`) explicitly.

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

1. Discord → **+** → **Create My Own** → make a private server for your stream / SM host.
2. Create a **vote** text channel (and optionally a **chat-relay** channel).
3. Create a **Streamer** (or viewer) role if you want role-gated votes.
4. Enable **Developer Mode** (Settings → Advanced) so you can copy IDs.

### Bot (Developer Portal)

1. [Discord Developer Portal](https://discord.com/developers/applications) → **New Application**.
2. **Bot** → Add Bot → **Reset Token** → `DISCORD_TOKEN`.
3. If you will use chat relay later: Bot → Privileged Gateway Intents → enable **Message Content Intent**.
4. OAuth2 → URL Generator:
   - Scopes: `bot`, `applications.commands`
   - Permissions: **Use Application Commands** (Send Messages optional; needed if the bot replies in channels)
5. Open the generated invite URL and add the bot to your server.
6. **Application ID** → `CLIENT_ID` (legacy alias `DISCORD_CLIENT_ID` still works).
7. Right-click server → **Copy Server ID** → `GUILD_ID` (legacy `DISCORD_GUILD_ID`). Guild slash registration is instant; global can take up to ~1h.

### Copy role / channel IDs into `.env`

| Discord UI | `.env` key |
|------------|------------|
| Right-click vote channel → Copy Channel ID | `VOTE_CHANNEL_ID` |
| Right-click result channel (optional) → Copy Channel ID | `RESULT_CHANNEL_ID` (Phase C; falls back to vote channel) |
| Right-click streamer role → Copy Role ID | `STREAMER_ROLE_ID` |
| Right-click chat channel → Copy Channel ID | `CHAT_CHANNEL_ID` (Discord → game relay) |

**Never commit `.env` or real tokens.**

---

## 2. Install & `.env`

```bash
cd discord-bridge
cp .env.example .env    # Windows cmd: copy .env.example .env
npm install
```

Essential keys:

```env
DISCORD_TOKEN=
CLIENT_ID=
GUILD_ID=

# Prefer USER_DATA (see Windows / Linux sections). Example Windows:
# DROP_PATH=C:\Users\<you>\AppData\Roaming\Axolot Games\Scrap Mechanic\User\User_<id>\rfs_discord_bridge\vote.json

# Optional gates (src/permissions.js — see below)
VOTE_CHANNEL_ID=
RESULT_CHANNEL_ID=
STREAMER_ROLE_ID=
ALLOW_EVERYONE_VOTES=false
VOTE_COOLDOWN_SEC=15

# Chat relay (Discord → file → in-game when /gensettings relay ON)
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

## 3. DROP_PATH — USER_DATA vs content paths

### Prefer writable USER_DATA (Workshop-safe)

Workshop `$CONTENT_*` is often **read-only**. Prefer USER_DATA — `RfsStreamer.lua` polls it **first**:

| OS | Typical bridge folder |
|----|------------------------|
| Windows | `%AppData%\Axolot Games\Scrap Mechanic\User\User_<id>\rfs_discord_bridge\` |
| Linux (native) | `~/.local/share/Axolot Games/Scrap Mechanic/User/User_<id>/rfs_discord_bridge/` |
| Linux (Proton) | `…/compatdata/387990/pfx/drive_c/users/steamuser/AppData/Roaming/Axolot Games/Scrap Mechanic/User/User_<id>/rfs_discord_bridge/` |
| macOS | SM host is usually elsewhere — share that host's USER_DATA path or run the bot on the host |

Create `rfs_discord_bridge` if needed, set `…/vote.json` as `DROP_PATH`.

### Local Custom Game pack

Only when the pack folder is writable on the **SM host** (example Windows path):

```env
DROP_PATH=C:\sm\RFS\discord-bridge\inbox\vote.json
```

This GitHub `discord-bridge` is **not** inside the Workshop upload; do not assume Workshop content contains it.

### Exact paths `RfsStreamer.lua` tries (in order)

From `Scripts/game/RfsStreamer.lua` (`VOTE_PATHS`):

| # | SM path | Typical Windows meaning |
|---|---------|-------------------------|
| 1 | `$USER_DATA/rfs_discord_bridge/vote.json` | `%AppData%\Axolot Games\Scrap Mechanic\User\User_<id>\rfs_discord_bridge\vote.json` |
| 2 | `$TEMP_DATA/rfs_discord_bridge/vote.json` | SM temp user data + same relative folder |
| 3 | `$CONTENT_DATA/discord-bridge/inbox/vote.json` | Active content root → `discord-bridge/inbox/vote.json` |
| 4 | `$CONTENT_29c99287-1213-48c7-9471-19a4a5c12247/discord-bridge/inbox/vote.json` | RFS pack `localId` content folder |

Point `DROP_PATH` at **one** file the host can read. Prefer **#1** when Workshop content is read-only.

---

## 4. Register commands & start

| Script | Action |
|--------|--------|
| `npm run register` | Deploy `/ping` and `/vote` (`src/register-commands.js`) |
| `npm start` | Run the bot; also re-registers when `CLIENT_ID` is set |
| `npm run watch` | Poll `$USER_DATA/rfs_discord_bridge/start_request.json` / `stop_request.json` and spawn/stop the bot (for `/gensettings` Discord tab) |
| `npm run clean` | Delete inbox runtime JSON files |

```bash
npm run register
npm run watch
```

Keep `npm run watch` (or `npm start`) running while you host. Startup logs the resolved drop path, cooldown, and `ALLOW_EVERYONE_VOTES`.

Watcher env:

| Env | Behavior |
|-----|----------|
| `RFS_BRIDGE_REQUEST_DIR` | Absolute path to `rfs_discord_bridge` (skip User_* scan) |
| `DROP_PATH` | If set, watcher also polls that file's directory |
| `RFS_BRIDGE_POLL_MS` | Poll interval ms (default `1000`) |

---

## 5. Enable Streamer in-game

1. Host a **Recipe Framework Survival** world.
2. Open **`/gensettings`** (host-only) → **STREAMERS** → turn **Streamer mode** **ON**.
3. Optional: **DISCORD** tab → chat relay ON; **Start Discord bot** if `npm run watch` is already running.
4. `RfsFeatures.streamerModeEnabled()` gates polling; off → votes ignored (safe no-op).
5. Only the **host** runs `RfsStreamer.sv_think` (~0.5s).

---

## 6. Test: `/vote` → Farmbot

Units/items must appear in `config/allowlist.json` (Lua caches after load; use `/gensettings` → Reload allowlist after edits).

```text
/vote action:spawn unit:farmbot amount:1
```

Bridge writes atomically (temp → rename), for example:

```json
{
  "id": "…",
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
| `amount` | no | 1–20 (default 1) |

---

## Allowlist

**Full edit remains JSON** (no in-game list editor):

1. Pack / content default: `discord-bridge/config/allowlist.json`
2. Optional host override (checked first by `RfsStreamer.lua`): `$USER_DATA/rfs_discord_bridge/allowlist.json` (then `$TEMP_DATA/…`, then content paths)

### Phase C — preview / reload in `/gensettings`

Host **`/gensettings` → STREAMERS** shows:

| Control | Behavior |
|---------|----------|
| **Allowlist: Units: N \| Items: M (file\|builtin)** | Summary from the same load paths as `RfsStreamer` |
| **Reload allowlist** | Clears the Lua cache and re-reads the file (or builtin defaults) |
| **Unit: name (i/n)** | Cycles unit aliases for a quick preview (not an editor) |

Edit the JSON on disk, then press **Reload allowlist** (Node also reloads `config/allowlist.json` on each `/vote`). Bot restart is not required.

- `units[]` — spawn aliases (`farmbot`, `haybot`, …)
- `items[]` — `{ "alias", "uuid", "name?" }` for give

Aliases must also be understood by `RfsStreamer.lua` (`UNIT_ALIAS`) or be a raw unit UUID.

---

## Drop JSON schema

| Field | Notes |
|-------|--------|
| `id` | UUID / unique id — RfsStreamer skips repeats |
| `action` | `"spawn"` \| `"give"` |
| `unit` / `item` | Spawn alias or give UUID |
| `amount` | Count |
| `source` | `"discord"` |
| `voter` | Discord user snowflake |
| `createdAt` | ISO-8601 |
| Legacy | `ts`, `uuid` (give), `quantity` — still written for older readers |

`RfsStreamer.lua` accepts `item`/`uuid`, `amount`/`quantity`, `unit`/`unitName`/`name`.

---

## Vote resolve feedback (Phase C — game → Discord)

After a successful apply or a **permanent** reject (not allowlisted / unknown unit), `RfsStreamer.lua` writes `vote_result.json` next to the consumed vote (same bridge roots; prefers the folder of the vote file, then `$USER_DATA/rfs_discord_bridge/…`).

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

- `✅ Streamer: spawned farmbot x1`
- `❌ Streamer: unit not allowlisted`

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

- Missing file / Streamer off / not host → no-op.
- Unknown unit/item → Discord rejects before write; bad in-file votes skipped.
- Per-user cooldown; optional channel/role gates.
- `.env` gitignored — never commit tokens.
- Standalone package (not shared with other Discord bots). No Steam push from this workflow.

---

## Chat relay (Discord → game)

`src/chat-relay.js` is attached from `src/index.js`. When `CHAT_RELAY_ENABLED=true` and `CHAT_CHANNEL_ID` is set, non-bot messages in that channel append to `inbox/chat.jsonl` and refresh `inbox/chat_inbox.json` (JSON companion for Lua — Scrap Mechanic cannot `sm.json.open` JSONL). Enable **Message Content Intent** in the Developer Portal.

| Env | Behavior |
|-----|----------|
| `CHAT_RELAY_ENABLED` | Default `false`. Set `true` to listen. |
| `CHAT_CHANNEL_ID` | Required to actually listen; if unset while enabled → safe no-op. |
| `CHAT_RELAY_PATH` | Optional absolute path (default `inbox/chat.jsonl`). Companion is sibling `chat_inbox.json`. |

**In-game:** `/gensettings` → **DISCORD** → **Discord chat relay: ON** (`RfsFeatures.streamerChatRelayEnabled()`, default OFF). Host-only `RfsChatRelay.sv_think` polls ~0.5s.

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

---

## Chat outbox (game → Discord, Phase D)

Scrap Mechanic cannot hook freeform player chat. Use **`/say your message`** or **`/d your message`** in-game.

| Piece | Role |
|-------|------|
| `Scripts/game/RfsChatOutbox.lua` | Host writes `$USER_DATA/rfs_discord_bridge/chat_outbox.json` (and CONTENT fallbacks) as `{ messages:[{id,author,content,ts,source:"game",direction:"out"}] }` |
| `src/chat-outbox.js` | Polls outbox ~1s, posts to `CHAT_CHANNEL_ID` (or `OUT_CHANNEL_ID`), tracks last `id` |
| Gate | **Streamer ON** + **Discord chat relay ON** in `/gensettings` **DISCORD** tab (`streamerChatRelay`) |

**Bot env:** `CHAT_OUTBOX_ENABLED` defaults to follow `CHAT_RELAY_ENABLED` when unset. Set `CHAT_OUTBOX_PATH` if the outbox is under USER_DATA (same folder as `vote.json`).

**Loop safety:** Lua tags `direction:"out"` / `source:"game"`; bot skips `direction:"in"`, `source:"discord"`, `[Discord]` prefixes, and Discord bot authors (relay ignores bots). Bot posts are not re-ingested into the game inbox.
