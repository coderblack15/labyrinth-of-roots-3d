# The tactics battle on a 3D board, played by the 2D game's Tactical Advantage rules:
# a speed bar sets the turn order; each unit moves and plays one card, either order,
# then faces a way. d20 + hit against AC; from the side +2, from behind +4. The ground
# counts (scripts/tactics/maps.gd, GROUND). ◆ Resonance grows 1 a turn, 3 at most, and
# pays for the big cards. Drop the captain and the rest break.
# The pieces are the 2D game's painted minis, standing on brass bases.
# Created by: Adrian Blackshire and Claude.
extends Node3D

signal picked(ev)

const M = preload("res://scripts/models.gd")
const LOOK = preload("res://scripts/look.gd")
const MAPS = preload("res://scripts/tactics/maps.gd")
const TOKEN = preload("res://shaders/token.gdshader")
const TS := 1.2       # one square
const HIGH := 0.6     # how far high ground stands up
const SINK := 0.12    # how far sinking ground sits down
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var main
var world
var ui
var rng := RandomNumberGenerator.new()
var board := {}
var W := 0
var H := 0
var G := []            # [y][x] ground char
var tile_nodes := {}
var overlays := {}
var ov_mats := {}
var units := []
var active = null
var auto := false
var fast := false
var turns := 0
var over := false
var result := ""
var root: Node3D
var log_lines := []

# camera
var cam_turn := 0
var cam_yaw := 0.0
var cam_zoom := 1.0
var cam_pan := Vector3.ZERO
var cam_focus := Vector3.ZERO
var drag_from := Vector2.ZERO
var dragging := false
var press := false
var fingers := {}
var pinch_d := 0.0

# the player's turn
var reach := {}
var sel_card := ""
var pend = null
var undo_to = null

func setup(key: String) -> void:
	board = MAPS.BOARDS[key]
	G = []
	for row in board.grid:
		var r := []
		for ch in row:
			r.append(ch)
		G.append(r)
	H = G.size()
	W = G[0].size()

# ---------------------------------------------------------------- the board
func build() -> void:
	world.build(board.stage)
	for k in ["grid", "ryytaa", "sp_a", "sp_b", "sp_c", "sp_d"]:
		if world.props.has(k):
			world.props[k].visible = false
	for e in world.props.get("eggs", []):
		e.queue_free()
	for wb in world.props.get("webs", []):
		wb.visible = false
	world.props.eggs = []
	world.set_light("torch", 0.01)
	world.torch_light.visible = false
	world.player.visible = false
	world.player.process_mode = Node.PROCESS_MODE_DISABLED
	world.set_physics_process(false)
	world.set_process_unhandled_input(false)
	world.joy.visible = false
	world.cam_fixed = true
	# lift the lid off the cave: the board is seen from above, like a table in a diorama
	for n in world.stage.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var bb := mi.global_transform * mi.get_aabb()
		var sh := mi.material_override as ShaderMaterial
		if sh and sh.shader and sh.shader.resource_path.contains("shaft"):
			mi.visible = false
		if bb.position.y > 4.5 or mi.name in ["Cave", "Silk"] or (mi.get_parent() and mi.get_parent().name in ["Cave", "Silk"]):
			mi.visible = false
	root = Node3D.new()
	root.name = "Board"
	world.stage.add_child(root)
	_make_ov_mats()
	var floor_m := _stone("cavefloor", Color("74685a"), 0.3)
	var side_m := _stone("caverock", Color("5a524a"), 0.35)
	var high_m := _stone("cliff", Color("7a7062"), 0.3)
	var root_m := _stone("root", Color("6a4a32"), 0.6)
	var egg_m := LOOK.egg_mats()
	var lines := StandardMaterial3D.new()
	lines.albedo_texture = _frame_tex()
	lines.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lines.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# the board's own slab, so the grid reads as a board laid in the cave
	var slab := M.part(root, M.box(W * TS + 0.5, 0.3, H * TS + 0.5), side_m, Vector3(0, -0.16, 0))
	slab.name = "Slab"
	for y in H:
		for x in W:
			var p := Vector2i(x, y)
			var k: String = G[y][x]
			var top := top_y(p)
			var c := tile_pos(p)
			var t := Node3D.new()
			t.position = Vector3(c.x, 0, c.z)
			root.add_child(t)
			tile_nodes[p] = t
			if k == "#":
				_tall(t, p)
				continue
			if k == "h":
				M.part(t, M.box(TS * 0.99, top + 0.02, TS * 0.99), high_m, Vector3(0, top * 0.5 - 0.01, 0))
			var fm: Material = floor_m
			if k == "~":
				fm = M.mat(Color("2a2620"), 0.4)
			elif k == "w":
				fm = M.mat(Color("1a3a48"), 0.05, Color("2a6a88"), 0.3, 0.85, 0.2)
			elif k == "i":
				fm = M.mat(Color("1a2028"), 0.05, Color("3a5a7a"), 0.2, 1.0, 0.3)
			elif k == "o":
				fm = M.mat(Color("8a5a3a"), 0.8, Color("ff7a3a"), 0.4)
			M.part(t, M.box(TS * 0.96, 0.04, TS * 0.96), fm, Vector3(0, top - 0.02, 0))
			# the grid: a frame round every square, tinted for its ground
			var gq := PlaneMesh.new()
			gq.size = Vector2(TS, TS)
			var lm := lines.duplicate() as StandardMaterial3D
			lm.albedo_color = _kind_col(k)
			M.part(t, gq, lm, Vector3(0, top + 0.012, 0))
			_dress(t, k, top, root_m, egg_m)
			var ov := MeshInstance3D.new()
			var om := PlaneMesh.new()
			om.size = Vector2(TS * 0.86, TS * 0.86)
			ov.mesh = om
			ov.position = Vector3(0, top + 0.035, 0)
			ov.visible = false
			t.add_child(ov)
			overlays[p] = ov
	for u in board.units:
		spawn(u[0], Vector2i(u[1], u[2]))
	# a warm lamp over the table and a cool fill, so the board and its pieces read
	var key := SpotLight3D.new()
	key.light_color = Color("ffd8a0")
	key.light_energy = 3.0
	key.spot_range = 30.0
	key.spot_angle = 48.0
	key.spot_attenuation = 0.6
	key.shadow_enabled = true
	key.position = Vector3(-3, 12, 6)
	root.add_child(key)
	key.look_at(Vector3(0, 0, 0), Vector3.UP)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("8aa0c8")
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-60, 150, 0)
	root.add_child(fill)
	cam_focus = Vector3.ZERO
	_place_cam(true)

