# Track 2 总控交接报告：第一卷魔大陆东北角（米格路德 ↔ 利卡里斯）奇遇事件包

- **项目**：《无职转生～属于你自己的人生～》（Godot 4.7.2 / 纯 GDScript）
- **并行轨道**：Track 2（纯数据与校验扩展 · 零冲突独立包）
- **交付日期**：2026-11-21
- **验证环境**：`Godot Engine v4.7.2.stable.official.ed1daf0bf`（无头推演全量通过，0 Error / 0 Warning / 0 Leak）

---

## 1. 任务状态与三线零冲突证明

### 1.1 任务完成状态
- **多分支 D20 奇遇主扩展包**：已完成 `data/events/pack_vol1_demon_northeast.json`（4 大主题遭遇池、**14 个**地道轻小说风魔大陆东北角事件、**42 个**差异化选项、**27 个** D20 技能检定、**15 处**自然 20/自然 1 彩蛋文案与奖励分支）。
- **手账故事片段伴生包**：已完成 `data/storylets/pack_vol1_demon_northeast.json`（6 条 100% 原生兼容 `StoryletScheduler` 自动扫描机制的据点/途中故事片段，完整保留并零篡改既有 `rikarisu_gate_entry` 钩子）。
- **无头 Schema 与实机推演校验器**：已完成 `tools/verify_narrative/test_vol1_demon_pack.gd`，在内存中向真实 `EncounterEngine`、`RuleEngine`、`StoryletScheduler`、`EconomyManager` 与 `JournalManager` 喂入扩展包，完成全量 Schema 校验与 **100 条分支干跑推演**（`13/13 PASS`）。

### 1.2 三线零冲突证明
- **修改既有项目文件数**：**`0`**（未修改 `project.godot`、`core/`、`data/maps/`、`data/storylets/` 既有文件、`data/economy/`、`data/codex/`、`scenes/`、`ui/` 及冻结战斗目录）。
- 说明：下方 `git status --short` 中的 `M` 文件及 `core/economy_manager.gd`、`core/journal_manager.gd`、`scenes/world_map/chunks/`、`tools/verify_integration/` 等条目均来自前序里程碑与并行轨道；本轨道全部产物严格位于白名单新建路径内。

