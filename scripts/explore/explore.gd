# Exploring a dungeon: walk the maze with the thumb stick, find the key, search the walls,
# open the chest and the locked door. Walk into a fight and it plays on the tactics board;
# win and you come back to where you stood. The boss's door ends the dungeon.
# Created by: Adrian Blackshire and Claude.
extends Node3D

const M = preload("res://scripts/models.gd")
const LOOK = preload("res://scripts/look.gd")
const DG = preload("res://scripts/explore/dungeons.gd")
const MAPS = preload("res://scripts/tactics/maps.gd")
const TOKEN = preload("res://shaders/token.gdshader")
const CS := 4.0      # one maze cell
const WH := 3.2      # wall height

var main
var world
var auto := false
var d := {}
var th := {}
var key := ""
var grid := []
var W := 0
var H := 0
var rng := RandomNumberGenerator.new()
var state := {"key": false, "opened": {}, "broken": {}, "looted": {}, "cleared": {}}
var hp := 24
var max_hp := 24
var tier := 0     # the dungeon's place in the journey (0 for the first)
var busy := false
var done := ""
var bodies := {}     # Vector2i -> StaticBody3D for doors and cracked walls
var things := {}     # Vector2i -> Node3D (key, chest lid, lurking spiders)
var near = null      # the interactable cell in reach
var mats := {}
var lights_left := 10
var standees := []   # painted pieces in the corridors: they turn to face the camera

# the screen
var hud: CanvasLayer
var hp_lbl: Label
var hint: Label
var act_btn: Button
var ban: Label

func run(k: String) -> String:
	key = k
	d = DG.DUNGEONS[k]
	th = DG.THEMES[d.theme]
	grid = []
	for row in d.maze:
		grid.append(row)
	H = grid.size()
	tier = DG.ORDER.find(k)
	max_hp = 24 + tier * 2
	hp = max_hp
	W = grid[0].length()
	_hud()
	_gear_up()
	if _dbg("nohero"):
		world.player.visible = false
	build()
	world.place_player(cell_pos(find("P")) + Vector3(0, 0.1, 0), 0)
	if _dbg("count"):
		_count()
	await get_tree().process_frame
	main.ui.fade_in(0.8)
	banner(d.title, d.intro)
	if auto:
		_bot()
	while done == "":
		await get_tree().process_frame
	return done

func _gear_up() -> void:
	world._hold("hand_r", M.axe(), Vector3(0, -0.1, 0), Vector3(-50, 0, 0))
	world.hero_take_torch()
	world.torch_e = 4.5
	world.cam_offset = Vector3(0, 11.5, 4.2)
	world.cam_look_off = Vector3(0, 0.0, -1.2)
	world.speed = 5.0

# ---------------------------------------------------------------- building the maze
func ch(p: Vector2i) -> String:
	if p.x < 0 or p.y < 0 or p.x >= W or p.y >= H:
		return "#"
	return grid[p.y][p.x]

func find(c: String) -> Vector2i:
	for y in H:
		for x in W:
			if grid[y][x] == c:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func cell_pos(p: Vector2i) -> Vector3:
	return Vector3((p.x - (W - 1) * 0.5) * CS, 0, (p.y - (H - 1) * 0.5) * CS)

func cell_at(v: Vector3) -> Vector2i:
	return Vector2i(int(round(v.x / CS + (W - 1) * 0.5)), int(round(v.z / CS + (H - 1) * 0.5)))

func _stone(spec: Array) -> ShaderMaterial:
	var m := LOOK.rock(spec[1], 0.0, 0.0, 0.25, 0.9)
	var path := "res://art/tex_%s.webp" % spec[0]
	if ResourceLoader.exists(path):
		m.set_shader_parameter("tex", load(path))
		m.set_shader_parameter("use_tex", 0.85)
		m.set_shader_parameter("tex_scale", spec[2])
	return m

