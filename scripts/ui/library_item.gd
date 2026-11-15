class_name LibraryItem
extends Button
## Pieza de la biblioteca: clic para agregarla o arrástrala al plano o al hangar.

var part_id := ""


func _get_drag_data(_at: Vector2) -> Variant:
	if disabled:
		return null
	var preview := PartThumb.new()
	preview.setup(Catalog.new_part(part_id))
	preview.custom_minimum_size = Vector2(70, 90)
	preview.size = preview.custom_minimum_size
	preview.ink = Game.MARK
	var holder := Control.new()
	holder.add_child(preview)
	preview.position = -preview.size / 2.0
	set_drag_preview(holder)
	return {"type": "new_part", "id": part_id}
