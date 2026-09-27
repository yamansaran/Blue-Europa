class_name RigPiece
extends Resource

## ============================================================================
## RIG PIECE  —  one image on one rig part  (class_name global)
## ============================================================================
## The unit of rig art. A RigSkin (the base body) and an ItemLook (a piece of armour)
## are both just {part_id: RigPiece}. The part's JOINT is the origin; `offset` moves
## the image so its pivot sits on that joint. With NO texture the part keeps its
## code-drawn placeholder and `color` tints it instead — so a look can be authored
## (and seen) before its art exists. RIG_SPEC §4.
## ----------------------------------------------------------------------------

@export var texture: Texture2D = null
## Pixel offset of the image from the joint (Sprite2D.offset; centred image).
@export var offset: Vector2 = Vector2.ZERO
@export var scale: Vector2 = Vector2.ONE
@export var rotation_degrees: float = 0.0
## Multiplies the texture (white = as drawn).
@export var tint: Color = Color.WHITE
## Placeholder colour when there is no texture. Alpha 0 = "use the default".
@export var color: Color = Color(0, 0, 0, 0)
## This piece REPLACES the part's base image instead of sitting on top of it
## (a full helm over the head). Ignored on a base-skin piece.
@export var hides_base: bool = false
