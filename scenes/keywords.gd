extends RefCounted
class_name Keywords

## ============================================================================
## KEYWORDS  —  the single keyword-colouring registry for hover text
## ============================================================================
## One place that decides which WORDS in a piece of hover text get coloured and
## what colour they take. By default it colours the eight real element names
## (Physical, Spiritual, Ice, Fire, Lightning, Blood, Toxic, Mental) using the
## exact per-element colours from ElementColors, so a description like
##   "Deal 100 + Vigor Physical damage to the target."
## renders "Physical" in the physical-element colour with no change to the .tres.
##
## HOW IT WORKS
## ------------
## colorize(text) turns a PLAIN string into a BBCode string for a RichTextLabel:
## every registered term is matched as a WHOLE WORD, CASE-INSENSITIVELY, and
## wrapped in [color=#rrggbb]...[/color]. The original casing is preserved, so
## "physical", "Physical" and "PHYSICAL" all colour but keep how they were typed.
## Any stray "[" in the source text is escaped so it can't be read as BBCode.
##
## EXTENDING IT (the whole point of a registry)
## --------------------------------------------
## Add or override a term at load time from anywhere:
##     Keywords.add_term("Vulnerability", Color(0.85, 0.35, 0.95))
##     Keywords.add_term("Bleed", ElementColors.color("blood"))
## Terms can be multiple words ("Max HP") — they are matched literally. Removing
## a term: Keywords.remove_term("ice"). The compiled matcher rebuilds itself
## automatically whenever the registry changes.
##
## WHY "true" ISN'T COLOURED: the hidden TRUE element's colour is near-black and
## the word "true" shows up constantly in ordinary prose, so it is intentionally
## left OUT of the default registry. Add it yourself if you ever want it.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

## term (stored lower-cased) -> Color. Lazily seeded with the element names on
## first use. Never read this directly — go through registry().
static var _registry: Dictionary = {}
static var _seeded: bool = false
static var _re: RegEx = null


## The live term->Color table (lower-cased keys). Seeds the element names once.
static func registry() -> Dictionary:
	if not _seeded:
		_seeded = true
		# Default terms: the eight REAL elements, coloured by ElementColors. The
		# hidden "true" element is deliberately omitted (see header).
		for e in Stats.REAL_ELEMENTS:
			_registry[str(e).to_lower()] = ElementColors.color(str(e))
	return _registry


## Add or override a coloured term. `term` is matched whole-word, case-insensitive
## (it is stored lower-cased). Rebuilds the matcher on the next colorize().
static func add_term(term: String, color: Color) -> void:
	var key := term.strip_edges().to_lower()
	if key == "":
		return
	registry()          # ensure seeded before we mutate
	_registry[key] = color
	_re = null           # force the matcher to recompile with the new term


## Remove a term so it is no longer coloured. Safe if it was never registered.
static func remove_term(term: String) -> void:
	var key := term.strip_edges().to_lower()
	registry()
	if _registry.has(key):
		_registry.erase(key)
		_re = null


## The colour a matched word should use (looked up by its lower-cased form).
static func color_for(term_lower: String) -> Color:
	return registry().get(term_lower, ElementColors.DEFAULT)


## Turn a PLAIN string into BBCode with every registered term coloured. Feed the
## result to a RichTextLabel that has bbcode_enabled = true. A string with no
## matches comes back as itself (with only "[" escaped), so it is always safe to
## push through a BBCode label.
static func colorize(text: String) -> String:
	if text == "":
		return ""
	var re := _matcher()
	# No terms registered (or all removed) -> just make the raw text BBCode-safe.
	if re == null:
		return _escape(text)

	var out := ""
	var last := 0
	for m in re.search_all(text):
		var start := m.get_start()
		var end := m.get_end()
		# untouched text before this match
		out += _escape(text.substr(last, start - last))
		# the matched word, wrapped in its colour (original casing preserved)
		var word := text.substr(start, end - start)
		var col := color_for(word.to_lower())
		out += "[color=#%s]%s[/color]" % [col.to_html(false), _escape(word)]
		last = end
	out += _escape(text.substr(last))
	return out


# ----------------------------------------------------------------------------
# Internals
# ----------------------------------------------------------------------------
## The compiled whole-word, case-insensitive alternation of every term. Rebuilt
## whenever the registry changes (add_term / remove_term null it out). Returns
## null when there are no terms to match.
static func _matcher() -> RegEx:
	if _re != null:
		return _re
	var terms: Array = registry().keys()
	if terms.is_empty():
		return null
	# Longest first so a multi-word term wins over a substring term.
	terms.sort_custom(func(a, b): return a.length() > b.length())
	var escaped: Array = []
	for t in terms:
		escaped.append(_regex_escape(str(t)))
	# (?i) case-insensitive; \b word boundaries so "physical" doesn't fire inside
	# a larger word. Word boundaries work for the element names (plain letters).
	var pattern := "(?i)\\b(" + "|".join(escaped) + ")\\b"
	var re := RegEx.new()
	if re.compile(pattern) == OK:
		_re = re
		return _re
	return null


## Escape BBCode control chars in literal text: only "[" needs neutralising, and
## RichTextLabel renders [lb] as a literal "[".
static func _escape(s: String) -> String:
	return s.replace("[", "[lb]")


## Escape the RegEx metacharacters that could appear in a term string.
static func _regex_escape(s: String) -> String:
	var specials := ["\\", ".", "^", "$", "|", "?", "*", "+", "(", ")", "[", "]", "{", "}"]
	var out := s
	for c in specials:
		out = out.replace(c, "\\" + c)
	return out
