"""Build the tabletop world atlas from the original color map with Blender and NumPy.

Run from the repository: blender --background --python tools/build_world_map_blender.py
The optional -- --cuts-only argument validates the masks without exporting.
"""

import json
import math
from pathlib import Path
import struct
import sys
import tempfile

import bpy
from mathutils import Vector, geometry
import numpy as np


sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from world_atlas_architecture import build_archetypes, build_ring


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/maps/world_map_colored.png"
MODEL = ROOT / "assets/3d/world_map.glb"
DATA = ROOT / "data/maps/world_map_data.json"
CUT_PREVIEW = ROOT / "tools/world_map_regions_preview.png"
WORLD_RENDER = ROOT / "tools/world_map_3d_world.png"
CLOSE_RENDER = ROOT / "tools/world_map_3d_closeup.png"
REFERENCE_SIZE = (1672, 941)
PIXEL_UNIT = 0.01
CONTINENT_TOP = 0.135

# These short gates isolate the colored land masses where the illustrated
# parchment border joins two otherwise separate shores.
GATES = {
    "demon_sky": ((1111, 17), (1116, 32), (1119, 51), (1121, 66), (1126, 87)),
    "demon_milis": ((1452, 499), (1436, 499), (1427, 503), (1419, 508)),
    "milis_central": ((946, 807), (951, 820), (952, 848)),
    "central_begaritt": ((259, 434), (270, 443), (282, 456), (301, 477)),
    "central_begaritt_south": ((781, 811), (779, 829), (780, 862)),
    "central_sky": ((829, 49), (839, 66), (844, 81), (855, 116)),
}
REGIONS = {
    "demon": {"seed": (1390, 206), "color": (1.0, 0.36, 0.07),
              "islands": ((1310, 402, 1415, 510),)},
    "milis": {"seed": (1340, 710), "color": (0.09, 0.9, 0.42),
              "islands": ((953, 771, 1070, 835),)},
    "central": {"seed": (453, 351), "color": (0.20, 0.62, 1.0),
                "islands": ((754, 86, 925, 231), (706, 766, 928, 829), (269, 476, 314, 505))},
}


def raster_image(image):
    width, height = image.size
    values = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(values)
    return values.reshape(height, width, 4)[::-1].copy()


def save_image(path, pixels):
    h, w = pixels.shape[:2]
    image = bpy.data.images.new(path.stem, width=w, height=h, alpha=True)
    image.pixels.foreach_set(np.ascontiguousarray(pixels[::-1]).ravel())
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)


def components(mask):
    """Four-connected labels using spans, rather than per-pixel flood stacks."""
    h, w = mask.shape
    parent = [0]
    spans = []
    previous = []

    def representative(index):
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    for y, row in enumerate(mask):
        cuts = np.flatnonzero(np.diff(np.r_[False, row, False]))
        current = []
        cursor = 0
        for left, right in cuts.reshape(-1, 2):
            left, right = int(left), int(right)
            index = len(parent)
            parent.append(index)
            while cursor < len(previous) and previous[cursor][1] <= left:
                cursor += 1
            match = cursor
            while match < len(previous) and previous[match][0] < right:
                parent[representative(previous[match][2])] = representative(index)
                match += 1
            current.append((left, right, index))
            spans.append((y, left, right, index))
        previous = current
    output = np.zeros((h, w), dtype=np.int32)
    for y, left, right, index in spans:
        output[y, left:right] = representative(index)
    return output, np.bincount(output.ravel(), minlength=len(parent))


def expand(mask, radius):
    result = mask.copy()
    for shift in range(1, radius + 1):
        result[shift:] |= mask[:-shift]
        result[:-shift] |= mask[shift:]
    vertical = result.copy()
    for shift in range(1, radius + 1):
        result[:, shift:] |= vertical[:, :-shift]
        result[:, :-shift] |= vertical[:, shift:]
    return result


def stroke(mask, points, radius):
    h, w = mask.shape
    for a, b in zip(points, points[1:]):
        steps = max(1, math.ceil(max(abs(b[0] - a[0]), abs(b[1] - a[1]))))
        for index in range(steps + 1):
            t = index / steps
            x = round(a[0] + (b[0] - a[0]) * t)
            y = round(a[1] + (b[1] - a[1]) * t)
            mask[max(0, y-radius):min(h, y+radius+1), max(0, x-radius):min(w, x+radius+1)] = True


