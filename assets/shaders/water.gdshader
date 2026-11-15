// Agua de las lagunas y del océano Atlántico: dos capas de olas que se mueven en
// direcciones distintas (mapa de normales generado), color profundo con algo de verde
// cerca de la costa, reflejos del cielo (fresnel) y brillo del sol.
shader_type spatial;
render_mode specular_schlick_ggx, depth_draw_always;

uniform sampler2D wave_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 deep : source_color = vec3(0.02, 0.09, 0.13);
uniform vec3 shallow : source_color = vec3(0.07, 0.22, 0.22);
uniform float ocean_z = 820.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wp.xz * 0.035;
	vec3 n1 = texture(wave_nor, uv + TIME * vec2(0.012, 0.007)).rgb;
	vec3 n2 = texture(wave_nor, uv * 2.7 - TIME * vec2(0.009, 0.016)).rgb;
	vec3 n3 = texture(wave_nor, uv * 0.23 + TIME * vec2(0.002, 0.004)).rgb;
	NORMAL_MAP = normalize((n1 + n2 + n3) / 3.0 * 2.0 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.7;
	// Mar abierto más profundo y oscuro; lagunas más verdosas
	float sea = smoothstep(ocean_z - 60.0, ocean_z + 300.0, wp.z);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(shallow, deep, sea) * (1.0 - fres * 0.6);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.7;
}
