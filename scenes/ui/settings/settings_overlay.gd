extends CanvasLayer

## Warm parchment grimoire-style Settings Overlay UI (Track 4).
## Strictly procedural layout built via UIThemeKit & UIMotion; minimal .tscn root.
## Decoupled from Autoload names: inject managers via configure(), or let it safely
## auto-discover /root/SettingsManager and /root/AudioBusManager (with local fallback).

signal opened()
signal closed()
signal settings_saved()
signal test_chime_played()

const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const BACKDROP := preload("res://shaders/backdrop_blur_vignette.gdshader")
const SettingsManagerScript := preload("res://core/settings_manager.gd")
const AudioBusManagerScript := preload("res://resources/audio/audio_bus_manager.gd")

const TAB_GRAPHICS := "graphics"
const TAB_AUDIO := "audio"
const TAB_READING := "reading"
const TAB_ORDER: Array[String] = [TAB_GRAPHICS, TAB_AUDIO, TAB_READING]

const CARD_SIZE := Vector2(1180.0, 846.0)
const SEA_MIST_SOFT := Color("#dce9f2")
const SEA_MIST_BORDER := Color("#4a7fa7")
const SEA_MIST_DEEP := Color("#36688d")
const ROW_FILL := Color("#efe5d3cc")
const ROW_BORDER := Color("#b7976766")

const TEXT_SPEED_PRESETS: Array[Dictionary] = [
	{"id": "slow", "label": "慢", "value": 0.6},
	{"id": "normal", "label": "标准", "value": 1.0},
	{"id": "fast", "label": "快", "value": 1.6},
	{"id": "instant", "label": "瞬显", "value": 2.5},
]

const AUDIO_ROWS: Array[Dictionary] = [
	{"key": "vol_master", "bus": &"Master", "title": "主音量", "desc": "全局总输出增益，拉至 0% 彻底静音"},
	{"key": "vol_bgm", "bus": &"BGM", "title": "背景音乐", "desc": "旅途与城镇配乐 · 弹窗与配音时轻柔避让"},
	{"key": "vol_ambience", "bus": &"Ambience", "title": "环境氛围", "desc": "海浪、风沙、酒馆人声与雨雪声景"},
	{"key": "vol_sfx", "bus": &"SFX", "title": "交互与音效", "desc": "手账翻页、D20 落骰、木质点击与金币声"},
	{"key": "vol_voice", "bus": &"Voice", "title": "角色配音", "desc": "预留配音专轨 · 语音播报自动闪避背景乐"},
]


