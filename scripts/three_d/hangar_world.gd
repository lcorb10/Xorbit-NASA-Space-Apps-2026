class_name HangarWorld
extends RefCounted
## Construye el mundo 3D: hangar con techo en arco, portón abierto, ventanales,
## grúa puente; afuera, explanada, camino, plataforma de lanzamiento, terreno
## montañoso y cielo con sol. Las paredes, el techo y el terreno tienen colisión
## (capa 1) para que la cámara no los atraviese.

const W := 70.0 # ancho interior (x)
const D := 80.0 # largo interior (z)
const WALL_H := 90.0 # nave alta como el VAB: cabe un Saturno V de pie (110 m con la oruga)
const R := W / 2.0 # radio del arco del techo: cumbrera a WALL_H + R
const DOOR_W := 48.0 # la oruga real mide 33 m de ancho
const ROAD_W := 46.0
const DOOR_H := 118.0
const PAD_Z := 230.0 # plataforma de lanzamiento, saliendo por el portón (+z)
const PAD_SURFACE := 3.0 # altura del piso de la plataforma
const DECK_H := 6.8 # altura de la oruga real de la NASA (escala real): el cohete viaja y despega sobre ella
const PAD_TOP := PAD_SURFACE + DECK_H # base del cohete en la plataforma
const RAMP_LEN := 45.0 # rampa por la que sube la oruga
const TEX := "res://assets/textures/polyhaven/"
const NASA := "res://assets/models/nasa/"
const LAYER_WORLD := 1

var root: Node3D
var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
## Modo noche (Game.settings.night): Luna en vez de Sol, focos en la plataforma y faroles encendidos.
var night := false
var amb_day := 0.7 ## luz ambiente a nivel del suelo (el vuelo la baja al subir)
var night_lights: Array[Light3D] = [] ## se encienden solo de noche
var _lamp_mats: Array[StandardMaterial3D] = []
var _mats := {}
var _noise: FastNoiseLite
var _detail: FastNoiseLite
## Sol del cielo HDRI (posición medida en la foto: u = 0,595; 47,8° sobre el horizonte)
const HDRI_SUN_U := 0.5947
const SUN_ELEV := 47.8
const SUN_YAW := -35.0


func build(parent: Node3D) -> Node3D:
	root = Node3D.new()
	root.name = "World"
	parent.add_child(root)
	_environment()
	_hangar()
	_outside()
	_nasa_exhibits()
	_terrain()
	KscScenery.new(self).build(Game.settings.get("quality", "high") == "high")
	Crew.populate(self, Game.settings.get("quality", "high") == "high") # personal de tierra caminando
	if str(Game.settings.get("quality", "high")) == "high":
		_grass()
	_floodlights()
	set_night(bool(Game.settings.get("night", false)))
	return root


## Cambia entre día y noche sin rearmar el mundo.
func set_night(on: bool) -> void:
	night = on
	sky_mat.set_shader_parameter("night", 1.0 if on else 0.0)
	if on:
		# La Luna: luz fría y débil, alta hacia el sur-oeste
		sun.rotation_degrees = Vector3(-38.0, 150.0, 0)
		sun.light_energy = 0.16
		sun.light_color = Color(0.62, 0.72, 1.0)
		sky_mat.set_shader_parameter("moon_dir", sun.transform.basis.z)
		amb_day = 0.2
		env.fog_light_color = Color(0.05, 0.07, 0.12)
		env.glow_intensity = 0.8
		env.glow_bloom = 0.1
		env.tonemap_exposure = 1.15
		env.volumetric_fog_density = 0.0012
	else:
		sun.rotation_degrees = Vector3(-SUN_ELEV, SUN_YAW, 0)
		sun.light_energy = 1.9
		sun.light_color = Color(1.0, 0.96, 0.9)
		amb_day = 0.7
		env.fog_light_color = Color(0.62, 0.72, 0.86)
		env.glow_intensity = 0.45
		env.glow_bloom = 0.04
		env.tonemap_exposure = 1.0
		env.volumetric_fog_density = 0.0004
	env.ambient_light_energy = amb_day
	for l in night_lights:
		l.visible = on
	for m in _lamp_mats:
		m.emission_energy_multiplier = 9.0 if on else 0.3


