---
project_name: 'Bảo Vệ Đêm (Nightwatch)'
user_name: 'Aiden'
date: '2026-06-30'
sections_completed: ['technology_stack','engine_rules','architecture_rules','performance_rules','organization_rules','testing_rules','platform_rules','gotchas']
existing_patterns_found: 6
status: 'complete'
optimized_for_llm: true
---

# Project Context for AI Agents

_Critical rules and unobvious traps for implementing game code in this project. Authoritative design/wiring lives in `docs/DESIGN.md` and `docs/ARCHITECTURE.md` — read those before changing systems. This file is the short list of things that are easy to get wrong._

---

## Technology Stack & Versions

- **Engine:** Godot **4.7**, Forward+ renderer. `project.godot` `config/features=("4.7","Forward Plus")`.
- **Language:** GDScript only. ~53 scripts under `scripts/{core,systems,threats,ui}`.
- **Rendering:** Vulkan with `rendering_device/fallback_to_d3d12=true` (widest launch coverage). MSAA 3D = 2. Do **not** force a driver.
- **Physics:** Jolt Physics (3D).
- **Display:** 1280×720 base; `window/stretch/mode="canvas_items"`, `aspect="expand"` (viewport renders at native window res, fills edge-to-edge). Min window 960×540.
- **Localization:** Godot translations, `vi` primary/fallback + `en`. Built from `localization/strings.csv` → `.translation` files.
- **Data:** `.tres` resources in `data/{threats,items,nights,lore}`.
- **Tooling:** Python `tools/gen_sfx.py` regenerates procedural SFX. Headless harnesses in `tools/`.

## Critical Implementation Rules

### Engine-Specific (Godot)

- **Autoload load order is load-bearing:** `Events → Settings → Save → Locale → Audio → Game → Router` (in `project.godot [autoload]`). Don't reorder; don't make an earlier autoload depend on a later one.
- **`Events` (event_bus.gd) is a stateless global signal bus.** Cross-system communication goes through `Events` signals, not direct node references. Add new cross-cutting signals there.
- **Globally-registered `class_name` types are NOT autoloads:** `GameEnums, NightConfig, ThreatDef, ItemDef, ThreatBase, MapGraph`. Reference them by class name; never `preload` a second copy.
- Player input uses the named actions in `project.godot [input]` (`pan_left/right`, `toggle_cameras`, `left_door`, `light_incense`, `ring_bell`, `answer_phone`, `use_item`, `close_drain`, etc.). Add a new binding there + a string label; don't read raw keycodes.

### Architecture / Threat contract (most violated by LLMs)

- **Threats are pure-logic `Node`s.** A threat holds its 2D textures + state (`current_location`, `phase`, `ai_level`). The 3D `GuardRoom` and the 2D `CameraSystem` monitor are **views** that read that state and draw it. **Threats never draw themselves in 3D.**
- **Subclass the `_behavior_*` hooks, never the director entry points.** The `ThreatDirector` calls `movement_check()`, `on_door()`, `on_light()`, `on_view()`, `on_via_state()`, `on_offering()`, `on_player_pan()`. Subclasses override `_behavior_move()` and friends and use the provided helpers (`move_to`, `advance_path`, `arrive_at_door`, `begin_attack`, `repel`, `reset_to_spawn`).
- **5 movement models:** PATH, WANDER, FLYER (unused — reserved for v2 ma_lai), STALKER (advances only when NOT viewed), CREEPER (freezes while player holds still). Capability flags decide the counter: `counter_door/light/view/offering/stillness`, `ignores_doors`.
- **`MapGraph` (scripts/systems/map_graph.gd) is the single source of truth** for the camera/location graph (ADJ, ordered camera list, MIRROR pairs, MAP_POS, BFS `distance()`). The in-code map drawing reads the *same* MAP_POS as the dots — never hardcode positions in a second place, or dots/rooms drift apart.
- **Shipped threats (6):** `ong_ke, ma_da, co_hon, quy_nhap_trang, ma_troi, oan_hon` + counterfeit vendor `ba_hang_rong` (in `vendor.gd`, not the director). **`ma_lai` is a debated v2 legend — no script, no registry entry. Do not assume it exists.**
- `NightController` (root of `scenes/Night.tscn`) owns the clock/power/vía economy, spawns threats from `NightConfig.threat_levels`, and routes endings. Final-night win → `Router.to_ending()`: **siêu thoát** if `Save.investigation_complete()` (all 3 Oan hồn clues) else survive epilogue.

### Localization

