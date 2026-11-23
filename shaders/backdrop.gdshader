// A painting as the far distance: mirrored so a narrow crop covers a wide sky.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float crop = 0.45;
uniform float top = 0.0;
uniform float bottom = 0.8;
uniform float bright = 1.0;
void fragment() {
	float x = UV.x * 2.0;
	float u = (x < 1.0 ? x : 2.0 - x) * crop;
	vec3 c = texture(tex, vec2(u, mix(top, bottom, UV.y))).rgb;
	ALBEDO = c * bright;
}
