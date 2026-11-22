shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Zero-light additive volumetric lighthouse cone (Feathered axially & radially)
uniform vec3 beam_color : source_color = vec3(1.0, 0.78, 0.36);
uniform float beam_intensity : hint_range(0.0, 3.0) = 0.35;

void fragment() {
	float along = clamp(UV.y, 0.0, 1.0);
	float axial_fade = smoothstep(0.0, 0.11, along) * pow(1.0 - along, 1.85);
	float edge_feather = pow(clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 1.45);
	float shimmer = 0.93 + 0.07 * sin(TIME * 2.1 + along * 5.2);
	float strength = axial_fade * edge_feather * beam_intensity * shimmer;

	ALBEDO = beam_color * strength * 0.58;
	ALPHA = clamp(strength * 0.48, 0.0, 0.62);
}
