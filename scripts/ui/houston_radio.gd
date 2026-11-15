class_name HoustonRadio
extends CanvasLayer
## Tutorial guiado por Houston: panel de radio con texto que se escribe solo,
## tonos Quindar de la NASA al abrir y cerrar cada mensaje, y un marco que
## resalta la parte de la pantalla que hay que usar.
## Cada paso avanza con «Siguiente» o cuando se cumple su condición.
## Voz: si existe assets/voice/en/<id>.ogg, se reproduce.

signal finished
signal step_changed(step: Dictionary)

var steps: Array = []
var targets := {} # nombre -> Control a resaltar
var check: Callable # func(cond: String) -> bool

var _i := -1
var _panel: PanelContainer
var _text: Label
var _call: Label
var _next: Button
var _wait: Label
var _frame: Control
var _tween: Tween
var _beep: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _poll := 0.0
var _mute: Button
var _data := {}
## ¿Hay tutorial guiado para esta misión en data/tutorial.json → levels?
static func has_level(lvl: int) -> bool:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tutorial.json"))
	return (d.get("levels", {}) as Dictionary).has(str(lvl))


var level_key := "0" # "0" = tutorial de la misión 0; "1", "2" = data/tutorial.json → levels


func _ready() -> void:
	layer = 40
	var f := FileAccess.open("res://data/tutorial.json", FileAccess.READ)
	_data = JSON.parse_string(f.get_as_text()) if f else {}
	steps = _data.get("steps", [])
	if level_key != "0":
		steps = _data.get("levels", {}).get(level_key, {}).get("steps", [])

	_frame = HighlightFrame.new()
	add_child(_frame)

	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.theme = Game.theme # una CanvasLayer no hereda el tema de la ventana
	add_child(anchor)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", Game._box(Color(Game.PAPER_DEEP, 0.96), 2, Game.MARK, Vector4(22, 16, 22, 16)))
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -390
	_panel.offset_right = 390
	_panel.offset_bottom = -54
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	anchor.add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_panel.add_child(row)
	var icon := RadioIcon.new()
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	row.add_child(col)
	_call = Label.new()
	_call.theme_type_variation = "Eyebrow"
	_call.add_theme_color_override("font_color", Game.MARK)
	col.add_child(_call)
	_text = Label.new()
	_text.theme_type_variation = "Body"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_text.custom_minimum_size = Vector2(560, 0)
	_text.add_theme_font_size_override("font_size", 16)
	col.add_child(_text)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	col.add_child(bottom)
	_mute = Button.new()
	_mute.flat = true
	_mute.add_theme_color_override("font_color", Game.INK_DIM)
	_mute.pressed.connect(_toggle_voice)
	_update_mute()
	bottom.add_child(_mute)
	var skip := Button.new()
	skip.text = "TUT_SKIP"
	skip.flat = true
	skip.add_theme_color_override("font_color", Game.INK_DIM)
	skip.pressed.connect(_finish)
	bottom.add_child(skip)
	_wait = Label.new()
	_wait.theme_type_variation = "Hint"
	_wait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_wait.add_theme_font_size_override("font_size", 13)
	bottom.add_child(_wait)
	_next = Button.new()
	_next.text = "TUT_NEXT"
	_next.theme_type_variation = "Primary"
	_next.add_theme_font_size_override("font_size", 22)
	_next.pressed.connect(_advance)
	bottom.add_child(_next)

	_beep = AudioStreamPlayer.new()
	add_child(_beep)
	_voice = AudioStreamPlayer.new()
	add_child(_voice)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tutstep="):
			_i = int(arg.trim_prefix("--tutstep=")) - 2
	_advance()


func _process(delta: float) -> void:
	if _i < 0 or _i >= steps.size():
		return
	var s: Dictionary = steps[_i]
	var t: Control = targets.get(s.get("target", ""))
	var hf := _frame as HighlightFrame
	var tgt: Control = t if t != null and t.is_visible_in_tree() else null
	if hf.target != tgt:
		hf.target = tgt
		hf.label = Codex.pick(s.point) if s.has("point") else ""
		# Si la pieza señalada está fuera de la vista de una lista, desplazarla hasta verla
		var sc := tgt.get_parent() if tgt else null
		while sc != null and not (sc is ScrollContainer):
			sc = sc.get_parent()
		if sc:
			(sc as ScrollContainer).ensure_control_visible(tgt)
	_poll -= delta
	if _poll <= 0.0 and s.has("until") and check.is_valid():
		_poll = 0.25
		if check.call(s.until):
			_advance()


func _advance() -> void:
	if _i >= 0:
		_play_tone(2475.0) # tono Quindar de fin de mensaje
	_i += 1
	if _i >= steps.size():
		_finish()
		return
	var s: Dictionary = steps[_i]
	_call.text = Codex.pick(_data.get("callsign", {}))
	_text.text = Codex.pick(s.text)
	_text.visible_ratio = 0.0
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(0.3)
	_tween.tween_callback(_play_tone.bind(2525.0)) # tono Quindar de inicio
	_tween.tween_property(_text, "visible_ratio", 1.0, clampf(_text.text.length() * 0.022, 0.8, 4.5))
	step_changed.emit(s)
	var waits := s.has("until")
	_next.visible = not waits
	_wait.text = tr("TUT_WAITING") if waits else ""
	_play_voice(str(s.id))


