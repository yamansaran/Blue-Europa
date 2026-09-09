This is the ENEMY AI making-primer for the Blue Europa Godot project. Load it when the task is to
BUILD, EXTEND or TUNE the unit AI — the thing that decides what a non-player combatant does on its
turn. It is a DESIGN doc first (nothing below is implemented yet) and becomes the reference once it
is. This is a MAP — pasted code = ground truth and overrides this doc; request the real script (or
just the relevant function) for real work.

# BLUE-EUROPA :: AI PRIMER  (DESIGN — NOT YET IMPLEMENTED)
LAST_UPDATED: 2026-09-03 (rev3 — THE AUXILIARY SIGNALS + SIGNATURE-AND-TEXTURE. Eight new signals
(softness, reputation, cooldown_load, is_female / is_child, spirit_need, party_depletion) and the
composition rule they exist for: an archetype is ONE big gain plus three-to-five small ones (§4.6).
Adds the persisted `damage_rating` stat and its recording hook, the `figure` identity field, and
three new archetypes. THE THREE OPEN QUESTIONS ARE ANSWERED: DEFENSE reads the actor's OWN danger,
AI allies ARE omniscient, and the Phase-5 magnitude pass is GREEN-LIT — so severity and offer
strength are the real model, not a fallback. Two auxiliaries need mechanics that do not exist yet
(cooldown extension, summoning) and are specced in §19.
rev2 — THE GAIN CURVE. Every bias is `× pow(gain, signal)` instead of a linear `× (1 + k·signal)`,
which is what lets a tuning number produce a 15x swing instead of a 2x one; neutral for every gain
stat is 1.0, NOT 0.0. Plus OFFER STRENGTH, the `ai_smart` gate, cooldown-aware viability, OFFENSE cut
to three terms on purpose, the ARCHETYPE CATALOGUE, and tuning-by-dynamic-range.
rev1 was the initial three-layer design.)
PURPOSE: give a unit a decision it can make every turn, in a shape that survives 200 abilities and
40 creature types without being rewritten. It answers ONE question — "what does this unit do now?" —
and hands the answer to the seam combat already exposes.

STATUS OF THE ENGINE UNDER IT: DONE. COMBAT_PRIMER rev29 made the whole resolve path
caster-agnostic. Any unit already carries its own `loadout`, `ability_ranks`, `ap` and `cooldowns`;
`_use_ability(caster, ability, target, slot)` resolves for anyone; `_use_blocked` / `_can_use` and
`_valid_target` are already written from the caster's seat. `_take_ai_turn(u)` prints and passes.
**The deciding is the only thing missing, and this document is that decision.**

>> READ ALSO, only if needed: COMBAT_PRIMER (the seam, the AP economy, the damage pipeline),
   BUFF_PRIMER (`magnitude` / `weight`, which this design finally consumes),
   CHARACTER_PRIMER (`ai`, `abilities`, `ability_ranks`, `base_stats` overrides — where a creature's
   personality is authored), ABILITY_PRIMER (the field set the ability layer reads).

>> SECTION MAP
   §1  the model            §2  files            §3  the seam         §4  THE GAIN CURVE
   §5  stat vocabulary      §6  signals          §7  layer 1 intent   §8  layer 2 target
   §9  layer 3 ability      §10 severity+offer   §11 the estimator    §12 the ai_smart gate
   §13 ARCHETYPE CATALOGUE  §14 allies+future    §15 the pick+tuning  §16 the runner
   §17 worked examples      §18 build order      §19 open threads
   §4.6 SIGNATURE + TEXTURE — how big each gain in an archetype should be. Read it before §13.
   §6.8 THE AUXILIARY SIGNALS — the small terms that give an archetype texture (rev3).


================================================================================
## 1. THE 60-SECOND MODEL
================================================================================
Every turn, for every living non-player unit, three layers run in order. Each layer narrows the
decision and hands a smaller question to the next.

    ┌─ LAYER 1 · INTENT ────────────────────────────────────────────────────┐
    │  Which of four things do I want to do?                                 │
    │  OFFENSE (hurt them) / DEFENSE (protect me) / BUFF (help us) /         │
    │  DEBUFF (weaken them)                                                  │
    │  4 hidden per-character weights x 100, each multiplied by a small       │
    │  product of GAIN TERMS, non-viable intents zeroed, weighted pick.      │
    └────────────────────────────────┬───────────────────────────────────────┘
                                     v
    ┌─ LAYER 2 · TARGET ────────────────────────────────────────────────────┐
    │  Which unit?  Every candidate's MAGNETISM stat is COPIED, then bent    │
    │  by the intent's gain terms — an assassin multiplies a half-dead       │
    │  target by 6.3x and a quarter-dead one by 15.9x — then a weighted      │
    │  random pick over the bent values.                                     │
    │  DEFENSE short-circuits: the target is always the unit itself.         │
    └────────────────────────────────┬───────────────────────────────────────┘
                                     v
    ┌─ LAYER 3 · ABILITY ───────────────────────────────────────────────────┐
    │  Which ability, from the set this intent can use, against that target? │
    │  Filtered by _can_use + _valid_target, scored per intent, weighted pick│
    └────────────────────────────────┬───────────────────────────────────────┘
                                     v
              combat._use_ability(unit, ability, target, slot)

Then: if the unit still has action points and a legal move, **the whole pipeline runs again** from
Layer 1 with the new battlefield state. A two-action boss re-decides; it does not repeat.

SIX PROPERTIES THE DESIGN IS BUILT AROUND:
1. **Weighted, not greedy.** Every layer picks by roulette over positive scores, never argmax. A
   unit with a strong preference still occasionally does the other thing, which is what makes a
   fight feel alive. `ai_decisiveness` / `ai_focus` sharpen or flatten that at will (§15.2), so
   argmax IS available — as an extreme setting, not a second code path.
2. **BIG dynamic range.** Small weight variance reads as random; large variance reads as
   intentional. Every bias is exponential (§4), so a single tuning number can move a weight by 15x
   or 40x, and the pick lands on the right target *far* more often than not. Half the tuning work is
   deciding how big a swing an idea deserves — §15.3 is the table for that.
3. **The personality is stats.** Every tunable number is a hidden base stat, so it is per-character
   overridable from a module or a fight spec, and **buffable** — a taunt is
   `mods:{magnetism:+300}`, a berserk is `mods:{ai_intent_offense:+0.4}`, a daze that makes a boss
   stop reading your Magnificence is `mods:{ai_smart:-1.0}`. No new mechanism.
4. **One source of truth for the math.** The AI never re-implements damage. It calls a non-rolling
   twin of `CombatMath.resolve` (§11), so the AI's idea of a hit and the actual hit can never drift.
5. **Nothing in combat.gd changes but one line.** `_take_ai_turn` becomes `await AITurn.run(self, u)`.
6. **Every layer degrades to "attack something".** A total failure at any layer falls through the
   ladder in §16.5 and ends at "hit the highest-magnetism enemy", then "pass".


================================================================================
## 2. WHERE IT LIVES  (new files — all RefCounted, static-only, `class_name` globals)
================================================================================
Same convention as CombatMath / CombatBuffs / CombatShields: no autoload, no scene, no state.

    scenes/combat/ai/
      ai_turn.gd      AITurn      THE RUNNER. One unit's whole turn: the action loop, the
                                  fallback ladder, the pacing awaits, the debug log.
      ai_context.gd   AIContext   A per-DECISION snapshot of the battlefield handed to every
                                  layer: the acting unit, its allies, its hostiles, its usable
                                  (ability, slot) pairs, the built-buff cache and the estimate
                                  cache. Built ONCE per action, thrown away after.
      ai_signals.gd   AISignals   The normalized readings every layer scores from. EVERY signal
                                  returns 0..1 and 0 ALWAYS means "this term does nothing". §6.
      ai_gain.gd      AIGain      The one bias primitive: apply_gain / clamp / the debug ledger. §4.
      ai_intent.gd    AIIntent    LAYER 1. Scores the four intents, applies viability, picks. §7.
      ai_target.gd    AITarget    LAYER 2. Magnetism copy + gain terms + pick. §8.
      ai_ability.gd   AIAbility   LAYER 3. Intent -> ability set, scoring, pick. §9.
      ai_rules.gd     AIRules     The ARCHETYPE CATALOGUE (§13): which signals wire to which gain
                                  stat, per `ai` id, plus the stat-block preset for each.
      ai_estimate.gd  AIEstimate  Dry-run damage / effective-HP / offer-value helpers. §11.
      ai_pick.gd      AIPick      The weighted roulette + the AI's RNG. §15.

    scenes/combat/combat.gd        ONE line changes (`_take_ai_turn`).
    scenes/combat/combat_math.gd   gains `preview()` — a non-rolling `resolve()`. §11.1.
    scenes/characters/stats.gd     gains the hidden AI stats + their defaults. §5.
    scenes/abilities/ability.gd    gains 2 optional AI-hint exports. §9.4.

WHY SO MANY FILES. Because the layers are independently tunable and independently testable, and
because a 900-line `ai.gd` is exactly the thing that gets rewritten at ability #60. Each file has one
job and a small public surface; a new behaviour is a new function in ONE of them.

EDITOR STEPS: none per file beyond the usual — these are `class_name` globals, so restart Godot once
after adding them. No autoload to register. No .tres. No SAVE_VERSION bump (§5 explains why).


================================================================================
## 3. THE SEAM  (what already exists — do not rebuild any of this)
================================================================================
Everything below is live code in combat.gd today. The AI is a CLIENT of it.

  _use_ability(caster, ability, tgt, slot)  resolves for ANY caster: reads the caster's stats,
        rank (`_ability_rank`), spirit, AP and slot cooldown; threads the caster as the damage
        source so on-struck riders fire; applies buffs with the caster's Disdain roll.
  _use_blocked(caster, ability, slot) -> String   the SINGLE gate. "" = legal. §7.1 lists every
        check it makes. **The AI filters with this and with nothing else** — if it ever disagrees
        with the click handler, that is a bug in the gate, not in the AI.
  _valid_target(caster, ability, tgt)  targeting relative TO THE CASTER. Target.ENEMY = hostile
        to the caster, so an enemy's attack legally targets the party.
  _is_hostile(a, b)  sides. TEAM_PLAYER + TEAM_ALLY are one side; TEAM_ENEMY is the other.
  u.loadout        the unit's ability ids in SLOT order, snapshotted at spawn. THE INDEX IS THE
                   SLOT, and cooldowns key by it. The AI must carry the index around with the
                   ability, never re-derive it.
  u.ap / u.reset_ap() / u.cooldowns / u.on_cooldown(slot) / u.cooldown_left(slot)
  u.body.ability_ranks   id -> rank; `_ability_rank` reads it for non-player casters.
  CombatBuffs.is_stunned / is_silenced / count_debuffs_of_element / visible_entries
  CombatMath.resolve / resolve_flat        the damage pipeline (§11).
  CombatResist.resist_chance(caster, target, entry)   the Magnificence-vs-Disdain roll (§12).
  CombatDodge.chance(attacker, defender, ability)     the alacrity/accuracy roll (§12).
  CombatShields.total(body)     shields sit on TOP of health; the AI must count them (§6.2).
  BuffLibrary.build(id, caster, target)   builds an entry WITHOUT applying it — the AI reads
        `magnitude` / `weight` off the result to price an offer (§10.2).

CONSTRAINTS THE SEAM IMPOSES ON THE AI — read these twice:
  - **Slot indices matter.** `_use_ability(..., slot)` starts the cooldown on THAT slot. Passing -1
    means the ability never cools down. The AI must always pass the real index.
  - **`_use_ability` can end the fight** (`_check_victory` / `_check_defeat` run inside it) and the
    caller must re-check `_battle_over` after EVERY call, including between actions of the same
    unit's multi-action turn.
  - **`action_cost` can be 0.0** (ZAP!). An AI action loop that only stops when AP runs out will
    spin forever on a free, cooldown-free ability. §16.3 caps it.
  - **The player's auto-end-turn does not apply.** `_use_ability` only auto-ends the turn when
    `caster == _player`. A non-player unit simply stops being able to act; its routine must stop
    asking. That is the AI's job, not combat's.
  - **Everything the AI reads is live.** There is no fog of war and no memory between turns. If
    "the enemy remembers you healed" is ever wanted, it needs its own store (§19.6).


================================================================================
## 4. THE GAIN CURVE  (the single primitive every bias in the design uses)
================================================================================
### 4.1 THE PROBLEM WITH LINEAR BIAS
rev1 bent a weight with `× (1 + k·signal)`. To make a half-dead target 7x more attractive that needs
`k = 12`, and at that k a *slightly* hurt target (signal 0.1) is already 2.2x more attractive — the
curve is steepest exactly where you want it flattest, and the numbers you type stop meaning anything
you can picture. Worse, a repulsion needs a second code path (an `invert` flag) because `1 + k·s`
goes negative.

### 4.2 THE FIX — one exponential, one clamp
    AIGain.apply(value: float, gain: float, signal: float) -> float:
        var g := clampf(gain, MIN_GAIN, MAX_GAIN)        # 0.02 .. 200.0
        var s := clampf(signal, 0.0, 1.0)
        return value * pow(g, s)

    THE WHOLE CONTRACT:
      gain == 1.0   the term does NOTHING, at any signal.        pow(1, s) == 1
      gain  > 1.0   ATTRACTION, rising to exactly `gain` at s=1.
      gain  < 1.0   REPULSION,  falling to exactly `gain` at s=1.
      signal == 0   the term does NOTHING, at any gain.          pow(g, 0) == 1
    So a gain stat reads in plain language: **`ai_bloodlust = 40` means "up to 40x more attractive
    at full signal"**, and `ai_caution = 0.15` means "down to 0.15x against the scariest thing on the
    board". No invert flag. No sign juggling. Never negative, never zero, always composable.

### 4.3 WHAT EACH GAIN ACTUALLY BUYS  (the tuning table — keep this open while tuning)

    gain  | s=0.25   s=0.50   s=0.75   s=1.00   reads as
    ------+----------------------------------------------------------------------
    0.10  |  0.56     0.32     0.18     0.10    near-total avoidance
    0.15  |  0.62     0.39     0.24     0.15    strong avoidance
    0.25  |  0.71     0.50     0.35     0.25    clear avoidance (the tidiness default)
    0.50  |  0.84     0.71     0.59     0.50    mild avoidance
    0.60  |  0.88     0.77     0.68     0.60    a nudge away (the shield default)
    1.00  |  1.00     1.00     1.00     1.00    OFF
    1.50  |  1.11     1.22     1.36     1.50    a nudge toward
    2.00  |  1.19     1.41     1.68     2.00    mild preference
    4.00  |  1.41     2.00     2.83     4.00    clear preference
    8.00  |  1.68     2.83     4.76     8.00    strong preference
    12.0  |  1.86     3.46     6.45    12.00    dominant
    15.0  |  1.97     3.87     7.62    15.00    dominant
    25.0  |  2.24     5.00    11.18    25.00    near-decisive
    40.0  |  2.51     6.32    15.91    40.00    obsessive
    100   |  3.16    10.00    31.62   100.00    single-minded

    THE DESIGN BRIEF'S OWN NUMBER, DERIVED: an assassin should find a half-health target 6-8x more
    magnetic and a quarter-health one about 15x. With `missing_hp` as the signal, half health is
    s=0.50 and quarter health is s=0.75, so:
        ai_bloodlust = 40  ->  40^0.50 = 6.32x   and   40^0.75 = 15.91x
    That is the spec, hit exactly, by one number. This is why the whole design is on this curve.

