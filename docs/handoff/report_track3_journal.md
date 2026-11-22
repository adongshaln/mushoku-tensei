# 并行轨道 3 总控交接报告：手账「自动旅途日记 + 六面世界图鉴」驱动底座与 UI 升级

- **负责轨道**：并行轨道 3（Journal Diary & World Codex）
- **引擎版本**：Godot 4.7.2.stable.official (`Forward Plus` / `Mobile` 兼容，纯强类型 GDScript)
- **交付日期**：2026-11-21
- **验收状态**：✅ **全部完成并通过**（轨道 3 无头单测 **170 / 170** 通过 + 轨道 1 回归 **822 / 822** 通过，**0 报错、0 告警、0 泄漏**）

---

## 一、任务状态与三线零冲突证明

### 1.1 并行目录防冲突核查结论
本轨道严格遵守三线并发红线，所有新增与修改操作仅发生在以下允许路径内：
- `data/codex/`
- `core/journal_manager.gd`、`core/world_blackboard.gd`、`project.godot`
- 既有手账外壳目录 `ui/`（`character_journal_overlay.gd`、`journal_ui.gd`、`journal_diary_view.gd`、`journal_codex_view.gd`）及独立预览场景 `scenes/ui/journal/`
- `tools/verify_journal/`
- `docs/handoff/report_track3_journal.md`

对以下三类并发/冻结目录 **触碰次数严格为 0**：
- ❌ 3D 大地图轨道：`scenes/world_map/`、`assets/3d/world_v2/`、`tools/blender_world_v2/`（0 次修改）
- ❌ 设置与多轨音频轨道：`core/settings_manager.gd`、`core/audio_manager.gd`、`resources/audio/`、`scenes/ui/settings/`、`tools/verify_settings_audio/`（0 次修改）
- ❌ 冻结战斗模块：`core/combat_engine.gd`、`scenes/combat/`、`data/combat/`（0 次修改）

> 注：下述 `git status --short` 中出现的 `scenes/world_map/`、`tools/blender_world_v2/`、`core/settings_manager.gd`、`scenes/ui/settings/`、`resources/` 等条目均为并行轨道及前序里程碑 M1~M4 的未提交变更，本轨道未做任何修改。

### 1.2 实测 `git status --short` 完整清单
```text
 M AGENTS.md
 M core/audio_manager.gd
 M core/character_catalog.gd
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
?? data/maps/region_encounters.json
?? data/maps/world_relief_meta.json
?? docs/
?? resources/
?? scenes/dialogue/dialogue_widgets.gd
?? scenes/dialogue/dialogue_widgets.gd.uid
?? scenes/ui/
?? scenes/world_map/atlas_encounter_overlay.gd
?? scenes/world_map/atlas_encounter_overlay.gd.uid
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
?? tools/verify_journal/
?? tools/verify_settings_audio/
?? ui/area_arrival_banner.gd
?? ui/area_arrival_banner.gd.uid
?? ui/journal_codex_view.gd
?? ui/journal_diary_view.gd
?? ui/prop_3d_viewer.gd
?? ui/prop_3d_viewer.gd.uid
```

---

## 二、本轨道新增与修改文件清单

