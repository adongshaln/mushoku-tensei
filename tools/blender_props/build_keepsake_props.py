"""Model the three keepsakes and render the two studio proofs with headless Blender.

Usage: blender --background --python tools/blender_props/build_keepsake_props.py
Blueprint coordinates are X = right, Y = up, Z = the marked front. Models are
centered and transformed before the native Y-up glTF export.
"""

import json
import math
from pathlib import Path
import struct
import sys

import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
PROPS = ROOT / "assets/3d/props"
PREVIEWS = Path(__file__).resolve().parent / "previews"

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(ROOT / "tools"))
from build_travel_pawns import Parts, aim, angles, material, rgba
from build_d20_blender import studio_font

GOLD, GOLD_EDGE, GOLD_DARK, SILVER, SILVER_EDGE, SILVER_DARK, BRONZE, BRONZE_EDGE, BRONZE_DARK, WOOD, WOOD_GRAIN, LEATHER, GLASS, GLASS_ICE, GLASS_DEEP = range(15)


class Keepsake(Parts):
    def __init__(self):
        super().__init__()
        self.normals_by_vertex = {}

    def relief(self, polygon, z, height, tone, edge=None):
        """A physical, rolled-edge stamp on either side of the blueprint."""
        middle = sum((Vector(point) for point in polygon), Vector((0, 0))) / len(polygon)
        sign = 1 if height >= 0 else -1
        rings = []
        for scale, step in ((.95, -.20), (1.0, .26), (.98, .72), (.90, 1.0)):
            rings.append([(*((Vector(point) - middle) * scale + middle), z + abs(height) * step * sign)
                          for point in polygon])
        self.loft(rings, lambda row, _col: tone if edge is None or row == 2 else edge, smooth=False)

    def line(self, points, z, radius, tone, sides=5, loop=False):
        self.tube([(x, y, z) for x, y in points], radius, tone, sides=sides, loop=loop)

    def ring(self, center, radius, z, thickness, tone, segments=60, sides=6, ratios=(1, 1)):
        x, y = center
        path = [(x + radius * ratios[0] * math.cos(a), y + radius * ratios[1] * math.sin(a))
                for a in angles(segments)]
        self.line(path, z, thickness, tone, sides=sides, loop=True)

    def make(self, name, materials, brush_silver=False):
        vertices = [Vector((p[0], -p[2], p[1])) for p in self.points]
        low = Vector(tuple(min(point[i] for point in vertices) for i in range(3)))
        high = Vector(tuple(max(point[i] for point in vertices) for i in range(3)))
        origin = (low + high) / 2
        extent = max(high - low)
        coords = [(vertex - origin) / extent for vertex in vertices]
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(coords, [], self.faces)
        mesh.update()
        assert not mesh.validate(clean_customdata=False), f"{name}: invalid authored mesh"
        for mat in materials:
            mesh.materials.append(mat)
        for face, (tone, smooth) in zip(mesh.polygons, self.styles, strict=True):
            face.material_index = tone
            face.use_smooth = smooth
        check = bmesh.new()
        try:
            check.from_mesh(mesh)
            bmesh.ops.recalc_face_normals(check, faces=list(check.faces))
            assert all(edge.is_manifold for edge in check.edges), f"{name}: open component"
            assert all(face.calc_area() > 1e-10 for face in check.faces), f"{name}: zero face"
            if brush_silver:
                bmesh.ops.triangulate(check, faces=[face for face in check.faces if len(face.verts) > 4])
            check.to_mesh(mesh)
        finally:
            check.free()
        mesh.update()
        if self.normals_by_vertex:
            mesh.normals_split_custom_set([
                self.normals_by_vertex.get(loop.vertex_index, (0, 0, 0)) for loop in mesh.loops
            ])
        if brush_silver:
            add_brush_uvs(mesh)
        mesh.calc_loop_triangles()
        assert all(triangle.area > 1e-11 for triangle in mesh.loop_triangles), f"{name}: vanishing triangle"
        assert 2500 <= len(mesh.loop_triangles) <= 8000, f"{name}: {len(mesh.loop_triangles)} triangles"
        return mesh


