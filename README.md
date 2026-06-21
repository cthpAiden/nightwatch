# Bảo Vệ Đêm (Night Guard)

A **2.5D Vietnamese FNAF-style comedy-horror** night-guard game, built in **Godot 4.7**.
You are the new night security guard at an old Vietnamese school, **Trường THCS Minh
Phúc**. Survive each shift from **12:00 AM to 6:00 AM** while folklore creatures
close in from the dark. Watch the cameras, work the doors and lights, place
offerings for the wandering souls, and — above all — **don't answer the water.**

> Tone: comedy-horror. The scares are real; the joke is always on the nervous guard,
> never on the beliefs. The folklore is used **authentically and respectfully**
> (see `docs/DESIGN.md` §1 for the binding cultural rules this project follows).

---

## ▶ How to play / develop

1. Open **Godot 4.7** → Import → select `F:\Nightwatch\project.godot`.
2. Press **F5** (Play). The main menu (Bảo Vệ Đêm) appears.
3. _New Game_ → intro → Night 1.

It also runs from the command line:

```
"C:\Users\DELL\Desktop\Godot_v4.7-stable_win64.exe" --path .
```

### Controls

| Action                   | Key / Mouse                                                    |
| ------------------------ | -------------------------------------------------------------- |
| Look around the office   | Move mouse to screen edges, or **←/→** (and **↓** to recenter) |
| Raise/lower cameras      | **C** or **Tab**, or the **CAM** button                        |
| Left door / Left light   | **A** / **S** (or HUD buttons)                                 |
| Right door / Right light | **L** / **K** (or HUD buttons)                                 |
| Place an offering        | **F** (or **Đặt mâm cúng**)                                    |
| Pause                    | **Esc**                                                        |

### The two meters

- **Điện (Power)** — drains faster with doors closed, lights on, and cameras up.
  Hits 0 → blackout: doors open, you're exposed.
- **Vía (Spirit)** — your nerve/soul. Drains when threats loom or you break taboos;
  recovers when calm, with incense/offerings, and toward dawn. Hits 0 → you're taken.

### The threats (each plays differently)

| Threat             | How it works                                                           | Counter                                                          |
| ------------------ | ---------------------------------------------------------------------- | ---------------------------------------------------------------- |
| **Ông kẹ**         | Rushes the left door                                                   | Close left door, or behave (lights off + sit still)              |
| **Ma da**          | A false "help me" from the water — **don't answer**; flood rises       | Shut the drain, ignore the cry, incense                          |
| **Cô hồn**         | A hungry crowd swells all night                                        | Keep the offering tray stocked (you feed them, never fight them) |
| **Quỷ nhập tràng** | The cat **Mun** creeps toward a draped corpse                          | Close the right door / barrier to divert the cat                 |
| **Ma trơi**        | Blue field-flames — panic makes them chase                             | Move slowly; don't "run" (don't whip the camera around)          |
| **Oan hồn**        | A wronged schoolgirl; watching **or** ignoring too long angers her     | Brief glances; pacify with incense                               |
| **Bà hàng rong**   | The vendor shop — but an **impostor** may copy her (warped street-cry) | Don't buy from the fake; close the left door if it turns hostile |

---

## 🎨 Swapping in your own art & audio

Everything ships with **procedural placeholder art (SVG) and synthesized audio (WAV)**
so the game is fully playable now. To replace an asset, just drop a file with the
**same name** over the placeholder — no code changes needed.

- **Art:** `assets/art/` (`room/`, `cameras/`, `threats/`, `ui/`, `intro/`, `shop/`).
  SVGs import as textures; you can also drop in `.png`/`.webp` (update the path or
  keep the name). Edit the SVGs directly in Inkscape/Illustrator.
- **Audio:** `assets/audio/` (`sfx/`, `music/`, `jumpscare/`). Replace any `.wav`
  with a real recording (same filename). Regenerate the placeholders any time with
  `python tools/gen_sfx.py`.
- **Suggested sources:** SFX → Freesound.org; ambient music → Suno; Vietnamese
  voice lines → ElevenLabs (e.g. "Mua không em?", the bác Tư tapes).
- **Text:** all player-facing strings live in `localization/strings.csv`
  (Vietnamese + English). Never hard-code text; add a key and use it.

---

## 📦 Building a Windows .exe

A Windows export preset is already configured (`export_presets.cfg`).

1. In Godot: **Project → Export**. If prompted, click **Manage Export Templates →
   Download and Install**.
2. Select **Windows Desktop → Export Project** → save as `build/BaoVeDem.exe`.
3. Zip the `build/` folder and upload to itch.io (name-your-own-price).

---

## 🗂 Project structure

```
project.godot            # autoloads, input map, render, localization
assets/                  # art (svg), audio (wav), fonts (Be Vietnam Pro)
localization/strings.csv # bilingual VI/EN text
scripts/core/            # autoloads: Events, Settings, Save, Locale, Audio, Game, Router
scripts/systems/         # night_controller, guard_room (2.5D), camera_system,
                         #   threat_director, vendor, item_system, registries, map_graph
scripts/threats/         # threat_base + 6 folklore threats
scripts/ui/              # hud, shop, cassette, pause, menus, screens
scenes/                  # thin scenes (logic is built in code)
data/, docs/, tools/     # design docs, the SFX generator, the screenshot harness
```

## 📚 Design docs

- `docs/DESIGN.md` — the full, culturally-vetted design spec (threats, vía,
  offerings, items, vendor, night progression, narrative, **binding respect rules**).
- `docs/ARCHITECTURE.md` — how the code is wired (autoloads, contracts, scene tree).
- `MASTER_PLAN.md` — the high-level plan and current build status.

## 🙏 Credits & note

Solo project by **Aiden**, vibe-coded with **Godot 4.7 + Claude Code**.
Folklore researched and used with care; this game celebrates Vietnamese folk belief
and is not meant to mock it. Native-speaker proofreading is recommended before release.
