extends Control

const Kit := preload("res://ui/ui_theme_kit.gd")
const JournalOverlayScript := preload("res://ui/character_journal_overlay.gd")

var _title_font: Font
var _body_font: Font
var _journal_overlay: CanvasLayer
var _hud_layer: CanvasLayer
var _section_btns: Dictionary[String, Button] = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_font = Kit.make_font(true)
	_body_font = Kit.make_font(false)
	_seed_demo_journal()
	_build_preview()
	switch_section("diary")


func _seed_demo_journal() -> void:
	WorldBlackboard.reset_new_game()
	EconomyManager.reset_from_blackboard()
	JournalManager.reset_for_new_game()

	# Day 1 morning: Departure from Migurd Village
	JournalManager.add_entry(
		"milestone",
		"告别米格路德盆地",
		"背起学徒木杖与干粮行囊，回望薄雾笼罩的翡翠发聚落，正式踏上前往利卡里斯镇的荒原古道。",
		{"city_id": "city_migurd", "location": "米格路德村", "tone": "positive", "badge": "启程里程碑"},
		"demo:depart_migurd"
	)

	# Day 2 afternoon: Crit Fail during wilds watch
	WorldBlackboard.advance_time(5)
	JournalManager.record_dice_highlight(
		"潜行", 1, 13, false, true, "夜宿赤岩裂谷时遭遇游荡红蜥群"
	)

	# Day 3 evening: Starvation warning on road
	WorldBlackboard.advance_time(5)
	JournalManager.record_economy_event(
		"starvation",
		"干粮在风沙改道中消耗殆尽，饥肠辘辘之下全检定受到 -1 惩罚，急需赶往利卡里斯镇补给。",
		{
			"title": "旅途断粮警讯（第 1 日）",
			"tone": "negative",
			"badge": "断粮险情",
			"city_id": "city_migurd",
			"location": "比耶戈亚荒原",
			"dedupe_key": "demo:starvation_day3"
		}
	)

	# Day 4 morning: Arrive at Rikarisu Town -> unlocks geo_rikarisu & lore_adventurer_guild (unread!)
	WorldBlackboard.advance_time(2)
	WorldBlackboard.current_city_id = "city_rikarisu"
	EconomyManager.set_balance("demon_ore", 4500)
	EconomyManager.set_balance("millis", 400)
	JournalManager.record_city_arrival("city_rikarisu", "利卡里斯镇")

	# Day 4 afternoon: Guild 0% Exchange highlight
	WorldBlackboard.advance_time(1)
	JournalManager.record_economy_event(
		"guild_exchange",
		"在利卡里斯镇冒险者协会柜台按公定牌价将 10 大绿矿钱无损兑换为 2 米里斯大铜钱（免手续费 0%），并购妥 7 日份干粮。",
		{
			"title": "协会官方零费换汇与行囊整备",
			"tone": "positive",
			"badge": "免税换汇",
			"city_id": "city_rikarisu",
			"location": "利卡里斯镇",
			"currency_id": "millis",
			"dedupe_key": "demo:guild_exchange"
		}
	)

	# Day 4 evening: D20 Crit Success!
	WorldBlackboard.advance_time(1)
	JournalManager.record_dice_highlight(
		"察觉", 20, 14, true, false, "在利卡里斯镇酒馆角落听闻米里斯海港航线风声"
	)


func _build_preview() -> void:
	# Warm antique walnut backdrop behind the FolioOverlay blur
	var bg := ColorRect.new()
	bg.color = Color("#241a13")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_journal_overlay = JournalOverlayScript.new()
	add_child(_journal_overlay)
	_journal_overlay.call("set_preview_offset_top", 38.0, true)
	_journal_overlay.call("open_section", "diary")

	# Top preview control strip placed cleanly above FolioOverlay (layer 115)
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 125
	add_child(_hud_layer)

	var top_margin := MarginContainer.new()
	top_margin.anchor_left = 0.0
	top_margin.anchor_right = 1.0
	top_margin.anchor_top = 0.0
	top_margin.anchor_bottom = 0.0
	top_margin.offset_bottom = 74.0
	top_margin.add_theme_constant_override("margin_left", 28)
	top_margin.add_theme_constant_override("margin_right", 28)
	top_margin.add_theme_constant_override("margin_top", 10)
	top_margin.add_theme_constant_override("margin_bottom", 4)
	_hud_layer.add_child(top_margin)

	var bar := Kit.create_smoked_hud_panel(16, 8, 8)
	top_margin.add_child(bar)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	bar.add_child(hbox)

	var badge := Kit.create_badge("手账 V2 独立预览", Kit.WAX_GOLD, _title_font, 15)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(badge)

	for spec: Array in [
		["overview", "旅途总览（既有）"],
		["diary", "旅途日记"],
		["codex", "世界图鉴"]
	]:
		var sid := str(spec[0])
		var btn := Kit.create_tactile_button(str(spec[1]), "dark_brass", _body_font, 15)
		btn.custom_minimum_size = Vector2(152.0, 44.0)
		var captured := sid
		btn.pressed.connect(func() -> void: switch_section(captured))
		hbox.add_child(btn)
		_section_btns[sid] = btn

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var btn_crit := Kit.create_tactile_button("+ 记入大成功", "dark_brass", _body_font, 14)
	btn_crit.custom_minimum_size = Vector2(118.0, 44.0)
	btn_crit.pressed.connect(func() -> void:
		JournalManager.record_dice_highlight("水魔术", 20, 15, true, false, "演示检定"))
	hbox.add_child(btn_crit)

	var btn_milis := Kit.create_tactile_button("解锁米里斯图鉴", "dark_brass", _body_font, 14)
	btn_milis.custom_minimum_size = Vector2(132.0, 44.0)
	btn_milis.pressed.connect(func() -> void:
		JournalManager.record_city_arrival("city_milishion", "王都米里希翁"))
	hbox.add_child(btn_milis)

	var btn_reset := Kit.create_tactile_button("重置演示", "dark_brass", _body_font, 14)
	btn_reset.custom_minimum_size = Vector2(96.0, 44.0)
	btn_reset.pressed.connect(func() -> void:
		_seed_demo_journal()
		switch_section(str(_journal_overlay.call("get_active_section"))))
	hbox.add_child(btn_reset)


func switch_section(section_id: String) -> void:
	_journal_overlay.call("select_section", section_id, false)
	for sid: String in _section_btns:
		var btn: Button = _section_btns[sid]
		btn.modulate = Color("#ffe5aa") if sid == section_id else Color("#cfc2b3")


func get_journal_overlay() -> CanvasLayer:
	return _journal_overlay
