class_name TransferView
extends SubViewportContainer
## Vista de mapa del viaje después de la órbita baja (misiones 2-9): la nave sigue los tramos
## de la misión (data/levels.json → legs) sobre el sistema Tierra-Luna o el sistema solar,
## con planetas texturizados (Solar System Scope, CC BY 4.0) y la Vía Láctea de fondo.
## Cada tramo es una maniobra con su Δv: si al cohete le alcanza el Δv sobrante, la hace;
## si no, la nave se queda donde llegó y Houston explica cuánto faltó.
## Escalas: distancias con proporciones reales dentro de cada sistema; los planetas, agrandados.

signal finished
signal say(kind: String, leg: String)

const TEX := "res://assets/textures/planets/"

var level := {} ## entrada de levels.json (view, target, legs)
var leftover := 0.0 ## Δv que sobró en órbita baja (m/s)

var _root: Node3D
var _cam: Camera3D
var _probe: MeshInstance3D
var _trail: MeshInstance3D
var _trail_pts := PackedVector3Array()
var _label: Label
var _sub: Label
var _bodies := {} ## nombre -> Node3D
var _orbits := {} ## nombre -> {r, period_s (de la animación), angle0}
var _steps: Array = [] ## [{kind, leg, dur, from(Callable->Vector3)...}]
var _si := 0
var _st := 0.0
var _t := 0.0
var _done := false
var _cam_target := Vector3.ZERO
var _cam_dist := 30.0
var _cam_dist_goal := 30.0
var _reached := 0 ## tramos cumplidos
var _labels: Array[Label3D] = []
var _vp: SubViewport
var _cabin: CabinView
var _pov := false
var _stage_node: Node3D ## etapa de arriba que empuja la nave en el encendido
var _stage_flame: MeshInstance3D
var _stage_dropped := false
var _stage_drift := Vector3.ZERO
var _planned_drawn := false
var _plan_box := AABB()
var _craft: Node3D
var _craft_id := ""
var _craft_size := 0.35
var _follow: Array = [] ## [nodo, cuerpo]: nodos que siguen la posición de un cuerpo sin girar con él


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stretch = true
	var vp := SubViewport.new()
	_vp = vp
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	_root = Node3D.new()
	vp.add_child(_root)
	_environment()
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 100000.0
	_cam.near = 0.01
	_root.add_child(_cam)
	_build()
	_hud()


func _environment() -> void:
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load(TEX + "8k_stars_milky_way.jpg")
	sky_mat.energy_multiplier = 3.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.27, 0.32)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.15
	var we := WorldEnvironment.new()
	we.environment = env
	_root.add_child(we)


