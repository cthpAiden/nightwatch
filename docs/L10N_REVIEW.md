# Localization — Native-Speaker Review Checklist

The localization layer is **mechanically clean** (verified 2026-06-26): `strings.csv`
has 345 keys, valid UTF-8 (no BOM), LF endings, **0 missing keys**, **0 empty/untranslated
VI or EN cells**, **0 duplicate keys**, and all 345 VI rows are NFC-normalized with no
mojibake or zero-width characters. Every key referenced in code — literal `tr()`/`UI.label()`/
`UI.button()`/`notify.emit()` and every dynamic family (`COUNTER_<id>`, `NIGHT_TITLE_%d`,
`TAPE_N*_L*`, `PHONE_N*_L*`, `ITEM_*`, `UPG_*`, `CAM*_NAME`) — resolves to an existing row.

What an automated audit **cannot** validate is register, dialect, folklore accuracy, and
tone. The rows below carry cultural weight and should be **read aloud by a Vietnamese
speaker** before release. Priority order: **Tapes + Phone → Endings → ritual/taboo lines →
threat lore/tags → pronoun consistency.**

## 1. Tapes (most prose, most lore-load) — `strings.csv` ~lines 275–292
`TAPE_N1_L1 … TAPE_N6_L3` — the previous guard's voice and the rules: odd incense / never
4, don't call names after midnight, Mun the cat, the ma-da apology, cô hồn offerings, the
corpse under the sheet, ma-trơi "walk slow," the áo-dài girl's unfinished wrong. Check
naturalness and lore accuracy.

## 2. Live phone calls — ~lines 329–346
`PHONE_N1_L1 … PHONE_N6_L3` — bác Tư's live hints, same lore beats. Check the colloquial
imperative tone (`kệ nó`, `liếc nhanh thôi`, `siêu thoát`).

## 3. Endings (tone-critical) — ~lines 70–80
`ENDING_GOOD_L1…L4` + `ENDING_GOOD_SIGN`, `ENDING_SURV_L1…L4`, `WIN_SIEU_TITLE` ("Siêu
Thoát"). Confirm the Buddhist *siêu thoát* (passing-into-rest) framing of the good ending
reads respectfully.

## 4. Ritual / taboo lines — must match real custom
- `INCENSE_RULE` (~224) — odd-incense / never-four taboo
- `TABOO_NO_NAME` (~223) — no names after midnight
- `OFFERING_DONE` (~124) — "Mong các vong yên nghỉ"
- `MADA_LURE` (~209) — "Cứu... cứu tôi với..."
- `OAN_HON_PETTY` (~186), `ALTAR_*` (~298–302)

## 5. Threat lore / tags — ~lines 169–175, 236–246
`BEST_ONG_KE … BEST_BA_GIA` bestiary descriptions; `TAG_*` folklore tags ("Văn hóa dân
gian" / "Truyền thuyết đô thị" / "Hư cấu dân gian" / "Tín ngưỡng chung khu vực"); `COUNTER_*`
one-liners.

## 6. Pronoun / honorific consistency
The script addresses the player as **anh** throughout (`WIN_SURVIVED`, `DAWN_GREET`,
`INTRO_*`); the vendor uses **em** (`SHOP_PROMPT` "Mua không em?"). Confirm the register is
intentional and consistent across all speakers.

---

### Optional cleanups (not blockers, decide per-item)
- **33 orphaned keys** defined but referenced nowhere — bloat the translator's surface.
  Some look like planned-but-unwired UI (`CAM_SIGNAL_LOST`, `CAM_OFFLINE`, `HUD_POWER`,
  `HUD_VIA`, `WARNING_DOOR_STUCK`); others are vestigial generic buttons (`BTN_YES/NO/OK/
  CANCEL/CLOSE/QUIT/RESUME/RETRY/START`). Wire the intended ones or delete the rest.
- **`hud.gd` `(?!)` marker** on the fake-phone answer button is a hardcoded Western glyph
  appended to `ACTION_ANSWER`; a VI reviewer may prefer a different cue. Add an
  `ACTION_ANSWER_FAKE_TAG` key if you want it translatable.

> Note: editing `strings.csv` requires re-importing in the Godot editor so the compiled
> `strings.vi.translation` / `strings.en.translation` binaries regenerate — a CSV-only edit
> will **not** take effect at runtime.
