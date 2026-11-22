"""Build 6 stylized low-poly watercolor miniature biome props for World Map M3.

Run headless from repository root:
    /Users/mac/.local/bin/blender --background --python tools/blender_world_v2/build_biome_props.py

Exports:
    assets/3d/world_v2/props/prop_tree_broadleaf.glb
    assets/3d/world_v2/props/prop_tree_meadow.glb
    assets/3d/world_v2/props/prop_tree_pine_snow.glb
    assets/3d/world_v2/props/prop_demon_deadwood.glb
    assets/3d/world_v2/props/prop_demon_crystal.glb
    assets/3d/world_v2/props/prop_rock_cluster.glb
    tools/blender_world_v2/previews/biome_props_lineup.png
"""

import json
import math
from pathlib import Path
import struct
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
import numpy as np


sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import build_world_map_blender as legacy_map  # Reuse shared render_shot & GLB binary readers.

OUT_PROPS_DIR = ROOT / "assets/3d/world_v2/props"
OUT_PREVIEW = Path(__file__).resolve().parent / "previews/biome_props_lineup.png"


def srgb_hex_to_linear_rgba(hex_str: str) -> tuple[float, float, float, float]:
    h = hex_str.lstrip("#")
    sr = int(h[0:2], 16) / 255.0
    sg = int(h[2:4], 16) / 255.0
    sb = int(h[4:6], 16) / 255.0

    def to_lin(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return (to_lin(sr), to_lin(sg), to_lin(sb), 1.0)


def lerp_col(c0: tuple[float, float, float, float], c1: tuple[float, float, float, float], t: float) -> tuple[float, float, float, float]:
    t = max(0.0, min(1.0, t))
    return (
        c0[0] + (c1[0] - c0[0]) * t,
        c0[1] + (c1[1] - c0[1]) * t,
        c0[2] + (c1[2] - c0[2]) * t,
        1.0,
    )


def create_vertex_color_material(name: str = "WatercolorVertexColorMat", roughness: float = 0.84) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.18
    vcol = nt.nodes.new("ShaderNodeVertexColor")
    vcol.layer_name = "Col"
    nt.links.new(vcol.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


class PropBuilder:
    """Helper to sculpt crisp flat-faceted meshes with painted linear RGBA face colors."""

    def __init__(self, name: str):
        self.name = name
        self.bm = bmesh.new()
        self.cidx_layer = self.bm.faces.layers.int.new("cidx")
        self.color_palette: list[tuple[float, float, float, float]] = []
        self._palette_lookup: dict[tuple[float, float, float, float], int] = {}

    def _add_face(self, verts: list, color: tuple[float, float, float, float]) -> None:
        try:
            f = self.bm.faces.new(verts)
        except ValueError:
            return
        f.smooth = False
        qcol = tuple(round(c, 5) for c in color)
        if qcol not in self._palette_lookup:
            self._palette_lookup[qcol] = len(self.color_palette)
            self.color_palette.append(qcol)
        f[self.cidx_layer] = self._palette_lookup[qcol]

    def add_tube(
        self,
        centers: list[Vector],
        radii: list[float],
        sides: int,
        c_bot: tuple[float, float, float, float],
        c_top: tuple[float, float, float, float],
        cap_bottom: bool = True,
        cap_top: bool = True,
        twist: float = 0.0,
    ) -> None:
        assert len(centers) == len(radii) and len(centers) >= 2
        rings: list[list] = []
        n_rings = len(centers)
        for idx, (ctr, rad) in enumerate(zip(centers, radii)):
            t = idx / (n_rings - 1)
            prev_c = centers[max(0, idx - 1)]
            next_c = centers[min(n_rings - 1, idx + 1)]
            tangent = (next_c - prev_c)
            if tangent.length_squared < 1e-8:
                tangent = Vector((0.0, 0.0, 1.0))
            tangent.normalize()
            ref = Vector((0.0, 1.0, 0.0)) if abs(tangent.y) < 0.85 else Vector((1.0, 0.0, 0.0))
            u_ax = tangent.cross(ref).normalized()
            v_ax = tangent.cross(u_ax).normalized()
            ring = []
            for s in range(sides):
                ang = math.tau * s / sides + idx * twist
                wobble = 1.0 + 0.07 * math.sin(ang * 2.0 + idx * 1.3)
                p = ctr + (u_ax * math.cos(ang) + v_ax * math.sin(ang)) * (rad * wobble)
                ring.append(self.bm.verts.new(p))
            rings.append(ring)

        if cap_bottom:
            self._add_face(list(reversed(rings[0])), c_bot)
        for r_i in range(n_rings - 1):
            t_mid = (r_i + 0.5) / (n_rings - 1)
            col = lerp_col(c_bot, c_top, t_mid)
            r0, r1 = rings[r_i], rings[r_i + 1]
            for s in range(sides):
                sn = (s + 1) % sides
                self._add_face([r0[s], r0[sn], r1[sn], r1[s]], col)
        if cap_top:
            self._add_face(rings[-1], c_top)

    def add_dome(
        self,
        center: Vector,
        rx: float,
        ry: float,
        rz: float,
        sides: int,
        c_bot: tuple[float, float, float, float],
        c_mid: tuple[float, float, float, float],
        c_top: tuple[float, float, float, float],
        asym_seed: float = 0.0,
        flat_bottom: float = 0.72,
    ) -> None:
        """Compact stylized faceted foliage puff / boulder (exact predictable tris)."""
        v_bot = self.bm.verts.new(center + Vector((0.0, 0.0, -rz * flat_bottom)))
        v_top = self.bm.verts.new(center + Vector((0.03 * rx, -0.02 * ry, rz * 0.90)))

        ring_low = []
        ring_high = []
        for s in range(sides):
            ang_l = math.tau * s / sides + asym_seed * 0.4
            ang_h = ang_l + math.tau / (sides * 2.0)  # Stagger facets cleanly!
            w_l = 1.0 + 0.14 * math.sin(ang_l * 2.0 + asym_seed) + 0.08 * math.cos(ang_l * 3.0 - asym_seed)
            w_h = 1.0 + 0.11 * math.cos(ang_h * 2.0 - asym_seed * 1.3)
            ring_low.append(self.bm.verts.new(center + Vector((
                math.cos(ang_l) * rx * 0.98 * w_l,
                math.sin(ang_l) * ry * 0.98 * w_l,
                -rz * 0.22,
            ))))
            ring_high.append(self.bm.verts.new(center + Vector((
                math.cos(ang_h) * rx * 0.80 * w_h,
                math.sin(ang_h) * ry * 0.80 * w_h,
                rz * 0.44,
            ))))

        for s in range(sides):
            sn = (s + 1) % sides
            self._add_face([v_bot, ring_low[sn], ring_low[s]], c_bot)
            # Staggered belt triangles (gives hand-carved polygonal look instead of boring quads)
            belt_shade = lerp_col(c_bot, c_mid, 0.55 + 0.25 * math.sin(s * 1.7 + asym_seed))
            self._add_face([ring_low[s], ring_low[sn], ring_high[s]], belt_shade)
            up_shade = lerp_col(c_mid, c_top, 0.35 + 0.25 * math.cos(s * 1.3 - asym_seed))
            self._add_face([ring_low[sn], ring_high[sn], ring_high[s]], up_shade)
            crown_shade = lerp_col(c_mid, c_top, 0.78 + 0.22 * math.sin(s * 1.1 + asym_seed))
            self._add_face([ring_high[s], ring_high[sn], v_top], crown_shade)

    def add_pointed_prism(
        self,
        base_pos: Vector,
        tilt_dir: Vector,
        length: float,
        r_base: float,
        r_shoulder: float,
        sides: int,
        c_bot: tuple[float, float, float, float],
        c_mid: tuple[float, float, float, float],
        c_tip: tuple[float, float, float, float],
        rot_offset: float = 0.0,
    ) -> None:
        axis = tilt_dir.normalized()
        ref = Vector((0.0, 1.0, 0.0)) if abs(axis.y) < 0.85 else Vector((1.0, 0.0, 0.0))
        u_ax = axis.cross(ref).normalized()
        v_ax = axis.cross(u_ax).normalized()

        ring_b = []
        ring_s = []
        shoulder_z = length * 0.72
        for k in range(sides):
            ang = math.tau * k / sides + rot_offset
            radial = u_ax * math.cos(ang) + v_ax * math.sin(ang)
            ring_b.append(self.bm.verts.new(base_pos + radial * r_base))
            ring_s.append(self.bm.verts.new(base_pos + axis * shoulder_z + radial * r_shoulder))
        v_tip = self.bm.verts.new(base_pos + axis * length)

        self._add_face(list(reversed(ring_b)), c_bot)
        for k in range(sides):
            kn = (k + 1) % sides
            side_shift = 0.14 * math.sin(k * 1.5 + rot_offset)
            self._add_face([ring_b[k], ring_b[kn], ring_s[kn], ring_s[k]], lerp_col(c_bot, c_mid, 0.62 + side_shift))
            self._add_face([ring_s[k], ring_s[kn], v_tip], lerp_col(c_mid, c_tip, 0.74 + side_shift))

    def finalize_object(self, material: bpy.types.Material, recenter_xy: bool = True, ground_z: bool = True) -> tuple[bpy.types.Object, int]:
        # Triangulate everything explicitly; bmesh preserves the per-face "cidx" layer automatically!
        bmesh.ops.triangulate(self.bm, faces=self.bm.faces[:])
        self.bm.normal_update()

        # Snap bottom strictly to Z = 0 and optionally center XY bounds for clean placement
        coords = [v.co.copy() for v in self.bm.verts]
        min_x = min(c.x for c in coords)
        max_x = max(c.x for c in coords)
        min_y = min(c.y for c in coords)
        max_y = max(c.y for c in coords)
        min_z = min(c.z for c in coords)
        cx = (min_x + max_x) * 0.5 if recenter_xy else 0.0
        cy = (min_y + max_y) * 0.5 if recenter_xy else 0.0
        cz = min_z if ground_z else 0.0
        for v in self.bm.verts:
            v.co.x -= cx
            v.co.y -= cy
            v.co.z -= cz

        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        mesh.update()

        # Write crisp linear RGBA corner color attribute ("Col") after to_mesh
        col_attr = mesh.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="CORNER")
        fi_read = self.bm.faces.layers.int.get("cidx")
        for poly, bm_f in zip(mesh.polygons, self.bm.faces):
            rgba = self.color_palette[bm_f[fi_read]] if fi_read is not None else (0.8, 0.8, 0.8, 1.0)
            for loop_idx in poly.loop_indices:
                col_attr.data[loop_idx].color = rgba

        mesh.materials.append(material)
        self.bm.free()

        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(obj)
        return obj, len(mesh.polygons)


# ---------------------------------------------------------------------------
# 6 Stylized Low-Poly Prop Recipes (strictly 40..140 triangles)
# ---------------------------------------------------------------------------
def build_tree_broadleaf(mat: bpy.types.Material):
    """Milis Great Forest: sculpted trunk + 3 asymmetric sage/sprout canopy domes."""
    pb = PropBuilder("prop_tree_broadleaf")
    bark_bot = srgb_hex_to_linear_rgba("#463122")
    bark_top = srgb_hex_to_linear_rgba("#644834")
    fol_shadow = srgb_hex_to_linear_rgba("#466D55")
    fol_mid = srgb_hex_to_linear_rgba("#699362")
    fol_sun = srgb_hex_to_linear_rgba("#99B875")

    # Gentle organic trunk (3 rings x 5 sides = 20 side tris + bottom = 23 tris)
    pb.add_tube(
        centers=[Vector((0.0, 0.0, 0.0)), Vector((0.02, -0.01, 0.24)), Vector((-0.02, 0.02, 0.48))],
        radii=[0.088, 0.060, 0.044],
        sides=5,
        c_bot=bark_bot,
        c_top=bark_top,
        cap_bottom=True,
        cap_top=False,
    )
    # 3 overlapping canopy puffs (5-sided = 20 tris each -> 60 tris) -> ~83 tris total, bump to 6-sided lower puffs = ~95 tris
    pb.add_dome(Vector((-0.14, 0.09, 0.56)), 0.30, 0.28, 0.24, 6, fol_shadow, fol_mid, lerp_col(fol_mid, fol_sun, 0.45), asym_seed=0.5)
    pb.add_dome(Vector((0.18, -0.08, 0.62)), 0.28, 0.26, 0.23, 6, fol_shadow, fol_mid, lerp_col(fol_mid, fol_sun, 0.65), asym_seed=2.1)
    pb.add_dome(Vector((0.01, 0.02, 0.80)), 0.33, 0.31, 0.27, 6, lerp_col(fol_shadow, fol_mid, 0.45), lerp_col(fol_mid, fol_sun, 0.45), fol_sun, asym_seed=4.0)
    return pb.finalize_object(mat, recenter_xy=True, ground_z=True)


def build_tree_meadow(mat: bpy.types.Material):
    """Central Plains: asymmetric tall warm tree + cozy companion shrub."""
    pb = PropBuilder("prop_tree_meadow")
    bark_bot = srgb_hex_to_linear_rgba("#4E3828")
    bark_top = srgb_hex_to_linear_rgba("#70523B")
    leaf_low = srgb_hex_to_linear_rgba("#527A4E")
    leaf_mid = srgb_hex_to_linear_rgba("#78A05E")
    leaf_tip = srgb_hex_to_linear_rgba("#BCC372")

    # Main graceful leaning trunk (4 sides x 3 rings + cap = 18 tris)
    pb.add_tube(
        centers=[Vector((-0.05, 0.0, 0.0)), Vector((-0.07, 0.03, 0.23)), Vector((-0.04, -0.02, 0.48))],
        radii=[0.078, 0.052, 0.036],
        sides=4,
        c_bot=bark_bot,
        c_top=bark_top,
        cap_bottom=True,
        cap_top=False,
    )
    # Main twin foliage puffs (6-sided = 24 tris each -> 48 tris)
    pb.add_dome(Vector((-0.09, 0.04, 0.56)), 0.29, 0.27, 0.24, 6, leaf_low, leaf_mid, lerp_col(leaf_mid, leaf_tip, 0.45), asym_seed=1.2)
    pb.add_dome(Vector((0.02, -0.03, 0.80)), 0.27, 0.26, 0.24, 6, lerp_col(leaf_low, leaf_mid, 0.4), leaf_mid, leaf_tip, asym_seed=3.4)

    # Companion shrub nestled beside main root (tiny stem + low lush dome = 6 + 20 = 26 tris)
    pb.add_tube(
        centers=[Vector((0.21, -0.06, 0.0)), Vector((0.22, -0.07, 0.16))],
        radii=[0.045, 0.030],
        sides=4,
        c_bot=bark_bot,
        c_top=bark_top,
        cap_bottom=True,
        cap_top=False,
    )
    pb.add_dome(Vector((0.23, -0.07, 0.28)), 0.20, 0.19, 0.18, 5, leaf_low, leaf_mid, lerp_col(leaf_mid, leaf_tip, 0.65), asym_seed=5.0)
    return pb.finalize_object(mat, recenter_xy=True, ground_z=True)


def build_tree_pine_snow(mat: bpy.types.Material):
    """Northern Tundra & Mountain Shoulders: 3-tier miniature alpine pine with ivory snow caps."""
    pb = PropBuilder("prop_tree_pine_snow")
    bark_bot = srgb_hex_to_linear_rgba("#422E23")
    bark_top = srgb_hex_to_linear_rgba("#5C4233")
    pine_deep = srgb_hex_to_linear_rgba("#2B4B4D")
    pine_mid = srgb_hex_to_linear_rgba("#466D65")
    snow_cap = srgb_hex_to_linear_rgba("#EAE6D8")
    snow_lit = srgb_hex_to_linear_rgba("#F5F2E6")

    # Trunk (5 sides, 2 rings + bottom = 13 tris)
    pb.add_tube(
        centers=[Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, 0.26))],
        radii=[0.085, 0.056],
        sides=5,
        c_bot=bark_bot,
        c_top=bark_top,
        cap_bottom=True,
        cap_top=False,
    )

    # 3 stacked conical scalloped tiers with steep needle bottom + snowy upper shoulder
    tiers = [
        # (z_base, z_shoulder, z_top, r_skirt, r_shoulder, r_neck, sides, snow_ratio)
        (0.18, 0.34, 0.48, 0.36, 0.24, 0.14, 7, 0.42),
        (0.42, 0.59, 0.74, 0.29, 0.18, 0.09, 7, 0.65),
        (0.66, 0.85, 1.06, 0.22, 0.10, 0.00, 7, 0.92),
    ]
    for t_idx, (zb, zs, zt, rb, rs, rn, sides, snow_mix) in enumerate(tiers):
        ring_bot = []
        ring_mid = []
        rot = t_idx * 0.32
        for k in range(sides):
            ang = math.tau * k / sides + rot
            jag = 1.0 + 0.09 * math.sin(ang * 3.0 + t_idx)
            ring_bot.append(pb.bm.verts.new(Vector((math.cos(ang) * rb * jag, math.sin(ang) * rb * jag, zb))))
            ring_mid.append(pb.bm.verts.new(Vector((math.cos(ang + 0.08) * rs * jag, math.sin(ang + 0.08) * rs * jag, zs))))
        pb._add_face(list(reversed(ring_bot)), pine_deep)

        lower_col = lerp_col(pine_deep, pine_mid, 0.45 + 0.2 * t_idx)
        upper_snow = lerp_col(pine_mid, snow_cap, snow_mix)
        for k in range(sides):
            kn = (k + 1) % sides
            pb._add_face([ring_bot[k], ring_bot[kn], ring_mid[kn], ring_mid[k]], lower_col)

        if rn > 0.001:
            ring_neck = []
            for k in range(sides):
                ang = math.tau * k / sides + rot + 0.12
                ring_neck.append(pb.bm.verts.new(Vector((math.cos(ang) * rn, math.sin(ang) * rn, zt))))
            for k in range(sides):
                kn = (k + 1) % sides
                pb._add_face([ring_mid[k], ring_mid[kn], ring_neck[kn], ring_neck[k]], lerp_col(upper_snow, snow_lit, 0.35))
        else:
            v_apex = pb.bm.verts.new(Vector((0.01, -0.01, zt)))
            for k in range(sides):
                kn = (k + 1) % sides
                pb._add_face([ring_mid[k], ring_mid[kn], v_apex], snow_lit)

    return pb.finalize_object(mat, recenter_xy=True, ground_z=True)


