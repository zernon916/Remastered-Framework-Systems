# Discord / Streamer companion

**GitHub-only.** Not bundled in the Steam Workshop pack.

## In-game Streamer

- Host `/gensettings` → enable **Streamer** (and Discord chat relay if wanted).
- Game polls vote/chat JSON drops under:

  `%USER_DATA%/rfs_discord_bridge`

- Discord `/vote` (via the companion) writes a local JSON drop; `RfsStreamer` applies spawn/gives.

## Companion bot (separate process)

1. Clone https://github.com/zernon916/Remastered-Framework-Systems  
   (older remote name `Recipe-Framework-Systems` redirects here)
2. Open folder `discord-bridge/`
3. Configure `.env`
4. Run:

```text
npm install
npm run watch
```

Watcher polls start/stop requests written by the `/gensettings` Discord tab.

## Community

- Discord: https://discord.gg/DfjDMRx9ab
- Author: Zernon916

See also `discord-bridge/README.md` in the GitHub clone and `COMMANDS.txt` Streamer section.