| 文件路径 | 操作 | 职责与改动范围 |
|---|---|---|
| `data/codex/world_codex.json` | 新增 | 六面世界图鉴可扩展种子表：4 大分类（`geography` / `races_lore` / `economy` / `rules`）、16 篇精炼轻小说注释体词条（9 篇初始解锁 + 7 篇待旅途发掘），含声明式 `unlock_triggers`（`cities` / `flags` / `currencies`） |
| `core/journal_manager.gd` | 新增 | Autoload 单例 `JournalManager`：自动旅途日记流（甲龙历时间与地点抓取、`dedupe_key` 去重、分类筛选/关键词检索/排序、500 条滚动归档上限）、图鉴解锁与未读追踪引擎、轻量响应式监听及 `SaveManager` `"journal"` 模块双向持久化（兼容无 `journal` 字段旧存档） |
| `core/world_blackboard.gd` | 微调 | 仅新增 `chronicle_recorded(entry: Dictionary)` 信号并在 `record_chronicle()` 末尾发射（+4/-1 行），零破坏既有接口 |
| `project.godot` | 微调 | 在 `[autoload]` 中于 `SaveManager`、`EconomyManager` 之后与 `JournalUI` 之前注册 `JournalManager="*res://core/journal_manager.gd"`，保证初始化与存档水合顺序严格正确 |
| `ui/journal_diary_view.gd` | 新增 | 「旅途日记」双页手账视图：左页收录统计 + 分类筛选胶囊 + 关键词检索 + 正/倒序切换 + 色温图例；右页甲龙历鎏金时间轴（暖金大成功/里程碑 vs 冷海雾蓝险情/断粮/大失败） |
| `ui/journal_codex_view.gd` | 新增 | 「世界图鉴」双页手账视图：左页收集度进度条 + 单行 5 分类胶囊 + 目录列表（含暖金未读圆点 `● 新收录` 与 `？？？ · 待旅途发掘` 灰显态）；右页轻小说注释阅读页，点选未读词条自动消点 |
| `ui/character_journal_overlay.gd` | 扩展 | 在既有 `FolioOverlay` 精装手账顶栏平滑集成三主键页签「旅途总览」「旅途日记」「世界图鉴 ●N」，完整保留既有角色立绘、星盘与 4 子页签，同时同步展示本地货币与经济生存修正，并新增 `open_section()` / `select_section()` / `set_preview_offset_top()` |
| `ui/journal_ui.gd` | 扩展 | 保留既有全部方法与快捷键，追加 `open_diary()`、`open_codex(entry_id := "")`、`get_unread_codex_count()` |
| `scenes/ui/journal/journal_v2_preview.tscn` & `.gd` | 新增 | 极简 `.tscn` 根节点 + 独立交互预览入口，内置演示行程数据、三主页签一键切换、大成功追加与米里斯图鉴实时解锁按钮 |
| `tools/verify_journal/test_journal_system.gd` | 新增 | Godot 4.7.2 无头自动化测试套件（170 项断言覆盖 JSON 完整性、日记/去重/筛选/500 条上限、城池抵达解锁与未读增减、存档往返与旧存档迁移、预览场景冒烟） |
| `tools/verify_journal/capture_journal_shots.gd` | 新增 | 1920×1080 实机界面自动截图脚本（输出旅途日记、世界图鉴、升级后总览 3 张 PNG） |
| `docs/handoff/report_track3_journal.md` | 新增 | 本标准化总控交接报告 |

---

## 三、对外公共 API 与信号契约（`JournalManager`）

### 3.1 Signals
```gdscript
signal diary_entry_added(entry: Dictionary)
signal diary_changed
signal codex_unlocked(entry_id: String, entry_data: Dictionary)
signal codex_read_changed(unread_count: int)
signal journal_state_changed
```

### 3.2 日记引擎公共方法
```gdscript
func add_entry(category: String, title: String, body: String, meta: Dictionary = {}, dedupe_key: String = "") -> Dictionary
func record_city_arrival(city_id: String, city_name: String = "") -> Dictionary
func record_dice_highlight(skill_name: String, roll: int, dc: int, is_crit_success: bool, is_crit_fail: bool, context: String = "") -> Dictionary
func record_economy_event(event_type: String, summary: String, meta: Dictionary = {}) -> Dictionary
func get_diary_entries(category: String = "all", keyword: String = "", newest_first: bool = true) -> Array[Dictionary]
func get_diary_count(category: String = "all") -> int
func get_diary_category_counts() -> Dictionary[String, int]
func clear_diary() -> void
```
- **合法 `category`**：`"travel"`（行程）、`"economy"`（商贸）、`"dice"`（命运）、`"milestone"`（里程碑）
- **色温 `meta["tone"]`**：`"positive"`（暖金）、`"negative"`（冷海雾蓝）、`"neutral"`（羊皮纸墨褐）
- **归档保护**：`MAX_DIARY_ENTRIES := 500`（超出后从最旧条目滚动清理并同步维护 `_dedupe_index`）

### 3.3 六面世界图鉴公共方法
```gdscript
func get_codex_categories() -> Array[Dictionary]
func get_codex_category_label(category_id: String) -> String
func get_codex_entries(category: String = "all") -> Array[Dictionary]
func get_codex_entry(entry_id: String) -> Dictionary
func is_codex_unlocked(entry_id: String) -> bool
func is_codex_unread(entry_id: String) -> bool
func unlock_codex(entry_id: String, source_hint: String = "", mark_as_unread: bool = true) -> bool
func mark_codex_read(entry_id: String) -> bool
func mark_all_codex_read() -> void
func get_unread_codex_count() -> int
func get_codex_progress() -> Dictionary   # {"unlocked": int, "total": int, "unread": int, "ratio": float}
func sync_codex_from_world(mark_new_unread: bool = false) -> int
```

### 3.4 持久化与生命周期方法
```gdscript
func reset_for_new_game() -> void
func serialize_state() -> Dictionary
func deserialize_state(payload: Dictionary) -> bool
```

### 3.5 `JournalUI` / `CharacterJournalOverlay` 新增界面入口
```gdscript
# JournalUI Autoload
func open_diary() -> void
func open_codex(entry_id: String = "") -> void
func get_unread_codex_count() -> int

# CharacterJournalOverlay (JournalUI.character)
func open_section(section_id: String, codex_entry_id: String = "") -> void
func select_section(section_id: String, animate: bool = true) -> void
func get_active_section() -> String
```

---

## 四、与其他模块的衔接点说明（单行接入示例）

