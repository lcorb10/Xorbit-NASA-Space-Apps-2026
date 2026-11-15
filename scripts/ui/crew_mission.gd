class_name CrewMission
extends Node
## Encadena los retos de una fase (data/crew_challenges.json): salta al puesto, Houston da la orden,
## corre el reto (jugador o IA) y guarda el puntaje por puesto. run_phase("countdown") -> phase_done.
## scores: role -> [puntajes]. Sirve para el informe (MVP y títulos).

signal phase_done(phase: String, avg: float)
signal houston(line: Dictionary)
signal challenge_done(id: String, role: String, score: float, ok: bool)
signal step_scored(role: String, score: float, human: bool)

var view: CrewView
var turbulence := 0.0
var scores := {} ## role -> Array[float]
var failed_critical := false

var _queue: Array = []
var phase := "" ## fase en curso (para saber qué falla si la tripulación se equivoca demasiado)
var _phase := ""
var _phase_scores: Array = []
var _all: Array = []


func _ready() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/crew_challenges.json"))
	_all = d.get("challenges", [])


func challenges_for(phase: String) -> Array:
	var room := view.room if view else "cabin"
	return _all.filter(func(c: Dictionary) -> bool:
		var r := str(c.get("room", "any"))
		return str(c.phase) == phase and (r == "any" or r == room))


## Cierra la fase ya: el reto abierto lo termina el piloto automático y no se corren los que faltan.
func abort() -> void:
	_queue.clear()
	if not is_instance_valid(view):
		return
	for c in view.get_children():
		if c is CrewChallenge:
			(c as CrewChallenge).autopilot_now()


func run_phase(phase: String) -> void:
	_phase = phase
	self.phase = phase
	view.shake = turbulence
	# Los mandos vibran durante la turbulencia
	if turbulence > 0.0:
		for p in view.players:
			if int(p.device) >= 0:
				Input.start_joy_vibration(int(p.device), 0.25 * turbulence, 0.6 * turbulence, 2.5)
	_phase_scores = []
	_queue = challenges_for(phase)
	_next()


func _next() -> void:
	if _queue.is_empty():
		var t := 0.0
		for s in _phase_scores:
			t += float(s)
		view.shake = 0.0
		phase_done.emit(_phase, t / maxf(_phase_scores.size(), 1.0))
		return
	var c: Dictionary = _queue.pop_front()
	var role := str(c.role)
	if view.active_role != role:
		view.set_active(role)
		await view.jumped
	# Silla caliente: si el turno pasa a otro jugador que comparte el teclado, se le pasa el teclado
	var hp := view.player_of(role)
	if view.needs_handoff(hp):
		view.show_handoff(hp)
		await view.handoff_done
	# Pantalla partida: si otro jugador (con su propio mando) tiene un reto en esta fase, lo hacen a la vez
	var partner := _pair_for(c)
	if not partner.is_empty():
		_queue.erase(partner)
		view.set_split(str(partner.role))
		_pending = 2
		_start(c, 0)
		_start(partner, 1)
	else:
		_pending = 1
		_start(c, -1)


var _pending := 0


func _start(c: Dictionary, half: int) -> void:
	var role := str(c.role)
	var ch := CrewChallenge.new()
	ch.data = c
	ch.view = view
	ch.half = half
	ch.player = view.player_of(role)
	ch.turbulence = turbulence
	if half != 1: # la radio dice la instrucción del primero; la del segundo está en su tarjeta
		ch.houston.connect(func(line: Dictionary) -> void: houston.emit(line))
	ch.step_scored.connect(func(sc: float, human: bool) -> void: step_scored.emit(role, sc, human))
	ch.finished.connect(func(id: String, score: float, ok: bool) -> void:
		if not scores.has(role):
			scores[role] = []
		scores[role].append(score)
		_phase_scores.append(score)
		if not ok and c.get("critical", false):
			failed_critical = true
		challenge_done.emit(id, role, score, ok)
		_pending -= 1
		if _pending <= 0:
			view.set_split("")
			_next.call_deferred())
	view.add_child(ch)


## Reto que puede ir a la vez con c: de otro jugador humano, con otro dispositivo (no se comparte el
## teclado) y sin pasos de "mirar" (la mirada es de la cámara principal).
func _pair_for(c: Dictionary) -> Dictionary:
	var p1 := view.player_of(str(c.role))
	if p1 < 0 or _has_look(c) or "--nosplit" in OS.get_cmdline_user_args():
		return {}
	for c2: Dictionary in _queue:
		var p2 := view.player_of(str(c2.role))
		if p2 < 0 or p2 == p1 or _has_look(c2) or str(c2.role) == str(c.role):
			continue
		if int(view.players[p1].device) < 0 and int(view.players[p2].device) < 0:
			continue
		return c2
	return {}


func _has_look(c: Dictionary) -> bool:
	for s: Dictionary in c.get("steps", []):
		if str(s.get("type", "")) == "look":
			return true
	return false
