"""Build the four atlas pawns and two studio previews with Blender's bundled Python.

Run blender --background --python tools/blender_props/build_travel_pawns.py.
The bases touch Blender Z=0. Blender's glTF exporter converts this to Y=0.
"""

import json
import math
from pathlib import Path
import struct

import bmesh
import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
MODELS = ROOT / "assets/3d/pawns"
PREVIEWS = Path(__file__).resolve().parent / "previews"
TAU = math.tau
GOLD, DARK_GOLD, IVORY, LINEN, BLUE, DARK_BLUE, WOOD, LEATHER, CRYSTAL, ICE, WATER = range(11)


class Parts:
    def __init__(self):
        self.points = []
        self.faces = []
        self.styles = []

    def solid(self, points, faces, material, smooth=False):
        start = len(self.points)
        self.points.extend(points)
        for index, face in enumerate(faces):
            self.faces.append([start + corner for corner in face])
            tone = material[index] if isinstance(material, (list, tuple)) else material
            shading = smooth[index] if isinstance(smooth, (list, tuple)) else smooth
            self.styles.append((tone, shading))

    def loft(self, rings, tone, smooth=True, loop=False):
        width = len(rings[0])
        points = [point for ring in rings for point in ring]
        faces = []
        styles = []
        shades = []
        for row in range(len(rings) if loop else len(rings) - 1):
            first, second = row * width, (row + 1) % len(rings) * width
            for i in range(width):
                j = (i + 1) % width
                faces.append((first + i, first + j, second + j, second + i))
                styles.append(tone(row, i) if callable(tone) else tone)
                shades.append(smooth)
        if not loop:
            faces.extend((tuple(reversed(range(width))), tuple(range(len(points) - width, len(points)))))
            styles.extend((tone(0, 0), tone(len(rings) - 2, 0)) if callable(tone) else (tone, tone))
            shades.extend((False, False))
        self.solid(points, faces, styles, shades)

    def turned(self, profile, tone, sides=48, stretch=1.0, loop=False):
        rings = [[(radius * math.cos(a), stretch * radius * math.sin(a), z)
                  for a in angles(sides)] for radius, z in profile]
        self.loft(rings, tone, loop=loop)

    def bar(self, start, end, radius, tone, sides=8, tip=None, bevel=True):
        start, end = Vector(start), Vector(end)
        if not bevel:
            self.tube([start, end], [radius, tip or radius], tone, sides)
            return
        size = radius * 0.15
        axis = (end - start).normalized()
        self.tube([start, start + axis * size, end - axis * size, end],
                  [radius * 0.78, radius, tip or radius, (tip or radius) * 0.78], tone, sides)

    def tube(self, points, radius, tone, sides=8, loop=False, guide=(0, 0, 1)):
        points = [Vector(p) for p in points]
        rings = []
        for i, point in enumerate(points):
            before = points[(i - 1) % len(points)] if loop else points[max(0, i - 1)]
            after = points[(i + 1) % len(points)] if loop else points[min(i + 1, len(points) - 1)]
            axis = (after - before).normalized()
            right = axis.cross(Vector(guide))
            if right.length_squared < 1e-8:
                right = axis.cross(Vector((1, 0, 0)))
            right.normalize()
            up = axis.cross(right)
            size = radius[i] if isinstance(radius, (list, tuple)) else radius
            rings.append([point + size * (right * math.cos(a) + up * math.sin(a)) for a in angles(sides)])
        self.loft(rings, tone, loop=loop)

    def oval(self, center, size, tone, sides=14, rows=7):
        x, y, z = center
        rx, ry, rz = size
        points = [(x, y, z - rz)]
        for row in range(1, rows):
            level = -math.pi * 0.5 + math.pi * row / rows
            c, s = math.cos(level), math.sin(level)
            points.extend((x + rx * c * math.cos(a), y + ry * c * math.sin(a), z + rz * s)
                          for a in angles(sides))
        points.append((x, y, z + rz))
        faces = [(0, 1 + (i + 1) % sides, 1 + i) for i in range(sides)]
        for row in range(rows - 2):
            low, high = 1 + row * sides, 1 + (row + 1) * sides
            for i in range(sides):
                j = (i + 1) % sides
                faces.append((low + i, low + j, high + j, high + i))
        faces.extend((len(points) - 1, len(points) - 1 - sides + i,
                      len(points) - 1 - sides + (i + 1) % sides) for i in range(sides))
        self.solid(points, faces, tone, True)

    def panel(self, origin, size, tone, cut=0.012):
        x, y, z = origin
        a, b, height = size[0] * 0.5, size[1] * 0.5, size[2]
        corner = min(cut, a * 0.4, b * 0.4, height * 0.25)
        outline = [(-a + corner, -b), (a - corner, -b), (a, -b + corner), (a, b - corner),
                   (a - corner, b), (-a + corner, b), (-a, b - corner), (-a, -b + corner)]
        rings = [[(x + u * factor, y + v * factor, z + level) for u, v in outline]
                 for level, factor in ((0, 0.91), (corner, 1), (height - corner, 1), (height, 0.91))]
        self.loft(rings, tone, smooth=False)

    def patch(self, points, thickness, tone, smooth=True):
        """Create a closed, thin sheet from a rectangular grid with its own thickness vector."""
        rows, cols = len(points), len(points[0])
        surface = [Vector(p) for row in points for p in row]
        count = len(surface)
        surface.extend(p + Vector(thickness) for p in surface[:])
        faces = []
        for row in range(rows - 1):
            for col in range(cols - 1):
                step = row * cols + col
                quad = [step, step + 1, step + cols + 1, step + cols]
                faces.append(quad)
                faces.append([v + count for v in quad[::-1]])
        edges = [*range(cols), *(row * cols + cols - 1 for row in range(1, rows)),
                 *((rows - 1) * cols + col for col in range(cols - 2, -1, -1)),
                 *(row * cols for row in range(rows - 2, 0, -1))]
        for a, b in zip(edges, edges[1:] + edges[:1]):
            faces.append((a, b, b + count, a + count))
        self.solid(surface, faces, tone, smooth)

    def build(self, name, palette):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.points, [], self.faces)
        mesh.update()
        if mesh.validate(clean_customdata=False):
            raise ValueError(f"{name}: validation repaired authored faces")
        for material in palette:
            mesh.materials.append(material)
        for face, (tone, smooth) in zip(mesh.polygons, self.styles, strict=True):
            face.material_index = tone
            face.use_smooth = smooth
        checks = bmesh.new()
        try:
            checks.from_mesh(mesh)
            bmesh.ops.recalc_face_normals(checks, faces=list(checks.faces))
            assert all(edge.is_manifold for edge in checks.edges), f"{name}: open mesh edges"
            assert all(face.calc_area() > 1e-9 for face in checks.faces), f"{name}: zero-area surface"
            checks.to_mesh(mesh)
        finally:
            checks.free()
        mesh.calc_loop_triangles()
        assert all(triangle.area > 1e-10 for triangle in mesh.loop_triangles), f"{name}: degenerate triangle"
        assert min(v.co.z for v in mesh.vertices) == 0.0, f"{name}: base above or below origin"
        footprint = [v.co for v in mesh.vertices if v.co.z < .10]
        widths = []
        for axis in (0, 1):
            low = min(point[axis] for point in footprint)
            high = max(point[axis] for point in footprint)
            assert abs(high + low) < 0.00002, f"{name}: off-axis base"
            widths.append(high - low)
        assert .97 <= max(widths) <= 1.01, f"{name}: base diameter {max(widths):.3f}"
        assert 1500 <= len(mesh.loop_triangles) <= 5000, f"{name}: {len(mesh.loop_triangles)} triangles"
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        return obj


