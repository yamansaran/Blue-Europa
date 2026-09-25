@tool
extends Resource
class_name BuffIconStyle

## ============================================================================
## BUFF ICON STYLE  —  HOW every buff/debuff icon looks (a Resource)
## ============================================================================
## Part of the BUFF ICON ENGINE (scenes/ui/buff_icons/). This is the "drawing
## engine" knob-board: every visual decision about an icon — its SHAPE, rounding,
## colour grading, shadow, bevel, border, rune stroke and counter text — is a field
## here, so the look can be changed without touching a line of combat, buff or UI
## code. WHAT each buff shows (its colour and rune) lives in BuffIconCatalog.
##
## EDIT IT IN THE INSPECTOR: open res://scenes/ui/buff_icons/default_buff_icon_style.tres
## and change fields; every icon in the game reads that file (BuffIconPainter.style()).
## Nothing assumes a rectangle — flip `shape` to CIRCLE / DIAMOND / HEXAGON / SHIELD /
## OCTAGON and every icon follows.
## ----------------------------------------------------------------------------

enum Shape { RECT, ROUNDED_RECT, CIRCLE, DIAMOND, HEXAGON, OCTAGON, SHIELD }
enum RuneSource { STROKES, FONT }

@export_group("Shape")
@export var shape: Shape = Shape.ROUNDED_RECT
## Corner radius as a fraction of the SHORTER side (ROUNDED_RECT only).
@export_range(0.0, 0.5, 0.01) var corner_radius: float = 0.18
## Points per rounded corner / circle quadrant. Higher = smoother.
@export_range(2, 16) var corner_detail: int = 5
## Inset of the whole shape from the icon's rect, in px.
@export var margin: float = 0.5

@export_group("Colour grading")
## The top of the fill is the base colour lightened by this much…
@export_range(0.0, 1.0, 0.01) var top_lighten: float = 0.28
## …and the bottom darkened by this much. Together they are the vertical gradient.
@export_range(0.0, 1.0, 0.01) var bottom_darken: float = 0.38
## Multiplies the base colour's saturation (1 = untouched).
@export_range(0.0, 2.0, 0.01) var saturation: float = 0.92
## Multiplies the base colour's value/brightness (1 = untouched).
@export_range(0.0, 2.0, 0.01) var value: float = 0.95
## How strongly a DEBUFF is pushed toward `debuff_tint` (0 = not at all).
@export_range(0.0, 1.0, 0.01) var debuff_tint_amount: float = 0.12
@export var debuff_tint: Color = Color(0.35, 0.0, 0.05)

@export_group("Bevel + shadow")
## A lighter inner band along the top edge (a lit bevel). 0 disables it.
@export_range(0.0, 1.0, 0.01) var bevel_strength: float = 0.35
## Height of the bevel band as a fraction of the icon height.
@export_range(0.0, 1.0, 0.01) var bevel_height: float = 0.38
## Inset of the bevel band from the outer shape, in px.
@export var bevel_inset: float = 1.5
@export var shadow_offset: Vector2 = Vector2(1.0, 1.5)
@export var shadow_color: Color = Color(0, 0, 0, 0.45)

@export_group("Border")
@export var border_width: float = 1.25
## Buffs and debuffs get different border colours, so they separate at a glance
## even when two effects share a hue.
@export var buff_border_color: Color = Color(0.95, 0.92, 0.80, 0.85)
@export var debuff_border_color: Color = Color(0.08, 0.02, 0.03, 0.95)
@export var hover_border_color: Color = Color(1, 1, 1, 1)
## A DEBUFF empowered by its caster's Disdain gets this border instead.
@export var empowered_border_color: Color = Color(0.76, 0.55, 0.98, 1.0)
@export var empowered_border_width: float = 2.0

@export_group("Rune")
@export var rune_source: RuneSource = RuneSource.STROKES
## Font used when rune_source = FONT (e.g. Noto Sans Runic). Null falls back to strokes.
@export var rune_font: Font = null
## Rune box height as a fraction of the icon's shorter side.
@export_range(0.1, 1.0, 0.01) var rune_scale: float = 0.62
## Stroke width as a fraction of the rune box height (STROKES only).
@export_range(0.01, 0.3, 0.005) var rune_width: float = 0.11
@export var rune_min_width: float = 1.1
@export var rune_color: Color = Color(1.0, 0.98, 0.92, 0.97)
## Used instead of rune_color when the icon's colour is so light a pale rune would vanish.
@export var rune_color_on_light: Color = Color(0.08, 0.10, 0.16, 0.95)
## Luminance of the base colour above which rune_color_on_light is used.
@export_range(0.0, 1.0, 0.01) var light_threshold: float = 0.72
@export var rune_shadow_color: Color = Color(0, 0, 0, 0.55)
@export var rune_shadow_offset: Vector2 = Vector2(0.6, 0.9)
## Nudges the rune up/down inside the icon (fraction of height; + = down).
@export_range(-0.5, 0.5, 0.01) var rune_offset_y: float = 0.0

@export_group("Counters")
## Turns-left counter (bottom-right). A PERMANENT effect shows no counter at all.
@export var show_counter: bool = true
@export var counter_font_size: int = 9
@export var counter_color: Color = Color(1, 1, 1)
@export var counter_outline: Color = Color(0, 0, 0)
## Stack badge "xN" (top-left).
@export var show_stacks: bool = true
@export var stack_font_size: int = 8

@export_group("Sizes")
## Icon size in the TOP PANEL (important units' big bars).
@export var panel_icon_size: Vector2 = Vector2(28, 39)
## Icon size UNDER A UNIT'S OVERHEAD BARS. Kept small — five rows of units share the field.
@export var overhead_icon_size: Vector2 = Vector2(18, 18)
## Counters are hidden on icons smaller than this (height, px) — too small to read.
@export var min_counter_height: float = 15.0
