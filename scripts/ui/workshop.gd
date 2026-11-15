extends Control
## Taller: biblioteca de piezas (propias y de internet), plano del cohete y
## panel con el editor de la pieza elegida y el análisis en vivo.

const KIND_ORDER := ["nose", "payload", "solid", "tank", "engine", "decoupler", "adapter"]
const BODY_KINDS := ["tank", "solid", "payload", "engine"]

var design: Array = []
var analysis: Dictionary = {}
var level := 0
## Misión contra la que se mide el cohete: la de la campaña, o la que se elige en el taller libre (-1 = vuelo libre)
var mission := 0
var sandbox := false
var selected := -1

var _canvas: RocketCanvas
var _hangar: HangarView
var _tab_3d: Button
var _tab_plan: Button
var _view_hint: Label
static var _last_tab := "3d"
var _editor: VBoxContainer
var _stats: VBoxContainer
var _details_open := false ## análisis: etapas y tabla de números a la vista
var _dv_meter: Meter
var _cost_meter: Meter
var _launch: Button
var _launch_hint: Label
var _result: Control
var _codex: Control
var _codex_btn: Button
var _side_scroll: ScrollContainer
var _help_btn: Button
var _library_panel: Control
var _editor_panel: Control
var _launched := false
var tutorial: HoustonRadio
var comms: CommsBar
var _tut_step: Dictionary = {} # paso actual del tutorial (vacío = sin tutorial)
var _library_items: Array[LibraryItem] = []
var _library_list: VBoxContainer
var _design_btn: Button
var _ai: ViabilityPanel
var _help: HelpPanel
var _job: MissionBrief
var _my_btn: MenuButton
var _real_btn: MenuButton
var _tab_buttons: Array[Button] = []
static var _comms_data := {}
static var _info_open := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Catalog.load_all()
	sandbox = Game.sandbox or Game.selected_level < 0
	level = 9 if sandbox else Game.selected_level
	mission = Game.sandbox_mission if sandbox else level
	design = Game.load_design(-1 if sandbox else level)
	var want_tutorial := (level == 0 and not sandbox and not bool(Game.progress.get("tutorial_done", false))) or "--tutorial" in OS.get_cmdline_user_args()
	# Misiones 1 y 2: tutoriales guiados la primera vez (motores líquidos y etapas; hidrógeno e Isp)
	if not sandbox and level in [1, 2] and not Game.progress.get("seen", {}).has("tutorial_%d" % level):
		want_tutorial = true
	# Misiones 3 a 8: tutorial corto con flechas sobre lo nuevo (instrumentos, antenas, energía...), sin borrar el cohete
	var short_tut: bool = not sandbox and level >= 3 and HoustonRadio.has_level(level) and not Game.progress.get("seen", {}).has("tutorial_%d" % level)
	if short_tut:
		want_tutorial = true
	if "--notut" in OS.get_cmdline_user_args(): # grabaciones (tráiler): sin tutorial encima
		want_tutorial = false
		short_tut = false
	if want_tutorial and not short_tut:
		design = [] # el tutorial arma el cohete desde cero
		if level == 2:
			design = (Catalog.default_designs["two_stage"] as Array).duplicate(true) # se mejora uno de dos etapas
	# El hangar 3D ocupa toda la pantalla, detrás de los paneles (que son de vidrio oscuro)
	_hangar = HangarView.new()
	_hangar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hangar.part_selected.connect(_select)
	_hangar.drop_new.connect(_add_part)
	add_child(_hangar)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	margin.add_theme_constant_override("margin_top", 44)
	margin.add_theme_constant_override("margin_bottom", 44)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", Game._box(Color(0.03, 0.07, 0.12, 0.8), 1, Color(Game.LINE, 0.7), Vector4(18, 10, 18, 10)))
	top.add_child(_top_bar())
	col.add_child(top)

	var body := HBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	col.add_child(body)
	body.add_child(_library())
	body.add_child(_center_area())
	body.add_child(_side_panel())

	_result = _build_result()
	_result.visible = false
	add_child(_result)
	_codex = _build_codex()
	_codex.visible = false
	add_child(_codex)

	comms = CommsBar.new()
	# Entre la lista de piezas (izquierda) y el análisis (derecha), sin taparlos
	comms.text_width = 500.0
	comms.shift_x = -60.0
	add_child(comms)
	# Encargo de la misión (historia XORBIT): se muestra la primera vez y con el botón "Encargo"
	_job = MissionBrief.new()
	_job.mission = mission
	_job.checklist = func() -> Array: return [] if design.is_empty() else Advisor.checklist(analysis, design)
	_job.dev_months = func() -> float: return float(analysis.get("probe", {}).get("dev_months", 12.0))
	_job.extras = func() -> Array: return Advisor.extras(mission, analysis, design, {}, 0.0)
	_job.visible = false
	add_child(_job)
	_recompute()
	_select(-1)
	var first_brief := not sandbox and not Game._smoke and not "--nobrief" in OS.get_cmdline_user_args() and Game.first_time("mission_card_%d" % level)
	if first_brief:
		if level == 0 and Game.first_time("xorbit_intro"):
			# Primera vez en el juego: bienvenida a XORBIT y después el encargo
			# Partida nueva: animación del contrato (presentación de la tripulación) y después el encargo
			var contract := ContractCinematic.new()
			contract.theme = Game.theme
			comms.visible = false
			contract.finished.connect(func() -> void:
				comms.visible = true
				_play_cinematic())
			add_child(contract)
		else:
			_play_cinematic()
	if want_tutorial:
		if first_brief:
			# El tutorial empieza cuando se cierra el encargo
			# (sin CONNECT_ONE_SHOT: con el contrato y la cinemática la ficha primero se ABRE y eso no debe gastar la conexión)
			_job.visibility_changed.connect(_on_job_closed_start_tutorial)
		else:
			_start_tutorial.call_deferred()
	elif not sandbox and Game.first_time("level_brief_%d" % level):
		# Si está la cinemática, Houston habla del encargo después (no dos voces a la vez)
		var brief_line: Dictionary = _comms().level_briefs[level]
		if is_instance_valid(_cinematic):
			_cinematic.finished.connect(func() -> void: comms.say(brief_line))
		else:
			comms.say(brief_line)
	for arg in OS.get_cmdline_user_args():
		if arg == "--codex":
			_codex.set_deferred("visible", true)
		if arg == "--designer":
			_open_designer.call_deferred("")
		if arg == "--tab=plan":
			_show_tab.call_deferred("plan")
		if arg == "--solution":
			(func() -> void:
				_ask_houston()
				_help.open_solution()).call_deferred()
		if arg == "--job":
			_job.set_deferred("visible", true)
		if arg == "--contract":
			var cc := ContractCinematic.new()
			cc.theme = Game.theme
			add_child.call_deferred(cc)
		if arg == "--cinematic":
			_play_cinematic.call_deferred()
		if arg == "--ai":
			_run_ai.call_deferred()
		if arg.begins_with("--video="):
			VideoBox.open.call_deferred(self, arg.trim_prefix("--video="))
		if arg.begins_with("--real="):
			Game._dev_no_save = true
			_load_real.call_deferred(arg.trim_prefix("--real="))
		if arg.begins_with("--select="):
			_select.call_deferred(int(arg.trim_prefix("--select=")))
		if arg.begins_with("--build="):
			Game._dev_no_save = true
			_build_demo.call_deferred(arg.trim_prefix("--build="))


func _unhandled_input(event: InputEvent) -> void:
	if _hangar.free_cam:
		return
	if event.is_action_pressed("ui_cancel"):
		if _codex.visible:
			_codex.visible = false
		elif _result.visible:
			_result.visible = false
		elif selected >= 0:
			_select(-1)
		else:
			_back()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_DELETE and selected >= 0:
		_remove(selected)
		get_viewport().set_input_as_handled()


func _comms() -> Dictionary:
	if _comms_data.is_empty():
		var f := FileAccess.open("res://data/comms.json", FileAccess.READ)
		if f:
			_comms_data = JSON.parse_string(f.get_as_text())
	return _comms_data


## Houston explica para qué sirve una pieza la primera vez que el jugador la usa.
## En el tutorial lo explica el propio guion, así que no se repite.
func _brief(kind: String) -> void:
	if tutorial != null and is_instance_valid(tutorial) and not _tut_step.is_empty():
		Game.first_time("brief_" + kind) # cuenta como explicada
		return
	if Game.first_time("brief_" + kind):
		var b: Dictionary = _comms().get("part_briefs", {}).get(kind, {})
		if not b.is_empty():
			comms.say(b)


