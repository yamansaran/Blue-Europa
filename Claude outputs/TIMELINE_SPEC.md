# BLUE-EUROPA :: TURN TIMELINE SPEC (proposed rev30)

STATUS: proposal, not implemented. Supersedes the round loop described in COMBAT_PRIMER C1
("TURN CYCLE") and extends C7 (action points). Approve or amend before implementation.

DECIDED (from the design conversation):
- Real ATB rework — the timeline IS the turn order, not a skin over rounds.
- Interval driven by **alacrity**, with **multipliers defaulting to 1.0** so a boss can be given
  two turns, or an ability can cost less than a full turn.
- "3 turns" on a buff/cooldown means **the bearer's own turns**.

================================================================================
## T1. THE MODEL
================================================================================

A single float `_clock` (units: TICKS) replaces `_round`. Every unit carries `next_turn_at`
(the clock value at which its next turn fires). The engine repeatedly picks the living unit
with the smallest `next_turn_at`, jumps the clock to it, and gives that unit a turn. There is
no round, no player phase, no enemy phase — just a queue of scheduled instants.

A unit's INTERVAL is how many ticks pass between its turns:

```
interval = TICKS_PER_TURN * (ALACRITY_REF + ALACRITY_BASE) / (ALACRITY_REF + alacrity) / turn_rate
         = 100 * 110 / (100 + alacrity) / turn_rate          # with the constants below
```

| const           | value | meaning                                                          |
|-----------------|-------|------------------------------------------------------------------|
| TICKS_PER_TURN  | 100.0 | interval of a default character (alacrity 10, turn_rate 1.0)      |
| ALACRITY_REF    | 100.0 | alacrity that halves the interval, measured from ALACRITY_BASE    |
| ALACRITY_BASE   | 10.0  | Stats.MAJOR_DEFAULTS["alacrity"], so the default lands exactly 100 |
| MIN_INTERVAL    | 10.0  | floor; guards against a runaway alacrity/turn_rate stack           |

Sanity: alacrity 0 → 110. alacrity 10 → 100. alacrity 45 → 75.9. alacrity 120 → 50 (double turns).
Hyperbolic, so speed has automatic diminishing returns and can never reach zero interval.

**`turn_rate` is a NEW hidden base stat, default 1.0** — the "extra multiplier" from the design
call. It DIVIDES the interval, so `turn_rate: 2.0` on an enemy spec is literally "this thing acts
twice as often", and a buff carrying `mods:{"turn_rate": +0.5}` is a haste effect that is
independent of alacrity (which also feeds crit and dodge). Same shape as `action_points` /
`vulnerability`: real stat, spec-overridable, buffable, never shown on the attribute screen.

### Acting for less than a full turn

The existing action-point economy (C7) already models "this ability costs less than a whole
action". It is reused rather than duplicated: **the timeline advance is the fraction of the
unit's AP budget it actually spent.**

```
func _turn_advance(u) -> float:
    var iv := u.turn_interval()
    if u.ap_spent <= AP_EPSILON:
        return iv                                   # a pass, or a lost turn to stun, costs a full turn
    var max_ap := maxf(AP_EPSILON, u.body.get_effective("action_points"))
    return iv * clampf(u.ap_spent / max_ap, MIN_TURN_FRAC, 1.0)     # MIN_TURN_FRAC := 0.1
```

What falls out of that, with no special cases:

- default (action_points 1.0, action_cost 1.0): spend 1.0/1.0 → full interval. **Identical to today.**
- `action_cost: 0.5` ability, used once then End Turn → advances half an interval → acts again
  twice as soon. That is "an attack that uses less than one full turn."
- `action_cost: 0.5` used twice → spends 1.0 → full interval. Two small actions = one turn.
- `action_points: 2.0` boss → acts twice, spends 2.0/2.0 → full interval. "Two attacks per turn."
- `turn_rate: 2.0` boss → normal single action, but half the interval. "Twice as many turns."

The two boss knobs are deliberately distinct: `action_points` = more per turn, `turn_rate` = more
turns. Both default to 1.0 and neither needs code.

### Turn units for buffs, cooldowns, regen

Everything that currently ticks "for all units at the round boundary" ticks **only for the unit
whose turn is starting**. This is almost entirely a deletion — `CombatBuffs.collect_turn_start`,
`tick_cooldowns`, `reset_ap`, `CombatShields.tick_decay` are all already per-body; the `_all`
loops around them go away.

Consequences worth knowing before approving:

- A 3-turn DoT ticks 3 times on the BEARER's schedule. A slow target bleeds over a longer stretch
  of the fight but takes the same total. A fast target burns its own buffs faster — so haste is a
  real tradeoff, not pure upside.
