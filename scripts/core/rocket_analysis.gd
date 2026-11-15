class_name RocketAnalysis
extends RefCounted
## Física del cohete calculada desde la geometría de sus piezas.
## El diseño es una lista de piezas de arriba hacia abajo. y = 0 en la punta, crece hacia abajo.
##
## - Área de la pared × espesor × densidad del material → masa de la estructura.
## - Volumen interior → propelente que cabe.
## - Ecuación del cohete (Tsiolkovsky) por etapa → Δv.
## - Centro de presión con Barrowman: teoría de cuerpo esbelto para el perfil
##   (puntas, adaptadores, piezas importadas) y la fórmula de aletas.

const G0 := 9.80665
const SOLID_BURN_S := 60.0
const TANK_FILL := 0.95
const SOLID_FILL := 0.85 # el grano sólido deja un canal central
const ENGINE_HOUSING := 0.35
const PAYLOAD_BASE_USD := 2000000.0 ## computadora, estructura y pruebas de la nave
const LAUNCH_BASE_USD := 5000000.0 ## operaciones de lanzamiento
const STAGE_USD := 3000000.0 ## integración y aviónica de cada etapa
const PAYLOAD_USD_PER_KG := 2000.0


# ---------- Geometría ----------

static func bell(engine_id: String) -> Dictionary:
	var e: Dictionary = Catalog.engines.get(engine_id, {})
	var kn := maxf(float(e.get("thrust_vac", 0.0)) / 1000.0, 0.0)
	var de := clampf(0.032 * sqrt(kn), 0.18, 3.0)
	return {"exit_d": de, "length": de * 1.6}


static func part_length(p: Dictionary) -> float:
	var t := Catalog.template(p.id)
	if t.get("kind") == "engine" and not t.has("profile"):
		return ENGINE_HOUSING + float(bell(p.get("engine", "")).length)
	return float(p.get("length", 1.0))


## Perfil (radio, y) local de la pieza, de arriba hacia abajo, en metros.
static func profile(p: Dictionary) -> PackedVector2Array:
	var t := Catalog.template(p.id)
	var length := part_length(p)
	var r := float(p.get("diameter", 1.0)) / 2.0
	var out := PackedVector2Array()
	if t.has("profile"):
		for pt in t.profile:
			out.append(Vector2(float(pt[0]) * r, float(pt[1]) * length))
		return out
	match t.get("kind"):
		"nose":
			if t.get("shape") == "cone":
				out.append_array([Vector2(0, 0), Vector2(r, length)])
			else:
				for i in 13:
					var y := length * i / 12.0
					out.append(Vector2(r * sqrt(maxf(0.0, 1.0 - pow(1.0 - y / length, 2.0))), y))
		"adapter":
			out.append_array([Vector2(float(p.get("diameter_top", 0.6)) / 2.0, 0), Vector2(r, length)])
		"engine":
			out.append_array([Vector2(r, 0), Vector2(r, ENGINE_HOUSING)])
		_:
			out.append_array([Vector2(r, 0), Vector2(r, length)])
	return out


## Área lateral, volumen y sus centroides (medidos desde arriba de la pieza).
static func integrate(prof: PackedVector2Array) -> Dictionary:
	var area := 0.0
	var area_m := 0.0
	var vol := 0.0
	var vol_m := 0.0
	for i in range(1, prof.size()):
		var r1 := prof[i - 1].x
		var r2 := prof[i].x
		var y1 := prof[i - 1].y
		var h := prof[i].y - y1
		if h <= 0.0:
			continue
		var slant := sqrt(h * h + (r2 - r1) * (r2 - r1))
		var a := PI * (r1 + r2) * slant
		var ay := y1 + (h * (r1 + 2.0 * r2) / (3.0 * (r1 + r2)) if r1 + r2 > 0.0 else h / 2.0)
		area += a
		area_m += a * ay
		var k := r1 * r1 + r1 * r2 + r2 * r2
		var v := PI * h * k / 3.0
		var vy := y1 + (h * (r1 * r1 + 2.0 * r1 * r2 + 3.0 * r2 * r2) / (4.0 * k) if k > 0.0 else h / 2.0)
		vol += v
		vol_m += v * vy
	return {"area": area, "area_cy": area_m / area if area > 0.0 else 0.0,
		"volume": vol, "vol_cy": vol_m / vol if vol > 0.0 else 0.0}


