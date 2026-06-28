# MASTER_PLAN.md
## Bảo Vệ Đêm (Night Guard)
### A Vietnamese FNAF-style comedy-horror game — solo vibe-code build (Godot 4.7)

> This is the high-level plan and **current build status**. The deep, culturally-
> vetted design spec lives in [`docs/DESIGN.md`](docs/DESIGN.md); how the code is
> wired lives in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). This file
> supersedes the original 4-threat sketch — the game grew into a 2.5D, 6-threat,
> 6-night build with a **10-camera two-wing map**, a **finite-incense altar ritual**,
> a **3-clue Oan hồn investigation with two endings**, and an Extras hub
> (Bestiary / Tape Archive / Stats / Custom Night).

---

## 1. Concept

You are the new night guard at an old Vietnamese school, **Trường THCS Minh Phúc**.
Survive each shift from **12:00 AM → 6:00 AM** (midnight = giờ Tý, the witching
hour, is peak dread). Folklore threats approach from the dark; you juggle a camera
system, two doors, two lights, a **power (Điện)** bar and a **spirit (Vía)** bar,
plus offerings to the wandering souls and a roaming street-vendor shop.

- **Genre:** 2.5D survival horror-comedy (FNAF-like, Vietnamese folklore core).
- **Tone:** balanced comedy-horror — scares are real, the joke is on the guard,
  never on the beliefs (binding rules in DESIGN §1).
- **View:** pan-around 3D guard office + 2D camera feeds, threats and UI.
- **Language:** Vietnamese-primary, English toggle (full bilingual `strings.csv`).
- **Platform:** itch.io (free / name-your-own-price). Windows export ready.

---

## 2. What is built (this session)

A complete, **runnable** game — it boots to a menu, plays a tape, runs a full
6-night campaign with six distinct threats across a 10-camera two-wing map, runs an
investigation that branches into two endings, and wins/loses cleanly. The Extras
hub (Bestiary, Tape Archive, Stats, Custom Night) is wired off the main menu.

| Pillar | Status | Where |
|---|---|---|
| 2.5D guard office (pan, doors, lights, billboards, altar) | ✅ built in code | `scripts/systems/guard_room.gd` |
| Night loop: 12AM→6AM clock, power, vía (NORMAL/SHAKEN/CRITICAL), win/lose, jumpscare | ✅ | `scripts/systems/night_controller.gd` |
| Living-altar ritual: **finite "nhang" incense**, cold-draft guttering, bell, shrine upgrades | ✅ | `scripts/systems/night_controller.gd`, `shrine_screen.gd` |
| Camera monitor: **10 feeds** across two wings, CRT static/scanline shader, clickable floor-plan map | ✅ | `scripts/systems/camera_system.gd` |
| Threat AI base + director (FNAF 0–20 AI, per-night ramp) | ✅ | `scripts/threats/threat_base.gd`, `scripts/systems/threat_director.gd` |
| 6 folklore threats, each a **distinct mechanic** | ✅ | `scripts/threats/*.gd` |
| Offerings (cúng cô hồn) — appeasement, not killing | ✅ | inline in night_controller + `co_hon.gd` |
| Item / shop system, 14 items, sacred-never-cursed split | ✅ | `item_system.gd`, `item_registry.gd` |
| Dual-state vendor (real vs counterfeit, audio tell) | ✅ | `scripts/systems/vendor.gd` |
| Cassette-tape narrative + live phone calls, 1 set per night (bác Tư arc) | ✅ | `cassette_ui.gd`, `lore.gd`, `phone_system.gd`, `strings.csv` |
| **Oan hồn investigation**: 3 clues (phone name, classroom-cam drawing, tag-her photo) | ✅ | `phone_system.gd`, `camera_system.gd`, `night_controller.gd` |
| **Two endings**: *siêu thoát* (all 3 clues) vs survive epilogue | ✅ | `ending_screen.gd`, `save_manager.gd` |
| 6-night campaign + custom night, sequential unlocks, **atomic versioned save/progress** | ✅ | `game_state.gd`, `save_manager.gd` |
| Menus: main / night-select / settings / intro / win / game-over / pause | ✅ | `scripts/ui/*.gd` |
| Extras hub: **Bestiary (Hồ Sơ Ma) / Tape Archive / Stats / Custom Night / Credits / Ending** | ✅ | `scenes/screens/*` |
| Horror juice: reactive vignette, tension drone, screen shake, heartbeat, jumpscare punch-in | ✅ | `scripts/systems/night_controller.gd` |
| Night-1 hands-on tutorial (look → incense → door → cameras) | ✅ | `scripts/systems/night_controller.gd` |
| Bilingual VI/EN, proper diacritics (Be Vietnam Pro font) | ✅ | `localization/`, `assets/fonts/` |
| Settings: language, volumes, fullscreen, brightness, **scare-off**, difficulty | ✅ | `settings_manager.gd`, `settings_menu.gd` |
| Full SVG art set (room, 6 cams, 6 threats, vendor, UI, screens) | ✅ placeholder | `assets/art/` |
| Procedural audio (28 SFX + jumpscare + 2 ambiences) | ✅ placeholder | `assets/audio/`, `tools/gen_sfx.py` |
| Windows export preset | ✅ | `export_presets.cfg` |

