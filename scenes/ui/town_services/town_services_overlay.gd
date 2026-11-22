extends Control
class_name TownServicesOverlay

signal closed
signal city_changed(city_id: String)
signal tab_changed(tab_id: String)

const ThemeKit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const ExchangePanelScript := preload("res://scenes/ui/town_services/currency_exchange_panel.gd")

const TAB_ORDER: Array[String] = ["guild", "inn", "restaurant", "merchant"]
const TAB_LABELS: Dictionary[String, String] = {
	"guild": "冒险者协会",
	"inn": "旅馆休整",
	"restaurant": "酒馆餐馆",
	"merchant": "补给与旅商"
}

var _title_font: Font
var _body_font: Font
var _city_id := "city_rikarisu"
var _active_tab := "guild"
var _pay_currency_id := ""
var _inline_exchange_open: Dictionary[String, bool] = {
	"inn": false,
	"restaurant": false,
	"merchant": false
}
var _supply_quantities: Dictionary[String, int] = {
	"ration_normal": 3,
	"ration_fine": 1,
	"emergency_herbs": 1,
	"travel_waterskin": 1,
	"cold_weather_cloak": 1
}
var _built := false
var _show_backdrop := true
var _show_close_button := true
var _top_inset := 0.0

var _backdrop: ColorRect
var _center_host: CenterContainer
var _book_binding: PanelContainer
var _book_spread: PanelContainer

# Left folio page controls
var _city_title_label: Label
var _city_meta_label: Label
var _price_badge_holder: HBoxContainer
var _date_label: Label
var _stamina_value_label: Label
var _stamina_bar: ProgressBar
var _rations_summary_label: Label
var _modifiers_flow: HFlowContainer
var _wallet_list_vbox: VBoxContainer
var _total_wealth_label: Label

# Right folio page controls
var _tab_buttons: Dictionary[String, Button] = {}
var _close_button: Button
var _content_holder: Control
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_timer: SceneTreeTimer
var _active_exchange_panel: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_font = ThemeKit.make_font(true)
	_body_font = ThemeKit.make_font(false)
	_city_id = EconomyManager.normalize_city_id(WorldBlackboard.current_city_id)
	_pay_currency_id = EconomyManager.get_local_currency_id(_city_id)
	_build_shell()
	_connect_signals()
	refresh_all(false)


func _connect_signals() -> void:
	if not EconomyManager.economy_state_changed.is_connected(_on_economy_updated):
		EconomyManager.economy_state_changed.connect(_on_economy_updated)
	if not WorldBlackboard.world_time_changed.is_connected(_on_economy_updated):
		WorldBlackboard.world_time_changed.connect(_on_economy_updated)
	if not WorldBlackboard.inventory_changed.is_connected(_on_economy_updated):
		WorldBlackboard.inventory_changed.connect(_on_economy_updated)


func configure_presentation(show_backdrop: bool, show_close_button: bool, top_inset: float = 0.0) -> void:
	_show_backdrop = show_backdrop
	_show_close_button = show_close_button
	_top_inset = top_inset
	if _backdrop != null:
		_backdrop.visible = _show_backdrop
	if _close_button != null:
		_close_button.visible = _show_close_button
	if _center_host != null:
		_center_host.offset_top = _top_inset


func open_for_city(city_id: String, initial_tab: String = "guild") -> void:
	_city_id = EconomyManager.normalize_city_id(city_id)
	_pay_currency_id = EconomyManager.get_local_currency_id(_city_id)
	_active_tab = initial_tab if initial_tab in TAB_ORDER else "guild"
	visible = true
	refresh_all(false)
	if _backdrop != null and _backdrop.visible:
		Motion.fade_in(_backdrop, 0.22)
	if _book_binding != null:
		_book_binding.pivot_offset_ratio = Vector2(0.5, 0.5)
		Motion.spring(_book_binding, "scale", Vector2.ONE * 0.94, Vector2.ONE, 0.42, 8.8, 7.6)
		Motion.fade_in(_book_binding, 0.24)
	city_changed.emit(_city_id)
	tab_changed.emit(_active_tab)


func set_city(city_id: String) -> void:
	_city_id = EconomyManager.normalize_city_id(city_id)
	_pay_currency_id = EconomyManager.get_local_currency_id(_city_id)
	refresh_all(true)
	city_changed.emit(_city_id)


func select_tab(tab_id: String, animate: bool = true) -> void:
	if tab_id not in TAB_ORDER:
		return
	_active_tab = tab_id
	_update_tab_button_states()
	_rebuild_right_content(animate)
	tab_changed.emit(_active_tab)


func set_inline_exchange_open(opened: bool) -> void:
	if _inline_exchange_open.has(_active_tab):
		_inline_exchange_open[_active_tab] = opened
		_rebuild_right_content(true)


func get_active_exchange_panel() -> PanelContainer:
	return _active_exchange_panel


func close_overlay() -> void:
	visible = false
	closed.emit()


