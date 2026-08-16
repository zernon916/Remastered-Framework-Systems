# Playtest checklist

Durable list for **Custom Game** playtest. The **parent agent updates this file** when the user reports pass or fail (`- [x]` / `- [ ]` plus a short note). Do **not** close GitHub issues until the user says so.

**Play path:** Scrap Mechanic → **Custom Game** (Remastered / Recipe Framework Survival). Do not use Mod Tool Test.

**Restore:** if a Rush item must be reverted, tag `rush-base` = `75abb2f`.

**Repo issues:** [zernon916/Remastered-Framework-Systems](https://github.com/zernon916/Remastered-Framework-Systems/issues) — fetched 2026-08-16 (`state=all`). Do not `gh issue close` from this checklist.

**Order:** hack menus first. MiniMap / LCD / traders come later.

---

## 1. Hack menus — Orders / hijack / Hack Control Infection

Do this block before HUD, map, signs, or traders.

- [ ] **E on powered beacon: Orders window visible AND cursor** — How: wire Battery + optional switch; E on Hack / Control / Infection. Pass: panel drawn **and** mouse cursor (not cursor-only / invisible window). Chat: menu visible ISH — confirm after last copy.
- [ ] **Open/close without flash-destroy (#1)** — How: E to open; CLOSE; E again; Esc; reopen several times. Pass: `queueOpen` / `cl_rfs_ordersOpen` — no flash, no destroy-on-E-frame, menu stays until you close it. Was working, then broke, then restored — **NEED RETEST** after last copy.
- [ ] **Select / Color / SHOW RANGE after list refresh** — How: open Orders, SET MASTER or wait for list refresh, then click a row, pick Color, toggle SHOW RANGE. Pass: those three still work after refresh, not only on first open / first Set Master.
- [ ] **Multi-select** — How: click more than one ally row (Ctrl/click as the GUI allows). Pass: ColorSelLabel lists several names; Color / orders apply to the set, not only the last row.
- [ ] **Row labels Seed 1 / Tote 1** — How: hijack a seedbot (tomato-crate farmer) and a tote; open the list. Pass: yellow name field shows **Seed 1** / **Tote 1** (or Hay N), not a bare number.
- [ ] **World nametag Seed N** — How: look at a hijacked seedbot in the world (UUID `4fbefe2d-83c7-4859-982e-1720f04079a3`, tomato-crate farmer). Pass: overhead **Seed N**, not `Bot N`.
- [ ] **Return walks to ITS converting device** — How: hijack from beacon A, open Orders on beacon B (or Master), set Return. Pass: Return is in the dropdown; the bot walks to **its** converting hack device (`hackBeaconKey`), not necessarily the menu you opened.
- [ ] **CLEAR MASTER persists Independent** — How: SET MASTER, CLOSE, CLEAR MASTER, reload the save / rejoin. Pass: role stays Independent after reload (not stuck Master).
- [x] **Thin SHOW RANGE ring + idle battery** — How: SHOW RANGE / HIDE RANGE on a powered beacon with no convert in progress. Pass: thin ground ring (do **not** thicken / recolor / weld onto the battery net); idle powered battery does not drain. **User confirmed Aug 16** (liked thin ring; battery perfect). GitHub **#6** stays open until the user says the *toggle after refresh* is done.
- [x] **Caps 2 / 4 / 6 per device** — How: convert onto Hack / Control / Infection until chat says cap reached. Pass: Hack **2**, Control **4**, Infection **6**; extra converts refused. Shared Orders pool does not raise the cap. **User tested Aug 16.**
- [x] **Master-off split (PARKED — skip)** — Known leftover: CLEAR MASTER does not re-split allies onto Independent devices. Do **not** “fix” as Rush. Skip unless the user asks to unpark.
- [ ] **Rename persist** — How: Orders NameEdit + RENAME; also E on a robot → APPLY; `/botname` optional. Reload the save. Pass: custom name still on the unit (list + overhead).
- [ ] **Farm / Collect / Collect Oil type-gated gray** — How: open a mixed list; try Farm on a tote, Collect on a hay, Oil on a non-water tote. Pass: wrong-type modes gray / no-op is **OK**. Fail if gating **blocks Return** (Return must stay usable on every type).

### GitHub issues (do not close until user says so)

Source: [Remastered-Framework-Systems issues](https://github.com/zernon916/Remastered-Framework-Systems/issues?q=is%3Aissue). Still open on GitHub until the user confirms, even if coded.

- [ ] **[#1](https://github.com/zernon916/Remastered-Framework-Systems/issues/1) Beacon Orders GUI flashes / closes immediately** — How: E open / CLOSE / E reopen. Pass: panel stays until you close it; no flash-destroy. Coded (`queueOpen`); **NEED RETEST** after last copy — do not close until user says so.
- [ ] **[#2](https://github.com/zernon916/Remastered-Framework-Systems/issues/2) Numbers/nametags above bots missing or incomplete** — How: look at several hijacked types (Hay / Tote / Seed / Farm). Pass: type+number overhead visible (Seed N, Tote N, …), not missing. Coded, needs playtest confirm — do not close until user says so.
- [ ] **[#3](https://github.com/zernon916/Remastered-Framework-Systems/issues/3) Bot naming (E on bot or hack-device rename)** — How: E-on-bot APPLY and Orders Name+RENAME; check overhead. Pass: custom name shows with the number; survives reload. Coded, needs playtest confirm — do not close until user says so.
- [ ] **[#4](https://github.com/zernon916/Remastered-Framework-Systems/issues/4) RAID should not affect bots out of farm range** — How: put a Farm/Collect/Oil ally outside home radius during a raid. Pass: that bot ignores RAID jam / range mul / raid notes. Coded (`allyIgnoresRaid`), needs playtest confirm — do not close until user says so.
- [ ] **[#5](https://github.com/zernon916/Remastered-Framework-Systems/issues/5) Empty ally list showing 0** — How: hijack 2+ bots, open Orders. Pass: list is not empty/0. May have become **#19** (1 of N). Coded, needs playtest confirm — do not close until user says so.
- [ ] **[#6](https://github.com/zernon916/Remastered-Framework-Systems/issues/6) SHOW/HIDE range toggle** — How: SHOW RANGE after first open **and** after list refresh / Set Master. Pass: thin ring appears/clears; menu does not die. Ring look + idle battery **user liked Aug 16**; issue stays open until user confirms the toggle is fully done — do not close until user says so.
- [ ] **[#7](https://github.com/zernon916/Remastered-Framework-Systems/issues/7) Raid list / timer not clearing when bots destroyed or captured** — How: start a raid, hijack or destroy the raiders. Pass: raid list/timer clears. Closed on GitHub as believed fixed. Coded, needs playtest confirm — do not close until user says so.
- [ ] **[#8](https://github.com/zernon916/Remastered-Framework-Systems/issues/8) Hack beacons missing E/Use** — How: look at a placed Hack/Control/Infection; press E when powered. Pass: Use prompt + Orders (not Tinker-only). Closed on GitHub as believed fixed. Coded, needs playtest confirm — do not close until user says so.
- [ ] **[#9](https://github.com/zernon916/Remastered-Framework-Systems/issues/9) Bot overhead text too large (FontSize 48→24)** — How: stand next to a tagged ally. Pass: nametag is half-size (24), not huge. Closed on GitHub as believed fixed. Coded, needs playtest confirm — do not close until user says so.
- [ ] **[#10](https://github.com/zernon916/Remastered-Framework-Systems/issues/10) Orders Close button did nothing** — How: OPEN then click CLOSE (not only Esc). Pass: GUI closes and E can open it again. Closed on GitHub as believed fixed. Coded, needs playtest confirm — do not close until user says so.
- [ ] **[#11](https://github.com/zernon916/Remastered-Framework-Systems/issues/11) Orders menu would not open (g_rfsGame RPC)** — How: E on powered beacon. Pass: window+cursor (this issue was closed as **partial**; remaining flash is **#1**). Do not close until user says so.
- [ ] **[#12](https://github.com/zernon916/Remastered-Framework-Systems/issues/12) Ally color presets on Beacon Orders** — How: Color dropdown with a selection and with none selected. Pass: tint sticks (not snapped back to default green). Closed on GitHub as believed shipped; in-game regression is **#15**. Do not close until user says so.
- [ ] **[#13](https://github.com/zernon916/Remastered-Framework-Systems/issues/13) Master/Slave hack beacon linking** — How: two powered devices in range; SET MASTER on one; open both. Pass: shared ally/order list; CLEAR MASTER → Independent (see persist item above). Closed on GitHub as believed fixed. Coded, needs playtest confirm — do not close until user says so.
- [x] **[#14](https://github.com/zernon916/Remastered-Framework-Systems/issues/14) ASCII Steam description / Remastered rename (docs)** — Docs/history tracker. **User confirmed** Custom Game tag / Remastered naming. Closed on GitHub.
- [ ] **[#15](https://github.com/zernon916/Remastered-Framework-Systems/issues/15) Orders Color does not apply** — How: select a bot (or none = all listed); pick a Color. Pass: ally tint changes and stays after AI tick / list refresh. Coded, needs playtest confirm — do not close until user says so.
- [ ] **[#16](https://github.com/zernon916/Remastered-Framework-Systems/issues/16) List click Select does not select the bot** — How: click icon / number / name row. Pass: row marks selected; ColorSelLabel updates. Coded, needs playtest confirm — do not close until user says so.
- [ ] **[#17](https://github.com/zernon916/Remastered-Framework-Systems/issues/17) Seed bots nametag shows Bot 1 instead of Seed 1** — How: hijack tomato-crate farmer (`4fbefe2d-…`). Pass: world tag **Seed 1** (not Bot 1). Coded, needs playtest confirm — do not close until user says so.
- [ ] **[#18](https://github.com/zernon916/Remastered-Framework-Systems/issues/18) Return bot to its hack beacon** — How: Return in the mode dropdown. Pass: bot walks to **its** converting device. Coded, needs playtest confirm — do not close until user says so.
- [ ] **[#19](https://github.com/zernon916/Remastered-Framework-Systems/issues/19) Ally list shows only 1 bot while multiple exist** — How: hijack 2+ (e.g. Bot 6 and Bot 7); open Orders. Pass: list shows **all** of them, not 1 of N. Related: **#5** empty/0 may have become this. Coded, needs playtest confirm — do not close until user says so.
- [ ] **[#20](https://github.com/zernon916/Remastered-Framework-Systems/issues/20) Defend / Hay / Tote / Water orders non-functional** — How: Defend on any; Farm on hay (+ seed); Collect on tote; Collect Oil on waterbot (blue tote). Pass: bots actually carry out the job, not only the dropdown caption. Type-gated gray on the wrong type is OK if Return still works. Coded, needs playtest confirm — do not close until user says so.

---

## 2. Session setup

- [x] **Custom Game launch tag** — How: Scrap Mechanic → Custom Game (not Mod Tool Test). Pass: Remastered / Recipe Framework Survival world. **User confirmed.**
- [ ] **`/rfsmenu` public** — How: as a non-admin client (or host), type `/rfsmenu` and `/menu`. Pass: player menu opens for everyone; `/rfsmenu` works if `/menu` is engine-reserved.
- [ ] **`/setup` admin** — How: host/admin types `/setup`; a non-admin client tries it. Pass: host/admin gets the setup GUI; regular clients do not.

---

## 3. HUD

- [ ] **Ammo HUD** — How: hold a gun with ammo; look at lower-right. Pass: ammo count stays visible; MiniMap / atlas do not cover it.
- [ ] **Block overlay** — How: `/menu` → Block overlay on; look at a creation. Pass: look-at HUD / world text (mass / shape-count). Not a per-block HP gradient (no engine API).
- [ ] **HP bars** — How: `/menu` Enemy / Neutral color cycle; look at a hostile and an ally. Pass: custom billboards use those colors (engine bars cannot be recolored). Allies/hacked use Neutral.
- [ ] **`/menu` Names + Big Red** — How: Names off/on; Big Red on a farmbot. Pass: nametags hide/show; farmbot label becomes **Big Red**.

---

## 4. Map

- [ ] **MiniMap HUD (Nutt 3780282057)** — How: subscribe Workshop **World Map** `3780282057`; do **not** enable it as a world mod. Walk around. Pass: corner MiniMap while walking; credit Nutt. If pack missing: original clock/compass/ammo still there.
- [ ] **`/map` atlas** — How: `/map` or `/rfsmap` or `/menu` Map. Pass: full atlas (Nutt) or lock-camera fallback; E / Esc / `/mapclose` exits.

---

## 5. Jobs (after Orders GUI is usable)

- [ ] **Stay / Recall / `/botorder` / Sentry** — How: Orders Stay (leash 16/32/48); Recall (walk to Orders home `workBeaconKey`, not Return’s hack device); `/botorder rest|defend|stay|recall|return|farm|collect|oil|sentry`; tapebot Sentry in dropdown. Pass: each mode does that job.
- [ ] **Painted chests + walk-to-chest** — How: yellow chest = seeds, green = produce, other/unpainted = drop-off; weld to beacon creation or Connect Tool to the beacon; Farm/Collect/Oil. Pass: bots walk to the right chest; doorway side-step if LOS blocked; M1–M5 jobs not scrambled.

---

## 6. Signs

- [ ] **Inventory LCD S / L / XL** — How: Craftbot LCDs `3c06e928` / `4d17fa39` / `5e280b4a`; weld/adjacent or LCD→chest wire. Pass: Small cycles one stack; L/XL list + scroll; logic switch can hide the face; chest does not loot-vacuum.
- [ ] **Text Digital Signs S / L / XL** — How: Craftbot Digital Sign; E to edit; optional logic switch. Pass: text shows; unpowered logic hides the face; no battery; UUID `f8c2a5e4-…` kept (not factory).

---

## 7. Traders

- [ ] **Hideout 1 crate → 80 seeds** — How: Farmers Hideout; spend 1 matching produce crate. Pass: you get **80** seeds. No Ally Factory / 200 Farmers factory listing.

---

## 8. Cheats

- [ ] **Cheats host/admin only** — How: enable cheats in `/gensettings`; try `/god` / `/hijack` as host vs a non-admin client. Pass: host/admin get cheats in the chat list; regular clients do not.
- [ ] **`/unlimited` does not unlock the world** — How: host types `/unlimited`. Pass: chat says the world-wide flag is **not** applied (would unlock all clients); inventories stay limited.

---

## 9. Pickup-dupe

- [ ] **Carry LMB does not clone the hotbar item** — How: pick up a large carryable; LMB / use while carrying. Pass: no cloned hotbar item; carry still works.

---

## 10. Factory CUT

- [ ] **Ally Factory GONE** — How: Craftbot + Hideout shop; search for factory shape / `RfsFactory` / 200 Farmers factory. Pass: **no** factory script, shape, or Hideout factory row. Digital Sign UUID unchanged. Crate→80 still exists (section 7).

---

## How to mark

| Mark | Meaning |
|------|---------|
| `- [ ]` | Not confirmed by the user this session |
| `- [x]` | User reported pass (or parked skip, noted) |
| Fail | Leave `[ ]` and add **FAIL:** one line under the item |

Parent agent: tick boxes here; do not close GitHub issues; do not copy to `C:\sm\RFS` or Workshop from this docs-only change.
