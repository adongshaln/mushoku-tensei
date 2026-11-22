"""Build the three continuous Demon Continent tiles from the source coastline."""

import argparse
import json
import sys

import bpy
import numpy as np

sys.dont_write_bytecode = True
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_chunk_demon_ne as terrain

relief = terrain.relief
smooth = terrain.smooth


def atlas_layout(manifest):
    atlas = json.loads(relief.MAP_DATA_JSON.read_text())
    nodes = {city["node"]: city for group in atlas["continents"] if group["id"] == "demon"
             for region in group["regions"] for city in relief.legacy_map.sites(region)}
    offsets = manifest["city_pixel_offsets"]
    cities = {node: (np.array(city["pixel"]) + offsets.get(node, (0, 0)) - (836, 470.5)) * 0.01
              for node, city in nodes.items()}
    edges = {(row["from"], row["to"]): row for row in json.loads(relief.ROUTES_JSON.read_text())["routes"]
             if row["mode"] == "land" and row["from"] in cities and row["to"] in cities}
    definitions = {(row["from"], row["to"]): row for row in manifest["detailed_roads"]}
    if edges.keys() != definitions.keys():
        raise ValueError("Detailed roads must match the canonical Demon land edges")
    roads = {}
    for edge, row in definitions.items():
        via = row.get("via", [(np.array(px) - (836, 470.5)) * 0.01 for px in edges[edge].get("via", [])])
        roads[edge] = np.array([cities[edge[0]], *via, cities[edge[1]]])
    return cities, roads


def road_corridor(x, z, points, elevation):
    """Interpolate the travelled valley spine from one authored terrace to the next."""
    distance = np.full(np.broadcast_shapes(x.shape, z.shape), 10.0)
    h = np.zeros_like(distance)
    for i, (a, b) in enumerate(zip(points, points[1:])):
        dx, dz = b - a
        t = np.clip(((x - a[0]) * dx + (z - a[1]) * dz) / (dx * dx + dz * dz), 0, 1)
        d = np.hypot(x - a[0] - t * dx, z - a[1] - t * dz)
        h = np.where(d < distance, elevation[i] + (elevation[i + 1] - elevation[i]) * t, h)
        distance = np.minimum(distance, d)
    return distance, h


