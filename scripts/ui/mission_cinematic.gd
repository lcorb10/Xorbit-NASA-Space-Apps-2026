class_name MissionCinematic
extends Control
## Cinemática del encargo (antes de construir): Houston cuenta la misión desde la Sala de Control y la
## cámara corta al destino con el objetivo, el cliente y los requisitos. Se salta con el botón, Espacio,
## Esc o B del mando. Houston aparece en un círculo hablando (retrato en vivo, abajo a la izquierda).

signal finished

const DEST := ["earth", "earth", "earth", "moon", "moon", "mars", "mars", "jupiter", "neptune", "neptune"]
const TEX := {"earth": "res://assets/textures/nasa/earth_day.jpg", "moon": "res://assets/textures/planets/2k_moon.jpg",
	"mars": "res://assets/textures/planets/2k_mars.jpg", "jupiter": "res://assets/textures/planets/2k_jupiter.jpg",
	"neptune": "res://assets/textures/planets/2k_neptune.jpg"}
const SHOT1_MIN := 7.0

var mission := 0

var _t := 0.0
var _shot := 1
var _shot1_len := SHOT1_MIN
var _vp: SubViewport
var _room: MissionControl
var _cam: Camera3D
var _planet_root: Node3D
var _planet: MeshInstance3D
var _text: Label
var _cards: VBoxContainer
var _voice: AudioStreamPlayer
var _portrait: HoustonPortrait
var _done := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := SubViewportContainer.new()
	box.stretch = true
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	box.add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.01, 0.01, 0.02)
	env.environment.ambient_light_color = Color(0.7, 0.75, 0.85)
	env.environment.ambient_light_energy = 0.4
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment.glow_enabled = true
	_vp.add_child(env)
	_room = MissionControl.new()
	_vp.add_child(_room)
	_cam = Camera3D.new()
	_cam.fov = 60
	_vp.add_child(_cam)
	_cam.current = true
	_build_planet()
	_build_overlay()
	_build_portrait()
	_voice = AudioStreamPlayer.new()
	add_child(_voice)
	var m: Dictionary = MissionBrief.data().get("missions", {}).get(str(mission), {})
	var story: Dictionary = m.get("story", {})
	_text.text = Codex.pick(story)
	var path := "res://assets/voice/en/story_%d.ogg" % mission
	if ResourceLoader.exists(path) and HoustonRadio.voice_on():
		_voice.stream = load(path)
		_voice.play()
		_shot1_len = maxf(SHOT1_MIN, _voice.stream.get_length() + 0.8)
	else:
		_shot1_len = clampf(_text.text.length() * 0.055, SHOT1_MIN, 16.0)


func _build_planet() -> void:
	_planet_root = Node3D.new()
	_planet_root.visible = false
	_planet_root.position = Vector3(0, 0, -500)
	_vp.add_child(_planet_root)
	var stars := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 300.0
	sm.height = 600.0
	stars.mesh = sm
	var stm := StandardMaterial3D.new()
	stm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stm.albedo_texture = load("res://assets/textures/planets/8k_stars_milky_way.jpg")
	stm.cull_mode = BaseMaterial3D.CULL_FRONT
	stars.material_override = stm
	_planet_root.add_child(stars)
	_planet = MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 3.0
	pm.height = 6.0
	pm.radial_segments = 96
	pm.rings = 48
	_planet.mesh = pm
	var mat := StandardMaterial3D.new()
	var d: String = DEST[clampi(mission, 0, DEST.size() - 1)]
	mat.albedo_texture = load(TEX[d])
	mat.roughness = 0.9
	_planet.material_override = mat
	_planet.position = Vector3(2.2, 0, 0)
	_planet_root.add_child(_planet)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-15, -60, 0)
	sun.light_energy = 1.6
	_planet_root.add_child(sun)


