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
	return scene != null and scene.scene_file_path in [CABIN, ATLAS] and not SceneTransition.is_busy() and (
		not _restoring and not WorldBlackboard.is_journey_active() and not StoryletScheduler.is_busy())


func slot_info(id: String) -> Dictionary:
	var data := _read(id)
	if data.is_empty():
		return {"status": "invalid" if id in SLOTS and FileAccess.file_exists(_path(id)) else "empty"}
	var result: Dictionary = data["meta"].duplicate(true)
	result["status"] = "ready"
	result["saved_at"] = data["saved_at"]
	return result


func latest_slot() -> String:
	var newest := ""
	var latest_time := -1.0
	for id: String in SLOTS:
		var data := _read(id)
		if data.is_empty():
			continue
		var timestamp := float(data["saved_at"])
		if timestamp >= latest_time:
			newest = id
			latest_time = timestamp
	return newest


func save_slot(id: String) -> bool:
	if id not in SLOTS or not can_save():
		return false
	var scene := get_tree().current_scene
	var modules := _unclaimed_modules.duplicate(true)
	for module_id: String in _modules:
		var callback: Callable = _modules[module_id]["serialize"]
		if callback.is_valid():
			var state: Variant = callback.call()
			if not state is Dictionary:
				return false
			modules[module_id] = state
	var data := {
		"schema_version": SCHEMA_VERSION, "saved_at": Time.get_unix_time_from_system(),
		"meta": {"name": str(WorldBlackboard.profile.get("name", "")), "date": WorldBlackboard.date_text(),
			"location": WorldBlackboard.city_label()},
		"scene_path": scene.scene_file_path, "modules": modules
	}
	if scene.has_method("get_save_context"):
		data["scene_context"] = scene.call("get_save_context")
	var destination := _path(id)
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


func load_slot(id: String) -> bool:
	var data := _read(id)
	if data.is_empty() or WorldBlackboard.is_journey_active() or StoryletScheduler.is_busy():
		return false
	var context: Dictionary = data["scene_context"]
	return SceneTransition.change_to(str(data["scene_path"]), context, _hydrate.bind(data["modules"]))


func remove_slot(id: String) -> bool:
	if id not in SLOTS or not FileAccess.file_exists(_path(id)) or DirAccess.remove_absolute(_path(id)) != OK:
		return false
	slots_changed.emit()
	return true


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
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
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
	var meta: Dictionary = data.get("meta", {}) if data.get("meta") is Dictionary else {}
	var context: Dictionary = data.get("scene_context", {}) if data.get("scene_context") is Dictionary else {}
	var saved: Variant = data.get("saved_at", FileAccess.get_modified_time(_path(id)))
	var timestamp := float(saved) if saved is float or saved is int else float(FileAccess.get_modified_time(_path(id)))
	return {"modules": modules, "meta": meta, "scene_path": scene, "scene_context": context, "saved_at": timestamp}


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