## Focos: cuatro torres de reflectores alrededor de la plataforma apuntando al cohete
## (como en los lanzamientos nocturnos) y faroles a lo largo del camino de la oruga.
func _floodlights() -> void:
	var head := StandardMaterial3D.new()
	head.albedo_color = Color(1, 0.97, 0.88)
	head.emission_enabled = true
	head.emission = Color(1.0, 0.92, 0.75)
	_lamp_mats.append(head)
	var steel := pbr("pole", "metal_plate", 1.0, Color(0.5, 0.52, 0.55))
	for k in 4:
		var a := PI / 4.0 + k * PI / 2.0
		var base := Vector3(cos(a) * 62.0, 0.0, PAD_Z + sin(a) * 62.0)
		_box(Vector3(0.8, 26.0, 0.8), base + Vector3(0, 13.0, 0), steel)
		_box(Vector3(5.0, 2.5, 1.0), base + Vector3(0, 27.0, 0), head)
		var spot := SpotLight3D.new()
		spot.position = base + Vector3(0, 27.0, 0)
		spot.light_color = Color(1.0, 0.9, 0.75)
		spot.light_energy = 22.0
		spot.spot_range = 160.0
		spot.spot_angle = 22.0
		spot.spot_attenuation = 0.6
		spot.shadow_enabled = k < 2
		spot.light_volumetric_fog_energy = 0.6
		root.add_child(spot)
		spot.look_at(Vector3(0, 45.0, PAD_Z), Vector3.UP)
		night_lights.append(spot)
	# Faroles del camino de la oruga (los postes los pone KscScenery cada 40 m)
	var z := D / 2.0 + 60.0
	var n := 0
	while z < PAD_Z - 35.0 - RAMP_LEN and n < 8:
		for sx in [-1.0, 1.0]:
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(sx * (ROAD_W / 2.0 + 2.4), 11.4, z)
			lamp.light_color = Color(1.0, 0.78, 0.5)
			lamp.light_energy = 6.0
			lamp.omni_range = 26.0
			lamp.shadow_enabled = false
			root.add_child(lamp)
			night_lights.append(lamp)
			_box(Vector3(1.4, 0.25, 0.5), lamp.position + Vector3(0, 0.45, 0), head)
		z += 40.0
		n += 1


## Altura del techo interior a una distancia x del centro.
static func ceiling_at(x: float) -> float:
	var ax := clampf(absf(x), 0.0, R)
	return WALL_H + sqrt(R * R - ax * ax)


static func pad_position() -> Vector3:
	return Vector3(0, 0, PAD_Z)


# ---------- Cielo y luz ----------

