# Track 4 总控交接报告：系统设置外壳 + 多轨音频/未来配音总线底座

- **项目**：《无职转生～属于你自己的人生～》（Godot 4.7.2 / 纯 GDScript）
- **并行轨道**：Track 4（独立零冲突模块）
- **交付日期**：2026-11-21
- **验证环境**：`Godot Engine v4.7.2.stable.official.ed1daf0bf`（macOS Apple M4，Headless + Metal Forward+ 实机截帧双通）

---

## 1. 任务状态与零冲突证明

### 1.1 任务完成状态
- **多轨音频总线布局资源**：已完成 `resources/audio/game_bus_layout.tres`（5 轨 `Master / BGM / Ambience / SFX / Voice` + `BGM` 低通滤镜槽位）。
- **多轨音频与未来配音管理器**：已完成 `resources/audio/audio_bus_manager.gd`（详见下方重要架构防冲突说明）。
- **系统设置持久化与画质分档引擎**：已完成 `core/settings_manager.gd`（独立 `ConfigFile` 落盘 `user://settings.cfg`，3 档画质 Profile + 12 项核心设置 + 完整容错与信号驱动）。
- **暖羊皮纸手账风设置浮层 UI & 预览沙盒**：已完成 `scenes/ui/settings/settings_overlay.tscn/.gd` 与 `scenes/ui/settings/settings_preview.tscn/.gd`（3 分区标签、自定义果冻开关与海雾蓝滑块、测试微铃声、移动端自动隐藏显示模式）。
- **自动化验证与实机截图**：无头回归 `16/16 PASS`（0 Error / 0 Warning / 0 Leak），实机渲染 3 张全页签预览截图。

### 1.2 重要零冲突防踩坑说明（关于既有的 `core/audio_manager.gd`）
在动工前盘点仓库发现：**`core/audio_manager.gd` 为既有已追踪文件（且已在 `project.godot` 第 13 行注册为 `AudioManager` Autoload，全项目 `ui/ui_theme_kit.gd`、`scenes/dialogue/dialogue_view.gd`、`scenes/world_map/world_atlas_view.gd` 等共 65 处调用了字符串签名 `play_sfx(sound: String)` / `play_voice(voice_path: String)` / `bind_ui(...)`）**。
为严格遵守最高优先级红线「**只新建、不改任何既有老文件（修改旧文件数 = 0）**」并避免强类型签名冲突破坏正在并行运行 Godot 的其他轨道：
1. 本轨道 **未触碰** `core/audio_manager.gd` 与 `default_bus_layout.tres`（既有 65 处调用 100% 保持原样可用）；
2. 全新强类型 `AudioStream` 多轨音频与配音底座严格新建于允许白名单目录 `resources/audio/audio_bus_manager.gd`；
3. `SettingsManager.apply_audio_settings()` 同时兼容新 `AudioBusManager` 与既有 `AudioManager`，并直接补齐 `AudioServer` 的 `Master / Ambience` 音轨控制，合拢阶段可零痛点挂载为并行 Autoload 或渐进合并（详见第 4 节）。

