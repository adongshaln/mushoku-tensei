"""Build four museum-grade 3D travel gear props (.glb) and studio proofs with headless Blender.

Usage: blender --background --python tools/blender_props/build_travel_gear_ag.py
Coordinates: Blender Z-up tabletop pose; glTF exporter converts to Y-up.
Each exported .glb is strictly watertight, centered at (0, 0, 0), normalized to
max extent 0.96 units, and within 3,000-9,000 triangles.
"""

import json
import math
from pathlib import Path
import struct
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.geometry import tessellate_polygon

ROOT = Path(__file__).resolve().parents[2]
PROPS_DIR = ROOT / "assets/3d/props"
PREVIEWS_DIR = Path(__file__).resolve().parent / "previews"
TARGET_EXTENT = 0.96
TAU = math.tau

sys.dont_write_bytecode = True


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgba(code, alpha=1.0):
    code = code.lstrip("#")
    return tuple(srgb_to_linear(int(code[i:i + 2], 16) / 255.0) for i in (0, 2, 4)) + (alpha,)


def hex_srgb(code):
    code = code.lstrip("#")
    return np.array([int(code[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def angles(n, start=0.0):
    return [start + TAU * i / n for i in range(n)]


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def smoothstep(edge0, edge1, x):
    t = clamp((x - edge0) / (edge1 - edge0 + 1e-12), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def catmull_rom(pts, samples_per_seg=8):
    """Smooth spline interpolation through control points."""
    p = [Vector(pt) for pt in pts]
    if len(p) < 2:
        return p
    ext = [p[0] + (p[0] - p[1])] + p + [p[-1] + (p[-1] - p[-2])]
    out = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        n = samples_per_seg
        for s in range(n):
            t = s / n
            t2, t3 = t * t, t * t * t
            pt = 0.5 * (
                (2.0 * p1)
                + (-p0 + p2) * t
                + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
                + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
            )
            out.append(pt)
    out.append(p[-1])
    return out


# ---------------------------------------------------------------------------
# Procedural Tileable PBR Textures (Compact 256x256 Packed PNGs via NumPy)
# ---------------------------------------------------------------------------

def _tile_noise(size, freq, seed):
    rng = np.random.default_rng(seed)
    grid = rng.random((freq, freq), dtype=np.float32)
    u = np.linspace(0.0, freq, size, endpoint=False, dtype=np.float32)
    v = np.linspace(0.0, freq, size, endpoint=False, dtype=np.float32)
    ix = np.floor(u).astype(np.int32)
    iy = np.floor(v).astype(np.int32)
    fx = u - ix
    fy = v - iy
    sx = fx * fx * (3.0 - 2.0 * fx)
    sy = fy * fy * (3.0 - 2.0 * fy)
    x0, x1 = ix % freq, (ix + 1) % freq
    y0, y1 = iy % freq, (iy + 1) % freq
    g00 = grid[y0[:, None], x0[None, :]]
    g10 = grid[y0[:, None], x1[None, :]]
    g01 = grid[y1[:, None], x0[None, :]]
    g11 = grid[y1[:, None], x1[None, :]]
    top = g00 * (1.0 - sx[None, :]) + g10 * sx[None, :]
    bot = g01 * (1.0 - sx[None, :]) + g11 * sx[None, :]
    return top * (1.0 - sy[:, None]) + bot * sy[:, None]


def _fbm(size, freqs, weights, seed):
    acc = np.zeros((size, size), dtype=np.float32)
    total = 0.0
    for idx, (f, w) in enumerate(zip(freqs, weights)):
        acc += _tile_noise(size, f, seed + idx * 97) * w
        total += w
    return acc / max(total, 1e-6)


def _height_to_normal(height, strength=2.0):
    gx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5 * strength
    gy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5 * strength
    nx, ny = -gx, -gy
    nz = np.ones_like(height)
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx * inv * 0.5 + 0.5, ny * inv * 0.5 + 0.5, nz * inv * 0.5 + 0.5], axis=-1)
    return np.clip(rgb, 0.0, 1.0)


def _pack_image(name, rgb_or_gray, colorspace="sRGB"):
    h, w = rgb_or_gray.shape[:2]
    if rgb_or_gray.ndim == 2:
        rgba = np.stack([rgb_or_gray, rgb_or_gray, rgb_or_gray, np.ones((h, w), dtype=np.float32)], axis=-1)
    elif rgb_or_gray.shape[2] == 3:
        rgba = np.concatenate([rgb_or_gray, np.ones((h, w, 1), dtype=np.float32)], axis=-1)
    else:
        rgba = rgb_or_gray
    img = bpy.data.images.new(name, width=w, height=h, alpha=(rgba.shape[2] == 4 and colorspace == "sRGB"))
    img.colorspace_settings.name = colorspace
    img.pixels.foreach_set(np.clip(rgba, 0.0, 1.0).ravel())
    img.update()
    img.pack()
    return img


def _make_pbr_mat(name, base_hex, roughness=0.5, metallic=0.0, coat=0.0,
                  albedo_arr=None, rough_arr=None, height_arr=None, normal_strength=0.45,
                  emission_hex=None, emission_strength=0.0, alpha=1.0, alpha_blend=False,
                  uv_scale=1.0):
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    nt = mat.node_tree
    nodes = nt.nodes
    links = nt.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = hex_rgba(base_hex)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = coat
    if "Alpha" in bsdf.inputs:
        bsdf.inputs["Alpha"].default_value = alpha
    if alpha_blend:
        mat.blend_method = "BLEND"
        mat.use_backface_culling = True
        if hasattr(mat, "shadow_method"):
            mat.shadow_method = "NONE"
    if emission_hex is not None and emission_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = hex_rgba(emission_hex)
        bsdf.inputs["Emission Strength"].default_value = emission_strength

    mapping = None
    if any(x is not None for x in (albedo_arr, rough_arr, height_arr)):
        tc = nodes.new("ShaderNodeTexCoord")
        mapping = nodes.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value = (uv_scale, uv_scale, 1.0)
        links.new(tc.outputs["UV"], mapping.inputs["Vector"])

    if albedo_arr is not None:
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = _pack_image(f"{name}_albedo", albedo_arr, "sRGB")
        links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
        links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])

    if rough_arr is not None:
        tex_r = nodes.new("ShaderNodeTexImage")
        tex_r.image = _pack_image(f"{name}_rough", rough_arr, "Non-Color")
        links.new(mapping.outputs["Vector"], tex_r.inputs["Vector"])
        links.new(tex_r.outputs["Color"], bsdf.inputs["Roughness"])

    if height_arr is not None:
        nrm_arr = _height_to_normal(height_arr, strength=2.4)
        tex_n = nodes.new("ShaderNodeTexImage")
        tex_n.image = _pack_image(f"{name}_normal", nrm_arr, "Non-Color")
        nrm_node = nodes.new("ShaderNodeNormalMap")
        nrm_node.inputs["Strength"].default_value = normal_strength
        links.new(mapping.outputs["Vector"], tex_n.inputs["Vector"])
        links.new(tex_n.outputs["Color"], nrm_node.inputs["Color"])
        links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])

    return mat


def build_material_library():
    """Shared cohesive light-novel collectible PBR material library."""
    sz = 256
    u = np.linspace(0.0, 1.0, sz, endpoint=False, dtype=np.float32)
    v = np.linspace(0.0, 1.0, sz, endpoint=False, dtype=np.float32)
    uu, vv = np.meshgrid(u, v)

    # 1. Fine pebbled leather (used for grimoire blue-leather & oiled brown leather)
    pebble = _fbm(sz, [8, 16, 32, 64], [0.22, 0.30, 0.30, 0.18], seed=101)
    crease = _fbm(sz, [4, 8, 16], [0.5, 0.35, 0.15], seed=107)
    leather_h = 0.65 * pebble + 0.35 * crease

    def leather_mat(name, lo_hex, hi_hex, rough_lo, rough_hi, coat=0.14, nrm_s=0.38, scale=2.2):
        lo, hi = hex_srgb(lo_hex), hex_srgb(hi_hex)
        mix = np.clip((leather_h - 0.25) / 0.55, 0.0, 1.0)[..., None]
        alb = lo * (1.0 - mix) + hi * mix
        rgh = np.clip(rough_hi - (rough_hi - rough_lo) * (leather_h - 0.2) / 0.65, rough_lo, rough_hi)
        return _make_pbr_mat(name, hi_hex, roughness=0.5 * (rough_lo + rough_hi), coat=coat,
                             albedo_arr=alb, rough_arr=rgh, height_arr=leather_h,
                             normal_strength=nrm_s, uv_scale=scale)

    # 2. Layered parchment page edges (fine horizontal deckled sheets along V)
    sheets = 0.5 + 0.5 * np.sin(TAU * (vv * 72.0 + 0.22 * _fbm(sz, [4, 8], [0.6, 0.4], seed=211)))
    sheet_var = _fbm(sz, [4, 16, 48], [0.35, 0.35, 0.30], seed=219)
    page_h = 0.76 * sheets + 0.24 * sheet_var
    p_dark, p_light = hex_srgb("A88E67"), hex_srgb("F2E6CC")
    p_mix = np.clip(0.18 + 0.68 * sheets + 0.20 * (sheet_var - 0.5), 0.0, 1.0)[..., None]
    page_alb = p_dark * (1.0 - p_mix) + p_light * p_mix
    page_rgh = np.clip(0.88 - 0.16 * sheets, 0.68, 0.92)

    # 3. Coarse burlap / linen weave (ration bundle)
    warp = 0.5 + 0.5 * np.sin(TAU * (uu * 42.0 + 0.15 * np.sin(TAU * vv * 6.0)))
    weft = 0.5 + 0.5 * np.sin(TAU * (vv * 42.0 + 0.15 * np.sin(TAU * uu * 6.0)))
    checker = ((np.floor(uu * 42.0) + np.floor(vv * 42.0)) % 2.0)
    weave = np.where(checker > 0.5, warp, weft)
    linen_var = _fbm(sz, [4, 12, 32], [0.45, 0.35, 0.20], seed=307)
    linen_h = 0.55 * weave + 0.45 * linen_var
    l_lo, l_hi = hex_srgb("A98F6C"), hex_srgb("D5BE9A")
    l_mix = np.clip(0.20 + 0.55 * linen_var + 0.30 * (weave - 0.5), 0.0, 1.0)[..., None]
    linen_alb = l_lo * (1.0 - l_mix) + l_hi * l_mix
    linen_rgh = np.clip(0.82 + 0.12 * (1.0 - weave), 0.78, 0.95)

    # 4. Soft felted sea-mist wool cloth (cloak outer)
    wool_n = _fbm(sz, [6, 18, 48, 96], [0.28, 0.28, 0.26, 0.18], seed=409)
    wool_twill = 0.5 + 0.5 * np.sin(TAU * ((uu + vv) * 44.0))
    wool_h = 0.72 * wool_n + 0.28 * wool_twill
    w_lo, w_hi = hex_srgb("325772"), hex_srgb("5281A3")
    w_mix = np.clip(0.24 + 0.64 * wool_n + 0.15 * (wool_twill - 0.5), 0.0, 1.0)[..., None]
    wool_alb = w_lo * (1.0 - w_mix) + w_hi * w_mix
    wool_rgh = np.clip(0.86 + 0.10 * (1.0 - wool_n), 0.82, 0.96)

    # 5. Warm parchment cotton lining (cloak interior)
    cot_n = _fbm(sz, [6, 20, 48], [0.4, 0.35, 0.25], seed=433)
    c_lo, c_hi = hex_srgb("D7C39F"), hex_srgb("EFE1C6")
    cot_alb = c_lo * (1.0 - cot_n[..., None]) + c_hi * cot_n[..., None]
    cot_rgh = np.clip(0.80 + 0.10 * (1.0 - cot_n), 0.76, 0.92)

    # 6. Aged antique brass brushed micro-grain
    br_streak = _fbm(sz, [4, 16, 48], [0.4, 0.35, 0.25], seed=509)
    br_fine = 0.5 + 0.5 * np.sin(TAU * (uu * 36.0 + 0.3 * br_streak))
    br_h = 0.65 * br_streak + 0.35 * br_fine
    b_lo, b_hi = hex_srgb("A68246"), hex_srgb("CFA963")
    b_mix = np.clip(0.25 + 0.65 * br_streak, 0.0, 1.0)[..., None]
    br_alb = b_lo * (1.0 - b_mix) + b_hi * b_mix
    br_rgh = np.clip(0.28 + 0.09 * (1.0 - br_streak), 0.26, 0.38)

    # 7. Turned dark walnut wood
    wood_ring = 0.5 + 0.5 * np.sin(TAU * (uu * 9.0 + 0.55 * _fbm(sz, [4, 10], [0.65, 0.35], seed=613)))
    wd_lo, wd_hi = hex_srgb("3F281A"), hex_srgb("69452D")
    wd_alb = wd_lo * (1.0 - wood_ring[..., None]) + wd_hi * wood_ring[..., None]
    wd_rgh = np.clip(0.50 + 0.14 * (1.0 - wood_ring), 0.45, 0.66)

    # 8. Flame emissive vertical gradient (V=0 base deep amber -> V=0.40 warm gold core -> V=1 soft amber tip)
    flame_alb = np.zeros((sz, sz, 3), dtype=np.float32)
    f_base = hex_srgb("DC5C14")
    f_core = hex_srgb("FFDF8A")
    f_tip = hex_srgb("EB841C")
    t1 = np.clip(vv / 0.38, 0.0, 1.0)[..., None]
    t2 = np.clip((vv - 0.38) / 0.62, 0.0, 1.0)[..., None]
    flame_alb = np.where(vv[..., None] < 0.38, f_base * (1.0 - t1) + f_core * t1,
                         f_core * (1.0 - t2) + f_tip * t2)

    mats = {
        "grimoire_leather": leather_mat("Book · Sea-Mist Leather", "254259", "3D6785", 0.50, 0.64, coat=0.04, nrm_s=0.40, scale=2.6),
        "grimoire_leather_dark": leather_mat("Book · Deep Spine Leather", "1B3244", "2D5069", 0.50, 0.64, coat=0.04, nrm_s=0.42, scale=2.8),
        "page_edges": _make_pbr_mat("Book · Parchment Pages", "E8DAC0", roughness=0.80,
                                    albedo_arr=page_alb, rough_arr=page_rgh, height_arr=page_h,
                                    normal_strength=0.68, uv_scale=1.0),
        "ribbon_blue": _make_pbr_mat("Book · Sea-Mist Ribbon", "4D7B9B", roughness=0.48, coat=0.06),
        "ribbon_trim": _make_pbr_mat("Book · Ribbon Gold Edge", "C59F59", roughness=0.36, metallic=0.72),
        "water_gem": _make_pbr_mat("Book · Water Crystal", "79B7D9", roughness=0.10, coat=0.85,
                                   emission_hex="67A8CC", emission_strength=0.18),
        "burlap_linen": _make_pbr_mat("Pack · Coarse Linen", "C5AE8A", roughness=0.88,
                                      albedo_arr=linen_alb, rough_arr=linen_rgh, height_arr=linen_h,
                                      normal_strength=0.52, uv_scale=2.0),
        "burlap_shadow": _make_pbr_mat("Pack · Linen Crease", "A68C69", roughness=0.90),
        "leather_strap": leather_mat("Pack · Saddle Strap Leather", "452B1B", "68422A", 0.48, 0.60, coat=0.04, nrm_s=0.36, scale=2.4),
        "canteen_leather": leather_mat("Pack · Oiled Canteen Leather", "5D351C", "8D5733", 0.46, 0.55, coat=0.04, nrm_s=0.38, scale=2.2),
        "canteen_welt": leather_mat("Pack · Canteen Edge Welt", "3A2012", "54321D", 0.52, 0.64, coat=0.03, nrm_s=0.32, scale=2.5),
        "cork": _make_pbr_mat("Pack · Natural Cork", "B79164", roughness=0.84,
                              albedo_arr=linen_alb * 0.88 + hex_srgb("A87E51") * 0.12,
                              height_arr=linen_h, normal_strength=0.46, uv_scale=2.6),
        "linen_thread": _make_pbr_mat("Shared · Waxed Thread", "E2D1B2", roughness=0.78),
        "cloak_wool": _make_pbr_mat("Cloak · Sea-Mist Wool", "48728F", roughness=0.90,
                                    albedo_arr=wool_alb, rough_arr=wool_rgh, height_arr=wool_h,
                                    normal_strength=0.48, uv_scale=2.4),
        "cloak_wool_deep": _make_pbr_mat("Cloak · Hood Shadow Wool", "29465C", roughness=0.94),
        "cloak_lining": _make_pbr_mat("Cloak · Parchment Lining", "E6D6B9", roughness=0.86,
                                      albedo_arr=cot_alb, rough_arr=cot_rgh, height_arr=cot_n,
                                      normal_strength=0.28, uv_scale=2.2),
        "brass_antique": _make_pbr_mat("Metal · Antique Brass", "C59E59", roughness=0.31, metallic=0.86,
                                       albedo_arr=br_alb, rough_arr=br_rgh, height_arr=br_h,
                                       normal_strength=0.22, uv_scale=1.6),
        "brass_bright": _make_pbr_mat("Metal · Burnished Brass", "DFBC74", roughness=0.27, metallic=0.88),
        "brass_dark": _make_pbr_mat("Metal · Patina Bronze", "785C34", roughness=0.37, metallic=0.84),
        "walnut_wood": _make_pbr_mat("Wood · Dark Walnut", "543623", roughness=0.56, coat=0.10,
                                     albedo_arr=wd_alb, rough_arr=wd_rgh, height_arr=wood_ring,
                                     normal_strength=0.28, uv_scale=1.5),
        "charred_wick": _make_pbr_mat("Lantern · Charred Wick", "2A211C", roughness=0.92),
        "lantern_glass": _make_pbr_mat("Lantern · Frosted Glass", "FFF6E8", roughness=0.14, metallic=0.0,
                                       coat=0.30, emission_hex="FFCB7D", emission_strength=0.035,
                                       alpha=0.20, alpha_blend=True),
        "lantern_flame": _make_pbr_mat("Lantern · Amber Flame", "FFBE58", roughness=0.25,
                                       albedo_arr=flame_alb, emission_hex="FFA038", emission_strength=2.5),
    }
    # Link flame albedo texture to emission color too so the glow preserves vertical amber-to-cream gradient
    f_mat = mats["lantern_flame"]
    f_nt = f_mat.node_tree
    f_bsdf = next(n for n in f_nt.nodes if n.type == "BSDF_PRINCIPLED")
    f_tex = next((n for n in f_nt.nodes if n.type == "TEX_IMAGE"), None)
    if f_tex is not None:
        f_nt.links.new(f_tex.outputs["Color"], f_bsdf.inputs["Emission Color"])
    return mats


