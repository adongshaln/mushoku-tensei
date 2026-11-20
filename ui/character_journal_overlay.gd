extends "res://ui/folio_overlay.gd"

const TABS: Array[String] = ["能力与特质", "修为与技能", "装束与行囊", "线索与纪事"]
const KitArt := preload("res://core/placeholder_art_factory.gd")

var _column: VBoxContainer
var _contents: VBoxContainer
var _active_tab := 0
var _displayed_portrait := ""
var _portrait: TextureRect
var _portrait_fallback: Control
var _identity: Label
var _heritage: Label
var _location: Label
var _date: Label
var _purse: Label
var _health: ProgressBar
var _mana: ProgressBar
var _health_caption: Label
var _mana_caption: Label
var _buff_row: HFlowContainer


func _ready() -> void:
	build("角色手账", Vector2(1472, 870))
	var spread := HBoxContainer.new()
	spread.add_theme_constant_override("separation", 27)
	spread.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(spread)

	var identity_frame := Kit.create_folio_panel(Kit.PAPER_DEEP, 23, 17, 2)
	identity_frame.custom_minimum_size.x = 382.0
	spread.add_child(identity_frame)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 9)
	identity_frame.add_child(_column)

	var portrait_frame := Kit.create_folio_panel(Color("#ddd2b8"), 12, 10, 2)
	portrait_frame.custom_minimum_size.y = 377.0
	_column.add_child(portrait_frame)
	var portrait_stage := Control.new()
	portrait_stage.custom_minimum_size = Vector2(305.0, 352.0)
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
	placeholder.add_child(Kit.create_micro_icon("star", 70, Kit.BLUE))

	_identity = line("", 37, Kit.INK, true)
	_column.add_child(_identity)
	_heritage = line("", 21, Kit.BLUE)
	_column.add_child(_heritage)
	_health = _meter("HP", Kit.VERMILLION)
	_health_caption = _health.get_meta("caption")
	_mana = _meter("MP", Kit.BLUE)
	_mana_caption = _mana.get_meta("caption")
	_location = line("", 20, Kit.INK)
	_date = line("", 18)
	_purse = line("", 20, Kit.INK)
	_column.add_child(_location)
	_column.add_child(_date)
	_column.add_child(_purse)
	_buff_row = HFlowContainer.new()
	_buff_row.add_theme_constant_override("h_separation", 8)
	_column.add_child(_buff_row)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 17)
	spread.add_child(right)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	right.add_child(tabs)
	var group := ButtonGroup.new()
	for index: int in TABS.size():
		var tab := Kit.create_tactile_button(TABS[index], "secondary", title_font, 22)
		tab.custom_minimum_size.y = 53.0
		tab.toggle_mode = true
		tab.button_group = group
		tab.set_pressed_no_signal(index == 0)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_select_tab.bind(index))
		tabs.add_child(tab)
	_contents = scroll_into(right)
	WorldBlackboard.world_time_changed.connect(_refresh)
	WorldBlackboard.state_changed.connect(_refresh)
	WorldBlackboard.flags_changed.connect(_refresh)


func open() -> void:
	reveal()
	_refresh()


func _select_tab(index: int) -> void:
	_active_tab = index
	_refresh()


func _refresh() -> void:
	if not is_open():
		return
	var profile := WorldBlackboard.profile
	_identity.text = str(profile.get("name", ""))
	var race: Dictionary = WorldBlackboard.catalog.races.get(str(profile.get("race_id", "")), {})
	_heritage.text = "%s  ·  %d 岁" % [race.get("label", profile.get("race_id", "")), WorldBlackboard.age()]
	_display_portrait(str(profile.get("portrait", "")), profile.get("portrait_crop", []))
	var resources := WorldBlackboard.resources
	_update_meter(_health, _health_caption, int(resources["hp"]), int(resources["max_hp"]))
	_update_meter(_mana, _mana_caption, int(resources["mp"]), int(resources["max_mp"]))
	_location.text = "所在地   " + WorldBlackboard.city_label()
	_date.text = WorldBlackboard.date_text()
	_purse.text = "钱币   " + WorldBlackboard.format_currency(WorldBlackboard.currency_copper)
	clear(_buff_row)
	for buff: String in WorldBlackboard.get_buff_names():
		_buff_row.add_child(Kit.create_badge(buff, Kit.BLUE, body_font, 17))

	clear(_contents)
	match _active_tab:
		0: _abilities()
		1: _proficiencies()
		2: _equipment()
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


