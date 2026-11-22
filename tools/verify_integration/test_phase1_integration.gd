extends SceneTree

var _passed := 0
var _failed := 0


func _init() -> void:
	call_deferred("_run_all")


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("[FAIL] " + msg)
		print("[FAIL] " + msg)


func _make_dummy_wav(duration_sec: float = 0.5, freq_hz: float = 440.0) -> AudioStreamWAV:
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


func _find_seed_for_d20(target_face: int) -> int:
	var probe := RandomNumberGenerator.new()
	for s: int in range(1, 5000):
		probe.seed = s
		if probe.randi_range(1, 20) == target_face:
			return s
	return 1


func _run_all() -> void:
	print("=== Phase 1 Cross-System Integration Verification (Godot 4.7.2) ===")

	# 1. Verify all canonical Autoloads & 5-bus layout booted cleanly
	var wb: Node = root.get_node_or_null("WorldBlackboard")
	var rules: Node = root.get_node_or_null("RuleEngine")
	var bus_mgr: Node = root.get_node_or_null("AudioBusManager")
	var audio: Node = root.get_node_or_null("AudioManager")
	var settings: Node = root.get_node_or_null("SettingsManager")
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	var eco: Node = root.get_node_or_null("EconomyManager")
	var jm: Node = root.get_node_or_null("JournalManager")
	var jui: Node = root.get_node_or_null("JournalUI")

	_assert(wb != null and rules != null and bus_mgr != null and audio != null and settings != null
		and save_mgr != null and eco != null and jm != null and jui != null,
		"All 9 core Phase 1 Autoloads must be present on /root")
	_assert(bool(audio.call("has_all_required_buses")), "AudioManager bridge must see all 5 canonical buses")
	_assert(int(bus_mgr.call("get_bgm_lowpass_effect_index")) >= 0, "BGM bus must contain LowPassFilter slot")

	# 2. AudioManager bridge: legacy string APIs + new 5-bus / Voice Ducking / BGM Muffling
	audio.call("play_sfx", "ui_click")
	audio.call("play_sfx", "page_flip")
	audio.call("play_modifier_impact", true, 1, true)
	_assert(not bool(audio.call("has_voice", "")), "Empty voice path must return has_voice == false")
	_assert(not bool(audio.call("play_voice", "")), "Empty voice path must silently skip and return false")

	var orig_cfg_path: String = str(settings.call("get_config_path"))
	var tmp_cfg := "user://phase1_verify_settings.cfg"
	settings.call("set_config_path", tmp_cfg)
	settings.call("reset_to_defaults", false)
	settings.call("set_setting", "audio", "vol_master", 0.90)
	settings.call("set_setting", "audio", "vol_bgm", 0.65)
	settings.call("set_setting", "audio", "vol_ambience", 0.45)
	settings.call("set_setting", "audio", "vol_sfx", 0.75)
	settings.call("set_setting", "audio", "vol_voice", 0.85)
	settings.call("apply_audio_settings", bus_mgr)
	_assert(absf(float(audio.call("get_bus_volume", &"Ambience")) - 0.45) < 0.01,
		"SettingsManager Ambience volume must propagate through AudioBusManager -> AudioManager")
	audio.call("set_bus_volume", &"BGM", 0.0)
	_assert(bool(audio.call("is_bus_muted", &"BGM")), "AudioManager.set_bus_volume(BGM, 0.0) must mute BGM bus")
	audio.call("set_bus_volume", &"BGM", 0.70)
	_assert(not bool(audio.call("is_bus_muted", &"BGM")), "Restoring BGM volume must unmute BGM bus")

	var bgm_wav := _make_dummy_wav(2.0, 220.0)
	var voice_wav := _make_dummy_wav(1.5, 520.0)
	_assert(bool(audio.call("play_bgm", bgm_wav, 0.0)), "AudioManager.play_bgm(AudioStream) must succeed via AudioBusManager")
	_assert(bool(audio.call("play_voice", voice_wav, "notia")), "AudioManager.play_voice(AudioStream, character_id) must succeed")
	_assert(bool(audio.call("is_bgm_ducked")), "Playing character voice via AudioManager must trigger BGM Ducking")
	audio.call("stop_voice")
	_assert(not bool(audio.call("is_bgm_ducked")), "Stopping voice must release BGM Ducking")

	audio.call("set_bgm_muffled", true, 0.0)
	_assert(bool(audio.call("is_bgm_muffled")), "AudioManager.set_bgm_muffled(true) must enable BGM lowpass filter")
	audio.call("set_bgm_muffled", false, 0.0)
	_assert(not bool(audio.call("is_bgm_muffled")), "AudioManager.set_bgm_muffled(false) must restore BGM lowpass filter")

	# 3. SettingsManager <-> DialogueView (text_speed / auto_play_delay) & DiceRollOverlay (dice_animation_speed)
	var dlg_scene := load("res://scenes/dialogue/dialogue_view.tscn") as PackedScene
	_assert(dlg_scene != null, "dialogue_view.tscn must load cleanly")
	if dlg_scene != null:
		var dlg: Node = dlg_scene.instantiate()
		root.add_child(dlg)
		await process_frame
		settings.call("set_setting", "reading", "text_speed", 1.5)
		settings.call("set_setting", "reading", "auto_play_delay", 3.5)
		_assert(absf(float(dlg.call("get_effective_chars_per_sec")) - 42.0 * 1.5) < 0.01,
			"DialogueView must live-update chars_per_sec on SettingsManager change")
		_assert(not bool(dlg.call("is_instant_text_enabled")), "text_speed 1.5 must not trigger instant text")
		_assert(absf(float(dlg.call("get_effective_auto_delay")) - 3.5) < 0.01,
			"DialogueView must live-update auto_play_delay on SettingsManager change")
		settings.call("set_setting", "reading", "text_speed", 2.5)
		_assert(bool(dlg.call("is_instant_text_enabled")), "text_speed 2.5 must enable instant text mode in DialogueView")
		dlg.queue_free()
		await process_frame

	var dice_script := load("res://ui/dice_roll_overlay.gd") as Script
	var dice_overlay: Node = dice_script.new()
	root.add_child(dice_overlay)
	await process_frame
	settings.call("set_setting", "reading", "dice_animation_speed", "normal")
	_assert(is_equal_approx(float(dice_overlay.call("get_time_scale")), 1.0),
		"DiceRollOverlay time_scale must be 1.0 for normal speed")
	settings.call("set_setting", "reading", "dice_animation_speed", "fast")
	_assert(is_equal_approx(float(dice_overlay.call("get_time_scale")), 1.8),
		"DiceRollOverlay time_scale must live-update to 1.8 for fast speed")
	settings.call("set_setting", "reading", "dice_animation_speed", "normal")
	dice_overlay.queue_free()
	await process_frame

	# 4. Economy Survival Modifiers <-> RuleEngine Check Chain
	wb.call("reset_new_game")
	eco.call("reset_from_blackboard")
	jm.call("reset_for_new_game")

	var base_check: Dictionary = rules.call("collect_check", "CON", {})
	var base_mod := int(base_check["total_mod"])
	eco.call("set_balance", "demon_ore", 10000)
	var meal: Dictionary = eco.call("order_meal", "city_rikarisu", "demon_lizard_skewer", "")
	_assert(bool(meal.get("executed", false)), "Ordering meal in Rikarisu should succeed")
	var fed_check: Dictionary = rules.call("collect_check", "CON", {})
	_assert(int(eco.call("get_travel_check_modifier")) == 1 and int(fed_check["total_mod"]) == base_mod + 1,
		"well_fed (+1) must increase RuleEngine check total_mod by +1")

	var existing_r := int(eco.call("get_total_rations"))
	if existing_r > 0:
		wb.call("consume_rations", existing_r)
	eco.call("consume_daily_rations", 1, 1)
	var hungry_check: Dictionary = rules.call("collect_check", "CON", {})
	_assert(int(eco.call("get_travel_check_modifier")) == -1 and int(hungry_check["total_mod"]) == base_mod - 1,
		"hungry (-1) must decrease RuleEngine check total_mod by -1")

	eco.call("consume_daily_rations", 1, 1)
	var starving_check: Dictionary = rules.call("collect_check", "CON", {})
	_assert(int(eco.call("get_travel_check_modifier")) == -2 and int(starving_check["total_mod"]) == base_mod - 2,
		"starving (-2) must decrease RuleEngine check total_mod by -2")

	# 5. Economy Milestones <-> JournalManager Codex Unlock, Deduplicated Diary & UI Unread Badge
	wb.call("reset_new_game")
	eco.call("reset_from_blackboard")
	jm.call("reset_for_new_game")
	_assert(not bool(jm.call("is_codex_unlocked", "eco_six_currency_rates")),
		"eco_six_currency_rates must start locked before first cross-currency exchange")

	eco.call("set_balance", "demon_ore", 5000)
	var ex1: Dictionary = eco.call("execute_exchange", "demon_ore", "millis", 1000, "adventurer_guild", "city_rikarisu")
	_assert(bool(ex1.get("executed", false)), "First guild 0% exchange should succeed")
	_assert(bool(jm.call("is_codex_unlocked", "eco_six_currency_rates")),
		"First cross-currency exchange must auto-unlock eco_six_currency_rates codex")
	_assert(int(jm.call("get_unread_codex_count")) >= 1,
		"Auto-unlocked economy codex must increment unread codex count")
	var eco_diary_after_first := int(jm.call("get_diary_count", "economy"))
	_assert(eco_diary_after_first == 1, "First guild exchange must record exactly 1 economy diary entry")

	# Second small exchange must NOT spam diary
	var ex2: Dictionary = eco.call("execute_exchange", "demon_ore", "millis", 100, "adventurer_guild", "city_rikarisu")
	_assert(bool(ex2.get("executed", false)), "Second small guild exchange should succeed")
	_assert(int(jm.call("get_diary_count", "economy")) == eco_diary_after_first,
		"Repeated small exchanges must not spam duplicate economy diary entries")

	# Verify JournalUI character overlay reflects unread badge and clears on reading
	var char_overlay: Node = jui.get("character")
	char_overlay.call("open_section", "codex")
	await process_frame
	var unread_before_click := int(jm.call("get_unread_codex_count"))
	var codex_view: Node = char_overlay.call("get_codex_view")
	codex_view.call("select_entry", "eco_six_currency_rates", true)
	await process_frame
	_assert(int(jm.call("get_unread_codex_count")) == unread_before_click - 1,
		"Clicking unread economy codex in JournalUI must decrement unread badge")
	char_overlay.call("close_immediately")

	# 6. D20 Nat 20 / Nat 1 Auto-Diary Highlight (Zero Ordinary Spam, Zero Duplicate) + SaveManager Roundtrip
	var dice_before := int(jm.call("get_diary_count", "dice"))
	# Ordinary roll (face 10): must NOT write diary
	rules.call("set_seed", _find_seed_for_d20(10))
	var normal_roll: Dictionary = rules.call("roll_check", "DEX", 12, "natural", 0, {"label": "平衡"})
	_assert(int(normal_roll["raw_roll"]) == 10, "Seeded ordinary d20 roll expected 10")
	_assert(int(jm.call("get_diary_count", "dice")) == dice_before,
		"Ordinary d20 roll (10) must NOT spam JournalManager")

	# Natural 20: auto-writes positive warm highlight
	rules.call("set_seed", _find_seed_for_d20(20))
	var nat20: Dictionary = rules.call("roll_check", "INT", 14, "natural", 0, {"label": "魔术洞察", "context_note": "解读古碑"})
	_assert(bool(nat20["is_nat20"]), "Seeded Nat 20 roll expected")
	_assert(int(jm.call("get_diary_count", "dice")) == dice_before + 1,
		"Nat 20 must auto-record 1 dice highlight in JournalManager")

	# Calling record_dice_highlight again with the same roll_uid dedupe_key must NOT duplicate
	var dup_key := "dice_uid:" + str(nat20.get("roll_uid", ""))
	jm.call("record_dice_highlight", "魔术洞察", 20, 14, true, false, "解读古碑", dup_key)
	_assert(int(jm.call("get_diary_count", "dice")) == dice_before + 1,
		"Shared roll_uid dedupe_key must guarantee Nat 20 is never logged twice")

	# Natural 1: auto-writes negative cool highlight
	rules.call("set_seed", _find_seed_for_d20(1))
	var nat1: Dictionary = rules.call("roll_check", "DEX", 12, "natural", 0, {"label": "潜行", "context_note": "夜探峡谷"})
	_assert(bool(nat1["is_nat1"]), "Seeded Nat 1 roll expected")
	_assert(int(jm.call("get_diary_count", "dice")) == dice_before + 2,
		"Nat 1 must auto-record 1 dice highlight in JournalManager")

	# SaveManager full roundtrip preserving D20 highlights + codex + economy wallet
	var orig_save_dir: String = str(save_mgr.get("directory"))
	save_mgr.set("directory", "user://saves_verify_phase1_tmp")
	var snap_dice_count := int(jm.call("get_diary_count", "dice"))
	var snap_codex_prog: Dictionary = jm.call("get_codex_progress")
	var snap_millis := int(eco.call("get_balance", "millis"))
	_assert(bool(save_mgr.call("save_slot", "slot_1", save_mgr.get("ATLAS"))), "Phase 1 SaveManager.save_slot failed")

	jm.call("clear_diary")
	eco.call("set_balance", "millis", 0)
	_assert(bool(save_mgr.call("restore_slot_state", "slot_1")), "Phase 1 SaveManager.restore_slot_state failed")
	_assert(int(jm.call("get_diary_count", "dice")) == snap_dice_count,
		"Restored dice highlights count must match saved count")
	_assert(int(eco.call("get_balance", "millis")) == snap_millis,
		"Restored Millis wallet balance must match saved balance")
	var rest_prog: Dictionary = jm.call("get_codex_progress")
	_assert(int(rest_prog["unlocked"]) == int(snap_codex_prog["unlocked"]),
		"Restored codex unlocked count must match saved count")

	# Cleanup temp save dir
	var slot1_abs := ProjectSettings.globalize_path(str(save_mgr.get("directory")).path_join("slot_1.json"))
	if FileAccess.file_exists(slot1_abs):
		DirAccess.remove_absolute(slot1_abs)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(str(save_mgr.get("directory"))))
	save_mgr.set("directory", orig_save_dir)

	# 7. Title Screen instantiation + SettingsOverlay open/close + BGM Muffling + Zero Leak
	var title_scene := load("res://scenes/title/title_screen.tscn") as PackedScene
	_assert(title_scene != null, "title_screen.tscn must load cleanly")
	if title_scene != null:
		var title: Node = title_scene.instantiate()
		root.add_child(title)
		await process_frame
		audio.call("play_bgm", bgm_wav, 0.0)
		title.call("open_settings", "audio")
		await process_frame
		_assert(bool(title.call("is_settings_open")), "Title screen open_settings() must open SettingsOverlay")
		_assert(bool(audio.call("is_bgm_muffled")), "Opening SettingsOverlay from Title Screen must muffle BGM")
		title.call("close_settings", false)
		await process_frame
		_assert(not bool(title.call("is_settings_open")), "Title screen close_settings() must close SettingsOverlay")
		_assert(not bool(audio.call("is_bgm_muffled")), "Closing SettingsOverlay must restore BGM clarity")
		title.queue_free()
		await process_frame

	# Clean up audio & temporary config file
	audio.call("stop_voice")
	audio.call("stop_bgm", 0.0)
	audio.call("stop_all_sfx")
	settings.call("reset_to_defaults", false)
	settings.call("set_config_path", orig_cfg_path)
	var abs_cfg := ProjectSettings.globalize_path(tmp_cfg)
	if FileAccess.file_exists(tmp_cfg):
		DirAccess.remove_absolute(abs_cfg)

	await create_timer(0.15).timeout
	print("=== Phase 1 Integration Complete: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