func _sphere(r: float, tex: String, emissive := false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 48
	s.rings = 24
	m.mesh = s
	var mat := StandardMaterial3D.new()
	if tex != "":
		mat.albedo_texture = load(tex)
	mat.roughness = 0.9
	if emissive:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(2.2, 2.0, 1.7)
	m.material_override = mat
	_root.add_child(m)
	return m


## Halo de atmósfera (borde que brilla) alrededor de un planeta.
func _atmo(body: Node3D, r: float, col: Color, strength := 1.6) -> void:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r * 1.06
	s.height = r * 2.12
	s.radial_segments = 48
	s.rings = 24
	m.mesh = s
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/atmo_rim.gdshader")
	mat.set_shader_parameter("color", col)
	mat.set_shader_parameter("strength", strength)
	m.material_override = mat
	body.add_child(m)


## Nombre del cuerpo, siempre del mismo tamaño en pantalla.
func _name(body: Node3D, key: String, r: float) -> void:
	var l := Label3D.new()
	l.text = tr(key)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font_size = 28
	l.outline_size = 8
	l.modulate = Color(0.85, 0.9, 1.0, 0.9)
	l.no_depth_test = true
	l.position = Vector3(0, r * 1.5 + 0.05, 0)
	l.top_level = false
	body.add_child(l)
	# El nombre no debe girar con el planeta: se compensa en _process
	_labels.append(l)


## Anillos de Saturno: un disco con bandas transparentes.
func _rings(body: Node3D, r: float) -> void:
	var m := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(r * 4.6, r * 4.6)
	m.mesh = q
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.52, 0.56, 0.75, 0.78, 0.92, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.85, 0.78, 0.62, 0.7), Color(0.9, 0.84, 0.7, 0.85), Color(0.3, 0.28, 0.24, 0.2), Color(0.8, 0.74, 0.6, 0.6), Color(0, 0, 0, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = gt
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material_override = mat
	m.rotation.x = deg_to_rad(26.7)
	body.add_child(m)


## Esfera de influencia (SOI): dentro de ella manda la gravedad de ese cuerpo.
func _soi(body: Node3D, r: float) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for k in 97:
		var a := TAU * k / 96.0
		im.surface_add_vertex(Vector3(cos(a) * r, 0, sin(a) * r))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.4, 0.9, 1.0, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	var holder := Node3D.new()
	holder.add_child(mi)
	var l := Label3D.new()
	l.text = tr("TR_SOI")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0009
	l.font_size = 22
	l.modulate = Color(0.4, 0.9, 1.0, 0.8)
	l.position = Vector3(r, 0, 0)
	holder.add_child(l)
	_root.add_child(holder)
	_follow.append([holder, body])


func _ring(r: float, col: Color) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for k in 129:
		var a := TAU * k / 128.0
		im.surface_add_vertex(Vector3(cos(a) * r, 0, sin(a) * r))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	_root.add_child(mi)


func _sun_light(dir: Vector3, energy := 1.6) -> void:
	var l := DirectionalLight3D.new()
	l.light_energy = energy
	_root.add_child(l)
	l.look_at_from_position(Vector3.ZERO, dir, Vector3.UP if absf(dir.normalized().y) < 0.9 else Vector3.FORWARD)


func _point_light(pos: Vector3, energy: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 0.2
	_root.add_child(l)


# ---------- Escenas ----------

func _build() -> void:
	var view := str(level.get("view", "earth"))
	var target := str(level.get("target", ""))
	var legs: Array = level.get("legs", [])
	# Cuántos tramos alcanza el Δv sobrante
	var left := leftover
	for lg: Dictionary in legs:
		if left + 1.0 >= float(lg.dv):
			left -= float(lg.dv)
			_reached += 1
		else:
			break
	match view:
		"earth":
			_build_earth_system(target, legs)
		"sun":
			_build_solar_system(target, legs)
		_:
			_build_galaxy()
	_probe = _sphere(0.02 if view == "earth" else 0.08, "", true)
	(_probe.material_override as StandardMaterial3D).albedo_color = Color(3.0, 1.6, 0.6)
	# La nave real de una misión parecida (GOES, Apolo, LRO, Perseverance, Juno, Voyager)
	_craft_id = str(Spacecraft.BY_MISSION.get(int(level.get("id", 0)), ""))
	_craft_size = 0.12 if view == "earth" else 0.16 # más chica que la Luna (0,59) y que Marte (0,35)
	if _craft_id != "":
		_craft = Spacecraft.model(_craft_id, _craft_size)
		_probe.add_child(_craft)
	_build_stage()
	var fill := DirectionalLight3D.new() # luz suave para que la nave se vea de cualquier lado
	fill.light_energy = 0.4
	fill.rotation_degrees = Vector3(-30, 140, 0)
	_root.add_child(fill)
	_trail = MeshInstance3D.new()
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(1.0, 0.6, 0.25)
	_trail.material_override = tm
	_root.add_child(_trail)


## Tierra-Luna. Radio de la Tierra = 1; órbita baja 1,03; GEO 6,6; Luna a 60 (proporción real).
func _build_earth_system(target: String, legs: Array) -> void:
	var earth := _sphere(1.0, "res://assets/textures/nasa/earth_day.jpg")
	earth.rotation.x = deg_to_rad(-23.4)
	_bodies.earth = earth
	_atmo(earth, 1.0, Color(0.35, 0.6, 1.0))
	_name(earth, "PL_EARTH", 1.0)
	_sun_light(Vector3(-1, -0.15, -0.4))
	var moon := _sphere(0.27 * 2.2, TEX + "2k_moon.jpg") # Luna agrandada ×2,2 para verla
	_bodies.moon = moon
	_name(moon, "PL_MOON", 0.6)
	_soi(moon, 10.4) # 66.000 km: desde ahí manda la gravedad de la Luna
	_orbits.moon = {"r": 60.0, "w": 0.06, "a0": 0.0}
	_ring(60.0, Color(0.6, 0.7, 0.85, 0.25))
	_ring(1.08, Color(1, 0.6, 0.3, 0.35))
	var leo := 1.08
	_add_step("park", "", 3.0, func(k: float) -> Vector3: return _circle(leo, k * TAU * 0.6))
	if target == "geo":
		_ring(6.6, Color(0.5, 0.9, 0.6, 0.3))
		_hohmann_steps(legs, leo, 6.6, "", false)
	else:
		_hohmann_steps(legs, leo, 60.0, "moon", false)
	_cam_dist = 6.0
	_cam_dist_goal = 6.0


## Sistema solar. 1 UA = 10 unidades (Tierra 10, Marte 15,2, Júpiter 52); planetas agrandados.
func _build_solar_system(target: String, legs: Array) -> void:
	var sun := _sphere(1.6, TEX + "2k_sun.jpg", true)
	_bodies.sun = sun
	_atmo(sun, 1.6, Color(1.0, 0.6, 0.2), 3.0)
	_name(sun, "PL_SUN", 1.6)
	_point_light(Vector3.ZERO, 6.0, 1500.0)
	# Los ocho planetas a su distancia real (1 UA = 10); tamaños agrandados para verlos
	var data := {"mercury": [3.87, 0.22, TEX + "2k_mercury.jpg", 4.15],
		"venus": [7.23, 0.45, TEX + "2k_venus_atmosphere.jpg", 1.62],
		"earth": [10.0, 0.5, "res://assets/textures/nasa/earth_day.jpg", 1.0],
		"mars": [15.24, 0.35, TEX + "2k_mars.jpg", 0.53],
		"jupiter": [52.0, 1.6, TEX + "2k_jupiter.jpg", 0.084],
		"saturn": [95.4, 1.3, TEX + "2k_saturn.jpg", 0.034],
		"uranus": [192.0, 0.9, TEX + "2k_uranus.jpg", 0.0119],
		"neptune": [301.0, 0.88, TEX + "2k_neptune.jpg", 0.0061]}
	_asteroid_belt()
	for nm: String in data:
		var d: Array = data[nm]
		_bodies[nm] = _sphere(float(d[1]), str(d[2]))
		_name(_bodies[nm], "PL_" + nm.to_upper(), float(d[1]))
		match nm:
			"earth":
				_atmo(_bodies[nm], float(d[1]), Color(0.35, 0.6, 1.0))
			"mars":
				_atmo(_bodies[nm], float(d[1]), Color(1.0, 0.55, 0.3), 0.9)
			"jupiter":
				_atmo(_bodies[nm], float(d[1]), Color(1.0, 0.85, 0.6), 0.7)
			"venus":
				_atmo(_bodies[nm], float(d[1]), Color(1.0, 0.9, 0.6), 1.2)
			"uranus", "neptune":
				_atmo(_bodies[nm], float(d[1]), Color(0.5, 0.8, 1.0), 0.9)
			"saturn":
				_rings(_bodies[nm], float(d[1]))
		_orbits[nm] = {"r": float(d[0]), "w": 0.05 * float(d[3]), "a0": 0.0}
		_ring(float(d[0]), Color(0.6, 0.7, 0.85, 0.22))
	_add_step("park", "", 2.5, func(k: float) -> Vector3: return _body_pos("earth") + _circle(0.7, k * TAU))
	if target == "escape":
		var start := _body_pos("earth")
		_add_step("burn", legs[0].key if legs.size() > 0 else "", 1.5, func(_k: float) -> Vector3: return start)
		if _reached >= 1:
			_add_step("coast", legs[0].key, 9.0, func(k: float) -> Vector3:
				var dir := start.normalized()
				return dir * lerpf(10.0, 160.0, pow(k, 1.6)) + Vector3(-dir.z, 0, dir.x) * 20.0 * sin(k * PI * 0.5))
			_add_step("arrive", "escape", 3.0, func(_k: float) -> Vector3: return start.normalized() * 160.0 + Vector3(-start.normalized().z, 0, start.normalized().x) * 20.0)
		else:
			_add_step("short", legs[0].key if legs.size() > 0 else "", 3.0, func(_k: float) -> Vector3: return start)
		_cam_dist = 40.0
		_cam_dist_goal = 40.0
		return
	_hohmann_steps(legs, 10.0, float(_orbits[target].r), target, true)
	_cam_dist = 26.0
	_cam_dist_goal = 26.0


## Cinturón de asteroides entre Marte y Júpiter (2,2 a 3,2 UA).
func _asteroid_belt() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var s := SphereMesh.new()
	s.radius = 0.06
	s.height = 0.1
	s.radial_segments = 5
	s.rings = 3
	mm.mesh = s
	mm.instance_count = 1500
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for k in mm.instance_count:
		var a := rng.randf() * TAU
		var r := rng.randf_range(22.0, 32.0)
		mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.4, 1.6)), Vector3(cos(a) * r, rng.randf_range(-0.4, 0.4), sin(a) * r)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.5, 0.45)
	mi.material_override = m
	_root.add_child(mi)