func _kind_col(k: String) -> Color:
	match k:
		"c":
			return Color(0.55, 0.75, 1.0, 0.85)
		"r":
			return Color(0.95, 0.6, 0.3, 0.85)
		"h":
			return Color(1.0, 0.85, 0.4, 0.95)
		"~":
			return Color(0.45, 0.95, 0.75, 0.85)
		"i":
			return Color(0.7, 0.9, 1.0, 0.85)
		"o":
			return Color(1.0, 0.55, 0.3, 0.85)
		"w":
			return Color(0.4, 0.7, 1.0, 0.85)
	return Color(1.0, 0.92, 0.75, 0.42)

func _frame_tex() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for i in n:
		for w in 2:
			for q in [[i, w], [i, n - 1 - w], [w, i], [n - 1 - w, i]]:
				img.set_pixel(q[0], q[1], Color(1, 1, 1, 1.0 if w == 0 else 0.5))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _stone(tex: String, c: Color, scale: float) -> ShaderMaterial:
	var m := LOOK.rock(c, 0.0, 0.0, 0.2, 0.9)
	var path := "res://art/tex_%s.webp" % tex
	if ResourceLoader.exists(path):
		m.set_shader_parameter("tex", load(path))
		m.set_shader_parameter("use_tex", 0.85)
		m.set_shader_parameter("tex_scale", scale)
	return m

func _tall(t: Node3D, p: Vector2i) -> void:
	var m := _stone("caverock", Color("5a524a"), 0.35)
	var hgt := 2.4 + rng.randf() * 1.2
	M.part(t, M.box(TS * 0.98, hgt, TS * 0.98), m, Vector3(0, hgt * 0.5, 0), Vector3(0, rng.randf_range(-5, 5), 0))
	M.part(t, M.sph(TS * 0.55, 8), m, Vector3(rng.randf_range(-0.1, 0.1), hgt, 0), Vector3.ZERO, Vector3(1, 0.5, 1))

func _dress(t: Node3D, k: String, top: float, root_m: Material, egg_m: Array) -> void:
	var nest: bool = board.get("dress", "") == "nest"
	match k:
		"c":
			if nest:
				# a clutch of egg sacs, waist-high: cover
				for i in 3:
					var e := M.egg_sac()
					var a := TAU * i / 3.0 + rng.randf()
					e.position = Vector3(cos(a) * 0.28, top, sin(a) * 0.28 - 0.1)
					var s := rng.randf_range(0.62, 0.78)
					e.scale = Vector3(s, s * rng.randf_range(0.95, 1.15), s)
					e.rotation.y = rng.randf() * TAU
					LOOK.paint_egg(e, egg_m)
					t.add_child(e)
			else:
				for i in 2:
					M.part(t, M.torus_mesh(0.4, 0.09), root_m, Vector3(rng.randf_range(-0.2, 0.2), top - 0.05, rng.randf_range(-0.25, 0.1)), Vector3(90, rng.randf_range(-40, 40) + i * 90, 0), Vector3(1, 1, 0.9))
		"r":
			if nest:
				var wm := M.web_mat(int(t.position.x * 7 + t.position.z * 13))
				var wp := PlaneMesh.new()
				wp.size = Vector2(TS * 1.05, TS * 1.05)
				M.part(t, wp, wm, Vector3(0, top + 0.05, 0), Vector3(0, rng.randf() * 90, 0))
				var wv := QuadMesh.new()
				wv.size = Vector2(TS * 0.8, 0.5)
				M.part(t, wv, wm, Vector3(0, top + 0.25, rng.randf_range(-0.3, 0.3)), Vector3(-20, rng.randf_range(-40, 40), 0))
			for i in 5:
				M.part(t, M.sph(rng.randf_range(0.05, 0.11), 6), M.mat(Color("6a6258"), 0.95),
					Vector3(rng.randf_range(-0.45, 0.45), top + 0.02, rng.randf_range(-0.45, 0.45)), Vector3.ZERO, Vector3(1, 0.6, 1))
		"~":
			var sm := M.mat(Color("3a3a2c"), 0.1, Color("6a7050"), 0.15, 0.8, 0.3)
			var q := PlaneMesh.new()
			q.size = Vector2(TS * 0.92, TS * 0.92)
			M.part(t, q, sm, Vector3(0, top + 0.03, 0))
			if nest:
				var wm2 := M.web_mat(int(t.position.x * 3 + t.position.z * 5) + 9)
				var wp2 := PlaneMesh.new()
				wp2.size = Vector2(TS * 0.8, TS * 0.8)
				M.part(t, wp2, wm2, Vector3(0, top + 0.05, 0), Vector3(0, rng.randf() * 90, 0))
		"o":
			var l := OmniLight3D.new()
			l.light_color = Color("ff8a3a")
			l.light_energy = 0.6
			l.omni_range = 2.0
			l.position = Vector3(0, top + 0.4, 0)
			t.add_child(l)