func _build_shell() -> void:
	if _built:
		return
	_built = true

	_backdrop = ColorRect.new()
	_backdrop.color = Color("#18100ac2")
	_backdrop.visible = _show_backdrop
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)

	_center_host = CenterContainer.new()
	_center_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center_host.offset_top = _top_inset
	add_child(_center_host)

	var book := ThemeKit.create_grimoire_book(Vector2(1620.0, 910.0), 0.285, true)
	_book_binding = book["binding"]
	_book_spread = book["spread"]
	_center_host.add_child(_book_binding)

	var spread_hbox := HBoxContainer.new()
	spread_hbox.add_theme_constant_override("separation", 42)
	_book_spread.add_child(spread_hbox)

	# ── Left Page: City Archive, Survival Status & Multi-Currency Purse ──
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(405.0, 0.0)
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 12)
	spread_hbox.add_child(left_col)

	_city_title_label = ThemeKit.create_label("利卡里斯镇", 32, ThemeKit.INK, _title_font)
	left_col.add_child(_city_title_label)

	_city_meta_label = ThemeKit.create_label("", 15, ThemeKit.MUTED, _body_font)
	_city_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_col.add_child(_city_meta_label)

	_price_badge_holder = HBoxContainer.new()
	_price_badge_holder.add_theme_constant_override("separation", 8)
	left_col.add_child(_price_badge_holder)

	_date_label = ThemeKit.create_label("", 15, ThemeKit.MUTED, _body_font)
	left_col.add_child(_date_label)

	left_col.add_child(ThemeKit.create_gold_divider(0.0, true, 12.0))

	# Survival Vitals Inset Card
	var vitals_card := PanelContainer.new()
	var vitals_box := ThemeKit.style(ThemeKit.PAPER_DEEP, 16, 14, 2, 1, Color("#9e7e56"))
	vitals_box.set_corner_radius_all(8)
	vitals_card.add_theme_stylebox_override("panel", vitals_box)
	left_col.add_child(vitals_card)

	var vitals_vbox := VBoxContainer.new()
	vitals_vbox.add_theme_constant_override("separation", 8)
	vitals_card.add_child(vitals_vbox)

	var stam_row := HBoxContainer.new()
	vitals_vbox.add_child(stam_row)
	var stam_title := ThemeKit.create_label("旅途体力", 16, ThemeKit.INK, _title_font)
	stam_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stam_row.add_child(stam_title)
	_stamina_value_label = ThemeKit.create_label("100 / 100", 16, ThemeKit.INK, _body_font)
	stam_row.add_child(_stamina_value_label)

	_stamina_bar = ThemeKit.create_meter(ThemeKit.GREEN, Color("#d4c5ac"), 11.0)
	_stamina_bar.min_value = 0
	_stamina_bar.max_value = 100
	_stamina_bar.value = 100
	vitals_vbox.add_child(_stamina_bar)

	_rations_summary_label = ThemeKit.create_label("", 14, ThemeKit.MUTED, _body_font)
	_rations_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vitals_vbox.add_child(_rations_summary_label)

	var mod_hdr := ThemeKit.create_label("当前状态修正（检定生效）", 14, ThemeKit.MUTED, _body_font)
	vitals_vbox.add_child(mod_hdr)

	_modifiers_flow = HFlowContainer.new()
	_modifiers_flow.add_theme_constant_override("h_separation", 8)
	_modifiers_flow.add_theme_constant_override("v_separation", 8)
	vitals_vbox.add_child(_modifiers_flow)

	# Multi-Currency Purse Card
	var purse_card := PanelContainer.new()
	var purse_box := ThemeKit.style(ThemeKit.PAPER_DEEP, 16, 14, 2, 1, Color("#9e7e56"))
	purse_box.set_corner_radius_all(8)
	purse_card.add_theme_stylebox_override("panel", purse_box)
	purse_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(purse_card)

	var purse_vbox := VBoxContainer.new()
	purse_vbox.add_theme_constant_override("separation", 8)
	purse_card.add_child(purse_vbox)

	var purse_hdr := HBoxContainer.new()
	purse_vbox.add_child(purse_hdr)
	var purse_title := ThemeKit.create_label("随身钱袋", 19, ThemeKit.INK, _title_font)
	purse_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	purse_hdr.add_child(purse_title)
	_total_wealth_label = ThemeKit.create_label("", 13, ThemeKit.MUTED, _body_font)
	_total_wealth_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	purse_hdr.add_child(_total_wealth_label)

	purse_vbox.add_child(ThemeKit.create_gold_divider(0.0, false, 6.0))

	var purse_scroll := ScrollContainer.new()
	purse_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	purse_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ThemeKit.style_scrollbar(purse_scroll.get_v_scroll_bar())
	purse_vbox.add_child(purse_scroll)

	_wallet_list_vbox = VBoxContainer.new()
	_wallet_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wallet_list_vbox.add_theme_constant_override("separation", 8)
	purse_scroll.add_child(_wallet_list_vbox)

	# ── Right Page: Four Town Service Tabs ──
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 12)
	spread_hbox.add_child(right_col)

	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 10)
	right_col.add_child(tab_bar)

	for tab_id: String in TAB_ORDER:
		var btn := ThemeKit.create_gold_tab_button(TAB_LABELS[tab_id], _title_font, 22)
		btn.custom_minimum_size = Vector2(150.0, 50.0)
		var captured := tab_id
		btn.pressed.connect(func() -> void: select_tab(captured, true))
		tab_bar.add_child(btn)
		_tab_buttons[tab_id] = btn

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_bar.add_child(spacer)

	_close_button = ThemeKit.create_tactile_button("合上手账", "subtle", _body_font, 16)
	_close_button.custom_minimum_size = Vector2(108.0, 46.0)
	_close_button.visible = _show_close_button
	_close_button.pressed.connect(close_overlay)
	tab_bar.add_child(_close_button)

	right_col.add_child(ThemeKit.create_gold_divider(0.0, false, 8.0))

	_content_holder = Control.new()
	_content_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_holder.clip_contents = true
	right_col.add_child(_content_holder)

	# Bottom Feedback Toast Bar (always cleanly anchored at bottom of right column, hidden when idle)
	_toast_panel = PanelContainer.new()
	var toast_box := ThemeKit.style(Color("#322419eb"), 18, 10, 4, 1, ThemeKit.BRASS)
	toast_box.set_corner_radius_all(8)
	_toast_panel.add_theme_stylebox_override("panel", toast_box)
	_toast_panel.visible = false
	right_col.add_child(_toast_panel)

	_toast_label = ThemeKit.create_label("", 16, ThemeKit.IVORY, _body_font)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_panel.add_child(_toast_label)