func _build_galaxy() -> void:
	var sun := _sphere(0.4, TEX + "2k_sun.jpg", true)
	_bodies.sun = sun
	for r in [3.0, 4.5, 15.0, 28.0]:
		_ring(r, Color(0.6, 0.7, 0.85, 0.2))
	_add_step("galaxy", "", 12.0, func(k: float) -> Vector3: return Vector3(lerpf(3.0, 60.0, k), 0, 0))
	_cam_dist = 10.0
	_cam_dist_goal = 900.0


## Pasos de una transferencia de Hohmann de r1 a r2: encendido, viaje por media elipse,
## y en la llegada captura/aterrizaje según los tramos que alcanzó el Δv.
func _hohmann_steps(legs: Array, r1: float, r2: float, target: String, helio: bool) -> void:
	if legs.is_empty():
		return
	var moon := target == "moon"
	var target_pos := func() -> Vector3: return _body_pos(target) if target != "" else Vector3.ZERO
	var leg0: String = legs[0].key
	var travel := 9.0 if helio else 7.0
	# Momento en que empieza el viaje (después de la órbita de espera y del encendido)
	var t0 := 2.0
	for s in _steps:
		t0 += float(s.dur)
	# Desde dónde sale: en el sistema solar, desde donde esté la Tierra en t0
	var start_angle := 0.0
	if helio:
		var ep := _body_pos_at("earth", t0)
		start_angle = atan2(ep.z, ep.x)
	# Ventana de lanzamiento: el destino tiene que estar en el lado opuesto (θ = π) al llegar
	if target != "" and _orbits.has(target):
		_orbits[target].a0 = start_angle + PI - float(_orbits[target].w) * (t0 + travel)
	var p0 := func() -> Vector3: return _circle(r1, start_angle) if not helio else _body_pos("earth")
	_add_step("burn", leg0, 2.0, func(_k: float) -> Vector3: return p0.call())
	if _reached < 1:
		_add_step("short", leg0, 3.0, func(_k: float) -> Vector3: return p0.call())
		return
	var a := (r1 + r2) / 2.0
	var e := (r2 - r1) / (r2 + r1)
	_add_step("coast", leg0, travel, func(k: float) -> Vector3:
		var th := PI * _kepler(k, e)
		var rr := a * (1.0 - e * e) / (1.0 + e * cos(th))
		return Vector3(cos(start_angle + th), 0, sin(start_angle + th)) * rr)
	if legs.size() < 2:
		_add_step("arrive", leg0, 3.0, func(k: float) -> Vector3: return target_pos.call() + _circle(0.9 if helio else 0.0, k))
		return
	var leg1: String = legs[1].key
	if _reached < 2:
		# Sin Δv para frenar: pasa de largo
		_add_step("flyby", leg1, 5.0, func(k: float) -> Vector3:
			var tp: Vector3 = target_pos.call()
			var out := Vector3(-tp.z, 0, tp.x).normalized()
			return tp + out * k * (8.0 if helio else 12.0) + tp.normalized() * k * 3.0)
		return
	var cap_r := 2.2 if moon else (1.4 if helio else 0.0)
	if r2 < 10.0 and not helio and not moon:
		_add_step("arrive", leg1, 5.0, func(k: float) -> Vector3: return _circle(r2, PI + k * TAU * 0.4))
		return
	_add_step("arrive", leg1, 5.0, func(k: float) -> Vector3: return target_pos.call() + _circle(cap_r, k * TAU))
	# El aterrizaje (tercer tramo) se muestra después, en la escena 3D de la superficie (LandingView)


