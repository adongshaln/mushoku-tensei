# 魔大陆全洲三块精雕交接

## 区块与坐标

| 区块 | 世界 X 边界 | 世界 Z 边界 | 网格单元 | 三角面 | GLB |
| --- | --- | --- | --- | ---: | ---: |
| `chunk_demon_ne` | 4.828621 至 7.855517 | −4.705000 至 −2.281212 | 168 × 170 | 57,120 | 1.21 MiB |
| `chunk_demon_nw` | 2.234138 至 4.828621 | −4.705000 至 −2.281212 | 144 × 170 | 48,960 | 1.04 MiB |
| `chunk_demon_south` | 2.234138 至 7.855517 | −2.281212 至 0.641591 | 312 × 82 | 51,168 | 1.09 MiB |

三区合计 157,248 三角面。每块独立输出 Albedo、切线法线、AO、Roughness 四张 4096 × 4096 PNG。三块共用东北角的暖赤陶色板，西北寒海边缘局部降低饱和度，温恩港湾以浅台阶和礁岬收束。粗糙度在量化写入和 Godot 采样两端均限制为 0.76–0.94。

| 城池 | 城池 ID | 运行时 XZ |
| --- | --- | --- |
| 米格路德村 | `city_migurd` | (6.71, −3.795) |
| 利卡里斯镇 | `city_rikarisu` | (6.02, −3.295) |
| 克拉斯玛镇 | `city_kurasuma` | (3.36, −3.435) |
| 温恩港 | `city_wind_port` | (5.80, −0.215) |

城池源点及航线拓扑来自原地图与路线配置。像素坐标减 `(836, 470.5)` 后乘 `0.01` 转世界 XZ。既有构图偏移在区块清单记录，Godot 实机与原城池 XZ 对照通过。城池 Y 由各自精雕台基重新求得。

## 拼接、场景与航线

- Blender 用同一个世界坐标高度函数生成三区。相邻边使用相同的采样站点，PBR 的坡度和 AO 在边缘读取邻块三角形。只有大陆外缘与宏观地板对齐。Godot 导入关闭逐块 LOD 简化和顶点压缩，底板着色器按已注册覆盖面剔除原网格。
- 注册表在舆图打开时挂载 `demon` 组。缺块时整组回落到旧底板，避免精雕内部接缝暴露。运行时海面统一读取已加载的深度层。近看东北角时，方向光阴影柔和度系数乘 0.8，海岸泡沫只加微量自发光。
- 每个场景都有 `TerrainRoot`、`AssetsRoot`、`AtmosphereRoot`。地表碰撞与贴地采样共用同一网格。`CustomProps.snap_node_to_terrain(node, world_xz, y_offset, align_normal_strength)` 在碰撞可用时采用射线高度与法线，初始化时可用同一三角形解析采样。
- 英雄模型优先查找 `heroes/hero_<city_id>.glb`，现有两件东北角英雄资产有路径别名。克拉斯玛与温恩港继续使用旧建筑，实例化时裁除厚底盘三角形，保留港墙、栈台和灯塔。
- 四条陆路均采样两侧和中心，纵向间隔最多 0.0045 世界单位，基础净空 0.018。起止点在建筑占地之外，端部收窄并淡出。行进时激活的航线接管底图对应段。东北角移除外挂红岩，保留三丛绿矿晶。

## 跨洲扩展模板

1. 按原彩图和已有世界坐标确定完整海岸范围。给新区块登记 `id`、`scene`、`terrain`、`pbr_prefix`、`bounds`、`grid_cells`、`terrain_group`、`cities`。同组的内部共享边采用同一组世界采样站点，边缘材质同样跨块取样。
2. 复用 `world_chunk.gd` 及最小根节点场景。依赖连续几何的地形组加入 `atomic_terrain_groups`。港口需隐藏现有厚底盘时启用 `hide_legacy_plinth`。在 `detailed_roads` 逐条登记原始城市 ID，只有需要微调演出时才提供世界坐标 `via`。
3. 复用 `build_demon_continent_chunks.py` 的网格出口、共用采样和烘焙，替换该洲独立的海岸识别、地形剖面和色板。批量重建本次魔大陆可运行以下命令。

```sh
blender --background --python-exit-code 1 --python tools/blender_world_v2/build_demon_continent_chunks.py -- --size 4096
godot --headless --editor --import --rendering-method forward_plus --path "$isolated_atlas"
godot --path "$isolated_atlas" --rendering-method forward_plus --resolution 1920x1080 res://tools/blender_world_v2/verify_demon_continent_chunks.tscn -- "$atlas_capture_dir"
```

## 48° 实机截图

取景使用游戏舆图视口，棋子停在路侧以便检查贴地金线。

- [东北角复验](../../tools/blender_world_v2/previews/demon_continent_ne.png)
- [西北断崖与克拉斯玛](../../tools/blender_world_v2/previews/demon_continent_nw.png)
- [温恩港湾傍晚](../../tools/blender_world_v2/previews/demon_continent_south.png)
- [魔大陆全洲合拢](../../tools/blender_world_v2/previews/demon_continent_overview.png)

## 验收结果

Godot 4.7.2 Forward+ 在 Apple M4、Metal 4.0 下完成无头导入、实机验证和缺块回落。日志统一为 0 Error / 0 Warning / 0 Shader 告警。Blender 校验覆盖 123,435 个有效陆地像素。

| 48° 视口 | 1920 × 1080 实机 FPS |
| --- | ---: |
| 东北角修订 | 26.5 |
| 西北上午 | 33.4 |
| 温恩港傍晚 | 26.7 |
| 全洲 | 35.0 |

帧率按预热后连续 32 帧实测。三条拼缝各抽查 130 点，最大高差为 0.00000135 世界单位。三区 `CustomProps` 动态测试锚点的最大射线高度误差为 0.00000047。四条金线的顶点净空实测为 0.017898–0.018115，陆行与海运高度均通过。测试西北 GLB 缺失时整组回落，两座东北城池仍可选择。

本次锁定目录写入数为 0。
