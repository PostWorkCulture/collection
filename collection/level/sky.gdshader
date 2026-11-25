// Afternoon sky (AAA phase 3): a blue gradient to a pale horizon, a soft sun and drifting-looking but still
// fair-weather clouds. Nothing here moves, so the sky light is worked out once, not every frame.
shader_type sky;

uniform vec3 top : source_color = vec3(0.30, 0.50, 0.84);
uniform vec3 horizon : source_color = vec3(0.74, 0.82, 0.91);
uniform vec3 ground : source_color = vec3(0.62, 0.66, 0.6);
uniform float cover = 0.48;            // 0 clear .. 1 overcast
uniform float cloud_scale = 0.55;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 6; i++) {
		s += vnoise(p) * a;
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col;
	if (d.y >= 0.0) {
		col = mix(horizon, top, pow(d.y, 0.55));
	} else {
		col = mix(horizon, ground, clamp(-d.y * 6.0, 0.0, 1.0));
	}
	vec3 sun_dir = LIGHT0_DIRECTION;
	float sa = max(dot(d, sun_dir), 0.0);
	vec3 sun_col = LIGHT0_COLOR * LIGHT0_ENERGY;
	col += sun_col * (pow(sa, 600.0) * 0.6 + pow(sa, 12.0) * 0.07);   // glare round the sun
	if (d.y > 0.0) {
		// clouds on a flat layer overhead, thinning towards the horizon
		vec2 uv = d.xz / (d.y + 0.12) * cloud_scale;
		float n = fbm(uv * 1.6 + vec2(3.1, 7.7));
		float c = smoothstep(1.0 - cover, 1.0 - cover + 0.28, n);
		float thick = smoothstep(1.0 - cover, 1.0, fbm(uv * 1.6 + vec2(3.1, 7.7) + sun_dir.xz * 0.06));
		vec3 lit = mix(vec3(1.0, 0.98, 0.95), horizon * 0.82, thick * 0.7);   // sunny tops, grey-blue bellies
		lit += sun_col * pow(sa, 6.0) * 0.25 * (1.0 - thick);                  // silver lining near the sun
		c *= smoothstep(0.0, 0.18, d.y);
		col = mix(col, lit, c * 0.9);
	}
	if (!AT_CUBEMAP_PASS) {
		col += sun_col * smoothstep(0.99985, 0.99995, sa) * 12.0;   // the disc itself (kept out of the sky light)
	}
	COLOR = col;
}
