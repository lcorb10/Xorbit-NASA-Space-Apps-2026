class_name CodexFigure
extends Control
## Dibujo animado para cada concepto del manual (estilo plano técnico):
## dv / rocket_eq (tanque que se vacía y velocidad que crece), twr (empuje contra peso),
## cm / cp / stability (el viento endereza o voltea el cohete), isp (dos motores),
## staging (la primera etapa se suelta), gimbal (la tobera se inclina), orbit (cae y no toca la Tierra).

var kind := ""
var _t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(300, 180)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()


func _draw() -> void:
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), Color(Game.PAPER_DEEP, 0.9))
	var g := 18.0
	var x := 0.0
	while x < sz.x:
		draw_line(Vector2(x, 0), Vector2(x, sz.y), Color(Game.GRID, 0.6), 1.0)
		x += g
	var y := 0.0
	while y < sz.y:
		draw_line(Vector2(0, y), Vector2(sz.x, y), Color(Game.GRID, 0.6), 1.0)
		y += g
	draw_rect(Rect2(Vector2.ZERO, sz), Game.LINE, false, 1.0)
	match kind:
		"dv", "rocket_eq":
			_fig_dv(sz)
		"twr":
			_fig_twr(sz)
		"cm", "cp", "stability":
			_fig_stability(sz)
		"isp":
			_fig_isp(sz)
		"staging":
			_fig_staging(sz)
		"gimbal":
			_fig_gimbal(sz)
		"orbit":
			_fig_orbit(sz)
		"dvmap":
			_fig_dvmap(sz)
		"landing":
			_fig_landing(sz)


