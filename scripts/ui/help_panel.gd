class_name HelpPanel
extends ColorRect
## Ayuda de Houston. Primero solo da una pista (lo primero que conviene arreglar) y el estado de los
## requisitos. Si el jugador decide rendirse, muestra la solución: un cohete verificado para la misión
## (data/solutions.json, generado por Solver) explicado pieza por pieza, de abajo hacia arriba, con el
## porqué de cada decisión y sus números. Ver la solución deja la misión con 1 estrella como máximo.

signal load_solution(design: Array)

var mission := 0
var analysis := {}
var design: Array = []
var help := {} ## comms.json → help

var _v: VBoxContainer
var _scroll: ScrollContainer
static var _sol := {}


static func solution(m: int) -> Dictionary:
	if _sol.is_empty() and FileAccess.file_exists("res://data/solutions.json"):
		_sol = JSON.parse_string(FileAccess.get_file_as_string("res://data/solutions.json")).get("solutions", {})
	return _sol.get(str(m), {})


func _ready() -> void:
	add_to_group("modal") # la radio de Houston sube y no tapa el panel
	color = Color(Game.PAPER_DEEP, 0.88)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -120 # deja ver la radio de Houston abajo
	add_child(center)
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = "Sheet"
	sheet.custom_minimum_size = Vector2(860, 0)
	center.add_child(sheet)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size.y = 600
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet.add_child(_scroll)
	_v = VBoxContainer.new()
	_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_v.add_theme_constant_override("separation", 10)
	_scroll.add_child(_v)


func open_hint() -> void:
	_clear()
	_v.add_child(_l("HP_EYEBROW", "Eyebrow"))
	_v.add_child(_title(tr("HP_TITLE")))
	_v.add_child(_l("HP_FIRST", "Eyebrow"))
	var e: Dictionary = help.get(Advisor.suggest(analysis, design), {})
	_v.add_child(_text(Codex.pick(e), Game.MARK, 18))
	if not design.is_empty():
		_v.add_child(_l("CX_MISSION", "Eyebrow"))
		for it: Dictionary in Advisor.checklist(analysis, design):
			_v.add_child(_text(("✓  " if it.ok else "✗  ") + str(it.text), Game.GOOD if it.ok else Game.MARK, 15))
	_v.add_child(_text(tr("HP_GIVEUP_NOTE"), Game.INK_DIM, 13))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	var give := Button.new()
	give.text = "HP_GIVEUP"
	give.disabled = solution(mission).is_empty()
	give.pressed.connect(open_solution)
	row.add_child(give)
	var ok := Button.new()
	ok.text = "HP_KEEP"
	ok.theme_type_variation = "Primary"
	ok.pressed.connect(func() -> void: visible = false)
	row.add_child(ok)
	_v.add_child(row)
	visible = true
	ok.grab_focus.call_deferred()


func open_solution() -> void:
	var sol := solution(mission)
	if sol.is_empty():
		return
	Game.first_time("solution_seen_%d" % mission) # el informe limita las estrellas
	_clear()
	var d: Array = sol.design
	var a := RocketAnalysis.analyze(d, mission, false)
	_v.add_child(_l("HP_SOL_EYEBROW", "Eyebrow"))
	_v.add_child(_title(tr("HP_SOL_TITLE") % tr("LEVEL_%d_NAME" % mission)))
	_v.add_child(_text(tr("HP_SOL_INTRO"), Game.INK_DIM, 15))
	var n := 1
	for step: Array in _steps(d, a):
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", Game._box(Color(Game.PAPER, 0.9), 1, Game.LINE, Vector4(16, 10, 16, 12)))
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 4)
		card.add_child(cv)
		var t := _text("%d · %s" % [n, step[0]], Game.MARK, 20)
		t.add_theme_font_override("font", Game.font_display_medium)
		cv.add_child(t)
		cv.add_child(_text(step[1], Game.INK, 14))
		_v.add_child(card)
		n += 1
	# Resumen con los números
	var need := float(a.dv_required)
	_v.add_child(_text(tr("HP_SOL_COST") % [Game.fmt(float(a.cost_rocket) / 1e6, 1), Game.fmt(float(a.cost_payload) / 1e6, 1), int(a.payload_mass)], Game.INK_DIM, 14))
	_v.add_child(_text(tr("HP_SOL_SUM") % [Game.fmt(float(a.dv_total) / 1000.0, 2), Game.fmt(need / 1000.0, 1), Game.fmt(float(a.cost) / 1e6, 1), Game.fmt(float(a.budget) / 1e6, 0), int(a.probe.science_max), int(a.probe.target)], Game.GOOD, 16))
	_v.add_child(_text(tr("HP_SOL_NOTE"), Game.INK_DIM, 13))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	var close := Button.new()
	close.text = "CR_CLOSE"
	close.pressed.connect(func() -> void: visible = false)
	row.add_child(close)
	var load_b := Button.new()
	load_b.text = "HP_LOAD"
	load_b.theme_type_variation = "Primary"
	load_b.pressed.connect(func() -> void:
		load_solution.emit((d as Array).duplicate(true))
		visible = false)
	row.add_child(load_b)
	_v.add_child(row)
	visible = true
	_scroll.set_deferred("scroll_vertical", 0)
	load_b.grab_focus.call_deferred()