func _finish() -> void:
	(_frame as HighlightFrame).target = null
	_play_tone(2475.0)
	step_changed.emit({})
	finished.emit()
	var t := create_tween()
	t.tween_property(_panel, "modulate:a", 0.0, 0.3)
	t.tween_callback(queue_free)


## Silenciar o activar la voz de Houston (se guarda en los ajustes).
func _toggle_voice() -> void:
	Game.set_voice(not voice_on())
	_update_mute()
	if voice_on() and _i >= 0 and _i < steps.size():
		_play_voice(str(steps[_i].id))
	else:
		_voice.stop()


func _update_mute() -> void:
	_mute.text = "TUT_VOICE_ON" if voice_on() else "TUT_VOICE_OFF"


static func voice_on() -> bool:
	return bool(Game.settings.get("voice", true))


func _play_voice(id: String) -> void:
	var path := "res://assets/voice/en/%s.ogg" % id
	if voice_on() and ResourceLoader.exists(path):
		_voice.stream = load(path)
		_voice.play()


func _play_tone(freq: float) -> void:
	quindar(_beep, freq)


## Tono Quindar: 250 ms de seno puro, como los de las comunicaciones del Apolo.
static func quindar(player: AudioStreamPlayer, freq: float) -> void:
	var rate := 22050
	var n := int(rate * 0.25)
	var data := PackedByteArray()
	data.resize(n * 2)
	for k in n:
		var env := minf(1.0, minf(k, n - k) / 300.0)
		var v := int(sin(TAU * freq * k / rate) * 9000.0 * env)
		data.encode_s16(k * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	player.stream = wav
	player.volume_db = -10.0
	player.play()


## Señala la parte de la pantalla que hay que usar: oscurece el resto, dibuja un marco que late
## y una flecha con una etiqueta corta ("Arrastra esto al soporte").
class HighlightFrame extends Control:
	var target: Control = null:
		set(v):
			target = v
			queue_redraw()
	var label := ""
	var _t := 0.0

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		if target != null:
			queue_redraw()

	func _draw() -> void:
		if target == null:
			return
		var r := target.get_global_rect().grow(6.0)
		var full := get_viewport_rect()
		# Oscurecer todo menos lo señalado (cuatro franjas alrededor)
		var dim := Color(0.0, 0.02, 0.05, 0.42)
		draw_rect(Rect2(full.position, Vector2(full.size.x, maxf(r.position.y, 0.0))), dim)
		draw_rect(Rect2(Vector2(0, r.end.y), Vector2(full.size.x, maxf(full.size.y - r.end.y, 0.0))), dim)
		draw_rect(Rect2(Vector2(0, r.position.y), Vector2(maxf(r.position.x, 0.0), r.size.y)), dim)
		draw_rect(Rect2(Vector2(r.end.x, r.position.y), Vector2(maxf(full.size.x - r.end.x, 0.0), r.size.y)), dim)
		var a := 0.55 + 0.45 * sin(_t * 4.0)
		draw_rect(r, Color(Game.MARK, a), false, 3.0)
		draw_rect(r.grow(5.0), Color(Game.MARK, a * 0.35), false, 2.0)
		# Flecha que rebota hacia el objetivo, desde el lado con más espacio
		var bob := sin(_t * 5.0) * 6.0
		var font := Game.font_mono_medium
		var fs := 16
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if label != "" else 0.0
		var right_side := r.end.x + 170.0 + tw < full.size.x
		var tip: Vector2
		var dir: Vector2
		if r.size.x > full.size.x * 0.5 and r.size.y > full.size.y * 0.5:
			tip = r.get_center() + Vector2(0, -40)
			dir = Vector2(0, -1)
		elif right_side:
			tip = Vector2(r.end.x + 8.0 + bob, r.get_center().y)
			dir = Vector2(1, 0)
		else:
			tip = Vector2(r.position.x - 8.0 - bob, r.get_center().y)
			dir = Vector2(-1, 0)
		var tail := tip + dir * 60.0
		draw_line(tail, tip + dir * 6.0, Game.MARK, 5.0, true)
		var n := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([tip, tip + dir * 20.0 + n * 12.0, tip + dir * 20.0 - n * 12.0]), Game.MARK)
		if label != "":
			var box_pos := tail + dir * 8.0
			var box := Rect2(box_pos, Vector2(tw + 24.0, 32.0))
			if dir.x < 0.0:
				box.position.x -= box.size.x
			box.position.y -= 16.0
			draw_rect(box, Game.MARK)
			draw_string(font, box.position + Vector2(12, 22), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Game.PAPER_DEEP)


## Ícono de radio: auriculares con ondas.
class RadioIcon extends Control:
	var _t := 0.0

	func _ready() -> void:
		custom_minimum_size = Vector2(64, 64)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := Vector2(32, 34)
		draw_arc(c, 18, PI * 1.05, PI * 1.95, 24, Game.INK, 3.0, true)
		draw_rect(Rect2(c + Vector2(-22, -2), Vector2(9, 15)), Game.INK)
		draw_rect(Rect2(c + Vector2(13, -2), Vector2(9, 15)), Game.INK)
		draw_line(c + Vector2(-17, 13), c + Vector2(-6, 22), Game.INK, 2.0)
		draw_circle(c + Vector2(-4, 23), 3.0, Game.MARK)
		for k in 3:
			var ph := fmod(_t * 1.5 + k / 3.0, 1.0)
			draw_arc(c + Vector2(26, -20), 4.0 + ph * 12.0, -PI / 2.0, 0.0, 10, Color(Game.MARK, 1.0 - ph), 2.0, true)
