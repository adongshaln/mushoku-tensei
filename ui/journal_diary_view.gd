extends HBoxContainer

const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")

const FILTER_DEFS: Array[Array] = [
	["all", "全部手记"],
	["travel", "行程"],
	["economy", "商贸"],
	["dice", "命运"],
	["milestone", "里程碑"]
]

var _title_font: Font
var _body_font: Font
var _active_category := "all"
var _keyword := ""
var _newest_first := true
var _built := false

var _count_summary_label: Label
var _count_detail_label: Label
var _filter_buttons: Dictionary[String, Button] = {}
var _search_input: LineEdit
var _sort_button: Button
var _header_summary_label: Label
var _timeline_vbox: VBoxContainer


func setup(title_font: Font, body_font: Font) -> void:
	_title_font = title_font
	_body_font = body_font
	if _built:
		refresh()
		return
	_built = true
	add_theme_constant_override("separation", 42)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	refresh()


func set_filter(category: String) -> void:
	_active_category = category
	refresh()


func set_keyword(query: String) -> void:
	_keyword = query
	if _search_input != null and _search_input.text != query:
		_search_input.text = query
	refresh()


func set_newest_first(newest: bool) -> void:
	_newest_first = newest
	refresh()


func _build_ui() -> void:
	# ── Left Page: Diary Archive Controls & Filters ──
	var left_margin := MarginContainer.new()
	left_margin.custom_minimum_size.x = 374.0
	left_margin.add_theme_constant_override("margin_top", 4)
	left_margin.add_theme_constant_override("margin_bottom", 4)
	add_child(left_margin)

	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 12)
	left_margin.add_child(left_col)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	left_col.add_child(title_row)
	var icon := Kit.create_micro_icon("quill", 26.0, Kit.WAX_GOLD)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(icon)
	var heading := Kit.create_label("旅途日记", 30, Kit.INK, _title_font)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(heading)

	var sub := Kit.create_label("以甲龙历时序自动镌刻足迹、商贸与命运瞬间。", 15, Kit.MUTED, _body_font)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_col.add_child(sub)

	left_col.add_child(Kit.create_gold_divider(0.0, true, 10.0))

	# Summary Card
	var stats_card := Kit.create_folio_panel(Kit.PAPER_DEEP, 16, 12, 2)
	left_col.add_child(stats_card)
	var stats_v := VBoxContainer.new()
	stats_v.add_theme_constant_override("separation", 4)
	stats_card.add_child(stats_v)
	stats_v.add_child(Kit.create_label("手账收录统计", 14, Kit.MUTED, _body_font))
	_count_summary_label = Kit.create_label("共 0 篇手记", 24, Kit.INK, _title_font)
	stats_v.add_child(_count_summary_label)
	_count_detail_label = Kit.create_label("行程 0 · 商贸 0 · 命运 0 · 里程碑 0", 14, Kit.MUTED, _body_font)
	stats_v.add_child(_count_detail_label)

	# Category Filter Pills
	left_col.add_child(Kit.create_label("按分类筛选", 15, Kit.MUTED, _body_font))
	var filter_flow := HFlowContainer.new()
	filter_flow.add_theme_constant_override("h_separation", 8)
	filter_flow.add_theme_constant_override("v_separation", 8)
	left_col.add_child(filter_flow)

	for spec: Array in FILTER_DEFS:
		var cat_id := str(spec[0])
		var cat_label := str(spec[1])
		var pill := Kit.create_tactile_button(cat_label, "secondary", _body_font, 15)
		pill.toggle_mode = true
		pill.custom_minimum_size = Vector2(110.0, 44.0)
		var active_box := Kit.style(Color("#281c14ee"), 14, 8, 3, 1, Kit.BRASS)
		active_box.set_corner_radius_all(8)
		pill.add_theme_stylebox_override("pressed", active_box)
		pill.add_theme_stylebox_override("hover_pressed", active_box)
		pill.add_theme_color_override("font_pressed_color", Kit.IVORY)
		pill.add_theme_color_override("font_hover_pressed_color", Color("#fff6e0"))
		var captured := cat_id
		pill.pressed.connect(func() -> void:
			_active_category = captured
			refresh(true))
		filter_flow.add_child(pill)
		_filter_buttons[cat_id] = pill

	left_col.add_child(Kit.create_gold_divider(0.0, false, 8.0))

	# Keyword Search Input
	left_col.add_child(Kit.create_label("检索手记", 15, Kit.MUTED, _body_font))
	_search_input = LineEdit.new()
	_search_input.placeholder_text = "输入地名、事件或关键词..."
	_search_input.custom_minimum_size.y = 46.0
	_search_input.add_theme_font_override("font", _body_font)
	_search_input.add_theme_font_size_override("font_size", 16)
	_search_input.add_theme_color_override("font_color", Kit.INK)
	_search_input.add_theme_color_override("font_placeholder_color", Color("#94806b"))
	_search_input.add_theme_stylebox_override("normal", Kit.style(Color("#fbf5ea"), 14, 8, 1, 1, Color("#8a6a44")))
	_search_input.add_theme_stylebox_override("focus", Kit.style(Color("#fffaf0"), 14, 8, 2, 2, Kit.AMBER))
	_search_input.text_changed.connect(func(new_text: String) -> void:
		_keyword = new_text
		refresh(false))
	left_col.add_child(_search_input)

	# Sort Toggle
	_sort_button = Kit.create_tactile_button("时间顺序：最新在前 ↓", "subtle", _body_font, 15)
	_sort_button.custom_minimum_size.y = 46.0
	_sort_button.pressed.connect(func() -> void:
		_newest_first = not _newest_first
		refresh(true))
	left_col.add_child(_sort_button)

	# Legend hint card at bottom of left column
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(spacer)

	var legend_card := Kit.create_folio_panel(Color("#efe5d4"), 14, 10, 0)
	left_col.add_child(legend_card)
	var legend_v := VBoxContainer.new()
	legend_v.add_theme_constant_override("separation", 6)
	legend_card.add_child(legend_v)
	legend_v.add_child(Kit.create_label("手记色温标识", 14, Kit.MUTED, _body_font))
	var badges_r := HFlowContainer.new()
	badges_r.add_theme_constant_override("h_separation", 8)
	badges_r.add_theme_constant_override("v_separation", 6)
	legend_v.add_child(badges_r)
	badges_r.add_child(Kit.create_status_badge("大成功 / 里程碑", true, _body_font, 13))
	badges_r.add_child(Kit.create_status_badge("险情 / 断粮 / 大失败", false, _body_font, 13))

	# ── Right Page: Dragon Calendar Timeline ──
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 10)
	add_child(right_col)

	var right_hdr := HBoxContainer.new()
	right_hdr.add_theme_constant_override("separation", 12)
	right_col.add_child(right_hdr)
	_header_summary_label = Kit.create_label("甲龙历旅途时间轴", 22, Kit.INK, _title_font)
	_header_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_hdr.add_child(_header_summary_label)

	right_col.add_child(Kit.create_gold_divider(0.0, false, 6.0))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Kit.style_scrollbar(scroll.get_v_scroll_bar())
	right_col.add_child(scroll)

	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.add_theme_constant_override("margin_left", 4)
	inset.add_theme_constant_override("margin_right", 12)
	inset.add_theme_constant_override("margin_top", 4)
	inset.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(inset)

	_timeline_vbox = VBoxContainer.new()
	_timeline_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline_vbox.add_theme_constant_override("separation", 12)
	inset.add_child(_timeline_vbox)


