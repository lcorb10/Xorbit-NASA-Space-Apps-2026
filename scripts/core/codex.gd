class_name Codex
extends RefCounted
## Explicaciones del juego (data/codex.json) en el idioma activo.

static var _data := {}


static func _load() -> void:
	if not _data.is_empty():
		return
	var f := FileAccess.open("res://data/codex.json", FileAccess.READ)
	if f:
		var v: Variant = JSON.parse_string(f.get_as_text())
		if v is Dictionary:
			_data = v


static func pick(entry: Variant) -> String:
	if not entry is Dictionary:
		return ""
	var loc := TranslationServer.get_locale().substr(0, 2)
	return str(entry.get(loc, entry.get("en", "")))


## what / how / real de un tipo de pieza (nose, tank, fins…).
static func part(kind: String, field: String) -> String:
	_load()
	return pick(_data.get("parts", {}).get(kind, {}).get(field))


static func concepts() -> Array:
	_load()
	return _data.get("concepts", [])


static func concept(id: String) -> Dictionary:
	for c in concepts():
		if c.id == id:
			return c
	return {}


## Texto de ayuda para un concepto: "Título: explicación".
static func tip(id: String) -> String:
	var c := concept(id)
	if c.is_empty():
		return ""
	return "%s\n%s" % [pick(c.title), pick(c.body)]


## Sección "Cómo se arma un cohete": {title, intro, steps: [{title, body}], rules}.
static func build() -> Dictionary:
	_load()
	return _data.get("build", {})


static func materials_intro() -> Dictionary:
	_load()
	return _data.get("materials_intro", {})