func _txt(p: Vector2, s: String, col := Game.INK_DIM, fs := 12) -> void:
	draw_string(Game.font_mono, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Cohete de perfil: base en p, alto h, ancho w. fill = fracción del tanque llena.
func _rocket(p: Vector2, h: float, w: float, fill := 1.0, ang := 0.0, col := Game.INK) -> void:
	var xf := Transform2D(ang, p)
	var body := PackedVector2Array([Vector2(-w / 2, 0), Vector2(w / 2, 0), Vector2(w / 2, -h * 0.75), Vector2(0, -h), Vector2(-w / 2, -h * 0.75), Vector2(-w / 2, 0)])
	var tank_top := -h * 0.7
	var level := lerpf(0.0, tank_top, fill)
	var liquid := PackedVector2Array([Vector2(-w / 2 + 2, -2), Vector2(w / 2 - 2, -2), Vector2(w / 2 - 2, level), Vector2(-w / 2 + 2, level)])
	if fill > 0.01:
		draw_colored_polygon(xf * liquid, Color(Game.MARK, 0.35))
	draw_polyline(xf * body, col, 2.0, true)
	draw_polyline(xf * PackedVector2Array([Vector2(-w / 2, 0), Vector2(-w * 0.9, 8), Vector2(-w / 2, -h * 0.2)]), col, 1.5, true)
	draw_polyline(xf * PackedVector2Array([Vector2(w / 2, 0), Vector2(w * 0.9, 8), Vector2(w / 2, -h * 0.2)]), col, 1.5, true)


func _flame(p: Vector2, length: float, ang := 0.0) -> void:
	var xf := Transform2D(ang, p)
	var fl := length * (0.85 + 0.15 * sin(_t * 30.0))
	draw_colored_polygon(xf * PackedVector2Array([Vector2(-5, 0), Vector2(5, 0), Vector2(0, fl)]), Color(Game.MARK, 0.85))


func _fig_dv(sz: Vector2) -> void:
	var k := fmod(_t / 5.0, 1.0)
	var m0 := 10.0
	var mf := 3.0
	var m := lerpf(m0, mf, k)
	var dv := 3.1 * log(m0 / m) # Isp 316 s · g0
	_rocket(Vector2(70, sz.y - 30), 110, 30, 1.0 - k)
	_flame(Vector2(70, sz.y - 30), 20)
	var bx := 130.0
	var bw := sz.x - bx - 20.0
	_txt(Vector2(bx, 30), "Δv = Isp·g₀·ln(m₀/m)", Game.INK, 13)
	_txt(Vector2(bx, 56), "m₀ = %.0f t   m = %.1f t" % [m0, m])
	draw_rect(Rect2(bx, 70, bw, 14), Game.LINE, false, 1.0)
	draw_rect(Rect2(bx, 70, bw * dv / 3.8, 14), Game.MARK)
	_txt(Vector2(bx, 102), "Δv = %.2f km/s" % dv, Game.MARK, 13)
	# Curva logarítmica
	var pts := PackedVector2Array()
	for i in 41:
		var kk := i / 40.0
		var mm := lerpf(m0, mf, kk)
		pts.append(Vector2(bx + kk * bw, sz.y - 20 - log(m0 / mm) / log(m0 / mf) * 50.0))
	draw_polyline(pts, Game.INK_DIM, 1.5, true)
	draw_circle(Vector2(bx + k * bw, sz.y - 20 - log(m0 / m) / log(m0 / mf) * 50.0), 4, Game.MARK)


func _fig_twr(sz: Vector2) -> void:
	var twr := 1.15 + 0.45 * sin(_t * 1.2)
	var lift := maxf(twr - 1.0, 0.0)
	var base := Vector2(sz.x * 0.35, sz.y - 22 - lift * 70.0 * (0.5 + 0.5 * sin(_t * 1.2 - 0.3)))
	draw_line(Vector2(20, sz.y - 22), Vector2(sz.x - 20, sz.y - 22), Game.INK_DIM, 2.0)
	_rocket(base, 90, 26, 0.8)
	_flame(base, 18 * twr)
	# Flechas: empuje arriba (naranja), peso abajo (claro)
	var up := 40.0 * twr
	draw_line(base + Vector2(40, -45), base + Vector2(40, -45 - up), Game.MARK, 3.0)
	draw_colored_polygon(PackedVector2Array([base + Vector2(34, -45 - up), base + Vector2(46, -45 - up), base + Vector2(40, -55 - up)]), Game.MARK)
	draw_line(base + Vector2(56, -45), base + Vector2(56, -5), Game.INK, 3.0)
	draw_colored_polygon(PackedVector2Array([base + Vector2(50, -5), base + Vector2(62, -5), base + Vector2(56, 5)]), Game.INK)
	_txt(Vector2(sz.x * 0.62, 40), "TWR = %.2f" % twr, Game.MARK if twr >= 1.0 else Game.INK, 16)
	_txt(Vector2(sz.x * 0.62, 64), tr("FIG_TWR_UP") if twr > 1.0 else tr("FIG_TWR_STAY"))


func _fig_stability(sz: Vector2) -> void:
	var good := fmod(_t, 8.0) < 4.0
	var tt := fmod(_t, 4.0)
	var ang := 0.35 * exp(-tt * 1.2) * cos(tt * 4.0) if good else minf(0.2 + tt * 0.9, PI)
	var c := Vector2(sz.x * 0.4, sz.y * 0.55)
	var xf := Transform2D(ang + PI / 2.0, c)
	draw_set_transform_matrix(xf * Transform2D(0, Vector2(0, 60)))
	_rocket(Vector2.ZERO, 120, 22, 0.6)
	var cm := Vector2(0, -70 if good else -45)
	var cp := Vector2(0, -40 if good else -80)
	draw_circle(cm, 6, Game.INK)
	draw_line(cp - Vector2(7, 0), cp + Vector2(7, 0), Game.MARK, 3.0)
	draw_line(cp - Vector2(0, 7), cp + Vector2(0, 7), Game.MARK, 3.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# Viento
	for i in 3:
		var yy := 40.0 + i * 40.0
		var xx := fmod(_t * 120.0 + i * 50.0, sz.x)
		draw_line(Vector2(xx, yy), Vector2(xx + 30, yy), Color(Game.INK_DIM, 0.6), 1.5)
	_txt(Vector2(14, sz.y - 30), "● CM   ✚ CP", Game.INK, 12)
	_txt(Vector2(14, sz.y - 12), tr("FIG_STAB_OK") if good else tr("FIG_STAB_BAD"), Game.GOOD if good else Game.MARK, 12)


func _fig_isp(sz: Vector2) -> void:
	for i in 2:
		var cx := sz.x * (0.27 + i * 0.4)
		var isp := 340.0 if i == 0 else 450.0
		var base := Vector2(cx, sz.y * 0.5)
		_rocket(base, 70, 22, 0.7)
		# Gas que sale más rápido con más Isp
		for j in 6:
			var spd := isp / 4.0
			var yy := fmod(_t * spd + j * 18.0, 90.0)
			draw_circle(base + Vector2(randf_range(-2, 2), yy + 6), 2.5, Color(Game.MARK, 1.0 - yy / 90.0))
		_txt(Vector2(cx - 40, 26), "Isp %d s" % int(isp), Game.MARK if i == 1 else Game.INK, 13)
		_txt(Vector2(cx - 40, sz.y - 10), "Δv %.1f km/s" % (isp * 9.81 * log(4.0) / 1000.0), Game.INK_DIM, 12)


func _fig_staging(sz: Vector2) -> void:
	var k := fmod(_t / 6.0, 1.0)
	var c := Vector2(sz.x * 0.5, sz.y - 20)
	var sep := 0.45
	var up := k * 80.0
	if k < sep:
		_rocket(c + Vector2(0, -up), 80, 24, 1.0 - k / sep)
		_flame(c + Vector2(0, -up), 18)
		draw_line(c + Vector2(-16, -up - 60), c + Vector2(16, -up - 60), Game.INK, 1.0)
	else:
		var kk := (k - sep) / (1.0 - sep)
		var top := c + Vector2(0, -up - 60)
		_rocket(top, 50, 18, 1.0 - kk * 0.8)
		_flame(top, 14)
		var fall := c + Vector2(-kk * 40.0, -sep * 80.0 + kk * kk * 60.0)
		_rocket(fall, 60, 24, 0.0, kk * 1.2, Game.INK_DIM)
	_txt(Vector2(14, 24), tr("FIG_STAGING"), Game.INK, 12)


func _fig_gimbal(sz: Vector2) -> void:
	var ang := 0.25 * sin(_t * 1.6)
	var base := Vector2(sz.x * 0.45, sz.y * 0.78)
	_rocket(base, 120, 28, 0.6, -ang * 0.3)
	_flame(base, 30, ang)
	draw_arc(base, 40, PI / 2 - 0.3, PI / 2 + 0.3, 16, Color(Game.MARK, 0.6), 1.5)
	_txt(Vector2(sz.x * 0.65, 50), "gimbal %+d°" % int(rad_to_deg(ang)), Game.MARK, 14)


func _fig_orbit(sz: Vector2) -> void:
	var c := Vector2(sz.x * 0.5, sz.y * 0.62)
	var r := 52.0
	draw_circle(c, r, Color(Game.INK, 0.12))
	draw_arc(c, r, 0, TAU, 64, Game.INK, 2.0)
	var k := fmod(_t / 4.0, 3.0)
	var top := c + Vector2(0, -r - 6)
	# Tres tiros: lento (cae), medio (cae más lejos), orbital (da la vuelta)
	for shot in 3:
		var spd: float = [0.35, 0.65, 1.0][shot]
		var pts := PackedVector2Array()
		for i in 60:
			var a: float = i / 59.0 * (PI * 2.0 if shot == 2 else PI * spd * 0.9)
			var rr: float = r + 6.0 + (0.0 if shot == 2 else -a * 14.0 / spd)
			if rr < r:
				break
			pts.append(c + Vector2(sin(a), -cos(a)) * rr)
		if pts.size() > 1:
			draw_polyline(pts, Game.MARK if shot == int(k) else Color(Game.INK_DIM, 0.5), 1.5 if shot != int(k) else 2.5, true)
	draw_circle(top, 4, Game.MARK)
	_txt(Vector2(14, 22), "7,8 km/s →", Game.MARK, 13)


## Mapa de Δv tipo metro: estaciones (círculos) unidas por tramos con su costo en km/s.
func _fig_dvmap(sz: Vector2) -> void:
	var es := TranslationServer.get_locale().begins_with("es")
	var w := sz.x
	var h := sz.y
	var y0 := h * 0.55
	var st := {
		"earth": Vector2(w * 0.06, y0), "leo": Vector2(w * 0.27, y0),
		"gto": Vector2(w * 0.42, h * 0.22), "geo": Vector2(w * 0.58, h * 0.22),
		"tli": Vector2(w * 0.47, y0), "llo": Vector2(w * 0.66, y0), "moon": Vector2(w * 0.86, y0),
		"tmi": Vector2(w * 0.45, h * 0.86), "mars": Vector2(w * 0.66, h * 0.86), "marsl": Vector2(w * 0.86, h * 0.86)}
	var legs := [["earth", "leo", "9,4"], ["leo", "gto", "2,4"], ["gto", "geo", "1,5"], ["leo", "tli", "3,1"],
		["tli", "llo", "0,9"], ["llo", "moon", "1,7"], ["leo", "tmi", "3,6"], ["tmi", "mars", "2,1"], ["mars", "marsl", "0,6"]]
	var hot := int(_t / 1.2) % legs.size()
	for i in legs.size():
		var a: Vector2 = st[legs[i][0]]
		var b: Vector2 = st[legs[i][1]]
		var col := Game.MARK if i == hot else Color(Game.INK, 0.55)
		draw_line(a, b, col, 4.0 if i == hot else 3.0, true)
		_txt((a + b) / 2.0 + Vector2(-10, -8), legs[i][2], col, 13)
	var names := {"earth": ["Earth", "Tierra"], "leo": ["Low orbit", "Órbita baja"], "geo": ["GEO", "GEO"],
		"moon": ["Moon", "Luna"], "llo": ["Moon orbit", "Órbita lunar"], "mars": ["Mars orbit", "Órbita Marte"], "marsl": ["Mars", "Marte"]}
	for k in st:
		var p: Vector2 = st[k]
		draw_circle(p, 6.0, Game.PAPER_DEEP)
		draw_arc(p, 6.0, 0, TAU, 16, Game.INK, 2.0, true)
		if names.has(k):
			_txt(p + Vector2(-16, 20), names[k][1 if es else 0], Game.INK_DIM, 11)


## Alunizaje: la nave baja frenando con el motor hacia abajo; la llama se achica al llegar al suelo.
func _fig_landing(sz: Vector2) -> void:
	var k := fmod(_t / 5.0, 1.0)
	var ground := sz.y * 0.82
	draw_line(Vector2(0, ground), Vector2(sz.x, ground), Game.INK_DIM, 2.0)
	var y := lerpf(sz.y * 0.15, ground - 26.0, 1.0 - pow(1.0 - k, 2.0))
	var x := lerpf(sz.x * 0.25, sz.x * 0.55, 1.0 - pow(1.0 - k, 3.0))
	var p := Vector2(x, y)
	draw_rect(Rect2(p + Vector2(-14, -16), Vector2(28, 16)), Game.INK, false, 2.0)
	draw_line(p + Vector2(-14, 0), p + Vector2(-22, 24), Game.INK, 2.0)
	draw_line(p + Vector2(14, 0), p + Vector2(22, 24), Game.INK, 2.0)
	if k < 0.92:
		_flame(p + Vector2(0, 2), 26.0 * (1.0 - k * 0.7))
	var v := (1.0 - k) * 1700.0
	_txt(Vector2(10, 18), "%d m/s" % int(v), Game.MARK, 13)
