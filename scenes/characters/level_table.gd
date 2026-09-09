extends RefCounted
class_name LevelTable

## ============================================================================
## LEVEL TABLE  —  the leveling curve (class_name global "LevelTable")
## ============================================================================
## The single, easy-to-edit source of truth for the XP curve. This is NOT an
## autoload — it is a class_name global (like Stats / CharacterBase), so it is
## reachable from anywhere as `LevelTable.something`. RESTART Godot once after
## first adding this file so the editor registers the global.
##
## XP IS ONE CONTINUOUS NUMBER. It never resets on level-up. `CUTOFFS[L]` is the
## TOTAL cumulative XP required to have reached level L:
##       CUTOFFS[1] = 0   (you start here)
##       CUTOFFS[2] = 100 (100 total xp -> level 2)
##       ...
## The "reset to zero" the player sees on the bar is faked: we subtract the
## current level's cutoff from the total (see xp_into_level / progress_fraction).
##
## TO FINE-TUNE: just edit the numbers in CUTOFFS below. Index 0 is unused (kept
## at 0 so the array index lines up with the level number). Keep it sorted
## ascending and keep exactly MAX_LEVEL entries after index 0.
## ----------------------------------------------------------------------------

const MAX_LEVEL := 50

## Skill points granted per level gained (flat).
const SKILL_POINTS_PER_LEVEL := 2

## Attribute points granted when a level-up brings the player TO `level`.
## Variable by level bracket: 2 for 1-10, 3 for 11-20, 4 for 21-30, 5 for 31-40,
## 8 for 41-50. (Level 1 is the start, so this only ever applies to levels 2..50.)
static func attribute_points_for_level(level: int) -> int:
	var l := clampi(level, 1, MAX_LEVEL)
	if l <= 10:
		return 2
	elif l <= 20:
		return 3
	elif l <= 30:
		return 4
	elif l <= 40:
		return 5
	else:
		return 8

## CUTOFFS[level] = total cumulative XP needed to BE that level.
## Index 0 is a dummy; levels run 1..MAX_LEVEL.
##
## THE CURVE (retuned). Roughly geometric: the cost of the NEXT level rises about
## 11-13% per level, from 100 XP for level 2 to 23,200 for level 50, totalling
## 216,000 across the whole game. The per-level step is smooth enough that no
## single level feels like a wall, and the early game moves quickly — levels 2-10
## together cost 1,480, less than one level 30 step.
##
## The right-hand comment on each row is the XP required to leave that level (the
## first difference), which is the number the player actually experiences as "one
## level's worth of bar". Keep the two in sync when retuning: CUTOFFS is the source
## of truth and every helper below derives from it, so editing a cutoff silently
## changes the two spans either side of it.
const CUTOFFS := [
	0,                                                    # [0] unused
	# level:      1     2     3     4     5     6     7      8      9
	0, 100, 210, 335, 475, 635, 810, 1010, 1230,          # steps 100 110 125 140 160 175 200 220 250
	# level:     10    11    12    13    14    15    16    17    18    19
	1480, 1760, 2070, 2420, 2810, 3250, 3740, 4290, 4905, 5595,   # steps 280 310 350 390 440 490 550 615 690 770
	# level:     20    21    22    23     24     25     26     27     28     29
	6365, 7230, 8200, 9300, 10500, 11850, 13400, 15100, 17000, 19150,   # steps 865 970 1100 1200 1350 1550 1700 1900 2150 2400
	# level:      30     31     32     33     34     35     36     37     38     39
	21550, 24250, 27250, 30650, 34450, 38700, 43450, 48750, 54700, 61400,   # steps 2700 3000 3400 3800 4250 4750 5300 5950 6700 7500
	# level:      40     41     42     43     44      45      46      47      48      49
	68900, 77300, 86700, 97200, 109000, 122200, 137000, 153600, 172100, 192800,  # steps 8400 9400 10500 11800 13200 14800 16600 18500 20700 23200
	216000,                                               # level 50 (max)
]


## Total XP required to have reached `level` (clamped into range).
static func cutoff_for_level(level: int) -> int:
	var l := clampi(level, 1, MAX_LEVEL)
	return int(CUTOFFS[l])


## The level a given amount of TOTAL xp corresponds to (capped at MAX_LEVEL).
static func level_for_xp(total_xp: int) -> int:
	var lvl := 1
	for l in range(2, MAX_LEVEL + 1):
		if total_xp >= int(CUTOFFS[l]):
			lvl = l
		else:
			break
	return lvl


## Whether this level is the top of the curve.
static func is_max_level(level: int) -> bool:
	return level >= MAX_LEVEL


## Total XP that lies between this level and the next (the size of this level's
## bar). 0 at max level.
static func xp_span_for_level(level: int) -> int:
	if is_max_level(level):
		return 0
	return cutoff_for_level(level + 1) - cutoff_for_level(level)


## The faked "reset to zero" value: how much of the CURRENT level's bar the
## player has filled, in raw XP. (total_xp - this level's cutoff, clamped.)
static func xp_into_level(total_xp: int, level: int) -> int:
	var into := total_xp - cutoff_for_level(level)
	return maxi(into, 0)


## Progress through the current level as a 0.0..1.0 fraction. Max level = 1.0.
static func progress_fraction(total_xp: int, level: int) -> float:
	var span := xp_span_for_level(level)
	if span <= 0:
		return 1.0
	return clampf(float(xp_into_level(total_xp, level)) / float(span), 0.0, 1.0)


## Progress through the current level as a whole-number percentage (0..100).
static func progress_percent(total_xp: int, level: int) -> int:
	return int(round(progress_fraction(total_xp, level) * 100.0))
