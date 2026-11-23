# Look pass (a test, switched on with --look): painted stone, a painting for the far
# distance, roots over the gate, a lantern, drifting dust and a painterly screen filter.
extends RefCounted

const M = preload("res://scripts/models.gd")
const ROCK = preload("res://shaders/rock.gdshader")
# Sculpted sets switched on so far (the others are built but still being placed).
const SETS_READY := ["pathway", "corridors", "chamber", "nest"]

static func rock(base: Color, disp := 0.25, moss := 0.5, strata := 0.5, scale := 0.55) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ROCK
	m.set_shader_parameter("base_col", base)
	m.set_shader_parameter("dark_col", base.darkened(0.3))
	m.set_shader_parameter("disp", disp)
	m.set_shader_parameter("moss", moss)
	m.set_shader_parameter("strata", strata)
	m.set_shader_parameter("scale", scale)
	return m

# Screen filter, under the story UI (which sits on layer 5).
static func add_filter(host: Node) -> void:
	var cl := CanvasLayer.new()
	cl.layer = 1
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/paint.gdshader")
	r.material = sm
	cl.add_child(r)
	host.add_child(cl)

# Swap the flat colours on a stage's blocks for painted stone.
static func dress(world, name: String) -> void:
	for n in world.stage.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.mesh is PrimitiveMesh:
			continue
		var sm = mi.material_override
		if not sm is StandardMaterial3D or sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or sm.emission_enabled or sm.albedo_texture:
			continue
		if sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			continue
		var c: Color = sm.albedo_color
		if c.get_luminance() < 0.04:
			continue  # black voids stay black
		var mesh: Mesh = mi.mesh
		if mesh is CylinderMesh and mesh.top_radius == 0.0 and name == "pathway":
			mi.visible = false  # the cone peaks: the painting takes over
			continue
		var flat: bool = mesh is BoxMesh and mesh.size.y < 0.3
		var disp: float = 0.0 if flat else 0.22
		if mesh is BoxMesh:
			var s: Vector3 = mesh.size * mi.global_transform.basis.get_scale()
			mesh = mesh.duplicate()
			mesh.subdivide_width = clampi(int(s.x / 0.35), 0, 30)
			mesh.subdivide_height = clampi(int(s.y / 0.35), 0, 30)
			mesh.subdivide_depth = clampi(int(s.z / 0.35), 0, 30)
			mi.mesh = mesh
		elif mesh is SphereMesh:
			mesh = mesh.duplicate()
			mesh.radial_segments = 24
			mesh.rings = 16
			mi.mesh = mesh
			disp = 0.35
		var base := c.lightened(0.05)
		if name == "pathway":
			base = c.lerp(Color("6e6862"), 0.6)
		mi.material_override = rock(base, disp, 0.6 if name == "pathway" else 0.15, 0.0 if flat else 0.5)
	var set_path := "res://models/set_%s.glb" % name
	if name in SETS_READY and ResourceLoader.exists(set_path):
		_diorama(world, set_path)
	match name:
		"pathway":
			_pathway(world)
		"corridors":
			_corridors(world)
		"chamber":
			_chamber(world)
		"nest":
			_nest(world)

# Surfaces of a sculpted set, by material name: [colour, moss, strata, streaks].
const SURF := {
	"wallstone": [Color("4a4640"), 0.2, 0.3, 0.3],
	"cavefloor": [Color("3a342c"), 0.1, 0.0, 0.0],
	"caverock": [Color("4a443e"), 0.1, 0.4, 0.2],
	"bark": [Color("4e3c2c"), 0.1, 0.0, 0.45],
	"heartwood": [Color("2a1e16"), 0.0, 0.0, 0.3],
	"thorn": [Color("bcb89e"), 0.0, 0.0, 0.0],
	"bone": [Color("cfc7b0"), 0.0, 0.0, 0.0],
	"cliff": [Color("66625c"), 0.35, 0.2, 0.3],
	"gatestone": [Color("62605a"), 0.3, 0.3, 0.25],
	"ground": [Color("4a4436"), 0.9, 0.0, 0.0],
	"flag": [Color("5c574f"), 0.35, 0.0, 0.0],
	"rock": [Color("625e58"), 0.45, 0.0, 0.0],
	"root": [Color("4a3c30"), 0.15, 0.0, 0.4],
}