func _build_overlay() -> void:
	var skip := Button.new()
	skip.text = "CN_SKIP"
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	skip.offset_left = -170
	skip.offset_right = -28
	skip.offset_top = 28
	skip.offset_bottom = 72
	skip.pressed.connect(_end)
	add_child(skip)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Sheet"
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 230
	panel.offset_right = 230 + 760
	panel.offset_bottom = -36
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var m: Dictionary = MissionBrief.data().get("missions", {}).get(str(mission), {})
	var eb := Label.new()
	eb.text = (tr("MB_JOB") % mission) + " · " + Codex.pick(m.get("client", {})).to_upper()
	eb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	eb.theme_type_variation = "Eyebrow"
	eb.add_theme_color_override("font_color", Game.MARK)
	v.add_child(eb)
	var title := Label.new()
	title.text = tr("LEVEL_%d_NAME" % mission)
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.theme_type_variation = "Title"
	title.add_theme_font_size_override("font_size", 40)
	v.add_child(title)
	_text = Label.new()
	_text.theme_type_variation = "Body"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_text.add_theme_font_size_override("font_size", 17)
	_text.visible_ratio = 0.0
	v.add_child(_text)
	_cards = VBoxContainer.new()
	_cards.visible = false
	v.add_child(_cards)
	var goal := Label.new()
	goal.text = Codex.pick(m.get("goal", {}))
	goal.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	goal.theme_type_variation = "Body"
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal.add_theme_color_override("font_color", Game.MARK)
	goal.add_theme_font_size_override("font_size", 18)
	_cards.add_child(goal)
	var lv := Game.level(mission)
	var req := Label.new()
	req.text = tr("MB_REQ_LINE") % [Game.fmt(float(lv.get("dv_km_s", 0.0)), 1), Game.budget_text(lv), int(Probe.destination(mission).get("payload_min_kg", 0))]
	req.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	req.theme_type_variation = "Body"
	req.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cards.add_child(req)
	var go := Button.new()
	go.text = "CN_START"
	go.theme_type_variation = "Primary"
	go.custom_minimum_size.y = 44
	go.pressed.connect(_end)
	_cards.add_child(go)


## Retrato de Houston en un círculo (su cara MakeHuman con la boca moviéndose mientras habla).
func _build_portrait() -> void:
	_portrait = HoustonPortrait.new(176)
	_portrait.anchor_top = 1.0
	_portrait.anchor_bottom = 1.0
	_portrait.offset_left = 36
	_portrait.offset_right = 36 + 176
	_portrait.offset_top = -36 - 176
	_portrait.offset_bottom = -36
	add_child(_portrait)
	var name_lbl := Label.new()
	name_lbl.text = "HOUSTON"
	name_lbl.theme_type_variation = "Eyebrow"
	name_lbl.add_theme_color_override("font_color", Game.MARK)
	name_lbl.anchor_top = 1.0
	name_lbl.anchor_bottom = 1.0
	name_lbl.offset_left = 92
	name_lbl.offset_top = -30
	add_child(name_lbl)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_portrait.talking = _voice.playing or (_shot == 1 and _text.visible_ratio < 1.0)
	if _shot == 1:
		# Plano 1: la cámara avanza entre las consolas hacia la pantalla grande
		var k := clampf(_t / _shot1_len, 0.0, 1.0)
		_cam.position = Vector3(lerpf(3.5, -2.5, k), lerpf(3.4, 2.6, k), lerpf(9.0, 1.0, k))
		_cam.look_at(Vector3(-3.0, 2.6, -8.7))
		_text.visible_ratio = clampf(_t / (_shot1_len * 0.8), 0.0, 1.0)
		if _room.wall_mat:
			_room.wall_mat.set_shader_parameter("progress", k * 0.6)
		if _t >= _shot1_len:
			_shot = 2
			_t = 0.0
			_room.visible = false
			_planet_root.visible = true
			_cards.visible = true
			(_cards.get_child(_cards.get_child_count() - 1) as Button).grab_focus() # A del mando empieza
			_text.visible_ratio = 1.0
	else:
		# Plano 2: el destino gira con las estrellas detrás
		_cam.position = _planet_root.position + Vector3(0, 0.4, 9.5 - minf(_t * 0.15, 1.5))
		_cam.look_at(_planet_root.position + Vector3(0.6, 0, 0))
		_planet.rotation.y += delta * 0.08


func _unhandled_input(event: InputEvent) -> void:
	var skip: bool = (event is InputEventKey and event.pressed and event.keycode in [KEY_SPACE, KEY_ESCAPE, KEY_ENTER]) \
		or (event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_B, JOY_BUTTON_A])
	if skip:
		if _shot == 1:
			_t = _shot1_len # primero salta al destino; otra vez cierra
		else:
			_end()
		get_viewport().set_input_as_handled()


func _end() -> void:
	if _done:
		return
	_done = true
	_voice.stop()
	finished.emit()
	queue_free()
