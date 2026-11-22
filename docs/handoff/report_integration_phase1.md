# 系统总装合拢 · 阶段一交接报告（轨道 4 正式接入 + 轨道 1 / 3 / D20 跨系统闭环）

- **阶段定位**：系统总装合拢 · 阶段一（非大地图与非奇遇剧情包部分完整闭环）
- **引擎版本**：`Godot Engine v4.7.2.stable.official.ed1daf0bf`（纯强类型 GDScript，零第三方依赖）
- **完成时间**：2026-11-21
- **总体状态**：✅ **全部合拢并通过全量回归**（**4 套自动化测试共 1,058 / 1,058 项通过，0 Error / 0 Warning / 0 Leak**）

---

## 一、三线并发防冲突核查结论与实测清单

### 1.1 零冲突隔离核验
本轮严格避让并发推进中的大地图 3D 样板区轨道（Agent 1）、第一卷魔大陆奇遇事件包轨道（Agent 3）及冻结战斗目录，对以下全部禁入路径 **触碰与修改次数严格为 `0`**：
- ❌ `scenes/world_map/`、`assets/3d/world_v2/`、`tools/blender_world_v2/`、`assets/textures/world_v2/`、`shaders/world_relief_*`（0 次修改）
- ❌ `data/events/`、`data/storylets/`、`tools/verify_narrative/`（0 次修改）
- ❌ `core/combat_engine.gd`、`scenes/combat/`、`data/combat/`（0 次修改）

### 1.2 本阶段实际新增/修改文件明细（共 13 个文件）

| 文件路径 | 操作 | 核心合拢改动 |
|---|---|---|
| `project.godot` | 修改 | 在 `[autoload]` 按依赖序注册 `AudioBusManager` → `AudioManager` → `SettingsManager`（全量 12 个 Autoload 顺序严密）；追加 `[audio] buses/default_bus_layout="res://resources/audio/game_bus_layout.tres"` |
| `core/audio_manager.gd` | 修改 | 100% 保留既有 65 处字符串签名调用（`play_sfx(String)` / `bind_ui()` / `play_modifier_impact()` / `has_voice()` / `play_voice(String)`），平滑桥接 `AudioBusManager` 提供标准 5 轨音量控制（`Master/BGM/Ambience/SFX/Voice`）、BGM 双通道 Crossfade、Ambience 切换、弹窗低通柔化（`set_bgm_muffled`）、未来配音 BGM 自动 Ducking 及零泄漏 `_exit_tree()` / `stop_all_sfx()` |
| `core/rule_engine.gd` | 修改 | 新增 `check_resolved(outcome: Dictionary, context: Dictionary)` 信号；`roll_check()` 为每次非沙盒 D20 检定打标 `stat`、`skill_label`、`context_note` 与唯一 `roll_uid` 供手账高光去重 |
| `core/economy_manager.gd` | 修改 | 新增语义领域信号 `exchange_completed(result: Dictionary)` 与 `purchase_completed(kind: String, result: Dictionary)`，供手账与未来成就/UI 解耦订阅 |
| `data/codex/world_codex.json` | 微调 | 将 `eco_six_currency_rates`（六大货币区与换汇常识）设为 `default_unlocked: false`，使其在玩家首次跨币种换汇或持有外大陆通货时即时解锁并点亮未读红点 |
| `core/journal_manager.gd` | 修改 | 订阅 `RuleEngine.check_resolved`（自然 20/1 自动写高光日记，按 `dice_uid:<roll_uid>` 去重，普通检定零刷屏）；订阅 `EconomyManager.exchange_completed` / `purchase_completed`（首次 0%/5% 换汇、首次外币直付、大额跨洲换汇及旅馆休整自动解锁对应图鉴并写入去重日记）；`record_dice_highlight()` 向后兼容追加可选 `dedupe_key` 参数 |
| `ui/ui_theme_kit.gd` | 微调 | 在 `MicroIcon` 增补 `"gear"` 矢量齿轮图标（用于标题页、木屋工具栏与手账顶栏设置按钮） |
| `scenes/dialogue/dialogue_widgets.gd` | 微调 | 在 `DialogueGlyph` 增补 `"gear"` 轻小说极简矢量齿轮图标 |
| `ui/journal_ui.gd` | 修改 | 统一托管共享 `SettingsOverlay`（`scenes/ui/settings/settings_overlay.tscn`，自动注入 `SettingsManager` 与 `AudioBusManager`），暴露 `open_settings()` / `close_settings()` / `is_settings_open()`，接入 `Esc` 关闭链，并在 `make_toolbar()` 中增设紧凑 `"gear"` 设置入口 |
| `ui/character_journal_overlay.gd` | 微调 | 在手账顶栏「合上 Esc」左侧增设紧凑 `"gear"` 设置入口（支持翻阅手账时直接呼出设置浮层） |
| `scenes/title/title_screen.gd` | 修改 | 在主菜单「读取手账」与「离开」之间增设「系统设置」书法条目，并暴露 `open_settings()` / `close_settings()` / `is_settings_open()` 入口（打开自动柔化 BGM、关闭平滑恢复） |
| `scenes/dialogue/dialogue_view.gd` | 修改 | 实时订阅 `SettingsManager` 的 `text_speed`（含瞬显模式 `>= 2.45`）与 `auto_play_delay`；右上工具栏新增「系统设置」图标按钮；将选项卡片负向检定修正色温统一修正为冷海雾蓝（`Kit.MODIFIER_COLD_VALUE / LIGHT`）；向 `AudioManager.play_voice()` 透传说话人 `pid` 以支持语音 Ducking |
| `ui/d20_3d_stage.gd` & `ui/dice_roll_overlay.gd` | 修改 | 实时订阅 `SettingsManager.get_dice_time_scale()`（`"normal" = 1.0` / `"fast" = 1.8`），等比缩放 3D 落骰、收敛、修正吸收飞行与停顿时长；在 `_stamp()` 结算出口补充 `JournalManager.record_dice_highlight()`（与 `RuleEngine.check_resolved` 共用 `dice_uid:<roll_uid>` 保证零重复零遗漏） |
| `tools/verify_integration/test_phase1_integration.gd` | 新增 | 阶段一跨系统端到端集成测试（50 项断言） |
| `docs/handoff/report_integration_phase1.md` | 新增 | 本阶段一总装交接报告 |

