# MASTER_PLAN.md
## Bảo Vệ Đêm (Night Guard)
### A Vietnamese FNAF-style comedy-horror game — Solo vibe-code build

---

## 1. Concept Summary

You are a night security guard at an old Vietnamese school. Your job is to survive from 10pm to 6am. Four threats roam the school and approach your guard room from different directions. You have a camera system to track them, doors to block them, and a điện (power) bar that drains when you use doors and lights. If power runs out, you have no doors and no light. A mysterious bà bán hàng rong appears at the school gate offering items — helpful or cursed — but if you ignore her too long, she turns hostile.

**Tone:** Vietnamese-flavored comedy-horror. Think banter, familiar cultural details, absurd scares.
**Target audience:** Vietnamese players first, international second.
**Platform:** itch.io (free, name-your-own-price later)
**Engine:** Godot 4.4+

---

## 2. Technical Stack

| Tool | Role | Cost |
|---|---|---|
| Godot 4.4+ | Game engine | Free |
| Claude Code + Pro/Max | Vibe coding via MCP | Already have |
| godot-mcp (Coding-Solo) | Claude Code ↔ Godot bridge | Free (npm) |
| Freesound.org | SFX library | Free |
| Suno | Ambient music generation | Free tier |
| ElevenLabs | Optional Vietnamese voice lines | Free tier |
| itch.io | Distribution | Free |

---

## 3. MCP Setup (Windows + Claude Code)

**Prerequisites:**
- Node.js installed (check with `node -v` in terminal; install from nodejs.org if missing)
- Godot 4.4+ installed
- Claude Code already set up

**Step 1: Create `.mcp.json` in your project root folder**

This is the most reliable method on Windows. Create a file called `.mcp.json` directly in your Godot project folder (same level as `project.godot`).

```json
{
  "mcpServers": {
    "godot": {
      "command": "cmd",
      "args": ["/c", "npx", "@coding-solo/godot-mcp"],
      "env": {
        "DEBUG": "true",
        "GODOT_PATH": "C:\\path\\to\\Godot_v4.4.exe"
      }
    }
  }
}
```

> Replace `C:\\path\\to\\Godot_v4.4.exe` with the actual path to your Godot executable.
> Note the double backslashes `\\` — that's required in JSON on Windows.

**Step 2: Restart Claude Code from inside your project folder**

Open your terminal, `cd` into your project folder, then run `claude`. Claude Code should detect `.mcp.json` and ask you to enable the godot MCP server.

**Step 3: Test the connection**

With Godot editor open, type this in Claude Code:
```
List all nodes in the current scene
```
If you get a scene tree back, you're connected. If it hangs, the most common fix is double-checking your GODOT_PATH value has no typos and uses `\\`.

**Windows-specific gotcha:** The `cmd /c` wrapper in the config is required. Without it, `npx` commands silently fail on Windows.

---

## 4. Godot Scene Structure

```
res://
├── project.godot
├── .mcp.json
├── scenes/
│   ├── Main.tscn              # Root scene, game manager
│   ├── GuardRoom.tscn         # Player's base (no camera)
│   ├── CameraSystem.tscn      # The 5 camera feeds
│   ├── UI.tscn                # HUD: power bar, clock, camera button
│   ├── BaHangRong.tscn        # The bà bán hàng rong + shop UI
│   ├── Intro.tscn             # Intro cutscene (text + static image)
│   ├── GameOver.tscn          # Lose screen (jumpscare + text)
│   └── WinScreen.tscn         # Survive-til-6am screen
├── scripts/
│   ├── GameManager.gd         # Master state, night timer, power
│   ├── CameraSystem.gd        # Camera switching logic
│   ├── DoorManager.gd         # Left/right door open/close + power drain
│   ├── ThreatBase.gd          # Base class all ghosts inherit from
│   ├── MaDa.gd                # Ma da behavior
│   ├── CoHon.gd               # Cô hồn behavior
│   ├── OngKe.gd               # Ông kẹ behavior
│   ├── BaHangRong.gd          # Bà bán hàng rong dual-state logic
│   ├── ItemSystem.gd          # Item effects
│   └── IntroScene.gd          # Cutscene text sequencer
├── art/
│   ├── backgrounds/           # Static camera images (5 rooms)
│   ├── characters/            # Threat sprites (simple flat art)
│   ├── ui/                    # HUD elements
│   └── intro/                 # Intro screen image
└── audio/
    ├── music/                 # Ambient loop (from Suno)
    ├── sfx/                   # Door creak, static, footsteps (from Freesound)
    └── jumpscare/             # Jumpscare sound (one sharp loud SFX)
```