func refresh(animate_list: bool = false) -> void:
	if not _built:
		return
	var counts: Dictionary[String, int] = JournalManager.get_diary_category_counts()
	var total := int(counts.get("all", 0))
	_count_summary_label.text = "共 %d 篇旅途手记" % total
	_count_detail_label.text = "行程 %d · 商贸 %d · 命运 %d · 里程碑 %d" % [
		int(counts.get("travel", 0)),
		int(counts.get("economy", 0)),
		int(counts.get("dice", 0)),
		int(counts.get("milestone", 0))
	]

	for spec: Array in FILTER_DEFS:
		var cat_id := str(spec[0])
		var base_label := str(spec[1])
		var btn: Button = _filter_buttons[cat_id]
		var c := int(counts.get(cat_id, 0))
		btn.text = "%s (%d)" % [base_label, c]
		btn.set_pressed_no_signal(cat_id == _active_category)

	_sort_button.text = "时间顺序：最新在前 ↓" if _newest_first else "时间顺序：最早在前 ↑"

	var entries: Array[Dictionary] = JournalManager.get_diary_entries(_active_category, _keyword, _newest_first)
	var cat_title := "全部手记"
	for spec: Array in FILTER_DEFS:
		if str(spec[0]) == _active_category:
			cat_title = str(spec[1])
			break
	_header_summary_label.text = "甲龙历时间轴 · %s（%d 篇）" % [cat_title, entries.size()]

	for child: Node in _timeline_vbox.get_children():
		_timeline_vbox.remove_child(child)
		child.queue_free()

	if entries.is_empty():
		var empty_card := Kit.create_folio_panel(Color("#efe5d4"), 24, 20, 0)
		var empty_lbl := Kit.create_label(
			"未检索到符合条件的旅途手记。" if not _keyword.strip_edges().is_empty() else "这一页仍留着清淡墨香，随着旅途推进将自动写下你的经历。",
			18,
			Color("#8b7660"),
			_body_font
		)
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_card.add_child(empty_lbl)
		_timeline_vbox.add_child(empty_card)
		return

	for i: int in range(entries.size()):
		var entry: Dictionary = entries[i]
		_timeline_vbox.add_child(_build_entry_row(entry, i == entries.size() - 1))

	if animate_list:
		Motion.fade_in(_timeline_vbox, 0.20)
		Motion.spring(_timeline_vbox, ^"position:x", 16.0, 0.0, 0.28, 9.0, 7.0)


