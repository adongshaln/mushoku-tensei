extends Node

signal diary_entry_added(entry: Dictionary)
signal diary_changed
signal codex_unlocked(entry_id: String, entry_data: Dictionary)
signal codex_read_changed(unread_count: int)
signal journal_state_changed

const CODEX_PATH := "res://data/codex/world_codex.json"
const MAX_DIARY_ENTRIES := 500
const VALID_CATEGORIES: Array[String] = ["travel", "economy", "dice", "milestone"]
const CATEGORY_LABELS: Dictionary[String, String] = {
	"travel": "行程",
	"economy": "商贸",
	"dice": "命运",
	"milestone": "里程碑"
}

var _categories: Array[Dictionary] = []
var _categories_by_id: Dictionary[String, Dictionary] = {}
var _codex_entries: Array[Dictionary] = []
var _codex_by_id: Dictionary[String, Dictionary] = {}

var _diary_entries: Array[Dictionary] = []
var _dedupe_index: Dictionary[String, int] = {}
var _next_seq := 1

var _unlocked_codex: Dictionary[String, Dictionary] = {}
var _unread_codex: Dictionary[String, bool] = {}

var _initialized := false
var _last_observed_city := ""
var _last_hunger_days := 0
var _had_well_rested := false


func _ready() -> void:
	_load_codex_config()
	reset_for_new_game()
	SaveManager.register_save_module("journal", serialize_state, deserialize_state)
	WorldBlackboard.location_changed.connect(_on_world_location_changed)
	WorldBlackboard.flags_changed.connect(_on_world_flags_changed)
	WorldBlackboard.chronicle_recorded.connect(_on_world_chronicle_recorded)
	if has_node("/root/RuleEngine"):
		var re: Node = get_node("/root/RuleEngine")
		if re.has_signal("check_resolved"):
			re.connect("check_resolved", _on_rule_check_resolved)
	if has_node("/root/EconomyManager"):
		var eco: Node = get_node("/root/EconomyManager")
		if eco.has_signal("wallet_changed"):
			eco.connect("wallet_changed", _on_economy_wallet_changed)
		if eco.has_signal("survival_state_changed"):
			eco.connect("survival_state_changed", _on_economy_survival_changed)
		if eco.has_signal("exchange_completed"):
			eco.connect("exchange_completed", _on_economy_exchange_completed)
		if eco.has_signal("purchase_completed"):
			eco.connect("purchase_completed", _on_economy_purchase_completed)
	_initialized = true


func _load_codex_config() -> void:
	var raw := WorldBlackboard.read_config(CODEX_PATH)
	_categories.clear()
	_categories_by_id.clear()
	for cat_var: Variant in raw.get("categories", []):
		if cat_var is Dictionary:
			var copy := (cat_var as Dictionary).duplicate(true)
			var cid := str(copy.get("id", ""))
			if not cid.is_empty():
				_categories.append(copy)
				_categories_by_id[cid] = copy
	_categories.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("order", 99)) < int(b.get("order", 99)))

	_codex_entries.clear()
	_codex_by_id.clear()
	for entry_var: Variant in raw.get("entries", []):
		if entry_var is Dictionary:
			var copy := (entry_var as Dictionary).duplicate(true)
			var eid := str(copy.get("id", ""))
			if not eid.is_empty():
				_codex_entries.append(copy)
				_codex_by_id[eid] = copy


func reset_for_new_game() -> void:
	_diary_entries.clear()
	_dedupe_index.clear()
	_next_seq = 1
	_unlocked_codex.clear()
	_unread_codex.clear()
	_last_observed_city = WorldBlackboard.current_city_id
	_last_hunger_days = 0
	_had_well_rested = false
	for entry: Dictionary in _codex_entries:
		if bool(entry.get("default_unlocked", false)):
			var eid := str(entry["id"])
			_unlocked_codex[eid] = {"source": "手账基础收录", "date": _date_stamp()}
	sync_codex_from_world(false)
	_import_world_chronicle()
	diary_changed.emit()
	codex_read_changed.emit(get_unread_codex_count())
	journal_state_changed.emit()


# ── Travel Diary Engine ────────────────────────────────────────────────────────