#### `git status --short` 完整输出
```text
 M AGENTS.md
 M core/audio_manager.gd
 M core/character_catalog.gd
 M core/rule_engine.gd
 M core/save_manager.gd
 M core/storylet_scheduler.gd
 M core/travel_planner.gd
 M core/world_blackboard.gd
 M data/dialogues/418_village_gate.json
 M data/maps/world_map_data.json
 M data/maps/world_routes.json
 M data/rules/character_presets.json
 M data/rules/equipment_items.json
 M data/rules/equipment_slots.json
 M data/rules/rank_definitions.json
 M project.godot
 M scenes/dialogue/dialogue_view.gd
 M scenes/dialogue/portrait_slot.gd
 M scenes/room/room_explorer.gd
 M scenes/shared/scene_transition.gd
 M scenes/title/title_screen.gd
 M scenes/world_map/atlas_travel_journal.gd
 M scenes/world_map/atlas_travel_stage.gd
 M scenes/world_map/world_atlas_view.gd
 M shaders/title_ambience.gdshader
 M ui/character_journal_overlay.gd
 M ui/d20_3d_stage.gd
 M ui/dice_roll_overlay.gd
 M ui/folio_overlay.gd
 M ui/journal_ui.gd
 M ui/save_load_overlay.gd
 M ui/ui_theme_kit.gd
?? assets/3d/dice/
?? assets/3d/pawns/
?? assets/3d/props/
?? assets/3d/world_v2/
?? assets/portraits/eris.png
?? assets/portraits/eris.png.import
?? assets/portraits/notia.png
?? assets/portraits/notia.png.import
?? assets/portraits/roin.png
?? assets/portraits/roin.png.import
?? assets/portraits/rudeus.png
?? assets/portraits/rudeus.png.import
?? assets/portraits/ruijerd.png
?? assets/portraits/ruijerd.png.import
?? assets/textures/
?? core/economy_manager.gd
?? core/encounter_engine.gd
?? core/encounter_engine.gd.uid
?? core/journal_manager.gd
?? core/settings_manager.gd
?? data/codex/
?? data/economy/
?? data/events/
?? data/maps/region_encounters.json
?? data/maps/world_relief_meta.json
?? data/storylets/pack_vol1_demon_northeast.json
?? docs/
?? resources/
?? scenes/dialogue/dialogue_widgets.gd
?? scenes/dialogue/dialogue_widgets.gd.uid
?? scenes/ui/
?? scenes/world_map/atlas_encounter_overlay.gd
?? scenes/world_map/atlas_encounter_overlay.gd.uid
?? scenes/world_map/chunks/
?? scenes/world_map/world_biome_scatter.gd
?? scenes/world_map/world_biome_scatter.gd.uid
?? scenes/world_map/world_hero_assets.gd
?? scenes/world_map/world_terrain_sampler.gd
?? scenes/world_map/world_terrain_sampler.gd.uid
?? scenes/world_map/world_weather_stage.gd
?? shaders/area_arrival_banner.gdshader
?? shaders/area_arrival_banner.gdshader.uid
?? shaders/basin_mist.gdshader
?? shaders/basin_mist.gdshader.uid
?? shaders/bust_feather.gdshader
?? shaders/bust_feather.gdshader.uid
?? shaders/cabin_ambience.gdshader
?? shaders/cabin_ambience.gdshader.uid
?? shaders/circle_mask.gdshader
?? shaders/circle_mask.gdshader.uid
?? shaders/dialogue_choice_ribbon.gdshader
?? shaders/dialogue_choice_ribbon.gdshader.uid
?? shaders/dialogue_curtain.gdshader
?? shaders/dialogue_curtain.gdshader.uid
?? shaders/game_button_sheen.gdshader
?? shaders/game_button_sheen.gdshader.uid
?? shaders/grimoire_book_spread.gdshader
?? shaders/grimoire_book_spread.gdshader.uid
?? shaders/ink_transition.gdshader
?? shaders/ink_transition.gdshader.uid
?? shaders/lighthouse_beam.gdshader
?? shaders/lighthouse_beam.gdshader.uid
?? shaders/map_route_line.gdshader
?? shaders/map_route_line.gdshader.uid
?? shaders/pawn_contact_shadow.gdshader
?? shaders/pawn_contact_shadow.gdshader.uid
?? shaders/smoked_hud_glass.gdshader
?? shaders/smoked_hud_glass.gdshader.uid
?? shaders/world_biome_prop.gdshader
?? shaders/world_biome_prop.gdshader.uid
?? shaders/world_cloud_wisp.gdshader
?? shaders/world_cloud_wisp.gdshader.uid
?? shaders/world_ocean_m1.gdshader
?? shaders/world_ocean_m1.gdshader.uid
?? shaders/world_relief_m1_preview.gdshader
?? shaders/world_relief_m1_preview.gdshader.uid
?? shaders/world_relief_ocean_v2.gdshader
?? shaders/world_relief_ocean_v2.gdshader.uid
?? shaders/world_relief_terrain_v2.gdshader
?? shaders/world_relief_terrain_v2.gdshader.uid
?? tools/atlas_25d/
?? tools/blender_props/
?? tools/blender_world_v2/
?? tools/verify_economy/
?? tools/verify_integration/
?? tools/verify_journal/
?? tools/verify_narrative/
?? tools/verify_settings_audio/
?? ui/area_arrival_banner.gd
?? ui/area_arrival_banner.gd.uid
?? ui/journal_codex_view.gd
?? ui/journal_diary_view.gd
?? ui/prop_3d_viewer.gd
?? ui/prop_3d_viewer.gd.uid
```

#### Track 2 专属新增文件核验
```text
?? data/events/pack_vol1_demon_northeast.json
?? data/storylets/pack_vol1_demon_northeast.json
?? docs/handoff/report_track2_demon_opening.md
?? tools/verify_narrative/test_vol1_demon_pack.gd
```

---

## 2. 新增文件清单与事件总览表

