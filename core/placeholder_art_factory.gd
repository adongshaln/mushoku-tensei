extends RefCounted

const SIZE := Vector2i(480, 270)

static var _map_cache: Dictionary = {}
static var _raw_textures: Dictionary[String, ImageTexture] = {}
static var _raw_modified: Dictionary[String, int] = {}


static func load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if ResourceLoader.exists(path, "Texture2D"):
		return ResourceLoader.load(path, "Texture2D") as Texture2D
	if not FileAccess.file_exists(path):
		_raw_textures.erase(path)
		_raw_modified.erase(path)
		return null
	var modified := FileAccess.get_modified_time(path)
	if _raw_modified.get(path, -1) == modified:
		return _raw_textures[path]
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	var texture := ImageTexture.create_from_image(image)
	_raw_modified[path] = modified
	_raw_textures[path] = texture
	return texture


static func make_village() -> ImageTexture:
	var size := Vector2i(864, 486)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	for y: int in range(size.y):
		var sky := Color("#8d9b93").lerp(Color("#e5d5af"), clampf(y / 295.0, 0.0, 1.0))
		image.fill_rect(Rect2i(0, y, size.x, 1), sky)
	_paint_polygon(image, [
		Vector2(0, 183), Vector2(96, 116), Vector2(152, 131), Vector2(251, 97), Vector2(356, 147),
		Vector2(453, 129), Vector2(568, 172), Vector2(662, 130), Vector2(750, 155), Vector2(864, 117),
		Vector2(864, 486), Vector2(0, 486)
	], Color("#a39c83"))
	_paint_polygon(image, [
		Vector2(0, 231), Vector2(132, 220), Vector2(242, 176), Vector2(337, 210), Vector2(477, 197),
		Vector2(585, 241), Vector2(695, 199), Vector2(864, 218), Vector2(864, 486), Vector2(0, 486)
	], Color("#91866d"))
	_paint_polygon(image, [
		Vector2(0, 294), Vector2(153, 266), Vector2(313, 287), Vector2(461, 254), Vector2(595, 273),
		Vector2(725, 248), Vector2(864, 282), Vector2(864, 486), Vector2(0, 486)
	], Color("#9c8060"))
	_paint_polygon(image, [
		Vector2(382, 486), Vector2(391, 434), Vector2(521, 380), Vector2(561, 330), Vector2(543, 286),
		Vector2(566, 284), Vector2(616, 326), Vector2(590, 380), Vector2(598, 417), Vector2(664, 486)
	], Color("#c4a57b"))
	for hut: Array in [[631, 247, 0.51], [474, 257, 0.61], [291, 281, 0.81], [738, 306, 0.88], [109, 338, 1.10]]:
		_paint_hut(image, Vector2(hut[0], hut[1]), float(hut[2]))
	# Fog drifts along the valley floor and softens the distant roofs.
	var random := RandomNumberGenerator.new()
	random.seed = 418
	for y: int in range(size.y):
		var mist := exp(-pow((y - 244.0) / 58.0, 2.0)) * 0.29
		for x: int in range(size.x):
			var base := image.get_pixel(x, y)
			var veil := mist * (0.74 + 0.26 * sin(x / 140.0 + y / 45.0))
			var grain := random.randf_range(-0.015, 0.015)
			base = base.lerp(Color("#e7dec7"), veil)
			image.set_pixel(x, y, Color(base.r + grain, base.g + grain, base.b + grain))
	return ImageTexture.create_from_image(image)


static func _paint_hut(image: Image, origin: Vector2, factor: float) -> void:
	var roof := PackedVector2Array()
	for point: Vector2 in [Vector2(-68, 22), Vector2(-56, -2), Vector2(-30, -26), Vector2(1, -37), Vector2(24, -33), Vector2(56, -12), Vector2(70, 17), Vector2(53, 27), Vector2(-26, 32)]:
		roof.append(origin + point * factor)
	_paint_polygon(image, roof, Color("#5b5748"))
	_paint_polygon(image, [roof[0], roof[1], roof[2], roof[3], origin + Vector2(6, -2) * factor, roof[7], roof[8]], Color("#897450"))
	_paint_polygon(image, [roof[8], roof[7], origin + Vector2(46, 42) * factor, origin + Vector2(-32, 44) * factor], Color("#725948"))
	_paint_polygon(image, [
		origin + Vector2(1, 28) * factor, origin + Vector2(13, 27) * factor,
		origin + Vector2(13, 43) * factor, origin + Vector2(0, 43) * factor
	], Color("#443e35"))


