class_name Explosion
extends Node3D
## Explosión de un cohete. En el aire: destello, bola de fuego que sube y se apaga en
## humo negro, columna de humo que se queda, chispas que caen, onda expansiva y estruendo.
## En el vacío no hay aire que arda ni que lleve el sonido: un destello y una nube de
## vapor y restos que se expande y se desvanece, en silencio.
## Todo vive en coordenadas locales: se cuelga del nodo que se mueve con el suelo.

var size := 10.0
var vacuum := false
var on_ground := false
var _core: MeshInstance3D
var _ring: MeshInstance3D
var _light: OmniLight3D
var _t := 0.0

static var _puff_tex: Texture2D
static var _boom: AudioStreamWAV


static func spawn(parent: Node3D, pos: Vector3, rocket_size: float, in_vacuum: bool, ground := false) -> Explosion:
	var e := Explosion.new()
	e.size = clampf(rocket_size, 2.0, 120.0)
	e.vacuum = in_vacuum
	e.on_ground = ground
	parent.add_child(e)
	e.position = pos
	e._build()
	return e


func _build() -> void:
	var s := size
	# Destello de luz
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.7, 0.35)
	_light.light_energy = 40.0
	_light.omni_range = s * 18.0
	_light.shadow_enabled = false
	add_child(_light)
	# Núcleo incandescente que crece en un cuarto de segundo
	_core = MeshInstance3D.new()
	_core.mesh = QuadMesh.new()
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	cm.billboard_keep_scale = true
	cm.albedo_texture = puff_texture()
	cm.albedo_color = Color(1.0, 0.85, 0.55, 1.0)
	cm.emission_enabled = true
	cm.emission = Color(1.0, 0.7, 0.35)
	cm.emission_energy_multiplier = 3.0
	_core.material_override = cm
	_core.scale = Vector3.ONE * 0.01
	add_child(_core)
	# Onda expansiva: un anillo que se abre rápido (en el aire se ve por la condensación)
	if false:
		_ring = MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.92
		tor.outer_radius = 1.0
		tor.rings = 48
		_ring.mesh = tor
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.albedo_color = Color(1, 1, 1, 0.5)
		_ring.material_override = rm
		_ring.scale = Vector3.ONE * 0.01
		if not on_ground:
			_ring.rotation = Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
		add_child(_ring)

	if vacuum:
		# Nube de vapor que se expande en todas direcciones, sin subir ni caer
		_particles(160, 3.5, s * 0.5, s * 1.4, s * 3.0, s * 6.0, Vector3.ZERO, 0.2, 180.0,
			[Color(5.0, 4.0, 2.5, 1.0), Color(0.85, 0.85, 0.9, 0.55), Color(0.7, 0.72, 0.8, 0.0)], true)
		_sparks(70, s * 6.0, Vector3.ZERO)
	else:
		# Bola de fuego: sube porque el aire caliente flota, y se oscurece al enfriarse
		_particles(150, 3.2, s * 0.7, s * 1.8, s * 1.2, s * 3.5, Vector3(0, s * 0.6, 0), 2.0, 180.0,
			[Color(3.2, 2.0, 0.7, 0.85), Color(2.4, 0.75, 0.12, 0.8), Color(0.7, 0.16, 0.04, 0.75),
			Color(0.14, 0.11, 0.09, 0.8), Color(0.1, 0.1, 0.1, 0.0)], true)
		# Humo negro y espeso que queda en el cielo
		_particles(120, 12.0, s * 1.0, s * 2.6, s * 0.4, s * 1.6, Vector3(0, s * 0.25, 0), 0.6, 180.0,
			[Color(0.16, 0.14, 0.13, 0.0), Color(0.16, 0.14, 0.13, 0.75), Color(0.3, 0.3, 0.3, 0.4), Color(0.45, 0.45, 0.45, 0.0)], false)
		_sparks(90, s * 4.0, Vector3(0, -9.8, 0))
		if on_ground:
			# Polvo que corre por el suelo
			var dust := _particles(90, 6.0, s * 0.8, s * 2.2, s * 2.0, s * 5.0, Vector3(0, 0.6, 0), 1.5, 90.0,
				[Color(0.55, 0.48, 0.4, 0.0), Color(0.55, 0.48, 0.4, 0.8), Color(0.6, 0.55, 0.5, 0.0)], false)
			(dust.process_material as ParticleProcessMaterial).direction = Vector3(1, 0.05, 0)
			(dust.process_material as ParticleProcessMaterial).flatness = 0.85
		_play_boom()


## Sistema de partículas de humo o fuego (cuadros que miran a la cámara con una bocanada suave).
func _particles(amount: int, life: float, size_min: float, size_max: float, v_min: float, v_max: float,
		gravity: Vector3, damping: float, spread: float, colors: Array, glow: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.92
	p.randomness = 0.4
	p.local_coords = true
	p.visibility_aabb = AABB(Vector3.ONE * -size * 40.0, Vector3.ONE * size * 80.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = size * 0.35
	pm.direction = Vector3(0, 1, 0)
	pm.spread = spread
	pm.initial_velocity_min = v_min
	pm.initial_velocity_max = v_max
	pm.gravity = gravity
	pm.damping_min = damping * size * 0.3
	pm.damping_max = damping * size * 0.6
	pm.scale_min = size_min
	pm.scale_max = size_max
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -20.0
	pm.angular_velocity_max = 20.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.35))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1, 1.8))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	var offs := PackedFloat32Array()
	for i in colors.size():
		offs.append(float(i) / float(colors.size() - 1))
	grad.offsets = offs
	grad.colors = PackedColorArray(colors)
	var gt := GradientTexture1D.new()
	gt.use_hdr = true
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = smoke_sprite(amount) if not glow else (load("res://assets/textures/particles/fire_01.png") if ResourceLoader.exists("res://assets/textures/particles/fire_01.png") else puff_texture())
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # el fuego da su propia luz
	else:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.roughness = 1.0
	quad.material = mat
	p.draw_pass_1 = quad
	add_child(p)
	p.emitting = true
	return p


