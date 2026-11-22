extends Node

## Independent system settings & graphics quality tier manager (Track 4).
## Persists to user://settings.cfg via ConfigFile, completely decoupled from game saves.
## Emits granular signals so WorldMap, Dialogue, DiceOverlay, and AudioBusManager can
## subscribe with zero tight coupling.

signal settings_changed(section: String, key: String, value: Variant)
signal graphics_preset_changed(preset: String, profile: Dictionary)
signal settings_loaded()
signal settings_saved(path: String)
signal settings_reset()

const DEFAULT_CONFIG_PATH := "user://settings.cfg"

const SECTION_GRAPHICS := "graphics"
const SECTION_READING := "reading"
const SECTION_AUDIO := "audio"

const PRESET_COLLECTOR := "collector"
const PRESET_BALANCED := "balanced"
const PRESET_BATTERY := "battery"
const VALID_GRAPHICS_PRESETS: Array[String] = [
	PRESET_COLLECTOR,
	PRESET_BALANCED,
	PRESET_BATTERY,
]

const DISPLAY_WINDOWED := "windowed"
const DISPLAY_FULLSCREEN := "fullscreen"
const VALID_DISPLAY_MODES: Array[String] = [
	DISPLAY_WINDOWED,
	DISPLAY_FULLSCREEN,
]

const DICE_SPEED_NORMAL := "normal"
const DICE_SPEED_FAST := "fast"
const VALID_DICE_SPEEDS: Array[String] = [
	DICE_SPEED_NORMAL,
	DICE_SPEED_FAST,
]

const TEXT_SPEED_MIN := 0.5
const TEXT_SPEED_MAX := 2.5
const TEXT_SPEED_INSTANT_THRESHOLD := 2.45
const BASE_CHARS_PER_SEC := 42.0

const AUTO_PLAY_DELAY_MIN := 0.5
const AUTO_PLAY_DELAY_MAX := 6.0

const VOLUME_MIN := 0.0
const VOLUME_MAX := 1.0
const MUTE_LINEAR_THRESHOLD := 0.0001
const MUTE_DB := -80.0

const AUDIO_KEY_TO_BUS: Dictionary[String, StringName] = {
	"vol_master": &"Master",
	"vol_bgm": &"BGM",
	"vol_ambience": &"Ambience",
	"vol_sfx": &"SFX",
	"vol_voice": &"Voice",
}

const BUS_TO_AUDIO_KEY: Dictionary[StringName, String] = {
	&"Master": "vol_master",
	&"BGM": "vol_bgm",
	&"Ambience": "vol_ambience",
	&"SFX": "vol_sfx",
	&"Voice": "vol_voice",
}

const DEFAULTS: Dictionary[String, Dictionary] = {
	"graphics": {
		"graphics_preset": "collector",
		"display_mode": "windowed",
		"vsync_enabled": true,
		"map_weather_particles": true,
	},
	"reading": {
		"text_speed": 1.0,
		"auto_play_delay": 2.0,
		"dice_animation_speed": "normal",
	},
	"audio": {
		"vol_master": 0.85,
		"vol_bgm": 0.70,
		"vol_ambience": 0.65,
		"vol_sfx": 0.80,
		"vol_voice": 0.90,
	},
}

