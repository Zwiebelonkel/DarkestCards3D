extends Sprite3D

const SHEET := preload("res://assets/cards/newlabel.png")
const FRAME_SIZE := 64
const FPS := 12.0

var _frame_elapsed := 0.0
var _collection_card_id := ""


func _ready() -> void:
	texture = SHEET
	hframes = maxi(SHEET.get_width() / FRAME_SIZE, 1)
	vframes = maxi(SHEET.get_height() / FRAME_SIZE, 1)
	frame = 0
	pixel_size = 0.005
	position = Vector3(-0.396, 0.57, 0.06)
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	shaded = false


func watch_collection_card(card_id: String) -> void:
	_collection_card_id = card_id
	if not CollectionManager.is_card_new(card_id):
		_dismiss()
		return
	if not CollectionManager.card_seen.is_connected(_on_card_seen):
		CollectionManager.card_seen.connect(_on_card_seen)


func _on_card_seen(card_id: String) -> void:
	if card_id == _collection_card_id:
		_dismiss()


func _dismiss() -> void:
	hide()
	set_process(false)
	queue_free()


func _process(delta: float) -> void:
	_frame_elapsed += delta
	var steps := int(_frame_elapsed * FPS)
	if steps > 0:
		_frame_elapsed -= float(steps) / FPS
		frame = (frame + steps) % (hframes * vframes)