func _on_economy_updated() -> void:
	if not _built or not is_inside_tree():
		return
	refresh_all(false)


func refresh_all(animate_right: bool = false) -> void:
	_refresh_left_folio()
	_update_tab_button_states()
	_rebuild_right_content(animate_right)


func _refresh_left_folio() -> void:
	var city := EconomyManager.get_city_economy(_city_id)
	var local_id := EconomyManager.get_local_currency_id(_city_id)
	var local_def := EconomyManager.get_currency_def(local_id)
	var cont_label := _continent_label(str(city.get("continent", "demon")))

	_city_title_label.text = str(city.get("name", _city_id))
	_city_meta_label.text = "%s · 本地通货：%s" % [cont_label, str(local_def.get("name", local_id))]
	_date_label.text = WorldBlackboard.date_text()

	for child: Node in _price_badge_holder.get_children():
		child.queue_free()
	var mult := float(city.get("price_multiplier", 1.0))
	var mult_color := ThemeKit.GREEN if mult < 0.95 else (ThemeKit.AMBER if mult > 1.1 else ThemeKit.BLUE)
	_price_badge_holder.add_child(ThemeKit.create_badge("物价 ×%.2f" % mult, mult_color, _body_font, 14))
	var has_guild := EconomyManager.has_city_service(_city_id, "adventurer_guild")
	_price_badge_holder.add_child(ThemeKit.create_badge(
		"设冒险者协会（0%换汇）" if has_guild else "无协会分部（代兑 5%）",
		ThemeKit.SAPPHIRE if has_guild else ThemeKit.MUTED,
		_body_font,
		14
	))

	# Survival Vitals
	var stam := EconomyManager.stamina
	var max_stam := EconomyManager.max_stamina
	_stamina_value_label.text = "%d / %d" % [stam, max_stam]
	_stamina_bar.max_value = max_stam
	_stamina_bar.value = stam
	var bar_col := ThemeKit.GREEN if stam >= 65 else (ThemeKit.AMBER if stam >= 35 else ThemeKit.VERMILLION)
	var fg := StyleBoxFlat.new()
	fg.bg_color = bar_col
	fg.border_color = bar_col.lightened(0.26)
	fg.border_width_top = 1
	fg.set_corner_radius_all(4)
	_stamina_bar.add_theme_stylebox_override("fill", fg)

	var rations := EconomyManager.get_ration_counts()
	var weight := EconomyManager.get_total_ration_weight_kg()
	var hunger_suffix := "" if EconomyManager.hunger_days <= 0 else " · 已断粮 %d 日" % EconomyManager.hunger_days
	_rations_summary_label.text = "随身干粮：%d 日份（普通 %d · 精良 %d · %.1f kg）%s" % [
		int(rations["total"]),
		int(rations["normal"]) + int(rations["legacy"]),
		int(rations["fine"]),
		weight,
		hunger_suffix
	]

	for child: Node in _modifiers_flow.get_children():
		child.queue_free()
	var mods := EconomyManager.get_active_modifiers_list()
	if mods.is_empty():
		var calm := ThemeKit.create_chip("状态平稳（检定 +0）", _body_font, 14)
		_modifiers_flow.add_child(calm)
	else:
		for mod: Dictionary in mods:
			var val := int(mod.get("value", 0))
			var positive := val > 0
			var badge := ThemeKit.create_status_badge(
				"%s %+d" % [str(mod.get("name", "")), val],
				positive,
				_body_font,
				15
			)
			_modifiers_flow.add_child(badge)

	# Multi-currency purse
	_total_wealth_label.text = "总计 %d 基准点" % EconomyManager.get_total_wealth_in_base()
	for child: Node in _wallet_list_vbox.get_children():
		child.queue_free()

	var order := EconomyManager.get_currency_order()
	var ordered_ids: Array[String] = [local_id]
	for cid: String in order:
		if cid != local_id and EconomyManager.get_balance(cid) > 0:
			ordered_ids.append(cid)

	for cid: String in ordered_ids:
		var def := EconomyManager.get_currency_def(cid)
		var bal := EconomyManager.get_balance(cid)
		var is_local := cid == local_id
		var row_panel := PanelContainer.new()
		var bg := Color("#fcf6eb") if is_local else Color("#f1e6d2")
		var rim := ThemeKit.AMBER if is_local else Color("#b79a72")
		var box := ThemeKit.style(bg, 12, 8, 1 if is_local else 0, 2 if is_local else 1, rim)
		box.set_corner_radius_all(7)
		row_panel.add_theme_stylebox_override("panel", box)
		_wallet_list_vbox.add_child(row_panel)

		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 3)
		row_panel.add_child(vb)

		var top_r := HBoxContainer.new()
		top_r.add_theme_constant_override("separation", 8)
		vb.add_child(top_r)

		var name_l := ThemeKit.create_label(str(def.get("name", cid)), 15, ThemeKit.INK, _body_font)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_r.add_child(name_l)

		if is_local:
			top_r.add_child(ThemeKit.create_badge("当地流通", ThemeKit.AMBER, _body_font, 12))
		else:
			var mult_lbl := ThemeKit.create_label("×%.2f" % float(def.get("multiplier", 1.0)), 13, ThemeKit.MUTED, _body_font)
			top_r.add_child(mult_lbl)

		var val_l := ThemeKit.create_label(EconomyManager.format_currency(cid, bal), 19, ThemeKit.INK, _title_font)
		vb.add_child(val_l)


