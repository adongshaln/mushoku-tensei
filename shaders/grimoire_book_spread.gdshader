shader_type canvas_item;
render_mode unshaded;

uniform vec2 panel_size = vec2(1460.0, 860.0);
uniform float spine_x = 0.295;
uniform float spine_strength = 0.34;
uniform float show_spine = 1.0;

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
	float grain = hash21(floor(local_pos * 1.5)) - 0.5;
	float fiber = hash21(floor(vec2(local_pos.x * 0.28, local_pos.y * 2.2))) - 0.5;
	vec3 col = COLOR.rgb * (1.0 + grain * 0.044 + fiber * 0.028);

	// Warm desk-lamp illumination from upper left fading softly toward outer edges.
	float lamp = 1.0 - smoothstep(0.0, 0.92, length((uv - vec2(0.28, 0.14)) * vec2(1.15, 0.95)));
	col += vec3(0.055, 0.044, 0.024) * lamp;

	// Aged parchment border darkening.
	vec2 dist = min(uv, vec2(1.0) - uv);
	float edge = 1.0 - smoothstep(0.0, 0.055, min(dist.x, dist.y));
	col = mix(col, col * vec3(0.87, 0.78, 0.61), edge * 0.34);

	// Physical center book-spine gutter shadow and soft page curl highlight.
	if (show_spine > 0.5) {
		float dx = uv.x - spine_x;
		float gutter = exp(-pow(dx / 0.024, 2.0));
		float crease = exp(-pow(dx / 0.0028, 2.0));
		float curl_l = exp(-pow((dx + 0.036) / 0.028, 2.0));
		float curl_r = exp(-pow((dx - 0.036) / 0.028, 2.0));
		col *= 1.0 - gutter * spine_strength - crease * 0.24;
		col += vec3(0.042, 0.034, 0.018) * (curl_l + curl_r);
	}

	// Crisp double-line filigree inset border.
	for (int i = 0; i < 2; i++) {
		float pad = i == 0 ? 7.0 : 12.0;
		vec2 inset = local_pos - vec2(pad);
		vec2 inner = sz - vec2(pad * 2.0);
		vec2 d = min(inset, inner - inset);
		float d_line = min(d.x, d.y);
		float mask = 1.0 - smoothstep(0.0, max(1.1, fwidth(d_line)), abs(d_line));
		float inside = step(0.0, inset.x) * step(0.0, inset.y) * step(inset.x, inner.x) * step(inset.y, inner.y);
		float alpha = i == 0 ? 0.24 : 0.12;
		col = mix(col, vec3(0.54, 0.38, 0.20), mask * inside * alpha);
	}

	COLOR = vec4(col, COLOR.a);
}
