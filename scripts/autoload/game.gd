extends Node
## Estado global: paleta y tema de plano técnico, textos EN/ES, datos de niveles,
## ajustes, progreso y cambio de escena con fundido.
## Prueba automática: godot --headless --path . -- --smoke

# Paleta de plano técnico (tinta clara sobre azul de plano)
const PAPER := Color("#0d2540")
const PAPER_DEEP := Color("#0a1d33")
const INK := Color("#e3eef8")
const INK_DIM := Color("#9db8d2")
const LINE := Color("#2f5378")
const GRID := Color(0.89, 0.93, 0.97, 0.045)
const GRID_MAJOR := Color(0.89, 0.93, 0.97, 0.09)
const MARK := Color("#fb923c") # lápiz rojo: lo único que resalta
const GOOD := Color("#5ad19a")

const SCENES := {
	"menu": "res://scenes/main_menu.tscn",
	"levels": "res://scenes/level_select.tscn",
	"settings": "res://scenes/settings.tscn",
	"workshop": "res://scenes/workshop.tscn",
	"flight": "res://scenes/flight.tscn",
	"saves": "res://scenes/saves.tscn",
}
const SETTINGS_PATH := "user://settings.cfg"
const OLD_PROGRESS_PATH := "user://progress.cfg" # antes de las ranuras de partida
const SLOTS := 3
const LOCALES := ["en", "es"]

var font_display: Font
var font_display_medium: Font
var font_mono: Font
var font_mono_medium: Font
var theme: Theme

var levels: Array = []
var selected_level := 0
## Lo que se va a lanzar: {design, analysis, level, sandbox}
var flight := {}
var sandbox := false
## Misión elegida en el taller libre para medir el cohete (-1 = vuelo libre)
var sandbox_mission := -1
## --landtest=moon|mars|moon_nolegs: abre la escena de aterrizaje directo (pruebas)
var landtest := ""
## Jugadores de la tripulación (lo llena la sala de tripulación). Por defecto: uno con teclado en todos los puestos.
var crew_setup: Array = []


func crew_players() -> Array:
	if "--crewai" in OS.get_cmdline_user_args():
		return [] # prueba: la IA hace todos los puestos
	if crew_setup.is_empty():
		return [{"name": "P1", "device": -1, "roles": ["commander", "engineer", "systems", "comms"]}]
	return crew_setup
var settings := {"locale": "en", "volume": 0.8, "music": 0.6, "fullscreen": false, "quality": "high", "slot": 1, "voice": true, "night": false}
var progress := _fresh_progress("")
## Ranura de partida en uso (1..SLOTS). Cada una guarda su progreso y sus cohetes.
var slot := 1
var _save_root := "user://saves"
var _smoke_io := false
var _dev_no_save := false # con --unlocked (capturas) no se escribe la partida # la prueba automática escribe en una carpeta aparte

var _fade: ColorRect
var _busy := false
var _smoke := false


## Pruebas: --shot=<segundos>:<archivo.png> guarda la imagen real de la ventana (al tamaño de la ventana) y cierra.
func _dev_shot(arg: String) -> void:
	var p := arg.trim_prefix("--shot=").split(":", true, 1)
	await get_tree().create_timer(float(p[0])).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(p[1])
	print("SHOT ", img.get_width(), "x", img.get_height(), " ", p[1])
	get_tree().quit()


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_dev_shot.call_deferred(a)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_smoke = "--smoke" in OS.get_cmdline_user_args()
	_load_fonts()
	theme = _build_theme()
	get_tree().root.theme = theme
	_load_translations()
	levels = _read_json("res://data/levels.json").get("levels", [])
	if not _smoke:
		_migrate_old_name()
		_load_settings()
		slot = clampi(int(settings.get("slot", 1)), 1, SLOTS)
		_migrate_old_save()
		_load_progress()
	_apply_settings()
	_build_fade()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_min_size(Vector2i(1024, 576))
	if _smoke:
		_run_smoke.call_deferred()
	_dev_args()