def sculpt(x, z, coast, macro, cities, roads, configs, outer):
    wx = (x - relief.MIN_X) / relief.WORLD_W
    wz = (z - relief.MIN_Z) / relief.WORLD_D
    uv_x = (x - outer[0]) / (outer[2] - outer[0])
    uv_z = (z - outer[1]) / (outer[3] - outer[1])
    shore = terrain.sample_grid(coast, wx, wz)
    noise = relief.value_noise_2d
    strata_warp = noise(uv_x, uv_z, 24, 22, 311)
    fine = noise(uv_x, uv_z, 89, 84, 63)
    broad = noise(uv_x, uv_z, 12, 11, 921)

    # The narrow northern gullies follow staggered escarpments down to the strait.
    gorge_axis = 3.53 + 0.39 * (z + 3.70) + 0.14 * np.sin(z * 7.1)
    gorge = np.exp(-((x - gorge_axis + 0.064 * strata_warp) / 0.116) ** 2)
    west_rim = np.exp(-((x - (3.05 - 0.18 * np.sin(z * 4.4))) / 0.34) ** 2)
    east_rim = np.exp(-((x - (4.15 + 0.21 * np.sin(z * 3.8))) / 0.53) ** 2)
    nw = 0.21 + 0.29 * east_rim + 0.19 * west_rim - 0.20 * gorge
    nw += 0.092 * broad + 0.053 * strata_warp + 0.011 * fine
    nw_bed = terrain.terrace(nw, 0.077, 0.015 * np.cos(x * 8.6 + z * 4.7) + 0.018 * strata_warp)
    nw = (nw * 0.28 + nw_bed * 0.72) * smooth(-0.002, 0.063, shore)

    # Toward the south, broad benches lose elevation into the Wind Port cove.
    retreat = 1 - smooth(-2.85, -0.10, z - 0.10 * np.sin(x * 5.2))
    ridge_a = np.exp(-((x - (5.18 + 0.30 * np.sin(z * 3.1))) / 0.49) ** 2)
    ridge_b = np.exp(-((x - (6.40 + 0.22 * np.sin(z * 4.1))) / 0.48) ** 2)
    erosion = 1 - smooth(0.10, 0.46, abs(strata_warp + np.sin(x * 11 + z * 4) * 0.14))
    south = 0.135 + retreat * (0.19 + 0.28 * np.maximum(ridge_a, ridge_b))
    south += 0.09 * broad - 0.044 * erosion + 0.014 * fine
    south_bed = terrain.terrace(south, 0.061, 0.019 * np.sin(x * 6.5 - z * 5.8) + 0.013 * strata_warp)
    south = (south * 0.25 + south_bed * 0.75) * smooth(-0.003, 0.084, shore)
    north = 1 - smooth(-2.63, -1.94, z + 0.10 * np.sin(x * 4.3))
    h = south * (1 - north) + nw * north

    northeast = configs["chunk_demon_ne"]["bounds"]
    local_road = roads["city_migurd", "city_rikarisu"]
    ne = terrain.sculpt_northeast(x, z, northeast, shore, cities, local_road)
    ne_weight = smooth(northeast[0] - 0.14, northeast[0] + 0.69, x) * (
        1 - smooth(northeast[3] - 0.69, northeast[3] + 0.14, z))
    h = h * (1 - ne_weight) + ne * ne_weight

    grades = {
        ("city_rikarisu", "city_kurasuma"): (0.453, 0.41, 0.31, 0.36, 0.29, 0.18, 0.17),
        ("city_rikarisu", "city_wind_port"): (0.453, 0.36, 0.24, 0.14),
        ("city_kurasuma", "city_wind_port"): (0.17, 0.31, 0.35, 0.23, 0.14),
    }
    for edge, levels in grades.items():
        distance, floor = road_corridor(x, z, roads[edge], levels)
        cut = (1 - smooth(0.026, 0.13, distance)) * smooth(-0.015, 0.04, shore)
        h = h * (1 - cut) + (floor + 0.008 * strata_warp) * cut

    for city_id, grade, depth in [("city_kurasuma", 0.17, 0.28), ("city_wind_port", 0.14, 0.35)]:
        cx, cz = cities[city_id]
        dx, dz = x - cx, z - cz
        pad_dist = np.maximum(abs(dx + dz * 0.18), abs(dz * 1.15 - dx * 0.20))
        pad = (1 - smooth(0.20, depth, pad_dist)) * smooth(-0.026, 0.073, shore + 0.045)
        platform = grade - 0.12 * smooth(0.042, 0.235, dz) + 0.008 * strata_warp
        h = h * (1 - pad) + platform * pad

    # A sheltered landing descends toward the southwestern inlet. The
    # eastern headland stays steep and the offshore ledges sit near water.
    inlet_dist = np.hypot((x - 5.64) / 1.18, (z + 0.015) / 0.95)
    inlet = (1 - smooth(0.23, 0.74, inlet_dist)) * (1 - smooth(5.97, 6.29, x))
    harbor_slope = 0.144 * smooth(-0.004, 0.215, shore)
    harbor_terrace = terrain.terrace(harbor_slope, 0.029, 0.008 * broad)
    harbor_floor = 0.58 * harbor_slope + 0.42 * harbor_terrace
    port_distance = np.hypot(x - cities["city_wind_port"][0], z - cities["city_wind_port"][1])
    inlet *= smooth(0.105, 0.209, port_distance)
    h = h * (1 - inlet) + harbor_floor * inlet

    # Match the earlier sample's open seabed. Outside the Demon shelf, reuse
    # macro bathymetry and the other side of the northern ice bridge.
    old = terrain.sample_grid(macro, wx, wz, triangular=True)
    seabed = -0.24 * smooth(0.0, -0.48, shore) - 0.078 * smooth(0.01, -0.16, shore)
    horizon = smooth(-0.46, -0.13, shore)
    seabed = old * (1 - horizon) + seabed * horizon
    seabed *= 1 - inlet * (1 - smooth(-0.35, -0.05, shore)) * 0.44
    ice_bridge = (1 - smooth(2.88, 3.24, x)) * (1 - smooth(-4.24, -3.95, z))
    seabed = seabed * (1 - ice_bridge) + old * ice_bridge
    h = np.where(shore > 0, h, seabed)

    edge = np.minimum.reduce([x - outer[0], outer[2] - x, z - outer[1], outer[3] - z])
    # Internal edges are sampled from this same continuous relief field.
    # Only the outer continent group needs to meet the old atlas mesh.
    blend = smooth(0, 0.44, edge)
    return (blend * h + (1 - blend) * old).astype(np.float32)


