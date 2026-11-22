shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// 7 Mobile-friendly texture samplers total (strictly well within Android 16-sampler budget)
uniform sampler2D heightmap_tex : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D biome_splat_a : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D biome_splat_b : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D region_id_map : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D ao_curvature_tex : hint_default_white, filter_linear, repeat_disable;
uniform sampler2DArray tile_albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tile_normal_array : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

// Height decoding & dual-state zoom blend (0.0 = vivid watercolor diorama, 1.0 = royal parchment atlas)
uniform float min_height = -0.295;
uniform float max_height = 1.359;
uniform float sea_level = 0.0;
uniform float atlas_blend : hint_range(0.0, 1.0) = 1.0;
uniform float tile_scale = 1.32;

// Seamless region & continent interaction uniforms
uniform int hovered_region_idx = 0;
uniform int selected_region_idx = 0;
uniform int hovered_continent_idx = 0;
uniform int active_continent_idx = 0;
uniform int crossing_continent_idx = 0;
uniform float hover_pulse : hint_range(0.0, 1.0) = 0.0;

// M4 seasonal climate & living drifting cloud shadows
uniform float winter_snow_push : hint_range(0.0, 1.0) = 0.0;
uniform float wetness_boost : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_shadow_strength : hint_range(0.0, 0.6) = 0.22;
uniform float rain_cloud_boost : hint_range(0.0, 1.0) = 0.0;

uniform int sculpted_count = 0;
uniform vec4 sculpted_rects[12];
uniform bool sculpted_terrain = false;
uniform vec4 sculpted_transition_bounds;
uniform float sculpted_seam = 0.38;
uniform sampler2D sculpted_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D sculpted_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D sculpted_ao : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D sculpted_roughness : hint_default_white, filter_linear_mipmap, repeat_disable;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
uniform bool hero_ground_enabled = false;
uniform vec4 hero_ground_rect;
uniform sampler2D hero_ground_contact : filter_linear, repeat_disable;
uniform vec4 hero_rock_color : source_color;
uniform vec4 hero_sand_color : source_color;

const vec2 ID_TEXEL = vec2(1.0 / 2048.0, 1.0 / 1024.0);

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm_macro(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 3; i++) {
		v += a * value_noise(p);
		p = p * 2.07 + vec2(13.1, 7.9);
		a *= 0.48;
	}
	return v;
}

float sample_h_world(vec2 uv) {
	float hn = texture(heightmap_tex, clamp(uv, vec2(0.0005), vec2(0.9995))).r;
	return min_height + hn * (max_height - min_height);
}

ivec2 sample_ids(vec2 uv) {
	vec4 px = texture(region_id_map, clamp(uv, vec2(0.0002), vec2(0.9998)));
	return ivec2(int(round(px.r * 255.0)), int(round(px.g * 255.0)));
}

// Smooth C1 anti-aliased regional/continental indicator coverage (eliminates ALL discrete bitmap staircases!)
float smooth_id_coverage(vec2 uv, int target_id, bool match_continent, float radius_px) {
	vec2 dirs[8] = vec2[](
		vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0),
		vec2(0.707, 0.707), vec2(-0.707, 0.707), vec2(0.707, -0.707), vec2(-0.707, -0.707)
	);
	ivec2 c0 = sample_ids(uv);
	float acc = ((match_continent ? c0.y : c0.x) == target_id) ? 2.0 : 0.0;
	float wsum = 2.0;
	for (int i = 0; i < 8; i++) {
		ivec2 n1 = sample_ids(uv + dirs[i] * ID_TEXEL * (radius_px * 0.52));
		ivec2 n2 = sample_ids(uv + dirs[i] * ID_TEXEL * radius_px);
		acc += (((match_continent ? n1.y : n1.x) == target_id) ? 1.15 : 0.0);
		acc += (((match_continent ? n2.y : n2.x) == target_id) ? 0.65 : 0.0);
		wsum += 1.80;
	}
	return acc / wsum;
}

