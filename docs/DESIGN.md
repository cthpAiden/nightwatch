# DESIGN.md — Bảo Vệ Đêm (Night Guard)

> Source-of-truth design spec, folded into MASTER_PLAN.md. A 2.5D FNAF-style
> Vietnamese comedy-horror night-guard game. Built on the verified folklore
> research dossiers (fact + sensitivity passes, all "solid"). This document
> supersedes the older 4-threat door-survival sketch in MASTER_PLAN §6–§8.
>
> Engine: Godot 4.4+. Data-driven: threats = `data/threats/*.tres` (ThreatDef),
> items = `data/items/*.tres` (ItemDef), nights = `data/nights/*.tres`
> (NightConfig). All player-facing strings live in `localization/strings.csv`.

---

## 0. Reading order for implementers

1. §1 Authenticity statement — these are **binding constraints**, not flavor.
2. §2 Threat roster — each maps to one ThreatDef + one threat scene/script.
3. §3 Vía, §4 Offerings, §5 Items, §6 Vendor — the four core systems.
4. §7 Night progression — drives the `data/nights/` table.
5. §8 Narrative, §9 Audio/Art, §10 String list.

---

## 1. Authenticity & Respect Statement (BINDING)

Bảo Vệ Đêm treats Vietnamese folk belief as living culture, not horror set
dressing. The emotional core is **compassion under pressure**: most of the
dead are pitiable — drowned children, forgotten souls, wronged women, the
unburied — not monsters to be slaughtered. The dread comes from the night, the
clock, and the unknown; the resolution, wherever possible, is **mercy** (feed,
calm, help them move on / *siêu thoát*). The **joke is always on the living
night guard** — his nerves, his bumbling, his over-literal handling of rituals,
his bargaining with the dead — **never** on the beliefs, the rites, the
ancestors, or the faithful.

### Hard rules (do not violate in code, art, audio, or text)

1. **Sacred is never a trap.** Incense (nhang/hương), the offering tray, salt-rice
   (muối gạo), a genuine amulet (bùa), and the ancestor altar (bàn thờ) are
   **always reliably helpful** when used correctly. They are **never** placed in
   the "might be cursed" item pool. Curse risk lives only on profane/suspect items
   or on **counterfeit** goods from a fake vendor.
2. **The altar is inviolable.** The bàn thờ is sanctuary: it can be tended, lit,
   and bowed to, but is **never** desecrated, knocked over, possessed, or used as a
   jump-scare surface. Spirits never emanate *from* the ancestor altar.
3. **Tier the dead.** Ordinary wandering souls (cô hồn / người âm) resolve through
   **appeasement**, not a kill-screen. Neglect raises *unrest* and escalates other
   threats — the souls themselves do not "murder" you. Lethal jump-scares are
   reserved for genuinely malevolent/cursed agents.
4. **Comedy targets the guard.** Never mock ancestor worship, Buddhism, funerals,
   incense, offerings, or grief. The only mockable human is a **charlatan**
   (pháp sư rởm / counterfeit vendor).
5. **Wu Lan is walled off.** Theme the scare-night as **Tháng Cô Hồn** (7th lunar
   month / hungry-ghost season), **never** as *Lễ Vu Lan*. No monks, sutras, or the
   rose-pinning rite appear as horror material. If Vu Lan is referenced at all, it
   is the warm, daytime, reverent counterweight, clearly separated.
6. **Label borrowed/shared lore honestly** in the in-game bestiary (Hồ Sơ Ma):
   - *Ma lai* = pan–Southeast-Asian (Khmer Áp, Thai Krasue, Malay Penanggalan,
     Lao Kasu, Filipino Manananggal); in Vietnam, Trường Sơn–Tây Nguyên
     **ethnic-minority** lore. **Frame it as an in-world legend, never tie it to a
     named real ethnic group, never depict the boiling-oil "tests"** (real
     persecution history). Consider it cut-able from v1.
   - *Ma xó* = Mường / Tây Bắc **highland** tradition, not pan-Kinh.
   - *Quỷ nhập tràng* = Vietnamese (cat-over-corpse), NOT the Chinese jiangshi;
     note the parallel, don't import hopping-vampire iconography.
   - *Tết Trung Thu / mooncakes*, *ngạ quỷ*, *ma trơi*, *gương bát quái*,
     *the hồn-phách / vía system* = shared Sino/Buddhist/worldwide layers —
     disclaim, don't claim as uniquely Vietnamese.
   - *Con ma vú dài* = a **1960s–70s Saigon urban legend** (Chí Hòa), not ancient
     folklore; treat the wronged woman with pity, never sexualize.
