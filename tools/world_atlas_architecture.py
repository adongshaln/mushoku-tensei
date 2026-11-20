"""Low-poly porcelain architecture for the 3D world atlas."""

import math

import bpy


IVORY, STONE, GOLD, BLUE, TERRA, DARK, LAMP = range(7)


class Sculpture:
    def __init__(self):
        self.vertices = []
        self.faces = []
        self.slots = []

    def face(self, points, slot):
        self.faces.append(tuple(range(len(self.vertices), len(self.vertices) + len(points))))
        self.vertices.extend(points)
        self.slots.append(slot)

    def profile(self, x, y, rings, sides, slot, angle=0.0):
        sections = []
        for z, radius in rings:
            sections.append([(x + radius * math.cos(angle + math.tau * i / sides),
                              y + radius * math.sin(angle + math.tau * i / sides), z)
                             for i in range(sides)])
        self.face(sections[0][::-1], slot)
        for low, high in zip(sections, sections[1:]):
            for i in range(sides):
                j = (i + 1) % sides
                self.face((low[i], low[j], high[j], high[i]), slot)
        self.face(sections[-1], slot)

    def block(self, x, y, z, wide, depth, height, slot):
        a, b = wide / 2, depth / 2
        cut = min(a, b) * 0.22
        shape = ((-a + cut, -b), (a - cut, -b), (a, -b + cut), (a, b - cut),
                 (a - cut, b), (-a + cut, b), (-a, b - cut), (-a, -b + cut))
        low = [(x + px, y + py, z) for px, py in shape]
        high = [(px, py, pz + height) for px, py, pz in low]
        self.face(low[::-1], slot)
        self.face(high, slot)
        for i in range(len(low)):
            j = (i + 1) % len(low)
            self.face((low[i], low[j], high[j], high[i]), slot)

    def hip(self, x, y, z, width, depth, rise, slot):
        a, b = width * 0.5, depth * 0.5
        ridge = a * 0.58
        low = [(x-a, y-b, z), (x+a, y-b, z), (x+a, y+b, z), (x-a, y+b, z)]
        left, right = (x-ridge, y, z+rise), (x+ridge, y, z+rise)
        self.face(low[::-1], slot)
        self.face((low[0], low[1], right, left), slot)
        self.face((low[1], low[2], right), slot)
        self.face((low[2], low[3], left, right), slot)
        self.face((low[3], low[0], left), slot)
        self.block(x, y, z + rise - 0.012, ridge * 2.04, 0.035, 0.036, GOLD)
        # Narrow glazed seams follow the sloping roof faces.
        for side in (-1, 1):
            for tick in (-0.68, -0.36, 0.0, 0.36, 0.68):
                p = (x + tick*a, y + side*b*0.96, z + rise*0.042 + 0.008)
                q = (x + tick*ridge, y + side*b*0.08, z + rise*0.922 + 0.008)
                offset = 0.010
                face = [(p[0]-offset, p[1], p[2]), (p[0]+offset, p[1], p[2]),
                        (q[0]+offset, q[1], q[2]), (q[0]-offset, q[1], q[2])]
                self.face(face if side == -1 else face[::-1], GOLD if tick == 0.0 else slot)

    def arch(self, x, y, z, width, height, slot):
        radius = width * 0.5
        shoulder = z + height - radius
        face = [(x - radius, y, z), (x + radius, y, z)]
        for i in range(9):
            angle = math.pi * i / 8
            face.append((x + radius * math.cos(angle), y, shoulder + radius * math.sin(angle)))
        self.face(face, slot)

    def doorway(self, x, y, z, width, height):
        self.arch(x, y - 0.016, z, width * 1.24, height * 1.09, GOLD)
        self.arch(x, y - 0.023, z + 0.014, width, height * 0.91, DARK)

    def house(self, x, y, z, width, depth, height, roof):
        self.block(x, y, z, width * 1.07, depth * 1.07, 0.065, STONE)
        self.block(x, y, z + 0.06, width, depth, height, IVORY)
        self.block(x, y, z + height + 0.042, width * 1.13, depth * 1.11, 0.055, GOLD)
        self.hip(x, y, z + height + 0.094, width * 1.19, depth * 1.20, width * 0.38, roof)
        self.doorway(x, y - depth * 0.5, z + 0.07, width * 0.25, height * 0.67)

    def tower(self, x, y, z, radius, height, roof, peak=0.34):
        self.profile(x, y, [(z, radius*1.13), (z+0.055, radius), (z+height, radius*0.92)], 8, IVORY)
        self.profile(x, y, [(z+height-0.086, radius*0.97), (z+height, radius*1.14),
                            (z+height+0.052, radius*1.14)], 8, GOLD)
        self.profile(x, y, [(z+height+0.051, radius*1.23), (z+height+0.13, radius*0.94),
                            (z+height+peak-0.03, radius*0.26), (z+height+peak, 0.025)], 8, roof)
        self.profile(x, y, [(z+height+peak-0.02, 0.04), (z+height+peak+0.095, 0.013)], 8, GOLD)
        self.doorway(x, y - radius * 0.94, z+height*0.37, radius*0.68, radius*1.3)

    def crescent(self, low, high, z, height, parts, begin, end, slot):
        outer = [(high * math.cos(begin + (end - begin) * i / parts),
                  high * math.sin(begin + (end - begin) * i / parts)) for i in range(parts + 1)]
        inner = [(low * math.cos(begin + (end - begin) * i / parts),
                  low * math.sin(begin + (end - begin) * i / parts)) for i in range(parts + 1)]
        for i in range(parts):
            j = i+1
            top = [(*point, z+height) for point in (outer[i], outer[j], inner[j], inner[i])]
            bottom = [(x, y, z) for x, y, _ in top]
            self.face(top, slot)
            self.face(bottom[::-1], slot)
            for k in (0, 2):
                self.face((bottom[k], bottom[k+1], top[k+1], top[k]), slot)
            if i == 0 and end - begin < math.tau:
                self.face((bottom[3], bottom[0], top[0], top[3]), slot)
            if j == parts and end - begin < math.tau:
                self.face((bottom[1], bottom[2], top[2], top[1]), slot)

    def pedestal(self):
        self.profile(0, 0, [(0.00, 0.81), (0.025, 0.93), (0.073, 0.93), (0.13, 0.88)], 20, GOLD)
        self.profile(0, 0, [(0.13, 0.87), (0.153, 0.84), (0.175, 0.81)], 20, STONE)

    def mesh(self, name, materials):
        unique, index, remap = [], {}, []
        for point in self.vertices:
            key = tuple(round(value, 6) for value in point)
            if key not in index:
                index[key] = len(unique)
                unique.append(point)
            remap.append(index[key])
        result = bpy.data.meshes.new(name)
        result.from_pydata(unique, [], [tuple(remap[i] for i in face) for face in self.faces])
        result.update()
        assert not result.validate(clean_customdata=False), name
        for palette in materials:
            result.materials.append(palette)
        for polygon, slot in zip(result.polygons, self.slots):
            polygon.material_index = slot
        return result


