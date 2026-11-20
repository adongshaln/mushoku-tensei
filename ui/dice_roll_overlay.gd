extends CanvasLayer

signal completed

const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const Stage := preload("res://ui/d20_3d_stage.gd")
const Dial := preload("res://ui/d20_stage_dial.gd")
const Resonance := preload("res://ui/d20_resonance_fx.gd")
const BACKDROP := preload("res://shaders/backdrop_blur_vignette.gdshader")
const PORCELAIN_MIST := preload("res://shaders/d20_porcelain_mist.gdshader")
const PATCH_SIZE := Vector2(170.0, 126.0)
const FACE_INK := Color("#FFF0CF")
const TITLE_INK := Color("#F5EBDC")
const DC_INK := Color("#F1D6A6")
const HUD_FADE_SECONDS := 0.22
const BARE_BEAT := 0.35
const WAKE_SECONDS := 0.08
const CLUTCH_WAKE_SECONDS := WAKE_SECONDS + 0.10
const FLIGHT_SECONDS := 0.24
const MAX_BEATS := 7
const SKIP_LOCK_MS := 240


class Modifier extends RefCounted:
	var title: String
	var value: int
	var category: String
	var total: int
	var crossing := false
	var base := false
	var count := 1
	var chip: PanelContainer
	var flight: Resonance.Flight

	func _init(text: String, amount: int, sublabel: String = "", is_base: bool = false) -> void:
		title = text
		value = amount
		category = sublabel
		base = is_base


var _check: Dictionary = {}
var _active := false
var _phase := "idle"
var _sequence: Tween
var _ink_tween: Tween
var _stamp_locked_until := 0
var _last_polarity := 0
var _streak := 0
var _root: Control
var _stage: Stage
var _stage_box: Control
var _dial: Dial
var _resonance: Resonance
var _face_ink: Control
var _mist: ColorRect
var _mist_material: ShaderMaterial
var _title: Label
var _subtitle: Label
var _divider: Control
var _dc_label: Label
var _dc_badge: HBoxContainer
var _number: Label
var _beats: Array[Modifier] = []
var _stamp_box: PanelContainer
var _stamp_label: Label
var _equation: Label
var _hint: Label
var _title_font: SystemFont
var _body_font: SystemFont
var _serif: SystemFont
var _hud_opacities: Dictionary[CanvasItem, float] = {}


func _ready() -> void:
	layer = 80
	_title_font = Kit.make_font(true)
	_body_font = Kit.make_font()
	_serif = SystemFont.new()
	_serif.font_names = PackedStringArray(["Georgia", "Times New Roman", "Noto Serif"])
	_serif.font_weight = 700
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.gui_input.connect(_on_gui_input)
	_root.resized.connect(_layout_chips)

	_build_backdrop()
	_build_heading()

	_stage_box = Control.new()
	_stage_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_stage_box)
	_stage_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_stage_box.offset_left = -380
	_stage_box.offset_right = 380
	_stage_box.offset_top = -353
	_stage_box.offset_bottom = 287
	_dial = Dial.new()
	_stage_box.add_child(_dial)
	_dial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage = Stage.new()
	_stage.process_mode = Node.PROCESS_MODE_DISABLED
	_stage_box.add_child(_stage)
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.settled.connect(_on_settled)
	_stage.landed.connect(_dial.pulse)
	_build_face_ink()

	_stamp_box = Kit.create_folio_panel(Color("#302318E8"), 26, 12, 9)
	_stamp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_stamp_box)
	_stamp_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_stamp_box.offset_left = -270
	_stamp_box.offset_right = 270
	_stamp_box.offset_top = 222
	_stamp_box.offset_bottom = 318
	_stamp_box.pivot_offset_ratio = Vector2(0.5, 0.5)
	var stamp_page := VBoxContainer.new()
	stamp_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamp_page.add_theme_constant_override("separation", 4)
	_stamp_box.add_child(stamp_page)
	_stamp_label = Kit.create_label("", 32, DC_INK, _title_font)
	_stamp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp_page.add_child(_stamp_label)
	_equation = Kit.create_label("", 18, Color("#C9B89E"), _body_font)
	_equation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp_page.add_child(_equation)
	_stamp_box.hide()

	_hint = Kit.create_label("", 18, Color("#E3CFB3"), _body_font)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_hint)
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = 0.846
	_hint.anchor_bottom = 0.846
	_hint.offset_left = -560
	_hint.offset_right = 560
	_hint.offset_top = -14
	_hint.offset_bottom = 14


