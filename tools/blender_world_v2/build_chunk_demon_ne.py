"""Build the northeast Demon Continent terrain and its independent UV bakes.

blender -b --python-exit-code 1 -P tools/blender_world_v2/build_chunk_demon_ne.py -- --size 4096
"""

import json
import math
from pathlib import Path
import struct
import sys
import tempfile
import zlib

import bpy
import numpy as np
from mathutils import Vector

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_relief_world as relief

ROOT = relief.ROOT
KEY = "chunk_demon_ne"
MANIFEST = ROOT / "scenes/world_map/chunks/world_chunks_manifest.json"


def smooth(lo, hi, v):
    f = np.clip((v - lo) / (hi - lo), 0.0, 1.0)
    return f * f * (3.0 - 2.0 * f)


def sample_grid(grid, u, v, triangular=False):
    fx = np.clip(u, 0, 1) * (grid.shape[1] - 1)
    fz = np.clip(v, 0, 1) * (grid.shape[0] - 1)
    x = np.minimum(fx.astype(np.int32), grid.shape[1] - 2)
    z = np.minimum(fz.astype(np.int32), grid.shape[0] - 2)
    s, t = fx - x, fz - z
    a, b, c, d = grid[z, x], grid[z, x + 1], grid[z + 1, x], grid[z + 1, x + 1]
    if triangular:
        return a + np.where(t > s, t * (c - a) + s * (d - c), s * (b - a) + t * (d - b))
    return (a * (1 - s) + b * s) * (1 - t) + (c * (1 - s) + d * s) * t


def macro_vertices():
    bpy.ops.import_scene.gltf(filepath=str(relief.OUT_GLB))
    mesh = next(obj for obj in bpy.context.selected_objects if obj.name == "TerrainSurface")
    points = np.array([mesh.matrix_world @ v.co for v in mesh.data.vertices])
    u = (points[:, 0] - relief.MIN_X) / relief.WORLD_W
    v = (-points[:, 1] - relief.MIN_Z) / relief.WORLD_D
    grid = np.full((relief.GRID_Z + 1, relief.GRID_X + 1), np.nan, dtype=np.float32)
    grid[np.rint(v * relief.GRID_Z).astype(int), np.rint(u * relief.GRID_X).astype(int)] = points[:, 2]
    if not np.isfinite(grid).all():
        raise ValueError("The macro terrain no longer matches its canonical grid")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    return grid


def coastline():
    image = bpy.data.images.load(str(relief.SOURCE_PNG))
    pixels = relief.legacy_map.raster_image(image)
    bpy.data.images.remove(image)
    silhouette = relief.legacy_map.outer_mask(pixels)
    mask = relief.legacy_map.identify_regions(pixels, silhouette)["demon"]
    # The original inked coastline fixes the zero crossing. The distance
    # farther inland is only used to shape the escarpment and sea shelf.
    sdf = relief.signed_distance_approx(mask) * 0.01
    return relief.gaussian_blur(sdf, 1.1)


def poly_distance(x, z, points):
    distance = np.full(np.broadcast_shapes(x.shape, z.shape), 1e3)
    for a, b in zip(points, points[1:]):
        dx, dz = b - a
        t = np.clip(((x - a[0]) * dx + (z - a[1]) * dz) / (dx * dx + dz * dz), 0, 1)
        distance = np.minimum(distance, np.hypot(x - a[0] - t * dx, z - a[1] - t * dz))
    return distance


def terrace(h, step, phase=0.0):
    layers = (h + phase) / step
    return (np.floor(layers) + smooth(0.40, 0.81, np.mod(layers, 1))) * step - phase