### 1.3 零冲突证明（`git status --short` 完整输出）
说明：下表中既有的 `M` 标记文件及 `core/economy_manager.gd`、`tools/verify_economy/` 等 `??` 文件为本轨道启动前已存在或由并行 Track 1–3 产生；**本轨道实际写入的文件 100% 位于白名单新建路径内，修改既有项目文件数 = `0`**，未触碰 `project.godot`、`scenes/world_map/`、`assets/3d/world_v2/`、`tools/blender_world_v2/`、`data/economy/`、`scenes/ui/town_services/`、`core/save_manager.gd`、`core/world_blackboard.gd` 及战斗目录。

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
?? core/settings_manager.gd
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
?? tools/verify_settings_audio/
?? ui/area_arrival_banner.gd
?? ui/area_arrival_banner.gd.uid
?? ui/prop_3d_viewer.gd
?? ui/prop_3d_viewer.gd.uid
```

Track 4 专属新增路径清单（`git status --short --untracked-files=all -- resources/ core/settings_manager.gd scenes/ui/settings/ tools/verify_settings_audio/ docs/handoff/report_track4_settings_audio.md`）：
```text
?? core/settings_manager.gd
?? docs/handoff/report_track4_settings_audio.md
?? resources/audio/audio_bus_manager.gd
?? resources/audio/game_bus_layout.tres
?? scenes/ui/settings/settings_overlay.gd
?? scenes/ui/settings/settings_overlay.tscn
?? scenes/ui/settings/settings_preview.gd
?? scenes/ui/settings/settings_preview.tscn
?? tools/verify_settings_audio/capture_preview.gd
?? tools/verify_settings_audio/settings_preview_audio.png
?? tools/verify_settings_audio/settings_preview_graphics.png
?? tools/verify_settings_audio/settings_preview_reading.png
?? tools/verify_settings_audio/test_settings_audio.gd
```

---

## 2. 新增文件清单

| 文件路径 | 核心职责 | 代码行数 |
| :--- | :--- | ---: |
| `resources/audio/game_bus_layout.tres` | 标准 5 轨音频总线布局资源（`Master` / `BGM` 含 `AudioEffectLowPassFilter` 预留槽 / `Ambience` / `SFX` / `Voice`） | 34 |
| `resources/audio/audio_bus_manager.gd` | 独立强类型多轨音频与配音底座：自动载入/兜底建轨、BGM 双通道 Crossfade 与弹窗低通柔化、Ambience 平滑切换、6 槽 SFX 对象池、Voice 专轨与 BGM 自动 Ducking、零资产柔和测试铃音、空资源静默保护 | 763 |
| `core/settings_manager.gd` | 系统设置独立持久化管理器（`user://settings.cfg`）：12 项核心偏好、3 档画质推荐 Profile、非法/越界/损坏配置自动回退默认值、跨平台检测（移动端隐藏显示模式）、解耦信号分发与一键重置 | 554 |
| `scenes/ui/settings/settings_overlay.tscn` | 极简设置浮层场景根节点（`CanvasLayer`, `layer = 120`） | 7 |
| `scenes/ui/settings/settings_overlay.gd` | 暖羊皮纸手账风设置浮层 UI：基于 `UIThemeKit` 与 `UIMotion` 构建 3 大页签、自定义 `JellyToggle` 果冻开关、程序抗锯齿海雾蓝滑块与静音按钮、测试提示音与实时状态反馈、阻尼微动效 | 1230 |
| `scenes/ui/settings/settings_preview.tscn` | 独立可运行的设置浮层预览沙盒场景根节点 | 12 |
| `scenes/ui/settings/settings_preview.gd` | 预览沙盒控制器：纯程序绘制暖昏暗书桌星盘底图、独立装配 `SettingsManager` 与 `AudioBusManager`、无须修改 `project.godot` 即可实机预览交互 | 151 |
| `tools/verify_settings_audio/test_settings_audio.gd` | Godot 4.7.2 无头自动化测试脚本（16 项全覆盖用例：持久化、非法回退、3 档画质、5 轨建轨与 dB 静音、BGM Crossfade/Muffle、SFX 池、Voice Ducking、空资源保护、UI 预览全流程） | 530 |
| `tools/verify_settings_audio/capture_preview.gd` | 实机 GPU 渲染截帧脚本，自动截取 3 个页签 16:9 预览图 | 64 |
| `tools/verify_settings_audio/settings_preview_graphics.png` | 实机预览截图：「画面与性能」页签（1280×720） | — |
| `tools/verify_settings_audio/settings_preview_audio.png` | 实机预览截图：「声音与配音」页签（1280×720，含测试铃声实时反馈） | — |
| `tools/verify_settings_audio/settings_preview_reading.png` | 实机预览截图：「阅读与演出」页签（1280×720） | — |
| `docs/handoff/report_track4_settings_audio.md` | 本总控交接报告 | — |

