class_name TrashPanel
extends PanelContainer
## Panel de la biblioteca: si sueltas aquí una pieza del cohete, se quita.

var on_drop: Callable
var _hot := false


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	var ok: bool = data is Dictionary and data.get("type") == "move"
	if ok != _hot:
		_hot = ok
		queue_redraw()
	return ok


func _drop_data(_at: Vector2, data: Variant) -> void:
	_hot = false
	queue_redraw()
	if on_drop.is_valid():
		on_drop.call(int(data.index))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _hot:
		_hot = false
		queue_redraw()


func _draw() -> void:
	if _hot:
		draw_rect(Rect2(Vector2.ZERO, size), Color(Game.MARK, 0.12))
		draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), Game.MARK, false, 2.0)