func _update_tab_button_states() -> void:
	var has_guild := EconomyManager.has_city_service(_city_id, "adventurer_guild")
	for tab_id: String in TAB_ORDER:
		var btn: Button = _tab_buttons[tab_id]
		var active := tab_id == _active_tab
		btn.set_pressed_no_signal(active)
		if tab_id == "guild":
			btn.text = "冒险者协会" if has_guild else "冒险者协会（无）"
		if btn.has_meta(&"gold_underline"):
			var underline: Control = btn.get_meta(&"gold_underline")
			underline.modulate.a = 1.0 if active else 0.0


func _rebuild_right_content(animate: bool) -> void:
	_active_exchange_panel = null
	for child: Node in _content_holder.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ThemeKit.style_scrollbar(scroll.get_v_scroll_bar())
	_content_holder.add_child(scroll)

	var scroll_pad := MarginContainer.new()
	scroll_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_pad.add_theme_constant_override("margin_left", 4)
	scroll_pad.add_theme_constant_override("margin_right", 10)
	scroll_pad.add_theme_constant_override("margin_top", 4)
	scroll_pad.add_theme_constant_override("margin_bottom", 10)
	scroll.add_child(scroll_pad)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	scroll_pad.add_child(body)

	match _active_tab:
		"guild":
			_build_guild_tab(body)
		"inn":
			_build_inn_tab(body)
		"restaurant":
			_build_restaurant_tab(body)
		"merchant":
			_build_merchant_tab(body)

	if animate:
		body.modulate.a = 0.0
		Motion.fade_alpha(body, 1.0, 0.22)
		Motion.slide_drawer_in(body, 22.0, 0.34)


func _build_guild_tab(parent: VBoxContainer) -> void:
	var city := EconomyManager.get_city_economy(_city_id)
	var has_guild := EconomyManager.has_city_service(_city_id, "adventurer_guild")

	if not has_guild:
		var notice := ThemeKit.create_folio_panel(ThemeKit.PAPER_DEEP, 32, 28, 6)
		parent.add_child(notice)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 16)
		notice.add_child(vb)

		var badge_row := HBoxContainer.new()
		badge_row.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(badge_row)
		badge_row.add_child(ThemeKit.create_badge("聚落提示 · 无协会常驻分部", ThemeKit.AMBER, _body_font, 15))

		var title := ThemeKit.create_label("%s未设冒险者协会分部" % str(city.get("name", _city_id)), 28, ThemeKit.INK, _title_font)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(title)

		vb.add_child(ThemeKit.create_gold_divider(0.0, true, 12.0))

		var desc_pad := MarginContainer.new()
		desc_pad.add_theme_constant_override("margin_left", 48)
		desc_pad.add_theme_constant_override("margin_right", 48)
		vb.add_child(desc_pad)
		var note_text := str(city.get("guild_absence_note",
			"本村未设冒险者协会分部，可前往旅馆或向旅商兑换（5% 手续费）。"))
		var desc := ThemeKit.create_label(note_text, 18, ThemeKit.MUTED, _body_font)
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_pad.add_child(desc)

		var btn_row := HBoxContainer.new()
		btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_row.add_theme_constant_override("separation", 16)
		vb.add_child(btn_row)

		var go_inn := ThemeKit.create_tactile_button("前往旅馆代兑（5% 手续费）", "secondary", _body_font, 18)
		go_inn.custom_minimum_size = Vector2(260.0, 50.0)
		go_inn.pressed.connect(func() -> void:
			_inline_exchange_open["inn"] = true
			select_tab("inn", true))
		btn_row.add_child(go_inn)

		var go_merch := ThemeKit.create_tactile_button("前往旅商换汇（5% 手续费）", "primary", _body_font, 18)
		go_merch.custom_minimum_size = Vector2(260.0, 50.0)
		go_merch.pressed.connect(func() -> void:
			_inline_exchange_open["merchant"] = true
			select_tab("merchant", true))
		btn_row.add_child(go_merch)

		# Still show the 6-currency reference card underneath so players can inspect world rates cleanly.
		parent.add_child(_build_rate_reference_card(false))
		return

	# Official Guild 0% Exchange Workbench + 6-Currency Reference Card side-by-side
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 18)
	parent.add_child(split)

	var exchange_panel: PanelContainer = ExchangePanelScript.new()
	exchange_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exchange_panel.size_flags_stretch_ratio = 1.35
	exchange_panel.call("setup", _city_id, "adventurer_guild", _title_font, _body_font, false)
	exchange_panel.connect("exchange_completed", _on_exchange_completed)
	split.add_child(exchange_panel)
	_active_exchange_panel = exchange_panel

	var rate_card := _build_rate_reference_card(true)
	rate_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rate_card.size_flags_stretch_ratio = 0.95
	split.add_child(rate_card)


