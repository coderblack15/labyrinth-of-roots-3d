// A soft shaft of light falling through dust: additive, fades at the ends and edges.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 col : source_color = vec3(1.0, 0.85, 0.6);
uniform float strength = 0.35;
varying vec3 lnorm;
void vertex() { lnorm = NORMAL; }
void fragment() {
	float ends = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.6, UV.y);
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.5);
	ALBEDO = col * strength * ends * edge;
}
