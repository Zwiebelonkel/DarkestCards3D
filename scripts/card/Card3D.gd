extends Node3D
class_name Card3D

class RarityPreset:
	var intensity: float
	var scroll_speed: float
	var band_density: float
	var jaggedness: float
	var pulse_strength: float
	var pulse_speed: float
	var base_glow: float
	var emission_boost: float

	func _init(
		p_intensity: float,
		p_scroll_speed: float,
		p_band_density: float,
		p_jaggedness: float,
		p_pulse_strength: float,
		p_pulse_speed: float,
		p_base_glow: float,
		p_emission_boost: float
	) -> void:
		intensity = p_intensity
		scroll_speed = p_scroll_speed
		band_density = p_band_density
		jaggedness = p_jaggedness
		pulse_strength = p_pulse_strength
		pulse_speed = p_pulse_speed
		base_glow = p_base_glow
		emission_boost = p_emission_boost


@onready var card_model: Node3D = $card
@onready var card_outline: Node3D = $cardOutline
@onready var card_image: MeshInstance3D = $CardImage
@onready var rarity_mesh: MeshInstance3D = $card/rarity
@onready var name_label: Label3D = $NameLabel
@onready var attack_label: Label3D = $AttackLabel
@onready var defense_label: Label3D = $DefenseLabel
@onready var description_label: Label3D = $DescriptionLabel
@onready var effects_label: Label3D = $EffectsLabel
@onready var rarity_label: Label3D = $RarityLabel
@onready var area: Area3D = $Area3D

var card_data: Dictionary = {}
var is_stack_decoration: bool = false
var _localized_font_sizes: Dictionary = {}

# HP-Werte).
var max_hp: int = 0
var current_hp: int = 0
var attack_value: int = 0
var _first_hit_shield_available: bool = false
var _last_stand_available: bool = false
var _grave_return_available: bool = false
var _skip_next_attack: bool = false
var _curse_penalty: int = 0
var eternal_suffering_damage: int = 0
var _combat_indicators: COMBAT_INDICATORS_SCRIPT
var _disabled := false
var event_block_turns: int = 0
var stats_hidden := false # Local viewer presentation; never changes combat state.
var _event_block_badge: Node3D

# Transient match data travels with stolen cards in a battle deck. It is never
# written back to CardDatabase, the collection, or a player's saved deck.
const EVENT_MATCH_STATE_KEY := "_match_combat_state"

var _card_material: StandardMaterial3D

var _animated_image := false
var _frame_count := 1
var _frame_columns := 1
var _frame_rows := 1
var _frame_fps := 8.0

var _current_frame := 0
var _frame_timer := 0.0

signal died(card: Card3D)
signal card_hovered(card: Card3D)
signal card_unhovered(card: Card3D)
signal combat_effects_changed(card: Card3D)

# Wird genau am Scheitelpunkt der Angriffsanimation ausgeloest (nach
# dem Hinflug + "Rammstoss", bevor die Karte wieder zurueckfliegt).
# Aufrufer (z.B. GameTable._resolve_duel) sollen HIER Schaden/Blut/SFX
# anwenden statt erst auf das komplette Ende von
# play_attack_animation() zu warten — sonst wirken Treffer viel zu spaet.
signal attack_impact

# Wird ausgeloest, wenn play_attack_animation() komplett fertig ist
# (Karte wieder an ihrer Ausgangsposition). Da play_attack_animation()
# als "fire and forget" (ohne await) gestartet wird, kann der Aufrufer
# ueber dieses Signal trotzdem auf das echte Ende warten, statt auf den
# (nicht einfangbaren) Rueckgabewert der Coroutine.
signal attack_finished

@export_group("Auswahl-Highlight")
@export var select_highlight_color: Color = Color(1.0, 0.92, 0.3, 1.0)
@export var select_lift: float = 0.08
@export var select_duration: float = 0.15

@export_group("Treffer-Blut")
@export_range(0.1, 30.0, 0.1) var blood_fade_duration: float = 5.0
@export_range(0.0, 1.0, 0.01) var blood_max_coverage: float = 0.58
@export var blood_color: Color = Color(0.65, 0.015, 0.025, 0.92)

const BLOOD_MIX_SHADER := preload("res://assets/shader/bloodMix.gdshader")
const HOLO_SHADER := preload("res://assets/shader/holo.gdshader")
const SPECIAL_AURA_SHADER := preload("res://assets/shader/special_card_aura.gdshader")
const DEATH_DISSOLVE_SCRIPT := preload("res://scripts/card/CardDeathDissolve.gd")
const DIORAMA_SCRIPT := preload("res://scripts/card/CardDiorama.gd")
const COMBAT_INDICATORS_SCRIPT := preload("res://scripts/card/CardCombatIndicators.gd")
const EVENT_BLOCK_KNIFE_SCENE := preload("res://scenes/effects/EventBlockKnife.tscn")
var _death_dissolve: RefCounted
var _diorama_art: CardDiorama
var _diorama_scene_path := ""
var _special_aura: MeshInstance3D
var _holo_body_base_material: Material
var _holo_body_material: Material
var _holo_body_pass: ShaderMaterial
var _holo_image_pass: ShaderMaterial
const BLOOD_NOISE := preload("res://assets/shader/card_blood_noise.tres")
var _blood_materials: Array[ShaderMaterial] = []
var _blood_targets: Array[MeshInstance3D] = []
var _blood_intensity: float = 0.0
var _blood_fade_speed: float = 0.0

var _is_selected: bool = false
var _select_base_position: Vector3 = Vector3.ZERO
var _select_tween: Tween = null
var _has_select_base_position := false
var _is_card_hovered := false
const EFFECT_PLACEHOLDER := "res://assets/effects/placeholder.png"
const EFFECT_ICON_HOLO_SHADER := preload("res://assets/shader/effect_icon_holo.gdshader")

@onready var effect_icon_1: Sprite3D = $EffectSlot1
@onready var effect_icon_2: Sprite3D = $EffectSlot2
@onready var effect_icon_area_1: Area3D = $EffectSlot1Area
@onready var effect_icon_area_2: Area3D = $EffectSlot2Area
# Wie "heftig" sich der Rarity-Shader pro Stufe verhaelt.
# common bleibt bewusst praktisch unbewegt/ruhig, exotic ist maximal
# chaotisch und hell.
static var _rarity_presets: Dictionary[String, RarityPreset] = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _rarity_glow_material: ShaderMaterial = null


