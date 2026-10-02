// Preview item (potion_3): the next hidden layer peeking out behind the top
// items. Same darkened, half-faded look as the old 50%-alpha sprite, but drawn
// SOLID — the fade is mixed toward fog_color (the cell panel over the game
// background) instead of done with alpha — so overlapping previews never show
// through each other. Retune fog_color if the game background changes.
// Node/cell modulate alpha (drop-in, conveyor fades) is still honoured.
shader_type canvas_item;

uniform vec4 shade : source_color = vec4(0.15, 0.15, 0.15, 1.0);
uniform vec4 fog_color : source_color = vec4(0.072, 0.084, 0.108, 1.0);
uniform float fade : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(mix(fog_color.rgb, tex.rgb * shade.rgb, fade), step(0.5, tex.a) * COLOR.a);
}