### 1.3 实测 `git status --short` 完整清单
> 说明：清单中的 `scenes/world_map/`、`tools/blender_world_v2/`、`assets/3d/world_v2/`、`assets/textures/world_v2/`、`data/events/` 等条目系由并行 Agent 1、Agent 3 及前序里程碑 M1~M4 产生，阶段一总装未触碰上述任何路径。

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
?? tools/verify_settings_audio/
?? ui/area_arrival_banner.gd
?? ui/area_arrival_banner.gd.uid
?? ui/journal_codex_view.gd
?? ui/journal_diary_view.gd
?? ui/prop_3d_viewer.gd
?? ui/prop_3d_viewer.gd.uid
```

---

## 二、全量统一回归统计（Godot 4.7.2 无头模式）

全部 4 套自动化测试套件在同一 `project.godot` 总装状态下连续执行通过：

| 测试套件 | 脚本路径 | 通过数 | 失败数 | Error / Warning / Leak |
|---|---|---:|---:|---|
| 阶段一跨系统联调套件（新增） | `tools/verify_integration/test_phase1_integration.gd` | **50** | **0** | **0 / 0 / 0** |
| 轨道 1 多币种经济与休整套件 | `tools/verify_economy/test_economy_system.gd` | **822** | **0** | **0 / 0 / 0** |
| 轨道 3 手账日记与世界图鉴套件 | `tools/verify_journal/test_journal_system.gd` | **170** | **0** | **0 / 0 / 0** |
| 轨道 4 系统设置与 5 轨音频套件 | `tools/verify_settings_audio/test_settings_audio.gd` | **16** | **0** | **0 / 0 / 0** |
| **合计** | **4 Suites** | **1,058** | **0** | **0 Error / 0 Warning / 0 Leak** |

---

## 三、已贯通的跨模块信号与数据流清单

### 3.1 启动与设置/音频链路
1. **Autoload 初始化顺序（`project.godot`）**：
   `WorldBlackboard` → `RuleEngine` → `AudioBusManager` → `AudioManager` → `SettingsManager` → `SceneTransition` → `StatChangeBanner` → `StoryletScheduler` → `SaveManager` → `EconomyManager` → `JournalManager` → `JournalUI`
2. **启动自动生效**：
   `AudioBusManager._ready()` 载入 `res://resources/audio/game_bus_layout.tres`（5 轨 + BGM 低通槽）→ `SettingsManager._ready()` 自动读取 `user://settings.cfg` 并立即应用 5 轨音量、桌面显示模式与垂直同步。
