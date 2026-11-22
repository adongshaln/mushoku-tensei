"""Sculpt and photograph the four Demon Continent coins as closed solids.

Run: blender --background --python tools/blender_props/build_demon_currency.py
The working plane is XY. GLB delivery uses Y-up with the obverse facing +Z.
All pigment, roughness and microrelief are baked into the GLBs.
"""

from dataclasses import dataclass
import json
import math
from pathlib import Path
import struct

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector
from mathutils.geometry import delaunay_2d_cdt
import numpy as np


ROOT = Path(__file__).resolve().parents[2]
PROPS = ROOT / "assets/3d/props"
PREVIEWS = Path(__file__).resolve().parent / "previews"
ATLAS_SIZE = 1024
FACE_SPAN = 1.10
FRONT_TILE = (8, 520, 496, 496)
BACK_TILE = (520, 520, 496, 496)
RIM_TILE = (8, 300, 1008, 192)
BORE_TILE = (8, 124, 512, 144)
BORE_CENTER = (.022, -.018)


@dataclass(frozen=True)
class Coin:
    kind: str
    name: str
    english: str
    diameter: float
    thickness: float
    aspect: float
    irregularity: float
    bevel: float
    metallic: float
    seed: int
    sampling: tuple[float, float]
    hammer_depth: float
    hammer_count: int

    @property
    def stem(self):
        return f"coin_demon_{self.kind}"


COINS = (
    Coin("green_ore", "绿矿钱", "Green ore", .940, .168, .970, .049, .087, .08, 142,
         (.045, .035), .0029, 11),
    Coin("iron", "铁钱", "Forged iron", .879, .141, .971, .063, .064, .80, 216,
         (.032, .032), .0122, 24),
    Coin("scrap_iron", "屑铁钱", "Scrap iron", .808, .086, .814, .108, .056, .72, 371,
         (.032, .030), .0089, 26),
    Coin("stone", "石钱", "Stone", .765, .113, .900, .078, .086, .0, 481,
         (.030, .030), .0049, 18),
)


@dataclass(frozen=True)
class Cut:
    points: tuple[tuple[float, float], ...]
    width: float
    depth: float


def ellipse_stroke(center, radii, wiggle, phase, sweep=(0, math.tau)):
    cx, cy = center
    start, end = sweep
    return tuple(
        (cx + (radii[0] + wobble) * math.cos(a), cy + (radii[1] + wobble) * math.sin(a))
        for a in np.linspace(start, end, math.ceil((end - start) * 10) + 1)
        for wobble in (wiggle * (.68 * math.sin(3*a + phase) + .32 * math.cos(7*a - phase)),)
    )


def engravings(coin, rear):
    if coin.kind == "green_ore":
        if rear:
            return (
                Cut(((-.093, -.015), (-.025, .072), (.081, .033), (.052, -.044),
                     (-.023, -.089), (-.078, -.054)), .018, .0128),
                Cut(((-.035, -.028), (.030, .015)), .010, .0087),
            )
        return (
            Cut(ellipse_stroke((-.011, .008), (.342, .320), .007, 1.8), .0125, .0126),
            Cut(ellipse_stroke((-.008, .010), (.252, .239), .0055, 3.1), .0115, .0113),
            Cut(((-.145, -.075), (-.085, .061), (-.012, .128), (.122, .068),
                 (.058, .017), (.012, .042), (-.056, -.071)), .0150, .0138),
            Cut(((.136, -.041), (.064, -.123), (-.036, -.132), (-.003, -.071)),
                .0130, .0105),
        )
    if coin.kind == "iron":
        if rear:
            return (Cut(ellipse_stroke((.008, -.009), (.368, .340), .013, 2.2, (.16, 6.18)),
                        .0135, .0102),)
        return (
            Cut(((-.178, -.013), (-.022, .163), (.165, .027), (.028, -.161),
                 (-.178, -.013)), .019, .0145),
            Cut(((-.093, .007), (.002, .012), (.088, .035)), .0145, .0112),
            Cut(((.017, -.078), (.008, .004), (-.010, .089)), .015, .0118),
        )
    if coin.kind == "scrap_iron" and not rear:
        return (
            Cut(((-.081, .054), (-.027, -.065), (.059, -.033)), .018, .012),
            Cut(((-.026, -.003), (.041, .044)), .011, .0075),
        )
    return ()


def ease(low, high, value):
    t = np.clip((value - low) / (high - low), 0, 1)
    return t*t*(3 - 2*t)


