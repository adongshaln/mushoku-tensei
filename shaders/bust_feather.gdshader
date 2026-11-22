shader_type canvas_item;

uniform float uv_y_min : hint_range(0.0, 1.0) = 0.0;
uniform float uv_y_max : hint_range(0.0, 1.0) = 1.0;
uniform float bottom_fade_start : hint_range(0.4, 0.98) = 0.78;
uniform float bottom_fade_end : hint_range(0.5, 1.0) = 0.99;
uniform vec4 rim_tint : source_color = vec4(0.92, 0.78, 0.52, 0.14);

void fragment() {
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	float span = max(uv_y_max - uv_y_min, 0.0001);
	float local_v = clamp((UV.y - uv_y_min) / span, 0.0, 1.0);
	float bottom_mask = 1.0 - smoothstep(bottom_fade_start, bottom_fade_end, local_v);
	// Subtle warm ambient integration near the dialogue-box contact edge.
	float lower_blend = smoothstep(0.62, 0.95, local_v) * rim_tint.a;
	vec3 rgb = mix(tex.rgb, mix(tex.rgb, rim_tint.rgb, 0.35), lower_blend);
	COLOR = vec4(rgb, tex.a * bottom_mask);
}
