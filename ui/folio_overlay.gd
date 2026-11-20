extends CanvasLayer

const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const BACKDROP := preload("res://shaders/backdrop_blur_vignette.gdshader")

var canvas: Control
var folio: PanelContainer
var page: VBoxContainer
var header: HBoxContainer
var title_font: SystemFont
var body_font: SystemFont


func build(title: String, dimensions: Vector2) -> void:
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

	folio = Kit.create_folio_panel(Kit.PAPER, 32, 25, 14)
	folio.custom_minimum_size = dimensions
	canvas.add_child(folio)
	folio.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	folio.offset_left = -dimensions.x * 0.5
	folio.offset_right = dimensions.x * 0.5
	folio.offset_top = -dimensions.y * 0.5
	folio.offset_bottom = dimensions.y * 0.5

	page = VBoxContainer.new()
	page.add_theme_constant_override("separation", 15)
	folio.add_child(page)
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	page.add_child(header)
	var heading := Kit.create_label(title, 39, Kit.INK, title_font)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var close_button := Kit.create_tactile_button("合上", "secondary", title_font, 21)
	close_button.custom_minimum_size = Vector2(110.0, 49.0)
	close_button.pressed.connect(close)
	header.add_child(close_button)
	canvas.hide()


func is_open() -> bool:
	return canvas != null and canvas.visible


func reveal() -> void:
	canvas.show()
	Motion.fade_in(canvas, 0.22)


func close() -> void:
	canvas.hide()


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
	inset.add_theme_constant_override("margin_right", 12)
	scroll.add_child(inset)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	inset.add_child(content)
	return content