const GRAPHICS_PROFILES: Dictionary[String, Dictionary] = {
	"collector": {
		"preset": "collector",
		"label": "典藏",
		"subtitle": "满血画质 · 精细光影与全量动态粒子",
		"msaa_3d": Viewport.MSAA_4X,
		"msaa_2d": Viewport.MSAA_4X,
		"shadow_atlas_scale": 1.0,
		"directional_shadow_size": 4096,
		"soft_shadow_quality": 3,
		"ssao_enabled": true,
		"ssil_enabled": true,
		"glow_enabled": true,
		"weather_particle_scale": 1.0,
		"render_scale": 1.0,
		"max_fps": 0,
	},
	"balanced": {
		"preset": "balanced",
		"label": "均衡",
		"subtitle": "流畅与质感兼顾 · 推荐日常畅玩",
		"msaa_3d": Viewport.MSAA_2X,
		"msaa_2d": Viewport.MSAA_2X,
		"shadow_atlas_scale": 0.75,
		"directional_shadow_size": 2048,
		"soft_shadow_quality": 2,
		"ssao_enabled": true,
		"ssil_enabled": false,
		"glow_enabled": true,
		"weather_particle_scale": 0.65,
		"render_scale": 1.0,
		"max_fps": 60,
	},
	"battery": {
		"preset": "battery",
		"label": "省电",
		"subtitle": "移动端护航 · 低温顺滑长续航",
		"msaa_3d": Viewport.MSAA_DISABLED,
		"msaa_2d": Viewport.MSAA_DISABLED,
		"shadow_atlas_scale": 0.5,
		"directional_shadow_size": 1024,
		"soft_shadow_quality": 1,
		"ssao_enabled": false,
		"ssil_enabled": false,
		"glow_enabled": false,
		"weather_particle_scale": 0.25,
		"render_scale": 0.85,
		"max_fps": 45,
	},
}

var config_path: String = DEFAULT_CONFIG_PATH
var auto_load_on_ready: bool = true
var mobile_override: int = -1  # -1 = auto-detect, 0 = force desktop, 1 = force mobile

var _values: Dictionary[String, Dictionary] = {}
var _loaded := false


func _init() -> void:
	_init_default_values()


func _ready() -> void:
	if auto_load_on_ready and not _loaded:
		load_settings(config_path)
		apply_display_settings()
		apply_audio_settings(_find_audio_manager())


func _init_default_values() -> void:
	_values.clear()
	for section: String in DEFAULTS.keys():
		_values[section] = DEFAULTS[section].duplicate(true)


func set_config_path(path: String) -> void:
	if not path.is_empty():
		config_path = path


func get_config_path() -> String:
	return config_path


func is_mobile_platform() -> bool:
	if mobile_override == 0:
		return false
	if mobile_override == 1:
		return true
	return OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile")


## Loads settings from disk ConfigFile. Missing or invalid values safely fall back to defaults.
func load_settings(path: String = "") -> Error:
	var target_path := config_path if path.is_empty() else path
	config_path = target_path
	_init_default_values()
	_loaded = true

	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(target_path):
		settings_loaded.emit()
		return ERR_FILE_NOT_FOUND

	var raw_text := FileAccess.get_file_as_string(target_path)
	if not _looks_like_valid_cfg(raw_text):
		settings_loaded.emit()
		return ERR_PARSE_ERROR

	var err := cfg.parse(raw_text)
	if err != OK:
		settings_loaded.emit()
		return err

	for section: String in DEFAULTS.keys():
		var section_defaults: Dictionary = DEFAULTS[section]
		for key: String in section_defaults.keys():
			if not cfg.has_section_key(section, key):
				continue
			var raw_value: Variant = cfg.get_value(section, key, section_defaults[key])
			_values[section][key] = _sanitize_value(section, key, raw_value, true)

	settings_loaded.emit()
	return OK


## Saves current settings to disk via ConfigFile.
func save_settings(path: String = "") -> Error:
	var target_path := config_path if path.is_empty() else path
	config_path = target_path
	var cfg := ConfigFile.new()
	for section: String in DEFAULTS.keys():
		var section_data: Dictionary = _values.get(section, DEFAULTS[section])
		for key: String in DEFAULTS[section].keys():
			cfg.set_value(section, key, section_data.get(key, DEFAULTS[section][key]))
	var err := cfg.save(target_path)
	if err == OK:
		settings_saved.emit(target_path)
	return err


