class_name CrewView
extends Control
## Vista de la tripulación en primera persona (ver docs/TRIPULACION.md).
## - La cabina vive en su propio mundo 3D (SubViewport con own_world_3d): no la afectan las luces del vuelo.
## - set_active(role): la cámara salta de casco a casco por encima de la mesa (JUMP_S) y aparece el cartel
##   "TU TURNO · PUESTO · JUGADOR N". El que tiene el reto mira libre (mouse o stick derecho, con límite de cuello)
##   y su cabeza gira igual (los demás ven hacia dónde mira). Los otros astronautas lo miran.
## - Emotes: la cruceta de cada mando (o F1-F4 en el teclado) hace el emote del astronauta de ese jugador.
## - react(kind): un compañero que no es del jugador activo hace un emote (tripulación automática).
## players: [{"name": "P1", "device": -1 (teclado) o índice del mando, "roles": ["commander", ...]}]

signal jumped(role: String)
signal handoff_done

const JUMP_S := 0.9
const YAW_LIMIT := deg_to_rad(80.0)
const PITCH_UP := deg_to_rad(65.0)
const PITCH_DOWN := deg_to_rad(-45.0)
const MOUSE_SENS := 0.0025
const STICK_SPEED := 2.4
const EMOTE_BY_DPAD := {JOY_BUTTON_DPAD_UP: "wave", JOY_BUTTON_DPAD_RIGHT: "thumbs", JOY_BUTTON_DPAD_DOWN: "hurry", JOY_BUTTON_DPAD_LEFT: "panic"}
const EMOTE_BY_KEY := {KEY_F1: "wave", KEY_F2: "thumbs", KEY_F3: "hurry", KEY_F4: "panic"}

var players: Array = [{"name": "P1", "device": -1, "roles": ["commander", "engineer", "systems", "comms"]}]
var active_role := "commander"
var room := "cabin" ## cabin (misión tripulada) o mcc (Sala de Control, no tripulada)
var look_enabled := true
var shake := 0.0 ## turbulencia 0..1 (max-Q, separación): la cámara tiembla y los mandos vibran
var cabin: CrewCabin
var cam: Camera3D
var viewport: SubViewport

var _yaw := 0.0
## Pantalla partida: dos jugadores con reto a la vez. La mitad derecha es la vista del segundo puesto
## (otra cámara en el mismo mundo de la cabina).
var split_role := ""
var viewport2: SubViewport
var cam2: Camera3D
var _box: SubViewportContainer
var _box2: SubViewportContainer
var _divider: ColorRect
var _split_tag: Label
var _pitch := 0.0
var _jump_t := 1.0
var _from := Transform3D.IDENTITY
var _banner: PanelContainer
var _flash: ColorRect
var _frame: Panel
var _frame_sb: StyleBoxFlat
var _banner_title: Label
var _banner_sub: Label
var _banner_bar: ColorRect
var _rng := RandomNumberGenerator.new()
var _ai_emote_t := 10.0


func _ready() -> void:
	_rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := SubViewportContainer.new()
	_box = box
	box.stretch = true
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	box.add_child(viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.02, 0.02, 0.03)
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.environment.ambient_light_energy = 0.35
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment.ssao_enabled = true
	env.environment.glow_enabled = true
	viewport.add_child(env)
	cabin = MissionControl.new() if room == "mcc" else CrewCabin.new()
	viewport.add_child(cabin)
	cam = Camera3D.new()
	cam.fov = 78
	cam.near = 0.03
	viewport.add_child(cam)
	cam.current = true
	_build_banner()
	# Rueda de emotes chiquita abajo a la izquierda (T / clic / L1 + stick derecho)
	var wheel := EmoteWheel.new()
	add_child(wheel)
	wheel.picked.connect(_player_emote)
	_enter_seat.call_deferred(active_role)
	# Oculta no se dibuja: la cabina y sus pantallas dejan de gastar la tarjeta de video
	visibility_changed.connect(_on_visibility)
	_on_visibility()