func _add_step(kind: String, leg: String, dur: float, pos: Callable) -> void:
	_steps.append({"kind": kind, "leg": leg, "dur": dur, "pos": pos})


## Avance por la elipse más lento lejos (2.ª ley de Kepler aproximada).
static func _kepler(k: float, e: float) -> float:
	return lerpf(k, 1.0 - pow(1.0 - k, 1.0 + e * 1.4), 0.75)


func _circle(r: float, ang: float) -> Vector3:
	return Vector3(cos(ang) * r, 0, sin(ang) * r)


func _body_pos(nm: String) -> Vector3:
	return _body_pos_at(nm, _t)


func _body_pos_at(nm: String, t: float) -> Vector3:
	if not _orbits.has(nm):
		return Vector3.ZERO
	var o: Dictionary = _orbits[nm]
	return _circle(float(o.r), float(o.a0) + float(o.w) * t)


# ---------- HUD ----------

func _hud() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(40, 36)
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	var eye := Label.new()
	eye.text = "TR_MAP"
	eye.theme_type_variation = "Eyebrow"
	box.add_child(eye)
	_label = Label.new()
	_label.theme_type_variation = "Title"
	_label.add_theme_font_size_override("font_size", 40)
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	box.add_child(_label)
	_sub = Label.new()
	_sub.theme_type_variation = "Body"
	_sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_sub.add_theme_font_override("font", Game.font_mono_medium)
	box.add_child(_sub)
	var skip := Button.new()
	skip.text = "TR_SKIP"
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	skip.offset_left = -200
	skip.offset_right = -40
	skip.offset_top = 36
	skip.offset_bottom = 76
	skip.pressed.connect(_finish)
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