func _environment() -> void:
	# Cielo: foto HDR de un cielo real (Poly Haven, CC0) que pasa a espacio con estrellas al subir
	var sun_basis := Basis.from_euler(Vector3(deg_to_rad(-SUN_ELEV), deg_to_rad(SUN_YAW), 0.0))
	var to_sun := sun_basis.z
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://assets/shaders/sky.gdshader")
	sky_mat.set_shader_parameter("pano", load("res://assets/textures/sky/kloofendal_puresky_2k.hdr"))
	sky_mat.set_shader_parameter("pano_energy", 0.85)
	# Girar la foto para que su sol quede donde está la luz del sol de la escena
	sky_mat.set_shader_parameter("pano_offset", HDRI_SUN_U - 0.5 - atan2(to_sun.x, -to_sun.z) / TAU)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 1.5
	env.ssil_enabled = true
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.04
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.72, 0.86)
	env.fog_density = 0.00007
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.15
	env.volumetric_fog_enabled = true
	if str(Game.settings.get("quality", "high")) != "high":
		env.volumetric_fog_enabled = false
		env.ssil_enabled = false
		env.ssr_enabled = false
	env.volumetric_fog_density = 0.0004
	env.volumetric_fog_albedo = Color(0.9, 0.92, 0.95)
	env.volumetric_fog_length = 120.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-SUN_ELEV, SUN_YAW, 0) # entra por el portón y los ventanales
	sun.light_energy = 1.9
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.light_angular_distance = 0.5 # sombras con borde suave, como las del sol real
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 450.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.light_volumetric_fog_energy = 1.5
	root.add_child(sun)

	var probe := ReflectionProbe.new()
	probe.size = Vector3(W, ceiling_at(0.0), D)
	probe.position = Vector3(0, ceiling_at(0.0) / 2.0, 0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.box_projection = true
	probe.interior = false
	root.add_child(probe)


# ---------- Hangar ----------

func _hangar() -> void:
	var concrete := pbr("floor", "brushed_concrete", 4.0, Color(1, 1, 1))
	var panel := pbr("panel", "corrugated_iron_02", 3.0, Color(0.85, 0.88, 0.9))
	var steel := pbr("steel", "metal_plate", 2.0, Color(0.55, 0.58, 0.62))
	var yellow := pbr("yellow", "metal_plate", 1.5, Color(1.2, 0.9, 0.15))
	var white := pbr("white_line", "concrete", 1.0, Color(1.3, 1.3, 1.25))
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.6, 0.75, 0.85, 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.3

	# Piso
	_box(Vector3(W, 0.4, D), Vector3(0, -0.2, 0), concrete, true)
	# Losas del piso (juntas)
	for i in range(-3, 4):
		_box(Vector3(0.08, 0.01, D), Vector3(i * 10.0, 0.005, 0), steel)
	for j in range(-4, 5):
		_box(Vector3(W, 0.01, 0.08), Vector3(0, 0.005, j * 10.0), steel)

	# Paredes laterales: zócalo, banda de ventanales con montantes y parte alta
	for sx in [-1.0, 1.0]:
		var x: float = sx * (W / 2.0 + 0.3)
		_box(Vector3(0.6, 14.0, D + 0.6), Vector3(x, 7.0, 0), panel, true)
		# Parte alta hasta el arranque del arco, con una segunda banda de ventanales arriba
		_box(Vector3(0.6, WALL_H - 34.0, D + 0.6), Vector3(x, (20.0 + WALL_H - 14.0) / 2.0, 0), panel, true)
		_box(Vector3(0.6, 6.0, D + 0.6), Vector3(x, WALL_H - 3.0, 0), panel, true)
		for wy in [17.0, WALL_H - 10.0]:
			_box(Vector3(0.1, 6.0 if wy < 20.0 else 8.0, D), Vector3(x, wy, 0), glass, true)
			for k in range(-4, 5):
				_box(Vector3(0.7, 6.0 if wy < 20.0 else 8.0, 0.5), Vector3(x, wy, k * 10.0), steel)
		# Pasarelas de servicio cada 18 m, con barandas (como las plataformas del VAB)
		for py in [24.0, 42.0, 60.0, 78.0]:
			_box(Vector3(4.0, 0.4, D - 2.0), Vector3(x - sx * 2.3, py, 0), steel, true)
			_box(Vector3(0.08, 1.1, D - 2.0), Vector3(x - sx * 4.2, py + 0.75, 0), yellow)
			for k in range(-7, 8):
				_box(Vector3(0.08, 1.1, 0.08), Vector3(x - sx * 4.2, py + 0.75, k * 5.0), yellow)
		# Nervaduras de chapa ondulada en la parte baja
		for k in 40:
			_box(Vector3(0.15, 14.0, 0.25), Vector3(x - sx * 0.35, 7.0, -D / 2.0 + 1.0 + k * 2.0), panel)

	# Techo en arco (facetado) con colisión, y arcos estructurales cada 10 m
	var seg := 28
	for i in seg:
		var a0 := PI * i / seg
		var a1 := PI * (i + 1) / seg
		var p0 := Vector2(cos(a0) * R, WALL_H + sin(a0) * R)
		var p1 := Vector2(cos(a1) * R, WALL_H + sin(a1) * R)
		var mid := (p0 + p1) / 2.0
		var len := p0.distance_to(p1)
		var ang := atan2(p1.y - p0.y, p1.x - p0.x)
		var roof := _box(Vector3(len + 0.15, 0.5, D + 1.2), Vector3(mid.x, mid.y + 0.25, 0), panel, true)
		roof.rotation.z = ang
		for k in range(-4, 5):
			var rib := _box(Vector3(len + 0.1, 0.9, 0.6), Vector3(mid.x * 0.985, mid.y * 0.985, k * 10.0), steel)
			rib.rotation.z = ang
		# Lucernario en la cumbrera
		if i in [13, 14]:
			roof.material_override = glass
	# Columnas bajo cada arco
	for k in range(-4, 5):
		for sx in [-1.0, 1.0]:
			_box(Vector3(0.9, WALL_H, 0.9), Vector3(sx * (W / 2.0 - 0.6), WALL_H / 2.0, k * 10.0), steel)

	# Muros frontal y trasero (hastiales), el frontal con el portón abierto
	for side in [-1.0, 1.0]:
		var z: float = side * (D / 2.0 + 0.3)
		var x := -R + 1.25
		while x < R:
			var top := ceiling_at(x) + 0.5
			if side > 0.0 and absf(x) < DOOR_W / 2.0:
				if top > DOOR_H:
					_box(Vector3(2.5, top - DOOR_H, 0.6), Vector3(x, (top + DOOR_H) / 2.0, z), panel, true)
			else:
				_box(Vector3(2.5, top, 0.6), Vector3(x, top / 2.0, z), panel, true)
			x += 2.5
	# Dintel y marco del portón
	_box(Vector3(DOOR_W + 2.0, 2.0, 1.2), Vector3(0, DOOR_H + 1.0, D / 2.0 + 0.3), steel, true)
	for sx in [-1.0, 1.0]:
		_box(Vector3(1.2, DOOR_H, 1.2), Vector3(sx * (DOOR_W / 2.0 + 0.6), DOOR_H / 2.0, D / 2.0 + 0.3), steel, true)
	# Hojas del portón corridas hacia los lados (por fuera)
	for sx in [-1.0, 1.0]:
		for k in 2:
			_box(Vector3(DOOR_W / 4.0, DOOR_H - 1.0, 0.5), Vector3(sx * (DOOR_W / 2.0 + DOOR_W / 8.0 + k * 0.2 + 1.5), (DOOR_H - 1.0) / 2.0, D / 2.0 + 1.2 + k * 0.7), panel, true)
	# Franjas de advertencia en el umbral
	for i in 10:
		var stripe := _box(Vector3(2.0, 0.02, 1.4), Vector3(-DOOR_W / 2.0 + 2.0 + i * 4.0, 0.02, D / 2.0 - 1.0), yellow)
		stripe.rotation.y = deg_to_rad(35)

	# Grúa puente
	for sx in [-1.0, 1.0]:
		_box(Vector3(1.0, 1.4, D - 2.0), Vector3(sx * (W / 2.0 - 2.0), WALL_H - 1.5, 0), yellow)
	_box(Vector3(W - 4.0, 1.8, 1.6), Vector3(0, WALL_H - 0.6, -8.0), yellow)
	_box(Vector3(3.0, 1.6, 3.0), Vector3(-6.0, WALL_H - 2.2, -8.0), steel)
	_box(Vector3(0.12, 10.0, 0.12), Vector3(-6.0, WALL_H - 8.0, -8.0), steel)

	# Marcas del piso: círculo del soporte, pasillos y rumbo al portón
	_box(Vector3(10, 0.03, 10), Vector3(0, 0.015, 0), yellow)
	_box(Vector3(9.2, 0.04, 9.2), Vector3(0, 0.02, 0), concrete)
	for x in [-14.0, 14.0]:
		_box(Vector3(0.3, 0.03, D - 4.0), Vector3(x, 0.015, 0), yellow)
	for i in 8:
		_box(Vector3(0.5, 0.03, 3.0), Vector3(0, 0.015, 8.0 + i * 4.0), white)

	# Utilería: mesa de trabajo (para el plano), cajas, tanques de gas, banco de herramientas
	var wood := pbr("wood", "forest_ground_04", 1.2, Color(0.9, 0.62, 0.4)) # veta de madera aproximada
	_box(Vector3(4.0, 0.12, 2.2), Vector3(-20.0, 1.0, -22.0), wood, true)
	for dx in [-1.8, 1.8]:
		for dz in [-0.9, 0.9]:
			_box(Vector3(0.12, 1.0, 0.12), Vector3(-20.0 + dx, 0.5, -22.0 + dz), steel)
	var crate := pbr("crate", "corrugated_iron_02", 1.1, Color(0.5, 0.6, 0.42))
	for c in [Vector3(24, 1, -30), Vector3(26.5, 1, -30), Vector3(25, 3, -30), Vector3(-28, 1, 18)]:
		_box(Vector3(2.2, 2.0, 2.2), c, crate, true)
	var red := pbr("red", "metal_plate", 1.0, Color(1.1, 0.18, 0.14))
	for k in 4:
		var tank := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.3
		cyl.bottom_radius = 0.3
		cyl.height = 1.7
		tank.mesh = cyl
		tank.material_override = red if k % 2 == 0 else steel
		tank.position = Vector3(30.0, 0.85, 10.0 + k * 0.8)
		root.add_child(tank)

	_apollo_exhibit()

	# Lámparas colgantes
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1, 0.97, 0.9)
	lamp.emission_enabled = true
	lamp.emission = Color(1, 0.95, 0.85)
	lamp.emission_energy_multiplier = 5.0
	for i in 3:
		for j in 3:
			var pos := Vector3(-20.0 + i * 20.0, WALL_H + 6.0, -25.0 + j * 25.0)
			_box(Vector3(2.0, 0.3, 2.0), pos, lamp)
			var l := SpotLight3D.new()
			l.position = pos - Vector3(0, 0.4, 0)
			l.rotation_degrees = Vector3(-90, 0, 0)
			l.spot_range = 60.0
			l.spot_angle = 50.0
			l.light_energy = 7.0
			l.light_color = Color(1, 0.95, 0.88)
			l.shadow_enabled = (i == 1 and j == 1)
			root.add_child(l)


