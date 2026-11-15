class_name Astronaut
extends Node3D
## Astronauta de la tripulación: maniquí UAL (CC0) con traje IVA, color del puesto y casco con visor.
## - play(): animación base (siempre sentada en la cabina).
## - reach(side, node): la mano (TwoBoneIK3D, uno por brazo) va al control y lo sigue; release() la devuelve.
## - look_at_point(): la cabeza (LookAtModifier3D) mira hacia un punto.
## - emote(): saludo, apurar, pulgar arriba o pánico. Los gestos se calculan desde la posición real del
##   hombro y la cabeza en cada cuadro (sentado el hombro está a ~1,07 m, no a la altura de pie), con el
##   codo hacia afuera y abajo como en un brazo humano. La cabeza asiente o niega según el gesto.
## - Ojos: se dibujan en el vidrio del visor (pantalla bajo el reflejo), no flotando delante.
## Espacio del modelo: mira a +Z, su derecha es -X.

signal spoke(text: String)

const SCENE := "res://assets/models/crew/astronaut/astronaut.glb"
const ROLE_COLORS := {"commander": Color("#f28c28"), "engineer": Color("#3d8bfd"), "systems": Color("#2fbf71"), "comms": Color("#a05cf0")}
## Nombre de cada astronauta: el color de su puesto en inglés (decisión de Sebastián).
const NAMES := {"commander": "Orange", "engineer": "Blue", "systems": "Green", "comms": "Purple"}
const EMOTES := {
	"wave": ["Hi!", "Hey there!"],
	"hurry": ["Hurry up!", "Tick tock!"],
	"thumbs": ["Nice one!", "You got this!"],
	"panic": ["Not that button!", "Wait, wait, wait!"],
}
const MOODS := {"wave": 1, "thumbs": 1, "hurry": 2, "panic": 3}
const EMOTE_TIME := 2.4
static var THUMB_ROLL := 1.5 ## supinación del antebrazo para que el pulgar apunte arriba

var role := "commander"
var outfit := "suit" ## suit (astronauta con casco) o controller (controlador de vuelo: polo, auricular y lentes)
var skeleton: Skeleton3D
var anim: AnimationPlayer
var helmet: Node3D
var base_anim := "Sitting_Idle"
var _mesh: MeshInstance3D
var _ik := {} ## side -> TwoBoneIK3D
var _targets := {} ## side -> Marker3D (objetivo de la mano)
var _poles := {} ## side -> Marker3D (hacia dónde apunta el codo)
var _follow := {} ## side -> Node3D que la mano sigue
var _look: LookAtModifier3D
var fingers: FingerPose
var _look_target: Marker3D
var _look_base := Vector3.ZERO ## punto que mira cuando no hay gesto
var _look_kept := false ## look_at_point() activo
var _bubble: Label3D
var _voice: AudioStreamPlayer3D
var _visor_mat: ShaderMaterial
var _blink_t := 2.0
var _emote_t := 0.0
var _emote := ""
var _rng := RandomNumberGenerator.new()
static var _crew_talk_until := 0.0 ## hasta cuándo habla algún astronauta (todas las instancias)


func _ready() -> void:
	_rng.randomize()
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	anim = model.find_children("*", "AnimationPlayer", true, false)[0]
	for n in model.find_children("*", "MeshInstance3D", true, false):
		_mesh = n
		var m := ShaderMaterial.new()
		m.shader = load("res://assets/shaders/suit.gdshader")
		m.set_shader_parameter("role_color", ROLE_COLORS.get(role, Color.WHITE))
		m.set_shader_parameter("outfit", 1 if outfit == "controller" else 0)
		n.material_override = m
	_build_helmet()
	_build_ik()
	_bubble = Label3D.new()
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.font = Game.font_display
	_bubble.font_size = 48
	_bubble.pixel_size = 0.0022
	_bubble.outline_size = 14
	_bubble.outline_modulate = Color(0, 0, 0, 0.85)
	_bubble.modulate = ROLE_COLORS.get(role, Color.WHITE).lightened(0.35)
	_bubble.position = Vector3(0, 1.52, -0.12)
	_bubble.no_depth_test = true
	_bubble.visible = false
	add_child(_bubble)
	_voice = AudioStreamPlayer3D.new()
	_voice.position = Vector3(0, 1.2, -0.1)
	add_child(_voice)
	# Sin fundido al aparecer: si no, se ve la pose T del modelo durante el blend
	play(base_anim, 0.0)
	anim.advance(0.0)


## Godot quita el sufijo _Loop al importar (y deja esas animaciones en bucle): se aceptan ambos nombres.
func play(a_name: String, blend := 0.35) -> void:
	if anim == null:
		base_anim = a_name
		return
	var n := a_name if anim.has_animation(a_name) else a_name.trim_suffix("_Loop")
	if anim.has_animation(n):
		anim.play(n, blend)