---

## 5. Camera Layout

```
        [SCHOOL GATE — CAM 1]
        bà bán hàng rong spawns here
        ông kẹ spawns here
              |
    +---------+---------+
    |                   |
[LEFT CORRIDOR — CAM 2]  [RIGHT CORRIDOR — CAM 3]
  ông kẹ path             ma da path
    |                         |
[DARK CLASSROOM — CAM 5]  [BATHROOM — CAM 4]
  cô hồn wanders here       ma da spawns here
    |                   |
    +--------+----------+
             |
        [GUARD ROOM]
        Left door    Right door
        (blocks CAM 2 path)  (blocks CAM 3 path)
```

**5 camera feeds.** Player flips between them on the UI. When a threat reaches the doorway, closing the corresponding door blocks it and drains power. If you don't close the door in time, it reaches your room = game over.

---

## 6. Threat Behavior Design

### Cô hồn (build first — simplest)
- Spawns randomly at CAM 5 (classroom)
- Every 10-15 seconds, randomly moves to an adjacent camera
- Never targets the player directly, just drifts
- If she ends up at CAM 2 or CAM 3 (your doorway cameras), she can then enter
- **Counter:** close the door on whatever side she drifts to

### Ma da (second)
- Spawns at CAM 4 (bathroom)
- Moves in a fixed path: CAM 4 → CAM 3 → guard room right door
- Moves one camera step every 12 seconds (gets faster as night progresses)
- **Counter:** close right door when she reaches CAM 3

### Ông kẹ (third)
- Spawns at CAM 1 (school gate)
- Moves in a fixed path: CAM 1 → CAM 2 → guard room left door
- Move speed same as ma da but offset so they don't always arrive together
- **Counter:** close left door when he reaches CAM 2

### Bà bán hàng rong (fourth — dual state)
See section 7 below.

---

## 7. Bà Bán Hàng Rong — Dual State System

```
STATE: IDLE (not present)
    ↓  [random timer, every 2-3 minutes]
STATE: SHOP — appears on CAM 1
    ↓  [30 second countdown starts]
    ├── Player calls her in → SHOP SCREEN (pick 1 item) → returns to IDLE
    └── Timer runs out → STATE: HOSTILE
STATE: HOSTILE — moves like a threat (CAM 1 → CAM 2 → left door)
    └── Player closes left door → she leaves → IDLE
```

**GDScript logic (simple version for Claude Code):**
- She's a Node with an enum: `State.IDLE, State.SHOP, State.HOSTILE`
- A `Timer` node triggers the transition from IDLE to SHOP
- Another `Timer` counts down 30 seconds in SHOP state
- If the player calls her: open shop UI, apply item, set state to IDLE
- If timer expires: set state to HOSTILE, start movement toward left door
- Hostile movement reuses the same movement code as ông kẹ (one camera step at a time)

**This is not complex code.** It's one script with state switching. Claude Code can write the entire thing in one prompt.

---

## 8. Item System

She offers 3 items on a shop screen. Player picks one. Items are selected from a small pool with unknown effects until used.