func _build_banner() -> void:
	# Destello de pantalla completa y marco del color del jugador que tiene el turno
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	add_child(_flash)
	_frame = Panel.new()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_sb = StyleBoxFlat.new()
	_frame_sb.draw_center = false
	_frame_sb.set_border_width_all(10)
	_frame_sb.border_color = Color(1, 1, 1, 0)
	_frame.add_theme_stylebox_override("panel", _frame_sb)
	add_child(_frame)
	_banner = PanelContainer.new()
	_banner.theme_type_variation = "Sheet"
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.offset_top = 36
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	add_child(_banner)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_banner.add_child(v)
	_banner_bar = ColorRect.new()
	_banner_bar.custom_minimum_size = Vector2(0, 5)
	v.add_child(_banner_bar)
	_banner_title = Label.new()
	_banner_title.theme_type_variation = "Title"
	_banner_title.add_theme_font_size_override("font_size", 46)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.text = "CREW_YOUR_TURN"
	v.add_child(_banner_title)
	_banner_sub = Label.new()
	_banner_sub.theme_type_variation = "Eyebrow"
	_banner_sub.add_theme_font_size_override("font_size", 18)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(_banner_sub)


func _on_visibility() -> void:
	var mode := SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	viewport.render_target_update_mode = mode
	for r in cabin.screens:
		(cabin.screens[r] as SubViewport).render_target_update_mode = mode


## Tutorial de la tripulación: tarjeta con lo esencial antes del primer reto. done() se llama al cerrarla.
func show_intro(done: Callable) -> void:
	var veil := ColorRect.new()
	veil.color = Color(Game.PAPER_DEEP, 0.55)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.add_to_group("modal")
	add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.add_child(center)
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = "Sheet"
	sheet.custom_minimum_size.x = 760
	center.add_child(sheet)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	sheet.add_child(v)
	var key := "MCC" if room == "mcc" else "CABIN"
	var eb := Label.new()
	eb.text = "CT_EYEBROW"
	eb.theme_type_variation = "Eyebrow"
	eb.add_theme_color_override("font_color", Game.MARK)
	v.add_child(eb)
	var t := Label.new()
	t.text = "CT_TITLE_" + key
	t.theme_type_variation = "Title"
	t.add_theme_font_size_override("font_size", 40)
	v.add_child(t)
	for k in ["CT_BODY_" + key, "CT_ROLES", "CT_TURNS"]:
		var b := Label.new()
		b.text = k
		b.theme_type_variation = "Body"
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 16)
		v.add_child(b)
	# Puestos con su color
	var roles := HBoxContainer.new()
	roles.add_theme_constant_override("separation", 14)
	for r in ["commander", "engineer", "systems", "comms"]:
		var l := Label.new()
		l.text = "CREW_" + r.to_upper()
		l.theme_type_variation = "Eyebrow"
		l.add_theme_color_override("font_color", Astronaut.ROLE_COLORS[r])
		roles.add_child(l)
	v.add_child(roles)
	# Controles por tipo de reto
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	for row in [["CT_K_WHAT", "CT_K_KB", "CT_K_PAD"], ["CT_K_ACTION", "CT_K_ACTION_KB", "CT_K_ACTION_PAD"],
			["CT_K_NEEDLE", "CT_K_NEEDLE_KB", "CT_K_NEEDLE_PAD"], ["CT_K_SEQ", "CT_K_SEQ_KB", "CT_K_SEQ_PAD"],
			["CT_K_LOOK", "CT_K_LOOK_KB", "CT_K_LOOK_PAD"], ["CT_K_EMOTE", "CT_K_EMOTE_KB", "CT_K_EMOTE_PAD"]]:
		for j in 3:
			var c := Label.new()
			c.text = row[j]
			c.theme_type_variation = "Eyebrow" if j == 0 or row[0] == "CT_K_WHAT" else "Body"
			c.add_theme_font_size_override("font_size", 13 if j > 0 else 12)
			grid.add_child(c)
	v.add_child(grid)
	var ok := Button.new()
	ok.text = "CT_OK"
	ok.theme_type_variation = "Primary"
	ok.custom_minimum_size.y = 46
	v.add_child(ok)
	ok.grab_focus.call_deferred()
	ok.pressed.connect(func() -> void:
		veil.queue_free()
		done.call())


## Jugador que maneja un puesto (índice en players) o -1 si lo cubre el piloto automático.
## Silla caliente: varios jugadores comparten el teclado. Cuando el turno pasa a otro jugador de teclado,
## un cartel de su color pide pasarle el teclado y espera a que pulse Espacio.
var _last_kb := -1


func needs_handoff(p: int) -> bool:
	if p < 0 or int(players[p].device) >= 0 or "--crewai" in OS.get_cmdline_user_args():
		return false
	var kb := players.filter(func(pl: Dictionary) -> bool: return int(pl.device) < 0).size()
	if kb < 2:
		return false
	if _last_kb == -1:
		_last_kb = p
		return false
	return _last_kb != p