## Opciones de desarrollo: -- --goto=levels --locale=es --unlocked=4
func _dev_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--solve-free":
			Solver.ignore_budget = true
			Solver.solve_all()
			get_tree().quit.call_deferred()
		if arg == "--solve":
			Solver.solve_all()
			get_tree().quit.call_deferred()
		if arg.begins_with("--landtest="):
			landtest = arg.trim_prefix("--landtest=")
		if arg == "--night":
			settings.night = true
		if arg == "--nohud": # grabar el video: solo los gráficos del juego, sin interfaz
			get_tree().node_added.connect(func(n: Node) -> void:
				if n is CanvasLayer:
					n.visible = false)
		if arg == "--sandbox":
			sandbox = true
			selected_level = -1
		var kv := arg.trim_prefix("--").split("=")
		if kv.size() == 2 and kv[0] == "level":
			selected_level = int(kv[1])
		if kv.size() != 2:
			continue
		match kv[0]:
			"flytest":
				_dev_no_save = true # las pruebas de vuelo no tocan la partida real
				Catalog.load_all()
				var fparts := kv[1].split(":") # --flytest=saturn_v:3 vuela contra la misión 3
				kv[1] = fparts[0]
				var d: Array = (Catalog.default_designs[kv[1].trim_suffix("_nofins")] as Array).duplicate(true)
				if kv[1].ends_with("_nofins"):
					for part in d:
						part.erase("fins")
				var lv := int(fparts[1]) if fparts.size() > 1 else (0 if kv[1].begins_with("sounding") else 1)
				selected_level = lv
				flight = {"design": d, "analysis": RocketAnalysis.analyze(d, lv, false), "level": lv, "sandbox": false}
			"simtest":
				# --simtest=diseño:nivel  (nivel -1 = taller libre): imprime el vuelo y sale
				Catalog.load_all()
				var parts := kv[1].split(":")
				var lvl := int(parts[1]) if parts.size() > 1 else 0
				var dd: Array = (Catalog.default_designs[parts[0]] as Array).duplicate(true)
				var an := RocketAnalysis.analyze(dd, lvl, lvl < 0)
				var fr := FlightSim.simulate(an, lvl, lvl < 0)
				var evs := []
				for e in fr.events:
					evs.append("%s@%.0f%s" % [e.key, e.t, ("(" + str(e.why) + ")") if e.has("why") else ""])
				print("SIM costo %.1f M (cohete %.1f + nave %.1f) · " % [float(an.cost) / 1e6, float(an.cost_rocket) / 1e6, float(an.cost_payload) / 1e6], "SIM %s nivel %d: %s apogeo=%.1f km vmax=%.0f maxQ=%.1f kPa maxG=%.1f estab=%.2f twr=%.2f | %s" % [parts[0], lvl, fr.reason, fr.apogee / 1000.0, fr.max_v, fr.max_q / 1000.0, fr.max_g, an.stability, an.stages[0].twr, " ".join(evs)])
				get_tree().quit.call_deferred()
			"locale":
				settings.locale = kv[1]
				TranslationServer.set_locale(kv[1])
			"unlocked":
				_dev_no_save = true # atajo de prueba: no se guarda en la partida real
				progress.unlocked = int(kv[1])
				for i in int(kv[1]):
					progress.stars[str(i)] = 3 - i % 3
			"goto":
				if SCENES.has(kv[1]):
					get_tree().change_scene_to_file.call_deferred(SCENES[kv[1]])


# ---------- Escenas ----------

func goto(key: String) -> void:
	if _busy or not SCENES.has(key):
		return
	_busy = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var out := create_tween()
	out.tween_property(_fade, "modulate:a", 1.0, 0.16)
	await out.finished
	get_tree().change_scene_to_file(SCENES[key])
	await get_tree().process_frame
	await get_tree().process_frame
	var back := create_tween()
	back.tween_property(_fade, "modulate:a", 0.0, 0.22)
	await back.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


func _build_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = PAPER_DEEP
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	layer.add_child(_fade)


# ---------- Niveles y progreso ----------

func level(i: int) -> Dictionary:
	for l in levels:
		if int(l.id) == i:
			return l
	return {}


func is_unlocked(i: int) -> bool:
	return sandbox or i <= int(progress.unlocked)


func stars_for(i: int) -> int:
	return int(progress.stars.get(str(i), 0))


func complete_level(i: int, stars: int) -> void:
	progress.stars[str(i)] = maxi(stars_for(i), clampi(stars, 0, 3))
	progress.unlocked = clampi(maxi(int(progress.unlocked), i + 1), 0, levels.size() - 1)
	_save_progress()


func reset_progress() -> void:
	progress = _fresh_progress(str(progress.get("name", "")))
	_save_progress()


# ---------- Partidas guardadas (ranuras) ----------
# user://saves/slot_N/progress.cfg  → misiones, estrellas, tutoriales vistos, nombre, fechas, tiempo jugado
# user://saves/slot_N/designs/*.json → el cohete de cada misión y el del taller libre

var _slot_live := false # la ranura actual existe en disco


func _fresh_progress(title: String) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	return {"unlocked": 0, "stars": {}, "tutorial_done": false, "seen": {}, "name": title,
		"created": now, "updated": now, "play_s": 0.0}


func _slot_dir(n: int) -> String:
	return "%s/slot_%d" % [_save_root, n]


func slot_exists(n: int) -> bool:
	return FileAccess.file_exists(_slot_dir(n) + "/progress.cfg")


## Resumen de una ranura para la pantalla de partidas ({} si está vacía).
func slot_info(n: int) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(_slot_dir(n) + "/progress.cfg") != OK:
		return {}
	var stars: Dictionary = cfg.get_value("progress", "stars", {})
	var total := 0
	for k in stars:
		total += int(stars[k])
	var play := float(cfg.get_value("progress", "play_s", 0.0))
	if n == slot:
		play = float(progress.get("play_s", play))
	return {
		"name": str(cfg.get_value("progress", "name", "")),
		"unlocked": int(cfg.get_value("progress", "unlocked", 0)),
		"stars": total,
		"tutorial_done": bool(cfg.get_value("progress", "tutorial_done", false)),
		"created": int(cfg.get_value("progress", "created", 0)),
		"updated": int(cfg.get_value("progress", "updated", 0)),
		"play_s": play,
	}


