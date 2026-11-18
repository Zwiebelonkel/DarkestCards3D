extends Node3D
class_name BlackMarketBoard
## A physical shop surface using Main's shared camera and saved daily stock.

signal card_purchased(result: Dictionary)

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
const FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")
const BUY_SOUND := preload("res://assets/sounds/SFX/button.mp3")
const BOARD_SIZE := Vector2(6.0, 3.4)
const BUTTON_SIZE := Vector2(1.22, 0.36)
const ERRORS := {
	"locked": "Der Zugang zum Black Market fehlt.",
	"stale": "Neue Tagesangebote sind eingetroffen.",
	"sold": "Dieses Angebot ist ausverkauft.",
	"invalid_offer": "Dieses Angebot ist nicht mehr verfügbar.",
	"insufficient_funds": "Nicht genug Soul Coins.",
	"busy": "Bitte versuche es gleich erneut.",
	"save_failed": "Kauf nicht gespeichert. Bitte erneut versuchen.",
}

@export var camera: Camera3D
@export_range(0, 3, 1) var view_side := 0

var focus_area: Area3D
var offer_areas: Array[Area3D] = []
var offers_snapshot: Dictionary = {}
var interaction_enabled := false
var _cards: Array[Card3D] = []
var _prices: Array[Label3D] = []
var _buttons: Array[Label3D] = []
var _button_materials: Array[StandardMaterial3D] = []
var _title: Label3D
var _subtitle: Label3D
var _status: Label3D
var _content: Node3D
var _audio: AudioStreamPlayer3D
var _refresh_pending := true
var _clock_elapsed := 0.0
var _message := ""
var _message_seconds := 0.0
var _hovered := -1


func _ready() -> void:
	focus_area = _make_area("BoardFocusArea", Vector3(0, 0, 0.10), BOARD_SIZE)
	focus_area.set_meta("focus_distance", 4.8)
	_title = _label("TAGESANGEBOTE", Vector3(0, 1.36, 0.14), 42, 0.005)
	_subtitle = _label("", Vector3(0, 1.00, 0.14), 22, 0.0048)
	_status = _label("", Vector3(0, -1.51, 0.14), 22, 0.0045)
	_content = Node3D.new()
	_content.name = "Offers"
	add_child(_content)
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = BUY_SOUND
	_audio.bus = &"SFX"
	_audio.unit_size = 5.0
	_audio.volume_db = -9.0
	add_child(_audio)
	CollectionManager.collection_changed.connect(_queue_refresh)
	CardUpgradeManager.upgrades_changed.connect(_on_upgrades_changed)
	GameCurrency.coins_changed.connect(_on_coins_changed)
	GameCurrency.npc_rescue_changed.connect(refresh_offers)
	Localization.locale_changed.connect(_on_locale_changed)
	refresh_offers()
	set_interaction_enabled(false)


func _process(delta: float) -> void:
	_clock_elapsed += delta
	if _clock_elapsed >= 0.5:
		_clock_elapsed = 0.0
		if str(offers_snapshot.get("day", "")) != CollectionManager.get_black_market_day():
			_message = "Neue Tagesangebote sind eingetroffen."
			_message_seconds = 5.0
			_refresh_pending = true
		_refresh_labels()
	if _refresh_pending:
		refresh_offers()
	if _message_seconds > 0.0:
		_message_seconds = maxf(0.0, _message_seconds - delta)
		if _message_seconds == 0.0:
			_message = ""
			_refresh_labels()
	var pointed := _offer_at(get_viewport().get_mouse_position()) if _can_interact() else -1
	if pointed != _hovered:
		_hovered = pointed
		_refresh_labels()


func _unhandled_input(event: InputEvent) -> void:
	if not _can_interact() or not event is InputEventMouseButton:
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var index := _offer_at(event.position)
	if index < 0:
		return
	purchase_offer(index)
	get_viewport().set_input_as_handled()