### 4.4 THE FOOTGUN — neutral is 1.0, NOT 0.0
Every OTHER coefficient in this codebase is neutral at 0 (a buff's `mods`, a `damage_taken_mult`).
A gain stat is neutral at **1.0**, and a gain left at 0.0 clamps to MIN_GAIN and becomes a 50x
*repulsion* — a silent, extremely confusing bug.
    MITIGATIONS, all three:
      1. Every gain stat's DEFAULT in `Stats.default_base_stats()` is 1.0 unless it is deliberately
         biased (the table in §5 marks every non-1.0 default).
      2. `AIRules.validate()` runs once at combat start under `GameManager.is_debug()` and
         `push_warning`s on any gain stat sitting at exactly 0.0 on any unit.
      3. Naming: gain stats never share a name shape with additive stats. Everything additive in the
         AI vocabulary is an `ai_intent_*` weight; everything else is a gain.
    NB a BUFF that moves a gain still works normally: `mods:{ai_bloodlust:+20}` on a 40 base gives
    60 (obsessive), and `mult:{ai_bloodlust:-0.5}` halves it to 20. Just never author a buff that
    lands a gain on zero.

### 4.5 COMPOSING TERMS
A layer's multiplier is the PRODUCT of its terms, each applied through `AIGain.apply`. Products of
exponentials are exponentials, so the terms compose cleanly and the order never matters:
    m = base × g1^s1 × g2^s2 × g3^s3 ...
Two consequences worth knowing:
  - Terms MULTIPLY, so three 4x terms is 64x, not 12x. Three moderate preferences add up to an
    obsession. When something feels over-tuned, look for a stack of terms rather than one big gain.
  - The pick's exponent (§15.2) rides on top of the whole product, so `ai_focus 2.5` turns an
    effective 15.9x into 15.9^2.5 = 1006x. **Gains and the exponent compound in log space.** Tune
    one at a time.

### 4.6 SIGNATURE AND TEXTURE  (the composition rule — read this before authoring an archetype)
An archetype is **one big gain plus three to five small ones.** Not one gain, and not eight equal
ones. The two failure modes it sits between:

    ONE GAIN ONLY        the unit is a rule with a name. An assassin that reads nothing but
                         missing_hp will walk past a lethal, undefended target to poke the one
                         with slightly less health, forever, identically. Legible; lifeless.
    MANY EQUAL GAINS     nothing reads as a decision. Six 3x terms produce a 729x spread with no
                         discernible reason behind it — the unit looks like it is rolling dice in
                         a complicated way, which is the exact feeling §4 exists to avoid.

    THE PATTERN:
      SIGNATURE  ONE gain in the 12-40 band, on the signal that IS the archetype.
                 It should be visible in a single turn: "oh, it goes for the hurt one."
      TEXTURE    THREE to FIVE gains in the 1.5-4 band, on auxiliary signals (§6.8).
                 They never overturn the signature; they BREAK TIES underneath it, which is
                 what makes the same archetype behave differently in two similar situations.
      SILENCE    everything else stays at 1.0. A gain you did not think about is a gain that
                 should not fire.

    WHY 1.5-4 IS THE RIGHT TEXTURE BAND, arithmetically. Four texture terms at 2.5x each give a
    39x total spread — enough to reorder two candidates the signature alone would tie, and not
    enough to beat a signature term sitting at 15-40 on a strong signal. Push texture to 6+ and it
    starts winning arguments it should lose: two 6x textures (36x) already beat a 25x signature at
    half signal (5x). **Texture above 4 is not texture any more; it is a second signature, and
    two signatures is an archetype that reads as neither.**

    WORKED — the assassin, textured:
      SIGNATURE  ai_bloodlust      40      hunt the wounded            <- the whole identity
      TEXTURE    ai_opportunism    30      (inherited default is 8; an assassin raises it, and
                                           this one IS allowed past the band — `lethal` is binary
                                           and a guaranteed kill is a rule, not a taste, §15.3)
                 ai_efficiency      3.0    prefer whoever my damage cuts through (§6.8)
                 ai_pressure        2.5    press whoever has spent their options
                 ai_grudge          2.0    and lean toward whoever has been carrying the party
                 ai_caution         0.7    a slight reluctance to open on the biggest gun
      SILENCE    everything else at 1.0.
    In a four-unit party the signature decides ~85% of turns on its own. The texture decides the
    other 15% — and, more importantly, decides WHICH of two equally-wounded targets it takes, which
    is the difference between "it goes for the hurt one" and "it hunts."


================================================================================
## 5. THE VOCABULARY  (hidden stats — the whole personality system)
================================================================================
Every tunable AI number is a real hidden non-major base stat, exactly like `action_points`,
`spirit_regen` and `vulnerability`. That means, for free and with no AI-specific code:

  - a MODULE authors it:       `base_stats["ai_bloodlust"] = 40.0`
  - a FIGHT SPEC overrides it: `{"character":"ice_spirit", "stats":{"ai_panic": 20.0}}`
  - a BUFF MOVES it:           taunt      = `mods:{"magnetism": 300}`
                               berserk    = `mods:{"ai_intent_offense": 0.4}`
                               terrify    = `mods:{"ai_panic": 12.0}`
                               DAZE       = `mods:{"ai_smart": -1.0}`  — strips a boss's ability to
                                            read your Magnificence, dodge and resistances for N
                                            turns. A whole "make the boss stupid" mechanic, free.
  - read through `get_effective()`, so the full (base + Σ flat) × (1 + Σ mult) model applies.
  - NO SAVE_VERSION BUMP. `CharacterBase.from_dict` rebuilds `base_stats` from
    `Stats.default_base_stats()` and THEN overlays the saved values, so a newly-added default stat
    auto-propagates onto old saves (CORE_PRIMER §10). Same path `spirit_regen` / `action_points` /
    `vulnerability` / `heal_power` took.
  - NOT majors, so they never appear on the attribute screen, and the debug stat panel (which
    iterates `major_keys()`) does not show them either.

THE ONE COST: a stat is a scalar. Anything list-shaped (which signal feeds which gain) cannot be a
stat, and lives in the `AIRules` catalogue instead (§13). **Stats are the NUMBERS, `ai` is the SHAPE.**

### 5.1 INTENT WEIGHTS  (ADDITIVE, neutral at 0 — the only additive stats here)
    KEY                     DEFAULT   MEANING
    ai_intent_offense       0.50      base appetite for hurting things
    ai_intent_defense       0.15      base appetite for protecting itself
    ai_intent_buff          0.10      base appetite for helping its side
    ai_intent_debuff        0.15      base appetite for weakening the other side
    A weight of exactly 0.0 makes that intent impossible, full stop — the cleanest way to author
    "this thing only ever attacks".

### 5.2 SELECTION SHAPE  (exponents, neutral at 1.0)
    ai_decisiveness         1.5       exponent on intent AND ability scores before the pick.
                                      0 = uniform random; 1 = proportional; 8+ ≈ argmax. §15.2
    ai_focus                1.5       the same exponent on target magnetism. High = a laser; low
                                      = spreads damage around the party.

### 5.3 THE SMART GATE  (a switch, not a gain)
    ai_smart                0.0       >= 0.5 means this unit READS COUNTERPLAY: Magnificence,
                                      dodge and element matchups. 0 means it does not, and the
                                      three signals in §12 return 0 for it, which makes their gain
                                      terms vanish with no branch anywhere else. Mostly for
                                      minibosses and bosses — see §12 for why this is a player-
                                      feedback decision, not a difficulty one.

### 5.4 INTENT GAINS  (neutral 1.0; these multiply an INTENT's score — §7)
    KEY                     DEFAULT   SIGNAL IT RIDES              MEANING
    ai_finisher             15.0      best_kill_fraction           OFFENSE up when a kill is on.
                                                                   At s=1 (lethal) that is 15x —
                                                                   an available kill dominates.
    ai_shield_aversion      0.60      mean hostile shield_frac     OFFENSE down into a shield wall.
                                      (also a TARGET gain, §8)     Shield-reaver archetypes set >1.
    ai_bloodrage            1.00      own missing_hp               OFFENSE up as the unit itself
                                                                   dies. Berserkers set 8-12.
    ai_offer_drive          6.00      offer_strength(intent)       BUFF/DEBUFF/DEFENSE up when the
                                                                   best CASTABLE effect is strong.
                                                                   §10.2 — this is what makes a
                                                                   weak-buff creature only buff
                                                                   when it has nothing better.
    ai_tidiness             0.25      party buff/debuff pressure   BUFF/DEBUFF down when that side
                                      (also a TARGET gain, §8)     is already saturated.
    ai_altruism             4.00      best_buff_need               BUFF up when someone needs it.
    ai_panic                4.00      self_danger                  DEFENSE up as its own danger
                                                                   rises. Turtles set 20.
    ai_defense_sat          0.20      own defensive saturation     DEFENSE down when already
                                                                   shielded/warded.
    ai_resist_awareness     1.00      best_resist_chance           DEBUFF down when it will bounce.
                                      [ai_smart gated]             1.0 = OFF, which is the default
                                                                   on purpose. Smart units set 0.15.

### 5.5 TARGET GAINS  (neutral 1.0; these bend a candidate's MAGNETISM — §8)
    KEY                     DEFAULT   SIGNAL                       MEANING
    ai_bloodlust            1.00      missing_hp(tgt)              hunt the wounded. Assassin 40.
                                                                   DEFAULT IS OFF — see §8.2.
    ai_opportunism          8.00      lethal(tgt)  [binary]        finish a kill. Even a brute does.
    ai_gluttony             1.00      hp_frac(tgt)                 hunt the HEALTHY (a %-max-HP or
                                                                   %-current-HP scaler wants this).
    ai_caution              1.00      threat(tgt)                  <1 avoids the dangerous one,
                                                                   >1 duels it.
    ai_spite                1.00      debuff_severity(tgt)         pile onto an already-loaded
                                                                   target (the exact inverse of
                                                                   the DEBUFF tidiness rule).
    ai_spirit_hunger        1.00      spirit_frac(tgt)             drain the full caster.
    ai_combo_drive          1.00      combo_ready(tgt) [binary]    go where my Shatter/Snap payoff
                                                                   already has its mark.
    ai_element_savvy        1.00      element_advantage(tgt)       hit what my element beats.
                                      [ai_smart gated]
    ai_sapper               1.00      threat(tgt)                  DEBUFF-intent only: hex the
                                                                   scariest thing rather than the
                                                                   cleanest. Fights ai_tidiness on
                                                                   purpose.
    ai_prudence             1.50      hp_frac(tgt)                 DEBUFF-intent only: don't spend
                                                                   a 6-turn hex on a dying target.
    ai_mercy               12.00      missing_hp(ally)             BUFF-intent: heal who is hurt.
    ai_triage               4.00      debuff_severity(ally)        BUFF-intent: help who is loaded.
    ai_vigilance            1.00      incoming_pressure(ally)      BUFF-intent: shield who is about
                                                                   to be hit. Wardens set 8.
    ai_favoritism           1.00      ally_power(ally)             BUFF-intent: empower the
                                                                   strongest. Zealots set 6.
    ai_self_buff            0.25      is_self(tgt)  [binary]       BUFF-intent: how willing to
                                                                   target itself. 0.0 = a martyr
                                                                   that never does; 1.0 = no
                                                                   preference either way.

### 5.6 THE AUXILIARY GAINS  (rev3 — the texture band, §4.6; signals in §6.8)
    KEY                     DEFAULT   SIGNAL                       MEANING
    ai_efficiency           1.00      softness(tgt)                prefer whoever my damage cuts
                                                                   through fastest. **The most
                                                                   broadly useful texture gain in
                                                                   the list** — most archetypes
                                                                   should carry it at 2-4.
    ai_grudge               1.00      reputation(tgt)              go after whoever has actually
                                                                   been carrying their party,
                                                                   across battles.
    ai_pressure             1.00      cooldown_load(tgt)           press whoever has spent their kit.
    ai_spare_female         1.00      is_female(tgt)  [binary]     <1 spares, >1 hunts.
    ai_spare_child          1.00      is_child(tgt)   [binary]     <1 spares, >1 hunts.
    ai_thirst               4.00      spirit_need x relief         LAYER 3: reach for an ability
                                                                   that refills my Spirit. ON by
                                                                   default — an instinct, not a
                                                                   personality.
    ai_retinue_drive        1.00      party_depletion(actor)       BUFF intent + summon need-fit.
    ai_retinue              0         (not a gain — a COUNT)       the retinue size this unit wants.
                                                                   0 = does not summon, and every
                                                                   term reading it vanishes.

### 5.7 NOT STATS  (two things the AI reads that deliberately are not in base_stats)
    damage_rating   float, PERSISTED per unit in `Character.damage_history` (§6.8). Not a base stat
                    because it is a RECORD, not a tuning knob — nothing should buff it, a fight spec
                    should not fake it, and it has to survive between battles, which base_stats on a
                    combat clone does not. Needs no SAVE_VERSION bump (§6.8).
    figure          int, an enum on CharacterBase beside `race` / `organic`: NONE / MALE / FEMALE /
                    CHILD, default NONE. Not a base stat because it is IDENTITY — and putting it in
                    base_stats would make it buffable, which is wrong.

### 5.8 ALREADY EXISTS, NOW CONSUMED
    magnetism             100.0       the per-unit base draw. Hidden major, already in Stats,
                                      already documented as "reserved for future targeting". A tank
                                      raises it, a rogue lowers it, a taunt buff adds to it.

TOTAL: 33 new hidden stats plus `ai_retinue`, `damage_rating` and the `figure` enum. **All but a
dozen default to a value that makes their term vanish entirely**, and the ones that don't
(`ai_finisher`, `ai_opportunism`, `ai_shield_aversion`, `ai_offer_drive`, `ai_tidiness`,
`ai_altruism`, `ai_panic`, `ai_defense_sat`, `ai_mercy`, `ai_triage`, `ai_prudence`, `ai_thirst`)
encode instincts every creature should have. Adding all of them changes no existing behaviour —
every current creature reads exactly as it does today until a module sets one.


================================================================================
## 6. SIGNALS  (ai_signals.gd — the shared vocabulary every gain rides)
================================================================================
### 6.1 THE ONE RULE
**Every signal returns 0..1, and 0 ALWAYS means "this term does nothing".** That single discipline
buys three things: every gain is comparable, `pow(gain, 0) == 1` makes "not applicable" free, and
gating a signal (§12) is `return 0.0` with no branch at the call site. Anything unbounded gets
squashed on the way out with `squash(x) = x / (1 + x)` — the same soft saturation `CombatMitigation`
and `CombatDodge` already use, so this is the codebase's third use of a curve it already trusts.

### 6.2 THE CHEAP SIGNALS  (pure reads — no estimator, compute freely)
    hp_frac(u)        = float(u.body.current_hp) / maxf(1.0, float(u.body.max_hp()))
    missing_hp(u)     = 1.0 - hp_frac(u)
    shield_frac(u)    = clampf(float(CombatShields.total(u.body)) / maxf(1.0, float(u.body.max_hp())), 0, 1)
    spirit_frac(u)    = float(u.body.current_spirit) / maxf(1.0, float(u.body.max_spirit()))
    is_self(a, u)     = 1.0 if u == a else 0.0
    effective_hp(u, elem) -> float                      # NOT normalized; a raw HP number
        = u.body.current_hp + (0 if elem == "true" else CombatShields.total(u.body))
        The element argument is the whole point: TRUE damage ignores shields (COMBAT C8), so an AI
        that adds the shield to a true-damage lethality check refuses a kill it actually has.

### 6.3 SEVERITY  (§10 has the full derivation and the field disambiguation)
    buff_severity(u)   = squash(severity_raw(u.body, "buffs")   / SEVERITY_REF)     # REF 4.0
    debuff_severity(u) = squash(severity_raw(u.body, "debuffs") / SEVERITY_REF)
    party_buff_pressure(side)   = mean buff_severity over LIVING members
    party_debuff_pressure(side) = mean debuff_severity over LIVING members
        `party_debuff_pressure(hostiles)` is the design brief's rule verbatim: total severity on the
        enemy party divided by the number of the enemy party.

### 6.4 OFFER STRENGTH  (§10.2 — new in rev2, and the answer to "weak buffs vs strong buffs")
    offer_strength(actor, intent) = squash(best_entry_value / OFFER_REF)             # REF 3.0
        best over every USABLE (ability, slot) pair tagged with `intent`. "Usable" means it passed
        `_can_use`, so **an ability on cooldown contributes nothing** and the unit's appetite for
        that intent drops this turn all by itself. That is the cleanest possible answer to "only use
        buffs if you have nothing better to do".

### 6.5 THE ESTIMATOR SIGNALS  (§11 — cached per action, skipped when no gain reads them)
    kill_fraction(a, t)  = clampf(best_expected_damage(a -> t) / maxf(1, effective_hp(t, elem)), 0, 1)
    lethal(a, t)         = 1.0 if best_expected_damage(a -> t) >= effective_hp(t, elem) else 0.0
                           Binary on purpose — "can I finish it" is not a gradient. The gradient
                           version is kill_fraction, and both exist because OFFENSE wants both.
    threat(u) vs actor   = squash(best_expected_damage(u -> actor) / maxf(1, effective_hp(actor,"")))
                           Literally "what fraction of me can this thing remove in one hit". This is
                           the one place the AI reads another unit's loadout; it is legal (no fog of
                           war) and it is what makes ai_caution actually work.
    incoming_pressure(u) = squash(Σ threat(h) vs u, over living hostiles TO u)
    ally_power(u)        = squash(best_expected_damage(u -> the most magnetic hostile)
                                  / maxf(1, effective_hp(that hostile, "")))
    self_danger(a)       = clampf(0.50*missing_hp(a) + 0.25*debuff_severity(a)
                                + 0.25*incoming_pressure(a), 0, 1)
                           A unit that is unhurt, unencumbered and facing one weak enemy reads ~0
                           and never defends; one at 20% HP under three debuffs with a boss opposite
                           reads ~0.9 and defends most turns.

