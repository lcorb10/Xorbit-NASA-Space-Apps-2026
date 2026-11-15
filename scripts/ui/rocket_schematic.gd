class_name RocketSchematic
extends Control
## Vista lateral de un cohete de dos etapas dibujada como plano.
## Al aparecer, el contorno se traza solo; después aparecen cotas,
## centro de masa (CM), centro de presión (CP) y rótulos.

const H := 42.0 # altura en metros (unidades del dibujo)
const R := 1.8 # radio del cuerpo
const NOSE := 9.0
const SEP_Y := 17.0
const BODY_END := 38.0
const DRAW_TIME := 1.8
const NOTE_TIME := 0.7

var _t := 0.0
var _paths: Array[PackedVector2Array] = []
var _dashed: Array[PackedVector2Array] = []
var _total := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	resized.connect(queue_redraw)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()


func _process(delta: float) -> void:
	if _t < DRAW_TIME + NOTE_TIME:
		_t += delta
		queue_redraw()


func _build() -> void:
	# Perfil derecho de la nariz (ojiva) en coordenadas del cohete: x = radio, y = desde la punta
	var right := PackedVector2Array()
	for i in 13:
		var y := NOSE * i / 12.0
		right.append(Vector2(R * sqrt(1.0 - pow(1.0 - y / NOSE, 2.0)), y))
	right.append(Vector2(R, BODY_END))
	var left := PackedVector2Array()
	for p in right:
		left.append(Vector2(-p.x, p.y))
	left.reverse()
	var hull := PackedVector2Array()
	hull.append_array(left)
	hull.append_array(right.slice(1))
	hull.append(Vector2(-R, BODY_END))
	_paths = [hull]
	# Tobera
	_paths.append(PackedVector2Array([Vector2(-0.7, BODY_END), Vector2(-1.4, H - 0.6), Vector2(1.4, H - 0.6), Vector2(0.7, BODY_END)]))
	# Aletas
	for s in [-1.0, 1.0]:
		_paths.append(PackedVector2Array([Vector2(R * s, 31.0), Vector2(3.9 * s, 37.0), Vector2(3.9 * s, 39.2), Vector2(R * s, 37.4)]))
	# Separación de etapas y bahía de carga
	_paths.append(PackedVector2Array([Vector2(-R, SEP_Y), Vector2(R, SEP_Y)]))
	_dashed = [
		PackedVector2Array([Vector2(-1.3, 4.6), Vector2(1.3, 4.6), Vector2(1.3, NOSE + 1.2), Vector2(-1.3, NOSE + 1.2), Vector2(-1.3, 4.6)]),
		PackedVector2Array([Vector2(-R, 13.0), Vector2(R, 13.0)]),
		PackedVector2Array([Vector2(-R, 26.0), Vector2(R, 26.0)]),
	]
	_total = 0.0
	for p in _paths:
		_total += _length(p)


func _length(p: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, p.size()):
		l += p[i - 1].distance_to(p[i])
	return l


func _xf() -> Transform2D:
	# Escala para que el cohete ocupe el 80 % del alto; corrido a la derecha
	# para dejar sitio a los rótulos de la izquierda
	var s := size.y * 0.8 / H
	return Transform2D(0.0, Vector2(s, s), 0.0, Vector2(size.x * 0.62, size.y * 0.08))


