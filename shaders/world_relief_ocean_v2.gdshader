shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Single heightmap sampler — zero depth-buffer / SSR overhead, Android 60FPS single-pass
uniform sampler2D heightmap_tex : hint_default_black, filter_linear, repeat_disable;
uniform float min_height = -0.295;
uniform float max_height = 1.359;
uniform float sea_level = 0.0;
uniform float atlas_blend : hint_range(0.0, 1.0) = 1.0;
uniform float cloud_shadow_strength : hint_range(0.0, 0.6) = 0.22;
uniform float rain_cloud_boost : hint_range(0.0, 1.0) = 0.0;

uniform int sculpted_count = 0;
uniform vec4 sculpted_rects[12];
uniform sampler2DArray sculpted_depth : filter_linear, repeat_disable;

varying vec3 v_world_pos;

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

float fbm2(vec2 p) {
	return value_noise(p) * 0.64 + value_noise(p * 2.13 + vec2(5.7, -3.4)) * 0.36;
}

float fbm_cloud(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 3; i++) {
		v += a * value_noise(p);
		p = p * 2.07 + vec2(13.1, 7.9);
		a *= 0.48;
	}
	return v;
}

float water_wave_height(vec2 xz, float t) {
	float w1 = value_noise(xz * 8.4 + vec2(t * 0.22, -t * 0.15));
	float w2 = value_noise(xz * 16.5 + vec2(-t * 0.18, t * 0.24) + vec2(9.2, 4.1));
	return w1 * 0.58 + w2 * 0.42;
}

