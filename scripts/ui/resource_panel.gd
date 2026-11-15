class_name ResourcePanel
extends Control
## Los 6 recursos que pide el reto (masa, energía, presupuesto, datos, comunicaciones y tiempo),
## cada uno con su barra "usado / disponible". Verde si alcanza, lápiz rojo si no.
## Al pasar el mouse por una fila, explica qué es ese recurso y qué lo cambia.

const ROW_H := 30.0

var rows: Array = [] ## [{key, value, target, more, text}]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "-" # el texto real sale de _get_tooltip según la fila


func set_data(a: Dictionary) -> void:
	rows.clear()
	var ev: Dictionary = a.get("probe", {})
	var pm := float(a.get("payload_mass", 0.0))
	var pmin := float(a.get("payload_min", 0.0))
	rows.append({"key": "RS_MASS", "value": pm, "target": pmin, "more": true,
		"text": ("%d kg · min %d" % [int(pm), int(pmin)]) if pmin > 0.0 else "%d kg" % int(pm)})
	if not ev.is_empty():
		var have := float(ev.have_w)
		var need := float(ev.need_w)
		if have <= 0.0:
			rows.append({"key": "RS_POWER", "value": float(ev.battery_hours), "target": float(ev.mission_h), "more": true,
				"text": tr("RS_BATTERY") % [_dur(float(ev.battery_hours)), _dur(float(ev.mission_h))]})
		else:
			rows.append({"key": "RS_POWER", "value": have, "target": need, "more": true, "text": "%d W / %d W" % [int(have), int(need)]})
	var cost := float(a.get("cost", 0.0))
	var budget := float(a.get("budget", 0.0))
	rows.append({"key": "RS_BUDGET", "value": cost, "target": budget, "more": false,
		"text": ("US$ %s / %s M" % [Game.fmt(cost / 1e6, 1), Game.fmt_int(int(budget / 1e6))]) if budget > 0.0 else "US$ %s M" % Game.fmt(cost / 1e6, 1)})
	if ev.is_empty():
		queue_redraw()
		_resize()
		return
	var data := float(ev.data_mb)
	var down := float(ev.downlink_mb) if bool(ev.link_ok) else 0.0
	rows.append({"key": "RS_DATA", "value": data, "target": down, "more": false,
		"text": tr("RS_PER_DAY") % _mb(data)})
	rows.append({"key": "RS_COMMS", "value": down, "target": data, "more": true,
		"text": (tr("RS_PER_DAY") % _mb(down) + " · " + str(ev.get("ground", "")).to_upper()) if bool(ev.link_ok) else tr("RS_NO_LINK")})
	rows.append({"key": "RS_TIME", "value": float(ev.life_h), "target": float(ev.mission_h), "more": true,
		"text": "%s / %s" % [_dur(float(ev.life_h)), _dur(float(ev.mission_h))]})
	# Tiempo de desarrollo (CubeSat 101: de 9 a 24 meses)
	rows.append({"key": "RS_DEVROW", "value": 0.0, "target": 0.0, "more": true, "text": tr("TL_MONTHS") % int(round(float(ev.get("dev_months", 0.0))))})
	_resize()
	queue_redraw()


func _resize() -> void:
	custom_minimum_size = Vector2(0, ROW_H * rows.size())


static func _mb(mb: float) -> String:
	return "%s GB" % Game.fmt(mb / 1000.0, 1) if mb >= 1000.0 else "%d MB" % int(round(mb))


func _dur(h: float) -> String:
	if h >= 1e7:
		return "∞"
	if h < 48.0:
		return tr("RS_H") % Game.fmt(h, 1 if h < 10.0 else 0)
	if h < 24.0 * 700.0:
		return tr("RS_DAYS") % int(round(h / 24.0))
	return tr("RS_YEARS") % Game.fmt(h / 8766.0, 1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()


func _draw() -> void:
	var w := size.x
	for i in rows.size():
		var r: Dictionary = rows[i]
		var y := i * ROW_H
		var t := float(r.target)
		var v := float(r.value)
		var ok := t <= 0.0 or (v >= t if r.more else v <= t)
		var c := Game.GOOD if ok else Game.MARK
		draw_string(Game.font_mono_medium, Vector2(0, y + 13), tr(str(r.key)), HORIZONTAL_ALIGNMENT_LEFT, w * 0.42, 11, Game.INK_DIM)
		draw_string(Game.font_mono_medium, Vector2(w * 0.40, y + 13), str(r.text), HORIZONTAL_ALIGNMENT_RIGHT, w * 0.60, 13, Game.INK if ok else Game.MARK)
		var bar := Rect2(0, y + 19, w, 3)
		draw_rect(bar, Game.LINE)
		if t > 0.0:
			var sc := w / maxf(maxf(t, v) * 1.15, 0.0001)
			draw_rect(Rect2(bar.position, Vector2(minf(v * sc, w), 3)), c)
			draw_line(Vector2(t * sc, bar.position.y - 3), Vector2(t * sc, bar.end.y + 3), Game.INK, 2.0)
		else:
			draw_rect(Rect2(bar.position, Vector2(w * 0.5, 3)), Color(Game.INK_DIM, 0.4))


func _get_tooltip(at: Vector2) -> String:
	var i := int(at.y / ROW_H)
	if i < 0 or i >= rows.size():
		return ""
	return tr(str(rows[i].key) + "_TIP")