func _build_backdrop() -> void:
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_root.add_child(copy)
	var backdrop := ColorRect.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = BACKDROP
	backdrop.material = material
	_root.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_heading() -> void:
	var top := VBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 3)
	_root.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -490
	top.offset_right = 490
	top.offset_top = 92
	var spaced := FontVariation.new()
	spaced.base_font = _title_font
	spaced.spacing_glyph = 2
	_title = Kit.create_label("", 37, TITLE_INK, spaced)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_shadow_color", Color("#21140FBD"))
	_title.add_theme_constant_override("shadow_offset_y", 3)
	_title.add_theme_constant_override("shadow_outline_size", 7)
	top.add_child(_title)

	_divider = Control.new()
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_divider.custom_minimum_size = Vector2(260, 16)
	_divider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_divider.pivot_offset_ratio = Vector2(0.5, 0.5)
	top.add_child(_divider)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.22, 0.50, 0.78, 1.0])
	gradient.colors = PackedColorArray([Color("#BD8B4500"), Color("#C9995A42"), Color("#E3AD62E8"), Color("#C9995A42"), Color("#BD8B4500")])
	var rule := GradientTexture1D.new()
	rule.gradient = gradient
	rule.width = 260
	var line := TextureRect.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	line.texture = rule
	line.position = Vector2(0, 7)
	line.size = Vector2(260, 2)
	_divider.add_child(line)
	var star := Kit.create_micro_icon("star", 13.0, Color("#E9BD80"))
	star.position = Vector2(123.5, 1.5)
	star.size = Vector2(13, 13)
	_divider.add_child(star)

	var target := Kit.create_label("目标难度", 17, Color("#C9B89E"), _body_font)
	target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(target)
	_dc_badge = HBoxContainer.new()
	_dc_badge.alignment = BoxContainer.ALIGNMENT_CENTER
	_dc_badge.add_theme_constant_override("separation", 9)
	_dc_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dc_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_dc_badge.pivot_offset_ratio = Vector2(0.5, 0.5)
	top.add_child(_dc_badge)
	var prefix := Kit.create_label("DC", 14, Color("#CEB793"), _serif)
	prefix.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dc_badge.add_child(prefix)
	_dc_label = Kit.create_label("", 50, DC_INK, _serif)
	_dc_label.add_theme_constant_override("shadow_outline_size", 11)
	_dc_badge.add_child(_dc_label)
	var balance := Control.new()
	balance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	balance.custom_minimum_size.x = _serif.get_string_size("DC", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_dc_badge.add_child(balance)
	_subtitle = Kit.create_label("", 17, Color("#C9B89E"), _body_font)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(_subtitle)


func _build_face_ink() -> void:
	_resonance = Resonance.new()
	_root.add_child(_resonance)
	_resonance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_face_ink = Control.new()
	_face_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_face_ink)
	_mist = ColorRect.new()
	_mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mist.size = PATCH_SIZE
	_mist.position = -PATCH_SIZE * 0.5
	_mist_material = ShaderMaterial.new()
	_mist_material.shader = PORCELAIN_MIST
	_mist_material.set_shader_parameter("dice_view", _stage.get_stage_texture())
	_mist_material.set_shader_parameter("patch_size", PATCH_SIZE)
	_mist.material = _mist_material
	_face_ink.add_child(_mist)

	_number = Kit.create_label("", 74, FACE_INK, _serif)
	_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_number.add_theme_constant_override("outline_size", 8)
	_number.add_theme_constant_override("shadow_outline_size", 13)
	_number.add_theme_color_override("font_outline_color", Color("#392922"))
	_number.size = Vector2(300, 104)
	_number.position = Vector2(-150, -55)
	_number.pivot_offset_ratio = Vector2(0.5, 0.5)
	_face_ink.add_child(_number)
	_face_ink.hide()


