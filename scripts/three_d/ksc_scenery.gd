class_name KscScenery
extends RefCounted
## Alrededores como el Centro Espacial Kennedy (Florida, plataforma 39A):
## - terreno plano de marisma con lagunas y el océano Atlántico al este (+z, hacia donde sale el cohete);
## - palmeras sabal (Sabal palmetto, el árbol de Florida) y matorral de palmito;
## - torre de servicio fija de celosía con brazo de acceso, tres torres pararrayos con cables,
##   torre de agua del sistema de supresión de sonido;
## - camino de oruga de grava de río con mediana de pasto, centro de control (LCC), reloj de
##   cuenta regresiva y asta de bandera como en el sitio de prensa, postes de luz y cercas.
## Las estructuras de celosía se arman en una sola malla por torre (pocas llamadas de dibujo).

const OCEAN_Z := 820.0 # línea de playa
const WATER_Y := -0.9

var w: HangarWorld
var root: Node3D
var _leaf_cache := {}


func _init(world: HangarWorld) -> void:
	w = world
	root = world.root


func build(quality_high: bool) -> void:
	_water()
	_pad_structures()
	_buildings()
	_vegetation(quality_high)


# ---------- Agua ----------

func _water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(9000, 9000)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/water.gdshader")
	var n := FastNoiseLite.new()
	n.frequency = 0.03
	n.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 3.0
	tex.noise = n
	mat.set_shader_parameter("wave_nor", tex)
	mi.material_override = mat
	mi.position = Vector3(0, WATER_Y, 1200)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Water"
	root.add_child(mi)


# ---------- Plataforma 39A ----------

