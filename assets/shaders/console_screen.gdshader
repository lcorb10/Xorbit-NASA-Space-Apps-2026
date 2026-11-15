shader_type spatial;
render_mode unshaded, cull_disabled;
// Pantallas de las consolas de la Sala de Control: datos que se mueven (filas de texto y una gráfica).
uniform vec3 tint : source_color = vec3(0.35, 0.85, 1.0);
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed) * 43758.5453); }

void fragment() {
	// Las pantallas del modelo comparten UV: se usan coordenadas del mundo para variar el contenido
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 q = vec2(w.x * 1.8 + w.z * 0.7, w.y * 3.0);
	vec2 uv = fract(q);
	vec2 cell = floor(q);
	float t = TIME * 0.6 + hash(cell) * 10.0;
	vec3 c = vec3(0.01, 0.025, 0.05);
	float row = floor(uv.y * 9.0);
	float len = hash(vec2(row, floor(t * 0.5) + cell.x));
	float txt = step(fract(uv.y * 9.0), 0.55) * step(uv.x, 0.1 + 0.6 * len) * step(0.08, uv.x);
	c += tint * txt * 0.55 * step(0.4, hash(cell + 3.0));
	float g = 0.5 + 0.3 * sin(uv.x * 9.0 + t * 2.0 + hash(cell) * 6.0);
	c += vec3(0.3, 1.0, 0.5) * smoothstep(0.03, 0.0, abs(uv.y - g)) * step(hash(cell + 7.0), 0.4);
	ALBEDO = c * 1.6;
}