## Empieza una partida desde cero en la ranura n (borra lo que hubiera ahí).
func new_game(n: int, title: String) -> void:
	delete_slot(n)
	slot = n
	progress = _fresh_progress(title.strip_edges())
	_save_progress()
	settings.slot = n
	_save_settings()


## Sigue con la partida guardada en la ranura n.
func load_slot(n: int) -> void:
	_save_progress() # guarda el tiempo jugado de la que se deja
	slot = n
	settings.slot = n
	_save_settings()
	_load_progress()


## Borra la ranura n por completo (progreso y cohetes). No se puede deshacer.
func delete_slot(n: int) -> void:
	_remove_tree(_slot_dir(n))
	if n == slot:
		progress = _fresh_progress("")
		_slot_live = false


func rename_slot(n: int, title: String) -> void:
	if n == slot:
		progress.name = title.strip_edges()
		_save_progress()
		return
	var cfg := ConfigFile.new()
	if cfg.load(_slot_dir(n) + "/progress.cfg") == OK:
		cfg.set_value("progress", "name", title.strip_edges())
		cfg.save(_slot_dir(n) + "/progress.cfg")


## Vuelve a mostrar los tutoriales y las explicaciones de Houston sin perder las estrellas.
func replay_tutorials(n: int) -> void:
	if n != slot:
		load_slot(n)
	progress.tutorial_done = false
	progress.seen = {}
	_save_progress()


func first_empty_slot() -> int:
	for n in range(1, SLOTS + 1):
		if not slot_exists(n):
			return n
	return -1


func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for sub in d.get_directories():
		_remove_tree(path + "/" + sub)
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(path)


## El juego se llamaba "Δv": su carpeta de datos era app_userdata/Δv. Se copia lo guardado
## (partidas, piezas propias, ajustes) a la carpeta nueva de Xorbit la primera vez.
func _migrate_old_name() -> void:
	var old := OS.get_user_data_dir().get_base_dir() + "/Δv"
	if not DirAccess.dir_exists_absolute(old) or FileAccess.file_exists("user://settings.cfg"):
		return
	_copy_tree(old, OS.get_user_data_dir(), ["logs", "shader_cache", "vulkan", "objectdb_snapshots"])


func _copy_tree(src: String, dst: String, skip: Array) -> void:
	DirAccess.make_dir_recursive_absolute(dst)
	var d := DirAccess.open(src)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.copy_absolute(src + "/" + f, dst + "/" + f)
	for sub in d.get_directories():
		if sub not in skip:
			_copy_tree(src + "/" + sub, dst + "/" + sub, skip)


## Las versiones anteriores guardaban una sola partida en user://progress.cfg y user://designs.
## La primera vez se mueven a la ranura 1.
func _migrate_old_save() -> void:
	if not FileAccess.file_exists(OLD_PROGRESS_PATH) or slot_exists(1):
		return
	DirAccess.make_dir_recursive_absolute(_slot_dir(1))
	var cfg := ConfigFile.new()
	if cfg.load(OLD_PROGRESS_PATH) == OK:
		var now := int(Time.get_unix_time_from_system())
		cfg.set_value("progress", "name", "")
		cfg.set_value("progress", "created", now)
		cfg.set_value("progress", "updated", now)
		cfg.save(_slot_dir(1) + "/progress.cfg")
	if DirAccess.dir_exists_absolute("user://designs"):
		DirAccess.rename_absolute("user://designs", _slot_dir(1) + "/designs")
	DirAccess.remove_absolute(OLD_PROGRESS_PATH)
	slot = 1


func _load_progress() -> void:
	progress = _fresh_progress("")
	var cfg := ConfigFile.new()
	if cfg.load(_slot_dir(slot) + "/progress.cfg") != OK:
		return
	for k in progress.keys():
		progress[k] = cfg.get_value("progress", k, progress[k])
	progress.unlocked = int(progress.unlocked)
	_slot_live = true


## Primera vez que pasa algo (una explicación ya dada, etc.). Devuelve true solo la primera vez.
func first_time(key: String) -> bool:
	if not progress.has("seen"):
		progress["seen"] = {}
	if progress.seen.has(key):
		return false
	progress.seen[key] = true
	_save_progress()
	return true


func save_progress() -> void:
	_save_progress()


func _save_progress() -> void:
	if (_smoke and not _smoke_io) or _dev_no_save:
		return
	DirAccess.make_dir_recursive_absolute(_slot_dir(slot))
	progress.updated = int(Time.get_unix_time_from_system())
	var cfg := ConfigFile.new()
	for k in progress.keys():
		cfg.set_value("progress", k, progress[k])
	cfg.save(_slot_dir(slot) + "/progress.cfg")
	_slot_live = true


## Tiempo jugado: cuenta mientras hay una partida y no se está en el menú.
func _process(delta: float) -> void:
	if not _slot_live:
		return
	var cur := get_tree().current_scene
	if cur != null and cur.scene_file_path != SCENES.menu and cur.scene_file_path != SCENES.saves:
		progress.play_s = float(progress.get("play_s", 0.0)) + delta


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _slot_live:
		_save_progress()


