// Hanging sway (potion_3 menu): herb bundles on their nails, the title sign on
// its chains. The poke idea from zen_farm/assets/plant_sway.gdshader (push it,
// it leans away, springs back past upright and settles), but pivoting from the
// top, and done by sliding whole art-pixel rows sideways, so the pixel art stays
// crisp instead of smearing like a rotated sprite.
// HangingSway.gd runs the spring and feeds `sway`; this only draws it.
shader_type canvas_item;

uniform float sway = 0.0;        // sideways offset in art px, measured `reach` below the pivot
uniform float pivot_y = 0.0;     // texture px; rows above this never move (the nail)
uniform float reach = 48.0;      // texture px below the pivot where the offset equals `sway`
uniform bool rigid = false;      // chains: everything deeper than `reach` moves as one board
uniform float droop = 0.0;       // soft bundles bend more toward the tip (0 = straight pendulum)
uniform float art_px = 3.0;
uniform float pad = 24.0;        // texture px of room drawn on each side for the swing

varying vec4 tint;

void vertex() {
	// COLOR here already includes the node's modulate; overwriting COLOR in
	// fragment() would drop it, so carry it over by hand.
	tint = COLOR;
	// Widen the quad so rows can slide out past the texture's own edges.
	float side = UV.x < 0.5 ? -1.0 : 1.0;
	VERTEX.x += side * pad;
	UV.x += side * pad * TEXTURE_PIXEL_SIZE.x;
}

void fragment() {
	vec2 tex_size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 p = UV * tex_size;
	float row_mid = (floor(p.y / art_px) + 0.5) * art_px;
	float depth = max(row_mid - pivot_y, 0.0) / reach;
	float shape = rigid ? min(depth, 1.0) : depth * (1.0 + droop * (depth - 1.0));
	// Whole art pixels only: every row steps sideways as a block.
	float shift = round(sway * max(shape, 0.0)) * art_px;
	vec2 uv = vec2(p.x - shift, p.y) / tex_size;
	vec4 tex = texture(TEXTURE, uv);
	if (uv.x < 0.0 || uv.x > 1.0) {
		tex = vec4(0.0);
	}
	COLOR = tex * tint;
}