## Houston mira el análisis y dice qué arreglar primero (scripts/core/advisor.gd).
func _ask_houston() -> void:
	var id := Advisor.suggest(analysis, design)
	var e: Dictionary = _comms().get("help", {}).get(id, {})
	if not e.is_empty():
		comms.say(e)
	if _tutorial_locked() or sandbox and mission < 0:
		return
	# Panel de ayuda: primero una pista; si el jugador se rinde, la solución explicada
	if _help == null:
		_help = HelpPanel.new()
		_help.visible = false
		add_child(_help)
		_help.load_solution.connect(func(d: Array) -> void:
			comms.clear()
			comms.skip()
			_apply_design(d))
	_help.mission = mission
	_help.analysis = analysis
	_help.design = design
	_help.help = _comms().get("help", {})
	_help.open_hint()


func _tutorial_locked() -> bool:
	return not _tut_step.is_empty()


func _part_allowed(id: String) -> bool:
	if _tut_step.is_empty():
		return true
	return id in _tut_step.get("allow", [])


## Cada paso del tutorial deja usar solo lo que pide.
func _on_tutorial_step(step: Dictionary) -> void:
	_tut_step = step
	for b in _library_items:
		b.disabled = not _part_allowed(b.part_id)
		b.modulate.a = 1.0 if not b.disabled else 0.35
	var tabs_ok := step.is_empty() or bool(step.get("tabs", false))
	_design_btn.disabled = not step.is_empty()
	if _help_btn:
		_help_btn.disabled = not step.is_empty()
	if _real_btn:
		_real_btn.disabled = not step.is_empty()
	for t in _tab_buttons:
		t.disabled = not tabs_ok
	if step.has("select"):
		for i in design.size():
			if Catalog.parts[design[i].id].kind == step.select:
				_select(i)
				break
	_update_stats()
	if step.is_empty():
		_build_editor()


## Arranca el tutorial la primera vez que se CIERRA la ficha del encargo.
func _on_job_closed_start_tutorial() -> void:
	if _job.visible or tutorial != null:
		return
	_job.visibility_changed.disconnect(_on_job_closed_start_tutorial)
	_start_tutorial()


func _start_tutorial() -> void:
	tutorial = HoustonRadio.new()
	if level >= 1 and not sandbox and HoustonRadio.has_level(level):
		tutorial.level_key = str(level)
	tutorial.targets = {"view": _hangar, "library": _library_panel, "editor": _editor_panel, "dv_meter": _dv_meter,
		"cost_meter": _cost_meter, "tab_plan": _tab_plan, "canvas": _canvas, "codex": _codex_btn, "launch": _launch, "stats": _stats}
	for b in _library_items:
		tutorial.targets["part:" + str(b.part_id)] = b # para señalar la pieza exacta de la lista
	tutorial.check = _tutorial_check
	tutorial.step_changed.connect(_on_tutorial_step)
	tutorial.finished.connect(func() -> void:
		if tutorial.level_key == "0":
			Game.progress["tutorial_done"] = true
		else:
			Game.first_time("tutorial_" + tutorial.level_key)
		Game.save_progress())
	add_child(tutorial)


## Condiciones de los pasos del tutorial (data/tutorial.json → until).
func _tutorial_check(cond: String) -> bool:
	var first := {}
	for i in design.size():
		var k: String = Catalog.parts[design[i].id].kind
		if not first.has(k):
			first[k] = i
	match cond:
		"has_solid":
			return first.has("solid")
		"payload_selected":
			return selected >= 0 and selected < design.size() and Catalog.parts[design[selected].id].kind == "payload"
		"has_fins":
			for p in design:
				if int(p.get("fins", {}).get("count", 0)) > 0:
					return true
			return false
		"payload_on_top":
			return first.has("payload") and first.has("solid") and int(first.payload) < int(first.solid)
		"nose_first":
			return not design.is_empty() and Catalog.parts[design[0].id].kind == "nose"
		"dv_ok":
			return float(analysis.get("dv_total", 0.0)) >= float(analysis.get("dv_required", 0.0)) and float(analysis.get("dv_total", 0.0)) > 0.0
		"tab_plan":
			return _last_tab == "plan"
		"stable":
			return float(analysis.get("stability", -99.0)) >= 1.0
		"in_budget":
			return float(analysis.get("budget", 0.0)) <= 0.0 or float(analysis.get("cost", 0.0)) <= float(analysis.get("budget", 0.0))
		"launched":
			return _launched
		"has_engine":
			return first.has("engine")
		"tank_above_engine":
			return first.has("tank") and first.has("engine") and int(first.tank) < int(first.engine)
		"twr_ok":
			var st: Array = analysis.get("stages", [])
			return not st.is_empty() and float(st[0].twr) >= 1.2
		"has_decoupler":
			return first.has("decoupler")
		"two_stages":
			var ws := []
			for wv in analysis.get("warnings", []):
				ws.append(wv.key)
			return (analysis.get("stages", []) as Array).size() >= 2 and not "W_NO_ENGINE" in ws and not "W_NO_FUEL" in ws
		"payload_nose":
			return first.has("payload") and not design.is_empty() and Catalog.parts[design[0].id].kind == "nose"
		"has_lh2":
			for p in design:
				if p.get("propellant", "") == "lox_lh2":
					return true
			return false
		"upper_hydrogen_engine":
			var dec := int(first.get("decoupler", design.size()))
			for i in dec:
				if Catalog.parts[design[i].id].kind == "engine":
					var e: Dictionary = Catalog.engines.get(design[i].get("engine", ""), {})
					if e.get("propellant", "") == "lox_lh2":
						return true
			return false
	return false


func _back() -> void:
	Game.goto("menu" if sandbox else "levels")


# ---------- Construcción de la pantalla ----------

func _top_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	var back := Button.new()
	back.text = "UI_BACK"
	back.custom_minimum_size = Vector2(110, 40)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_back)
	bar.add_child(back)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -4)
	var eyebrow := _label("", "Eyebrow")
	eyebrow.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	eyebrow.text = tr("WS_SANDBOX").to_upper() if sandbox else (tr("LEVELS_MISSION") % level) + " · " + tr("WS_TITLE").to_upper()
	titles.add_child(eyebrow)
	var title := _label("WS_SANDBOX" if sandbox else "LEVEL_%d_NAME" % level, "Title")
	title.add_theme_font_size_override("font_size", 44)
	# Nombres largos de misión se recortan con "…" en vez de empujar Lanzar fuera de la pantalla
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size.x = 120
	eyebrow.clip_text = true
	eyebrow.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	titles.add_child(title)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if sandbox:
		# En el taller libre se elige contra qué misión probar el cohete
		var pick := OptionButton.new()
		pick.add_item(tr("WS_FREE_FLIGHT"), 0)
		for l in Game.levels:
			pick.add_item(tr("LEVELS_MISSION") % int(l.id) + " · " + tr("LEVEL_%d_NAME" % int(l.id)), int(l.id) + 1)
		pick.select(mission + 1)
		pick.tooltip_text = tr("WS_MISSION_PICK_TIP")
		pick.fit_to_longest_item = false
		pick.clip_text = true
		pick.custom_minimum_size.x = 220
		pick.item_selected.connect(func(k: int) -> void:
			mission = k - 1
			Game.sandbox_mission = mission
			_recompute())
		titles.add_child(pick)
	titles.tooltip_text = title.text
	bar.add_child(titles)
	var learn := Button.new()
	_codex_btn = learn
	learn.text = "WS_CODEX"
	learn.custom_minimum_size = Vector2(0, 40)
	learn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	learn.pressed.connect(func() -> void: _codex.visible = true)
	var ask := Button.new()
	ask.text = "WS_HELP"
	ask.custom_minimum_size = learn.custom_minimum_size
	ask.size_flags_vertical = learn.size_flags_vertical
	ask.pressed.connect(_ask_houston)
	_help_btn = ask
	bar.add_child(learn)
	bar.add_child(ask)
	# Lo que se usa menos va en un solo menú "Más" (antes eran tres botones más en la barra)
	var more := MenuButton.new()
	more.text = tr("WS_MORE") + " ▾"
	more.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	more.flat = false
	more.custom_minimum_size = Vector2(0, 40)
	more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pm := more.get_popup()
	pm.add_theme_font_size_override("font_size", 18)
	if not sandbox:
		pm.add_item(tr("WS_JOB"), 0)
	pm.add_item(tr("WS_AI"), 1)
	pm.set_item_tooltip(pm.get_item_index(1), tr("WS_AI_TIP"))
	pm.add_check_item(tr("SET_NIGHT"), 2) # día / noche en el hangar y el Centro Espacial
	pm.set_item_checked(pm.get_item_index(2), bool(Game.settings.get("night", false)))
	pm.set_item_tooltip(pm.get_item_index(2), tr("WS_NIGHT_TIP"))
	pm.id_pressed.connect(func(id: int) -> void:
		if id == 0:
			_job.visible = true
		elif id == 1:
			_run_ai()
		elif id == 2:
			var on := not pm.is_item_checked(pm.get_item_index(2))
			pm.set_item_checked(pm.get_item_index(2), on)
			Game.set_night(on)
			if _hangar.world:
				_hangar.world.set_night(on))
	bar.add_child(more)
	_dv_meter = Meter.new()
	_dv_meter.caption = "ST_TOTAL_DV"
	bar.add_child(_dv_meter)
	_cost_meter = Meter.new()
	_cost_meter.caption = "ST_COST"
	_cost_meter.more_is_better = false
	bar.add_child(_cost_meter)
	_dv_meter.mouse_filter = Control.MOUSE_FILTER_STOP
	_dv_meter.tooltip_text = Codex.tip("dv")
	_launch = Button.new()
	_launch.text = "WS_LAUNCH"
	_launch.theme_type_variation = "Primary"
	_launch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_launch.pressed.connect(_on_launch)
	bar.add_child(_launch)
	return bar