def build_demon_deadwood(mat: bpy.types.Material):
    """Demon Wastes: twisted gnarled deadwood + splayed bare limbs + dry root tuft."""
    pb = PropBuilder("prop_demon_deadwood")
    wood_root = srgb_hex_to_linear_rgba("#3D2820")
    wood_mid = srgb_hex_to_linear_rgba("#705442")
    wood_tip = srgb_hex_to_linear_rgba("#AA8F7A")
    scrub_col = srgb_hex_to_linear_rgba("#786545")

    # Crooked tapered main trunk
    pb.add_tube(
        centers=[
            Vector((0.0, 0.0, 0.0)),
            Vector((0.05, -0.03, 0.25)),
            Vector((-0.04, 0.04, 0.55)),
            Vector((-0.11, 0.07, 0.88)),
            Vector((-0.17, 0.10, 1.00)),
        ],
        radii=[0.105, 0.072, 0.052, 0.026, 0.011],
        sides=5,
        c_bot=wood_root,
        c_top=wood_tip,
        cap_bottom=True,
        cap_top=True,
        twist=0.14,
    )
    # Right gnarled branch splitting at mid-trunk
    pb.add_tube(
        centers=[Vector((0.0, 0.01, 0.44)), Vector((0.18, -0.08, 0.64)), Vector((0.30, -0.14, 0.80))],
        radii=[0.046, 0.027, 0.010],
        sides=4,
        c_bot=wood_mid,
        c_top=wood_tip,
        cap_bottom=False,
        cap_top=True,
    )
    # Left secondary fork near crown
    pb.add_tube(
        centers=[Vector((-0.06, 0.04, 0.60)), Vector((-0.24, -0.11, 0.75)), Vector((-0.31, -0.17, 0.88))],
        radii=[0.036, 0.021, 0.009],
        sides=4,
        c_bot=wood_mid,
        c_top=wood_tip,
        cap_bottom=False,
        cap_top=True,
    )
    # Two dry spiky scrub horns tucked cleanly around root base (no float!)
    pb.add_pointed_prism(Vector((0.10, 0.08, 0.0)), Vector((0.45, 0.25, 0.85)), 0.30, 0.065, 0.022, 4, wood_root, scrub_col, wood_tip, 0.4)
    pb.add_pointed_prism(Vector((-0.12, -0.06, 0.0)), Vector((-0.38, -0.22, 0.90)), 0.26, 0.058, 0.018, 4, wood_root, scrub_col, wood_tip, 1.1)
    return pb.finalize_object(mat, recenter_xy=True, ground_z=True)


