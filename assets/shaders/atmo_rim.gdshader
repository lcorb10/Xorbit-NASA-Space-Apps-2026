// Halo de atmósfera para el mapa: brilla en el borde del planeta (efecto Fresnel), más del lado iluminado.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(0.35, 0.6, 1.0);
uniform float strength = 1.6;
uniform float power = 3.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), power);
	ALBEDO = color * rim * strength;
}