7. **Bestiary honesty tags.** Every Hồ Sơ Ma entry carries a status tag:
   *documented folklore* / *urban legend* / *ethnic-minority tradition* /
   *folk-thin (creator's license)* / *shared regional*. This is a selling point.
8. **No real people / no instructions.** No reference to the real Thiên Linh Cái
   murder case, no named real schools, no ritual "recipes." Fictionalize fully.
9. **Diacritics everywhere** player-facing (Bảo Vệ Đêm, cô hồn, ma da, vía,
   quỷ nhập tràng, cúng cô hồn…). ASCII only in code identifiers/filenames
   (`MaDa.gd`, `co_hon.tres`). Native-speaker proof pass before ship.
10. **Accessibility:** `SET_SCARE_OFF` must genuinely disable jump-scare
    images/stings (swap for a soft fade + audio cue).

---

## 2. THREAT ROSTER (7 threats, distinct mechanics)

The 2.5D rig: a pan-around 3D **guard office** (mouse-drag to look L/R/up at the
roof vent, down at the floor drain) + a 2D **camera monitor** (six feeds, see
strings `CAM1..CAM6`). Each threat below is a `ThreatDef` resource plus a scene.
AI difficulty is the FNAF-style **0–20 level** from `NightConfig.threat_levels`,
which scales each threat's own *cadence/aggression knob* — NOT a shared
"move every N seconds" timer. **The whole point is mechanical variety.**

Map of mechanic archetypes (deliberately one each):
`door-rusher · water-lure look-away · roof audio-tracker · camera-disabler ·
appeasement-economy swarm · cat-prevention trigger · dawn-deadline aerial`.

---

### 2.1 Ma da — *Water Ghost* (water-lure / "don't answer" look-away)
- **Lore (1 line):** A drowned soul bound to the school's flooded courtyard pond,
  it must lure a living replacement (*tìm người thế thân*) before it can move on.
- **Spawn / path:** CAM4 (Nhà Vệ Sinh) and CAM6 (Sân Sau pond/cistern). It does
  **not** walk corridors; it manifests **only through water sources** — a running
  tap, a puddle, the cooler, the floor drain you can look down at in the office.
- **DISTINCT mechanic — the false cry:** At intervals it plays a pitiful
  "help me" audio from **one** water node. The office intercom may light up with a
  voice "from the water." **If the player answers the intercom / investigates the
  wrong water source, ma da advances a stage.** The counter is *inaction done
  right*: keep drains shut, taps off, and **do not answer**. A slowly rising flood
  level (a bar) is the night-long pressure; mopping/closing a drain resets it.
- **How it differs:** It is the only threat punished by the player **reacting**.
  Doors do nothing. Cameras can't reveal it (it's under the water line).
- **Counter:** Manage water (close drain = office action), refuse the cry, light
  incense at the pond shrine to calm it for a window. Lethal only at full flood.
- **Fear factor:** 5.
- **Comedic beat:** A pitiful "help… me…" — the guard agonizes, creeps to the
  mop bucket… it's the leaky water cooler. He unplugs it triumphantly. (Then the
  *toilet* gurgles.)
- **Sensitivity:** drowning encodes real child deaths — never show a child
  drowning; keep humor on the guard's water paranoia.

### 2.2 Cô hồn — *Wandering Hungry Souls* (appeasement-economy swarm)
- **Lore (1 line):** Forgotten souls with no one to worship them, roaming during
  Tháng Cô Hồn — hungry and cold, not evil.
- **Spawn / path:** Emerge from CAM1 (Cổng Trường, the night's symbolic
  Quỷ Môn Quan) and drift toward the courtyard offering spot and the office.
- **DISTINCT mechanic — the offering economy (see §4):** A growing *crowd
  pressure* meter. A **stocked, freshly-incensed outdoor offering tray** keeps
  them passive. Let it run empty and they swarm the office windows, spiking Vía
  and blocking your view of other threats. **You never "kill" them — you feed
  them.** The fail-state is *being overwhelmed* (Vía to zero / view smothered),
  framed as the night descending into chaos, NOT a soul grabbing you.
- **How it differs:** Pure resource management, not a positional rusher. They are
  many, slow, and pitiable; the threat is logistics.
- **Counter:** Refill the tray (cháo loãng + muối gạo + bánh kẹo + nước), light
  incense, optionally let the *giật cô hồn* scramble disperse them (§4).
- **Fear factor:** 2 (dread of the crowd, not gore).
- **Comedic beat:** A polite orderly queue of starving ghosts at the tray; the
  guard frantically refilling cháo while one taps the glass impatiently. He
  shares his instant noodles. ("Con mời… đây là phần của con.")

### 2.3 Ông kẹ — *The Bogeyman* (classic door-rusher + "be ngoan")
- **Lore (1 line):** The vague childhood "be good or he'll take you" bogeyman —
  folk-thin by design, the guard's own nursery fear clocking in for a shift.
- **Spawn / path:** CAM1 → CAM2 (Hành Lang Trái) → **left door**. The reliable
  positional rusher that teaches the core door loop.
- **DISTINCT mechanic — obedience, not just doors:** Seen only as a partial
  silhouette in the doorway. He's repelled by closing the **left door** in time
  (power cost) **OR**, when power is scarce, by performing a *"ngoan"* action on
  cue (kill the flashlight, sit still, finish a chore) so he loses interest. So he
  has a **two-option counter**, unlike a pure door threat.
- **How it differs:** The only threat with a non-resource "stay calm / behave"
  counter; the early-night tutorial rusher.
- **Counter:** Left door, or the *ngoan* behavior prompt. Lethal if he steps
  fully into the light.
- **Fear factor:** 3.
- **Comedic beat:** Guard bargaining: "I ate my vegetables. I came home before
  dark. You have NO grounds." Ông kẹ, almost bureaucratically polite, waits.
- **Bestiary tag:** folk-thin / children's bogeyman — no invented canon myth.