class JellyToggle extends BaseButton:
	signal toggled_value(enabled: bool)

	var _progress := 0.0
	var _state_tween: Tween = null

	func _init() -> void:
		toggle_mode = true
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(74.0, 46.0)
		pivot_offset_ratio = Vector2(0.5, 0.5)
		toggled.connect(_on_toggled)

	func set_checked_instant(enabled: bool) -> void:
		set_pressed_no_signal(enabled)
		_kill_state_tween()
		_progress = 1.0 if enabled else 0.0
		queue_redraw()

	func _on_toggled(enabled: bool) -> void:
		_animate_to(1.0 if enabled else 0.0)
		toggled_value.emit(enabled)

	func _animate_to(target: float) -> void:
		_kill_state_tween()
		if not is_inside_tree():
			_progress = target
			queue_redraw()
			return
		var tw := create_tween()
		_state_tween = tw
		tw.tween_method(func(v: float) -> void:
			_progress = v
			queue_redraw()
		, _progress, target, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Motion.spring(self, ^"scale", Vector2(0.93, 0.93), Vector2.ONE, 0.28, 9.5, 8.0)

	func _kill_state_tween() -> void:
		if _state_tween != null and _state_tween.is_valid():
			_state_tween.kill()
		_state_tween = null

	func _draw() -> void:
		var track_w := 62.0
		var track_h := 32.0
		var x0 := (size.x - track_w) * 0.5
		var y0 := (size.y - track_h) * 0.5
		var t := clampf(_progress, 0.0, 1.0)
		var off_fill := Color("#d3c3aa")
		var on_fill := Kit.BLUE
		var track_col := off_fill.lerp(on_fill, t)
		if is_hovered():
			track_col = track_col.lightened(0.06)

		var track_box := StyleBoxFlat.new()
		track_box.bg_color = track_col
		track_box.border_color = Color("#8f7351").lerp(Color("#2c587a"), t)
		track_box.set_border_width_all(1)
		track_box.set_corner_radius_all(16)
		draw_style_box(track_box, Rect2(x0, y0, track_w, track_h))

		var min_cx := x0 + 16.0
		var max_cx := x0 + track_w - 16.0
		var cx := lerpf(min_cx, max_cx, _progress)
		var cy := y0 + track_h * 0.5
		draw_circle(Vector2(cx, cy + 1.5), 11.5, Color(0.08, 0.05, 0.03, 0.22))
		draw_circle(Vector2(cx, cy), 11.2, Kit.IVORY)
		draw_arc(Vector2(cx, cy), 11.0, 0.0, TAU, 28, Color("#c4a062").lerp(Kit.SAPPHIRE, t), 1.4, true)
		draw_circle(Vector2(cx, cy), 4.0, Color("#b9a58b").lerp(Kit.BLUE, t))


var _settings: Node = null
var _audio: Node = null
var _owns_settings := false
var _owns_audio := false
var _built := false
var _is_open := false
var _active_tab := TAB_GRAPHICS
var _syncing_ui := false

var _title_font: SystemFont
var _body_font: SystemFont
var _grabber_tex: ImageTexture
var _grabber_hover_tex: ImageTexture

var _canvas: Control
var _binding: PanelContainer
var _folio: PanelContainer
var _tab_buttons: Dictionary[String, Button] = {}
var _tab_pages: Dictionary[String, Control] = {}
var _tab_contents: Dictionary[String, Control] = {}
var _page_host: MarginContainer
var _status_label: Label
var _status_tween: Tween = null
var _close_tween: Tween = null

# Graphics widgets
var _preset_buttons: Dictionary[String, Button] = {}
var _preset_summary_label: Label
var _display_mode_row: PanelContainer
var _display_mode_buttons: Dictionary[String, Button] = {}
var _vsync_toggle: JellyToggle
var _vsync_state_label: Label
var _weather_toggle: JellyToggle
var _weather_state_label: Label

# Audio widgets
var _audio_sliders: Dictionary[String, HSlider] = {}
var _audio_value_labels: Dictionary[String, Label] = {}
var _audio_mute_buttons: Dictionary[String, Button] = {}
var _audio_saved_nonzero: Dictionary[String, float] = {}
var _test_chime_button: Button
var _audio_hint_label: Label

# Reading widgets
var _text_speed_buttons: Dictionary[String, Button] = {}
var _text_speed_slider: HSlider
var _text_speed_value_label: Label
var _auto_delay_slider: HSlider
var _auto_delay_value_label: Label
var _dice_speed_buttons: Dictionary[String, Button] = {}

# Footer widgets
var _reset_button: Button
var _save_close_button: Button
var _close_top_button: Button


func _ready() -> void:
	_ensure_built()


func _exit_tree() -> void:
	if _status_tween != null and _status_tween.is_valid():
		_status_tween.kill()
		_status_tween = null
	if _close_tween != null and _close_tween.is_valid():
		_close_tween.kill()
		_close_tween = null
	if _is_open and _audio != null and is_instance_valid(_audio) and _audio.has_method("set_bgm_muffled"):
		_audio.call("set_bgm_muffled", false, 0.0)
	_is_open = false


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close(true)


## Injects SettingsManager and optional AudioBusManager instances.
func configure(settings_mgr: Node, audio_mgr: Node = null) -> void:
	if _owns_settings and _settings != null and _settings != settings_mgr:
		_settings.queue_free()
		_owns_settings = false
	if _owns_audio and _audio != null and _audio != audio_mgr:
		_audio.queue_free()
		_owns_audio = false
	_settings = settings_mgr
	_audio = audio_mgr
	_ensure_built()
	refresh_from_settings()


func get_settings_manager() -> Node:
	_resolve_managers()
	return _settings


func get_audio_manager() -> Node:
	_resolve_managers()
	return _audio


func is_open() -> bool:
	return _is_open and _canvas != null and _canvas.visible


func get_active_tab() -> String:
	return _active_tab


func open(initial_tab: String = "") -> void:
	_ensure_built()
	_resolve_managers()
	if _close_tween != null and _close_tween.is_valid():
		_close_tween.kill()
		_close_tween = null

	var target_tab := initial_tab if TAB_ORDER.has(initial_tab) else _active_tab
	_is_open = true
	refresh_from_settings()
	select_tab(target_tab, false)
	_canvas.show()
	_canvas.modulate.a = 1.0
	_binding.scale = Vector2.ONE
	_status_label.text = "调整后即时生效 · 独立保存于系统手账"
	_status_label.modulate.a = 0.85

	if _audio != null and _audio.has_method("set_bgm_muffled"):
		_audio.call("set_bgm_muffled", true, 0.25)

	if is_inside_tree():
		Motion.fade_in(_canvas, 0.22)
		Motion.spring(_binding, ^"scale", Vector2(0.94, 0.94), Vector2.ONE, 0.38, 9.0, 7.5)

	opened.emit()


func close(animated: bool = true) -> void:
	if not _is_open:
		return
	_is_open = false
	if _audio != null and _audio.has_method("set_bgm_muffled"):
		_audio.call("set_bgm_muffled", false, 0.25)

	if not animated or not is_inside_tree():
		if _canvas != null:
			_canvas.hide()
		closed.emit()
		return

	if _close_tween != null and _close_tween.is_valid():
		_close_tween.kill()
	var tw := create_tween().set_parallel(true)
	_close_tween = tw
	tw.tween_property(_canvas, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_binding, "scale", Vector2(0.955, 0.955), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void:
		if not _is_open and _canvas != null:
			_canvas.hide()
			_canvas.modulate.a = 1.0
			_binding.scale = Vector2.ONE
		closed.emit()
	)


func select_tab(tab_id: String, animated: bool = true) -> void:
	_ensure_built()
	if not TAB_ORDER.has(tab_id):
		return
	var prev_idx := TAB_ORDER.find(_active_tab)
	var next_idx := TAB_ORDER.find(tab_id)
	var direction := 1.0 if next_idx >= prev_idx else -1.0
	_active_tab = tab_id

	for id: String in TAB_ORDER:
		var btn: Button = _tab_buttons[id]
		var active := id == tab_id
		btn.set_pressed_no_signal(active)
		var underline := btn.get_meta(&"gold_underline", null) as Control
		if underline != null:
			if animated and is_inside_tree():
				Motion.fade_alpha(underline, 1.0 if active else 0.0, 0.20)
			else:
				underline.modulate.a = 1.0 if active else 0.0
		var page_node: Control = _tab_pages[id]
		page_node.visible = active
		var inner_content: Control = _tab_contents.get(id, page_node)
		if active and animated and is_inside_tree():
			page_node.modulate.a = 0.0
			Motion.fade_alpha(page_node, 1.0, 0.22)
			if inner_content != page_node:
				var base_x := inner_content.position.x
				inner_content.position.x = base_x + direction * 16.0
				var slide_tw := create_tween()
				slide_tw.tween_property(inner_content, "position:x", base_x, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			Motion.spring(btn, ^"scale", Vector2(0.95, 0.95), Vector2.ONE, 0.30, 9.5, 8.0)
		elif active:
			page_node.modulate.a = 1.0


func refresh_from_settings() -> void:
	_ensure_built()
	_resolve_managers()
	if _settings == null:
		return
	_syncing_ui = true

	# Graphics tab
	var preset := str(_settings.call("get_graphics_preset"))
	_apply_segmented_visuals(_preset_buttons, preset, false)
	_update_preset_summary(preset)

	var is_mobile := bool(_settings.call("is_mobile_platform"))
	_display_mode_row.visible = not is_mobile
	var display_mode := str(_settings.call("get_display_mode"))
	_apply_segmented_visuals(_display_mode_buttons, display_mode, false)

	var vsync_on := bool(_settings.call("is_vsync_enabled"))
	_vsync_toggle.set_checked_instant(vsync_on)
	_vsync_state_label.text = "已开启" if vsync_on else "已关闭"
	_vsync_state_label.add_theme_color_override("font_color", SEA_MIST_DEEP if vsync_on else Kit.MUTED)

	var weather_on := bool(_settings.call("is_map_weather_particles_enabled"))
	_weather_toggle.set_checked_instant(weather_on)
	_weather_state_label.text = "已开启" if weather_on else "已关闭"
	_weather_state_label.add_theme_color_override("font_color", SEA_MIST_DEEP if weather_on else Kit.MUTED)

	# Audio tab
	for row: Dictionary in AUDIO_ROWS:
		var key := str(row["key"])
		var vol := clampf(float(_settings.call("get_setting", "audio", key, 0.8)), 0.0, 1.0)
		var slider: HSlider = _audio_sliders[key]
		slider.set_value_no_signal(vol)
		if vol > 0.01:
			_audio_saved_nonzero[key] = vol
		_update_volume_label(key, vol, false)

	# Reading tab
	var text_speed := clampf(float(_settings.call("get_text_speed")), 0.5, 2.5)
	_text_speed_slider.set_value_no_signal(text_speed)
	_update_text_speed_ui(text_speed, false)

	var auto_delay := clampf(float(_settings.call("get_auto_play_delay")), 0.5, 6.0)
	_auto_delay_slider.set_value_no_signal(auto_delay)
	_auto_delay_value_label.text = "%.1f 秒" % auto_delay

	var dice_speed := str(_settings.call("get_dice_animation_speed"))
	_apply_segmented_visuals(_dice_speed_buttons, dice_speed, false)

	_syncing_ui = false


## Plays a soft procedural bell chime on the SFX bus so players can test audio levels live.
func play_test_chime() -> bool:
	_resolve_managers()
	var played := false
	if _audio != null and _audio.has_method("play_test_chime"):
		played = bool(_audio.call("play_test_chime", &"SFX"))
	else:
		var temp_mgr := AudioBusManagerScript.new()
		add_child(temp_mgr)
		_audio = temp_mgr
		_owns_audio = true
		if _settings != null and _settings.has_method("apply_audio_settings"):
			_settings.call("apply_audio_settings", _audio)
		played = bool(_audio.call("play_test_chime", &"SFX"))

	if _test_chime_button != null and is_inside_tree():
		Motion.spring(_test_chime_button, ^"scale", Vector2(0.92, 0.92), Vector2.ONE, 0.34, 8.5, 9.0)

	var sfx_vol := clampf(float(_settings.call("get_setting", "audio", "vol_sfx", 0.8)), 0.0, 1.0) if _settings != null else 0.8
	var master_vol := clampf(float(_settings.call("get_setting", "audio", "vol_master", 0.85)), 0.0, 1.0) if _settings != null else 0.85
	var sfx_pct := roundi(sfx_vol * 100.0)
	if sfx_vol <= 0.001 or master_vol <= 0.001:
		_show_status("♪ 测试提示音已触发（当前主音量或音效处于静音状态）")
	else:
		var db_val := AudioBusManagerScript.linear_volume_to_db(sfx_vol)
		_show_status("♪ 已播放测试微铃声 · 音效 %d%%（%.1f dB）" % [sfx_pct, db_val])

	test_chime_played.emit()
	return played


func _resolve_managers() -> void:
	if _settings == null and is_inside_tree():
		_settings = get_tree().root.get_node_or_null("SettingsManager")
	if _settings == null:
		var local_settings := SettingsManagerScript.new()
		local_settings.name = "LocalSettingsManager"
		local_settings.auto_load_on_ready = false
		add_child(local_settings)
		local_settings.load_settings()
		_settings = local_settings
		_owns_settings = true

	if _audio == null and is_inside_tree():
		_audio = get_tree().root.get_node_or_null("AudioBusManager")
	if _audio == null:
		var local_audio := AudioBusManagerScript.new()
		local_audio.name = "LocalAudioBusManager"
		add_child(local_audio)
		_audio = local_audio
		_owns_audio = true
		if _settings != null and _settings.has_method("apply_audio_settings"):
			_settings.call("apply_audio_settings", _audio)


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_title_font = Kit.make_font(true)
	_body_font = Kit.make_font(false)
	_grabber_tex = _build_slider_knob_texture(24, false)
	_grabber_hover_tex = _build_slider_knob_texture(26, true)

	_canvas = Control.new()
	_canvas.name = "SettingsCanvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_canvas)
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_canvas.add_child(copy)

	var blur := ColorRect.new()
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var blur_mat := ShaderMaterial.new()
	blur_mat.shader = BACKDROP
	blur.material = blur_mat
	_canvas.add_child(blur)
	blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center_shell := CenterContainer.new()
	center_shell.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.add_child(center_shell)
	center_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var book := Kit.create_grimoire_book(CARD_SIZE, 0.30, false)
	_binding = book["binding"] as PanelContainer
	_folio = book["spread"] as PanelContainer
	center_shell.add_child(_binding)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 12)
	_folio.add_child(root_vbox)

	_build_header(root_vbox)
	root_vbox.add_child(Kit.create_gold_divider(0.0, true, 12.0))
	_build_tab_bar(root_vbox)

	_page_host = MarginContainer.new()
	_page_host.name = "TabPageHost"
	_page_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_host.clip_contents = true
	root_vbox.add_child(_page_host)

	var graphics_built := _build_graphics_tab()
	var audio_built := _build_audio_tab()
	var reading_built := _build_reading_tab()
	_tab_pages[TAB_GRAPHICS] = graphics_built["root"] as Control
	_tab_contents[TAB_GRAPHICS] = graphics_built["stack"] as Control
	_tab_pages[TAB_AUDIO] = audio_built["root"] as Control
	_tab_contents[TAB_AUDIO] = audio_built["stack"] as Control
	_tab_pages[TAB_READING] = reading_built["root"] as Control
	_tab_contents[TAB_READING] = reading_built["stack"] as Control
	for id: String in TAB_ORDER:
		var page_node: Control = _tab_pages[id]
		_page_host.add_child(page_node)

	root_vbox.add_child(Kit.create_gold_divider(0.0, false, 10.0))
	_build_footer(root_vbox)

	_canvas.hide()


func _build_header(parent: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	parent.add_child(header)

	var emblem := Kit.create_micro_icon("compass", 30.0, Kit.WAX_GOLD)
	emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(emblem)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	header.add_child(title_box)

	var title_lbl := Kit.create_label("系统设置", 34, Kit.INK, _title_font)
	title_box.add_child(title_lbl)

	var subtitle_lbl := Kit.create_label("暖羊皮纸旅途手账偏好 · 独立持久化于本地配置", 15, Kit.MUTED, _body_font)
	title_box.add_child(subtitle_lbl)

	_close_top_button = Kit.create_icon_button("close", "合上  Esc", "dark_brass", _title_font, 17, Kit.BRASS)
	_close_top_button.custom_minimum_size = Vector2(138.0, 46.0)
	_close_top_button.pressed.connect(func() -> void: close(true))
	header.add_child(_close_top_button)


func _build_tab_bar(parent: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	parent.add_child(bar)

	var tabs_meta: Array[Dictionary] = [
		{"id": TAB_GRAPHICS, "label": "画面与性能"},
		{"id": TAB_AUDIO, "label": "声音与配音"},
		{"id": TAB_READING, "label": "阅读与演出"},
	]
	var group := ButtonGroup.new()
	for meta: Dictionary in tabs_meta:
		var id := str(meta["id"])
		var btn := Kit.create_gold_tab_button(str(meta["label"]), _title_font, 22)
		btn.button_group = group
		btn.custom_minimum_size = Vector2(182.0, 48.0)
		btn.pressed.connect(select_tab.bind(id, true))
		bar.add_child(btn)
		_tab_buttons[id] = btn


func _create_tab_scroll_page(page_name: String) -> Dictionary:
	var scroll := ScrollContainer.new()
	scroll.name = page_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Kit.style_scrollbar(scroll.get_v_scroll_bar())

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(margin)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 14)
	margin.add_child(stack)

	return {"root": scroll, "stack": stack}


func _create_setting_card(pad_y: int = 13) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := Kit.style(ROW_FILL, 20, pad_y, 1, 1, ROW_BORDER)
	box.set_corner_radius_all(8)
	box.shadow_color = Color("#3a271618")
	box.shadow_offset = Vector2(0.0, 2.0)
	card.add_theme_stylebox_override("panel", box)
	return card


func _create_row_heading(title: String, desc: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 3)

	var t_lbl := Kit.create_label(title, 20, Kit.INK, _title_font)
	col.add_child(t_lbl)
	if not desc.is_empty():
		var d_lbl := Kit.create_label(desc, 14, Kit.MUTED, _body_font)
		d_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(d_lbl)
	return col


func _build_graphics_tab() -> Dictionary:
	var built := _create_tab_scroll_page("GraphicsTabPage")
	var stack := built["stack"] as VBoxContainer

	# 1. Graphics preset selector card
	var preset_card := _create_setting_card()
	stack.add_child(preset_card)
	var preset_vbox := VBoxContainer.new()
	preset_vbox.add_theme_constant_override("separation", 12)
	preset_card.add_child(preset_vbox)

	var preset_top := HBoxContainer.new()
	preset_top.add_theme_constant_override("separation", 16)
	preset_vbox.add_child(preset_top)
	preset_top.add_child(_create_row_heading("画质与性能档位", "按设备性能一键协调 3D 沙盘抗锯齿、阴影精度与大气粒子"))

	var preset_seg := HBoxContainer.new()
	preset_seg.add_theme_constant_override("separation", 10)
	preset_seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preset_top.add_child(preset_seg)
	var preset_defs: Array[Dictionary] = [
		{"id": "collector", "label": "典藏"},
		{"id": "balanced", "label": "均衡"},
		{"id": "battery", "label": "省电"},
	]
	for item: Dictionary in preset_defs:
		var pid := str(item["id"])
		var btn := _create_segment_button(str(item["label"]), 112.0)
		btn.pressed.connect(_on_graphics_preset_pressed.bind(pid))
		preset_seg.add_child(btn)
		_preset_buttons[pid] = btn

	var summary_panel := PanelContainer.new()
	var summary_box := Kit.style(Color("#e6d8be99"), 14, 8, 0, 1, Color("#b5946455"))
	summary_box.set_corner_radius_all(6)
	summary_panel.add_theme_stylebox_override("panel", summary_box)
	preset_vbox.add_child(summary_panel)
	_preset_summary_label = Kit.create_label("", 15, SEA_MIST_DEEP, _body_font)
	summary_panel.add_child(_preset_summary_label)

	# 2. Display mode (desktop only; auto-hidden on Android/mobile)
	_display_mode_row = _create_setting_card()
	stack.add_child(_display_mode_row)
	var disp_hbox := HBoxContainer.new()
	disp_hbox.add_theme_constant_override("separation", 16)
	_display_mode_row.add_child(disp_hbox)
	disp_hbox.add_child(_create_row_heading("显示模式", "仅桌面端生效，移动端将自动采用横屏沉浸显示"))

	var disp_seg := HBoxContainer.new()
	disp_seg.add_theme_constant_override("separation", 10)
	disp_seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	disp_hbox.add_child(disp_seg)
	for item: Dictionary in [{"id": "windowed", "label": "窗口"}, {"id": "fullscreen", "label": "全屏"}]:
		var did := str(item["id"])
		var btn := _create_segment_button(str(item["label"]), 124.0)
		btn.pressed.connect(_on_display_mode_pressed.bind(did))
		disp_seg.add_child(btn)
		_display_mode_buttons[did] = btn

	# 3. VSync toggle
	var vsync_card := _create_setting_card()
	stack.add_child(vsync_card)
	var vsync_hbox := HBoxContainer.new()
	vsync_hbox.add_theme_constant_override("separation", 14)
	vsync_card.add_child(vsync_hbox)
	vsync_hbox.add_child(_create_row_heading("垂直同步（V-Sync）", "平滑锁帧以消除横屏卷动与 3D 沙盘镜头撕裂"))
	_vsync_state_label = Kit.create_label("已开启", 15, SEA_MIST_DEEP, _body_font)
	_vsync_state_label.custom_minimum_size.x = 58.0
	_vsync_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_vsync_state_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vsync_hbox.add_child(_vsync_state_label)
	_vsync_toggle = JellyToggle.new()
	_vsync_toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_vsync_toggle.toggled_value.connect(_on_vsync_toggled)
	vsync_hbox.add_child(_vsync_toggle)

	# 4. World map dynamic weather particles toggle
	var weather_card := _create_setting_card()
	stack.add_child(weather_card)
	var weather_hbox := HBoxContainer.new()
	weather_hbox.add_theme_constant_override("separation", 14)
	weather_card.add_child(weather_hbox)
	weather_hbox.add_child(_create_row_heading("大地图动态雨雪与薄雾", "控制立体浮雕沙盘上的季节雨雪与盆地轻雾粒子演出"))
	_weather_state_label = Kit.create_label("已开启", 15, SEA_MIST_DEEP, _body_font)
	_weather_state_label.custom_minimum_size.x = 58.0
	_weather_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weather_state_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	weather_hbox.add_child(_weather_state_label)
	_weather_toggle = JellyToggle.new()
	_weather_toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_weather_toggle.toggled_value.connect(_on_weather_toggled)
	weather_hbox.add_child(_weather_toggle)

	return built


func _build_audio_tab() -> Dictionary:
	var built := _create_tab_scroll_page("AudioTabPage")
	var stack := built["stack"] as VBoxContainer
	stack.add_theme_constant_override("separation", 10)

	# Compact top strip with "测试提示音" button
	var strip := PanelContainer.new()
	var strip_box := Kit.style(Color("#e8dec8cc"), 18, 9, 0, 1, Color("#b8955c78"))
	strip_box.set_corner_radius_all(8)
	strip.add_theme_stylebox_override("panel", strip_box)
	stack.add_child(strip)

	var strip_row := HBoxContainer.new()
	strip_row.add_theme_constant_override("separation", 14)
	strip.add_child(strip_row)

	var voice_icon := Kit.create_micro_icon("voice", 22.0, Kit.BLUE)
	voice_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip_row.add_child(voice_icon)

	_audio_hint_label = Kit.create_label("五轨独立总控（Master / BGM / Ambience / SFX / Voice）· 0% 自动彻底静音", 15, Kit.MUTED, _body_font)
	_audio_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_audio_hint_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip_row.add_child(_audio_hint_label)

	_test_chime_button = Kit.create_icon_button("voice", "测试提示音", "primary", _title_font, 16, Kit.IVORY)
	_test_chime_button.custom_minimum_size = Vector2(154.0, 44.0)
	_test_chime_button.pressed.connect(func() -> void: play_test_chime())
	strip_row.add_child(_test_chime_button)

	for row: Dictionary in AUDIO_ROWS:
		var key := str(row["key"])
		var card := _create_setting_card(10)
		stack.add_child(card)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 14)
		card.add_child(hbox)

		var heading := _create_row_heading(str(row["title"]), str(row["desc"]))
		heading.custom_minimum_size.x = 340.0
		hbox.add_child(heading)

		var mute_btn := _create_mute_toggle_button(key)
		mute_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(mute_btn)
		_audio_mute_buttons[key] = mute_btn

		var slider := _create_styled_slider(0.0, 1.0, 0.01)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(_on_audio_slider_changed.bind(key))
		slider.drag_ended.connect(_on_audio_slider_drag_ended.bind(key))
		hbox.add_child(slider)
		_audio_sliders[key] = slider

		var val_lbl := Kit.create_label("80%", 18, SEA_MIST_DEEP, _title_font)
		val_lbl.custom_minimum_size = Vector2(68.0, 36.0)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		val_lbl.pivot_offset_ratio = Vector2(0.5, 0.5)
		val_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(val_lbl)
		_audio_value_labels[key] = val_lbl

	return built


func _build_reading_tab() -> Dictionary:
	var built := _create_tab_scroll_page("ReadingTabPage")
	var stack := built["stack"] as VBoxContainer

	# 1. Text speed (presets + fine slider)
	var speed_card := _create_setting_card()
	stack.add_child(speed_card)
	var speed_vbox := VBoxContainer.new()
	speed_vbox.add_theme_constant_override("separation", 12)
	speed_card.add_child(speed_vbox)

	var speed_top := HBoxContainer.new()
	speed_top.add_theme_constant_override("separation", 14)
	speed_vbox.add_child(speed_top)
	speed_top.add_child(_create_row_heading("文字显现速度", "调节对话正文逐字书写的节奏，或直接切换至瞬显"))

	var speed_seg := HBoxContainer.new()
	speed_seg.add_theme_constant_override("separation", 10)
	speed_seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	speed_top.add_child(speed_seg)
	for item: Dictionary in TEXT_SPEED_PRESETS:
		var sid := str(item["id"])
		var btn := _create_segment_button(str(item["label"]), 92.0)
		btn.pressed.connect(_on_text_speed_preset_pressed.bind(float(item["value"]), sid))
		speed_seg.add_child(btn)
		_text_speed_buttons[sid] = btn

	var speed_slider_row := HBoxContainer.new()
	speed_slider_row.add_theme_constant_override("separation", 14)
	speed_vbox.add_child(speed_slider_row)
	var fine_lbl := Kit.create_label("精细微调（0.5× ~ 2.5×）", 14, Kit.MUTED, _body_font)
	fine_lbl.custom_minimum_size.x = 180.0
	fine_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	speed_slider_row.add_child(fine_lbl)

	_text_speed_slider = _create_styled_slider(0.5, 2.5, 0.05)
	_text_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_speed_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_text_speed_slider.value_changed.connect(_on_text_speed_slider_changed)
	_text_speed_slider.drag_ended.connect(_on_text_speed_drag_ended)
	speed_slider_row.add_child(_text_speed_slider)

	_text_speed_value_label = Kit.create_label("1.0× · 42 字/秒", 16, SEA_MIST_DEEP, _title_font)
	_text_speed_value_label.custom_minimum_size.x = 148.0
	_text_speed_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_text_speed_value_label.pivot_offset_ratio = Vector2(0.5, 0.5)
	_text_speed_value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	speed_slider_row.add_child(_text_speed_value_label)

	# 2. Auto-play delay
	var delay_card := _create_setting_card()
	stack.add_child(delay_card)
	var delay_hbox := HBoxContainer.new()
	delay_hbox.add_theme_constant_override("separation", 16)
	delay_card.add_child(delay_hbox)
	var delay_head := _create_row_heading("自动阅读停顿", "开启自动翻页时，单句对话结束后停留的等待秒数")
	delay_head.custom_minimum_size.x = 380.0
	delay_hbox.add_child(delay_head)

	_auto_delay_slider = _create_styled_slider(0.5, 6.0, 0.1)
	_auto_delay_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auto_delay_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_auto_delay_slider.value_changed.connect(_on_auto_delay_slider_changed)
	_auto_delay_slider.drag_ended.connect(_on_auto_delay_drag_ended)
	delay_hbox.add_child(_auto_delay_slider)

	_auto_delay_value_label = Kit.create_label("2.0 秒", 18, SEA_MIST_DEEP, _title_font)
	_auto_delay_value_label.custom_minimum_size.x = 84.0
	_auto_delay_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_auto_delay_value_label.pivot_offset_ratio = Vector2(0.5, 0.5)
	_auto_delay_value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	delay_hbox.add_child(_auto_delay_value_label)

	# 3. 3D Dice animation speed
	var dice_card := _create_setting_card()
	stack.add_child(dice_card)
	var dice_hbox := HBoxContainer.new()
	dice_hbox.add_theme_constant_override("separation", 16)
	dice_card.add_child(dice_hbox)
	dice_hbox.add_child(_create_row_heading("3D 二十面骰演出速度", "标准模式保留手绘木桌抛掷质感；极速模式加快翻滚与检定回弹"))

	var dice_seg := HBoxContainer.new()
	dice_seg.add_theme_constant_override("separation", 10)
	dice_seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dice_hbox.add_child(dice_seg)
	for item: Dictionary in [{"id": "normal", "label": "标准演出"}, {"id": "fast", "label": "极速演出"}]:
		var dsid := str(item["id"])
		var btn := _create_segment_button(str(item["label"]), 136.0)
		btn.pressed.connect(_on_dice_speed_pressed.bind(dsid))
		dice_seg.add_child(btn)
		_dice_speed_buttons[dsid] = btn

	return built


func _build_footer(parent: VBoxContainer) -> void:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	parent.add_child(footer)

	_reset_button = Kit.create_tactile_button("恢复默认", "subtle", _title_font, 19)
	_reset_button.custom_minimum_size = Vector2(156.0, 48.0)
	_reset_button.pressed.connect(_on_reset_defaults_pressed)
	footer.add_child(_reset_button)

	_status_label = Kit.create_label("", 15, Kit.MUTED, _body_font)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_child(_status_label)

	_save_close_button = Kit.create_tactile_button("保存并关闭", "primary", _title_font, 19)
	_save_close_button.custom_minimum_size = Vector2(182.0, 48.0)
	_save_close_button.pressed.connect(_on_save_and_close_pressed)
	footer.add_child(_save_close_button)


func _create_segment_button(label_text: String, min_width: float) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(min_width, 46.0)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", _title_font)
	btn.add_theme_font_size_override("font_size", 18)
	_style_segment_button(btn, false)
	Motion.attach_button_feel(btn, 1.025, 0.955, false)
	return btn


func _style_segment_button(btn: Button, selected: bool) -> void:
	var norm_fill := Kit.BLUE if selected else Color("#ebe0cb")
	var hov_fill := Kit.BLUE.lightened(0.08) if selected else Color("#f4ead8")
	var prs_fill := SEA_MIST_DEEP if selected else Color("#dfd0b7")
	var norm_border := Color("#2f5f84") if selected else Color("#a5886099")
	var hov_border := Kit.BRASS if selected else SEA_MIST_BORDER
	var text_col := Kit.IVORY if selected else Kit.INK

	var s_norm := Kit.style(norm_fill, 14, 6, 3 if selected else 1, 1, norm_border)
	var s_hov := Kit.style(hov_fill, 14, 6, 4 if selected else 2, 1, hov_border)
	var s_prs := Kit.style(prs_fill, 14, 6, 0, 1, norm_border)
	for box: StyleBoxFlat in [s_norm, s_hov, s_prs]:
		box.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", s_norm)
	btn.add_theme_stylebox_override("hover", s_hov)
	btn.add_theme_stylebox_override("pressed", s_norm)
	btn.add_theme_stylebox_override("hover_pressed", s_hov)
	btn.add_theme_stylebox_override("focus", s_hov)
	btn.add_theme_color_override("font_color", text_col)
	btn.add_theme_color_override("font_hover_color", text_col)
	btn.add_theme_color_override("font_pressed_color", text_col)
	btn.add_theme_color_override("font_hover_pressed_color", text_col)
	btn.add_theme_color_override("font_focus_color", text_col)


func _apply_segmented_visuals(group_map: Dictionary[String, Button], active_id: String, animated: bool) -> void:
	for id: String in group_map.keys():
		var btn: Button = group_map[id]
		var selected := id == active_id
		btn.set_pressed_no_signal(selected)
		_style_segment_button(btn, selected)
		if selected and animated and is_inside_tree():
			Motion.spring(btn, ^"scale", Vector2(0.93, 0.93), Vector2.ONE, 0.32, 9.0, 8.5)


func _create_mute_toggle_button(audio_key: String) -> Button:
	var btn := Button.new()
	btn.text = "声"
	btn.tooltip_text = "点击快速静音 / 恢复音量"
	btn.custom_minimum_size = Vector2(44.0, 44.0)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", _title_font)
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(_on_audio_mute_button_pressed.bind(audio_key))
	Motion.attach_button_feel(btn, 1.05, 0.92, false)
	_style_mute_button(btn, false)
	return btn


func _style_mute_button(btn: Button, muted: bool) -> void:
	btn.text = "静" if muted else "声"
	var fill := Color("#dfd1bc") if muted else SEA_MIST_SOFT
	var border := Color("#9b7c5c99") if muted else Color("#4a7fa7aa")
	var txt := Kit.MUTED if muted else SEA_MIST_DEEP
	var s_norm := Kit.style(fill, 0, 0, 0, 1, border)
	var s_hov := Kit.style(fill.lightened(0.06), 0, 0, 1, 1, SEA_MIST_BORDER)
	s_norm.set_corner_radius_all(22)
	s_hov.set_corner_radius_all(22)
	btn.add_theme_stylebox_override("normal", s_norm)
	btn.add_theme_stylebox_override("hover", s_hov)
	btn.add_theme_stylebox_override("pressed", s_hov)
	btn.add_theme_stylebox_override("focus", s_hov)
	btn.add_theme_color_override("font_color", txt)
	btn.add_theme_color_override("font_hover_color", txt)
	btn.add_theme_color_override("font_pressed_color", txt)


func _create_styled_slider(min_v: float, max_v: float, step_v: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.custom_minimum_size = Vector2(220.0, 44.0)
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var track := StyleBoxFlat.new()
	track.bg_color = Color("#d8c8ae")
	track.border_color = Color("#9b7e5977")
	track.set_border_width_all(1)
	track.set_corner_radius_all(5)
	track.content_margin_top = 4
	track.content_margin_bottom = 4

	var fill := StyleBoxFlat.new()
	fill.bg_color = Kit.BLUE
	fill.border_color = Color("#7ab0d8")
	fill.border_width_top = 1
	fill.set_corner_radius_all(5)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4

	var fill_hl := fill.duplicate() as StyleBoxFlat
	fill_hl.bg_color = Kit.BLUE.lightened(0.08)

	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_hl)
	slider.add_theme_icon_override("grabber", _grabber_tex)
	slider.add_theme_icon_override("grabber_highlight", _grabber_hover_tex)
	slider.add_theme_icon_override("grabber_disabled", _grabber_tex)
	return slider


func _build_slider_knob_texture(diameter: int, highlighted: bool) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(diameter) * 0.5, float(diameter) * 0.5)
	var outer_r := float(diameter) * 0.46
	var rim_r := outer_r - 2.3
	var core_col := Kit.BLUE.lightened(0.10) if highlighted else Kit.BLUE
	var rim_col := Kit.IVORY
	var gold_col := Kit.BRASS if highlighted else Color("#b68d4c")

	for y: int in range(diameter):
		for x: int in range(diameter):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var dist := p.distance_to(center)
			var col := Color(0.0, 0.0, 0.0, 0.0)
			if dist <= outer_r + 1.0:
				var alpha := clampf(outer_r + 0.6 - dist, 0.0, 1.0)
				if dist >= outer_r - 1.2:
					col = Color(gold_col.r, gold_col.g, gold_col.b, alpha)
				elif dist >= rim_r:
					col = Color(rim_col.r, rim_col.g, rim_col.b, alpha)
				else:
					var spec := clampf(1.0 - p.distance_to(center + Vector2(-outer_r * 0.28, -outer_r * 0.28)) / (outer_r * 0.65), 0.0, 1.0)
					var shaded := core_col.lightened(spec * 0.28)
					col = Color(shaded.r, shaded.g, shaded.b, alpha)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