# ---------- Afuera ----------

func _outside() -> void:
	var asphalt := pbr("crawlerway", "ganges_river_pebbles", 2.0, Color(1.05, 1.02, 0.98))
	var concrete := pbr("pad", "concrete", 4.0, Color(1, 1, 1))
	var yellow := pbr("yellow", "metal_plate", 1.5, Color(1.2, 0.9, 0.15))
	var steel := pbr("steel", "metal_plate", 2.0, Color(0.55, 0.58, 0.62))
	var orange := pbr("tower_orange", "metal_plate", 2.0, Color(0.95, 0.45, 0.2))
	# Explanada frente al portón y camino de oruga hasta la plataforma
	_box(Vector3(90, 0.3, 50), Vector3(0, -0.15, D / 2.0 + 25.0), concrete, true)
	var pad_edge := PAD_Z - 35.0
	var road_end := pad_edge - RAMP_LEN
	_box(Vector3(ROAD_W, 0.3, road_end - D / 2.0 - 50.0), Vector3(0, -0.14, (D / 2.0 + 50.0 + road_end) / 2.0), asphalt, true)
	# Rampa: sube de 0 a PAD_SURFACE a lo largo de RAMP_LEN
	var ang := atan2(PAD_SURFACE, RAMP_LEN)
	var rl := sqrt(RAMP_LEN * RAMP_LEN + PAD_SURFACE * PAD_SURFACE)
	var ramp := _box(Vector3(ROAD_W, 1.0, rl), Vector3(0, PAD_SURFACE / 2.0 - 0.5 * cos(ang), road_end + RAMP_LEN / 2.0 + 0.5 * sin(ang)), concrete, true)
	ramp.rotation.x = -ang
	for k in 30:
		var lz := D / 2.0 + 55.0 + k * 8.0
		if lz < PAD_Z - 35.0 - RAMP_LEN - 2.0:
			_box(Vector3(0.4, 0.02, 4.0), Vector3(0, 0.02, lz), yellow)
	# Plataforma de lanzamiento
	_box(Vector3(70, 3.0, 70), Vector3(0, 1.5, PAD_Z), concrete, true)
	_box(Vector3(14, 3.2, 40), Vector3(0, 1.5, PAD_Z + 25.0), asphalt) # foso de llamas
	# La torre de servicio, los pararrayos y la torre de agua están en KscScenery
	# Tanques esféricos de propelente junto a la plataforma
	# Tanques esféricos de oxígeno e hidrógeno líquidos, sobre patas (como en la plataforma 39)
	var white := RocketBuilder._mat("paint_white")
	for k in 2:
		var c := Vector3(70.0 + k * 22.0, 11.0, PAD_Z - 20.0)
		var s := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 8.0
		sph.height = 16.0
		s.mesh = sph
		s.material_override = white
		s.position = c
		root.add_child(s)
		for leg in 6:
			var leg_ang := TAU * leg / 6.0
			_box(Vector3(0.6, 9.0, 0.6), Vector3(c.x + cos(leg_ang) * 6.5, 4.5, c.z + sin(leg_ang) * 6.5), steel)
		_plaque(Vector3(c.x, 21.5, c.z), "PAD_TANK_LOX" if k == 0 else "PAD_TANK_LH2")


