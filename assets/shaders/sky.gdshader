// Cielo del juego: de día, una foto HDR de cielo real (Poly Haven, CC0); al subir,
// se oscurece hasta el espacio: estrellas de varios brillos y colores, Vía Láctea y
// el disco del Sol (en el espacio el Sol se ve blanco y nítido, sin aire que lo difumine).
shader_type sky;
render_mode use_debanding;

uniform sampler2D pano : filter_linear, hint_default_black;
uniform float pano_energy = 1.0;
uniform float pano_offset = 0.0; // giro horizontal de la foto (vueltas) para alinear su sol con la luz
uniform float space : hint_range(0.0, 1.0) = 0.0; // 0 = cielo con aire, 1 = espacio
uniform float star_energy = 1.0;
uniform float night : hint_range(0.0, 1.0) = 0.0; // 1 = de noche en la Tierra (modo noche)
uniform vec3 moon_dir = vec3(0.4, 0.55, 0.73);

float h13(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h13(i), h13(i + vec3(1, 0, 0)), f.x), mix(h13(i + vec3(0, 1, 0)), h13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h13(i + vec3(0, 0, 1)), h13(i + vec3(1, 0, 1)), f.x), mix(h13(i + vec3(0, 1, 1)), h13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p *= 2.07;
		a *= 0.5;
	}
	return s;
}

// Una capa de estrellas: una (o ninguna) por celda de una cuadrícula sobre la esfera
vec3 star_layer(vec3 d, float cells, float keep, float seed) {
	vec3 p = d * cells;
	vec3 c = floor(p);
	vec3 col = vec3(0.0);
	for (int k = 0; k < 2; k++) { // celda propia y la vecina más cercana, para no cortar estrellas
		vec3 cc = c + (k == 0 ? vec3(0.0) : sign(fract(p) - 0.5));
		float h = h13(cc + seed);
		if (h > keep) {
			vec3 o = vec3(h13(cc + seed + 1.7), h13(cc + seed + 4.3), h13(cc + seed + 8.9));
			vec3 sp = normalize((cc + 0.2 + 0.6 * o) / cells);
			float dist = length(sp - d);
			float b = pow((h - keep) / (1.0 - keep), 3.0);
			float r = 0.00055 * (0.8 + 1.4 * b); // radio angular: un píxel o dos
			float s = exp(-dist * dist / (r * r));
			// Color según la temperatura: rojizas, amarillas, blancas, azuladas
			float tcol = h13(cc + seed + 13.1);
			vec3 tint = tcol < 0.2 ? vec3(1.0, 0.72, 0.55) : (tcol < 0.5 ? vec3(1.0, 0.92, 0.8) : (tcol < 0.85 ? vec3(0.95, 0.97, 1.0) : vec3(0.72, 0.82, 1.0)));
			col += tint * s * (0.25 + 4.0 * b);
		}
	}
	return col;
}

vec3 space_sky(vec3 d) {
	vec3 col = vec3(0.0);
	col += star_layer(d, 90.0, 0.955, 0.0);
	col += star_layer(d, 210.0, 0.97, 31.0) * 0.5;
	// Vía Láctea: una banda difusa con polvo oscuro y muchas estrellas débiles
	vec3 gn = normalize(vec3(0.35, 0.62, -0.7));
	float lat = dot(d, gn);
	float band = exp(-lat * lat * 14.0);
	float cloud = fbm(d * 7.0);
	float dust = smoothstep(0.45, 0.7, fbm(d * 13.0 + 4.0));
	col += vec3(0.62, 0.6, 0.72) * band * (0.012 + 0.05 * cloud) * (1.0 - 0.7 * dust);
	col += star_layer(d, 420.0, 0.9, 77.0) * 0.35 * band;
	return col * star_energy;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec2 uv = vec2(fract(atan(d.x, -d.z) / TAU + 0.5 + pano_offset), acos(clamp(d.y, -1.0, 1.0)) / PI);
	vec3 day = texture(pano, uv).rgb * pano_energy;
	// Al subir, el azul se oscurece primero arriba y al final en el horizonte
	float up = clamp(d.y, 0.0, 1.0);
	float fade = clamp(space * (2.2 - 0.6 * (1.0 - up)), 0.0, 1.0); // a ~50 km ya no queda nada de la foto (nubes)
	vec3 col = day * (1.0 - fade) * (1.0 - night);
	// Noche: azul muy oscuro, algo más claro en el horizonte (resplandor de la ciudad), Luna
	float hz = 1.0 - clamp(d.y * 3.0, 0.0, 1.0);
	vec3 night_col = mix(vec3(0.004, 0.008, 0.02), vec3(0.03, 0.04, 0.07), hz * hz) + vec3(0.05, 0.035, 0.02) * pow(hz, 6.0);
	col += night_col * night * (1.0 - fade);
	float md = dot(d, normalize(moon_dir));
	col += (vec3(1.0, 0.97, 0.9) * smoothstep(0.99985, 0.9999, md) * 6.0 + vec3(0.5, 0.6, 0.8) * pow(max(md, 0.0), 200.0) * 0.25) * night * (1.0 - fade);
	// Estrellas: aparecen cuando el cielo ya está oscuro (en el espacio o de noche)
	col += space_sky(d) * max(smoothstep(0.55, 1.0, space), night * 0.8 * smoothstep(-0.02, 0.15, d.y));
	// Sol: disco nítido con un halo leve (el de la foto se desvanece con el aire)
	if (LIGHT0_ENABLED) {
		float sd = dot(d, LIGHT0_DIRECTION);
		float disk = smoothstep(0.99996, 0.99998, sd);
		float glow = pow(max(sd, 0.0), 900.0) * 0.8 + pow(max(sd, 0.0), 60.0) * 0.04;
		col += LIGHT0_COLOR * (disk * 60.0 + glow * 3.0) * fade * (1.0 - night);
	}
	COLOR = col;
}
