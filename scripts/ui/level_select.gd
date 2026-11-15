extends Control
## Selección de misión: 10 tarjetas a la izquierda y la ficha de la misión
## elegida a la derecha.

var _cards: Array[LevelCard] = []
var _current := 0
var _eyebrow: Label
var _name: Label
var _desc: Label
var _dv: Label
var _budget: Label
var _unlocks: Label
var _start: Button
var _ladder: DvLadder


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new()) # misma plataforma 3D que el menú, atenuada para leer
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.09, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child.call_deferred(dim)
	move_child.call_deferred(dim, 1)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 72)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 60)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 24)
	margin.add_child(col)

	# Encabezado
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	var back := Button.new()
	back.text = "UI_BACK"
	back.custom_minimum_size = Vector2(120, 40)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void: Game.goto("menu"))
	head.add_child(back)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	var t := _label("LEVELS_TITLE", "Title")
	t.add_theme_font_size_override("font_size", 60)
	titles.add_child(t)
	titles.add_child(_label("LEVELS_SUB", "Hint"))
	head.add_child(titles)
	col.add_child(head)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 28)
	col.add_child(body)

	# Tarjetas
	var grid_col := VBoxContainer.new()
	grid_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_col.size_flags_stretch_ratio = 2.0
	grid_col.add_theme_constant_override("separation", 12)
	body.add_child(grid_col)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid_col.add_child(grid)
	for l in Game.levels:
		var card := LevelCard.new()
		card.setup(l)
		var i := int(l.id)
		card.pressed.connect(func() -> void: _on_card(i))
		# Con teclado/mando, enfocar = seleccionar. Con ratón decide el clic (_on_card).
		card.focus_entered.connect(func() -> void:
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_select(i))
		grid.add_child(card)
		_cards.append(card)
	var ladder_gap := Control.new()
	ladder_gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_col.add_child(ladder_gap)
	_ladder = DvLadder.new()
	grid_col.add_child(_ladder)
	grid_col.add_child(_label("LEVELS_DV_NOTE", "Hint"))

	# Ficha de la misión
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = "Sheet"
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.custom_minimum_size.x = 400
	sheet.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(sheet)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 12)
	sheet.add_child(info)
	_eyebrow = _label("", "Eyebrow")
	_eyebrow.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	info.add_child(_eyebrow)
	_name = _label("", "Title")
	_name.add_theme_font_size_override("font_size", 46)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_name)
	_desc = _label("", "Body")
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size.y = 72
	info.add_child(_desc)

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 32)
	_dv = _stat(stats, "LEVELS_DV")
	_budget = _stat(stats, "LEVELS_BUDGET")
	info.add_child(stats)
	info.add_child(_label("LEVELS_UNLOCKS", "Eyebrow"))
	_unlocks = _label("", "Body")
	_unlocks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_unlocks)
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	info.add_child(gap)
	_start = Button.new()
	_start.text = "LEVELS_START"
	_start.theme_type_variation = "Primary"
	_start.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_start.pressed.connect(_launch)
	info.add_child(_start)

	_current = clampi(Game.selected_level, 0, Game.levels.size() - 1)
	_select(_current)
	_cards[_current].grab_focus.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _name != null:
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Game.goto("menu")
		get_viewport().set_input_as_handled()


func _on_card(i: int) -> void:
	# Primer clic selecciona; segundo clic (o Enter) sobre la misma tarjeta la empieza
	if i == _current and Game.is_unlocked(i):
		_launch()
	else:
		_select(i)


func _select(i: int) -> void:
	_current = i
	for c in _cards:
		c.selected = c.index == i
	if _ladder:
		_ladder.selected = i
	_refresh()


func _refresh() -> void:
	var l := Game.level(_current)
	var unlocked := Game.is_unlocked(_current)
	_eyebrow.text = tr("LEVELS_MISSION") % _current
	_name.text = tr("LEVEL_%d_NAME" % _current)
	_desc.text = tr("LEVEL_%d_DESC" % _current) if unlocked else tr("LEVELS_LOCKED_HINT")
	_dv.text = Game.dv_text(l)
	_budget.text = Game.budget_text(l)
	_unlocks.text = tr("LEVEL_%d_UNLOCKS" % _current)
	_start.disabled = not unlocked


func _launch() -> void:
	if not Game.is_unlocked(_current):
		return
	Game.selected_level = _current
	Game.goto("workshop")


func _stat(parent: Control, caption: String) -> Label:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(_label(caption, "Eyebrow"))
	var val := _label("", "Value")
	val.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(val)
	parent.add_child(v)
	return val


func _label(text: String, variation: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l
