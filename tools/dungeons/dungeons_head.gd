# The dungeons, one per chapter. Created by: Adrian Blackshire and Claude.
# Written by tools/dungeons/gen.py from tools/dungeons/chapters.py: change those and run it again.
#
# A dungeon is a maze of 4 m cells, row 0 at the north:
#   #  wall              .  floor            P  where you come in
#   K  the key           D  a locked door    S  a cracked wall (search it to break through)
#   C  a chest           B  the boss's door  1-9  a fight (walk in and it starts)
#   ,  overgrown floor   ~  a pool (shallow, walkable, looks wet)
# fights maps each digit to a board (scripts/tactics/maps.gd or gen_boards.gd); boss is the last board.
# lines are the banner as each fight opens; theme picks the stone, the plants and the light.
extends RefCounted