def triangle_sampler(config, surfaces):
    bounds, grid = surfaces[config["id"]]

    def sample(x, z):
        results = terrain.sample_grid(grid, (x - bounds[0]) / (bounds[2] - bounds[0]),
                                      (z - bounds[1]) / (bounds[3] - bounds[1]), True)
        for neighbor_bounds, neighbor_grid in surfaces.values():
            if neighbor_bounds is bounds:
                continue
            left, top, right, bottom = neighbor_bounds
            owns = ((x >= left) & (x <= right)) & ((z >= top) & (z <= bottom))
            if np.any(owns):
                xx, zz = np.broadcast_arrays(x, z)
                results[owns] = terrain.sample_grid(neighbor_grid, (xx[owns] - left) / (right - left),
                                                    (zz[owns] - top) / (bottom - top), True)
        return results
    return sample


def main(default_chunk="all", preview_ne=False):
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--size", type=int, choices=(2048, 4096), default=4096)
    cli.add_argument("--chunk", choices=("all", "chunk_demon_ne", "chunk_demon_nw", "chunk_demon_south"), default=default_chunk)
    cli.add_argument("--preview-ne", action="store_true", default=preview_ne)
    cli.add_argument("--check-layout", action="store_true", help="Validate coast coverage and shared edges without exporting")
    args = cli.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    manifest = json.loads(terrain.MANIFEST.read_text())
    configs = {cfg["id"]: cfg for cfg in manifest["chunks"] if cfg.get("terrain_group") == "demon"}
    cities, roads = atlas_layout(manifest)
    macro, coast = terrain.macro_vertices(), terrain.coastline()
    palettes = terrain.sample_asset_palettes()
    outer = (min(c["bounds"][0] for c in configs.values()), min(c["bounds"][1] for c in configs.values()),
             max(c["bounds"][2] for c in configs.values()), max(c["bounds"][3] for c in configs.values()))
    surfaces = {}
    for key, config in configs.items():
        bounds = np.array(config["bounds"])
        nx, nz = config["grid_cells"]
        x, z = np.meshgrid(np.linspace(bounds[0], bounds[2], nx + 1), np.linspace(bounds[1], bounds[3], nz + 1))
        height = sculpt(x, z, coast, macro, cities, roads, configs, outer)
        assert np.isfinite(height).all() and 45_000 <= nx * nz * 2 <= 65_000
        surfaces[key] = (bounds, height)

    coast_rows, coast_columns = np.nonzero(coast > 0.0)
    coast_x = relief.MIN_X + coast_columns / (coast.shape[1] - 1) * relief.WORLD_W
    coast_z = relief.MIN_Z + coast_rows / (coast.shape[0] - 1) * relief.WORLD_D
    covered = np.zeros(coast_x.shape, dtype=bool)
    for bounds, _height in surfaces.values():
        covered |= (coast_x >= bounds[0]) & (coast_x <= bounds[2]) & (coast_z >= bounds[1]) & (coast_z <= bounds[3])
    if not covered.all():
        raise ValueError(f"{np.count_nonzero(~covered)} Demon coastline pixels fall outside the chunk group")
    print(f"All {covered.size:,} land pixels covered", flush=True)
    northeast = surfaces["chunk_demon_ne"][1]
    northwest = surfaces["chunk_demon_nw"][1]
    south = surfaces["chunk_demon_south"][1]
    borders = ((northeast[:, 0], northwest[:, -1]),
               (south[0], np.concatenate((northwest[-1], northeast[-1, 1:]))))
    for current, adjacent in borders:
        if not np.allclose(current, adjacent, rtol=0.0, atol=2e-6):
            raise ValueError("Tiles disagree at the shared edge")
    if args.check_layout:
        return

    for key, config in configs.items():
        if args.chunk not in ("all", key):
            continue
        bounds, height = surfaces[key]
        obj = terrain.build_mesh(bounds, height, config["grid_cells"])
        glb = terrain.ROOT / config["terrain"].removeprefix("res://")
        bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB", export_yup=True,
                                  use_selection=True, export_materials="NONE")
        print(f"{key}: {len(obj.data.polygons):,} triangles, {glb.stat().st_size:,} bytes", flush=True)
        sample = triangle_sampler(config, surfaces)
        out = (terrain.ROOT / config["pbr_prefix"].removeprefix("res://")).parent
        terrain.bake(key, sample, bounds, list(roads.values()), palettes, args.size, out)
        if key == "chunk_demon_ne" and args.preview_ne:
            terrain.preview(obj, out, relief.OUT_PREVIEW_DIR / f"{key}_blender_preview.png", bounds)
        bpy.data.objects.remove(obj, do_unlink=True)


if __name__ == "__main__":
    main()
