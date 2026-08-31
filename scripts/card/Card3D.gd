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

# HP-Werte).
var max_hp: int = 0
var current_hp: int = 0
var attack_value: int = 0
var _first_hit_shield_available: bool = false
var _last_stand_available: bool = false
var _grave_return_available: bool = false
var _skip_next_attack: bool = false
var _disabled := false

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

var _is_selected: bool = false
var _select_base_position: Vector3 = Vector3.ZERO
var _select_tween: Tween = null
var _has_select_base_position := false
var _is_card_hovered := false
const EFFECT_ICON_PATH := "res://assets/effects/"
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

func _process(delta: float) -> void:
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

func _ensure_materials_resolved() -> void:
	if _rarity_glow_material == null and rarity_mesh != null:
		var shared_rarity_mat: ShaderMaterial = rarity_mesh.get_surface_override_material(0) as ShaderMaterial
		
		if shared_rarity_mat != null:
			_rarity_glow_material = shared_rarity_mat.duplicate(true) as ShaderMaterial
			rarity_mesh.set_surface_override_material(0, _rarity_glow_material)


func setup(data: Dictionary) -> void:
	card_data = data

	var card_name: String = str(data.get("name", "Unknown"))
	var attack: int = int(data.get("attack", 0))
	var defense: int = int(data.get("defense", 0))
	var rarity: String = str(data.get("rarity", "common")).to_lower()
	var description: String = str(data.get("description", ""))
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

	name_label.text = card_name
	attack_label.text = str(attack)
	_update_hp_label()
	description_label.play(_wrap_text(description, 45))
	effects_label.visible = false
	_apply_effect_icons()
	rarity_label.text = rarity.to_upper()

	_ensure_materials_resolved()
	_apply_rarity_style(rarity)
	_apply_card_image(image_path)


func _update_hp_label() -> void:
	defense_label.text = str(current_hp)


func _build_effects_summary() -> String:
	var effect_names: Array[String] = []
	for effect in CardData.get_active_effects(card_data):
		var label := _format_effect_label(effect)
		if label != "":
			effect_names.append(label)
	if effect_names.is_empty():
		return "Effects: -"
	return "Effects: " + " • ".join(effect_names)


func _format_effect_label(effect: Dictionary) -> String:
	var label := str(effect.get("name", effect.get("type", ""))).replace("_", " ").capitalize()
	if effect.has("percent"):
		label += " %d%%" % int(round(float(effect.get("percent", 0.0)) * 100.0))
	elif effect.has("value"):
		var value := float(effect.get("value", 0.0))
		if value > 0.0 and value <= 1.0:
			label += " %d%%" % int(round(value * 100.0))
		else:
			label += " +%d" % int(round(value))
	elif effect.has("damage") and effect.has("turns"):
		label += " %d/%dT" % [int(effect.get("damage", 0)), int(effect.get("turns", 0))]
	return label


func heal(amount: int, allow_overheal: bool = false) -> void:
	if amount <= 0 or is_dead():
		return

	if allow_overheal:
		current_hp += amount
	else:
		current_hp = min(current_hp + amount, max_hp)

	_update_hp_label()


func consume_first_hit_shield() -> bool:
	if not _first_hit_shield_available:
		return false
	_first_hit_shield_available = false
	return true


func try_survive_death() -> bool:
	if has_meta("last_survival_effect"):
		remove_meta("last_survival_effect")

	if _last_stand_available:
		_last_stand_available = false
		current_hp = 1
		_update_hp_label()
		set_meta("last_survival_effect", "last_stand")
		return true
	if _grave_return_available:
		_grave_return_available = false
		current_hp = int(max(round(float(max_hp) * 0.5), 1))
		_update_hp_label()
		set_meta("last_survival_effect", "grave_return")
		return true
	return false


func apply_curse(value: int) -> void:
	attack_value = int(max(attack_value - value, 0))
	attack_label.text = str(attack_value)


func stun_next_attack() -> void:
	_skip_next_attack = true