def add_brush_uvs(mesh):
    """Supply a texture-free tangent frame for the directional satin silver."""
    uv = mesh.uv_layers.new(name="Brushing direction")
    projections = ((1, 2), (0, 2), (0, 1))
    for face in mesh.polygons:
        axis = max(range(3), key=lambda i: abs(face.normal[i]))
        u, v = projections[axis]
        for i in face.loop_indices:
            position = mesh.vertices[mesh.loops[i].vertex_index].co
            uv.uv[i].vector = (.5 + position[u], .5 + position[v])


def xy(x, y, scale=1, angle=0):
    def transform(p):
        a, b = p
        c, s = math.cos(angle), math.sin(angle)
        return (x + (a*c-b*s)*scale, y + (a*s+b*c)*scale)
    return transform


def star(center, inner, outer, rays, turn=0):
    x, y = center
    return [(x + r * math.cos(a + turn), y + r * math.sin(a + turn))
            for i, a in enumerate(angles(rays * 2)) for r in [outer if i % 2 == 0 else inner]]


def underside(parts, fn, *args):
    # Mirror the relief horizontally and turn it toward the back.
    start = len(parts.points)
    fn(parts, *args)
    for i, p in enumerate(parts.points[start:], start):
        parts.points[i] = (-p[0], p[1], -p[2])


def blade(parts, center, amount, angle, z, tone, dark, luminous):
    place = xy(*center, amount, angle)
    sword = [(-.043, -.181), (-.036, .199), (0, .298), (.036, .199), (.043, -.181)]
    parts.relief([place(p) for p in sword], z, .019, tone, dark)
    parts.relief([place(p) for p in [(-.013, -.170), (0, .260), (.012, -.171)]], z + .016, .005, luminous)
    cross = [(-.121, -.175), (-.103, -.151), (.103, -.151), (.121, -.176),
             (.103, -.198), (-.103, -.197)]
    parts.relief([place(p) for p in cross], z+.007, .016, luminous, dark)
    parts.line([place((0, -.185)), place((0, -.266))], z+.014, .015 * amount, dark, sides=7)
    x, y = place((0, -.277))
    parts.oval((x, y, z+.022), (.019*amount, .018*amount, .011), luminous, sides=10, rows=4)


def rounded_rect(width, height, radius, steps=6):
    points = []
    for corner, (x, y) in enumerate(((width-radius,height-radius), (-width+radius,height-radius),
                                     (-width+radius,-height+radius), (width-radius,-height+radius))):
        for i in range(steps + 1):
            angle = (corner + i/steps) * math.pi/2
            points.append((x + radius * math.cos(angle), y + radius * math.sin(angle)))
    return points


def outline_from_hole(polygon, center):
    def cross(a, b):
        return a[0]*b[1] - a[1]*b[0]

    anchor = Vector(center)
    edges = [Vector(point) - anchor for point in polygon]
    rotations = sorted({round(a % math.tau, 8) for a in angles(28) +
                        [math.atan2(point.y, point.x) for point in edges]})
    surrounds, rays = [], []
    for angle in rotations:
        ray = Vector((math.cos(angle), math.sin(angle)))
        results = []
        for a, b in zip(edges, edges[1:] + edges[:1]):
            edge = b - a
            denominator = cross(ray, edge)
            if abs(denominator) < 1e-9:
                continue
            t = cross(a, edge) / denominator
            u = cross(a, ray) / denominator
            if t > 0 and -1e-6 <= u <= 1+1e-6:
                results.append(t)
        assert results
        surrounds.append(tuple(anchor + ray*min(results)))
        rays.append(ray)
    return surrounds, rays


