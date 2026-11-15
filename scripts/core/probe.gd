class_name Probe
extends RefCounted
## La sonda que va en la bahía de carga: instrumentos, fuente de energía y antena (data/science.json).
## Configuración en la pieza payload: p.probe = {"instruments": [ids], "power": id, "antenna": id}.
## evaluate() dice masa, costo, balance de energía en el destino, si la antena alcanza la Tierra
## y cuánta ciencia puede dar; science_earned() calcula la ciencia del vuelo.

const HOURS_YEAR := 8766.0

static var _d := {}


static func data() -> Dictionary:
	if _d.is_empty():
		_d = JSON.parse_string(FileAccess.get_file_as_string("res://data/science.json"))
	return _d


static func item(list: String, id: String) -> Dictionary:
	for it: Dictionary in data().get(list, []):
		if it.id == id:
			return it
	return {}


static func default_config(mission: int) -> Dictionary:
	var land := []
	for g: Dictionary in data().get("landing", []):
		if has_n(g.get("needed_for", []), mission):
			land.append(str(g.id))
	return {"instruments": ["thermo"] if mission <= 0 else ["camera"], "power": "battery" if mission <= 0 else "solar_small",
		"antenna": "whip" if mission <= 1 else ("patch" if mission <= 4 else "dish"), "landing": land,
		"computer": "obc_rad" if mission >= 7 else "obc_basic", "adcs": "spin" if mission <= 0 else "wheels",
		"ground": default_ground(mission), "orbit": "leo" if not orbits_for(mission).is_empty() else ""}


## Órbitas que se pueden elegir en esta misión (vacío si el destino es fijo).
static func orbits_for(mission: int) -> Array:
	return data().get("orbits", []).filter(func(o: Dictionary) -> bool: return has_n(o.get("missions", []), mission))


## ¿La lista del JSON tiene este número? (JSON da decimales: 4 in [4.0] es falso en GDScript)
static func has_n(arr: Array, n: int) -> bool:
	for x in arr:
		if int(x) == n:
			return true
	return false


## La red cercana llega hasta la Luna; más lejos hace falta la Red de Espacio Profundo.
static func default_ground(mission: int) -> String:
	return "nen" if float(destination(mission).get("link_km", 0.0)) <= 2000000.0 else "dsn"


static func destination(mission: int) -> Dictionary:
	return data().get("destinations", {}).get(str(maxi(mission, 0)), {})


