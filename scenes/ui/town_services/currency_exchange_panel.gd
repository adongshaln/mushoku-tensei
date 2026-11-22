extends PanelContainer
class_name CurrencyExchangePanel

signal exchange_completed(result: Dictionary)

const ThemeKit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")

var _title_font: Font
var _body_font: Font
var _city_id := "city_rikarisu"
var _venue_type := "adventurer_guild"
var _compact := false
var _from_currency := "demon_ore"
var _to_currency := "millis"
var _amount_units := 1000
var _rebuilding := false

var _venue_title_label: Label
var _venue_badge: PanelContainer
var _from_select: OptionButton
var _to_select: OptionButton
var _from_balance_label: Label
var _to_balance_label: Label
var _amount_spin: SpinBox
var _amount_formatted_label: Label
var _rate_value_label: Label
var _fee_value_label: Label
var _actual_pay_label: Label
var _received_value_label: Label
var _refund_note_label: Label
var _confirm_button: Button
var _swap_button: Button
var _step_buttons_box: HFlowContainer


func setup(city_id: String, venue_type: String, title_font: Font, body_font: Font, compact: bool = false) -> void:
	_city_id = EconomyManager.normalize_city_id(city_id)
	_venue_type = venue_type
	_title_font = title_font
	_body_font = body_font
	_compact = compact
	_choose_default_pair()
	_build_ui()
	refresh()


func configure(city_id: String, venue_type: String) -> void:
	_city_id = EconomyManager.normalize_city_id(city_id)
	_venue_type = venue_type
	_choose_default_pair()
	refresh()


func set_pair_and_amount(from_currency: String, to_currency: String, units: int) -> void:
	_from_currency = from_currency
	_to_currency = to_currency
	_amount_units = maxi(1, units)
	refresh()


func _choose_default_pair() -> void:
	var local_id := EconomyManager.get_local_currency_id(_city_id)
	var held := EconomyManager.get_held_currencies(false)
	var best_foreign := ""
	for entry: Dictionary in held:
		var cid := str(entry.get("currency_id", ""))
		if cid != local_id and int(entry.get("min_units", 0)) > 0:
			best_foreign = cid
			break
	if not best_foreign.is_empty():
		_from_currency = best_foreign
		_to_currency = local_id
	else:
		_from_currency = local_id
		_to_currency = "millis" if local_id != "millis" else "asura"
	var bal := EconomyManager.get_balance(_from_currency)
	var u_from := EconomyManager.get_unit_base_value(_from_currency)
	@warning_ignore("integer_division")
	var default_units := maxi(1, 1000 / u_from)
	if bal > 0:
		_amount_units = mini(bal, default_units)
	else:
		_amount_units = default_units


