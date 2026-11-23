# Renders two fixed scenes (the Pathway at dusk, the Nest fight) to PNGs, for comparing looks.
#   godot --path . --rendering-driver opengl3 --script res://tools/lookshot.gd -- OUTPREFIX [--look]
extends SceneTree

class FakeStory:
	var S := {"axe": true}
class FakeMain:
	extends Node
	signal advance(how)
	var story = FakeStory.new()
	var ui = null
	var rng := RandomNumberGenerator.new()

func _init() -> void:
	var ua := OS.get_cmdline_user_args()
	var out: String = ua[0] if ua.size() > 0 else "look"
	var fm := FakeMain.new()
	get_root().add_child(fm)
	var world = load("res://scripts/world.gd").new()
	world.main = fm
	world.look = "--look" in ua
	fm.add_child(world)
	await process_frame
	world.build("pathway")
	world.set_light("dusk", 0.01)
	world.place_player(Vector3(0, 0.1, -4.0), 0)
	await _settle(world)
	_save(out + "-pathway.png")
	if "--pathway" in ua:
		quit()
		return
	world.build("corridors")
	world.set_light("torch", 0.01)
	world.hero_take_torch()
	world.place_player(Vector3(0, 0.1, -3.0), 0)
	await _settle(world)
	_save(out + "-corridors.png")
	world.build("chamber")
	world.set_light("torch", 0.01)
	world.place_player(Vector3(0, 0.1, 6.0), 0)
	await _settle(world)
	_save(out + "-chamber.png")
	world.build("nest")
	world.set_light("torch", 0.01)
	world._hold("hand_r", load("res://scripts/models.gd").axe(), Vector3(0, -0.1, 0), Vector3(-50, 0, 0))
	world.hero_take_torch()
	world.torch_light.visible = true
	world.place_player(world.sq(3, 4), 0)
	world.props.ryytaa.visible = true
	var spots := [[3, 2], [1, 4], [5, 4]]
	for i in 3:
		var sp = world.props["sp_" + ["a", "b", "c"][i]]
		sp.visible = true
		sp.position = world.sq(spots[i][0], spots[i][1])
		sp.look_at(world.sq(3, 4), Vector3.UP, false)
	world.cam_fixed = true
	world.cam_fixed_pos = world.sq(3, 4) + Vector3(0.6, 5.4, 6.2)
	world.cam_fixed_look = world.sq(3, 2)
	world.cam.global_position = world.cam_fixed_pos
	world.cam_look = world.cam_fixed_look
	await _settle(world)
	_save(out + "-nest.png")
	quit()

func _settle(world) -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw

func _save(p: String) -> void:
	get_root().get_texture().get_image().save_png(p)
	print("saved ", p)