### 2.1 新增文件清单
| 文件路径 | 核心职责 | 行数 |
| :--- | :--- | ---: |
| `data/events/pack_vol1_demon_northeast.json` | 第一卷魔大陆东北角（米格路德盆地 ↔ 利卡里斯镇）14 事件 4 池完整多选项 D20 扩展包，100% 兼容 `EncounterEngine` / `AtlasEncounterOverlay` | 1546 |
| `data/storylets/pack_vol1_demon_northeast.json` | 6 条原生伴生 Storylet，由 `StoryletScheduler` 启动自动扫描加载，关联主事件包 ID | 252 |
| `tools/verify_narrative/test_vol1_demon_pack.gd` | Godot 4.7.2 无头 Schema 合法性、全局 ID 唯一性、跨轨经济/图鉴联动与 100 分支引擎干跑校验器 | 682 |
| `docs/handoff/report_track2_demon_opening.md` | 本总控交接报告 | — |

### 2.2 全部 14 个核心事件总览表（`data/events/pack_vol1_demon_northeast.json`）

| # | 事件 ID | 事件标题 | 分类池 | 触发地域 / 路线 | D20 检定（属性 · DC · 标签） | 冷却 / 频控 | 经济（`demon_ore`）与核心联动 |
| :-: | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | `vol1_dn_01_basin_mist_tracks` | 晨雾尽头的红岩爪印 | 米格路德盆地与种族风土 | `demon_biegoya` · `city_migurd` / `misty_forest_path` · 上/下午 | `INT` DC 11（感知与自然追踪，含 Nat20/Nat1）；`DEX` DC 10（隐匿步法） | 冷却 4 天 | 获 `emergency_herbs`（基准价 600）/ 熏肉；`geo_migurd_basin` |
| 2 | `vol1_dn_02_emerald_hair_telepathy` | 翡翠发色与无声回响 | 米格路德盆地与种族风土 | `demon_biegoya` · `city_migurd` / `migurd_village` · 白天/傍晚 | `WIL` DC 11（洞察神色，含 Nat20）；`CHA` DC 10（从容礼节） | `once_only` | 获 2 熏肉 / 1 精良口粮（500）与 `WIL +1` 增益；`lore_migurd_tribe` |
| 3 | `vol1_dn_03_broken_signpost_cache` | 断折路标下的旧干粮盒 | 米格路德盆地与种族风土 | `demon_biegoya` · `misty_forest_path` / `dryrock_spring` | `INT` DC 11（仔细调查，含 Nat20）；`WIL` DC 10（修整路标） | 冷却 6 天 | `+180` / `+120 demon_ore`（1.2~1.8 大绿矿钱）+ 1 干粮；`eco_demon_ore_currency` |
| 4 | `vol1_dn_04_redrock_sandstorm` | 赤岩裂谷的赭色砂幕 | 赤岩荒原行路与魔物险情 | `demon_biegoya` · `city_migurd<->city_rikarisu` | `CON` DC 12（体质抗沙，含 Nat20/Nat1）；`WIL` DC 13（顶风强闯，兜帽 +2） | 冷却 5 天 | 失败扣干粮 + 体力 `-14/-18` + `travel_fatigue`；`geo_demon_continent` |
| 5 | `vol1_dn_05_stone_lizard_ambush` | 赭岩脊上的红蜥蜴群 | 赤岩荒原行路与魔物险情 | `demon_biegoya` · `city_migurd<->city_rikarisu` | `DEX` DC 12（隐匿绕行，含 Nat20）；`INT` DC 12（水魔术威慑，含 Nat20） | 冷却 4 天 | 预留 `combat_hook`（零耦合）；Nat20 鳞片可换 `+150 demon_ore` |
| 6 | `vol1_dn_06_glinting_mana_vein` | 半埋赤岩的微光魔石脉 | 赤岩荒原行路与魔物险情 | `demon_biegoya` · `dryrock_spring` / 商道 | `INT` DC 13（奥术辨矿，含 Nat20/Nat1）；`DEX` DC 10（巧手轻采） | 冷却 7 天 | `+120` / `+350` / `+600 demon_ore`（1.2~6 大绿矿钱）；失败体力 `-15` |
| 7 | `vol1_dn_07_dry_well_turbid_water` | 枯井石槽与微浊泉水 | 赤岩荒原行路与魔物险情 | `demon_biegoya` · `dryrock_spring` | `INT` DC 11（水魔术净水，含 Nat20）；`CON` DC 11（体质试饮） | 冷却 5 天 | 成功体力 `+18/+26` 清疲惫；失败体力 `-12` + `upset_stomach` 减益 |
| 8 | `vol1_dn_08_demon_peddler_wagon` | 摇铃而来的魔族游商马车 | 魔大陆行商与原作经济联动 | `demon_biegoya` · `city_migurd<->city_rikarisu` | `CHA` DC 12（游说讲价与询汇，含 Nat20）；+ 2 项直接经济选项 | 冷却 4 天 | **2 干粮 400（讲价 300）** + **旅商 5% 手续费现场换汇**；`eco_six_currency_rates` |
| 9 | `vol1_dn_09_broken_caravan_axle` | 赤岩弯道上的断轴商车 | 魔大陆行商与原作经济联动 | `demon_biegoya` · `city_migurd<->city_rikarisu` | `INT` DC 12（水魔术辅修，含 Nat20/Nat1 趣闻）；`STR` DC 13（力量扛辕） | 冷却 7 天 | 成功赠 **1 银矿钱（`1,000 demon_ore`）+ 利卡里斯引荐条**；失败/大失败仍获 `200` + 干粮谢礼 |
| 10 | `vol1_dn_10_blackmarket_foreign_coin` | 黑市摊上的“古怪外陆硬币” | 魔大陆行商与原作经济联动 | `demon_biegoya` · `city_migurd<->city_rikarisu` | `INT` DC 13（奥术鉴定，含 Nat20）；`CHA` DC 12（拆穿周旋） | 冷却 8 天 | **付 300（Nat20 付 200）→ 淘得 1 枚真米里斯大铜钱（100 `millis` = 500 基准点）** |
| 11 | `vol1_dn_11_campfire_adventurer_tales` | 赤岩篝火旁的冒险者夜话 | 魔大陆行商与原作经济联动 | `demon_biegoya` · `dryrock_spring` / 商道 · 傍晚/深夜 | `CHA` DC 11（篝火攀谈，含 Nat20）；`INT` DC 10（记取常识） | `once_only` | 体力 `+20/+25`；解锁**赤龙山脉 / 冒险者协会 / 0% 换汇常识 / 六面世界**图鉴钩子 |
| 12 | `vol1_dn_12_rikarisu_outer_outpost` | 赤岩外哨与魔族卫兵盘查 | 利卡里斯镇近郊与城门前奏 | `demon_biegoya` · `city_rikarisu` / `rikarisu_gate` | `CHA` DC 11（礼仪游说，兜帽 +2，含 Nat20）；`WIL` DC 12（沉着威慑） | 冷却 5 天 | 登记费 `100 demon_ore`（1 大绿）；呼应但不篡改 `rikarisu_gate_entry` |
| 13 | `vol1_dn_13_gate_bounty_flyers` | 城门石柱上的新手悬赏传单 | 利卡里斯镇近郊与城门前奏 | `demon_biegoya` · `city_rikarisu` / `rikarisu_gate` | `INT` DC 11（甄别悬赏，含 Nat20）；`CHA` DC 11（同行打听） | `once_only` | 预告 F 级报酬（300 / 800 / 1,000 `demon_ore`）与新人免工本费线索；`lore_adventurer_guild` |
| 14 | `vol1_dn_14_dusk_rikarisu_spires` | 黄昏远眺：岩坑里的琥珀石城 | 利卡里斯镇近郊与城门前奏 | `demon_biegoya` · `city_rikarisu` / `rikarisu_gate` · 下午/傍晚/深夜 | `WIL` DC 10（沉淀心志，含 Nat20）；`INT` DC 11（俯瞰城郭） | `once_only` | 纯氛围轻小说里程碑；`first_city_resolve`（`WIL +1, CHA +1`）；`geo_rikarisu` |