## "1 h 12 min", "8 min"
func play_time_text(s: float) -> String:
	var m := int(s / 60.0)
	if m < 60:
		return "%d min" % m
	return "%d h %02d min" % [m / 60, m % 60]


## Fecha local legible de una marca de tiempo Unix.
func date_text(unix: int) -> String:
	if unix <= 0:
		return "—"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix + bias)
	return "%02d/%02d/%d %02d:%02d" % [d.day, d.month, d.year, d.hour, d.minute]


# ---------- Diseños guardados (uno por misión; -1 = taller libre) ----------

func _design_path(lvl: int) -> String:
	return "%s/designs/%s.json" % [_slot_dir(slot), "sandbox" if lvl < 0 else "level_%d" % lvl]


func load_design(lvl: int) -> Array:
	Catalog.load_all()
	if not _smoke:
		var f := FileAccess.open(_design_path(lvl), FileAccess.READ)
		if f != null:
			var v: Variant = JSON.parse_string(f.get_as_text())
			if v is Array:
				return (v as Array).filter(func(p: Variant) -> bool:
					return p is Dictionary and Catalog.parts.has(p.get("id", "")))
	# Sin diseño guardado, la misión empieza sin cohete: el jugador lo arma pieza por pieza
	if _smoke:
		return (Catalog.default_designs["sounding" if lvl == 0 else "two_stage"] as Array).duplicate(true)
	return []


func save_design(lvl: int, design: Array) -> void:
	if (_smoke and not _smoke_io) or _dev_no_save:
		return
	DirAccess.make_dir_recursive_absolute(_slot_dir(slot) + "/designs")
	var f := FileAccess.open(_design_path(lvl), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(design))

# ---------- Mis cohetes (compartidos entre partidas) ----------
const ROCKETS_DIR := "user://rockets"


func list_rockets() -> Array:
	var out := []
	var d := DirAccess.open(ROCKETS_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(".json"):
			continue
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROCKETS_DIR + "/" + f))
		if v is Dictionary and v.get("design") is Array:
			out.append({"name": str(v.get("name", f)), "design": v.design, "file": f, "saved": int(v.get("saved", 0))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.saved) > int(b.saved))
	return out


func save_rocket(title: String, design: Array) -> void:
	if (_smoke and not _smoke_io) or _dev_no_save:
		return
	DirAccess.make_dir_recursive_absolute(ROCKETS_DIR)
	var safe := title.to_lower().validate_filename().replace(" ", "_")
	export_rocket("%s/%s.json" % [ROCKETS_DIR, safe], title, design)


func delete_rocket(file: String) -> void:
	DirAccess.remove_absolute(ROCKETS_DIR + "/" + file)


func export_rocket(path: String, title: String, design: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"xorbit": 1, "name": title, "saved": int(Time.get_unix_time_from_system()), "design": design}, "  "))


## Lee un cohete exportado (o un arreglo de piezas suelto). Devuelve [] si no sirve.
func import_rocket(path: String) -> Array:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var d: Variant = v.get("design") if v is Dictionary else v
	if not d is Array:
		return []
	Catalog.load_all()
	return (d as Array).filter(func(p: Variant) -> bool: return p is Dictionary and Catalog.parts.has(p.get("id", "")))


# ---------- Ajustes ----------

func set_locale(loc: String) -> void:
	if loc not in LOCALES:
		return
	settings.locale = loc
	TranslationServer.set_locale(loc)
	_save_settings()


func set_music(v: float) -> void:
	settings.music = clampf(v, 0.0, 1.0)
	Sound.apply_volume()
	_save_settings()


func set_volume(v: float) -> void:
	settings.volume = clampf(v, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(settings.volume, 0.0001)))
	_save_settings()


## Modo noche: el KSC de noche, con focos y faroles.
func set_night(on: bool) -> void:
	settings.night = on
	_save_settings()


## Voz de Houston (los subtítulos se muestran siempre).
func set_voice(on: bool) -> void:
	settings.voice = on
	_save_settings()


func set_quality(q: String) -> void:
	settings.quality = q
	_save_settings()


func set_fullscreen(on: bool) -> void:
	settings.fullscreen = on
	_apply_window_mode()
	_save_settings()


func _apply_settings() -> void:
	TranslationServer.set_locale(settings.locale)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(settings.volume, 0.0001)))
	if settings.fullscreen:
		_apply_window_mode()


func _apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if "--windowed" in OS.get_cmdline_user_args(): # pruebas en ventana (p. ej. pantallas pequeñas)
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for k in settings.keys():
		settings[k] = cfg.get_value("settings", k, settings[k])


func _save_settings() -> void:
	if _smoke:
		return
	var cfg := ConfigFile.new()
	for k in settings.keys():
		cfg.set_value("settings", k, settings[k])
	cfg.save(SETTINGS_PATH)


# ---------- Textos y números ----------

