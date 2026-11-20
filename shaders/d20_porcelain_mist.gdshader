shader_type canvas_item;
render_mode unshaded;

uniform sampler2D dice_view : filter_linear, repeat_disable;
uniform vec2 swatch_left;
uniform vec2 swatch_right;
uniform vec2 right_to_plate;
uniform vec2 down_to_plate;
uniform vec2 patch_size = vec2(170.0, 126.0);
uniform vec4 glow_tone : source_color = vec4(0.79, 0.88, 0.95, 1.0);
uniform float light_mix : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 local_px = (UV - vec2(0.5)) * patch_size;
	vec2 p = vec2(dot(local_px, right_to_plate), dot(local_px, down_to_plate));
	float border = min(0.228 - p.y, 0.228 + p.y * 0.5 - abs(p.x) * 0.866);
	float plate = smoothstep(0.004, 0.032, border);
	float distance_to_center = length(vec2(p.x / 0.386, (p.y + 0.017) / 0.239));
	float mist = 1.0 - smoothstep(0.71, 1.0, distance_to_center);
	vec3 left = texture(dice_view, swatch_left).rgb;
	vec3 right = texture(dice_view, swatch_right).rgb;
	vec3 glaze = mix(left, right, smoothstep(-0.28, 0.28, p.x));
	float grain = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	float soft_light = (1.0 - smoothstep(0.08, 0.8, distance_to_center)) * light_mix;
	glaze = mix(glaze, glow_tone.rgb, soft_light * 0.26);
	glaze += (grain - 0.5) * 0.016;
	COLOR = vec4(glaze, COLOR.a * mist * plate);
}
