// Painted-stone surface for the look pass: world-space noise bends the blocky
// meshes into rock, adds strata, grime at the foot and moss on top faces.
shader_type spatial;
render_mode world_vertex_coords, diffuse_burley, cull_disabled;

uniform vec3 base_col : source_color = vec3(0.36, 0.35, 0.33);
uniform vec3 dark_col : source_color = vec3(0.10, 0.09, 0.09);
uniform vec3 moss_col : source_color = vec3(0.20, 0.25, 0.12);
uniform float disp = 0.25;
uniform float scale = 0.55;
uniform float moss = 0.5;
uniform float strata = 0.5;
uniform float bump = 0.6;
uniform float grime = 1.0;
uniform float streaks = 0.0;
// a painted texture from Adrian's image tool, laid on from three sides
uniform sampler2D tex : source_color, repeat_enable, filter_linear_mipmap;
uniform float use_tex = 0.0;
uniform float tex_scale = 0.22;
uniform vec3 tex_tint : source_color = vec3(1.0);

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	vec3 w = VERTEX;
	vec3 off = vec3(fbm(w * scale), fbm(w * scale + vec3(5.2, 1.3, 7.7)), fbm(w * scale + vec3(2.1, 9.4, 3.3))) - 0.47;
	VERTEX = w + off * disp * 2.0;
	wpos = VERTEX;
	wnrm = NORMAL;
}

void fragment() {
	vec3 p = wpos;
	float h = fbm(p * 0.8) * 0.75 + fbm(p * 3.0) * 0.25;
	if (streaks > 0.0) {
		h = mix(h, fbm(vec3(p.x * 9.0, p.y * 1.2, p.z * 9.0)), streaks);
	}
	// bump from the height field
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhdx = dFdx(h);
	float dhdy = dFdy(h);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	NORMAL = normalize(abs(det) * NORMAL - bump * grad);

	float band = 0.5 + 0.5 * sin(p.y * 3.1 + fbm(p * 0.7) * 6.0);
	vec3 c = mix(dark_col, base_col, smoothstep(0.1, 0.9, h));
	c *= mix(1.0, 0.75 + 0.5 * band, strata);
	float foot = smoothstep(0.0, 1.6, p.y);
	c *= mix(1.0, mix(0.45, 1.0, foot), grime);
	float m = smoothstep(0.35, 0.9, wnrm.y) * smoothstep(0.45, 0.6, fbm(p * 1.3)) * moss;
	c = mix(c, moss_col * (0.7 + 0.6 * h), m);
	if (use_tex > 0.0) {
		vec3 w = pow(abs(wnrm), vec3(4.0));
		w /= (w.x + w.y + w.z);
		vec3 t = texture(tex, p.zy * tex_scale).rgb * w.x + texture(tex, p.xz * tex_scale).rgb * w.y + texture(tex, p.xy * tex_scale).rgb * w.z;
		// break up the repeat with slow light and dark patches, keep a little relief from the noise
		float patch = mix(0.72, 1.18, fbm(p * 0.18));
		t *= patch * mix(0.85, 1.1, h);
		c = mix(c, t * tex_tint * mix(0.6, 1.0, foot), use_tex);
	}
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
}
