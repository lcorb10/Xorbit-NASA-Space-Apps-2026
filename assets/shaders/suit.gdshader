shader_type spatial;
// Ropa de la tripulación sobre el maniquí UAL.
// outfit 0: traje de cabina (IVA) blanco y negro con el color del puesto en los hombros.
// outfit 1: controlador de vuelo: polo del color del puesto, pantalón oscuro, manos y cabeza con piel.
// Máscaras en COLOR (assets/models/crew/astronaut/FUENTE.md): R guantes/botas, G hombros, B cabeza, A piernas.
uniform int outfit = 0;
uniform vec3 role_color : source_color = vec3(1.0, 0.55, 0.15);
uniform vec3 suit_color : source_color = vec3(0.86, 0.87, 0.88);
uniform vec3 dark_color : source_color = vec3(0.07, 0.075, 0.085);
uniform vec3 skin_color : source_color = vec3(0.78, 0.6, 0.48);
uniform vec3 pants_color : source_color = vec3(0.16, 0.17, 0.2);
uniform bool hide_head = false; // primera persona: la cámara va dentro de la cabeza

varying vec4 mask;

void vertex() {
	mask = COLOR;
}

void fragment() {
	if (hide_head && mask.b > 0.3) { discard; }
	vec2 t = UV * vec2(900.0, 900.0);
	float weave = 0.5 + 0.5 * sin(t.x) * sin(t.y);
	vec3 c;
	float rough;
	if (outfit == 1) {
		// Polo del puesto (tejido piqué), pantalón oscuro, zapatos negros, manos y cara con piel
		c = role_color * (0.82 + 0.1 * weave);
		rough = 0.85;
		float legs = smoothstep(0.35, 0.6, mask.a);
		c = mix(c, pants_color * (0.9 + 0.1 * weave), legs);
		float feet = smoothstep(0.35, 0.6, mask.r) * legs;
		float hands = smoothstep(0.35, 0.6, mask.r) * (1.0 - legs);
		float head = smoothstep(0.35, 0.6, mask.b);
		c = mix(c, dark_color, feet);
		c = mix(c, skin_color, max(hands, head));
		rough = mix(rough, 0.6, max(hands, head));
	} else {
		c = suit_color * (0.94 + 0.06 * weave);
		rough = 0.78;
		float dark = smoothstep(0.35, 0.6, mask.r + mask.b);
		c = mix(c, dark_color, dark);
		rough = mix(rough, 0.55, dark);
		float role = smoothstep(0.35, 0.55, mask.g) * (1.0 - dark);
		c = mix(c, role_color, role);
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	NORMAL_MAP = vec3(0.5 + 0.04 * (weave - 0.5), 0.5, 1.0);
}