---

## 3. 对外公共 API 与信号契约

### 3.1 `SettingsManager`（`res://core/settings_manager.gd`，无 `class_name`，注册 Autoload 零冲突）

#### Signals
| 信号签名 | 触发时机 |
| :--- | :--- |
| `settings_changed(section: String, key: String, value: Variant)` | 任意单项设置变更时触发（`section` ∈ `"graphics" / "reading" / "audio"`） |
| `graphics_preset_changed(preset: String, profile: Dictionary)` | 画质档位变更时触发，携带对应档位完整渲染建议字典 |
| `settings_loaded()` | `load_settings()` 执行完毕时触发 |
| `settings_saved(path: String)` | `save_settings()` 写入成功时触发 |
| `settings_reset()` | `reset_to_defaults()` 完成重置时触发 |

#### 公共方法签名
```gdscript
func set_config_path(path: String) -> void
func get_config_path() -> String
func is_mobile_platform() -> bool
func load_settings(path: String = "") -> Error
func save_settings(path: String = "") -> Error
func get_setting(section: String, key: String, fallback: Variant = null) -> Variant
func set_setting(section: String, key: String, value: Variant, auto_save: bool = false) -> bool
func get_section(section: String) -> Dictionary
func get_all_settings() -> Dictionary
func get_defaults() -> Dictionary
func get_graphics_profile(preset: String = "") -> Dictionary
func get_graphics_preset() -> String
func set_graphics_preset(preset: String, auto_save: bool = false) -> bool
func get_display_mode() -> String
func is_vsync_enabled() -> bool
func is_map_weather_particles_enabled() -> bool
func get_text_speed() -> float
func get_text_speed_chars_per_sec() -> float
func is_instant_text_enabled() -> bool
func get_auto_play_delay() -> float
func get_dice_animation_speed() -> String
func get_dice_time_scale() -> float
func get_bus_volume(bus_name: StringName) -> float
func set_bus_volume(bus_name: StringName, linear_volume: float, auto_save: bool = false) -> bool
func apply_audio_settings(audio_mgr: Node = null) -> void
func apply_display_settings() -> void
func apply_graphics_to_viewport(viewport: Viewport = null) -> void
func apply_all(audio_mgr: Node = null) -> void
func reset_to_defaults(auto_save: bool = true) -> void
```

#### `get_graphics_profile(preset)` 返回字典结构
| 键名 | 类型 | `"collector"`（典藏） | `"balanced"`（均衡） | `"battery"`（省电） |
| :--- | :--- | :---: | :---: | :---: |
| `preset` | `String` | `"collector"` | `"balanced"` | `"battery"` |
| `label` | `String` | `"典藏"` | `"均衡"` | `"省电"` |
| `subtitle` | `String` | `"满血画质 · 精细光影与全量动态粒子"` | `"流畅与质感兼顾 · 推荐日常畅玩"` | `"移动端护航 · 低温顺滑长续航"` |
| `msaa_3d` / `msaa_2d` | `int` (`Viewport.MSAA`) | `Viewport.MSAA_4X` (`2`) | `Viewport.MSAA_2X` (`1`) | `Viewport.MSAA_DISABLED` (`0`) |
| `shadow_atlas_scale` | `float` | `1.0` | `0.75` | `0.5` |
| `directional_shadow_size` | `int` | `4096` | `2048` | `1024` |
| `soft_shadow_quality` | `int` | `3` | `2` | `1` |
| `ssao_enabled` | `bool` | `true` | `true` | `false` |
| `ssil_enabled` | `bool` | `true` | `false` | `false` |
| `glow_enabled` | `bool` | `true` | `true` | `false` |
| `weather_particle_scale` | `float` | `1.0` | `0.65` | `0.25` |
| `render_scale` | `float` | `1.0` | `1.0` | `0.85` |
| `max_fps` | `int` | `0`（不限） | `60` | `45` |