func get_setting(section: String, key: String, fallback: Variant = null) -> Variant:
	if _values.has(section):
		var section_dict: Dictionary = _values[section]
		if section_dict.has(key):
			return section_dict[key]
	if DEFAULTS.has(section) and DEFAULTS[section].has(key):
		return DEFAULTS[section][key]
	return fallback


## Updates a single setting, emits signals when changed, and optionally persists immediately.
## Returns false if section/key is unknown or value type/enum is invalid.
func set_setting(section: String, key: String, value: Variant, auto_save: bool = false) -> bool:
	if not DEFAULTS.has(section) or not DEFAULTS[section].has(key):
		return false
	if not _is_valid_runtime_input(section, key, value):
		return false

	var sanitized: Variant = _sanitize_value(section, key, value, false)
	var previous: Variant = _values[section][key]
	var changed := not _values_equal(previous, sanitized)
	_values[section][key] = sanitized

	if changed:
		settings_changed.emit(section, key, sanitized)
		if section == SECTION_GRAPHICS and key == "graphics_preset":
			var preset_name := str(sanitized)
			graphics_preset_changed.emit(preset_name, get_graphics_profile(preset_name))

	if auto_save:
		save_settings()
	return true


func get_section(section: String) -> Dictionary:
	if not _values.has(section):
		return {}
	return _values[section].duplicate(true)


func get_all_settings() -> Dictionary:
	var snapshot: Dictionary = {}
	for section: String in DEFAULTS.keys():
		snapshot[section] = get_section(section)
	return snapshot


func get_defaults() -> Dictionary:
	var snapshot: Dictionary = {}
	for section: String in DEFAULTS.keys():
		snapshot[section] = DEFAULTS[section].duplicate(true)
	return snapshot


## Returns recommended rendering parameters for the requested preset (or current preset if empty).
## Unknown preset names safely fall back to the default "collector" profile.
func get_graphics_profile(preset: String = "") -> Dictionary:
	var resolved := get_graphics_preset() if preset.is_empty() else preset
	if not GRAPHICS_PROFILES.has(resolved):
		resolved = PRESET_COLLECTOR
	return GRAPHICS_PROFILES[resolved].duplicate(true)


func get_graphics_preset() -> String:
	return str(get_setting(SECTION_GRAPHICS, "graphics_preset", PRESET_COLLECTOR))


func set_graphics_preset(preset: String, auto_save: bool = false) -> bool:
	return set_setting(SECTION_GRAPHICS, "graphics_preset", preset, auto_save)


func get_display_mode() -> String:
	return str(get_setting(SECTION_GRAPHICS, "display_mode", DISPLAY_WINDOWED))


func is_vsync_enabled() -> bool:
	return bool(get_setting(SECTION_GRAPHICS, "vsync_enabled", true))


func is_map_weather_particles_enabled() -> bool:
	return bool(get_setting(SECTION_GRAPHICS, "map_weather_particles", true))


func get_text_speed() -> float:
	return float(get_setting(SECTION_READING, "text_speed", 1.0))


func get_text_speed_chars_per_sec() -> float:
	return BASE_CHARS_PER_SEC * get_text_speed()


func is_instant_text_enabled() -> bool:
	return get_text_speed() >= TEXT_SPEED_INSTANT_THRESHOLD


func get_auto_play_delay() -> float:
	return float(get_setting(SECTION_READING, "auto_play_delay", 2.0))


func get_dice_animation_speed() -> String:
	return str(get_setting(SECTION_READING, "dice_animation_speed", DICE_SPEED_NORMAL))


func get_dice_time_scale() -> float:
	return 1.8 if get_dice_animation_speed() == DICE_SPEED_FAST else 1.0


func get_bus_volume(bus_name: StringName) -> float:
	if not BUS_TO_AUDIO_KEY.has(bus_name):
		return 1.0
	var key := BUS_TO_AUDIO_KEY[bus_name]
	return float(get_setting(SECTION_AUDIO, key, 1.0))


