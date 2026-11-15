class_name Meter
extends Control
## Indicador con meta: rótulo, valor y barra. Verde si se cumple, lápiz rojo si no.
## more_is_better = true para Δv (hay que llegar); false para el costo (no pasarse).

var caption := ""
var value := 0.0
var target := 0.0
var text := ""
var more_is_better := true


func _ready() -> void:
	custom_minimum_size = Vector2(240, 58)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()


func set_values(v: float, t: float, txt: String) -> void:
	value = v
	target = t
	text = txt
	queue_redraw()


func _draw() -> void:
	var ok := target <= 0.0 or (value >= target if more_is_better else value <= target)
	var c := Game.GOOD if ok else Game.MARK
	draw_string(Game.font_mono_medium, Vector2(0, 13), tr(caption), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Game.INK_DIM)
	draw_string(Game.font_display, Vector2(0, 40), text, HORIZONTAL_ALIGNMENT_LEFT, size.x, 24, Game.INK)
	var bar := Rect2(0, size.y - 8, size.x, 4)
	draw_rect(bar, Game.LINE)
	if target > 0.0:
		var full := maxf(target, value) * (1.0 if more_is_better else 1.0)
		var scale := bar.size.x / maxf(full * 1.15, 0.0001)
		draw_rect(Rect2(bar.position, Vector2(minf(value * scale, bar.size.x), 4)), c)
		var tx := target * scale
		draw_line(Vector2(tx, bar.position.y - 5), Vector2(tx, bar.end.y + 3), Game.INK, 2.0)
	else:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * 0.5, 4)), Color(Game.INK_DIM, 0.4))
