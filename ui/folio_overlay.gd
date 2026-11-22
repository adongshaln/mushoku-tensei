extends CanvasLayer

const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const BACKDROP := preload("res://shaders/backdrop_blur_vignette.gdshader")
const HUD_FADE_SECONDS := 0.20

var canvas: Control
var binding: PanelContainer
var folio: PanelContainer
var page: VBoxContainer
var header: HBoxContainer
var title_label: Label
var title_font: SystemFont
var body_font: SystemFont
var _hud_opacities: Dictionary[CanvasItem, float] = {}


func build(title: String, dimensions: Vector2, show_spine: bool = false, spine_x: float = 0.295) -> void:
	layer = 115
	title_font = Kit.make_font(true)
	body_font = Kit.make_font()
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(canvas)
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	canvas.add_child(copy)
	var blur := ColorRect.new()
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = BACKDROP
	blur.material = material
	canvas.add_child(blur)
	blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var book := Kit.create_grimoire_book(dimensions, spine_x, show_spine)
	binding = book["binding"] as PanelContainer
	folio = book["spread"] as PanelContainer
	canvas.add_child(binding)
	binding.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	binding.offset_left = -dimensions.x * 0.5
	binding.offset_right = dimensions.x * 0.5
	binding.offset_top = -dimensions.y * 0.5
	binding.offset_bottom = dimensions.y * 0.5

	page = VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	folio.add_child(page)
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	page.add_child(header)
	var emblem := Kit.create_micro_icon("book", 28.0, Kit.WAX_GOLD)
	emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(emblem)
	title_label = Kit.create_label(title, 36, Kit.INK, title_font)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title_label)
	var close_button := Kit.create_icon_button("close", "合上  Esc", "dark_brass", title_font, 18, Kit.BRASS)
	close_button.custom_minimum_size = Vector2(138.0, 46.0)
	close_button.pressed.connect(close)
	header.add_child(close_button)
	page.add_child(Kit.create_gold_divider(0.0, true, 12.0))
	canvas.hide()


func is_open() -> bool:
	return canvas != null and canvas.visible


func reveal() -> void:
	_cover_hud()
	canvas.show()
	Motion.fade_in(canvas, 0.22)
	Motion.spring(binding, ^"scale", Vector2(0.955, 0.955), Vector2.ONE, 0.36, 9.2, 7.0)
	AudioManager.play_sfx("page_flip")


func close() -> void:
	if not is_open():
		return
	canvas.hide()
	_restore_hud(true)


func close_immediately() -> void:
	if canvas != null:
		canvas.hide()
	_hud_opacities.clear()


func _cover_hud() -> void:
	var hosts: Array[Node] = [get_tree().current_scene, StoryletScheduler]
	for host: Node in hosts:
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
	var snapshot := _hud_opacities.duplicate()
	_hud_opacities.clear()
	for item: CanvasItem in snapshot:
		if not is_instance_valid(item):
			continue
		if animated:
			Motion.fade_alpha(item, snapshot[item], HUD_FADE_SECONDS)
		else:
			Motion.cancel(item, ^"modulate:a")
			item.modulate.a = snapshot[item]


func _exit_tree() -> void:
	_restore_hud(false)


func clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func line(description: String, font_size: int = 20, color: Color = Kit.MUTED, display: bool = false) -> Label:
	var label := Kit.create_label(description, font_size, color, title_font if display else body_font)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func scroll_into(target: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target.add_child(scroll)
	Kit.style_scrollbar(scroll.get_v_scroll_bar())
	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.add_theme_constant_override("margin_right", 10)
	scroll.add_child(inset)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	inset.add_child(content)
	return content
