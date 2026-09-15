extends AngelDialogue
class_name DealerDialogue
## Reuses the collection dialog's typewriter, modal input, pause handling and
## independent presentation RNG without changing the shop or granting rewards.

const DEALER_CONTENT := preload("res://scripts/rooms/DealerDialogueContent.gd")
const VOICE_PITCH_OFFSET := -16.0


func _ready() -> void:
	actor = get_parent().get_node("Kiosk/Dealer") as Sprite3D
	dialog_name = "Dealer"
	# Even the highest dealer syllable (-10 semitones) remains below the
	# lowest angel/Satan syllable (-4 semitones) and the Jester's +2.
	voice_pitch_offset = VOICE_PITCH_OFFSET
	super._ready()


func _get_sentences() -> Array[String]:
	return DEALER_CONTENT.SENTENCES


func _get_dialog_title() -> String:
	return "Der Händler"
