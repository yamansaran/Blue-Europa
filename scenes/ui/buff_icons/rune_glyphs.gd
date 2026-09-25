extends RefCounted
class_name RuneGlyphs

## ============================================================================
## RUNE GLYPHS  —  the rune alphabet, drawn by the engine as strokes
## ============================================================================
## Part of the BUFF ICON ENGINE (scenes/ui/buff_icons/). Nothing outside that
## folder needs to know this file exists.
##
## WHY STROKES AND NOT A FONT. Godot ships no rune font. The Unicode Runic block
## (U+16A0..U+16FF) is covered by open fonts — Noto Sans Runic (SIL OFL 1.1) is the
## cleanest, Junicode (OFL) is the scholarly one — and BuffIconStyle can use one
## (rune_source = FONT). But the Elder Futhark is made ENTIRELY of straight lines,
## so drawing it is ~3 lines of data per rune and buys things a font cannot:
## a stroke width that scales with the icon, a drop shadow per stroke, any colour,
## no licence file, no import step, and new invented runes are just more data.
##
## THE DATA. Each rune is a list of POLYLINES in a normalised box: x 0..1 left to
## right, y 0..1 TOP to bottom. The painter fits that box into the icon (keeping
## RUNE_ASPECT, since runes are taller than they are wide). Add a rune by adding a
## key — invented glyphs for buffs that want their own sign are welcome here too.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

## Width / height of the box a rune is authored in. Runes are tall and narrow.
const RUNE_ASPECT := 0.64