func consume_stun() -> bool:
	if not _skip_next_attack:
		return false
	_skip_next_attack = false
	return true


# Fuegt dieser Karte Schaden zu und gibt true zurueck, wenn die Karte
# dadurch stirbt (current_hp <= 0). HP wird nie unter 0 angezeigt.
func take_damage(amount: int) -> bool:
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
	return {
		"card_data": card_data.duplicate(true),
		"max_hp": max_hp,
		"current_hp": current_hp,
		"attack_value": attack_value,
		"first_hit_shield_available": _first_hit_shield_available,
		"last_stand_available": _last_stand_available,
		"grave_return_available": _grave_return_available,
		"skip_next_attack": _skip_next_attack,
		"poison_damage": int(get_meta("poison_damage", 0)),
		"poison_turns": int(get_meta("poison_turns", 0)),
	}


## Restores a snapshot created by get_network_state(). Calling setup first
## rebuilds the card's visual presentation; the mutable combat values then
## replace setup's defaults.
func apply_network_state(state: Dictionary) -> void:
	var data := state.get("card_data", {}) as Dictionary
	setup(data.duplicate(true))

	max_hp = maxi(int(state.get("max_hp", max_hp)), 1)
	current_hp = clampi(int(state.get("current_hp", current_hp)), 0, max_hp)
	attack_value = maxi(int(state.get("attack_value", attack_value)), 0)
	_first_hit_shield_available = bool(state.get("first_hit_shield_available", _first_hit_shield_available))
	_last_stand_available = bool(state.get("last_stand_available", _last_stand_available))
	_grave_return_available = bool(state.get("grave_return_available", _grave_return_available))
	_skip_next_attack = bool(state.get("skip_next_attack", _skip_next_attack))

	attack_label.text = str(attack_value)
	_update_hp_label()

	var poison_turns := maxi(int(state.get("poison_turns", 0)), 0)
	if poison_turns > 0:
		set_meta("poison_turns", poison_turns)
		set_meta("poison_damage", maxi(int(state.get("poison_damage", 0)), 0))
	else:
		if has_meta("poison_turns"):
			remove_meta("poison_turns")
		if has_meta("poison_damage"):
			remove_meta("poison_damage")


func _apply_card_image(image_path: String) -> void:
	if image_path == "":
		return

	var texture: Texture2D = load(image_path) as Texture2D
	if texture == null:
		push_warning("Kartenbild nicht gefunden: " + image_path)
		return

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	_card_material = mat
	card_image.material_override = _card_material

	if _animated_image:
		_update_card_frame()
	else:
		_card_material.uv1_scale = Vector3.ONE
		_card_material.uv1_offset = Vector3.ZERO


func _apply_rarity_style(rarity: String) -> void:
	var color: Color = _get_rarity_color(rarity)
	var preset: RarityPreset = _rarity_presets.get(rarity, _rarity_presets["common"]) as RarityPreset

	rarity_label.modulate = color

	_apply_static_outline_color(card_outline, color)

	if _rarity_glow_material == null:
		return

	_rarity_glow_material.set_shader_parameter("rarity_color", color)
	_rarity_glow_material.set_shader_parameter("intensity", preset.intensity)
	_rarity_glow_material.set_shader_parameter("scroll_speed", preset.scroll_speed)
	_rarity_glow_material.set_shader_parameter("band_density", preset.band_density)
	_rarity_glow_material.set_shader_parameter("jaggedness", preset.jaggedness)
	_rarity_glow_material.set_shader_parameter("pulse_strength", preset.pulse_strength)
	_rarity_glow_material.set_shader_parameter("pulse_speed", preset.pulse_speed)
	_rarity_glow_material.set_shader_parameter("base_glow", preset.base_glow)
	_rarity_glow_material.set_shader_parameter("emission_boost", preset.emission_boost)

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

	_apply_static_outline_color(card_outline, color)

	if _rarity_glow_material == null:
		return

	_rarity_glow_material.set_shader_parameter("rarity_color", color)
	_rarity_glow_material.set_shader_parameter("emission_boost", preset.emission_boost)


