extends HBoxContainer

signal entry_selected(entry_id: String)

const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")

var _title_font: Font
var _body_font: Font
var _active_category := "all"
var _selected_entry_id := ""
var _built := false

var _progress_label: Label
var _unread_badge_holder: HBoxContainer
var _progress_bar: ProgressBar
var _cat_buttons: Dictionary[String, Button] = {}
var _list_vbox: VBoxContainer
var _reader_container: VBoxContainer


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
	_pick_initial_entry()
	refresh()


func set_category(category: String) -> void:
	_active_category = category
	refresh(true)


func select_entry(entry_id: String, mark_read_if_unlocked: bool = true) -> void:
	_selected_entry_id = entry_id
	if mark_read_if_unlocked and JournalManager.is_codex_unlocked(entry_id) and JournalManager.is_codex_unread(entry_id):
		JournalManager.mark_codex_read(entry_id)
	refresh(false, true)
	entry_selected.emit(entry_id)


func _pick_initial_entry() -> void:
	var entries: Array[Dictionary] = JournalManager.get_codex_entries("all")
	# Prefer first unlocked entry so the reading page is immediately inviting.
	for e: Dictionary in entries:
		if bool(e.get("unlocked", false)) and not bool(e.get("unread", false)):
			_selected_entry_id = str(e["id"])
			return
	if not entries.is_empty():
		_selected_entry_id = str(entries[0]["id"])


func _build_ui() -> void:
	# ── Left Page: Codex Progress, Categories & Entry Directory ──
	var left_margin := MarginContainer.new()
	left_margin.custom_minimum_size.x = 384.0
	left_margin.add_theme_constant_override("margin_top", 4)
	left_margin.add_theme_constant_override("margin_bottom", 4)
	add_child(left_margin)

	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 10)
	left_margin.add_child(left_col)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	left_col.add_child(title_row)
	var icon := Kit.create_micro_icon("book", 26.0, Kit.SAPPHIRE)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(icon)
	var heading := Kit.create_label("六面世界图鉴", 28, Kit.INK, _title_font)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(heading)

	_unread_badge_holder = HBoxContainer.new()
	_unread_badge_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_unread_badge_holder)

	# Progress card
	var prog_card := Kit.create_folio_panel(Kit.PAPER_DEEP, 14, 10, 2)
	left_col.add_child(prog_card)
	var prog_v := VBoxContainer.new()
	prog_v.add_theme_constant_override("separation", 6)
	prog_card.add_child(prog_v)
	_progress_label = Kit.create_label("已收录 0 / 0 篇", 15, Kit.INK, _body_font)
	prog_v.add_child(_progress_label)
	_progress_bar = Kit.create_meter(Kit.WAX_GOLD, Color("#d4c3a7"), 10.0)
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	prog_v.add_child(_progress_bar)

	# Category filter pills (compact single-row fit across 5 categories)
	var cat_flow := HBoxContainer.new()
	cat_flow.add_theme_constant_override("separation", 5)
	left_col.add_child(cat_flow)

	var cat_specs: Array[Array] = [["all", "全部"]]
	for cat: Dictionary in JournalManager.get_codex_categories():
		cat_specs.append([str(cat.get("id", "")), str(cat.get("short_name", cat.get("name", "")))])

	for spec: Array in cat_specs:
		var cid := str(spec[0])
		var cname := str(spec[1])
		var btn := Kit.create_tactile_button(cname, "secondary", _body_font, 13)
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL if cid != "all" else Control.SIZE_SHRINK_BEGIN
		btn.custom_minimum_size = Vector2(46.0 if cid == "all" else 68.0, 44.0)
		for st: String in ["normal", "hover", "pressed", "hover_pressed"]:
			var sb := btn.get_theme_stylebox(st)
			if sb is StyleBoxFlat:
				var copy := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
				copy.content_margin_left = 6
				copy.content_margin_right = 6
				btn.add_theme_stylebox_override(st, copy)
		var active_box := Kit.style(Color("#281c14ee"), 6, 6, 2, 1, Kit.BRASS)
		active_box.set_corner_radius_all(7)
		btn.add_theme_stylebox_override("pressed", active_box)
		btn.add_theme_stylebox_override("hover_pressed", active_box)
		btn.add_theme_color_override("font_pressed_color", Kit.IVORY)
		btn.add_theme_color_override("font_hover_pressed_color", Color("#fff6e0"))
		var captured := cid
		btn.pressed.connect(func() -> void:
			_active_category = captured
			refresh(true, false))
		cat_flow.add_child(btn)
		_cat_buttons[cid] = btn

	left_col.add_child(Kit.create_gold_divider(0.0, false, 6.0))

	# Entry Directory List
	var dir_scroll := ScrollContainer.new()
	dir_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dir_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dir_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Kit.style_scrollbar(dir_scroll.get_v_scroll_bar())
	left_col.add_child(dir_scroll)

	var dir_pad := MarginContainer.new()
	dir_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dir_pad.add_theme_constant_override("margin_right", 8)
	dir_pad.add_theme_constant_override("margin_top", 2)
	dir_pad.add_theme_constant_override("margin_bottom", 8)
	dir_scroll.add_child(dir_pad)

	_list_vbox = VBoxContainer.new()
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_vbox.add_theme_constant_override("separation", 7)
	dir_pad.add_child(_list_vbox)

	# ── Right Page: Light-Novel Annotated Reading Folio ──
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Kit.style_scrollbar(right_scroll.get_v_scroll_bar())
	add_child(right_scroll)

	var right_pad := MarginContainer.new()
	right_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_pad.add_theme_constant_override("margin_left", 6)
	right_pad.add_theme_constant_override("margin_right", 14)
	right_pad.add_theme_constant_override("margin_top", 4)
	right_pad.add_theme_constant_override("margin_bottom", 14)
	right_scroll.add_child(right_pad)

	_reader_container = VBoxContainer.new()
	_reader_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reader_container.add_theme_constant_override("separation", 14)
	right_pad.add_child(_reader_container)


