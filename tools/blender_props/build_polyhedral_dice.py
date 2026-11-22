"""Build D4 through D12 using the existing D20 studio palette and engraving process.

Run: blender --background --python tools/blender_props/build_polyhedral_dice.py
Only the new dice directory and two named previews are written.
"""

from collections import Counter, defaultdict
from dataclasses import dataclass, field
from itertools import combinations, product
import json
import math
from pathlib import Path
import struct
import sys

import bpy
from mathutils import Matrix, Vector
import numpy as np


ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets/3d"
DICE = ASSETS / "dice"
PREVIEWS = Path(__file__).resolve().parent / "previews"
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / "tools"))
import build_d20_blender as d20

Z = Vector((0, 0, 1))
CELL = 504
MARGIN = 16
FACE_KINDS = {"d4": (4, 3), "d6": (6, 4), "d8": (8, 3), "d10": (10, 4), "d12": (12, 5)}


@dataclass
class Face:
    indices: tuple
    normal: Vector
    up: Vector
    right: Vector
    center: Vector
    border: tuple
    scale: float
    offset: np.ndarray
    number: int = 0
    readings: dict = field(default_factory=dict)

    @property
    def plate(self):
        return tuple(self.center + (point - self.center) * d20.PLATE_SCALE - self.normal * 0.035
                     for point in self.border)

    @property
    def tile(self):
        index = self.number - 1
        return MARGIN + (index % 4) * CELL, MARGIN + (index // 4) * CELL

    def pixels(self, point):
        relative = point - self.center
        return self.offset + self.scale * np.array((relative.dot(self.right), relative.dot(self.up)))

    def uv(self, point):
        return tuple((self.pixels(point) + self.tile) / d20.ATLAS_SIZE)


@dataclass
class Die:
    key: str
    vertices: list
    faces: list
    mesh: object = None

    def face(self, number):
        return next(face for face in self.faces if face.number == number)


def base_vertices(key):
    if key == "d4":
        return [Vector(p).normalized() for p in ((1, 1, 1), (-1, -1, 1), (-1, 1, -1), (1, -1, -1))]
    if key == "d6":
        return [Vector(p).normalized() for p in product((-1, 1), repeat=3)]
    if key == "d8":
        return [Vector(tuple(sign if axis == i else 0 for i in range(3)))
                for axis in range(3) for sign in (-1, 1)]
    if key == "d10":
        # Alternating crown heights make the pole, two shoulders, and short
        # tip of every kite coplanar. The pole-to-pole size is two units.
        step = math.pi / 5
        height = (1.0 - math.cos(step)) / (1.0 + math.cos(step))
        return [Z, -Z] + [Vector((0.80 * math.cos(i * step), 0.80 * math.sin(i * step),
                                    height * (-1 if i % 2 == 0 else 1))) for i in range(10)]
    phi = (1 + math.sqrt(5)) / 2
    points = list(product((-1, 1), repeat=3))
    for a, b in product((-1, 1), repeat=2):
        points.extend(((0, a / phi, b * phi), (a / phi, b * phi, 0), (a * phi, 0, b / phi)))
    return [Vector(point).normalized() for point in points]


def support_faces(points):
    planes = {}
    for i, j, k in combinations(range(len(points)), 3):
        normal = (points[j] - points[i]).cross(points[k] - points[i])
        if normal.length < 1e-7:
            continue
        normal.normalize()
        distances = [(point - points[i]).dot(normal) for point in points]
        if min(distances) < -1e-6 and max(distances) > 1e-6:
            continue
        if normal.dot(points[i]) < 0:
            normal = -normal
        group = tuple(index for index, distance in enumerate(distances) if abs(distance) <= 1e-6)
        if group not in planes:
            planes[group] = normal
    return planes


def shape(key):
    vertices = base_vertices(key)
    faces = []
    planes = support_faces(vertices)
    count, corners = FACE_KINDS[key]
    assert len(planes) == count and all(len(group) == corners for group in planes), key
    for group, normal in planes.items():
        center = sum((vertices[i] for i in group), Vector()) / len(group)
        x_axis = (vertices[group[0]] - center).normalized()
        y_axis = normal.cross(x_axis)
        indices = tuple(sorted(group, key=lambda i: math.atan2(
            (vertices[i] - center).dot(y_axis), (vertices[i] - center).dot(x_axis))))
        border = tuple(vertices[i] * (1 - d20.BEVEL_RADIUS) + normal * d20.BEVEL_RADIUS for i in indices)
        center = sum(border, Vector()) / len(border)
        reference = Z if abs(normal.dot(Z)) < .95 else Vector((0, 1, 0))
        if key == "d6":
            candidates = [((a + b) * .5 - center).normalized()
                          for a, b in zip(border, border[1:] + border[:1])]
            up = max(candidates, key=lambda vector: vector.dot(reference))
        elif key == "d10":
            pole = 0 if normal.z > 0 else 1
            up = (border[indices.index(pole)] - center).normalized()
            edges = [(vertices[a] - vertices[b]).length for a, b in zip(indices, indices[1:] + indices[:1])]
            long = max(edges)
            assert sum(abs(edge - long) < 1e-6 for edge in edges) == 2 and max(edges) - min(edges) > .05
            assert abs((vertices[indices[2]] - vertices[indices[0]]).dot(
                vertices[indices[3]] - vertices[indices[1]])) < 1e-6, "D10 kite diagonals"
        else:
            top = max(border, key=lambda point: point.dot(reference))
            up = (top - center).normalized()
        up = (up - normal * normal.dot(up)).normalized()
        right = up.cross(normal)
        local = np.asarray([((point - center).dot(right), (point - center).dot(up))
                            for point in border]) * d20.PLATE_SCALE
        low, high = local.min(axis=0), local.max(axis=0)
        scale = 350.0 / max(high - low)
        faces.append(Face(indices, normal, up, right, center, border, scale, CELL / 2 - (low + high) * scale * .5))
    if key == "d4":
        for face in faces:
            face.number = next(i + 1 for i in range(4) if i not in face.indices)
            for i in face.indices:
                tangent = vertices[i] - face.normal * face.normal.dot(vertices[i])
                face.readings[i + 1] = tangent.normalized()
    elif key == "d10":
        upper = sorted((face for face in faces if face.normal.z > 0),
                       key=lambda face: math.atan2(face.normal.y, face.normal.x))
        for number, face in zip(range(1, 10, 2), upper, strict=True):
            pair(face, number, 11, faces)
    else:
        available = sorted(faces, key=lambda face: tuple(round(value, 5) for value in face.normal))
        for number in range(1, count // 2 + 1):
            front = available.pop(0)
            back = pair(front, number, count + 1, available)
            available.remove(back)
    return Die(key, vertices, sorted(faces, key=lambda face: face.number))


def pair(face, number, expected_sum, candidates):
    opposite = [other for other in candidates if face.normal.dot(other.normal) < -.99999]
    assert len(opposite) == 1
    face.number = number
    opposite[0].number = expected_sum - number
    return opposite[0]


def make_geometry(die):
    geo = d20.Geometry()
    neighbors = defaultdict(list)
    bevel = d20.BEVEL_RADIUS
    for i, face in enumerate(die.faces):
        edges = tuple(zip(face.indices, face.indices[1:] + face.indices[:1]))
        for a, b in edges:
            neighbors[tuple(sorted((a, b)))].append(i)
        rings = [face.border]
        for scale, depth in ((.967, 0), (.929, .004), (.890, .018), (.855, .031), (d20.PLATE_SCALE, .035)):
            rings.append(tuple(face.center + (p - face.center) * scale - face.normal * depth for p in face.border))
        for layer, (outer, inner) in enumerate(zip(rings, rings[1:])):
            ceramic = layer == len(rings) - 2
            for a in range(len(outer)):
                b = (a + 1) % len(outer)
                geo.add((outer[a], outer[b], inner[b], inner[a]), face.normal, d20.CERAMIC if ceramic else d20.GOLD,
                        ceramic_face=face if ceramic else None)
        plate = rings[-1]
        for i in range(1, len(plate) - 1):
            geo.add((plate[0], plate[i], plate[i + 1]), face.normal, d20.CERAMIC, ceramic_face=face)
    arcs = {}
    for (a, b), adjacent in neighbors.items():
        i, j = adjacent
        first, last = die.faces[i].normal, die.faces[j].normal
        steps = d20.EDGE_STEPS
        arc = [first, *(first.slerp(last, step / steps) for step in range(1, steps)), last]
        arcs[i, j], arcs[j, i] = arc, arc[::-1]
        p, q = die.vertices[a] * (1 - bevel), die.vertices[b] * (1 - bevel)
        for n0, n1 in zip(arc, arc[1:]):
            geo.add((p + n0 * bevel, q + n0 * bevel, q + n1 * bevel, p + n1 * bevel),
                    n0 + n1, d20.GOLD, (n0, n0, n1, n1))

    for vertex, point in enumerate(die.vertices):
        direction = point.normalized()
        adjoining = [i for i, face in enumerate(die.faces) if vertex in face.indices]
        first = die.faces[adjoining[0]].normal
        x = (first - direction * first.dot(direction)).normalized()
        y = direction.cross(x)
        adjoining.sort(key=lambda i: math.atan2(die.faces[i].normal.dot(y), die.faces[i].normal.dot(x)))
        normals = []
        for i, j in zip(adjoining, adjoining[1:] + adjoining[:1]):
            normals.extend(arcs[i, j][:-1])
        center = point * (1 - bevel)
        cap = [[direction.slerp(normal, row / d20.CAP_ROWS) for normal in normals]
               for row in range(1, d20.CAP_ROWS)] + [normals]
        for a in range(len(normals)):
            b = (a + 1) % len(normals)
            inner = cap[0]
            geo.add((center + direction * bevel, center + inner[a] * bevel, center + inner[b] * bevel),
                    direction, d20.GOLD, (direction, inner[a], inner[b]))
            for inside, outside in zip(cap, cap[1:]):
                row = (inside[a], outside[a], outside[b], inside[b])
                geo.add(tuple(center + n * bevel for n in row), direction, d20.GOLD, row)
    return build_mesh(die, geo)


def build_mesh(die, geo):
    directed = Counter()
    for face in geo.polygons:
        for a, b in zip(face, face[1:] + face[:1]):
            assert a != b
            directed[a, b] += 1
    assert all(count == 1 and directed[b, a] == 1 for (a, b), count in directed.items()), "open/wound edge"
    assert abs(max(point.length for point in geo.vertices) - 1) < 1e-6
    mesh = bpy.data.meshes.new(die.key.upper() + " rounded shell")
    mesh.from_pydata(geo.vertices, [], geo.polygons)
    mesh.update()
    assert not mesh.validate(clean_customdata=False)
    mesh.uv_layers.new(name="Ceramic atlas").uv.foreach_set("vector", np.asarray(geo.uvs, dtype=np.float32).ravel())
    for polygon, material in zip(mesh.polygons, geo.materials, strict=True):
        polygon.material_index = material
        polygon.use_smooth = True
    mesh.normals_split_custom_set(geo.normals)
    mesh.calc_loop_triangles()
    assert 800 <= len(mesh.loop_triangles) <= 6500
    positions = np.asarray(geo.vertices, dtype=np.float64)
    lookup = np.asarray([tuple(tri.vertices) for tri in mesh.loop_triangles])
    a, b, c = np.split(positions[lookup], 3, axis=1)
    a, b, c = a[:, 0], b[:, 0], c[:, 0]
    assert np.all(np.linalg.norm(np.cross(b-a, c-a), axis=1) > 1e-9)
    volumes = np.einsum("ij,ij->i", a, np.cross(b, c))
    centroid = np.sum((a + b + c) * volumes[:, None], axis=0) / (4.0 * volumes.sum())
    assert volumes.sum() > 0 and np.linalg.norm(centroid) < 1e-6, centroid
    print(f"{die.key.upper()} centered closed shell, radius 1.000, volume centroid error {np.linalg.norm(centroid):.2g}")
    return mesh


def glyph_shapes(font):
    curve = bpy.data.curves.new("Serif engraving source", "FONT")
    curve.font = font
    curve.resolution_u = 16
    text = bpy.data.objects.new("Glyph raster source", curve)
    bpy.context.scene.collection.objects.link(text)
    result = {}
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for number in range(1, 13):
        curve.body = str(number)
        depsgraph.update()
        evaluated = text.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        vertices = np.array([tuple(vertex.co[:2]) for vertex in mesh.vertices])
        low, high = vertices.min(axis=0), vertices.max(axis=0)
        vertices = (vertices - (low + high) / 2) / (high[1] - low[1])
        triangles = np.array([tuple(tri.vertices) for tri in mesh.loop_triangles])
        result[number] = vertices, triangles, np.ptp(vertices[:, 0])
        evaluated.to_mesh_clear()
    bpy.data.objects.remove(text, do_unlink=True)
    bpy.data.curves.remove(curve)
    return result


def raster_glyph(shape, center, up, height):
    ss = 3
    points, triangles, _width = shape
    right = np.array((up[1], -up[0]))
    vertices = (center + height * (points[:, :1] * right + points[:, 1:] * up)) * ss
    low = np.floor(vertices.min(axis=0)).astype(int) - 1
    high = np.ceil(vertices.max(axis=0)).astype(int) + 1
    # Local supersampling bounds keep each raster small, including rotated D4 digits.
    low = low // ss * ss
    high = (high + ss - 1) // ss * ss
    assert np.all(low >= 0) and np.all(high <= CELL * ss)
    mask = np.zeros((high[1] - low[1], high[0] - low[0]), dtype=bool)
    vertices -= low
    for triangle in triangles:
        a, b, c = vertices[triangle]
        if abs((b[0]-a[0])*(c[1]-a[1]) - (b[1]-a[1])*(c[0]-a[0])) < 1e-8:
            continue
        start = np.floor(np.minimum(np.minimum(a, b), c)).astype(int)
        end = np.ceil(np.maximum(np.maximum(a, b), c)).astype(int)
        x = np.arange(start[0], end[0], dtype=float)[None, :] + .5
        y = np.arange(start[1], end[1], dtype=float)[:, None] + .5
        ab = (b[0] - a[0]) * (y - a[1]) - (b[1] - a[1]) * (x - a[0])
        bc = (c[0] - b[0]) * (y - b[1]) - (c[1] - b[1]) * (x - b[0])
        ca = (a[0] - c[0]) * (y - c[1]) - (a[1] - c[1]) * (x - c[0])
        mask[start[1]:end[1], start[0]:end[0]] |= (
            ((ab >= 0) & (bc >= 0) & (ca >= 0)) | ((ab <= 0) & (bc <= 0) & (ca <= 0)))
    size = (high - low) // ss
    result = np.zeros((CELL, CELL), np.float32)
    left, bottom = low // ss
    result[bottom:bottom+size[1], left:left+size[0]] = mask.reshape(size[1], ss, size[0], ss).mean(axis=(1, 3))
    return result


GRID_X = np.arange(CELL, dtype=np.float32)[None, :] + .5
GRID_Y = np.arange(CELL, dtype=np.float32)[:, None] + .5


def plate_distance(face):
    corners = [face.pixels(point) for point in face.plate]
    distance = np.full((CELL, CELL), np.inf, np.float32)
    for a, b in zip(corners, corners[1:] + corners[:1]):
        step = b - a
        cross = step[0] * (GRID_Y - a[1]) - step[1] * (GRID_X - a[0])
        np.minimum(distance, cross / np.linalg.norm(step), out=distance)
    return distance


def marks(die, face, glyphs, distance):
    spots = []
    mid = face.pixels(face.center)
    if die.key == "d4":
        for number, reading in face.readings.items():
            # Each digit has its own frame. Its top aims toward its actual apex.
            corner = face.plate[face.indices.index(number - 1)]
            tangent = np.asarray((reading.dot(face.right), reading.dot(face.up)))
            tangent /= np.linalg.norm(tangent)
            spots.append((number, mid * .50 + face.pixels(corner) * .50, tangent, 57.0))
    else:
        height = {"d6": 128.0, "d8": 96.0, "d10": 111.0, "d12": 114.0}[die.key]
        if die.key in ("d6", "d12"):
            mid += (0, 4.0)
        corners = np.array([face.pixels(p) for p in face.plate])
        height = min(height, np.ptp(corners[:, 0]) * .58 / glyphs[face.number][2])
        spots.append((face.number, mid, np.array((0.0, 1.0)), height))
    result = np.zeros((CELL, CELL), np.float32)
    ornaments = np.zeros_like(result)
    for number, center, up, height in spots:
        right = np.array((up[1], -up[0]))
        px, py = GRID_X - center[0], GRID_Y - center[1]
        local_x = px * right[0] + py * right[1]
        local_y = px * up[0] + py * up[1]
        for factor in (1.0, .94, .88, .82, .76):
            size = height * factor
            glyph = raster_glyph(glyphs[number], center, up, size)
            symbol = np.zeros_like(result)
            if number in (6, 9):
                half_width = size * .195
                baseline = size * .635
                symbol = np.clip(3.6 - np.hypot(np.maximum(abs(local_x) - half_width, 0), local_y + baseline), 0, 1)
            if number == len(die.faces):
                radius = 7.8 if die.key == "d4" else 14.0
                position = size * (.62 if die.key == "d4" else .72) + radius * .62
                star = (abs(local_x) / radius)**.64 + (abs(local_y - position) / radius)**.64
                symbol = np.maximum(symbol, np.clip((1.09 - star) * 8, 0, 1))
            footprint = np.maximum(glyph, symbol) > .06
            if distance[footprint].min() >= 21.0:
                break
        else:
            raise ValueError(f"{die.key} face {face.number}: cannot inset glyph {number}")
        assert not np.any(footprint & (np.maximum(result, ornaments) > .06))
        assert size >= 42.0
        if number in (6, 9) or number == len(die.faces):
            assert np.count_nonzero(symbol > .5) > 30
            assert not np.any((symbol > .06) & (glyph > .06))
        result = np.maximum(result, glyph)
        ornaments = np.maximum(ornaments, symbol)
    return result, ornaments


def bake_atlas(die, glyphs):
    maps = [np.ones((d20.ATLAS_SIZE, d20.ATLAS_SIZE, 4), np.float32) for _ in range(3)]
    for face in die.faces:
        distance = plate_distance(face)
        edge = np.clip(distance / 75.0, 0, 1)
        trim = np.clip(1.55 - abs(distance - 13.0), 0, 1) * .92
        shadow = np.clip(1.25 - abs(distance - 16.4), 0, 1) * .49
        rng = np.random.default_rng(418 + face.number)
        wash = d20.pigment_noise(rng, CELL, CELL, 55)
        flecks = d20.pigment_noise(rng, CELL, CELL, 7)
        grain = rng.random((CELL, CELL)) - .5
        glaze = np.clip(.17 + edge*.57 + (wash-.5)*.29 + (flecks-.5)*.07 + grain*.028, 0, 1)
        color = d20.rgb("3B678C") + glaze[:, :, None] * (d20.rgb("689BBA") - d20.rgb("3B678C"))
        color += (d20.rgb("233E52") - color) * shadow[:, :, None]
        color += (d20.rgb("F2E6CE") - color) * trim[:, :, None]

        glyph, ornament = marks(die, face, glyphs, distance)
        fill = np.maximum(glyph, ornament)
        contour = d20.dilate(fill, 3)
        color += (d20.rgb("3F2C24") - color) * contour[:, :, None]
        gradient = np.clip((GRID_Y - face.offset[1] + 45.0) / 115.0, 0, 1)[:, :, None]
        ivory = d20.rgb("F2E6CE") + gradient * (d20.rgb("FFF1D1") - d20.rgb("F2E6CE"))
        color += (ivory - color) * glyph[:, :, None]
        color += (d20.rgb("CFA052") - color) * ornament[:, :, None]

        height = wash*.052 + flecks*.025 + grain*.010 - contour*.23 + fill*.078
        dy, dx = np.gradient(height)
        normal = np.stack((-dx, -dy, np.ones_like(dx)), axis=-1)
        normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
        orm = np.stack((np.ones_like(fill), .38 + .030*(wash-.5) - .055*fill,
                        .04 + .19*glyph + .70*ornament), axis=-1)
        left, bottom = face.tile
        for target, values in zip(maps, (color, normal*.5 + .5, orm), strict=True):
            target[bottom:bottom+CELL, left:left+CELL, :3] = values

    names = ("Glaze Albedo", "Engraving Normal", "Metallic Roughness")
    spaces = ("sRGB", "Non-Color", "Non-Color")
    return tuple(d20.packed_image(die.key.upper() + " " + name, pixels, space)
                 for name, pixels, space in zip(names, maps, spaces, strict=True))


def apply_materials(die, gold, glyphs):
    ceramic, shader = d20.pbr("Sea-mist glazed ceramic", "4A7BA0", .04, .38)
    shader.inputs["Coat Weight"].default_value = .16
    shader.inputs["Coat Roughness"].default_value = .24
    nodes, links = ceramic.node_tree.nodes, ceramic.node_tree.links
    textures = []
    for image in bake_atlas(die, glyphs):
        node = nodes.new("ShaderNodeTexImage")
        node.image = image
        node.extension = "EXTEND"
        textures.append(node)
    links.new(textures[0].outputs["Color"], shader.inputs["Base Color"])
    normal = nodes.new("ShaderNodeNormalMap")
    normal.inputs["Strength"].default_value = .85
    links.new(textures[1].outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], shader.inputs["Normal"])
    values = nodes.new("ShaderNodeSeparateColor")
    values.mode = "RGB"
    links.new(textures[2].outputs["Color"], values.inputs["Color"])
    links.new(values.outputs["Green"], shader.inputs["Roughness"])
    links.new(values.outputs["Blue"], shader.inputs["Metallic"])
    for material in (gold, ceramic):
        die.mesh.materials.append(material)


def axis_record(normal, up):
    assert abs(normal.length - 1) < 1e-6 and abs(up.length - 1) < 1e-6
    assert abs(normal.dot(up)) < 1e-6
    hint = d20.gltf_vector(up)
    return {"normal": d20.gltf_vector(normal), "up": hint, "up_hint": hint}


def make_table(die):
    table = {}
    face_count = len(die.faces)
    assert [face.number for face in die.faces] == list(range(1, face_count + 1))
    for face in die.faces:
        entry = axis_record(face.normal, face.up)
        if die.key == "d4":
            # Numeric keys describe the face opposite the corresponding apex.
            assert face.normal.dot(die.vertices[face.number - 1]) < -.999999
            entry["top_readings"] = {str(i): d20.gltf_vector(up) for i, up in sorted(face.readings.items())}
        else:
            opposite = [other for other in die.faces if face.normal.dot(other.normal) < -.999999]
            assert len(opposite) == 1 and face.number + opposite[0].number == face_count + 1
            if die.key == "d10":
                assert (face.number % 2 == 1) == (face.normal.z > 0)
        table[str(face.number)] = entry
    if die.key == "d4":
        table["reading_mode"] = "apex_top"
        table["apex_vectors"] = {str(i + 1): d20.gltf_vector(vertex) for i, vertex in enumerate(die.vertices)}
        views = {}
        for i, vector in enumerate(die.vertices, 1):
            matching = []
            for face in die.faces:
                if i not in face.readings:
                    continue
                toward_apex = (vector - face.normal * vector.dot(face.normal)).normalized()
                assert toward_apex.dot(face.readings[i]) > .999999
                matching.append({"face_key": str(face.number), **axis_record(face.normal, face.readings[i])})
            assert len(matching) == 3
            views[str(i)] = matching
        table["apex_views"] = views
    return table


def glb(path):
    data = path.read_bytes()
    magic, version, size, chunk_size, tag = struct.unpack_from("<4sIII4s", data)
    assert (magic, version, size, tag) == (b"glTF", 2, len(data), b"JSON")
    offset = 20 + chunk_size
    byte_count, binary_tag = struct.unpack_from("<I4s", data, offset)
    assert binary_tag == b"BIN\0" and offset + 8 + byte_count == size
    return json.loads(data[20:offset]), data[offset+8:], size


def attribute(doc, binary, index, columns):
    accessor = doc["accessors"][index]
    kind = {5123: "<u2", 5125: "<u4", 5126: "<f4"}[accessor["componentType"]]
    field = doc["bufferViews"][accessor["bufferView"]]
    offset = field.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    width = np.dtype(kind).itemsize
    return np.ndarray((accessor["count"], columns), dtype=kind, buffer=binary,
                      offset=offset, strides=(field.get("byteStride", columns * width), width))


def validate_export(path, die, table, reference):
    doc, binary, size = glb(path)
    assert len(doc["nodes"]) == len(doc["meshes"]) == 1
    assert not {"translation", "rotation", "scale", "matrix"}.intersection(doc["nodes"][0])
    primitives = doc["meshes"][0]["primitives"]
    assert len(primitives) == 2
    assert all("TANGENT" in primitive["attributes"] for primitive in primitives)
    assert sum(doc["accessors"][p["indices"]]["count"] // 3 for p in primitives) == len(die.mesh.loop_triangles)
    assert len(doc["images"]) == 3
    for image in doc["images"]:
        view = doc["bufferViews"][image["bufferView"]]
        offset = view.get("byteOffset", 0)
        assert binary[offset:offset+8] == b"\x89PNG\r\n\x1a\n"
        assert struct.unpack_from(">II", binary, offset + 16) == (2048, 2048)

    gold = next(mat for mat in doc["materials"] if mat["name"] == "Antique gilt")
    source_gold = next(mat for mat in reference["materials"] if mat["name"] == gold["name"])
    assert gold == source_gold, "Gold parameters must match existing D20 GLB"
    index, ceramic = next((i, mat) for i, mat in enumerate(doc["materials"]) if mat["name"].startswith("Sea-mist"))
    source_ceramic = next(mat for mat in reference["materials"] if mat["name"].startswith("Sea-mist"))
    assert ceramic["extensions"] == source_ceramic["extensions"]
    assert ceramic["normalTexture"]["scale"] == source_ceramic["normalTexture"]["scale"]
    assert set(ceramic["pbrMetallicRoughness"]) == set(source_ceramic["pbrMetallicRoughness"])
    assert doc["samplers"] == reference["samplers"]

    surface = next(p for p in primitives if p["material"] == index)
    position = attribute(doc, binary, surface["attributes"]["POSITION"], 3)
    uv = attribute(doc, binary, surface["attributes"]["TEXCOORD_0"], 2)
    triangles = attribute(doc, binary, surface["indices"], 1).reshape(-1, 3)
    all_positions = position[triangles].astype(np.float64)
    all_uv = uv[triangles].astype(np.float64)
    raster = all_uv.copy()
    raster[:, :, 1] = 1.0 - raster[:, :, 1]
    raster *= d20.ATLAS_SIZE
    verified = set()
    for face in die.faces:
        reading = table[str(face.number)]
        normal, up = np.asarray(reading["normal"]), np.asarray(reading["up"])
        low = np.asarray(face.tile)
        within = np.all((raster >= low) & (raster < low + CELL), axis=(1, 2))
        plane = face.plate[0].dot(face.normal)
        level = np.max(abs(all_positions @ normal - plane), axis=1) < 1e-6
        matching = np.flatnonzero(within & level)
        assert len(matching) >= len(face.indices) - 2
        for i in matching:
            positions = all_positions[i]
            axes = (positions[1:] - positions[0]).T
            coords = all_uv[i]
            jacobian = axes @ np.linalg.inv((coords[1:] - coords[0]).T)
            stored_normal = np.cross(axes[:, 0], axes[:, 1])
            stored_normal /= np.linalg.norm(stored_normal)
            stored_up = -jacobian[:, 1] / np.linalg.norm(jacobian[:, 1])
            assert np.linalg.norm(normal - stored_normal) < 3e-6
            assert np.linalg.norm(up - stored_up) < 3e-6, "Texture and stored upright differ"
            if die.key == "d4":
                for number, reading_up in face.readings.items():
                    raster_vector = np.array((reading_up.dot(face.right), -reading_up.dot(face.up)))
                    top = jacobian @ raster_vector
                    top /= np.linalg.norm(top)
                    assert np.linalg.norm(top - table[str(face.number)]["top_readings"][str(number)]) < 3e-6
        verified.add(face.number)
    assert len(verified) == len(die.faces)
    print(f"{path.name}: {len(die.mesh.loop_triangles):,} triangles, {size:,} bytes; "
          f"{len(verified)} exported normals and UV uprights verified", flush=True)


def export(die, table, reference):
    for node in bpy.context.selected_objects:
        node.select_set(False)
    obj = bpy.data.objects.new(die.key.upper() + " · sea-mist ceramic", die.mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    target = DICE / f"{die.key}_skin.glb"
    status = bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB", use_selection=True,
                                       export_yup=True, export_tangents=True, export_animations=False)
    assert "FINISHED" in status
    validate_export(target, die, table, reference)
    bpy.data.objects.remove(obj, do_unlink=True)


def studio(font):
    scene = bpy.context.scene
    paper, shade = d20.pbr("Warm parchment stage", "AA8D71", 0.0, .81)
    deck = paper.node_tree.nodes
    noise = deck.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 22
    noise.inputs["Detail"].default_value = 2.2
    ramp = deck.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*d20.srgb_to_linear("8E7058"), 1)
    ramp.color_ramp.elements[1].color = (*d20.srgb_to_linear("AE9276"), 1)
    paper.node_tree.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    paper.node_tree.links.new(ramp.outputs["Color"], shade.inputs["Base Color"])
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.012))
    bpy.context.object.data.materials.append(paper)
    ink, _ = d20.pbr("Warm studio ink", "442F22", 0.0, .92)

    if scene.world is None:
        scene.world = bpy.data.worlds.new("Die studio")
    if scene.world.node_tree is None:
        scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (.32, .37, .46, 1)
    background.inputs["Strength"].default_value = .43
    for name, location, energy, color, width in [
        ("Warm key", (-4.8, -5.8, 7.5), 2100, (1.0, .83, .65), 8.3),
        ("Sea fill", (5.9, -3.2, 4.5), 1230, (.67, .82, 1.0), 6.5),
        ("Gold rim", (.3, 4.8, 5.8), 1760, (1.0, .88, .70), 7.2),
    ]:
        light = bpy.data.lights.new(name, "AREA")
        light.energy, light.color, light.shape, light.size = energy, color, "DISK", width
        obj = bpy.data.objects.new(name, light)
        bpy.context.scene.collection.objects.link(obj)
        obj.location = location
        d20.aimed(obj, (0, 0, .36))

    camera_data = bpy.data.cameras.new("Oblique studio camera")
    camera_data.type = "ORTHO"
    camera = bpy.data.objects.new("Oblique studio camera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    scene.camera = camera
    scene.view_settings.view_transform = "AgX"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.resolution_percentage = 100
    return scene, camera, ink


def basis(normal, up):
    return Matrix((up.cross(normal), up, normal)).transposed()


def die_pose(die, number, d4_turn=21):
    if die.key == "d4":
        apex = die.vertices[number - 1]
        facing = next(face for face in die.faces if number in face.readings)
        up = -(facing.normal - apex * facing.normal.dot(apex)).normalized()
        return Matrix.Rotation(math.radians(d4_turn), 3, "Z") @ basis(apex, up).transposed()
    face = die.face(number)
    return basis(face.normal, face.up).transposed()


def mount(name, mesh, rotation, x, y, scale=1.0):
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.rotation_euler = rotation.to_euler()
    obj.scale = (scale,) * 3
    contact = min((rotation @ vertex.co).z for vertex in mesh.vertices) * scale
    obj.location = (x, y, -contact)
    return obj


def label(text, font, ink, x, y, size):
    curve = bpy.data.curves.new(text, "FONT")
    curve.body, curve.font, curve.align_x, curve.size = text, font, "CENTER", size
    curve.space_character = 1.06
    curve.materials.append(ink)
    obj = bpy.data.objects.new(text, curve)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = (x, y, -.006)
    return obj


def render(scene, path):
    scene.render.filepath = str(path)
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "CYCLES"):
        try:
            scene.render.engine = engine
            if engine == "CYCLES":
                scene.cycles.device = "CPU"
                scene.cycles.samples = 20
                scene.cycles.use_denoising = True
            if "FINISHED" in bpy.ops.render.render(write_still=True):
                print(f"{engine} wrote {path}", flush=True)
                return
        except (TypeError, ValueError, RuntimeError) as reason:
            print(f"{engine}: {reason}", flush=True)
    raise RuntimeError(f"Cannot render {path.name}")