# --- Attack-Animation -----------------------------------------------------

@export_group("Attack-Animation")
@export var attack_lunge_ratio: float = 0.7
@export var attack_out_duration: float = 0.18
@export var attack_hit_duration: float = 0.08
@export var attack_return_duration: float = 0.22
@export var attack_overshoot_scale: float = 1.12

# Laesst die Karte in Richtung target_global_pos vorfliegen ("ramming"),
# kurz dort verharren/leicht hineinstossen, und dann zurueck an ihre
# urspruengliche Position fliegen. Wartet auf das komplette Ende der
# Animation, bevor zurueckgekehrt wird — der Aufrufer kann also einfach
# `await card.play_attack_animation(target.global_position)` nutzen, um
# den Schaden erst NACH der Animation anzuwenden.
#
# WICHTIG: Fuer Treffer-Timing (Schaden/Blut/SFX) soll der Aufrufer NICHT
# auf das Ende dieser Funktion warten, sondern auf das Signal
# `attack_impact`, das genau am Scheitelpunkt (nach dem Rammstoss, vor
# dem Rueckflug) gefeuert wird. Das Ende dieser Funktion markiert nur,
# wann die Karte wieder komplett an ihrer Ausgangsposition ist.
func play_attack_animation(target_global_pos: Vector3) -> void:
	var start_pos: Vector3 = global_position
	var start_rot: Vector3 = rotation_degrees
	var start_scale: Vector3 = scale

	var direction: Vector3 = target_global_pos - start_pos
	var lunge_pos: Vector3 = start_pos + direction * attack_lunge_ratio

	var out_tween: Tween = create_tween().set_parallel(true)
	out_tween.tween_property(self, "global_position", lunge_pos, attack_out_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	out_tween.tween_property(self, "scale", start_scale * attack_overshoot_scale, attack_out_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await out_tween.finished

	if not is_instance_valid(self):
		return

	# Kurzer "Rammstoss": minimal weiter nach vorne und sofort wieder
	# ein Stueck zurueck, fuer ein spuerbares Einschlag-Gefuehl statt
	# nur eines glatten Hin- und Herfliegens.
	var hit_pos: Vector3 = start_pos + direction * (attack_lunge_ratio + 0.08)
	var hit_tween: Tween = create_tween()
	hit_tween.tween_property(self, "global_position", hit_pos, attack_hit_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	await hit_tween.finished

	if not is_instance_valid(self):
		return

	# --- Scheitelpunkt der Animation: HIER soll der Treffer "passieren" ---
	# Aufrufer koennen auf dieses Signal warten, um Schaden, Blut-Effekte
	# und Treffer-SFX exakt in diesem Moment auszuloesen, statt erst nach
	# dem kompletten Rueckflug.
	attack_impact.emit()

	var return_tween: Tween = create_tween().set_parallel(true)
	return_tween.tween_property(self, "global_position", start_pos, attack_return_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	return_tween.tween_property(self, "rotation_degrees", start_rot, attack_return_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	return_tween.tween_property(self, "scale", start_scale, attack_return_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	await return_tween.finished

	if is_instance_valid(self):
		attack_finished.emit()


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
	var effect_type := str(effect.get("type", "")).strip_edges().to_lower()

	if effect_type == "":
		return ""

	var file_name := effect_type

	if effect_type == "armor":
		var value := float(effect.get("value", 0.0))

		if is_equal_approx(value, 0.25):
			file_name = "armor_25"
		elif is_equal_approx(value, 0.5):
			file_name = "armor_50"
		elif is_equal_approx(value, 0.75):
			file_name = "armor_75"

	var path := EFFECT_ICON_PATH + file_name + ".png"

	if ResourceLoader.exists(path):
		return path

	return EFFECT_PLACEHOLDER


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

	slot.texture = texture
	slot.material_override = mat
	slot.visible = true
	slot.modulate = Color.WHITE
	slot.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
