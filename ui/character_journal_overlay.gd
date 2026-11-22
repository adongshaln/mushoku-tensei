extends "res://ui/folio_overlay.gd"

const TABS: Array[Array] = [
	["star", "属性与特质"],
	["bag", "装束与行囊"],
	["scroll", "修为与语言"],
	["quill", "线索与纪事"]
]
const SLOT_ICONS: Dictionary[String, String] = {
	"weapon": "staff",
	"cloak": "cloak",
	"charm": "charm",
	"title": "crown"
}
const GROUP_ICONS: Dictionary[String, String] = {
	"magic": "drop",
	"sword": "sword",
	"languages": "scroll",
	"skills": "eye"
}
const KitArt := preload("res://core/placeholder_art_factory.gd")
const PropViewer := preload("res://ui/prop_3d_viewer.gd")
const DiceOverlay := preload("res://ui/dice_roll_overlay.gd")
const DiaryViewScript := preload("res://ui/journal_diary_view.gd")
const CodexViewScript := preload("res://ui/journal_codex_view.gd")

const PRIMARY_SECTIONS: Array[Array] = [
	["overview", "旅途总览"],
	["diary", "旅途日记"],
	["codex", "世界图鉴"]
]

const STUDIO_ITEMS: Array[Dictionary] = [
	{"id": "apprentice_staff", "label": "学徒木杖", "path": "res://assets/3d/props/wand_apprentice_water.glb", "tilt": -18.0, "cam": 1.24, "note": "枯岩木短杖配水蓝晶石与金环，拖拽可端详晶面折射。"},
	{"id": "old_silver_charm", "label": "旧银护符", "path": "res://assets/3d/props/charm_old_silver.glb", "tilt": 0.0, "cam": 1.28, "note": "米格路德族绞丝银坠，翻转背面可见六瓣星花镂空纹。"},
	{"id": "guild_card_f", "label": "F 级铭牌", "path": "res://assets/3d/props/guild_card_f.glb", "tilt": 0.0, "cam": 1.28, "note": "冒险者公会铜质铭牌，背面蚀刻交叉剑杖徽记。"},
	{"id": "coin_copper", "label": "铜币", "path": "res://assets/3d/props/coin_asura_copper.glb", "tilt": 0.0, "cam": 1.28, "note": "阿斯拉通用铜币，七棱城楼压纹，旅途日常最常用。"},
	{"id": "coin_silver", "label": "银币", "path": "res://assets/3d/props/coin_asura_silver.glb", "tilt": 0.0, "cam": 1.28, "note": "阿斯拉八角银币（1 银 = 100 铜），浮雕剑盾纹章。"},
	{"id": "coin_gold", "label": "金币", "path": "res://assets/3d/props/coin_asura_gold.glb", "tilt": 0.0, "cam": 1.28, "note": "阿斯拉王冠金币（1 金 = 100 银），重铸圆环王冠印。"}
]
const STUDIO_DICE: Array[Dictionary] = [
	{"id": "d4", "label": "D4", "path": "res://assets/3d/dice/d4_skin.glb", "cam": 1.38, "note": "四面釉瓷骰 · 顶角读数，用于轻巧随机与微弱增益。"},
	{"id": "d6", "label": "D6", "path": "res://assets/3d/dice/d6_skin.glb", "cam": 1.34, "note": "六面釉瓷骰 · 古铜倒角，标准旅途与基础波动骰。"},
	{"id": "d8", "label": "D8", "path": "res://assets/3d/dice/d8_skin.glb", "cam": 1.34, "note": "八面釉瓷骰 · 海雾蓝釉，中阶技艺与魔术波动骰。"},
	{"id": "d10", "label": "D10", "path": "res://assets/3d/dice/d10_skin.glb", "cam": 1.36, "note": "十面釉瓷骰 · 鸢形切面，十进制刻度与高阶检定。"},
	{"id": "d12", "label": "D12", "path": "res://assets/3d/dice/d12_skin.glb", "cam": 1.32, "note": "十二面釉瓷骰 · 五边形釉面，重击与强效法术骰。"},
	{"id": "d20", "label": "D20", "path": "res://assets/3d/d20_skin.glb", "cam": 1.30, "note": "二十面釉瓷骰 · 命运主检定骰，承载全部核心判定。"}
]

var _column: VBoxContainer
var _overview_spread: HBoxContainer
var _diary_view: HBoxContainer
var _codex_view: HBoxContainer
var _section_buttons: Dictionary[String, Button] = {}
var _active_section := "overview"
var _contents: VBoxContainer
var _content_holder: Control
var _tab_buttons: Array[Button] = []
var _active_tab := 0
var _expanded_slot := ""
var _show_unlearned := false
var _displayed_portrait := ""
var _portrait: TextureRect
var _portrait_fallback: Control
var _identity: Label
var _heritage: Label
var _location: Label
var _date: Label
var _purse: Label
var _coin_viewer: PropViewer
var _health: ProgressBar
var _mana: ProgressBar
var _health_caption: Label
var _mana_caption: Label
var _buff_row: HFlowContainer
var _feedback_bar: PanelContainer
var _feedback_label: Label
var _studio_card: PanelContainer
var _prop_viewer: PropViewer
var _studio_title: Label
var _studio_badge: Label
var _studio_note: Label
var _studio_roll_btn: Button
var _studio_buttons: Dictionary[String, Button] = {}
var _studio_active_id := "apprentice_staff"
var _studio_active_die := ""
var _dice_overlay: DiceOverlay