static func _static_init() -> void:
	_rarity_presets = {
		"common":    RarityPreset.new(0.0, 0.0, 2.0, 0.0, 0.0, 0.0, 0.18, 1.5),
"uncommon":  RarityPreset.new(0.5, 0.5, 3.0, 0.15, 0.15, 1.2, 0.22, 3.0),
"rare":      RarityPreset.new(0.9, 0.9, 4.0, 0.3, 0.2, 1.6, 0.28, 5.0),
"epic":      RarityPreset.new(1.3, 1.3, 5.0, 0.45, 0.3, 2.0, 0.32, 8.0),
"legendary": RarityPreset.new(1.7, 1.7, 6.0, 0.55, 0.35, 2.4, 0.38, 12.0),
"mythic": RarityPreset.new(3.2, 3.0, 9.0, 0.95, 0.65, 4.0, 0.85, 34.0),
"exotic": RarityPreset.new(3.8, 3.8, 10.0, 1.0, 0.75, 4.8, 1.0, 45.0),
"secret": RarityPreset.new(1.0, 0.35, 3.0, 0.0, 0.0, 0.0, 0.6, 6.0),
	}


func _ready() -> void:
	_rng.seed = hash(Time.get_ticks_usec() ^ int(get_instance_id()))

	_ensure_materials_resolved()
	_connect_effect_icon_areas()

	if is_stack_decoration:
		# Reine Deko-Ruecken: kein Shine-Sweep, kein Rarity-Glow, keine
		# Klick-Area noetig — und sie soll auch nicht versehentlich
		# klickbar/hoverbar sein.
		if area != null:
			area.monitoring = false
			area.monitorable = false
		_set_effect_icon_areas_enabled(false)
		rarity_mesh.visible = false
		return

	_connect_card_hover_area()
	_combat_indicators = COMBAT_INDICATORS_SCRIPT.new()
	_combat_indicators.name = "CombatIndicators"
	add_child(_combat_indicators)
	_combat_indicators.configure([effect_icon_1, effect_icon_2])
	Localization.locale_changed.connect(_on_locale_changed)
	_refresh_localized_text()

func _process(delta: float) -> void:
	# Static card art and cards thrown off the table must fade just as well.
	_update_blood_fade(delta)
	if not _animated_image:
		return

	if _card_material == null:
		return

	_frame_timer += delta

	if _frame_timer < 1.0 / _frame_fps:
		return

	_frame_timer = 0.0

	_current_frame = (_current_frame + 1) % _frame_count
	_update_card_frame()


## Called only once death is confirmed, never from take_damage/died: effects
## such as Last Stand may still save the card before the table starts its flight.
func begin_death_dissolve() -> void:
	if _death_dissolve != null:
		return
	if is_instance_valid(_event_block_badge):
		_event_block_badge.reset()
	_death_dissolve = DEATH_DISSOLVE_SCRIPT.new()
	# Stop indicator tweens before dissolve replaces the seal materials.
	if _combat_indicators != null:
		_combat_indicators.retire()
	# Keep the exact currently displayed atlas frame for the whole flight.
	_animated_image = false
	var body := card_model.get_node_or_null("Cube") as MeshInstance3D
	var icons: Array[Sprite3D] = [effect_icon_1, effect_icon_2]
	_death_dissolve.begin(self, body, card_image, icons)
	_set_effect_icon_areas_enabled(false)
	for label in find_children("*", "Label3D", true, false):
		(label as Label3D).hide()
	for decoration in [card_outline, rarity_mesh, _special_aura, _event_block_badge]:
		if is_instance_valid(decoration):
			(decoration as Node3D).hide()
	# Blood's gameplay-visible state remains intact while its extra render
	# passes are detached by the helper, so they cannot cover dissolved holes.


func set_death_dissolve_progress(progress: float) -> void:
	begin_death_dissolve()
	_death_dissolve.set_progress(progress)


func get_death_dissolve_progress() -> float:
	if _death_dissolve == null:
		return 0.0
	return _death_dissolve.get_progress()


func _ensure_materials_resolved() -> void:
	if _rarity_glow_material == null and rarity_mesh != null:
		var shared_rarity_mat: ShaderMaterial = rarity_mesh.get_surface_override_material(0) as ShaderMaterial
		
		if shared_rarity_mat != null:
			_rarity_glow_material = shared_rarity_mat.duplicate(true) as ShaderMaterial
			rarity_mesh.set_surface_override_material(0, _rarity_glow_material)


func setup(data: Dictionary) -> void:
	if _combat_indicators != null:
		_combat_indicators.reset()
	if is_instance_valid(_event_block_badge):
		_event_block_badge.reset()
	# Network snapshots rebuild the same card's art. They must neither clean
	# its current stain nor restart its timer. A different card starts clean.
	var previous_identity := str(card_data.get("instance_id", "")) + ":" + str(card_data.get("id", card_data.get("name", "")))
	var next_identity := str(data.get("instance_id", "")) + ":" + str(data.get("id", data.get("name", "")))
	if previous_identity != next_identity or is_stack_decoration:
		_clear_blood()
	card_data = data.duplicate(true)
	card_data.erase(EVENT_MATCH_STATE_KEY)

	var attack: int = int(data.get("attack", 0))
	var defense: int = int(data.get("defense", 0))
	var rarity: String = str(data.get("rarity", "common")).to_lower()
	var image_path: String = str(data.get("image", ""))
	
	_animated_image = bool(data.get("animated", false))
	_frame_count = int(data.get("frame_count", 1))
	_frame_columns = int(data.get("frame_columns", _frame_count))
	_frame_rows = int(data.get("frame_rows", 1))
	_frame_fps = float(data.get("frame_fps", 8.0))

	_current_frame = 0
	_frame_timer = 0.0

	if CardData.has_effect(data, "swap_stats"):
		var original_attack := attack
		attack = defense
		defense = original_attack

	attack_value = attack
	max_hp = defense
	current_hp = defense
	_first_hit_shield_available = CardData.has_effect(data, "shield_first_hit")
	_last_stand_available = CardData.has_effect(data, "last_stand")
	_grave_return_available = CardData.has_effect(data, "grave_return")
	_skip_next_attack = false
	_curse_penalty = 0
	eternal_suffering_damage = 0
	if has_meta("eternal_suffering_spread"):
		remove_meta("eternal_suffering_spread")
	if has_meta("event_death_awarded"):
		remove_meta("event_death_awarded")
	event_block_turns = 0
	_clear_poison_state()
	if has_meta("chick_survived_turns"):
		remove_meta("chick_survived_turns")
	if has_meta("last_survival_effect"):
		remove_meta("last_survival_effect")

	attack_label.text = "?" if stats_hidden else str(attack)
	_update_hp_label()
	_refresh_localized_text(true)
	effects_label.visible = false
	_apply_effect_icons()
	var combat_card := CardData.is_combat_card(data)
	attack_label.visible = combat_card
	defense_label.visible = combat_card
	$AttackTitle.visible = combat_card
	$DefenseTitle.visible = combat_card

	_ensure_materials_resolved()
	_apply_rarity_style(rarity)
	_apply_card_image(image_path)
	_apply_holo_style()
	_apply_special_aura()
	var saved_combat_state: Variant = data.get(EVENT_MATCH_STATE_KEY, {})
	if saved_combat_state is Dictionary and not saved_combat_state.is_empty():
		_restore_combat_state(saved_combat_state, false)
	else:
		_update_event_block_badge(false)
		_refresh_combat_indicators(false)


