class_name CrewChallenge
extends Control
## Un reto de la tripulación (data/crew_challenges.json) en curso: pasos press / timing / zone / look.
## Lo hace el jugador `player` (índice en view.players) con su teclado o mando, o la IA si player < 0.
## Muestra abajo el panel del paso (qué hacer, qué tecla, medidor) y al final el puntaje (0-100).
## Las manos del astronauta van al control y el control se mueve de verdad en la cabina.

signal finished(id: String, score: float, ok: bool)
signal houston(line: Dictionary)
signal step_scored(score: float, human: bool)

const BEAT := 0.75 ## segundos entre números de la cuenta
const NOW_WINDOW := 0.5 ## error máximo que todavía da puntos en un reto de tiempo

var data: Dictionary
var view: CrewView
var player := -1
var turbulence := 0.0 ## 0..1: más deriva en las agujas y la cámara tiembla

var _steps: Array
var _i := -1
var _t := 0.0
var _scores: Array = []
var _v := 0.5 ## valor de la aguja en los pasos zone
var _in := 0.0
var _hurried := false
var _done := false
var _waiting_result := 0.0
var _ai_at := 0.0
var _look_hold := 0.0
var _alarm_pos := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _human := true ## el paso lo hace (o lo debía hacer) una persona: sus errores cuentan
var _seq: Array = [] ## índices de botón que hay que pulsar (sequence)
var _seq_i := 0
var _seq_err := 0
var _rf_green := false ## reflex: la luz está verde
var _rf_next := 0.0
var _rf_hits := 0
var _rf_bad := 0
const SEQ_KEYS_KB := [KEY_1, KEY_2, KEY_3, KEY_4]
const SEQ_KEYS_PAD := [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]
const SEQ_GLYPH_KB := ["1", "2", "3", "4"]
const SEQ_GLYPH_PAD := ["A", "B", "X", "Y"]

var _panel: PanelContainer
var _head: Label
var _hint: Label
var _keys: Label
var _meter: Control
var _result: Label


var half := -1 ## -1 pantalla completa; 0 mitad izquierda; 1 mitad derecha (pantalla partida)


func _ready() -> void:
	_rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_steps = data.get("steps", [])
	_build_panel()
	houston.emit(data.get("say", {}))
	_next_step()


func _role() -> String:
	return str(data.role)


func _astro() -> Astronaut:
	return view.cabin.crew[_role()]


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "Sheet"
	# Abajo a la izquierda: no tapa la consola donde actúa la mano
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	if half == 1: # pantalla partida: el reto del segundo jugador va en la mitad derecha
		_panel.anchor_left = 0.5
		_panel.anchor_right = 0.5
	_panel.offset_left = 28
	_panel.offset_right = 28 + 470
	_panel.offset_bottom = -110
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_panel.add_child(v)
	_head = _lbl(v, "Eyebrow", 15)
	_head.add_theme_color_override("font_color", Astronaut.ROLE_COLORS[_role()])
	_hint = _lbl(v, "Title", 30)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_meter = Control.new()
	_meter.custom_minimum_size = Vector2(0, 46)
	_meter.draw.connect(_draw_meter)
	v.add_child(_meter)
	var row := HBoxContainer.new()
	v.add_child(row)
	_keys = _lbl(row, "Eyebrow", 14)
	_keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result = _lbl(row, "Title", 26)


func _lbl(parent: Control, variation: String, size: int) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", size)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	parent.add_child(l)
	return l


func _step() -> Dictionary:
	return _steps[_i] if _i >= 0 and _i < _steps.size() else {}


