# 魔大陆东北角区块交接

## 坐标与资产

| 项目 | 参数 |
| --- | --- |
| 区块 ID | `chunk_demon_ne` |
| 世界坐标边界 XZ | X `[4.82862069, 7.85551724]`，Z `[-4.70500000, -2.28121212]` |
| 世界坐标换算 | `X = (pixel_x - 836) × 0.01`，`Z = (pixel_y - 470.5) × 0.01`，Y 向上 |
| 米格路德村 | `city_migurd`，运行时 XZ `(6.71, -3.795)` |
| 利卡里斯镇 | `city_rikarisu`，运行时 XZ `(6.02, -3.295)` |
| 地形 | `168 × 170` 个网格单元，57,120 三角面，1.21 MiB |
| PBR | Albedo、切线法线、AO、Roughness 各 `4096 × 4096`，粗糙度限于 `0.76–0.94` |
| 西南衔接 | `0.69` 单位渐变带，外围边沿落在原底板网格线上 |
| 舞台 | 默认镜头 48°，跟随 49°，上午侧光 36°，傍晚侧光 30° |

地图数据提供城池原始像素，现有 `world_relief_meta.json` 还保存了此前确定的最终落位偏移。本次从两份数据校验两城实际 XZ，只由精雕地形重新求 Y。领地 ID 使用既有世界 UV 和拾取数据。

海岸提取自原始着色图。区块内部高度由沉积台阶、侵蚀沟壑、高地台面、半围合盆地与商道剖面构成。仅外圈渐变带读取宏观 GLB 的三角面高度。Albedo 从村落、城镇与岩崖采样，结合地形高程、坡度和腔体遮蔽离线烘焙。法线单独编码岩层、裂缝和细颗粒。

## 装配与贴地契约

- `world_chunks_manifest.json` 声明各区块场景、GLB、四张纹理的共同前缀、世界矩形、网格单元数、城池、路线导引点和陈设。注册表支持最多 12 个互不重叠的区块。关闭条目或缺少资源时，舆图重新打开即使用宏观底板。`chunk_demon_nw` 与 `chunk_demon_south` 已预留。
- `TerrainRoot` 承载精雕网格与静态碰撞体。底板着色器剔除已注册覆盖面，区块内混用同一世界 UV 维持边缘过渡与选择高亮。海洋继续由一张连续网格绘制，采样区块深度层，使泡沫沿真实崖脚分布。
- `AssetsRoot` 承载两城原英雄模型与 `CustomProps`。样板区只有 3 块半埋点缀岩与 3 丛微光矿晶，旧枯木散布退到区块外。盆地微雾、道路展示线和按时段亮起的暖灯由 `AtmosphereRoot` 管理。
- `CustomProps.snap_node_to_terrain(node, world_xz, y_offset, align_normal_strength) -> bool` 接收 Godot 世界 XZ。成功时把节点收进 `CustomProps` 并返回 `true`，越界返回 `false`。偏移沿世界 Y，法线权重取 `0–1`。输入节点已有朝向和缩放会随法线对齐保留。贴地数学使用与静态碰撞体一致的三角形对角线与插值。
- 航线使用清单里的区块世界坐标导引点，从模型包围盒外缘起止。近景金线的两侧分别重采样，净空 `0.005` 单位。陆地棋子使用同一高度采样，船只沿原海平面。

## 下一区块的复刻命令

1. 从母图确定新区域海岸与世界范围，让边界落在宏观 GLB 的网格线上。复制首块构建脚本，换成新区块 ID 与地形剖面，并在清单中登记对应资源与场景。
2. 用以下命令重建首块。预制阶段可传 `--size 2048`，交付默认 4K。

   ```sh
   blender --background --python-exit-code 1 --python tools/blender_world_v2/build_chunk_demon_ne.py -- --size 4096
   ```

3. 在隔离工程副本中导入、校验并截取实机图。

   ```sh
   godot --headless --editor --import --rendering-method forward_plus --path "$isolated_atlas"
   godot --path "$isolated_atlas" --rendering-method forward_plus --resolution 1920x1080 res://tools/blender_world_v2/verify_chunk_demon_ne.tscn -- "$atlas_capture_dir"
   ```

## 验收

本机 Apple M4 使用 Godot 4.7.2 Forward+、Metal 4.0。在隔离工程完成无头导入、实机渲染和旧版样板 `slot_6` 副本加载。缺少地形资源时回落到底板，两城仍可选。静态射线与贴地采样的抽查最大差值为 `0.00003168`，西缘与旧底板三角面的抽查最大差值为 `0.00003642`。动态测试锚点的指定偏移及法线对齐通过，陆海路线、棋子落位、航线避开建筑和旧存档恢复通过。

无头导入、Forward+ 实机和回落测试的日志均为 0 Error / 0 Warning / 0 Shader 编译告警。1920 × 1080 视口连续计时 32 帧，上午 28.7 FPS、傍晚 28.9 FPS、中景 37.2 FPS。近景采图时诺缇雅停在路肩，让两城之间的短程金线可见。

本次写入局限于区块场景、对应的大地图渲染与工具路径和本报告。工作树内已有其他轨道的并行改动。

### 验收图

- [Blender 白模与 4K 彩模](../../tools/blender_world_v2/previews/chunk_demon_ne_blender_preview.png)
- [Godot 48° 上午](../../tools/blender_world_v2/previews/chunk_demon_ne_morning.png)
- [Godot 48° 傍晚](../../tools/blender_world_v2/previews/chunk_demon_ne_dusk.png)
- [Godot 中景与西南过渡](../../tools/blender_world_v2/previews/chunk_demon_ne_midrange.png)
