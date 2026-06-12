// Rigidly displaces the whole frog sprite by the decor-layer wind evaluated
// at his perch point — the same math AND the same GPU TIME clock as
// plant_sway.gdshader, so froggo stays glued to his swaying tuft (a CPU
// replication drifted against shader TIME and read as sliding).
// Keep the wave/gust formulas in sync with plant_sway.gdshader.
shader_type canvas_item;

uniform vec2 seat_pos = vec2(0.0);     // perch point, decor-map local px
uniform vec2 flower_id = vec2(0.0);    // the tuft's tile id (phase jitter)
uniform float bend_mask = 0.8;         // how high on the stalk froggo sits
uniform float wind_strength = 5.0;     // decor layer values (see Game.gd)
uniform float wind_speed = 1.0;
uniform float wind_spread = 0.038;
uniform float gust_strength = 0.45;
uniform float gust_speed = 0.35;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	float phase_jitter = hash(flower_id) * 6.28318;
	float speed_jitter = mix(0.94, 1.06, hash(flower_id + vec2(3.1, 7.2)));
	float amp_jitter   = mix(0.92, 1.08, hash(flower_id + vec2(8.4, 1.9)));

	float wave1 = sin(TIME * wind_speed * speed_jitter
		+ seat_pos.x * wind_spread + seat_pos.y * 0.018 + phase_jitter);
	float wave2 = sin(TIME * wind_speed * 0.53 * speed_jitter
		+ seat_pos.x * wind_spread * 1.7 + seat_pos.y * 0.031 + phase_jitter * 1.37);

	float gust = 0.5 + 0.5 * sin(TIME * gust_speed * 2.0
		- seat_pos.x * 0.006 - seat_pos.y * 0.003);
	gust = mix(1.0 - gust_strength, 1.0 + gust_strength * 0.6, gust);

	VERTEX.x += (wave1 * 0.7 + wave2 * 0.3) * wind_strength
		* amp_jitter * gust * bend_mask;
}
