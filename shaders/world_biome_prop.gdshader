shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Stylized Light-Novel Watercolor Prop Shader (Zero Texture Samplers — 60FPS Mobile Safe)
uniform float atlas_blend : hint_range(0.0, 1.0) = 1.0;
uniform int active_continent_idx = 0;
uniform int crossing_continent_idx = 0;
uniform float wind_strength : hint_range(0.0, 0.12) = 0.032;
uniform float wind_speed = 1.45;
uniform float emission_boost : hint_range(0.0, 2.0) = 0.0;
uniform vec3 emission_color : source_color = vec3(0.24, 0.82, 0.72);
uniform float night_glow : hint_range(0.0, 1.0) = 0.0;
uniform float winter_snow_push : hint_range(0.0, 1.0) = 0.0;
uniform float wetness_boost : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_shadow_strength : hint_range(0.0, 0.6) = 0.22;

varying float v_local_y;
varying float v_cont_id;
varying float v_warmth;
varying vec3 v_world_pos;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm_cloud(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(13.1, 7.9);
		a *= 0.48;
	}
	return v;
}

void vertex() {
	v_local_y = VERTEX.y;
	v_warmth = INSTANCE_CUSTOM.x;
	v_cont_id = INSTANCE_CUSTOM.z;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	if (wind_strength > 0.0001) {
		// Strictly lock trunk roots (VERTEX.y <= 0.14) to terrain while upper canopy sways gently
		float sway_mask = smoothstep(0.14, 0.96, VERTEX.y);
		float phase = MODEL_MATRIX[3].x * 1.15 + MODEL_MATRIX[3].z * 0.92 + INSTANCE_CUSTOM.w * 6.283185;
		float sx = sin(TIME * wind_speed + phase) + 0.35 * cos(TIME * wind_speed * 1.7 + phase * 1.3);
		float sz = cos(TIME * wind_speed * 0.88 + phase * 0.75);
		VERTEX.x += sx * wind_strength * sway_mask;
		VERTEX.z += sz * wind_strength * 0.65 * sway_mask;
	}
}

void fragment() {
	vec3 col = COLOR.rgb;

	// Subtle per-instance warmth & value shift (handmade variation across instanced forest groves)
	float w_shift = (v_warmth - 0.5) * 2.0;
	col *= mix(vec3(0.95, 0.98, 1.05), vec3(1.06, 1.01, 0.94), clamp(v_warmth, 0.0, 1.0));
	col *= (1.0 + 0.045 * w_shift);

	// Grounded root-contact ambient darkening (zero floating prop gap) + subtle sunlit crown lift
	float root_ao = mix(0.72, 1.0, smoothstep(0.0, 0.24, v_local_y));
	float crown_lift = 1.0 + 0.06 * smoothstep(0.45, 1.0, v_local_y);
	col *= root_ao * crown_lift;

	// Dual-state zoom fusion: blend gently into royal archival parchment at World Overview
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 royal_vellum = vec3(luma * 1.05, luma * 0.98, luma * 0.85);
	vec3 atlas_col = mix(col, royal_vellum, 0.28);
	atlas_col = mix(atlas_col, vec3(0.835, 0.772, 0.648), 0.09);
	col = mix(col, atlas_col, smoothstep(0.14, 0.95, atlas_blend));

	// Continent-focus harmonization (matches world_relief_terrain_v2.gdshader seamlessly)
	int c_id = int(round(v_cont_id));
	bool is_active_cont = (active_continent_idx == 0)
		|| (c_id == active_continent_idx)
		|| (crossing_continent_idx > 0 && c_id == crossing_continent_idx);
	float em_scale = 1.0;
	if (c_id == 0) {
		float periph_dim = (active_continent_idx == 0) ? 0.86 : 0.66;
		float pl = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(vec3(pl * 0.97, pl * 0.91, pl * 0.80), col, 0.50) * periph_dim;
		em_scale = periph_dim;
	} else if (!is_active_cont) {
		float il = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(vec3(il * 0.95, il * 0.90, il * 0.82), col, 0.42) * 0.68;
		em_scale = 0.45;
	}

	// Subtle cool dusk/night atmospheric tint while preserving crystal luminescence
	col *= mix(1.0, 0.82, night_glow);

	// M4 Synchronized Winter Crown Frosting (Northern Central Continent — keeps emerald lower boughs visible!) & Milis Summer Moisture
	if (winter_snow_push > 0.001 && c_id == 3 && emission_boost < 0.01) {
		float north_zone = smoothstep(0.45, -2.50, v_world_pos.z);
		float crown_mask = smoothstep(0.50, 0.94, v_local_y);
		float frost_t = clamp(north_zone * crown_mask * winter_snow_push * 0.58, 0.0, 0.58);
		col = mix(col, vec3(0.88, 0.90, 0.93), frost_t);
	}
	float prop_wet = (c_id == 2) ? wetness_boost : 0.0;
	if (prop_wet > 0.001) {
		col = mix(col, col * vec3(0.84, 0.92, 0.89), prop_wet * 0.42);
	}

	// Synchronized slow drifting sky cloud shadows
	float cloud_drift = fbm_cloud(v_world_pos.xz * 0.30 + vec2(TIME * 0.018, TIME * 0.009));
	float cloud_sh = smoothstep(0.49 - prop_wet * 0.12, 0.78, cloud_drift);
	float eff_cloud = cloud_shadow_strength * (1.0 + prop_wet * 0.65) * mix(1.0, 0.72, atlas_blend);
	col = mix(col, col * vec3(0.76, 0.82, 0.92), cloud_sh * eff_cloud);

	// Delicate studio porcelain crown rim light
	float fresnel_rim = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.8);
	col += vec3(0.10, 0.12, 0.14) * (fresnel_rim * smoothstep(0.25, 0.85, v_local_y) * (1.0 - atlas_blend * 0.45) * em_scale);

	vec3 em = vec3(0.0);
	if (emission_boost > 0.001) {
		float tip_mask = smoothstep(0.22, 0.94, v_local_y);
		float em_mult = emission_boost * (1.0 + night_glow * 0.85) * mix(1.0, 0.55, atlas_blend);
		em = emission_color * (tip_mask * em_mult * em_scale);
	}

	ALBEDO = col;
	EMISSION = em;
	ROUGHNESS = mix(mix(0.82, 0.90, atlas_blend), 0.44, prop_wet * 0.55);
	METALLIC = 0.0;
	SPECULAR = (emission_boost > 0.001) ? 0.38 : mix(0.18, 0.32, prop_wet * 0.55);
}