func _process(_delta: float) -> void:
	if _active:
		_hint.modulate.a = 0.70 + 0.15 * sin(float(Time.get_ticks_msec()) * 0.0018)
		if _face_ink.visible:
			_sync_face_ink()


func _sync_face_ink() -> void:
	if _stage.size.x <= 0.0 or _stage.size.y <= 0.0:
		return
	var face := _stage.get_face_projection()
	var inverse := face.affine_inverse()
	_face_ink.position = _stage_box.position + face.origin
	_mist_material.set_shader_parameter("right_to_plate", Vector2(inverse.x.x, inverse.y.x))
	_mist_material.set_shader_parameter("down_to_plate", Vector2(inverse.x.y, inverse.y.y))
	_mist_material.set_shader_parameter("swatch_left", (face * Vector2(-0.225, 0.057)) / _stage.size)
	_mist_material.set_shader_parameter("swatch_right", (face * Vector2(0.225, 0.057)) / _stage.size)


func is_active() -> bool:
	return _active


func present(check: Dictionary, title: String, subtitle := "", auto_roll := false) -> void:
	_stop_sequence()
	_clear_resonance()
	_drop_chips()
	_beats.clear()
	_check = check
	_active = true
	_phase = "idle"
	_last_polarity = 0
	_streak = 0
	_stamp_locked_until = 0
	_root.show()
	_cover_hud()
	_stage.process_mode = Node.PROCESS_MODE_INHERIT
	_face_ink.hide()
	_stamp_box.hide()
	_dc_label.add_theme_color_override("font_color", DC_INK)
	_dc_label.add_theme_color_override("font_shadow_color", Color("#A5723B63"))
	_divider.modulate = Color(1, 1, 1, 0.84)
	_title.text = title
	_subtitle.text = subtitle
	_subtitle.visible = not subtitle.is_empty()
	_dc_label.text = str(int(check["dc"]))
	var rolls: Array[int] = check["rolls"]
	_stage.setup(rolls)
	_build_chips()
	_hint.text = "即将自动掷出 · 点击立即开掷" if auto_roll else "点击骰子或按空格掷出"
	Motion.fade_in(_root, 0.22)
	if auto_roll:
		_sequence = create_tween()
		_sequence.tween_interval(0.6)
		_sequence.tween_callback(_begin_roll)


func _cover_hud() -> void:
	for host: Node in [get_tree().current_scene, get_parent()]:
		if host == null or not host.has_method("get_dice_hud_items"):
			continue
		var items: Array[CanvasItem] = host.call("get_dice_hud_items")
		for item: CanvasItem in items:
			if is_instance_valid(item) and not _hud_opacities.has(item):
				_hud_opacities[item] = item.modulate.a
	for item: CanvasItem in _hud_opacities:
		if is_instance_valid(item):
			Motion.fade_alpha(item, 0.0, HUD_FADE_SECONDS)


func _restore_hud(animated: bool) -> void:
	for item: CanvasItem in _hud_opacities:
		if not is_instance_valid(item):
			continue
		if animated:
			Motion.fade_alpha(item, _hud_opacities[item], HUD_FADE_SECONDS)
		else:
			Motion.cancel(item, ^"modulate:a")
			item.modulate.a = _hud_opacities[item]
	if not animated:
		_hud_opacities.clear()