func _ready() -> void:
	build("旅途手账", Vector2(1548.0, 900.0), true, 0.285)
	_mount_primary_section_tabs()

	var spread := HBoxContainer.new()
	spread.add_theme_constant_override("separation", 42)
	spread.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(spread)
	_overview_spread = spread

	# Left open-book page: illustrated portrait & character bio.
	var left_page := MarginContainer.new()
	left_page.custom_minimum_size.x = 374.0
	left_page.add_theme_constant_override("margin_top", 4)
	left_page.add_theme_constant_override("margin_bottom", 4)
	spread.add_child(left_page)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 8)
	left_page.add_child(_column)

	var portrait_frame := Kit.create_folio_panel(Color("#e3d6be"), 8, 8, 3)
	portrait_frame.custom_minimum_size.y = 358.0
	_column.add_child(portrait_frame)
	var portrait_stage := Control.new()
	portrait_stage.custom_minimum_size = Vector2(318.0, 338.0)
	portrait_frame.add_child(portrait_stage)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_stage.add_child(_portrait)
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var placeholder := CenterContainer.new()
	_portrait_fallback = placeholder
	portrait_stage.add_child(placeholder)
	placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	placeholder.add_child(Kit.create_micro_icon("star", 64.0, Kit.AMBER))
	var marks := Kit.CornerMarks.new()
	marks.setup(Kit.WAX_GOLD, 6.0, 18.0)
	portrait_stage.add_child(marks)
	marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	_column.add_child(name_row)
	_identity = Kit.create_label("", 36, Kit.INK, title_font)
	_identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_identity)
	var seal := Kit.WaxSeal.new()
	seal.setup(Kit.SAPPHIRE, "star", 36.0)
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(seal)

	_heritage = Kit.create_label("", 19, Kit.SAPPHIRE, body_font)
	_column.add_child(_heritage)
	_health = _meter("hp", "HP", Kit.VERMILLION)
	_health_caption = _health.get_meta("caption")
	_mana = _meter("drop", "MP", Kit.SAPPHIRE)
	_mana_caption = _mana.get_meta("caption")

	_column.add_child(Kit.create_gold_divider(0.0, false, 8.0))
	_location = _info_row("compass", Kit.SAPPHIRE)
	_date = _info_row("morning", Kit.WAX_GOLD)
	_purse = _purse_row()

	var status_label := Kit.create_label("当前状态", 15, Kit.MUTED, body_font)
	_column.add_child(status_label)
	_buff_row = HFlowContainer.new()
	_buff_row.add_theme_constant_override("h_separation", 8)
	_buff_row.add_theme_constant_override("v_separation", 6)
	_column.add_child(_buff_row)

	# Right open-book page: 4-tab illustrated ledger.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	spread.add_child(right)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	right.add_child(tabs)
	var group := ButtonGroup.new()
	for index: int in TABS.size():
		var tab := Kit.create_gold_tab_button(str(TABS[index][1]), title_font, 22)
		tab.button_group = group
		tab.set_pressed_no_signal(index == 0)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_select_tab.bind(index))
		tabs.add_child(tab)
		_tab_buttons.append(tab)
	right.add_child(Kit.create_gold_divider(0.0, false, 6.0))

	_content_holder = VBoxContainer.new()
	_content_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_holder.add_theme_constant_override("separation", 10)
	right.add_child(_content_holder)
	_build_prop_studio()
	_contents = scroll_into(_content_holder)

	_dice_overlay = DiceOverlay.new()
	add_child(_dice_overlay)
	_dice_overlay.layer = 130

	_feedback_bar = Kit.create_smoked_hud_panel(16, 8, 4)
	_feedback_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feedback_label = line("", 18, Kit.BRASS, true)
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_bar.add_child(_feedback_label)
	_feedback_bar.hide()
	right.add_child(_feedback_bar)

	_diary_view = DiaryViewScript.new()
	_diary_view.call("setup", title_font, body_font)
	_diary_view.hide()
	page.add_child(_diary_view)

	_codex_view = CodexViewScript.new()
	_codex_view.call("setup", title_font, body_font)
	_codex_view.hide()
	page.add_child(_codex_view)

	WorldBlackboard.world_time_changed.connect(_refresh)
	WorldBlackboard.state_changed.connect(_refresh)
	WorldBlackboard.flags_changed.connect(_refresh)
	if has_node("/root/JournalManager"):
		var jm: Node = get_node("/root/JournalManager")
		if jm.has_signal("journal_state_changed"):
			jm.connect("journal_state_changed", _on_journal_manager_changed)
		if jm.has_signal("codex_read_changed"):
			jm.connect("codex_read_changed", _on_codex_unread_changed)
	if has_node("/root/EconomyManager"):
		var eco: Node = get_node("/root/EconomyManager")
		if eco.has_signal("economy_state_changed"):
			eco.connect("economy_state_changed", _refresh)


func _mount_primary_section_tabs() -> void:
	title_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var section_bar := HBoxContainer.new()
	section_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	section_bar.add_theme_constant_override("separation", 14)

	var sec_group := ButtonGroup.new()
	for spec: Array in PRIMARY_SECTIONS:
		var sid := str(spec[0])
		var slabel := str(spec[1])
		var btn := Kit.create_gold_tab_button(slabel, title_font, 23)
		btn.button_group = sec_group
		btn.custom_minimum_size = Vector2(158.0, 48.0)
		btn.set_pressed_no_signal(sid == _active_section)
		var captured := sid
		btn.pressed.connect(func() -> void: select_section(captured, true))
		section_bar.add_child(btn)
		_section_buttons[sid] = btn

	header.add_child(section_bar)
	header.move_child(section_bar, maxi(0, header.get_child_count() - 2))
	var settings_btn := Kit.create_icon_button("gear", "", "dark_brass", title_font, 18, Kit.BRASS)
	settings_btn.custom_minimum_size = Vector2(46.0, 46.0)
	settings_btn.tooltip_text = "系统设置"
	settings_btn.pressed.connect(func() -> void:
		if has_node("/root/JournalUI"):
			get_node("/root/JournalUI").call("open_settings", ""))
	header.add_child(settings_btn)
	header.move_child(settings_btn, maxi(0, header.get_child_count() - 2))
	_update_codex_tab_badge()


func open() -> void:
	_feedback_bar.hide()
	_sync_section_visibility(false)
	_sync_tab_underlines()
	reveal()
	_refresh()


func open_section(section_id: String, codex_entry_id: String = "") -> void:
	if section_id in ["overview", "diary", "codex"]:
		_active_section = section_id
	if not is_open():
		open()
	else:
		select_section(_active_section, true)
	if _active_section == "codex" and not codex_entry_id.is_empty():
		_codex_view.call("select_entry", codex_entry_id, true)


func select_section(section_id: String, animate: bool = true) -> void:
	if section_id not in ["overview", "diary", "codex"]:
		return
	_active_section = section_id
	_feedback_bar.hide()
	_sync_section_visibility(animate)
	_refresh()
	if is_open() and animate:
		AudioManager.play_sfx("page_flip")


func get_active_section() -> String:
	return _active_section


func get_diary_view() -> Control:
	return _diary_view


func get_codex_view() -> Control:
	return _codex_view