def make_outline(coin):
    """Uneven grind flats and a few worn-away chips in a closed perimeter."""
    rng = np.random.default_rng(coin.seed)
    count = 18 if coin.kind == "green_ore" else 22
    knots = np.arange(count)*math.tau/count
    knots[1:] += rng.uniform(-.068, .068, count-1)
    shape = rng.uniform(-.75, .74, count)
    angles = np.arange(72)*math.tau/72
    wear = np.interp(angles, knots, shape, period=math.tau)
    for angle, depth, width in zip(rng.uniform(0, math.tau, 4),
                                  rng.uniform(.30, .74, 4),
                                  rng.uniform(.09, .18, 4), strict=True):
        distance = (angles - angle + math.pi) % math.tau - math.pi
        wear -= depth * np.exp(-((distance / width)**2))
    variation = (wear + .53*np.sin(3*angles + coin.seed*.16)
                 + .28*np.cos(5*angles + coin.seed*.42))
    radius = .498 * (1 + coin.irregularity*variation)
    x = radius*np.cos(angles)
    y = coin.aspect*radius*np.sin(angles)
    if coin.kind == "scrap_iron":
        y += .12*x + .018*np.cos(4*angles + .5)
    if coin.kind == "stone":
        x += .021*np.sin(2*angles + .4)
    return np.column_stack((x, y))


def circle_edges(start, count):
    return [(start+i, start+(i+1) % count) for i in range(count)]


def bore_outline(depth_fraction):
    angles = np.arange(28)*math.tau/28
    # A tapered, off-axis opening shaped by drilling inward from both faces.
    radius = (.052 + .029 * abs(depth_fraction)**1.30
              + .004*np.sin(3*angles - .4) + .0028*np.cos(5*angles + .2))
    x = BORE_CENTER[0] + radius*np.cos(angles) + .009*depth_fraction
    y = BORE_CENTER[1] + .91*radius*np.sin(angles) - .006*depth_fraction
    return np.column_stack((x, y))


def contains(points, polygon):
    """Crossing count with all query positions evaluated together."""
    x, y = points.T
    inside = np.zeros(len(points), dtype=bool)
    for (ax, ay), (bx, by) in zip(polygon, np.roll(polygon, -1, axis=0), strict=True):
        crossing = (ay > y) != (by > y)
        if by != ay:
            inside ^= crossing & (x < (bx-ax)*(y-ay)/(by-ay) + ax)
    return inside


def segment_distance_sq(x, y, start, end):
    ax, ay = start
    u, v = end[0] - ax, end[1] - ay
    t = np.clip(((x-ax)*u + (y-ay)*v) / (u*u + v*v), 0, 1)
    return (x-ax-t*u)**2 + (y-ay-t*v)**2


def cut_field(x, y, cuts):
    field = np.zeros(np.broadcast_shapes(np.shape(x), np.shape(y)), dtype=np.float32)
    for cut in cuts:
        distance_sq = np.full_like(field, np.inf)
        for start, end in zip(cut.points[:-1], cut.points[1:], strict=True):
            np.minimum(distance_sq, segment_distance_sq(x, y, start, end), out=distance_sq)
        dist = np.sqrt(distance_sq)/cut.width
        tool_profile = 1 - ease(.18, 1.05, dist)
        field = np.maximum(field, cut.depth * tool_profile)
    return field


def cut_samples(cut):
    path = np.array(cut.points)
    lengths = np.linalg.norm(np.diff(path, axis=0), axis=1)
    distance = np.concatenate(([0.], np.cumsum(lengths)))
    marks = np.linspace(0, distance[-1], math.ceil(distance[-1]/.035) + 1)
    center = np.column_stack([np.interp(marks, distance, path[:, i]) for i in range(2)])
    tangents = np.gradient(center, axis=0)
    normal = np.column_stack((-tangents[:, 1], tangents[:, 0]))
    normal /= np.linalg.norm(normal, axis=1, keepdims=True)
    for offset in (0, -.54, .54, -1.14, 1.14):
        yield from center + normal*(offset * cut.width)


class CoinFace:
    def __init__(self, coin, rear):
        self.coin = coin
        self.rear = rear
        self.cuts = engravings(coin, rear)
        rng = np.random.default_rng(coin.seed + 37 * rear)
        self.dents = []
        for i in range(coin.hammer_count):
            a = rng.uniform(0, math.tau)
            radius = .421 * math.sqrt(rng.random())
            x, y = radius*math.cos(a), radius*math.sin(a)*coin.aspect
            size = rng.uniform(.045, .091) if i < 9 else rng.uniform(.021, .049)
            self.dents.append((x, y, size, size*rng.uniform(.57, .94), rng.uniform(0, math.tau),
                               coin.hammer_depth*rng.uniform(.31, 1.0)))

    def dents_field(self, x, y):
        result = np.zeros(np.broadcast_shapes(np.shape(x), np.shape(y)), np.float32)
        for cx, cy, rx, ry, angle, depth in self.dents:
            qx, qy = x-cx, y-cy
            u = (qx*np.cos(angle) + qy*np.sin(angle))/rx
            v = (-qx*np.sin(angle) + qy*np.cos(angle))/ry
            result -= depth * np.maximum(0, 1-u*u-v*v)**1.28
        return result

    def top_height(self, x, y):
        """Distance from the mid-plane, before centering the solid."""
        coin = self.coin
        radius = np.hypot(x, y / coin.aspect)
        orientation = (self.rear * 1.91 + coin.seed * .137)
        wave = (np.sin(x*12.0 + y*5.0 + orientation)
                + .69*np.cos(y*17 - x*12 + orientation)
                + .27*np.sin(x*48 - y*17 + orientation))
        scale = {"green_ore": .0016, "iron": .0020, "scrap_iron": .0049, "stone": .0042}
        height = coin.thickness * .5 + scale[coin.kind]*wave
        if coin.kind == "iron":
            height -= .0108 * (1 - ease(.22, .432, radius))
        if coin.kind == "stone":
            drilled = np.hypot(x-BORE_CENTER[0], y-BORE_CENTER[1])
            height -= .0065 * (1 - ease(.075, .137, drilled))
        return height + self.dents_field(x, y) - cut_field(x, y, self.cuts)


