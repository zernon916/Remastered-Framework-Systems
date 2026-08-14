# Recipe Framework Survival (GitHub)

Clean repository for **Recipe Framework Survival (RFS)** only — Scrap Mechanic Custom Game pack plus `discord-bridge`.

This tree is prepared for GitHub; it is not a Steam Workshop upload source by itself.

## Push

**Push from Desktop `RecipeFrameworkSurvival` when the user asks.**  
Do not push or commit from this workflow unless explicitly requested. Preferred git root:

`C:\Users\benko\Desktop\RecipeFrameworkSurvival`

(Local working copy / host Custom Game may live under `RecipeFrameworkSurvival-local-backup` or `C:\sm\RFS` — sync into the Desktop folder first, then commit/push from there when asked.)

## Docs

- Player overview: `README.txt`
- Phase roadmap: `PHASES.md`
- Steam blurb: `STEAM_DESCRIPTION.txt`
- Discord bridge: `discord-bridge/README.md`
- Modder API: `MODDER_API.txt`
- Pending fixes log: `PENDING_FIXES.md`

Do not commit `.env`, `node_modules`, or live `discord-bridge/inbox` vote/chat/result data (see `.gitignore`).
