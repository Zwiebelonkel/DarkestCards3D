extends Node

const CURRENCY_SCRIPT := preload("res://scripts/GameCurrency.gd")
const LEVEL_PROGRESS_SCENE := preload("res://scenes/ui/LevelProgress.tscn")
const PANEL_NODE_NAMES := [
	"Frame", "BrassTrim", "RecessedFace", "XPTrack", "XPFill", "BottomRail",
	"TopLeftScrew", "TopRightScrew", "BottomLeftScrew", "BottomRightScrew",
	"LevelLabel", "XPLabel", "BonusLabel", "CoinLabel", "CoinButton", "CoinButton/Label3D",
]

class TestLevelProgress extends "res://scripts/ui/LevelProgress.gd":
	# The headless DisplayServer cannot enter fullscreen. Override only the
	# platform query so all production pointer and notification logic runs.
	var simulated_window_mode: int = Window.MODE_WINDOWED

	func _is_fullscreen() -> bool:
		return simulated_window_mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]

var _failures: Array[String] = []
var _level_events: Array[Vector2i] = []
var _coins_events: Array[float] = []
var _progress_events := 0


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	# The runner creates a tiny project with only currency and an isolated profile.
	if ProjectSettings.get_setting("application/config/name", "") != "DarkestCardsProgressionTests":
		push_error("Use tests/run_progression_tests.ps1 to keep real saves isolated.")
		get_tree().quit(1)
		return
	Localization.set_locale("de")
	GameCurrency.save_path = "res://progression-ui-test.cfg"
	var currency := CURRENCY_SCRIPT.new()
	currency.save_path = "res://progression-test.cfg"
	currency.coins_changed.connect(func(value: float) -> void: _coins_events.append(value))
	currency.level_up.connect(func(new_level: int, bonus: int) -> void: _level_events.append(Vector2i(new_level, bonus)))
	currency.progression_changed.connect(func(_level: int, _xp: int, _required: int) -> void: _progress_events += 1)

	currency.load_currency()
	_expect(currency.get_coins() == 20 and currency.get_level() == 1 and currency.get_xp() == 0, "New profile has 20 coins, level 1, no XP")
	_expect(currency.get_xp_required() == 100 and currency.get_level_bonus() == 25, "First level requires 100 XP and grants 25 coins")
	var ignored: Dictionary = currency.add_xp(-5)
	_expect(ignored["xp_awarded"] == 0 and not FileAccess.file_exists(currency.save_path), "Negative XP is a no-op")
	currency.add_xp(99)
	_expect(currency.get_level() == 1 and currency.get_xp() == 99 and currency.get_coins() == 20, "Below-boundary XP keeps the current level and coins")
	var boundary: Dictionary = currency.add_xp(1)
	_expect(boundary["levels_gained"] == 1 and boundary["coins_bonus"] == 25, "Exact level boundary awards its bonus once")
	_expect(currency.get_level() == 2 and currency.get_xp() == 0 and currency.get_coins() == 45, "Boundary consumes XP and credits coins")
	_expect(_level_events == [Vector2i(2, 25)], "Level-up signal reports level and bonus")
	_expect(currency.get_xp_required() == 150, "Next level has a larger requirement")

	var overflow: Dictionary = currency.add_xp(375)
	_expect(overflow["old_level"] == 2 and overflow["new_level"] == 4 and overflow["levels_gained"] == 2, "One award can cross multiple levels")
	_expect(currency.get_xp() == 25 and currency.get_xp_required() == 250, "Multiple level-ups preserve overflow XP")
	_expect(overflow["coins_bonus"] == 80 and currency.get_coins() == 125, "Every crossed level grants its coin bonus")
	_expect(_level_events == [Vector2i(2, 25), Vector2i(3, 35), Vector2i(4, 45)], "Each crossed level emits exactly one event")
	_expect(_coins_events == [20.0, 45.0, 125.0] and _progress_events == 4, "Progress and coin signals match actual changes")

	var reloaded := CURRENCY_SCRIPT.new()
	reloaded.save_path = currency.save_path
	reloaded.load_currency()
	_expect(reloaded.get_level() == 4 and reloaded.get_xp() == 25 and reloaded.get_coins() == 125, "Currency, level and XP persist together")
	_expect(not FileAccess.file_exists(currency.save_path + ".tmp"), "Atomic save leaves no temporary file after replacement")
	_expect(reloaded.spend_coins(100), "Level bonus money can be spent")
	reloaded.add_coins(3)
	currency.load_currency()
	_expect(currency.get_coins() == 28 and currency.get_level() == 4 and currency.get_xp() == 25, "Currency transactions retain progression")
	_expect(not currency.spend_coins(29) and currency.get_coins() == 28, "Unaffordable purchases preserve the balance")

	var legacy := ConfigFile.new()
	legacy.set_value("currency", "coins", 321)
	_expect(legacy.save(currency.save_path) == OK, "Legacy currency fixture saves")
	currency.load_currency()
	_expect(currency.get_coins() == 321 and currency.get_level() == 1 and currency.get_xp() == 0, "Legacy saves retain coins and start at level 1")
	currency.add_xp(10)
	reloaded.load_currency()
	_expect(reloaded.get_coins() == 321 and reloaded.get_xp() == 10, "Legacy profile migrates on the next award")

	currency.reset_progression()
	reloaded.load_currency()
	_expect(reloaded.get_coins() == 20 and reloaded.get_level() == 1 and reloaded.get_xp() == 0, "Reset clears and persists all progression")
	currency.add_xp(200)
	DirAccess.remove_absolute(currency.save_path)
	currency.reset_progression(false)
	_expect(currency.get_level() == 1 and currency.get_xp() == 0 and currency.get_coins() == 20, "Menu reset also clears in-memory progression")
	_expect(not FileAccess.file_exists(currency.save_path), "Non-persistent menu reset leaves deleted saves deleted")
	_expect(currency.get_match_xp("win") == 100 and currency.get_match_xp("draw") == 50 and currency.get_match_xp("loss") == 25 and currency.get_match_xp("spectator") == 0, "Only recognized playing outcomes grant match XP")
	_check_match_rewards()
	_check_fractional_coins()
	get_tree().root.size = Vector2i(1280, 720)
	var camera := Camera3D.new()
	get_tree().root.add_child(camera)
	camera.make_current()
	var badge := LEVEL_PROGRESS_SCENE.instantiate()
	badge.set_script(TestLevelProgress)
	camera.add_child(badge)
	# Feed deterministic pointer positions while keeping SceneTree tweens running.
	badge.set_process(false)
	_expect(badge is Node3D, "Level progress is a reusable 3D scene")
	_expect(badge.level_label is Label3D and badge.xp_label is Label3D and badge.bonus_label is Label3D, "Level, XP and bonus text are physical 3D labels")
	_expect(badge.level_label.text == Localization.format_text("LEVEL %d", [1]) and badge.xp_label.text == Localization.format_text("%d / %d XP", [0, 100]), "3D progress displays a fresh localized profile")
	_expect(not badge.is_expanded() and badge.visible, "Visor starts folded with its hinge still visible")
	_check_hardware_visible(badge, camera)
	_expect(not badge.xp_fill.visible, "Zero XP leaves the 3D bar empty")
	_expect(_uses_only_3d_geometry(badge), "Progress scene uses 3D geometry without 2D controls or picking collisions")
	GameCurrency.add_xp(125)
	_expect(badge.level_label.text == Localization.format_text("LEVEL %d", [2]) and badge.xp_label.text == Localization.format_text("%d / %d XP", [25, 150]), "3D text follows XP and level signals while folded")
	_expect(badge.xp_fill.visible and is_equal_approx(badge.xp_fill.scale.x, 25.0 / 150.0) and badge.bonus_label.text.contains("35"), "3D bar fill and next coin bonus follow the new level")
	_check_localized_progress(badge)
	var screen_size := get_viewport().get_visible_rect().size
	badge.set_pointer_position(screen_size * 0.5)
	_expect(not badge.is_expanded(), "Pointer over the board keeps the visor folded")
	badge.set_pointer_position(Vector2(screen_size.x * 0.5, 2.0))
	_expect(badge.is_expanded(), "Pointer at the top edge unfolds the visor")
	await get_tree().create_timer(0.65).timeout
	_expect(badge.visible and absf(badge.hinge.rotation_degrees.x) < 0.1, "Visor finishes its downward hinge rotation")
	await _check_camera_layouts(badge, camera)
	screen_size = get_viewport().get_visible_rect().size
	badge.set_pointer_position(Vector2(screen_size.x * 0.5, 40.0))
	_expect(badge.is_expanded(), "Moving onto the progress panel keeps it open")
	badge.set_pointer_position(Vector2(screen_size.x * 0.5, screen_size.y * 0.6))
	_expect(not badge.is_expanded(), "Returning to the board folds the visor away")
	await get_tree().create_timer(0.65).timeout
	_expect(badge.visible and badge.hinge.rotation_degrees.x > 90.0, "Folded visor keeps the physical hinge visible")
	_check_hardware_visible(badge, camera)
	badge.set_enabled(false)
	badge.set_pointer_position(Vector2(screen_size.x * 0.5, 2.0))
	_expect(not badge.is_expanded() and badge.visible, "Disabled visor ignores the top edge while retaining its hinge")
	badge.set_enabled(true)
	badge.set_pointer_position(Vector2(screen_size.x * 0.5, 2.0))
	_expect(badge.is_expanded(), "Re-enabled visor responds to the top edge again")
	_check_window_edges(badge, camera)
	camera.free()
	DirAccess.remove_absolute(GameCurrency.save_path)
	currency.free()
	reloaded.free()
	if _failures.is_empty():
		print("PASS: progression boundaries, overflow, signals, atomic save/reload, legacy migration, reset, rewards and 3D visor interaction")
	else:
		for failure in _failures:
			push_error(failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _check_localized_progress(badge: LevelProgress) -> void:
	var before := [GameCurrency.get_coin_cents(), GameCurrency.get_level(), GameCurrency.get_xp(), badge.is_expanded(), badge.hinge.transform, badge.xp_fill.scale]
	for locale: String in Localization.SUPPORTED_LOCALES:
		Localization.set_locale(locale)
		_expect(badge.level_label.text == Localization.format_text("LEVEL %d", [2]), "Language change updates the physical level label: " + locale)
		_expect(badge.xp_label.text == Localization.format_text("%d / %d XP", [25, 150]), "Language change updates the XP label: " + locale)
		_expect(badge.bonus_label.text == Localization.format_text("Nächstes Level: +%d Soul Coins", [35]), "Language change updates the next-level bonus: " + locale)
		_expect(badge.coin_label.text == Localization.format_text("%s Soul Coins", [GameCurrency.format_coins()]), "Language change updates the coin balance: " + locale)
		_expect(GameCurrency.format_coins(0.02) == ("0.02" if locale == "en" else "0,02"), "Currency decimals follow the selected locale: " + locale)
		_expect([GameCurrency.get_coin_cents(), GameCurrency.get_level(), GameCurrency.get_xp(), badge.is_expanded(), badge.hinge.transform, badge.xp_fill.scale] == before, "Language change preserves currency, progression and visor state: " + locale)
	Localization.set_locale("de")


func _check_match_rewards() -> void:
	var currency := CURRENCY_SCRIPT.new()
	currency.save_path = "res://match-rewards-test.cfg"
	var coin_events: Array[float] = []
	var saved_events: Array[Dictionary] = []
	var level_events: Array[Vector2i] = []
	currency.coins_changed.connect(func(value: float) -> void:
		coin_events.append(value)
		var saved := ConfigFile.new()
		var loaded := saved.load(currency.save_path) == OK
		saved_events.append({
			"loaded": loaded,
			"coins": int(saved.get_value("currency", "coins", -1)),
			"level": int(saved.get_value("progression", "level", -1)),
			"xp": int(saved.get_value("progression", "xp", -1)),
		})
	)
	currency.level_up.connect(func(new_level: int, bonus: int) -> void:
		level_events.append(Vector2i(new_level, bonus))
	)
	for outcome: Dictionary in [
		{"name": "win", "coins": 10, "xp": 100},
		{"name": "draw", "coins": 5, "xp": 50},
		{"name": "loss", "coins": 2, "xp": 25},
	]:
		for crosses_level: bool in [false, true]:
			currency.coins = 20
			currency.level = 2
			currency.xp = 150 - int(outcome["xp"]) if crosses_level else 0
			coin_events.clear()
			saved_events.clear()
			level_events.clear()
			var result: Dictionary = currency.award_match(str(outcome["name"]))
			var expected_bonus := 35 if crosses_level else 0
			var expected_coins := 20 + int(outcome["coins"]) + expected_bonus
			var expected_level := 3 if crosses_level else 2
			var expected_xp := 0 if crosses_level else int(outcome["xp"])
			var context := "%s, level-up=%s" % [outcome["name"], crosses_level]
			_expect(result["xp_awarded"] == outcome["xp"] and result["coins_reward"] == outcome["coins"], context + ": match awards fixed coins alongside XP")
			_expect(result["coins_bonus"] == expected_bonus and result["coins_awarded"] == expected_coins - 20, context + ": level bonus is additional to the match payout")
			_expect(currency.coins == expected_coins and currency.level == expected_level and currency.xp == expected_xp, context + ": complete reward reaches the profile")
			_expect(coin_events == [float(expected_coins)], context + ": coin listeners receive the complete reward once")
			_expect(saved_events == [{"loaded": true, "coins": expected_coins, "level": expected_level, "xp": expected_xp}], context + ": coin listeners see all rewards already persisted together")
			_expect(level_events == ([Vector2i(3, 35)] if crosses_level else []), context + ": only a real level-up emits its bonus event")
			var reloaded := CURRENCY_SCRIPT.new()
			reloaded.save_path = currency.save_path
			reloaded.load_currency()
			_expect(reloaded.coins == expected_coins and reloaded.level == expected_level and reloaded.xp == expected_xp, context + ": reward survives profile reload")
			reloaded.free()
	DirAccess.remove_absolute(currency.save_path)
	coin_events.clear()
	var coins_before: float = currency.coins
	var xp_before: int = currency.xp
	var invalid: Dictionary = currency.award_match("spectator")
	_expect(invalid["coins_awarded"] == 0 and invalid["xp_awarded"] == 0 and currency.coins == coins_before and currency.xp == xp_before, "Unknown or spectator result grants no reward")
	_expect(coin_events.is_empty() and not FileAccess.file_exists(currency.save_path), "Unknown result does not notify or write a profile")
	currency.free()


func _check_fractional_coins() -> void:
	var currency := CURRENCY_SCRIPT.new()
	currency.save_path = "res://fractional-coins-test.cfg"
	currency.coins = 0.0
	var observed: Array[float] = []
	currency.coins_changed.connect(func(value: float) -> void: observed.append(value))
	for click_index in 50:
		currency.add_coins(0.02)
	_expect(currency.get_coin_cents() == 100, "Fifty base clicks produce exactly one Soul Coin")
	_expect(is_equal_approx(observed[0], 0.02), "Balance listeners receive fractions without truncation")
	for click_index in 100:
		currency.add_coins(0.01)
	_expect(currency.get_coin_cents() == 200, "Repeated hundredths accumulate without floating-point drift")
	currency.add_coins(0.05)
	_expect(currency.spend_coins(2.0) and currency.get_coin_cents() == 5, "Whole-coin purchases retain the fractional remainder")
	_expect(not currency.has_coins(0.06) and not currency.spend_coins(0.06) and currency.get_coin_cents() == 5, "An unaffordable fractional purchase preserves the balance")
	_expect(currency.has_coins(0.05) and currency.spend_coins(0.05) and currency.get_coin_cents() == 0, "An exact fractional balance can be spent")
	currency.reset_progression(false)
	currency.add_coins(0.03)
	currency.award_match("win")
	_expect(currency.get_coin_cents() == 5503 and currency.level == 2, "Match reward and level bonus preserve earned hundredths")
	_expect(currency.format_coins() == "55,03" and currency.format_coins(0.02) == "0,02", "Coin formatting shows both decimal places")
	var saved := ConfigFile.new()
	_expect(saved.load(currency.save_path) == OK and saved.get_value("currency", "coin_cents", -1) == 5503, "The save records exact integer hundredths")
	var reloaded := CURRENCY_SCRIPT.new()
	reloaded.save_path = currency.save_path
	reloaded.load_currency()
	_expect(reloaded.get_coin_cents() == 5503 and reloaded.level == 2, "Fractional reward and progression survive reload")
	var legacy := ConfigFile.new()
	legacy.set_value("currency", "coins", 12.34)
	legacy.set_value("progression", "level", 3)
	legacy.set_value("progression", "xp", 5)
	legacy.save(currency.save_path)
	reloaded.load_currency()
	_expect(reloaded.get_coin_cents() == 1234 and reloaded.level == 3 and reloaded.xp == 5, "Legacy fractional saves migrate without truncation or lost progress")
	reloaded.add_coins(0.01)
	currency.load_currency()
	_expect(currency.get_coin_cents() == 1235, "Migrated balances remain exact after another reward")
	DirAccess.remove_absolute(currency.save_path)
	currency.free()
	reloaded.free()


func _uses_only_3d_geometry(node: Node) -> bool:
	if node is Control or node is CollisionObject3D:
		return false
	for child in node.get_children():
		if not _uses_only_3d_geometry(child):
			return false
	return true


func _check_hardware_visible(badge: Node3D, camera: Camera3D) -> void:
	var viewport_rect := get_viewport().get_visible_rect()
	for hardware_name: String in ["Axle", "LeftHinge", "RightHinge", "LeftHingeBand", "RightHingeBand"]:
		var hardware := badge.get_node(hardware_name) as MeshInstance3D
		_expect(hardware.is_visible_in_tree(), "%s stays visible when progress is folded" % hardware_name)
		var has_projected_vertex := false
		var projected_bounds := Rect2()
		for vertex: Vector3 in hardware.mesh.get_faces():
			var corner := hardware.to_global(vertex)
			if camera.is_position_behind(corner):
				continue
			var projected := camera.unproject_position(corner)
			if not has_projected_vertex:
				projected_bounds = Rect2(projected, Vector2.ZERO)
				has_projected_vertex = true
			else:
				projected_bounds = projected_bounds.expand(projected)
		_expect(has_projected_vertex and projected_bounds.intersects(viewport_rect), "%s remains partly visible at the top edge" % hardware_name)


func _check_window_edges(badge: Node3D, camera: Camera3D) -> void:
	for window_mode: int in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
		badge.simulated_window_mode = window_mode
		var viewport_size := get_viewport().get_visible_rect().size
		var top_edge := Vector2(viewport_size.x * 0.5, 0.0)
		badge._notification(Node.NOTIFICATION_WM_MOUSE_ENTER)
		badge.set_expanded(false)
		badge.set_pointer_position(top_edge)
		_expect(badge.is_expanded(), "Exact top pixel opens the visor in fullscreen mode %d" % window_mode)
		badge._notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
		_expect(badge.is_expanded(), "Fullscreen border exit event does not snap the visor shut")
		for top_y: float in [-1.0, 0.0, 1.0, -1.0]:
			badge.set_pointer_position(Vector2(top_edge.x, top_y))
			_expect(badge.is_expanded(), "Fullscreen border y=%s remains open after mouse exit" % top_y)
		badge.set_expanded(false)
		badge.set_pointer_position(Vector2(top_edge.x, -1.0))
		_expect(badge.is_expanded(), "Fullscreen border can reopen without a mouse-enter event")
		badge.set_pointer_position(Vector2(-20.0, 0.0))
		_expect(not badge.is_expanded() and badge.visible, "Genuine fullscreen side exit folds while retaining the hinge")
		badge._notification(Node.NOTIFICATION_WM_MOUSE_ENTER)
		badge.set_pointer_position(top_edge)
		badge._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		_expect(not badge.is_expanded() and badge.visible, "Focus loss folds the visor while retaining the hinge")
		badge._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
		badge.set_pointer_position(top_edge)
		get_tree().paused = true
		badge._process(0.0)
		_expect(not badge.is_expanded() and badge.visible, "Pausing folds the visor while retaining the hinge")
		get_tree().paused = false
	badge.simulated_window_mode = Window.MODE_WINDOWED
	badge._notification(Node.NOTIFICATION_WM_MOUSE_ENTER)
	var viewport_size := get_viewport().get_visible_rect().size
	badge.set_pointer_position(Vector2(viewport_size.x * 0.5, 0.0))
	_expect(badge.is_expanded(), "Windowed top pixel opens the visor")
	badge._notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	badge.set_pointer_position(Vector2(viewport_size.x * 0.5, -1.0))
	_expect(not badge.is_expanded() and badge.visible, "Windowed exit is not mistaken for a fullscreen border")
	badge._notification(Node.NOTIFICATION_WM_MOUSE_ENTER)
	badge._update_camera_layout()
	_check_hardware_visible(badge, camera)


func _check_camera_layouts(badge: Node3D, camera: Camera3D) -> void:
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(720, 1280)]:
		get_tree().root.size = viewport_size
		await get_tree().process_frame
		for aspect_mode: int in [Camera3D.KEEP_HEIGHT, Camera3D.KEEP_WIDTH]:
			camera.keep_aspect = aspect_mode
			for field_of_view: float in [45.0, 95.0]:
				camera.fov = field_of_view
				badge._update_camera_layout()
				var layout_description := "%s at FOV %d, aspect mode %d" % [viewport_size, field_of_view, aspect_mode]
				var viewport_rect := get_viewport().get_visible_rect().grow(1.0)
				badge.hinge.rotation_degrees.x = 0.0
				for node_name: String in PANEL_NODE_NAMES:
					var geometry := badge.get_node("Hinge/" + node_name) as GeometryInstance3D
					_expect(geometry.visible and geometry.is_visible_in_tree(), "%s remains enabled when open in %s" % [node_name, layout_description])
					# Both game cameras use KEEP_HEIGHT; their open panel must fit.
					# Folded geometry is additionally checked under KEEP_WIDTH below.
					if aspect_mode == Camera3D.KEEP_HEIGHT:
						for corner_index in range(8):
							var corner := geometry.to_global(geometry.get_aabb().get_endpoint(corner_index))
							_expect(not camera.is_position_behind(corner) and viewport_rect.has_point(camera.unproject_position(corner)), "Open %s fits %s (corner %s)" % [node_name, layout_description, camera.unproject_position(corner)])
				badge.hinge.rotation_degrees.x = badge.STOWED_ANGLE
				_expect(badge.visible and badge.hinge.visible, "Folded scene stays enabled in %s" % layout_description)
				for node_name: String in PANEL_NODE_NAMES:
					var geometry := badge.get_node("Hinge/" + node_name) as GeometryInstance3D
					_expect(geometry.visible and geometry.is_visible_in_tree(), "%s folds out of view without being hidden in %s" % [node_name, layout_description])
					for corner_index in range(8):
						var corner := geometry.to_global(geometry.get_aabb().get_endpoint(corner_index))
						_expect(not camera.is_position_behind(corner) and camera.unproject_position(corner).y <= 0.0, "Folded %s stays above the screen in %s (corner %s)" % [node_name, layout_description, camera.unproject_position(corner)])
				_check_hardware_visible(badge, camera)
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	camera.fov = 75.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	badge.hinge.rotation_degrees.x = 0.0
	badge._update_camera_layout()
