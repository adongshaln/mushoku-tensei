extends Node

signal slots_changed

const SCHEMA_VERSION := 1
const TITLE := "res://scenes/title/title_screen.tscn"
const CABIN := "res://scenes/room/room_explorer.tscn"
const ATLAS := "res://scenes/world_map/world_atlas_view.tscn"
const SLOTS: Array[String] = ["auto", "slot_1", "slot_2", "slot_3", "slot_4", "slot_5", "slot_6"]

var directory := "user://saves"
var _modules: Dictionary[String, Dictionary] = {}
var _unclaimed_modules: Dictionary = {}
var _last_day: int
var _autosave_pending := false
var _restoring := false


func _ready() -> void:
	register_save_module("world", WorldBlackboard.serialize_state, WorldBlackboard.deserialize_state)
	register_save_module("storylets", StoryletScheduler.serialize_state, StoryletScheduler.deserialize_state)
	_last_day = _day_stamp()
	WorldBlackboard.world_time_changed.connect(_on_time_changed)
	WorldBlackboard.location_changed.connect(_on_location_changed)


func register_save_module(module_id: String, serialize_cb: Callable, deserialize_cb: Callable) -> bool:
	if module_id.is_empty() or not serialize_cb.is_valid() or not deserialize_cb.is_valid():
		return false
	_modules[module_id] = {"serialize": serialize_cb, "deserialize": deserialize_cb}
	if _unclaimed_modules.get(module_id) is Dictionary:
		deserialize_cb.call(_unclaimed_modules[module_id].duplicate(true))
		_unclaimed_modules.erase(module_id)
	return true


func slot_label(id: String) -> String:
	return "自动手账" if id == "auto" else "手账 %s" % id.trim_prefix("slot_")


func can_save() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path in [CABIN, ATLAS] and _state_stable()


func is_restoring() -> bool:
	return _restoring


func _state_stable() -> bool:
	return not SceneTransition.is_busy() and not _restoring and not WorldBlackboard.is_journey_active() and not StoryletScheduler.is_busy()


func has_any_save() -> bool:
	return not get_latest_slot_id().is_empty()


func get_latest_slot_id() -> String:
	var newest := ""
	var latest_time := -1.0
	for id: String in SLOTS:
		var data := _read(id)
		if data.is_empty():
			continue
		var timestamp := float(data["saved_at_unix"])
		if timestamp >= latest_time:
			newest = id
			latest_time = timestamp
	return newest


func latest_slot() -> String:
	return get_latest_slot_id()


func slot_info(id: String) -> Dictionary:
	var data := _read(id)
	var base := {
		"slot_id": id,
		"label": slot_label(id),
		"is_auto": id == "auto"
	}
	if data.is_empty():
		base["status"] = "invalid" if id in SLOTS and FileAccess.file_exists(_path(id)) else "empty"
		return base
	var result: Dictionary = data["meta"].duplicate(true)
	result.merge(base, true)
	result["status"] = "ready"
	result["saved_at"] = str(data["saved_at"])
	result["saved_at_unix"] = float(data["saved_at_unix"])
	result["scene_path"] = str(data["scene_path"])
	return result


func list_slots() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for id: String in SLOTS:
		entries.append(slot_info(id))
	return entries


func save_slot(slot_id: String, scene_path: String = "") -> bool:
	if slot_id not in SLOTS or not _state_stable():
		return false
	var scene := get_tree().current_scene
	var target_scene := scene_path
	if target_scene.is_empty():
		if scene == null or scene.scene_file_path not in [CABIN, ATLAS]:
			return false
		target_scene = scene.scene_file_path
	elif target_scene not in [CABIN, ATLAS]:
		return false
	var modules := _unclaimed_modules.duplicate(true)
	for module_id: String in _modules:
		var callback: Callable = _modules[module_id]["serialize"]
		if callback.is_valid():
			var state: Variant = callback.call()
			if not state is Dictionary:
				return false
			modules[module_id] = state
	var unix_now := Time.get_unix_time_from_system()
	var saved_text := _format_datetime(Time.get_datetime_dict_from_system(false))
	var char_name := str(WorldBlackboard.profile.get("name", ""))
	var date_str := WorldBlackboard.date_text()
	var loc_name := WorldBlackboard.city_label()
	var currency_str := WorldBlackboard.get_currency_display_text()
	var data := {
		"schema_version": SCHEMA_VERSION,
		"saved_at": saved_text,
		"saved_at_unix": unix_now,
		"scene_path": target_scene,
		"meta": {
			"character_name": char_name,
			"name": char_name,
			"age": WorldBlackboard.age(),
			"date_text": date_str,
			"date": date_str,
			"location_name": loc_name,
			"location": loc_name,
			"currency_text": currency_str,
			"chapter_hint": WorldBlackboard.chapter_hint()
		},
		"modules": modules
	}
	if scene != null and scene.scene_file_path == target_scene and scene.has_method("get_save_context"):
		data["scene_context"] = scene.call("get_save_context")
	var destination := _path(slot_id)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
		return false
	var temporary := destination + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var written := file.get_error() == OK
	file.close()
	if not written or DirAccess.rename_absolute(temporary, destination) != OK:
		if FileAccess.file_exists(temporary):
			DirAccess.remove_absolute(temporary)
		return false
	slots_changed.emit()
	return true