def angles(count):
    return [TAU * index / count for index in range(count)]


def plinth(parts, stretch=1.0, surface=WOOD, fine=True):
    # Rolled shoulders and the narrow dark groove are actual profile geometry.
    profile = [(0.423, 0), (0.464, 0.008), (0.490, 0.027), (0.496, 0.047),
               (0.486, 0.058), (0.466, 0.060), (0.467, 0.070), (0.486, 0.074),
               (0.477, 0.090), (0.450, 0.106), (0.418, 0.110)]
    tones = [DARK_GOLD, GOLD, GOLD, GOLD, DARK_GOLD, DARK_GOLD, GOLD, GOLD, GOLD, surface]
    if fine:
        parts.turned(profile, lambda row, _col: tones[row], sides=40, stretch=stretch)
        parts.tube([(0.421 * math.cos(a), stretch * 0.421 * math.sin(a), 0.111)
                    for a in angles(40)], 0.0037, GOLD, sides=4, loop=True)
    else:
        profile = [profile[i] for i in (0, 1, 3, 5, 7, 9, 10)]
        parts.turned(profile, lambda row, _col: surface if row == 5 else GOLD,
                     sides=32, stretch=stretch)


def crystal(parts, center, size, faces=4):
    x, y, z = center
    radius, below, above = size
    points = [(x + radius * math.cos(a), y + radius * math.sin(a), z) for a in angles(faces)]
    points += [(x, y, z - below), (x, y, z + above)]
    triangles, tones = [], []
    for i in range(faces):
        j = (i + 1) % faces
        triangles.extend(((faces, j, i), (faces + 1, i, j)))
        tones.extend((DARK_BLUE if i in (1, 2) else CRYSTAL, ICE if i in (2, 3) else CRYSTAL))
    parts.solid(points, triangles, tones)


