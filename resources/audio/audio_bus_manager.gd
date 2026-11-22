extends Node

## Multi-track audio & voice bus manager (Track 4 standalone module).
## Manages Master / BGM / Ambience / SFX / Voice buses, dual-channel BGM & Ambience
## crossfades, pooled SFX playback, voice playback with automatic BGM ducking, and
## optional BGM low-pass muffling when modal overlays open.
## Zero hard dependency on Autoload names; can be used standalone or registered as an Autoload.

signal voice_started(character_id: String, stream: AudioStream)
signal voice_finished(character_id: String)
signal bgm_changed(stream: AudioStream)
signal ambience_changed(stream: AudioStream)
signal bus_volume_changed(bus_name: StringName, linear_volume: float)

const BUS_LAYOUT_PATH := "res://resources/audio/game_bus_layout.tres"
const BUS_MASTER := &"Master"
const BUS_BGM := &"BGM"
const BUS_AMBIENCE := &"Ambience"
const BUS_SFX := &"SFX"
const BUS_VOICE := &"Voice"
const REQUIRED_BUSES: Array[StringName] = [
	&"Master",
	&"BGM",
	&"Ambience",
	&"SFX",
	&"Voice",
]

const SFX_POOL_SIZE := 6
const MUTE_DB := -80.0
const SILENT_DB := -60.0
const MIN_LINEAR_DB_THRESHOLD := 0.0001
const BGM_DUCK_DB := -6.5
const BGM_DUCK_IN_SEC := 0.22
const BGM_DUCK_OUT_SEC := 0.45
const BGM_MUFFLE_OPEN_HZ := 18000.0
const BGM_MUFFLE_MODAL_HZ := 1450.0
const TEST_CHIME_SAMPLE_RATE := 24000

var _initialized := false
var _bgm_players: Array[AudioStreamPlayer] = []
var _bgm_slot_mix_db: Array[float] = [SILENT_DB, SILENT_DB]
var _bgm_active_slot := 0
var _bgm_current_stream: AudioStream = null
var _bgm_crossfade_tween: Tween = null
var _bgm_duck_db := 0.0
var _bgm_ducked := false
var _bgm_duck_tween: Tween = null
var _bgm_lowpass_index := -1
var _bgm_muffled := false
var _bgm_muffle_tween: Tween = null

var _ambience_players: Array[AudioStreamPlayer] = []
var _ambience_slot_mix_db: Array[float] = [SILENT_DB, SILENT_DB]
var _ambience_active_slot := 0
var _ambience_current_stream: AudioStream = null
var _ambience_crossfade_tween: Tween = null

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next_index := 0

var _voice_player: AudioStreamPlayer = null
var _voice_active := false
var _active_voice_character := ""

var _bus_volumes: Dictionary[StringName, float] = {
	&"Master": 0.85,
	&"BGM": 0.70,
	&"Ambience": 0.65,
	&"SFX": 0.80,
	&"Voice": 0.90,
}
var _bus_muted: Dictionary[StringName, bool] = {}
var _rng := RandomNumberGenerator.new()
var _test_chime_stream: AudioStreamWAV = null


func _ready() -> void:
	_ensure_initialized()


func _exit_tree() -> void:
	_kill_tween(_bgm_crossfade_tween)
	_bgm_crossfade_tween = null
	_kill_tween(_bgm_duck_tween)
	_bgm_duck_tween = null
	_kill_tween(_bgm_muffle_tween)
	_bgm_muffle_tween = null
	_kill_tween(_ambience_crossfade_tween)
	_ambience_crossfade_tween = null
	for player: AudioStreamPlayer in _bgm_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	for player: AudioStreamPlayer in _ambience_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	for player: AudioStreamPlayer in _sfx_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	if _voice_player != null and is_instance_valid(_voice_player):
		_voice_player.stop()
		_voice_player.stream = null
	_voice_active = false
	_active_voice_character = ""
	_bgm_current_stream = null
	_ambience_current_stream = null
	_test_chime_stream = null


func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_rng.randomize()
	ensure_bus_layout(true)
	_build_players()
	_sync_all_bus_volumes_to_server()