---

### 3.2 `AudioBusManager`（`res://resources/audio/audio_bus_manager.gd`，无 `class_name`，注册 Autoload 零冲突）

#### Signals
| 信号签名 | 触发时机 |
| :--- | :--- |
| `voice_started(character_id: String, stream: AudioStream)` | 角色语音开始播放且自动触发 BGM Ducking 时触发 |
| `voice_finished(character_id: String)` | 角色语音自然播完或被 `stop_voice()` / 下一句中断结束时触发 |
| `bgm_changed(stream: AudioStream)` | BGM 切换新曲或停止（传 `null`）时触发 |
| `ambience_changed(stream: AudioStream)` | 环境音切换或停止（传 `null`）时触发 |
| `bus_volume_changed(bus_name: StringName, linear_volume: float)` | 任意音轨线性音量更新时触发 |

#### 公共方法签名
```gdscript
static func linear_volume_to_db(linear_volume: float) -> float
func ensure_bus_layout(load_resource: bool = true) -> bool
func set_bus_volume(bus_name: StringName, linear_volume: float) -> void
func get_bus_volume(bus_name: StringName) -> float
func set_bus_muted(bus_name: StringName, muted: bool) -> void
func is_bus_muted(bus_name: StringName) -> bool
func get_bus_volume_db(bus_name: StringName) -> float
func has_all_required_buses() -> bool
func get_bgm_lowpass_effect_index() -> int
func play_bgm(stream: AudioStream, fade_sec: float = 1.2) -> bool
func stop_bgm(fade_sec: float = 0.8) -> void
func get_current_bgm() -> AudioStream
func is_bgm_playing() -> bool
func get_active_bgm_slot() -> int
func set_bgm_muffled(muffled: bool, duration_sec: float = 0.25) -> void
func is_bgm_muffled() -> bool
func play_ambience(stream: AudioStream, fade_sec: float = 1.0) -> bool
func stop_ambience(fade_sec: float = 0.8) -> void
func get_current_ambience() -> AudioStream
func is_ambience_playing() -> bool
func play_sfx(stream: AudioStream, pitch_jitter: float = 0.04, volume_db: float = 0.0) -> bool
func get_sfx_pool_size() -> int
func play_voice(stream: AudioStream, character_id: String = "") -> bool
func stop_voice() -> void
func is_voice_playing() -> bool
func get_active_voice_character() -> String
func is_bgm_ducked() -> bool
func get_bgm_duck_db() -> float
func load_stream_safe(resource_path: String) -> AudioStream
func create_test_chime_stream() -> AudioStreamWAV
func play_test_chime(bus_name: StringName = &"SFX") -> bool
```

---

### 3.3 `SettingsOverlay`（`res://scenes/ui/settings/settings_overlay.tscn` + `settings_overlay.gd`）

#### Signals
| 信号签名 | 触发时机 |
| :--- | :--- |
| `opened()` | 设置浮层打开动画开始时触发 |
| `closed()` | 设置浮层完全隐藏时触发 |
| `settings_saved()` | 点击「保存并关闭」落盘成功时触发 |
| `test_chime_played()` | 点击「测试提示音」按钮时触发 |

#### 公共方法签名
```gdscript
func configure(settings_mgr: Node, audio_mgr: Node = null) -> void
func get_settings_manager() -> Node
func get_audio_manager() -> Node
func is_open() -> bool
func get_active_tab() -> String
func open(initial_tab: String = "") -> void
func close(animated: bool = true) -> void
func select_tab(tab_id: String, animated: bool = true) -> void
func refresh_from_settings() -> void
func play_test_chime() -> bool
```

---

## 4. 后续总装接入指引（精确到行）