static func _paint_polygon(image: Image, vertices: PackedVector2Array, fill: Color) -> void:
	var bounds := Rect2(vertices[0], Vector2.ZERO)
	for point: Vector2 in vertices:
		bounds = bounds.expand(point)
	var low := Vector2i(bounds.position.floor()).clamp(Vector2i.ZERO, image.get_size())
	var high := Vector2i(bounds.end.ceil()).clamp(Vector2i.ZERO, image.get_size())
	for y: int in range(low.y, high.y):
		for x: int in range(low.x, high.x):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), vertices):
				image.set_pixel(x, y, fill)

static func make_background() -> ImageTexture:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color("#b39c78"))
	image.fill_rect(Rect2i(0, 153, SIZE.x, 117), Color("#8a7153"))
	image.fill_rect(Rect2i(0, 136, 278, 18), Color("#77664a"))
	image.fill_rect(Rect2i(0, 0, 113, 136), Color("#c9b683"))
	for x: int in [22, 67, 112, 208, 282, 392]:
		image.fill_rect(Rect2i(x, 0, 5, 154), Color("#554733"))
	for y: int in [164, 190, 218, 249]:
		image.fill_rect(Rect2i(0, y, SIZE.x, 2), Color("#6e5940"))
	return ImageTexture.create_from_image(image)


static func make_combat_background(kind: String) -> ImageTexture:
	var size := Vector2i(960, 540)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	var trial := kind == "stone_trial"
	var sky := Color("#83968f") if trial else Color("#8d9c9b")
	var light := Color("#efdcb4") if trial else Color("#f5dfb4")
	var sand := Color("#8c8064") if trial else Color("#a07651")
	var earth := Color("#4e5144") if trial else Color("#614932")
	for y: int in size.y:
		var color := sky.lerp(light, clampf(y / 310.0, 0.0, 1.0))
		if y > 293:
			color = sand.lerp(earth, (y - 293) / 247.0)
		image.fill_rect(Rect2i(0, y, size.x, 1), color)
	_paint_polygon(image, [
		Vector2(0, 136), Vector2(87, 169), Vector2(143, 126), Vector2(210, 163), Vector2(270, 122),
		Vector2(335, 187), Vector2(397, 223), Vector2(495, 240), Vector2(568, 195), Vector2(633, 178),
		Vector2(685, 138), Vector2(740, 166), Vector2(824, 111), Vector2(960, 148),
		Vector2(960, 303), Vector2(0, 303)
	], sand.lightened(0.29))
	_paint_polygon(image, [
		Vector2(0, 114), Vector2(55, 156), Vector2(66, 226), Vector2(179, 218), Vector2(233, 258),
		Vector2(345, 286), Vector2(487, 310), Vector2(362, 337), Vector2(0, 371)
	], sand.darkened(0.17))
	_paint_polygon(image, [
		Vector2(960, 134), Vector2(875, 155), Vector2(836, 212), Vector2(767, 217), Vector2(717, 248),
		Vector2(633, 280), Vector2(543, 305), Vector2(669, 339), Vector2(960, 357)
	], sand.darkened(0.08))
	_paint_polygon(image, [
		Vector2(0, 178), Vector2(64, 202), Vector2(81, 258), Vector2(149, 280), Vector2(180, 318),
		Vector2(99, 351), Vector2(0, 379)
	], earth.lightened(0.09))
	var noise := RandomNumberGenerator.new()
	noise.seed = 412 if trial else 418
	for i: int in 170:
		var y := noise.randi_range(304, 537)
		var x := noise.randi_range(1, 938)
		var length := noise.randi_range(3, 27)
		var tone := sand.lightened(noise.randf_range(0.04, 0.19)) if i % 3 == 0 else sand.darkened(noise.randf_range(0.17, 0.35))
		_paint_polygon(image, [
			Vector2(x, y), Vector2(x + length * 0.30, y - 3), Vector2(x + length, y - 2),
			Vector2(x + length + 3, y + 1)
		], tone)
	if trial:
		for stone: Array in [[226, 335, 68, 190], [681, 315, 48, 131], [743, 343, 81, 213], [150, 312, 39, 100]]:
			_paint_stele(image, Vector2(stone[0], stone[1]), float(stone[2]), float(stone[3]))
	for y: int in size.y:
		var haze := exp(-pow((y - 261.0) / 94.0, 2.0)) * 0.21
		for x: int in size.x:
			var color := image.get_pixel(x, y).lerp(light, haze)
			var luma := noise.randf_range(-0.026, 0.026)
			luma += sin(x * 0.091 + y * 0.034) * sin(y * 0.127) * 0.009
			image.set_pixel(x, y, Color(color.r + luma, color.g + luma, color.b + luma))
	return ImageTexture.create_from_image(image)