### 2.3 伴生 Storylet 映射表（`data/storylets/pack_vol1_demon_northeast.json`）
| Storylet ID | 触发方式与地点 | 关联主事件 ID |
| :--- | :--- | :--- |
| `vol1_st_basin_mist_scout` | `manual` · `city_migurd` / `migurd_village` / `misty_forest_path`（上午/下午） | `vol1_dn_01_basin_mist_tracks` |
| `vol1_st_migurd_telepathy_echo` | `manual` · `city_migurd` / `migurd_village`（`once_only`） | `vol1_dn_02_emerald_hair_telepathy` |
| `vol1_st_redrock_vein_prospect` | `en_route`（`min_km: 40`）· `city_rikarisu` / `city_migurd` | `vol1_dn_06_glinting_mana_vein` |
| `vol1_st_campfire_adventurer_chat` | `manual` · `dryrock_spring` / `city_rikarisu`（傍晚/深夜，`once_only`） | `vol1_dn_11_campfire_adventurer_tales` |
| `vol1_st_rikarisu_bounty_board` | `manual` · `city_rikarisu` / `rikarisu_gate`（`once_only`） | `vol1_dn_13_gate_bounty_flyers` |
| `vol1_st_dusk_rikarisu_vista` | `manual` · `city_rikarisu` / `rikarisu_gate`（下午/傍晚/深夜，`once_only`） | `vol1_dn_14_dusk_rikarisu_spires` |