# ---------------------------------------------------------------------------
# Watertight Manifold Mesh Builder with Parametric UV & Validation
# ---------------------------------------------------------------------------

class MeshBuilder:
    def __init__(self):
        self.verts = []
        self.faces = []
        self.mats = []
        self.smooths = []
        self.uvs = []

    def add_solid(self, pts, faces, mat, smooth=True, face_uvs=None):
        base = len(self.verts)
        self.verts.extend([Vector(p) for p in pts])
        for idx, f in enumerate(faces):
            self.faces.append([base + v for v in f])
            m = mat[idx] if isinstance(mat, (list, tuple)) else mat
            s = smooth[idx] if isinstance(smooth, (list, tuple)) else smooth
            self.mats.append(m)
            self.smooths.append(s)
            if face_uvs is not None:
                self.uvs.append(face_uvs[idx])
            else:
                self.uvs.append(None)

    def _cap_ring(self, ring_pts, mat, reverse=False):
        n = len(ring_pts)
        center = sum(ring_pts, Vector((0, 0, 0))) / n
        if n <= 4:
            idxs = list(reversed(range(n))) if reverse else list(range(n))
            return [tuple(idxs)], None
        # Fan cap around ring centroid for guaranteed watertight convex/star caps
        return None, center

    def loft(self, rings, mat, smooth=True, loop=False, cap=True, uv_scale=(1.0, 1.0)):
        """Build a closed manifold tube/shell from equal-length vertex rings."""
        rings = [[Vector(p) for p in r] for r in rings]
        nrows, ncols = len(rings), len(rings[0])
        pts = [p for r in rings for p in r]
        faces, f_mats, f_smooth, f_uvs = [], [], [], []
        us, vs = uv_scale
        row_count = nrows if loop else nrows - 1
        for r in range(row_count):
            r0 = r * ncols
            r1 = ((r + 1) % nrows) * ncols
            v0 = (r / max(row_count, 1)) * vs
            v1 = ((r + 1) / max(row_count, 1)) * vs
            for c in range(ncols):
                c1 = (c + 1) % ncols
                u0 = (c / ncols) * us
                u1 = ((c + 1) / ncols) * us
                faces.append((r0 + c, r0 + c1, r1 + c1, r1 + c))
                m = mat(r, c) if callable(mat) else mat
                f_mats.append(m)
                f_smooth.append(smooth)
                f_uvs.append(((u0, v0), (u1, v0), (u1, v1), (u0, v1)))
        if cap and not loop:
            # Start cap (row 0)
            c0 = sum(rings[0], Vector((0, 0, 0))) / ncols
            c0_idx = len(pts)
            pts.append(c0)
            m0 = mat(0, 0) if callable(mat) else mat
            for c in range(ncols):
                c1 = (c + 1) % ncols
                faces.append((c0_idx, c1, c))
                f_mats.append(m0)
                f_smooth.append(False)
                f_uvs.append(((0.5, 0.5), (0.5 + 0.4 * math.cos(TAU * c1 / ncols), 0.5 + 0.4 * math.sin(TAU * c1 / ncols)),
                              (0.5 + 0.4 * math.cos(TAU * c / ncols), 0.5 + 0.4 * math.sin(TAU * c / ncols))))
            # End cap (row -1)
            last = (nrows - 1) * ncols
            c1p = sum(rings[-1], Vector((0, 0, 0))) / ncols
            c1_idx = len(pts)
            pts.append(c1p)
            m1 = mat(nrows - 2, 0) if callable(mat) else mat
            for c in range(ncols):
                c1 = (c + 1) % ncols
                faces.append((c1_idx, last + c, last + c1))
                f_mats.append(m1)
                f_smooth.append(False)
                f_uvs.append(((0.5, 0.5), (0.5 + 0.4 * math.cos(TAU * c / ncols), 0.5 + 0.4 * math.sin(TAU * c / ncols)),
                              (0.5 + 0.4 * math.cos(TAU * c1 / ncols), 0.5 + 0.4 * math.sin(TAU * c1 / ncols))))
        self.add_solid(pts, faces, f_mats, f_smooth, f_uvs)

    def lathe(self, profile, mat, sides=32, center=(0.0, 0.0, 0.0), axis="Z",
              stretch=(1.0, 1.0), smooth=True, cap=True, uv_scale=(1.0, 1.0)):
        """Revolve (radius, height) profile around Z (or X/Y) axis."""
        cx, cy, cz = center
        sx, sy = stretch
        rings = []
        for r, h in profile:
            r_eff = max(r, 1e-4)
            ring = []
            for a in angles(sides):
                ca, sa = math.cos(a), math.sin(a)
                if axis == "Z":
                    ring.append((cx + r_eff * sx * ca, cy + r_eff * sy * sa, cz + h))
                elif axis == "X":
                    ring.append((cx + h, cy + r_eff * sx * ca, cz + r_eff * sy * sa))
                else:
                    ring.append((cx + r_eff * sx * ca, cy + h, cz + r_eff * sy * sa))
            rings.append(ring)
        self.loft(rings, mat, smooth=smooth, loop=False, cap=cap, uv_scale=uv_scale)

    def tube(self, path, radius, mat, sides=10, loop=False, aspect=1.0, smooth=True, cap=True):
        """Parallel-transport (Bishop frame) twist-free tube along 3D curve."""
        pts = [Vector(p) for p in path]
        n = len(pts)
        tangents = []
        for i in range(n):
            prev_p = pts[(i - 1) % n] if loop else pts[max(0, i - 1)]
            next_p = pts[(i + 1) % n] if loop else pts[min(n - 1, i + 1)]
            t = next_p - prev_p
            if t.length < 1e-8:
                t = Vector((0, 0, 1))
            else:
                t.normalize()
            tangents.append(t)

        # Initial frame
        ref = Vector((0, 0, 1)) if abs(tangents[0].z) < 0.92 else Vector((1, 0, 0))
        norm = tangents[0].cross(ref).normalized()
        binorm = tangents[0].cross(norm).normalized()
        rings = []
        for i, p in enumerate(pts):
            if i > 0:
                t_prev, t_cur = tangents[i - 1], tangents[i]
                rot_axis = t_prev.cross(t_cur)
                if rot_axis.length > 1e-7:
                    ang = math.acos(clamp(t_prev.dot(t_cur), -1.0, 1.0))
                    rot_m = Matrix.Rotation(ang, 3, rot_axis.normalized())
                    norm = (rot_m @ norm).normalized()
                    binorm = t_cur.cross(norm).normalized()
            rad = radius[i] if isinstance(radius, (list, tuple)) else radius
            if isinstance(rad, (list, tuple)):
                rx, ry = rad[0], rad[1]
            else:
                rx, ry = rad, rad * aspect
            ring = [p + norm * (rx * math.cos(a)) + binorm * (ry * math.sin(a)) for a in angles(sides)]
            rings.append(ring)
        self.loft(rings, mat, smooth=smooth, loop=loop, cap=cap)

    def strap(self, path, normals, width, thickness, mat, bevel=0.25, smooth=True, loop=False, cap=True):
        """Beveled flat leather/ribbon strap swept along a 3D curve with explicit surface normals."""
        pts = [Vector(p) for p in path]
        nrms = [Vector(nm).normalized() for nm in normals]
        n = len(pts)
        # 8-point rounded-rectangle cross-section
        rings = []
        for i in range(n):
            prev_p = pts[(i - 1) % n] if loop else pts[max(0, i - 1)]
            next_p = pts[(i + 1) % n] if loop else pts[min(n - 1, i + 1)]
            t = (next_p - prev_p).normalized()
            nm = nrms[i]
            side = t.cross(nm)
            if side.length < 1e-7:
                side = t.cross(Vector((0, 0, 1)))
            side.normalize()
            nm = side.cross(t).normalized()
            w = (width[i] if isinstance(width, (list, tuple)) else width) * 0.5
            h = (thickness[i] if isinstance(thickness, (list, tuple)) else thickness) * 0.5
            bw, bh = w * (1.0 - bevel), h * (1.0 - bevel)
            prof = [
                (-bw, -h), (bw, -h), (w, -bh), (w, bh),
                (bw, h), (-bw, h), (-w, bh), (-w, -bh),
            ]
            rings.append([pts[i] + side * sx + nm * sy for sx, sy in prof])
        self.loft(rings, mat, smooth=smooth, loop=loop, cap=cap)

    def beveled_plate(self, poly_2d, z0, z1, mat, bevel=0.004, inset_ratio=0.96, smooth=False,
                      transform=None):
        """Extrude any (even concave) 2D polygon into a watertight beveled plate."""
        poly = [Vector((p[0], p[1])) for p in poly_2d]
        n = len(poly)
        cx = sum(p.x for p in poly) / n
        cy = sum(p.y for p in poly) / n
        mid = Vector((cx, cy))
        # Ensure CCW winding
        area2 = sum(poly[i].x * poly[(i + 1) % n].y - poly[(i + 1) % n].x * poly[i].y for i in range(n))
        if area2 < 0:
            poly = list(reversed(poly))

        h = z1 - z0
        b = min(bevel, abs(h) * 0.35)
        levels = [
            (z0, inset_ratio),
            (z0 + b, 1.0),
            (z1 - b, 1.0),
            (z1, inset_ratio),
        ]
        rings = []
        for z_val, sc in levels:
            ring = []
            for p in poly:
                q = mid + (p - mid) * sc
                v = Vector((q.x, q.y, z_val))
                if transform is not None:
                    v = transform(v)
                ring.append(v)
            rings.append(ring)

        pts = [p for r in rings for p in r]
        faces, f_mats, f_smooth = [], [], []
        for r in range(3):
            r0, r1 = r * n, (r + 1) * n
            for i in range(n):
                j = (i + 1) % n
                faces.append((r0 + i, r0 + j, r1 + j, r1 + i))
                f_mats.append(mat)
                f_smooth.append(smooth)
        # Tessellate top and bottom caps (works cleanly for concave stars/L-corners)
        tris = tessellate_polygon([[Vector((p.x, p.y, 0.0)) for p in poly]])
        top_off = 3 * n
        for a, b_i, c in tris:
            faces.append((c, b_i, a))  # bottom facing -Z
            f_mats.append(mat)
            f_smooth.append(False)
            faces.append((top_off + a, top_off + b_i, top_off + c))  # top facing +Z
            f_mats.append(mat)
            f_smooth.append(False)
        self.add_solid(pts, faces, f_mats, f_smooth)

    def thick_sheet(self, top_grid, bot_grid, mat_top, mat_bot=None, mat_edge=None,
                    smooth=True, uv_scale=(1.0, 1.0)):
        """Watertight curved cloth/board sheet bounded by matching top & bottom grids."""
        mat_bot = mat_top if mat_bot is None else mat_bot
        mat_edge = mat_top if mat_edge is None else mat_edge
        nr, nc = len(top_grid), len(top_grid[0])
        pts = [Vector(p) for row in top_grid for p in row]
        off = len(pts)
        pts.extend(Vector(p) for row in bot_grid for p in row)
        faces, f_mats, f_smooth, f_uvs = [], [], [], []
        us, vs = uv_scale
        for r in range(nr - 1):
            v0, v1 = r / (nr - 1) * vs, (r + 1) / (nr - 1) * vs
            for c in range(nc - 1):
                u0, u1 = c / (nc - 1) * us, (c + 1) / (nc - 1) * us
                i00 = r * nc + c
                i10 = i00 + 1
                i11 = i00 + nc + 1
                i01 = i00 + nc
                faces.append((i00, i10, i11, i01))
                f_mats.append(mat_top)
                f_smooth.append(smooth)
                f_uvs.append(((u0, v0), (u1, v0), (u1, v1), (u0, v1)))

                faces.append((off + i00, off + i01, off + i11, off + i10))
                f_mats.append(mat_bot)
                f_smooth.append(smooth)
                f_uvs.append(((u0, v0), (u0, v1), (u1, v1), (u1, v0)))

        # Perimeter seam stitch
        perim = (
            [c for c in range(nc)]
            + [r * nc + (nc - 1) for r in range(1, nr)]
            + [(nr - 1) * nc + c for c in range(nc - 2, -1, -1)]
            + [r * nc for r in range(nr - 2, 0, -1)]
        )
        m_p = len(perim)
        for k in range(m_p):
            a = perim[k]
            b = perim[(k + 1) % m_p]
            faces.append((a, off + a, off + b, b))
            f_mats.append(mat_edge)
            f_smooth.append(smooth)
            t0, t1 = k / m_p, (k + 1) / m_p
            f_uvs.append(((t0, 0.0), (t0, 1.0), (t1, 1.0), (t1, 0.0)))
        self.add_solid(pts, faces, f_mats, f_smooth, f_uvs)

    def ellipsoid(self, center, radii, mat, sides=18, rows=10, deform=None, smooth=True):
        """Watertight UV ellipsoid with optional organic vertex deformation fn(v)->v."""
        cx, cy, cz = center
        rx, ry, rz = radii
        pts = []
        v_bot = Vector((cx, cy, cz - rz))
        pts.append(deform(v_bot) if deform else v_bot)
        for r in range(1, rows):
            phi = -0.5 * math.pi + math.pi * r / rows
            cp, sp = math.cos(phi), math.sin(phi)
            for a in angles(sides):
                v = Vector((cx + rx * cp * math.cos(a), cy + ry * cp * math.sin(a), cz + rz * sp))
                pts.append(deform(v) if deform else v)
        v_top = Vector((cx, cy, cz + rz))
        pts.append(deform(v_top) if deform else v_top)
        faces, f_uvs = [], []
        for i in range(sides):
            j = (i + 1) % sides
            faces.append((0, 1 + j, 1 + i))
            f_uvs.append(((0.5, 0.0), ((i + 1) / sides, 1 / rows), (i / sides, 1 / rows)))
        for r in range(rows - 2):
            lo, hi = 1 + r * sides, 1 + (r + 1) * sides
            v0, v1 = (r + 1) / rows, (r + 2) / rows
            for i in range(sides):
                j = (i + 1) % sides
                faces.append((lo + i, lo + j, hi + j, hi + i))
                f_uvs.append(((i / sides, v0), ((i + 1) / sides, v0), ((i + 1) / sides, v1), (i / sides, v1)))
        top_i = len(pts) - 1
        last = top_i - sides
        for i in range(sides):
            j = (i + 1) % sides
            faces.append((top_i, last + i, last + j))
            f_uvs.append(((0.5, 1.0), (i / sides, (rows - 1) / rows), ((i + 1) / sides, (rows - 1) / rows)))
        self.add_solid(pts, faces, mat, smooth, f_uvs)

    def build_mesh(self, name, mat_lib, target_extent=TARGET_EXTENT):
        """Center at (0,0,0), normalize max extent to target_extent, validate manifold & normals."""
        xs = [v.x for v in self.verts]
        ys = [v.y for v in self.verts]
        zs = [v.z for v in self.verts]
        lo = Vector((min(xs), min(ys), min(zs)))
        hi = Vector((max(xs), max(ys), max(zs)))
        center = (lo + hi) * 0.5
        extent = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)
        scale = target_extent / extent
        coords = [(v - center) * scale for v in self.verts]

        used_keys = []
        key_to_idx = {}
        for m in self.mats:
            if m not in key_to_idx:
                key_to_idx[m] = len(used_keys)
                used_keys.append(m)

        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(coords, [], self.faces)
        mesh.update()
        assert not mesh.validate(clean_customdata=False), f"{name}: mesh validation failed"
        for k in used_keys:
            mesh.materials.append(mat_lib[k])
        for poly, m_key, sm in zip(mesh.polygons, self.mats, self.smooths, strict=True):
            poly.material_index = key_to_idx[m_key]
            poly.use_smooth = sm

        # Populate UV layer (explicit parametric UVs where given, triplanar fallback otherwise)
        uv_layer = mesh.uv_layers.new(name="UVMap")
        proj = ((1, 2), (0, 2), (0, 1))
        for poly, f_uv in zip(mesh.polygons, self.uvs, strict=True):
            if f_uv is not None and len(f_uv) == len(poly.loop_indices):
                for li, uv_pt in zip(poly.loop_indices, f_uv):
                    uv_layer.data[li].uv = uv_pt
            else:
                nrm = poly.normal
                ax = max(range(3), key=lambda i: abs(nrm[i]))
                ia, ib = proj[ax]
                for li in poly.loop_indices:
                    co = mesh.vertices[mesh.loops[li].vertex_index].co
                    uv_layer.data[li].uv = (co[ia] + 0.5, co[ib] + 0.5)

        bm = bmesh.new()
        try:
            bm.from_mesh(mesh)
            bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
            non_man = [e for e in bm.edges if not e.is_manifold]
            assert not non_man, f"{name}: {len(non_man)} non-manifold edges"
            tiny = [f for f in bm.faces if f.calc_area() <= 1e-10]
            assert not tiny, f"{name}: {len(tiny)} degenerate faces"
            bm.to_mesh(mesh)
        finally:
            bm.free()

        mesh.update()
        mesh.calc_loop_triangles()
        tris = len(mesh.loop_triangles)
        assert 3000 <= tris <= 9000, f"{name}: triangle count {tris} outside [3000, 9000]"
        return mesh


