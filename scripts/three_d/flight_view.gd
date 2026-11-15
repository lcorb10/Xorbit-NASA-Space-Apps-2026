extends Control
## Lanzamiento: el cohete sale del hangar en la oruga, cuenta regresiva con las voces de
## control, encendido, despegue y vuelo reproducido desde FlightSim (la física ya calculada).
## Cámaras: torre, seguimiento desde tierra y persecución (C cambia; arrastrar gira; rueda acerca).
## Tierra curva con atmósfera, cielo que se oscurece, etapas que caen, informe al final.

enum Phase { ROLLOUT, COUNTDOWN, FLIGHT, TRANSFER, OPS, REPORT }

const ROLLOUT_S := 14.0
const COUNTDOWN_S := 10.0
const RE := FlightSim.RE
const FLOAT_ORIGIN_ALT := 25000.0

var analysis: Dictionary
var design: Array
var level := 0
var _reentered := false
var _science := 0.0
var _cabin: CabinView
var _transfer: TransferView
var _skip_phase: Button
var _skip_result: Button
var _pause: ColorRect
# Tripulación (docs/TRIPULACION.md): retos en la cabina (misión tripulada) o en la Sala de Control
var _crew: CrewView
var _crew_mission: CrewMission
var _crew_busy := false
var _crew_after: Callable ## qué sigue cuando termina la fase de la tripulación (viaje, aterrizaje)
var _crew_done := {} ## fases ya jugadas
var _pip: SubViewportContainer
var _pip_cam: Camera3D
var _pip_vp: SubViewport
var _lobby: CrewLobby
var _crew_hidden: Array = [] ## partes del HUD del vuelo ocultas durante un reto
const CREW_SLOWMO := 0.1
const CREWED_MISSIONS := [4]
const CREW_MISTAKE := 50.0 ## un paso con menos puntos es un error
var _crew_mistakes := 0
var _crew_failed := false
var _shake_t := 0.0 ## turbulencia por un error ## misiones tripuladas por historia (alunizaje con astronautas)
var _flowlog := "--flowlog" in OS.get_cmdline_user_args()
var _last_logged := -1
var _ops: OpsView
var _ops_done := false
var _paused := false
var sandbox := false
var sim: Dictionary

var _phase := Phase.ROLLOUT
var _phase_t := 0.0
var _pt := 0.0 # tiempo de vuelo simulado que se está mostrando
var _warp := 1.0
var _auto_warp := true
var _next_event := 0
var _said := {}

# Escena 3D
var _vp: SubViewport
var _scene: Node3D # raíz del mundo 3D (la cámara y el cohete cuelgan de aquí)
var _ground: Node3D # hangar, terreno, plataforma, Tierra: se desplaza con el origen flotante
var _world: HangarWorld
var _cam: Camera3D
var _rocket: Node3D
var _stages: Array[Node3D] = [] # índice 0 = etapa 1 (la de abajo)
var _stage_bottom: Array[float] = []
var _plumes: Array[MeshInstance3D] = []
var _crawler: Crawler
var _last_z := 0.0
var _pitch_s := 0.0 # inclinación suavizada de la oruga
var _smoke: GPUParticles3D
var _pad_smoke: GPUParticles3D
var _drops: Array = [] # etapas soltadas: {node, pos(PackedFloat64), vel, spin, t}
var _origin := PackedFloat64Array([0.0, 0.0, 0.0]) # origen flotante (coordenadas reales)
var _floating := false
var _rocket_real := PackedFloat64Array([0.0, 0.0, 0.0])
var _exploded := false
var _debris: Array = []
var _base := Vector3.ZERO # base del cohete en la plataforma
var _center := Vector3.ZERO # centro de la Tierra (coordenadas reales)
var _earth_mat: ShaderMaterial
var _shake := 0.0 # temblor de cámara por explosiones (se apaga solo)
var _engine_snd: AudioStreamPlayer
var _crawler_snd: AudioStreamPlayer # motor del crawler durante el traslado
var _roar: AudioStreamPlayer # estruendo del despegue (grabación de la NASA)
var _pa: AudioStreamPlayer # altavoces de la plataforma: cuenta regresiva real del Apolo 11
var _since_boom := 0.0 # segundos desde la explosión (el informe espera a que se vea)
var _impacts := 0 # explosiones chicas de restos que caen (con tope, por rendimiento)
const SITE_LAT := 28.5 # Cabo Cañaveral: la plataforma 39A está ahí
const SITE_LON := -80.6

# Cámara
var _cam_mode := 0 # 0 torre/seguimiento, 1 persecución, 2 lateral
var _yaw := 0.6
var _pitch := 0.15
var _zoom := 1.0
var _dragging := false
var _local_shown := true
var _cam_touched := false ## el jugador giró la cámara: no se mueve sola

# Interfaz
var comms: CommsBar
var _hud: CanvasLayer
var _telemetry: Label
var _countdown: Label
var _chart: TrajectoryChart
var _warp_buttons := {}
var _report: Control
var _comms_data := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var f: Dictionary = Game.flight
	design = f.get("design", [])
	analysis = f.get("analysis", {})
	level = int(f.get("level", 0))
	sandbox = bool(f.get("sandbox", false))
	sim = FlightSim.simulate(analysis, level, sandbox)
	var cf := FileAccess.open("res://data/comms.json", FileAccess.READ)
	_comms_data = JSON.parse_string(cf.get_as_text()) if cf else {}

	var box := SubViewportContainer.new()
	box.stretch = true
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(_on_view_input)
	add_child(box)
	_vp = SubViewport.new()
	_vp.msaa_3d = Viewport.MSAA_4X
	if str(Game.settings.get("quality", "high")) == "high":
		_vp.use_taa = true # suavizado temporal: menos parpadeo en celosías, pasto y bordes finos
	_vp.own_world_3d = true
	box.add_child(_vp)
	_scene = Node3D.new()
	_vp.add_child(_scene)
	_ground = Node3D.new()
	_scene.add_child(_ground)
	_world = HangarWorld.new()
	_world.build(_ground)
	_base = Vector3(0, HangarWorld.PAD_TOP, HangarWorld.PAD_Z)
	_center = _base - Vector3(0, RE, 0)
	_build_earth()
	_build_rocket()
	_build_effects()
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.near = 0.3
	_cam.far = 5.0e6
	_scene.add_child(_cam)

	comms = CommsBar.new()
	add_child(comms)
	_build_hud()
	if Game.landtest != "":
		analysis["probe"] = {"gear_missing": ["legs"] if Game.landtest.ends_with("nolegs") else []}
		_start_landing.call_deferred(Game.landtest.begins_with("mars"), true)
	_say("rollout")
	var args := OS.get_cmdline_user_args()
	if _crew_enabled() and Game.crew_setup.is_empty() and not "--crewai" in args and not "--nolobby" in args and Game.landtest == "":
		_lobby = CrewLobby.new()
		_lobby.theme = Game.theme
		_hud.get_child(0).add_child(_lobby)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fltime="):
			_crawler.position = Vector3(0, HangarWorld.PAD_SURFACE, HangarWorld.PAD_Z)
			_phase = Phase.FLIGHT
			_pt = float(arg.trim_prefix("--fltime="))
			if is_instance_valid(_lobby):
				_lobby._start() # prueba: sin sala
			_auto_warp = false
			_set_warp(1.0)
			_said["tower"] = true
			while _next_event < sim.events.size() and float(sim.events[_next_event].t) <= _pt:
				if sim.events[_next_event].key == "separation":
					_drop_stage(int(sim.events[_next_event].stage) - 1)
				_next_event += 1
		if arg == "--pause":
			_toggle_pause.call_deferred()
		if arg == "--report": # grabaciones: ir directo al informe
			get_tree().create_timer(1.5).timeout.connect(_show_report)
			get_tree().create_timer(6.0).timeout.connect(_show_report)
		if arg == "--pauseset":
			_toggle_pause.call_deferred()
			_open_settings.call_deferred()
		if arg.begins_with("--flcam="):
			_cam_mode = int(arg.trim_prefix("--flcam="))
			_set_cabin.call_deferred(_cam_mode == 3)


# ---------- Construcción ----------

func _build_rocket() -> void:
	RenderingServer.global_shader_parameter_set("xorbit_cut", 0.0)
	var built := RocketBuilder.build(design, analysis)
	_rocket = Node3D.new()
	_scene.add_child(_rocket)
	# Agrupar las piezas por etapa (cada etapa se puede soltar)
	var stages: Array = analysis.get("stages", [])
	var height := float(analysis.get("height", 0.0))
	for si in stages.size():
		var g := Node3D.new()
		g.name = "Stage_%d" % (si + 1)
		_rocket.add_child(g)
		_stages.append(g)
		var bottom_info: Dictionary = analysis.parts[int(stages[si].bottom)]
		_stage_bottom.append(height - (float(bottom_info.y) + float(bottom_info.length)))
	for part in built.get_children():
		var idx := int(part.get_meta("index", -1))
		var target := 0
		for si in stages.size():
			if idx >= int(stages[si].top) and idx <= int(stages[si].bottom):
				target = si
		var xf: Transform3D = part.transform
		built.remove_child(part)
		_stages[target].add_child(part)
		part.transform = xf
		for body in part.find_children("*", "StaticBody3D", true, false):
			body.queue_free()
	built.free()
	# Llamas: una por etapa, debajo de su pieza más baja
	for si in _stages.size():
		var plume := _make_plume(si)
		plume.set_meta("plume", true)
		plume.position.y = _stage_bottom[si]
		_stages[si].add_child(plume)
		plume.visible = false
		_plumes.append(plume)
	# Oruga transportadora con su mesa de lanzamiento: lleva el cohete y se queda en la plataforma
	_crawler = Crawler.new()
	_crawler.build(_world, float(analysis.get("max_d", 1.0)))
	_ground.add_child(_crawler)
	_crawler.position = Vector3(0, 0, 0)


func _make_plume(si: int) -> MeshInstance3D:
	var st: Dictionary = analysis.stages[si]
	var r := 0.5
	var solid := false
	var hydrogen := false
	for i in range(int(st.top), int(st.bottom) + 1):
		var p: Dictionary = design[i]
		r = maxf(r, float(p.get("diameter", 1.0)) * 0.45)
		var kind: String = Catalog.parts[p.id].kind
		if kind == "solid":
			solid = true
		if kind == "tank" and p.get("propellant", "") == "lox_lh2":
			hydrogen = true
	# Llama con shader (assets/shaders/plume.gdshader): dos conos, uno exterior turbulento
	# y uno interior más corto y brillante. Color según el propelente.
	var c := Color(1.0, 0.5, 0.16) # queroseno: naranja con hollín
	var energy := 3.2
	if solid:
		c = Color(1.0, 0.78, 0.45) # sólido: amarillo blanco, muy brillante
		energy = 4.5
	elif hydrogen:
		c = Color(0.45, 0.6, 1.0) # hidrógeno: casi invisible, azulado
		energy = 1.4
	var holder := MeshInstance3D.new() # nodo intermedio para escalar desde la tobera
	for layer in 2:
		var m := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = r * (0.75 if layer == 0 else 0.45)
		cone.bottom_radius = r * (1.6 if layer == 0 else 0.7)
		cone.height = r * (10.0 if layer == 0 else 4.5)
		cone.radial_segments = 32
		cone.rings = 8
		cone.cap_top = false
		cone.cap_bottom = false
		m.mesh = cone
		var mat := ShaderMaterial.new()
		mat.shader = _plume_shader()
		mat.set_shader_parameter("color", c)
		mat.set_shader_parameter("energy", energy * (1.0 if layer == 0 else 0.8))
		mat.set_shader_parameter("noise_tex", _plume_noise())
		mat.set_shader_parameter("seed", randf() * 10.0)
		m.material_override = mat
		m.position.y = -cone.height / 2.0
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(m)
	# Luz de la llama: ilumina el humo, la plataforma y el propio cohete
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.3) if not hydrogen else Color(0.7, 0.75, 1.0)
	light.light_energy = 8.0 if not hydrogen else 2.0
	light.omni_range = r * 40.0
	light.position.y = -r * 2.0
	light.shadow_enabled = false
	light.name = "Glow"
	holder.add_child(light)
	return holder