- `spirit_regen` is per own turn, so a fast character regenerates more spirit per fight. Probably
  correct, but it makes alacrity a stealth spirit stat. Flagging it.
- Ability tooltips that say "3 turns" now mean the bearer's turns. Wording unchanged, meaning
  narrowed. No code change; may want a glossary line in Keywords later.

### Haste mid-fight

`HASTE_RESCALES_PENDING := true`. When a unit's interval changes while it is waiting, the
REMAINING wait scales by the same ratio:

```
remaining = next_turn_at - _clock
next_turn_at = _clock + remaining * (new_interval / old_interval)
```

So casting a haste buff visibly slides that unit's next bar closer immediately, rather than only
helping from the turn after next. Each unit caches `_last_interval`; `_sync_intervals()` compares
and rescales, and is called from `_refresh_turn_ui()` (already invoked on every state change) and
after any buff application/expiry. Set the const false to get the "helps next turn" behaviour.

### Initiative at battle start

`next_turn_at = interval` for every unit (not 0). Faster units therefore act first, and the
display is honest from the first frame: the shortest bar is nearest the marker.

### Death and revival

A dead unit is skipped by the actor search and its row draws greyed and empty. Nothing is removed
from `_units`. If a revive ever exists, it re-enters with `next_turn_at = _clock + interval`.

================================================================================
## T2. THE WIDGET  (scenes/combat/turn_timeline.gd — new)
================================================================================

`class_name TurnTimeline extends Control`, one custom `_draw()`, no child nodes.

One ROW per unit: a left gutter with the unit's short name, then a strip of repeating bars. A bar
starts at each clock value `next_turn_at + k*interval`, is `interval` ticks long, and is drawn at

```
x = marker_x + (edge_clock - _display_clock) * PPU
```

so future edges sit right of the marker and travel left as the clock advances. A fixed vertical
marker line runs through every row at `MARKER_FRAC` across the strip, with roughly one third of a
turn of past visible to its left and two and a half turns of future to its right.

```
const ROW_H       := 13.0
const ROW_SEP     := 4.0
const GUTTER      := 62.0     # name column
const STRIP_W     := 300.0    # ≈ 260 ticks visible at PPU 1.15
const PPU         := 1.15     # pixels per tick
const MARKER_FRAC := 0.30
const SEG_GAP     := 3.0      # pixel gap between consecutive bars
const CAP_W       := 3.0      # bright leading-edge cap
const SCROLL_TIME := 0.30     # seconds for one advance animation
```

