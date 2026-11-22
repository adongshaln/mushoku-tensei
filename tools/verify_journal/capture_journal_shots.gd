extends SceneTree

const OUT_DIR := "user://journal_shots"


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
	var preview_res := load("res://scenes/ui/journal/journal_v2_preview.tscn") as PackedScene
	var preview: Node = preview_res.instantiate()
	root.add_child(preview)
	await _wait_frames(8)

	var overlay: Node = preview.call("get_journal_overlay")

	# Shot 1: Travel Diary Timeline (warm gold Crit Success & Exchange + cool sea-mist Starvation & Crit Fail)
	preview.call("switch_section", "diary")
	await _wait_frames(18)
	await _save_shot("01_journal_diary_timeline.png")

	# Shot 2: World Codex Reading Page (showing unlocked Rikarisu reading folio + unread gold dot on Adventurer Guild + locked ??? entries)
	preview.call("switch_section", "codex")
	var codex_view: Node = overlay.call("get_codex_view")
	# Select geo_rikarisu (reads it, leaving lore_adventurer_guild still unread with glowing gold dot!)
	codex_view.call("select_entry", "geo_rikarisu", true)
	await _wait_frames(18)
	await _save_shot("02_journal_codex_reading.png")

	# Shot 3: Existing Character Overview preserved seamlessly under the new 3-tab header + unread codex badge
	preview.call("switch_section", "overview")
	await _wait_frames(18)
	await _save_shot("03_journal_overview_upgraded.png")

	print("=== All 3 Journal V2 UI screenshots captured ===")
	quit(0)
