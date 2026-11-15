class_name HangarView
extends SubViewportContainer
## Vista 3D del taller: el hangar (HangarWorld) con el cohete del diseño sobre su soporte.
## Cámara orbital (arrastrar = girar, rueda = acercar, clic derecho = subir/bajar)
## y cámara libre (F: WASD, Q/E, Shift). La cámara choca con paredes, techo y terreno.

signal part_selected(index: int)
signal drop_new(id: String, at: int)

const LAYER_WORLD := 1
const LAYER_ROCKET := 2

var selected := -1:
	set(v):
		selected = v
		_apply_highlight()

var world: HangarWorld
var _vp: SubViewport
var _world: Node3D
var cutaway := false
var _rocket: Node3D
var _stand: MeshInstance3D
var _cam: Camera3D
var _design: Array = []
var _analysis: Dictionary = {}
var _probe_sphere: SphereShape3D

# Cámara orbital
var _yaw := deg_to_rad(35.0)
var _pitch := deg_to_rad(6.0)
var _dist := 18.0
var _target := Vector3(0, 4, 0)
var _goal_target := Vector3(0, 4, 0)
var _goal_dist := 18.0
var _dragging := false
var _drag_moved := 0.0
# Cámara libre
var free_cam := false
var _free_pos := Vector3.ZERO
var _free_yaw := 0.0
var _free_pitch := 0.0
## Mientras es false (p. ej. durante el lanzamiento), esta vista no mueve la cámara.
var camera_control := true


func _ready() -> void:
	stretch = true
	if "--nohud" in OS.get_cmdline_user_args(): # grabar el video: el hangar a pantalla completa, sin paneles
		top_level = true
		z_index = RenderingServer.CANVAS_ITEM_Z_MAX
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	_vp = SubViewport.new()
	_vp.msaa_3d = Viewport.MSAA_4X
	if str(Game.settings.get("quality", "high")) == "high":
		_vp.use_taa = true # suavizado temporal: menos parpadeo en celosías, pasto y bordes finos
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_vp.positional_shadow_atlas_size = 4096
	_vp.own_world_3d = true
	add_child(_vp)
	_world = Node3D.new()
	_vp.add_child(_world)
	world = HangarWorld.new()
	world.build(_world)
	var steel := world.pbr("stand_steel", "metal_plate", 1.0, Color(0.4, 0.42, 0.46))
	_stand = MeshInstance3D.new()
	_stand.mesh = CylinderMesh.new()
	_stand.material_override = steel
	_world.add_child(_stand)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.near = 0.1
	_cam.far = 6000.0
	_world.add_child(_cam)
	_probe_sphere = SphereShape3D.new()
	_probe_sphere.radius = 0.6
	_update_camera(1.0)


func get_world_root() -> Node3D:
	return _world


func get_camera() -> Camera3D:
	return _cam


func get_rocket() -> Node3D:
	return _rocket


func get_stand() -> MeshInstance3D:
	return _stand


func set_design(design: Array, analysis: Dictionary) -> void:
	_design = design
	_analysis = analysis
	if _rocket:
		_rocket.queue_free()
	RocketBuilder.cutaway = cutaway
	_rocket = RocketBuilder.build(design, analysis)
	RocketBuilder.cutaway = false
	if cutaway:
		_rocket.add_child(RocketInterior.build(design, analysis))
	var maxd := maxf(float(analysis.get("max_d", 1.0)), 0.4)
	var sh := clampf(maxd * 0.8, 0.5, 1.6)
	var cyl := _stand.mesh as CylinderMesh
	cyl.top_radius = maxd * 1.1
	cyl.bottom_radius = maxd * 1.3
	cyl.height = sh
	_stand.position = Vector3(0, sh / 2.0, 0)
	_rocket.position = Vector3(0, sh, 0)
	_world.add_child(_rocket)
	var h := maxf(float(analysis.get("height", 1.0)), 1.0)
	_goal_target = Vector3(0, sh + h * 0.5, 0)
	_goal_dist = clampf(h * 1.3 + 4.0, 6.0, 160.0)
	_apply_highlight()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--camview="):
			var v := arg.trim_prefix("--camview=").split(",")
			_yaw = deg_to_rad(float(v[0]))
			_pitch = deg_to_rad(float(v[1]))
			_goal_dist = float(v[2])
			_goal_target = Vector3(0, float(v[3]), float(v[4]))


## Vista en corte: corta la mitad del cohete que mira a la cámara y muestra lo de adentro.
func set_cutaway(on: bool) -> void:
	cutaway = on
	RenderingServer.global_shader_parameter_set("xorbit_cut", 1.0 if on else 0.0)
	if not _design.is_empty():
		set_design(_design, _analysis)


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("xorbit_cut", 0.0)


func _process(delta: float) -> void:
	if cutaway and _rocket and _cam:
		# El plano de corte pasa por el eje del cohete y mira hacia la cámara
		var to_cam := _cam.global_position - _rocket.global_position
		to_cam.y = 0.0
		RenderingServer.global_shader_parameter_set("xorbit_cut_n", to_cam.normalized() if to_cam.length() > 0.01 else Vector3.FORWARD)
		RenderingServer.global_shader_parameter_set("xorbit_cut_o", _rocket.global_position)
	if not camera_control:
		return
	if free_cam:
		_free_move(delta)
	else:
		_update_camera(clampf(delta * 6.0, 0.0, 1.0))


