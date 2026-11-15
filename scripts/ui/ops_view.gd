class_name OpsView
extends Control
## Fase de operación (reto: "simular la misión" y "eventos aleatorios"): los días de la misión pasan
## rápido mientras la sonda junta ciencia y baja datos. En 3 momentos ocurre un evento (data/events.json)
## con dos decisiones; cada una tiene consecuencias y se explica el porqué. Si nadie responde en
## AUTOPILOT_S segundos, el piloto automático elige la opción segura.
## role del evento: qué puesto de la tripulación responde (crew mode). finished(mult, extra_cost, log).

signal finished(mult: float, extra_cost: float, log: Array)
signal say(line: Dictionary)
signal event_started(role: String)

const RUN_S := 18.0
const AUTOPILOT_S := 25.0
const EVENT_AT := [0.22, 0.5, 0.78]

var ev: Dictionary ## Probe.evaluate
var mission := 1
var base_science := 0.0
var target := 0.0

var _days := 1.0
var _life_days := 1.0
var _day := 0.0
var _mult := 1.0
var _cost := 0.0
var _health := 1.0
var _log: Array = []
var _queue: Array = [] ## eventos pendientes
var _current := {}
var _wait := 0.0 ## cuenta del piloto automático
var _result_t := 0.0 ## tiempo que se muestra el resultado
var _done := false
var _rng := RandomNumberGenerator.new()
var _lost_line := {}

var _day_lbl: Label
var _bar: ProgressBar
var _m_sci: Meter
var _m_data: Meter
var _m_batt: Meter
var _m_health: Meter
var _card: PanelContainer
var _card_box: VBoxContainer
var _log_box: VBoxContainer
var _cd: Label


static func where_for(m: int) -> String:
	if m <= 2:
		return "earth"
	if m <= 4:
		return "moon"
	if m <= 6:
		return "mars"
	return "deep"


func _ready() -> void:
	add_to_group("modal")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if "--smoke" in OS.get_cmdline_user_args():
		_rng.seed = 7
	else:
		_rng.randomize()
	_days = maxf(float(ev.get("mission_h", 24.0)) / 24.0, 1.0)
	_life_days = maxf(float(ev.get("life_h", 1e9)) / 24.0, 0.1)
	_pick_events()
	_build()


func _pick_events() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/events.json"))
	_lost_line = data.get("lost_signal", {})
	var w := where_for(mission)
	var pool: Array = data.events.filter(func(e: Dictionary) -> bool:
		return "any" in e.where or w in e.where)
	# Un evento propio del destino primero (si hay), luego al azar
	var own: Array = pool.filter(func(e: Dictionary) -> bool: return w in e.where)
	var rest: Array = pool.filter(func(e: Dictionary) -> bool: return not w in e.where)
	_shuffle(own)
	_shuffle(rest)
	var chosen := (own.slice(0, 1) + rest) if _rng.randf() < 0.6 else (rest + own)
	for i in mini(EVENT_AT.size(), chosen.size()):
		_queue.append({"at": EVENT_AT[i], "e": chosen[i]})


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


func _build() -> void:
	var veil := ColorRect.new()
	veil.color = Color(Game.PAPER_DEEP, 0.82)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = "Sheet"
	sheet.custom_minimum_size.x = 820
	center.add_child(sheet)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	sheet.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var eyebrow := Label.new()
	eyebrow.text = "OPS_TITLE"
	eyebrow.theme_type_variation = "Eyebrow"
	eyebrow.add_theme_color_override("font_color", Game.MARK)
	eyebrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(eyebrow)
	var skip := Button.new()
	skip.text = "OPS_SKIP"
	skip.theme_type_variation = &"Hud"
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(_skip_all)
	head.add_child(skip)
	_day_lbl = Label.new()
	_day_lbl.theme_type_variation = "Title"
	_day_lbl.add_theme_font_size_override("font_size", 34)
	_day_lbl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(_day_lbl)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 6
	_bar.max_value = 1.0
	v.add_child(_bar)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	v.add_child(grid)
	_m_sci = _meter(grid, "OPS_SCIENCE")
	_m_data = _meter(grid, "OPS_DATA")
	_m_batt = _meter(grid, "OPS_BATTERY")
	_m_health = _meter(grid, "OPS_HEALTH")
	_card = PanelContainer.new()
	_card.theme_type_variation = "Cell"
	_card.custom_minimum_size.y = 200
	v.add_child(_card)
	_card_box = VBoxContainer.new()
	_card_box.add_theme_constant_override("separation", 8)
	_card.add_child(_card_box)
	_idle_card()
	_log_box = VBoxContainer.new()
	_log_box.add_theme_constant_override("separation", 2)
	v.add_child(_log_box)
	_refresh()


func _meter(parent: Control, cap: String) -> Meter:
	var m := Meter.new()
	m.caption = cap
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(m)
	m.custom_minimum_size = Vector2(170, 58)
	return m