func _on_locale_changed() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	_refresh_localized_text()
	_update_event_block_badge()


## Only printed text changes. Calling setup here would heal damaged cards,
## restore consumed effects and reset animated artwork during a live match.
func _refresh_localized_text(animate_description: bool = false) -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not is_node_ready() or is_stack_decoration:
		return
	$AttackTitle.text = Localization.text("Attack")
	$DefenseTitle.text = Localization.text("Defense")
	$DescriptionTitle.text = Localization.text("Description")
	_fit_localized_label($AttackTitle, 0.22)
	_fit_localized_label($DefenseTitle, 0.22)
	if card_data.is_empty():
		return
	name_label.text = Localization.text(str(card_data.get("name", "Unknown")))
	_fit_localized_label(name_label, 0.70)
	var description := "?" if stats_hidden else Localization.text(str(card_data.get("description", "")))
	description_label.play(_wrap_text(description, 45))
	if not animate_description:
		description_label.skip()
	effects_label.text = _build_effects_summary()
	var rarity := str(card_data.get("rarity", "common")).to_upper()
	var category_label := rarity if CardData.is_combat_card(card_data) else "SONDERKARTE"
	if card_data.get("permanent_upgrade", false) == true:
		category_label = "PERMANENT"
	rarity_label.text = Localization.text(category_label)


func _fit_localized_label(label: Label3D, available_width: float) -> void:
	# Keep the complete translated name inside the physical card. Start from
	# the scene's original size so shorter names/languages grow back normally.
	if not _localized_font_sizes.has(label):
		_localized_font_sizes[label] = label.font_size
	label.font_size = int(_localized_font_sizes[label])
	var font: Font = label.font if label.font != null else ThemeDB.fallback_font
	var pixel_width := available_width / maxf(label.pixel_size * absf(label.scale.x), 0.000001) - 2.0 * label.outline_size
	while label.font_size > 1 and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x > pixel_width:
		label.font_size -= 1


## Local presentation only: called once by the table at a damage impact.
func show_blood_hit(intensity: float = 1.0) -> void:
	if is_stack_decoration or not is_node_ready() or intensity <= 0.0:
		return
	_ensure_blood_materials()
	_blood_intensity = clampf(_blood_intensity + intensity, 0.0, 1.0)
	_blood_fade_speed = _blood_intensity / maxf(blood_fade_duration, 0.1)
	for i in _blood_targets.size():
		_blood_targets[i].material_overlay = _blood_materials[i]
	_update_blood_materials()


func get_blood_intensity() -> float:
	return _blood_intensity


func _ensure_blood_materials() -> void:
	if not _blood_materials.is_empty():
		return
	# Both overlays use card-local XY coordinates, so a stain continues from
	# the printed card face onto its separate (possibly animated) artwork.
	var noise_offset := Vector2(_rng.randf(), _rng.randf())
	var body_mesh := card_model.get_node_or_null("Cube") as MeshInstance3D
	var image_transform := global_transform.affine_inverse() * card_image.global_transform
	var image_bounds: AABB = image_transform * card_image.get_aabb()
	var image_rect := Vector4(image_bounds.position.x, image_bounds.position.y, image_bounds.end.x, image_bounds.end.y)
	for mesh in [body_mesh, card_image]:
		if mesh == null:
			continue
		var material := ShaderMaterial.new()
		material.shader = BLOOD_MIX_SHADER
		material.render_priority = 2
		material.set_shader_parameter("noise", BLOOD_NOISE)
		material.set_shader_parameter("noise_offset", noise_offset)
		material.set_shader_parameter("noise_shading", 0.35)
		material.set_shader_parameter("use_card_projection", true)
		# The transparent artwork does not write depth. Exclude its rectangle
		# on the body pass so the same stain never blends twice over the art.
		material.set_shader_parameter("exclude_artwork", mesh == body_mesh)
		material.set_shader_parameter("artwork_rect", image_rect)
		material.set_shader_parameter("card_space_transform", global_transform.affine_inverse() * mesh.global_transform)
		_blood_materials.append(material)
		_blood_targets.append(mesh)


func _update_blood_fade(delta: float) -> void:
	if _blood_intensity <= 0.0:
		return
	if is_stack_decoration:
		_clear_blood()
		return
	_blood_intensity = maxf(_blood_intensity - _blood_fade_speed * delta, 0.0)
	if _blood_intensity <= 0.0:
		_clear_blood()
	else:
		_update_blood_materials()


func _update_blood_materials() -> void:
	for material in _blood_materials:
		# Shrinking the threshold removes the edges of each stain as its
		# opacity fades. At zero the overlay is detached completely.
		material.set_shader_parameter("intensity", lerpf(0.0, blood_max_coverage, sqrt(_blood_intensity)))
		material.set_shader_parameter("opacity", _blood_intensity)
		material.set_shader_parameter("color", blood_color)


func _clear_blood() -> void:
	_blood_intensity = 0.0
	_blood_fade_speed = 0.0
	for i in _blood_targets.size():
		if is_instance_valid(_blood_targets[i]) and _blood_targets[i].material_overlay == _blood_materials[i]:
			_blood_targets[i].material_overlay = null
	_update_blood_materials()


func _update_hp_label() -> void:
	attack_label.text = "?" if stats_hidden else str(attack_value)
	defense_label.text = "?" if stats_hidden else str(current_hp)