func build() -> void:
	world.clear_stage()
	world.stage_name = "maze"
	world.set_light("torch", 0.01)
	world.env.ambient_light_color = th.amb
	world.env.ambient_light_energy = 0.95
	world.env.fog_density = 0.02
	rng.seed = hash(key)
	bodies = {}
	standees = []
	things = {}
	lights_left = 6 if OS.has_feature("web") else 10
	mats.floor = _stone(th.floor)
	mats.wall = _stone(th.wall)
	mats.trim = _stone(th.trim)
	mats.earth = _stone([th.wall[0], th.wall[1].darkened(0.55), th.wall[2]])
	var p = th.plants
	mats.fern = M.mat(p.fern, 0.9)
	mats.moss = M.mat(p.moss.darkened(0.25), 1.0)
	mats.moss2 = M.mat(p.moss.lerp(Color("6a7a3a"), 0.4).darkened(0.2), 1.0)
	mats.cap = M.mat(p.fungus, 0.6, p.glow, 1.4)
	mats.stalk = M.mat(p.fungus.darkened(0.3), 0.8)
	mats.shard = M.mat(p.fungus, 0.1, p.glow, 0.5, 0.75, 0.4)
	mats.water = M.mat(Color("1a2a30"), 0.05, Color("2a4a58"), 0.2, 0.8, 0.3)
	# the floor, one slab under it all
	world.solid(Vector3(W * CS, 0.4, H * CS), Vector3(0, -0.2, 0), mats.floor)
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			var k := ch(c)
			var at := cell_pos(c)
			match k:
				"#":
					_wall(c, at)
				"S":
					if state.broken.has(c):
						_rubble(at)
					else:
						_cracked(c, at)
				"D":
					if not state.opened.has(c):
						_door(c, at)
				"K":
					if not state.key:
						_key(c, at)
				"C":
					_chest(c, at)
				"B":
					_boss_door(c, at)
				",":
					_overgrowth(at, 1.0)
				"~":
					_pool(at)
			if k in "123456789" and not state.cleared.has(c):
				_lurkers(c, at)
			if k != "#" and k != "," and rng.randf() < 0.35:
				_overgrowth(at, 0.4)
	_bake()

func _dbg(k: String) -> bool:
	return ("--dbg-" + k) in OS.get_cmdline_user_args()

# Merge the loose dressing (roots, moss, ferns, fungus, rocks) into one mesh per material.
# A maze makes a couple of thousand little pieces; as single meshes they swamp a phone or
# a browser's WebGL, merged they're a few dozen draws.
func _bake() -> void:
	var groups := {}
	for n in world.stage.get_children():
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or mi.material_override == null or mi.get_child_count() > 0:
			continue
		if not groups.has(mi.material_override):
			groups[mi.material_override] = []
		groups[mi.material_override].append(mi)
	for m in groups:
		var list: Array = groups[m]
		if list.size() < 3:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var shadow: int = list[0].cast_shadow
		for mi in list:
			for si in mi.mesh.get_surface_count():
				st.append_from(mi.mesh, si, mi.transform)
			world.stage.remove_child(mi)
			mi.free()
		var out := MeshInstance3D.new()
		out.mesh = st.commit()
		out.material_override = m
		out.cast_shadow = shadow
		world.stage.add_child(out)

func _count() -> void:
	print("meshes ", world.stage.find_children("*", "MeshInstance3D", true, false).size(), " lights ", world.stage.find_children("*", "Light3D", true, false).size())

func _wall(c: Vector2i, at: Vector3) -> void:
	var b: Node3D = world.solid(Vector3(CS, WH, CS), at + Vector3(0, WH * 0.5, 0), mats.wall)
	if _dbg("bare"):
		return
	# dress only the faces that show on the floor side
	for dd in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var n: Vector2i = c + dd
		if ch(n) == "#" or n.x < 0 or n.y < 0 or n.x >= W or n.y >= H:
			continue
		var face := at + Vector3(dd.x, 0, dd.y) * (CS * 0.5 + 0.02)
		var along := Vector3(dd.y, 0, dd.x)
		# hanging roots down the face
		for i in rng.randi_range(1, 3):
			var o := along * rng.randf_range(-1.6, 1.6)
			var top := face + o + Vector3(0, WH, 0)
			var bot := face + o + Vector3(dd.x, 0, dd.y) * rng.randf_range(0.05, 0.3) + Vector3(0, rng.randf_range(0.0, 1.6), 0)
			if not _dbg("noroots"):
				M.limb(world.stage, top, bot, rng.randf_range(0.04, 0.09), mats.trim)
		# moss along the foot of the wall
		for i in rng.randi_range(1, 3):
			if not _dbg("nomoss"):
				_moss(face + along * rng.randf_range(-1.6, 1.6), rng.randf_range(0.25, 0.45))
		if th.webs and rng.randf() < 0.18 and not _dbg("noweb"):
			world.web(face + along * rng.randf_range(-1.2, 1.2) + Vector3(dd.x, 0, dd.y) * 0.3 + Vector3(0, WH - 0.9, 0), 1.6, 1.4, Vector3(0, rad_to_deg(atan2(float(dd.y), float(dd.x))) + 90, 0), rng.randi())
	# the top: dark earth with a tangle of roots and moss, so the paths read as cut through it
	if _dbg("notop"):
		return
	M.part(world.stage, M.box(CS + 0.02, 0.12, CS + 0.02), mats.earth, at + Vector3(0, WH + 0.06, 0))
	for i in rng.randi_range(2, 4):
		var a := Vector3(rng.randf_range(-1.8, 1.8), WH + 0.12, rng.randf_range(-1.8, 1.8))
		var b2 := a + Vector3(rng.randf_range(-1.5, 1.5), 0.0, rng.randf_range(-1.5, 1.5))
		M.limb(world.stage, at + a, at + b2, rng.randf_range(0.06, 0.12), mats.trim)
	for i in rng.randi_range(1, 3):
		_moss(at + Vector3(rng.randf_range(-1.5, 1.5), WH + 0.12, rng.randf_range(-1.5, 1.5)), rng.randf_range(0.35, 0.6))

# Ferns, moss and pale glowing fungus.
func _overgrowth(at: Vector3, amount: float) -> void:
	if _dbg("noflora"):
		return
	var n := int(round(rng.randf_range(2, 6) * amount))
	for i in n:
		var p := at + Vector3(rng.randf_range(-1.6, 1.6), 0, rng.randf_range(-1.6, 1.6))
		var r := rng.randf()
		match th.get("flora", "cave"):
			"ice", "glass":
				if r < 0.6:
					_shards(p)
				elif r < 0.8:
					_rocks(p)
			"dry":
				if r < 0.5:
					_tuft(p)
				elif r < 0.85:
					_rocks(p)
				else:
					_moss(p, 0.2)
			"reed", "jungle":
				if r < 0.35:
					_reeds(p)
				elif r < 0.65:
					_fern(p)
				elif r < 0.9:
					_moss(p, rng.randf_range(0.2, 0.4))
				else:
					_fungus(p)
			"weed":
				if r < 0.25:
					_fern(p)
				elif r < 0.7:
					_moss(p, rng.randf_range(0.2, 0.4))
				elif r < 0.85:
					_rocks(p)
				else:
					_fungus(p)
			_:
				if r < 0.45:
					_fern(p)
				elif r < 0.8:
					_moss(p, rng.randf_range(0.2, 0.4))
				else:
					_fungus(p)

func _shards(p: Vector3) -> void:
	for i in rng.randi_range(2, 5):
		var h := rng.randf_range(0.3, 1.1)
		var o := p + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		M.part(world.stage, M.cyl(0.0, rng.randf_range(0.08, 0.18), h, 5), mats.shard, o + Vector3(0, h * 0.45, 0),
			Vector3(rng.randf_range(-20, 20), rng.randf() * 90, rng.randf_range(-20, 20)))
	if lights_left > 0 and rng.randf() < 0.4:
		lights_left -= 1
		var l := OmniLight3D.new()
		l.light_color = th.plants.glow
		l.light_energy = 0.5
		l.omni_range = 2.6
		l.position = p + Vector3(0, 0.6, 0)
		world.stage.add_child(l)

func _rocks(p: Vector3) -> void:
	for i in rng.randi_range(1, 3):
		var r := rng.randf_range(0.12, 0.35)
		M.part(world.stage, M.sph(r, 7), mats.wall, p + Vector3(rng.randf_range(-0.3, 0.3), r * 0.4, rng.randf_range(-0.3, 0.3)),
			Vector3(rng.randf() * 30, rng.randf() * 90, 0), Vector3(1.2, 0.7, 1))