func _build_rate_reference_card(vertical_compact: bool) -> PanelContainer:
	var card := PanelContainer.new()
	var box := ThemeKit.style(ThemeKit.PAPER_DEEP, 18, 16, 3, 1, Color("#9a7952"))
	box.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", box)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 9)
	card.add_child(vb)

	var hdr := HBoxContainer.new()
	vb.add_child(hdr)
	var title := ThemeKit.create_label("六大货币公定牌价", 21, ThemeKit.INK, _title_font)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)
	hdr.add_child(ThemeKit.create_label("以 1,000 基准点折算", 13, ThemeKit.MUTED, _body_font))

	vb.add_child(ThemeKit.create_gold_divider(0.0, false, 6.0))

	var local_id := EconomyManager.get_local_currency_id(_city_id)
	var container: Container
	if vertical_compact:
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 7)
		container = list
	else:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 8)
		container = grid
	vb.add_child(container)

	for cid: String in EconomyManager.get_currency_order():
		var def := EconomyManager.get_currency_def(cid)
		var u_base := EconomyManager.get_unit_base_value(cid)
		@warning_ignore("integer_division")
		var equiv_1000 := 1000 / u_base
		var is_local := cid == local_id
		var item_panel := PanelContainer.new()
		item_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ibox := ThemeKit.style(
			Color("#fdf7ec") if is_local else Color("#f3e9d6"),
			12, 8, 0, 2 if is_local else 1,
			ThemeKit.AMBER if is_local else Color("#bda27d")
		)
		ibox.set_corner_radius_all(6)
		item_panel.add_theme_stylebox_override("panel", ibox)
		container.add_child(item_panel)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		item_panel.add_child(row)

		var left_v := VBoxContainer.new()
		left_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left_v.add_theme_constant_override("separation", 2)
		row.add_child(left_v)

		var cname := ThemeKit.create_label(
			"%s%s" % [str(def.get("name", cid)), " · 当地" if is_local else ""],
			15,
			ThemeKit.INK,
			_body_font
		)
		left_v.add_child(cname)
		var region_short := str(def.get("region_label", "")).replace("魔法都市夏利亚", "夏利亚")
		var creg := ThemeKit.create_label(
			"×%.2f · %s" % [float(def.get("multiplier", 1.0)), region_short],
			12,
			ThemeKit.MUTED,
			_body_font
		)
		creg.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		left_v.add_child(creg)

		var eq_lbl := ThemeKit.create_label(EconomyManager.format_currency(cid, equiv_1000), 17, ThemeKit.BLUE if is_local else ThemeKit.INK, _title_font)
		eq_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		eq_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(eq_lbl)

	var foot := ThemeKit.create_label(
		"对照例：10 大绿矿钱（1 银矿）= 2 米里斯大铜钱 = 1 阿斯拉大铜钱",
		13,
		ThemeKit.MUTED,
		_body_font
	)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(foot)
	return card


func _build_service_utility_bar(parent: VBoxContainer, tab_key: String, venue_type: String, drawer_label: String) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	parent.add_child(bar)

	var pay_lbl := ThemeKit.create_label("结账币种：", 16, ThemeKit.MUTED, _body_font)
	pay_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(pay_lbl)

	var pay_opt := _create_payment_currency_option()
	bar.add_child(pay_opt)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var is_open := bool(_inline_exchange_open.get(tab_key, false))
	var toggle_btn := ThemeKit.create_tactile_button(
		("收起%s" if is_open else "%s（5%% 手续费）") % drawer_label,
		"accent" if is_open else "secondary",
		_body_font,
		16
	)
	toggle_btn.custom_minimum_size = Vector2(240.0, 46.0)
	toggle_btn.pressed.connect(func() -> void:
		_inline_exchange_open[tab_key] = not bool(_inline_exchange_open.get(tab_key, false))
		_rebuild_right_content(true))
	bar.add_child(toggle_btn)

	if is_open:
		var drawer: PanelContainer = ExchangePanelScript.new()
		drawer.call("setup", _city_id, venue_type, _title_font, _body_font, true)
		drawer.connect("exchange_completed", _on_exchange_completed)
		parent.add_child(drawer)
		_active_exchange_panel = drawer


func _create_payment_currency_option() -> OptionButton:
	var local_id := EconomyManager.get_local_currency_id(_city_id)
	if _pay_currency_id.is_empty():
		_pay_currency_id = local_id

	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(310.0, 46.0)
	opt.add_theme_font_override("font", _body_font)
	opt.add_theme_font_size_override("font_size", 15)
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
	popup.add_theme_font_size_override("font_size", 15)
	popup.add_theme_stylebox_override("panel", ThemeKit.style(ThemeKit.PAPER, 8, 8, 6, 2, ThemeKit.BORDER))
	popup.add_theme_color_override("font_color", ThemeKit.INK)
	popup.add_theme_color_override("font_hover_color", ThemeKit.INK)
	popup.add_theme_stylebox_override("hover", ThemeKit.style(Color("#e8d5b5"), 8, 4, 0, 0))

	var order := EconomyManager.get_currency_order()
	var choices: Array[String] = [local_id]
	for cid: String in order:
		if cid != local_id and (EconomyManager.get_balance(cid) > 0 or cid == _pay_currency_id):
			choices.append(cid)

	var sel_idx := 0
	for i: int in range(choices.size()):
		var cid := choices[i]
		var def := EconomyManager.get_currency_def(cid)
		var suffix := "（本地直付 · 0%）" if cid == local_id else "（外币折算 · +5%）"
		opt.add_item("%s%s" % [str(def.get("short_name", cid)), suffix], i)
		opt.set_item_metadata(i, cid)
		if cid == _pay_currency_id:
			sel_idx = i
	opt.select(sel_idx)
	opt.item_selected.connect(func(idx: int) -> void:
		_pay_currency_id = str(opt.get_item_metadata(idx))
		_rebuild_right_content(false))
	return opt