def notia(parts):
    plinth(parts)
    skirt = []
    for level, radius, fold in [(0.112, .169, .005), (.148, .184, .022), (.20, .179, .022),
                                (.33, .145, .021), (.50, .111, .011), (.68, .088, .003), (.80, .073, .001)]:
        skirt.append([((radius + fold * math.cos(7 * a)) * math.cos(a),
                       .82 * (radius + fold * math.cos(7 * a)) * math.sin(a), level)
                      for a in angles(32)])
    parts.loft(skirt, lambda row, _col: LINEN if row == 0 else IVORY)
    parts.tube([(.156 * math.cos(a), .125 * math.sin(a), .150 + .008 * math.cos(6 * a))
                for a in angles(32)], .005, DARK_GOLD, sides=4, loop=True)

    # The cape opens at the front and lifts to one side along its lower edge.
    def cape(rows, divisions, lining, trim):
        cloth = []
        for z, radius, wave, front in rows:
            row = []
            for i in range(divisions + 1):
                a = -math.pi * 0.5 + front + (TAU - 2 * front) * i / divisions
                r = radius + wave * math.cos(5.0 * a + .4)
                lift = .063 * max(0.0, (.71 - z) / .52) * math.sin(a + .5)
                row.append((r * math.cos(a), .81 * r * math.sin(a) + .025, z + lift))
            cloth.append(row)
        parts.patch(cloth, (0, 0.002, -0.008), lining)
        parts.tube(cloth[0], .006, trim, sides=5, guide=(0, 1, 0))
        for side in (0, -1):
            parts.tube([row[side] for row in cloth], .0064, trim, sides=5, guide=(0, 1, 0))

    cape([(.199, .258, .021, .72), (.26, .237, .020, .63), (.40, .191, .018, .57),
          (.57, .151, .010, .50), (.73, .118, .003, .42), (.83, .068, .002, .49)],
         21, BLUE, DARK_BLUE)
    cape([(.563, .168, .009, .61), (.619, .162, .009, .60), (.718, .139, .004, .51),
          (.791, .099, .002, .44), (.833, .071, .001, .43)], 17, BLUE, GOLD)
    parts.oval((-.006, -.096, .748), (.027, .013, .022), GOLD, sides=10, rows=5)
    parts.oval((-.006, -.106, .751), (.014, .008, .014), CRYSTAL, sides=10, rows=4)

    hood = []
    for y, width, height, z in [(.137, .041, .057, 1.006), (.100, .100, .126, .998),
                                   (.046, .132, .163, .999), (-.030, .134, .169, .995),
                                   (-.102, .122, .156, .994), (-.122, .115, .151, .993),
                                   (-.112, .091, .121, .989), (-.071, .091, .120, .989),
                                   (-.026, .070, .090, .995)]:
        hood.append([(width * math.cos(a) * (1 - .11 * max(0.0, math.sin(a))), y,
                      z + height * math.sin(a) + .045 * max(0.0, math.sin(a))**5)
                     for a in angles(26)])
    parts.loft(hood, lambda row, _col: BLUE if row < 5 else DARK_BLUE)
    parts.tube(hood[4], .005, GOLD, sides=4, loop=True, guide=(0, 1, 0))
    parts.oval((0.008, -.099, .980), (.076, .042, .112), IVORY, sides=18, rows=7)

    start, tip = Vector((.160, -.154, .150)), Vector((.399, -.211, 1.245))
    parts.bar(start, tip, .013, WOOD, sides=10, tip=.010)
    for lo, hi, size in [(.02, .075, .017), (.47, .51, .016), (.91, .955, .017), (.985, 1, .019)]:
        parts.bar(start.lerp(tip, lo), start.lerp(tip, hi), size, GOLD)
    hand = start.lerp(tip, .472)
    parts.tube([(.099, -.007, .731), (.149, -.072, .657), hand + Vector((-.014, .022, .001))],
               [.052, .045, .030], BLUE, sides=10, guide=(0, 1, 0))
    parts.oval(hand, (.029, .025, .035), IVORY, sides=12, rows=6)
    crystal(parts, (tip.x, tip.y, tip.z + .049), (.038, .050, .075), faces=6)


