class_name VideoBox
extends ColorRect
## Videos explicativos del manual (hechos con Google Flow / Veo).
## Si existe res://assets/video/<id>.ogv, el manual muestra un botón "Ver video" que lo abre
## a pantalla completa. Godot reproduce Ogg Theora: convertir los MP4 con
##   ffmpeg -i in.mp4 -c:v libtheora -q:v 8 -c:a libvorbis -q:a 5 out.ogv
## Las ideas de cada video (prompts) están en assets/video/PROMPTS.md.

const DIR := "res://assets/video/"

var _player: VideoStreamPlayer


## Botón para abrir el video id, o null si ese video no existe todavía.
static func button(id: String) -> Button:
	if not ResourceLoader.exists(DIR + id + ".ogv"):
		return null
	var b := Button.new()
	b.text = TranslationServer.translate("CX_VIDEO")
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.custom_minimum_size = Vector2(150, 40)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void: open(b, id))
	return b


static func open(from: Node, id: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	from.get_tree().root.add_child(layer)
	var box := VideoBox.new()
	layer.add_child(box)
	box._start(id)


func _start(id: String) -> void:
	color = Color(0, 0, 0, 0.92)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Game.theme
	var center := AspectRatioContainer.new()
	center.ratio = 16.0 / 9.0
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 60
	center.offset_right = -60
	center.offset_top = 60
	center.offset_bottom = -90
	add_child(center)
	_player = VideoStreamPlayer.new()
	_player.stream = load(DIR + id + ".ogv")
	_player.expand = true
	_player.bus = "Master"
	center.add_child(_player)
	_player.finished.connect(_close)
	_player.play()
	Sound.duck(true)
	var close := Button.new()
	close.text = "CR_CLOSE"
	close.custom_minimum_size = Vector2(140, 40)
	close.anchor_left = 0.5
	close.anchor_right = 0.5
	close.anchor_top = 1.0
	close.anchor_bottom = 1.0
	close.offset_left = -70
	close.offset_right = 70
	close.offset_top = -70
	close.offset_bottom = -30
	close.pressed.connect(_close)
	add_child(close)
	close.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	Sound.duck(false)
	get_parent().queue_free()
