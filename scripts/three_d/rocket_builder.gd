class_name RocketBuilder
extends RefCounted
## Construye el cohete en 3D desde el mismo diseño y los mismos perfiles que usa la física.
## Eje Y hacia arriba; la base del cohete queda en y = 0.

const SEGMENTS := 64

static var _mats := {}

## Colores y acabados que el jugador puede elegir por pieza.
const PAINTS := {"auto": null, "white": Color(0.92, 0.93, 0.94), "silver": Color(0.8, 0.81, 0.83),
	"black": Color(0.06, 0.06, 0.07), "orange": Color(0.92, 0.42, 0.1), "red": Color(0.72, 0.1, 0.08),
	"blue": Color(0.1, 0.25, 0.62), "yellow": Color(0.95, 0.75, 0.12), "green": Color(0.15, 0.45, 0.25),
	"roll": Color(0.93, 0.93, 0.94)} # roll = blanco con cuadrantes negros (patrón de rodadura)
const FINISHES := {"auto": [], "matte": [0.0, 0.85], "gloss": [0.0, 0.18], "metal": [1.0, 0.3]}


## Devuelve un Node3D con un hijo por pieza (nombre "Part_<i>") y su cuerpo de colisión para elegirla con el ratón.
## Vista en corte (hangar): todas las pieces de cuerpo usan la piel que se puede cortar.
static var cutaway := false


static func build(design: Array, analysis: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Rocket"
	var height := float(analysis.get("height", 0.0))
	for info in analysis.get("parts", []):
		var i: int = info.index
		var p: Dictionary = design[i]
		var t := Catalog.template(p.id)
		var part := Node3D.new()
		part.name = "Part_%d" % i
		part.set_meta("index", i)
		# Arriba de la pieza en coordenadas del mundo
		var y_top := height - float(info.y)
		part.position.y = y_top
		root.add_child(part)
		var length := float(info.length)
		var r := float(p.get("diameter", 1.0)) / 2.0

		if t.has("model"):
			_add_model(part, t, p, length)
		else:
			var prof := RocketAnalysis.profile(p)
			var next_kind := ""
			if i + 1 < design.size():
				next_kind = str(Catalog.template(design[i + 1].id).get("kind", ""))
			var gear: Array = p.get("probe", {}).get("landing", []) if t.kind == "payload" else []
			if not gear.is_empty():
				# Bahía abierta: se ve la nave que va a aterrizar (Módulo Lunar o cápsula de Marte)
				_lander_bay(part, p, length, r, gear)
			else:
				part.add_child(_mesh_node(lathe(prof), skin(p, t, prof, next_kind)))
			match t.kind:
				"engine":
					var b := RocketAnalysis.bell(p.get("engine", ""))
					var n := int(p.get("count", 1))
					var housing_bottom := -prof[prof.size() - 1].y
					for pos in _cluster(n, r, float(b.exit_d)):
						var bell := _mesh_node(bell_mesh(float(b.exit_d), float(b.length), r), _mat("engine_bell"))
						bell.position = Vector3(pos.x, housing_bottom, pos.y)
						part.add_child(bell)
				"solid":
					var nz := _mesh_node(bell_mesh(r * 0.8, r * 1.0, r), _mat("engine_bell"))
					nz.position.y = -length
					part.add_child(nz)
				"decoupler":
					# Anillo de pernos explosivos
					var ring := _mesh_node(lathe(PackedVector2Array([Vector2(r * 1.02, length * 0.35), Vector2(r * 1.02, length * 0.65)])), _mat("bolt_ring"))
					part.add_child(ring)
		# Aletas
		var f: Dictionary = p.get("fins", {})
		var nf := int(f.get("count", 0))
		if nf > 0:
			var fin := fin_mesh(float(f.get("root", 0.5)), float(f.get("tip", 0.3)), float(f.get("span", 0.3)), 0.04)
			var fmat := _material_for(p, t, true)
			var yb := -(length - float(f.get("offset", 0.0)))
			for k in nf:
				var holder := Node3D.new()
				holder.rotation.y = TAU * k / nf + PI / 4.0
				part.add_child(holder)
				var m := _mesh_node(fin, fmat)
				m.position = Vector3(r * 0.98, yb, 0)
				holder.add_child(m)
		# Colisión para elegir la pieza
		var body := StaticBody3D.new()
		body.collision_layer = 2 # capa del cohete: se puede elegir con el ratón pero no frena la cámara
		body.collision_mask = 0
		body.set_meta("index", i)
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = maxf(PartDraw.half_width(p), 0.1)
		cyl.height = maxf(length, 0.05)
		shape.shape = cyl
		shape.position.y = -length / 2.0
		body.add_child(shape)
		part.add_child(body)
	return root


# ---------- Mallas ----------

## Superficie de revolución desde un perfil (radio, y hacia abajo desde la cima de la pieza).
## Bahía de carga abierta (como el adaptador del Saturno V con los paneles abiertos): anillos arriba y
## abajo, cuatro largueros, y adentro la nave de aterrizaje a escala para que quepa.
static func _lander_bay(part: Node3D, p: Dictionary, length: float, r: float, gear: Array) -> void:
	var metal := _mat("bolt_ring")
	for y in [-0.04, -length + 0.04]:
		part.add_child(_ring_node(r, 0.08, y, metal))
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		var bar := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.06 + r * 0.03, length, 0.06 + r * 0.03)
		bar.mesh = b
		bar.material_override = metal
		bar.position = Vector3(cos(a) * r * 0.97, -length / 2.0, sin(a) * r * 0.97)
		part.add_child(bar)
	var craft: Node3D = Spacecraft.lunar_module() if "legs" in gear else Spacecraft.mars_capsule()
	var holder := Node3D.new()
	holder.add_child(craft)
	var box := ModelPlace.bounds(craft, holder)
	var s := minf(r * 1.8 / maxf(maxf(box.size.x, box.size.z), 0.01), length * 0.9 / maxf(box.size.y, 0.01))
	craft.scale *= s
	box = ModelPlace.bounds(craft, holder)
	craft.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
	holder.position.y = -length * 0.95
	part.add_child(holder)