func _tuft(p: Vector3) -> void:
	for i in rng.randi_range(6, 10):
		var h := rng.randf_range(0.3, 0.6)
		var a := rng.randf() * TAU
		var m := M.part(world.stage, M.cyl(0.006, 0.02, h, 4), mats.fern, p + Vector3(cos(a) * 0.06, h * 0.45, sin(a) * 0.06), Vector3(cos(a) * 25, 0, sin(a) * 25))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _reeds(p: Vector3) -> void:
	for i in rng.randi_range(5, 9):
		var h := rng.randf_range(0.8, 1.6)
		var o := p + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		var m := M.part(world.stage, M.cyl(0.012, 0.03, h, 4), mats.fern, o + Vector3(0, h * 0.5, 0), Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8)))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if rng.randf() < 0.4:
			M.part(world.stage, M.cyl(0.04, 0.04, 0.18, 6), mats.stalk, o + Vector3(0, h, 0))

# A lumpy clump of moss: a few small mounds in two greens, never a flat disc.
func _moss(p: Vector3, r: float) -> void:
	for i in rng.randi_range(3, 6):
		var o := p + Vector3(rng.randf_range(-r, r), 0, rng.randf_range(-r, r)) * 0.8
		var s := r * rng.randf_range(0.3, 0.55)
		var mi := M.part(world.stage, M.sph(s, 10), mats.moss if rng.randf() < 0.6 else mats.moss2, o + Vector3(0, s * 0.15, 0), Vector3.ZERO, Vector3(1, 0.55, 1))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _fern(p: Vector3) -> void:
	var k := rng.randi_range(5, 8)
	var s := rng.randf_range(0.6, 1.1)
	for i in k:
		var a := TAU * i / k + rng.randf() * 0.4
		var leaf := M.part(world.stage, M.sph(0.12, 6), mats.fern, p + Vector3(cos(a), 0.0, sin(a)) * 0.28 * s + Vector3(0, 0.22 * s, 0),
			Vector3(0, -rad_to_deg(a), 35), Vector3(3.2 * s, 0.25, 0.9 * s))
		leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _fungus(p: Vector3) -> void:
	for i in rng.randi_range(2, 4):
		var o := p + Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		var h := rng.randf_range(0.12, 0.35)
		M.part(world.stage, M.cyl(0.025, 0.035, h, 6), mats.stalk, o + Vector3(0, h * 0.5, 0))
		M.part(world.stage, M.sph(rng.randf_range(0.07, 0.13), 8), mats.cap, o + Vector3(0, h, 0), Vector3.ZERO, Vector3(1, 0.45, 1))
	if lights_left > 0 and rng.randf() < 0.5:
		lights_left -= 1
		var l := OmniLight3D.new()
		l.light_color = th.plants.glow
		l.light_energy = 0.6
		l.omni_range = 2.6
		l.position = p + Vector3(0, 0.4, 0)
		world.stage.add_child(l)

func _pool(at: Vector3) -> void:
	var q := PlaneMesh.new()
	q.size = Vector2(CS * 0.8, CS * 0.8)
	M.part(world.stage, q, mats.water, at + Vector3(0, 0.02, 0))
	for i in 5:
		var spot := at + Vector3(rng.randf_range(-1.8, 1.8), 0, rng.randf_range(-1.8, 1.8))
		match th.get("flora", "cave"):
			"ice", "glass":
				_shards(spot)
			"dry":
				_tuft(spot)
			"reed", "jungle":
				_reeds(spot)
			_:
				_fern(spot)

func _cracked(c: Vector2i, at: Vector3) -> void:
	var b: Node3D = world.solid(Vector3(CS, WH, CS), at + Vector3(0, WH * 0.5, 0), mats.wall)
	bodies[c] = b
	var gm := M.glow(Color("ffb060"), 1.6)
	for dd in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var n: Vector2i = c + dd
		if ch(n) == "#":
			continue
		var face := Vector3(dd.x, 0, dd.y) * (CS * 0.5 + 0.03)
		var along := Vector3(dd.y, 0, dd.x)
		for i in 5:
			var a := along * rng.randf_range(-0.8, 0.8) + Vector3(0, rng.randf_range(0.4, 2.2), 0)
			var cr := M.part(b, M.box(0.04, rng.randf_range(0.3, 0.8), 0.04), gm, face + a - Vector3(0, WH * 0.5, 0), Vector3(0, 0, 0))
			cr.rotation = Vector3(0, atan2(float(dd.x), float(dd.y)), rng.randf_range(-0.8, 0.8))