func set_preview_offset_top(offset_px: float, hide_close_btn: bool = false) -> void:
	if binding != null:
		var half_h := binding.custom_minimum_size.y * 0.5
		binding.offset_top = -half_h + offset_px
		binding.offset_bottom = half_h + offset_px
	if hide_close_btn and header != null and header.get_child_count() > 0:
		var last := header.get_child(header.get_child_count() - 1)
		if last is Button:
			(last as Button).visible = false


func _sync_section_visibility(animate: bool) -> void:
	for sid: String in _section_buttons:
		var btn: Button = _section_buttons[sid]
		var active := sid == _active_section
		btn.set_pressed_no_signal(active)
		var underline := btn.get_meta(&"gold_underline", null) as Control
		if underline != null:
			if animate and is_open():
				Motion.fade_alpha(underline, 1.0 if active else 0.0, 0.18)
			else:
				underline.modulate.a = 1.0 if active else 0.0
	_overview_spread.visible = _active_section == "overview"
	_diary_view.visible = _active_section == "diary"
	_codex_view.visible = _active_section == "codex"
	_update_codex_tab_badge()
	if animate and is_open():
		var target: Control = _overview_spread if _active_section == "overview" else (_diary_view if _active_section == "diary" else _codex_view)
		Motion.fade_in(target, 0.22)
		Motion.spring(target, ^"position:x", 22.0, 0.0, 0.32, 9.2, 7.0)


func _update_codex_tab_badge() -> void:
	if not _section_buttons.has("codex"):
		return
	var unread := 0
	if has_node("/root/JournalManager"):
		unread = int(get_node("/root/JournalManager").call("get_unread_codex_count"))
	var btn: Button = _section_buttons["codex"]
	btn.text = "世界图鉴  ●%d" % unread if unread > 0 else "世界图鉴"


func _on_codex_unread_changed(_unread_count: int) -> void:
	_update_codex_tab_badge()


func _on_journal_manager_changed() -> void:
	_update_codex_tab_badge()
	if not is_open():
		return
	if _active_section == "diary":
		_diary_view.call("refresh", false)
	elif _active_section == "codex":
		_codex_view.call("refresh", false, false)


func select_tab(index: int) -> void:
	if index >= 0 and index < TABS.size():
		_select_tab(index)


func _select_tab(index: int) -> void:
	_active_tab = index
	_feedback_bar.hide()
	for i: int in _tab_buttons.size():
		_tab_buttons[i].set_pressed_no_signal(i == index)
	_sync_tab_underlines()
	_refresh()
	if is_open():
		Motion.fade_in(_content_holder, 0.20)
		Motion.spring(_content_holder, ^"position:x", 20.0, 0.0, 0.30, 9.2, 7.0)
		AudioManager.play_sfx("page_flip")


func _sync_tab_underlines() -> void:
	for i: int in _tab_buttons.size():
		var underline := _tab_buttons[i].get_meta(&"gold_underline", null) as Control
		if underline != null:
			Motion.fade_alpha(underline, 1.0 if i == _active_tab else 0.0, 0.18)


func _refresh() -> void:
	if not is_open():
		return
	_update_codex_tab_badge()
	if _active_section == "diary":
		_diary_view.call("refresh", false)
		return
	if _active_section == "codex":
		_codex_view.call("refresh", false, false)
		return
	var profile := WorldBlackboard.profile
	_identity.text = str(profile.get("name", ""))
	_heritage.text = "%s  ·  %d 岁" % [WorldBlackboard.race_label(), WorldBlackboard.age()]
	_display_portrait(str(profile.get("portrait", "")), profile.get("portrait_crop", []))
	var resources := WorldBlackboard.resources
	_update_meter(_health, _health_caption, int(resources.get("hp", 0)), int(resources.get("max_hp", 1)))
	_update_meter(_mana, _mana_caption, int(resources.get("mp", 0)), int(resources.get("max_mp", 1)))
	_location.text = WorldBlackboard.city_label()
	_date.text = WorldBlackboard.date_text().replace("   ", " ")
	_purse.text = WorldBlackboard.get_currency_display_text()
	_sync_purse_coin_3d()

	clear(_buff_row)
	var statuses := WorldBlackboard.active_statuses()
	var eco_mods: Array = []
	if has_node("/root/EconomyManager"):
		var raw_mods: Variant = get_node("/root/EconomyManager").call("get_active_modifiers_list")
		if raw_mods is Array:
			eco_mods = raw_mods
	if statuses.is_empty() and eco_mods.is_empty():
		_buff_row.add_child(Kit.create_label("气息平稳 · 无附加状态", 16, Color("#8f7a64"), body_font))
	else:
		for status: Dictionary in statuses:
			var polarity := WorldBlackboard.status_polarity(status)
			_buff_row.add_child(Kit.create_status_badge(str(status.get("name", status.get("id", "状态"))), polarity >= 0, body_font, 15))
		for mod_var: Variant in eco_mods:
			if mod_var is Dictionary:
				var mod: Dictionary = mod_var
				var val := int(mod.get("value", 0))
				_buff_row.add_child(Kit.create_status_badge("%s %+d" % [str(mod.get("name", "")), val], val >= 0, body_font, 15))

	_studio_card.visible = _active_tab == 1
	if _active_tab == 1:
		_refresh_studio_status()

	clear(_contents)
	match _active_tab:
		0: _abilities()
		1: _equipment_and_bag()
		2: _proficiencies()
		3: _chronicle()


func _display_portrait(path: String, framing: Array) -> void:
	if path != _displayed_portrait:
		_displayed_portrait = path
		_portrait.texture = KitArt.load_texture(path) if not path.is_empty() else null
		if _portrait.texture != null and framing.size() == 4:
			var dimensions := _portrait.texture.get_size()
			var area := Rect2(Vector2(float(framing[0]), float(framing[1])) * dimensions,
				Vector2(float(framing[2]), float(framing[3])) * dimensions)
			var crop := AtlasTexture.new()
			crop.atlas = _portrait.texture
			crop.region = area.intersection(Rect2(Vector2.ZERO, dimensions))
			_portrait.texture = crop
	_portrait_fallback.visible = _portrait.texture == null


func _info_row(icon_kind: String, tone: Color) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	_column.add_child(row)
	var ic := Kit.create_micro_icon(icon_kind, 18.0, tone)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var lbl := Kit.create_label("", 18, Kit.INK, body_font)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(lbl)
	return lbl


func _purse_row() -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	_column.add_child(row)
	_coin_viewer = PropViewer.new()
	_coin_viewer.custom_minimum_size = Vector2(26.0, 26.0)
	_coin_viewer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_coin_viewer)
	_coin_viewer.configure(false, 1.15, 1.18)
	var lbl := Kit.create_label("", 18, Kit.INK, body_font)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(lbl)
	return lbl