func _make_ov_mats() -> void:
	var cols := {"move": Color(0.95, 0.78, 0.3, 0.5), "target": Color(1.0, 0.3, 0.25, 0.55), "ally": Color(0.4, 0.9, 0.5, 0.5),
		"focus": Color(1.0, 0.95, 0.7, 0.6), "face": Color(0.5, 0.8, 1.0, 0.6), "pend": Color(1.0, 0.1, 0.05, 0.8)}
	for k in cols:
		var m := StandardMaterial3D.new()
		m.albedo_color = cols[k]
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ov_mats[k] = m

func tile(p: Vector2i):
	if p.x < 0 or p.y < 0 or p.x >= W or p.y >= H:
		return null
	return G[p.y][p.x]

func top_y(p: Vector2i) -> float:
	var k = tile(p)
	if k == "h":
		return HIGH
	if k == "~" or k == "w":
		return 0.02 - SINK
	return 0.02

func tile_pos(p: Vector2i) -> Vector3:
	return Vector3((p.x - (W - 1) * 0.5) * TS, top_y(p), (p.y - (H - 1) * 0.5) * TS)

# ---------------------------------------------------------------- the pieces
func spawn(id: String, p: Vector2i) -> Dictionary:
	var d: Dictionary = MAPS.UNITS[id]
	var u := {"id": id, "name": d.name, "side": d.side, "kind": d.kind, "hp": d.hp, "max": d.hp, "hit": d.hit, "ac": d.ac,
		"die": d.die, "spd": d.spd, "mv": d.mv, "cards": d.cards.duplicate(), "pos": p,
		"face": Vector2i(0, 1) if d.side == "foe" else Vector2i(0, -1), "ct": float(rng.randi_range(1, 30)),
		"res": 0, "used": {}, "stun": 0, "alive": true, "moved": false, "acted": false, "mv0": []}
	if id == "you":
		var nm: String = main.story.S.get("name", "")
		u.name = nm if nm != "" else "You"
	var n := Node3D.new()
	n.position = tile_pos(p)
	root.add_child(n)
	u.node = n
	var big: bool = d.get("big", false)
	var small: bool = d.get("small", false)
	var r := 0.46 if big else (0.36 if small else 0.4)
	# the brass base, as on the 2D mat
	var brass := M.mat(Color("8a6d3e"), 0.35, Color(0, 0, 0, 0), 1.0, 1.0, 0.7)
	M.part(n, M.cyl(r, r + 0.03, 0.07, 28), brass, Vector3(0, 0.035, 0))
	M.part(n, M.cyl(r - 0.03, r - 0.03, 0.01, 28), M.mat(Color("2a2018"), 0.9), Vector3(0, 0.075, 0))
	# a facing arrow on the base: gold for yours, red for theirs (the 2D map's pointer)
	var arrow := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.22, 0.16, 0.03)
	arrow.mesh = pm
	arrow.material_override = M.glow(Color("f3d27a") if u.side == "you" else Color("e0573f"), 1.6)
	arrow.rotation_degrees = Vector3(-90, 0, 0)
	arrow.position = Vector3(0, 0.09, -(r - 0.02))
	n.add_child(arrow)
	# the standee: a post and the round painted piece on top
	var post_h := 0.3 if not big else 0.36
	M.part(n, M.box(0.05, post_h, 0.03), brass, Vector3(0, 0.07 + post_h * 0.5, 0))
	var piv := Node3D.new()
	var disc := (1.7 if big else (1.2 if small else 1.35))
	piv.position = Vector3(0, 0.07 + post_h + disc * 0.5 - 0.04, 0)
	n.add_child(piv)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(disc, disc)
	q.mesh = qm
	var sm := ShaderMaterial.new()
	sm.shader = TOKEN
	var art: String = d.art
	if art == "hero":
		art = "res://art/pieces/tok_hero_%s.webp" % main.story.S.get("pr", "they")
	sm.set_shader_parameter("art", load(art))
	sm.set_shader_parameter("medal", 1.0 if d.get("medal", false) else 0.0)
	sm.set_shader_parameter("ring_col", Color("6fd08c") if u.side == "you" else Color("e0573f"))
	sm.set_shader_parameter("rim_col", Color("cfa850") if u.kind != "cap" else Color("f3d27a"))
	q.material_override = sm
	q.layers = 3
	var card := Node3D.new()
	piv.add_child(card)
	card.add_child(q)
	# a backing, so the piece reads as a thick painted disc from the side
	var back := MeshInstance3D.new()
	back.mesh = M.cyl(disc * 0.5, disc * 0.5, 0.035, 28)
	back.material_override = brass
	back.rotation_degrees = Vector3(90, 0, 0)
	back.position = Vector3(0, 0, -0.02)
	card.add_child(back)
	u.piv = piv
	u.card = card
	u.mat = sm
	u.arrow = arrow
	units.append(u)
	_face(u, u.face)
	return u

func _hp_show(u: Dictionary) -> void:
	u.mat.set_shader_parameter("hp", clamp(float(u.hp) / float(u.max), 0.0, 1.0))

func _face(u: Dictionary, d: Vector2i) -> void:
	if d == Vector2i.ZERO:
		return
	u.face = d
	var r: float = u.arrow.position.length()
	u.arrow.position = Vector3(d.x * r, 0.09, d.y * r)
	u.arrow.rotation = Vector3(-PI * 0.5, atan2(-float(d.x), -float(d.y)), 0)

