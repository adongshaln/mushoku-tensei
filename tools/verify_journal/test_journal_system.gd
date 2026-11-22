extends SceneTree

var _passed := 0
var _failed := 0
var _unlocked_events: Array[String] = []
var _last_unread_signal := -1


func _init() -> void:
	call_deferred("_run_all")


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("[FAIL] " + msg)
		print("[FAIL] " + msg)


func _on_codex_unlocked(entry_id: String, _entry_data: Dictionary) -> void:
	_unlocked_events.append(entry_id)


func _on_codex_read_changed(unread: int) -> void:
	_last_unread_signal = unread


func _run_all() -> void:
	var wb: Node = root.get_node("WorldBlackboard")
	var eco: Node = root.get_node("EconomyManager")
	var jm: Node = root.get_node("JournalManager")
	var save_mgr: Node = root.get_node("SaveManager")

	print("=== Journal & Codex System Headless Verification (Godot 4.7.2) ===")

	# 1. Validate world_codex.json structure, uniqueness & non-empty fields
	var raw_codex: Dictionary = wb.call("read_config", "res://data/codex/world_codex.json")
	var cats: Array = raw_codex.get("categories", [])
	var raw_entries: Array = raw_codex.get("entries", [])
	_assert(cats.size() == 4, "Expected 4 codex categories, got %d" % cats.size())
	_assert(raw_entries.size() >= 14 and raw_entries.size() <= 18,
		"Expected 14-18 seed codex entries, got %d" % raw_entries.size())

	var valid_cat_ids: Dictionary[String, bool] = {}
	for c_var: Variant in cats:
		var c: Dictionary = c_var
		valid_cat_ids[str(c.get("id", ""))] = true

	var seen_ids: Dictionary[String, bool] = {}
	for e_var: Variant in raw_entries:
		var e: Dictionary = e_var
		var eid := str(e.get("id", ""))
		_assert(not eid.is_empty() and not seen_ids.has(eid), "Duplicate or empty codex id: " + eid)
		seen_ids[eid] = true
		_assert(valid_cat_ids.has(str(e.get("category", ""))), "Invalid category for codex entry: " + eid)
		_assert(not str(e.get("title", "")).strip_edges().is_empty(), "Empty title in " + eid)
		_assert(not str(e.get("subtitle", "")).strip_edges().is_empty(), "Empty subtitle in " + eid)
		_assert(not str(e.get("summary", "")).strip_edges().is_empty(), "Empty summary in " + eid)
		_assert(not str(e.get("body", "")).strip_edges().is_empty(), "Empty body in " + eid)
		_assert(e.has("default_unlocked") and e["default_unlocked"] is bool, "Missing bool default_unlocked in " + eid)
		_assert(e.get("unlock_triggers") is Dictionary, "Missing unlock_triggers dict in " + eid)

	# 2. Fresh state & city arrival + codex unlock & unread tracking
	wb.call("reset_new_game")
	eco.call("reset_from_blackboard")
	jm.call("reset_for_new_game")

	jm.connect("codex_unlocked", _on_codex_unlocked)
	jm.connect("codex_read_changed", _on_codex_read_changed)

	_assert(bool(jm.call("is_codex_unlocked", "geo_demon_continent")), "geo_demon_continent should default unlock")
	_assert(bool(jm.call("is_codex_unlocked", "geo_migurd_basin")), "geo_migurd_basin should default unlock")
	_assert(not bool(jm.call("is_codex_unlocked", "geo_rikarisu")), "geo_rikarisu should start locked")
	_assert(not bool(jm.call("is_codex_unlocked", "lore_adventurer_guild")), "lore_adventurer_guild should start locked")
	_assert(int(jm.call("get_unread_codex_count")) == 0, "Fresh game should have 0 unread default codex")

	# Diary add_entry + Dragon Calendar timestamp + dedupe_key
	var e1: Dictionary = jm.call("add_entry", "milestone", "告别米格路德村", "背上木杖启程。", {"tone": "positive"}, "depart_migurd")
	var e1_dup: Dictionary = jm.call("add_entry", "milestone", "告别米格路德村（重复）", "不应重复写入。", {"tone": "positive"}, "depart_migurd")
	_assert(str(e1.get("id", "")) == str(e1_dup.get("id", "")), "dedupe_key should return existing entry")
	_assert(int(jm.call("get_diary_count", "milestone")) == 1, "dedupe_key prevented duplicate milestone entry")
	_assert(str(e1.get("date_text", "")).contains("甲龙历 418 年 1 月 1 日"), "Diary entry must capture exact Dragon Calendar stamp")
	_assert(str(e1.get("location", "")) == "米格路德村", "Diary entry must capture current city location")

	# Dice highlight Crit Success & Crit Fail
	var crit_s: Dictionary = jm.call("record_dice_highlight", "察觉", 20, 14, true, false, "穿越红岩峡谷")
	var crit_f: Dictionary = jm.call("record_dice_highlight", "潜行", 1, 13, false, true, "夜宿荒野")
	_assert(str(crit_s.get("tone", "")) == "positive" and str(crit_s.get("badge", "")).contains("大成功"),
		"Crit success must carry positive warm tone and 大成功 badge")
	_assert(str(crit_f.get("tone", "")) == "negative" and str(crit_f.get("badge", "")).contains("大失败"),
		"Crit fail must carry negative cool tone and 大失败 badge")

	# Arrival at city_migurd (already unlocked codex) & city_rikarisu (auto-unlocks geo_rikarisu + lore_adventurer_guild!)
	_unlocked_events.clear()
	jm.call("record_city_arrival", "city_migurd", "米格路德村")
	_assert(_unlocked_events.is_empty(), "Arriving at city_migurd should not re-unlock already unlocked entries")

	wb.call("advance_time", 4)
	wb.current_city_id = "city_rikarisu"
	var arr_rik: Dictionary = jm.call("record_city_arrival", "city_rikarisu", "利卡里斯镇")
	_assert(str(arr_rik.get("category", "")) == "travel", "City arrival must record travel diary entry")
	_assert(bool(jm.call("is_codex_unlocked", "geo_rikarisu")), "Arriving at city_rikarisu must unlock geo_rikarisu")
	_assert(bool(jm.call("is_codex_unlocked", "lore_adventurer_guild")), "Arriving at city_rikarisu must unlock lore_adventurer_guild")
	_assert(int(jm.call("get_unread_codex_count")) >= 2, "New unlocks should mark unread count >= 2")

	var unread_before := int(jm.call("get_unread_codex_count"))
	var read_ok := bool(jm.call("mark_codex_read", "geo_rikarisu"))
	_assert(read_ok and int(jm.call("get_unread_codex_count")) == unread_before - 1,
		"mark_codex_read must decrement unread count by 1")
	_assert(_last_unread_signal == unread_before - 1, "codex_read_changed signal must emit updated count")

	# Record arrival at Milishion -> unlocks geo_milis_holy_country & lore_six_faced_world
	_unlocked_events.clear()
	jm.call("record_city_arrival", "city_milishion", "王都米里希翁")
	_assert(bool(jm.call("is_codex_unlocked", "geo_milis_holy_country")), "city_milishion must unlock geo_milis_holy_country")
	_assert(_unlocked_events.has("geo_milis_holy_country"), "codex_unlocked signal must fire for geo_milis_holy_country")

	# Economy event + filter + keyword search + order
	jm.call("record_economy_event", "guild_exchange", "在利卡里斯镇免税换得 2 米里斯大铜钱。", {"currency_id": "millis"})
	var dice_only: Array = jm.call("get_diary_entries", "dice", "", true)
	_assert(dice_only.size() == 2, "Expected 2 dice diary entries, got %d" % dice_only.size())
	var search_hits: Array = jm.call("get_diary_entries", "all", "利卡里斯", true)
	_assert(search_hits.size() >= 2, "Keyword search '利卡里斯' expected >= 2 hits, got %d" % search_hits.size())
	var asc: Array = jm.call("get_diary_entries", "all", "", false)
	var desc: Array = jm.call("get_diary_entries", "all", "", true)
	_assert(int(asc[0]["seq"]) < int(asc[asc.size() - 1]["seq"]), "Ascending sort broken")
	_assert(int(desc[0]["seq"]) > int(desc[desc.size() - 1]["seq"]), "Descending sort broken")

	# Reactive EconomyManager starvation diary hook
	var existing_r := int(eco.call("get_total_rations"))
	if existing_r > 0:
		wb.call("consume_rations", existing_r)
	var eco_count_before := int(jm.call("get_diary_count", "economy"))
	eco.call("consume_daily_rations", 1, 1)
	_assert(int(jm.call("get_diary_count", "economy")) == eco_count_before + 1,
		"First starvation day should automatically record ONE negative economy diary alert")

	# 3. SaveManager disk roundtrip & Legacy Save Migration (without journal module)
	var orig_dir: String = save_mgr.directory
	save_mgr.directory = "user://saves_verify_journal_tmp"

	var snap_diary_count := int(jm.call("get_diary_count", "all"))
	var snap_progress: Dictionary = jm.call("get_codex_progress")
	var snap_entries: Array = jm.call("get_diary_entries", "all", "", false)

	var saved_ok := bool(save_mgr.call("save_slot", "slot_1", save_mgr.ATLAS))
	_assert(saved_ok, "SaveManager.save_slot failed for journal roundtrip")

	# Clobber runtime state completely
	jm.call("clear_diary")
	jm.call("mark_all_codex_read")
	_assert(int(jm.call("get_diary_count", "all")) == 0, "Clear diary sanity check")

	var restored_ok := bool(save_mgr.call("restore_slot_state", "slot_1"))
	_assert(restored_ok, "SaveManager.restore_slot_state failed for journal roundtrip")
	_assert(int(jm.call("get_diary_count", "all")) == snap_diary_count,
		"Restored diary count mismatch (%d vs %d)" % [int(jm.call("get_diary_count", "all")), snap_diary_count])
	var rest_prog: Dictionary = jm.call("get_codex_progress")
	_assert(int(rest_prog["unlocked"]) == int(snap_progress["unlocked"]) and int(rest_prog["unread"]) == int(snap_progress["unread"]),
		"Restored codex progress/unread mismatch")
	var rest_entries: Array = jm.call("get_diary_entries", "all", "", false)
	_assert(str(rest_entries[0]["title"]) == str(snap_entries[0]["title"]) and str(rest_entries[rest_entries.size() - 1]["title"]) == str(snap_entries[snap_entries.size() - 1]["title"]),
		"Restored diary titles mismatch")

	# Legacy save missing BOTH economy and journal modules, located in city_rikarisu
	var legacy_save := {
		"schema_version": 1,
		"saved_at": "2026-01-01 12:00:00",
		"saved_at_unix": 1767268800,
		"scene_path": save_mgr.ATLAS,
		"meta": {"character_name": "诺缇雅", "location_name": "利卡里斯镇"},
		"modules": {
			"world": {
				"character": {"profile": {"character_id": "notia"}},
				"current_city_id": "city_rikarisu",
				"current_location_id": "rikarisu_gate",
				"currency_copper": 45,
				"world_time": {"year": 418, "month": 1, "day": 5, "slot": 1},
				"chronicle": [{"title": "旧档初入利卡里斯", "text": "旧存档迁移测试。", "date": "甲龙历 418 年 1 月 5 日   下午", "city_id": "city_rikarisu"}]
			}
		}
	}
	var legacy_path: String = str(save_mgr.directory).path_join("slot_2.json")
	var lf := FileAccess.open(legacy_path, FileAccess.WRITE)
	_assert(lf != null, "Could not create legacy save file")
	if lf != null:
		lf.store_string(JSON.stringify(legacy_save, "\t"))
		lf.close()

	var legacy_ok := bool(save_mgr.call("restore_slot_state", "slot_2"))
	_assert(legacy_ok, "Loading legacy save without journal module failed")
	_assert(bool(jm.call("is_codex_unlocked", "geo_demon_continent")), "Legacy load must keep default codex unlocked")
	_assert(bool(jm.call("is_codex_unlocked", "geo_rikarisu")), "Legacy load at city_rikarisu must auto-unlock geo_rikarisu")
	_assert(int(jm.call("get_diary_count", "milestone")) >= 1, "Legacy load must migrate WorldBlackboard chronicle cleanly")

	# Cleanup temporary save folder
	for fn: String in ["slot_1.json", "slot_2.json"]:
		var p: String = ProjectSettings.globalize_path(str(save_mgr.directory).path_join(fn))
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(str(save_mgr.directory)))
	save_mgr.directory = orig_dir

	# 4. Max diary cap protection (500 rolling archive)
	jm.call("clear_diary")
	for idx: int in range(515):
		jm.call("add_entry", "travel", "归档测试 #%d" % idx, "滚动归档上限测试。")
	_assert(int(jm.call("get_diary_count", "all")) == 500,
		"Diary max archive cap should stay at 500, got %d" % int(jm.call("get_diary_count", "all")))

	# 5. Preview scene & UI smoke test (overview, diary, codex + clicking unread entry)
	var preview_res := load("res://scenes/ui/journal/journal_v2_preview.tscn") as PackedScene
	_assert(preview_res != null, "Failed to load journal_v2_preview.tscn")
	if preview_res != null:
		var preview: Node = preview_res.instantiate()
		root.add_child(preview)
		await process_frame
		var overlay: Node = preview.call("get_journal_overlay")
		_assert(overlay != null, "Journal overlay missing from preview")
		for sid: String in ["overview", "diary", "codex"]:
			preview.call("switch_section", sid)
			await process_frame
		var unread_pre := int(jm.call("get_unread_codex_count"))
		var codex_view: Node = overlay.call("get_codex_view")
		codex_view.call("select_entry", "geo_rikarisu", true)
		await process_frame
		_assert(int(jm.call("get_unread_codex_count")) == maxi(0, unread_pre - 1),
			"Selecting unread codex entry in UI must clear its unread badge")
		preview.queue_free()
		await process_frame
		await create_timer(0.45).timeout

	print("=== Journal Verification Complete: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
