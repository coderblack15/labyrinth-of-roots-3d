# The battle's screen: the turn bar along the top (as the 2D game's), the active piece's
# card with its cards to play, the odds and ground notes, a short log, camera turns and a
# ground key. Sized for a phone in either direction. Created by: Adrian Blackshire and Claude.
extends CanvasLayer

const MAPS = preload("res://scripts/tactics/maps.gd")
const C_TEXT := Color("e8dcc4")
const C_GOLD := Color("f3d27a")

var main
var root: Control
var bar: HBoxContainer
var who_lbl: Label
var stat_lbl: RichTextLabel
var cards_box: HFlowContainer
var info_lbl: RichTextLabel
var log_lbl: RichTextLabel
var ban: VBoxContainer
var ban_t: Label
var ban_s: Label
var key_panel: PanelContainer
var bottom: PanelContainer
var logs := []
var circle: Shader

func _ready() -> void:
	layer = 6
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = main.ui._theme()
	add_child(root)
	circle = Shader.new()
	circle.code = "shader_type canvas_item;\nuniform vec4 ring : source_color = vec4(1.0);\nvoid fragment(){ vec2 p = UV*2.0-1.0; float r = length(p); if (r > 1.0) discard; vec4 c = texture(TEXTURE, UV); if (r > 0.86) c = ring; COLOR = c; }"
	# the turn bar
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 8
	top.offset_right = -8
	top.offset_top = 6
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 2)
	top.add_child(tv)
	var tl := Label.new()
	tl.text = "Turn order"
	tl.add_theme_font_size_override("font_size", 12)
	tl.add_theme_color_override("font_color", Color("a99a7a"))
	tv.add_child(tl)
	bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	tv.add_child(bar)
	# the bottom panel: who, cards, odds, log
	bottom = PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 8
	bottom.offset_right = -8
	bottom.offset_bottom = -8
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(bottom)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	bottom.add_child(bv)
	var hb := HBoxContainer.new()
	bv.add_child(hb)
	who_lbl = Label.new()
	who_lbl.add_theme_font_size_override("font_size", 20)
	who_lbl.add_theme_color_override("font_color", C_GOLD)
	hb.add_child(who_lbl)
	stat_lbl = RichTextLabel.new()
	stat_lbl.bbcode_enabled = true
	stat_lbl.fit_content = true
	stat_lbl.scroll_active = false
	stat_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_lbl.add_theme_font_size_override("normal_font_size", 16)
	hb.add_child(stat_lbl)
	info_lbl = RichTextLabel.new()
	info_lbl.bbcode_enabled = true
	info_lbl.fit_content = true
	info_lbl.scroll_active = false
	info_lbl.add_theme_font_size_override("normal_font_size", 16)
	info_lbl.add_theme_font_size_override("bold_font_size", 16)
	bv.add_child(info_lbl)
	cards_box = HFlowContainer.new()
	cards_box.add_theme_constant_override("h_separation", 6)
	cards_box.add_theme_constant_override("v_separation", 6)
	bv.add_child(cards_box)
	log_lbl = RichTextLabel.new()
	log_lbl.bbcode_enabled = true
	log_lbl.fit_content = true
	log_lbl.scroll_active = false
	log_lbl.add_theme_font_size_override("normal_font_size", 13)
	log_lbl.add_theme_color_override("default_color", Color("a9b8c8"))
	bv.add_child(log_lbl)
	# camera turns and the ground key, small, at the right edge
	var side := VBoxContainer.new()
	side.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	side.offset_right = -8
	side.offset_left = -64
	side.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	side.add_theme_constant_override("separation", 6)
	root.add_child(side)
	for b in [["Turn", "turn"], ["Key", "key"]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(56, 40)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_side.bind(b[1]))
		side.add_child(btn)
	key_panel = PanelContainer.new()
	key_panel.set_anchors_preset(Control.PRESET_CENTER)
	key_panel.visible = false
	root.add_child(key_panel)
	# the banner
	ban = VBoxContainer.new()
	ban.set_anchors_preset(Control.PRESET_CENTER)
	ban.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ban.modulate.a = 0.0
	root.add_child(ban)
	ban_t = Label.new()
	ban_t.add_theme_font_size_override("font_size", 34)
	ban_t.add_theme_color_override("font_color", C_GOLD)
	ban_t.add_theme_constant_override("outline_size", 10)
	ban_t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	ban_t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ban.add_child(ban_t)
	ban_s = Label.new()
	ban_s.add_theme_font_size_override("font_size", 16)
	ban_s.add_theme_constant_override("outline_size", 8)
	ban_s.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	ban_s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ban_s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ban_s.custom_minimum_size = Vector2(320, 0)
	ban.add_child(ban_s)

var battle

func _side(k: String) -> void:
	if k == "turn":
		battle.turn_cam(1)
	else:
		key_panel.visible = not key_panel.visible
		if key_panel.visible:
			_fill_key()

func _fill_key() -> void:
	for c in key_panel.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	key_panel.add_child(v)
	var used := {}
	for row in battle.G:
		for ch in row:
			used[ch] = true
	for row in battle.L:
		for lv in row:
			if lv > 0:
				used["h"] = true
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.custom_minimum_size = Vector2(min(440, root.size.x - 40), 0)
	r.add_theme_font_size_override("normal_font_size", 15)
	r.add_theme_font_size_override("bold_font_size", 15)
	var t := "[b]The ground on this board[/b]\n"
	for k in [".", "c", "p", "#", "P", "r", "h", "=", "~", "i", "o", "w"]:
		if used.has(k):
			var g: Array = MAPS.GROUND[k]
			t += "\n[color=#%s]■[/color] [b]%s[/b]: %s" % [battle._kind_col(k).to_html(false), g[0], g[1]]
	t += "\n\n[i]Spiders and Ryytaa climb anything, and reach up or down any height.[/i]"
	r.text = t
	v.add_child(r)
	var b := Button.new()
	b.text = "Close"
	b.pressed.connect(func(): key_panel.visible = false)
	v.add_child(b)