def badge_border(parts, z, reverse=False):
    contour = [(x, y-.050) for x, y in rounded_rect(.218,.284,.039)]
    parts.line(contour, z+.003, .0045, BRONZE_DARK, sides=5, loop=True)
    fine = [(x*.958,y*.953) for x,y in contour]
    parts.line(fine, z+.0068, .0030, BRONZE_EDGE, sides=4, loop=True)
    for x in (-.185,.185):
        for y in (-.309,.207):
            parts.relief(star((x,y), .016,.021,4), z+.001,.008,BRONZE_EDGE)
            if not reverse:
                parts.oval((x,y,z+.009),(.013,.013,.009),BRONZE,sides=10,rows=4)


def badge_front(parts, z):
    badge_border(parts, z)
    parts.oval((0,.073,z+.0005),(.140,.151,.0105),BRONZE_DARK,sides=36,rows=5)
    parts.ring((0,.073),.144,z+.002,.0032,BRONZE_EDGE,segments=46,sides=4,ratios=(1,1.076))
    serif = [(-.47, -.65), (-.47, -.54), (-.34, -.50), (-.31, -.43), (-.31, .43),
             (-.34, .49), (-.47, .54), (-.47, .65), (.46, .65), (.46, .35),
             (.35, .35), (.27, .49), (.20, .50), (-.081, .50), (-.081, .07),
             (.158, .07), (.207, .12), (.225, .215), (.317, .215), (.317, -.217),
             (.225, -.217), (.195, -.11), (.151, -.084), (-.081, -.084), (-.081, -.44),
             (-.049, -.51), (.097, -.55), (.097, -.65)]
    letter = [xy(-.002,.072,.182)(point) for point in serif]
    parts.relief(letter, z+.007, .024, BRONZE_EDGE, BRONZE_DARK)
    for index in range(3):
        baseline = -.135 - .044 * index
        left = -.149 + .021 * index
        path = [(x, baseline + .010 * math.sin(i*.78+index*.72) * math.sin(math.pi*i/25))
                for i in range(26) for x in [left - 2*left*i/25]]
        parts.line(path,z+.0024,.0030,BRONZE_DARK,sides=5)
        parts.line([(x,y+.006) for x,y in path],z+.0017,.0017,BRONZE_EDGE,sides=4)


def guild_staff(parts, z):
    pose = xy(.005,-.049,.63,-.71)
    line = [pose((-.006,-.253)), pose((.008,-.123)), pose((-.006,.077)), pose((0,.218))]
    parts.line(line,z+.013,.009,BRONZE_EDGE,sides=7)
    cap = pose((0,.226))
    parts.relief(star(cap,.016,.038,4,.75),z+.011,.012,BRONZE_EDGE,BRONZE_DARK)
    parts.ring(cap,.049,z+.008,.0037,BRONZE,segments=22,sides=5)


def badge_reverse(parts,z):
    badge_border(parts,z,True)
    center = (0,-.047)
    parts.ring(center,.178,z+.005,.007,BRONZE_EDGE,segments=46,sides=5)
    parts.ring(center,.146,z+.003,.0035,BRONZE_DARK,segments=44,sides=4)
    for i, angle in enumerate(angles(20)):
        if i % 5 == 0:
            x,y = .163*math.cos(angle), center[1]+.163*math.sin(angle)
            parts.relief(star((x,y),.006,.014,4,angle),z+.011,.004,BRONZE_EDGE)
    guild_staff(parts,z+.006)
    blade(parts, (0,-.043), .56, .80, z+.021, BRONZE_EDGE, BRONZE_DARK, BRONZE_EDGE)


