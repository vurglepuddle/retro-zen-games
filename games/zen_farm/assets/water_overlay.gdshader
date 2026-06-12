shader_type canvas_item;

uniform sampler2D pattern_texture : repeat_enable, filter_nearest;
uniform vec2 scroll_speed_px = vec2(3.0, -2.0);
uniform float wobble_strength_px : hint_range(0.0, 8.0, 0.1) = 1.4;
uniform float wobble_scale : hint_range(0.0, 0.2, 0.001) = 0.045;
uniform vec2 vertex_offset = vec2(0.0, 0.0);
uniform vec2 pattern_origin = vec2(0.0, 0.0);
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform vec2 poke_pos = vec2(-9999.0, -9999.0);
uniform float poke_amount : hint_range(0.0, 1.0) = 0.0;
uniform float poke_radius : hint_range(1.0, 300.0) = 90.0;
uniform float poke_strength_px : hint_range(0.0, 18.0, 0.1) = 5.0;
uniform float rain_amount : hint_range(0.0, 1.0, 0.01) = 0.0;

varying vec2 world_pos;

void vertex() {
	VERTEX.xy += vertex_offset;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Expanding raindrop rings: the water is divided into cells; each cell
// spawns a ring at a hash-random moment of a repeating cycle, expanding
// and fading like a real raindrop hit.
float rain_rings(vec2 pos, float t, float cell, vec2 seed) {
	vec2 gid = floor(pos / cell);
	vec2 jitter = vec2(hash(gid + seed), hash(gid + seed + vec2(7.3, 1.9))) - 0.5;
	vec2 center = (gid + 0.5 + jitter * 0.6) * cell;
	float phase = fract(t + hash(gid + seed + vec2(3.7, 9.1)));
	float radius = phase * cell * 0.55;
	float d = length(pos - center);
	float ring = 1.0 - smoothstep(0.0, 2.4, abs(d - radius));
	return ring * (1.0 - phase);
}

void fragment() {
	vec2 pattern_pos = world_pos - pattern_origin;
	vec2 from_touch = world_pos - poke_pos;
	float touch_dist = length(from_touch);
	float touch_t = clamp(1.0 - touch_dist / poke_radius, 0.0, 1.0);
	float touch_falloff = smoothstep(0.0, 1.0, touch_t) * poke_amount;
	if (touch_dist > 0.001) {
		float ripple = sin(touch_dist * 0.32 - TIME * 13.0) * touch_falloff * poke_strength_px;
		pattern_pos += normalize(from_touch) * ripple;
	}
	float rain_wave = (
		sin((pattern_pos.x + pattern_pos.y) * 0.085 + TIME * 18.0) +
		sin(pattern_pos.x * 0.12 - pattern_pos.y * 0.07 - TIME * 24.0)
	) * 0.5;
	pattern_pos += vec2(rain_wave * 0.5, -rain_wave * 0.2) * rain_amount;
	vec2 base_wobble = vec2(
		sin((pattern_pos.y + TIME * 21.0) * wobble_scale),
		cos((pattern_pos.x + TIME * 17.0) * wobble_scale)
	) * wobble_strength_px;
	vec2 rain_wobble = vec2(
		sin((pattern_pos.x * 0.07 + pattern_pos.y * 0.11) + TIME * 3.4),
		cos((pattern_pos.x * 0.13 - pattern_pos.y * 0.05) - TIME * 4.1)
	) * 0.55 * rain_amount;
	vec2 wobble = base_wobble + rain_wobble;
	vec2 pattern_size = vec2(textureSize(pattern_texture, 0));
	vec2 pattern_uv = (pattern_pos + TIME * scroll_speed_px + wobble) / pattern_size;
	COLOR = texture(pattern_texture, pattern_uv) * COLOR;
	if (rain_amount > 0.001) {
		// Chunky 2 px blocks keep the rings pixel-art; two offset grids of
		// different sizes give natural, non-repeating drop coverage.
		vec2 ring_pos = floor((world_pos - pattern_origin) / 2.0) * 2.0;
		float rings = rain_rings(ring_pos, TIME * 0.9, 34.0, vec2(0.0));
		rings += rain_rings(ring_pos, TIME * 0.9 + 0.37, 52.0, vec2(11.0));
		rings = floor(clamp(rings, 0.0, 1.0) * 3.0 + 0.5) / 3.0;
		COLOR.rgb += vec3(0.10, 0.13, 0.14) * rings * rain_amount * COLOR.a;
	}
	COLOR.rgb += vec3(0.05) * touch_falloff * COLOR.a;
	COLOR.a *= opacity;
}