func _center_area() -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tabs := HBoxContainer.new()
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	_tab_3d = _tab_button("WS_TAB_3D", group)
	_tab_plan = _tab_button("WS_TAB_PLAN", group)
	_tab_buttons = [_tab_3d, _tab_plan]
	_tab_3d.pressed.connect(func() -> void: _show_tab("3d"))
	_tab_plan.pressed.connect(func() -> void: _show_tab("plan"))
	tabs.add_child(_tab_3d)
	tabs.add_child(_tab_plan)
	var cut := Button.new()
	cut.text = "WS_CUTAWAY"
	cut.toggle_mode = true
	cut.tooltip_text = tr("WS_CUTAWAY_TIP")
	cut.toggled.connect(func(on: bool) -> void:
		_show_tab("3d")
		_hangar.set_cutaway(on))
	tabs.add_child(cut)
	if "--cutaway" in OS.get_cmdline_user_args():
		cut.set_pressed.call_deferred(true)
	var gap := Control.new()
	gap.custom_minimum_size.x = 12
	tabs.add_child(gap)
	_view_hint = _label("", "Hint")
	_view_hint.add_theme_font_size_override("font_size", 13)
	_view_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_view_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view_hint.custom_minimum_size.x = 0
	_view_hint.clip_text = true
	_view_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_view_hint.mouse_filter = Control.MOUSE_FILTER_STOP
	_view_hint.tooltip_text = tr("WS_HINT_3D_FULL")
	tabs.add_child(_view_hint)
	v.add_child(tabs)
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.clip_contents = true
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE # en 3D, el ratón pasa al hangar de fondo
	v.add_child(stack)
	_canvas = RocketCanvas.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.part_selected.connect(_select)
	_canvas.drop_new.connect(_add_part)
	_canvas.drop_move.connect(_move_to)
	stack.add_child(_canvas)
	_show_tab.call_deferred(_last_tab)
	return v


