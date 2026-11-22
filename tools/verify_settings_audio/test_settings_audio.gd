extends SceneTree

## Headless automated verification suite for Track 4:
## SettingsManager + AudioBusManager + game_bus_layout.tres + SettingsOverlay / settings_preview.tscn

const SettingsManagerScript := preload("res://core/settings_manager.gd")
const AudioBusManagerScript := preload("res://resources/audio/audio_bus_manager.gd")
const SETTINGS_PREVIEW_PATH := "res://scenes/ui/settings/settings_preview.tscn"

const TMP_CFG_PATH := "user://track4_verify_settings.cfg"
const CORRUPT_CFG_PATH := "user://track4_verify_corrupt.cfg"

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_run_all.call_deferred()


func _run_all() -> void:
	print("=== Track 4 Headless Verification Suite (Godot %s) ===" % Engine.get_version_info().get("string", ""))

	await _test_settings_defaults_and_roundtrip()
	await _test_settings_illegal_fallback_and_corrupt()
	await _test_settings_reset_and_runtime_validation()
	await _test_graphics_presets_and_signals()
	await _test_audio_bus_layout_and_fallback()
	await _test_audio_volume_db_and_settings_sync()
	await _test_audio_bgm_crossfade_and_muffle()
	await _test_audio_ambience_and_sfx_pool()
	await _test_audio_voice_ducking_lifecycle()
	await _test_audio_null_and_missing_safe()
	await _test_settings_preview_scene_and_ui_flow()

	_cleanup_temp_files()
	var total := _passed + _failed
	print("=== Track 4 Verification Summary: %d/%d PASS (%d FAIL) ===" % [_passed, total, _failed])
	quit(0 if _failed == 0 else 1)


