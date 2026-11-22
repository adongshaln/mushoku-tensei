shader_type canvas_item;
render_mode unshaded;

uniform float hearth_intensity = 0.26;
uniform float night_factor = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(89.17, 217.53));
	p += dot(p, p + 41.2);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;
	// Subtle flickering warm hearth glow centered around the lower-right clay pot & stones.
	float flicker = 0.88 + 0.07 * sin(TIME * 3.7) + 0.05 * sin(TIME * 7.9 + 1.4);
	float hearth_d = length((uv - vec2(0.67, 0.84)) * vec2(1.0, 1.35));
	float hearth = (1.0 - smoothstep(0.02, 0.56, hearth_d)) * flicker * hearth_intensity * (1.0 + night_factor * 0.45);

	// Soft golden window shaft from the left curtain.
	float beam = (1.0 - smoothstep(0.0, 0.42, uv.x + uv.y * 0.22 - 0.14)) * (1.0 - night_factor * 0.72) * 0.09;

	// Floating sunlit dust motes / rising hearth embers.
	vec2 mote_grid = uv * vec2(24.0, 14.0) + vec2(-0.04, 0.12) * TIME;
	vec2 cell = floor(mote_grid);
	vec2 cpos = vec2(hash21(cell), hash21(cell + vec2(11.3, 5.7))) * 0.62 + 0.19;
	float dot_m = 1.0 - smoothstep(0.008, 0.042, length(fract(mote_grid) - cpos));
	float twinkle = 0.35 + 0.65 * sin(TIME * 1.4 + hash21(cell + 9.0) * 6.283);
	float mote_mask = smoothstep(0.04, 0.35, uv.y) * smoothstep(0.98, 0.45, uv.y);
	float mote = dot_m * twinkle * mote_mask * 0.22;

	// Subtle cinematic warm framing vignette.
	float vig = smoothstep(0.46, 0.92, length((uv - vec2(0.5, 0.5)) * vec2(1.05, 1.0)));

	vec3 glow_col = vec3(1.0, 0.68, 0.30) * hearth + vec3(1.0, 0.92, 0.72) * (beam + mote);
	float glow_alpha = clamp(hearth * 0.55 + beam + mote, 0.0, 0.45);
	vec3 final_col = mix(glow_col, vec3(0.08, 0.05, 0.03), vig * 0.42);
	float final_alpha = clamp(glow_alpha + vig * 0.32, 0.0, 0.55);
	COLOR = vec4(final_col, final_alpha);
}