def capital(m):
    for i, span in enumerate((1.14, 0.99, 0.85)):
        m.block(0, -0.48 + i*0.047, 0.169+i*0.046, span, 0.51, 0.049, STONE if i % 2 == 0 else IVORY)
    m.house(0.0, 0.06, 0.25, 0.86, 0.66, 0.66, BLUE)
    for x, y, h in ((-0.42, 0.11, 0.83), (0.43, 0.18, 1.01), (0.18, 0.45, 1.15)):
        m.tower(x, y, 0.175, 0.151, h, BLUE if x > 0 else TERRA, 0.42)
    for x in (-0.27, 0.27):
        m.arch(x, -0.295, 0.55, 0.13, 0.23, DARK)


def crater(m):
    m.crescent(0.60, 0.74, 0.173, 0.26, 22, -1.24, 4.39, STONE)
    m.crescent(0.60, 0.76, 0.42, 0.042, 22, -1.24, 4.39, GOLD)
    m.crescent(0.39, 0.49, 0.174, 0.20, 16, -2.8, 2.91, IVORY)
    for i in range(10):
        angle = -0.98 + i*0.56
        m.block(math.cos(angle)*0.68, math.sin(angle)*0.68, 0.456, 0.13, 0.125, 0.08, IVORY)
    for x, y, h in ((-0.26, 0.23, 0.66), (0.12, 0.28, 0.72), (0.29, -0.02, 0.43)):
        m.tower(x, y, 0.18, 0.13, h, TERRA, 0.24)
    for i in range(5):
        m.block(0, -0.61 + i*0.079, 0.175+i*0.037, 0.24, 0.38, 0.052, STONE)


