# Architecture — Bảo Vệ Đêm

This is the technical contract for the codebase. Read it before changing systems.

## High-level

A FNAF-style "stationary survival" loop rendered in **2.5D**: a real 3D guard
room you pan/look around, with **2D** camera feeds, threats, and UI on top. You
survive each night from **00:00 to 06:00**. Threats advance toward your two doors;
you watch cameras, close doors, flash lights, place offerings, and use items —
all while juggling a draining **Điện (power)** bar and a **Vía (spirit/sanity)** bar.

## Autoload singletons (load order matters)

| Name | Script | Responsibility |
|---|---|---|
| `Events` | `scripts/core/event_bus.gd` | Global signal bus. No state. |
| `Settings` | `scripts/core/settings_manager.gd` | Audio/display/accessibility/difficulty. `user://settings.cfg`. |
| `Save` | `scripts/core/save_manager.gd` | Progress, bestiary, tapes, stats. `user://progress.cfg`. |
| `Locale` | `scripts/core/locale_manager.gd` | vi/en switching. `Locale.t(key, args)`. |
| `Audio` | `scripts/core/audio_manager.gd` | `play_sfx`, `start_loop/stop_loop`, `play_music`, `play_jumpscare`. |
| `Game` | `scripts/core/game_state.gd` | Which night/difficulty; builds `NightConfig`; progression. |
| `Router` | `scripts/core/scene_router.gd` | Fade scene transitions + global brightness. |

Globally-registered (via `class_name`, not autoloads): `GameEnums`, `NightConfig`,
`ThreatDef`, `ItemDef`, `ThreatBase`.

## The camera / location graph

Locations are string ids. Six are camera-viewable; two are door thresholds; one is
the office (you). Threats traverse this graph.

```
            gate (CAM1)
           /    |     \
   left_hall  courtyard  right_hall
   (CAM2)    (CAM6)      (CAM3)
     |    \   /   \       |
 left_door classroom    restroom
     |     (CAM5)        (CAM4)
     |                     |
   OFFICE  <----------  right_door
```

- Camera feeds: `gate, left_hall, right_hall, restroom, classroom, courtyard`
- Door thresholds (not on cameras; seen via door lights): `left_door, right_door`
- `office` = game over if a threat reaches it uncountered.
- `Locations` (in `scripts/systems/map_graph.gd`, `class_name MapGraph`) holds the
  adjacency, the camera list, and which side each door is.

## ThreatBase contract (`scripts/threats/threat_base.gd`, `class_name ThreatBase`)

A threat is a `Node` (pure logic + its 2D textures). The **room** and the
**camera monitor** are its *views* — they read `current_location` and the threat's
textures to draw it. Threats never draw themselves in 3D.

Configured by the director via `setup(def, ai_level, controller)`.

Movement models (`movement_model`):
- `PATH` — fixed ordered route to a door (e.g. Ma da, Ông kẹ).
- `WANDER` — random walk along adjacency (Cô hồn).
- `FLYER` — like PATH but `ignores_doors = true`; countered by light/offering (Ma lai).
- `STALKER` — only advances while the player is NOT viewing its camera (view-gated).
- `CREEPER` — freezes while the player holds still / doesn't pan (Quỷ nhập tràng).

Capability flags (how it is countered):
`counter_door, counter_light, counter_view, counter_offering, counter_stillness, ignores_doors`.

Key runtime state: `ai_level: float`, `current_location: String`, `phase` (GameEnums.ThreatPhase),
`threatening_side` (GameEnums.Side when AT_DOOR).

Director-driven entry points (the director calls these; subclasses override the
`_behavior_*` hooks, not these):
- `movement_check()` — called on this threat's cadence; rolls `randf()*20 < ai_level`
  to decide whether to act, then calls `_behavior_move()`.
- `on_door(side, closed)`, `on_light(side, on)`, `on_view(is_viewing_my_cam)`,
  `on_via_state(state)`, `on_offering(location)`, `on_player_pan(is_panning)`.

Helpers ThreatBase provides to subclasses: `move_to(loc)`, `advance_path()`,
`arrive_at_door(side)`, `begin_attack()`, `repel(to_location)`, `reset_to_spawn()`.

Emits via `Events`: `threat_relocated`, `threat_at_door`, `threat_left_door`,
`threat_repelled`, `threat_reset`, and on a successful kill → `Events.game_over(id)`
(after `Events.jumpscare_started(id)`).

## NightController (`scripts/systems/night_controller.gd`)

