class_name DvLadder
extends Control
## Regla de Δv: cada misión marcada sobre una escala de 0 a 20 km/s.
## Muestra de un vistazo cuánto más difícil es cada destino.

const MAX_DV := 20.0

var selected := -1:
	set(v):
		selected = v
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = 170
	resized.connect(queue_redraw)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()


func _draw() -> void:
	var f := Game.font_mono
	var fm := Game.font_mono_medium
	var left := 8.0
	var right := size.x - 40.0
	var axis_y := size.y - 34.0
	var x_of := func(dv: float) -> float: return left + (right - left) * dv / MAX_DV

	draw_string(fm, Vector2(left, axis_y - 4 * 26.0 - 30.0), tr("LEVELS_LADDER"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Game.INK_DIM)

	# Eje con marcas cada 1 km/s y rótulos cada 5
	draw_line(Vector2(left, axis_y), Vector2(right, axis_y), Game.INK_DIM, 1.0)
	for i in int(MAX_DV) + 1:
		var x: float = x_of.call(float(i))
		var major := i % 5 == 0
		draw_line(Vector2(x, axis_y), Vector2(x, axis_y + (10.0 if major else 5.0)), Game.INK_DIM, 1.0)
		if major:
			var s := str(i)
			var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(f, Vector2(x - w / 2.0, axis_y + 26), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Game.INK_DIM)
	draw_string(f, Vector2(right + 8, axis_y + 4), "km/s", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Game.INK_DIM)

	# Misiones ordenadas por Δv; los rótulos que chocan suben de fila
	var items := []
	for l in Game.levels:
		if l.get("dv_km_s") != null:
			items.append(l)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.dv_km_s) < float(b.dv_km_s))
	var row_end := [-INF, -INF, -INF, -INF]
	var row_h := 26.0
	for l in items:
		var i := int(l.id)
		var x: float = x_of.call(float(l.dv_km_s))
		var label := "%02d" % i
		var w := fm.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var row := 0
		while row < row_end.size() - 1 and row_end[row] > x - w / 2.0 - 6.0:
			row += 1
		row_end[row] = x + w / 2.0
		var unlocked := Game.is_unlocked(i)
		var is_sel := i == selected
		var col := Game.MARK if is_sel else (Game.INK if unlocked else Color(Game.INK_DIM, 0.45))
		var ly := axis_y - 22.0 - row * row_h
		draw_line(Vector2(x, axis_y), Vector2(x, ly + 6), Color(col, 0.7 if not is_sel else 1.0), 2.0 if is_sel else 1.0)
		draw_circle(Vector2(x, axis_y), 3.5 if is_sel else 2.5, col)
		draw_string(fm, Vector2(x - w / 2.0, ly), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
		if is_sel:
			var v := Game.dv_text(l)
			draw_string(f, Vector2(x + w / 2.0 + 8, ly), v, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Game.MARK)