### 4.1 `project.godot` 合拢片段（推荐追加位置：第 18 行 `JournalUI` 之后）
> **推荐方案（零破坏共存）**：保留现有 `AudioManager="*res://core/audio_manager.gd"` 供 65 处合成短音效调用，同时注册 `AudioBusManager` 与 `SettingsManager`（**注意顺序：`AudioBusManager` 在 `SettingsManager` 之前**，确保启动时先加载 5 轨 `game_bus_layout.tres`，再由 `SettingsManager._ready()` 读取 `user://settings.cfg` 自动恢复五轨音量）。

```ini
; 插入到 project.godot 的 [autoload] 区块末尾（现有第 18 行 JournalUI 之后）
AudioBusManager="*res://resources/audio/audio_bus_manager.gd"
SettingsManager="*res://core/settings_manager.gd"
```

可选在 `[audio]` 区块指定默认总线布局资源：
```ini
[audio]

buses/default_bus_layout="res://resources/audio/game_bus_layout.tres"
```

### 4.2 标题页 / 暂停菜单 / 大地图打开设置面板（3~5 行示例）
```gdscript
const SettingsOverlayScene := preload("res://scenes/ui/settings/settings_overlay.tscn")
var _settings_overlay: CanvasLayer = SettingsOverlayScene.instantiate() as CanvasLayer
add_child(_settings_overlay)
_settings_overlay.configure(SettingsManager, AudioBusManager)
_settings_overlay.open("graphics")  # 支持 "graphics" / "audio" / "reading"
```

### 4.3 大地图 3D 沙盘订阅画质档位与天气开关（5 行示例）
```gdscript
SettingsManager.graphics_preset_changed.connect(func(_preset: String, profile: Dictionary) -> void:
	SettingsManager.apply_graphics_to_viewport(get_viewport())
	world_env.environment.ssao_enabled = bool(profile["ssao_enabled"])
	world_env.environment.ssil_enabled = bool(profile["ssil_enabled"])
	weather_stage.set_particle_density_scale(float(profile["weather_particle_scale"])))
```
并可单独监听天气开关：
```gdscript
SettingsManager.settings_changed.connect(func(section: String, key: String, value: Variant) -> void:
	if section == "graphics" and key == "map_weather_particles":
		weather_stage.visible = bool(value))
```

### 4.4 对话页与 3D 骰子接入阅读速度与未来配音（5 行示例）
```gdscript
# 对话逐字速度与自动停顿
var chars_per_sec: float = SettingsManager.get_text_speed_chars_per_sec()
var instant_mode: bool = SettingsManager.is_instant_text_enabled()
var auto_wait_sec: float = SettingsManager.get_auto_play_delay()
# 播放角色语音（若资源尚未录制返回 null 时静默跳过，录制后自动触发 BGM Ducking）
AudioBusManager.play_voice(AudioBusManager.load_stream_safe(voice_path), speaker_id)
```
3D 骰子演出速度：
```gdscript
var dice_speed_scale: float = SettingsManager.get_dice_time_scale()  # "normal" -> 1.0, "fast" -> 1.8
```

---

## 5. 实机验证与无头测试结果