func _sync_purse_coin_3d() -> void:
	if _coin_viewer == null:
		return
	var copper := WorldBlackboard.currency_copper
	var coin_path := "res://assets/3d/props/coin_asura_copper.glb"
	if copper >= 10000:
		coin_path = "res://assets/3d/props/coin_asura_gold.glb"
	elif copper >= 100:
		coin_path = "res://assets/3d/props/coin_asura_silver.glb"
	_coin_viewer.set_model(coin_path, 0.0, 1.18)


func _build_prop_studio() -> void:
	_studio_card = Kit.create_folio_panel(Color("#ede2ce"), 14, 12, 3)
	_studio_card.hide()
	_content_holder.add_child(_studio_card)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 14)
	_studio_card.add_child(split)

	var stage_box := Kit.create_smoked_hud_panel(6, 6, 4, Color("#1b130df2"), Color("#cfa259b8"))
	stage_box.custom_minimum_size = Vector2(214.0, 186.0)
	split.add_child(stage_box)
	var stage_inner := Control.new()
	stage_inner.custom_minimum_size = Vector2(200.0, 172.0)
	stage_box.add_child(stage_inner)
	_prop_viewer = PropViewer.new()
	stage_inner.add_child(_prop_viewer)
	_prop_viewer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_prop_viewer.configure(true, 0.56, 1.28)
	var marks := Kit.CornerMarks.new()
	marks.setup(Color(Kit.BRASS, 0.68), 4.0, 14.0)
	stage_inner.add_child(marks)
	marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var drag_hint := Kit.create_label("拖拽 360° 端详", 12, Color("#d4bc97cc"), body_font)
	drag_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_inner.add_child(drag_hint)
	drag_hint.anchor_left = 0.0
	drag_hint.anchor_right = 1.0
	drag_hint.anchor_top = 1.0
	drag_hint.anchor_bottom = 1.0
	drag_hint.offset_top = -18.0
	drag_hint.offset_bottom = -1.0

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 7)
	split.add_child(info)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	info.add_child(head)
	_studio_title = Kit.create_label("学徒木杖", 22, Kit.INK, title_font)
	head.add_child(_studio_title)
	_studio_badge = Kit.create_label("", 14, Kit.SAPPHIRE, title_font)
	_studio_badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_studio_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_studio_badge)
	var flip_btn := Kit.create_tactile_button("翻转背面", "subtle", title_font, 14)
	flip_btn.custom_minimum_size = Vector2(92.0, 38.0)
	flip_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_hover")
		_prop_viewer.flip_side())
	head.add_child(flip_btn)
	_studio_roll_btn = Kit.create_tactile_button("3D 试掷", "primary", title_font, 15)
	_studio_roll_btn.custom_minimum_size = Vector2(94.0, 38.0)
	_studio_roll_btn.pressed.connect(_roll_studio_die)
	_studio_roll_btn.hide()
	head.add_child(_studio_roll_btn)

	_studio_note = line("", 15, Kit.MUTED)
	info.add_child(_studio_note)

	var prop_row := HBoxContainer.new()
	prop_row.add_theme_constant_override("separation", 6)
	info.add_child(prop_row)
	prop_row.add_child(Kit.create_label("器物", 14, Kit.MUTED, title_font))
	for item: Dictionary in STUDIO_ITEMS:
		var item_id := str(item["id"])
		var chip := _make_studio_chip(str(item["label"]), body_font)
		chip.pressed.connect(_select_studio_entry.bind(item_id, false))
		prop_row.add_child(chip)
		_studio_buttons[item_id] = chip

	var dice_row := HBoxContainer.new()
	dice_row.add_theme_constant_override("separation", 6)
	info.add_child(dice_row)
	dice_row.add_child(Kit.create_label("骰匣", 14, Kit.MUTED, title_font))
	for die: Dictionary in STUDIO_DICE:
		var die_id := str(die["id"])
		var chip := _make_studio_chip(str(die["label"]), title_font)
		chip.pressed.connect(_select_studio_entry.bind(die_id, true))
		dice_row.add_child(chip)
		_studio_buttons[die_id] = chip

	_select_studio_entry("apprentice_staff", false)


func _make_studio_chip(label_text: String, font: Font) -> Button:
	var chip := Kit.create_tactile_button(label_text, "secondary", font, 14)
	chip.toggle_mode = true
	chip.custom_minimum_size = Vector2(0.0, 38.0)
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var active_box := Kit.style(Color("#241912f2"), 10, 6, 3, 1, Kit.BRASS)
	active_box.set_corner_radius_all(7)
	chip.add_theme_stylebox_override("pressed", active_box)
	chip.add_theme_stylebox_override("hover_pressed", active_box)
	chip.add_theme_color_override("font_pressed_color", Kit.IVORY)
	chip.add_theme_color_override("font_hover_pressed_color", Color("#fff6e0"))
	return chip


func _select_studio_entry(entry_id: String, is_die: bool) -> void:
	_studio_active_id = entry_id
	_studio_active_die = entry_id if is_die else ""
	var source: Array[Dictionary] = STUDIO_DICE if is_die else STUDIO_ITEMS
	var chosen: Dictionary = {}
	for entry: Dictionary in source:
		if str(entry["id"]) == entry_id:
			chosen = entry
			break
	if chosen.is_empty():
		return
	_studio_title.text = str(chosen["label"])
	_studio_note.text = str(chosen["note"])
	_studio_roll_btn.visible = is_die
	_prop_viewer.set_model(str(chosen["path"]), float(chosen.get("tilt", 0.0)), float(chosen.get("cam", 1.28)))
	_refresh_studio_status()
	if is_open():
		AudioManager.play_sfx("ui_click")