func _tab_button(key: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = key
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(110, 34)
	return b


func _show_tab(tab: String) -> void:
	_last_tab = tab
	var is3d := tab == "3d"
	_hangar.visible = is3d
	_canvas.visible = not is3d
	_tab_3d.set_pressed_no_signal(is3d)
	_tab_plan.set_pressed_no_signal(not is3d)
	_view_hint.text = "WS_HINT_3D" if is3d else "WS_HINT_PLAN"


func _library() -> Control:
	var sheet := TrashPanel.new()
	_library_panel = sheet
	sheet.on_drop = func(i: int) -> void: _remove(i)
	sheet.theme_type_variation = "Sheet"
	sheet.custom_minimum_size.x = 280
	sheet.add_theme_stylebox_override("panel", Game._box(Color(0.03, 0.07, 0.12, 0.8), 1, Color(Game.LINE, 0.7), Vector4(14, 14, 10, 14)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	sheet.add_child(v)
	v.add_child(_label("WS_LIBRARY", "Eyebrow"))
	var hint := _label("WS_LIBRARY_HINT", "Hint")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	# Solo en las primeras misiones: después ya se sabe y quita espacio a la lista (queda como ayuda flotante)
	hint.visible = not sandbox and level <= 1
	v.add_child(hint)
	sheet.tooltip_text = tr("WS_LIBRARY_HINT")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_design_btn = Button.new()
	_design_btn.text = "WS_DESIGN_PART"
	_design_btn.custom_minimum_size.y = 38
	_design_btn.pressed.connect(func() -> void: _open_designer(""))
	v.add_child(_design_btn)
	var reals := Catalog.real_rockets.filter(func(r: Dictionary) -> bool: return sandbox or level >= int(r.unlock_level))
	if not reals.is_empty():
		_real_btn = MenuButton.new()
		_real_btn.text = "WS_LOAD_REAL"
		_real_btn.flat = false
		_real_btn.custom_minimum_size.y = 38
		var pop := _real_btn.get_popup()
		for k in reals.size():
			pop.add_item(tr(reals[k].name_key), k)
		pop.id_pressed.connect(func(k: int) -> void: _ask_load_real(str(reals[k].id), tr(reals[k].name_key)))
		v.add_child(_real_btn)
	_my_btn = MenuButton.new()
	_my_btn.text = "WS_MY_ROCKETS"
	_my_btn.flat = false
	_my_btn.custom_minimum_size.y = 38
	_my_btn.about_to_popup.connect(_fill_my_rockets)
	_my_btn.get_popup().id_pressed.connect(_on_my_rockets)
	v.add_child(_my_btn)
	_library_list = VBoxContainer.new()
	_library_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_library_list)
	_fill_library()
	return sheet


func _fill_library() -> void:
	for c in _library_list.get_children():
		c.queue_free()
	_library_items.clear()
	var ids := Catalog.unlocked_parts(level, sandbox)
	var mine := ids.filter(func(id: String) -> bool: return Catalog.parts[id].source == "custom")
	var groups := [["KIND_custom", mine]]
	for kind in KIND_ORDER:
		groups.append(["KIND_" + kind, ids.filter(func(id: String) -> bool:
			return Catalog.parts[id].kind == kind and Catalog.parts[id].source != "custom")])
	for g in groups:
		if (g[1] as Array).is_empty():
			continue
		var cap := _label(g[0], "Eyebrow")
		cap.add_theme_color_override("font_color", Game.INK_DIM)
		var gap := Control.new()
		gap.custom_minimum_size.y = 6
		_library_list.add_child(gap)
		_library_list.add_child(cap)
		for id in g[1]:
			_library_list.add_child(_library_item(id))
	if not _tut_step.is_empty():
		_on_tutorial_step(_tut_step)


## IA de viabilidad: 50 vuelos simulados con variaciones reales y puntaje por área.
func _run_ai() -> void:
	_explored = true # comparar alternativas (CML 3)
	if design.is_empty():
		comms.say(_comms().get("help", {}).get("help_empty", {}))
		return
	if _ai == null:
		_ai = ViabilityPanel.new()
		add_child(_ai)
	_ai.analysis = analysis
	_ai.design = design.duplicate(true)
	_ai.mission = mission
	_ai.sandbox = sandbox
	_ai.help = _comms().get("help", {})
	_ai.start()


# ---------- Sonda: instrumentos, energía y comunicaciones ----------

func _probe_cfg(i: int) -> Dictionary:
	if not design[i].has("probe"):
		design[i]["probe"] = Probe.default_config(mission)
	return design[i].probe


func _probe_editor(i: int) -> void:
	var cfg := _probe_cfg(i)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	_editor.add_child(gap)
	var head := _label("PR_TITLE", "Eyebrow")
	head.add_theme_color_override("font_color", Game.MARK)
	_editor.add_child(head)
	var hint := _label("PR_HINT", "Hint")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	_editor.add_child(hint)
	var lvl := 9 if sandbox else level
	# Cápsula con tripulación (misión tripulada: retos en la cabina)
	var crew_cap: Dictionary = Probe.data().get("crew_capsule", {})
	var crew_cb := CheckBox.new()
	crew_cb.text = "%s · %s t" % [Codex.pick(crew_cap.get("name", {})), Game.fmt(float(crew_cap.get("mass", 5500.0)) / 1000.0, 1)]
	crew_cb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	crew_cb.button_pressed = bool(cfg.get("crew", false))
	crew_cb.tooltip_text = Codex.pick(crew_cap.get("what", {}))
	crew_cb.add_theme_font_size_override("font_size", 13)
	crew_cb.add_theme_color_override("font_color", Game.MARK)
	crew_cb.clip_text = true
	crew_cb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	crew_cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crew_cb.toggled.connect(func(on: bool) -> void:
		_probe_cfg(i)["crew"] = on
		_recompute()
		_build_editor.call_deferred())
	_editor.add_child(crew_cb)
	# Instrumentos (casillas)
	_editor.add_child(_label("PR_INSTR", "Eyebrow"))
	for it: Dictionary in Probe.data().instruments:
		var cb := CheckBox.new()
		var locked := int(it.unlock) > lvl
		cb.text = "%s · %s kg · %d W" % [Codex.pick(it.name), Game.fmt(float(it.mass), 1), int(it.power_w)]
		cb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cb.button_pressed = str(it.id) in cfg.instruments
		cb.disabled = locked
		cb.tooltip_text = Codex.pick(it.what) + ("

" + tr("PR_LOCKED") % int(it.unlock) if locked else "")
		cb.add_theme_font_size_override("font_size", 13)
		cb.clip_text = true
		cb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		cb.custom_minimum_size.x = 0
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id: String = it.id
		cb.toggled.connect(func(on: bool) -> void:
			var arr: Array = _probe_cfg(i).instruments
			if on and not id in arr:
				arr.append(id)
			elif not on:
				arr.erase(id)
			_recompute()
			_build_editor.call_deferred())
		_editor.add_child(cb)
	# Energía y antena (listas)
	var dflt := Probe.default_config(mission)
	for pair in [["PR_POWER", "power", "power"], ["PR_ANTENNA", "antennas", "antenna"], ["PR_COMPUTER", "computers", "computer"],
			["PR_ADCS", "adcs", "adcs"], ["PR_GROUND", "ground", "ground"], ["PR_ORBIT", "orbits", "orbit"]]:
		var key: String = pair[2]
		if key == "orbit" and Probe.orbits_for(mission).is_empty():
			continue
		var list: Array = Probe.orbits_for(mission) if key == "orbit" else Probe.data()[pair[1]]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var cap := _label(pair[0], "Eyebrow")
		cap.custom_minimum_size.x = 92
		row.add_child(cap)
		var o := OptionButton.new()
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		o.clip_text = true
		o.fit_to_longest_item = false
		var ids := []
		for it: Dictionary in list:
			if int(it.unlock) > lvl:
				continue
			o.add_item(Codex.pick(it.name))
			o.set_item_tooltip(ids.size(), Codex.pick(it.what))
			ids.append(it.id)
		o.select(maxi(ids.find(cfg.get(key, dflt.get(key, ""))), 0))
		o.item_selected.connect(func(k: int) -> void:
			_probe_cfg(i)[key] = ids[k]
			_recompute()
			_build_editor.call_deferred())
		row.add_child(o)
		_editor.add_child(row)
	# Pruebas antes del lanzamiento y fin de misión
	_editor.add_child(_label("PR_TESTS", "Eyebrow"))
	for tst: Dictionary in Probe.data().get("tests", []):
		var tcb := CheckBox.new()
		tcb.text = "%s · US$ %s M · %d %s" % [Codex.pick(tst.name), Game.fmt(float(tst.cost_musd), 1), int(tst.months), tr("PR_MONTHS")]
		tcb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		tcb.button_pressed = str(tst.id) in cfg.get("tests", [])
		tcb.tooltip_text = Codex.pick(tst.what)
		tcb.add_theme_font_size_override("font_size", 13)
		tcb.clip_text = true
		tcb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tcb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tid: String = tst.id
		tcb.toggled.connect(func(on: bool) -> void:
			var arr: Array = _probe_cfg(i).get("tests", [])
			if on and not tid in arr:
				arr.append(tid)
			elif not on:
				arr.erase(tid)
			_probe_cfg(i)["tests"] = arr
			_recompute()
			_build_editor.call_deferred())
		_editor.add_child(tcb)
	var deo: Dictionary = Probe.data().get("deorbit", {})
	if (deo.get("dv", {}) as Dictionary).has(str(mission)):
		var dcb := CheckBox.new()
		dcb.text = "%s · +%d m/s" % [Codex.pick(deo.name), int(deo.dv[str(mission)])]
		dcb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		dcb.button_pressed = bool(cfg.get("deorbit", false))
		dcb.tooltip_text = Codex.pick(deo.what)
		dcb.add_theme_font_size_override("font_size", 13)
		dcb.clip_text = true
		dcb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		dcb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dcb.toggled.connect(func(on: bool) -> void:
			_probe_cfg(i)["deorbit"] = on
			_recompute()
			_build_editor.call_deferred())
		_editor.add_child(dcb)
	# Equipo de aterrizaje: solo en misiones que aterrizan (o en el taller libre)
	var land_items: Array = Probe.data().get("landing", []).filter(func(g: Dictionary) -> bool: return int(g.unlock) <= lvl)
	if not land_items.is_empty() and (sandbox or mission in [4, 6]):
		if not cfg.has("landing"):
			cfg["landing"] = []
		_editor.add_child(_label("PR_LANDING", "Eyebrow"))
		for g: Dictionary in land_items:
			var cb := CheckBox.new()
			var needed: bool = Probe.has_n(g.get("needed_for", []), mission)
			cb.text = "%s · %s kg%s" % [Codex.pick(g.name), Game.fmt(float(g.mass), 0), ("  · " + tr("PR_NEEDED")) if needed else ""]
			cb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			cb.button_pressed = str(g.id) in cfg.landing
			cb.tooltip_text = Codex.pick(g.what)
			cb.add_theme_font_size_override("font_size", 13)
			cb.clip_text = true
			cb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if needed and not cb.button_pressed:
				cb.add_theme_color_override("font_color", Game.MARK)
			var gid: String = g.id
			cb.toggled.connect(func(on: bool) -> void:
				var arr: Array = _probe_cfg(i).get("landing", [])
				if on and not gid in arr:
					arr.append(gid)
				elif not on:
					arr.erase(gid)
				_probe_cfg(i)["landing"] = arr
				_recompute()
				_build_editor.call_deferred())
			_editor.add_child(cb)
	# Balance en el destino
	var ev: Dictionary = analysis.get("probe", {})
	if ev.is_empty():
		return
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var lines := [
		[tr("PR_MASS") % [Game.fmt(float(ev.mass), 1), Game.fmt(float(ev.cost) / 1e6, 1)], Game.INK_DIM],
		[tr("PR_ENERGY") % [int(ev.have_w), int(ev.need_w)] + ("  ✓" if ev.power_ok else "  ✗"), Game.GOOD if ev.power_ok else Game.MARK],
		[tr("PR_LINK") % _km_text(float(ev.range_km), float(ev.link_km)) + ("  ✓" if ev.link_ok else "  ✗"), Game.GOOD if ev.link_ok else Color("#e5484d")],
		[tr("PR_SCIENCE") % [int(ev.science_max), int(ev.target)], Game.GOOD if float(ev.science_max) >= float(ev.target) else Game.MARK],
	]
	for ln in lines:
		var l := _label(str(ln[0]), "Body")
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", ln[1])
		box.add_child(l)
	_editor.add_child(box)


func _km_text(range_km: float, need_km: float) -> String:
	var f := func(x: float) -> String:
		return Game.fmt(x / 1e6, 0) + " M km" if x >= 1e6 else Game.fmt(x, 0) + " km"
	return "%s / %s" % [f.call(range_km), f.call(need_km)]


# ---------- Mis cohetes: guardar soluciones, exportar e importar ----------

func _fill_my_rockets() -> void:
	var pop := _my_btn.get_popup()
	pop.clear()
	for c in pop.get_children():
		if c is PopupMenu:
			c.queue_free()
	pop.add_item(tr("MY_SAVE"), 1)
	pop.add_item(tr("MY_EXPORT"), 2)
	pop.add_item(tr("MY_IMPORT"), 3)
	pop.set_item_disabled(0, design.is_empty())
	pop.set_item_disabled(1, design.is_empty())
	var saved := Game.list_rockets()
	if not saved.is_empty():
		pop.add_separator(tr("MY_SAVED"))
		for k in saved.size():
			pop.add_item(str(saved[k].name), 100 + k)
		var del := PopupMenu.new()
		del.name = "Del"
		for k in saved.size():
			del.add_item(str(saved[k].name), k)
		del.id_pressed.connect(func(k: int) -> void:
			Game.delete_rocket(str(saved[k].file))
			comms.say({"en": "Deleted from My rockets.", "es": "Borrado de Mis cohetes."}, "XORBIT"))
		pop.add_child(del)
		pop.add_submenu_node_item(tr("MY_DELETE"), del)


func _on_my_rockets(id: int) -> void:
	match id:
		1:
			var def := tr("LEVEL_%d_NAME" % mission) if mission >= 0 else tr("WS_SANDBOX")
			_ask_text(tr("MY_SAVE"), tr("MY_NAME"), def, func(nm: String) -> void:
				Game.save_rocket(nm, design)
				_explored = true
				comms.say({"en": "Saved in My rockets: %s." % nm, "es": "Guardado en Mis cohetes: %s." % nm}, "XORBIT"))
		2:
			var fd := _file_dialog(FileDialog.FILE_MODE_SAVE_FILE)
			fd.current_file = "mi_cohete.xorbit.json"
			fd.file_selected.connect(func(path: String) -> void:
				Game.export_rocket(path, path.get_file().get_basename().get_basename(), design)
				comms.say({"en": "Exported to %s" % path, "es": "Exportado a %s" % path}, "XORBIT"))
			fd.popup_centered_ratio(0.6)
		3:
			var fd := _file_dialog(FileDialog.FILE_MODE_OPEN_FILE)
			fd.file_selected.connect(func(path: String) -> void:
				var d := Game.import_rocket(path)
				if d.is_empty():
					comms.say({"en": "That file is not a Xorbit rocket.", "es": "Ese archivo no es un cohete de Xorbit."}, "XORBIT")
				else:
					_apply_design(d))
			fd.popup_centered_ratio(0.6)
		_:
			var saved := Game.list_rockets()
			var k := id - 100
			if k >= 0 and k < saved.size():
				_apply_design(saved[k].design)


func _apply_design(d: Array) -> void:
	if _tutorial_locked():
		return
	design = d.filter(func(p: Variant) -> bool: return p is Dictionary and Catalog.parts.has(p.get("id", "")))
	_select(-1)
	_recompute()


func _file_dialog(mode: FileDialog.FileMode) -> FileDialog:
	var fd := FileDialog.new()
	fd.file_mode = mode
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.filters = PackedStringArray(["*.json ; Xorbit"])
	fd.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	fd.visibility_changed.connect(func() -> void:
		if not fd.visible:
			fd.queue_free.call_deferred())
	add_child(fd)
	return fd


## Pide un texto (nombre) en un cuadro propio.
func _ask_text(title: String, caption: String, default: String, done: Callable) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = title
	dlg.ok_button_text = tr("SV_SAVE")
	var v := VBoxContainer.new()
	var l := Label.new()
	l.text = caption
	v.add_child(l)
	var e := LineEdit.new()
	e.text = default
	e.max_length = 40
	e.custom_minimum_size.x = 360
	v.add_child(e)
	dlg.add_child(v)
	dlg.register_text_enter(e)
	dlg.confirmed.connect(func() -> void:
		if e.text.strip_edges() != "":
			done.call(e.text.strip_edges()))
	dlg.visibility_changed.connect(func() -> void:
		if not dlg.visible:
			dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()
	e.select_all.call_deferred()
	e.grab_focus.call_deferred()


func _ask_load_real(id: String, title: String) -> void:
	if _tutorial_locked():
		return
	if design.is_empty():
		_load_real(id)
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = title
	dlg.dialog_text = tr("WS_LOAD_REAL_CONFIRM") % title
	dlg.ok_button_text = tr("WS_LOAD_REAL_OK")
	dlg.cancel_button_text = tr("PD_CANCEL")
	dlg.confirmed.connect(func() -> void: _load_real(id))
	dlg.visibility_changed.connect(func() -> void:
		if not dlg.visible:
			dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()


func _load_real(id: String) -> void:
	design = (Catalog.default_designs[id] as Array).duplicate(true)
	_select(-1)
	_recompute()
	var e: Dictionary = _comms().get("real_briefs", {}).get(id, {})
	if not e.is_empty():
		comms.say(e)


## Para grabar el video: arma un cohete real pieza por pieza, de abajo hacia arriba, como lo haría un jugador.
func _build_demo(id: String) -> void:
	var full: Array = (Catalog.default_designs[id] as Array).duplicate(true)
	design = []
	_select(-1)
	_recompute()
	await get_tree().create_timer(0.6).timeout
	for i in range(full.size() - 1, -1, -1):
		design.insert(0, full[i])
		if not "--nohud" in OS.get_cmdline_user_args(): # sin interfaz: la cámara encuadra el cohete entero
			_select(0)
		_recompute()
		await get_tree().create_timer(0.4).timeout
	_select(-1)


func _open_designer(id: String) -> void:
	if _tutorial_locked():
		return
	var d := PartDesigner.new()
	d.level = level
	d.sandbox = sandbox
	if id != "":
		var t := Catalog.template(id)
		d.editing_id = id
		d.points = (t.profile as Array).duplicate(true)
		d.kind = t.kind
		d.part_name = str(t.get("name", ""))
		d.length = float(t.defaults.get("length", 2.0))
		d.diameter = float(t.defaults.get("diameter", 1.0))
		d.mat_id = str(t.defaults.get("material", "aluminium"))
	d.saved.connect(func(_new_id: String) -> void:
		# Quitar del diseño las piezas propias que ya no existan
		design = design.filter(func(p: Dictionary) -> bool: return Catalog.parts.has(p.id))
		_fill_library()
		_recompute()
		_select(-1))
	add_child(d)


func _library_item(id: String) -> Button:
	var t := Catalog.template(id)
	var b := LibraryItem.new()
	b.part_id = id
	_library_items.append(b)
	b.custom_minimum_size = Vector2(0, 70)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: _add_part(id))
	if t.source == "custom":
		b.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
				_open_designer(id))
		b.tooltip_text = tr("WS_EDIT_HINT")
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var pad := Control.new()
	pad.custom_minimum_size.x = 2
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(pad)
	var thumb := PartThumb.new()
	thumb.setup(Catalog.new_part(id))
	h.add_child(thumb)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var n := _label(Catalog.display_name(id), "Body")
	n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	n.add_theme_font_override("font", Game.font_display_medium)
	n.add_theme_font_size_override("font_size", 21)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(n)
	var src := _label({"kenney": "WS_SRC_KENNEY", "custom": "WS_SRC_CUSTOM"}.get(t.source, "WS_SRC_OWN"), "Hint")
	src.add_theme_font_size_override("font_size", 12)
	if t.source == "kenney":
		src.add_theme_color_override("font_color", Game.MARK)
	src.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(src)
	return b


func _side_panel() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 400
	# SHOW_NEVER (no DISABLED): así un texto largo no ensancha el panel y lo empuja fuera de la pantalla
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_side_scroll = scroll
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 14)
	scroll.add_child(v)
	var ed_sheet := PanelContainer.new()
	_editor_panel = ed_sheet
	ed_sheet.theme_type_variation = "Sheet"
	ed_sheet.add_theme_stylebox_override("panel", Game._box(Color(0.03, 0.07, 0.12, 0.8), 1, Color(Game.LINE, 0.7), Vector4(20, 16, 20, 18)))
	_editor = VBoxContainer.new()
	_editor.add_theme_constant_override("separation", 8)
	ed_sheet.add_child(_editor)
	v.add_child(ed_sheet)
	var st_sheet := PanelContainer.new()
	st_sheet.theme_type_variation = "Sheet"
	st_sheet.add_theme_stylebox_override("panel", Game._box(Color(0.03, 0.07, 0.12, 0.8), 1, Color(Game.LINE, 0.7), Vector4(20, 16, 20, 18)))
	_stats = VBoxContainer.new()
	_stats.add_theme_constant_override("separation", 6)
	st_sheet.add_child(_stats)
	v.add_child(st_sheet)
	return scroll


# ---------- Edición del diseño ----------

func _add_part(id: String, drop_at := -1) -> void:
	if not _part_allowed(id):
		return
	var p := Catalog.new_part(id)
	var kind: String = Catalog.parts[id].kind
	var at := design.size()
	if _tut_step.has("insert_at"):
		at = mini(int(_tut_step.insert_at), design.size())
	elif drop_at >= 0:
		at = mini(drop_at, design.size())
	elif selected >= 0:
		at = selected + 1
	elif kind == "nose":
		at = 0
	# Igualar el diámetro con la pieza vecina para que encaje
	var neighbor: Dictionary = {}
	if at < design.size():
		neighbor = design[at]
	elif at > 0:
		neighbor = design[at - 1]
	if not neighbor.is_empty() and kind != "adapter":
		var d := float(neighbor.get("diameter", p.get("diameter", 1.0)))
		var old_d := float(p.get("diameter", d))
		p.diameter = d
		if Catalog.parts[id].has("profile") and p.has("length"):
			p.length = snappedf(float(p.length) * d / old_d, 0.05)
		if p.has("fins"):
			for k in ["span", "root", "tip", "offset"]:
				if p.fins.has(k):
					p.fins[k] = snappedf(float(p.fins[k]) * d / old_d, 0.01)
	design.insert(at, p)
	_select(at)
	_recompute()
	_brief(kind)


func _remove(i: int) -> void:
	if i < 0 or i >= design.size() or _tutorial_locked():
		return
	design.remove_at(i)
	_select(mini(i, design.size() - 1) if not design.is_empty() else -1)
	_recompute()


## Mover una pieza arrastrándola a la posición de inserción k.
func _move_to(i: int, k: int) -> void:
	if i < 0 or i >= design.size() or _tutorial_locked():
		return
	var p: Dictionary = design[i]
	design.remove_at(i)
	if k > i:
		k -= 1
	k = clampi(k, 0, design.size())
	design.insert(k, p)
	_select(k)
	_recompute()


func _move(i: int, dir: int) -> void:
	if _tutorial_locked():
		return
	var j := i + dir
	if j < 0 or j >= design.size():
		return
	var tmp: Dictionary = design[i]
	design[i] = design[j]
	design[j] = tmp
	_select(j)
	_recompute()


func _select(i: int) -> void:
	selected = i if i >= 0 and i < design.size() else -1
	_canvas.selected = selected
	_hangar.selected = selected
	_build_editor()
	_fit_side.call_deferred()


func _set_param(i: int, key: String, value: Variant) -> void:
	design[i][key] = value
	_recompute()


func _set_fin(i: int, key: String, value: float) -> void:
	design[i].fins[key] = value
	_recompute()


## Ajusta al ancho del panel derecho todo lo que podría salirse: listas desplegables recortan
## su texto y las etiquetas sueltas de una columna pasan a varias líneas.
func _fit_side() -> void:
	if _side_scroll == null:
		return
	for n in _side_scroll.find_children("*", "Control", true, false):
		if n is OptionButton:
			(n as OptionButton).clip_text = true
			(n as OptionButton).fit_to_longest_item = false
			(n as OptionButton).custom_minimum_size.x = 0
			(n as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		elif n is Label and n.get_parent() is VBoxContainer:
			var l := n as Label
			if l.autowrap_mode == TextServer.AUTOWRAP_OFF and l.theme_type_variation != "Title":
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			elif l.theme_type_variation == "Title":
				l.clip_text = true
				l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		elif n is Label and n.get_parent() is HBoxContainer and (n as Label).size_flags_horizontal & Control.SIZE_EXPAND:
			(n as Label).clip_text = true
			(n as Label).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


## Nivel de madurez del concepto (JPL): 1 idea, 2 factible, 3 alternativas comparadas, 4 diseño puntual con márgenes.
func _cml() -> int:
	if design.is_empty():
		return 1
	var stages: Array = analysis.get("stages", [])
	var feasible := float(analysis.get("dv_total", 0.0)) > 0.0 and not stages.is_empty() and float(stages[0].twr) >= 1.0
	if not feasible:
		return 1
	if not (_explored or _edits >= 6):
		return 2
	for it: Dictionary in Advisor.checklist(analysis, design):
		if not it.ok:
			return 3
	var need := float(analysis.get("dv_required", 0.0))
	if need > 0.0 and float(analysis.get("dv_total", 0.0)) < need * 1.03:
		return 3 # sin margen todavía no es un diseño puntual
	return 4


var _edits := 0
var _explored := false


## Cinemática del encargo (Houston en la Sala de Control y el destino); al terminar se abre la ficha del encargo.
var _cinematic: MissionCinematic


func _play_cinematic() -> void:
	var cin := MissionCinematic.new()
	_cinematic = cin
	cin.mission = mission
	cin.theme = Game.theme
	comms.clear()
	comms.skip()
	comms.visible = false # la cinemática tiene su propia voz y texto
	cin.finished.connect(func() -> void:
		comms.visible = true
		_job.visible = true)
	add_child(cin)


func _recompute() -> void:
	_edits += 1
	analysis = RocketAnalysis.analyze(design, mission, sandbox)
	_canvas.set_data(design, analysis)
	_hangar.set_design(design, analysis)
	_update_stats()
	_fit_side.call_deferred()
	Game.save_design(-1 if sandbox else level, design)


# ---------- Editor de la pieza elegida ----------

func _build_editor() -> void:
	for c in _editor.get_children():
		c.queue_free()
	# Sin pieza elegida, el panel no se muestra (antes ocupaba espacio con una frase de ayuda)
	_editor_panel.visible = selected >= 0 or _tut_step.get("target", "") == "editor"
	if selected < 0:
		_editor.add_child(_label("ED_TITLE", "Eyebrow"))
		var h := _label("ED_NONE", "Hint")
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_editor.add_child(h)
		return
	var p: Dictionary = design[selected]
	var t := Catalog.template(p.id)
	var kind: String = t.kind
	_editor.add_child(_label("ED_TITLE", "Eyebrow"))
	var n := _label(Catalog.display_name(str(p.id)), "Title")
	n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	n.add_theme_font_size_override("font_size", 32)
	_editor.add_child(n)
	if t.source == "kenney":
		var src := _label("WS_SRC_KENNEY", "Hint")
		src.add_theme_color_override("font_color", Game.MARK)
		src.add_theme_font_size_override("font_size", 12)
		_editor.add_child(src)

	_part_info(kind)

	var i := selected
	if not (kind == "engine" and not t.has("profile")):
		_slider(i, "ED_LENGTH", "length", 0.2, 60.0, 0.05, "m")
	_slider(i, "ED_DIAMETER", "diameter", 0.2, 10.0, 0.05, "m")
	if kind == "adapter":
		_slider(i, "ED_DIAMETER_TOP", "diameter_top", 0.2, 10.0, 0.05, "m")
	if kind == "payload":
		_slider(i, "ED_PAYLOAD", "payload_kg", 0.0, 20000.0, 10.0, "kg")
		_probe_editor(i)
	if kind == "engine":
		var engines := Catalog.unlocked(Catalog.engines, level, sandbox).filter(func(id: String) -> bool: return id != "solid_basic")
		_option(i, "ED_ENGINE", "engine", engines, func(id: String) -> String:
			var e: Dictionary = Catalog.engines[id]
			return "%s · %s kN" % [str(e.reference).split(" (")[0], Game.fmt(float(e.thrust_vac) / 1000.0, 0 if float(e.thrust_vac) >= 1000.0 else 3)])
		_slider(i, "ED_COUNT", "count", 1, 9, 1, "")
	if kind == "tank":
		_option(i, "ED_PROPELLANT", "propellant", Catalog.unlocked(Catalog.propellants, level, sandbox).filter(func(id: String) -> bool: return id != "solid"),
			func(id: String) -> String: return Catalog.propellants[id].label)
	if kind != "engine" or t.has("profile"):
		_option(i, "ED_MATERIAL", "material", Catalog.unlocked(Catalog.materials, level, sandbox),
			func(id: String) -> String: return tr("MAT_" + id))
		var card := MaterialCard.new()
		card.mat_id = str(p.get("material", "aluminium"))
		card.compact = true
		_editor.add_child(card)
		card.refresh()

	# Pintura y acabado (se ven en el hangar 3D y en el vuelo)
	_option(i, "ED_PAINT", "paint", RocketBuilder.PAINTS.keys(), func(id: String) -> String: return tr("PAINT_" + id))
	_option(i, "ED_FINISH", "finish", RocketBuilder.FINISHES.keys(), func(id: String) -> String: return tr("FINISH_" + id))

	# Aletas
	if kind in BODY_KINDS:
		var gap := Control.new()
		gap.custom_minimum_size.y = 4
		_editor.add_child(gap)
		var f: Dictionary = p.get("fins", {})
		if int(f.get("count", 0)) > 0:
			var fl := _label("ED_FINS", "Eyebrow")
			fl.mouse_filter = Control.MOUSE_FILTER_STOP
			fl.tooltip_text = Codex.part("fins", "what") + "\n\n" + Codex.part("fins", "how")
			_editor.add_child(fl)
			_fin_slider(i, "ED_FIN_COUNT", "count", 3, 4, 1, "")
			_fin_slider(i, "ED_SPAN", "span", 0.05, 4.0, 0.01, "m")
			_fin_slider(i, "ED_ROOT", "root", 0.1, 6.0, 0.01, "m")
			_fin_slider(i, "ED_TIP", "tip", 0.0, 6.0, 0.01, "m")
			var rm := Button.new()
			rm.text = "ED_REMOVE_FINS"
			rm.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			rm.custom_minimum_size.y = 34
			rm.pressed.connect(func() -> void:
				design[i].erase("fins")
				_recompute()
				_build_editor())
			_editor.add_child(rm)
		else:
			var add := Button.new()
			add.text = "ED_ADD_FINS"
			add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			add.custom_minimum_size.y = 34
			add.pressed.connect(func() -> void:
				var fd: Dictionary = (Catalog.fins_spec.get("defaults", {}) as Dictionary).duplicate()
				var d := float(design[i].get("diameter", 1.0))
				fd.span = snappedf(d * 0.6, 0.01)
				fd.root = snappedf(minf(d * 1.2, RocketAnalysis.part_length(design[i])), 0.01)
				fd.tip = snappedf(float(fd.root) * 0.4, 0.01)
				design[i]["fins"] = fd
				_recompute()
				_build_editor()
				_brief("fins"))
			_editor.add_child(add)

	# Mover y quitar
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for spec in [["ED_UP", -1], ["ED_DOWN", 1]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(0, 36)
		var dir: int = spec[1]
		b.pressed.connect(func() -> void: _move(i, dir))
		b.disabled = (dir < 0 and i == 0) or (dir > 0 and i == design.size() - 1) or _tutorial_locked()
		row.add_child(b)
	var del := Button.new()
	del.text = "ED_REMOVE"
	del.custom_minimum_size = Vector2(0, 36)
	del.add_theme_color_override("font_color", Game.MARK)
	del.pressed.connect(func() -> void: _remove(i))
	del.disabled = _tutorial_locked()
	row.add_child(del)
	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 6
	_editor.add_child(gap2)
	_editor.add_child(row)


## Qué hace la pieza (siempre visible), cómo funciona (desplegable) y un ejemplo real.
func _part_info(kind: String) -> void:
	var what := _label(Codex.part(kind, "what"), "Body")
	what.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.add_theme_font_size_override("font_size", 14)
	_editor.add_child(what)
	var toggle := Button.new()
	toggle.flat = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.add_theme_color_override("font_color", Game.MARK)
	toggle.add_theme_color_override("font_hover_color", Game.MARK.lightened(0.2))
	toggle.add_theme_font_size_override("font_size", 14)
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_editor.add_child(toggle)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var how := _label(Codex.part(kind, "how"), "Body")
	how.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.add_theme_font_size_override("font_size", 14)
	how.add_theme_color_override("font_color", Game.INK_DIM)
	box.add_child(how)
	var real := _label(tr("ED_REAL") + " " + Codex.part(kind, "real"), "Body")
	real.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	real.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	real.add_theme_font_size_override("font_size", 13)
	real.add_theme_color_override("font_color", Game.INK_DIM)
	box.add_child(real)
	_editor.add_child(box)
	var refresh := func() -> void:
		box.visible = _info_open
		toggle.text = tr("ED_HOW_HIDE") if _info_open else tr("ED_HOW_SHOW")
	refresh.call()
	toggle.pressed.connect(func() -> void:
		_info_open = not _info_open
		refresh.call())
	var line := HSeparator.new()
	line.add_theme_stylebox_override("separator", Game._box(Game.LINE, 0, Game.LINE, Vector4(0, 0, 0, 0)))
	line.add_theme_constant_override("separation", 10)
	_editor.add_child(line)


## Guía "Cómo funciona un cohete": tarjetas con los conceptos clave.
func _build_codex() -> Control:
	var veil := ColorRect.new()
	veil.color = Color(Game.PAPER_DEEP, 0.9)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 120)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	veil.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	margin.add_child(v)
	var head := HBoxContainer.new()
	var title := _label("WS_CODEX_TITLE", "Title")
	title.add_theme_font_size_override("font_size", 52)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "CR_CLOSE"
	close.custom_minimum_size = Vector2(120, 40)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void: _codex.visible = false)
	head.add_child(close)
	v.add_child(head)
	var sub := _label("WS_CODEX_SUB", "Hint")
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 16)
	scroll.add_child(col)
	# Esta misión: requisitos con su estado y la recomendación de Houston
	var mission := PanelContainer.new()
	mission.add_theme_stylebox_override("panel", Game._box(Color(Game.PAPER, 0.95), 2, Game.MARK, Vector4(22, 16, 22, 18)))
	col.add_child(mission)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 6)
	mission.add_child(mv)
	mv.add_child(_label("CX_MISSION", "Eyebrow"))
	var checks := VBoxContainer.new()
	checks.add_theme_constant_override("separation", 2)
	mv.add_child(checks)
	var advice_row := HBoxContainer.new()
	advice_row.add_theme_constant_override("separation", 12)
	mv.add_child(advice_row)
	var advice := _label("", "Body")
	advice.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	advice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	advice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	advice.add_theme_color_override("font_color", Game.MARK)
	advice_row.add_child(advice)
	var say := Button.new()
	say.text = "CX_SAY"
	say.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	say.pressed.connect(func() -> void:
		_codex.visible = false
		_ask_houston())
	advice_row.add_child(say)
	var build_fill := _codex_build(col)
	var mat_fill := _codex_materials(col)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	col.add_child(grid)
	var cards := []
	for c in Codex.concepts():
		var card := PanelContainer.new()
		card.theme_type_variation = "Sheet"
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", Game._box(Color(Game.PAPER, 0.95), 1, Game.LINE, Vector4(20, 16, 20, 18)))
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		var ct := _label("", "Title")
		ct.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		ct.add_theme_font_size_override("font_size", 28)
		var cb := _label("", "Body")
		cb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cb.add_theme_font_size_override("font_size", 15)
		var chead := HBoxContainer.new()
		ct.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chead.add_child(ct)
		var cvid := VideoBox.button(str(c.get("id", "")))
		if cvid:
			chead.add_child(cvid)
		cv.add_child(chead)
		var fig := CodexFigure.new()
		fig.kind = str(c.get("id", ""))
		fig.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cv.add_child(fig)
		cv.add_child(cb)
		card.add_child(cv)
		grid.add_child(card)
		cards.append([c, ct, cb])
	var fill := func() -> void:
		build_fill.call()
		mat_fill.call()
		for k in cards:
			k[1].text = Codex.pick(k[0].title)
			k[2].text = Codex.pick(k[0].body)
		for ch in checks.get_children():
			ch.queue_free()
		for item: Dictionary in Advisor.checklist(analysis, design):
			var row := _label(("✓  " if item.ok else "✗  ") + str(item.text), "Body")
			row.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			row.add_theme_color_override("font_color", Game.GOOD if item.ok else Game.MARK)
			checks.add_child(row)
		var e: Dictionary = _comms().get("help", {}).get(Advisor.suggest(analysis, design), {})
		advice.text = tr("CX_ADVICE") + " " + Codex.pick(e)
	fill.call()
	veil.visibility_changed.connect(fill)
	veil.visibility_changed.connect(func() -> void: scroll.set_deferred("scroll_vertical", 0))
	return veil


