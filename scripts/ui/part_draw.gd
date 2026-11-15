class_name PartDraw
extends RefCounted
## Dibuja una pieza en estilo plano: contorno de su perfil (el mismo que usa la física)
## más los detalles de su tipo (cúpulas del tanque, toberas, rayado de corte del separador, aletas).
## origin = punto del eje en la parte de arriba de la pieza (px); s = px por metro.


static func draw_part(ci: CanvasItem, p: Dictionary, origin: Vector2, s: float, ink: Color, fill: Color, detail := true) -> void:
	var t := Catalog.template(p.id)
	if t.is_empty():
		return
	var kind: String = t.kind
	var prof := RocketAnalysis.profile(p)
	var length := RocketAnalysis.part_length(p)
	var r := float(p.get("diameter", 1.0)) / 2.0 * s
	var faint := Color(ink, ink.a * 0.55)
	var f := Game.font_mono

	# Aletas detrás del cuerpo
	var fins: Dictionary = p.get("fins", {})
	if int(fins.get("count", 0)) > 0:
		var yb := origin.y + (length - float(fins.get("offset", 0.0))) * s
		var root := float(fins.get("root", 0.5)) * s
		var tip := float(fins.get("tip", 0.3)) * s
		var span := float(fins.get("span", 0.3)) * s
		for side in [-1.0, 1.0]:
			var poly := PackedVector2Array([
				Vector2(origin.x + side * r, yb - root), Vector2(origin.x + side * (r + span), yb - tip),
				Vector2(origin.x + side * (r + span), yb), Vector2(origin.x + side * r, yb)])
			ci.draw_colored_polygon(poly, fill)
			var closed := poly.duplicate()
			closed.append(poly[0])
			ci.draw_polyline(closed, ink, 1.5, true)
		if int(fins.count) == 4:
			ci.draw_line(Vector2(origin.x, yb - root), Vector2(origin.x, yb), ink, 2.0)

	# Contorno del perfil (lado derecho bajando, lado izquierdo subiendo)
	var outline := PackedVector2Array()
	for pt in prof:
		outline.append(origin + Vector2(pt.x * s, pt.y * s))
	for i in range(prof.size() - 1, -1, -1):
		outline.append(origin + Vector2(-prof[i].x * s, prof[i].y * s))
	if not Geometry2D.triangulate_polygon(outline).is_empty():
		ci.draw_colored_polygon(outline, fill)
	var closed_outline := outline.duplicate()
	closed_outline.append(outline[0])
	ci.draw_polyline(closed_outline, ink, 1.5, true)

	if not detail:
		return
	var top := origin.y
	var body_bottom := origin.y + prof[prof.size() - 1].y * s
	var h := body_bottom - top
	match kind:
		"tank":
			# Cúpulas de los extremos y el propelente, si cabe el rótulo
			for yy in [top + minf(h * 0.08, r * 0.6), body_bottom - minf(h * 0.08, r * 0.6)]:
				ci.draw_dashed_line(Vector2(origin.x - r, yy), Vector2(origin.x + r, yy), faint, 1.0, 4.0)
			var label: String = Catalog.propellants.get(p.get("propellant", ""), {}).get("label", "")
			_label_in(ci, label, origin, r, top, body_bottom, ink)
		"solid":
			ci.draw_dashed_line(Vector2(origin.x, top + 6), Vector2(origin.x, body_bottom - 6), faint, 1.0, 6.0)
			var throat := r * 0.35
			var exit := r * 0.8
			var nl := r * 1.0
			_bell(ci, Vector2(origin.x, body_bottom), throat, exit, nl, ink, fill)
			_label_in(ci, "APCP", origin, r * 0.8, top, body_bottom, ink)
		"engine":
			if not t.has("profile"):
				var b := RocketAnalysis.bell(p.get("engine", ""))
				var n := int(p.get("count", 1))
				var cols := 1 if n == 1 else int(ceil(sqrt(float(n))))
				var cell := 2.0 * r / cols
				var exit := minf(float(b.exit_d) * s, cell * 0.92)
				var bl := float(b.length) * s * (exit / maxf(float(b.exit_d) * s, 0.001))
				for c in cols:
					var cx := origin.x - r + (c + 0.5) * cell
					_bell(ci, Vector2(cx, body_bottom), exit * 0.3, exit, bl, ink, fill)
				if n > 1:
					ci.draw_string(Game.font_mono_medium, Vector2(origin.x + r + 8, body_bottom + bl * 0.6), "×%d" % n, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ink)
		"payload":
			var inset := minf(r * 0.3, h * 0.2)
			var rect := Rect2(Vector2(origin.x - r + inset, top + inset), Vector2(2.0 * (r - inset), maxf(h - 2.0 * inset, 1.0)))
			_dashed_rect(ci, rect, faint)
			_label_in(ci, "%s kg" % Game.fmt_int(int(p.get("payload_kg", 0))), origin, r - inset - 3.0, top, body_bottom, ink, origin.x + r + 10.0)
		"decoupler":
			# Rayado de corte a 45°, como en una sección de plano
			var step := 6.0
			var x := -r - h
			while x < r:
				var a := Vector2(x, h)
				var b := Vector2(x + h, 0)
				if a.x < -r:
					a = Vector2(-r, h - (-r - a.x))
				if b.x > r:
					b = Vector2(r, (b.x - r))
				if a.x <= b.x:
					ci.draw_line(Vector2(origin.x + a.x, top + a.y), Vector2(origin.x + b.x, top + b.y), faint, 1.0)
				x += step