static var _plume_sh: Shader
static var _plume_tex: Texture2D


static func _plume_shader() -> Shader:
	if _plume_sh == null:
		_plume_sh = load("res://assets/shaders/plume.gdshader")
	return _plume_sh


static func _plume_noise() -> Texture2D:
	if _plume_tex == null:
		var n := FastNoiseLite.new()
		n.frequency = 0.04
		n.fractal_octaves = 4
		var t := NoiseTexture2D.new()
		t.width = 256
		t.height = 256
		t.seamless = true
		t.noise = n
		_plume_tex = t
	return _plume_tex


func _build_effects() -> void:
	_smoke = _make_smoke(900, 16.0, 4.0, Color(0.92, 0.92, 0.9, 0.55))
	_ground.add_child(_smoke)
	_smoke.emitting = false
	_pad_smoke = _make_smoke(400, 9.0, 9.0, Color(0.95, 0.95, 0.93, 0.7))
	_pad_smoke.one_shot = true
	_pad_smoke.explosiveness = 0.6
	var pm := _pad_smoke.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0, 0.15, 1)
	pm.spread = 80.0
	pm.initial_velocity_min = 18.0
	pm.initial_velocity_max = 40.0
	_pad_smoke.position = _base
	_pad_smoke.emitting = false
	_ground.add_child(_pad_smoke)


func _make_smoke(amount: int, life: float, size: float, color: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-4000, -4000, -4000), Vector3(8000, 8000, 8000))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 14.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 14.0
	pm.gravity = Vector3(0, 0.6, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = size * 0.6
	pm.scale_max = size
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 3.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, color)
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_texture = Explosion.smoke_sprite(amount)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -12.0
	pm.angular_velocity_max = 12.0
	mat.billboard_keep_scale = true
	quad.material = mat
	p.draw_pass_1 = quad
	return p