func _meter(label: String, tone: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	_column.add_child(row)
	var name_label := line(label, 18, Kit.INK, true)
	name_label.custom_minimum_size.x = 38
	row.add_child(name_label)
	var bar := Kit.create_meter(tone)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var caption := line("", 18, Kit.INK)
	caption.custom_minimum_size.x = 72
	row.add_child(caption)
	bar.set_meta("caption", caption)
	return bar


func _update_meter(bar: ProgressBar, caption: Label, amount: int, maximum: int) -> void:
	bar.max_value = maxi(1, maximum)
	bar.value = amount
	caption.text = "%d / %d" % [amount, maximum]


func _heading(title: String) -> void:
	_contents.add_child(Kit.create_ribbon_header(title, title_font, 22, Kit.BLUE))


func _abilities() -> void:
	_heading("能力")
	var cards := GridContainer.new()
	cards.columns = 3
	cards.add_theme_constant_override("h_separation", 12)
	cards.add_theme_constant_override("v_separation", 10)
	_contents.add_child(cards)
	for key: String in WorldBlackboard.stats:
		var result := RuleEngine.collect_check(key)
		var card := Kit.create_folio_panel(Kit.PAPER_DEEP, 14, 10, 0)
		card.custom_minimum_size.y = 64.0
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cards.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var heading := Kit.create_label(WorldBlackboard.stat_label(key), 22, Kit.INK, title_font)
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(heading)
		var score := Kit.create_label(str(result["effective_stat"]), 30, Kit.INK, title_font)
		score.custom_minimum_size.x = 44.0
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		score.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(score)
		var amount := int(result["total_mod"])
		var badge := Kit.create_badge("%+d" % amount, Kit.BLUE if amount >= 0 else Kit.VERMILLION, body_font, 19)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)

	_heading("当前特质")
	var tags := HFlowContainer.new()
	tags.add_theme_constant_override("h_separation", 9)
	tags.add_theme_constant_override("v_separation", 8)
	_contents.add_child(tags)
	var labels: Dictionary = WorldBlackboard.catalog.definitions.get("traits", {})
	for tag: String in WorldBlackboard.actor_tags():
		tags.add_child(Kit.create_badge(str(labels.get(tag, tag)), Kit.BLUE, body_font, 18))

	_heading("人际与声望")
	var has_relation := false
	var relation_types: Dictionary = WorldBlackboard.catalog.definitions.get("relations", {})
	for group: String in WorldBlackboard.relations:
		var entries: Variant = WorldBlackboard.relations[group]
		if not entries is Dictionary or entries.is_empty():
			continue
		has_relation = true
		_contents.add_child(line(str(relation_types.get(group, group)), 19, Kit.BLUE))
		for id: String in entries:
			var entry: Variant = entries[id]
			var data: Dictionary = entry if entry is Dictionary else {"value": entry}
			var title := str(data.get("label", WorldBlackboard.catalog.city_names.get(id, id)))
			_contents.add_child(line("%s    %+d  %s" % [title, int(data.get("value", 0)), data.get("note", "")], 21, Kit.INK))
	if not has_relation:
		_contents.add_child(line("这一页留给旅途中相识的人和地方。"))


func _proficiencies() -> void:
	var definitions := WorldBlackboard.catalog.definitions
	var groups: Dictionary = definitions.get("groups", {})
	for id: String in WorldBlackboard.proficiencies:
		var values: Variant = WorldBlackboard.proficiencies[id]
		if not values is Dictionary:
			continue
		var definition: Dictionary = groups.get(id, {})
		var scale: Array = definitions.get(str(definition.get("scale", "")), [])
		var names: Dictionary = definition.get("items", {})
		_heading(str(definition.get("label", id)))
		for skill: String in values:
			var level := int(values[skill])
			var rank := "未习得" if level <= 0 else (str(scale[level - 1]) if level <= scale.size() else str(level))
			_contents.add_child(line("%s   ·   %s" % [names.get(skill, skill), rank], 22, Kit.MUTED if level <= 0 else Kit.INK))


