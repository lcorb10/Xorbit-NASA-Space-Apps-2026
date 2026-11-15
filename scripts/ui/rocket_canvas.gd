class_name RocketCanvas
extends Control
## Plano del cohete del jugador: piezas, etapas, cotas, CM y CP en vivo.
## Clic en una pieza para seleccionarla.

signal part_selected(index: int)
signal drop_new(id: String, at: int)
signal drop_move(from: int, to: int)

var design: Array = []
var analysis: Dictionary = {}
var selected := -1:
	set(v):
		selected = v
		queue_redraw()

var _hover := -1
var _s := 1.0
var _origin := Vector2.ZERO
var _half_w := 1.0
var _drop_at := -1 # dónde caería la pieza que se arrastra (índice de inserción)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	mouse_exited.connect(func() -> void:
		_hover = -1
		queue_redraw())


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()
	elif what == NOTIFICATION_DRAG_END:
		_drop_at = -1
		queue_redraw()


func set_data(d: Array, a: Dictionary) -> void:
	design = d
	analysis = a
	queue_redraw()


func _layout() -> void:
	var h := maxf(float(analysis.get("height", 1.0)), 0.5)
	_half_w = 0.3
	var extra := 0.0
	for p in design:
		_half_w = maxf(_half_w, PartDraw.half_width(p))
	if not design.is_empty():
		extra = PartDraw.below(design[-1])
	var avail_h := size.y - 110.0
	var avail_w := size.x - 380.0
	_s = clampf(minf(avail_h / (h + extra), avail_w / (2.0 * _half_w)), 2.0, 400.0)
	_origin = Vector2(size.x * 0.5 + 20.0, 46.0 + maxf(0.0, (avail_h - (h + extra) * _s) * 0.35))


func _index_at(pos: Vector2) -> int:
	for info in analysis.get("parts", []):
		var y0 := _origin.y + float(info.y) * _s
		var y1 := y0 + float(info.length) * _s
		var hw := PartDraw.half_width(design[info.index]) * _s + 8.0
		if pos.y >= y0 and pos.y <= y1 and absf(pos.x - _origin.x) <= hw:
			return info.index
	return -1


## Índice de inserción según la altura del ratón: entre las piezas más cercanas.
func _insert_index(pos: Vector2) -> int:
	var parts: Array = analysis.get("parts", [])
	if parts.is_empty():
		return 0
	for info in parts:
		var mid := _origin.y + (float(info.y) + float(info.length) / 2.0) * _s
		if pos.y < mid:
			return int(info.index)
	return design.size()


func _get_drag_data(at: Vector2) -> Variant:
	var i := _index_at(at)
	if i < 0:
		return null
	var preview := PartThumb.new()
	preview.setup(design[i])
	preview.custom_minimum_size = Vector2(70, 90)
	preview.size = preview.custom_minimum_size
	preview.ink = Game.MARK
	var holder := Control.new()
	holder.add_child(preview)
	preview.position = -preview.size / 2.0
	set_drag_preview(holder)
	return {"type": "move", "index": i}


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.get("type") in ["new_part", "move"]):
		return false
	var k := _insert_index(at)
	if k != _drop_at:
		_drop_at = k
		queue_redraw()
	return true


func _drop_data(at: Vector2, data: Variant) -> void:
	var k := _insert_index(at)
	_drop_at = -1
	if data.type == "new_part":
		drop_new.emit(data.id, k)
	else:
		drop_move.emit(int(data.index), k)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var i := _index_at(event.position)
		if i != _hover:
			_hover = i
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		part_selected.emit(_index_at(event.position))
		accept_event()


