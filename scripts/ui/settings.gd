extends Control
## Ajustes: idioma, pantalla completa, volumen, calidad y acceso a las partidas guardadas.

var _vol_value: Label
var overlay := false ## true: abierto desde la pausa del juego (sin fondo 3D; Volver lo cierra en vez de ir al menú)
signal closed


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.09, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if overlay:
		add_to_group("modal")
		process_mode = Node.PROCESS_MODE_ALWAYS
		dim.color.a = 0.85
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(dim)
	else:
		add_child(MenuBackdrop.new()) # misma plataforma 3D que el menú, atenuada para leer
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child.call_deferred(dim)
		move_child.call_deferred(dim, 1)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = "Sheet"
	sheet.custom_minimum_size.x = 860
	center.add_child(sheet)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	sheet.add_child(outer)

	var t := _label("SET_TITLE", "Title")
	t.add_theme_font_size_override("font_size", 56)
	outer.add_child(t)
	# Dos columnas: todo cabe en 720 p sin desplazarse (sonido e imagen a la izquierda, juego a la derecha)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	outer.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.custom_minimum_size.x = 420
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.custom_minimum_size.x = 340
	cols.add_child(right)
	var v := left

	# Idioma
	v.add_child(_label("SET_LANGUAGE", "Eyebrow"))
	var lh := HBoxContainer.new()
	lh.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	var first: Button
	for pair in [["en", "English"], ["es", "Español"]]:
		var b := Button.new()
		b.text = pair[1]
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = Game.settings.locale == pair[0]
		b.custom_minimum_size = Vector2(150, 40)
		var loc: String = pair[0]
		b.pressed.connect(func() -> void: Game.set_locale(loc))
		lh.add_child(b)
		if b.button_pressed:
			first = b
	v.add_child(lh)

	# Pantalla
	v.add_child(_gap())
	v.add_child(_label("SET_DISPLAY", "Eyebrow"))
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 8)
	var dgroup := ButtonGroup.new()
	for pair in [["SET_WINDOWED", false], ["SET_FULLSCREEN", true]]:
		var b := Button.new()
		b.text = pair[0]
		b.toggle_mode = true
		b.button_group = dgroup
		b.button_pressed = bool(Game.settings.fullscreen) == pair[1]
		b.custom_minimum_size = Vector2(150, 40)
		var on: bool = pair[1]
		b.pressed.connect(func() -> void: Game.set_fullscreen(on))
		dh.add_child(b)
	v.add_child(dh)

	# Volumen
	v.add_child(_gap())
	v.add_child(_label("SET_VOLUME", "Eyebrow"))
	var vh := HBoxContainer.new()
	vh.add_theme_constant_override("separation", 16)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = float(Game.settings.volume) * 100.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_vol_value = _label("", "Body")
	_vol_value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_vol_value.custom_minimum_size.x = 56
	_vol_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(func(x: float) -> void:
		_vol_value.text = "%d %%" % int(x)
		Game.set_volume(x / 100.0))
	_vol_value.text = "%d %%" % int(slider.value)
	vh.add_child(slider)
	vh.add_child(_vol_value)
	v.add_child(vh)
	# Música (aparte del volumen general)
	v.add_child(_label("SET_MUSIC", "Eyebrow"))
	var mh := HBoxContainer.new()
	mh.add_theme_constant_override("separation", 16)
	var ms := HSlider.new()
	ms.min_value = 0
	ms.max_value = 100
	ms.step = 5
	ms.value = float(Game.settings.get("music", 0.6)) * 100.0
	ms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ms.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mv := _label("", "Body")
	mv.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	mv.custom_minimum_size.x = 56
	mv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mv.text = "%d %%" % int(ms.value)
	ms.value_changed.connect(func(x: float) -> void:
		mv.text = "%d %%" % int(x)
		Game.set_music(x / 100.0))
	mh.add_child(ms)
	mh.add_child(mv)
	v.add_child(mh)

	v = right
	# Voz de Houston
	v.add_child(_gap())
	v.add_child(_label("SET_VOICE", "Eyebrow"))
	var voice_row := HBoxContainer.new()
	voice_row.add_theme_constant_override("separation", 8)
	var voice_group := ButtonGroup.new()
	for pair in [["SET_VOICE_ON", true], ["SET_VOICE_OFF", false]]:
		var b := Button.new()
		b.text = pair[0]
		b.toggle_mode = true
		b.button_group = voice_group
		b.button_pressed = HoustonRadio.voice_on() == pair[1]
		b.custom_minimum_size = Vector2(150, 40)
		var on: bool = pair[1]
		b.pressed.connect(func() -> void: Game.set_voice(on))
		voice_row.add_child(b)
	v.add_child(voice_row)

	# Hora del día en el Centro Espacial
	v.add_child(_gap())
	v.add_child(_label("SET_TIME", "Eyebrow"))
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 8)
	var time_group := ButtonGroup.new()
	for pair in [["SET_DAY", false], ["SET_NIGHT", true]]:
		var b := Button.new()
		b.text = pair[0]
		b.toggle_mode = true
		b.button_group = time_group
		b.button_pressed = bool(Game.settings.get("night", false)) == pair[1]
		b.custom_minimum_size = Vector2(150, 40)
		var on: bool = pair[1]
		b.pressed.connect(func() -> void: Game.set_night(on))
		time_row.add_child(b)
	v.add_child(time_row)

	# Calidad gráfica (se aplica al entrar al hangar / vuelo)
	v.add_child(_gap())
	v.add_child(_label("SET_QUALITY", "Eyebrow"))
	var qh := HBoxContainer.new()
	qh.add_theme_constant_override("separation", 8)
	var qgroup := ButtonGroup.new()
	for pair in [["SET_QUALITY_HIGH", "high"], ["SET_QUALITY_MEDIUM", "medium"]]:
		var b := Button.new()
		b.text = pair[0]
		b.toggle_mode = true
		b.button_group = qgroup
		b.button_pressed = str(Game.settings.get("quality", "high")) == pair[1]
		b.custom_minimum_size = Vector2(150, 40)
		var q: String = pair[1]
		b.pressed.connect(func() -> void: Game.set_quality(q))
		qh.add_child(b)
	v.add_child(qh)

	# Progreso (confirmación en el mismo botón)
	v.add_child(_gap())
	var prog := _label("SET_PROGRESS", "Eyebrow")
	prog.visible = not overlay
	v.add_child(prog)
	var saves := Button.new()
	saves.text = "SET_SAVES"
	saves.custom_minimum_size.y = 40
	saves.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	saves.pressed.connect(func() -> void: Game.goto("saves"))
	v.add_child(saves)
	saves.visible = not overlay # desde la pausa no se sale del vuelo

	v.add_child(_gap())
	var back := Button.new()
	back.text = "UI_BACK"
	back.custom_minimum_size = Vector2(140, 40)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.pressed.connect(_back)
	outer.add_child(back)

	first.grab_focus.call_deferred()


func _back() -> void:
	if overlay:
		closed.emit()
		queue_free()
	else:
		Game.goto("menu")


func _input(event: InputEvent) -> void:
	# Esc cierra los ajustes (antes que la pausa del vuelo, que escucha después)
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()


func _gap() -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = 4
	return c


func _label(text: String, variation: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l