func _exit_tree() -> void:
	_restore_hud(false)


func _build_chips() -> void:
	var steps: Array[Modifier] = []
	var gains: Array[Modifier] = []
	var losses: Array[Modifier] = []
	var base_mod := int(_check["base_mod"])
	if base_mod != 0:
		steps.append(Modifier.new("基础修正", base_mod, "属性", true))
	for bonus: Dictionary in _check["bonus_list"]:
		var value := int(bonus["value"])
		if value == 0:
			continue
		var category: Variant = bonus.get("category", "")
		var step := Modifier.new(RuleEngine.bonus_label(bonus), value, str(category).strip_edges() if category is String or category is StringName else "")
		if value > 0:
			gains.append(step)
		else:
			losses.append(step)
	steps.append_array(gains)
	steps.append_array(losses)

	var dc := int(_check["dc"])
	var running := int(_check["raw_roll"])
	for step: Modifier in steps:
		step.total = running + step.value
		step.crossing = (running >= dc) != (step.total >= dc)
		running = step.total
	_beats = steps if steps.size() <= MAX_BEATS else _merge_beats(steps)
	var width := 188.0 if _beats.size() >= 6 else 213.0
	for beat: Modifier in _beats:
		var title := beat.title if beat.count == 1 else ("%d 项增益" if beat.value > 0 else "%d 项减益") % beat.count
		var category := beat.category if beat.count == 1 else ""
		if category.is_empty():
			category = "增益" if beat.value > 0 else "减益"
		beat.chip = Kit.create_modifier_chip(title, beat.value, category, _title_font, _serif, width)
		_root.add_child(beat.chip)
	_layout_chips()


func _merge_beats(steps: Array[Modifier]) -> Array[Modifier]:
	# Keep the base and each DC crossing separate. An ordered run of one sign
	# can cross DC only once, so long lists still fit in at most seven beats.
	var grouped: Array[Modifier] = []
	for step: Modifier in steps:
		var prior: Modifier = grouped.back() if not grouped.is_empty() else null
		if prior != null and not prior.base and not prior.crossing and not step.crossing and signi(prior.value) == signi(step.value):
			prior.count += 1
			prior.value += step.value
			prior.total = step.total
			continue
		var beat := Modifier.new(step.title, step.value, step.category, step.base)
		beat.total = step.total
		beat.crossing = step.crossing
		grouped.append(beat)
	return grouped


func _layout_chips() -> void:
	if _phase not in ["idle", "rolling", "pair", "breath"]:
		return
	var gap := 13.0
	var width := gap * maxi(0, _beats.size() - 1)
	for beat: Modifier in _beats:
		beat.chip.size = beat.chip.get_combined_minimum_size()
		width += beat.chip.size.x
	var x := (_root.size.x - width) * 0.5
	for beat: Modifier in _beats:
		beat.chip.position = Vector2(x, _root.size.y * 0.758 - beat.chip.size.y * 0.5)
		x += beat.chip.size.x + gap


func _on_gui_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_root.accept_event()
		_advance_click()
	elif event is InputEventMouseMotion and _phase == "idle":
		var motion := event as InputEventMouseMotion
		var center := _stage_box.get_global_rect().get_center()
		var local := (motion.position - center) / (_stage_box.size * 0.5)
		var inside := _stage_box.get_global_rect().has_point(motion.position)
		_stage.set_hover(inside, local.clamp(Vector2(-1, -1), Vector2(1, 1)))


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_ENTER]:
			get_viewport().set_input_as_handled()
			_advance_click()
		elif event.keycode == KEY_ESCAPE and _phase == "stamp":
			get_viewport().set_input_as_handled()
			_dismiss()


func _advance_click() -> void:
	match _phase:
		"idle":
			_begin_roll()
		"rolling":
			_stage.skip()
		"absorb":
			_skip_absorption()
		"stamp":
			_dismiss()