func _next_step() -> void:
	_i += 1
	_human = player >= 0
	_t = 0.0
	_hurried = false
	_look_hold = 0.0
	_ai_err_v = INF
	if _i >= _steps.size():
		_finish()
		return
	var s := _step()
	var who := (tr("CREW_PLAYER") % (player + 1)) if player >= 0 else tr("CREW_AUTOPILOT")
	_head.text = "%s %s · %s · %d/%d" % [tr("CREW_" + _role().to_upper()), Astronaut.NAMES[_role()].to_upper(), who, _i + 1, _steps.size()]
	_hint.text = Codex.pick(s.get("hint", {}))
	_keys.text = _keys_text(str(s.type))
	_result.text = ""
	_ai_at = _rng.randf_range(0.7, 1.8)
	match str(s.type):
		"zone":
			var tgt := float(s.get("target", 0.5))
			_v = clampf(tgt + (0.35 if _rng.randf() < 0.5 else -0.35), 0.02, 0.98)
			_in = 0.0
		"sequence":
			_seq.clear()
			var n := int(s.get("length", 4))
			var keys: Array = s.get("keys", [])
			for k in n:
				_seq.append(k % keys.size() if s.get("ordered", false) else _rng.randi_range(0, keys.size() - 1))
			_seq_i = 0
			_seq_err = 0
		"reflex":
			_rf_green = false
			_rf_next = _rng.randf_range(0.8, 1.8)
			_rf_hits = 0
			_rf_bad = 0
		"look":
			var k := _rng.randi_range(0, view.cabin.annunciators.size() - 1)
			view.cabin.set_alarm(k)
			_alarm_pos = view.cabin.annunciators[k].global_position
	if s.has("control") and view.cabin.controls.has(str(s.control)):
		var ctl: Node3D = view.cabin.controls[str(s.control)]
		var side := "l" if _astro().to_local(ctl.global_position).x > 0.0 else "r"
		_astro().reach(side, ctl)
	_meter.queue_redraw()


func _keys_text(kind: String) -> String:
	var kb := player >= 0 and int(view.players[player].device) < 0
	if player < 0:
		return tr("CREW_AI_DOING")
	match kind:
		"zone":
			return tr("CREW_KEYS_AXIS_KB") if kb else tr("CREW_KEYS_AXIS_PAD")
		"look":
			return tr("CREW_KEYS_LOOK_KB") if kb else tr("CREW_KEYS_LOOK_PAD")
		"sequence":
			return tr("CREW_KEYS_SEQ_KB") if kb else tr("CREW_KEYS_SEQ_PAD")
	return tr("CREW_KEYS_ACTION_KB") if kb else tr("CREW_KEYS_ACTION_PAD")


# ---------- entrada del jugador ----------

func _action_pressed(event: InputEvent) -> bool:
	if player < 0 or not event.is_pressed() or event.is_echo():
		return false
	var dev := int(view.players[player].device)
	if dev < 0:
		return event is InputEventKey and (event.keycode in [KEY_SPACE, KEY_E, KEY_ENTER])
	return event is InputEventJoypadButton and event.device == dev and event.button_index == JOY_BUTTON_A


func _axis() -> float:
	if player < 0:
		return 0.0
	var dev := int(view.players[player].device)
	if dev < 0:
		return float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
	var x := Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
	return x if absf(x) > 0.12 else 0.0


## Botón de secuencia (0-3) que corresponde a este evento del jugador, o -1.
func _seq_button(event: InputEvent) -> int:
	if player < 0 or not event.is_pressed() or event.is_echo():
		return -1
	var dev := int(view.players[player].device)
	if dev < 0 and event is InputEventKey:
		return SEQ_KEYS_KB.find(event.keycode)
	if dev >= 0 and event is InputEventJoypadButton and event.device == dev:
		return SEQ_KEYS_PAD.find(event.button_index)
	return -1


func _unhandled_input(event: InputEvent) -> void:
	if _done or _waiting_result > 0.0:
		return
	var s := _step()
	if str(s.get("type", "")) == "sequence":
		var b := _seq_button(event)
		if b >= 0:
			_seq_press(b)
			get_viewport().set_input_as_handled()
		return
	if not _action_pressed(event):
		return
	match str(s.get("type", "")):
		"press":
			_do_press()
			get_viewport().set_input_as_handled()
		"timing":
			_do_timing()
			get_viewport().set_input_as_handled()
		"reflex":
			_reflex_press()
			get_viewport().set_input_as_handled()