### 6.6 THE COMBO SIGNAL  (new in rev2 — cheap, and it unlocks a whole archetype)
    combo_ready(a, t) = 1.0 if the actor holds a USABLE ability with any of
                            consume_debuff_element / damage_per_debuff_element /
                            pierce_per_debuff_element
                        whose element `t` already carries
                        (CombatBuffs.count_debuffs_of_element(t.body, elem) > 0), else 0.0
    Three abilities already ship with those fields — Shatter, Snap and Cryonecrosis — so a creature
    given an ice debuff and a Shatter can be taught to set up and then cash in, with one gain stat.

### 6.7 THE GATED SIGNALS  (§12 — return 0.0 unless ai_smart >= 0.5)
    resist_chance(a, t, entry) = CombatResist.resist_chance(a.body, t.body, entry) / 100.0
    dodge_chance(a, t, ability) = CombatDodge.chance(a.body, t.body, ability) / 100.0
    element_advantage(a, t, elem) = clampf(2.0 * (fit - 0.5), 0, 1)
        where fit = 0.5 + 0.5*squash(0.03 * (my_pierce - their_effective_defense))
              their_effective_defense = t.body.get_effective(Stats.defense_key(elem))
                                      * (1 + CombatBuffs.resist_mult_bonus(t.body, elem))
        Reframed from rev1's `element_fit` so that 0 means "no edge" rather than "at a
        disadvantage" — that is what the §6.1 rule requires, and it also means a smart unit is drawn
        to good matchups rather than repelled by bad ones, which reads better in play.
        elem == "true" always returns 1.0.

