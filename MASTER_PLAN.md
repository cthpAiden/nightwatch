# MASTER_PLAN.md
## Bảo Vệ Đêm (Night Guard)
### A Vietnamese FNAF-style comedy-horror game — solo vibe-code build (Godot 4.7)

> This is the high-level plan and **current build status**. The deep, culturally-
> vetted design spec lives in [`docs/DESIGN.md`](docs/DESIGN.md); how the code is
> wired lives in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). This file
> supersedes the original 4-threat sketch — the game grew into a 2.5D, 6-threat,
> multi-night build.

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

A complete, **runnable** vertical slice of the whole game — it boots to a menu,
plays a tape, runs a full night with six distinct threats, and wins/loses cleanly.

| Pillar | Status | Where |
|---|---|---|
| 2.5D guard office (pan, doors, lights, billboards, altar) | ✅ built in code | `scripts/systems/guard_room.gd` |
| Night loop: 12AM→6AM clock, power, vía (NORMAL/SHAKEN/CRITICAL), win/lose, jumpscare | ✅ | `scripts/systems/night_controller.gd` |
| Camera monitor: 6 feeds, CRT static/scanline shader, clickable floor-plan map | ✅ | `scripts/systems/camera_system.gd` |
| Threat AI base + director (FNAF 0–20 AI, per-night ramp) | ✅ | `scripts/threats/threat_base.gd`, `scripts/systems/threat_director.gd` |
| 6 folklore threats, each a **distinct mechanic** | ✅ | `scripts/threats/*.gd` |
| Offerings (cúng cô hồn) — appeasement, not killing | ✅ | inline in night_controller + `co_hon.gd` |
| Item / shop system, 14 items, sacred-never-cursed split | ✅ | `item_system.gd`, `item_registry.gd` |
| Dual-state vendor (real vs counterfeit, audio tell) | ✅ | `scripts/systems/vendor.gd` |
| Cassette-tape narrative, 1 per night (bác Tư arc) | ✅ | `cassette_ui.gd`, `lore.gd`, `strings.csv` |
| 6-night campaign + custom night, sequential unlocks, save/progress | ✅ | `game_state.gd`, `save_manager.gd` |
| Menus: main / night-select / settings / intro / win / game-over / pause | ✅ | `scripts/ui/*.gd` |
| Bilingual VI/EN, proper diacritics (Be Vietnam Pro font) | ✅ | `localization/`, `assets/fonts/` |
| Settings: language, volumes, fullscreen, brightness, **scare-off**, difficulty | ✅ | `settings_manager.gd`, `settings_menu.gd` |
| Full SVG art set (room, 6 cams, 6 threats, vendor, UI, screens) | ✅ placeholder | `assets/art/` |
| Procedural audio (28 SFX + jumpscare + 2 ambiences) | ✅ placeholder | `assets/audio/`, `tools/gen_sfx.py` |
| Windows export preset | ✅ | `export_presets.cfg` |

Validated: parses clean, runs headless with no errors (incl. Night 6 / all threats),
and renders correctly on the real D3D12/Forward+ path. See `docs/shots/`.

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

## 4. Honest notes — simplified for v1, deepen later

These work and are fun, but are lighter than the full DESIGN vision:
- **Oan hồn investigation / multiple endings:** the camera-paradox + incense counter
  is implemented; the multi-night clue-gathering that yields the *siêu thoát* "good
  ending" is scaffolded (Save flags) but not yet a full questline. Currently:
  survive Night 6 = survivor ending.
- **Đốt vía ritual & giật cô hồn scramble:** vía restore via offerings/incense/dawn
  is in; the step-over ritual mini-game and the offering-scramble risk/reward beat
  are not yet their own interactions.
- **Forbidden-offering fail-state:** offerings currently always succeed (the humble
  tray); the "wrong food fails" teaching beat is not yet surfaced as a choice.
- **Bestiary (Hồ Sơ Ma) screen:** data + honesty tags exist in `threat_registry` +
  `strings.csv`; the viewer screen itself is a TODO (Extras menu).
- **Vendor on the camera feed:** she's audio + toast cued; no on-cam sprite yet.

None of these block play; they're the obvious next iterations.

---

## 5. How to continue (suggested order)

1. **Play it 5×** and tune `game_state.STORY` AI levels + `NightConfig` drains.
2. **Replace placeholder assets** (same filenames) — art in `assets/art/`, audio in
   `assets/audio/`. Add Vietnamese voice lines (bác Tư tapes, "Mua không em?").
3. **Native-speaker proof** `localization/strings.csv` (esp. the tapes).
4. Build out the **Bestiary** screen and the **Oan hồn ending** questline.
5. Export → itch.io.

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
- [x] Bilingual VI/EN with correct diacritics
- [x] Runs on the real renderer; Windows export preset ready
- [ ] Real art + audio + Vietnamese VO (placeholders shipped)
- [ ] Native-speaker text proof
- [ ] itch.io page live

*Working title: Bảo Vệ Đêm | Built with Godot 4.7 + Claude Code | Solo, vibe-coded.*