| Item | Display Name | Effect | Type |
|---|---|---|---|
| Cây nhang | Incense stick | Slows next ghost movement by 50% for 60s | Helpful |
| Gương thần | Magic mirror | Shows all ghost positions on cameras for 30s | Helpful |
| Nước thánh | Holy water | Resets one threat back to spawn point | Helpful |
| Bánh lạ | Strange pastry | Doubles ghost movement speed for 60s | Cursed |
| Bùa | Amulet | Drains your power by 20% instantly | Cursed |
| Nước mắm | Fish sauce | Bà herself comes back again after 60s | Cursed |

**Design note:** Don't display whether items are helpful or cursed. Player learns through dying. That's the replay hook.

---

## 9. Story & Narrative (Light Version)

### Intro Cutscene (Intro.tscn)
Static dark image of the school at night. Text fades in one line at a time:

```
"Trường THCS Minh Phúc. 9:45 tối."
"Công việc đơn giản: Bảo vệ qua đêm."
"Không ai nói gì về... những thứ kia."
[Press any key to start]
```

Plays an ambient night sound loop. Fades to black, loads Main scene.

### Win Ending Screen (WinScreen.tscn)
When clock hits 6:00 AM: fade to warm orange light, rooster crow SFX, text:

```
"6:00 sáng."
"Anh sống sót."
"Cảm ơn anh đã bảo vệ trường."
"— Ban giám hiệu"
[small text below: "...Anh có muốn thử lại không?"]
[Play Again] [Quit]
```

### Game Over Screen (GameOver.tscn)
Jumpscare image fills screen, loud SFX, then fades to black, simple text:

```
"Đêm nay không qua được."
[Try Again] [Quit]
```

---

## 10. Art Plan

**Philosophy:** Deliberately simple/crude art is fine and fits the meme-horror aesthetic. Do not spend more than 3 days on art total.

**Camera backgrounds (5 images):**
- Simple flat 2D illustrations: dark rooms, minimal detail, strong silhouettes
- Draw in Godot directly using Polygon2D nodes, or use any simple drawing tool
- Color palette: dark blues/greens for night, one accent color per room

**Threat sprites:**
- Each threat = 2-3 frames max (idle + "getting closer" version)
- Crude is fine. A blob with eyes works if the audio and timing are right.
- Option: generate with Stable Diffusion + clean up in Paint.NET (free)

**Bà bán hàng rong:**
- She should look warm and friendly on the camera feed — that's the horror of her
- Shop screen can be a simple UI panel, no elaborate art needed

**Intro image:**
- Single dark school building silhouette against a moon
- AI-generate this with any image AI, it just needs to be atmospheric

---

## 11. Audio Plan

**All SFX from Freesound.org (free, Creative Commons):**
- Search terms: `door creak`, `static tv`, `footsteps wood`, `breathing`, `distant bell`, `rooster crow`, `horror sting`
- One jumpscare SFX: search `horror jumpscare sting` — pick the sharpest one

**Ambient music from Suno (free tier):**
- Prompt to use: *"lo-fi horror ambient loop, Vietnamese night atmosphere, distant motorbikes, crickets, subtle dread, no lyrics, seamless loop"*
- Download as mp3, drop into `audio/music/`

**Optional Vietnamese voice lines from ElevenLabs (free tier):**
- Bà bán hàng rong saying "Mua không em?" when she appears on camera
- One ghost whisper on game over

---

## 12. Day-by-Day Build Plan

### WEEK 1 — Foundation

**Day 1-2: Learn Godot (no Claude Code yet)**
- Download and install Godot 4.4
- Watch one beginner video (search "Godot 4 beginner 2D in 30 minutes")
- Open Godot, create a blank 2D project, add a few nodes, move them around
- Goal: understand what Node2D, Sprite2D, Label, Timer, and Signal mean
- Do NOT write any game code yet

**Day 3: MCP Setup**
- Install Node.js if not already installed
- Create your project folder and `project.godot`
- Create `.mcp.json` using the config in Section 3
- Open Claude Code in the project folder, confirm MCP connection works
- Test with: `List all nodes in the current scene`