### 2.4 Oan hồn — *The Wronged Schoolgirl (white áo dài)* (camera-stalker + multi-night investigation boss)
- **Lore (1 line):** A student who died a wronged death (*chết oan*) walks the
  corridors; she has a specific grievance — and mistakes the new guard for the
  one who wronged her.
- **Spawn / path:** Drifts between CAM2/CAM3/CAM5 and stairwells; **advances when
  watched too long AND when ignored too long** (a tension knife-edge between the
  cameras — opposite of "watch to be safe").
- **DISTINCT mechanic — investigation boss:** She cannot be permanently warded.
  Over several nights the guard gathers clues (a photo, a name, a lost object) and
  performs the **right act** (return the object, light the right incense, say the
  right name) to lay her to rest. Until then she escalates and singles out the
  guard. **The "win" is righting the wrong / siêu thoát, not destroying her** —
  this changes the ending (§8).
- **How it differs:** Only threat with a cross-night narrative state machine and a
  camera-attention paradox; the emotional spine of the game.
- **Counter:** Incense to pacify a zone short-term; the cumulative
  investigation to resolve her for good.
- **Fear factor:** 5.
- **Comedic beat:** Terrifying entrance → she presents an absurdly petty grievance
  ("You never returned my mechanical pencil. 2003."). Horror-to-bathos; her pain
  is real, the misunderstanding is funny. Guard: "Ma'am, I started *last night*."
- **Sensitivity:** death treated with compassion; obscure the manner of death,
  never stage a hanging, never the punchline.

### 2.5 Ma trơi — *Will-o'-the-wisp* (movement-rule hazard: don't run)
- **Lore (1 line):** Pale-blue ghost-flames over the old back field (built atop a
  graveyard); folk says the restless unburied — science says phosphine.
- **Spawn / path:** Drifting blue lights in CAM6 (Sân Sau) and dark corridors; can
  also appear when the guard moves through the field on a patrol beat.
- **DISTINCT mechanic — override your panic:** If the guard **runs/sprints** near a
  flame (or mashes the move key), it **locks on and pursues**, draining Vía and
  light. If he **walks calmly**, it drifts away. Teaches the real folk rule "don't
  run from ma trơi." Also used as a **lure** — a trail of flames baiting you toward
  a worse threat.
- **How it differs:** The only threat governed by *how* you move, not where you
  are; punishes haste. Lowest-gore, "charming-creepy" lighter beat.
- **Counter:** Walk, don't run; stay calm; knowing the chemistry "dispels" it
  (a tape gag).
- **Fear factor:** 3.
- **Comedic beat:** A know-it-all tape voice calmly explaining diphosphine
  combustion while the recorded guard is clearly sprinting and screaming.

### 2.6 Quỷ nhập tràng + Linh miêu — *Risen Corpse & the Black Cat* (cat-prevention trigger)
- **Lore (1 line):** During the wake, a fresh body can sit bolt upright if a cat
  (esp. a black cat) leaps over it — so you keep cat-watch (*canh mèo*).
- **Spawn / path:** A draped, coffin-shaped object in the old infirmary/store-room
  (CAM5 or a dedicated cam). The threat is **dormant**; the **black school cat
  "Mun"** pathfinds toward it on a timer (visible on cameras).
- **DISTINCT mechanic — prevent the trigger:** The corpse is not a rusher — you
  fight the **cause**. Divert Mun away from the draped object: close the right
  door, make noise (an office action), or place a thorny-branch barrier (item). If
  the cat **crosses the body**, quỷ nhập tràng **activates for the night** (a
  sudden sit-up look-away state: do NOT let it grab you, back away). A
  *prevention puzzle* + a conditional stalker.
- **How it differs:** The only threat with an intermediary AI agent (the cat) and a
  "stop X from happening" loop rather than "block X from reaching you."
- **Counter:** Cat management; if triggered, look-away/retreat until dawn.
- **Fear factor:** 4.
- **Comedic beat:** The guard's entire job tonight is "keep the cat off the
  spooky thing," and Mun is *committed*. He offers Mun a snack as a bribe; Mun
  accepts, then beelines for the object anyway. Cat is never harmed — only herded.
- **Sensitivity:** funeral imagery stays dignified; Mun is a hazard to manage, not
  an animal to hurt (no animal-cruelty option).

### 2.7 Ma lai — *Flying Severed Head* (OPTIONAL dawn-deadline aerial; v2 candidate)
- **Lore (1 line):** A shared Southeast-Asian being — a head that detaches at
  night trailing viscera and must rejoin its body by dawn. **In-world legend the
  characters debate.**
- **Spawn / path:** Aerial — drifts past **upper** windows / the roof vent (the
  office "look up" axis), bypassing ground doors. Detected by its faint **glow** on
  CAM6 / the vent feed.
- **DISTINCT mechanic — survive to 6AM:** It cannot be killed; it must return to
  its body by sunrise. Seal **upper** windows / the vent (a different defensive
  axis than doors), or salt/block its lane; otherwise just **endure until 6AM**,
  reinforcing the survival clock.
- **How it differs:** Only **aerial/vertical** threat; only one whose counter is
  literally "outlast the night."