def interior_samples(face, cap, hole):
    coin = face.coin
    rng = np.random.default_rng(coin.seed + 809 + face.rear)
    stride = coin.sampling[face.rear]
    coordinates = np.arange(-.505, .522, stride)
    x, y = np.meshgrid(coordinates, coordinates)
    grid = np.stack((x.ravel(), y.ravel()), axis=-1)
    grid += rng.uniform(-.32*stride, .32*stride, grid.shape)
    motifs = np.array([point for cut in face.cuts for point in cut_samples(cut)]).reshape(-1, 2)
    hammer_centres = np.array([(cx, cy) for cx, cy, *_ in face.dents])
    candidates = np.concatenate((motifs, hammer_centres, grid))
    keep = contains(candidates, cap*.985)
    if hole is not None:
        keep &= ~contains(candidates, np.asarray(BORE_CENTER) + 1.12*(hole - BORE_CENTER))
    accepted = []
    cells = {}
    spacing = .0052
    for point in candidates[keep]:
        ix, iy = np.floor(point/spacing).astype(int)
        nearby = [other for dx in (-1,0,1) for dy in (-1,0,1)
                  for other in cells.get((ix+dx, iy+dy), ())]
        if any(np.dot(point-other, point-other) < spacing*spacing for other in nearby):
            continue
        cells.setdefault((ix,iy), []).append(point)
        accepted.append(point)
    return np.array(accepted).reshape(-1, 2)


def cap_indices(face, outer_ids, inner_ids, vertices, triangles, uv_faces):
    cap = np.array([vertices[i][:2] for i in outer_ids])
    hole = np.array([vertices[i][:2] for i in inner_ids]) if inner_ids else None
    points = [cap]
    edges = circle_edges(0, len(cap))
    if hole is not None:
        points.append(hole)
        edges += circle_edges(len(cap), len(hole))
    points.append(interior_samples(face, cap, hole))
    points = np.concatenate(points)
    coordinates, _, faces, source, _, _ = delaunay_2d_cdt(
        [Vector(point) for point in points], edges, [], 0, 1e-7
    )
    coords = np.array(coordinates)
    local = np.array(faces, dtype=int)
    centers = coords[local].mean(axis=1)
    keep = contains(centers, cap)
    if hole is not None:
        keep &= ~contains(centers, hole)
    local = local[keep]
    used = sorted(set(local.ravel()))
    heights = face.top_height(*coords[used].T) * (-1 if face.rear else 1)
    boundary = outer_ids + inner_ids
    mapping = {}
    for i, z in zip(used, heights, strict=True):
        origin = source[i][0]
        if origin < len(boundary):
            mapping[i] = boundary[origin]
        else:
            mapping[i] = len(vertices)
            vertices.append((*coords[i], z))
    tile = BACK_TILE if face.rear else FRONT_TILE
    for a, b, c in local:
        ba, ca = coords[b]-coords[a], coords[c]-coords[a]
        ccw = ba[0]*ca[1] - ba[1]*ca[0] > 0
        sequence = (a,b,c) if ccw != face.rear else (a,c,b)
        triangle = tuple(mapping[i] for i in sequence)
        triangles.append(triangle)
        uv_faces.append(tuple(tile_uv(tile, vertices[i][0]/FACE_SPAN + .5,
                                      vertices[i][1]/FACE_SPAN + .5) for i in triangle))


def tile_uv(tile, u, v):
    x, y, w, h = tile
    return ((x + .5 + (w-1)*u)/ATLAS_SIZE, (y + .5 + (h-1)*v)/ATLAS_SIZE)


def make_ring(outline, height, vertices):
    ids = list(range(len(vertices), len(vertices) + len(outline)))
    vertices.extend((*point, z) for point, z in zip(outline, height, strict=True))
    return ids


