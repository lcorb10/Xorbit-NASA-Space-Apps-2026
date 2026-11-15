class_name Catalog
extends RefCounted
## Catálogo de piezas, materiales, propelentes y motores.
## Une nuestras piezas (data/parts.json) con las importadas de internet
## (data/parts_imported.json): todas quedan como plantillas con los mismos campos.

const WALL_BY_KIND := {"nose": 0.003, "payload": 0.003, "tank": 0.006, "solid": 0.004,
	"engine": 0.004, "decoupler": 0.004, "adapter": 0.003}

static var parts := {}
static var order: Array[String] = []
static var materials := {}
static var propellants := {}
static var engines := {}
static var fins_spec := {}
static var fixed := {}
static var default_designs := {}
static var real_rockets: Array = []
static var sources := {}
static var _loaded := false


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var pj := _json("res://data/parts.json")
	for p: Dictionary in pj.get("parts", []):
		p["source"] = "own"
		parts[p.id] = p
		order.append(p.id)
	fins_spec = pj.get("fins", {})
	fixed = pj.get("fixed_mass_kg", {})
	default_designs = pj.get("default_designs", {})
	real_rockets = pj.get("real_rockets", [])

	var imp := _json("res://data/parts_imported.json")
	sources["kenney"] = imp.get("_source", {})
	for p: Dictionary in imp.get("parts", []):
		var kind: String = p.kind
		var d := 0.6 if int(p.unlock_level) == 0 else 1.2
		var defaults := {"length": snappedf(float(p.aspect) * d, 0.05), "diameter": d, "material": "aluminium"}
		match kind:
			"tank":
				defaults["propellant"] = "lox_rp1"
			"engine":
				defaults["engine"] = "rutherford"
				defaults["count"] = 1
			"payload":
				defaults["payload_kg"] = 50
		if p.get("fins") != null:
			var f: Dictionary = p.fins
			defaults["fins"] = {"count": 4, "span": snappedf(float(f.span) * d, 0.01),
				"root": snappedf(float(f.root) * defaults.length, 0.01),
				"tip": snappedf(float(f.tip) * defaults.length, 0.01),
				"offset": snappedf(float(f.bottom_offset) * defaults.length, 0.01)}
		parts[p.id] = {"id": p.id, "kind": kind, "unlock_level": p.unlock_level, "profile": p.profile,
			"aspect": p.aspect, "source": "kenney", "wall_m": WALL_BY_KIND.get(kind, 0.004),
			"model": "res://assets/models/kenney_space_kit/" + str(p.file), "defaults": defaults,
			"model_radius": p.get("model_radius", 0.5), "model_height": p.get("model_height", 1.0),
			"model_center": p.get("model_center", [0, 0, 0])}
		order.append(p.id)

	_load_custom()

	for m: Dictionary in _json("res://data/materials.json").get("materials", []):
		materials[m.id] = m
	for p: Dictionary in _json("res://data/propellants.json").get("propellants", []):
		propellants[p.id] = p
	for e: Dictionary in _json("res://data/engines.json").get("engines", []):
		engines[e.id] = e


const CUSTOM_PATH := "user://custom_parts.json"


## Piezas dibujadas por el jugador en el torno: perfiles como cualquier otra pieza.
static func _load_custom() -> void:
	var f := FileAccess.open(CUSTOM_PATH, FileAccess.READ)
	if f == null:
		return
	var arr: Variant = JSON.parse_string(f.get_as_text())
	if not arr is Array:
		return
	for c: Dictionary in arr:
		_register_custom(c)


static func _register_custom(c: Dictionary) -> void:
	var prof: Array = c.get("profile", [])
	var d := float(c.defaults.get("diameter", 1.0))
	var l := float(c.defaults.get("length", 1.0))
	parts[c.id] = {"id": c.id, "kind": c.kind, "unlock_level": 0, "profile": prof, "aspect": l / d,
		"source": "custom", "name": c.get("name", "?"), "wall_m": WALL_BY_KIND.get(c.kind, 0.004),
		"defaults": c.defaults}
	if not order.has(c.id):
		order.append(c.id)


static func custom_list() -> Array:
	var f := FileAccess.open(CUSTOM_PATH, FileAccess.READ)
	if f == null:
		return []
	var arr: Variant = JSON.parse_string(f.get_as_text())
	return arr if arr is Array else []


static func save_custom(c: Dictionary) -> void:
	var arr := custom_list().filter(func(x: Dictionary) -> bool: return x.id != c.id)
	arr.append(c)
	var f := FileAccess.open(CUSTOM_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(arr))
	_register_custom(c)


static func delete_custom(id: String) -> void:
	var arr := custom_list().filter(func(x: Dictionary) -> bool: return x.id != id)
	var f := FileAccess.open(CUSTOM_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(arr))
	parts.erase(id)
	order.erase(id)


## Nombre para mostrar: el que le puso el jugador o el texto traducido.
static func display_name(id: String) -> String:
	var t := template(id)
	if t.has("name"):
		return str(t.name)
	return TranslationServer.translate("PART_" + id)


static func template(id: String) -> Dictionary:
	return parts.get(id, {})


## Pieza nueva lista para poner en el cohete, con sus valores por defecto.
static func new_part(id: String) -> Dictionary:
	var t := template(id)
	var p: Dictionary = (t.get("defaults", {}) as Dictionary).duplicate(true)
	p["id"] = id
	return p


static func unlocked_parts(level: int, all: bool) -> Array[String]:
	var out: Array[String] = []
	for id in order:
		if all or int(parts[id].unlock_level) <= level:
			out.append(id)
	return out


static func unlocked(dict: Dictionary, level: int, all: bool) -> Array:
	var out := []
	for id in dict:
		var u: Variant = dict[id].get("unlock_level", 0)
		if all or (u != null and int(u) <= level):
			out.append(id)
	return out


static func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("No se pudo abrir %s" % path)
		return {}
	var v: Variant = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}