3. **弹窗 BGM 低通柔化**：
   `TitleScreen` / `DialogueView` / `RoomExplorer` / `CharacterJournalOverlay` → `JournalUI.open_settings()` → `SettingsOverlay.open()` → `AudioBusManager.set_bgm_muffled(true, 0.25)`；关闭时自动平滑还原 `set_bgm_muffled(false, 0.25)`。
4. **阅读与演出实时联动**：
   - `SettingsManager.settings_changed("reading", ...)` / `settings_loaded` / `settings_reset` → `DialogueView._sync_reading_settings()`（即时更新逐字流速、瞬显模式与自动阅读停顿）；
   - `SettingsManager.settings_changed("reading", "dice_animation_speed", ...)` → `DiceRollOverlay._sync_dice_speed_settings()` → `D20Stage.set_time_scale(1.0 | 1.8)`。
5. **未来角色配音自动闪避**：
   `DialogueView` → `AudioManager.play_voice(voice_path, speaker_id)` → `AudioBusManager.play_voice(stream, speaker_id)` → 缺失文件静默略过，有效语音自动触发 `BGM -6.5 dB` Ducking 并在播毕/推进时平滑恢复。

### 3.2 经济 ↔ D&D 规则 ↔ 手账日记/图鉴 ↔ 存档链路
1. **经济生存状态 → D&D 检定链**：
   `EconomyManager._provide_rule_modifiers` 注册为 `RuleEngine` 修正提供者（`"economy_survival"`, priority `80`），将 `饱腹暖胃 (+1)`、`精力充沛 (+1)`、`饥饿 (-1)`、`虚弱断粮 (-2)` 注入全部 `RuleEngine.collect_check()` / `roll_check()`，并在 `DialogueView` 选项卡片与 `DiceRollOverlay` 芯片上严格按**正向暖金 / 负向冷海雾蓝**着色。
2. **D20 命运高光 → 手账日记**：
   `RuleEngine.check_resolved(outcome, context)` + `DiceRollOverlay._record_critical_highlight()` 双重兜底、共用 `dedupe_key = "dice_uid:<roll_uid>"`：自然 20 自动写入暖金「大成功 ★」、自然 1 自动写入冷海雾蓝「大失败」，普通点数与沙盒掷骰绝不刷屏。
3. **经济里程碑 → 手账日记 + 六面世界图鉴**：
   - `EconomyManager.exchange_completed` → `JournalManager._on_economy_exchange_completed`：首次跨币换汇自动解锁 `eco_six_currency_rates`（及对应币种/协会词条）并点亮未读红点，写入去重里程碑日记；
   - `EconomyManager.purchase_completed` → `JournalManager._on_economy_purchase_completed`：首次外币折算直付、大型旅馆休整写入去重日记并解锁对应货币词条；
   - `EconomyManager.survival_state_changed` → `JournalManager._on_economy_survival_changed`：首次断粮与热水浴「精力充沛 +1」写入去重日记。
