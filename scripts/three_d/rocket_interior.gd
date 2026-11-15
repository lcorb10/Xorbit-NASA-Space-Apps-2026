class_name RocketInterior
extends RefCounted
## Lo que hay dentro del cohete, para la vista en corte del hangar (la piel se corta con el shader
## rocket_skin y esto se ve detrás): tanques con el oxidante arriba y el combustible abajo, el túnel
## de alimentación, el grano del motor sólido con su canal central, pernos del desacoplador y la sonda
## con sus instrumentos, energía y antena (según data/science.json). Cada cosa lleva su nombre.

static func build(design: Array, analysis: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Interior"
	var height := float(analysis.get("height", 0.0))
	var parts: Array = analysis.get("parts", [])
	for info: Dictionary in parts:
		var p: Dictionary = design[int(info.index)]
		var top := height - float(info.y)
		var plen := float(info.length)
		var r := float(info.diameter) / 2.0 * 0.93
		var bottom := top - plen
		match str(info.kind):
			"tank":
				_tank(root, p, top, bottom, r)
			"solid":
				_solid(root, top, bottom, r)
			"payload":
				_probe(root, p, top, bottom, r)
			"decoupler":
				for k in 8:
					var a := TAU * k / 8.0
					var b := _cyl(root, 0.06 * r + 0.03, 0.06 * r + 0.03, plen * 0.8, Vector3(cos(a) * r * 0.9, (top + bottom) / 2.0, sin(a) * r * 0.9), _mat(Color(0.75, 0.7, 0.2), 0.8))
					b.name = "Bolt"
				_label(root, "IN_BOLTS", Vector3(r * 1.3, (top + bottom) / 2.0, 0))
			"engine":
				_label(root, "IN_ENGINE", Vector3(r * 1.3, (top + bottom) / 2.0, 0))
			"nose":
				_label(root, "IN_NOSE", Vector3(r * 0.4 + 0.3, bottom + plen * 0.35, 0))
	return root


static func _tank(root: Node3D, p: Dictionary, top: float, bottom: float, r: float) -> void:
	var prop := str(p.get("propellant", "lox_rp1"))
	var plen := top - bottom
	# Oxígeno líquido arriba (como en el Saturno V y el Falcon 9) y combustible abajo; el hidrógeno
	# ocupa mucho más volumen porque es muy liviano
	var ox_frac := 0.55 if prop == "lox_rp1" else (0.3 if prop == "lox_lh2" else 0.45)
	var mid := bottom + plen * (1.0 - ox_frac)
	var lox := _cyl(root, r * 0.97, r * 0.97, top - mid - plen * 0.04, Vector3(0, (top + mid) / 2.0 - plen * 0.02, 0), _liquid(Color(0.55, 0.75, 1.0), 0.5))
	lox.name = "LOX"
	var fuel_col := Color(0.95, 0.62, 0.2) if prop == "lox_rp1" else (Color(0.85, 0.92, 1.0) if prop == "lox_lh2" else Color(0.75, 0.8, 0.4))
	var fuel := _cyl(root, r * 0.97, r * 0.97, mid - bottom - plen * 0.04, Vector3(0, (mid + bottom) / 2.0 + plen * 0.02, 0), _liquid(fuel_col, 0.45))
	fuel.name = "Fuel"
	# Mamparo entre los dos y túnel del oxígeno que baja por dentro del combustible hasta el motor
	_cyl(root, r, r, 0.04 + r * 0.02, Vector3(0, mid, 0), _mat(Color(0.6, 0.62, 0.65), 0.6))
	_cyl(root, r * 0.09 + 0.02, r * 0.09 + 0.02, mid - bottom + 0.3, Vector3(0, (mid + bottom) / 2.0 - 0.15, 0), _mat(Color(0.8, 0.82, 0.85), 0.7))
	_label(root, "IN_LOX", Vector3(r * 1.25, (top + mid) / 2.0, 0))
	_label(root, "IN_RP1" if prop == "lox_rp1" else ("IN_LH2" if prop == "lox_lh2" else "IN_FUEL"), Vector3(r * 1.25, (mid + bottom) / 2.0, 0))


static func _solid(root: Node3D, top: float, bottom: float, r: float) -> void:
	var plen := top - bottom
	# Grano de propelente sólido (gris) con el canal central donde arde (naranja)
	var grain := _cyl(root, r * 0.97, r * 0.97, plen * 0.94, Vector3(0, (top + bottom) / 2.0, 0), _mat(Color(0.42, 0.4, 0.37), 0.9))
	grain.name = "Grain"
	var core := StandardMaterial3D.new()
	core.albedo_color = Color(1.0, 0.45, 0.1)
	core.emission_enabled = true
	core.emission = Color(1.0, 0.45, 0.1)
	core.emission_energy_multiplier = 1.5
	_cyl(root, r * 0.28, r * 0.28, plen * 0.95, Vector3(0, (top + bottom) / 2.0, 0), core)
	_label(root, "IN_GRAIN", Vector3(r * 1.25, (top + bottom) / 2.0, 0))


static func _probe(root: Node3D, p: Dictionary, top: float, bottom: float, r: float) -> void:
	var cfg: Dictionary = p.get("probe", {})
	var plen := top - bottom
	var cy := (top + bottom) / 2.0
	# Cuerpo de la sonda envuelto en aislante dorado (manta térmica)
	var bus_h := minf(plen * 0.55, r * 1.3)
	var bus := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(r * 1.0, bus_h, r * 1.0)
	bus.mesh = bm
	bus.material_override = _mat(Color(0.95, 0.72, 0.25), 0.35, 0.9)
	bus.position = Vector3(0, cy, 0)
	root.add_child(bus)
	_label(root, "IN_PROBE", Vector3(r * 1.3, cy + bus_h * 0.4, 0))
	# Instrumentos alrededor del cuerpo
	var items: Array = cfg.get("instruments", [])
	for k in items.size():
		var a := TAU * (k + 0.5) / maxf(items.size(), 1.0)
		var pos := Vector3(cos(a) * r * 0.62, cy + bus_h * 0.15, sin(a) * r * 0.62)
		var it := Probe.item("instruments", str(items[k]))
		var node := _instrument(str(items[k]), r)
		node.position = pos
		root.add_child(node)
		_label(root, "", pos + Vector3(0, r * 0.25, 0), Codex.pick(it.get("name", {})), 0.75)
	# Energía: paneles plegados a los lados, RTG abajo o batería
	match str(cfg.get("power", "battery")):
		"solar_small", "solar_big":
			for s in [-1.0, 1.0]:
				var pn := MeshInstance3D.new()
				var pm := BoxMesh.new()
				pm.size = Vector3(0.03, bus_h * 0.9, r * 0.8)
				pn.mesh = pm
				pn.material_override = _mat(Color(0.08, 0.12, 0.35), 0.3, 0.6)
				pn.position = Vector3(s * r * 0.55, cy, 0)
				root.add_child(pn)
			_label(root, "IN_SOLAR", Vector3(-r * 1.3, cy, 0))
		"rtg":
			var rtg := _cyl(root, r * 0.16, r * 0.16, bus_h * 0.6, Vector3(0, cy - bus_h * 0.5 - bus_h * 0.25, 0), _mat(Color(0.2, 0.2, 0.22), 0.5, 0.7))
			for k in 6:
				var fa := TAU * k / 6.0
				var fin := MeshInstance3D.new()
				var fm := BoxMesh.new()
				fm.size = Vector3(r * 0.18, bus_h * 0.55, 0.02)
				fin.mesh = fm
				fin.material_override = rtg.material_override
				fin.position = rtg.position + Vector3(cos(fa) * r * 0.2, 0, sin(fa) * r * 0.2)
				fin.rotation.y = -fa
				root.add_child(fin)
			_label(root, "IN_RTG", rtg.position + Vector3(-r * 1.2, 0, 0))
		_:
			var bat := MeshInstance3D.new()
			var btm := BoxMesh.new()
			btm.size = Vector3(r * 0.4, bus_h * 0.25, r * 0.3)
			bat.mesh = btm
			bat.material_override = _mat(Color(0.15, 0.15, 0.17), 0.6)
			bat.position = Vector3(0, cy - bus_h * 0.5 - bus_h * 0.13, 0)
			root.add_child(bat)
			_label(root, "IN_BATTERY", bat.position + Vector3(-r * 1.2, 0, 0))
	# Antena arriba
	var ant_y := cy + bus_h * 0.5
	match str(cfg.get("antenna", "whip")):
		"dish":
			var d := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = r * 0.45
			sm.height = r * 0.3
			sm.is_hemisphere = true
			d.mesh = sm
			d.material_override = _mat(Color(0.92, 0.92, 0.9), 0.4, 0.3)
			d.rotation.x = PI
			d.position = Vector3(0, ant_y + r * 0.32, 0)
			root.add_child(d)
		"patch":
			var pt := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(r * 0.35, 0.03, r * 0.35)
			pt.mesh = pb
			pt.material_override = _mat(Color(0.85, 0.85, 0.82), 0.4)
			pt.position = Vector3(0, ant_y + 0.05, 0)
			root.add_child(pt)
		_:
			_cyl(root, 0.012, 0.012, r * 0.6, Vector3(0, ant_y + r * 0.3, 0), _mat(Color(0.8, 0.8, 0.8), 0.4, 0.8))
	_label(root, "IN_ANTENNA", Vector3(r * 1.2, ant_y + r * 0.2, 0))


static func _instrument(id: String, r: float) -> Node3D:
	var n := Node3D.new()
	var s := r * 0.18
	match id:
		"camera":
			var body := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(s, s, s * 1.4)
			body.mesh = b
			body.material_override = _mat(Color(0.12, 0.12, 0.14), 0.4)
			n.add_child(body)
			var lens := _cyl(n, s * 0.35, s * 0.35, s * 0.5, Vector3(0, 0, s * 0.9), _mat(Color(0.2, 0.35, 0.6), 0.1, 0.8))
			lens.rotation.x = PI / 2.0
		"magnetometer":
			_cyl(n, s * 0.06, s * 0.06, s * 4.0, Vector3(0, s * 2.0, 0), _mat(Color(0.85, 0.85, 0.8), 0.5))
			var head := MeshInstance3D.new()
			var hb := BoxMesh.new()
			hb.size = Vector3(s * 0.5, s * 0.5, s * 0.5)
			head.mesh = hb
			head.material_override = _mat(Color(0.9, 0.9, 0.9), 0.5)
			head.position.y = s * 4.0
			n.add_child(head)
		"drill":
			_cyl(n, s * 0.12, s * 0.05, s * 3.0, Vector3(0, -s * 1.5, 0), _mat(Color(0.7, 0.7, 0.72), 0.3, 0.9))
		"radar":
			var pl := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(s * 2.2, s * 0.15, s * 1.2)
			pl.mesh = pb
			pl.material_override = _mat(Color(0.3, 0.3, 0.32), 0.5)
			n.add_child(pl)
		_:
			var box := MeshInstance3D.new()
			var bb := BoxMesh.new()
			bb.size = Vector3(s, s * 0.8, s)
			box.mesh = bb
			box.material_override = _mat(Color(0.75, 0.75, 0.78) if id == "thermo" else Color(0.35, 0.4, 0.5), 0.5, 0.4)
			n.add_child(box)
	return n


static func _cyl(parent: Node3D, top_r: float, bottom_r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = maxf(h, 0.01)
	c.radial_segments = 32
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


## Líquido: un poco translúcido y con brillo propio para que se distinga en la penumbra del corte.
static func _liquid(c: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c, alpha + 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.35
	m.roughness = 0.1
	m.metallic_specular = 0.8
	return m


static func _label(root: Node3D, key: String, pos: Vector3, text := "", scale := 1.0) -> void:
	var l := Label3D.new()
	l.text = text if text != "" else TranslationServer.translate(key)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0005 * scale
	l.font_size = 26
	l.outline_size = 10
	l.modulate = Color(1.0, 0.85, 0.6)
	l.no_depth_test = true
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.position = pos
	root.add_child(l)