## Manual: cómo se arma un cohete. Dibujo que se arma solo (RocketAnatomy) y, al lado, los pasos
## con qué es cada pieza, dónde va y por qué. La fila de la pieza que se dibuja queda resaltada.
func _codex_build(col: VBoxContainer) -> Callable:
	var b := Codex.build()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Game._box(Color(Game.PAPER, 0.95), 1, Game.LINE, Vector4(22, 18, 22, 20)))
	col.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var head := HBoxContainer.new()
	var title := _label("", "Title")
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.add_theme_font_size_override("font_size", 36)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var vid := VideoBox.button("build")
	if vid:
		head.add_child(vid)
	v.add_child(head)
	var intro := _label("", "Body")
	intro.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)
	var hint := _label("CX_BUILD_HINT", "Hint")
	v.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	v.add_child(row)
	var fig := RocketAnatomy.new()
	fig.custom_minimum_size = Vector2(300, 600)
	row.add_child(fig)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	row.add_child(list)
	var rows := []
	var steps: Array = b.get("steps", [])
	for i in steps.size():
		var card := PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 2)
		card.add_child(cv)
		var ct := _label("", "Body")
		ct.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		ct.add_theme_font_override("font", Game.font_display_medium)
		ct.add_theme_font_size_override("font_size", 22)
		var cb := _label("", "Body")
		cb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cb.add_theme_font_size_override("font_size", 14)
		cv.add_child(ct)
		cv.add_child(cb)
		list.add_child(card)
		var k := i
		card.mouse_entered.connect(func() -> void: fig.hold = k)
		card.mouse_exited.connect(func() -> void: fig.hold = -1)
		rows.append([card, ct, cb])
	var paint := func(cur: int) -> void:
		for i in rows.size():
			var on := i == cur
			rows[i][0].add_theme_stylebox_override("panel", Game._box(Color(Game.MARK, 0.14) if on else Color(0, 0, 0, 0), 1 if on else 0, Game.MARK, Vector4(12, 6, 12, 8)))
			rows[i][1].add_theme_color_override("font_color", Game.MARK if on else Game.INK)
	fig.step_changed.connect(paint)
	var rules := _label("", "Body")
	rules.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.add_theme_color_override("font_color", Game.MARK)
	v.add_child(rules)
	return func() -> void:
		title.text = Codex.pick(b.get("title"))
		intro.text = Codex.pick(b.get("intro"))
		rules.text = Codex.pick(b.get("rules"))
		for i in rows.size():
			rows[i][1].text = "%d · %s" % [i + 1, Codex.pick(steps[i].title)]
			rows[i][2].text = Codex.pick(steps[i].body)
		paint.call(fig.step)


