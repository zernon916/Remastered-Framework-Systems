-- World Map: BUILD FLAGS - the one place the release and the dev copy differ.
--
-- ONE codebase ships TWO mods. minimap-mod\mod\ is the Workshop release that
-- Eric's main custom game loads; minimap-mod\mod-dev\ is a local copy with its
-- own localId, its own item uuids and its own imageset prefix, generated from
-- mod\ by tools/make_dev_mod.py (ship.py runs it). The generator rewrites the
-- values in THIS FILE and nothing else in the Lua ever forks.
--
-- NEVER hand-edit mod-dev\Scripts\Flags.lua. It is regenerated on every ship
-- and any edit there is lost - and worse, it is an invitation to let the dev
-- copy diverge, which is the whole thing this file exists to prevent.
--
-- Adding a feature flag:
--   1. declare it below as false. Release-safe by default, always - a
--      half-finished feature must not be one forgotten line away from the
--      Workshop.
--   2. add it to DEV_FLAGS in tools/make_dev_mod.py to switch it on for dev.
--   3. read it as `g_wmFlags.NAME` at CALL time. Do NOT copy it into a local
--      at load time: BigMap.lua and Waypoint.lua are dofile'd by MinimapHud
--      and script load order across the mod is not ours to depend on.
--   4. when the feature is good enough for players, delete the flag and the
--      old branch - flags are scaffolding, not configuration.
--
-- A flag is also how a behavior change gets A/B'd in ONE build: keep the old
-- path alive under `if not g_wmFlags.X then` until Eric confirms the new one.
--
-- test_mod.py fails the build if DEV is true in mod\, so a dev-only flag can
-- never reach the Workshop by accident.

g_wmFlags = {
	-- true ONLY in the generated dev mod. It marks the big map title
	-- ("WORLD MAP  v1.0.0  DEV b6") and the stats file, so a screenshot or a
	-- telemetry read can never be pinned on the wrong copy - the exact class
	-- of confusion that cost three builds during M3/M4.
	DEV = false,

	-- BUG-4 candidate fix: generation-stamp the waypoint pin/ghost widget
	-- names once per map session, so every session gets brand-new names and
	-- the engine cannot serve cached per-name widget state. This is the v35
	-- remedy that fixed the garbled cells, applied to the pins that never got
	-- it. UNCONFIRMED against the real cause - the "wpui" events in
	-- bm_events.json say whether Lua thought the phantom pin was hidden.
	-- Flip OFF in dev to A/B the old fixed names in the same build.
	WP_FRESH_NAMES = false,

}
-- (HELD_TP_POSE shipped: the third-person hold pose was confirmed by Eric on
-- build 40 ("placement is good") after four bakes, so the branch is gone and
-- setTpRenderables simply takes the TP mesh. FP and TP are two separate meshes
-- for good - a .rend carries no transform, so a pose can only live baked in the
-- geometry, and the two poses are genuinely different.
-- HELD_DEVICE shipped: the in-hand GPS with the vanilla sway was confirmed on
-- build 33 and its flag deleted. The three HELD_* diagnostics - control carrot, rend variants, pose picker -
-- lived here across builds 12-16 and were deleted once each had answered its
-- question. BUG-5's WP_COMMIT_ON_DRAG_END lived here for one build. Eric confirmed it
-- in-game on b7, so the branch was deleted and drag-end commit is simply how
-- the map works now. That is the intended end state for every flag here.)
