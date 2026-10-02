// Preview item (potion_3): the next hidden layer peeking out behind the top
// items. Darkened and half-faded, but drawn SOLID — the fade is mixed toward
// fog_color instead of done with alpha — so overlapping previews never show
// through each other. Cell.gd sets fog_color to the box's velvet lining
// (LINING_* constants), so previews read as sunk into the box.
// Node/cell modulate alpha (drop-in, conveyor fades) is still honoured.
shader_type canvas_item;

uniform vec4 shade : source_color = vec4(0.15, 0.15, 0.15, 1.0);
uniform vec4 fog_color : source_color = vec4(0.094, 0.247, 0.224, 1.0);   // teal velvet #183f39
uniform float fade : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(mix(fog_color.rgb, tex.rgb * shade.rgb, fade), step(0.5, tex.a) * COLOR.a);
}