func _build_inn_tab(parent: VBoxContainer) -> void:
	_build_service_utility_bar(parent, "inn", "inn", "旅馆代兑货币")

	var tiers := EconomyManager.get_inn_tiers(_city_id)
	for tier: Dictionary in tiers:
		var available := bool(tier.get("available", false))
		var local_units := int(tier.get("local_units", 0))
		var quote := EconomyManager.quote_purchase(_city_id, local_units, "inn", _pay_currency_id)
		var affordable := available and bool(quote.get("affordable", false))

		var card := PanelContainer.new()
		var bg := Color("#fbf5ea") if available else Color("#eae0cf")
		var rim := Color("#8a6a44") if available else Color("#b09e88")
		var box := ThemeKit.style(bg, 20, 16, 3 if available else 0, 2 if available else 1, rim)
		box.set_corner_radius_all(8)
		card.add_theme_stylebox_override("panel", box)
		parent.add_child(card)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		card.add_child(row)

		var left := VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.add_theme_constant_override("separation", 6)
		row.add_child(left)

		var hdr := HBoxContainer.new()
		hdr.add_theme_constant_override("separation", 10)
		left.add_child(hdr)
		hdr.add_child(ThemeKit.create_label(str(tier.get("name", "")), 22, ThemeKit.INK if available else ThemeKit.MUTED, _title_font))

		var mod_id := str(tier.get("grants_modifier", ""))
		if not mod_id.is_empty():
			hdr.add_child(ThemeKit.create_status_badge("精力充沛 +1", true, _body_font, 14))
		if not available:
			hdr.add_child(ThemeKit.create_badge("仅大中城镇", ThemeKit.MUTED, _body_font, 13))

		left.add_child(ThemeKit.create_label(str(tier.get("subtitle", "")), 15, ThemeKit.BLUE if available else ThemeKit.MUTED, _body_font))
		var desc := ThemeKit.create_label(str(tier.get("description", "")), 15, ThemeKit.MUTED, _body_font)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left.add_child(desc)

		var right := VBoxContainer.new()
		right.custom_minimum_size = Vector2(230.0, 0.0)
		right.alignment = BoxContainer.ALIGNMENT_CENTER
		right.add_theme_constant_override("separation", 6)
		row.add_child(right)

		var price_lbl := ThemeKit.create_label(str(tier.get("formatted_price", "")), 22, ThemeKit.INK if available else ThemeKit.MUTED, _title_font)
		price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(price_lbl)

		if bool(quote.get("is_foreign_payment", false)) and available:
			var f_lbl := ThemeKit.create_label(
				"外币折算：%s（+5%%）" % str(quote.get("formatted_pay", "")),
				13,
				ThemeKit.AMBER,
				_body_font
			)
			f_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			right.add_child(f_lbl)

		var tier_id := str(tier.get("id", ""))
		var btn := ThemeKit.create_tactile_button(
			"登记入住" if available else "本村暂不提供",
			"accent" if mod_id == "well_rested" else "primary",
			_body_font,
			17
		)
		btn.custom_minimum_size = Vector2(180.0, 48.0)
		btn.disabled = not affordable
		btn.pressed.connect(func() -> void:
			var res := EconomyManager.rest_at_inn(_city_id, tier_id, _pay_currency_id)
			_handle_inn_result(res))
		right.add_child(btn)


func _build_restaurant_tab(parent: VBoxContainer) -> void:
	_build_service_utility_bar(parent, "restaurant", "restaurant", "餐馆代兑货币")

	var city := EconomyManager.get_city_economy(_city_id)
	var cont := str(city.get("continent", "demon"))
	var kitchen_titles: Dictionary[String, String] = {
		"demon": "魔大陆灶台风味 · 滚烫热食",
		"milis": "米里斯圣都餐桌 · 香草慢炖",
		"central": "中央大陆旅人酒馆 · 麦酒炭烤"
	}
	var kitchen_title: String = kitchen_titles.get(cont, "本地餐馆风味")
	parent.add_child(ThemeKit.create_label(kitchen_title, 20, ThemeKit.MUTED, _title_font))

	var menu := EconomyManager.get_restaurant_menu(_city_id)
	for dish: Dictionary in menu:
		var local_units := int(dish.get("local_units", 0))
		var quote := EconomyManager.quote_purchase(_city_id, local_units, "restaurant", _pay_currency_id)
		var affordable := bool(quote.get("affordable", false))

		var card := PanelContainer.new()
		var box := ThemeKit.style(Color("#fbf5ea"), 20, 16, 3, 2, Color("#8a6a44"))
		box.set_corner_radius_all(8)
		card.add_theme_stylebox_override("panel", box)
		parent.add_child(card)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		card.add_child(row)

		var left := VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.add_theme_constant_override("separation", 6)
		row.add_child(left)

		var hdr := HBoxContainer.new()
		hdr.add_theme_constant_override("separation", 10)
		left.add_child(hdr)
		hdr.add_child(ThemeKit.create_label(str(dish.get("name", "")), 22, ThemeKit.INK, _title_font))
		hdr.add_child(ThemeKit.create_status_badge("饱腹暖胃 +1", true, _body_font, 14))

		left.add_child(ThemeKit.create_label(str(dish.get("subtitle", "")), 15, ThemeKit.BLUE, _body_font))
		var desc := ThemeKit.create_label(str(dish.get("description", "")), 15, ThemeKit.MUTED, _body_font)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left.add_child(desc)

		var right := VBoxContainer.new()
		right.custom_minimum_size = Vector2(230.0, 0.0)
		right.alignment = BoxContainer.ALIGNMENT_CENTER
		right.add_theme_constant_override("separation", 6)
		row.add_child(right)

		var price_lbl := ThemeKit.create_label(str(dish.get("formatted_price", "")), 22, ThemeKit.INK, _title_font)
		price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(price_lbl)

		if bool(quote.get("is_foreign_payment", false)):
			var f_lbl := ThemeKit.create_label(
				"外币折算：%s（+5%%）" % str(quote.get("formatted_pay", "")),
				13,
				ThemeKit.AMBER,
				_body_font
			)
			f_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			right.add_child(f_lbl)

		var dish_id := str(dish.get("id", ""))
		var btn := ThemeKit.create_tactile_button("点餐享用", "accent", _body_font, 17)
		btn.custom_minimum_size = Vector2(180.0, 48.0)
		btn.disabled = not affordable
		btn.pressed.connect(func() -> void:
			var res := EconomyManager.order_meal(_city_id, dish_id, _pay_currency_id)
			_handle_meal_result(res))
		right.add_child(btn)


