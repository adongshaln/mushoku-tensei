"""Clean, scale and export the three optional northeast hero assets.

blender --background --python-exit-code 1 --python tools/blender_world_v2/polish_hero_assets.py
"""

import argparse
import json
import math

import numpy as np
from pathlib import Path
import struct
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector


WORLD = Path(__file__).resolve().parents[2] / "assets/3d/world_v2"
# XZ footprint in Godot units, matte roughness and normal strength.
SPECS = {
    "hero_migurd_village": (0.40, 0.81, 0.45),
    "hero_rikarisu_town": (0.50, 0.78, 0.46),
    "kit_demon_cliff_a": (1.00, 0.85, 0.50),
}
EMBED = 0.02


def glb_json(path):
    with path.open("rb") as stream:
        magic, ver, size, json_size, kind = struct.unpack("<4sIII4s", stream.read(20))
        if (magic, ver, size, kind) != (b"glTF", 2, path.stat().st_size, b"JSON"):
            raise ValueError(f"Invalid GLB 2.0: {path.name}")
        return json.loads(stream.read(json_size))


def map_counts(doc):
    materials = doc.get("materials", [])
    color = sum("baseColorTexture" in m.get("pbrMetallicRoughness", {}) for m in materials)
    normal = sum("normalTexture" in m for m in materials)
    return color, normal


def triangles(mesh):
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def albedo_image(shader):
    base = shader.inputs["Base Color"]
    if base.is_linked and base.links[0].from_node.type == "TEX_IMAGE":
        return base.links[0].from_node.image
    return None


def pixels(image):
    width, height = image.size
    rgba = np.empty(width * height * 4, np.float32)
    image.pixels.foreach_get(rgba)
    return rgba.reshape((height, width, 4))


def micro_normal(image):
    # Suppress isolated texel noise and broad lighting baked into the albedo.
    rgb = pixels(image)[:, :, :3]
    luminance = rgb @ np.array((0.2126, 0.7152, 0.0722), dtype=np.float32)
    def blur(field, radius):
        result = field
        for axis in (0, 1):
            for _ in range(radius):
                result = (np.roll(result, -1, axis) + 2 * result + np.roll(result, 1, axis)) * 0.25
        return result

    fine = blur(luminance, 3)
    relief = fine - blur(fine, 8)
    dx = sum(weight * (np.roll(np.roll(relief, dy, 0), -1, 1)
                       - np.roll(np.roll(relief, dy, 0), 1, 1))
             for dy, weight in ((-1, 1), (0, 2), (1, 1))) * 0.125
    dy = sum(weight * (np.roll(np.roll(relief, dx, 1), -1, 0)
                       - np.roll(np.roll(relief, dx, 1), 1, 0))
             for dx, weight in ((-1, 1), (0, 2), (1, 1))) * 0.125
    gain = 2.8
    vec = np.stack((-np.clip(dx * gain, -.22, .22), -np.clip(dy * gain, -.22, .22),
                    np.ones_like(dx)), axis=-1)
    vec /= np.linalg.norm(vec, axis=-1, keepdims=True)
    rgba = np.ones((*dx.shape, 4), dtype=np.float32)
    rgba[:, :, :3] = vec * 0.5 + 0.5
    normal = bpy.data.images.new(image.name + " Microrelief", *image.size, alpha=False)
    normal.colorspace_settings.name = "Non-Color"
    normal.pixels.foreach_set(np.ascontiguousarray(rgba).ravel())
    normal.update()
    normal.pack()
    return normal