// Procedural antique 16-point cartographic compass rose & radiating rhumb lines in open Ringus Sea
float compass_rose_pattern(vec2 p, float depth_mask) {
	if (depth_mask <= 0.005) {
		return 0.0;
	}
	float r = length(p);
	float ang = atan(p.y, p.x);

	float rhumb_phase = abs(sin(ang * 8.0));
	float fw_rhumb = max(fwidth(ang * 8.0), 0.004);
	float rhumb_line = (1.0 - smoothstep(0.0, fw_rhumb * 1.35, rhumb_phase))
		* smoothstep(0.28, 0.42, r) * (1.0 - smoothstep(1.9, 4.4, r));

	float fw_r = max(fwidth(r), 0.003);
	float ring_outer = 1.0 - smoothstep(0.010, 0.010 + fw_r * 1.5, abs(r - 1.18));
	float ring_mid = 1.0 - smoothstep(0.007, 0.007 + fw_r * 1.4, abs(r - 1.06));
	float ring_inner = 1.0 - smoothstep(0.007, 0.007 + fw_r * 1.4, abs(r - 0.34));

	float ticks = (1.0 - smoothstep(0.0, max(fwidth(ang * 32.0), 0.01) * 1.2, abs(sin(ang * 32.0))))
		* step(1.06, r) * step(r, 1.18);

	float a4 = mod(ang + 3.14159265, 1.57079633) - 0.78539816;
	float star4_edge = 1.02 * (1.0 - clamp(abs(a4) / 0.24, 0.0, 1.0));
	float star4 = (1.0 - smoothstep(star4_edge - fw_r * 1.6, star4_edge + fw_r * 1.6, r)) * step(r, 1.05);
	float star4_shade = star4 * (a4 > 0.0 ? 0.92 : 0.42);

	float a8 = mod(ang + 3.14159265 + 0.78539816, 1.57079633) - 0.78539816;
	float star8_edge = 0.68 * (1.0 - clamp(abs(a8) / 0.20, 0.0, 1.0));
	float star8 = (1.0 - smoothstep(star8_edge - fw_r * 1.6, star8_edge + fw_r * 1.6, r)) * step(r, 0.72);
	float star8_shade = star8 * (a8 > 0.0 ? 0.74 : 0.34);

	float center_dot = 1.0 - smoothstep(0.06, 0.06 + fw_r * 1.6, r);

	float ink = max(max(ring_outer * 0.85, ring_mid * 0.55), max(ring_inner * 0.60, ticks * 0.45));
	ink = max(ink, max(star4_shade * 0.92, star8_shade * 0.72));
	ink = max(ink, max(center_dot * 0.85, rhumb_line * 0.32));
	return ink * depth_mask;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float h_norm = texture(heightmap_tex, UV).r;
	float terrain_y = min_height + h_norm * (max_height - min_height);
	float sculpted_shore = 0.0;
	for (int j = 0; j < sculpted_count; j++) {
		vec4 rect = sculpted_rects[j];
		vec2 local = (v_world_pos.xz - rect.xy) / (rect.zw - rect.xy);
		if (all(greaterThanEqual(local, vec2(0.0))) && all(lessThanEqual(local, vec2(1.0)))) {
			vec2 dimensions = vec2(textureSize(sculpted_depth, 0).xy);
			vec2 texel_uv = (local * (dimensions - 1.0) + 0.5) / dimensions;
			terrain_y = texture(sculpted_depth, vec3(texel_uv, float(j))).r;
			sculpted_shore = 1.0;
			break;
		}
	}
	float depth = max(0.0, sea_level - terrain_y);

	// 1. Lucid Water Depth Bands: Clear turquoise shallows -> Coastal cerulean -> Vintage Sea-Mist Deep Blue
	vec3 shallow_aqua = vec3(0.31, 0.59, 0.55);
	vec3 coastal_cerulean = vec3(0.275, 0.515, 0.585);
	vec3 mid_seamist = vec3(0.195, 0.365, 0.468);
	vec3 deep_seamist = vec3(0.08, 0.18, 0.275);

	float t_coastal = smoothstep(0.008, 0.056, depth);
	float t_mid = smoothstep(0.050, 0.145, depth);
	float t_deep = smoothstep(0.138, 0.270, depth);
	vec3 water = mix(shallow_aqua, coastal_cerulean, t_coastal);
	water = mix(water, mid_seamist, t_mid);
	water = mix(water, deep_seamist, t_deep);

	// Subtle layered open-sea watercolor current depth & gentle sunlit water dapples
	float sea_wash = fbm2(v_world_pos.xz * 0.48);
	float current_sheen = value_noise(v_world_pos.xz * 2.4 + vec2(TIME * 0.05, -TIME * 0.04));
	water *= mix(0.93, 1.07, sea_wash);
	water += vec3(0.025, 0.045, 0.052) * smoothstep(0.58, 0.88, current_sheen) * smoothstep(0.06, 0.18, depth) * (1.0 - atlas_blend * 0.55);

	// 2. Crisp Hand-Painted Shoreline Surf Lines (2 slender organically broken gouache arcs — ZERO fuzzy airbrush halo!)
	float surf_mask = 0.0;
	if (depth < 0.095) {
		float flow = fbm2(v_world_pos.xz * 4.4 + vec2(TIME * 0.06, -TIME * 0.05));
		float break_a = smoothstep(0.30, 0.68, value_noise(v_world_pos.xz * 8.6 + vec2(-TIME * 0.09, TIME * 0.07)));
		float break_b = smoothstep(0.34, 0.72, value_noise(v_world_pos.xz * 10.5 + vec2(TIME * 0.07, TIME * 0.08) + vec2(4.1, -2.7)));

		// Animate 2 crisp thin surf lines gliding gently shoreward across [0.008 .. 0.068]
		float d_warped = depth + (flow - 0.5) * 0.016;
		float wave_t1 = fract(d_warped * 24.0 + TIME * 0.24);
		float wave_t2 = fract(d_warped * 24.0 + TIME * 0.24 + 0.52);

		// Sharp Wind-Waker / hand-painted gouache stroke thickness (crisp edge, never blurry fog!)
		float fw_d = max(fwidth(d_warped * 24.0), 0.018);
		float line1 = (1.0 - smoothstep(0.04, 0.04 + fw_d * 1.8, abs(wave_t1 - 0.5)))
			* smoothstep(0.006, 0.016, depth) * (1.0 - smoothstep(0.046, 0.076, depth)) * (0.28 + 0.72 * break_a);
		float line2 = (1.0 - smoothstep(0.032, 0.032 + fw_d * 1.8, abs(wave_t2 - 0.5)))
			* smoothstep(0.004, 0.014, depth) * (1.0 - smoothstep(0.034, 0.062, depth)) * (0.22 + 0.78 * break_b);

		// Razor-crisp shore contact waterline kiss strictly at depth < 0.0065
		float shore_edge = (1.0 - smoothstep(0.002, 0.0075, depth)) * (0.65 + 0.35 * break_a);

		surf_mask = clamp(max(max(line1 * 0.88, line2 * 0.72), shore_edge * 0.78), 0.0, 0.92);
		vec3 gouache_foam = vec3(0.955, 0.945, 0.902);
		water = mix(water, gouache_foam, surf_mask * (0.66 + 0.16 * sin(TIME * 1.15 + flow * 4.2)));
	}

	// 3. Antique Nautical Chart Layer (Zoom-Adaptive: crisp folio chart at overview, soft ghostly watermark up close!)
	float chart_vis = smoothstep(0.42, 0.90, atlas_blend);

	float vellum_grain = value_noise(v_world_pos.xz * 20.0) * 0.6 + value_noise(v_world_pos.xz * 52.0) * 0.4;
	water *= mix(0.975, 1.025, vellum_grain);
	water = mix(water, mix(water, vec3(0.26, 0.41, 0.47), 0.20), atlas_blend * 0.52);

	// Ornate Vintage Compass Rose placed cleanly in open Ringus Sea (zero landmass overlap)
	float open_sea_mask = smoothstep(0.115, 0.215, depth);
	float compass_ink = compass_rose_pattern(v_world_pos.xz - vec2(0.55, 0.12), open_sea_mask);

	vec3 chart_gold = vec3(0.84, 0.73, 0.48);
	float total_chart_ink = clamp(compass_ink * 0.48, 0.0, 0.56) * chart_vis;
	water = mix(water, chart_gold, total_chart_ink);
	vec3 emission = chart_gold * (compass_ink * 0.09 * chart_vis);
	emission += vec3(0.040, 0.049, 0.047) * surf_mask * sculpted_shore * (1.0 - 0.45 * atlas_blend);

	// 4. Synchronized Drifting Cloud Shadows over Sea & Studio HDRI Specular Shimmer
	float cloud_drift = fbm_cloud(v_world_pos.xz * 0.30 + vec2(TIME * 0.018, TIME * 0.009));
	float milis_sea = smoothstep(0.2, 2.2, v_world_pos.x) * smoothstep(-0.3, 1.4, v_world_pos.z);
	float local_rain = rain_cloud_boost * milis_sea;
	float cloud_sh = smoothstep(0.49 - local_rain * 0.14, 0.78 - local_rain * 0.08, cloud_drift);
	float eff_cloud = cloud_shadow_strength * (1.0 + local_rain * 0.75) * mix(1.0, 0.72, atlas_blend);
	water = mix(water, water * vec3(0.75, 0.82, 0.93), cloud_sh * eff_cloud);

	float eps = 0.022;
	float hc = water_wave_height(v_world_pos.xz, TIME);
	float hx = water_wave_height(v_world_pos.xz + vec2(eps, 0.0), TIME);
	float hz = water_wave_height(v_world_pos.xz + vec2(0.0, eps), TIME);
	float ripple_amp = mix(0.11, 0.032, atlas_blend) * (1.0 - surf_mask * 0.85);
	vec3 wave_n = normalize(vec3((hc - hx) * ripple_amp / eps * 0.085, (hc - hz) * ripple_amp / eps * 0.085, 1.0));

	ALBEDO = water;
	EMISSION = emission;
	NORMAL_MAP = wave_n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = mix(0.36, 0.14, atlas_blend);
	ROUGHNESS = mix(mix(0.22, 0.44, atlas_blend), 0.78, surf_mask * 0.88);
	METALLIC = 0.05;
	SPECULAR = mix(0.48, 0.24, atlas_blend);
}