1. **大地图抵达城池结算（`scenes/world_map/` 后续合入点）**
   抵达新城镇时调用一行即可同时写入甲龙历行程手记 + 自动解锁对应地域/风土图鉴并点亮未读红点：
   ```gdscript
   JournalManager.record_city_arrival(target_city_id, target_city_name)
   ```

2. **D20 命运掷骰演出（`ui/dice_roll_overlay.gd` 或事件结算点）**
   掷出自然 20（大成功）或自然 1（大失败）时自动刻入高光手账（暖金 / 冷蓝自动着色）：
   ```gdscript
   if natural_roll == 20 or natural_roll == 1:
       JournalManager.record_dice_highlight(skill_label, natural_roll, dc, natural_roll == 20, natural_roll == 1, scene_context)
   ```

3. **城镇经济大额换汇 / 跨海船票 / 关键消费（`scenes/ui/town_services/` 后续按需挂接）**
   ```gdscript
   JournalManager.record_economy_event("guild_exchange", "于利卡里斯镇协会零费换得 2 米里斯大铜钱。", {"currency_id": "millis"})
   ```
   > 注：断粮警讯与热水浴「精力充沛 +1」已通过轻量监听 `EconomyManager.survival_state_changed` 自动去重录载，无需业务方重复写入。

4. **Storylet / 主线剧情里程碑与自定义图鉴解锁**
   ```gdscript
   JournalManager.add_entry("milestone", "初遇旅途同行者", "在荒原营火旁结识了同路旅人。", {"tone": "positive"}, "story:first_companion")
   JournalManager.unlock_codex("lore_six_faced_world", "酒馆传闻")
   ```

5. **顶栏未读红点角标联动**
   大地图或室内顶栏手账按钮监听 `JournalManager.codex_read_changed(unread_count)` 即可零轮询实时刷新未读圆点。

---

## 五、实机验证与回归结果

### 5.1 自动化测试汇总（Godot 4.7.2 无头模式）
| 测试套件 | 执行命令 | 通过数 | 失败数 | 报错 / 告警 |
|---|---|---|---|---|
| 轨道 3 手账日记与图鉴全链路单测 | `/Users/mac/.local/bin/godot --headless --path . -s res://tools/verify_journal/test_journal_system.gd` | **170** | **0** | **0 报错 / 0 告警** |
| 轨道 1 多币种经济与休整全链路回归 | `/Users/mac/.local/bin/godot --headless --path . -s res://tools/verify_economy/test_economy_system.gd` | **822** | **0** | **0 报错 / 0 告警** |

### 5.2 实机渲染截图验收（Metal 4.0 Forward+，1920×1080）
执行命令：
```bash
/Users/mac/.local/bin/godot --path . --resolution 1920x1080 -s res://tools/verify_journal/capture_journal_shots.gd
```
截图已归档至工作区校验目录（同时同步至对话产物目录）：
1. **旅途日记时间轴**：`tools/verify_journal/01_journal_diary_timeline.png`（验证甲龙历时间轴、暖金「大成功 ★ / 免税换汇 / 新地踏足」与冷海雾蓝「断粮险情 / 大失败」卡片、左侧分类计数胶囊与检索栏）
2. **六面世界图鉴阅读页**：`tools/verify_journal/02_journal_codex_reading.png`（验证 5 分类单行胶囊、收集进度条 `11 / 16 (69%)`、已解锁阅读页「利卡里斯镇」、暖金未读圆点 `● 冒险者协会体系` 与未解锁 `？？？ · 待旅途发掘` 灰显态）
3. **既有「旅途总览」兼容态**：`tools/verify_journal/03_journal_overview_upgraded.png`（验证三主页签顶栏、`世界图鉴 ●1` 未读提示、多币种钱包 `4 银矿 5 大绿` 与原有立绘/六维星盘零回归）

---

## 六、遗留事项与后续扩展建议

1. **三线总合入联调（由总控执行）**：
   - 将 `JournalManager.record_city_arrival(city_id, city_name)` 挂入大地图城池抵达结算钩子；
   - 将 `JournalManager.record_dice_highlight(...)` 挂入 `ui/dice_roll_overlay.gd` 掷骰终值回调（仅自然 20/1 自动记录）；
   - 如需在大地图/室内顶栏「手账」按钮上显示未读小圆点，可直接订阅 `JournalManager.codex_read_changed`。
2. **图鉴无代码扩容**：后续只需向 `data/codex/world_codex.json` 的 `entries` 数组追加词条（如剑神流/水神流/北神流、七大列强、各国名产、主要伙伴人物志），无需改动任何 GDScript 代码。
3. **可选增强**：当首次触发 `JournalManager.codex_unlocked` 时，可复用与 `StatChangeBanner` 相同的非阻断轻量横幅在屏幕右上角提示「已收录新图鉴：《XXX》」，进一步强化探索正反馈。