Validated: parses clean, runs headless with no errors (incl. Night 6 / all threats /
both endings), and renders correctly on the real D3D12/Forward+ path. See `docs/shots/`.

> **Polish & hardening pass (2026-06-26).** An audit-driven shippability pass (no new
> mechanics) landed 36 fixes across balance (smoothed the N6 cliff, made offerings a real
> ongoing cost, fixed custom-night double-scaling), game feel (pause now ducks the audio
> bed; monitor lower fades; loop gain trims), transitions (door-tween lifecycle, fade input
> blocking), save robustness (.bak recovery now persists; `nights_won` no longer double-counts;
> forward-version guard), accessibility (scare-OFF now suppresses all shake/flash; REDUCED tier
> genuinely gentler), code health, and presentation. The headless self-test grew **96→100**
> checks (added save-robustness coverage) and stays **0 failed**. Full per-axis writeup +
> remaining-risk checklist in [`POLISH_NOTES.md`](POLISH_NOTES.md); native-speaker review list
> in [`docs/L10N_REVIEW.md`](docs/L10N_REVIEW.md).

---

## 3. Threat roster (summary — full design in DESIGN §2)

| Threat (vi) | Mechanic archetype | Counter |
|---|---|---|
| **Ông kẹ** | door-rusher (tutorial) + "be ngoan" | left door / behave |
| **Ma da** | water-lure "don't answer", rising flood | shut drain, ignore the cry, incense |
| **Cô hồn** | appeasement-economy swarm | keep the offering tray stocked |
| **Quỷ nhập tràng** | cat-prevention trigger (Mun) | divert the cat (right door / barrier) |
| **Ma trơi** | movement rule — panic = chased | move slowly, don't whip the view |
| **Oan hồn** | camera-attention paradox boss | brief glances, incense |
| **Bà hàng rong** | dual-state shop / impostor | read the street-cry; door the fake |

(*Ma lai*, the flying-head, is intentionally held for v2 — see DESIGN §2.7 for the
sensitivity reasoning.)

---

## 4. Shipped systems (now DONE — were "honest notes" in earlier drafts)

What earlier drafts of this plan listed as scaffolded or "deepen later" has since
landed and is live in code:
- **Oan hồn investigation + two endings — DONE.** A real 3-clue questline: `clue_name`
  (answer bác Tư's phone, Night 2+ — `phone_system.gd`), `clue_drawing` (the classroom
  camera hotspot, Night 3+ — `camera_system.gd`), and `clue_photo` (tag her on a feed —
  `night_controller.tag_anomaly`). Clearing Night 6 with all three → **siêu thoát** good
  ending; otherwise the **survive** epilogue (`ending_screen.gd`, `Save.investigation_complete()`).
- **Bestiary (Hồ Sơ Ma) — DONE.** A real `BestiaryScreen`, reachable from the Extras hub,
  reading name/desc/honesty-tag keys from `threat_registry.gd` + `strings.csv`; entries
  unlock as you encounter each spirit (`Save.see_threat`).
- **Tape Archive / Stats / Custom Night — DONE.** `TapeArchiveScreen` (re-listen to
  unlocked tapes), `StatsScreen` (deaths-by-threat, nights won, outages, offerings), and
  `CustomNightScreen` (set per-threat AI 0–20, Nightmare pacing) are all wired off the menu.
