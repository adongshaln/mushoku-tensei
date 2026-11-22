shader_type canvas_item;
render_mode unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ink_color : source_color = vec4(0.10, 0.07, 0.05, 1.0);
uniform vec4 gold_rim : source_color = vec4(0.86, 0.67, 0.36, 1.0);

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.5);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
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
	vec2 uv = UV;
	float n = noise(uv * 6.0) * 0.14 + noise(uv * 16.0) * 0.05;
	// Smooth outer-to-inner warm ink vignette curtain with golden leading edge.
	float dist = length((uv - vec2(0.5, 0.5)) * vec2(1.08, 1.0));
	float field = dist * 0.72 + n;
	float threshold = mix(1.05, -0.25, progress);
	float alpha = smoothstep(threshold - 0.12, threshold + 0.10, field);
	alpha *= smoothstep(0.0, 0.04, progress);
	float edge = exp(-pow((field - threshold) / 0.055, 2.0)) * sin(progress * 3.14159);
	vec3 col = mix(ink_color.rgb, gold_rim.rgb, edge * 0.48);
	COLOR = vec4(col, clamp(alpha, 0.0, 1.0));
}
