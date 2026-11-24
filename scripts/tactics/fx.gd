# Immersion on the tactics board (Adrian's yes to all of it, 24 Nov 2026). Looks and sound only:
# nothing here changes a roll, a move or a rule, so the board still plays as the 2D game does.
#   a living board   lamps flicker, motes drift, dust falls on big blows
#   the camera       pushes in on a crit, sweeps round as a boss board opens, slows on the final blow
#   weighty pieces   a hit rocks a piece, a heavy blow slides it back, a beaten piece topples over
#   the ground       footfalls puff the ground's own colour, water ripples, ice and glass crack under
#                    a heavy blow, moss and roots smoulder on a crit (on screen only, Adrian's pick:
#                    the rules stay the 2D game's)
#   sound            footsteps by ground, blows, a crit's ring, all in a cave's echo; the fight's
#                    music swells as the foes fall
#   weather          fog in the fens and drowned places, heat haze in the sands, snow in the rime
# Created by: Adrian Blackshire and Claude.
extends Node3D

const M = preload("res://scripts/models.gd")

# how the ground answers a heavy blow, by theme (looks only)
const CRACKS := ["rime", "melt", "glass", "moon", "ink"]
const SMOULDER := ["roots", "hesk", "jungle", "heart", "fen", "east"]

# which weather each chapter's theme gets
const WEATHER := {
	"roots": "spores", "sand": "heat", "fen": "fog", "mere": "fog", "well": "dust", "glass": "dust",
	"hesk": "spores", "noon": "heat", "moon": "fog", "siege": "embers", "lead": "fog", "tithe": "fog",
	"east": "embers", "ink": "dust", "rime": "snow", "welling": "fog", "melt": "snow", "jungle": "spores",
	"heart": "embers", "vell": "dust",
}

var b                      # the battle
var flick := []            # [light, base energy, phase]
var t := 0.0
var shake := 0.0
var fog_was := {}
var music_was := -8.0
var foes0 := 1
var sfx := {}
var bus := "Master"
var env_ref: Environment
var mu_ref: AudioStreamPlayer
var fast_base := 1.0

func setup(battle) -> void:
	b = battle
	env_ref = b.world.env
	mu_ref = b.world.music
	fast_base = Engine.time_scale
	var theme: String = b.board.get("theme", "roots")
	for n in b.root.find_children("*", "OmniLight3D", true, false):
		flick.append([n, n.light_energy, randf() * 10.0])
	_weather(WEATHER.get(theme, "dust"), theme)
	_sounds()
	foes0 = max(1, b.living("foe").size())
	if b.world.music:
		music_was = b.world.music.volume_db
	b.world.play_music("rootbreaker")
	if "--dbg-fx" in OS.get_cmdline_user_args():
		# for stills: show the ground's answers at every piece
		for u in b.units:
			crack(u.pos)
			smoulder(u.pos)
			ripple(b.tile_pos(u.pos) + Vector3(0, 0.05, 0))
	if b.world.music:
		b.world.music.volume_db = -16.0

func _exit_tree() -> void:
	if env_ref and not fog_was.is_empty():
		env_ref.fog_light_color = fog_was.col
		env_ref.fog_density = fog_was.dens
	if is_instance_valid(mu_ref):
		mu_ref.volume_db = music_was
	Engine.time_scale = fast_base

func _process(delta: float) -> void:
	if not is_instance_valid(b):
		queue_free()
		return
	t += delta
	for f in flick:
		var l: OmniLight3D = f[0]
		if is_instance_valid(l):
			l.light_energy = f[1] * (0.86 + 0.1 * sin(t * 7.3 + f[2]) + 0.06 * sin(t * 17.1 + f[2] * 2.0))
	if shake > 0.0:
		shake = max(0.0, shake - delta * 3.0)
		b.shake_off = Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * shake * 0.12
	else:
		b.shake_off = Vector3.ZERO

