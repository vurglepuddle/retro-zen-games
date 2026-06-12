shader_type canvas_item;

uniform float wind_strength : hint_range(0.0, 12.0) = 4.0;
uniform float wind_speed    : hint_range(0.0, 4.0) = 1.2;
uniform float wind_spread   : hint_range(0.0, 0.12) = 0.038;

// Gust bands: slow waves of wind intensity rolling diagonally across the
// field — the whole meadow breathes instead of shimmering uniformly.
// NOTE: mirrored in Game.gd _frog_sway_offset(); keep the math in sync.
uniform float gust_strength : hint_range(0.0, 1.0) = 0.45;
uniform float gust_speed    : hint_range(0.0, 2.0) = 0.35;

uniform vec2  poke_pos = vec2(-9999.0, -9999.0);
uniform float poke_amount : hint_range(0.0, 1.0) = 0.0;
uniform float poke_radius : hint_range(1.0, 300.0) = 90.0;
uniform float poke_strength : hint_range(0.0, 60.0) = 18.0;
uniform float tile_size = 64.0;
uniform bool use_tall_tiles = false;

// Runtime-atlas layout, set from Game.gd (_apply_atlas_layout_params).
// With Godot's default use_texture_padding every tile is copied into the
// runtime atlas with a 1 px border: pitch = tile_size + 2, margin = 1.
// The padding is what makes per-tile reconstruction possible at quad
// corners: a tile quad is exactly tile_size tall, so with a tile_size
// pitch the top and bottom vertices are indistinguishable (mod gives the
// same value) and the whole plant moves rigidly — the old "glued squares"
// bug. With pitch 66 every corner lands inside its own padded cell.
uniform float atlas_pitch = 66.0;
uniform float atlas_margin = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec2 base_vertex = VERTEX.xy;
	vec2 atlas_pos = UV / TEXTURE_PIXEL_SIZE;

	// Which padded atlas cell does this vertex belong to?
	vec2 cell = floor(atlas_pos / atlas_pitch);

	float visual_height = tile_size;
	if (use_tall_tiles) {
		// Tall plants sit on atlas rows 4 and 6 and span two rows; the
		// bottom vertices of their quads land in padded rows 5 / 7 —
		// fold them back onto the tile's own row.
		if (abs(cell.y - 5.0) < 0.1 || abs(cell.y - 7.0) < 0.1) {
			cell.y -= 1.0;
		}
		if (abs(cell.y - 4.0) < 0.1 || abs(cell.y - 6.0) < 0.1) {
			visual_height = tile_size * 2.0;
		}
	}

	// Vertex position within its plant's artwork: x in 0..tile_size,
	// y in 0..visual_height. Correct for all four quad corners.
	vec2 visual_pos = atlas_pos - (cell * atlas_pitch + atlas_margin);
	float y01 = clamp(visual_pos.y / visual_height, 0.0, 1.0);
	float bend_mask = pow(1.0 - y01, 1.7);

	vec2 flower_anchor = base_vertex - visual_pos;
	vec2 flower_id = floor(flower_anchor / tile_size);

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

	float gust = 0.5 + 0.5 * sin(TIME * gust_speed * 2.0
		- base_vertex.x * 0.006 - base_vertex.y * 0.003);
	gust = mix(1.0 - gust_strength, 1.0 + gust_strength * 0.6, gust);

	float wind_offset = (wave1 * 0.7 + wave2 * 0.3) * wind_strength * amp_jitter * gust;
	VERTEX.x += wind_offset * bend_mask;

	// --- Rooted-stalk poke ---------------------------------------------------
	// The plant is glued to the ground at the bottom-center of its tile.
	// Pushing near it bends the stalk away from the finger, pivoting around
	// the root with more rotation toward the tip:   \  v  /
	vec2 root_local = flower_anchor + vec2(tile_size * 0.5, visual_height);
	vec2 root_world = (MODEL_MATRIX * vec4(root_local, 0.0, 1.0)).xy;

	// Distance from the finger to the nearest point on the stalk (the vertical
	// segment from root up to the plant top), so pressing anywhere along the
	// plant's body engages it — not just near its center.
	float dx = root_world.x - poke_pos.x;
	float dy = poke_pos.y - clamp(poke_pos.y, root_world.y - visual_height, root_world.y);
	float dist = length(vec2(dx, dy));
	float t = clamp(1.0 - dist / poke_radius, 0.0, 1.0);
	float reaction = smoothstep(0.0, 1.0, t) * poke_amount;

	if (abs(reaction) > 0.0005) {
		// Lean sign eases through zero as the finger crosses the stalk, so
		// plants directly under the finger squash instead of flip-flopping.
		float dir = clamp(dx / (poke_radius * 0.45), -1.0, 1.0);
		float ang = dir * reaction * poke_strength * 0.05 * bend_mask;

		// Rotate around the root: the tip travels sideways AND droops,
		// like a real bent stalk, while the base never moves.
		vec2 rel = base_vertex - root_local;
		float s = sin(ang);
		float c = cos(ang);
		vec2 bent = vec2(rel.x * c - rel.y * s, rel.x * s + rel.y * c);
		VERTEX.xy += bent - rel;

		// Finger straight on top: press the plant down (the "v").
		VERTEX.y += (1.0 - abs(dir)) * reaction * poke_strength * 0.55 * bend_mask;
	}
}