func _refresh_studio_status() -> void:
	for key: String in _studio_buttons:
		_studio_buttons[key].set_pressed_no_signal(key == _studio_active_id)
	if not _studio_active_die.is_empty():
		_studio_badge.text = "海雾蓝釉多面骰 · 可试掷"
		return
	var copper := WorldBlackboard.currency_copper
	match _studio_active_id:
		"coin_copper":
			_studio_badge.text = "当前持有 %d 枚铜币" % (copper % 100)
		"coin_silver":
			@warning_ignore("integer_division")
			var silver := copper / 100 % 100
			_studio_badge.text = "当前持有 %d 枚银币" % silver if silver > 0 else "暂未持有 · 图鉴端详"
		"coin_gold":
			@warning_ignore("integer_division")
			var gold := copper / 10000
			_studio_badge.text = "当前持有 %d 枚金币" % gold if gold > 0 else "暂未持有 · 图鉴端详"
		_:
			var owned := WorldBlackboard.get_item_count(_studio_active_id) > 0
			var worn := false
			for slot_key: String in WorldBlackboard.equipment:
				if str(WorldBlackboard.equipment[slot_key]) == _studio_active_id:
					worn = true
					break
			_studio_badge.text = "穿戴中" if worn else ("行囊持有" if owned else "旅途图鉴 · 尚未入手")


func _roll_studio_die() -> void:
	if _studio_active_die.is_empty() or _dice_overlay == null or _dice_overlay.is_active():
		return
	var die_id := _studio_active_die
	_dice_overlay.present_polyhedral(die_id, "%s 釉瓷骰试掷" % die_id.to_upper(), "米格路德旅途骰匣", 0, false)


func inspect_studio_item(entry_id: String, is_die: bool = false) -> void:
	_select_studio_entry(entry_id, is_die)


func trigger_studio_die_roll(die_id: String, fixed_roll: int = 0) -> void:
	_select_studio_entry(die_id, true)
	if _dice_overlay != null:
		_dice_overlay.present_polyhedral(die_id, "%s 釉瓷骰试掷" % die_id.to_upper(), "米格路德旅途骰匣", fixed_roll, true)


