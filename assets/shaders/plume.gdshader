// Llama del motor: brillante en el centro y suave en los bordes, con turbulencia que
// corre hacia abajo, núcleo casi blanco junto a la tobera y "diamantes de choque"
// (las bandas brillantes que se ven en el escape al nivel del mar).
// UV.y = 0 en la tobera, 1 en la punta de la llama. Colores en HDR: el brillo sale con el glow.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.55, 0.2);
uniform float energy = 3.0;
uniform float diamonds = 1.0; // 1 al nivel del mar, 0 en el vacío
uniform float alpha = 1.0;
uniform float seed = 0.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

void fragment() {
	float along = UV.y;
	float facing = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float edge = pow(facing, 1.6); // centro de la silueta brillante, bordes suaves
	float n = texture(noise_tex, vec2(UV.x * 2.0 + seed, along * 1.3 - TIME * 3.2)).r;
	float n2 = texture(noise_tex, vec2(UV.x * 5.0 - seed, along * 3.1 - TIME * 6.0)).r;
	float fade = pow(1.0 - along, 1.6) * smoothstep(0.0, 0.04, along);
	float d = diamonds * smoothstep(0.55, 0.95, sin(along * 46.0) * 0.5 + 0.5) * (1.0 - smoothstep(0.05, 0.5, along));
	vec3 col = color * energy * edge * fade * (0.45 + 0.75 * n * n2 * 1.6);
	col += vec3(1.0, 0.9, 0.75) * energy * 0.9 * d * edge;
	col += vec3(1.0, 0.97, 0.9) * energy * 1.6 * pow(facing, 5.0) * (1.0 - smoothstep(0.0, 0.22, along));
	ALBEDO = col * alpha;
}
