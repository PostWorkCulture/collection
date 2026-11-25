// Pool and hot-tub water (AAA phase 3): a clear surface you see the tiles through, bent by small moving ripples,
// tinted deeper where the water is deeper, with sharp reflections of the lights and sky at a glancing angle.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 tint : source_color = vec3(0.5, 0.84, 0.92);    // what a thin layer does to the light through it
uniform vec3 deep : source_color = vec3(0.03, 0.3, 0.45);   // the colour it tends to with depth
uniform float absorb = 0.9;           // per metre
uniform float wave_scale = 0.9;        // ripples per metre
uniform float speed = 1.0;
uniform float chop = 0.16;             // ripple height in the normal
uniform float refraction = 0.01;

varying vec3 wpos;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453);
}

float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(dot(hash2(i), f), dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
			mix(dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)), dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}

float ripples(vec2 p, float t) {
	return gnoise(p * 1.3 + vec2(t * 0.11, t * 0.07)) * 0.5
		+ gnoise(p * 2.9 - vec2(t * 0.09, -t * 0.13)) * 0.3
		+ gnoise(p * 6.3 + vec2(-t * 0.21, t * 0.17)) * 0.12;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float view_depth(vec2 uv, mat4 inv_proj) {
	float z = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, z, 1.0);
	return v.z / v.w;
}

void fragment() {
	float t = TIME * speed;
	vec2 p = wpos.xz * wave_scale;
	float e = 0.04;
	float h0 = ripples(p, t);
	vec2 g = vec2(ripples(p + vec2(e, 0.0), t) - h0, ripples(p + vec2(0.0, e), t) - h0) / e;
	vec3 nw = normalize(vec3(-g.x * chop, 1.0, -g.y * chop));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// what's under the surface, nudged by the ripples (but never by something in front of the water)
	vec2 ruv = clamp(SCREEN_UV + g * refraction, vec2(0.001), vec2(0.999));
	float d = VERTEX.z - view_depth(ruv, INV_PROJECTION_MATRIX);
	if (d < 0.0) {
		ruv = SCREEN_UV;
		d = VERTEX.z - view_depth(ruv, INV_PROJECTION_MATRIX);
	}
	d = clamp(d, 0.0, 8.0);
	vec3 below = textureLod(screen_tex, ruv, 0.0).rgb;
	vec3 col = mix(below * tint, deep, 1.0 - exp(-d * absorb));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	ALBEDO = vec3(0.0);
	EMISSION = col * (1.0 - fres * 0.8);
	ROUGHNESS = 0.02;
	METALLIC = 0.0;
	SPECULAR = 0.65;
}