static func _paint_stele(image: Image, at: Vector2, width: float, height: float) -> void:
	var left := at.x - width * 0.5
	var top := at.y - height
	_paint_polygon(image, [
		Vector2(left - 11, at.y + 6), Vector2(left, top + 16), Vector2(left + width * 0.53, top),
		Vector2(left + width - 1, top + 27), Vector2(left + width + 6, at.y + 4)
	], Color("#77766a"))
	_paint_polygon(image, [
		Vector2(left, top + 16), Vector2(left + width * 0.53, top), Vector2(left + width * 0.59, at.y + 3), Vector2(left - 11, at.y + 6)
	], Color("#a29d86"))
	for line: int in 4:
		image.fill_rect(Rect2i(int(left + 9), int(top + height * (0.28 + 0.11 * line)), int(width * 0.28), 2), Color("#625f54"))


static func make_combat_enemy(kind: String, tone: Color) -> ImageTexture:
	var image := Image.create(464, 412, false, Image.FORMAT_RGBA8)
	var ink := tone.darkened(0.58)
	if kind == "swordsman":
		_paint_polygon(image, [
			Vector2(156, 373), Vector2(185, 228), Vector2(163, 154), Vector2(193, 116),
			Vector2(192, 64), Vector2(218, 40), Vector2(254, 42), Vector2(278, 71), Vector2(269, 119),
			Vector2(300, 145), Vector2(319, 210), Vector2(289, 225), Vector2(331, 371),
			Vector2(269, 381), Vector2(244, 300), Vector2(227, 379)
		], ink)
		_paint_polygon(image, [Vector2(194, 139), Vector2(237, 136), Vector2(275, 133), Vector2(298, 180), Vector2(279, 238), Vector2(319, 356), Vector2(277, 359), Vector2(243, 266), Vector2(217, 357), Vector2(175, 357), Vector2(201, 232)], tone)
		_paint_polygon(image, [Vector2(237, 226), Vector2(254, 207), Vector2(396, 111), Vector2(425, 104), Vector2(404, 133), Vector2(249, 243)], Color("#d5dcce"))
		_paint_polygon(image, [Vector2(198, 80), Vector2(219, 55), Vector2(252, 55), Vector2(265, 84), Vector2(250, 114), Vector2(221, 110)], tone.lightened(0.34))
	else:
		_paint_polygon(image, [
			Vector2(29, 241), Vector2(56, 191), Vector2(68, 109), Vector2(106, 141), Vector2(130, 105),
			Vector2(161, 121), Vector2(200, 84), Vector2(220, 102), Vector2(266, 74), Vector2(300, 110),
			Vector2(341, 123), Vector2(372, 146), Vector2(420, 154), Vector2(454, 199), Vector2(409, 210),
			Vector2(355, 184), Vector2(353, 259), Vector2(400, 324), Vector2(353, 330), Vector2(312, 267),
			Vector2(281, 206), Vector2(240, 238), Vector2(231, 289), Vector2(250, 341), Vector2(195, 345),
			Vector2(172, 281), Vector2(181, 228), Vector2(130, 208), Vector2(109, 245), Vector2(81, 262)
		], ink)
		_paint_polygon(image, [Vector2(54, 230), Vector2(74, 184), Vector2(80, 134), Vector2(107, 172), Vector2(137, 124), Vector2(169, 143), Vector2(215, 122), Vector2(286, 100), Vector2(342, 132), Vector2(354, 175), Vector2(308, 192), Vector2(246, 217), Vector2(192, 201), Vector2(131, 191), Vector2(94, 248)], tone)
		_paint_polygon(image, [Vector2(181, 147), Vector2(204, 96), Vector2(218, 125), Vector2(256, 88), Vector2(270, 117), Vector2(290, 99), Vector2(311, 134), Vector2(274, 164), Vector2(227, 177)], tone.lightened(0.31))
		image.fill_rect(Rect2i(91, 184, 17, 4), Color("#f7c66d"))
	return ImageTexture.create_from_image(image)


