class_name ItemLook
extends Resource

## ============================================================================
## ITEM LOOK  —  how an equipped item is DRAWN on a rig  (class_name global)
## ============================================================================
## Hung on Item.look. Purely presentation — stats never read it. RIG_SPEC §4.
##   ARMOUR  fill `pieces` {part_id: RigPiece} for the parts it covers. A slot's
##           parts are listed in RigPlans.covers(); a piece for any other part is
##           still honoured (a cape on the torso from a head item, say).
##   WEAPON  fill the weapon block. With no texture the socket draws a placeholder
##           shape for `weapon_class`.
## An Item with NO look still shows: armour tints its slot's parts with a colour from
## the item id, a weapon draws the placeholder its item_type implies.
## ----------------------------------------------------------------------------

@export var pieces: Dictionary = {}

@export_group("Weapon")
## Which placeholder shape to draw and (Stage 2) which clip set to use:
## unarmed, blade, blunt, polearm, gun, bow, staff, shield. Blank = from item_type.
@export var weapon_class: StringName = &""
@export var texture: Texture2D = null
## The pixel point of the texture held in the fist.
@export var grip: Vector2 = Vector2.ZERO
## Extra rotation of the image in the fist, degrees.
@export var angle_degrees: float = 0.0
## Where a projectile / effect leaves, in the texture's pixel space (Stage 2).
@export var muzzle: Vector2 = Vector2.ZERO
## Placeholder weapon length in rig units (0 = the class default).
@export var length: float = 0.0
@export var tint: Color = Color.WHITE

func piece(part_id: StringName) -> RigPiece:
	var p = pieces.get(part_id, pieces.get(String(part_id), null))
	return p as RigPiece
