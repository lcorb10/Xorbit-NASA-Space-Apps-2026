extends Control
## Menú principal: opciones a la izquierda, plano del cohete a la derecha
## y cartela (cuadro de rótulo) con el selector de idioma abajo a la derecha.

var _hint: Label
var _credits: Control
var _lang_buttons := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new()) # plataforma 39A en 3D con un Saturno V, cámara girando

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 88)
	margin.add_theme_constant_override("margin_top", 64)
	margin.add_theme_constant_override("margin_bottom", 56)
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	margin.add_child(row)

	# ---- Columna izquierda: título y opciones ----
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.9
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)

	left.add_child(_label("MENU_EYEBROW", "Eyebrow"))
	# Logo del juego (assets/ui/xorbit_logo.png, fondo quitado)
	var title := TextureRect.new()
	title.texture = load("res://assets/ui/xorbit_logo.png")
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	title.custom_minimum_size = Vector2(560, 560.0 * 190.0 / 1140.0)
	title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(title)
	var tag := _label("MENU_TAGLINE", "Lead")
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.custom_minimum_size.x = 420
	left.add_child(tag)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 18
	left.add_child(spacer)

	_hint = _label("", "Hint")
	var items := VBoxContainer.new()
	items.add_theme_constant_override("separation", 2)
	left.add_child(items)
	# Partida: seguir la de la ranura en uso, o empezar una nueva si está vacía
	var first: Button
	if Game.slot_exists(Game.slot):
		var info := Game.slot_info(Game.slot)
		var nm := str(info.get("name", ""))
		if nm == "":
			nm = tr("SV_SLOT") % Game.slot
		var hint := tr("MENU_CONTINUE_HINT") % [nm, int(info.unlocked), int(info.stars)]
		first = _item(items, "MENU_CONTINUE", func() -> void:
			Game.sandbox = false
			Game.goto("levels"), hint)
	else:
		first = _item(items, "MENU_NEW_GAME", func() -> void:
			Game.new_game(Game.slot, "")
			Game.sandbox = false
			Game.goto("levels"))
	_item(items, "MENU_SAVES", func() -> void: Game.goto("saves"))
	_item(items, "MENU_SANDBOX", func() -> void:
		Game.sandbox = true
		Game.selected_level = -1
		Game.goto("workshop"))
	# Tripulación: sala "¿Quién vuela?" (1 a 4 jugadores) y después las misiones
	_item(items, "MENU_TEAM", func() -> void:
		var lobby := CrewLobby.new()
		lobby.theme = Game.theme
		lobby.started.connect(func() -> void: Game.goto("levels"))
		add_child(lobby))
	_item(items, "MENU_SETTINGS", func() -> void: Game.goto("settings"))
	_item(items, "MENU_CREDITS", _open_credits)
	_item(items, "MENU_QUIT", func() -> void: get_tree().quit())

	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(420, 40)
	var hint_gap := Control.new()
	hint_gap.custom_minimum_size.y = 8
	left.add_child(hint_gap)
	left.add_child(_hint)

	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(fill)
	var foot := _label("v%s · Godot 4.7" % ProjectSettings.get_setting("application/config/version"), "Eyebrow")
	foot.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	left.add_child(foot)

	# ---- Columna derecha: plano y cartela ----
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.1
	right.add_theme_constant_override("separation", 16)
	row.add_child(right)
	var schem := RocketSchematic.new()
	schem.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(schem)
	schem.modulate.a = 0.0 # el cohete 3D de fondo ocupa su lugar; el plano queda para el taller
	right.add_child(_title_block())

	_credits = _build_credits()
	_credits.visible = false
	add_child(_credits)

	# Diferido; se omite si la escena ya se cambió (p. ej. con --goto)
	(func() -> void:
		if first.is_inside_tree():
			first.grab_focus()).call_deferred()
	if "--credits" in OS.get_cmdline_user_args():
		_open_credits.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _credits.visible:
		_close_credits()
		get_viewport().set_input_as_handled()


# ---------- Piezas ----------