static func evaluate(cfg: Dictionary, mission: int) -> Dictionary:
	var dest := destination(mission)
	var au := float(dest.get("au", 1.0))
	var dflt := default_config(mission)
	var r := {"mass": 0.0, "cost": 0.0, "need_w": 0.0, "have_w": 0.0, "power_ok": true, "link_ok": true,
		"data_mb": 0.0, "science_max": 0.0, "target": float(dest.get("target", 20.0)), "n_instruments": 0,
		"link_km": float(dest.get("link_km", 1000.0)), "range_km": 0.0, "battery_hours": 0.0}
	var zones: Dictionary = dest.get("zones", {})
	# Computador de a bordo y control de orientación
	var comp := item("computers", str(cfg.get("computer", dflt.computer)))
	var adcs := item("adcs", str(cfg.get("adcs", dflt.adcs)))
	var pointing := 1.0
	for part: Dictionary in [comp, adcs]:
		if part.is_empty():
			continue
		r.mass += float(part.mass)
		r.cost += float(part.cost_musd) * 1e6
		r.need_w += float(part.power_w)
	if not adcs.is_empty():
		pointing = float(adcs.pointing)
	r["pointing"] = pointing
	# Órbita elegida: Δv extra, sombra, caída por el aire y calidad de las observaciones
	var orb := {}
	if not orbits_for(mission).is_empty():
		orb = item("orbits", str(cfg.get("orbit", dflt.orbit)))
	r["orbit"] = str(orb.get("id", ""))
	r["dv_extra"] = float(orb.get("dv_extra", 0.0))
	# Fin de misión en órbita terrestre: guardar Δv para salir de órbita (o quedar como basura espacial)
	var deo: Dictionary = data().get("deorbit", {}).get("dv", {})
	r["eol_applies"] = deo.has(str(mission))
	r["deorbit"] = r.eol_applies and bool(cfg.get("deorbit", false))
	if r.deorbit:
		r.dv_extra += float(deo[str(mission)])
	var orb_mult := float(orb.get("sci_mult", 1.0))
	r["eclipse"] = float(orb.get("eclipse", 0.0))
	r["computer"] = str(comp.get("id", ""))
	r["adcs"] = str(adcs.get("id", ""))
	for id in cfg.get("instruments", []):
		var it := item("instruments", str(id))
		if it.is_empty():
			continue
		r.n_instruments += 1
		r.mass += float(it.mass)
		r.cost += float(it.cost_musd) * 1e6
		r.need_w += float(it.power_w)
		r.data_mb += float(it.data_mb)
		r.science_max += float(it.science) * _zone_mult(it, zones) * (pointing * orb_mult if it.get("needs_pointing", false) else 1.0)
	var ant := item("antennas", str(cfg.get("antenna", "whip")))
	if not ant.is_empty():
		r.mass += float(ant.mass)
		r.cost += float(ant.cost_musd) * 1e6
		r.need_w += float(ant.power_w)
		r.range_km = float(ant.range_km)
	# Estación de tierra: hasta dónde escucha, cuántas horas al día y cuánto cuesta por año
	var gs := item("ground", str(cfg.get("ground", dflt.ground)))
	r["ground"] = str(gs.get("id", ""))
	var rate := 0.0
	if not ant.is_empty() and not gs.is_empty():
		# Más lejos, la señal llega más débil y hay que transmitir más lento
		rate = float(ant.rate_mbps) * float(gs.gain) * minf(float(ant.get("ref_km", 1.0)) / maxf(r.link_km, 1.0), 1.0)
		if ant.get("needs_pointing", false) and pointing < 0.9:
			rate *= 0.25 # el plato no se queda apuntando a la Tierra
	r["downlink_mb"] = rate * float(gs.get("contact_h", 0.0)) * 3600.0 / 8.0
	r["ground_ok"] = float(gs.get("max_km", 0.0)) >= r.link_km
	r.link_ok = r.range_km >= r.link_km and r.ground_ok
	r["data_frac"] = 1.0 if r.data_mb <= 0.0 else clampf(r.downlink_mb / r.data_mb, 0.0, 1.0)
	var pw := item("power", str(cfg.get("power", "battery")))
	if not pw.is_empty():
		r.mass += float(pw.mass)
		r.cost += float(pw.cost_musd) * 1e6
		# Paneles: la luz cae con 1/d². RTG: igual en todas partes.
		r.have_w = float(pw.w_1au) if pw.get("rtg", false) else float(pw.w_1au) / (au * au)
		r.battery_hours = float(pw.battery_wh) / maxf(float(r.need_w), 1.0)
		r["power"] = str(pw.id)
	# Equipo de aterrizaje (patas, escudo térmico, paracaídas)
	r["gear"] = []
	for id in cfg.get("landing", []):
		var g := item("landing", str(id))
		if g.is_empty():
			continue
		r.mass += float(g.mass)
		r.cost += float(g.cost_musd) * 1e6
		r.gear.append(str(id))
	r["gear_missing"] = gear_missing(r.gear, mission)
	# Cápsula con tripulación: mucha más masa, costo y energía; los retos pasan a la cabina
	# Pruebas antes del lanzamiento: cuestan dinero y meses, bajan el riesgo en la operación
	r["tests"] = []
	var test_months := 0.0
	for id in cfg.get("tests", []):
		var tst := item("tests", str(id))
		if tst.is_empty():
			continue
		r.tests.append(str(id))
		r.cost += float(tst.cost_musd) * 1e6
		test_months += float(tst.months)
	r["crew"] = bool(cfg.get("crew", false))
	if r.crew:
		var cap: Dictionary = data().get("crew_capsule", {})
		r.mass += float(cap.get("mass", 5500.0))
		r.cost += float(cap.get("cost_musd", 40.0)) * 1e6
		r.need_w += float(cap.get("power_w", 60.0))
	var mission_h := float(dest.get("hours", 1.0))
	# Los paneles solo cargan al sol: en una órbita con sombra rinden menos en promedio
	if not pw.is_empty() and not pw.get("rtg", false):
		r.have_w *= 1.0 - float(orb.get("eclipse", 0.0))
	r.power_ok = r.have_w >= r.need_w or r.battery_hours >= mission_h
	# Vida útil: la radiación del destino desgasta el computador; sin energía suficiente, dura la batería
	var life := float(comp.get("life_h", 1e9)) / maxf(float(dest.get("rad", 1.0)), 0.1)
	if r.have_w < r.need_w:
		life = minf(life, r.battery_hours)
	life = minf(life, float(orb.get("decay_h", 1e9)))
	r["life_h"] = life
	r["mission_h"] = mission_h
	r["life_frac"] = clampf(life / maxf(mission_h, 0.01), 0.0, 1.0)
	r["life_ok"] = life >= mission_h
	r["storage_mb"] = float(comp.get("storage_mb", 0.0))
	# Operación: alquilar la estación de tierra durante toda la misión
	r["ops_cost"] = float(gs.get("cost_musd_year", 0.0)) * 1e6 * mission_h / HOURS_YEAR
	r.cost += r.ops_cost
	r["science_expected"] = float(r.science_max) * float(r.data_frac) * float(r.life_frac)
	# Tiempo de desarrollo (meses): base + instrumentos + piezas especiales + pruebas (CubeSat 101: 9 a 24 meses)
	var months := 6.0 + 2.0 * float(r.n_instruments) + test_months
	if str(r.get("computer", "")) == "obc_rad":
		months += 3.0
	if not (r.gear as Array).is_empty():
		months += 3.0
	if r.crew:
		months += 10.0
	r["dev_months"] = months
	return r


## Multiplicador de la mejor zona del destino donde el instrumento sirve (si no sirve en ninguna, 0,3).
static func _zone_mult(it: Dictionary, zones: Dictionary) -> float:
	var best := 0.0
	for z in it.get("best", []):
		best = maxf(best, float(zones.get(z, 0.0)))
	if best <= 0.0:
		var mx := 0.0
		for z in zones:
			mx = maxf(mx, float(zones[z]))
		best = mx * 0.3
	return best


## Ciencia que llega a la Tierra: llegar al destino (o una parte), con energía y con enlace.
static func science_earned(ev: Dictionary, success: bool, legs_reached: int, legs_total: int) -> float:
	if ev.is_empty() or int(ev.get("n_instruments", 0)) == 0:
		return 0.0
	var reach := 1.0 if success else (float(legs_reached) / float(legs_total) * 0.5 if legs_total > 0 else 0.0)
	var power := 1.0 if ev.power_ok else 0.3
	var link := 1.0 if ev.link_ok else 0.0 # sin enlace los datos nunca llegan
	return float(ev.science_max) * reach * power * link * float(ev.get("data_frac", 1.0)) * float(ev.get("life_frac", 1.0))


## Equipo de aterrizaje que la misión necesita y la sonda no lleva.
static func gear_missing(gear: Array, mission: int) -> Array:
	var out := []
	for g: Dictionary in data().get("landing", []):
		if has_n(g.get("needed_for", []), mission) and not str(g.id) in gear:
			out.append(str(g.id))
	return out