---

## 3. Schema 兼容说明与引擎接入契约

### 3.1 既有引擎扫描机制核查
1. **`core/storylet_scheduler.gd`（已自动扫描 ✅）**：
   - 第 5 行与第 40–50 行自动遍历 `res://data/storylets/*.json` 并合并至 `_pool`。
   - `data/storylets/pack_vol1_demon_northeast.json` **现已开箱即用**，无需修改 `storylet_scheduler.gd`（已在 `V12` 验证自动载入且不影响既有 `gate_entry_hook` / `atlas_rikarisu_gate`）。
2. **`core/encounter_engine.gd`（总装时仅需加 8 行目录扫描 🔧）**：
   - 当前第 3 行仅硬编码读取单一文件 `ENCOUNTER_PATH := "res://data/maps/region_encounters.json"`。
   - **重要数值发现**：`data/maps/world_routes.json` 第 3 行中 `city_migurd -> city_rikarisu` 距离为 **`60 km`**，而旧 `region_encounters.json` 的 `pool_demon_wilds` 设置为 `min_km: 120` 导致第一卷开篇路段此前完全无法掷出路遇。本扩展包 4 个遭遇池均精确校准为 `min_km: 30~40`，接入后即可在 60 km 开篇荒原商道丝滑触发。

### 3.2 合拢阶段推荐接入片段（精确到行）

#### (A) 在 `core/encounter_engine.gd`（第 3 行与第 15–22 行 `reload()`）挂载 `data/events/` 扩展包目录
```gdscript
const EVENT_PACK_DIR := "res://data/events/"

func reload() -> void:
	_config = WorldBlackboard.read_config(ENCOUNTER_PATH)
	_pools.clear()
	_append_pools_from(_config)
	for file: String in DirAccess.get_files_at(EVENT_PACK_DIR):
		if file.ends_with(".json"):
			_append_pools_from(WorldBlackboard.read_config(EVENT_PACK_DIR + file))
	var mults: Variant = _config.get("posture_multipliers", {})
	_posture_mult = mults if mults is Dictionary else {}
```

#### (B) 在 `core/encounter_engine.gd`（第 110–113 行 `apply_check_outcome`）可选升级 Nat 20 / Nat 1 彩蛋与扩展钩子
当前 `RuleEngine.roll_check()` 已返回 `is_nat20` / `is_nat1`，合拢时可将 `apply_check_outcome(option, passed, is_nat20 := false, is_nat1 := false)` 扩展为：
```gdscript
if passed and is_nat20 and option.has("crit_success_text"):
	apply_effects(option.get("crit_success_effects", option.get("success_effects", [])))
	return str(option["crit_success_text"])
if not passed and is_nat1 and option.has("crit_fail_text"):
	apply_effects(option.get("crit_fail_effects", option.get("fail_effects", [])))
	return str(option["crit_fail_text"])
```
并可顺带读取事件顶层 `trigger.cooldown_days` / `trigger.once_only` / `trigger.allowed_slots` 与 `pool.match_routes` / `match_cities` 做防刷过滤。

