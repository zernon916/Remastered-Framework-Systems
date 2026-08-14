# Modder hooks

Deep reference: pack file **`MODDER_API.txt`**. Checklist / JSON schemas: **`AUTHOR_GUIDE.txt`** and `AUTHOR_SNIPPET/`.

Custom Game localId: `29c99287-1213-48c7-9471-19a4a5c12247`

## Store / shop hooks

Implemented in `ModRecipeScan.lua` + Hideout / Mining Hub traders.

| Target | Ship this in your B&P mod |
|--------|---------------------------|
| Craftbot | `CraftingRecipes/craftbot.json` (unlockable schematics; not auto-unlocked) |
| Hideout | `CraftingRecipes/hideout_trades.json` (or wrapper `hideout.json` with `currencyItemId` + `trades`) |
| Mining Hub | `CraftingRecipes/mininghub_trades.json` |
| Loot (optional) | `CraftingRecipes/loot.json` |

- Currency for Hideout is forced to Farmers (`8d601982-4608-4d5e-bb9e-e4041486f7c7`).
- Survival `hideout.json` is **never written** to disk (checksum-safe).
- Missing shapes on a peer are skipped (no ghost BLOCK NOT FOUND rows).
- Dedupe by itemId; first registered wins.

Guest mods are discovered via **ModDatabase** `descriptions.json` (subscribe only; do not enable as a world mod).

## Progression (honest scope)

No vault / chapter tree editor. Supported paths:

- Unlockable Craftbot recipes unlocked via Hideout schematic trade, quest rewards, or host `/unlock*` when cheats are on
- Quest rewards through Survival's normal CompleteQuest / GrantSchematics path

## Feature flags

Pack `rfs_settings.json`: `frameworkOnly`, `setupQuestTab`, `cheats`.  
World overrides: host `/gensettings` (RfsFeatures storage). Flags gate RFS gameplay content only — never the store merge or RfsQuest API.

## Quest API — `_G.RfsQuest`

Thin wrappers around Survival QuestManager (`Scripts/game/RfsQuest.lua`):

- `isActive` / `isComplete` / `getStage` / `getActive`
- `activate` / `tryActivate` / `complete` / `abandon`
- `onActivate` / `onComplete` Lua callbacks
- Optional metadata: `Quests/rfs_quests.json` via `RfsQuest.loadModQuestMeta`

You still need a Survival-style quest ScriptableObject for real quest logic.

## Ally hooks

- `_G.g_rfsIsPlayerAlly(unit)`
- `_G.g_rfsPlayerAllies` (ally table)

Optional Intelligentia paste: `AUTHOR_SNIPPET/Intelligentia_ally_skip.lua`.
