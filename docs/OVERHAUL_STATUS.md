# Mass-improve overhaul — status & resume point

Aiden asked Claude to do a full "mass improve" pass on Nightwatch acting as game
designer + architect + audio designer + graphics designer. Three audit agents swept the
whole codebase (design/architecture, audio, graphics) and the findings became the plan
below. Aiden approved: **mechanics/balance changes are allowed** this round, and a **perf
cleanup pass is bundled in**. Work proceeds phase by phase — tests green before each commit,
one commit per phase.

## Progress

- **Phase 1 (graphics grading) — DONE, pushed** (commit `d0c883a`, 2026-07-02): all 10 room
  `.tscn` files now carry the filmic tonemap/SSAO/glow/adjustment grade block; fixed a real
  bug where CSG `Inner`/door/window subtraction brushes had no material (rendered flat
  white) by giving them the room's wall material; MSAA 2X added to camera-feed + desk CRT
  viewports. SelfTest 119/0, IntegrityCheck 36/0 confirmed before push.
- **Phase 2 (rim lights + smoke) — started, not committed.** Pick up here next.
- Phases 3-6 — not started.

## Resume here (in order)

- **Phase 2**: doorway rim lights (`OmniLight3D` per doorway, energized from
  `ThreatBase.accent_color` when a threat is AT_DOOR — `accent_color` is defined in
  `scripts/threats/threat_base.gd` but currently unused) + living incense smoke (per-puff
  RNG jitter + second harmonic on the 4 Sprite3D puffs in `scripts/systems/guard_room.gd`
  ~line 533-555, replacing the mechanical fixed-phase sway). Render office, run tests,
  commit.
- **Phase 3** (audio): `scripts/threats/oan_hon.gd` is a completely silent threat — needs
  whisper/sting_breath telegraphs at agro thresholds. Wire `phone_ring_warp` (SFX generated,
  never played) into fake/vendor calls. Play `clock_tick` and `fluorescent_hum` (both
  generated, never played). Add `ui_hover` on all menu buttons (currently only cassette_ui
  has it). Stereo-pan threats by side. Complete the REDUCED scare-tier volume scaling onto
  the VERB_BUS stings. New SFX go through `tools/gen_sfx.py`, appended at the **end of the
  file only** — see the RNG-cascade note below. Regenerate, confirm old WAVs are
  byte-identical, tests, commit.
- **Phase 4** (design telegraphs + one mechanic): teach the "ngoan" ông kẹ counter (exists
  but is never taught to the player); add a blackout early-warning; add tag-anomaly/giật cô
  hồn outcome feedback; add a Mun cam-dot pulse cue. Also: the vendor hostile branch almost
  never fires — raise its probability and add a SelfTest case for it. VI+EN strings in
  `localization/strings.csv`. Tests + FlowTest, commit.
- **Phase 5** (perf hot-paths, audit-confirmed): `threat_at_door()` is scanned 6×/frame in
  `night_controller.gd` — memoize per frame. Monitor threat nodes rebuild 4×/sec in
  `camera_system.gd::_refresh_threats` — only rebuild on state change. Desk CRT threat
  texture is rescanned every frame — cache on `camera_changed`. HUD warning string rebuilt
  every frame — only rebuild when the source changes. Tests, commit.
- **Phase 6** (final verify + push): re-render all 10 rooms + office; SelfTest +
  IntegrityCheck + FlowTest all green; delete `tools/gfx_shot.gd` (still present, untracked,
  throwaway render harness — safe to delete, or regenerate the same way if needed again);
  push; report to Aiden with before/after shots.

## How to render / test (reference)

- Godot binary: `C:\Users\datdo\OneDrive\Desktop\Godot_v4.7-stable_win64.exe` (adjust path on
  other devices).
- SelfTest: `NW_SKIP_TAPE=1 NW_NIGHT=6 <godot> --headless --path . res://tools/SelfTest.tscn`
  → expect **119/0**.
- IntegrityCheck: `<godot> --headless --path . res://tools/IntegrityCheck.tscn` → expect
  **36/0**.
- FlowTest: `NW_FLOW=death|win NW_SKIP_TAPE=1 NW_NIGHT=<n> <godot> --headless --path .
  res://tools/FlowTest.tscn` — don't pass `--quit-after`; it self-quits with PASS/FAIL after
  ~3644 frames. Grep output for PASS/FAIL.