func _meter(icon_kind: String, label_text: String, tone: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_column.add_child(row)
	var icon := Kit.create_micro_icon(icon_kind, 18.0, tone)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var name_label := Kit.create_label(label_text, 16, Kit.INK, title_font)
	name_label.custom_minimum_size.x = 30.0
	row.add_child(name_label)
	var bar := Kit.create_meter(tone, Color("#d4c3a7"), 11.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var caption := Kit.create_label("", 16, Kit.INK, body_font)
	caption.custom_minimum_size.x = 64.0
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(caption)
	bar.set_meta("caption", caption)
	return bar


func _update_meter(bar: ProgressBar, caption: Label, amount: int, maximum: int) -> void:
	bar.max_value = maxi(1, maximum)
	bar.value = amount
	caption.text = "%d / %d" % [amount, maximum]


func _heading(title: String) -> void:
	_contents.add_child(Kit.create_ribbon_header(title, title_font, 22, Kit.WAX_GOLD))


func _abilities() -> void:
	_heading("六维星盘与 D20 修正")
	var top_split := HBoxContainer.new()
	top_split.add_theme_constant_override("separation", 18)
	_contents.add_child(top_split)

	# Left: Custom vector astronomical stat radar chart.
	var radar_frame := Kit.create_folio_panel(Kit.PAPER_DEEP, 10, 10, 2)
	radar_frame.custom_minimum_size = Vector2(266.0, 248.0)
	top_split.add_child(radar_frame)
	var radar_labels: Array[String] = []
	var radar_values: Array[float] = []
	for key: String in WorldBlackboard.stats:
		var res := RuleEngine.collect_check(key)
		radar_labels.append(WorldBlackboard.stat_label(key))
		radar_values.append(float(res["effective_stat"]))
	var radar := Kit.StatRadarChart.new()
	radar.setup(radar_labels, radar_values, title_font)
	radar_frame.add_child(radar)

	# Right: 2x3 crafted stat medallion cards.
	var cards := GridContainer.new()
	cards.columns = 2
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cards.add_theme_constant_override("h_separation", 12)
	cards.add_theme_constant_override("v_separation", 10)
	top_split.add_child(cards)
	for key: String in WorldBlackboard.stats:
		var result := RuleEngine.collect_check(key)
		var card := Kit.create_folio_panel(Kit.PAPER_DEEP, 14, 11, 2)
		card.custom_minimum_size.y = 74.0
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cards.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var label_box := VBoxContainer.new()
		label_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label_box.alignment = BoxContainer.ALIGNMENT_CENTER
		label_box.add_theme_constant_override("separation", 0)
		row.add_child(label_box)
		label_box.add_child(Kit.create_label(WorldBlackboard.stat_label(key), 22, Kit.INK, title_font))
		label_box.add_child(Kit.create_label(key, 12, Color("#8b7660"), body_font))
		var score := Kit.create_label(str(result["effective_stat"]), 30, Kit.INK, title_font)
		score.custom_minimum_size.x = 40.0
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		score.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(score)
		var amount := int(result["total_mod"])
		var badge := Kit.create_status_badge("%+d" % amount, amount >= 0, title_font, 19)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)

	_heading("角色特质")
	var tags := HFlowContainer.new()
	tags.add_theme_constant_override("h_separation", 10)
	tags.add_theme_constant_override("v_separation", 8)
	_contents.add_child(tags)
	var labels: Dictionary = WorldBlackboard.catalog.definitions.get("traits", {})
	for tag: String in WorldBlackboard.actor_tags():
		tags.add_child(Kit.create_status_badge(str(labels.get(tag, tag)), true, body_font, 16))

	_heading("人际与声望")
	var has_relation := false
	var relation_types: Dictionary = WorldBlackboard.catalog.definitions.get("relations", {})
	for group: String in WorldBlackboard.relations:
		var entries: Variant = WorldBlackboard.relations[group]
		if not entries is Dictionary or entries.is_empty():
			continue
		has_relation = true
		_contents.add_child(Kit.create_label(str(relation_types.get(group, group)), 18, Kit.SAPPHIRE, title_font))
		for id: String in entries:
			var entry: Variant = entries[id]
			var data: Dictionary = entry if entry is Dictionary else {"value": entry}
			var title := str(data.get("label", WorldBlackboard.catalog.city_names.get(id, id)))
			var val := int(data.get("value", 0))
			var rel_card := Kit.create_folio_panel(Kit.PAPER_DEEP, 14, 9, 1)
			_contents.add_child(rel_card)
			var rel_row := HBoxContainer.new()
			rel_row.add_theme_constant_override("separation", 10)
			rel_card.add_child(rel_row)
			var rel_name := Kit.create_label(title, 20, Kit.INK, title_font)
			rel_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rel_row.add_child(rel_name)
			rel_row.add_child(Kit.create_status_badge("%+d" % val, val >= 0, title_font, 17))
			var note := str(data.get("note", ""))
			if not note.is_empty():
				rel_row.add_child(Kit.create_label(note, 17, Kit.MUTED, body_font))
	if not has_relation:
		var blank := Kit.create_folio_panel(Color("#efe5d4"), 18, 14, 0)
		blank.add_child(line("旅途初启，这一页留给往后相识的旅伴、城镇与阵营声望。", 18, Color("#8a7560")))
		_contents.add_child(blank)


func _equipment_and_bag() -> void:
	_heading("随身装束")
	var slot_ids := WorldBlackboard.catalog.ordered_slot_ids()
	var slot_grid := GridContainer.new()
	slot_grid.columns = 2
	slot_grid.add_theme_constant_override("h_separation", 12)
	slot_grid.add_theme_constant_override("v_separation", 12)
	_contents.add_child(slot_grid)

	for slot_id: String in slot_ids:
		var definition: Dictionary = WorldBlackboard.catalog.slots.get(slot_id, {})
		var item_id := str(WorldBlackboard.equipment.get(slot_id, ""))
		var equipped: Dictionary = WorldBlackboard.catalog.items.get(item_id, {})
		var candidates := _owned_candidates_for_slot(slot_id, item_id)
		var expanded := _expanded_slot == slot_id

		var card := Kit.create_folio_panel(Kit.PAPER if expanded else Kit.PAPER_DEEP, 14, 12, 4 if expanded else 1)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot_grid.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)

		# Brass-rimmed equipment socket icon (lights up gold when equipped).
		var socket := Kit.create_smoked_hud_panel(10, 10, 2, Color("#241a12f0") if not equipped.is_empty() else Color("#3b2d21c0"), Kit.BRASS if not equipped.is_empty() else Color("#8a6e4b88"))
		socket.custom_minimum_size = Vector2(54.0, 54.0)
		socket.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var center := CenterContainer.new()
		socket.add_child(center)
		var ic_kind: String = str(SLOT_ICONS.get(slot_id, "star"))
		center.add_child(Kit.create_micro_icon(ic_kind, 26.0, Kit.BRASS if not equipped.is_empty() else Color("#a69178")))
		row.add_child(socket)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		info.add_theme_constant_override("separation", 3)
		row.add_child(info)
		var top_line := HBoxContainer.new()
		top_line.add_theme_constant_override("separation", 8)
		info.add_child(top_line)
		top_line.add_child(Kit.create_label(str(definition.get("label", slot_id)), 15, Kit.MUTED, body_font))
		if not equipped.is_empty():
			top_line.add_child(Kit.create_status_badge("已穿戴", true, body_font, 13))
		elif not candidates.is_empty():
			top_line.add_child(Kit.create_badge("可选 %d" % candidates.size(), Kit.SAPPHIRE, body_font, 13))

		var eq_name := str(equipped.get("label", str(definition.get("empty_hint", "空槽"))))
		var eq_lbl := Kit.create_label(eq_name, 20, Kit.INK if not equipped.is_empty() else Color("#8f7a64"), title_font)
		eq_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		info.add_child(eq_lbl)

		var btn := _action("收起" if expanded else ("更换" if not equipped.is_empty() else "选择"), "dark_brass" if expanded else "secondary", _toggle_slot.bind(slot_id))
		btn.custom_minimum_size = Vector2(82.0, 44.0)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(btn)

	# Inline detail & equip selector tray directly under the 2x2 socket grid when a slot is selected.
	if not _expanded_slot.is_empty() and WorldBlackboard.catalog.slots.has(_expanded_slot):
		var slot_id := _expanded_slot
		var definition: Dictionary = WorldBlackboard.catalog.slots[slot_id]
		var item_id := str(WorldBlackboard.equipment.get(slot_id, ""))
		var equipped: Dictionary = WorldBlackboard.catalog.items.get(item_id, {})
		var candidates := _owned_candidates_for_slot(slot_id, item_id)

		var tray := Kit.create_folio_panel(Color("#f8f2e7"), 18, 14, 4)
		_contents.add_child(tray)
		var tbox := VBoxContainer.new()
		tbox.add_theme_constant_override("separation", 10)
		tray.add_child(tbox)
		var thead := HBoxContainer.new()
		thead.add_theme_constant_override("separation", 10)
		tbox.add_child(thead)
		var th_lbl := Kit.create_label("装束整备 · " + str(definition.get("label", slot_id)), 20, Kit.INK, title_font)
		th_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		thead.add_child(th_lbl)
		if not equipped.is_empty():
			var unequip_btn := _action("卸下当前", "subtle", _equip.bind(slot_id, "", str(equipped.get("label", ""))))
			unequip_btn.custom_minimum_size = Vector2(114.0, 44.0)
			thead.add_child(unequip_btn)

		if not equipped.is_empty():
			_append_equipment_details(tbox, equipped)
		tbox.add_child(Kit.create_gold_divider(0.0, false, 6.0))
		if candidates.is_empty():
			tbox.add_child(line("行囊中没有其他可装备在此槽位的物品。", 17, Color("#8b7660")))
		else:
			for candidate_id: String in candidates:
				var record: Dictionary = WorldBlackboard.catalog.items[candidate_id]
				var opt_card := Kit.create_folio_panel(Kit.PAPER_DEEP, 14, 10, 1)
				tbox.add_child(opt_card)
				var opt_col := VBoxContainer.new()
				opt_col.add_theme_constant_override("separation", 6)
				opt_card.add_child(opt_col)
				var opt_row := HBoxContainer.new()
				opt_row.add_theme_constant_override("separation", 10)
				opt_col.add_child(opt_row)
				var opt_title := Kit.create_label(str(record.get("label", candidate_id)), 20, Kit.INK, title_font)
				opt_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				opt_row.add_child(opt_title)
				var wear_btn := _action("穿戴", "primary", _equip.bind(slot_id, candidate_id, str(record.get("label", candidate_id))))
				wear_btn.custom_minimum_size = Vector2(96.0, 44.0)
				opt_row.add_child(wear_btn)
				_append_equipment_details(opt_col, record)

	_heading("行囊清单")
	var items := WorldBlackboard.inventory_entries()
	if items.is_empty():
		_contents.add_child(line("行囊空空如也。", 19, Color("#8b7660")))
		return
	for id: String in items:
		var count := WorldBlackboard.get_item_count(id)
		var item_panel := Kit.create_folio_panel(Kit.PAPER_DEEP, 15, 10, 1)
		_contents.add_child(item_panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		item_panel.add_child(row)

		var icon_name := "bag"
		var icon_col := Kit.MUTED
		if WorldBlackboard.is_ration_item(id):
			icon_name = "ration"
			icon_col = Kit.WAX_GOLD
		elif WorldBlackboard.catalog.items.has(id):
			icon_name = str(SLOT_ICONS.get(str(WorldBlackboard.catalog.items[id].get("slot", "")), "staff"))
			icon_col = Kit.SAPPHIRE
		var ic := Kit.create_micro_icon(icon_name, 22.0, icon_col)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)

		var name_text := str(items[id].get("name", id))
		var name_lbl := Kit.create_label("%s   × %d" % [name_text, count], 20, Kit.INK, title_font)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(name_lbl)

		if WorldBlackboard.is_ration_item(id):
			row.add_child(Kit.create_status_badge("干粮", true, body_font, 15))
			var eat_btn := _action("食用 1 份", "accent", _eat_item.bind(id, name_text))
			eat_btn.custom_minimum_size = Vector2(118.0, 44.0)
			eat_btn.disabled = count < 1
			row.add_child(eat_btn)
		elif WorldBlackboard.catalog.items.has(id):
			var equip_def: Dictionary = WorldBlackboard.catalog.items[id]
			var target_slot := str(equip_def.get("slot", ""))
			var is_worn := str(WorldBlackboard.equipment.get(target_slot, "")) == id
			if is_worn:
				row.add_child(Kit.create_status_badge("穿戴中", true, body_font, 15))
			else:
				var quick_wear := _action("穿戴", "secondary", _equip.bind(target_slot, id, name_text))
				quick_wear.custom_minimum_size = Vector2(92.0, 44.0)
				row.add_child(quick_wear)
		else:
			row.add_child(Kit.create_badge("随身物", Kit.MUTED, body_font, 15))