- **10-camera two-wing map — DONE.** Replaced the old 6-feed map with a symmetric FNAF-style
  approach: gate + courtyard, a left wing (canteen, classroom, library, left_hall) and a
  mirrored right wing (gym, restroom, infirmary, right_hall), converging on left/right
  doors and the office (`map_graph.gd`).
- **Finite incense ("nhang") altar ritual — DONE.** The altar is the primary active defense:
  a finite bundle of nhang per night, cold-draft guttering events, a one-job bell, and
  purchasable shrine upgrades — not a free "win button" (`night_controller.gd`, `shrine_screen.gd`).
- **Atomic, versioned saves — DONE.** `progress.cfg` writes are atomic (.tmp + rename, keeping
  a .bak); a corrupt file is preserved, not wiped; a `save_version` guards migrations
  (`save_manager.gd`).
- **Horror juice — DONE.** Reactive red vignette on low vía, tension drone, heartbeat loop,
  screen shake, and a punch-in jumpscare (scale-snap + white flash + jitter), all respecting
  the accessibility scare-off toggle.
- **Night-1 hands-on tutorial — DONE.** A frozen-sim lesson teaching look → incense → door →
  cameras before the night goes live.

These no longer block anything; the remaining gaps are the v2 backlog below.

## 4b. v2 backlog — genuinely not built yet

- **Đốt vía step-over ritual** as its own interaction (vía restore today is via
  offerings / incense / dawn; the step-over mini-game is not a distinct beat).
- ~~**Giật cô hồn scramble**~~ — **DONE (Pass 4)**: a ~4 s risk/reward beat after placing an
  offering (let the child-spirits take it for lộc, or press the offering key to guard it and
  slight the souls). Logic self-tested; feel/odds want playtest. See POLISH_NOTES Pass 4.
- ~~**Forbidden-offering fail-state**~~ — **DONE (Pass 4)**: an occasional, telegraphed
  mặn/lavish tray the souls refuse (a gentle, auto-fixing fail teaching the humble rule).
- ~~**Vendor on the camera feed**~~ — **DONE (Pass 4)**: she now shows on the gate feed while
  shopping/hostile (the warped-rao tell still does the work, never her face).
- **Ma lai bestiary entry** — the flying-head legend is held for v2 (sensitivity reasoning
  in DESIGN §2.7); it is not implemented and has no bestiary file.
- **Native-speaker VO + text proof** of `localization/strings.csv` (esp. tapes/phone).
- **Store-page assets** — itch.io capsule/screens/trailer for release.

---

## 5. How to continue (suggested order)

1. **Play it 5×** and tune `game_state.STORY` AI levels + `NightConfig` drains.
2. **Replace placeholder assets** (same filenames) — art in `assets/art/`, audio in
   `assets/audio/`. Add Vietnamese voice lines (bác Tư tapes/phone, "Mua không em?").
3. **Native-speaker proof** `localization/strings.csv` (esp. tapes + phone lines).
4. Pick off the **v2 backlog** (§4b) — step-over ritual, giật-cô-hồn scramble,
   forbidden-offering fail-state, vendor-on-camera sprite.
5. Export → itch.io (build the store-page assets).

---

## 6. Scope lock (v1) — resist these until v2
- Ma lai (flying head) full implementation, 3D free-movement, multiple floors,
  online leaderboard, mobile, more than the custom night beyond Night 6,
  branching dialogue trees. Keep the loop tight.

## 7. Ship checklist
- [x] Boots menu → intro → night without crashing
- [x] Win (6AM) and lose (caught / vía-0 / power-out) both resolve
- [x] All 6 threats move and can end the night
- [x] Vendor shop + counterfeit + hostile door-counter
- [x] Offerings, items, vía, power all function
- [x] 10-camera two-wing map + finite-incense altar ritual
- [x] 3-clue Oan hồn investigation → two endings (siêu thoát / survive)
- [x] Extras hub: Bestiary, Tape Archive, Stats, Custom Night, Credits
- [x] Atomic, versioned saves (corrupt-file safe)
- [x] Bilingual VI/EN with correct diacritics
- [x] Runs on the real renderer; Windows export preset ready
- [ ] Real art + audio + Vietnamese VO (placeholders shipped)  *(v2 backlog)*
- [ ] Native-speaker text proof  *(v2 backlog)*
- [ ] Store-page assets + itch.io page live  *(v2 backlog)*

*Working title: Bảo Vệ Đêm | Built with Godot 4.7 + Claude Code | Solo, vibe-coded.*