func _pad_structures() -> void:
	var steel := w.pbr("fss_steel", "metal_plate", 2.0, Color(0.62, 0.64, 0.66))
	var red := w.pbr("fss_red", "metal_plate", 2.0, Color(1.1, 0.3, 0.2))
	var white := w.pbr("tower_white", "metal_plate_02", 2.0, Color(1.5, 1.5, 1.5))
	var pz := HangarWorld.PAD_Z
	var ps := HangarWorld.PAD_SURFACE
	# Torre de servicio fija (FSS): celosía de 10 m de lado y 80 m, al costado del cohete
	var tx := -27.0 # fuera del paso de la oruga (33 m de ancho)
	var boxes := []
	var top := 80.0
	for cx in [-5.0, 5.0]:
		for cz in [-5.0, 5.0]:
			boxes.append([Vector3(0.7, top, 0.7), Vector3(tx + cx, ps + top / 2.0, pz + cz)])
	var lvl := 0.0
	while lvl <= top:
		for s in [-5.0, 5.0]:
			boxes.append([Vector3(10.5, 0.45, 0.45), Vector3(tx, ps + lvl, pz + s)])
			boxes.append([Vector3(0.45, 0.45, 10.5), Vector3(tx + s, ps + lvl, pz)])
		boxes.append([Vector3(10, 0.2, 10), Vector3(tx, ps + lvl - 0.2, pz)]) # piso de cada nivel
		lvl += 6.0
	_add_merged(boxes, steel)
	# Diagonales (cruces de San Andrés) en las cuatro caras
	var diag := []
	lvl = 0.0
	while lvl < top:
		for s in [-5.0, 5.0]:
			diag.append([Vector3(tx - 5, ps + lvl, pz + s), Vector3(tx + 5, ps + lvl + 6, pz + s)])
			diag.append([Vector3(tx + 5, ps + lvl, pz + s), Vector3(tx - 5, ps + lvl + 6, pz + s)])
			diag.append([Vector3(tx + s, ps + lvl, pz - 5), Vector3(tx + s, ps + lvl + 6, pz + 5)])
		lvl += 6.0
	_add_struts(diag, 0.25, steel)
	# Brazo de acceso de la tripulación y brazos de servicio hacia el cohete
	for ay in [18.0, 36.0, 60.0]:
		w._box(Vector3(18.0, 2.2, 2.2), Vector3(tx + 14.0, ps + ay, pz), red)
	# Mástil pararrayos sobre la torre
	w._box(Vector3(0.6, 30.0, 0.6), Vector3(tx, ps + top + 15.0, pz), steel)
	# Tres torres pararrayos de 150 m alrededor de la plataforma, unidas por cables
	var tips := []
	for k in 3:
		var a := PI / 2.0 + TAU * k / 3.0 # 90°, 210°, 330°: ninguna sobre el camino de la oruga (-z)
		var c := Vector3(cos(a) * 95.0, 0.0, pz + sin(a) * 95.0)
		_lattice_mast(c, 150.0, 3.0, white)
		tips.append(c + Vector3(0, 150.0, 0))
	var wires := []
	for k in 3:
		wires.append([tips[k], tips[(k + 1) % 3]])
		var out: Vector3 = tips[k] - Vector3(0, 150.0, pz)
		out.y = 0.0
		wires.append([tips[k], Vector3(tips[k].x, 0.0, tips[k].z) + out.normalized() * 120.0 + Vector3(0, 0, 0)])
	_add_struts(wires, 0.06, steel)
	# Torre de agua del sistema de supresión de sonido (88 m): patas, riostras y tanque
	var wt := Vector3(-120.0, 0.0, pz + 70.0)
	var legs := []
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		legs.append([wt + Vector3(cos(a) * 9.0, 0, sin(a) * 9.0), wt + Vector3(cos(a) * 5.0, 76.0, sin(a) * 5.0)])
	for hy in [20.0, 40.0, 60.0]:
		for k in 4:
			var a0 := TAU * k / 4.0 + PI / 4.0
			var a1 := TAU * (k + 1) / 4.0 + PI / 4.0
			var r: float = 9.0 - 4.0 * hy / 76.0
			legs.append([wt + Vector3(cos(a0) * r, hy, sin(a0) * r), wt + Vector3(cos(a1) * r, hy, sin(a1) * r)])
	_add_struts(legs, 0.6, steel)
	var tank := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 7.5
	cyl.bottom_radius = 7.5
	cyl.height = 12.0
	tank.mesh = cyl
	tank.material_override = white
	tank.position = wt + Vector3(0, 82.0, 0)
	root.add_child(tank)
	var cap := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 7.5
	sph.height = 5.0
	cap.mesh = sph
	cap.material_override = white
	cap.position = wt + Vector3(0, 88.0, 0)
	root.add_child(cap)
	# Mediana de pasto entre los dos carriles de grava del camino de oruga
	var grass := w.pbr("median_grass", "leafy_grass", 2.5, Color(0.85, 1.0, 0.8))
	var z0 := HangarWorld.D / 2.0 + 50.0
	var z1 := pz - 35.0 - HangarWorld.RAMP_LEN
	w._box(Vector3(14.0, 0.32, z1 - z0), Vector3(0, -0.12, (z0 + z1) / 2.0), grass)
	# Postes de luz a lo largo del camino
	var pole := w.pbr("pole", "metal_plate", 1.0, Color(0.5, 0.52, 0.55))
	var z := z0 + 10.0
	while z < z1:
		for sx in [-1.0, 1.0]:
			w._box(Vector3(0.3, 12.0, 0.3), Vector3(sx * (HangarWorld.ROAD_W / 2.0 + 4.0), 6.0, z), pole)
			w._box(Vector3(2.0, 0.3, 0.6), Vector3(sx * (HangarWorld.ROAD_W / 2.0 + 3.2), 12.0, z), pole)
		z += 40.0


## Torre de celosía delgada (pararrayos): tres patas, aros y diagonales.
func _lattice_mast(base: Vector3, h: float, r: float, mat: Material) -> void:
	var s := []
	var pts := []
	for k in 3:
		var a := TAU * k / 3.0
		pts.append(Vector3(cos(a) * r, 0, sin(a) * r))
	for k in 3:
		s.append([base + pts[k], base + pts[k] * 0.4 + Vector3(0, h, 0)])
	var y := 0.0
	while y < h:
		var k0 := 1.0 - 0.6 * y / h
		var k1 := 1.0 - 0.6 * (y + 6.0) / h
		for k in 3:
			var p0: Vector3 = pts[k]
			var p1: Vector3 = pts[(k + 1) % 3]
			s.append([base + p0 * k0 + Vector3(0, y, 0), base + p1 * k0 + Vector3(0, y, 0)])
			s.append([base + p0 * k0 + Vector3(0, y, 0), base + p1 * k1 + Vector3(0, y + 6.0, 0)])
		y += 6.0
	_add_struts(s, 0.22, mat)


