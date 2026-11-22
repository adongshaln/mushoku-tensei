shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// 0 = Slender gilded calligraphy ribbon, 1 = Hub-transfer sea-mist dashed preview, 2 = Walked sepia trail
uniform int line_mode = 0;
uniform vec4 base_color : source_color = vec4(0.925, 0.765, 0.395, 0.95);
uniform vec4 glow_color : source_color = vec4(1.0, 0.935, 0.720, 1.0);
uniform vec4 ink_color : source_color = vec4(0.320, 0.205, 0.112, 0.48);
uniform float flow_speed = 1.45;
uniform float dash_freq = 3.2;
uniform float dash_duty = 0.56;
uniform float fade_alpha : hint_range(0.0, 1.0) = 1.0;
uniform bool tapered_ends = false;

void fragment() {
	// UV.x = distance along spline (world units); UV.y = across ribbon [0..1], center = 0.5
	float d = abs(UV.y - 0.5) * 2.0;

	if (line_mode == 0) {
		// Slender feathered gilded ink silk ribbon — soft warm-umber drop halo, ZERO heavy black outline!
		float outer_feather = 1.0 - smoothstep(0.45, 1.0, d);
		float gold_core = 1.0 - smoothstep(0.18, 0.68, d);
		float inner_glint = 1.0 - smoothstep(0.0, 0.36, d);

		// Graceful forward-flowing warm antique-gold shimmer wave
		float wave_phase = fract(UV.x * 0.65 - TIME * flow_speed * 0.42);
		float pulse = exp(-pow((wave_phase - 0.5) * 4.8, 2.0));
		float micro_sheen = 0.5 + 0.5 * sin(UV.x * 9.0 - TIME * flow_speed * 2.4);

		vec3 col = mix(ink_color.rgb, base_color.rgb, smoothstep(0.05, 0.55, gold_core));
		col = mix(col, glow_color.rgb, clamp(inner_glint * (0.26 + 0.58 * pulse + 0.12 * micro_sheen), 0.0, 0.92));
		float alpha = outer_feather * mix(ink_color.a * 0.62, base_color.a, gold_core);
		if (tapered_ends) {
			alpha *= smoothstep(0.0, 0.028, UV2.x);
		}
		ALBEDO = col;
		ALPHA = clamp(alpha, 0.0, 0.96) * fade_alpha;
	} else if (line_mode == 1) {
		// Remaining post-transfer preview: slender translucent sea-mist dashed thread
		float core_mask = 1.0 - smoothstep(0.16, 0.78, d);
		float edge_soft = 1.0 - smoothstep(0.42, 1.0, d);
		float phase = fract(UV.x * dash_freq - TIME * flow_speed * 0.22);
		float dash = smoothstep(0.05, 0.18, phase) * (1.0 - smoothstep(dash_duty - 0.10, dash_duty + 0.05, phase));
		float shimmer = 0.88 + 0.12 * sin(UV.x * 4.5 - TIME * 2.2);
		vec3 col = mix(ink_color.rgb, base_color.rgb, core_mask) * shimmer;
		col = mix(col, glow_color.rgb, (1.0 - smoothstep(0.0, 0.32, d)) * 0.32);
		ALBEDO = col;
		ALPHA = edge_soft * dash * base_color.a * fade_alpha;
	} else {
		// Walked footprint trail: delicate muted warm sepia dashes trailing smoothly behind the pawn
		float core_mask = 1.0 - smoothstep(0.14, 0.84, d);
		float phase = fract(UV.x * dash_freq);
		float step_mark = smoothstep(0.10, 0.24, phase) * (1.0 - smoothstep(dash_duty - 0.08, dash_duty + 0.06, phase));
		ALBEDO = mix(ink_color.rgb, base_color.rgb, core_mask * 0.72);
		ALPHA = core_mask * step_mark * base_color.a * 0.82 * fade_alpha;
	}
}
