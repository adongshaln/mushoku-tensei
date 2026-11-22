shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;

// Soft Grounded Contact Shadow under Moving 3D Pawns
uniform vec3 shadow_color : source_color = vec3(0.14, 0.10, 0.08);
uniform float shadow_opacity : hint_range(0.0, 0.9) = 0.42;

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float r = length(centered);
	float alpha = smoothstep(0.96, 0.22, r) * shadow_opacity;
	ALBEDO = shadow_color;
	ALPHA = alpha;
}