## Posición de un hueso en el espacio local del astronauta (el modelo está en el origen sin rotar).
func bone_local(bone: String) -> Vector3:
	var i := skeleton.find_bone(bone)
	return skeleton.get_bone_global_pose(i).origin if i >= 0 else Vector3.ZERO


func _build_ik() -> void:
	for side in ["r", "l"]:
		var t := Marker3D.new()
		add_child(t)
		_targets[side] = t
		var pole := Marker3D.new()
		add_child(pole)
		_poles[side] = pole
		var ik := TwoBoneIK3D.new()
		ik.setting_count = 1
		ik.set_root_bone_name(0, "upperarm_" + side)
		ik.set_middle_bone_name(0, "lowerarm_" + side)
		ik.set_end_bone_name(0, "hand_" + side)
		ik.influence = 0.0
		skeleton.add_child(ik)
		ik.set_target_node(0, ik.get_path_to(t))
		ik.set_pole_node(0, ik.get_path_to(pole))
		_ik[side] = ik
		_set_pole(side, Vector3(0.0, -0.35, -0.15))
	# Dedos después del IK (el orden de los hijos del esqueleto es el orden de aplicación)
	fingers = FingerPose.new()
	skeleton.add_child(fingers)
	_look_target = Marker3D.new()
	add_child(_look_target)
	_look = LookAtModifier3D.new()
	_look.bone_name = "Head"
	_look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	_look.use_angle_limitation = true
	_look.symmetry_limitation = true
	_look.primary_limit_angle = deg_to_rad(120.0)
	_look.secondary_limit_angle = deg_to_rad(70.0)
	_look.duration = 0.2
	_look.influence = 0.0
	skeleton.add_child(_look)
	_look.target_node = _look.get_path_to(_look_target)


## Codo: desplazamiento desde el hombro hacia afuera (lado del brazo), abajo y atrás.
func _set_pole(side: String, out_down_back: Vector3) -> void:
	var s := -1.0 if side == "r" else 1.0 # la derecha del modelo es -X
	var sh := bone_local("upperarm_" + side) if skeleton else Vector3(0.2 * s, 1.07, -0.28)
	(_poles[side] as Marker3D).position = sh + Vector3(s * (0.35 + out_down_back.x), out_down_back.y, out_down_back.z)