def outer_mask(pixels):
    rgb = pixels[:, :, :3]
    paper_white = (rgb.min(axis=2) > 0.935) & (np.ptp(rgb, axis=2) < 0.046)
    labels, _ = components(paper_white)
    exterior = set(np.unique(np.concatenate((labels[0], labels[-1], labels[:, 0], labels[:, -1])))) - {0}
    assert labels[0, 0] in exterior and labels[-1, -1] in exterior, "White margin must surround the artwork."
    labels, counts = components(~np.isin(labels, list(exterior)))
    main = int(1 + np.argmax(counts[1:]))
    silhouette = labels == main
    assert 0.49 < silhouette.mean() < 0.87
    return silhouette


def identify_regions(pixels, silhouette):
    r, g, b = np.moveaxis(pixels[:, :, :3], -1, 0)
    blue = ((g - r > 0.024) & (b - r > -0.018) & (g + b > 0.43)) | ((b - r > 0.034) & (g - r > -0.01))
    # Seal thin grid lines in the sea. Only ocean reachable from a sea seed is
    # removed, so cool ink, snow and interior lakes stay on their land plates.
    blue = ~expand(~expand(blue & silhouette, 2), 2) & silhouette
    water_labels, _ = components(blue)
    probes = ((970, 430), (475, 680), (1162, 44), (1362, 455), (925, 795))
    ocean_ids = {int(water_labels[y, x]) for x, y in probes} - {0}
    ocean = np.isin(water_labels, list(ocean_ids))
    gate_mask = np.zeros_like(silhouette)
    for path in GATES.values():
        stroke(gate_mask, path, 2)
    labels, counts = components(silhouette & ~ocean & ~gate_mask)
    owned = {}
    used = set()
    for name, region in REGIONS.items():
        x, y = region["seed"]
        own = int(labels[y, x])
        assert own and own not in used, f"Gate failed to isolate {name}"
        used.add(own)
        owned[name] = [own]
    excluded = {int(labels[y, x]) for x, y in ((306, 802), (989, 33))}
    assert not (used & excluded), "An excluded plate is attached to a movable mainland."
    for name, region in REGIONS.items():
        for left, top, right, bottom in region["islands"]:
            nearby = np.bincount(labels[top:bottom, left:right].ravel(), minlength=len(counts))
            for index in np.flatnonzero((nearby >= 13) & (nearby >= 0.8 * counts) & (counts <= 2400)):
                index = int(index)
                if index not in used and index not in excluded:
                    owned[name].append(index)
                    used.add(index)
    masks = {name: np.isin(labels, ids) for name, ids in owned.items()}
    for name, mask in masks.items():
        print(f"{name}: {mask.sum()} pixels, {len(owned[name])} components", flush=True)
    assert 42000 < masks["demon"].sum() < 125000
    assert 30000 < masks["milis"].sum() < 115000
    assert 105000 < masks["central"].sum() < 365000
    return masks


def signed_area(points):
    return sum(a[0]*b[1] - b[0]*a[1] for a, b in zip(points, points[1:] + points[:1])) * 0.5


def trace_loops(mask):
    padded = np.pad(mask, 1)
    neighbors = (padded[:-2, 1:-1], padded[1:-1, 2:], padded[2:, 1:-1], padded[1:-1, :-2])
    corners = (((0, 0), (1, 0)), ((1, 0), (1, 1)), ((1, 1), (0, 1)), ((0, 1), (0, 0)))
    edges = {}
    for nearby, (a, b) in zip(neighbors, corners):
        for y, x in np.argwhere(mask & ~nearby):
            start = (int(x)+a[0], int(y)+a[1])
            end = (int(x)+b[0], int(y)+b[1])
            edges.setdefault(start, []).append(end)

    def pick(start, previous):
        options = edges[start]
        if len(options) == 1:
            end = options.pop()
        else:
            dx, dy = start[0]-previous[0], start[1]-previous[1]
            end = max(options, key=lambda p: 2*(dx*(p[1]-start[1])-dy*(p[0]-start[0]))
                      + dx*(p[0]-start[0]) + dy*(p[1]-start[1]))
            options.remove(end)
        if not options:
            del edges[start]
        return end

    loops = []
    while edges:
        first = next(iter(edges))
        current = first
        previous = (first[0] - 1, first[1])
        loop = []
        while True:
            loop.append(current)
            following = pick(current, previous)
            if following == first:
                break
            previous, current = current, following
        if len(loop) >= 4 and signed_area(loop) >= 15:
            loops.append(loop)
    return sorted(loops, key=signed_area, reverse=True)