# Adrian's painted textures (art/tex_*.webp): which one each surface uses, and its size.
const TEX_ALIAS := {"bark": "root", "thorn": "root", "heartwood": "root"}
const TEX_SCALE := {"cliff": 0.16, "gatestone": 0.2, "flag": 0.45, "ground": 0.28, "rock": 0.5,
	"root": 0.55, "bark": 0.22, "wallstone": 0.3, "cavefloor": 0.25, "caverock": 0.18, "thorn": 1.2}
const TEX_TINT := {"cliff": Color(1.0, 0.95, 0.88), "ground": Color(0.85, 0.9, 0.8), "bark": Color(1.0, 0.85, 0.68), "heartwood": Color(0.55, 0.45, 0.38)}

# A Blender-sculpted set replaces the stage's blocks; the blocks stay for walking into.
static func _diorama(world, path: String) -> void:
	# hide only the stage's plain scenery: not story props, webs, glows or the dark voids
	var keep := {}
	for v in world.props.values():
		for x in (v if v is Array else [v]):
			if x is Node:
				keep[x] = true
	for n in world.stage.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.mesh is PrimitiveMesh:
			continue
		var par := mi.get_parent()
		if not (par == world.stage or (par is StaticBody3D and par.get_parent() == world.stage)):
			continue
		if keep.has(mi) or keep.has(par):
			continue
		var sm = mi.material_override
		if sm is ShaderMaterial and sm.shader == ROCK:
			mi.visible = false
			continue
		if not sm is StandardMaterial3D or sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or sm.emission_enabled or sm.albedo_texture:
			continue
		if sm.albedo_color.get_luminance() < 0.04:
			continue
		mi.visible = false
	var set_node: Node3D = M.glb(path.get_file().get_basename())
	world.stage.add_child(set_node)
	world.props.diorama = true
	_paint_set(set_node)

# Give a sculpted model the painted surfaces, by material name.
static func _paint_set(set_node: Node3D) -> void:
	for n in set_node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var key := src.resource_name if src else ""
			if key in ["ember", "silk"]:
				continue  # glowing cracks and silk keep their own materials
			var spec: Array = SURF.get(key, [Color("5a5650"), 0.3, 0.3, 0.0])
			var m := rock(spec[0], 0.0, spec[1], spec[2])
			m.set_shader_parameter("streaks", spec[3])
			m.set_shader_parameter("grime", 0.0 if key in ["ground", "flag"] else 0.8)
			var tk: String = TEX_ALIAS.get(key, key)
			var tp := "res://art/tex_%s.webp" % tk
			if ResourceLoader.exists(tp):
				m.set_shader_parameter("tex", load(tp))
				m.set_shader_parameter("use_tex", 1.0)
				m.set_shader_parameter("tex_scale", TEX_SCALE.get(key, 0.22))
				m.set_shader_parameter("bump", 0.35)
				m.set_shader_parameter("tex_tint", TEX_TINT.get(key, Color.WHITE))
			mi.set_surface_override_material(i, m)

