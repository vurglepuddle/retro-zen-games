shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

uniform vec4 shadow_tint : source_color = vec4(0.16, 0.20, 0.42, 1.0);
uniform vec4 mid_tint : source_color = vec4(0.84, 0.90, 1.0, 1.0);
uniform vec4 highlight_tint : source_color = vec4(1.0, 0.92, 0.80, 1.0);
uniform float night_amount = 0.0;
uniform float dusk_amount = 0.0;
uniform float dawn_amount = 0.0;
uniform float saturation = 1.0;
uniform float exposure = 1.0;
uniform float contrast = 1.0;
uniform float lift = 0.0;
uniform float vignette_strength = 0.0;

vec3 apply_saturation(vec3 color, float amount) {
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	return mix(vec3(luma), color, amount);
}

void fragment() {
	vec4 src = texture(screen_texture, SCREEN_UV);
	vec3 color = src.rgb;
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	float night = clamp(night_amount, 0.0, 1.15);

	float shadow_mask = 1.0 - smoothstep(0.12, 0.62, luma);
	float mid_mask = 1.0 - abs(luma - 0.5) * 2.0;
	float highlight_mask = smoothstep(0.48, 0.95, luma);
	float warm_mask = smoothstep(0.04, 0.30, color.r - color.b) * smoothstep(0.16, 0.75, color.r);
	float green_mask = smoothstep(0.02, 0.26, color.g - max(color.r, color.b));

	vec3 shadow_grade = color * mix(vec3(1.0), shadow_tint.rgb, 0.62) + shadow_tint.rgb * 0.13;
	vec3 mid_grade = color * mix(vec3(1.0), mid_tint.rgb, 0.26);
	vec3 highlight_grade = mix(color, vec3(luma), 0.30) * mix(vec3(1.0), highlight_tint.rgb, 0.22);

	color = mix(color, shadow_grade, shadow_mask * night);
	color = mix(color, mid_grade, clamp(mid_mask, 0.0, 1.0) * (night * 0.38 + dawn_amount * 0.20));
	color = mix(color, highlight_grade, highlight_mask * night * 0.58);

	vec3 deep_blue = vec3(0.015, 0.045, 0.300);
	//vec3 violet = vec3(0.370, 0.080, 0.470);
	vec3 violet = vec3(0.270, 0.080, 0.470);
	vec3 cobalt = vec3(0.020, 0.190, 0.850);
	vec3 moon_lilac = vec3(0.680, 0.560, 1.000);
	vec3 night_palette = mix(deep_blue, violet, smoothstep(0.08, 0.46, luma));
	night_palette = mix(night_palette, cobalt, smoothstep(0.20, 0.72, luma) * 0.48);
	night_palette = mix(night_palette, moon_lilac, highlight_mask * 0.32);

	vec3 saturated_base = apply_saturation(color, 1.45);
	vec3 night_grade = saturated_base * vec3(0.54, 0.58, 0.86) + night_palette * (0.50 + shadow_mask * 0.42 + clamp(mid_mask, 0.0, 1.0) * 0.16);
	vec3 grass_night = saturated_base * vec3(0.30, 0.78, 0.92) + vec3(0.010, 0.070, 0.190);
	night_grade = mix(night_grade, grass_night, green_mask * 0.38);
	color = mix(color, night_grade, night * 0.86);

	vec3 dusk_grade = color * vec3(1.12, 0.84, 0.72) + vec3(0.055, 0.018, 0.030);
	color = mix(color, dusk_grade, dusk_amount * (0.22 + shadow_mask * 0.30));

	vec3 dawn_grade = color * vec3(0.92, 0.96, 1.12) + vec3(0.018, 0.026, 0.045);
	vec3 dawn_warm = color * vec3(1.10, 0.98, 0.78) + vec3(0.040, 0.026, 0.005);
	color = mix(color, dawn_grade, dawn_amount * shadow_mask * 0.42);
	color = mix(color, dawn_warm, dawn_amount * highlight_mask * 0.18);

	vec3 warm_protected = mix(color, src.rgb * vec3(1.04, 0.86, 0.60) + vec3(0.030, 0.012, 0.000), 0.45);
	color = mix(color, warm_protected, warm_mask * night * 0.22);
	color = apply_saturation(color, saturation);
	color = (color - 0.5) * contrast + 0.5;
	color = color * exposure + lift;

	vec2 centered = UV - vec2(0.5);
	float vignette = smoothstep(0.16, 0.82, dot(centered, centered) * 2.0);
	color = mix(color, color * vec3(0.80, 0.84, 1.02), vignette * vignette_strength);

	COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)), src.a);
}
