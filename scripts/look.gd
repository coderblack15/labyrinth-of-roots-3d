# Look pass (a test, switched on with --look): painted stone, a painting for the far
# distance, roots over the gate, a lantern, drifting dust and a painterly screen filter.
extends RefCounted

const M = preload("res://scripts/models.gd")
const ROCK = preload("res://shaders/rock.gdshader")

static func rock(base: Color, disp := 0.25, moss := 0.5, strata := 0.5, scale := 0.55) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ROCK
	m.set_shader_parameter("base_col", base)
	m.set_shader_parameter("dark_col", base.darkened(0.35))
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
	match name:
		"pathway":
			_pathway(world)
		"nest":
			_nest(world)

static func _pathway(world) -> void:
	# the painting, far off behind the gate
	var q := QuadMesh.new()
	q.size = Vector2(260, 120)
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://shaders/backdrop.gdshader")
	bm.set_shader_parameter("tex", load("res://art/sc_pathway.webp"))
	bm.set_shader_parameter("bright", 0.95)
	var bd := M.part(world.stage, q, bm, Vector3(0, 38, -120))
	bd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# roots poured over the gate, around the doorway
	var bark := rock(Color("4a3c2e"), 0.0, 0.0, 0.0)
	bark.set_shader_parameter("streaks", 0.8)
	bark.set_shader_parameter("grime", 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 26:
		var x := rng.randf_range(-7.0, 7.0)
		_root(world.stage, Vector3(x, 9.6, -31.1), 0.2 * rng.randf_range(0.7, 1.2), rng, bark, 0)
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
	_dust(world.stage, Vector3(0, 2, -14), Vector3(5, 2.5, 18), Color(1.0, 0.85, 0.7, 0.35))

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

static func _nest(world) -> void:
	var back := DirectionalLight3D.new()
	back.light_color = Color("6070a0")
	back.light_energy = 0.2
	back.rotation_degrees = Vector3(-50, 160, 0)
	world.stage.add_child(back)
	_dust(world.stage, Vector3(0, 2, 0), Vector3(7, 2.5, 7), Color(1.0, 0.75, 0.45, 0.45))

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