### 5.1 无头回归测试（`test_settings_audio.gd`）
执行命令：
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --audio-driver Dummy --path "/Users/mac/Documents/all project/无职转生" --script res://tools/verify_settings_audio/test_settings_audio.gd
```

- **总计**：**`16/16 PASS`（0 FAIL）**
- **Godot 4.7.2 运行期报错数**：**`0`**
- **Godot 4.7.2 运行期告警 / 内存泄漏数**：**`0`**

| 用例编号 | 验证范围 | 结果 |
| :--- | :--- | :---: |
| `T01_defaults_complete` | 全部 12 项默认配置键值校验 | PASS |
| `T02_config_roundtrip` | `ConfigFile` 全量写入与跨实例重载往返一致 | PASS |
| `T03_illegal_values_fallback` | 非法枚举、错误类型、越界数值、`NaN` 安全回退默认值，合法值保留 | PASS |
| `T04_corrupt_cfg_graceful` | 语法损坏的配置文件安全拦截不报错且保持默认配置 | PASS |
| `T05_reset_to_defaults` | `reset_to_defaults(true)` 恢复全量默认并触发 `settings_reset` / `settings_changed` | PASS |
| `T06_runtime_set_validation` | 运行期未知键/非法枚举/`NaN` 拒绝，合法数值边界平滑钳位 | PASS |
| `T07_graphics_profiles_valid` | `collector > balanced > battery` 三档 Profile 字段完整与非法档位回退 | PASS |
| `T08_graphics_preset_signal` | 切档精确触发 `graphics_preset_changed` 且重复设置不抖动重发 | PASS |
| `T09_bus_layout_resource_load` | `game_bus_layout.tres` 正确载入 5 条音轨 + `BGM` 低通滤镜（默认禁用） | PASS |
| `T10_bus_fallback_auto_create` | 空白单轨布局下自动兜底建全 `BGM / Ambience / SFX / Voice` 与低通滤镜 | PASS |
| `T11_volume_db_and_settings_sync` | 线性音量至 dB 映射、`0.0` 彻底静音及 `SettingsManager.apply_audio_settings()` 五轨同步 | PASS |
| `T12_bgm_crossfade_and_muffle` | BGM 双通道无缝 Crossfade、弹窗低通柔化开关与平滑停止 | PASS |
| `T13_ambience_and_sfx_pool` | Ambience 双通道平滑切换、6 槽 SFX 对象池 8 连发与程序测试铃音 | PASS |
| `T14_voice_ducking_lifecycle` | Voice 播放触发 `voice_started` 与 BGM 自动压低（`-6.50 dB`），停止后触发 `voice_finished` 并平滑回升至 `0.00 dB` | PASS |
| `T15_null_and_missing_safe` | `null` 流与不存在音频路径全部静默跳过，零报错且不误触发 Ducking | PASS |
| `T16_settings_preview_and_ui_flow` | `settings_preview.tscn` 实例化、3 页签切换、移动端隐藏显示模式、测试提示音、关闭闭环 | PASS |

### 5.2 实机渲染预览截图（Metal 4.0 Forward+，0 Error / 0 Warning）
- 画面与性能页签：`tools/verify_settings_audio/settings_preview_graphics.png`（1280×720）
- 声音与配音页签：`tools/verify_settings_audio/settings_preview_audio.png`（1280×720，五轨全部一屏完整展示无须滚动，含测试铃声实时 dB 反馈）
- 阅读与演出页签：`tools/verify_settings_audio/settings_preview_reading.png`（1280×720）

---

## 6. 遗留事项与后续扩展建议

1. **与既有 `core/audio_manager.gd` 的统一策略**：
   - 合拢阶段可直接双 Autoload 并存（`AudioManager` 继续承担既有程序化 UI 合成短音效，全部走 `SFX` 轨自动受本模块五轨音量调控；`AudioBusManager` 承担流式 `AudioStream` 的 BGM/Ambience/Voice/SFX 资源播放），也可在后续重构时为 `core/audio_manager.gd` 增加代理或逐步迁移既有 `play_bgm(path)` / `play_voice(path)` 至 `AudioBusManager`。
2. **大地图 & 对话页实质挂接**：
   - 需在总装阶段将 `world_atlas_view.gd`、`world_weather_stage.gd`、`dialogue_view.gd`、`dice_roll_overlay.gd` 与 `title_screen.gd` 接入第 4 节所示的 3~5 行订阅与弹窗按钮（本轨道因零冲突红线未修改上述文件）。
3. **Android 真机实测与语言/无障碍预留**：
   - 本模块已按 `AGENTS.md` 三端触控红线保证全部可点控件高度 `≥ 44px`（主流按钮 `46~48px`）、间距 `≥ 10px`，并在 `is_mobile_platform()` 为 `true` 时自动隐藏「显示模式」；后续可在 `SettingsManager` 中平滑扩展字幕字号倍率、BGM 曲目预览或语音语言包切换键，无需变更 `user://settings.cfg` 既有区块结构。
