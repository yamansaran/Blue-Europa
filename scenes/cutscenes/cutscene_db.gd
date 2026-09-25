extends RefCounted
class_name CutsceneDB

## ============================================================================
## CUTSCENE DB  —  id -> what a cutscene IS
## ============================================================================
## The Diary tells story in two places: dialogue at the head of fights (CombatDialogue)
## and CUTSCENES — after a zone's boss, and at the very start of a new game. This is
## the registry the CutscenePlayer reads. An id that is NOT registered simply plays
## nothing and moves on, which is how the class-select -> zone-1 hand-off already
## calls `opening_<class>` today with no cutscene authored.
##
## TWO SHAPES:
##   {"scene": "res://scenes/cutscenes/<name>.tscn"}
##       a hand-built scene (AnimationPlayer, art, anything). Its ROOT must emit a
##       `finished` signal when it is done; the player awaits it.
##   {"steps": [ ... ]}
##       a data cutscene, played on a plain backdrop. Each step is a Dictionary:
##         {"line": {speaker, text, portrait, color}}          a DialogueBox line
##         {"background": Color | "res://image.png"}           change the backdrop
##         {"wait": 1.5}                                       pause, in seconds
##         {"title": "Northern Greenland, 1941"}               a centred caption
##
## Esc skips any cutscene.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

const CUTSCENES := {
	# Nothing authored yet. Example of the data shape, for when there is:
	# "opening_blue_blood": {"steps": [
	#     {"background": Color(0.02, 0.03, 0.05)},
	#     {"title": "Northern Greenland"},
	#     {"wait": 1.2},
	#     {"line": {"speaker": "Sonny", "text": "…"}},
	# ]},
}

static func has(id: String) -> bool:
	return id != "" and CUTSCENES.has(id)

static func get_cutscene(id: String) -> Dictionary:
	return CUTSCENES.get(id, {})