static func _bell(ci: CanvasItem, top_center: Vector2, throat: float, exit: float, length: float, ink: Color, fill: Color) -> void:
	var right := PackedVector2Array()
	for i in 7:
		var u := i / 6.0
		var w := throat + (exit - throat) * sqrt(u)
		right.append(top_center + Vector2(w / 2.0, u * length))
	var poly := PackedVector2Array(right)
	for i in range(right.size() - 1, -1, -1):
		poly.append(Vector2(2.0 * top_center.x - right[i].x, right[i].y))
	if not Geometry2D.triangulate_polygon(poly).is_empty():
		ci.draw_colored_polygon(poly, fill)
	poly.append(poly[0])
	ci.draw_polyline(poly, ink, 1.5, true)


static func _dashed_rect(ci: CanvasItem, r: Rect2, c: Color) -> void:
	var p := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		ci.draw_dashed_line(p[i], p[i + 1], c, 1.0, 4.0)


static func _label_in(ci: CanvasItem, text: String, origin: Vector2, r: float, top: float, bottom: float, ink: Color, outside_x := -1.0) -> void:
	if text.is_empty():
		return
	var size := 11
	var w := Game.font_mono.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if w < 2.0 * r - 8.0 and bottom - top > 18.0:
		ci.draw_string(Game.font_mono, Vector2(origin.x - w / 2.0, (top + bottom) / 2.0 + 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(ink, ink.a * 0.8))
	elif bottom - top > w + 12.0 and 2.0 * r > 28.0:
		# Rótulo vertical si la pieza es angosta y alta
		# Pegado a la pared derecha para no tapar el eje (donde van CM y CP)
		ci.draw_set_transform(Vector2(origin.x + r * 0.62 + 4.0, (top + bottom) / 2.0 + w / 2.0), -PI / 2.0)
		ci.draw_string(Game.font_mono, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(ink, ink.a * 0.8))
		ci.draw_set_transform(Vector2.ZERO)
	elif outside_x > 0.0:
		ci.draw_string(Game.font_mono, Vector2(outside_x, (top + bottom) / 2.0 + 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(ink, ink.a * 0.8))


## Ancho total en metros con aletas (para encuadrar).
static func half_width(p: Dictionary) -> float:
	var w := float(p.get("diameter", 1.0)) / 2.0
	var fins: Dictionary = p.get("fins", {})
	if int(fins.get("count", 0)) > 0:
		w += float(fins.get("span", 0.0))
	return w


## Lo que sobresale por debajo de la pieza (toberas), en metros.
static func below(p: Dictionary) -> float:
	var t := Catalog.template(p.id)
	match t.get("kind"):
		"solid":
			return float(p.get("diameter", 1.0)) / 2.0
		"engine":
			return 0.0 if t.has("profile") else 0.0 # la tobera ya está dentro de part_length
	return 0.0