def join_rings(rings, fractions, tile, polygons, texture, inward=False):
    count = len(rings[0])
    for first, second, low, high in zip(rings[:-1], rings[1:], fractions[:-1], fractions[1:], strict=True):
        for i in range(count):
            nxt = (i + 1) % count
            corners = first[i], first[nxt], second[nxt], second[i]
            uv = (tile_uv(tile, i/count, low), tile_uv(tile, (i+1)/count, low),
                  tile_uv(tile, (i+1)/count, high), tile_uv(tile, i/count, high))
            for tri in ((0, 1, 2), (0, 2, 3)):
                if inward:
                    tri = tri[::-1]
                polygons.append(tuple(corners[j] for j in tri))
                texture.append(tuple(uv[j] for j in tri))


def center_of_volume(vertices, triangles):
    tetrahedra = vertices[np.asarray(triangles)]
    a, b, c = tetrahedra.transpose(1, 0, 2)
    six_volumes = np.einsum("ij,ij->i", a, np.cross(b, c))
    assert six_volumes.sum() > 1e-6, "Surface winding or enclosed volume is invalid"
    return np.sum(tetrahedra.sum(axis=1)*six_volumes[:, None], axis=0)/(4*six_volumes.sum())


def mesh_for_coin(coin, outline, front, rear):
    vertices, triangles, uv_faces = [], [], []
    fraction = [0, .09, .24, .49, .70, .88, 1]
    radii = 1 - coin.bevel*np.array([1.13, .53, .13, 0, .07, .39, .97])
    low = -rear.top_height(*(outline*radii[0]).T)
    high = front.top_height(*(outline*radii[-1]).T)
    assert np.min(high-low) > .041, coin.stem
    angles = np.arange(len(outline))*math.tau/len(outline)
    rim = []
    for r, t in zip(radii, fraction, strict=True):
        chatter = np.sin(angles*13 + t*5.2) + .55*np.cos(angles*21 - 4*t)
        ripple = (coin.irregularity*.15 * math.sin(math.pi*t)*chatter)
        xy = (r + ripple[:, None])*outline
        z = low*(1-t) + high*t
        rim.append(make_ring(xy, z, vertices))
    join_rings(rim, fraction, RIM_TILE, triangles, uv_faces)

    bore = []
    if coin.kind == "stone":
        bore_layers = [-1, -.76, -.41, -.04, .47, .77, 1]
        ring_low = -rear.top_height(*bore_outline(-1).T)
        ring_high = front.top_height(*bore_outline(1).T)
        fractions = [(t+1)/2 for t in bore_layers]
        for t, f in zip(bore_layers, fractions, strict=True):
            xy = bore_outline(t)
            bore.append(make_ring(xy, ring_low*(1-f) + ring_high*f, vertices))
        join_rings(bore, fractions, BORE_TILE, triangles, uv_faces, inward=True)

    cap_indices(front, rim[-1], bore[-1] if bore else [], vertices, triangles, uv_faces)
    cap_indices(rear, rim[0], bore[0] if bore else [], vertices, triangles, uv_faces)
    assert 2000 <= len(triangles) <= 6000, f"{coin.stem}: {len(triangles)} triangles"
    positions = np.array(vertices)
    axis_length = np.concatenate(rim)
    rim_xy = positions[axis_length, :2]
    planar_diameter = np.sqrt(np.max(np.sum((rim_xy[:, None, :]-rim_xy[None, :, :])**2, axis=-1)))
    positions = (positions - center_of_volume(positions, triangles)) * coin.diameter/planar_diameter
    assert np.linalg.norm(center_of_volume(positions, triangles)) < 1e-12, coin.stem
    assert .75 <= np.max(np.ptp(positions, axis=0)) <= .95, coin.stem
    # Rotate upright before Blender's standard Y-up glTF conversion.
    normalized = positions[:, [0, 2, 1]] * (1, -1, 1)
    mesh = bpy.data.meshes.new(coin.stem)
    mesh.from_pydata(normalized.tolist(), [], triangles)
    mesh.update()
    assert not mesh.validate(clean_customdata=False), coin.stem
    uv = mesh.uv_layers.new(name="Coin surfaces")
    for face, corners in zip(mesh.polygons, uv_faces, strict=True):
        face.use_smooth = True
        for loop, coord in zip(face.loop_indices, corners, strict=True):
            uv.uv[loop].vector = coord

    check = bmesh.new()
    try:
        check.from_mesh(mesh)
        assert all(e.is_manifold and e.is_contiguous for e in check.edges), coin.stem
        assert all(f.calc_area() > 1e-10 for f in check.faces), coin.stem
        assert len(check.verts) - len(check.edges) + len(check.faces) == (0 if bore else 2), coin.stem
        assert check.calc_volume(signed=True) > 0, coin.stem
    finally:
        check.free()
    return mesh


def rgb(hex_color):
    return np.array([int(hex_color[i:i+2], 16)/255 for i in (0, 2, 4)], dtype=np.float32)


def blend(first, second, fraction):
    weight = np.asarray(fraction)[..., None]
    return first*(1-weight) + second*weight