### 6.8 THE AUXILIARY SIGNALS  (rev3 — the texture layer of §4.6)
These exist so an archetype can be one signature plus several small opinions. **This list is
expected to grow with the game**; each entry below is one function in AISignals plus one line in the
dispatcher plus one gain in Stats, and nothing else in the design moves. Two of them need a MECHANIC
that does not exist yet — both are specced in §19 and marked BLOCKED here.

    ── softness ── how far my damage goes into that pool ─────────────────────────
    gain: ai_efficiency   default 1.00 (off)   TARGET, offense + debuff
        The design want: a full-health 500-HP unit should read as a stronger target than a
        full-health 1000-HP unit — and a unit that resists my elements should read weaker than its
        raw HP suggests. Both fall out of ONE quantity: how many of my hits it takes.

        hits_to_kill(actor, tgt) = effective_hp(tgt, primary_elem)
                                 / maxf(1.0, mean_expected_damage(actor -> tgt))
        softness(actor, tgt)     = SOFT_K / (SOFT_K + hits_to_kill)          # SOFT_K = 3.0

        mean_expected_damage is the MEAN over the actor's usable damaging abilities, not the max —
        `lethal` already asks "what is my best single hit", and softness is asking about sustained
        pressure. Because each estimate runs through `CombatMath.preview`, the target's flat
        resistance, its multiplicative resist layer, the actor's pierce and amp and the target's
        damage_taken_mult are ALL already folded in. **That is the "modified by its resistances to
        the actor's main element types" clause, for free, with no separate element-weighting pass —
        a unit that resists everything I throw simply takes more hits.**

        THE CURVE, which is why it is written as a ratio rather than a squash:
            hits    1     2     3     4     5     8    10    15    20
            signal 0.75  0.60  0.50  0.43  0.375 0.27  0.23  0.17  0.13
        Softness never reaches 1.0 (a one-hit kill reads 0.75) because `lethal` is the signal for
        that case and the two should not double-count.

        NOTE THE OVERLAP, deliberately: softness, kill_fraction and lethal all read the same
        underlying estimate at different resolutions — sustained / this-hit / binary. An archetype
        picks the resolution it cares about. Do not wire all three at strength on one unit.

    ── reputation ── who has actually been carrying the party ────────────────────
    gain: ai_grudge       default 1.00 (off)   TARGET, offense + debuff
        A PERSISTED, cross-battle measure, unlike everything else in §6 — it is the only signal
        that survives a fight. The want: a player building an ally as support reads low; a glass
        cannon reads high; and the AI focuses whoever is actually the damage engine, which is a
        different question from "who can hit me hardest right now" (that is `threat`).

        THE STAT (new, persisted):  damage_rating : float
            The mean total damage dealt per battle over the LAST 5 BATTLES.
        RECORDING (all new, all small):
          1. `BattleCharacter.damage_dealt: float`, accumulated during a fight — in _use_ability's
             ATTACK branch, in _apply_shatter, and in CombatBuffs' on_hit_damage rider. DoT is
             dealt with NO source (COMBAT C1) and therefore cannot be attributed; it is excluded,
             and that exclusion is a real bias worth remembering when a DoT build reads low.
          2. At fight end, for every non-enemy unit, push `damage_dealt` onto a rolling 5-entry
             list and store the mean.
        STORAGE: `Character.damage_history : Dictionary` — unit id -> Array[float], with the
             player under the reserved key "player" and allies under their CharacterRegistry id.
             It goes in the save dict beside `allocations`. **NO SAVE_VERSION BUMP NEEDED:**
             `load_game` reads every field with `parsed.get(key, default)`, so a save written
             before this key existed simply loads an empty dict. (NB the primers say SAVE_VERSION
             3; the code is on 4, and its loader DISCARDS any save whose version does not match
             exactly — so a bump is a wipe, and this change must not need one.)
        NORMALISATION — relative, never absolute:
            reputation(u) = damage_rating(u) / max(damage_rating over the candidate set)
            0.0 when every candidate reads 0.
        Relative because an absolute reference would go stale the moment damage numbers inflate
        with levels and gear. Relative means the top damage dealer always reads 1.0 and everyone
        else reads their share of it — self-scaling forever, no retuning.
        THE THREE-TIER FALLBACK (this matters — without it every unit reads 0 on battle one):
            1. a stored damage_rating, if there is one
            2. else `damage_dealt` so far THIS fight (so it warms up mid-battle)
            3. else the derived `ally_power` / `threat` estimate (so turn one is never blind)
        Enemies are rebuilt from their module every fight and keep no history — they always land on
        tier 2 or 3, which is correct: an enemy has no reputation to have earned.

    ── cooldown_load ── how much of their kit is spent ───────────────────────────
    gain: ai_pressure     default 1.00 (off)   TARGET, offense + debuff
        cooldown_load(u) = (# slots i in u.loadout where u.on_cooldown(i)) / maxf(1, u.loadout.size())
        Pure existing API — `BattleCharacter.cooldowns` is per-unit and per-slot, and the player's
        is the wheel's. A unit that has just spent its whole kit is a unit that cannot answer, and
        an archetype that presses that advantage feels like it is paying attention.
        **PAIRS WITH A MECHANIC THAT DOES NOT EXIST — see §19.13**: an ability that ADDS cooldown to
        slots already cooling. That combination is self-reinforcing (the more they are cooling, the
        harder the AI presses, the longer they cool), which is exactly the intended nasty — and
        exactly why it needs a cap. §19.13 has the spec and the cap.

    ── is_female / is_child ── the restraint signals ─────────────────────────────
    gains: ai_spare_female  default 1.00 (off)   TARGET, offense + debuff
           ai_spare_child   default 1.00 (off)   TARGET, offense + debuff
        Two BINARY signals off a new identity field. Because they are separate gains, "less likely"
        and "much less likely" are independent numbers rather than one scale: a knightly enemy sets
        `ai_spare_female 0.5` (half as likely) and `ai_spare_child 0.05` (effectively never).
        THE FIELD (identity, NOT a stat — see §5.7):
            CharacterBase.figure : int, enum Stats.Figure { NONE, MALE, FEMALE, CHILD }
            **DEFAULT IS NONE, and that default is load-bearing** — most of the bestiary is spirits,
            constructs and beasts, and defaulting to MALE would silently mark every one of them.
            Both signals return 0.0 for NONE, so the terms vanish for anything unlabelled.
        NAMING: the brief called this "gender", but CHILD is not a gender, so a name that spans all
        three is more accurate and leaves room for the list to grow (the brief says it will).
        `figure` is the recommendation; `frame` and `form` also work. Whatever it is called, it sits
        beside `race` and `organic` as identity, not in `base_stats` — which means, correctly, that
        **no buff can change it.**
        THE INVERSE IS FREE. A gain above 1.0 on the same signal is a unit that specifically HUNTS
        children — a horror enemy, a boss with a cruelty theme. One field, both directions.
        PLAYER SIDE: the player character and every recruitable ally need `figure` authored, or the
        restraint gains never fire on the units they exist for.

    ── spirit_need ── my own tank is empty ───────────────────────────────────────
    gain: ai_thirst       default 4.00 (ON)     ABILITY (layer 3), not target
        The only auxiliary that scores an ABILITY rather than a candidate, because "I should top
        myself up" is a choice between abilities, not between targets.
            spirit_need(actor)   = 1.0 - spirit_frac(actor)
            spirit_relief(a, ab, rank) = clampf((spirit_gain_at(rank) + spirit_steal_at(rank))
                                         / maxf(1.0, a.get_max_spirit() - a.get_spirit()), 0, 1)
                                   # "what fraction of my deficit does this fill" — 1.0 = tops me up
            layer-3 score *= pow(ai_thirst, spirit_need * spirit_relief)
        At 20% spirit with a full-deficit refill that is 4^0.80 = 3.0x; at full spirit the deficit
        is 0, `spirit_relief` is 0, and the term vanishes. It is ON by default because wanting your
        resource back is an instinct, not a personality.
        IT ALREADY HAS A USER: Acceleration (`lamed`) is a free ATTACK with `spirit_gain 25`, and
        ZAP! (`cheth`) has `spirit_steal 10, spirit_gain 5` at zero action cost. Both become
        correctly attractive to a drained caster with no ability-specific code.
        NB the "run dry, use free abilities" behaviour needs NO signal — `_can_use` already refuses
        what the unit cannot afford, so the usable set shrinks and viability does the work.

    ── party_depletion ── my retinue is thin ─────────────────────────────────────
    gain: ai_retinue_drive  default 1.00 (off)  INTENT (buff) + ABILITY need-fit
    stat: ai_retinue        default 0           the retinue size this unit WANTS
        party_depletion(actor) = clampf(1.0 - living_friendlies(actor) / maxf(1.0, ai_retinue), 0, 1)
        With `ai_retinue 4` and only itself alive that is 0.75; with a full retinue it is 0 and every
        term reading it vanishes, so a non-summoner (ai_retinue 0) is unaffected by construction.
        WHERE IT RIDES: summoning is **BUFF intent**, not a fifth intent — it is helping your own
        side, it is chosen from the buff-tagged usable set, and it targets SELF. It adds one term to
        the BUFF multiplier, `pow(ai_retinue_drive, party_depletion)`, and it is the need_fit for a
        summon ability in layer 3.
        WHY NOT A FIFTH INTENT: the brief's model is four, and a fifth costs an enum value, a
        viability row, a multiplier block and a wiring block in every archetype. Riding on BUFF costs
        one term. **If summoning ever grows richer** — summon types, positioning, sacrificing a
        minion — promote it; the change is contained and the four listed pieces are all of it.
        **BLOCKED — no summon mechanic exists.** §19.14 has the spec, including the one real hazard
        (spawning into `_units` while `end_player_turn` is iterating it).


================================================================================
## 7. LAYER 1 — INTENT  (ai_intent.gd)
================================================================================
    score[i] = 100.0 * get_effective("ai_intent_<i>")     # the brief's "value x 100"
    score[i] *= context_multiplier[i]                      # §7.2 — a product of gain terms
    score[i]  = maxf(0.0, score[i])
    if not viable[i]: score[i] = 0.0
    if i == OFFENSE and viable[OFFENSE]: score[i] = maxf(score[i], OFFENSE_FLOOR)   # 12.0
    -> AIPick.weighted(score, exponent = ai_decisiveness)

### 7.1 VIABILITY — a gate, never a discount
An intent is viable ONLY IF the unit has at least one ability that serves it AND at least one legal
target for that ability. Both are checked with the real predicates, never a copy:

    usable(u, ability, slot) := combat._can_use(u, ability, slot)
    which is combat._use_blocked returning "" — and it already checks, in this order:
        1. caster / body / ability non-null
        2. caster.is_alive()
        3. not CombatBuffs.is_stunned(caster.body)
        4. **not caster.on_cooldown(slot)**          <- the cooldown gate, per rev2's brief
        5. not (spirit_cost_at(rank) > 0 and CombatBuffs.is_silenced(caster.body))
        6. caster.get_spirit() >= spirit_cost_at(rank)          (RANK-AWARE)
        7. ability.action_cost <= caster.ap + AP_EPSILON

    INTENT   VIABLE IFF
    OFFENSE  >=1 usable OFFENSE-tagged ability  AND  >=1 legal hostile
    DEBUFF   >=1 usable DEBUFF-tagged ability   AND  >=1 legal hostile
    BUFF     >=1 usable BUFF-tagged ability     AND  >=1 legal friendly target
             (SELF counts only when ai_self_buff > 0, OR the unit is the only living friendly)
    DEFENSE  >=1 usable DEFENSE-tagged ability targeting SELF

**COOLDOWNS PROPAGATE TWICE, AND THAT IS DELIBERATE.** Once here, as a hard viability gate (a hexer
whose only debuff is cooling simply cannot pick DEBUFF), and once through `offer_strength` (§10.2),
which is computed over the SAME usable set — so a hexer with a weak backup debuff off cooldown and
its big one cooling is *viable* for DEBUFF but much less *inclined*, and will usually attack
instead. That is exactly the behaviour a cooldown should buy.

### 7.2 THE CONTEXT MULTIPLIERS, IN FULL
Each is a product of `AIGain.apply` terms. Every term is 1.0 when its gain is 1.0 or its signal is
0, so a creature with default stats runs on its base weights alone.

    ── OFFENSE ─ deliberately the SIMPLEST of the four ──────────────────────────
        m  = pow(ai_finisher,        best_kill_fraction)
           * pow(ai_shield_aversion, mean_shield_frac(legal hostiles))
           * pow(ai_bloodrage,       missing_hp(actor))
        score = maxf(base * m, OFFENSE_FLOOR)

        THREE TERMS, AND THAT IS THE POINT. Offense is the default — it should not need to argue
        for itself, it should win whenever nothing else has a strong case. Making it complicated
        would also make it WRONG for a whole class of creature: an enemy whose damage scales off the
        target's max or current HP should prefer a HEALTHY target, and one with no such scaling
        should not care either way. Neither is an intent-layer concern; both are one target gain
        (`ai_gluttony` / `ai_bloodlust`, §8), left OFF by default. **The intent layer must not
        assume anything about who offense will be pointed at.**
          - best_kill_fraction: max over legal hostiles of kill_fraction(actor, t). At the default
            ai_finisher 15.0, an available kill multiplies offense appetite by 15 — from a base 50
            to 750, which will beat any other intent's realistic score. That is the intended
            "desire to go for lethal is very high".
          - shield aversion is MODERATE (0.60 -> a fully shielded party is a 0.6x nudge, not a
            refusal) and is NOT set in stone: a `shield_reaver` sets it to 3.5 and becomes actively
            drawn to shields, on both this term and the matching target gain.
          - bloodrage is OFF by default and is what a berserker turns on.

    ── DEBUFF ────────────────────────────────────────────────────────────────────
        m  = pow(ai_tidiness,          party_debuff_pressure(hostile side))
           * pow(ai_offer_drive,       offer_strength(actor, DEBUFF))
           * pow(ai_resist_awareness,  best_resist_chance)          [0 unless ai_smart]

          - tidiness at 0.25: a fully saturated enemy party cuts debuff appetite to a quarter. This
            is the brief's core rule. A `plaguebearer` sets it to 1.0 and keeps stacking.
          - offer_drive at 6.0: a creature holding a strong, castable debuff gets up to 6x the
            appetite of one holding a weak one. **This is what makes a weak-debuff creature use its
            debuff only when it has nothing better to do**, without a single special case.
          - best_resist_chance = the LOWEST resist chance available across (debuff ability x legal
            target) — the AI asks "is there anyone I can reliably land this on", not "will this
            particular cast land". Returns 0 for a non-smart unit, so the term vanishes (§12).

    ── BUFF ──────────────────────────────────────────────────────────────────────
        m  = pow(ai_tidiness,       party_buff_pressure(own side))
           * pow(ai_offer_drive,    offer_strength(actor, BUFF))
           * pow(ai_altruism,       best_buff_need)
           * pow(ai_retinue_drive,  party_depletion(actor))       [rev3 — summoners only]

          best_buff_need = max over legal friendly targets t of
              clampf(0.50*missing_hp(t) + 0.30*debuff_severity(t) + 0.20*(1 - buff_severity(t)), 0, 1)
          A topped-up, clean, already-buffed party drives this toward 0, and pow(4, 0) = 1 leaves
          the base weight standing — buffing becomes unattractive, never impossible. A badly hurt
          ally drives it to ~1 and multiplies appetite by 4.

    ── DEFENSE ───────────────────────────────────────────────────────────────────
        m  = pow(ai_panic,        self_danger(actor))
           * pow(ai_offer_drive,  offer_strength(actor, DEFENSE))
           * pow(ai_defense_sat,  maxf(shield_frac(actor), buff_severity(actor)))

          At the default panic 4.0 a unit in real trouble quadruples its defensive appetite; a
          `turtle` at 20.0 becomes nearly guaranteed to hunker when hurt. defense_sat at 0.20 stops
          it stacking a third shield on a unit already behind two.

  >> SETTLED (rev3). The brief's line "If the enemy is low on health or debuffed then a defense
     intent is more likely" read backwards, and the reading confirmed is the mechanical one:
     **DEFENSE is driven by the ACTOR'S OWN danger**, via `self_danger` above. A wounded enemy
     invites OFFENSE and gets it, through `ai_bloodlust` / `ai_opportunism` in the target layer.
     There is no `ai_vulture` term and none is planned; if one is ever wanted it is a single added
     `pow(ai_vulture, 1 - mean hp_frac(hostiles))` line here and nothing else.

### 7.3 FAILURE
If every score is 0 the layer returns FAILED and the runner drops to the fallback ladder (§16.5). It
never returns a non-viable intent.


================================================================================
## 8. LAYER 2 — TARGET  (ai_target.gd)
================================================================================
### 8.1 THE MECHANISM
    1. CANDIDATES = every living unit for which `_valid_target(actor, ability_class, u)` can hold
       for at least one of the intent's usable abilities.
    2. COPY the magnetism.  m = u.body.get_effective("magnetism")
       **The copy is what gets bent; the unit's own stat is never written.** The brief is explicit
       about this and it matters — `magnetism` is a real buffable stat, and a taunt must not be
       consumed by being read.
    3. BEND it with this intent's gain terms from the archetype's wiring (§13):
           for term in AIRules.target_gains(ai, intent):
               var s := AISignals.get(term.signal, actor, u)     # 0..1, 0 = no-op
               var g := actor.body.get_effective(term.stat)      # 1.0 = no-op
               m = AIGain.apply(m, g, s)
           m = maxf(MIN_MAGNETISM, m)     # 1.0 — nothing is ever accidentally untargetable.
                                          # Author magnetism 0 on the body if you mean it.
    4. PICK by roulette over the bent values, exponent `ai_focus`.

    DEFENSE SHORT-CIRCUITS THE WHOLE LAYER: the target is the acting unit, full stop. The brief says
    defense "will pick one of the defense abilities in its defense set based on further behavior in
    the next layer" — so DEFENSE goes Layer 1 -> Layer 3 directly, and the "further behaviour" is
    §9.2's need-fit scoring.

### 8.2 THE WIRING, PER INTENT  (the `"standard"` entry — archetypes override in §13)

    OFFENSE                                     DEFAULT GAIN   ON BY DEFAULT?
      missing_hp        x ai_bloodlust             1.00           no
      hp_frac           x ai_gluttony              1.00           no
      lethal            x ai_opportunism           8.00           YES
      threat            x ai_caution               1.00           no
      shield_frac       x ai_shield_aversion       0.60           yes (mild)
      spirit_frac       x ai_spirit_hunger         1.00           no
      debuff_severity   x ai_spite                 1.00           no
      combo_ready       x ai_combo_drive           1.00           no
      element_advantage x ai_element_savvy         1.00           no  [ai_smart gated]
      softness          x ai_efficiency            1.00           no  } rev3 auxiliaries —
      reputation        x ai_grudge                1.00           no  } the TEXTURE band (§4.6).
      cooldown_load     x ai_pressure              1.00           no  } All off by default;
      is_female         x ai_spare_female          1.00           no  } an archetype turns on
      is_child          x ai_spare_child           1.00           no  } three to five at 1.5-4.

    **BOTH HEALTH GAINS ARE OFF BY DEFAULT, AND THAT IS THE IMPORTANT DEFAULT IN THE WHOLE
    DOCUMENT.** A default enemy targets on RAW MAGNETISM and nothing else, plus a hard pull toward a
    kill it can actually land. It does not prefer the wounded, because plenty of enemies should not:
    a creature whose damage scales off the target's max or current HP wants the HEALTHY one, and
    turns on `ai_gluttony` instead. Preferring the wounded is an assassin's trait, not a law of
    combat, so it is opt-in at `ai_bloodlust = 40`.

    DEBUFF                                      DEFAULT GAIN   ON BY DEFAULT?
      debuff_severity   x ai_tidiness             0.25           YES (the brief's rule)
      hp_frac           x ai_prudence             1.50           yes (mild)
      threat            x ai_sapper               1.00           no
      resist_chance     x ai_resist_awareness     1.00           no  [ai_smart gated]
      element_advantage x ai_element_savvy        1.00           no  [ai_smart gated]
      softness          x ai_efficiency           1.00           no  } rev3 auxiliaries. A hex
      reputation        x ai_grudge               1.00           no  } lands best on the party's
      cooldown_load     x ai_pressure             1.00           no  } engine, and on whoever has
      is_female         x ai_spare_female         1.00           no  } no cooldowns left to
      is_child          x ai_spare_child          1.00           no  } answer it with.

      `ai_prudence` at 1.50 is a gentle pull toward healthier targets — a six-turn hex spent on
      something that dies next turn is wasted, but not catastrophically, so the nudge is small.
      `ai_sapper` deliberately FIGHTS `ai_tidiness`: tidiness says "spread out", sapper says "hex the
      scariest one". A sapper sets sapper 6.0 and leaves tidiness at 0.25, and the product decides —
      it will hex the dangerous target until that target is loaded, then move on. That emergent
      behaviour is why the terms multiply rather than being an either/or.

    BUFF                                        DEFAULT GAIN   ON BY DEFAULT?
      missing_hp        x ai_mercy              12.00           YES
      debuff_severity   x ai_triage              4.00           YES
      buff_severity     x ai_tidiness             0.25           YES
      incoming_pressure x ai_vigilance            1.00           no
      ally_power        x ai_favoritism           1.00           no
      is_self           x ai_self_buff            0.25           yes (a mild self-preference cut)

      `ai_mercy` at 12 means a half-dead ally is 3.46x more magnetic and a quarter-health one 6.45x;
      a medic pushes it to 25 (5.0x / 11.2x) and becomes a proper triage nurse.

    DEFENSE  — no target layer.

### 8.3 THE ORDERING PROBLEM (target before ability), stated honestly
Layer 2 runs before Layer 3, but four target signals (`lethal`, `kill_fraction`, `element_advantage`,
`combo_ready`) depend on WHICH ability gets used. The design resolves it with a **proxy**: they are
evaluated against the actor's single best-scoring usable ability of the intent's class, computed once
when the AIContext is built and reused for every candidate. That is one estimator pass per ability
(not per ability x target), and it is honest about being an approximation.

The alternative — score every (ability, target) PAIR and pick from the cross product — is strictly
better and strictly more expensive, and it dissolves the magnetism concept the brief is built around
into a scoring term. **Recommendation: ship the proxy.** `AITarget.pick()` takes an optional
`ability_hint` so pair-scoring slots in later without changing the layer's signature.


================================================================================
## 9. LAYER 3 — ABILITY  (ai_ability.gd)
================================================================================
### 9.1 THE SET
`intent_abilities(u, intent, tgt)` = every (ability, slot) pair in `u.loadout` that
  (a) carries this intent in its tag set (§9.4),
  (b) passes `_can_use(u, ability, slot)`,
  (c) passes `_valid_target(u, ability, tgt)`.
An empty set means this intent was mis-declared viable — it can legitimately happen, because Layer 1
checked "some debuff ability has some legal hostile" and the roulette may have landed on a target
that is not legal for all of them. Return FAILED and let the ladder run (§16.5).

