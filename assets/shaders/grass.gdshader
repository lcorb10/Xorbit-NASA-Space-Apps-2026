// Hojas de pasto: verde oscuro en la base y claro en la punta, se mecen con ráfagas de
// viento que recorren el campo, y dejan pasar la luz del sol (se ven translúcidas a contraluz).
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;

uniform vec3 base_col : source_color = vec3(0.09, 0.13, 0.04);
uniform vec3 tip_col : source_color = vec3(0.42, 0.52, 0.2);
uniform vec3 dry_col : source_color = vec3(0.58, 0.52, 0.3);
uniform float wind_strength = 0.22;

varying float hgt;
varying float dry;
varying float shade;

void vertex() {
	hgt = COLOR.r;
	dry = INSTANCE_CUSTOM.r;
	shade = 0.8 + 0.4 * INSTANCE_CUSTOM.g;
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// Ráfagas: una onda lenta que cruza el campo y un temblor rápido
	float gust = sin(TIME * 0.9 - wp.x * 0.05 - wp.z * 0.03) * 0.5 + 0.5;
	float flutter = sin(TIME * 4.1 + wp.x * 0.7 + wp.z * 0.4) * 0.25;
	float bend = (gust * 0.9 + flutter) * hgt * hgt * wind_strength;
	VERTEX.x += bend;
	VERTEX.z += bend * 0.4;
	VERTEX.y -= bend * bend * 0.6; // al doblarse baja un poco
}

void fragment() {
	vec3 tip = mix(tip_col, dry_col, dry * 0.75);
	vec3 c = mix(base_col, tip, smoothstep(0.0, 1.0, hgt)) * shade;
	ALBEDO = c;
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
	AO = mix(0.35, 1.0, hgt);
	AO_LIGHT_AFFECT = 0.6;
	BACKLIGHT = c * 0.6;
	// Normales hacia arriba: el pasto se ilumina como el suelo y no parpadea
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, 0.6));
}