# ---------------------------------------------------------------------------
# Prop 1: book_sister_grimoire.glb (《姐姐的水魔术手记》)
# ---------------------------------------------------------------------------

def _rounded_rect_2d(x0, x1, y0, y1, r, corner_steps=4):
    pts = []
    corners = [
        (x1 - r, y1 - r, 0.0),
        (x0 + r, y1 - r, math.pi * 0.5),
        (x0 + r, y0 + r, math.pi),
        (x1 - r, y0 + r, math.pi * 1.5),
    ]
    for cx, cy, a0 in corners:
        for i in range(corner_steps + 1):
            a = a0 + (math.pi * 0.5) * (i / corner_steps)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def _l_corner_poly(size, arm_w, inner_notch=0.018):
    """Ornate L-shaped book corner guard polygon in local [0..size] quadrant (corner at 0,0)."""
    s, w, n = size, arm_w, inner_notch
    return [
        (0.0, 0.0), (s, 0.0), (s, w * 0.55), (s - w * 0.45, w),
        (w + n, w), (w + n * 0.35, w + n * 0.35), (w, w + n),
        (w, s - w * 0.45), (w * 0.55, s), (0.0, s),
    ]


def build_book_sister_grimoire():
    b = MeshBuilder()
    # Dimensions in local tabletop coords: X=width (spine at -X), Y=height, Z=thickness
    bx0, bx1 = -0.34, 0.34
    by0, by1 = -0.45, 0.45
    hz = 0.105        # half thickness of outer cover
    board_t = 0.022   # leather board thickness

    # 1. Front & Back beveled leather boards (rounded outer corners on fore-edge)
    board_poly = _rounded_rect_2d(bx0 + 0.035, bx1, by0, by1, r=0.028, corner_steps=4)
    # Front board (+Z) and Back board (-Z)
    b.beveled_plate(board_poly, hz - board_t, hz, "grimoire_leather", bevel=0.0055, inset_ratio=0.985, smooth=True)
    b.beveled_plate(board_poly, -hz, -hz + board_t, "grimoire_leather", bevel=0.0055, inset_ratio=0.985, smooth=True)

    # 2. Rounded leather spine connecting front & back boards with subtle French-groove hinge
    spine_rings = []
    ny_spine = 16
    # Cross-section around the C-shaped spine (closed thick shell profile)
    prof_outer = []
    n_arc = 10
    for i in range(n_arc + 1):
        t = i / n_arc  # 0 = top (+Z) -> 1 = bottom (-Z)
        ang = math.pi * 0.5 + math.pi * t
        px = bx0 + 0.042 + 0.056 * math.cos(ang)
        pz = (hz - 0.002) * math.sin(ang)
        prof_outer.append((px, pz))
    # Tuck back slightly into boards to form watertight C-wall
    prof_inner = []
    for i in range(n_arc, -1, -1):
        t = i / n_arc
        ang = math.pi * 0.5 + math.pi * t
        px = bx0 + 0.048 + 0.036 * math.cos(ang)
        pz = (hz - board_t + 0.002) * math.sin(ang)
        prof_inner.append((px, pz))
    spine_prof = prof_outer + prof_inner

    for iy in range(ny_spine + 1):
        ty = iy / ny_spine
        y = by0 + (by1 - by0) * ty
        # Slight endcap swell near top/bottom headcaps
        end_flare = 0.003 * (1.0 - smoothstep(0.0, 0.08, min(ty, 1.0 - ty)))
        ring = [(px - end_flare if px < bx0 + 0.02 else px, y, pz) for px, pz in spine_prof]
        spine_rings.append(ring)
    b.loft(spine_rings, "grimoire_leather_dark", smooth=True, cap=True, uv_scale=(1.5, 2.0))

    # 3. Four classic raised spine bands (Raised Bands) wrapping cleanly over the spine curve
    band_ys = (-0.30, -0.10, 0.10, 0.30)
    for by in band_ys:
        path = []
        nrms = []
        n_b = 11
        for i in range(n_b + 1):
            t = i / n_b
            ang = math.pi * 0.42 + math.pi * 1.16 * t
            px = bx0 + 0.042 + 0.060 * math.cos(ang)
            pz = (hz + 0.002) * math.sin(ang)
            path.append((px, by, pz))
            nrms.append((math.cos(ang), 0.0, math.sin(ang)))
        b.strap(path, nrms, width=0.024, thickness=0.014, mat="grimoire_leather_dark", bevel=0.35, smooth=True)
        # Subtle gilded accent fillet line flanking each raised band
        for dy in (-0.017, 0.017):
            g_path = [(p[0] - 0.001, by + dy, p[2]) for p in path[1:-1]]
            b.tube(g_path, 0.0026, "brass_antique", sides=6)

    # 4. Recessed warm parchment page block with sculpted subtle multi-page edge wave & deckled grooves
    px0, px1 = bx0 + 0.046, bx1 - 0.030
    py0, py1 = by0 + 0.026, by1 - 0.026
    pz_h = hz - board_t + 0.002
    nz_layers = 10
    page_rings = []
    # Build perimeter ring around the page block (fore-edge has gentle concave thumb-hollow + sheet ripples)
    perim_2d = []
    # Bottom edge (left to right)
    for i in range(8):
        perim_2d.append((px0 + (px1 - px0) * (i / 8), py0))
    # Fore-edge (+X, bottom to top)
    for i in range(14):
        perim_2d.append((px1, py0 + (py1 - py0) * (i / 14)))
    # Top edge (right to left)
    for i in range(8):
        perim_2d.append((px1 - (px1 - px0) * (i / 8), py1))
    # Spine edge (-X, top to bottom)
    for i in range(6):
        perim_2d.append((px0, py1 - (py1 - py0) * (i / 6)))

    for iz in range(nz_layers + 1):
        tz = iz / nz_layers
        z = -pz_h + 2.0 * pz_h * tz
        # Natural book page-block curve: slight outward arch in the middle layers + micro sheet ripple
        arch = math.sin(tz * math.pi)
        sheet_rip = 0.0026 * math.sin(tz * math.pi * 11.0)
        ring = []
        for x, y in perim_2d:
            dx, dy = 0.0, 0.0
            if x > px1 - 0.005:
                # Subtle organic concave fore-edge curve + fine layered sheet modulation
                y_norm = (y - py0) / (py1 - py0)
                dx = -0.008 * arch * math.sin(y_norm * math.pi) + sheet_rip
            elif y < py0 + 0.005:
                dy = -0.0025 * arch + sheet_rip * 0.6
            elif y > py1 - 0.005:
                dy = 0.0025 * arch - sheet_rip * 0.6
            ring.append((x + dx, y + dy, z))
        page_rings.append(ring)
    b.loft(page_rings, "page_edges", smooth=True, cap=True, uv_scale=(2.0, 1.35))

    # Stitched woven headbands tucked at top and bottom of the spine
    for sy_sign in (-1.0, 1.0):
        hy = py1 + 0.004 if sy_sign > 0 else py0 - 0.004
        hb_pts = []
        for i in range(9):
            t = i / 8
            z = -pz_h * 0.85 + 1.70 * pz_h * t
            x = px0 - 0.005 - 0.008 * math.sin(t * math.pi)
            hb_pts.append((x, hy, z))
        b.tube(hb_pts, 0.008, "ribbon_blue", sides=8)

    # 5. Front & Back blind-tooled recessed/raised decorative border frames (360-degree detail)
    for z_sign in (1.0, -1.0):
        z_surf = z_sign * hz
        # Outer gilded/tooled frame line
        fx0, fx1 = bx0 + 0.095, bx1 - 0.042
        fy0, fy1 = by0 + 0.042, by1 - 0.042
        frame_pts = [
            (fx0, fy0, z_surf), (fx1, fy0, z_surf),
            (fx1, fy1, z_surf), (fx0, fy1, z_surf),
        ]
        b.tube(frame_pts, 0.0042, "brass_dark" if z_sign < 0 else "brass_antique", sides=6, loop=True)
        # Inner stepped panel line
        ix0, ix1 = fx0 + 0.032, fx1 - 0.032
        iy0, iy1 = fy0 + 0.032, fy1 - 0.032
        inner_pts = [
            (ix0, iy0, z_surf), (ix1, iy0, z_surf),
            (ix1, iy1, z_surf), (ix0, iy1, z_surf),
        ]
        b.tube(inner_pts, 0.0028, "grimoire_leather_dark", sides=6, loop=True)

    # Back cover central embossed diamond seal (ensures rich underside craftsmanship)
    back_diam = [(0.03, 0.08), (0.09, 0.0), (0.03, -0.08), (-0.03, 0.0)]
    b.beveled_plate(back_diam, -hz - 0.007, -hz + 0.002, "brass_dark", bevel=0.0022, inset_ratio=0.88)

    # 6. Eight antique-gold ornate corner guards (4 front + 4 back wrapping around board corners)
    l_poly = _l_corner_poly(size=0.145, arm_w=0.034, inner_notch=0.022)
    corner_specs = [
        (bx1 + 0.003, by1 + 0.003, -1.0, -1.0),
        (bx1 + 0.003, by0 - 0.003, -1.0, 1.0),
        (bx0 + 0.040, by1 + 0.003, 1.0, -1.0),
        (bx0 + 0.040, by0 - 0.003, 1.0, 1.0),
    ]
    for cx, cy, sx, sy in corner_specs:
        poly_c = [(cx + sx * px, cy + sy * py) for px, py in l_poly]
        # Front corner plate
        b.beveled_plate(poly_c, hz - 0.002, hz + 0.009, "brass_antique", bevel=0.0026, inset_ratio=0.92)
        # Back corner plate
        b.beveled_plate(poly_c, -hz - 0.009, -hz + 0.002, "brass_antique", bevel=0.0026, inset_ratio=0.92)
        # Corner edge wrap bumper on fore-edge corners
        if sx < 0:
            edge_poly = [(cx + sx * px, cy + sy * py) for px, py in [(0.0, 0.0), (0.030, 0.0), (0.030, 0.030), (0.0, 0.030)]]
            b.beveled_plate(edge_poly, hz - board_t - 0.002, hz + 0.008, "brass_dark", bevel=0.002)
            b.beveled_plate(edge_poly, -hz - 0.008, -hz + board_t + 0.002, "brass_dark", bevel=0.002)
        # Tiny decorative rivets on each corner guard
        for rx_off, ry_off in ((0.020, 0.095), (0.095, 0.020), (0.024, 0.024)):
            b.ellipsoid((cx + sx * rx_off, cy + sy * ry_off, hz + 0.009), (0.0055, 0.0055, 0.004), "brass_bright", sides=8, rows=4)
            b.ellipsoid((cx + sx * rx_off, cy + sy * ry_off, -hz - 0.009), (0.0055, 0.0055, 0.004), "brass_bright", sides=8, rows=4)

    # 7. Front Cover Center Hero Emblem: 4-point diamond star + Water-Drop bezel + Sea-Mist Crystal
    ecx, ecy = 0.025, 0.015
    # Outer 8-point compass / 4-point long star relief
    star_pts = []
    for i in range(8):
        a = i * math.pi * 0.25 + math.pi * 0.5
        if i % 2 == 0:
            r = 0.165 if (i == 0 or i == 4) else 0.135
        else:
            r = 0.058
        star_pts.append((ecx + r * math.cos(a), ecy + r * math.sin(a)))
    b.beveled_plate(star_pts, hz - 0.002, hz + 0.010, "brass_antique", bevel=0.003, inset_ratio=0.86)

    # Circular filigree ring encircling the water drop
    ring_pts = [(ecx + 0.088 * math.cos(a), ecy + 0.088 * math.sin(a), hz + 0.009) for a in angles(28)]
    b.tube(ring_pts, 0.0065, "brass_bright", sides=7, loop=True)

    # Sculpted water-drop gold bezel
    drop_poly = []
    for i in range(20):
        t = i / 20
        a = TAU * t
        # Classic teardrop equation: pointed at +Y, plump round base at -Y
        rx = 0.048 * math.sin(a) * (0.62 + 0.38 * math.sin(a * 0.5))
        # Use cleaner parametric teardrop
        u = math.pi * (2.0 * t - 1.0)
        dx = 0.044 * math.sin(u) * (1.0 - 0.42 * math.cos(u))
        dy = 0.068 * math.cos(u)
        drop_poly.append((ecx + dx, ecy + dy))
    b.beveled_plate(drop_poly, hz + 0.006, hz + 0.018, "brass_antique", bevel=0.003, inset_ratio=0.84)

    # Inset domed sea-mist water crystal cabochon inside the teardrop
    def _drop_deform(v):
        lx = v.x - ecx
        ly = v.y - ecy
        taper = 1.0 - 0.38 * clamp((ly + 0.045) / 0.095, 0.0, 1.0)
        return Vector((ecx + lx * taper, v.y, v.z))

    b.ellipsoid((ecx, ecy - 0.005, hz + 0.017), (0.034, 0.048, 0.014), "water_gem",
                sides=16, rows=8, deform=_drop_deform, smooth=True)

    # Four small brass accent gems/studs at cardinal points
    for dx, dy in ((0.0, 0.190), (0.0, -0.190), (0.158, 0.0), (-0.158, 0.0)):
        b.ellipsoid((ecx + dx, ecy + dy, hz + 0.005), (0.009, 0.009, 0.005), "brass_bright", sides=8, rows=4)

    # 8. Antique-Gold Fore-Edge Clasp (hinged tongue wrapping from back cover across fore-edge onto front)
    clasp_path = [
        (bx1 - 0.065, 0.0, -hz - 0.007),
        (bx1 + 0.006, 0.0, -hz - 0.004),
        (bx1 + 0.015, 0.0, -hz * 0.5),
        (bx1 + 0.017, 0.0, 0.0),
        (bx1 + 0.015, 0.0, hz * 0.5),
        (bx1 + 0.006, 0.0, hz + 0.006),
        (bx1 - 0.072, 0.0, hz + 0.010),
    ]
    clasp_smooth = catmull_rom(clasp_path, samples_per_seg=4)
    clasp_nrms = []
    for p in clasp_smooth:
        if p.x > bx1 + 0.008:
            clasp_nrms.append((1.0, 0.0, 0.0))
        elif p.z > 0:
            clasp_nrms.append((0.0, 0.0, 1.0))
        else:
            clasp_nrms.append((0.0, 0.0, -1.0))
    b.strap(clasp_smooth, clasp_nrms, width=0.064, thickness=0.012, mat="brass_antique", bevel=0.28, smooth=True)
    # Catch plate & latch knob on front cover
    catch_poly = _rounded_rect_2d(bx1 - 0.115, bx1 - 0.048, -0.042, 0.042, r=0.012, corner_steps=3)
    b.beveled_plate(catch_poly, hz - 0.001, hz + 0.012, "brass_dark", bevel=0.0025, inset_ratio=0.92)
    b.ellipsoid((bx1 - 0.084, 0.0, hz + 0.015), (0.014, 0.014, 0.010), "brass_bright", sides=10, rows=5)
    # Hinge knuckle pin on the fore-edge corners of the clasp
    for hz_pin in (-hz + 0.008, hz - 0.008):
        b.tube([(bx1 + 0.016, -0.036, hz_pin), (bx1 + 0.016, 0.036, hz_pin)], 0.0075, "brass_bright", sides=8)

    # 9. Wavy Sea-Mist Blue Silk Bookmark Ribbon with Swallowtail V-Notch emerging from bottom page edge
    nr_rib = 18
    nc_rib = 4
    top_grid, bot_grid = [], []
    rib_half_w = 0.034
    rib_thick = 0.0055
    for r in range(nr_rib + 1):
        t = r / nr_rib  # 0 = tucked inside bottom pages -> 1 = wavy tail outside
        y = py0 + 0.035 - 0.235 * t
        # Graceful S-wave drift in X and gentle tabletop rest ripple in Z
        cx = 0.095 + 0.042 * math.sin(t * math.pi * 1.45) * smoothstep(0.05, 0.55, t)
        # Descends smoothly from page center (z=0.01) down toward bottom board resting plane (-hz + 0.012)
        cz = (0.005 * (1.0 - smoothstep(0.10, 0.58, t))
              + (-hz + 0.010) * smoothstep(0.10, 0.58, t)
              + 0.014 * math.sin(t * math.pi * 2.4) * smoothstep(0.20, 0.85, t))
        # Slight ribbon twist as it unfurls
        roll = 0.16 * math.sin(t * math.pi * 1.6) * smoothstep(0.15, 0.8, t)
        # Swallowtail V-notch cutout at the final 16% of length: pull center columns back in Y!
        notch_t = smoothstep(0.76, 1.0, t)
        row_top, row_bot = [], []
        for c in range(nc_rib + 1):
            u = (c / nc_rib) * 2.0 - 1.0  # -1 .. +1 across width
            v_pull = (1.0 - abs(u)) * 0.046 * notch_t
            # Slight inward curl at edges for silky look
            lx = u * rib_half_w
            lz = 0.002 * (u * u)
            rx = cx + lx * math.cos(roll)
            rz = cz + lx * math.sin(roll) + lz
            ry = y + v_pull
            row_top.append((rx, ry, rz + rib_thick * 0.5))
            row_bot.append((rx, ry, rz - rib_thick * 0.5))
        top_grid.append(row_top)
        bot_grid.append(row_bot)
    b.thick_sheet(top_grid, bot_grid, "ribbon_blue", "ribbon_blue", "ribbon_trim", smooth=True, uv_scale=(1.0, 3.0))

    return b.build_mesh("book_sister_grimoire", None) if False else b


