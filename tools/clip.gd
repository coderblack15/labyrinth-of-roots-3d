# Records a short walk along the Pathway in the diorama look, steering with the on-screen stick.
#   godot --path . --rendering-driver opengl3 --write-movie OUT/frame.png --fixed-fps 24 --script res://tools/clip.gd
extends SceneTree

class FakeStory:
	var S := {"axe": false}
class FakeMain:
	extends Node
	signal advance(how)
	var story = FakeStory.new()
	var ui = null
	var rng := RandomNumberGenerator.new()

var world
var f := 0
const END := 230

func _init() -> void:
	var fm := FakeMain.new()
	get_root().add_child(fm)
	world = load("res://scripts/world.gd").new()
	world.main = fm
	world.look = true
	fm.add_child(world)
	await process_frame
	world.build("pathway")
	world.set_light("dusk", 0.01)
	world.place_player(Vector3(0, 0.1, 6.5), 0)
	process_frame.connect(_tick)

func _tick() -> void:
	f += 1
	var vs: Vector2 = world.get_viewport().get_visible_rect().size
	var c := Vector2(150, vs.y - 150)
	var stick := Vector2.ZERO
	if f > 18 and f < 100:
		stick = Vector2(0.08 * sin(f * 0.05), -1.0)
	elif f >= 100 and f < 160:
		world.cam_yaw = lerp(0.0, -0.75, smoothstep(100.0, 160.0, float(f)))
	elif f >= 160 and f < 215:
		world.cam_yaw = lerp(-0.75, -0.25, smoothstep(160.0, 215.0, float(f)))
		stick = Vector2(0.25, -0.9)
	if stick != Vector2.ZERO:
		if not world.joy.active:
			world.joy.begin(c)
		world.joy.drag(c + stick * 56.0)
		world.demo_input = world.joy.value
	else:
		if world.joy.active:
			world.joy.end()
		world.demo_input = Vector2.ZERO
	if f >= END:
		quit()