func _load_translations() -> void:
	var data := _read_json("res://data/i18n.json")
	var by_locale := {}
	for key: String in data.keys():
		if key.begins_with("_"):
			continue
		var entry: Dictionary = data[key]
		for loc: String in entry.keys():
			if not by_locale.has(loc):
				var t := Translation.new()
				t.locale = loc
				by_locale[loc] = t
			(by_locale[loc] as Translation).add_message(key, entry[loc])
	for loc in by_locale:
		TranslationServer.add_translation(by_locale[loc])


## Número con un decimal y la coma o el punto según el idioma.
func fmt(v: float, decimals := 1) -> String:
	var s := ("%." + str(decimals) + "f") % v
	return s.replace(".", ",") if TranslationServer.get_locale().begins_with("es") else s


## Entero con separador de miles según el idioma.
func fmt_int(v: int) -> String:
	var s := str(absi(v))
	var sep := "." if TranslationServer.get_locale().begins_with("es") else ","
	var out := ""
	while s.length() > 3:
		out = sep + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out


func budget_text(l: Dictionary) -> String:
	if l.get("budget_musd") == null:
		return tr("LEVELS_BUDGET_OPEN")
	return "US$ %s M" % fmt_int(int(l.budget_musd))


func dv_text(l: Dictionary) -> String:
	if l.get("dv_km_s") == null:
		return "—"
	return "%s km/s" % fmt(float(l.dv_km_s))


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("No se pudo abrir %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_error("JSON inválido en %s" % path)
	return {}


# ---------- Dibujo compartido ----------

static func star_points(center: Vector2, r_out: float, r_in: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		var r := r_out if i % 2 == 0 else r_in
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts


# ---------- Tema de plano técnico ----------

func _load_fonts() -> void:
	font_display = _font("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
	font_display_medium = _font("res://assets/fonts/BarlowCondensed-Medium.ttf")
	font_mono = _font("res://assets/fonts/IBMPlexMono-Regular.ttf")
	font_mono_medium = _font("res://assets/fonts/IBMPlexMono-Medium.ttf")


func _font(path: String) -> Font:
	var f: FontFile = load(path)
	# Respaldo del sistema para glifos que la fuente no trae (Δ, flechas)
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Segoe UI", "Arial", "DejaVu Sans", "Noto Sans"])
	var fb: Array[Font] = [sys]
	f.fallbacks = fb
	return f


func _box(bg: Color, border := 0, border_color := LINE, margin := Vector4(16, 8, 16, 8)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(border)
	s.border_color = border_color
	s.content_margin_left = margin.x
	s.content_margin_top = margin.y
	s.content_margin_right = margin.z
	s.content_margin_bottom = margin.w
	s.set_corner_radius_all(6)
	s.anti_aliasing = true
	return s


func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font_mono
	t.default_font_size = 17

	# Etiquetas
	t.set_color("font_color", "Label", INK)
	for v in [["Eyebrow", font_mono_medium, 13, INK_DIM], ["Title", font_display, 72, INK],
			["Lead", font_display_medium, 30, INK_DIM], ["Body", font_mono, 16, INK],
			["Hint", font_mono, 15, INK_DIM], ["Value", font_display, 34, INK]]:
		t.set_type_variation(v[0], "Label")
		t.set_font("font", v[0], v[1])
		t.set_font_size("font_size", v[0], v[2])
		t.set_color("font_color", v[0], v[3])

	# Botón base: rectángulo de línea fina, como una casilla del plano
	var clear := Color(0, 0, 0, 0)
	t.set_font("font", "Button", font_mono_medium)
	t.set_font_size("font_size", "Button", 16)
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", INK)
	t.set_color("font_pressed_color", "Button", MARK)
	t.set_color("font_disabled_color", "Button", Color(INK_DIM, 0.45))
	t.set_stylebox("normal", "Button", _box(clear, 1, LINE))
	t.set_stylebox("hover", "Button", _box(Color(INK, 0.06), 1, INK))
	t.set_stylebox("pressed", "Button", _box(Color(MARK, 0.12), 1, MARK))
	t.set_stylebox("hover_pressed", "Button", _box(Color(MARK, 0.18), 1, MARK))
	t.set_stylebox("disabled", "Button", _box(clear, 1, Color(LINE, 0.5)))
	# Foco en tinta blanca para no confundirlo con la opción elegida (lápiz rojo)
	var focus := _box(clear, 2, INK)
	focus.expand_margin_left = 3
	focus.expand_margin_right = 3
	focus.expand_margin_top = 3
	focus.expand_margin_bottom = 3
	focus.draw_center = false
	t.set_stylebox("focus", "Button", focus)

	# Opción grande del menú principal
	t.set_type_variation("MenuItem", "Button")
	t.set_font("font", "MenuItem", font_display)
	t.set_font_size("font_size", "MenuItem", 38)
	var m := Vector4(20, 2, 20, 2)
	var item_normal := _box(clear, 0, LINE, m)
	var item_hover := _box(Color(INK, 0.05), 0, MARK, m)
	item_hover.border_width_left = 3
	var item_pressed := _box(Color(MARK, 0.1), 0, MARK, m)
	item_pressed.border_width_left = 3
	var item_focus := _box(clear, 0, MARK, m)
	item_focus.border_width_left = 3
	item_focus.draw_center = false
	t.set_stylebox("normal", "MenuItem", item_normal)
	t.set_stylebox("hover", "MenuItem", item_hover)
	t.set_stylebox("pressed", "MenuItem", item_pressed)
	t.set_stylebox("hover_pressed", "MenuItem", item_pressed)
	t.set_stylebox("disabled", "MenuItem", item_normal)
	t.set_stylebox("focus", "MenuItem", item_focus)

	# Acción principal: el único bloque relleno en lápiz rojo
	t.set_type_variation("Primary", "Button")
	t.set_font("font", "Primary", font_display)
	t.set_font_size("font_size", "Primary", 30)
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "Primary", PAPER_DEEP)
	t.set_color("font_disabled_color", "Primary", Color(INK_DIM, 0.6))
	var pm := Vector4(28, 8, 28, 8)
	t.set_stylebox("normal", "Primary", _box(MARK, 0, MARK, pm))
	t.set_stylebox("hover", "Primary", _box(MARK.lightened(0.15), 0, MARK, pm))
	t.set_stylebox("pressed", "Primary", _box(MARK.darkened(0.15), 0, MARK, pm))
	t.set_stylebox("hover_pressed", "Primary", _box(MARK.darkened(0.1), 0, MARK, pm))
	t.set_stylebox("disabled", "Primary", _box(clear, 1, LINE, pm))
	var pfocus := _box(clear, 2, INK, pm)
	pfocus.draw_center = false
	pfocus.expand_margin_left = 4
	pfocus.expand_margin_right = 4
	pfocus.expand_margin_top = 4
	pfocus.expand_margin_bottom = 4
	t.set_stylebox("focus", "Primary", pfocus)

	# Peligro: acciones que borran (rojo), con foco visible
	const DANGER := Color("#e5484d")
	t.set_type_variation("Danger", "Button")
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "Danger", Color.WHITE)
	var dm := Vector4(22, 8, 22, 8)
	t.set_stylebox("normal", "Danger", _box(DANGER, 0, DANGER, dm))
	t.set_stylebox("hover", "Danger", _box(DANGER.lightened(0.12), 0, DANGER, dm))
	t.set_stylebox("pressed", "Danger", _box(DANGER.darkened(0.15), 0, DANGER, dm))
	t.set_stylebox("focus", "Danger", pfocus)
	# Control compacto del HUD (velocidad del tiempo, cámara, saltar): misma altura y letra más chica
	t.set_type_variation("Hud", "Button")
	t.set_font_size("font_size", "Hud", 15)
	var hm := Vector4(12, 6, 12, 6)
	t.set_stylebox("normal", "Hud", _box(Color(0.03, 0.07, 0.12, 0.82), 1, Color(LINE, 0.8), hm))
	t.set_stylebox("hover", "Hud", _box(Color(0.06, 0.12, 0.2, 0.9), 1, INK_DIM, hm))
	t.set_stylebox("pressed", "Hud", _box(Color(MARK, 0.25), 1, MARK, hm))
	t.set_stylebox("hover_pressed", "Hud", _box(Color(MARK, 0.3), 1, MARK, hm))
	t.set_stylebox("disabled", "Hud", _box(Color(0.03, 0.07, 0.12, 0.5), 1, Color(LINE, 0.4), hm))
	t.set_color("font_pressed_color", "Hud", MARK)
	t.set_color("font_hover_pressed_color", "Hud", MARK)

	# Hoja: panel con borde de línea
	t.set_type_variation("Sheet", "PanelContainer")
	var sheet := _box(Color(0.03, 0.07, 0.12, 0.82), 1, Color(LINE, 0.8), Vector4(28, 24, 28, 24))
	sheet.shadow_color = Color(0, 0, 0, 0.35)
	sheet.shadow_size = 12
	t.set_stylebox("panel", "Sheet", sheet)
	t.set_type_variation("Cell", "PanelContainer")
	t.set_stylebox("panel", "Cell", _box(Color(PAPER_DEEP, 0.85), 1, LINE, Vector4(12, 6, 12, 8)))

	# Deslizador y casillas
	var track := _box(LINE, 0, LINE, Vector4(0, 2, 0, 2))
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", _box(MARK, 0, MARK, Vector4(0, 2, 0, 2)))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(MARK.lightened(0.15), 0, MARK, Vector4(0, 2, 0, 2)))
	t.set_color("font_color", "CheckButton", INK)
	t.set_color("font_hover_color", "CheckButton", INK)
	t.set_color("font_pressed_color", "CheckButton", INK)
	t.set_color("font_focus_color", "CheckButton", INK)
	t.set_color("font_hover_pressed_color", "CheckButton", INK)
	t.set_font("font", "CheckButton", font_mono_medium)
	t.set_font_size("font_size", "CheckButton", 17)
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(s, "CheckButton", _box(clear, 0, LINE, Vector4(0, 4, 0, 4)))
	t.set_stylebox("focus", "CheckButton", focus)
	return t


# ---------- Prueba automática (sin ventana) ----------

## Ranuras de partida en una carpeta aparte (no toca las partidas reales).
func _smoke_saves() -> void:
	var keep_root := _save_root
	var keep_prog := progress.duplicate(true)
	var keep_slot := slot
	_save_root = "user://saves_smoke"
	_remove_tree(_save_root)
	_smoke_io = true
	var log := []
	new_game(1, "Equipo A")
	complete_level(0, 3)
	complete_level(1, 2)
	save_design(1, [{"id": "nose_cone"}])
	var i1 := slot_info(1)
	log.append("nueva=%s estrellas=%d desbloq=%d" % [i1.name, i1.stars, i1.unlocked])
	new_game(2, "")
	log.append("ranura2_vacía_de_estrellas=%s libre=%d" % [stars_for(0) == 0, first_empty_slot()])
	load_slot(1)
	log.append("cargar1=%s diseño=%s" % [stars_for(1) == 2, FileAccess.file_exists(_design_path(1))])
	replay_tutorials(1)
	log.append("tutoriales=%s estrellas_siguen=%d" % [not bool(progress.tutorial_done), slot_info(1).stars])
	rename_slot(1, "Equipo B")
	log.append("renombrar=%s" % slot_info(1).name)
	new_game(1, "Equipo B")
	log.append("de_cero=%s sin_diseño=%s" % [slot_info(1).stars == 0, not FileAccess.file_exists(_design_path(1))])
	delete_slot(2)
	delete_slot(1)
	log.append("borradas=%s" % [slot_info(1).is_empty() and slot_info(2).is_empty()])
	print("SMOKE partidas: %s" % " ".join(log))
	if get_tree().current_scene and get_tree().current_scene.scene_file_path != SCENES.saves:
		await goto("saves")
	_remove_tree(_save_root)
	_smoke_io = false
	_save_root = keep_root
	progress = keep_prog
	slot = keep_slot
	_slot_live = false

func _run_smoke() -> void:
	print("SMOKE inicio")
	await get_tree().create_timer(0.5).timeout
	for key in ["levels", "workshop", "settings", "saves", "menu"]:
		await goto(key)
		await get_tree().create_timer(0.3).timeout
		var cur := get_tree().current_scene
		print("SMOKE escena %s -> %s" % [key, cur.name if cur else "null"])
		if cur == null:
			push_error("SMOKE la escena %s no cargó" % key)
	# Taller libre: agregar cada pieza del catálogo, editarla y quitarla
	sandbox = true
	selected_level = -1
	await goto("workshop")
	await get_tree().create_timer(0.2).timeout
	var shop := get_tree().current_scene
	var before: int = shop.design.size()
	for id in Catalog.order:
		shop._select(-1)
		shop._add_part(id)
		shop._set_param(shop.selected, "diameter", 2.0)
		await get_tree().process_frame
	print("SMOKE taller: %d piezas agregadas, diseño=%d, Δv=%.0f m/s, avisos=%d" % [Catalog.order.size(), shop.design.size(), shop.analysis.dv_total, shop.analysis.warnings.size()])
	while shop.design.size() > before:
		shop._remove(shop.design.size() - 1)
	# Arrastrar y soltar: insertar en una posición, mover y quitar
	shop._add_part("nose_cone", 0)
	var ok_insert: bool = shop.design[0].id == "nose_cone"
	shop._move_to(0, shop.design.size())
	var ok_move: bool = shop.design[-1].id == "nose_cone"
	shop._remove(shop.design.size() - 1)
	print("SMOKE arrastrar: insertar=%s mover=%s quitar=%s" % [ok_insert, ok_move, shop.design.size() == before])
	await get_tree().process_frame
	print("SMOKE taller: quitadas, diseño=%d" % shop.design.size())
	# Tutorial de la misión 0: armar el cohete paso a paso y comprobar cada condición
	sandbox = false
	selected_level = 0
	await goto("workshop")
	await get_tree().create_timer(0.3).timeout
	var tut := get_tree().current_scene
	var radio: HoustonRadio = tut.tutorial
	var log := []
	var wait := func() -> void: await get_tree().create_timer(0.4).timeout
	log.append("vacío=%s" % tut.design.is_empty())
	tut._add_part("solid_motor")
	log.append("bloqueado_paso1=%s" % tut.design.is_empty())
	radio._advance()
	radio._advance() # paso 3: solo el motor sólido
	tut._add_part("nose_cone")
	log.append("punta_bloqueada=%s" % tut.design.is_empty())
	tut._add_part("solid_motor")
	await wait.call()
	log.append("paso=%d(aletas)" % (radio._i + 1))
	tut.design[0]["fins"] = (Catalog.fins_spec.defaults as Dictionary).duplicate()
	tut._recompute()
	await wait.call()
	tut._add_part("payload_bay", 5) # el tutorial la pone arriba aunque se suelte abajo
	await wait.call()
	log.append("carga_arriba=%s" % tut._tutorial_check("payload_on_top"))
	tut._add_part("nose_ogive")
	await wait.call()
	await wait.call()
	log.append("paso=%d(plano)" % (radio._i + 1))
	tut._show_tab("plan")
	await wait.call()
	await wait.call()
	await wait.call()
	log.append("paso=%d(codex)" % (radio._i + 1))
	log.append("lanzar_bloqueado=%s" % tut._launch.disabled)
	radio._advance()
	log.append("lanzar_habilitado=%s" % (not tut._launch.disabled))
	tut._on_launch()
	await wait.call()
	log.append("terminado=%s" % bool(progress.get("tutorial_done", false)))
	print("SMOKE tutorial: %s" % " ".join(log))
	tut._show_tab("3d")
	complete_level(0, 3)
	print("SMOKE progreso: desbloqueado=%d estrellas_n0=%d" % [progress.unlocked, stars_for(0)])
	set_locale("es")
	await get_tree().process_frame
	print("SMOKE es: %s | %s | %s" % [tr("MENU_CAMPAIGN"), fmt(13.4), budget_text(level(8))])
	set_locale("en")
	await get_tree().process_frame
	print("SMOKE en: %s | %s | %s" % [tr("MENU_CAMPAIGN"), fmt(13.4), budget_text(level(8))])
	await _smoke_saves()
	# Física de los diseños por defecto
	Catalog.load_all()
	var lv_of := {"sounding": 0, "two_stage": 1}
	for rr: Dictionary in Catalog.real_rockets:
		lv_of[str(rr.id)] = maxi(int(rr.unlock_level), 1) if str(rr.id) != "mercury_redstone" else 0
	for key: String in lv_of:
		var r := RocketAnalysis.analyze(Catalog.default_designs[key], lv_of[key], false)
		var st := []
		for s in r.stages:
			st.append("E%d m0=%.0f kg dv=%.0f m/s twr=%.2f isp=%.0f" % [s.number, s.m0, s.dv, s.twr, s.isp])
		print("SMOKE %s: alto=%.1f m masa=%.0f kg dv=%.0f m/s costo=%.2f M CM=%.2f CP=%.2f estab=%.2f cal | %s" % [key, r.height, r.mass, r.dv_total, r.cost / 1e6, r.cm, r.cp, r.stability, " ; ".join(st)])
		var ws := []
		for w in r.warnings:
			ws.append(w.key)
		print("SMOKE   avisos: ", ", ".join(ws))
		var f := FlightSim.simulate(r, lv_of[key], false)
		var evs := []
		for e in f.events:
			evs.append("%s@%.0f" % [e.key, e.t])
		var mid := FlightSim.state_at(f, f.duration * 0.5)
		var last := FlightSim.state_at(f, f.duration - 5.0)
		print("SMOKE   actitud: mitad=%.0f° final=%.0f° (0 = punta arriba, 90 = de lado, 180 = punta abajo)" % [rad_to_deg(mid.att), rad_to_deg(last.att)])
		print("SMOKE   vuelo: %s éxito=%s apogeo=%.1f km vmax=%.0f m/s maxQ=%.1f kPa maxG=%.1f órbita=%s perigeo=%.0f km progreso=%.2f dur=%.0f s | %s" % [f.reason, f.success, f.apogee / 1000.0, f.max_v, f.max_q / 1000.0, f.max_g, f.orbit, f.perigee / 1000.0, f.progress, f.duration, " ".join(evs)])
	var k := RocketAnalysis.analyze([Catalog.new_part("k_nose_b"), Catalog.new_part("k_body_a"), Catalog.new_part("k_base_a")], 1, false)
	print("SMOKE kenney: alto=%.2f masa=%.0f kg estab=%.2f" % [k.height, k.mass, k.stability])
	# Pieza propia (torno) con pintura: se calcula y se construye en 3D como cualquier otra
	Catalog._register_custom({"id": "c_smoke", "name": "Smoke tank", "kind": "tank",
		"profile": [[0.6, 0.0], [1.0, 0.2], [1.0, 0.8], [0.6, 1.0]],
		"defaults": {"length": 4.0, "diameter": 1.2, "material": "aluminium", "propellant": "lox_rp1"}})
	var cdesign := [Catalog.new_part("nose_cone"), Catalog.new_part("c_smoke"), Catalog.new_part("engine")]
	cdesign[1]["paint"] = "red"
	cdesign[1]["finish"] = "gloss"
	var ca := RocketAnalysis.analyze(cdesign, 1, false)
	var built := RocketBuilder.build(cdesign, ca)
	print("SMOKE torno: alto=%.2f m masa=%.0f kg propelente=%.0f kg nodos3d=%d nombre=%s" % [ca.height, ca.mass, ca.parts[1].prop, built.get_child_count(), Catalog.display_name("c_smoke")])
	built.free()
	Catalog.parts.erase("c_smoke")
	Catalog.order.erase("c_smoke")
	# Todos los scripts del juego compilan (la prueba no abre el vuelo: así un error de sintaxis no se escapa)
	var bad := []
	for dir in ["res://scripts/core", "res://scripts/three_d", "res://scripts/ui", "res://scripts/autoload"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				var sc: GDScript = load(dir + "/" + f)
				if sc == null or not sc.can_instantiate():
					bad.append(f)
	print("SMOKE scripts: ", "todos compilan" if bad.is_empty() else "FALLAN " + str(bad))
	if not bad.is_empty():
		push_error("SMOKE FAIL scripts")
		get_tree().quit(1)
		return
	print("SMOKE OK")
	get_tree().quit()
