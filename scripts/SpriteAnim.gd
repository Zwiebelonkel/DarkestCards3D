extends Sprite3D

@export var fps: float = 12.0
@export var loop: bool = true
@export var TOTAL_FRAMES := 25

var _frame_timer := 0.0

func _ready() -> void:
	hframes = TOTAL_FRAMES
	vframes = 1
	frame = 0

func _process(delta: float) -> void:
	if fps <= 0.0:
		return

	_frame_timer += delta

	if _frame_timer >= 1.0 / fps:
		_frame_timer = 0.0

		var next_frame := frame + 1

		if next_frame >= TOTAL_FRAMES:
			if loop:
				next_frame = 0
			else:
				next_frame = TOTAL_FRAMES - 1
				set_process(false)

		frame = next_frame