func set_interaction_enabled(enabled: bool) -> void:
	if enabled and not interaction_enabled:
		_refresh_pending = true
	interaction_enabled = enabled
	for area: Area3D in [focus_area] + offer_areas:
		if is_instance_valid(area):
			area.input_ray_pickable = enabled
			area.set_meta("keep_input_ray_pickable_disabled", not enabled)
	if not enabled and _hovered != -1:
		_hovered = -1
		_refresh_labels()


func _can_interact() -> bool:
	return GameCurrency.is_npc_rescued("dealer") and interaction_enabled and not get_tree().paused and is_visible_in_tree() and is_instance_valid(camera) and camera.is_current()


func purchase_offer(index: int) -> Dictionary:
	var offers: Array = offers_snapshot.get("offers", [])
	if not _can_interact() or index < 0 or index >= offers.size():
		return {"ok": false, "reason": "busy"}
	var result: Dictionary = CollectionManager.purchase_black_market_offer(str(offers_snapshot["day"]), str(offers[index]["offer_id"]))
	_message = "Karte zur Sammlung hinzugefügt." if bool(result.get("ok", false)) else str(ERRORS.get(str(result.get("reason", "")), ERRORS["invalid_offer"]))
	_message_seconds = 5.0
	refresh_offers()
	if bool(result.get("ok", false)):
		_audio.play()
		card_purchased.emit(result)
	return result


func _queue_refresh(_ids: Array = []) -> void:
	_refresh_pending = true


func _on_coins_changed(_coins: float) -> void:
	_refresh_labels()


func _on_locale_changed() -> void:
	_refresh_labels()


func _on_upgrades_changed(_card_id: String) -> void:
	_refresh_pending = true


func refresh_offers() -> void:
	_refresh_pending = false
	var next: Dictionary = CollectionManager.get_black_market_offers()
	var old_ids: Array = []
	var new_ids: Array = []
	for entry: Dictionary in offers_snapshot.get("offers", []):
		old_ids.append(entry["card_id"])
	for entry: Dictionary in next.get("offers", []):
		new_ids.append(entry["card_id"])
	offers_snapshot = next
	if old_ids != new_ids:
		_rebuild_cards()
	else:
		for index in range(_cards.size()):
			_setup_preview(_cards[index], str(new_ids[index]))
	_refresh_labels()


func _rebuild_cards() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	for area in offer_areas:
		remove_child(area)
		area.queue_free()
	offer_areas.clear()
	_cards.clear()
	_prices.clear()
	_buttons.clear()
	_button_materials.clear()
	var offers: Array = offers_snapshot.get("offers", [])
	for index in range(offers.size()):
		var x := (float(index) - (offers.size() - 1) * 0.5) * 1.43
		var card := CARD_SCENE.instantiate() as Card3D
		_content.add_child(card)
		var card_id := str(offers[index]["card_id"])
		_setup_preview(card, card_id)
		card.position = Vector3(x, 0.06, 0.16)
		card.scale = Vector3.ONE * 1.12
		_cards.append(card)
		_prices.append(_label("", Vector3(x, -0.76, 0.15), 25, 0.0048, _content))
		var button_at := Vector3(x, -1.14, 0.14)
		var area := _make_area("BuyOffer%d" % index, button_at, BUTTON_SIZE)
		offer_areas.append(area)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(BUTTON_SIZE.x, BUTTON_SIZE.y, 0.035)
		mesh.mesh = box
		mesh.position = button_at
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color("59402a")
		mesh.material_override = material
		_content.add_child(mesh)
		_button_materials.append(material)
		_buttons.append(_label("", button_at + Vector3(0, 0, 0.03), 24, 0.0048, _content))
	set_interaction_enabled(interaction_enabled)


func _setup_preview(card: Card3D, card_id: String) -> void:
	card.setup(CardUpgradeManager.apply_upgrades(card_id, CardDatabase.get_card(card_id)))
	card.description_label.skip()
	_disable_card_input(card)


