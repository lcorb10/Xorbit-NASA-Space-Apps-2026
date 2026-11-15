class_name ContractCinematic
extends Control
## Animación del contrato al empezar una partida nueva (docs/TRIPULACION.md §11):
##   1. Sala de Control: Houston da la bienvenida.
##   2. Cabina: la cámara recorre la mesa; cada astronauta saluda y aparece su ficha (nombre, puesto, especialidad).
##   3. Contrato XORBIT: el papel se despliega, el texto se escribe solo, firma animada con el nombre de la partida y sello.
## Se salta con el botón, Espacio, Esc o B. Al terminar emite finished.

signal finished

const ROLES := ["commander", "engineer", "systems", "comms"]
const T_ROOM := 6.0
const T_CREW := 2.6 ## por astronauta

var _t := 0.0
var _act := 1
var _vp: SubViewport
var _room: MissionControl
var _cabin: CrewCabin
var _cam: Camera3D
var _card: PanelContainer
var _card_name: Label
var _card_role: Label
var _card_spec: Label
var _caption: Label
var _portrait: HoustonPortrait ## Houston hablando en un círculo, abajo a la izquierda
var _paper: PanelContainer
var _paper_text: Label
var _sign: Label
var _stamp: Label
var _accept: Button
var _crew_i := -1
var _voice: AudioStreamPlayer
var _done := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("modal")
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
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.environment.ambient_light_energy = 0.4
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment.glow_enabled = true
	_vp.add_child(env)
	_room = MissionControl.new()
	_vp.add_child(_room)
	_cabin = CrewCabin.new()
	_cabin.position = Vector3(0, 0, 200) # lejos de la sala; se muestra en el acto 2
	_cabin.visible = false
	_vp.add_child(_cabin)
	_cam = Camera3D.new()
	_cam.fov = 60
	_vp.add_child(_cam)
	_cam.current = true
	_build_overlay()
	_voice = AudioStreamPlayer.new()
	add_child(_voice)
	_say("contract_welcome")


