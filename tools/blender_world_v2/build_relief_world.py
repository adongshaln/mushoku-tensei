"""Build the Flagship M1 3D Relief World Diorama, 2048x1024 control maps, metadata, and previews.

Run from repository root:
    blender --background --python tools/blender_world_v2/build_relief_world.py
"""

import json
import math
from pathlib import Path
import struct
import sys
import zlib

import bpy
from mathutils import Vector
import numpy as np


sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import build_world_map_blender as legacy_map  # Reuse exact canon coastline & 15-region partition logic.

SOURCE_PNG = ROOT / "assets/maps/world_map_colored.png"
MAP_DATA_JSON = ROOT / "data/maps/world_map_data.json"
ROUTES_JSON = ROOT / "data/maps/world_routes.json"

OUT_GLB = ROOT / "assets/3d/world_v2/world_relief_world.glb"
OUT_TEX_DIR = ROOT / "assets/textures/world_v2"
OUT_META_JSON = ROOT / "data/maps/world_relief_meta.json"
OUT_PREVIEW_DIR = ROOT / "tools/blender_world_v2/previews"

REF_W, REF_H = 1672, 941
PIXEL_UNIT = 0.01
MIN_X, MAX_X = -REF_W * 0.5 * PIXEL_UNIT, REF_W * 0.5 * PIXEL_UNIT   # -8.36 .. +8.36
MIN_Z, MAX_Z = -REF_H * 0.5 * PIXEL_UNIT, REF_H * 0.5 * PIXEL_UNIT   # -4.705 .. +4.705
WORLD_W = MAX_X - MIN_X
WORLD_D = MAX_Z - MIN_Z

TEX_W, TEX_H = 2048, 1024
GRID_X, GRID_Z = 232, 132  # 61,248 tris for TerrainSurface
OCEAN_X, OCEAN_Z = 48, 28  # 2,688 tris for OceanPlane
SEA_LEVEL = 0.0


# ---------------------------------------------------------------------------
# Pure-Python Lossless PNG Writers (Zero Color-Management Drift)
# ---------------------------------------------------------------------------
def _png_chunk(tag: bytes, payload: bytes) -> bytes:
    crc = zlib.crc32(tag + payload) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", crc)


def write_png_u16_gray(path: Path, arr_u16: np.ndarray) -> None:
    """Write an exact 16-bit big-endian grayscale PNG (H, W)."""
    h, w = arr_u16.shape
    be = np.ascontiguousarray(arr_u16, dtype=">u2")
    raw_rows = np.concatenate([np.zeros((h, 1), dtype=np.uint8), be.view(np.uint8).reshape(h, w * 2)], axis=1)
    ihdr = struct.pack(">IIBBBBB", w, h, 16, 0, 0, 0, 0)
    data = b"\x89PNG\r\n\x1a\n" + _png_chunk(b"IHDR", ihdr) + _png_chunk(b"IDAT", zlib.compress(raw_rows.tobytes(), 6)) + _png_chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def write_png_rgba8(path: Path, arr_u8: np.ndarray) -> None:
    """Write an exact 8-bit RGBA PNG (H, W, 4)."""
    h, w, c = arr_u8.shape
    assert c == 4
    arr = np.ascontiguousarray(arr_u8, dtype=np.uint8).reshape(h, w * 4)
    raw_rows = np.concatenate([np.zeros((h, 1), dtype=np.uint8), arr], axis=1)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    data = b"\x89PNG\r\n\x1a\n" + _png_chunk(b"IHDR", ihdr) + _png_chunk(b"IDAT", zlib.compress(raw_rows.tobytes(), 6)) + _png_chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


# ---------------------------------------------------------------------------
# Fast Vectorized NumPy Image / Field Utilities
# ---------------------------------------------------------------------------
def resample_bilinear(arr: np.ndarray, out_h: int, out_w: int) -> np.ndarray:
    in_h, in_w = arr.shape[:2]
    ys = (np.arange(out_h, dtype=np.float32) + 0.5) * (in_h / out_h) - 0.5
    xs = (np.arange(out_w, dtype=np.float32) + 0.5) * (in_w / out_w) - 0.5
    ys = np.clip(ys, 0.0, in_h - 1.0001)
    xs = np.clip(xs, 0.0, in_w - 1.0001)
    y0 = ys.astype(np.int32)
    x0 = xs.astype(np.int32)
    y1 = np.minimum(y0 + 1, in_h - 1)
    x1 = np.minimum(x0 + 1, in_w - 1)
    wy = (ys - y0)[:, None]
    wx = (xs - x0)[None, :]
    if arr.ndim == 3:
        wy = wy[:, :, None]
        wx = wx[:, :, None]
    a = arr[y0[:, None], x0[None, :]]
    b = arr[y0[:, None], x1[None, :]]
    c = arr[y1[:, None], x0[None, :]]
    d = arr[y1[:, None], x1[None, :]]
    return (a * (1.0 - wx) + b * wx) * (1.0 - wy) + (c * (1.0 - wx) + d * wx) * wy


def resample_nearest(arr: np.ndarray, out_h: int, out_w: int) -> np.ndarray:
    in_h, in_w = arr.shape[:2]
    ys = np.clip(((np.arange(out_h, dtype=np.float32) + 0.5) * (in_h / out_h)).astype(np.int32), 0, in_h - 1)
    xs = np.clip(((np.arange(out_w, dtype=np.float32) + 0.5) * (in_w / out_w)).astype(np.int32), 0, in_w - 1)
    return arr[ys[:, None], xs[None, :]]


def gaussian_blur(arr: np.ndarray, sigma: float) -> np.ndarray:
    if sigma <= 0.15:
        return arr.copy()
    radius = max(1, int(math.ceil(sigma * 2.6)))
    k = np.arange(-radius, radius + 1, dtype=np.float32)
    kernel = np.exp(-0.5 * (k / sigma) ** 2)
    kernel /= kernel.sum()
    # Horizontal pass
    pad_x = np.pad(arr, ((0, 0), (radius, radius)), mode="edge")
    tmp = np.zeros_like(arr, dtype=np.float32)
    for i, w in enumerate(kernel):
        tmp += w * pad_x[:, i:i + arr.shape[1]]
    # Vertical pass
    pad_y = np.pad(tmp, ((radius, radius), (0, 0)), mode="edge")
    out = np.zeros_like(arr, dtype=np.float32)
    for i, w in enumerate(kernel):
        out += w * pad_y[i:i + arr.shape[0], :]
    return out


def signed_distance_approx(mask_bool: np.ndarray) -> np.ndarray:
    """Fast smooth signed distance in source-map pixel units (positive inland, negative offshore)."""
    h, w = mask_bool.shape
    # Downsample 4x for rapid exact-ish Chamfer propagation, then combine with high-res coastal bevel.
    sh, sw = h // 4, w // 4
    small = resample_bilinear(mask_bool.astype(np.float32), sh, sw) >= 0.5

    def chamfer(binary: np.ndarray) -> np.ndarray:
        dist = np.where(binary, 1e6, 0.0).astype(np.float32)
        for _ in range(2):
            for y in range(1, sh):
                dist[y] = np.minimum(dist[y], dist[y - 1] + 1.0)
                dist[y, 1:] = np.minimum(dist[y, 1:], dist[y - 1, :-1] + 1.4142)
                dist[y, :-1] = np.minimum(dist[y, :-1], dist[y - 1, 1:] + 1.4142)
            for y in range(sh - 2, -1, -1):
                dist[y] = np.minimum(dist[y], dist[y + 1] + 1.0)
                dist[y, 1:] = np.minimum(dist[y, 1:], dist[y + 1, :-1] + 1.4142)
                dist[y, :-1] = np.minimum(dist[y, :-1], dist[y + 1, 1:] + 1.4142)
            for x in range(1, sw):
                dist[:, x] = np.minimum(dist[:, x], dist[:, x - 1] + 1.0)
            for x in range(sw - 2, -1, -1):
                dist[:, x] = np.minimum(dist[:, x], dist[:, x + 1] + 1.0)
        return dist

    d_in = chamfer(small) * (REF_W / sw)
    d_out = chamfer(~small) * (REF_W / sw)
    coarse_sdf = resample_bilinear(d_in - d_out, h, w)
    # High-frequency crisp coastal transition blended near zero-crossing.
    fine_mask = gaussian_blur(mask_bool.astype(np.float32), 2.2)
    fine_sdf = (fine_mask - 0.5) * 14.0
    near_coast = np.exp(-(coarse_sdf / 10.0) ** 2)
    return coarse_sdf * (1.0 - 0.65 * near_coast) + fine_sdf * (0.65 * near_coast)