def simplify_open(points, epsilon):
    if len(points) < 3:
        return points
    a, b = Vector(points[0]), Vector(points[-1])
    edge = b - a
    maximum, split = 0.0, 0
    for index, point in enumerate(points[1:-1], 1):
        relative = Vector(point) - a
        ratio = min(1.0, max(0.0, relative.dot(edge) / max(edge.length_squared, 1e-7)))
        distance = (relative - edge * ratio).length
        if distance > maximum:
            maximum, split = distance, index
    if maximum <= epsilon:
        return [points[0], points[-1]]
    return simplify_open(points[:split+1], epsilon)[:-1] + simplify_open(points[split:], epsilon)


def outline(mask, tolerance):
    result = []
    for loop in trace_loops(mask):
        half = len(loop) // 2
        simplified = simplify_open(loop[:half+1], tolerance)[:-1]
        simplified += simplify_open(loop[half:] + loop[:1], tolerance)[:-1]
        if len(simplified) < 3:
            continue
        smooth = [tuple(Vector(point) * 0.82 + (Vector(simplified[i-1])
                  + Vector(simplified[(i+1) % len(simplified)])) * 0.09)
                  for i, point in enumerate(simplified)]
        result.append(smooth)
    return result


def ridge(axis, points):
    return np.interp(axis, [point[0] for point in points], [point[1] for point in points])


def partition(masks):
    """Trace interior boundaries along visible ridges, forests and headlands.

    The values are source-image pixel guides. The coast mask always clips
    the guides, including any islands on either side of a straight extension.
    """
    y, x = np.ogrid[:REFERENCE_SIZE[1], :REFERENCE_SIZE[0]]
    demon_west = x < ridge(y, ((0, 1316), (63, 1333), (102, 1348), (152, 1374), (207, 1370), (235, 1381)))
    demon_north = y < ridge(x, ((1110, 207), (1248, 186), (1281, 197), (1330, 221), (1381, 239),
                               (1422, 221), (1451, 233), (1494, 208), (1545, 213)))
    demon_south = y >= ridge(x, ((1248, 339), (1299, 361), (1329, 359), (1359, 378),
                               (1385, 365), (1429, 386), (1459, 369), (1530, 376)))
    milis_north = y < ridge(x, ((1295, 601), (1352, 584), (1390, 590), (1424, 569), (1509, 579)))
    milis_forest = y < ridge(x, ((1187, 625), (1267, 650), (1329, 669), (1363, 680),
                                (1390, 699), (1452, 711), (1520, 738)))
    milis_west = x < ridge(y, ((710, 1091), (777, 1091), (800, 1130), (825, 1111), (873, 1138), (905, 1138)))
    north = y < ridge(x, ((120, 129), (213, 141), (272, 137), (316, 161), (366, 155),
                          (417, 178), (494, 166), (553, 188), (638, 163), (734, 158), (910, 170)))
    north |= (x >= 775) & (y < 231)
    biheiriru = x >= ridge(y, ((0, 563), (45, 578), (82, 581), (119, 609), (175, 620)))
    south = y > ridge(x, ((320, 604), (448, 610), (502, 604), (547, 582), (615, 590), (660, 566), (740, 593)))
    sword = (x < ridge(y, ((105, 206), (158, 210), (192, 223), (226, 213),
                           (250, 220), (275, 209), (299, 190), (319, 177)))) & (y < 323)
    asura = x < ridge(y, ((0, 335), (160, 352), (201, 387), (239, 435), (270, 449),
                         (300, 470), (330, 487), (390, 495), (435, 514), (482, 513), (545, 543), (620, 563)))
    strife = x < ridge(y, ((158, 715), (206, 657), (252, 632), (309, 623), (362, 638),
                          (402, 627), (446, 647), (493, 622), (529, 617), (569, 620), (630, 633)))
    labels = {
        "demon": np.select([demon_south, demon_north & demon_west, demon_north & ~demon_west],
                           [4, 2, 1], default=3),
        "milis": np.select([milis_north, milis_west, milis_forest], [1, 4, 2], default=3),
        "central": np.select([north & biheiriru, north, south, sword, asura, strife],
                             [4, 1, 7, 2, 3, 5], default=6),
    }
    result = {}
    for name, label in labels.items():
        label = np.where(masks[name], label, 0)
        # Recess only the shared interior edges, leaving the original coast intact.
        seam = np.zeros_like(label, dtype=bool)
        seam[1:] |= (label[1:] > 0) & (label[:-1] > 0) & (label[1:] != label[:-1])
        seam[:, 1:] |= (label[:, 1:] > 0) & (label[:, :-1] > 0) & (label[:, 1:] != label[:, :-1])
        visible = np.where(seam, 0, label)
        result[name] = [visible == number for number in range(1, 8 if name == "central" else 5)]
    return result


