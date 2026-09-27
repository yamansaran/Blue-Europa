class_name ProjectileLook
extends Resource

## ============================================================================
## PROJECTILE LOOK  —  what a RANGED ability sends flying  (class_name global)
## ============================================================================
## Hung on Ability.projectile. null = the caster's WEAPON preset for an attack
## (for_weapon: a gun fires a bullet, a bow an arrow) or an orb in the element's
## colour for a spell. Presentation only. claude/RIG_SPEC.md §6, Stage 3 §12.
## ----------------------------------------------------------------------------

## How it is drawn when there is no texture.
enum Style { ORB, BULLET, ARROW, BOLT }

@export var style: Style = Style.ORB

@export var texture: Texture2D = null
## Orb colour when there is no texture. Alpha 0 = the element's colour.
@export var color: Color = Color(0, 0, 0, 0)
## Orb radius in battle-panel pixels (no texture).
@export var radius: float = 6.0
## Pixels per second.
@export var speed: float = 1100.0
## Height of the arc at mid-flight (0 = straight; a thrown rock ~60).
@export var arc_height: float = 0.0
## Degrees per second (a spinning axe). 0 = the image points along its flight.
@export var spin_degrees: float = 0.0

## The preset for a weapon class, or null (= the element orb). New presets go here.
static func for_weapon(weapon_class: StringName) -> ProjectileLook:
	var p := ProjectileLook.new()
	match weapon_class:
		&"gun":
			p.style = Style.BULLET
			p.color = Color(1.0, 0.92, 0.6)
			p.radius = 2.5
			p.speed = 2400.0
		&"bow":
			p.style = Style.ARROW
			p.color = Color(0.85, 0.8, 0.7)
			p.radius = 2.0
			p.speed = 1300.0
			p.arc_height = 28.0
		&"staff":
			p.style = Style.BOLT
			p.radius = 7.0
			p.speed = 900.0
		_:
			return null
	return p