# --- Signal Handlers ---

func _on_graphics_preset_pressed(preset_id: String) -> void:
	if _syncing_ui or _settings == null:
		return
	_settings.call("set_graphics_preset", preset_id, false)
	_settings.call("apply_graphics_to_viewport")
	_apply_segmented_visuals(_preset_buttons, preset_id, true)
	_update_preset_summary(preset_id)
	_show_status("已切换画质档位：%s" % str(_settings.call("get_graphics_profile", preset_id).get("label", preset_id)))


func _update_preset_summary(preset_id: String) -> void:
	if _settings == null or _preset_summary_label == null:
		return
	var profile: Dictionary = _settings.call("get_graphics_profile", preset_id)
	var msaa_code := int(profile.get("msaa_3d", 0))
	var msaa_txt := "关闭"
	match msaa_code:
		Viewport.MSAA_2X:
			msaa_txt = "2×"
		Viewport.MSAA_4X:
			msaa_txt = "4×"
		Viewport.MSAA_8X:
			msaa_txt = "8×"
	var shadow_sz := int(profile.get("directional_shadow_size", 2048))
	var gi_txt := "SSAO + SSIL 开启" if bool(profile.get("ssil_enabled", false)) else ("仅 SSAO 开启" if bool(profile.get("ssao_enabled", false)) else "轻量光照")
	var particle_pct := roundi(float(profile.get("weather_particle_scale", 1.0)) * 100.0)
	_preset_summary_label.text = "%s  ·  MSAA %s  ·  阴影 %d  ·  %s  ·  天气粒子 %d%%" % [
		str(profile.get("subtitle", "")),
		msaa_txt,
		shadow_sz,
		gi_txt,
		particle_pct,
	]


