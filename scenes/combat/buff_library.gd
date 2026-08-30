extends RefCounted
class_name BuffLibrary

## ============================================================================
## BUFF LIBRARY  —  the named buff / debuff catalogue (class_name global)
## ============================================================================
## The concrete buffs live here, in readable code, keyed by a string id. An
## Ability .tres names one of these ids in its `applies_buff` field; combat calls
## BuffLibrary.build(id, caster, target) when that ability resolves and applies
## the returned entry with CombatBuffs.apply().
##
## Each builder returns a FRESH entry dict (via Buff.make), so callers never share
## state. `caster` / `target` are passed for future scaling (e.g. a DoT that
## scales off the caster's stats); the current catalogue uses fixed numbers.
##
## To add a buff: add a case to build() (or call Buff.make directly). To retune
## the existing ones, edit the numbers here — this is the single tuning spot.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

## Thorns tuning: per stack, reflect this much flat damage + this fraction of the
## damage taken back at the attacker. The single tuning spot for thorns.
const THORNS_FLAT := 20.0
const THORNS_PCT := 0.15

## Every real element's defense (resist) stat key, for "all resists" effects.
static func _all_resist_mods(delta: float) -> Dictionary:
	var mods := {}
	for e in Stats.REAL_ELEMENTS:
		mods[Stats.defense_key(e)] = delta
	return mods