def field_noise(x, y, seed):
    """Deterministic continuous value noise, evaluated in physical coin coordinates."""
    ix, iy = np.floor(x).astype(np.int32), np.floor(y).astype(np.int32)
    t, s = x-ix, y-iy
    t, s = t*t*(3-2*t), s*s*(3-2*s)
    offset = np.uint32((seed * 1274126177) & 0xffffffff)

    def lattice(a, b):
        v = a.astype(np.uint32)*np.uint32(374761393) + b.astype(np.uint32)*np.uint32(668265263)
        v = v + offset
        v = (v ^ (v >> 13)) * np.uint32(1274126177)
        return ((v ^ (v >> 16)) & np.uint32(65535)).astype(np.float32) / 65535

    lower = lattice(ix, iy)*(1-t) + lattice(ix+1, iy)*t
    upper = lattice(ix, iy+1)*(1-t) + lattice(ix+1, iy+1)*t
    return lower*(1-s) + upper*s


def mineral_veins(x, y, seed):
    drift = field_noise(x*12.5, y*13.8, seed)
    diagonal = .49*x + .102 + .044*np.sin(x*9.4 -.9) + .029*(drift-.5)
    main = np.exp(-((y-diagonal) / (.0105 + .012*drift))**2)
    split = diagonal + .044 + .029*np.sin(8*x + .2)
    fork = np.exp(-((y-split)/.0060)**2) * ease(-.28, -.13, x)*(1-ease(.23, .46, x))
    fine = y - (.41*x - .293 + .028*np.cos(x*15) + .019*(drift-.5))
    return np.clip(.83*main + .56*fork + .53*np.exp(-(fine/.009)**2), 0, 1)


def pigment(coin, x, y, cut, dent, wear, wall=False):
    # Seed by coin and scale so the same stone grain flows over the two bevels.
    seed = coin.seed
    clouds = (.63*field_noise(x*6.4, y*7.1, seed)
              + .37*field_noise(x*18.1, y*21.7, seed+1))
    small = field_noise(x*51.2, y*45, seed+2)
    grains = (.68*field_noise(x*162, y*180, seed+3)
              + .32*field_noise(x*343, y*315, seed+4))
    bruise = np.clip(-dent/max(coin.hammer_depth, 1e-8), 0, 1)
    incision = ease(.001, .013, cut)
    if coin.kind == "green_ore":
        veins = mineral_veins(x, y, coin.seed+33)
        color = blend(rgb("112C29"), rgb("2B5548"), np.clip(clouds + .11*(small-.5), 0, 1))
        color = blend(color, rgb("81927D"), veins * (.35 + .25*clouds))
        color = blend(color, rgb("4B6B58"), wear*.10)
        color = blend(color, rgb("122620"), incision*.65 + .07*bruise)
        roughness = np.clip(.34 + .11*(clouds-.5) + .043*small -.059*wear + .037*incision, .28, .42)
        micro = .00086*(grains-.5) + .00074*(small-.5) - .00049*veins
    elif coin.kind in {"iron", "scrap_iron"}:
        scrap = coin.kind == "scrap_iron"
        gray = blend(rgb("272C2D") if not scrap else rgb("2D302E"),
                     rgb("575A57") if not scrap else rgb("504D45"),
                     np.clip(.84*clouds + .16*small, 0, 1))
        scale = 10.5 if scrap else 13.0
        oxidation = (.68*field_noise(x*scale - 1, y*scale + 2.5, seed+13)
                     + .20*small + .12*grains + .20*bruise + .085*incision)
        if scrap:
            oxides = ease(.37, .70, oxidation)*.90
            rust = blend(rgb("432A20"), rgb("7A5136"), .80*small+.20*grains)
            roughness = np.clip(.577 + .075*small + .075*oxides -.035*wear, .57, .70)
        else:
            oxides = ease(.56, .86, oxidation)*.46
            rust = blend(rgb("413028"), rgb("694D38"), small)
            roughness = np.clip(.503 + .080*small + .083*oxides -.035*wear, .48, .62)
        color = blend(gray, rust, oxides)
        color = blend(color, rgb("1B1D1C"), .47*incision+.17*bruise)
        color = blend(color, rgb("676A61"), .09*wear if scrap else .12*wear)
        micro = (.00140 + .00071*scrap)*(grains-.5) + .00120*(small-.5) - .0017*oxides
    else:
        stratum = .50 + .50*np.sin(x*42.0 + y*19.0 + 11.0*clouds)
        pore = ease(.59, .88, grains)
        color = blend(rgb("514B43"), rgb("8D7B65"),
                      np.clip(.73*clouds + .16*small + .11*stratum, 0, 1))
        color = blend(color, rgb("37342C"), .44*pore + .13*bruise)
        color = blend(color, rgb("9C8C73"), wear*.12 + .10*ease(.68,.90,small))
        roughness = np.clip(.863 + .05*grains + .053*small -.020*wear, .85, .95)
        micro = .0031*(small-.5) + .0021*(grains-.5) - .0019*pore + .0009*stratum
    grain_contrast = .13 if coin.kind == "green_ore" else .25
    color = np.clip(color * (1 + (grains-.5)[..., None]*grain_contrast), 0, 1)
    if wall:
        micro *= 1.18
    # A small imprint complements the much deeper marks already cut into the mesh.
    micro += dent*.12 - cut*.075
    return color, roughness, micro


