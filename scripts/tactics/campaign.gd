# A dungeon played as its run of tactics boards: the fights in order, then the boss.
# A short card opens each fight; your HP carries over, with a breather after each win.
# Lose a fight and Burr drags you clear: you try that board again at half HP.
# Created by: Adrian Blackshire and Claude.
extends Node

const DG = preload("res://scripts/explore/dungeons.gd")

var main
var auto := false

func run(key: String) -> String:
	var d: Dictionary = DG.DUNGEONS[key]
	var tier: int = DG.ORDER.find(key)
	var max_hp: int = 24 + tier * 2
	var hp: int = max_hp
	var steps := []
	var digits: Array = d.get("fights", {}).keys()
	digits.sort()
	for dg in digits:
		steps.append({"board": d.fights[dg], "line": d.get("lines", {}).get(dg, ["Foes!", "They come at you out of the dark."])})
	steps.append({"board": d.boss, "line": d.boss_line, "boss": true})
	main.world.player.visible = false
	await _card(d.title, d.chapter, d.intro, "Begin")
	var i := 0
	while i < steps.size():
		var s: Dictionary = steps[i]
		var tag := "Boss" if s.get("boss", false) else "Fight %d of %d" % [i + 1, steps.size() - 1]
		await _card(s.line[0], tag + "   ·   HP %d/%d" % [hp, max_hp], s.line[1], "Fight")
		var res: Dictionary = await main.run_battle(s.board, hp, "Continue", tier)
		main.world.player.visible = false
		if res.result == "victory":
			# a breather after the fight: Burr licks your hand, you bind the worst of it
			hp = min(max_hp, max(1, res.hp) + 4)
			i += 1
		else:
			hp = max_hp / 2
			await _card("Burr drags you clear", "HP %d/%d" % [hp, max_hp], "Vaelric's axe holds you at 1 HP. You gather yourself and go again.", "Try again")
	await _card("Dungeon cleared", d.title, d.get("outro", "The way on is open."), "Continue")
	return "cleared"

func _card(title: String, sub: String, text: String, go: String) -> void:
	print("[dungeon] ", title, ": ", text)
	var ui = main.ui
	var t: Dictionary = ui._overlay()
	ui._lbl(t.box, title, 28, ui.C_GOLD)
	ui._lbl(t.box, sub, 15, ui.C_MECH)
	ui._lbl(t.box, text, 18)
	var b: Button = ui._button(go)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.box.add_child(b)
	await ui.fade_in(0.5)
	if auto:
		ui._auto(func(): b.pressed.emit())
	await b.pressed
	await ui.fade_out(0.4)
	t.o.queue_free()