4. **手账未读角标 & 存档全量水合**：
   `JournalManager.codex_read_changed(unread_count)` 实时刷新 `CharacterJournalOverlay` 顶栏 `世界图鉴 ●N`，点击未读词条后自动消点；`SaveManager` 按 `world` → `storylets` → `economy` → `journal` 顺序序列化与恢复，保持 `SCHEMA_VERSION = 1` 并完全兼容缺失 `economy`/`journal` 字段的老存档。

---

## 四、留待阶段二总装的精确挂接清单（大地图 + 轨道 2 奇遇包）

待 Agent 1（大地图 3D 样板区）与 Agent 3（第一卷魔大陆奇遇事件包）交接后，阶段二只需按以下 5 处轻量挂接即可完成全游戏大合拢：

1. **大地图接入系统设置按钮与画质/天气实时订阅（`scenes/world_map/world_atlas_view.gd` & `world_weather_stage.gd`）**
   - 顶栏按钮调用 `JournalUI.open_settings("graphics")`（自动触发 BGM 低通柔化，免重复实例化）；
   - `_ready()` 订阅 `SettingsManager.graphics_preset_changed` 与 `SettingsManager.settings_changed`：
     ```gdscript
     SettingsManager.apply_graphics_to_viewport(get_viewport())
     SettingsManager.graphics_preset_changed.connect(_on_graphics_preset_changed)
     SettingsManager.settings_changed.connect(_on_graphics_setting_changed)
     ```
     在回调中按 `profile["ssao_enabled"]`、`profile["ssil_enabled"]`、`profile["glow_enabled"]`、`profile["weather_particle_scale"]` 与 `map_weather_particles` 开关实时调整 `WorldEnvironment` 与 `world_weather_stage.gd`。

2. **大地图接入城镇服务浮层（`scenes/world_map/world_atlas_view.gd` ↔ `scenes/ui/town_services/town_services_overlay.tscn`）**
   - 驻城卡片新增「城镇服务（换汇 / 旅馆 / 餐馆 / 补给）」按钮，呼出 `TownServicesOverlay.open_for_city(WorldBlackboard.current_city_id, "guild")`；
   - 跨海客船航段扣费可复用 `EconomyManager.get_ferry_fare_quote(from_city_id, to_city_id, pay_currency_id)` 与 `EconomyManager.execute_purchase(...)`；
   - 大地图顶栏货币文本直接绑定 `WorldBlackboard.get_currency_display_text()` 与 `WorldBlackboard.currency_display_changed` 信号即可实时展示当地多币种进位文本。

3. **大地图抵城结算接入自动日记与图鉴解锁（`scenes/world_map/world_atlas_view.gd` / `atlas_travel_stage.gd`）**
   - 旅途抵达城池结算回调中追加一行：
     ```gdscript
     JournalManager.record_city_arrival(target_city_id, target_city_name)
     ```
   - 跨日行进结算中可将原有干粮扣减平滑切换至 `EconomyManager.consume_daily_rations(days, party_size)`，自动贯通饥饿/断粮 `-1/-2` 与手账警讯；
   - 大地图顶栏「手账」按钮订阅 `JournalManager.codex_read_changed(unread_count)` 渲染暖金未读圆点。

4. **大地图随机遭遇检定确认接入 `RuleEngine` 与 `DiceRollOverlay`（`scenes/world_map/atlas_encounter_overlay.gd`）**
   - 确认其使用 `RuleEngine.roll_check(...)` 与 `DiceRollOverlay.present(...)` 后，将自动继承：经济饱腹/饥饿修正 + 设置面板 3D 骰子速度 + Nat 20/1 自动写入手账日记（无需重复编写任何胶水代码）。

5. **接入轨道 2 第一卷魔大陆奇遇事件包（`data/events/pack_vol1_demon_northeast.json` ↔ `core/storylet_scheduler.gd` / `core/encounter_engine.gd`）**
   - 核对事件包产出 Schema 并挂入调度器；事件结算中的 `codex_unlock` / `diary_entry` / `currency_delta` 效果字段直接映射到 `JournalManager.unlock_codex(...)`、`JournalManager.add_entry(...)` 与 `EconomyManager.add_currency(...)`，完成后重跑全量 5 套测试闭环收官。
