class_name PartPreview3D
extends SubViewportContainer
## Vista 3D de la pieza que se está diseñando en el torno: gira sola sobre una base
## giratoria; arrastrar la gira a mano, la rueda acerca o aleja. Usa los mismos
## materiales con textura que el cohete del hangar.

var _vp: SubViewport
var _pivot: Node3D
var _part: Node3D
var _cam: Camera3D
var _yaw := 0.7
var _pitch := 0.22
var _zoom := 1.0
var _drag := false
var _idle := 0.0
var _fit := 3.0 # tamaño de la pieza para encuadrarla
var _center_y := 0.0


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)
	var root := Node3D.new()
	_vp.add_child(root)
	# Estudio: fondo oscuro, luz de ambiente y reflejos del cielo HDRI para que el metal brille
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.09, 0.13)
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load("res://assets/textures/sky/kloofendal_puresky_2k.hdr")
	pano.energy_multiplier = 0.8
	sky.sky_material = pano
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -40, 0)
	key.light_energy = 1.4
	key.shadow_enabled = true
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 150, 0)
	rim.light_energy = 0.7
	rim.light_color = Color(0.7, 0.8, 1.0)
	root.add_child(rim)
	# Base giratoria con la cuadrícula del plano
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.05
	cyl.height = 0.08
	cyl.radial_segments = 64
	base.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.16, 0.2, 0.26)
	bm.metallic = 0.6
	bm.roughness = 0.35
	base.material_override = bm
	base.name = "Base"
	root.add_child(base)
	_pivot = Node3D.new()
	root.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 35.0
	root.add_child(_cam)
	gui_input.connect(_on_input)


## Arma la pieza: perfil de revolución (r, y hacia abajo), tipo y material.
func show_part(prof: PackedVector2Array, kind: String, part: Dictionary, length: float, diameter: float) -> void:
	if _pivot == null:
		return
	if _part:
		_part.queue_free()
	_part = Node3D.new()
	_pivot.add_child(_part)
	var t := {"kind": kind}
	_part.add_child(RocketBuilder._mesh_node(RocketBuilder.lathe(prof), RocketBuilder._material_for(part, t)))
	var bottom := length
	var r := diameter / 2.0
	# Tapas arriba y abajo (en el cohete las tapan las piezas vecinas; aquí se vería el hueco)
	for end in [0, prof.size() - 1]:
		var cr := prof[end].x
		if cr > 0.01:
			var cap := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = cr
			cyl.bottom_radius = cr
			cyl.height = 0.004
			cyl.radial_segments = 64
			cap.mesh = cyl
			cap.material_override = RocketBuilder._mat("metal_dark")
			cap.position.y = -prof[end].y
			_part.add_child(cap)
	match kind:
		"engine":
			var b := RocketAnalysis.bell(str(part.get("engine", "rutherford")))
			var bl := float(b.get("length", r))
			var bell := RocketBuilder._mesh_node(RocketBuilder.bell_mesh(minf(float(b.get("exit_d", r)), diameter * 0.9), bl, r), RocketBuilder._mat("engine_bell"))
			bell.position.y = -length
			_part.add_child(bell)
			bottom += bl
		"solid":
			var nz := RocketBuilder._mesh_node(RocketBuilder.bell_mesh(r * 0.8, r, r), RocketBuilder._mat("engine_bell"))
			nz.position.y = -length
			_part.add_child(nz)
			bottom += r
	# La pieza se apoya en la base
	_part.position.y = bottom + 0.04
	var base := _vp.get_child(0).get_node("Base") as MeshInstance3D
	base.scale = Vector3(maxf(r * 1.6, 0.3), 1.0, maxf(r * 1.6, 0.3))
	_fit = maxf(bottom, diameter) + 0.2
	_center_y = bottom / 2.0


func _process(delta: float) -> void:
	if _cam == null:
		return
	_idle += delta
	if not _drag and _idle > 2.0:
		_yaw += delta * 0.45 # gira sola cuando no la tocas
	var dist := _fit * 0.5 / tan(deg_to_rad(_cam.fov) * 0.5) * 1.25 * _zoom
	var target := Vector3(0, _center_y, 0)
	_cam.position = target + Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, -_pitch) * Vector3(0, 0, dist)
	_cam.near = maxf(dist * 0.01, 0.01)
	_cam.far = dist * 20.0
	_cam.look_at(target)


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = maxf(_zoom * 0.9, 0.4)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = minf(_zoom * 1.1, 3.0)
		_idle = 0.0
	elif event is InputEventMouseMotion and _drag:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.008
		_pitch = clampf(_pitch + mm.relative.y * 0.006, -0.3, 1.3)
		_idle = 0.0
