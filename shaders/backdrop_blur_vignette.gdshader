shader_type canvas_item;
render_mode unshaded;

uniform sampler2D scene_color : hint_screen_texture, filter_linear_mipmap, repeat_disable;

void fragment() {
	vec2 p = SCREEN_UV - vec2(0.5, 0.46);
	float falloff = smoothstep(0.10, 0.68, length(p * vec2(1.0, 1.06)));
	vec2 radius = vec2(7.5, 6.0) * SCREEN_PIXEL_SIZE * mix(0.85, 1.45, falloff);
	float lod = mix(2.15, 3.10, falloff);
	vec3 art = textureLod(scene_color, SCREEN_UV, lod).rgb * 0.24;
	art += textureLod(scene_color, SCREEN_UV + vec2(radius.x, 0.0), lod).rgb * 0.13;
	art += textureLod(scene_color, SCREEN_UV - vec2(radius.x, 0.0), lod).rgb * 0.13;
	art += textureLod(scene_color, SCREEN_UV + vec2(0.0, radius.y), lod).rgb * 0.13;
	art += textureLod(scene_color, SCREEN_UV - vec2(0.0, radius.y), lod).rgb * 0.13;
	art += textureLod(scene_color, SCREEN_UV + radius, lod).rgb * 0.06;
	art += textureLod(scene_color, SCREEN_UV - radius, lod).rgb * 0.06;
	art += textureLod(scene_color, SCREEN_UV + vec2(radius.x, -radius.y), lod).rgb * 0.06;
	art += textureLod(scene_color, SCREEN_UV + vec2(-radius.x, radius.y), lod).rgb * 0.06;
	float gray = dot(art, vec3(0.299, 0.587, 0.114));
	art = mix(art, vec3(gray), 0.16 + falloff * 0.18);
	vec3 window = art * vec3(0.73, 0.68, 0.61);
	vec3 tint = vec3(0.105, 0.066, 0.043);
	COLOR = vec4(mix(window, tint, 0.13 + falloff * 0.63), COLOR.a);
}
