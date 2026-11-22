extends Control

## Standalone interactive preview scene for SettingsOverlay + SettingsManager + AudioBusManager.
## Runs completely independently without modifying project.godot Autoloads.

const Kit := preload("res://ui/ui_theme_kit.gd")
const SettingsManagerScript := preload("res://core/settings_manager.gd")
const AudioBusManagerScript := preload("res://resources/audio/audio_bus_manager.gd")
const SettingsOverlayScene := preload("res://scenes/ui/settings/settings_overlay.tscn")

var settings_manager: Node = null
var audio_bus_manager: Node = null
var settings_overlay: CanvasLayer = null

var _title_font: SystemFont
var _body_font: SystemFont
var _summary_label: Label


func _ready() -> void:
	_title_font = Kit.make_font(true)
	_body_font = Kit.make_font(false)

	_build_backdrop()
	_setup_managers()
	_build_preview_hud()

	settings_overlay = SettingsOverlayScene.instantiate() as CanvasLayer
	add_child(settings_overlay)
	settings_overlay.call("configure", settings_manager, audio_bus_manager)
	settings_overlay.connect("closed", _refresh_summary)
	settings_overlay.connect("settings_saved", _refresh_summary)
	settings_overlay.call("open", "graphics")
	_refresh_summary()


func _setup_managers() -> void:
	audio_bus_manager = AudioBusManagerScript.new()
	audio_bus_manager.name = "PreviewAudioBusManager"
	add_child(audio_bus_manager)

	settings_manager = SettingsManagerScript.new()
	settings_manager.name = "PreviewSettingsManager"
	settings_manager.set("auto_load_on_ready", false)
	add_child(settings_manager)
	settings_manager.call("load_settings")
	settings_manager.call("apply_all", audio_bus_manager)
	settings_manager.connect("settings_changed", func(_s: String, _k: String, _v: Variant) -> void:
		_refresh_summary()
	)


func _build_backdrop() -> void:
	# Warm twilight parchment desk gradient backdrop (pure procedural, zero assets).
	var bg := TextureRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([
		Color("#2a2018"),
		Color("#3d2d20"),
		Color("#1e1610"),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.42)
	tex.fill_to = Vector2(1.0, 1.0)
	tex.width = 512
	tex.height = 288
	bg.texture = tex
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var watermark := Kit.AstralWatermark.new()
	watermark.setup(Color("#e0b76a"))
	add_child(watermark)
	watermark.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	watermark.offset_left = -460.0
	watermark.offset_right = 460.0
	watermark.offset_top = -460.0
	watermark.offset_bottom = 460.0


func _build_preview_hud() -> void:
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := Kit.create_folio_panel(Kit.PAPER, 36, 28, 12)
	panel.custom_minimum_size = Vector2(720.0, 320.0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var heading := Kit.create_label("系统设置与多轨音频 · 独立预览沙盒", 28, Kit.INK, _title_font)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(heading)

	vbox.add_child(Kit.create_gold_divider(0.0, true, 12.0))

	_summary_label = Kit.create_label("", 17, Kit.MUTED, _body_font)
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_summary_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 14)
	vbox.add_child(btn_row)

	var open_gfx := Kit.create_tactile_button("打开系统设置", "primary", _title_font, 19)
	open_gfx.custom_minimum_size = Vector2(180.0, 48.0)
	open_gfx.pressed.connect(func() -> void: settings_overlay.call("open", "graphics"))
	btn_row.add_child(open_gfx)

	var open_audio := Kit.create_tactile_button("声音与配音页", "secondary", _title_font, 19)
	open_audio.custom_minimum_size = Vector2(180.0, 48.0)
	open_audio.pressed.connect(func() -> void: settings_overlay.call("open", "audio"))
	btn_row.add_child(open_audio)

	var open_read := Kit.create_tactile_button("阅读与演出页", "secondary", _title_font, 19)
	open_read.custom_minimum_size = Vector2(180.0, 48.0)
	open_read.pressed.connect(func() -> void: settings_overlay.call("open", "reading"))
	btn_row.add_child(open_read)


func _refresh_summary() -> void:
	if _summary_label == null or settings_manager == null:
		return
	var preset := str(settings_manager.call("get_graphics_preset"))
	var profile: Dictionary = settings_manager.call("get_graphics_profile", preset)
	var vol_m := roundi(float(settings_manager.call("get_setting", "audio", "vol_master", 0.85)) * 100.0)
	var vol_b := roundi(float(settings_manager.call("get_setting", "audio", "vol_bgm", 0.70)) * 100.0)
	var vol_v := roundi(float(settings_manager.call("get_setting", "audio", "vol_voice", 0.90)) * 100.0)
	var txt_spd := float(settings_manager.call("get_text_speed"))
	var dice_spd := str(settings_manager.call("get_dice_animation_speed"))
	_summary_label.text = "当前画质：%s（%s）  ·  主音 %d%% / 配乐 %d%% / 配音 %d%%\n文字速度 %.2f×  ·  骰子演出：%s" % [
		str(profile.get("label", preset)),
		preset,
		vol_m,
		vol_b,
		vol_v,
		txt_spd,
		"极速" if dice_spd == "fast" else "标准",
	]