func _refresh_labels() -> void:
	if not is_instance_valid(_title) or not is_instance_valid(_content):
		return
	var rescued := GameCurrency.is_npc_rescued("dealer")
	_content.visible = rescued
	if not rescued:
		_title.text = Localization.text("GESCHLOSSEN")
		_subtitle.text = Localization.text("Befreie zuerst den Dealer.")
		_status.text = ""
		Localization.fit_text_3d(_title, 5.5, 0.33)
		Localization.fit_text_3d(_subtitle, 5.5, 0.22)
		return
	_title.text = Localization.text("TAGESANGEBOTE")
	Localization.fit_text_3d(_title, 5.5, 0.33)
	var now := Time.get_datetime_dict_from_system()
	var seconds := 86400 - (int(now["hour"]) * 3600 + int(now["minute"]) * 60 + int(now["second"]))
	_subtitle.text = Localization.format_text("Neue Angebote in %s", ["%02d:%02d:%02d" % [seconds / 3600, (seconds % 3600) / 60, seconds % 60]])
	_status.text = Localization.text(_message) if not _message.is_empty() else Localization.format_text("Guthaben: %s Soul Coins", [Localization.decimal(GameCurrency.coins)])
	Localization.fit_text_3d(_subtitle, 5.5, 0.22)
	Localization.fit_text_3d(_status, 5.5, 0.21)
	var offers: Array = offers_snapshot.get("offers", [])
	for index in range(mini(offers.size(), _buttons.size())):
		var offer: Dictionary = offers[index]
		var sold := bool(offer.get("sold", false))
		var price := float(offer["price_cents"]) / 100.0
		var affordable := GameCurrency.coins + 0.00001 >= price
		_prices[index].text = Localization.format_text("%s SC", [Localization.decimal(price)])
		_buttons[index].text = Localization.text("AUSVERKAUFT" if sold else "KAUFEN")
		_buttons[index].modulate = Color("978e7d") if sold or not affordable else Color("fff0cc")
		_prices[index].modulate = Color("cc806b") if not sold and not affordable else Color("d9c397")
		_button_materials[index].albedo_color = Color("292a26") if sold else (Color("9b6b38") if _hovered == index and affordable else Color("59402a"))
		_cards[index].visible = not sold
		Localization.fit_text_3d(_buttons[index], 1.11, 0.25)
		Localization.fit_text_3d(_prices[index], 1.28, 0.24)


func _offer_at(point: Vector2) -> int:
	if not is_instance_valid(camera) or not get_viewport().get_visible_rect().has_point(point):
		return -1
	var origin := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	var normal := global_basis.z.normalized()
	if normal.dot(direction) >= -0.001:
		return -1
	for index in range(offer_areas.size()):
		var area := offer_areas[index]
		var hit: Variant = Plane(normal, area.global_position).intersects_ray(origin, direction)
		if hit == null:
			continue
		var local: Vector3 = area.to_local(hit)
		if absf(local.x) <= BUTTON_SIZE.x * 0.5 and absf(local.y) <= BUTTON_SIZE.y * 0.5:
			return index
	return -1


func _make_area(area_name: String, at: Vector3, dimensions: Vector2) -> Area3D:
	var area := Area3D.new()
	area.name = area_name
	area.position = at
	area.collision_layer = 0
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	area.input_ray_pickable = false
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(dimensions.x, dimensions.y, 0.06)
	collision.shape = box
	area.add_child(collision)
	add_child(area)
	return area


func _label(value: String, at: Vector3, size: int, pixel: float, parent: Node3D = null) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.font = FONT
	label.font_size = size
	label.pixel_size = pixel
	label.position = at
	label.modulate = Color("ebdbb4")
	label.outline_size = 2
	label.shaded = false
	(parent if parent != null else self).add_child(label)
	return label


func _disable_card_input(node: Node) -> void:
	if node is CollisionObject3D:
		node.input_ray_pickable = false
		node.collision_layer = 0
		node.collision_mask = 0
		node.set_meta("keep_input_ray_pickable_disabled", true)
	for child in node.get_children():
		_disable_card_input(child)
