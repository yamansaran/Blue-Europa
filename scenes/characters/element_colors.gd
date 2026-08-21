extends RefCounted
class_name ElementColors

## ============================================================================
## ELEMENT COLORS  —  the single source of truth for per-element display colour
## ============================================================================
## Every system that tints by element (the floating damage numbers, the
## minor-attribute bar graphs, and anything added later) reads its colour from
## HERE, so the palette is defined in exactly ONE place. Keyed by the element
## STRING used everywhere else in the codebase (Stats.element_key(): "physical",
## "spiritual", "ice", ... plus the hidden "true").
##
## Stats.element_color() delegates to ElementColors.color() so old callers keep
## working; new code should call ElementColors.color(element) directly.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

## The canonical element palette.
const COLORS := {
	"physical":  Color(0.90, 0.20, 0.20),   # red
	"spiritual": Color(0.25, 0.82, 0.78),   # turquoise
	"ice":       Color(0.95, 0.98, 1.00),   # white
	"fire":      Color(1.00, 0.55, 0.15),   # orange
	"lightning": Color(1.00, 0.90, 0.25),   # yellow
	"blood":     Color(0.55, 0.04, 0.08),   # deep red
	"toxic":     Color(0.28, 0.80, 0.30),   # green
	"mental":    Color(0.66, 0.30, 0.86),   # purple
	"true":      Color(0.05, 0.05, 0.06),   # black
}

## Fallback for any unknown element string.
const DEFAULT := Color(0.70, 0.70, 0.72)

## Element string ("fire", "ice", "true", ...) -> its display colour.
static func color(element: String) -> Color:
	return COLORS.get(element, DEFAULT)

## Element enum (Stats.Element) -> its display colour.
static func color_for_enum(e: int) -> Color:
	return color(Stats.element_key(e))
