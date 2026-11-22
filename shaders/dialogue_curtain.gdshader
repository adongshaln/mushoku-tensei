shader_type canvas_item;

// Full-width cinematic feathered bottom curtain for modern light-novel ADV reading.
// Smoothly dissolves upward into total transparency with micro-dithered warmth (zero banding, zero hard seam).
uniform vec4 deep_tone : source_color = vec4(0.070, 0.046, 0.032, 0.86);
uniform vec4 mid_tone : source_color = vec4(0.104, 0.070, 0.048, 0.68);
uniform float center_focus : hint_range(0.0, 0.35) = 0.11;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float v = UV.y;
	// Silky multi-stage vertical feather: invisible top veil -> soft speaker mist -> rich warm espresso floor.
	float upper = smoothstep(0.0, 0.28, v);
	float lower = smoothstep(0.14, 0.56, v);
	float curve = mix(upper * upper * 0.68, 1.0, lower);

	// Gently breathe airier at extreme left/right film margins, slightly richer under the central 72% text column.
	float horiz_dist = abs(UV.x - 0.5) * 2.0;
	float edge_lift = 1.0 - smoothstep(0.62, 1.0, horiz_dist) * center_focus;

	vec3 col = mix(mid_tone.rgb, deep_tone.rgb, smoothstep(0.16, 0.78, v));
	// Microscopic warm dithering to prevent 8-bit gradient banding.
	float dither = (hash12(FRAGCOORD.xy) - 0.5) * 0.008;
	float alpha = clamp(curve * deep_tone.a * edge_lift + dither * curve, 0.0, 0.90);

	COLOR = vec4(col + vec3(dither * 0.35), alpha);
}