### 9.2 THE SCORING  (everything lands near 1.0 for "an ordinary use")

    OFFENSE  score = min(expected_damage / effective_hp(tgt, elem), 1.0)
                   + (LETHAL_BONUS 1.5 if expected_damage >= effective_hp)
                   * pow(0.5, cooldown_at(rank) / COOLDOWN_REF)        # COOLDOWN_REF 6.0
                   * pow(0.7, spirit_cost_at(rank) / maxf(1, max_spirit))
                   * ai_priority
        Capping the ratio at 1.0 **is** the anti-overkill rule: once an ability kills, a bigger one
        is not better, so the cheaper / shorter-cooldown one wins the discounts. `expected_damage`
        already folds dodge and crit in as expectations (§11), so a high-dodge target automatically
        devalues a big slow attack relative to a reliable one — no separate accuracy rule needed.

    DEBUFF   score = entry_value(ability, rank)
                   * (1 - resist_chance)          [resist_chance is 0 unless ai_smart, so a dumb
                                                   unit's score is just entry_value x novelty]
                   * novelty
                   * ai_priority
        novelty = 0.15 when the target already carries this exact entry id AND the entry is not
        stackable (re-applying only refreshes duration — worth something, not much); 1.0 otherwise.
        With independent-instance stacking (BUFF_PRIMER) a stackable entry is always full value.

    BUFF     score = need_fit(ability, tgt) * entry_value(ability, rank) * ai_priority
        need_fit by kind:  HEAL   -> missing_hp(tgt)
                           SHIELD -> incoming_pressure(tgt) * (1 - shield_frac(tgt))
                           BUFF   -> (1 - buff_severity(tgt))
        A full-HP ally does not get healed and a fully shielded one does not get a second shield,
        without either being a special case.

    DEFENSE  the same need_fit against SELF, with `self_danger` in place of incoming_pressure.
        This is the "further behaviour in the next layer" the brief asks for: the defence SET is
        chosen by intent, the MEMBER by which flavour of trouble the unit is in — hurt -> heal,
        about to be hit -> shield, debuffed -> cleanse (when a cleanse exists), otherwise -> the
        flat mitigation buff.

    SUMMON (rev3, BLOCKED — §19.14): rides on the BUFF intent, targets SELF.
        need_fit = party_depletion(actor)
        So a summoner with a full retinue scores its summon near 0 and casts something else, and a
        summoner standing alone scores it near 1 and reaches for it. No special case.

    THE UNIVERSAL RIDER (rev3), applied to EVERY intent's score after the above:
        score *= pow(ai_thirst, spirit_need(actor) * spirit_relief(actor, ability, rank))
        Non-1.0 only for an ability that actually grants or steals Spirit, and only while the actor
        has a deficit — so it is silent on almost every cast and decisive on the one that matters.

    -> AIPick.weighted(scores, exponent = ai_decisiveness)

### 9.3 WHY `ai_priority` MATTERS MORE THAN IT LOOKS
It is the only per-ABILITY knob in the whole system, and it is how a `disabler` exists at all: the
archetype's stat block cannot say "prefer the stun", because the stun is an ability, not a stat. So
the disabler's stun `.tres` carries `ai_priority = 3.0` and the archetype simply raises
`ai_intent_debuff`. Conversely `ai_priority = 0.0` means "the AI never picks this", which is how a
player-only ability can live on a shared `.tres` an enemy also carries.

### 9.4 TWO NEW ABILITY EXPORTS  (ability.gd)
Which intents an ability serves is DERIVABLE from `kind` + `target` for every ability shipped today,
so the derivation is the default and the export is the override:

    DEFAULT DERIVATION (`Ability.ai_intents_default()`):
      kind ATTACK, target ENEMY/ALL_ENEMIES        -> [OFFENSE]  (+ [DEBUFF] if applies_buff != "")
      kind DEBUFF                                  -> [DEBUFF]
      kind BUFF,   target SELF                     -> [DEFENSE, BUFF]
      kind BUFF,   target ALLY/ALL_ALLIES          -> [BUFF]
      kind HEAL,   target SELF                     -> [DEFENSE]
      kind HEAL,   target ALLY/ALL_ALLIES          -> [BUFF, DEFENSE]
      kind SHIELD, target SELF                     -> [DEFENSE]
      kind SHIELD, target ALLY/ALL_ALLIES          -> [BUFF, DEFENSE]
      kind PASSIVE / any always-active shape       -> []   (never castable)

    @export var ai_intents: Array[String] = []    # [] = derive. Override to narrow or widen — an
                                                  # ATTACK that exists to apply a debuff can declare
                                                  # ["debuff"] and stop competing for offense.
    @export var ai_priority: float = 1.0          # flat multiplier on the Layer-3 score. 0.0 = the
                                                  # AI never picks it; 3.0 = a signature move.

Both default harmlessly on every existing `.tres` with no re-save, exactly like every field added
since rev20 (ABILITY_PRIMER §8).

**A PASSIVE MUST NEVER REACH THE AI.** `_loadout_for` returns `body.abilities` verbatim, so a module
that lists a passive there would hand the AI an uncastable slot. Filter `is_passive()` /
`is_always_active()` out when the context is built, and `push_warning` once — an authoring error
worth surfacing, not swallowing.


================================================================================
## 10. SEVERITY AND OFFER STRENGTH
================================================================================
### 10.1 SEVERITY — the number the whole design leans on
The brief's word for "how loaded up is this unit". **The schema already has it and nothing reads it
yet:** every buff entry carries `magnitude` (BUFF_PRIMER §1: "HIDDEN severity gauge — reserved for
future targeting") and `weight` ("for FUTURE AI targeting"). This design is that future. No new buff
field is needed anywhere.

    THE TWO FIELDS, DISAMBIGUATED — write this into BUFF_PRIMER when the AI lands:
      magnitude : HOW BIG this effect is. A stun is enormous (5.0); +5 Alacrity for 3 turns is small
                  (0.5). It is the unit of severity.
      weight    : HOW MUCH THE AI SHOULD CARE, independently of size. The designer's thumb for an
                  effect the AI should chase or avoid regardless of its raw numbers. 1.0 = "care
                  exactly as much as the magnitude says".

    AISignals.severity_raw(body, basket) -> float          # unbounded
        Σ over entries in body.baskets[basket]:
              magnitude(e) * weight(e) * Buff.stacks(e)
            * potency_applied(e)          # Disdain already amplified it — count that
            * duration_factor(e)

    duration_factor(e):
        permanent (duration < 0)  -> DUR_PERMANENT (2.0)   # fight-long is worth ~2 turns of a
                                                           # temporary one, not infinity
        else clampf(remaining / DUR_REFERENCE, DUR_FLOOR, 1.0)   # DUR_REFERENCE 4.0, FLOOR 0.25

    buff_severity / debuff_severity = squash(severity_raw / SEVERITY_REFERENCE)     # REF 4.0

WHY SQUASH RATHER THAN CLAMP: a target with twelve debuffs should read "very loaded" but not
*infinitely* more loaded than one with six — a clamp makes every heavily-hit target identical, and a
raw ratio lets one over-stacked unit swallow the whole roulette. Squash is what the codebase already
does for the same problem in mitigation and dodge.

**FOLLOW-UP THIS CREATES:** every entry in buff_library.gd currently uses the default
`magnitude: 1.0`, so on day one a stun and a +5 Alacrity buff read as equally severe. A tuning pass
over the catalogue — one `magnitude` (and where wanted, `weight`) per entry — is Phase 5 (§18). The
AI works before that pass; it just judges bluntly.

### 10.2 OFFER STRENGTH — "how good is the best thing I could actually cast right now"
New in rev2, and the answer to the brief's rule that a creature with weak buffs should only buff when
it has nothing better, while a creature holding a powerful, available buff should reach for it.

    AIEstimate.entry_value(actor, ability, rank, tgt) -> float        # unbounded, ~1.0 = ordinary
      BUFF / DEBUFF kinds:
          e = BuffLibrary.build(combat._rank_clone_id(String(ability.applies_buff), rank),
                                actor.body, tgt.body)
          value = magnitude(e) * weight(e) * duration_factor(e)
          (BuffLibrary.build only CONSTRUCTS — it never applies. Confirm that stays true; if any
           entry ever gains a build-time side effect, switch to a static magnitude table instead.)
      HEAL kind:
          value = (compute_heal(actor stats, rank) * heal_power_dealt) / maxf(1, tgt.max_hp())
                  * HEAL_VALUE_SCALE (3.0)
      SHIELD kind:
          value = (compute_shield(actor stats, rank) * shield_power_dealt) / maxf(1, tgt.max_hp())
                  * SHIELD_VALUE_SCALE (2.5)
      An ability that carries BOTH a buff and a heal sums the two.

    AISignals.offer_strength(actor, intent) =
        squash(max over USABLE (ability, slot) pairs tagged `intent` of
                   entry_value(actor, ability, rank, best_candidate_target)
               / OFFER_REFERENCE)                                     # OFFER_REFERENCE 3.0

    WHAT IT PRODUCES, at the default ai_offer_drive 6.0:
        best offer value 0.5 (a trivial +5 stat buff)   -> s≈0.14 -> x1.29
        best offer value 3.0 (a solid multi-turn debuff)-> s=0.50 -> x2.45
        best offer value 9.0 (a stun, a big shield)     -> s=0.75 -> x3.83
        best offer value 30+ (a fight-changing effect)  -> s≈0.91 -> x5.1
    So a creature holding a stun is roughly 3x more likely to reach for DEBUFF than one holding a
    minor slow — and the moment that stun goes on cooldown, `_can_use` drops it from the set and the
    appetite falls back to whatever the backup offers. **Cooldowns change personality, per turn,
    with no extra code.**

    THE HEAL/SHIELD SCALES exist because those kinds have no `magnitude` to read. They convert an
    amount into the same "≈1.0 is ordinary" space: a heal for 33% of the target's max HP scores
    0.33 * 3.0 = 1.0. Tune the two scalars, not the formula.


================================================================================
## 11. THE ESTIMATOR  (ai_estimate.gd + one addition to combat_math.gd)
================================================================================
Dry-running damage is the difference between "attacks the lowest-HP target" and "notices its fire
attack bounces off the fire elemental and switches to the ice one". The rule is that it goes
**through the real pipeline** — a second copy of the damage formula that drifts from the first is
the worst outcome available here.

### 11.1 `CombatMath.preview()` — a non-rolling `resolve()`
`resolve()` today ROLLS twice: `CombatDodge.rolls_dodge` at stage 0 (with an early return) and
`CombatCrit.rolls_crit` at stage 3. Neither may happen during a dry run. The refactor:

    _resolve_core(attacker, defender, ability, points, scaling_bonus, extra_pierce) -> Dictionary
        Stages 1, 2, 2b ONLY (pre-mitigation, mitigation, damage_taken). Plus the two CHANCES,
        computed but NOT rolled: dodge_chance, crit_chance, crit_mult. NO RNG. NO mutation.
    resolve(...)   = _resolve_core + the dodge roll (early return) + the crit roll. Byte-for-byte
                     the same behaviour as today — a pure extract; the AI landing must not change a
                     single damage number in a player's fight.
    preview(...)   = _resolve_core + an `expected` field:
                     expected = post
                              * (1 - dodge_chance/100)
                              * (1 + (crit_chance/100) * (crit_mult - 1))
                     with dodged = false, is_crit = false.

`_resolve_core` is side-effect-free today: it only calls `get_effective`,
`CombatBuffs.resist_mult_bonus`, `CombatMitigation.apply`, `CombatDodge.chance` and
`CombatCrit.chance`, none of which mutate. **Verify that again at implementation time.** Hoarfrost is
the standing hazard: it is consumed in `take_damage`, not in `resolve`, and it must stay there —
otherwise the AI silently eats the player's combo just by thinking about it.

### 11.2 `AIEstimate` — what the layers actually call
    expected_damage(actor, tgt, ability, slot) -> float
        rank = combat._ability_rank(actor, ability); calls preview(); returns `expected`, then folds
        in the riders that are cheap and deterministic:
          - `damage_per_debuff_element` (Snap) — multiply by the live matching debuff count.
            **NOT optional**: Snap deals literally 0 with no matching debuff, and an AI that does not
            know that will cast it into nothing all day.
          - `pierce_per_debuff_element` (Cryonecrosis) — pass as `extra_pierce`, as `_use_ability`
            does.
          - `shatter_*` — add the %-max-HP term ONLY when the target carries a matching debuff (the
            same gate `_apply_shatter` uses).
        Ignores: on-hit riders, spirit effects, applies_buff. Documented as ignored, not forgotten.

    effective_hp(tgt, element)   §6.2.
    best_attack(actor, tgt) -> {ability, slot, expected}   max over usable ATTACK-class pairs. Feeds
        lethal / kill_fraction / threat / ally_power / element_advantage.
    entry_value(...)   §10.2.

### 11.3 COST CONTROL
One `preview` is a handful of dictionary lookups and floats. Rules that keep it that way:
  - Cache every estimate on the AIContext, keyed (ability_id, target). One action = one cache.
  - Cache every built buff entry the same way, keyed (ability_id, rank).
  - `threat` estimates against the ACTOR only, never all-pairs.
  - **Skip any signal whose every consuming gain is 1.0 on this unit.** A creature with
    `ai_caution 1.0` never computes `threat` at all, and that is the single biggest saving — most
    creatures leave most gains off.
A 6-unit fight with 4 abilities each lands around 100 previews per turn, which is nothing. Revisit if
a fight ever runs 12 units x 10 abilities.


================================================================================
## 12. THE `ai_smart` GATE  (why a boss reads Magnificence and a wolf does not)
================================================================================
Three signals describe the player's COUNTERPLAY rather than the battlefield: `resist_chance` (their
Magnificence), `dodge_chance` (their Alacrity) and `element_advantage` (their resistances). All three
return **0.0** unless `actor.body.get_effective("ai_smart") >= 0.5`, and because 0 is the no-op
signal (§6.1), every gain term that reads them vanishes with no branch at any call site.

**THIS IS A PLAYER-FEEDBACK DECISION, NOT A DIFFICULTY ONE.** If every enemy avoided casting into a
wall of Magnificence, a player who invested heavily in Magnificence would see *nothing* — the debuffs
would simply stop coming, and the stat would feel like it did nothing. Because most enemies are not
smart, they cast anyway, the debuff bounces, and `tgt.float_resist()` puts a visible RESIST on
screen. **The stat pays off in the most legible way available: the enemy tries and fails, on camera,
every turn.** That float already exists in `_maybe_apply_buff` — the feedback loop is built, and this
gate is what keeps it firing.

Smart units are then a genuine escalation. A miniboss with `ai_smart = 1.0` and
`ai_resist_awareness = 0.15` stops feeding your Magnificence and starts hunting whoever on your side
does NOT have it — which is a different, harder fight, and reads as intelligence rather than as a
stat check.

    WHO IS SMART:  minibosses and bosses, plus a few "caster" archetypes where cunning IS the
                   fantasy (`warlock`). Never a beast, never a minion, never a swarm unit.
    THE COMBO IT ENABLES:  `ai_smart` is a stat, so a debuff can strip it —
                   "Daze: 2 turns, mods:{ai_smart: -1.0}" makes a boss stop reading your defences.
                   That is a player-side counterplay to enemy intelligence, in one BuffLibrary entry.
    WHAT IS *NOT* GATED:  lethality, shields, health, severity, threat, combos. A dumb brute still
                   finishes a kill, still notices a shield, still avoids the scariest thing if its
                   archetype says to. Stupidity here means "does not read your stat sheet", not
                   "does not have instincts".


================================================================================
## 13. THE ARCHETYPE CATALOGUE  (ai_rules.gd)
================================================================================
### 13.1 HOW AN ENTRY WORKS
`CharacterBase.ai` is already a String on every body, already read by combat, already settable from a
module or a spec, and today only understands `"none"`. It stays the routine selector, and each entry
supplies TWO things:

    RULES[id] = {
      "target_gains": { "offense": [ {signal, stat}, ... ], "debuff": [...], "buff": [...] },
      "preset":       { "ai_intent_offense": 0.9, "ai_bloodlust": 40.0, ... },
      "smart":        false,
      "notes":        "one line of design intent",
    }

  - `target_gains` is the WIRING — which signals are even consulted. Omit an intent and it falls
    back to `"standard"`'s wiring, so a preset states only its differences. `"standard"` is complete.
  - `preset` is the STAT BLOCK. It is applied to a body **only where the module or spec has not set
    that stat itself**, so a module can name an archetype and still override two numbers. Applied at
    context-build time, not baked into base_stats, so it never pollutes a save.
  - Unknown id -> falls back to `"standard"` with a `push_warning`. Never a crash, and never a
    silent pass (a silent pass is what a typo costs today; worth fixing here).

Below, every archetype lists only its DELTAS from `standard`. Anything unlisted is the §5 default.
Each entry names its ONE SIGNATURE gain and its TEXTURE set, per §4.6 — the signature is what the
player will name the creature by after one fight; the texture is what stops it being a rule.

### 13.2 BASELINE
    none        Passes its turn. UNCHANGED, and still the default on every existing creature, so
                landing the AI changes nothing in any current fight until a module opts in.

    standard    The §5 defaults exactly. A generic soldier: attacks whoever is most magnetic,
                lunges at an available kill, defends when badly hurt, buffs a hurt ally if it can.

    erratic     ai_decisiveness 0.0, ai_focus 0.0.
                Uniform random across every viable intent and legal target. A mad beast, a
                possessed thing, a confused summon. Also the single best debugging archetype —
                if `erratic` crashes, the bug is in the plumbing, not the scoring.

### 13.3 OFFENSE FAMILY
    brute       intent off 0.85 / def 0.05 / buff 0 / deb 0 · ai_focus 1.0 · magnetism 130
                SIGNATURE  none — deliberately.   TEXTURE  ai_efficiency 2.0.
                Pure magnetism targeting with a kill instinct and one small opinion about who is
                soft. The wall you hit first. Its whole design value is being the control case that
                proves magnetism works, so it stays almost bare on purpose.

    assassin    intent off 0.90 / deb 0.15 / def 0.05 · ai_focus 2.5 · magnetism 55
                SIGNATURE  ai_bloodlust 40        (+ ai_opportunism 30 — see §4.6 on why a binary
                                                   lethal gain is allowed past the texture band)
                TEXTURE    ai_efficiency 3.0 · ai_pressure 2.5 · ai_grudge 2.0 · ai_caution 0.7
                6.3x on a half-dead target, 15.9x on a quarter-dead one. The texture decides WHICH
                of two equally-wounded targets it takes — the difference between "goes for the hurt
                one" and "hunts". Low own magnetism, so it is hard to pull off its victim.

    executioner intent off 0.85 · ai_bloodlust 4 · ai_finisher 40
                SIGNATURE  ai_opportunism 60
                TEXTURE    ai_efficiency 3.5 · ai_pressure 2.0 · ai_gluttony 1.4
                The inverse of the assassin: barely cares that you are hurt, cares enormously that
                you are KILLABLE. Ignorable until the moment it isn't. Pairs beautifully with an
                assassin — one softens, the other cashes in.

    coward      intent off 0.60 / def 0.30 · ai_panic 12 · magnetism 70
                SIGNATURE  ai_caution 0.12
                TEXTURE    ai_efficiency 2.5 · ai_pressure 2.0 · ai_grudge 0.6
                Beats up whoever can't hurt it and turtles the moment it is threatened. A great
                early teaching enemy: it punishes leaving a squishy unit exposed. Note ai_grudge
                BELOW 1.0 — the same signal used as avoidance, so it also shies off the carry.

    duelist     intent off 0.85 · ai_focus 4.0 · ai_opportunism 12
                SIGNATURE  ai_caution 6.0
                TEXTURE    ai_grudge 3.0 · ai_efficiency 0.8 · ai_pressure 1.6
                Attracted to threat rather than repelled by it, and drawn to the party's PROVEN
                damage engine as well as its momentary one. Locks onto your biggest gun and does not
                let go. The exact opposite of `coward` from the same two stats.

    berserker   intent off 0.70 / def 0.05 · ai_panic 0.2 · ai_opportunism 15
                SIGNATURE  ai_bloodrage 10   (an INTENT gain — the only archetype whose signature
                                              lives in layer 1 rather than layer 2)
                TEXTURE    ai_efficiency 2.5 · ai_caution 1.5 · ai_pressure 1.5
                Gets ANGRIER as it dies instead of more careful, and wades toward danger rather than
                away. At 25% HP its offense appetite is x5.6 and its defensive appetite is
                effectively gone. Kill it fast.

    titan_slayer intent off 0.85 · ai_bloodlust 0.5
                SIGNATURE  ai_gluttony 6.0
                TEXTURE    ai_efficiency 0.7 · ai_grudge 2.0 · ai_shield_aversion 1.0
                Attracted to HEALTHY targets, repelled by wounded ones — the creature whose damage
                scales off max or current HP. The reason both health gains default to OFF (§8.2),
                and the clearest case of an auxiliary turned DOWN rather than up: efficiency below
                1.0 makes it seek the target its damage does NOT cut through easily, which is
                exactly right for a %-max-HP scaler. Shields do not deter it either.

    shield_reaver intent off 0.85
                SIGNATURE  ai_shield_aversion 3.5   (both the intent and the target term)
                TEXTURE    ai_efficiency 2.0 · ai_pressure 2.2 · ai_grudge 1.8
                Drawn to shields rather than deterred by them. Punishes a shield-stacking build and
                makes ai_shield_aversion visibly not a constant.

    spirit_leech intent off 0.55 / deb 0.35 · ai_prudence 1.0
                SIGNATURE  ai_spirit_hunger 6.0
                TEXTURE    ai_pressure 3.0 · ai_grudge 2.5 · ai_efficiency 1.8 · ai_thirst 8.0
                Hunts full Spirit bars, and presses whoever is already out of answers. Wants a
                ZAP!-shaped ability. Its raised ai_thirst means it also drinks what it steals —
                making the player spend before it acts, a pressure nothing else in the roster
                applies.

    chevalier   intent off 0.75 / def 0.20 · ai_focus 2.0 · magnetism 120
                SIGNATURE  ai_spare_child 0.05   (a child is ~20x less likely to be struck)
                TEXTURE    ai_spare_female 0.5 · ai_caution 3.0 · ai_efficiency 1.5 ·
                           ai_grudge 2.2
                A knightly enemy that seeks out the party's strongest fighter and visibly declines
                to hit the ones it considers non-combatants. The restraint gains ONLY read a `figure`
                the author actually set (§5.7) — against an all-NONE party it is simply a duelist
                with good manners, which is the correct graceful degradation.

    lockjaw     intent off 0.45 / deb 0.50 · ai_focus 2.5
                SIGNATURE  ai_pressure 12.0
                TEXTURE    ai_efficiency 2.0 · ai_grudge 3.0 · ai_prudence 2.0 · ai_tidiness 0.6
                The cooldown predator: it piles onto whoever has the least kit left. **Wants the
                cooldown-extension mechanic from §19.13** and is only half itself without it — with
                that ability it can lock one party member out of their rotation entirely, which is
                why §19.13 also specifies the cap that stops it being miserable.

### 13.4 CONTROL FAMILY
    hexer       intent deb 0.80 / off 0.25 · ai_offer_drive 8
                SIGNATURE  ai_tidiness 0.15
                TEXTURE    ai_prudence 2.2 · ai_efficiency 1.8 · ai_grudge 2.0 · ai_pressure 1.6
                Spreads debuffs evenly across your whole party, favouring the healthy (its hexes
                will live longer there) and the carry. The archetype that teaches the player what
                severity even is.

    plaguebearer intent deb 0.80 / off 0.25 · ai_tidiness 1.0 · ai_focus 3.0
                SIGNATURE  ai_spite 4.0
                TEXTURE    ai_pressure 2.5 · ai_efficiency 2.0 · ai_prudence 1.8
                The mirror image: piles everything on ONE victim until they fall over. Same intent
                weights as the hexer, opposite tidiness, and it plays completely differently.

    sapper      intent deb 0.70 / off 0.35 · ai_prudence 2.5
                SIGNATURE  ai_sapper 6.0
                TEXTURE    ai_grudge 3.5 · ai_pressure 2.0 · ai_efficiency 1.5
                Hexes your most dangerous unit specifically — by BOTH measures, the momentary
                (`threat`) and the historical (`reputation`) — then moves on once that one is loaded
                and tidiness wins. Emergent behaviour from two gains pulling against each other.

    disabler    intent deb 0.75 / off 0.30 · ai_prudence 2.5 · ai_offer_drive 10
                SIGNATURE  ai_priority 3.0 ON ITS STUN/SILENCE .tres — not a stat at all
                TEXTURE    ai_grudge 3.0 · ai_pressure 2.5 · ai_efficiency 1.5
                The archetype that proves §9.3: the preference lives on the ABILITY, because a stat
                cannot name one. Won't waste a stun on something already dying, and prefers to lock
                down the party member who actually does the damage.

    combo_setter intent deb 0.60 / off 0.50 · ai_tidiness 0.5
                SIGNATURE  ai_combo_drive 10.0
                TEXTURE    ai_efficiency 2.5 · ai_prudence 2.0 · ai_pressure 1.5
                Applies its mark, then the combo signal flips and its OFFENSE targeting slams into
                the marked unit for the Shatter/Snap payoff. Wants a matching debuff + payoff pair;
                Hoarfrost + Shatter already exists.

    lockjaw     — see §13.3. Filed under offense because its intent weights lean that way, but it
                belongs to this family in spirit and pairs naturally with a `disabler`.

    warlock     SMART. ai_smart 1.0 · ai_decisiveness 3.0 · intent deb 0.70 / off 0.40 · magnetism 90
                SIGNATURE  ai_resist_awareness 0.15  (the whole point: it stops feeding your
                                                      Magnificence and hunts whoever lacks it)
                TEXTURE    ai_element_savvy 3.5 · ai_grudge 3.0 · ai_efficiency 2.5 · ai_pressure 2.0
                A miniboss. Picks the element you are soft to, the party member who has been carrying
                you, and the moment your kit is spent. The escalation §12 is built to deliver.

### 13.5 SUPPORT FAMILY
    medic       intent buff 0.70 / def 0.30 / off 0.15 · ai_triage 6 · ai_altruism 8
                ai_self_buff 0.15 · ai_offer_drive 8 · magnetism 85
                SIGNATURE  ai_mercy 25
                TEXTURE    ai_vigilance 2.5 · ai_favoritism 2.0 · ai_thirst 6.0
                Triage nurse. Goes to whoever is worst off, leans slightly toward keeping the
                party's damage engine alive, rarely helps itself, and shields itself only when
                genuinely threatened. The "kill the healer first" enemy.

    warden      intent buff 0.55 / def 0.35 · ai_mercy 6
                SIGNATURE  ai_vigilance 8.0
                TEXTURE    ai_favoritism 3.0 · ai_triage 2.5 · ai_thirst 5.0
                Preemptive rather than reactive: shields whoever is about to be HIT, not whoever is
                already hurt. Reads as prescience because it is reading `incoming_pressure`.

    zealot      intent buff 0.60 / off 0.30 · ai_mercy 3
                SIGNATURE  ai_favoritism 6.0
                TEXTURE    ai_vigilance 3.0 · ai_triage 2.0 · ai_thirst 5.0
                Buffs the STRONGEST ally rather than the neediest — and with `ally_power` and
                `reputation` both available it can be pointed at either "who hits hardest now" or
                "who has hit hardest all campaign". Changes which enemy the player kills first.

    martyr      intent buff 0.65 / def 0.10 · ai_mercy 20 · ai_altruism 8
                SIGNATURE  ai_self_buff 0.0
                TEXTURE    ai_triage 5.0 · ai_vigilance 3.0 · ai_favoritism 2.0
                Literally never targets itself with a buff. Will die holding the line. One stat at
                its extreme, producing a whole personality.

    cleanser    intent buff 0.60 / def 0.25 · ai_mercy 5
                SIGNATURE  ai_triage 20
                TEXTURE    ai_vigilance 2.5 · ai_favoritism 2.0
                Targets the most debuff-loaded ally. **BLOCKED — no cleanse ability exists yet**
                (nothing calls `CombatBuffs.remove`). Authored and inert until one does; listed so
                the gap is visible. §19.3.

    summoner    intent buff 0.60 / off 0.30 / def 0.10 · ai_retinue 4 · ai_focus 1.5
                SIGNATURE  ai_retinue_drive 12.0
                TEXTURE    ai_mercy 4.0 · ai_vigilance 3.0 · ai_panic 8.0 · ai_efficiency 2.0
                Refills its retinue as it thins, and gets increasingly frantic about it — at one
                summon left alive `party_depletion` is 0.75 and the BUFF intent is multiplied by
                12^0.75 = 6.4x. Its raised panic means a summoner alone and hurt turtles while it
                rebuilds. **BLOCKED — no summon mechanic exists yet. §19.14.**

### 13.6 DEFENSIVE FAMILY
    turtle      intent def 0.60 / off 0.35 · ai_defense_sat 0.10 · magnetism 150
                SIGNATURE  ai_panic 20
                TEXTURE    ai_efficiency 2.0 · ai_grudge 2.0 · ai_thirst 5.0
                Hunkers hard the moment it is hurt, and is very magnetic, so it eats attention. A
                damage sponge that makes the player choose between chewing through it and ignoring it.

    bulwark     intent def 0.40 / buff 0.30 / off 0.30 · ai_panic 8
                SIGNATURE  magnetism 180 + a self-buff carrying `mods:{magnetism: +300}`
                TEXTURE    ai_vigilance 4.0 · ai_efficiency 1.8 · ai_grudge 1.8
                A real TAUNT, expressed entirely in the existing buff system. The one archetype that
                actively MANIPULATES the targeting layer rather than just reading it — and the proof
                that magnetism being a normal buffable stat was the right call.

    stalwart    intent off 0.70 / def 0.20 · ai_opportunism 10
                SIGNATURE  ai_panic 1.5   (a signature by its LOWNESS)
                TEXTURE    ai_efficiency 2.0 · ai_pressure 1.8 · ai_grudge 1.5
                Barely reacts to its own danger. Steady, relentless, boring on purpose — the
                baseline against which panicky archetypes read as panicky.

### 13.7 THE SMART TIER (a convention, not a family)
Any archetype above becomes its miniboss/boss version by setting `ai_smart 1.0` plus the awareness
cluster — `ai_resist_awareness 0.15`, `ai_element_savvy 3.0`, and usually `ai_decisiveness 3.0`.
`warlock` is that treatment applied to `hexer`. Do the same to `assassin` for a boss assassin, and so
on; there is no need for a doubled catalogue.

### 13.8 THE TABLE, AT A GLANCE
    id             off   def   buf   deb   SIGNATURE                       TEXTURE (the small ones)
    -------------------------------------------------------------------------------------------
    none            —     —     —     —    (passes)
    standard       .50   .15   .10   .15   —                               —
    erratic        .50   .15   .10   .15   ai_decisiveness 0               —
    brute          .85   .05   .00   .00   — (raw magnetism)               efficiency
    assassin       .90   .05   .00   .15   ai_bloodlust 40                 effic · pressure · grudge · caution
    executioner    .85   .10   .00   .00   ai_opportunism 60               effic · pressure · gluttony
    coward         .60   .30   .00   .10   ai_caution 0.12                 effic · pressure · grudge(0.6)
    duelist        .85   .10   .00   .00   ai_caution 6.0                  grudge · effic(0.8) · pressure
    berserker      .70   .05   .00   .00   ai_bloodrage 10                 effic · caution · pressure
    titan_slayer   .85   .10   .00   .00   ai_gluttony 6.0                 effic(0.7) · grudge · shield
    shield_reaver  .85   .10   .00   .00   ai_shield_aversion 3.5          effic · pressure · grudge
    spirit_leech   .55   .15   .00   .35   ai_spirit_hunger 6.0            pressure · grudge · effic · thirst
    chevalier      .75   .20   .00   .05   ai_spare_child 0.05             spare_female · caution · effic · grudge
    lockjaw        .45   .05   .00   .50   ai_pressure 12.0                effic · grudge · prudence · tidiness
    hexer          .25   .15   .05   .80   ai_tidiness 0.15                prudence · effic · grudge · pressure
    plaguebearer   .25   .15   .05   .80   ai_spite 4.0                    pressure · effic · prudence
    sapper         .35   .15   .00   .70   ai_sapper 6.0                   grudge · pressure · effic
    disabler       .30   .15   .00   .75   ai_priority 3.0 (on the ability) grudge · pressure · effic
    combo_setter   .50   .10   .00   .60   ai_combo_drive 10               effic · prudence · pressure
    warlock        .40   .20   .10   .70   ai_resist_awareness 0.15 [smart] savvy · grudge · effic · pressure
    medic          .15   .30   .70   .05   ai_mercy 25                     vigilance · favoritism · thirst
    warden         .10   .35   .55   .05   ai_vigilance 8.0                favoritism · triage · thirst
    zealot         .30   .15   .60   .05   ai_favoritism 6.0               vigilance · triage · thirst
    martyr         .20   .10   .65   .05   ai_self_buff 0.0                triage · vigilance · favoritism
    cleanser       .10   .25   .60   .05   ai_triage 20  [BLOCKED]         vigilance · favoritism
    summoner       .30   .10   .60   .00   ai_retinue_drive 12 [BLOCKED]   mercy · vigilance · panic · effic
    turtle         .35   .60   .05   .10   ai_panic 20                     effic · grudge · thirst
    bulwark        .30   .40   .30   .05   magnetism 180 + a taunt         vigilance · effic · grudge
    stalwart       .70   .20   .05   .10   ai_panic 1.5 (low)              effic · pressure · grudge
    ally_attack   1.00   .00   .00   .00   (see §14)
    ally_defense   .20   .60   .30   .05   (see §14)
    ally_neutral   .50   .20   .25   .20   (see §14)
    ally_heal      .00   .05  1.00   .00   (see §14)
    ally_support   .20   .15   .60   .35   (see §14)

**A NEW ARCHETYPE IS ONE DICTIONARY ENTRY.** A new SIGNAL is one function in AISignals plus one line
in the dispatcher. A new GAIN is one line in `Stats.default_base_stats()`. That is the entire
extension story, and it is why the catalogue is a table rather than 31 subclasses.


================================================================================
## 14. ALLIES — THE SAME PIPELINE, A DIFFERENT CHOOSER
================================================================================
Allies eventually run this system with the player choosing a general archetype, and later — via a
FRIENDSHIP mechanic, to be designed separately — unlocking direct control. Nothing in this design
blocks either, and two small things need to be true for it to land cleanly:

### 14.1 THE FIVE PRESETS
    ally_attack    off 1.00, everything else 0.0. Never heals, never defends. Pure damage.
    ally_defense   def 0.60 / buff 0.30 / off 0.20 · ai_vigilance 6 · ai_panic 8. Protects the party.
    ally_neutral   the `standard` block with ai_self_buff 0.40 — a rounded companion that will look
                   after itself.
    ally_heal      buff 1.00, everything else 0.0, plus `ai_priority 0.0` on any non-heal ability in
                   its loadout. Heals or does nothing.
    ally_support   buff 0.60 / deb 0.35 / off 0.20 · ai_offer_drive 8. Buffs and debuffs; attacks
                   only when it has nothing better, which is exactly what offer_drive delivers.

### 14.2 WHAT THIS CHANGES IN THE DESIGN
  - `ai_mercy` / `ai_triage` / `ai_vigilance` stop being flavour and become the ally's actual job.
    Tune them against ally play, not against enemy play — an ally that heals the wrong party member
    is far more annoying than an enemy that buffs the wrong one.
  - **SETTLED (rev3): AI ALLIES ARE OMNISCIENT.** `threat`, `ally_power` and `softness` all read
    other units' loadouts and stat blocks, and an ally is allowed to. A companion that plays badly
    feels worse than one that plays suspiciously well — the player asked it to help. Two practical
    consequences: an ally will pre-emptively shield against a boss ability the player has not seen
    yet (correct, and it doubles as a TELL — a watchful player learns to read their warden), and no
    "known abilities" bookkeeping is needed anywhere in the design.
  - **`reputation` is the ally signal that matters most.** `damage_rating` is stored per unit in
    `Character.damage_history` (§6.8), so an ally the player has built as support genuinely reads
    low and one built as a glass cannon genuinely reads high — which is what makes `zealot`-style
    ally behaviour ("buff whoever is actually carrying") work off the player's real build choices
    rather than a designer's guess. Author the player's own entry under the reserved key "player"
    so an ally can favour or protect them by the same measure.
  - Presets must be PLAYER-FACING strings eventually ("Aggressive", "Protective", "Balanced",
    "Healer only", "Support"). Keep the id -> label mapping in AIRules beside the preset so the UI
    has one source.
  - Direct control is a THIRD path, not a fourth layer: with friendship unlocked, combat routes the
    ally through the wheel instead of `AITurn.run`. `_loadout_for` and `_use_ability` already work
    for any unit, so the plumbing exists. The AI does not need to know about it.

### 14.3 WHAT IS DEFERRED
The friendship mechanic itself — how it is earned, what it unlocks, whether an ally can refuse an
order — is out of scope here and gets its own design pass. This section exists so the AI is not
built in a way that has to be undone for it.


================================================================================
## 15. THE PICK, AND TUNING BY DYNAMIC RANGE  (ai_pick.gd)
================================================================================
### 15.1 THE ROULETTE
    AIPick.weighted(scores: Array[float], exponent := 1.0) -> int      # -1 if all zero
        w[i]  = pow(maxf(0.0, scores[i]), exponent)
        total = Σ w
        if total <= 0: return -1
        roll  = rng.randf() * total                                     # [0, total)
        acc = 0.0
        for i in w.size():
            acc += w[i]
            if roll < acc: return i
        return w.size() - 1                                             # float-drift guard

    The brief's worked example (25, 60, 100, 400 -> total 585):
        roll <  25 -> target 1 | 25..85 -> target 2 | 85..185 -> target 3 | 185..585 -> target 4
    (the brief said "more than 85 but less than 186 hits target 3" — same interval, one-off slip at
    the top; the cumulative bound is 185. Written as a strict `roll < acc` walk it cannot be got
    wrong.)

    Layers 1, 2 and 3 ALL end here. One implementation, one RNG, one place to unit-test the
    off-by-ones, one place to add a "don't repeat last turn's choice" rule later. Do not write three
    roulettes.

### 15.2 THE EXPONENT
    0.0   every non-zero option equally likely (a confused unit — `erratic`)
    1.0   proportional to score (the brief's model)
    1.5   the default: real preference, real upsets
    2-4   strongly favours the best while leaving genuine surprises (a boss)
    8+    effectively argmax (a calculating machine)
    Applied as `pow(score, k)` rather than a softmax so a ZERO STAYS ZERO — a non-viable option is
    impossible at every exponent, which a softmax would not guarantee.

### 15.3 HOW BIG SHOULD A NUMBER BE?  (the table this whole rev exists for)
"Small weight variance feels random; large weight variance feels intentional." Here is the
arithmetic behind that. To pick your preferred option with probability P, against (n-1) alternatives
all sitting at weight 1, its weight must be:

    W = P·(n-1) / (1-P)

    targets |  50%   75%   90%   95%   99%
    --------+-----------------------------------
       2    |    1     3     9    19    99
       3    |    2     6    18    38   198
       4    |    3     9    27    57   297
       5    |    4    12    36    76   396
       6    |    5    15    45    95   495

    READ IT LIKE THIS: in a four-unit party, an assassin that should go for the quarter-health
    target ~90% of the time needs an effective 27x. `ai_bloodlust 40` gives 15.9x at that health
    (≈84%), and `ai_focus 1.5` raises it to 15.9^1.5 = 63x (≈95%). **That is the intended pairing:
    the gain sets the shape, the exponent sets the conviction.**

    RULES OF THUMB:
      - Anything below 2x is invisible in play. If a term deserves to exist, give it at least 4.
      - 8-15 is the band where a preference reads as a *decision* to the player.
      - Above 40 you have written a rule, not a preference — fine for `lethal`, wrong for taste.
      - Terms MULTIPLY (§4.5). Three 4x preferences is 64x, which is a rule you did not mean to
        write. When something feels over-tuned, count the terms before shrinking the gains.

### 15.4 RNG AND DETERMINISM
`AIPick.rng` is a `RandomNumberGenerator` owned by the AI, seeded from the clock by default and
settable (`AIPick.seed(n)`). One seedable source means a fight can be replayed exactly for a bug
report — worth having from day one, and free.


================================================================================
## 16. THE RUNNER  (ai_turn.gd — the loop, the ladder, the guards)
================================================================================
### 16.1 THE ONLY CHANGE TO combat.gd
    func _take_ai_turn(u: BattleCharacter) -> void:
        if u == null or u.body == null or not u.is_alive(): return
        if CombatBuffs.is_stunned(u.body):
            print("[combat] %s is stunned and loses its turn." % u.unit_name); return
        if u.ai == "none":
            print("[combat] %s does nothing." % u.unit_name); return
        await AITurn.run(self, u)
`end_player_turn`'s loop must `await` it (it already re-checks `_battle_over` after each unit, which
is what makes the await safe).

### 16.2 THE ACTION LOOP
    while true:
        if combat._battle_over or not u.is_alive() or CombatBuffs.is_stunned(u.body): break
        if actions_taken >= MAX_ACTIONS_PER_TURN: break                       # §16.3
        ctx = AIContext.build(combat, u)                                       # FRESH every action
        if ctx.usable_pairs.is_empty(): break
        decision = decide(ctx)                                                 # 3 layers + ladder
        if decision == null: break
        await combat.get_tree().create_timer(AI_ACTION_DELAY).timeout          # §16.4
        combat._use_ability(u, decision.ability, decision.target, decision.slot)
        actions_taken += 1
        if u.ap <= combat.AP_EPSILON: break
**The context is rebuilt every action, never reused.** After one action HP moved, a debuff landed, a
cooldown started and the AP dropped — a second action decided from stale state is the classic bug.

### 16.3 THE GUARDS (each exists because something in the codebase can actually cause it)
    MAX_ACTIONS_PER_TURN = 8   ZAP! is `action_cost 0.0`, `cooldown 0` (ABILITY_PRIMER §8 flags it).
                               A loop that stops only on AP will never stop on a unit holding it.
    _battle_over after every _use_ability   it runs _check_victory / _check_defeat internally, and
                               _win() awaits 2s then navigates away.
    is_alive() every iteration a thorns / High Voltage reflect can kill the acting unit on its own
                               action.
    is_stunned() every iteration   nothing stuns mid-turn today, but _use_blocked checks it and the
                               loop should agree.
    slot index always passed   never -1; a -1 slot silently skips the cooldown.

### 16.4 PACING
COMBAT C4.10: enemy turns resolve instantly inside `end_player_turn`, so the whole enemy phase would
land in one frame and read as a single blur. The AI is what makes that visible, so the AI owns the
fix: `AI_ACTION_DELAY` (~0.45s) before each action, and a longer beat between units.
LATER: an INTENT TELEGRAPH — "the Ice Spirit is preparing to defend" — is a natural fit, because
Layer 1 produces exactly that string one beat before the action. Design the debug log's intent line
so it can become that label.

### 16.5 THE FALLBACK LADDER
    1. Roll an intent. If Layer 2 or Layer 3 fails for it, ZERO that intent and re-roll from the
       remaining non-zero scores. (Do not fall straight to offense — a medic whose heal target
       evaporated should try its shield before it starts swinging.)
    2. All four exhausted -> OFFENSE with the best usable ATTACK against the highest-magnetism legal
       hostile. Deterministic, no roulette. **The brief's "the default answer is simple offense".**
    3. No usable attack either -> pass, print why, spend no AP, break.
    Every rung logs under `is_debug()`. A unit that silently does nothing is the hardest AI bug to
    find, and today's `"none"` behaviour is exactly that — do not reproduce it.

### 16.6 DEBUG OUTPUT (gated by `GameManager.is_debug()`, per CORE §5B)
One block per decision, showing the GAIN LEDGER — every term, its signal, its gain and its product —
because with exponential terms, "why is that number 63" is otherwise unanswerable:

    [ai] Ice Spirit (assassin) turn 4  ap 1.0  smart:no
      intent   off 750.0  = 50.0 x finisher^1.00(15.00)   <- LETHAL AVAILABLE
               def  17.3  = 15.0 x panic^0.15(1.23) x sat^0.00(1.00)
               buf   0.0  NOT VIABLE (no buff-tagged usable ability)
               deb  22.5  = 15.0 x tidiness^0.50(0.50) x offer^0.62(3.00)
      -> OFFENSE (roll 0.04 of 1.00)
      target   Player  100 -> 1590  [bloodlust^0.75 = 15.91, opportunism^1 = 30.00 ... ]
               Ally    100 ->  100  [no terms fired]
      -> Player (roll 0.31)
      ability  Frost Bolt 1.62 (exp 71 vs 66 ehp — LETHAL) | Rime Touch 0.21
      -> Frost Bolt (slot 0)
Build this in Phase 0, before any tuning. Tuning exponential systems without a ledger is guesswork.


================================================================================
## 17. WORKED EXAMPLES
================================================================================
### 17.1 THE HEXER — spreading, not stacking
An `ice_spirit` with `ai = "hexer"`, facing a player at 40% HP carrying two ice debuffs, and an ally
at full health carrying none. Loadout: Frost Bolt (attack), Hypothermia (debuff, entry_value ≈ 3.0,
off cooldown), Rime Guard (self shield). Not smart.

    LAYER 1
      offense  base 25.0. best_kill_fraction 0.35 -> 15^0.35 = 2.60 -> 65.0
               mean hostile shield_frac 0 -> x1.00.  bloodrage off.       => 65.0
      debuff   base 80.0. party_debuff_pressure = (0.50 + 0.00)/2 = 0.25
                          -> 0.15^0.25 = 0.62                            -> 49.8
               offer_strength = squash(3.0/3.0) = 0.50 -> 8^0.50 = 2.83  -> 141.0
               resist_awareness: NOT SMART, signal 0 -> x1.00            => 141.0
      defense  base 15.0. self_danger 0.15 -> 4^0.15 = 1.23              => 18.4
      buff     0.0 — no buff-tagged usable ability. NOT VIABLE.
      exponent 1.5 -> weights 524 : 1674 : 79 : 0.  DEBUFF ~73%, OFFENSE ~23%.
      Rolled: DEBUFF.

    LAYER 2  (hexer debuff wiring: tidiness on debuff_severity, prudence on hp_frac)
      Player: 100 x 0.15^0.50 (tidiness) x 1.5^0.40 (prudence) = 100 x 0.387 x 1.176 = 45.5
      Ally:   100 x 0.15^0.00               x 1.5^1.00          = 100 x 1.000 x 1.500 = 150.0
      exponent ai_focus 1.5 -> 307 : 1837.  The ALLY is ~86% likely.
      **The clean, healthy target draws the hex** — spread, not stack, and the long debuff goes on
      something that will live long enough to suffer it.
      Rolled: Ally.

    LAYER 3  Only Hypothermia is debuff-tagged, usable and legal -> slot 1.
    RESULT   _use_ability(ice_spirit, hypothermia, ally, 1). AP 1.0 - 1.0 = 0 -> turn ends.

    NOTE WHAT DID NOT HAPPEN: it did not pile a third debuff on the nearly-dead player. But it WOULD
    have attacked ~23% of the time — and if Hypothermia had been on cooldown, offer_strength would
    have collapsed to whatever the backup offered and OFFENSE would have won outright.

### 17.2 THE ASSASSIN — and why the numbers are inflated
Same fight, `ai = "assassin"`, facing the player at 25% HP and the ally at 100%. Frost Bolt's
expected damage is 71; the player's effective HP is 66.

    LAYER 1
      offense  base 90.0. best_kill_fraction = 1.0 (LETHAL) -> 15^1.0 = 15.0  => 1350.0
      debuff   base 15.0 x tidiness^0.25 (0.25^0.25 = 0.71) x offer^0.50 (6^0.5 = 2.45)  => 26.0
      defense  base  5.0 x panic^0.10 (4^0.10 = 1.15)                         =>  5.7
      exponent 1.5 -> 49,600 : 133 : 14.  OFFENSE at 99.7%.
      An available kill is not a preference; it is effectively a rule. That is intended.

    LAYER 2  (assassin offense wiring; both candidates sit at the default magnetism 100 — the
              assassin's own 55 is what makes IT hard to target, and never enters this sum)
      Player  (25% HP, killable): 100 x bloodlust^0.75 (40^0.75 = 15.91) x opportunism^1 (30.0)
                                = 47,730
      Ally    (100% HP, not killable): 100 x bloodlust^0.00 (1.00) x opportunism^0 (1.00) = 100
      exponent ai_focus 2.5 -> the player is ~99.99% likely.
      With the rev1 LINEAR model and a coefficient of 2.5, those same two would have been 288 vs 100
      — a 74/26 split, which reads as the AI *wandering*. **This is the whole argument for §4.**

    LAYER 3  Frost Bolt 1.62 (lethal bonus) vs Rime Touch 0.21 -> Frost Bolt at 98%.
    RESULT   The player dies. Which is what an assassin standing over a quarter-health target should
             mean, every single time, and what the brief asked for.


================================================================================
## 18. BUILD ORDER  (each phase is playable and independently valuable)
================================================================================
PHASE 0 — THE SPINE  (no intelligence at all; proves the seam)
    ai_pick.gd, ai_gain.gd, ai_context.gd, ai_turn.gd. `ai = "standard"` picks a UNIFORM random
    legal (ability, target) pair from the usable set and casts it. Plus the debug ledger and the
    pacing await. **The highest-value single step in the document**: the moment it lands, enemies
    attack, and every on-struck / on-hit rider in the game gets exercised in both directions for the
    first time (COMBAT C4.1 has been waiting on this). Expect real bugs here — they will be in the
    riders, not in the AI.

PHASE 1 — LAYER 1  (intent)
    The four intent weights + ai_decisiveness + the OFFENSE_FLOOR. ai_intent.gd with VIABILITY only
    (no context multipliers yet). Ability intent-tag derivation in ability.gd. Target and ability
    still uniform. Tune the four base weights until archetypes feel distinct at all.

PHASE 2 — LAYER 2  (magnetism + the gain curve)
    ai_signals.gd (the cheap signals first), ai_target.gd, ai_rules.gd with `"standard"` plus three
    contrasting presets — `brute`, `assassin`, `titan_slayer` — because the whole point of §4 is that
    those three should feel like different creatures with the same loadout. **Resolve the §7.2 spec
    ambiguity before this phase.**

PHASE 3 — THE ESTIMATOR
    The `CombatMath` extract-refactor (`_resolve_core` / `preview`) — the riskiest change in the
    plan, because it touches the live damage path. Do it ALONE, in its own pass, and verify a handful
    of player hits produce identical numbers before and after. Then ai_estimate.gd, then
    lethal / kill_fraction / threat / element_advantage / ally_power.

PHASE 3b — THE AUXILIARY SIGNALS  (rev3; slots in right after the estimator)
    The cheap ones first, because they need nothing new: `cooldown_load`, `is_female` / `is_child`
    (plus the `figure` enum on CharacterBase), `spirit_need` / `spirit_relief`. Then `softness`,
    which needs the estimator from Phase 3. Then `reputation`, which is the only one with real
    plumbing: `BattleCharacter.damage_dealt`, the accumulation in the three damage paths, the
    fight-end rollup, and `Character.damage_history` in the save (§6.8 — no SAVE_VERSION bump, but
    do verify that against the CURRENT `load_game`, which discards on a version mismatch).
    `party_depletion` lands here too but stays inert until §19.14 exists.
    THEN, and only then, give three archetypes their TEXTURE sets (§4.6) and check that a
    `standard`, an `assassin` and a `titan_slayer` with identical loadouts read as three creatures.

PHASE 4 — LAYER 3, THE CONTEXT MULTIPLIERS AND OFFER STRENGTH
    ai_ability.gd's real scoring; the §7.2 multipliers; `ai_priority` + `ai_intents` on abilities;
    `entry_value` and `offer_strength`; the `ai_thirst` universal rider. The AI becomes recognisably
    smart here, and buff/debuff creatures stop casting their worst option.

PHASE 5 — CONTENT
    A `magnitude` / `weight` pass over the whole of buff_library.gd (§10.1) — without it both
    severity AND offer_strength are flat. Then the rest of the §13 catalogue, and a stat block per
    existing creature. This is the phase where the game actually changes feel.

PHASE 6 — POLISH AND THE SMART TIER
    `ai_smart` and the three gated signals (§12); the `warlock`-tier presets; intent telegraphs;
    per-unit pacing; an inspector-friendly panel for the gain ledger.

PHASE 7 — ALLIES (whenever the ally system is wanted)
    The five presets, the player-facing labels, and the tuning pass against ally play. §14.

ALL THREE OPEN QUESTIONS ARE NOW ANSWERED (rev3) — nothing is blocking the build order:
    (a) DEFENSE reads the ACTOR'S OWN danger. `self_danger` is the design; there is no `ai_vulture`
        term and none is planned. §7.2.
    (b) AI ALLIES ARE OMNISCIENT about enemy loadouts, deliberately. §14.2.
    (c) THE PHASE-5 MAGNITUDE PASS IS GREEN-LIT. `magnitude` and `weight` may be re-authored across
        the whole buff catalogue, so SEVERITY AND OFFER STRENGTH ARE THE REAL MODEL — not a
        fallback to be designed around. Two consequences worth stating plainly:
          - Nothing needs a derived-from-raw-payload backup path. Do not build one.
          - Phase 5 stops being optional polish and becomes the phase the design DEPENDS on. Until
            it lands, severity is a duration-weighted count and offer strength cannot tell a stun
            from a slow, and every buff/debuff/support archetype will read blunt. Budget it as real
            work, not a tuning afternoon: ~30 catalogue entries, each needing one considered
            `magnitude` and occasionally a `weight`.
        RECOMMENDED ANCHORS for that pass, so the numbers are comparable across authors:
            0.5   a small single-stat buff (+5 Alacrity, 3 turns) — pass_current
            1.0   an ordinary debuff or a modest DoT — arc_burn, hypothermia
            2.0   a strong multi-turn package — electrostimulated, scaled_skin
            3.5   a heavy resistance or damage swing — guard_4, wraith_form
            5.0   hard control: a stun, a silence — stunned, silenced
            weight stays 1.0 unless the AI should care out of proportion to the size (a combo
            enabler like hoarfrost is small in magnitude and large in weight).


================================================================================
## 19. OPEN THREADS
================================================================================
1. `CombatMath.preview` must be a pure EXTRACT — verify no damage number changes for the player.
   The one change in the plan that can break something a player already feels.
2. `magnitude` / `weight` are 1.0 across the entire buff catalogue today. The Phase-5 pass that fixes
   this is GREEN-LIT (rev3, §18) and the design now DEPENDS on it. Until it lands, severity is
   a duration-weighted COUNT and offer_strength cannot tell a stun from a slow. The AI works; it
   judges bluntly.
3. **No cleanse exists.** Nothing in the game calls `CombatBuffs.remove`, so the `cleanser`
   archetype (§13.5) and the DEFENSE need-fit's cleanse branch (§9.2) are both authored and inert.
   One BUFF-kind ability with a "remove N debuffs" rider would activate both.
4. `_loadout_for` returns `body.abilities` verbatim — a module listing a PASSIVE there hands the AI
   an uncastable slot. Filter + warn at context-build time (§9.4).
5. `ALL_ENEMIES` / `ALL_ALLIES` don't fan out (COMBAT C4.2). The AI treats them as single-target and
   will badly under-value them once they do. When fan-out lands, an AoE's Layer-2 score should become
   the SUM over the affected set rather than a single pick — leave a comment at the pick site.
6. No memory between turns. A unit will not save a cooldown for turn 3, and two enemies will
   independently pick the same target and overkill it. Seams: an `AIMemory` keyed by unit for the
   first, a per-PHASE shared "already committed damage" context for the second. Do the second early
   if overkill reads badly.
7. Enemy phase pacing (COMBAT C4.10) is the AI's problem now, not combat's (§16.4).
8. ZAP!'s `action_cost 0.0 / cooldown 0` shape means any future free ability is an infinite-loop risk
   for the action loop. `MAX_ACTIONS_PER_TURN` covers it; a free ability with a real resource cost is
   the better long-term answer.
9. `threat` and `ally_power` read other units' loadouts — the AI has perfect information. Fine for
   enemies; §14.2 argues it should stay on for allies too, but that is a call, not a fact.
10. The AI never uses items or consumables — there is no consumable system in combat yet (CORE §11
    lists it as a stub). When there is, it is a fifth intent, not a special case inside OFFENSE.
11. Nothing here reads `Ability.requires` / `required_level` (nothing does, CORE §10) or the
    `resistible` / `transient` buff fields. `transient` ("attack-applied flavour") may deserve a
    severity discount once it means something.
13. **COOLDOWN EXTENSION — a mechanic that does not exist, wanted by `ai_pressure` / `lockjaw`.**
    The want: an ability that ADDS turns to the target's slots that are ALREADY cooling. Sketch:
        Ability: `cooldown_add: int` (+ `cooldown_add_ranks`), `cooldown_add_only_cooling: bool = true`
        Combat:  a `_apply_cooldown_pressure(caster, ability, tgt, rank)` beside `_apply_shatter`,
                 walking `tgt.cooldowns` and adding to each entry (or to every slot, when the flag
                 is false). `BattleCharacter.cooldowns` is already per-unit and per-slot, so the
                 data is right there; this is a ~15-line addition, not a system.
    THREE THINGS TO GET RIGHT:
      - **Cap it.** `ai_pressure` targets whoever is most locked out, and this ability makes them
        more locked out — a self-reinforcing loop that can take a party member out of the fight
        entirely. Cap total added cooldown per slot (suggest 3 turns over its base) or the
        archetype is misery rather than menace.
      - It cannot be a BUFF. Buffs know nothing about slots, and slot indices are combat-local — so
        this has to be an ability rider, not a BuffLibrary entry. That is a real asymmetry with
        every other control effect in the game and worth remembering.
      - It should be RESISTIBLE somehow, or a smart player has no counterplay. The cleanest hook is
        to route it through `CombatResist` like a debuff even though it is not one.
14. **SUMMONING — a mechanic that does not exist, wanted by `party_depletion` / `summoner`.** Sketch:
        Ability: `Kind.SUMMON` (6) + `summon_character: StringName` + `summon_count: int`
        Combat:  a SUMMON branch in `_use_ability` calling `CharacterRegistry.create(id)` then the
                 existing `_spawn_unit(body, caster.team, body.ai)`.
    THE ONE REAL HAZARD: `_units` is being ITERATED in `end_player_turn` when a non-player unit
    acts, so appending to it mid-loop is undefined behaviour in the making. Queue summons into a
    pending list and flush them at the phase boundary, or iterate a duplicate of `_units`. Also
    needed: `_build_health_bars` re-run (or an incremental add) so the new unit gets a bar, and
    `_layout_column` re-run so the column re-spaces. Neither is hard; both are easy to forget.
    Worth deciding early: do summons grant XP / loot? `_win()` builds its party list from `_units`,
    so a summoned ally would show up on the victory screen unless filtered.
15. No positioning, no bluffing, no difficulty scaling, no learning. Difficulty is `ability_ranks`
    and stat overrides (CHARACTER_PRIMER §3b calls ranks "a free difficulty dial") — keep it there.

Ground rule, as everywhere: pasted code = ground truth and overrides this doc. Request the real
script — or just the relevant function — for real work.