# ---------- Edificios ----------

func _buildings() -> void:
	var concrete := w.pbr("lcc", "concrete", 6.0, Color(1.25, 1.25, 1.22))
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.12, 0.18, 0.24)
	glass.metallic = 0.6
	glass.roughness = 0.08
	# Centro de Control de Lanzamiento (LCC), junto al VAB: 4 pisos con ventanales inclinados
	var c := Vector3(-95.0, 0.0, -95.0)
	w._box(Vector3(60, 24, 34), c + Vector3(0, 12, 0), concrete, true)
	for fl in 3:
		w._box(Vector3(58, 3.0, 0.3), c + Vector3(0, 6.0 + fl * 6.0, 17.1), glass)
	w._box(Vector3(62, 1.0, 36), c + Vector3(0, 24.5, 0), concrete)
	# Reloj de cuenta regresiva y asta de bandera, como en el sitio de prensa
	var clock_pos := Vector3(70.0, 0.0, HangarWorld.PAD_Z - 150.0)
	var dark := w.pbr("clock", "metal_plate", 1.0, Color(0.15, 0.15, 0.17))
	w._box(Vector3(14, 4, 1.2), clock_pos + Vector3(0, 3.5, 0), dark)
	var lbl := Label3D.new()
	lbl.name = "CountdownClock"
	lbl.text = "T- 00:00:00"
	lbl.font_size = 140
	lbl.pixel_size = 0.012
	lbl.modulate = Color(1.0, 0.35, 0.15)
	lbl.outline_size = 0
	lbl.position = clock_pos + Vector3(0, 3.5, -0.65)
	lbl.rotation.y = PI
	lbl.shaded = false
	root.add_child(lbl)
	w._box(Vector3(0.25, 18.0, 0.25), clock_pos + Vector3(9.0, 9.0, 0), w.pbr("pole", "metal_plate", 1.0, Color(0.5, 0.52, 0.55)))
	var flag := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(4.5, 2.4)
	flag.mesh = q
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = _flag_texture()
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	flag.material_override = fm
	flag.position = clock_pos + Vector3(11.3, 16.5, 0)
	root.add_child(flag)
	# Cerca perimetral de la plataforma (postes y malla)
	var fence := w.pbr("fence", "metal_plate", 1.0, Color(0.6, 0.62, 0.65))
	var posts := []
	var rr := 160.0
	for k in 72:
		var a := TAU * k / 72.0
		var p := Vector3(cos(a) * rr, 0, HangarWorld.PAD_Z + sin(a) * rr)
		if absf(p.x) < HangarWorld.ROAD_W and p.z < HangarWorld.PAD_Z:
			continue # paso del camino de oruga
		posts.append([Vector3(0.12, 2.4, 0.12), p + Vector3(0, 1.2, 0)])
	_add_merged(posts, fence)


## Bandera de franjas y estrellas simplificada (dibujada por código).
func _flag_texture() -> Texture2D:
	var img := Image.create(190, 100, true, Image.FORMAT_RGB8)
	for y in 100:
		var stripe := int(y / (100.0 / 13.0)) % 2 == 0
		for x in 190:
			var c := Color(0.7, 0.1, 0.15) if stripe else Color(0.95, 0.95, 0.95)
			if x < 76 and y < 54:
				c = Color(0.12, 0.16, 0.38)
				if (x % 12 == 6 and y % 10 == 5) or (x % 12 == 0 and y % 10 == 0 and x > 0 and y > 0):
					c = Color(0.95, 0.95, 0.95)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ---------- Vegetación ----------