def wheel(parts, x, y, z):
    def ring(radius, offset):
        return [(x + offset, y + radius * math.cos(a), z + radius * math.sin(a)) for a in angles(16)]

    profile = [(.105, -.011), (.111, -.004), (.111, .007), (.102, .012),
               (.086, .008), (.089, -.010)]
    parts.loft([ring(radius, offset) for radius, offset in profile],
               lambda row, _col: GOLD if row in (1, 2, 5) else (DARK_GOLD if row == 0 else WOOD),
               loop=True)
    for a in angles(6):
        parts.bar((x, y + .025 * math.cos(a), z + .025 * math.sin(a)),
                  (x, y + .091 * math.cos(a), z + .091 * math.sin(a)),
                  .009, WOOD, sides=5, tip=.0065, bevel=False)
    parts.bar((x - .020, y, z), (x + .020, y, z), .027, GOLD, sides=10)


def caravan(parts):
    plinth(parts, stretch=1.26, fine=False)
    # Ellipsoid is turned through the major axis to keep the maximum diameter at one unit.
    for i, p in enumerate(parts.points):
        parts.points[i] = (p[0] / 1.26, p[1] / 1.26, p[2])
    for y in (-.022, .274):
        parts.bar((-.215, y, .220), (.215, y, .220), .016, WOOD)
        for x in (-.197, .197):
            wheel(parts, x, y, .220)
    parts.panel((0, .132, .235), (.327, .46, .109), WOOD)
    for x in (-.162, .162):
        for z in (.253, .287, .319):
            parts.panel((x, .132, z), (.020, .454, .028), LEATHER if z == .287 else WOOD, .004)
        parts.panel((x, .132, .341), (.029, .47, .023), GOLD, .004)
        for y in (-.042, .304):
            parts.panel((x * 1.065, y, .241), (.014, .020, .112), DARK_GOLD, .003)
    parts.panel((0, .358, .252), (.336, .021, .106), WOOD)
    parts.panel((0, -.126, .239), (.264, .051, .038), WOOD, .008)
    parts.panel((0, -.136, .277), (.247, .046, .031), LEATHER, .006)

    canvas = []
    canopy_rows = [(-.091, .183, .179), (-.068, .185, .192),
                   (.132, .177, .193), (.274, .183, .190), (.341, .185, .191), (.365, .182, .177)]
    for y, width, rise in canopy_rows:
        canvas.append([(width * math.cos(a), y, .356 + rise * math.sin(a))
                       for a in [math.pi * i / 12 for i in range(13)]])
    parts.patch(canvas, (0, 0, -.008), LINEN)
    for index in (0, 1, 2, 4, 5):
        parts.tube([Vector(point) + Vector((0, 0, .005)) for point in canvas[index]],
                   .0053 if index in (0, 5) else .0048,
                   GOLD if index in (0, 5) else IVORY, sides=4, guide=(0, 1, 0))
    for side in (0, -1):
        parts.tube([row[side] for row in canvas], .006, DARK_GOLD, sides=5)
    # The road beast is short, thick-necked and pulled forward by a real yoke.
    parts.oval((0, -.297, .241), (.083, .130, .075), BLUE, sides=12, rows=6)
    parts.oval((0, -.385, .280), (.064, .064, .086), BLUE, sides=10, rows=5)
    parts.oval((0, -.444, .315), (.060, .066, .058), BLUE, sides=10, rows=5)
    parts.oval((0, -.477, .287), (.047, .039, .037), DARK_BLUE, sides=9, rows=5)
    for side in (-1, 1):
        x = side * .049
        for y in (-.221, -.355):
            parts.tube([(x, y, .213), (x * 1.12, y + .023, .167), (x * 1.22, y + .007, .113)],
                       [.024, .021, .016], BLUE, sides=6, guide=(0, 1, 0))
            parts.oval((x * 1.20, y, .128), (.023, .029, .018), DARK_BLUE, sides=8, rows=3)
        parts.tube([(x * .84, -.443, .346), (x * 1.30, -.433, .378),
                    (x * 1.43, -.408, .406), (x * 1.50, -.390, .418)],
                   [.022, .017, .010, .0032], IVORY, sides=7, guide=(0, 1, 0))
        parts.oval((x * .97, -.475, .329), (.008, .009, .008), DARK_BLUE, sides=6, rows=3)
        parts.bar((side * .105, -.038, .278), (side * .067, -.369, .218), .011, WOOD, sides=6)
    parts.bar((-.090, -.369, .218), (.090, -.369, .218), .010, GOLD)
    parts.tube([(0, -.160, .255), (0, -.142, .220), (0, -.168, .190)],
               [.016, .012, .008], DARK_BLUE, sides=7, guide=(1, 0, 0))


