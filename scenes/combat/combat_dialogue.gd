extends RefCounted
class_name CombatDialogue

## ============================================================================
## COMBAT DIALOGUE  —  which lines play when, in a fight
## ============================================================================
## The story is told in two places (the Diary's rule): dialogue at the head of a
## fight (and sometimes during it), and cutscenes after zones. This is the first.
##
## WHERE IT IS WRITTEN: one file per zone, scenes/dialogue/zones/<zone>_dialogue.gd,
## keyed by fight id (DialogueDB). GameManager._stage_fight copies it into
## BattleState.dialogue (an inline "dialogue" key on a fight spec still works as a
## fallback). Two accepted shapes:
##
##   1) a plain list of LINES  -> all of it plays at the start of the fight
##        "dialogue": [ {"speaker": "Sonny", "text": "..."}, ... ]
##
##   2) a list of TRIGGERS, each with "when" + "lines"
##        "dialogue": [
##          {"when": "start", "lines": [...]},
##          {"when": "player_turn", "turn": 3, "lines": [...]},     # the player's 3rd turn
##          {"when": "enemy_hp_below", "pct": 0.5, "character": "the_scavenger", "lines": [...]},
##          {"when": "unit_defeated", "character": "strapped_passenger", "lines": [...]},
##          {"when": "victory", "lines": [...]},
##        ]
##      "character" is a CharacterRegistry id (or a unit's display name); omit it on
##      enemy_hp_below / unit_defeated to mean "any enemy". Every trigger fires ONCE.
##
## A LINE is what DialogueBox.show_line takes (speaker / text / portrait / color),
## plus two keys resolved here:
##   "side"       "left" | "right". Omitted -> the speaking unit's side (party = left,
##                enemies = right), and "left" if the speaker is not on the field.
##   "character"  a CharacterRegistry id: fills in speaker name, colour and portrait
##                from that unit when the line does not set them.
##   "speaker": "$player" is replaced by the player's name.
##
## TIMING. Triggers are checked only at SAFE POINTS — before the fight's first turn,
## and between one unit's turn and the next (combat._run_turn_loop). Never in the
## middle of resolving an ability, so a line can't interrupt half a Shatter.
## ----------------------------------------------------------------------------

var _triggers: Array = []
var _fired: Dictionary = {}

static func from_config(cfg) -> CombatDialogue:
	var d := CombatDialogue.new()
	if typeof(cfg) != TYPE_ARRAY or (cfg as Array).is_empty():
		return d
	var arr: Array = cfg
	# Shape 1: a bare list of lines (no "when" anywhere) = the opening exchange.
	var is_lines := true
	for item in arr:
		if typeof(item) == TYPE_DICTIONARY and (item as Dictionary).has("when"):
			is_lines = false
			break
	if is_lines:
		d._triggers.append({"when": "start", "lines": arr.duplicate(true)})
		return d
	for item in arr:
		if typeof(item) == TYPE_DICTIONARY and (item as Dictionary).has("lines"):
			d._triggers.append((item as Dictionary).duplicate(true))
	return d

func is_empty() -> bool:
	return _triggers.is_empty()

## Lines for the first unfired trigger matching `when` that `check` accepts.
## `check` is a Callable(trigger: Dictionary) -> bool. Marks it fired.
func take(when: String, check: Callable = Callable()) -> Array:
	for i in _triggers.size():
		if _fired.has(i):
			continue
		var t: Dictionary = _triggers[i]
		if str(t.get("when", "")) != when:
			continue
		if check.is_valid() and not bool(check.call(t)):
			continue
		_fired[i] = true
		var lines = t.get("lines", [])
		return lines if typeof(lines) == TYPE_ARRAY else []
	return []

## Every unfired trigger of a kind (used to test several conditions in one sweep).
func pending(when: String) -> Array:
	var out: Array = []
	for i in _triggers.size():
		if not _fired.has(i) and str((_triggers[i] as Dictionary).get("when", "")) == when:
			out.append(_triggers[i])
	return out
