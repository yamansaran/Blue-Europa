class_name RigPlans
extends RefCounted

## ============================================================================
## RIG PLANS  —  body plan id -> rig scene  (class_name global, static)
## ============================================================================
## A BODY PLAN is one skeleton: its bones, its parts, its draw order, its clips.
## Every unit that shares a plan shares its animations; what differs is the skin and
## the gear. Today there is one plan, "humanoid". A new creature shape (a quadruped,
## a spirit) is a new rig scene + one entry here — UnitRig finds the parts by
## scanning the scene, so no other code changes. RIG_SPEC §2, §7.
##
## CharacterBase.rig_plan names the plan; &"" = no rig (the unit keeps its
## rectangle / portrait).
## ----------------------------------------------------------------------------

const HUMANOID := &"humanoid"

const PLANS := {
	&"humanoid": {
		"scene": "res://scenes/characters/rig/humanoid_rig.tscn",
		# Equip slot key -> the parts that slot's armour covers (and tints, when the
		# item has no look). Weapon slots name their SOCKET part.
		"covers": {
			"head": [&"head"],
			"body": [&"torso", &"upper_arm_near", &"upper_arm_far", &"forearm_near", &"forearm_far"],
			"legs": [&"hip", &"thigh_near", &"thigh_far", &"calf_near", &"calf_far"],
			"gloves": [&"hand_near", &"hand_far"],
			"feet": [&"foot_near", &"foot_far"],
			"weapon_main": [&"weapon_main"],
			"weapon_off": [&"weapon_off"],
		},
	},
}

## Placeholder length (rig units) per weapon class.
const WEAPON_LENGTH := {
	&"blade": 52.0, &"blunt": 44.0, &"polearm": 96.0, &"gun": 40.0,
	&"bow": 58.0, &"staff": 90.0, &"shield": 30.0,
}

## item_type words -> weapon class (lower-case substring match, first hit wins).
const TYPE_WORDS := [
	["shield", &"shield"], ["buckler", &"shield"],
	["sword", &"blade"], ["blade", &"blade"], ["knife", &"blade"], ["dagger", &"blade"],
	["sabre", &"blade"], ["saber", &"blade"], ["cleaver", &"blade"],
	["axe", &"blunt"], ["hammer", &"blunt"], ["mace", &"blunt"], ["club", &"blunt"],
	["baton", &"blunt"], ["hook", &"blunt"], ["prod", &"blunt"],
	["spear", &"polearm"], ["pike", &"polearm"], ["halberd", &"polearm"], ["polearm", &"polearm"],
	["gun", &"gun"], ["pistol", &"gun"], ["rifle", &"gun"], ["revolver", &"gun"],
	["bow", &"bow"],
	["staff", &"staff"], ["wand", &"staff"], ["rod", &"staff"], ["sceptre", &"staff"],
]

static func has(plan: StringName) -> bool:
	return PLANS.has(plan)

static func scene_path(plan: StringName) -> String:
	return str(PLANS.get(plan, {}).get("scene", ""))

## The parts an equip slot's armour covers on this plan ([] = draws nothing).
static func covers(plan: StringName, slot_key: String) -> Array:
	return PLANS.get(plan, {}).get("covers", {}).get(slot_key, [])

## The weapon class an item is drawn as: its look's explicit class, else read from
## its item_type, else a blade (any weapon-slot item draws SOMETHING).
static func weapon_class_of(item) -> StringName:
	if item == null:
		return &"unarmed"
	var look = item.get("look")
	if look is ItemLook and (look as ItemLook).weapon_class != &"":
		return (look as ItemLook).weapon_class
	var t := str(item.get("item_type")).to_lower()
	for pair in TYPE_WORDS:
		if t.find(pair[0]) >= 0:
			return pair[1]
	return &"blade"

static func weapon_length(cls: StringName) -> float:
	return float(WEAPON_LENGTH.get(cls, 48.0))