# ---------- Modelos de la NASA (escala real) ----------

## Jardín de cohetes junto al hangar (como el del Centro Espacial Kennedy) y el VAB al fondo.
## Naves del programa Apolo en la explanada frente al portón, a tamaño real: el Módulo Lunar
## (modelo NASA), la nave de mando y servicio (CSM) parada sobre su motor y el Apolo-Soyuz de 1975.
func _apollo_exhibit() -> void:
	var concrete := pbr("concrete_exhibit", "concrete", 4.0, Color(1.1, 1.1, 1.08))
	var spots := [[Vector3(-37, 0, 56), "EX_LM"], [Vector3(-37, 0, 72), "EX_CSM"], [Vector3(-37, 0, 88), "EX_ASTP"]]
	for s in spots:
		_box(Vector3(12, 0.4, 12), (s[0] as Vector3) + Vector3(0, 0.1, 0), concrete, true)
		var sign := Label3D.new()
		sign.text = tr(str(s[1]))
		sign.font_size = 64
		sign.pixel_size = 0.01
		sign.outline_size = 12
		sign.modulate = Color(1, 1, 1, 0.95)
		sign.position = (s[0] as Vector3) + Vector3(6.3, 1.2, 0)
		sign.rotation.y = PI / 2.0
		root.add_child(sign)
	if ResourceLoader.exists(Spacecraft.DIR + "apollo_lm.glb"):
		var lm := Spacecraft.lunar_module()
		lm.position = spots[0][0] + Vector3(0, 0.3, 0)
		lm.rotation.y = 0.6
		root.add_child(lm)
	var csm := Spacecraft.csm()
	csm.position = spots[1][0] + Vector3(0, 0.3 + 3.9 + 7.5, 0)
	csm.rotation.y = -0.4
	root.add_child(csm)
	if ResourceLoader.exists(Spacecraft.DIR + "apollo_soyuz.glb"):
		var astp := Spacecraft.model("apollo_soyuz", 20.0)
		astp.position = spots[2][0] + Vector3(0, 5.5, 0)
		astp.rotation.y = PI / 2.0
		root.add_child(astp)


