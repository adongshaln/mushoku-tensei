shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// Migurd Village Hidden Crater Basin Mist (drifting warm ivory-ochre gauze, zero UI/village blocking)
uniform vec3 mist_color : source_color = vec3(0.90, 0.84, 0.75);
uniform float opacity : hint_range(0.0, 0.7) = 0.24;
uniform float drift_phase = 0.0;

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
	vec2 centered = UV * 2.0 - 1.0;
	float r = length(centered);
	// Ring-soft hollow around the village rooftops so houses stay crisp while crater edges & valley mist swirl
	float outer_fade = smoothstep(0.98, 0.42, r);
	float center_clear = mix(0.45, 1.0, smoothstep(0.06, 0.36, r));
	vec2 flow_uv = UV * 3.2 + vec2(TIME * 0.022 + drift_phase, -TIME * 0.016 + drift_phase * 0.5);
	float swirl = vnoise(flow_uv) * 0.62 + vnoise(flow_uv * 2.1 - vec2(TIME * 0.03, 0.0)) * 0.38;
	float alpha = outer_fade * center_clear * smoothstep(0.24, 0.76, swirl) * opacity;

	ALBEDO = mist_color;
	ALPHA = clamp(alpha, 0.0, 0.42);
}
