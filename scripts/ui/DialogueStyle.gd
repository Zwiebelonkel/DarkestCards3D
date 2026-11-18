extends RefCounted
## Shared speaker colors and literal-text presentation for NPC conversations.

const LAUGH_EFFECT := preload("res://scripts/ui/SatanLaughTextEffect.gd")
const SATAN := Color("ff4545")
const JESTER := Color("65df70")
const DEALER := Color("bc7aff")
const PRISONER := Color("ffe066")
const ANGEL := Color("68b5ff")
const SPEAKER_COLORS := {
	"satan": SATAN,
	"jester": JESTER,
	"dealer": DEALER,
	"prisoner": PRISONER,
	"angel": ANGEL,
}


static func speaker_color(character_id: String) -> Color:
	return SPEAKER_COLORS.get(character_id.to_lower(), Color.WHITE)


static func set_body(label: RichTextLabel, content: String, laughing: bool) -> void:
	label.text = content
	label.clip_contents = not laughing
	if not laughing:
		return
	# Keep .text literal and BBCode disabled, including Steam persona names.
	# clear() rebuilds only the display stack; it retains the text property.
	label.clear()
	label.push_color(SATAN)
	label.push_customfx(LAUGH_EFFECT.new(), {})
	label.add_text(content)
	label.pop()
	label.pop()
