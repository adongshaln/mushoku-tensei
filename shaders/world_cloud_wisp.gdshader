shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// Stylized Soft-Edged Hand-Painted Sky Cloud Wisps (auto-fades on close-up zoom)
uniform vec3 cloud_tint : source_color = vec3(0.98, 0.96, 0.90);
uniform float opacity : hint_range(0.0, 0.8) = 0.22;
uniform float seed_offset = 0.0;
uniform float density_threshold : hint_range(0.2, 0.8) = 0.44;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p * vec2(0.88, 1.15));
	float n = vnoise(UV * 3.8 + vec2(seed_offset, seed_offset * 0.7)) * 0.62
		+ vnoise(UV * 7.6 + vec2(-TIME * 0.025, TIME * 0.015) + vec2(seed_offset)) * 0.38;
	float disc = smoothstep(0.96, 0.24, r + (n - 0.5) * 0.38);
	float wisp = smoothstep(density_threshold - 0.16, density_threshold + 0.22, n * 0.55 + (1.0 - r) * 0.52);
	float alpha = disc * wisp * opacity;

	ALBEDO = cloud_tint;
	ALPHA = clamp(alpha, 0.0, 0.65);
}