def build_demon_crystal(mat: bpy.types.Material):
    """Demon Rifts & Migurd Basin: clustered hexagonal emerald green-ore spires."""
    pb = PropBuilder("prop_demon_crystal")
    base_dark = srgb_hex_to_linear_rgba("#1A3D3F")
    ore_mid = srgb_hex_to_linear_rgba("#2E867B")
    ore_tip = srgb_hex_to_linear_rgba("#8AE6D6")
    stone_collar = srgb_hex_to_linear_rgba("#4C403A")

    # Basalt mineral base collar strictly grounded at Z=0
    pb.add_dome(Vector((0.0, 0.0, 0.09)), 0.30, 0.28, 0.13, 6, stone_collar, base_dark, ore_mid, asym_seed=0.7, flat_bottom=0.68)

    # 4 splayed crystal prisms
    pb.add_pointed_prism(Vector((0.0, 0.0, 0.04)), Vector((0.06, 0.04, 1.0)), 0.94, 0.145, 0.105, 6, base_dark, ore_mid, ore_tip, 0.2)
    pb.add_pointed_prism(Vector((-0.11, -0.07, 0.03)), Vector((-0.38, -0.22, 0.90)), 0.66, 0.105, 0.075, 5, base_dark, ore_mid, ore_tip, 0.9)
    pb.add_pointed_prism(Vector((0.12, 0.06, 0.03)), Vector((0.40, 0.22, 0.88)), 0.56, 0.092, 0.064, 5, base_dark, ore_mid, ore_tip, 1.5)
    pb.add_pointed_prism(Vector((0.04, -0.12, 0.02)), Vector((0.16, -0.45, 0.86)), 0.40, 0.078, 0.048, 4, base_dark, ore_mid, ore_tip, 0.4)
    return pb.finalize_object(mat, recenter_xy=True, ground_z=True)


