class_name ModelPlace
extends RefCounted
## Coloca un modelo .glb a escala real: lo escala, lo gira y lo apoya con su base
## (el punto más bajo) en `base`, centrado en x/z. Mide la caja real del modelo
## después de girarlo, así no importa cómo venga armado el archivo.


static func place(parent: Node3D, path: String, scale: float, rot_deg: Vector3, base: Vector3) -> Node3D:
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("No se pudo cargar %s" % path)
		return null
	var holder := Node3D.new()
	parent.add_child(holder)
	var inst: Node3D = scene.instantiate()
	holder.add_child(inst)
	holder.rotation_degrees = rot_deg
	holder.scale = Vector3.ONE * scale
	var box := bounds(holder, parent)
	var center := box.get_center()
	holder.position += base - Vector3(center.x, box.position.y, center.z)
	return holder


const TEX := "res://assets/textures/polyhaven/"
static var _dress_cache := {}


## Viste las superficies que vienen sin textura (color liso) con una textura PBR real
## proyectada en triplanar, teñida con el color original. kind: "metal" o "concrete".
## Así los modelos de la NASA que traen solo colores no se ven como plástico.
static func dress(root: Node3D, kind: String, tile_m := 2.0, force := false) -> int:
	var n := 0
	if root == null:
		return 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			if m.get_surface_override_material(s) != null:
				continue
			var mat := m.mesh.surface_get_material(s) as BaseMaterial3D
			var tex: Texture2D = mat.albedo_texture if mat else null
			if tex != null and not force:
				continue
			var tint: Color = mat.albedo_color if mat else Color(0.8, 0.8, 0.8)
			m.set_surface_override_material(s, _dressed(kind, tint, tile_m))
			n += 1
	return n


static func _dressed(kind: String, tint: Color, tile_m: float) -> ORMMaterial3D:
	var key := "%s_%s_%.1f" % [kind, tint.to_html(false), tile_m]
	if _dress_cache.has(key):
		return _dress_cache[key]
	var base := "metal_plate_02" if kind == "metal" else "concrete"
	# Color medio de cada foto (medido): se compensa para que el tinte quede como el color original
	var avg := Color(85, 73, 63) / 255.0 if kind == "metal" else Color(115, 105, 92) / 255.0
	var m := ORMMaterial3D.new()
	m.albedo_texture = load(TEX + base + "_diff.jpg")
	m.albedo_color = Color(tint.r * 0.5 / avg.r, tint.g * 0.5 / avg.g, tint.b * 0.5 / avg.b)
	m.orm_texture = load(TEX + base + "_arm.jpg")
	m.normal_enabled = true
	m.normal_texture = load(TEX + base + "_nor.jpg")
	m.normal_scale = 0.5
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 6.0
	m.uv1_scale = Vector3.ONE / tile_m
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_dress_cache[key] = m
	return m


## Caja que ocupan todas las mallas debajo de `root`, medida en el espacio de `space`
## (un antepasado de `root`). No necesita que los nodos estén dentro del árbol de escena.
static func bounds(root: Node3D, space: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b := _rel_xf(m, space) * m.mesh.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


## Transformación de `n` relativa a `space`, sumando las de cada padre en el camino.
static func _rel_xf(n: Node3D, space: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != space:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf
