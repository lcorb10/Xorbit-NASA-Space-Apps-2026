class_name CrewLobby
extends ColorRect
## Sala de tripulación: "¿Quién vuela?". Tres pasos, uno por pantalla (como la vinculación de la Switch):
##   1. ¿Cuántos juegan? 4 tarjetas grandes (1 a 4). Teclas 1-4, o clic.
##   2. Vincula los mandos: una tarjeta por jugador con su color. Cada persona mantiene L + R de SU mando
##      (o pulsa A); el primero es el Jugador 1, el siguiente el 2... El mando vibra y se enciende con su
##      color. Con el teclado: Espacio (un solo jugador puede usarlo). Esc vuelve al paso 1.
##   3. Modo de juego: Asistido o Manual y, si juegas solo, Todos los puestos o Solo comandante.
## Los puestos se reparten solos según cuántos haya (docs/TRIPULACION.md). Al empezar llena Game.crew_setup.

signal started

const ROLES := ["commander", "engineer", "systems", "comms"]
const SPLIT := {
	1: [["commander", "engineer", "systems", "comms"]],
	2: [["commander", "engineer"], ["systems", "comms"]],
	3: [["commander"], ["engineer"], ["systems", "comms"]],
	4: [["commander"], ["engineer"], ["systems"], ["comms"]],
}
const READY_PAUSE := 1.2

var devices: Array = [] ## dispositivo de cada jugador (-1 teclado)
var manual := false
var solo_all := true
var count := 0 ## cuántos juegan (paso 1)

var _phase := "count"
var _sheet: PanelContainer
var _v: VBoxContainer
var _cards: HBoxContainer
var _title: Label
var _mode_cards: Array[Button] = []
var _solo_box: VBoxContainer
var _solo_cards: Array[Button] = []
var _ready_t := -1.0


func _ready() -> void:
	add_to_group("modal")
	color = Color(Game.PAPER_DEEP, 0.92)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	manual = str(Game.settings.get("crew_mode", "assisted")) == "manual"
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_sheet = PanelContainer.new()
	_sheet.theme_type_variation = "Sheet"
	_sheet.custom_minimum_size.x = 900
	center.add_child(_sheet)
	_show_count()
	# Prueba: --lobbytest=link:3:1 (paso, cuántos juegan, cuántos ya vinculados) o --lobbytest=mode:1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lobbytest="):
			var p := a.trim_prefix("--lobbytest=").split(":")
			count = int(p[1]) if p.size() > 1 else 2
			_show_link()
			for k in (int(p[2]) if p.size() > 2 else 0):
				devices.append(-1 if k == 0 else k - 1)
			_refresh_link()
			if p[0] == "mode":
				devices = [-1]
				_show_mode()


func _clear() -> void:
	if _v:
		_v.queue_free()
	_v = VBoxContainer.new()
	_v.add_theme_constant_override("separation", 14)
	_sheet.add_child(_v)
	_v.add_child(_lbl("CL_EYEBROW", "Eyebrow", 0, Game.MARK))
	_title = _lbl("CL_TITLE", "Title", 42)
	_v.add_child(_title)
	_mode_cards.clear()
	_solo_cards.clear()


# ---------- 1 · ¿Cuántos juegan? ----------
func _show_count() -> void:
	_phase = "count"
	devices.clear()
	_clear()
	_title.text = "CL_HOW_MANY"
	_v.add_child(_lbl("CL_HOW_MANY_D", "Body", 15))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_v.add_child(row)
	for n in range(1, 5):
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 150)
		b.text = "%d\n%s" % [n, tr("CL_N_PLAYERS_1" if n == 1 else "CL_N_PLAYERS")]
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.add_theme_font_size_override("font_size", 26)
		b.add_theme_font_override("font", Game.font_display)
		# Una franja por jugador con el color de su puesto
		var dots := HBoxContainer.new()
		dots.alignment = BoxContainer.ALIGNMENT_CENTER
		dots.add_theme_constant_override("separation", 6)
		dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dots.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		dots.offset_top = -22
		dots.offset_bottom = -12
		for k in n:
			var d := ColorRect.new()
			d.custom_minimum_size = Vector2(26, 8)
			d.color = Astronaut.ROLE_COLORS[SPLIT[n][k][0]]
			d.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dots.add_child(d)
		b.add_child(dots)
		b.pressed.connect(_choose_count.bind(n))
		row.add_child(b)
		if n == 1:
			b.grab_focus.call_deferred()