func set_bus_volume(bus_name: StringName, linear_volume: float, auto_save: bool = false) -> bool:
	if not BUS_TO_AUDIO_KEY.has(bus_name):
		return false
	var key := BUS_TO_AUDIO_KEY[bus_name]
	return set_setting(SECTION_AUDIO, key, linear_volume, auto_save)


## Applies all 5 audio slider values to the supplied audio manager (or AudioServer directly).
## Guarantees Master and Ambience are also applied on AudioServer even if paired with
## a legacy audio node that only handles BGM/SFX/Voice.
func apply_audio_settings(audio_mgr: Node = null) -> void:
	var has_bus_setter := audio_mgr != null and audio_mgr.has_method("set_bus_volume")
	for key: String in AUDIO_KEY_TO_BUS.keys():
		var bus_name: StringName = AUDIO_KEY_TO_BUS[key]
		var linear := clampf(float(get_setting(SECTION_AUDIO, key, 1.0)), VOLUME_MIN, VOLUME_MAX)
		if has_bus_setter:
			audio_mgr.call("set_bus_volume", bus_name, linear)
		_apply_bus_volume_direct_if_needed(bus_name, linear)


func _apply_bus_volume_direct_if_needed(bus_name: StringName, linear: float) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		return
	var should_mute := linear <= MUTE_LINEAR_THRESHOLD
	var target_db := MUTE_DB if should_mute else linear_to_db(linear)
	if AudioServer.is_bus_mute(bus_idx) != should_mute:
		AudioServer.set_bus_mute(bus_idx, should_mute)
	if not is_equal_approx(AudioServer.get_bus_volume_db(bus_idx), target_db):
		AudioServer.set_bus_volume_db(bus_idx, target_db)


## Applies window mode and VSync safely (skips window mode on mobile and DisplayServer calls in headless).
func apply_display_settings() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var vsync_mode := DisplayServer.VSYNC_ENABLED if is_vsync_enabled() else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(vsync_mode)
	if not is_mobile_platform():
		var want_fullscreen := get_display_mode() == DISPLAY_FULLSCREEN
		var target_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if want_fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != target_mode:
			DisplayServer.window_set_mode(target_mode)


## Applies MSAA & render scale from the active graphics profile onto a Viewport.
func apply_graphics_to_viewport(viewport: Viewport = null) -> void:
	var target := viewport if viewport != null else (get_viewport() if is_inside_tree() else null)
	if target == null:
		return
	var profile := get_graphics_profile()
	target.msaa_3d = int(profile.get("msaa_3d", Viewport.MSAA_4X)) as Viewport.MSAA
	target.msaa_2d = int(profile.get("msaa_2d", Viewport.MSAA_4X)) as Viewport.MSAA
	var render_scale := clampf(float(profile.get("render_scale", 1.0)), 0.5, 1.0)
	target.scaling_3d_scale = render_scale


func apply_all(audio_mgr: Node = null) -> void:
	apply_display_settings()
	apply_graphics_to_viewport()
	apply_audio_settings(audio_mgr)


## Resets every setting back to its canonical default, emits change signals, and optionally saves.
func reset_to_defaults(auto_save: bool = true) -> void:
	var previous_preset := get_graphics_preset()
	var changed_entries: Array[Dictionary] = []

	for section: String in DEFAULTS.keys():
		var section_defaults: Dictionary = DEFAULTS[section]
		for key: String in section_defaults.keys():
			var default_val: Variant = section_defaults[key]
			var old_val: Variant = _values[section][key]
			_values[section][key] = default_val
			if not _values_equal(old_val, default_val):
				changed_entries.append({
					"section": section,
					"key": key,
					"value": default_val,
				})

	for entry: Dictionary in changed_entries:
		settings_changed.emit(str(entry["section"]), str(entry["key"]), entry["value"])

	var current_preset := get_graphics_preset()
	if previous_preset != current_preset:
		graphics_preset_changed.emit(current_preset, get_graphics_profile(current_preset))

	apply_display_settings()
	settings_reset.emit()

	if auto_save:
		save_settings()


