# Labyrinth of Roots 3D. Created by: Adrian Blackshire and Claude.
# Builds the world, the story panel and the story, then runs Parts I to IV.
#
# Test flags (after "--" on the command line):
#   --autoplay        picks choices and presses every button by itself
#   --seed=N          fixes the dice
#   --shots=DIR       saves screenshots at the story's key moments
#   --fast            no typewriter, short waits (for headless runs)
#   --look            the painted diorama look (test)
#   --explore=KEY     play a dungeon's fight boards in order (scripts/tactics/campaign.gd);
#                     --explore=all plays all twenty in chapter order
#   --battle=KEY      straight into a tactics battle (nest, gallery); with --autoplay both sides play themselves
extends Node3D

signal advance(how)

var rng := RandomNumberGenerator.new()
var ui
var world
var story
var autoplay := false
var fast := false
var test_tier := 0   # --tier=N: a single battle as the Nth dungeon would play it
var shots_dir := ""
var shot_n := 0

func _ready() -> void:
	var seeded := false
	for a in OS.get_cmdline_user_args():
		if a == "--autoplay":
			autoplay = true
		elif a == "--fast":
			fast = true
		elif a.begins_with("--seed="):
			rng.seed = int(a.substr(7))
			seeded = true
		elif a.begins_with("--tier="):
			test_tier = int(a.substr(7))
		elif a.begins_with("--shots="):
			shots_dir = a.substr(8)
	if not seeded:
		rng.randomize()
	world = preload("res://scripts/world.gd").new()
	world.name = "World"
	world.main = self
	world.look = true  # the painted look, everywhere (it was --look while on trial)
	add_child(world)
	ui = preload("res://scripts/ui.gd").new()
	ui.name = "UI"
	ui.main = self
	add_child(ui)
	story = preload("res://scripts/story.gd").new()
	story.name = "Story"
	story.main = self
	add_child(story)
	if fast:
		Engine.time_scale = 4.0
	get_tree().root.size_changed.connect(_fit)
	_fit()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--battle="):
			battle_key = a.substr(9)
	var dungeon := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--explore="):
			dungeon = a.substr(10)
	var q := _query()
	if q.has("d"):
		await _from_2d(q)
	elif dungeon != "":
		await _explore(dungeon)
	elif battle_key != "":
		await _battle()
	else:
		var pick: String = await ui.start_menu()
		if pick == "story":
			story.run()
		else:
			await _explore(pick)
			get_tree().reload_current_scene()

var battle_key := ""
var battle

# The tactics battle (scripts/tactics/): the painted look, the board, its screen.
func _battle() -> void:
	while true:
		var r := await run_battle(battle_key, 0, "Fight again", test_tier)
		if autoplay:
			get_tree().quit()
			return

# One fight on the tactics board: build it, play it, show the result, clear it away.
# hp: your HP going in (0 = full). Returns {"result", "hp"}.
func run_battle(key: String, hp := 0, after := "Continue", tier := 0) -> Dictionary:
	battle = preload("res://scripts/tactics/battle.gd").new()
	battle.name = "Battle"
	battle.main = self
	battle.world = world
	battle.rng = rng
	battle.auto = autoplay
	battle.demo = "--demo" in OS.get_cmdline_user_args()
	battle.start_hp = hp
	battle.tier = tier
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--closeup="):
			battle.closeup = a.substr(10)
	battle.fast = fast
	battle.setup(key)
	add_child(battle)
	var bui = preload("res://scripts/tactics/battle_ui.gd").new()
	bui.main = self
	add_child(bui)
	battle.ui = bui
	battle.build()
	await get_tree().process_frame
	ui.fade_in(0.8)
	var r: String = await battle.run()
	bui.result(r, battle, after)
	await shot("battle-" + key)
	if autoplay:
		await get_tree().create_timer(1.5).timeout
	else:
		while true:
			var ev: Dictionary = await battle.picked
			if ev.type == "again":
				break
	var you = battle.me()
	var left: int = you.hp if you != null else 0
	await ui.fade_out(0.6)
	bui.queue_free()
	battle.queue_free()
	battle = null
	world.player.visible = true
	world.player.process_mode = Node.PROCESS_MODE_INHERIT
	world.set_physics_process(true)
	world.set_process_unhandled_input(true)
	world.joy.visible = true
	world.cam_fixed = false
	return {"result": r, "hp": left}