def guild_card(parts):
    outline = rounded_rect(.282,.435,.071)
    hole = (0,.326)
    shell, rays = outline_from_hole(outline,hole)
    outer, inner = [], []
    for scale, z in ((.954,.040),(.992,.027),(1.0,.006),(1.0,-.006),(.992,-.028),(.954,-.040)):
        outer.append([(x*scale,y*scale,z) for x,y in shell])
    for radius,z in ((.054,-.040),(.046,-.032),(.044,-.023),(.044,.024),(.046,.033),(.054,.040)):
        inner.append([(hole[0]+d.x*radius,hole[1]+d.y*radius,z) for d in rays])
    parts.loft(outer+inner, lambda row,_col: BRONZE_EDGE if row in (0,4,6,10) else
               (BRONZE_DARK if row in (2,7,8) else BRONZE), loop=True)
    # The broad faces retain the plate's continuous curvature at the rim and eyelet.
    width = len(shell)
    for row, side in ((0,1), (5,-1), (6,-1), (11,1)):
        for i in range(row * width, (row + 1) * width):
            x = parts.points[i][0]
            parts.normals_by_vertex[i] = Vector((.032 * side * x / .283**2, -side, 0)).normalized()
    badge_front(parts,.040)
    underside(parts,badge_reverse,.040)
    parts.ring(hole,.058,.042,.005,BRONZE_EDGE,segments=28,sides=5)
    parts.ring(hole,.058,-.042,.005,BRONZE_EDGE,segments=28,sides=5)
    radius = .074
    hanger = [(math.sin(1.01)*math.cos(a)*radius, .402+radius*math.sin(a),
               .006 + math.cos(1.01)*math.cos(a)*radius) for a in angles(36)]
    parts.tube(hanger,.012,BRONZE_EDGE,sides=7,loop=True,guide=(1,0,0))
    for i,p in enumerate(parts.points):
        x,y,z=p
        bend=.016*max(0,1-(x/.283)**2)
        parts.points[i]=(x,y,z+bend)


def drop(a, width=.242, height=.342):
    c,s=math.cos(a),math.sin(a)
    return (width*s*(1-.38*c), height*c)


def twist_frame(parts):
    center = [Vector((*drop(a), 0)) for a in angles(96)]
    backing = [Vector((*drop(a), 0)) for a in angles(60)]
    parts.tube(backing,.0185,SILVER_DARK,sides=7,loop=True)
    for shift, tone in ((0,SILVER_EDGE),(math.pi,SILVER)):
        rope = []
        for i, point in enumerate(center):
            tangent = (center[(i+1)%len(center)] - center[i-1]).normalized()
            lateral = tangent.cross(Vector((0,0,1)))
            angle = math.tau * 13 * i / len(center) + shift
            rope.append(point + .014*(lateral*math.cos(angle) + Vector((0,0,1))*math.sin(angle)))
        parts.tube(rope,.0105,tone,sides=6,loop=True)


def drop_gem(parts, center=(0,-.032), size=(.130,.205), profile=(-.094,.100)):
    corners = [drop(a,*size) for a in angles(12)]
    center_x,center_y=center
    back,front=profile
    shape=[(.29,back),(.55,back*.81),(.94,back*.25),(1.0,0),
           (.96,front*.23),(.65,front*.80),(.44,front)]
    rings=[[(center_x+x*factor,center_y+y*factor,z)for x,y in corners]for factor,z in shape]
    parts.loft(rings,lambda row,column: GLASS if (row+column)%4 in (1,2) else
               (GLASS_DEEP if (row+column)%4==3 else GLASS_ICE),smooth=False)