def build_rock_cluster(mat: bpy.types.Material):
    """Universal faceted boulder cluster in neutral warm grey (tinted per region in Godot)."""
    pb = PropBuilder("prop_rock_cluster")
    rock_bot = srgb_hex_to_linear_rgba("#76726D")
    rock_mid = srgb_hex_to_linear_rgba("#B4AFA7")
    rock_top = srgb_hex_to_linear_rgba("#DED9D0")

    # 3 interlocking crisp boulders
    pb.add_dome(Vector((-0.08, 0.03, 0.23)), 0.34, 0.29, 0.31, 6, rock_bot, rock_mid, rock_top, asym_seed=1.1, flat_bottom=0.74)
    pb.add_dome(Vector((0.24, -0.07, 0.16)), 0.24, 0.22, 0.22, 5, rock_bot, rock_mid, lerp_col(rock_mid, rock_top, 0.7), asym_seed=2.8, flat_bottom=0.72)
    pb.add_dome(Vector((-0.02, -0.22, 0.12)), 0.19, 0.17, 0.16, 4, rock_bot, lerp_col(rock_bot, rock_mid, 0.85), rock_mid, asym_seed=4.4, flat_bottom=0.72)
    return pb.finalize_object(mat, recenter_xy=True, ground_z=True)


# ---------------------------------------------------------------------------
# Strict GLB Validator + Lineup Render
# ---------------------------------------------------------------------------
def export_and_validate_glb(obj: bpy.types.Object, path: Path) -> dict:
    path.parent.mkdir(parents=True, exist_ok=True)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    res = bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        export_yup=True,
        export_animations=False,
        use_selection=True,
    )
    assert "FINISHED" in res, f"GLB export failed for {path.name}: {res}"

    blob = path.read_bytes()
    magic, version, total_len = struct.unpack_from("<4sII", blob, 0)
    json_len, json_type = struct.unpack_from("<I4s", blob, 12)
    gltf = json.loads(blob[20:20 + json_len])
    bin_len, bin_type = struct.unpack_from("<I4s", blob, 20 + json_len)
    binary = blob[28 + json_len:28 + json_len + bin_len]
    assert magic == b"glTF" and version == 2 and json_type == b"JSON" and bin_type == b"BIN\0"

    mesh = gltf["meshes"][0]
    prim = mesh["primitives"][0]
    attrs = prim["attributes"]
    assert "POSITION" in attrs, f"{path.name}: missing POSITION"
    assert "COLOR_0" in attrs, f"{path.name}: missing COLOR_0 vertex colors! attrs={list(attrs.keys())}"
    tris = gltf["accessors"][prim["indices"]]["count"] // 3
    assert 40 <= tris <= 140, f"{path.name}: {tris} tris outside [40, 140] budget!"

    pos = legacy_map.read_float_attribute(gltf, binary, attrs["POSITION"], 3)
    min_y = float(np.min(pos[:, 1]))
    max_y = float(np.max(pos[:, 1]))
    mean_x = float(np.mean(pos[:, 0]))
    mean_z = float(np.mean(pos[:, 2]))
    assert abs(min_y) < 0.004, f"{path.name}: bottom origin drift min_y={min_y:.5f}"
    assert abs(mean_x) < 0.16 and abs(mean_z) < 0.16, f"{path.name}: center drift ({mean_x:.4f}, {mean_z:.4f})"

    # Verify exported COLOR_0 actually contains rich painterly gradients (never uniform fallback grey!)
    c_acc = gltf["accessors"][attrs["COLOR_0"]]
    c_comp = c_acc["componentType"]
    if c_comp == 5126:
        col_arr = legacy_map.read_float_attribute(gltf, binary, attrs["COLOR_0"], 4 if c_acc["type"] == "VEC4" else 3)
    else:
        view = gltf["bufferViews"][c_acc["bufferView"]]
        start = view.get("byteOffset", 0) + c_acc.get("byteOffset", 0)
        w_c = 4 if c_acc["type"] == "VEC4" else 3
        dtype_c = "<u2" if c_comp == 5123 else "<u1"
        norm_c = 65535.0 if c_comp == 5123 else 255.0
        col_arr = np.ndarray((c_acc["count"], w_c), dtype=dtype_c, buffer=binary, offset=start).astype(np.float32) / norm_c
    col_std = float(np.std(col_arr[:, :3]))
    assert col_std > 0.025, f"{path.name}: COLOR_0 appears uniform/flat (std={col_std:.4f})"

    print(
        f"  [OK] {path.name:<24} | {tris:3d} tris | COLOR_0 std={col_std:.3f} | Y=[{min_y:.4f}, {max_y:.3f}] | XZ_avg=({mean_x:+.3f}, {mean_z:+.3f}) | {total_len:,} B",
        flush=True,
    )
    return {"name": path.name, "tris": tris, "max_y": max_y, "bytes": total_len}