func add_entry(category: String, title: String, body: String, meta: Dictionary = {}, dedupe_key: String = "") -> Dictionary:
	var clean_cat := category if category in VALID_CATEGORIES else "milestone"
	var clean_title := title.strip_edges()
	if clean_title.is_empty():
		clean_title = CATEGORY_LABELS.get(clean_cat, "手记")
	var clean_body := body.strip_edges()
	var clean_key := dedupe_key.strip_edges()

	if not clean_key.is_empty() and _dedupe_index.has(clean_key):
		var existing_seq := int(_dedupe_index[clean_key])
		for existing: Dictionary in _diary_entries:
			if int(existing.get("seq", -1)) == existing_seq:
				return existing.duplicate(true)

	var wt := WorldBlackboard.get_world_time()
	var date_str := str(meta.get("date_text", _date_stamp()))
	var city_id := str(meta.get("city_id", WorldBlackboard.current_city_id))
	var loc_name := str(meta.get("location", _city_name(city_id)))
	var tone := str(meta.get("tone", _default_tone_for_category(clean_cat)))
	if tone not in ["positive", "negative", "neutral"]:
		tone = "neutral"
	var badge := str(meta.get("badge", CATEGORY_LABELS.get(clean_cat, "手记")))

	var seq := _next_seq
	_next_seq += 1
	var entry: Dictionary = {
		"id": "entry_%04d" % seq,
		"seq": seq,
		"category": clean_cat,
		"tone": tone,
		"badge": badge,
		"title": clean_title,
		"body": clean_body,
		"date_text": date_str,
		"world_time": wt.duplicate(true),
		"city_id": city_id,
		"location": loc_name,
		"dedupe_key": clean_key,
		"meta": meta.duplicate(true)
	}
	_diary_entries.append(entry)
	if not clean_key.is_empty():
		_dedupe_index[clean_key] = seq

	while _diary_entries.size() > MAX_DIARY_ENTRIES:
		var removed: Dictionary = _diary_entries.pop_front()
		var rem_key := str(removed.get("dedupe_key", ""))
		if not rem_key.is_empty() and int(_dedupe_index.get(rem_key, -1)) == int(removed.get("seq", -2)):
			_dedupe_index.erase(rem_key)

	var copy := entry.duplicate(true)
	diary_entry_added.emit(copy)
	diary_changed.emit()
	journal_state_changed.emit()
	return copy


func record_city_arrival(city_id: String, city_name: String = "") -> Dictionary:
	var resolved_id := _normalize_city_id(city_id)
	var resolved_name := city_name.strip_edges()
	if resolved_name.is_empty():
		resolved_name = _city_name(resolved_id)
	_last_observed_city = resolved_id
	var unlocked_ids := _unlock_codex_for_city(resolved_id, "抵达" + resolved_name, true)
	var wt := WorldBlackboard.get_world_time()
	var dkey := "arrival:%s:%d-%d-%d" % [resolved_id, int(wt["year"]), int(wt["month"]), int(wt["day"])]
	var body := "风尘仆仆地踏入%s，将沿途风物与当地所见记入手账。" % resolved_name
	if not unlocked_ids.is_empty():
		var unlocked_titles := PackedStringArray()
		for eid: String in unlocked_ids:
			unlocked_titles.append("「%s」" % str(_codex_by_id[eid].get("title", eid)))
		body += " 同时收录了新图鉴：%s。" % "、".join(unlocked_titles)
	return add_entry(
		"travel",
		"抵达%s" % resolved_name,
		body,
		{
			"city_id": resolved_id,
			"location": resolved_name,
			"tone": "positive" if not unlocked_ids.is_empty() else "neutral",
			"badge": "新地踏足" if not unlocked_ids.is_empty() else "行程",
			"unlocked_codex": unlocked_ids
		},
		dkey
	)