def pixel_grid(tile, span):
    _, _, w, h = tile
    return np.meshgrid(np.linspace(-span/2, span/2, w, dtype=np.float32),
                       np.linspace(-span/2, span/2, h, dtype=np.float32))


def write_tile(atlas, tile, values, spacing):
    x, y, w, h = tile
    color, roughness, micro = values
    dy, dx = np.gradient(micro, *spacing)
    normal = np.stack((-dx, -dy, np.ones_like(dx)), axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    white = np.ones_like(roughness)
    packed = np.stack((white, roughness, white), axis=-1)
    for image, channels in zip(atlas, (color, normal*.5+.5, packed), strict=True):
        image[y:y+h, x:x+w, :3] = channels


def bake_atlas(coin, outline, front, rear):
    atlas = [np.ones((ATLAS_SIZE, ATLAS_SIZE, 4), np.float32) for _ in range(3)]
    atlas[0][:, :, :3] = rgb("373A35")
    atlas[1][:, :, :3] = (.5,.5,1)
    atlas[2][:, :, :3] = (1,.55,1)
    face_width = FRONT_TILE[2]
    x, y = pixel_grid(FRONT_TILE, FACE_SPAN)
    radius = np.hypot(x, y/coin.aspect)
    wear = ease(.355, .471, radius) * (.6 + .4*field_noise(x*21,y*21,coin.seed))
    for tile, face in ((FRONT_TILE, front), (BACK_TILE, rear)):
        cut = cut_field(x, y, face.cuts)
        dent = face.dents_field(x, y)
        values = pigment(coin, x, y, cut, dent, wear)
        step = FACE_SPAN/(face_width-1)
        write_tile(atlas, tile, values, (step, step))

    for tile in (RIM_TILE, BORE_TILE) if coin.kind == "stone" else (RIM_TILE,):
        _, _, w, h = tile
        u, v = np.meshgrid(np.linspace(0, 1, w, dtype=np.float32),
                           np.linspace(0, 1, h, dtype=np.float32))
        ring = outline if tile == RIM_TILE else bore_outline(0)
        perimeter = np.linalg.norm(np.roll(ring, -1, axis=0)-ring, axis=1).sum()
        angles = np.arange(len(ring))/len(ring)
        x = np.interp(u, angles, ring[:,0], period=1)
        y = np.interp(u, angles, ring[:,1], period=1)
        wear = .18+.75*ease(.70,1,np.abs(2*v-1))
        x = x*(.94+.06*np.sin(math.pi*v)) + .055*(v-.5)
        y = y*(.94+.06*np.sin(math.pi*v)) + .083*(v-.5)
        zeros = np.zeros_like(v)
        values = pigment(coin, x, y, zeros, zeros, wear, wall=True)
        color, roughness, micro = values
        if tile == BORE_TILE:
            color = color*.76
            # Faint circumferential scratches left by the hand drill.
            micro = micro + .00075*np.sin(v*106 + 3*u)
        write_tile(atlas, tile, (color,roughness,micro),
                   (coin.thickness/(h-1), perimeter/(w-1)))

    pictures = []
    for name, pixels, space in zip(("Albedo", "Normal", "Roughness"), atlas,
                                    ("sRGB", "Non-Color", "Non-Color"), strict=True):
        image = bpy.data.images.new(f"{coin.english} {name}", ATLAS_SIZE, ATLAS_SIZE, alpha=False)
        image.colorspace_settings.name = space
        image.pixels.foreach_set(np.clip(pixels,0,1).ravel())
        image.update()
        image.pack()
        pictures.append(image)
    return pictures


def make_material(coin, images):
    mat = bpy.data.materials.new(coin.english)
    if mat.node_tree is None:
        mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Metallic"].default_value = coin.metallic
    if coin.kind == "green_ore":
        shader.inputs["Coat Weight"].default_value = .075
        shader.inputs["Coat Roughness"].default_value = .37
    textures = []
    for image in images:
        node = nodes.new("ShaderNodeTexImage")
        node.image = image
        node.extension = "EXTEND"
        textures.append(node)
    links.new(textures[0].outputs["Color"], shader.inputs["Base Color"])
    normal = nodes.new("ShaderNodeNormalMap")
    normal.inputs["Strength"].default_value = .80 if coin.kind == "green_ore" else .95
    links.new(textures[1].outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], shader.inputs["Normal"])
    channel = nodes.new("ShaderNodeSeparateColor")
    channel.mode = "RGB"
    links.new(textures[2].outputs["Color"], channel.inputs["Color"])
    links.new(channel.outputs["Green"], shader.inputs["Roughness"])
    return mat


