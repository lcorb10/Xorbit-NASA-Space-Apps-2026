shader_type spatial;
// Visor del casco: vidrio oscuro reflectante con una pantalla interna que dibuja los ojos.
// Los ojos se ubican por ángulo sobre la superficie curva del visor (no es un plano flotando),
// brillan bajo el reflejo y se curvan con el vidrio.
// mood: 0 normal, 1 feliz (^ ^), 2 impaciente (párpado caído y ceja), 3 pánico (O O). blink: 0..1.
uniform vec3 eye_color : source_color = vec3(1.0, 0.6, 0.2);
uniform int mood = 0;
uniform float blink = 0.0;

varying vec3 local_dir;

void vertex() {
	local_dir = normalize(VERTEX);
}

float box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Un ojo en coordenadas centradas (unidades ~ alto del ojo). mirror = 1 para el ojo izquierdo.
float eye(vec2 p, float mirror) {
	if (mood == 1) { // feliz: arco cerrado hacia arriba
		float r = length(p - vec2(0.0, -0.55));
		return smoothstep(0.16, 0.06, abs(r - 0.7)) * step(-0.2, p.y);
	}
	if (mood == 3) { // pánico: anillos grandes
		return smoothstep(0.14, 0.05, abs(length(p) - 0.75));
	}
	float h = mix(0.7, 0.06, blink);
	if (mood == 2) {
		h = min(h, 0.42); // párpado a media altura
	}
	float d = box(p, vec2(0.45, h), 0.3);
	float e = smoothstep(0.06, -0.02, d);
	if (mood == 2) { // ceja inclinada hacia el centro
		float brow = p.y - (0.55 + 0.35 * p.x * mirror);
		e = max(e * step(brow, -0.12), smoothstep(0.08, 0.0, abs(brow)) * step(abs(p.x), 0.7));
	}
	return e;
}

void fragment() {
	// Ángulos sobre la esfera del visor: u = izquierda/derecha, v = arriba/abajo
	float u = atan(local_dir.x, local_dir.z);
	float v = asin(clamp(local_dir.y, -1.0, 1.0));
	vec2 p = vec2(u, v - 0.06) / 0.16;
	float e = eye(p - vec2(-1.55, 0.0), 1.0) + eye((p - vec2(1.55, 0.0)) * vec2(-1.0, 1.0), -1.0);
	e *= step(0.0, local_dir.z); // solo en la parte de adelante
	// Vidrio: casi negro, muy liso y metálico (refleja la cabina)
	ALBEDO = vec3(0.015, 0.018, 0.024);
	METALLIC = 0.85;
	ROUGHNESS = 0.06;
	SPECULAR = 0.8;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.02;
	// Pantalla interna: ojos, un halo tenue y líneas de píxeles
	float px = 0.8 + 0.2 * step(0.5, fract(v * 140.0));
	float glow = smoothstep(1.4, 0.0, length(p * vec2(0.45, 1.0))) * 0.06;
	EMISSION = eye_color * (e * 2.4 * px + glow);
}