## Manual: los materiales lado a lado, con barras de densidad, resistencia, calor y costo.
func _codex_materials(col: VBoxContainer) -> Callable:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Game._box(Color(Game.PAPER, 0.95), 1, Game.LINE, Vector4(22, 18, 22, 20)))
	col.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var title := _label("", "Title")
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.add_theme_font_size_override("font_size", 36)
	v.add_child(title)
	var intro := _label("", "Body")
	intro.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)
	var holders := []
	for id: String in Catalog.materials:
		var card := MaterialCard.new()
		card.mat_id = id
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(card)
		holders.append(card)
	var mi := Codex.materials_intro()
	return func() -> void:
		title.text = Codex.pick(mi.get("title"))
		intro.text = Codex.pick(mi.get("body"))
		for c: MaterialCard in holders:
			c.refresh()


func _slider(i: int, caption: String, key: String, lo: float, hi: float, step: float, unit: String) -> void:
	var value := float(design[i].get(key, lo))
	_slider_row(caption, value, lo, hi, step, unit, func(v: float) -> void:
		_set_param(i, key, int(v) if step >= 1.0 and unit != "kg" else v))


func _fin_slider(i: int, caption: String, key: String, lo: float, hi: float, step: float, unit: String) -> void:
	_slider_row(caption, float(design[i].fins.get(key, lo)), lo, hi, step, unit, func(v: float) -> void:
		_set_fin(i, key, v))