func _draw() -> void:
	var f := Game.font_mono
	var fm := Game.font_mono_medium
	if design.is_empty() or analysis.get("parts", []).is_empty():
		var msg := tr("W_EMPTY")
		var w := minf(size.x - 80.0, 520.0)
		draw_multiline_string(fm, Vector2((size.x - w) / 2.0, size.y / 2.0), msg, HORIZONTAL_ALIGNMENT_CENTER, w, 16, -1, Game.INK_DIM)
		if _drop_at >= 0:
			draw_rect(Rect2(Vector2(20, 20), size - Vector2(40, 40)), Game.MARK, false, 2.0)
		return
	_layout()
	var s := _s
	var o := _origin
	var height := float(analysis.height)

	# Eje de simetría
	draw_dashed_line(o + Vector2(0, -16), o + Vector2(0, height * s + 24), Color(Game.INK_DIM, 0.35), 1.0, 14.0)

	# Piezas
	for info in analysis.parts:
		var i: int = info.index
		var ink := Game.MARK if i == selected else Game.INK
		var fill := Color(Game.PAPER_DEEP, 0.92)
		if i == _hover and i != selected:
			fill = Color(Game.INK, 0.08)
		elif i == selected:
			fill = Color(Game.MARK, 0.1)
		PartDraw.draw_part(self, design[i], Vector2(o.x, o.y + float(info.y) * s), s, ink, fill)

	# Línea de inserción mientras se arrastra una pieza
	if _drop_at >= 0:
		var yy := o.y + height * s
		if _drop_at < analysis.parts.size():
			yy = o.y + float(analysis.parts[_drop_at].y) * s
		var hw := _half_w * s + 30.0
		draw_line(Vector2(o.x - hw, yy), Vector2(o.x + hw, yy), Game.MARK, 3.0)
		draw_circle(Vector2(o.x - hw, yy), 5.0, Game.MARK)
		draw_circle(Vector2(o.x + hw, yy), 5.0, Game.MARK)

	# Etapas a la izquierda
	var bx := o.x - _half_w * s - 56.0
	for st in analysis.get("stages", []):
		var top_info: Dictionary = analysis.parts[int(st.top)]
		var bot_info: Dictionary = analysis.parts[int(st.bottom)]
		var y0 := o.y + float(top_info.y) * s + 2.0
		var y1 := o.y + (float(bot_info.y) + float(bot_info.length)) * s - 2.0
		draw_line(Vector2(bx, y0), Vector2(bx, y1), Game.INK_DIM, 1.0)
		draw_line(Vector2(bx, y0), Vector2(bx + 8, y0), Game.INK_DIM, 1.0)
		draw_line(Vector2(bx, y1), Vector2(bx + 8, y1), Game.INK_DIM, 1.0)
		var label := tr("ST_STAGE") % int(st.number)
		var dv := "Δv %s km/s" % Game.fmt(float(st.dv) / 1000.0, 2)
		var ym := (y0 + y1) / 2.0
		var lw := fm.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var dw := f.get_string_size(dv, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(fm, Vector2(bx - 10 - lw, ym - 2), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Game.INK)
		draw_string(f, Vector2(bx - 10 - dw, ym + 14), dv, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Game.INK_DIM)

	# CM y CP sobre el eje
	var r := 8.0
	var cm := Vector2(o.x, o.y + float(analysis.cm) * s)
	draw_circle(cm, r, Game.PAPER)
	draw_arc(cm, r, 0, TAU, 28, Game.INK, 1.5, true)
	_quadrant(cm, r, -PI / 2.0, Game.INK)
	_quadrant(cm, r, PI / 2.0, Game.INK)
	var stab := float(analysis.stability)
	if stab > -50.0:
		var cp := Vector2(o.x, o.y + float(analysis.cp) * s)
		draw_circle(cp, r, Game.PAPER)
		draw_arc(cp, r, 0, TAU, 28, Game.MARK, 1.5, true)
		draw_line(cp + Vector2(-r, 0), cp + Vector2(r, 0), Game.MARK, 1.5)
		draw_line(cp + Vector2(0, -r), cp + Vector2(0, r), Game.MARK, 1.5)
		# Rótulos a la derecha con línea guía
		var rx := o.x + _half_w * s + 26.0
		_tag(cm, Vector2(rx, cm.y), "CM", Game.INK)
		_tag(cp, Vector2(rx, cp.y + (14.0 if absf(cp.y - cm.y) < 16.0 else 0.0)), "CP", Game.MARK)
		var sx := rx + 46.0
		draw_line(Vector2(sx, cm.y), Vector2(sx, cp.y), Color(Game.MARK, 0.8), 1.0)
		draw_string(f, Vector2(sx + 6, (cm.y + cp.y) / 2.0 + 4), "%s cal" % Game.fmt(stab, 2), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Game.MARK)
	else:
		_tag(cm, Vector2(o.x + _half_w * s + 26.0, cm.y), "CM", Game.INK)

	# Cota de altura total
	var dx := o.x + _half_w * s + 150.0
	var top := Vector2(dx, o.y)
	var bot := Vector2(dx, o.y + height * s)
	draw_line(Vector2(o.x + 6, o.y), Vector2(dx + 6, o.y), Color(Game.INK_DIM, 0.5), 1.0)
	draw_line(Vector2(o.x + float(analysis.parts[-1].diameter) / 2.0 * s, bot.y), Vector2(dx + 6, bot.y), Color(Game.INK_DIM, 0.5), 1.0)
	draw_line(top, bot, Game.INK_DIM, 1.0)
	_arrow(top, Vector2.UP)
	_arrow(bot, Vector2.DOWN)
	var hl := "%s m" % Game.fmt(height)
	draw_set_transform(Vector2(dx - 6, (top.y + bot.y) / 2.0 + fm.get_string_size(hl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x / 2.0), -PI / 2.0)
	draw_string(fm, Vector2.ZERO, hl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Game.INK)
	draw_set_transform(Vector2.ZERO)

	# Barra de escala abajo a la izquierda
	var nice := [0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0]
	var meters := 1.0
	for m in nice:
		if m * s <= 140.0:
			meters = m
	var sb := Vector2(16, size.y - 22)
	draw_line(sb, sb + Vector2(meters * s, 0), Game.INK_DIM, 2.0)
	draw_line(sb + Vector2(0, -5), sb + Vector2(0, 5), Game.INK_DIM, 1.0)
	draw_line(sb + Vector2(meters * s, -5), sb + Vector2(meters * s, 5), Game.INK_DIM, 1.0)
	draw_string(f, sb + Vector2(meters * s + 8, 4), "%s m" % Game.fmt(meters), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Game.INK_DIM)


func _tag(from: Vector2, to: Vector2, text: String, c: Color) -> void:
	draw_line(from + Vector2(9, 0), to, Color(c, 0.6), 1.0)
	draw_string(Game.font_mono_medium, to + Vector2(4, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c)


func _arrow(tip: Vector2, dir: Vector2) -> void:
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * 8.0 + side * 3.0, tip - dir * 8.0 - side * 3.0]), Game.INK_DIM)


func _quadrant(c: Vector2, r: float, start: float, color: Color) -> void:
	var pts := PackedVector2Array([c])
	for i in 9:
		var a := start + (PI / 2.0) * i / 8.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, color)
