class_name RocketAnatomy
extends Control
## Dibujo del manual "Cómo se arma un cohete": un cohete de dos etapas que se arma solo,
## pieza por pieza de abajo hacia arriba, con una línea de llamada a cada pieza.
## La pieza que se está explicando brilla en naranja; step_changed avisa cuál es
## (el manual resalta la fila de texto que le corresponde).

signal step_changed(i: int)

## Orden de armado (de abajo hacia arriba). Coincide con data/codex.json → build.steps.
const PARTS := ["engine1", "fins", "tank1", "decoupler", "engine2", "tank2", "payload", "nose"]
const STEP_S := 2.6

var step := -1
var hold := -1 ## si >= 0, se queda mostrando esa pieza (el ratón está sobre su fila)
var _t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(300, 520)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	var total := STEP_S * (PARTS.size() + 2)
	var s := int(fmod(_t, total) / STEP_S)
	if hold >= 0:
		s = hold
	if s != step:
		step = s
		step_changed.emit(step if step < PARTS.size() else -1)
	queue_redraw()


## Rectángulos de cada pieza (x centrado en cx), de abajo hacia arriba.
func _layout() -> Dictionary:
	var h := size.y - 30.0
	var w := minf(size.x * 0.26, 64.0)
	var cx := size.x * 0.5
	var base := size.y - 18.0
	var u := h / 100.0 # el cohete mide 100 unidades
	var r := {}
	var y := base
	# (alto, ancho) de abajo hacia arriba; las lambdas copian las variables, así que va en un bucle
	var stack := [["engine1", 9.0, 0.7], ["tank1", 38.0, 1.0], ["decoupler", 3.0, 1.0], ["engine2", 7.0, 0.55],
		["tank2", 18.0, 0.82], ["payload", 11.0, 0.82], ["nose", 13.0, 0.82]]
	for s in stack:
		var hh := float(s[1]) * u
		var ww := float(s[2]) * w
		r[s[0]] = Rect2(cx - ww / 2.0, y - hh, ww, hh)
		y -= hh
	r["fins"] = Rect2(cx - w * 1.05, (r.tank1 as Rect2).end.y - 14.0 * u, w * 2.1, 14.0 * u)
	return r


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Game.PAPER_DEEP, 0.9))
	var g := 18.0
	var x := 0.0
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(Game.GRID, 0.6), 1.0)
		x += g
	var yy := 0.0
	while yy < size.y:
		draw_line(Vector2(0, yy), Vector2(size.x, yy), Color(Game.GRID, 0.6), 1.0)
		yy += g
	draw_rect(Rect2(Vector2.ZERO, size), Game.LINE, false, 1.0)
	var r := _layout()
	var shown := step if step >= 0 else PARTS.size()
	# Plataforma
	draw_line(Vector2(size.x * 0.2, size.y - 18.0), Vector2(size.x * 0.8, size.y - 18.0), Game.INK_DIM, 2.0)
	for i in PARTS.size():
		if i > shown:
			break
		var id: String = PARTS[i]
		var rc: Rect2 = r[id]
		var hot := i == step
		# La pieza nueva cae desde arriba a su lugar
		var k := clampf(fmod(_t, STEP_S) / 0.5, 0.0, 1.0) if hot and hold < 0 else 1.0
		var drop := (1.0 - k * k) * -40.0
		rc.position.y += drop
		var col := Game.MARK if hot else Game.INK
		var fill := Color(Game.MARK, 0.25) if hot else Color(Game.INK, 0.07)
		_part(id, rc, col, fill)
		if hot:
			_callout(rc, i + 1)
	# Números de cada pieza ya puesta
	for i in mini(shown + 1, PARTS.size()):
		var rc2: Rect2 = r[PARTS[i]]
		var side := -1.0 if i % 2 == 0 else 1.0
		var px := rc2.get_center().x + side * (r.tank1 as Rect2).size.x * 1.25
		var py := rc2.get_center().y
		if PARTS[i] == "fins":
			py = rc2.end.y - 6.0
		draw_line(Vector2(px - side * 12.0, py), Vector2(rc2.get_center().x + side * rc2.size.x * 0.5, py), Color(Game.INK_DIM, 0.6), 1.0)
		draw_circle(Vector2(px, py), 11.0, Game.MARK if i == step else Game.LINE)
		draw_string(Game.font_mono_medium, Vector2(px - 4.0, py + 5.0), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Game.PAPER_DEEP if i == step else Game.INK)
	# Llama al final, cuando el cohete está completo
	if step >= PARTS.size():
		var e: Rect2 = r.engine1
		var fl := 50.0 * (0.85 + 0.15 * sin(_t * 30.0))
		draw_colored_polygon(PackedVector2Array([Vector2(e.position.x + 4, e.end.y), Vector2(e.end.x - 4, e.end.y), Vector2(e.get_center().x, e.end.y + fl)]), Color(Game.MARK, 0.85))


func _part(id: String, rc: Rect2, col: Color, fill: Color) -> void:
	match id:
		"nose":
			var poly := PackedVector2Array([Vector2(rc.get_center().x, rc.position.y)])
			for k in range(1, 13):
				var a := float(k) / 12.0
				poly.append(Vector2(rc.get_center().x + rc.size.x / 2.0 * sin(a * PI / 2.0), rc.position.y + rc.size.y * a))
			for k in range(12, 0, -1):
				var a := float(k) / 12.0
				poly.append(Vector2(rc.get_center().x - rc.size.x / 2.0 * sin(a * PI / 2.0), rc.position.y + rc.size.y * a))
			draw_colored_polygon(poly, fill)
			poly.append(poly[0])
			draw_polyline(poly, col, 2.0, true)
		"engine1", "engine2":
			var top_w := rc.size.x * 0.45
			var poly := PackedVector2Array([Vector2(rc.get_center().x - top_w / 2, rc.position.y), Vector2(rc.get_center().x + top_w / 2, rc.position.y),
				Vector2(rc.end.x, rc.end.y), Vector2(rc.position.x, rc.end.y)])
			draw_colored_polygon(poly, fill)
			poly.append(poly[0])
			draw_polyline(poly, col, 2.0, true)
		"fins":
			var c := rc.get_center().x
			var half := rc.size.x * 0.24
			for s in [-1.0, 1.0]:
				var poly := PackedVector2Array([Vector2(c + s * half, rc.position.y), Vector2(c + s * rc.size.x / 2.0, rc.end.y - rc.size.y * 0.15),
					Vector2(c + s * rc.size.x / 2.0, rc.end.y), Vector2(c + s * half, rc.end.y)])
				draw_colored_polygon(poly, fill)
				poly.append(poly[0])
				draw_polyline(poly, col, 2.0, true)
		"decoupler":
			draw_rect(rc, Color(col, 0.5))
			draw_rect(rc, col, false, 2.0)
		_:
			draw_rect(rc, fill)
			draw_rect(rc, col, false, 2.0)
			if id.begins_with("tank"):
				# Dos compartimentos: combustible y oxidante
				var mid := rc.position.y + rc.size.y * 0.45
				draw_line(Vector2(rc.position.x, mid), Vector2(rc.end.x, mid), Color(col, 0.6), 1.0)
			if id == "payload":
				draw_circle(rc.get_center(), rc.size.x * 0.2, Color(col, 0.6))


func _callout(rc: Rect2, _n: int) -> void:
	var a := 0.5 + 0.5 * sin(_t * 6.0)
	draw_rect(rc.grow(4.0), Color(Game.MARK, a), false, 2.0)