func _vegetation(quality_high: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 39
	var blocked := [Rect2(-60, -60, 120, 190), Rect2(-HangarWorld.ROAD_W / 2.0 - 8.0, 0, HangarWorld.ROAD_W + 16.0, HangarWorld.PAD_Z),
		Rect2(-175, HangarWorld.PAD_Z - 175, 350, 350), Rect2(40, -100, 70, 200), Rect2(-270, -290, 210, 260)]
	var ok := func(x: float, z: float) -> bool:
		for r: Rect2 in blocked:
			if r.has_point(Vector2(x, z)):
				return false
		var h := w.ground_height(x, z)
		return h > -0.3 and z < OCEAN_Z - 60.0
	# Palmeras sabal en grupos ("hammocks"), como en la isla Merritt
	var palms: Array[Transform3D] = []
	for g in 70:
		var gc := Vector2(rng.randf_range(-1400, 1400), rng.randf_range(-1300, OCEAN_Z - 80))
		var n := rng.randi_range(4, 14)
		for k in n:
			var x := gc.x + rng.randf_range(-35, 35)
			var z := gc.y + rng.randf_range(-35, 35)
			if not ok.call(x, z):
				continue
			var s := rng.randf_range(0.75, 1.3)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.25), s))
			palms.append(Transform3D(b, Vector3(x, w.ground_height(x, z) - 0.2, z)))
	_multimesh(_palm_mesh(), palms, 0.0)
	# Matorral de palmito y arbustos bajos
	var shrubs: Array[Transform3D] = []
	var count := 5000 if quality_high else 1800
	for k in count:
		var x := rng.randf_range(-1300, 1300)
		var z := rng.randf_range(-1200, OCEAN_Z - 40)
		if not ok.call(x, z):
			continue
		var s := rng.randf_range(0.6, 1.6)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.6, 1.0), s))
		shrubs.append(Transform3D(b, Vector3(x, w.ground_height(x, z) - 0.1, z)))
	_multimesh(_shrub_mesh(), shrubs, 900.0)


func _multimesh(mesh: Mesh, xfs: Array[Transform3D], range_end: float) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	if range_end > 0.0:
		mi.visibility_range_end = range_end
		mi.visibility_range_end_margin = 100.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(mi)


## Palmera sabal: tronco algo curvo con corteza y una copa de hojas en abanico.
func _palm_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	# Tronco
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 9.0
	var segs := 8
	var sides := 7
	var bend := Vector3(0.8, 0, 0)
	for i in segs:
		var k0 := float(i) / segs
		var k1 := float(i + 1) / segs
		var c0 := bend * k0 * k0 + Vector3(0, h * k0, 0)
		var c1 := bend * k1 * k1 + Vector3(0, h * k1, 0)
		var r0 := lerpf(0.32, 0.22, k0)
		var r1 := lerpf(0.32, 0.22, k1)
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			for v in [[c0 + d0 * r0, d0, Vector2(float(s) / sides, k0 * 4)], [c1 + d1 * r1, d1, Vector2(float(s + 1) / sides, k1 * 4)], [c0 + d1 * r0, d1, Vector2(float(s + 1) / sides, k0 * 4)],
					[c0 + d0 * r0, d0, Vector2(float(s) / sides, k0 * 4)], [c1 + d0 * r1, d0, Vector2(float(s) / sides, k1 * 4)], [c1 + d1 * r1, d1, Vector2(float(s + 1) / sides, k1 * 4)]]:
				st.set_normal(v[1])
				st.set_uv(v[2])
				st.add_vertex(v[0])
	st.commit(mesh)
	var bark := StandardMaterial3D.new()
	bark.albedo_texture = load(HangarWorld.TEX + "bark_brown_02_diff.jpg")
	bark.normal_enabled = true
	bark.normal_texture = load(HangarWorld.TEX + "bark_brown_02_nor.jpg")
	bark.albedo_color = Color(0.85, 0.8, 0.72)
	mesh.surface_set_material(0, bark)
	# Copa: hojas en abanico (cuadros con textura recortada por alfa), hacia arriba y caídas
	var top := bend + Vector3(0, h, 0)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 16:
		var a := TAU * k / 16.0 + (0.2 if k % 2 == 0 else 0.0)
		var droop := -0.35 + 0.9 * float(k % 3) / 2.0 # unas suben, otras cuelgan
		var dir := Vector3(cos(a) * cos(droop), sin(droop), sin(a) * cos(droop))
		var side := Vector3(-sin(a), 0, cos(a))
		var L := 3.4
		var W2 := 1.5
		var p0 := top
		var p1 := top + dir * L
		var c0 := p0 - side * W2 * 0.15
		var c1 := p0 + side * W2 * 0.15
		var c2 := p1 + side * W2
		var c3 := p1 - side * W2
		var n := dir.cross(side).normalized()
		if n.y < 0.0:
			n = -n
		for v in [[c0, Vector2(0.45, 1)], [c2, Vector2(1, 0)], [c1, Vector2(0.55, 1)], [c0, Vector2(0.45, 1)], [c3, Vector2(0, 0)], [c2, Vector2(1, 0)]]:
			st2.set_normal(n.lerp(Vector3.UP, 0.5).normalized())
			st2.set_uv(v[1])
			st2.add_vertex(v[0])
	st2.commit(mesh)
	mesh.surface_set_material(1, _leaf_material("fan"))
	return mesh


