shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D biome_splat_a : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D biome_splat_b : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D region_id_map : hint_default_black, filter_nearest, repeat_disable;

uniform int hovered_region_idx = 0;
uniform int selected_region_idx = 0;
uniform int hovered_continent_idx = 0;
uniform int active_continent_idx = 0;
uniform int crossing_continent_idx = 0;
uniform float hover_pulse : hint_range(0.0, 1.0) = 0.0;
uniform float sea_level = 0.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

const vec2 ID_TEXEL = vec2(1.0 / 2048.0, 1.0 / 1024.0);

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

ivec2 sample_ids(vec2 uv) {
	vec4 px = texture(region_id_map, clamp(uv, vec2(0.0002), vec2(0.9998)));
	return ivec2(int(round(px.r * 255.0)), int(round(px.g * 255.0)));
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 sa = texture(biome_splat_a, UV);
	vec4 sb = texture(biome_splat_b, UV);
	ivec2 ids = sample_ids(UV);
	int r_id = ids.x;
	int c_id = ids.y;

	// Normalize biome weights softly over warm royal parchment clay
	float sa_sum = max(sa.r + sa.g + sa.b + sa.a, 0.001);
	vec4 bw = sa / sa_sum;

	// M1 tasteful sculpted parchment-clay palette + refined biome pastel washes (calibrated for Forward Mobile exposure)
	vec3 col_demon = vec3(0.745, 0.558, 0.432);
	vec3 col_milis = vec3(0.578, 0.688, 0.538);
	vec3 col_central = vec3(0.768, 0.722, 0.598);
	vec3 col_frost = vec3(0.778, 0.806, 0.835);
	vec3 base_clay = col_demon * bw.r + col_milis * bw.g + col_central * bw.b + col_frost * bw.a;

	// Blend toward warm archival vellum so M1 reads as a cohesive museum relief sculpture without blowing out highlights
	vec3 warm_parchment = vec3(0.768, 0.708, 0.598);
	vec3 col = mix(warm_parchment, base_clay, 0.68);

	// Slope-aware rock ridge & crag relief shading
	vec3 wn = normalize(v_world_normal);
	float geom_slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	float rock_mask = clamp(sb.r * 0.76 + smoothstep(0.08, 0.32, geom_slope) * 0.72, 0.0, 1.0);
	vec3 rock_central = vec3(0.535, 0.368, 0.285); // Red Wyrm terracotta sandstone
	vec3 rock_milis = vec3(0.415, 0.468, 0.415);   // Blue Dragon slate-jade stone
	vec3 rock_demon = vec3(0.485, 0.325, 0.248);   // Demon burnt-ochre crag
	vec3 rock_frost = vec3(0.545, 0.585, 0.630);   // Northern alpine rock
	vec3 rock_col = rock_demon * bw.r + rock_milis * bw.g + rock_central * bw.b + rock_frost * bw.a;
	col = mix(col, rock_col, rock_mask * 0.58);

	// Subtle snow cap catch on high alpine peaks (excluding Demon arid highlands)
	float peak_frost = smoothstep(0.62, 0.94, v_world_pos.y) * (1.0 - bw.r * 0.88) * smoothstep(0.52, 0.90, wn.y);
	col = mix(col, vec3(0.885, 0.895, 0.910), peak_frost * 0.52);

	// Coastal & lakefront warm parchment sand transition
	col = mix(col, vec3(0.815, 0.752, 0.625), sb.g * 0.34);

	// Paved royal roads etched subtly like fine cartographic ink/ochre paths
	col = mix(col, vec3(0.845, 0.788, 0.665), sb.b * 0.34);

	// Demon rift & scorch valley depth shading
	col = mix(col, vec3(0.455, 0.318, 0.248), sb.a * 0.28);

	// Fine handmade paper grain & subtle topographic elevation warmth
	float grain = value_noise(v_world_pos.xz * 22.0) * 0.6 + value_noise(v_world_pos.xz * 64.0) * 0.4;
	col *= 0.955 + grain * 0.085;

	// Subtle valley cavity tint vs ridge highlight for museum sculpture readability
	float elev_lift = smoothstep(0.08, 0.85, v_world_pos.y);
	col *= mix(0.92, 1.04, elev_lift);

	// Submerged seabed color (beneath OceanPlane)
	if (v_world_pos.y < sea_level + 0.008) {
		float depth_t = clamp((sea_level + 0.008 - v_world_pos.y) / 0.22, 0.0, 1.0);
		vec3 seabed_col = mix(vec3(0.64, 0.70, 0.64), vec3(0.20, 0.32, 0.38), depth_t);
		col = mix(col, seabed_col, smoothstep(sea_level + 0.008, sea_level - 0.018, v_world_pos.y));
	}

	// --- Seamless Draped Borders & Region/Continent Hover Glow via region_id_map ---
	bool is_playable = (r_id > 0);
	bool is_active_cont = (active_continent_idx == 0)
		|| (c_id == active_continent_idx)
		|| (crossing_continent_idx > 0 && c_id == crossing_continent_idx);

	bool is_hov_reg = (hovered_region_idx > 0 && r_id == hovered_region_idx);
	bool is_sel_reg = (selected_region_idx > 0 && r_id == selected_region_idx);
	bool is_hov_cont = (active_continent_idx == 0 && hovered_continent_idx > 0 && c_id == hovered_continent_idx);
	bool is_highlighted = is_hov_reg || is_sel_reg || is_hov_cont;

	// Sample 8-direction neighbors at crisp & glow radii for smooth anti-aliased draped borders
	float internal_edge = 0.0;
	float any_reg_edge = 0.0;
	float any_cont_edge = 0.0;
	float glow_halo = 0.0;

	if (is_playable) {
		vec2 dirs[8] = vec2[](
			vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0),
			vec2(0.707, 0.707), vec2(-0.707, 0.707), vec2(0.707, -0.707), vec2(-0.707, -0.707)
		);
		for (int i = 0; i < 8; i++) {
			ivec2 n_near = sample_ids(UV + dirs[i] * ID_TEXEL * 2.2);
			if (n_near.x != r_id) {
				any_reg_edge = 1.0;
				if (n_near.x > 0) {
					internal_edge = 1.0;
				}
			}
			if (n_near.y != c_id) {
				any_cont_edge = 1.0;
			}
			if (is_highlighted) {
				ivec2 n_mid = sample_ids(UV + dirs[i] * ID_TEXEL * 4.4);
				ivec2 n_far = sample_ids(UV + dirs[i] * ID_TEXEL * 7.5);
				bool diff_mid = is_hov_cont ? (n_mid.y != c_id) : (n_mid.x != r_id);
				bool diff_far = is_hov_cont ? (n_far.y != c_id) : (n_far.x != r_id);
				if (diff_mid) {
					glow_halo = max(glow_halo, 0.72);
				}
				if (diff_far) {
					glow_halo = max(glow_halo, 0.34);
				}
			}
		}
	}

	// Quiet archival sepia-gold national/regional ink borders at rest
	if (internal_edge > 0.5 && is_active_cont) {
		col = mix(col, vec3(0.45, 0.34, 0.21), 0.44);
	}

	// Gentle dimming of non-active continents & peripheral unplayable lands
	if (!is_playable && v_world_pos.y >= sea_level) {
		float periph_dim = (active_continent_idx == 0) ? 0.86 : 0.64;
		float luma = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(vec3(luma * 0.96, luma * 0.91, luma * 0.82), col, 0.55) * periph_dim;
	} else if (is_playable && !is_active_cont) {
		float luma = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(vec3(luma * 0.96, luma * 0.90, luma * 0.80), col, 0.42) * 0.68;
	}

	// Warm sunlit gold wash & glowing draped antique-gold border on hover / selection
	vec3 emission = vec3(0.0);
	float pulse = 0.5 + 0.5 * hover_pulse;
	if (is_highlighted) {
		float fill_str = is_hov_reg ? 0.16 : (is_sel_reg ? 0.12 : 0.11);
		vec3 gold_tint = vec3(0.955, 0.825, 0.525);
		col = mix(col, gold_tint, fill_str + 0.04 * pulse);
		emission += vec3(0.88, 0.68, 0.28) * (fill_str * 0.42 + 0.03 * pulse);

		float border_line = is_hov_cont ? any_cont_edge : any_reg_edge;
		vec3 gold_rim = vec3(0.985, 0.765, 0.295);
		col = mix(col, vec3(0.46, 0.31, 0.12), glow_halo * 0.24 * (1.0 - border_line));
		col = mix(col, gold_rim, border_line * 0.92 + glow_halo * 0.28);
		emission += gold_rim * (border_line * (1.05 + 0.32 * pulse) + glow_halo * (0.34 + 0.12 * pulse));
	}

	ALBEDO = col;
	EMISSION = emission;
	ROUGHNESS = mix(0.84, 0.91, rock_mask * 0.5);
	METALLIC = 0.0;
	SPECULAR = 0.18;
}