- **Counter:** Vent/upper-window seal; thorny barrier; dawn.
- **Fear factor:** 5 (body-horror — use sparingly, low-gore).
- **Comedic beat:** Guard refuses to believe in "the flying-head one" — "that's
  the *Thai* one, isn't it?" — a self-aware nod to shared lore.
- **STATUS:** Body-horror + real persecution history → **ship as a debated
  legend or hold for v2.** Bestiary must label shared-SEA + ethnic-minority
  origin and never reenact accusation "tests."

> **Roster decision:** ship **2.1–2.6 as the core six** (one of each mechanic
> archetype, all low-risk). Add **2.7 Ma lai** as the 7th only with the
> sensitivity guardrails honored; otherwise reserve for v2. (Older MASTER_PLAN
> names — "ma_lai", "quy_nhap_trang", "co_hon", "ong_ke" in game_state — should be
> reconciled to these IDs: `ma_da, co_hon, ong_ke, oan_hon, ma_troi,
> quy_nhap_trang, ma_lai`.)

### Mechanic-distinctness matrix
| Threat | Archetype | Counter axis | Punishes |
|---|---|---|---|
| Ma da | water look-away | inaction + water mgmt | reacting/answering |
| Cô hồn | appeasement swarm | offerings/incense | neglecting the tray |
| Ông kẹ | door-rusher | door OR "ngoan" | slow door / panic |
| Oan hồn | camera paradox boss | investigation | over- or under-watching |
| Ma trơi | movement rule | walk, don't run | haste/running |
| Quỷ nhập tràng | cat-prevention | divert the cat | letting the trigger fire |
| Ma lai (opt) | aerial dawn-deadline | seal vent / outlast | ignoring the up-axis |

---

## 3. The VÍA System (spirit / sanity)

Grounded in **vía / phách** (the corporeal yin half of the soul; Daoist
hồn-phách, with the Vietnamese *nam thất nữ cửu* folk layer — men 7 vía, women 9).
HUD label already exists: `HUD_VIA` = "Vía". Disclaim the shared Daoist origin in
the bestiary/tape lore.

- **Representation:** A meter rendered as **flames/lanterns guttering out**
  (the popular "three flames on the shoulders" image — tagged *folk/ghost-story*,
  not classical doctrine). Default **7 segments** (male guard); a "nặng/yếu vía"
  difficulty trait may set max/decay (see below).
