"""Headless Blender Cycles baker for M4 Baked Global AO + Ridge Curvature + City/Cliff Contact Shadow.

Does NOT modify world_relief_world.glb geometry or heightmaps! Reads TerrainSurface from
assets/3d/world_v2/world_relief_world.glb and world_heightmap.png + world_relief_meta.json,
bakes physical Cycles AO on CPU, computes multi-scale ridge curvature & city contact shadows,
and writes lossless 2048x1024 RGBA8 PNG:
    assets/textures/world_v2/world_ao_curvature.png
    tools/blender_world_v2/previews/world_ao_curvature_preview.png

Run from repository root:
    /Users/mac/.local/bin/blender --background --python tools/blender_world_v2/bake_world_ao_curvature.py
"""

import json
import math
from pathlib import Path
import struct
import zlib

import bpy
import numpy as np


ROOT = Path(__file__).resolve().parents[2]
IN_GLB = ROOT / "assets/3d/world_v2/world_relief_world.glb"
IN_HEIGHT_PNG = ROOT / "assets/textures/world_v2/world_heightmap.png"
IN_META_JSON = ROOT / "data/maps/world_relief_meta.json"
OUT_PNG = ROOT / "assets/textures/world_v2/world_ao_curvature.png"
OUT_PREVIEW = Path(__file__).resolve().parent / "previews/world_ao_curvature_preview.png"

TEX_W, TEX_H = 2048, 1024


# ---------------------------------------------------------------------------
# Lossless PNG I/O (16-bit gray reader & 8-bit RGBA writer, zero sRGB drift)
# ---------------------------------------------------------------------------
def read_png_u16_gray(path: Path) -> np.ndarray:
    blob = path.read_bytes()
    assert blob[:8] == b"\x89PNG\r\n\x1a\n"
    pos = 8
    w = h = bit_depth = color_type = 0
    idat_parts = []
    while pos < len(blob):
        length, ctype = struct.unpack_from(">I4s", blob, pos)
        payload = blob[pos + 8:pos + 8 + length]
        pos += 12 + length
        if ctype == b"IHDR":
            w, h, bit_depth, color_type, _, _, _ = struct.unpack(">IIBBBBB", payload)
        elif ctype == b"IDAT":
            idat_parts.append(payload)
        elif ctype == b"IEND":
            break
    assert bit_depth == 16 and color_type == 0, f"Unexpected format: {bit_depth}-bit type {color_type}"
    raw = zlib.decompress(b"".join(idat_parts))
    stride = 1 + w * 2
    rows = np.frombuffer(raw, dtype=np.uint8).reshape(h, stride)
    # Reconstruct standard PNG scanline filters (supports 0=None, 1=Sub, 2=Up) if present
    filters = rows[:, 0]
    if np.all(filters == 0):
        pixels_u16 = np.frombuffer(np.ascontiguousarray(rows[:, 1:]), dtype=">u2").reshape(h, w)
        return pixels_u16.astype(np.float32) / 65535.0
    raise RuntimeError(f"Unsupported PNG row filter in {path.name}: {np.unique(filters)}")


def write_png_rgba8(path: Path, rgba_u8: np.ndarray) -> None:
    h, w, c = rgba_u8.shape
    assert c == 4
    arr = np.ascontiguousarray(rgba_u8, dtype=np.uint8).reshape(h, w * 4)
    raw_rows = np.concatenate([np.zeros((h, 1), dtype=np.uint8), arr], axis=1)

    def chunk(tag: bytes, payload: bytes) -> bytes:
        crc = zlib.crc32(tag + payload) & 0xFFFFFFFF
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw_rows.tobytes(), 6)) + chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def gaussian_blur_np(arr: np.ndarray, sigma: float) -> np.ndarray:
    """Fast separable 2D Gaussian blur in pure NumPy (clamp border mode)."""
    if sigma <= 0.15:
        return arr.astype(np.float32)
    rad = int(math.ceil(sigma * 2.5))
    x = np.arange(-rad, rad + 1, dtype=np.float32)
    k = np.exp(-0.5 * (x / sigma) ** 2)
    k /= np.sum(k)

    # Horizontal
    pad_h = np.pad(arr, ((0, 0), (rad, rad)), mode="edge")
    out_h = np.zeros_like(arr, dtype=np.float32)
    for i, w_val in enumerate(k):
        out_h += pad_h[:, i:i + arr.shape[1]] * w_val

    # Vertical
    pad_v = np.pad(out_h, ((rad, rad), (0, 0)), mode="edge")
    out_v = np.zeros_like(arr, dtype=np.float32)
    for i, w_val in enumerate(k):
        out_v += pad_v[i:i + arr.shape[0], :] * w_val
    return out_v