func at(p: Vector2i):
	for u in units:
		if u.alive and u.pos == p:
			return u
	return null

func living(side := "") -> Array:
	var out := []
	for u in units:
		if u.alive and (side == "" or u.side == side):
			out.append(u)
	return out

func me():
	for u in units:
		if u.id == "you":
			return u
	return null

# ---------------------------------------------------------------- the rules (2D Tactical Advantage)
func cost(from: Vector2i, to: Vector2i) -> int:
	var t = tile(to)
	if t == null or t == "#" or t == "w":
		return 999
	if tile(from) == "~":
		return 2
	if t == "r":
		return 2
	if t == "h" and tile(from) != "h":
		return 2
	return 1

# ice: keep sliding until something stops you
func slide_end(p: Vector2i, d: Vector2i, mover) -> Vector2i:
	while tile(p) == "i":
		var n := p + d
		var t = tile(n)
		if t == null or t in ["#", "c", "h", "w"]:
			break
		var o = at(n)
		if o != null and o != mover:
			break
		p = n
	return p

func reachable(u: Dictionary) -> Dictionary:
	var out := {u.pos: [0, u.pos, Vector2i.ZERO]}
	if u.moved:
		return {u.pos: out[u.pos], "_all": out}
	var open := [u.pos]
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if out[open[i]][0] < out[open[bi]][0]:
				bi = i
		var c: Vector2i = open.pop_at(bi)
		var cc: int = out[c][0]
		for d in DIRS:
			var n: Vector2i = c + d
			var o = at(n)
			if o != null and o.side != u.side:
				continue
			var nc := cc + cost(c, n)
			if nc > u.mv:
				continue
			var e := slide_end(n, d, u) if tile(n) == "i" else n
			if e == u.pos:
				continue
			if not out.has(e) or out[e][0] > nc:
				out[e] = [nc, c, d]
				open.append(e)
	# you may pass through friends but not stop on them
	var stops := {}
	for p in out.keys():
		if p == u.pos or at(p) == null:
			stops[p] = out[p]
	stops["_all"] = out
	return stops

func path_to(r: Dictionary, p: Vector2i) -> Array:
	var all: Dictionary = r["_all"]
	var path := [p]
	while all[path[0]][1] != path[0]:
		path.push_front(all[path[0]][1])
	return path

