shader_type canvas_item;

// Frameless cinematic feathered warm-espresso band with horizontally fading antique-gold top/bottom hairlines.
uniform vec2 banner_size = vec2(780.0, 114.0);
uniform float reveal_progress : hint_range(0.0, 1.0) = 1.0;
uniform vec4 band_tone : source_color = vec4(0.082, 0.055, 0.039, 0.88);
uniform vec4 gold_line : source_color = vec4(0.914, 0.768, 0.455, 1.0);

void fragment() {
	vec2 uv = UV;
	float cx = abs(uv.x - 0.5) * 2.0;

	// Silky horizontal dissolve at both ends + animated center-outward reveal.
	float horiz = 1.0 - smoothstep(0.42, 1.0, cx);
	float reveal = 1.0 - smoothstep(max(reveal_progress - 0.16, 0.0), max(reveal_progress, 0.001), cx);
	float mask = pow(horiz, 1.25) * reveal;

	// Subtle vertical softness at outer edges.
	float vert = smoothstep(0.0, 0.12, uv.y) * (1.0 - smoothstep(0.88, 1.0, uv.y));
	float bg_alpha = band_tone.a * mask * (0.86 + 0.14 * vert);

	// Ultra-fine ~1.35px antique-gold hairlines top and bottom, fading toward both ends.
	float py = uv.y * max(banner_size.y, 1.0);
	float top_l = 1.0 - smoothstep(0.55, 1.75, py);
	float bot_l = 1.0 - smoothstep(0.55, 1.75, max(banner_size.y, 1.0) - py);
	float line_horiz = (1.0 - smoothstep(0.28, 0.96, cx)) * reveal;
	float line_alpha = max(top_l, bot_l) * line_horiz * 0.88;

	// Soft golden sheen right under the center star.
	float center_glow = exp(-pow(cx * 2.8, 2.0)) * 0.10 * reveal;
	vec3 bg_rgb = band_tone.rgb + gold_line.rgb * center_glow;
	vec3 final_rgb = mix(bg_rgb, gold_line.rgb, clamp(line_alpha * 1.15, 0.0, 1.0));
	float final_alpha = max(bg_alpha, line_alpha);

	COLOR = vec4(final_rgb, final_alpha) * COLOR.a;
}
