class_name MenuBackdrop
extends SubViewportContainer
## Fondo del menú principal: la plataforma 39A en 3D con un Saturno V sobre la oruga,
## y una cámara que gira despacio alrededor (como la pantalla de inicio de un juego grande).
## Un degradado oscuro a la izquierda deja leer el título y las opciones.

var _cam: Camera3D
var _t := 0.0
var _target := Vector3.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	if str(Game.settings.get("quality", "high")) == "high":
		vp.use_taa = true # suavizado temporal: menos parpadeo en celosías, pasto y bordes finos
	add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)
	var world := HangarWorld.new()
	world.build(root)
	# Cohete sobre la oruga en la plataforma
	Catalog.load_all()
	var design: Array = (Catalog.default_designs.get("saturn_v", []) as Array).duplicate(true)
	var analysis := RocketAnalysis.analyze(design, 3, true)
	var crawler := Crawler.new()
	crawler.build(world, float(analysis.get("max_d", 1.0)))
	root.add_child(crawler)
	crawler.position = Vector3(0, HangarWorld.PAD_SURFACE, HangarWorld.PAD_Z)
	var rocket := RocketBuilder.build(design, analysis)
	root.add_child(rocket)
	rocket.position = Vector3(0, HangarWorld.PAD_TOP, HangarWorld.PAD_Z)
	_target = rocket.position + Vector3(0, float(analysis.get("height", 50.0)) * 0.55, 0)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.far = 20000.0
	root.add_child(_cam)
	# Degradado para leer el texto del menú
	var shade := TextureRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 0.75])
	g.colors = PackedColorArray([Color(0.02, 0.05, 0.09, 0.92), Color(0.02, 0.05, 0.09, 0.55), Color(0.02, 0.05, 0.09, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_sibling.call_deferred(shade)
	_place_camera()


func _process(delta: float) -> void:
	_t += delta
	_place_camera()


func _place_camera() -> void:
	if _cam == null:
		return
	var a := -0.35 + sin(_t * 0.03) * 0.5 # desde el este: la torre de servicio queda detrás
	var r := 190.0
	_cam.position = _target + Vector3(cos(a) * r, -25.0 + sin(_t * 0.05) * 8.0, sin(a) * r)
	_cam.look_at(_target, Vector3.UP)
	_cam.h_offset = -48.0 # el cohete queda a la derecha; el menú a la izquierda