# ---------- pasos ----------

func _do_press() -> void:
	var s := _step()
	_anim(str(s.get("anim", "")), str(s.get("control", "")))
	_score(clampf(100.0 - maxf(_t - 1.5, 0.0) * 15.0, 40.0, 100.0))


## El piloto automático toma el control del paso (nadie respondió a tiempo o se saltó al informe).
func autopilot_now() -> void:
	if _done:
		return
	player = -1
	_keys.text = tr("CREW_AI_DOING")
	_ai_at = _t


func _seq_press(b: int) -> void:
	var s := _step()
	if b == int(_seq[_seq_i]):
		_seq_i += 1
		view.cabin.press(str(s.get("control", "readback")))
		if _seq_i >= _seq.size():
			var time := float(s.get("time", 7.0))
			var sc := clampf(100.0 - _seq_err * 25.0 - maxf(_t - time * 0.5, 0.0) * 6.0, 0.0, 100.0)
			_score(sc)
	else:
		_seq_err += 1
		view.react("panic")
		_seq_i = 0 # se equivocó: vuelve a empezar la secuencia
	_meter.queue_redraw()


func _reflex_press() -> void:
	if _rf_green:
		_rf_hits += 1
		_rf_green = false
		_rf_next = _t + _rng.randf_range(0.7, 1.6)
		if _rf_hits >= int(_step().get("hits", 3)):
			_score(clampf(100.0 - _rf_bad * 25.0, 0.0, 100.0))
	else:
		_rf_bad += 1
		view.react("panic")


func _now_t() -> float:
	return BEAT * (int(_step().get("count", 3)) + 1)


func _do_timing() -> void:
	var s := _step()
	var err := _t - _now_t()
	_anim(str(s.get("anim", "")), str(s.get("control", "")))
	view.cabin.press(str(s.get("control", "")))
	if err < -NOW_WINDOW:
		view.react("panic") # ¡antes de tiempo!
		_score(10.0, tr("CREW_EARLY"))
		return
	var sc := clampf(100.0 * (1.0 - absf(err) / NOW_WINDOW), 0.0, 100.0)
	_score(sc, tr("CREW_PERFECT") if absf(err) < 0.08 else (tr("CREW_EARLY_A_BIT") if err < 0.0 else tr("CREW_LATE")))


func _anim(kind: String, control: String) -> void:
	match kind:
		"cover_open":
			view.cabin.set_cover(true)
		"toggle_on":
			view.cabin.set_toggle(true)
	if control == "master_alarm":
		view.cabin.set_alarm(-1)
	view.cabin.press(control)


func _set_control(control: String, v: float) -> void:
	match control:
		"stick":
			view.cabin.set_stick(Vector2((v - 0.5) * 2.0, 0.0))
		"throttle":
			view.cabin.set_throttle(v)
		"antenna":
			view.cabin.set_antenna(v)
		_:
			if control.begins_with("knob"):
				view.cabin.set_knob(int(control.trim_prefix("knob")), v)


## Termina el paso con `sc` puntos y muestra la calificación; luego sigue al próximo paso.
func _score(sc: float, label := "") -> void:
	_scores.append(sc)
	step_scored.emit(sc, _human)
	if label == "":
		label = tr("CREW_PERFECT") if sc >= 90.0 else (tr("CREW_GOOD") if sc >= 60.0 else tr("CREW_POOR"))
	_result.text = "+%d  %s" % [int(sc), label]
	_result.add_theme_color_override("font_color", Game.GOOD if sc >= 60.0 else Game.MARK)
	_waiting_result = 0.9 if not "--smoke" in OS.get_cmdline_user_args() else 0.01
	if sc >= 85.0 and _rng.randf() < 0.5:
		view.react("thumbs")
	elif sc < 35.0:
		view.react("panic")