func _begin_roll() -> void:
	if _phase != "idle":
		return
	_stop_sequence()
	_phase = "rolling"
	_hint.text = "骰子翻滚中 · 点击可加速"
	_stage.set_hover(false, Vector2.ZERO)
	_stage.toss()


func _on_settled() -> void:
	if _phase != "rolling":
		return
	var rolls: Array[int] = _check["rolls"]
	if rolls.size() > 1:
		_phase = "pair"
		var winner := maxi(0, rolls.find(int(_check["raw_roll"])))
		_sequence = _stage.converge(winner)
		_sequence.finished.connect(_start_breath)
	else:
		_start_breath()


func _start_breath() -> void:
	_phase = "breath"
	_dial.pulse(0.36)
	_hint.text = ""
	_sequence = create_tween()
	_sequence.tween_interval(BARE_BEAT)
	_sequence.tween_callback(_start_absorption)


func _start_absorption() -> void:
	var raw := int(_check["raw_roll"])
	if _is_critical_face():
		_drop_chips()
		_resonance.impact(_focus_point(), raw == 20, true, true)
		_stamp()
		return
	if _beats.is_empty():
		_stamp()
		return
	_phase = "absorb"
	_hint.text = "修正值吸收中 · 点击或按空格加速"
	var count := _beats.size()
	var gap := 0.30 if count <= 3 else clampf(0.84 / float(count - 1), 0.14, 0.28)
	var first_wake := CLUTCH_WAKE_SECONDS if _beats[0].crossing and _beats[0].value > 0 else WAKE_SECONDS
	var first_contact := first_wake + FLIGHT_SECONDS
	_sequence = create_tween().set_parallel(true)
	for index: int in count:
		var beat := _beats[index]
		var clutch := beat.crossing and beat.value > 0
		var wake_time := CLUTCH_WAKE_SECONDS if clutch else WAKE_SECONDS
		var contact := first_contact + gap * index
		var launch := contact - FLIGHT_SECONDS
		_sequence.tween_callback(_wake.bind(beat, wake_time)).set_delay(maxf(0.0, launch - wake_time))
		_sequence.tween_callback(_launch.bind(beat)).set_delay(launch)
		_sequence.tween_method(_fly.bind(beat), 0.0, 1.0, FLIGHT_SECONDS).set_delay(launch)
		_sequence.tween_callback(_contact.bind(beat)).set_delay(contact)
	_sequence.finished.connect(_finish_absorption)


func _wake(beat: Modifier, duration: float) -> void:
	var chip := beat.chip
	chip.add_theme_stylebox_override("panel", Kit.modifier_style(beat.value > 0, true))
	Motion.spring(chip, ^"scale", chip.scale, Vector2.ONE * 1.08, duration, 5.8, 8.1)
	Motion.spring(chip, ^"position:y", chip.position.y, chip.position.y - 8.0, duration, 5.8, 8.1)


func _launch(beat: Modifier) -> void:
	Motion.cancel(beat.chip, ^"scale")
	Motion.cancel(beat.chip, ^"position:y")
	var flight := Resonance.Flight.new()
	flight.start = beat.chip.get_rect().get_center()
	flight.end = _focus_point()
	var side := flight.start.x - flight.end.x
	var wing := signf(side) * clampf(absf(side) * 0.40, 0.0, 160.0)
	flight.bend = flight.start.lerp(flight.end, 0.38) + Vector2(wing, -116.0 - minf(absf(side) * 0.15, 60.0))
	flight.color = Kit.MODIFIER_WARM_LIGHT if beat.value > 0 else Kit.MODIFIER_COLD_LIGHT
	beat.flight = flight
	_resonance.follow(flight)


