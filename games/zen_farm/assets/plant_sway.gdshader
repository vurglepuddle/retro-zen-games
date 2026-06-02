shader_type canvas_item;

uniform float wind_strength : hint_range(0.0, 12.0) = 4.0;
uniform float wind_speed    : hint_range(0.0, 4.0) = 1.2;
uniform float wind_spread   : hint_range(0.0, 0.12) = 0.038;

uniform vec2  poke_pos = vec2(-9999.0, -9999.0);
uniform float poke_amount : hint_range(0.0, 1.0) = 0.0;
uniform float poke_radius : hint_range(1.0, 300.0) = 90.0;
uniform float poke_strength : hint_range(0.0, 60.0) = 18.0;
uniform float tile_size = 64.0;
uniform bool use_tall_tiles = false;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec2 base_vertex = VERTEX.xy;

	vec2 atlas_pos = UV / TEXTURE_PIXEL_SIZE;
	float atlas_row = floor(atlas_pos.y / tile_size + 0.001);
	float visual_height = tile_size;
	if (use_tall_tiles && (abs(atlas_row - 4.0) < 0.1 || abs(atlas_row - 6.0) < 0.1)) {
		visual_height = tile_size * 2.0;
	}

	vec2 visual_pos = vec2(
		mod(atlas_pos.x, tile_size),
		mod(atlas_pos.y, visual_height)
	);
	float y01 = clamp(visual_pos.y / visual_height, 0.0, 1.0);
	float bend_mask = pow(1.0 - y01, 1.7);

	vec2 flower_anchor = base_vertex - visual_pos;
	vec2 flower_id = floor(flower_anchor / tile_size);
	vec2 flower_center = flower_anchor + vec2(tile_size * 0.5);

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
	VERTEX.x += wind_offset * bend_mask;

	vec2 flower_center_world = (MODEL_MATRIX * vec4(flower_center, 0.0, 1.0)).xy;
	vec2 plant_from_finger = flower_center_world - poke_pos;
	float dist = length(plant_from_finger);
	float t = clamp(1.0 - dist / poke_radius, 0.0, 1.0);
	float reaction = smoothstep(0.0, 1.0, t) * poke_amount;

	if (dist > 0.001) {
		VERTEX.xy += normalize(plant_from_finger) * reaction * poke_strength * bend_mask;
	}
}
