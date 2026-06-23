extends Node3D
class_name Card3D

# --- Kleine typisierte Helferklasse fuer die Rarity-Presets ---------------
#
# Bewusst KEINE Dictionary[String, float] verwendet, da verschachtelte
# Dictionary-Literale in GDScript zu Variant-Werten fuehren, sobald sie
# wieder ausgelesen werden (Dictionary.get() liefert immer Variant).
# Eine kleine RefCounted-Klasse mit typisierten Feldern vermeidet das
# komplett und gibt zur Editierzeit Typ-Sicherheit.
class RarityPreset:
	var intensity: float
	var scroll_speed: float
	var band_density: float
	var jaggedness: float
	var pulse_strength: float
	var pulse_speed: float
	var base_glow: float

	func _init(
		p_intensity: float,
		p_scroll_speed: float,
		p_band_density: float,
		p_jaggedness: float,
		p_pulse_strength: float,
		p_pulse_speed: float,
		p_base_glow: float
	) -> void:
		intensity = p_intensity
		scroll_speed = p_scroll_speed
		band_density = p_band_density
		jaggedness = p_jaggedness
		pulse_strength = p_pulse_strength
		pulse_speed = p_pulse_speed
		base_glow = p_base_glow


@onready var card_model: Node3D = $card
@onready var card_outline: Node3D = $cardOutline
@onready var card_image: MeshInstance3D = $CardImage
@onready var rarity_glow_plane: MeshInstance3D = $RarityGlowPlane
@onready var name_label: Label3D = $NameLabel
@onready var attack_label: Label3D = $AttackLabel
@onready var defense_label: Label3D = $DefenseLabel
@onready var description_label: Label3D = $DescriptionLabel
@onready var rarity_label: Label3D = $RarityLabel
@onready var area: Area3D = $Area3D

var card_data: Dictionary = {}

# Wenn true, ist diese Karteninstanz nur eine rein optische
# Stapel-Dekoration (z.B. im sichtbaren Nachzieh-Stapel) ohne echte
# Spieldaten. setup() wird dafuer nie aufgerufen, und teure/unnoetige
# Laufzeit-Effekte (Shine-Sweep, Klick-Area) werden deaktiviert.
# Muss VOR dem Hinzufuegen zum SceneTree (also vor _ready()) gesetzt
# werden, z.B. direkt nach instantiate().
var is_stack_decoration: bool = false

# --- Kampf/HP-System -----------------------------------------------------
#
# defense aus card_data ist die MAXIMALE Lebenspunkte-Anzahl einer Karte.
# current_hp sinkt mit jedem Duell, in dem die Karte angegriffen wird,
# und bleibt dabei laufzeit-spezifisch fuer GENAU DIESE Karteninstanz
# (zwei Karten mit derselben card_id auf dem Tisch haben unabhaengige
# HP-Werte).
var max_hp: int = 0
var current_hp: int = 0
var attack_value: int = 0

signal died(card: Card3D)

@export_group("Auswahl-Highlight")
@export var select_highlight_color: Color = Color(1.0, 0.92, 0.3, 1.0)
@export var select_lift: float = 0.08
@export var select_duration: float = 0.15

var _is_selected: bool = false
var _select_base_position: Vector3 = Vector3.ZERO

# Wie "heftig" sich der Rarity-Shader pro Stufe verhaelt.
# common bleibt bewusst praktisch unbewegt/ruhig, exotic ist maximal
# chaotisch und hell.
static var _rarity_presets: Dictionary[String, RarityPreset] = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _rarity_glow_material: ShaderMaterial = null


static func _static_init() -> void:
	_rarity_presets = {
		"common": RarityPreset.new(0.0, 0.0, 2.0, 0.0, 0.0, 0.0, 0.18),
		"uncommon": RarityPreset.new(0.5, 0.5, 3.0, 0.15, 0.15, 1.2, 0.22),
		"rare": RarityPreset.new(0.9, 0.9, 4.0, 0.3, 0.2, 1.6, 0.28),
		"epic": RarityPreset.new(1.3, 1.3, 5.0, 0.45, 0.3, 2.0, 0.32),
		"legendary": RarityPreset.new(1.7, 1.7, 6.0, 0.55, 0.35, 2.4, 0.38),
		"mythic": RarityPreset.new(2.1, 2.1, 7.0, 0.7, 0.4, 2.8, 0.42),
		"exotic": RarityPreset.new(2.6, 2.8, 8.0, 0.9, 0.5, 3.4, 0.5),
	}


