shader_type canvas_item;
render_mode unshaded;

uniform sampler2D scene_color : hint_screen_texture, filter_linear_mipmap, repeat_disable;

float grain(vec2 p) {
	return fract(sin(dot(p, vec2(73.81, 193.37))) * 44932.81);
}

void fragment() {
	vec2 p = SCREEN_UV;
	// Dreamy cinematic shallow depth-of-field blur across the hearth scene.
	float focus_dist = length((p - vec2(0.67, 0.72)) * vec2(1.0, 1.1));
	float lod = mix(1.05, 2.55, smoothstep(0.12, 0.75, focus_dist));
	vec3 art = textureLod(scene_color, p, lod).rgb;

	// Rich warm anime color grading (deeper cozy shadows + amber highlights).
	float gray = dot(art, vec3(0.299, 0.587, 0.114));
	art = mix(vec3(gray), art, 1.08) * vec3(0.95, 0.87, 0.78);

	// Gentle flickering hearth firelight bloom in lower-right.
	float flicker = 0.90 + 0.06 * sin(TIME * 3.2) + 0.04 * sin(TIME * 6.8 + 1.2);
	float hearth = (1.0 - smoothstep(0.04, 0.52, length((p - vec2(0.66, 0.82)) * vec2(1.0, 1.28)))) * flicker;
	art += vec3(1.0, 0.58, 0.22) * hearth * 0.26;

	// Cinematic dark-espresso atmospheric vignette on left for luminous ivory/gold calligraphy.
	float left_veil = 1.0 - smoothstep(0.06, 0.58, p.x);
	float outer_vig = smoothstep(0.36, 0.92, length((p - vec2(0.62, 0.48)) * vec2(1.02, 1.04)));
	vec3 espresso = vec3(0.10, 0.072, 0.054);
	art = mix(art, espresso, clamp(left_veil * 0.74 + outer_vig * 0.48, 0.0, 0.86));

	// Subtle filmic paper grain.
	art += (grain(FRAGCOORD.xy) - 0.5) * 0.018;

	// Rising golden hearth embers & sunlit dust motes across the right vista.
	vec2 dust = p * vec2(26.0, 15.0) + vec2(-0.07, 0.22) * TIME;
	vec2 cell = floor(dust);
	vec2 center = vec2(grain(cell), grain(cell + vec2(7.0, 18.0))) * 0.64 + 0.18;
	float fleck = 1.0 - smoothstep(0.007, 0.046, length(fract(dust) - center));
	fleck *= 0.45 + 0.55 * sin(TIME * 1.15 + grain(cell + 4.0) * 6.283);
	art += vec3(1.0, 0.78, 0.40) * fleck * smoothstep(0.14, 0.70, p.x) * 0.56;

	COLOR = vec4(art, 1.0);
}
