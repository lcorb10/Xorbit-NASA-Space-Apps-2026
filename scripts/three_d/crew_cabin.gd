class_name CrewCabin
extends Node3D
## Cabina de la cápsula Xorbit (modo tripulación, ver docs/TRIPULACION.md).
## Mesa redonda en el centro con los 4 puestos alrededor, mirándose: cada uno ve la cara de los demás.
## Cada puesto (stations[role]) tiene su asiento, su consola inclinada sobre la mesa con los controles de
## su rol y una pantalla baja (no tapa las caras). Arriba, un anillo de avisadores (la alarma que hay que
## buscar con la mirada). Ventanas entre los puestos. Materiales PBR CC0 de ambientCG (assets/textures/cabin).
## Controles: set_stick(v2), set_throttle(0..1), set_cover(open), set_toggle(on), set_knob(i, 0..1),
## set_antenna(0..1), press(name), set_alarm(index or -1). Las manos van a controls[name] (Marker3D).

const TEX := "res://assets/textures/cabin/"
const ROLES := ["commander", "engineer", "systems", "comms"]
const SEAT_R := 1.42 ## distancia del centro de la mesa al asiento
const TABLE_R := 0.82
const TABLE_Y := 0.78
const SHELL_BOTTOM := 2.45
const SHELL_TOP := 1.35
const SHELL_H := 2.9

var crew := {} ## role -> Astronaut
var stations := {} ## role -> Node3D (origen en el asiento, -Z local mira al centro)
var controls := {} ## nombre -> Node3D (punto de agarre)
var annunciators: Array[MeshInstance3D] = []
var screens := {} ## role -> SubViewport
var window_mat: ShaderMaterial
var crew_outfit := "suit" ## la Sala de Control usa "controller"

var _mats := {}
var _pivots := {} ## nombre -> Node3D que gira
var _alarm := -1
var _alarm_light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	_build_room()
	for i in 4:
		_build_station(i)
	_build_role_controls()
	_build_lights()


## Espacio alrededor de los puestos (la sala de control lo reemplaza).
func _build_room() -> void:
	_build_shell()
	_build_windows()
	_build_table()
	_build_overhead()


## Dónde va el puesto i: origen en el asiento, -Z local mira a su consola.
func _station_xform(i: int) -> Transform3D:
	var a := _angle(i)
	return Transform3D(Basis(Vector3.UP, a), Vector3(sin(a), 0, cos(a)) * SEAT_R)


## Ángulo del puesto i: 45°, 135°, 225°, 315° (las ventanas quedan entre puestos).
func _angle(i: int) -> float:
	return deg_to_rad(45.0 + 90.0 * i)


# ---------- materiales ----------

