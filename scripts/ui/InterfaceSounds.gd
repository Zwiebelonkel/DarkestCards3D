extends RefCounted

const CLICK := preload("res://assets/sounds/SFX/button.mp3")
const PANEL_FLIP := preload("res://assets/sounds/SFX/PanelFlip.mp3")


static func play_click(owner: Node) -> void:
	_play(owner, CLICK)


static func play_panel_flip(owner: Node) -> void:
	_play(owner, PANEL_FLIP)


static func connect_button(button: BaseButton, owner: Node) -> void:
	var callback := play_click.bind(owner)
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


static func connect_buttons(owner: Node) -> void:
	for button: BaseButton in owner.find_children("*", "BaseButton", true, false):
		connect_button(button, owner)


static func _play(owner: Node, stream: AudioStream) -> void:
	var player := owner.get_node_or_null("InterfaceSound") as AudioStreamPlayer
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = "InterfaceSound"
		player.bus = &"SFX"
		player.max_polyphony = 4
		owner.add_child(player)
	player.stream = stream
	player.play()
