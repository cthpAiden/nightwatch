# POLISH_NOTES.md — shippability pass (2026-06-26)

> ## Pass 3 — full-game "make it feel WAY better" pass
> An exhaustive 12-aspect critique (gameplay loop, balance, onboarding, juice, audio, UI/UX,
> threat design, narrative, extras, accessibility, code, art) produced **84 findings**; the
> high-value, in-scope set (~55) was applied as **91 edits** across 32 files. **No new features;
> screen resolution/display untouched** (per a known bug). Highlights:
> - **Feel/juice:** directional door-arrival cue (side-pitched sting + HUD light flash); success
>   spikes on repel/bell/anomaly-tag; HUD bar tween + hit-flash; Ma trơi startle shake; dawn-win
>   relief beat; weightier screen shake; surging crowd overlay.
> - **Clarity/onboarding:** toast queue + length-scaled dwell (story lines stay readable); meter
>   threats teach their counter the first time they hurt; tutorial now teaches the doorway light;
>   pause menu shows a 3-clue checklist.
> - **Balance/economy:** shop items & shrine upgrades share one currency scale; anti-farm commits
>   on win only (stuck players keep earning); N5 wisp softened so the peak lands on N6; early-night
>   dead air trimmed; Custom Night pace relaxed off NIGHTMARE.
> - **UX:** visible keyboard focus + disabled-button styles; button press/click juice; reachable
>   Settings + Reset-to-defaults + live slider %; Stats nemesis/endings/custom rows; Bestiary
>   discovered-count + fear; animated intro/ending backdrops.
> - **Narrative:** the wronged girl is named **Linh** so the climax pays off (EN; VI flagged for
>   native review); clearer endings/credit copy ("Built with Godot 4").
> - **Audio/art:** unstacked the hourly chime collision and the door double-hit; deeper, longer
>   cricket ambience; hostile-doorway glow tint; ghost temperature split; removed 6 dead-art SVGs.
>
> Deferred (flagged, intentionally not done): the structural one-offering-targets-one-threat rework
> and a mid-game difficulty selector (both need playtesting, not headless validation). Balance
> numbers are conservative judgment calls validated by a green test battery, not human playtesting.
>
> **Verification:** self-test **103/0**, integrity sweep **36/0** (every screen + N1-N6 + custom +
> the new l10n keys), death N1-N6 → GameOver, win N3 → WinScreen, win N6 → EndingScreen. Strings
> recompiled; ambience regenerated. An adversarial regression re-check of the full diff found **0
> critical/major** issues and **2 minor self-introduced regressions, both fixed**: the new button
> hover-juice was wiping HUD door/light state colors (moved to `self_modulate`), and the Stats
> nemesis row could show the raw `via` id (now threat-causes only).

---

An audit-driven **polish & hardening** pass: no new threats, screens, items, or mechanics —
only refinement of the existing build. A 9-axis read-only audit produced 37 grounded findings
(0 critical / 9 major / 16 minor / 12 polish); **36 code fixes were applied** across 19 files,
plus SFX regeneration and 4 new self-test checks.

**Verification:** headless self-test **100 passed / 0 failed** (was 96/0 — +4 save checks);
win flow → `EndingScreen`, death flow → `GameOver`; no import errors, no parse warnings, no
script errors. Godot 4.7, `res://tools/SelfTest.tscn`.

---

## 1. Balance & difficulty tuning
| Change | File | Was → Now | Why |
|---|---|---|---|
| Night-6 cliff | `game_state.gd` | `quy_nhap_trang 6→5`, `ma_troi 6→5`, `oan_hon 8→6` | N6 broke the +1/night cadence and introduced Oan hồn — a brand-new mechanic — at the campaign's highest *start* level (8). Softened to keep N6 the peak (still the only 6-threat night) without a first-encounter wall. |
| Offering relief | `co_hon.gd` `oan_hon.gd` `ma_da.gd` | crowd/agro `45→30`, flood `32→22` | One free tray reset **all three** meter threats at once, so spending offerings on cooldown held the night passive with no skill. Now a tray *thins* a meter rather than clearing it; incense stays the weaker, more frequent tool. |
| Custom-night double-scaling | `game_state.gd` | skip `_difficulty_level_scale` when `is_custom` | Custom levels are already absolute 0–20; the NIGHTMARE ×1.6 was applied on top, clamping authored levels ≥13 all to ~20 (dead top-third of the slider). Story-night scaling unchanged. |
| Loss consolation | `night_controller.gd` | `_last_hour * 2 → * 3` | A player *stuck* on a hard night earned almost nothing per attempt and couldn't afford the upgrade that would unblock them. The `night_best_coins` anti-farm cap still prevents repeat-night milking. |

