shader_type canvas_item;
render_mode unshaded;

uniform int outline_state = 0;
uniform vec4 outline_color : source_color = vec4(1.0, 0.77, 0.38, 1.0);
uniform vec4 placeholder_color : source_color = vec4(0.59, 0.36, 0.23, 1.0);
uniform bool show_placeholder = false;
uniform bool use_source_color = false;
uniform float flash_strength = 0.0;
uniform float layer_opacity = 1.0;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float center = source.a;
	vec4 pixel = vec4(placeholder_color.rgb, show_placeholder ? center : 0.0);
	if (use_source_color) {
		pixel = vec4(mix(source.rgb, vec3(1.0), flash_strength), center);
	}
	if (outline_state > 0) {
		float radius = outline_state == 2 ? 2.65 : 1.65;
		vec2 step_size = TEXTURE_PIXEL_SIZE * radius;
		float outer = center;
		for (int x = -1; x <= 1; x++) {
			for (int y = -1; y <= 1; y++) {
				if (x != 0 || y != 0) {
					outer = max(outer, texture(TEXTURE, UV + vec2(float(x), float(y)) * step_size).a);
				}
			}
		}
		float pulse = outline_state == 2 ? 0.87 + 0.11 * sin(TIME * 2.5) : 0.57;
		float edge = max(0.0, outer - center) * pulse;
		pixel.rgb = mix(pixel.rgb, outline_color.rgb, outline_color.a * smoothstep(0.0, 0.45, edge));
		pixel.a = max(pixel.a, edge * outline_color.a);
	}
	COLOR = vec4(pixel.rgb, pixel.a * layer_opacity * COLOR.a);
}