- **What drains Vía:**
  - Proximity to an active threat; being stared at by oan hồn; the cô hồn swarm at
    the windows.
  - **Breaking a night taboo** (answering a voice at night, whistling, turning your
    *whole* body when called from behind, hanging laundry out, picking up the
    dead's dropped offering-money, soi gương in the dark).
  - A successful jump-scare (large hit); darkness/blackout (slow bleed).
- **What it does at low levels** (`GameEnums.ViaState`):
  - **NORMAL:** clean perception.
  - **SHAKEN** (~40%): audio-visual distortion, false apparitions/fake-out
    silhouettes, the warning line `WARNING_LOW_VIA` ("Vía yếu... đừng nhìn lâu.").
  - **CRITICAL** (~15%): heavy distortion, a real threat can land a "soul-snatch"
    grab that at **0 Vía** = game over (your hồn is taken). One flame left = one
    mistake left.
- **How to restore Vía:**
  - **Đốt vía** — the core cleanse: a short threshold ritual (burn paper, step over
    it the folk-correct **7×** male / **9×** female), restoring a chunk and purging
    weak spirits nearby. Costs **time** during the night (risk/reward). Comedy lives
    in the guard *miscounting his step-overs*, never in the chant being absurd.
  - **Light incense** at a safe-zone altar (steady regen aura).
  - **Petting Mun** the cat (small regen, when she's friendly).
  - **Dawn** — Vía recovers as dương khí returns toward 6AM.
  - **Gọi hồn** second-chance: if Vía hits 0, a one-time ally rescue (the black dog,
    or a scripted elder over the phone "hú hồn hú vía") can revive you once.
- **Trait tie-in:** Selectable/forced protagonist trait *yếu bóng vía* (weak-aura
  = smaller, faster-draining Vía: hard mode) vs *nặng vía* (slower drain, but some
  spirits hide better from you).

---

## 4. OFFERINGS — Cúng Cô Hồn (appeasement economy)

The respectful heart of the loop. The whole shift is framed as one **Tháng Cô
Hồn** night (7th lunar month, when the gate opens). HUD: `HUD_OFFERINGS` = "Đồ
cúng"; prompt `OFFERING_PROMPT`; confirm `OFFERING_DONE` ("Đã cúng. Mong các vong
yên nghỉ.").

- **The tray (mâm cúng), set OUTDOORS only** (gate/courtyard, never on the indoor
  bàn thờ): assemble the correct **humble** items — **cháo trắng loãng** (thin
  porridge, the key item), **gạo muối**, **bánh kẹo**, **nước**, fruit. Finishing
  the rite = **rải gạo muối outward** + (optionally) **đốt vàng mã** to see the
  souls off.
- **Forbidden-offerings rule (authentic + a fail-state):** the tray must be humble
  and meatless. **No xôi (sticky rice), no gà (chicken), no mặn (salty/meat).**
  Wrong food → a disappointed groan and the offering fails (a *gentle* comedic
  beat — the joke is the guard's mistake, never the rite). The "needle-thin
  throat" lore is the teaching moment: lavish food **fails**; humble cháo works.
- **Loop:** Cô hồn crowd-pressure climbs over the night; a stocked, freshly
  incensed tray keeps them passive; an empty tray = swarm (§2.2). The player
  rations limited offerings (`OFFERING_NONE` = "Hết đồ cúng rồi") against time
  spent on other threats.
- **Placement rule = a taboo:** scatter **outward**; flinging muối gạo **indoors**
  breaks the ward / buffs the swarm. Failure is clearly framed "the rookie did the
  etiquette wrong," with a one-line cue teaching the correct way.
- **Giật cô hồn (risk/reward beat):** when an offering is set, a chaotic scramble
  of mischievous child-spirits may descend. **Let them snatch it** → lose the items
  but gain calm/"lộc" (and cover from a scarier threat). **Guard it** → keep items
  but anger the souls. Authentic message: sharing brings fortune. Comedy = the
  slapstick scramble, never violence.
- **Compassion framing:** feeding sends souls peacefully on (*siêu thoát*); the
  altar/incense are reverent safe zones; **never** stage a scare on the altar or
  during an offering. **Never label this night "Vu Lan."**

---

## 5. ITEM / SHOP SYSTEM (helpful-or-cursed, hidden)

Items are `ItemDef` resources; `kind` (HELPFUL/CURSED/NEUTRAL) is **hidden** from
the player and learned through play. Dispatched by `effect_id` in ItemSystem.

**CRITICAL split (Hard Rule §1.1):** **Sacred items are NEVER in the cursed
pool.** Curse risk lives only on **profane/suspect** items and on **counterfeit**
goods from a **fake vendor** (§6). The reliable-sacred tier vs the gamble tier:

### Tier A — Sacred / reliable (always HELPFUL when used right)
| id | Display (vi / en) | effect_id | Effect | kind |
|---|---|---|---|---|
| `nhang` | Cây nhang / Incense | `calm_zone` | Light 1/3/5 (odd) at a shrine: calms a zone, regen Vía, briefly reveals a threat via smoke. Wrong **count** = weak effect (not a curse — player error). | HELPFUL |
| `muoi_gao` | Muối gạo / Salt-rice | `salt_line` | Scatter **outward** across a threshold: a degrading ward line vs weak spirits / feed the swarm. Indoors = ward breaks (taboo lesson). | HELPFUL |
| `bua_that` | Bùa thật / Real amulet (temple/legit) | `ward_save` | One-time "save" vs a grab, or seal a door for a phase. Reliable because it's genuine. | HELPFUL |
| `nuoc_phep` | Nước phép / Blessed water (folk thầy-pháp) | `cleanse` | Sprinkle: dispel a spirit's buff / wash off a "taint" debuff / reset a cursed zone. | HELPFUL |
| `vong_dau_tam` | Vòng dâu tằm / Mulberry bracelet | `child_ward` | Passive ward vs **child-type/startle** threats (Mun-triggered scares, child-spirits); cuts startle damage. | HELPFUL |
| `toi` | Tỏi / Garlic | `repel_weak` | Cheap starter: small passive courage buff; throw a bruised clove to make a weak wandering soul recoil briefly. | HELPFUL |
| `banh_chung` | Bánh chưng / Sticky-rice cake | `ancestor_favor` | Offer at the school shrine to invoke ancestral protection (temp guardian buff / second chance). Wholesome, good-karma option. | HELPFUL |
| `canh_gai` | Cành gai / Thorny branch | `barrier` | Place at a threshold/vent: blocks the cat's path (quỷ nhập tràng) or ma lai's aerial lane. | HELPFUL |

### Tier B — Profane / suspect (the real gamble: may be CURSED)
| id | Display (vi / en) | effect_id | Effect | kind |
|---|---|---|---|---|
| `banh_la` | Bánh lạ / Strange pastry | `speed_curse` | **Doubles** threat aggression for 60s. | CURSED |
| `bua_rom` | Bùa rởm / Counterfeit charm | `power_drain` | Drains Vía/power instantly — because it's a **fake** sold by a con vendor (the joke is the fraud, not real amulets). | CURSED |
| `tien_roi` | Tiền rơi / Dropped offering-money | `taint` | Picking up the dead's money = bad-luck taint debuff (a taboo made into an item). | CURSED |
| `chai_la` | Chai nước lạ / Unlabeled bottle | `mimic` | Looks like nước phép; might be plain well water (does nothing, wastes a turn) — the Bảo-Lộc-style counterfeit gag, fully fictionalized. | NEUTRAL/CURSED |

### Tier C — Mundane-funny
| id | Display (vi / en) | effect_id | Effect | kind |
|---|---|---|---|---|
| `nuoc_mam` | Nước mắm / Fish sauce | `odor_cloud` | The flagship gag: thrown like holy water it does **nothing** supernatural — but the **stench** makes nearby entities (and the guard) recoil. Not a true ward; may attract a hungry/animal threat. Also a small "taste of home" Vía morale boost. | NEUTRAL |
| `den_ong_sao` | Đèn ông sao / Star lantern | `fragile_light` | Portable fragile light for a blackout: reveals nearby threats but **marks your position**. Bribe/light-morale tie to child-spirits. | NEUTRAL |

- **Design:** shop shows 3 items; effects hidden. Tier A is safe-by-design so a
  player is never punished for trusting incense/salt/a real amulet. Tier B/C carry
  the gamble + replay hook. **Combo gag:** `toi` + `nuoc_mam` = stacked odor
  debuff at the cost of attracting certain creatures.

---

## 6. Bà Bán Hàng Rong — Dual-State Vendor

A real, **dignified** roaming street-food vendor (gánh hàng rong, nón lá, áo bà
ba, shoulder-pole baskets). She is the **warm straight-woman** of the comedy and
the mobile shop. States: `GameEnums.VendorState.{IDLE, SHOP, HOSTILE, LEAVING}`.
Strings: `SHOP_TITLE`, `SHOP_PROMPT` ("Mua không em?"), `SHOP_INVITE`,
`SHOP_TIMER`, etc. Config: `NightConfig.vendor_*`.

```
IDLE ──(random vendor_min..max interval)──▶ approaches, sings her tiếng rao
SHOP ── shows on CAM1, 30s window (SHOP_TIMER), player "Mời Vào" → 3-item shop
   ├─ player buys → applies item → LEAVING → IDLE
   └─ ignored too long → … see dual-state below
```

### The crucial twist (Sensitivity: never villainize the real bà)
The **genuine** vendor never becomes the monster. Two figures share her shape:

- **REAL bà:** Her **tiếng rao** (street cry) is **warm and correct**, arrives at
  a plausible hour, sells **reliable Tier-A/C** goods. Ignoring her just means she
  shrugs and wanders off (LEAVING → IDLE). She is dignified; her hardship is never
  the joke.
- **COUNTERFEIT vendor (the impostor):** Something **wearing her shape**. The
  **tell** is the call: **pitched-down, slowed, looped wrong, or arriving at an
  impossible 3 AM**, sometimes at the wrong camera. Buying from the fake one
  dispenses **cursed Tier-B** goods (bùa rởm, etc.). If you fail to spot it and it
  lingers, **the impostor** turns HOSTILE and rushes the left door (reuse ông kẹ
  pathing); close the door and "she" leaves. **The HOSTILE/GameOver art is the
  impostor, never a beloved-grandmother caricature.**

So the player's real skill is **reading the call before opening the window** — an
audio-judgment mini-mechanic that doubles as horror and protects the vendor's
dignity. (Comedy: the guard haggling over incense while a ghost looms behind him;
"Bà" calmly continuing her patter through a jump-scare — *for the real one*.)

---

## 7. NIGHT-BY-NIGHT PROGRESSION

Six nights + a custom night. Each is a `NightConfig` (`data/nights/`). `00:00 →
06:00`, `seconds_per_hour` ≈ 90 (9 real min/night, tightening on later nights).
**Midnight (giờ Tý) is the peak-dread spike**; danger eases toward dawn. Threats
introduced one at a time so each mechanic is learned before stacking. AI levels
0–20 with `ai_ramp` climbing per night.

| Night | New / escalated | Active threats (start AI) | Systems on | Notes |
|---|---|---|---|---|
| **1 — Làm quen** | Ông kẹ (door-rusher tutorial) | ông_kẹ 2 | doors, lights, cameras, Vía, **tape** | Teaches door loop + "ngoan". Vendor off. Gentle. |
| **2 — Tiếng nước** | + Ma da (water look-away) | ông_kẹ 3, ma_da 2 | + water nodes, offerings intro | Learn "don't answer the water." Vendor **on** (real only). |
| **3 — Mâm cúng** | + Cô hồn (offering swarm) | ông_kẹ 4, ma_da 3, cô_hồn 3 | + full Cúng Cô Hồn economy, **giật cô hồn** | Tháng Cô Hồn night proper. Counterfeit vendor may appear. |
| **4 — Con mèo** | + Quỷ nhập tràng / Mun (cat-prevention) | +quỷ_nhập_tràng 3; others +1 | + cat AI, thorny-branch item | Prevention puzzle layered over swarm. |
| **5 — Đốm xanh** | + Ma trơi (movement rule) | +ma_trơi 4; others +1–2 | + patrol/field beat, **đốt vía** stressed | "Don't run." Midnight spike sharpens. |
| **6 — Oan hồn** | Oan hồn climax (investigation boss) | all active, mid-high AI | investigation resolution beat | The wronged schoolgirl arc resolves → branches ending. Optional ma lai cameo as "debated legend." |
| **Đêm Tùy Chỉnh** | Player sets each threat's AI 0–20 | configurable | all | Custom Night (`MENU_CUSTOM_NIGHT`). Unlocks after Night 6. "7/20/7" style preset names. |

- **Difficulty curve:** Night 1 forgiving (slow AI, generous power/Vía); each night
  raises starting AI + `ai_ramp` + tightens `seconds_per_hour` and power economy.
  `Difficulty.{EASY..NIGHTMARE}` scales the base table multiplicatively.
- **Per-night tape** (`has_tape`) gates the narrative (§8).
- **Unlock gating:** Nights unlock sequentially (`MENU_LOCKED` / `MENU_NIGHTS`);
  Custom Night after clearing Night 6 (`WIN_ALL_DONE`).

---

## 8. NARRATIVE — The Previous Guard's Cassette Tapes

### Frame
The school is **Trường THCS Minh Phúc** (fictional). The new guard inherits a
worn notebook of folk rules and a shoebox of **cassette tapes** from **bác Tư**,
the previous night guard, who "stopped showing up." Each night you find/play one
tape (`TAPE_*` strings) — tutorial + lore + slow-burn mystery. The school sits on
older ground (an old **pond**, a **back field over a graveyard**, a former
infirmary used once as a wake room) — explaining ma da, ma trơi, and quỷ nhập
tràng on the grounds.

### The tape arc (one per night; comedy + dread + restraint)
- **Tape 1 (warm, practical):** "Chào người mới. Quy tắc số một: thắp nhang lẻ —
  một, ba, hoặc năm. Đừng bao giờ bốn. Và… đừng gọi tên ai sau nửa đêm." (Then,
  cheerfully:) "À, con mèo tên Mun. Nó dễ thương. Đừng tin nó."
- **Tape 2:** the water rule — "Nếu nghe tiếng kêu cứu từ chỗ có nước… kệ nó.
  Tao xin lỗi đứa nhỏ dưới ao mỗi đêm. Mày cũng nên xin lỗi." (Compassion, not
  contempt — ma da is a wronged child.)
- **Tape 3:** Tháng Cô Hồn — keep the tray full, scatter **outward**. A funny
  aside about the day staff cúng-ing at the wrong hour. Bác Tư's voice warmer here.
- **Tape 4:** the cat + the draped thing in the store-room. Bác Tư clearly scared
  but trying to be brave; a self-deprecating "đừng cười tao" joke.
- **Tape 5:** the blue field lights — bác Tư insists you DON'T run, then the tape
  records him… running. (Comedy via the gap.)
- **Tape 6 (the turn):** bác Tư realizes the corridors' **áo dài** girl isn't
  hunting *him* — she's looking for someone specific, and a wrong was never set
  right. His last tape asks the new guard to **finish what he couldn't**: find her
  name, return what was taken, let her rest. (No body, no method shown — only the
  unrighted wrong.)

### Backstory revealed across nights (restrained, never over-explained)
Decades ago a student (the oan hồn) was wronged at the school; the matter was
buried with her. Bác Tư spent years half-solving it. The "active" nights are her
grievance surfacing during Tháng Cô Hồn. **The villain is a long-dead human
wrongdoer**, never the dead girl, never the faith.

### Multiple endings (hinted, branch on player choices)
- **Survivor ending** (default — clear nights without resolving her): you live to
  6AM, but she still walks. `WIN_SURVIVED` / bittersweet. (`WIN_AGAIN`.)
- **Siêu thoát / "good" ending** (gather all clues + perform the right act on
  Night 6): the wrong is acknowledged, she rests, dawn breaks gently — the warm
  Vu-Lan-adjacent reverent note (filial-piety/compassion, clearly *not* horror).
  `WIN_ALL_DONE`-tier.
- **Compassion sub-ending:** if you consistently fed cô hồn and befriended a
  lonely soul, that soul warns/aids you in the climax (the warmth-amid-horror beat).
- **Bad/abrupt ending:** caught (`GO_TITLE` / `GO_CAUGHT_BY`) — the loop the genre
  expects.

Comedic line samples for tapes (keep ~10% of runtime light): bác Tư mid-lore
getting interrupted by his own microwave; "Nếu mày thấy chai nước mắm cạnh chai
nước phép — NHỚ KỸ cái nào là cái nào. Tao… tao học bài học đó rồi."

---

## 9. AUDIO & ART DIRECTION (from media-tone research)

**Tone thesis:** *the familiar turned wrong.* Build dread by souring cozy
school/Tết/altar familiarity, not by importing Western gore. Folk detail **is**
the identity, not decoration. A **moral/karmic spine** (nghiệp báo) and
**restraint** (anticipation, darkness, silence over loud stings) define the
respected Vietnamese-horror register; **ration jump-scares**, don't over-explain.

### Audio
- **Ambience:** lo-fi night — distant motorbikes, crickets, a far temple bell,
  rain on tin, the hum of an old CRT monitor. Seamless loop.
- **Signature motif — eerie đồng dao:** an **original** children's chant (write it;
  do **not** reproduce "Bắc Kim Thang" film lyrics) as a tinny music-box "threat
  near" cue. Payoff: the guard hums it to self-soothe, then a second, colder voice
  joins. (Heritage rhyme as inspiration only.)