func _pbr(id: String, tile := 1.0, tint := Color.WHITE, metal := false) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [id, tile, tint.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + id + "_Color.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(TEX + id + "_NormalGL.jpg")
	m.roughness_texture = load(TEX + id + "_Roughness.jpg")
	if metal and ResourceLoader.exists(TEX + id + "_Metalness.jpg"):
		m.metallic = 1.0
		m.metallic_texture = load(TEX + id + "_Metalness.jpg")
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE / tile
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


func _plain(color: Color, rough := 0.5, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO, r2 := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r if r2 < 0.0 else r2
	c.height = h
	c.radial_segments = 32
	mi.mesh = c
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _label(parent: Node3D, text: String, pos: Vector3, size := 0.012, color := Color(0.85, 0.88, 0.9)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Game.font_mono_medium
	l.pixel_size = size / 24.0
	l.font_size = 24
	l.modulate = color
	l.outline_size = 0
	l.position = pos
	l.rotation_degrees = Vector3(-90, 0, 0)
	parent.add_child(l)
	return l


func _ring(y: float, inset: float, thick: float, mat: Material) -> void:
	var r := SHELL_BOTTOM - (SHELL_BOTTOM - SHELL_TOP) * y / SHELL_H - inset
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - thick
	tm.outer_radius = r
	tm.rings = 64
	ring.mesh = tm
	ring.position = Vector3(0, y, 0)
	ring.material_override = mat
	add_child(ring)


# ---------- estructura ----------

func _build_shell() -> void:
	# Cápsula: tronco de cono, paredes de plástico blanco como Crew Dragon por dentro
	var shell := _cyl(self, SHELL_TOP, SHELL_H, Vector3(0, SHELL_H / 2.0, 0), _pbr("Plastic013A", 0.8, Color(0.9, 0.91, 0.93)), Vector3.ZERO, SHELL_BOTTOM)
	(shell.mesh as CylinderMesh).radial_segments = 64
	(shell.mesh as CylinderMesh).cap_top = false
	(shell.mesh as CylinderMesh).cap_bottom = false
	shell.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Banda de aislante acolchado abajo
	var quilt := _cyl(self, 2.12, 0.9, Vector3(0, 0.45, 0), _pbr("Fabric081C", 0.25, Color(0.78, 0.79, 0.8)), Vector3.ZERO, 2.4)
	(quilt.mesh as CylinderMesh).radial_segments = 64
	(quilt.mesh as CylinderMesh).cap_top = false
	(quilt.mesh as CylinderMesh).cap_bottom = false
	quilt.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Piso (rejilla oscura) y techo
	_cyl(self, SHELL_BOTTOM, 0.04, Vector3(0, 0.0, 0), _pbr("Plastic006", 0.6, Color(0.45, 0.46, 0.48)))
	_cyl(self, SHELL_TOP + 0.01, 0.04, Vector3(0, SHELL_H, 0), _pbr("Plastic013A", 0.8, Color(0.82, 0.83, 0.85)))
	# Costillas de aluminio a lo largo de la pared
	var slope := atan((SHELL_BOTTOM - SHELL_TOP) / SHELL_H)
	var alu := _pbr("Metal009", 0.4, Color(0.72, 0.74, 0.78), true)
	var mid_r := (SHELL_BOTTOM + SHELL_TOP) / 2.0 - 0.03
	for k in 16:
		var rib := Node3D.new()
		add_child(rib)
		rib.rotation.y = TAU * k / 16.0
		_box(rib, Vector3(0.05, 3.05, 0.035), Vector3(0, SHELL_H / 2.0, -mid_r), alu, Vector3(-rad_to_deg(slope), 0, 0))
	_ring(0.92, 0.02, 0.04, alu)
	_ring(2.25, 0.02, 0.04, alu)


func _build_windows() -> void:
	window_mat = ShaderMaterial.new()
	window_mat.shader = load("res://assets/shaders/cabin_window.gdshader")
	var frame := _pbr("Metal009", 0.3, Color(0.32, 0.33, 0.35), true)
	var y := 1.62
	var r := SHELL_BOTTOM - (SHELL_BOTTOM - SHELL_TOP) * y / SHELL_H - 0.06
	var slope := rad_to_deg(atan((SHELL_BOTTOM - SHELL_TOP) / SHELL_H))
	for k in 4:
		var pivot := Node3D.new()
		add_child(pivot)
		pivot.rotation.y = deg_to_rad(90.0 * k)
		var w := Node3D.new()
		pivot.add_child(w)
		w.position = Vector3(0, y, -r)
		w.rotation_degrees = Vector3(-slope, 0, 0)
		var glass := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.6, 0.42)
		glass.mesh = q
		glass.material_override = window_mat
		w.add_child(glass)
		for s in [[Vector3(0.68, 0.05, 0.07), Vector3(0, 0.235, 0.02)], [Vector3(0.68, 0.05, 0.07), Vector3(0, -0.235, 0.02)],
				[Vector3(0.05, 0.52, 0.07), Vector3(0.325, 0, 0.02)], [Vector3(0.05, 0.52, 0.07), Vector3(-0.325, 0, 0.02)]]:
			_box(w, s[0], s[1], frame)


func _build_table() -> void:
	var carbon := _pbr("Fabric004", 0.1, Color(0.8, 0.8, 0.85))
	var alu := _pbr("Metal009", 0.3, Color(0.75, 0.77, 0.8), true)
	# Pedestal y tablero redondo con canto de aluminio
	_cyl(self, 0.22, TABLE_Y - 0.05, Vector3(0, (TABLE_Y - 0.05) / 2.0, 0), alu, Vector3.ZERO, 0.32)
	_cyl(self, TABLE_R, 0.06, Vector3(0, TABLE_Y, 0), carbon)
	var edge := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = TABLE_R - 0.02
	tm.outer_radius = TABLE_R + 0.02
	tm.rings = 64
	edge.mesh = tm
	edge.position = Vector3(0, TABLE_Y, 0)
	edge.material_override = alu
	add_child(edge)
	# Centro: holograma de la trayectoria (anillo luminoso) para dar vida a la mesa
	var holo := MeshInstance3D.new()
	var hm := TorusMesh.new()
	hm.inner_radius = 0.2
	hm.outer_radius = 0.215
	holo.mesh = hm
	holo.name = "Holo"
	holo.position = Vector3(0, TABLE_Y + 0.12, 0)
	holo.rotation_degrees = Vector3(20, 0, 0)
	holo.material_override = _plain(Color(0.35, 0.7, 1.0), 0.2, 0.0, 2.5)
	add_child(holo)
	var globe := _cyl(self, 0.06, 0.12, Vector3(0, TABLE_Y + 0.12, 0), _plain(Color(0.2, 0.5, 0.9), 0.3, 0.0, 1.2))
	globe.mesh = SphereMesh.new()
	(globe.mesh as SphereMesh).radius = 0.06
	(globe.mesh as SphereMesh).height = 0.12


func _build_station(i: int) -> void:
	var role: String = ROLES[i]
	var a := _angle(i)
	var st := Node3D.new()
	st.name = "Station_" + role
	add_child(st)
	st.transform = _station_xform(i) # -Z local mira a su consola
	stations[role] = st
	_build_seat(st, role)
	# Consola del puesto sobre la mesa: cuña inclinada hacia el astronauta
	var desk := Node3D.new()
	desk.name = "Desk"
	st.add_child(desk)
	desk.position = Vector3(0, TABLE_Y + 0.06, -(SEAT_R - TABLE_R) - 0.16)
	desk.rotation_degrees = Vector3(-22, 0, 0)
	_box(desk, Vector3(0.62, 0.05, 0.3), Vector3(0, 0, 0), _pbr("Plastic006", 0.4, Color(0.55, 0.56, 0.6)))
	_box(desk, Vector3(0.64, 0.055, 0.02), Vector3(0, 0, 0.16), _pbr("Metal009", 0.3, Color(0.75, 0.77, 0.8), true))
	# Pantalla baja detrás de los controles (no tapa la cara del de enfrente)
	var scr := Node3D.new()
	st.add_child(scr)
	scr.position = Vector3(0, TABLE_Y + 0.2, -(SEAT_R - TABLE_R) - 0.4)
	scr.rotation_degrees = Vector3(-28, 0, 0)
	_box(scr, Vector3(0.5, 0.3, 0.03), Vector3(0, 0, -0.02), _pbr("Plastic006", 0.4, Color(0.4, 0.4, 0.44)))
	_screen(scr, role)
	# El astronauta, sentado mirando al centro
	var astro := Astronaut.new()
	astro.role = role
	astro.outfit = crew_outfit
	st.add_child(astro)
	astro.position = Vector3(0, 0, 0.0)
	astro.rotation.y = PI # el modelo mira a +Z local
	crew[role] = astro


## Pantalla del puesto: SubViewport con datos del puesto (UI 2D) como textura emisiva.
func _screen(parent: Node3D, role: String) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(480, 280)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.05, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 22
	v.offset_top = 16
	vp.add_child(v)
	var t := Label.new()
	t.text = tr("CREW_" + role.to_upper())
	t.add_theme_font_override("font", Game.font_mono_medium)
	t.add_theme_font_size_override("font_size", 28)
	t.add_theme_color_override("font_color", Astronaut.ROLE_COLORS[role])
	v.add_child(t)
	var body := Label.new()
	body.name = "Body"
	body.add_theme_font_override("font", Game.font_mono_medium)
	body.add_theme_font_size_override("font_size", 30)
	body.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	body.text = "STANDBY"
	v.add_child(body)
	screens[role] = vp
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.46, 0.27)
	q.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_texture = vp.get_texture()
	m.emission_enabled = true
	m.emission_texture = vp.get_texture()
	m.emission_energy_multiplier = 1.3
	m.roughness = 0.15
	q.material_override = m
	parent.add_child(q)


func set_screen_text(role: String, text: String) -> void:
	var vp: SubViewport = screens.get(role)
	if vp:
		(vp.find_child("Body", true, false) as Label).text = text


## Anillo de avisadores en el techo, sobre la mesa: hay que mirar hacia arriba para encontrar la alarma.
func _build_overhead() -> void:
	var oh := Node3D.new()
	oh.name = "Overhead"
	add_child(oh)
	oh.position = Vector3(0, 2.45, 0)
	var dark := _pbr("Plastic006", 0.5, Color(0.5, 0.52, 0.56))
	_cyl(oh, 0.95, 0.05, Vector3.ZERO, dark)
	_cyl(oh, 0.45, 0.06, Vector3(0, -0.01, 0), _plain(Color(0.92, 0.94, 1.0), 0.3, 0.0, 1.6)) # luz central
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var cm := CylinderMesh.new()
	cm.top_radius = 0.006
	cm.bottom_radius = 0.008
	cm.height = 0.04
	mm.mesh = cm
	mm.instance_count = 40
	for k in 40:
		var a := TAU * k / 40.0
		mm.set_instance_transform(k, Transform3D(Basis.from_euler(Vector3(0.35 if k % 3 else -0.35, 0, 0)).rotated(Vector3.UP, a), Vector3(sin(a) * 0.82, -0.045, cos(a) * 0.82)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _pbr("Metal009", 0.2, Color(0.8, 0.8, 0.82), true)
	oh.add_child(mmi)
	for k in 12:
		var a := TAU * (k + 0.5) / 12.0
		var an := _box(oh, Vector3(0.11, 0.02, 0.06), Vector3(sin(a) * 0.63, -0.035, cos(a) * 0.63), _plain(Color(0.25, 0.22, 0.12), 0.4), Vector3(0, rad_to_deg(a), 0))
		annunciators.append(an)
	_alarm_light = OmniLight3D.new()
	_alarm_light.light_color = Color(1, 0.2, 0.12)
	_alarm_light.light_energy = 0.0
	_alarm_light.omni_range = 1.2
	oh.add_child(_alarm_light)


func set_alarm(index: int) -> void:
	_alarm = index
	for k in annunciators.size():
		var on := k == index
		annunciators[k].material_override = _plain(Color(1.0, 0.18, 0.12) if on else Color(0.25, 0.22, 0.12), 0.4, 0.0, 4.0 if on else 0.0)
	if index >= 0:
		_alarm_light.position = annunciators[index].position + Vector3(0, -0.12, 0)
	_alarm_light.light_energy = 0.5 if index >= 0 else 0.0
	var mab: MeshInstance3D = _pivots.get("master_alarm_lamp")
	if mab:
		mab.material_override = _plain(Color(1, 0.1, 0.08), 0.3, 0.0, 4.0 if index >= 0 else 0.3)


func _build_seat(s: Node3D, role: String) -> void:
	var shell := _pbr("Fabric004", 0.1, Color(0.75, 0.75, 0.8))
	var cushion := _pbr("Fabric086", 0.2, Color(0.55, 0.57, 0.6))
	var alu := _pbr("Metal009", 0.3, Color(0.7, 0.72, 0.75), true)
	# Medidas tomadas de Sitting_Idle: pelvis (0; 0,54; +0,33 en el puesto), rodillas en z = -0,12,
	# pies en el piso, espalda en z ~ +0,46, hombros a 1,07 m y cabeza a 1,18 m.
	_box(s, Vector3(0.54, 0.06, 0.5), Vector3(0, 0.37, 0.22), shell) # bandeja del asiento
	_box(s, Vector3(0.48, 0.05, 0.46), Vector3(0, 0.42, 0.22), cushion) # cojín: tope a 0,445 m
	_box(s, Vector3(0.54, 0.9, 0.06), Vector3(0, 0.88, 0.55), shell, Vector3(-8, 0, 0)) # respaldo
	_box(s, Vector3(0.46, 0.78, 0.04), Vector3(0, 0.88, 0.505), cushion, Vector3(-8, 0, 0))
	_box(s, Vector3(0.3, 0.2, 0.07), Vector3(0, 1.42, 0.62), shell, Vector3(-8, 0, 0)) # cabecera
	for side in [-1, 1]:
		_box(s, Vector3(0.05, 0.16, 0.46), Vector3(side * 0.3, 0.47, 0.24), shell) # laterales del cojín
		_box(s, Vector3(0.08, 0.04, 0.36), Vector3(side * 0.34, 0.66, 0.2), alu) # apoyabrazos
		_box(s, Vector3(0.03, 0.26, 0.03), Vector3(side * 0.34, 0.53, 0.34), alu)
	_box(s, Vector3(0.14, 0.34, 0.14), Vector3(0, 0.17, 0.26), _pbr("Metal009", 0.3, Color(0.5, 0.52, 0.55), true))
	# Arnés: dos bandas del color del puesto sobre el pecho (siguen la inclinación del respaldo)
	var strap := _plain(Astronaut.ROLE_COLORS[role].darkened(0.35), 0.7)
	for side in [-1, 1]:
		_box(s, Vector3(0.045, 0.4, 0.008), Vector3(side * 0.1, 0.86, 0.335), strap, Vector3(-8, 0, side * 10))


# ---------- controles por puesto ----------

func _desk_node(role: String, x: float, z: float) -> Node3D:
	var p := Node3D.new()
	(stations[role] as Node3D).get_node("Desk").add_child(p)
	p.position = Vector3(x, 0.025, z)
	return p


func _grip(name_: String, parent: Node3D, pos: Vector3) -> Marker3D:
	var g := Marker3D.new()
	g.name = name_
	g.position = pos
	parent.add_child(g)
	controls[name_] = g
	return g


func _build_role_controls() -> void:
	var alu := _pbr("Metal009", 0.2, Color(0.82, 0.84, 0.86), true)
	var rubber := _plain(Color(0.06, 0.06, 0.07), 0.8)
	var white := _plain(Color(0.9, 0.9, 0.9), 0.5)
	# Comandante: mando de giro en el apoyabrazos derecho (+X local del puesto) y botón de GO
	var cst: Node3D = stations["commander"]
	var base := _cyl(cst, 0.045, 0.05, Vector3(0.33, 0.71, -0.02), rubber)
	var stick := Node3D.new()
	stick.position = base.position + Vector3(0, 0.03, 0)
	cst.add_child(stick)
	_pivots["stick"] = stick
	_cyl(stick, 0.012, 0.12, Vector3(0, 0.06, 0), alu)
	_cyl(stick, 0.022, 0.09, Vector3(0, 0.15, 0), rubber, Vector3.ZERO, 0.026)
	_cyl(stick, 0.008, 0.012, Vector3(0, 0.2, 0.0), _plain(Color(0.9, 0.2, 0.1), 0.4))
	_grip("stick", stick, Vector3(0, 0.15, 0.02))
	var p0 := _desk_node("commander", 0.0, 0.02)
	_box(p0, Vector3(0.12, 0.02, 0.07), Vector3.ZERO, _plain(Color(0.1, 0.8, 0.3), 0.3, 0.0, 1.5))
	_grip("go_button", p0, Vector3(0, 0.03, 0))
	_label(p0, "GO / NO-GO", Vector3(0, 0.012, 0.07))
	# Ingeniería: palanca de aceleración e interruptor con tapa
	var p1 := _desk_node("engineer", -0.16, 0.0)
	_box(p1, Vector3(0.05, 0.02, 0.24), Vector3.ZERO, rubber)
	var lever := Node3D.new()
	p1.add_child(lever)
	_pivots["throttle"] = lever
	_box(lever, Vector3(0.02, 0.16, 0.02), Vector3(0, 0.08, 0), alu)
	_box(lever, Vector3(0.1, 0.035, 0.035), Vector3(0, 0.165, 0), rubber)
	_grip("throttle", lever, Vector3(0, 0.17, 0.01))
	_label(p1, "THROTTLE", Vector3(0, 0.012, 0.13))
	var p2 := _desk_node("engineer", 0.14, 0.0)
	_box(p2, Vector3(0.08, 0.02, 0.1), Vector3.ZERO, alu)
	var tog := Node3D.new()
	p2.add_child(tog)
	_pivots["toggle"] = tog
	_cyl(tog, 0.007, 0.06, Vector3(0, 0.03, 0), alu)
	var cover := Node3D.new()
	cover.position = Vector3(0, 0.012, -0.05)
	p2.add_child(cover)
	_pivots["cover"] = cover
	_box(cover, Vector3(0.07, 0.065, 0.1), Vector3(0, 0.033, 0.05), _plain(Color(0.85, 0.1, 0.08), 0.35))
	_grip("toggle", p2, Vector3(0, 0.07, 0.02))
	_label(p2, "ARM / STAGE", Vector3(0, 0.012, 0.09))
	# Sistemas: tres válvulas, disyuntores y alarma maestra
	for k in 3:
		var pk := _desk_node("systems", -0.22 + k * 0.12, -0.05)
		var knob := Node3D.new()
		pk.add_child(knob)
		_pivots["knob%d" % k] = knob
		_cyl(knob, 0.028, 0.03, Vector3(0, 0.015, 0), rubber)
		_box(knob, Vector3(0.006, 0.004, 0.028), Vector3(0, 0.032, -0.012), white)
		_grip("knob%d" % k, pk, Vector3(0, 0.04, 0))
		_label(pk, ["O2", "FUEL", "LOX"][k], Vector3(0, 0.012, 0.05))
	var pb := _desk_node("systems", -0.1, 0.1)
	for k in 5:
		_cyl(pb, 0.009, 0.025, Vector3(-0.12 + k * 0.06, 0.012, 0), _plain(Color(0.1, 0.1, 0.1), 0.6))
	var pm := _desk_node("systems", 0.2, -0.02)
	var lamp := _box(pm, Vector3(0.09, 0.03, 0.06), Vector3.ZERO, _plain(Color(1, 0.1, 0.08), 0.3, 0.0, 0.3))
	_pivots["master_alarm_lamp"] = lamp
	_grip("master_alarm", pm, Vector3(0, 0.03, 0))
	_label(pm, "MASTER ALARM", Vector3(0, 0.012, 0.06))
	# Comunicaciones: perilla de antena y botón de confirmación
	var pa := _desk_node("comms", -0.12, -0.02)
	var ant := Node3D.new()
	pa.add_child(ant)
	_pivots["antenna"] = ant
	_cyl(ant, 0.045, 0.035, Vector3(0, 0.018, 0), alu)
	_box(ant, Vector3(0.008, 0.005, 0.04), Vector3(0, 0.037, -0.02), _plain(Color(0.65, 0.4, 1.0), 0.4, 0.0, 1.0))
	_grip("antenna", pa, Vector3(0, 0.045, 0))
	_label(pa, "ANT AIM", Vector3(0, 0.012, 0.07))
	var pr := _desk_node("comms", 0.14, -0.02)
	_cyl(pr, 0.04, 0.03, Vector3(0, 0.015, 0), _plain(Color(0.15, 0.85, 0.35), 0.3, 0.0, 1.2))
	_grip("readback", pr, Vector3(0, 0.035, 0))
	_label(pr, "READBACK", Vector3(0, 0.012, 0.07))


func _build_lights() -> void:
	var top := OmniLight3D.new()
	top.position = Vector3(0, 2.3, 0)
	top.light_color = Color(1.0, 0.97, 0.92)
	top.light_energy = 1.6
	top.omni_range = 4.5
	top.shadow_enabled = true
	add_child(top)
	var table_glow := OmniLight3D.new()
	table_glow.position = Vector3(0, TABLE_Y + 0.35, 0)
	table_glow.light_color = Color(0.55, 0.75, 1.0)
	table_glow.light_energy = 0.6
	table_glow.omni_range = 1.8
	add_child(table_glow)
	# Una luz suave sobre cada asiento para que se vean las caras
	for i in 4:
		var a := _angle(i)
		var l := OmniLight3D.new()
		l.position = Vector3(sin(a), 0, cos(a)) * (SEAT_R - 0.5) + Vector3(0, 1.9, 0)
		l.light_energy = 0.5
		l.omni_range = 1.6
		add_child(l)


# ---------- mover los controles ----------

func set_stick(v: Vector2) -> void:
	var s: Node3D = _pivots.get("stick")
	if s:
		s.rotation = Vector3(v.y * 0.35, 0, -v.x * 0.35)


func set_throttle(f: float) -> void:
	var l: Node3D = _pivots.get("throttle")
	if l:
		l.rotation.x = lerpf(0.5, -0.5, clampf(f, 0.0, 1.0))


func set_cover(open: bool) -> void:
	var c: Node3D = _pivots.get("cover")
	if c:
		create_tween().tween_property(c, "rotation:x", -1.9 if open else 0.0, 0.2)


func set_toggle(on: bool) -> void:
	var t: Node3D = _pivots.get("toggle")
	if t:
		create_tween().tween_property(t, "rotation:x", -0.5 if on else 0.5, 0.08)


func set_knob(i: int, f: float) -> void:
	var k: Node3D = _pivots.get("knob%d" % i)
	if k:
		k.rotation.y = lerpf(2.3, -2.3, clampf(f, 0.0, 1.0))


func set_antenna(f: float) -> void:
	var k: Node3D = _pivots.get("antenna")
	if k:
		k.rotation.y = lerpf(2.6, -2.6, clampf(f, 0.0, 1.0))


## Botón que se hunde un instante.
func press(name_: String) -> void:
	var g: Node3D = controls.get(name_)
	if g == null:
		return
	var p := g.get_parent() as Node3D
	var y0 := p.position.y
	var tw := create_tween()
	tw.tween_property(p, "position:y", y0 - 0.008, 0.05)
	tw.tween_property(p, "position:y", y0, 0.1)


## Punto de vista del asiento (ojos del astronauta sentado), mirando un poco hacia abajo a su consola.
func eye_of(role: String) -> Transform3D:
	var st: Node3D = stations.get(role)
	if st == null:
		return Transform3D.IDENTITY
	return st.global_transform * Transform3D(Basis.from_euler(Vector3(deg_to_rad(-16), 0, 0)), Vector3(0, 1.3, -0.02))


func _process(delta: float) -> void:
	_t += delta
	if _alarm >= 0:
		_alarm_light.light_energy = 0.3 + 0.4 * absf(sin(_t * 6.0))
	var holo := get_node_or_null("Holo") as Node3D
	if holo:
		holo.rotation.y += delta * 0.6
