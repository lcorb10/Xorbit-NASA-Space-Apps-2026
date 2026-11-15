shader_type spatial;
render_mode unshaded;
// Ventana de la cabina: cielo según la altitud (0 = suelo, 1 = espacio), estrellas y la curva de la Tierra.
uniform float altitude : hint_range(0.0, 1.0) = 0.0;
uniform float tilt = 0.0; // inclinación del cohete (mueve el horizonte)

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	float h = uv.y + tilt * 0.4; // 0 arriba, 1 abajo
	vec3 sky_low = mix(vec3(0.55, 0.72, 0.92), vec3(0.02, 0.03, 0.08), altitude);
	vec3 sky_high = mix(vec3(0.25, 0.45, 0.8), vec3(0.0, 0.0, 0.01), altitude);
	vec3 c = mix(sky_high, sky_low, clamp(h, 0.0, 1.0));
	// Estrellas cuando ya no hay aire
	vec2 g = floor(uv * vec2(180.0, 120.0));
	float s = step(0.996, hash(g)) * smoothstep(0.5, 1.0, altitude);
	c += vec3(s);
	// La Tierra: borde curvo abajo, con la línea azul de la atmósfera
	float curve = 0.82 - 0.25 * altitude + 0.12 * pow(uv.x - 0.5, 2.0) * (1.0 + 3.0 * altitude) + tilt * 0.4;
	float earth = smoothstep(curve, curve + 0.01, uv.y);
	vec3 ground = mix(vec3(0.2, 0.35, 0.2), vec3(0.1, 0.25, 0.55), altitude);
	float rim = exp(-abs(uv.y - curve) * 60.0) * altitude;
	c = mix(c, ground * (0.8 + 0.2 * hash(floor(uv * 40.0))), earth);
	c += vec3(0.3, 0.55, 1.0) * rim;
	// Vidrio: un reflejo suave
	c += vec3(0.08) * smoothstep(0.3, 0.0, abs(uv.x - uv.y * 0.6 - 0.2));
	ALBEDO = c;
}