- **Never hardcode player-facing text.** All display strings live in `localization/strings.csv`; code resolves keys via `tr()` / `Locale.t(key, args)`. New UI text = new CSV key, both `vi` and `en` columns.
- Code identifiers stay English; threat ids are snake_case folklore names.

### Rendering gotchas (cost real debugging time)

- **All SVGs import at `svg/scale=2`.** A full-screen `TextureRect` defaults its minimum size to the texture's raster size, so a 1280×720 SVG rasterises to 2560×1440 and **overflows to 2× the canvas** under fill stretch modes — only the top-left quarter shows. Fix: full-screen fill TextureRects must set `expand_mode = EXPAND_IGNORE_SIZE` (handled in `UI.texture_rect` for SCALE / KEEP_ASPECT_COVERED). HUD/icon TextureRects in containers keep natural sizing.
- **Global brightness is a screen-space MULTIPLY shader** (in `scene_router.gd`), not a white overlay. Canvas shaders that *build* colour from scratch get washed by it — author them dark and let blacks be black. Texture-sampling shaders (camera feed) round-trip fine.
- Camera feed fit is object-fit:cover inside the feed shader (`rect_aspect` uniform per frame); don't reintroduce a stretch-scale.

### Performance

- Real-time survival loop; keep `_process`/`_physics_process` lean. Threat logic runs on per-threat cadences via the director (`movement_check` rolls `randf()*20 < ai_level`) — don't move per-frame polling into `_process`.
- Audio loops (heartbeat/drone/static) must be stopped on scene change — `Audio.stop_all_loops()` runs at the top of `Router.change_scene`. Any new sustained loop must be covered by that, or it bleeds across scenes.

### Code Organization

- `scripts/core/` = autoload singletons; `scripts/systems/` = night systems & views; `scripts/threats/` = ThreatBase + subclasses; `scripts/ui/` = HUD/menus/overlays.
- Game content as data: add a threat/item/night by authoring a `.tres` in `data/` + (for threats) a behavior script — not by hardcoding in the controller.
- Tools/tests live in `tools/`.

### Testing / Verification (always run before declaring done)

- **Headless self-test (grows with features, ~96 checks):**
  `godot --headless --path . res://tools/SelfTest.tscn` (env `NW_SKIP_TAPE=1 NW_NIGHT=6`).
- **Flow transitions:** `res://tools/FlowTest.tscn` verifies death→GameOver and win→WinScreen (headless `--quit-after` counts FRAMES, not seconds — await-timers need ~1600+ frames).
- **Integrity:** `res://tools/IntegrityCheck.tscn`. **Screenshots:** `res://tools/Shot.tscn` (`NW_SHOT_W/H`, `NW_OPEN_CAM`, `NW_LOOK_YAW/PITCH/FOV`).
- Godot binary: `C:\Users\DELL\Desktop\Godot_v4.7-stable_win64.exe`.
- **The first self-test run after a fresh import can abort early — re-run; subsequent runs are stable.**
- **Pixel-MEASURE screen edges/positions; never trust an eyeball on a windowed shot** (a real bug — a bezel border — was missed that way). When SVG-vs-code positions disagree, draw it in code from the single source of truth.
- **Night-1 tutorial needs input → not exercised headless;** verify it by compile + reasoning, flag it for a manual playtest.

### Platform & Build

- Target: **Windows** export (`export_presets.cfg`), `embed_pck=true`. Includes `LICENSE` + `assets/fonts/OFL.txt`.
- Atomic versioned saves: `.tmp`+rename+`.bak`, corrupt file copied to `*.corrupt` before defaults; `SAVE_VERSION` + `_migrate`. `user://progress.cfg` (Save) and `user://settings.cfg` (Settings).
- `Router` queues transitions (`_pending`) so end-of-night transitions aren't swallowed.

### Don't-Miss Summary

- Don't draw threats in 3D, don't override director entry points, don't hardcode strings or map positions, don't force a render driver, don't add a full-screen TextureRect without `EXPAND_IGNORE_SIZE`, don't author a canvas shader bright, don't reference `ma_lai`, don't skip the headless self-test + flow tests before saying "done".

---

## Usage Guidelines

**For AI Agents:** Read this file before implementing any game code. Follow all rules exactly; when in doubt, prefer the more restrictive option. The full design/wiring contract is `docs/DESIGN.md` + `docs/ARCHITECTURE.md` — this file only lists what's easy to get wrong.

**For Humans:** Keep it lean and trap-focused. Update when the stack, autoload order, or render pipeline changes, or when a new class of bug bites twice. Remove rules that become obvious.

Last Updated: 2026-06-30