def sites(region):
    for city in region["cities"]:
        yield city
        yield from city.get("sites", [])


def site_scale(city, mask):
    x, y = city["pixel"]
    assert mask[y, x], f'{city["id"]} must stand on its authored region at {x},{y}'
    left, top = max(0, x - 23), max(0, y - 23)
    ys, xs = np.nonzero(~mask[top:y + 24, left:x + 24])
    clearance = min(np.hypot(xs + left - x, ys + top - y), default=23.0)
    assert clearance >= 6.0, f'{city["id"]} needs a land-supported pedestal (clearance {clearance:.1f}px)'
    return float(min(0.165, (clearance - 1.6) * PIXEL_UNIT))


def paint_box(pixels, x, y, width, height, color):
    pixels[y:y + height, x:x + width, :3] = color


def paint_number(pixels, x, y, value):
    maps = ("abcdef", "bc", "abdeg", "abcdg", "bcfg", "acdfg", "acdefg", "abc", "abcdefg", "abcdfg")
    paths = {"a": (2, 0, 7, 2), "b": (8, 2, 2, 6), "c": (8, 10, 2, 6),
             "d": (2, 16, 7, 2), "e": (0, 10, 2, 6), "f": (0, 2, 2, 6), "g": (2, 8, 7, 2)}
    label = str(value)
    x -= 6 * len(label)
    paint_box(pixels, x - 4, y - 3, 12 * len(label) + 6, 24, (0.15, 0.09, 0.07))
    for digit in label:
        for segment in maps[int(digit)]:
            dx, dy, width, height = paths[segment]
            paint_box(pixels, x + dx, y + dy, width, height, (1.0, 0.91, 0.72))
        x += 12


def preview_cuts(pixels, continents, outlines, masks):
    marked = pixels.copy()
    number = 0
    for group in continents:
        for region in group["regions"]:
            number += 1
            name = region["id"]
            paint = np.zeros(marked.shape[:2], dtype=bool)
            shadow = np.zeros_like(paint)
            for line in outlines[name]:
                rounded = [(round(x), round(y)) for x, y in line]
                stroke(shadow, rounded + rounded[:1], 2)
                stroke(paint, rounded + rounded[:1], 1)
            marked[shadow, :3] *= 0.48
            marked[paint, :3] = REGIONS[group["id"]]["color"]
            enough_space = ~expand(~masks[name], 15)
            for city in sites(region):
                px, py = city["pixel"]
                enough_space[py-22:py+23, px-26:px+27] = False
            candidates = np.argwhere(enough_space)
            if not len(candidates):
                candidates = np.argwhere(masks[name])
            row, col = candidates[np.argmin(((candidates - candidates.mean(axis=0))**2).sum(axis=1))]
            paint_number(marked, int(col), int(row) - 8, number)
    for group in continents:
        for region in group["regions"]:
            for city in sites(region):
                x, y = city["pixel"]
                disk = (np.arange(-7, 8)[None, :]**2 + np.arange(-7, 8)[:, None]**2)
                area = marked[y-7:y+8, x-7:x+8, :3]
                area[disk <= 44] = (1.0, 0.91, 0.73)
                area[disk <= 25] = (0.88, 0.12, 0.11)
    save_image(CUT_PREVIEW, marked)
    print(f"Cut and placement preview: {CUT_PREVIEW}", flush=True)


def segment(image, continents):
    assert tuple(image.size) == REFERENCE_SIZE, "Adjust coastline gates for a different source image size."
    pixels = raster_image(image)
    silhouette = outer_mask(pixels)
    coasts = identify_regions(pixels, silhouette)
    parts = partition(coasts)
    outer = outline(silhouette, 0.93)[0]
    coast_lines = {name: outline(mask, 1.05) for name, mask in coasts.items()}
    masks = {}
    outlines = {}
    for group in continents:
        for region, mask in zip(group["regions"], parts[group["id"]], strict=True):
            name = region["id"]
            assert mask.sum() >= 1400, name
            masks[name] = mask
            outlines[name] = outline(mask, 1.02)
            for city in sites(region):
                city["model_scale"] = site_scale(city, mask)
                print(f'{city["id"]} at {city["pixel"]}: {city["model_scale"]:.3f}')
    assert len(outlines) == 15
    preview_cuts(pixels, continents, outlines, masks)
    return outer, coast_lines, outlines


def world_point(point, elevation):
    x, y = point
    return ((x - REFERENCE_SIZE[0] * 0.5) * PIXEL_UNIT,
            (REFERENCE_SIZE[1] * 0.5 - y) * PIXEL_UNIT, elevation)


