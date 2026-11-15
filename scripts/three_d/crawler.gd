class_name Crawler
extends Node3D
## Oruga transportadora (inspirada en las de la NASA): cuatro trenes de orugas, chasis,
## gatos hidráulicos, dos cabinas y una mesa de lanzamiento arriba con el foso de llamas.
## El cohete viaja parado sobre la mesa y despega desde ella.
## La parte de arriba de la mesa queda en y = HangarWorld.DECK_H (coordenadas locales).

var width := 16.0
var _treads: Array[ORMMaterial3D] = []
var _dist := 0.0


func build(world: HangarWorld, rocket_d: float) -> void:
	# Modelo real de la NASA (Crawler-Transporter), 40 m de largo: avanza a lo largo de su eje largo
	var model := ModelPlace.place(self, HangarWorld.NASA + "crawler.glb", 4.55, Vector3(0, 90, 0), Vector3.ZERO)
	ModelPlace.dress(model, "metal", 2.0) # las partes sin textura, con chapa de verdad
	var box := ModelPlace.bounds(model, self)
	width = box.size.x
	# La parte de arriba del modelo debe coincidir con DECK_H (donde va parado el cohete)
	model.position.y += HangarWorld.DECK_H - box.end.y
	# Mesa de lanzamiento sobre la oruga, con foso de llamas, del tamaño del cohete
	var paint := world.pbr("crawler_paint", "metal_plate", 2.0, Color(0.85, 0.86, 0.84))
	var hole := maxf(rocket_d * 1.4, 2.0)
	var side := maxf(rocket_d * 1.2, 2.0)
	var s := hole + side * 2.0
	var y := HangarWorld.DECK_H - 0.2
	_box(Vector3(s, 0.4, side), Vector3(0, y, -(hole + side) / 2.0), paint)
	_box(Vector3(s, 0.4, side), Vector3(0, y, (hole + side) / 2.0), paint)
	_box(Vector3(side, 0.4, hole), Vector3(-(hole + side) / 2.0, y, 0), paint)
	_box(Vector3(side, 0.4, hole), Vector3((hole + side) / 2.0, y, 0), paint)


## Avanza la textura de las orugas según la distancia recorrida.
func roll(distance: float) -> void:
	_dist += distance
	for m in _treads:
		m.uv1_offset = Vector3(0, -_dist * 0.25, 0)


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	add_child(m)
	return m


## Altura del suelo a lo largo del camino (piso, rampa, plataforma) y su inclinación.
static func ground_at(z: float) -> Vector2:
	var pad_edge := HangarWorld.PAD_Z - 35.0
	var ramp_start := pad_edge - HangarWorld.RAMP_LEN
	if z <= ramp_start:
		return Vector2(0.0, 0.0)
	if z >= pad_edge:
		return Vector2(HangarWorld.PAD_SURFACE, 0.0)
	var k := (z - ramp_start) / HangarWorld.RAMP_LEN
	return Vector2(k * HangarWorld.PAD_SURFACE, atan2(HangarWorld.PAD_SURFACE, HangarWorld.RAMP_LEN))