## Build a buff entry by id. Returns {} (empty) for an unknown / blank id.
static func build(id: String, caster: CharacterBase = null, target: CharacterBase = null) -> Dictionary:
	match id:
		# --- Bet: +100% to ALL resists, 5 turns, stacks infinitely -----------
		# A true MULTIPLICATIVE resist bonus (see CombatMath): resist_mult 1.0 per
		# stack => x2 resists at one stack, x3 at two, ... max_stacks 0 = unlimited.
		"resist_up_100":
			return Buff.make({
				"id": "resist_up_100",
				"source": "Bet — Resist Up",
				"desc": "Increases all resistances by 100% (multiplicative). Stacks without limit.",
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": 5,
				"stackable": true,
				"max_stacks": 0,             # 0 => unlimited
				"weight": 1.0,
				"resistible": false,
				"resist_mult": 1.0,          # per stack: +100% of resists
			})

		# --- Gimel: +25 spirit per turn, 8 turns -----------------------------
		"spirit_regen_25":
			return Buff.make({
				"id": "spirit_regen_25",
				"source": "Gimel — Spirit Font",
				"desc": "Restores 25 spirit at the start of each of your turns for 8 turns.",
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": 8,
				"stackable": false,
				"weight": 1.0,
				"resistible": false,
				"spirit_per_turn": 25.0,
			})

		# --- Dalet: -15 flat to all resists AND drain 20 spirit/turn, 5 turns -
		"resist_down_drain":
			return Buff.make({
				"id": "resist_down_drain",
				"source": "Dalet — Sap",
				"desc": "Lowers all resistances by 15 (flat) and drains 20 spirit at the start of each turn for 5 turns.",
				"kind": Buff.KIND_DEBUFF,
				"visible": true,
				"duration": 5,
				"stackable": false,
				"weight": 1.0,
				"resistible": true,
				"mods": _all_resist_mods(-15.0),   # flat resist reduction (additive)
				"spirit_per_turn": -20.0,          # drain
			})

		# --- Thorns: when struck, deal damage back to the attacker ------------
		# The first user of the generic "when struck do X" system (see
		# CombatBuffs.fire_on_struck). Each stack reflects THORNS_FLAT flat damage
		# PLUS THORNS_PCT of the damage taken back at the attacker. Stacks up to 5.
		"thorns":
			return Buff.make({
				"id": "thorns",
				"source": "Thorns",
				"desc": "When struck, reflects %d (+%d%% of the damage taken) back to the attacker. Stacks up to 5." % [int(THORNS_FLAT), int(round(THORNS_PCT * 100.0))],
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": 5,
				"stackable": true,
				"max_stacks": 5,
				"weight": 1.0,
				"resistible": false,
				"on_struck": [
					{"effect": "reflect", "amount": THORNS_FLAT, "percent": THORNS_PCT, "element": "physical"},
				],
			})

		# --- Frost Ward: a PERMANENT innate ice resistance -------------------
		# Used as a PERMANENT buff (duration -1, so it never counts down): a
		# character module lists "frost_ward" in its permanent_buffs and combat
		# auto-applies it at battle start. Flat +40 ice defence via mods, so it
		# shows in the stat readouts like any flat resist.
		"frost_ward":
			return Buff.make({
				"id": "frost_ward",
				"source": "Frost Ward",
				"desc": "Wreathed in frost: +40 ice resistance. Permanent.",
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": -1,              # -1 => permanent, never expires
				"stackable": false,
				"weight": 1.0,
				"resistible": false,
				"element": "ice",
				"mods": {"ice_defense": 40.0},
			})

		# --- Frost Mantle: a PERMANENT reflect aura --------------------------
		# The boss's extra permanent buff: reflects a little ice damage back
		# whenever it is struck (via the generic on_struck "reflect" system —
		# see CombatBuffs.fire_on_struck). Permanent (duration -1).
		"frost_mantle":
			return Buff.make({
				"id": "frost_mantle",
				"source": "Frost Mantle",
				"desc": "A permanent mantle of frost: reflects 15 (+10% of the damage taken) as ice when struck.",
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": -1,              # -1 => permanent, never expires
				"stackable": false,
				"weight": 1.0,
				"resistible": false,
				"element": "ice",
				"on_struck": [
					{"effect": "reflect", "amount": 15.0, "percent": 0.10, "element": "ice"},
				],
			})

		# --- Guard (Tav): reduce ALL incoming damage until your next turn -----
		# Four rank-clones, identical EXCEPT the reduction fraction. combat.gd maps
		# the Guard ability's invested rank -> guard_1..guard_4 (see its
		# _maybe_apply_buff). The reduction is a flat incoming-damage multiplier read
		# by CombatMath (damage_taken_mult, stored in mods, additive around 0:
		# -0.80 => take 80% less). All four share id "guard" so re-casting refreshes
		# duration instead of stacking (two guards would be far too strong). Retune
		# the four numbers here — this is the single tuning spot.
		"guard_1":
			return _make_guard(0.80)
		"guard_2":
			return _make_guard(0.90)
		"guard_3":
			return _make_guard(0.95)
		"guard_4":
			return _make_guard(0.99)

		# --- Scaled Skin (Yesod): 20% damage resist + heal over time ----------
		# Three rank-clones, identical EXCEPT their duration (5/6/7 turns) and the
		# heal-per-turn fraction of the TARGET's Instinct (30/40/50%). combat.gd maps
		# the Scaled Skin ability's invested rank -> scaled_skin_1..3 (see its
		# _maybe_apply_buff), exactly like Guard. The 20% resist is a flat incoming-
		# damage multiplier (damage_taken_mult -0.20 in mods, read by CombatMath) and
		# is the same at every rank. The per-turn heal is snapshotted from the target's
		# Instinct at cast time into heal_per_turn (see _make_scaled_skin). All three
		# share id "scaled_skin" so re-casting refreshes duration instead of stacking.
		"scaled_skin_1":
			return _make_scaled_skin(5, 0.30, target)
		"scaled_skin_2":
			return _make_scaled_skin(6, 0.40, target)
		"scaled_skin_3":
			return _make_scaled_skin(7, 0.50, target)

		# --- Hematopoiesis (Altar of Water): pure heal over time --------------
		# Three rank-clones differing in duration (4/5/6 turns) and the heal-per-turn
		# fraction of the TARGET's (Vigor + Instinct) (100/200/325%). combat.gd maps
		# the ability's invested rank -> hematopoiesis_1..3 (see its _maybe_apply_buff),
		# exactly like Scaled Skin. The per-turn heal is snapshotted from the target's
		# stats at cast time into heal_per_turn (see _make_hematopoiesis). All three
		# share id "hematopoiesis" so re-casting refreshes duration instead of stacking.
		"hematopoiesis_1":
			return _make_hematopoiesis(4, 1.00, target)
		"hematopoiesis_2":
			return _make_hematopoiesis(5, 2.00, target)
		"hematopoiesis_3":
			return _make_hematopoiesis(6, 3.25, target)

		# --- Crystaline (Tzaddi): +100% to ALL resists, 5 turns --------------
		# A single-rank self buff: a true MULTIPLICATIVE resist bonus (resist_mult 1.0
		# => x2 all resists), read by CombatMath. Unlike resist_up_100 (Netzach) this
		# one does NOT stack — Crystalize is a 1-rank ability, so re-casting just
		# refreshes the 5-turn duration. Applied by the Crystalize ability.
		"crystaline":
			return Buff.make({
				"id": "crystaline",
				"source": "Crystaline",
				"desc": "Encased in crystal: all resistances increased by 100% for 5 turns.",
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": 5,
				"stackable": false,
				"weight": 1.0,
				"resistible": false,
				"element": "ice",
				"resist_mult": 1.0,          # +100% of all resists (multiplicative)
			})

		# --- Gliogenesis (Peh): passive per-turn health + spirit regen ---------
		# Four rank-clones, applied to the player as a PERMANENT buff (duration -1)
		# at combat start while the Gliogenesis passive sits in the wheel (see
		# combat._apply_passive_buffs). They differ only in the % of max health healed
		# per turn (2.5/5/7.5/10%) and the flat spirit gained per turn (0/0/4/6). The
		# heal is a LIVE fraction of current max HP (heal_pct_per_turn), read each turn.
		"gliogenesis_1":
			return _make_gliogenesis(0.025, 0.0)
		"gliogenesis_2":
			return _make_gliogenesis(0.05, 0.0)
		"gliogenesis_3":
			return _make_gliogenesis(0.075, 4.0)
		"gliogenesis_4":
			return _make_gliogenesis(0.10, 6.0)

		# --- Stunned: blocks all actions for 1 turn ---------------------------
		# Applied by Shatter when it consumes an ice debuff. The `stun` flag is read by
		# CombatBuffs.is_stunned (the wheel greys out for a stunned PLAYER; enemy turn
		# logic will consume it once the enemy action engine exists). Deliberately has
		# NO element tag so a later Shatter cannot consume the stun as an "ice debuff".
		"stunned":
			return Buff.make({
				"id": "stunned",
				"source": "Stunned",
				"desc": "Stunned: cannot act for 1 turn.",
				"kind": Buff.KIND_DEBUFF,
				"visible": true,
				"duration": 1,
				"stackable": false,
				"weight": 1.0,
				"resistible": false,
				"stun": true,
			})

		# --- Hypothermia (Nun): -alacrity + spirit drain, 8 turns --------------
		# Two rank-clones differing only in the alacrity multiplier (-10% / -12%).
		# combat.gd maps the ability rank -> hypothermia_1/2 in _maybe_apply_buff.
		"hypothermia_1":
			return _make_hypothermia(-0.10)
		"hypothermia_2":
			return _make_hypothermia(-0.12)

		# --- Frost (Menorah): -alacrity + ice DoT, 2 turns --------------------
		# Two rank-clones differing in alacrity mult (-20% / -22%) and the ice DoT,
		# which is SNAPSHOTTED from the CASTER at cast: instinct_pct*Instinct +
		# vigor_pct*Vigor (50%/100% Instinct + 25% Vigor). Mapped by combat.gd rank.
		"frost_1":
			return _make_frost(-0.20, 0.5, 0.25, caster)
		"frost_2":
			return _make_frost(-0.22, 1.0, 0.25, caster)

		# --- Arc Burn (Neurostatic): a lightning DoT, ranks 1..3 ---------------
		# The per-turn damage is SNAPSHOTTED from the CASTER's Instinct at the moment
		# the debuff lands (the `frost` pattern), so it does not drift if the caster's
		# stats change mid-fight. 50 / 75 / 100% of Instinct for 3 turns.
		"arc_burn_1":
			return _make_arc_burn(0.50, caster)
		"arc_burn_2":
			return _make_arc_burn(0.75, caster)
		"arc_burn_3":
			return _make_arc_burn(1.00, caster)

		# --- Electromyogenesis: +Alacrity equal to a % of the CASTER's Instinct -
		# Ranks 1..4: 25/30/35/40% of Instinct, for 3/3/4/4 turns. Snapshotted at
		# cast (a flat `mods` bonus), so it is the caster's Instinct that matters
		# even when the buff is handed to an ally.
		"electromyogenesis_1":
			return _make_electromyogenesis(0.25, 3, caster)
		"electromyogenesis_2":
			return _make_electromyogenesis(0.30, 3, caster)
		"electromyogenesis_3":
			return _make_electromyogenesis(0.35, 4, caster)
		"electromyogenesis_4":
			return _make_electromyogenesis(0.40, 4, caster)

		# --- Energized Form: the lightning ultimate (single rank) --------------
		# +30 Alacrity, +50% to all lightning damage dealt (lightning_amp — the
		# (A+1) coefficient in CombatMitigation), and a rider that adds 45% of the
		# bearer's Vigor as Lightning damage to every hit it lands (on_hit_damage).
		"energized_form":
			return Buff.make({
				"id": "energized_form",
				"source": "Energized Form",
				"desc": "Energized: +30 Alacrity, +50% Lightning damage, and every hit deals an extra 45% of Vigor as Lightning damage.",
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": 5,
				"stackable": false,
				"element": "lightning",
				"weight": 2.0,
				"resistible": false,
				"mods": {
					"alacrity": 30.0,
					"lightning_amp": 0.50,
				},
				"on_hit_damage": [
					{"element": "lightning", "scale_stat": "vigor", "pct": 0.45},
				],
			})

		# --- Electrostimulated: a self/ally power buff with a lightning price ---
		# Ranks 1..3. Every turn the bearer TAKES lightning damage equal to a % of the
		# CASTER's Instinct (snapshotted, like Arc Burn) — 40/35/30%, i.e. the cost
		# SHRINKS as the ability ranks up — and in exchange gains flat Alacrity, Vigor,
		# Instinct and spirit regen for 6/8/10 turns.
		"electrostimulated_1":
			return _make_electrostimulated(6, 0.40, 10.0, 5.0, 5.0, caster)
		"electrostimulated_2":
			return _make_electrostimulated(8, 0.35, 20.0, 10.0, 10.0, caster)
		"electrostimulated_3":
			return _make_electrostimulated(10, 0.30, 30.0, 15.0, 15.0, caster)

		# --- Pass Current (Bread): the caster's half of the ability ------------
		# A small, flat self buff riding on an attack (applies_buff_self). Identical
		# at every rank — only Pass Current's damage and its Arc Burn scale up.
		"pass_current":
			return Buff.make({
				"id": "pass_current",
				"source": "Pass Current",
				"desc": "Carrying the current: +5 Alacrity for 3 turns.",
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": 3,
				"stackable": false,
				"weight": 1.0,
				"resistible": false,
				"element": "lightning",
				"mods": {"alacrity": 5.0},
			})

		# --- Lightning Shell (Geburah): overfilled spirit becomes shield -------
		# The passive_buff of the Lightning Shell passive, ranks 1..10. Every 5 points
		# of spirit that WOULD have refilled past the bearer's maximum are converted
		# into an absorbing shield worth (10..100% of Vitality + 10% of Instinct) —
		# read LIVE off the bearer at conversion time, so the shield tracks the stats.
		# The shield carries no decay spec, so it lasts until it is spent. The engine
		# side is BattleCharacter.change_spirit -> _convert_spirit_overflow.
		"lightning_shell_1":
			return _make_lightning_shell(1)
		"lightning_shell_2":
			return _make_lightning_shell(2)
		"lightning_shell_3":
			return _make_lightning_shell(3)
		"lightning_shell_4":
			return _make_lightning_shell(4)
		"lightning_shell_5":
			return _make_lightning_shell(5)
		"lightning_shell_6":
			return _make_lightning_shell(6)
		"lightning_shell_7":
			return _make_lightning_shell(7)
		"lightning_shell_8":
			return _make_lightning_shell(8)
		"lightning_shell_9":
			return _make_lightning_shell(9)
		"lightning_shell_10":
			return _make_lightning_shell(10)

		# --- High Voltage: Lightning Shell's rank-10 capstone ------------------
		# A permanent on-struck reflect scaled off the BEARER's own Instinct (35%),
		# dealt as Lightning. Attacks-only like every other on_struck reaction — a
		# spell cast at the bearer does not get shocked back.
		"high_voltage":
			return Buff.make({
				"id": "high_voltage",
				"source": "High Voltage",
				"desc": "High Voltage: anything that strikes you in melee takes 35% of your Instinct as Lightning damage.",
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": -1,              # -1 => permanent, never expires
				"stackable": false,
				"weight": 2.0,
				"resistible": false,
				"element": "lightning",
				"on_struck": [
					{"effect": "reflect", "scale_stat": "instinct", "pct": 0.35, "element": "lightning"},
				],
			})

		# --- Rime Skin (Vav): -50% healing + self-damage when struck, 4 turns --
		# One entry (identical at every rank; only the applying attack scales). The
		# healing cut is a healing_received_mult -0.5 in mods; the on_struck reaction
		# deals 5% of the bearer's own max HP as ice each time a sourced attack hits it.
		"rime_skin":
			return Buff.make({
				"id": "rime_skin",
				"source": "Rime Skin",
				"desc": "Rime Skin: healing received cut by 50%; when struck by an attack, takes 5% of maximum health as ice damage.",
				"kind": Buff.KIND_DEBUFF,
				"visible": true,
				"duration": 4,
				"stackable": false,
				"weight": 1.0,
				"resistible": true,
				"element": "ice",
				"mods": {"healing_received_mult": -0.5},
				"on_struck": [
					{"effect": "self_pct_max_hp", "percent": 0.05, "element": "ice"},
				],
			})

		# --- Hoarfrost (Yod): amplify the next ice instance, then consume ------
		# A stacking marker debuff. It carries no stats: ice_amp_per_stack is read by
		# CombatBuffs.apply_incoming_ice_amp when a sourced ice hit lands, which boosts
		# that hit by 20% per stack and removes the debuff. Unlimited stacking (0).
		"hoarfrost":
			return Buff.make({
				"id": "hoarfrost",
				"source": "Hoarfrost",
				"desc": "Hoarfrost: the next ice damage taken is increased by 20% per stack, then consumed.",
				"kind": Buff.KIND_DEBUFF,
				"visible": true,
				"duration": 1,
				"stackable": true,
				"max_stacks": 0,
				"weight": 1.0,
				"resistible": false,
				"element": "ice",
				"ice_amp_per_stack": 0.2,
			})

		# --- Silenced (Mind Freeze): block spirit-cost abilities for 3 turns ---
		# The `silence` flag is read by CombatBuffs.is_silenced — the wheel greys out
		# spirit-cost slots for a silenced PLAYER; enemy targeting/action AI will consume
		# it once that engine exists (mirrors how `stunned` is wired). Fixed 3-turn
		# duration at every rank, so no per-rank clones are needed.
		"silenced":
			return Buff.make({
				"id": "silenced",
				"source": "Silenced",
				"desc": "Silenced: cannot use spirit-cost abilities for 3 turns.",
				"kind": Buff.KIND_DEBUFF,
				"visible": true,
				"duration": 3,
				"stackable": false,
				"weight": 1.0,
				"resistible": true,
				"silence": true,
			})

		# --- Wraith Form (Mercy): a defensive self-buff with an on-hit rider ------
		# Applied to the caster by the Wraith Form ability (SELF target). For 5 turns:
		# take 50% less damage (damage_taken_mult -0.5, the Guard lever read by CombatMath),
		# +50% Instinct (a base-stat multiplier that shows in readouts), and — via
		# on_hit_apply (see CombatBuffs.fire_on_hit) — coat every target the wraith strikes
		# in a 1-turn Rime Skin (the existing rime_skin debuff, duration overridden to 1).
		# Single-rank, so re-casting just refreshes the duration.
		"wraith_form":
			return Buff.make({
				"id": "wraith_form",
				"source": "Wraith Form",
				"desc": "Wraith Form: takes 50% less damage and has +50% Instinct for 5 turns; every target struck is coated in Rime Skin.",
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": 5,
				"stackable": false,
				"weight": 1.0,
				"resistible": false,
				"mods": {"damage_taken_mult": -0.5},
				"mult": {"instinct": 0.5},
				"on_hit_apply": [
					{"buff": "rime_skin", "duration": 1},
				],
			})

		_:
			return {}