func _process(delta: float) -> void:
	if _done:
		return
	if _waiting_result > 0.0:
		_waiting_result -= delta
		if _waiting_result <= 0.0:
			_next_step()
		return
	_t += delta
	var s := _step()
	var kind := str(s.get("type", ""))
	# La IA tarda un poco: si se demora, un compañero apura (una vez por paso)
	if not _hurried and player >= 0 and _t > 4.0 and kind in ["press", "look"]:
		_hurried = true
		view.react("hurry")
	match kind:
		"press":
			if player < 0 and _t >= _ai_at:
				_do_press()
			elif _t > 14.0:
				_score(25.0, tr("CREW_TIMEOUT"))
				return
		"timing":
			var now := _now_t()
			var left := now - _t
			_hint.text = Codex.pick(s.get("hint", {})) + "   " + (str(int(ceil(left / BEAT))) if left > 0.05 else tr("CREW_NOW"))
			if player < 0 and _t >= now + _ai_err():
				_do_timing()
			elif _t > now + NOW_WINDOW + 0.2:
				_score(0.0, tr("CREW_MISSED"))
		"zone":
			_zone(s, delta)
		"sequence":
			var keys: Array = s.get("keys", [])
			var line := ""
			for k in _seq.size():
				var nm := str(keys[int(_seq[k])])
				line += ("[%s] " % nm) if k == _seq_i else (("· " if k < _seq_i else "") + nm + "  ")
			_hint.text = line
			if player < 0 and _t >= _ai_at + _seq_i * 0.45:
				_seq_press(int(_seq[_seq_i]) if _rng.randf() > 0.08 else (int(_seq[_seq_i]) + 1) % keys.size())
			elif _t > float(s.get("time", 7.0)) + 4.0:
				_score(clampf(20.0 * _seq_i / maxf(_seq.size(), 1.0), 0.0, 20.0), tr("CREW_MISSED"))
		"reflex":
			if _t >= _rf_next and not _rf_green:
				_rf_green = _rng.randf() < 0.6
				_rf_next = _t + (_rng.randf_range(0.6, 1.0) if _rf_green else _rng.randf_range(0.5, 1.1))
				if not _rf_green:
					pass
			elif _rf_green and _t >= _rf_next:
				_rf_green = false # se apagó sin que lo pulsara
				_rf_next = _t + _rng.randf_range(0.5, 1.2)
			if player < 0 and _rf_green and _t >= _rf_next - 0.45:
				_reflex_press()
			if _t > 14.0:
				_score(clampf(30.0 * _rf_hits, 0.0, 60.0), tr("CREW_POOR"))
		"look":
			var found := view.looking_at(_alarm_pos, 10.0) if player >= 0 else _t > _ai_at + 1.0
			if player < 0:
				_astro().look_at_point(_alarm_pos, true)
			_look_hold = _look_hold + delta if found else 0.0
			if _t > 18.0 and not found:
				_score(20.0, tr("CREW_TIMEOUT"))
				return
			if _look_hold > 0.25:
				_score(clampf(100.0 - maxf(_t - 2.0, 0.0) * 12.0, 30.0, 100.0), tr("CREW_FOUND"))
	_meter.queue_redraw()


var _ai_err_v := INF
func _ai_err() -> float:
	if _ai_err_v == INF:
		_ai_err_v = _rng.randf_range(-0.07, 0.16) # el piloto automático casi nunca se equivoca
	return _ai_err_v


func _zone(s: Dictionary, delta: float) -> void:
	var tgt := float(s.get("target", 0.5))
	var w := float(s.get("width", 0.15))
	var drift := float(s.get("drift", 1.0)) * (1.0 + turbulence)
	var push := (sin(_t * 1.7) * 0.6 + sin(_t * 3.3 + 1.0) * 0.4) * 0.22 * drift
	var inp := _axis()
	if player < 0:
		inp = clampf((tgt - _v) * 4.0 + _rng.randf_range(-0.4, 0.4), -1.0, 1.0)
	_v = clampf(_v + (push + inp * 0.55) * delta, 0.0, 1.0)
	_set_control(str(s.get("control", "")), _v)
	if absf(_v - tgt) <= w / 2.0:
		_in += delta
	var need := float(s.get("seconds", 2.5))
	if _in >= need:
		_score(clampf(100.0 * need / maxf(_t - 0.6, need), 0.0, 100.0))
	elif _t > need + 7.0:
		_score(clampf(50.0 * _in / need, 0.0, 50.0), tr("CREW_POOR"))