def verify_glb(path, coin, mesh):
    data = path.read_bytes()
    magic, version, length, size, tag = struct.unpack_from("<4sIII4s", data)
    assert (magic, version, length, tag) == (b"glTF", 2, len(data), b"JSON"), path
    document = json.loads(data[20:20+size])
    assert len(document["nodes"]) == len(document["meshes"]) == 1, path
    node = document["nodes"][0]
    assert "rotation" not in node and "translation" not in node, path
    assert len(document["images"]) == 3 and all("bufferView" in i for i in document["images"]), path
    primitive, = document["meshes"][0]["primitives"]
    assert {"POSITION", "NORMAL", "TEXCOORD_0", "TANGENT"} <= primitive["attributes"].keys(), path
    mat = document["materials"][primitive["material"]]
    assert "normalTexture" in mat and "metallicRoughnessTexture" in mat["pbrMetallicRoughness"], path
    assert abs(mat["pbrMetallicRoughness"]["metallicFactor"] - coin.metallic) < 1e-6, path
    slots = document["accessors"]
    count = slots[primitive["indices"]]["count"]
    assert count == 3*len(mesh.polygons), path
    coord = slots[primitive["attributes"]["POSITION"]]
    x, y, z = (b-a for a, b in zip(coord["min"], coord["max"], strict=True))
    assert .75 <= max(x, y) <= coin.diameter+2e-6 and z < .20, path
    return count//3, length


def build_assets():
    meshes = {}
    for coin in COINS:
        outline = make_outline(coin)
        front, rear = CoinFace(coin, False), CoinFace(coin, True)
        mesh = mesh_for_coin(coin, outline, front, rear)
        mesh.materials.append(make_material(coin, bake_atlas(coin, outline, front, rear)))
        obj = bpy.data.objects.new(coin.english, mesh)
        bpy.context.collection.objects.link(obj)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        path = PROPS / f"{coin.stem}.glb"
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
                                  export_yup=True, export_tangents=True, export_animations=False)
        triangles, size = verify_glb(path, coin, mesh)
        print(f"DEMON COIN {coin.stem}: {triangles} triangles, {size} bytes", flush=True)
        bpy.data.objects.remove(obj, do_unlink=True)
        meshes[coin.kind] = mesh
    return meshes


def linear_color(hex_color):
    color = rgb(hex_color)
    return (*np.where(color < .04045, color/12.92, ((color+.055)/1.055)**2.4), 1.0)


def aim(object_to_aim, target):
    object_to_aim.rotation_euler = (Vector(target)-object_to_aim.location).to_track_quat("-Z", "Y").to_euler()