## Build a Guard damage-reduction buff: a self buff that reduces ALL incoming damage
## by `reduction` (0.80 = take 80% less) until the caster's next turn (duration 1, so
## it protects through the enemies' turn and expires at the start of the caster's next
## turn). The four Guard ranks are clones of this differing ONLY in `reduction`. Stored
## as a `mods` entry (damage_taken_mult, additive around 0) so CombatMath reads it via
## get_basket_bonus, exactly like the attacker-side damage_dealt_mult layer. All ranks
## share id "guard" so applying it refreshes duration instead of stacking.
static func _make_guard(reduction: float) -> Dictionary:
	return Buff.make({
		"id": "guard",
		"source": "Guard",
		"desc": "Guarding: takes %d%% less damage until your next turn." % int(round(reduction * 100.0)),
		"kind": Buff.KIND_BUFF,
		"visible": true,
		"duration": 1,
		"stackable": false,
		"mods": {"damage_taken_mult": -reduction},
	})

## Constant fraction of ALL incoming damage that Scaled Skin removes, at every rank
## (0.20 = take 20% less). The single tuning spot for the resist half of the buff.
const SCALED_SKIN_RESIST := 0.20

## Build a Scaled Skin buff: a target buff that reduces ALL incoming damage by
## SCALED_SKIN_RESIST and restores `heal_pct` of the TARGET's Instinct at the start
## of each of the target's turns, for `turns` turns. The three ranks are clones of
## this differing only in `turns` (5/6/7) and `heal_pct` (0.30/0.40/0.50). The resist
## is a `mods` damage_taken_mult (read by CombatMath, same lever as Guard); the heal
## is SNAPSHOTTED here from the target's effective Instinct into heal_per_turn (read
## each turn by CombatBuffs.collect_turn_start -> combat applies it via heal()). All
## ranks share id "scaled_skin" so applying it refreshes duration instead of stacking.
static func _make_scaled_skin(turns: int, heal_pct: float, target: CharacterBase) -> Dictionary:
	var instinct := 0.0
	if target != null:
		instinct = maxf(0.0, target.get_effective("instinct"))
	var heal := heal_pct * instinct
	return Buff.make({
		"id": "scaled_skin",
		"source": "Scaled Skin",
		"desc": "Scaled Skin: takes %d%% less damage and restores %d health at the start of each turn for %d turns." % [
			int(round(SCALED_SKIN_RESIST * 100.0)), int(round(heal)), turns],
		"kind": Buff.KIND_BUFF,
		"visible": true,
		"duration": turns,
		"stackable": false,
		"element": "toxic",
		"mods": {"damage_taken_mult": -SCALED_SKIN_RESIST},
		"heal_per_turn": heal,
	})

