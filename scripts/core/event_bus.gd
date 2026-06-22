extends Node
## Global signal bus (autoload "Events").
## Systems emit and listen here so they stay decoupled. No state lives here —
## persistent run state lives in Game, per-night state in NightController.

# --- Meters -----------------------------------------------------------------
signal power_changed(current: float, maximum: float)
signal power_depleted()
signal via_changed(current: float, maximum: float)
signal via_state_changed(state: int)            # GameEnums.ViaState

# --- Clock ------------------------------------------------------------------
signal clock_advanced(game_minutes: int)        # minutes since 00:00
signal hour_reached(hour: int)                   # 0..6 (6 == survived)
signal night_survived()

# --- Threats ----------------------------------------------------------------
signal threat_relocated(threat_id: String, location_id: String)
signal threat_at_door(threat_id: String, side: int)
signal threat_left_door(threat_id: String, side: int)
signal threat_repelled(threat_id: String)
signal threat_reset(threat_id: String)
signal threat_special(threat_id: String, kind: String, payload: Dictionary)

# --- Outcome ----------------------------------------------------------------
signal jumpscare_started(threat_id: String)
signal game_over(cause_id: String)

# --- Cameras ----------------------------------------------------------------
signal cameras_toggled(is_open: bool)
signal camera_changed(cam_id: String)
signal camera_signal_changed(cam_id: String, ok: bool)

# --- Room controls ----------------------------------------------------------
signal door_toggled(side: int, is_closed: bool)
signal light_toggled(side: int, is_on: bool)
signal view_panned(yaw: float)

# --- Vendor (bà hàng rong) --------------------------------------------------
signal vendor_state_changed(state: int)          # GameEnums.VendorState

# --- Items / offerings ------------------------------------------------------
signal item_added(item_id: String)
signal item_consumed(item_id: String)
signal item_effect_applied(effect_id: String, payload: Dictionary)
signal offering_placed(location_id: String)

# --- Gameplay specials (per-threat mechanics) -------------------------------
signal water_lure(active: bool)                  # Ma da: false cry begins/ends
signal intercom_answered()                        # player took the bait (bad)
signal office_action(action: String)              # close_drain / make_noise / dot_via / light_incense
signal crowd_changed(level: float)                # Cô hồn swarm pressure 0..1
signal water_level(level: float)                  # Ma da flood pressure 0..1
signal cat_moved(location: String)                # Mun the cat
signal cat_triggered()                            # Mun crossed the draped body
signal investigation_updated(clues: int)          # Oan hồn arc progress
signal taboo_broken(taboo_id: String)             # vía penalty + flavor
signal grievance_changed(level: float)            # Oan hồn agro 0..1
signal huong_changed(level: float)                # altar incense protection 0..1
signal altar_lit_changed(lit: bool)               # candles lit vs guttered (draft)
signal phone_ring(active: bool, fake: bool)       # desk phone (fake = ma da lure)
signal anomaly_tagged(threat_id: String)          # player spotted a cam anomaly
signal coins_changed(amount: int)                 # spirit-money / vàng mã balance

# --- Meta / UI --------------------------------------------------------------
signal settings_changed()
signal locale_changed(locale: String)
signal notify(message_key: String, args: Array)  # transient HUD toast
signal cassette_state_changed(playing: bool, night: int)
