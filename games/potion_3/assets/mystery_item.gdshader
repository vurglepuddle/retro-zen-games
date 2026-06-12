// Mystery item silhouette (potion_3): solid dusty-blue smoke instead of a
// translucent darkening, so stacked silhouettes never show through each
// other. The item texture's alpha is binarized into a hard pixel cutout,
// and a slow world-space swirl drifts inside the shape.
shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.07, 0.08, 0.14, 1.0);
uniform vec4 swirl_color : source_color = vec4(0.13, 0.16, 0.26, 1.0);
uniform float block_px = 3.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float a = texture(TEXTURE, UV).a;
	vec2 p = floor(world_pos / block_px) * 0.33;
	float sw = sin(p.x + TIME * 0.40 + sin(p.y * 1.2 + TIME * 0.30))
	         + sin(p.y * 0.9 - TIME * 0.34 + sin(p.x * 1.05 - TIME * 0.22));
	sw = floor((sw * 0.25 + 0.5) * 3.0) / 3.0;
	vec3 col = mix(base_color.rgb, swirl_color.rgb, sw);
	COLOR = vec4(col, step(0.5, a));
}
