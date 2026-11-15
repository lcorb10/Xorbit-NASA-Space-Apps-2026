class_name Solver
extends RefCounted
## Busca un cohete que cumpla cada misión (para el botón "Me rindo"). Se corre una vez con
## godot --headless --path . -- --solve y guarda data/solutions.json; el juego solo lee ese archivo.
## Plantilla: punta ojival, bahía de carga con la sonda, etapas de arriba de hidrógeno (RL10 o J-2)
## y primera etapa de queroseno (Merlin, sin aletas: los motores se inclinan). Se prueban largos y
## diámetros, se calcula cuántos motores necesita la primera etapa para TWR 1,3, y se quedan los que
## alcanzan el Δv con 3 % de margen, entran en el presupuesto y vuelan bien en FlightSim.

const PROBES := {
	0: {"instruments": ["thermo"], "power": "battery", "antenna": "whip"},
	1: {"instruments": ["camera"], "power": "solar_small", "antenna": "whip"},
	2: {"instruments": ["camera", "magnetometer"], "power": "solar_big", "antenna": "patch"},
	3: {"instruments": ["camera", "spectrometer"], "power": "solar_small", "antenna": "patch"},
	4: {"instruments": ["camera", "spectrometer", "drill"], "power": "solar_big", "antenna": "patch", "landing": ["legs"]},
	5: {"instruments": ["camera", "spectrometer", "radar"], "power": "solar_big", "antenna": "dish"},
	6: {"instruments": ["camera", "spectrometer", "drill"], "power": "solar_big", "antenna": "dish", "landing": ["heat_shield", "parachute"]},
	7: {"instruments": ["camera", "spectrometer", "magnetometer"], "power": "rtg", "antenna": "dish"},
	8: {"instruments": ["magnetometer", "camera", "spectrometer"], "power": "rtg", "antenna": "dish"},
}


static var ignore_budget := false


## Material de las etapas de arriba según lo desbloqueado: fibra de carbono (la más liviana) desde la
## misión 5, aluminio-litio desde la 3. La primera etapa usa aluminio (barato: ahí el peso importa menos).
static func upper_materials(m: int) -> Array:
	if m >= 5:
		return ["carbon", "al_li"]
	if m >= 3:
		return ["al_li", "aluminium"]
	return ["aluminium"]


static func design(m: int, d: float, uppers: Array, l1: float, n1: int, e1: String, mat_up := "aluminium") -> Array:
	var probe: Dictionary = PROBES.get(m, PROBES[1]).duplicate(true)
	var pmass := float(Probe.evaluate(probe, m).mass)
	var need := float(Probe.destination(m).get("payload_min_kg", 0.0))
	var out := [
		{"id": "nose_ogive", "length": snappedf(d * 1.6, 0.1), "diameter": d, "material": "carbon" if m >= 5 else "aluminium", "paint": "white"},
		{"id": "payload_bay", "length": snappedf(maxf(d * 0.9, 3.0 if not (probe.get("landing", []) as Array).is_empty() else 0.0), 0.1), "diameter": d, "material": "aluminium", "payload_kg": snappedf(maxf(need - pmass, 0.0) + 1.0, 1.0), "paint": "white", "probe": probe},
	]
	for u: Dictionary in uppers:
		out.append({"id": "tank", "length": u.l, "diameter": d, "material": mat_up, "propellant": u.prop, "paint": "silver"})
		out.append({"id": "engine", "diameter": d, "engine": u.eng, "count": u.n})
		out.append({"id": "decoupler", "length": 0.6, "diameter": d, "material": "aluminium", "paint": "white"})
	out.append({"id": "tank", "length": l1, "diameter": d, "material": "aluminium", "propellant": "lox_rp1", "paint": "white"})
	out.append({"id": "engine", "diameter": d, "engine": e1, "count": n1})
	return out


