extends Node
## Applies item effects (DESIGN.md §5) by dispatching on ItemDef.effect_id.
## Sacred items are HELPFUL by construction; only Tier-B can be CURSED.

var _c   # NightController

func setup(controller) -> void:
	_c = controller

func apply(def: ItemDef) -> void:
	var cursed := def.kind == GameEnums.ItemKind.CURSED
	match def.effect_id:
		"calm_zone":
			_c.add_via(def.magnitude)
			_c.start_reveal(6.0)
			_c.broadcast_calm()   # incense actually settles ma da / cô hồn / oan hồn
		"salt_line":
			_c.setback_nearest()
			_c.add_via(4.0)
		"ward_save":
			_c.grant_ward(int(def.magnitude))
		"cleanse":
			_c.cleanse()
			_c.add_via(8.0)
		"child_ward":
			_c.add_startle_resist(def.magnitude)
		"repel_weak":
			_c.add_via(6.0)
			_c.setback_nearest()
		"ancestor_favor":
			_c.grant_ward(1)
			_c.add_via(6.0)
		"barrier":
			_c.set_barrier(def.duration)
		"speed_curse":
			_c.set_global_speed(def.magnitude, def.duration)
		"power_drain":
			_c.add_power(-def.magnitude)
		"taint":
			_c.add_taint(def.duration)
		"mimic":
			pass  # plain water — does nothing, wastes the turn
		"odor_cloud":
			_c.add_via(5.0)
			_c.setback_nearest()
		"fragile_light":
			_c.start_reveal(def.duration)
		_:
			push_warning("ItemSystem: unknown effect " + def.effect_id)
	Audio.play_sfx("item_bad" if cursed else "item_good", -2.0)
	Events.item_consumed.emit(def.id)
	Events.item_effect_applied.emit(def.effect_id, {})
	Events.notify.emit("ITEM_USED", [tr(def.name_key)])