func _build_ui() -> void:
	for child: Node in get_children():
		child.queue_free()

	var fill := ThemeKit.PAPER_DEEP if _compact else ThemeKit.PAPER
	var pad_x := 18 if _compact else 22
	var pad_y := 14 if _compact else 18
	var border_col := Color("#8a6842") if _venue_type == "adventurer_guild" else Color("#7d6245")
	add_theme_stylebox_override("panel", ThemeKit.style(fill, pad_x, pad_y, 4, 2, border_col))
	ThemeKit.bind_paper(self, ThemeKit.paper_material(Vector2(540, 380), not _compact))

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10 if _compact else 13)
	add_child(root)

	# Header Row
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)

	_venue_title_label = ThemeKit.create_label("官方免手续费换汇", 22 if _compact else 25, ThemeKit.INK, _title_font)
	_venue_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_venue_title_label)

	var is_guild := _venue_type == "adventurer_guild"
	_venue_badge = ThemeKit.create_badge(
		"官方免手续费 · 0%" if is_guild else "代兑手续费 · 5%",
		ThemeKit.GREEN if is_guild else ThemeKit.AMBER,
		_body_font,
		15
	)
	header.add_child(_venue_badge)

	root.add_child(ThemeKit.create_gold_divider(0.0, false, 8.0))

	# Currency Pair Selector Row
	var pair_row := HBoxContainer.new()
	pair_row.add_theme_constant_override("separation", 12)
	root.add_child(pair_row)

	var from_col := VBoxContainer.new()
	from_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	from_col.add_theme_constant_override("separation", 4)
	pair_row.add_child(from_col)

	var from_hdr := HBoxContainer.new()
	from_col.add_child(from_hdr)
	var from_lbl := ThemeKit.create_label("兑出货币", 15, ThemeKit.MUTED, _body_font)
	from_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	from_hdr.add_child(from_lbl)
	_from_balance_label = ThemeKit.create_label("", 15, ThemeKit.INK, _body_font)
	from_hdr.add_child(_from_balance_label)

	_from_select = _create_parchment_option()
	_from_select.item_selected.connect(_on_from_selected)
	from_col.add_child(_from_select)

	_swap_button = ThemeKit.create_tactile_button("⇄", "secondary", _body_font, 20)
	_swap_button.custom_minimum_size = Vector2(52.0, 46.0)
	_swap_button.size_flags_vertical = Control.SIZE_SHRINK_END
	_swap_button.pressed.connect(_on_swap_pressed)
	pair_row.add_child(_swap_button)

	var to_col := VBoxContainer.new()
	to_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	to_col.add_theme_constant_override("separation", 4)
	pair_row.add_child(to_col)

	var to_hdr := HBoxContainer.new()
	to_col.add_child(to_hdr)
	var to_lbl := ThemeKit.create_label("兑入货币", 15, ThemeKit.MUTED, _body_font)
	to_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	to_hdr.add_child(to_lbl)
	_to_balance_label = ThemeKit.create_label("", 15, ThemeKit.INK, _body_font)
	to_hdr.add_child(_to_balance_label)

	_to_select = _create_parchment_option()
	_to_select.item_selected.connect(_on_to_selected)
	to_col.add_child(_to_select)

	# Amount Input Row
	var amount_row := HBoxContainer.new()
	amount_row.add_theme_constant_override("separation", 12)
	root.add_child(amount_row)

	var amount_lbl := ThemeKit.create_label("兑换额（最小币单位）", 15, ThemeKit.MUTED, _body_font)
	amount_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	amount_row.add_child(amount_lbl)

	_amount_spin = SpinBox.new()
	_amount_spin.min_value = 1
	_amount_spin.max_value = 10000000
	_amount_spin.step = 1
	_amount_spin.value = _amount_units
	_amount_spin.custom_minimum_size = Vector2(165.0, 44.0)
	_style_spinbox(_amount_spin)
	_amount_spin.value_changed.connect(_on_amount_changed)
	amount_row.add_child(_amount_spin)

	_amount_formatted_label = ThemeKit.create_label("", 18, ThemeKit.INK, _title_font)
	_amount_formatted_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_amount_formatted_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_amount_formatted_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	amount_row.add_child(_amount_formatted_label)

	# Quick Step Buttons
	_step_buttons_box = HFlowContainer.new()
	_step_buttons_box.add_theme_constant_override("h_separation", 6)
	_step_buttons_box.add_theme_constant_override("v_separation", 6)
	root.add_child(_step_buttons_box)

	for spec: Dictionary in [
		{"label": "+10", "delta": 10, "w": 56.0},
		{"label": "+100", "delta": 100, "w": 64.0},
		{"label": "+500", "delta": 500, "w": 64.0},
		{"label": "+1000", "delta": 1000, "w": 72.0},
		{"label": "半数", "mode": "half", "w": 58.0},
		{"label": "全部", "mode": "all", "w": 58.0},
		{"label": "取整无损", "mode": "snap", "w": 92.0}
	]:
		var btn := ThemeKit.create_tactile_button(str(spec["label"]), "subtle", _body_font, 14)
		for state_name: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var sb := btn.get_theme_stylebox(state_name)
			if sb is StyleBoxFlat:
				var copy := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
				copy.content_margin_left = 10
				copy.content_margin_right = 10
				btn.add_theme_stylebox_override(state_name, copy)
		btn.custom_minimum_size = Vector2(float(spec["w"]), 44.0)
		if spec.has("delta"):
			var delta := int(spec["delta"])
			btn.pressed.connect(func() -> void:
				_set_amount_units(_amount_units + delta))
		else:
			var mode := str(spec["mode"])
			btn.pressed.connect(func() -> void:
				_apply_quick_amount(mode))
		_step_buttons_box.add_child(btn)

	# Quote Summary Box
	var summary_card := PanelContainer.new()
	var sum_style := ThemeKit.style(Color("#fbf5ea"), 16, 12, 2, 1, Color("#b99667"))
	sum_style.set_corner_radius_all(8)
	summary_card.add_theme_stylebox_override("panel", sum_style)
	root.add_child(summary_card)

	var sum_vbox := VBoxContainer.new()
	sum_vbox.add_theme_constant_override("separation", 6)
	summary_card.add_child(sum_vbox)

	var info_grid := GridContainer.new()
	info_grid.columns = 2
	info_grid.add_theme_constant_override("h_separation", 16)
	info_grid.add_theme_constant_override("v_separation", 5)
	sum_vbox.add_child(info_grid)

	_rate_value_label = _add_quote_row(info_grid, "公定牌价", ThemeKit.INK, 16)
	_fee_value_label = _add_quote_row(info_grid, "手续费", ThemeKit.GREEN if is_guild else ThemeKit.AMBER, 16)
	_actual_pay_label = _add_quote_row(info_grid, "实际扣除", ThemeKit.INK, 17)
	_received_value_label = _add_quote_row(info_grid, "预计实得", ThemeKit.BLUE, 21)

	_refund_note_label = ThemeKit.create_label("", 14, ThemeKit.MUTED, _body_font)
	_refund_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sum_vbox.add_child(_refund_note_label)

	# Confirm Action Button
	_confirm_button = ThemeKit.create_tactile_button(
		"确认官方换汇（免手续费）" if is_guild else "确认代兑货币（含 5% 手续费）",
		"accent" if is_guild else "primary",
		_body_font,
		19
	)
	_confirm_button.custom_minimum_size.y = 50.0
	_confirm_button.pressed.connect(_on_confirm_pressed)
	root.add_child(_confirm_button)