func _owned_candidates_for_slot(slot_id: String, current_item_id: String) -> Array[String]:
	var result: Array[String] = []
	for candidate_id: String in WorldBlackboard.catalog.items:
		var record: Dictionary = WorldBlackboard.catalog.items[candidate_id]
		if candidate_id != current_item_id and str(record.get("slot", "")) == slot_id and WorldBlackboard.get_item_count(candidate_id) > 0:
			result.append(candidate_id)
	return result


func _append_equipment_details(target: VBoxContainer, item: Dictionary) -> void:
	var description := str(item.get("description", ""))
	if not description.is_empty():
		target.add_child(line(description, 17, Kit.MUTED))
	var tag_flow := HFlowContainer.new()
	tag_flow.add_theme_constant_override("h_separation", 8)
	tag_flow.add_theme_constant_override("v_separation", 6)
	var tag_labels: Dictionary = WorldBlackboard.catalog.definitions.get("tags", {})
	var added := false
	for tag: String in item.get("tags", []):
		tag_flow.add_child(Kit.create_badge(str(tag_labels.get(tag, tag)), Kit.MUTED, body_font, 15))
		added = true
	for suppress_tag: String in item.get("suppress_tags", []):
		tag_flow.add_child(Kit.create_status_badge("遮蔽 · " + str(tag_labels.get(suppress_tag, suppress_tag)), true, body_font, 15))
		added = true
	for modifier: Dictionary in item.get("modifiers", []):
		var val := int(modifier.get("value", 0))
		tag_flow.add_child(Kit.create_status_badge("%s %+d" % [RuleEngine.bonus_label(modifier), val], val >= 0, body_font, 15))
		added = true
	if added:
		target.add_child(tag_flow)


func _proficiencies() -> void:
	var definitions := WorldBlackboard.catalog.definitions
	var groups: Dictionary = definitions.get("groups", {})
	var unlearned_names: PackedStringArray = []
	var unlearned_details: Array[Dictionary] = []

	for id: String in WorldBlackboard.proficiencies:
		var values: Variant = WorldBlackboard.proficiencies[id]
		if not values is Dictionary:
			continue
		var definition: Dictionary = groups.get(id, {})
		var scale: Array = definitions.get(str(definition.get("scale", "")), [])
		var names: Dictionary = definition.get("items", {})
		var group_label := str(definition.get("label", id))
		var learned_items: Array[Dictionary] = []
		for skill: String in values:
			var level := int(values[skill])
			var item_label := str(names.get(skill, skill))
			if level > 0:
				var rank := str(scale[level - 1]) if level <= scale.size() else "第 %d 阶" % level
				learned_items.append({"name": item_label, "rank": rank, "level": level, "max_level": maxi(1, scale.size())})
			else:
				unlearned_names.append(item_label)
				unlearned_details.append({"group": group_label, "name": item_label})

		if learned_items.is_empty():
			continue
		_heading(group_label)
		for entry: Dictionary in learned_items:
			var card := Kit.create_folio_panel(Kit.PAPER_DEEP, 16, 12, 1)
			_contents.add_child(card)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 14)
			card.add_child(row)
			var g_icon := Kit.create_micro_icon(str(GROUP_ICONS.get(id, "star")), 22.0, Kit.SAPPHIRE if id == "magic" else Kit.WAX_GOLD)
			g_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(g_icon)
			var n_lbl := Kit.create_label(str(entry["name"]), 21, Kit.INK, title_font)
			n_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			n_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(n_lbl)
			var pips := Kit.RankPipBar.new()
			pips.setup(int(entry["level"]), int(entry["max_level"]), Kit.SAPPHIRE if id == "magic" else Kit.WAX_GOLD)
			pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(pips)
			var r_badge := Kit.create_status_badge(str(entry["rank"]), true, body_font, 16)
			r_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(r_badge)

	if not unlearned_names.is_empty():
		_contents.add_child(Kit.create_gold_divider(0.0, false, 10.0))
		var fold_panel := Kit.create_folio_panel(Color("#efe5d4"), 16, 12, 0)
		_contents.add_child(fold_panel)
		var fold_box := VBoxContainer.new()
		fold_box.add_theme_constant_override("separation", 8)
		fold_panel.add_child(fold_box)
		var fold_row := HBoxContainer.new()
		fold_row.add_theme_constant_override("separation", 10)
		fold_box.add_child(fold_row)
		var summary_text := "尚未习得的修为与语言（%d 项）：%s" % [unlearned_names.size(), "、".join(unlearned_names)]
		var summary_lbl := line(summary_text, 17, Color("#8b7660"))
		summary_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fold_row.add_child(summary_lbl)
		var toggle := _action("收起" if _show_unlearned else "展开", "subtle", _toggle_unlearned)
		toggle.custom_minimum_size = Vector2(84.0, 44.0)
		fold_row.add_child(toggle)
		if _show_unlearned:
			for item: Dictionary in unlearned_details:
				fold_box.add_child(line("%s  ·  %s（未习得）" % [item["group"], item["name"]], 17, Color("#96826c")))