func _rubble(at: Vector3) -> void:
	for i in 8:
		M.part(world.stage, M.sph(rng.randf_range(0.2, 0.45), 6), mats.wall, at + Vector3(rng.randf_range(-1.6, 1.6), 0.1, rng.randf_range(-1.6, 1.6)), Vector3.ZERO, Vector3(1, 0.6, 1))

func _door(c: Vector2i, at: Vector3) -> void:
	var b: Node3D = world.solid(Vector3(CS, WH, 0.5), at + Vector3(0, WH * 0.5, 0), null, Vector3.ZERO, false)
	# turn the door across the corridor
	if ch(c + Vector2i(1, 0)) != "#" and ch(c + Vector2i(-1, 0)) != "#":
		b.rotation_degrees.y = 90
	bodies[c] = b
	for i in 7:
		var x := -1.6 + i * 0.53
		M.part(b, M.cyl(0.11, 0.14, WH, 8), mats.trim, Vector3(x, 0, 0), Vector3(0, 0, rng.randf_range(-4, 4)))
	M.part(b, M.box(CS, 0.2, 0.25), mats.trim, Vector3(0, 0.6, 0))
	M.part(b, M.box(CS, 0.2, 0.25), mats.trim, Vector3(0, -0.8, 0))
	var lock := M.part(b, M.torus_mesh(0.22, 0.05), M.glow(Color("ff5040"), 2.4), Vector3(0, -0.1, 0.2), Vector3(90, 0, 0))
	lock.name = "Lock"

func _key(c: Vector2i, at: Vector3) -> void:
	var k := Node3D.new()
	k.position = at + Vector3(0, 1.1, 0)
	world.stage.add_child(k)
	var gm := M.glow(Color("ffd070"), 2.5)
	M.part(k, M.torus_mesh(0.18, 0.04), gm, Vector3(0, 0.25, 0), Vector3(90, 0, 0))
	M.part(k, M.box(0.06, 0.5, 0.06), gm, Vector3(0, -0.05, 0))
	M.part(k, M.box(0.18, 0.06, 0.06), gm, Vector3(0.09, -0.22, 0))
	var l := OmniLight3D.new()
	l.light_color = Color("ffd070")
	l.light_energy = 1.2
	l.omni_range = 4.0
	k.add_child(l)
	things[c] = k

func _chest(c: Vector2i, at: Vector3) -> void:
	var ch_ := Node3D.new()
	ch_.position = at
	world.stage.add_child(ch_)
	var wood := M.mat(Color("5a3a22"), 0.8)
	var iron := M.mat(Color("3a3632"), 0.4, Color(0, 0, 0, 0), 1.0, 1.0, 0.7)
	M.part(ch_, M.box(1.1, 0.6, 0.7), wood, Vector3(0, 0.3, 0))
	M.part(ch_, M.box(1.14, 0.08, 0.74), iron, Vector3(0, 0.45, 0))
	var lid := Node3D.new()
	lid.position = Vector3(0, 0.6, -0.35)
	ch_.add_child(lid)
	M.part(lid, M.box(1.1, 0.22, 0.7), wood, Vector3(0, 0.11, 0.35))
	if state.looted.has(c):
		lid.rotation_degrees.x = -100
	things[c] = lid
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.1, 0.8, 0.7)
	cs.shape = sh
	cs.position = Vector3(0, 0.4, 0)
	sb.add_child(cs)
	ch_.add_child(sb)

func _lurkers(c: Vector2i, at: Vector3) -> void:
	var g := Node3D.new()
	g.position = at
	world.stage.add_child(g)
	var fb: Dictionary = MAPS.board(d.fights[ch(c)])
	var foe := ""
	for u in fb.units:
		if MAPS.unit(u[0]).side == "foe":
			foe = u[0]
			break
	if foe != "spider":
		# the fight's foes stand waiting in the corridor, as their painted pieces
		for i in 2:
			_standee(g, MAPS.unit(foe), Vector3(rng.randf_range(-1.0, 1.0), 0, -0.8 + i * 1.4), 1.1)
		things[c] = g
		return
	for i in 2:
		var s := M.spider(false)
		s.scale = Vector3.ONE * 0.6
		s.position = Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.2, 1.2))
		s.rotation.y = rng.randf() * TAU
		g.add_child(s)
	things[c] = g

