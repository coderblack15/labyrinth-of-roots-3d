# Records a short walk (Pathway, or the Nest with --nest) in the diorama look, steering with the on-screen stick.
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
var nest := false
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
	nest = "--nest" in OS.get_cmdline_user_args()
	if nest:
		world.build("nest")
		world.set_light("torch", 0.01)
		world.hero_take_torch()
		world.props.ryytaa.visible = true
		world.place_player(Vector3(0, 0.1, 12.5), 0)
	else:
		world.build("pathway")
		world.set_light("dusk", 0.01)
		world.place_player(Vector3(0, 0.1, 6.5), 0)
	process_frame.connect(_tick)

func _tick() -> void:
	f += 1
	var vs: Vector2 = world.get_viewport().get_visible_rect().size
	var c := Vector2(150, vs.y - 150)
	var stick := Vector2.ZERO
	if nest:
		if f > 12 and f < 62:
			stick = Vector2(0.05 * sin(f * 0.08), -1.0)
		elif f >= 70 and f < 150:
			world.cam_yaw = lerp(0.0, -1.0, smoothstep(70.0, 150.0, float(f)))
		elif f >= 150 and f < 190:
			world.cam_yaw = lerp(-1.0, -0.6, smoothstep(150.0, 190.0, float(f)))
			stick = Vector2(0.0, -0.5)
		_drive(c, stick)
		if f >= 200:
			quit()
		return
	if f > 18 and f < 100:
		stick = Vector2(0.08 * sin(f * 0.05), -1.0)
	elif f >= 100 and f < 160:
		world.cam_yaw = lerp(0.0, -0.75, smoothstep(100.0, 160.0, float(f)))
	elif f >= 160 and f < 215:
		world.cam_yaw = lerp(-0.75, -0.25, smoothstep(160.0, 215.0, float(f)))
		stick = Vector2(0.25, -0.9)
	_drive(c, stick)
	if f >= END:
		quit()

func _drive(c: Vector2, stick: Vector2) -> void:
	if stick != Vector2.ZERO:
		if not world.joy.active:
			world.joy.begin(c)
		world.joy.drag(c + stick * 56.0)
		world.demo_input = world.joy.value
	else:
		if world.joy.active:
			world.joy.end()
		world.demo_input = Vector2.ZERO
