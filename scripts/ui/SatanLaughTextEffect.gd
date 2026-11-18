extends RichTextEffect
## Small, smooth movements with a separate phase and speed for each letter.

var bbcode := "satan_laugh"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var index := float(char_fx.relative_index)
	var phase := fmod(index * 2.399963, TAU)
	var speed := 14.0 + fmod(index * 2.37, 8.0)
	var time := char_fx.elapsed_time
	char_fx.offset += Vector2(
		sin(time * speed + phase) * 1.8,
		cos(time * (speed * 0.83) + phase * 1.7) * 2.6
	)
	return true
