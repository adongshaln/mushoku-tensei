"""Build the Migurd d20 using Blender's bundled Python and NumPy.

Run: blender --background --factory-startup --python-exit-code 1 --python tools/build_d20_blender.py
Set D20_FONT to a serif TTF/OTF path to override the local studio font.
"""

from collections import Counter, defaultdict
from dataclasses import dataclass
import json
from math import atan2, sqrt
import os
from pathlib import Path
import struct

import bpy
from mathutils import Matrix, Vector
import numpy as np


ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "assets" / "3d"
PREVIEW_PATH = ROOT / "tools" / "d20_preview.png"
ATLAS_SIZE = 2048
CELL_WIDTH = 400
CELL_HEIGHT = 480
TILE_TRIANGLE_WIDTH = 336.0
BEVEL_RADIUS = 0.092
EDGE_STEPS = 8
CAP_ROWS = 4
PLATE_SCALE = 0.827
GOLD = 0
CERAMIC = 1
Z = Vector((0, 0, 1))


@dataclass
class Face:
    indices: tuple
    center: Vector
    normal: Vector
    up: Vector
    right: Vector
    border: tuple
    uv_scale: float
    number: int = 0

    def uv(self, point):
        x0, y0 = tile_origin(self.number)
        relative = point - self.center
        return ((x0 + CELL_WIDTH / 2 + relative.dot(self.right) * self.uv_scale) / ATLAS_SIZE,
                (y0 + tile_center_y() + relative.dot(self.up) * self.uv_scale) / ATLAS_SIZE)


