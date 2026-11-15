// Piel de las piezas pintadas del cohete (las del jugador y las propias):
// - juntas de paneles cada ~1,2 m alrededor y ~2,5 m a lo largo, y larguerillos finos;
// - pintura con relieve de chapa (normal de Poly Haven) y algo de suciedad en manchas;
// - hollín que sube desde abajo en las piezas que van sobre los motores;
// - patrón de rodadura blanco y negro (como el V-2 o el Saturno V) si se elige;
// - espuma aislante con relieve irregular para los tanques de hidrógeno.
// Las medidas reales de la pieza (dims) hacen que el detalle tenga el mismo tamaño en
// una pieza chica o en una gigante. UV.x = vuelta (0..1), UV.y = de arriba (0) a abajo (1).
shader_type spatial;
render_mode cull_disabled; // por dentro también se ve (vista en corte)

// Vista en corte del hangar: se descarta la mitad de la piel que mira a la cámara
global uniform float xorbit_cut;
global uniform vec3 xorbit_cut_n;
global uniform vec3 xorbit_cut_o;
varying vec3 world_pos;

uniform vec3 paint : source_color = vec3(0.92, 0.93, 0.94);
uniform float metal = 0.0;
uniform float rough = 0.6;
uniform vec2 dims = vec2(3.0, 10.0); // circunferencia y largo en metros
uniform float pattern = 0.0; // 1 = patrón de rodadura
uniform float soot = 0.0; // 0..1 hollín desde abajo
uniform float foam = 0.0; // 1 = espuma aislante
uniform sampler2D plate_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grime : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h12(i), h12(i + vec2(1, 0)), f.x), mix(h12(i + vec2(0, 1)), h12(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (xorbit_cut > 0.5 && dot(world_pos - xorbit_cut_o, xorbit_cut_n) > 0.0) {
		discard;
	}
	vec2 m = UV * dims; // metros sobre la superficie
	float px = fwidth(m.x) + fwidth(m.y); // tamaño de un píxel en metros (para no parpadear de lejos)
	// Juntas de paneles
	vec2 cell = m / vec2(1.2, 2.5);
	vec2 f = abs(fract(cell) - 0.5) * vec2(1.2, 2.5); // distancia al centro del panel en metros
	float seam_d = min(0.6 - f.x, 1.25 - f.y);
	float seam = (1.0 - smoothstep(0.0, 0.008 + px, seam_d)) * (1.0 - smoothstep(0.02, 0.08, px)); // de lejos se desvanecen
	// Larguerillos verticales cada 0,3 m (muy suaves)
	float str = 1.0 - smoothstep(0.0, 0.01 + px, abs(fract(m.x / 0.3) - 0.5) * 0.3 - 0.13);
	// Remaches a lo largo de las juntas horizontales
	vec2 rv = vec2(fract(m.x / 0.15) - 0.5, (f.y - 1.18) / 0.15);
	float rivet = (1.0 - smoothstep(0.15, 0.3, length(rv))) * step(1.12, f.y);
	vec3 col = paint;
	// Patrón de rodadura: cuadrantes alternos en dos bandas
	float chk = mod(floor(UV.x * 4.0) + floor(UV.y * 2.0), 2.0);
	col = mix(col, vec3(0.04, 0.04, 0.045), chk * pattern);
	// Espuma: color irregular y relieve
	float fn = vnoise(m * 9.0) * 0.6 + vnoise(m * 31.0) * 0.4;
	col = mix(col, col * (0.82 + 0.3 * fn), foam);
	// Suciedad en manchas y chorreaduras verticales
	float g = texture(grime, m * vec2(0.18, 0.06)).r;
	float streak = vnoise(vec2(m.x * 3.0, m.y * 0.15));
	col *= mix(1.0, 0.72 + 0.45 * g, 0.28 * (1.0 - foam * 0.5));
	col *= 1.0 - 0.06 * smoothstep(0.55, 0.9, streak);
	// Hollín de los motores, subiendo desde el borde de abajo
	float s = soot * smoothstep(0.45, 1.0, UV.y + (g - 0.5) * 0.25);
	col = mix(col, vec3(0.05, 0.045, 0.04), s * 0.85);
	// Juntas más oscuras
	col *= 1.0 - seam * 0.13 * (1.0 - foam) - str * 0.025 * (1.0 - foam);
	col *= 1.0 - rivet * 0.12;
	// Cara interior (se ve en el corte): metal sin pintar, más oscuro
	if (!FRONT_FACING) {
		col = vec3(0.42, 0.43, 0.45) * (0.8 + 0.2 * g);
	}
	ALBEDO = col;
	ROUGHNESS = clamp(mix(rough, 0.95, foam) + seam * 0.15 + s * 0.3, 0.05, 1.0);
	METALLIC = metal * (1.0 - s);
	// Relieve: chapa de Poly Haven (pintura) o grumos (espuma)
	vec3 plate = texture(plate_nor, m * 0.5).rgb;
	vec3 bump = normalize(vec3((vnoise(m * 9.0 + 0.5) - 0.5) * 1.4, (vnoise(m * 9.0 + 7.3) - 0.5) * 1.4, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP = mix(plate, bump, foam);
	NORMAL_MAP_DEPTH = mix(0.35, 1.0, foam);
}
