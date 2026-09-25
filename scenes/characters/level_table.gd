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
## THE CURVE (rev34: WIDENED to 2,160,000). Geometric: the cost of the NEXT level
## rises ~18.4% per level (k = 1.18433), from 100 XP for level 2 to 336,000 for level
## 50, totalling 2,160,000 across the whole game — 10x the old 216,000.
##
## THE ANCHOR DID NOT MOVE. Level 2 still costs 100 and the opening hours are priced
## exactly as they were; all of the extra weight is at the top. Things that follow,
## and that anything tuned against this table has to respect:
##   - a five-level ZONE band now costs x2.33 the one before it (was x1.76), so band 9
##     is 1,009x band 1 (was 132x);
##   - levels 45-50 are 1,233,000 XP = 57% of the whole curve (was 43%). That headroom
##     is explicitly postgame and wants postgame content, not zone-9 training fights;
##   - grinding decays much harder: farming a cleared zone's tier-3 fight costs 7.2
##     fights for the first level of the next band and 16.8 by +5 levels, i.e. 2.3x to
##     5.3x the 3.2 fights-per-level a player who moves on is paying.
##
## ROUNDING: nearest 5 under 1,000, nearest 50 under 10,000, nearest 500 under 100,000,
## nearest 1,000 above. The rounding residual (-350) is absorbed as seven -50 nudges in
## the 1,000-10,000 band, so every entry is a round number, the table is strictly
## monotone, and level 50 lands on 2,160,000 exactly.
##
## The right-hand comment on each row is the XP required to leave that level (the
## first difference), which is the number the player actually experiences as "one
## level's worth of bar". Keep the two in sync when retuning: CUTOFFS is the source
## of truth and every helper below derives from it, so editing a cutoff silently
## changes the two spans either side of it.
const CUTOFFS := [
	0,                                                    # [0] unused
	# level:        1      2      3      4      5      6      7      8      9
	0, 100, 220, 360, 525, 720, 955, 1230, 1555,
	# steps        100    120    140    165    195    235    275    325    385
	# level:       10     11     12     13     14     15     16     17     18     19
	1940, 2400, 2945, 3590, 4350, 5250, 6300, 7550, 9050, 10800,
	# steps        460    545    645    760    900   1050   1250   1500   1750   2100
	# level:       20     21     22     23     24     25     26     27     28     29
	12900, 15350, 18250, 21700, 25800, 30650, 36450, 43300, 51400, 61000,
	# steps       2450   2900   3450   4100   4850   5800   6850   8100   9600  11500
	# level:       30     31     32     33     34     35     36     37     38     39
	72500, 86000, 102000, 121000, 143500, 170000, 201500, 239000, 283000, 335500,
	# steps      13500  16000  19000  22500  26500  31500  37500  44000  52500  62000
	# level:       40     41     42     43     44     45     46     47     48     49
	397500, 471000, 558000, 661000, 783000, 927000, 1098000, 1300000, 1540000, 1824000,
	# steps      73500  87000 103000 122000 144000 171000 202000 240000 284000 336000
	2160000,                                              # level 50 (max)
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