# ---------------------------------------------------------------- weather
func _weather(kind: String, theme: String) -> void:
	var w: float = b.W * b.TS
	var h: float = b.H * b.TS
	var env: Environment = b.world.env
	fog_was = {"col": env.fog_light_color, "dens": env.fog_density}
	match kind:
		"fog":
			env.fog_light_color = Color("5c6a66")
			env.fog_density = 0.035
			_mist(w, h)
			_motes(Color(0.8, 0.85, 0.8, 0.25), w, h, 40, Vector3(0.1, 0.02, 0.05), 0.05, 7.0)
		"heat":
			env.fog_light_color = Color("8a6a48")
			env.fog_density = 0.02
			_motes(Color(1.0, 0.8, 0.5, 0.35), w, h, 70, Vector3(0, 0.35, 0), 0.04, 5.0, true)
		"snow":
			env.fog_light_color = Color("8090a8")
			env.fog_density = 0.02
			_motes(Color(1, 1, 1, 0.95), w, h, 260, Vector3(0.25, -0.9, 0.1), 0.13, 6.0)
		"embers":
			_motes(Color(1.0, 0.5, 0.2, 0.9), w, h, 60, Vector3(0.05, 0.5, 0.0), 0.04, 5.0, true)
		"spores":
			_motes(Color(0.75, 0.95, 0.6, 0.55), w, h, 70, Vector3(0.05, 0.08, 0.02), 0.035, 8.0)
		_:
			_motes(Color(0.9, 0.85, 0.7, 0.35), w, h, 60, Vector3(0.04, -0.03, 0.02), 0.03, 8.0)

func _mote_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft()
	return m

# a soft round dot, so motes, flakes and mist have no hard edges
var soft_tex: Texture2D
func _soft() -> Texture2D:
	if soft_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		var t2 := GradientTexture2D.new()
		t2.gradient = g
		t2.fill = GradientTexture2D.FILL_RADIAL
		t2.fill_from = Vector2(0.5, 0.5)
		t2.fill_to = Vector2(0.5, 0.0)
		t2.width = 64
		t2.height = 64
		soft_tex = t2
	return soft_tex

func _motes(c: Color, w: float, h: float, n: int, drift: Vector3, size: float, life: float, rise := false) -> void:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _mote_mat(c)
	p.mesh = q
	p.amount = n
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(w * 0.6, 2.5, h * 0.6)
	p.position = Vector3(0, 0.5 if rise else 3.0, 0)
	p.direction = drift.normalized() if drift != Vector3.ZERO else Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = drift.length() * 0.6
	p.initial_velocity_max = drift.length() * 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.2, Color(1, 1, 1, 1))
	ramp.add_point(0.8, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	add_child(p)

# low banks of mist that slide slowly over the board
func _mist(w: float, h: float) -> void:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(5.0, 3.0)
	q.material = _mote_mat(Color(0.75, 0.82, 0.8, 0.22))
	p.mesh = q
	p.amount = 18
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(w * 0.7, 0.2, h * 0.7)
	p.position = Vector3(0, 0.7, 0)
	p.direction = Vector3(1, 0, 0.3)
	p.spread = 15.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.15
	p.initial_velocity_max = 0.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.3, Color(1, 1, 1, 1))
	ramp.add_point(0.7, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	add_child(p)

# a one-off burst: dust off a blow, a puff from a footfall, a splash
func burst(at: Vector3, c: Color, n: int, speed: float, size: float, up := 1.0, life := 0.7) -> void:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _mote_mat(c)
	p.mesh = q
	p.amount = n
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.direction = Vector3(0, up, 0)
	p.spread = 70.0
	p.gravity = Vector3(0, -3.0, 0)
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.3, true, false, true).timeout.connect(p.queue_free)

func _ground_col(p: Vector2i) -> Color:
	var th: Dictionary = b.th
	var k: String = b.tile(p) if b.tile(p) != null else "."
	if k == "w":
		return Color(0.7, 0.85, 0.95, 0.8)
	return ((th.floor[1] as Color).lightened(0.25) * Color(1, 1, 1, 0.75))

# ---------------------------------------------------------------- the pieces
func step(u: Dictionary, p: Vector2i) -> void:
	var at: Vector3 = b.tile_pos(p) + Vector3(0, 0.05, 0)
	var wet: bool = b.tile(p) == "w" or b.tile(p) == "~"
	burst(at, _ground_col(p), 10 if wet else 6, 1.2 if wet else 0.7, 0.07, 1.0, 0.5)
	if wet:
		ripple(at)
	_play("splash" if wet else ("crunch" if WEATHER.get(b.board.get("theme", ""), "") == "snow" else "step"), -14.0, randf_range(0.9, 1.1))