func _add_quote_row(grid: GridContainer, key_text: String, value_color: Color, value_size: int) -> Label:
	var k := ThemeKit.create_label(key_text, 15, ThemeKit.MUTED, _body_font)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(k)
	var v := ThemeKit.create_label("—", value_size, value_color, _title_font if value_size >= 19 else _body_font)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(v)
	return v


func refresh() -> void:
	if _from_select == null:
		return
	_rebuilding = true
	var venue := EconomyManager.get_venue_def(_venue_type)
	if _venue_title_label != null:
		_venue_title_label.text = str(venue.get("name", "货币兑换"))

	var order := EconomyManager.get_currency_order()
	_populate_option(_from_select, order, _from_currency)
	_populate_option(_to_select, order, _to_currency)
	_amount_spin.value = _amount_units
	_rebuilding = false
	_update_quote_display()


func _populate_option(opt: OptionButton, order: Array[String], selected_id: String) -> void:
	opt.clear()
	var selected_idx := 0
	for i: int in range(order.size()):
		var cid := order[i]
		var def := EconomyManager.get_currency_def(cid)
		var label := "%s（×%.2f）" % [str(def.get("short_name", cid)), float(def.get("multiplier", 1.0))]
		opt.add_item(label, i)
		opt.set_item_metadata(i, cid)
		if cid == selected_id:
			selected_idx = i
	opt.select(selected_idx)


