class_name Crew
extends Node3D
## Personal de tierra que camina por el hangar y por el Centro Espacial Kennedy.
## Modelos y animaciones: Animated Man / Woman de Quaternius (CC0), ver assets/models/crew/FUENTE.md.
## Cada persona recorre un circuito de puntos; en algunos se detiene a trabajar o a mirar.
## Los circuitos esquivan el centro del hangar (donde va el cohete) y el camino de la oruga.

const DIR := "res://assets/models/crew/"
const HEIGHT := 1.75
const WALK_SPEED := 1.25

## Uniformes: [overol, chaleco o franja, casco]. Blanco = técnico de la sala limpia,
## azul = ingeniero, naranja = seguridad de la plataforma.
const LOOKS := [
	[Color(0.93, 0.94, 0.96), Color(0.97, 0.97, 0.98), Color(0.95, 0.95, 0.95), false], # técnico de sala limpia: todo blanco
	[Color(0.14, 0.2, 0.36), Color(0.62, 0.78, 0.92), Color(0.95, 0.95, 0.95), false], # ingeniero: camisa celeste, pantalón azul
	[Color(0.2, 0.22, 0.25), Color(0.98, 0.55, 0.1), Color(0.98, 0.8, 0.1), false], # seguridad de plataforma: chaleco naranja
	[Color(0.28, 0.3, 0.33), Color(0.16, 0.26, 0.5), Color(0.95, 0.95, 0.95), false], # control de misión: polo azul NASA
	[Color(0.3, 0.3, 0.3), Color(0.5, 0.5, 0.5), Color(0, 0, 0, 0), true], # visitante sin casco, ropa de calle
]

static var _models: Array[PackedScene] = []

var path: PackedVector3Array = []
var stops := {} # índice de punto -> segundos de parada
var stop_anim := "idle"
var world: HangarWorld
var outdoor := false

var _i := 0
var _wait := 0.0
var _anim: AnimationPlayer
var _cur := ""
var _names := {"walk": "", "idle": "", "work": ""}
var _skel: Skeleton3D
var _top := 1.75
var _helmet_color := Color(0, 0, 0, 0)
var _helmet_done := false