def charm(parts):
    twist_frame(parts)
    inner = [drop(a,.181,.267) for a in angles(50)]
    for z,tone in ((-.083,SILVER_DARK),(.007,SILVER),(.053,SILVER_EDGE)):
        parts.line(inner,z,.0125,tone,sides=6,loop=True)
    for a in (1.37,2.71,3.65,4.91):
        x,y = drop(a)
        xx,yy = drop(a,.183,.269)
        parts.bar((xx,yy,-.042),(x*.966,y*.972,-.007),.013,SILVER,sides=7)
    drop_gem(parts,profile=(-.091,.106))

    for side in (-1,1):
        leaf = [(side*x,y,z) for x,y,z in [(.201,.064,.009),(.188,.027,.066),(.148,-.032,.100),
                    (.145,-.088,.106),(.177,-.148,.073),(.204,-.158,.032)]]
        parts.tube(leaf,[.009,.0148,.018,.016,.0085,.0023],SILVER_EDGE,sides=9,guide=(0,1,0))
        parts.tube([p for p in leaf[1:-1]],[.0045,.0045,.005,.0024],SILVER_DARK,sides=5,guide=(0,0,1))

    flower = []
    for a in angles(80):
        r = .054 + .103 * (0.5 + 0.5 * math.cos(6*a))**1.38
        flower.append((r*math.cos(a),-.031+r*1.14*math.sin(a),-.101-.014*math.sin(a)**2))
    parts.tube(flower,.0082,SILVER_EDGE,sides=6,loop=True)
    parts.ring((0,-.025),.046,-.117,.0065,SILVER,segments=34,sides=5)
    for a in angles(6):
        x,y=.155*math.cos(a),-.031+.155*1.14*math.sin(a)
        outer_x,outer_y=drop(math.atan2(math.cos(a),math.sin(a)),.176,.266)
        parts.tube([(x,y,-.103),((x+outer_x)*.5,(y+outer_y)*.5,-.080),(outer_x,outer_y,-.078)],
                   [.0058,.0068,.008],SILVER,sides=5)

    for side in (-1,1):
        spine=[(side*.025*math.cos(i/13*.9),.312+.046*i/13,.023*math.sin(i/13*math.tau))
               for i in range(14)]
        parts.tube(spine,.011,SILVER,sides=6,guide=(1,0,0))
    hanger=[(.055*math.cos(a)*.78,.398+.055*math.sin(a),.055*math.cos(a)*.62)
            for a in angles(40)]
    parts.tube(hanger,.011,SILVER_EDGE,sides=7,loop=True,guide=(0,1,1))


def shaft_center(y):
    return Vector((.046 * math.sin((y + .15) * 5) - .019 * y, y,
                   .010 * math.cos(6 * y + 1.2)))


def shaft_radius(y):
    return .035 + .004 * math.cos((y + .38) * 6) - .005 * y


def shaft_skin(y, angle, offset=0):
    radius = shaft_radius(y) * (1 + .043 * math.sin(5 * angle + 7 * y)) + offset
    return shaft_center(y) + Vector((radius * math.cos(angle), 0, .89 * radius * math.sin(angle)))


def shaft_metal(parts, profile, dark=GOLD_DARK, middle=GOLD, edge=GOLD_EDGE):
    rings = [[shaft_center(y) + Vector((radius * math.cos(a), 0, .91 * radius * math.sin(a)))
              for a in angles(20)] for y, radius in profile]
    parts.loft(rings, lambda row, _col: (dark, middle, edge, middle)[row % 4])


