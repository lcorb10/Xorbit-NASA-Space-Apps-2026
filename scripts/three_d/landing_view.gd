class_name LandingView
extends SubViewportContainer
## Escena de aterrizaje en 3D (misiones 4 y 6), con la superficie del destino como el hangar en la Tierra.
## Luna: el Módulo Lunar baja con su motor de descenso, frena la velocidad de lado, levanta polvo y
## toca el suelo sobre sus patas; la Tierra se ve en el cielo negro.
## Marte: la cápsula entra con el escudo térmico al rojo, abre el paracaídas, suelta la coraza y la
## grúa aérea baja el rover con cables.
## Si falta equipo (patas, escudo, paracaídas) o combustible, se ve qué pasa. Houston explica cada paso.

signal finished(success: bool)
signal say(key: String)

const TEX := "res://assets/textures/planets/"

var body := "moon" ## "moon" o "mars"
var walk_enabled := false ## misión tripulada en la Luna: el comandante baja y clava la bandera
var _walking := false
var _walk_t := 0.0
var _walker := Vector3(0, 0, 5.5) ## posición del comandante (pies): al pie de la escalera, fuera del módulo
var _yaw := 0.0
var _pitch := -0.15
var _hop := 0.0
var _last_hop := 0.0
var _flag_spot := Vector3(0, 0, 15.0)
var _flag: Node3D
var _planting := -1.0
var _marker: MeshInstance3D
var _prompt: Label
var _astro: Astronaut
var _idle_t := 0.0 ## segundos sin tocar los controles en la caminata
var _cam_off := Vector3.ZERO ## cámara de seguimiento: distancia suavizada a la nave
var _body: Astronaut ## cuerpo del comandante en primera persona (sin cabeza: se ven brazos, pecho y piernas)
var _body_anim := ""
var _eye_h := 0.0
var _vy := 0.0 ## velocidad vertical: gravedad lunar real (1,62 m/s²)
var _air := 0.0 ## altura sobre el suelo
const MOON_G := 1.62
var gear_missing: Array = []
var fuel_ok := true ## alcanzó el Δv del aterrizaje

var _root: Node3D
var _cam: Camera3D
var _craft: Node3D
var _plume: MeshInstance3D
var _dust: GPUParticles3D
var _hud: Label
var _phase: Label
var _t := 0.0
var _done := false
var _said := {}
var _crashed := false
var _chute: Node3D
var _shell: Node3D
var _rover: Node3D
var _crane: Node3D
var _glow: MeshInstance3D


func _ready() -> void:
	Sound.flight_music = "landing" # descenso con tensión; al caminar cambia a "moon"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stretch = true
	var vp := SubViewport.new()
	_vp = vp
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	_root = Node3D.new()
	vp.add_child(_root)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 4000000.0
	_cam.near = 0.3
	_root.add_child(_cam)
	if body == "mars":
		_build_mars()
	else:
		_build_moon()
	_build_hud()


# ---------- Escenarios ----------