func _process(delta: float) -> void:
	if _done or _steps.is_empty():
		return
	_t += delta
	_st += delta
	# Planetas en sus órbitas y girando
	for nm in _orbits:
		(_bodies[nm] as Node3D).position = _body_pos(nm)
	for nm in _bodies:
		(_bodies[nm] as Node3D).rotate_y(delta * 0.15)
	for f in _follow:
		(f[0] as Node3D).position = (f[1] as Node3D).position
	var s: Dictionary = _steps[_si]
	var k := clampf(_st / float(s.dur), 0.0, 1.0)
	var p: Vector3 = (s.pos as Callable).call(k)
	# La nave apunta hacia donde va (dirección de la velocidad)
	var vel := p - _probe.position
	_probe.position = p
	if vel.length() > 0.0005:
		var fwd := vel.normalized()
		var side := fwd.cross(Vector3.UP)
		if side.length() > 0.01:
			_probe.basis = _probe.basis.slerp(Basis(side.normalized(), fwd, side.normalized().cross(fwd)).orthonormalized(), clampf(delta * 4.0, 0.0, 1.0))
	# La etapa de arriba empuja durante el encendido y se suelta al empezar el viaje
	if _stage_node and is_instance_valid(_stage_node):
		_stage_flame.visible = s.kind == "burn"
		if s.kind == "burn":
			_stage_flame.scale = Vector3.ONE * (1.0 + randf_range(-0.1, 0.1))
		elif s.kind == "coast" and not _stage_dropped:
			_drop_stage()
	if _stage_dropped and is_instance_valid(_stage_node):
		_stage_node.position += _stage_drift * delta
		_stage_node.rotate_z(delta * 0.6)
		_stage_node.scale *= 1.0 - delta * 0.15
	if s.kind in ["coast", "arrive", "land", "flyby"]:
		_trail_pts.append(p)
		_draw_trail()
	_show_step(s)
	# Antes de encender, se dibuja la trayectoria planeada completa (línea tenue)
	if s.kind == "burn" and not _planned_drawn:
		_draw_planned()
	# Cámara: cerca de la nave al salir y al llegar; en el viaje, fija y encuadrando salida y destino
	var goal := p
	if s.kind == "coast" and _plan_box.size != Vector3.ZERO:
		goal = _plan_box.get_center()
	elif s.kind == "galaxy":
		goal = Vector3.ZERO
	_cam_target = _cam_target.lerp(goal, clampf(delta * 1.0, 0.0, 1.0))
	if s.kind == "coast":
		_cam_dist_goal = maxf(_plan_box.size.length() * 0.85, 8.0)
	elif s.kind in ["arrive", "land"]:
		_cam_dist_goal = 4.0 if str(level.get("view")) == "earth" else 6.0
	elif s.kind == "galaxy":
		_cam_dist_goal = lerpf(10.0, 1500.0, k * k)
	_cam_dist = lerpf(_cam_dist, _cam_dist_goal, clampf(delta * 0.8, 0.0, 1.0))
	var ang := _t * 0.05
	if _pov:
		# Desde la nave, mirando hacia donde va
		var fwd := _probe.basis.y
		_cam.position = _probe.position + fwd * _craft_size * 0.6
		_cam.look_at(_cam.position + fwd * 10.0, Vector3.UP if absf(fwd.y) < 0.95 else Vector3.FORWARD)
		if _cabin:
			_cabin.set_data(0.0, 0.0, 0.0, 1)
	else:
		_cam.position = _cam_target + Vector3(cos(ang) * 0.6, 0.55, sin(ang) * 0.6).normalized() * _cam_dist
		_cam.look_at(_cam_target, Vector3.UP)
	if k >= 1.0:
		_si += 1
		_st = 0.0
		if _si >= _steps.size():
			_finish()
		else:
			_announce(_steps[_si])