func record_dice_highlight(skill_name: String, roll: int, dc: int,
		is_crit_success: bool, is_crit_fail: bool, context: String = "", dedupe_key: String = "") -> Dictionary:
	var skill := skill_name.strip_edges()
	if skill.is_empty():
		skill = "命运"
	var title := ""
	var badge := "命运"
	var tone := "neutral"
	var body := ""
	var ctx_prefix := ("%s之际，" % context.strip_edges()) if not context.strip_edges().is_empty() else ""

	if is_crit_success:
		tone = "positive"
		badge = "大成功 ★"
		title = "命运眷顾 · %s大成功（自然 %d）" % [skill, roll]
		body = "%s二十面釉瓷骰稳稳定格在自然 %d（目标 DC %d），奇迹般化解了眼前的考验。" % [ctx_prefix, roll, dc]
	elif is_crit_fail:
		tone = "negative"
		badge = "大失败"
		title = "惊险波折 · %s大失败（自然 %d）" % [skill, roll]
		body = "%s二十面釉瓷骰不幸翻出自然 %d（目标 DC %d），局势骤生变数，只得咬牙周旋。" % [ctx_prefix, roll, dc]
	else:
		var passed := roll >= dc
		tone = "positive" if passed else "negative"
		badge = "检定通过" if passed else "检定受挫"
		title = "%s检定%s（%d / DC %d）" % [skill, "通过" if passed else "失利", roll, dc]
		body = "%s此番%s检定投出 %d 对抗 DC %d，%s。" % [
			ctx_prefix, skill, roll, dc, "顺利达成所愿" if passed else "未能如愿，另寻他法"
		]

	return add_entry(
		"dice",
		title,
		body,
		{
			"skill_name": skill,
			"roll": roll,
			"dc": dc,
			"is_crit_success": is_crit_success,
			"is_crit_fail": is_crit_fail,
			"context": context,
			"tone": tone,
			"badge": badge
		},
		dedupe_key
	)


func record_economy_event(event_type: String, summary: String, meta: Dictionary = {}) -> Dictionary:
	var et := event_type.strip_edges().to_lower()
	var title_map: Dictionary[String, String] = {
		"exchange": "跨币种换汇记录",
		"guild_exchange": "冒险者协会官方换汇",
		"cross_currency": "外币折算直付结账",
		"inn_rest": "旅馆投宿休整",
		"luxury_rest": "舒适套房沐浴安眠",
		"meal": "酒馆热食补给",
		"bulk_supply": "整备旅途干粮行囊",
		"starvation": "旅途断粮警讯",
		"ferry_ticket": "购置跨海客船船票"
	}
	var badge_map: Dictionary[String, String] = {
		"exchange": "商贸换汇",
		"guild_exchange": "免税换汇",
		"cross_currency": "外币折算",
		"inn_rest": "旅宿休整",
		"luxury_rest": "精力充沛",
		"meal": "饱腹暖胃",
		"bulk_supply": "行囊补给",
		"starvation": "断粮险情",
		"ferry_ticket": "跨海航运"
	}
	var default_tone := "neutral"
	if et in ["starvation", "hungry", "forced_march"]:
		default_tone = "negative"
	elif et in ["guild_exchange", "luxury_rest", "inn_rest", "meal"]:
		default_tone = "positive"

	var enriched_meta := meta.duplicate(true)
	enriched_meta["event_type"] = et
	if not enriched_meta.has("tone"):
		enriched_meta["tone"] = default_tone
	if not enriched_meta.has("badge"):
		enriched_meta["badge"] = badge_map.get(et, "商贸")

	if enriched_meta.has("currency_id"):
		_unlock_codex_for_currency(str(enriched_meta["currency_id"]), "商贸流转", true)

	var title := str(enriched_meta.get("title", title_map.get(et, "商贸见闻")))
	var dedupe_key := str(enriched_meta.get("dedupe_key", ""))
	return add_entry("economy", title, summary, enriched_meta, dedupe_key)


func get_diary_entries(category: String = "all", keyword: String = "", newest_first: bool = true) -> Array[Dictionary]:
	var clean_cat := category.strip_edges().to_lower()
	var query := keyword.strip_edges().to_lower()
	var out: Array[Dictionary] = []
	for entry: Dictionary in _diary_entries:
		if clean_cat != "all" and not clean_cat.is_empty() and str(entry.get("category", "")) != clean_cat:
			continue
		if not query.is_empty():
			var haystack := "%s %s %s %s %s" % [
				str(entry.get("title", "")),
				str(entry.get("body", "")),
				str(entry.get("location", "")),
				str(entry.get("badge", "")),
				str(entry.get("date_text", ""))
			]
			if not haystack.to_lower().contains(query):
				continue
		out.append(entry.duplicate(true))
	if newest_first:
		out.reverse()
	return out


func get_diary_count(category: String = "all") -> int:
	if category == "all" or category.is_empty():
		return _diary_entries.size()
	var count := 0
	for entry: Dictionary in _diary_entries:
		if str(entry.get("category", "")) == category:
			count += 1
	return count