# ---------------------------------------------------------------------------
# Prop 2: pack_travel_rations.glb (旅途干粮包与皮水囊)
# ---------------------------------------------------------------------------

def build_pack_travel_rations():
    b = MeshBuilder()

    # --- A. Plump Coarse-Linen Ration Bundle (left-back, resting flush on z=0) ---
    pcx, pcy, pcz = -0.155, 0.030, 0.148
    prx, pry, prz = 0.275, 0.215, 0.148
    # Two binding strap X-positions in local bundle frame
    strap_xs = (-0.112, 0.105)

    def pack_point(u_ang, v_lat, offset=0.0):
        """Parametric plump cloth parcel with pinched ends and compression grooves under straps."""
        # u_ang in [0, 2pi) around Y-Z cross-section; v_lat in [-pi/2, pi/2] along X axis
        # Build elongated pillow along X (left-right), rounded cross-section in Y-Z
        s_x = math.sin(v_lat)  # -1..1 along X
        c_x = math.cos(v_lat)  # 0 at ends, 1 at center
        # Superellipsoid-like plumpness so it looks packed with hardtack & jerky
        x_l = prx * math.copysign(abs(s_x) ** 0.78, s_x)
        # Cross section radial envelope
        env = (c_x ** 0.68)
        ca, sa = math.cos(u_ang), math.sin(u_ang)
        # Soft pillowy squircle cross-section + flattened resting underside
        r_sq = 1.0 / ((abs(ca) ** 2.6 + abs(sa) ** 2.6) ** (1.0 / 2.6) + 1e-6)
        r_mix = 0.62 + 0.38 * r_sq
        y_l = pry * env * r_mix * ca
        z_l = prz * env * r_mix * sa
        if z_l < 0.0:
            # Soft gravity flatten onto tabletop (z=0 -> z_l >= -pcz)
            z_l = z_l * (0.86 + 0.14 * (1.0 - env))

        # Organic cloth wrinkles & compression under the two leather straps
        pinch = 0.0
        for sx in strap_xs:
            d = (x_l - sx) / 0.034
            pinch += 0.016 * math.exp(-d * d)
        # Subtle cloth drape creases radiating from the pinched ends
        end_fold = 0.0085 * (1.0 - env * 0.75) * math.sin(u_ang * 5.0 + 1.3 * s_x)
        belly_puff = 0.007 * math.sin(u_ang * 3.0 - 0.6) * env * (1.0 - pinch * 30.0)
        # Apply radial displacement along Y-Z
        rad_yz = math.hypot(y_l, z_l)
        if rad_yz > 1e-5:
            dr = -pinch + end_fold + belly_puff + offset
            scale_yz = max(0.05, (rad_yz + dr) / rad_yz)
            y_l *= scale_yz
            z_l *= scale_yz
        return Vector((pcx + x_l, pcy + y_l, max(0.0, pcz + z_l)))

    # Construct watertight bundle mesh via lofted rings along X
    nx_rings = 26
    nu_seg = 28
    pack_rings = []
    for ix in range(1, nx_rings):
        v_lat = -0.492 * math.pi + 0.984 * math.pi * (ix / nx_rings)
        ring = [pack_point(a, v_lat, offset=0.0) for a in angles(nu_seg)]
        pack_rings.append(ring)
    b.loft(pack_rings, "burlap_linen", smooth=True, cap=True, uv_scale=(2.2, 1.8))

    # Gathered bunched linen ears/folds cinched at both left & right parcel ends
    for end_sign in (-1.0, 1.0):
        ex = pcx + end_sign * (prx - 0.012)
        ey = pcy + (0.010 if end_sign < 0 else -0.008)
        ez = pcz + 0.012
        # Soft cinched fabric collar ring
        collar_prof = [(0.044, 0.0), (0.034, 0.012), (0.030, 0.022), (0.046, 0.040), (0.058, 0.060), (0.032, 0.072)]
        ear_rings = []
        for idx_p, (rr, hh) in enumerate(collar_prof):
            ring = []
            for a in angles(16):
                # Multi-lobe gathered linen ruffle
                ruff = 1.0 + (0.22 * math.sin(a * 4.0 + end_sign) + 0.12 * math.cos(a * 7.0)) * smoothstep(0.015, 0.065, hh)
                r_use = rr * ruff
                ring.append((ex + end_sign * hh, ey + r_use * math.cos(a), ez + r_use * 0.85 * math.sin(a)))
            ear_rings.append(ring)
        b.loft(ear_rings, "burlap_linen", smooth=True, cap=True, uv_scale=(1.2, 1.0))
        # Waxed twine tie binding the gathered neck
        twine_pts = [
            (ex + end_sign * 0.018, ey + 0.035 * math.cos(a), ez + 0.031 * math.sin(a))
            for a in angles(18)
        ]
        b.tube(twine_pts, 0.0055, "linen_thread", sides=7, loop=True)

    # Top folded linen flap seam running along the crest of the bundle
    flap_pts = []
    flap_nrms = []
    for i in range(13):
        t = i / 12
        v_lat = -0.36 * math.pi + 0.72 * math.pi * t
        pt = pack_point(math.pi * 0.42 + 0.08 * math.sin(t * math.pi), v_lat, offset=0.003)
        flap_pts.append(pt)
        flap_nrms.append((0.0, 0.25, 0.97))
    b.strap(flap_pts, flap_nrms, width=0.036, thickness=0.010, mat="burlap_shadow", bevel=0.35, smooth=True)

    # --- B. Two Dark-Brown Tanned Leather Straps + Antique Brass 日-Buckles ---
    for idx_s, sx in enumerate(strap_xs):
        # Solve v_lat corresponding to sx
        s_norm = clamp(sx / prx, -0.92, 0.92)
        v_lat = math.asin(math.copysign(abs(s_norm) ** (1.0 / 0.78), s_norm))
        n_st = 30
        s_path, s_nrms = [], []
        for i in range(n_st):
            a = TAU * i / n_st
            p0 = pack_point(a, v_lat, offset=0.0085)
            p_in = pack_point(a, v_lat, offset=-0.004)
            nrm = (p0 - p_in)
            nrm = nrm.normalized() if nrm.length > 1e-6 else Vector((0, math.cos(a), math.sin(a)))
            s_path.append(p0)
            s_nrms.append(nrm)
        b.strap(s_path, s_nrms, width=0.034, thickness=0.011, mat="leather_strap", bevel=0.28, smooth=True, loop=True)

        # Mini antique-brass roller buckle (日字扣) perched cleanly on front-top slope (a ≈ 0.34*pi -> -Y/+Z side)
        ang_bk = math.pi * 0.66 if idx_s == 0 else math.pi * 0.62
        # Wait: in Blender Y=-1 is front toward viewer (camera at -Y), Z=+1 is up -> angle near 0.65*pi has cos<0 (-Y), sin>0 (+Z)!
        p_bk = pack_point(ang_bk, v_lat, offset=0.0155)
        p_bk_in = pack_point(ang_bk, v_lat, offset=0.0)
        n_bk = (p_bk - p_bk_in).normalized()
        t_bk = (pack_point(ang_bk + 0.08, v_lat, offset=0.015) - pack_point(ang_bk - 0.08, v_lat, offset=0.015)).normalized()
        s_bk = t_bk.cross(n_bk).normalized()
        t_bk = n_bk.cross(s_bk).normalized()

        # Buckle frame loop (4 rounded bars around the strap)
        hw, hl = 0.023, 0.024
        frame_c = [
            p_bk + s_bk * (-hw) + t_bk * (-hl),
            p_bk + s_bk * (hw) + t_bk * (-hl),
            p_bk + s_bk * (hw) + t_bk * (hl),
            p_bk + s_bk * (-hw) + t_bk * (hl),
        ]
        # Subdivide corners slightly for soft rounded brass frame
        bk_loop = []
        for k in range(4):
            c0, c1 = frame_c[k], frame_c[(k + 1) % 4]
            bk_loop.append(c0.lerp(c1, 0.14))
            bk_loop.append(c0.lerp(c1, 0.86))
        b.tube(bk_loop, 0.0048, "brass_antique", sides=8, loop=True)
        # Central roller crossbar + prong tongue (日字扣 bar)
        b.tube([p_bk - s_bk * hw, p_bk + s_bk * hw], 0.0038, "brass_bright", sides=7)
        b.tube([p_bk, p_bk + t_bk * (hl * 1.05) + n_bk * 0.004], 0.0030, "brass_bright", sides=6)

        # Slightly curled leather strap tongue tail tucked neatly past the buckle
        tail_pts, tail_nrms = [], []
        for k in range(6):
            tk = k / 5.0
            a_t = ang_bk + 0.09 + 0.26 * tk
            lift = 0.0175 + 0.0045 * math.sin(tk * math.pi)
            pt = pack_point(a_t, v_lat, offset=lift)
            pn = (pt - pack_point(a_t, v_lat, offset=0.0)).normalized()
            tail_pts.append(pt)
            tail_nrms.append(pn)
        b.strap(tail_pts, tail_nrms, width=[0.028, 0.028, 0.027, 0.025, 0.021, 0.014],
                thickness=0.0075, mat="leather_strap", bevel=0.30, smooth=True)
        # Brass keeper rivet stud centered cleanly on the strap just below the buckle
        p_riv = pack_point(ang_bk - 0.14, v_lat, offset=0.0155)
        b.ellipsoid(p_riv, (0.0052, 0.0052, 0.0052), "brass_bright", sides=8, rows=4)

    # --- C. Curved Kidney-Bean / Teardrop Oiled-Leather Canteen (right-front) ---
    # Placed leaning naturally beside the ration bundle with generous clearance from the gathered linen ear
    c_origin = Vector((0.278, -0.048, 0.018))
    rot_c = Matrix.Rotation(math.radians(-24.0), 3, "Z") @ Matrix.Rotation(math.radians(15.0), 3, "Y") @ Matrix.Rotation(math.radians(-8.0), 3, "X")

    def c_world(lx, ly, lz):
        return c_origin + (rot_c @ Vector((lx, ly, lz)))

    # Kidney-teardrop curved spine centerline in local (x=width, y=flatness, z=height)
    nz_can = 24
    na_can = 24
    can_rings = []
    welt_left, welt_right = [], []

    def canteen_spine(t):
        """Plump traditional stitched teardrop/kidney leather canteen profile (smooth rounded pouch base)."""
        cx = 0.030 * math.sin(t * math.pi) - 0.016 * (t ** 1.55)
        cz = 0.390 * t
        # Smooth plump teardrop envelope: fully rounded bottom (t->0), fullest belly at t≈0.34, tapering to neck at t≈0.92
        t_cl = clamp(t, 0.002, 1.0)
        # Smooth teardrop curve: sin(pi*t)^0.58 * (1 - 0.48*t^1.2)
        belly = (math.sin(t_cl * math.pi * 0.96) ** 0.54) * (1.0 - 0.56 * smoothstep(0.32, 0.92, t_cl))
        neck_blend = smoothstep(0.74, 0.98, t_cl)
        rx = 0.156 * belly * (1.0 - 0.85 * neck_blend) + 0.032 * neck_blend
        ry = 0.094 * belly * (1.0 - 0.85 * neck_blend) + 0.029 * neck_blend
        return cx, cz, max(rx, 0.016), max(ry, 0.012)

    for iz in range(nz_can + 1):
        # Start at t=0.012 so the bottom cap closes smoothly into a plump rounded leather pouch (zero pedestal flare)
        t = 0.012 + 0.988 * (iz / nz_can)
        cx, cz, rx, ry = canteen_spine(t)
        ring = []
        for a in angles(na_can):
            ca, sa = math.cos(a), math.sin(a)
            seam_pinch = 1.0 - 0.07 * (ca ** 8) * (1.0 - smoothstep(0.80, 1.0, t))
            dimple = 1.0 + 0.020 * math.sin(a * 2.0 + t * 5.0) * math.sin(t * math.pi)
            lx = cx + rx * ca * dimple
            ly = ry * sa * seam_pinch * dimple
            ring.append(c_world(lx, ly, cz))
        can_rings.append(ring)
        if 0.05 <= t <= 0.86:
            welt_right.append(c_world(cx + rx * 1.02, 0.0, cz))
            welt_left.append(c_world(cx - rx * 1.02, 0.0, cz))

    b.loft(can_rings, "canteen_leather", smooth=True, cap=True, uv_scale=(2.0, 2.0))

    # Pinched perimeter leather welt seam wrapping smoothly around left, rounded bottom, and right pouch edge!
    welt_bottom = []
    cx0, cz0, rx0, _ = canteen_spine(0.05)
    for k in range(7):
        tk = k / 6.0
        a = math.pi * (1.0 - tk)
        welt_bottom.append(c_world(cx0 + (rx0 * 1.02) * math.cos(a), 0.0, cz0 - 0.018 * math.sin(a)))
    full_welt = list(reversed(welt_left)) + welt_bottom[1:-1] + welt_right
    b.tube(full_welt, 0.010, "canteen_welt", sides=8, aspect=0.60)

    # Waxed linen decorative stitch marks along the welt seam
    for idx_w in range(1, len(full_welt) - 1, 2):
        p_st = full_welt[idx_w]
        b.ellipsoid(p_st, (0.0042, 0.0068, 0.0042), "linen_thread", sides=6, rows=3)

    # Turned antique-brass spout collar & lip seated tightly at canteen neck (t = 0.90..1.02)
    neck_cx, neck_cz, _, _ = canteen_spine(0.95)
    collar_prof = [
        (0.030, -0.020), (0.038, -0.016), (0.039, 0.002),
        (0.035, 0.010), (0.042, 0.022), (0.043, 0.032),
        (0.035, 0.038), (0.025, 0.036),
    ]
    collar_rings = [
        [c_world(neck_cx + rr * math.cos(a), rr * math.sin(a), neck_cz + hh) for a in angles(20)]
        for rr, hh in collar_prof
    ]
    b.loft(collar_rings, "brass_antique", smooth=True, cap=True)

    # Turned tapered natural cork stopper protruding from the spout with waist groove
    cork_prof = [
        (0.022, 0.022), (0.027, 0.042), (0.028, 0.056),
        (0.024, 0.064),  # tether tie groove
        (0.031, 0.074), (0.033, 0.094), (0.029, 0.104), (0.016, 0.107),
    ]
    cork_rings = [
        [c_world(neck_cx + rr * math.cos(a), rr * math.sin(a), neck_cz + hh) for a in angles(18)]
        for rr, hh in cork_prof
    ]
    b.loft(cork_rings, "cork", smooth=True, cap=True)

    # Leather belly harness belt hugging the canteen snugly around t = 0.46
    t_hb = 0.46
    h_cx, h_cz, h_rx, h_ry = canteen_spine(t_hb)
    hb_path, hb_nrms = [], []
    for a in angles(24):
        ca, sa = math.cos(a), math.sin(a)
        hb_path.append(c_world(h_cx + (h_rx + 0.0045) * ca, (h_ry + 0.0045) * sa, h_cz))
        hb_nrms.append(rot_c @ Vector((ca, sa, 0.0)))
    b.strap(hb_path, hb_nrms, width=0.024, thickness=0.0075, mat="leather_strap", bevel=0.25, smooth=True, loop=True)

    # Shoulder leather lug + antique-brass small keeper ring (D-ring) on canteen left shoulder (t = 0.74)
    sh_cx, sh_cz, sh_rx, _ = canteen_spine(0.74)
    lug_center = c_world(sh_cx - sh_rx - 0.010, 0.0, sh_cz)
    # Brass small ring perched at the shoulder
    ring_c = c_world(sh_cx - sh_rx - 0.020, 0.0, sh_cz + 0.004)
    dring_pts = [
        ring_c + (rot_c @ Vector((0.016 * math.cos(a), 0.004 * math.sin(a), 0.016 * math.sin(a))))
        for a in angles(16)
    ]
    b.tube(dring_pts, 0.0042, "brass_bright", sides=7, loop=True)
    # Stitched leather anchor tab holding the brass ring
    b.ellipsoid(lug_center, (0.015, 0.012, 0.018), "leather_strap", sides=10, rows=5)

    # Fine leather anti-loss tether cord looping gracefully from the brass ring to the cork groove
    cork_groove = c_world(neck_cx - 0.025, -0.005, neck_cz + 0.064)
    tether_ctrl = [
        ring_c + (rot_c @ Vector((-0.010, -0.004, 0.012))),
        c_world(sh_cx - sh_rx - 0.042, -0.032, sh_cz + 0.045),
        c_world(neck_cx - 0.068, -0.036, neck_cz + 0.035),
        cork_groove,
    ]
    b.tube(catmull_rom(tether_ctrl, samples_per_seg=5), 0.0045, "leather_strap", sides=7)
    # Tight cord loop wrapped cleanly inside the cork stopper groove
    groove_loop = [
        c_world(neck_cx + 0.0275 * math.cos(a), 0.0275 * math.sin(a), neck_cz + 0.064)
        for a in angles(16)
    ]
    b.tube(groove_loop, 0.0042, "leather_strap", sides=6, loop=True)

    # Decorative brass buckle boss on the front of the canteen belly belt (clean tabletop detail)
    b.ellipsoid(c_world(h_cx, -(h_ry + 0.013), h_cz), (0.012, 0.007, 0.012), "brass_bright", sides=10, rows=5)

    # Shift entire assembly so lowest Z touches z=0 cleanly before centering
    min_z = min(v.z for v in b.verts)
    for i in range(len(b.verts)):
        b.verts[i] = Vector((b.verts[i].x, b.verts[i].y, b.verts[i].z - min_z))

    return b