func _on_display_mode_pressed(mode_id: String) -> void:
	if _syncing_ui or _settings == null:
		return
	_settings.call("set_setting", "graphics", "display_mode", mode_id, false)
	_settings.call("apply_display_settings")
	_apply_segmented_visuals(_display_mode_buttons, mode_id, true)
	_show_status("显示模式已切换为：%s" % ("全屏" if mode_id == "fullscreen" else "窗口"))


func _on_vsync_toggled(enabled: bool) -> void:
	if _syncing_ui or _settings == null:
		return
	_settings.call("set_setting", "graphics", "vsync_enabled", enabled, false)
	_settings.call("apply_display_settings")
	_vsync_state_label.text = "已开启" if enabled else "已关闭"
	_vsync_state_label.add_theme_color_override("font_color", SEA_MIST_DEEP if enabled else Kit.MUTED)
	_show_status("垂直同步：%s" % ("已开启" if enabled else "已关闭"))


func _on_weather_toggled(enabled: bool) -> void:
	if _syncing_ui or _settings == null:
		return
	_settings.call("set_setting", "graphics", "map_weather_particles", enabled, false)
	_weather_state_label.text = "已开启" if enabled else "已关闭"
	_weather_state_label.add_theme_color_override("font_color", SEA_MIST_DEEP if enabled else Kit.MUTED)
	_show_status("大地图动态雨雪与薄雾：%s" % ("已开启" if enabled else "已关闭"))


