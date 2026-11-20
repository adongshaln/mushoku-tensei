shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform float reveal_progress = 1.0;
uniform float falloff = 1.2;
uniform float plateau = 0.62;
uniform vec2 banner_size = vec2(760.0, 104.0);
// 画布直写 sRGB 帧缓冲（无 2D HDR），uniform 直接使用 sRGB 数值：#F5EDE0 / #3B2E25 / #C88A3B。
uniform vec4 band_color = vec4(0.961, 0.929, 0.878, 0.90);
uniform vec4 border_color = vec4(0.231, 0.180, 0.145, 1.0);
uniform vec4 border_glow = vec4(0.788, 0.541, 0.231, 1.0);
uniform float border_width = 2.5;
uniform float grain_strength = 0.035;

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
	float center_dist = abs(UV.x - 0.5) * 2.0;
	float horizontal = pow(1.0 - smoothstep(plateau, 1.0, center_dist), falloff);
	float reveal = 1.0 - smoothstep(reveal_progress - 0.15, reveal_progress, center_dist);
	float strength = horizontal * reveal;

	float grain = (hash21(floor(pixel_pos * 1.7)) - 0.5) * grain_strength;
	vec3 band_rgb = band_color.rgb * (1.0 + grain);
	float band_a = band_color.a * strength;

	float edge_dist = min(pixel_pos.y, banner_size.y - pixel_pos.y);
	float line = 1.0 - smoothstep(border_width - 0.75, border_width + 0.75, edge_dist);
	float core = 1.0 - smoothstep(0.0, 1.2, edge_dist);
	vec3 line_rgb = mix(border_color.rgb, border_glow.rgb, core * 0.55);
	float line_a = line * strength * border_color.a;

	float out_a = line_a + band_a * (1.0 - line_a);
	vec3 out_rgb = line_rgb * line_a + band_rgb * band_a * (1.0 - line_a);
	COLOR = vec4(out_rgb, out_a) * COLOR.a;
}
