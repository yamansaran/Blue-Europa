class_name RigSkin
extends Resource

## ============================================================================
## RIG SKIN  —  a body's BASE look  (class_name global)
## ============================================================================
## {part_id (StringName): RigPiece}. Parts it does not name keep the placeholder in
## the unit's model colour. A CharacterBase with no skin is the plain mannequin.
## Save one as a .tres and assign it on a module (`skin = preload(...)`). RIG_SPEC §4.
## ----------------------------------------------------------------------------

@export var pieces: Dictionary = {}

func piece(part_id: StringName) -> RigPiece:
	var p = pieces.get(part_id, pieces.get(String(part_id), null))
	return p as RigPiece