func _build_merchant_tab(parent: VBoxContainer) -> void:
	_build_service_utility_bar(parent, "merchant", "traveling_merchant", "旅商换汇")

	var supplies := EconomyManager.get_supplies_catalog(_city_id)
	var local_id := EconomyManager.get_local_currency_id(_city_id)
	for item: Dictionary in supplies:
		var item_id := str(item.get("id", ""))
		var is_ration := str(item.get("category", "")) == "ration"
		var qty := maxi(1, int(_supply_quantities.get(item_id, 3 if is_ration else 1)))
		_supply_quantities[item_id] = qty
		var unit_local := int(item.get("local_units", 0))
		var total_local := unit_local * qty
		var quote := EconomyManager.quote_purchase(_city_id, total_local, "traveling_merchant", _pay_currency_id)
		var affordable := bool(quote.get("affordable", false))
		var weight_total := float(item.get("weight_kg", 0.5)) * float(qty)

		var card := PanelContainer.new()
		var box := ThemeKit.style(Color("#fbf5ea"), 18, 14, 3, 2, Color("#8a6a44"))
		box.set_corner_radius_all(8)
		card.add_theme_stylebox_override("panel", box)
		parent.add_child(card)

		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 8)
		card.add_child(vb)

		var top_row := HBoxContainer.new()
		top_row.add_theme_constant_override("separation", 14)
		vb.add_child(top_row)

		var info_v := VBoxContainer.new()
		info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_v.add_theme_constant_override("separation", 4)
		top_row.add_child(info_v)

		var name_r := HBoxContainer.new()
		name_r.add_theme_constant_override("separation", 10)
		info_v.add_child(name_r)
		name_r.add_child(ThemeKit.create_label(str(item.get("name", "")), 21, ThemeKit.INK, _title_font))
		name_r.add_child(ThemeKit.create_chip("单价 %s" % str(item.get("formatted_price", "")), _body_font, 14))
		name_r.add_child(ThemeKit.create_chip("已有 %d" % int(item.get("owned_count", 0)), _body_font, 14))

		info_v.add_child(ThemeKit.create_label(str(item.get("subtitle", "")), 14, ThemeKit.BLUE, _body_font))
		var desc := ThemeKit.create_label(str(item.get("description", "")), 14, ThemeKit.MUTED, _body_font)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_v.add_child(desc)

		# Right side stepper & quick ration presets
		var ctrl_v := VBoxContainer.new()
		ctrl_v.custom_minimum_size = Vector2(315.0, 0.0)
		ctrl_v.add_theme_constant_override("separation", 8)
		top_row.add_child(ctrl_v)

		var step_row := HBoxContainer.new()
		step_row.alignment = BoxContainer.ALIGNMENT_END
		step_row.add_theme_constant_override("separation", 8)
		ctrl_v.add_child(step_row)

		var minus_btn := ThemeKit.create_tactile_button("−", "subtle", _body_font, 20)
		minus_btn.custom_minimum_size = Vector2(46.0, 44.0)
		minus_btn.pressed.connect(func() -> void:
			_supply_quantities[item_id] = maxi(1, int(_supply_quantities.get(item_id, 1)) - 1)
			_rebuild_right_content(false))
		step_row.add_child(minus_btn)

		var qty_lbl := ThemeKit.create_label("%d 份" % qty, 18, ThemeKit.INK, _title_font)
		qty_lbl.custom_minimum_size = Vector2(64.0, 44.0)
		qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		qty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		step_row.add_child(qty_lbl)

		var plus_btn := ThemeKit.create_tactile_button("+", "subtle", _body_font, 20)
		plus_btn.custom_minimum_size = Vector2(46.0, 44.0)
		plus_btn.pressed.connect(func() -> void:
			_supply_quantities[item_id] = mini(99, int(_supply_quantities.get(item_id, 1)) + 1)
			_rebuild_right_content(false))
		step_row.add_child(plus_btn)

		if is_ration:
			for preset_days: int in [3, 7]:
				var qbtn := ThemeKit.create_tactile_button("%d日" % preset_days, "secondary", _body_font, 15)
				qbtn.custom_minimum_size = Vector2(62.0, 44.0)
				var captured_days := preset_days
				qbtn.pressed.connect(func() -> void:
					_supply_quantities[item_id] = captured_days
					_rebuild_right_content(false))
				step_row.add_child(qbtn)

		var buy_row := HBoxContainer.new()
		buy_row.alignment = BoxContainer.ALIGNMENT_END
		buy_row.add_theme_constant_override("separation", 10)
		ctrl_v.add_child(buy_row)

		var subtotal_v := VBoxContainer.new()
		subtotal_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		subtotal_v.add_theme_constant_override("separation", 2)
		buy_row.add_child(subtotal_v)

		var total_str := EconomyManager.format_currency(local_id, total_local)
		var sub_lbl := ThemeKit.create_label("合计 %s" % total_str, 18, ThemeKit.INK, _title_font)
		sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		subtotal_v.add_child(sub_lbl)

		var meta_parts := PackedStringArray()
		if is_ration:
			meta_parts.append("可支撑 %d 日" % (qty * int(item.get("nutrition_days", 1))))
		meta_parts.append("负重 %.1f kg" % weight_total)
		if bool(quote.get("is_foreign_payment", false)):
			meta_parts.append("外币 %s" % str(quote.get("formatted_pay", "")))
		var meta_l := ThemeKit.create_label(" · ".join(meta_parts), 12, ThemeKit.AMBER if bool(quote.get("is_foreign_payment", false)) else ThemeKit.MUTED, _body_font)
		meta_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		subtotal_v.add_child(meta_l)

		var buy_btn := ThemeKit.create_tactile_button("购入", "primary", _body_font, 17)
		buy_btn.custom_minimum_size = Vector2(102.0, 46.0)
		buy_btn.disabled = not affordable
		buy_btn.pressed.connect(func() -> void:
			var res := EconomyManager.buy_supply(_city_id, item_id, qty, _pay_currency_id)
			_handle_buy_result(res))
		buy_row.add_child(buy_btn)

	# Sea Ferry Reference Card (subtle footer for cross-continent planning)
	var ferry_card := PanelContainer.new()
	var fbox := ThemeKit.style(ThemeKit.PAPER_DEEP, 16, 12, 1, 1, Color("#a98b63"))
	fbox.set_corner_radius_all(7)
	ferry_card.add_theme_stylebox_override("panel", fbox)
	parent.add_child(ferry_card)

	var fvb := VBoxContainer.new()
	fvb.add_theme_constant_override("separation", 4)
	ferry_card.add_child(fvb)
	fvb.add_child(ThemeKit.create_label("跨海定期客船参考票价（大地图航线共用）", 15, ThemeKit.INK, _title_font))
	for ferry: Dictionary in EconomyManager.get_sea_ferry_fares():
		var line := ThemeKit.create_label(
			"• %s：%d 基准点（约 %s · 航程 %d 日）" % [
				str(ferry.get("label", "")),
				int(ferry.get("base_fare", 0)),
				str(ferry.get("formatted_from_fare", "")),
				int(ferry.get("duration_days", 1))
			],
			13,
			ThemeKit.MUTED,
			_body_font
		)
		fvb.add_child(line)


