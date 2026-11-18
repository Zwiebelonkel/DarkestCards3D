extends Node


func _ready() -> void:
	var audio := AudioStreamMP3.new()
	audio.data = FileAccess.get_file_as_bytes("res://assets/sounds/SFX/piss.mp3")
	audio.loop = true
	var result := ResourceSaver.save(audio, "res://assets/sounds/SFX/piss_stream_audio.res")
	if result != OK or audio.data.is_empty():
		push_error("Could not prepare the supplied stream sound")
		get_tree().quit(1)
		return
	print("SATAN_STREAM_AUDIO_TESTS: PASS")
	get_tree().quit()
