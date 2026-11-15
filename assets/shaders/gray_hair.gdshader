shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
// Pelo canoso: la textura original de MakeHuman pasada a gris (conserva los mechones y su transparencia).
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.86, 0.86, 0.84);
uniform float lift = 1.9;

void fragment() {
	vec4 c = texture(tex, UV);
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	ALBEDO = clamp(vec3(lum * lift), 0.0, 1.0) * tint;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	NORMAL_MAP = texture(nrm, UV).rgb;
	ROUGHNESS = 0.7;
}