Root script of `scenes/Night.tscn`. Owns the night:
- Clock: advances game-minutes using `NightConfig.seconds_per_hour`; emits
  `Events.clock_advanced` / `hour_reached`; at hour 6 → `Events.night_survived`.
- Power: drains from idle + open doors + lights + camera use; at 0 → power-out
  (doors open, lights die, vulnerability spikes); emits `Events.power_changed/power_depleted`.
- Vía: drains from staring at threats, darkness, scares; restored slowly when calm /
  via offerings/incense; emits `Events.via_changed/via_state_changed`.
- Spawns threats from `NightConfig.threat_levels`, owns the `ThreatDirector`.
- Spawns the Vendor if enabled. Holds `ItemSystem` + `OfferingSystem`.
- Listens for `Events.game_over` → `Router.to_game_over(cause)`;
  `Events.night_survived` → record + `Router.to_win()`.

Node paths inside `Night.tscn` (views read these):
```
Night (NightController)
├─ GuardRoom (Node3D, guard_room.gd)      # 3D room + Camera3D pivot, doors, lights
├─ Threats (Node)                          # ThreatBase instances added at runtime
├─ Vendor (Node, vendor.gd)
├─ Systems (Node)
│  ├─ Director (ThreatDirector)
│  ├─ Items (ItemSystem)
│  └─ Offerings (OfferingSystem)
└─ UI (CanvasLayer)
   ├─ HUD (Control, hud.gd)
   ├─ Monitor (Control, camera_system.gd)  # hidden until raised
   ├─ Shop (Control, shop_ui.gd)           # hidden
   ├─ Cassette (Control, cassette_ui.gd)   # hidden
   └─ Pause (Control, pause_menu.gd)       # hidden
```

## GuardRoom (`scripts/systems/guard_room.gd`)

- `Camera3D` on a yaw pivot; mouse-X / `pan_left|pan_right|pan_reset` rotate it
  within ±~55°. Emits `Events.view_panned(yaw)`. `facing_side()` → LEFT/RIGHT/null.
- Doors: `set_door(side, closed)` animates the 3D shutter; drains power while closed.
- Lights: `set_light(side, on)` toggles a doorway SpotLight; while on, a `Sprite3D`
  shows any threat AT_DOOR on that side (the "flash to check" mechanic).
- Raising the monitor disables panning; lowering re-enables.

## CameraSystem / Monitor (`scripts/systems/camera_system.gd`)

- Toggled by `toggle_cameras` / CAM button → `Events.cameras_toggled(is_open)`.
- Shows the selected feed (`assets/art/cameras/cam_<loc>.svg`) with a CCTV tint,
  static, and scanlines; a map panel switches feeds → `Events.camera_changed(loc)`.
- Draws each threat whose `current_location` == feed loc using the threat's texture.
- Viewing a feed sets "is the player watching cam X" → feeds `on_view` to threats.

## Item effects (dispatched by `ItemSystem.apply(effect_id, item)`)

| effect_id | result |
|---|---|
| `slow_ghosts` | global ghost speed ×0.5 for `duration` |
| `reveal_all` | show all threat positions on cameras for `duration` |
| `reset_nearest` | send the closest threat back to spawn |
| `restore_via` | +`magnitude` vía |
| `seal_one_door` | one door free (no power) for `duration` |
| `speed_ghosts` | (cursed) ghost speed ×2 for `duration` |
| `drain_power` | (cursed) −`magnitude`% power now |
| `summon_vendor` | (cursed) vendor returns soon |
| `blind_cams` | (cursed) static on all cams for `duration` |

Items are `ItemDef` resources in `data/items/`. Kind (HELPFUL/CURSED) is hidden
from the UI — the player learns by using them.

## Offerings (`scripts/systems/offering_system.gd`)

Place a `mâm cúng` (offering tray) — respectfully tied to *cúng cô hồn*. Calms
wandering souls: pauses/relocates `counter_offering` threats and restores a little
vía. Limited count per night (`NightConfig.offerings_start` + shop).

## Data resources

- `data/nights/night_<n>.tres` (optional; else `Game.STORY` table builds it).
- `data/threats/<id>.tres` (`ThreatDef`: identity + scene + spawn).
- `data/items/<id>.tres` (`ItemDef`).
- Lore/cassette text: `data/lore/tape_<n>.json` (bilingual lines).

## Conventions

- Player-facing strings live in `localization/strings.csv` only; code uses keys via
  `tr()` / `Locale.t()`. Never hardcode display text.
- Code identifiers in English; comments concise. Threat ids are snake_case folklore
  names (`co_hon`, `ma_da`, `ong_ke`, `ma_lai`, `quy_nhap_trang`, `ba_hang_rong`).