def academy(m):
    m.block(0, 0, 0.17, 1.30, 0.94, 0.14, STONE)
    m.tower(-0.27, 0.18, 0.30, 0.228, 1.10, BLUE, 0.61)
    m.profile(0.34, 0.12, [(0.29, 0.31), (0.62, 0.31), (0.67, 0.34)], 12, IVORY)
    m.profile(0.34, 0.12, [(0.67, 0.35), (0.75, 0.35), (0.899, 0.30), (1.018, 0.205),
                           (1.071, 0.075), (1.085, 0.025)], 12, BLUE)
    m.profile(0.34, 0.12, [(1.06, 0.05), (1.13, 0.05), (1.22, 0.012)], 8, GOLD)
    for x in (-0.50, -0.24, 0.03, 0.28, 0.50):
        m.profile(x, -0.45, [(0.30, 0.044), (0.69, 0.038), (0.72, 0.052)], 6, IVORY)
    for x in (-0.37, -0.11, 0.16, 0.39):
        m.arch(x, -0.432, 0.31, 0.21, 0.42, DARK)
    m.block(0, -0.445, 0.72, 1.22, 0.25, 0.075, GOLD)


def port(m):
    m.crescent(0.56, 0.80, 0.17, 0.11, 12, -2.94, 0.43, BLUE)
    m.crescent(0.52, 0.77, 0.275, 0.06, 12, -2.75, -0.05, STONE)
    for i in range(8):
        angle = -2.68 + 0.34*i
        m.block(math.cos(angle)*0.72, math.sin(angle)*0.72, 0.328, 0.085, 0.09, 0.105, IVORY)
    m.house(-0.29, 0.18, 0.177, 0.64, 0.48, 0.31, BLUE)
    x, y = 0.42, -0.02
    m.profile(x, y, [(0.182, 0.216), (0.25, 0.20), (0.42, 0.172), (0.96, 0.116)], 10, IVORY)
    m.profile(x, y, [(0.57, 0.162), (0.62, 0.16)], 10, TERRA)
    m.profile(x, y, [(0.91, 0.134), (0.96, 0.186), (1.00, 0.17)], 10, GOLD)
    m.profile(x, y, [(0.997, 0.118), (1.18, 0.118)], 10, LAMP)
    for i in range(6):
        angle = math.tau*i/6
        m.profile(x+math.cos(angle)*0.121, y+math.sin(angle)*0.121,
                  [(1.0, 0.022), (1.18, 0.022)], 6, GOLD)
    m.profile(x, y, [(1.178, 0.175), (1.225, 0.151), (1.36, 0.041), (1.40, 0.023)], 10, TERRA)
    m.doorway(x, y - 0.187, 0.22, 0.11, 0.17)


def village(m):
    for x, y, w, d, h, roof in ((-0.35, -0.22, 0.46, 0.39, 0.34, TERRA),
                               (0.32, -0.10, 0.43, 0.43, 0.34, BLUE),
                               (-0.19, 0.34, 0.55, 0.37, 0.44, TERRA),
                               (0.42, 0.34, 0.37, 0.26, 0.26, TERRA)):
        m.house(x, y, 0.175, w, d, h, roof)
    for i in range(7):
        m.block(0.015+(i%2)*0.062, -0.70+i*0.131, 0.172, 0.11, 0.092, 0.022, GOLD)


def fortress(m):
    m.block(0, -0.42, 0.172, 1.37, 0.40, 0.30, STONE)
    m.block(0, -0.44, 0.46, 1.37, 0.37, 0.06, GOLD)
    for x in (-0.51, -0.24, 0.24, 0.51):
        m.block(x, -0.49, 0.52, 0.15, 0.16, 0.12, IVORY)
    m.doorway(0.0, -0.61, 0.18, 0.31, 0.32)
    m.house(0.0, 0.13, 0.19, 0.95, 0.60, 0.62, TERRA)
    for x in (-0.48, 0.48):
        m.tower(x, 0.11, 0.175, 0.18, 0.57, BLUE, 0.32)


def build_archetypes(materials):
    shapes = {}
    for recipe in (capital, crater, academy, port, village, fortress):
        sculpt = Sculpture()
        sculpt.pedestal()
        recipe(sculpt)
        name = "arch_crater_city" if recipe == crater else f"arch_{recipe.__name__}"
        shapes[name] = sculpt.mesh(name, materials)
    return shapes


def build_ring(materials):
    sculpt = Sculpture()
    sculpt.crescent(0.97, 1.034, 0.039, 0.014, 24, 0, math.tau, GOLD)
    return sculpt.mesh("Landmark gilt ring", materials)