# ---------------------------------------------------------------------------
# Prop 3: cloak_traveler_hooded.glb (折叠旅行兜帽斗篷)
# ---------------------------------------------------------------------------

def _folded_wool_tier(b, cx, cy, z_bot, rx, ry, thickness, yaw_deg, phase,
                      mat_wool="cloak_wool", mat_lining="cloak_lining", turnback=False):
    """Build a soft, organically draped folded wool layer with rounded fold edges."""
    rot = Matrix.Rotation(math.radians(yaw_deg), 3, "Z")
    # Build as a plump rounded pillowed slab with organic cloth ripples along perimeter & top
    # Loft vertically through 7 profile slices (rounded bottom tuck -> plump mid fold -> rounded top)
    n_perim = 36
    # Profile slices: (radial_scale, z_fraction, mat_choice)
    slices = [
        (0.84, 0.00),
        (0.95, 0.14),
        (1.00, 0.36),
        (1.00, 0.64),
        (0.95, 0.86),
        (0.82, 1.00),
    ]
    rings = []
    for s_idx, (r_sc, zf) in enumerate(slices):
        ring = []
        for i in range(n_perim):
            a = TAU * i / n_perim
            ca, sa = math.cos(a), math.sin(a)
            # Soft squircle footprint (folded cloth rectangle with naturally rounded corners)
            p_exp = 3.0
            r_sq = 1.0 / ((abs(ca) ** p_exp + abs(sa) ** p_exp) ** (1.0 / p_exp) + 1e-6)
            # Subtle organic perimeter wave so edges feel like heavy wool folds, not rigid plastic
            wave = 1.0 + 0.036 * math.sin(a * 3.0 + phase) + 0.022 * math.cos(a * 5.0 - phase * 1.3)
            lx = rx * r_sq * ca * r_sc * wave
            ly = ry * r_sq * sa * r_sc * wave
            # Gentle drape height undulation on upper half
            drape_z = (
                0.011 * math.sin(lx * 8.5 + phase) * math.cos(ly * 7.0)
                + 0.008 * math.sin((lx + ly) * 10.0 - phase)
            ) * smoothstep(0.10, 0.85, zf)
            lz = z_bot + thickness * zf + drape_z
            if turnback and lx > rx * 0.32 and ly < -ry * 0.25:
                # Subtle front-right corner lift where parchment lining peeks from underneath
                corner_f = smoothstep(rx * 0.32, rx * 0.85, lx) * smoothstep(-ry * 0.25, -ry * 0.85, ly)
                lz += 0.022 * corner_f * smoothstep(0.0, 0.7, zf)
            pt = Vector((cx, cy, 0.0)) + (rot @ Vector((lx, ly, 0.0)))
            pt.z = max(0.0, lz)
            ring.append(pt)
        rings.append(ring)

    def tier_mat(row, _col):
        # Expose subtle warm parchment lining band peeking inside the lower fold crease
        if row == 1:
            return mat_lining
        return mat_wool

    b.loft(rings, tier_mat if turnback else mat_wool, smooth=True, cap=True, uv_scale=(2.4, 1.0))

    # Add a soft sculpted top drape sheet resting across the upper surface to break flat cap
    nr, nc = 10, 12
    top_g, bot_g = [], []
    for r in range(nr):
        vr = (r / (nr - 1)) * 2.0 - 1.0
        row_t, row_b = [], []
        for c in range(nc):
            vc = (c / (nc - 1)) * 2.0 - 1.0
            # Pull corners slightly inward to match squircle top smoothly
            rad = math.hypot(vc, vr)
            pull = 1.0 - 0.14 * smoothstep(0.7, 1.42, rad)
            lx = vc * rx * 0.88 * pull
            ly = vr * ry * 0.88 * pull
            # Gentle diagonal wool drape creases
            fold = (
                0.013 * math.sin(lx * 10.5 + ly * 5.0 + phase)
                + 0.008 * math.cos(ly * 12.0 - phase)
            ) * (1.0 - 0.55 * clamp(rad * 0.75, 0.0, 1.0))
            crown = 0.018 * (1.0 - clamp((vc * vc + vr * vr) * 0.45, 0.0, 1.0))
            lz = z_bot + thickness + crown + fold
            if turnback and lx > rx * 0.28 and ly < -ry * 0.22:
                cf = smoothstep(rx * 0.28, rx * 0.82, lx) * smoothstep(-ry * 0.22, -ry * 0.82, ly)
                lz += 0.020 * cf
            p_xy = Vector((cx, cy, 0.0)) + (rot @ Vector((lx, ly, 0.0)))
            row_t.append((p_xy.x, p_xy.y, lz))
            row_b.append((p_xy.x, p_xy.y, lz - 0.016))
        top_g.append(row_t)
        bot_g.append(row_b)
    b.thick_sheet(top_g, bot_g, mat_wool, mat_lining, mat_wool, smooth=True, uv_scale=(2.0, 2.0))