float smooth_playable_coverage(vec2 uv, float radius_px) {
	vec2 dirs[8] = vec2[](
		vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0),
		vec2(0.707, 0.707), vec2(-0.707, 0.707), vec2(0.707, -0.707), vec2(-0.707, -0.707)
	);
	float acc = (sample_ids(uv).x > 0) ? 2.0 : 0.0;
	float wsum = 2.0;
	for (int i = 0; i < 8; i++) {
		acc += (sample_ids(uv + dirs[i] * ID_TEXEL * radius_px).x > 0) ? 1.0 : 0.0;
		wsum += 1.0;
	}
	return acc / wsum;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 n = normalize(NORMAL);
	vec3 t_raw = cross(n, vec3(0.0, 0.0, 1.0));
	vec3 t = (length(t_raw) > 0.001) ? normalize(t_raw) : vec3(1.0, 0.0, 0.0);
	TANGENT = t;
	BINORMAL = normalize(cross(t, n));
}

void fragment() {
	vec2 world_uv = UV;
	vec2 chunk_uv = UV;
	float sculpted_weight = 0.0;
	if (sculpted_terrain) {
		world_uv = (v_world_pos.xz + vec2(8.36, 4.705)) / vec2(16.72, 9.41);
		vec2 edge_dist = min(v_world_pos.xz - sculpted_transition_bounds.xy, sculpted_transition_bounds.zw - v_world_pos.xz);
		sculpted_weight = smoothstep(0.010, sculpted_seam, min(edge_dist.x, edge_dist.y));
	} else {
		for (int j = 0; j < sculpted_count; j++) {
			vec4 rect = sculpted_rects[j];
			if (all(greaterThanEqual(v_world_pos.xz, rect.xy)) && all(lessThan(v_world_pos.xz, rect.zw))) {
				discard;
			}
		}
	}
	vec4 sa = texture(biome_splat_a, world_uv);
	vec4 sb = texture(biome_splat_b, world_uv);
	ivec2 ids = sample_ids(world_uv);
	int r_id = ids.x;
	int c_id = ids.y;

	vec3 wn = normalize(v_world_normal);
	float geom_slope = 1.0 - clamp(wn.y, 0.0, 1.0);

	// 1. Base 4 pure watercolor biome weights (Splat A) + M4 Dragon-Calendar Northern Winter Snow-Line Push
	float w_demon = sa.r;
	float w_milis = sa.g;
	float w_central = sa.b;
	float w_snow = sa.a;
	if (winter_snow_push > 0.001) {
		float snow_noise = fbm_macro(v_world_pos.xz * 0.95) * 0.14 - 0.07;
		// Push snowline organically southward across Central Continent north (Sharia -> Biheiriru -> Strife Keep -> Red Wyrm north)
		float north_push = smoothstep(0.56 - winter_snow_push * 0.34, 0.16, world_uv.y + snow_noise)
			* smoothstep(0.06, 0.18, v_world_pos.y)
			* (1.0 - smoothstep(0.46, 0.66, world_uv.x))  // Protect northeast Demon Continent arid wastes
			* (1.0 - w_demon * 0.88) * (1.0 - w_milis * 0.92);
		float alpine_push = smoothstep(0.52 - winter_snow_push * 0.22, 0.76, v_world_pos.y)
			* (1.0 - w_demon * 0.85) * (1.0 - w_milis * 0.85);
		w_snow = clamp(w_snow + (north_push * 0.94 + alpine_push * 0.58) * winter_snow_push, 0.0, 1.0);
	}
	float sum_a = max(w_demon + w_milis + w_central + w_snow, 0.001);
	vec4 bw_a = vec4(w_demon, w_milis, w_central, w_snow) / sum_a;

	vec2 raw_uv = v_world_pos.xz * tile_scale;
	vec2 drift = vec2(
		value_noise(v_world_pos.xz * 0.52 + vec2(4.2, 1.7)) - 0.5,
		value_noise(v_world_pos.xz * 0.52 + vec2(-3.1, 8.4)) - 0.5
	) * 0.075;
	vec2 organic_uv = raw_uv + drift;

	vec3 base_albedo = vec3(0.0);
	vec3 base_normal = vec3(0.0);
	if (bw_a.r > 0.015) {
		base_albedo += texture(tile_albedo_array, vec3(organic_uv, 0.0)).rgb * bw_a.r;
		base_normal += (texture(tile_normal_array, vec3(organic_uv, 0.0)).rgb * 2.0 - 1.0) * bw_a.r;
	}
	if (bw_a.g > 0.015) {
		base_albedo += texture(tile_albedo_array, vec3(organic_uv, 1.0)).rgb * bw_a.g;
		base_normal += (texture(tile_normal_array, vec3(organic_uv, 1.0)).rgb * 2.0 - 1.0) * bw_a.g;
	}
	if (bw_a.b > 0.015) {
		base_albedo += texture(tile_albedo_array, vec3(organic_uv, 2.0)).rgb * bw_a.b;
		base_normal += (texture(tile_normal_array, vec3(organic_uv, 2.0)).rgb * 2.0 - 1.0) * bw_a.b;
	}
	if (bw_a.a > 0.015) {
		base_albedo += texture(tile_albedo_array, vec3(organic_uv, 3.0)).rgb * bw_a.a;
		base_normal += (texture(tile_normal_array, vec3(organic_uv, 3.0)).rgb * 2.0 - 1.0) * bw_a.a;
	}
	if (length(base_normal) < 0.01) {
		base_normal = vec3(0.0, 0.0, 1.0);
	}

	vec3 col = base_albedo;
	vec3 nrm = base_normal;

	// 2a. Demon Rifts & Volcanic Mineral Strata (Layer 7 — clean, zero turtle-shell mud)
	float w_rift = sb.a * 0.64;
	if (w_rift > 0.015) {
		vec3 rift_col = texture(tile_albedo_array, vec3(organic_uv * 0.95, 7.0)).rgb;
		vec3 rift_nrm = texture(tile_normal_array, vec3(organic_uv * 0.95, 7.0)).rgb * 2.0 - 1.0;
		col = mix(col, rift_col, w_rift);
		nrm = mix(nrm, rift_nrm, w_rift);
	}

	// 2b. Coastal & Lakefront Fine Sand (Layer 5)
	float w_sand = sb.g * (1.0 - smoothstep(0.14, 0.30, geom_slope)) * 0.78;
	if (w_sand > 0.015) {
		vec3 sand_col = texture(tile_albedo_array, vec3(raw_uv * 1.08, 5.0)).rgb;
		vec3 sand_nrm = texture(tile_normal_array, vec3(raw_uv * 1.08, 5.0)).rgb * 2.0 - 1.0;
		col = mix(col, sand_col, w_sand);
		nrm = mix(nrm, sand_nrm, w_sand);
	}

	// 2c. Slender Sun-Warmed Limestone Imperial Highway (Layer 6 — soft organic feathered watercolor edge)
	float road_edge_noise = value_noise(v_world_pos.xz * 12.0) * 0.16;
	float w_road = smoothstep(0.20, 0.74, sb.b - road_edge_noise) * (1.0 - smoothstep(0.22, 0.38, geom_slope)) * 0.78;
	if (sculpted_terrain && c_id == 1) {
		w_road = 0.0;
	}
	if (w_road > 0.015) {
		vec2 road_uv = raw_uv * 2.15;
		vec3 road_col = texture(tile_albedo_array, vec3(road_uv, 6.0)).rgb;
		vec3 road_nrm = texture(tile_normal_array, vec3(road_uv, 6.0)).rgb * 2.0 - 1.0;
		col = mix(col, road_col, w_road);
		nrm = mix(nrm, road_nrm, w_road);
	}

	// 2d. Steep Mountain Cliff Rock (Layer 4) — ONLY on genuine steep mountain walls & cliffs (clean directional strata!)
	float w_rock = clamp(smoothstep(0.24, 0.80, sb.r) * 0.62 + smoothstep(0.13, 0.34, geom_slope) * 0.94, 0.0, 1.0) * (1.0 - w_road * 0.60);
	if (w_rock > 0.015) {
		vec2 rock_xz = raw_uv * 0.85;
		vec2 wall_uv = (abs(wn.x) > abs(wn.z)
			? vec2(v_world_pos.z, v_world_pos.y * 1.48)
			: vec2(v_world_pos.x, v_world_pos.y * 1.48)) * (tile_scale * 0.85);
		float wall_t = smoothstep(0.14, 0.34, geom_slope);
		vec3 rock_col;
		vec3 rock_nrm;
		if (wall_t < 0.04) {
			rock_col = texture(tile_albedo_array, vec3(rock_xz, 4.0)).rgb;
			rock_nrm = texture(tile_normal_array, vec3(rock_xz, 4.0)).rgb * 2.0 - 1.0;
		} else if (wall_t > 0.96) {
			rock_col = texture(tile_albedo_array, vec3(wall_uv, 4.0)).rgb;
			rock_nrm = texture(tile_normal_array, vec3(wall_uv, 4.0)).rgb * 2.0 - 1.0;
		} else {
			vec3 c0 = texture(tile_albedo_array, vec3(rock_xz, 4.0)).rgb;
			vec3 c1 = texture(tile_albedo_array, vec3(wall_uv, 4.0)).rgb;
			vec3 n0 = texture(tile_normal_array, vec3(rock_xz, 4.0)).rgb * 2.0 - 1.0;
			vec3 n1 = texture(tile_normal_array, vec3(wall_uv, 4.0)).rgb * 2.0 - 1.0;
			rock_col = mix(c0, c1, wall_t);
			rock_nrm = mix(n0, n1, wall_t);
		}
		// Refined geological mineral tint per continent
		vec3 tint_demon = vec3(0.95, 0.68, 0.56);
		vec3 tint_milis = vec3(0.75, 0.88, 0.84);
		vec3 tint_central = vec3(1.06, 0.75, 0.60);
		vec3 tint_frost = vec3(0.84, 0.90, 0.98);
		vec3 rock_tint = tint_demon * bw_a.r + tint_milis * bw_a.g + tint_central * bw_a.b + tint_frost * bw_a.a;
		rock_col *= rock_tint;

		// Soft alpine snow dusting resting on high flatter mountain shoulders (excluding arid Demon highlands)
		float alpine_cap = smoothstep(0.62, 0.96, v_world_pos.y) * smoothstep(0.46, 0.85, wn.y) * (1.0 - bw_a.r * 0.90);
		rock_col = mix(rock_col, vec3(0.91, 0.915, 0.92), alpine_cap * 0.56);

		col = mix(col, rock_col, w_rock);
		nrm = mix(nrm, rock_nrm, w_rock);
	}

	// 3. Macro Watercolor Color Wash (Anti-Tiling) + Heightmap Curvature Chiseled Relief Sculpture!
	float macro_a = fbm_macro(v_world_pos.xz * 0.42);
	float macro_b = value_noise(v_world_pos.xz * 1.05 + vec2(5.3, -2.9));
	vec3 warm_wash = mix(vec3(0.94, 0.93, 0.91), vec3(1.06, 1.03, 0.97), macro_a);
	col *= warm_wash * (0.97 + 0.06 * macro_b);

	// Fine cold-press cotton paper grain
	float paper_tooth = value_noise(v_world_pos.xz * 28.0) * 0.6 + value_noise(v_world_pos.xz * 72.0) * 0.4;
	col *= 0.972 + 0.056 * paper_tooth;

	// Real-time Laplacian + High-Precision Cycles Baked Global AO / Ridge Curvature / Contact Shadows
	float h_c = sample_h_world(world_uv);
	vec2 d1 = ID_TEXEL * 3.0;
	vec2 d2 = ID_TEXEL * 9.0;
	float h_avg1 = 0.25 * (
		sample_h_world(world_uv + vec2(d1.x, 0.0)) + sample_h_world(world_uv - vec2(d1.x, 0.0))
		+ sample_h_world(world_uv + vec2(0.0, d1.y)) + sample_h_world(world_uv - vec2(0.0, d1.y))
	);
	float h_avg2 = 0.25 * (
		sample_h_world(world_uv + vec2(d2.x, 0.0)) + sample_h_world(world_uv - vec2(d2.x, 0.0))
		+ sample_h_world(world_uv + vec2(0.0, d2.y)) + sample_h_world(world_uv - vec2(0.0, d2.y))
	);
	float curv_fine = h_c - h_avg1;
	float curv_broad = h_c - h_avg2;
	float land_mask = smoothstep(0.02, 0.12, h_c);
	vec3 baked_aoc = texture(ao_curvature_tex, world_uv).rgb;

	// Baked Physical Global AO (R) + Real-time Valley Cavity -> Cool sea-mist / violet-slate canyon shadows (zero muddy black!)
	float baked_occ = clamp(1.0 - baked_aoc.r, 0.0, 1.0) * land_mask;
	float valley_ao = clamp((-curv_fine * 14.0) + (-curv_broad * 6.0), 0.0, 1.0) * land_mask;
	float baked_crease = clamp((0.5 - baked_aoc.g) * 2.1, 0.0, 1.0) * land_mask;
	float deep_valley = clamp(baked_occ * 0.72 + valley_ao * 0.34 + baked_crease * 0.26, 0.0, 1.0);
	col = mix(col, col * vec3(0.64, 0.69, 0.85), deep_valley * 0.62);

	// 19-City Plinth & Coastal Footing Grounded Contact Shadow (B)
	col *= mix(vec3(0.70, 0.67, 0.73), vec3(1.0), clamp(baked_aoc.b, 0.0, 1.0));

	// Chiseled Ridge & Cliff Curvature Highlight (G) + Sunlit Spines -> Refined ivory-ochre hand-carved relief
	float baked_ridge = clamp((baked_aoc.g - 0.5) * 2.2, 0.0, 1.0) * smoothstep(0.10, 0.44, h_c);
	float rt_ridge = clamp((curv_fine * 16.0) + (curv_broad * 6.5), 0.0, 1.0) * smoothstep(0.16, 0.52, h_c);
	float ridge_pop = clamp(baked_ridge * 0.68 + rt_ridge * 0.42, 0.0, 1.0);
	col = mix(col, col * vec3(1.08, 1.04, 0.94) + vec3(0.024, 0.018, 0.008), ridge_pop * 0.46);

	float hero_area = 0.0;
	if (hero_ground_enabled && c_id == 1) {
		vec2 hero_uv = (v_world_pos.xz - hero_ground_rect.xy) / hero_ground_rect.zw;
		vec2 fade = smoothstep(vec2(0.0), vec2(0.15), hero_uv)
			* (1.0 - smoothstep(vec2(0.78), vec2(1.0), hero_uv));
		hero_area = fade.x * fade.y * bw_a.r * land_mask;
		if (hero_area > 0.001) {
			float footing = texture(hero_ground_contact, hero_uv).r;
			float mineral = smoothstep(0.22, 0.82, macro_b * 0.57 + w_rock * 0.54);
			float grain = value_noise(v_world_pos.xz * 42.0) - 0.5;
			float bedding = value_noise(vec2(v_world_pos.x * 20.0, v_world_pos.y * 67.0)) - 0.5;
			vec3 sediment = mix(hero_sand_color.rgb, hero_rock_color.rgb, mineral * 0.76);
			sediment *= 0.90 + 0.19 * macro_a + 0.19 * grain + 0.11 * mineral * bedding;
			sediment *= mix(vec3(1.0), vec3(0.76, 0.78, 0.85), deep_valley * 0.47);
			col = mix(col, sediment, hero_area * mix(0.61, 0.27, atlas_blend));
			col *= mix(vec3(1.0), vec3(0.66, 0.65, 0.71), footing * hero_area * 0.69);
			vec3 ceramic_grain = texture(tile_normal_array, vec3(organic_uv * 1.66, 0.0)).rgb * 2.0 - 1.0;
			nrm = mix(nrm, ceramic_grain, hero_area * 0.29 * (1.0 - atlas_blend));
		}
	}

	float sculpted_occlusion = 1.0;
	if (sculpted_weight > 0.0) {
		vec3 pigments = texture(sculpted_albedo, chunk_uv).rgb;
		vec2 grain_xy = texture(sculpted_normal, chunk_uv).rg * 2.0 - 1.0;
		vec3 grain = vec3(grain_xy.x, -grain_xy.y, sqrt(max(0.0, 1.0 - dot(grain_xy, grain_xy))));
		col = mix(col, pigments, sculpted_weight);
		nrm = mix(nrm, grain, sculpted_weight);
		sculpted_occlusion = mix(1.0, texture(sculpted_ao, chunk_uv).r, sculpted_weight);
	}

	// 4. Dual-State Zoom Adaptation: Close-Up Living Watercolor (0.0) <-> Overview Royal Parchment Atlas (1.0)
	float luma_pre = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 royal_vellum = vec3(luma_pre * 1.05, luma_pre * 0.98, luma_pre * 0.85);
	vec3 atlas_col = mix(col, royal_vellum, 0.30);
	atlas_col = mix(atlas_col, vec3(0.835, 0.772, 0.648), 0.11);
	col = mix(col, atlas_col, smoothstep(0.14, 0.95, atlas_blend));

	// Anti-aliased hand-inked cartographic elevation contour lines (fwidth-filtered, zero shimmer)
	float contour_vis = smoothstep(0.28, 0.90, atlas_blend) * smoothstep(0.06, 0.16, v_world_pos.y);
	if (contour_vis > 0.01) {
		float cy_min = v_world_pos.y * 10.5;
		float fw_min = max(fwidth(cy_min), 0.0012);
		float line_min = 1.0 - smoothstep(0.55, 1.42, abs(fract(cy_min - 0.5) - 0.5) / fw_min);

		float cy_maj = v_world_pos.y * 3.5;
		float fw_maj = max(fwidth(cy_maj), 0.0012);
		float line_maj = 1.0 - smoothstep(0.65, 1.62, abs(fract(cy_maj - 0.5) - 0.5) / fw_maj);

		float ink_w = clamp(line_min * 0.24 + line_maj * 0.38, 0.0, 0.48) * contour_vis;
		col = mix(col, vec3(0.32, 0.23, 0.14), ink_w);
	}

	// Submerged seabed tint beneath OceanPlane
	if (v_world_pos.y < sea_level + 0.010) {
		float depth_t = clamp((sea_level + 0.010 - v_world_pos.y) / 0.22, 0.0, 1.0);
		vec3 seabed_col = mix(vec3(0.70, 0.68, 0.56), vec3(0.18, 0.30, 0.37), depth_t);
		col = mix(col, seabed_col, smoothstep(sea_level + 0.010, sea_level - 0.018, v_world_pos.y));
	}

	// 5. Smooth Zero-Staircase Anti-Aliased Matte Antique-Gold Borders (STRICTLY NO WHITE OVEREXPOSURE!)
	bool is_playable = (r_id > 0);
	bool is_active_cont = (active_continent_idx == 0)
		|| (c_id == active_continent_idx)
		|| (crossing_continent_idx > 0 && c_id == crossing_continent_idx);

	int hl_target_id = 0;
	bool hl_match_cont = false;
	if (active_continent_idx == 0 && hovered_continent_idx > 0) {
		hl_target_id = hovered_continent_idx;
		hl_match_cont = true;
	} else if (hovered_region_idx > 0) {
		hl_target_id = hovered_region_idx;
		hl_match_cont = false;
	} else if (selected_region_idx > 0) {
		hl_target_id = selected_region_idx;
		hl_match_cont = false;
	}

	vec3 emission = vec3(0.0);

	// Rest-state silky hairline antique-gold internal borders between playable regions
	if (is_playable && is_active_cont) {
		float rest_r = mix(1.55, 2.55, atlas_blend);
		float same_cov = smooth_id_coverage(world_uv, r_id, false, rest_r);
		float play_cov = smooth_playable_coverage(world_uv, rest_r);
		float internal_line = smoothstep(0.92, 0.42, same_cov) * smoothstep(0.84, 0.98, play_cov);
		if (sculpted_terrain && c_id == 1) {
			internal_line = 0.0;
		}
		if (internal_line > 0.01) {
			vec3 rest_gold = mix(vec3(0.62, 0.47, 0.22), vec3(0.76, 0.59, 0.28), atlas_blend);
			col = mix(col, rest_gold, internal_line * mix(0.46, 0.68, atlas_blend));
			emission += rest_gold * (0.05 * internal_line);
		}
	}

	// Harmonious cool-sepia receding on peripheral unplayable lands & inactive continents
	if (!is_playable && v_world_pos.y >= sea_level) {
		float periph_dim = (active_continent_idx == 0) ? 0.85 : 0.66;
		float pl = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(vec3(pl * 0.97, pl * 0.91, pl * 0.80), col, 0.50) * periph_dim;
	} else if (is_playable && !is_active_cont) {
		float il = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(vec3(il * 0.95, il * 0.90, il * 0.82), col, 0.42) * 0.68;
	}

	// Smooth C1 antique-gold hover/selection border & gentle warm glaze (capped brightness — zero blown-out white!)
	if (hl_target_id > 0) {
		float hl_r = mix(1.85, 3.10, atlas_blend);
		float hl_cov = smooth_id_coverage(world_uv, hl_target_id, hl_match_cont, hl_r);
		if (hl_cov > 0.01) {
			float pulse = 0.5 + 0.5 * hover_pulse;
			// Soft interior warm golden glaze strictly inside the territory
			float inside_mask = smoothstep(0.46, 0.86, hl_cov);
			float fill_str = (hovered_region_idx > 0 || hl_match_cont) ? 0.095 : 0.075;
			col = mix(col, vec3(0.92, 0.81, 0.54), inside_mask * (fill_str + 0.02 * pulse));
			emission += vec3(0.55, 0.40, 0.14) * (inside_mask * (0.04 + 0.015 * pulse));

			// Silky anti-aliased matte antique-gold hairline border right along the C1 0.5 contour!
			float border_band = smoothstep(0.14, 0.46, hl_cov) * (1.0 - smoothstep(0.54, 0.86, hl_cov));
			float border_str = clamp(border_band * 1.45, 0.0, 1.0);
			vec3 antique_gold = vec3(0.84, 0.62, 0.22);
			col = mix(col, antique_gold, border_str * 0.86);
			// Strictly capped emission (<= 0.24) so steep sunlit ridges NEVER clip to pure white!
			emission += vec3(0.24, 0.16, 0.04) * (border_str * (0.85 + 0.22 * pulse));
		}
	}

	// M4 Drifting Soft Cloud Shadows & Regional Milis Monsoon Wetness (6..8月 rain season)
	float cloud_drift = fbm_macro(v_world_pos.xz * 0.30 + vec2(TIME * 0.018, TIME * 0.009));
	float is_milis_wet = clamp(bw_a.g * 1.15 + ((c_id == 2) ? 0.85 : 0.0), 0.0, 1.0);
	float local_rain = clamp(wetness_boost * is_milis_wet + rain_cloud_boost * is_milis_wet * 0.65, 0.0, 1.0);
	float cloud_sh = smoothstep(0.47 - local_rain * 0.16, 0.76 - local_rain * 0.08, cloud_drift);
	float eff_cloud = cloud_shadow_strength * (1.0 + local_rain * 0.95) * mix(1.0, 0.75, atlas_blend);
	col = mix(col, col * vec3(0.73, 0.80, 0.91), cloud_sh * eff_cloud);

	float rough = mix(0.84, 0.91, atlas_blend);
	rough = mix(rough, 0.76, w_road * 0.55 + w_snow * 0.35);
	float spec = mix(0.22, 0.14, atlas_blend);
	if (local_rain > 0.001) {
		col = mix(col, col * vec3(0.76, 0.86, 0.85), local_rain * 0.58);
		rough = mix(rough, 0.28, local_rain * 0.75);
		spec = mix(spec, 0.48, local_rain * 0.75);
	}

	if (sculpted_weight > 0.0) {
		float matte = clamp(texture(sculpted_roughness, chunk_uv).r, 0.76, 0.94);
		rough = mix(rough, matte, sculpted_weight);
	}
	AO = sculpted_occlusion;
	ALBEDO = col;
	EMISSION = emission;
	NORMAL_MAP = normalize(nrm) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = mix(0.62, 0.22, atlas_blend) + hero_area * 0.14 * (1.0 - atlas_blend);
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = spec;
}
