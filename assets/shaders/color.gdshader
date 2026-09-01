shader_type canvas_item;

// Repaints whatever it is put on in one flat colour. The texture decides the
// shape, the uniform decides the colour, and whatever the file was drawn in
// stops mattering — so a single .svg can serve every state a button has.

// source_color is what makes the editor offer a colour picker and hand the
// value over in the space the texture is read in. Without the hint the colour
// that comes out on screen is not the one that was picked.
uniform vec4 tint : source_color = vec4(1.0);

// 1.0 replaces the colour outright. 0.0 leaves the texture exactly as it would
// look with no material at all, and in between is a wash — which is usually
// what a hover or a disabled state wants.
uniform float amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 source = texture(TEXTURE, UV);

	// COLOR is the node's modulate. Folding it into the untinted side keeps
	// amount = 0.0 identical to having no shader.
	vec3 original = source.rgb * COLOR.rgb;

	// Only the RGB is replaced. The alpha stays the texture's own, so the shape
	// and its antialiased edge survive, and it keeps being multiplied by the
	// modulate's alpha, so fading a node in and out still works.
	COLOR = vec4(mix(original, tint.rgb, amount), source.a * tint.a * COLOR.a);
}
