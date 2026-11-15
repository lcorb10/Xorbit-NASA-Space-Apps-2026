class_name PartThumb
extends Control
## Miniatura de una pieza para la biblioteca: el mismo dibujo que en el plano, encuadrado.

var part: Dictionary = {}
var ink := Game.INK


func setup(p: Dictionary) -> void:
	part = p
	custom_minimum_size = Vector2(56, 64)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	if part.is_empty():
		return
	var length := RocketAnalysis.part_length(part)
	var extra := PartDraw.below(part)
	var hw := PartDraw.half_width(part)
	var s := minf((size.y - 8.0) / (length + extra), (size.x - 8.0) / (2.0 * hw))
	var y0 := (size.y - (length + extra) * s) / 2.0
	PartDraw.draw_part(self, part, Vector2(size.x / 2.0, y0), s, ink, Color(Game.PAPER_DEEP, 0.9), false)
