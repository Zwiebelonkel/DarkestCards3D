extends Node3D
class_name LocalizedModelText

## Runtime presentation over imported geometry. No imported resource is edited;
## moving buttons retain their existing parents, animations and collision boxes.
const FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")
const ATLAS_SHADER := preload("res://assets/shader/localized_slot_atlas.gdshader")
const ATLAS_SIZE := Vector2(1536.0, 1024.0)
# Pixel rectangles in the original slot atlas, excluding ornamental borders.
# Old payout figures and BAR lettering are covered: actual reels/payouts are
# already rendered from the game's five effect symbols by SoulSlotMachine.
const ATLAS_REGIONS := [
	{"rect": Rect2(108, 110, 280, 88), "source": "JACKPOT"},
	{"rect": Rect2(1090, 135, 174, 102), "source": "GOOD LUCK"},
	{"rect": Rect2(113, 507, 262, 43), "source": "PLAY TO WIN"},
	{"rect": Rect2(1325, 729, 163, 77), "source": "INSERT COIN"},
	{"rect": Rect2(1280, 448, 238, 253), "source": ""},
	{"rect": Rect2(212, 385, 74, 49), "source": ""},
	{"rect": Rect2(1050, 558, 115, 47), "source": ""},
	{"rect": Rect2(1050, 641, 115, 47), "source": ""},
]

var _mesh_texts: Array[Dictionary] = []
var _atlas_labels: Array[Dictionary] = []


static func attach_neon(sign: Node3D, source: String) -> LocalizedModelText:
	if sign == null:
		return null
	var existing := sign.get_node_or_null("LocalizedModelText") as LocalizedModelText
	if existing != null:
		return existing
	var helper := LocalizedModelText.new()
	helper.name = "LocalizedModelText"
	sign.add_child(helper)
	var old := sign.find_child("cards", true, false) as MeshInstance3D
	if old != null:
		helper._replace_xz_text(old, source)
	helper._refresh()
	return helper


static func attach_slot_model(model: Node3D) -> LocalizedModelText:
	if model == null:
		return null
	var existing := model.get_node_or_null("LocalizedModelText") as LocalizedModelText
	if existing != null:
		return existing
	var helper := LocalizedModelText.new()
	helper.name = "LocalizedModelText"
	model.add_child(helper)
	for entry in [["setzen", "Text_002", "BET"], ["spin", "Text_003", "SPIN"]]:
		var button := model.find_child(entry[0], true, false) as Node3D
		if button == null:
			continue
		# Godot sanitizes glTF dots to underscores in node names. Discover the
		# direct text child rather than depending on a particular importer build.
		for child in button.get_children():
			if child is MeshInstance3D and str(child.name).begins_with("Text"):
				helper._replace_xz_text(child, entry[2])
				break
	helper._localize_atlas_meshes(model)
	helper._refresh()
	return helper


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Localization.locale_changed.connect(_refresh)


func _replace_xz_text(original: MeshInstance3D, source: String) -> void:
	var carrier := Node3D.new()
	carrier.name = "Localized" + str(original.name)
	original.get_parent().add_child(carrier)
	carrier.transform = original.transform
	var replacement := MeshInstance3D.new()
	replacement.name = "Letters"
	var letters := TextMesh.new()
	letters.font = FONT
	letters.font_size = 64
	letters.pixel_size = 0.01
	letters.depth = 0.08
	letters.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letters.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	replacement.mesh = letters
	var material := original.get_active_material(0)
	if material != null:
		replacement.material_override = material.duplicate(true)
	carrier.add_child(replacement)
	_mesh_texts.append({"mesh": replacement, "source": source, "bounds": original.get_aabb()})
	original.visible = false