func show_handoff(p: int) -> void:
	_last_kb = p
	var roles: Array = players[p].roles
	var c: Color = Astronaut.ROLE_COLORS[roles[0]]
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.04, 0.08, 0.92)
	sb.set_border_width_all(6)
	sb.border_color = c
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(28)
	card.add_theme_stylebox_override("panel", sb)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	var t := Label.new()
	t.text = (tr("CREW_PLAYER") % (p + 1)).to_upper()
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	t.theme_type_variation = "Title"
	t.add_theme_font_size_override("font_size", 54)
	t.add_theme_color_override("font_color", c)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := Label.new()
	s.text = "CREW_HANDOFF"
	s.theme_type_variation = "Body"
	s.add_theme_font_size_override("font_size", 20)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	add_child(card)
	_flash.color = Color(c, 0.5)
	create_tween().tween_property(_flash, "color", Color(c, 0.0), 0.6)
	# Espera una pulsación nueva (no la tecla que quedó apretada del reto anterior)
	var held := true
	while true:
		await get_tree().process_frame
		var down := Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_ENTER)
		if not down:
			held = false
		elif not held:
			break
	card.queue_free()
	handoff_done.emit()


func set_split(role: String) -> void:
	split_role = role
	if is_inside_tree():
		_update_heads.call_deferred()
	if role == "":
		_box.anchor_right = 1.0
		if _box2:
			_box2.visible = false
			_divider.visible = false
			_split_tag.visible = false
			viewport2.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if viewport2 == null:
		_box2 = SubViewportContainer.new()
		_box2.stretch = true
		_box2.anchor_left = 0.5
		_box2.anchor_right = 1.0
		_box2.anchor_bottom = 1.0
		_box2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_box2)
		move_child(_box2, 1)
		viewport2 = SubViewport.new()
		viewport2.world_3d = viewport.find_world_3d()
		viewport2.msaa_3d = Viewport.MSAA_2X
		_box2.add_child(viewport2)
		cam2 = Camera3D.new()
		cam2.fov = 78
		cam2.near = 0.03
		viewport2.add_child(cam2)
		cam2.current = true
		_divider = ColorRect.new()
		_divider.anchor_left = 0.5
		_divider.anchor_right = 0.5
		_divider.anchor_bottom = 1.0
		_divider.offset_left = -3
		_divider.offset_right = 3
		_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_divider)
		_split_tag = Label.new()
		_split_tag.theme_type_variation = "Title"
		_split_tag.add_theme_font_size_override("font_size", 26)
		_split_tag.anchor_left = 0.5
		_split_tag.anchor_right = 1.0
		_split_tag.offset_top = 150
		_split_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_split_tag.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_split_tag.add_theme_color_override("font_outline_color", Color.BLACK)
		_split_tag.add_theme_constant_override("outline_size", 8)
		add_child(_split_tag)
	var c: Color = Astronaut.ROLE_COLORS[role]
	var p := player_of(role)
	_box.anchor_right = 0.5
	_box2.visible = true
	_divider.visible = true
	_divider.color = c
	_split_tag.visible = true
	_split_tag.text = ((tr("CREW_PLAYER") % (p + 1)) if p >= 0 else tr("CREW_AUTOPILOT")).to_upper() + "  ·  " + Astronaut.NAMES[role].to_upper()
	_split_tag.add_theme_color_override("font_color", c)
	viewport2.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var e2 := cabin.eye_of(role)
	cam2.global_transform = e2
	cam2.global_position -= e2.basis.z * 0.2
	_update_heads()
	if p >= 0 and int(players[p].device) >= 0:
		Input.start_joy_vibration(int(players[p].device), 0.2, 0.5, 0.25)
		if Input.has_joy_light(int(players[p].device)):
			Input.set_joy_light(int(players[p].device), c)


func player_of(role: String) -> int:
	for i in players.size():
		if role in players[i].roles:
			return i
	return -1


func _enter_seat(role: String) -> void:
	active_role = role
	_yaw = 0.0
	_pitch = 0.0
	_jump_t = 1.0
	cam.global_transform = cabin.eye_of(role)
	_update_heads()


## Salta al puesto `role` con la animación de cámara y el cartel del turno.
func set_active(role: String, instant := false) -> void:
	if not cabin.crew.has(role):
		return
	if instant or not is_inside_tree():
		_enter_seat(role)
		return
	(cabin.crew[active_role] as Astronaut).set_head_visible(true)
	_from = cam.global_transform
	active_role = role
	_yaw = 0.0
	_pitch = 0.0
	_jump_t = 0.0
	_show_banner(role)
	_update_heads()


