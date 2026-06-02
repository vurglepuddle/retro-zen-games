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

varying vec2 world_pos;

void vertex() {
	VERTEX.xy += vertex_offset;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
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
	vec2 wobble = vec2(
		sin((pattern_pos.y + TIME * 21.0) * wobble_scale),
		cos((pattern_pos.x + TIME * 17.0) * wobble_scale)
	) * wobble_strength_px;
	vec2 pattern_size = vec2(textureSize(pattern_texture, 0));
	vec2 pattern_uv = (pattern_pos + TIME * scroll_speed_px + wobble) / pattern_size;
	COLOR = texture(pattern_texture, pattern_uv) * COLOR;
	COLOR.rgb += vec3(0.05) * touch_falloff * COLOR.a;
	COLOR.a *= opacity;
}
