// Blinking (Pete, 27 Nov; reworked after the 27 Nov review): drawn over the body as its overlay, only inside each
// eye's oval in the texture, so the lid is the face itself: lit like it, and behind the hair wherever the hair is in
// front. A skin-coloured lid comes down from the top of the eye to `shut` (0 open, 1 shut) with a dark edge; shut,
// that edge is the closed-eye curve along the bottom of the oval. Everything else is discarded.
shader_type spatial;
render_mode cull_disabled, depth_draw_never;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 skin_uv;            // a skin texel just under the eyes
uniform float shut = 0.0;
uniform int eye_count = 0;
uniform vec2 eye_c[2];           // each eye's centre in the texture
uniform vec2 eye_r[2];           // its half-width (towards the face's right) in the texture
uniform vec2 eye_u[2];           // its half-height (up the face) in the texture
uniform float roughness_v = 0.62;
uniform float metallic_v = 0.05;
uniform float rim_v = 0.5;
uniform float rim_tint_v = 0.6;

const float SIZE = 1.6;          // the lid is bigger than the dark of the eye, so none of its rim shows round it
const float LINE = 0.2;          // how thick the lid's edge is (eye half-heights)

void fragment() {
	float lid = 0.0;
	float edge_line = 0.0;
	vec3 skin = texture(albedo_tex, skin_uv).rgb;
	for (int i = 0; i < 2; i++) {
		if (i >= eye_count) { break; }
		mat2 m = mat2(eye_r[i], eye_u[i]);
		vec2 q = inverse(m) * (UV - eye_c[i]);   // x: -1 left .. 1 right, y: -1 bottom .. 1 top of the eye
		float r = length(q);
		if (r > SIZE) { continue; }
		float edge = SIZE - 2.0 * SIZE * shut;   // where the lid has come down to
		if (q.y >= edge) {
			// the lid's colour: blended from the face just outside the eye on all four sides, so it carries on the
			// texture's own shading with no seam round it
			float o = SIZE + 0.25;
			vec3 up = texture(albedo_tex, eye_c[i] + eye_r[i] * q.x + eye_u[i] * o).rgb;
			vec3 dn = texture(albedo_tex, eye_c[i] + eye_r[i] * q.x - eye_u[i] * o).rgb;
			vec3 rt = texture(albedo_tex, eye_c[i] + eye_r[i] * o + eye_u[i] * q.y).rgb;
			vec3 lf = texture(albedo_tex, eye_c[i] - eye_r[i] * o + eye_u[i] * q.y).rgb;
			vec4 w = 1.0 / max(vec4(o - q.y, o + q.y, o - q.x, o + q.x), vec4(0.05));
			skin = (up * w.x + dn * w.y + rt * w.z + lf * w.w) / (w.x + w.y + w.z + w.w);
			lid = 1.0 - smoothstep(SIZE - 0.2, SIZE, r);   // a soft rim, so no hard oval shows
			float across = (1.0 - smoothstep(0.0, LINE, q.y - edge)) * step(0.04, shut) * (1.0 - smoothstep(0.7, 0.95, shut));
			// shut: a curve like the bottom of the eye (a U), as a drawn closed eye
			float arc = (1.0 - smoothstep(0.07, 0.16, abs(r - 0.95))) * smoothstep(0.1, -0.2, q.y) * smoothstep(0.6, 0.9, shut);
			edge_line = max(across, arc);
		}
	}
	if (lid < 0.01) {
		discard;
	}
	ALBEDO = mix(skin, vec3(0.045, 0.04, 0.045), edge_line);
	ALPHA = lid;
	ROUGHNESS = roughness_v;
	METALLIC = metallic_v;
	RIM = rim_v;
	RIM_TINT = rim_tint_v;
}
