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
const CUTOFFS := [
	0,                                                    # [0] unused
	0, 100, 400, 950, 1800, 3000, 4600, 6650, 9150,       # levels 1..9
	12175, 15725, 19850, 24550, 29875, 35850, 42500, 49850, 57925, 66750,   # 10..19
	76350, 86750, 97950, 110000, 122900, 136675, 151350, 166950, 183500, 201000, # 20..29
	219475, 238950, 259450, 280975, 303550, 327200, 351925, 377775, 404725, 432825, # 30..39
	462075, 492500, 524100, 556900, 590925, 626200, 662725, 700500, 739550, 779900, # 40..49
	821575,                                               # level 50 (max)
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