func _build_effects_summary() -> String:
	if stats_hidden:
		return "?"
	var effect_names: Array[String] = []
	for effect in get_available_effects():
		var label := _format_effect_label(effect)
		if label != "":
			effect_names.append(label)
	if effect_names.is_empty():
		return Localization.text("Effects: -")
	return Localization.text("Effects: ") + " • ".join(effect_names)


func _format_effect_label(effect: Dictionary) -> String:
	var label := EffectPresentation.get_title(EffectPresentation.resolve_defaults(effect))
	if effect.has("percent"):
		label += " %d%%" % int(round(float(effect.get("percent", 0.0)) * 100.0))
	elif effect.has("value"):
		var value := float(effect.get("value", 0.0))
		if value > 0.0 and value <= 1.0:
			label += " %d%%" % int(round(value * 100.0))
		else:
			label += " +%d" % int(round(value))
	elif effect.has("damage") and effect.has("turns"):
		label += Localization.format_text(" %d/%dT", [int(effect.get("damage", 0)), int(effect.get("turns", 0))])
	return label


func heal(amount: int, allow_overheal: bool = false) -> void:
	if amount <= 0 or is_dead():
		return

	if allow_overheal:
		current_hp += amount
	else:
		# A normal heal can fill missing health but must never remove health
		# already granted by an overheal or restored battle snapshot.
		current_hp += mini(amount, maxi(max_hp - current_hp, 0))

	_update_hp_label()


func consume_first_hit_shield() -> bool:
	if not _first_hit_shield_available:
		return false
	_first_hit_shield_available = false
	_refresh_combat_indicators()
	return true


func try_survive_death() -> bool:
	if not is_dead():
		return false
	if has_meta("last_survival_effect"):
		remove_meta("last_survival_effect")

	if _last_stand_available:
		_last_stand_available = false
		current_hp = 1
		_update_hp_label()
		set_meta("last_survival_effect", "last_stand")
		_refresh_combat_indicators()
		return true
	if _grave_return_available:
		_grave_return_available = false
		current_hp = int(max(round(float(max_hp) * 0.5), 1))
		_update_hp_label()
		set_meta("last_survival_effect", "grave_return")
		_refresh_combat_indicators()
		return true
	return false


func apply_curse(value: int) -> void:
	if value <= 0:
		return
	_curse_penalty += mini(value, attack_value)
	attack_value = int(max(attack_value - value, 0))
	_update_hp_label()
	_refresh_combat_indicators()


func stun_next_attack() -> void:
	_skip_next_attack = true
	_refresh_combat_indicators()


func consume_stun() -> bool:
	if not _skip_next_attack:
		return false
	_skip_next_attack = false
	_refresh_combat_indicators()
	return true


func apply_poison(damage: int, turns: int) -> void:
	if damage <= 0 or turns <= 0:
		_clear_poison_state()
	else:
		set_meta("poison_damage", damage)
		set_meta("poison_turns", turns)
	_refresh_combat_indicators()


func apply_eternal_suffering() -> void:
	# Reapplication cannot reset the accumulated suffering.
	eternal_suffering_damage = maxi(eternal_suffering_damage, 1)
	_refresh_combat_indicators()


func cleanse_eternal_suffering_from_neighbor() -> void:
	eternal_suffering_damage = 0
	_refresh_combat_indicators()


func advance_eternal_suffering() -> void:
	if eternal_suffering_damage > 0:
		eternal_suffering_damage += 2
		_refresh_combat_indicators()


func tick_poison() -> void:
	var turns := maxi(int(get_meta("poison_turns", 0)) - 1, 0)
	if turns == 0:
		_clear_poison_state()
	else:
		set_meta("poison_turns", turns)
	_refresh_combat_indicators()


## The printed collection data stays intact; consumed charges are battle-only.
func get_available_effects() -> Array[Dictionary]:
	if stats_hidden:
		return []
	var availability := _get_effect_availability()
	var result: Array[Dictionary] = []
	for effect in CardData.get_active_effects(card_data):
		if bool(availability.get(str(effect.get("type", "")), true)):
			result.append(effect)
	return result


func _get_effect_availability() -> Dictionary:
	return {
		"shield_first_hit": _first_hit_shield_available,
		"last_stand": _last_stand_available,
		"grave_return": _grave_return_available,
	}


func _refresh_combat_indicators(animate: bool = true) -> void:
	if _combat_indicators == null or _death_dissolve != null:
		return
	var effects := CardData.get_active_effects(card_data)
	var availability := _get_effect_availability()
	_combat_indicators.sync_seals(effects, availability, animate)
	var areas: Array[Area3D] = [effect_icon_area_1, effect_icon_area_2]
	for i in range(areas.size()):
		_set_effect_icon_area_enabled(areas[i], i < effects.size() and bool(availability.get(str(effects[i].get("type", "")), true)))
	_combat_indicators.sync_statuses({
		"poison": int(get_meta("poison_turns", 0)),
		"stun": 1 if _skip_next_attack else 0,
		"curse": _curse_penalty,
		"eternal_suffering": eternal_suffering_damage,
	}, animate)
	_combat_indicators.visible = not stats_hidden
	if stats_hidden:
		effect_icon_1.hide()
		effect_icon_2.hide()
	effects_label.text = _build_effects_summary()
	combat_effects_changed.emit(self)


func set_stats_hidden(value: bool) -> void:
	if stats_hidden == value:
		return
	stats_hidden = value
	_update_hp_label()
	_refresh_localized_text()
	_update_event_block_badge()
	_refresh_combat_indicators(false)


## Blocks attacks and counterattacks until the table has ticked this card at
## the end of the requested number of its owner's turns. Reapplying refreshes
## the duration without shortening an existing block.
func apply_event_block(turns: int) -> void:
	event_block_turns = maxi(event_block_turns, maxi(turns, 0))
	_update_event_block_badge()


func is_event_blocked() -> bool:
	return event_block_turns > 0


func tick_event_block() -> void:
	event_block_turns = maxi(event_block_turns - 1, 0)
	_update_event_block_badge()


## Strength follows the current combat values, including damage and curses.
## Scaling current and maximum HP preserves damage proportion and overheal.
func apply_event_strength(multiplier: float) -> void:
	if is_dead() or not is_finite(multiplier) or multiplier <= 1.0:
		return
	attack_value = maxi(ceili(float(attack_value) * multiplier), 0)
	max_hp = maxi(ceili(float(max_hp) * multiplier), 1)
	current_hp = maxi(ceili(float(current_hp) * multiplier), 1)
	_update_hp_label()