func struck(t: Dictionary, from: Vector2i, dmg: int, crit: bool) -> void:
	var heavy := crit or dmg >= 8
	var away := Vector3(t.pos.x - from.x, 0, t.pos.y - from.y)
	if away.length() < 0.01:
		away = Vector3(0, 0, 1)
	away = away.normalized()
	var home: Vector3 = t.node.position
	var axis := away.cross(Vector3.UP).normalized()
	var tilt := (0.35 if heavy else 0.2)
	var tw := create_tween()
	tw.tween_property(t.node, "quaternion", Quaternion(axis, -tilt), 0.07)
	if heavy:
		tw.parallel().tween_property(t.node, "position", home + away * 0.28, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(t.node, "quaternion", Quaternion(axis, tilt * 0.4), 0.12)
	tw.tween_property(t.node, "quaternion", Quaternion.IDENTITY, 0.18)
	if heavy:
		tw.parallel().tween_property(t.node, "position", home, 0.3).set_trans(Tween.TRANS_SINE)
	_play("thud", -6.0 if heavy else -10.0, randf_range(0.85, 1.05) * (0.85 if heavy else 1.0))
	if heavy:
		# dust shaken down off the stone, and the table jolts
		burst(t.node.position + Vector3(0, 2.6, 0), Color(0.85, 0.8, 0.7, 0.7), 24, 0.6, 0.05, -1.0, 1.4)
		burst(t.node.position + Vector3(0, 0.1, 0), _ground_col(t.pos), 14, 1.6, 0.08, 1.0, 0.6)
		shake = 1.0 if crit else 0.6
		var theme: String = b.board.get("theme", "")
		if theme in CRACKS:
			crack(t.pos)
		elif theme in SMOULDER and crit:
			smoulder(t.pos)
		if b.tile(t.pos) == "w" or b.tile(t.pos) == "~":
			ripple(b.tile_pos(t.pos) + Vector3(0, 0.05, 0), 1.6)
	if crit:
		_play("ring", -8.0, 1.0)
		push_in(t.node.position, 0.9)

func toppled(u: Dictionary, from: Vector2i) -> void:
	var away := Vector3(u.pos.x - from.x, 0, u.pos.y - from.y)
	if away.length() < 0.01:
		away = Vector3(1, 0, 0)
	away = away.normalized()
	var axis := away.cross(Vector3.UP).normalized()
	var tw := create_tween()
	tw.tween_property(u.node, "quaternion", Quaternion(axis, -1.45), 0.55).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(u.node, "position", u.node.position + away * 0.35 + Vector3(0, 0.05, 0), 0.55)
	_play("topple", -7.0, randf_range(0.9, 1.05))
	burst(u.node.position + away * 0.6, _ground_col(u.pos), 16, 1.3, 0.08, 1.0, 0.7)
	_swell()

# ---------------------------------------------------------------- the ground answers (looks only)
func _fade_out(n: Node3D, m: StandardMaterial3D, after: float, secs: float) -> void:
	var tw := create_tween()
	tw.tween_interval(after)
	tw.tween_property(m, "albedo_color:a", 0.0, secs)
	tw.tween_callback(n.queue_free)

# rings that spread over water from a footfall or a blow
func ripple(at: Vector3, big := 1.0) -> void:
	for i in 2:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.8, 0.9, 1.0, 0.55)
		var r := MeshInstance3D.new()
		r.mesh = M.torus_mesh(0.18, 0.012)
		r.material_override = m
		r.position = at
		add_child(r)
		var tw := create_tween()
		tw.tween_interval(i * 0.18)
		tw.tween_property(r, "scale", Vector3.ONE * 3.2 * big, 0.9).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.9)
		tw.tween_callback(r.queue_free)

# a star of cracks in ice or glass under a heavy blow; it fades after a while
func crack(p: Vector2i) -> void:
	var at: Vector3 = b.tile_pos(p) + Vector3(0, 0.015, 0)
	var n := Node3D.new()
	n.position = at
	add_child(n)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.9, 0.97, 1.0, 0.85)
	for i in 7:
		var a := TAU * i / 7.0 + randf_range(-0.25, 0.25)
		var len := randf_range(0.35, 0.55)
		var seg := MeshInstance3D.new()
		seg.mesh = M.box(0.045, 0.006, len)
		seg.material_override = m
		seg.rotation = Vector3(0, a, 0)
		seg.position = Vector3(sin(a), 0, cos(a)) * (0.3 + len * 0.5)
		n.add_child(seg)
		# a fork off each spoke
		var f := MeshInstance3D.new()
		f.mesh = M.box(0.03, 0.006, len * 0.45)
		f.material_override = m
		var a2 := a + randf_range(-0.6, 0.6)
		f.rotation = Vector3(0, a2, 0)
		f.position = Vector3(sin(a), 0, cos(a)) * (0.3 + len * 0.8) + Vector3(sin(a2), 0, cos(a2)) * len * 0.22
		n.add_child(f)
	n.scale = Vector3.ONE * 0.2
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3.ONE, 0.12).set_ease(Tween.EASE_OUT)
	_play("crunch", -9.0, 0.7)
	_fade_out(n, m, 5.0, 2.0)