func _label(text: String, variation: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l


func _item(parent: Control, key: String, action: Callable, hint := "") -> Button:
	var b := Button.new()
	b.text = key
	b.theme_type_variation = "MenuItem"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.x = 380
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if action.is_valid():
		b.pressed.connect(action)
	var show_hint := func() -> void: _hint.text = hint if hint != "" else key + "_HINT"
	b.focus_entered.connect(show_hint)
	b.mouse_entered.connect(show_hint)
	parent.add_child(b)
	return b


func _soon_tag(b: Button) -> void:
	var tag := Label.new()
	tag.text = "MENU_SOON"
	tag.theme_type_variation = "Eyebrow"
	tag.add_theme_color_override("font_color", Game.MARK)
	b.add_child(tag)
	# Justo después del texto del botón (se recalcula al cambiar de idioma)
	var place := func() -> void:
		var w := Game.font_display.get_string_size(tr(b.text), HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x
		tag.position = Vector2(20 + w + 14, (b.size.y - tag.size.y) / 2.0 + 4)
	b.resized.connect(place)
	b.item_rect_changed.connect(place)
	tag.resized.connect(place)
	place.call_deferred()


func _title_block() -> Control:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", -1)
	grid.add_theme_constant_override("v_separation", -1)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_END
	grid.add_child(_cell("TB_PROJECT", "Xorbit", 150))
	grid.add_child(_cell("TB_REV", "0.1", 90))
	grid.add_child(_cell("TB_SCALE", "1 : 1", 110))

	var lang := PanelContainer.new()
	lang.theme_type_variation = "Cell"
	lang.custom_minimum_size.x = 170
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	lv.add_child(_label("TB_LANG", "Eyebrow"))
	var lh := HBoxContainer.new()
	lh.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for loc in Game.LOCALES:
		var b := Button.new()
		b.text = loc.to_upper()
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = Game.settings.locale == loc
		b.custom_minimum_size = Vector2(56, 30)
		b.pressed.connect(func() -> void: Game.set_locale(loc))
		lh.add_child(b)
		_lang_buttons[loc] = b
	lv.add_child(lh)
	lang.add_child(lv)
	grid.add_child(lang)

	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_END
	wrap.add_theme_constant_override("separation", -1)
	wrap.add_child(grid)
	var drawn := _cell("TB_DRAWN", "Sebastián · María Cecilia", 0)
	wrap.add_child(drawn)
	return wrap


func _cell(caption: String, value: String, min_w: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "Cell"
	p.custom_minimum_size.x = min_w
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.add_child(_label(caption, "Eyebrow"))
	var val := _label(value, "Body")
	val.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	val.add_theme_font_override("font", Game.font_mono_medium)
	v.add_child(val)
	p.add_child(v)
	return p


# ---------- Créditos ----------

func _build_credits() -> Control:
	var veil := ColorRect.new()
	veil.color = Color(Game.PAPER_DEEP, 0.82)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.add_child(center)
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = "Sheet"
	sheet.custom_minimum_size.x = 760
	center.add_child(sheet)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	sheet.add_child(v)

	var t := _label("CR_TITLE", "Title")
	t.add_theme_font_size_override("font_size", 52)
	v.add_child(t)
	_credit_block(v, "CR_TEAM", ["Sebastián", "María Cecilia"])
	_credit_block(v, "CR_IDEAS", ["Mr. Warner", "Kerbal Space Program (mechanics inspiration)", "The Open Space Program (MIT)"])
	_credit_block(v, "CR_DATA", [
		"Planetary Fact Sheet · NSSDC / Goddard",
		"Apollo Experience Report: Descent Propulsion System · NTRS",
		"NSTAR Ion Thruster · NASA Glenn",
		"MMRTG Fact Sheet · NASA / DOE",
		"Blue Marble Next Generation, City Lights 2012 · NASA Earth Observatory",
		"Launch sounds, Apollo 11 countdown · NASA Audio (public domain)",
	])
	_credit_block(v, "CR_OTHER", [
		"oddurs/tsi · engine database (MIT)",
		"Barlow Condensed, IBM Plex Mono · SIL Open Font License",
		"Kenney Space Kit · 3D models (CC0)",
		"Poly Haven · PBR textures and sky HDRI (CC0)",
		"OpenGameArt · music by yd, Centurion_of_war, Yoiyami, vitalezzz, Ville Nousiainen & XCVG, cynicmusic, allen yatsura (CC0)",
		"Houston voice · generated with VoiceStudio (OmniVoice)",
		"NASA 3D Resources · Saturn V, Space Shuttle, Jupiter-C, Crawler, VAB, Apollo LM, Apollo-Soyuz, LRO, GOES, Perseverance, Juno, Voyager",
		"Quaternius · Animated Man / Woman, ground crew (CC0)",
		"Quaternius · Universal Animation Library 1 & 2, crew astronauts (CC0)",
		"ambientCG · cabin PBR materials (CC0)",
		"NASA 3D Resources · JSC Mission Control Room",
		"MakeHuman community assets (CC0) via MPFB2 · Houston",
		"Solar System Scope · planet and Milky Way textures (CC BY 4.0)",
		"Godot Engine 4.7 (MIT)",
	])
	var disc := _label("CR_DISCLAIMER", "Hint")
	disc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(disc)
	var close := Button.new()
	close.name = "Close"
	close.text = "CR_CLOSE"
	close.custom_minimum_size = Vector2(140, 40)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(_close_credits)
	v.add_child(close)
	return veil


func _credit_block(parent: Control, caption: String, lines: Array) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	parent.add_child(gap)
	parent.add_child(_label(caption, "Eyebrow"))
	for line in lines:
		var l := _label(line, "Body")
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		parent.add_child(l)


func _open_credits() -> void:
	_credits.visible = true
	_credits.find_child("Close", true, false).grab_focus()


func _close_credits() -> void:
	_credits.visible = false
	var items := find_children("*", "Button", true, false)
	for b: Button in items:
		if b.text == "MENU_CREDITS":
			b.grab_focus()
			return
