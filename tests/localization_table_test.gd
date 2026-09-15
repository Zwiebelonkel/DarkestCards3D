extends Node3D
## Real event/battle presentation; run through the isolated match feature runner.

var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	print(("PASS " if value else "FAIL ") + message)
	if not value:
		failures += 1
func _ready() -> void:
	run.call_deferred()
func run() -> void:
	if (
		not GameCurrency.save_path.begins_with("res://test-user/")
		or not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/")
		or not SettingsManager.CONFIG_PATH.begins_with("res://test-user/")
	):
		push_error("Run localization_table_test through the isolated match feature runner.")
		get_tree().quit(1)
		return
	var camera := Camera3D.new()
	add_child(camera)
	var table := (load("res://scenes/table/GameTable.tscn") as PackedScene).instantiate() as GameTable
	table.table_camera = camera
	add_child(table)
	await get_tree().process_frame
	table.enemy_turn_delay = 60.0
	table.set_process(false)
	table._table_state = GameTable.TableState.PLAYING
	table._game_over = false
	table._current_turn = "player"
	table._rng.seed = 314159
	table._initialize_event_deck()
	var ally: Dictionary = {}
	var opposing: Dictionary = {}
	for event: Dictionary in table._event_deck:
		if event["id"] == "strength_120" and ally.is_empty():
			ally = event
		if event["id"] == "block" and opposing.is_empty():
			opposing = event
	table._event_deck.erase(ally)
	table._event_deck.erase(opposing)
	table._player_event_hand.assign([ally, opposing])
	for side: String in ["player", "enemy"]:
		var data := CardDatabase.get_card("corpse").duplicate(true)
		data["instance_id"] = "localization-test-" + side
		data["effects"] = []
		data["active_effects"] = []
		data["defense"] = 100
		var deck: Array[Dictionary] = table._player_deck if side == "player" else table._enemy_deck
		deck.append(data)
		table._draw_to_slot(side, 0, false)
	Localization.set_locale("de")
	table._on_event_selected(ally["uid"])
	table._refresh_event_hand()
	var snapshot := table._build_online_snapshot().duplicate(true)
	var rng_state := table._rng.state
	Localization._formatted_sources.clear()
	for locale: String in Localization.SUPPORTED_LOCALES:
		Localization.set_locale(locale)
		check(table._event_notice == Localization.format_text("%s · Choose one of your cards. Right-click/Esc: cancel", [Localization.localized_arg(ally["name"])]), "whole ally prompt and event name: " + locale)
		check(table._event_hand_ui._status_label.text.ends_with(table._event_notice), "visible hand notice refreshed: " + locale)
		check(table._build_online_snapshot() == snapshot and table._rng.state == rng_state and table._selected_event_uid == ally["uid"], "locale preserves selection, snapshot and RNG: " + locale)
	table._on_event_target_clicked("enemy", 0)
	Localization.set_locale("en")
	check(table._event_notice == "Choose one of your cards for this event.", "wrong ally target uses a complete English sentence")
	table._on_event_selected(opposing["uid"])
	Localization.set_locale("fr")
	check(table._event_notice == Localization.format_text("%s · Choose an opposing card. Right-click/Esc: cancel", [Localization.localized_arg(opposing["name"])]), "whole opposing prompt and authored name")
	table._on_event_target_clicked("player", 0)
	Localization.set_locale("en")
	check(table._event_notice == "Choose an opposing card for this event.", "wrong opposing target uses a complete English sentence")
	check(table._try_play_event("player", opposing["uid"], 0), "actual event resolves once")
	snapshot = table._build_online_snapshot().duplicate(true)
	rng_state = table._rng.state
	Localization.set_locale("pl")
	check(table._event_notice == Localization.format_text("%s spielt %s", [Localization.localized_arg("Du"), Localization.localized_arg(opposing["name"])]), "played event localizes You and authored event name")
	check(table._build_online_snapshot() == snapshot and table._rng.state == rng_state, "event result locale does not replay effect or alter network state")
	check(table._event_target_error("player", {}, 0) == "Event nicht verfügbar.", "validation reason remains a canonical network source")
	var attacker: Card3D = table._player_slots[0]
	var defender: Card3D = table._enemy_slots[0]
	attacker.stun_next_attack()
	table._resolve_duel(attacker, defender, "player")
	snapshot = table._build_online_snapshot().duplicate(true)
	rng_state = table._rng.state
	Localization.set_locale("es")
	check(table._match_status_message == Localization.format_text("%s ist betäubt und setzt aus!", [Localization.localized_arg(attacker.card_data["name"])]), "actual battle notice translates card name after locale change")
	check(table._build_online_snapshot() == snapshot and table._rng.state == rng_state, "battle translation does not rerun duel or consume RNG")
	table._clear_match()
	await get_tree().create_timer(0.55).timeout
	NetworkManager._participants = {1:{"role":"player", "name":"Settings"}}
	table._online_is_spectator = true
	table._apply_online_result("player")
	Localization.set_locale("fr")
	check(table._match_status_message.contains("Settings"), "Steam persona identical to source key stays verbatim")
	NetworkManager._participants.clear()
	table._apply_online_result("enemy")
	Localization.set_locale("pl")
	check(table._match_status_message.contains("Gość"), "authored guest fallback retranslates")
	table._online_is_spectator = false
	GameCurrency.reset_progression()
	table._last_match_outcome = GameTable.MatchOutcome.WIN
	table._match_reward_granted = false
	Localization.set_locale("en")
	table._grant_match_rewards()
	check(table._match_reward_text == "Victory! · +100 XP · +10 Soul Coins\nLevel 2! +25 Soul Coins", "actual win displays full English reward and level bonus")
	var balance := [GameCurrency.coins, GameCurrency.level, GameCurrency.xp]
	for locale: String in ["de", "es", "fr", "pl", "en"]:
		Localization._formatted_sources.clear()
		Localization.set_locale(locale)
		var expected := Localization.format_text("%s · +%d XP · +%d Soul Coins", [Localization.localized_arg("Sieg!"),100,10]) + Localization.format_text("\nLevel %d! +%d Soul Coins", [2,25])
		check(table._match_reward_text == expected and table._match_status_message == expected, "both reward lines retranslate without cache: " + locale)
		table._grant_match_rewards()
		check([GameCurrency.coins,GameCurrency.level,GameCurrency.xp] == balance, "locale and duplicate results never award twice: " + locale)
	table._set_match_status("Beende Online-Match...")
	Localization.set_locale("de")
	check(table._match_status_message == Localization.text("Beende Online-Match..."), "exit status is not overwritten by stored reward")
	table._clear_match()
	Localization.set_locale("en")
	check(table._match_reward_text.is_empty(), "new match clears cached reward presentation")
	table.queue_free()
	await get_tree().process_frame
	print("LOCALIZATION_TABLE_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)