func get_diary_category_counts() -> Dictionary[String, int]:
	var counts: Dictionary[String, int] = {
		"all": _diary_entries.size(),
		"travel": 0,
		"economy": 0,
		"dice": 0,
		"milestone": 0
	}
	for entry: Dictionary in _diary_entries:
		var cat := str(entry.get("category", "milestone"))
		counts[cat] = int(counts.get(cat, 0)) + 1
	return counts


func clear_diary() -> void:
	_diary_entries.clear()
	_dedupe_index.clear()
	diary_changed.emit()
	journal_state_changed.emit()


# ── World Codex Engine ─────────────────────────────────────────────────────────

func get_codex_categories() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cat: Dictionary in _categories:
		out.append(cat.duplicate(true))
	return out


func get_codex_category_label(category_id: String) -> String:
	var cat: Dictionary = _categories_by_id.get(category_id, {})
	return str(cat.get("name", category_id))


func get_codex_entries(category: String = "all") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _codex_entries:
		var cat := str(entry.get("category", ""))
		if category != "all" and not category.is_empty() and cat != category:
			continue
		out.append(_decorate_codex_entry(entry))
	return out


func get_codex_entry(entry_id: String) -> Dictionary:
	if not _codex_by_id.has(entry_id):
		return {}
	return _decorate_codex_entry(_codex_by_id[entry_id])


func is_codex_unlocked(entry_id: String) -> bool:
	return _unlocked_codex.has(entry_id)


func is_codex_unread(entry_id: String) -> bool:
	return _unlocked_codex.has(entry_id) and bool(_unread_codex.get(entry_id, false))


func unlock_codex(entry_id: String, source_hint: String = "", mark_as_unread: bool = true) -> bool:
	if not _codex_by_id.has(entry_id) or _unlocked_codex.has(entry_id):
		return false
	var hint := source_hint.strip_edges()
	if hint.is_empty():
		hint = "旅途见闻收录"
	_unlocked_codex[entry_id] = {
		"source": hint,
		"date": _date_stamp()
	}
	if mark_as_unread:
		_unread_codex[entry_id] = true
	var decorated := _decorate_codex_entry(_codex_by_id[entry_id])
	codex_unlocked.emit(entry_id, decorated)
	codex_read_changed.emit(get_unread_codex_count())
	journal_state_changed.emit()
	return true


func mark_codex_read(entry_id: String) -> bool:
	if not _unread_codex.has(entry_id):
		return false
	_unread_codex.erase(entry_id)
	codex_read_changed.emit(get_unread_codex_count())
	journal_state_changed.emit()
	return true


func mark_all_codex_read() -> void:
	if _unread_codex.is_empty():
		return
	_unread_codex.clear()
	codex_read_changed.emit(0)
	journal_state_changed.emit()


func get_unread_codex_count() -> int:
	var count := 0
	for eid: String in _unread_codex:
		if _unlocked_codex.has(eid) and bool(_unread_codex[eid]):
			count += 1
	return count


func get_codex_progress() -> Dictionary:
	var total := _codex_entries.size()
	var unlocked := 0
	for entry: Dictionary in _codex_entries:
		if _unlocked_codex.has(str(entry["id"])):
			unlocked += 1
	return {
		"unlocked": unlocked,
		"total": total,
		"unread": get_unread_codex_count(),
		"ratio": float(unlocked) / float(maxi(1, total))
	}


func sync_codex_from_world(mark_new_unread: bool = false) -> int:
	var newly_unlocked := 0
	var cur_city := _normalize_city_id(WorldBlackboard.current_city_id)
	if not cur_city.is_empty():
		newly_unlocked += _unlock_codex_for_city(cur_city, "身处" + _city_name(cur_city), mark_new_unread).size()

	var flags := WorldBlackboard.flag_facts()
	for flag_key: String in flags:
		if bool(flags[flag_key]):
			newly_unlocked += _unlock_codex_for_flag(flag_key, "旅途见闻", mark_new_unread).size()

	if has_node("/root/EconomyManager"):
		var eco: Node = get_node("/root/EconomyManager")
		var held_var: Variant = eco.call("get_held_currencies", false)
		if held_var is Array:
			for h: Variant in held_var:
				if h is Dictionary and int((h as Dictionary).get("min_units", 0)) > 0:
					var cid := str((h as Dictionary).get("currency_id", ""))
					newly_unlocked += _unlock_codex_for_currency(cid, "持有通货", mark_new_unread).size()
	return newly_unlocked