func _say(id: String) -> void:
	var line: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/comms.json")) as Dictionary).get("crew", {}).get(id, {})
	_caption.text = Codex.pick(line)
	var path := "res://assets/voice/en/%s.ogg" % id
	if ResourceLoader.exists(path) and HoustonRadio.voice_on():
		_voice.stream = load(path)
		_voice.play()


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
	# Subtítulo de Houston abajo
	_caption = Label.new()
	_caption.theme_type_variation = "Body"
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.anchor_left = 0.15
	_caption.anchor_right = 0.85
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	_caption.offset_top = -110
	_caption.offset_bottom = -40
	_caption.add_theme_font_size_override("font_size", 19)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 8)
	_caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_caption)
	_portrait = HoustonPortrait.new(150)
	_portrait.anchor_top = 1.0
	_portrait.anchor_bottom = 1.0
	_portrait.offset_left = 24
	_portrait.offset_right = 24 + 150
	_portrait.offset_top = -24 - 150
	_portrait.offset_bottom = -24
	add_child(_portrait)
	# Ficha del astronauta
	_card = PanelContainer.new()
	_card.theme_type_variation = "Sheet"
	_card.anchor_left = 1.0
	_card.anchor_right = 1.0
	_card.offset_left = -440
	_card.offset_right = -40
	_card.offset_top = 140
	_card.modulate.a = 0.0
	add_child(_card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 4)
	_card.add_child(cv)
	var eb := Label.new()
	eb.text = "CC_CREW_MEMBER"
	eb.theme_type_variation = "Eyebrow"
	cv.add_child(eb)
	_card_name = Label.new()
	_card_name.theme_type_variation = "Title"
	_card_name.add_theme_font_size_override("font_size", 44)
	_card_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	cv.add_child(_card_name)
	_card_role = Label.new()
	_card_role.theme_type_variation = "Eyebrow"
	_card_role.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	cv.add_child(_card_role)
	_card_spec = Label.new()
	_card_spec.theme_type_variation = "Body"
	_card_spec.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_spec.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	cv.add_child(_card_spec)
	# El contrato (papel claro sobre la escena)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_paper = PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.95, 0.93, 0.87)
	ps.set_corner_radius_all(4)
	ps.set_content_margin_all(36)
	ps.shadow_color = Color(0, 0, 0, 0.5)
	ps.shadow_size = 18
	_paper.add_theme_stylebox_override("panel", ps)
	_paper.custom_minimum_size = Vector2(720, 0)
	_paper.visible = false
	_paper.pivot_offset = Vector2(360, 0)
	center.add_child(_paper)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	_paper.add_child(pv)
	var head := Label.new()
	head.text = "CC_TITLE"
	head.theme_type_variation = "Title"
	head.add_theme_font_size_override("font_size", 34)
	head.add_theme_color_override("font_color", Color(0.1, 0.12, 0.18))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(head)
	var line := ColorRect.new()
	line.custom_minimum_size.y = 2
	line.color = Color(0.85, 0.45, 0.12)
	pv.add_child(line)
	_paper_text = Label.new()
	_paper_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_paper_text.add_theme_font_override("font", Game.font_mono_medium)
	_paper_text.add_theme_font_size_override("font_size", 16)
	_paper_text.add_theme_color_override("font_color", Color(0.12, 0.13, 0.16))
	_paper_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_paper_text.visible_ratio = 0.0
	var names := []
	for r in ROLES:
		names.append("%s %s" % [tr("CC_ROLE_" + r.to_upper()), Astronaut.NAMES[r]])
	_paper_text.text = tr("CC_BODY") % [", ".join(names)]
	pv.add_child(_paper_text)
	var sign_row := HBoxContainer.new()
	sign_row.add_theme_constant_override("separation", 16)
	pv.add_child(sign_row)
	var sv := VBoxContainer.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sign_row.add_child(sv)
	_sign = Label.new()
	var who := str(Game.progress.get("name", ""))
	_sign.text = who if who != "" else tr("CC_SIGN_DEFAULT")
	_sign.theme_type_variation = "Title"
	_sign.add_theme_font_size_override("font_size", 38)
	_sign.add_theme_color_override("font_color", Color(0.1, 0.2, 0.55))
	_sign.visible_ratio = 0.0
	_sign.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	sv.add_child(_sign)
	var sl := ColorRect.new()
	sl.custom_minimum_size = Vector2(300, 2)
	sl.color = Color(0.2, 0.2, 0.25)
	sv.add_child(sl)
	var sc := Label.new()
	sc.text = "CC_SIGNATURE"
	sc.add_theme_font_size_override("font_size", 12)
	sc.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4))
	sv.add_child(sc)
	_stamp = Label.new()
	_stamp.text = "CC_STAMP"
	_stamp.theme_type_variation = "Title"
	_stamp.add_theme_font_size_override("font_size", 40)
	_stamp.add_theme_color_override("font_color", Color(0.8, 0.15, 0.12))
	_stamp.rotation_degrees = -12
	_stamp.modulate.a = 0.0
	sign_row.add_child(_stamp)
	_accept = Button.new()
	_accept.text = "CC_ACCEPT"
	_accept.theme_type_variation = "Primary"
	_accept.custom_minimum_size.y = 46
	_accept.modulate.a = 0.0
	_accept.disabled = true
	_accept.pressed.connect(_end)
	pv.add_child(_accept)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_portrait.talking = _voice.playing
	match _act:
		1:
			# El acto dura lo que dure la bienvenida de Houston (no se corta la voz)
			var room_len := maxf(T_ROOM, (_voice.stream.get_length() + 0.6) if _voice.stream and HoustonRadio.voice_on() else 0.0)
			var k := clampf(_t / room_len, 0.0, 1.0)
			_cam.position = Vector3(lerpf(4.0, -1.0, k), lerpf(3.6, 2.4, k), lerpf(10.0, 3.0, k))
			_cam.look_at(Vector3(-3.0, 2.4, -8.7))
			if _t >= room_len and not _voice.playing:
				_act = 2
				_t = 0.0
				_room.visible = false
				_cabin.visible = true
				_say("contract_crew")
		2:
			var i := int(_t / T_CREW)
			if i >= ROLES.size() and _voice.playing:
				i = ROLES.size() - 1 # espera a que Houston termine antes de abrir el contrato
			elif i >= ROLES.size():
				_act = 3
				_t = 0.0
				_open_contract()
				return
			if i != _crew_i:
				_crew_i = i
				_present(ROLES[i])
			# La cámara mira desde el centro de la mesa al astronauta que se presenta
			var st: Node3D = _cabin.stations[ROLES[i]]
			var face := st.global_transform * Vector3(0, 1.3, 0.05)
			var from := _cabin.global_transform * Vector3(0, 1.45, 0) + (face - _cabin.global_position).normalized() * 0.15
			var k := clampf(fmod(_t, T_CREW) / T_CREW, 0.0, 1.0)
			_cam.global_position = from.lerp(face.lerp(from, 0.55), k * 0.3)
			_cam.look_at(face, Vector3.UP)
		3:
			_paper_text.visible_ratio = clampf((_t - 0.6) / 5.0, 0.0, 1.0)
			_sign.visible_ratio = clampf((_t - 6.0) / 1.4, 0.0, 1.0)
			if _t > 7.6 and _stamp.modulate.a == 0.0:
				_stamp.modulate.a = 1.0
				_stamp.scale = Vector2.ONE * 2.2
				create_tween().tween_property(_stamp, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if _t > 8.2 and _accept.disabled:
				_accept.disabled = false
				create_tween().tween_property(_accept, "modulate:a", 1.0, 0.3)
				_accept.grab_focus()


func _present(role: String) -> void:
	var a: Astronaut = _cabin.crew[role]
	a.emote("wave")
	var c: Color = Astronaut.ROLE_COLORS[role]
	_card_name.text = Astronaut.NAMES[role]
	_card_name.add_theme_color_override("font_color", c)
	_card_role.text = tr("CREW_" + role.to_upper())
	_card_spec.text = tr("CC_SPEC_" + role.to_upper())
	_card.modulate.a = 0.0
	_card.position.x += 60
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_card, "modulate:a", 1.0, 0.3)
	tw.tween_property(_card, "position:x", _card.position.x - 60, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _open_contract() -> void:
	_card.visible = false
	_say("contract_sign")
	_paper.visible = true
	_paper.scale = Vector2(1, 0.02)
	create_tween().tween_property(_paper, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _unhandled_input(event: InputEvent) -> void:
	var skip: bool = (event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE]) \
		or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B)
	if skip:
		_end()
		get_viewport().set_input_as_handled()


func _end() -> void:
	if _done:
		return
	_done = true
	_voice.stop()
	finished.emit()
	queue_free()