static func make_combat_shoulder(kind: String) -> ImageTexture:
	var image := Image.create(516, 421, false, Image.FORMAT_RGBA8)
	var coat := Color("#3c6269") if kind == "adult" else Color("#827259")
	var blue := Color("#335961")
	_paint_polygon(image, [
		Vector2(0, 335), Vector2(27, 281), Vector2(100, 255), Vector2(176, 247),
		Vector2(205, 206), Vector2(298, 218), Vector2(315, 268), Vector2(382, 297),
		Vector2(461, 353), Vector2(499, 421), Vector2(0, 421)
	], coat.darkened(0.45))
	_paint_polygon(image, [
		Vector2(0, 353), Vector2(32, 294), Vector2(106, 265), Vector2(172, 251),
		Vector2(205, 279), Vector2(282, 286), Vector2(312, 274), Vector2(381, 308),
		Vector2(452, 353), Vector2(486, 421), Vector2(0, 421)
	], coat)
	_paint_polygon(image, [
		Vector2(169, 254), Vector2(138, 208), Vector2(124, 142), Vector2(142, 69),
		Vector2(194, 30), Vector2(250, 20), Vector2(319, 38), Vector2(354, 88),
		Vector2(362, 146), Vector2(335, 216), Vector2(285, 253), Vector2(214, 264)
	], blue.darkened(0.34))
	_paint_polygon(image, [
		Vector2(165, 224), Vector2(145, 161), Vector2(152, 93), Vector2(183, 53),
		Vector2(242, 29), Vector2(295, 39), Vector2(339, 73), Vector2(352, 133),
		Vector2(324, 204), Vector2(282, 235), Vector2(222, 246)
	], blue)
	_paint_polygon(image, [
		Vector2(155, 112), Vector2(188, 60), Vector2(244, 39), Vector2(296, 48),
		Vector2(334, 79), Vector2(306, 73), Vector2(261, 66), Vector2(213, 80),
		Vector2(177, 128)
	], blue.lightened(0.20))
	var last_knot := 8 if kind == "adult" else 6
	for knot: int in last_knot:
		var at := Vector2(220 - 9 * knot + knot % 2 * 8, 226 + 22 * knot)
		_paint_polygon(image, [
			at + Vector2(-22, 0), at + Vector2(4, -9), at + Vector2(24, 8),
			at + Vector2(12, 31), at + Vector2(-9, 28)
		], blue.lerp(blue.lightened(0.19), 0.2 if knot % 2 == 0 else 0.85))
	return ImageTexture.create_from_image(image)


static func make_mask(polygon: PackedVector2Array) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	if polygon.size() < 3:
		return image
	var pixels := PackedVector2Array()
	for point: Vector2 in polygon:
		pixels.append(point * Vector2(SIZE))
	_paint_polygon(image, pixels, Color.WHITE)
	return image