func _on_audio_slider_changed(new_value: float, key: String) -> void:
	if _syncing_ui or _settings == null:
		return
	var clamped := clampf(new_value, 0.0, 1.0)
	if clamped > 0.01:
		_audio_saved_nonzero[key] = clamped
	_settings.call("set_setting", "audio", key, clamped, false)
	_settings.call("apply_audio_settings", _audio)
	_update_volume_label(key, clamped, false)


func _on_audio_slider_drag_ended(_value_changed: bool, key: String) -> void:
	if _syncing_ui:
		return
	var lbl: Label = _audio_value_labels.get(key)
	if lbl != null and is_inside_tree():
		Motion.spring(lbl, ^"scale", Vector2(1.16, 1.16), Vector2.ONE, 0.30, 8.5, 9.5)


func _on_audio_mute_button_pressed(key: String) -> void:
	if _settings == null:
		return
	var current := clampf(float(_settings.call("get_setting", "audio", key, 0.8)), 0.0, 1.0)
	var next_vol := 0.0
	if current <= 0.001:
		next_vol = clampf(float(_audio_saved_nonzero.get(key, 0.75)), 0.15, 1.0)
	else:
		_audio_saved_nonzero[key] = current
		next_vol = 0.0
	_settings.call("set_setting", "audio", key, next_vol, false)
	_settings.call("apply_audio_settings", _audio)
	_audio_sliders[key].set_value_no_signal(next_vol)
	_update_volume_label(key, next_vol, true)