static func _pathway(world) -> void:
	# the painting, far off behind the gate
	var q := QuadMesh.new()
	q.size = Vector2(360, 220)
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://shaders/backdrop.gdshader")
	bm.set_shader_parameter("tex", load("res://art/bg_pathway.webp"))
	bm.set_shader_parameter("bright", 1.0)
	bm.set_shader_parameter("mirror", false)
	bm.set_shader_parameter("top", 0.0)
	bm.set_shader_parameter("bottom", 1.0)
	var bd := M.part(world.stage, q, bm, Vector3(-20, 10, -120))
	bd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	if world.props.get("diorama", false):
		# the dark inside the doorway's arch
		M.part(world.stage, M.box(4.0, 4.0, 0.3), M.mat(Color("050404")), Vector3(0, 6.5, -32.6))
		_lantern(world)
		_dust(world.stage, Vector3(0, 2, -20), Vector3(5, 2.5, 10), Color(1.0, 0.85, 0.7, 0.35))
		return
	# roots poured over the gate, around the doorway
	var bark := rock(Color("4a3c2e"), 0.0, 0.0, 0.0)
	bark.set_shader_parameter("streaks", 0.8)
	bark.set_shader_parameter("grime", 0.0)
	for i in 26:
		var x := rng.randf_range(-7.0, 7.0)
		_root(world.stage, Vector3(x, 9.6, -31.1), 0.2 * rng.randf_range(0.7, 1.2), rng, bark, 0)
	_lantern(world)
	_tufts(world, rng)
	_dust(world.stage, Vector3(0, 2, -14), Vector3(5, 2.5, 18), Color(1.0, 0.85, 0.7, 0.35))

static func _lantern(world) -> void:
	# a lantern hung in the doorway, like the painting
	var lan := Node3D.new()
	lan.position = Vector3(0, 4.4, -31.7)
	world.stage.add_child(lan)
	M.limb(lan, Vector3(0, 0.4, 0), Vector3(0, 1.3, 0), 0.015, M.mat(Color("222")))
	M.part(lan, M.box(0.32, 0.42, 0.32), M.glow(Color("ffb050"), 3.0))
	var ll := OmniLight3D.new()
	ll.light_color = Color("ffa040")
	ll.light_energy = 2.4
	ll.omni_range = 9.0
	lan.add_child(ll)

static func _tufts(world, rng: RandomNumberGenerator) -> void:
	# tufts along the verges
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = M.cyl(0.0, 0.09, 0.45, 4)
	mm.instance_count = 900
	for i in mm.instance_count:
		var side := -1.0 if i % 2 == 0 else 1.0
		var p := Vector3(side * rng.randf_range(1.5, 3.4), 0.18, rng.randf_range(-30.0, 8.0))
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3(1, 0, 0), rng.randf_range(-0.4, 0.4)).scaled(Vector3.ONE * rng.randf_range(0.5, 1.4)), p)
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, Color("4a5232").lerp(Color("7a6a40"), rng.randf()).darkened(rng.randf_range(0, 0.4)))
	var tm := StandardMaterial3D.new()
	tm.vertex_color_use_as_albedo = true
	tm.roughness = 1.0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = tm
	world.stage.add_child(mmi)

static func _root(parent: Node3D, p: Vector3, r: float, rng: RandomNumberGenerator, m: Material, depth: int) -> void:
	var dir := Vector3(rng.randf_range(-0.3, 0.3), -1, 0).normalized()
	var steps := rng.randi_range(8, 18)
	for s in steps:
		var np := p + dir * rng.randf_range(0.35, 0.55)
		# go round the doorway
		if abs(np.x) < 2.0 and np.y < 6.2:
			np.x = sign(np.x + 0.001) * (2.0 + rng.randf_range(0, 0.3))
		np.z = -31.15 + rng.randf_range(0.0, 0.25)
		if np.y < 0.0:
			break
		M.limb(parent, p, np, r, m)
		M.part(parent, M.sph(r * 1.15, 6), m, np)
		p = np
		r = max(0.035, r * 0.93)
		dir = (dir + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.2, 0.1), 0)).normalized()
		if dir.y > -0.3:
			dir.y = -0.3
		if depth < 2 and rng.randf() < 0.18:
			_root(parent, p, r * 0.6, rng, m, depth + 1)

