extends RefCounted
class_name CharacterRegistry

## ============================================================================
## CHARACTER REGISTRY  —  id -> character module  (class_name global)
## ============================================================================
## The single place that knows which character id maps to which module class.
## A fight spec names a character by id ({"character": "ice_spirit"}); combat asks
## the registry to build it. Adding a new character is two steps:
##   1. make its module in scenes/characters/units/<name>.gd (extends CharacterBase)
##   2. add one line to create() below.
##
## WHY A REGISTRY (and not CharacterBase.from_spec calling the modules directly):
## CharacterBase must NOT depend on its own subclasses (that would be a circular
## class dependency). The registry sits ABOVE both — it references the modules and
## CharacterBase, and nothing references the registry back.
##
## class_name global — RESTART Godot once after adding this file.
## ----------------------------------------------------------------------------

## Instantiate a fresh character by id. Returns null for an unknown id.
static func create(id: String) -> CharacterBase:
	match id:
		# --- the shared ice set (every campaign not yet written) ---------------
		"ice_spirit":
			return IceSpirit.new()
		"large_ice_spirit":
			return LargeIceSpirit.new()

		# --- ZONE 1 · THE ARCTIC ----------------------------------------------
		# Eight modules for seven fights. A creature earns a module by having its own
		# JOB; a VARIANT is a fight spec — which is why the two Shambling Corpses in
		# fight 2 are ONE module plus a {"level":2, "stats":{…}} override rather than
		# two files. See c1.gd.
		"shambling_corpse":
			return ShamblingCorpse.new()
		"shambling_guard":
			return ShamblingGuard.new()
		"frozen_corpse":
			return FrozenCorpse.new()
		"unknown_entity":
			return UnknownEntity.new()
		"old_ice":
			return OldIce.new()
		"inuit_hunter":
			return InuitHunter.new()
		"strapped_passenger":
			return StrappedPassenger.new()
		"the_scavenger":
			return TheScavenger.new()

		# --- ZONE 2b · GODTHAAB -----------------------------------------------
		# Sixteen modules for nine fights. Two of them SHARE A DISPLAY NAME
		# ("Sanitation Technician") on purpose — the ids do the distinguishing and
		# the player just sees two men in the same uniform.
		"wharfinger":
			return Wharfinger.new()
		"stevedore":
			return Stevedore.new()
		"security_guard":
			return SecurityGuard.new()
		"enforcer":
			return Enforcer.new()
		"registrar":
			return Registrar.new()
		"rotting_corpse":
			return RottingCorpse.new()
		"screaming_corpse":
			return ScreamingCorpse.new()
		"burning_hulk":
			return BurningHulk.new()
		"burning_corpse":
			return BurningCorpse.new()
		"sanitation_tech_prod":
			return SanitationTechProd.new()
		"sanitation_tech_hook":
			return SanitationTechHook.new()
		"sanitation_engineer":
			return SanitationEngineer.new()
		"sanitation_officer_net":
			return SanitationOfficerNet.new()
		"sanitation_officer_shield":
			return SanitationOfficerShield.new()
		"harbour_guard":
			return HarbourGuard.new()
		"chief_of_the_detail":
			return ChiefOfTheDetail.new()

		"player":
			return PlayerCharacter.new()
		_:
			return null

## True when `id` names a character module this registry knows how to build.
static func has(id: String) -> bool:
	return create(str(id)) != null

## Build a combatant from a fight spec Dictionary.
##   - If the spec names a "character" module, start from that module (its own
##     identity / stats / permanent buffs) and then layer any per-fight overrides
##     on top (name, level, stats{}, max_hp, color, size_scale, ai, current_hp,
##     permanent_buffs, abilities[], ability_ranks{}) via CharacterBase.apply_spec_overrides.
##   - Otherwise fall back to the plain-dictionary path (CharacterBase.from_spec),
##     so old-style inline specs (e.g. the training dummy) keep working unchanged.
static func build(spec: Dictionary) -> CharacterBase:
	var char_id := str(spec.get("character", ""))
	if char_id == "":
		return CharacterBase.from_spec(spec)
	var cb := create(char_id)
	if cb == null:
		push_warning("CharacterRegistry: unknown character id '%s' — using spec fallback." % char_id)
		return CharacterBase.from_spec(spec)
	CharacterBase.apply_spec_overrides(cb, spec)
	return cb
