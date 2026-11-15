class_name HoustonFace
extends Node3D
## Houston, el director de vuelo: personaje MakeHuman (MPFB2, recursos CC0) con visemas para mover la boca.
## talking = true mientras suena su voz: la boca alterna formas (aa, O, E, U, PP, FF...) con transiciones suaves.

const SCENE := "res://assets/models/crew/houston/houston.glb"
const MOUTH := ["viseme_aa", "viseme_O", "viseme_E", "viseme_I", "viseme_U", "viseme_PP", "viseme_FF", "viseme_DD", "viseme_kk", "viseme_SS"]

var talking := false
var _face: MeshInstance3D
var _targets := {} ## nombre del visema -> peso objetivo
var _next := 0.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	add_child(model)
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh and mi.mesh.get_blend_shape_count() > 0:
			_face = mi
		# Pelo canoso de veterano: se cambia el castaño por gris y se conserva el relieve de la textura
		if "short0" in str(mi.name):
			for s in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(s)
				if src is BaseMaterial3D:
					var m := ShaderMaterial.new()
					m.shader = load("res://assets/shaders/gray_hair.gdshader")
					m.set_shader_parameter("tex", (src as BaseMaterial3D).albedo_texture)
					m.set_shader_parameter("nrm", (src as BaseMaterial3D).normal_texture)
					mi.set_surface_override_material(s, m)
	for v in MOUTH:
		_targets[v] = 0.0


## Punto de la cabeza (para encuadrar el retrato).
func head_position() -> Vector3:
	return global_position + Vector3(0, 1.62, 0.02)


func _process(delta: float) -> void:
	if _face == null:
		return
	_t += delta
	if talking and _t >= _next:
		# Una sílaba nueva cada 70-140 ms: una forma principal y a veces una mezcla
		_next = _t + _rng.randf_range(0.07, 0.14)
		for v in MOUTH:
			_targets[v] = 0.0
		_targets[MOUTH[_rng.randi() % MOUTH.size()]] = _rng.randf_range(0.55, 1.0)
		if _rng.randf() < 0.3:
			_targets[MOUTH[_rng.randi() % 5]] = _rng.randf_range(0.2, 0.5)
	elif not talking:
		for v in MOUTH:
			_targets[v] = 0.0
	for v in MOUTH:
		var i := _face.find_blend_shape_by_name(v)
		if i >= 0:
			var cur := _face.get_blend_shape_value(i)
			_face.set_blend_shape_value(i, lerpf(cur, float(_targets[v]), clampf(delta * 18.0, 0.0, 1.0)))
