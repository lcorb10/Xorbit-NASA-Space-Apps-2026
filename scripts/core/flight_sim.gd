class_name FlightSim
extends RefCounted
## Simula el vuelo completo antes de mostrarlo (así la animación muestra exactamente lo
## que dice la física). Punto de masa en 2D sobre una Tierra redonda:
## - gravedad que baja con la altura (μ / r²) y "fuerza centrífuga" de la velocidad de lado;
## - atmósfera exponencial (escala 8,5 km) con resistencia ½·ρ·v²·Cd·A;
## - empuje que sube al bajar la presión (de nivel del mar a vacío), gasto másico constante;
## - giro por gravedad para ganar velocidad de lado; etapas que se sueltan al agotarse;
## - corte de motores al lograr órbita; apogeo y perigeo con mecánica orbital.

const MU := 3.986004418e14
const RE := 6371000.0
const G0 := 9.80665
const H_SCALE := 8500.0
const RHO0 := 1.225
const DT := 0.05
const T_MAX := 1800.0
const SAMPLE_EVERY := 0.25
const ORBIT_PERIGEE := 140000.0 # perigeo mínimo para contar como órbita estable
const TARGET_ALT := 200000.0 # altura a la que apunta el guiado orbital
## Límites de la estructura (con aluminio 2219; escalan con la resistencia del material más débil).
## Un cohete real se diseña para unos 30-40 kPa de presión dinámica con margen; los sondas aguantan más.
const Q_LIMIT := 180000.0
const G_LIMIT := 30.0


