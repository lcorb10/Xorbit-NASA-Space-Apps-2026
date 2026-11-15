class_name MissionControl
extends CrewCabin
## Sala de Control de Houston (modelo NASA JSC, con materiales propios): las misiones no tripuladas se
## juegan aquí. Los jugadores son controladores de vuelo en una fila de consolas mirando la pantalla grande.
## Hereda de CrewCabin los puestos, controles, cámara y retos; solo cambia el espacio alrededor.
## Coordenadas del modelo: (x, y, z) del archivo -> (x, z, -y) en Godot. La pantalla está en z = -8,7.

const MODEL := "res://assets/models/nasa/mcc/mission_control.glb"
## Fila de los jugadores: escritorio en z = -1,1 (de -0,75 a -1,5), pantallas en z = -1,5 (medido del modelo).
## Bloque derecho de la fila: x de -3 a 4,8. Los asientos van detrás del escritorio.
const SEAT_Z := -0.22
const STATION_X := [-2.2, -0.4, 1.4, 3.2]

var wall_mat: ShaderMaterial


func _build_room() -> void:
	crew_outfit = "controller" # en tierra: polo del puesto, auricular y lentes
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	add_child(model)
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := _material_for(mi.mesh.surface_get_material(s).resource_name)
			if mat is BaseMaterial3D:
				mat = mat.duplicate()
				(mat as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED # el modelo trae caras invertidas
			if mat:
				mi.set_surface_override_material(s, mat)
	# Avisadores: una fila de luces sobre la pantalla grande (hay que mirar arriba para encontrar la alarma)
	for k in 12:
		var a := _box(self, Vector3(0.5, 0.18, 0.05), Vector3(-8.0 + k * 0.85, 5.15, -8.5), _plain(Color(0.25, 0.22, 0.12), 0.4))
		annunciators.append(a)
	_alarm_light = OmniLight3D.new()
	_alarm_light.light_color = Color(1, 0.2, 0.12)
	_alarm_light.light_energy = 0.0
	_alarm_light.omni_range = 3.0
	add_child(_alarm_light)


func _material_for(name_: String) -> Material:
	match name_:
		"floor":
			return _pbr("Carpet016", 1.2, Color(0.42, 0.45, 0.55))
		"wall", "wall_top", "cabnet", "edge", "mid", "midle", "right", "far_right", "crstation_1", "crstation_2":
			return _pbr("Plastic013A", 1.5, Color(0.42, 0.45, 0.5))
		"ceiling":
			return _pbr("Plastic013A", 2.0, Color(0.55, 0.57, 0.6))
		"console_body", "console_back", "console_face":
			return _pbr("Plastic006", 0.6, Color(0.42, 0.44, 0.5))
		"console_desk":
			return _pbr("Plastic013A", 0.8, Color(0.62, 0.6, 0.56))
		"Keyboards", "keyboard_special":
			return _plain(Color(0.08, 0.08, 0.09), 0.6)
		"screens":
			var m := ShaderMaterial.new()
			m.shader = load("res://assets/shaders/console_screen.gdshader")
			return m
		"screen":
			wall_mat = ShaderMaterial.new()
			wall_mat.shader = load("res://assets/shaders/wall_screen.gdshader")
			return wall_mat
		"wall_screen":
			return _plain(Color(0.05, 0.06, 0.08), 0.5)
		"lights":
			return _plain(Color(1.0, 0.97, 0.9), 0.3, 0.0, 2.5)
		"projector1":
			return _pbr("Metal009", 0.4, Color(0.4, 0.42, 0.45), true)
	if name_.begins_with("picture"):
		return _plain(Color(0.15, 0.2, 0.3), 0.4, 0.0, 0.4)
	if name_.begins_with("console_namep"):
		return _plain(Color(0.85, 0.85, 0.8), 0.5, 0.0, 0.3)
	return null


func _station_xform(i: int) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(STATION_X[i], 0, SEAT_Z))


func _build_lights() -> void:
	var sun := DirectionalLight3D.new() # luz difusa del techo
	sun.rotation_degrees = Vector3(-80, 20, 0)
	sun.light_energy = 0.25
	add_child(sun)
	for x in [-6.0, -1.5, 3.0]:
		for z in [-6.0, -1.0, 4.0]:
			var l := OmniLight3D.new()
			l.position = Vector3(x, 5.2, z)
			l.light_energy = 1.2
			l.omni_range = 7.0
			l.light_color = Color(1.0, 0.96, 0.9)
			add_child(l)
	var glow := OmniLight3D.new()
	glow.position = Vector3(-3.0, 3.0, -7.5)
	glow.light_color = Color(0.4, 0.6, 1.0)
	glow.light_energy = 1.5
	glow.omni_range = 9.0
	add_child(glow)