func _update_volume_label(key: String, linear_vol: float, pop_anim: bool) -> void:
	var lbl: Label = _audio_value_labels.get(key)
	var mute_btn: Button = _audio_mute_buttons.get(key)
	var is_muted := linear_vol <= 0.001
	if lbl != null:
		lbl.text = "静音" if is_muted else "%d%%" % roundi(linear_vol * 100.0)
		lbl.add_theme_color_override("font_color", Kit.MUTED if is_muted else SEA_MIST_DEEP)
		if pop_anim and is_inside_tree():
			Motion.spring(lbl, ^"scale", Vector2(1.15, 1.15), Vector2.ONE, 0.28, 8.5, 9.5)
	if mute_btn != null:
		_style_mute_button(mute_btn, is_muted)


func _on_text_speed_preset_pressed(speed_value: float, _preset_id: String) -> void:
	if _syncing_ui or _settings == null:
		return
	_settings.call("set_setting", "reading", "text_speed", speed_value, false)
	_text_speed_slider.set_value_no_signal(speed_value)
	_update_text_speed_ui(speed_value, true)
	_show_status("文字显现速度已更新")


func _on_text_speed_slider_changed(new_value: float) -> void:
	if _syncing_ui or _settings == null:
		return
	var clamped := clampf(new_value, 0.5, 2.5)
	_settings.call("set_setting", "reading", "text_speed", clamped, false)
	_update_text_speed_ui(clamped, false)


