class_name PartDesigner
extends ColorRect
## Torno: el jugador dibuja la silueta de una pieza (mitad derecha de su perfil) y
## elige tipo, medidas y material. La pieza se guarda como perfil, igual que las
## prefabricadas y las importadas, así que la física y el 3D la tratan igual.
## Arrastrar un punto = moverlo · doble clic = agregar punto · clic derecho = quitar.

signal saved(id: String)
signal closed

const KINDS := ["nose", "payload", "tank", "solid", "engine"]
const PRESETS := {
	"cone": [[0.0, 0.0], [1.0, 1.0]],
	"ogive": [[0.0, 0.0], [0.45, 0.15], [0.72, 0.35], [0.9, 0.6], [1.0, 1.0]],
	"cylinder": [[1.0, 0.0], [1.0, 1.0]],
	"capsule": [[0.0, 0.0], [0.6, 0.06], [0.85, 0.15], [1.0, 0.3], [1.0, 0.7], [0.85, 0.85], [0.6, 0.94], [0.0, 1.0]],
	"bell": [[0.35, 0.0], [0.4, 0.3], [0.6, 0.6], [1.0, 1.0]],
}

var editing_id := "" # vacío = pieza nueva
var points: Array = [] # [[r, y], ...] normalizados, y de 0 (arriba) a 1 (abajo)
var kind := "tank"
var length := 3.0
var diameter := 1.2
var mat_id := "aluminium"
var propellant := "lox_rp1"
var part_name := ""
var level := 0
var sandbox := false

var _canvas: Control
var _stats: Label
var _name_edit: LineEdit
var _drag := -1
var _preview: PartPreview3D


func _ready() -> void:
	color = Color(Game.PAPER_DEEP, 0.94)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if points.is_empty():
		points = (PRESETS.ogive as Array).duplicate(true)
		kind = "nose"
		length = 2.0
		diameter = 1.2
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 50)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	var title := Label.new()
	title.text = "PD_TITLE"
	title.theme_type_variation = "Title"
	title.add_theme_font_size_override("font_size", 48)
	col.add_child(title)
	var hint := Label.new()
	hint.text = "PD_HINT"
	hint.theme_type_variation = "Hint"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	col.add_child(body)

	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_canvas)
	_canvas.gui_input.connect(_canvas_input)
	_canvas.clip_contents = true
	body.add_child(_canvas)
	# Vista 3D de la pieza, al lado del dibujo (gira sola; arrastrar para mirarla)
	var view := VBoxContainer.new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.add_theme_constant_override("separation", 6)
	body.add_child(view)
	view.add_child(_cap("PD_VIEW_3D"))
	_preview = PartPreview3D.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(280, 0)
	view.add_child(_preview)

	var side := PanelContainer.new()
	side.theme_type_variation = "Sheet"
	side.custom_minimum_size.x = 440
	body.add_child(side)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	side.add_child(v)
	v.add_child(_cap("PD_NAME"))
	_name_edit = LineEdit.new()
	_name_edit.text = part_name if part_name != "" else tr("PD_DEFAULT_NAME")
	_name_edit.max_length = 28
	_name_edit.custom_minimum_size.y = 38
	v.add_child(_name_edit)
	v.add_child(_cap("PD_START_FROM"))
	var presets := HFlowContainer.new()
	presets.add_theme_constant_override("h_separation", 6)
	presets.add_theme_constant_override("v_separation", 6)
	for key in PRESETS:
		var b := Button.new()
		b.text = "PD_PRESET_" + key
		b.custom_minimum_size.y = 34
		var k: String = key
		b.pressed.connect(func() -> void:
			points = (PRESETS[k] as Array).duplicate(true)
			_refresh())
		presets.add_child(b)
	v.add_child(presets)
	v.add_child(_cap("PD_KIND"))
	var ko := OptionButton.new()
	ko.custom_minimum_size.y = 36
	for i in KINDS.size():
		ko.add_item(tr("PD_KIND_" + KINDS[i]), i)
		if KINDS[i] == kind:
			ko.select(i)
	ko.item_selected.connect(func(i: int) -> void:
		kind = KINDS[i]
		_refresh())
	v.add_child(ko)
	_slider(v, "ED_LENGTH", length, 0.2, 40.0, func(x: float) -> void: length = x)
	_slider(v, "ED_DIAMETER", diameter, 0.2, 10.0, func(x: float) -> void: diameter = x)
	v.add_child(_cap("ED_MATERIAL"))
	var mo := OptionButton.new()
	mo.custom_minimum_size.y = 36
	var mats := Catalog.unlocked(Catalog.materials, level, sandbox)
	for i in mats.size():
		mo.add_item(tr("MAT_" + mats[i]), i)
		if mats[i] == mat_id:
			mo.select(i)
	mo.item_selected.connect(func(i: int) -> void:
		mat_id = mats[i]
		_refresh())
	v.add_child(mo)
	_stats = Label.new()
	_stats.theme_type_variation = "Body"
	_stats.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats.add_theme_font_size_override("font_size", 14)
	v.add_child(_stats)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	if editing_id != "":
		var del := Button.new()
		del.text = "PD_DELETE"
		del.add_theme_color_override("font_color", Game.MARK)
		del.custom_minimum_size.y = 40
		del.pressed.connect(_delete)
		row.add_child(del)
	var cancel := Button.new()
	cancel.text = "PD_CANCEL"
	cancel.custom_minimum_size.y = 40
	cancel.pressed.connect(func() -> void:
		closed.emit()
		queue_free())
	row.add_child(cancel)
	var save := Button.new()
	save.text = "PD_SAVE"
	save.theme_type_variation = "Primary"
	save.pressed.connect(_save)
	row.add_child(save)
	v.add_child(row)
	_refresh()


