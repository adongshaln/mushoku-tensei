shader_type canvas_item;
render_mode unshaded;

uniform vec2 panel_size = vec2(220.0, 56.0);
uniform float hover_amount = 0.0;
uniform float sheen_progress = -0.6;
uniform vec4 sheen_color : source_color = vec4(1.0, 0.89, 0.64, 0.42);
uniform float grain_strength = 0.036;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 sz = max(panel_size, vec2(1.0));
	vec2 uv = clamp(local_pos / sz, vec2(0.0), vec2(1.0));
	vec4 base = COLOR;
	float grain = (hash21(floor(local_pos * 1.4)) - 0.5) * grain_strength;
	vec3 col = base.rgb * (1.0 + grain);
	// Soft top bevel catchlight and lower depth shading.
	float top_gloss = smoothstep(0.45, 0.0, uv.y) * 0.11;
	float bottom_shade = smoothstep(0.55, 1.0, uv.y) * 0.10;
	col += vec3(1.0, 0.94, 0.82) * (top_gloss + hover_amount * 0.06);
	col -= vec3(0.14, 0.09, 0.05) * bottom_shade;
	// Subtle diagonal golden sheen sweep on hover.
	float diag = uv.x * 0.82 + uv.y * 0.34;
	float band = exp(-pow((diag - sheen_progress) / 0.13, 2.0));
	col += sheen_color.rgb * band * sheen_color.a * (0.28 + hover_amount * 0.72);
	// Delicate inner top highlight rim.
	float top_rim = 1.0 - smoothstep(1.0, 2.6, local_pos.y);
	float side_fade = smoothstep(0.0, 0.12, uv.x) * smoothstep(1.0, 0.88, uv.x);
	col += vec3(1.0, 0.90, 0.68) * top_rim * side_fade * (0.14 + hover_amount * 0.14);
	COLOR = vec4(col, base.a);
}
