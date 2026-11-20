shader_type canvas_item;
render_mode unshaded;

uniform vec2 panel_size = vec2(192.0, 67.0);
uniform vec4 sheen_tone : source_color = vec4(0.85, 0.65, 0.32, 1.0);
varying vec2 panel_pixel;

void vertex() {
	panel_pixel = VERTEX;
}

void fragment() {
	vec2 p = panel_pixel / max(panel_size, vec2(1.0));
	float interior = step(2.0, panel_pixel.x) * step(2.0, panel_pixel.y)
		* step(panel_pixel.x, panel_size.x - 2.0)
		* step(panel_pixel.y, panel_size.y - 2.0);
	float noise = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715)))) - 0.5;
	float gloss = exp(-max(panel_pixel.y - 3.0, 0.0) * 0.18)
		* (1.0 - smoothstep(0.24, 0.60, abs(p.x - 0.5)));
	float air = (1.0 - clamp(p.y, 0.0, 1.0)) * 0.048;
	vec3 frost = mix(COLOR.rgb, sheen_tone.rgb, interior * (gloss * 0.17 + air));
	COLOR = vec4(frost + noise * 0.026 * interior, COLOR.a);
}
