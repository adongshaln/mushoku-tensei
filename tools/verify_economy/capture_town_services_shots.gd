extends SceneTree

const OUT_DIR := "user://economy_shots"


func _init() -> void:
	call_deferred("_capture_all")


func _wait_frames(n: int) -> void:
	for _i: int in range(n):
		await process_frame


func _save_shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var out_path := abs_dir.path_join(filename)
	var err := img.save_png(out_path)
	if err == OK:
		print("[SHOT] Saved: ", out_path)
	else:
		push_error("[SHOT] Failed to save: " + out_path)


func _capture_all() -> void:
	var wb: Node = root.get_node("WorldBlackboard")
	var eco: Node = root.get_node("EconomyManager")

	var preview_res := load("res://scenes/ui/town_services/town_services_preview.tscn") as PackedScene
	var preview: Node = preview_res.instantiate()
	root.add_child(preview)
	await _wait_frames(6)

	var overlay: Node = preview.call("get_overlay")

	# Setup rich canonical state for Shot 1: Rikarisu Adventurer Guild 0% Exchange + warm buff
	eco.call("set_balance", "demon_ore", 4500)
	eco.call("set_balance", "millis", 800)
	eco.call("set_balance", "asura", 200)
	eco.call("order_meal", "city_rikarisu", "demon_lizard_skewer", "")
	# Re-top wallet so numbers stay crisp & canon: 4 银矿 5 大绿
	eco.call("set_balance", "demon_ore", 4500)
	preview.call("switch_preview_city", "city_rikarisu", "guild")
	await _wait_frames(6)
	var guild_panel: Node = overlay.call("get_active_exchange_panel")
	if guild_panel != null:
		# Demonstrate canon 10 大绿矿钱 (1000) -> 2 米里斯大铜钱 (200) at 0% fee
		guild_panel.call("set_pair_and_amount", "demon_ore", "millis", 1000)
	await _wait_frames(18)
	await _save_shot("01_rikarisu_guild_0pct_exchange.png")

	# Shot 2: Migurd Village Guild Notice (no Adventurer Guild branch) + hungry (-1) cold blue chip!
	var existing_r := int(eco.call("get_total_rations"))
	if existing_r > 0:
		wb.call("consume_rations", existing_r)
	eco.call("consume_daily_rations", 1, 1)
	wb.call("add_item", "ration_normal", "普通干粮", 3, "ration")
	preview.call("switch_preview_city", "city_migurd", "guild")
	await _wait_frames(18)
	await _save_shot("02_migurd_no_guild_notice.png")

	# Shot 3: Migurd Village Supplies & Merchant + Expanded 5% Quick Exchange Drawer!
	preview.call("switch_preview_city", "city_migurd", "merchant")
	overlay.call("set_inline_exchange_open", true)
	await _wait_frames(6)
	var merch_panel: Node = overlay.call("get_active_exchange_panel")
	if merch_panel != null:
		merch_panel.call("set_pair_and_amount", "millis", "demon_ore", 200)
	await _wait_frames(18)
	await _save_shot("03_migurd_merchant_5pct_exchange.png")

	# Shot 4: Migurd Village Inn Rest (showing 5% inn exchange drawer + village luxury bath locked)
	preview.call("switch_preview_city", "city_migurd", "inn")
	overlay.call("set_inline_exchange_open", false)
	await _wait_frames(18)
	await _save_shot("04_migurd_inn_rest.png")

	# Shot 5: Royal Capital Milishion (Millis Currency + Continental Holy Beef Stew Restaurant + Luxury Bath)
	eco.call("clear_hunger_penalties", true)
	eco.stamina = 78
	eco.call("order_meal", "city_milishion", "milis_holy_beef_stew", "")
	eco.call("set_balance", "millis", 1850)
	preview.call("switch_preview_city", "city_milishion", "restaurant")
	overlay.call("set_inline_exchange_open", false)
	await _wait_frames(18)
	await _save_shot("05_milishion_millis_restaurant.png")

	print("=== All 5 Economy UI screenshots captured ===")
	quit(0)