# ── SaveManager Persistence ────────────────────────────────────────────────────

func serialize_state() -> Dictionary:
	var entries_copy: Array[Dictionary] = []
	for entry: Dictionary in _diary_entries:
		entries_copy.append(entry.duplicate(true))
	var unlocked_copy: Dictionary = {}
	for eid: String in _unlocked_codex:
		unlocked_copy[eid] = _unlocked_codex[eid].duplicate(true)
	var unread_list: Array[String] = []
	for eid: String in _unread_codex:
		if _unlocked_codex.has(eid) and bool(_unread_codex[eid]):
			unread_list.append(eid)
	unread_list.sort()
	return {
		"schema_version": 1,
		"next_seq": _next_seq,
		"diary_entries": entries_copy,
		"unlocked_codex": unlocked_copy,
		"unread_codex": unread_list
	}


func deserialize_state(payload: Dictionary) -> bool:
	if not payload is Dictionary:
		return false
	# Legacy save or fresh new_game lacking journal module: initialize defaults & sync world cleanly.
	if payload.is_empty() or (not payload.has("diary_entries") and not payload.has("unlocked_codex")):
		reset_for_new_game()
		return true

	_diary_entries.clear()
	_dedupe_index.clear()
	var max_seq := 0
	var raw_entries: Variant = payload.get("diary_entries", [])
	if raw_entries is Array:
		for item: Variant in raw_entries:
			if item is Dictionary:
				var copy := (item as Dictionary).duplicate(true)
				var seq := int(copy.get("seq", max_seq + 1))
				copy["seq"] = seq
				if str(copy.get("id", "")).is_empty():
					copy["id"] = "entry_%04d" % seq
				max_seq = maxi(max_seq, seq)
				_diary_entries.append(copy)
				var dkey := str(copy.get("dedupe_key", "")).strip_edges()
				if not dkey.is_empty():
					_dedupe_index[dkey] = seq
	while _diary_entries.size() > MAX_DIARY_ENTRIES:
		_diary_entries.pop_front()
	_next_seq = maxi(max_seq + 1, int(payload.get("next_seq", max_seq + 1)))

	_unlocked_codex.clear()
	for entry: Dictionary in _codex_entries:
		if bool(entry.get("default_unlocked", false)):
			var eid := str(entry["id"])
			_unlocked_codex[eid] = {"source": "手账基础收录", "date": _date_stamp()}
	var raw_unlocked: Variant = payload.get("unlocked_codex", {})
	if raw_unlocked is Dictionary:
		for key: Variant in raw_unlocked:
			var eid := str(key)
			if not _codex_by_id.has(eid):
				continue
			var val: Variant = raw_unlocked[key]
			if val is Dictionary:
				_unlocked_codex[eid] = (val as Dictionary).duplicate(true)
			elif bool(val):
				_unlocked_codex[eid] = {"source": "旅途收录", "date": ""}

	_unread_codex.clear()
	var raw_unread: Variant = payload.get("unread_codex", [])
	if raw_unread is Array:
		for item: Variant in raw_unread:
			var eid := str(item)
			if _unlocked_codex.has(eid):
				_unread_codex[eid] = true
	elif raw_unread is Dictionary:
		for key: Variant in raw_unread:
			var eid := str(key)
			if _unlocked_codex.has(eid) and bool(raw_unread[key]):
				_unread_codex[eid] = true

	_last_observed_city = WorldBlackboard.current_city_id
	if has_node("/root/EconomyManager"):
		var eco: Node = get_node("/root/EconomyManager")
		_last_hunger_days = int(eco.get("hunger_days"))
		var mods: Variant = eco.get("active_modifiers")
		_had_well_rested = mods is Dictionary and (mods as Dictionary).has("well_rested")
	# Ensure current city & flags codex are synced without adding spurious unread flags.
	sync_codex_from_world(false)
	diary_changed.emit()
	codex_read_changed.emit(get_unread_codex_count())
	journal_state_changed.emit()
	return true


# ── Internal Helpers & Reactive Hooks ──────────────────────────────────────────

