extends Node

const SAMPLE_RATE := 24000
const BUS_NAMES: Array[StringName] = [&"BGM", &"SFX", &"Voice"]
const SOUNDS: Dictionary[String, Array] = {
	"ui_hover": [[0.0, 920.0, 0.047, 0.025, 0.10]],
	"ui_click": [[0.0, 365.0, 0.09, 0.10, 0.26]],
	"page_flip": [[0.0, 235.0, 0.20, 0.10, 0.80], [0.075, 530.0, 0.10, 0.05, 0.65]],
	"dice_roll": [
		[0.0, 330.0, 0.075, 0.14, 0.41], [0.073, 455.0, 0.093, 0.15, 0.35],
		[0.182, 306.0, 0.076, 0.13, 0.48], [0.32, 488.0, 0.09, 0.10, 0.35],
		[0.443, 281.0, 0.08, 0.09, 0.41], [0.59, 254.0, 0.102, 0.06, 0.30]
	],
	"dice_success": [
		[0.0, 523.25, 0.32, 0.10, 0.0], [0.05, 659.25, 0.31, 0.075, 0.0],
		[0.09, 783.99, 0.34, 0.09, 0.0]
	],
	"dice_fail": [[0.0, 174.61, 0.24, 0.14, 0.13], [0.075, 130.81, 0.27, 0.10, 0.0]],
	"cast_start": [[0.0, 440.0, 0.30, 0.067, 0.02], [0.076, 659.25, 0.26, 0.065, 0.04], [0.16, 880.0, 0.19, 0.05, 0.06]],
	"water_hit": [[0.0, 156.0, 0.22, 0.14, 0.67], [0.028, 416.0, 0.15, 0.07, 0.48]],
	"slash_hit": [[0.0, 769.0, 0.15, 0.15, 0.75], [0.015, 186.0, 0.14, 0.08, 0.39]],
	"shield_block": [[0.0, 687.0, 0.26, 0.085, 0.08], [0.013, 1087.0, 0.3, 0.096, 0.02]],
	"timeline_tick": [[0.0, 810.0, 0.041, 0.03, 0.22]],
	"dice_bounce": [
		[0.0, 196.0, 0.085, 0.17, 0.62], [0.0, 98.0, 0.11, 0.13, 0.35],
		[0.012, 392.0, 0.05, 0.05, 0.5]
	],
	"modifier_absorb": [
		[0.0, 783.99, 0.18, 0.091, 0.01], [0.023, 1174.66, 0.16, 0.055, 0.0],
		[0.046, 1567.98, 0.13, 0.030, 0.0]
	],
	"modifier_drain": [
		[0.0, 138.59, 0.145, 0.16, 0.17], [0.006, 88.0, 0.18, 0.09, 0.06],
		[0.0, 254.0, 0.048, 0.046, 0.31]
	],
	"modifier_clutch": [
		[0.0, 392.0, 0.25, 0.062, 0.0], [0.014, 493.88, 0.25, 0.042, 0.0],
		[0.029, 587.33, 0.24, 0.040, 0.0]
	],
	"stat_up": [
		[0.0, 659.25, 0.30, 0.075, 0.0], [0.09, 987.77, 0.34, 0.065, 0.0],
		[0.09, 1318.51, 0.28, 0.03, 0.0]
	],
	"stat_down": [
		[0.0, 392.0, 0.26, 0.07, 0.05], [0.10, 261.63, 0.32, 0.06, 0.08]
	],
	"map_unfold": [
		[0.0, 320.0, 0.34, 0.10, 0.85], [0.10, 520.0, 0.26, 0.07, 0.80],
		[0.22, 260.0, 0.20, 0.05, 0.90]
	],
	"travel_step": [
		[0.0, 240.0, 0.06, 0.09, 0.50], [0.0, 120.0, 0.05, 0.06, 0.30]
	],
	"travel_wave": [
		[0.0, 155.0, 0.28, 0.07, 0.80], [0.06, 240.0, 0.24, 0.07, 0.96],
		[0.17, 390.0, 0.23, 0.04, 0.70]
	]
}

var _voice: AudioStreamPlayer
var _bgm: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx: Dictionary[String, AudioStreamWAV] = {}
var _streams: Dictionary[String, AudioStream] = {}
var _stream_modified: Dictionary[String, int] = {}
var _next_player := 0