static func simulate(analysis: Dictionary, level: int, sandbox: bool) -> Dictionary:
	var stages: Array = analysis.get("stages", [])
	var res := {"samples": [], "events": [], "success": false, "reason": "", "apogee": 0.0, "max_v": 0.0,
		"max_q": 0.0, "max_q_t": 0.0, "max_g": 0.0, "orbit": false, "perigee": 0.0, "apoapsis": 0.0,
		"progress": 0.0, "leftover_dv": 0.0, "duration": 0.0, "stage_drops": []}
	if stages.is_empty():
		res.reason = "FAIL_EMPTY"
		return res
	# Órbita solo si la misión elegida la pide (en el taller libre también se elige misión)
	var orbital := level >= 1 or (level < 0 and float(analysis.get("dv_total", 0.0)) > 8500.0)
	var dv_req := float(analysis.get("dv_required", 0.0))
	var maxd := maxf(float(analysis.get("max_d", 1.0)), 0.1)
	var area := PI * maxd * maxd / 4.0
	var cd0 := float(analysis.get("cd", 0.45))
	var stab := float(analysis.get("stability", 0.0))
	var gimbal := bool(analysis.get("gimbal", false))
	var unstable := stab < 0.0 and not gimbal
	var strength := clampf(float(analysis.get("min_strength", 1.0)), 0.3, 3.0)

	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var t := 0.0
	var si := 0 # índice de la etapa encendida (0 = etapa 1)
	var m := float(stages[0].m0)
	var prop := float(stages[0].burnable)
	var coast := 0.0 # pausa entre etapas
	var burning := true
	var lifted := false
	var on_pad_fail := false
	var orbit_done := false
	var next_sample := 0.0
	var tilt := 0.0
	var events: Array = res.events

	events.append({"t": 0.0, "key": "ignition"})
	var w0 := m * G0
	if float(stages[0].f_sl) < w0:
		on_pad_fail = true

	while t < T_MAX:
		var r := RE + y
		var g := MU / (r * r)
		var p_ratio := exp(-y / H_SCALE) if y < 150000.0 else 0.0
		var rho := RHO0 * p_ratio
		var v := sqrt(vx * vx + vy * vy)
		var q := 0.5 * rho * v * v
		var st: Dictionary = stages[si]

		# Empuje
		var thrust := 0.0
		var mdot := 0.0
		if burning and coast <= 0.0 and prop > 0.0 and float(st.mdot) > 0.0:
			thrust = float(st.f_vac) - (float(st.f_vac) - float(st.f_sl)) * p_ratio
			mdot = float(st.mdot)
		# Guiado: vertical al principio; giro por gravedad; arriba, empujar de lado y anular la subida
		if orbital and v > 40.0:
			if y < 35000.0:
				# Giro por gravedad programado mientras hay aire denso
				tilt = deg_to_rad(62.0) * pow(clampf((y - 600.0) / 35000.0, 0.0, 1.0), 0.6)
			elif thrust > 0.0:
				# Guiado en lazo cerrado: la velocidad vertical que hace falta para subir
				# hasta la altura de órbita; el resto del empuje va de lado
				var g_eff := maxf(g - vx * vx / r, 0.3)
				var vy_goal := sqrt(2.0 * g_eff * maxf(TARGET_ALT - y, 0.0)) * 0.55 if y < TARGET_ALT else (TARGET_ALT - y) / 40.0
				var ay_goal := (vy_goal - vy) / 25.0
				var cos_t := clampf((ay_goal + g_eff) / maxf(thrust / m, 0.01), -0.35, 1.0)
				tilt = acos(cos_t)
		elif not orbital:
			tilt = deg_to_rad(2.0) if v > 40.0 else 0.0 # recto hacia arriba, un poco hacia afuera

		# Arrastre con el efecto de la barrera del sonido: cerca de Mach 1 el aire se comprime
		# delante del cohete y el arrastre casi se duplica; más rápido baja otra vez
		var sound := 340.0 - 45.0 * clampf(y / 11000.0, 0.0, 1.0)
		var mach := v / sound
		var trans := 1.0
		if mach > 0.8 and mach < 1.1:
			trans = lerpf(1.0, 1.9, (mach - 0.8) / 0.3)
		elif mach >= 1.1:
			trans = 1.0 + 0.9 * pow(1.1 / mach, 1.5)
		var drag := q * cd0 * trans * area
		var ax := 0.0
		var ay := 0.0
		if m > 0.0:
			ax = thrust * sin(tilt) / m
			ay = thrust * cos(tilt) / m - g + vx * vx / r
			if v > 0.1:
				ax -= drag * vx / v / m
				ay -= drag * vy / v / m
		# En la plataforma: no baja del suelo; si el empuje no vence al peso, no despega
		if not lifted:
			if ay <= 0.0 or on_pad_fail:
				ax = 0.0
				ay = 0.0
				vx = 0.0
				vy = 0.0
			else:
				lifted = true
				events.append({"t": t, "key": "liftoff"})
		vx += ax * DT
		vy += ay * DT
		x += vx * DT
		y += vy * DT
		var accel := sqrt(ax * ax + (ay + g) * (ay + g)) / G0 if thrust > 0.0 else 0.0
		res.max_g = maxf(res.max_g, accel)
		if q > res.max_q and vy > 0.0: # solo en el ascenso
			res.max_q = q
			res.max_q_t = t
		res.max_v = maxf(res.max_v, v)
		res.apogee = maxf(res.apogee, y)

		# Inestable sin dirección: se voltea al tomar velocidad y se rompe
		if lifted and unstable and v > 70.0 and y > 150.0:
			events.append({"t": t, "key": "tumble"})
			res.reason = "FAIL_UNSTABLE"
			_sample(res, t, x, y, vx, vy, tilt, si, false, q, accel)
			break

		# Rotura: la presión del aire o la aceleración superan lo que aguanta la estructura
		if lifted and (q > Q_LIMIT * strength or accel > G_LIMIT * strength):
			if vy < 0.0:
				# Al volver a caer: la etapa vacía se quema al reentrar; la cápsula o la carga
				# bajan con escudo térmico y paracaídas. No es una falla del diseño.
				if not _has(events, "reentry"):
					events.append({"t": t, "key": "reentry"})
				strength = 1e9
			else:
				events.append({"t": t, "key": "breakup", "why": "q" if q > Q_LIMIT * strength else "g"})
				res.reason = "FAIL_BREAKUP"
				_sample(res, t, x, y, vx, vy, tilt, si, false, q, accel)
				break

		# Consumo y etapas
		if mdot > 0.0:
			var used := minf(mdot * DT, prop)
			prop -= used
			m -= used
			if prop <= 0.0:
				var is_last := si >= stages.size() - 1
				events.append({"t": t, "key": "cutoff_last" if is_last else "cutoff", "stage": si + 1})
				if is_last:
					burning = false
				else:
					var drop := m - float(stages[si + 1].m0)
					res.stage_drops.append({"t": t + 1.0, "stage": si + 1})
					m -= maxf(drop, 0.0)
					si += 1
					prop = float(stages[si].burnable)
					coast = 1.5
					events.append({"t": t + 1.0, "key": "separation", "stage": si})
		if coast > 0.0:
			coast -= DT
			if coast <= 0.0 and burning:
				events.append({"t": t, "key": "ignition_upper", "stage": si + 1})
		if events.size() > 0 and q > 0.0 and absf(t - res.max_q_t) < DT * 0.5 and t > 5.0:
			pass

		# ¿Órbita? Con los motores encendidos, cortar en cuanto el perigeo sea seguro
		if orbital and lifted and y > 100000.0:
			var orb := _orbit(x, y, vx, vy)
			if orb.perigee > ORBIT_PERIGEE and not orbit_done:
				orbit_done = true
				res.orbit = true
				res.perigee = orb.perigee
				res.apoapsis = orb.apoapsis
				# Δv que sobra en lo que queda de propelente (esta etapa + las de arriba sin usar)
				res.leftover_dv = _leftover_dv(stages, si, m, prop)
				events.append({"t": t, "key": "orbit"})
				burning = false
		if t >= next_sample:
			_sample(res, t, x, y, vx, vy, tilt, si, thrust > 0.0, q, accel)
			next_sample += SAMPLE_EVERY
		t += DT

		# Fin: cae al suelo, o ya en órbita un rato, o en vuelo suborbital pasó el apogeo y bajó
		if lifted and y <= 0.0:
			y = 0.0
			events.append({"t": t, "key": "impact"})
			break
		if orbit_done and t > _event_t(events, "orbit") + 25.0:
			break
		if on_pad_fail and prop <= 0.0:
			break
		if on_pad_fail and t > 12.0:
			break

	_sample(res, t, x, y, vx, vy, tilt, si, false, 0.0, 0.0)
	res.duration = t
	var lv := Game.level(level) if level >= 0 else {}
	# Resultado
	if res.reason == "":
		if on_pad_fail:
			res.reason = "FAIL_TWR"
		elif not orbital:
			res.success = res.apogee >= 100000.0
			res.progress = res.apogee / 100000.0
			res.reason = "OK_SPACE" if res.success else "FAIL_LOW"
		elif not res.orbit:
			res.reason = "FAIL_SUBORBITAL" if res.apogee >= 100000.0 else "FAIL_LOW"
			res.progress = clampf(res.max_v / 7800.0, 0.0, 0.99) * (9400.0 / maxf(dv_req, 9400.0))
		else:
			var reached := 9400.0 + float(res.leftover_dv)
			res.progress = reached / maxf(dv_req, 9400.0) if dv_req > 0.0 else 1.0
			res.success = sandbox or res.progress >= 1.0
			res.reason = "OK_ORBIT" if res.success else "FAIL_TRANSFER"
	# El cliente pidió una nave de cierta masa: con menos, la misión no cumple aunque vuele
	if res.success and bool(analysis.get("payload_short", false)):
		res.success = false
		res.reason = "FAIL_PAYLOAD"
	if res.reason in ["FAIL_UNSTABLE", "FAIL_BREAKUP"]:
		res.progress = clampf(res.apogee / (100000.0 if not orbital else 200000.0), 0.0, 0.99)
	# Hitos para los comentarios de radio
	if res.max_q_t > 1.0 and res.max_q > 5000.0:
		events.append({"t": res.max_q_t, "key": "max_q"})
	if res.apogee >= 100000.0:
		events.append({"t": _time_at_altitude(res.samples, 100000.0), "key": "karman"})
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.t) < float(b.t))
	res["level_name"] = lv.get("id", 0)
	return res


