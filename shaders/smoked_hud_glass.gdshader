shader_type canvas_item;
render_mode unshaded;

uniform vec2 panel_size = vec2(320.0, 80.0);
uniform vec4 rim_tint : source_color = vec4(0.85, 0.68, 0.38, 0.52);

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.5);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 sz = max(panel_size, vec2(1.0));
	vec2 uv = clamp(local_pos / sz, vec2(0.0), vec2(1.0));
	vec4 base = COLOR;
	float grain = (hash21(floor(local_pos * 1.3)) - 0.5) * 0.04;
	vec3 col = base.rgb * (1.0 + grain);
	// Warm ambient top sheen + subtle espresso edge depth.
	float upper = smoothstep(0.65, 0.0, uv.y);
	col += vec3(0.24, 0.17, 0.10) * upper * 0.28;
	vec2 edge_d = min(uv, vec2(1.0) - uv);
	float edge_glow = 1.0 - smoothstep(0.0, 0.07, min(edge_d.x, edge_d.y));
	col = mix(col, col * 0.82, edge_glow * 0.45);
	// Thin interior gold hairline.
	vec2 inset = local_pos - vec2(4.0);
	vec2 inner = sz - vec2(8.0);
	vec2 d = min(inset, inner - inset);
	float dist = min(d.x, d.y);
	float hairline = 1.0 - smoothstep(0.0, max(1.1, fwidth(dist)), abs(dist));
	float inside = step(0.0, inset.x) * step(0.0, inset.y) * step(inset.x, inner.x) * step(inset.y, inner.y);
	col = mix(col, rim_tint.rgb, hairline * inside * rim_tint.a * 0.45);
	COLOR = vec4(col, base.a);
}
