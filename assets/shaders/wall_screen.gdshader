shader_type spatial;
render_mode unshaded, cull_disabled;
// Pantalla grande de la Sala de Control: mapa del mundo esquemático con la trayectoria del cohete.
uniform float progress : hint_range(0.0, 1.0) = 0.3;
uniform vec3 track : source_color = vec3(1.0, 0.6, 0.2);
// Imagen en vivo del cohete (cámara del vuelo) en la pantalla grande; con use_feed = 1 reemplaza al mapa
uniform sampler2D feed : source_color, filter_linear;
uniform float use_feed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// El modelo no trae UV útiles en la pantalla: se usa la posición (x de -7,9 a 1,6; y de 1,1 a 4,7)
varying vec3 obj;
void vertex() {
	obj = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = vec2((obj.x + 7.9) / 9.5, 1.0 - (obj.y - 1.1) / 3.6);
	vec3 c = vec3(0.02, 0.05, 0.11);
	float land = smoothstep(0.55, 0.6, noise(uv * vec2(7.0, 4.0)) * 0.7 + noise(uv * vec2(17.0, 9.0)) * 0.3);
	c = mix(c, vec3(0.06, 0.16, 0.22), land);
	vec2 g = abs(fract(uv * vec2(12.0, 6.0)) - 0.5);
	c += vec3(0.05, 0.12, 0.2) * smoothstep(0.48, 0.5, max(g.x, g.y));
	float y = 0.5 + 0.28 * sin(uv.x * 6.2831 * 1.5 + 1.0);
	float on = smoothstep(0.006, 0.0, abs(uv.y - y)) * step(uv.x, progress);
	float ahead = smoothstep(0.004, 0.0, abs(uv.y - y)) * step(progress, uv.x) * step(0.5, fract(uv.x * 60.0));
	c += track * on * 1.6 + vec3(0.4, 0.5, 0.6) * ahead * 0.5;
	vec2 ship = vec2(progress, 0.5 + 0.28 * sin(progress * 6.2831 * 1.5 + 1.0));
	c += track * smoothstep(0.012, 0.0, length((uv - ship) * vec2(1.6, 1.0))) * (1.5 + sin(TIME * 6.0));
	if (use_feed > 0.5) {
		vec3 f = texture(feed, uv).rgb;
		// marco fino y una franja con el mapa abajo, como en la sala real
		float frame = step(0.985, max(abs(uv.x - 0.5), abs(uv.y - 0.5)) * 2.0);
		c = mix(f, c, step(0.86, uv.y) * 0.85);
		c = mix(c, vec3(1.0, 0.6, 0.2), frame);
	}
	ALBEDO = c;
}