func _draw() -> void:
	if size.y < 50:
		return
	var xf := _xf()
	var s := xf.get_scale().x
	var ink := Game.INK
	var p := clampf(_t / DRAW_TIME, 0.0, 1.0)
	p = 1.0 - pow(1.0 - p, 3.0) # desacelera al final, como un trazo a mano

	# Contorno que se va trazando
	var budget := _total * p
	for path in _paths:
		var pts := PackedVector2Array()
		pts.append(xf * path[0])
		for i in range(1, path.size()):
			if budget <= 0.0:
				break
			var seg := path[i - 1].distance_to(path[i])
			var k := minf(1.0, budget / seg)
			pts.append(xf * path[i - 1].lerp(path[i], k))
			budget -= seg
		if pts.size() > 1:
			draw_polyline(pts, ink, 2.0, true)

	# Lo que aparece después del trazo
	var a := clampf((_t - DRAW_TIME * 0.85) / NOTE_TIME, 0.0, 1.0)
	if a <= 0.0:
		return
	var dim := Color(Game.INK_DIM, a)
	var faint := Color(Game.INK_DIM, a * 0.6)
	for d in _dashed:
		for i in range(1, d.size()):
			draw_dashed_line(xf * d[i - 1], xf * d[i], faint, 1.0, 6.0, true, true)
	# Eje de simetría (línea de centro: trazo-punto)
	draw_dashed_line(xf * Vector2(0, -1.5), xf * Vector2(0, H + 1.0), Color(Game.INK_DIM, a * 0.35), 1.0, 14.0)

	var f := Game.font_mono
	var fm := Game.font_mono_medium
	# Cota de altura total a la derecha
	var cx := xf * Vector2(9.6, 0)
	var top := xf * Vector2(9.6, 0)
	var bot := xf * Vector2(9.6, H - 0.6)
	draw_line(xf * Vector2(1.0, 0), xf * Vector2(10.3, 0), faint, 1.0)
	draw_line(xf * Vector2(1.6, H - 0.6), xf * Vector2(10.3, H - 0.6), faint, 1.0)
	draw_line(top, bot, dim, 1.0)
	_arrow(top, Vector2.UP, dim)
	_arrow(bot, Vector2.DOWN, dim)
	draw_set_transform(Vector2(cx.x - 8, (top.y + bot.y) / 2.0 + 30), -PI / 2.0)
	draw_string(fm, Vector2.ZERO, "%s m" % Game.fmt(H), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(Game.INK, a))
	draw_set_transform(Vector2.ZERO)

	# Cota de diámetro abajo
	var dy := H + 2.4
	var l0 := xf * Vector2(-R, dy)
	var l1 := xf * Vector2(R, dy)
	draw_line(xf * Vector2(-R, BODY_END + 1.0), xf * Vector2(-R, dy + 0.6), faint, 1.0)
	draw_line(xf * Vector2(R, BODY_END + 1.0), xf * Vector2(R, dy + 0.6), faint, 1.0)
	draw_line(l0, l1, dim, 1.0)
	_arrow(l0, Vector2.LEFT, dim)
	_arrow(l1, Vector2.RIGHT, dim)
	draw_string(fm, Vector2(l1.x + 10, l1.y + 5), "Ø %s m" % Game.fmt(R * 2.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(Game.INK, a))

	# Centro de masa: círculo con dos cuadrantes rellenos (símbolo de dibujo técnico)
	var cm := xf * Vector2(0, 22.5)
	var r := 9.0
	draw_circle(cm, r, Color(Game.PAPER, a))
	draw_arc(cm, r, 0, TAU, 32, Color(Game.INK, a), 1.5, true)
	_quadrant(cm, r, -PI / 2.0, Color(Game.INK, a))
	_quadrant(cm, r, PI / 2.0, Color(Game.INK, a))
	# Centro de presión: círculo con cruz, en lápiz rojo
	var cp := xf * Vector2(0, 30.0)
	var mark := Color(Game.MARK, a)
	draw_circle(cp, r, Color(Game.PAPER, a))
	draw_arc(cp, r, 0, TAU, 32, mark, 1.5, true)
	draw_line(cp + Vector2(-r, 0), cp + Vector2(r, 0), mark, 1.5)
	draw_line(cp + Vector2(0, -r), cp + Vector2(0, r), mark, 1.5)

	# Rótulos con línea guía a la izquierda
	var lx := xf * Vector2(-11.0, 0)
	_callout(xf * Vector2(-1.3, 7.0), Vector2(lx.x, (xf * Vector2(0, 7.0)).y), tr("SCHEM_PAYLOAD"), a)
	_callout(xf * Vector2(-R, 11.0), Vector2(lx.x, (xf * Vector2(0, 12.0)).y), tr("SCHEM_STAGE2"), a)
	_callout(xf * Vector2(-R, SEP_Y), Vector2(lx.x, (xf * Vector2(0, SEP_Y)).y), tr("SCHEM_SEP"), a)
	_callout(cm + Vector2(-r, 0), Vector2(lx.x, cm.y), tr("SCHEM_CM"), a)
	_callout(cp + Vector2(-r, 0), Vector2(lx.x, cp.y), tr("SCHEM_CP"), a, Game.MARK)
	_callout(xf * Vector2(-R, 34.0), Vector2(lx.x, (xf * Vector2(0, 35.0)).y), tr("SCHEM_STAGE1"), a)
	# Margen de estabilidad entre CM y CP
	var gap := xf * Vector2(4.4, 22.5)
	var gap2 := xf * Vector2(4.4, 30.0)
	draw_line(gap, gap2, Color(Game.MARK, a * 0.8), 1.0)
	_arrow(gap, Vector2.UP, Color(Game.MARK, a * 0.8))
	_arrow(gap2, Vector2.DOWN, Color(Game.MARK, a * 0.8))
	draw_string(f, Vector2(gap.x + 8, (gap.y + gap2.y) / 2.0 + 5), "%s cal" % Game.fmt((30.0 - 22.5) / (R * 2.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(Game.MARK, a))
	if s <= 0.0:
		return


func _callout(from: Vector2, to: Vector2, text: String, a: float, color := Game.INK) -> void:
	var c := Color(color, a)
	var elbow := Vector2(to.x + 24.0, to.y)
	draw_line(from, elbow, Color(Game.INK_DIM, a * 0.7), 1.0)
	draw_line(elbow, to, Color(Game.INK_DIM, a * 0.7), 1.0)
	draw_circle(from, 2.0, c)
	var w := Game.font_mono_medium.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(Game.font_mono_medium, Vector2(to.x - w - 8.0, to.y + 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, c)


func _arrow(tip: Vector2, dir: Vector2, color: Color) -> void:
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * 9.0 + side * 3.0, tip - dir * 9.0 - side * 3.0]), color)


func _quadrant(c: Vector2, r: float, start: float, color: Color) -> void:
	var pts := PackedVector2Array([c])
	for i in 9:
		var ang := start + (PI / 2.0) * i / 8.0
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	draw_colored_polygon(pts, color)