func _blend_ik(side: String, to: float, time: float) -> void:
	create_tween().tween_property(_ik[side], "influence", to, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## La mano del lado `side` ("r"/"l") va hacia `node` y lo sigue (palanca, perilla, botón).
func reach(side: String, node: Node3D, time := 0.35) -> void:
	_follow[side] = node
	(_targets[side] as Marker3D).global_position = node.global_position
	_set_pole(side, Vector3(0.05, -0.4, -0.1))
	_blend_ik(side, 1.0, time)
	create_tween().tween_method(func(v: float) -> void: fingers.curl[side] = v, float(fingers.curl[side]), 0.75, time) # agarra


func release(time := 0.4) -> void:
	for side in _follow:
		_blend_ik(side, 0.0, time)
		var sd: String = side
		create_tween().tween_method(func(v: float) -> void: fingers.curl[sd] = v, float(fingers.curl[sd]), 0.0, time)
	_follow.clear()


func look_at_point(p: Vector3, on := true) -> void:
	_look_base = to_local(p)
	_look_kept = on
	_look_target.position = _look_base
	create_tween().tween_property(_look, "influence", 1.0 if on else 0.0, 0.3)


## Emote: wave / hurry / thumbs / panic. Devuelve la frase dicha.
func emote(kind: String, voice: AudioStream = null) -> String:
	var lines: Array = EMOTES.get(kind, ["..."])
	var text: String = lines[_rng.randi() % lines.size()]
	_emote = kind
	_emote_t = 0.0
	set_mood(MOODS.get(kind, 0))
	_bubble.text = text
	_bubble.visible = true
	_bubble.modulate.a = 1.0
	_bubble.scale = Vector3.ONE * 0.2
	create_tween().tween_property(_bubble, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var vpath := "res://assets/voice/crew/%s_%s.ogg" % [role, text.to_lower().replace(" ", "_").replace(",", "").replace("!", "").replace("'", "")]
	if voice == null and ResourceLoader.exists(vpath):
		voice = load(vpath)
	# Una sola voz de la tripulación a la vez: si otro está hablando, solo se ve el globo
	var now := Time.get_ticks_msec() / 1000.0
	if voice and now >= _crew_talk_until:
		_voice.stream = voice
		_voice.volume_db = -4.0
		_voice.play()
		_crew_talk_until = now + voice.get_length() + 0.2
	# Qué brazos usa cada gesto (el otro sigue la animación sentada)
	var arms: Array = {"wave": ["r"], "thumbs": ["r"], "hurry": ["r", "l"], "panic": ["r", "l"]}.get(kind, [])
	for side in ["r", "l"]:
		if side in arms:
			_blend_ik(side, 1.0, 0.28)
	if kind == "thumbs":
		fingers.thumb_up["r"] = true
		create_tween().tween_method(func(v: float) -> void: fingers.wrist_roll["r"] = v, 0.0, THUMB_ROLL, 0.25)
		create_tween().tween_method(func(v: float) -> void: fingers.curl["r"] = v, 0.0, 1.0, 0.25)
	elif kind == "hurry":
		create_tween().tween_method(func(v: float) -> void: fingers.curl["r"] = v, 0.0, 0.6, 0.2) # índice que toca
	if _look.influence < 0.5:
		_look_base = bone_local("Head") + Vector3(0, 0.1, 1.5)
		create_tween().tween_property(_look, "influence", 1.0, 0.2)
	spoke.emit(text)
	return text


func _process(delta: float) -> void:
	for side in _follow:
		var n: Node3D = _follow[side]
		if is_instance_valid(n):
			(_targets[side] as Marker3D).global_position = n.global_position
	_blink(delta)
	if _emote == "":
		return
	_emote_t += delta
	var t := _emote_t
	# Entrada y salida suaves del gesto
	var amp := clampf(t / 0.3, 0.0, 1.0) * clampf((EMOTE_TIME - t) / 0.4, 0.0, 1.0)
	var sh_r := bone_local("upperarm_r")
	var sh_l := bone_local("upperarm_l")
	var head := bone_local("Head") + Vector3(0, 0.1, 0) # centro del casco
	var tr_: Marker3D = _targets["r"]
	var tl: Marker3D = _targets["l"]
	var look := _look_base
	match _emote:
		"wave":
			# Mano al costado de la cabeza, palma al frente; el antebrazo se balancea desde el codo
			tr_.position = sh_r + Vector3(-0.2 + 0.07 * sin(t * 9.0), 0.3, 0.14)
			_set_pole("r", Vector3(0.15, -0.15, -0.05))
		"thumbs":
			# Antebrazo hacia adelante a la altura del pecho, codo pegado al cuerpo; la cabeza asiente
			tr_.position = sh_r + Vector3(0.04, -0.1, 0.36)
			_set_pole("r", Vector3(-0.1, -0.45, -0.1))
			look += Vector3(0, 0.25 * sin(t * 7.0) * amp, 0)
		"hurry":
			# Levanta la muñeca izquierda (el reloj) y la toca con el índice derecho
			tl.position = sh_l + Vector3(-0.14, -0.16, 0.3)
			_set_pole("l", Vector3(-0.05, -0.4, -0.1))
			tr_.position = tl.position + Vector3(0.02, 0.06 + 0.035 * absf(sin(t * 11.0)), 0.04)
			_set_pole("r", Vector3(-0.05, -0.4, -0.1))
			look = head + Vector3(0.1, -0.6, 0.8) # mira el reloj
		"panic":
			# Manos a los lados del casco, codos abiertos; la cabeza niega
			tr_.position = head + Vector3(-0.17, 0.0, 0.02)
			tl.position = head + Vector3(0.17, 0.0, 0.02)
			_set_pole("r", Vector3(0.2, -0.2, 0.05))
			_set_pole("l", Vector3(0.2, -0.2, 0.05))
			look += Vector3(0.35 * sin(t * 12.0) * amp, 0, 0)
	_look_target.position = look
	if t > EMOTE_TIME - 0.6:
		_bubble.modulate.a = clampf((EMOTE_TIME - t) / 0.6, 0.0, 1.0)
	if t > EMOTE_TIME:
		_emote = ""
		_bubble.visible = false
		set_mood(0)
		fingers.thumb_up["r"] = false
		create_tween().tween_method(func(v: float) -> void: fingers.wrist_roll["r"] = v, float(fingers.wrist_roll["r"]), 0.0, 0.3)
		if not _follow.has("r"):
			create_tween().tween_method(func(v: float) -> void: fingers.curl["r"] = v, fingers.curl["r"], 0.0, 0.3)
		_look_target.position = _look_base
		if not _look_kept:
			create_tween().tween_property(_look, "influence", 0.0, 0.4)
		for side in ["r", "l"]:
			if not _follow.has(side):
				_blend_ik(side, 0.0, 0.35)


func _blink(delta: float) -> void:
	if _visor_mat == null:
		return
	_blink_t -= delta
	var b := 0.0
	if _blink_t < 0.0:
		b = clampf(1.0 - absf(_blink_t + 0.07) / 0.07, 0.0, 1.0)
		if _blink_t < -0.14:
			_blink_t = _rng.randf_range(2.0, 5.0)
	_visor_mat.set_shader_parameter("blink", b)


## Casco cerrado: carcasa blanca con franja del color del puesto y visor de vidrio con pantalla de ojos.
func _build_helmet() -> void:
	var att := BoneAttachment3D.new()
	att.bone_name = "Head"
	skeleton.add_child(att)
	helmet = Node3D.new()
	att.add_child(helmet)
	if outfit == "controller":
		_build_headset()
		return
	helmet.position = Vector3(0, 0.1, 0.01)
	var shell := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.142
	sm.height = 0.3
	shell.mesh = sm
	var shell_mat := StandardMaterial3D.new()
	shell_mat.albedo_color = Color(0.9, 0.91, 0.92)
	shell_mat.roughness = 0.3
	shell_mat.clearcoat_enabled = true
	shell.material_override = shell_mat
	helmet.add_child(shell)
	var stripe := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.136
	tm.outer_radius = 0.149
	stripe.mesh = tm
	stripe.rotation_degrees = Vector3(0, 0, 90)
	var st_mat := StandardMaterial3D.new()
	st_mat.albedo_color = ROLE_COLORS.get(role, Color.WHITE)
	st_mat.roughness = 0.4
	stripe.material_override = st_mat
	helmet.add_child(stripe)
	var visor := MeshInstance3D.new()
	var vm := SphereMesh.new()
	vm.radius = 0.118
	vm.height = 0.19
	vm.radial_segments = 48
	vm.rings = 24
	visor.mesh = vm
	visor.position = Vector3(0, -0.01, 0.055)
	visor.scale = Vector3(1.0, 1.0, 0.9)
	_visor_mat = ShaderMaterial.new()
	_visor_mat.shader = load("res://assets/shaders/visor.gdshader")
	_visor_mat.set_shader_parameter("eye_color", ROLE_COLORS.get(role, Color.WHITE).lightened(0.2))
	visor.material_override = _visor_mat
	helmet.add_child(visor)


## Controlador de vuelo: auricular con micrófono y lentes con pantalla (los ojos se ven en los lentes).
func _build_headset() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.09)
	dark.roughness = 0.5
	var band := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.105
	tm.outer_radius = 0.118
	band.mesh = tm
	band.position = Vector3(0, 0.12, 0.0)
	band.rotation_degrees = Vector3(0, 0, 90)
	band.material_override = dark
	helmet.add_child(band)
	for s in [-1.0, 1.0]:
		var cup := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.04
		cm.bottom_radius = 0.04
		cm.height = 0.03
		cup.mesh = cm
		cup.position = Vector3(s * 0.1, 0.08, 0.0)
		cup.rotation_degrees = Vector3(0, 0, 90)
		cup.material_override = dark
		helmet.add_child(cup)
	var mic := MeshInstance3D.new()
	var mm := CylinderMesh.new()
	mm.top_radius = 0.005
	mm.bottom_radius = 0.005
	mm.height = 0.13
	mic.mesh = mm
	mic.position = Vector3(-0.085, 0.03, 0.07)
	mic.rotation_degrees = Vector3(70, -30, 0)
	mic.material_override = dark
	helmet.add_child(mic)
	var glasses := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 0.1
	gm.height = 0.2
	gm.radial_segments = 32
	gm.rings = 16
	glasses.mesh = gm
	glasses.position = Vector3(0, 0.1, 0.03)
	glasses.scale = Vector3(1.05, 0.32, 0.9)
	_visor_mat = ShaderMaterial.new()
	_visor_mat.shader = load("res://assets/shaders/visor.gdshader")
	_visor_mat.set_shader_parameter("eye_color", ROLE_COLORS.get(role, Color.WHITE).lightened(0.2))
	glasses.material_override = _visor_mat
	helmet.add_child(glasses)


## Expresión de los ojos del visor: 0 normal, 1 feliz, 2 impaciente, 3 pánico.
func set_mood(m: int) -> void:
	if _visor_mat:
		_visor_mat.set_shader_parameter("mood", m)


## Primera persona: la cámara va dentro de la cabeza; se ocultan casco y cabeza (máscara B del traje).
func set_head_visible(on: bool) -> void:
	if helmet:
		helmet.visible = on
	if _mesh and _mesh.material_override is ShaderMaterial:
		(_mesh.material_override as ShaderMaterial).set_shader_parameter("hide_head", not on)