func _fly(progress: float, beat: Modifier) -> void:
	var flight := beat.flight
	flight.progress = ease(progress, -1.55)
	var chip := beat.chip
	chip.position = flight.point(flight.progress) - chip.size * 0.5
	chip.scale = Vector2.ONE * lerpf(1.08, 0.136, pow(progress, 1.3))
	chip.modulate.a = 1.0 - smoothstep(0.70, 1.0, progress) * 0.84
	_resonance.queue_redraw()


func _contact(beat: Modifier) -> void:
	var flight := beat.flight
	var direction := (flight.end - flight.bend).normalized()
	_resonance.end_flight(flight)
	beat.flight = null
	beat.chip.hide()
	var positive := beat.value > 0
	_stage.play_modifier_impact(positive, direction, beat.crossing)
	_dial.pulse(0.86 if beat.crossing else 0.52, positive)
	_resonance.impact(_focus_point(), positive, beat.crossing)
	_show_ink(beat.total, positive)
	if beat.crossing:
		_set_dc_polarity(positive, true)
	var polarity := signi(beat.value)
	_streak = _streak + 1 if polarity == _last_polarity else 0
	_last_polarity = polarity
	AudioManager.play_modifier_impact(positive, _streak, beat.crossing)


func _focus_point() -> Vector2:
	return _stage_box.position + _stage.get_face_projection().origin


func _show_ink(total: int, positive: bool) -> void:
	var first := not _face_ink.visible
	_face_ink.show()
	_sync_face_ink()
	_number.text = str(total)
	if first:
		Motion.fade_in(_mist, 0.074)
		_number.modulate.a = 0.0
	else:
		_number.modulate.a = 1.0
	_stop_ink_tint()
	var tint := Color("#FFDB94") if positive else Color("#CAE8F6")
	_set_ink_tint(tint)
	_mist_material.set_shader_parameter("glow_tone", tint)
	_mist_material.set_shader_parameter("light_mix", 0.8)
	var kick := Vector2.ONE * (1.20 if positive else 0.90)
	_ink_tween = create_tween().set_parallel(true)
	_ink_tween.tween_method(_set_ink_tint, tint, FACE_INK, 0.25).set_trans(Tween.TRANS_SINE)
	_ink_tween.tween_property(_mist_material, "shader_parameter/light_mix", 0.12, 0.26)
	if first:
		_number.scale = kick
		_ink_tween.tween_property(_number, "modulate:a", 1.0, 0.055).set_delay(0.075)
		_ink_tween.tween_callback(_kick_number.bind(kick)).set_delay(0.075)
	else:
		_kick_number(kick)


func _kick_number(kick: Vector2) -> void:
	Motion.spring(_number, ^"scale", kick, Vector2.ONE, 0.24, 5.8, 10.5)


func _set_ink_tint(tint: Color) -> void:
	_number.add_theme_color_override("font_color", tint)
	_number.add_theme_color_override("font_shadow_color", Color(tint, 0.5))


func _set_dc_polarity(positive: bool, pulse: bool) -> void:
	var ink := Kit.MODIFIER_WARM_VALUE if positive else Kit.MODIFIER_COLD_VALUE
	_dc_label.add_theme_color_override("font_shadow_color", Color(ink, 0.50 if pulse else 0.34))
	_dc_label.add_theme_color_override("font_color", ink)
	_divider.modulate = Color(1.0, 0.91, 0.70, 1.0) if positive else Color(0.69, 0.81, 0.98, 0.76)
	if pulse:
		Motion.spring(_dc_badge, ^"scale", Vector2.ONE * (1.13 if positive else 0.91), Vector2.ONE, 0.29, 5.6, 11.0)
		Motion.spring(_divider, ^"scale", Vector2(1.18 if positive else 0.94, 1.0), Vector2.ONE, 0.38, 6.0, 8.0)
		Motion.fade_alpha(_divider, 0.84 if positive else 0.72, 0.38)