func _label(text: String, variation: String, size := 0, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _clear_card() -> void:
	for c in _card_box.get_children():
		c.queue_free()


func _idle_card() -> void:
	_clear_card()
	_card_box.add_child(_label(tr("OPS_IDLE"), "Hint", 15, true))


func _process(delta: float) -> void:
	if _done:
		return
	if not _current.is_empty():
		if _current.get("chosen", -1) >= 0:
			_result_t -= delta
			if _result_t <= 0.0:
				_current = {}
				_idle_card()
		else:
			_wait -= delta
			if is_instance_valid(_cd):
				_cd.text = tr("OPS_AUTOPILOT") % int(ceil(_wait))
			if _wait <= 0.0:
				_choose(_safe_index(_current.e), true)
		_refresh()
		return
	_day += _days / RUN_S * delta
	var p := _day / _days
	if not _queue.is_empty() and p >= float(_queue[0].at):
		_open_event(_queue.pop_front().e)
	if _day >= minf(_days, _life_days):
		_day = minf(_days, _life_days)
		_finish()
	_refresh()


func _refresh() -> void:
	var shown_days := int(ceil(_day))
	_day_lbl.text = tr("OPS_DAY") % [Game.fmt_int(shown_days), Game.fmt_int(int(ceil(_days)))]
	_bar.value = _day / _days
	var active := minf(_days, _life_days)
	var frac := clampf(_day / maxf(active, 0.001), 0.0, 1.0)
	var sci := base_science * _mult * frac
	_m_sci.set_values(sci, target, "%d / %d" % [int(sci), int(target)])
	var sent := float(ev.get("data_mb", 0.0)) * float(ev.get("data_frac", 1.0)) * _day
	_m_data.set_values(sent, 0.0, ResourcePanel._mb(sent))
	var batt := 1.0
	if str(ev.get("power", "")) != "rtg":
		batt = 1.0 - 0.45 * float(ev.get("eclipse", 0.0)) * absf(sin(_day * 3.1))
	if not _current.is_empty() and str(_current.e.id) in ["battery_low", "dust_storm"] and _current.get("chosen", -1) < 0:
		batt = 0.2
	_m_batt.set_values(batt * 100.0, 30.0, "%d %%" % int(batt * 100.0))
	var health := _health
	if _life_days < _days:
		health *= clampf(1.0 - _day / _life_days, 0.0, 1.0)
	_m_health.set_values(health * 100.0, 1.0, "%d %%" % int(health * 100.0))


func _open_event(e: Dictionary) -> void:
	_current = {"e": e, "chosen": -1}
	_wait = AUTOPILOT_S
	_clear_card()
	var role_row := HBoxContainer.new()
	role_row.add_theme_constant_override("separation", 10)
	var role := _label(tr("CREW_" + str(e.role).to_upper()), "Eyebrow")
	role.add_theme_color_override("font_color", Game.MARK)
	role_row.add_child(role)
	var cd := _label("", "Eyebrow")
	_cd = cd
	cd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	role_row.add_child(cd)
	_card_box.add_child(role_row)
	_card_box.add_child(_label(Codex.pick(e.title), "Title", 28))
	_card_box.add_child(_label(Codex.pick(e.text), "Body", 16, true))
	# Qué está pasando y por qué importa (Houston lo explica antes de pedir la decisión)
	if e.has("context"):
		var ctx := _label(tr("OPS_WHY") + "  " + Codex.pick(e.context), "Hint", 14, true)
		_card_box.add_child(ctx)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_card_box.add_child(row)
	# Las opciones salen en orden al azar y con el mismo estilo: la buena no siempre es la primera
	var opts: Array = e.options
	var order := range(opts.size())
	_shuffle(order)
	_current["order"] = order
	for j in order.size():
		var i: int = order[j]
		var b := Button.new()
		b.text = "%d · %s" % [j + 1, Codex.pick(opts[i].label)] + (("\n" + Codex.pick(opts[i].hint)) if opts[i].has("hint") else "")
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.y = 64
		b.add_theme_font_size_override("font_size", 14)
		var k := i
		b.pressed.connect(func() -> void: _choose(k, false))
		row.add_child(b)
		if j == 0:
			b.grab_focus.call_deferred() # con el mando se puede elegir sin ratón
	say.emit(e.get("voice", {"en": str(e.title.en) + ". " + str(e.text.en), "es": str(e.title.es) + ". " + str(e.text.es)}))
	event_started.emit(str(e.role))


func _safe_index(e: Dictionary) -> int:
	# Las opciones salen en orden al azar y con el mismo estilo: la buena no siempre es la primera
	var opts: Array = e.options
	var order := range(opts.size())
	_shuffle(order)
	_current["order"] = order
	for j in order.size():
		var i: int = order[j]
		if opts[i].get("safe", false):
			return i
	return 0


func _has(piece: String) -> bool:
	return piece != "" and (piece in [str(ev.get("computer", "")), str(ev.get("adcs", "")), str(ev.get("power", ""))] or piece in (ev.get("tests", []) as Array))


## Aplica la opción: multiplicador de ciencia, costo, vida, riesgo; explica el resultado.
func choose(i: int) -> void:
	if not _current.is_empty() and _current.get("chosen", -1) < 0:
		_choose(i, false)


func _choose(i: int, auto: bool) -> void:
	var e: Dictionary = _current.e
	var o: Dictionary = e.options[clampi(i, 0, e.options.size() - 1)]
	_current.chosen = i
	var m := float(o.get("sci", 1.0))
	var text := Codex.pick(o.result)
	var good := true
	if o.has("needs_storage"):
		if float(ev.get("storage_mb", 0.0)) < float(ev.get("data_mb", 0.0)) * float(o.needs_storage):
			m = float(o.get("fail_sci", 0.9))
			text = Codex.pick(o.fail_text)
			good = false
	if o.has("boost") and _has(str(o.boost)):
		m = float(o.sci_boost)
		text = Codex.pick(o.boost_text)
	if o.has("immune_sci") and _has(str(o.immune_sci)):
		m = 1.0
	var tests: Array = ev.get("tests", [])
	var risk := float(o.get("risk", 0.0)) * pow(0.7, tests.size()) # cada prueba en tierra baja el riesgo
	if str(e.id) == "instrument_reset" and "ditl" in tests:
		risk = 0.0 # la prueba de un día de operación ya encontró el error de software
	if risk > 0.0 and not _has(str(o.get("immune", ""))):
		if _rng.randf() < risk:
			m = float(o.risk_sci)
			text = Codex.pick(o.risk_text)
			good = false
			_health *= 0.8
	if o.has("life"):
		m *= lerpf(1.0, float(o.life), 0.5)
	_mult *= m
	_cost += float(o.get("cost_musd", 0.0)) * 1e6
	_log.append({"title": Codex.pick(e.title), "choice": Codex.pick(o.label), "text": text, "good": good, "auto": auto, "role": str(e.role)})
	_clear_card()
	var hdr := _label(("%s · %s" % [Codex.pick(e.title), tr("OPS_AUTO")]) if auto else Codex.pick(e.title), "Eyebrow")
	hdr.add_theme_color_override("font_color", Game.GOOD if good else Game.MARK)
	_card_box.add_child(hdr)
	_card_box.add_child(_label(Codex.pick(o.label), "Title", 22, true))
	var res := _label(text, "Body", 16, true)
	_card_box.add_child(res)
	var pct := int(round((m - 1.0) * 100.0))
	_card_box.add_child(_label(tr("OPS_EFFECT") % [("+" if pct >= 0 else "") + str(pct)], "Hint", 14))
	var ln := _label(("✓ " if good else "✕ ") + "%s: %s" % [Codex.pick(e.title), Codex.pick(o.label)], "Body", 13, true)
	ln.add_theme_color_override("font_color", Game.INK_DIM)
	_log_box.add_child(ln)
	var said: Dictionary = o.result
	if not good and o.has("risk_text") and text == Codex.pick(o.risk_text):
		said = o.risk_text
	elif not good and o.has("fail_text"):
		said = o.fail_text
	elif o.has("boost_text") and text == Codex.pick(o.boost_text):
		said = o.boost_text
	say.emit(said)
	_result_t = 5.0 if not "--smoke" in OS.get_cmdline_user_args() else 0.0


func _skip_all() -> void:
	if not _current.is_empty() and _current.get("chosen", -1) < 0:
		_choose(_safe_index(_current.e), true)
	while not _queue.is_empty():
		_current = {"e": _queue.pop_front().e, "chosen": -1}
		_choose(_safe_index(_current.e), true)
	_current = {}
	_day = minf(_days, _life_days)
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	_refresh()
	if _life_days < _days:
		var d := str(int(_life_days))
		say.emit({"en": str(_lost_line.get("en", "")).replace("{d}", d), "es": str(_lost_line.get("es", "")).replace("{d}", d)}) # el número cambia: sin voz grabada
	var t := get_tree().create_timer(1.2 if not "--smoke" in OS.get_cmdline_user_args() else 0.01)
	t.timeout.connect(func() -> void: finished.emit(_mult, _cost, _log))


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	var k := -1
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1, KEY_KP_1]:
			k = 0
		elif event.keycode in [KEY_2, KEY_KP_2]:
			k = 1
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_A:
			k = 0
		elif event.button_index == JOY_BUTTON_B:
			k = 1
	if k >= 0 and not _current.is_empty() and _current.get("chosen", -1) < 0:
		var order: Array = _current.get("order", [0, 1])
		_choose(int(order[mini(k, order.size() - 1)]), false)
		get_viewport().set_input_as_handled()