## Pasos de abajo hacia arriba: [título, explicación con números].
func _steps(d: Array, a: Dictionary) -> Array:
	var out := []
	var stages: Array = a.stages
	var parts: Array = a.parts
	# Recorrer de abajo hacia arriba; la etapa sube en cada desacoplador
	var st := 0
	var i := d.size() - 1
	while i >= 0:
		var p: Dictionary = d[i]
		var kind: String = Catalog.parts[p.id].kind
		match kind:
			"engine":
				var e: Dictionary = Catalog.engines.get(str(p.get("engine", "")), {})
				var tank: Dictionary = d[i - 1] if i > 0 else {}
				var s: Dictionary = stages[mini(st, stages.size() - 1)]
				var eng_name := str(e.get("reference", p.get("engine", ""))).split(" (")[0]
				var prop := str(tank.get("propellant", e.get("propellant", "")))
				var why_key := "HP_WHY_FIRST" if st == 0 else ("HP_WHY_UPPER_H2" if prop == "lox_lh2" else "HP_WHY_UPPER")
				out.append([tr("HP_STAGE") % [st + 1, int(p.get("count", 1)), eng_name, tr("HP_PROP_" + prop) if prop != "" else "", Game.fmt(float(tank.get("length", 0.0)), 1)],
					tr(why_key) % [Game.fmt(float(s.twr), 2), int(round(float(s.isp))), Game.fmt(float(s.dv) / 1000.0, 2)] + " " + tr("HP_MAT_" + str(tank.get("material", "aluminium")))])
				i -= 2 # el motor y su tanque
				continue
			"solid":
				var s0: Dictionary = stages[0]
				out.append([tr("HP_SOLID") % Game.fmt(float(p.length), 1), tr("HP_WHY_SOLID") % [Game.fmt(float(s0.twr), 2), Game.fmt(float(s0.dv) / 1000.0, 2)]])
			"decoupler":
				out.append([tr("HP_DECOUPLER"), tr("HP_WHY_DECOUPLER") % (st + 1)])
				st += 1
			"payload":
				var cfg: Dictionary = p.get("probe", {})
				var ev: Dictionary = a.get("probe", {})
				var names := []
				for id in cfg.get("instruments", []):
					names.append(Codex.pick(Probe.item("instruments", str(id)).get("name", {})))
				out.append([tr("HP_PROBE"), tr("HP_WHY_PROBE") % [", ".join(names), int(ev.science_max), int(ev.target),
					Codex.pick(Probe.item("power", str(cfg.get("power", ""))).get("name", {})), int(ev.have_w), int(ev.need_w),
					Codex.pick(Probe.item("antennas", str(cfg.get("antenna", ""))).get("name", {}))]])
				var gear := []
				for gid in cfg.get("landing", []):
					gear.append(Codex.pick(Probe.item("landing", str(gid)).get("name", {})))
				if not gear.is_empty():
					out.append([tr("HP_GEAR_T"), tr("HP_GEAR") % ", ".join(gear)])
			"nose":
				out.append([tr("HP_NOSE"), tr("HP_WHY_NOSE") % Game.fmt(float(a.get("cd", 0.0)), 2)])
		i -= 1
	return out


func _clear() -> void:
	for c in _v.get_children():
		c.queue_free()


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
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	t.add_theme_font_size_override("font_size", 40)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return t


func _text(text: String, col: Color, fs: int) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Body"
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", fs)
	return l