func _nasa_exhibits() -> void:
	var concrete := pbr("pad", "concrete", 4.0, Color(1, 1, 1))
	# Saturno V acostado sobre soportes, 110,6 m
	_box(Vector3(16, 0.3, 120), Vector3(78, 0.0, 25), concrete, true)
	for k in 5:
		_box(Vector3(6, 4.0, 2.5), Vector3(78, 2.0, -25.0 + k * 25.0), concrete, true)
	# Las superficies que vienen sin textura (color liso) se visten con chapa o concreto reales
	ModelPlace.dress(ModelPlace.place(root, NASA + "saturn_v.glb", 8.514, Vector3(90, 0, 0), Vector3(78, 4.0, 25)), "metal", 3.0)
	_plaque(Vector3(66, 1.6, -36), "NASA_SATURN_V")
	# Transbordador espacial de pie, 56 m
	_box(Vector3(34, 0.3, 26), Vector3(66, 0.0, -62), concrete, true)
	# En el archivo la nariz apunta a -z: girar +90° en x la deja hacia arriba
	var shuttle := ModelPlace.place(root, NASA + "space_shuttle.glb", 1.34, Vector3(90, 0, 0), Vector3(66, 0.15, -62))
	_paint_shuttle(shuttle)
	_plaque(Vector3(46, 1.6, -50), "NASA_SHUTTLE")
	# Jupiter-C, el cohete del primer satélite de EE. UU. (Explorer 1, 1958), 21,2 m
	_box(Vector3(8, 0.3, 8), Vector3(44, 0.0, 70), concrete, true)
	ModelPlace.dress(ModelPlace.place(root, NASA + "jupiter_c.glb", 1.21, Vector3.ZERO, Vector3(44, 0.15, 70)), "metal", 1.5)
	_plaque(Vector3(44, 1.6, 64), "NASA_JUPITER_C")
	# Edificio de ensamblaje de vehículos (VAB), 160 m, al fondo
	var vab := ModelPlace.place(root, NASA + "vab.glb", 11.7, Vector3(0, 90, 0), Vector3(-170, -0.4, -170))
	var dressed := ModelPlace.dress(vab, "concrete", 12.0, true) # su textura es blanca lisa: concreto en todo
	if "--smoke" in OS.get_cmdline_user_args():
		print("SMOKE vab: %d superficies vestidas" % dressed)


## El modelo de la NASA viene todo gris: se pinta cada parte como el real.
func _paint_shuttle(node: Node3D) -> void:
	if node == null:
		return
	var tank := ["shuttlesrbsande6"]
	var dark := ["lambert19SG", "lambert2SG", "lambert20SG", "blinn1SG", "shuttlesrbsande5"]
	var metal := ["blinn4SG", "blinn6SG", "boosters_initial", "lambert9SG"]
	var counts := {}
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			var name := mat.resource_name if mat else ""
			var id := "paint_white"
			if name in tank:
				id = "foam_orange"
			elif name in dark:
				id = "paint_black_tiles"
			elif name in metal:
				id = "metal_dark"
			(mi as MeshInstance3D).set_surface_override_material(s, RocketBuilder._mat(id))
			counts[id] = int(counts.get(id, 0)) + 1

	if "--smoke" in OS.get_cmdline_user_args():
		print("SMOKE transbordador pintado: ", counts)

func _plaque(pos: Vector3, key: String) -> void:
	var l := Label3D.new()
	l.text = key
	l.font = Game.font_display
	l.font_size = 64
	l.pixel_size = 0.012
	l.outline_size = 12
	l.modulate = Color(1, 1, 1)
	l.outline_modulate = Color(0, 0, 0, 0.7)
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.position = pos
	l.width = 900
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(l)


# ---------- Terreno ----------

