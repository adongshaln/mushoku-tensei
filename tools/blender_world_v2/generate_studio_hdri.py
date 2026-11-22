"""Generate a procedural 1024x512 Museum Diorama Studio HDRI (.hdr) & tone-mapped preview PNG.

Run from repository root:
    /Users/mac/.local/bin/blender --background --python tools/blender_world_v2/generate_studio_hdri.py
(or `python3 tools/blender_world_v2/generate_studio_hdri.py` if numpy is installed)

Outputs:
    assets/textures/world_v2/diorama_studio_env.hdr
    tools/blender_world_v2/previews/diorama_studio_env_preview.png
"""

import math
from pathlib import Path
import struct
import zlib

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
OUT_HDR = ROOT / "assets/textures/world_v2/diorama_studio_env.hdr"
OUT_PREVIEW = Path(__file__).resolve().parent / "previews/diorama_studio_env_preview.png"

W, H = 1024, 512


def smoothstep(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
    denom = edge1 - edge0
    if abs(denom) < 1e-8:
        return np.where(x >= edge0, 1.0, 0.0).astype(np.float32)
    t = np.clip((x - edge0) / denom, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def wrap_angle_diff(a: np.ndarray, b: float) -> np.ndarray:
    return np.arctan2(np.sin(a - b), np.cos(a - b))


def write_radiance_hdr(path: Path, rgb_linear: np.ndarray) -> None:
    """Write standard 32-bit Radiance .hdr (RGBE) readable by Godot & Blender."""
    h, w, c = rgb_linear.shape
    assert c == 3
    img = np.maximum(rgb_linear, 0.0).astype(np.float32)
    max_val = np.max(img, axis=2)

    mantissa, exponent = np.frexp(max_val)
    scale = np.zeros_like(max_val, dtype=np.float32)
    nz = max_val >= 1e-32
    scale[nz] = (mantissa[nz] * 256.0) / max_val[nz]

    rgbe = np.zeros((h, w, 4), dtype=np.uint8)
    rgbe[:, :, 0] = np.clip(np.floor(img[:, :, 0] * scale), 0, 255).astype(np.uint8)
    rgbe[:, :, 1] = np.clip(np.floor(img[:, :, 1] * scale), 0, 255).astype(np.uint8)
    rgbe[:, :, 2] = np.clip(np.floor(img[:, :, 2] * scale), 0, 255).astype(np.uint8)
    rgbe[nz, 3] = np.clip(exponent[nz] + 128, 0, 255).astype(np.uint8)

    # Guard against accidental stbi RLE magic trigger (2,2,H,L) on raw scanlines
    first_col_mask = (rgbe[:, 0, 0] == 2) & (rgbe[:, 0, 1] == 2) & ((rgbe[:, 0, 2] & 0x80) == 0)
    if np.any(first_col_mask):
        rgbe[first_col_mask, 0, 0] = 3

    header = (
        "#?RADIANCE\n"
        "# Procedural Diorama Studio HDRI for World Atlas M4\n"
        "FORMAT=32-bit_rle_rgbe\n\n"
        f"-Y {h} +X {w}\n"
    ).encode("ascii")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + rgbe.tobytes())


def write_png_rgba8(path: Path, rgba_u8: np.ndarray) -> None:
    h, w, _ = rgba_u8.shape
    raw_rows = np.concatenate([np.zeros((h, 1), dtype=np.uint8), rgba_u8.reshape(h, w * 4)], axis=1)

    def chunk(tag: bytes, payload: bytes) -> bytes:
        crc = zlib.crc32(tag + payload) & 0xFFFFFFFF
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw_rows.tobytes(), 6)) + chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def generate_studio_panorama() -> np.ndarray:
    u = (np.arange(W, dtype=np.float32) + 0.5) / float(W)
    v = (np.arange(H, dtype=np.float32) + 0.5) / float(H)
    uu, vv = np.meshgrid(u, v)

    # Equirectangular angles matching Godot PanoramaSkyMaterial
    az = (uu - 0.5) * math.tau            # [-pi .. +pi]
    el = (0.5 - vv) * math.pi             # [+pi/2 zenith .. -pi/2 nadir]

    cos_el = np.cos(el)
    dx = cos_el * np.sin(az)
    dy = np.sin(el)
    dz = cos_el * np.cos(az)

    # 1. Base Studio Museum Room Dome (warm soft upper dome + dark walnut floor bounce)
    up_t = smoothstep(-0.06, 0.45, dy)
    zenith_t = smoothstep(0.15, 0.92, dy)
    lower_t = smoothstep(0.05, -0.78, dy)

    floor_dark = np.array([0.075, 0.050, 0.036], dtype=np.float32)
    desk_walnut = np.array([0.24, 0.165, 0.112], dtype=np.float32)
    horizon_vellum = np.array([0.62, 0.54, 0.44], dtype=np.float32)
    sky_loft = np.array([0.34, 0.41, 0.53], dtype=np.float32)

    env = np.zeros((H, W, 3), dtype=np.float32)
    for c in range(3):
        upper_c = horizon_vellum[c] * (1.0 - zenith_t) + sky_loft[c] * zenith_t
        lower_c = desk_walnut[c] * (1.0 - lower_t) + floor_dark[c] * lower_t
        env[:, :, c] = lower_c * (1.0 - up_t) + upper_c * up_t

    # Soft museum warm ambient bounce belt around horizon (dy in [-0.15..0.28])
    belt = np.exp(-((el - 0.04) / 0.24) ** 2)
    env += belt[:, :, None] * np.array([0.22, 0.17, 0.11], dtype=np.float32)[None, None, :]

    # 2. Primary Studio Warm-Amber Softbox (Upper-Left-Front, aligned with Key DirectionalLight)
    key_az = math.radians(-42.0)
    key_el = math.radians(38.0)
    d_az_k = wrap_angle_diff(az, key_az)
    d_el_k = el - key_el
    softbox_u = smoothstep(0.68, 0.26, np.abs(d_az_k))
    softbox_v = smoothstep(0.42, 0.14, np.abs(d_el_k))
    key_box = softbox_u * softbox_v
    key_core = np.exp(-((d_az_k / 0.34) ** 2 + (d_el_k / 0.22) ** 2))
    # Subtle softbox frame gradient + warm specular diffuser
    key_col = np.array([4.95, 3.82, 2.38], dtype=np.float32)
    env += (key_box * 0.78 + key_core * 0.48)[:, :, None] * key_col[None, None, :]

    # Fine bright catchlight edge strip inside key softbox for crisp antique brass bevel highlights
    bevel_strip = smoothstep(0.45, 0.15, np.abs(d_az_k)) * np.exp(-((el - math.radians(48.0)) / 0.065) ** 2)
    env += bevel_strip[:, :, None] * np.array([2.85, 2.30, 1.50], dtype=np.float32)[None, None, :]

    # 3. Cool Sea-Mist Rim Strip Reflector (Upper-Right-Back, carving crisp porcelain/metal contours)
    rim_az = math.radians(136.0)
    rim_el = math.radians(26.0)
    d_az_r = wrap_angle_diff(az, rim_az)
    d_el_r = el - rim_el
    rim_strip = smoothstep(0.95, 0.36, np.abs(d_az_r)) * smoothstep(0.28, 0.09, np.abs(d_el_r))
    rim_core = np.exp(-((d_az_r / 0.56) ** 2 + (d_el_r / 0.14) ** 2))
    rim_col = np.array([1.38, 2.08, 3.05], dtype=np.float32)
    env += (rim_strip * 0.72 + rim_core * 0.45)[:, :, None] * rim_col[None, None, :]

    # 4. Soft Overhead Diffuser Dome (gentle top fill on flat parchment roofs & water)
    overhead = smoothstep(math.radians(52.0), math.radians(78.0), el)
    env += overhead[:, :, None] * np.array([0.85, 0.84, 0.80], dtype=np.float32)[None, None, :]

    # Subtle directional noise sheen breakdown (prevents banding in flat ocean mirror reflections)
    rng = np.random.default_rng(4180401)
    dither = rng.normal(0.0, 0.004, size=(H, W, 1)).astype(np.float32)
    env = np.maximum(env + dither, 0.005)
    return env