func refresh(animate_list: bool = false, animate_reader: bool = false) -> void:
	if not _built:
		return
	var prog := JournalManager.get_codex_progress()
	var unlocked := int(prog.get("unlocked", 0))
	var total := int(prog.get("total", 0))
	var unread := int(prog.get("unread", 0))
	var pct := roundi(float(prog.get("ratio", 0.0)) * 100.0)
	_progress_label.text = "已收录 %d / %d 篇（收集度 %d%%）" % [unlocked, total, pct]
	_progress_bar.max_value = maxi(1, total)
	_progress_bar.value = unlocked

	for child: Node in _unread_badge_holder.get_children():
		_unread_badge_holder.remove_child(child)
		child.queue_free()
	if unread > 0:
		_unread_badge_holder.add_child(Kit.create_status_badge("● %d 未读" % unread, true, _body_font, 13))

	for cid: String in _cat_buttons:
		_cat_buttons[cid].set_pressed_no_signal(cid == _active_category)

	var entries: Array[Dictionary] = JournalManager.get_codex_entries(_active_category)
	var selection_in_list := false
	for e: Dictionary in entries:
		if str(e["id"]) == _selected_entry_id:
			selection_in_list = true
			break
	if not selection_in_list and not entries.is_empty():
		_selected_entry_id = str(entries[0]["id"])

	# Rebuild directory list
	for child: Node in _list_vbox.get_children():
		_list_vbox.remove_child(child)
		child.queue_free()

	for entry: Dictionary in entries:
		_list_vbox.add_child(_build_directory_item(entry))

	if animate_list:
		Motion.fade_in(_list_vbox, 0.18)

	_rebuild_reader(animate_reader)


func _build_directory_item(entry: Dictionary) -> Button:
	var eid := str(entry["id"])
	var unlocked := bool(entry.get("unlocked", false))
	var unread := bool(entry.get("unread", false))
	var selected := eid == _selected_entry_id

	var btn := Button.new()
	btn.custom_minimum_size.y = 54.0
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var bg: Color
	var rim: Color
	var bw := 1
	if selected:
		bg = Color("#fcf6ea") if unlocked else Color("#ece3d4")
		rim = Kit.AMBER
		bw = 2
	elif unlocked:
		bg = Color("#f4ead8")
		rim = Color("#c7a268") if unread else Color("#bba281")
	else:
		bg = Color("#e7decb")
		rim = Color("#bfa98d")

	var norm := Kit.style(bg, 12, 8, 2 if selected else 0, bw, rim)
	norm.set_corner_radius_all(7)
	var hov := Kit.style(bg.lightened(0.04), 12, 8, 3, bw, Kit.AMBER)
	hov.set_corner_radius_all(7)
	btn.add_theme_stylebox_override("normal", norm)
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", hov)
	btn.add_theme_stylebox_override("focus", hov)
	Motion.attach_button_feel(btn, 1.015, 0.98, false)
	AudioManager.bind_ui(btn)

	var inner := HBoxContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("separation", 8)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_bottom", 6)
	btn.add_child(pad)
	pad.add_child(inner)

	if unread:
		var dot := Kit.create_label("●", 14, Kit.WAX_GOLD, _body_font)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inner.add_child(dot)

	var text_v := VBoxContainer.new()
	text_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_v.alignment = BoxContainer.ALIGNMENT_CENTER
	text_v.add_theme_constant_override("separation", 1)
	inner.add_child(text_v)

	var main_title := str(entry.get("title", "")) if unlocked else "？？？ · 待旅途发掘"
	var t_lbl := Kit.create_label(main_title, 17, Kit.INK if unlocked else Color("#8f7e6b"), _title_font if unlocked else _body_font)
	t_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_v.add_child(t_lbl)

	var cat_short := str(entry.get("category_short", ""))
	var sub_text := "%s · %s" % [cat_short, "新收录" if unread else ("已收录" if unlocked else "未发掘")]
	var s_lbl := Kit.create_label(sub_text, 12, Kit.AMBER if unread else Color("#8d7963"), _body_font)
	text_v.add_child(s_lbl)

	var captured := eid
	btn.pressed.connect(func() -> void:
		select_entry(captured, true))
	return btn


