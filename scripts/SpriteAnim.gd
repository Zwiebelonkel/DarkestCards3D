extends Sprite3D

const EYE_EMISSION_MAPS := {
	"satan": preload("res://assets/characters/satan/satan_eyes.res"),
	"satanHover": preload("res://assets/characters/satan/satanHover_eyes.res"),
	"satanLaught": preload("res://assets/characters/satan/satanLaught_eyes.res"),
	"satanDeath": preload("res://assets/characters/satan/satanDeath_eyes.res"),
	"satanPanic": preload("res://assets/characters/satan/satanPanic_eyes.res"),
	"satanKill": preload("res://assets/characters/satan/satanKill_eyes.res"),
	"angel": preload("res://assets/characters/angel/angel_eyes.res"),
	"angelHover": preload("res://assets/characters/angel/angelHover_eyes.res"),
	"blackmarketDealer": preload("res://assets/characters/baclmarketDealer/blackmarketDealer_eyes.res"),
	"dealerHover": preload("res://assets/characters/baclmarketDealer/dealerHover_eyes.res"),
	"jester": preload("res://assets/characters/jester/jester_eyes.res"),
	"jesterHover": preload("res://assets/characters/jester/jesterHover_eyes.res"),
	"prisoner": preload("res://assets/characters/prisoner/prisoner_eyes.res"),
	"prisonerHover": preload("res://assets/characters/prisoner/prisonerHover_eyes.res"),
}

@export var fps: float = 12.0
@export var loop: bool = true
@export var TOTAL_FRAMES := 25
@export var hover_texture: Texture2D

var _frame_timer := 0.0
var _idle_texture: Texture2D
var _hovered := false
var _player_resources: Dictionary = {}
var _original_character_material: Material

func _ready() -> void:
	if material_override is StandardMaterial3D and material_override.get_meta(&"character_eye_glow", false):
		# Each actor owns its texture bindings; the baked maps remain shared.
		material_override = material_override.duplicate()
		texture_changed.connect(_sync_eye_emission)
		_sync_eye_emission()
	_idle_texture = texture
	hframes = TOTAL_FRAMES
	vframes = 1
	frame = 0


func _sync_eye_emission() -> void:
	var eye_material := material_override as StandardMaterial3D
	if eye_material == null:
		return
	if not _player_resources.is_empty():
		eye_material.albedo_texture = _player_resources["texture"]
		eye_material.emission_texture = _player_resources["emission"]
		eye_material.emission_enabled = true
		return
	eye_material.albedo_texture = texture
	var sheet_name := texture.resource_path.get_file().get_basename() if texture != null else ""
	var eye_map := EYE_EMISSION_MAPS.get(sheet_name) as Texture2D
	eye_material.emission_texture = eye_map
	# Unknown sheets must never turn the entire sprite into an emitter.
	eye_material.emission_enabled = eye_map != null


func set_player_appearance(appearance: Dictionary) -> void:
	if _player_resources.is_empty():
		_original_character_material = material_override
		material_override = material_override.duplicate() if material_override != null else StandardMaterial3D.new()
	_player_resources = CharacterAppearance.resources(appearance)
	play_sheet(_player_resources["texture"], 1, 0.0)
	_sync_eye_emission()


func clear_player_appearance() -> void:
	if _player_resources.is_empty():
		return
	_player_resources = {}
	material_override = _original_character_material
	play_sheet(_idle_texture, 25, 15.0)
	_sync_eye_emission()


func set_hovered(hovered: bool) -> void:
	if hover_texture == null or _idle_texture == null or _hovered == hovered:
		return
	_hovered = hovered
	# Matching sheets share a timeline, including the partially elapsed frame.
	play_sheet(hover_texture if hovered else _idle_texture, TOTAL_FRAMES, fps, loop, true)


func play_sheet(
	sheet: Texture2D,
	frame_count: int,
	animation_fps: float,
	should_loop: bool = true,
	preserve_frame: bool = false
) -> void:
	if sheet == null:
		return
	# Every online pose keeps the selected face and hat, including hover,
	# laugh and death. Existing scene motion and audio still run as before.
	if not _player_resources.is_empty():
		sheet = _player_resources["texture"]
		frame_count = 1
		animation_fps = 0.0

	var previous_frame := frame
	var previous_frame_timer := _frame_timer
	texture = sheet
	TOTAL_FRAMES = maxi(frame_count, 1)
	fps = maxf(animation_fps, 0.0)
	loop = should_loop
	hframes = TOTAL_FRAMES
	vframes = 1
	frame = clampi(previous_frame, 0, TOTAL_FRAMES - 1) if preserve_frame else 0
	_frame_timer = previous_frame_timer if preserve_frame else 0.0
	set_process(fps > 0.0)

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
