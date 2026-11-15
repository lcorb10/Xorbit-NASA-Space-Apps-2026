// Terreno: mezcla pasto, tierra, roca y nieve (texturas CC0 de Poly Haven) según la
// pendiente, la altura y la distancia a la cámara:
// - de cerca, pasto con hojas (leafy_grass) y manchas de tierra con relieve (mapas de normales);
// - de lejos, la foto aérea de pasto y roca, que no se ve repetida;
// - manchas grandes de color (ruido) para que el campo no parezca un patrón;
// - roca en proyección triplanar para que las laderas empinadas no se estiren.
shader_type spatial;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D near_grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D near_grass_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grass_tile = 0.025; // repeticiones por metro (foto aérea)
uniform float near_tile = 0.4; // pasto de cerca: una repetición cada 2,5 m
uniform float rock_tile = 0.012;
uniform float snow_line = 380.0;
uniform float ocean_z = 820.0; // la playa: arena desde aquí hacia +z

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

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

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return s;
}

vec3 triplanar(sampler2D tex, vec3 p, vec3 n, float tile) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 x = texture(tex, p.zy * tile).rgb;
	vec3 y = texture(tex, p.xz * tile).rgb;
	vec3 z = texture(tex, p.xy * tile).rgb;
	return x * w.x + y * w.y + z * w.z;
}

// Muestra sin repetición visible: mezcla dos tomas de la textura giradas y desplazadas
vec3 no_tile(sampler2D tex, vec2 uv, float k) {
	vec3 a = texture(tex, uv).rgb;
	vec2 r = vec2(uv.x * 0.8 - uv.y * 0.6, uv.x * 0.6 + uv.y * 0.8) * 0.77 + 0.37;
	vec3 b = texture(tex, r).rgb;
	return mix(a, b, k);
}

void fragment() {
	vec3 n = normalize(world_nrm);
	float cam_d = length(world_pos - CAMERA_POSITION_WORLD);
	vec2 xz = world_pos.xz;
	float macro = fbm(xz * 0.012);
	float patches = fbm(xz * 0.05 + 7.3);

	// Pasto: de cerca la textura con hojas; de lejos la foto aérea
	float near_w = 1.0 - smoothstep(35.0, 140.0, cam_d);
	vec3 far_grass = texture(grass_tex, xz * grass_tile).rgb;
	vec3 near_grass = no_tile(near_grass_tex, xz * near_tile, smoothstep(0.35, 0.65, patches));
	vec3 grass = mix(far_grass * vec3(0.72, 0.95, 0.55), near_grass * vec3(0.9, 1.0, 0.8), near_w);
	// Manchas de tierra (más en lo llano y cerca de las construcciones)
	float dirt_w = smoothstep(0.58, 0.72, patches) * 0.75;
	vec3 dirt = no_tile(dirt_tex, xz * 0.25, 0.5);
	grass = mix(grass, dirt, dirt_w * near_w + dirt_w * 0.3 * (1.0 - near_w));
	// Variación grande: zonas más secas o más verdes
	grass *= mix(vec3(0.8, 0.95, 0.72), vec3(1.05, 1.05, 0.85), macro);

	vec3 rock = texture(rock_tex, xz * 0.15).rgb; // barro de marisma
	vec3 snow = texture(snow_tex, xz * 0.12).rgb; // arena de playa
	float slope = 1.0 - n.y;
	float rock_w = smoothstep(-0.45, -0.8, world_pos.y + (macro - 0.5) * 0.3); // orillas de lagunas
	vec3 c = mix(grass, rock, clamp(rock_w, 0.0, 1.0));
	float snow_w = smoothstep(ocean_z - 170.0, ocean_z - 90.0, world_pos.z + (macro - 0.5) * 40.0);
	c = mix(c, snow, snow_w);
	// El color por vértice da variación a gran escala sin repetir el patrón
	c *= mix(vec3(1.0), COLOR.rgb * 2.2, 0.12);
	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.6, snow_w);

	// Relieve de cerca: mapas de normales del pasto y la tierra proyectados desde arriba
	float flat_w = near_w * (1.0 - clamp(rock_w, 0.0, 1.0)) * (1.0 - snow_w);
	if (flat_w > 0.01) {
		vec3 gn = texture(near_grass_nor, xz * near_tile).rgb * 2.0 - 1.0;
		vec3 dn = texture(dirt_nor, xz * 0.25).rgb * 2.0 - 1.0;
		vec3 tn = normalize(mix(gn, dn, dirt_w));
		// Espacio tangente aproximado: tangente = +x, bitangente = +z (vale para suelo casi llano)
		vec3 wn = normalize(vec3(tn.x, 0.0, -tn.y) * 0.9 + n * tn.z);
		wn = normalize(mix(n, wn, flat_w));
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	}
}
