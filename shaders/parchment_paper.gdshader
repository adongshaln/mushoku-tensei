shader_type canvas_item;
render_mode unshaded;

uniform vec2 panel_size = vec2(320.0, 200.0);
uniform float grain_strength = 0.05;
uniform float fiber_strength = 0.032;
uniform float edge_warmth = 0.16;
uniform float sheen_strength = 0.06;
uniform float inner_line = 1.0;
uniform vec4 inner_line_color : source_color = vec4(0.42, 0.30, 0.19, 0.15);

varying vec2 pixel_pos;

void vertex() {
	pixel_pos = VERTEX;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 size = max(panel_size, vec2(1.0));
	vec2 uv = clamp(pixel_pos / size, vec2(0.0), vec2(1.0));
	float grain = hash21(floor(pixel_pos * 1.6)) - 0.5;
	float fiber = hash21(floor(vec2(pixel_pos.x * 0.32, pixel_pos.y * 2.4))) - 0.5;
	vec3 col = COLOR.rgb * (1.0 + grain * grain_strength + fiber * fiber_strength);
	vec2 dist = min(uv, vec2(1.0) - uv);
	float edge = 1.0 - smoothstep(0.0, 0.085, min(dist.x, dist.y));
	col = mix(col, col * vec3(0.90, 0.82, 0.64), edge * edge_warmth);
	col += sheen_strength * pow(1.0 - uv.y, 2.0) * vec3(0.10, 0.085, 0.055);
	if (inner_line > 0.5) {
		vec2 inset = pixel_pos - vec2(5.0);
		vec2 inner_size = size - vec2(10.0);
		vec2 d = min(inset, inner_size - inset);
		float distance_to_line = min(d.x, d.y);
		float line = 1.0 - smoothstep(0.0, max(1.2, fwidth(distance_to_line)), abs(distance_to_line));
		float inside = step(0.0, inset.x) * step(0.0, inset.y)
			* step(inset.x, inner_size.x) * step(inset.y, inner_size.y);
		col = mix(col, inner_line_color.rgb, line * inside * inner_line_color.a);
	}
	COLOR = vec4(col, COLOR.a);
}