func _slider_row(caption: String, value: float, lo: float, hi: float, step: float, unit: String, on_change: Callable) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var c := _label(caption, "Eyebrow")
	c.custom_minimum_size.x = 112
	h.add_child(c)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	var val := _label("", "Body")
	val.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	val.custom_minimum_size.x = 84
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var show_value := func(x: float) -> void:
		var num := Game.fmt_int(int(x)) if step >= 1.0 else Game.fmt(x, 2)
		val.text = (num + " " + unit).strip_edges()
	show_value.call(value)
	s.value_changed.connect(func(x: float) -> void:
		show_value.call(x)
		on_change.call(x))
	h.add_child(val)
	_editor.add_child(h)


func _option(i: int, caption: String, key: String, ids: Array, name_of: Callable) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var c := _label(caption, "Eyebrow")
	c.custom_minimum_size.x = 112
	h.add_child(c)
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	o.clip_text = true
	o.fit_to_longest_item = false
	o.custom_minimum_size.x = 0
	var current: String = design[i].get(key, "")
	for k in ids.size():
		o.add_item(name_of.call(ids[k]), k)
		if ids[k] == current:
			o.select(k)
	o.item_selected.connect(func(k: int) -> void:
		_set_param(i, key, ids[k])
		if key == "material":
			_build_editor.call_deferred() # la ficha del material cambia con él
			_fit_side.call_deferred())
	h.add_child(o)
	_editor.add_child(h)


