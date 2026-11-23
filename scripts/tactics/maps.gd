# Battle boards and rules for the 3D tactics fights, matched to the 2D game's
# Tactical Advantage (index.html: FD_RULES, TA_CARDS, TA_CO, tacCompany).
# Created by: Adrian Blackshire and Claude.
#
# Each board is a grid of the 2D ground types, row 0 at the far side (the foes' end):
#   .  open ground     c  low cover      #  tall cover     r  rugged ground
#   h  high ground     ~  sinking ground i  black ice      o  warm stone     w  deep water
# The 3D board raises high ground, sinks the sinking ground, and dresses each square
# for its place (in the nest, low cover is a clutch of egg sacs and rugged ground is web).
extends RefCounted

const BOARDS := {
	# The nest under the Hollow Chamber: Ryytaa the Ender and four of her brood. 14 x 9,
	# wider than the 2D 7 x 6, so the fight has room and the ground is worth racing for.
	"nest": {
		"title": "The Nest",
		"blurb": "Ryytaa's cavern: egg clutches to hide behind, webs that drag at your feet, sinking silk-mire, and her ledge at the back.",
		"stage": "nest",
		"dress": "nest",
		"grid": [
			"#c.rr.hh.rr.c#",
			"..r...hh...r..",
			"c...~~..~~...c",
			".r..~....~..r.",
			"..h...cc...h..",
			"..h..#..#..h..",
			".c..r....r..c.",
			"..............",
			"#....r..r....#",
		],
		"units": [
			["you", 6, 7], ["burr", 7, 7],
			["ryytaa", 6, 0], ["spider", 3, 2], ["spider", 10, 2], ["spider", 2, 1], ["spider", 11, 1],
		],
		"captains": ["ryytaa"],
	},
	# The Root Gallery (the 2D roots field), widened: root-curtains, a sap-pool, a rise.
	"gallery": {
		"title": "The Root Gallery",
		"blurb": "A long hall of the labyrinth where the roots have come down from the ceiling like curtains, and a sap-pool shines in the middle of the floor.",
		"stage": "nest",
		"dress": "roots",
		"grid": [
			"c#..rc..#..c",
			"...~....h.hh",
			".r.~.r..hh..",
			"c....#..c...",
			"..rr...~~.r.",
			".c....c.....",
			"...r.....#..",
			"............",
		],
		"units": [
			["you", 5, 7], ["burr", 6, 7],
			["spider", 3, 0], ["spider", 7, 1], ["spider", 10, 3],
		],
		"captains": [],
	},
}

# The ground, word for word from the 2D game.
const GROUND := {
	".": ["Open ground", "Easy going. A straight run of 2 or more steps across it, ending in a blow, is a charge: +2 damage. It can charge you here too."],
	"c": ["Low cover", "Blows at you get −1. Nothing charges you through it."],
	"#": ["Tall cover", "Can't be crossed. It blocks a sling or bow shot."],
	"r": ["Rugged ground", "Costs 2 steps. Whoever swings from it is at −1, and nobody can charge someone standing in it."],
	"h": ["High ground", "Costs 2 steps to climb. +1 to hit and +1 damage against anyone below. A foe shoved off it falls."],
	"~": ["Sinking ground", "Whoever is in it is stuck: −3 to their blows and +3 to blows at them, and 2 steps to get out. Shove a foe in."],
	"i": ["Black ice", "Step onto it and you slide the same way until something stops you: a wall, a block, a warm stone or another body."],
	"o": ["Warm stone", "A stone that holds a little heat. Anyone sliding stops on it."],
	"w": ["Deep water", "Nobody can stand in it. It doesn't block a shot. Shove a foe in and the water has it for a moment."],
}

# The cards (2D TA_CARDS), the ones these fights use. die = [count, sides, bonus].
const CARDS := {
	"strike": {"name": "Strike", "min": 1, "max": 1, "melee": true, "text": "Your weapon. A straight run of 2+ steps into it is a charge, +2."},
	"heavy": {"name": "Heavy Blow", "cost": 2, "min": 1, "max": 1, "melee": true, "twice": true, "text": "Roll the weapon's dice twice."},
	"shove": {"name": "Shove", "cost": 1, "min": 1, "max": 1, "melee": true, "shove": true, "die": [1, 4, 0], "text": "Push it a square: into sinking ground, off a ledge, into rock."},
	"sling": {"name": "Sling", "min": 2, "max": 4, "ranged": true, "die": [1, 4, 1], "text": "A stone from range. Tall cover blocks it."},
	"bite": {"name": "Bite", "min": 1, "max": 1, "melee": true, "text": "Teeth at the knee."},
	"drag": {"name": "Drag Down", "cost": 1, "min": 1, "max": 1, "melee": true, "stun": true, "die": [1, 4, 0], "text": "It goes down and loses its next turn."},
	"spray": {"name": "Venom Spray", "min": 2, "max": 3, "ranged": true, "die": [1, 6, 0], "text": "Venom from range. Tall cover blocks it."},
}

# Who fights. hit and ac as in the story (Parts I–IV); Burr from TA_CO (hp 45% of yours,
# AC one under yours, speed 12, 4 steps, Bite and Drag Down). Ryytaa is the captain:
# drop her and the rest break.
const UNITS := {
	"you": {"name": "You", "side": "you", "kind": "you", "hp": 24, "hit": 5, "ac": 13, "die": [1, 12, 3], "spd": 10, "mv": 3,
		"cards": ["strike", "heavy", "shove", "sling"], "art": "hero"},
	"burr": {"name": "Burr", "side": "you", "kind": "co", "hp": 11, "hit": 5, "ac": 12, "die": [1, 6, 1], "spd": 12, "mv": 4,
		"cards": ["bite", "drag"], "art": "res://art/pieces/tok_burr.webp", "small": true},
	"spider": {"name": "Spider", "side": "foe", "kind": "sol", "hp": 6, "hit": 4, "ac": 12, "die": [1, 4, 1], "spd": 7, "mv": 3,
		"cards": ["strike", "spray"], "art": "res://art/pieces/tok_spider.png", "medal": true},
	"ryytaa": {"name": "Ryytaa", "side": "foe", "kind": "cap", "hp": 22, "hit": 5, "ac": 13, "die": [1, 8, 2], "spd": 8, "mv": 3,
		"cards": ["strike", "heavy"], "art": "res://art/pieces/tok_ryytaa.webp", "big": true},
}
