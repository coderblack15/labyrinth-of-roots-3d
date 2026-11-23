# The dungeons, one per chapter. Created by: Adrian Blackshire and Claude.
#
# A dungeon is a maze of 4 m cells, row 0 at the north:
#   #  wall              .  floor            P  where you come in
#   K  the key           D  a locked door    S  a cracked wall (search it to break through)
#   C  a chest           B  the boss's door  1-9  a fight (walk in and it starts)
#   ,  overgrown floor (ferns, moss, fungus) ~  a pool (shallow, walkable, looks wet)
# fights maps each digit to a board in scripts/tactics/maps.gd; boss is the last board.
# theme picks the stone, the plants and the light.
extends RefCounted

const DUNGEONS := {
	"roots": {
		"title": "Under the Roots",
		"chapter": "Parts I–IV",
		"intro": "Past the root-gate the labyrinth closes over you. Somewhere below, something clicks in the dark.",
		"theme": "roots",
		"maze": [
			"###########",
			"#P.,#..,#K#",
			"#,#...#.#.#",
			"#.#####,#1#",
			"#.,.#.#.,.#",
			"#####.###.#",
			"#,C.S..,..#",
			"#########D#",
			"#,~.,.B.,.#",
			"###########",
		],
		"fights": {"1": "gallery"},
		"boss": "nest",
		"chest": {"name": "a healing draught", "heal": 12},
	},
}

# How each theme dresses its maze and its boards.
const THEMES := {
	"roots": {
		"floor": ["cavefloor", Color("6e6254"), 0.3],
		"wall": ["caverock", Color("5a524a"), 0.3],
		"trim": ["root", Color("6a4a32"), 0.55],
		"light": Color("ffb070"),
		"amb": Color("4a4050"),
		# what grows here: ferns and moss in the damp, pale fungus that glows, hanging roots
		"plants": {"fern": Color("4a6a34"), "moss": Color("3e5a2e"), "fungus": Color("cfe0a0"), "glow": Color("9fe0a0")},
		"webs": true,
	},
}