def offset(points, amount):
    shifted = []
    for i, value in enumerate(points):
        p = Vector(value)
        before = (p - Vector(points[i - 1])).normalized()
        after = (Vector(points[(i + 1) % len(points)]) - p).normalized()
        a = Vector((before.y, -before.x))
        b = Vector((after.y, -after.x))
        direction = (a + b).normalized()
        shift = min(amount * 2.0, amount / max(0.5, a.dot(direction)))
        shifted.append(tuple(p + direction * shift))
    return shifted


def triangulate_contours(loops):
    points = []
    faces = []
    for ring in loops:
        start = len(points)
        points.extend(Vector(p) for p in ring)
        faces.append(list(range(start, len(points))))
    vertices, _, triangles, _, _, origins = geometry.delaunay_2d_cdt(points, [], faces, 1, 0.0005)
    return vertices, triangles, origins


def finish_mesh(name, vertices, faces, assignments, materials, pivot):
    unique = []
    lookup = {}
    remap = []
    for vertex in vertices:
        key = tuple(round(component, 6) for component in vertex)
        if key not in lookup:
            lookup[key] = len(unique)
            unique.append(vertex)
        remap.append(lookup[key])
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([Vector(point) - pivot for point in unique], [],
                     [[remap[index] for index in face] for face in faces])
    mesh.update()
    assert not mesh.validate(clean_customdata=False), f"Invalid mesh: {name}"
    for material in materials:
        mesh.materials.append(material)
    uv = mesh.uv_layers.new(name="Original world map")
    for polygon, assignment in zip(mesh.polygons, assignments):
        polygon.material_index = assignment
        for loop in polygon.loop_indices:
            x, y, _ = unique[mesh.loops[loop].vertex_index]
            uv.data[loop].uv = (x / (REFERENCE_SIZE[0] * PIXEL_UNIT) + 0.5,
                                y / (REFERENCE_SIZE[1] * PIXEL_UNIT) + 0.5)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = pivot
    mesh.calc_loop_triangles()
    return obj


def surface(vertices, faces, assignments, points, triangles, origins, z, underside=False):
    start = len(vertices)
    vertices.extend(world_point(point, z) for point in points)
    for triangle, original in zip(triangles, origins):
        if not original or (not underside and 0 not in original):
            continue
        if len(triangle) != 3 or abs(signed_area([points[i] for i in triangle])) < 1e-7:
            continue
        clock = signed_area([points[i] for i in triangle]) > 0
        indices = [start + i for i in triangle]
        faces.append(list(reversed(indices)) if clock != underside else indices)
        assignments.append(3 if underside else (1 if len(original) > 1 else 0))


def shell(vertices, faces, assignments, profile, material_indices):
    starts = []
    for ring, z in profile:
        starts.append(len(vertices))
        vertices.extend(world_point(point, z) for point in ring)
    length = len(profile[0][0])
    for row, mat in enumerate(material_indices):
        top, lower = starts[row], starts[row + 1]
        for i in range(length):
            j = (i + 1) % length
            faces.append((top + i, top + j, lower + j, lower + i))
            assignments.append(mat)


def slab(name, outer, recesses, materials):
    vertices, faces, indices = [], [], []
    points, triangles, origins = triangulate_contours([outer, *recesses])
    surface(vertices, faces, indices, points, triangles, origins, 0.0)
    edge = offset(outer, 1.65)
    shell(vertices, faces, indices, [(outer, 0.0), (edge, -0.032), (edge, -0.169)], [2, 3])
    points, triangles, origins = triangulate_contours([edge])
    surface(vertices, faces, indices, points, triangles, origins, -0.169, True)
    return finish_mesh(name, vertices, faces, indices, materials, Vector((0, 0, 0)))


def region_mesh(name, loops, materials):
    minimum = np.min(np.concatenate(loops), axis=0)
    maximum = np.max(np.concatenate(loops), axis=0)
    pivot = Vector(world_point((minimum + maximum) * 0.5, CONTINENT_TOP))
    vertices, faces, indices = [], [], []
    for outline in loops:
        points, triangles, origins = triangulate_contours([outline])
        surface(vertices, faces, indices, points, triangles, origins, CONTINENT_TOP)
        lip = offset(outline, 0.68)
        # The top bevel flares down to the sidewall and the sole follows the lip.
        shell(vertices, faces, indices, [(outline, CONTINENT_TOP), (lip, 0.115), (lip, 0.014)], [2, 3])
        points, triangles, origins = triangulate_contours([lip])
        surface(vertices, faces, indices, points, triangles, origins, 0.014, True)
    return finish_mesh(name, vertices, faces, indices, materials, pivot)