- **Per-threat audio tells:** ma da's false "help me" (the lure you must ignore);
  Mun's collar-bell + claws on the roof; ma trơi's low electrical crackle; oan
  hồn's distant áo dài rustle; cô hồn's hungry murmur swelling at the windows;
  the **vendor's tiếng rao** (the warm vs warped versions are the core tell).
- **Reverent SFX kept straight:** incense whoosh, the offering bell
  (`offering_bell`), a soft chime on a completed rite. Never comedic-ize the rite.
- **Diacritically-correct VN voice lines** (ElevenLabs/recorded), e.g. "Mua không
  em?", the đốt-vía chant, bác Tư's tapes. Native-speaker proof.
- **6AM:** rooster crow + morning bell + warm swell = salvation (dương khí returns).
- **`SET_SCARE_OFF`** must mute stings/jump images → soft fade + low cue instead.

### Art (2.5D)
- **Palette:** dark blues/greens for night, warm amber for safe zones (altar,
  lantern, dawn). Heavy shadow, strong silhouettes; "signs of rot" (peeling
  walls, water stains) as visual metaphor for a buried wrong.
- **Setting:** an old French-colonial-era school — peeling corridors, a courtyard
  banyan, a lotus pond/old well, tin roofs, a shrine niche. Authentic, atmospheric.
