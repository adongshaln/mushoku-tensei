#!/usr/bin/env python3
"""Export paint references from the aligned world relief control maps.

Run with Python 3.9+ and Pillow / NumPy. No Godot or Blender process is needed.
Each input texel keeps its address in the output. The full world X/Z bounds
map to the full 2:1 texture using WorldTerrainSampler's UV convention.
Crop boxes are [left, top, width, height] in that same PNG, with exclusive
right and bottom edges. Multiply all four integers by 2 or 3 for HD pasteback.
"""

import json
from math import cos, floor, pi, sin, sqrt
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
META_PATH = ROOT / "data/maps/world_relief_meta.json"
OUT = Path(__file__).resolve().parent / "blueprints"
SIZE = (2048, 1024)
CROP_MARGIN = 80
CONTINENTS = {
    "central_continent": "central",
    "demon_continent": "demon",
    "millis_continent": "milis",
}
# Authored Begaritt probe in tools/build_world_map_blender.py's reference image.
BEGARITT_UV = (306 / 1672, 802 / 941)


def read_map(meta, key, mode):
    path = meta["control_maps"][key]
    if not path.startswith("res://"):
        raise ValueError(f"Expected a project resource path for {key}: {path}")
    with Image.open(ROOT / path[len("res://"):]) as image:
        if image.size != SIZE or image.mode not in mode:
            raise ValueError(f"Unexpected {key}: {image.size}, {image.mode}")
        return np.asarray(image).copy()


def smooth(low, high, value):
    t = np.clip((value - low) / (high - low), 0, 1)
    return t * t * (3 - 2 * t)


def mix(base, tint, weight):
    w = weight[..., None]
    return base * (1 - w) + tint * w


def pixel_at_uv(u, v):
    return u * (SIZE[0] - 1), v * (SIZE[1] - 1)


def land_groups(meta, height, region_map):
    land = height >= meta["height_range"]["sea_level"]
    ids = region_map[..., 1]
    groups = {
        key: land & (ids == meta["continents"][continent_id])
        for key, continent_id in CONTINENTS.items()
    }
    # An ID of zero includes both unnumbered continents and the sea. Isolate
    # only the connected above-water land at the Begaritt seed.
    unnumbered = Image.fromarray(np.where(land & (ids == 0), 255, 0).astype(np.uint8)).copy()
    seed = tuple(round(coordinate) for coordinate in pixel_at_uv(*BEGARITT_UV))
    if unnumbered.getpixel(seed) != 255:
        raise ValueError("The Begaritt coast seed is no longer on unnumbered land.")
    ImageDraw.floodfill(unnumbered, seed, 128)
    groups["southwest_continent"] = np.asarray(unnumbered) == 128
    return groups


def crop_boxes(groups):
    boxes = {}
    for key, mask in groups.items():
        box = Image.fromarray(mask).getbbox()
        if box is None:
            raise ValueError(f"No mapped coastline for {key}")
        left = max(0, box[0] - CROP_MARGIN)
        top = max(0, box[1] - CROP_MARGIN)
        right = min(SIZE[0], box[2] + CROP_MARGIN)
        bottom = min(SIZE[1], box[3] + CROP_MARGIN)
        boxes[key] = [left, top, right - left, bottom - top]
    return boxes


def softened_height(height):
    offsets = np.arange(-5, 6, dtype=np.float32)
    weights = np.exp(-0.5 * (offsets / 1.65) ** 2)
    weights /= weights.sum()
    for axis, padding in ((0, ((5, 5), (0, 0))), (1, ((0, 0), (5, 5)))):
        padded = np.pad(height, padding, mode="edge")
        height = np.zeros_like(height)
        for index, weight in enumerate(weights):
            window = (slice(index, index + SIZE[1]), slice(None)) if axis == 0 else (
                slice(None), slice(index, index + SIZE[0])
            )
            height += weight * padded[window]
    return height