def wand(parts):
    rows = [[shaft_skin(-.431 + .751 * i / 22, a) for a in angles(18)] for i in range(23)]
    parts.loft(rows, WOOD)
    for i in range(5):
        start = -.348 + .056 * (i % 3)
        path = [shaft_skin(start + .532*t/17, i * 1.21 + .48 * math.sin(t/17 * 3), -.0005)
                for t in range(18)]
        parts.tube(path, [.0006 + .0018 * math.sin(math.pi*t/17) for t in range(18)],
                   WOOD_GRAIN, sides=5, guide=(0,0,1))

    shaft_metal(parts, [(-.476,.008),(-.471,.014),(-.458,.021),(-.420,.031),(-.394,.037),
                        (-.386,.043),(-.376,.043),(-.370,.039),(-.367,.036)])
    # The rims of the two low-profile leather turns follow the same spiral as the lapped strip.
    leather_profile = [(-.012,.001),(-.012,.004),(-.009,.007),(.009,.007),
                       (.012,.004),(.012,.001),(.008,-.002),(-.008,-.002)]
    leather_rows = []
    seams = [[], []]
    for i in range(51):
        angle = i / 50 * math.tau * 2
        y = -.245 + i / 50 * .100
        leather_rows.append([shaft_skin(y + jump, angle, offset) for jump,offset in leather_profile])
        for side, seam in zip((-1,1), seams, strict=True):
            seam.append(shaft_skin(y + side * .009, angle, .0062))
    parts.loft(leather_rows, LEATHER)
    for seam in seams:
        parts.tube(seam, .0017, WOOD_GRAIN, sides=5)

    for y, size in ((.197,.041),(.233,.046),(.272,.052)):
        shaft_metal(parts, [(y-.010,size*.82),(y-.008,size*.97),(y-.004,size),
                            (y+.006,size),(y+.009,size*.93),(y+.011,size*.82)])
    shaft_metal(parts, [(.275,.033),(.286,.043),(.308,.053),(.326,.052),(.333,.039)])
    gem_x = shaft_center(.32).x
    drop_gem(parts, center=(gem_x,.394), size=(.059,.106), profile=(-.060,.071))
    for side in (-1,1):
        prong = [(gem_x+side*x,y,side*z) for x,y,z in [
            (.023,.286,-.013),(.044,.323,.002),(.061,.352,.021),(.070,.381,.033),
            (.066,.409,.043),(.055,.436,.049),(.034,.455,.046),(.015,.463,.029)]]
        radii = [.021,.022,.019,.016,.014,.010,.007,.0036]
        parts.tube(prong,radii,GOLD,sides=12,guide=(0,1,0))
        accent = [(x+side*r*.64,y,z+side*r*.64) for (x,y,z),r in zip(prong,radii,strict=True)]
        parts.tube(accent,[.0031,.0040,.0043,.004,.0035,.0028,.002,.0009],
                   GOLD_EDGE,sides=7,guide=(0,1,0))
    for i in range(4):
        angle = math.tau*i/4 + .4
        parts.oval((gem_x+.047*math.cos(angle),.314,.044*math.sin(angle)),
                   (.009,.010,.009),GOLD_EDGE,sides=8,rows=4)


def make_palette():
    definitions = [
        ("Asura · struck gold", "C79752", .24, .90, .08),
        ("Gold · polished bevel", "ECD195", .23, .90, .10),
        ("Gold · recessed die", "88623C", .33, .88, .03),
        ("Asura · brushed silver", "B9C5CC", .28, .88, .05),
        ("Silver · polished lip", "E9E7DE", .23, .89, .10),
        ("Silver · old patina", "74848D", .39, .82, .02),
        ("Guild bronze", "926D48", .32, .85, .06),
        ("Bronze · burnished bevel", "CEA476", .28, .86, .10),
        ("Bronze · deep engraving", "5B3C2C", .40, .81, .03),
        ("Walnut · oiled", "41271F", .43, .02, .08),
        ("Walnut · raised grain", "533226", .45, .02, .08),
        ("Leather · wrapped", "71452F", .51, .00, .05),
        ("Sea-mist crystal", "4A7FA3", .17, .04, .20),
        ("Sea-mist crystal · ice facets", "87B9CC", .15, .03, .23),
        ("Sea-mist crystal · deep facets", "336A8D", .21, .06, .19),
    ]
    result = [material(name, rgba(hex_code), roughness, metallic, coat)
              for name, hex_code, roughness, metallic, coat in definitions]
    for i, strength in ((SILVER,.26),(SILVER_EDGE,.12),(SILVER_DARK,.19)):
        shader = next(node for node in result[i].node_tree.nodes if node.type == "BSDF_PRINCIPLED")
        shader.inputs["Anisotropic"].default_value = strength
    for i, weight in ((GLASS,.59),(GLASS_ICE,.72),(GLASS_DEEP,.48)):
        shader = next(node for node in result[i].node_tree.nodes if node.type == "BSDF_PRINCIPLED")
        shader.inputs["Transmission Weight"].default_value = weight
        shader.inputs["IOR"].default_value = 1.44
    return result