## Etapa de arriba (blanca, como la S-IVB del Saturno V) acoplada detrás de la nave, con su llama.
func _build_stage() -> void:
	_stage_node = Node3D.new()
	var c := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = _craft_size * 0.22
	cy.bottom_radius = _craft_size * 0.22
	cy.height = _craft_size * 1.1
	c.mesh = cy
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.92, 0.92, 0.9)
	m.roughness = 0.5
	c.material_override = m
	c.position.y = -_craft_size * 0.95
	_stage_node.add_child(c)
	_stage_flame = MeshInstance3D.new()
	var fl := CylinderMesh.new()
	fl.top_radius = _craft_size * 0.12
	fl.bottom_radius = _craft_size * 0.03
	fl.height = _craft_size * 1.2
	_stage_flame.mesh = fl
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(2.5, 1.6, 0.8)
	_stage_flame.material_override = fm
	_stage_flame.position.y = -_craft_size * 2.1
	_stage_flame.visible = false
	_stage_node.add_child(_stage_flame)
	_probe.add_child(_stage_node)
	var l := Label3D.new()
	l.text = tr("TR_UPPER_STAGE")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0009
	l.font_size = 22
	l.modulate = Color(0.85, 0.9, 1.0, 0.85)
	l.no_depth_test = true
	l.position = Vector3(_craft_size * 0.5, -_craft_size * 1.0, 0)
	if str(level.get("view", "")) == "earth": # en el sistema solar se encimaría con el nombre de la Tierra
		_stage_node.add_child(l)
	else:
		l.free()