func _terrain(size: float, n: int, height: Callable, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := size / n
	# Alturas de la cuadrícula (una vez por punto). El borde baja hasta la esfera del planeta para
	# que el terreno detallado se funda con ella, y todo se curva con el radio real.
	var hs := PackedFloat32Array()
	hs.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var x := -size / 2.0 + i * step
			var z := -size / 2.0 + j * step
			var edge := clampf((maxf(absf(x), absf(z)) - size * 0.4) / (size * 0.1), 0.0, 1.0)
			hs[j * (n + 1) + i] = lerpf(float(height.call(x, z)), -3.0, edge) - (x * x + z * z) / (2.0 * _radius)
	for j in n:
		for i in n:
			var x0 := -size / 2.0 + i * step
			var z0 := -size / 2.0 + j * step
			var q := [Vector2(x0, z0), Vector2(x0 + step, z0), Vector2(x0 + step, z0 + step), Vector2(x0, z0 + step)]
			var hq := [hs[j * (n + 1) + i], hs[j * (n + 1) + i + 1], hs[(j + 1) * (n + 1) + i + 1], hs[(j + 1) * (n + 1) + i]]
			for idx in [0, 1, 2, 0, 2, 3]:
				var p: Vector2 = q[idx]
				st.set_uv(Vector2(0.5, 0.5) + p / PLANET_UV)
				st.set_uv2(p / 6.0)
				st.add_vertex(Vector3(p.x, float(hq[idx]), p.y))
	st.generate_normals()
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	m.material_override = mat
	_root.add_child(m)


## Altura de la Luna: llanura con ondulaciones y cráteres de borde levantado (el lugar de aterrizaje, en el
## centro, es plano: por eso se elige con cuidado).
func _moon_h(x: float, z: float) -> float:
	var h := _noise.get_noise_2d(x, z) * 8.0 + _noise.get_noise_2d(x * 7.0, z * 7.0) * 0.8
	var p := Vector2(x, z)
	for c in _craters:
		var rr: float = c[1]
		var dd := p.distance_squared_to(c[0])
		if dd > rr * rr * 6.0:
			continue
		var d := sqrt(dd) / rr
		var depth: float = c[2]
		if d < 1.0:
			h += depth * (d * d - 1.0) # cuenco
		h += depth * 0.45 * exp(-pow((d - 1.0) / 0.22, 2.0)) # borde levantado
		if d > 1.0:
			h += depth * 0.12 / pow(d, 3.0) # manto de eyección
	var flat := clampf(p.length() / 140.0, 0.0, 1.0) # el lugar de aterrizaje es plano
	return h * flat


var _noise := FastNoiseLite.new()
var _craters := []
var _radius := 1737400.0 ## radio del planeta (la superficie se curva con él)
const PLANET_UV := 1600000.0 ## metros que abarca la textura entera (el sitio queda en el centro, lejos de los polos)
var _vp: SubViewport
var _cabin: CabinView
var _pov := false
var _env_ref: Environment


## El planeta entero: una esfera del tamaño real, con la superficie en y = 0 bajo el lugar de aterrizaje.
## Desde lo alto se ve el horizonte curvo.
func _planet(r: float, tex: String, tint: Color) -> void:
	# Casquete esférico alrededor del sitio: anillos cada vez más espaciados (hasta 600 km), con los
	# vértices exactamente sobre la esfera; la textura se proyecta igual que en el terreno de detalle.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radii := [0.0]
	var rr := 2400.0
	while rr < 600000.0:
		radii.append(rr)
		rr *= 1.18
	var seg := 160
	var pt := func(d: float, a: float) -> Vector3:
		var x := cos(a) * d
		var z := sin(a) * d
		# Bajo el terreno de detalle el casquete se hunde, para que no asome en el fondo de los cráteres
		var sink := 400.0 * clampf(1.0 - d / 2400.0, 0.0, 1.0)
		return Vector3(x, sqrt(maxf(r * r - d * d, 0.0)) - r - 2.5 - sink, z)
	for i in radii.size() - 1:
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var quad := [pt.call(radii[i], a0), pt.call(radii[i + 1], a0), pt.call(radii[i + 1], a1), pt.call(radii[i], a1)]
			for idx in [0, 1, 2, 0, 2, 3]:
				var v: Vector3 = quad[idx]
				st.set_uv(Vector2(0.5, 0.5) + Vector2(v.x, v.z) / PLANET_UV)
				st.add_vertex(v)
	st.generate_normals()
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(tex)
	mat.albedo_color = tint
	mat.roughness = 1.0
	m.material_override = mat
	_root.add_child(m)


func _build_moon() -> void:
	_noise.frequency = 0.004
	_noise.fractal_octaves = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	_radius = 1737400.0
	for k in 260:
		var c := Vector2(rng.randf_range(-2600, 2600), rng.randf_range(-2600, 2600))
		var r := clampf(10.0 * pow(rng.randf_range(0.02, 1.0), -0.8), 10.0, 420.0)
		if c.length() < 160.0 + r:
			continue
		_craters.append([c, r, r * 0.26])
	_planet(_radius, TEX + "2k_moon.jpg", Color(0.8, 0.8, 0.8))
	var mat := _ground_mat(TEX + "2k_moon.jpg", Color(0.8, 0.8, 0.8))
	_terrain(6000.0, 170, _moon_h, mat)
	_rocks(Color(0.45, 0.45, 0.45), _moon_h)
	# Cielo negro con estrellas (sin aire no hay cielo azul) y la Tierra a lo lejos
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load(TEX + "8k_stars_milky_way.jpg")
	sky_mat.energy_multiplier = 1.5
	_env(sky_mat, Color(0.05, 0.05, 0.06), 0.1)
	var earth := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 260.0
	s.height = 520.0
	earth.mesh = s
	var em := StandardMaterial3D.new()
	em.albedo_texture = load("res://assets/textures/nasa/earth_day.jpg")
	em.emission_enabled = true
	em.emission_texture = em.albedo_texture
	em.emission_energy_multiplier = 0.6
	earth.material_override = em
	s.radius = 6000.0
	s.height = 12000.0
	earth.position = Vector3(-90000, 60000, -210000)
	_root.add_child(earth)
	_sun(Vector3(-11, 140, 0), 2.6, Color(1, 0.98, 0.95)) # sol bajo, como en los alunizajes del Apolo: sombras largas
	# El Módulo Lunar
	_craft = Spacecraft.lunar_module()
	_root.add_child(_craft)
	_plume = _make_plume(Color(1.0, 0.75, 0.45), 1.2, 9.0)
	_plume.position.y = 0.6
	_craft.add_child(_plume)
	_dust = _make_dust(Color(0.7, 0.7, 0.7))
	_root.add_child(_dust)


func _build_mars() -> void:
	_noise.frequency = 0.003
	_noise.fractal_octaves = 5
	var mat := _ground_mat(TEX + "2k_mars.jpg", Color(1.0, 0.85, 0.75))
	mat.roughness = 1.0
	var h := func(x: float, z: float) -> float:
		return _noise.get_noise_2d(x, z) * 30.0 * clampf(Vector2(x, z).length() / 200.0, 0.0, 1.0)
	_radius = 3389500.0
	_planet(_radius, TEX + "2k_mars.jpg", Color(1.0, 0.85, 0.75))
	_terrain(6000.0, 140, h, mat)
	_rocks(Color(0.45, 0.25, 0.15), h)
	# Cielo de Marte: color caramelo por el polvo fino en el aire
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color(0.62, 0.48, 0.36)
	sky.sky_horizon_color = Color(0.85, 0.65, 0.48)
	sky.ground_bottom_color = Color(0.35, 0.2, 0.12)
	sky.ground_horizon_color = Color(0.75, 0.55, 0.4)
	_env(sky, Color(0.6, 0.45, 0.35), 0.5)
	_sun(Vector3(-40, 30, 0), 1.4, Color(1.0, 0.9, 0.8))
	# Cápsula (escudo + coraza) con el rover y la grúa aérea dentro
	_craft = Node3D.new()
	_root.add_child(_craft)
	_shell = Node3D.new()
	_craft.add_child(_shell)
	var back := _cone(2.2, 0.9, 3.0, Color(0.9, 0.9, 0.92))
	back.position.y = 1.5
	_shell.add_child(back)
	_glow = _cone(2.25, 2.25, 0.35, Color(0.35, 0.22, 0.15))
	_shell.add_child(_glow)
	_crane = _sky_crane()
	_crane.visible = false
	_craft.add_child(_crane)
	_rover = Spacecraft.model("perseverance", 3.0)
	_rover.visible = false
	_craft.add_child(_rover)
	_chute = Node3D.new()
	var canopy := MeshInstance3D.new()
	var cs := SphereMesh.new()
	cs.radius = 10.0
	cs.height = 7.0
	cs.is_hemisphere = true
	canopy.mesh = cs
	# Tela en gajos blancos y naranjas (como el de Perseverance) y las cuerdas hasta la cápsula
	var img := Image.create(64, 4, false, Image.FORMAT_RGB8)
	for x in 64:
		var c: Color = Color(0.95, 0.95, 0.93) if (x / 4) % 2 == 0 else Color(0.95, 0.45, 0.15)
		for y in 4:
			img.set_pixel(x, y, c)
	var cm := _std(Color.WHITE, 0.8)
	cm.albedo_texture = ImageTexture.create_from_image(img)
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	canopy.material_override = cm
	canopy.position.y = 22.0
	_chute.add_child(canopy)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for k in 16:
		var a := TAU * k / 16.0
		im.surface_add_vertex(Vector3(cos(a) * 10.0, 22.0, sin(a) * 10.0))
		im.surface_add_vertex(Vector3(0, 2.6, 0))
	im.surface_end()
	var lines := MeshInstance3D.new()
	lines.mesh = im
	lines.material_override = _std(Color(0.85, 0.85, 0.8), 0.9)
	_chute.add_child(lines)
	_chute.visible = false
	_craft.add_child(_chute)
	_plume = _make_plume(Color(1.0, 0.7, 0.4), 0.5, 4.0)
	_plume.visible = false
	_crane.add_child(_plume)
	_dust = _make_dust(Color(0.75, 0.45, 0.3))
	_root.add_child(_dust)


## Suelo de detalle: la misma foto del planeta que el casquete (sin cortes de color) y, de cerca,
## el grano y el relieve de arena real (Poly Haven) en la segunda capa de UV.
func _ground_mat(tex: String, tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(tex)
	mat.albedo_color = tint
	mat.roughness = 1.0
	mat.detail_enabled = true
	mat.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	mat.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	mat.detail_normal = load("res://assets/textures/polyhaven/coast_sand_01_nor.jpg")
	return mat


func _rocks(col: Color, h: Callable) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 1.4
	s.radial_segments = 7
	s.rings = 4
	mm.mesh = s
	mm.instance_count = 600
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in mm.instance_count:
		var p := Vector2(rng.randf_range(-700, 700), rng.randf_range(-700, 700))
		if p.length() < 30.0:
			p *= 3.0
		var sc := rng.randf_range(0.2, 2.2) * (1.0 if rng.randf() < 0.9 else 3.0)
		var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)).scaled(Vector3(sc, sc * 0.6, sc * 0.9))
		mm.set_instance_transform(k, Transform3D(b, Vector3(p.x, float(h.call(p.x, p.y)) + sc * 0.2, p.y)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _std(col, 1.0)
	_root.add_child(mi)


func _env(sky_mat: Material, amb: Color, amb_e: float) -> void:
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = amb
	env.ambient_light_energy = amb_e
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.ssao_enabled = true
	if body == "mars":
		env.fog_enabled = true
		env.fog_light_color = Color(0.8, 0.6, 0.45)
		env.fog_density = 0.0006
	_env_ref = env
	var we := WorldEnvironment.new()
	we.environment = env
	_root.add_child(we)


func _sun(rot: Vector3, e: float, c: Color) -> void:
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-rot.x if rot.x > 0 else rot.x, rot.y, rot.z)
	l.light_energy = e
	l.light_color = c
	l.shadow_enabled = true
	l.directional_shadow_max_distance = 300.0
	_root.add_child(l)


func _make_plume(c: Color, r: float, length: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = r * 0.6
	cone.bottom_radius = r * 1.6
	cone.height = length
	cone.cap_top = false
	cone.cap_bottom = false
	m.mesh = cone
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var g := Gradient.new()
	g.set_color(0, Color(c * 2.0, 0.55))
	g.set_color(1, Color(c, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	mat.albedo_texture = gt
	m.material_override = mat
	var holder := MeshInstance3D.new()
	m.position.y = -length / 2.0
	holder.add_child(m)
	return holder


func _make_dust(c: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 400
	p.lifetime = 2.5
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	# El polvo sale disparado en abanico casi a ras del suelo (en la Luna no hay aire que lo levante)
	pm.direction = Vector3(1, 0.05, 0)
	pm.spread = 180.0
	pm.flatness = 1.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 18.0
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.gravity = Vector3(0, -1.6 if body == "moon" else -3.7, 0)
	pm.scale_min = 1.0
	pm.scale_max = 3.0
	pm.color = Color(c, 0.5)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Explosion.smoke_sprite(3)
	q.material = mat
	p.draw_pass_1 = q
	return p


func _cone(r_bottom: float, r_top: float, h: float, c: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.bottom_radius = r_bottom
	cy.top_radius = r_top
	cy.height = h
	m.mesh = cy
	m.material_override = _std(c, 0.5)
	return m


## Grúa aérea como la del Mars 2020 (la que bajó a Perseverance): cuerpo octogonal, cuatro tanques
## esféricos, ocho motores inclinados hacia afuera en las esquinas y lámina dorada de aislamiento.
func _sky_crane() -> Node3D:
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 1.45
	bm.bottom_radius = 1.6
	bm.height = 0.55
	bm.radial_segments = 8
	body.mesh = bm
	body.material_override = _std(Color(0.55, 0.56, 0.58), 0.5)
	n.add_child(body)
	var foil := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 1.0
	fm.bottom_radius = 1.0
	fm.height = 0.4
	fm.radial_segments = 8
	foil.mesh = fm
	foil.position.y = 0.42
	var gold := _std(Color(0.85, 0.65, 0.25), 0.35)
	gold.metallic = 0.8
	foil.material_override = gold
	n.add_child(foil)
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var tank := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.42
		sm.height = 0.84
		tank.mesh = sm
		tank.position = Vector3(cos(a) * 0.8, 0.35, sin(a) * 0.8)
		tank.material_override = _std(Color(0.8, 0.8, 0.82), 0.3)
		n.add_child(tank)
	for k in 8:
		var a := TAU * k / 8.0
		var arm := Node3D.new()
		arm.position = Vector3(cos(a) * 1.55, -0.1, sin(a) * 1.55)
		arm.rotation = Vector3(0, -a, deg_to_rad(-25.0))
		n.add_child(arm)
		var nozzle := MeshInstance3D.new()
		var nm := CylinderMesh.new()
		nm.top_radius = 0.08
		nm.bottom_radius = 0.17
		nm.height = 0.4
		nozzle.mesh = nm
		nozzle.position.y = -0.22
		nozzle.material_override = _std(Color(0.2, 0.2, 0.22), 0.4)
		arm.add_child(nozzle)
	return n


func _std(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _build_hud() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(40, 36)
	add_child(box)
	var eye := Label.new()
	eye.text = "LD_EYEBROW_MOON" if body == "moon" else "LD_EYEBROW_MARS"
	eye.theme_type_variation = "Eyebrow"
	box.add_child(eye)
	_phase = Label.new()
	_phase.theme_type_variation = "Title"
	_phase.add_theme_font_size_override("font_size", 40)
	box.add_child(_phase)
	_hud = Label.new()
	_hud.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_hud.add_theme_font_override("font", Game.font_mono_medium)
	box.add_child(_hud)
	var skip := Button.new()
	skip.text = "TR_SKIP"
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	skip.offset_left = -200
	skip.offset_right = -40
	skip.offset_top = 36
	skip.offset_bottom = 76
	skip.pressed.connect(func() -> void: _finish())
	add_child(skip)
	var cab := Button.new()
	cab.text = "FL_CABIN"
	cab.toggle_mode = true
	cab.anchor_left = 1.0
	cab.anchor_right = 1.0
	cab.offset_left = -200
	cab.offset_right = -40
	cab.offset_top = 86
	cab.offset_bottom = 126
	cab.toggled.connect(func(on: bool) -> void:
		_pov = on
		if on and _cabin == null:
			_cabin = CabinView.new()
			_cabin.outside = _vp.get_texture()
			add_child(_cabin)
			move_child(_cabin, 1)
		if _cabin:
			_cabin.visible = on)
	add_child(cab)


# ---------- Animación ----------

func _step(key: String) -> void:
	if _said.has(key):
		return
	_said[key] = true
	_phase.text = "LD_" + key.to_upper()
	say.emit(key)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if body == "mars":
		_mars(delta)
	else:
		_moon(delta)


## Perfil del alunizaje (comprimido en el tiempo): descenso con velocidad de lado que se anula,
## giro a vertical, bajada lenta, contacto. Altura y = 0 en el lugar de aterrizaje.
func _moon(delta: float) -> void:
	var t := _t
	var pos := Vector3.ZERO
	var vy := 0.0
	var vx := 0.0
	var tilt := 0.0
	if t < 10.0:
		_step("pdi")
		var k := t / 10.0
		var e := 1.0 - pow(1.0 - k, 2.0)
		pos = Vector3(lerpf(-60000.0, -60.0, e), lerpf(12000.0, 60.0, 1.0 - pow(1.0 - k, 1.6)), 0)
		vx = lerpf(1600.0, 4.0, e)
		vy = -lerpf(60.0, 6.0, k)
		tilt = deg_to_rad(lerpf(75.0, 10.0, k)) # el motor apunta hacia adelante para frenar
	elif t < 17.0:
		_step("vertical")
		var k := (t - 10.0) / 7.0
		pos = Vector3(lerpf(-60.0, 0.0, k), lerpf(60.0, 0.0, k * (2.0 - k)), 0)
		vx = 3.0 * (1.0 - k)
		vy = -lerpf(6.0, 0.9, k)
		tilt = deg_to_rad(10.0 * (1.0 - k))
		# Sin combustible para la última parte: el motor se apaga y cae
		if not fuel_ok and pos.y < 45.0:
			_crash("fuel")
			return
	else:
		pos = Vector3.ZERO
		if not _said.has("contact"):
			if "legs" in gear_missing:
				_crash("legs")
				return
		_step("contact")
		_plume.visible = false
		_dust.emitting = false
		if t > 25.0:
			if walk_enabled and not _crashed and fuel_ok and gear_missing.is_empty():
				if not _walking:
					_start_walk()
				_walk(delta)
				return
			_finish()
	_craft.position = pos
	_craft.rotation.z = tilt
	_plume.visible = t < 17.0
	var flick := 1.0 + randf_range(-0.08, 0.08)
	_plume.scale = Vector3(flick, flick, flick)
	_dust.position = Vector3(pos.x, 0.5, 0)
	_dust.emitting = pos.y < 35.0 and t < 17.0
	_hud.text = tr("LD_HUD") % [Game.fmt(maxf(pos.y, 0.0), 0), Game.fmt(absf(vy), 1), Game.fmt(absf(vx), 1)]
	_follow(pos, clampf(pos.y * 0.5, 26.0, 9000.0))


func _mars(delta: float) -> void:
	var t := _t
	var pos := Vector3.ZERO
	var v := 0.0
	if t < 6.0:
		_step("entry")
		var k := t / 6.0
		pos = Vector3(lerpf(-140000.0, -300.0, 1.0 - pow(1.0 - k, 2.0)), lerpf(40000.0, 900.0, 1.0 - pow(1.0 - k, 1.5)), 0)
		v = lerpf(5400.0, 450.0, k)
		var gm := _glow.material_override as StandardMaterial3D
		gm.emission_enabled = true
		gm.emission = Color(1.0, 0.45, 0.15)
		gm.emission_energy_multiplier = 4.0 * (1.0 - k)
		if "heat_shield" in gear_missing and k > 0.4:
			_crash("heat")
			return
	elif t < 11.0:
		var k := (t - 6.0) / 5.0
		if "parachute" in gear_missing:
			pos = Vector3(lerpf(-300.0, 0.0, k), lerpf(900.0, 0.0, k), 0)
			if k > 0.95:
				_crash("chute")
				return
		else:
			_step("chute")
			_chute.visible = true
			pos = Vector3(lerpf(-300.0, -20.0, k), lerpf(900.0, 160.0, k), 0)
		v = lerpf(450.0, 90.0, k)
	elif t < 19.0:
		_step("skycrane")
		var k := (t - 11.0) / 8.0
		_chute.visible = false
		_shell.visible = false
		_crane.visible = true
		_rover.visible = true
		_plume.visible = true
		pos = Vector3(lerpf(-20.0, 0.0, k), lerpf(160.0, 9.0, k * (2.0 - k)), 0)
		_rover.position.y = -lerpf(1.0, 7.0, clampf((k - 0.6) / 0.3, 0.0, 1.0)) # cables bajan el rover
		v = lerpf(90.0, 0.75, k)
		if not fuel_ok and k > 0.6:
			_crash("fuel")
			return
	else:
		_step("touchdown")
		pos = Vector3(0, 9.0, 0)
		# La grúa corta los cables y se aleja para no caer sobre el rover
		var k := clampf((t - 19.0) / 3.0, 0.0, 1.0)
		_rover.top_level = true
		_rover.global_position = Vector3(0, 1.4, 0)
		_crane.position = Vector3(k * 60.0, k * 40.0, 0)
		if t > 25.0:
			_finish()
	_craft.position = pos
	# Bruma de polvo: densa cerca del suelo y casi nada desde lo alto (así se ve el horizonte curvo)
	_env_ref.fog_density = lerpf(0.0005, 0.000004, clampf(_cam.position.y / 12000.0, 0.0, 1.0))
	_dust.position = Vector3(pos.x, 0.5, 0)
	_dust.emitting = pos.y < 30.0 and t < 21.0
	_hud.text = tr("LD_HUD_MARS") % [Game.fmt(0.0 if t >= 19.0 else maxf(pos.y, 0.0), 0), Game.fmt(v, 0)]
	_follow(pos, 30.0 if t > 11.0 else clampf(pos.y * 0.35, 260.0, 14000.0))


func _follow(pos: Vector3, dist: float) -> void:
	if _pov:
		# Desde la ventana de la nave, mirando hacia adelante y abajo (lo que veían los astronautas)
		_cam.position = pos + Vector3(0, 4.0, 0)
		_cam.look_at(pos + Vector3(60.0, -40.0, 0), Vector3.UP)
		if _cabin:
			_cabin.set_data(maxf(pos.y, 0.0), 0.0, 1.0 if body == "moon" else 0.4, 1)
		return
	# Se suaviza la distancia a la nave (no la posición absoluta): la cámara la sigue pegada aunque vaya
	# a 1.600 m/s y se acerca o se aleja sin saltos cuando cambia la fase del descenso
	var goal := Vector3(dist * 0.45, dist * 0.25, dist)
	if _cam_off == Vector3.ZERO:
		_cam_off = goal
	_cam_off = _cam_off.lerp(goal, 1.0 - exp(-1.6 * get_process_delta_time()))
	_cam.position = pos + _cam_off
	_cam.look_at(pos + Vector3(0, 2, 0), Vector3.UP)


func _crash(why: String) -> void:
	if _crashed:
		return
	_crashed = true
	_step("crash_" + why)
	if why == "legs":
		# Sin patas el módulo se apoya en la campana del motor y se vuelca
		var tw := create_tween()
		tw.tween_property(_craft, "rotation:z", deg_to_rad(75.0), 1.2).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void: Explosion.spawn(_root, _craft.position + Vector3(0, 2, 0), 6.0, body == "moon", true))
	else:
		Explosion.spawn(_root, _craft.position, 8.0, body == "moon", why != "heat")
		_craft.visible = false
	_plume.visible = false
	var t := get_tree().create_timer(5.0)
	t.timeout.connect(func() -> void: _finish())


# ---------- Caminata lunar y bandera ----------

func _ground(x: float, z: float) -> float:
	return _moon_h(x, z) - _moon_h(0.0, 0.0)


func _start_walk() -> void:
	_walking = true
	_fade_in()
	_walk_t = 0.0
	_step("walk")
	_walker.y = _ground(_walker.x, _walker.z)
	Sound.flight_music = "moon"
	_yaw = PI # de espaldas al módulo, mirando hacia la marca (+Z)
	_pitch = -0.35 # un poco hacia abajo: se ven los brazos y el traje
	# Primera persona: plano cercano corto para ver brazos y guantes (a 0,3 m se recortaban)
	_cam.near = 0.04
	_cam.far = 20000.0
	_body = Astronaut.new()
	_body.role = "commander"
	_body.base_anim = "Idle"
	_root.add_child(_body)
	_body.set_head_visible(false)
	if not "--crewai" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # el ratón mueve la cabeza (Esc lo suelta)
	# Marca donde va la bandera: anillo que brilla en el suelo
	_marker = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.05
	_marker.mesh = tm
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(1.0, 0.6, 0.2)
	_marker.material_override = mm
	_marker.position = _flag_spot + Vector3(0, _ground(_flag_spot.x, _flag_spot.z) + 0.05, 0)
	_root.add_child(_marker)
	_prompt = Label.new()
	_prompt.theme_type_variation = "Title"
	_prompt.add_theme_font_size_override("font_size", 28)
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_top = -170
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.text = "LW_WALK"
	add_child(_prompt)


func _walk(delta: float) -> void:
	_walk_t += delta
	if _planting >= 0.0:
		_plant_cinematic(delta)
		return
	# Entrada: WASD / flechas / stick izquierdo para caminar; stick derecho para mirar
	var mv := Vector2(float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	for dev in Input.get_connected_joypads():
		var ls := Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
		if ls.length() > 0.2:
			mv = ls
		var rs := Vector2(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y))
		if rs.length() > 0.2:
			_yaw -= rs.x * 2.2 * delta
			_pitch = clampf(_pitch - rs.y * 1.6 * delta, -1.0, 0.8)
	if mv != Vector2.ZERO:
		_idle_t = 0.0
	else:
		_idle_t += delta
	# Sin nadie a los controles (prueba, o 25 s sin tocar nada): camina solo hacia la marca y se detiene
	# en ella. Antes seguía girando hacia el centro de la marca al llegar y la cámara daba vueltas.
	var to := _flag_spot - _walker
	to.y = 0.0
	if ("--crewai" in OS.get_cmdline_user_args() or _idle_t > 25.0) and to.length() > 1.2:
		_yaw = lerp_angle(_yaw, atan2(-to.x, -to.z), 1.0 - exp(-3.0 * delta))
		mv = Vector2(0, -1)
	var basis := Basis(Vector3.UP, _yaw)
	var dir := basis * Vector3(mv.x, 0, mv.y)
	var moving := dir.length() > 0.1
	if moving:
		# En el aire se sigue avanzando (inercia); en el suelo, paso lento con traje
		_walker += dir.normalized() * (1.9 if _air > 0.0 else 1.4) * delta
	# Gravedad lunar real: cada paso es un saltito largo y lento (en la Luna pesas 1/6)
	if _air <= 0.0 and _vy <= 0.0:
		_air = 0.0
		if moving:
			_vy = 1.1 # saltito al caminar (~0,4 m y casi 1,4 s en el aire)
		if Input.is_key_pressed(KEY_SPACE) and _prompt.text != "LW_PLANT":
			_vy = 2.4 # salto alto (~1,8 m): en la Tierra serían 30 cm
		for dev in Input.get_connected_joypads():
			if Input.is_joy_button_pressed(dev, JOY_BUTTON_B):
				_vy = 2.4
	_vy -= MOON_G * delta
	_air = maxf(_air + _vy * delta, 0.0)
	if _air == 0.0 and _vy < -0.6:
		_dust.position = _walker + Vector3(0, 0.1, 0) # polvo al caer
		_dust.restart()
		_dust.emitting = true
	if _air == 0.0:
		_vy = minf(_vy, 0.0)
	_walker.y = _ground(_walker.x, _walker.z) + _air
	_body.position = _walker
	_body.rotation.y = _yaw + PI
	var want := "Walk" if moving else "Idle"
	if want != _body_anim:
		_body_anim = want
		_body.play(want)
	if _body.anim:
		_body.anim.speed_scale = 0.6 # todo más lento con traje y poca gravedad
	var fwd := Basis(Vector3.UP, _yaw) * Vector3(0, 0, -1)
	# Ojos a la altura de la cabeza del modelo (el traje mide menos que 1,6 m hasta los ojos)
	if _eye_h <= 0.0 and _body.skeleton:
		_eye_h = _body.bone_local("Head").y + 0.1
	var eye := _walker + Vector3(0, _eye_h if _eye_h > 0.0 else 1.45, 0) + fwd * 0.1
	_cam.global_transform = Transform3D(Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch), eye)
	if "--walk3p" in OS.get_cmdline_user_args(): # prueba: cámara detrás para ver el cuerpo
		var dc: Camera3D = _root.get_node_or_null("DbgCam")
		if dc == null:
			dc = Camera3D.new()
			dc.name = "DbgCam"
			_root.add_child(dc)
		dc.current = true
		dc.global_position = eye + fwd * 1.8 + Vector3(0.8, 0.2, 0)
		dc.look_at(eye - Vector3(0, 0.4, 0))
	_marker.rotation.y += delta
	var near := Vector2(_walker.x - _flag_spot.x, _walker.z - _flag_spot.z).length() < 2.2
	_prompt.text = "LW_PLANT" if near else "LW_WALK"
	if near and ("--crewai" in OS.get_cmdline_user_args() or _idle_t > 30.0):
		_plant()


func _input(event: InputEvent) -> void:
	if not _walking or _planting >= 0.0:
		return
	# Mirar con el ratón siempre (capturado; si se soltó con Esc, también con el ratón libre)
	if event is InputEventMouseMotion:
		_idle_t = 0.0
		_yaw -= event.relative.x * 0.003
		_pitch = clampf(_pitch - event.relative.y * 0.003, -1.3, 0.8)
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var act: bool = (event is InputEventKey and event.pressed and event.keycode in [KEY_SPACE, KEY_E]) or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A)
	if act and _prompt.text == "LW_PLANT":
		_plant()
		get_viewport().set_input_as_handled()


## Cinemática: cámara en tercera persona alrededor del comandante mientras la bandera sube.
func _plant() -> void:
	_planting = 0.0
	_fade_in()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _body:
		_body.queue_free()
		_body = null
	_cam.near = 0.3
	_cam.far = 4000000.0
	_prompt.visible = false
	_marker.visible = false
	_step("flag")
	_astro = Astronaut.new()
	_astro.role = "commander"
	_astro.base_anim = "Interact"
	_root.add_child(_astro)
	var g := _ground(_flag_spot.x, _flag_spot.z)
	_astro.position = Vector3(_flag_spot.x, g, _flag_spot.z - 0.9)
	_flag = Node3D.new()
	_flag.position = Vector3(_flag_spot.x, g - 2.0, _flag_spot.z)
	_root.add_child(_flag)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.02
	pm.bottom_radius = 0.02
	pm.height = 2.4
	pole.mesh = pm
	pole.position.y = 1.2
	pole.material_override = _std(Color(0.85, 0.85, 0.88), 0.3)
	_flag.add_child(pole)
	var bar := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.012
	bm.bottom_radius = 0.012
	bm.height = 1.0
	bar.mesh = bm
	bar.rotation_degrees = Vector3(0, 0, 90)
	bar.position = Vector3(0.5, 2.35, 0)
	bar.material_override = pole.material_override
	_flag.add_child(bar)
	var cloth := MeshInstance3D.new()
	var cm := QuadMesh.new()
	cm.size = Vector2(1.0, 0.62)
	cloth.mesh = cm
	cloth.position = Vector3(0.5, 2.03, 0)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.06, 0.12, 0.24)
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.material_override = fm
	_flag.add_child(cloth)
	var stripe := MeshInstance3D.new()
	var sm := QuadMesh.new()
	sm.size = Vector2(1.0, 0.1)
	stripe.mesh = sm
	stripe.position = Vector3(0.5, 1.84, 0.002)
	stripe.material_override = _std(Color(1.0, 0.55, 0.15), 0.6)
	(stripe.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	_flag.add_child(stripe)
	for side in [1.0, -1.0]:
		# El logo de Xorbit en la bandera, por las dos caras
		var logo := Sprite3D.new()
		logo.texture = load("res://assets/ui/xorbit_logo.png")
		logo.pixel_size = 0.9 / 1140.0
		logo.position = Vector3(0.5, 2.08, 0.004 * side)
		logo.rotation.y = 0.0 if side > 0.0 else PI
		_flag.add_child(logo)
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(_flag, "position:y", g, 1.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _plant_cinematic(delta: float) -> void:
	_planting += delta
	var a := 0.6 + _planting * 0.05 # giro lento y corto alrededor del comandante
	var center := _flag_spot + Vector3(0, _ground(_flag_spot.x, _flag_spot.z) + 1.3, 0)
	_cam.global_position = center + Vector3(sin(a) * 6.0, 1.2 + _planting * 0.15, cos(a) * 6.0)
	_cam.look_at(center, Vector3.UP)
	if _planting > 1.4 and _astro and _astro.anim:
		_astro.look_at_point(center + Vector3(0, 0.8, 0), true)
	if _planting > 9.0:
		_finish()


## Al cambiar de cámara (salir a caminar, plantar la bandera) la imagen aparece desde negro en vez de saltar.
func _fade_in(t := 0.8) -> void:
	var r := ColorRect.new()
	r.color = Color.BLACK
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	var tw := r.create_tween()
	tw.tween_property(r, "color:a", 0.0, t).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(r.queue_free)


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit(not _crashed and fuel_ok and gear_missing.is_empty())