func _cap(key: String) -> Label:
	var l := Label.new()
	l.text = key
	l.theme_type_variation = "Eyebrow"
	return l


func _slider(parent: Control, key: String, value: float, lo: float, hi: float, on_change: Callable) -> void:
	parent.add_child(_cap(key))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var lab := Label.new()
	lab.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	lab.custom_minimum_size.x = 80
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lab.text = "%s m" % Game.fmt(value, 2)
	s.value_changed.connect(func(x: float) -> void:
		lab.text = "%s m" % Game.fmt(x, 2)
		on_change.call(x)
		_refresh())
	h.add_child(s)
	h.add_child(lab)
	parent.add_child(h)


# ---------- Lienzo del torno ----------

func _frame() -> Dictionary:
	var area := Rect2(Vector2(60, 30), _canvas.size - Vector2(120, 70))
	var s := minf(area.size.y / length, area.size.x / diameter)
	var top := Vector2(area.position.x + area.size.x / 2.0, area.position.y + (area.size.y - length * s) / 2.0)
	return {"s": s, "top": top}


func _to_px(p: Array) -> Vector2:
	var f := _frame()
	return f.top + Vector2(float(p[0]) * diameter / 2.0 * f.s, float(p[1]) * length * f.s)


func _draw_canvas() -> void:
	var c := _canvas
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Game.PAPER)
	var step := 24.0
	var x := 0.0
	while x < c.size.x:
		c.draw_line(Vector2(x, 0), Vector2(x, c.size.y), Game.GRID, 1.0)
		x += step
	var y := 0.0
	while y < c.size.y:
		c.draw_line(Vector2(0, y), Vector2(c.size.x, y), Game.GRID, 1.0)
		y += step
	var f := _frame()
	var top: Vector2 = f.top
	# Eje de giro
	c.draw_dashed_line(top - Vector2(0, 20), top + Vector2(0, length * f.s + 20), Color(Game.INK_DIM, 0.6), 1.0, 12.0)
	# Pieza completa (los dos lados) rellena
	var right := PackedVector2Array()
	var left := PackedVector2Array()
	for p in points:
		var px := _to_px(p)
		right.append(px)
		left.append(Vector2(2.0 * top.x - px.x, px.y))
	left.reverse()
	var outline := PackedVector2Array(right)
	outline.append_array(left)
	if not Geometry2D.triangulate_polygon(outline).is_empty():
		c.draw_colored_polygon(outline, Color(Game.INK, 0.06))
	var closed := outline.duplicate()
	closed.append(outline[0])
	c.draw_polyline(closed, Color(Game.INK_DIM, 0.7), 1.5, true)
	# Lado editable en lápiz rojo con sus puntos
	c.draw_polyline(right, Game.MARK, 2.5, true)
	for i in points.size():
		var px := _to_px(points[i])
		c.draw_circle(px, 7.0 if i == _drag else 5.5, Game.MARK)
		c.draw_circle(px, 3.0, Game.PAPER)
	# Cotas
	var fm := Game.font_mono
	c.draw_string(fm, Vector2(top.x + diameter / 2.0 * f.s + 16, top.y + length * f.s / 2.0), "%s m" % Game.fmt(length, 2), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Game.INK_DIM)
	c.draw_string(fm, Vector2(top.x - 30, top.y + length * f.s + 22), "Ø %s m" % Game.fmt(diameter, 2), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Game.INK_DIM)


