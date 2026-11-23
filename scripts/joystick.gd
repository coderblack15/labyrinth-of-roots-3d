# On-screen thumb stick for phones: touch the 3D view and drag to walk.
# A quick tap still walks to the spot you tapped. A second finger turns the camera.
extends Control

var active := false
var base := Vector2.ZERO
var knob := Vector2.ZERO
var value := Vector2.ZERO  # -1..1, x right, y down
const R := 56.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func begin(p: Vector2) -> void:
	active = true
	base = p
	knob = p
	value = Vector2.ZERO
	queue_redraw()

func drag(p: Vector2) -> void:
	var d := p - base
	if d.length() > R:
		d = d.normalized() * R
	knob = base + d
	value = d / R
	queue_redraw()

func end() -> void:
	active = false
	value = Vector2.ZERO
	queue_redraw()

func _draw() -> void:
	if not active:
		return
	draw_circle(base, R, Color(0.05, 0.04, 0.03, 0.35))
	draw_arc(base, R, 0, TAU, 48, Color(0.91, 0.75, 0.44, 0.7), 2.0, true)
	draw_circle(knob, 22.0, Color(0.91, 0.75, 0.44, 0.75))