static func make_map_base() -> ImageTexture:
	if _map_cache.has("base"):
		return _map_cache["base"]
	var low_size := Vector2i(550, 338)
	var low := Image.create(low_size.x, low_size.y, false, Image.FORMAT_RGB8)
	var random := RandomNumberGenerator.new()
	random.seed = 418
	var anchors := [Vector2(0.16, 0.52), Vector2(0.43, 0.36), Vector2(0.59, 0.72), Vector2(0.84, 0.32)]
	var tints := [Color("#9db07f"), Color("#7e9678"), Color("#7fa8a0"), Color("#a89a86")]
	for y: int in low_size.y:
		for x: int in low_size.x:
			var uv := Vector2(float(x) / low_size.x, float(y) / low_size.y)
			var col := Color("#ecdcb8").lerp(Color("#d8c193"), uv.y)
			for i: int in 4:
				var blob := exp(-pow(uv.distance_to(anchors[i]) / 0.16, 2.0)) * 0.30
				col = col.lerp(tints[i], blob)
			var mist := exp(-pow((uv.y - 0.34) / 0.10, 2.0)) * exp(-pow((uv.x - 0.45) / 0.30, 2.0)) * 0.35
			col = col.lerp(Color("#e9e4d2"), mist)
			var edge := minf(minf(uv.x, 1.0 - uv.x), minf(uv.y, 1.0 - uv.y))
			var vig := clampf((0.06 - edge) / 0.06, 0.0, 1.0)
			col = col.lerp(Color("#8a6f4d"), vig * 0.55)
			var grain := random.randf_range(-0.02, 0.02)
			low.set_pixel(x, y, Color(col.r + grain, col.g + grain, col.b + grain))
	var image := low.duplicate()
	image.resize(2200, 1350, Image.INTERPOLATE_CUBIC)
	for gx: int in range(200, 2200, 200):
		image.fill_rect(Rect2i(gx, 46, 1, 1258), Color("#c9b089"))
	for gy: int in range(200, 1350, 200):
		image.fill_rect(Rect2i(46, gy, 2108, 1), Color("#c9b089"))
	for peak: Array in [[700, 210, 62, 96], [830, 190, 74, 122], [960, 225, 58, 88], [1100, 185, 80, 132], [1240, 215, 64, 98], [1380, 195, 72, 116], [1520, 225, 56, 84], [150, 420, 54, 80], [260, 400, 66, 102], [370, 430, 50, 74]]:
		_paint_peak(image, Vector2(peak[0], peak[1]), float(peak[2]), float(peak[3]))
	for tree: int in 34:
		var tx := random.randf_range(720.0, 1180.0)
		var ty := random.randf_range(300.0, 660.0)
		_paint_tree(image, Vector2(tx, ty), random.randf_range(14.0, 24.0))
	for hut: Array in [[300, 660, 0.9], [390, 700, 1.1], [330, 760, 0.8], [430, 640, 0.7]]:
		_paint_hut(image, Vector2(hut[0], hut[1]), float(hut[2]) * 0.8)
	_paint_spring(image, Vector2(1298, 972))
	_paint_city(image, Vector2(1848, 432))
	_paint_compass(image, Vector2(1980, 1150))
	for band: Array in [[24, 10], [40, 2]]:
		var inset: int = band[0]
		var thick: int = band[1]
		var tone := Color("#6b5138") if thick > 4 else Color("#8a6f4d")
		image.fill_rect(Rect2i(inset, inset, 2200 - inset * 2, thick), tone)
		image.fill_rect(Rect2i(inset, 1350 - inset - thick, 2200 - inset * 2, thick), tone)
		image.fill_rect(Rect2i(inset, inset, thick, 1350 - inset * 2), tone)
		image.fill_rect(Rect2i(2200 - inset - thick, inset, thick, 1350 - inset * 2), tone)
	var texture := ImageTexture.create_from_image(image)
	_map_cache["base"] = texture
	return texture


static func _paint_peak(image: Image, at: Vector2, w: float, h: float) -> void:
	_paint_polygon(image, [at + Vector2(-w, 0), at + Vector2(-w * 0.15, -h), at + Vector2(w * 0.2, -h * 0.72), at + Vector2(w, 0)], Color("#b7a480"))
	_paint_polygon(image, [at + Vector2(-w * 0.15, -h), at + Vector2(w * 0.2, -h * 0.72), at + Vector2(w, 0), at + Vector2(w * 0.1, 0)], Color("#8f7c5c"))
	_paint_polygon(image, [at + Vector2(-w * 0.15, -h), at + Vector2(-w * 0.02, -h * 0.80), at + Vector2(w * 0.10, -h * 0.86)], Color("#f0e6cc"))