func _show_banner(role: String) -> void:
	var c: Color = Astronaut.ROLE_COLORS[role]
	var p := player_of(role)
	var who := (tr("CREW_PLAYER") % (p + 1)) if p >= 0 else tr("CREW_AUTOPILOT")
	# Destello del color del jugador al saltar y marco de ese color mientras dure su turno
	var fl := create_tween()
	fl.tween_property(_flash, "color", Color(c, 0.6), 0.08)
	fl.tween_property(_flash, "color", Color(c, 0.0), 0.55)
	create_tween().tween_property(_frame_sb, "border_color", Color(c, 0.9), 0.3)
	if players.size() > 1 and p >= 0:
		# Con varios jugadores, el número del jugador va en grande: así se sabe a quién le toca
		_banner_title.text = who.to_upper()
		_banner_title.add_theme_color_override("font_color", c)
		_banner_sub.text = "%s  ·  %s %s" % [tr("CREW_YOUR_TURN"), tr("CREW_" + role.to_upper()), Astronaut.NAMES[role].to_upper()]
		_banner_sub.add_theme_color_override("font_color", c)
		_banner_bar.color = c
		_banner_tween()
		_pad_feedback(p, c)
		return
	_banner_sub.text = "%s %s  ·  %s" % [tr("CREW_" + role.to_upper()), Astronaut.NAMES[role].to_upper(), who]
	_banner_sub.add_theme_color_override("font_color", c)
	_banner_bar.color = c
	_banner_title.text = "CREW_YOUR_TURN" if players.size() > 1 or p >= 0 else "CREW_TURN"
	_banner_title.remove_theme_color_override("font_color")
	_banner_tween()
	_pad_feedback(p, c)


func _banner_tween() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_banner, "modulate:a", 1.0, 0.25)
	tw.tween_property(_banner, "offset_top", 36.0, 0.35).from(-80.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(2.2)
	tw.chain().tween_property(_banner, "modulate:a", 0.0, 0.4)


func _pad_feedback(p: int, c: Color) -> void:
	# Luz del mando del jugador con el color del puesto
	if p >= 0 and int(players[p].device) >= 0 and Input.has_joy_light(int(players[p].device)):
		Input.set_joy_light(int(players[p].device), c)
		Input.start_joy_vibration(int(players[p].device), 0.2, 0.5, 0.25)


## Cabezas: el activo (cámara dentro) sin cabeza; los demás miran al que tiene el reto.
func _update_heads() -> void:
	for r in cabin.crew:
		var a: Astronaut = cabin.crew[r]
		if r == active_role:
			# En pantalla partida cada cámara va delante de la cara (fuera del casco) y todas las cabezas
			# se ven: si no, el otro jugador vería a su compañero sin cabeza
			a.set_head_visible(_jump_t < 0.85 or split_role != "")
		else:
			a.set_head_visible(true)
			var target: Astronaut = cabin.crew[active_role]
			a.look_at_point(target.global_position + Vector3(0, 1.25, 0), true)


func _process(delta: float) -> void:
	_ai_emotes(delta)
	if _jump_t < 1.0:
		_jump_t = minf(_jump_t + delta / JUMP_S, 1.0)
		var s := _ease(_jump_t)
		var to := cabin.eye_of(active_role)
		# Arco por encima de la mesa, mirando al centro a mitad del salto
		var top := Vector3(0, 2.05, 0)
		var p := _from.origin.lerp(top, s).lerp(top.lerp(to.origin, s), s)
		var mid := Basis.looking_at((Vector3(0, 0.9, 0) - p).normalized(), Vector3.UP)
		var b: Basis
		if s < 0.5:
			b = _from.basis.orthonormalized().slerp(mid, s * 2.0)
		else:
			b = mid.slerp(to.basis.orthonormalized(), (s - 0.5) * 2.0)
		cam.global_transform = Transform3D(b, p)
		var me: Astronaut = cabin.crew[active_role]
		me.set_head_visible(_jump_t < 0.85)
		if _jump_t >= 1.0:
			jumped.emit(active_role)
		return
	# Mirada libre en todo momento (no solo en tu reto): stick derecho de cualquier mando
	if look_enabled:
		for dev in Input.get_connected_joypads():
			var v := Vector2(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y))
			if v.length() > 0.15:
				_yaw -= v.x * STICK_SPEED * delta
				_pitch -= v.y * STICK_SPEED * delta
	_apply_look()