**Day 4-5: Core UI + Guard Room**
Claude Code prompt:
```
Create a main game scene in Godot 4 with:
- A black background representing the guard room
- A HUD showing: a power bar (starts at 100, drains slowly over time),
  a clock label showing time from 22:00 to 06:00,
  and a "CAM" button in the bottom right
- The clock should count up in game time (1 real second = 1 game minute)
- When power hits 0, print "POWER OUT" to the console
- Use GDScript
```

**Day 6-7: Camera System**
Claude Code prompt:
```
Add a camera switching system to the game. When the player clicks the CAM button,
show a camera view overlay with 5 camera feeds labeled:
CAM1 (School Gate), CAM2 (Left Corridor), CAM3 (Right Corridor),
CAM4 (Bathroom), CAM5 (Classroom).
Each feed is a colored rectangle for now (placeholder art).
Player can click any feed to "view" it. Clicking CAM button again closes the overlay.
While the camera overlay is open, power drains slightly faster.
```

### WEEK 2 — Content

**Day 8: First threat (Cô hồn)**
Claude Code prompt:
```
Add the first threat called CôHồn. She starts at CAM5.
Every 12 seconds, she randomly moves to an adjacent camera.
Adjacent connections: CAM5 can go to CAM2. CAM2 can go to left door or CAM5.
If she reaches left door, trigger game over after 5 seconds unless the left door is closed.
Show her position as a white circle sprite on the relevant camera feed.
Add left and right door buttons to the guard room UI that close/open doors.
Closing a door drains power by 5 per second while it stays closed.
```

**Day 9: Ma da + Ông kẹ**
Claude Code prompt:
```
Add two more threats:
MaDa: spawns at CAM4, moves CAM4 → CAM3 → right door. Moves every 15 seconds.
OngKe: spawns at CAM1, moves CAM1 → CAM2 → left door. Moves every 18 seconds.
Both follow fixed paths. Both trigger game over if they reach a door that's open.
Both should move faster as the night progresses (increase speed every 2 game hours).
```

**Day 10: Bà bán hàng rong**
Claude Code prompt:
```
Add BàHàngRong character with dual state logic:
- Every 2-3 minutes, she appears on CAM1 (SHOP state)
- A 30-second countdown shows in the HUD when she appears
- A "Mời vào" button appears on the guard room UI
- If player clicks the button: show a shop screen with 3 random items from this list:
  [Cây nhang, Gương thần, Nước thánh, Bánh lạ, Bùa, Nước mắm]
  Player clicks one item to take it. Apply the item effect. She disappears.
- If countdown reaches 0 without player clicking: she enters HOSTILE state
- In HOSTILE state, she moves CAM1 → CAM2 → left door (same as OngKe path)
- If player closes left door while she's hostile, she leaves and returns to IDLE
Implement item effects as described: [paste item table from Section 8]
```

**Day 11: Item effects + jumpscare**
Claude Code prompt:
```
Implement the item effects from the ItemSystem:
- Cây nhang: set a variable ghost_speed_multiplier to 0.5 for 60 seconds
- Gương thần: show all ghost positions labeled on camera feeds for 30 seconds
- Nước thánh: reset the threat that is currently closest to the guard room back to spawn
- Bánh lạ: set ghost_speed_multiplier to 2.0 for 60 seconds
- Bùa: subtract 20 from current power immediately
- Nước mắm: force BàHàngRong back to SHOP state after 60 seconds

Also add a jumpscare:
- When any threat reaches the guard room (door open), play a jumpscare:
  Show a full-screen image (placeholder black square for now) for 0.5 seconds
  Play a loud SFX (placeholder)
  Then load GameOver scene
```