# ---------- Análisis completo ----------

static func analyze(design: Array, level: int, sandbox: bool) -> Dictionary:
	var probe_ev := {}
	Catalog.load_all()
	var parts := []
	var warnings := []
	var y := 0.0
	var max_d := 0.0
	var min_strength := 10.0 # material más débil: define cuánta carga aguanta la estructura
	for i in design.size():
		var p: Dictionary = design[i]
		var t := Catalog.template(p.id)
		if t.is_empty():
			continue
		var kind: String = t.kind
		var length := part_length(p)
		var prof := profile(p)
		var g := integrate(prof)
		var mat: Dictionary = Catalog.materials.get(p.get("material", "aluminium"), Catalog.materials["aluminium"])
		var wall := float(t.get("wall_m", 0.004)) / float(mat.strength)
		min_strength = minf(min_strength, float(mat.strength))
		var shell := float(g.area) * wall * float(mat.density_kg_m3)
		var info := {
			"index": i, "kind": kind, "y": y, "length": length, "diameter": float(p.get("diameter", 1.0)),
			"dry": shell, "dry_moment": shell * (y + float(g.area_cy)), "prop": 0.0, "prop_moment": 0.0,
			"prop_type": "", "cost": shell * float(mat.cost_usd_per_kg), "volume": float(g.volume),
			"engines": [], "fins_mass": 0.0,
		}
		max_d = maxf(max_d, info.diameter)
		match kind:
			"tank":
				var pt: String = p.get("propellant", "lox_rp1")
				var pr: Dictionary = Catalog.propellants.get(pt, {})
				info.prop_type = pt
				info.prop = float(g.volume) * TANK_FILL * float(pr.get("bulk_density_kg_m3", 1000.0))
				info.prop_moment = info.prop * (y + float(g.vol_cy))
				info.cost += info.prop * float(pr.get("cost_usd_per_kg", 0.0))
			"solid":
				var pr: Dictionary = Catalog.propellants["solid"]
				var e: Dictionary = Catalog.engines.get(p.get("engine", "solid_basic"), {})
				info.prop_type = "solid"
				info.prop = float(g.volume) * SOLID_FILL * float(pr.bulk_density_kg_m3)
				info.prop_moment = info.prop * (y + float(g.vol_cy))
				info.cost += info.prop * float(pr.cost_usd_per_kg)
				var isp_sl := float(e.get("isp_sl", 250.0))
				var isp_vac := float(e.get("isp_vac", 270.0))
				# Empuje que vacía el grano en SOLID_BURN_S segundos
				info.engines.append({"prop_type": "solid", "isp_sl": isp_sl, "isp_vac": isp_vac,
					"thrust_sl": info.prop * G0 * isp_sl / SOLID_BURN_S,
					"thrust_vac": info.prop * G0 * isp_vac / SOLID_BURN_S, "own_prop": info.prop})
			"engine":
				var e: Dictionary = Catalog.engines.get(p.get("engine", ""), {})
				var n := int(p.get("count", 1))
				var em := float(e.get("dry_mass", 0.0) if e.get("dry_mass") != null else 0.0) * n
				info.dry += em
				info.dry_moment += em * (y + length * 0.6)
				info.cost += float(e.get("cost_musd", 0.0) if e.get("cost_musd") != null else 0.0) * 1e6 * n
				info.engines.append({"prop_type": e.get("propellant", ""), "isp_sl": float(e.get("isp_sl", 0.0)),
					"isp_vac": float(e.get("isp_vac", 0.0)), "thrust_sl": float(e.get("thrust_sl", 0.0)) * n,
					"thrust_vac": float(e.get("thrust_vac", 0.0)) * n, "own_prop": 0.0})
			"payload":
				var pk := float(p.get("payload_kg", 0.0)) + float(Catalog.fixed.get("payload_bay_avionics", 20.0))
				info.dry += pk
				info.dry_moment += pk * (y + length / 2.0)
				# La nave: cuesta por kilo según el destino (un satélite en órbita baja es más barato por kilo
				# que un rover para Marte o una sonda para los planetas exteriores)
				var pay_cost := PAYLOAD_BASE_USD + float(p.get("payload_kg", 0.0)) * float(Probe.destination(level).get("usd_per_kg", 5000.0))
				info.cost += pay_cost
				info["payload_cost"] = pay_cost
				info["payload_kg"] = float(p.get("payload_kg", 0.0))
				# Sonda: instrumentos, energía y antena (su masa y su costo se suman a la carga)
				if not probe_ev.has("mass"):
					probe_ev = Probe.evaluate(p.get("probe", Probe.default_config(level)), level)
					info.dry += float(probe_ev.mass)
					info.dry_moment += float(probe_ev.mass) * (y + length / 2.0)
					info.cost += float(probe_ev.cost)
					info["payload_cost"] = float(info.get("payload_cost", 0.0)) + float(probe_ev.cost)
			"decoupler":
				var dm: float = float(Catalog.fixed.get("decoupler_per_m_diameter", 60.0)) * info.diameter
				info.dry += dm
				info.dry_moment += dm * (y + length / 2.0)
		# Aletas pegadas a esta pieza
		var f: Dictionary = p.get("fins", {})
		if int(f.get("count", 0)) > 0:
			var root := float(f.get("root", 0.5))
			var tip := float(f.get("tip", 0.3))
			var span := float(f.get("span", 0.3))
			var off := float(f.get("offset", 0.0))
			var fm: float = (root + tip) / 2.0 * span * int(f.count) * float(Catalog.fins_spec.get("thickness_m", 0.008)) * float(mat.density_kg_m3)
			info.fins_mass = fm
			info.dry += fm
			info.dry_moment += fm * (y + length - off - root / 2.0)
			info.cost += fm * float(mat.cost_usd_per_kg)
		info["profile_global"] = _offset(prof, y)
		parts.append(info)
		y += length

	var res := {"parts": parts, "height": y, "max_d": max_d, "warnings": warnings, "min_strength": min_strength}
	if parts.is_empty():
		res.merge({"stages": [], "dv_total": 0.0, "cost": 0.0, "mass": 0.0, "cm": 0.0, "cp": 0.0,
			"stability": 0.0, "d_ref": 0.0, "twr": 0.0}, true)
		warnings.append({"key": "W_EMPTY", "args": [], "level": "bad"})
		return res

	# ---- Etapas: los separadores parten el cohete; el separador cae con la etapa de abajo ----
	var groups := [[]]
	for info in parts:
		if info.kind == "decoupler" and not groups[-1].is_empty():
			groups.append([])
		groups[-1].append(info)
	var n := groups.size()
	var stages := []
	var above := 0.0
	var mass_total := 0.0
	for gi in n:
		var gdry := 0.0
		var gprop := 0.0
		for info in groups[gi]:
			gdry += float(info.dry)
			gprop += float(info.prop)
		var stage_no := n - gi # la de más abajo se enciende primero
		var first := stage_no == 1
		# Motores y el propelente que pueden quemar
		var engines := []
		var liquid_types := {}
		for info in groups[gi]:
			for e in info.engines:
				engines.append(e)
				if e.prop_type != "solid":
					liquid_types[e.prop_type] = true
		var burnable := 0.0
		for info in groups[gi]:
			if info.kind == "solid":
				burnable += float(info.prop)
			elif info.kind == "tank":
				if liquid_types.has(info.prop_type):
					burnable += float(info.prop)
				else:
					warnings.append({"key": "W_PROP_MISMATCH", "args": [stage_no, Catalog.propellants.get(info.prop_type, {}).get("label", info.prop_type)], "level": "warn"})
		var f_sum := 0.0
		var flow := 0.0 # suma de F / (Isp·g0) = gasto másico
		var f_sl := 0.0
		var vac_at_sl := false
		# Para el simulador de vuelo: empuje a nivel del mar y en vacío, y gasto másico (constante)
		var sim_sl := 0.0
		var sim_vac := 0.0
		var sim_mdot := 0.0
		for e in engines:
			var liquid_fed: bool = e.prop_type == "solid" or burnable > 0.0
			if not liquid_fed:
				continue
			if float(e.isp_vac) > 0.0:
				sim_sl += float(e.thrust_sl)
				sim_vac += float(e.thrust_vac)
				sim_mdot += float(e.thrust_vac) / (float(e.isp_vac) * G0)
			var isp := float(e.isp_vac)
			var thrust := float(e.thrust_vac)
			if first:
				if float(e.isp_sl) > 0.0:
					isp = (float(e.isp_sl) + float(e.isp_vac)) / 2.0
					thrust = (float(e.thrust_sl) + float(e.thrust_vac)) / 2.0
				else:
					isp = float(e.isp_vac) * 0.5
					vac_at_sl = true
				f_sl += float(e.thrust_sl)
			if isp > 0.0 and thrust > 0.0:
				f_sum += thrust
				flow += thrust / (isp * G0)
		var m0 := above + gdry + gprop
		var mf := m0 - burnable
		var isp_eff := f_sum / (flow * G0) if flow > 0.0 else 0.0
		var dv := isp_eff * G0 * log(m0 / mf) if (burnable > 0.0 and mf > 0.0 and isp_eff > 0.0) else 0.0
		var thrust_ref := f_sl if first else f_sum
		var twr := thrust_ref / (m0 * G0) if m0 > 0.0 else 0.0
		stages.append({"number": stage_no, "m0": m0, "mf": mf, "dry": gdry, "prop": gprop, "burnable": burnable,
			"dv": dv, "twr": twr, "isp": isp_eff, "thrust": thrust_ref, "burn_s": burnable / flow if flow > 0.0 else 0.0,
			"has_engine": not engines.is_empty(), "f_sl": sim_sl, "f_vac": sim_vac, "mdot": sim_mdot, "top": groups[gi][0].index, "bottom": groups[gi][-1].index})
		if vac_at_sl:
			warnings.append({"key": "W_VAC_ENGINE", "args": [], "level": "warn"})
		if gprop > 0.0 and engines.is_empty():
			warnings.append({"key": "W_NO_ENGINE", "args": [stage_no], "level": "bad"})
		elif not engines.is_empty() and burnable <= 0.0:
			warnings.append({"key": "W_NO_FUEL", "args": [stage_no], "level": "bad"})
		above = m0
		mass_total = m0
	# Aceleración máxima estimada: empuje en vacío / masa al agotar el propelente de la etapa
	var max_g := 0.0
	for st in stages:
		var mfin := float(st.mf)
		if float(st.f_vac) > 0.0 and mfin > 0.0:
			max_g = maxf(max_g, float(st.f_vac) / mfin / G0)
	res["max_g_est"] = max_g
	stages.reverse() # etapa 1 primero

	var dv_total := 0.0
	for s in stages:
		dv_total += float(s.dv)
	var cost := 0.0
	var cost_payload := 0.0
	var moment := 0.0
	for info in parts:
		cost += float(info.cost)
		cost_payload += float(info.get("payload_cost", 0.0))
		moment += float(info.dry_moment) + float(info.prop_moment)

	# ---- Centro de presión (Barrowman) ----
	var d_ref := float(parts[0].diameter)
	var a_ref := PI * d_ref * d_ref / 4.0
	var cn := 0.0
	var cn_x := 0.0
	var body := PackedVector2Array()
	for info in parts:
		body.append_array(info.profile_global)
	for i in range(1, body.size()):
		var a1 := PI * body[i - 1].x * body[i - 1].x
		var a2 := PI * body[i].x * body[i].x
		if absf(a2 - a1) < 1e-6 or body[i].y <= body[i - 1].y:
			continue
		var y1 := body[i - 1].y
		var y2 := body[i].y
		var h := y2 - y1
		var r1 := body[i - 1].x
		var r2 := body[i].x
		var v := PI * h * (r1 * r1 + r1 * r2 + r2 * r2) / 3.0
		var c := 2.0 * (a2 - a1) / a_ref
		var x := (y2 * a2 - y1 * a1 - v) / (a2 - a1) # teoría de cuerpo esbelto
		cn += c
		cn_x += c * x
	for info in parts:
		var p: Dictionary = design[info.index]
		var f: Dictionary = p.get("fins", {})
		var nf := int(f.get("count", 0))
		if nf <= 0:
			continue
		var cr := float(f.get("root", 0.5))
		var ct := float(f.get("tip", 0.3))
		var s := float(f.get("span", 0.3))
		var rb := float(info.diameter) / 2.0
		var xt := cr - ct # borde de ataque inclinado, borde de salida recto
		var lm := sqrt(s * s + pow(xt + ct / 2.0 - cr / 2.0, 2.0))
		var c := (1.0 + rb / (s + rb)) * (4.0 * nf * pow(s / d_ref, 2.0)) / (1.0 + sqrt(1.0 + pow(2.0 * lm / (cr + ct), 2.0)))
		var xb := float(info.y) + float(info.length) - float(f.get("offset", 0.0)) - cr
		var x := xb + xt * (cr + 2.0 * ct) / (3.0 * (cr + ct)) + (cr + ct - cr * ct / (cr + ct)) / 6.0
		cn += c
		cn_x += c * x

	var cm := moment / mass_total if mass_total > 0.0 else 0.0
	var cp := cn_x / cn if cn > 0.0 else 0.0
	var stability := (cp - cm) / d_ref if cn > 0.0 else -99.0
	# ---- Aerodinámica: coeficiente de arrastre (Cd) subsónico, por partes ----
	# Punta: más larga y afilada (L/D alto) = menos arrastre de presión; sin punta, un frente plano (~0,8).
	# Cuerpo: fricción de la piel, crece con lo largo y delgado del cohete.
	# Base: la "succión" detrás del culo del cohete. Aletas: fricción y su borde.
	# En el vuelo se multiplica por el efecto de la barrera del sonido (pico cerca de Mach 1).
	var a_drag := PI * max_d * max_d / 4.0
	var cd_nose := 0.8
	if parts[0].kind == "nose":
		var fin_r := float(parts[0].length) / maxf(float(parts[0].diameter), 0.05)
		cd_nose = clampf(0.5 / (1.0 + 1.2 * fin_r), 0.05, 0.5)
		if str(design[0].id).contains("ogive"):
			cd_nose *= 0.8 # la ojiva curva desvía el aire con más suavidad que el cono
	var cd_body := clampf(0.006 * float(res.height) / maxf(max_d, 0.05), 0.02, 0.2)
	var cd_base := 0.12
	var cd_fins := 0.0
	for info in parts:
		var f: Dictionary = design[info.index].get("fins", {})
		var nf := int(f.get("count", 0))
		if nf > 0:
			var fin_area := float(f.get("span", 0.3)) * (float(f.get("root", 0.5)) + float(f.get("tip", 0.3))) / 2.0
			cd_fins += nf * (fin_area * 0.016 + float(f.get("span", 0.3)) * 0.01 * 0.5) / maxf(a_drag, 0.01)
	cd_fins = minf(cd_fins, 0.3)
	res["cd"] = cd_nose + cd_body + cd_base + cd_fins
	res["cd_parts"] = {"nose": cd_nose, "body": cd_body, "base": cd_base, "fins": cd_fins}
	res["area_ref"] = a_drag

	if not parts.is_empty():
		cost += LAUNCH_BASE_USD + STAGE_USD * stages.size()
	res["cost_payload"] = cost_payload
	res["cost_rocket"] = cost - cost_payload
	res.merge({"stages": stages, "dv_total": dv_total, "cost": cost, "mass": mass_total, "cm": cm, "cp": cp,
		"stability": stability, "d_ref": d_ref, "twr": float(stages[0].twr) if not stages.is_empty() else 0.0}, true)

	# ---- Avisos (lo que el juego explica) ----
	var lvl := Game.level(level) if level >= 0 else {}
	var dv_req: Variant = lvl.get("dv_km_s")
	var budget: Variant = lvl.get("budget_musd")
	res["dv_required"] = float(dv_req) * 1000.0 if dv_req != null else 0.0 # en el taller libre, la misión elegida
	res["budget"] = float(budget) * 1e6 if budget != null and not sandbox else 0.0
	if res.dv_required > 0.0:
		res.dv_required += float(probe_ev.get("dv_extra", 0.0)) # la órbita elegida puede pedir más Δv
	if parts[0].kind != "nose":
		warnings.append({"key": "W_NO_NOSE", "args": [], "level": "warn"})
	var has_payload := false
	for info in parts:
		if info.kind == "payload":
			has_payload = true
	if not has_payload:
		warnings.append({"key": "W_NO_PAYLOAD", "args": [], "level": "warn"})
	res["probe"] = probe_ev
	var pay_mass := float(probe_ev.get("mass", 0.0))
	for info in parts:
		if info.kind == "payload":
			pay_mass += float(info.get("payload_kg", 0.0))
	res["payload_mass"] = pay_mass
	res["payload_min"] = float(Probe.destination(level).get("payload_min_kg", 0.0)) if level >= 0 else 0.0
	res["payload_short"] = has_payload and pay_mass < float(res.payload_min)
	if res.payload_short:
		warnings.append({"key": "W_PAYLOAD_MIN", "args": [int(pay_mass), int(res.payload_min)], "level": "bad"})
	if has_payload and not probe_ev.is_empty():
		if int(probe_ev.n_instruments) == 0:
			warnings.append({"key": "W_NO_INSTR", "args": [], "level": "warn"})
		if not bool(probe_ev.power_ok):
			warnings.append({"key": "W_POWER", "args": [int(probe_ev.have_w), int(probe_ev.need_w)], "level": "warn"})
		if not bool(probe_ev.link_ok):
			warnings.append({"key": "W_LINK", "args": [], "level": "bad"})
		elif float(probe_ev.get("data_frac", 1.0)) < 0.999:
			warnings.append({"key": "W_DATA", "args": [int(round(float(probe_ev.data_frac) * 100.0))], "level": "warn"})
		if not bool(probe_ev.get("life_ok", true)) and bool(probe_ev.power_ok):
			warnings.append({"key": "W_LIFE", "args": [int(round(float(probe_ev.life_frac) * 100.0))], "level": "warn"})
		if not (probe_ev.get("gear_missing", []) as Array).is_empty():
			warnings.append({"key": "W_GEAR", "args": [], "level": "bad"})
	if max_g > FlightSim.G_LIMIT * clampf(min_strength, 0.3, 3.0):
		warnings.append({"key": "W_G_LIMIT", "args": [int(round(max_g))], "level": "bad"})
	var twr1 := float(res.twr)
	if twr1 < 1.0:
		warnings.append({"key": "W_TWR_LOW", "args": [twr1], "level": "bad"})
	elif twr1 < 1.2:
		warnings.append({"key": "W_TWR_MARGINAL", "args": [twr1], "level": "warn"})
	# Los motores líquidos de la etapa 1 pueden inclinarse (gimbal) y corregir el rumbo,
	# como Falcon 9 o Electron, que no tienen aletas estabilizadoras. Un motor sólido no.
	var gimbal := false
	if not stages.is_empty():
		for i in range(int(stages[0].top), int(stages[0].bottom) + 1):
			if parts[i].kind == "engine":
				gimbal = true
	res["gimbal"] = gimbal
	if cn <= 0.0 or stability < 0.0:
		warnings.append({"key": "W_UNSTABLE_GIMBAL" if gimbal else "W_UNSTABLE", "args": [], "level": "warn" if gimbal else "bad"})
	elif stability < 1.0:
		warnings.append({"key": "W_STAB_LOW", "args": [stability], "level": "warn"})
	elif stability > 4.0:
		warnings.append({"key": "W_STAB_HIGH", "args": [stability], "level": "warn"})
	if res.budget > 0.0 and cost > res.budget:
		warnings.append({"key": "W_BUDGET", "args": [(cost - res.budget) / 1e6], "level": "bad"})
	if res.dv_required > 0.0:
		if dv_total < res.dv_required:
			warnings.append({"key": "W_DV_SHORT", "args": [(res.dv_required - dv_total) / 1000.0], "level": "bad"})
		else:
			warnings.append({"key": "W_DV_OK", "args": [], "level": "ok"})
	return res


## Listo para lanzar: sin avisos graves.
static func ready_to_fly(res: Dictionary) -> bool:
	for w in res.get("warnings", []):
		if w.level == "bad":
			return false
	return true


static func _offset(prof: PackedVector2Array, y: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in prof:
		out.append(Vector2(p.x, p.y + y))
	return out