func _drop_stage() -> void:
	_stage_dropped = true
	_stage_flame.visible = false
	var gp := _stage_node.global_transform
	_probe.remove_child(_stage_node)
	_root.add_child(_stage_node)
	_stage_node.global_transform = gp
	_stage_drift = -_probe.basis.y * _craft_size * 0.6
	say.emit("separate", "")


## Trayectoria planeada: se toma la posición del paso de viaje en muchos puntos y se dibuja tenue.
func _draw_planned() -> void:
	_planned_drawn = true
	var pts := PackedVector3Array()
	for st in _steps:
		if st.kind in ["coast", "flyby"]:
			for j in 81:
				pts.append((st.pos as Callable).call(j / 80.0))
	if pts.size() < 2:
		return
	_plan_box = AABB(pts[0], Vector3.ZERO)
	for q in pts:
		_plan_box = _plan_box.expand(q)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for j in range(0, pts.size() - 1, 2):
		im.surface_add_vertex(pts[j])
		im.surface_add_vertex(pts[j + 1])
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.75, 0.4, 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	_root.add_child(mi)


func _draw_trail() -> void:
	if _trail_pts.size() < 2:
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for q in _trail_pts:
		im.surface_add_vertex(q)
	im.surface_end()
	_trail.mesh = im


var _shown := -1


func _show_step(s: Dictionary) -> void:
	if _shown == _si:
		return
	_shown = _si
	var leg: String = s.leg
	var title := tr("TR_" + str(s.kind).to_upper())
	if leg != "":
		title = tr("LEG_" + leg)
	_label.text = title
	var dv := 0.0
	for lg: Dictionary in level.get("legs", []):
		if lg.key == leg:
			dv = float(lg.dv)
	if s.kind == "short":
		_sub.text = tr("TR_SHORT") % [Game.fmt(dv / 1000.0, 2), Game.fmt(maxf(dv - _left_before(leg), 0.0) / 1000.0, 2)]
	elif dv > 0.0:
		_sub.text = "Δv %s km/s · %s" % [Game.fmt(dv / 1000.0, 2), _days(leg)]
	else:
		_sub.text = ""


func _left_before(leg: String) -> float:
	var left := leftover
	for lg: Dictionary in level.get("legs", []):
		if lg.key == leg:
			return left
		left -= float(lg.dv)
	return left


func _days(leg: String) -> String:
	for lg: Dictionary in level.get("legs", []):
		if lg.key == leg:
			var d := float(lg.days)
			if d < 1.0:
				return tr("TR_HOURS") % Game.fmt(d * 24.0, 0)
			if d > 400.0:
				return tr("TR_YEARS") % Game.fmt(d / 365.0, 1)
			return tr("TR_DAYS") % Game.fmt(d, 0)
	return ""


func _announce(s: Dictionary) -> void:
	say.emit(str(s.kind), str(s.leg))


func start() -> void:
	if not _steps.is_empty():
		_announce(_steps[0])


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()


## Cuántos tramos se lograron (para el informe).
func reached() -> int:
	return _reached