# A painted piece on a post, like the board's, standing in the maze.
func _standee(parent: Node3D, u: Dictionary, pos: Vector3, size: float) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	var brass := M.mat(Color("8a6d3e"), 0.35, Color(0, 0, 0, 0), 1.0, 1.0, 0.7)
	M.part(n, M.cyl(size * 0.34, size * 0.36, 0.08, 24), brass, Vector3(0, 0.04, 0))
	M.part(n, M.box(0.06, 0.4, 0.04), brass, Vector3(0, 0.28, 0))
	var piv := Node3D.new()
	piv.position = Vector3(0, 0.45 + size * 0.5, 0)
	n.add_child(piv)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	q.mesh = qm
	var sm := ShaderMaterial.new()
	sm.shader = TOKEN
	sm.set_shader_parameter("art", load(u.art))
	sm.set_shader_parameter("medal", 1.0 if u.get("medal", false) else 0.0)
	sm.set_shader_parameter("ring_col", Color("e0573f"))
	sm.set_shader_parameter("rim_col", Color("f3d27a") if u.kind == "cap" else Color("cfa850"))
	q.material_override = sm
	piv.add_child(q)
	standees.append(piv)
	return n

func _boss_door(c: Vector2i, at: Vector3) -> void:
	if not th.webs:
		# a stone arch with a glowing seal, and the one who waits beyond it
		var am: Material = mats.trim
		for sx in [-1.0, 1.0]:
			M.part(world.stage, M.box(0.5, WH, 0.6), am, at + Vector3(sx * (CS * 0.5 - 0.3), WH * 0.5, 0))
		M.part(world.stage, M.box(CS, 0.5, 0.6), am, at + Vector3(0, WH - 0.25, 0))
		var seal := M.glow(th.light, 1.4)
		M.part(world.stage, M.torus_mesh(0.5, 0.06), seal, at + Vector3(0, WH - 0.9, 0.32), Vector3(90, 0, 0))
		var l := OmniLight3D.new()
		l.light_color = th.light
		l.light_energy = 1.4
		l.omni_range = 5.0
		l.position = at + Vector3(0, 2.0, 0)
		world.stage.add_child(l)
		var bb: Dictionary = MAPS.board(d.boss)
		_standee(world.stage, MAPS.unit(bb.units[2][0]), at + Vector3(0, 0, -0.6), 1.7)
		return
	# a curtain of web across the way, egg sacs heaped at its foot
	world.web(at + Vector3(-CS * 0.5 + 0.2, WH * 0.5, 0), CS, WH, Vector3(0, 90, 0), 77)
	var em := LOOK.egg_mats()
	for i in 5:
		var e := M.egg_sac()
		e.position = at + Vector3(-1.2 + rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-1.6, 1.6))
		var s := rng.randf_range(0.6, 0.9)
		e.scale = Vector3.ONE * s
		LOOK.paint_egg(e, em)
		world.stage.add_child(e)

# ---------------------------------------------------------------- walking and doing
func _face_standees() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	for piv in standees:
		if is_instance_valid(piv) and piv.is_inside_tree():
			var to: Vector3 = cam.global_position
			to.y = piv.global_position.y + (to.y - piv.global_position.y) * 0.35
			piv.look_at(to, Vector3.UP)
			piv.rotate_object_local(Vector3.UP, PI)