def paper_surface():
    mat = bpy.data.materials.new("Weathered umber backdrop")
    if mat.node_tree is None:
        mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shade = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
    shade.inputs["Roughness"].default_value = .86
    shade.inputs["Specular IOR Level"].default_value = .24
    coords = nodes.new("ShaderNodeTexCoord")
    clouds = nodes.new("ShaderNodeTexNoise")
    clouds.inputs["Scale"].default_value = 2.8
    clouds.inputs["Detail"].default_value = 3.5
    links.new(coords.outputs["Object"], clouds.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = .16
    ramp.color_ramp.elements[0].color = linear_color("332D28")
    ramp.color_ramp.elements[1].position = .83
    ramp.color_ramp.elements[1].color = linear_color("625445")
    links.new(clouds.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], shade.inputs["Base Color"])
    speckle = nodes.new("ShaderNodeTexNoise")
    speckle.inputs["Scale"].default_value = 108
    speckle.inputs["Detail"].default_value = 2
    links.new(coords.outputs["Object"], speckle.inputs["Vector"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = .24
    bump.inputs["Distance"].default_value = .016
    links.new(speckle.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], shade.inputs["Normal"])
    return mat


def studio(name, resolution, width, elevation, background):
    scene = bpy.data.scenes.new(name)
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 40
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 6
    scene.render.resolution_x, scene.render.resolution_y = resolution
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = -.093
    scene.world = bpy.data.worlds.new(name)
    if scene.world.node_tree is None:
        scene.world.use_nodes = True
    glow = scene.world.node_tree.nodes.get("Background")
    glow.inputs["Color"].default_value = (.48, .53, .59, 1)
    glow.inputs["Strength"].default_value = .30

    camera = bpy.data.objects.new("Still life camera", bpy.data.cameras.new("Still life camera"))
    scene.collection.objects.link(camera)
    angle = math.radians(elevation)
    camera.location = (0, -9*math.cos(angle), 9*math.sin(angle))
    aim(camera, (0,0,0))
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = width
    scene.camera = camera
    floor = bpy.data.meshes.new("Backdrop")
    floor.from_pydata([(-20,-20,0),(20,-20,0),(20,20,0),(-20,20,0)], [], [(0,1,2,3)])
    floor.materials.append(background)
    scene.collection.objects.link(bpy.data.objects.new("Backdrop", floor))

    for title, xyz, power, color, sx, sy in (
        ("Warm softbox", (-2.9,-2.1,3.5), 435, (1,.88,.75), 3.34, 3.00),
        ("Cool silver bounce", (3.3,.1,3.1), 310, (.78,.89,1), 3.65, 2.72),
        ("Low raking strip", (.1,2.8,1.62), 305, (1,.94,.84), 3.90, .68),
    ):
        light = bpy.data.lights.new(title, "AREA")
        light.shape = "RECTANGLE"
        light.size, light.size_y = sx, sy
        light.energy = power
        light.color = color
        prop = bpy.data.objects.new(title, light)
        scene.collection.objects.link(prop)
        prop.location = xyz
        aim(prop, (0,0,0))
    return scene


def place(scene, coin, mesh, xy, scale, angles, rear=False):
    prop = bpy.data.objects.new(coin.name + (" reverse" if rear else " obverse"), mesh)
    scene.collection.objects.link(prop)
    flat = Matrix.Rotation(-math.pi/2, 3, "X")
    if rear:
        flat = flat @ Matrix.Rotation(math.pi, 3, "Z")
    gesture = Euler(tuple(math.radians(angle) for angle in angles)).to_matrix()
    rotation = gesture @ flat
    base = min((rotation @ vertex.co).z for vertex in mesh.vertices)
    prop.scale = (scale,)*3
    prop.rotation_euler = rotation.to_euler()
    prop.location = (*xy, -base*scale + .008)
    return prop


def label_style():
    fonts = (Path("/System/Library/Fonts/Hiragino Sans GB.ttc"),
             Path("/System/Library/Fonts/STHeiti Medium.ttc"),
             Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"))
    font = next((bpy.data.fonts.load(str(path)) for path in fonts if path.is_file()), None)
    mat = bpy.data.materials.new("Warm paper lettering")
    if mat.node_tree is None:
        mat.use_nodes = True
    nodes = mat.node_tree.nodes
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = linear_color("E8D9C1")
    emission.inputs["Strength"].default_value = 1.16
    mat.node_tree.links.new(emission.outputs[0], nodes.get("Material Output").inputs["Surface"])
    return font, mat


def caption(scene, label, screen_x, screen_y, style, size):
    font, mat = style
    text = bpy.data.curves.new(label, "FONT")
    text.body = label
    if font:
        text.font = font
    text.align_x = "CENTER"
    text.align_y = "CENTER"
    text.space_character = 1.15
    text.size = size
    text.resolution_u = 8
    text.materials.append(mat)
    obj = bpy.data.objects.new(label, text)
    scene.collection.objects.link(obj)
    camera = scene.camera
    # Keep labels level at the orthographic image plane for both setups.
    bpy.context.view_layer.update()
    basis = camera.rotation_euler.to_matrix()
    obj.rotation_euler = camera.rotation_euler
    obj.location = camera.location + basis @ Vector((screen_x, screen_y, -7.0))
    obj.visible_shadow = False


def render(scene, path):
    print(f"STUDIO {path.name}", flush=True)
    scene.render.filepath = str(path)
    bpy.ops.render.render(scene=scene.name, write_still=True)


def render_previews(meshes):
    backdrop = paper_surface()
    style = label_style()
    has_cjk = style[0] is not None
    lineup = studio("Demon Continent currency", (2440, 1060), 5.03, 58, backdrop)
    for i, (coin, angles) in enumerate(zip(COINS, ((6,8,-12),(4,-7,7),(2,8,-14),(7,-4,18)),
                                           strict=True)):
        x = (i-1.5)*1.155
        place(lineup, coin, meshes[coin.kind], (x,.15), 1.13, angles)
        caption(lineup, coin.name if has_cjk else coin.english, x, -.555, style, .108)
    render(lineup, PREVIEWS/"demon_currency_lineup.png")

    detail = studio("Ore and iron obverse and reverse", (2360, 2000), 3.31, 65, backdrop)
    for row, coin in enumerate(COINS[:2]):
        y = .708 - 1.455*row
        for rear, x, angles in ((False,-.78,(5,8,-12)),(True,.78,(2,-6,9))):
            place(detail, coin, meshes[coin.kind], (x,y), 1.34, angles, rear)
            side = ("背面" if rear else "正面") if has_cjk else ("Reverse" if rear else "Obverse")
            label = f"{coin.name if has_cjk else coin.english} · {side}"
            caption(detail, label, x, .068-1.318*row, style, .085)
    render(detail, PREVIEWS/"demon_currency_closeup.png")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    PROPS.mkdir(parents=True, exist_ok=True)
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    render_previews(build_assets())


if __name__ == "__main__":
    main()