func _draw_meter() -> void:
	var s := _step()
	var w := _meter.size.x
	var h := _meter.size.y
	var c: Color = Astronaut.ROLE_COLORS[_role()]
	match str(s.get("type", "")):
		"zone":
			var tgt := float(s.get("target", 0.5))
			var zw := float(s.get("width", 0.15))
			_meter.draw_rect(Rect2(0, h * 0.35, w, h * 0.3), Color(Game.LINE, 0.6))
			_meter.draw_rect(Rect2((tgt - zw / 2.0) * w, h * 0.25, zw * w, h * 0.5), Color(Game.GOOD, 0.55))
			var x := _v * w
			var inside := absf(_v - tgt) <= zw / 2.0
			_meter.draw_rect(Rect2(x - 3, 0, 6, h), Game.GOOD if inside else Game.MARK)
			var need := float(s.get("seconds", 2.5))
			_meter.draw_rect(Rect2(0, h - 4, w * clampf(_in / need, 0.0, 1.0), 4), c)
		"timing":
			var now := _now_t()
			var frac := clampf(_t / (now + NOW_WINDOW), 0.0, 1.0)
			_meter.draw_rect(Rect2(0, h * 0.4, w, h * 0.2), Color(Game.LINE, 0.6))
			var nx := now / (now + NOW_WINDOW) * w
			_meter.draw_rect(Rect2(nx - w * 0.04, h * 0.2, w * 0.08, h * 0.6), Color(Game.GOOD, 0.55))
			_meter.draw_rect(Rect2(frac * w - 3, 0, 6, h), c)
		"sequence":
			var keys: Array = s.get("keys", [])
			var kb := player >= 0 and int(view.players[player].device) < 0
			var bw := w / 4.0
			for k in 4:
				var col := c if (not _seq.is_empty() and _seq_i < _seq.size() and int(_seq[_seq_i]) == k) else Color(Game.LINE, 0.9)
				_meter.draw_rect(Rect2(k * bw + 3, 2, bw - 6, h - 4), Color(col, 0.35), true)
				_meter.draw_rect(Rect2(k * bw + 3, 2, bw - 6, h - 4), col, false, 2.0)
				var glyph: String = (SEQ_GLYPH_KB if kb else SEQ_GLYPH_PAD)[k]
				_meter.draw_string(Game.font_mono_medium, Vector2(k * bw + 10, h * 0.62), glyph + " " + str(keys[k] if k < keys.size() else ""), HORIZONTAL_ALIGNMENT_LEFT, bw - 14, 13, Game.INK)
			var time := float(s.get("time", 7.0))
			_meter.draw_rect(Rect2(0, h - 3, w * clampf(1.0 - _t / time, 0.0, 1.0), 3), Game.MARK)
		"reflex":
			var lc := Game.GOOD if _rf_green else Color(0.85, 0.15, 0.1)
			_meter.draw_circle(Vector2(w * 0.5, h * 0.5), h * 0.42, lc)
			_meter.draw_string(Game.font_mono_medium, Vector2(8, h * 0.62), "%d / %d" % [_rf_hits, int(s.get("hits", 3))], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Game.INK)
		"press", "look":
			var pulse := 0.5 + 0.5 * sin(_t * 6.0)
			_meter.draw_rect(Rect2(0, h * 0.4, w, h * 0.2), Color(c, 0.25 + 0.35 * pulse))


func _finish() -> void:
	_done = true
	var total := 0.0
	for sc in _scores:
		total += float(sc)
	var avg := total / maxf(_scores.size(), 1.0)
	_astro().release()
	_astro().look_at_point(Vector3.ZERO, false)
	view.cabin.set_alarm(-1)
	finished.emit(str(data.id), avg, avg >= 35.0)
	queue_free()