func _update_event_block_badge(animate: bool = true) -> void:
	if not is_node_ready() or is_stack_decoration:
		return
	if _death_dissolve != null:
		return
	if _event_block_badge == null and event_block_turns <= 0:
		return
	if _event_block_badge == null:
		_event_block_badge = EVENT_BLOCK_KNIFE_SCENE.instantiate() as Node3D
		_event_block_badge.name = "EventBlockBadge"
		add_child(_event_block_badge)
	_event_block_badge.sync(event_block_turns, stats_hidden, animate)


# Fuegt dieser Karte Schaden zu und gibt true zurueck, wenn die Karte
# dadurch stirbt (current_hp <= 0). HP wird nie unter 0 angezeigt.
func take_damage(amount: int) -> bool:
	if amount <= 0 or is_dead():
		return is_dead()
	current_hp = int(max(current_hp - amount, 0))
	_update_hp_label()

	if current_hp <= 0:
		died.emit(self)
		return true
	return false


func is_dead() -> bool:
	return current_hp <= 0


## Returns the gameplay-relevant state as plain Variants so the authoritative
## host can send it through Godot's RPC layer. Visual/transient state (tweens,
## materials and selection) deliberately stays local.
func get_network_state() -> Dictionary:
	var state := _get_combat_state()
	state["card_data"] = card_data.duplicate(true)
	return state


## A stolen card stays the same battle instance when it is drawn again.
func export_event_deck_card() -> Dictionary:
	var data := card_data.duplicate(true)
	data[EVENT_MATCH_STATE_KEY] = _get_combat_state()
	return data


func _get_combat_state() -> Dictionary:
	var state := {
		"max_hp": max_hp,
		"current_hp": current_hp,
		"attack_value": attack_value,
		"first_hit_shield_available": _first_hit_shield_available,
		"last_stand_available": _last_stand_available,
		"grave_return_available": _grave_return_available,
		"skip_next_attack": _skip_next_attack,
		"curse_penalty": _curse_penalty,
		"eternal_suffering_damage": eternal_suffering_damage,
		"event_block_turns": event_block_turns,
		"poison_damage": int(get_meta("poison_damage", 0)),
		"poison_turns": int(get_meta("poison_turns", 0)),
	}
	# Growth belongs to this battle instance, so network snapshots and Steel
	# preserve it without adding age to the catalog or permanent collection.
	if str(card_data.get("id", "")) == "chick":
		state["chick_survived_turns"] = clampi(int(get_meta("chick_survived_turns", 0)), 0, 10)
	return state


## Restores a snapshot created by get_network_state(). Calling setup first
## rebuilds the card's visual presentation; the mutable combat values then
## replace setup's defaults.
func apply_network_state(state: Dictionary) -> void:
	var data := state.get("card_data", {}) as Dictionary
	var same_card := not card_data.is_empty() and card_data == data
	# Repeated snapshots must not rebuild seals or restart their exit animation.
	if not same_card:
		setup(data.duplicate(true))
	_restore_combat_state(state, same_card)


func _restore_combat_state(state: Dictionary, animate_indicators: bool = true) -> void:
	max_hp = maxi(int(state.get("max_hp", max_hp)), 1)
	# Lifesteal can intentionally exceed max_hp; snapshots and theft must
	# preserve that health as well as damage already received.
	current_hp = maxi(int(state.get("current_hp", current_hp)), 0)
	attack_value = maxi(int(state.get("attack_value", attack_value)), 0)
	_first_hit_shield_available = bool(state.get("first_hit_shield_available", _first_hit_shield_available))
	_last_stand_available = bool(state.get("last_stand_available", _last_stand_available))
	_grave_return_available = bool(state.get("grave_return_available", _grave_return_available))
	_skip_next_attack = bool(state.get("skip_next_attack", _skip_next_attack))
	_curse_penalty = maxi(int(state.get("curse_penalty", 0)), 0)
	eternal_suffering_damage = maxi(int(state.get("eternal_suffering_damage", 0)), 0)
	event_block_turns = maxi(int(state.get("event_block_turns", 0)), 0)
	if str(card_data.get("id", "")) == "chick":
		set_meta("chick_survived_turns", clampi(int(state.get("chick_survived_turns", 0)), 0, 10))
	elif has_meta("chick_survived_turns"):
		remove_meta("chick_survived_turns")

	_update_hp_label()
	_update_event_block_badge(animate_indicators)

	var poison_turns := maxi(int(state.get("poison_turns", 0)), 0)
	if poison_turns > 0:
		set_meta("poison_turns", poison_turns)
		set_meta("poison_damage", maxi(int(state.get("poison_damage", 0)), 0))
	else:
		_clear_poison_state()
	_refresh_combat_indicators(animate_indicators)


func _clear_poison_state() -> void:
	if has_meta("poison_turns"):
		remove_meta("poison_turns")
	if has_meta("poison_damage"):
		remove_meta("poison_damage")


func _apply_card_image(image_path: String) -> void:
	var texture: Texture2D
	var room_path := str(card_data.get("artwork_scene", ""))
	if not room_path.is_empty() and not is_stack_decoration:
		if not is_instance_valid(_diorama_art) or _diorama_scene_path != room_path:
			_clear_diorama_art()
			var room_scene := load(room_path) as PackedScene
			if room_scene != null:
				_diorama_art = DIORAMA_SCRIPT.new() as CardDiorama
				_diorama_art.name = "CardDiorama"
				add_child(_diorama_art)
				_diorama_art.configure(card_image, room_scene)
				_diorama_scene_path = room_path
		if is_instance_valid(_diorama_art):
			texture = _diorama_art.get_texture()
			_animated_image = false
	else:
		_clear_diorama_art()
	if texture == null and not image_path.is_empty():
		texture = load(image_path) as Texture2D
	if texture == null:
		card_image.hide()
		_card_material = null
		if not image_path.is_empty() or not room_path.is_empty() and not is_stack_decoration:
			push_warning("Kartenbild nicht gefunden: " + (room_path if not room_path.is_empty() else image_path))
		return
	card_image.show()

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR if is_instance_valid(_diorama_art) else BaseMaterial3D.TEXTURE_FILTER_NEAREST

	_card_material = mat
	card_image.material_override = _card_material

	if _animated_image:
		_update_card_frame()
	else:
		_card_material.uv1_scale = Vector3.ONE
		_card_material.uv1_offset = Vector3.ZERO


