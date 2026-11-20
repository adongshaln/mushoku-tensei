shader_type spatial;

uniform vec4 cloth_color : source_color = vec4(0.245, 0.174, 0.132, 1.0);
varying vec2 table_uv;

void vertex() {
	table_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

float grain(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

float fabric_cloud(vec2 p) {
	vec2 cell = floor(p);
	vec2 h = fract(p);
	vec2 w = h * h * (3.0 - 2.0 * h);
	return mix(mix(grain(cell), grain(cell + vec2(1.0, 0.0)), w.x),
		mix(grain(cell + vec2(0.0, 1.0)), grain(cell + vec2(1.0)), w.x), w.y);
}

void fragment() {
	vec2 thread = table_uv * vec2(28.0, 33.0);
	vec2 footprint = fwidth(thread);
	vec2 weave = cos(fract(thread) * TAU) * (1.0 - smoothstep(vec2(0.42), vec2(0.97), footprint));
	float thread_pattern = 0.047 * weave.x + 0.041 * weave.y + 0.033 * weave.x * weave.y;
	float fleck = (grain(floor(table_uv * 145.0)) - 0.5) * 0.057;
	float dye = (fabric_cloud(table_uv * 0.88) - 0.5) * 0.23
		+ (fabric_cloud(table_uv * 5.8) - 0.5) * 0.10;
	float fold = sin(table_uv.x * 0.47 + table_uv.y * 0.18) * 0.055
		+ sin(table_uv.y * 1.03 - table_uv.x * 0.13) * 0.036;
	float edge = smoothstep(6.5, 17.0, length(table_uv * vec2(0.76, 1.03)));
	ALBEDO = cloth_color.rgb * (1.0 + thread_pattern + fleck + dye + fold - edge * 0.35);
	ROUGHNESS = 0.93;
	SPECULAR = 0.17;
}
