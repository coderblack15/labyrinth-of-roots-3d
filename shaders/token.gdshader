// A painted mini from the 2D game, standing on the board: the piece's painting in a round
// frame, with the life ring round it (as on the 2D mat). Created by: Adrian Blackshire and Claude.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D art : source_color, filter_linear_mipmap, repeat_disable;
uniform float hp = 1.0;
uniform vec4 ring_col : source_color = vec4(0.44, 0.82, 0.55, 1.0);
uniform vec4 rim_col : source_color = vec4(0.79, 0.66, 0.31, 1.0);
uniform float medal = 0.0;    // 1: the art is a whole medallion (no extra frame round it)
uniform float active = 0.0;   // glows gold when it's this piece's turn
uniform float down = 0.0;     // greyed when beaten
uniform float light = 1.2;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	vec3 c;
	float inner = medal > 0.5 ? 0.86 : 0.78;
	if (r < inner) {
		vec2 uv = p / inner * (medal > 0.5 ? 1.0 : 0.98) * 0.5 + 0.5;
		vec4 a = texture(art, uv);
		if (medal > 0.5 && a.a < 0.5) {
			c = vec3(0.08, 0.06, 0.05);
		} else {
			c = smoothstep(vec3(0.0), vec3(0.75), a.rgb);
		}
		// a soft vignette, like the 2D mat's minis
		c *= mix(1.0, 0.72, smoothstep(inner * 0.6, inner, r));
	} else if (r < inner + 0.03) {
		c = rim_col.rgb * 0.45;
	} else if (r < 0.95) {
		float a = fract(atan(p.x, p.y) / 6.2831853 + 0.5);
		c = a <= hp ? ring_col.rgb : vec3(0.17, 0.07, 0.06);
	} else {
		c = rim_col.rgb * 0.55;
	}
	c = mix(c, vec3(dot(c, vec3(0.3, 0.59, 0.11))) * 0.6, down);
	c *= light;
	c += vec3(0.95, 0.75, 0.3) * active * smoothstep(0.9, 1.0, r) * 0.9;
	ALBEDO = c;
}
