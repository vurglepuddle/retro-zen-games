// Magical alchemical pour droplet (alchemical_sort).
// Drawn on a small ColorRect; the rect's color tints the droplet (COLOR).
// The blob is snapped to a chunky block grid so it reads as pixel art:
// a wobbling essence core with pulsing inner light, twinkling sparkle
// pixels, an off-center shine, and a quantized aura ring around it.
shader_type canvas_item;

uniform float quad_px = 24.0;   // ColorRect size in px (square)
uniform float block_px = 2.0;   // chunky pixel size

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// Snap to chunky pixels so the droplet matches the hand-drawn art.
	vec2 block = floor(UV * quad_px / block_px);
	vec2 uv = (block + 0.5) * block_px / quad_px;
	vec2 c = uv - 0.5;

	// Living blob: the rim breathes with two slow counter-rotating waves.
	float ang = atan(c.y, c.x);
	float wob = sin(ang * 3.0 + TIME * 9.0) * 0.05
	          + sin(ang * 5.0 - TIME * 7.0) * 0.03;
	float d = length(c) * 2.0 / (1.0 + wob);

	float core = 1.0 - step(0.46, d);

	// Quantized aura — stepped glow rings, like a tiny magical seal.
	float halo = 1.0 - smoothstep(0.40, 1.0, d);
	halo = floor(halo * 3.0) / 3.0 * 0.5;

	// Pulsing inner light + off-center shine spot.
	float pulse = 0.85 + 0.15 * sin(TIME * 6.0);
	float shine = 1.0 - step(0.20, length(c + vec2(0.12, 0.12)) * 2.0);

	// Twinkling sparkle pixels drifting through the core.
	float t_step = floor(TIME * 9.0);
	float tw = step(0.92, hash(block + vec2(t_step, t_step * 1.7)));

	vec3 col = COLOR.rgb * pulse
	         + vec3(0.5) * shine * core
	         + vec3(0.9) * tw * core;
	float a = COLOR.a * max(core, halo);
	COLOR = vec4(min(col, vec3(1.0)), a);
}
