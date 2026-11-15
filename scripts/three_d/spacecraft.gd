class_name Spacecraft
extends RefCounted
## Naves reales: modelos de NASA 3D Resources (assets/models/nasa/spacecraft) y la nave de
## mando y servicio del Apolo (CSM), armada aquí con sus medidas reales porque NASA no la publica
## sola (solo acoplada a la Soyuz).
## CSM real: módulo de mando cónico de 3,9 m de diámetro y 3,2 m de alto; módulo de servicio
## cilíndrico de 7,5 m con el motor SPS (campana de 3,9 m de largo).

const DIR := "res://assets/models/nasa/spacecraft/"

## Nave de cada misión para el mapa del viaje (la que usó o usa una misión real parecida).
const BY_MISSION := {2: "goes", 3: "apollo", 4: "apollo", 5: "lro", 6: "mars_capsule", 7: "juno", 8: "voyager", 9: "voyager"}


## Modelo de NASA escalado para que su lado mayor mida `size` y centrado en el origen.
static func model(id: String, size: float) -> Node3D:
	var holder := Node3D.new()
	if id == "apollo" or id == "mars_capsule":
		holder.add_child(apollo_stack() if id == "apollo" else mars_capsule())
		var b := ModelPlace.bounds(holder, holder)
		var k := size / maxf(maxf(b.size.x, b.size.y), b.size.z)
		holder.get_child(0).scale *= k
		return holder
	if not ResourceLoader.exists(DIR + id + ".glb"):
		return holder
	var m: Node3D = (load(DIR + id + ".glb") as PackedScene).instantiate()
	holder.add_child(m)
	var box := ModelPlace.bounds(m, holder)
	var s := size / maxf(maxf(box.size.x, box.size.y), maxf(box.size.z, 0.0001))
	m.scale *= s
	box = ModelPlace.bounds(m, holder)
	m.position -= box.get_center()
	return holder


## CSM + Módulo Lunar acoplados punta con punta, como viajaban a la Luna (en metros reales).
static func apollo_stack() -> Node3D:
	var root := Node3D.new()
	var csm := csm()
	root.add_child(csm)
	if ResourceLoader.exists(DIR + "apollo_lm.glb"):
		var lm := lunar_module()
		lm.rotation.x = PI # el LM viaja "cabeza abajo", acoplado a la punta del CSM
		lm.position.y = 3.2 + 3.6
		root.add_child(lm)
	return root


static func lunar_module() -> Node3D:
	var lm: Node3D = (load(DIR + "apollo_lm.glb") as PackedScene).instantiate()
	var holder := Node3D.new()
	holder.add_child(lm)
	var box := ModelPlace.bounds(lm, holder)
	var s := 7.04 / maxf(box.size.y, 0.001) # el LM real mide 7,04 m de alto con las patas
	lm.scale *= s
	box = ModelPlace.bounds(lm, holder)
	lm.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
	return holder


## Módulo de mando y servicio. Origen en la base del módulo de mando (encima del de servicio).
static func csm() -> Node3D:
	var root := Node3D.new()
	var white := _mat(Color(0.88, 0.89, 0.9), 0.35, 0.6)
	var silver := _mat(Color(0.8, 0.82, 0.85), 0.2, 0.95)
	var dark := _mat(Color(0.12, 0.12, 0.13), 0.6, 0.4)
	# Módulo de mando (CM): cono con la punta roma, recubierto de mylar plateado
	_cyl(root, 0.42, 1.96, 3.2, Vector3(0, 1.6, 0), silver)
	_cyl(root, 1.96, 1.96, 0.12, Vector3(0, 0.06, 0), _mat(Color(0.45, 0.32, 0.2), 0.8)) # escudo térmico
	# Módulo de servicio (SM): cilindro con radiadores y el motor SPS abajo
	_cyl(root, 1.96, 1.96, 7.5, Vector3(0, -3.75, 0), white)
	for k in 8:
		var a := TAU * k / 8.0
		var rad := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.9, 3.0, 0.04)
		rad.mesh = b
		rad.material_override = _mat(Color(0.95, 0.95, 0.95), 0.3, 0.2)
		rad.position = Vector3(cos(a) * 1.98, -3.2, sin(a) * 1.98)
		rad.rotation.y = -a + PI / 2.0
		root.add_child(rad)
	_cyl(root, 1.25, 0.45, 3.9, Vector3(0, -7.5 - 1.95, 0), dark) # campana del SPS
	# Antena de alta ganancia (cuatro platos) en un brazo
	_cyl(root, 0.05, 0.05, 1.6, Vector3(2.4, -7.0, 0), silver).rotation.z = PI / 2.0
	for k in 4:
		var d := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.38
		sm.height = 0.18
		sm.is_hemisphere = true
		d.mesh = sm
		d.material_override = white
		d.position = Vector3(3.2 + (k % 2) * 0.8, -7.0 + (k / 2) * 0.8 - 0.4, 0)
		d.rotation.z = PI / 2.0
		root.add_child(d)
	# Propulsores de control (RCS) en cuatro grupos
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		var q := MeshInstance3D.new()
		var qb := BoxMesh.new()
		qb.size = Vector3(0.3, 0.6, 0.3)
		q.mesh = qb
		q.material_override = dark
		q.position = Vector3(cos(a) * 2.1, -1.5, sin(a) * 2.1)
		root.add_child(q)
	return root


static func _cyl(parent: Node3D, top_r: float, bottom_r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = h
	c.radial_segments = 40
	m.mesh = c
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
	return m


static func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


## Nave que lleva un rover a Marte (como Perseverance): etapa de crucero con paneles solares en anillo
## y, debajo, la cápsula (coraza blanca arriba y escudo térmico abajo) con el rover plegado adentro.
## Medidas reales: 4,5 m de diámetro.
static func mars_capsule() -> Node3D:
	var root := Node3D.new()
	_cyl(root, 1.6, 2.25, 0.8, Vector3(0, 0.4, 0), _mat(Color(0.92, 0.92, 0.94), 0.5)) # coraza
	_cyl(root, 0.6, 1.6, 1.2, Vector3(0, 1.4, 0), _mat(Color(0.92, 0.92, 0.94), 0.5))
	_cyl(root, 2.25, 0.4, 0.7, Vector3(0, -0.35, 0), _mat(Color(0.32, 0.22, 0.15), 0.8)) # escudo térmico
	# Etapa de crucero arriba: disco con celdas solares
	_cyl(root, 2.0, 2.0, 0.25, Vector3(0, 2.2, 0), _mat(Color(0.75, 0.75, 0.78), 0.4, 0.6))
	for k in 10:
		var a := TAU * k / 10.0
		var cell := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.7, 0.04, 1.0)
		cell.mesh = b
		cell.material_override = _mat(Color(0.08, 0.12, 0.35), 0.3, 0.5)
		cell.position = Vector3(cos(a) * 1.45, 2.34, sin(a) * 1.45)
		cell.rotation.y = -a
		root.add_child(cell)
	return root
