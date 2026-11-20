shader_type canvas_item;
render_mode unshaded;

uniform sampler2D scene_color : hint_screen_texture, filter_linear_mipmap, repeat_disable;

float grain(vec2 p) {
	return fract(sin(dot(p, vec2(73.81, 193.37))) * 44932.81);
}

void fragment() {
	vec2 p = SCREEN_UV;
	vec3 art = textureLod(scene_color, p, 2.1).rgb;
	float gray = dot(art, vec3(0.299, 0.587, 0.114));
	art = mix(art, vec3(gray), 0.18) * vec3(0.81, 0.73, 0.65);
	float edge = smoothstep(0.33, 0.79, length((p - vec2(0.61, 0.44)) * vec2(1.07, 1.0)));
	art = mix(art, vec3(0.20, 0.105, 0.055), edge * 0.48);
	float paper = 1.0 - smoothstep(0.24, 0.68, p.x);
	vec3 vellum = mix(vec3(0.90, 0.81, 0.67), vec3(0.97, 0.91, 0.80), 1.0 - p.y);
	vellum += (grain(FRAGCOORD.xy) - 0.5) * 0.045;
	art = mix(art, vellum, paper * 0.97);
	vec2 dust = p * vec2(27.0, 16.0) + vec2(-0.11, 0.19) * TIME;
	vec2 cell = floor(dust);
	vec2 center = vec2(grain(cell), grain(cell + vec2(7.0, 18.0))) * 0.64 + 0.18;
	float fleck = 1.0 - smoothstep(0.009, 0.052, length(fract(dust) - center));
	fleck *= 0.5 + 0.5 * sin(TIME * 0.9 + grain(cell + 4.0) * 6.28);
	art += vec3(1.0, 0.77, 0.37) * fleck * smoothstep(0.24, 0.78, p.x) * 0.40;
	COLOR = vec4(art, 1.0);
}
