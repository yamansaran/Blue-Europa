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
		"ice_spirit":
			return IceSpirit.new()
		"large_ice_spirit":
			return LargeIceSpirit.new()
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
##     permanent_buffs) via CharacterBase.apply_spec_overrides.
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