def build_cloak_traveler_hooded():
    b = MeshBuilder()

    # 1. Bottom thick folded wool base layer (largest sweep, resting flat on z=0)
    _folded_wool_tier(
        b, cx=0.0, cy=0.015, z_bot=0.0, rx=0.388, ry=0.312, thickness=0.088,
        yaw_deg=-5.0, phase=0.4, mat_wool="cloak_wool", mat_lining="cloak_lining", turnback=False,
    )

    # 2. Subtle warm parchment-ivory folded lining layer tucked cleanly between bottom & middle wool folds
    _folded_wool_tier(
        b, cx=0.012, cy=-0.014, z_bot=0.074, rx=0.348, ry=0.276, thickness=0.028,
        yaw_deg=3.5, phase=1.7, mat_wool="cloak_lining", mat_lining="cloak_lining", turnback=False,
    )

    # 3. Upper folded wool tier (naturally hand-folded angle, subtle corner fold peeking the parchment lining)
    _folded_wool_tier(
        b, cx=-0.012, cy=0.012, z_bot=0.096, rx=0.342, ry=0.270, thickness=0.078,
        yaw_deg=6.0, phase=2.6, mat_wool="cloak_wool", mat_lining="cloak_lining", turnback=True,
    )

    # 4. Sculpted Pointed Traveler's Hood draped softly across the top of the folded cloak!
    # Build as a true closed, double-walled hollow cloth cowl (outer wool + thick rolled brim + warm parchment inner lining)
    # Parameter u along hood depth: 0 = front opening rim -> 1 = drooping pointed back tip
    # Parameter a around cross-section loop: 0 = right cheek, pi/2 = crown top, pi = left cheek, 3pi/2 = chin/base resting on cloak
    nu_hood = 18
    na_hood = 24
    # Centerline path sweeping from front-left opening back toward rear-right drooping point
    def hood_spine(u):
        # Smooth draped hood spine resting snugly over z ≈ 0.175
        u_pos = max(0.0, u)
        hx = -0.028 + 0.105 * (u_pos ** 1.35) + 0.020 * math.sin(u_pos * math.pi)
        hy = -0.175 + 0.445 * u
        # Crown arches up gracefully near u=0.28, then droops smoothly onto the folded cloak back near u=1.0
        hz = 0.248 + 0.036 * math.sin(u_pos * math.pi * 0.92) - 0.078 * (u_pos ** 1.75)
        # Cross-section radii: open wide at front (u=0..0.35), tapering organically to a soft pointed tip at u=1
        open_env = 1.0 - smoothstep(0.28, 1.0, u_pos) ** 1.15
        rx = 0.168 * (0.14 + 0.86 * open_env) + 0.014 * math.sin(u_pos * math.pi)
        rz = 0.108 * (0.12 + 0.88 * open_env) + 0.012 * math.sin(u_pos * math.pi)
        return hx, hy, hz, rx, rz

    def hood_ring_pts(u, radial_off=0.0):
        hx, hy, hz, rx, rz = hood_spine(u)
        pts = []
        for a in angles(na_hood):
            ca, sa = math.cos(a), math.sin(a)
            # Soft gothic pointed arch slight peak at top of hood (sa > 0) + flattened bottom sitting on cloak (sa < 0)
            arch_peak = 0.022 * max(0.0, sa) ** 3 * (1.0 - 0.45 * u)
            # Natural heavy-wool drape ripples along hood cheeks & crown
            pleat = (
                0.0085 * math.sin(a * 4.0 + u * 5.2)
                + 0.0055 * math.cos(a * 6.0 - u * 4.0)
            ) * smoothstep(0.04, 0.85, u) * (1.0 - 0.5 * u)
            lx = (rx + radial_off + pleat) * ca
            lz = (rz + radial_off + pleat * 0.7) * sa + arch_peak
            if sa < 0.0:
                # Flatten underside softly against folded cloak top (z ≈ 0.162)
                lz *= 0.62
            # Subtle forward-curving hood brim flare at front edge
            flare_y = -0.022 * max(0.0, sa) * (1.0 - smoothstep(0.0, 0.35, u))
            pts.append(Vector((hx + lx, hy + flare_y, max(0.158, hz + lz))))
        return pts

    # Construct continuous closed manifold ring-loop:
    # Outer wall (u=0.98 -> u=0.0) -> thick rolled brim lip -> Inner lining wall (u=0.03 -> u=0.82) -> closed inner tip!
    outer_us = [0.99 - 0.99 * (i / nu_hood) for i in range(nu_hood + 1)]
    # Rolled soft wool brim around u=0
    brim_rings = [
        hood_ring_pts(0.00, radial_off=0.008),
        hood_ring_pts(-0.018, radial_off=0.002),
        hood_ring_pts(-0.014, radial_off=-0.012),
        hood_ring_pts(0.015, radial_off=-0.020),
    ]
    inner_us = [0.08 + 0.72 * (i / 10.0) for i in range(11)]

    all_hood_rings = []
    ring_mats = []
    for u in outer_us:
        all_hood_rings.append(hood_ring_pts(u, radial_off=0.0))
        ring_mats.append("cloak_wool")
    for br in brim_rings:
        all_hood_rings.append(br)
        ring_mats.append("cloak_wool")
    for idx_in, u in enumerate(inner_us):
        # Inner lining smoothly tucks inward and stays clear of outer shell
        off_in = -0.024 * (1.0 - 0.55 * u)
        all_hood_rings.append(hood_ring_pts(u, radial_off=off_in))
        # Warm parchment lining visible around the hood opening; deep shadowed wool further inside
        ring_mats.append("cloak_lining" if idx_in < 5 else "cloak_wool_deep")

    def hood_mat_fn(row, _col):
        return ring_mats[min(row, len(ring_mats) - 1)]

    b.loft(all_hood_rings, hood_mat_fn, smooth=True, cap=True, uv_scale=(2.2, 2.0))

    # Extra plump rolled piping welt tracing the front hood rim for crisp light-novel figurine silhouette
    rim_path = hood_ring_pts(-0.012, radial_off=0.006)
    b.tube(rim_path, 0.0115, "cloak_wool", sides=8, loop=True)

    # 5. Soft Rounded Draped Shoulder Collar Folds hugging smoothly under the hood throat (zero sharp corners!)
    for side in (-1.0, 1.0):
        # Soft plump wool collar fold sweeping gracefully from chin outward over the folded top tier
        collar_ctrl = [
            Vector((-0.020 + side * 0.028, -0.195, 0.196)),
            Vector((-0.020 + side * 0.112, -0.205, 0.190)),
            Vector((-0.020 + side * 0.215, -0.155, 0.180)),
            Vector((-0.020 + side * 0.255, -0.055, 0.172)),
        ]
        c_pts = catmull_rom(collar_ctrl, samples_per_seg=4)
        c_rad = [0.022 + 0.010 * math.sin((i / max(len(c_pts) - 1, 1)) * math.pi) for i in range(len(c_pts))]
        b.tube(c_pts, c_rad, "cloak_wool", sides=10, aspect=0.52)

    # 6. Refined Matte Antique-Gold Crescent-Moon & Leaf Cloak Clasp pinned cleanly at the front collar
    clasp_c = Vector((-0.022, -0.204, 0.206))
    clasp_rot = Matrix.Rotation(math.radians(52.0), 3, "X") @ Matrix.Rotation(math.radians(-4.0), 3, "Z")

    def c_xf(v_local):
        return clasp_c + (clasp_rot @ v_local)

    # Two antique-gold circular cloak-fastener medallions flanking cleanly left & right of the crescent
    for side_x in (-0.088, 0.088):
        disc_poly = [(side_x + 0.022 * math.cos(a), 0.006 + 0.022 * math.sin(a)) for a in angles(16)]
        b.beveled_plate(disc_poly, -0.004, 0.008, "brass_antique", bevel=0.0025, inset_ratio=0.86, transform=c_xf)
        b.ellipsoid(c_xf(Vector((side_x, 0.006, 0.009))), (0.009, 0.009, 0.006), "brass_bright", sides=10, rows=5)

    # Central hero Crescent Moon (balanced upright crescent cradling the sculpted leaf brooch)
    crescent = []
    n_cr = 14
    for i in range(n_cr + 1):
        a = math.pi * 0.32 + math.pi * 1.36 * (i / n_cr)  # C-shaped crescent opening cleanly to the right
        crescent.append((-0.006 + 0.044 * math.cos(a), -0.002 + 0.044 * math.sin(a)))
    for i in range(n_cr, -1, -1):
        a = math.pi * 0.42 + math.pi * 1.16 * (i / n_cr)
        crescent.append((0.006 + 0.032 * math.cos(a), -0.002 + 0.032 * math.sin(a)))
    b.beveled_plate(crescent, 0.001, 0.014, "brass_antique", bevel=0.003, inset_ratio=0.88, transform=c_xf)

    # Sculpted slender antique-gold leaf blade nestling cleanly inside the crescent (zero overlap with medallions)
    leaf_poly = []
    n_lf = 10
    for i in range(n_lf + 1):
        t = i / n_lf
        lx = -0.028 + 0.068 * t
        w = 0.015 * math.sin(t * math.pi) ** 0.78
        leaf_poly.append((lx, -0.002 + w + 0.005 * math.sin(t * math.pi)))
    for i in range(n_lf - 1, 0, -1):
        t = i / n_lf
        lx = -0.028 + 0.068 * t
        w = 0.015 * math.sin(t * math.pi) ** 0.78
        leaf_poly.append((lx, -0.002 - w + 0.005 * math.sin(t * math.pi)))
    b.beveled_plate(leaf_poly, 0.006, 0.018, "brass_bright", bevel=0.0025, inset_ratio=0.84, transform=c_xf)

    # Central raised leaf vein rib + delicate sea-mist water crystal gem accent
    vein_pts = [c_xf(Vector((-0.024 + 0.060 * (i / 6.0), -0.002 + 0.005 * math.sin(i / 6.0 * math.pi), 0.019))) for i in range(7)]
    b.tube(vein_pts, 0.0026, "brass_antique", sides=6)
    b.ellipsoid(c_xf(Vector((0.006, 0.000, 0.019))), (0.008, 0.006, 0.005), "water_gem", sides=10, rows=5)

    # Delicate antique-gold draped chain links connecting left medallion -> crescent -> right medallion
    for seg_sign in (-1.0, 1.0):
        inner_x = -0.044 if seg_sign < 0 else 0.036
        chain_ctrl = [
            c_xf(Vector((seg_sign * 0.074, 0.004, 0.010))),
            c_xf(Vector((seg_sign * 0.058, -0.010, 0.012))),
            c_xf(Vector((inner_x, -0.002, 0.012))),
        ]
        ch_pts = catmull_rom(chain_ctrl, samples_per_seg=4)
        b.tube(ch_pts, 0.0034, "brass_bright", sides=6)
        for pt_b in ch_pts[1:-1:2]:
            b.ellipsoid(pt_b, (0.0048, 0.0048, 0.0048), "brass_antique", sides=7, rows=4)

    return b


# ---------------------------------------------------------------------------
# Prop 4: lantern_brass_travel.glb (复古黄铜防风提灯)
# ---------------------------------------------------------------------------