func _equipment() -> void:
	_heading("装束")
	for slot_id: String in WorldBlackboard.catalog.slots:
		var definition: Dictionary = WorldBlackboard.catalog.slots[slot_id]
		var item_id := str(WorldBlackboard.equipment.get(slot_id, ""))
		var item: Dictionary = WorldBlackboard.catalog.items.get(item_id, {})
		var label := str(definition.get("label", slot_id))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_contents.add_child(row)
		var heading := line(label + "   ·   " + str(item.get("label", "空槽")), 21, Kit.INK)
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(heading)
		if not item.is_empty():
			row.add_child(_action("卸下", _equip.bind(slot_id, "")))
			_equipment_note(item)
		for candidate: String in WorldBlackboard.catalog.items:
			var record: Dictionary = WorldBlackboard.catalog.items[candidate]
			if candidate != item_id and str(record.get("slot", "")) == slot_id and WorldBlackboard.get_item_count(candidate) > 0:
				var button := _action("穿戴 · " + str(record.get("label", candidate)), _equip.bind(slot_id, candidate))
				_contents.add_child(button)
				_equipment_note(record)

	_heading("行囊")
	var items := WorldBlackboard.inventory_entries()
	for id: String in items:
		_contents.add_child(line("%s   × %d" % [items[id].get("name", id), WorldBlackboard.get_item_count(id)], 21, Kit.INK))
	var eat := _action("食用干粮  ·  剩余 %d 份" % WorldBlackboard.get_total_rations(), _eat)
	eat.disabled = WorldBlackboard.get_total_rations() < 1
	_contents.add_child(eat)


func _equipment_note(item: Dictionary) -> void:
	var notes := PackedStringArray()
	var description := str(item.get("description", ""))
	if not description.is_empty():
		notes.append(description)
	for tag: String in item.get("suppress_tags", []):
		var labels: Dictionary = WorldBlackboard.catalog.definitions.get("tags", {})
		notes.append("遮蔽 · " + str(labels.get(tag, tag)))
	for modifier: Dictionary in item.get("modifiers", []):
		notes.append("%s  %+d" % [RuleEngine.bonus_label(modifier), int(modifier.get("value", 0))])
	if not notes.is_empty():
		_contents.add_child(line("\n".join(notes), 18))


func _chronicle() -> void:
	_heading("已获得的线索")
	var flags := WorldBlackboard.flag_facts()
	var clues: Dictionary = WorldBlackboard.catalog.definitions.get("clues", {})
	var found := false
	for id: String in clues:
		if not bool(flags.get(id, false)):
			continue
		found = true
		_contents.add_child(line(str(clues[id]["title"]), 23, Kit.INK, true))
		_contents.add_child(line(str(clues[id]["text"])))
	if not found:
		_contents.add_child(line("还没有记下可追查的线索。"))
	_heading("旅程纪事")
	var events := WorldBlackboard.get_chronicle()
	events.reverse()
	for event: Dictionary in events:
		_contents.add_child(line(str(event.get("title", "")), 23, Kit.INK, true))
		_contents.add_child(line(str(event.get("date", "")) + "   " + str(event.get("text", "")), 18))
	if events.is_empty():
		_contents.add_child(line("旅程才刚开始。"))


func _action(text: String, callback: Callable) -> Button:
	var button := Kit.create_tactile_button(text, "secondary", title_font, 20)
	button.custom_minimum_size.y = 46.0
	button.pressed.connect(callback)
	return button


func _equip(slot: String, item: String) -> void:
	WorldBlackboard.equip_item(slot, item)


func _eat() -> void:
	if WorldBlackboard.consume_rations(1) == 1:
		WorldBlackboard.remove_buff(WorldBlackboard.TRAVEL_FATIGUE_ID)