# The 2D game can send one of its fights here: it opens this page in a frame with
# ?d=DUNGEON&f=N&hpf=0.73&pr=she (f: which fight board, "boss" for the boss board; hpf: your HP
# as a share of your most). When it's over, the result goes back to the 2D game by postMessage.
func _query() -> Dictionary:
	var q := {}
	var src := ""
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("window.location.search", true)
		if v is String:
			src = v
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--from2d="):
			src = a.substr(9)
	for pair in src.trim_prefix("?").split("&", false):
		var kv: PackedStringArray = pair.split("=")
		if kv.size() == 2:
			q[kv[0].uri_decode()] = kv[1].uri_decode()
	return q

func _from_2d(q: Dictionary) -> void:
	var DG = preload("res://scripts/explore/dungeons.gd")
	var key: String = q.d if DG.DUNGEONS.has(q.d) else "roots"
	var dd: Dictionary = DG.DUNGEONS[key]
	var boards := []
	var digits: Array = dd.get("fights", {}).keys()
	digits.sort()
	for dg in digits:
		boards.append(dd.fights[dg])
	var board: String = dd.boss
	if q.get("f", "") != "boss" and boards.size() > 0:
		board = boards[clampi(int(q.get("f", "0")), 0, boards.size() - 1)]
	if q.has("pr"):
		story.S["pr"] = q.pr
	if q.get("auto", "") == "1":
		autoplay = true  # for the 2D game's tests
	var tier: int = max(0, DG.ORDER.find(key))
	var mx: int = 24 + tier * 2
	var hp: int = clampi(int(round(float(q.get("hpf", "1")) * mx)), 1, mx)
	world.player.visible = false
	var res: Dictionary = await run_battle(board, hp, "Back to the story", tier)
	var hpf: float = float(res.hp) / float(mx)
	print("[from2d] ", res.result, " ", hpf)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.parent.postMessage({lor3d: 1, result: '%s', hpf: %f}, '*')" % [res.result, hpf], true)
	if autoplay and not OS.has_feature("web"):
		get_tree().quit()

# A dungeon is its run of tactics boards (scripts/tactics/campaign.gd).
# "all" plays every dungeon in chapter order, starting fresh in each.
func _explore(key: String) -> void:
	var keys: Array = preload("res://scripts/explore/dungeons.gd").ORDER if key == "all" else [key]
	for k in keys:
		var c = preload("res://scripts/tactics/campaign.gd").new()
		c.name = "Campaign"
		c.main = self
		c.auto = autoplay
		add_child(c)
		var r: String = await c.run(k)
		print("== DUNGEON ", k, " ", r)
		c.queue_free()
		await get_tree().process_frame
	if autoplay:
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()

# Keeps text readable on phones and desktops alike: the UI scale follows the screen,
# and the 3D camera is told how much of the screen the story panel covers.
func _fit() -> void:
	var win := get_tree().root
	var ws := Vector2(win.size)
	if ws.x < 2 or ws.y < 2:
		return
	var dpr := DisplayServer.screen_get_scale()
	var f: float = max(min(ws.x / 520.0, ws.y / 760.0), dpr)
	f = clamp(f, 0.75, 4.0)
	win.content_scale_size = Vector2i(int(ws.x / f), int(ws.y / f))
	if ui:
		ui.layout(Vector2(ws.x / f, ws.y / f))

func shot(tag: String) -> void:
	if shots_dir == "":
		return
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	shot_n += 1
	DirAccess.make_dir_recursive_absolute(shots_dir)
	img.save_png(shots_dir.path_join("%02d-%s.png" % [shot_n, tag]))
	print("[shot] ", tag)
