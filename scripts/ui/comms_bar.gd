class_name CommsBar
extends CanvasLayer
## Subtítulos de radio: Houston (u otro) habla y su línea aparece abajo, con los
## tonos Quindar al empezar y terminar. Las líneas se ponen en cola.
## Si existe assets/voice/en/<id>.ogg, se reproduce y la línea dura lo que dure el audio.

var _queue: Array = []
var _busy := false
var text_width := 820.0 ## ancho del texto (el taller lo achica para no tapar los paneles)
var shift_x := 0.0 ## corre la barra a un lado (centro del área libre de la pantalla)
## Público: true mientras haya una línea mostrándose o en cola (el vuelo lo usa para no acelerar el tiempo).
var busy := false
var _panel: PanelContainer
var _who: Label
var _text: Label
var _beep: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _tw: Tween
var _portrait: HoustonPortrait
var _top := false
var _check_t := 0.0


## Si hay una ventana abierta (nodos del grupo "modal" visibles), la radio pasa arriba para no tapar sus botones.
func _process(delta: float) -> void:
	if _portrait and _portrait.visible:
		_portrait.talking = _voice.playing
	_check_t -= delta
	if _check_t > 0.0 or _panel == null:
		return
	_check_t = 0.2
	var modal := false
	for n in get_tree().get_nodes_in_group("modal"):
		if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
			modal = true
			break
	if modal == _top:
		return
	_top = modal
	# Con una ventana abierta (centrada), la radio va a la esquina de arriba a la izquierda y más angosta
	_panel.anchor_left = 0.0 if modal else 0.5
	_panel.anchor_right = 0.0 if modal else 0.5
	_panel.anchor_top = 0.0 if modal else 1.0
	_panel.anchor_bottom = 0.0 if modal else 1.0
	_panel.offset_left = 16.0 if modal else -360.0
	_panel.offset_right = 356.0 if modal else 360.0
	_panel.offset_top = 16.0 if modal else 0.0
	_panel.offset_bottom = 16.0 if modal else -84.0
	_panel.grow_vertical = Control.GROW_DIRECTION_END if modal else Control.GROW_DIRECTION_BEGIN
	_text.add_theme_font_size_override("font_size", 14 if modal else 18)


## Corta la línea que se está diciendo y pasa a la siguiente (botón "Saltar" o Espacio).
func skip() -> void:
	if not _busy:
		return
	if _tw:
		_tw.kill()
	_voice.stop()
	_next()


func _unhandled_input(event: InputEvent) -> void:
	if _busy and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_TAB]:
		skip()
		get_viewport().set_input_as_handled()


func _ready() -> void:
	layer = 35
	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.theme = Game.theme
	add_child(anchor)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", Game._box(Color(0.02, 0.05, 0.09, 0.82), 0, Game.MARK, Vector4(20, 10, 20, 12)))
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -360 + shift_x
	_panel.offset_right = 360 + shift_x
	_panel.offset_bottom = -84 # encima de la fila de controles del HUD
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.modulate.a = 0.0
	anchor.add_child(_panel)
	# Retrato de Houston a la izquierda (su cara con la boca moviéndose mientras habla) y el texto a la derecha
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_panel.add_child(row)
	_portrait = HoustonPortrait.new(84)
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_portrait.visible = false
	row.add_child(_portrait)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	_who = Label.new()
	_who.theme_type_variation = "Eyebrow"
	_who.add_theme_color_override("font_color", Game.MARK)
	_who.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var head := HBoxContainer.new()
	_who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_who)
	var hint := Label.new()
	hint.text = "COMMS_SKIP"
	hint.theme_type_variation = "Eyebrow"
	hint.add_theme_color_override("font_color", Game.INK_DIM)
	head.add_child(hint)
	v.add_child(head)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_text.add_theme_font_size_override("font_size", 18)
	_text.add_theme_color_override("font_color", Color(1, 1, 1))
	_text.custom_minimum_size.x = text_width
	v.add_child(_text)
	_beep = AudioStreamPlayer.new()
	add_child(_beep)
	_voice = AudioStreamPlayer.new()
	add_child(_voice)


## Encola una línea. entry: {"id", "en", "es"}; speaker: texto del emisor.
func say(entry: Dictionary, speaker := "HOUSTON") -> void:
	_queue.append({"entry": entry, "speaker": speaker})
	if not _busy:
		_next()


func clear() -> void:
	_queue.clear()


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		busy = false
		var out := create_tween()
		out.tween_property(_panel, "modulate:a", 0.0, 0.3)
		return
	_busy = true
	busy = true
	var item: Dictionary = _queue.pop_front()
	var entry: Dictionary = item.entry
	_who.text = item.speaker
	_portrait.visible = "HOUSTON" in str(item.speaker).to_upper()
	_text.text = Codex.pick(entry)
	_text.visible_ratio = 0.0
	var t := create_tween()
	_tw = t
	t.tween_property(_panel, "modulate:a", 1.0, 0.2)
	t.tween_callback(HoustonRadio.quindar.bind(_beep, 2525.0))
	t.tween_property(_text, "visible_ratio", 1.0, clampf(_text.text.length() * 0.02, 0.6, 3.5))
	var dur := 2.2 + _text.text.length() * 0.045
	var path := "res://assets/voice/en/%s.ogg" % str(entry.get("id", ""))
	if HoustonRadio.voice_on() and ResourceLoader.exists(path):
		_voice.stream = load(path)
		_voice.play()
		dur = maxf(dur, _voice.stream.get_length() + 0.6)
	t.tween_interval(dur)
	t.tween_callback(HoustonRadio.quindar.bind(_beep, 2475.0))
	t.tween_interval(0.35)
	t.tween_callback(_next)