def sculpt_northeast(x, z, bounds, shore, cities, road):
    tx = np.clip((x - bounds[0]) / (bounds[2] - bounds[0]), 0.0, 1.0)
    tz = np.clip((z - bounds[1]) / (bounds[3] - bounds[1]), 0.0, 1.0)
    noise = relief.value_noise_2d
    folds = noise(tx, tz, 10, 9, 43)
    chips = noise(tx, tz, 67, 65, 11)
    fissures = 1 - smooth(0.02, 0.25, abs(noise(tx, tz, 20, 21, 528)))
    mig, town = cities["city_migurd"], cities["city_rikarisu"]

    dx, dz = x - mig[0], z - mig[1]
    angle = np.arctan2(dz, dx)
    basin_dist = np.hypot(dx / 1.04, (dz + 0.018 * np.sin(dx * 13.0)) / 0.82)
    outlet = 1 - smooth(0.20, 0.85, abs(np.arctan2(np.sin(angle - 2.56), np.cos(angle - 2.56))))
    basin_wall = smooth(0.22, 0.44, basin_dist) * (1 - smooth(0.44, 0.68, basin_dist))
    basin_wall *= 1.0 - outlet * 0.87

    dx, dz = x - town[0], z - town[1]
    town_dist = np.maximum(abs(dx + dz * 0.17), abs(dz - dx * 0.24))
    highland = 1 - smooth(0.25, 0.63, town_dist + folds * 0.09)
    spur = np.exp(-((z + 3.55 + 0.55 * (x - 5.9) + 0.07 * np.sin(x * 8)) / 0.25) ** 2)
    western_ridge = 0.28 * spur * (1 - smooth(5.48, 6.28, x))
    rock_height = 0.205 + 0.24 * highland + 0.26 * basin_wall + western_ridge
    rock_height += 0.069 * folds - 0.046 * fissures + 0.016 * chips
    bed_phase = 0.020 * np.sin(x * 7.5 + z * 4.2) + 0.019 * folds
    h = terrace(rock_height, 0.073, bed_phase) * 0.79 + rock_height * 0.21 + 0.008 * chips
    h += 0.011 * np.sin(shore * 105 + x * 7.7 + z * 11.8) * (1 - smooth(0.025, 0.18, shore))
    h *= smooth(-0.002, 0.052 + 0.013 * folds, shore)

    floor_h = 0.23 + 0.006 * folds + 0.006 * chips + 0.016 * dx
    basin_floor = (1 - smooth(0.196, 0.29, basin_dist)) * smooth(0.023, 0.06, shore)
    h = h * (1 - basin_floor) + floor_h * basin_floor
    town_floor = (1 - smooth(0.252, 0.355, town_dist)) * smooth(0.03, 0.09, shore)
    h = h * (1 - town_floor) + (0.455 + 0.010 * dx - 0.019 * dz + 0.004 * folds) * town_floor

    distance = poly_distance(x, z, road)
    road_blend = 1 - smooth(0.026, 0.151, distance)
    progress = smooth(0.0, 1.0, ((x - town[0]) * 0.69 - (z - town[1]) * 0.5) / (0.69**2 + 0.5**2))
    path_height = 0.448 - 0.219 * progress + 0.008 * folds - 0.012 * np.exp(-(distance / 0.026)**2)
    # Stop the carved corridor before it reaches either building footprint.
    road_blend *= smooth(0.18, 0.26, basin_dist) * smooth(0.20, 0.28, town_dist)
    h = h * (1 - road_blend) + path_height * road_blend
    return h

def build_mesh(bounds, height, cells):
    nx, nz = cells
    u, v = np.meshgrid(np.linspace(0, 1, nx + 1), np.linspace(0, 1, nz + 1))
    x = bounds[0] + u * (bounds[2] - bounds[0])
    z = bounds[1] + v * (bounds[3] - bounds[1])
    points = np.stack((x, -z, height), axis=-1).reshape(-1, 3)
    a = (np.arange(nz)[:, None] * (nx + 1) + np.arange(nx)[None, :]).ravel()
    c = a + nx + 1
    faces = np.concatenate([np.stack((a, c, c + 1), -1), np.stack((a, c + 1, a + 1), -1)])
    mesh = bpy.data.meshes.new("SculptedTerraces")
    mesh.from_pydata(points.tolist(), [], faces.tolist())
    mesh.update()
    if mesh.validate():
        raise ValueError("Invalid sculpt triangles")
    mesh.polygons.foreach_set("use_smooth", np.ones(len(faces), dtype=bool))
    uv = mesh.uv_layers.new(name="GroundUV")
    indices = np.empty(len(mesh.loops), dtype=np.int32)
    mesh.loops.foreach_get("vertex_index", indices)
    uv.uv.foreach_set("vector", np.stack((u.ravel()[indices], 1 - v.ravel()[indices]), axis=-1).ravel())
    obj = bpy.data.objects.new("SculptedTerraces", mesh)
    bpy.context.collection.objects.link(obj)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    return obj


