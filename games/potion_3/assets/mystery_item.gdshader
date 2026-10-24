// Mystery item silhouette (potion_3): solid dusty-blue smoke instead of a
// translucent darkening, so stacked silhouettes never show through each
// other. The item texture's alpha is binarized into a hard pixel cutout,
// and a slow world-space swirl drifts inside the shape. A gold inner contour
// keeps the silhouette readable without growing into neighbouring slots.
shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.07, 0.08, 0.14, 1.0);
uniform vec4 swirl_color : source_color = vec4(0.13, 0.16, 0.26, 1.0);
uniform vec4 outline_color : source_color = vec4(0.937255, 0.674510, 0.156863, 0.8); // #efac28 at 80%
// Items render at 90/120 of their source size: 2 2/3 texels = 2 game pixels.
uniform float outline_px : hint_range(1.0, 8.0) = 2.666667;
uniform float block_px = 3.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float a = texture(TEXTURE, UV).a;
	vec2 edge = TEXTURE_PIXEL_SIZE * outline_px;
	float interior = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			if (x != 0 || y != 0) {
				vec2 uv = UV + vec2(float(x), float(y)) * edge;
				// Outside-image samples are transparent, including edge-touching art.
				vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
				interior = min(interior, step(0.5, texture(TEXTURE, uv).a) * inside.x * inside.y);
			}
		}
	}
	vec2 p = floor(world_pos / block_px) * 0.33;
	float sw = sin(p.x + TIME * 0.40 + sin(p.y * 1.2 + TIME * 0.30))
	         + sin(p.y * 0.9 - TIME * 0.34 + sin(p.x * 1.05 - TIME * 0.22));
	sw = floor((sw * 0.25 + 0.5) * 3.0) / 3.0;
	vec3 col = mix(base_color.rgb, swirl_color.rgb, sw);
	// Blend the translucent gold over the smoke, keeping the cutout opaque.
	col = mix(col, outline_color.rgb, (1.0 - interior) * outline_color.a);
	// × COLOR.a keeps node/cell modulate fades (drop-in, conveyor) working —
	// overwriting COLOR outright drops modulate, so silhouettes used to pop.
	COLOR = vec4(col, step(0.5, a) * COLOR.a);
}
