class_name BlueprintBackground
extends Control
## Fondo de plano: cuadrícula, marco de hoja y zonas de referencia (1-8, A-D)
## como en un plano de ingeniería real.

const MINOR := 24.0
const MAJOR_EVERY := 5
const FRAME := 20.0
const ZONES_X := 8
const ZONES_Y := 4


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Game.PAPER)
	var i := 0
	var x := 0.0
	while x <= size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), Game.GRID_MAJOR if i % MAJOR_EVERY == 0 else Game.GRID, 1.0)
		x += MINOR
		i += 1
	i = 0
	var y := 0.0
	while y <= size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), Game.GRID_MAJOR if i % MAJOR_EVERY == 0 else Game.GRID, 1.0)
		y += MINOR
		i += 1

	# Marco de la hoja con franja de zonas
	var outer := Rect2(Vector2(FRAME, FRAME), size - Vector2(FRAME, FRAME) * 2.0)
	var inner := outer.grow(-16.0)
	draw_rect(outer, Game.LINE, false, 1.0)
	draw_rect(inner, Game.LINE, false, 1.5)
	var f := Game.font_mono
	var col := Color(Game.INK_DIM, 0.55)
	for z in ZONES_X:
		var zx := outer.position.x + outer.size.x * (z + 0.5) / ZONES_X
		var label := str(z + 1)
		for yy in [outer.position.y + 12.0, outer.end.y - 4.0]:
			draw_string(f, Vector2(zx - 4, yy), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		if z > 0:
			var bx := outer.position.x + outer.size.x * z / ZONES_X
			draw_line(Vector2(bx, outer.position.y), Vector2(bx, inner.position.y), Game.LINE, 1.0)
			draw_line(Vector2(bx, inner.end.y), Vector2(bx, outer.end.y), Game.LINE, 1.0)
	for z in ZONES_Y:
		var zy := outer.position.y + outer.size.y * (z + 0.5) / ZONES_Y
		var label := "ABCD"[z]
		for xx in [outer.position.x + 4.0, outer.end.x - 12.0]:
			draw_string(f, Vector2(xx, zy + 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		if z > 0:
			var by := outer.position.y + outer.size.y * z / ZONES_Y
			draw_line(Vector2(outer.position.x, by), Vector2(inner.position.x, by), Game.LINE, 1.0)
			draw_line(Vector2(inner.end.x, by), Vector2(outer.end.x, by), Game.LINE, 1.0)
