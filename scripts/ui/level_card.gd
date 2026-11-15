class_name LevelCard
extends Button
## Tarjeta de una misión en la pantalla de niveles. Se dibuja a mano
## para parecer una casilla de plano: número, nombre, Δv, presupuesto y estrellas.

var level: Dictionary
var index := 0
var selected := false:
	set(v):
		selected = v
		queue_redraw()


func setup(l: Dictionary) -> void:
	level = l
	index = int(l.id)


func _ready() -> void:
	custom_minimum_size = Vector2(0, 176)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_ALL
	text = ""
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(s, StyleBoxEmpty.new())
	for sig in [mouse_entered, mouse_exited, focus_entered, focus_exited]:
		sig.connect(queue_redraw)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()


func _draw() -> void:
	var unlocked := Game.is_unlocked(index)
	var hot := is_hovered() or has_focus()
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(Game.PAPER_DEEP, 0.88))
	if hot and not selected:
		draw_rect(r, Color(Game.INK, 0.04))
	var border := Game.MARK if selected else (Game.INK if hot else Game.LINE)
	draw_rect(r.grow(-0.5), border, false, 2.0 if selected else 1.0)
	# Marcas de esquina, como las de registro de un plano
	var k := 8.0
	for c in [Vector2(0, 0), Vector2(size.x, 0), Vector2(0, size.y), Vector2(size.x, size.y)]:
		var sx := 1.0 if c.x == 0 else -1.0
		var sy := 1.0 if c.y == 0 else -1.0
		draw_line(c + Vector2(4 * sx, 4 * sy), c + Vector2((4 + k) * sx, 4 * sy), border, 1.0)
		draw_line(c + Vector2(4 * sx, 4 * sy), c + Vector2(4 * sx, (4 + k) * sy), border, 1.0)

	var pad := 16.0
	var a := 1.0 if unlocked else 0.42
	draw_string(Game.font_mono_medium, Vector2(pad, pad + 16), "%02d" % index, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(Game.MARK if selected else Game.INK_DIM, maxf(a, 0.6)))

	# Estrellas o candado arriba a la derecha
	if unlocked:
		var stars := Game.stars_for(index)
		for i in 3:
			var c := Vector2(size.x - pad - 8 - (2 - i) * 20.0, pad + 10)
			var pts := Game.star_points(c, 8.0, 3.4)
			if i < stars:
				draw_colored_polygon(pts, Game.MARK)
			else:
				var closed := pts.duplicate()
				closed.append(pts[0])
				draw_polyline(closed, Color(Game.INK_DIM, 0.6), 1.0, true)
	else:
		var lc := Vector2(size.x - pad - 10, pad + 12)
		draw_arc(lc + Vector2(0, -3), 5.0, PI, TAU, 12, Game.INK_DIM, 1.5, true)
		draw_line(lc + Vector2(-5, -3), lc + Vector2(-5, 0), Game.INK_DIM, 1.5)
		draw_line(lc + Vector2(5, -3), lc + Vector2(5, 0), Game.INK_DIM, 1.5)
		draw_rect(Rect2(lc + Vector2(-7, 0), Vector2(14, 10)), Game.INK_DIM, false, 1.5)

	var mission_name := tr("LEVEL_%d_NAME" % index)
	var fs := _fit_size(mission_name, size.x - pad * 2, 28, 18)
	draw_multiline_string(Game.font_display, Vector2(pad, 74), mission_name, HORIZONTAL_ALIGNMENT_LEFT, size.x - pad * 2, fs, 2, Color(Game.INK, a))

	var y := size.y - pad - 22
	var f := Game.font_mono
	if unlocked:
		draw_string(f, Vector2(pad, y), "Δv  " + Game.dv_text(level), HORIZONTAL_ALIGNMENT_LEFT, size.x - pad * 2, 14, Game.INK_DIM)
		draw_string(f, Vector2(pad, y + 20), Game.budget_text(level), HORIZONTAL_ALIGNMENT_LEFT, size.x - pad * 2, 14, Game.INK_DIM)
	else:
		draw_string(Game.font_mono_medium, Vector2(pad, y + 20), tr("LEVELS_LOCKED"), HORIZONTAL_ALIGNMENT_LEFT, size.x - pad * 2, 13, Color(Game.INK_DIM, 0.7))


## Tamaño de letra más grande con el que la palabra más larga cabe en el ancho.
func _fit_size(text: String, width: float, max_size: int, min_size: int) -> int:
	var longest := 0.0
	var s := max_size
	while s > min_size:
		longest = 0.0
		for word in text.split(" "):
			longest = maxf(longest, Game.font_display.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x)
		if longest <= width:
			break
		s -= 1
	return s