def ship(parts):
    plinth(parts, surface=WATER)
    for level, span, offset, scale in [(.116, .345, .055, .84), (.119, .313, -.04, 1),
                                       (.124, .235, .035, .9)]:
        for phase in (.10, 3.24):
            points = []
            for i in range(12):
                a = phase + 2.65 * i / 11
                r = span + .012 * math.sin(4 * a)
                points.append((r * math.cos(a), r * scale * math.sin(a) + offset,
                               level + .005 * math.sin(5 * a)))
            radii = [.003 + .004 * math.sin(math.pi * i / 11) for i in range(12)]
            parts.tube(points, radii, BLUE if span < .32 else ICE, sides=4)

    # Sheer rises at stem and stern, with a shallow, sealed deck between the rails.
    hull_data = [(.407, .021, .205, .368), (.335, .108, .154, .335),
                 (.264, .140, .136, .320), (.028, .151, .121, .306),
                 (-.165, .129, .139, .318), (-.324, .081, .173, .342),
                 (-.416, .027, .221, .387), (-.452, .009, .271, .410)]
    sections = []
    for y, radius, keel, sheer in hull_data:
        height = sheer - keel
        profile = [(0, 0), (-.49, .10), (-.83, .34), (-1, .70), (-.98, .93),
                   (-.91, 1), (.91, 1), (.98, .93), (1, .70), (.83, .34), (.49, .10)]
        sections.append([(x * radius, y, keel + z * height) for x, z in profile])
    parts.loft(sections, lambda _row, col: (
        LINEN if col == 5 else (LEATHER if col in (2, 4, 6, 8) else WOOD)
    ), smooth=False)
    for edge in (4, 7):
        parts.tube([section[edge] for section in sections], .0068, GOLD, sides=6, guide=(1, 0, 0))
    for edge in (2, 9):
        parts.tube([section[edge] for section in sections], .0045, DARK_GOLD, sides=4, guide=(1, 0, 0))
    parts.panel((0, .295, .321), (.150, .106, .036), LEATHER, .008)
    parts.panel((0, .119, .310), (.071, .068, .018), WOOD, .006)
    for side in (-1, 1):
        for x, y, z in [(.110, .282, .323), (.067, .352, .341), (.015, .397, .365)]:
            parts.bar((side * x, y, z - .007), (side * x, y, z + .035), .0050, LEATHER, sides=5)
        parts.tube([(side * .113, .267, .352), (side * .111, .290, .354),
                    (side * .067, .352, .376), (side * .015, .397, .400)],
                   .006, GOLD, sides=5, guide=(1, 0, 0))

    parts.tube([(0, -.385, .307), (0, -.431, .357), (0, -.451, .415),
                (0, -.485, .464), (0, -.510, .451), (0, -.512, .430)],
               [.012, .015, .014, .014, .009, .004], GOLD, 8, guide=(1, 0, 0))
    parts.oval((0, -.482, .443), (.015, .020, .014), ICE, sides=10, rows=5)

    for y, top, rake in [(.133, 1.343, .032), (-.223, 1.037, -.032)]:
        mast = Vector((0, y, .301))
        summit = Vector((0, y + rake, top))
        parts.bar(mast, summit, .013, WOOD, 10, tip=.008)
        for fraction in (.18, .54, .94):
            parts.bar(mast.lerp(summit, fraction), mast.lerp(summit, fraction + .035),
                      .014 if fraction < .88 else .011, GOLD, sides=8, bevel=False)
        parts.oval(summit, (.017, .017, .015), GOLD, sides=8, rows=4)

    main = []
    for row in range(9):
        v = row / 8
        edge = .241 * (1 - v) + .171 * v + .012 * math.sin(v * math.pi)
        for_wind = []
        for i in range(11):
            u = (i - 5) / 5
            billow = (.098 + .024 * v) * math.sin(math.pi * v)**.75 * (1 - u * u)
            for_wind.append((edge * u + .035 * v, .144 + .064 * u - billow,
                             .526 + .621 * v + (.033 - .019 * v) * u * u - .024 * u))
        main.append(for_wind)
    parts.patch(main, (0, .009, 0), IVORY)
    for row in (main[0], main[-1]):
        parts.tube(row, .0046, LINEN, sides=5, guide=(0, 0, 1))
        start, finish = Vector(row[0]), Vector(row[-1])
        parts.bar(start + (start - finish).normalized() * .025,
                  finish + (finish - start).normalized() * .025, .008, WOOD, sides=8)
    for column in (0, 10):
        parts.tube([row[column] for row in main], .0048, LINEN, sides=5, guide=(0, 1, 0))
    for column in (3, 7):
        parts.tube([Vector(row[column]) + Vector((0, -.005, 0)) for row in main],
                   .0027, LINEN, sides=4, guide=(0, 1, 0))

    foresail = []
    for row in range(8):
        v = row / 7
        span = .299 * (1 - v) + .016 * v
        cloth = []
        for col in range(8):
            u = col / 7
            wind = .070 * math.sin(u * math.pi) * math.sin(v * math.pi)
            cloth.append((-.105 + .109 * v + span * u + wind, -.415 + .178 * v + .112 * u + wind * .4,
                          .460 + .548 * v + .023 * u * (1 - v)))
        foresail.append(cloth)
    parts.patch(foresail, (0, .008, 0), IVORY)
    for col in (0, 7):
        parts.tube([row[col] for row in foresail], .0041, LINEN, sides=5, guide=(0, 1, 0))
    parts.tube(foresail[0], .004, LINEN, sides=5)
    parts.bar((0, -.469, .426), (0, -.246, 1.044), .0038, DARK_GOLD, sides=5)
    for x in (-.135, .135):
        parts.bar((x, .157, .313), (0, .165, 1.30), .0034, DARK_GOLD, sides=5)

    for y, level, size in [(.163, 1.329, .164), (-.252, 1.027, .109)]:
        flag = []
        for i in range(8):
            u = i / 7
            wy = .028 * math.sin(u * math.pi * 1.7)
            center = level - .020 * u
            half = .027 * (1 - .72 * u)
            flag.append([(.005 + size * u, y + wy, center - half),
                         (.005 + size * u, y + wy, center + half)])
        parts.patch(flag, (0, .004, 0), BLUE)