func dist(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func los(a: Vector2i, b: Vector2i) -> bool:
	var n := int(ceil(Vector2(b - a).length() * 5.0))
	for i in range(1, n):
		var x := int(round(a.x + (b.x - a.x) * float(i) / n))
		var y := int(round(a.y + (b.y - a.y) * float(i) / n))
		var q := Vector2i(x, y)
		if q == a or q == b:
			continue
		if tile(q) == "#":
			return false
	return true

func dir_to(a: Vector2i, b: Vector2i) -> Vector2i:
	var d := b - a
	if d == Vector2i.ZERO:
		return Vector2i.ZERO
	if abs(d.x) >= abs(d.y):
		return Vector2i(sign(d.x), 0)
	return Vector2i(0, sign(d.y))

func side_of(from: Vector2i, t: Dictionary) -> String:
	var v := dir_to(t.pos, from)
	if v == Vector2i.ZERO:
		v = t.face
	if v == t.face:
		return "front"
	if v == -t.face:
		return "back"
	return "side"

func card_ok(u: Dictionary, k: String) -> bool:
	var c: Dictionary = MAPS.CARDS[k]
	return c.get("cost", 0) <= u.res

func in_range(u: Dictionary, c: Dictionary, p: Vector2i, from: Vector2i) -> bool:
	var dd := dist(from, p)
	return dd >= c.min and dd <= c.max and (not c.get("ranged", false) or los(from, p))

func targets(u: Dictionary, k: String, from: Vector2i) -> Array:
	var c: Dictionary = MAPS.CARDS[k]
	var out := []
	for t in living():
		if t.side != u.side and t != u and in_range(u, c, t.pos, from):
			out.append(t.pos)
	return out

func mods(a: Dictionary, t: Dictionary, from: Vector2i) -> Array:
	var m := []
	var ta = tile(from)
	var tt = tile(t.pos)
	if ta == "h" and tt != "h":
		m.append(["from above", 1])
	if ta == "r":
		m.append(["bad footing", -1])
	if tt == "c":
		m.append(["in cover", -1])
	if ta == "~":
		m.append(["stuck fast", -3])
	if tt == "~":
		m.append(["it's stuck", 3])
	var sd := side_of(from, t)
	if sd == "side":
		m.append(["from the side", 2])
	elif sd == "back":
		m.append(["from behind", 4])
	return m

func is_charge(u: Dictionary, t: Dictionary, c: Dictionary) -> bool:
	if not c.get("melee", false) or u.mv0.size() < 2 or tile(t.pos) == "r":
		return false
	for s in u.mv0:
		if s.d != u.mv0[0].d or s.t != ".":
			return false
	return true

func odds(a: Dictionary, t: Dictionary, k: String, from: Vector2i) -> float:
	var need: int = t.ac - a.hit
	for x in mods(a, t, from):
		need -= x[1]
	return clamp((21.0 - need) / 20.0, 0.05, 0.95)

func roll(die: Array) -> int:
	var tot: int = die[2]
	for i in die[0]:
		tot += rng.randi_range(1, die[1])
	return tot

func avg(die: Array) -> float:
	return die[0] * (die[1] + 1) * 0.5 + die[2]

# ---------------------------------------------------------------- the battle
func run() -> String:
	over = false
	_log("== %s: %d x %d board" % [board.title, W, H])
	for u in units:
		_hp_show(u)
	ui.banner(board.title, board.blurb)
	await wait(2.2 if not fast else 0.4)
	while not over:
		var u = next_actor()
		active = u
		turns += 1
		u.moved = false
		u.acted = false
		u.mv0 = []
		u.res = min(3, u.res + 1)
		_active_glow()
		ui.order(preview(10), self)
		if u.stun > 0:
			u.stun = 0
			_say(u, "reeling")
			_log("%s is still reeling and loses the turn" % u.name)
			await wait(0.6)
		elif u.side == "you" and (not auto or demo):
			await player_turn(u)
		else:
			await ai_turn(u)
		u.ct = 0.0
		check_end()
		if turns > 300:
			over = true
			result = "stalemate"
	_active_glow()
	_log("== END " + result)
	return result

func next_actor():
	var g := 0
	while g < 5000:
		g += 1
		var best = null
		for u in living():
			if u.ct >= 100.0 and (best == null or u.ct > best.ct):
				best = u
		if best != null:
			return best
		for u in living():
			u.ct += u.spd
	return living()[0]

func preview(n: int) -> Array:
	var sim := {}
	var alive := living()
	for u in alive:
		sim[u] = u.ct
	var out := []
	var g := 0
	while out.size() < n and g < 3000:
		g += 1
		var best = null
		for u in alive:
			if sim[u] >= 100.0 and (best == null or sim[u] > sim[best]):
				best = u
		if best != null:
			out.append(best)
			sim[best] = 0.0
		else:
			for u in alive:
				sim[u] += u.spd
	return out

# ---------------------------------------------------------------- your turn
func player_turn(u: Dictionary) -> void:
	sel_card = ""
	pend = null
	undo_to = null
	_focus_on(u.pos)
	ui.banner(("Your turn" if u.id == "you" else u.name + "'s turn"), "")
	while u.alive and not over:
		if u.moved and u.acted:
			break
		_refresh(u)
		var ev: Dictionary
		if demo:
			ev = await _demo_event(u)
		else:
			ev = await picked
		if ev.type == "end":
			break
		elif ev.type == "undo" and u.moved and not u.acted and undo_to != null:
			u.pos = undo_to[0]
			u.node.position = tile_pos(u.pos)
			_face(u, undo_to[1])
			u.mv0 = []
			u.moved = false
			undo_to = null
			pend = null
			_log("%s step back" % ("You" if u.id == "you" else u.name))
		elif ev.type == "card":
			sel_card = "" if sel_card == ev.card else ev.card
			pend = null
		elif ev.type == "tile":
			await _tap(u, ev.pos)
	_clear_ov()
	check_end()
	if u.alive and not over and (not auto or demo):
		await _choose_face(u)
	_clear_ov()
	ui.panel(null, self)
	ui.info("")

func _tap(u: Dictionary, p: Vector2i) -> void:
	var card: String = sel_card if sel_card != "" else ("" if u.acted else u.cards[0])
	var t = at(p)
	if not u.acted and card != "" and card_ok(u, card) and t != null and t.side != u.side and p in targets(u, card, u.pos):
		if pend == p:
			pend = null
			sel_card = ""
			await act(u, card, t)
			u.acted = true
		else:
			pend = p
		return
	pend = null
	if not u.moved and reach.has(p) and p != u.pos:
		undo_to = [u.pos, u.face]
		await move_along(u, path_to(reach, p))
		u.moved = true
		return
	ui.tile_info(self, p)

func _choose_face(u: Dictionary) -> void:
	_auto_face(u)
	for d in DIRS:
		var n: Vector2i = u.pos + d
		if overlays.has(n):
			_ov(n, "face")
	_ov(u.pos, "focus")
	ui.facing(u, self)
	while true:
		var ev: Dictionary
		if demo:
			await wait(1.0)
			ev = {"type": "keep"}
		else:
			ev = await picked
		if ev.type == "tile" and dist(ev.pos, u.pos) == 1:
			_face(u, ev.pos - u.pos)
			break
		if ev.type in ["end", "keep"] or (ev.type == "tile" and ev.pos == u.pos):
			break

func _refresh(u: Dictionary) -> void:
	_clear_ov()
	reach = reachable(u) if not u.moved else {}
	for p in reach.keys():
		if p is Vector2i and p != u.pos:
			_ov(p, "move")
	var card: String = sel_card if sel_card != "" else ("" if u.acted else u.cards[0])
	if not u.acted and card != "" and card_ok(u, card):
		for p in targets(u, card, u.pos):
			_ov(p, "target")
	if pend != null:
		_ov(pend, "pend")
	_ov(u.pos, "focus")
	ui.panel(u, self)
	if pend != null:
		var t = at(pend)
		var o := odds(u, t, card, u.pos)
		var c: Dictionary = MAPS.CARDS[card]
		var die: Array = c.get("die", u.die)
		var txt := "[b]%s[/b] at %s: [color=#f3d27a]%d%%[/color] to hit, %s" % [c.name, t.name, int(round(o * 100)), _die_txt(die, c.get("twice", false))]
		var ms := mods(u, t, u.pos)
		if is_charge(u, t, c):
			ms.append(["charge, +2 damage", 0])
		if not ms.is_empty():
			txt += "\n" + ", ".join(ms.map(func(x): return x[0] + ("" if x[1] == 0 else " %+d" % x[1])))
		txt += "\n[color=#a9b8c8]Tap it again to strike.[/color]"
		ui.info(txt)
	elif sel_card != "":
		ui.info("[b]%s[/b]: %s" % [MAPS.CARDS[sel_card].name, MAPS.CARDS[sel_card].text])
	elif not u.moved and not u.acted:
		ui.info("Move %s (gold squares) or play a card. Tap a red target once to see the odds, again to strike." % ("yourself" if u.id == "you" else u.name))
	elif not u.acted:
		ui.info("Play a card, or end the turn.")
	else:
		ui.info("Move, or end the turn.")

func _die_txt(die: Array, twice: bool) -> String:
	var n: int = die[0] * (2 if twice else 1)
	return "%dd%d%s damage" % [n, die[1], (" + %d" % die[2]) if die[2] > 0 else ""]

# ---------------------------------------------------------------- moving and striking
func move_along(u: Dictionary, path: Array) -> void:
	_clear_ov()
	u.mv0 = []
	for i in range(1, path.size()):
		var a: Vector2i = path[i - 1]
		var b: Vector2i = path[i]
		var d := dir_to(a, b)
		_face(u, d)
		u.mv0.append({"d": d, "t": tile(b)})
		var tw := create_tween()
		var tt: float = (0.1 if fast else 0.2) * max(1, dist(a, b))
		if abs(top_y(a) - top_y(b)) > 0.2:
			var mid := (tile_pos(a) + tile_pos(b)) * 0.5 + Vector3(0, 0.5, 0)
			tw.tween_property(u.node, "position", mid, tt * 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_property(u.node, "position", tile_pos(b), tt * 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		else:
			tw.tween_property(u.node, "position", tile_pos(b), tt)
		await tw.finished
	u.pos = path[-1]
	u.moved = true
	_log("%s to %s" % [_verb(u, "move"), u.pos])
	if tile(u.pos) == "~":
		_say(u, "sinking")
	_focus_on(u.pos)

func lunge(u: Dictionary, p: Vector2i) -> void:
	var s: Vector3 = u.node.position
	var d: Vector3 = tile_pos(p) - s
	d.y = 0
	var tw := create_tween()
	tw.tween_property(u.node, "position", s + d.normalized() * min(0.45, d.length() * 0.4), 0.12)
	tw.tween_property(u.node, "position", s, 0.22)
	await wait(0.12)

func act(u: Dictionary, k: String, t: Dictionary) -> void:
	var c: Dictionary = MAPS.CARDS[k]
	u.res -= c.get("cost", 0)
	u.acted = true
	_face(u, dir_to(u.pos, t.pos))
	if c.get("ranged", false):
		await _shot(u, t)
	else:
		await lunge(u, t.pos)
	await hit(u, t, c)

func _shot(u: Dictionary, t: Dictionary) -> void:
	var b := MeshInstance3D.new()
	b.mesh = M.sph(0.07, 6)
	b.material_override = M.glow(Color("c8e070") if u.side == "foe" else Color("e0d0b0"), 2.0)
	root.add_child(b)
	b.position = u.node.position + Vector3(0, 0.8, 0)
	var tw := create_tween()
	tw.tween_property(b, "position", t.node.position + Vector3(0, 0.8, 0), 0.3)
	await tw.finished
	b.queue_free()

func hit(a: Dictionary, t: Dictionary, c: Dictionary) -> void:
	var r := rng.randi_range(1, 20)
	var m := 0
	for x in mods(a, t, a.pos):
		m += x[1]
	if r == 1 or (r != 20 and r + a.hit + m < t.ac):
		_log("%s %s (d20 %d%+d vs AC %d)" % [_verb(a, "miss"), t.name, r, a.hit + m, t.ac])
		_say(t, "miss", Color("c0c8d0"))
		await wait(0.45)
		return
	var crit := r == 20
	var die: Array = c.get("die", a.die)
	var n: int = die[0] * (2 if crit else 1) * (2 if c.get("twice", false) else 1)
	var dmg := roll([n, die[1], die[2]])
	if tile(a.pos) == "h" and tile(t.pos) != "h":
		dmg += 1
	if is_charge(a, t, c):
		dmg += 2
		_say(a, "charge!", Color("f3d27a"))
		_log(_verb(a, "charge") + "!")
	_log("%s %s for %d (d20 %d)" % [_verb(a, "crit" if crit else "hit"), t.name, dmg, r])
	await hurt(t, dmg, crit)
	if c.get("stun", false) and t.alive:
		t.stun = 1
		_say(t, "down!", Color("f3d27a"))
		_log("%s goes down and loses the next turn" % t.name)
	if c.get("shove", false) and t.alive:
		await shove(a, t)

func shove(a: Dictionary, t: Dictionary) -> void:
	var d := dir_to(a.pos, t.pos)
	var n: Vector2i = t.pos + d
	var nt = tile(n)
	var o2 = at(n)
	if nt == null or nt == "#" or nt == "w":
		_log("%s slams into %s" % [t.name, "the edge" if nt == null else ("the water" if nt == "w" else "rock")])
		await hurt(t, rng.randi_range(1, 4))
	elif o2 != null:
		var x := rng.randi_range(1, 4)
		_log("%s crashes into %s" % [t.name, o2.name])
		await hurt(t, x)
		await hurt(o2, x)
	else:
		var fall: bool = tile(t.pos) == "h" and nt != "h"
		t.pos = n
		var tw := create_tween()
		tw.tween_property(t.node, "position", tile_pos(n), 0.25).set_trans(Tween.TRANS_QUAD)
		await tw.finished
		if fall:
			_log("%s goes off the ledge" % t.name)
			await hurt(t, rng.randi_range(1, 6))
		elif nt == "~":
			_log("%s is shoved into the sinking ground" % t.name)
			_say(t, "sinking")
		else:
			_log("%s is shoved back" % t.name)

func hurt(u: Dictionary, d: int, crit := false) -> void:
	if not u.alive:
		return
	u.hp -= d
	_hp_show(u)
	_say(u, ("−%d" % d) + ("!" if crit else ""), Color("ff7060") if u.side == "you" else Color("ffd070"))
	world.flash(u.node.position + Vector3(0, 1.0, 0), Color("ff6040"), 2.5, 0.25, 3.0)
	var tw := create_tween()
	tw.tween_property(u.card, "rotation:z", 0.25, 0.06)
	tw.tween_property(u.card, "rotation:z", -0.15, 0.1)
	tw.tween_property(u.card, "rotation:z", 0.0, 0.12)
	if u.hp <= 0:
		await down(u)
	else:
		await wait(0.35)

func down(u: Dictionary) -> void:
	u.alive = false
	u.hp = 0
	_hp_show(u)
	u.mat.set_shader_parameter("down", 1.0)
	var msg := "%s is down" % u.name
	if u.id == "you":
		msg = "You go down"
	elif u.side == "you":
		msg = "%s is out of the fight" % u.name
	_log(msg)
	_say(u, msg, Color("e0d0b0"))
	# fall flat, like the 2D minis
	var tw := create_tween()
	tw.tween_property(u.card, "rotation:x", -0.85, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(u.piv, "position:y", 0.12, 0.45)
	await tw.finished
	await wait(0.3)

func check_end() -> void:
	if over:
		return
	var you = me()
	if you == null or not you.alive:
		over = true
		result = "dragged out"
		return
	var caps: Array = board.get("captains", [])
	if not caps.is_empty():
		var up := false
		for u in living("foe"):
			if u.id in caps:
				up = true
		if not up:
			over = true
			result = "victory"
			for u in living("foe"):
				_say(u, "breaks and runs", Color("e0d0b0"))
				var tw := create_tween()
				tw.tween_property(u.node, "position", u.node.position + Vector3(0, 0, -8), 1.2)
				u.alive = false
			_log("the captain is down and the rest break")
			return
	if living("foe").is_empty():
		over = true
		result = "victory"

# ---------------------------------------------------------------- their turn (and autoplay's), as the 2D ai()
func ai_turn(u: Dictionary) -> void:
	_focus_on(u.pos)
	await wait(0.15 if fast else 0.35)
	var pl := plan(u)
	if pl.is_empty():
		return
	if pl.p != u.pos:
		await move_along(u, path_to(pl.r, pl.p))
		await wait(0.1 if fast else 0.3)
	if pl.has("k"):
		await act(u, pl.k, pl.t)
		_auto_face(u)
		await wait(0.2 if fast else 0.4)
		return
	_auto_face(u)
	await wait(0.15 if fast else 0.3)

# The 2D ai(): the best card from the best square, or else the way in.
func plan(u: Dictionary) -> Dictionary:
	var foes := []
	for t in living():
		if t.side != u.side:
			foes.append(t)
	if foes.is_empty():
		return {}
	var r := reachable(u)
	var spots := r.keys().filter(func(k): return k is Vector2i)
	var best = null
	for k in u.cards:
		if not card_ok(u, k):
			continue
		var c: Dictionary = MAPS.CARDS[k]
		var die: Array = c.get("die", u.die)
		var av := avg(die) * (2.0 if c.get("twice", false) else 1.0)
		for p in spots:
			var sink := 6.0 if tile(p) == "~" else 0.0
			for q in targets(u, k, p):
				var t = at(q)
				var sc: float = odds(u, t, k, p) * av + (8.0 if av >= t.hp else 0.0) + (2.0 if t.id == "you" else 0.0) \
					+ (3.0 if t.kind == "cap" else 0.0) - c.get("cost", 0) * 1.5 + (1.5 if c.get("stun", false) else 0.0)
				sc -= sink + (0.0 if p != u.pos else -0.3)
				if sc > 0.0 and (best == null or sc > best.sc):
					best = {"sc": sc, "k": k, "p": p, "t": t, "r": r}
	if best != null:
		return best
	var bs = null
	for p in spots:
		var dd := 999.0
		for t in foes:
			dd = min(dd, dist(t.pos, p))
		dd += 4.0 if tile(p) == "~" else 0.0
		# the ground's worth: cover and height draw them, as players learn to
		dd -= 0.6 if tile(p) == "c" else 0.0
		dd -= 0.8 if tile(p) == "h" else 0.0
		if bs == null or dd < bs.dd:
			bs = {"dd": dd, "p": p, "r": r}
	return bs if bs != null else {}

# For recorded samples: a player's turn played through the real screen, tap by tap.
var demo := false
func _demo_event(u: Dictionary) -> Dictionary:
	await wait(1.1)
	if not u.moved:
		var pl := plan(u)
		if not pl.is_empty() and pl.p != u.pos:
			demo_plan = pl
			return {"type": "tile", "pos": pl.p}
	if not u.acted and not demo_plan.is_empty() and demo_plan.has("k"):
		var t = demo_plan.t
		if t.alive and t.pos in targets(u, demo_plan.k, u.pos):
			if demo_plan.k != u.cards[0] and sel_card != demo_plan.k:
				return {"type": "card", "card": demo_plan.k}
			await wait(0.6)
			return {"type": "tile", "pos": t.pos}
	if not u.acted:
		var pl2 := plan(u)
		if not pl2.is_empty() and pl2.has("k") and pl2.p == u.pos:
			demo_plan = pl2
			if pl2.k != u.cards[0] and sel_card != pl2.k:
				return {"type": "card", "card": pl2.k}
			await wait(0.6)
			return {"type": "tile", "pos": pl2.t.pos}
	demo_plan = {}
	return {"type": "end"}
var demo_plan := {}

func _auto_face(u: Dictionary) -> void:
	var best = null
	var bd := 999
	for t in living():
		if t.side != u.side and dist(u.pos, t.pos) < bd:
			bd = dist(u.pos, t.pos)
			best = t
	if best != null:
		_face(u, dir_to(u.pos, best.pos))

# ---------------------------------------------------------------- overlays, camera, input
func _ov(p: Vector2i, k: String) -> void:
	if overlays.has(p):
		overlays[p].material_override = ov_mats[k]
		overlays[p].visible = true

func _clear_ov() -> void:
	for p in overlays:
		overlays[p].visible = false

func _active_glow() -> void:
	for u in units:
		u.mat.set_shader_parameter("active", 1.0 if (u == active and not over) else 0.0)

func _say(u: Dictionary, t: String, c := Color("e8e0c0")) -> void:
	world.float_text(u.node.position + Vector3(0, 1.5, 0), t, c)

func _focus_on(p: Vector2i) -> void:
	var t := tile_pos(p)
	cam_focus = Vector3(t.x * 0.35, 0, t.z * 0.35)

func _place_cam(snap := false) -> void:
	var vs := get_viewport().get_visible_rect().size
	var portrait := vs.y > vs.x
	var d := (19.0 if portrait else 14.0) * cam_zoom
	var pitch := deg_to_rad(52.0)
	var off := Vector3(0, sin(pitch), cos(pitch)) * d
	off = off.rotated(Vector3.UP, cam_yaw)
	var look := cam_focus + cam_pan + Vector3(0, 0.3, 0.6)
	world.cam_fixed_pos = look + off
	world.cam_fixed_look = look
	world.cam_yaw = cam_yaw
	if snap:
		world.cam.global_position = look + off
		world.cam_look = look

func _process(delta: float) -> void:
	if world == null or root == null:
		return
	world.inset = Vector2.ZERO
	var want := deg_to_rad(18.0) + cam_turn * PI * 0.5
	cam_yaw = lerp_angle(cam_yaw, want, 1.0 - exp(-delta * 6.0))
	_place_cam()
	# the painted pieces turn to face the camera, as standees on a table do when you lean in
	var cb: Basis = world.cam.global_transform.basis
	for u in units:
		if u.alive:
			# lean back toward the eye a little short of flat-on, like a standee seen from above
			var b := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, -0.75)
			u.piv.global_transform.basis = b.scaled(u.piv.global_transform.basis.get_scale())

func turn_cam(d: int) -> void:
	cam_turn += d

func zoom(f: float) -> void:
	cam_zoom = clamp(cam_zoom * f, 0.5, 1.6)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_Q:
				turn_cam(1)
			KEY_E:
				turn_cam(-1)
			KEY_ENTER, KEY_SPACE:
				picked.emit({"type": "end"})
	if e is InputEventScreenTouch:
		if e.pressed:
			fingers[e.index] = e.position
		else:
			fingers.erase(e.index)
		if fingers.size() == 2:
			var v: Array = fingers.values()
			pinch_d = (v[0] as Vector2).distance_to(v[1])
			dragging = true
	if e is InputEventScreenDrag and fingers.size() == 2:
		fingers[e.index] = e.position
		var v: Array = fingers.values()
		var nd: float = (v[0] as Vector2).distance_to(v[1])
		if pinch_d > 1.0 and nd > 1.0:
			zoom(pinch_d / nd)
		pinch_d = nd
		return
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			zoom(0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			zoom(1.1)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				press = true
				dragging = false
				drag_from = e.position
			else:
				if press and not dragging and fingers.size() < 2:
					var p = pick(e.position)
					if p != null:
						picked.emit({"type": "tile", "pos": p})
				press = false
				dragging = false
	if e is InputEventMouseMotion and press and fingers.size() < 2:
		if not dragging and e.position.distance_to(drag_from) > 14.0:
			dragging = true
		if dragging:
			var r := Vector3(-e.relative.x, 0, -e.relative.y) * 0.025 * cam_zoom
			cam_pan += r.rotated(Vector3.UP, cam_yaw)
			cam_pan.x = clamp(cam_pan.x, -W * TS * 0.5, W * TS * 0.5)
			cam_pan.z = clamp(cam_pan.z, -H * TS * 0.5, H * TS * 0.5)

# The square under a screen point: pieces first (they stand up off the board), then square tops.
func pick(sp: Vector2):
	var cam: Camera3D = world.cam
	var best = null
	var bd := 40.0
	for u in living():
		var wp: Vector3 = u.piv.global_position
		if cam.is_position_behind(wp):
			continue
		var d := cam.unproject_position(wp).distance_to(sp)
		if d < bd:
			bd = d
			best = u.pos
	if best != null:
		return best
	var o := cam.project_ray_origin(sp)
	var n := cam.project_ray_normal(sp)
	var bt := INF
	for y in H:
		for x in W:
			var p := Vector2i(x, y)
			if tile(p) == "#" or abs(n.y) < 0.0001:
				continue
			var c := tile_pos(p)
			var t := (c.y - o.y) / n.y
			if t <= 0.0 or t >= bt:
				continue
			var hp := o + n * t
			if abs(hp.x - c.x) <= TS * 0.5 and abs(hp.z - c.z) <= TS * 0.5:
				bt = t
				best = p
	return best

func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _verb(u: Dictionary, v: String) -> String:
	return u.name + " " + (v if u.name == "You" else v + ("es" if v.ends_with("s") or v.ends_with("h") else "s"))

func _log(s: String) -> void:
	log_lines.append(s)
	if ui:
		ui.log_line(s)
	print(s)