# ---------- Análisis ----------

func _update_stats() -> void:
	for c in _stats.get_children():
		c.queue_free()
	_stats.add_child(_label("ST_TITLE", "Eyebrow"))
	var nc := NasaCycle.new()
	var lvl_cml := _cml()
	nc.set_state(lvl_cml + 1, lvl_cml)
	_stats.add_child(nc)
	if not (analysis.get("probe", {}) as Dictionary).is_empty():
		var rp := ResourcePanel.new()
		rp.set_data(analysis)
		_stats.add_child(rp)
		var gap0 := Control.new()
		gap0.custom_minimum_size.y = 4
		_stats.add_child(gap0)
	var dv_req := float(analysis.get("dv_required", 0.0))
	var dv := float(analysis.get("dv_total", 0.0))
	_dv_meter.set_values(dv, dv_req, "%s / %s km/s" % [Game.fmt(dv / 1000.0, 2), Game.fmt(dv_req / 1000.0, 1)] if dv_req > 0.0 else "%s km/s" % Game.fmt(dv / 1000.0, 2))
	var cost := float(analysis.get("cost", 0.0))
	var budget := float(analysis.get("budget", 0.0))
	_cost_meter.set_values(cost, budget, "US$ %s / %s M" % [Game.fmt(cost / 1e6, 2), Game.fmt_int(int(budget / 1e6))] if budget > 0.0 else "US$ %s M" % Game.fmt(cost / 1e6, 2))

	# Etapas y tabla de números: plegadas en "Detalles" (a la vista quedan los recursos y los avisos)
	var det := Button.new()
	det.text = ("▾ " if _details_open else "▸ ") + tr("WS_DETAILS")
	det.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	det.flat = true
	det.alignment = HORIZONTAL_ALIGNMENT_LEFT
	det.add_theme_font_size_override("font_size", 15)
	det.pressed.connect(func() -> void:
		_details_open = not _details_open
		_update_stats())
	_stats.add_child(det)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 6)
	details.visible = _details_open
	_stats.add_child(details)
	for st in analysis.get("stages", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var stage_name := _label(tr("ST_STAGE") % int(st.number), "Body")
		stage_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		stage_name.add_theme_font_override("font", Game.font_mono_medium)
		stage_name.custom_minimum_size.x = 86
		stage_name.mouse_filter = Control.MOUSE_FILTER_STOP
		stage_name.tooltip_text = Codex.tip("staging")
		row.add_child(stage_name)
		var vals := _label("Δv %s · TWR %s · %s" % [Game.fmt(float(st.dv) / 1000.0, 2), Game.fmt(float(st.twr), 2), _mass(float(st.m0))], "Body")
		vals.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		vals.add_theme_font_size_override("font_size", 14)
		vals.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vals.clip_text = true
		vals.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(vals)
		details.add_child(row)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 2)
	var stab := float(analysis.get("stability", 0.0))
	for pair in [["ST_HEIGHT", "%s m" % Game.fmt(float(analysis.get("height", 0.0)))],
			["ST_MASS", _mass(float(analysis.get("mass", 0.0)))],
			["ST_TWR", Game.fmt(float(analysis.get("twr", 0.0)), 2)],
			["ST_STABILITY", "%s cal" % Game.fmt(stab, 2) if stab > -50.0 else "—"],
			["ST_CD", Game.fmt(float(analysis.get("cd", 0.0)), 2)],
			["ST_COST_ROCKET", "US$ %s M" % Game.fmt(float(analysis.get("cost_rocket", 0.0)) / 1e6, 1)],
			["ST_COST_SHIP", "US$ %s M · %d kg" % [Game.fmt(float(analysis.get("cost_payload", 0.0)) / 1e6, 1), int(analysis.get("payload_mass", 0.0))]]]:
		var cap := _label(pair[0], "Eyebrow")
		cap.mouse_filter = Control.MOUSE_FILTER_STOP
		cap.tooltip_text = Codex.tip({"ST_TWR": "twr", "ST_STABILITY": "stability", "ST_MASS": "rocket_eq", "ST_HEIGHT": "cm"}.get(pair[0], ""))
		grid.add_child(cap)
		var v := _label(pair[1], "Body")
		v.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		grid.add_child(v)
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	details.add_child(gap)
	details.add_child(grid)

	var warns: Array = analysis.get("warnings", [])
	if not warns.is_empty():
		var gap2 := Control.new()
		gap2.custom_minimum_size.y = 6
		_stats.add_child(gap2)
		_stats.add_child(_label("ST_NOTES", "Eyebrow"))
	for w in warns:
		var l := _label(_warning_text(w), "Body")
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", {"bad": Game.MARK, "warn": Game.INK, "ok": Game.GOOD}[w.level])
		_stats.add_child(l)

	var ok := RocketAnalysis.ready_to_fly(analysis)
	_launch.disabled = not ok or (_tutorial_locked() and not _tut_step.get("launch", false))


func _warning_text(w: Dictionary) -> String:
	var args := []
	for a in w.args:
		if a is float:
			args.append(Game.fmt(a, 2))
		else:
			args.append(a)
	var prefix: String = {"bad": "✕ ", "warn": "! ", "ok": "✓ "}[w.level]
	var txt := tr(w.key)
	if not args.is_empty():
		txt = txt % args
	return prefix + txt


func _mass(kg: float) -> String:
	return "%s t" % Game.fmt(kg / 1000.0, 2) if kg >= 1000.0 else "%s kg" % Game.fmt_int(int(kg))


# ---------- Lanzamiento (provisional: el simulador de vuelo es el siguiente paso) ----------

func _on_launch() -> void:
	if not RocketAnalysis.ready_to_fly(analysis):
		return
	_launched = true
	if tutorial != null and is_instance_valid(tutorial):
		Game.progress["tutorial_done"] = true
		Game.save_progress()
	Game.flight = {"design": design.duplicate(true), "analysis": analysis, "level": mission, "sandbox": sandbox}
	if "--smoke" in OS.get_cmdline_user_args():
		return # la prueba automática no cambia de escena aquí
	Game.goto("flight")


func _build_result() -> Control:
	var veil := ColorRect.new()
	veil.color = Color(Game.PAPER_DEEP, 0.85)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.add_child(center)
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = "Sheet"
	sheet.custom_minimum_size.x = 620
	center.add_child(sheet)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	sheet.add_child(v)
	var t := _label("WS_RESULT_TITLE", "Title")
	t.add_theme_font_size_override("font_size", 48)
	v.add_child(t)
	var b := _label("", "Body")
	b.name = "Body"
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(b)
	var note := _label("WS_RESULT_NOTE", "Hint")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Game.MARK)
	v.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	var keep := Button.new()
	keep.text = "WS_KEEP_BUILDING"
	keep.custom_minimum_size = Vector2(0, 40)
	keep.pressed.connect(func() -> void: _result.visible = false)
	row.add_child(keep)
	var go := Button.new()
	go.text = "WS_TO_MISSIONS"
	go.theme_type_variation = "Primary"
	go.pressed.connect(func() -> void:
		Game.selected_level = mini(level + 1, Game.levels.size() - 1)
		_back())
	row.add_child(go)
	v.add_child(row)
	return veil


func _label(text: String, variation: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l
