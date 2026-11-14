shader_type canvas_item;

// Blends whatever is being drawn toward a solid colour.
// flash_amount 0 = normal look, 1 = fully flash_color.
// Used for the white flash when something is hit. It works on placeholder shapes
// and will keep working unchanged once real sprites replace them.

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 base = COLOR;
	COLOR = vec4(mix(base.rgb, flash_color.rgb, flash_amount), base.a);
}