# moss and roots smoulder where a crit lands: embers, a little smoke and a dying glow
func smoulder(p: Vector2i) -> void:
	var at: Vector3 = b.tile_pos(p) + Vector3(0, 0.05, 0)
	burst(at, Color(1.0, 0.55, 0.2, 0.95), 18, 1.1, 0.05, 1.0, 1.2)
	burst(at + Vector3(0, 0.3, 0), Color(0.35, 0.32, 0.3, 0.45), 10, 0.4, 0.3, 1.0, 2.2)
	var l := OmniLight3D.new()
	l.light_color = Color("ff7a30")
	l.light_energy = 1.6
	l.omni_range = 2.2
	l.position = at + Vector3(0, 0.25, 0)
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 2.5)
	tw.tween_callback(l.queue_free)

# ---------------------------------------------------------------- the camera
func push_in(at: Vector3, hold: float) -> void:
	if b.fast and b.auto:
		return
	var z0: float = b.cam_zoom
	var f0: Vector3 = b.cam_focus
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(b, "cam_zoom", z0 * 0.62, 0.25).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(b, "cam_focus", f0.lerp(Vector3(at.x, 0, at.z), 0.6), 0.25)
	tw.tween_interval(hold)
	tw.tween_property(b, "cam_zoom", z0, 0.45).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(b, "cam_focus", f0, 0.45)

func slow(factor: float, secs: float) -> void:
	if b.fast and b.auto:
		return
	var base := Engine.time_scale
	Engine.time_scale = base * factor
	await get_tree().create_timer(secs, true, false, true).timeout
	Engine.time_scale = base

func final_blow(at: Vector3) -> void:
	push_in(at, 1.4)
	_play("ring", -6.0, 0.75)
	await slow(0.3, 1.1)

# a boss board: the camera takes one slow turn round the table before the fight
func sweep() -> void:
	if b.fast and b.auto:
		return
	var z0: float = b.cam_zoom
	b.cam_zoom = z0 * 0.8
	var tw := create_tween()
	tw.tween_method(func(v: float): b.cam_spin = v, -TAU, 0.0, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(b, "cam_zoom", z0, 2.6)
	await tw.finished

# ---------------------------------------------------------------- sound
func _sounds() -> void:
	# a cave's echo on its own bus
	var i := AudioServer.get_bus_index("Cave")
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "Cave")
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.85
		rv.damping = 0.4
		rv.wet = 0.35
		rv.dry = 0.85
		AudioServer.add_bus_effect(i, rv)
	bus = "Cave"
	sfx = {
		"step": _wav(0.07, 0.0, 1.0, 900.0, 0.03),
		"crunch": _wav(0.1, 0.0, 1.0, 3000.0, 0.05),
		"splash": _wav(0.22, 0.0, 1.0, 2200.0, 0.12),
		"thud": _wav(0.25, 70.0, 0.55, 600.0, 0.08),
		"topple": _wav(0.4, 95.0, 0.5, 1400.0, 0.18),
		"ring": _wav(0.9, 880.0, 0.0, 0.0, 0.6, 1320.0),
	}

# A little synthesized sound: a decaying tone (and its fifth) plus a burst of filtered noise.
func _wav(secs: float, hz: float, noise: float, cut: float, decay: float, hz2 := 0.0) -> AudioStreamWAV:
	var rate := 22050
	var n := int(secs * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var a := 1.0 - exp(-TAU * max(cut, 1.0) / rate)
	for k in n:
		var tt := float(k) / rate
		var env := exp(-tt / max(decay, 0.001))
		var s := 0.0
		if hz > 0.0:
			s += sin(TAU * hz * tt) * (1.0 - noise)
		if hz2 > 0.0:
			s += sin(TAU * hz2 * tt) * 0.5
		if noise > 0.0:
			lp += a * (randf_range(-1.0, 1.0) - lp)
			s += lp * noise * 2.5
		var v := int(clamp(s * env * 0.6, -1.0, 1.0) * 32000.0)
		data.encode_s16(k * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w

func _play(k: String, db: float, pitch := 1.0) -> void:
	if not sfx.has(k):
		return
	var p := AudioStreamPlayer.new()
	p.stream = sfx[k]
	p.volume_db = db
	p.pitch_scale = pitch
	p.bus = bus
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

# the fight's music builds as the foes fall
func _swell() -> void:
	var mu: AudioStreamPlayer = b.world.music
	if mu == null:
		return
	if not is_instance_valid(b):
		return
	var left: float = float(b.living("foe").size()) / float(foes0)
	var tw := create_tween()
	tw.tween_property(mu, "volume_db", lerp(-4.0, -16.0, left), 1.5)