static func _ring_node(r: float, h: float, y: float, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.cap_top = false
	c.cap_bottom = false
	m.mesh = c
	m.material_override = mat
	m.position.y = y - h / 2.0
	return m


static func lathe(prof: PackedVector2Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var n := prof.size()
	# Longitud acumulada para la coordenada V de la textura
	var acc := [0.0]
	for i in range(1, n):
		acc.append(acc[-1] + prof[i - 1].distance_to(prof[i]))
	var total: float = maxf(acc[-1], 0.001)
	for i in range(1, n):
		var a := prof[i - 1]
		var b := prof[i]
		for s in SEGMENTS:
			var t0 := TAU * s / SEGMENTS
			var t1 := TAU * (s + 1) / SEGMENTS
			var p00 := Vector3(cos(t0) * a.x, -a.y, sin(t0) * a.x)
			var p01 := Vector3(cos(t1) * a.x, -a.y, sin(t1) * a.x)
			var p10 := Vector3(cos(t0) * b.x, -b.y, sin(t0) * b.x)
			var p11 := Vector3(cos(t1) * b.x, -b.y, sin(t1) * b.x)
			var u0 := float(s) / SEGMENTS
			var u1 := float(s + 1) / SEGMENTS
			var v0: float = acc[i - 1] / total
			var v1: float = acc[i] / total
			_tri(st, [p00, p10, p11], [Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1)])
			_tri(st, [p00, p11, p01], [Vector2(u0, v0), Vector2(u1, v1), Vector2(u1, v0)])
	# Tapas (si el borde no termina en el eje)
	for cap in [[prof[0], 1.0], [prof[n - 1], -1.0]]:
		var c: Vector2 = cap[0]
		if c.x <= 0.001:
			continue
		var center := Vector3(0, -c.y, 0)
		for s in SEGMENTS:
			var t0 := TAU * s / SEGMENTS
			var t1 := TAU * (s + 1) / SEGMENTS
			var q0 := Vector3(cos(t0) * c.x, -c.y, sin(t0) * c.x)
			var q1 := Vector3(cos(t1) * c.x, -c.y, sin(t1) * c.x)
			if cap[1] > 0.0:
				_tri(st, [center, q0, q1], [Vector2(0.5, 0.5), Vector2(0, 0), Vector2(1, 0)])
			else:
				_tri(st, [center, q1, q0], [Vector2(0.5, 0.5), Vector2(1, 0), Vector2(0, 0)])
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


static func _tri(st: SurfaceTool, pts: Array, uvs: Array) -> void:
	# Orden de vértices para que la cara apunte hacia afuera (Godot: antihorario visto de frente)
	for k in [0, 2, 1]:
		st.set_uv(uvs[k])
		st.add_vertex(pts[k])


## Tobera tipo campana: de la garganta a la salida.
static func bell_mesh(exit_d: float, length: float, _body_r: float) -> ArrayMesh:
	var prof := PackedVector2Array()
	var throat := exit_d * 0.18
	prof.append(Vector2(throat * 1.6, 0.0))
	prof.append(Vector2(throat, length * 0.12))
	for i in range(1, 9):
		var u := i / 8.0
		prof.append(Vector2(throat + (exit_d / 2.0 - throat) * sqrt(u), length * (0.12 + 0.88 * u)))
	return lathe(prof)


## Aleta trapezoidal con grosor: borde de ataque inclinado, borde de salida recto.
static func fin_mesh(root: float, tip: float, span: float, thick: float) -> ArrayMesh:
	var outline := [Vector2(0, root), Vector2(span, tip), Vector2(span, 0), Vector2(0, 0)] # (x hacia afuera, y hacia arriba desde el borde de salida)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := thick / 2.0
	var v := func(p: Vector2, z: float) -> Vector3: return Vector3(p.x, p.y, z)
	# Caras laterales
	for z in [h, -h]:
		var a: Vector3 = v.call(outline[0], z)
		for i in range(1, 3):
			var b: Vector3 = v.call(outline[i], z)
			var c: Vector3 = v.call(outline[i + 1], z)
			if z > 0:
				st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
			else:
				st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
	# Cantos
	for i in 4:
		var p: Vector2 = outline[i]
		var q: Vector2 = outline[(i + 1) % 4]
		var a := Vector3(p.x, p.y, h)
		var b := Vector3(q.x, q.y, h)
		var c := Vector3(q.x, q.y, -h)
		var d := Vector3(p.x, p.y, -h)
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
		st.add_vertex(a); st.add_vertex(d); st.add_vertex(c)
	st.generate_normals()
	return st.commit()


static func _cluster(n: int, r: float, exit_d: float) -> Array:
	# Posiciones (x, z) de las toberas: una al centro, anillos alrededor
	if n == 1:
		return [Vector2.ZERO]
	var out := []
	var center := 1 if n >= 7 else 0
	if center == 1:
		out.append(Vector2.ZERO)
	var ring := n - center
	var rr := clampf(r - exit_d * 0.5, exit_d * 0.55, r)
	for k in ring:
		var a := TAU * k / ring
		out.append(Vector2(cos(a), sin(a)) * rr)
	return out


static func _mesh_node(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	return m


static func _add_model(part: Node3D, t: Dictionary, p: Dictionary, length: float) -> void:
	var scene: PackedScene = load(t.model)
	if scene == null:
		return
	var inst: Node3D = scene.instantiate()
	var holder := Node3D.new()
	var sx := float(p.get("diameter", 1.0)) / (2.0 * float(t.get("model_radius", 0.5)))
	var sy := length / float(t.get("model_height", 1.0))
	holder.scale = Vector3(sx, sy, sx)
	holder.position.y = -length
	var c: Array = t.get("model_center", [0, 0, 0])
	inst.position = Vector3(-float(c[0]), -float(c[1]), -float(c[2]))
	holder.add_child(inst)
	part.add_child(holder)


# ---------- Materiales (PBR) ----------

static var _skin_shader: Shader

## Piel con juntas, remaches, suciedad y hollín (assets/shaders/rocket_skin.gdshader) para las
## piezas pintadas o con espuma. Las de metal desnudo y fibra de carbono siguen con su textura.
static func skin(p: Dictionary, t: Dictionary, prof: PackedVector2Array, next_kind: String) -> Material:
	var base := _material_for(p, t) as StandardMaterial3D
	var kind: String = t.get("kind", "")
	if base == null or (base.albedo_texture != null and not cutaway) or not kind in ["nose", "payload", "tank", "solid", "adapter", "decoupler"]:
		return base
	if _skin_shader == null:
		_skin_shader = load("res://assets/shaders/rocket_skin.gdshader")
	var r := 0.0
	var plen := 0.0
	for k in prof.size():
		r = maxf(r, prof[k].x)
		if k > 0:
			plen += prof[k - 1].distance_to(prof[k])
	var m := ShaderMaterial.new()
	m.shader = _skin_shader
	m.set_shader_parameter("paint", base.albedo_color)
	m.set_shader_parameter("metal", base.metallic)
	m.set_shader_parameter("rough", base.roughness)
	m.set_shader_parameter("dims", Vector2(maxf(TAU * r, 0.3), maxf(plen, 0.2)))
	m.set_shader_parameter("pattern", 1.0 if p.get("paint", "") == "roll" else 0.0)
	m.set_shader_parameter("foam", 1.0 if base == _mat("foam_orange") else 0.0)
	m.set_shader_parameter("soot", 0.7 if next_kind == "engine" or kind == "solid" else 0.0)
	m.set_shader_parameter("plate_nor", _tex(TEX + "metal_plate_02_nor.jpg"))
	m.set_shader_parameter("grime", _tex(TEX + "concrete_diff.jpg"))
	return m

static func _material_for(p: Dictionary, t: Dictionary, fins := false) -> Material:
	var paint: String = p.get("paint", "auto")
	var finish: String = p.get("finish", "auto")
	if paint != "auto" or finish != "auto":
		var key := "custom_%s_%s" % [paint, finish]
		if not _mats.has(key):
			var base := _material_for(p.merged({"paint": "auto", "finish": "auto"}, true), t, fins) as StandardMaterial3D
			var m := base.duplicate() as StandardMaterial3D
			if paint != "auto":
				m.albedo_color = PAINTS[paint]
			if finish != "auto":
				m.metallic = FINISHES[finish][0]
				m.roughness = FINISHES[finish][1]
				m.clearcoat_enabled = finish == "gloss"
			_mats[key] = m
		return _mats[key]
	var kind: String = t.kind
	var mat_id: String = p.get("material", "aluminium")
	if fins:
		return _mat("metal_" + mat_id)
	match kind:
		"nose", "payload":
			return _mat("paint_white")
		"tank":
			if p.get("propellant", "") == "lox_lh2":
				return _mat("foam_orange") # aislante de espuma, como el tanque externo del transbordador y SLS
			return _mat("paint_white") if mat_id != "carbon" else _mat("metal_carbon")
		"solid":
			return _mat("paint_white")
		"decoupler":
			return _mat("metal_dark")
		"engine":
			return _mat("metal_dark")
		"adapter":
			return _mat("metal_" + mat_id)
	return _mat("metal_" + mat_id)


const TEX := "res://assets/textures/polyhaven/"
static var _tex_cache := {}


static func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path)
	return _tex_cache[path]


## Materiales de las piezas (las propias, las prefabricadas y las del jugador usan los mismos).
## Texturas en proyección triplanar del objeto: no hacen falta coordenadas UV y el
## tamaño del detalle es el mismo en una pieza chica o en una gigante.
static func _mat(id: String) -> StandardMaterial3D:
	if _mats.has(id):
		return _mats[id]
	var m := StandardMaterial3D.new()
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	match id:
		"paint_white":
			_painted(m, Color(0.92, 0.93, 0.94))
		"paint_black_tiles":
			_painted(m, Color(0.07, 0.07, 0.08))
			m.roughness = 1.0
			m.clearcoat_enabled = false
		"foam_orange":
			m.albedo_color = Color(0.78, 0.36, 0.12)
			m.roughness = 0.9
			m.normal_enabled = true
			m.normal_texture = _foam_normal()
			m.normal_scale = 0.7
			m.uv1_scale = Vector3.ONE / 1.5
		"metal_aluminium":
			_metal(m, Color(0.95, 0.96, 0.97), 0.9)
		"metal_al_li":
			_metal(m, Color(0.93, 0.9, 0.84), 0.9)
		"metal_steel":
			_metal(m, Color(0.88, 0.88, 0.9), 0.7)
			m.roughness = 0.7
		"metal_titanium":
			_metal(m, Color(0.7, 0.7, 0.75), 1.0)
		"metal_carbon":
			m.albedo_texture = _carbon_tex()
			m.metallic = 0.15
			m.roughness = 0.3
			m.clearcoat_enabled = true
			m.clearcoat = 0.8
			m.uv1_scale = Vector3.ONE / 0.25
		"metal_dark":
			_metal(m, Color(0.24, 0.24, 0.26), 1.0)
		"bolt_ring":
			_metal(m, Color(0.4, 0.4, 0.42), 0.5)
		"engine_bell":
			_metal(m, Color(0.5, 0.4, 0.34), 0.8)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED # se ve por dentro de la campana
		_:
			m.albedo_color = Color(0.8, 0.8, 0.8)
	_mats[id] = m
	return m


## Pintura sobre paneles remachados: el color lo pone la pintura, el relieve y la rugosidad la textura.
static func _painted(m: StandardMaterial3D, color: Color) -> void:
	m.albedo_color = color
	m.metallic = 0.0
	m.roughness = 0.75
	m.roughness_texture = _tex(TEX + "metal_plate_02_arm.jpg")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.normal_enabled = true
	m.normal_texture = _tex(TEX + "metal_plate_02_nor.jpg")
	m.normal_scale = 0.45
	m.ao_enabled = true
	m.ao_texture = _tex(TEX + "metal_plate_02_arm.jpg")
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.ao_light_affect = 0.3
	m.clearcoat_enabled = true
	m.clearcoat = 0.25
	m.uv1_scale = Vector3.ONE / 2.0 # paneles de unos 2 m


## Metal desnudo con textura de chapa, teñido según el material.
static func _metal(m: StandardMaterial3D, tint: Color, tile_m: float) -> void:
	m.albedo_texture = _tex(TEX + "metal_plate_diff.jpg")
	m.albedo_color = tint
	m.metallic = 1.0
	m.roughness = 1.0
	m.roughness_texture = _tex(TEX + "metal_plate_arm.jpg")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.normal_enabled = true
	m.normal_texture = _tex(TEX + "metal_plate_nor.jpg")
	m.normal_scale = 0.6
	m.uv1_scale = Vector3.ONE / tile_m


## Relieve irregular de la espuma aislante (ruido convertido en mapa de normales).
static func _foam_normal() -> Texture2D:
	if _tex_cache.has("_foam"):
		return _tex_cache["_foam"]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = 0.05
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 6.0
	tex.noise = n
	_tex_cache["_foam"] = tex
	return tex


## Tejido de fibra de carbono (sarga 2×2) generado por código.
static func _carbon_tex() -> Texture2D:
	if _tex_cache.has("_carbon"):
		return _tex_cache["_carbon"]
	var img := Image.create(64, 64, true, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var band := ((x / 8) + (y / 8)) % 2
			var along := float((x if band == 0 else y) % 8) / 8.0
			var v := 0.05 + 0.09 * sin(along * PI)
			img.set_pixel(x, y, Color(v, v, v * 1.05))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["_carbon"] = tex
	return tex


## Material encima de la pieza elegida: brillo naranja suave.
static func highlight_material() -> StandardMaterial3D:
	if _mats.has("_highlight"):
		return _mats["_highlight"]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.55, 0.2, 0.22)
	m.rim_enabled = false
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.no_depth_test = false
	_mats["_highlight"] = m
	return m