func _build_entry_row(entry: Dictionary, is_last: bool) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)

	var tone := str(entry.get("tone", "neutral"))
	var cat := str(entry.get("category", "milestone"))
	var node_color := Kit.WAX_GOLD if tone == "positive" else (Kit.BLUE if tone == "negative" else Color("#8f7354"))

	# Left golden timeline rail
	var rail := VBoxContainer.new()
	rail.custom_minimum_size.x = 22.0
	rail.alignment = BoxContainer.ALIGNMENT_BEGIN
	rail.add_theme_constant_override("separation", 4)
	row.add_child(rail)

	var top_pad := Control.new()
	top_pad.custom_minimum_size.y = 12.0
	rail.add_child(top_pad)
	var icon_kind := "star" if tone != "negative" else "eye"
	if cat == "travel":
		icon_kind = "compass"
	elif cat == "economy":
		icon_kind = "bag"
	var pin := Kit.create_micro_icon(icon_kind, 18.0, node_color)
	pin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rail.add_child(pin)

	if not is_last:
		var stem := ColorRect.new()
		stem.color = Color(node_color, 0.38)
		stem.custom_minimum_size = Vector2(2.0, 26.0)
		stem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		stem.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rail.add_child(stem)

	# Right parchment card
	var bg := Color("#fbf5ea") if tone == "positive" else (Color("#f0f3f6") if tone == "negative" else Kit.PAPER_DEEP)
	var rim := Color("#c69447") if tone == "positive" else (Color("#698eb0") if tone == "negative" else Color("#9a7952"))
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style_box := Kit.style(bg, 18, 13, 2, 2 if tone != "neutral" else 1, rim)
	style_box.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", style_box)
	row.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 7)
	card.add_child(vb)

	# Card header: badge + title + date/location
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 10)
	vb.add_child(hdr)

	var badge_text := str(entry.get("badge", JournalManager.CATEGORY_LABELS.get(cat, "手记")))
	if tone == "positive":
		hdr.add_child(Kit.create_status_badge(badge_text, true, _body_font, 13))
	elif tone == "negative":
		hdr.add_child(Kit.create_status_badge(badge_text, false, _body_font, 13))
	else:
		hdr.add_child(Kit.create_badge(badge_text, Color("#6e5b47"), _body_font, 13))

	var title_lbl := Kit.create_label(str(entry.get("title", "")), 20, Kit.INK, _title_font)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hdr.add_child(title_lbl)

	var date_lbl := Kit.create_label(str(entry.get("date_text", "")), 14, Kit.SAPPHIRE, _body_font)
	date_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hdr.add_child(date_lbl)

	# Body text
	var body_text := str(entry.get("body", ""))
	if not body_text.is_empty():
		var body_lbl := Kit.create_label(body_text, 16, Kit.MUTED, _body_font)
		body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(body_lbl)

	# Footer metadata chips (location + dice details if present)
	var meta: Dictionary = entry.get("meta", {}) if entry.get("meta") is Dictionary else {}
	var footer := HFlowContainer.new()
	footer.add_theme_constant_override("h_separation", 8)
	footer.add_theme_constant_override("v_separation", 4)
	var loc := str(entry.get("location", ""))
	if not loc.is_empty():
		footer.add_child(Kit.create_chip("地点 · " + loc, _body_font, 13))
	if cat == "dice" and meta.has("roll") and meta.has("dc"):
		var roll_text := "d20 = %d / DC %d · %s" % [
			int(meta.get("roll", 0)),
			int(meta.get("dc", 10)),
			str(meta.get("skill_name", "检定"))
		]
		footer.add_child(Kit.create_chip(roll_text, _body_font, 13))
	if footer.get_child_count() > 0:
		vb.add_child(footer)

	return row