def waypoint(parts):
    # These loops are separate structural rings with open centres and bevelled profiles.
    lower = [(.354, .009), (.368, 0), (.467, 0), (.491, .012), (.499, .034),
             (.481, .056), (.448, .064), (.378, .063), (.359, .051), (.351, .028)]
    parts.turned(lower, lambda row, _col: DARK_GOLD if row in (0, 1, 8) else GOLD,
                 sides=48, loop=True)
    upper = [(.194, .043), (.204, .026), (.307, .026), (.329, .047),
             (.316, .079), (.289, .092), (.219, .090), (.200, .070)]
    parts.loft([[(r * math.cos(a), r * math.sin(a), z) for a in angles(44)] for r, z in upper],
               lambda row, _col: DARK_GOLD if row == 1 else GOLD, loop=True)
    parts.tube([(.426 * math.cos(a), .426 * math.sin(a), .065) for a in angles(48)],
               .0044, DARK_BLUE, sides=5, loop=True)
    for i, angle in enumerate(angles(12)):
        c, s = math.cos(angle), math.sin(angle)
        if i % 3 == 0:
            parts.bar((.290 * c, .290 * s, .057), (.383 * c, .383 * s, .052), .016, DARK_GOLD, sides=6)
            crystal(parts, (.439 * c, .439 * s, .071), (.023, .005, .010))
        else:
            parts.bar((.405 * c, .405 * s, .064), (.442 * c, .442 * s, .065), .0046, GOLD, sides=5)

    crystal(parts, (0, 0, .542), (.187, .315, .348))
    # A tilted armillary circle surrounds the crystal. Its cross-section is a thin beveled band.
    normal = Vector((.50, -.37, .64)).normalized()
    u = normal.cross(Vector((0, 0, 1))).normalized()
    v = normal.cross(u)
    center = Vector((0, 0, .550))
    profile = [(.326, -.010), (.337, -.013), (.349, -.007), (.349, .007),
               (.337, .013), (.326, .010)]
    parts.loft([[center + (u * math.cos(a) + v * math.sin(a)) * radius + normal * thickness
                 for a in angles(52)] for radius, thickness in profile],
               lambda row, _col: DARK_GOLD if row == 3 else GOLD, loop=True)
    for i, a in enumerate(angles(4)):
        anchor = center + (u * math.cos(a) + v * math.sin(a)) * .348
        crystal(parts, (anchor.x, anchor.y, anchor.z), (.021, .023, .023))
        if i == 0:
            parts.oval(anchor, (.026, .024, .013), GOLD, sides=8, rows=4)