func _apply_look() -> void:
	_yaw = clampf(_yaw, -YAW_LIMIT, YAW_LIMIT)
	_pitch = clampf(_pitch, PITCH_DOWN, PITCH_UP)
	var eye := cabin.eye_of(active_role)
	cam.global_transform = Transform3D(eye.basis * Basis.from_euler(Vector3(_pitch, _yaw, 0)), eye.origin)
	if split_role != "":
		cam.global_position -= cam.global_basis.z * 0.2 # fuera del casco (todas las cabezas visibles)
	# La cabeza del astronauta sigue la mirada (los demás lo ven mirar)
	if shake > 0.0:
		var tt := Time.get_ticks_msec() * 0.001
		cam.global_position += Vector3(sin(tt * 37.0), sin(tt * 43.0 + 1.0), 0) * 0.012 * shake
		cam.rotate_object_local(Vector3.FORWARD, sin(tt * 29.0) * 0.012 * shake)
	var me: Astronaut = cabin.crew[active_role]
	me.look_at_point(cam.global_position - cam.global_basis.z * 2.0, absf(_yaw) + absf(_pitch) > 0.05)


## Los puestos de la IA lanzan un emote de vez en cuando (saludan o animan al que tiene el reto).
func _ai_emotes(delta: float) -> void:
	_ai_emote_t -= delta
	if _ai_emote_t > 0.0:
		return
	_ai_emote_t = _rng.randf_range(9.0, 16.0)
	var ai := []
	for r in cabin.crew:
		if r != active_role and player_of(r) < 0:
			ai.append(r)
	if not ai.is_empty():
		(cabin.crew[ai[_rng.randi() % ai.size()]] as Astronaut).emote(["wave", "thumbs", "thumbs", "hurry"][_rng.randi() % 4])


static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


## Hacia dónde mira la cámara (para los retos de buscar con la mirada).
func look_dir() -> Vector3:
	return -cam.global_basis.z


## ¿La mirada apunta a `p` con un margen de `deg` grados?
func looking_at(p: Vector3, deg := 12.0) -> bool:
	return look_dir().angle_to((p - cam.global_position).normalized()) < deg_to_rad(deg)


## Un compañero automático (no controlado por el jugador del puesto activo) hace un emote.
func react(kind: String) -> void:
	var active_p := player_of(active_role)
	var options := []
	for r in cabin.crew:
		if r != active_role and (player_of(r) == active_p or player_of(r) < 0):
			options.append(r)
	if options.is_empty():
		for r in cabin.crew:
			if r != active_role:
				options.append(r)
	if not options.is_empty():
		(cabin.crew[options[_rng.randi() % options.size()]] as Astronaut).emote(kind)


func _input(event: InputEvent) -> void:
	if not look_enabled or _jump_t < 1.0 or not is_visible_in_tree():
		return
	# Ratón: mirar en cualquier momento, sea o no tu reto. Sobre la vista se mira moviendo el ratón;
	# sobre los botones del reto el ratón queda libre (mantén clic derecho para mirar igual).
	if event is InputEventMouseMotion:
		var hov := get_viewport().gui_get_hovered_control()
		var free_look := hov == null or hov == self or not (hov is BaseButton or hov is Range)
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or free_look or (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_yaw -= event.relative.x * MOUSE_SENS
			_pitch -= event.relative.y * MOUSE_SENS


func _unhandled_input(event: InputEvent) -> void:
	# Emotes: cada mando hace el emote del astronauta de su jugador (su primer puesto que no esté activo)
	if event is InputEventJoypadButton and event.pressed and EMOTE_BY_DPAD.has(event.button_index):
		_player_emote(event.device, EMOTE_BY_DPAD[event.button_index])
	elif event is InputEventKey and event.pressed and not event.echo and EMOTE_BY_KEY.has(event.keycode):
		_player_emote(-1, EMOTE_BY_KEY[event.keycode])


func _player_emote(device: int, kind: String) -> void:
	for i in players.size():
		if int(players[i].device) != device:
			continue
		var roles: Array = players[i].roles
		var who := ""
		for r in roles:
			if r != active_role:
				who = r
				break
		if who == "" and not roles.is_empty():
			who = roles[0]
		if who != "":
			(cabin.crew[who] as Astronaut).emote(kind)
			get_viewport().set_input_as_handled()
		return
	# Teclado sin jugador propio (un solo jugador): emote de un compañero automático
	if device < 0:
		react(kind)