def hillshade(height, bounds, sea, rock):
    # Different world-unit spacings on X and Z keep the slope bearings correct
    # even though the exported image follows the 2:1 UV grid.
    dx = (bounds["max_x"] - bounds["min_x"]) / (SIZE[0] - 1)
    dz = (bounds["max_z"] - bounds["min_z"]) / (SIZE[1] - 1)
    slope_z, slope_x = np.gradient(softened_height(np.maximum(height, sea)), dz, dx)
    slope_x *= 0.68
    slope_z *= 0.68
    light_up = 0.67
    light_side = sqrt((1 - light_up**2) / 2)
    lit = (light_up + light_side * (slope_x + slope_z)) / np.sqrt(1 + slope_x**2 + slope_z**2)
    strength = .21 + .32 * rock
    return np.clip(1 + (lit - light_up) * strength, .68, 1.17)


def clean_image(meta, height, splat_a, splat_b, southwest):
    # RGBA channels match build_relief_world.py. Alpha is data in both splats.
    demon, forest, meadow, frost = np.moveaxis(splat_a, -1, 0)
    rock, sand, road, scorch = np.moveaxis(splat_b, -1, 0)
    total = demon + forest + meadow + frost
    desert = np.where(southwest[..., None], (213, 170, 120), (205, 127, 99))
    pigment = (desert * demon[..., None] + forest[..., None] * (109, 157, 115)
               + meadow[..., None] * (180, 189, 125) + frost[..., None] * (230, 239, 239))
    land = np.where(total[..., None] > 0.005,
                    pigment / np.maximum(total[..., None], 0.005), (201, 177, 137))
    land = mix(land, (162, 101, 85), 0.19 * scorch)
    land = mix(land, (230, 207, 162), 0.47 * smooth(.08, .74, sand))

    # Grey-violet stone in the Red Dragon spine and blue-grey in the Blue
    # Dragon spine, using their parent biome colours plus the baked rock layer.
    ridge_color = mix(np.array((166, 143, 132)), (123, 146, 153), smooth(.06, .95, forest))
    ridge_color = mix(ridge_color, (185, 151, 137), .48 * demon)
    ridge_color = mix(ridge_color, (209, 221, 226), .72 * frost)
    sea = float(meta["height_range"]["sea_level"])
    elevation = height - sea
    upland = smooth(.16, .53, elevation)
    ridge = smooth(.11, .93, rock) * (.21 + .53 * upland)
    land = mix(land, ridge_color, ridge)
    land *= hillshade(height, meta["world_bounds"], sea, ridge)[..., None]

    # Reveal the paved-road raster without inventing routes or thinning them
    # by moving their centreline. Both tints use the original splat weights.
    land = mix(land, (137, 104, 74), .42 * smooth(.11, .47, road))
    land = mix(land, (243, 215, 162), .91 * smooth(.30, .76, road))
    water = mix(np.array((67, 115, 145)), (144, 198, 191),
                1 - smooth(.012, .265, -elevation))
    rgb = mix(water, land, smooth(-.005, .005, elevation))
    return Image.fromarray(np.rint(np.clip(rgb, 0, 255)).astype(np.uint8))


def marker_kind(city):
    if city["id"] == "migurd":
        return "village"
    if city["arch"] == "arch_port":
        return "port"
    if city["arch"] in {"arch_capital", "arch_academy", "arch_crater_city"}:
        return "major"
    return "town"


