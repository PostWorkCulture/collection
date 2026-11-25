// Moving light on the pool floor (AAA phase 3): the bright wavy net that sunlit water throws on the tiles.
// Drawn on a thin sheet just above the floor and added to what's there.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec3 colour : source_color = vec3(0.75, 0.95, 1.0);
uniform float strength = 0.22;
uniform float scale = 0.7;     // per metre
uniform float speed = 0.35;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// a few rounds of warping sine waves: the usual cheap water-caustic pattern
	vec2 p = mod(wpos.xz * scale * 6.2831, 6.2831) - 250.0;
	vec2 i = p;
	float c = 1.0;
	float inten = 0.005;
	float t = TIME * speed;
	for (int n = 0; n < 5; n++) {
		float tt = t * (1.0 - 3.5 / float(n + 1));
		i = p + vec2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
		c += 1.0 / length(vec2(p.x / (sin(i.x + tt) / inten), p.y / (cos(i.y + tt) / inten)));
	}
	c /= 5.0;
	c = 1.17 - pow(c, 1.4);
	float v = pow(abs(c), 8.0);
	ALBEDO = colour * clamp(v, 0.0, 1.0) * strength;
}