## Loads game_bus_layout.tres if available and guarantees all 5 canonical buses
## plus the BGM LowPassFilter effect slot exist on AudioServer.
func ensure_bus_layout(load_resource: bool = true) -> bool:
	var loaded_from_resource := false
	if load_resource and ResourceLoader.exists(BUS_LAYOUT_PATH, "AudioBusLayout"):
		var layout := ResourceLoader.load(BUS_LAYOUT_PATH, "AudioBusLayout") as AudioBusLayout
		if layout != null:
			AudioServer.set_bus_layout(layout)
			loaded_from_resource = true

	for bus_name: StringName in REQUIRED_BUSES:
		if bus_name == BUS_MASTER:
			continue
		if AudioServer.get_bus_index(bus_name) < 0:
			var new_index := AudioServer.bus_count
			AudioServer.add_bus(new_index)
			AudioServer.set_bus_name(new_index, String(bus_name))
			AudioServer.set_bus_send(new_index, BUS_MASTER)

	_bgm_lowpass_index = _ensure_bgm_lowpass_effect()
	_sync_all_bus_volumes_to_server()
	return loaded_from_resource


func _ensure_bgm_lowpass_effect() -> int:
	var bgm_idx := AudioServer.get_bus_index(BUS_BGM)
	if bgm_idx < 0:
		return -1
	var effect_count := AudioServer.get_bus_effect_count(bgm_idx)
	for idx: int in range(effect_count):
		if AudioServer.get_bus_effect(bgm_idx, idx) is AudioEffectLowPassFilter:
			return idx
	var lowpass := AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = BGM_MUFFLE_OPEN_HZ
	lowpass.resonance = 0.45
	AudioServer.add_bus_effect(bgm_idx, lowpass)
	var added_idx := AudioServer.get_bus_effect_count(bgm_idx) - 1
	AudioServer.set_bus_effect_enabled(bgm_idx, added_idx, false)
	return added_idx


func _build_players() -> void:
	if _bgm_players.is_empty():
		for i: int in range(2):
			var player := _create_player("BGMChannel%d" % i, BUS_BGM)
			player.volume_db = SILENT_DB
			_bgm_players.append(player)
	if _ambience_players.is_empty():
		for i: int in range(2):
			var player := _create_player("AmbienceChannel%d" % i, BUS_AMBIENCE)
			player.volume_db = SILENT_DB
			_ambience_players.append(player)
	if _sfx_players.is_empty():
		for i: int in range(SFX_POOL_SIZE):
			_sfx_players.append(_create_player("SFXPool%d" % i, BUS_SFX))
	if _voice_player == null:
		_voice_player = _create_player("VoiceChannel", BUS_VOICE)
		_voice_player.finished.connect(_on_voice_player_finished)