- **Guard office (3D-ish):** pan-around rig with deliberate look axes (left/right
  doors, **up** = roof vent for ma lai, **down** = floor drain for ma da), a CRT
  monitor for the 2D feeds, a desk altar (amber, safe), instant-noodle cup, the
  cassette player.
- **Camera feeds (2D):** flat, grainy, scan-lined; `CAM_SIGNAL_LOST` /
  `CAM_OFFLINE` states. Threats read as strong silhouettes.
- **Bestiary (Hồ Sơ Ma):** each card respectfully illustrated **with its honesty
  tag** (documented / urban legend / ethnic-minority / folk-thin / shared) — turn
  scholarship into a selling point.
- **Threat design specifics:** avoid jiangshi Qing-robes/hopping and Japanese
  yūrei clichés; anchor in Vietnamese specifics (white **áo dài** schoolgirl,
  nón lá vendor, the black cat, blue field-flames). Con ma vú dài (if ever used):
  never sexualized, treated with pity, tagged urban legend.

---

## 10. BILINGUAL FLAVOR LIST (player-facing)

Add/confirm in `localization/strings.csv` (correct diacritics mandatory). Many
keys already exist; new ones marked **[new]**.

| key | vi | en |
|---|---|---|
| `SHOP_PROMPT` | Mua không em? | Buy something, dear? |
| `OFFERING_DONE` | Đã cúng. Mong các vong yên nghỉ. | Offering placed. May the souls rest. |
| `WARNING_LOW_VIA` | Vía yếu... đừng nhìn lâu. | Your spirit is weak... don't stare too long. |
| `TABOO_NO_NAME` **[new]** | Đừng gọi tên ai sau nửa đêm. | Don't call anyone's name after midnight. |
| `TABOO_NO_ANSWER` **[new]** | Nghe gọi sau lưng — đừng quay lại. | Hear a call behind you — don't turn around. |
| `MADA_LURE` **[new]** | Cứu... cứu tôi với... | Help... please, help me... |
| `MADA_RESIST` **[new]** | Kệ tiếng dưới nước. Đừng trả lời. | Ignore the voice in the water. Don't answer. |
| `DOT_VIA_CHANT` **[new]** | Vía lành thì ở, vía dữ thì đi. | Good aura stay, bad aura go. |
| `INCENSE_RULE` **[new]** | Thắp nhang lẻ — một, ba, năm. Đừng bốn. | Light odd incense — one, three, five. Never four. |
| `OFFERING_WRONG` **[new]** | Đồ cúng phải thanh đạm. Bỏ đồ mặn ra. | Offerings must be humble. Take the meat out. |
| `CAT_WARN` **[new]** | Giữ con Mun tránh xa cái mền kia! | Keep Mun away from that draped sheet! |
| `MATROI_RULE` **[new]** | Thấy đốm xanh thì đi chậm. Đừng chạy. | See the blue flame? Walk slow. Don't run. |
| `VENDOR_FAKE_TELL` **[new]** | Tiếng rao... sai sai. Đừng mở cửa sổ. | That street-cry... is wrong. Don't open the window. |
| `OAN_HON_PETTY` **[new]** | Trả cây bút cho tôi... | Give me back my pen... |
| `TAPE_FROM` | Từ người bảo vệ cũ | From the previous guard |
| `WIN_SURVIVED` | Anh sống sót. | You survived. |
| `GO_TITLE` | ĐÊM NAY KHÔNG QUA ĐƯỢC | YOU DIDN'T MAKE IT |
| `DAWN_GREET` **[new]** | 6 giờ. Trời sáng rồi. Mình qua được rồi. | 6 o'clock. Dawn. We made it. |

---

## 11. Data-authoring checklist (so guardrails ship)

- `data/threats/*.tres`: `ma_da, co_hon, ong_ke, oan_hon, ma_troi, quy_nhap_trang`
  (+ optional `ma_lai`), each with `name_key`, `bestiary_key` (+ honesty tag),
  `fear_factor`, `accent_color`. Reconcile old game_state IDs.
- `data/items/*.tres`: Tier A sacred → `kind = HELPFUL` only; Tier B/C →
  gamble. **No sacred item in the cursed pool.** Rename any "Bùa = drain" to
  `bua_rom` (counterfeit). Drop unattributed `nuoc_thanh`; use `nuoc_phep` (folk),
  reserve Catholic "nước thánh" only behind a Catholic NPC and always helpful.
- `data/nights/*.tres`: the §7 table; midnight spike; sequential unlocks.
- `localization/strings.csv`: add the **[new]** keys above; native-speaker proof.
- Bestiary text: every entry carries its origin/honesty tag (Hard Rule §6–§7).
- Altar/offering art + the đồt-vía/incense/vendor lines: route past a Vietnamese
  cultural reader before ship.