func _chronicle() -> void:
	_heading("已获得的线索")
	var flags := WorldBlackboard.flag_facts()
	var clues: Dictionary = WorldBlackboard.catalog.definitions.get("clues", {})
	var found := false
	for id: String in clues:
		if not bool(flags.get(id, false)):
			continue
		found = true
		var clue_card := Kit.create_folio_panel(Kit.PAPER_DEEP, 16, 12, 2)
		_contents.add_child(clue_card)
		var crow := HBoxContainer.new()
		crow.add_theme_constant_override("separation", 12)
		clue_card.add_child(crow)
		var pin := Kit.create_micro_icon("star", 18.0, Kit.WAX_GOLD)
		pin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		crow.add_child(pin)
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 4)
		crow.add_child(box)
		box.add_child(line(str(clues[id]["title"]), 21, Kit.INK, true))
		box.add_child(line(str(clues[id]["text"]), 17, Kit.MUTED))
	if not found:
		var empty_clue := Kit.create_folio_panel(Color("#efe5d4"), 16, 12, 0)
		empty_clue.add_child(line("还没有记下可追查的线索，多去村口与旅途间留心听闻吧。", 18, Color("#8b7660")))
		_contents.add_child(empty_clue)

	_heading("旅程纪事")
	var events := WorldBlackboard.get_chronicle()
	events.reverse()
	for event: Dictionary in events:
		var ev_row := HBoxContainer.new()
		ev_row.add_theme_constant_override("separation", 12)
		_contents.add_child(ev_row)

		# Vertical golden timeline stem & diamond node.
		var rail := VBoxContainer.new()
		rail.custom_minimum_size.x = 20.0
		rail.alignment = BoxContainer.ALIGNMENT_CENTER
		ev_row.add_child(rail)
		rail.add_child(Kit.create_micro_icon("star", 16.0, Kit.WAX_GOLD))
		var stem := ColorRect.new()
		stem.color = Color(Kit.WAX_GOLD, 0.45)
		stem.custom_minimum_size = Vector2(2.0, 28.0)
		stem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		stem.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rail.add_child(stem)

		var ev_card := Kit.create_folio_panel(Kit.PAPER_DEEP, 16, 11, 1)
		ev_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ev_row.add_child(ev_card)
		var ev_box := VBoxContainer.new()
		ev_box.add_theme_constant_override("separation", 4)
		ev_card.add_child(ev_box)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 10)
		ev_box.add_child(top)
		var title_lbl := Kit.create_label(str(event.get("title", "")), 21, Kit.INK, title_font)
		title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(title_lbl)
		top.add_child(Kit.create_label(str(event.get("date", "")).replace("   ", " "), 15, Kit.SAPPHIRE, body_font))
		var text := str(event.get("text", ""))
		if not text.is_empty():
			ev_box.add_child(line(text, 17, Kit.MUTED))
	if events.is_empty():
		var empty_ev := Kit.create_folio_panel(Color("#efe5d4"), 16, 12, 0)
		empty_ev.add_child(line("旅程才刚开始，翻开的第一页还留着墨香。", 18, Color("#8b7660")))
		_contents.add_child(empty_ev)

	_contents.add_child(Kit.create_gold_divider(0.0, false, 8.0))
	var jump_row := HBoxContainer.new()
	jump_row.add_theme_constant_override("separation", 12)
	_contents.add_child(jump_row)
	var to_diary := _action("翻阅完整旅途日记 →", "secondary", select_section.bind("diary", true))
	to_diary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jump_row.add_child(to_diary)
	var to_codex := _action("查阅六面世界图鉴 →", "primary", select_section.bind("codex", true))
	to_codex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jump_row.add_child(to_codex)


func _action(text: String, style_name: String, callback: Callable) -> Button:
	var button := Kit.create_tactile_button(text, style_name, title_font, 18)
	button.custom_minimum_size.y = 44.0
	button.pressed.connect(callback)
	return button


func _toggle_slot(slot_id: String) -> void:
	_expanded_slot = "" if _expanded_slot == slot_id else slot_id
	if not _expanded_slot.is_empty():
		var equipped_id := str(WorldBlackboard.equipment.get(slot_id, ""))
		var focus_id := equipped_id
		if focus_id.is_empty():
			var cands := _owned_candidates_for_slot(slot_id, "")
			if not cands.is_empty():
				focus_id = cands[0]
		if not focus_id.is_empty():
			if _studio_buttons.has(focus_id):
				_select_studio_entry(focus_id, false)
			else:
				var rec: Dictionary = WorldBlackboard.catalog.items.get(focus_id, {})
				var custom_model := str(rec.get("model_3d", ""))
				if not custom_model.is_empty():
					_studio_active_id = focus_id
					_studio_active_die = ""
					_studio_title.text = str(rec.get("label", focus_id))
					_studio_note.text = str(rec.get("description", ""))
					_studio_roll_btn.hide()
					_prop_viewer.set_model(custom_model, float(rec.get("model_tilt_deg", 0.0)), 1.28)
					_refresh_studio_status()
	_refresh()


func _toggle_unlearned() -> void:
	_show_unlearned = not _show_unlearned
	_refresh()


func _equip(slot: String, item: String, label_text: String) -> void:
	if WorldBlackboard.equip_item(slot, item):
		_expanded_slot = ""
		AudioManager.play_sfx("page_flip")
		_show_feedback("已卸下「%s」。" % label_text if item.is_empty() else "已穿戴「%s」。" % label_text)


func _eat_item(item_id: String, label_text: String) -> void:
	var had_fatigue := WorldBlackboard.has_buff(WorldBlackboard.TRAVEL_FATIGUE_ID)
	if WorldBlackboard.eat_ration(item_id):
		AudioManager.play_sfx("ui_click")
		_show_feedback("食用了「%s」，旅途疲惫已消散。" % label_text if had_fatigue else "食用了「%s」，体力稍有恢复。" % label_text)


func _show_feedback(text: String) -> void:
	_feedback_label.text = text
	_feedback_bar.show()
	Motion.fade_in(_feedback_bar, 0.18)