func _rebuild_reader(animate: bool) -> void:
	for child: Node in _reader_container.get_children():
		_reader_container.remove_child(child)
		child.queue_free()

	var entry := JournalManager.get_codex_entry(_selected_entry_id)
	if entry.is_empty():
		return

	var unlocked := bool(entry.get("unlocked", false))
	var cat_name := str(entry.get("category_name", ""))
	var accent := Color(str(entry.get("accent_hex", "#8c6548")))

	if not unlocked:
		var locked_panel := Kit.create_folio_panel(Kit.PAPER_DEEP, 36, 38, 4)
		_reader_container.add_child(locked_panel)
		var lv := VBoxContainer.new()
		lv.add_theme_constant_override("separation", 16)
		locked_panel.add_child(lv)

		var badge_r := HBoxContainer.new()
		badge_r.alignment = BoxContainer.ALIGNMENT_CENTER
		lv.add_child(badge_r)
		badge_r.add_child(Kit.create_badge("%s · 未启封残页" % cat_name, Color("#7e6c58"), _body_font, 15))

		var icon_c := CenterContainer.new()
		lv.add_child(icon_c)
		icon_c.add_child(Kit.create_micro_icon("star", 52.0, Color("#b69b75")))

		var l_title := Kit.create_label("？？？ · 待旅途发掘", 30, Color("#7e6a56"), _title_font)
		l_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lv.add_child(l_title)

		lv.add_child(Kit.create_gold_divider(0.0, true, 12.0))

		var hint_text := str(entry.get("discovery_hint", "随着你的脚步踏遍六面世界，该词条将在旅途中自动收录。"))
		var hint_lbl := Kit.create_label("发掘线索：" + hint_text, 18, Kit.MUTED, _body_font)
		hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lv.add_child(hint_lbl)
	else:
		var sheet := Kit.create_folio_panel(Color("#fbf5ea"), 30, 26, 4)
		_reader_container.add_child(sheet)
		var sv := VBoxContainer.new()
		sv.add_theme_constant_override("separation", 14)
		sheet.add_child(sv)

		# Top meta ribbon
		var top_row := HBoxContainer.new()
		top_row.add_theme_constant_override("separation", 10)
		sv.add_child(top_row)
		top_row.add_child(Kit.create_badge(cat_name, accent, _body_font, 14))
		var src_text := str(entry.get("unlocked_source", "手账收录"))
		var src_lbl := Kit.create_label("收录契机：" + src_text, 14, Kit.MUTED, _body_font)
		src_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		src_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		top_row.add_child(src_lbl)
		top_row.add_child(Kit.create_status_badge("已收录", true, _body_font, 13))

		# Title & Poetic Subtitle
		var title_lbl := Kit.create_label(str(entry.get("title", "")), 34, Kit.INK, _title_font)
		sv.add_child(title_lbl)

		var sub_text := str(entry.get("subtitle", ""))
		if not sub_text.is_empty():
			var sub_lbl := Kit.create_label(sub_text, 18, Kit.SAPPHIRE, _body_font)
			sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sv.add_child(sub_lbl)

		sv.add_child(Kit.create_gold_divider(0.0, true, 12.0))

		# Highlighted Lead Summary Box
		var summary_text := str(entry.get("summary", ""))
		if not summary_text.is_empty():
			var quote_box := PanelContainer.new()
			var qstyle := Kit.style(Kit.PAPER_DEEP, 18, 14, 1, 1, Color("#b99667"))
			qstyle.border_width_left = 4
			qstyle.border_color = Kit.WAX_GOLD
			qstyle.set_corner_radius_all(6)
			quote_box.add_theme_stylebox_override("panel", qstyle)
			sv.add_child(quote_box)

			var sum_lbl := Kit.create_label(summary_text, 17, Kit.INK, _body_font)
			sum_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sum_lbl.add_theme_constant_override("line_spacing", 5)
			quote_box.add_child(sum_lbl)

		# Light-Novel Annotated Body Paragraphs
		var body_raw := str(entry.get("body", ""))
		var paragraphs := body_raw.split("\n\n", false)
		for para: String in paragraphs:
			var p_lbl := Kit.create_label(para.strip_edges(), 18, Color("#4a3a2e"), _body_font)
			p_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			p_lbl.add_theme_constant_override("line_spacing", 8)
			sv.add_child(p_lbl)

		sv.add_child(Kit.create_gold_divider(0.0, false, 8.0))

		# Footer unlock provenance
		var udate := str(entry.get("unlocked_date", ""))
		var foot_text := "收录于 %s  ·  六面世界见闻录" % (udate if not udate.is_empty() else "旅途启程之际")
		var foot_lbl := Kit.create_label(foot_text, 13, Color("#8b7660"), _body_font)
		foot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sv.add_child(foot_lbl)

	if animate:
		Motion.fade_in(_reader_container, 0.22)
		Motion.spring(_reader_container, ^"position:x", 18.0, 0.0, 0.30, 9.0, 7.0)