- Bar colour: `u.body.model_color()` (the same tint as the unit's model and health bar), with the
  leading edge capped in `col.lightened(0.5)` so the trigger point is unmistakable.
- Party rows first, enemy rows below, separated by a hairline; enemy rows get a faintly red row
  background so sides read at a glance.
- The ACTIVE unit's row gets a brighter background band.
- `clip_contents = true`; the segment entering from the left is drawn clipped, not omitted, so the
  motion reads as continuous.
- Intervals are recomputed from the live stat on every redraw, so a haste buff visibly SHORTENS
  the bars in place.

**Animation.** `scroll_to(clock)` tweens `_display_clock` over `SCROLL_TIME` (or
`min(SCROLL_TIME, dt/TICKS_PER_TURN * SCROLL_TIME)` for short hops) and returns the tween's
`finished` signal; combat awaits it before starting the next turn. The acting unit's
`next_turn_at` is rewritten at the START of that scroll, so its row's re-layout is hidden inside
the motion instead of snapping.

**Placement.** The health-bar band (TOP_FRAC 0.15) is already full. Rather than reflow the bands,
the timeline anchors top-LEFT inside `_battle_panel` at offset (18, 8) with a translucent dark
backing — it reads as sitting directly under the party health bars, costs no layout change to the
battle band, and `mouse_filter = IGNORE` so it never eats a click meant for a unit. If you would
rather it be inside the top panel, that means TOP_FRAC 0.15 → ~0.24 and MID_FRAC 0.70 → ~0.61,
which moves every unit on screen; say so and I'll do it that way instead.

The `Turn N` label in the bottom-right is retired. If a round number is still wanted for flavour,
`int(_clock / TICKS_PER_TURN) + 1` is a reasonable "round equivalent".

================================================================================
## T3. FILE-BY-FILE CHANGES
================================================================================

**1. `scenes/combat/combat_timeline.gd` — NEW.** `class_name CombatTimeline extends RefCounted`,
static-only, sibling of CombatMath/CombatCrit. Holds the four constants and
`static func interval(alacrity: float, turn_rate: float) -> float`. One place to retune speed.

**2. `scenes/combat/turn_timeline.gd` — NEW.** The widget above, ~180 lines.

**3. `scenes/characters/stats.gd`.** Add `const TURN_RATE_DEFAULT := 1.0` beside
ACTION_POINTS_DEFAULT with the same doc-comment shape, and `d["turn_rate"] = TURN_RATE_DEFAULT`
in `default_base_stats()`. Not a major, so it stays off the attribute screen automatically.
Optionally add a field to DebugStatPanel for testing.

**4. `scenes/combat/battle_character.gd`.** Four additions:
- `var next_turn_at: float = 0.0`
- `var ap_spent: float = 0.0`   (reset in `reset_ap()`)
- `var turns_taken: int = 0`
- `func turn_interval() -> float` → `CombatTimeline.interval(body.get_effective("alacrity"),
  body.get_effective("turn_rate"))`, plus the cached `_last_interval` for haste rescaling.

`tick_cooldowns()`, `start_cooldown()`, `reset_ap()` are unchanged — they were already per-unit,
they just get called at a different moment.

**5. `scenes/combat/combat.gd`** — the real work, ~150 lines changed.

*Removed:* `_round`, `_turn_label`, `_process_turn_start_all`, `_tick_cooldowns_all`,
`_reset_ap_all`, and the enemy-loop body of `end_player_turn`.

*Added:*
```
var _clock: float = 0.0
var _active: BattleCharacter = null
var _timeline: TurnTimeline = null
const MIN_TURN_FRAC := 0.1
const ENEMY_THINK_DELAY := 0.35

_start_battle()            # _clock = 0; every unit next_turn_at = its interval; _advance_to_next_turn()
_next_actor()              # min next_turn_at among the living; ties break on higher alacrity, then spawn order
_advance_to_next_turn()    # jump the clock, await _timeline.scroll_to(), _begin_unit_turn()
_begin_unit_turn(u)        # turns_taken++, _process_turn_start(u), u.tick_cooldowns(), u.reset_ap(),
                           # victory/defeat check, then: stunned -> end immediately;
                           # player -> Phase.PLAYER and wait for input; else -> _take_ai_turn(u), end
end_unit_turn(u)           # u.next_turn_at = _clock + _turn_advance(u); _advance_to_next_turn()
_process_turn_start(u)     # today's _process_turn_start_all loop body, for ONE unit
_turn_advance(u)           # the AP-fraction formula in T1
_sync_intervals()          # haste rescaling
```

*Changed:* `end_player_turn()` becomes a thin guard that calls `end_unit_turn(_player)`, so the
End Turn button and its `disabled` logic keep working. In `_use_ability`, `caster.ap_spent +=
ability.action_cost` is recorded beside the existing AP debit, and the auto-end-turn at the bottom
stops being player-only — it fires for `caster == _active`, so an enemy that spends its budget
also ends its turn (its routine simply stops being asked).

**6. `claude/COMBAT_PRIMER.md`** — rev30. Rewrite C1's TURN CYCLE paragraph, extend C7 with the
timeline-advance rule, add a C9 for the timeline itself, and close open thread C4.10 (enemy
pacing), which this fixes for free: each enemy acts on its own scheduled instant with a scroll
animation and a short delay between, instead of the whole enemy phase landing in one frame.

================================================================================
## T4. WHAT THIS DOES *NOT* CHANGE
================================================================================

`_use_ability` and everything under it — damage, shields, buffs, Disdain, Shatter, dodge, the
wheel, targeting, `_use_blocked` — are untouched. rev29 already made the resolve path
caster-agnostic; this changes only WHO is asked to act and WHEN. Enemy AI (open thread C4.1) stays
unwritten: enemies will now receive real, individually-scheduled turns and still do nothing in
them. That is the natural next piece of work once this lands.

================================================================================
## T5. OPEN QUESTIONS FOR YOU
================================================================================

1. **Placement** — overlay at the top-left of the battle band (no layout change, recommended), or
   grow the top panel and put it under the health bars properly (moves every unit on screen)?
2. **Enemy rows** — show enemy bars at all? Seeing exactly when the boss acts is the best part of
   this display, but it is also a large information gift. Alternative: show enemy rows without the
   gutter name until the unit has acted once.
3. **`MIN_TURN_FRAC 0.1`** — is a 0.1-cost ability allowed to give ten actions per interval, or
   should the floor be higher (0.25)?
4. **Spirit regen** — leave it per own turn (fast characters regen more per fight), or divide it
   by the interval ratio so total regen per tick is speed-neutral?