func _update_quote_display() -> void:
	var from_bal := EconomyManager.get_balance(_from_currency)
	var to_bal := EconomyManager.get_balance(_to_currency)
	_from_balance_label.text = "持有：%s" % EconomyManager.format_currency(_from_currency, from_bal)
	_to_balance_label.text = "持有：%s" % EconomyManager.format_currency(_to_currency, to_bal)
	_amount_formatted_label.text = EconomyManager.format_currency(_from_currency, _amount_units)

	var quote := EconomyManager.quote_exchange(_from_currency, _to_currency, _amount_units, _venue_type, _city_id)
	var rate_text := str(quote.get("rate_text", EconomyManager.get_exchange_rate_text(_from_currency, _to_currency)))
	_rate_value_label.text = rate_text

	if not bool(quote.get("ok", false)):
		_fee_value_label.text = "—"
		_actual_pay_label.text = "—"
		_received_value_label.text = "无法兑换"
		_received_value_label.add_theme_color_override("font_color", ThemeKit.VERMILLION)
		_refund_note_label.text = str(quote.get("reason_text", "无法生成换汇报价"))
		_refund_note_label.add_theme_color_override("font_color", ThemeKit.VERMILLION)
		_confirm_button.disabled = true
		return

	var fee_base := int(quote.get("fee_base", 0))
	var fee_rate := float(quote.get("fee_rate", 0.0))
	if fee_base <= 0:
		_fee_value_label.text = "0 基准点（免手续费）"
		_fee_value_label.add_theme_color_override("font_color", ThemeKit.GREEN)
	else:
		_fee_value_label.text = "%d 基准点（%.0f%% 向上取整）" % [fee_base, fee_rate * 100.0]
		_fee_value_label.add_theme_color_override("font_color", ThemeKit.AMBER)

	_actual_pay_label.text = str(quote.get("formatted_actual_from", ""))
	_received_value_label.text = str(quote.get("formatted_received", ""))
	_received_value_label.add_theme_color_override("font_color", ThemeKit.BLUE)

	var notes := PackedStringArray()
	var refund := int(quote.get("refund_from_units", 0))
	if refund > 0:
		notes.append("零头退还：%s 将保留在钱袋中，不扣多余尾款。" % str(quote.get("formatted_refund_from", "")))
	var rem_base := int(quote.get("remainder_base", 0))
	if rem_base > 0:
		var step := int(quote.get("exact_step_from_units", 1))
		notes.append("不可整除余差：%d 基准点（点击「取整无损」按 %s 步长零误差兑换）。" % [
			rem_base, EconomyManager.format_currency(_from_currency, step)
		])
	var affordable := bool(quote.get("affordable", false))
	if not affordable:
		notes.append("余额不足：当前持有 %s，需要 %s。" % [
			EconomyManager.format_currency(_from_currency, from_bal),
			str(quote.get("formatted_actual_from", ""))
		])
	elif notes.is_empty():
		notes.append("账目精确无尾差，确认后即时入袋。")
	_refund_note_label.text = " ".join(notes)
	_refund_note_label.add_theme_color_override("font_color", ThemeKit.VERMILLION if not affordable else ThemeKit.MUTED)
	_confirm_button.disabled = not affordable


func _on_from_selected(idx: int) -> void:
	if _rebuilding:
		return
	var next_id := str(_from_select.get_item_metadata(idx))
	if next_id == _to_currency:
		_to_currency = _from_currency
	_from_currency = next_id
	refresh()


func _on_to_selected(idx: int) -> void:
	if _rebuilding:
		return
	var next_id := str(_to_select.get_item_metadata(idx))
	if next_id == _from_currency:
		_from_currency = _to_currency
	_to_currency = next_id
	refresh()