func _skip_absorption() -> void:
	_stop_sequence()
	_clear_resonance()
	_stamp_locked_until = Time.get_ticks_msec() + SKIP_LOCK_MS
	_face_ink.show()
	_mist.modulate.a = 1.0
	_mist_material.set_shader_parameter("light_mix", 0.0)
	_number.modulate.a = 1.0
	_set_ink_tint(FACE_INK)
	_sync_face_ink()
	for beat: Modifier in _beats:
		if beat.crossing:
			_set_dc_polarity(beat.value > 0, false)
	_finish_absorption()


func _finish_absorption() -> void:
	_number.text = str(int(_check["total"]))
	_drop_chips()
	_stamp()


func _is_critical_face() -> bool:
	return _check.get("mode", "natural") == "natural" and (bool(_check["is_nat20"]) or bool(_check["is_nat1"]))


func _stamp() -> void:
	_phase = "stamp"
	var passed := bool(_check["passed"])
	var message := "✦ 检定成功" if passed else "✦ 失败推进"
	var tone := Kit.MODIFIER_WARM_VALUE if passed else Kit.MODIFIER_COLD_VALUE
	if _is_critical_face():
		var high := bool(_check["is_nat20"])
		if high and passed:
			message = "✦ 大成功！"
		elif not high and not passed:
			message = "✦ 大失败"
		else:
			message += "  ·  自然 %d" % int(_check["raw_roll"])
		tone = Kit.MODIFIER_WARM_VALUE if high else Kit.MODIFIER_COLD_VALUE
	_stamp_label.text = message
	_stamp_label.add_theme_color_override("font_color", tone)
	_stamp_box.add_theme_stylebox_override("panel", Kit.style(Color("#302318E8"), 26, 12, 9, 1, Color(tone, 0.52)))
	var terms := "d20(%d)" % int(_check["raw_roll"])
	for beat: Modifier in _beats:
		terms += " − %d" % absi(beat.value) if beat.value < 0 else " + %d" % beat.value
	_equation.text = "%s = %d   /   DC %d" % [terms, int(_check["total"]), int(_check["dc"])]
	_stamp_box.show()
	Motion.stamp_impact(_stamp_box)
	AudioManager.play_sfx("dice_success" if passed else "dice_fail")
	_hint.text = "点击任意处继续"


func _drop_chips() -> void:
	for beat: Modifier in _beats:
		if is_instance_valid(beat.chip):
			Motion.cancel(beat.chip, ^"scale")
			Motion.cancel(beat.chip, ^"position:y")
			_root.remove_child(beat.chip)
			beat.chip.queue_free()
		beat.chip = null
		beat.flight = null


func _stop_sequence() -> void:
	if _sequence != null:
		_sequence.kill()
		_sequence = null


func _stop_ink_tint() -> void:
	if _ink_tween != null:
		_ink_tween.kill()
		_ink_tween = null


func _clear_resonance() -> void:
	_resonance.clear()
	_dial.reset()
	_stage.clear_modifier_impact()
	_stop_ink_tint()
	Motion.cancel(_mist, ^"modulate:a")
	Motion.cancel(_number, ^"scale")
	Motion.cancel(_dc_badge, ^"scale")
	Motion.cancel(_divider, ^"scale")
	Motion.cancel(_divider, ^"modulate:a")
	_number.scale = Vector2.ONE
	_dc_badge.scale = Vector2.ONE
	_divider.scale = Vector2.ONE


func _dismiss() -> void:
	if _phase != "stamp" or Time.get_ticks_msec() < _stamp_locked_until:
		return
	_phase = "done"
	_clear_resonance()
	_stage.process_mode = Node.PROCESS_MODE_DISABLED
	_restore_hud(true)
	_sequence = create_tween()
	_sequence.tween_property(_root, "modulate:a", 0.0, HUD_FADE_SECONDS).set_trans(Tween.TRANS_SINE)
	_sequence.tween_callback(func() -> void:
		_root.hide()
		_restore_hud(false)
		_active = false
		completed.emit())
