class_name EmoteWheel
extends Control
## Rueda de emotes pequeña, abajo a la izquierda, para no tapar el reto del compañero.
## - Botón "EMOTES · T" siempre visible: clic abre o cierra la rueda.
## - Teclado: mantén T, elige con 1-4 / flechas o haz clic en un gajo; soltar T sin elegir la cierra.
## - Mando: mantén L1, inclina el stick derecho hacia un gajo y suelta L1 (la cruceta sigue mandando directo).
## Emite `picked(device, kind)`; crew_view decide qué astronauta lo hace.

signal picked(device: int, kind: String)

const KINDS := ["wave", "thumbs", "hurry", "panic"] ## arriba, derecha, abajo, izquierda
const DIRS := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
const R := 82.0
const SHORT := {"wave": "Hi!", "thumbs": "Nice!", "hurry": "Hurry!", "panic": "Wait!"} ## cortas para que quepan en la rueda
const KEYS := {KEY_1: 0, KEY_2: 1, KEY_3: 2, KEY_4: 3, KEY_UP: 0, KEY_RIGHT: 1, KEY_DOWN: 2, KEY_LEFT: 3}

var open := false
var _device := -1 ## quién la abrió (-1 teclado)
var _hover := -1
var _color := Color.WHITE
var _btn: Button
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 20
	offset_top = -280
	offset_right = 20 + 240
	offset_bottom = -20
	_font = Game.font_mono_medium
	_btn = Button.new()
	_btn.text = "EMOTES · T"
	_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.add_theme_font_size_override("font_size", 13)
	_btn.anchor_top = 1.0
	_btn.anchor_bottom = 1.0
	_btn.offset_top = -34
	_btn.offset_right = 120
	_btn.pressed.connect(func() -> void:
		if open:
			close()
		else:
			show_for(-1, Color.WHITE))
	add_child(_btn)
	if "--wheel" in OS.get_cmdline_user_args():
		show_for.call_deferred(-1, Color(1.0, 0.55, 0.15))
		set_deferred("_hover", 1)


func center() -> Vector2:
	return Vector2(118, 116)


func show_for(device: int, col: Color) -> void:
	open = true
	_device = device
	_color = col
	_hover = -1
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func close() -> void:
	open = false
	_hover = -1
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func choose(i: int) -> void:
	if i < 0:
		close()
		return
	picked.emit(_device, KINDS[i])
	close()


func _seg_at(p: Vector2) -> int:
	var d := p - center()
	if d.length() < 18.0 or d.length() > R + 30.0:
		return -1
	var best := -1
	var bd := -2.0
	for i in 4:
		var dot := d.normalized().dot(DIRS[i])
		if dot > bd:
			bd = dot
			best = i
	return best


func _gui_input(event: InputEvent) -> void:
	if not open:
		return
	if event is InputEventMouseMotion:
		var h := _seg_at(event.position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		choose(_seg_at(event.position))
		accept_event()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and not event.echo:
		if event.keycode == KEY_T:
			if event.pressed and not open:
				show_for(-1, Color.WHITE)
			elif not event.pressed and open and _device == -1 and _hover >= 0:
				choose(_hover)
			get_viewport().set_input_as_handled()
		elif event.pressed and open and _device == -1 and KEYS.has(event.keycode):
			choose(KEYS[event.keycode])
			get_viewport().set_input_as_handled()
		elif event.pressed and open and event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.button_index == JOY_BUTTON_LEFT_SHOULDER:
		if event.pressed and not open:
			show_for(event.device, Color.WHITE)
		elif not event.pressed and open and _device == event.device:
			choose(_hover)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if open and _device >= 0:
		var v := Vector2(Input.get_joy_axis(_device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(_device, JOY_AXIS_RIGHT_Y))
		var h := -1
		if v.length() > 0.5:
			h = _seg_at(center() + v.normalized() * R * 0.7)
		if h != _hover:
			_hover = h
			queue_redraw()


func _draw() -> void:
	if not open:
		return
	var c := center()
	draw_circle(c, R + 36.0, Color(0.03, 0.06, 0.1, 0.78))
	draw_arc(c, R + 36.0, 0, TAU, 48, Color(_color, 0.8), 2.0)
	for i in 4:
		var p: Vector2 = c + DIRS[i] * R * 0.78
		var on := i == _hover
		draw_circle(p, 32.0, Color(_color, 0.9) if on else Color(1, 1, 1, 0.12))
		var txt: String = SHORT[KINDS[i]]
		var fs := 15
		var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(_font, p + Vector2(-w / 2.0, 4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.05, 0.05, 0.08) if on else Color(1, 1, 1, 0.95))
		var n := str(i + 1)
		draw_string(_font, p + Vector2(-3, -16), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.55))