**Day 12: Intro + Win + Game Over screens**
Claude Code prompt:
```
Create three scenes:
1. Intro.tscn: Black background, text fades in line by line with 1.5 second gaps:
   Line 1: "Trường THCS Minh Phúc. 9:45 tối."
   Line 2: "Công việc đơn giản: Bảo vệ qua đêm."
   Line 3: "Không ai nói gì về... những thứ kia."
   Line 4: "Nhấn phím bất kỳ để bắt đầu."
   After player presses any key, load Main scene.

2. WinScreen.tscn: Orange background, text:
   "6:00 sáng. Anh sống sót."
   Two buttons: [Chơi lại] and [Thoát]

3. GameOver.tscn: Black background, large red text: "Đêm nay không qua được."
   Two buttons: [Thử lại] and [Thoát]

Connect: when clock reaches 06:00, load WinScreen.
```

**Day 13: Art + Audio pass**
- Replace placeholder rectangles with actual art for camera backgrounds
- Add ambient audio loop (Suno mp3) to Main scene AudioStreamPlayer
- Add SFX: door creak when opening/closing, static when switching cameras
- Add jumpscare image and jumpscare SFX to GameOver trigger
- Optional: ElevenLabs voice line for bà bán hàng rong

**Day 14: Polish + Ship**
- Play through the full game at least 5 times yourself
- Fix any bugs Claude Code missed
- Export the game: Godot → Project → Export → Windows Desktop
- Create an itch.io account if you don't have one
- Upload the `.exe` + `.pck` as a zip
- Write a short Vietnamese description + English description
- Set price to "Name your own price" (free with optional payment)
- Post on Twitter/X, TikTok, and share in Vietnamese game communities

---

## 13. Claude Code Prompting Tips for This Project

**Always start a session with:**
```
Read the current scene tree and all scripts in the /scripts folder,
then tell me what's there before making any changes.
```

**When something breaks:**
```
The game is crashing with this error: [paste error]
Read the relevant script first, then fix it.
Do not rewrite the whole file, only change what's broken.
```

**When adding a new feature:**
```
Before writing any code, tell me your plan in plain English.
I'll approve it, then you write the code.
```

**When art placeholders need replacing:**
```
Replace the placeholder [ColorRect] on [scene name] with a
TextureRect that loads from res://art/[folder]/[filename].png
```

**Godot MCP auto-reload gotcha (Windows):**
If Claude Code edits a script and Godot freezes or shows stale results:
Go to Godot → Editor Settings → Text Editor → Files → disable "Auto Reload Scripts"
during coding sessions. Re-enable when you want to test manually.

---

## 14. Scope Lock — DO NOT ADD THESE

These will kill your 2-week timeline. Write them down and forget them until v2:

- 3D graphics or any 3D mode
- Multiple floors or rooms beyond the 5 cameras
- Multiple playable characters
- Online leaderboard
- Mobile support
- Save/load system
- More than 4 threats in v1
- Dialogue trees or branching story
- More than one night in v1
- Background lore documents or collectibles
- Any feature that takes more than one day to describe

**The rule:** if you can't explain the feature in two sentences, it's not v1.

---

## 15. Ship Checklist

- [ ] Game runs from start to win screen without crashing
- [ ] Game runs from start to game over without crashing
- [ ] Power system drains correctly and game reacts to power=0
- [ ] All 4 threats move and can trigger game over
- [ ] Bà bán hàng rong appears, offers shop, and turns hostile correctly
- [ ] At least 3 items have working effects
- [ ] Intro cutscene plays before the game
- [ ] Win and game over screens both have working buttons
- [ ] Jumpscare triggers correctly
- [ ] Ambient audio loops without cutting out
- [ ] At least one SFX plays (door, static, or jumpscare)
- [ ] Game exports to a working .exe on Windows
- [ ] itch.io page is live with a description in Vietnamese and English

---

*Working title: Bảo Vệ Đêm | Rename whenever you want*
*Built with Godot 4.4 + Claude Code | Solo dev | vibe-coded*