func _process(_delta: float) -> void:
	_face_standees()
	if busy or done != "" or world == null or world.player == null:
		return
	var pp: Vector3 = world.player.global_position
	var here := cell_at(pp)
	var k := ch(here)
	# the key comes to hand when you walk over it
	if k == "K" and not state.key and pp.distance_to(cell_pos(here)) < 1.6:
		state.key = true
		if things.has(here):
			things[here].queue_free()
			things.erase(here)
		banner("The key", "An old iron key, warm to hold.")
		_stats()
	if k in "123456789" and not state.cleared.has(here) and pp.distance_to(cell_pos(here)) < 1.8:
		_fight(here, d.fights[k], false, k)
		return
	if k == "B" and pp.distance_to(cell_pos(here)) < 1.8:
		_fight(here, d.boss, true)
		return
	for p in things.values():
		if p is Node3D and p.has_meta("bob"):
			pass
	if things.has(find("K")) and not state.key:
		var kn: Node3D = things[find("K")]
		kn.rotation.y += _delta * 1.5
	# what's within reach to do
	near = null
	var best := 2.9
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			var cc := ch(c)
			var can: bool = (cc == "S" and not state.broken.has(c)) or (cc == "D" and not state.opened.has(c)) or (cc == "C" and not state.looted.has(c))
			if not can:
				continue
			var dist := Vector2(pp.x, pp.z).distance_to(Vector2(cell_pos(c).x, cell_pos(c).z))
			if dist < best + (CS * 0.5 if cc != "C" else 0.0):
				best = dist
				near = c
	if near == null:
		act_btn.visible = false
	else:
		var cc := ch(near)
		act_btn.visible = true
		act_btn.text = {"S": "Search the wall", "D": "Unlock the door" if state.key else "Locked", "C": "Open the chest"}[cc]
		act_btn.disabled = cc == "D" and not state.key

func _unhandled_key_input(e: InputEvent) -> void:
	if e.pressed and not e.echo and (e.keycode == KEY_E or e.keycode == KEY_SPACE or e.keycode == KEY_ENTER):
		do_action()