func _on_exchange_completed(result: Dictionary) -> void:
	if bool(result.get("executed", false)):
		var fee_base := int(result.get("fee_base", 0))
		var refund := int(result.get("refund_from_units", 0))
		var msg := "换汇完成：付出 %s，实得 %s（%s）" % [
			str(result.get("formatted_actual_from", "")),
			str(result.get("formatted_received", "")),
			"免手续费" if fee_base == 0 else "手续费 %d 基准点" % fee_base
		]
		if refund > 0:
			msg += " · 退还零头 %s" % str(result.get("formatted_refund_from", ""))
		_show_toast(msg)
	else:
		_show_toast(str(result.get("reason_text", "换汇失败")))


func _handle_inn_result(res: Dictionary) -> void:
	if bool(res.get("executed", false)):
		var msg := "已入住%s（实付 %s），时间推进至 %s，体力恢复至 %d。" % [
			str(res.get("tier_name", "旅馆")),
			str(res.get("formatted_pay", "")),
			str(res.get("new_date_text", "")),
			int(res.get("stamina", 100))
		]
		if str(res.get("granted_modifier", "")) == "well_rested":
			msg += " 获得「精力充沛 +1」！"
		_show_toast(msg)
		_bounce_modifiers()
	else:
		_show_toast(str(res.get("reason_text", "无法办理入住")))


func _handle_meal_result(res: Dictionary) -> void:
	if bool(res.get("executed", false)):
		var msg := "享用了「%s」（实付 %s），体力恢复至 %d · 获得「饱腹暖胃 +1」！" % [
			str(res.get("dish_name", "")),
			str(res.get("formatted_pay", "")),
			int(res.get("stamina", 100))
		]
		_show_toast(msg)
		_bounce_modifiers()
	else:
		_show_toast(str(res.get("reason_text", "点餐失败")))


func _handle_buy_result(res: Dictionary) -> void:
	if bool(res.get("executed", false)):
		var msg := "购入 %s ×%d（实付 %s）" % [
			str(res.get("supply_name", "")),
			int(res.get("quantity", 1)),
			str(res.get("formatted_pay", ""))
		]
		var change := str(res.get("formatted_change", ""))
		if not change.is_empty():
			msg += " · 找零 %s" % change
		_show_toast(msg)
	else:
		_show_toast(str(res.get("reason_text", "购买失败")))


func _bounce_modifiers() -> void:
	for child: Node in _modifiers_flow.get_children():
		if child is Control:
			Motion.pop_badge(child as Control, 0.42)


func _show_toast(message: String) -> void:
	if _toast_panel == null or _toast_label == null:
		return
	_toast_label.text = message
	_toast_panel.visible = true
	Motion.fade_in(_toast_panel, 0.18)
	Motion.pop_badge(_toast_panel, 0.34)
	_toast_timer = get_tree().create_timer(4.5)
	var expected := _toast_timer
	expected.timeout.connect(func() -> void:
		if _toast_timer == expected and is_instance_valid(_toast_panel):
			_toast_panel.visible = false)


static func _continent_label(cont: String) -> String:
	match cont:
		"demon":
			return "魔大陆"
		"milis":
			return "米里斯大陆"
		"central":
			return "中央大陆"
		_:
			return cont