func _decorate_codex_entry(entry: Dictionary) -> Dictionary:
	var copy := entry.duplicate(true)
	var eid := str(copy.get("id", ""))
	var cat_id := str(copy.get("category", ""))
	var cat_def: Dictionary = _categories_by_id.get(cat_id, {})
	var unlock_meta: Dictionary = _unlocked_codex.get(eid, {})
	copy["category_name"] = str(cat_def.get("name", cat_id))
	copy["category_short"] = str(cat_def.get("short_name", cat_id))
	copy["accent_hex"] = str(cat_def.get("accent_hex", "#8c6548"))
	copy["unlocked"] = _unlocked_codex.has(eid)
	copy["unread"] = is_codex_unread(eid)
	copy["unlocked_source"] = str(unlock_meta.get("source", ""))
	copy["unlocked_date"] = str(unlock_meta.get("date", ""))
	return copy


func _unlock_codex_for_city(city_id: String, source_hint: String, mark_new_unread: bool) -> Array[String]:
	var unlocked_now: Array[String] = []
	for entry: Dictionary in _codex_entries:
		var eid := str(entry["id"])
		if _unlocked_codex.has(eid):
			continue
		var triggers: Variant = entry.get("unlock_triggers", {})
		if not triggers is Dictionary:
			continue
		var cities: Variant = (triggers as Dictionary).get("cities", [])
		if cities is Array and (cities as Array).has(city_id):
			if unlock_codex(eid, source_hint, mark_new_unread):
				unlocked_now.append(eid)
	return unlocked_now


func _unlock_codex_for_flag(flag_id: String, source_hint: String, mark_new_unread: bool) -> Array[String]:
	var unlocked_now: Array[String] = []
	for entry: Dictionary in _codex_entries:
		var eid := str(entry["id"])
		if _unlocked_codex.has(eid):
			continue
		var triggers: Variant = entry.get("unlock_triggers", {})
		if not triggers is Dictionary:
			continue
		var flags: Variant = (triggers as Dictionary).get("flags", [])
		if flags is Array and (flags as Array).has(flag_id):
			if unlock_codex(eid, source_hint, mark_new_unread):
				unlocked_now.append(eid)
	return unlocked_now


func _unlock_codex_for_currency(currency_id: String, source_hint: String, mark_new_unread: bool) -> Array[String]:
	var unlocked_now: Array[String] = []
	for entry: Dictionary in _codex_entries:
		var eid := str(entry["id"])
		if _unlocked_codex.has(eid):
			continue
		var triggers: Variant = entry.get("unlock_triggers", {})
		if not triggers is Dictionary:
			continue
		var currs: Variant = (triggers as Dictionary).get("currencies", [])
		if currs is Array and (currs as Array).has(currency_id):
			if unlock_codex(eid, source_hint, mark_new_unread):
				unlocked_now.append(eid)
	return unlocked_now


func _import_world_chronicle() -> void:
	for event: Dictionary in WorldBlackboard.get_chronicle():
		var title := str(event.get("title", "")).strip_edges()
		if title.is_empty():
			continue
		var text := str(event.get("text", "")).strip_edges()
		var date_str := str(event.get("date", _date_stamp())).replace("   ", " ")
		var cid := str(event.get("city_id", WorldBlackboard.current_city_id))
		var dkey := "chronicle:%s:%s" % [date_str, title]
		add_entry(
			"milestone",
			title,
			text,
			{"date_text": date_str, "city_id": cid, "location": _city_name(cid), "tone": "positive", "badge": "里程碑"},
			dkey
		)


func _on_world_location_changed(city_id: String) -> void:
	if not _initialized or SaveManager.is_restoring():
		return
	var resolved := _normalize_city_id(city_id)
	if resolved.is_empty() or resolved == _last_observed_city:
		return
	_last_observed_city = resolved
	_unlock_codex_for_city(resolved, "抵达" + _city_name(resolved), true)


func _on_world_flags_changed() -> void:
	if not _initialized or SaveManager.is_restoring():
		return
	var flags := WorldBlackboard.flag_facts()
	for flag_key: String in flags:
		if bool(flags[flag_key]):
			_unlock_codex_for_flag(flag_key, "旅途见闻", true)


func _on_world_chronicle_recorded(entry: Dictionary) -> void:
	if not _initialized or SaveManager.is_restoring():
		return
	var title := str(entry.get("title", "")).strip_edges()
	if title.is_empty():
		return
	var text := str(entry.get("text", "")).strip_edges()
	var date_str := str(entry.get("date", _date_stamp())).replace("   ", " ")
	var cid := str(entry.get("city_id", WorldBlackboard.current_city_id))
	var dkey := "chronicle:%s:%s" % [date_str, title]
	add_entry(
		"milestone",
		title,
		text,
		{"date_text": date_str, "city_id": cid, "location": _city_name(cid), "tone": "positive", "badge": "里程碑"},
		dkey
	)