def build_lantern_brass_travel():
    b = MeshBuilder()

    # 1. Turned Stepped Circular Antique-Brass Base & Oil Fount (z = 0.0 .. 0.202)
    base_prof = [
        (0.150, 0.006),  # recessed underside foot interior (360-degree bottom detail)
        (0.185, 0.000),  # outer foot resting ring
        (0.232, 0.000),
        (0.238, 0.014),  # lower beaded plinth lip
        (0.228, 0.028),
        (0.214, 0.038),
        (0.220, 0.050),  # stepped molding bead
        (0.202, 0.064),
        (0.212, 0.098),  # plump oil-tank fount belly
        (0.206, 0.132),
        (0.182, 0.156),  # dark patina waist groove
        (0.168, 0.165),
        (0.186, 0.176),  # upper gallery deck flange
        (0.186, 0.192),
        (0.164, 0.202),  # glass-seat bezel
        (0.134, 0.202),
    ]

    def base_mat(row, _col):
        if row in (6, 10, 11):
            return "brass_dark"
        if row in (3, 12, 13):
            return "brass_bright"
        return "brass_antique"

    b.lathe(base_prof, base_mat, sides=26, smooth=True, cap=True, uv_scale=(2.0, 1.4))

    # Decorative micro rivets ringing the stepped base shoulder
    for a in angles(12, start=math.pi / 12.0):
        b.ellipsoid((0.177 * math.cos(a), 0.177 * math.sin(a), 0.184),
                    (0.006, 0.006, 0.006), "brass_bright", sides=7, rows=4)

    # Side Oil-Filler Cap (front-left shoulder, angled outward)
    cap_ang = math.radians(-135.0)
    cap_dir = Vector((math.cos(cap_ang), math.sin(cap_ang), 0.48)).normalized()
    cap_base = Vector((0.188 * math.cos(cap_ang), 0.188 * math.sin(cap_ang), 0.125))
    cap_path = [cap_base + cap_dir * d for d in (0.0, 0.016, 0.022, 0.032, 0.038)]
    b.tube(cap_path, [0.018, 0.018, 0.023, 0.023, 0.017], "brass_bright", sides=12)

    # Side Knurled Wick-Adjuster Stem & Thumbwheel (front-right shoulder)
    wk_ang = math.radians(-38.0)
    wk_dir = Vector((math.cos(wk_ang), math.sin(wk_ang), 0.10)).normalized()
    wk_base = Vector((0.174 * math.cos(wk_ang), 0.174 * math.sin(wk_ang), 0.168))
    b.tube([wk_base, wk_base + wk_dir * 0.056], [0.008, 0.007], "brass_dark", sides=8)
    wheel_c = wk_base + wk_dir * 0.060
    # Mini knurled brass thumbwheel disc perpendicular to wk_dir
    ref_v = Vector((0, 0, 1))
    u_ax = wk_dir.cross(ref_v).normalized()
    v_ax = wk_dir.cross(u_ax).normalized()
    wheel_rings = []
    for offset_w, r_sc in ((-0.006, 0.85), (-0.004, 1.0), (0.004, 1.0), (0.006, 0.85)):
        ring = []
        for i in range(16):
            a = TAU * i / 16
            knurl = 0.021 + (0.0022 if i % 2 == 0 else -0.0012)
            ring.append(wheel_c + wk_dir * offset_w + (u_ax * math.cos(a) + v_ax * math.sin(a)) * (knurl * r_sc))
        wheel_rings.append(ring)
    b.loft(wheel_rings, "brass_bright", smooth=False, cap=True)

    # 2. Interior Miniature Brass Oil Burner Seat + Charred Wick + Glowing Amber Flame
    burner_prof = [
        (0.115, 0.196),
        (0.115, 0.214),
        (0.088, 0.228),
        (0.068, 0.246),
        (0.072, 0.256),  # burner crown rim
        (0.044, 0.264),
        (0.026, 0.268),
    ]
    b.lathe(burner_prof, "brass_antique", sides=22, smooth=True, cap=True)
    # Miniature burner gallery crown collar
    b.lathe([(0.084, 0.216), (0.089, 0.224), (0.084, 0.232)], "brass_bright", sides=20, smooth=True, cap=True)

    # Charred cotton wick stub rising from burner nozzle
    b.lathe([(0.015, 0.262), (0.014, 0.284), (0.011, 0.290)], "charred_wick", sides=10, smooth=True, cap=True)

    # Organic Teardrop Warm-Amber Self-Luminous Flame Core (z = 0.284 .. 0.398)
    flame_rings = []
    nz_fl = 14
    na_fl = 16
    for iz in range(nz_fl + 1):
        t = iz / nz_fl  # 0 = wick base -> 1 = slender flickering tip
        z = 0.284 + 0.116 * t
        # Teardrop radius envelope: plump lower belly at t≈0.28, elegant flame point at t=1
        r_fl = 0.034 * (math.sin(t * math.pi) ** 0.72) * (1.0 - 0.55 * (t ** 1.35)) + 0.0018
        # Gentle organic flicker sway
        sway_x = 0.0055 * math.sin(t * math.pi * 1.15) * (t ** 1.1)
        sway_y = -0.0030 * math.sin(t * math.pi * 1.4) * t
        ring = []
        for a in angles(na_fl):
            # Very gentle petal fluting for liveliness
            rf = r_fl * (1.0 + 0.06 * math.sin(a * 3.0 + t * 2.5) * math.sin(t * math.pi))
            ring.append((sway_x + rf * math.cos(a), sway_y + rf * math.sin(a), z))
        flame_rings.append(ring)
    b.loft(flame_rings, "lantern_flame", smooth=True, cap=True, uv_scale=(1.0, 1.0))

    # 3. Classical Gently-Bulged Frosted Glass Chimney (single clean outer shell for Godot BLEND)
    glass_prof = []
    nz_gl = 14
    for iz in range(nz_gl + 1):
        t = iz / nz_gl
        z = 0.200 + 0.362 * t  # z = 0.200 .. 0.562
        # Graceful pear/lantern-globe swell: narrower top & bottom, plump classical waist around t=0.45
        bulge = math.sin(t * math.pi) ** 0.82
        r_gl = 0.128 - 0.008 * t + 0.052 * bulge
        glass_prof.append((r_gl, z))
    b.lathe(glass_prof, "lantern_glass", sides=24, smooth=True, cap=True, uv_scale=(2.0, 1.0))

    # 4. Four Gracefully Outward-Curving Slender Brass Guard Pillars + Two Horizontal Guard Rings
    # Placed at 45, 135, 225, 315 deg so front view frames the glowing flame symmetrically!
    def pillar_radius(t):
        # Smooth outward bow clearing glass max radius (0.178) comfortably with ~0.042 margin
        return 0.166 - 0.006 * t + 0.055 * (math.sin(t * math.pi) ** 0.80)

    pillar_angs = [math.radians(a) for a in (45.0, 135.0, 225.0, 315.0)]
    for ang in pillar_angs:
        ca, sa = math.cos(ang), math.sin(ang)
        p_path = []
        n_p = 11
        for i in range(n_p + 1):
            t = i / n_p
            z = 0.188 + 0.378 * t
            r = pillar_radius(t)
            p_path.append((r * ca, r * sa, z))
        b.tube(p_path, 0.0082, "brass_antique", sides=7)
        # Stepped anchor lug ferrules at bottom & top sockets
        for z_lug, r_lug in ((0.194, 0.167), (0.560, 0.161)):
            b.ellipsoid((r_lug * ca, r_lug * sa, z_lug), (0.015, 0.015, 0.013), "brass_bright", sides=7, rows=4)

    # Two horizontal slender brass guard rings bridging all 4 pillars
    for t_ring in (0.32, 0.68):
        z_ring = 0.188 + 0.378 * t_ring
        r_ring = pillar_radius(t_ring)
        ring_pts = [(r_ring * math.cos(a), r_ring * math.sin(a), z_ring) for a in angles(24)]
        b.tube(ring_pts, 0.0068, "brass_bright", sides=6, loop=True)
        # Tiny soldered collar beads at each of the 4 pillar intersections
        for ang in pillar_angs:
            b.ellipsoid((r_ring * math.cos(ang), r_ring * math.sin(ang), z_ring),
                        (0.0115, 0.0115, 0.0115), "brass_antique", sides=7, rows=4)

    # 5. Multi-Tiered Ventilated Heat-Dissipation Brass Chimney Dome Cap (z = 0.556 .. 0.778)
    # 5a. Lower wide rain-baffle eaves collar sheltering the glass top
    eaves_prof = [
        (0.125, 0.556),
        (0.168, 0.556),
        (0.228, 0.568),  # wide overhanging storm rain eaves
        (0.232, 0.578),
        (0.214, 0.588),
        (0.168, 0.602),
        (0.148, 0.610),
    ]
    b.lathe(eaves_prof, lambda r, _c: "brass_bright" if r in (2, 3) else "brass_antique",
            sides=26, smooth=True, cap=True)

    # 5b. Openwork Ventilated Heat-Dissipation Tier (recessed dark flue core + 8 angled brass louver struts)
    flue_prof = [
        (0.098, 0.602),
        (0.096, 0.674),
        (0.088, 0.682),
    ]
    b.lathe(flue_prof, "brass_dark", sides=20, smooth=True, cap=True)

    # 8 sculpted outward-slanted brass louver fins framing genuine openwork heat vents!
    for i in range(8):
        a = TAU * i / 8.0 + math.pi / 8.0
        ca, sa = math.cos(a), math.sin(a)
        tx, ty = -sa, ca
        # Each louver fin is a crisp beveled vertical vane spanning z=0.604..0.674
        fin_path = [
            (0.146 * ca, 0.146 * sa, 0.602),
            (0.152 * ca, 0.152 * sa, 0.638),
            (0.142 * ca, 0.142 * sa, 0.676),
        ]
        fin_nrms = [(tx * 0.85 + ca * 0.52, ty * 0.85 + sa * 0.52, 0.0)] * 3
        b.strap(fin_path, fin_nrms, width=0.024, thickness=0.008, mat="brass_antique", bevel=0.25, smooth=True)
    # Mid-vent horizontal brass ring collar uniting the louver fins
    vent_ring = [(0.149 * math.cos(a), 0.149 * math.sin(a), 0.638) for a in angles(28)]
    b.tube(vent_ring, 0.0058, "brass_bright", sides=6, loop=True)

    # 5c. Upper Storm Cap Cupola Dome & Turned Finial Knob (z = 0.668 .. 0.782)
    dome_prof = [
        (0.132, 0.668),
        (0.184, 0.676),  # secondary upper rain hood lip
        (0.186, 0.686),
        (0.166, 0.698),
        (0.138, 0.716),
        (0.104, 0.734),
        (0.068, 0.746),
        (0.036, 0.752),
        (0.022, 0.758),  # finial neck
        (0.032, 0.770),  # finial acorn sphere
        (0.024, 0.780),
        (0.008, 0.786),
    ]
    b.lathe(dome_prof, lambda r, _c: "brass_bright" if r in (1, 2, 9, 10) else "brass_antique",
            sides=28, smooth=True, cap=True)

    # 6. Articulated Curved Brass Carrying Bail Handle + Turned Dark-Walnut Heat Grip
    # Forged side hinge ear lugs on ±X shoulders of the rain eaves (z = 0.592)
    ear_z = 0.594
    ear_x = 0.194
    for sx in (-1.0, 1.0):
        # Bracket block protruding at ±X
        b.ellipsoid((sx * (ear_x - 0.008), 0.0, ear_z), (0.024, 0.016, 0.018), "brass_dark", sides=10, rows=5)
        # Pivot eye ring
        eye_pts = [
            (sx * (ear_x + 0.012) + 0.014 * math.cos(a), 0.0, ear_z + 0.014 * math.sin(a))
            for a in angles(14)
        ]
        b.tube(eye_pts, 0.0048, "brass_bright", sides=6, loop=True)

    # Curved carrying wire bail tilted naturally 20 degrees backward (+Y) so it reads clearly articulated!
    bail_tilt = Matrix.Rotation(math.radians(-20.0), 3, "X")
    pivot_c = Vector((0.0, 0.0, ear_z + 0.008))

    def bail_pt(lx, lz):
        return pivot_c + (bail_tilt @ Vector((lx, 0.0, lz)))

    # Graceful S-scroll wire profile from left ear lug up over dome crown (lz_max = 0.285) to right ear lug
    bail_ctrl = [
        bail_pt(-0.214, -0.006),
        bail_pt(-0.244, 0.028),
        bail_pt(-0.252, 0.118),
        bail_pt(-0.210, 0.215),
        bail_pt(-0.125, 0.272),
        bail_pt(0.0, 0.292),
        bail_pt(0.125, 0.272),
        bail_pt(0.210, 0.215),
        bail_pt(0.252, 0.118),
        bail_pt(0.244, 0.028),
        bail_pt(0.214, -0.006),
    ]
    bail_smooth = catmull_rom(bail_ctrl, samples_per_seg=4)
    b.tube(bail_smooth, 0.0076, "brass_antique", sides=8)

    # Turned dark walnut wood heat-insulated grip barrel wrapped smoothly around the bail crown
    grip_center = bail_pt(0.0, 0.290)
    grip_prof = [
        (0.012, -0.088),
        (0.017, -0.084),  # left brass ferrule
        (0.017, -0.072),
        (0.020, -0.068),  # walnut grip shoulder
        (0.025, -0.036),
        (0.027, 0.000),   # comfortable turned swell
        (0.025, 0.036),
        (0.020, 0.068),
        (0.017, 0.072),   # right brass ferrule
        (0.017, 0.084),
        (0.012, 0.088),
    ]

    def grip_mat(row, _col):
        if row in (0, 1, 8, 9):
            return "brass_bright"
        return "walnut_wood"

    b.lathe(grip_prof, grip_mat, sides=18, center=tuple(grip_center), axis="X", smooth=True, cap=True)

    return b


# ---------------------------------------------------------------------------
# GLB Export, Strict Verification & Studio Photography
# ---------------------------------------------------------------------------

ASSETS = (
    ("book_sister_grimoire", "《姐姐的水魔术手记》", build_book_sister_grimoire),
    ("pack_travel_rations", "旅途干粮包与皮水囊", build_pack_travel_rations),
    ("cloak_traveler_hooded", "折叠旅行兜帽斗篷", build_cloak_traveler_hooded),
    ("lantern_brass_travel", "复古黄铜防风提灯", build_lantern_brass_travel),
)


