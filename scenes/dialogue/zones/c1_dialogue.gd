extends RefCounted

## ============================================================================
## ZONE c1 — The Arctic — fight dialogue
## ============================================================================
## Keyed by fight id (the "id" in c1.gd's fights() / training_fights()); "c1_" may be
## dropped. Shapes and line keys: see CombatDialogue (scenes/combat/combat_dialogue.gd).
##
##   a bare list of lines           -> plays before the first turn
##   [{"when": ..., "lines": [...]}] -> start | player_turn (+"turn") |
##                                     enemy_hp_below (+"pct", opt "character") |
##                                     unit_defeated (opt "character") | victory
##
## Line keys: speaker ("$player" = the player), text (BBCode ok), character (a
## CharacterRegistry id — fills name/colour/portrait/side), portrait, color, side.
## ----------------------------------------------------------------------------

const FIGHTS := {
	# --- 1 · Wreckage -----------------------------------------------------------
	# PLACEHOLDER lines — replace with the real ones.
	"f1": [
		{"when": "start", "lines": [
			{"speaker": "$player", "text": "Cold. A uniform I don't remember putting on — and I know exactly how to stand against the thing coming at me. I don't know why I know that."},
			{"character": "shambling_corpse", "text": "…"},
		]},
	],

	# --- 2 · The Cabin Line -------------------------------------------------------
	# "f2": [],

	# --- 3 · White Expanse ----------------------------------------------------------
	# "f3": [],

	# --- 4 · The Drift -------------------------------------------------------------
	# "f4": [],

	# --- 5 · The Old Ice (hunters join) ---------------------------------------------
	# "f5": [],

	# --- 6 · The Chaplain -----------------------------------------------------------
	# "f6": [],

	# --- BOSS · The Scavenger -------------------------------------------------------
	# "boss": [
	# 	{"when": "start", "lines": [...]},
	# 	{"when": "enemy_hp_below", "pct": 0.5, "character": "the_scavenger", "lines": [...]},
	# 	{"when": "victory", "lines": [...]},
	# ],
}