### 3.3 严格遵循的合法字段与 Opcode 契约
- **六维属性 ID**（源自 `data/rules/rank_definitions.json`）：仅使用 `STR`、`DEX`、`CON`、`INT`、`WIL`、`CHA`；具体技能语义置于 `check.label` 与 `check.context.tags` / `skill_id`。
- **效果 Opcode**（源自 `core/encounter_engine.gd:136-167`）：仅使用 `spend_copper`、`consume_rations`、`add_item`、`restore_mp`、`advance_time`、`set_flag`、`add_buff`、`remove_buff`；伴生 Storylet 仅使用 `core/storylet_scheduler.gd:349-362` 支持的 `set_flag`、`add_item`、`add_buff`、`remove_buff`、`advance_time`。
- **货币换算锚点**（源自 `data/economy/currencies.json`）：`1 legacy copper = 100 base = 1 大绿矿钱（100 demon_ore）`，因此 `spend_copper: 4` 与 `demon_ore: 400` 严格等价。

---

## 4. 与轨道 1（经济）& 轨道 3（手账图鉴）的联动清单

### 4.1 轨道 1 `EconomyManager`（`core/economy_manager.gd`）挂接清单
扩展包每个涉及多币种或体力的选项均已声明标准 `economy_hooks[]` 数组，合拢时在事件结算回调中统一分派即可：

| 事件 ID | 触发分支 | `economy_hooks` 声明动作 | 对应 `EconomyManager` 调用建议 |
| :--- | :--- | :--- | :--- |
| `vol1_dn_03_broken_signpost_cache` | 调查成功 / 扶正成功 | `add_currency(demon_ore, +180 / +120)` | `EconomyManager.add_currency("demon_ore", units)` |
| `vol1_dn_04_redrock_sandstorm` | 抗沙失败 / 强闯失败 | `adjust_stamina(-14 / -18)` | 扣减 `EconomyManager.stamina` 并触发 `survival_state_changed` |
| `vol1_dn_05_stone_lizard_ambush` | 魔术大成功 / 失败 | `add_currency(+150)` / `adjust_stamina(-12/-10)` | 战利品折算与撤离体力损耗 |
| `vol1_dn_06_glinting_mana_vein` | 辨矿成功 / Nat20 / 轻采 | `add_currency(demon_ore, +350 / +600 / +120)` | `EconomyManager.add_currency("demon_ore", units)` |
| `vol1_dn_07_dry_well_turbid_water` | 净水成功 / Nat20 / 失败 | `adjust_stamina(+18 / +26 / -12)` | 补水回体 / 腹痛耗体 |
| **`vol1_dn_08_demon_peddler_wagon`** | 购粮 / 讨价 / 询汇 | `buy_supply("ration_normal", 2)` + **`open_exchange("traveling_merchant", 0.05)`** | 弹出旅商 5% 换汇面板或调用 `EconomyManager.execute_exchange(from_id, to_id, units, "traveling_merchant", "city_rikarisu")` |
| **`vol1_dn_09_broken_caravan_axle`** | 修轴成功 / 失败趣闻 | `add_currency(demon_ore, +1000 / +200 / +150)` | 获赠 **1 枚银矿钱（1,000）** + 标记 `vol1_rikarisu_merchant_voucher` 供城内商铺折扣 |
| **`vol1_dn_10_blackmarket_foreign_coin`** | 鉴定成功 / Nat20 / 失败 | `trade_currency(demon_ore: -300/-200 → millis: +100)` | `EconomyManager.add_currency("demon_ore", -300)` + `EconomyManager.add_currency("millis", 100)`（1 枚米里斯大铜钱 = 500 基准点） |
| `vol1_dn_11_campfire_adventurer_tales` | 分享干粮成功 / Nat20 | `adjust_stamina(+20 / +25)` | 烤肉热食回体 |
| `vol1_dn_12_rikarisu_outer_outpost` | 威慑失败 / 登记费 | `add_currency(demon_ore, -100)` | 外哨登记费 1 大绿矿钱 |