func _check(condition: bool, test_id: String, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s%s" % [test_id, (" - " + detail) if not detail.is_empty() else ""])
	else:
		_failed += 1
		push_error("[FAIL] %s%s" % [test_id, (" - " + detail) if not detail.is_empty() else ""])
		print("[FAIL] %s%s" % [test_id, (" - " + detail) if not detail.is_empty() else ""])


func _make_settings_mgr() -> Node:
	var mgr := SettingsManagerScript.new()
	mgr.set("auto_load_on_ready", false)
	mgr.call("set_config_path", TMP_CFG_PATH)
	root.add_child(mgr)
	return mgr


func _make_audio_mgr() -> Node:
	var mgr := AudioBusManagerScript.new()
	root.add_child(mgr)
	return mgr


func _make_dummy_wav(duration_sec: float = 0.8, freq_hz: float = 440.0) -> AudioStreamWAV:
	var rate := 16000
	var frames := maxi(16, ceili(duration_sec * float(rate)))
	var pcm := PackedByteArray()
	pcm.resize(frames * 2)
	for i: int in range(frames):
		var sample := sin(TAU * freq_hz * float(i) / float(rate)) * 0.2
		pcm.encode_s16(i * 2, roundi(clampf(sample, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = pcm
	return wav


func _wait_seconds(sec: float) -> void:
	await create_timer(sec).timeout


func _cleanup_temp_files() -> void:
	for p: String in [TMP_CFG_PATH, CORRUPT_CFG_PATH]:
		var abs_path := ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(abs_path)


func _test_settings_defaults_and_roundtrip() -> void:
	_cleanup_temp_files()
	var mgr := _make_settings_mgr()

	var defaults_ok := (
		str(mgr.call("get_graphics_preset")) == "collector"
		and str(mgr.call("get_display_mode")) == "windowed"
		and bool(mgr.call("is_vsync_enabled")) == true
		and bool(mgr.call("is_map_weather_particles_enabled")) == true
		and is_equal_approx(float(mgr.call("get_text_speed")), 1.0)
		and is_equal_approx(float(mgr.call("get_auto_play_delay")), 2.0)
		and str(mgr.call("get_dice_animation_speed")) == "normal"
		and is_equal_approx(float(mgr.call("get_setting", "audio", "vol_master")), 0.85)
		and is_equal_approx(float(mgr.call("get_setting", "audio", "vol_bgm")), 0.70)
		and is_equal_approx(float(mgr.call("get_setting", "audio", "vol_ambience")), 0.65)
		and is_equal_approx(float(mgr.call("get_setting", "audio", "vol_sfx")), 0.80)
		and is_equal_approx(float(mgr.call("get_setting", "audio", "vol_voice")), 0.90)
	)
	_check(defaults_ok, "T01_defaults_complete", "All 12 default keys verified")

	# Mutate every setting and verify persistence roundtrip
	mgr.call("set_setting", "graphics", "graphics_preset", "battery")
	mgr.call("set_setting", "graphics", "display_mode", "fullscreen")
	mgr.call("set_setting", "graphics", "vsync_enabled", false)
	mgr.call("set_setting", "graphics", "map_weather_particles", false)
	mgr.call("set_setting", "reading", "text_speed", 2.5)
	mgr.call("set_setting", "reading", "auto_play_delay", 3.7)
	mgr.call("set_setting", "reading", "dice_animation_speed", "fast")
	mgr.call("set_setting", "audio", "vol_master", 0.55)
	mgr.call("set_setting", "audio", "vol_bgm", 0.30)
	mgr.call("set_setting", "audio", "vol_ambience", 0.45)
	mgr.call("set_setting", "audio", "vol_sfx", 0.95)
	mgr.call("set_setting", "audio", "vol_voice", 0.0)
	var save_err := int(mgr.call("save_settings", TMP_CFG_PATH))

	var mgr2 := _make_settings_mgr()
	var load_err := int(mgr2.call("load_settings", TMP_CFG_PATH))
	var roundtrip_ok := (
		save_err == OK
		and load_err == OK
		and str(mgr2.call("get_graphics_preset")) == "battery"
		and str(mgr2.call("get_display_mode")) == "fullscreen"
		and bool(mgr2.call("is_vsync_enabled")) == false
		and bool(mgr2.call("is_map_weather_particles_enabled")) == false
		and is_equal_approx(float(mgr2.call("get_text_speed")), 2.5)
		and bool(mgr2.call("is_instant_text_enabled")) == true
		and is_equal_approx(float(mgr2.call("get_auto_play_delay")), 3.7)
		and str(mgr2.call("get_dice_animation_speed")) == "fast"
		and is_equal_approx(float(mgr2.call("get_dice_time_scale")), 1.8)
		and is_equal_approx(float(mgr2.call("get_setting", "audio", "vol_master")), 0.55)
		and is_equal_approx(float(mgr2.call("get_setting", "audio", "vol_bgm")), 0.30)
		and is_equal_approx(float(mgr2.call("get_setting", "audio", "vol_ambience")), 0.45)
		and is_equal_approx(float(mgr2.call("get_setting", "audio", "vol_sfx")), 0.95)
		and is_equal_approx(float(mgr2.call("get_setting", "audio", "vol_voice")), 0.0)
	)
	_check(roundtrip_ok, "T02_config_roundtrip", "ConfigFile save & reload identical across all 12 keys")

	mgr.queue_free()
	mgr2.queue_free()
	await process_frame


func _test_settings_illegal_fallback_and_corrupt() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "graphics_preset", "ultra_illegal_tier")
	cfg.set_value("graphics", "display_mode", "hologram")
	cfg.set_value("graphics", "vsync_enabled", "not_a_bool")
	cfg.set_value("graphics", "map_weather_particles", 42)
	cfg.set_value("reading", "text_speed", 99.9)
	cfg.set_value("reading", "auto_play_delay", -10.0)
	cfg.set_value("reading", "dice_animation_speed", "warp_speed")
	cfg.set_value("audio", "vol_master", "loud_string")
	cfg.set_value("audio", "vol_bgm", -5.0)
	cfg.set_value("audio", "vol_ambience", 0.42)  # Valid value should survive!
	cfg.set_value("audio", "vol_sfx", 3.5)
	cfg.set_value("audio", "vol_voice", NAN)
	cfg.save(TMP_CFG_PATH)

	var mgr := _make_settings_mgr()
	var err := int(mgr.call("load_settings", TMP_CFG_PATH))
	var fallback_ok := (
		err == OK
		and str(mgr.call("get_graphics_preset")) == "collector"
		and str(mgr.call("get_display_mode")) == "windowed"
		and bool(mgr.call("is_vsync_enabled")) == true
		and bool(mgr.call("is_map_weather_particles_enabled")) == true
		and is_equal_approx(float(mgr.call("get_text_speed")), 1.0)
		and is_equal_approx(float(mgr.call("get_auto_play_delay")), 2.0)
		and str(mgr.call("get_dice_animation_speed")) == "normal"
		and is_equal_approx(float(mgr.call("get_setting", "audio", "vol_master")), 0.85)
		and is_equal_approx(float(mgr.call("get_setting", "audio", "vol_bgm")), 0.70)
		and is_equal_approx(float(mgr.call("get_setting", "audio", "vol_ambience")), 0.42)
		and is_equal_approx(float(mgr.call("get_setting", "audio", "vol_sfx")), 0.80)
		and is_equal_approx(float(mgr.call("get_setting", "audio", "vol_voice")), 0.90)
	)
	_check(fallback_ok, "T03_illegal_values_fallback", "All illegal/out-of-range values safely reverted to defaults; valid entry kept")

	# Corrupt file syntax test
	var f := FileAccess.open(CORRUPT_CFG_PATH, FileAccess.WRITE)
	f.store_string("[[[broken_ini===\nnot_valid_config_syntax")
	f.close()
	var corrupt_err := int(mgr.call("load_settings", CORRUPT_CFG_PATH))
	var corrupt_ok := corrupt_err != OK and str(mgr.call("get_graphics_preset")) == "collector"
	_check(corrupt_ok, "T04_corrupt_cfg_graceful", "Syntax-corrupt cfg handled safely with defaults intact")

	mgr.queue_free()
	await process_frame


func _test_settings_reset_and_runtime_validation() -> void:
	var mgr := _make_settings_mgr()
	var changed_events: Array[Dictionary] = []
	var reset_count := [0]
	mgr.connect("settings_changed", func(section: String, key: String, val: Variant) -> void:
		changed_events.append({"section": section, "key": key, "value": val})
	)
	mgr.connect("settings_reset", func() -> void:
		reset_count[0] = int(reset_count[0]) + 1
	)

	mgr.call("set_graphics_preset", "balanced")
	mgr.call("set_setting", "audio", "vol_sfx", 0.25)
	mgr.call("set_setting", "reading", "dice_animation_speed", "fast")
	changed_events.clear()

	mgr.call("reset_to_defaults", true)
	var reset_ok := (
		int(reset_count[0]) == 1
		and changed_events.size() == 3
		and str(mgr.call("get_graphics_preset")) == "collector"
		and is_equal_approx(float(mgr.call("get_setting", "audio", "vol_sfx")), 0.80)
		and str(mgr.call("get_dice_animation_speed")) == "normal"
	)
	_check(reset_ok, "T05_reset_to_defaults", "reset_to_defaults restored all keys & emitted signals")

	var reject_unknown := not bool(mgr.call("set_setting", "ghost_section", "foo", 1))
	var reject_bad_enum := not bool(mgr.call("set_graphics_preset", "nonexistent_tier"))
	var reject_nan := not bool(mgr.call("set_setting", "audio", "vol_bgm", NAN))
	var clamp_high := bool(mgr.call("set_setting", "audio", "vol_bgm", 1.75)) and is_equal_approx(float(mgr.call("get_setting", "audio", "vol_bgm")), 1.0)
	var clamp_low := bool(mgr.call("set_setting", "reading", "text_speed", 0.05)) and is_equal_approx(float(mgr.call("get_text_speed")), 0.5)
	_check(
		reject_unknown and reject_bad_enum and reject_nan and clamp_high and clamp_low,
		"T06_runtime_set_validation",
		"Invalid keys/enums/NaN rejected; valid numeric edges clamped safely"
	)

	mgr.queue_free()
	await process_frame


func _test_graphics_presets_and_signals() -> void:
	var mgr := _make_settings_mgr()
	var p_col: Dictionary = mgr.call("get_graphics_profile", "collector")
	var p_bal: Dictionary = mgr.call("get_graphics_profile", "balanced")
	var p_bat: Dictionary = mgr.call("get_graphics_profile", "battery")
	var p_fb: Dictionary = mgr.call("get_graphics_profile", "does_not_exist")

	var required_keys: Array[String] = [
		"preset", "label", "msaa_3d", "msaa_2d", "shadow_atlas_scale",
		"directional_shadow_size", "soft_shadow_quality", "ssao_enabled",
		"ssil_enabled", "weather_particle_scale", "render_scale",
	]
	var keys_ok := true
	for prof: Dictionary in [p_col, p_bal, p_bat]:
		for k: String in required_keys:
			if not prof.has(k):
				keys_ok = false
	var ordering_ok := (
		int(p_col["msaa_3d"]) > int(p_bal["msaa_3d"])
		and int(p_bal["msaa_3d"]) > int(p_bat["msaa_3d"])
		and float(p_col["shadow_atlas_scale"]) > float(p_bal["shadow_atlas_scale"])
		and float(p_bal["shadow_atlas_scale"]) > float(p_bat["shadow_atlas_scale"])
		and float(p_col["weather_particle_scale"]) > float(p_bal["weather_particle_scale"])
		and float(p_bal["weather_particle_scale"]) > float(p_bat["weather_particle_scale"])
		and bool(p_col["ssil_enabled"]) == true
		and bool(p_bal["ssil_enabled"]) == false
		and bool(p_bat["ssao_enabled"]) == false
		and str(p_fb["preset"]) == "collector"
	)
	_check(keys_ok and ordering_ok, "T07_graphics_profiles_valid", "collector > balanced > battery profiles complete & fallback safe")

	var signal_log: Array[String] = []
	mgr.connect("graphics_preset_changed", func(preset: String, profile: Dictionary) -> void:
		if str(profile.get("preset", "")) == preset:
			signal_log.append(preset)
	)
	mgr.call("set_graphics_preset", "balanced")
	mgr.call("set_graphics_preset", "balanced")  # duplicate should not re-emit
	mgr.call("set_graphics_preset", "battery")
	mgr.call("set_graphics_preset", "collector")
	_check(
		signal_log == ["balanced", "battery", "collector"],
		"T08_graphics_preset_signal",
		"graphics_preset_changed emitted exact sequence %s" % str(signal_log)
	)

	mgr.queue_free()
	await process_frame


func _test_audio_bus_layout_and_fallback() -> void:
	var audio := _make_audio_mgr()
	var loaded := bool(audio.call("ensure_bus_layout", true))
	var has_all := bool(audio.call("has_all_required_buses"))
	var bgm_idx := AudioServer.get_bus_index(&"BGM")
	var lp_idx := int(audio.call("get_bgm_lowpass_effect_index"))
	var lp_ok := bgm_idx >= 0 and lp_idx >= 0 and (AudioServer.get_bus_effect(bgm_idx, lp_idx) is AudioEffectLowPassFilter) and not AudioServer.is_bus_effect_enabled(bgm_idx, lp_idx)
	_check(loaded and has_all and lp_ok, "T09_bus_layout_resource_load", "game_bus_layout.tres loaded with 5 buses + BGM LowPassFilter slot")

	# Test fallback auto-creation on a bare Master-only AudioBusLayout
	AudioServer.set_bus_layout(AudioBusLayout.new())
	var bare_count := AudioServer.bus_count
	audio.call("ensure_bus_layout", false)
	var recovered_all := bool(audio.call("has_all_required_buses"))
	var recovered_lp := int(audio.call("get_bgm_lowpass_effect_index")) >= 0
	# Restore canonical layout resource afterwards
	audio.call("ensure_bus_layout", true)
	_check(bare_count == 1 and recovered_all and recovered_lp, "T10_bus_fallback_auto_create", "Fallback auto-created BGM/Ambience/SFX/Voice + BGM LowPassFilter")

	audio.queue_free()
	await process_frame


func _test_audio_volume_db_and_settings_sync() -> void:
	var audio := _make_audio_mgr()
	var settings := _make_settings_mgr()

	var db_full := float(AudioBusManagerScript.linear_volume_to_db(1.0))
	var db_half := float(AudioBusManagerScript.linear_volume_to_db(0.5))
	var db_zero := float(AudioBusManagerScript.linear_volume_to_db(0.0))
	var curve_ok := (
		is_equal_approx(db_full, 0.0)
		and absf(db_half - linear_to_db(0.5)) < 0.01
		and is_equal_approx(db_zero, -80.0)
	)

	settings.call("set_setting", "audio", "vol_master", 0.90)
	settings.call("set_setting", "audio", "vol_bgm", 0.0)
	settings.call("set_setting", "audio", "vol_ambience", 0.50)
	settings.call("set_setting", "audio", "vol_sfx", 0.75)
	settings.call("set_setting", "audio", "vol_voice", 1.0)
	settings.call("apply_audio_settings", audio)

	var sync_ok := (
		not bool(audio.call("is_bus_muted", &"Master"))
		and absf(float(audio.call("get_bus_volume_db", &"Master")) - linear_to_db(0.90)) < 0.05
		and bool(audio.call("is_bus_muted", &"BGM"))
		and absf(float(audio.call("get_bus_volume_db", &"Ambience")) - linear_to_db(0.50)) < 0.05
		and absf(float(audio.call("get_bus_volume_db", &"SFX")) - linear_to_db(0.75)) < 0.05
		and absf(float(audio.call("get_bus_volume_db", &"Voice")) - 0.0) < 0.05
	)
	_check(curve_ok and sync_ok, "T11_volume_db_and_settings_sync", "5-bus dB mapping, 0.0 mute & SettingsManager sync verified")

	settings.queue_free()
	audio.queue_free()
	await process_frame


func _test_audio_bgm_crossfade_and_muffle() -> void:
	var audio := _make_audio_mgr()
	var bgm_a := _make_dummy_wav(1.5, 220.0)
	var bgm_b := _make_dummy_wav(1.5, 330.0)
	var bgm_events: Array[AudioStream] = []
	audio.connect("bgm_changed", func(stream: AudioStream) -> void: bgm_events.append(stream))

	var ok_a := bool(audio.call("play_bgm", bgm_a, 0.05))
	var slot_a := int(audio.call("get_active_bgm_slot"))
	await _wait_seconds(0.08)
	var playing_a := bool(audio.call("is_bgm_playing"))

	var ok_b := bool(audio.call("play_bgm", bgm_b, 0.06))
	var slot_b := int(audio.call("get_active_bgm_slot"))
	await _wait_seconds(0.10)
	var current_bgm := audio.call("get_current_bgm") as AudioStream
	var switched_ok := ok_a and ok_b and playing_a and slot_a != slot_b and current_bgm == bgm_b

	# Test BGM low-pass modal muffle
	var bgm_idx := AudioServer.get_bus_index(&"BGM")
	var lp_idx := int(audio.call("get_bgm_lowpass_effect_index"))
	audio.call("set_bgm_muffled", true, 0.05)
	await _wait_seconds(0.08)
	var muffled_on := bool(audio.call("is_bgm_muffled")) and AudioServer.is_bus_effect_enabled(bgm_idx, lp_idx)
	var filter := AudioServer.get_bus_effect(bgm_idx, lp_idx) as AudioEffectLowPassFilter
	var cutoff_dropped := filter != null and filter.cutoff_hz < 2000.0
	audio.call("set_bgm_muffled", false, 0.05)
	await _wait_seconds(0.09)
	var muffled_off := not bool(audio.call("is_bgm_muffled")) and not AudioServer.is_bus_effect_enabled(bgm_idx, lp_idx)

	audio.call("stop_bgm", 0.05)
	await _wait_seconds(0.09)
	var bgm_after_stop := audio.call("get_current_bgm") as AudioStream
	var stopped_ok := not bool(audio.call("is_bgm_playing")) and bgm_after_stop == null
	_check(
		switched_ok and muffled_on and cutoff_dropped and muffled_off and stopped_ok and bgm_events.size() == 3,
		"T12_bgm_crossfade_and_muffle",
		"Dual-channel crossfade, low-pass muffle toggle & smooth stop verified"
	)

	audio.queue_free()
	await process_frame


func _test_audio_ambience_and_sfx_pool() -> void:
	var audio := _make_audio_mgr()
	var amb_a := _make_dummy_wav(1.2, 180.0)
	var amb_b := _make_dummy_wav(1.2, 260.0)
	var sfx_wav := _make_dummy_wav(0.25, 660.0)

	var amb_ok := bool(audio.call("play_ambience", amb_a, 0.04))
	await _wait_seconds(0.06)
	amb_ok = amb_ok and bool(audio.call("is_ambience_playing")) and bool(audio.call("play_ambience", amb_b, 0.04))
	await _wait_seconds(0.07)
	audio.call("stop_ambience", 0.04)
	await _wait_seconds(0.07)
	amb_ok = amb_ok and not bool(audio.call("is_ambience_playing"))

	var pool_size := int(audio.call("get_sfx_pool_size"))
	var rapid_ok := pool_size >= 4 and pool_size <= 6
	for _i: int in range(8):
		if not bool(audio.call("play_sfx", sfx_wav, 0.04)):
			rapid_ok = false
	var chime_ok := bool(audio.call("play_test_chime"))
	_check(amb_ok and rapid_ok and chime_ok, "T13_ambience_and_sfx_pool", "Ambience crossfade, %d-slot SFX pool burst & procedural chime verified" % pool_size)

	audio.queue_free()
	await process_frame


func _test_audio_voice_ducking_lifecycle() -> void:
	var audio := _make_audio_mgr()
	var bgm_wav := _make_dummy_wav(2.5, 220.0)
	var voice_wav := _make_dummy_wav(1.5, 520.0)

	var started_chars: Array[String] = []
	var finished_chars: Array[String] = []
	audio.connect("voice_started", func(cid: String, _s: AudioStream) -> void: started_chars.append(cid))
	audio.connect("voice_finished", func(cid: String) -> void: finished_chars.append(cid))

	audio.call("play_bgm", bgm_wav, 0.0)
	var ok_play := bool(audio.call("play_voice", voice_wav, "roxy"))
	var active_playing := bool(audio.call("is_voice_playing")) and str(audio.call("get_active_voice_character")) == "roxy"
	await _wait_seconds(0.28)
	var ducked_state := bool(audio.call("is_bgm_ducked"))
	var ducked_db := float(audio.call("get_bgm_duck_db"))

	audio.call("stop_voice")
	await _wait_seconds(0.52)
	var unducked_state := not bool(audio.call("is_bgm_ducked"))
	var recovered_db := float(audio.call("get_bgm_duck_db"))

	var ok := (
		ok_play
		and active_playing
		and started_chars == ["roxy"]
		and finished_chars == ["roxy"]
		and ducked_state
		and ducked_db <= -5.5
		and unducked_state
		and absf(recovered_db) < 0.25
	)
	_check(
		ok,
		"T14_voice_ducking_lifecycle",
		"Voice started/finished signals & BGM ducking (%.2f dB -> %.2f dB) verified" % [ducked_db, recovered_db]
	)

	audio.call("stop_bgm", 0.0)
	audio.queue_free()
	await process_frame


func _test_audio_null_and_missing_safe() -> void:
	var audio := _make_audio_mgr()
	var no_bgm := not bool(audio.call("play_bgm", null, 0.5))
	var no_amb := not bool(audio.call("play_ambience", null, 0.5))
	var no_sfx := not bool(audio.call("play_sfx", null, 0.04))
	var no_voice := not bool(audio.call("play_voice", null, "sylphy"))
	var no_duck := not bool(audio.call("is_bgm_ducked"))
	var no_empty_path := (audio.call("load_stream_safe", "") as AudioStream) == null
	var no_missing_path := (audio.call("load_stream_safe", "res://assets/audio/missing_placeholder_voice.ogg") as AudioStream) == null
	_check(
		no_bgm and no_amb and no_sfx and no_voice and no_duck and no_empty_path and no_missing_path,
		"T15_null_and_missing_safe",
		"Null streams and missing paths skipped silently with zero errors"
	)

	audio.queue_free()
	await process_frame


func _test_settings_preview_scene_and_ui_flow() -> void:
	var preview_scene := load(SETTINGS_PREVIEW_PATH) as PackedScene
	if preview_scene == null:
		_check(false, "T16_settings_preview_and_ui_flow", "Failed to load settings_preview.tscn")
		return
	var preview := preview_scene.instantiate()
	root.add_child(preview)
	await process_frame
	await process_frame

	var smgr: Node = preview.get("settings_manager")
	var amgr: Node = preview.get("audio_bus_manager")
	var overlay: CanvasLayer = preview.get("settings_overlay")

	# Redirect config path so preview test never touches user's real settings.cfg
	smgr.call("set_config_path", TMP_CFG_PATH)

	var opened_ok := overlay != null and bool(overlay.call("is_open")) and str(overlay.call("get_active_tab")) == "graphics"

	# Verify desktop vs mobile display_mode row visibility
	smgr.set("mobile_override", 1)
	overlay.call("refresh_from_settings")
	var display_row: Control = overlay.get("_display_mode_row")
	var hidden_on_mobile := display_row != null and not display_row.visible
	smgr.set("mobile_override", 0)
	overlay.call("refresh_from_settings")
	var visible_on_desktop := display_row != null and display_row.visible

	# Switch tabs & trigger test chime
	overlay.call("select_tab", "audio", false)
	var audio_tab_ok := str(overlay.call("get_active_tab")) == "audio"
	var chime_ok := bool(overlay.call("play_test_chime"))
	overlay.call("select_tab", "reading", false)
	var reading_tab_ok := str(overlay.call("get_active_tab")) == "reading"

	# Close cleanly
	overlay.call("close", false)
	await process_frame
	var closed_ok := not bool(overlay.call("is_open"))

	_check(
		opened_ok and hidden_on_mobile and visible_on_desktop and audio_tab_ok and chime_ok and reading_tab_ok and closed_ok and amgr != null,
		"T16_settings_preview_and_ui_flow",
		"settings_preview.tscn rendered & exercised all 3 tabs, mobile hiding, test chime & close"
	)

	preview.queue_free()
	await _wait_seconds(0.08)