func banner(t: String, s: String) -> void:
	ban_t.text = t
	ban_s.text = s
	ban.reset_size()
	ban.position = (root.size - ban.size) * 0.5 - Vector2(0, root.size.y * 0.12)
	var tw := create_tween()
	tw.tween_property(ban, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.4 if s == "" else 2.4)
	tw.tween_property(ban, "modulate:a", 0.0, 0.5)

func _art(u: Dictionary) -> Texture2D:
	return u.mat.get_shader_parameter("art")

func order(list: Array, b) -> void:
	battle = b
	for c in bar.get_children():
		c.queue_free()
	for i in list.size():
		var u: Dictionary = list[i]
		var tr := TextureRect.new()
		tr.texture = _art(u)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var s := 44 if i == 0 else 34
		tr.custom_minimum_size = Vector2(s, s)
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sm := ShaderMaterial.new()
		sm.shader = circle
		sm.set_shader_parameter("ring", C_GOLD if i == 0 else (Color("6fd08c") if u.side == "you" else Color("e0573f")))
		tr.material = sm
		tr.tooltip_text = u.name
		bar.add_child(tr)

func panel(u, b) -> void:
	battle = b
	for c in cards_box.get_children():
		c.queue_free()
	if u == null:
		who_lbl.text = ""
		stat_lbl.text = ""
		return
	who_lbl.text = u.name
	# ◆ Resonance as gold dots (the web build's font has no ◆)
	var res: String = "[color=#f3d27a]%s[/color][color=#5a4a30]%s[/color]" % ["•".repeat(u.res), "•".repeat(3 - u.res)]
	stat_lbl.text = "  HP %d/%d · AC %d · Res %s%s" % [u.hp, u.max, u.ac, res, "" if not u.moved else " · moved"]
	for k in u.cards:
		var c: Dictionary = MAPS.CARDS[k]
		var btn := Button.new()
		var cost: int = c.get("cost", 0)
		btn.text = c.name + ("" if cost == 0 else " " + "•".repeat(cost))
		btn.toggle_mode = true
		btn.button_pressed = b.sel_card == k
		btn.disabled = u.acted or not b.card_ok(u, k)
		btn.custom_minimum_size = Vector2(0, 44)
		btn.tooltip_text = c.text
		btn.pressed.connect(func(): b.picked.emit({"type": "card", "card": k}))
		cards_box.add_child(btn)
	if u.moved and not u.acted and b.undo_to != null:
		var ub := Button.new()
		ub.text = "Undo move"
		ub.custom_minimum_size = Vector2(0, 44)
		ub.pressed.connect(func(): b.picked.emit({"type": "undo"}))
		cards_box.add_child(ub)
	var end := Button.new()
	end.text = "End turn"
	end.custom_minimum_size = Vector2(0, 44)
	end.pressed.connect(func(): b.picked.emit({"type": "end"}))
	cards_box.add_child(end)

func facing(u: Dictionary, b) -> void:
	for c in cards_box.get_children():
		c.queue_free()
	info("Face a way: tap a blue square next to %s. Foes who come at the side or back get +2 or +4." % ("you" if u.id == "you" else u.name))
	var keep := Button.new()
	keep.text = "Keep facing"
	keep.custom_minimum_size = Vector2(0, 44)
	keep.pressed.connect(func(): b.picked.emit({"type": "keep"}))
	cards_box.add_child(keep)

func info(t: String) -> void:
	info_lbl.text = t

func tile_info(b, p: Vector2i) -> void:
	if b.tile(p) == null:
		return
	var k: String = b.raw(p)
	var g: Array = MAPS.GROUND[k]
	var u = b.at(p)
	var t := "[b]%s[/b]%s: %s" % [g[0], (", level %d" % b.level(p)) if b.level(p) > 0 else "", g[1]]
	if b.level(p) > 0:
		t += "\n[b]High ground[/b]: " + MAPS.GROUND["h"][1]
	if u != null:
		t = "[b]%s[/b], HP %d/%d, AC %d, standing on %s.\n" % [u.name, u.hp, u.max, u.ac, g[0].to_lower()] + t
	info(t)

func log_line(s: String) -> void:
	if s.begins_with("=="):
		return
	logs.push_front(s)
	logs = logs.slice(0, 3)
	log_lbl.text = "\n".join(logs)

func result(r: String, b, after := "Fight again") -> void:
	for c in cards_box.get_children():
		c.queue_free()
	var good := r == "victory"
	banner("Victory" if good else ("Burr drags you clear" if r == "dragged out" else "The fight stalls"),
		("Ryytaa is down and the brood breaks." if "ryytaa" in b.board.get("captains", []) else "The board is yours.") if good else "Vaelric's axe holds you at 1 HP. Try the ground another way.")
	info("[b]%s[/b]" % (("The nest is yours." if "ryytaa" in b.board.get("captains", []) else "They're beaten.") if good else "You're out of the fight, but not out of the labyrinth."))
	var again := Button.new()
	again.text = after
	again.custom_minimum_size = Vector2(0, 44)
	again.pressed.connect(func(): b.picked.emit({"type": "again"}))
	cards_box.add_child(again)