### 4.2 轨道 3 `JournalManager`（`core/journal_manager.gd`）图鉴与日记挂接清单
所有事件均声明了 `codex_unlocks[]`（100% 校验存在于 `data/codex/world_codex.json`）与 `diary_hint`：

| 图鉴 ID（`data/codex/world_codex.json`） | 触发事件 ID | 建议调用 |
| :--- | :--- | :--- |
| `geo_migurd_basin` | `vol1_dn_01_basin_mist_tracks` | `JournalManager.unlock_codex("geo_migurd_basin", "晨雾尽头的红岩爪印")` |
| `lore_migurd_tribe` | `vol1_dn_02_emerald_hair_telepathy` | `JournalManager.unlock_codex("lore_migurd_tribe", "翡翠发色与无声回响")` |
| `geo_demon_continent` | `vol1_dn_01`, `04`, `05` | `JournalManager.unlock_codex("geo_demon_continent", event.title)` |
| `eco_demon_ore_currency` | `vol1_dn_03`, `06`, `08`, `09` | `JournalManager.unlock_codex("eco_demon_ore_currency", event.title)` |
| `rule_rations_and_rest` | `vol1_dn_07_dry_well_turbid_water` | `JournalManager.unlock_codex("rule_rations_and_rest", "枯井石槽与微浊泉水")` |
| `eco_six_currency_rates` | `vol1_dn_08`, `10`, `11` | `JournalManager.unlock_codex("eco_six_currency_rates", event.title)` |
| `lore_demon_society` | `vol1_dn_02`, `09`, `12` | `JournalManager.unlock_codex("lore_demon_society", event.title)` |
| **`geo_red_dragon_range`**（默认未解锁） | `vol1_dn_11_campfire_adventurer_tales` | 提前于篝火夜话解锁赤龙山脉传闻词条！ |
| **`lore_adventurer_guild`**（默认未解锁） | `vol1_dn_11`, `vol1_dn_13` | 篝火夜话或城门悬赏栏触发时调用 `JournalManager.unlock_codex("lore_adventurer_guild", ...)` |
| **`lore_six_faced_world`**（默认未解锁） | `vol1_dn_11_campfire_adventurer_tales` | 篝火夜话远方传闻解锁 |
| **`geo_rikarisu`**（默认未解锁） | `vol1_dn_12`, `13`, `14` | 接近利卡里斯哨卡/黄昏初望尖塔时提前点亮利卡里斯图鉴！ |

日记联动：事件结束时调用 `JournalManager.add_entry(hint["category"], hint["title"], outcome_text, {"event_id": event["id"]}, hint["dedupe_key"])` 即可自动按甲龙历记入旅途日记并按 `dedupe_key` 防重。

---

## 5. Godot 4.7.2 无头推演验证结果