## Build a Hematopoiesis buff: a pure heal-over-time that restores `heal_pct` of the
## TARGET's (Vigor + Instinct) at the start of each of the target's turns, for `turns`
## turns. The three ranks are clones differing only in `turns` (4/5/6) and `heal_pct`
## (1.00/2.00/3.25). The heal is SNAPSHOTTED here from the target's effective Vigor and
## Instinct into heal_per_turn (read each turn by CombatBuffs.collect_turn_start ->
## combat applies it via heal()). No resist / mods — it is heal only. All ranks share
## id "hematopoiesis" so applying it refreshes duration instead of stacking.
static func _make_hematopoiesis(turns: int, heal_pct: float, target: CharacterBase) -> Dictionary:
	var stat_sum := 0.0
	if target != null:
		stat_sum = maxf(0.0, target.get_effective("vigor")) + maxf(0.0, target.get_effective("instinct"))
	var heal := heal_pct * stat_sum
	return Buff.make({
		"id": "hematopoiesis",
		"source": "Hematopoiesis",
		"desc": "Hematopoiesis: restores %d health at the start of each turn for %d turns." % [int(round(heal)), turns],
		"kind": Buff.KIND_BUFF,
		"visible": true,
		"duration": turns,
		"stackable": false,
		"element": "blood",
		"heal_per_turn": heal,
	})