func load_slot(slot_id: String) -> bool:
	var data := _read(slot_id)
	if data.is_empty() or not _state_stable():
		return false
	var context: Dictionary = data["scene_context"]
	return SceneTransition.change_to(str(data["scene_path"]), context, _hydrate.bind(data["modules"]))


func restore_slot_state(slot_id: String) -> bool:
	var data := _read(slot_id)
	if data.is_empty() or not _state_stable():
		return false
	_hydrate(data["modules"])
	return true


func delete_slot(slot_id: String) -> bool:
	if slot_id not in SLOTS or not FileAccess.file_exists(_path(slot_id)) or DirAccess.remove_absolute(_path(slot_id)) != OK:
		return false
	slots_changed.emit()
	return true


func remove_slot(id: String) -> bool:
	return delete_slot(id)


func new_game(character_id: String) -> bool:
	var preset: Dictionary = WorldBlackboard.catalog.presets.get(character_id, {})
	if preset.is_empty() or bool(preset.get("locked", false)):
		return false
	var scene := str(preset.get("start", {}).get("scene_path", CABIN))
	return SceneTransition.change_to(scene if scene in [CABIN, ATLAS] else CABIN, {}, _start_new_game.bind(character_id))


func _start_new_game(character_id: String) -> void:
	_hydrate({"world": {"character": {"profile": {"character_id": character_id}}}})


func _hydrate(modules: Dictionary) -> void:
	_restoring = true
	_autosave_pending = false
	_unclaimed_modules = modules.duplicate(true)
	for id: String in _modules:
		var callback: Callable = _modules[id]["deserialize"]
		var entry: Variant = modules.get(id, {})
		if callback.is_valid():
			callback.call(entry.duplicate(true) if entry is Dictionary else {})
			_unclaimed_modules.erase(id)
	_last_day = _day_stamp()
	_restoring = false


func _path(id: String) -> String:
	return directory.path_join(id + ".json")


func _read(id: String) -> Dictionary:
	if id not in SLOTS:
		return {}
	var file := FileAccess.open(_path(id), FileAccess.READ)
	if file == null:
		return {}
	var raw_text := file.get_as_text()
	file.close()
	if raw_text.strip_edges().is_empty():
		return {}
	var parser := JSON.new()
	if parser.parse(raw_text) != OK or not parser.data is Dictionary:
		return {}
	var data: Dictionary = parser.data
	var raw_version: Variant = data.get("schema_version", 0)
	if not (raw_version is int or raw_version is float):
		return {}
	var version := int(raw_version)
	if version < 0 or version > SCHEMA_VERSION:
		return {}
	var modules: Variant = data.get("modules")
	if version == 0 and modules == null:
		if data.get("world") is Dictionary:
			modules = {"world": data["world"]}
		elif data.has("protagonist") or data.has("world_time"):
			modules = {"world": data}
	if not modules is Dictionary or not modules.get("world") is Dictionary:
		return {}
	var world: Dictionary = modules["world"]
	var scene := str(data.get("scene_path", CABIN))
	if scene not in [ATLAS, CABIN]:
		scene = CABIN
	var home_region: String = WorldBlackboard.LEGACY_REGIONS[WorldBlackboard.HOME_CITY]
	if str(world.get("current_city_id", WorldBlackboard.HOME_CITY)) != WorldBlackboard.HOME_CITY or (
		not world.has("current_city_id") and str(world.get("current_location_id", home_region)) != home_region):
		scene = ATLAS
	var raw_meta: Dictionary = data.get("meta", {}) if data.get("meta") is Dictionary else {}
	var meta := _normalize_meta(raw_meta, world)
	var context: Dictionary = data.get("scene_context", {}) if data.get("scene_context") is Dictionary else {}
	var mtime := float(FileAccess.get_modified_time(_path(id)))
	var raw_unix: Variant = data.get("saved_at_unix", null)
	var raw_saved: Variant = data.get("saved_at", null)
	var unix_stamp := mtime
	if raw_unix is float or raw_unix is int:
		unix_stamp = float(raw_unix)
	elif raw_saved is float or raw_saved is int:
		unix_stamp = float(raw_saved)
	var saved_display := ""
	if raw_saved is String and not raw_saved.strip_edges().is_empty():
		saved_display = raw_saved.strip_edges()
	else:
		saved_display = _format_datetime(Time.get_datetime_dict_from_unix_time(int(unix_stamp)))
	return {
		"modules": modules,
		"meta": meta,
		"scene_path": scene,
		"scene_context": context,
		"saved_at": saved_display,
		"saved_at_unix": unix_stamp
	}


