shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D heightmap_tex : hint_default_black, filter_linear, repeat_disable;
uniform float min_height = -0.295;
uniform float max_height = 1.25;
uniform float sea_level = 0.0;

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

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float h_norm = texture(heightmap_tex, UV).r;
	float terrain_y = min_height + h_norm * (max_height - min_height);
	float depth = max(0.0, sea_level - terrain_y);

	// Antique royal nautical chart depth gradient
	vec3 shallow_col = vec3(0.555, 0.715, 0.705);
	vec3 mid_col = vec3(0.325, 0.495, 0.562);
	vec3 deep_col = vec3(0.205, 0.352, 0.438);

	float t_mid = smoothstep(0.015, 0.115, depth);
	float t_deep = smoothstep(0.105, 0.245, depth);
	vec3 water = mix(shallow_col, mid_col, t_mid);
	water = mix(water, deep_col, t_deep);

	// Subtle sunlit antique coastal bathymetry contour + gentle animated shoreline foam
	float wave = sin(depth * 95.0 - TIME * 1.15 + value_noise(v_world_pos.xz * 2.8) * 3.2) * 0.5 + 0.5;
	float shore_band = (1.0 - smoothstep(0.004, 0.048, depth)) * smoothstep(0.0, 0.006, depth);
	float outer_contour = exp(-pow((depth - 0.055) / 0.014, 2.0)) * 0.32;
	water = mix(water, vec3(0.89, 0.87, 0.79), shore_band * (0.42 + 0.24 * wave) + outer_contour * 0.22);

	// Subtle cartographic parchment-vellum grain + delicate nautical latitude/longitude lines
	float paper_grain = value_noise(v_world_pos.xz * 14.0) * 0.65 + value_noise(v_world_pos.xz * 42.0) * 0.35;
	water *= 0.965 + paper_grain * 0.06;

	vec2 grid_p = abs(fract(v_world_pos.xz * 0.45 + 0.5) - 0.5) / 0.45;
	float chart_line = (1.0 - smoothstep(0.0, 0.018, min(grid_p.x, grid_p.y))) * smoothstep(0.05, 0.14, depth);
	water = mix(water, vec3(0.76, 0.71, 0.56), chart_line * 0.10);

	// Gentle specular shimmer on open water
	float ripple_n = value_noise(v_world_pos.xz * 5.2 + vec2(TIME * 0.08, -TIME * 0.05));
	ALBEDO = water;
	ROUGHNESS = mix(0.30, 0.46, ripple_n * 0.55 + shore_band * 0.45);
	METALLIC = 0.04;
	SPECULAR = 0.42;
}