## Pone a toda la gente en el mundo. n según la calidad gráfica.
static func populate(w: HangarWorld, high: bool) -> void:
	if not ResourceLoader.exists(DIR + "quaternius/man.fbx"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var routes := _routes()
	var count := 0
	for r: Dictionary in routes:
		if not high and r.get("optional", false):
			continue
		for k in int(r.get("people", 1)):
			var c := Crew.new()
			c.world = w
			c.outdoor = bool(r.get("outdoor", false))
			c.path = PackedVector3Array(r.points)
			if r.get("reverse", false) and k % 2 == 1:
				c.path.reverse()
			c.stops = r.get("stops", {})
			c.stop_anim = str(r.get("anim", "idle"))
			c._i = (k * 3 + rng.randi_range(0, 5)) % c.path.size()
			c._wait = rng.randf_range(0.0, 3.0)
			w.root.add_child(c)
			c._dress(LOOKS[int(r.get("look", count)) % LOOKS.size()] if r.has("look") else LOOKS[(count + k) % 4], rng)
			c.position = c._ground(c.path[c._i])
			count += 1


## Circuitos (x, z): el hangar mide 70 × 80 m con el cohete en el centro; el portón da a +z;
## el camino de la oruga ocupa |x| < 23 hasta la plataforma (z = 230).
static func _routes() -> Array:
	var pz := HangarWorld.PAD_Z
	return [
		# Hangar: vuelta por el perímetro, se detienen en la mesa del plano, las cajas y los tanques
		{"points": [Vector3(-26, 0, -30), Vector3(-20, 0, -24), Vector3(-26, 0, -6), Vector3(-26, 0, 22), Vector3(-12, 0, 32),
			Vector3(12, 0, 32), Vector3(26, 0, 24), Vector3(28, 0, 10), Vector3(26, 0, -10), Vector3(24, 0, -26), Vector3(6, 0, -33), Vector3(-10, 0, -33)],
			"people": 3, "reverse": true, "stops": {1: 7.0, 7: 5.0, 9: 6.0}, "anim": "work"},
		# Hangar: dos técnicos de sala limpia que van y vienen junto a la base del cohete (sin tocarlo)
		{"points": [Vector3(-14, 0, -12), Vector3(-14, 0, 12), Vector3(14, 0, 12), Vector3(14, 0, -12)],
			"people": 2, "look": 0, "stops": {0: 4.0, 2: 4.0}, "anim": "work"},
		# Afuera: veredas a los costados del camino de la oruga, hasta la plataforma
		{"points": [Vector3(31, 0, 46), Vector3(31, 0, 120), Vector3(31, 0, pz - 85), Vector3(31, 0, 120)],
			"people": 2, "outdoor": true, "stops": {2: 6.0}, "anim": "idle"},
		{"points": [Vector3(-31, 0, 50), Vector3(-31, 0, 125), Vector3(-31, 0, pz - 85), Vector3(-31, 0, 125)],
			"people": 2, "outdoor": true, "stops": {2: 5.0}, "anim": "idle", "optional": true},
		# Explanada frente al portón (por fuera del paso de la oruga)
		{"points": [Vector3(30, 0, 48), Vector3(42, 0, 60), Vector3(44, 0, 85), Vector3(32, 0, 88)],
			"people": 2, "outdoor": true, "stops": {1: 4.0}, "anim": "work", "optional": true},
		# Sitio de prensa junto al reloj de cuenta regresiva: gente mirando la plataforma
		{"points": [Vector3(62, 0, pz - 146), Vector3(66, 0, pz - 143), Vector3(74, 0, pz - 145), Vector3(80, 0, pz - 142)],
			"people": 4, "outdoor": true, "look": 4, "stops": {0: 14.0, 1: 10.0, 2: 16.0, 3: 12.0}, "anim": "idle"},
		# Alrededor de las exhibiciones del Saturno V y del Jupiter-C
		{"points": [Vector3(66, 0, -10), Vector3(66, 0, 40), Vector3(52, 0, 74), Vector3(66, 0, 90), Vector3(90, 0, 40), Vector3(90, 0, -10)],
			"people": 3, "outdoor": true, "look": 4, "reverse": true, "stops": {1: 8.0, 2: 6.0, 4: 8.0}, "anim": "idle", "optional": true},
	]


func _dress(look: Array, rng: RandomNumberGenerator) -> void:
	if _models.is_empty():
		for f in ["man", "woman"]:
			_models.append(load(DIR + "quaternius/%s.fbx" % f))
	var m: Node3D = (_models[0] if rng.randf() < 0.7 else _models[1]).instantiate()
	add_child(m)
	# Escala a una persona de ~1,75 m (con un poco de variación). La caja de una malla con
	# esqueleto no sirve para medir: se mide con los huesos (pies a coronilla).
	var sk := m.find_child("Skeleton3D", true, false) as Skeleton3D
	var lo := 0.0
	var hi := 1.0
	if sk:
		var rel := global_transform.affine_inverse() * sk.global_transform
		lo = 1e9
		hi = -1e9
		for i in sk.get_bone_count():
			var y := (rel * sk.get_bone_global_rest(i)).origin.y
			lo = minf(lo, y)
			hi = maxf(hi, y)
	_top = HEIGHT * rng.randf_range(0.94, 1.05)
	var s := _top / maxf(hi - lo, 0.0001)
	m.scale *= s
	m.position.y -= lo * s
	m.rotation.y += PI # el modelo mira a +z; con el giro de _process miramos a -z
	# Uniforme: el modelo pinta con una paleta en franjas (piel, ojos, pelo, camisa, pantalón);
	# se arma una paleta propia para cada persona según su puesto
	var tex := _palette(look, rng)
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for k in mesh.get_surface_count():
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = tex
			mat.roughness = 0.85
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			(mi as MeshInstance3D).set_surface_override_material(k, mat)
	_skel = m.find_child("Skeleton3D", true, false) as Skeleton3D
	_helmet_color = look[2]
	_anim = m.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		for nm in _anim.get_animation_list():
			var a := _anim.get_animation(nm)
			a.loop_mode = Animation.LOOP_LINEAR
			var low := String(nm).to_lower()
			if low.ends_with("|walk") or low.ends_with("|walking"):
				_names["walk"] = nm
			elif low.ends_with("|idle"):
				_names["idle"] = nm
			elif low.ends_with("|working") or low.ends_with("|pickup"):
				_names["work"] = nm
		_anim.speed_scale = rng.randf_range(0.92, 1.08)
	_play("idle")
	for g in m.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Casco pegado al hueso de la cabeza; se ubica en la coronilla una vez que el esqueleto ya tiene pose.
func _put_helmet() -> void:
	_helmet_done = true
	if _helmet_color.a <= 0.0 or _skel == null:
		return
	var head := -1
	for i in _skel.get_bone_count():
		if _skel.get_bone_name(i).to_lower().contains("head"):
			head = i
			break
	if head < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_idx = head
	_skel.add_child(att)
	var mat := _mat(_helmet_color, 0.35)
	var h := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.125
	sph.height = 0.15
	sph.is_hemisphere = true
	sph.radial_segments = 16
	sph.rings = 6
	h.mesh = sph
	h.material_override = mat
	var brim := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.15
	cyl.height = 0.012
	cyl.radial_segments = 16
	brim.mesh = cyl
	brim.material_override = mat
	var holder := Node3D.new()
	holder.add_child(h)
	holder.add_child(brim)
	att.add_child(holder)
	# Coronilla: a la altura de la cabeza del modelo menos el alto del casco, sobre el hueso
	var bone_g := _skel.global_transform * _skel.get_bone_global_pose(head)
	var crown := Vector3(bone_g.origin.x, global_position.y + _top - 0.085, bone_g.origin.z)
	holder.global_transform = Transform3D(Basis.IDENTITY, crown)


## Paleta de 64×64 con las mismas franjas que body.png del modelo de Quaternius:
## piel 0–19 %, ojos y cejas 19–34 %, pelo 34–53 %, camisa 53–72 %, pantalón 72–100 %.
## Lleva un poco de ruido para que la tela no se vea plana.
static func _palette(look: Array, rng: RandomNumberGenerator) -> Texture2D:
	const SKINS := [Color(0.98, 0.8, 0.64), Color(0.87, 0.66, 0.5), Color(0.72, 0.5, 0.35), Color(0.52, 0.34, 0.22), Color(0.36, 0.23, 0.15)]
	const HAIRS := [Color(0.08, 0.06, 0.05), Color(0.25, 0.15, 0.08), Color(0.45, 0.3, 0.15), Color(0.78, 0.62, 0.36), Color(0.55, 0.55, 0.55)]
	var skin: Color = SKINS[rng.randi() % SKINS.size()]
	var hair: Color = HAIRS[rng.randi() % HAIRS.size()]
	var shirt: Color = look[1]
	var pants: Color = look[0]
	if look.size() > 3 and bool(look[3]): # visitante: ropa de calle de colores variados
		shirt = Color.from_hsv(rng.randf(), rng.randf_range(0.25, 0.7), rng.randf_range(0.45, 0.9))
		pants = [Color(0.18, 0.22, 0.35), Color(0.3, 0.27, 0.22), Color(0.12, 0.12, 0.13), Color(0.55, 0.5, 0.42)][rng.randi() % 4]
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var bands := [[0.0, 0.19, skin], [0.19, 0.345, Color(0.12, 0.1, 0.1)], [0.345, 0.533, hair], [0.533, 0.722, shirt], [0.722, 1.01, pants]]
	for y in 64:
		var v := (y + 0.5) / 64.0
		var c: Color = skin
		for b in bands:
			if v >= float(b[0]) and v < float(b[1]):
				c = b[2]
		for x in 64:
			var n := rng.randf_range(-0.035, 0.035)
			img.set_pixel(x, y, Color(clampf(c.r + n, 0, 1), clampf(c.g + n, 0, 1), clampf(c.b + n, 0, 1)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _play(role: String) -> void:
	var nm: String = _names.get(role, "")
	if nm == "":
		nm = _names.idle
	if _cur == nm or _anim == null or nm == "":
		return
	_cur = nm
	_anim.play(nm, 0.3)


func _ground(p: Vector3) -> Vector3:
	if outdoor and world:
		return Vector3(p.x, maxf(world.ground_height(p.x, p.z), 0.0), p.z)
	return Vector3(p.x, 0.0, p.z)


func _process(delta: float) -> void:
	if not _helmet_done and _cur != "":
		_put_helmet.call_deferred()
		_helmet_done = true
	if path.size() < 2:
		return
	if _wait > 0.0:
		_wait -= delta
		_play(stop_anim if stops.has(_i) else "idle")
		return
	var target := _ground(path[_i])
	var to := target - position
	to.y = 0.0
	var d := to.length()
	if d < 0.15:
		_wait = float(stops.get(_i, 0.0))
		_i = (_i + 1) % path.size()
		return
	_play("walk")
	var step := minf(WALK_SPEED * delta, d)
	var dir := to / d
	position += dir * step
	position.y = _ground(position).y
	# Gira suave hacia donde camina
	var want := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(delta * 6.0, 0.0, 1.0))
