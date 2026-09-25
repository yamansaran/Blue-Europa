extends RefCounted

## ============================================================================
## ZONE c2b — Godthaab — fight dialogue
## ============================================================================
## Keyed by fight id (the "id" in c2b.gd's fights()); the "c2b_" prefix may be
## dropped. Shapes and line keys: see CombatDialogue (scenes/combat/combat_dialogue.gd).
##
##   a bare list of lines           -> plays before the first turn
##   [{"when": ..., "lines": [...]}] -> start | player_turn (+"turn") |
##                                     enemy_hp_below (+"pct", opt "character") |
##                                     unit_defeated (opt "character") | victory
##
## Line keys: speaker ("$player" = the player), text (BBCode ok), character (a
## CharacterRegistry id — fills name/colour/portrait/side), portrait, color, side.
##
## THE ZONE, IN ONE LINE: the same organisation, twice, six fights apart. Godthaab
## is not held by monsters — it is held by people doing paperwork about a plague,
## and the corpses in the back rooms are what the paperwork is about. Nobody here
## thinks they are the villain, and the dialogue never lets them say otherwise.
## ----------------------------------------------------------------------------

const FIGHTS := {
	# --- 1 · The Quarantine Pier ----------------------------------------------
	# Establish the register: they are not hostile, they are ON DUTY.
	"f1": [
		{"when": "start", "lines": [
			{"character": "wharfinger", "text": "Pier's closed. Harbour order, not mine."},
			{"speaker": "$player", "text": "I came off the ice."},
			{"character": "wharfinger", "text": "Then you came off the ice into a closed pier. [i]Lads.[/i]"},
		]},
		{"when": "victory", "lines": [
			{"character": "wharfinger", "text": "…should have let you through. Wasn't my call to make either way."},
		]},
	],

	# --- 2 · The Processing Line ----------------------------------------------
	"f2": [
		{"when": "start", "lines": [
			{"character": "security_guard", "text": "You're not on the list. Everyone coming off the ice is on the list."},
			{"speaker": "$player", "text": "Then the list is wrong."},
			{"character": "security_guard", "text": "The list is never wrong. That's rather the point of it."},
		]},
	],

	# --- 3 · The Registrar -----------------------------------------------------
	# THE FIGHT THAT TEACHES BACK-ROW PROTECTION. The dialogue states the shape of
	# it once, at the start, and then shuts up — the seating is doing the teaching.
	"f3": [
		{"when": "start", "lines": [
			{"character": "registrar", "text": "I don't want any trouble and I don't intend to be in any. Gentlemen, if you would — stand in front of me."},
			{"speaker": "$player", "text": "That's it? You hide?"},
			{"character": "registrar", "text": "I file. It is remarkably similar and it has kept me alive rather longer."},
		]},
		# Fires the first time the player gets THROUGH the line — the moment the
		# lesson lands, rather than at a fixed turn.
		{"when": "enemy_hp_below", "pct": 0.5, "character": "registrar", "lines": [
			{"character": "registrar", "text": "[i]No — no, close it up, close the line up —[/i]"},
		]},
		{"when": "victory", "lines": [
			{"speaker": "$player", "text": "Three men in front of one clerk."},
			{"speaker": "$player", "text": "Whatever he was writing down, somebody wanted it finished."},
		]},
	],

	# --- 4 · The Back Rooms ----------------------------------------------------
	# The turn. Up to here Godthaab has been an argument about paperwork.
	"f4": [
		{"when": "start", "lines": [
			{"speaker": "$player", "text": "This is behind the registry. This is where they were filing them."},
			{"character": "screaming_corpse", "text": "[i]—[/i]"},
		]},
		{"when": "unit_defeated", "character": "screaming_corpse", "lines": [
			{"speaker": "$player", "text": "It didn't stop when it died the first time. That's the part nobody wrote down."},
		]},
	],

	# --- 5 · Deeper In ---------------------------------------------------------
	# Six of them, seated 3 by 3 — the fight that teaches the rule one fight AFTER
	# fight 3 stated it. No dialogue mid-fight; the room is the line.
	"f5": [
		{"when": "start", "lines": [
			{"speaker": "$player", "text": "Six. In rows."},
			{"speaker": "$player", "text": "Somebody stood them in rows."},
		]},
	],

	# --- MINIBOSS · The Burning Ground -----------------------------------------
	# Their answer to the back rooms, and the first sign the organisation knows
	# exactly what it has.
	"mini": [
		{"when": "start", "lines": [
			{"speaker": "$player", "text": "They burned them. They burned them and it [i]didn't work[/i]."},
			{"character": "burning_hulk", "text": "[i]…[/i]"},
		]},
		{"when": "victory", "lines": [
			{"speaker": "$player", "text": "Still warm. Whoever lit this was here this morning."},
		]},
	],

	# --- 6 · The Sanitation Corps ----------------------------------------------
	# The same organisation as the wharf, better trained — and it says so itself.
	"f6": [
		{"when": "start", "lines": [
			{"character": "sanitation_engineer", "text": "Sanitation. Stand still, please — this is a controlled area."},
			{"speaker": "$player", "text": "Controlled."},
			{"character": "sanitation_engineer", "text": "It is now. That took a great deal of work and I'd rather not repeat it."},
		]},
	],

	# --- 7 · The Cordon --------------------------------------------------------
	# The zone's hardest non-boss fight. The net and the shield get named out loud,
	# once, because both are mechanics the player has not met before.
	"f7": [
		{"when": "start", "lines": [
			{"character": "sanitation_officer_net", "text": "Net him. Don't damage him — the Chief wants whatever came off the ice intact."},
			{"character": "sanitation_officer_shield", "text": "Behind me. All of you, behind me."},
		]},
		{"when": "unit_defeated", "character": "sanitation_officer_shield", "lines": [
			{"character": "sanitation_officer_net", "text": "[i]He's down — he's down, you're all in the open —[/i]"},
		]},
	],

	# --- 8 · The Harbour Gate --------------------------------------------------
	# THE FIRST FIGHT THE PLAYER CAN WIN BY SURVIVING. The dialogue says what the
	# chip badges are already showing, once, and then lets the clock speak.
	"f8": [
		{"when": "start", "lines": [
			{"character": "harbour_guard", "text": "Gate holds. Whatever it takes, the gate holds."},
			{"speaker": "$player", "text": "You've all taken something."},
			{"character": "harbour_guard", "text": "Issued. It's issued. Six hours a dose and we've been on eleven."},
		]},
		{"when": "victory", "lines": [
			{"speaker": "$player", "text": "They didn't lose. They ran out."},
		]},
	],

	# --- BOSS · The Chief of the Detail ----------------------------------------
	# >> THE CHIEF'S KIT IS THE DEV'S TO WRITE (GODTHAAB §2.5), so his fight is
	#    deliberately left with ONLY an opening beat — anything more would be
	#    writing the fight's shape on his behalf. The escort's Amphetamines already
	#    gives it a six-turn rhythm whatever he turns out to do.
	"boss": [
		{"when": "start", "lines": [
			{"character": "chief_of_the_detail", "text": "You're the one off the ice. I've read three pages about you and not one of them says what you are."},
			{"speaker": "$player", "text": "Neither do I."},
			{"character": "chief_of_the_detail", "text": "No. I didn't think you would."},
		]},
		# {"when": "enemy_hp_below", "pct": 0.5, "character": "chief_of_the_detail", "lines": [...]},
		# {"when": "victory", "lines": [...]},
	],
}