## Arbusto de palmito: varias hojas en abanico cruzadas, cerca del suelo.
func _shrub_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	for k in 7:
		var a := rng.randf() * TAU
		var tilt := rng.randf_range(0.5, 1.2)
		var dir := Vector3(cos(a) * cos(tilt), sin(tilt), sin(a) * cos(tilt))
		var side := Vector3(-sin(a), 0, cos(a))
		var L := rng.randf_range(1.0, 1.6)
		var p1 := dir * L
		var c0 := -side * 0.1
		var c1 := side * 0.1
		var c2 := p1 + side * 0.7
		var c3 := p1 - side * 0.7
		for v in [[c0, Vector2(0.45, 1)], [c2, Vector2(1, 0)], [c1, Vector2(0.55, 1)], [c0, Vector2(0.45, 1)], [c3, Vector2(0, 0)], [c2, Vector2(1, 0)]]:
			st.set_normal(Vector3.UP)
			st.set_uv(v[1])
			st.add_vertex(v[0])
	var mesh := st.commit()
	mesh.surface_set_material(0, _leaf_material("fan"))
	return mesh


func _leaf_material(kind: String) -> StandardMaterial3D:
	if _leaf_cache.has(kind):
		return _leaf_cache[kind]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _fan_texture()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.75
	m.backlight_enabled = true
	m.backlight = Color(0.25, 0.32, 0.1)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_leaf_cache[kind] = m
	return m


## Hoja en abanico (palmeada): foliolos que salen del pecíolo, generada por código.
func _fan_texture() -> Texture2D:
	var sz := 256
	var img := Image.create(sz, sz, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var base := Vector2(sz * 0.5, sz - 2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for k in 31:
		var a := lerpf(-1.25, 1.25, k / 30.0) - PI / 2.0
		var length := sz * rng.randf_range(0.8, 0.98)
		var tint := Color(0.22, 0.36, 0.12).lerp(Color(0.38, 0.48, 0.18), rng.randf())
		var steps := int(length)
		for s in steps:
			var t := float(s) / steps
			var p := base + Vector2(cos(a), sin(a)) * s
			var half := 2.6 * (1.0 - t * 0.7) * (0.6 if t > 0.85 else 1.0)
			for o in range(-int(ceil(half)), int(ceil(half)) + 1):
				var q := p + Vector2(-sin(a), cos(a)) * o
				var x := int(q.x)
				var y := int(q.y)
				if x >= 0 and x < sz and y >= 0 and y < sz:
					var shade := 1.0 - 0.25 * absf(o) / maxf(half, 1.0)
					img.set_pixel(x, y, Color(tint.r * shade, tint.g * shade, tint.b * shade, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ---------- Ayudantes de mallas ----------

## Une muchas cajas [tamaño, centro] en una sola malla.
func _add_merged(boxes: Array, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in boxes:
		var bm := BoxMesh.new()
		bm.size = b[0]
		st.append_from(bm, 0, Transform3D(Basis.IDENTITY, b[1]))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	root.add_child(mi)


## Barras (vigas, cables) entre pares de puntos [a, b], unidas en una sola malla.
func _add_struts(pairs: Array, thick: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for pr in pairs:
		var a: Vector3 = pr[0]
		var b: Vector3 = pr[1]
		var d := b - a
		var len := d.length()
		if len < 0.01:
			continue
		var bm := BoxMesh.new()
		bm.size = Vector3(thick, len, thick)
		var y := d / len
		var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
		var z := x.cross(y).normalized()
		st.append_from(bm, 0, Transform3D(Basis(x, y, z), (a + b) * 0.5))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	root.add_child(mi)