## Build a Gliogenesis buff: a PERMANENT self buff that, at the start of each of the
## bearer's turns, restores `heal_pct` of the bearer's CURRENT max HP and grants
## `spirit` flat spirit. Unlike Scaled Skin / Hematopoiesis (which snapshot a flat
## heal from a stat at cast), the health regen here is LIVE via heal_pct_per_turn, so
## it tracks any change to max HP during the fight. The four Gliogenesis ranks are
## clones of this differing only in `heal_pct` and `spirit`. Re-applying refreshes
## (shared id "gliogenesis"); the passive re-grants it every combat.
static func _make_gliogenesis(heal_pct: float, spirit: float) -> Dictionary:
	var pct_txt := ("%.1f" % (heal_pct * 100.0)).trim_suffix(".0")
	var spirit_txt := "" if spirit <= 0.0 else " and %d spirit" % int(round(spirit))
	return Buff.make({
		"id": "gliogenesis",
		"source": "Gliogenesis",
		"desc": "Gliogenesis: restores %s%% of maximum health%s at the start of each turn." % [pct_txt, spirit_txt],
		"kind": Buff.KIND_BUFF,
		"visible": true,
		"duration": -1,               # permanent for the fight; re-granted each combat by the passive
		"stackable": false,
		"weight": 1.0,
		"resistible": false,
		"element": "spiritual",
		"heal_pct_per_turn": heal_pct,
		"spirit_per_turn": spirit,
	})