func _canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.double_click:
				_insert_at(mb.position)
			elif mb.pressed:
				_drag = _point_at(mb.position)
			else:
				_drag = -1
			_canvas.queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var i := _point_at(mb.position)
			if i > 0 and i < points.size() - 1:
				points.remove_at(i)
				_refresh()
	elif event is InputEventMouseMotion and _drag >= 0:
		var f := _frame()
		var top: Vector2 = f.top
		var mp := (event as InputEventMouseMotion).position
		var r := clampf((mp.x - top.x) / (diameter / 2.0 * f.s), 0.0, 1.0)
		var yn := clampf((mp.y - top.y) / (length * f.s), 0.0, 1.0)
		if _drag == 0:
			yn = 0.0
		elif _drag == points.size() - 1:
			yn = 1.0
		else:
			yn = clampf(yn, float(points[_drag - 1][1]) + 0.01, float(points[_drag + 1][1]) - 0.01)
		points[_drag] = [snappedf(r, 0.01), snappedf(yn, 0.005)]
		_refresh()


func _point_at(pos: Vector2) -> int:
	for i in points.size():
		if _to_px(points[i]).distance_to(pos) < 12.0:
			return i
	return -1


func _insert_at(pos: Vector2) -> void:
	var f := _frame()
	var top: Vector2 = f.top
	var yn := clampf((pos.y - top.y) / (length * f.s), 0.01, 0.99)
	var r := clampf((pos.x - top.x) / (diameter / 2.0 * f.s), 0.0, 1.0)
	for i in range(1, points.size()):
		if float(points[i][1]) > yn:
			points.insert(i, [snappedf(r, 0.01), snappedf(yn, 0.005)])
			break
	_refresh()


func _refresh() -> void:
	_canvas.queue_redraw()
	# Vista previa de la física con la misma integración que el resto del juego
	var prof := PackedVector2Array()
	for p in points:
		prof.append(Vector2(float(p[0]) * diameter / 2.0, float(p[1]) * length))
	var g := RocketAnalysis.integrate(prof)
	var look := {"material": mat_id, "propellant": propellant, "engine": "rutherford"}
	_preview.show_part(prof, kind, look, length, diameter)
	var mat: Dictionary = Catalog.materials.get(mat_id, Catalog.materials["aluminium"])
	var wall := float(Catalog.WALL_BY_KIND.get(kind, 0.004)) / float(mat.strength)
	var shell := float(g.area) * wall * float(mat.density_kg_m3)
	var txt := "%s %s m³\n%s %s m²\n%s %s kg" % [tr("PD_VOLUME"), Game.fmt(float(g.volume), 2), tr("PD_AREA"), Game.fmt(float(g.area), 1), tr("PD_SHELL"), Game.fmt_int(int(shell))]
	if kind == "tank":
		var pr: Dictionary = Catalog.propellants.get(propellant, {})
		txt += "\n%s %s kg (%s)" % [tr("PD_PROP"), Game.fmt_int(int(float(g.volume) * RocketAnalysis.TANK_FILL * float(pr.get("bulk_density_kg_m3", 1000.0)))), pr.get("label", "")]
	elif kind == "solid":
		txt += "\n%s %s kg (APCP)" % [tr("PD_PROP"), Game.fmt_int(int(float(g.volume) * RocketAnalysis.SOLID_FILL * 1750.0))]
	_stats.text = txt


func _save() -> void:
	var id := editing_id if editing_id != "" else "c_%d" % Time.get_unix_time_from_system()
	var defaults := {"length": snappedf(length, 0.05), "diameter": snappedf(diameter, 0.05), "material": mat_id}
	match kind:
		"tank":
			defaults["propellant"] = propellant
		"solid":
			defaults["engine"] = "solid_basic"
		"engine":
			defaults["engine"] = "rutherford"
			defaults["count"] = 1
		"payload":
			defaults["payload_kg"] = 50
	var prof := []
	for p in points:
		prof.append([float(p[0]), float(p[1])])
	Catalog.save_custom({"id": id, "name": _name_edit.text.strip_edges(), "kind": kind, "profile": prof, "defaults": defaults})
	saved.emit(id)
	queue_free()


func _delete() -> void:
	Catalog.delete_custom(editing_id)
	saved.emit("")
	queue_free()
