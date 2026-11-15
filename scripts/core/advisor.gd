class_name Advisor
extends RefCounted
## Houston como asesor: mira el análisis del cohete y dice qué arreglar primero y por qué.
## Lo usan el botón "Preguntar a Houston" del taller y el manual (sección "Esta misión").
## Los textos están en data/comms.json → help (en/es, con voz opcional por id).


## Id de la primera sugerencia que aplica (orden de importancia), o "help_ok".
static func suggest(analysis: Dictionary, design: Array) -> String:
	if design.is_empty():
		return "help_empty"
	var ws := {}
	for w in analysis.get("warnings", []):
		ws[str(w.key)] = true
	if ws.has("W_NO_ENGINE"):
		return "help_no_engine"
	if ws.has("W_NO_FUEL"):
		return "help_no_fuel"
	if ws.has("W_TWR_LOW"):
		return "help_twr"
	if ws.has("W_NO_NOSE"):
		return "help_nose"
	if ws.has("W_UNSTABLE"):
		return "help_unstable"
	if ws.has("W_G_LIMIT"):
		return "help_g"
	if ws.has("W_PAYLOAD_MIN"):
		return "help_payload_min"
	if ws.has("W_GEAR"):
		return "help_gear"
	if ws.has("W_LINK"):
		return "help_link"
	if ws.has("W_POWER"):
		return "help_power"
	if ws.has("W_NO_INSTR"):
		return "help_instr"
	var need := float(analysis.get("dv_required", 0.0))
	var have := float(analysis.get("dv_total", 0.0))
	var stages: Array = analysis.get("stages", [])
	if need > 0.0 and have < need:
		return "help_stage" if stages.size() < 2 and need > 6000.0 else "help_dv"
	var budget := float(analysis.get("budget", 0.0))
	if budget > 0.0 and float(analysis.get("cost", 0.0)) > budget:
		return "help_budget"
	if ws.has("W_TWR_MARGINAL"):
		return "help_twr_marginal"
	if ws.has("W_NO_PAYLOAD"):
		return "help_payload"
	return "help_ok"


## Lista de requisitos para ganar la misión con su estado: [{text, ok}].
static func checklist(analysis: Dictionary, design: Array) -> Array:
	var out := []
	var need := float(analysis.get("dv_required", 0.0))
	var have := float(analysis.get("dv_total", 0.0))
	if need > 0.0:
		out.append({"text": TranslationServer.translate("CK_DV") % [Game.fmt(have / 1000.0, 2), Game.fmt(need / 1000.0, 1)], "ok": have >= need})
	var stages: Array = analysis.get("stages", [])
	var twr := float(stages[0].twr) if not stages.is_empty() else 0.0
	out.append({"text": TranslationServer.translate("CK_TWR") % Game.fmt(twr, 2), "ok": twr >= 1.2})
	var stab := float(analysis.get("stability", -9.0))
	var gimbal := bool(analysis.get("gimbal", false))
	out.append({"text": TranslationServer.translate("CK_STAB") % Game.fmt(stab, 2), "ok": stab >= 1.0 or gimbal})
	var budget := float(analysis.get("budget", 0.0))
	if budget > 0.0:
		var cost := float(analysis.get("cost", 0.0))
		out.append({"text": TranslationServer.translate("CK_COST") % [Game.fmt(cost / 1e6, 1), Game.fmt(budget / 1e6, 0)], "ok": cost <= budget})
	var has_nose: bool = not design.is_empty() and Catalog.parts.get(design[0].id, {}).get("kind", "") == "nose"
	out.append({"text": TranslationServer.translate("CK_NOSE"), "ok": has_nose, "verify": "inspection"})
	var has_payload := false
	for p in design:
		if Catalog.parts.get(p.id, {}).get("kind", "") == "payload":
			has_payload = true
	out.append({"text": TranslationServer.translate("CK_PAYLOAD_KG") % [int(analysis.get("payload_mass", 0.0)), int(analysis.get("payload_min", 0.0))], "ok": has_payload and not bool(analysis.get("payload_short", false)), "verify": "inspection"})
	# Requisitos de la sonda (segmento espacial y de tierra)
	var ev: Dictionary = analysis.get("probe", {})
	if has_payload and ev.has("mission_h"):
		out.append({"text": TranslationServer.translate("CK_POWER"), "ok": bool(ev.power_ok), "verify": "analysis"})
		out.append({"text": TranslationServer.translate("CK_LINK"), "ok": bool(ev.link_ok) and float(ev.get("data_frac", 1.0)) >= 0.999, "verify": "test"})
		out.append({"text": TranslationServer.translate("CK_LIFE"), "ok": bool(ev.get("life_ok", true)), "verify": "analysis"})
		out.append({"text": TranslationServer.translate("CK_SCIENCE") % [int(ev.get("science_expected", 0.0)), int(ev.get("target", 0.0))], "ok": float(ev.get("science_expected", 0.0)) >= float(ev.get("target", 1e9)), "verify": "demonstration"})
	# Cómo se comprueba cada requisito (NASA: cada requisito lleva su verificación)
	for it: Dictionary in out:
		it["text"] = str(it.text) + "   · " + TranslationServer.translate("VER_" + str(it.get("verify", "analysis")).to_upper())
	return out


## Misiones secundarias del encargo (data/missions.json → extras) con su estado.
## flight: resultado del vuelo (vacío en el taller: se mide lo que ya se sabe del diseño).
static func extras(mission: int, analysis: Dictionary, design: Array, flight: Dictionary, science: float) -> Array:
	var out := []
	var m: Dictionary = MissionBrief.data().get("missions", {}).get(str(mission), {})
	var cfg := {}
	for p in design:
		if Catalog.parts.get(p.id, {}).get("kind", "") == "payload":
			cfg = p.get("probe", Probe.default_config(mission))
			break
	var ev: Dictionary = analysis.get("probe", {})
	for x: Dictionary in m.get("extras", []):
		var c := str(x.cond).split(":")
		var ok := false
		match c[0]:
			"instr":
				ok = c[1] in cfg.get("instruments", [])
			"power":
				ok = str(cfg.get("power", "")) == c[1]
			"antenna":
				ok = str(cfg.get("antenna", "")) == c[1]
			"budget":
				var b := float(analysis.get("budget", 0.0))
				ok = b <= 0.0 or float(analysis.get("cost", 0.0)) <= b * float(c[1])
			"max_g":
				ok = float(flight.get("max_g", analysis.get("max_g_est", 99.0))) <= float(c[1])
			"science":
				var have := science if not flight.is_empty() else float(ev.get("science_max", 0.0))
				ok = have >= float(ev.get("target", 1e9))
		if not flight.is_empty() and not bool(flight.get("success", false)):
			ok = false
		out.append({"text": Codex.pick(x.text), "ok": ok})
	return out
