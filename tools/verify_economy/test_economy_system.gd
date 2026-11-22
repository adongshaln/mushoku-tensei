extends SceneTree

var _passed := 0
var _failed := 0


func _init() -> void:
	call_deferred("_run_all")


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("[FAIL] " + msg)
		print("[FAIL] " + msg)


func _run_all() -> void:
	var wb: Node = root.get_node("WorldBlackboard")
	var eco: Node = root.get_node("EconomyManager")
	var save_mgr: Node = root.get_node("SaveManager")
	var rules: Node = root.get_node("RuleEngine")

	print("=== Economy System Headless Verification (Godot 4.7.2) ===")

	# 1. Config integrity: 6 currencies & 19 cities & sea ferry fares
	var currencies: Array = eco.call("get_currency_order")
	_assert(currencies.size() == 6, "Expected 6 currencies, got %d" % currencies.size())
	var expected_units := {
		"demon_ore": 1,
		"minor_central": 2,
		"magic_nations": 4,
		"millis": 5,
		"king_dragon": 8,
		"asura": 10
	}
	for cid: String in expected_units:
		var u := int(eco.call("get_unit_base_value", cid))
		_assert(u == int(expected_units[cid]), "Currency %s unit_base_value expected %d got %d" % [cid, int(expected_units[cid]), u])
		var def: Dictionary = eco.call("get_currency_def", cid)
		var denoms: Array = def.get("denominations", [])
		_assert(denoms.size() == 6, "Currency %s should have 6 denominations, got %d" % [cid, denoms.size()])

	var all_cities: Array = eco.call("get_all_city_ids")
	_assert(all_cities.size() == 19, "Expected 19 cities in town_economy_catalog.json, got %d" % all_cities.size())
	var ferries: Array = eco.call("get_sea_ferry_fares")
	_assert(ferries.size() >= 2, "Expected >= 2 sea ferry reference fares")
	var wz_quote: Dictionary = eco.call("get_ferry_fare_quote", "city_wind_port", "city_zanto_port", "")
	_assert(bool(wz_quote.get("ok", false)) and int(wz_quote.get("local_base_cost", 0)) == 25000,
		"Wind<->Zanto ferry should be 25,000 base points")
	var we_quote: Dictionary = eco.call("get_ferry_fare_quote", "city_west_port", "city_east_port", "")
	_assert(bool(we_quote.get("ok", false)) and int(we_quote.get("local_base_cost", 0)) == 12000,
		"West<->East ferry should be 12,000 base points")

	# Formatting sanity checks
	_assert(str(eco.call("format_currency", "demon_ore", 450)) == "4 大绿 5 绿矿", "Format 450 demon_ore mismatch")
	_assert(str(eco.call("format_currency", "demon_ore", 1500)) == "1 银矿 5 大绿", "Format 1500 demon_ore mismatch")
	_assert(str(eco.call("format_currency", "millis", 230)) == "2 大铜 3 铜", "Format 230 millis mismatch")
	_assert(str(eco.call("format_currency", "asura", 100)) == "1 大铜", "Format 100 asura mismatch")

	# 2. All 6 currencies bidirectional exchange: Guild 0% lossless & 5% venues ceil fee
	for from_c: String in currencies:
		for to_c: String in currencies:
			if from_c == to_c:
				continue
			var u_from := int(eco.call("get_unit_base_value", from_c))
			var u_to := int(eco.call("get_unit_base_value", to_c))
			# 4000 base is evenly divisible by all 6 unit_base_values (lcm=40)
			@warning_ignore("integer_division")
			var start_units := 4000 / u_from
			eco.call("set_balance", from_c, start_units)
			eco.call("set_balance", to_c, 0)

			var res_fwd: Dictionary = eco.call("execute_exchange", from_c, to_c, start_units, "adventurer_guild", "city_rikarisu")
			_assert(bool(res_fwd.get("executed", false)), "Guild fwd %s->%s failed" % [from_c, to_c])
			_assert(int(res_fwd.get("fee_base", -1)) == 0, "Guild fee_base should be 0 for %s->%s" % [from_c, to_c])
			_assert(int(res_fwd.get("refund_from_units", -1)) == 0, "Guild exact multiple refund should be 0")
			_assert(int(res_fwd.get("remainder_base", -1)) == 0, "Guild exact multiple remainder should be 0")
			var got_units := int(res_fwd.get("received_units", 0))
			_assert(got_units * u_to == 4000, "Guild fwd base preservation failed %s->%s" % [from_c, to_c])

			var res_back: Dictionary = eco.call("execute_exchange", to_c, from_c, got_units, "adventurer_guild", "city_rikarisu")
			_assert(bool(res_back.get("executed", false)), "Guild back %s->%s failed" % [to_c, from_c])
			_assert(int(eco.call("get_balance", from_c)) == start_units, "Guild roundtrip %s<->%s not lossless" % [from_c, to_c])

			# Test 5% venues (merchant, inn, restaurant) with odd amounts to verify ceil fee + zero-swallow refund
			for venue: String in ["traveling_merchant", "inn", "restaurant"]:
				var test_units := start_units + 3
				eco.call("set_balance", from_c, test_units + 50)
				eco.call("set_balance", to_c, 0)
				var bal_before := int(eco.call("get_balance", from_c))
				var q5: Dictionary = eco.call("execute_exchange", from_c, to_c, test_units, venue, "city_rikarisu")
				_assert(bool(q5.get("executed", false)), "5%% exchange %s->%s at %s failed" % [from_c, to_c, venue])
				var req_gross := test_units * u_from
				@warning_ignore("integer_division")
				var expected_req_fee := (req_gross * 5 + 99) / 100
				_assert(int(q5.get("requested_fee_base", -1)) == expected_req_fee,
					"5%% requested_fee_base ceil mismatch for %s->%s (%d vs %d)" % [from_c, to_c, int(q5.get("requested_fee_base", -1)), expected_req_fee])
				var actual_from := int(q5.get("actual_from_units", 0))
				var refund_from := int(q5.get("refund_from_units", 0))
				var actual_gross := actual_from * u_from
				@warning_ignore("integer_division")
				var expected_act_fee := (actual_gross * 5 + 99) / 100
				_assert(actual_from + refund_from == test_units, "actual_from + refund_from != requested")
				_assert(int(q5.get("fee_base", -1)) == expected_act_fee, "actual fee_base ceil mismatch")
				var rec := int(q5.get("received_units", 0))
				var rem := int(q5.get("remainder_base", 0))
				_assert(actual_gross == expected_act_fee + rec * u_to + rem,
					"Conservation broken for %s->%s at %s" % [from_c, to_c, venue])
				_assert(int(eco.call("get_balance", from_c)) == bal_before - actual_from,
					"Refunded source units were not preserved in wallet")

	# Test explicit remainder refund transparency (105 demon_ore -> asura at 0% guild -> 10 asura, 5 demon_ore refunded!)
	eco.call("set_balance", "demon_ore", 105)
	eco.call("set_balance", "asura", 0)
	var odd_q: Dictionary = eco.call("execute_exchange", "demon_ore", "asura", 105, "adventurer_guild", "city_rikarisu")
	_assert(bool(odd_q.get("executed", false)), "105 demon_ore -> asura should execute")
	_assert(int(odd_q.get("actual_from_units", 0)) == 100, "Should only deduct 100 demon_ore")
	_assert(int(odd_q.get("refund_from_units", 0)) == 5, "Should refund 5 demon_ore")
	_assert(int(eco.call("get_balance", "demon_ore")) == 5, "Wallet must retain 5 refunded demon_ore")
	_assert(int(eco.call("get_balance", "asura")) == 10, "Wallet must receive 10 asura iron coins")

	# 3. Canon cross-continent rate test: 10 大绿矿钱 (1000 base) = 2 米里斯大铜钱 = 1 阿斯拉大铜钱
	eco.call("set_balance", "demon_ore", 1000)
	eco.call("set_balance", "millis", 0)
	eco.call("set_balance", "asura", 0)
	var d_to_m: Dictionary = eco.call("execute_exchange", "demon_ore", "millis", 1000, "adventurer_guild", "city_rikarisu")
	_assert(bool(d_to_m.get("executed", false)) and int(d_to_m.get("received_units", 0)) == 200,
		"10 大绿矿钱 must equal 200 米里斯铁钱 (2 米里斯大铜钱)")
	_assert(str(eco.call("format_currency", "millis", 200)) == "2 大铜", "200 millis units should format as 2 大铜")
	var m_to_a: Dictionary = eco.call("execute_exchange", "millis", "asura", 200, "adventurer_guild", "city_milishion")
	_assert(bool(m_to_a.get("executed", false)) and int(m_to_a.get("received_units", 0)) == 100,
		"2 米里斯大铜钱 must equal 100 阿斯拉铁钱 (1 阿斯拉大铜钱)")
	_assert(str(eco.call("format_currency", "asura", 100)) == "1 大铜", "100 asura units should format as 1 大铜")
	var a_to_d: Dictionary = eco.call("execute_exchange", "asura", "demon_ore", 100, "adventurer_guild", "city_arusu")
	_assert(bool(a_to_d.get("executed", false)) and int(a_to_d.get("received_units", 0)) == 1000,
		"1 阿斯拉大铜钱 must convert back to 10 大绿矿钱 (1000 demon_ore)")

	# 4. City service venue enforcement: Migurd blocks guild 0% & allows inn/merchant 5%; Rikarisu allows guild 0%
	eco.call("set_balance", "demon_ore", 2000)
	eco.call("set_balance", "millis", 0)
	var mig_guild: Dictionary = eco.call("execute_exchange", "demon_ore", "millis", 1000, "adventurer_guild", "city_migurd")
	_assert(not bool(mig_guild.get("executed", true)) and str(mig_guild.get("reason", "")) == "venue_unavailable",
		"city_migurd MUST block adventurer_guild 0%% exchange")
	_assert(int(eco.call("get_balance", "demon_ore")) == 2000, "Blocked exchange must not touch wallet")
	var mig_inn: Dictionary = eco.call("execute_exchange", "demon_ore", "millis", 1000, "inn", "city_migurd")
	_assert(bool(mig_inn.get("executed", false)) and int(mig_inn.get("fee_base", 0)) == 50 and int(mig_inn.get("received_units", 0)) == 190,
		"city_migurd inn 5%% exchange failed (expected fee 50, received 190 millis)")
	var mig_merch: Dictionary = eco.call("execute_exchange", "demon_ore", "millis", 1000, "traveling_merchant", "city_migurd")
	_assert(bool(mig_merch.get("executed", false)) and int(mig_merch.get("fee_base", 0)) == 50,
		"city_migurd merchant 5%% exchange failed")

	# Also verify Migurd blocks luxury_bath inn tier while Rikarisu allows it
	eco.call("set_balance", "demon_ore", 20000)
	var mig_lux: Dictionary = eco.call("rest_at_inn", "city_migurd", "luxury_bath", "")
	_assert(not bool(mig_lux.get("executed", true)) and str(mig_lux.get("reason", "")) == "tier_unavailable",
		"city_migurd (village) must reject luxury_bath tier")

	# Test foreign-currency direct checkout in Migurd (pay in asura when demon_ore = 0)
	eco.call("set_balance", "demon_ore", 0)
	eco.call("set_balance", "asura", 100)
	var fbuy: Dictionary = eco.call("buy_supply", "city_migurd", "ration_normal", 1, "asura")
	_assert(bool(fbuy.get("executed", false)) and bool(fbuy.get("is_foreign_payment", false)),
		"Foreign currency direct purchase in city_migurd failed")
	_assert(int(fbuy.get("fee_base", 0)) > 0, "Foreign currency direct purchase should charge 5%% fee")

	# 5. Ration buying, daily consumption, starvation -1 / -2, inn rest & Dragon Calendar advance, restaurant +1
	wb.call("reset_new_game")
	eco.call("reset_from_blackboard")
	wb.current_city_id = "city_rikarisu"
	# Clear any existing rations cleanly
	var existing_r := int(eco.call("get_total_rations"))
	if existing_r > 0:
		wb.call("consume_rations", existing_r)
	eco.call("set_balance", "demon_ore", 10000)

	var buy_norm: Dictionary = eco.call("buy_supply", "city_rikarisu", "ration_normal", 2, "")
	var buy_fine: Dictionary = eco.call("buy_supply", "city_rikarisu", "ration_fine", 1, "")
	_assert(bool(buy_norm.get("executed", false)) and bool(buy_fine.get("executed", false)), "Buying rations in Rikarisu failed")
	_assert(int(eco.call("get_total_rations")) == 3 and int(wb.call("get_total_rations")) == 3, "Ration sync to WorldBlackboard failed")

	var day1: Dictionary = eco.call("consume_daily_rations", 1, 1, "normal_first")
	_assert(int(day1.get("consumed_normal", 0)) == 1 and int(day1.get("hunger_days", -1)) == 0, "Day 1 normal ration consume failed")
	var day23: Dictionary = eco.call("consume_daily_rations", 2, 1, "normal_first")
	_assert(int(day23.get("consumed_normal", 0)) == 1 and int(day23.get("consumed_fine", 0)) == 1 and int(eco.call("get_total_rations")) == 0,
		"Days 2-3 ration drain failed")

	# Starvation day 1 -> hungry (-1)
	var starve1: Dictionary = eco.call("consume_daily_rations", 1, 1)
	_assert(int(starve1.get("hunger_days", 0)) == 1 and int(eco.call("get_travel_check_modifier")) == -1,
		"1 day without rations must trigger hungry (-1)")
	var check1: Dictionary = rules.call("collect_check", "CON", {})
	var found_hungry := false
	for b: Dictionary in check1.get("bonus_list", []):
		if str(b.get("id", "")) == "economy:hungry" and int(b.get("value", 0)) == -1:
			found_hungry = true
	_assert(found_hungry, "RuleEngine did not receive economy:hungry (-1) modifier")

	# Starvation day 2 -> starving (-2)
	var starve2: Dictionary = eco.call("consume_daily_rations", 1, 1)
	_assert(int(starve2.get("hunger_days", 0)) == 2 and int(eco.call("get_travel_check_modifier")) == -2,
		"2 consecutive days without rations must trigger starving (-2)")
	var check2: Dictionary = rules.call("collect_check", "CON", {})
	var found_starving := false
	for b: Dictionary in check2.get("bonus_list", []):
		if str(b.get("id", "")) == "economy:starving" and int(b.get("value", 0)) == -2:
			found_starving = true
	_assert(found_starving, "RuleEngine did not receive economy:starving (-2) modifier")

	# Advance time to afternoon (slot=1) then stay at Rikarisu luxury bath inn -> next morning (day+1, slot=0), clears starving, grants well_rested (+1)
	wb.call("advance_time", 1)
	var time_before: Dictionary = wb.call("get_world_time")
	_assert(int(time_before["slot"]) == 1, "Expected afternoon slot 1 before inn rest")
	var inn_res: Dictionary = eco.call("rest_at_inn", "city_rikarisu", "luxury_bath", "")
	_assert(bool(inn_res.get("executed", false)), "Rikarisu luxury_bath inn rest failed")
	var time_after: Dictionary = wb.call("get_world_time")
	_assert(int(time_after["day"]) == int(time_before["day"]) + 1 and int(time_after["slot"]) == 0,
		"Inn rest must advance Dragon Calendar to next day morning (slot 0)")
	_assert(int(eco.hunger_days) == 0 and int(eco.stamina) == 100, "Inn rest must clear hunger and restore stamina to 100")
	_assert(int(eco.call("get_travel_check_modifier")) == 1, "Luxury bath must grant well_rested (+1)")

	# Order Milis regional dish in city_milishion -> well_fed (+1), total modifier +2
	eco.call("set_balance", "millis", 1000)
	var meal_res: Dictionary = eco.call("order_meal", "city_milishion", "milis_holy_beef_stew", "")
	_assert(bool(meal_res.get("executed", false)), "Milis restaurant meal failed")
	_assert(int(eco.call("get_travel_check_modifier")) == 2, "well_rested (+1) + well_fed (+1) must total +2")

	# 6. SaveManager full disk roundtrip + Legacy save migration (zero crashes!)
	var orig_dir: String = save_mgr.directory
	save_mgr.directory = "user://saves_verify_economy_tmp"
	eco.call("set_balance", "demon_ore", 3210)
	eco.call("set_balance", "minor_central", 450)
	eco.call("set_balance", "magic_nations", 125)
	eco.call("set_balance", "millis", 777)
	eco.call("set_balance", "king_dragon", 88)
	eco.call("set_balance", "asura", 42)
	eco.call("buy_supply", "city_rikarisu", "ration_normal", 4, "")
	var snap_wallet: Dictionary = eco.wallet.duplicate(true)
	var snap_stamina: int = eco.stamina
	var snap_mod: int = int(eco.call("get_travel_check_modifier"))
	var snap_rations: int = int(eco.call("get_total_rations"))
	var snap_time: Dictionary = wb.call("get_world_time")

	var saved_ok := bool(save_mgr.call("save_slot", "slot_1", save_mgr.ATLAS))
	_assert(saved_ok, "SaveManager.save_slot failed")
	var slot_meta: Dictionary = save_mgr.call("slot_info", "slot_1")
	_assert(str(slot_meta.get("currency_text", "")).contains("银矿") or str(slot_meta.get("currency_text", "")).contains("大绿"),
		"Save slot meta currency_text should display formatted local currency, got: %s" % str(slot_meta.get("currency_text", "")))

	# Clobber runtime state completely, then restore
	for cid: String in currencies:
		eco.call("set_balance", cid, 0)
	eco.stamina = 11
	eco.hunger_days = 5
	eco.active_modifiers.clear()
	var loaded_ok := bool(save_mgr.call("restore_slot_state", "slot_1"))
	_assert(loaded_ok, "SaveManager.restore_slot_state failed")
	for cid: String in currencies:
		_assert(int(eco.call("get_balance", cid)) == int(snap_wallet[cid]),
			"Restored balance mismatch for %s (%d vs %d)" % [cid, int(eco.call("get_balance", cid)), int(snap_wallet[cid])])
	_assert(int(eco.stamina) == snap_stamina, "Restored stamina mismatch")
	_assert(int(eco.call("get_travel_check_modifier")) == snap_mod, "Restored modifier mismatch")
	_assert(int(eco.call("get_total_rations")) == snap_rations, "Restored rations mismatch")
	var restored_time: Dictionary = wb.call("get_world_time")
	_assert(int(restored_time["day"]) == int(snap_time["day"]) and int(restored_time["slot"]) == int(snap_time["slot"]),
		"Restored Dragon Calendar mismatch")

	# Legacy save migration test (save file with ONLY modules.world and NO modules.economy)
	var legacy_save := {
		"schema_version": 1,
		"saved_at": "2026-01-01 12:00:00",
		"saved_at_unix": 1767268800,
		"scene_path": save_mgr.CABIN,
		"meta": {"character_name": "诺缇雅", "location_name": "米格路德村"},
		"modules": {
			"world": {
				"character": {"profile": {"character_id": "notia"}},
				"current_city_id": "city_migurd",
				"current_location_id": "migurd_village",
				"currency_copper": 45,
				"world_time": {"year": 418, "month": 1, "day": 3, "slot": 2}
			}
		}
	}
	var legacy_path: String = str(save_mgr.directory).path_join("slot_2.json")
	var lf := FileAccess.open(legacy_path, FileAccess.WRITE)
	_assert(lf != null, "Could not write legacy test save file")
	if lf != null:
		lf.store_string(JSON.stringify(legacy_save, "\t"))
		lf.close()
	var legacy_ok := bool(save_mgr.call("restore_slot_state", "slot_2"))
	_assert(legacy_ok, "Loading legacy save without economy module failed")
	_assert(int(eco.call("get_balance", "demon_ore")) == 4500,
		"Legacy 45 copper at city_migurd should migrate to 4500 demon_ore, got %d" % int(eco.call("get_balance", "demon_ore")))
	_assert(str(wb.call("get_currency_display_text")) == "4 银矿 5 大绿",
		"WorldBlackboard display text should sync to '4 银矿 5 大绿', got '%s'" % str(wb.call("get_currency_display_text")))

	# Cleanup temporary save directory
	for fn: String in ["slot_1.json", "slot_2.json"]:
		var p: String = ProjectSettings.globalize_path(str(save_mgr.directory).path_join(fn))
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(str(save_mgr.directory)))
	save_mgr.directory = orig_dir

	# 7. UI Preview Scene instantiation & tab cycling smoke test
	var preview_res := load("res://scenes/ui/town_services/town_services_preview.tscn") as PackedScene
	_assert(preview_res != null, "Failed to load town_services_preview.tscn")
	if preview_res != null:
		var preview: Node = preview_res.instantiate()
		root.add_child(preview)
		await process_frame
		var overlay: Node = preview.call("get_overlay")
		_assert(overlay != null, "Preview overlay node missing")
		for test_city: String in ["city_migurd", "city_rikarisu", "city_milishion"]:
			preview.call("switch_preview_city", test_city, "guild")
			await process_frame
			for tab_id: String in ["guild", "inn", "restaurant", "merchant"]:
				overlay.call("select_tab", tab_id, false)
				if tab_id != "guild":
					overlay.call("set_inline_exchange_open", true)
					await process_frame
					overlay.call("set_inline_exchange_open", false)
				await process_frame
		preview.queue_free()
		await process_frame

	print("=== Verification Complete: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
