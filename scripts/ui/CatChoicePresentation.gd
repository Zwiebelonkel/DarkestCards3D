extends CanvasLayer
class_name CatChoicePresentation
## The cellar choice reuses the table victory's first-person pistol presentation.
## The encounter owns persistence, rewards and the cat's world-space reaction.

signal choice_requested(choice: String)
signal shot_fired

const ANGEL_TEXTURE := preload("res://assets/characters/angel.png")
const SATAN_TEXTURE := preload("res://assets/characters/satan.png")
const SATAN_HOVER_TEXTURE := preload("res://assets/characters/satanHover.png")
const GUN_TEXTURE := preload("res://assets/characters/gun_back.png")
const FLASH_TEXTURE := preload("res://assets/characters/flash.png")
const SHOT_SOUND := preload("res://assets/sounds/SFX/shot.mp3")
const FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")
const SHOOT_MESSAGE := "Click me to shoot the cat and earn %d Soul Coins."
const SPARE_MESSAGE := "Everyone deserves to live. Click me to spare the cat."
const GUN_HIDDEN_OFFSET := 350.0
const RAISE_DURATION := 0.55
const LOWER_DURATION := 0.45
const RECOIL_DURATION := 0.08
const KNOCKBACK_DURATION := 0.6

var _root: Control
var _angel_mount: Control
var _satan_mount: Control
var _angel: TextureButton
var _satan: TextureButton
var _angel_atlas := AtlasTexture.new()
var _satan_atlas := AtlasTexture.new()
var _satan_hover_atlas := AtlasTexture.new()
var _gun_mount: Control
var _muzzle_flash: TextureRect
var _tooltip: Panel
var _message: Label
var _shot_audio: AudioStreamPlayer
var _motion_tween: Tween
var _gun_tween: Tween
var _timer_tween: Tween
var _active := false
var _transitioning := false
var _choice_pending := false
var _interaction_enabled := true
var _suspended := false
var _hovered_choice := ""
var _status_message := ""
var _reward_amount := 1000
var _generation := 0
var _animation_seconds := 0.0
var _portrait_reveal := 0.0
var _gun_vertical_offset := GUN_HIDDEN_OFFSET
var _ui_scale := 1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 110 # Same layer as WinCinematicCanvas, below Main's lens and CRT.
	_rng.randomize()
	_build_ui()
	get_viewport().size_changed.connect(_layout_ui)
	Localization.locale_changed.connect(_refresh_tooltip)
	_layout_ui()
	reset_immediately()


func _process(delta: float) -> void:
	if not _active or _suspended:
		return
	_animation_seconds = fmod(_animation_seconds + delta, 30.0)
	_update_portrait_frames()


func is_active() -> bool:
	return _active


func is_busy() -> bool:
	return _transitioning or _choice_pending


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	# The controller can release a selection after a failed durable save.
	if enabled and not _transitioning:
		_choice_pending = false
	_sync_buttons()
	_refresh_tooltip()


func set_suspended(suspended: bool) -> void:
	if _suspended == suspended:
		return
	_suspended = suspended
	visible = _active and not _suspended
	# Online pause is an overlay and deliberately leaves the SceneTree running.
	for tween: Tween in [_motion_tween, _gun_tween, _timer_tween]:
		if tween != null and tween.is_valid():
			if suspended:
				tween.pause()
			else:
				tween.play()
	if is_instance_valid(_shot_audio):
		_shot_audio.stream_paused = suspended
	_clear_hover()
	_sync_buttons()
	# PauseMenu emits visibility_changed before it unpauses the SceneTree.
	# Re-enable portrait buttons after that same synchronous close completes.
	if not suspended:
		_sync_buttons.call_deferred()


func show_message(message: String) -> void:
	_status_message = message
	_refresh_tooltip()


