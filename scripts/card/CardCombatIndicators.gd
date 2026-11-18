extends Node3D

## Presentation only: the owning card supplies authoritative battle state.
const BADGE_SHADER := preload("res://assets/shader/card_status_badge.gdshader")
const CONSUME_DURATION := 0.32
const STATUS_TYPES := ["eternal_suffering", "poison", "stun", "curse"]
const STATUS_COLORS := {
	"poison": Color("65f276"),
	"stun": Color("ffd35a"),
	"curse": Color("d48aff"),
	"eternal_suffering": Color("ff354f"),
}

var _seals: Array[Sprite3D] = []
var _seal_scales: Array[Vector3] = []
var _seal_active: Array[bool] = []
var _seal_tweens: Dictionary = {}
var _badges: Dictionary = {}
var _badge_active: Dictionary = {}
var _badge_tweens: Dictionary = {}


func configure(seals: Array[Sprite3D]) -> void:
	_seals = seals
	for seal in seals:
		_seal_scales.append(seal.scale)
		_seal_active.append(true)


func reset() -> void:
	for animation: Tween in _seal_tweens.values() + _badge_tweens.values():
		if animation.is_valid():
			animation.kill()
	_seal_tweens.clear()
	_badge_tweens.clear()
	for i in range(_seals.size()):
		_seals[i].scale = _seal_scales[i]
		_seal_active[i] = true
	for badge: Node3D in _badges.values():
		badge.hide()
	_badge_active.clear()


func retire() -> void:
	for i in range(_seals.size()):
		if not _seal_active[i]:
			_seals[i].hide()
	reset()
	hide()


func sync_seals(effects: Array[Dictionary], availability: Dictionary, animate: bool) -> void:
	for i in range(_seals.size()):
		var effect_type := str(effects[i].get("type", "")) if i < effects.size() else ""
		var active := not effect_type.is_empty() and bool(availability.get(effect_type, true))
		var seal := _seals[i]
		if _seal_active[i] and not active:
			if animate and seal.visible:
				var animation := create_tween().set_parallel(true)
				_seal_tweens[i] = animation
				animation.tween_property(seal, "scale", _seal_scales[i] * 0.08, CONSUME_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
				animation.tween_method(_set_seal_opacity.bind(seal.material_override), 1.0, 0.0, CONSUME_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
				animation.chain().tween_callback(seal.hide)
			else:
				seal.hide()
		elif active:
			if not _seal_active[i]:
				var animation := _seal_tweens.get(i) as Tween
				if animation != null and animation.is_valid():
					animation.kill()
				seal.scale = _seal_scales[i]
				_set_seal_opacity(1.0, seal.material_override as ShaderMaterial)
			seal.visible = seal.texture != null
		_seal_active[i] = active


func sync_statuses(statuses: Dictionary, animate: bool) -> void:
	var slot := 0
	for effect_type: String in STATUS_TYPES:
		var amount := int(statuses.get(effect_type, 0))
		var active := amount > 0
		var was_active := bool(_badge_active.get(effect_type, false))
		if active:
			if not _badges.has(effect_type):
				_badges[effect_type] = _create_badge(effect_type)
			var badge := _badges[effect_type] as Node3D
			badge.position = Vector3(0.315 - slot * 0.17, 0.405, 0.035)
			var count := badge.get_node("Count") as Label3D
			count.text = ("-%d" if effect_type == "curse" else "%d") % amount
			# Stun always consumes the next selected attack; the icon alone is enough.
			count.visible = effect_type != "stun"
			if not was_active:
				_kill_badge_tween(effect_type)
				badge.show()
				_set_badge_opacity(1.0, badge)
				badge.scale = Vector3.ONE * (0.65 if animate else 1.0)
				if animate:
					var animation := create_tween()
					_badge_tweens[effect_type] = animation
					animation.tween_property(badge, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			slot += 1
		elif was_active:
			_kill_badge_tween(effect_type)
			var badge := _badges[effect_type] as Node3D
			if animate:
				var animation := create_tween().set_parallel(true)
				_badge_tweens[effect_type] = animation
				animation.tween_property(badge, "scale", Vector3.ONE * 0.1, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
				animation.tween_method(_set_badge_opacity.bind(badge), 1.0, 0.0, 0.18)
				animation.chain().tween_callback(badge.hide)
			else:
				badge.hide()
		_badge_active[effect_type] = active


func _create_badge(effect_type: String) -> Node3D:
	var badge := Node3D.new()
	badge.name = effect_type.to_pascal_case()
	add_child(badge)
	var icon := MeshInstance3D.new()
	icon.name = "Icon"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.155, 0.155)
	icon.mesh = quad
	icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = BADGE_SHADER
	# Draw after card art and its transparent shader passes, even where raised
	# artwork/dioramas extend in front of the physical status plane.
	material.render_priority = 80
	material.set_shader_parameter("icon_texture", EffectPresentation.get_icon({"type": effect_type}))
	material.set_shader_parameter("accent_color", STATUS_COLORS[effect_type])
	icon.material_override = material
	badge.add_child(icon)
	var count := Label3D.new()
	count.name = "Count"
	count.position = Vector3(0.049, -0.051, 0.006)
	count.pixel_size = 0.0015
	count.font_size = 28
	count.outline_size = 7
	count.modulate = Color.WHITE
	count.no_depth_test = true
	count.render_priority = 81
	badge.add_child(count)
	return badge


func _kill_badge_tween(effect_type: String) -> void:
	var animation := _badge_tweens.get(effect_type) as Tween
	if animation != null and animation.is_valid():
		animation.kill()
	_badge_tweens.erase(effect_type)


func _set_badge_opacity(value: float, badge: Node3D) -> void:
	var icon := badge.get_node("Icon") as MeshInstance3D
	(icon.material_override as ShaderMaterial).set_shader_parameter("opacity", value)
	(badge.get_node("Count") as Label3D).modulate.a = value


func _set_seal_opacity(value: float, material: ShaderMaterial) -> void:
	material.set_shader_parameter("effect_opacity", value)