func _on_text_speed_drag_ended(_value_changed: bool) -> void:
	if _text_speed_value_label != null and is_inside_tree():
		Motion.spring(_text_speed_value_label, ^"scale", Vector2(1.14, 1.14), Vector2.ONE, 0.28, 8.5, 9.0)


func _update_text_speed_ui(speed_val: float, animated: bool) -> void:
	var matched_id := ""
	var best_diff := 0.16
	for item: Dictionary in TEXT_SPEED_PRESETS:
		var diff := absf(float(item["value"]) - speed_val)
		if diff < best_diff:
			best_diff = diff
			matched_id = str(item["id"])
	_apply_segmented_visuals(_text_speed_buttons, matched_id, animated)
	if speed_val >= 2.45:
		_text_speed_value_label.text = "瞬显模式"
	else:
		var cps := roundi(42.0 * speed_val)
		_text_speed_value_label.text = "%.2f× · %d 字/秒" % [speed_val, cps]


func _on_auto_delay_slider_changed(new_value: float) -> void:
	if _syncing_ui or _settings == null:
		return
	var clamped := clampf(new_value, 0.5, 6.0)
	_settings.call("set_setting", "reading", "auto_play_delay", clamped, false)
	_auto_delay_value_label.text = "%.1f 秒" % clamped