def rgba(hex_color):
    def linear(byte):
        shade = int(byte, 16) / 255
        return shade / 12.92 if shade <= .04045 else ((shade + .055) / 1.055) ** 2.4
    return (*[linear(hex_color[i:i + 2]) for i in (0, 2, 4)], 1.0)


def material(name, color, roughness, metal=0.0, polish=0.0, emission=0.0):
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    shade = next(node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shade.inputs["Base Color"].default_value = color
    shade.inputs["Metallic"].default_value = metal
    shade.inputs["Roughness"].default_value = roughness
    shade.inputs["Coat Weight"].default_value = polish
    shade.inputs["Coat Roughness"].default_value = .24
    if emission:
        shade.inputs["Emission Color"].default_value = color
        shade.inputs["Emission Strength"].default_value = emission
    return mat


def make_palette():
    return [
        material("Antique gold · bevels", rgba("C99A55"), .28, .85),
        material("Recessed antique gold", rgba("765332"), .35, .78),
        material("Warm ivory porcelain", rgba("F4E5C9"), .29, .02, .18),
        material("Ivory canvas", rgba("E9D7B9"), .48, .0, .03),
        material("Sea-mist blue glaze", rgba("4D7B9B"), .33, .06, .19),
        material("Indigo glaze · relief", rgba("244660"), .31, .09, .15),
        material("Dark walnut", rgba("4E3226"), .44, .03, .10),
        material("Warm leather and oiled walnut", rgba("714C34"), .46, .04),
        material("Sea-blue crystal", rgba("5EA8C7"), .19, .16, .42, .15),
        material("Ice-blue facets", rgba("A7DAE0"), .24, .16, .34, .085),
        material("Seamist ripple porcelain", rgba("467891"), .28, .12, .27),
    ]


def export_glb(obj):
    for node in bpy.context.selected_objects:
        node.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    destination = MODELS / f"{obj.name}.glb"
    result = bpy.ops.export_scene.gltf(filepath=str(destination), export_format="GLB",
                                       use_selection=True, export_yup=True, export_animations=False)
    assert "FINISHED" in result
    blob = destination.read_bytes()
    tag, version, length, json_length, chunk = struct.unpack_from("<4sIII4s", blob)
    assert (tag, version, length, chunk) == (b"glTF", 2, len(blob), b"JSON")
    data = json.loads(blob[20:20 + json_length])
    assert len(data["nodes"]) == len(data["meshes"]) == 1 and data["nodes"][0]["name"] == obj.name
    for transform in ("translation", "rotation", "scale", "matrix"):
        assert transform not in data["nodes"][0], f"{obj.name}: root must use identity"
    triangles = 0
    for prim in data["meshes"][0]["primitives"]:
        assert prim.get("mode", 4) == 4
        triangles += data["accessors"][prim["indices"]]["count"] // 3
    positions = [data["accessors"][prim["attributes"]["POSITION"]]
                 for prim in data["meshes"][0]["primitives"]]
    low = [min(a["min"][i] for a in positions) for i in range(3)]
    high = [max(a["max"][i] for a in positions) for i in range(3)]
    assert abs(low[1]) < 1e-6, f"{obj.name}: glTF base must touch Y=0"
    minimum_height = .50 if obj.name == "pawn_caravan" else .70
    assert high[1] > minimum_height, f"{obj.name}: expected Y-up dimensions"
    assert triangles == len(obj.data.loop_triangles)
    print(f"{destination.name}: {triangles:,} triangles, {length:,} bytes, "
          f"Y-Up height {high[1]:.3f}, bottom Y={low[1]:.6f}", flush=True)


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def studio():
    scene = bpy.context.scene
    world = bpy.data.worlds.new("Quiet studio")
    if world.node_tree is None:
        world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (.38, .33, .28, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = .28
    scene.world = world
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.004))
    board = material("Walnut tabletop", (.084, .046, .030, 1), .62)
    bpy.context.object.data.materials.append(board)
    tree = board.node_tree
    principled = next(node for node in tree.nodes if node.type == "BSDF_PRINCIPLED")
    coordinates = tree.nodes.new("ShaderNodeTexCoord")
    grain_scale = tree.nodes.new("ShaderNodeVectorMath")
    grain_scale.operation = "MULTIPLY"
    grain_scale.inputs[1].default_value = (2.0, 11.0, 5.0)
    tree.links.new(coordinates.outputs["Object"], grain_scale.inputs[0])
    noise = tree.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 1.1
    noise.inputs["Detail"].default_value = 2.0
    tree.links.new(grain_scale.outputs["Vector"], noise.inputs["Vector"])
    colors = tree.nodes.new("ShaderNodeValToRGB")
    colors.color_ramp.elements[0].color = (.052, .032, .024, 1.0)
    colors.color_ramp.elements[1].color = (.116, .075, .052, 1.0)
    tree.links.new(noise.outputs["Fac"], colors.inputs["Fac"])
    tree.links.new(colors.outputs["Color"], principled.inputs["Base Color"])

    for name, position, power, color, width in [
        ("Warm softbox", (-3.2, -3.6, 5.2), 770, (1.0, .83, .65), 4.2),
        ("Sea-mist fill", (3.5, -2.1, 3.4), 550, (.68, .83, 1.0), 3.6),
        ("Gold edge light", (1.0, 3.0, 3.3), 640, (1.0, .88, .70), 3.1),
    ]:
        light = bpy.data.lights.new(name, "AREA")
        light.energy, light.color, light.size = power, color, width
        obj = bpy.data.objects.new(name, light)
        bpy.context.collection.objects.link(obj)
        obj.location = position
        aim(obj, (0, 0, .36))

    camera = bpy.data.objects.new("Pawn studio camera", bpy.data.cameras.new("Pawn studio camera"))
    bpy.context.collection.objects.link(camera)
    camera.data.type = "ORTHO"
    scene.camera = camera
    scene.view_settings.view_transform = "AgX"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.resolution_percentage = 100
    return scene, camera