func _create_player(node_name: String, bus_name: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = bus_name
	add_child(player)
	return player


## Linear (0.0..1.0) to smooth perceptual dB conversion; 0.0 maps to MUTE_DB (-80 dB).
static func linear_volume_to_db(linear_volume: float) -> float:
	var clamped := clampf(linear_volume, 0.0, 1.0)
	if clamped <= MIN_LINEAR_DB_THRESHOLD:
		return MUTE_DB
	return linear_to_db(clamped)


func set_bus_volume(bus_name: StringName, linear_volume: float) -> void:
	_ensure_initialized()
	var clamped := clampf(linear_volume, 0.0, 1.0)
	_bus_volumes[bus_name] = clamped
	_apply_bus_to_server(bus_name)
	bus_volume_changed.emit(bus_name, clamped)


func get_bus_volume(bus_name: StringName) -> float:
	_ensure_initialized()
	return float(_bus_volumes.get(bus_name, 1.0))


func set_bus_muted(bus_name: StringName, muted: bool) -> void:
	_ensure_initialized()
	_bus_muted[bus_name] = muted
	_apply_bus_to_server(bus_name)


func is_bus_muted(bus_name: StringName) -> bool:
	_ensure_initialized()
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		return true
	return AudioServer.is_bus_mute(bus_idx)


func get_bus_volume_db(bus_name: StringName) -> float:
	_ensure_initialized()
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		return MUTE_DB
	return AudioServer.get_bus_volume_db(bus_idx)


func has_all_required_buses() -> bool:
	for bus_name: StringName in REQUIRED_BUSES:
		if AudioServer.get_bus_index(bus_name) < 0:
			return false
	return true


func get_bgm_lowpass_effect_index() -> int:
	_ensure_initialized()
	return _bgm_lowpass_index


func _sync_all_bus_volumes_to_server() -> void:
	for bus_name: StringName in REQUIRED_BUSES:
		_apply_bus_to_server(bus_name)


func _apply_bus_to_server(bus_name: StringName) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		return
	var linear := clampf(float(_bus_volumes.get(bus_name, 1.0)), 0.0, 1.0)
	var forced_mute := bool(_bus_muted.get(bus_name, false))
	var should_mute := forced_mute or linear <= MIN_LINEAR_DB_THRESHOLD
	AudioServer.set_bus_mute(bus_idx, should_mute)
	AudioServer.set_bus_volume_db(bus_idx, linear_volume_to_db(linear))


## Plays a BGM stream with seamless dual-channel crossfade.
## Safely ignores null streams without raising errors.
func play_bgm(stream: AudioStream, fade_sec: float = 1.2) -> bool:
	_ensure_initialized()
	if stream == null:
		return false

	var clamped_fade := maxf(fade_sec, 0.0)
	var current_player := _bgm_players[_bgm_active_slot]
	if _bgm_current_stream == stream and current_player.playing:
		_kill_tween(_bgm_crossfade_tween)
		_bgm_crossfade_tween = null
		if clamped_fade <= 0.0 or not is_inside_tree():
			_set_bgm_slot_mix_db(_bgm_active_slot, 0.0)
		else:
			var active_slot := _bgm_active_slot
			var start_db := _bgm_slot_mix_db[active_slot]
			_bgm_crossfade_tween = create_tween()
			_bgm_crossfade_tween.tween_method(
				_set_bgm_slot_mix_db.bind(active_slot),
				start_db,
				0.0,
				clamped_fade
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		return true

	_kill_tween(_bgm_crossfade_tween)
	_bgm_crossfade_tween = null

	var old_slot := _bgm_active_slot
	var new_slot := 1 - _bgm_active_slot
	_bgm_active_slot = new_slot
	_bgm_current_stream = stream

	var old_player := _bgm_players[old_slot]
	var new_player := _bgm_players[new_slot]
	new_player.stream = stream

	if clamped_fade <= 0.0 or not is_inside_tree():
		if old_player.playing:
			old_player.stop()
		_bgm_slot_mix_db[old_slot] = SILENT_DB
		_bgm_slot_mix_db[new_slot] = 0.0
		_apply_bgm_slot_volumes()
		new_player.play()
	else:
		_bgm_slot_mix_db[new_slot] = SILENT_DB
		_apply_bgm_slot_volumes()
		new_player.play()
		var old_start_db := _bgm_slot_mix_db[old_slot]
		var tw := create_tween().set_parallel(true)
		_bgm_crossfade_tween = tw
		tw.tween_method(
			_set_bgm_slot_mix_db.bind(new_slot),
			SILENT_DB,
			0.0,
			clamped_fade
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if old_player.playing:
			tw.tween_method(
				_set_bgm_slot_mix_db.bind(old_slot),
				old_start_db,
				SILENT_DB,
				clamped_fade
			).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			tw.chain().tween_callback(func() -> void:
				if _bgm_active_slot != old_slot:
					old_player.stop()
					_set_bgm_slot_mix_db(old_slot, SILENT_DB)
			)

	bgm_changed.emit(stream)
	return true


func stop_bgm(fade_sec: float = 0.8) -> void:
	_ensure_initialized()
	_kill_tween(_bgm_crossfade_tween)
	_bgm_crossfade_tween = null
	var had_stream := _bgm_current_stream != null
	_bgm_current_stream = null

	var clamped_fade := maxf(fade_sec, 0.0)
	if clamped_fade <= 0.0 or not is_inside_tree():
		for i: int in range(_bgm_players.size()):
			_bgm_players[i].stop()
			_bgm_slot_mix_db[i] = SILENT_DB
		_apply_bgm_slot_volumes()
		if had_stream:
			bgm_changed.emit(null)
		return

	var any_playing := false
	var tw := create_tween().set_parallel(true)
	_bgm_crossfade_tween = tw
	for i: int in range(_bgm_players.size()):
		if _bgm_players[i].playing:
			any_playing = true
			tw.tween_method(
				_set_bgm_slot_mix_db.bind(i),
				_bgm_slot_mix_db[i],
				SILENT_DB,
				clamped_fade
			).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if any_playing:
		tw.chain().tween_callback(func() -> void:
			if _bgm_current_stream == null:
				for i: int in range(_bgm_players.size()):
					_bgm_players[i].stop()
					_bgm_slot_mix_db[i] = SILENT_DB
				_apply_bgm_slot_volumes()
		)
	else:
		_kill_tween(_bgm_crossfade_tween)
		_bgm_crossfade_tween = null
	if had_stream:
		bgm_changed.emit(null)


func get_current_bgm() -> AudioStream:
	return _bgm_current_stream


func is_bgm_playing() -> bool:
	_ensure_initialized()
	for player: AudioStreamPlayer in _bgm_players:
		if player.playing:
			return true
	return false


func get_active_bgm_slot() -> int:
	return _bgm_active_slot


## Smoothly toggles the BGM LowPassFilter for modal overlays (settings, journal, pause).
func set_bgm_muffled(muffled: bool, duration_sec: float = 0.25) -> void:
	_ensure_initialized()
	_bgm_muffled = muffled
	var bgm_idx := AudioServer.get_bus_index(BUS_BGM)
	if bgm_idx < 0 or _bgm_lowpass_index < 0:
		return
	var filter := AudioServer.get_bus_effect(bgm_idx, _bgm_lowpass_index) as AudioEffectLowPassFilter
	if filter == null:
		return

	_kill_tween(_bgm_muffle_tween)
	_bgm_muffle_tween = null

	var target_hz := BGM_MUFFLE_MODAL_HZ if muffled else BGM_MUFFLE_OPEN_HZ
	var clamped_dur := maxf(duration_sec, 0.0)
	if muffled:
		AudioServer.set_bus_effect_enabled(bgm_idx, _bgm_lowpass_index, true)

	if clamped_dur <= 0.0 or not is_inside_tree():
		filter.cutoff_hz = target_hz
		AudioServer.set_bus_effect_enabled(bgm_idx, _bgm_lowpass_index, muffled)
		return

	var tw := create_tween()
	_bgm_muffle_tween = tw
	tw.tween_property(filter, "cutoff_hz", target_hz, clamped_dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not muffled:
		tw.tween_callback(func() -> void:
			if not _bgm_muffled and _bgm_lowpass_index >= 0:
				AudioServer.set_bus_effect_enabled(bgm_idx, _bgm_lowpass_index, false)
		)


func is_bgm_muffled() -> bool:
	return _bgm_muffled


## Smooth dual-channel Ambience switcher (waves, desert wind, tavern chatter, rain).
func play_ambience(stream: AudioStream, fade_sec: float = 1.0) -> bool:
	_ensure_initialized()
	if stream == null:
		return false

	var clamped_fade := maxf(fade_sec, 0.0)
	var current_player := _ambience_players[_ambience_active_slot]
	if _ambience_current_stream == stream and current_player.playing:
		return true

	_kill_tween(_ambience_crossfade_tween)
	_ambience_crossfade_tween = null

	var old_slot := _ambience_active_slot
	var new_slot := 1 - _ambience_active_slot
	_ambience_active_slot = new_slot
	_ambience_current_stream = stream

	var old_player := _ambience_players[old_slot]
	var new_player := _ambience_players[new_slot]
	new_player.stream = stream

	if clamped_fade <= 0.0 or not is_inside_tree():
		if old_player.playing:
			old_player.stop()
		_set_ambience_slot_mix_db(old_slot, SILENT_DB)
		_set_ambience_slot_mix_db(new_slot, 0.0)
		new_player.play()
	else:
		_set_ambience_slot_mix_db(new_slot, SILENT_DB)
		new_player.play()
		var old_start_db := _ambience_slot_mix_db[old_slot]
		var tw := create_tween().set_parallel(true)
		_ambience_crossfade_tween = tw
		tw.tween_method(
			_set_ambience_slot_mix_db.bind(new_slot),
			SILENT_DB,
			0.0,
			clamped_fade
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		if old_player.playing:
			tw.tween_method(
				_set_ambience_slot_mix_db.bind(old_slot),
				old_start_db,
				SILENT_DB,
				clamped_fade
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			tw.chain().tween_callback(func() -> void:
				if _ambience_active_slot != old_slot:
					old_player.stop()
					_set_ambience_slot_mix_db(old_slot, SILENT_DB)
			)

	ambience_changed.emit(stream)
	return true


func stop_ambience(fade_sec: float = 0.8) -> void:
	_ensure_initialized()
	_kill_tween(_ambience_crossfade_tween)
	_ambience_crossfade_tween = null
	var had_stream := _ambience_current_stream != null
	_ambience_current_stream = null

	var clamped_fade := maxf(fade_sec, 0.0)
	if clamped_fade <= 0.0 or not is_inside_tree():
		for i: int in range(_ambience_players.size()):
			_ambience_players[i].stop()
			_set_ambience_slot_mix_db(i, SILENT_DB)
		if had_stream:
			ambience_changed.emit(null)
		return

	var any_playing := false
	var tw := create_tween().set_parallel(true)
	_ambience_crossfade_tween = tw
	for i: int in range(_ambience_players.size()):
		if _ambience_players[i].playing:
			any_playing = true
			tw.tween_method(
				_set_ambience_slot_mix_db.bind(i),
				_ambience_slot_mix_db[i],
				SILENT_DB,
				clamped_fade
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if any_playing:
		tw.chain().tween_callback(func() -> void:
			if _ambience_current_stream == null:
				for i: int in range(_ambience_players.size()):
					_ambience_players[i].stop()
					_set_ambience_slot_mix_db(i, SILENT_DB)
		)
	else:
		_kill_tween(_ambience_crossfade_tween)
		_ambience_crossfade_tween = null
	if had_stream:
		ambience_changed.emit(null)


func get_current_ambience() -> AudioStream:
	return _ambience_current_stream


func is_ambience_playing() -> bool:
	_ensure_initialized()
	for player: AudioStreamPlayer in _ambience_players:
		if player.playing:
			return true
	return false


## Plays a one-shot SFX through the 6-player object pool with optional random pitch jitter.
## Safely ignores null streams without raising errors.
func play_sfx(stream: AudioStream, pitch_jitter: float = 0.04, volume_db: float = 0.0) -> bool:
	_ensure_initialized()
	if stream == null:
		return false
	var player := _acquire_sfx_player()
	if player == null:
		return false
	var jitter := absf(pitch_jitter)
	var pitch := 1.0
	if jitter > 0.0:
		pitch = clampf(1.0 + _rng.randf_range(-jitter, jitter), 0.5, 2.0)
	player.bus = BUS_SFX
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = clampf(volume_db, MUTE_DB, 6.0)
	player.play()
	return true


func get_sfx_pool_size() -> int:
	_ensure_initialized()
	return _sfx_players.size()


func _acquire_sfx_player() -> AudioStreamPlayer:
	if _sfx_players.is_empty():
		return null
	for i: int in range(_sfx_players.size()):
		var idx := (_sfx_next_index + i) % _sfx_players.size()
		if not _sfx_players[idx].playing:
			_sfx_next_index = (idx + 1) % _sfx_players.size()
			return _sfx_players[idx]
	var recycled := _sfx_players[_sfx_next_index]
	_sfx_next_index = (_sfx_next_index + 1) % _sfx_players.size()
	return recycled


## Plays a character voice line on the dedicated Voice bus and gently ducks BGM.
## Safely ignores null streams without raising errors or triggering ducking.
func play_voice(stream: AudioStream, character_id: String = "") -> bool:
	_ensure_initialized()
	if stream == null:
		return false
	if _voice_active:
		var previous_character := _active_voice_character
		_voice_active = false
		_active_voice_character = ""
		_voice_player.stop()
		voice_finished.emit(previous_character)

	_active_voice_character = character_id
	_voice_active = true
	_voice_player.stream = stream
	_voice_player.volume_db = 0.0
	_voice_player.play()
	_set_bgm_ducked(true)
	voice_started.emit(character_id, stream)
	return true


func stop_voice() -> void:
	_ensure_initialized()
	if not _voice_active and not _voice_player.playing:
		return
	var previous_character := _active_voice_character
	_voice_active = false
	_active_voice_character = ""
	_voice_player.stop()
	_set_bgm_ducked(false)
	voice_finished.emit(previous_character)


func is_voice_playing() -> bool:
	_ensure_initialized()
	return _voice_active and _voice_player.playing


func get_active_voice_character() -> String:
	return _active_voice_character


func is_bgm_ducked() -> bool:
	return _bgm_ducked


func get_bgm_duck_db() -> float:
	return _bgm_duck_db


func _on_voice_player_finished() -> void:
	if not _voice_active:
		return
	var finished_character := _active_voice_character
	_voice_active = false
	_active_voice_character = ""
	_set_bgm_ducked(false)
	voice_finished.emit(finished_character)


func _set_bgm_ducked(ducked: bool) -> void:
	_bgm_ducked = ducked
	_kill_tween(_bgm_duck_tween)
	_bgm_duck_tween = null
	var target_db := BGM_DUCK_DB if ducked else 0.0
	var duration := BGM_DUCK_IN_SEC if ducked else BGM_DUCK_OUT_SEC
	if not is_inside_tree() or duration <= 0.0:
		_set_bgm_duck_db(target_db)
		return
	var tw := create_tween()
	_bgm_duck_tween = tw
	tw.tween_method(_set_bgm_duck_db, _bgm_duck_db, target_db, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_bgm_duck_db(value_db: float) -> void:
	_bgm_duck_db = value_db
	_apply_bgm_slot_volumes()


func _set_bgm_slot_mix_db(slot: int, value_db: float) -> void:
	if slot < 0 or slot >= _bgm_slot_mix_db.size():
		return
	_bgm_slot_mix_db[slot] = value_db
	_apply_bgm_slot_volumes()


func _apply_bgm_slot_volumes() -> void:
	for i: int in range(_bgm_players.size()):
		var combined_db := clampf(_bgm_slot_mix_db[i] + _bgm_duck_db, MUTE_DB, 6.0)
		_bgm_players[i].volume_db = combined_db


func _set_ambience_slot_mix_db(slot: int, value_db: float) -> void:
	if slot < 0 or slot >= _ambience_slot_mix_db.size():
		return
	_ambience_slot_mix_db[slot] = value_db
	if slot < _ambience_players.size():
		_ambience_players[slot].volume_db = clampf(value_db, MUTE_DB, 6.0)


## Safely loads an AudioStream from a resource path or disk file, returning null
## without logging errors when the asset does not exist yet (e.g. unrecorded voice lines).
func load_stream_safe(resource_path: String) -> AudioStream:
	if resource_path.is_empty():
		return null
	if ResourceLoader.exists(resource_path, "AudioStream"):
		return ResourceLoader.load(resource_path, "AudioStream") as AudioStream
	if not FileAccess.file_exists(resource_path):
		return null
	match resource_path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(resource_path)
		"wav":
			return AudioStreamWAV.load_from_file(resource_path)
	return null


## Synthesizes a soft warm bell chime (zero external assets) for Settings audio preview.
func create_test_chime_stream() -> AudioStreamWAV:
	if _test_chime_stream != null:
		return _test_chime_stream
	var duration := 0.56
	var frame_count := ceili(duration * float(TEST_CHIME_SAMPLE_RATE))
	var pcm := PackedByteArray()
	pcm.resize(frame_count * 2)
	var notes: Array[Array] = [
		[0.0, 587.33, 0.42, 0.24],   # D5 warm fundamental
		[0.085, 880.0, 0.44, 0.20],  # A5 fifth chime
		[0.16, 1174.66, 0.38, 0.11], # D6 crystalline shimmer
	]
	for frame: int in range(frame_count):
		var t := float(frame) / float(TEST_CHIME_SAMPLE_RATE)
		var sample := 0.0
		for note: Array in notes:
			var start_t := float(note[0])
			var freq := float(note[1])
			var note_dur := float(note[2])
			var amp := float(note[3])
			var local_t := t - start_t
			if local_t < 0.0 or local_t > note_dur:
				continue
			var attack := clampf(local_t / 0.008, 0.0, 1.0)
			var decay := exp(-local_t * 6.4) * (1.0 - local_t / note_dur)
			var tone := sin(TAU * freq * local_t) + 0.22 * sin(TAU * freq * 2.0 * local_t)
			sample += tone * attack * decay * amp
		pcm.encode_s16(frame * 2, roundi(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = TEST_CHIME_SAMPLE_RATE
	stream.stereo = false
	stream.data = pcm
	_test_chime_stream = stream
	return stream


## Plays the procedural warm test chime on the SFX bus (or specified bus) to verify volume changes live.
func play_test_chime(bus_name: StringName = BUS_SFX) -> bool:
	_ensure_initialized()
	var chime := create_test_chime_stream()
	if bus_name == BUS_SFX:
		return play_sfx(chime, 0.015, -2.0)
	var player := _acquire_sfx_player()
	if player == null:
		return false
	var target_bus := bus_name if AudioServer.get_bus_index(bus_name) >= 0 else BUS_SFX
	player.bus = target_bus
	player.stream = chime
	player.pitch_scale = 1.0
	player.volume_db = -2.0
	player.play()
	return true


func _kill_tween(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
