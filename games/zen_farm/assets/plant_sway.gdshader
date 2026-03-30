shader_type canvas_item;

uniform float wind_strength : hint_range(0.0, 12.0) = 4.0;
uniform float wind_speed    : hint_range(0.0, 4.0) = 1.2;
uniform float wind_spread   : hint_range(0.0, 0.12) = 0.038;

uniform vec2  poke_pos = vec2(-9999.0, -9999.0);
uniform float poke_age : hint_range(0.0, 1.0) = 1.0;
uniform float poke_radius : hint_range(1.0, 200.0) = 90.0;
uniform float poke_strength : hint_range(0.0, 20.0) = 5.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec2 base_vertex = VERTEX.xy;

	float local_y = mod(base_vertex.y, 64.0);
	float sway = mix(0.2, 1.0, 1.0 - local_y / 64.0);

	// Which 64x64 flower tile this vertex belongs to
	vec2 flower_id = floor(base_vertex / 64.0);

	// Stable per-flower variation
	float phase_jitter = hash(flower_id) * 6.28318;
	float speed_jitter = mix(0.94, 1.06, hash(flower_id + vec2(3.1, 7.2)));
	float amp_jitter   = mix(0.92, 1.08, hash(flower_id + vec2(8.4, 1.9)));

	float wave1 = sin(
		TIME * wind_speed * speed_jitter +
		base_vertex.x * wind_spread +
		base_vertex.y * 0.018 +
		phase_jitter
	);

	float wave2 = sin(
		TIME * wind_speed * 0.53 * speed_jitter +
		base_vertex.x * wind_spread * 1.7 +
		base_vertex.y * 0.031 +
		phase_jitter * 1.37
	);

	float wind_offset = (wave1 * 0.7 + wave2 * 0.3) * wind_strength * amp_jitter;
	VERTEX.x += wind_offset * sway;

	// Keep your cursed-good poke version
	vec2 canvas_pos = (CANVAS_MATRIX * MODEL_MATRIX * vec4(base_vertex, 0.0, 1.0)).xy;
	vec2 offset = canvas_pos - poke_pos;

	float dist = length(offset);
	float t = clamp(1.0 - dist / poke_radius, 0.0, 1.0);
	float reaction = t * t * (1.0 - poke_age);

	if (dist > 0.001) {
		float poke_sway = mix(0.6, 1.0, 1.0 - local_y / 64.0);
		VERTEX.xy += normalize(offset) * reaction * poke_strength * poke_sway;
	}
}