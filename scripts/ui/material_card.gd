class_name MaterialCard
extends PanelContainer
## Ficha de un material (data/materials.json): qué es, cuatro barras comparables entre todos
## los materiales (densidad, resistencia, calor máximo, costo), a favor, en contra y dónde se usa.
## compact = versión del panel de la pieza (sin el texto largo).

var mat_id := "aluminium"
var compact := false
var _v: VBoxContainer


func _ready() -> void:
	add_theme_stylebox_override("panel", Game._box(Color(Game.PAPER_DEEP, 0.85), 1, Game.LINE, Vector4(14, 10, 14, 12)))
	_v = VBoxContainer.new()
	_v.add_theme_constant_override("separation", 4)
	add_child(_v)
	refresh()


func refresh() -> void:
	if _v == null:
		return
	for c in _v.get_children():
		c.queue_free()
	var m: Dictionary = Catalog.materials.get(mat_id, {})
	if m.is_empty():
		return
	if not compact:
		var name_l := _l(Codex.pick(m.get("name")), "Title", 24)
		_v.add_child(name_l)
		var what := _l(Codex.pick(m.get("what")), "Body", 13)
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_v.add_child(what)
	# Máximos entre todos los materiales, para que las barras se puedan comparar
	var mx := {"density_kg_m3": 1.0, "strength": 1.0, "max_temp_c": 1.0, "cost_usd_per_kg": 1.0}
	for o: Dictionary in Catalog.materials.values():
		for k in mx:
			mx[k] = maxf(float(mx[k]), float(o.get(k, 0.0)))
	_bar("MAT_DENSITY", float(m.density_kg_m3) / float(mx.density_kg_m3), "%s kg/m³" % Game.fmt(float(m.density_kg_m3), 0), false)
	_bar("MAT_STRENGTH", float(m.strength) / float(mx.strength), "%s %s" % [Game.fmt(float(m.strength), 2), tr("MAT_VS_AL")], true)
	_bar("MAT_HEAT", float(m.max_temp_c) / float(mx.max_temp_c), "%d °C" % int(m.max_temp_c), true)
	_bar("MAT_COST", float(m.cost_usd_per_kg) / float(mx.cost_usd_per_kg), "US$ %d/kg" % int(m.cost_usd_per_kg), false)
	_pair("MAT_PROS", Codex.pick(m.get("pros")), Game.GOOD)
	_pair("MAT_CONS", Codex.pick(m.get("cons")), Game.MARK)
	if not compact:
		_pair("MAT_USED", Codex.pick(m.get("used")), Game.INK_DIM)


func _l(text: String, variation: String, fs: int) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_size_override("font_size", fs)
	return l


## Barra 0..1; good_high = true si más es mejor (verde), false si más es peor (naranja).
func _bar(key: String, k: float, value: String, good_high: bool) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var cap := _l(tr(key).to_upper(), "Eyebrow", 11)
	cap.custom_minimum_size.x = 92
	h.add_child(cap)
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.value = clampf(k, 0.04, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(60, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var good := k >= 0.5 if good_high else k < 0.5
	var col := Game.GOOD if good else Game.MARK
	bar.add_theme_stylebox_override("background", Game._box(Color(Game.LINE, 0.5), 0, Game.LINE, Vector4.ZERO))
	bar.add_theme_stylebox_override("fill", Game._box(col, 0, col, Vector4.ZERO))
	h.add_child(bar)
	var val := _l(value, "Body", 12)
	val.add_theme_font_override("font", Game.font_mono_medium)
	val.custom_minimum_size.x = 120
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	_v.add_child(h)


func _pair(key: String, text: String, col: Color) -> void:
	if text == "":
		return
	var l := _l(tr(key) + ": " + text, "Body", 12)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", col)
	_v.add_child(l)