def old_d20():
    # Import the original asset into the transient studio only.
    for item in bpy.context.selected_objects:
        item.select_set(False)
    result = bpy.ops.import_scene.gltf(filepath=str(ASSETS / "d20_skin.glb"))
    assert "FINISHED" in result
    models = [item for item in bpy.context.selected_objects if item.type == "MESH"]
    assert len(models) == 1
    reference = json.loads((ASSETS / "d20_faces.json").read_text())
    assert len(reference) == 20

    def blender_vector(vector):
        return Vector((vector[0], -vector[2], vector[1])).normalized()

    axes = reference["20"]
    return models[0], basis(blender_vector(axes["normal"]), blender_vector(axes["up"])).transposed()


def previews(dice, font):
    scene, camera, ink = studio(font)
    lineup = []
    for die, x in zip(dice.values(), (-5.85, -3.53, -1.18, 1.19, 3.57), strict=True):
        lineup.append(mount(die.key, die.mesh, die_pose(die, len(die.faces)), x, .30))
        lineup.append(label(die.key.upper(), font, ink, x, -1.19, .206))
    model, pose = old_d20()
    lineup.append(mount("D20 reference", model.data, pose, 5.94, .30))
    bpy.data.objects.remove(model, do_unlink=True)
    lineup.append(label("D20  REFERENCE", font, ink, 5.94, -1.19, .177))
    camera.location = (0, -11.9, 11.1)
    d20.aimed(camera, (0, 0, .53))
    camera.data.ortho_scale = 14.43
    scene.render.resolution_x, scene.render.resolution_y = 2520, 1116
    render(scene, PREVIEWS / "polyhedral_dice_lineup.png")

    for obj in lineup:
        obj.hide_render = True
    for key, x in (("d4", -2.63), ("d10", 0), ("d12", 2.63)):
        die = dice[key]
        mount(key + " close-up", die.mesh, die_pose(die, len(die.faces), d4_turn=54), x, .56, 1.12)
        label(key.upper(), font, ink, x, -1.04, .157)
    for number, x in ((6, -.86), (9, .86)):
        die = dice["d10"]
        mount(f"D10 underline {number}", die.mesh, die_pose(die, number), x, -2.02, .61)
    camera.location = (0, -9.4, 10.45)
    d20.aimed(camera, (0, -.64, .53))
    camera.data.ortho_scale = 8.18
    scene.render.resolution_x, scene.render.resolution_y = 2380, 1460
    render(scene, PREVIEWS / "polyhedral_dice_closeup.png")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    DICE.mkdir(parents=True, exist_ok=True)
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    reference, _, _ = glb(ASSETS / "d20_skin.glb")
    font = d20.studio_font()
    glyphs = glyph_shapes(font)
    gold, _ = d20.pbr("Antique gilt", "CFA052", .85, .30)
    dice, tables = {}, {}
    for key in FACE_KINDS:
        die = shape(key)
        die.mesh = make_geometry(die)
        apply_materials(die, gold, glyphs)
        tables[key] = make_table(die)
        export(die, tables[key], reference)
        dice[key] = die
    (DICE / "dice_face_tables.json").write_text(json.dumps(tables, indent=2) + "\n", encoding="utf-8")
    previews(dice, font)


if __name__ == "__main__":
    main()
