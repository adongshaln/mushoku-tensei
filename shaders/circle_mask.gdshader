shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float dist = length(UV - vec2(0.5, 0.5));
	float mask = smoothstep(0.495, 0.465, dist);
	COLOR = vec4(tex.rgb, tex.a * mask) * COLOR;
}