## Build a Hypothermia debuff: a multiplicative alacrity reduction plus a flat 5
## spirit drain per turn, for 8 turns. The two ranks differ only in `alac_mult`.
static func _make_hypothermia(alac_mult: float) -> Dictionary:
	return Buff.make({
		"id": "hypothermia",
		"source": "Hypothermia",
		"desc": "Hypothermia: %d%% alacrity and drains 5 spirit at the start of each turn (8 turns)." % int(round(alac_mult * 100.0)),
		"kind": Buff.KIND_DEBUFF,
		"visible": true,
		"duration": 8,
		"stackable": false,
		"weight": 1.0,
		"resistible": true,
		"element": "ice",
		"mult": {"alacrity": alac_mult},
		"spirit_per_turn": -5.0,
	})

## Build a Frost debuff: a multiplicative alacrity reduction plus an ice DoT for 2
## turns. The DoT is SNAPSHOTTED from the CASTER at cast time (instinct_pct*Instinct
## + vigor_pct*Vigor), mirroring how Scaled Skin snapshots its heal. The two ranks
## differ in `alac_mult` and `instinct_pct` (vigor share is the same 25%).
static func _make_frost(alac_mult: float, instinct_pct: float, vigor_pct: float, caster: CharacterBase) -> Dictionary:
	var dmg := 0.0
	if caster != null:
		dmg = instinct_pct * maxf(0.0, caster.get_effective("instinct")) + vigor_pct * maxf(0.0, caster.get_effective("vigor"))
	return Buff.make({
		"id": "frost",
		"source": "Frost",
		"desc": "Frost: %d%% alacrity and %d ice damage at the start of each turn (2 turns)." % [int(round(alac_mult * 100.0)), int(round(dmg))],
		"kind": Buff.KIND_DEBUFF,
		"visible": true,
		"duration": 2,
		"stackable": false,
		"weight": 1.0,
		"resistible": true,
		"element": "ice",
		"mult": {"alacrity": alac_mult},
		"dot": dmg,
		"dot_element": "ice",
	})