**Confirmed sound, no change:** the FNAF 0–20 roll, the `_run_earned`/`night_best_coins`
anti-farm economy, and the idle-power floor (≤21% drain over the longest night → no night is
unwinnable by power alone).

## 2. Game feel & juice consistency
- **Pause now ducks the audio bed** (`night_controller.request_pause`). Previously every
  sustained loop (heartbeat, drone, breathing, shutter-strain, water, static) kept playing at
  full volume behind the pause menu. Now the SFX bus drops to −60 dB on open and is restored
  *exactly* via `Audio.apply_volumes()` on resume (also clears any in-flight duck). Reversible;
  no `stop_all_loops`.
- **Monitor lower now fades** (~0.10 s) to match the raise, instead of a one-frame hard cut.
- **SFX loop gain trims** so the cricket ambience survives a loom: `drone_tension −16→−19`,
  `breathing −15→−18`, `shutter_strain −16→−19` dB. Heartbeat/water left as intentional
  foreground.
- **Audited safe, left intact:** all 8 loops + music are correctly stopped on death (`_caught`),
  win (`_win`), and every scene change (`Router.change_scene` → `stop_all_loops` + `apply_volumes`),
  so no loop can orphan into a menu/win/game-over.

## 3. Transitions & state desync
- **Door tween lifecycle** (`guard_room.set_door`): a per-side tween is now stored and killed
  before a new one starts, so a rapid reverse no longer leaves two tweens fighting `position:y`
  (stutter/snap fixed).
- **Fade overlay blocks input during transitions** (`scene_router`): the fade `ColorRect` flips
  to `MOUSE_FILTER_STOP` while a scene change is in flight and back to `IGNORE` at rest, so menu
  screens can't take a stray second click under the fade.

## 4. Bug hunt & edge cases
- **`_win()` await guard**: added `if not is_inside_tree(): return` after its 0.6 s timer, mirroring
  the sibling `_caught()` path (prevents a future null-deref if the scene frees mid-await).
- **`vendor._attack()` made idempotent**: now early-returns unless `HOSTILE` and parks her state
  before emitting, so a counterfeit-vendor grab can't structurally re-emit every frame.
- **Documented protected invariants** (do not remove in future cleanups): the `_ending`
  early-returns, the `_power_out`/`_powered` re-entrancy guard, and the parent-before-child
  process order — these already make pause-during-jumpscare, quit-mid-effect, monitor-open-win,
  and power/door races safe.

## 5. Save robustness — `save_manager.gd`
- **`.bak` recovery is now persisted.** Previously a recovery left the good data only in memory +
  `.bak`; the next routine save rotated the still-corrupt `progress.cfg` over the only backup. Now
  a recovered load immediately rewrites a healthy `progress.cfg`.
- **`mark_night_cleared` counts a win once** — replaying an already-cleared night no longer
  inflates `stats.nights_won` (guarded by `nights_cleared.has(n)`).
- **Forward-version guard** in `_migrate`: a save from a newer build is no longer silently
  downgraded (warns and returns).
- **4 new self-test checks** lock these in (sandboxing the real save to `*.selftest` and restoring
  it). *Note: the self-test prints one engine `ConfigFile parse error` and one `version 100 > 1`
  warning — these are intentional artifacts of the corruption/forward-version tests, each followed
  by its PASS.*

## 6. Accessibility & settings integrity
- **Scare-OFF now suppresses every visual scare.** The pre-scare `add_shake(0.16)` and the
  scares-off branch's red `_flash` + `add_shake(0.4)` were firing even with scares disabled; both
  are now gated by `Settings.allow_jumpscares()`. OFF = no shake, no flash (a quiet audio sting
  still confirms the death).
- **REDUCED tier is now genuinely gentler than FULL** (it only lowered scream volume before):
  skips the screen-position jitter, uses the soft strobe variant, and halves the jumpscare shake.
- Keybind cheat-sheet ↔ `project.godot` input map verified consistent.

## 7. Localization — see [`docs/L10N_REVIEW.md`](docs/L10N_REVIEW.md)
Audit found the layer **mechanically airtight**: 345 keys, 0 missing, 0 untranslated, 0 encoding
faults, exactly one (by-design) hardcoded bilingual literal in the language picker. **No
`strings.csv` edits were made** — a CSV-only change would desync the compiled `.translation`
binaries without a Godot re-import. The deliverable is a native-speaker review checklist for the
culturally-sensitive prose (tapes, phone, endings, ritual/taboo lines).

