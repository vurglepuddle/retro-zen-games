// Pixel-art explosion shockwave for gem_match special gems.
// Drawn on a ColorRect centered on the blast; drive `progress` 0 -> 1
// from GDScript (see Game.gd _spawn_shockwave). The ring is snapped to a
// chunky block grid and its alpha is quantized so it reads as hand-placed
// pixels rather than a smooth gradient.
shader_type canvas_item;
render_mode blend_add;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ring_color : source_color = vec4(1.0, 0.62, 0.18, 0.9);
uniform vec4 spark_color : source_color = vec4(1.0, 0.95, 0.75, 1.0);
uniform float grid_cells = 26.0;            // pixel blocks across the quad
uniform float thickness : hint_range(0.02, 0.5) = 0.16;
// CROSS gems fire a plus-shaped wavefront instead of a circle: square-metric
// expansion masked to the two axis arms.
uniform bool cross_shape = false;
uniform float arm_width : hint_range(0.05, 0.6) = 0.22;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// Snap to a block grid: every block gets one color = squarish pixels.
	vec2 block_uv = (floor(UV * grid_cells) + 0.5) / grid_cells;
	vec2 ad = abs(block_uv - vec2(0.5)) * 2.0;

	float dist;
	float arm_mask = 1.0;
	if (cross_shape) {
		dist = max(ad.x, ad.y);                      // square-metric wavefront
		arm_mask = 1.0 - step(arm_width, min(ad.x, ad.y));  // confine to + arms
	} else {
		dist = length(ad);
	}

	float radius = mix(0.06, 1.0, progress);
	float band = (1.0 - smoothstep(0.0, thickness, abs(dist - radius))) * arm_mask;
	float fade = pow(clamp(1.0 - progress, 0.0, 1.0), 1.1);

	// Some blocks on the ring twinkle brighter as the wave passes.
	float h = hash(block_uv);
	float sparkle = step(0.78, h);

	float a = band * fade;
	a = floor(a * 4.0 + 0.5) / 4.0;   // quantized alpha steps = pixel-art feel

	vec3 col = mix(ring_color.rgb, spark_color.rgb, sparkle);
	COLOR = vec4(col, a * ring_color.a);
}
