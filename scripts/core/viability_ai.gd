class_name ViabilityAI
extends RefCounted
## "IA de viabilidad" de XORBIT: analiza el cohete completo y dice qué tan probable es que cumpla
## la misión, y por qué. No es un modelo de lenguaje: es un modelo estadístico (Monte Carlo).
## 1. Vuela el cohete N veces con FlightSim, cada vez con pequeñas variaciones como las reales:
##    empuje ±3 %, eficiencia del motor (Isp) ±1 %, arrastre ±12 %, resistencia del material ±7 %.
## 2. Viabilidad = vuelos que cumplen la misión / N.
## 3. Puntaje 0-100 por área (Δv, empuje/peso, estabilidad, estructura, aerodinámica, costo, carga),
##    cada uno con su explicación, y la causa de falla más común.

const RUNS := 50


## Una versión perturbada del análisis (no toca el original).
static func perturb(analysis: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var a := analysis.duplicate(true)
	var k_thrust := rng.randfn(1.0, 0.03)
	var k_isp := rng.randfn(1.0, 0.01)
	for st: Dictionary in a.get("stages", []):
		st.f_sl = float(st.f_sl) * k_thrust * k_isp
		st.f_vac = float(st.f_vac) * k_thrust * k_isp
		st.mdot = float(st.mdot) * k_thrust
	a.cd = float(a.get("cd", 0.45)) * clampf(rng.randfn(1.0, 0.12), 0.6, 1.5)
	a.min_strength = float(a.get("min_strength", 1.0)) * clampf(rng.randfn(1.0, 0.07), 0.7, 1.3)
	return a


## Una corrida: {ok, reason, progress, max_q, max_g, apogee}.
static func run_one(analysis: Dictionary, mission: int, sandbox: bool, rng: RandomNumberGenerator) -> Dictionary:
	var f := FlightSim.simulate(perturb(analysis, rng), mission, sandbox)
	var ok := bool(f.success) and (analysis.get("probe", {}).get("gear_missing", []) as Array).is_empty()
	if mission < 0:
		ok = f.reason in ["OK_ORBIT", "OK_SPACE"] or (f.reason == "FAIL_SUBORBITAL" and float(f.apogee) >= 100000.0)
	return {"ok": ok, "reason": str(f.reason), "progress": float(f.progress), "max_q": float(f.max_q),
		"max_g": float(f.max_g), "apogee": float(f.apogee)}


## Informe final a partir de las corridas.
static func report(runs: Array, analysis: Dictionary, design: Array) -> Dictionary:
	var n := maxi(runs.size(), 1)
	var ok := 0
	var reasons := {}
	var max_q := 0.0
	var max_g := 0.0
	for r: Dictionary in runs:
		if r.ok:
			ok += 1
		else:
			reasons[r.reason] = int(reasons.get(r.reason, 0)) + 1
		max_q = maxf(max_q, float(r.max_q))
		max_g = maxf(max_g, float(r.max_g))
	var worst := ""
	var worst_n := 0
	for k in reasons:
		if int(reasons[k]) > worst_n:
			worst = k
			worst_n = int(reasons[k])
	var scores := []
	var tr := func(k: String) -> String: return TranslationServer.translate(k)
	# Δv: margen sobre lo que pide la misión (10 % de margen = 100)
	var need := float(analysis.get("dv_required", 0.0))
	var have := float(analysis.get("dv_total", 0.0))
	if need > 0.0:
		var margin := (have - need) / need
		scores.append(_s("AI_DV", clampf(50.0 + margin * 500.0, 0.0, 100.0), tr.call("AI_DV_WHY") % [Game.fmt(have / 1000.0, 2), Game.fmt(need / 1000.0, 1), Game.fmt(margin * 100.0, 0)]))
	# Empuje/peso de la etapa 1: ideal 1,3-1,6
	var twr := float(analysis.get("twr", 0.0))
	var s_twr := 0.0
	if twr >= 1.3 and twr <= 1.8:
		s_twr = 100.0
	elif twr < 1.3:
		s_twr = clampf((twr - 1.0) / 0.3 * 100.0, 0.0, 100.0)
	else:
		s_twr = clampf(100.0 - (twr - 1.8) * 40.0, 30.0, 100.0)
	scores.append(_s("AI_TWR", s_twr, tr.call("AI_TWR_WHY") % Game.fmt(twr, 2)))
	# Estabilidad: 1-2 calibres ideal; gimbal la compensa
	var stab := float(analysis.get("stability", 0.0))
	var gimbal := bool(analysis.get("gimbal", false))
	var s_stab := clampf(stab / 1.0 * 100.0, 0.0, 100.0) if not gimbal else maxf(85.0, clampf(stab * 100.0, 0.0, 100.0))
	if stab > 3.0 and not gimbal:
		s_stab = 80.0 # demasiado estable: gira contra el viento y se desvía
	scores.append(_s("AI_STAB", s_stab, tr.call("AI_STAB_WHY_G" if gimbal else "AI_STAB_WHY") % Game.fmt(stab, 2)))
	# Estructura: el peor caso de presión del aire y aceleración contra lo que aguanta
	var strength := float(analysis.get("min_strength", 1.0))
	var q_use := max_q / (FlightSim.Q_LIMIT * strength)
	var g_use := max_g / (FlightSim.G_LIMIT * strength)
	var use := maxf(q_use, g_use)
	scores.append(_s("AI_STRUCT", clampf((1.0 - use) / 0.5 * 100.0, 0.0, 100.0), tr.call("AI_STRUCT_WHY") % [Game.fmt(max_q / 1000.0, 0), Game.fmt(max_g, 1), int(use * 100.0)]))
	# Aerodinámica: Cd total (0,3 muy bueno, 0,9 muy malo)
	var cd := float(analysis.get("cd", 0.5))
	var parts: Dictionary = analysis.get("cd_parts", {})
	scores.append(_s("AI_AERO", clampf((0.9 - cd) / 0.55 * 100.0, 0.0, 100.0), tr.call("AI_AERO_WHY") % [Game.fmt(cd, 2), Game.fmt(float(parts.get("nose", 0.0)), 2), Game.fmt(float(parts.get("body", 0.0)), 2), Game.fmt(float(parts.get("fins", 0.0)), 2)]))
	# Costo
	var budget := float(analysis.get("budget", 0.0))
	if budget > 0.0:
		var cost := float(analysis.get("cost", 0.0))
		scores.append(_s("AI_COST", clampf((budget - cost) / budget * 300.0 + 40.0, 0.0, 100.0), tr.call("AI_COST_WHY") % [Game.fmt(cost / 1e6, 1), Game.fmt(budget / 1e6, 0)]))
	# Carga útil
	var has_payload := false
	for p in design:
		if Catalog.parts.get(p.id, {}).get("kind", "") == "payload":
			has_payload = true
	scores.append(_s("AI_PAYLOAD", 100.0 if has_payload else 0.0, tr.call("AI_PAYLOAD_OK" if has_payload else "AI_PAYLOAD_NO")))
	# Ciencia de la sonda: energía, enlace y meta de ciencia
	var ev: Dictionary = analysis.get("probe", {})
	if not ev.is_empty():
		var s_sci := clampf(float(ev.science_max) / maxf(float(ev.target), 1.0) * 100.0, 0.0, 100.0)
		if not bool(ev.link_ok):
			s_sci = 0.0
		elif not bool(ev.power_ok):
			s_sci *= 0.3
		scores.append(_s("AI_SCIENCE", s_sci, tr.call("AI_SCIENCE_WHY") % [int(ev.science_max), int(ev.target), int(ev.have_w), int(ev.need_w), tr.call("AI_YES") if ev.link_ok else tr.call("AI_NO")]))
	var pct := float(ok) / n * 100.0
	var verdict := "AI_V_GO" if pct >= 90.0 else ("AI_V_RISK" if pct >= 50.0 else ("AI_V_LOW" if pct > 0.0 else "AI_V_NOGO"))
	return {"viability": pct, "runs": runs.size(), "ok": ok, "worst": worst, "worst_n": worst_n,
		"scores": scores, "verdict": verdict, "advice": Advisor.suggest(analysis, design)}


static func _s(key: String, score: float, why: String) -> Dictionary:
	return {"key": key, "score": score, "why": why}