def inspect_glb(path, mesh):
    data = path.read_bytes()
    magic, version, length, json_size, json_tag = struct.unpack_from("<4sIII4s", data)
    assert (magic, version, length, json_tag) == (b"glTF", 2, len(data), b"JSON"), f"{path}: invalid GLB header"
    doc = json.loads(data[20:20 + json_size])
    assert len(doc["meshes"]) == 1 and len(doc["nodes"]) == 1, f"{path}: expected 1 mesh & 1 node"
    assert "uri" not in doc["buffers"][0], f"{path}: external buffer URI found"
    primitives = doc["meshes"][0]["primitives"]
    assert all(p.get("mode", 4) == 4 for p in primitives), f"{path}: non-triangle primitive"
    accessors = doc["accessors"]
    tris = sum(accessors[p["indices"]]["count"] for p in primitives) // 3
    assert tris == len(mesh.loop_triangles), f"{path}: tri mismatch ({tris} vs {len(mesh.loop_triangles)})"
    assert 3000 <= tris <= 9000, f"{path}: {tris} triangles outside [3000, 9000]"
    pos_accs = [accessors[p["attributes"]["POSITION"]] for p in primitives]
    lo = [min(a["min"][i] for a in pos_accs) for i in range(3)]
    hi = [max(a["max"][i] for a in pos_accs) for i in range(3)]
    center_err = max(abs(a + b) * 0.5 for a, b in zip(lo, hi))
    extent = max(b - a for a, b in zip(lo, hi))
    assert center_err < 1e-4, f"{path}: bbox center offset {center_err}"
    assert 0.90 <= extent <= 1.00, f"{path}: max extent {extent:.4f} outside [0.9, 1.0]"
    if path.stem == "lantern_brass_travel":
        glass_mats = [m for m in doc.get("materials", []) if "Glass" in m.get("name", "")]
        assert glass_mats and glass_mats[0].get("alphaMode") == "BLEND", f"{path}: glass missing BLEND alphaMode"
    return tris, len(data), extent


def build_assets(mat_lib):
    meshes = {}
    stats = []
    for stem, label, builder_fn in ASSETS:
        b = builder_fn()
        mesh = b.build_mesh(stem, mat_lib, target_extent=TARGET_EXTENT)
        obj = bpy.data.objects.new(stem, mesh)
        bpy.context.collection.objects.link(obj)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        out_path = PROPS_DIR / f"{stem}.glb"
        bpy.ops.export_scene.gltf(
            filepath=str(out_path),
            export_format="GLB",
            use_selection=True,
            export_yup=True,
            export_animations=False,
            export_materials="EXPORT",
            export_texcoords=True,
            export_normals=True,
        )
        tris, nbytes, ext = inspect_glb(out_path, mesh)
        print(f"TRAVEL_PROP {stem}: {tris} triangles, {nbytes} bytes ({nbytes / 1024:.1f} KB), extent={ext:.4f}", flush=True)
        bpy.data.objects.remove(obj, do_unlink=True)
        meshes[stem] = mesh
        stats.append((stem, label, tris, nbytes, ext))
    return meshes, stats


def _aim(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def _load_cjk_font():
    candidates = [
        "/System/Library/Fonts/STHeiti Medium.ttc",
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/Supplemental/Songti.ttc",
        "/System/Library/Fonts/Hiragino Sans GB.ttc",
    ]
    for path in candidates:
        if Path(path).exists():
            try:
                return bpy.data.fonts.load(path)
            except Exception:
                pass
    return bpy.data.fonts.get("Bfont Regular") or next(iter(bpy.data.fonts), None)


def _studio_table_mat():
    mat = bpy.data.materials.new("Studio · Deep Warm Taupe")
    if mat.node_tree is None:
        mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.78
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 18.0
    noise.inputs["Detail"].default_value = 5.0
    noise.inputs["Roughness"].default_value = 0.62
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.22
    ramp.color_ramp.elements[0].color = hex_rgba("3B302A")
    ramp.color_ramp.elements[1].position = 0.80
    ramp.color_ramp.elements[1].color = hex_rgba("54453D")
    links.new(noise.outputs["Fac"], ramp.inputs[0])
    links.new(ramp.outputs[0], bsdf.inputs["Base Color"])
    return mat


def _make_studio_scene(name, width, height, table_mat, samples=48):
    scene = bpy.data.scenes.new(name)
    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 8
    scene.cycles.transparent_max_bounces = 8
    scene.cycles.transmission_bounces = 4
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 0.15

    world = bpy.data.worlds.new(f"{name}_world")
    if world.node_tree is None:
        world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = hex_rgba("3D3532")
    bg.inputs["Strength"].default_value = 0.34
    scene.world = world

    # Smooth curved cyclorama studio sweep (tabletop at z=0 curving up smoothly at +Y)
    prof_pts = [
        (-8.0, -6.0, 0.0), (8.0, -6.0, 0.0),
    ]
    n_arc = 14
    sweep_verts = []
    sweep_faces = []
    xs_sw = (-10.0, 10.0)
    ys_zs = [(-7.0, 0.0), (1.4, 0.0)]
    for i in range(1, n_arc + 1):
        a = -math.pi * 0.5 + math.pi * 0.5 * (i / n_arc)
        ys_zs.append((1.4 + 2.8 * math.cos(a), 2.8 + 2.8 * math.sin(a)))
    ys_zs.append((4.2, 8.5))
    for y, z in ys_zs:
        sweep_verts.append((xs_sw[0], y, z))
        sweep_verts.append((xs_sw[1], y, z))
    for r in range(len(ys_zs) - 1):
        i0 = r * 2
        sweep_faces.append((i0, i0 + 1, i0 + 3, i0 + 2))
    cyc_mesh = bpy.data.meshes.new(f"{name}_cyc")
    cyc_mesh.from_pydata(sweep_verts, [], sweep_faces)
    for p in cyc_mesh.polygons:
        p.use_smooth = True
    cyc_mesh.materials.append(table_mat)
    cyc_obj = bpy.data.objects.new(f"{name}_cyc", cyc_mesh)
    scene.collection.objects.link(cyc_obj)

    # Three-point studio lighting: Warm softbox key + Cool rim contour light + Soft parchment bounce
    lights = [
        ("Key Warm Softbox", (-3.8, -4.4, 4.8), 1150.0, (1.0, 0.87, 0.72), 4.6, 3.2),
        ("Rim Cool Accent", (3.6, 3.4, 2.8), 720.0, (0.72, 0.86, 1.0), 4.2, 2.4),
        ("Fill Parchment Bounce", (3.8, -3.6, 1.9), 340.0, (0.98, 0.91, 0.82), 4.8, 2.8),
    ]
    for title, loc, energy, col, w, h in lights:
        ld = bpy.data.lights.new(title, "AREA")
        ld.shape = "RECTANGLE"
        ld.size = w
        ld.size_y = h
        ld.energy = energy
        ld.color = col
        lo = bpy.data.objects.new(title, ld)
        scene.collection.objects.link(lo)
        lo.location = loc
        _aim(lo, (0.0, 0.0, 0.25))

    return scene


def _place_on_table(scene, mesh, name, x, y, yaw_deg=0.0, pitch_deg=0.0, roll_deg=0.0, scale=1.0):
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    obj.scale = (scale, scale, scale)
    obj.rotation_euler = (math.radians(pitch_deg), math.radians(roll_deg), math.radians(yaw_deg))
    # Compute lowest world Z so the prop rests cleanly on tabletop z=0 with zero float/sink
    rot_m = obj.rotation_euler.to_matrix()
    min_z = min((rot_m @ (v.co * scale)).z for v in mesh.vertices)
    obj.location = (x, y, -min_z)
    return obj


def _add_lantern_glow_light(scene, lantern_obj):
    """Studio-only warm candle point light inside the lantern glass so renders show authentic warm aura."""
    ld = bpy.data.lights.new("Lantern Inner Flame Glow", "POINT")
    ld.energy = 14.0
    ld.color = (1.0, 0.68, 0.28)
    ld.shadow_soft_size = 0.045
    lo = bpy.data.objects.new("Lantern Inner Flame Glow", ld)
    scene.collection.objects.link(lo)
    # Flame sits slightly below vertical center of the normalized lantern
    lo.location = lantern_obj.location + Vector((0.0, 0.0, -0.055 * lantern_obj.scale.z))
    return lo


def _add_caption(scene, font, ink_mat, text, loc, size, tilt_deg=26.0):
    curve = bpy.data.curves.new(f"Cap_{text}", "FONT")
    if font is not None:
        curve.font = font
    curve.body = text
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    curve.size = size
    curve.materials.append(ink_mat)
    obj = bpy.data.objects.new(f"Cap_{text}", curve)
    scene.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (math.radians(tilt_deg), 0.0, 0.0)
    return obj


def _render_to_array(scene, tmp_path):
    scene.render.filepath = str(tmp_path)
    bpy.ops.render.render(write_still=True, scene=scene.name)
    img = bpy.data.images.load(str(tmp_path))
    w, h = img.size[0], img.size[1]
    arr = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(arr)
    bpy.data.images.remove(img)
    return arr.reshape((h, w, 4))


def render_previews(meshes):
    table_mat = _studio_table_mat()
    ink_mat = _make_pbr_mat("Studio · Caption Ink", "F0DFC8", roughness=0.55,
                            emission_hex="F2E2CC", emission_strength=0.45)
    font = _load_cjk_font()

    # 1. Lineup Shot: travel_gear_lineup.png (4 props side-by-side oblique tabletop showcase)
    lineup = _make_studio_scene("Travel Gear Lineup", 2200, 960, table_mat, samples=56)
    placements = [
        ("book_sister_grimoire", "《姐姐的水魔术手记》", -1.48, 0.04, 20.0, 0.0, 0.0),
        ("pack_travel_rations", "旅途干粮包与皮水囊", -0.50, 0.00, -10.0, 0.0, 0.0),
        ("cloak_traveler_hooded", "折叠旅行兜帽斗篷", 0.50, 0.02, 12.0, 0.0, 0.0),
        ("lantern_brass_travel", "复古黄铜防风提灯", 1.48, -0.02, -16.0, 0.0, 0.0),
    ]
    for stem, label, px, py, yaw, pitch, roll in placements:
        obj = _place_on_table(lineup, meshes[stem], f"Lineup_{stem}", px, py, yaw_deg=yaw, pitch_deg=pitch, roll_deg=roll)
        if stem == "lantern_brass_travel":
            _add_lantern_glow_light(lineup, obj)
        _add_caption(lineup, font, ink_mat, label, (px, -0.78, 0.012), size=0.092, tilt_deg=22.0)

    cam_data = bpy.data.cameras.new("LineupCam")
    cam_data.lens = 45.0
    cam_obj = bpy.data.objects.new("LineupCam", cam_data)
    lineup.collection.objects.link(cam_obj)
    cam_obj.location = (0.0, -5.25, 3.05)
    _aim(cam_obj, (0.0, -0.06, 0.25))
    lineup.camera = cam_obj

    lineup_path = PREVIEWS_DIR / "travel_gear_lineup.png"
    print(f"STUDIO {lineup_path.name}", flush=True)
    lineup.render.filepath = str(lineup_path)
    bpy.ops.render.render(write_still=True, scene=lineup.name)

    # 2. 2x2 Macro Closeup Grid: travel_gear_closeup.png (each quadrant rendered cleanly with tailored macro camera)
    quad_w, quad_h = 1024, 720
    quad_specs = [
        # (stem, caption, yaw, cam_loc, aim_target, lens, cap_loc)
        ("book_sister_grimoire", "手记 · 封面书脊与丝带", 26.0, (-0.72, -1.24, 0.96), (0.02, -0.08, 0.11), 62.0, (-0.06, -0.58, 0.012)),
        ("pack_travel_rations", "补给 · 干粮捆带与皮水囊", -12.0, (0.24, -1.52, 0.78), (0.03, -0.04, 0.23), 62.0, (0.02, -0.45, 0.012)),
        ("cloak_traveler_hooded", "装束 · 兜帽褶皱与新月金扣", 10.0, (-0.16, -1.38, 0.80), (-0.01, -0.08, 0.23), 62.0, (-0.02, -0.52, 0.012)),
        ("lantern_brass_travel", "营具 · 黄铜护笼与暖光内焰", -18.0, (0.34, -1.78, 0.76), (0.00, -0.02, 0.44), 58.0, (0.00, -0.42, 0.012)),
    ]
    tiles = []
    tmp_tile = PREVIEWS_DIR / "_tmp_closeup_tile.png"
    for idx, (stem, cap_text, yaw, cam_loc, target, lens, cap_loc) in enumerate(quad_specs):
        sc = _make_studio_scene(f"Closeup_{idx}_{stem}", quad_w, quad_h, table_mat, samples=56)
        obj = _place_on_table(sc, meshes[stem], f"Macro_{stem}", 0.0, 0.0, yaw_deg=yaw)
        if stem == "lantern_brass_travel":
            _add_lantern_glow_light(sc, obj)

        cd = bpy.data.cameras.new(f"MacroCam_{idx}")
        cd.lens = lens
        co = bpy.data.objects.new(f"MacroCam_{idx}", cd)
        sc.collection.objects.link(co)
        co.location = cam_loc
        _aim(co, target)
        sc.camera = co

        print(f"STUDIO closeup tile {idx + 1}/4: {stem}", flush=True)
        tiles.append(_render_to_array(sc, tmp_tile))

    if tmp_tile.exists():
        tmp_tile.unlink()

    # Stitch 2x2 grid (Blender pixel arrays are bottom-to-top rows!)
    # Top row = tiles[0] (left), tiles[1] (right); Bottom row = tiles[2] (left), tiles[3] (right)
    pad = 6
    full_h = quad_h * 2 + pad
    full_w = quad_w * 2 + pad
    canvas = np.zeros((full_h, full_w, 4), dtype=np.float32)
    # Warm antique-gold hairline border color (in sRGB-encoded output space from loaded PNG)
    canvas[:, :, 0] = 0.66
    canvas[:, :, 1] = 0.54
    canvas[:, :, 2] = 0.36
    canvas[:, :, 3] = 1.0
    # Bottom row (y = 0 .. quad_h)
    canvas[0:quad_h, 0:quad_w, :] = tiles[2]
    canvas[0:quad_h, quad_w + pad:full_w, :] = tiles[3]
    # Top row (y = quad_h + pad .. full_h)
    canvas[quad_h + pad:full_h, 0:quad_w, :] = tiles[0]
    canvas[quad_h + pad:full_h, quad_w + pad:full_w, :] = tiles[1]

    closeup_path = PREVIEWS_DIR / "travel_gear_closeup.png"
    out_img = bpy.data.images.new("travel_gear_closeup", width=full_w, height=full_h, alpha=False)
    out_img.pixels.foreach_set(canvas.ravel())
    out_img.filepath_raw = str(closeup_path)
    out_img.file_format = "PNG"
    out_img.save()
    bpy.data.images.remove(out_img)
    print(f"STUDIO {closeup_path.name} ({full_w}x{full_h})", flush=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    PROPS_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEWS_DIR.mkdir(parents=True, exist_ok=True)
    mat_lib = build_material_library()
    meshes, _stats = build_assets(mat_lib)
    render_previews(meshes)


if __name__ == "__main__":
    main()