## Chispas y pedazos encendidos que salen disparados.
func _sparks(amount: int, speed: float, gravity: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 2.2
	p.one_shot = true
	p.explosiveness = 1.0
	p.randomness = 0.5
	p.local_coords = true
	p.visibility_aabb = AABB(Vector3.ONE * -size * 60.0, Vector3.ONE * size * 120.0)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = gravity
	pm.damping_min = 0.5
	pm.damping_max = 2.0
	pm.scale_min = size * 0.04
	pm.scale_max = size * 0.12
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([Color(3.0, 1.4, 0.3, 1), Color(2.0, 0.5, 0.06, 1), Color(0.5, 0.1, 0.0, 0)])
	var gt := GradientTexture1D.new()
	gt.use_hdr = true
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.35)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	p.draw_pass_1 = quad
	add_child(p)
	p.emitting = true


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / 0.35, 0.0, 1.0)
	_core.scale = Vector3.ONE * size * (0.5 + 3.0 * (1.0 - pow(1.0 - k, 3.0)))
	var cm := _core.material_override as StandardMaterial3D
	cm.albedo_color.a = clampf(1.0 - (_t - 0.1) / 0.45, 0.0, 1.0)
	cm.emission_energy_multiplier = 3.0 * cm.albedo_color.a
	_core.visible = cm.albedo_color.a > 0.0
	_light.light_energy = 40.0 * exp(-_t * 2.2) + (0.0 if vacuum else 4.0 * clampf(1.0 - _t / 3.0, 0.0, 1.0))
	if _ring:
		var r := size * (1.0 + _t * 60.0)
		_ring.scale = Vector3(r, r * 0.4, r)
		(_ring.material_override as StandardMaterial3D).albedo_color.a = clampf(0.5 - _t * 0.6, 0.0, 1.0)
		_ring.visible = _t < 0.85
	if _t > 16.0:
		queue_free()


## Sprite de humo del Kenney Particle Pack (CC0); varía según la semilla.
static func smoke_sprite(seed_i: int) -> Texture2D:
	var path := "res://assets/textures/particles/smoke_%02d.png" % (1 + absi(seed_i) % 9)
	if ResourceLoader.exists(path):
		return load(path)
	return puff_texture()


## Bocanada de humo suave y algo irregular, generada una vez (respaldo).
static func puff_texture() -> Texture2D:
	if _puff_tex:
		return _puff_tex
	var n := FastNoiseLite.new()
	n.seed = 5
	n.frequency = 0.06
	n.fractal_octaves = 4
	var img := Image.create(128, 128, true, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var d := Vector2(x - 63.5, y - 63.5).length() / 63.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (0.65 + 0.7 * (n.get_noise_2d(x, y) * 0.5 + 0.5))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	_puff_tex = ImageTexture.create_from_image(img)
	return _puff_tex


static var _rumble: AudioStreamWAV


## Rugido de motores cohete: ruido grave con crepitar, en bucle (2 s).
static func rumble_stream() -> AudioStreamWAV:
	if _rumble:
		return _rumble
	var rate := 22050
	var n := rate * 2
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var lp := 0.0
	var lp2 := 0.0
	var vals := PackedFloat32Array()
	vals.resize(n)
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.08
		lp2 += (lp - lp2) * 0.15
		var crackle := w * 0.25 if rng.randf() < 0.02 else 0.0
		vals[i] = lp2 * 4.0 + lp * 0.6 + crackle
	# Fundido cruzado al final para que el bucle no haga clic
	var fade := rate / 10
	for i in fade:
		var k := float(i) / fade
		vals[n - fade + i] = vals[n - fade + i] * (1.0 - k) + vals[i] * k
	for i in n:
		data.encode_s16(i * 2, int(clampf(vals[i], -1.0, 1.0) * 30000.0))
	_rumble = AudioStreamWAV.new()
	_rumble.format = AudioStreamWAV.FORMAT_16_BITS
	_rumble.mix_rate = rate
	_rumble.data = data
	_rumble.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_rumble.loop_begin = fade
	_rumble.loop_end = n
	return _rumble


## Estruendo: ruido grave que se apaga, con chasquidos al principio.
func _play_boom() -> void:
	if _boom == null:
		var rate := 22050
		var n := int(rate * 3.5)
		var data := PackedByteArray()
		data.resize(n * 2)
		var lp := 0.0
		var lp2 := 0.0
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		for i in n:
			var t := float(i) / rate
			var white := rng.randf_range(-1.0, 1.0)
			lp += (white - lp) * 0.06 # filtro paso bajo: retumbo
			lp2 += (lp - lp2) * 0.1
			var env := exp(-t * 1.6) * minf(t / 0.01, 1.0)
			var crack := white * exp(-t * 18.0) * 0.5
			var v := clampf((lp2 * 5.0 + crack) * env, -1.0, 1.0)
			data.encode_s16(i * 2, int(v * 32000.0))
		_boom = AudioStreamWAV.new()
		_boom.format = AudioStreamWAV.FORMAT_16_BITS
		_boom.mix_rate = rate
		_boom.data = data
	var pl := AudioStreamPlayer.new()
	pl.stream = _boom
	pl.volume_db = 2.0
	pl.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(pl)
	pl.play()