func do_action() -> void:
	if busy or near == null:
		return
	var c: Vector2i = near
	match ch(c):
		"S":
			state.broken[c] = true
			var b: StaticBody3D = bodies[c]
			world.shake = 0.6
			world.flash(cell_pos(c) + Vector3(0, 1.5, 0), Color("ffb060"), 4.0, 0.6, 6.0)
			var tw := create_tween()
			tw.tween_property(b, "scale", Vector3(1, 0.05, 1), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_callback(b.queue_free)
			bodies.erase(c)
			_rubble(cell_pos(c))
			banner("Hollow!", "The cracked stone gives, and there's a way through.")
		"D":
			if not state.key:
				banner("Locked", "Old iron bars. There's a keyhole, glowing.")
				return
			state.opened[c] = true
			var b: StaticBody3D = bodies[c]
			var tw := create_tween()
			tw.tween_property(b, "position:y", -WH * 0.5, 1.2).set_trans(Tween.TRANS_SINE)
			tw.tween_callback(b.queue_free)
			bodies.erase(c)
			banner("The door opens", "The bars sink into the floor. Something below goes quiet.")
		"C":
			state.looted[c] = true
			var lid: Node3D = things[c]
			var tw := create_tween()
			tw.tween_property(lid, "rotation_degrees:x", -100.0, 0.6).set_trans(Tween.TRANS_BACK)
			var ch_: Dictionary = d.get("chest", {})
			hp = min(max_hp, hp + int(ch_.get("heal", 0)))
			banner("The chest", "Inside: %s. You drink it (HP %d/%d)." % [ch_.get("name", "nothing"), hp, max_hp])
			_stats()
	near = null

func _fight(c: Vector2i, board: String, boss := false, digit := "") -> void:
	busy = true
	world.input_on = false
	world.target = null
	act_btn.visible = false
	var line: Array = d.boss_line if boss else d.get("lines", {}).get(digit, ["Foes!", "They come at you out of the dark."])
	banner(line[0], line[1])
	await get_tree().create_timer(1.0).timeout
	await main.ui.fade_out(0.6)
	hud.visible = false
	var res: Dictionary = await main.run_battle(board, hp, "Continue", tier)
	hud.visible = true
	if res.result == "victory":
		# a breather after the fight: Burr licks your hand, you bind the worst of it
		hp = min(max_hp, max(1, res.hp) + 4)
		state.cleared[c] = true
		if boss:
			done = "cleared"
			build()
			world.place_player(cell_pos(c), 0)
			main.ui.fade_in(0.6)
			banner("Dungeon cleared", d.get("outro", "The way on is open."))
			return
		build()
		world.place_player(cell_pos(c) + Vector3(0, 0.1, 0), 0)
		banner("They're beaten", "HP %d/%d." % [hp, max_hp])
	else:
		hp = max_hp / 2
		build()
		world.place_player(cell_pos(find("P")) + Vector3(0, 0.1, 0), 0)
		banner("Burr drags you clear", "Vaelric's axe holds you at 1 HP. You come round at the way in.")
	_stats()
	main.ui.fade_in(0.6)
	await get_tree().create_timer(0.8).timeout
	world.input_on = true
	busy = false

# ---------------------------------------------------------------- the screen
func _hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 6
	add_child(hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = main.ui._theme()
	hud.add_child(root)
	var top := PanelContainer.new()
	top.position = Vector2(10, 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	hp_lbl = Label.new()
	top.add_child(hp_lbl)
	act_btn = Button.new()
	act_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	act_btn.offset_left = -220
	act_btn.offset_top = -84
	act_btn.offset_right = -16
	act_btn.offset_bottom = -16
	act_btn.add_theme_font_size_override("font_size", 20)
	act_btn.visible = false
	act_btn.pressed.connect(do_action)
	root.add_child(act_btn)
	ban = Label.new()
	ban.set_anchors_preset(Control.PRESET_CENTER_TOP)
	ban.offset_top = 70
	ban.offset_left = -260
	ban.offset_right = 260
	ban.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ban.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ban.add_theme_font_size_override("font_size", 18)
	ban.add_theme_constant_override("outline_size", 8)
	ban.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	ban.modulate.a = 0.0
	root.add_child(ban)
	_stats()

func _stats() -> void:
	hp_lbl.text = "%s  ·  HP %d/%d%s" % [d.get("title", ""), hp, max_hp, "  ·  key" if state.key else ""]

func banner(t: String, s: String) -> void:
	ban.text = t + "\n" + s
	var tw := create_tween()
	tw.tween_property(ban, "modulate:a", 1.0, 0.25)
	tw.tween_interval(2.6)
	tw.tween_property(ban, "modulate:a", 0.0, 0.6)
	print("[dungeon] ", t, ": ", s)

# ---------------------------------------------------------------- the play-test bot
func passable(c: Vector2i) -> bool:
	var k := ch(c)
	if k == "#":
		return false
	if k == "S":
		return state.broken.has(c)
	if k == "D":
		return state.opened.has(c)
	return true

func path(a: Vector2i, b: Vector2i) -> Array:
	var prev := {a: a}
	var q := [a]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == b:
			break
		for dd in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var n: Vector2i = c + dd
			if not prev.has(n) and (passable(n) or n == b):
				prev[n] = c
				q.append(n)
	if not prev.has(b):
		return []
	var out := [b]
	while out[0] != a:
		out.push_front(prev[out[0]])
	return out

func _walk_to_cell(goal: Vector2i, stop_next := false) -> void:
	var guard := 0
	while guard < 60 and done == "":
		guard += 1
		while busy:
			await get_tree().create_timer(0.3).timeout
		var here := cell_at(world.player.global_position)
		var pth := path(here, goal)
		if pth.is_empty():
			return
		if stop_next:
			pth.pop_back()
		if pth.size() <= 1:
			return
		var nxt: Vector2i = pth[1]
		world.target = cell_pos(nxt)
		world.auto_walking = true
		var t := 0.0
		while t < 4.0 and not busy and world.player.global_position.distance_to(Vector3(cell_pos(nxt).x, world.player.global_position.y, cell_pos(nxt).z)) > 0.6:
			await get_tree().process_frame
			t += get_process_delta_time()
		world.target = null
		world.auto_walking = false

func _bot() -> void:
	await get_tree().create_timer(2.0).timeout
	var plan := [["K", false], ["S", true], ["C", true], ["D", true], ["B", false]]
	# after a beating you come round at the way in, so go round again (a few times at most)
	for round_ in 4:
		await _bot_round(plan)
		if done != "":
			return
	done = "bot gave up"

func _bot_round(plan: Array) -> void:
	for st in plan:
		var goal := find(st[0])
		if goal.x < 0:
			continue
		if (st[0] == "K" and state.key) or (st[0] == "S" and state.broken.has(goal)) or (st[0] == "C" and state.looted.has(goal)) or (st[0] == "D" and state.opened.has(goal)):
			continue
		await _walk_to_cell(goal, st[1])
		await get_tree().create_timer(0.4).timeout
		while busy:
			await get_tree().create_timer(0.3).timeout
		if st[1]:
			near = goal
			do_action()
			await get_tree().create_timer(1.4).timeout
		if done != "":
			return
	# the boss fight may still be starting
	while done == "" and busy:
		await get_tree().create_timer(0.3).timeout
