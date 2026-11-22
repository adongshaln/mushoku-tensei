"""Generate 8 seamless 512x512 hand-painted watercolor + paper-grain terrain tiles (Albedo + Normal)
plus a satin dark-walnut woodgrain tile for DioramaFrame and a visual contact sheet preview.

Run from repository root:
    blender --background --python tools/blender_world_v2/generate_terrain_tiles.py
"""

from pathlib import Path
import struct
import sys
import zlib

import numpy as np


sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "assets/textures/world_v2/tiles"
PREVIEW_PATH = ROOT / "tools/blender_world_v2/previews/m2_tiles_contact_sheet.png"
RES = 512


# ---------------------------------------------------------------------------
# Pure-Python Lossless RGBA8 PNG Writer
# ---------------------------------------------------------------------------
def _png_chunk(tag: bytes, payload: bytes) -> bytes:
    crc = zlib.crc32(tag + payload) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", crc)


def write_png_rgba8(path: Path, arr_u8: np.ndarray) -> None:
    h, w, c = arr_u8.shape
    assert c == 4
    raw = np.concatenate([np.zeros((h, 1), dtype=np.uint8), arr_u8.reshape(h, w * 4)], axis=1)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    data = b"\x89PNG\r\n\x1a\n" + _png_chunk(b"IHDR", ihdr) + _png_chunk(b"IDAT", zlib.compress(raw.tobytes(), 6)) + _png_chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def to_u8_rgba(rgb: np.ndarray) -> np.ndarray:
    h, w, _ = rgb.shape
    out = np.empty((h, w, 4), dtype=np.uint8)
    out[:, :, :3] = np.clip(np.round(rgb * 255.0), 0.0, 255.0).astype(np.uint8)
    out[:, :, 3] = 255
    return out