func _update_camera(k: float) -> void:
	_target = _target.lerp(_goal_target, k)
	_dist = lerpf(_dist, _goal_dist, k)
	var dir := Vector3(cos(_pitch) * sin(_yaw), sin(_pitch), cos(_pitch) * cos(_yaw))
	var want := _target + dir * _dist
	# Si una pared o el techo se interponen, la cámara se acerca hasta quedar delante
	if _world and _world.is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(_target, want, LAYER_WORLD)
		var hit := _world.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			want = _target + dir * maxf(_target.distance_to(hit.position) - 0.8, 1.0)
	want.y = maxf(want.y, 0.5)
	_cam.position = want
	_cam.look_at(_target, Vector3.UP)


# ---------- Entrada ----------

func _gui_input(event: InputEvent) -> void:
	if not camera_control:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_goal_dist = maxf(_goal_dist * 0.9, 3.0)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_goal_dist = minf(_goal_dist * 1.1, 200.0)
			accept_event()
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if mb.pressed:
				_dragging = true
				_drag_moved = 0.0
				grab_focus()
			else:
				_dragging = false
				if mb.button_index == MOUSE_BUTTON_LEFT and _drag_moved < 6.0 and not free_cam:
					part_selected.emit(_pick(mb.position))
			accept_event()
	elif event is InputEventMouseMotion and (_dragging or free_cam):
		var mm := event as InputEventMouseMotion
		_drag_moved += mm.relative.length()
		if free_cam:
			_free_yaw -= mm.relative.x * 0.004
			_free_pitch = clampf(_free_pitch - mm.relative.y * 0.004, -1.4, 1.4)
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or mm.shift_pressed:
			_goal_target.y = clampf(_goal_target.y + mm.relative.y * _dist * 0.002, 0.5, 200.0)
		else:
			_yaw -= mm.relative.x * 0.006
			_pitch = clampf(_pitch + mm.relative.y * 0.005, deg_to_rad(-5), deg_to_rad(80))
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not camera_control:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		toggle_free_cam()
		get_viewport().set_input_as_handled()


func toggle_free_cam() -> void:
	free_cam = not free_cam
	if free_cam:
		_free_pos = _cam.position
		var fwd := -_cam.global_transform.basis.z
		_free_yaw = atan2(-fwd.x, -fwd.z)
		_free_pitch = asin(clampf(fwd.y, -1.0, 1.0))
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _free_move(delta: float) -> void:
	if Input.is_key_pressed(KEY_ESCAPE):
		toggle_free_cam()
		return
	var basis := Basis.from_euler(Vector3(_free_pitch, _free_yaw, 0))
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir -= basis.z
	if Input.is_key_pressed(KEY_S): dir += basis.z
	if Input.is_key_pressed(KEY_A): dir -= basis.x
	if Input.is_key_pressed(KEY_D): dir += basis.x
	if Input.is_key_pressed(KEY_E): dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q): dir -= Vector3.UP
	var speed := 30.0 if Input.is_key_pressed(KEY_SHIFT) else 9.0
	if dir != Vector3.ZERO:
		var motion := dir.normalized() * speed * delta
		# Mover una esfera y detenerla antes de chocar (paredes, techo, terreno)
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = _probe_sphere
		params.transform = Transform3D(Basis.IDENTITY, _free_pos)
		params.motion = motion
		params.collision_mask = LAYER_WORLD
		var res := _world.get_world_3d().direct_space_state.cast_motion(params)
		var safe: float = res[0] if res.size() > 0 else 1.0
		_free_pos += motion * safe
	_free_pos.y = clampf(_free_pos.y, 0.5, 900.0)
	_cam.transform = Transform3D(basis, _free_pos)


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("type") == "new_part"


func _drop_data(at: Vector2, data: Variant) -> void:
	# Sobre una pieza: debajo de ella (o encima si se suelta en su mitad de arriba). En el vacío: al final.
	var hit := _pick_hit(at)
	if hit.is_empty():
		drop_new.emit(data.id, -1)
		return
	var i := int(hit.collider.get_meta("index"))
	var part: Node3D = hit.collider.get_parent()
	var local_y: float = part.to_local(hit.position).y
	var parts: Array = _analysis.get("parts", [])
	var length := float(parts[i].length) if i < parts.size() else 1.0
	drop_new.emit(data.id, i if local_y > -length / 2.0 else i + 1)


func _pick_hit(screen_pos: Vector2) -> Dictionary:
	var local := screen_pos * Vector2(_vp.size) / size
	var from := _cam.project_ray_origin(local)
	var to := from + _cam.project_ray_normal(local) * 500.0
	var hit := _world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, LAYER_ROCKET))
	if hit.is_empty() or not hit.collider.has_meta("index"):
		return {}
	return hit


func _pick(screen_pos: Vector2) -> int:
	var hit := _pick_hit(screen_pos)
	return -1 if hit.is_empty() else int(hit.collider.get_meta("index"))


func _apply_highlight() -> void:
	if _rocket == null:
		return
	for part in _rocket.get_children():
		var on: bool = int(part.get_meta("index", -1)) == selected
		for mi in part.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_overlay = RocketBuilder.highlight_material() if on else null