func _terrain() -> void:
	var size := 3000.0
	var n := 150
	_noise = FastNoiseLite.new()
	_noise.seed = 7
	_noise.frequency = 0.0016
	_noise.fractal_octaves = 5
	_detail = FastNoiseLite.new()
	_detail.seed = 11
	_detail.frequency = 0.01
	var noise := _noise
	var detail := _detail
	var heights := PackedFloat32Array()
	heights.resize((n + 1) * (n + 1))
	var step := size / n
	for j in n + 1:
		for i in n + 1:
			var x := -size / 2.0 + i * step
			var z := -size / 2.0 + j * step
			heights[j * (n + 1) + i] = _height(x, z, noise, detail)
	# Malla con color por altura y pendiente: pasto, roca, nieve
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hat := func(i: int, j: int) -> float:
		return heights[clampi(j, 0, n) * (n + 1) + clampi(i, 0, n)]
	# Normales suaves por vértice (diferencias centrales): laderas redondeadas, sin facetas
	var nrms := PackedVector3Array()
	nrms.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			nrms[j * (n + 1) + i] = Vector3(hat.call(i - 1, j) - hat.call(i + 1, j), 2.0 * step, hat.call(i, j - 1) - hat.call(i, j + 1)).normalized()
	for j in n:
		for i in n:
			for q in [[i, j], [i + 1, j], [i, j + 1], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var k: int = q[1] * (n + 1) + q[0]
				var v := Vector3(-size / 2.0 + q[0] * step, heights[k], -size / 2.0 + q[1] * step)
				st.set_color(_ground_color(v.y, nrms[k].y))
				st.set_normal(nrms[k])
				st.add_vertex(v)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/terrain.gdshader")
	mat.set_shader_parameter("grass_tex", load(TEX + "aerial_grass_rock_diff.jpg"))
	mat.set_shader_parameter("rock_tex", load(TEX + "brown_mud_02_diff.jpg"))
	mat.set_shader_parameter("snow_tex", load(TEX + "coast_sand_01_diff.jpg"))
	mat.set_shader_parameter("near_grass_tex", load(TEX + "leafy_grass_diff.jpg"))
	mat.set_shader_parameter("near_grass_nor", load(TEX + "leafy_grass_nor.jpg"))
	mat.set_shader_parameter("dirt_tex", load(TEX + "forest_ground_04_diff.jpg"))
	mat.set_shader_parameter("dirt_nor", load(TEX + "forest_ground_04_nor.jpg"))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	root.add_child(mi)
	# Colisión del terreno
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	var shape := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = n + 1
	hm.map_depth = n + 1
	hm.map_data = heights
	shape.shape = hm
	shape.scale = Vector3(step, 1.0, step)
	body.add_child(shape)
	root.add_child(body)


## Pasto de verdad cerca del hangar y de la plataforma: matas de hojas que se mecen con
## el viento. Se reparte en bloques que solo se dibujan de cerca (rinde bien).
func _grass() -> void:
	var clump := _grass_clump()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/grass.gdshader")
	clump.surface_set_material(0, mat)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var chunk := 40.0
	var per_chunk := 2000
	# Zonas sin pasto: hangar y explanada, camino, plataforma, tanques, exhibición, VAB
	var no_grass := [
		Rect2(-W / 2.0 - 6.0, -D / 2.0 - 6.0, W + 12.0, D + 6.0 + 50.0 + 6.0),
		Rect2(-ROAD_W / 2.0 - 3.0, D / 2.0, ROAD_W + 6.0, PAD_Z - D / 2.0),
		Rect2(-38.0, PAD_Z - 38.0, 76.0, 76.0), Rect2(-9.0, PAD_Z, 18.0, 50.0),
		Rect2(58.0, PAD_Z - 32.0, 46.0, 24.0), Rect2(66.0, -38.0, 26.0, 126.0),
		Rect2(48.0, -76.0, 36.0, 30.0), Rect2(39.0, 65.0, 10.0, 10.0), Rect2(-260.0, -290.0, 190.0, 240.0)]
	for cz in range(-6, 12):
		for cx in range(-8, 8):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = clump
			var xfs: Array[Transform3D] = []
			var tints: Array[Color] = []
			for k in per_chunk:
				var x := (cx + rng.randf()) * chunk
				var z := (cz + rng.randf()) * chunk
				var skip := false
				for r: Rect2 in no_grass:
					if r.has_point(Vector2(x, z)):
						skip = true
						break
				if skip:
					continue
				var y := _height(x, z, _noise, _detail)
				if y < -0.6:
					continue # laguna o mar
				var s := rng.randf_range(0.7, 1.4)
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
				xfs.append(Transform3D(b, Vector3(x, y - 0.05, z)))
				# Variación de color: pasto más seco o más verde por manchas
				var dry := clampf(_detail.get_noise_2d(x * 3.0, z * 3.0) * 0.8 + 0.5, 0.0, 1.0)
				tints.append(Color(dry, rng.randf(), 0.0, 0.0))
			if xfs.is_empty():
				continue
			mm.instance_count = xfs.size()
			for i in xfs.size():
				mm.set_instance_transform(i, xfs[i])
				mm.set_instance_custom_data(i, tints[i])
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 110.0
			mi.visibility_range_end_margin = 25.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			root.add_child(mi)


## Una mata de pasto: 5 hojas finas y curvas. El color del vértice guarda la altura (0 abajo, 1 punta).
func _grass_clump() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for b in 5:
		var ang := rng.randf() * TAU
		var off := Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(0.0, 0.25)
		var face := rng.randf() * TAU
		var side := Vector3(cos(face), 0, sin(face))
		var lean := Vector3(-sin(face), 0, cos(face)) * rng.randf_range(0.05, 0.25)
		var hgt := rng.randf_range(0.35, 0.75)
		var w := rng.randf_range(0.025, 0.045)
		var segs := 3
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for s in segs + 1:
			var k := float(s) / segs
			var c := off + Vector3(0, hgt * k, 0) + lean * k * k * hgt * 2.0
			var half := w * (1.0 - k * 0.92)
			var l := c - side * half
			var r := c + side * half
			if s > 0:
				var k0 := float(s - 1) / segs
				for v in [[prev_l, k0], [prev_r, k0], [r, k], [prev_l, k0], [r, k], [l, k]]:
					st.set_color(Color(v[1], 0, 0))
					st.set_normal(Vector3.UP)
					st.add_vertex(v[0])
			prev_l = l
			prev_r = r
	return st.commit()


## Altura del suelo en (x, z), para colocar cosas encima.
func ground_height(x: float, z: float) -> float:
	return _height(x, z, _noise, _detail)


func _height(x: float, z: float, noise: FastNoiseLite, detail: FastNoiseLite) -> float:
	return _florida_height(x, z, noise, detail)


## Isla Merritt (Florida): llano de marisma a 1 m sobre el mar, lagunas y la playa del Atlántico al este.
func _florida_height(x: float, z: float, noise: FastNoiseLite, detail: FastNoiseLite) -> float:
	var near_line := Vector2(x, clampf(z, -60.0, PAD_Z + 60.0)).distance_to(Vector2(0, clampf(z, -60.0, PAD_Z + 60.0)))
	var d := Vector2(x, z - PAD_Z * 0.4).length()
	var flat := smoothstep(140.0, 420.0, minf(near_line + 40.0, d))
	var undul := detail.get_noise_2d(x, z) * 1.1 * flat
	var lag := noise.get_noise_2d(x * 0.7, z * 0.7)
	var lagoon := smoothstep(-0.08, -0.28, lag) * flat
	var h := -0.4 + undul * (1.0 - lagoon) - lagoon * 2.4
	# Duna baja antes de la playa y luego el fondo del mar
	var dune := exp(-pow((z - (KscScenery.OCEAN_Z - 110.0)) / 30.0, 2.0)) * 2.5
	var beach := smoothstep(KscScenery.OCEAN_Z - 80.0, KscScenery.OCEAN_Z + 60.0, z)
	return lerpf(h + dune, -5.0, beach)


func _mountain_height(x: float, z: float, noise: FastNoiseLite, detail: FastNoiseLite) -> float:
	# Llano alrededor del hangar y la plataforma; montañas a lo lejos
	var near_line := Vector2(x, clampf(z, -60.0, PAD_Z + 60.0)).distance_to(Vector2(0, clampf(z, -60.0, PAD_Z + 60.0)))
	var d := Vector2(x, z - PAD_Z * 0.4).length()
	var flat := smoothstep(140.0, 420.0, minf(near_line + 40.0, d))
	var ridge := 1.0 - absf(noise.get_noise_2d(x, z))
	var mountains := (ridge * ridge * 0.8 + 0.2) * 560.0 * smoothstep(550.0, 1350.0, d)
	var hills := (detail.get_noise_2d(x, z) * 0.5 + 0.5) * 18.0 * flat
	return -0.4 + mountains + hills


func _ground_color(h: float, up: float) -> Color:
	var grass := Color(0.24, 0.32, 0.15)
	var dry := Color(0.45, 0.42, 0.28)
	var rock := Color(0.42, 0.4, 0.38)
	var snow := Color(0.92, 0.93, 0.95)
	var c := grass.lerp(dry, clampf(h / 60.0, 0.0, 1.0))
	c = c.lerp(rock, clampf((1.0 - up) * 2.5 + (h - 160.0) / 260.0, 0.0, 1.0))
	if h > 380.0 and up > 0.55:
		c = c.lerp(snow, clampf((h - 380.0) / 80.0, 0.0, 1.0))
	return c


# ---------- Ayudantes ----------

## Material con texturas de Poly Haven: color, normales y ARM (oclusión, rugosidad, metal),
## proyectadas por posición en el mundo (tile_m = metros que ocupa una repetición).
func pbr(id: String, tex: String, tile_m: float, tint: Color) -> ORMMaterial3D:
	if _mats.has(id):
		return _mats[id]
	var m := ORMMaterial3D.new()
	m.albedo_texture = load(TEX + tex + "_diff.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(TEX + tex + "_nor.jpg")
	m.orm_texture = load(TEX + tex + "_arm.jpg")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile_m
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[id] = m
	return m


func _mat(id: String, color: Color, rough: float, metal: float) -> StandardMaterial3D:
	if _mats.has(id):
		return _mats[id]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	_mats[id] = m
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, solid := false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	root.add_child(m)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = LAYER_WORLD
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
		m.add_child(body)
	return m
