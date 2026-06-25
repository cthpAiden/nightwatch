# Deep Integrity Check — spec & prompt

This is the self-contained verification spec for confirming the current build of
*Bảo Vệ Đêm* is whole and runnable. It is implemented as a headless harness
(`tools/integrity_check.gd` → `res://tools/IntegrityCheck.tscn`) so it can be re-run
on demand, exactly like the gameplay `selftest`.

> Run: `godot --headless --path . res://tools/IntegrityCheck.tscn`
> (Do **not** set `NW_NIGHT` — the night sweep sets `Game.current_night` itself.)
> The harness snapshots the player's real save and restores it; it never mutates progress.

## The prompt (what this verifies)

> **Deep-check and verify the integrity of the current state of the game without changing
> behavior.** Confirm that every player-reachable scenario and every extra still boots and
> runs:
>
> 1. **Scene boot** — instantiate every screen scene (MainMenu, Intro, NightSelect,
>    SettingsMenu, ShrineScreen, ExtrasScreen, Bestiary, TapeArchive, Stats, CustomNight,
>    Credits, WinScreen, GameOver, EndingScreen) and assert each builds its UI without a
>    script error.
> 2. **Play-through N1→N6** — boot each story night, assert it reaches the running state,
>    is not accidentally ending, and spawns exactly the expected threat roster (N1=1 … N6=6).
> 3. **Custom Night** — author a custom night and assert it boots, runs, and is flagged custom.
> 4. **Both terminal flows** — drive a real death → `GameOver` and a real win on the final
>    night → `EndingScreen` (via the existing FlowTest harness).
> 5. **Registries** — ThreatRegistry (6 threats), ItemRegistry (≥14 items), MapGraph
>    (10 cameras + symmetric mirror), Lore (tape + phone lines for nights 1–6).
> 6. **Assets on disk** — all 10 camera SVGs, the ending/intro/UI art, and the jumpscare WAV.
> 7. **Localization** — a representative sample of keys across every family (menu, HUD,
>    night titles, tapes, phone, endings, bestiary, counters, vendor, lure) resolve to real
>    text, not the bare key.
>
> Plus re-run the gameplay `selftest` (mechanics, save-robustness, economy, endings). Any
> failure is a real regression to fix; a fully green run means the build is shippable-whole.

## Pass criteria
- `IntegrityCheck`: all checks pass, exit 0.
- `SelfTest`: 100 passed / 0 failed.
- `FlowTest` death → `GameOver`, win → `EndingScreen`.
- No `SCRIPT ERROR`, parse warning, or failed-import in stderr (the only expected stderr
  lines are the SelfTest's intentional corrupt-save / forward-version artifacts).