## Build an Arc Burn debuff (Neurostatic): a pure lightning DoT for 3 turns whose
## per-turn damage is SNAPSHOTTED from the caster's Instinct at application time
## (instinct_pct * Instinct), mirroring how Frost / Scaled Skin snapshot theirs.
static func _make_arc_burn(instinct_pct: float, caster: CharacterBase) -> Dictionary:
	var dmg := 0.0
	if caster != null:
		dmg = instinct_pct * maxf(0.0, caster.get_effective("instinct"))
	return Buff.make({
		"id": "arc_burn",
		"source": "Arc Burn",
		"desc": "Arc Burn: %d Lightning damage at the start of each turn (3 turns)." % int(round(dmg)),
		"kind": Buff.KIND_DEBUFF,
		"visible": true,
		"duration": 3,
		"stackable": false,
		"weight": 1.0,
		"resistible": true,
		"element": "lightning",
		"dot": dmg,
		"dot_element": "lightning",
	})


## Build an Electromyogenesis buff: flat Alacrity equal to `instinct_pct` of the
## CASTER's Instinct at cast time, for `turns` turns. Snapshotted, so handing it to an
## ally still pays out on the caster's Instinct.
static func _make_electromyogenesis(instinct_pct: float, turns: int, caster: CharacterBase) -> Dictionary:
	var alac := 0.0
	if caster != null:
		alac = instinct_pct * maxf(0.0, caster.get_effective("instinct"))
	return Buff.make({
		"id": "electromyogenesis",
		"source": "Electromyogenesis",
		"desc": "Electromyogenesis: +%d Alacrity (%d%% of Instinct) for %d turns." % [int(round(alac)), int(round(instinct_pct * 100.0)), turns],
		"kind": Buff.KIND_BUFF,
		"visible": true,
		"duration": turns,
		"stackable": false,
		"weight": 1.0,
		"resistible": false,
		"element": "lightning",
		"mods": {"alacrity": alac},
	})


## Build an Electrostimulated buff: a big flat stat package plus spirit regen, paid for
## with a self-inflicted lightning DoT equal to `instinct_pct` of the CASTER's Instinct
## (snapshotted at cast). The DoT runs through the bearer's own lightning resistance and
## `vulnerability` like any other DoT, so lightning resist is a real counterplay.
static func _make_electrostimulated(turns: int, instinct_pct: float, alac: float, vig: float, inst: float, caster: CharacterBase) -> Dictionary:
	var dmg := 0.0
	if caster != null:
		dmg = instinct_pct * maxf(0.0, caster.get_effective("instinct"))
	return Buff.make({
		"id": "electrostimulated",
		"source": "Electrostimulated",
		"desc": "Electrostimulated: +%d Alacrity, +%d Vigor, +%d Instinct and +5 spirit per turn, but take %d Lightning damage at the start of each turn (%d turns)." % [int(alac), int(vig), int(inst), int(round(dmg)), turns],
		"kind": Buff.KIND_BUFF,
		"visible": true,
		"duration": turns,
		"stackable": false,
		"weight": 2.0,
		"resistible": false,
		"element": "lightning",
		"mods": {
			"alacrity": alac,
			"vigor": vig,
			"instinct": inst,
		},
		"dot": dmg,
		"dot_element": "lightning",
		"spirit_per_turn": 5.0,
	})