def save_tonemapped_preview(hdr_linear: np.ndarray, path: Path) -> None:
    # Reinhard/film-like curve mapped to sRGB8 for crisp human inspection
    x = hdr_linear * 0.85
    mapped = x / (1.0 + x)
    # Apply slight highlight saturation retention + sRGB gamma
    srgb = np.where(mapped <= 0.0031308, mapped * 12.92, 1.055 * (np.maximum(mapped, 0.0) ** (1.0 / 2.4)) - 0.055)
    rgb8 = np.clip(np.round(srgb * 255.0), 0, 255).astype(np.uint8)
    alpha = np.full((H, W, 1), 255, dtype=np.uint8)
    write_png_rgba8(path, np.concatenate([rgb8, alpha], axis=2))


def main() -> None:
    pano = generate_studio_panorama()
    assert np.all(np.isfinite(pano)), "Studio HDRI contains NaN or Inf!"
    luma = 0.2126 * pano[:, :, 0] + 0.7152 * pano[:, :, 1] + 0.0722 * pano[:, :, 2]
    max_l = float(np.max(luma))
    min_l = float(np.min(luma))
    mean_l = float(np.mean(luma))
    assert max_l > 3.5, f"Expected HDR key luminance > 3.5, got {max_l:.3f}"

    write_radiance_hdr(OUT_HDR, pano)
    save_tonemapped_preview(pano, OUT_PREVIEW)
    print(
        f"Studio HDRI written -> {OUT_HDR.name} ({W}x{H}, {OUT_HDR.stat().st_size:,} B) | Luma min={min_l:.4f}, mean={mean_l:.3f}, max={max_l:.2f}",
        flush=True,
    )


if __name__ == "__main__":
    main()