- Visual verification needs a real GPU: drop `--headless` (this machine has an RTX 3060). A
  `SceneTree` script (`-s res://tools/foo.gd`) building a `SubViewport` with `UPDATE_ALWAYS`,
  loading a room `.tscn`, waiting ~1.8s, then `get_root().get_texture().get_image()
  .save_png(...)` gives a clean feed render. Delete throwaway `tools/*.gd` render/bench
  scripts once done with them (`tools/gfx_shot.gd` is the current one, still around).
- After editing SVGs / `.import` flags / `strings.csv`: run `<godot> --headless --import .`
  to rebuild the `.ctex`/`.translation` cache; the `.translation` binaries are tracked in
  git and should be committed.
- `gen_sfx.py` uses a single seeded RNG with a strict draw-order — **never insert a new
  sound's `noise()`/random draw in the middle of the file**, always append new sound
  functions at the end, or every later WAV shifts and stops matching what's already
  committed/tested.

## Working style for this overhaul

- One phase at a time: implement → run SelfTest/IntegrityCheck (+FlowTest where relevant) →
  only commit once green → move to the next phase.
- Each phase is its own commit (don't squash phases together).
- Don't touch: CCTV/CRT/menu/jumpscare shaders (already tuned), placeholder threat figure
  geometry (Aiden is making real assets later), and don't reintroduce BMad/heavy planning
  frameworks — plain implement-test-commit.

---

# Graphics-quality presets + FPS overhaul (separate pass, branch `graphics-overhaul`)

A distinct effort from the mass-improve pass above: a player-selectable **Low/Medium/High**
graphics preset that reconciles "richer atmosphere" with "runs on weak hardware." Low is the
integrated-GPU floor. Environments are **not** centralised (each room keeps its authored mood);
instead a runtime applier overlays the preset's perf knobs.

## What landed
- **`scripts/core/graphics_quality.gd`** — new autoload `Graphics`. `apply_to_env` (SSAO/glow on
  Medium+, volumetric fog + optional SDFGI on High), `apply_to_viewport` (Low = FSR2 @ 0.7 render
  scale + FXAA, Medium = MSAA 2×, High = TAA; positional shadow atlas 2048/4096/8192),
  `apply_to_lights` (positional shadows dropped below Medium, authored state stashed in node meta
  so a live switch restores exactly), `cctv_viewport_size` (640×360 Low / 960×540 else).
- **`settings_manager.gd`** — `graphics_quality` (+ `sdfgi_enabled`) persisted under `[display]`;
  first-run default auto-detected from the GPU name (integrated → Low).
- **Wire-in**: `camera_system.gd::_mount_room` (per-room feed env + msaa + lights, size from preset)
  and `guard_room.gd::_build_environment`/end of `_ready` (office env + root viewport + lights).
  Both re-apply on `Events.settings_changed` for a live mid-night preset switch.
- **`scripts/ui/debug_overlay.gd`** — F3 perf HUD (FPS, cpu/phys ms, draw calls, prims, VRAM,
  nodes, current preset). Hidden by default; added in `night_controller._build_ui`.
- **Settings UI + L10n**: preset dropdown + GI toggle in `settings_menu.gd`; new `SET_GRAPHICS`,
  `GFX_*`, `SET_SDFGI(_HELP)`, `SET_GFX_HELP` keys in `strings.csv` (`.translation` rebuilt).

## Verified
- SelfTest **119/0**, IntegrityCheck **36/0**, FlowTest death+win **PASS** (win needs `NW_FASTWIN=1`).
- Real-renderer boot clean (Vulkan/Forward+). **Still TODO: measure FPS per preset via F3 in an
  actual played night** — needs interactive driving, not done here.

## Corrections to the reference notes above
- This machine's Godot binary is `C:\Users\DELL\Desktop\Godot_v4.7-stable_win64_console.exe`
  (the `datdo\OneDrive` path above is a different device).
- The dev GPU here is a **GTX 1050** (low-end discrete), not an RTX 3060 — reinforces the Low floor.
- A killed headless run corrupts `.godot/imported` (missing fonts/samples → cascading Nil UI). If
  that happens, delete `.godot` and re-run `--import` to completion.