func _refresh() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	for entry: Dictionary in _mesh_texts:
		var replacement := entry["mesh"] as MeshInstance3D
		if not is_instance_valid(replacement):
			continue
		var letters := replacement.mesh as TextMesh
		letters.text = Localization.text(entry["source"])
		var bounds: AABB = entry["bounds"]
		var printed := letters.get_aabb()
		var fit := minf(bounds.size.x / maxf(printed.size.x, 0.001), bounds.size.z / maxf(printed.size.y, 0.001))
		var frame := Basis(Vector3.RIGHT, -PI / 2.0) * Basis.from_scale(Vector3(fit, fit, bounds.size.y / maxf(printed.size.z, 0.001)))
		# Imported lettering lies in XZ, with its outward face along +Y.
		replacement.transform = Transform3D(frame, bounds.get_center() - frame * printed.get_center())
	for entry: Dictionary in _atlas_labels:
		var label := entry["label"] as Label3D
		if not is_instance_valid(label):
			continue
		label.text = Localization.text(entry["source"])
		var size: Vector2 = entry["size"]
		var pixel_width := FONT.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x
		label.pixel_size = minf(size.x / maxf(pixel_width, 1.0), size.y / float(label.font_size)) * 0.88


func _localize_atlas_meshes(root: Node) -> void:
	if root is MeshInstance3D:
		var mesh := root as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.get_active_material(surface) as StandardMaterial3D
			if original == null or original.albedo_texture == null or original.albedo_texture.get_size() != ATLAS_SIZE:
				continue
			var material := ShaderMaterial.new()
			material.shader = ATLAS_SHADER
			material.set_shader_parameter("atlas", original.albedo_texture)
			var masks := PackedVector4Array()
			for region: Dictionary in ATLAS_REGIONS:
				var rect: Rect2 = region["rect"]
				masks.append(Vector4(rect.position.x / ATLAS_SIZE.x, rect.position.y / ATLAS_SIZE.y, rect.end.x / ATLAS_SIZE.x, rect.end.y / ATLAS_SIZE.y))
			material.set_shader_parameter("text_masks", masks)
			material.set_shader_parameter("roughness_value", original.roughness)
			mesh.set_surface_override_material(surface, material)
			_add_atlas_labels(mesh, surface)
	# Snapshot children: creating labels while traversing must not recurse into
	# newly generated presentation nodes or duplicate them.
	for child in root.get_children():
		if child != self and not child is Label3D:
			_localize_atlas_meshes(child)


func _add_atlas_labels(mesh: MeshInstance3D, surface: int) -> void:
	var arrays := mesh.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		for index in vertices.size():
			indices.append(index)
	for region: Dictionary in ATLAS_REGIONS:
		var source: String = region["source"]
		if source.is_empty():
			continue
		var rect: Rect2 = region["rect"]
		var target_uv := rect.get_center() / ATLAS_SIZE
		var centers: Array[Vector3] = []
		for triangle in range(0, indices.size(), 3):
			var a := indices[triangle]
			var b := indices[triangle + 1]
			var c := indices[triangle + 2]
			var u := uvs[b] - uvs[a]
			var v := uvs[c] - uvs[a]
			var determinant := u.cross(v)
			if absf(determinant) < 0.000001:
				continue
			var point := target_uv - uvs[a]
			var weight_b := point.cross(v) / determinant
			var weight_c := u.cross(point) / determinant
			if weight_b < -0.0001 or weight_c < -0.0001 or weight_b + weight_c > 1.0001:
				continue
			var edge_b := vertices[b] - vertices[a]
			var edge_c := vertices[c] - vertices[a]
			var center := vertices[a] + edge_b * weight_b + edge_c * weight_c
			var duplicate := false
			for other: Vector3 in centers:
				if other.distance_to(center) < 0.001:
					duplicate = true
			if duplicate:
				continue
			centers.append(center)
			var right := (edge_b * v.y - edge_c * u.y) / determinant
			var down := (edge_c * u.x - edge_b * v.x) / determinant
			var normal := normals[a].normalized()
			var label := Label3D.new()
			label.name = "LocalizedAtlasText"
			label.font = FONT
			label.font_size = 64
			label.outline_size = 3
			label.modulate = Color("e3cfc0")
			label.outline_modulate = Color("240a0c")
			label.shaded = false
			label.no_depth_test = false
			label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mesh.add_child(label)
			label.transform = Transform3D(Basis(right.normalized(), -down.normalized(), right.cross(-down).normalized()), center + normal * 0.006)
			_atlas_labels.append({"label": label, "source": source, "size": Vector2(right.length() * rect.size.x / ATLAS_SIZE.x, down.length() * rect.size.y / ATLAS_SIZE.y)})