func _clear_diorama_art() -> void:
	if is_instance_valid(_diorama_art):
		_diorama_art.queue_free()
	_diorama_art = null
	_diorama_scene_path = ""
	if _holo_image_pass != null:
		_holo_image_pass.set_shader_parameter("albedo_texture", null)


func _apply_rarity_style(rarity: String) -> void:
	var color: Color = _get_rarity_color(rarity)
	var preset: RarityPreset = _rarity_presets.get(rarity, _rarity_presets["common"]) as RarityPreset

	rarity_label.modulate = color

	_apply_static_outline_color(card_outline, Color(0.08, 0.10, 0.13) if rarity == "secret" else color)

	if _rarity_glow_material == null:
		return

	_rarity_glow_material.set_shader_parameter("rarity_color", color)
	_rarity_glow_material.set_shader_parameter("rainbow_mode", rarity == "secret" and not is_stack_decoration)
	_rarity_glow_material.set_shader_parameter("rainbow_clock_offset", 0.0)
	_rarity_glow_material.set_shader_parameter("intensity", preset.intensity)
	_rarity_glow_material.set_shader_parameter("scroll_speed", preset.scroll_speed)
	_rarity_glow_material.set_shader_parameter("band_density", preset.band_density)
	_rarity_glow_material.set_shader_parameter("jaggedness", preset.jaggedness)
	_rarity_glow_material.set_shader_parameter("pulse_strength", preset.pulse_strength)
	_rarity_glow_material.set_shader_parameter("pulse_speed", preset.pulse_speed)
	_rarity_glow_material.set_shader_parameter("base_glow", preset.base_glow)
	_rarity_glow_material.set_shader_parameter("emission_boost", preset.emission_boost)


func _apply_holo_style() -> void:
	var body := card_model.get_node_or_null("Cube") as MeshInstance3D
	var enabled := CardData.is_holo(card_data) and not is_stack_decoration
	if not enabled:
		if body != null and _holo_body_base_material != null:
			body.set_surface_override_material(1, _holo_body_base_material)
		if _card_material != null and _card_material.next_pass == _holo_image_pass:
			_card_material.next_pass = null
		return
	if body != null and body.mesh != null and body.mesh.get_surface_count() > 1:
		if _holo_body_material == null:
			_holo_body_base_material = body.get_active_material(1)
			if _holo_body_base_material != null:
				_holo_body_material = _holo_body_base_material.duplicate(true)
				var source := _holo_body_base_material as BaseMaterial3D
				_holo_body_pass = _make_holo_pass(source.albedo_texture if source != null else null)
				# Preserve the existing print/shine chain and leave back surface 0
				# untouched, so face-down cards never disclose their finish.
				_holo_body_pass.next_pass = _holo_body_material.next_pass
				_holo_body_material.next_pass = _holo_body_pass
		if _holo_body_material != null:
			body.set_surface_override_material(1, _holo_body_material)
	if _card_material != null:
		if _holo_image_pass == null:
			_holo_image_pass = _make_holo_pass(_card_material.albedo_texture)
		_holo_image_pass.set_shader_parameter("albedo_texture", _card_material.albedo_texture)
		_card_material.next_pass = _holo_image_pass
		_update_holo_artwork_uv()


func _apply_special_aura() -> void:
	var enabled := str(card_data.get("category", "")).to_lower() == "special" and not is_stack_decoration
	if not enabled:
		if is_instance_valid(_special_aura):
			_special_aura.hide()
		return
	if not is_instance_valid(_special_aura):
		# One procedural veil per special, independent of Holo/shine/blood passes.
		# Front-face culling keeps unrevealed pack cards and backs anonymous.
		_special_aura = MeshInstance3D.new()
		_special_aura.name = "SpecialAura"
		var quad := QuadMesh.new()
		quad.size = Vector2(0.972, 1.32)
		_special_aura.mesh = quad
		_special_aura.position.z = 0.018
		_special_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_special_aura.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		var material := ShaderMaterial.new()
		material.shader = SPECIAL_AURA_SHADER
		material.render_priority = 1
		_special_aura.material_override = material
		add_child(_special_aura)
	# Stable across setup/refresh, with different motion for different card types.
	var identity := str(card_data.get("instance_id", "")) + ":" + str(card_data.get("id", card_data.get("card_id", "")))
	var aura_material := _special_aura.material_override as ShaderMaterial
	aura_material.set_shader_parameter("phase", float(absi(hash(identity)) % 10000) * 0.001)
	_special_aura.show()


