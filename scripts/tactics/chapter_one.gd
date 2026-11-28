# Chapter I, The Labyrinth of Roots, told between its tactics fights.
# The words follow the 2D game's Parts I to IV (STORY.md): the pathway and the strangers,
# the vine horror in the dark, the webs, the Hollow Chamber and Vaelric's axe, then the Nest.
# Each card is [title, small line, text, button].
# Created by: Adrian Blackshire and Claude.
extends RefCounted

const KEY := "roots"

const OPEN := [
	["Chapter I", "The Labyrinth of Roots   ·   Part I: The Pathway",
		"For two days you have walked the ceremonial pathway, stopping only to eat a few bites from your pack. On the road, two hooded strangers step into your way. \"Turn back,\" one says. \"Nothing that goes down there comes back up.\" You press three coins into their palms and walk on.",
		"Walk on"],
	["The outer gate", "Part I: The Pathway",
		"Level after level you go down, until the gate of the labyrinth rises in front of you, carved with spirals, antlered figures and runes that seem to shift when you look away. The sun sinks, the stone turns violet, and then the light is gone. Darkness, total and absolute.",
		"Step into the dark"],
	["Something unfolds", "Part I: The Pathway",
		"You never hear it coming. Behind you, a vine horror unfolds to its full height, nearly eight feet of thorned limbs made for tearing. One lashes past your ear. You run: left, right, left again, until the rustling fades. Burr is at your heel. With cloth, a stick and your flint you strike a torch.",
		"Raise the torch"],
]

# Shown before each fight, by its place in the run (0 = first). The boss has its own.
const BEFORE := {
	0: [["The Webs", "Part II: The Webs",
		"White webbing fills the corridor from floor to ceiling. Skeletons hang in it like flies, some still in rusted armour. A warm wind brushes your skin, though there should be no wind down here, and something hairy and jointed reaches out of the dark.",
		"Ready yourself"]],
	1: [["Under the webbing", "Part II: The Webs",
		"You smother the torch, crawl on your belly under the loose strands, and come out where the roots hang low. The ground is moving. Burrow-ticks, fat as fists, wake to the warmth of you and Burr.",
		"Ready yourself"]],
}

# How to play, once, before the first fight.
const GUIDE := ["How a fight goes", "Your first fight",
	"Gold squares show where you can move: tap one to walk there. Tap a foe once to see it, and again to strike. Your cards along the bottom are your moves: Strike, a Heavy Blow, a Shove that pushes a foe into sinking ground or off a ledge, and a Sling from range. Burr fights beside you on his own. Ground matters: high ground helps you hit, webs slow you, sinking ground traps whoever stands in it. Tap End turn when you're done.",
	"Got it"]

# Between the last road fight and the boss: the Hollow Chamber.
const CHAMBER := [
	["The Hollow Chamber", "Part III: The Hollow Chamber",
		"The passage opens into a round room that feels grown, not built, like the inside of a great hollowed tree. At its heart stands a dead trunk, split down the middle like a doorway. A skeleton in dented plate sits against the roots, and across its lap lies a two-handed axe set with ruby, sapphire and emerald.",
		"Lift the axe"],
	["The axe speaks", "Part III: The Hollow Chamber",
		"Power floods up your arms. A voice whispers from the blade: \"You will not perish here. Listen, and I will guide you through this catastrophe.\" The skeleton's left pauldron comes loose in your hand, a curved slab of steel the size of a small shield. You strap it to your forearm.",
		"Swing at the tree"],
	["Vaelric", "Part III: The Hollow Chamber",
		"Red light pulses from the trunk, and a ghost rises, the same shape as the skeleton at your feet. \"I am Vaelric, last warden of this place. My axe has chosen you. Carry it where I could not. Ryytaa the Ender nests beyond. Kill her, take what I guarded, and walk out into the light.\" The back of the tree splits open on a tunnel.",
		"Into the tunnel"],
]

const BOSS := ["The Nest", "Part IV: The Nest",
	"The tunnel ends in a cavern hung with webs, its floor littered with egg sacs as big as barrels. Clicking comes from every side. Spiders drop on silk lines, and behind them Ryytaa the Ender unfolds, the brood mother, big as a cart, venom dripping from her fangs. \"Strike her down,\" Vaelric whispers, \"and the brood breaks.\"",
	"Fight"]

const END := [
	["Ryytaa falls", "Part IV: The Nest",
		"The gems blaze so brightly that the nest is lit like noon. When Ryytaa the Ender falls, the egg sacs shrivel, the last spiders flee into the cracks, and the clicking dies. The shield on your arm is dented in the shape of a spider's face. Burr sneezes at the smoke.",
		"Look around"],
	["Chapter I complete", "The Labyrinth of Roots",
		"Beyond the nest, a stair of roots climbs toward a cold, grey light, and below it the labyrinth goes on: a library grown out of the stone, and far past it, a desert. Vaelric is quiet in the axe, but you can feel him listening. The rest of the road waits in the story game, and on the other nineteen boards.",
		"Back to the menu"],
]

# Before the axe, nothing holds you at 1 HP: Burr drags you clear instead.
const LOSE_EARLY := "Burr gets his teeth in your collar and hauls you back into the dark. You catch your breath and go again."