func _normalize_meta(raw: Dictionary, world: Dictionary) -> Dictionary:
	var char_data: Dictionary = world.get("character", {}) if world.get("character") is Dictionary else {}
	var prof: Dictionary = char_data.get("profile", {}) if char_data.get("profile") is Dictionary else {}
	var wt: Dictionary = world.get("world_time", {}) if world.get("world_time") is Dictionary else {}
	var char_name := str(raw.get("character_name", raw.get("name", prof.get("name", "旧手账"))))
	var age_val := int(raw.get("age", maxi(0, int(wt.get("year", 418)) - int(prof.get("birth_year", 408)))))
	var date_str := str(raw.get("date_text", raw.get("date", "")))
	var city_id := str(world.get("current_city_id", WorldBlackboard.HOME_CITY))
	var loc_name := str(raw.get("location_name", raw.get("location", WorldBlackboard.catalog.city_names.get(city_id, city_id))))
	var copper := int(world.get("currency_copper", 0))
	var currency_str := str(raw.get("currency_text", WorldBlackboard.format_currency(copper)))
	var chapter := str(raw.get("chapter_hint", "旅途 · " + loc_name if not loc_name.is_empty() else "旅程手账"))
	return {
		"character_name": char_name,
		"name": char_name,
		"age": age_val,
		"date_text": date_str,
		"date": date_str,
		"location_name": loc_name,
		"location": loc_name,
		"currency_text": currency_str,
		"chapter_hint": chapter
	}


func _format_datetime(dt: Dictionary) -> String:
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		int(dt.get("year", 2026)), int(dt.get("month", 1)), int(dt.get("day", 1)),
		int(dt.get("hour", 0)), int(dt.get("minute", 0)), int(dt.get("second", 0))
	]


func _day_stamp() -> int:
	var date := WorldBlackboard.get_world_time()
	return date["year"] * WorldBlackboard.MONTHS_PER_YEAR * WorldBlackboard.DAYS_PER_MONTH + (
		date["month"] - 1) * WorldBlackboard.DAYS_PER_MONTH + date["day"]


func _on_time_changed() -> void:
	var day := _day_stamp()
	if day != _last_day:
		_last_day = day
		_queue_autosave()


func _on_location_changed(_city_id: String) -> void:
	_queue_autosave()


func _queue_autosave() -> void:
	if _restoring or _autosave_pending or WorldBlackboard.is_journey_active():
		return
	_autosave_pending = true
	_flush_autosave.call_deferred()


func _flush_autosave() -> void:
	if not _autosave_pending:
		return
	_autosave_pending = false
	if WorldBlackboard.is_journey_active() or _restoring:
		return
	if not can_save():
		var scene := get_tree().current_scene
		if scene != null and scene.scene_file_path in [CABIN, ATLAS] and (StoryletScheduler.is_busy() or SceneTransition.is_busy()):
			_autosave_pending = true
			get_tree().create_timer(0.15).timeout.connect(_flush_autosave)
		return
	save_slot("auto")