static func _paint_tree(image: Image, at: Vector2, s: float) -> void:
	_paint_polygon(image, [at + Vector2(-s * 0.6, 0), at, at + Vector2(s * 0.6, 0)], Color("#6f8663"))
	_paint_polygon(image, [at + Vector2(-s * 0.45, -s * 0.5), at + Vector2(0, -s * 1.3), at + Vector2(s * 0.45, -s * 0.5)], Color("#7d9670"))
	image.fill_rect(Rect2i(int(at.x - 1), int(at.y), 2, int(s * 0.35)), Color("#6b5138"))


static func _paint_spring(image: Image, at: Vector2) -> void:
	_paint_ellipse(image, at, 96.0, 50.0, Color("#7fa8a0"))
	_paint_ellipse(image, at, 64.0, 32.0, Color("#9cc4bb"))
	_paint_ellipse(image, at + Vector2(-10, -4), 30.0, 14.0, Color("#c2ddd6"))
	for ripple: int in 3:
		_paint_ellipse_ring(image, at, 110.0 + ripple * 22.0, 58.0 + ripple * 12.0, Color("#8fb5ac"))


static func _paint_ellipse(image: Image, at: Vector2, rx: float, ry: float, fill: Color) -> void:
	var points := PackedVector2Array()
	for i: int in 28:
		var angle := TAU * i / 28.0
		points.append(at + Vector2(cos(angle) * rx, sin(angle) * ry))
	_paint_polygon(image, points, fill)


static func _paint_ellipse_ring(image: Image, at: Vector2, rx: float, ry: float, fill: Color) -> void:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i: int in 28:
		var angle := TAU * i / 28.0
		outer.append(at + Vector2(cos(angle) * rx, sin(angle) * ry))
		inner.append(at + Vector2(cos(angle) * (rx - 3.0), sin(angle) * (ry - 2.0)))
	for i: int in 28:
		var j := (i + 1) % 28
		_paint_polygon(image, [outer[i], outer[j], inner[j], inner[i]], fill)


static func _paint_city(image: Image, at: Vector2) -> void:
	_paint_polygon(image, [at + Vector2(-150, 40), at + Vector2(-150, -50), at + Vector2(150, -50), at + Vector2(150, 40)], Color("#9a9384"))
	for notch: int in 7:
		var nx := -140 + notch * 44
		image.fill_rect(Rect2i(int(at.x + nx), int(at.y - 62), 22, 14), Color("#9a9384"))
	_paint_polygon(image, [at + Vector2(-34, -50), at + Vector2(-34, -128), at + Vector2(34, -128), at + Vector2(34, -50)], Color("#8b8474"))
	_paint_polygon(image, [at + Vector2(-40, -128), at + Vector2(0, -160), at + Vector2(40, -128)], Color("#77705f"))
	_paint_polygon(image, [at + Vector2(-20, 40), at + Vector2(-20, -14), at + Vector2(0, -30), at + Vector2(20, -14), at + Vector2(20, 40)], Color("#4f4a3d"))


static func _paint_compass(image: Image, at: Vector2) -> void:
	_paint_ellipse(image, at, 74.0, 74.0, Color("#e4d3ac"))
	_paint_ellipse_ring(image, at, 74.0, 74.0, Color("#6b5138"))
	_paint_ellipse_ring(image, at, 52.0, 52.0, Color("#8a6f4d"))
	var star := PackedVector2Array()
	for i: int in 16:
		var reach := 62.0 if i % 4 == 0 else (34.0 if i % 2 == 0 else 16.0)
		star.append(at + Vector2.from_angle(TAU * i / 16.0 - PI * 0.5) * reach)
	_paint_polygon(image, star, Color("#6b5138"))
	var inner := PackedVector2Array()
	for i: int in 8:
		var reach := 30.0 if i % 2 == 0 else 10.0
		inner.append(at + Vector2.from_angle(TAU * i / 8.0 - PI * 0.5) * reach)
	_paint_polygon(image, inner, Color("#c88a3b"))