func _on_economy_wallet_changed() -> void:
	if not _initialized or SaveManager.is_restoring() or not has_node("/root/EconomyManager"):
		return
	var eco: Node = get_node("/root/EconomyManager")
	var held_var: Variant = eco.call("get_held_currencies", false)
	if held_var is Array:
		for h: Variant in held_var:
			if h is Dictionary and int((h as Dictionary).get("min_units", 0)) > 0:
				_unlock_codex_for_currency(str((h as Dictionary).get("currency_id", "")), "持有通货", true)


func _on_rule_check_resolved(outcome: Dictionary, context: Dictionary) -> void:
	if not _initialized or SaveManager.is_restoring():
		return
	if str(outcome.get("mode", "natural")) != "natural":
		return
	var dc := int(outcome.get("dc", 0))
	if dc <= 0:
		return
	var is_nat20 := bool(outcome.get("is_nat20", false))
	var is_nat1 := bool(outcome.get("is_nat1", false))
	if not is_nat20 and not is_nat1:
		return
	var skill := str(outcome.get("skill_label", outcome.get("stat", "命运")))
	var ctx_note := str(outcome.get("context_note", context.get("context_note", "")))
	var roll_uid := str(outcome.get("roll_uid", ""))
	var dkey := ("dice_uid:" + roll_uid) if not roll_uid.is_empty() else ""
	record_dice_highlight(skill, int(outcome.get("raw_roll", 0)), dc, is_nat20, is_nat1, ctx_note, dkey)


func _on_economy_exchange_completed(result: Dictionary) -> void:
	if not _initialized or SaveManager.is_restoring():
		return
	var from_c := str(result.get("from_currency", ""))
	var to_c := str(result.get("to_currency", ""))
	var venue_type := str(result.get("venue_type", ""))
	var city_id := str(result.get("city_id", WorldBlackboard.current_city_id))
	var city_name := str(result.get("city_name", _city_name(city_id)))
	var is_guild := venue_type == "adventurer_guild"
	var gross_base := int(result.get("gross_base", 0))

	# Unlock cross-currency knowledge codex on first exchange + matching currency codex entries.
	unlock_codex("eco_six_currency_rates", "于%s办理跨币种换汇" % city_name, true)
	if not from_c.is_empty():
		_unlock_codex_for_currency(from_c, "跨币换汇", true)
	if not to_c.is_empty():
		_unlock_codex_for_currency(to_c, "跨币换汇", true)
	if is_guild:
		unlock_codex("lore_adventurer_guild", "于%s冒险者协会办理汇兑" % city_name, true)

	# Write concise milestone diary entry with dedupe_key to prevent spam.
	var dkey := "milestone_exchange:guild" if is_guild else "milestone_exchange:fee_venue"
	var already_logged_first := _dedupe_index.has(dkey)
	if already_logged_first and gross_base < 5000:
		return
	if already_logged_first:
		var wt := WorldBlackboard.get_world_time()
		dkey = "major_exchange:%d-%d-%d:%s->%s" % [int(wt["year"]), int(wt["month"]), int(wt["day"]), from_c, to_c]

	var fee_note := "官方免手续费（0%）" if is_guild else ("代兑手续费 %d 基准点（5%%）" % int(result.get("fee_base", 0)))
	var summary := "在%s以 %s 兑换 %s（%s），熟悉了跨洲货币牌价与结算规矩。" % [
		city_name,
		str(result.get("formatted_actual_from", "")),
		str(result.get("formatted_received", "")),
		fee_note
	]
	record_economy_event(
		"guild_exchange" if is_guild else "exchange",
		summary,
		{
			"title": "首次协会免税换汇" if (is_guild and not already_logged_first) else ("首次旅途代兑外币" if not already_logged_first else "大额跨洲换汇"),
			"city_id": city_id,
			"location": city_name,
			"currency_id": to_c,
			"tone": "positive" if is_guild else "neutral",
			"badge": "免税换汇" if is_guild else "商贸换汇",
			"dedupe_key": dkey
		}
	)