func _choose_count(n: int) -> void:
	count = n
	_show_link()


# ---------- 2 · Vincula los mandos ----------
func _show_link() -> void:
	_phase = "link"
	devices.clear()
	_ready_t = -1.0
	_clear()
	_title.text = "CL_LINK"
	_v.add_child(_lbl("CL_LINK_D", "Body", 15))
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 10)
	_v.add_child(_cards)
	var back := Button.new()
	back.text = "CL_BACK"
	back.pressed.connect(_show_count)
	_v.add_child(back)
	_refresh_link()


func _refresh_link() -> void:
	for c in _cards.get_children():
		c.queue_free()
	for i in count:
		var roles: Array = SPLIT[count][i] if count > 1 else (SPLIT[1][0] if solo_all else ["commander"])
		var col: Color = Astronaut.ROLE_COLORS[roles[0]]
		var linked := i < devices.size()
		var cell := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col, 0.9) if linked else Color(col, 0.08)
		sb.set_border_width_all(3)
		sb.border_color = col
		sb.set_corner_radius_all(10)
		sb.set_content_margin_all(12)
		cell.add_theme_stylebox_override("panel", sb)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.custom_minimum_size.y = 190
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 4)
		cell.add_child(cv)
		var ink := Color(0.04, 0.05, 0.08) if linked else Game.INK
		var who := _lbl(tr("CREW_PLAYER") % (i + 1), "Title", 24, ink)
		who.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cv.add_child(who)
		var name_lbl := _lbl(" · ".join(roles.map(func(r: String) -> String: return Astronaut.NAMES[r])), "Eyebrow", 0, ink if linked else col)
		name_lbl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cv.add_child(name_lbl)
		var st: Label
		if linked:
			var dev := int(devices[i])
			st = _lbl("✓  " + (tr("CL_KEYBOARD") if dev < 0 else (tr("CL_PAD") % (dev + 1))), "Body", 15, ink)
		elif i == devices.size():
			st = _lbl("CL_WAIT_THIS", "Body", 14, Game.INK)
		else:
			st = _lbl(tr("CL_WAIT_AFTER") % i, "Hint", 13)
		st.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED if linked or i > devices.size() else Node.AUTO_TRANSLATE_MODE_INHERIT
		cv.add_child(st)
		for r in roles:
			cv.add_child(_lbl("CREW_" + str(r).to_upper(), "Hint", 12, ink if linked else Astronaut.ROLE_COLORS[r]))
		_cards.add_child(cell)
	if devices.size() >= count:
		_title.text = "CL_READY"


