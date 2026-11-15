class_name NasaCycle
extends Control
## Ciclo de la NASA para diseñar una misión (6 pasos) y el nivel de madurez del concepto de JPL (CML 1-4).
## Fuente: "Design and Develop Science Missions" (NASA SSVI, 2025) y "Concept Maturity Levels" (JPL).
## Ver docs/RECURSOS-NASA.md. Se muestra sutil: una tira de 6 segmentos y una línea con el CML.

const STEPS := ["NC_NEED", "NC_CONCEPT", "NC_REQ", "NC_DESIGN", "NC_VERIFY", "NC_IMPLEMENT"]

var done := 1 ## pasos cumplidos (0-6)
var cml := 1 ## 1-4


func _ready() -> void:
	custom_minimum_size = Vector2(0, 40)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "-"


func set_state(steps_done: int, level: int) -> void:
	done = steps_done
	cml = level
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var gap := 4.0
	var seg := (w - gap * 5.0) / 6.0
	for i in 6:
		var x := i * (seg + gap)
		var col := Game.GOOD if i < done else (Game.MARK if i == done else Game.LINE)
		draw_rect(Rect2(x, 0, seg, 4), col)
		draw_string(Game.font_mono_medium, Vector2(x, 16), tr(STEPS[i]), HORIZONTAL_ALIGNMENT_LEFT, seg, 9, Game.INK if i <= done else Game.INK_DIM)
	var txt := "CML %d · %s" % [cml, tr("CML_%d" % cml)]
	draw_string(Game.font_mono_medium, Vector2(0, 35), txt, HORIZONTAL_ALIGNMENT_LEFT, w, 12, Game.MARK if cml < 4 else Game.GOOD)


func _get_tooltip(_at: Vector2) -> String:
	return tr("NC_TIP") + "\n\n" + tr("CML_TIP_%d" % cml)