func show_choice(reward_amount: int = 1000) -> void:
	if _active:
		return
	reset_immediately()
	_reward_amount = reward_amount
	_active = true
	_transitioning = true
	_interaction_enabled = true
	_status_message = ""
	visible = not _suspended
	_gun_mount.show()
	_sync_buttons()
	var generation := _generation
	_motion_tween = create_tween().set_parallel(true)
	_motion_tween.tween_method(_set_portrait_reveal, 0.0, 1.0, RAISE_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_motion_tween.tween_method(_set_gun_vertical_offset, GUN_HIDDEN_OFFSET, 0.0, RAISE_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _suspended:
		_motion_tween.pause()
	await _motion_tween.finished
	if generation != _generation:
		return
	_motion_tween = null
	_transitioning = false
	_sync_buttons()


func play_shot() -> void:
	if not _active or _transitioning or _suspended:
		return
	_transitioning = true
	_choice_pending = false
	_clear_hover()
	_sync_buttons()
	var generation := _generation
	# Exactly the table win impact: flash, shot.mp3 and world reaction in one frame.
	_muzzle_flash.rotation = _rng.randf_range(-0.25, 0.25)
	_muzzle_flash.show()
	_shot_audio.play()
	_start_gun_recoil()
	shot_fired.emit()
	await _wait_presentation_time(0.1)
	if generation != _generation:
		return
	_muzzle_flash.hide()
	await _wait_presentation_time(KNOCKBACK_DURATION - 0.1)
	if generation != _generation:
		return
	await _lower_choice(generation)


func hide_choice() -> void:
	if not _active or _transitioning:
		return
	_transitioning = true
	_choice_pending = false
	_clear_hover()
	_sync_buttons()
	await _lower_choice(_generation)


func reset_immediately() -> void:
	_generation += 1
	var cancelled_tweens: Array[Tween] = [_motion_tween, _timer_tween]
	_motion_tween = null
	_timer_tween = null
	if _gun_tween != null:
		_gun_tween.kill()
		_gun_tween = null
	_active = false
	_transitioning = false
	_choice_pending = false
	_interaction_enabled = true
	_animation_seconds = 0.0
	_status_message = ""
	visible = false
	if not is_instance_valid(_root):
		return
	_shot_audio.stop()
	_muzzle_flash.hide()
	_gun_mount.rotation = 0.0
	_gun_mount.hide()
	_set_gun_vertical_offset(GUN_HIDDEN_OFFSET)
	_set_portrait_reveal(0.0)
	_clear_hover()
	_sync_buttons()
	# Killing a Tween alone never resolves an await on its finished signal.
	# Release obsolete coroutines after resetting state; their generation guards
	# keep them from progressing or changing a later encounter.
	for tween: Tween in cancelled_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
			tween.finished.emit()


func _can_accept_choice() -> bool:
	return _active and not _transitioning and not _choice_pending and _interaction_enabled and not _suspended and not get_tree().paused


func _request_choice(choice: String) -> void:
	if not _can_accept_choice():
		return
	_choice_pending = true
	_status_message = ""
	_clear_hover()
	_sync_buttons()
	choice_requested.emit(choice)


func _sync_buttons() -> void:
	if not is_instance_valid(_angel):
		return
	var enabled := _can_accept_choice()
	_angel.disabled = not enabled
	_satan.disabled = not enabled
	_angel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	_satan.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	if not enabled:
		_clear_hover()


func _lower_choice(generation: int) -> void:
	if _gun_tween != null:
		_gun_tween.kill()
	_motion_tween = create_tween().set_parallel(true)
	_motion_tween.tween_method(_set_portrait_reveal, _portrait_reveal, 0.0, LOWER_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_motion_tween.tween_method(_set_gun_vertical_offset, _gun_vertical_offset, GUN_HIDDEN_OFFSET, LOWER_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_motion_tween.tween_property(_gun_mount, "rotation", 0.0, LOWER_DURATION)
	if _suspended:
		_motion_tween.pause()
	await _motion_tween.finished
	if generation == _generation:
		_motion_tween = null
		reset_immediately()


func _wait_presentation_time(duration: float) -> void:
	var generation := _generation
	_timer_tween = create_tween()
	_timer_tween.tween_interval(duration)
	if _suspended:
		_timer_tween.pause()
	await _timer_tween.finished
	if generation == _generation:
		_timer_tween = null


func _start_gun_recoil() -> void:
	if _gun_tween != null:
		_gun_tween.kill()
	_gun_tween = create_tween().set_parallel(true)
	_gun_tween.tween_method(_set_gun_vertical_offset, 0.0, -24.0, RECOIL_DURATION).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_gun_tween.tween_property(_gun_mount, "rotation", deg_to_rad(-2.5), RECOIL_DURATION).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_gun_tween.chain().tween_method(_set_gun_vertical_offset, -24.0, 0.0, RECOIL_DURATION * 1.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_gun_tween.parallel().tween_property(_gun_mount, "rotation", 0.0, RECOIL_DURATION * 1.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _suspended:
		_gun_tween.pause()


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "ChoiceRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_angel_mount = Control.new()
	_angel_mount.name = "AngelMount"
	_angel_mount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_angel_mount)
	_satan_mount = Control.new()
	_satan_mount.name = "SatanMount"
	_satan_mount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_satan_mount)
	_angel_atlas.atlas = ANGEL_TEXTURE
	_satan_atlas.atlas = SATAN_TEXTURE
	_satan_hover_atlas.atlas = SATAN_HOVER_TEXTURE
	_angel = _make_portrait(_angel_mount, "Angel", _angel_atlas, "spared")
	_satan = _make_portrait(_satan_mount, "Satan", _satan_atlas, "shot")
	_satan.texture_hover = _satan_hover_atlas
	_update_portrait_frames()
	_gun_mount = Control.new()
	_gun_mount.name = "PlayerGunMount"
	_gun_mount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_gun_mount)
	# Rects, pivot, dark modulation and draw order match GameTable.tscn.
	_muzzle_flash = _make_texture(_gun_mount, "MuzzleFlash", FLASH_TEXTURE, Rect2(-253.0, -460.0, 525.0, 484.0))
	_muzzle_flash.pivot_offset = Vector2(48.0, 48.0)
	var gun := _make_texture(_gun_mount, "GunBack", GUN_TEXTURE, Rect2(-248.0, -357.0, 500.0, 500.0))
	gun.modulate = Color(0.118581, 0.118581, 0.118581, 1.0)
	_tooltip = Panel.new()
	_tooltip.name = "ChoiceTooltip"
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.032, 0.028, 0.96)
	style.border_color = Color(0.62, 0.52, 0.34, 0.85)
	style.set_border_width_all(2)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	_tooltip.add_theme_stylebox_override("panel", style)
	_root.add_child(_tooltip)
	_message = Label.new()
	_message.name = "Message"
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_font_override("font", FONT)
	_message.add_theme_color_override("font_color", Color("fff1d2"))
	_tooltip.add_child(_message)
	_shot_audio = AudioStreamPlayer.new()
	_shot_audio.name = "ShotSFX"
	_shot_audio.stream = SHOT_SOUND
	_shot_audio.bus = &"SFX"
	add_child(_shot_audio)


func _make_portrait(parent: Control, node_name: String, texture: Texture2D, choice: String) -> TextureButton:
	var button := TextureButton.new()
	button.name = node_name
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.texture_normal = texture
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(_request_choice.bind(choice))
	button.mouse_entered.connect(_set_hover.bind(choice, true))
	button.mouse_exited.connect(_set_hover.bind(choice, false))
	button.focus_entered.connect(_set_hover.bind(choice, true))
	button.focus_exited.connect(_set_hover.bind(choice, false))
	parent.add_child(button)
	return button


func _make_texture(parent: Control, node_name: String, texture: Texture2D, rect: Rect2) -> TextureRect:
	var image := TextureRect.new()
	image.name = node_name
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.texture = texture
	image.position = rect.position
	image.size = rect.size
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	parent.add_child(image)
	return image


func _set_hover(choice: String, hovered: bool) -> void:
	if hovered and _can_accept_choice():
		_hovered_choice = choice
	elif not hovered and _hovered_choice == choice:
		_hovered_choice = ""
	_refresh_tooltip()


func _clear_hover() -> void:
	_hovered_choice = ""
	if is_instance_valid(_tooltip):
		_refresh_tooltip()


func _refresh_tooltip() -> void:
	if not is_instance_valid(_tooltip):
		return
	_tooltip.visible = (not _hovered_choice.is_empty() or not _status_message.is_empty()) and _can_accept_choice()
	if not _tooltip.visible:
		return
	if _hovered_choice == "shot":
		_message.text = Localization.format_text(SHOOT_MESSAGE, [_reward_amount])
	elif _hovered_choice == "spared":
		_message.text = Localization.text(SPARE_MESSAGE)
	else:
		_message.text = Localization.text(_status_message)
	_layout_ui()


func _update_portrait_frames() -> void:
	_set_atlas_frame(_angel_atlas, ANGEL_TEXTURE, 18, floori(_animation_seconds * 10.0) % 18)
	_set_atlas_frame(_satan_atlas, SATAN_TEXTURE, 25, floori(_animation_seconds * 15.0) % 25)
	_set_atlas_frame(_satan_hover_atlas, SATAN_HOVER_TEXTURE, 25, floori(_animation_seconds * 15.0) % 25)


func _set_atlas_frame(atlas: AtlasTexture, texture: Texture2D, frames: int, frame: int) -> void:
	var frame_size := Vector2(float(texture.get_width()) / frames, texture.get_height())
	atlas.region = Rect2(Vector2(frame * frame_size.x, 0.0), frame_size)


func _set_portrait_reveal(value: float) -> void:
	_portrait_reveal = value
	_layout_ui()


func _set_gun_vertical_offset(value: float) -> void:
	_gun_vertical_offset = value
	if is_instance_valid(_gun_mount):
		var viewport_size := get_viewport().get_visible_rect().size
		_gun_mount.position = Vector2(viewport_size.x * 0.5, viewport_size.y + value * _ui_scale)


func _layout_ui() -> void:
	if not is_instance_valid(_message):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	_ui_scale = minf(1.0, minf(viewport_size.x / 1280.0, viewport_size.y / 720.0))
	var portrait_size := minf(viewport_size.y * 0.35, viewport_size.x * 0.24)
	var margin := 28.0 * _ui_scale
	# Both portraits rise from below the viewport to its exact bottom edge.
	# The same reveal value sends them fully below it again when dismissed.
	var portrait_y := viewport_size.y - portrait_size * _portrait_reveal
	_angel_mount.position = Vector2(margin, portrait_y)
	_satan_mount.position = Vector2(viewport_size.x - portrait_size - margin, portrait_y)
	_angel.size = Vector2.ONE * portrait_size
	_satan.size = Vector2.ONE * portrait_size
	_gun_mount.scale = Vector2.ONE * _ui_scale
	_set_gun_vertical_offset(_gun_vertical_offset)
	var font_size := maxi(13, roundi(21.0 * _ui_scale))
	_message.add_theme_font_size_override("font_size", font_size)
	var tooltip_width := minf(370.0 * _ui_scale, viewport_size.x * 0.42)
	# Let the Label shape its actual wrapping and line spacing at this width.
	_message.size = Vector2(tooltip_width - 36.0, 0.0)
	var tooltip_height := maxf(_message.get_minimum_size().y + 28.0, 80.0 * _ui_scale)
	_tooltip.size = Vector2(tooltip_width, tooltip_height)
	_message.position = Vector2(18.0, 14.0)
	_message.size = Vector2(tooltip_width - 36.0, tooltip_height - 28.0)
	_tooltip.position = Vector2(viewport_size.x - tooltip_width - margin if _hovered_choice == "shot" else margin, maxf(margin, portrait_y - tooltip_height - 12.0 * _ui_scale))