# ---------------------------------------------------------------------------
# Strictly Periodic (100% Seamless 4-Way Tileable) Procedural Primitives
# ---------------------------------------------------------------------------
def smoothstep(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
    diff = edge1 - edge0
    safe = diff if abs(diff) >= 1e-6 else (1e-6 if diff >= 0.0 else -1e-6)
    t = np.clip((x - edge0) / safe, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def periodic_value_noise(res: int, freq_x: int, freq_y: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    grid = rng.random((freq_y, freq_x), dtype=np.float32)
    u = np.arange(res, dtype=np.float32) / float(res)
    v = np.arange(res, dtype=np.float32) / float(res)
    gx = u * float(freq_x)
    gy = v * float(freq_y)
    x0 = np.floor(gx).astype(np.int32) % freq_x
    y0 = np.floor(gy).astype(np.int32) % freq_y
    x1 = (x0 + 1) % freq_x
    y1 = (y0 + 1) % freq_y
    fx = gx - np.floor(gx)
    fy = gy - np.floor(gy)
    # Quintic smoothstep for zero grid-line normal artifacts
    sx = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0)
    sy = fy * fy * fy * (fy * (fy * 6.0 - 15.0) + 10.0)

    v00 = grid[y0[:, None], x0[None, :]]
    v10 = grid[y0[:, None], x1[None, :]]
    v01 = grid[y1[:, None], x0[None, :]]
    v11 = grid[y1[:, None], x1[None, :]]
    top = v00 * (1.0 - sx[None, :]) + v10 * sx[None, :]
    bot = v01 * (1.0 - sx[None, :]) + v11 * sx[None, :]
    return top * (1.0 - sy[:, None]) + bot * sy[:, None]


def periodic_fbm(res: int, fx: int, fy: int, octaves: int, seed: int, persistence: float = 0.52) -> np.ndarray:
    total = np.zeros((res, res), dtype=np.float32)
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        mul = 1 << o
        total += amp * periodic_value_noise(res, fx * mul, fy * mul, seed + o * 137)
        norm += amp
        amp *= persistence
    return total / max(norm, 1e-6)


def periodic_ridge(res: int, fx: int, fy: int, octaves: int, seed: int, persistence: float = 0.50) -> np.ndarray:
    total = np.zeros((res, res), dtype=np.float32)
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        mul = 1 << o
        n = periodic_value_noise(res, fx * mul, fy * mul, seed + o * 193)
        r = 1.0 - np.abs(n * 2.0 - 1.0)
        total += amp * (r * r)
        norm += amp
        amp *= persistence
    return total / max(norm, 1e-6)


def periodic_sample(field: np.ndarray, dx_px: np.ndarray, dy_px: np.ndarray) -> np.ndarray:
    """Bilinearly sample a periodic (H, W) array displaced by (dx_px, dy_px) pixels."""
    h, w = field.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    sx = (xx + dx_px) % float(w)
    sy = (yy + dy_px) % float(h)
    x0 = np.floor(sx).astype(np.int32) % w
    y0 = np.floor(sy).astype(np.int32) % h
    x1 = (x0 + 1) % w
    y1 = (y0 + 1) % h
    tx = sx - np.floor(sx)
    ty = sy - np.floor(sy)
    v00 = field[y0, x0]
    v10 = field[y0, x1]
    v01 = field[y1, x0]
    v11 = field[y1, x1]
    return (v00 * (1.0 - tx) + v10 * tx) * (1.0 - ty) + (v01 * (1.0 - tx) + v11 * tx) * ty


def periodic_warped_wash(res: int, fx: int, fy: int, warp_px: float, seed: int, octaves: int = 4) -> np.ndarray:
    base = periodic_fbm(res, fx, fy, octaves, seed)
    wx = (periodic_fbm(res, max(2, fx // 2), max(2, fy // 2), 3, seed + 511) - 0.5) * 2.0 * warp_px
    wy = (periodic_fbm(res, max(2, fx // 2), max(2, fy // 2), 3, seed + 887) - 0.5) * 2.0 * warp_px
    return periodic_sample(base, wx, wy)


def periodic_blur(field: np.ndarray, radius_px: float) -> np.ndarray:
    """Fast exact periodic Gaussian blur using 2D FFT (100% wrap-seamless)."""
    h, w = field.shape
    ky = np.fft.fftfreq(h).astype(np.float32) * h
    kx = np.fft.rfftfreq(w).astype(np.float32) * w
    # Gaussian in spatial domain -> Gaussian in frequency domain
    sigma = max(radius_px, 0.25)
    g = np.exp(-2.0 * (np.pi ** 2) * (sigma ** 2) * ((ky[:, None] / h) ** 2 + (kx[None, :] / w) ** 2))
    return np.fft.irfft2(np.fft.rfft2(field) * g, s=(h, w)).astype(np.float32)


def periodic_voronoi(res: int, cells_x: int, cells_y: int, seed: int, jitter: float = 0.80, warp_px: float = 0.0):
    """Exact 4-way seamless Voronoi returning (f1, edge_dist, cell_val)."""
    rng = np.random.default_rng(seed)
    pts_x = (np.arange(cells_x)[None, :] + 0.5 + (rng.random((cells_y, cells_x)) - 0.5) * jitter) % cells_x
    pts_y = (np.arange(cells_y)[:, None] + 0.5 + (rng.random((cells_y, cells_x)) - 0.5) * jitter) % cells_y
    cell_val = rng.random((cells_y, cells_x)).astype(np.float32)

    yy, xx = np.mgrid[0:res, 0:res].astype(np.float32)
    if warp_px > 0.0:
        xx = (xx + (periodic_fbm(res, 6, 6, 3, seed + 401) - 0.5) * 2.0 * warp_px) % res
        yy = (yy + (periodic_fbm(res, 6, 6, 3, seed + 709) - 0.5) * 2.0 * warp_px) % res

    gx = xx / float(res) * cells_x
    gy = yy / float(res) * cells_y
    cx = np.floor(gx).astype(np.int32) % cells_x
    cy = np.floor(gy).astype(np.int32) % cells_y

    f1 = np.full((res, res), 1e6, dtype=np.float32)
    f2 = np.full((res, res), 1e6, dtype=np.float32)
    best_val = np.zeros((res, res), dtype=np.float32)

    for dy in (-1, 0, 1):
        ny = (cy + dy) % cells_y
        for dx in (-1, 0, 1):
            nx = (cx + dx) % cells_x
            px = pts_x[ny, nx]
            py = pts_y[ny, nx]
            ddx = gx - px
            ddx = ddx - np.round(ddx / cells_x) * cells_x
            ddy = gy - py
            ddy = ddy - np.round(ddy / cells_y) * cells_y
            dist = np.hypot(ddx, ddy)
            closer1 = dist < f1
            f2 = np.where(closer1, f1, np.minimum(f2, dist))
            f1 = np.where(closer1, dist, f1)
            best_val = np.where(closer1, cell_val[ny, nx], best_val)

    edge_dist = np.clip(f2 - f1, 0.0, 2.0)
    return f1, edge_dist, best_val


def watercolor_edge_pool(wash: np.ndarray) -> np.ndarray:
    """Authentic watercolor drying pigment rim along soft wash transitions."""
    gx = (np.roll(wash, -2, axis=1) - np.roll(wash, 2, axis=1)) * 0.5
    gy = (np.roll(wash, -2, axis=0) - np.roll(wash, 2, axis=0)) * 0.5
    grad = np.hypot(gx, gy)
    return smoothstep(0.012, 0.085, periodic_blur(grad, 1.8))


def handmade_paper_tooth(res: int, seed: int) -> np.ndarray:
    """Soft cold-press handmade parchment paper tooth (low shimmer, rich close-up tactility)."""
    coarse = periodic_fbm(res, 16, 16, 3, seed)
    fine_h = periodic_fbm(res, 32, 64, 2, seed + 211)
    fine_v = periodic_fbm(res, 64, 32, 2, seed + 431)
    fiber = 0.5 * fine_h + 0.5 * fine_v
    return 0.55 * coarse + 0.45 * fiber


def height_to_normal_rgb(h: np.ndarray, strength: float) -> np.ndarray:
    """Convert periodic [0..1] micro-height into smooth tangent-space OpenGL/Godot normal map RGB."""
    h_s = periodic_blur(h, 0.85)
    dx = (np.roll(h_s, -1, axis=1) - np.roll(h_s, 1, axis=1)) * 0.5 * strength
    dy = (np.roll(h_s, -1, axis=0) - np.roll(h_s, 1, axis=0)) * 0.5 * strength
    nx = -dx
    ny = -dy
    nz = np.ones_like(nx)
    inv_len = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz + 1e-8)
    rgb = np.stack([nx * inv_len * 0.5 + 0.5, ny * inv_len * 0.5 + 0.5, nz * inv_len * 0.5 + 0.5], axis=-1)
    return np.clip(rgb, 0.0, 1.0)


def mix_col(a, b, t: np.ndarray) -> np.ndarray:
    ca = np.asarray(a, dtype=np.float32)
    cb = np.asarray(b, dtype=np.float32)
    tt = np.clip(t, 0.0, 1.0)[..., None]
    return ca * (1.0 - tt) + cb * tt


def verify_seamless(arr: np.ndarray, name: str) -> None:
    """Confirm wrap continuity across left-right and top-bottom edges."""
    lr_diff = float(np.mean(np.abs(arr[:, 0, :3].astype(np.float32) - arr[:, -1, :3].astype(np.float32))))
    tb_diff = float(np.mean(np.abs(arr[0, :, :3].astype(np.float32) - arr[-1, :, :3].astype(np.float32))))
    assert lr_diff < 12.0 and tb_diff < 12.0, f"Seam detected in {name}: LR={lr_diff:.2f} TB={tb_diff:.2f}"


# ---------------------------------------------------------------------------
# 8 Hand-Painted Watercolor Biome Tiles + Dark Walnut Frame Tile
# ---------------------------------------------------------------------------
def build_tile_00_demon_wastes():
    """Splat A.R — Clean hand-painted Demon Continent terracotta ochre & weathered sandstone watercolor (ZERO mud cracks)."""
    wash1 = periodic_warped_wash(RES, 3, 3, 44.0, seed=1001, octaves=4)
    wash2 = periodic_warped_wash(RES, 6, 4, 28.0, seed=1033, octaves=4)
    wind_strata = periodic_warped_wash(RES, 3, 10, 22.0, seed=1061, octaves=3)
    ash_veil = smoothstep(0.48, 0.84, periodic_warped_wash(RES, 5, 5, 24.0, seed=1073, octaves=3))
    paper = handmade_paper_tooth(RES, seed=1099)
    rim = watercolor_edge_pool(wash1)

    # Refined terracotta red-ochre x warm ochre-sand x weathered canyon ash (clean, airy, zero dark crack grid!)
    col = mix_col((0.798, 0.578, 0.452), (0.688, 0.448, 0.342), wash1)
    col = mix_col(col, (0.858, 0.692, 0.545), smoothstep(0.42, 0.84, wash2) * 0.54)
    col = mix_col(col, (0.718, 0.618, 0.558), ash_veil * 0.32)
    col = mix_col(col, (0.612, 0.415, 0.325), smoothstep(0.46, 0.14, wind_strata) * 0.22 + rim * 0.14)
    col *= (0.962 + 0.076 * paper)[..., None]

    h = 0.50 + 0.18 * wash2 + 0.16 * wind_strata + 0.10 * paper
    return col, height_to_normal_rgb(h, 2.2)


def build_tile_01_milis_forest():
    """Splat A.G — Luminous hand-painted Milis sage-jade & sunlit moss watercolor (clean, crisp, zero murky gray)."""
    wash = periodic_warped_wash(RES, 4, 4, 40.0, seed=2003, octaves=4)
    dapple = periodic_warped_wash(RES, 8, 8, 26.0, seed=2029, octaves=4)
    canopy_soft = periodic_warped_wash(RES, 12, 10, 18.0, seed=2053, octaves=3)
    paper = handmade_paper_tooth(RES, seed=2099)
    rim = watercolor_edge_pool(wash)

    # Fresh clean watercolor sage-emerald & cool teal-moss shadows + sunlit warm chartreuse highlights
    col = mix_col((0.435, 0.642, 0.462), (0.585, 0.742, 0.512), wash)
    col = mix_col(col, (0.728, 0.818, 0.542), smoothstep(0.52, 0.86, dapple) * 0.52)
    col = mix_col(col, (0.312, 0.528, 0.448), smoothstep(0.44, 0.12, dapple) * 0.44 + rim * 0.15)
    col = mix_col(col, (0.535, 0.708, 0.492), smoothstep(0.48, 0.82, canopy_soft) * 0.24)
    col *= (0.962 + 0.076 * paper)[..., None]

    h = 0.48 + 0.18 * dapple + 0.16 * canopy_soft + 0.10 * paper
    return col, height_to_normal_rgb(h, 2.4)


def build_tile_02_central_meadow():
    """Splat A.B — Pure breezy light-novel warm sage & sunlit butter-yellow watercolor meadow."""
    wash = periodic_warped_wash(RES, 4, 4, 42.0, seed=3001, octaves=4)
    breeze = periodic_warped_wash(RES, 5, 12, 22.0, seed=3037, octaves=3)
    sunlit_gold = periodic_warped_wash(RES, 6, 6, 28.0, seed=3067, octaves=3)
    paper = handmade_paper_tooth(RES, seed=3089)
    rim = watercolor_edge_pool(wash)

    # Pure airy sage-green x sunlit warm yellow-green with soft cool celadon shadows (zero muddy olive!)
    col = mix_col((0.578, 0.735, 0.512), (0.738, 0.818, 0.548), wash)
    col = mix_col(col, (0.865, 0.848, 0.592), smoothstep(0.50, 0.86, sunlit_gold) * 0.48)
    col = mix_col(col, (0.455, 0.648, 0.515), smoothstep(0.42, 0.12, breeze) * 0.34 + rim * 0.14)
    col *= (0.964 + 0.072 * paper)[..., None]

    h = 0.48 + 0.16 * breeze + 0.14 * wash + 0.10 * paper
    return col, height_to_normal_rgb(h, 2.0)


def build_tile_03_north_frost():
    """Splat A.A — Luminous warm ivory snowfield with delicate sea-mist blue glacial wind shadows."""
    drift = periodic_warped_wash(RES, 4, 9, 28.0, seed=4003, octaves=4)
    glacier = periodic_warped_wash(RES, 3, 5, 32.0, seed=4027, octaves=3)
    sastrugi = periodic_ridge(RES, 4, 12, 3, seed=4057)
    paper = handmade_paper_tooth(RES, seed=4093)

    col = mix_col((0.812, 0.858, 0.888), (0.935, 0.918, 0.878), smoothstep(0.22, 0.78, drift))
    col = mix_col(col, (0.725, 0.805, 0.865), smoothstep(0.44, 0.12, glacier) * 0.36)
    col = mix_col(col, (0.958, 0.946, 0.912), smoothstep(0.58, 0.92, sastrugi) * 0.30)
    col *= (0.972 + 0.056 * paper)[..., None]

    h = 0.48 + 0.22 * drift + 0.18 * sastrugi + 0.08 * paper
    return col, height_to_normal_rgb(h, 2.2)


def build_tile_04_mountain_rock():
    """Splat B.R — Clean directional hand-painted stratified mountain cliff rock (ZERO turtle-shell Voronoi!)."""
    # Sweeping horizontal/diagonal rock strata + chiseled watercolor cliff facets
    strata_broad = periodic_warped_wash(RES, 2, 10, 34.0, seed=5003, octaves=4)
    strata_fine = periodic_warped_wash(RES, 4, 18, 20.0, seed=5021, octaves=3)
    chisel_ridge = periodic_ridge(RES, 3, 12, 4, seed=5039)
    # Soft stepped cliff terraces
    ledge_step = np.floor(strata_broad * 5.0) / 5.0
    ledge_blend = 0.62 * strata_broad + 0.38 * periodic_blur(ledge_step, 5.0)
    # Fine watercolor strata edge line (directional, NOT polygon grid!)
    strata_ink = watercolor_edge_pool(ledge_blend)
    paper = handmade_paper_tooth(RES, seed=5099)

    col = mix_col((0.568, 0.538, 0.505), (0.818, 0.788, 0.742), ledge_blend)
    col = mix_col(col, (0.882, 0.852, 0.802), smoothstep(0.54, 0.90, chisel_ridge) * 0.40)
    col = mix_col(col, (0.495, 0.468, 0.442), smoothstep(0.44, 0.14, strata_fine) * 0.28 + strata_ink * 0.24)
    col *= (0.962 + 0.076 * paper)[..., None]

    h = 0.44 + 0.28 * ledge_blend + 0.24 * chisel_ridge + 0.12 * strata_fine + 0.06 * paper
    return col, height_to_normal_rgb(h, 3.8)


def build_tile_05_coastal_sand():
    """Splat B.G — Clean velvety warm parchment coastal sand with gentle tide ripples."""
    ripple = periodic_warped_wash(RES, 5, 12, 20.0, seed=6007, octaves=3)
    wash = periodic_warped_wash(RES, 4, 4, 30.0, seed=6037, octaves=3)
    paper = handmade_paper_tooth(RES, seed=6091)

    col = mix_col((0.858, 0.798, 0.672), (0.922, 0.872, 0.752), wash)
    col = mix_col(col, (0.802, 0.735, 0.612), smoothstep(0.54, 0.18, ripple) * 0.24)
    col *= (0.968 + 0.064 * paper)[..., None]

    h = 0.50 + 0.16 * ripple + 0.08 * paper
    return col, height_to_normal_rgb(h, 2.0)


def build_tile_06_royal_road():
    """Splat B.B — Refined sun-warmed packed limestone imperial track & subtle worn paving slabs (never giant tiles!)."""
    yy, xx = np.mgrid[0:RES, 0:RES].astype(np.float32)
    u = xx / float(RES)
    v = yy / float(RES)
    wx = (periodic_fbm(RES, 6, 6, 3, seed=7001) - 0.5) * 0.045
    wy = (periodic_fbm(RES, 6, 6, 3, seed=7019) - 0.5) * 0.045
    rows = 12.0
    cols = 8.0
    row_f = (v + wy) * rows
    row_i = np.floor(row_f).astype(np.int32) % int(rows)
    stagger = (row_i % 2) * 0.5
    col_f = (u + wx) * cols + stagger
    col_i = np.floor(col_f).astype(np.int32) % int(cols)

    fu = col_f - np.floor(col_f)
    fv = row_f - np.floor(row_f)
    du = np.minimum(fu, 1.0 - fu)
    dv = np.minimum(fv, 1.0 - fv)
    stone_edge = np.minimum(du * 1.15, dv)
    dust_cover = smoothstep(0.32, 0.78, periodic_warped_wash(RES, 4, 4, 28.0, seed=7057, octaves=3))
    # Very gentle worn limestone joints partially veiled by sunlit earth
    mortar = (1.0 - smoothstep(0.025, 0.095, stone_edge)) * (1.0 - 0.72 * dust_cover)

    rng = np.random.default_rng(7043)
    stone_tint = rng.uniform(0.0, 1.0, size=(int(rows), int(cols))).astype(np.float32)
    per_stone = stone_tint[row_i, col_i]

    wear = periodic_warped_wash(RES, 5, 5, 24.0, seed=7069, octaves=3)
    paper = handmade_paper_tooth(RES, seed=7097)

    col = mix_col((0.835, 0.782, 0.678), (0.912, 0.872, 0.782), per_stone * 0.42 + wear * 0.58)
    col = mix_col(col, (0.715, 0.648, 0.545), mortar * 0.36)
    col = mix_col(col, (0.818, 0.755, 0.638), dust_cover * 0.45)
    col *= (0.968 + 0.064 * paper)[..., None]

    h = 0.58 - 0.16 * mortar + 0.06 * per_stone + 0.08 * wear + 0.06 * paper
    return col, height_to_normal_rgb(h, 2.2)


def build_tile_07_demon_rift():
    """Splat B.A — Clean volcanic umber-slate strata with delicate matte peacock-green & dusky amethyst mineral dust."""
    wash = periodic_warped_wash(RES, 4, 4, 34.0, seed=8009, octaves=4)
    strata = periodic_ridge(RES, 3, 10, 4, seed=8039)
    mineral_vein = smoothstep(0.62, 0.88, periodic_ridge(RES, 5, 8, 3, seed=8093)) * smoothstep(0.45, 0.78, periodic_warped_wash(RES, 3, 3, 24.0, seed=8101))
    amethyst_wash = smoothstep(0.55, 0.85, periodic_warped_wash(RES, 5, 5, 22.0, seed=8117))
    paper = handmade_paper_tooth(RES, seed=8147)

    col = mix_col((0.365, 0.282, 0.248), (0.525, 0.408, 0.352), wash * 0.62 + strata * 0.38)
    col = mix_col(col, (0.315, 0.565, 0.495), mineral_vein * 0.58)
    col = mix_col(col, (0.485, 0.362, 0.455), amethyst_wash * 0.26)
    col *= (0.96 + 0.08 * paper)[..., None]

    h = 0.48 + 0.26 * strata + 0.14 * wash + 0.08 * paper
    return col, height_to_normal_rgb(h, 3.2)


def build_tile_walnut_frame():
    """Museum-grade straight-grained satin dark walnut woodgrain tile for DioramaFrame."""
    yy, xx = np.mgrid[0:RES, 0:RES].astype(np.float32)
    u = xx / float(RES)
    v = yy / float(RES)
    warp = periodic_fbm(RES, 2, 6, 4, seed=9001)
    tau = 2.0 * np.pi
    ring_phase = (v * 11.0 + warp * 1.15 + 0.12 * np.sin(u * tau)) * tau
    rings = (0.5 + 0.5 * np.sin(ring_phase)) ** 1.3
    fine_grain = periodic_fbm(RES, 4, 48, 3, seed=9041)
    pores = smoothstep(0.72, 0.94, periodic_fbm(RES, 8, 64, 2, seed=9079))

    col = mix_col((0.122, 0.068, 0.042), (0.242, 0.148, 0.088), rings * 0.68 + fine_grain * 0.32)
    col = mix_col(col, (0.078, 0.044, 0.026), pores * 0.42)

    h = 0.55 + 0.14 * rings + 0.14 * fine_grain - 0.16 * pores
    return col, height_to_normal_rgb(h, 2.2)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    builders = [
        ("tile_00_demon_wastes", build_tile_00_demon_wastes),
        ("tile_01_milis_forest", build_tile_01_milis_forest),
        ("tile_02_central_meadow", build_tile_02_central_meadow),
        ("tile_03_north_frost", build_tile_03_north_frost),
        ("tile_04_mountain_rock", build_tile_04_mountain_rock),
        ("tile_05_coastal_sand", build_tile_05_coastal_sand),
        ("tile_06_royal_road", build_tile_06_royal_road),
        ("tile_07_demon_rift", build_tile_07_demon_rift),
        ("tile_walnut_frame", build_tile_walnut_frame),
    ]

    thumbs_alb = []
    thumbs_nrm = []
    for name, fn in builders:
        alb_f, nrm_f = fn()
        alb_u8 = to_u8_rgba(alb_f)
        nrm_u8 = to_u8_rgba(nrm_f)
        verify_seamless(alb_u8, name + "_albedo")
        verify_seamless(nrm_u8, name + "_normal")
        write_png_rgba8(OUT_DIR / f"{name}_albedo.png", alb_u8)
        write_png_rgba8(OUT_DIR / f"{name}_normal.png", nrm_u8)
        print(f"  Generated seamless 512x512: {name}_albedo.png & {name}_normal.png", flush=True)
        # Downsample 2x2 for a compact 2x2 tiled inspection preview (shows seam junctions dead-center!)
        a_half = alb_u8[::2, ::2, :]
        n_half = nrm_u8[::2, ::2, :]
        thumbs_alb.append(np.tile(a_half, (2, 2, 1))[::2, ::2, :])  # 256x256 showing 2x2 wrap!
        thumbs_nrm.append(np.tile(n_half, (2, 2, 1))[::2, ::2, :])

    # Assemble visual QA contact sheet (Row 1: first 5 Albedos, Row 2: first 5 Normals, Row 3: last 4 Albedos + blank, Row 4: last 4 Normals + blank)
    pad = 8
    tile_sz = 256
    cols = 5
    rows = 4
    sheet = np.full((rows * tile_sz + (rows + 1) * pad, cols * tile_sz + (cols + 1) * pad, 4), [34, 24, 18, 255], dtype=np.uint8)

    def blit(row: int, col: int, tile: np.ndarray) -> None:
        y0 = pad + row * (tile_sz + pad)
        x0 = pad + col * (tile_sz + pad)
        sheet[y0:y0 + tile_sz, x0:x0 + tile_sz, :] = tile

    for idx in range(5):
        blit(0, idx, thumbs_alb[idx])
        blit(1, idx, thumbs_nrm[idx])
    for idx in range(5, len(builders)):
        blit(2, idx - 5, thumbs_alb[idx])
        blit(3, idx - 5, thumbs_nrm[idx])

    write_png_rgba8(PREVIEW_PATH, sheet)
    print(f"All {len(builders)} seamless tile pairs + contact sheet written to {OUT_DIR}", flush=True)


if __name__ == "__main__":
    main()
