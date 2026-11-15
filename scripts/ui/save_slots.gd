extends Control
## Partidas guardadas: tres ranuras. En cada una se puede seguir jugando, empezar de cero,
## cambiar el nombre, repetir los tutoriales o borrarla. Todo lo que borra pide confirmación
## en un cuadro propio (no hay diálogos del sistema).

var _cards: HBoxContainer
var _veil: Control
var _dlg_title: Label
var _dlg_body: Label
var _dlg_input: LineEdit
var _dlg_ok: Button
var _dlg_action := Callable()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())
	var dim := ColorRect.new() # pantalla de gestión: el fondo 3D queda de ambiente
	dim.color = Color(0.02, 0.05, 0.09, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child.call_deferred(dim)
	move_child.call_deferred(dim, 1)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 72)
	margin.add_theme_constant_override("margin_top", 56)
	margin.add_theme_constant_override("margin_bottom", 48)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	col.add_child(_label("SV_EYEBROW", "Eyebrow"))
	var t := _label("SV_TITLE", "Title")
	t.add_theme_font_size_override("font_size", 72)
	col.add_child(t)
	var lead := _label("SV_LEAD", "Lead")
	lead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(lead)
	var gap := Control.new()
	gap.custom_minimum_size.y = 12
	col.add_child(gap)

	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 20)
	_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_cards)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	var note := _label("SV_NOTE", "Hint")
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(note)
	var back := Button.new()
	back.text = "UI_BACK"
	back.custom_minimum_size = Vector2(140, 40)
	back.pressed.connect(func() -> void: Game.goto("menu"))
	foot.add_child(back)
	col.add_child(foot)

	_veil = _build_dialog()
	add_child(_veil)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _veil.visible:
			_close_dialog()
		else:
			Game.goto("menu")
		get_viewport().set_input_as_handled()


# ---------- Tarjetas ----------

func _refresh() -> void:
	for c in _cards.get_children():
		c.queue_free()
	var focus: Button = null
	for n in range(1, Game.SLOTS + 1):
		var b := _card(n)
		if focus == null or (n == Game.slot and b != null):
			focus = b
	if focus:
		focus.grab_focus.call_deferred()


func _slot_name(n: int, info: Dictionary) -> String:
	var nm := str(info.get("name", ""))
	return nm if nm != "" else tr("SV_SLOT") % n