## 8. Code health
- Extracted `ThreatBase._ai_at(night_progress)` and replaced the effective-AI-level line that was
  copy-pasted across the base + 5 threats (single source of truth; bit-identical).
- Removed dead `ThreatBase.name_key` (field + director assignment, no readers).
- Silenced `INTEGER_DIVISION` warnings in the clock math (`night_controller`, `hud`).
- Silenced an `UNUSED_PARAMETER` warning (`co_hon.on_via_state` → `_state`).
- Named the nearest-threat sentinel (`99999 → _NO_THREAT_DIST`), relocated `set_fog_level` out of
  the var block (`camera_system`), and annotated the reserved-but-unused `MODEL_STALKER`.

## 9. Presentation
- **HUD help panel pushed down** so it no longer overlaps the conditional meter stack
  (coins/offerings/crowd/water/grievance) mid-night.
- **Shop panel centered** (was 50 px off to the right).
- **`static_loop` hiss aligned** between live monitor and tape archive (−26 → −22 dB).
- **`fluorescent_hum` removed from the LOOPING set** (it was configured to loop but never played).
- **Jumpscare WAV regenerated at peak 0.9** (was 0.99) so it stops slamming the master limiter on
  every death. `tools/gen_sfx.py` is deterministic (seed) — only `jumpscare.wav` changed.

---

## 10. Second-pass re-check (regressions found & fixed)
A focused adversarial re-audit of the polish diff (plus a deep integrity sweep — every
screen scene + N1–N6 + a custom night, run headless) caught **three regressions the polish
pass had itself introduced**; all three are now fixed and covered by new tests:
- **Counterfeit vendor stuck in `LEAVING`** — the idempotent `_attack()` now parks her in
  `LEAVING` *before* emitting the grab, but `repel_to_idle()` only reset from `HOSTILE`/`SHOP`,
  so a warded vendor save left her inert (no shop) for the rest of the night. Fixed by adding
  `LEAVING` to `repel_to_idle`'s guard. (`vendor.gd`)
- **Monitor look-lock** — the new lower-fade hid the panel via a deferred tween callback;
  a close-then-open within 0.10 s let the stale callback blank a reopened monitor, locking
  controls on a black screen. Fixed by storing/killing the monitor tween and re-checking
  `monitor_open` in the callback. (`night_controller.gd`)
- **Save recovery vs. forward-version guard** — recovering from a *newer* `.bak` then
  re-persisting would downgrade it, defeating the forward guard. Fixed by gating the
  recovery re-save on `ver <= SAVE_VERSION`. (`save_manager.gd`)

The critical-path sweep (death/win routing, power-out, kill path, director tick,
end-of-night transition) found **no critical or major latent bug**, and re-verified the N6
retune stays winnable but non-trivial. Self-test grew **100 → 103** (vendor `LEAVING` path +
monitor toggle race); integrity sweep **36/36**; both flow tests still green. New deep-check
harness: `tools/IntegrityCheck.tscn` (spec in [`docs/INTEGRITY_CHECK.md`](docs/INTEGRITY_CHECK.md)).

## Remaining risks / not done (honest)
- **Balance numbers are judgment calls**, validated by the audit's math + a green self-test, **not
  by extended human playtesting.** All values are one-line and easy to revert/retune — start with
  the §1 table.
- **Native-speaker proof still pending** — `docs/L10N_REVIEW.md` lists the exact rows. Mechanical
  correctness is confirmed; *register/lore* is not.
- **Real art / audio / Vietnamese VO** remain placeholder (out of scope here — see MASTER_PLAN §4b).
- **Pause-duck, scare tiers, monitor fade, door tween, HUD overlap** are visual/audio behaviors
  that headless tests can't observe — they were verified by code review and need a quick manual
  pass on a real run before release (see the §2/§3/§6 items).
- **Self-test leak counts at exit** (ObjectDB/resources) are pre-existing harness teardown noise —
  the test intentionally doesn't free the Night scene before `quit()`. Not a game-runtime issue.

## Deferred (flagged, intentionally not built — would add behavior/scope)
- One-time N2 onboarding hint for the ma-da water lure (reuse `MADA_LURE`).
- Optional N1 activeness bump (`ong_ke 2→3`) — needs design sign-off.
- Wiring or deleting the 33 orphaned `strings.csv` keys (decide per-key).