static func _sample(res: Dictionary, t: float, x: float, y: float, vx: float, vy: float, tilt: float, si: int, on: bool, q: float, accel: float) -> void:
	# Actitud (hacia dónde apunta la punta, medida desde la vertical local):
	# con el motor encendido, hacia donde empuja; sin motor, hacia donde se mueve
	# (como una flecha), así al pasar el apogeo se acuesta y baja de punta.
	var att := tilt
	if not on and vx * vx + vy * vy > 4.0:
		att = atan2(vx, vy)
	res.samples.append({"t": t, "x": x, "y": y, "vx": vx, "vy": vy, "tilt": tilt, "att": att, "stage": si, "on": on, "q": q, "g": accel})


static func _orbit(x: float, y: float, vx: float, vy: float) -> Dictionary:
	# Velocidad horizontal = tangencial, vertical = radial
	var r := RE + y
	var v2 := vx * vx + vy * vy
	var eps := v2 / 2.0 - MU / r
	if eps >= 0.0:
		return {"perigee": INF, "apoapsis": INF, "escape": true}
	var a := -MU / (2.0 * eps)
	var h := r * vx
	var e := sqrt(maxf(0.0, 1.0 + 2.0 * eps * h * h / (MU * MU)))
	return {"perigee": a * (1.0 - e) - RE, "apoapsis": a * (1.0 + e) - RE, "escape": false}


static func _leftover_dv(stages: Array, si: int, m: float, prop: float) -> float:
	var dv := 0.0
	var st: Dictionary = stages[si]
	if prop > 0.0 and float(st.mdot) > 0.0:
		var isp := float(st.f_vac) / (float(st.mdot) * G0)
		dv += isp * G0 * log(m / (m - prop))
	for k in range(si + 1, stages.size()):
		dv += float(stages[k].dv)
	return dv


static func _has(events: Array, key: String) -> bool:
	for e in events:
		if e.key == key:
			return true
	return false


static func _event_t(events: Array, key: String) -> float:
	for e in events:
		if e.key == key:
			return float(e.t)
	return 0.0


static func _time_at_altitude(samples: Array, h: float) -> float:
	for s in samples:
		if float(s.y) >= h:
			return float(s.t)
	return 0.0


## Estado interpolado en el instante t (para reproducir el vuelo).
static func state_at(res: Dictionary, t: float) -> Dictionary:
	var s: Array = res.samples
	if s.is_empty():
		return {}
	if t <= float(s[0].t):
		return s[0]
	var lo := 0
	var hi := s.size() - 1
	if t >= float(s[hi].t):
		return s[hi]
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if float(s[mid].t) <= t:
			lo = mid
		else:
			hi = mid
	var a: Dictionary = s[lo]
	var b: Dictionary = s[hi]
	var k := (t - float(a.t)) / maxf(float(b.t) - float(a.t), 0.0001)
	var out := {}
	for key in ["t", "x", "y", "vx", "vy", "tilt", "q", "g"]:
		out[key] = lerpf(float(a[key]), float(b[key]), k)
	out["att"] = lerp_angle(float(a.get("att", a.tilt)), float(b.get("att", b.tilt)), k)
	out["stage"] = a.stage
	out["on"] = a.on
	return out
