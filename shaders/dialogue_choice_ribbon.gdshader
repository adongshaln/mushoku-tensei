shader_type canvas_item;

// Frameless feathered warm-espresso ribbon with horizontally fading top/bottom antique-gold hairlines.
uniform vec4 base_tone : source_color = vec4(0.094, 0.064, 0.046, 0.84);
uniform vec4 hover_tone : source_color = vec4(0.205, 0.145, 0.092, 0.92);
uniform vec4 gold_line : source_color = vec4(0.878, 0.718, 0.416, 1.0);
uniform float hover_mix : hint_range(0.0, 1.0) = 0.0;
uniform vec2 rect_size = vec2(840.0, 74.0);

void fragment() {
	vec2 uv = UV;
	// Smooth horizontal fade at left & right tips so the ribbon floats weightlessly over the CG.
	float edge_fade = smoothstep(0.0, 0.11, uv.x) * (1.0 - smoothstep(0.89, 1.0, uv.x));
	float line_fade = smoothstep(0.0, 0.18, uv.x) * (1.0 - smoothstep(0.82, 1.0, uv.x));

	// Warm central sheen boost on hover.
	float center_glow = exp(-pow((uv.x - 0.5) * 2.1, 2.0)) * hover_mix * 0.18;
	vec4 bg = mix(base_tone, hover_tone, hover_mix);
	vec3 rgb = bg.rgb + gold_line.rgb * center_glow;
	float alpha = bg.a * edge_fade;

	// Ultra-crisp ~1.25px fading top and bottom antique-gold hairlines.
	float py = uv.y * max(rect_size.y, 1.0);
	float top_line = 1.0 - smoothstep(0.6, 1.75, py);
	float bot_line = 1.0 - smoothstep(0.6, 1.75, max(rect_size.y, 1.0) - py);
	float line_alpha = max(top_line, bot_line) * line_fade * mix(0.46, 0.96, hover_mix);

	vec3 final_rgb = mix(rgb, gold_line.rgb, clamp(line_alpha * 1.1, 0.0, 1.0));
	float final_alpha = max(alpha, line_alpha);

	COLOR = vec4(final_rgb, final_alpha);
}