## Build the Lightning Shell passive's hidden-machinery buff for invested `rank` (1..10).
## It carries no stat mods at all — its whole payload is the `overflow_shield` spec:
## every OVERFLOW_SHELL_PER_SPIRIT points of spirit the bearer would have gained above its
## maximum become an absorbing shield worth (rank x 10% of Vitality + 10% of Instinct).
## The scale fractions are read LIVE against the bearer when the conversion happens
## (BattleCharacter._convert_spirit_overflow), NOT snapshotted here, so the shield follows
## the bearer's Vitality and Instinct as gear and buffs move them. No "decay" key => the
## shield never decays and lasts until it is spent.
const OVERFLOW_SHELL_PER_SPIRIT := 5
const OVERFLOW_SHELL_VIT_PER_RANK := 0.10
const OVERFLOW_SHELL_INSTINCT := 0.10

static func _make_lightning_shell(rank: int) -> Dictionary:
	var r := clampi(rank, 1, 10)
	var vit := OVERFLOW_SHELL_VIT_PER_RANK * float(r)
	return Buff.make({
		"id": "lightning_shell",
		"source": "Lightning Shell",
		"desc": "Lightning Shell: every %d Spirit that would refill past your maximum becomes a shield worth %d%% of Vitality + %d%% of Instinct. The shield does not decay." % [
			OVERFLOW_SHELL_PER_SPIRIT, int(round(vit * 100.0)), int(round(OVERFLOW_SHELL_INSTINCT * 100.0))],
		"kind": Buff.KIND_BUFF,
		"visible": true,
		"duration": -1,              # -1 => permanent, never expires
		"stackable": false,
		"weight": 1.0,
		"resistible": false,
		"element": "lightning",
		"overflow_shield": {
			"per_spirit": OVERFLOW_SHELL_PER_SPIRIT,
			"scale": {
				"vitality": vit,
				"instinct": OVERFLOW_SHELL_INSTINCT,
			},
		},
	})


## True when `id` names a buff this library knows how to build.
static func has(id: String) -> bool:
	return not build(id).is_empty()

# ---------------------------------------------------------------------------
# Generic constructors — handy for building common effects from code without a
# catalogue entry (bleed/poison, a temporary max-HP / max-Spirit change, etc.).
# ---------------------------------------------------------------------------

## A bleed/poison DoT. `element` tints the ticking numbers and is stored as the
## DoT element; `dot_mult` is the flat per-DoT multiplier (default 1.0).
static func make_dot(id: String, source: String, amount: float, element: String, turns: int, dot_mult: float = 1.0, is_debuff: bool = true) -> Dictionary:
	return Buff.make({
		"id": id, "source": source, "desc": "%s: %d %s damage per turn." % [source, int(round(amount)), element],
		"kind": Buff.KIND_DEBUFF if is_debuff else Buff.KIND_BUFF,
		"visible": true, "duration": turns, "element": element, "resistible": true,
		"dot": amount, "dot_element": element, "dot_mult": dot_mult,
	})

## A temporary max-HP change (via hp_base, which max_hp() reads). Positive raises
## the ceiling; when it expires CombatBuffs re-clamps current HP down.
static func make_max_hp(id: String, source: String, delta: float, turns: int) -> Dictionary:
	return Buff.make({
		"id": id, "source": source, "desc": "%s: %+d maximum health." % [source, int(round(delta))],
		"kind": Buff.KIND_BUFF if delta >= 0.0 else Buff.KIND_DEBUFF,
		"visible": true, "duration": turns,
		"mods": {"hp_base": delta},
	})

## A temporary max-Spirit change (via the spirit base stat that max_spirit reads).
static func make_max_spirit(id: String, source: String, delta: float, turns: int) -> Dictionary:
	return Buff.make({
		"id": id, "source": source, "desc": "%s: %+d maximum spirit." % [source, int(round(delta))],
		"kind": Buff.KIND_BUFF if delta >= 0.0 else Buff.KIND_DEBUFF,
		"visible": true, "duration": turns,
		"mods": {"spirit": delta},
	})