def edge_rim(name, loops, parent, material, width=1.0, elevation=0.017):
    vertices, faces, indices = [], [], []
    for line in loops:
        outside = offset(line, width)
        inside = [tuple(Vector(p) * 2.0 - Vector(q)) for p, q in zip(line, outside)]
        roof = CONTINENT_TOP + elevation
        base = len(vertices)
        count = len(line)
        vertices.extend(world_point(point, roof) for point in outside)
        vertices.extend(world_point(point, roof) for point in inside)
        for i in range(count):
            j = (i + 1) % count
            faces.append((base + i, base + count + i, base + count + j, base + j))
            indices.append(0)
    obj = finish_mesh(name, vertices, faces, indices, [material], parent.location)
    obj.parent = parent
    obj.location = Vector((0, 0, 0))
    return obj


def material(name, base, roughness, metal=0.0):
    result = bpy.data.materials.new(name)
    if result.node_tree is None:
        result.use_nodes = True
    shader = next(node for node in result.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = (*base, 1.0)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metal
    return result, shader


def map_materials(image):
    top, top_shader = material("Unmodified color atlas", (1, 1, 1), 0.92)
    well, well_shader = material("Recessed parchment", (1, 1, 1), 0.94)
    for mat, shader in ((top, top_shader), (well, well_shader)):
        tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.interpolation = "Linear"
        tex.extension = "EXTEND"
        if mat == well:
            # Multiply in the recess material only. The GLB still embeds the
            # original image a single time for both surfaces.
            multiply = mat.node_tree.nodes.new("ShaderNodeMixRGB")
            multiply.blend_type = "MULTIPLY"
            multiply.inputs[0].default_value = 1.0
            multiply.inputs[2].default_value = (0.72, 0.66, 0.59, 1.0)
            mat.node_tree.links.new(tex.outputs["Color"], multiply.inputs[1])
            mat.node_tree.links.new(multiply.outputs[0], shader.inputs["Base Color"])
        else:
            mat.node_tree.links.new(tex.outputs["Color"], shader.inputs["Base Color"])
    bevel, _ = material("Patinated gilt bevel", (0.47, 0.275, 0.112), 0.41, 0.26)
    side, _ = material("Toasted parchment edge", (0.247, 0.106, 0.045), 0.64, 0.12)
    bronze, _ = material("Bronze index line", (0.85, 0.48, 0.13), 0.38, 0.26)
    return [top, well, bevel, side], bronze


def place_city(site, region, shapes, ring_mesh):
    sculpture = bpy.data.objects.new(site["node"], shapes[site["arch"]])
    bpy.context.collection.objects.link(sculpture)
    sculpture.parent = region
    sculpture.location = Vector(world_point(site["pixel"], CONTINENT_TOP + 0.006)) - region.location
    sculpture.scale = (site["model_scale"],) * 3
    ring = bpy.data.objects.new(site["ring"], ring_mesh)
    bpy.context.collection.objects.link(ring)
    ring.parent = sculpture
    return sculpture, ring


def read_float_attribute(gltf, binary, index, width):
    accessor = gltf["accessors"][index]
    assert accessor["componentType"] == 5126  # FLOAT in glTF 2.0.
    view = gltf["bufferViews"][accessor["bufferView"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    return np.ndarray((accessor["count"], width), dtype="<f4", buffer=binary,
                      offset=start, strides=(view.get("byteStride", width * 4), 4))


def verify_atlas_uvs(gltf, binary, authored, nodes):
    max_pixel_error = 0.0
    dimensions = np.array(REFERENCE_SIZE)
    for obj in authored:
        if obj.name != "world_base_slab" and not obj.name.startswith("region_"):
            continue
        node = nodes[obj.name]
        assert "rotation" not in node and "scale" not in node
        translation = np.array(node.get("translation", [0, 0, 0]))
        for surface in gltf["meshes"][node["mesh"]]["primitives"]:
            mat = gltf["materials"][surface["material"]]["name"]
            if mat not in ("Unmodified color atlas", "Recessed parchment"):
                continue
            attributes = surface["attributes"]
            position = read_float_attribute(gltf, binary, attributes["POSITION"], 3)
            uv = read_float_attribute(gltf, binary, attributes["TEXCOORD_0"], 2)
            expected = (position[:, [0, 2]] + translation[[0, 2]]) / PIXEL_UNIT + dimensions * 0.5
            max_pixel_error = max(max_pixel_error, np.max(np.abs(expected - uv * dimensions)))
    assert max_pixel_error < 0.002, f"Atlas UV drift: {max_pixel_error:.6f}px"
    print(f"Exported atlas UV drift: {max_pixel_error:.6f}px", flush=True)


def finish_export(authored):
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    for obj in authored:
        obj.hide_render = False
        obj.select_set(True)
    with tempfile.TemporaryDirectory(dir=MODEL.parent) as temporary:
        destination = Path(temporary) / MODEL.name
        bpy.ops.export_scene.gltf(filepath=str(destination), export_format="GLB",
                                  export_yup=True, export_animations=False, use_selection=True)
        triangles, drawn_triangles, size = validate_export(destination, authored)
        destination.replace(MODEL)
    print(f"World atlas export: {triangles:,} stored / {drawn_triangles:,} instanced triangles; "
          f"{size:,} bytes; original PNG verified byte-for-byte.", flush=True)


def validate_export(destination, authored):
    with destination.open("rb") as stream:
        magic, version, size = struct.unpack("<4sII", stream.read(12))
        json_length, json_type = struct.unpack("<I4s", stream.read(8))
        gltf = json.loads(stream.read(json_length))
        binary_length, binary_type = struct.unpack("<I4s", stream.read(8))
        binary = stream.read(binary_length)
    assert magic == b"glTF" and version == 2 and json_type == b"JSON"
    assert binary_type == b"BIN\0" and size == destination.stat().st_size
    nodes = {node["name"]: node for node in gltf["nodes"]}
    assert set(nodes) == {obj.name for obj in authored}, "Export lost a named object"
    for obj in authored:
        if obj.parent:
            parent = nodes[obj.parent.name]
            assert nodes[obj.name] in [gltf["nodes"][index] for index in parent["children"]], obj.name
    mesh_triangles = [
        sum(gltf["accessors"][primitive["indices"]]["count"] // 3 for primitive in mesh["primitives"])
        for mesh in gltf["meshes"]
    ]
    triangles = sum(mesh_triangles)
    drawn_triangles = sum(mesh_triangles[node["mesh"]] for node in nodes.values() if "mesh" in node)
    assert 1000 < triangles <= drawn_triangles <= 65000, f"Unexpected mobile mesh budget: {drawn_triangles} triangles"
    assert len(gltf["images"]) == 1, "Use the single original PNG for all top surfaces."
    view = gltf["bufferViews"][gltf["images"][0]["bufferView"]]
    position = view.get("byteOffset", 0)
    assert binary[position:position + view["byteLength"]] == SOURCE.read_bytes(), "Embedded texture diverged from the original PNG."
    verify_atlas_uvs(gltf, binary, authored, nodes)
    # The exporter keeps the atlas texture, but does not express this Multiply
    # node as a glTF factor. Record the same shade on the recess material.
    recess = next(item for item in gltf["materials"] if item["name"] == "Recessed parchment")
    recess["pbrMetallicRoughness"]["baseColorFactor"] = [0.72, 0.66, 0.59, 1.0]
    encoded = json.dumps(gltf, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    encoded += b" " * (-len(encoded) % 4)
    size = 28 + len(encoded) + len(binary)
    destination.write_bytes(struct.pack("<4sII", b"glTF", 2, size)
                            + struct.pack("<I4s", len(encoded), b"JSON") + encoded
                            + struct.pack("<I4s", len(binary), b"BIN\0") + binary)
    return triangles, drawn_triangles, size


def render_shot(scene, path):
    scene.render.filepath = str(path)
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "CYCLES"):
        try:
            scene.render.engine = engine
            if engine == "CYCLES":
                scene.cycles.device = "CPU"
                scene.cycles.samples = 20
                scene.cycles.use_denoising = True
            if "FINISHED" in bpy.ops.render.render(write_still=True):
                print(f"World atlas preview: {engine}; {path}", flush=True)
                return
        except (TypeError, ValueError, RuntimeError) as error:
            print(f"Cannot render preview with {engine}: {error}", flush=True)
    raise RuntimeError(f"No local render engine could render {path.name}.")


def render_preview(groups, hero, edges, feature_edge):
    for edge in edges:
        edge.hide_render = True
    groups["demon"].location.z = 0.34
    feature_edge.hide_render = False
    scene = bpy.context.scene
    bpy.ops.mesh.primitive_plane_add(size=150, location=(0, 0, -0.182))
    cloth, shader = material("Woven walnut table mat", (0.052, 0.025, 0.015), 0.91)
    bpy.context.object.data.materials.append(cloth)
    noise = cloth.node_tree.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 340.0
    noise.inputs["Detail"].default_value = 2.0
    ramp = cloth.node_tree.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.029, 0.014, 0.009, 1.0)
    ramp.color_ramp.elements[1].color = (0.093, 0.049, 0.031, 1.0)
    cloth.node_tree.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    cloth.node_tree.links.new(ramp.outputs["Color"], shader.inputs["Base Color"])

    def aim(obj, target):
        obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()

    camera_data = bpy.data.cameras.new("Oblique atlas camera")
    camera_data.lens = 39.0
    camera = bpy.data.objects.new(camera_data.name, camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (0, -10.2, 20.8)
    aim(camera, (0, 0, 0))
    scene.camera = camera
    for name, position, power, color, width in (
            ("Warm north window", (-5, -2, 11), 2300, (1.0, 0.84, 0.66), 8.0),
            ("Soft sea fill", (7, 6, 8), 1450, (0.70, 0.84, 1.0), 7.0),
            ("Parchment bounce", (0, -8, 6), 480, (1.0, 0.87, 0.72), 9.0)):
        light = bpy.data.lights.new(name, "AREA")
        light.energy, light.color, light.size = power, color, width
        lamp = bpy.data.objects.new(name, light)
        bpy.context.collection.objects.link(lamp)
        lamp.location = position
        aim(lamp, (0, 0, 0))
    scene.world = bpy.data.worlds.new("Warm room ambience")
    if scene.world.node_tree is None:
        scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.35, 0.30, 0.25, 1.0)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.5
    scene.view_settings.view_transform = "AgX"
    scene.render.resolution_x = 1680
    scene.render.resolution_y = 1080
    scene.render.resolution_percentage = 100
    render_shot(scene, WORLD_RENDER)
    groups["demon"].location.z = 0.0
    feature_edge.hide_render = True
    hero.location.z += 0.27
    location = Vector(world_point((1474, 124), CONTINENT_TOP))
    camera.location = location + Vector((0.38, -1.65, 2.12))
    camera_data.lens = 47.0
    aim(camera, location)
    render_shot(scene, CLOSE_RENDER)
    hero.location.z -= 0.27


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    image = bpy.data.images.load(str(SOURCE))
    configuration = json.loads(DATA.read_text(encoding="utf-8"))
    outer, coast_lines, outlines = segment(image, configuration["continents"])
    if "--cuts-only" in sys.argv:
        return
    materials, edge = map_materials(image)
    ceramics = [
        material("Porcelain ivory", (0.85, 0.67, 0.43), 0.35)[0],
        material("Warm cut limestone", (0.48, 0.36, 0.26), 0.57)[0],
        material("Aged brass footing", (0.64, 0.35, 0.112), 0.31, 0.70)[0],
        material("Seamist roof glaze", (0.105, 0.255, 0.37), 0.31, 0.08)[0],
        material("Terracotta roof glaze", (0.47, 0.15, 0.093), 0.38, 0.06)[0],
        material("Carved door shadow", (0.13, 0.077, 0.044), 0.70)[0],
    ]
    lamp, glaze = material("Lighthouse honey glass", (1.0, 0.57, 0.18), 0.27)
    glaze.inputs["Emission Color"].default_value = (1.0, 0.45, 0.12, 1.0)
    glaze.inputs["Emission Strength"].default_value = 0.45
    ceramics.append(lamp)
    shapes = build_archetypes(ceramics)
    ring_mesh = build_ring(ceramics)

    coasts = [line for lines in coast_lines.values() for line in lines]
    authored = [slab("world_base_slab", outer, coasts, materials)]
    groups, provinces, group_edges = {}, {}, {}
    edges = []
    for details in configuration["continents"]:
        name = details["id"]
        group = bpy.data.objects.new(details["node"], None)
        bpy.context.collection.objects.link(group)
        groups[name] = group
        authored.append(group)
        group_edge = edge_rim(details["rim"], coast_lines[name], group, edge, 1.65, 0.031)
        group_edges[name] = group_edge
        edges.append(group_edge)
        for region in details["regions"]:
            lines = outlines[region["id"]]
            plate = region_mesh(region["node"], lines, materials)
            provinces[region["id"]] = plate
            plate.parent = group
            region_rim = edge_rim(region["rim"], lines, plate, edge)
            edges.append(region_rim)
            authored.append(plate)
            for site in sites(region):
                city, ring = place_city(site, plate, shapes, ring_mesh)
                authored.append(city)
                edges.append(ring)
    render_preview(groups, provinces["demon_biegoya"], edges, group_edges["demon"])
    finish_export([*authored, *edges])


if __name__ == "__main__":
    main()