def value_noise_2d(gx: np.ndarray, gy: np.ndarray, freq_x: int, freq_y: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    grid = rng.uniform(-1.0, 1.0, (freq_y + 2, freq_x + 2)).astype(np.float32)
    fx = gx * freq_x
    fy = gy * freq_y
    ix = np.clip(np.floor(fx).astype(np.int32), 0, freq_x)
    iy = np.clip(np.floor(fy).astype(np.int32), 0, freq_y)
    tx = fx - ix
    ty = fy - iy
    # Quintic smoothstep
    sx = tx * tx * tx * (tx * (tx * 6.0 - 15.0) + 10.0)
    sy = ty * ty * ty * (ty * (ty * 6.0 - 15.0) + 10.0)
    a = grid[iy, ix]
    b = grid[iy, ix + 1]
    c = grid[iy + 1, ix]
    d = grid[iy + 1, ix + 1]
    return (a * (1.0 - sx) + b * sx) * (1.0 - sy) + (c * (1.0 - sx) + d * sx) * sy


def fbm_2d(u: np.ndarray, v: np.ndarray, base_x: int, base_y: int, octaves: int, seed: int) -> np.ndarray:
    total = np.zeros_like(u, dtype=np.float32)
    amp = 0.5
    norm = 0.0
    for i in range(octaves):
        total += amp * value_noise_2d(u, v, base_x * (1 << i), base_y * (1 << i), seed + i * 97)
        norm += amp
        amp *= 0.5
    return total / max(norm, 1e-6)


def ridge_fbm_2d(u: np.ndarray, v: np.ndarray, base_x: int, base_y: int, octaves: int, seed: int) -> np.ndarray:
    total = np.zeros_like(u, dtype=np.float32)
    amp = 0.55
    norm = 0.0
    for i in range(octaves):
        n = 1.0 - np.abs(value_noise_2d(u, v, base_x * (1 << i), base_y * (1 << i), seed + i * 131))
        total += amp * (n * n)
        norm += amp
        amp *= 0.48
    return total / max(norm, 1e-6)


def dist_to_polyline(px: np.ndarray, py: np.ndarray, pts: list[tuple[float, float]]) -> np.ndarray:
    """Minimum Euclidean distance in source-map pixel space to a piecewise-linear polyline."""
    best = np.full(px.shape, 1e9, dtype=np.float32)
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        dx = bx - ax
        dy = by - ay
        l2 = max(dx * dx + dy * dy, 1e-6)
        t = np.clip(((px - ax) * dx + (py - ay) * dy) / l2, 0.0, 1.0)
        qx = ax + t * dx
        qy = ay + t * dy
        d = np.hypot(px - qx, py - qy)
        best = np.minimum(best, d)
    return best


def smoothstep_np(edge0, edge1, x: np.ndarray) -> np.ndarray:
    diff = edge1 - edge0
    if isinstance(diff, np.ndarray):
        safe_diff = np.where(np.abs(diff) < 1e-6, np.where(diff >= 0.0, 1e-6, -1e-6), diff)
    else:
        safe_diff = diff if abs(diff) >= 1e-6 else (1e-6 if diff >= 0.0 else -1e-6)
    t = np.clip((x - edge0) / safe_diff, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# ---------------------------------------------------------------------------
# Landforms, Biome Splats & Region ID Generation (2048 x 1024)
# ---------------------------------------------------------------------------
def build_world_fields(config: dict, routes_cfg: dict):
    img = bpy.data.images.load(str(SOURCE_PNG))
    assert tuple(img.size) == (REF_W, REF_H), f"Unexpected source image size: {img.size}"
    src_rgba = legacy_map.raster_image(img)
    bpy.data.images.remove(img)

    silhouette = legacy_map.outer_mask(src_rgba)
    r, g, b = np.moveaxis(src_rgba[:, :, :3], -1, 0)
    blue = ((g - r > 0.024) & (b - r > -0.018) & (g + b > 0.43)) | ((b - r > 0.034) & (g - r > -0.01))
    blue = ~legacy_map.expand(~legacy_map.expand(blue & silhouette, 2), 2) & silhouette
    water_labels, _ = legacy_map.components(blue)
    probes = ((970, 430), (475, 680), (1162, 44), (1362, 455), (925, 795))
    ocean_ids = {int(water_labels[y, x]) for x, y in probes} - {0}
    ocean_src = np.isin(water_labels, list(ocean_ids)) | ~silhouette
    all_land_src = silhouette & ~ocean_src

    # Playable 3 continents and 15 continuous regions (NO 1px cutout seam!)
    coasts_src = legacy_map.identify_regions(src_rgba, silhouette)
    y_o, x_o = np.ogrid[:REF_H, :REF_W]
    demon_west = x_o < legacy_map.ridge(y_o, ((0, 1316), (63, 1333), (102, 1348), (152, 1374), (207, 1370), (235, 1381)))
    demon_north = y_o < legacy_map.ridge(x_o, ((1110, 207), (1248, 186), (1281, 197), (1330, 221), (1381, 239),
                                               (1422, 221), (1451, 233), (1494, 208), (1545, 213)))
    demon_south = y_o >= legacy_map.ridge(x_o, ((1248, 339), (1299, 361), (1329, 359), (1359, 378),
                                                (1385, 365), (1429, 386), (1459, 369), (1530, 376)))
    milis_north = y_o < legacy_map.ridge(x_o, ((1295, 601), (1352, 584), (1390, 590), (1424, 569), (1509, 579)))
    milis_forest = y_o < legacy_map.ridge(x_o, ((1187, 625), (1267, 650), (1329, 669), (1363, 680),
                                                (1390, 699), (1452, 711), (1520, 738)))
    milis_west = x_o < legacy_map.ridge(y_o, ((710, 1091), (777, 1091), (800, 1130), (825, 1111), (873, 1138), (905, 1138)))
    north = y_o < legacy_map.ridge(x_o, ((120, 129), (213, 141), (272, 137), (316, 161), (366, 155),
                                         (417, 178), (494, 166), (553, 188), (638, 163), (734, 158), (910, 170)))
    north |= (x_o >= 775) & (y_o < 231)
    biheiriru = x_o >= legacy_map.ridge(y_o, ((0, 563), (45, 578), (82, 581), (119, 609), (175, 620)))
    south = y_o > legacy_map.ridge(x_o, ((320, 604), (448, 610), (502, 604), (547, 582), (615, 590), (660, 566), (740, 593)))
    sword = (x_o < legacy_map.ridge(y_o, ((105, 206), (158, 210), (192, 223), (226, 213),
                                          (250, 220), (275, 209), (299, 190), (319, 177)))) & (y_o < 323)
    asura = x_o < legacy_map.ridge(y_o, ((0, 335), (160, 352), (201, 387), (239, 435), (270, 449),
                                         (300, 470), (330, 487), (390, 495), (435, 514), (482, 513), (545, 543), (620, 563)))
    strife = x_o < legacy_map.ridge(y_o, ((158, 715), (206, 657), (252, 632), (309, 623), (362, 638),
                                          (402, 627), (446, 647), (493, 622), (529, 617), (569, 620), (630, 633)))

    cont_region_idx = {
        "demon": np.select([demon_south, demon_north & demon_west, demon_north & ~demon_west], [4, 2, 1], default=3),
        "milis": np.select([milis_north, milis_west, milis_forest], [1, 4, 2], default=3),
        "central": np.select([north & biheiriru, north, south, sword, asura, strife], [4, 1, 7, 2, 3, 5], default=6),
    }

    region_id_src = np.zeros((REF_H, REF_W), dtype=np.uint8)
    cont_id_src = np.zeros((REF_H, REF_W), dtype=np.uint8)
    region_list = []
    continent_index_map = {"demon": 1, "milis": 2, "central": 3}

    next_idx = 1
    for group in config["continents"]:
        cid = group["id"]
        cidx = continent_index_map[cid]
        cmask = coasts_src[cid]
        cont_id_src[cmask] = cidx
        local_idx = cont_region_idx[cid]
        for local_num, reg in enumerate(group["regions"], start=1):
            rmask = cmask & (local_idx == local_num)
            region_id_src[rmask] = next_idx
            region_list.append({
                "index": next_idx,
                "id": reg["id"],
                "name": reg["name"],
                "continent_id": cid,
                "continent_index": cidx,
            })
            next_idx += 1

    # Resample core masks to 2048 x 1024
    region_id_map = resample_nearest(region_id_src, TEX_H, TEX_W)
    cont_id_map = resample_nearest(cont_id_src, TEX_H, TEX_W)
    land_hi = resample_bilinear(all_land_src.astype(np.float32), TEX_H, TEX_W) >= 0.48
    demon_hi = resample_bilinear(coasts_src["demon"].astype(np.float32), TEX_H, TEX_W)
    milis_hi = resample_bilinear(coasts_src["milis"].astype(np.float32), TEX_H, TEX_W)
    central_hi = resample_bilinear(coasts_src["central"].astype(np.float32), TEX_H, TEX_W)
    begaritt_hi = np.clip(land_hi.astype(np.float32) - demon_hi - milis_hi - central_hi, 0.0, 1.0)
    src_rgb_hi = resample_bilinear(src_rgba[:, :, :3].astype(np.float32), TEX_H, TEX_W)

    # Coordinate grids in UV [0..1] and canonical source pixel space [0..1672] x [0..941]
    u_1d = (np.arange(TEX_W, dtype=np.float32) + 0.5) / TEX_W
    v_1d = (np.arange(TEX_H, dtype=np.float32) + 0.5) / TEX_H
    u_grid, v_grid = np.meshgrid(u_1d, v_1d)
    px = u_grid * REF_W
    py = v_grid * REF_H

    # Smooth signed distance from coast (in source pixel units)
    sdf = signed_distance_approx(land_hi)
    inland = smoothstep_np(-1.5, 4.0, sdf)  # 0 ocean -> 1 land

    # 1. Base seabed & gentle coastal rise (low sea cliffs on Demon/North, gentle beaches elsewhere)
    seabed = -0.24 * smoothstep_np(0.0, -34.0, sdf) - 0.055 * smoothstep_np(0.0, -4.5, sdf)
    cliff_bias = np.clip(demon_hi * 0.85 + smoothstep_np(175.0, 95.0, py) * central_hi * 0.75, 0.0, 1.0)
    coastal_rise = (0.115 + 0.038 * cliff_bias) * smoothstep_np(0.0, 13.5 - 5.0 * cliff_bias, sdf)
    continental_lift = 0.058 * smoothstep_np(8.0, 88.0, sdf)

    # 2. Procedural multi-scale relief noise
    n_broad = fbm_2d(u_grid, v_grid, 14, 8, 4, seed=418)
    n_detail = fbm_2d(u_grid, v_grid, 42, 24, 3, seed=777)
    n_ridge = ridge_fbm_2d(u_grid, v_grid, 22, 13, 4, seed=909)
    n_crag = ridge_fbm_2d(u_grid, v_grid, 48, 28, 3, seed=1337)

    # Subtle mountain hint extracted from canon map artwork (dark/warm shaded peaks, smoothed to ignore lines)
    sr, sg, sb = src_rgb_hi[:, :, 0], src_rgb_hi[:, :, 1], src_rgb_hi[:, :, 2]
    luma = 0.299 * sr + 0.587 * sg + 0.114 * sb
    art_mtn = smoothstep_np(0.76, 0.42, gaussian_blur(luma, 5.5)) * smoothstep_np(6.0, 22.0, sdf)

    height = np.where(sdf < 0.0, seabed, coastal_rise + continental_lift)

    # Rolling base terrain by continent
    height += inland * (0.040 * (n_broad * 0.5 + 0.5) + 0.015 * n_detail)
    height += inland * art_mtn * 0.095

    # --- DEMON CONTINENT: Rugged ochre plateau, central rifts, Migurd sheltered basin, Wind Port cove ---
    demon_soft = gaussian_blur(demon_hi, 7.0)
    demon_plateau = 0.105 * smoothstep_np(6.0, 34.0, sdf) + 0.17 * n_ridge * smoothstep_np(10.0, 42.0, sdf)
    demon_crags = 0.115 * n_crag * smoothstep_np(14.0, 52.0, sdf)
    # Shallow rift valleys in central Demon wastes
    d_rift = dist_to_polyline(px, py, [(1275, 225), (1335, 268), (1395, 292), (1440, 330)])
    demon_rift_carve = -0.105 * np.exp(-(d_rift / 24.0) ** 2) * demon_soft
    # Kurasuma coastal highlands
    d_kura_ridge = dist_to_polyline(px, py, [(1210, 110), (1255, 165), (1315, 195)])
    kura_hills = 0.24 * np.exp(-(d_kura_ridge / 42.0) ** 2) * (0.55 + 0.65 * n_ridge)
    # Migurd Village cozy sheltered basin around (1491, 102) encircled by warm ochre ridge
    d_migurd = np.hypot(px - 1491.0, py - 102.0)
    migurd_ring = 0.21 * np.exp(-((d_migurd - 58.0) / 24.0) ** 2) * (0.68 + 0.45 * n_ridge)
    migurd_bowl = -0.135 * np.exp(-(d_migurd / 30.0) ** 2)
    # Wind Port sheltered harbor slope
    d_wind = np.hypot(px - 1423.0, py - 463.0)
    wind_cove = -0.095 * np.exp(-(d_wind / 46.0) ** 2)
    height += demon_soft * inland * (demon_plateau + demon_crags + kura_hills + migurd_ring + migurd_bowl + wind_cove) + demon_rift_carve

    # --- CENTRAL CONTINENT: Red Wyrm Mountains, Upper & Lower Jaws, Northern Ice Plateau, Dragon King Range ---
    central_soft = gaussian_blur(central_hi, 7.0)
    # Hero Red Wyrm Mountain Range (赤龙山脉) — monumental central spine + flanking massif shoulders
    # Keep southern massif peak cleanly south of city_red_dragon_jaw (560, 533) so the pass fortress sits 100% clear!
    d_red_wyrm = dist_to_polyline(px, py, [
        (338, 128), (382, 192), (424, 268), (464, 344), (508, 424), (534, 488), (588, 598), (612, 648)
    ])
    d_red_west = dist_to_polyline(px, py, [
        (372, 294), (426, 376), (474, 466), (512, 548)
    ])
    red_wyrm_env = np.exp(-(d_red_wyrm / 64.0) ** 2) + 0.44 * np.exp(-(d_red_west / 44.0) ** 2)
    red_wyrm_core = np.exp(-(d_red_wyrm / 30.0) ** 2)
    red_wyrm_peaks = (0.36 * red_wyrm_env + 0.34 * red_wyrm_core) * (0.58 + 0.56 * n_ridge + 0.16 * n_crag)

    # Dragon King Mountain Range (王龙山脉) along southern peninsula spine (starts cleanly south of Red Dragon Jaw)
    d_dk_mtn = dist_to_polyline(px, py, [(578, 608), (596, 656), (626, 708)])
    dk_peaks = 0.42 * np.exp(-(d_dk_mtn / 40.0) ** 2) * (0.55 + 0.65 * n_ridge)

    # Northern Frozen Highlands & Peaks (北方冰原高原)
    north_belt = smoothstep_np(208.0, 115.0, py) * central_soft
    d_north_mtn = dist_to_polyline(px, py, [(148, 92), (255, 76), (382, 74), (508, 66), (636, 76), (734, 110)])
    north_peaks = 0.46 * np.exp(-(d_north_mtn / 44.0) ** 2) * (0.58 + 0.62 * n_ridge)
    north_plateau = 0.145 * north_belt + north_peaks * central_soft

    # Strife Zone rugged valley hills
    d_strife = dist_to_polyline(px, py, [(495, 225), (565, 260), (618, 325)])
    strife_hills = 0.15 * np.exp(-(d_strife / 58.0) ** 2) * (0.42 + 0.68 * n_ridge)

    # Fittoa subtle circular teleportation crater basin near (308, 224)
    d_fittoa_ring = np.hypot(px - 308.0, py - 224.0)
    fittoa_crater = -0.042 * np.exp(-(d_fittoa_ring / 20.0) ** 2) + 0.024 * np.exp(-((d_fittoa_ring - 28.0) / 8.0) ** 2)

    height += central_soft * inland * (red_wyrm_peaks + dk_peaks + north_plateau + strife_hills + fittoa_crater)

    # Carve Upper Jaw Pass (赤龙上颚: Fittoa -> Sharia) and Lower Jaw Pass (赤龙下颚: Shiron -> Jaw -> Fittoa) cleanly!
    d_upper_jaw = dist_to_polyline(px, py, [(324, 245), (382, 196), (442, 144), (509, 86)])
    upper_carve = np.exp(-(d_upper_jaw / 22.0) ** 2)
    height = np.where(central_soft > 0.15, height * (1.0 - 0.72 * upper_carve) + 0.24 * (0.72 * upper_carve), height)

    d_lower_jaw = dist_to_polyline(px, py, [(644, 530), (560, 533), (503, 467), (468, 374), (403, 310), (324, 245)])
    lower_carve = np.exp(-(d_lower_jaw / 24.5) ** 2)
    height = np.where(central_soft > 0.15, height * (1.0 - 0.76 * lower_carve) + 0.23 * (0.76 * lower_carve), height)

    # --- MILIS CONTINENT: Blue Dragon Mountains, Great Forest terraced valleys, Milishion lake basin ---
    milis_soft = gaussian_blur(milis_hi, 7.0)
    d_blue_dragon = dist_to_polyline(px, py, [(1208, 712), (1256, 682), (1318, 664), (1362, 668)])
    blue_dragon_peaks = 0.56 * np.exp(-(d_blue_dragon / 40.0) ** 2) * (0.56 + 0.64 * n_ridge + 0.20 * n_crag)
    # Terraced Great Forest hills (east/north of Blue Dragon)
    forest_valleys = 0.085 * smoothstep_np(720.0, 585.0, py) * (0.45 + 0.55 * (np.sin(py * 0.09 + n_broad * 2.2) * 0.5 + 0.5))
    # Milishion calm central basin & sunken central lake (glints with OceanPlane water!)
    d_mili = np.hypot(px - 1352.0, py - 749.0)
    mili_basin = -0.075 * np.exp(-(d_mili / 44.0) ** 2)
    d_mili_lake = np.hypot(px - 1316.0, py - 734.0)
    mili_lake_w = np.exp(-(d_mili_lake / 15.0) ** 2) * milis_soft
    # Smooth Sacred Sword Highway valley from Milishion to West Port
    d_holy_road = dist_to_polyline(px, py, [(1352, 749), (1258, 774), (1147, 796), (1076, 817), (992, 825)])
    holy_road_smooth = np.exp(-(d_holy_road / 22.0) ** 2)
    height += milis_soft * inland * (blue_dragon_peaks + forest_valleys + mili_basin)
    height = np.where(milis_soft > 0.2, height * (1.0 - 0.48 * holy_road_smooth) + 0.155 * (0.48 * holy_road_smooth), height)
    height = height * (1.0 - 0.92 * mili_lake_w) - 0.032 * (0.92 * mili_lake_w)

    # --- PERIPHERAL SIX-FACED CONTINENTS: Begaritt (SW) & Heaven Continent (North) ---
    begaritt_soft = gaussian_blur(begaritt_hi, 6.0)
    heaven_mask = begaritt_soft * smoothstep_np(140.0, 75.0, py)
    begaritt_only = begaritt_soft * smoothstep_np(350.0, 460.0, py)
    height += heaven_mask * inland * (0.44 * (0.55 + 0.65 * n_ridge))
    height += begaritt_only * inland * (0.26 * (0.50 + 0.60 * n_ridge))

    # Carve clean navigable turquoise strait channel between Wind Port (Demon) and Zanto Port (Milis)
    d_wind_strait = dist_to_polyline(px, py, [(1370, 486), (1416, 491), (1462, 495)])
    strait_carve = np.exp(-(d_wind_strait / 11.5) ** 2)
    height = height * (1.0 - 0.94 * strait_carve) - 0.068 * (0.94 * strait_carve)

    # Keep land strictly above sea floor (except Milis Central Lake & Wind-Zanto Strait) and ocean strictly below sea level!
    keep_water = (mili_lake_w > 0.45) | (strait_carve > 0.38)
    height = np.where(sdf >= 0.0, np.where(keep_water, height, np.maximum(height, 0.035 * smoothstep_np(0.0, 4.5, sdf))), seabed)
    height = gaussian_blur(height, 1.85)
    # Guarantee zero coplanar Z-fighting with OceanPlane across open water
    height = np.where(sdf < -2.5, np.minimum(height, -0.028), height)

    # --- 19 CITY FLAT PADS (Gentle level terraces + M2.5 breathable spacing for crowded clusters & pass fortress!) ---
    # Visual layout nudges (in source pixels) strictly preserve canon region membership while eliminating overlap/cliff-clipping!
    city_nudge_px = {
        "city_red_dragon_jaw": (-12.0, -16.0),  # Center cleanly inside the wide open Lower Jaw valley floor (zero snow cliff clip!)
        "city_wind_port": (-7.0, -14.0),        # Pull slightly NNW onto Demon headland to open clear strait channel
        "city_zanto_port": (4.0, 14.0),         # Pull slightly SSE onto Milis headland to open clear strait channel
        "city_migurd": (16.0, -11.0),           # Nestle deeper into NE Migurd Basin away from Rikarisu
        "city_rikarisu": (-20.0, 14.0),         # Sit cleanly on SW crater plateau with graceful route gap to Migurd
    }
    all_cities = []
    for cont in config["continents"]:
        for reg in cont["regions"]:
            for city in legacy_map.sites(reg):
                all_cities.append((cont["id"], reg["id"], city))

    city_resolved_px = {}
    for _cid, _rid, city in all_cities:
        node_id = city["node"]
        dx_n, dy_n = city_nudge_px.get(node_id, (0.0, 0.0))
        cx = float(city["pixel"][0]) + dx_n
        cy = float(city["pixel"][1]) + dy_n
        city_resolved_px[node_id] = (cx, cy)
        ix = int(np.clip(round(cx / REF_W * (TEX_W - 1)), 0, TEX_W - 1))
        iy = int(np.clip(round(cy / REF_H * (TEX_H - 1)), 0, TEX_H - 1))
        is_port = city.get("arch") == "arch_port"
        base_h = float(height[iy, ix])
        target_h = max(0.105 if is_port else 0.145, min(base_h, 0.32 if node_id == "city_red_dragon_jaw" else 0.36))
        dist = np.hypot(px - cx, py - cy)
        r_in = 30.0 if node_id == "city_red_dragon_jaw" else 22.0
        r_out = 56.0 if node_id == "city_red_dragon_jaw" else 42.0
        pad_w = 1.0 - smoothstep_np(r_in, r_out, dist)
        # Do not raise open ocean into land near coastal ports
        pad_w = pad_w * smoothstep_np(-1.0, 2.5, sdf)
        height = height * (1.0 - pad_w) + target_h * pad_w

    min_h = float(np.min(height))
    max_h = float(np.max(height))
    norm_h = np.clip((height - min_h) / max(max_h - min_h, 1e-6), 0.0, 1.0)
    height_u16 = np.round(norm_h * 65535.0).astype(np.uint16)

    # --- BIOME SPLAT A (R=Demon Ochre, G=Milis Forest, B=Central Meadow, A=Northern Frost) ---
    snow_zone = np.clip(
        smoothstep_np(200.0, 118.0, py) * central_soft
        + heaven_mask
        + smoothstep_np(0.68, 0.88, height) * (1.0 - demon_soft * 0.85),
        0.0, 1.0
    )
    b_demon = np.clip(demon_soft + begaritt_only * 0.85, 0.0, 1.0) * (1.0 - 0.55 * snow_zone)
    b_milis = np.clip(milis_soft, 0.0, 1.0) * (1.0 - 0.60 * snow_zone)
    b_central = np.clip(central_soft, 0.0, 1.0) * (1.0 - snow_zone)
    b_snow = snow_zone
    splat_sum = np.maximum(b_demon + b_milis + b_central + b_snow, 1e-5)
    splat_a = np.stack([
        gaussian_blur(b_demon / splat_sum, 4.5),
        gaussian_blur(b_milis / splat_sum, 4.5),
        gaussian_blur(b_central / splat_sum, 4.5),
        gaussian_blur(b_snow / splat_sum, 4.5),
    ], axis=-1)
    splat_a = np.clip(np.round(splat_a * 255.0), 0, 255).astype(np.uint8)

    # --- BIOME SPLAT B (R=Steep Rock, G=Coast/Lake Sand, B=Paved Royal Roads, A=Demon Rifts/Scorch) ---
    dy, dx = np.gradient(height, WORLD_D / TEX_H, WORLD_W / TEX_W)
    slope = np.hypot(dx, dy)
    b_rock = np.clip(smoothstep_np(0.24, 0.72, slope) + smoothstep_np(0.42, 0.75, height) * 0.55, 0.0, 1.0) * inland
    b_sand = np.clip(smoothstep_np(-2.0, 3.0, sdf) * (1.0 - smoothstep_np(5.0, 18.0, sdf))
                     + np.exp(-(d_mili_lake / 22.0) ** 2) * milis_soft, 0.0, 1.0)

    # Rasterize slender organic royal roads (~55% slimmer than M1/M2 so Sacred Sword Highway never looks like a wide tile runway!)
    city_px = city_resolved_px
    road_dist = np.full((TEX_H, TEX_W), 1e9, dtype=np.float32)
    for route in routes_cfg.get("routes", []):
        if route.get("mode") == "ship":
            continue
        if float(route.get("stability_weight", 1.0)) > 1.25:
            continue
        pts = [city_px[route["from"]]] + [tuple(p) for p in route.get("via", [])] + [city_px[route["to"]]]
        road_dist = np.minimum(road_dist, dist_to_polyline(px, py, pts))
    road_wobble = (n_detail - 0.5) * 1.6
    b_road = (1.0 - smoothstep_np(1.35, 4.35, road_dist + road_wobble)) * inland

    b_scorch = np.clip((np.exp(-(d_rift / 38.0) ** 2) + 0.45 * n_crag * smoothstep_np(14.0, 45.0, sdf)) * demon_soft, 0.0, 1.0)
    splat_b = np.stack([
        gaussian_blur(b_rock, 2.0),
        gaussian_blur(b_sand, 2.5),
        gaussian_blur(b_road, 1.35),
        gaussian_blur(b_scorch, 3.0),
    ], axis=-1)
    splat_b = np.clip(np.round(splat_b * 255.0), 0, 255).astype(np.uint8)

    # --- REGION ID MAP (Lossless Nearest: R=region_idx, G=continent_idx, B=playable_land, A=255) ---
    region_rgba = np.zeros((TEX_H, TEX_W, 4), dtype=np.uint8)
    region_rgba[:, :, 0] = region_id_map
    region_rgba[:, :, 1] = cont_id_map
    region_rgba[:, :, 2] = np.where(region_id_map > 0, 255, 0).astype(np.uint8)
    region_rgba[:, :, 3] = 255

    # Write all 4 control maps
    write_png_u16_gray(OUT_TEX_DIR / "world_heightmap.png", height_u16)
    write_png_rgba8(OUT_TEX_DIR / "world_biome_splat_a.png", splat_a)
    write_png_rgba8(OUT_TEX_DIR / "world_biome_splat_b.png", splat_b)
    write_png_rgba8(OUT_TEX_DIR / "world_region_id_map.png", region_rgba)

    # Sample exact grounded 3D city positions (using resolved breathable pixel coords & asserting exact canon region!)
    region_id_to_idx = {entry["id"]: entry["index"] for entry in region_list}
    cities_meta = {}
    for cid, rid, city in all_cities:
        cpx, cpy = city_resolved_px[city["node"]]
        wx = (cpx - REF_W * 0.5) * PIXEL_UNIT
        wz = (cpy - REF_H * 0.5) * PIXEL_UNIT
        ix = int(np.clip(round((wx - MIN_X) / WORLD_W * (TEX_W - 1)), 0, TEX_W - 1))
        iy = int(np.clip(round((wz - MIN_Z) / WORLD_D * (TEX_H - 1)), 0, TEX_H - 1))
        wy = float(min_h + (height_u16[iy, ix] / 65535.0) * (max_h - min_h))
        got_ridx = int(region_id_map[iy, ix])
        exp_ridx = region_id_to_idx[rid]
        assert got_ridx == exp_ridx, f"Nudged city {city['node']} left region {rid} (got idx {got_ridx}, exp {exp_ridx})"
        assert wy > 0.08, f"Nudged city {city['node']} too low (y={wy:.4f})"
        cities_meta[city["node"]] = {
            "id": city["id"],
            "node": city["node"],
            "name": city["name"],
            "continent_id": cid,
            "region_id": rid,
            "arch": city.get("arch", "arch_village"),
            "pixel": [cpx, cpy],
            "position": [round(wx, 5), round(wy, 5), round(wz, 5)],
        }

    meta = {
        "schema_version": 1,
        "world_bounds": {
            "min_x": round(MIN_X, 5),
            "max_x": round(MAX_X, 5),
            "min_z": round(MIN_Z, 5),
            "max_z": round(MAX_Z, 5),
            "width": round(WORLD_W, 5),
            "depth": round(WORLD_D, 5),
        },
        "height_range": {
            "min_height": round(min_h, 6),
            "max_height": round(max_h, 6),
            "sea_level": SEA_LEVEL,
        },
        "control_maps": {
            "size": [TEX_W, TEX_H],
            "heightmap": "res://assets/textures/world_v2/world_heightmap.png",
            "biome_splat_a": "res://assets/textures/world_v2/world_biome_splat_a.png",
            "biome_splat_b": "res://assets/textures/world_v2/world_biome_splat_b.png",
            "region_id_map": "res://assets/textures/world_v2/world_region_id_map.png",
        },
        "continents": {"demon": 1, "milis": 2, "central": 3},
        "regions": region_list,
        "cities": cities_meta,
    }
    OUT_META_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_META_JSON.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Control maps (2048x1024) & metadata written. Height range: [{min_h:.3f}, {max_h:.3f}], Cities: {len(cities_meta)}", flush=True)
    return height, min_h, max_h, splat_a, splat_b, meta


# ---------------------------------------------------------------------------
# 3D Mesh Builders: TerrainSurface, OceanPlane, DioramaFrame
# ---------------------------------------------------------------------------
def make_pbr_mat(name: str, color, roughness: float, metallic: float = 0.0, coat: float = 0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = coat
    return mat, bsdf


def build_terrain_surface(height_field: np.ndarray, splat_a: np.ndarray, splat_b: np.ndarray):
    # Sample exact grid vertices (GRID_Z+1, GRID_X+1) in Blender Z-Up space:
    # Blender X = world_x in [MIN_X..MAX_X]
    # Blender Y = -world_z in [-MAX_Z..-MIN_Z] (north is +Y in Blender, becomes -Z in Godot!)
    # Blender Z = elevation (becomes +Y in Godot!)
    us = np.linspace(0.0, 1.0, GRID_X + 1, dtype=np.float32)
    vs = np.linspace(0.0, 1.0, GRID_Z + 1, dtype=np.float32)
    ug, vg = np.meshgrid(us, vs)

    # Bilinear sample height_field at exact vertex UVs
    fx = np.clip(ug * (TEX_W - 1), 0.0, TEX_W - 1.0001)
    fy = np.clip(vg * (TEX_H - 1), 0.0, TEX_H - 1.0001)
    x0, y0 = fx.astype(np.int32), fy.astype(np.int32)
    x1, y1 = np.minimum(x0 + 1, TEX_W - 1), np.minimum(y0 + 1, TEX_H - 1)
    wx, wy = fx - x0, fy - y0
    zg = (
        (height_field[y0, x0] * (1.0 - wx) + height_field[y0, x1] * wx) * (1.0 - wy)
        + (height_field[y1, x0] * (1.0 - wx) + height_field[y1, x1] * wx) * wy
    )

    xg = MIN_X + ug * WORLD_W
    yg = -(MIN_Z + vg * WORLD_D)  # North (v=0, world_z=MIN_Z) -> Blender +Y

    verts = np.stack([xg, yg, zg], axis=-1).reshape(-1, 3)
    # Build triangles cleanly with counter-clockwise upward (+Z) winding
    row_idx = np.arange(GRID_Z, dtype=np.int32)[:, None]
    col_idx = np.arange(GRID_X, dtype=np.int32)[None, :]
    v00 = row_idx * (GRID_X + 1) + col_idx
    v10 = v00 + 1
    v01 = v00 + (GRID_X + 1)
    v11 = v01 + 1
    # Note: y decreases as row increases, so (v00, v01, v11) and (v00, v11, v10) face +Z upward!
    tri1 = np.stack([v00, v01, v11], axis=-1).reshape(-1, 3)
    tri2 = np.stack([v00, v11, v10], axis=-1).reshape(-1, 3)
    faces = np.concatenate([tri1, tri2], axis=0)

    mesh = bpy.data.meshes.new("TerrainSurface")
    mesh.from_pydata(verts.tolist(), [], faces.tolist())
    mesh.update()
    assert not mesh.validate(clean_customdata=False), "TerrainSurface failed mesh validation"
    for poly in mesh.polygons:
        poly.use_smooth = True

    # UV layer: u_blender = u, v_blender = 1.0 - v (so glTF export flips v_gltf = 1 - v_blender = v!)
    uv_layer = mesh.uv_layers.new(name="UVMap")
    u_flat = ug.ravel()
    v_flat = (1.0 - vg).ravel()
    loop_vids = np.empty(len(mesh.loops), dtype=np.int32)
    mesh.loops.foreach_get("vertex_index", loop_vids)
    uv_coords = np.empty((len(mesh.loops), 2), dtype=np.float32)
    uv_coords[:, 0] = u_flat[loop_vids]
    uv_coords[:, 1] = v_flat[loop_vids]
    uv_layer.data.foreach_set("uv", uv_coords.ravel())

    # Clean sculptural clay-parchment material for Blender studio previews (Godot overrides with M1 shader).
    mat, bsdf = make_pbr_mat("SculptedParchmentClay", (0.86, 0.80, 0.69), 0.78, 0.02)
    # Bake a preview vertex color / image tint from splats for Blender studio render only
    sa = splat_a.astype(np.float32) / 255.0
    sb = splat_b.astype(np.float32) / 255.0
    base = (
        sa[:, :, 0:1] * np.array([0.82, 0.64, 0.51])
        + sa[:, :, 1:2] * np.array([0.67, 0.77, 0.60])
        + sa[:, :, 2:3] * np.array([0.84, 0.80, 0.67])
        + sa[:, :, 3:4] * np.array([0.92, 0.94, 0.96])
    )
    base = base * (1.0 - 0.45 * sb[:, :, 0:1]) + np.array([0.56, 0.44, 0.36]) * (0.45 * sb[:, :, 0:1])
    base = base * (1.0 - 0.35 * sb[:, :, 1:2]) + np.array([0.90, 0.84, 0.70]) * (0.35 * sb[:, :, 1:2])
    base = base * (1.0 - 0.35 * sb[:, :, 2:3]) + np.array([0.94, 0.89, 0.78]) * (0.35 * sb[:, :, 2:3])
    col_attr = mesh.color_attributes.new(name="PreviewTint", type="BYTE_COLOR", domain="POINT")
    v_col = np.ones((verts.shape[0], 4), dtype=np.float32)
    v_col[:, :3] = base[y0.ravel(), x0.ravel()]
    col_attr.data.foreach_set("color", v_col.ravel())
    vcol_node = mat.node_tree.nodes.new("ShaderNodeVertexColor")
    vcol_node.layer_name = "PreviewTint"
    mat.node_tree.links.new(vcol_node.outputs["Color"], bsdf.inputs["Base Color"])
    mesh.materials.append(mat)

    obj = bpy.data.objects.new("TerrainSurface", mesh)
    bpy.context.collection.objects.link(obj)
    mesh.calc_loop_triangles()
    return obj, len(mesh.loop_triangles)


def build_ocean_plane():
    us = np.linspace(0.0, 1.0, OCEAN_X + 1, dtype=np.float32)
    vs = np.linspace(0.0, 1.0, OCEAN_Z + 1, dtype=np.float32)
    ug, vg = np.meshgrid(us, vs)
    xg = MIN_X + ug * WORLD_W
    yg = -(MIN_Z + vg * WORLD_D)
    zg = np.full_like(xg, SEA_LEVEL, dtype=np.float32)
    verts = np.stack([xg, yg, zg], axis=-1).reshape(-1, 3)

    row_idx = np.arange(OCEAN_Z, dtype=np.int32)[:, None]
    col_idx = np.arange(OCEAN_X, dtype=np.int32)[None, :]
    v00 = row_idx * (OCEAN_X + 1) + col_idx
    v10 = v00 + 1
    v01 = v00 + (OCEAN_X + 1)
    v11 = v01 + 1
    tri1 = np.stack([v00, v01, v11], axis=-1).reshape(-1, 3)
    tri2 = np.stack([v00, v11, v10], axis=-1).reshape(-1, 3)
    faces = np.concatenate([tri1, tri2], axis=0)

    mesh = bpy.data.meshes.new("OceanPlane")
    mesh.from_pydata(verts.tolist(), [], faces.tolist())
    mesh.update()
    assert not mesh.validate(clean_customdata=False)
    for poly in mesh.polygons:
        poly.use_smooth = True

    uv_layer = mesh.uv_layers.new(name="UVMap")
    u_flat = ug.ravel()
    v_flat = (1.0 - vg).ravel()
    loop_vids = np.empty(len(mesh.loops), dtype=np.int32)
    mesh.loops.foreach_get("vertex_index", loop_vids)
    uv_coords = np.empty((len(mesh.loops), 2), dtype=np.float32)
    uv_coords[:, 0] = u_flat[loop_vids]
    uv_coords[:, 1] = v_flat[loop_vids]
    uv_layer.data.foreach_set("uv", uv_coords.ravel())

    sea_mat, bsdf = make_pbr_mat("AntiqueChartOcean", (0.31, 0.48, 0.54), 0.30, 0.04, 0.35)
    bsdf.inputs["Alpha"].default_value = 0.84
    mesh.materials.append(sea_mat)

    obj = bpy.data.objects.new("OceanPlane", mesh)
    bpy.context.collection.objects.link(obj)
    mesh.calc_loop_triangles()
    return obj, len(mesh.loop_triangles)


def build_diorama_frame():
    """Museum-grade dark walnut stepped plinth + matte antique-brass inlay & 4 sculpted corner clasps."""
    verts = []
    faces = []
    mat_ids = []

    def add_ring_loft(profile, mat_seq):
        # profile: list of (half_x, half_y, z)
        rings = []
        for hx, hy, z in profile:
            start = len(verts)
            verts.extend([(-hx, -hy, z), (hx, -hy, z), (hx, hy, z), (-hx, hy, z)])
            rings.append(start)
        for i, mat_i in enumerate(mat_seq):
            a, b = rings[i], rings[i + 1]
            for s in range(4):
                sn = (s + 1) % 4
                faces.append((a + s, a + sn, b + sn, b + s))
                mat_ids.append(mat_i)

    def add_box(cx, cy, z0, sx, sy, sz, mat_i, bevel=0.018):
        hx, hy = sx * 0.5, sy * 0.5
        bv = min(bevel, hx * 0.35, hy * 0.35, sz * 0.25)
        add_ring_loft([
            (hx - bv, hy - bv, z0),
            (hx, hy, z0 + bv),
            (hx, hy, z0 + sz - bv),
            (hx - bv, hy - bv, z0 + sz),
        ], [mat_i, mat_i, mat_i])
        # Shift last 16 verts to (cx, cy)
        for k in range(len(verts) - 16, len(verts)):
            vx, vy, vz = verts[k]
            verts[k] = (vx + cx, vy + cy, vz)
        top = len(verts) - 4
        bot = len(verts) - 16
        faces.append((top, top + 1, top + 2, top + 3))
        mat_ids.append(mat_i)
        faces.append((bot + 3, bot + 2, bot + 1, bot))
        mat_ids.append(mat_i)

    def add_stud(cx, cy, z0, radius, height, sides, mat_i):
        base_i = len(verts)
        for r, z in [(radius, z0), (radius * 0.82, z0 + height * 0.72), (radius * 0.35, z0 + height)]:
            for s in range(sides):
                ang = math.tau * s / sides
                verts.append((cx + math.cos(ang) * r, cy + math.sin(ang) * r, z))
        for ring in range(2):
            a, b = base_i + ring * sides, base_i + (ring + 1) * sides
            for s in range(sides):
                sn = (s + 1) % sides
                faces.append((a + s, a + sn, b + sn, b + s))
                mat_ids.append(mat_i)
        top = base_i + 2 * sides
        faces.append(tuple(range(top, top + sides)))
        mat_ids.append(mat_i)

    ix, iy = WORLD_W * 0.5 - 0.02, WORLD_D * 0.5 - 0.02
    # Main stepped Dark Walnut frame profile (material 0 = walnut, 1 = antique brass, 2 = dark bronze groove)
    add_ring_loft([
        (ix, iy, -0.26),          # Inner seabed wall bottom
        (ix, iy, 0.095),          # Inner wall top
        (ix + 0.035, iy + 0.035, 0.135),  # Inner brass bevel
        (ix + 0.095, iy + 0.095, 0.135),  # Inner brass flat inlay
        (ix + 0.115, iy + 0.115, 0.118),  # Recessed bronze seam
        (ix + 0.145, iy + 0.145, 0.155),  # Raised walnut top inner lip
        (ix + 0.42, iy + 0.42, 0.155),    # Broad walnut top shelf
        (ix + 0.52, iy + 0.52, 0.065),    # Outer chamfered walnut slope
        (ix + 0.56, iy + 0.56, 0.025),    # Lower molding lip
        (ix + 0.56, iy + 0.56, -0.045),   # Brass belt groove
        (ix + 0.62, iy + 0.62, -0.095),   # Lower stepped walnut plinth
        (ix + 0.64, iy + 0.64, -0.34),    # Base foot on tabletop
    ], [0, 1, 1, 2, 0, 0, 0, 0, 1, 0, 0])

    # Close underside bottom cap cleanly
    b_out = len(verts) - 4
    b_in = 0
    for s in range(4):
        sn = (s + 1) % 4
        faces.append((b_out + sn, b_out + s, b_in + s, b_in + sn))
        mat_ids.append(0)

    # Four sculpted aged antique-brass corner clasps & ornamental studs!
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            cx = sx * (ix + 0.30)
            cy = sy * (iy + 0.30)
            # L-shaped brass corner plate
            add_box(cx, cy, 0.146, 0.42, 0.42, 0.042, 1, bevel=0.016)
            add_box(cx - sx * 0.32, cy, 0.146, 0.36, 0.18, 0.032, 1, bevel=0.012)
            add_box(cx, cy - sy * 0.32, 0.146, 0.18, 0.36, 0.032, 1, bevel=0.012)
            # Decorative brass corner medallion + rivets
            add_stud(cx, cy, 0.186, 0.095, 0.036, 16, 1)
            add_stud(cx, cy, 0.220, 0.036, 0.016, 12, 2)
            add_stud(cx - sx * 0.38, cy, 0.176, 0.028, 0.014, 10, 2)
            add_stud(cx, cy - sy * 0.38, 0.176, 0.028, 0.014, 10, 2)

    # Mid-edge brass title plaques on North & South rims
    for sy in (-1.0, 1.0):
        add_box(0.0, sy * (iy + 0.28), 0.148, 1.35, 0.18, 0.026, 1, bevel=0.010)
        add_stud(-0.56, sy * (iy + 0.28), 0.172, 0.024, 0.012, 10, 2)
        add_stud(0.56, sy * (iy + 0.28), 0.172, 0.024, 0.012, 10, 2)

    mesh = bpy.data.meshes.new("DioramaFrame")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    assert not mesh.validate(clean_customdata=False), "DioramaFrame failed validation"
    for poly, mi in zip(mesh.polygons, mat_ids):
        poly.material_index = mi
        poly.use_smooth = False

    walnut, _ = make_pbr_mat("DioramaDarkWalnut", (0.145, 0.086, 0.052), 0.44, 0.04, 0.18)
    brass, _ = make_pbr_mat("DioramaMatteBrass", (0.72, 0.53, 0.24), 0.34, 0.82, 0.12)
    bronze, _ = make_pbr_mat("DioramaDarkBronze", (0.28, 0.19, 0.10), 0.46, 0.72)
    mesh.materials.append(walnut)
    mesh.materials.append(brass)
    mesh.materials.append(bronze)

    obj = bpy.data.objects.new("DioramaFrame", mesh)
    bpy.context.collection.objects.link(obj)
    mesh.calc_loop_triangles()
    return obj, len(mesh.loop_triangles)


# ---------------------------------------------------------------------------
# Export & Validate GLB + Render Two Studio Verification Previews
# ---------------------------------------------------------------------------
def export_world_glb(objects):
    OUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in objects:
        o.select_set(True)
    res = bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        export_yup=True,
        export_animations=False,
        use_selection=True,
    )
    assert "FINISHED" in res

    # Strict binary GLB inspection (node names, triangle count, exact UV alignment!)
    blob = OUT_GLB.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", blob, 0)
    json_len, json_type = struct.unpack_from("<I4s", blob, 12)
    gltf = json.loads(blob[20:20 + json_len])
    bin_len, bin_type = struct.unpack_from("<I4s", blob, 20 + json_len)
    binary = blob[28 + json_len:28 + json_len + bin_len]
    assert magic == b"glTF" and version == 2 and json_type == b"JSON" and bin_type == b"BIN\0"

    node_names = {n["name"] for n in gltf["nodes"]}
    assert {"TerrainSurface", "OceanPlane", "DioramaFrame"}.issubset(node_names), f"Missing nodes: {node_names}"
    total_tris = 0
    for mesh in gltf["meshes"]:
        tris = sum(gltf["accessors"][p["indices"]]["count"] // 3 for p in mesh["primitives"])
        print(f"  GLB mesh {mesh['name']}: {tris:,} triangles", flush=True)
        total_tris += tris
    assert 45000 <= total_tris <= 75000, f"Triangle count {total_tris} outside 45k..75k budget!"

    # Verify TerrainSurface UV matches exact linear world (X, Z) mapping!
    t_node = next(n for n in gltf["nodes"] if n["name"] == "TerrainSurface")
    prim = gltf["meshes"][t_node["mesh"]]["primitives"][0]
    pos = legacy_map.read_float_attribute(gltf, binary, prim["attributes"]["POSITION"], 3)
    uv = legacy_map.read_float_attribute(gltf, binary, prim["attributes"]["TEXCOORD_0"], 2)
    expected_u = (pos[:, 0] - MIN_X) / WORLD_W
    expected_v = (pos[:, 2] - MIN_Z) / WORLD_D
    max_drift = float(max(np.max(np.abs(uv[:, 0] - expected_u)), np.max(np.abs(uv[:, 1] - expected_v))))
    assert max_drift < 1e-4, f"UV drift too high: {max_drift}"
    print(f"Exported {OUT_GLB.name}: {total_tris:,} total tris, {length:,} bytes, UV drift={max_drift:.6f}", flush=True)


def render_studio_previews():
    OUT_PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    bpy.ops.mesh.primitive_plane_add(size=140, location=(0, 0, -0.342))
    desk, _ = make_pbr_mat("StudioWalnutMat", (0.048, 0.028, 0.019), 0.88, 0.02)
    bpy.context.object.data.materials.append(desk)

    def aim(obj, target):
        obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()

    cam_data = bpy.data.cameras.new("ReliefPreviewCam")
    cam_data.lens = 42.0
    cam = bpy.data.objects.new("ReliefPreviewCam", cam_data)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam

    # Soft warm sunlit directional key + cool sky fill for crisp sculpted relief shadows
    sun_data = bpy.data.lights.new("SunKey", "SUN")
    sun_data.energy = 3.2
    sun_data.color = (1.0, 0.90, 0.74)
    sun_data.angle = math.radians(4.5)
    sun_obj = bpy.data.objects.new("SunKey", sun_data)
    bpy.context.collection.objects.link(sun_obj)
    sun_obj.location = (-8.0, -5.0, 6.5)
    aim(sun_obj, (0.0, 0.0, 0.0))

    for name, pos, energy, col, sz in [
        ("SkyFill", (8.0, 6.0, 9.5), 1150, (0.72, 0.85, 1.0), 8.5),
        ("RimWarm", (0.5, 9.5, 4.2), 900, (1.0, 0.88, 0.72), 6.0),
    ]:
        ldata = bpy.data.lights.new(name, "AREA")
        ldata.energy, ldata.color, ldata.size = energy, col, sz
        lobj = bpy.data.objects.new(name, ldata)
        bpy.context.collection.objects.link(lobj)
        lobj.location = pos
        aim(lobj, (0, 0, 0.1))

    scene.world = bpy.data.worlds.new("StudioAmbience")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.30, 0.26, 0.21, 1.0)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.36
    scene.view_settings.view_transform = "AgX"
    scene.render.image_settings.file_format = "PNG"
    scene.render.resolution_percentage = 100

    # 1. Full diorama overview (shows entire dark walnut + antique brass frame cleanly)
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    cam.location = (0.0, -12.4, 20.2)
    aim(cam, (0.0, 0.05, 0.0))
    legacy_map.render_shot(scene, OUT_PREVIEW_DIR / "relief_overview.png")

    # 2. Close-up diptych: Red Wyrm Jaws (left) + Demon Migurd Basin (right)
    scene.render.resolution_x, scene.render.resolution_y = 900, 820
    cam_data.lens = 52.0
    # Shot A: Red Wyrm Mountains + Lower Jaw & Upper Jaw
    jaws_target = Vector((-3.55, 0.72, 0.22))
    cam.location = jaws_target + Vector((-0.6, -4.3, 3.6))
    aim(cam, jaws_target)
    p_a = OUT_PREVIEW_DIR / "_tmp_jaws.png"
    legacy_map.render_shot(scene, p_a)

    # Shot B: Demon Continent Migurd Basin + Rikarisu + Wind Port
    demon_target = Vector((5.65, 2.55, 0.18))
    cam.location = demon_target + Vector((0.4, -4.2, 3.4))
    aim(cam, demon_target)
    p_b = OUT_PREVIEW_DIR / "_tmp_demon.png"
    legacy_map.render_shot(scene, p_b)

    # Combine side-by-side cleanly using Blender images + NumPy -> lossless PNG
    img_a = bpy.data.images.load(str(p_a))
    img_b = bpy.data.images.load(str(p_b))
    ra = legacy_map.raster_image(img_a)
    rb = legacy_map.raster_image(img_b)
    bpy.data.images.remove(img_a)
    bpy.data.images.remove(img_b)
    p_a.unlink(missing_ok=True)
    p_b.unlink(missing_ok=True)
    divider = np.full((ra.shape[0], 8, 4), [0.16, 0.11, 0.07, 1.0], dtype=np.float32)
    combo = np.concatenate([ra, divider, rb], axis=1)
    write_png_rgba8(OUT_PREVIEW_DIR / "relief_closeup_jaws_and_demon.png", np.clip(np.round(combo * 255.0), 0, 255).astype(np.uint8))
    print(f"Combined close-up preview written: {OUT_PREVIEW_DIR / 'relief_closeup_jaws_and_demon.png'}", flush=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    config = json.loads(MAP_DATA_JSON.read_text(encoding="utf-8"))
    routes_cfg = json.loads(ROUTES_JSON.read_text(encoding="utf-8"))

    height, _min_h, _max_h, splat_a, splat_b, _meta = build_world_fields(config, routes_cfg)
    terrain_obj, t_tris = build_terrain_surface(height, splat_a, splat_b)
    ocean_obj, o_tris = build_ocean_plane()
    frame_obj, f_tris = build_diorama_frame()
    print(f"Built meshes -> TerrainSurface: {t_tris:,}, OceanPlane: {o_tris:,}, DioramaFrame: {f_tris:,}, Total: {t_tris+o_tris+f_tris:,}", flush=True)

    export_world_glb([terrain_obj, ocean_obj, frame_obj])
    render_studio_previews()


if __name__ == "__main__":
    main()