def render_lineup_preview(objects: list[bpy.types.Object]) -> None:
    OUT_PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene

    # Arrange the 6 props neatly side by side along Blender X on a warm parchment showcase plinth
    spacing = 1.18
    start_x = -0.5 * (len(objects) - 1) * spacing
    for idx, obj in enumerate(objects):
        obj.location = (start_x + idx * spacing, 0.0, 0.0)
        obj.rotation_euler = (0.0, 0.0, math.radians(-14.0))

    # Warm wood showcase desk + parchment pad underneath
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, -0.06))
    plinth = bpy.context.object
    plinth.scale = (spacing * len(objects) + 0.9, 1.45, 0.12)
    plinth_mat = bpy.data.materials.new("LineupParchment")
    plinth_mat.use_nodes = True
    bsdf = next(n for n in plinth_mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = srgb_hex_to_linear_rgba("#DFD0B2")
    bsdf.inputs["Roughness"].default_value = 0.86
    plinth.data.materials.append(plinth_mat)

    def aim(obj, target):
        obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()

    cam_data = bpy.data.cameras.new("LineupCam")
    cam_data.lens = 38.0
    cam = bpy.data.objects.new("LineupCam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (0.0, -7.8, 2.55)
    aim(cam, (0.0, 0.0, 0.42))
    scene.camera = cam

    sun_data = bpy.data.lights.new("LineupSun", "SUN")
    sun_data.energy = 3.1
    sun_data.color = (1.0, 0.91, 0.76)
    sun_data.angle = math.radians(5.0)
    sun = bpy.data.objects.new("LineupSun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.location = (-5.0, -4.0, 6.0)
    aim(sun, (0.0, 0.0, 0.35))

    fill_data = bpy.data.lights.new("LineupFill", "AREA")
    fill_data.energy = 240.0
    fill_data.color = (0.74, 0.86, 1.0)
    fill_data.size = 6.0
    fill = bpy.data.objects.new("LineupFill", fill_data)
    bpy.context.collection.objects.link(fill)
    fill.location = (4.5, 4.0, 4.5)
    aim(fill, (0.0, 0.0, 0.35))

    scene.world = bpy.data.worlds.new("LineupWorld")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = srgb_hex_to_linear_rgba("#2B2019")
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.65
    scene.view_settings.view_transform = "AgX"
    scene.render.image_settings.file_format = "PNG"
    scene.render.resolution_percentage = 100
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 720
    legacy_map.render_shot(scene, OUT_PREVIEW)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    shared_mat = create_vertex_color_material()
    recipes = [
        ("prop_tree_broadleaf.glb", build_tree_broadleaf),
        ("prop_tree_meadow.glb", build_tree_meadow),
        ("prop_tree_pine_snow.glb", build_tree_pine_snow),
        ("prop_demon_deadwood.glb", build_demon_deadwood),
        ("prop_demon_crystal.glb", build_demon_crystal),
        ("prop_rock_cluster.glb", build_rock_cluster),
    ]

    built_objs: list[bpy.types.Object] = []
    print("Building & Exporting M3 Biome Props:", flush=True)
    for filename, fn in recipes:
        obj, tri_count = fn(shared_mat)
        assert 40 <= tri_count <= 140, f"{filename} mesh tris={tri_count} outside [40, 140]"
        export_and_validate_glb(obj, OUT_PROPS_DIR / filename)
        built_objs.append(obj)

    render_lineup_preview(built_objs)


if __name__ == "__main__":
    main()