func _on_auto_delay_drag_ended(_value_changed: bool) -> void:
	if _auto_delay_value_label != null and is_inside_tree():
		Motion.spring(_auto_delay_value_label, ^"scale", Vector2(1.14, 1.14), Vector2.ONE, 0.28, 8.5, 9.0)


func _on_dice_speed_pressed(speed_id: String) -> void:
	if _syncing_ui or _settings == null:
		return
	_settings.call("set_setting", "reading", "dice_animation_speed", speed_id, false)
	_apply_segmented_visuals(_dice_speed_buttons, speed_id, true)
	_show_status("3D 骰子演出速度：%s" % ("极速演出" if speed_id == "fast" else "标准演出"))


func _on_reset_defaults_pressed() -> void:
	_resolve_managers()
	if _settings == null:
		return
	_settings.call("reset_to_defaults", true)
	_settings.call("apply_all", _audio)
	refresh_from_settings()
	if is_inside_tree():
		Motion.spring(_binding, ^"scale", Vector2(0.985, 0.985), Vector2.ONE, 0.30, 10.0, 8.5)
	_show_status("已恢复全部默认设置并写入配置文件")


func _on_save_and_close_pressed() -> void:
	_resolve_managers()
	if _settings != null:
		_settings.call("apply_all", _audio)
		_settings.call("save_settings")
	settings_saved.emit()
	close(true)


func _show_status(message: String) -> void:
	if _status_label == null:
		return
	_status_label.text = message
	if _status_tween != null and _status_tween.is_valid():
		_status_tween.kill()
		_status_tween = null
	if not is_inside_tree():
		_status_label.modulate.a = 1.0
		return
	_status_label.modulate.a = 0.0
	var tw := create_tween()
	_status_tween = tw
	tw.tween_property(_status_label, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