func _card(n: int) -> Button:
	var info := Game.slot_info(n)
	var active := n == Game.slot and not info.is_empty()
	var sheet := PanelContainer.new()
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var border := Game.MARK if active else Color(Game.LINE, 0.8)
	var box := Game._box(Color(0.03, 0.07, 0.12, 0.84), 2 if active else 1, border, Vector4(24, 20, 24, 22))
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 12
	sheet.add_theme_stylebox_override("panel", box)
	_cards.add_child(sheet)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	sheet.add_child(v)

	var head := HBoxContainer.new()
	var num := _label((tr("SV_SLOT") % n).to_upper(), "Eyebrow")
	num.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	num.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(num)
	if active:
		var tag := _label("SV_ACTIVE", "Eyebrow")
		tag.add_theme_color_override("font_color", Game.MARK)
		head.add_child(tag)
	v.add_child(head)

	if info.is_empty():
		var empty := _label("SV_EMPTY", "Title")
		empty.add_theme_font_size_override("font_size", 40)
		empty.add_theme_color_override("font_color", Game.INK_DIM)
		v.add_child(empty)
		var d := _label("SV_EMPTY_DESC", "Body")
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
		v.add_child(_spacer(6))
		v.add_child(_label("SV_NAME", "Eyebrow"))
		var input := LineEdit.new()
		input.placeholder_text = tr("SV_SLOT") % n
		input.max_length = 24
		input.custom_minimum_size.y = 40
		v.add_child(input)
		v.add_child(_spacer(4))
		var start := _button("SV_NEW", "Primary", func() -> void: _start_new(n, input.text))
		input.text_submitted.connect(func(_t: String) -> void: _start_new(n, input.text))
		v.add_child(start)
		return start

	var title := _label(_slot_name(n, info), "Title")
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.add_theme_font_size_override("font_size", 40)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	v.add_child(title)

	var unlocked := int(info.unlocked)
	var total := Game.levels.size()
	var next := _label(tr("SV_MISSION") % [unlocked, tr("LEVEL_%d_NAME" % unlocked)], "Body")
	next.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(next)
	var bar := ProgressBar.new()
	bar.max_value = total * 3
	bar.value = int(info.stars)
	bar.show_percentage = false
	bar.custom_minimum_size.y = 8
	bar.add_theme_stylebox_override("background", Game._box(Color(Game.LINE, 0.5), 0, Game.LINE, Vector4.ZERO))
	bar.add_theme_stylebox_override("fill", Game._box(Game.MARK, 0, Game.MARK, Vector4.ZERO))
	v.add_child(bar)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	_stat(grid, "SV_STARS", "★ %d / %d" % [int(info.stars), total * 3])
	_stat(grid, "SV_PLAYED", Game.play_time_text(float(info.play_s)))
	_stat(grid, "SV_LAST", Game.date_text(int(info.updated)))
	_stat(grid, "SV_TUTORIAL", tr("SV_YES") if bool(info.tutorial_done) else tr("SV_NO"))
	v.add_child(grid)
	v.add_child(_spacer(6))

	var cont := _button("SV_CONTINUE", "Primary", func() -> void:
		Game.load_slot(n)
		Game.sandbox = false
		Game.goto("levels"))
	v.add_child(cont)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_button("SV_RENAME", "", func() -> void:
		_open_dialog("SV_RENAME", "SV_RENAME_DESC", "SV_SAVE", false, _slot_name(n, info), func(text: String) -> void:
			Game.rename_slot(n, text)
			_refresh())))
	row.add_child(_button("SV_REPLAY", "", func() -> void:
		_open_dialog("SV_REPLAY", "SV_REPLAY_DESC", "SV_REPLAY_OK", false, null, func(_t: String) -> void:
			Game.replay_tutorials(n)
			_refresh())))
	for b in row.get_children():
		(b as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	var nm := _slot_name(n, info)
	row2.add_child(_button("SV_RESTART", "", func() -> void:
		_open_dialog("SV_RESTART", tr("SV_RESTART_DESC") % nm, "SV_RESTART_OK", true, null, func(_t: String) -> void:
			Game.new_game(n, str(info.get("name", "")))
			_refresh())))
	var del := _button("SV_DELETE", "", func() -> void:
		_open_dialog("SV_DELETE", tr("SV_DELETE_DESC") % nm, "SV_DELETE_OK", true, null, func(_t: String) -> void:
			Game.delete_slot(n)
			_refresh()))
	del.add_theme_color_override("font_color", Game.MARK)
	row2.add_child(del)
	for b in row2.get_children():
		(b as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(row2)
	return cont


func _start_new(n: int, text: String) -> void:
	Game.new_game(n, text)
	Game.sandbox = false
	Game.selected_level = 0
	Game.goto("levels")


func _stat(grid: GridContainer, key: String, value: String) -> void:
	grid.add_child(_label(key, "Eyebrow"))
	var l := _label(value, "Body")
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_override("font", Game.font_mono_medium)
	grid.add_child(l)


# ---------- Cuadro de confirmación ----------

func _build_dialog() -> Control:
	var veil := ColorRect.new()
	veil.color = Color(Game.PAPER_DEEP, 0.8)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.add_child(center)
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = "Sheet"
	sheet.custom_minimum_size.x = 560
	center.add_child(sheet)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	sheet.add_child(v)
	_dlg_title = _label("", "Title")
	_dlg_title.add_theme_font_size_override("font_size", 44)
	v.add_child(_dlg_title)
	_dlg_body = _label("", "Body")
	_dlg_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_dlg_body)
	_dlg_input = LineEdit.new()
	_dlg_input.max_length = 24
	_dlg_input.custom_minimum_size.y = 40
	_dlg_input.text_submitted.connect(func(_t: String) -> void: _confirm())
	v.add_child(_dlg_input)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	var cancel := _button("SV_CANCEL", "", _close_dialog)
	cancel.name = "Cancel"
	row.add_child(cancel)
	_dlg_ok = _button("", "Primary", _confirm)
	row.add_child(_dlg_ok)
	v.add_child(row)
	return veil


func _open_dialog(title_key: String, body: String, ok_key: String, danger: bool, input: Variant, action: Callable) -> void:
	_dlg_title.text = title_key
	_dlg_body.text = body
	_dlg_ok.text = ok_key
	_dlg_input.visible = input != null
	if input != null:
		_dlg_input.text = str(input)
	_dlg_ok.theme_type_variation = &"Danger" if danger else &"Primary"
	_dlg_action = action
	_veil.visible = true
	if input != null:
		_dlg_input.grab_focus.call_deferred()
		_dlg_input.select_all.call_deferred()
	else:
		# Lo que borra empieza con el foco en Cancelar, para no confirmar con Enter sin querer
		_veil.find_child("Cancel", true, false).grab_focus.call_deferred()


func _confirm() -> void:
	var text := _dlg_input.text
	var act := _dlg_action
	_close_dialog()
	if act.is_valid():
		act.call(text)


func _close_dialog() -> void:
	_veil.visible = false
	_dlg_action = Callable()


# ---------- Piezas ----------

func _label(text: String, variation: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l


func _button(key: String, variation: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = key
	if variation != "":
		b.theme_type_variation = variation
	b.custom_minimum_size.y = 40
	b.pressed.connect(action)
	return b


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c