func _on_swap_pressed() -> void:
	var prev := _from_currency
	_from_currency = _to_currency
	_to_currency = prev
	var bal := EconomyManager.get_balance(_from_currency)
	if bal > 0 and _amount_units > bal:
		_amount_units = bal
	refresh()


func _on_amount_changed(val: float) -> void:
	if _rebuilding:
		return
	_amount_units = maxi(1, int(val))
	_update_quote_display()


func _set_amount_units(units: int) -> void:
	_amount_units = maxi(1, units)
	_rebuilding = true
	_amount_spin.value = _amount_units
	_rebuilding = false
	_update_quote_display()


func _apply_quick_amount(mode: String) -> void:
	var bal := EconomyManager.get_balance(_from_currency)
	match mode:
		"half":
			@warning_ignore("integer_division")
			_set_amount_units(maxi(1, bal / 2))
		"all":
			_set_amount_units(maxi(1, bal))
		"snap":
			var step := EconomyManager.get_exact_lossless_step(_from_currency, _to_currency)
			@warning_ignore("integer_division")
			var snapped := maxi(step, (_amount_units / step) * step)
			if bal >= step and snapped > bal:
				@warning_ignore("integer_division")
				snapped = (bal / step) * step
			_set_amount_units(snapped)


func _on_confirm_pressed() -> void:
	var result := EconomyManager.execute_exchange(_from_currency, _to_currency, _amount_units, _venue_type, _city_id)
	if bool(result.get("executed", false)):
		Motion.pop_badge(_received_value_label, 0.36)
		var next_bal := EconomyManager.get_balance(_from_currency)
		if next_bal > 0 and _amount_units > next_bal:
			_amount_units = next_bal
	refresh()
	exchange_completed.emit(result)


func _create_parchment_option() -> OptionButton:
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(180.0, 46.0)
	opt.add_theme_font_override("font", _body_font)
	opt.add_theme_font_size_override("font_size", 16)
	var normal := ThemeKit.style(Color("#fbf5ea"), 14, 8, 2, 1, Color("#8a6a44"))
	var hover := ThemeKit.style(Color("#fff9ee"), 14, 8, 3, 1, ThemeKit.AMBER)
	opt.add_theme_stylebox_override("normal", normal)
	opt.add_theme_stylebox_override("hover", hover)
	opt.add_theme_stylebox_override("pressed", hover)
	opt.add_theme_stylebox_override("focus", hover)
	opt.add_theme_color_override("font_color", ThemeKit.INK)
	opt.add_theme_color_override("font_hover_color", ThemeKit.INK)
	opt.add_theme_color_override("font_pressed_color", ThemeKit.INK)
	opt.add_theme_color_override("font_focus_color", ThemeKit.INK)
	var popup := opt.get_popup()
	popup.add_theme_font_override("font", _body_font)
	popup.add_theme_font_size_override("font_size", 16)
	popup.add_theme_stylebox_override("panel", ThemeKit.style(ThemeKit.PAPER, 8, 8, 6, 2, ThemeKit.BORDER))
	popup.add_theme_color_override("font_color", ThemeKit.INK)
	popup.add_theme_color_override("font_hover_color", ThemeKit.INK)
	var hover_item := ThemeKit.style(Color("#e8d5b5"), 8, 4, 0, 0)
	popup.add_theme_stylebox_override("hover", hover_item)
	return opt


func _style_spinbox(spin: SpinBox) -> void:
	var line_edit := spin.get_line_edit()
	if line_edit != null:
		line_edit.add_theme_font_override("font", _body_font)
		line_edit.add_theme_font_size_override("font_size", 17)
		line_edit.add_theme_color_override("font_color", ThemeKit.INK)
		line_edit.add_theme_stylebox_override("normal", ThemeKit.style(Color("#fbf5ea"), 10, 6, 0, 1, Color("#8a6a44")))
		line_edit.add_theme_stylebox_override("focus", ThemeKit.style(Color("#fffaf0"), 10, 6, 0, 2, ThemeKit.AMBER))