func _ready() -> void:
	# FIX: _rng.randomize() allein basiert auf der Systemzeit. Wenn viele
	# Karten im selben Frame instanziiert werden (z.B. 40 Karten beim
	# Pack-Opening oder 10 Stapel-Karten beim Matchstart), kann die
	# Zeitaufloesung nicht granular genug sein, um pro Karte einen
	# unterschiedlichen Seed zu erzeugen — alle Karten shinen dann exakt
	# synchron. get_instance_id() ist garantiert pro Node-Instanz
	# unterschiedlich und wird zusaetzlich eingemischt, um das zu
	# verhindern.
	_rng.seed = hash(Time.get_ticks_usec() ^ int(get_instance_id()))

	_ensure_materials_resolved()

	if is_stack_decoration:
		# Reine Deko-Ruecken: kein Shine-Sweep, kein Rarity-Glow, keine
		# Klick-Area noetig — und sie soll auch nicht versehentlich
		# klickbar/hoverbar sein.
		if area != null:
			area.monitoring = false
			area.monitorable = false
		rarity_glow_plane.visible = false
		return



# FIX: setup() kann je nach Aufrufreihenfolge des Aufrufers (z.B. direkt
# nach instantiate()+add_child()) VOR _ready() laufen. Da die
# @onready-Referenzen rarity_glow_plane/shine_overlay erst zum
# _ready()-Zeitpunkt sicher gueltig sind, wurde _rarity_glow_material in
# diesem Fall nie gesetzt — _apply_rarity_style() brach dann stillschweigend
# ab und die Plane behielt ihre Default-Werte aus der .tscn (das graue
# "common"-Aussehen, unabhaengig von der tatsaechlichen Rarity).
# _ensure_materials_resolved() ist idempotent und wird jetzt an JEDEM
# Einstiegspunkt aufgerufen, der die Materialien braucht, unabhaengig
# davon ob _ready() schon gelaufen ist.
func _ensure_materials_resolved() -> void:
	if _rarity_glow_material == null and rarity_glow_plane != null:
		_rarity_glow_material = rarity_glow_plane.get_surface_override_material(0) as ShaderMaterial


func setup(data: Dictionary) -> void:
	card_data = data

	var card_name: String = str(data.get("name", "Unknown"))
	var attack: int = int(data.get("attack", 0))
	var defense: int = int(data.get("defense", 0))
	var rarity: String = str(data.get("rarity", "common")).to_lower()
	var description: String = str(data.get("description", ""))
	var image_path: String = str(data.get("image", ""))

	attack_value = attack
	max_hp = defense
	current_hp = defense

	name_label.text = card_name
	attack_label.text = str(attack)
	_update_hp_label()
	description_label.text = _shorten_description(description)
	rarity_label.text = rarity.to_upper()

	_ensure_materials_resolved()
	_apply_rarity_style(rarity)
	_apply_card_image(image_path)


func _update_hp_label() -> void:
	defense_label.text = str(current_hp)


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


func _apply_card_image(image_path: String) -> void:
	if image_path == "":
		return

	var texture: Texture2D = load(image_path) as Texture2D
	if texture == null:
		push_warning("Kartenbild nicht gefunden: " + image_path)
		return

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.roughness = 0.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	card_image.material_override = mat


# Faerbt zwei unabhaengige Dinge in der Rarity-Farbe:
# 1. cardOutline.glb bekommt ein einfaches, STATISCHES StandardMaterial3D
#    in der Rarity-Farbe (kein Glow/keine Animation) — das ist die
#    "klassische" eingefaerbte Kartenkante.
# 2. Die im Editor platzierte RarityGlowPlane bekommt den vollen
#    animierten Shader-Effekt (wandernde Risse/Energie, Pulsieren).
# Beide laufen unabhaengig voneinander.
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
	_rarity_glow_material.set_shader_parameter("emission_boost", 6.0)


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
	_is_selected = selected

	if selected:
		_select_base_position = position
		var tween: Tween = create_tween().set_parallel(true)
		tween.tween_property(self, "position", _select_base_position + Vector3(0, select_lift, 0), select_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_set_glow_override_color(select_highlight_color)
	else:
		var tween: Tween = create_tween().set_parallel(true)
		tween.tween_property(self, "position", _select_base_position, select_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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

	_apply_static_outline_color(card_outline, color)

	if _rarity_glow_material == null:
		return
	_rarity_glow_material.set_shader_parameter("rarity_color", color)
	_rarity_glow_material.set_shader_parameter("emission_boost", 6.0)


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

	var return_tween: Tween = create_tween().set_parallel(true)
	return_tween.tween_property(self, "global_position", start_pos, attack_return_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	return_tween.tween_property(self, "rotation_degrees", start_rot, attack_return_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	return_tween.tween_property(self, "scale", start_scale, attack_return_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	await return_tween.finished