ASSETS = (
    ("guild_card_f", "Guild card F", guild_card),
    ("charm_old_silver", "Old silver charm", charm),
    ("wand_apprentice_water", "Apprentice wand", wand),
)


def inspect_glb(path, mesh):
    data = path.read_bytes()
    magic, version, length, json_size, json_tag = struct.unpack_from("<4sIII4s", data)
    assert (magic, version, length, json_tag) == (b"glTF", 2, len(data), b"JSON"), path
    doc = json.loads(data[20:20 + json_size])
    assert len(doc["meshes"]) == 1 and len(doc["nodes"]) == 1, path
    assert "uri" not in doc["buffers"][0], path
    primitives = doc["meshes"][0]["primitives"]
    assert all(p.get("mode", 4) == 4 for p in primitives), path
    accessors = doc["accessors"]
    triangles = sum(accessors[p["indices"]]["count"] for p in primitives) // 3
    assert triangles == len(mesh.loop_triangles), (path, triangles, len(mesh.loop_triangles))
    bounds = [accessors[p["attributes"]["POSITION"]] for p in primitives]
    lower = [min(a["min"][i] for a in bounds) for i in range(3)]
    upper = [max(a["max"][i] for a in bounds) for i in range(3)]
    assert all(abs(a + b) < 1e-6 for a,b in zip(lower,upper,strict=True)), path
    assert abs(max(b - a for a,b in zip(lower,upper,strict=True)) - 1.0) < 1e-6, path
    if path.stem in {"charm_old_silver", "wand_apprentice_water"}:
        assert "KHR_materials_transmission" in doc["extensionsUsed"], path
    if path.stem == "charm_old_silver":
        assert "KHR_materials_anisotropy" in doc["extensionsUsed"], path
        assert all("TANGENT" in primitive["attributes"] for primitive in primitives), path
    return triangles, len(data)


def build_assets(palette):
    results = {}
    for stem, label, sculpt in ASSETS:
        parts = Keepsake()
        sculpt(parts)
        brush_silver = stem == "charm_old_silver"
        mesh = parts.make(stem, palette, brush_silver)
        obj = bpy.data.objects.new(label, mesh)
        bpy.context.collection.objects.link(obj)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        path = PROPS / f"{stem}.glb"
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB",
                                  use_selection=True, export_yup=True, export_animations=False,
                                  export_tangents=brush_silver)
        triangles, size = inspect_glb(path, mesh)
        print(f"KEEPSAKE {stem} {triangles} triangles {size} bytes", flush=True)
        bpy.data.objects.remove(obj, do_unlink=True)
        results[stem] = mesh
    return results


def panel_paper():
    mat = material("Studio · warm vellum", rgba("654D42"), .70)
    nodes = mat.node_tree.nodes
    shader = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 165
    noise.inputs["Detail"].default_value = 2
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = .16
    ramp.color_ramp.elements[0].color = rgba("594139")
    ramp.color_ramp.elements[1].position = .84
    ramp.color_ramp.elements[1].color = rgba("795749")
    mat.node_tree.links.new(noise.outputs["Fac"], ramp.inputs[0])
    mat.node_tree.links.new(ramp.outputs[0], shader.inputs["Base Color"])
    return mat


def backdrop(scene, mat):
    mesh = bpy.data.meshes.new("Studio backing")
    mesh.from_pydata([(-20,1.25,-20),(20,1.25,-20),(20,1.25,20),(-20,1.25,20)],
                     [], [(0,1,2,3)])
    mesh.materials.append(mat)
    obj = bpy.data.objects.new("Vellum studio backing", mesh)
    scene.collection.objects.link(obj)


