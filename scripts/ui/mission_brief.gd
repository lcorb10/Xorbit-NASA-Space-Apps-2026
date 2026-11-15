class_name MissionBrief
extends ColorRect
## Encargo de la misión (historia del Grupo XORBIT): cliente, qué necesita, objetivo medible,
## criterios para ganar con su estado actual (✓/✗) y un consejo. Textos en data/missions.json.
## Con mission = -2 muestra la bienvenida a XORBIT.

var mission := 0
var checklist: Callable ## func() -> Array de {text, ok}; vacío si no hay cohete que medir
var _scroll: ScrollContainer
var _foot: HBoxContainer
var dev_months: Callable ## meses de desarrollo del diseño actual (línea de tiempo)
var extras: Callable ## func() -> Array de {text, ok}: misiones secundarias
var _v: VBoxContainer

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions.json"))
	return _data


func _ready() -> void:
	add_to_group("modal")
	color = Color(Game.PAPER_DEEP, 0.86)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = "Sheet"
	sheet.custom_minimum_size.x = 720
	center.add_child(sheet)
	# Contenido con su propio scroll y botones fijos abajo: nunca quedan fuera de la pantalla
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	sheet.add_child(outer)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_scroll)
	_v = VBoxContainer.new()
	_v.add_theme_constant_override("separation", 10)
	_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_v)
	_foot = HBoxContainer.new()
	_foot.alignment = BoxContainer.ALIGNMENT_END
	outer.add_child(_foot)
	get_viewport().size_changed.connect(_fit)
	visibility_changed.connect(func() -> void:
		if visible:
			refresh())
	refresh()


func refresh() -> void:
	if _v == null:
		return
	for c in _v.get_children():
		c.queue_free()
	for c in _foot.get_children():
		c.queue_free()
	_fit.call_deferred()
	var d := data()
	if mission == -2:
		var intro: Dictionary = d.get("intro", {})
		_v.add_child(_l("XORBIT", "Eyebrow"))
		_v.add_child(_title(Codex.pick(intro.get("title"))))
		_v.add_child(_text(Codex.pick(intro.get("body")), Game.INK))
		_foot.add_child(_ok_button("MB_START"))
		return
	var m: Dictionary = d.get("missions", {}).get(str(mission), {})
	_v.add_child(_l((tr("MB_JOB") % mission) + " · " + Codex.pick(m.get("client")).to_upper(), "Eyebrow"))
	_v.add_child(_title(tr("LEVEL_%d_NAME" % mission)))
	_v.add_child(_text(Codex.pick(m.get("story")), Game.INK_DIM))
	_v.add_child(_l("MB_GOAL", "Eyebrow"))
	var goal := _text(Codex.pick(m.get("goal")), Game.INK)
	goal.add_theme_font_size_override("font_size", 18)
	_v.add_child(goal)
	var lv := Game.level(mission)
	_v.add_child(_l("MB_REQUIRES", "Eyebrow"))
	var req := _text(tr("MB_REQ_LINE") % [Game.fmt(float(lv.get("dv_km_s", 0.0)), 1), Game.budget_text(lv), int(Probe.destination(mission).get("payload_min_kg", 0))], Game.INK)
	_v.add_child(req)
	if checklist.is_valid():
		var items: Array = checklist.call()
		if not items.is_empty():
			_v.add_child(_l("MB_STATUS", "Eyebrow"))
			for it: Dictionary in items:
				_v.add_child(_text(("✓  " if it.ok else "✗  ") + str(it.text), Game.GOOD if it.ok else Game.MARK))
	if extras.is_valid():
		var xs: Array = extras.call()
		if not xs.is_empty():
			_v.add_child(_l("MB_EXTRAS", "Eyebrow"))
			for it: Dictionary in xs:
				_v.add_child(_text(("✓  " if it.ok else "○  ") + str(it.text), Game.GOOD if it.ok else Game.INK_DIM))
	_v.add_child(_l("MB_TIMELINE", "Eyebrow"))
	_v.add_child(_timeline(mission))
	var tip := _text(Codex.pick(m.get("tip")), Game.MARK)
	_v.add_child(tip)
	_foot.add_child(_ok_button("MB_OK"))


## Línea de tiempo de la misión (concepto de operaciones): desarrollo, lanzamiento, viaje, operación, fin.
func _timeline(m: int) -> Control:
	var legs_days := 0.0
	for lg: Dictionary in Game.level(m).get("legs", []):
		legs_days += float(lg.get("days", 0.0))
	var ops_days := float(Probe.destination(m).get("hours", 24.0)) / 24.0
	var dev := float(dev_months.call()) if dev_months.is_valid() else 12.0
	var steps := [[tr("TL_DEV"), tr("TL_MONTHS") % int(round(dev))], [tr("TL_LAUNCH"), tr("TL_MIN") % 10]]
	if legs_days > 0.0:
		steps.append([tr("TL_TRAVEL"), _days(legs_days)])
	steps.append([tr("TL_OPS"), _days(ops_days)])
	steps.append([tr("TL_END"), ""])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for i in steps.size():
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bar := ColorRect.new()
		bar.custom_minimum_size.y = 4
		bar.color = Game.MARK if i == 0 else Game.LINE
		cell.add_child(bar)
		var a := _l(str(steps[i][0]), "Eyebrow")
		a.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cell.add_child(a)
		var b := _l(str(steps[i][1]), "Hint")
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cell.add_child(b)
		row.add_child(cell)
	return row


func _days(d: float) -> String:
	if d < 1.0:
		return tr("TL_HOURS") % int(round(d * 24.0))
	if d > 700.0:
		return tr("RS_YEARS") % Game.fmt(d / 365.25, 1)
	return tr("RS_DAYS") % int(round(d))


## Alto del área con scroll: el del contenido, sin pasar de lo que cabe en la pantalla con los botones.
func _fit() -> void:
	if _scroll == null or not is_inside_tree():
		return
	await get_tree().process_frame
	var want := _v.get_combined_minimum_size().y
	# Se deja libre la franja de abajo, donde aparece la radio de Houston (está por encima de todo)
	var room := get_viewport_rect().size.y - 300.0
	_scroll.custom_minimum_size.y = clampf(want, 120.0, maxf(room, 200.0))


func _ok_button(key: String) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	var b := Button.new()
	b.text = key
	b.theme_type_variation = "Primary"
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(func() -> void: visible = false)
	row.add_child(b)
	b.grab_focus.call_deferred()
	return row


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		visible = false
		get_viewport().set_input_as_handled()


func _l(text: String, variation: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l


func _title(text: String) -> Label:
	var t := Label.new()
	t.text = text
	t.theme_type_variation = "Title"
	t.add_theme_font_size_override("font_size", 46)
	return t


func _text(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Body"
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", col)
	return l
