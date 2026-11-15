class_name HoustonPortrait
extends PanelContainer
## Retrato de Houston en un círculo: su cara en 3D (HoustonFace) con la boca moviéndose mientras habla.
## talking: true mientras suena su voz. Oculto no dibuja (no gasta la tarjeta de video).

var talking := false:
	set(v):
		talking = v
		if _face:
			_face.talking = v

var _face: HoustonFace
var _vp: SubViewport


func _init(size_px := 150) -> void:
	custom_minimum_size = Vector2(size_px, size_px)


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.07, 0.13)
	sb.set_corner_radius_all(int(custom_minimum_size.x / 2.0))
	sb.set_border_width_all(3)
	sb.border_color = Game.MARK
	add_theme_stylebox_override("panel", sb)
	clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := SubViewportContainer.new()
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	box.add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.1, 0.18)
	env.environment.ambient_light_color = Color(0.8, 0.82, 0.88)
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	_vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-18, 28, 0)
	key.light_energy = 1.3
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 200, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.6, 0.75, 1.0)
	_vp.add_child(rim)
	_face = HoustonFace.new()
	_face.talking = talking
	_vp.add_child(_face)
	var cam := Camera3D.new()
	cam.fov = 26
	_vp.add_child(cam)
	cam.position = Vector3(0, 1.64, 0.62)
	cam.look_at(Vector3(0, 1.62, 0))
	visibility_changed.connect(func() -> void:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED)