const GLYPHS := {
	# --- Freyr's aett -------------------------------------------------------
	"fehu":     [[Vector2(0.30, 0.00), Vector2(0.30, 1.00)], [Vector2(0.30, 0.40), Vector2(0.80, 0.08)], [Vector2(0.30, 0.66), Vector2(0.80, 0.34)]],
	"uruz":     [[Vector2(0.25, 1.00), Vector2(0.25, 0.00), Vector2(0.75, 0.32), Vector2(0.75, 1.00)]],
	"thurisaz": [[Vector2(0.30, 0.00), Vector2(0.30, 1.00)], [Vector2(0.30, 0.25), Vector2(0.75, 0.50), Vector2(0.30, 0.75)]],
	"ansuz":    [[Vector2(0.30, 0.00), Vector2(0.30, 1.00)], [Vector2(0.30, 0.02), Vector2(0.80, 0.32)], [Vector2(0.30, 0.30), Vector2(0.80, 0.60)]],
	"raidho":   [[Vector2(0.28, 1.00), Vector2(0.28, 0.00), Vector2(0.74, 0.25), Vector2(0.28, 0.50), Vector2(0.76, 1.00)]],
	"kenaz":    [[Vector2(0.72, 0.18), Vector2(0.28, 0.50), Vector2(0.72, 0.82)]],
	"gebo":     [[Vector2(0.18, 0.05), Vector2(0.82, 0.95)], [Vector2(0.82, 0.05), Vector2(0.18, 0.95)]],
	"wunjo":    [[Vector2(0.30, 1.00), Vector2(0.30, 0.00), Vector2(0.74, 0.22), Vector2(0.30, 0.46)]],
	# --- Heimdall's aett ----------------------------------------------------
	"hagalaz":  [[Vector2(0.25, 0.00), Vector2(0.25, 1.00)], [Vector2(0.75, 0.00), Vector2(0.75, 1.00)], [Vector2(0.25, 0.36), Vector2(0.75, 0.64)]],
	"naudiz":   [[Vector2(0.50, 0.00), Vector2(0.50, 1.00)], [Vector2(0.22, 0.34), Vector2(0.78, 0.66)]],
	"isa":      [[Vector2(0.50, 0.00), Vector2(0.50, 1.00)]],
	"jera":     [[Vector2(0.46, 0.06), Vector2(0.18, 0.30), Vector2(0.46, 0.54)], [Vector2(0.54, 0.46), Vector2(0.82, 0.70), Vector2(0.54, 0.94)]],
	"eihwaz":   [[Vector2(0.50, 0.00), Vector2(0.50, 1.00)], [Vector2(0.50, 0.00), Vector2(0.78, 0.20)], [Vector2(0.50, 1.00), Vector2(0.22, 0.80)]],
	"perthro":  [[Vector2(0.28, 0.00), Vector2(0.28, 1.00)], [Vector2(0.28, 0.00), Vector2(0.72, 0.26), Vector2(0.72, 0.08)], [Vector2(0.28, 1.00), Vector2(0.72, 0.74), Vector2(0.72, 0.92)]],
	"algiz":    [[Vector2(0.50, 0.12), Vector2(0.50, 1.00)], [Vector2(0.50, 0.46), Vector2(0.16, 0.08)], [Vector2(0.50, 0.46), Vector2(0.84, 0.08)]],
	"sowilo":   [[Vector2(0.72, 0.00), Vector2(0.28, 0.36), Vector2(0.72, 0.64), Vector2(0.28, 1.00)]],
	# --- Tyr's aett ---------------------------------------------------------
	"tiwaz":    [[Vector2(0.50, 0.00), Vector2(0.50, 1.00)], [Vector2(0.16, 0.34), Vector2(0.50, 0.00), Vector2(0.84, 0.34)]],
	"berkano":  [[Vector2(0.28, 0.00), Vector2(0.28, 1.00)], [Vector2(0.28, 0.00), Vector2(0.72, 0.25), Vector2(0.28, 0.50), Vector2(0.72, 0.75), Vector2(0.28, 1.00)]],
	"ehwaz":    [[Vector2(0.22, 1.00), Vector2(0.22, 0.00), Vector2(0.50, 0.34), Vector2(0.78, 0.00), Vector2(0.78, 1.00)]],
	"mannaz":   [[Vector2(0.22, 0.00), Vector2(0.22, 1.00)], [Vector2(0.78, 0.00), Vector2(0.78, 1.00)], [Vector2(0.22, 0.00), Vector2(0.78, 0.46)], [Vector2(0.78, 0.00), Vector2(0.22, 0.46)]],
	"laguz":    [[Vector2(0.34, 1.00), Vector2(0.34, 0.00), Vector2(0.74, 0.30)]],
	"ingwaz":   [[Vector2(0.50, 0.14), Vector2(0.82, 0.50), Vector2(0.50, 0.86), Vector2(0.18, 0.50), Vector2(0.50, 0.14)]],
	"dagaz":    [[Vector2(0.16, 0.08), Vector2(0.16, 0.92), Vector2(0.84, 0.08), Vector2(0.84, 0.92), Vector2(0.16, 0.08)]],
	"othala":   [[Vector2(0.18, 1.00), Vector2(0.78, 0.40), Vector2(0.50, 0.06), Vector2(0.22, 0.40), Vector2(0.82, 1.00)]],
	# --- invented signs (not Futhark) — for effects that want their own mark --
	"ward":     [[Vector2(0.15, 0.20), Vector2(0.50, 0.02), Vector2(0.85, 0.20), Vector2(0.85, 0.55), Vector2(0.50, 0.98), Vector2(0.15, 0.55), Vector2(0.15, 0.20)], [Vector2(0.50, 0.25), Vector2(0.50, 0.75)]],
	"bolt":     [[Vector2(0.62, 0.00), Vector2(0.26, 0.54), Vector2(0.62, 0.46), Vector2(0.36, 1.00)]],
	"drop":     [[Vector2(0.50, 0.00), Vector2(0.80, 0.60), Vector2(0.50, 1.00), Vector2(0.20, 0.60), Vector2(0.50, 0.00)]],
	"unknown":  [[Vector2(0.25, 0.25), Vector2(0.50, 0.00), Vector2(0.75, 0.25), Vector2(0.50, 0.55), Vector2(0.50, 0.72)], [Vector2(0.50, 0.90), Vector2(0.50, 1.00)]],
}

## The Unicode code point of each Futhark rune, for BuffIconStyle.rune_source FONT.
const UNICODE := {
	"fehu": "ᚠ", "uruz": "ᚢ", "thurisaz": "ᚦ", "ansuz": "ᚨ", "raidho": "ᚱ", "kenaz": "ᚲ",
	"gebo": "ᚷ", "wunjo": "ᚹ", "hagalaz": "ᚺ", "naudiz": "ᚾ", "isa": "ᛁ", "jera": "ᛃ",
	"eihwaz": "ᛇ", "perthro": "ᛈ", "algiz": "ᛉ", "sowilo": "ᛊ", "tiwaz": "ᛏ", "berkano": "ᛒ",
	"ehwaz": "ᛖ", "mannaz": "ᛗ", "laguz": "ᛚ", "ingwaz": "ᛜ", "dagaz": "ᛞ", "othala": "ᛟ",
}

static func has(rune: String) -> bool:
	return GLYPHS.has(rune)

static func names() -> Array:
	return GLYPHS.keys()

## The strokes of `rune` (falls back to "unknown" so a typo draws a visible "?").
static func strokes(rune: String) -> Array:
	return GLYPHS.get(rune, GLYPHS["unknown"])