def render(scene, path):
    scene.render.filepath = str(path)
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "CYCLES"):
        try:
            scene.render.engine = engine
            if engine == "CYCLES":
                scene.cycles.device = "CPU"
                scene.cycles.samples = 24
                scene.cycles.use_denoising = True
            if "FINISHED" in bpy.ops.render.render(write_still=True):
                print(f"{engine} wrote {path}", flush=True)
                return
        except (RuntimeError, TypeError, ValueError) as error:
            print(f"{engine}: {error}", flush=True)
    raise RuntimeError(f"Could not render {path.name}")


def previews(objects):
    scene, camera = studio()
    for name, x, turn in [
        ("pawn_notia", -1.99, -15), ("pawn_caravan", -.68, 48),
        ("pawn_ship", .69, -27), ("marker_waypoint", 2.01, 13),
    ]:
        objects[name].location.x = x
        objects[name].rotation_euler.z = math.radians(turn)
    camera.location = (0, -5.3, 5.72)
    camera.data.ortho_scale = 5.76
    aim(camera, (0, 0, .42))
    scene.render.resolution_x, scene.render.resolution_y = 2320, 1224
    render(scene, PREVIEWS / "travel_pawns_lineup.png")

    for name in ("pawn_caravan", "marker_waypoint"):
        objects[name].hide_render = True
    objects["pawn_notia"].location.x = -.66
    objects["pawn_notia"].rotation_euler.z = math.radians(-10)
    objects["pawn_ship"].location.x = .66
    objects["pawn_ship"].rotation_euler.z = math.radians(-36)
    camera.location = (0, -4.5, 3.86)
    camera.data.ortho_scale = 2.73
    aim(camera, (0, 0, .56))
    scene.render.resolution_x, scene.render.resolution_y = 2200, 1520
    render(scene, PREVIEWS / "travel_pawns_closeup.png")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MODELS.mkdir(parents=True, exist_ok=True)
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    palette = make_palette()
    objects = {}
    for name, recipe in [("pawn_notia", notia), ("pawn_caravan", caravan),
                         ("pawn_ship", ship), ("marker_waypoint", waypoint)]:
        geometry = Parts()
        recipe(geometry)
        objects[name] = geometry.build(name, palette)
    for obj in objects.values():
        export_glb(obj)
    previews(objects)


if __name__ == "__main__":
    main()