def studio(name, width, height, view, paper):
    scene = bpy.data.scenes.new(name)
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 7
    scene.cycles.transmission_bounces = 5
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = .12
    world = bpy.data.worlds.new(name)
    if world.node_tree is None:
        world.use_nodes = True
    glow = world.node_tree.nodes.get("Background")
    glow.inputs["Color"].default_value = (.36,.42,.53,1)
    glow.inputs["Strength"].default_value = .31
    scene.world = world

    camera = bpy.data.objects.new("Portrait lens", bpy.data.cameras.new("Portrait lens"))
    scene.collection.objects.link(camera)
    camera.location = (0,-14,.18)
    aim(camera, (0,0,0))
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = view
    scene.camera = camera
    backdrop(scene, paper)
    lighting = [
        ("Warm overhead softbox",(-4.2,-5.8,5.4),1900,(1,.83,.68),5.2,3.0),
        ("Blue studio fill",(4.0,-3.6,1.1),930,(.69,.84,1),3.5,5.5),
        ("Parchment bounce",(.5,-4.5,-4.0),780,(1,.93,.82),6.0,2.1),
    ]
    for title,location,power,color,w,h in lighting:
        light = bpy.data.lights.new(title,"AREA")
        light.shape = "RECTANGLE"
        light.size = w
        light.size_y = h
        light.energy = power
        light.color = color
        obj = bpy.data.objects.new(title,light)
        scene.collection.objects.link(obj)
        obj.location = location
        aim(obj, (0,0,0))
    return scene


def place(scene, meshes, stem, x, z, scale, yaw, tilt):
    obj = bpy.data.objects.new(stem, meshes[stem])
    scene.collection.objects.link(obj)
    obj.location = (x,0,z)
    obj.scale = (scale,) * 3
    obj.rotation_euler = (math.radians(tilt),0,math.radians(yaw))


def caption(scene, font, ink, name, x, z, size):
    curve = bpy.data.curves.new(name, "FONT")
    curve.font = font
    curve.body = name
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    curve.size = size
    curve.space_character = 1.11
    curve.materials.append(ink)
    obj = bpy.data.objects.new(name, curve)
    scene.collection.objects.link(obj)
    obj.rotation_euler.x = math.pi / 2
    obj.location = (x,-.03,z)


def render(scene, path):
    print(f"STUDIO {path.name}", flush=True)
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True, scene=scene.name)


def render_previews(meshes):
    paper = panel_paper()
    ink = material("Studio · pale ink", rgba("F1DCC5"), .62, emission=.32)
    font = studio_font()
    lineup = studio("Guild, Migurd and apprentice keepsakes", 1560, 750, 4.45, paper)
    for i, ((stem,label,_),yaw,tilt) in enumerate(zip(ASSETS, [11,-13,10], [5,3,2], strict=True)):
        x = (i - 1) * 1.39
        place(lineup, meshes, stem, x,.13,1.17,yaw,tilt)
        caption(lineup,font,ink,label,x,-.715,.127)
    render(lineup, PREVIEWS / "keepsakes_lineup.png")

    details = studio("Keepsake relief & crystal studies", 2400, 1536, 6.60, paper)
    views = [
        ("guild_card_f","Guild card · obverse",-2.47,.95,1.52,-9,3,-.005),
        ("guild_card_f","Guild seal · reverse",-.89,.95,1.52,191,4,-.005),
        ("charm_old_silver","Silver charm · obverse",-2.47,-1.03,1.51,-12,-6,-1.98),
        ("charm_old_silver","Silver tracery · reverse",-.89,-1.03,1.51,194,-5,-1.98),
        ("wand_apprentice_water","Water crystal",1.62,-1.29,5.55,-14,3,1.91),
    ]
    for stem,label,x,z,scale,yaw,tilt,text_z in views:
        place(details,meshes,stem,x,z,scale,yaw,tilt)
        caption(details,font,ink,label,x,text_z,.115)
    render(details, PREVIEWS / "keepsakes_closeup_both_sides.png")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    PROPS.mkdir(parents=True, exist_ok=True)
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    render_previews(build_assets(make_palette()))


if __name__ == "__main__":
    main()