def park_material(material, roughness, strength):
    if material.node_tree is None:
        material.use_nodes = True
    tree = material.node_tree
    output = next((n for n in tree.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output), None)
    shader = next((n for n in tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if output is None or shader is None:
        raise ValueError(f"Missing the imported glTF Principled material: {material.name}")
    base = albedo_image(shader)
    normal_socket = shader.inputs["Normal"]
    if base is not None and not normal_socket.is_linked:
        texture = tree.nodes.new("ShaderNodeTexImage")
        texture.image = micro_normal(base)
        normal = tree.nodes.new("ShaderNodeNormalMap")
        normal.inputs["Strength"].default_value = strength
        tree.links.new(texture.outputs["Color"], normal.inputs["Color"])
        tree.links.new(normal.outputs["Normal"], normal_socket)
    values = {
        "Roughness": roughness, "Metallic": 0.0,
        "Coat Weight": 0.0, "Transmission Weight": 0.0, "Emission Strength": 0.0,
    }
    for name, value in values.items():
        socket = shader.inputs[name]
        for link in list(socket.links):
            tree.links.remove(link)
        socket.default_value = value
    for normal in (n for n in tree.nodes if n.type == "NORMAL_MAP"):
        normal.inputs["Strength"].default_value = strength
        for link in normal.inputs["Color"].links:
            source = link.from_node
            if source.type == "TEX_IMAGE" and source.image is not None:
                source.image.colorspace_settings.name = "Non-Color"
    reachable = {output}
    pending = [output]
    while pending:
        node = pending.pop()
        for socket in node.inputs:
            for link in socket.links:
                if link.from_node not in reachable:
                    reachable.add(link.from_node)
                    pending.append(link.from_node)
    for node in list(tree.nodes):
        if node not in reachable:
            tree.nodes.remove(node)


def join_imported(path, name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    bpy.context.view_layer.update()
    originals = [(obj, obj.matrix_world.copy()) for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not originals:
        raise ValueError(f"No renderable mesh in {path.name}")
    meshes = []
    for obj, transform in originals:
        mesh = obj.data.copy()
        mesh.transform(transform)
        if transform.determinant() < 0:
            mesh.flip_normals()
        baked = bpy.data.objects.new(obj.name + "_baked", mesh)
        bpy.context.collection.objects.link(baked)
        meshes.append(baked)
    for obj in list(bpy.context.scene.objects):
        if obj not in meshes:
            bpy.data.objects.remove(obj, do_unlink=True)
    for obj in meshes:
        obj.select_set(True)
    model = meshes[0]
    bpy.context.view_layer.objects.active = model
    if len(meshes) > 1:
        bpy.ops.object.join()
    model.name = name
    model.data.name = name
    return model


def rebuild_normals(model):
    mesh = model.data
    bm = bmesh.new()
    try:
        bm.from_mesh(mesh)
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=2e-7)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(mesh)
    finally:
        bm.free()
    mesh.update()
    for poly in mesh.polygons:
        poly.use_smooth = True
    mesh.set_sharp_from_angle(angle=math.radians(68))
    mesh.normals_split_custom_set([(0.0, 0.0, 0.0)] * len(mesh.loops))
    weighted = model.modifiers.new("Angle-aware stone normals", "WEIGHTED_NORMAL")
    weighted.mode = "FACE_AREA_WITH_ANGLE"
    weighted.keep_sharp = True
    weighted.weight = 35
    bpy.ops.object.modifier_apply(modifier=weighted.name)


def skirt_color(model):
    mesh = model.data
    mat = mesh.materials[0]
    shader = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    image = albedo_image(shader)
    if image is None or mesh.uv_layers.active is None:
        raise ValueError("Skirt palette needs textured UVs")
    coordinates = np.array([v.co[:] for v in mesh.vertices])
    low, high = coordinates[:, 2].min(), coordinates[:, 2].max()
    uv = mesh.uv_layers.active.uv
    mesh.calc_loop_triangles()
    samples, weights = [], []
    tile = pixels(image)
    image_h, image_w = tile.shape[:2]
    for face in mesh.loop_triangles:
        if face.normal.z < -.65 or face.material_index != 0:
            continue
        center_y = coordinates[list(face.vertices), 2].mean()
        if not low + (high-low)*.025 <= center_y <= low + (high-low)*.33:
            continue
        u, v = sum((uv[i].vector for i in face.loops), Vector((0, 0))) / 3
        samples.append(tile[int(v*image_h) % image_h, int(u*image_w) % image_w, :3])
        weights.append(face.area)
    rgb = np.asarray(samples)
    if len(rgb) < 15:
        raise ValueError("Insufficient low rock skirt samples")
    luminance = rgb @ np.array((.2126, .7152, .0722))
    ordered = np.argsort(luminance)
    areas = np.asarray(weights)[ordered]
    core = (areas.cumsum() > areas.sum()*.16) & (areas.cumsum() < areas.sum()*.88)
    color = np.average(rgb[ordered][core], axis=0, weights=areas[core])
    return [round(float(c), 4) for c in color]


def normalize(model, footprint):
    points = [vertex.co for vertex in model.data.vertices]
    low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    width = max(high.x - low.x, high.y - low.y)
    if width < 1e-6 or high.z - low.z < 1e-6:
        raise ValueError("Degenerate hero mesh bounds")
    # Blender XY is horizontal; the exporter rotates Blender Z into Godot Y.
    recenter = Matrix.Translation(Vector((-(low.x+high.x)/2, -(low.y+high.y)/2, -low.z)))
    transform = Matrix.Translation(Vector((0, 0, -EMBED))) @ Matrix.Scale(footprint/width, 4) @ recenter
    model.data.transform(transform)
    model.data.update()


def verify(path, footprint, expected, source_maps):
    doc = glb_json(path)
    accessors = doc["accessors"]
    primitives = [p for mesh in doc["meshes"] for p in mesh["primitives"]]
    if any(p.get("mode", 4) != 4 for p in primitives):
        raise ValueError("Output contains non-triangle primitives")
    count = sum(accessors[p.get("indices", p["attributes"]["POSITION"])]["count"] // 3
                for p in primitives)
    if count != expected or count <= 0:
        raise ValueError(f"Export triangle count drifted: {count}")
    if any(not {"NORMAL", "TANGENT", "TEXCOORD_0"} <= p["attributes"].keys() for p in primitives):
        raise ValueError("Missing explicit shading normals, tangent basis or UVs")
    positions = [accessors[p["attributes"]["POSITION"]] for p in primitives]
    low = [min(pos["min"][i] for pos in positions) for i in range(3)]
    high = [max(pos["max"][i] for pos in positions) for i in range(3)]
    if (abs(low[1] + EMBED) > 1e-5 or any(abs(low[i]+high[i]) > 1e-5 for i in (0, 2))
            or abs(max(high[i]-low[i] for i in (0, 2)) - footprint) > 1e-5):
        raise ValueError(f"Incorrect Y-up asset bounds: {low} .. {high}")
    output_maps = map_counts(doc)
    if any(required and not present for required, present in zip((source_maps[0], source_maps[0]), output_maps, strict=True)):
        raise ValueError("An original albedo or tangent-space normal map was lost")
    for mat in doc.get("materials", []):
        pbr = mat.get("pbrMetallicRoughness", {})
        if (not 0.73999 <= pbr.get("roughnessFactor", 1) <= 0.88001
                or abs(pbr.get("metallicFactor", 1)) > 1e-6):
            raise ValueError(f"Material outside the matte range: {mat.get('name', 'unnamed')}")
    return count, output_maps


def polish(source, target, spec):
    footprint, roughness, strength = spec
    source_maps = map_counts(glb_json(source))
    model = join_imported(source, target.stem)
    before = triangles(model.data)
    rebuild_normals(model)
    if not before:
        raise ValueError("No faces after removing loose geometry")
    if not model.data.materials:
        model.data.materials.append(bpy.data.materials.new("Matte stone"))
    for material in model.data.materials:
        if material is not None:
            park_material(material, roughness, strength)
    after = triangles(model.data)
    if abs(after - before) > max(8, before * 0.005):
        raise ValueError(f"Cleanup lost too much geometry: {before} -> {after}")
    normalize(model, footprint)
    soil = skirt_color(model) if target.stem != "hero_rikarisu_town" else []
    pending = target.with_name(f".{target.stem}.staging.glb")
    try:
        bpy.ops.export_scene.gltf(filepath=str(pending), export_format="GLB", export_yup=True,
                                  use_selection=True, export_animations=False,
                                  export_tangents=True)
        count, maps = verify(pending, footprint, after, source_maps)
        pending.replace(target)
    finally:
        pending.unlink(missing_ok=True)
    print(f"{target.name}: {before:,} -> {count:,} triangles, {footprint:.2f} footprint, "
          f"albedo materials {maps[0]}, normal materials {maps[1]}, {target.stat().st_size:,} bytes", flush=True)
    return {"triangles": count, "skirt_rgb": soil, "footprint": footprint, "roughness": roughness, "normal_scale": strength}


def render_sheet(models, output):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    for i, (name, _spec) in enumerate(SPECS.items()):
        filepath = models / (name + ".glb")
        before = set(scene.objects)
        bpy.ops.import_scene.gltf(filepath=str(filepath))
        added = set(scene.objects) - before
        width = SPECS[name][0]
        from mathutils import Euler
        placement = Matrix.Translation(Vector(((i-1)*1.87, 0.08*(i%2), .026)))
        placement @= Euler((0, 0, math.radians((-21, -14, 11)[i]))).to_matrix().to_4x4()
        placement @= Matrix.Scale(1.40/width, 4)
        for obj in added:
            if obj.parent not in added:
                obj.matrix_world = placement @ obj.matrix_world
    def material(name, color):
        m = bpy.data.materials.new(name)
        m.diffuse_color = color
        return m
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.065))
    bpy.context.object.data.materials.append(material("Warm limestone backdrop", (.31, .26, .22, 1)))
    def aim(obj, point):
        obj.rotation_euler = (Vector(point)-obj.location).to_track_quat("-Z","Y").to_euler()
    for name, coord, energy, span, color in [
        ("Warm broad key", (-3.5, -4.2, 6.0), 570, 4.0, (1,.88,.74)),
        ("Cool fill", (3.1, -1, 4.5), 290, 3.4, (.78,.88,1)),
        ("Soft rim", (.3, 4.2, 5), 370, 4.0, (1,.91,.80)),
    ]:
        data = bpy.data.lights.new(name, "AREA")
        data.energy, data.size, data.color = energy, span, color
        ob = bpy.data.objects.new(name, data)
        scene.collection.objects.link(ob)
        ob.location = coord
        aim(ob, (0, 0, .2))
    if scene.world is None:
        scene.world = bpy.data.worlds.new("Studio skylight")
    if scene.world.node_tree is None:
        scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = .28
    camera = bpy.data.objects.new("Studio camera", bpy.data.cameras.new("Studio camera"))
    scene.collection.objects.link(camera)
    camera.location = (.05, -6.6, 4.6)
    aim(camera, (0, 0, .28))
    camera.data.type, camera.data.ortho_scale = "ORTHO", 6.1
    scene.camera = camera
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 2100, 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    output.parent.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--input", type=Path, default=WORLD / "raw_heroes")
    cli.add_argument("--output", type=Path, default=WORLD / "heroes")
    cli.add_argument("--palette", type=Path, default=WORLD.parents[1] / "textures/world_v2/hero_ground_palette.json")
    cli.add_argument("--preview", type=Path, default=Path(__file__).resolve().parent / "previews/heroes_polished_sheet.png")
    args = cli.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    args.output.mkdir(parents=True, exist_ok=True)
    failures = []
    results = {}
    for name, spec in SPECS.items():
        source = args.input / f"{name}_raw.glb"
        if not source.is_file():
            print(f"{name}: raw GLB pending, Godot will use its available assets", flush=True)
            continue
        try:
            results[name] = polish(source, args.output / f"{name}.glb", spec)
        except Exception as error:
            print(f"{name}: {error}", file=sys.stderr, flush=True)
            failures.append(name)
    if failures:
        raise RuntimeError("Polish failed for: " + ", ".join(failures))
    if len(results) == len(SPECS):
        args.palette.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
        render_sheet(args.output, args.preview)


if __name__ == "__main__":
    main()