执行命令：
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --audio-driver Dummy --path "/Users/mac/Documents/all project/无职转生" --script res://tools/verify_narrative/test_vol1_demon_pack.gd
```

- **总计**：**`13/13 PASS`（0 FAIL）**
- **推演覆盖**：14 个事件 × 42 个选项 × 成功/失败/大成功/大失败/资源耗尽兜底 = **100 条独立分支全量实机干跑通过**
- **Godot 4.7.2 运行期 Error / Warning / Leak**：**`0 Error / 0 Warning / 0 Leak`**
- **既有规则回归检查**（`tools/check_modifiers.gd`）：`MODIFIER CHECK failures=0`（0 Error / 0 Warning）

| 校验项 | 校验内容 | 结果 |
| :--- | :--- | :---: |
| `V01_event_pack_json_valid` | `data/events/pack_vol1_demon_northeast.json` JSON 解析有效 | PASS |
| `V02_storylet_pack_json_valid` | `data/storylets/pack_vol1_demon_northeast.json` JSON 解析有效 | PASS |
| `V03_counts_and_text_hygiene` | 4 池、14 事件、42 选项（27 D20 检定、15 彩蛋）、6 伴生 Storylet，全文本无空串/乱码/占位词 | PASS |
| `V04_global_id_uniqueness` | 与 `region_encounters.json`、`418_demon_continent.json`、`418_world_travel.json` 零 ID 冲突 | PASS |
| `V05_geography_ids_valid` | 全部 `region_id` / `city_ids` / `legacy_locations` / `routes` / `zones` / `danger_tags` 精确对齐地图表 | PASS |
| `V06_d20_checks_options_cooldowns_valid` | 每事件 3 选项、含 D20 检定、6 维属性与 DC 10–13 合法、全部带冷却天数或 `once_only` 防刷 | PASS |
| `V07_effect_opcodes_strictly_valid` | 全部效果指令与 buff 属性键 100% 落入 `EncounterEngine.apply_effects()` 支持集合 | PASS |
| `V08_economy_scale_and_codex_refs_valid` | `demon_ore` 数额平衡、5% 旅商换汇对齐 `currencies.json`、全部图鉴 ID 有效 | PASS |
| `V09_storylet_pack_schema_valid` | 6 条伴生 Storylet 字段、opcode 与 `event_pack_ref` 映射完全合法 | PASS |
| `V10_encounter_engine_pool_rolling` | 真实 `EncounterEngine.roll_leg_encounter()` 在 60 km `city_migurd -> city_rikarisu` 路段 4 池全通 | PASS |
| `V11_exhaustive_14_event_dry_run` | 100 条选项/分支（含零钱零粮防卡死兜底）在真实 `EncounterEngine` + `RuleEngine` 下零报错跑通 | PASS |
| `V12_storylet_scheduler_auto_load_and_dry_run` | `StoryletScheduler` 自动载入 6 条伴生片段、保留 `rikarisu_gate_entry` 钩子并干跑通过 | PASS |
| `V13_track1_economy_and_track3_codex_live_verified` | 实机核验 `EconomyManager` 5% 换汇（`100 millis -> 475 demon_ore`）与干粮定价（利卡里斯 400 / 米格路德 300）及 `JournalManager` 图鉴词条全命中 | PASS |

---

## 6. 后续扩写其他大区（温恩港 / 米里斯 / 中央大陆）的模板复用建议

1. **统一扩展包文件命名与分包隔离**：
   - `data/events/pack_vol1_demon_south_windport.json`（利卡里斯 ↔ 克拉斯玛 ↔ 温恩港：聚焦长途干粮、海港渡船 25,000 基准点船资筹措与 `eco_sea_ferry_trade` 图鉴解锁）；
   - `data/events/pack_vol2_milis_sacred_road.json`（赞特港 ↔ 大森林 ↔ 王都米里希翁：聚焦 `millis` 币 `×0.50` 物价、6–8 月雨季事件、圣殿外貌戒心与 `travel_hood` 兜帽 `+2` 互动）；
   - `data/events/pack_vol3_central_red_dragon.json`（东港 ↔ 王龙王国 ↔ 西隆 ↔ 赤龙下颚 ↔ 菲托亚/阿尔斯/夏利亚：聚焦 `king_dragon` / `minor_central` / `magic_nations` / `asura` 四区物价阶梯与 11–2 月严冬防寒斗篷联动）。
2. **四大区货币基准换算守则（严防数值膨胀）**：
   - 所有事件内购粮/报酬均以 `data/economy/currencies.json` 的 `unit_base_value` 为锚（`demon_ore = 1`、`minor_central = 2`、`magic_nations = 4`、`millis = 5`、`king_dragon = 8`、`asura = 10`），确保 1 份普通干粮基准恒定 `200` 基准点（再乘城镇 `price_multiplier`），避免跨洲套利漏洞。
3. **四段式配池黄金结构与校验器一键复用**：
   - 每个大区包建议保持「风土人文（3）+ 气候地形魔物险情（4）+ 货币行商与 NPC 互助（4）+ 枢纽城门/海港前奏与氛围里程碑（3）」共 14 事件结构；
   - `tools/verify_narrative/test_vol1_demon_pack.gd` 的 `_verify_event_pack_schema_and_balance` 与 `_verify_encounter_engine_dry_run` 可直接抽象为多包循环校验器，新大区 JSON 落地后 5 秒内即可完成全分支无头验收。