def city_marker(canvas, x, y, kind):
    # Supersample just the glyph. Pixels outside these stamps remain identical
    # to the original clean PNG, including the terrain below other coastlines.
    radius, scale = 13, 4
    side = 2 * radius + 1
    left, top = floor(x) - radius, floor(y) - radius
    stamp = Image.new("RGBA", (side * scale, side * scale))
    draw = ImageDraw.Draw(stamp)
    cream = "#fff4d8"

    def point(a, b):
        return (round((x - left + .5 + a) * scale), round((y - top + .5 + b) * scale))

    if kind == "port":
        blue = "#25678e"
        stem = [point(0, -4.3), point(0, 7.0)]
        bar = [point(-3.2, -1.0), point(3.2, -1.0)]
        arms = [point(a, b) for a, b in
                ((-6.4, 2.0), (-5.0, 4.7), (-3.0, 6.3), (0, 7.0),
                 (3.0, 6.3), (5.0, 4.7), (6.4, 2.0))]
        ring = [point(-2.25, -8.1), point(2.25, -3.6)]
        for color, weight in ((cream, 4.1), (blue, 2.0)):
            draw.line(stem, color, width=round(weight * scale))
            draw.line(bar, color, width=round(weight * scale))
            draw.line(arms, color, width=round(weight * scale), joint="curve")
            draw.ellipse(ring, outline=color, width=round(weight * .74 * scale))
    elif kind == "major":
        star = [point(r * sin(k * pi / 5), -r * cos(k * pi / 5))
                for k in range(10) for r in (8.5 if k % 2 == 0 else 4.1,)]
        draw.line(star + star[:1], cream, width=scale * 2, joint="curve")
        draw.polygon(star, fill="#efba46", outline="#8b602f", width=scale)
    else:
        r, color = (3.55, "#327958") if kind == "village" else (4.7, "#d16f3b")
        draw.ellipse([point(-r - 1.3, -r - 1.3), point(r + 1.3, r + 1.3)], fill=cream)
        draw.ellipse([point(-r, -r), point(r, r)], fill=color)
    canvas.alpha_composite(stamp.resize((side, side), Image.Resampling.LANCZOS), (left, top))


def marked_image(clean, meta, region_map):
    bounds = meta["world_bounds"]
    width = bounds["max_x"] - bounds["min_x"]
    depth = bounds["max_z"] - bounds["min_z"]
    canvas = clean.convert("RGBA")
    for city in meta["cities"].values():
        wx, _, wz = city["position"]
        u = (wx - bounds["min_x"]) / width
        v = (wz - bounds["min_z"]) / depth
        if not (0 <= u <= 1 and 0 <= v <= 1):
            raise ValueError(f"City outside world_bounds: {city['id']}")
        x, y = pixel_at_uv(u, v)
        if region_map[round(y), round(x), 1] != meta["continents"][city["continent_id"]]:
            raise ValueError(f"City does not match its continent in UV: {city['id']}")
        city_marker(canvas, x, y, marker_kind(city))
    return canvas.convert("RGB")


def main():
    meta = json.loads(META_PATH.read_text(encoding="utf-8"))
    if tuple(meta["control_maps"]["size"]) != SIZE:
        raise ValueError(f"Expected the native {SIZE} master canvas.")
    source = read_map(meta, "heightmap", {"I;16", "I;16B", "I"})
    h = meta["height_range"]
    height = source.astype(np.float32) * ((h["max_height"] - h["min_height"]) / 65535) + h["min_height"]
    splat_a = read_map(meta, "biome_splat_a", {"RGBA"}).astype(np.float32) / 255
    splat_b = read_map(meta, "biome_splat_b", {"RGBA"}).astype(np.float32) / 255
    regions = read_map(meta, "region_id_map", {"RGBA"})
    groups = land_groups(meta, height, regions)
    boxes = crop_boxes(groups)
    clean = clean_image(meta, height, splat_a, splat_b, groups["southwest_continent"])
    marked = marked_image(clean, meta, regions)

    OUT.mkdir(parents=True, exist_ok=True)
    clean.save(OUT / "blueprint_master_clean.png")
    marked.save(OUT / "blueprint_master_with_cities.png")
    (OUT / "continent_crop_boxes.json").write_text(
        json.dumps(boxes, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Exported {SIZE[0]} × {SIZE[1]} masters with {len(meta['cities'])} city anchors to {OUT}")
    print(json.dumps(boxes, ensure_ascii=False))


if __name__ == "__main__":
    main()