def d20_faces():
    phi = (1.0 + sqrt(5.0)) * 0.5
    points = [Vector(p).normalized() for p in (
        (-1, phi, 0), (1, phi, 0), (-1, -phi, 0), (1, -phi, 0),
        (0, -1, phi), (0, 1, phi), (0, -1, -phi), (0, 1, -phi),
        (phi, 0, -1), (phi, 0, 1), (-phi, 0, -1), (-phi, 0, 1))]
    triangles = [
        (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11),
        (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
        (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9),
        (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    faces = []
    for indices in triangles:
        a, b, c = (points[i] for i in indices)
        normal = (b - a).cross(c - a).normalized()
        assert normal.dot(a) > 0
        border = tuple(points[i] * (1 - BEVEL_RADIUS) + normal * BEVEL_RADIUS for i in indices)
        center = sum(border, Vector()) / 3
        top = max(border, key=lambda corner: corner.dot(Z))
        up = (top - center).normalized()
        right = up.cross(normal).normalized()
        width = (border[1] - border[0]).length * PLATE_SCALE
        faces.append(Face(indices, center, normal, up, right, border, TILE_TRIANGLE_WIDTH / width))

    available = set(range(20))
    for number in range(1, 11):
        front = min(available)
        available.remove(front)
        back = min(available, key=lambda i: faces[front].normal.dot(faces[i].normal))
        available.remove(back)
        assert faces[front].normal.dot(faces[back].normal) < -0.99999
        faces[front].number = number
        faces[back].number = 21 - number
    return points, faces


class Geometry:
    def __init__(self):
        self.vertices = []
        self.lookup = {}
        self.polygons = []
        self.materials = []
        self.normals = []
        self.uvs = []

    def add(self, points, outward, material, normals=None, ceramic_face=None):
        normal = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
        assert normal.length > 0.9999
        if normal.dot(outward) < 0:
            points = tuple(reversed(points))
            normal = -normal
            if normals is not None:
                normals = tuple(reversed(normals))
        indices = []
        for point in points:
            key = tuple(round(component, 6) for component in point)
            if key not in self.lookup:
                self.lookup[key] = len(self.vertices)
                self.vertices.append(point)
            indices.append(self.lookup[key])
        self.polygons.append(indices)
        self.materials.append(material)
        self.normals.extend(normals if normals is not None else [normal] * len(points))
        self.uvs.extend([ceramic_face.uv(point) for point in points] if ceramic_face
                        else [(0.0, 0.0)] * len(points))

    def build_mesh(self):
        edges = Counter()
        directions = Counter()
        for polygon in self.polygons:
            for a, b in zip(polygon, polygon[1:] + polygon[:1]):
                assert a != b
                edges[tuple(sorted((a, b)))] += 1
                directions[a, b] += 1
        assert all(count == 2 for count in edges.values()), "Unsealed bevel or face"
        assert all(count == 1 and directions[b, a] == 1 for (a, b), count in directions.items()), "Inconsistent winding"
        assert abs(max(point.length for point in self.vertices) - 1.0) < 1e-6
        for axis in range(3):
            extent = [point[axis] for point in self.vertices]
            assert abs(max(extent) + min(extent)) < 1e-6
        mesh = bpy.data.meshes.new("Rounded icosahedron")
        mesh.from_pydata(self.vertices, [], self.polygons)
        mesh.update()
        assert not mesh.validate(clean_customdata=False), "Invalid geometry"
        mesh.uv_layers.new(name="Ceramic atlas").uv.foreach_set("vector", np.asarray(self.uvs, dtype=np.float32).ravel())
        for polygon in mesh.polygons:
            polygon.use_smooth = True
        mesh.normals_split_custom_set(self.normals)
        mesh.calc_loop_triangles()
        assert 2000 <= len(mesh.loop_triangles) <= 6500
        return mesh


def make_geometry(vertices, faces):
    geo = Geometry()
    neighbors = defaultdict(list)
    for i, face in enumerate(faces):
        for a, b in zip(face.indices, (*face.indices[1:], face.indices[0])):
            neighbors[tuple(sorted((a, b)))].append(i)

        rings = [face.border]
        # A raised metal lip slopes down into the ceramic well.
        for scale, depth in ((0.967, 0.0), (0.929, 0.004), (0.890, 0.018),
                             (0.855, 0.031), (PLATE_SCALE, 0.035)):
            rings.append(tuple(face.center + (point - face.center) * scale - face.normal * depth
                               for point in face.border))
        for layer, (outer, inner) in enumerate(zip(rings, rings[1:])):
            glazed = layer == len(rings) - 2
            for a in range(3):
                b = (a + 1) % 3
                geo.add((outer[a], outer[b], inner[b], inner[a]), face.normal,
                        CERAMIC if glazed else GOLD, ceramic_face=face if glazed else None)
        geo.add(rings[-1], face.normal, CERAMIC, ceramic_face=face)

    arcs = {}
    for (a, b), adjacent in neighbors.items():
        i, j = adjacent
        first, last = faces[i].normal, faces[j].normal
        arc = [first, *(first.slerp(last, step / EDGE_STEPS) for step in range(1, EDGE_STEPS)), last]
        arcs[i, j] = arc
        arcs[j, i] = arc[::-1]
        p, q = vertices[a] * (1 - BEVEL_RADIUS), vertices[b] * (1 - BEVEL_RADIUS)
        for n0, n1 in zip(arc, arc[1:]):
            geo.add((p + n0 * BEVEL_RADIUS, q + n0 * BEVEL_RADIUS,
                     q + n1 * BEVEL_RADIUS, p + n1 * BEVEL_RADIUS),
                    n0 + n1, GOLD, (n0, n0, n1, n1))
    assert len(arcs) == 60

    for i, point in enumerate(vertices):
        incident = [j for j, face in enumerate(faces) if i in face.indices]
        assert len(incident) == 5
        first = faces[incident[0]].normal
        x = (first - point * first.dot(point)).normalized()
        y = point.cross(x)
        incident.sort(key=lambda index: atan2(faces[index].normal.dot(y), faces[index].normal.dot(x)))
        rim = []
        for a, b in zip(incident, (*incident[1:], incident[0])):
            rim.extend(arcs[a, b][:-1])
        center = point * (1 - BEVEL_RADIUS)
        normals = [[point.slerp(normal, row / CAP_ROWS) for normal in rim]
                   for row in range(1, CAP_ROWS)]
        normals.append(rim)
        for k in range(len(rim)):
            j = (k + 1) % len(rim)
            inner = normals[0]
            geo.add((point, center + inner[k] * BEVEL_RADIUS, center + inner[j] * BEVEL_RADIUS),
                    point, GOLD, (point, inner[k], inner[j]))
            for inner, outer in zip(normals, normals[1:]):
                quad = (inner[k], outer[k], outer[j], inner[j])
                geo.add(tuple(center + n * BEVEL_RADIUS for n in quad), point, GOLD, quad)

    mesh = geo.build_mesh()
    return geo, mesh


def tile_origin(number):
    index = number - 1
    return 24 + (index % 5) * CELL_WIDTH, 64 + (index // 5) * CELL_HEIGHT


def tile_center_y():
    return 88.0 + TILE_TRIANGLE_WIDTH * sqrt(3.0) / 6.0


def studio_font():
    candidates = (os.environ.get("D20_FONT"), "/System/Library/Fonts/Supplemental/Georgia Bold.ttf",
                  "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf", "C:/Windows/Fonts/georgiab.ttf")
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return bpy.data.fonts.load(str(candidate))
    raise FileNotFoundError("Set D20_FONT to a serif TTF or OTF font.")


def glyph_mask(number, font):
    curve = bpy.data.curves.new("Glyph outline", "FONT")
    curve.body = str(number)
    curve.font = font
    curve.resolution_u = 16
    text = bpy.data.objects.new("Glyph raster source", curve)
    bpy.context.scene.collection.objects.link(text)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    evaluated = text.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    mesh.calc_loop_triangles()
    vertices = np.array([vertex.co[:2] for vertex in mesh.vertices])
    low, high = vertices.min(axis=0), vertices.max(axis=0)
    scale = min(157 / (high[0] - low[0]), 91 / (high[1] - low[1]))
    centroid = np.array((CELL_WIDTH / 2, tile_center_y() + 7.0))
    supersample = 3
    vertices = ((vertices - (low + high) * 0.5) * scale + centroid) * supersample
    mask = np.zeros((CELL_HEIGHT * supersample, CELL_WIDTH * supersample), dtype=bool)
    for triangle in mesh.loop_triangles:
        a, b, c = vertices[triangle.vertices[:], :]
        start = np.floor(np.minimum(np.minimum(a, b), c)).astype(int)
        end = np.ceil(np.maximum(np.maximum(a, b), c)).astype(int)
        x = np.arange(start[0], end[0], dtype=float)[None, :] + 0.5
        y = np.arange(start[1], end[1], dtype=float)[:, None] + 0.5
        ab = (b[0] - a[0]) * (y - a[1]) - (b[1] - a[1]) * (x - a[0])
        bc = (c[0] - b[0]) * (y - b[1]) - (c[1] - b[1]) * (x - b[0])
        ca = (a[0] - c[0]) * (y - c[1]) - (a[1] - c[1]) * (x - c[0])
        mask[start[1]:end[1], start[0]:end[0]] |= (
            ((ab >= 0) & (bc >= 0) & (ca >= 0)) | ((ab <= 0) & (bc <= 0) & (ca <= 0)))
    evaluated.to_mesh_clear()
    bpy.data.objects.remove(text, do_unlink=True)
    bpy.data.curves.remove(curve)
    return mask.reshape(CELL_HEIGHT, supersample, CELL_WIDTH, supersample).mean(axis=(1, 3))


def rgb(hex_color):
    return np.array(tuple(bytes.fromhex(hex_color)), dtype=np.float32) / 255


def srgb_to_linear(color):
    return tuple(float(value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4)
                 for value in rgb(color))


def dilate(mask, radius):
    return np.maximum.reduce([np.roll(mask, shift=(y, x), axis=(0, 1))
                              for y in range(-radius, radius + 1)
                              for x in range(-radius, radius + 1) if x*x + y*y <= radius*radius])


def pigment_noise(rng, height, width, step):
    grid = rng.random((height // step + 2, width // step + 2)).astype(np.float32)
    x, y = np.arange(width) / step, np.arange(height) / step
    ix, iy = x.astype(int), y.astype(int)
    fx, fy = x - ix, y - iy
    fx, fy = fx * fx * (3 - 2 * fx), (fy * fy * (3 - 2 * fy))[:, None]
    return ((grid[iy[:, None], ix] * (1 - fx) + grid[iy[:, None], ix + 1] * fx) * (1 - fy)
            + (grid[iy[:, None] + 1, ix] * (1 - fx) + grid[iy[:, None] + 1, ix + 1] * fx) * fy)


def packed_image(name, pixels, color_space):
    image = bpy.data.images.new(name, width=ATLAS_SIZE, height=ATLAS_SIZE, alpha=False)
    image.colorspace_settings.name = color_space
    image.pixels.foreach_set(np.clip(pixels, 0, 1).ravel())
    image.update()
    image.pack()
    return image


def build_atlas(font):
    atlas = [np.ones((ATLAS_SIZE, ATLAS_SIZE, 4), np.float32) for _ in range(3)]
    x = (np.arange(CELL_WIDTH, dtype=np.float32) + 0.5)[None, :] - CELL_WIDTH / 2
    y = (np.arange(CELL_HEIGHT, dtype=np.float32) + 0.5)[:, None] - tile_center_y()
    radius = TILE_TRIANGLE_WIDTH * sqrt(3.0) / 6
    distance = np.minimum(y + radius, radius - y * 0.5 - abs(x) * sqrt(3.0) / 2)
    edge = np.clip(distance / 75, 0, 1)
    trim = np.clip(1.55 - abs(distance - 13.0), 0, 1) * 0.92
    shadow_trim = np.clip(1.25 - abs(distance - 16.4), 0, 1) * 0.49

    for number in range(1, 21):
        rng = np.random.default_rng(418 + number)
        wash = pigment_noise(rng, CELL_HEIGHT, CELL_WIDTH, 55)
        flecks = pigment_noise(rng, CELL_HEIGHT, CELL_WIDTH, 7)
        grain = rng.random((CELL_HEIGHT, CELL_WIDTH)) - 0.5
        glaze = np.clip(0.17 + edge * 0.57 + (wash - 0.5) * 0.29 + (flecks - 0.5) * 0.07 + grain * 0.028, 0, 1)
        color = rgb("3B678C") + glaze[:, :, None] * (rgb("689BBA") - rgb("3B678C"))
        color += (rgb("233E52") - color) * shadow_trim[:, :, None]
        color += (rgb("F2E6CE") - color) * trim[:, :, None]

        glyph = glyph_mask(number, font)
        symbol = np.zeros_like(glyph)
        if number in (6, 9):
            symbol = np.clip(3.6 - np.hypot(np.maximum(abs(x) - 19, 0), y + 53), 0, 1)
        if number == 20:
            star = (abs(x) / 15.0) ** 0.64 + (abs(y - 79.0) / 15.0) ** 0.64
            symbol = np.clip((1.09 - star) * 8.0, 0, 1)
        fill = np.maximum(glyph, symbol)
        contour = dilate(fill, 3)
        color += (rgb("3F2C24") - color) * contour[:, :, None]
        ivory = rgb("F2E6CE") + np.clip((y + 45) / 115, 0, 1)[:, :, None] * (rgb("FFF1D1") - rgb("F2E6CE"))
        color += (ivory - color) * glyph[:, :, None]
        color += (rgb("CFA052") - color) * symbol[:, :, None]

        height = wash * 0.052 + flecks * 0.025 + grain * 0.010 - contour * 0.23 + fill * 0.078
        dy, dx = np.gradient(height)
        normal = np.stack((-dx, -dy, np.ones_like(dx)), axis=-1)
        normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
        orm = np.stack((np.ones_like(fill), 0.38 + 0.030*(wash - 0.5) - 0.055*fill,
                        0.04 + 0.19*glyph + 0.70*symbol), axis=-1)
        x0, y0 = tile_origin(number)
        for target, values in zip(atlas, (color, normal * 0.5 + 0.5, orm)):
            target[y0:y0 + CELL_HEIGHT, x0:x0 + CELL_WIDTH, :3] = values

    return (packed_image("D20 Glaze Albedo", atlas[0], "sRGB"),
            packed_image("D20 Engraving Normal", atlas[1], "Non-Color"),
            packed_image("D20 Metallic Roughness", atlas[2], "Non-Color"))


def pbr(name, color, metal, roughness):
    material = bpy.data.materials.new(name)
    if material.node_tree is None:
        material.use_nodes = True
    shader = next(node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = (*srgb_to_linear(color), 1.0)
    shader.inputs["Metallic"].default_value = metal
    shader.inputs["Roughness"].default_value = roughness
    return material, shader


def make_materials(font):
    gold, _ = pbr("Antique gilt", "CFA052", 0.85, 0.30)
    ceramic, shader = pbr("Sea-mist glazed ceramic", "4A7BA0", 0.04, 0.38)
    for names, value in ((("Coat Weight", "Clearcoat"), 0.16), (("Coat Roughness", "Clearcoat Roughness"), 0.24)):
        for name in names:
            if name in shader.inputs:
                shader.inputs[name].default_value = value
                break
    albedo, bump, orm = build_atlas(font)
    nodes, links = ceramic.node_tree.nodes, ceramic.node_tree.links
    texture_nodes = []
    for atlas in (albedo, bump, orm):
        node = nodes.new("ShaderNodeTexImage")
        node.image = atlas
        node.extension = "EXTEND"
        texture_nodes.append(node)
    links.new(texture_nodes[0].outputs["Color"], shader.inputs["Base Color"])
    normal = nodes.new("ShaderNodeNormalMap")
    normal.inputs["Strength"].default_value = 0.85
    links.new(texture_nodes[1].outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], shader.inputs["Normal"])
    channels = nodes.new("ShaderNodeSeparateColor")
    channels.mode = "RGB"
    links.new(texture_nodes[2].outputs["Color"], channels.inputs["Color"])
    links.new(channels.outputs["Green"], shader.inputs["Roughness"])
    links.new(channels.outputs["Blue"], shader.inputs["Metallic"])
    return gold, ceramic


def gltf_vector(vector):
    return [float(vector.x), float(vector.z), float(-vector.y)]


def validate_coordinates(faces):
    table = {}
    for face in faces:
        assert abs(face.normal.length - 1.0) < 1e-6 and abs(face.up.length - 1.0) < 1e-6
        assert abs(face.normal.dot(face.up)) < 1e-5
        opposite = [other for other in faces if face.normal.dot(other.normal) < -0.99999]
        assert len(opposite) == 1 and face.number + opposite[0].number == 21

        # Derive upright from the UV Jacobian, including glTF's V flip.
        a, b, c = face.border
        uv = np.asarray([face.uv(point) for point in (a, b, c)])
        edges = np.asarray([gltf_vector(b - a), gltf_vector(c - a)]).T
        uv[:, 1] = 1 - uv[:, 1]
        uv_edges = (uv[1:] - uv[0]).T
        world_up = edges @ np.linalg.solve(uv_edges, [0, -1])
        world_up /= np.linalg.norm(world_up)
        assert np.linalg.norm(world_up - gltf_vector(face.up)) < 1e-6
        table[str(face.number)] = {"normal": gltf_vector(face.normal), "up": gltf_vector(face.up)}
    return {str(number): table[str(number)] for number in range(1, 21)}


def inspect_glb(file, expected_triangles):
    with file.open("rb") as stream:
        tag, version, size = struct.unpack("<4sII", stream.read(12))
        assert tag == b"glTF" and version == 2 and size == file.stat().st_size
        chunk, kind = struct.unpack("<I4s", stream.read(8))
        assert kind == b"JSON"
        gltf = json.loads(stream.read(chunk))
    primitives = [primitive for mesh in gltf["meshes"] for primitive in mesh["primitives"]]
    assert len(primitives) == 2
    assert sum(gltf["accessors"][primitive["indices"]]["count"] // 3 for primitive in primitives) == expected_triangles
    assert len(gltf["images"]) == 3 and all("bufferView" in image for image in gltf["images"])
    glaze = next(material for material in gltf["materials"] if material["name"].startswith("Sea-mist"))
    assert "normalTexture" in glaze
    assert "baseColorTexture" in glaze["pbrMetallicRoughness"]
    assert "metallicRoughnessTexture" in glaze["pbrMetallicRoughness"]
    print(f"D20 export: {expected_triangles} triangles, {size} bytes, three embedded 2048² maps", flush=True)


def aimed(node, target):
    node.rotation_euler = (Vector(target) - node.location).to_track_quat("-Z", "Y").to_euler()


def preview_label(text, size, x, z, font, ink):
    curve = bpy.data.curves.new(text, "FONT")
    curve.body, curve.font, curve.size, curve.align_x = text, font, size, "CENTER"
    curve.space_character = 1.11
    label = bpy.data.objects.new(text, curve)
    bpy.context.scene.collection.objects.link(label)
    label.location = (x, 0.05, z)
    label.rotation_euler = (1.5707963267948966, 0, 0)
    curve.materials.append(ink)


def render_preview(model, faces, font):
    scene = bpy.context.scene
    studio = scene.collection
    by_number = {face.number: face for face in faces}
    frontal = Matrix((Vector((1, 0, 0)), Z, Vector((0, -1, 0)))).transposed()
    views = [(6, -3.24, 2.79, 1.06), (20, 0, 2.79, 1.23), (9, 3.24, 2.79, 1.06)]
    for n in range(1, 21):
        views.append((n, ((n - 1) % 5 - 2) * 1.82, 0.63 - ((n - 1) // 5) * 1.18, 0.50))
    for number, x, z, scale in views:
        face = by_number[number]
        local = Matrix((face.right, face.up, face.normal)).transposed()
        die = bpy.data.objects.new(f"Preview {number}", model.data)
        studio.objects.link(die)
        die.location = (x, 0, z)
        die.scale = (scale,) * 3
        die.rotation_euler = (frontal @ local.transposed()).to_euler()
    bpy.data.objects.remove(model, do_unlink=True)

    paper, shader = pbr("Warm studio backdrop", "C5AD8D", 0.0, 0.85)
    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 1.35, 0), rotation=(1.5707963267948966, 0, 0))
    bpy.context.object.data.materials.append(paper)
    nodes, links = paper.node_tree.nodes, paper.node_tree.links
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 160.0
    noise.inputs["Roughness"].default_value = 0.75
    noise.inputs["Detail"].default_value = 2
    ramp = nodes.new("ShaderNodeValToRGB")
    for element, color in zip(ramp.color_ramp.elements, ("C0A584", "DEC6A1")):
        element.color = (*srgb_to_linear(color), 1.0)
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], shader.inputs["Base Color"])
    ink, _ = pbr("Warm ink", "503B2C", 0.0, 0.9)
    preview_label("MIGURD  /  D20", 0.43, 0, 4.43, font, ink)
    preview_label("GLAZED CERAMIC  ·  ANTIQUE GILT", 0.155, 0, 4.14, font, ink)
    preview_label("THE TWENTY FACES", 0.18, 0, 1.30, font, ink)

    camera_data = bpy.data.cameras.new("Studio camera")
    camera = bpy.data.objects.new("Studio camera", camera_data)
    studio.objects.link(camera)
    camera.location = (0, -15, 0.38)
    aimed(camera, (0, 0, 0.38))
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 11.2
    scene.camera = camera
    for name, position, energy, color, size in (
        ("Warm key", (-4.0, -5.6, 6.4), 1450, (1.0, 0.83, 0.65), 5.8),
        ("Sea fill", (6, -4.6, 2.4), 800, (0.63, 0.80, 1.0), 5.0),
        ("Lower bounce", (0, -6.0, -5.3), 500, (1.0, 0.88, 0.69), 7.5),
    ):
        light = bpy.data.lights.new(name, "AREA")
        light.energy, light.color, light.shape, light.size = energy, color, "DISK", size
        lamp = bpy.data.objects.new(name, light)
        studio.objects.link(lamp)
        lamp.location = position
        aimed(lamp, (0, 0, 0.4))
    if scene.world is None:
        scene.world = bpy.data.worlds.new("Studio ambient")
    if scene.world.node_tree is None:
        scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.32, 0.37, 0.46, 1.0)
    background.inputs["Strength"].default_value = 0.43
    scene.view_settings.view_transform = "AgX"
    scene.render.resolution_x, scene.render.resolution_y = 1680, 1460
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.filepath = str(PREVIEW_PATH)
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "CYCLES"):
        try:
            scene.render.engine = engine
        except (TypeError, ValueError):
            continue
        if engine == "CYCLES":
            scene.cycles.device = "CPU"
            scene.cycles.samples = 16
            scene.cycles.use_denoising = True
        try:
            result = bpy.ops.render.render(write_still=True)
        except RuntimeError as error:
            print(f"{engine} preview unavailable: {error}")
            continue
        if "FINISHED" in result:
            print(f"D20 preview: {engine}, {PREVIEW_PATH}", flush=True)
            return
    raise RuntimeError("No available render engine completed the d20 preview")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    vertices, faces = d20_faces()
    table = validate_coordinates(faces)
    geo, mesh = make_geometry(vertices, faces)
    font = studio_font()
    for material in make_materials(font):
        mesh.materials.append(material)
    for polygon, material in zip(mesh.polygons, geo.materials):
        polygon.material_index = material
    die = bpy.data.objects.new("Migurd D20", mesh)
    bpy.context.scene.collection.objects.link(die)
    die.select_set(True)
    bpy.context.view_layer.objects.active = die
    target = ASSET_DIR / "d20_skin.glb"
    result = bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB", use_selection=True,
                                       export_yup=True, export_tangents=True, export_animations=False)
    assert "FINISHED" in result
    inspect_glb(target, len(mesh.loop_triangles))
    (ASSET_DIR / "d20_faces.json").write_text(json.dumps(table, indent=2) + "\n", encoding="utf-8")
    render_preview(die, faces, font)


if __name__ == "__main__":
    main()