func _link(device: int) -> void:
	# El teclado puede ser de varios jugadores (silla caliente: se lo pasan en cada turno); un mando, de uno solo
	if _phase != "link" or (device >= 0 and device in devices) or devices.size() >= count:
		return
	devices.append(device)
	if device >= 0:
		var roles: Array = SPLIT[count][devices.size() - 1]
		if Input.has_joy_light(device):
			Input.set_joy_light(device, Astronaut.ROLE_COLORS[roles[0]])
		Input.start_joy_vibration(device, 0.4, 0.8, 0.3)
	_refresh_link()
	# Destello de la tarjeta recién vinculada
	var cell: Control = _cards.get_child(_cards.get_child_count() - count + devices.size() - 1)
	if cell:
		cell.pivot_offset = cell.size / 2.0
		cell.scale = Vector2.ONE * 1.08
		create_tween().tween_property(cell, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if devices.size() >= count:
		_ready_t = READY_PAUSE


func _process(delta: float) -> void:
	if _ready_t > 0.0:
		_ready_t -= delta
		if _ready_t <= 0.0:
			_show_mode()


# ---------- 3 · Modo de juego ----------
func _show_mode() -> void:
	_phase = "mode"
	_clear()
	_v.add_child(_lbl("CL_STEP_MODE", "Eyebrow"))
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 10)
	_v.add_child(modes)
	for k in 2:
		var b := _card(["CL_ASSISTED_T", "CL_MANUAL_T"][k], ["CL_ASSISTED_D", "CL_MANUAL_D"][k])
		var is_manual := k == 1
		b.pressed.connect(func() -> void:
			manual = is_manual
			_refresh_mode())
		modes.add_child(b)
		_mode_cards.append(b)
	_solo_box = VBoxContainer.new()
	_solo_box.add_theme_constant_override("separation", 8)
	_v.add_child(_solo_box)
	_solo_box.add_child(_lbl("CL_STEP_SOLO", "Eyebrow"))
	var solos := HBoxContainer.new()
	solos.add_theme_constant_override("separation", 10)
	_solo_box.add_child(solos)
	for k in 2:
		var b := _card(["CL_SOLO_ALL_T", "CL_SOLO_CMD_T"][k], ["CL_SOLO_ALL_D", "CL_SOLO_CMD_D"][k])
		var all := k == 0
		b.pressed.connect(func() -> void:
			solo_all = all
			_refresh_mode())
		solos.add_child(b)
		_solo_cards.append(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_v.add_child(row)
	var back := Button.new()
	back.text = "CL_BACK"
	back.custom_minimum_size.y = 50
	back.pressed.connect(_show_link)
	row.add_child(back)
	var go := Button.new()
	go.text = "CL_START"
	go.theme_type_variation = "Primary"
	go.custom_minimum_size.y = 50
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(_start)
	row.add_child(go)
	go.grab_focus.call_deferred()
	_refresh_mode()


func _refresh_mode() -> void:
	_set_card(_mode_cards[0], not manual)
	_set_card(_mode_cards[1], manual)
	_solo_box.visible = devices.size() == 1
	_set_card(_solo_cards[0], solo_all)
	_set_card(_solo_cards[1], not solo_all)


func _lbl(text: String, variation: String, size := 0, col := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if col.a > 0.0:
		l.add_theme_color_override("font_color", col)
	return l


## Tarjeta de opción: título y una línea que explica qué pasa si la eliges.
func _card(title: String, desc: String) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 88)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.set_meta("title", title)
	b.set_meta("desc", desc)
	return b


func _set_card(b: Button, on: bool) -> void:
	b.button_pressed = on
	b.theme_type_variation = &"Primary" if on else &""
	b.text = ("✓  " if on else "○  ") + tr(str(b.get_meta("title"))) + "\n" + tr(str(b.get_meta("desc")))
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_font_override("font", Game.font_mono_medium) # misma letra elegida o no


func _roles_for(i: int) -> Array:
	if devices.size() == 1:
		return SPLIT[1][0] if solo_all else ["commander"]
	return SPLIT[devices.size()][i]


func _input(event: InputEvent) -> void:
	match _phase:
		"count":
			if event is InputEventKey and event.pressed and event.keycode >= KEY_1 and event.keycode <= KEY_4:
				_choose_count(event.keycode - KEY_0)
				get_viewport().set_input_as_handled()
		"link":
			if event is InputEventJoypadButton and event.pressed:
				var d: int = event.device
				var both := Input.is_joy_button_pressed(d, JOY_BUTTON_LEFT_SHOULDER) and Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER)
				if both or event.button_index == JOY_BUTTON_A:
					_link(d)
					get_viewport().set_input_as_handled()
				elif event.button_index == JOY_BUTTON_B and devices.is_empty():
					_show_count()
			elif event is InputEventKey and event.pressed and not event.echo:
				if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
					_link(-1)
					get_viewport().set_input_as_handled()
				elif event.keycode == KEY_ESCAPE:
					_show_count()
					get_viewport().set_input_as_handled()
		"mode":
			if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
				_start()


func _start() -> void:
	var setup := []
	for i in devices.size():
		setup.append({"name": "P%d" % (i + 1), "device": int(devices[i]), "roles": _roles_for(i)})
	Game.crew_setup = setup
	Game.settings["crew_mode"] = "manual" if manual else "assisted"
	started.emit()
	queue_free()
