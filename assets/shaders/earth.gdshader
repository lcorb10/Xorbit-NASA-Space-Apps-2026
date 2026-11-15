// La Tierra vista desde el cohete: fotos de la NASA (Blue Marble de día y las luces de
// las ciudades de noche, dominio público), nubes que se mueven, brillo del Sol en el mar
// y el borde entre el día y la noche (terminador) suave y anaranjado.
shader_type spatial;
render_mode cull_back;

uniform sampler2D day_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D night_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0); // hacia el Sol, en el mundo
uniform float cloud_shift = 0.0;
uniform sampler2D cloud_tex : filter_linear_mipmap_anisotropic, repeat_enable; // tools/gen_nubes.gd

varying vec3 w_nrm;
varying vec3 o_dir;

void vertex() {
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	o_dir = normalize(VERTEX);
}

void fragment() {
	vec3 day = texture(day_tex, UV).rgb;
	vec3 night = texture(night_tex, UV).rgb;
	vec3 n = normalize(w_nrm);
	float ndl = dot(n, normalize(sun_dir));
	float lit = smoothstep(-0.08, 0.18, ndl);
	// Nubes: el mapa se desplaza despacio hacia el este
	float cl = texture(cloud_tex, UV + vec2(cloud_shift, 0.0)).r;
	// Detalle fino para verlas de cerca (el mismo mapa a otra escala)
	float fine = texture(cloud_tex, UV * vec2(11.0, 9.0) + vec2(0.37, 0.11)).r;
	cl = smoothstep(0.3, 0.85, clamp(cl * (0.55 + 0.9 * fine) * 1.15, 0.0, 1.0)); // menos nubes: se ve más la tierra
	// Mar: donde el azul domina
	float ocean = clamp((day.b - day.r) * 5.0, 0.0, 1.0) * (1.0 - cl);
	// Detalle fino en tierra firme para verla de cerca (la foto tiene ~2,4 km por píxel)
	float land = 1.0 - clamp((day.b - day.r) * 5.0, 0.0, 1.0);
	float det = texture(cloud_tex, UV * vec2(420.0, 210.0)).r * 0.6 + texture(cloud_tex, UV * vec2(1300.0, 650.0)).r * 0.4;
	vec3 surface = day * 1.15 * mix(1.0, 0.82 + 0.36 * det, land);
	ALBEDO = mix(surface, vec3(0.93, 0.94, 0.96), cl * 0.9);
	ROUGHNESS = mix(0.95, 0.28, ocean);
	SPECULAR = mix(0.15, 0.7, ocean);
	METALLIC = 0.0;
	// Atardecer: el borde del día se tiñe de naranja
	float dusk = exp(-pow(ndl * 7.0, 2.0));
	EMISSION = vec3(0.35, 0.12, 0.03) * dusk * 0.25;
	// Luces de las ciudades en el lado de noche (las nubes las tapan)
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	EMISSION += vec3(0.1, 0.2, 0.45) * (0.05 + 0.6 * pow(rim, 3.0)) * lit;
	EMISSION += vec3(0.5) * cl * lit * 0.15; // las nubes reflejan mucha luz
	EMISSION += pow(night, vec3(1.6)) * vec3(1.0, 0.82, 0.55) * 2.2 * (1.0 - lit) * (1.0 - cl * 0.85);
}