def smoothstep_np(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# ---------------------------------------------------------------------------
# 1. Blender Cycles Physical AO Bake on TerrainSurface
# ---------------------------------------------------------------------------
def bake_cycles_global_ao() -> np.ndarray:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    res = bpy.ops.import_scene.gltf(filepath=str(IN_GLB))
    assert "FINISHED" in res, f"Failed importing {IN_GLB}"

    terrain_obj = None
    to_remove = []
    for obj in list(bpy.data.objects):
        if obj.type == "MESH" and "TerrainSurface" in obj.name:
            terrain_obj = obj
        else:
            to_remove.append(obj)
    assert terrain_obj is not None, "TerrainSurface not found inside world_relief_world.glb!"
    for obj in to_remove:
        bpy.data.objects.remove(obj, do_unlink=True)

    # Prepare float image target for lossless Cycles bake (no color-management squash before readback)
    bake_img = bpy.data.images.new("CyclesAO_Target", width=TEX_W, height=TEX_H, alpha=False, float_buffer=True)
    bake_img.colorspace_settings.name = "Non-Color"

    mat = bpy.data.materials.new("CyclesAOBakeMat")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    ao_node = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao_node.samples = 24
    ao_node.only_local = False
    ao_node.inputs["Distance"].default_value = 0.85

    em_node = nt.nodes.new("ShaderNodeEmission")
    em_node.inputs["Strength"].default_value = 1.0
    out_node = nt.nodes.new("ShaderNodeOutputMaterial")

    tex_node = nt.nodes.new("ShaderNodeTexImage")
    tex_node.image = bake_img
    nt.nodes.active = tex_node

    nt.links.new(ao_node.outputs["AO"], em_node.inputs["Color"])
    nt.links.new(em_node.outputs["Emission"], out_node.inputs["Surface"])

    terrain_obj.data.materials.clear()
    terrain_obj.data.materials.append(mat)

    for o in bpy.context.selected_objects:
        o.select_set(False)
    terrain_obj.select_set(True)
    bpy.context.view_layer.objects.active = terrain_obj

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    scene.cycles.use_denoising = False
    scene.cycles.bake_type = "EMIT"
    scene.render.bake.margin = 6
    scene.render.bake.use_clear = True

    print("Baking 2048x1024 physical Global AO with Cycles CPU on TerrainSurface...", flush=True)
    bake_res = bpy.ops.object.bake(type="EMIT")
    assert "FINISHED" in bake_res, f"Cycles bake failed: {bake_res}"

    px = np.array(bake_img.pixels[:], dtype=np.float32).reshape(TEX_H, TEX_W, 4)
    # Blender images store bottom-up; flip vertically to match glTF/PNG top-down (UV v=0 North top)
    ao_topdown = np.flipud(px[:, :, 0]).copy()
    print(f"Cycles raw AO range: [{float(np.min(ao_topdown)):.4f}, {float(np.max(ao_topdown)):.4f}], mean={float(np.mean(ao_topdown)):.4f}", flush=True)
    return np.clip(ao_topdown, 0.0, 1.0)


# ---------------------------------------------------------------------------
# 2. Combine Physical Cycles AO + Multi-Scale Heightmap Curvature + 19-City Contact Shadows
# ---------------------------------------------------------------------------
def build_ao_curvature_texture() -> None:
    meta = json.loads(IN_META_JSON.read_text(encoding="utf-8"))
    hrange = meta["height_range"]
    min_h = float(hrange["min_height"])
    max_h = float(hrange["max_height"])
    bounds = meta["world_bounds"]
    min_x, max_x = float(bounds["min_x"]), float(bounds["max_x"])
    min_z, max_z = float(bounds["min_z"]), float(bounds["max_z"])
    world_w = max_x - min_x
    world_d = max_z - min_z

    h_norm = read_png_u16_gray(IN_HEIGHT_PNG)
    assert h_norm.shape == (TEX_H, TEX_W), f"Heightmap shape {h_norm.shape} != {(TEX_H, TEX_W)}"
    height = min_h + h_norm * (max_h - min_h)

    cycles_ao = bake_cycles_global_ao()

    # Smooth subtle low-poly mesh facet ripple on Cycles AO while keeping valley/canyon occlusion deep
    cycles_ao_smooth = gaussian_blur_np(cycles_ao, 2.2)
    # Heightmap-derived crisp horizon cavity AO (sub-triangle creases)
    h_b4 = gaussian_blur_np(height, 4.5)
    h_b12 = gaussian_blur_np(height, 13.0)
    cavity = np.clip((h_b4 - height) * 5.2 + (h_b12 - height) * 2.1, 0.0, 1.0)
    horizon_ao = 1.0 - cavity * 0.62

    land_mask = smoothstep_np(-0.02, 0.04, height)
    # R channel: deep articulated canyon/basin/cliff occlusion
    ao_combined = np.clip((cycles_ao_smooth ** 1.45) * 0.78 + horizon_ao * 0.22, 0.0, 1.0)
    r_ao = np.where(land_mask > 0.01, 1.0 - (1.0 - ao_combined) * land_mask, 1.0)

    # G channel: multi-scale chiseled ridge (> 0.5) & gorge crease (< 0.5) curvature
    h_b2 = gaussian_blur_np(height, 2.0)
    h_b6 = gaussian_blur_np(height, 6.0)
    h_b16 = gaussian_blur_np(height, 15.0)
    laplacian = 0.42 * (height - h_b2) + 0.36 * (height - h_b6) + 0.22 * (height - h_b16)
    g_raw = 0.5 + 0.48 * np.tanh(laplacian * 28.0)
    g_curv = 0.5 + (g_raw - 0.5) * land_mask

    # B channel: grounded 19-city plinth contact shadows + steep cliff shoreline footing shadow
    gy, gx = np.gradient(height, world_d / float(TEX_H - 1), world_w / float(TEX_W - 1))
    slope = np.hypot(gx, gy)

    xs = np.linspace(min_x, max_x, TEX_W, dtype=np.float32)
    zs = np.linspace(min_z, max_z, TEX_H, dtype=np.float32)
    xx, zz = np.meshgrid(xs, zs)

    contact = np.ones((TEX_H, TEX_W), dtype=np.float32)
    cities = meta.get("cities", {})
    for node_id, info in cities.items():
        pos = info["position"]
        cx, cz = float(pos[0]), float(pos[2])
        # Match GDScript CITY_GLOBAL_SCALE (0.76) / CITY_STRAIT_PORT_SCALE (0.70) plinth footprint (~0.17..0.22 outer radius)
        is_strait_port = node_id in ("city_wind_port", "city_zanto_port")
        approx_outer_r = (0.175 if is_strait_port else 0.195)
        d = np.hypot(xx - cx, zz - cz)
        # Soft grounded ambient shadow directly under and hugging stone plinth perimeter
        city_sh = 0.58 + 0.42 * smoothstep_np(approx_outer_r * 0.55, approx_outer_r * 1.48, d)
        contact = np.minimum(contact, city_sh)

    # Coastal bluff footing shadow right above shoreline where cliffs drop into sea
    coast_foot = smoothstep_np(0.0, 0.045, height) * (1.0 - smoothstep_np(0.055, 0.16, height)) * smoothstep_np(0.32, 0.95, slope)
    contact *= (1.0 - 0.24 * coast_foot)
    b_contact = np.clip(contact, 0.0, 1.0)

    rgba_f = np.stack([r_ao, g_curv, b_contact, np.ones_like(r_ao)], axis=-1)
    rgba_u8 = np.clip(np.round(rgba_f * 255.0), 0, 255).astype(np.uint8)
    write_png_rgba8(OUT_PNG, rgba_u8)

    # Diagnostic sanity check on real landmark regions (North-South alignment check!)
    mig_px = cities["city_migurd"]["pixel"]
    mix_x = int(np.clip(round((cities["city_migurd"]["position"][0] - min_x) / world_w * (TEX_W - 1)), 0, TEX_W - 1))
    mix_y = int(np.clip(round((cities["city_migurd"]["position"][2] - min_z) / world_d * (TEX_H - 1)), 0, TEX_H - 1))
    jaw_x = int(np.clip(round((cities["city_red_dragon_jaw"]["position"][0] - min_x) / world_w * (TEX_W - 1)), 0, TEX_W - 1))
    jaw_y = int(np.clip(round((cities["city_red_dragon_jaw"]["position"][2] - min_z) / world_d * (TEX_H - 1)), 0, TEX_H - 1))
    print(
        f"Baked PNG -> {OUT_PNG.name} ({TEX_W}x{TEX_H}) | R(AO)=[{float(np.min(r_ao)):.3f}, 1.000] G(Curv)=[{float(np.min(g_curv)):.3f}, {float(np.max(g_curv)):.3f}] B(Contact)=[{float(np.min(b_contact)):.3f}, 1.000]",
        flush=True,
    )
    print(
        f"  Alignment check -> Migurd center (B={b_contact[mix_y, mix_x]:.3f}, R={r_ao[mix_y, mix_x]:.3f}), RedDragonJaw center (B={b_contact[jaw_y, jaw_x]:.3f}, R={r_ao[jaw_y, jaw_x]:.3f})",
        flush=True,
    )

    # Render clean diagnostic 2x2 quad preview (downsampled 1024x512 -> quad 1024x512 RGB, AO, Curv, Contact)
    hw, hh = TEX_W // 2, TEX_H // 2
    r_half = rgba_u8[::2, ::2, 0]
    g_half = rgba_u8[::2, ::2, 1]
    b_half = rgba_u8[::2, ::2, 2]
    rgb_half = rgba_u8[::2, ::2, :3]

    q_ao = np.stack([r_half, r_half, r_half], axis=-1)
    q_curv = np.stack([g_half, g_half, g_half], axis=-1)
    q_cont = np.stack([b_half, b_half, b_half], axis=-1)
    top_row = np.concatenate([rgb_half, q_ao], axis=1)
    bot_row = np.concatenate([q_curv, q_cont], axis=1)
    quad_rgb = np.concatenate([top_row, bot_row], axis=0)
    quad_rgba = np.concatenate([quad_rgb, np.full((hh * 2, hw * 2, 1), 255, dtype=np.uint8)], axis=-1)
    write_png_rgba8(OUT_PREVIEW, quad_rgba)
    print(f"AO+Curvature 4-panel preview written -> {OUT_PREVIEW}", flush=True)


if __name__ == "__main__":
    build_ao_curvature_texture()