func _ready() -> void:
	_bgm = _make_player(&"BGM")
	_voice = _make_player(&"Voice")
	for i: int in range(4):
		_sfx_players.append(_make_player(&"SFX"))


func _make_player(bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player


func set_bus_volume(bus: StringName, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0 or not BUS_NAMES.has(bus):
		return
	var linear := clampf(volume, 0.0, 1.0)
	AudioServer.set_bus_mute(index, linear == 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))


func bind_ui(control: BaseButton, click_sound: String = "ui_click") -> void:
	control.mouse_entered.connect(func() -> void:
		if not control.disabled:
			play_sfx("ui_hover")
	)
	if not click_sound.is_empty():
		control.pressed.connect(play_sfx.bind(click_sound))


func play_sfx(sound: String, pitch_scale: float = 1.0) -> void:
	if not SOUNDS.has(sound):
		return
	if not _sfx.has(sound):
		_sfx[sound] = _synthesize(SOUNDS[sound])
	var player := _sfx_players[_next_player]
	_next_player = (_next_player + 1) % _sfx_players.size()
	player.stream = _sfx[sound]
	player.pitch_scale = pitch_scale
	player.play()


func play_modifier_impact(positive: bool, streak_index: int, clutch: bool = false) -> void:
	var step := clampi(streak_index, 0, 3)
	if positive:
		play_sfx("modifier_absorb", 1.0 + step * 0.10)
		if clutch:
			play_sfx("modifier_clutch")
	else:
		play_sfx("modifier_drain", 1.0 - step * 0.035)


func play_bgm(path: String) -> bool:
	return _play_file(_bgm, path)


func stop_bgm() -> void:
	_bgm.stop()


func has_voice(voice_path: String) -> bool:
	return _get_stream(voice_path) != null


func play_voice(voice_path: String) -> bool:
	stop_voice()
	return _play_file(_voice, voice_path)


func stop_voice() -> void:
	_voice.stop()


func is_voice_playing() -> bool:
	return _voice.playing


func _play_file(player: AudioStreamPlayer, path: String) -> bool:
	var stream := _get_stream(path)
	if stream == null:
		return false
	player.stream = stream
	player.play()
	return true


func _get_stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if ResourceLoader.exists(path, "AudioStream"):
		return ResourceLoader.load(path, "AudioStream") as AudioStream
	if not FileAccess.file_exists(path):
		_streams.erase(path)
		_stream_modified.erase(path)
		return null
	var modified := FileAccess.get_modified_time(path)
	if _stream_modified.get(path, -1) == modified:
		return _streams[path]
	var stream: AudioStream
	match path.get_extension().to_lower():
		"ogg":
			stream = AudioStreamOggVorbis.load_from_file(path)
		"wav":
			stream = AudioStreamWAV.load_from_file(path)
	if stream != null:
		_streams[path] = stream
		_stream_modified[path] = modified
	return stream


func _synthesize(notes: Array) -> AudioStreamWAV:
	var duration := 0.0
	for note: Array in notes:
		duration = maxf(duration, float(note[0]) + float(note[2]))
	var frame_count := ceili(duration * SAMPLE_RATE)
	var mix := PackedFloat32Array()
	mix.resize(frame_count)
	var noise := RandomNumberGenerator.new()
	noise.seed = 418
	for note: Array in notes:
		var start := roundi(float(note[0]) * SAMPLE_RATE)
		var length := mini(ceili(float(note[2]) * SAMPLE_RATE), frame_count - start)
		for i: int in length:
			var seconds := float(i) / SAMPLE_RATE
			var phase := float(i) / length
			var envelope := minf(1.0, seconds / 0.004) * pow(1.0 - phase, 2.6)
			var tone := sin(TAU * float(note[1]) * seconds) + 0.18 * sin(TAU * float(note[1]) * 2.0 * seconds)
			var wave := lerpf(tone, noise.randf_range(-1.0, 1.0), float(note[4]))
			mix[start + i] += wave * envelope * float(note[3])
	var pcm := PackedByteArray()
	pcm.resize(frame_count * 2)
	for i: int in frame_count:
		pcm.encode_s16(i * 2, roundi(clampf(mix[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = pcm
	return stream