static func shaft(parent: Node3D, top: Vector3, bottom: Vector3, r: float, c: Color, strength := 0.35, light := 1.6) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	var h := top.distance_to(bottom)
	cm.top_radius = r * 0.6
	cm.bottom_radius = r
	cm.height = h
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 20
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/shaft.gdshader")
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("strength", strength)
	var mi := M.part(parent, cm, m, (top + bottom) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var up := (top - bottom).normalized()
	if abs(up.dot(Vector3.UP)) < 0.999:
		mi.basis = Basis(Quaternion(Vector3.UP, up))
	# and the light it brings
	var sl := SpotLight3D.new()
	sl.light_color = c
	sl.light_energy = light
	sl.spot_range = h + 2.0
	sl.spot_angle = rad_to_deg(atan(r / h)) * 1.4
	sl.shadow_enabled = false
	parent.add_child(sl)
	sl.global_position = top
	sl.look_at(bottom, Vector3.FORWARD if abs(up.dot(Vector3.UP)) > 0.99 else Vector3.UP)
	return mi

static func _ember_lights(world, xs: Array, zs: Array, c: Color) -> void:
	for i in xs.size():
		var l := OmniLight3D.new()
		l.light_color = c
		l.light_energy = 1.2
		l.omni_range = 3.5
		l.position = Vector3(xs[i], 1.6, zs[i])
		world.stage.add_child(l)

static func _corridors(world) -> void:
	_ember_lights(world, [-1.7, 1.7, -1.7, 1.7, 1.7], [2.0, -2.5, -7.0, -10.0, -19.0], Color("ff7a28"))
	shaft(world.stage, Vector3(0.6, 9.0, -8.5), Vector3(-0.2, 0.0, -9.5), 1.0, Color("a8c8ff"), 0.14)
	shaft(world.stage, Vector3(-0.4, 9.0, -19.5), Vector3(0.3, 0.0, -20.5), 0.9, Color("a8c8ff"), 0.12)
	_dust(world.stage, Vector3(0, 2, -8), Vector3(1.6, 2.0, 12), Color(1.0, 0.8, 0.6, 0.4))

# The dead trunk: the sculpted halves ride on the same bodies the story moves apart.
static func _trunk(world) -> void:
	var trunk: Node3D = world.props.get("trunk")
	if trunk == null or not ResourceLoader.exists("res://models/trunk_front_l.glb"):
		return
	for b in trunk.get_children():
		if b is StaticBody3D:
			for c in b.get_children():
				if c is MeshInstance3D:
					c.visible = false
	for nm in ["trunk_front_l", "trunk_front_r"]:
		var g := M.glb(nm)
		trunk.add_child(g)
		_paint_set(g)
	var back: Array = world.props.trunk_back
	if back.is_empty():
		return
	back.sort_custom(func(a, b): return a.position.x < b.position.x)
	for pair in [["trunk_back_l", back[back.size() - 1]], ["trunk_back_r", back[0]]]:
		var g := M.glb(pair[0])
		var body: Node3D = pair[1]
		body.add_child(g)
		g.transform = body.transform.affine_inverse()
		_paint_set(g)

static func _far(world, pos: Vector3, size: Vector2) -> void:
	var q := QuadMesh.new()
	q.size = size
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://shaders/backdrop.gdshader")
	bm.set_shader_parameter("tex", load("res://art/bg_under.webp"))
	bm.set_shader_parameter("mirror", false)
	bm.set_shader_parameter("top", 0.0)
	bm.set_shader_parameter("bottom", 1.0)
	bm.set_shader_parameter("bright", 0.9)
	var mi := M.part(world.stage, q, bm, pos)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _chamber(world) -> void:
	_trunk(world)
	var warm := OmniLight3D.new()
	warm.light_color = Color("ffb070")
	warm.light_energy = 1.4
	warm.omni_range = 6.0
	warm.position = Vector3(1.5, 3.5, 1.5)
	world.stage.add_child(warm)
	_far(world, Vector3(0, 2.2, -16.6), Vector2(3.6, 4.6))
	shaft(world.stage, Vector3(1.8, 12.0, 0.6), Vector3(0.6, 0.0, 1.0), 1.3, Color("ffd8a0"), 0.14)
	_dust(world.stage, Vector3(0, 3, -1), Vector3(4, 3.0, 4), Color(1.0, 0.85, 0.6, 0.5))

static func _nest(world) -> void:
	_far(world, Vector3(0, 2.4, -16.6), Vector2(4.0, 5.0))
	var back := DirectionalLight3D.new()
	back.light_color = Color("6070a0")
	back.light_energy = 0.2
	back.rotation_degrees = Vector3(-50, 160, 0)
	world.stage.add_child(back)
	shaft(world.stage, Vector3(0.6, 13.0, 0.6), Vector3(0.0, 0.0, 1.2), 2.4, Color("b8c8ff"), 0.14, 0.8)
	_eggs(world)
	_dust(world.stage, Vector3(0, 2, 0), Vector3(7, 2.5, 7), Color(1.0, 0.75, 0.45, 0.45))

# The egg sacs, as in Adrian's painting: gathered in clutches, mottled dark shells under
# glistening silk.
static func _eggs(world) -> void:
	var eggs: Array = world.props.get("eggs", [])
	if eggs.is_empty():
		return
	var shell := rock(Color("5e574c"), 0.0, 0.0, 0.0, 1.6)
	shell.set_shader_parameter("grime", 0.6)
	shell.set_shader_parameter("bump", 0.8)
	if ResourceLoader.exists("res://art/tex_caverock.webp"):
		shell.set_shader_parameter("tex", load("res://art/tex_caverock.webp"))
		shell.set_shader_parameter("use_tex", 0.55)
		shell.set_shader_parameter("tex_scale", 0.9)
	var silk := StandardMaterial3D.new()
	silk.albedo_color = Color("d8d0bc")
	silk.roughness = 0.18
	silk.metallic_specular = 0.9
	silk.emission_enabled = true
	silk.emission = Color("6a6050")
	silk.emission_energy_multiplier = 0.25
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	# clutches round the back of the nest, behind Ryytaa and along the walls
	var centres := [Vector3(-2.6, 0, -6.6), Vector3(2.8, 0, -6.4), Vector3(-6.4, 0, -3.0), Vector3(6.6, 0, -2.6), Vector3(-7.0, 0, 2.6), Vector3(7.2, 0, 3.0)]
	for i in eggs.size():
		var e: Node3D = eggs[i]
		var c: Vector3 = centres[i % centres.size()]
		var k := i / centres.size()
		var ang := rng.randf() * TAU
		e.position = c + Vector3(cos(ang), 0, sin(ang)) * (0.0 if k == 0 else 0.85 + 0.25 * k)
		var sc := rng.randf_range(0.8, 1.25) * (1.2 if k == 0 else 1.0)
		e.scale = Vector3(sc, sc * rng.randf_range(0.92, 1.08), sc)
		e.rotation.y = rng.randf() * TAU
		for n in e.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			for si in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(si)
				var nm := src.resource_name if src else ""
				if nm == "egg_sac":
					mi.set_surface_override_material(si, shell)
				elif nm == "egg_silk":
					mi.set_surface_override_material(si, silk)
	# a soft light low among each clutch, so the silk catches
	for c in centres:
		var l := OmniLight3D.new()
		l.light_color = Color("c8b898")
		l.light_energy = 0.5
		l.omni_range = 2.6
		l.position = c + Vector3(0, 1.4, 1.0)
		world.stage.add_child(l)

static func _dust(parent: Node3D, at: Vector3, ext: Vector3, c: Color) -> void:
	var d := CPUParticles3D.new()
	d.position = at
	d.amount = 160
	d.lifetime = 8.0
	d.preprocess = 8.0
	d.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	d.emission_box_extents = ext
	d.gravity = Vector3(0, 0.02, 0)
	d.initial_velocity_min = 0.02
	d.initial_velocity_max = 0.1
	d.direction = Vector3(0.3, 1, 0)
	d.spread = 180
	var q := QuadMesh.new()
	q.size = Vector2(0.02, 0.02)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	q.material = m
	d.mesh = q
	parent.add_child(d)