func _build_earth() -> void:
	# Tierra con las fotos de la NASA (Blue Marble de día, luces de ciudades de noche),
	# girada para que la plataforma quede en Cabo Cañaveral y el cohete salga hacia el este.
	var earth := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = RE
	sph.height = RE * 2.0
	sph.radial_segments = 384
	sph.rings = 192
	earth.mesh = sph
	var sun_dir := _world.sun.transform.basis.z # hacia el Sol
	_earth_mat = ShaderMaterial.new()
	_earth_mat.shader = load("res://assets/shaders/earth.gdshader")
	_earth_mat.set_shader_parameter("day_tex", load("res://assets/textures/nasa/earth_day.jpg"))
	_earth_mat.set_shader_parameter("night_tex", load("res://assets/textures/nasa/earth_night.jpg"))
	_earth_mat.set_shader_parameter("cloud_tex", load("res://assets/textures/generated/earth_clouds.png"))
	_earth_mat.set_shader_parameter("sun_dir", sun_dir)
	earth.material_override = _earth_mat
	earth.position = _center - Vector3(0, 2.0, 0) # un poco por debajo del terreno local
	earth.basis = site_basis(SITE_LAT, SITE_LON)
	earth.name = "Earth"
	_ground.add_child(earth)
	# Atmósfera: borde azul del lado de día, naranja en el terminador, nada de noche
	var halo := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = RE + 70000.0
	hs.height = (RE + 70000.0) * 2.0
	hs.radial_segments = 192
	hs.rings = 96
	halo.mesh = hs
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never;
uniform vec3 sun_dir;
uniform vec3 center; // centro de la Tierra en el mundo (cambia con el origen flotante)
uniform float radius = 6371000.0;
void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 rd = normalize(wp - cam);
	// Punto del rayo más cercano a la Tierra: cuanto más bajo pasa, más aire atraviesa
	float tca = max(dot(center - cam, rd), 0.0);
	vec3 closest = cam + rd * tca;
	float h = max(length(closest - center) - radius, 0.0);
	float dens = exp(-h / 9000.0);
	// Si el rayo choca con la Tierra (mirando hacia abajo) solo hay una bruma fina: así se ven
	// el mar, la tierra verde y las nubes; el azul fuerte queda solo en el borde (el limbo)
	if (length(closest - center) < radius) {
		float edge = smoothstep(radius * 0.985, radius, length(closest - center));
		dens = mix(0.08, 1.0, edge * edge);
	}
	float l = dot(normalize(closest - center), normalize(sun_dir));
	vec3 c = mix(vec3(1.0, 0.42, 0.12), vec3(0.3, 0.55, 1.0), smoothstep(-0.05, 0.3, l));
	ALBEDO = c * dens * 1.4 * smoothstep(-0.3, 0.12, l);
}
"""
	var smat := ShaderMaterial.new()
	smat.shader = sh
	smat.set_shader_parameter("sun_dir", sun_dir)
	halo.material_override = smat
	halo.position = _center
	halo.name = "Halo"
	halo.visible = false
	_ground.add_child(halo)
	# Rugido de los motores
	# Sonidos reales de la NASA (dominio público): motores del Saturno V en bucle,
	# estruendo del despegue del transbordador y la cuenta regresiva del Apolo 11.
	_engine_snd = AudioStreamPlayer.new()
	var eng := load("res://assets/audio/nasa/engine_loop.ogg") as AudioStreamOggVorbis
	eng.loop = true
	_engine_snd.stream = eng
	_engine_snd.volume_db = -80.0
	add_child(_engine_snd)
	# Traslado: el crawler retumba y chirría (grabación de la NASA de un estruendo lejano, más grave)
	_crawler_snd = AudioStreamPlayer.new()
	var rum := load("res://assets/audio/nasa/far_rumble.ogg") as AudioStreamOggVorbis
	rum.loop = true
	_crawler_snd.stream = rum
	_crawler_snd.pitch_scale = 0.6
	_crawler_snd.volume_db = -10.0
	add_child(_crawler_snd)
	_roar = AudioStreamPlayer.new()
	_roar.stream = load("res://assets/audio/nasa/liftoff_roar.ogg")
	add_child(_roar)
	_pa = AudioStreamPlayer.new()
	_pa.stream = load("res://assets/audio/nasa/apollo11_liftoff.ogg")
	_pa.volume_db = -17.0
	add_child(_pa)


## Orientación de la esfera de la Tierra para que el punto (lat, lon) quede arriba (+y),
## el este hacia +z (la dirección del vuelo) y el norte hacia +x.
static func site_basis(lat_deg: float, lon_deg: float) -> Basis:
	var la := deg_to_rad(lat_deg)
	var a := (lon_deg + 180.0) / 360.0 * TAU # en SphereMesh, la coordenada u va a (sin(u·TAU), y, cos(u·TAU))
	var up := Vector3(cos(la) * sin(a), sin(la), cos(la) * cos(a))
	var east := Vector3(cos(a), 0.0, -sin(a))
	var north := Vector3(-sin(la) * sin(a), cos(la), -sin(la) * cos(a))
	return Basis(north, up, east).transposed()


# ---------- HUD ----------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 20
	add_child(_hud)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Game.theme
	_hud.add_child(root)
	# Telemetría arriba a la izquierda
	var tel := PanelContainer.new()
	tel.add_theme_stylebox_override("panel", Game._box(Color(0.02, 0.05, 0.09, 0.72), 1, Game.LINE, Vector4(18, 14, 18, 14)))
	tel.position = Vector2(28, 28)
	tel.custom_minimum_size = Vector2(330, 0)
	root.add_child(tel)
	_telemetry = Label.new()
	_telemetry.add_theme_font_override("font", Game.font_mono_medium)
	_telemetry.add_theme_font_size_override("font_size", 16)
	_telemetry.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	tel.add_child(_telemetry)
	# Trayectoria arriba a la derecha
	_chart = TrajectoryChart.new()
	_chart.sim = sim
	_chart.anchor_left = 1.0
	_chart.anchor_right = 1.0
	_chart.offset_left = -440
	_chart.offset_right = -28
	_chart.offset_top = 28
	_chart.offset_bottom = 268
	root.add_child(_chart)
	# Cuenta regresiva en el centro
	_countdown = Label.new()
	_countdown.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_countdown.offset_top = 90
	_countdown.offset_left = -200
	_countdown.offset_right = 200
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.add_theme_font_override("font", Game.font_display)
	_countdown.add_theme_font_size_override("font_size", 96)
	_countdown.add_theme_color_override("font_color", Color(1, 1, 1))
	_countdown.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_countdown.add_theme_constant_override("outline_size", 10)
	_countdown.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	root.add_child(_countdown)
	# Controles en dos grupos (zonas de HUD): abajo a la izquierda la velocidad del tiempo;
	# abajo a la derecha la vista y saltar, creciendo desde el borde para no salirse de la pantalla
	var warp_box := HBoxContainer.new()
	warp_box.anchor_top = 1.0
	warp_box.anchor_bottom = 1.0
	warp_box.offset_left = 28
	warp_box.offset_top = -66
	warp_box.offset_bottom = -28
	warp_box.add_theme_constant_override("separation", 6)
	root.add_child(warp_box)
	var ctl := HBoxContainer.new()
	ctl.anchor_left = 1.0
	ctl.anchor_right = 1.0
	ctl.anchor_top = 1.0
	ctl.anchor_bottom = 1.0
	ctl.offset_right = -28
	ctl.offset_top = -66
	ctl.offset_bottom = -28
	ctl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ctl.add_theme_constant_override("separation", 6)
	root.add_child(ctl)
	var lbl := Label.new()
	lbl.text = "FL_WARP"
	lbl.theme_type_variation = "Eyebrow"
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	warp_box.add_child(lbl)
	for w in [1, 5, 20, 100]:
		var b := Button.new()
		b.text = "%d×" % w
		b.theme_type_variation = &"Hud"
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(52, 38)
		var wv: float = w
		b.pressed.connect(func() -> void:
			_auto_warp = false
			_set_warp(wv))
		warp_box.add_child(b)
		_warp_buttons[w] = b
	var cabin_b := Button.new()
	cabin_b.text = "FL_CABIN"
	cabin_b.toggle_mode = true
	cabin_b.custom_minimum_size = Vector2(0, 38)
	cabin_b.theme_type_variation = &"Hud"
	cabin_b.toggled.connect(func(on: bool) -> void:
		_cam_mode = 3 if on else 1
		_set_cabin(on))
	ctl.add_child(cabin_b)
	var cam := Button.new()
	cam.text = "FL_CAM"
	cam.custom_minimum_size = Vector2(0, 38)
	cam.theme_type_variation = &"Hud"
	cam.pressed.connect(_cycle_cam)
	ctl.add_child(cam)
	# Saltar el traslado y la cuenta regresiva (se ve solo antes del despegue)
	_skip_phase = Button.new()
	_skip_phase.text = "FL_SKIP_PHASE"
	_skip_phase.custom_minimum_size = Vector2(0, 38)
	_skip_phase.theme_type_variation = &"Hud"
	_skip_phase.pressed.connect(_skip_to_launch)
	ctl.add_child(_skip_phase)
	var skip := Button.new()
	skip.text = "FL_SKIP"
	skip.custom_minimum_size = Vector2(0, 38)
	skip.theme_type_variation = &"Hud"
	skip.pressed.connect(_show_report)
	skip.visible = false # aparece al despegar (antes está "Saltar al despegue")
	_skip_result = skip
	ctl.add_child(skip)
	_set_warp(1.0)


func _set_warp(w: float) -> void:
	_warp = w
	for k in _warp_buttons:
		_warp_buttons[k].set_pressed_no_signal(int(k) == int(w))


# ---------- Bucle ----------

func _process(delta: float) -> void:
	if _paused:
		return
	if _flowlog and _phase != _last_logged:
		_last_logged = _phase
		print("FLOW t=%.1f phase=%s pt=%.0f crew_busy=%s ops=%s" % [Time.get_ticks_msec() / 1000.0, Phase.keys()[_phase], _pt, _crew_busy, _ops != null])
	_phase_t += delta
	if _exploded:
		_since_boom += delta
	match _phase:
		Phase.ROLLOUT:
			if is_instance_valid(_lobby):
				_phase_t -= delta # el traslado espera a la tripulación
			elif not _crawler_snd.playing:
				_crawler_snd.play()
			_do_rollout()
		Phase.COUNTDOWN:
			if _crew_busy:
				_phase_t -= delta # espera (hold) mientras la tripulación trabaja
			elif not _crew_done.has("countdown") and COUNTDOWN_S - _phase_t <= 9.0 and _crew_enabled():
				_crew_phase("countdown")
			_do_countdown()
		Phase.FLIGHT:
			_do_flight(delta)
		Phase.REPORT:
			_place_rocket(FlightSim.state_at(sim, _pt))
	_update_drops(delta * (_warp if _phase == Phase.FLIGHT else 1.0))
	_update_camera(delta)
	_update_sky()
	_dev_boom()
	_update_pip()
	_update_crew_screens()
	if _shake_t > 0.0:
		_shake_t -= delta
		if _cam:
			_cam.h_offset = sin(_phase_t * 41.0) * 0.4 * _shake_t
			_cam.v_offset = sin(_phase_t * 37.0 + 1.0) * 0.4 * _shake_t
		if _shake_t <= 0.0:
			if _cam:
				_cam.h_offset = 0.0
				_cam.v_offset = 0.0
			if _crew and _crew_mission:
				_crew.shake = _crew_mission.turbulence


func _do_rollout() -> void:
	var k := clampf(_phase_t / ROLLOUT_S, 0.0, 1.0)
	var left := ROLLOUT_S - _phase_t + COUNTDOWN_S
	_telemetry.text = "%s %02d:%02d\n%s" % [tr("FL_TMINUS"), int(left) / 60, int(left) % 60, tr("FL_ROLLOUT")]
	# Velocidad trapezoidal: arranca despacio, avanza parejo y frena suave al llegar
	var z := HangarWorld.PAD_Z * _trapezoid(k, 0.18, 0.25)
	# La oruga se apoya en sus trenes delantero y trasero (≈36 m entre ejes): la inclinación
	# sale de la diferencia de altura entre los dos, así entra y sale de la rampa sin saltos.
	var half := 18.0
	var front := Crawler.ground_at(z + half).x
	var back := Crawler.ground_at(z - half).x
	var pitch := atan2(front - back, half * 2.0)
	_pitch_s = lerpf(_pitch_s, pitch, clampf(get_process_delta_time() * 3.0, 0.0, 1.0)) # la suspensión amortigua
	var bob := sin(_phase_t * 9.0) * 0.015 * clampf((z - _last_z) * 30.0, 0.0, 1.0) # traqueteo de las orugas
	_crawler.position = Vector3(0, (front + back) * 0.5 + bob, z)
	_crawler.rotation.x = -_pitch_s
	_crawler.roll(z - _last_z)
	_last_z = z
	# Como la oruga real de la NASA, la mesa se nivela con gatos hidráulicos: el cohete sigue vertical
	var deck := _crawler.transform * Vector3(0, HangarWorld.DECK_H, 0)
	_rocket.position = deck
	_rocket.basis = Basis.IDENTITY
	if k >= 1.0:
		_crawler.position = Vector3(0, HangarWorld.PAD_SURFACE, HangarWorld.PAD_Z)
		_crawler.rotation = Vector3.ZERO
		_rocket.position = _base
		_phase = Phase.COUNTDOWN
		_phase_t = COUNTDOWN_S if _skip_after_rollout else 0.0
		if not _skip_after_rollout:
			_say("on_pad")


## Avance 0..1 con aceleración al principio (a) y frenado al final (d), velocidad pareja en medio.
static func _trapezoid(k: float, a: float, d: float) -> float:
	var vmax := 1.0 / (1.0 - a * 0.5 - d * 0.5)
	if k < a:
		return 0.5 * vmax * k * k / a
	if k > 1.0 - d:
		var r := 1.0 - k
		return 1.0 - 0.5 * vmax * r * r / d
	return 0.5 * vmax * a + vmax * (k - a)


func _do_countdown() -> void:
	var left := COUNTDOWN_S - _phase_t
	if left <= 8.4 and not _pa.playing and not _said.has("pa"):
		_said["pa"] = true
		_pa.play()
	if _phase_t > 1.0 and not _said.has("poll") and not _pa.playing:
		_say("poll")
	_countdown.text = "%s%d" % [tr("FL_TMINUS"), int(ceil(left))] if left > 0.0 else ""
	_telemetry.text = "%s 00:%02d\n%s" % [tr("FL_TMINUS"), int(ceil(maxf(left, 0.0))), tr("FL_ON_PAD")]
	if left < 3.0 and not _said.has("ignition"):
		_say("ignition")
		_plumes[0].visible = float(analysis.stages[0].mdot) > 0.0
		_pad_smoke.restart()
		_pad_smoke.emitting = true
	if left <= 0.0 and not _crew_failed:
		_phase = Phase.FLIGHT
		_phase_t = 0.0
		_pt = 0.0
		if float(analysis.stages[0].f_sl) < float(analysis.stages[0].m0) * FlightSim.G0:
			_say("pad_fail")
		else:
			_say("liftoff")
			_roar.play()


## Cono de vapor en el máximo de presión del aire: cerca de Mach 1 la presión baja de golpe
## detrás de la onda de choque y la humedad del aire se condensa en una nube blanca alrededor del cohete.
func _vapor_cone() -> void:
	if _rocket == null or _exploded:
		return
	var d := maxf(float(analysis.get("max_d", 1.0)), 0.5)
	var h := float(analysis.get("height", 20.0))
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = d * 0.55
	c.bottom_radius = d * 1.9
	c.height = d * 2.2
	c.cap_top = false
	c.cap_bottom = false
	c.radial_segments = 32
	m.mesh = c
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1, 1, 1, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.35, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	mat.albedo_texture = gt
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position.y = h * 0.62
	_rocket.add_child(m)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.75, 0.6)
	tw.tween_interval(2.2)
	tw.tween_property(mat, "albedo_color:a", 0.0, 1.4)
	tw.tween_callback(m.queue_free)


## Salta el traslado y la cuenta regresiva: el cohete queda en la plataforma y despega ya.
func _skip_to_launch() -> void:
	_said["pa"] = true
	comms.clear()
	comms.skip()
	if _pa:
		_pa.stop()
	if _phase == Phase.ROLLOUT:
		_phase_t = ROLLOUT_S # el próximo cuadro termina el traslado
		_skip_after_rollout = true
	elif _phase == Phase.COUNTDOWN:
		_phase_t = COUNTDOWN_S


var _skip_after_rollout := false


func _do_flight(delta: float) -> void:
	if _skip_phase and _skip_phase.visible:
		_skip_phase.visible = false
		_skip_result.visible = true
	# Velocidad automática: real al despegar, rápida en el ascenso, lenta en los eventos
	if _auto_warp:
		var w := 1.0
		if _pt > 25.0:
			w = 5.0
		if _pt > 200.0:
			w = 20.0
		for e in sim.events:
			if e.key in ["separation", "orbit", "tumble", "karman"] and absf(float(e.t) - _pt) < 3.0:
				w = 1.0
		_set_warp(w)
	# Mientras Houston está hablando el tiempo corre a 1x: si no, la voz se queda atrás de los eventos
	var eff_warp := 1.0 if (comms != null and comms.busy) else _warp
	if _crew_busy:
		eff_warp = CREW_SLOWMO
	elif _crew_enabled() and not _exploded:
		if not _crew_done.has("ascent") and _pt > 15.0:
			_crew_phase("ascent")
		elif not _crew_done.has("maxq") and float(sim.get("max_q_t", 0.0)) > 1.0 and _pt > float(sim.max_q_t) - 2.0:
			_crew_phase("maxq", 0.6)
		elif not _crew_done.has("separation") and _first_sep_t() > 0.0 and _pt > _first_sep_t() - 0.5:
			_crew_phase("separation", 0.5)
	_pt = minf(_pt + delta * eff_warp, float(sim.duration))
	# Comentarios de radio
	while _next_event < sim.events.size() and float(sim.events[_next_event].t) <= _pt:
		var ev: Dictionary = sim.events[_next_event]
		_on_event(ev)
		_next_event += 1
	var s := FlightSim.state_at(sim, _pt)
	if not _said.has("tower") and float(s.get("y", 0.0)) > 150.0 and not _exploded:
		_say("tower")
	_place_rocket(s)
	_telemetry.text = _telemetry_text(s)
	_chart.t = _pt
	_chart.queue_redraw()
	if _pt >= float(sim.duration) and _phase_t > 1.0 and (not _exploded or _since_boom > 5.0) and not _crew_busy:
		if _wants_transfer():
			_start_transfer()
		else:
			_show_report()


## Escena del aterrizaje en la Luna o en Marte (LandingView). El resultado depende del equipo
## (patas, escudo térmico, paracaídas) y de si quedó Δv para el último tramo.
func _start_landing(mars: bool, fuel_ok: bool) -> void:
	var lv := LandingView.new()
	lv.body = "mars" if mars else "moon"
	lv.fuel_ok = fuel_ok
	lv.gear_missing = analysis.get("probe", {}).get("gear_missing", [])
	lv.walk_enabled = not mars and (level in CREWED_MISSIONS or bool(analysis.get("probe", {}).get("crew", false)))
	lv.theme = Game.theme
	for c in _hud.get_children():
		if c is Control:
			c.visible = false
	_hud.add_child(lv)
	_hud.move_child(lv, 0)
	lv.say.connect(func(key: String) -> void:
		var e: Dictionary = _comms_data.get("landing", {}).get(key, {})
		if not e.is_empty():
			comms.clear()
			comms.skip()
			comms.say(e, "HOUSTON"))
	lv.finished.connect(func(ok: bool) -> void:
		if not ok:
			sim["success"] = false
			sim["reason"] = "FAIL_GEAR" if not lv.gear_missing.is_empty() else "FAIL_TRANSFER"
			sim["legs_reached"] = mini(int(sim.get("legs_reached", 0)), (Game.level(level).get("legs", []) as Array).size() - 1)
		_fade_then(func() -> void:
			_hud.remove_child(lv)
			lv.queue_free()
			for c in _hud.get_children():
				if c is Control:
					c.visible = true
			_show_report()))


## Misiones más allá de la órbita baja: el viaje se ve en el mapa (TransferView).
func _wants_transfer() -> bool:
	var lv := Game.level(level) if level >= 0 else {}
	return bool(sim.get("orbit", false)) and not _exploded and str(lv.get("view", "")) != ""


func _start_transfer() -> void:
	if _phase != Phase.FLIGHT:
		return
	_phase = Phase.TRANSFER
	comms.clear()
	# El viaje y el descenso van a su propio ritmo: la velocidad del vuelo vuelve a 1x
	_auto_warp = true
	_set_warp(1.0)
	# Antes del viaje, la tripulación hace el encendido de transferencia (apuntar, empujar, pasar a la DSN);
	# su nota mueve el Δv que llega al viaje (_crew_dv_factor)
	_crew_then("transfer", func() -> void: _fade_then(_begin_transfer))


## Fundido a negro entre escenas (vuelo → mapa → descenso → informe): f se llama con la pantalla negra.
func _fade_then(f: Callable, t := 0.6) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, 0)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(r)
	var tw := create_tween()
	tw.tween_property(r, "color:a", 1.0, t).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(f)
	tw.tween_interval(0.25)
	tw.tween_property(r, "color:a", 0.0, t * 1.4).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(layer.queue_free)


func _begin_transfer() -> void:
	_transfer = TransferView.new()
	_transfer.level = Game.level(level)
	_transfer.leftover = float(sim.get("leftover_dv", 0.0)) * _crew_dv_factor()
	_transfer.theme = Game.theme
	_hud.add_child(_transfer)
	_hud.move_child(_transfer, 0)
	for c in _hud.get_children():
		if c != _transfer and c is Control and c != comms:
			c.visible = false
	_transfer.say.connect(func(kind: String, leg: String) -> void:
		var tpl: Dictionary = _comms_data.get("transfer", {}).get(kind, {})
		if tpl.is_empty():
			return
		comms.clear() # cada maniobra se narra al momento, sin cola atrasada
		comms.skip()
		# Línea ya armada para ese tramo (tiene su audio: tr_<maniobra>_<tramo>); si no, se arma el texto
		var full: Dictionary = _comms_data.get("transfer_legs", {}).get("tr_%s_%s" % [kind, leg], {})
		if not full.is_empty():
			comms.say(full, "HOUSTON")
			return
		var leg_name := tr("LEG_" + leg) if leg != "" else ""
		comms.say({"id": str(tpl.get("id", "")), "en": str(tpl.en).replace("{leg}", leg_name), "es": str(tpl.es).replace("{leg}", leg_name)}, "HOUSTON"))
	_transfer.finished.connect(func() -> void:
		sim["legs_reached"] = _transfer.reached()
		if _flowlog:
			print("FLOW transfer reached ", _transfer.reached(), " leftover ", int(_transfer.leftover))
		_hud.remove_child(_transfer)
		_transfer.queue_free()
		var legs: Array = Game.level(level).get("legs", [])
		var land_leg := not legs.is_empty() and str(legs[-1].key) in ["land_moon", "edl_mars"]
		# Aterrizaje: si la nave llegó hasta el tramo de bajar, se ve en la superficie
		if land_leg and _transfer.reached() >= legs.size() - 1:
			var mars := str(legs[-1].key) == "edl_mars"
			var ok := _transfer.reached() >= legs.size()
			# De la órbita se pasa directo al descenso (sin reto de tripulación en medio: cortaba la escena)
			_fade_then(func() -> void: _start_landing(mars, ok))
			return
		for c in _hud.get_children():
			if c is Control:
				c.visible = true
		_show_report())
	_transfer.start()



func _on_event(ev: Dictionary) -> void:
	match ev.key:
		"liftoff":
			pass
		"max_q":
			_say("max_q")
			_vapor_cone()
		"cutoff":
			_say("cutoff")
		"separation":
			_say("separation")
			_drop_stage(int(ev.stage) - 1)
		"ignition_upper":
			_say("ignition_upper")
		"karman":
			_say("karman")
		"cutoff_last":
			_say("cutoff_last")
		"orbit":
			_say("orbit")
		"impact":
			if float(sim.apogee) >= 100000.0 or _reentered:
				# Volvió del espacio: la cápsula cae al mar con paracaídas (no es un choque)
				_say("splashdown")
				_rocket.visible = false
			else:
				_say("impact")
				_explode(true)
		"breakup":
			_say("breakup")
			_explode()
		"reentry":
			# La etapa vacía se quema al reentrar; la cápsula sigue (sin explosión: no es una falla)
			_reentered = true
			_say("reentry")
		"tumble":
			_say("tumble")
			_explode()


# ---------- Cohete en vuelo ----------

func _place_rocket(s: Dictionary) -> void:
	if s.is_empty() or _exploded:
		_update_plumes(s)
		return
	var x := float(s.x)
	var y := float(s.y)
	var th := x / RE
	var up := Vector3(0, cos(th), sin(th))
	var fwd := Vector3(0, -sin(th), cos(th))
	var tilt := float(s.get("att", s.tilt)) # actitud: empuje o dirección del movimiento
	var axis := (up * cos(tilt) + fwd * sin(tilt)).normalized()
	# Posición real (64 bits) sobre la Tierra curva
	var r := RE + y
	_rocket_real = PackedFloat64Array([_center.x, _center.y + r * cos(th), _center.z + r * sin(th)])
	if not _floating and y > FLOAT_ORIGIN_ALT:
		_floating = true
		_smoke.emitting = false
	if _floating:
		_origin = _rocket_real.duplicate()
	_ground.position = Vector3(-_origin[0], -_origin[1], -_origin[2])
	_rocket.position = Vector3(_rocket_real[0] - _origin[0], _rocket_real[1] - _origin[1], _rocket_real[2] - _origin[2])
	var bx := Vector3(1, 0, 0)
	var bz := bx.cross(axis).normalized()
	_rocket.basis = Basis(bx, axis, bz)
	# Humo: solo en el aire denso y a velocidad normal
	_smoke.emitting = bool(s.get("on", false)) and y < FLOAT_ORIGIN_ALT and _warp <= 5.0
	if _smoke.emitting:
		var si := int(s.get("stage", 0))
		_smoke.global_position = _rocket.to_global(Vector3(0, _stage_bottom[mini(si, _stage_bottom.size() - 1)] - 2.0, 0))
	_update_plumes(s)


func _update_plumes(s: Dictionary) -> void:
	var si := int(s.get("stage", 0))
	var on := bool(s.get("on", false)) and not _exploded
	if _phase == Phase.COUNTDOWN:
		on = _said.has("ignition")
		si = 0
	var y := float(s.get("y", 0.0))
	for k in _plumes.size():
		var p := _plumes[k]
		p.visible = on and k == si
		if p.visible:
			# Llama más larga y ancha al bajar la presión (en el vacío el gas se expande)
			var thin := clampf(y / 60000.0, 0.0, 1.0)
			var spread := 1.0 + clampf(y / 40000.0, 0.0, 1.0) * 2.2 # en el vacío el escape se abre mucho
			for child in p.get_children():
				if child is MeshInstance3D:
					var sm := (child as MeshInstance3D).material_override as ShaderMaterial
					sm.set_shader_parameter("alpha", lerpf(1.0, 0.4, thin))
					sm.set_shader_parameter("diamonds", 1.0 - clampf(y / 12000.0, 0.0, 1.0))
			var glow := p.get_node_or_null("Glow") as OmniLight3D
			if glow:
				glow.light_energy = (8.0 + randf_range(-1.2, 1.2)) * (1.0 - thin * 0.7)
			var flick := 1.0 + randf_range(-0.05, 0.05)
			p.scale = Vector3(spread, flick * (1.0 + thin * 1.3), spread)


func _drop_stage(index: int) -> void:
	if index < 0 or index >= _stages.size():
		return
	var g := _stages[index]
	var xf := g.global_transform
	_rocket.remove_child(g)
	_scene.add_child(g)
	g.global_transform = xf
	_plumes[index].visible = false
	var s := FlightSim.state_at(sim, _pt)
	var th := float(s.x) / RE
	var up := Vector3(0, cos(th), sin(th))
	var fwd := Vector3(0, -sin(th), cos(th))
	var vel := fwd * float(s.vx) + up * float(s.vy) - _rocket.basis.y * 3.0
	_drops.append({"node": g, "pos": PackedFloat64Array([_rocket_real[0], _rocket_real[1], _rocket_real[2]]),
		"off": g.global_position - _rocket.global_position, "vel": vel,
		"spin": Vector3(randf_range(-0.4, 0.4), randf_range(-0.2, 0.2), randf_range(-0.4, 0.4)), "t": 0.0})


func _update_drops(dt: float) -> void:
	for d in _drops:
		var n: Node3D = d.node
		var p: PackedFloat64Array = d.pos
		if not d.get("landed", false):
			d.t += dt
			var rv := Vector3(p[0] - _center.x, p[1] - _center.y, p[2] - _center.z)
			var r := rv.length()
			var dir := rv / r
			var alt := r - RE
			d.vel -= dir * 9.81 * dt
			# El aire frena los pedazos (mucho más abajo, donde es denso)
			var k: float = (0.004 if d.get("debris", false) else 0.0015) * exp(-maxf(alt, 0.0) / 8500.0)
			d.vel /= 1.0 + k * (d.vel as Vector3).length() * dt
			p[0] += d.vel.x * dt
			p[1] += d.vel.y * dt
			p[2] += d.vel.z * dt
			# Suelo: cerca de la base, el terreno; lejos, la esfera de la Tierra
			var near := Vector2(p[0] - _base.x, p[2] - _base.z).length() < 1500.0
			var ground_r := RE - (HangarWorld.PAD_TOP + 0.2 if near else 2.0)
			var nr := Vector3(p[0] - _center.x, p[1] - _center.y, p[2] - _center.z).length()
			if nr <= ground_r:
				var fix := ground_r / nr
				p[0] = _center.x + (p[0] - _center.x) * fix
				p[1] = _center.y + (p[1] - _center.y) * fix
				p[2] = _center.z + (p[2] - _center.z) * fix
				d["landed"] = true
				var speed := (d.vel as Vector3).length()
				if speed > 30.0 and _impacts < 8 and n.visible:
					_impacts += 1
					var real := Vector3(p[0], p[1], p[2])
					Explosion.spawn(_ground, real, clampf(speed / 25.0, 2.0, 8.0), false, true)
				d.vel = Vector3.ZERO
			d.pos = p
			n.rotate_x(d.spin.x * dt)
			n.rotate_z(d.spin.z * dt)
		n.position = Vector3(p[0] - _origin[0], p[1] - _origin[1], p[2] - _origin[2]) + d.off
		if not d.get("debris", false) and d.t > 40.0:
			n.visible = false


## El cohete revienta: bola de fuego (o nube de vapor en el vacío), cada pieza sale
## despedida por su lado, chamuscada y echando humo, y cae hasta el suelo.
func _explode(on_ground := false) -> void:
	if _exploded:
		return
	_exploded = true
	for pl in _plumes:
		pl.visible = false
	_smoke.emitting = false
	var s := FlightSim.state_at(sim, _pt)
	var alt := float(s.get("y", 0.0))
	var h := maxf(float(analysis.get("height", 10.0)), 3.0)
	var dmax := maxf(float(analysis.get("max_d", 1.0)), 0.5)
	var center := _rocket.global_position + _rocket.basis.y * h * (0.15 if on_ground else 0.5)
	var size := clampf(h * 0.8 + dmax * 2.0, 6.0, 120.0)
	var real := center + Vector3(_origin[0], _origin[1], _origin[2])
	Explosion.spawn(_ground, real, size, alt > 70000.0, on_ground)
	_shake = 1.0
	_zoom = maxf(_zoom, 2.2 + size / maxf(h, 3.0)) # alejar la cámara para ver la bola de fuego entera
	# Velocidad que llevaba el cohete: los pedazos la conservan
	var th := float(s.get("x", 0.0)) / RE
	var up := Vector3(0, cos(th), sin(th))
	var fwd := Vector3(0, -sin(th), cos(th))
	var v_rocket := Vector3.ZERO if on_ground else fwd * float(s.get("vx", 0.0)) + up * float(s.get("vy", 0.0))
	var charred := StandardMaterial3D.new()
	charred.albedo_color = Color(0.05, 0.04, 0.035, 0.55)
	charred.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	charred.roughness = 1.0
	var trails := 0
	for g in _stages:
		if g.get_parent() != _rocket:
			continue
		for part in g.get_children():
			if not part is Node3D or part.has_meta("plume"):
				continue
			var xf: Transform3D = part.global_transform
			g.remove_child(part)
			_scene.add_child(part)
			part.global_transform = xf
			for mi in part.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_overlay = charred
			var out: Vector3 = part.global_position - center
			out = out.normalized() if out.length() > 0.1 else Vector3(randf_range(-1, 1), 1, randf_range(-1, 1)).normalized()
			if on_ground:
				out = (out + up * 1.5).normalized()
			var speed := randf_range(10.0, 35.0) * clampf(size / 10.0, 0.7, 3.0)
			var jitter := Vector3(randf_range(-0.5, 0.5), randf_range(-0.2, 0.6), randf_range(-0.5, 0.5))
			var v := v_rocket * randf_range(0.7, 0.95) + (out + jitter).normalized() * speed
			if trails < 6 and alt < 60000.0:
				# Humo negro saliendo de los pedazos más grandes mientras caen
				trails += 1
				var trail := _make_smoke(160, 5.0, maxf(dmax * 0.6, 1.0), Color(0.12, 0.1, 0.09, 0.65))
				(trail.process_material as ParticleProcessMaterial).initial_velocity_min = 0.5
				(trail.process_material as ParticleProcessMaterial).initial_velocity_max = 2.0
				part.add_child(trail)
				trail.emitting = true
			var gp: Vector3 = part.global_position
			_drops.append({"node": part, "pos": PackedFloat64Array([gp.x + _origin[0], gp.y + _origin[1], gp.z + _origin[2]]),
				"off": Vector3.ZERO, "vel": v, "debris": true,
				"spin": Vector3(randf_range(-2.5, 2.5), randf_range(-1, 1), randf_range(-2.5, 2.5)), "t": 0.0})


# ---------- Cámara ----------

func _cycle_cam() -> void:
	_cam_mode = (_cam_mode + 1) % 4
	_set_cabin(_cam_mode == 3)


## Vista desde la cabina: la cámara exterior se pone en la punta mirando hacia adelante y su imagen
## se ve por las ventanas del interior (CabinView).
func _set_cabin(on: bool) -> void:
	if on and _cabin == null:
		_cabin = CabinView.new()
		_cabin.outside = _vp.get_texture()
		_hud.add_child(_cabin)
		_hud.move_child(_cabin, 0)
	if _cabin:
		_cabin.visible = on


func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = maxf(_zoom * 0.88, 0.25)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = minf(_zoom * 1.12, 12.0)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				_cam_touched = true
			if mb.pressed and _cam_mode == 0 and _phase == Phase.FLIGHT:
				_cam_mode = 1
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * 0.006
		_pitch = clampf(_pitch + event.relative.y * 0.005, -1.2, 1.3)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_C:
			_cycle_cam()
		elif event.keycode == KEY_ESCAPE and _phase != Phase.REPORT:
			_toggle_pause()


## Menú de pausa: el vuelo se congela mientras está abierto.
## Ajustes desde la pausa: la misma pantalla de ajustes, encima del vuelo congelado.
func _open_settings() -> void:
	var s: Control = (load("res://scripts/ui/settings.gd") as GDScript).new()
	s.set("overlay", true)
	s.theme = Game.theme
	_pause.visible = false
	_hud.add_child(s)
	s.connect("closed", func() -> void:
		_pause.visible = true
		(_pause.find_children("*", "Button", true, false)[0] as Button).grab_focus.call_deferred())


func _toggle_pause() -> void:
	if _pause == null:
		_pause = ColorRect.new()
		_pause.color = Color(Game.PAPER_DEEP, 0.72)
		_pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_pause.theme = Game.theme
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_pause.add_child(center)
		var sheet := PanelContainer.new()
		sheet.theme_type_variation = "Sheet"
		sheet.custom_minimum_size.x = 420
		center.add_child(sheet)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		sheet.add_child(v)
		var t := Label.new()
		t.text = "PA_TITLE"
		t.theme_type_variation = "Title"
		t.add_theme_font_size_override("font_size", 48)
		v.add_child(t)
		var items := [["PA_RESUME", "Primary", _toggle_pause],
			["PA_SETTINGS", "", _open_settings],
			["PA_RESTART", "", func() -> void:
				Game.goto("flight")],
			["PA_WORKSHOP", "", func() -> void:
				Game.goto("workshop")]]
		for it in items:
			var b := Button.new()
			b.text = it[0]
			if it[1] != "":
				b.theme_type_variation = it[1]
			b.custom_minimum_size.y = 44
			b.pressed.connect(it[2])
			v.add_child(b)
		_hud.add_child(_pause)
		_pause.visible = false
	_pause.visible = not _pause.visible
	_paused = _pause.visible # el vuelo se congela (ver _process); la radio también
	comms.process_mode = Node.PROCESS_MODE_DISABLED if _paused else Node.PROCESS_MODE_INHERIT
	if _pause.visible:
		(_pause.find_children("*", "Button", true, false)[0] as Button).grab_focus.call_deferred()


func _update_camera(delta: float) -> void:
	var h := maxf(float(analysis.get("height", 10.0)), 3.0)
	var target := _rocket.global_position + _rocket.basis.y * h * 0.5
	var alt := float(FlightSim.state_at(sim, _pt).get("y", 0.0)) if _phase >= Phase.FLIGHT else 0.0
	var want: Vector3
	match _phase:
		Phase.ROLLOUT:
			# Acompaña la oruga desde un costado
			want = target + Vector3(h * 1.6 + 14.0, h * 0.6 + 12.0, -h * 0.8 - 10.0)
			# Si un edificio tapa la vista (el centro de control junto al camino de la oruga), la cámara
			# se acerca hasta quedar delante del obstáculo
			var space := _cam.get_world_3d().direct_space_state
			if space:
				var q := PhysicsRayQueryParameters3D.create(target, want)
				var hit := space.intersect_ray(q)
				if not hit.is_empty():
					want = (hit.position as Vector3).lerp(target, 0.15)
		_:
			if _cam_mode == 0 and alt < 6000.0:
				# Cámara fija en el suelo, cerca de la plataforma, mirando hacia arriba
				var spot := Vector3(-60.0 - h, 3.0, HangarWorld.PAD_Z + 90.0 + h) - Vector3(_origin[0], _origin[1], _origin[2])
				want = spot
			elif _cam_mode == 2:
				want = target + _rocket.basis.x * h * 2.5 * _zoom
			else:
				var dist := h * 2.2 * _zoom + 6.0
				var b := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, -_pitch)
				var back := b * Vector3(0, 0, dist)
				# Referencia: el "arriba" local del cohete, para que la vista siga su giro
				var up := (_rocket.global_position - (_center - Vector3(_origin[0], _origin[1], _origin[2]))).normalized()
				var q := Quaternion(Vector3.UP, up)
				want = target + (Basis(q) * back)
				# Al subir (sin que el jugador haya girado la cámara): la cámara pasa adelante y arriba del
				# cohete y mira hacia atrás y abajo, así se ve la costa de Florida y la tierra verde, no solo mar
				if not _cam_touched and _phase == Phase.FLIGHT:
					var ak := smoothstep(5000.0, 16000.0, alt)
					if ak > 0.0:
						# Del lado opuesto a la plataforma: detrás del cohete queda Cabo Cañaveral y la Florida verde
						var pad := Vector3(0, HangarWorld.PAD_SURFACE, HangarWorld.PAD_Z) - Vector3(_origin[0], _origin[1], _origin[2])
						var away := target - pad
						away -= up * away.dot(up)
						if away.length() < 1.0:
							away = _rocket.basis.y - up * _rocket.basis.y.dot(up)
						var auto_pos := target + (up * 0.42 + away.normalized() * 0.9).normalized() * dist * 1.5
						want = want.lerp(auto_pos, ak)
	if _cam_mode == 3 and _phase != Phase.ROLLOUT:
		# Desde la punta, mirando hacia donde apunta el cohete (lo que verían los astronautas)
		var tip := _rocket.global_position + _rocket.basis.y * (h + 1.0)
		_cam.position = tip
		var fwd := _rocket.basis.y
		var up_ref := _rocket.basis.z if absf(fwd.dot(Vector3.UP)) > 0.95 else Vector3.UP
		_cam.look_at(tip + fwd * 100.0 - up_ref * 30.0, up_ref)
		if _cabin:
			var s := FlightSim.state_at(sim, _pt) if _phase >= Phase.FLIGHT else {}
			_cabin.set_data(float(s.get("y", 0.0)), sqrt(pow(float(s.get("vx", 0.0)), 2) + pow(float(s.get("vy", 0.0)), 2)), float(s.get("g", 1.0)), int(s.get("stage", 0)) + 1)
		return
	var k := clampf(delta * (3.0 if _phase == Phase.FLIGHT else 2.0), 0.0, 1.0)
	if _cam.position.distance_to(want) > h * 40.0 + 400.0:
		_cam.position = want
	else:
		_cam.position = _cam.position.lerp(want, k)
	var up_v := (_cam.position - (_center - Vector3(_origin[0], _origin[1], _origin[2]))).normalized()
	if _cam.position.distance_to(target) > 0.01:
		_cam.look_at(target, up_v)
	if "--earthcam" in OS.get_cmdline_user_args(): # prueba: la Tierra vista desde 400 km sobre la plataforma
		var pad := Vector3(0, HangarWorld.PAD_SURFACE, HangarWorld.PAD_Z) - Vector3(_origin[0], _origin[1], _origin[2])
		var upp := (pad - (_center - Vector3(_origin[0], _origin[1], _origin[2]))).normalized()
		_cam.position = pad + upp * 400000.0
		_cam.look_at(pad, Vector3.FORWARD if absf(upp.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT)
		return
	# Temblor: la explosión sacude más cuanto más cerca está la cámara; el despegue retumba
	_shake = maxf(_shake - delta * 0.7, 0.0)
	var near_k := clampf(1.0 - _cam.position.distance_to(target) / (h * 60.0 + 900.0), 0.0, 1.0)
	var rumble := 0.0
	if _phase == Phase.COUNTDOWN and _said.has("ignition"):
		rumble = 0.25
	elif _phase == Phase.FLIGHT and alt < 3000.0 and not _exploded:
		rumble = 0.3 * (1.0 - alt / 3000.0)
	var amp := _shake * _shake * h * 0.06 * near_k + rumble
	_cam.h_offset = randf_range(-amp, amp)
	_cam.v_offset = randf_range(-amp, amp)
	# Lente más cerrada desde el suelo cuando el cohete se aleja
	_cam.fov = clampf(55.0 - (_cam.position.distance_to(target) / 1000.0) * 4.0, 8.0, 55.0) if _cam_mode == 0 else 55.0


## Grabaciones (tráiler): --boom=T hace explotar el cohete a los T segundos de vuelo.
func _dev_boom() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--boom=") and _phase == Phase.FLIGHT and not _exploded and _pt >= float(arg.trim_prefix("--boom=")):
			sim["success"] = false
			sim["reason"] = "FAIL_CREW_LOC"
			sim["duration"] = _pt
			_explode()


func _update_sky() -> void:
	var s := FlightSim.state_at(sim, _pt) if _phase >= Phase.FLIGHT else {}
	var alt := float(s.get("y", 0.0))
	var k := clampf(alt / 70000.0, 0.0, 1.0)
	# El cielo se oscurece al subir: a 30 km ya es azul oscuro, a 80 km es negro con estrellas
	_world.sky_mat.set_shader_parameter("space", clampf(pow(alt / 80000.0, 0.7), 0.0, 1.0))
	# El terreno local (hangar, plataforma, Florida) es un cuadrado de unos kilómetros: al subir se
	# funde en la bruma y luego se oculta; desde ahí se ve la Tierra entera (esfera con la foto de la NASA)
	_world.env.fog_enabled = alt < 12000.0
	_world.env.fog_density = lerpf(0.00007, 0.0007, clampf(alt / 8000.0, 0.0, 1.0))
	# Se oculta todo menos el Sol: si se apagaba con el resto, desde los 9 km la Tierra y el cohete
	# quedaban sin luz (todo azul oscuro, sin tierra verde ni nubes)
	var show_local := alt < 9000.0
	if show_local != _local_shown:
		_local_shown = show_local
		for c in _world.root.get_children():
			if c is Node3D and c != _world.sun:
				(c as Node3D).visible = show_local
	_world.env.volumetric_fog_enabled = alt < 5000.0 and str(Game.settings.get("quality", "high")) == "high"
	_world.env.ambient_light_energy = lerpf(_world.amb_day, 0.2, k)
	if _earth_mat:
		_earth_mat.set_shader_parameter("cloud_shift", _pt * 0.000004)
	var halo := _ground.get_node_or_null("Halo")
	if halo:
		halo.visible = alt > 20000.0
		(halo.material_override as ShaderMaterial).set_shader_parameter("center", (halo as Node3D).global_position)
	# Motores: se oyen fuerte abajo y se apagan con el aire (en el vacío no hay sonido)
	var burning := _phase == Phase.COUNTDOWN and _said.has("ignition")
	if _phase == Phase.FLIGHT:
		burning = bool(s.get("on", false)) and not _exploded
	var vol := 0.0
	if burning:
		vol = clampf(1.0 - alt / 40000.0, 0.0, 1.0)
	if vol > 0.01:
		if not _engine_snd.playing:
			_engine_snd.play()
		_engine_snd.volume_db = linear_to_db(vol) - 4.0
		_engine_snd.pitch_scale = 1.0 + clampf(alt / 40000.0, 0.0, 1.0) * 0.15
	elif _engine_snd.playing:
		_engine_snd.stop()
	# Música según el momento: retos de la tripulación → tensión; ascenso → épica; espacio → calma
	if _phase == Phase.ROLLOUT:
		Sound.flight_music = "space" # traslado: música tranquila mientras el crawler avanza
	elif _crawler_snd.playing:
		_crawler_snd.stop()
	if _phase in [Phase.COUNTDOWN, Phase.FLIGHT]:
		if _exploded:
			Sound.flight_music = ""
		elif _crew_busy:
			Sound.flight_music = "challenge"
		elif _phase == Phase.FLIGHT:
			Sound.flight_music = "space" if alt > 60000.0 else "launch"
	elif _phase in [Phase.TRANSFER, Phase.OPS] and not _hud.get_children().any(func(c: Node) -> bool: return c is LandingView):
		Sound.flight_music = "challenge" if _crew_busy else "space"
	_roar.volume_db = linear_to_db(maxf(clampf(1.0 - alt / 20000.0, 0.0, 1.0), 0.0001))
	if alt > 20000.0 and _roar.playing:
		_roar.stop()


# ---------- Telemetría ----------

func _telemetry_text(s: Dictionary) -> String:
	var t := float(s.get("t", 0.0))
	var v := sqrt(pow(float(s.vx), 2.0) + pow(float(s.vy), 2.0))
	var si := int(s.get("stage", 0))
	var st: Dictionary = analysis.stages[mini(si, analysis.stages.size() - 1)]
	var lines := [
		"%s %02d:%02d" % [tr("FL_TPLUS"), int(t) / 60, int(t) % 60],
		"%-13s %s km" % [tr("FL_ALT"), Game.fmt(float(s.y) / 1000.0, 1)],
		"%-13s %s km/s" % [tr("FL_SPEED"), Game.fmt(v / 1000.0, 2)],
		"%-13s %s km" % [tr("FL_RANGE"), Game.fmt(float(s.x) / 1000.0, 1)],
		"%-13s %s g" % [tr("FL_ACCEL"), Game.fmt(float(s.g), 1)],
		"%-13s %s kPa" % [tr("FL_Q"), Game.fmt(float(s.q) / 1000.0, 1)],
		"%-13s %d / %d" % [tr("FL_STAGE"), si + 1, analysis.stages.size()],
	]
	return "\n".join(lines)


# ---------- Tripulación ----------

## Al llegar al informe la tripulación ya no hace falta: se libera (deja de dibujar la cabina y la ventanita).
func _free_crew() -> void:
	if _crew_mission:
		_crew_mission.abort()
	if _crew:
		_crew.queue_free()
		_crew = null
	if _pip:
		_pip.queue_free()
		_pip = null
	_crew_busy = false


## Filas del informe de la tripulación: [texto, es_título, color]. Nota S/A/B/C, MVP y título por puesto.
func _crew_report() -> Array:
	if _crew_mission == null or _crew_mission.scores.is_empty():
		return []
	var avg := crew_average()
	var grade := "S" if avg >= 90.0 else ("A" if avg >= 75.0 else ("B" if avg >= 55.0 else "C"))
	var rows := [[tr("RES_CREW") % [grade, int(avg)], true, Game.MARK]]
	var best := ""
	var best_v := -1.0
	var players := Game.crew_players()
	for role in ["commander", "engineer", "systems", "comms"]:
		var arr: Array = _crew_mission.scores.get(role, [])
		if arr.is_empty():
			continue
		var s := 0.0
		for x in arr:
			s += float(x)
		s /= arr.size()
		if s > best_v:
			best_v = s
			best = role
		var who := tr("CREW_AUTOPILOT")
		for i in players.size():
			if role in players[i].roles:
				who = tr("CREW_PLAYER") % (i + 1)
		var title := "TT_ICE" if s >= 95.0 else ("TT_STEADY" if s >= 85.0 else ("TT_SOLID" if s >= 70.0 else ("TT_ROOKIE" if s >= 50.0 else "TT_MASHER")))
		rows.append(["%s %s (%s) · %d · %s" % [tr("CREW_" + role.to_upper()), Astronaut.NAMES[role], who, int(s), tr(title)], false, Astronaut.ROLE_COLORS[role]])
	if best != "":
		rows.insert(1, [tr("RES_MVP") % ("%s %s" % [tr("CREW_" + best.to_upper()), Astronaut.NAMES[best]]), false, Game.GOOD])
	return rows


func _crew_enabled() -> bool:
	return bool(Game.settings.get("crew", true)) and Game.landtest == "" and not "--smoke" in OS.get_cmdline_user_args() and not "--nohud" in OS.get_cmdline_user_args() # --nohud: grabar el video sin retos de tripulación


func _first_sep_t() -> float:
	for e in sim.events:
		if e.key == "separation":
			return float(e.t)
	return -1.0


## Corre una fase de retos: la vista de la tripulación tapa el vuelo, que sigue en cámara lenta en la ventanita.
func _crew_phase(phase: String, turbulence := 0.0) -> void:
	_crew_done[phase] = true
	if _flowlog:
		print("FLOW crew phase ", phase, " pt=", int(_pt))
	if _crew == null:
		_crew = CrewView.new()
		var crewed := bool(analysis.get("probe", {}).get("crew", false)) or level in CREWED_MISSIONS
		_crew.room = "cabin" if crewed else "mcc"
		_crew.players = Game.crew_players()
		_crew.theme = Game.theme
		_hud.get_child(0).add_child(_crew)
		_hud.get_child(0).move_child(_crew, 0)
		_crew_mission = CrewMission.new()
		_crew_mission.view = _crew
		add_child(_crew_mission)
		_crew_mission.houston.connect(func(line: Dictionary) -> void:
			comms.clear()
			comms.skip()
			comms.say(line, "HOUSTON"))
		_crew_mission.phase_done.connect(_on_crew_phase_done)
		_crew_mission.step_scored.connect(_on_crew_step)
		_build_pip()
	if _crew_mission.challenges_for(phase).is_empty():
		return
	_crew_busy = true
	_crew.visible = true
	if _flowlog:
		print.call_deferred("FLOW crew visible ", phase, " ", _crew.is_visible_in_tree())
	var on_wall := _crew.room == "mcc"
	_pip.visible = not on_wall
	if on_wall:
		_pip_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_crew_hidden.clear()
	for c in _hud.get_child(0).get_children():
		if c is Control and c != _crew and c != _pip and c.visible:
			c.visible = false
			_crew_hidden.append(c)
	_crew_mission.turbulence = turbulence
	# Primera vez en la cabina o en la Sala de Control: tutorial de la tripulación antes del primer reto
	var tut := "crew_tut_" + _crew.room
	if not "--crewai" in OS.get_cmdline_user_args() and not Game._dev_no_save and Game.first_time(tut):
		var line: Dictionary = _comms_data.get("crew", {}).get(tut, {})
		if not line.is_empty():
			comms.clear()
			comms.say(line, "HOUSTON")
		_crew.show_intro(func() -> void:
			_crew_mission.run_phase(phase))
		return
	_crew_mission.run_phase(phase)


## Error de la tripulación: turbulencia; al tercero (segundo en manual) la nave falla de verdad.
func _on_crew_step(_role: String, score: float, human: bool) -> void:
	# Solo cuentan los errores de las personas (el piloto automático no hace fallar la nave)
	if score >= CREW_MISTAKE or _crew_failed or not human:
		return
	_crew_mistakes += 1
	_shake_t = 1.8
	if _crew:
		_crew.shake = 1.0
	for p in Game.crew_players():
		if int(p.device) >= 0:
			Input.start_joy_vibration(int(p.device), 0.6, 1.0, 0.8)
	var limit := 2 if str(Game.settings.get("crew_mode", "assisted")) == "manual" else 3
	var line: Dictionary = _comms_data.get("crew", {}).get("crew_err_%d" % mini(_crew_mistakes, limit - 1), {})
	if _crew_mistakes >= limit:
		_crew_fail(_crew_mission.phase)
	elif not line.is_empty():
		comms.clear()
		comms.say(line, "HOUSTON")


## La nave falla por la tripulación: según la fase, se aborta en la plataforma, se pierde el control o la etapa no se suelta.
func _crew_fail(phase: String) -> void:
	if phase == "transfer":
		_crew_mission.abort() # el encendido salió mal: la nota baja el Δv del viaje y quizá no se llega
		return
	_crew_failed = true
	_crew_mission.abort()
	sim["success"] = false
	var key := "FAIL_CREW_PAD" if phase == "countdown" else ("FAIL_CREW_SEP" if phase == "separation" else "FAIL_CREW_LOC")
	sim["reason"] = key
	var line: Dictionary = _comms_data.get("crew", {}).get(key.to_lower(), {})
	if not line.is_empty():
		comms.clear()
		comms.skip()
		comms.say(line, "HOUSTON")
	if phase == "landing" and _crew_after.is_valid():
		# Descenso perdido: el módulo baja sin control y se estrella (se ve en la superficie)
		var mars := level >= 5
		_crew_after = func() -> void: _fade_then(func() -> void: _start_landing(mars, false))
		return
	if phase == "countdown":
		_crew_busy = false
		get_tree().create_timer(3.5).timeout.connect(_show_report)
		return
	# En vuelo: el cohete se rompe ahora y el vuelo termina aquí
	sim["duration"] = _pt
	_explode()


## Corre los retos de la tripulación de esa fase y después llama a then (o la llama ya si no hay tripulación o retos).
func _crew_then(phase: String, then: Callable) -> void:
	if not _crew_enabled() or _exploded or _crew_done.has(phase):
		then.call()
		return
	_crew_phase(phase)
	if not _crew_busy:
		then.call()
		return
	_crew_after = then


func _on_crew_phase_done(_phase: String, _avg: float) -> void:
	if _flowlog:
		print("FLOW crew done ", _phase, " avg=", int(_avg), " pt=", int(_pt))
	_crew_busy = false
	_crew.visible = false
	_pip.visible = false
	_pip_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for c in _crew_hidden:
		if is_instance_valid(c):
			c.visible = true
	_crew_hidden.clear()
	if _crew_after.is_valid():
		var f := _crew_after
		_crew_after = Callable()
		f.call_deferred()
	# En modo manual, fallar un reto crítico termina la misión
	if _crew_mission.failed_critical and str(Game.settings.get("crew_mode", "assisted")) == "manual" and sim.success:
		sim["success"] = false
		sim["reason"] = "FAIL_CREW"


## Asistido: la nota de la tripulación mueve el Δv sobrante ±3 % (una buena tripulación salva un diseño justo).
func _crew_dv_factor() -> float:
	if _crew_mission == null:
		return 1.0
	var avg := crew_average()
	return 1.0 + clampf((avg - 70.0) / 30.0, -1.0, 1.0) * 0.03


func crew_average() -> float:
	if _crew_mission == null:
		return -1.0
	var t := 0.0
	var n := 0
	for r in _crew_mission.scores:
		for s in _crew_mission.scores[r]:
			t += float(s)
			n += 1
	return t / n if n > 0 else -1.0


## Pantallas de los puestos con datos del vuelo en vivo (cabina o Sala de Control).
func _update_crew_screens() -> void:
	if not _crew_busy or _crew == null or Engine.get_process_frames() % 6 != 0:
		return
	var s := FlightSim.state_at(sim, _pt) if _phase >= Phase.FLIGHT else {"y": 0.0, "vx": 0.0, "vy": 0.0, "g": 1.0, "q": 0.0, "stage": 0}
	var v := sqrt(pow(float(s.get("vx", 0.0)), 2.0) + pow(float(s.get("vy", 0.0)), 2.0))
	var ev: Dictionary = analysis.get("probe", {})
	var c := _crew.cabin
	c.set_screen_text("commander", "ALT %s km
VEL %s km/s" % [Game.fmt(float(s.get("y", 0.0)) / 1000.0, 1), Game.fmt(v / 1000.0, 2)])
	c.set_screen_text("engineer", "STAGE %d/%d
ACC %s g" % [int(s.get("stage", 0)) + 1, (analysis.get("stages", []) as Array).size(), Game.fmt(float(s.get("g", 0.0)), 1)])
	c.set_screen_text("systems", "Q %s kPa
PWR %d/%d W" % [Game.fmt(float(s.get("q", 0.0)) / 1000.0, 1), int(ev.get("have_w", 0.0)), int(ev.get("need_w", 0.0))])
	c.set_screen_text("comms", "LINK %s
%s/d" % [str(ev.get("ground", "NEN")).to_upper(), ResourcePanel._mb(float(ev.get("downlink_mb", 0.0)))])


## Ventanita con el cohete por fuera mientras hay un reto (otra cámara en el mismo mundo del vuelo).
func _build_pip() -> void:
	_pip = SubViewportContainer.new()
	_pip.stretch = true
	_pip.anchor_left = 1.0
	_pip.anchor_right = 1.0
	_pip.offset_left = -360
	_pip.offset_right = -24
	_pip.offset_top = 24
	_pip.offset_bottom = 24 + 189
	_pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pip.visible = false
	var vp := SubViewport.new()
	_pip_vp = vp
	vp.size = Vector2i(960, 540)
	vp.world_3d = _vp.find_world_3d() # el vuelo vive en su propio SubViewport
	_pip.visibility_changed.connect(func() -> void: vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _pip.visible else SubViewport.UPDATE_DISABLED)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_pip.add_child(vp)
	_pip_cam = Camera3D.new()
	vp.add_child(_pip_cam)
	_pip_cam.current = true
	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", Game._box(Color(0, 0, 0, 0), 2, Game.MARK, Vector4.ZERO))
	_pip.add_child(frame)
	_hud.get_child(0).add_child(_pip)
	# En la Sala de Control el cohete se ve en la pantalla grande, frente a todos (no en la ventanita)
	if _crew and _crew.room == "mcc" and (_crew.cabin as MissionControl).wall_mat:
		var wm: ShaderMaterial = (_crew.cabin as MissionControl).wall_mat
		wm.set_shader_parameter("feed", vp.get_texture())
		wm.set_shader_parameter("use_feed", 1.0)
		# Fuera de la ventanita (oculta, ahí la cámara no se activa) y con resolución propia
		_pip.remove_child(vp)
		add_child(vp)
		vp.size = Vector2i(960, 540)
		_pip_cam.set_deferred("current", true) # al mover el viewport la cámara deja de ser la activa


func _update_pip() -> void:
	if _pip and (_pip.visible or _crew_busy) and _cam:
		_pip_cam.global_transform = _cam.global_transform
		_pip_cam.fov = _cam.fov
		_pip_cam.far = _cam.far
		_pip_cam.near = _cam.near
		if _flowlog and Engine.get_process_frames() % 60 == 0:
			print("PIP cam=", _pip_cam.global_position, " main=", _cam.global_position, " vpcam=", _pip_vp.get_camera_3d(), " world_same=", _pip_vp.find_world_3d() == _vp.find_world_3d(), " size=", _pip_vp.size, " mode=", _pip_vp.render_target_update_mode)


func _say(key: String) -> void:
	_said[key] = true
	var e: Dictionary = _comms_data.get("flight", {}).get(key, {})
	if not e.is_empty():
		comms.say(e, str(e.get("who", "HOUSTON")))


# ---------- Informe ----------

func _show_report() -> void:
	if _phase == Phase.REPORT:
		return
	if _phase == Phase.FLIGHT and _pt < float(sim.duration) and _wants_transfer():
		# "Ir al resultado" durante el ascenso: igual se muestra el viaje (se puede saltar ahí)
		_pt = float(sim.duration)
		_start_transfer()
		return
	if _crew_busy and _crew_mission:
		_crew_mission.abort()
	if _ops != null:
		_ops._skip_all() # "Ir al resultado" durante la operación
		return
	if not _ops_done and _wants_ops():
		_start_ops()
		return
	_phase = Phase.REPORT
	_pt = float(sim.duration)
	_free_crew()
	if _exploded == false and sim.reason in ["FAIL_UNSTABLE", "FAIL_BREAKUP"]:
		_explode()
	_countdown.text = ""
	var stars := 0
	# Ciencia: llega a la Tierra si la sonda llegó (o en parte), tiene energía y la antena alcanza
	var legs_total := (Game.level(level).get("legs", []) as Array).size() if level >= 0 else 0
	_science = Probe.science_earned(analysis.get("probe", {}), bool(sim.success), int(sim.get("legs_reached", 0)), legs_total) * float(sim.get("ops_mult", 1.0))
	Sound.flight_music = "victory" if sim.success else ""
	if sim.success:
		stars = 1
		var budget := float(analysis.get("budget", 0.0))
		if budget <= 0.0 or float(analysis.cost) <= budget * 0.75:
			stars += 1
		if _science >= float(analysis.get("probe", {}).get("target", 1e9)):
			stars += 1
		# Si vio la solución, la misión queda aprobada con 1 estrella: las otras se ganan con un diseño propio
		if level >= 0 and Game.progress.get("seen", {}).has("solution_seen_%d" % level):
			stars = mini(stars, 1)
		if not sandbox:
			Game.complete_level(level, stars)
	_report = _build_report(stars)
	_hud.get_child(0).add_child(_report)


## Operación: la misión llegó y tiene instrumentos (no en la prueba de vuelo rápida).
func _wants_ops() -> bool:
	var ev: Dictionary = analysis.get("probe", {})
	return bool(sim.success) and level >= 1 and int(ev.get("n_instruments", 0)) > 0 and ev.has("mission_h")


func _start_ops() -> void:
	var ev: Dictionary = analysis.get("probe", {})
	var legs_total := (Game.level(level).get("legs", []) as Array).size()
	_phase = Phase.OPS
	_ops = OpsView.new()
	_ops.ev = ev
	_ops.mission = level
	_ops.base_science = Probe.science_earned(ev, true, legs_total, legs_total)
	_ops.target = float(ev.get("target", 0.0))
	_ops.theme = Game.theme
	for c in _hud.get_children():
		if c is Control and c != comms:
			c.visible = false
	_hud.add_child(_ops)
	_ops.say.connect(func(line: Dictionary) -> void:
		comms.clear()
		comms.skip()
		comms.say(line, "HOUSTON"))
	_ops.finished.connect(func(mult: float, extra: float, log: Array) -> void:
		_ops_done = true
		sim["ops_mult"] = mult
		sim["ops_log"] = log
		analysis["cost"] = float(analysis.get("cost", 0.0)) + extra
		_hud.remove_child(_ops)
		_ops.queue_free()
		_ops = null
		for c in _hud.get_children():
			if c is Control:
				c.visible = true
		_show_report())


func _build_report(stars: int) -> Control:
	var veil := ColorRect.new()
	veil.color = Color(Game.PAPER_DEEP, 0.78)
	veil.add_to_group("modal")
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.add_child(center)
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = "Sheet"
	sheet.custom_minimum_size.x = 1180 # dos columnas: números a la izquierda, detalle a la derecha (menos scroll)
	center.add_child(sheet)
	# Contenido con scroll y botones fijos abajo (el informe creció: segmentos, tripulación, decisiones)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	sheet.add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var title := Label.new()
	title.text = "RES_TITLE_OK" if sim.success else "RES_TITLE_FAIL"
	title.theme_type_variation = "Title"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Game.GOOD if sim.success else Game.MARK)
	v.add_child(title)
	var star_row := Label.new()
	star_row.text = "★".repeat(stars) + "☆".repeat(3 - stars)
	star_row.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	star_row.add_theme_font_size_override("font_size", 40)
	star_row.add_theme_color_override("font_color", Game.MARK)
	v.add_child(star_row)
	var why := Label.new()
	why.text = "RES_" + str(sim.reason)
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	why.theme_type_variation = "Body"
	why.add_theme_font_size_override("font_size", 17)
	v.add_child(why)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	v.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.custom_minimum_size.x = 470
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	# Números del vuelo en fichas (etiqueta arriba, valor grande abajo), 2 columnas
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 12)
	var orbit_txt := "—"
	if sim.orbit:
		orbit_txt = "%s × %s km" % [Game.fmt(float(sim.apoapsis) / 1000.0, 0), Game.fmt(float(sim.perigee) / 1000.0, 0)]
	for pair in [["RES_APOGEE", "%s km" % Game.fmt(float(sim.apogee) / 1000.0, 1)],
			["RES_MAXV", "%s km/s" % Game.fmt(float(sim.max_v) / 1000.0, 2)],
			["RES_MAXQ", "%s kPa" % Game.fmt(float(sim.max_q) / 1000.0, 1)],
			["RES_MAXG", "%s g" % Game.fmt(float(sim.max_g), 1)],
			["RES_LEGS", "%d / %d" % [int(sim.get("legs_reached", 0)), (Game.level(level).get("legs", []) as Array).size()] if level >= 2 else "—"],
			["RES_ORBIT", orbit_txt],
			["RES_SCIENCE", "%d / %d" % [int(_science), int(analysis.get("probe", {}).get("target", 0))]],
			["RES_PROGRESS", "%d %%" % int(clampf(float(sim.progress), 0.0, 1.0) * 100.0)]]:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		cell.custom_minimum_size.x = 210
		var c := Label.new()
		c.text = pair[0]
		c.theme_type_variation = "Eyebrow"
		cell.add_child(c)
		var val := Label.new()
		val.text = pair[1]
		val.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		val.theme_type_variation = "Title"
		val.add_theme_font_size_override("font_size", 26)
		cell.add_child(val)
		grid.add_child(cell)
	left.add_child(grid)
	# Los 4 segmentos de una misión (NASA): lanzamiento, espacial, tierra y usuario
	var ev: Dictionary = analysis.get("probe", {})
	if ev.has("mission_h"):
		var sl := Label.new()
		sl.text = "RES_SEGMENTS"
		sl.theme_type_variation = "Eyebrow"
		right.add_child(sl)
		var sg := GridContainer.new()
		sg.columns = 2
		sg.add_theme_constant_override("h_separation", 28)
		var data_gb := float(ev.get("data_mb", 0.0)) * float(ev.get("data_frac", 1.0)) * float(ev.get("mission_h", 0.0)) / 24.0 / 1000.0 if sim.success else 0.0
		var papers := int(_science / 15.0)
		var rows := [["SEG_SPACE", tr("SEG_SPACE_V") % [int(ev.get("mass", 0.0)), int(ev.get("n_instruments", 0))]],
			["SEG_GROUND", tr("SEG_GROUND_V") % [str(ev.get("ground", "")).to_upper(), ResourcePanel._mb(float(ev.get("downlink_mb", 0.0)))]],
			["SEG_USER", tr("SEG_USER_V") % [Game.fmt(data_gb, 1), papers]]]
		if bool(ev.get("eol_applies", false)):
			rows.append(["SEG_EOL", tr("SEG_EOL_OK") if bool(ev.get("deorbit", false)) else tr("SEG_EOL_JUNK")])
		for r in rows:
			var c := Label.new()
			c.text = r[0]
			c.theme_type_variation = "Eyebrow"
			sg.add_child(c)
			var val := Label.new()
			val.text = r[1]
			val.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			val.theme_type_variation = "Body"
			val.add_theme_font_size_override("font_size", 14)
			val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			val.custom_minimum_size.x = 300
			sg.add_child(val)
		right.add_child(sg)
	# Tripulación: nota, MVP y títulos por puesto
	var crew_rows := _crew_report()
	if not crew_rows.is_empty():
		for r: Array in crew_rows:
			var cl := Label.new()
			cl.text = str(r[0])
			cl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			cl.theme_type_variation = "Eyebrow" if r[1] else "Body"
			cl.add_theme_font_size_override("font_size", 15 if r[1] else 14)
			if r.size() > 2:
				cl.add_theme_color_override("font_color", r[2])
			cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			right.add_child(cl)
	# Decisiones de la fase de operación
	var ops_log: Array = sim.get("ops_log", [])
	if not ops_log.is_empty():
		var ol := Label.new()
		ol.text = "RES_OPS"
		ol.theme_type_variation = "Eyebrow"
		right.add_child(ol)
		for e: Dictionary in ops_log:
			var l := Label.new()
			l.text = ("✓ " if e.good else "✕ ") + "%s: %s%s" % [e.title, e.choice, (" (" + tr("OPS_AUTO") + ")") if e.auto else ""]
			l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.theme_type_variation = "Body"
			l.add_theme_font_size_override("font_size", 14)
			l.add_theme_color_override("font_color", Game.INK if e.good else Game.MARK)
			right.add_child(l)
	# Misiones secundarias del encargo
	var xs := Advisor.extras(level, analysis, design, sim, _science) if level >= 0 else []
	if not xs.is_empty():
		var xl := Label.new()
		xl.text = "RES_EXTRAS"
		xl.theme_type_variation = "Eyebrow"
		right.add_child(xl)
		for x: Dictionary in xs:
			var row := Label.new()
			row.text = ("✓  " if x.ok else "✗  ") + str(x.text)
			row.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			row.add_theme_color_override("font_color", Game.GOOD if x.ok else Game.INK_DIM)
			right.add_child(row)
	var note := Label.new()
	note.text = "RES_STARS_NOTE"
	note.theme_type_variation = "Hint"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 13)
	v.add_child(note)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	var replay := Button.new()
	replay.text = "RES_REPLAY"
	replay.custom_minimum_size.y = 42
	replay.pressed.connect(func() -> void: Game.goto("flight"))
	row.add_child(replay)
	var back := Button.new()
	back.text = "RES_RETRY"
	back.custom_minimum_size.y = 42
	back.pressed.connect(func() -> void: Game.goto("workshop"))
	row.add_child(back)
	if sim.success and not sandbox:
		var nxt := Button.new()
		nxt.text = "RES_NEXT"
		nxt.theme_type_variation = "Primary"
		nxt.pressed.connect(func() -> void:
			Game.selected_level = mini(level + 1, Game.levels.size() - 1)
			Game.goto("levels"))
		row.add_child(nxt)
	outer.add_child(row)
	# Alto del scroll: el del contenido, sin pasar de lo que cabe en la pantalla
	(func() -> void:
		await get_tree().process_frame
		scroll.custom_minimum_size.y = clampf(v.get_combined_minimum_size().y, 160.0, get_viewport().get_visible_rect().size.y - 190.0)).call_deferred()
	return veil


## Gráfico de la trayectoria (altura contra distancia) en estilo plano.
class TrajectoryChart extends Control:
	var sim: Dictionary = {}
	var t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.05, 0.09, 0.72))
		draw_rect(Rect2(Vector2.ZERO, size), Game.LINE, false, 1.0)
		draw_string(Game.font_mono_medium, Vector2(12, 18), tr("FL_TRAJ"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Game.INK_DIM)
		var samples: Array = sim.get("samples", [])
		if samples.size() < 2:
			return
		var max_x := 1000.0
		var max_y := 110000.0
		for s in samples:
			max_x = maxf(max_x, float(s.x))
			max_y = maxf(max_y, float(s.y))
		max_y *= 1.1
		var area := Rect2(Vector2(14, 28), size - Vector2(28, 42))
		var to_px := func(x: float, y: float) -> Vector2:
			return area.position + Vector2(x / max_x * area.size.x, area.size.y - y / max_y * area.size.y)
		# Línea de los 100 km
		var ky: Vector2 = to_px.call(0.0, 100000.0)
		draw_dashed_line(Vector2(area.position.x, ky.y), Vector2(area.end.x, ky.y), Color(Game.INK_DIM, 0.5), 1.0, 6.0)
		draw_string(Game.font_mono, Vector2(area.end.x - 110, ky.y - 4), tr("FL_KARMAN"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Game.INK_DIM)
		var all := PackedVector2Array()
		var flown := PackedVector2Array()
		for s in samples:
			var p: Vector2 = to_px.call(float(s.x), float(s.y))
			all.append(p)
			if float(s.t) <= t:
				flown.append(p)
		draw_polyline(all, Color(Game.INK_DIM, 0.35), 1.0, true)
		if flown.size() > 1:
			draw_polyline(flown, Game.MARK, 2.0, true)
			draw_circle(flown[flown.size() - 1], 4.0, Game.MARK)
