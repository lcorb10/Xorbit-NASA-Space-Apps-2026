class_name ViabilityPanel
extends ColorRect
## Pantalla de la IA de viabilidad: corre las simulaciones de a poco (barra de progreso)
## y muestra el % de viabilidad, el veredicto, el puntaje por área con su explicación,
## la falla más común y la recomendación de Houston.

var analysis := {}
var design: Array = []
var mission := 0
var sandbox := false
var help: Dictionary = {} ## comms.json → help (texto de la recomendación)

var _runs: Array = []
var _rng := RandomNumberGenerator.new()
var _v: VBoxContainer
var _bar: ProgressBar
var _status: Label
var _running := false


func _ready() -> void:
	color = Color(Game.PAPER_DEEP, 0.9)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = "Sheet"
	sheet.custom_minimum_size = Vector2(820, 0)
	center.add_child(sheet)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 640
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet.add_child(scroll)
	_v = VBoxContainer.new()
	_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_v.add_theme_constant_override("separation", 8)
	scroll.add_child(_v)


func start() -> void:
	_runs.clear()
	_rng.seed = hash(JSON.stringify(design)) # el mismo cohete da el mismo informe
	for c in _v.get_children():
		c.queue_free()
	_v.add_child(_l("AI_EYEBROW", "Eyebrow"))
	var t := _l("AI_TITLE", "Title")
	t.add_theme_font_size_override("font_size", 44)
	_v.add_child(t)
	_v.add_child(_wrap(tr("AI_HOW") % ViabilityAI.RUNS, Game.INK_DIM))
	_bar = ProgressBar.new()
	_bar.max_value = ViabilityAI.RUNS
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 10
	_bar.add_theme_stylebox_override("background", Game._box(Color(Game.LINE, 0.5), 0, Game.LINE, Vector4.ZERO))
	_bar.add_theme_stylebox_override("fill", Game._box(Game.MARK, 0, Game.MARK, Vector4.ZERO))
	_v.add_child(_bar)
	_status = _wrap("", Game.INK)
	_v.add_child(_status)
	visible = true
	_running = true


func _process(_delta: float) -> void:
	if not _running:
		return
	# Dos vuelos por cuadro para que la pantalla no se congele
	for k in 2:
		if _runs.size() >= ViabilityAI.RUNS:
			break
		_runs.append(ViabilityAI.run_one(analysis, mission, sandbox, _rng))
	_bar.value = _runs.size()
	_status.text = tr("AI_RUNNING") % [_runs.size(), ViabilityAI.RUNS]
	if _runs.size() >= ViabilityAI.RUNS:
		_running = false
		_show(ViabilityAI.report(_runs, analysis, design))


func _show(r: Dictionary) -> void:
	_bar.visible = false
	_status.visible = false
	var pct := float(r.viability)
	var col := Game.GOOD if pct >= 90.0 else (Game.MARK if pct >= 50.0 else Color("#e5484d"))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	var big := Label.new()
	big.text = "%d %%" % int(round(pct))
	big.theme_type_variation = "Title"
	big.add_theme_font_size_override("font_size", 72)
	big.add_theme_color_override("font_color", col)
	big.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	head.add_child(big)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	var verdict := _l(str(r.verdict), "Title")
	verdict.add_theme_font_size_override("font_size", 28)
	verdict.add_theme_color_override("font_color", col)
	hv.add_child(verdict)
	hv.add_child(_wrap(tr("AI_SUMMARY") % [int(r.ok), int(r.runs)], Game.INK_DIM))
	head.add_child(hv)
	_v.add_child(head)
	if str(r.worst) != "":
		_v.add_child(_wrap(tr("AI_WORST") % [int(r.worst_n), int(r.runs), tr("RES_" + str(r.worst))], Game.MARK))
	_v.add_child(_l("AI_AREAS", "Eyebrow"))
	for s: Dictionary in r.scores:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_l := _l(str(s.key), "Body")
		name_l.custom_minimum_size.x = 170
		name_l.add_theme_font_override("font", Game.font_display_medium)
		name_l.add_theme_font_size_override("font_size", 20)
		row.add_child(name_l)
		var bar := ProgressBar.new()
		bar.max_value = 100.0
		bar.value = maxf(float(s.score), 3.0)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(160, 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var c := Game.GOOD if float(s.score) >= 70.0 else (Game.MARK if float(s.score) >= 40.0 else Color("#e5484d"))
		bar.add_theme_stylebox_override("background", Game._box(Color(Game.LINE, 0.5), 0, Game.LINE, Vector4.ZERO))
		bar.add_theme_stylebox_override("fill", Game._box(c, 0, c, Vector4.ZERO))
		row.add_child(bar)
		var num := Label.new()
		num.text = "%d" % int(s.score)
		num.custom_minimum_size.x = 36
		num.add_theme_font_override("font", Game.font_mono_medium)
		row.add_child(num)
		_v.add_child(row)
		var why := _wrap(str(s.why), Game.INK_DIM)
		why.add_theme_font_size_override("font_size", 13)
		_v.add_child(why)
	_v.add_child(_l("AI_NEXT", "Eyebrow"))
	_v.add_child(_wrap(Codex.pick(help.get(str(r.advice), {})), Game.MARK))
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_END
	var ok := Button.new()
	ok.text = "MB_OK"
	ok.theme_type_variation = "Primary"
	ok.pressed.connect(func() -> void: visible = false)
	row2.add_child(ok)
	_v.add_child(row2)
	ok.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_running = false
		visible = false
		get_viewport().set_input_as_handled()


func _l(text: String, variation: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l


func _wrap(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Body"
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", col)
	return l
