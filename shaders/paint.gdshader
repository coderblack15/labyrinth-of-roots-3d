// Screen pass for the look pass: a Kuwahara filter turns the render into flat
// brush-like patches, then ink edges, a colour grade, canvas grain and a vignette.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform int radius = 2;
uniform float ink = 0.25;
uniform float grain = 0.03;
uniform vec3 shadow_tint : source_color = vec3(0.05, 0.13, 0.17);
uniform float saturation = 1.1;
uniform float contrast = 0.35;
uniform vec3 light_tint : source_color = vec3(1.04, 0.95, 0.84);

float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 uv = SCREEN_UV;
	vec3 m0 = vec3(0.0); vec3 m1 = vec3(0.0); vec3 m2 = vec3(0.0); vec3 m3 = vec3(0.0);
	float s0 = 0.0; float s1 = 0.0; float s2 = 0.0; float s3 = 0.0;
	float q0 = 0.0; float q1 = 0.0; float q2 = 0.0; float q3 = 0.0;
	for (int j = -radius; j <= radius; j++) {
		for (int i = -radius; i <= radius; i++) {
			vec3 c = texture(screen, uv + vec2(float(i), float(j)) * px * 1.25).rgb;
			float l = lum(c);
			if (i <= 0 && j <= 0) { m0 += c; s0 += l; q0 += l * l; }
			if (i >= 0 && j <= 0) { m1 += c; s1 += l; q1 += l * l; }
			if (i <= 0 && j >= 0) { m2 += c; s2 += l; q2 += l * l; }
			if (i >= 0 && j >= 0) { m3 += c; s3 += l; q3 += l * l; }
		}
	}
	float n = float((radius + 1) * (radius + 1));
	float v0 = q0 / n - (s0 / n) * (s0 / n);
	float v1 = q1 / n - (s1 / n) * (s1 / n);
	float v2 = q2 / n - (s2 / n) * (s2 / n);
	float v3 = q3 / n - (s3 / n) * (s3 / n);
	vec3 col = m0 / n;
	float best = v0;
	if (v1 < best) { best = v1; col = m1 / n; }
	if (v2 < best) { best = v2; col = m2 / n; }
	if (v3 < best) { best = v3; col = m3 / n; }

	// ink: darken strong luminance edges
	float lx = lum(texture(screen, uv + vec2(px.x * 2.0, 0.0)).rgb) - lum(texture(screen, uv - vec2(px.x * 2.0, 0.0)).rgb);
	float ly = lum(texture(screen, uv + vec2(0.0, px.y * 2.0)).rgb) - lum(texture(screen, uv - vec2(0.0, px.y * 2.0)).rgb);
	float e = smoothstep(0.12, 0.35, sqrt(lx * lx + ly * ly));
	col *= 1.0 - e * ink * 0.6;

	// grade: teal in the shadows, amber in the lights, richer colour, an S-curve
	float l = lum(col);
	col += shadow_tint * (1.0 - smoothstep(0.0, 0.45, l)) * 0.35;
	col = mix(col, col * light_tint * 1.12, smoothstep(0.35, 0.95, l));
	col = mix(vec3(lum(col)), col, saturation);
	col = clamp(col, 0.0, 1.0);
	col = mix(col, col * col * (3.0 - 2.0 * col), contrast);

	// canvas grain and weave
	vec2 fc = FRAGCOORD.xy;
	float g = hash(floor(fc / 2.0)) - 0.5;
	float weave = (sin(fc.x * 1.3) * sin(fc.y * 1.3)) * 0.5;
	col += (g + weave * 0.4) * grain;

	// vignette
	vec2 d = uv - 0.5;
	col *= 1.0 - dot(d, d) * 0.9;
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