func _on_economy_purchase_completed(kind: String, result: Dictionary) -> void:
	if not _initialized or SaveManager.is_restoring():
		return
	var city_id := str(result.get("city_id", WorldBlackboard.current_city_id))
	var city_name := _city_name(city_id)
	var is_foreign := bool(result.get("is_foreign_payment", false))
	if is_foreign:
		unlock_codex("eco_six_currency_rates", "于%s使用外币折算直付" % city_name, true)
		var pay_c := str(result.get("pay_currency_id", ""))
		if not pay_c.is_empty():
			_unlock_codex_for_currency(pay_c, "外币结账", true)
		record_economy_event(
			"cross_currency",
			"在%s以异国通货（%s，含 5%% 折算费）直接完成结账，体会到跨大陆行旅备齐本地零钱的重要。" % [
				city_name, str(result.get("formatted_pay", ""))
			],
			{
				"title": "首次外币折算结账",
				"city_id": city_id,
				"location": city_name,
				"currency_id": pay_c,
				"tone": "neutral",
				"badge": "外币折算",
				"dedupe_key": "milestone_foreign_checkout"
			}
		)
	elif kind == "inn" and int(result.get("local_base_cost", 0)) >= 1500 and str(result.get("tier_id", "")) != "luxury_bath":
		var wt := WorldBlackboard.get_world_time()
		var day_key := "%d-%d-%d" % [int(wt["year"]), int(wt["month"]), int(wt["day"])]
		record_economy_event(
			"inn_rest",
			"入住%s的「%s」（实付 %s），安稳休整至次日清晨，体力与魔力尽数恢复。" % [
				city_name, str(result.get("tier_name", "旅馆")), str(result.get("formatted_pay", ""))
			],
			{
				"city_id": city_id,
				"location": city_name,
				"tone": "positive",
				"badge": "旅宿休整",
				"dedupe_key": "inn_rest:%s:%s" % [day_key, city_id]
			}
		)


func _on_economy_survival_changed() -> void:
	if not _initialized or SaveManager.is_restoring() or not has_node("/root/EconomyManager"):
		return
	var eco: Node = get_node("/root/EconomyManager")
	var cur_hunger := int(eco.get("hunger_days"))
	var wt := WorldBlackboard.get_world_time()
	var day_key := "%d-%d-%d" % [int(wt["year"]), int(wt["month"]), int(wt["day"])]
	if cur_hunger > _last_hunger_days and cur_hunger >= 1:
		var msg := (
			"行囊干粮告罄，饥肠辘辘之下全检定受到 -1 惩罚，需尽快觅食或寻村补给。"
			if cur_hunger == 1
			else "连续 %d 日未能进食干粮，周身乏力陷入「虚弱断粮（-2）」，必须立刻休整。" % cur_hunger
		)
		record_economy_event(
			"starvation",
			msg,
			{
				"title": "旅途断粮警讯（第 %d 日）" % cur_hunger,
				"tone": "negative",
				"badge": "断粮险情",
				"hunger_days": cur_hunger,
				"dedupe_key": "starvation:%s:%d" % [day_key, cur_hunger]
			}
		)
	_last_hunger_days = cur_hunger

	var mods: Variant = eco.get("active_modifiers")
	var has_rested := mods is Dictionary and (mods as Dictionary).has("well_rested")
	if has_rested and not _had_well_rested:
		record_economy_event(
			"luxury_rest",
			"在%s的舒适客房沐浴安眠，一扫连日风尘，次日启程获得「精力充沛 +1」。" % _city_name(WorldBlackboard.current_city_id),
			{
				"tone": "positive",
				"badge": "旅宿休整",
				"dedupe_key": "luxury_rest:%s:%s" % [day_key, WorldBlackboard.current_city_id]
			}
		)
	_had_well_rested = has_rested


func _normalize_city_id(city_id: String) -> String:
	var raw := city_id.strip_edges()
	if raw.is_empty():
		return WorldBlackboard.current_city_id
	if WorldBlackboard.catalog.city_names.has(raw):
		return raw
	if WorldBlackboard.catalog.city_names.has("city_" + raw):
		return "city_" + raw
	return raw


func _city_name(city_id: String) -> String:
	return str(WorldBlackboard.catalog.city_names.get(city_id, city_id))


func _date_stamp() -> String:
	return WorldBlackboard.date_text().replace("   ", " ")


static func _default_tone_for_category(category: String) -> String:
	if category == "milestone":
		return "positive"
	return "neutral"
