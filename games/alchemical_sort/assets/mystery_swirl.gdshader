// Mystery-fog liquid (alchemical_sort): instead of flat black, hidden
// layers are a near-black purple with a slow swirling arcane texture and
// rare twinkle pixels. World-space sampling means every layer and vial
// shows a different part of the swirl, continuous across the bottle.
// The liquid atlas texture's alpha still defines the layer's shape.
shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.055, 0.015, 0.10, 1.0);
uniform vec4 swirl_color : source_color = vec4(0.22, 0.06, 0.34, 1.0);
uniform vec4 spark_color : source_color = vec4(0.86, 0.48, 1.0, 1.0);
uniform float block_px = 3.0;   // chunky pixel size

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float a = texture(TEXTURE, UV).a;
	vec2 wp = floor(world_pos / block_px);
	vec2 p = wp * 0.30;

	// Two folded sine fields drifting against each other read as slow smoke.
	float sw = sin(p.x + TIME * 0.45 + sin(p.y * 1.3 + TIME * 0.33))
	         + sin(p.y * 0.8 - TIME * 0.38 + sin(p.x * 1.1 - TIME * 0.26));
	sw = floor((sw * 0.25 + 0.5) * 4.0) / 4.0;   // quantized bands

	vec3 col = mix(base_color.rgb, swirl_color.rgb, sw);
	float star_seed = hash(wp);
	float star = smoothstep(0.991, 0.998, star_seed);
	float phase = hash(wp + vec2(19.7, 41.3));
	float rate = mix(0.035, 0.075, hash(wp + vec2(7.1, 83.4)));
	float cycle = fract(TIME * rate + phase);
	float fade_in = mix(0.12, 0.24, hash(wp + vec2(53.2, 11.8)));
	float fade_out_start = mix(0.28, 0.42, hash(wp + vec2(91.6, 24.5)));
	float fade_out_end = fade_out_start + mix(0.16, 0.28, hash(wp + vec2(12.4, 67.9)));
	float glint = smoothstep(0.0, fade_in, cycle)
		* (1.0 - smoothstep(fade_out_start, fade_out_end, cycle));
	float tw = star * glint * mix(0.65, 1.0, star_seed);
	col = mix(col, spark_color.rgb, tw);
	col += spark_color.rgb * tw * 0.22;
	COLOR = vec4(col, a);
}