func _make_holo_pass(texture: Texture2D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = HOLO_SHADER
	material.render_priority = 1
	material.set_shader_parameter("albedo_texture", texture)
	material.set_shader_parameter("overlay_opacity", 0.32)
	material.set_shader_parameter("iridescence_intensity", 0.72)
	material.set_shader_parameter("emission_strength", 0.3)
	material.set_shader_parameter("flow_speed", 0.22)
	return material


func _update_holo_artwork_uv() -> void:
	if _holo_image_pass == null or _card_material == null:
		return
	var uv_scale := _card_material.uv1_scale
	var uv_offset := _card_material.uv1_offset
	_holo_image_pass.set_shader_parameter("artwork_uv_scale", Vector2(uv_scale.x, uv_scale.y))
	_holo_image_pass.set_shader_parameter("artwork_uv_offset", Vector2(uv_offset.x, uv_offset.y))

# Wendet rekursiv ein einfaches, statisches StandardMaterial3D auf alle
# MeshInstance3D-Kinder von root an. Bewusst KEIN Shader hier, da
# StandardMaterial3D unabhaengig vom UV-Layout des importierten GLB
# funktioniert (anders als der Custom-Shader, der empfindlich auf
# unbekannte Mesh-Strukturen reagieren kann).
func _apply_static_outline_color(root: Node, color: Color) -> void:
	if root == null:
		return

	if root is MeshInstance3D:
		var mesh_instance: MeshInstance3D = root as MeshInstance3D
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.45
		mat.roughness = 0.35
		mat.metallic = 0.2
		mesh_instance.material_override = mat

	for child: Node in root.get_children():
		_apply_static_outline_color(child, color)


func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common":
			return Color(0.55, 0.55, 0.55, 1)
		"uncommon":
			return Color(0.25, 0.85, 0.35, 1)
		"rare":
			return Color(0.2, 0.45, 1.0, 1)
		"epic":
			return Color(0.75, 0.25, 1.0, 1)
		"legendary":
			return Color(1.0, 0.72, 0.12, 1)
		"mythic":
			return Color(0.18, 0.08, 0.45, 1)
		"exotic":
			return Color(1.0, 0.05, 0.05, 1)
		"secret":
			return RarityEffectsData.get_color("secret")
		_:
			return Color(0.45, 0.45, 0.45, 1)


func _shorten_description(text: String, max_chars: int = 95) -> String:
	if text.length() <= max_chars:
		return text
	return text.substr(0, max_chars - 3) + "..."


# --- Auswahl-Highlight (fuer GameTable-Kampfauswahl) ---------------------
#
# Wird vom GameTable aufgerufen, wenn der Spieler diese Karte als
# Angreifer/Ziel anklickt. Hebt die Karte leicht an und faerbt die
# RarityGlowPlane kurzfristig in select_highlight_color um, damit klar
# erkennbar ist, welche Karte gerade ausgewaehlt ist.
func set_selected(selected: bool) -> void:
	if selected == _is_selected:
		return

	if _select_tween != null:
		_select_tween.kill()
		_select_tween = null

	_is_selected = selected

	if selected:
		_select_base_position = position
		_has_select_base_position = true

		_select_tween = create_tween().set_parallel(true)
		_select_tween.tween_property(
			self,
			"position",
			_select_base_position + Vector3(0, select_lift, 0),
			select_duration
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

		_set_glow_override_color(select_highlight_color)
	else:
		var target_pos := _select_base_position if _has_select_base_position else position

		_select_tween = create_tween().set_parallel(true)
		_select_tween.tween_property(
			self,
			"position",
			target_pos,
			select_duration
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

		_restore_glow_rarity_color()

func _set_glow_override_color(color: Color) -> void:
	_apply_static_outline_color(card_outline, color)

	if _rarity_glow_material == null:
		return
	_rarity_glow_material.set_shader_parameter("rarity_color", color)
	_rarity_glow_material.set_shader_parameter("emission_boost", 12.0)


func _restore_glow_rarity_color() -> void:
	var rarity: String = str(card_data.get("rarity", "common")).to_lower()
	var color: Color = _get_rarity_color(rarity)
	var preset: RarityPreset = _rarity_presets.get(rarity, _rarity_presets["common"]) as RarityPreset

	_apply_static_outline_color(card_outline, Color(0.08, 0.10, 0.13) if rarity == "secret" else color)

	if _rarity_glow_material == null:
		return

	_rarity_glow_material.set_shader_parameter("rarity_color", color)
	_rarity_glow_material.set_shader_parameter("emission_boost", preset.emission_boost)


# --- Attack-Animation -----------------------------------------------------

@export_group("Attack-Animation")
@export var attack_card_footprint: Vector2 = Vector2(0.78, 1.08)
@export var attack_out_duration: float = 0.18
@export var attack_hit_duration: float = 0.08
@export var attack_return_duration: float = 0.22
@export var attack_overshoot_scale: float = 1.12

var _attack_impact_release_requested := true

# Laesst die Karte bis zum ersten Kontakt mit der Zielkarte vorfliegen,
# danach kurz hineinstossen ("ramming") und anschliessend zurueck an ihre
# urspruengliche Position fliegen.
#
# WICHTIG: Fuer Treffer-Timing (Schaden/Blut/SFX) soll der Aufrufer NICHT
# auf das Ende dieser Funktion warten, sondern auf das Signal
# `attack_impact`, das genau beim ersten Kontakt (vor dem Rammstoss)
# gefeuert wird. Das Ende dieser Funktion markiert nur, wann die Karte
# wieder komplett an ihrer Ausgangsposition ist.
func play_attack_animation(target_global_pos: Vector3, hold_at_impact: bool = false) -> void:
	_attack_impact_release_requested = not hold_at_impact
	var start_pos: Vector3 = global_position
	var start_rot: Vector3 = rotation_degrees
	var start_scale: Vector3 = scale

	var direction: Vector3 = target_global_pos - start_pos
	# Der Footprint ist in Tisch-/Parent-Einheiten angegeben. Dadurch bleibt
	# der Kontakt auch korrekt, wenn der komplette Spieltisch skaliert ist.
	var contact_direction := direction
	var parent_3d := get_parent() as Node3D
	if parent_3d != null:
		contact_direction = parent_3d.to_local(target_global_pos) - position
	var contact_ratio := _get_attack_contact_ratio(contact_direction)
	var contact_pos: Vector3 = start_pos + direction * contact_ratio

	var out_tween: Tween = create_tween()
	out_tween.tween_property(self, "global_position", contact_pos, attack_out_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	await out_tween.finished

	if not is_instance_valid(self):
		return

	# Der Treffer wird beim ersten Beruehren ausgeloest. Die Karte ist hier
	# noch nicht in das Ziel hineingefahren und hat ihre Ausgangsgroesse.
	attack_impact.emit()

	# Online wartet die Praesentation hier auf das autoritative Trefferpaket.
	# So koennen Netzwerk-Latenzen Blut/SFX nicht in den Rueckflug verschieben.
	while hold_at_impact and not _attack_impact_release_requested:
		await get_tree().process_frame
		if not is_instance_valid(self):
			return

	# Kurzer "Rammstoss": minimal weiter nach vorne und sofort wieder
	# ein Stueck zurueck, fuer ein spuerbares Einschlag-Gefuehl statt
	# nur eines glatten Hin- und Herfliegens.
	var hit_ratio := minf(contact_ratio + 0.08, 1.0)
	var hit_pos: Vector3 = start_pos + direction * hit_ratio
	var hit_tween: Tween = create_tween().set_parallel(true)
	hit_tween.tween_property(self, "global_position", hit_pos, attack_hit_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	hit_tween.tween_property(self, "scale", start_scale * attack_overshoot_scale, attack_hit_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await hit_tween.finished

	if not is_instance_valid(self):
		return

	var return_tween: Tween = create_tween().set_parallel(true)
	return_tween.tween_property(self, "global_position", start_pos, attack_return_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	return_tween.tween_property(self, "rotation_degrees", start_rot, attack_return_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	return_tween.tween_property(self, "scale", start_scale, attack_return_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	await return_tween.finished

	if is_instance_valid(self):
		attack_finished.emit()


func release_attack_after_impact() -> void:
	_attack_impact_release_requested = true


# Berechnet entlang der XZ-Angriffsrichtung den ersten Kontakt zweier
# gleich grosser, achsenparalleler Karten-Footprints. attack_card_footprint
# entspricht dabei bereits der Summe der beiden Half-Extents (Minkowski-AABB).
func _get_attack_contact_ratio(direction: Vector3) -> float:
	var remaining_ratio := INF
	var footprint_x := maxf(attack_card_footprint.x, 0.001)
	var footprint_z := maxf(attack_card_footprint.y, 0.001)

	if absf(direction.x) > 0.0001:
		remaining_ratio = minf(remaining_ratio, footprint_x / absf(direction.x))
	if absf(direction.z) > 0.0001:
		remaining_ratio = minf(remaining_ratio, footprint_z / absf(direction.z))

	# Gleiche XZ-Position: Die Karten beruehren/ueberlappen sich bereits.
	if is_inf(remaining_ratio):
		return 0.0

	return clampf(1.0 - remaining_ratio, 0.0, 1.0)


func _wrap_text(text: String, max_chars_per_line: int = 45) -> String:
	var words := text.split(" ")
	var result := ""
	var line := ""

	for word in words:
		if line.length() + word.length() + 1 > max_chars_per_line:
			result += line + "\n"
			line = word
		else:
			if line.is_empty():
				line = word
			else:
				line += " " + word

	result += line
	return result
	
	
func set_disabled(value: bool) -> void:
	_disabled = value

	var text_color := Color(0.45, 0.45, 0.45) if value else Color.WHITE

	name_label.modulate = text_color
	attack_label.modulate = text_color
	defense_label.modulate = text_color
	description_label.modulate = text_color
	effects_label.modulate = text_color
	rarity_label.modulate = text_color

	# Karte bleibt anklickbar für Detailansicht.
func _update_card_frame() -> void:
	if _card_material == null:
		return

	_frame_columns = max(_frame_columns, 1)
	_frame_rows = max(_frame_rows, 1)
	_frame_count = max(_frame_count, 1)

	var col := _current_frame % _frame_columns
	var row := int(_current_frame / _frame_columns)

	_card_material.uv1_scale = Vector3(
		1.0 / float(_frame_columns),
		1.0 / float(_frame_rows),
		1.0
	)

	_card_material.uv1_offset = Vector3(
		float(col) / float(_frame_columns),
		float(row) / float(_frame_rows),
		0.0
	)
	_update_holo_artwork_uv()

func clear_selected_immediate() -> void:
	if _select_tween != null:
		_select_tween.kill()
		_select_tween = null

	_is_selected = false

	if _has_select_base_position:
		position = _select_base_position

	_restore_glow_rarity_color()

func _connect_effect_icon_areas() -> void:
	var icon_areas: Array[Area3D] = [
		effect_icon_area_1,
		effect_icon_area_2,
	]

	for icon_area in icon_areas:
		if icon_area == null:
			continue
		icon_area.add_to_group("effect_icon_hover_area")
		icon_area.set_meta("keep_input_ray_pickable_disabled", true)
		# Effect icons must not participate in Godot's ray picking: otherwise
		# their small hover hitboxes become the front-most 3D collider and steal
		# clicks/drags from cards, kiosk screens and shop machines behind them.
		# Effect details now use the card's full Area3D hover instead.
		icon_area.input_ray_pickable = false
		icon_area.collision_layer = 0
		icon_area.collision_mask = 0


func _set_effect_icon_areas_enabled(enabled: bool) -> void:
	_set_effect_icon_area_enabled(effect_icon_area_1, enabled)
	_set_effect_icon_area_enabled(effect_icon_area_2, enabled)


func _set_effect_icon_area_enabled(icon_area: Area3D, enabled: bool) -> void:
	if icon_area == null:
		return
	icon_area.monitoring = false
	icon_area.monitorable = false
	icon_area.input_ray_pickable = false
	icon_area.collision_layer = 0
	icon_area.collision_mask = 0
	icon_area.visible = enabled


func _connect_card_hover_area() -> void:
	if area == null:
		return
	if not area.mouse_entered.is_connected(_on_card_area_mouse_entered):
		area.mouse_entered.connect(_on_card_area_mouse_entered)
	if not area.mouse_exited.is_connected(_on_card_area_mouse_exited):
		area.mouse_exited.connect(_on_card_area_mouse_exited)


func _on_card_area_mouse_entered() -> void:
	if is_stack_decoration or _is_card_hovered:
		return
	_is_card_hovered = true
	card_hovered.emit(self)


func _on_card_area_mouse_exited() -> void:
	if not _is_card_hovered:
		return
	_is_card_hovered = false
	card_unhovered.emit(self)


func _apply_effect_icons() -> void:
	var icon_slots: Array[Sprite3D] = [
		effect_icon_1,
		effect_icon_2,
	]
	var icon_areas: Array[Area3D] = [
		effect_icon_area_1,
		effect_icon_area_2,
	]

	_set_effect_icon_areas_enabled(false)

	for slot in icon_slots:
		if slot == null:
			continue
		slot.visible = false
		slot.texture = null

	var active_effects := CardData.get_active_effects(card_data)

	for i in range(min(active_effects.size(), icon_slots.size())):
		var slot := icon_slots[i]
		if slot == null:
			continue

		var icon_path := _get_effect_icon_path(active_effects[i])
		_apply_icon_texture(slot, icon_path)
		_set_effect_icon_area_enabled(icon_areas[i], slot.visible)


func _get_effect_icon_path(effect: Dictionary) -> String:
	if str(effect.get("type", "")).strip_edges().is_empty():
		return ""
	return EffectPresentation.get_icon_path(effect)


func _apply_icon_texture(slot: Sprite3D, texture_path: String) -> void:
	if texture_path == "":
		slot.visible = false
		slot.texture = null
		slot.material_override = null
		return

	var texture := load(texture_path) as Texture2D

	if texture == null:
		texture = load(EFFECT_PLACEHOLDER) as Texture2D

	if texture == null:
		slot.visible = false
		return

	var rarity := str(card_data.get("rarity", "common")).to_lower()
	var rarity_color := _get_rarity_color(rarity)

	var mat := ShaderMaterial.new()
	mat.shader = EFFECT_ICON_HOLO_SHADER
	mat.set_shader_parameter("icon_texture", texture)
	mat.set_shader_parameter("rarity_color", rarity_color)
	mat.set_shader_parameter("effect_opacity", 1.0)

	slot.texture = texture
	slot.material_override = mat
	slot.visible = true
	slot.modulate = Color.WHITE
	slot.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