def sample_asset_palettes():
    palette = json.loads((ROOT / "assets/textures/world_v2/hero_ground_palette.json").read_text())
    soil = palette["hero_migurd_village"]["skirt_rgb"]
    rock = palette["kit_demon_cliff_a"]["skirt_rgb"]
    # Town albedo remains in the original GLB. Sample the warm masonry pixels.
    raw = (ROOT / "assets/3d/world_v2/heroes/hero_rikarisu_town.glb").read_bytes()
    size = struct.unpack_from("<I", raw, 12)[0]
    gltf = json.loads(raw[20:20 + size])
    idx = gltf["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    img = gltf["images"][gltf["textures"][idx]["source"]]
    view = gltf["bufferViews"][img["bufferView"]]
    offset = 28 + size + view.get("byteOffset", 0)
    with tempfile.TemporaryDirectory() as directory:
        file = Path(directory) / ("town.jpg" if img["mimeType"] == "image/jpeg" else "town.png")
        file.write_bytes(raw[offset:offset + view["byteLength"]])
        image = bpy.data.images.load(str(file))
        rgb = relief.legacy_map.raster_image(image)[::4, ::4, :3].reshape(-1, 3)
        masonry = (rgb[:, 0] > 0.36) & (rgb[:, 0] - rgb[:, 1] > 0.075) & (rgb[:, 1] - rgb[:, 2] > 0.065)
        town = np.median(rgb[masonry], axis=0)
        bpy.data.images.remove(image)
    print("Baked pigment samples", soil, town.tolist(), rock, flush=True)
    return [np.asarray(color, dtype=np.float32) for color in (soil, town, rock)]


def bake_texture_rows(sample_height, bounds, paths, palettes, size):
    width, depth = bounds[2] - bounds[0], bounds[3] - bounds[1]
    x = bounds[0] + ((np.arange(size, dtype=np.float32) + 0.5) / size)[None, :] * width
    soil, town, rock = palettes
    noise = relief.value_noise_2d
    for row in range(0, size, 128):
        z = bounds[1] + ((np.arange(row, min(row + 128, size), dtype=np.float32) + 0.5) / size)[:, None] * depth
        u, v = (x - 2.0) / 6.1, (z + 4.71) / 5.55
        h = sample_height(x, z)
        dx = (sample_height(x + 0.012, z) - sample_height(x - 0.012, z)) / 0.024
        dz = (sample_height(x, z + 0.012) - sample_height(x, z - 0.012)) / 0.024
        slope = smooth(0.32, 1.5, np.hypot(dx, dz))
        sediment = 0.52 + 0.48 * np.sin(135.0 * h + 2.6 * noise(u, v, 13, 12, 88))
        strata = smooth(0.32, 0.76, sediment)
        cavity = np.zeros_like(h)
        for ox, oz in [(1, 0), (0, 1), (-1, 0), (0, -1), (.71, .71), (-.71, .71), (.71, -.71), (-.71, -.71)]:
            near = sample_height(x + 0.035 * ox, z + 0.035 * oz)
            far = sample_height(x + 0.105 * ox, z + 0.105 * oz)
            cavity += np.maximum(0, np.maximum((near - h) / 0.035, (far - h) / 0.105) - 0.15) / 8
        ao = 1.0 - 0.32 * smooth(0.045, 1.18, cavity)
        flecks = noise(u, v, 605, 504, 199)
        mottled = noise(u, v, 75, 56, 107)
        cracks = 1 - smooth(0.018, 0.24, abs(noise(u, v, 137, 103, 432)))
        strata_colors = (town * 0.39 + rock * 0.34 + soil * 0.27) * (0.90 + 0.21 * strata[..., None])
        floor = soil * (0.91 + mottled[..., None] * 0.15) + town * 0.08
        color = floor * (1 - slope[..., None]) + strata_colors * slope[..., None]
        color *= (0.93 + 0.070 * flecks + 0.077 * mottled - 0.085 * cracks)[..., None]
        color *= (0.90 + 0.10 * smooth(0.10, 0.50, h))[..., None]
        color *= 1 - (1 - ao[..., None]) * np.array([0.39, 0.27, 0.15])
        chill = (1 - smooth(3.45, 4.6, x)) * (1 - smooth(-4.42, -3.66, z)) * (0.26 + 0.33 * slope)
        gray_rock = color.mean(axis=-1)[..., None] * np.array([1.01, 1.01, 1.02])
        color = color * (1 - chill[..., None]) + gray_rock * chill[..., None]
        road_distance = np.minimum.reduce([poly_distance(x, z, path) for path in paths])
        path = np.exp(-(road_distance / 0.029)**2) * (1 - slope * 0.59)
        color += path[..., None] * np.array([0.065, 0.053, 0.038])
        # Local Sobel-like gradient of the sub-texel bedding and mineral grains.
        def micro(uu, vv, hh):
            return (0.0013 * np.sin(135 * hh + 2.6 * noise(uu, vv, 13, 12, 88)) * slope
                    + 0.0011 * noise(uu, vv, 605, 504, 199)
                    - 0.0016 * (1 - smooth(.018, .24, abs(noise(uu, vv, 137, 103, 432)))))
        du, dv = (1.5 / size) * width / 6.1, (1.5 / size) * depth / 5.55
        mx = (micro(u + du, v, h + dx * du * 6.1) - micro(u - du, v, h - dx * du * 6.1)) / (2 * du * 6.1)
        mz = (micro(u, v + dv, h + dz * dv * 5.55) - micro(u, v - dv, h - dz * dv * 5.55)) / (2 * dv * 5.55)
        normal = np.stack((-mx, mz, np.ones_like(h)), axis=-1)
        normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
        yield {
            "albedo": color,
            "normal": normal * 0.5 + 0.5,
            "ao": ao,
            "roughness": np.clip(0.82 + 0.060 * slope + 0.045 * mottled + 0.030 * cracks, 0.76, 0.94),
        }


def bake(key, sample_height, bounds, paths, palettes, size, out_dir):
    buffers = {k: (zlib.compressobj(5), bytearray()) for k in ("albedo", "normal", "ao", "roughness")}
    for rows in bake_texture_rows(sample_height, bounds, paths, palettes, size):
        for channel, values in rows.items():
            comp, buffer = buffers[channel]
            channels = 3 if values.ndim == 3 else 1
            pixels = np.rint(np.clip(values, 0, 1) * 255).astype(np.uint8).reshape(-1, size * channels)
            if channel == "roughness":
                # Keep the decoded PNG within the matte range after quantization.
                pixels = np.clip(pixels, math.ceil(0.76 * 255), math.floor(0.94 * 255))
            packed = np.empty((pixels.shape[0], pixels.shape[1] + 1), dtype=np.uint8)
            packed[:, 0] = 1  # PNG Sub filter.
            packed[:, 1:1 + channels] = pixels[:, :channels]
            packed[:, 1 + channels:] = pixels[:, channels:] - pixels[:, :-channels]
            buffer.extend(comp.compress(packed.tobytes()))
    for channel, (comp, buffer) in buffers.items():
        buffer.extend(comp.flush())
        header = struct.pack(">IIBBBBB", size, size, 8, 2 if channel in ("albedo", "normal") else 0, 0, 0, 0)
        chunk = relief._png_chunk
        out = out_dir / f"{key}_{channel}.png"
        out.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", buffer) + chunk(b"IEND", b""))
        print(out.name, out.stat().st_size, flush=True)


def preview(obj, texture_dir, output, bounds):
    scene = bpy.context.scene
    material, shader = relief.make_pbr_mat("Glazed terracotta", (0.68, 0.59, 0.49), .85, 0.0)
    nodes, links = material.node_tree.nodes, material.node_tree.links
    for key, socket in (("albedo", "Base Color"), ("normal", "Normal"), ("roughness", "Roughness")):
        texture = nodes.new("ShaderNodeTexImage")
        texture.image = bpy.data.images.load(str(texture_dir / f"{KEY}_{key}.png"))
        if key != "albedo":
            texture.image.colorspace_settings.name = "Non-Color"
        if key == "normal":
            normal = nodes.new("ShaderNodeNormalMap")
            normal.inputs["Strength"].default_value = 0.8
            links.new(texture.outputs["Color"], normal.inputs["Color"])
            links.new(normal.outputs["Normal"], shader.inputs[socket])
        else:
            links.new(texture.outputs["Color"], shader.inputs[socket])
    obj.data.materials.append(material)
    clay, _ = relief.make_pbr_mat("Ivory plaster", (.64, .60, .52), .87, 0.0)
    ground, _ = relief.make_pbr_mat("Slate blue sea", (.072, .15, .20), .69, 0.0)
    bpy.ops.mesh.primitive_plane_add(size=12.0, location=(6, 3.4, 0))
    sea = bpy.context.object
    sea.data.materials.append(ground)
    sea.visible_shadow = False

    def aim(node, point):
        node.rotation_euler = (Vector(point) - node.location).to_track_quat("-Z", "Y").to_euler()

    for name, location, size, power, color in [
        ("Warm rake", (3.2, 1.8, 3.3), 2.2, 425, (1.0, .81, .65)),
        ("Blue bounce", (8.9, 3.2, 4.5), 3.5, 190, (.73, .86, 1.0)),
        ("Rim", (6.8, 6.1, 2.9), 2.2, 165, (1.0, .84, .69)),
    ]:
        data = bpy.data.lights.new(name, "AREA")
        data.size, data.energy, data.color = size, power, color
        light = bpy.data.objects.new(name, data)
        scene.collection.objects.link(light)
        light.location = location
        aim(light, (6.2, 3.5, 0.1))
    camera = bpy.data.objects.new("Preview", bpy.data.cameras.new("Preview"))
    scene.collection.objects.link(camera)
    scene.camera = camera
    target = (0.5 * (bounds[0] + bounds[2]), -0.5 * (bounds[1] + bounds[3]), .19)
    camera.location = (target[0] + 0.50, target[1] - 4.5, target[2] + 4.6)
    aim(camera, target)
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 3.9
    scene.world = bpy.data.worlds.new("Soft studio")
    scene.world.color = (0.18, .18, .18)
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 18
    scene.cycles.use_denoising = True
    scene.view_settings.view_transform = "AgX"
    scene.render.resolution_x, scene.render.resolution_y = 1000, 820
    scene.render.resolution_percentage = 100
    with tempfile.TemporaryDirectory() as directory:
        cards = []
        for i, mat in enumerate((clay, material)):
            obj.data.materials[0] = mat
            file = Path(directory) / f"{i}.png"
            scene.render.filepath = str(file)
            bpy.ops.render.render(write_still=True)
            img = bpy.data.images.load(str(file))
            cards.append(relief.legacy_map.raster_image(img))
            bpy.data.images.remove(img)
        # Assemble with a fine neutral gutter using the rendered sRGB bytes.
        split = np.full((820, 12, 4), (0.21, 0.18, 0.16, 1.0), dtype=np.float32)
        sheet = np.concatenate((cards[0], split, cards[1]), axis=1)
        relief.write_png_rgba8(output, np.rint(np.clip(sheet, 0, 1) * 255).astype(np.uint8))


if __name__ == "__main__":
    from build_demon_continent_chunks import main
    main(default_chunk=KEY, preview_ne=True)
