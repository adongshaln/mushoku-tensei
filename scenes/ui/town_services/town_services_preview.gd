extends Control
class_name TownServicesPreview

const ThemeKit := preload("res://ui/ui_theme_kit.gd")
const OverlayScene := preload("res://scenes/ui/town_services/town_services_overlay.tscn")

const PREVIEW_CITIES: Array[Dictionary] = [
	{"id": "city_migurd", "label": "米格路德村（无协会 · 矿石钱）"},
	{"id": "city_rikarisu", "label": "利卡里斯镇（协会 0% · 矿石钱）"},
	{"id": "city_milishion", "label": "王都米里希翁（王都 · 米里斯币）"}
]

var _title_font: Font
var _body_font: Font
var _overlay: Control
var _city_buttons: Dictionary[String, Button] = {}
var _current_city := "city_rikarisu"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_font = ThemeKit.make_font(true)
	_body_font = ThemeKit.make_font(false)
	_seed_demo_wallet()
	_build_preview_ui()
	switch_preview_city("city_rikarisu", "guild")


func _seed_demo_wallet() -> void:
	EconomyManager.set_balance("demon_ore", 4500)
	EconomyManager.set_balance("minor_central", 0)
	EconomyManager.set_balance("magic_nations", 0)
	EconomyManager.set_balance("millis", 800)
	EconomyManager.set_balance("king_dragon", 0)
	EconomyManager.set_balance("asura", 200)
	if EconomyManager.get_total_rations() == 0:
		WorldBlackboard.add_item("ration_normal", "普通干粮", 4, "ration")
		WorldBlackboard.add_item("ration_fine", "精良口粮", 2, "ration")


func _build_preview_ui() -> void:
	# Warm walnut desk background
	var bg := ColorRect.new()
	bg.color = Color("#241a13")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Mount overlay slightly below the preview switcher bar
	_overlay = OverlayScene.instantiate() as Control
	add_child(_overlay)
	_overlay.call("configure_presentation", false, false, 78.0)

	# Top preview control strip (dark brass smoked glass)
	var top_margin := MarginContainer.new()
	top_margin.anchor_left = 0.0
	top_margin.anchor_right = 1.0
	top_margin.anchor_top = 0.0
	top_margin.anchor_bottom = 0.0
	top_margin.offset_bottom = 78.0
	top_margin.add_theme_constant_override("margin_left", 24)
	top_margin.add_theme_constant_override("margin_right", 24)
	top_margin.add_theme_constant_override("margin_top", 10)
	top_margin.add_theme_constant_override("margin_bottom", 6)
	add_child(top_margin)

	var bar_panel := ThemeKit.create_smoked_hud_panel(18, 8, 8)
	top_margin.add_child(bar_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	bar_panel.add_child(hbox)

	var badge := ThemeKit.create_badge("城镇服务预览", ThemeKit.WAX_GOLD, _title_font, 15)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(badge)

	for spec: Dictionary in PREVIEW_CITIES:
		var cid := str(spec["id"])
		var btn := ThemeKit.create_tactile_button(str(spec["label"]), "dark_brass", _body_font, 15)
		btn.custom_minimum_size = Vector2(210.0, 44.0)
		btn.pressed.connect(func() -> void:
			switch_preview_city(cid, "guild"))
		hbox.add_child(btn)
		_city_buttons[cid] = btn

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var btn_refill := ThemeKit.create_tactile_button("充入跨洲资金", "dark_brass", _body_font, 14)
	btn_refill.custom_minimum_size = Vector2(126.0, 44.0)
	btn_refill.pressed.connect(func() -> void:
		_seed_demo_wallet()
		_overlay.call("refresh_all", false))
	hbox.add_child(btn_refill)

	var btn_hungry := ThemeKit.create_tactile_button("模拟断粮", "dark_brass", _body_font, 14)
	btn_hungry.custom_minimum_size = Vector2(100.0, 44.0)
	btn_hungry.pressed.connect(func() -> void:
		var rations := EconomyManager.get_total_rations()
		if rations > 0:
			WorldBlackboard.consume_rations(rations)
		EconomyManager.consume_daily_rations(1, 1)
		_overlay.call("refresh_all", false))
	hbox.add_child(btn_hungry)

	var btn_starve := ThemeKit.create_tactile_button("断粮2日", "dark_brass", _body_font, 14)
	btn_starve.custom_minimum_size = Vector2(94.0, 44.0)
	btn_starve.pressed.connect(func() -> void:
		var rations := EconomyManager.get_total_rations()
		if rations > 0:
			WorldBlackboard.consume_rations(rations)
		EconomyManager.consume_daily_rations(2, 1)
		_overlay.call("refresh_all", false))
	hbox.add_child(btn_starve)


func switch_preview_city(city_id: String, tab_id: String = "guild") -> void:
	_current_city = EconomyManager.normalize_city_id(city_id)
	WorldBlackboard.current_city_id = _current_city
	_overlay.call("open_for_city", _current_city, tab_id)
	for cid: String in _city_buttons:
		var btn: Button = _city_buttons[cid]
		btn.modulate = Color("#ffe5aa") if cid == _current_city else Color("#d2c6b8")


func get_overlay() -> Control:
	return _overlay