static func solve_all() -> Dictionary:
	Catalog.load_all()
	var out := {}
	for lv: Dictionary in Game.levels:
		var m := int(lv.id)
		if lv.get("dv_km_s") == null:
			continue
		var best := solve(m)
		if not best.is_empty():
			out[str(m)] = best
			print("SOLVE %d: costo %.1f M de %s, Δv %.2f de %.1f, sim %s, ciencia %d/%d" % [m, best.cost / 1e6, str(lv.budget_musd), best.dv / 1000.0, float(lv.dv_km_s), best.reason, int(best.science), int(best.target)])
		else:
			print("SOLVE %d: sin solución" % m)
	var f := FileAccess.open("res://data/solutions.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"_notes": "Generado por Solver (godot --headless --path . -- --solve). Un cohete verificado por misión para el botón 'Me rindo'.", "solutions": out}, "  "))
	return out


static func solve(m: int) -> Dictionary:
	var lv := Game.level(m)
	var need := float(lv.dv_km_s) * 1000.0
	var budget := float(lv.budget_musd) * 1e6
	var cands := []
	if m == 0:
		# Cohete sonda: motor sólido con aletas
		for l in [3.0, 4.0, 5.0, 6.0]:
			var d0 := [{"id": "nose_ogive", "length": 1.6, "diameter": 0.6, "material": "aluminium"},
				{"id": "payload_bay", "length": 0.6, "diameter": 0.6, "material": "aluminium", "payload_kg": 45, "probe": PROBES[0].duplicate(true)},
				{"id": "solid_motor", "length": l, "diameter": 0.6, "material": "steel", "fins": {"count": 4, "span": 0.45, "root": 0.8, "tip": 0.35}}]
			cands.append(d0)
	else:
		var upper_opts := []
		var hyd_eng := "rl10c" if m < 3 else "j2"
		for ls in [3.0, 5.0, 7.0, 9.0, 12.0]:
			for k in ([1, 2] if hyd_eng == "rl10c" else [1]):
				if m <= 1:
					upper_opts.append([{"l": ls, "prop": "lox_rp1", "eng": "merlin_1d", "n": 1}]) # el Merlin de vacío se desbloquea en la misión 2
				else:
					upper_opts.append([{"l": ls, "prop": "lox_lh2", "eng": hyd_eng, "n": k}])
					if m >= 3:
						for ls2 in [8.0, 12.0, 16.0]:
							upper_opts.append([{"l": ls, "prop": "lox_lh2", "eng": hyd_eng, "n": k}, {"l": ls2, "prop": "lox_lh2", "eng": "j2", "n": 2}])
					if m >= 7:
						for ls2 in [10.0, 16.0]:
							for ls3 in [16.0, 24.0]:
								upper_opts.append([{"l": ls, "prop": "lox_lh2", "eng": "rl10c", "n": 1}, {"l": ls2, "prop": "lox_lh2", "eng": "j2", "n": 1}, {"l": ls3, "prop": "lox_lh2", "eng": "j2", "n": 5}])
		var firsts := ["merlin_1d"]
		if m >= 2:
			firsts.append("rd180")
		if m >= 3:
			firsts.append("f1")
		for d in ([2.4, 3.0, 3.7] if m <= 2 else ([3.7, 5.0, 6.6] if m < 8 else [5.0, 6.6, 8.4, 10.1])):
			for up in upper_opts:
				for l1 in [12.0, 16.0, 20.0, 25.0, 30.0, 36.0, 44.0]:
					for e1 in firsts:
						for mu in upper_materials(m):
							cands.append(design(m, d, up, l1, 1, e1, mu))
	var ok := []
	for dz: Array in cands:
		var a := RocketAnalysis.analyze(dz, m, false)
		if m > 0:
			# Motores de la primera etapa para TWR ~1,35
			var st0: Dictionary = a.stages[0]
			var per := float(st0.f_sl) / maxf(float(dz[dz.size() - 1].count), 1.0)
			var n1 := clampi(int(ceil(1.35 * float(st0.m0) * FlightSim.G0 / maxf(per, 1.0))), 1, 9)
			dz[dz.size() - 1].count = n1
			a = RocketAnalysis.analyze(dz, m, false)
		if float(a.dv_total) < need * 1.03 or (float(a.cost) > budget * 0.97 and not ignore_budget) or float(a.twr) < 1.2 or (float(a.twr) > 2.2 and m > 0):
			continue
		var ws := []
		for w in a.warnings:
			ws.append(w.key)
		if "W_POWER" in ws or "W_LINK" in ws or "W_G_LIMIT" in ws or "W_GEAR" in ws or "W_PAYLOAD_MIN" in ws:
			continue
		ok.append([float(a.cost), dz, a])
	ok.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	for c in ok.slice(0, 12):
		var a: Dictionary = c[2]
		var f := FlightSim.simulate(a, m, false)
		var legs := (lv.get("legs", []) as Array).size()
		var sci := Probe.science_earned(a.get("probe", {}), bool(f.success), legs, legs)
		if f.success:
			return {"design": c[1], "cost": c[0], "dv": float(a.dv_total), "reason": str(f.reason), "science": sci, "target": float(a.probe.get("target", 0.0))}
	return {}