func _find_audio_manager() -> Node:
	if not is_inside_tree():
		return null
	var root := get_tree().root
	if root == null:
		return null
	var candidate := root.get_node_or_null("AudioBusManager")
	if candidate != null:
		return candidate
	return root.get_node_or_null("AudioManager")


func _is_valid_runtime_input(section: String, key: String, value: Variant) -> bool:
	match section:
		SECTION_GRAPHICS:
			match key:
				"graphics_preset":
					return value is String and VALID_GRAPHICS_PRESETS.has(String(value))
				"display_mode":
					return value is String and VALID_DISPLAY_MODES.has(String(value))
				"vsync_enabled", "map_weather_particles":
					return value is bool
		SECTION_READING:
			match key:
				"text_speed", "auto_play_delay":
					if not (value is float or value is int):
						return false
					var num := float(value)
					return not is_nan(num) and not is_inf(num)
				"dice_animation_speed":
					return value is String and VALID_DICE_SPEEDS.has(String(value))
		SECTION_AUDIO:
			if AUDIO_KEY_TO_BUS.has(key):
				if not (value is float or value is int):
					return false
				var num := float(value)
				return not is_nan(num) and not is_inf(num)
	return false


## Sanitizes loaded or runtime values.
## When strict_range is true (ConfigFile load), out-of-range numeric values fall back to defaults
## instead of clamping so corrupted config files cleanly recover.
func _sanitize_value(section: String, key: String, raw: Variant, strict_range: bool) -> Variant:
	var default_val: Variant = DEFAULTS[section][key]
	match section:
		SECTION_GRAPHICS:
			match key:
				"graphics_preset":
					if raw is String and VALID_GRAPHICS_PRESETS.has(String(raw)):
						return String(raw)
					return default_val
				"display_mode":
					if raw is String and VALID_DISPLAY_MODES.has(String(raw)):
						return String(raw)
					return default_val
				"vsync_enabled", "map_weather_particles":
					if raw is bool:
						return bool(raw)
					return default_val
		SECTION_READING:
			match key:
				"text_speed":
					return _sanitize_float(raw, TEXT_SPEED_MIN, TEXT_SPEED_MAX, float(default_val), strict_range)
				"auto_play_delay":
					return _sanitize_float(raw, AUTO_PLAY_DELAY_MIN, AUTO_PLAY_DELAY_MAX, float(default_val), strict_range)
				"dice_animation_speed":
					if raw is String and VALID_DICE_SPEEDS.has(String(raw)):
						return String(raw)
					return default_val
		SECTION_AUDIO:
			if AUDIO_KEY_TO_BUS.has(key):
				return _sanitize_float(raw, VOLUME_MIN, VOLUME_MAX, float(default_val), strict_range)
	return default_val


func _sanitize_float(raw: Variant, min_val: float, max_val: float, default_val: float, strict_range: bool) -> float:
	if not (raw is float or raw is int):
		return default_val
	var num := float(raw)
	if is_nan(num) or is_inf(num):
		return default_val
	if strict_range and (num < min_val or num > max_val):
		return default_val
	return clampf(num, min_val, max_val)


func _values_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is float and b is float:
		return is_equal_approx(float(a), float(b))
	return a == b


func _looks_like_valid_cfg(raw_text: String) -> bool:
	var lines := raw_text.split("\n")
	for raw_line: String in lines:
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with(";") or line.begins_with("#"):
			continue
		if line.begins_with("["):
			if not line.ends_with("]") or line.length() <= 2:
				return false
			var inner := line.substr(1, line.length() - 2)
			if inner.contains("[") or inner.contains("]") or inner.contains("="):
				return false
			continue
		if not line.contains("="):
			return false
	return true
