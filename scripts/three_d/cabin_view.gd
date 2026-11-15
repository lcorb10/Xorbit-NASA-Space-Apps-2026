class_name CabinView
extends SubViewportContainer
## Vista desde dentro de la cabina (modo de cámara "Cabina" del vuelo), inspirada en el módulo de mando
## del Apolo: tres asientos con los astronautas, el tablero principal con instrumentos que se encienden y
## dos ventanas por las que se ve el vuelo real (la imagen de la cámara exterior, en vivo).
## Los números del tablero (altura, velocidad, aceleración) son los de la simulación.

var outside: Texture2D ## lo que se ve por las ventanas
var _root: Node3D
var _cam: Camera3D
var _readouts: Array[Label3D] = []
var _lights: Array[StandardMaterial3D] = []
var _t := 0.0
var _g := 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	_root = Node3D.new()
	vp.add_child(_root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	_root.add_child(we)
	_build()
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.near = 0.02
	_root.add_child(_cam)
	# Detrás y un poco arriba del astronauta del centro: se ven los cascos abajo, el tablero y las ventanas
	_cam.position = Vector3(0, 0.62, 0.62)
	_cam.look_at(Vector3(0, 0.92, -1.1), Vector3.UP)


func _build() -> void:
	var hull := _mat(Color(0.42, 0.43, 0.45), 0.85)
	var panel := _mat(Color(0.32, 0.34, 0.37), 0.6)
	var dark := _mat(Color(0.08, 0.08, 0.09), 0.7)
	# Casco interior: cono (el módulo de mando mide 3,9 m de diámetro abajo)
	var shell := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.6
	c.bottom_radius = 1.95
	c.height = 2.6
	c.radial_segments = 32
	shell.mesh = c
	var hm := hull.duplicate() as StandardMaterial3D
	hm.cull_mode = BaseMaterial3D.CULL_FRONT # se ve desde adentro
	shell.material_override = hm
	shell.position.y = 0.8
	_root.add_child(shell)
	# Tablero principal: tres paneles en arco frente a los asientos
	for k in 3:
		var a := (k - 1) * 0.62
		var p := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.95, 0.75, 0.06)
		p.mesh = b
		p.material_override = panel
		p.position = Vector3(sin(a) * 1.2, 0.6, -cos(a) * 1.2)
		p.rotation = Vector3(-0.35, -a, 0)
		_root.add_child(p)
		_gauges(p, k)
	# Dos ventanas (las de encuentro del Apolo) con el exterior en vivo
	for s in [-1.0, 1.0]:
		var w := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.62, 0.48)
		w.mesh = q
		var wm := StandardMaterial3D.new()
		wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wm.albedo_texture = outside
		wm.uv1_scale = Vector3(0.5, 0.75, 1)
		wm.uv1_offset = Vector3(0.25 if s < 0 else 0.25, 0.1, 0)
		w.material_override = wm
		w.position = Vector3(s * 0.38, 1.12, -0.95)
		w.rotation = Vector3(-0.3, s * -0.2, 0)
		_root.add_child(w)
		var frame := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(0.7, 0.56, 0.03)
		frame.mesh = fb
		frame.material_override = dark
		frame.position = w.position - w.transform.basis.z * 0.02
		frame.rotation = w.rotation
		_root.add_child(frame)
	# Tres asientos con astronautas (traje blanco y casco)
	for k in 3:
		var x := (k - 1) * 0.62
		var seat := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.5, 0.08, 1.0)
		seat.mesh = sb
		seat.material_override = dark
		seat.position = Vector3(x, -0.35, 0.35)
		seat.rotation.x = 0.35
		_root.add_child(seat)
		var suit := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.17
		cap.height = 0.75
		suit.mesh = cap
		suit.material_override = _mat(Color(0.92, 0.92, 0.9), 0.8)
		suit.position = Vector3(x, -0.18, 0.25)
		suit.rotation.x = -1.2
		_root.add_child(suit)
		var helmet := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = 0.15
		hs.height = 0.3
		helmet.mesh = hs
		var glass := _mat(Color(0.9, 0.9, 0.95), 0.1)
		glass.metallic = 0.6
		helmet.material_override = glass
		helmet.position = Vector3(x, 0.02, -0.12)
		_root.add_child(helmet)
	# Luz de cabina
	var l := OmniLight3D.new()
	l.position = Vector3(0, 1.4, 0.4)
	l.light_energy = 1.2
	l.omni_range = 4.0
	l.light_color = Color(0.95, 0.95, 1.0)
	_root.add_child(l)


## Indicadores del panel: luces de estado, interruptores y tres lecturas con números.
func _gauges(p: Node3D, k: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 40 + k
	for j in 18:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.03, 0.02)
		b.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.1, 0.1, 0.1)
		m.emission_enabled = true
		m.emission = [Color(0.2, 1.0, 0.4), Color(1.0, 0.7, 0.2), Color(1.0, 0.25, 0.2), Color(0.9, 0.9, 1.0)][rng.randi() % 4]
		m.emission_energy_multiplier = rng.randf_range(0.5, 2.0)
		b.material_override = m
		_lights.append(m)
		b.position = Vector3(-0.38 + (j % 6) * 0.15, -0.25 + (j / 6) * 0.08, 0.04)
		p.add_child(b)
	var r := Label3D.new()
	r.font_size = 40
	r.pixel_size = 0.0012
	r.modulate = Color(0.5, 1.0, 0.6)
	r.outline_size = 0
	r.position = Vector3(0, 0.15, 0.04)
	r.font = Game.font_mono_medium
	p.add_child(r)
	_readouts.append(r)


func set_data(alt_m: float, v: float, g: float, stage: int) -> void:
	_g = g
	if _readouts.size() >= 3:
		_readouts[0].text = "ALT\n%s km" % Game.fmt(alt_m / 1000.0, 1)
		_readouts[1].text = "VEL\n%s km/s" % Game.fmt(v / 1000.0, 2)
		_readouts[2].text = "ACC %s g\nSTG %d" % [Game.fmt(g, 1), stage]


func _process(delta: float) -> void:
	_t += delta
	# Las luces parpadean un poco; la cabina tiembla con la aceleración
	for k in _lights.size():
		if (int(_t * 3.0) + k) % 23 == 0:
			_lights[k].emission_energy_multiplier = randf_range(0.4, 2.0)
	var shake := clampf(_g - 1.0, 0.0, 6.0) * 0.003
	_cam.h_offset = randf_range(-shake, shake)
	_cam.v_offset = randf_range(-shake, shake)


static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
