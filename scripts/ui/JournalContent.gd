extends RefCounted
class_name JournalContent

## Read-only journal. Catalog chapters describe base data; the profile reads
## current progress without changing game state, creating instances or saving.
const PROFILE := preload("res://scripts/autoload/PlayerProfile.gd")
const RARITY_NAMES := {
	"common": "Gewöhnlich", "uncommon": "Ungewöhnlich", "rare": "Selten",
	"epic": "Episch", "legendary": "Legendär", "mythic": "Mythisch", "exotic": "Exotisch", "secret": "Secret",
}
const EGG_RULE := "Wird Egg zerstört, schlüpft mit 25 % Wahrscheinlichkeit am selben Platz eine neue Chick-Karte mit Grundwerten und Grundeffekten. Bei erfolgreichem Schlüpfen wird keine Karte nachgezogen oder zur Sammlung hinzugefügt; sonst wird normal nachgezogen. Überlebt das Küken fünf volle Runden auf dem Tisch, wird es zu Chicken. Steel stiehlt ein lebendes Ei, ohne es auszubrüten."
const CHICK_RULE := "Jedes Chick wächst nach fünf vollständig auf dem Tisch überlebten Runden zu Chicken heran, auch ein regulär gezogenes Küken. Eine Runde umfasst je einen Zug beider Seiten; ein beim Eintreffen bereits laufender Zug zählt nicht. Im Nachziehstapel pausiert das Wachstum, Steel erhält den bisherigen Fortschritt. Das Huhn ersetzt das Küken am selben Platz mit frischen Grundwerten und Grundeffekten, ohne Upgrades, Holo oder übernommene Zustände. Das ist kein Tod und löst keine Kill-Effekte aus; es wird keine Karte nachgezogen oder zur Sammlung hinzugefügt."
const EVENT_AVAILABILITY := "Alle Event-Kartentypen sind von Beginn an für alle freigeschaltet. Sie werden nicht aus Packs gezogen und gehören nicht zur Sammlung. Im Kampf erhältst du sie über deine zufällige Ereignis-Starthand oder Draw On Kill."


static func build_chapters() -> Array[Dictionary]:
	var cards := CardDatabase.get_all_cards().filter(func(card: Dictionary) -> bool: return not CardDatabase.is_event_card(card))
	# Match events deliberately live outside the collectible database.
	var event_cards := EventDeck.definitions()
	var card_entries: Array[Dictionary] = []
	var special_entries: Array[Dictionary] = []
	var event_entries: Array[Dictionary] = []
	for card: Dictionary in cards:
		if str(card.get("category", "combat")).to_lower() == "special":
			special_entries.append(_card_entry(card))
		elif CardData.is_combat_card(card):
			card_entries.append(_card_entry(card))
	for card: Dictionary in event_cards:
		event_entries.append(_card_entry(card, true))
	var card_order := func(a: Dictionary, b: Dictionary) -> bool:
		var comparison := str(a["title"]).naturalnocasecmp_to(str(b["title"]))
		return str(a["id"]) < str(b["id"]) if comparison == 0 else comparison < 0
	card_entries.sort_custom(card_order)
	special_entries.sort_custom(card_order)
	event_entries.sort_custom(card_order)
	# Reuse the authored catalog presentation without sharing mutable entry or
	# card dictionaries with the descriptive chapters. The gallery shows only
	# the cards; its own entry IDs remain unique throughout the journal.
	var collection_entries: Array[Dictionary] = []
	for entry: Dictionary in card_entries + special_entries:
		var collection_entry := entry.duplicate(true)
		collection_entry["id"] = "collection:" + str(entry["id"])
		collection_entries.append(collection_entry)
	# Sort from common to secret, keeping fixed slots within each rarity
	# across languages and finds.
	collection_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_rank := RarityEffectsData.rarity_rank(str(a["card_data"].get("rarity", "common")))
		var b_rank := RarityEffectsData.rarity_rank(str(b["card_data"].get("rarity", "common")))
		if a_rank != b_rank:
			return a_rank < b_rank
		var a_id := str(a["card_data"].get("id", ""))
		var b_id := str(b["card_data"].get("id", ""))
		return str(a["id"]) < str(b["id"]) if a_id == b_id else a_id < b_id)
	return [
		{"id": "cards", "title": _t("KAMPFKARTEN"), "entries": card_entries},
		{"id": "special_cards", "title": _t("SONDERKARTEN"), "entries": special_entries},
		{"id": "event_cards", "title": _t("EVENT-KARTEN"), "entries": event_entries},
		{"id": "effects", "title": _t("EFFEKTE"), "entries": _effect_entries(cards + event_cards)},
		{"id": "mechanics", "title": _t("MECHANIKEN"), "entries": _mechanic_entries()},
		build_profile_chapter(),
		{"id": "collection", "title": _t("COLLECTION"), "entries": collection_entries},
	]


static func build_profile_chapter() -> Dictionary:
	var stats := PROFILE.snapshot()
	var overview := _entry("profile:overview", _t("Dein Profil"),
		_t("Spielstand %d · Level %d") % [stats["slot"], stats["level"]],
		"\n".join([
			_t("Angriff: %d · Leben: %d") % [stats["total_attack"], stats["total_health"]],
			_t("Deck: %d / %d Karten") % [stats["deck_count"], stats["deck_capacity"]],
			"",
			_t("Soul Coins: %s") % GameCurrency.format_coins(stats["coins"]),
			_t("Erfahrung: %d / %d XP") % [stats["xp"], stats["xp_required"]],
			"",
			_t("Stärke = Angriff + maximale Lebenspunkte, inklusive Upgrades. Effekte zählen separat."),
		]))
	overview["profile_strength"] = stats["deck_strength"]
	var deck_lines: Array[String] = [
		_t("Gesamtstärke: %d") % stats["deck_strength"],
		_t("Angriff gesamt: %d") % stats["total_attack"],
		_t("Lebenspunkte gesamt: %d") % stats["total_health"],
		_t("Stärke je Karte: %s") % _number(stats["average_strength"]),
		_t("Effekte: %d · Arten: %d") % [stats["effect_count"], stats["unique_effects"]],
		_t("Holo-Karten im Deck: %d") % stats["holo_deck_count"],
		"",
	]
	var strongest_id := str(stats["strongest_card_id"])
	if strongest_id.is_empty():
		deck_lines.append(_t("Dein Deck ist noch leer."))
	else:
		deck_lines.append(_t("Stärkste Karte:"))
		deck_lines.append(_t(str(CardDatabase.get_card(strongest_id).get("name", strongest_id))))
		deck_lines.append(_t("Kartenstärke: %d") % stats["strongest_strength"])
	deck_lines.append("")
	deck_lines.append(_t("Werte deines gespeicherten Decks vor Kampfbeginn. Jede Kartenkopie zählt einzeln."))
	var deck := _entry("profile:deck", _t("Dein Deck"),
		_t("%d Karten · %d Kartentypen") % [stats["deck_count"], stats["unique_deck_cards"]], "\n".join(deck_lines))
	var collection := _entry("profile:collection", _t("Deine Sammlung"),
		_t("Spielstand %d · Sammelfortschritt") % stats["slot"],
		"\n".join([
			_t("Karten insgesamt: %d") % stats["collection_count"],
			_t("Kampfkarten: %d Exemplare") % stats["combat_copies"],
			_t("Kampfkartentypen: %d / %d") % [stats["combat_types"], stats["combat_catalog_count"]],
			_t("Sonderkartentypen: %d / %d") % [stats["special_types"], stats["special_catalog_count"]],
			_t("Holo-Karten insgesamt: %d") % stats["holo_collection_count"],
			"",
			_t("Gekaufte Stat-Upgrades: %d") % stats["stat_purchases"],
			"",
			_t("Exemplare zählen jede Kopie. Bei Kartentypen zählt jede verschiedene Karte einmal."),
		]))
	return {"id": "profile", "title": _t("PROFIL"), "entries": [overview, deck, collection]}


static func rarity_name(rarity: String) -> String:
	var normalized := rarity.to_lower().strip_edges()
	return _t(str(RARITY_NAMES.get(normalized, normalized.capitalize())))


static func _entry(id: String, title: String, subtitle: String, body: String) -> Dictionary:
	return {"id": id, "title": title, "subtitle": subtitle, "body": body}


static func _card_entry(card: Dictionary, match_event: bool = false) -> Dictionary:
	var id := str(card.get("id", ""))
	var category := str(card.get("category", "combat")).to_lower()
	var subtitle := rarity_name(str(card.get("rarity", "common")))
	if CardData.is_combat_card(card):
		subtitle += _t(" · %d ATK / %d HP · Grundwerte") % [int(card.get("attack", 0)), int(card.get("defense", 0))]
	elif category == "event":
		subtitle += _t(" · Ereigniskarte · nur im Kampf")
	else:
		subtitle += _t(" · Sonderkarte") + (_t(" · einmalig") if CardData.is_unique_unlock(card) else "")
	var paragraphs: Array[String] = []
	var description := str(card.get("description", "")).strip_edges()
	if not description.is_empty():
		paragraphs.append(_t(description))
	var flavor := str(card.get("flavor_text", "")).strip_edges()
	if not flavor.is_empty():
		paragraphs.append(_t(flavor))
	if card.get("permanent_upgrade", false):
		subtitle += _t(" · dauerhaft")
	if CardData.is_combat_card(card):
		var effects := CardData.get_active_effects(card)
		for effect: Dictionary in effects:
			var resolved := EffectPresentation.resolve_defaults(effect)
			paragraphs.append("%s: %s" % [_t(EffectPresentation.get_title(resolved)), effect_description(resolved, true)])
		if effects.is_empty():
			paragraphs.append(_t("Keine angeborenen Kampfeffekte."))
		var raw_effects: Variant = card.get("effects", [])
		if raw_effects is Array and raw_effects.size() > CardData.MAX_EFFECTS_PER_CARD:
			paragraphs.append(_t("Es gelten höchstens %d aktive Effekte; hier stehen die ersten %d.") % [CardData.MAX_EFFECTS_PER_CARD, CardData.MAX_EFFECTS_PER_CARD])
	if id == "eg":
		paragraphs.append(_t(EGG_RULE))
	elif id == "chick":
		paragraphs.append(_t(CHICK_RULE))
	elif id == "chicken":
		paragraphs.append(_t("Entsteht auch, wenn ein Chick fünf volle Runden auf dem Tisch überlebt. Dieses Huhn ersetzt das Küken mit frischen Grundwerten und Grundeffekten, ohne Upgrades, Holo oder übernommene Zustände. Es gehört nur zum laufenden Kampf; es wird keine Karte nachgezogen oder zur Sammlung hinzugefügt."))
	if category == "event":
		paragraphs.append(_t(EVENT_AVAILABILITY))
		paragraphs.append(_event_extra(card))
	var result := _entry(("event:" if match_event else "card:") + id, _t(str(card.get("name", id))), subtitle, "\n\n".join(paragraphs))
	result["card_data"] = card.duplicate(true)
	return result


static func _event_extra(card: Dictionary) -> String:
	match str(card.get("id", "")):
		"steel":
			return _t("Die gestohlene Karte behält ihren aktuellen Kampfzustand. Das ist kein Tod: Ein gestohlenes Egg schlüpft nicht.") + " " + _t("Ein Chick behält seinen Wachstumsfortschritt; im Nachziehstapel pausiert sein Wachstum.")
		"switch":
			return _t("Beide Nachziehstapel müssen mindestens eine Karte enthalten. Die Karten auf dem Tisch bleiben liegen.")
		"block":
			return _t("Die Dauer sinkt am Ende der Züge des betroffenen Besitzers. Erneutes Blockieren verkürzt eine längere bestehende Sperre nicht.")
		"strength_120", "strength_150", "strength_200":
			return _t("Aktueller Angriff, aktuelle HP und maximale HP werden getrennt aufgerundet. Bereits erlittener Schaden wird nicht vollständig geheilt.")
	return _t("Optional vor deinem Angriff spielbar; höchstens eine Ereigniskarte pro Zug.")


static func _effect_entries(cards: Array[Dictionary]) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var known_variants := {}
	var catalog := EffectDatabase.get_all_effects()
	for index in range(catalog.size()):
		var effect := EffectPresentation.resolve_defaults(catalog[index])
		entries.append(_effect_entry(effect, "effect:catalog:%d:%s" % [index, str(effect.get("type", ""))], _t("Effektkatalog")))
		known_variants[_effect_signature(effect)] = true
	for card: Dictionary in cards:
		var raw_effects: Variant = card.get("effects", [])
		if not raw_effects is Array:
			continue
		for raw: Variant in raw_effects:
			if not raw is Dictionary or str(raw.get("type", "")).is_empty():
				continue
			var effect := EffectPresentation.resolve_defaults(raw)
			var signature := _effect_signature(effect)
			if known_variants.has(signature):
				continue
			known_variants[signature] = true
			entries.append(_effect_entry(effect, "effect:card:" + signature, _t("Kartenvariante · ") + _t(str(card.get("name", card.get("id", ""))))))
	return entries


static func _effect_signature(effect: Dictionary) -> String:
	var parts: Array[String] = [str(effect.get("type", "")).to_lower()]
	for key: String in EffectPresentation.VARIANT_KEYS:
		if effect.has(key):
			parts.append("%s=%s" % [key, String.num(float(effect[key]), 6) if effect[key] is float or effect[key] is int else str(effect[key])])
	return "|".join(parts)


static func _effect_entry(effect: Dictionary, id: String, source: String) -> Dictionary:
	var badge := EffectPresentation.get_value_badge(effect)
	var result := _entry(id, _t(EffectPresentation.get_title(effect)), "%s · %s" % [rarity_name(str(effect.get("rarity", "common"))), badge], effect_description(effect) + "\n\n" + source)
	result["icon_path"] = EffectPresentation.get_icon_path(effect)
	result["effect_data"] = effect.duplicate(true)
	return result


static func effect_description(effect: Dictionary, compact: bool = false) -> String:
	var rules := EffectPresentation.get_combat_description(effect, compact)
	return rules if not rules.is_empty() else EffectPresentation.get_description(effect)

static func _number(value: float, decimals: int = 2) -> String:
	var text := str(int(round(value))) if is_equal_approx(value, round(value)) else String.num(value, maxi(decimals, 4) if absf(value) < 0.01 else decimals)
	return text if TranslationServer.get_locale().begins_with("en") else text.replace(".", ",")


static func _configured_modifier(card_id: String, key: String) -> float:
	# Catalog values only: the journal must not depend on ownership or mutate
	# a profile when documenting future permanent upgrades.
	var modifiers: Dictionary = CardDatabase.get_card(card_id).get("upgrade_modifiers", {})
	return float(modifiers.get(key, 0.0))


static func _boost_tier_summary(prefix: String) -> String:
	var tiers: Array[String] = []
	for tier in range(1, 5):
		tiers.append("+%s%%" % _number((_configured_modifier("%s_boost_%d" % [prefix, tier], prefix + "_multiplier") - 1.0) * 100.0))
	return " / ".join(tiers)


static func _mechanic_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	entries.append(_entry("combat", _t("Angriff & Gegenschlag"), _t("Ein Zug am Tisch"), _t("Wähle eine eigene Karte, dann ein gegnerisches Ziel. Optional darfst du vorher eine Ereigniskarte spielen. Beim ersten Treffer schlägt das Ziel mit seinem Angriffswert zurück, auch wenn es dabei stirbt. Eine durch Block gesperrte Karte kontert nicht. Danach wechselt der Zug; Mehrfachschläge und Angriffsketten werden vorher abgewickelt.")))
	entries.append(_entry("replacements", _t("Tote Karten & Nachziehen"), _t("Fünf Plätze pro Seite"), _t("Jede Seite hat bis zu fünf Karten auf dem Tisch. Eine zerstörte Karte gibt ihren Platz frei; dort erscheint die nächste Karte ihres Nachziehstapels. Ein leerer Stapel lässt den Platz leer. Der Kampf ist verloren, sobald weder Tischkarten noch Nachziehkarten übrig sind. Sind beide Seiten leer, ist es unentschieden. Ein zerstörtes Ei hinterlässt mit 25 % Wahrscheinlichkeit ein Küken, statt nachzuziehen.")))
	entries.append(_entry("egg_chicken", _t("Vom Ei zum Huhn"), _t("Schlüpfen & fünf Runden Wachstum"), _t(EGG_RULE) + _t(" Ein erfolgreich geschlüpftes Küken kann dich auch beim letzten Ei im Kampf halten. Last Stand oder Grave Return müssen zuerst verbraucht sein, sofern sie den tödlichen Treffer abfangen.") + "\n\n" + _t(CHICK_RULE)))
	entries.append(_entry("collection_deck", _t("Sammlung & Kampfdeck"), _t("%d Karten im Deck") % DeckManager.MAX_DECK_SIZE, _t("Die Sammlung bewahrt deine erhaltenen Exemplare. Das Kampfdeck enthält höchstens %d eigene Kampfkarten; zusätzliche Kopien einer Sorte benötigen zusätzliche Exemplare. Sonder- und Ereigniskarten gehören nicht hinein. Das Deck merkt sich die gewählten Exemplare, einschließlich Holo. Kämpfe verbrauchen deine Sammlungskarten nicht dauerhaft.") % DeckManager.MAX_DECK_SIZE))
	entries.append(_entry("starting_hand", _t("Deine Starthand"), _t("Freischaltungen I bis V"), _t("Die Sonderkarten Starthand I–V schalten nacheinander bis zu %d feste Startplätze frei. Eine spätere Stufe ersetzt keine fehlende frühere. Weise einem freien Startplatz ein bestimmtes Deckexemplar zu. Diese Karten beginnen am gewählten Platz; die übrige Auswahl wird gemischt. Du brauchst jede Freischaltung nur einmal.") % DeckManager.MAX_STARTING_HAND_SIZE))
	entries.append(_entry("active_effects", _t("Effekte & Zustände"), _t("Höchstens %d aktive Effekte") % CardData.MAX_EFFECTS_PER_CARD, _t("Eine Karte nutzt höchstens %d aktive Effekte. Ausgangseffekte und gekaufte Effekte teilen diese Plätze. HP, Fluch, Gift, Block und verbrauchte Schutzfähigkeiten gehören zum aktuellen Kampfzustand. Heilung endet normalerweise bei den maximalen HP.") % CardData.MAX_EFFECTS_PER_CARD))
	entries.append(_entry("turn_start", _t("Beginn & Ende eines Zuges"), _t("Heilung, Gift und Block"), _t("Zu Beginn deiner Seite werden Regeneration, Nachbarheilung und anschließend Gift ausgewertet. Gift zählt dabei einen eigenen Zug herunter. Eine Block-Sperre sinkt am Ende des Zuges ihres Besitzers. Sind alle eigenen Angreifer blockiert, kannst du den Zug über die angezeigte Schaltfläche beenden. Stun wird erst beim nächsten gewählten Angriff verbraucht.")))
	entries.append(_entry("events", _t("Ereigniskarten"), _t("Gemeinsamer Stapel mit %d Karten") % EventDeck.DECK_SIZE, _t(EVENT_AVAILABILITY) + "\n\n" + (_t("Jeder Spieler erhält zu Beginn jedes Matches %d zufällige Ereigniskarten, die bereits vor seinem ersten Angriff spielbar sind.") % EventDeck.STARTING_HAND_SIZE) + "\n\n" + _t("Draw On Kill zieht aus einem gemeinsamen Ereignisstapel. Normales Nachziehen gibt keine Ereigniskarte. Du darfst vor deinem Angriff höchstens ein Ereignis spielen; weitere Karten bleiben auf deiner Hand. Ist der Stapel leer, werden nur bereits gespielte Ereignisse neu gemischt. Ereignisse gehören zum Match, nicht zur dauerhaften Sammlung.")))
	entries.append(_entry("event_steel", _t("Steel: Karten stehlen"), _t("Verlegen statt zerstören"), _t("Steel nimmt eine gegnerische Tischkarte und mischt sie in deinen Nachziehstapel. Sie behält ihre Identität, aktuellen HP, veränderten Werte und verbrauchten Schutzfähigkeiten. Der Gegner zieht nach, wenn sein Stapel noch Karten enthält. Das Stehlen zählt nicht als Tod und löst weder einen Kill-Effekt noch das Schlüpfen eines Eis aus.") + " " + _t("Ein Chick behält seinen Wachstumsfortschritt; im Nachziehstapel pausiert sein Wachstum.")))
	entries.append(_entry("event_choices", _t("Switch, Block & Stärke"), _t("Ereignisse vor dem Angriff"), _t("Switch tauscht je eine zufällige Karte aus beiden Nachziehstapeln; beide Stapel müssen gefüllt sein. Block sperrt ein gegnerisches Ziel für zwei eigene Züge gegen Angriffe und Gegenschläge. Stärke ×1,2 / ×1,5 / ×2 multipliziert Angriff, aktuelle HP und maximale HP einer eigenen Karte, jeweils aufgerundet.")))
	var rarities: Array[String] = []
	for rarity: String in RarityEffectsData.RARITY_ORDER:
		rarities.append(rarity_name(rarity))
	entries.append(_entry("rarities", _t("Die Seltenheiten"), _t("Acht Stufen"), " → ".join(rarities) + _t(".\n\nPacks nutzen je nach Sorte unterschiedliche Gewichte für diese Stufen. Seltenheit und Holo sind getrennt: Auch eine gewöhnliche Karte kann Holo sein. Das Journal zeigt Grundwerte und angeborene Effekte aller Karten, unabhängig von deinem Besitz.")))
	entries.append(_entry("secret_rarity", _t("Secret-Karten"), _t("Besondere Funde · Regenbogenrand"), _t("Secret steht über Exotisch. Diese Karten tragen einen ständig umlaufenden Regenbogenrand. Du erhältst sie durch besondere Entdeckungen oder Belohnungen, nicht aus Packs. Die Schmiede endet bei Exotisch; Secret-Karten können nicht verschmolzen werden.")))
	# Document the authored reward catalog, independently of owned unlocks,
	# luck upgrades or developer filters. Unavailable rarities have no pack rate.
	var reward_catalog := CardDatabase.get_all_cards().filter(func(card: Dictionary) -> bool:
		return CardDatabase._is_random_reward(card) and float(card.get("reward_weight", 1.0)) > 0.0)
	for pack_id: String in PackDefinition.PACK_TYPES:
		var pack: Dictionary = PackDefinition.PACK_TYPES[pack_id]
		var weights := CardDatabase._get_unfiltered_reward_rarity_weights(reward_catalog, pack.get("rarity_weights", {}), 0.0)
		var rates: Array[String] = []
		for rarity: String in RarityEffectsData.RARITY_ORDER:
			if float(weights.get(rarity, 0.0)) > 0.0:
				rates.append("%s %s" % [rarity_name(rarity), _number(float(weights[rarity]), 3)])
		entries.append(_entry("pack:" + pack_id, _t(str(pack.get("name", pack_id))), _t("%d Soul Coins · %d Karten · ab Level %d") % [int(pack["cost"]), int(pack["card_count"]), int(pack["minimum_level"])], _t("Ein Pack enthält %d Karten und kostet %d Soul Coins. Verfügbar ab Spielerlevel %d.\n\nSeltenheitsgewichte: %s.\n\nBei einer nicht verfügbaren Stufe wird aus den übrigen erhältlichen Karten gezogen. Geheimfunde sind aus zufälligen Packbelohnungen ausgeschlossen.") % [int(pack["card_count"]), int(pack["cost"]), int(pack["minimum_level"]), "; ".join(rates)]))
	entries.append(_entry("pack_quantity", _t("Mehrere Packs kaufen"), _t("Menge und Gesamtkosten"), _t("Mit + und − wählst du die Packmenge bis zu deinem bezahlbaren Maximum. Der Gesamtpreis ist Stückpreis × Menge. Die Packs werden nacheinander geöffnet. Eingesammelte Karten behalten ihr bereits gewürfeltes Exemplar; wiederholtes Einsammeln würfelt keine neue Karte. Eine abgebrochene, noch ungeöffnete Restmenge wird zurückerstattet.")))
	var reward_lines: Array[String] = []
	for outcome: String in ["win", "draw", "loss"]:
		reward_lines.append(_t("%s: %d XP und %d Soul Coins") % [{"win": _t("Sieg"), "draw": _t("Unentschieden"), "loss": _t("Niederlage")}[outcome], GameCurrency.get_match_xp(outcome), GameCurrency.get_match_coins(outcome)])
	entries.append(_entry("match_rewards", _t("Kampfbelohnungen"), _t("Soul Coins & Erfahrung"), "\n".join(reward_lines) + _t(".\n\nEin Match zahlt sein Ergebnis einmal aus. Zuschauer erhalten keine Kampfbelohnung. Soul Coins bezahlst du für Packs, Upgrades und Slot-Einsätze; die Schmiede verlangt keine zusätzlichen Münzen.")))
	var difficulty_rewards: Array[String] = []
	for difficulty: String in ["easy", "normal", "hard", "insane"]:
		var difficulty_name := _t({"easy": "Easy", "normal": "Normal", "hard": "Hard", "insane": "Insane"}[difficulty])
		difficulty_rewards.append(_t("%s: %d XP · %s Soul Coins") % [difficulty_name, GameCurrency.get_match_xp("win", difficulty), GameCurrency.format_coins(GameCurrency.get_match_coins("win", difficulty), true)])
	entries.append(_entry("difficulty_rewards", _t("Schwierigkeit & Belohnung"), _t("Grundbelohnung bei einem Sieg"), "\n".join(difficulty_rewards) + "\n\n" + _t("Leicht zahlt 0,5×, Normal 1×, Schwer 1,5× und Wahnsinnig 3× Münzen und XP. Das gilt auch für Unentschieden und Niederlagen; XP werden auf ganze Punkte gerundet. Permanente Boni kommen danach hinzu. Online-Kämpfe verwenden Normal. Die gewählte Stufe gilt für den gesamten Kampf.")))
	entries.append(_entry("player_levels", _t("Spielerlevel"), _t("Mehr XP, zusätzliche Münzen"), _t("Start: Level 1 mit %d Soul Coins. Für das nächste Level brauchst du %d + (aktuelles Level − 1) × %d XP. Überschüssige XP bleiben erhalten. Level 2 bringt %d zusätzliche Soul Coins; jede folgende Stufe erhöht diesen Bonus um %d. GOD PACKS werden ab Level %d verfügbar.") % [GameCurrency.STARTING_COINS, GameCurrency.BASE_XP_REQUIRED, GameCurrency.XP_PER_LEVEL, GameCurrency.BASE_LEVEL_BONUS, GameCurrency.COINS_PER_LEVEL, PackDefinition.get_minimum_level("god")]))
	entries.append(_entry("clicker", _t("Clicker, Golden & Auto Clicker"), _t("Kleine Beträge sammeln"), _t("Clicker schaltet %s SoulCoins pro manuellem Klick frei. Jede Clicker-Upgrade-Kopie bringt weitere %s, jeder Goldene Clicker weitere %s SoulCoins pro Klick. Auto-Clicker erzeugt %s SoulCoins pro Sekunde im laufenden Spiel; es gibt keine Offline-Einnahmen. Golden und Auto benötigen zuerst Clicker. Die SoulCoin-Boosts gelten auch für diese Einnahmen.") % [_number(GameCurrency.BASE_MANUAL_CLICK_REWARD), _number(GameCurrency.CLICKER_UPGRADE_REWARD), _number(_configured_modifier("golden_clicker", "manual_click_bonus")), _number(_configured_modifier("auto_clicker", "auto_click_coins_per_second"))]))
	entries.append(_entry("type_upgrades", _t("Kartenwerte verbessern"), _t("Gilt für die ganze Kartensorte"), _t("An der Upgrade-Maschine kaufst du +1 Angriff oder +1 Leben. Der erste Wertkauf einer Sorte kostet 5 Soul Coins; jeder weitere Wertkauf dieser Sorte erhöht den nächsten Preis um %d. Angriff und Leben teilen diesen Zähler. Die Verbesserungen gelten für alle Exemplare der Sorte und bleiben dauerhaft gespeichert.") % CardUpgradeManager.STAT_UPGRADE_COST_STEP))
	entries.append(_entry("effect_upgrades", _t("Effekte kaufen & entfernen"), _t("Freie Effektplätze"), _t("Ein Effektwurf an der Upgrade-Maschine kostet 12 Soul Coins und benötigt einen freien Platz. Ein Wurf kann ohne Effekt enden; die Kosten fallen trotzdem an. Es wird höchstens ein gewürfelter Effekt hinzugefügt. Angeborene oder gekaufte Effekte lassen sich kostenlos entfernen. Die Änderung gilt für die Kartensorte; es gibt keine Erstattung für entfernte Effekte.")))
	entries.append(_entry("holo", _t("Holo-Exemplare"), _t("1 von %d normalen Erwerbswürfen") % CardData.HOLO_ROLL_SIDES, _t("Beim normalen Erhalt einer Karte wird unabhängig eine Holo-Chance von %s%% gewürfelt. Holo erzeugt einen schimmernden Überzug auf Kartenfläche und Bild. Es verändert weder Angriff, HP noch Seltenheit. Das Merkmal gehört zum einzelnen Exemplar und bleibt beim Speichern und im Kampf erhalten. Geschlüpfte Küken und durch Wachstum entstandene Hühner erhalten weder Holo noch einen Holo-Wurf.") % _number(100.0 / CardData.HOLO_ROLL_SIDES)))
	var fusion_counts: Array[int] = [CollectionManager.FUSION_REQUIRED_CARDS, int(_configured_modifier("fusion_upgrade_1", "fusion_requirement")), int(_configured_modifier("fusion_upgrade_2", "fusion_requirement"))]
	entries.append(_entry("forge", _t("Die Kartenschmiede"), _t("%d / %d / %d Karten werden eine") % fusion_counts, _t("Die Schmiede benötigt zunächst %d Exemplare derselben Seltenheit; verschiedene Kartennamen sind erlaubt. Fusionsupgrade I senkt die Anzahl auf %d, Fusionsupgrade II auf %d und benötigt Stufe I. Nur die höchste Stufe zählt. Die gewählten Exemplare werden gegen eine zufällige Kampfkarte genau einer Stufe höher getauscht, mit Stufe 1 und neu gewürfelten Effekten und Holo. Es kostet keine zusätzlichen SoulCoins.") % fusion_counts))
	entries.append(_entry("forge_protection", _t("Geschützte Schmiedekarten"), _t("Dein Deck bleibt vollständig"), _t("Karten im gespeicherten Kampfdeck, Sonderkarten, Ereignisse, Geheimfunde und exotische Karten lassen sich nicht verschmelzen. Ein Deckexemplar muss zuerst aus dem Deck genommen werden. Auswahl über mehrere Seiten ist möglich; nur die gewählten Exemplare werden verbraucht. Scheitert das Speichern, bleiben alle gewählten Karten erhalten. Bereits gekaufte Verbesserungen der Kartensorte bleiben bestehen.")))
	var bets: Array[String] = []
	for cents: int in SoulSlotMachine.BETS:
		bets.append(_number(cents / float(GameCurrency.CENTS_PER_COIN)))
	entries.append(_entry("slot_bets", _t("Slotmaschine bedienen"), _t("Einsatz wählen, BET, SPIN"), _t("Einsätze: %s Soul Coins. Mit +/− wählst du den Betrag und bestätigst ihn mit BET. Erst SPIN zieht den Einsatz ab und startet die Walzen. Während des Drehens ist kein weiterer Einsatz möglich. Das Ergebnis einer laufenden Drehung bleibt erhalten.") % ", ".join(bets)))
	var payouts: Array[String] = []
	for index in range(SoulSlotMachine.MULTIPLIERS.size()):
		payouts.append("%s / %s: ×%d" % [_t(SoulSlotMachine.COLOR_NAMES[index]), _t(SoulSlotMachine.SYMBOL_NAMES[index]), SoulSlotMachine.MULTIPLIERS[index]])
	entries.append(_entry("slot_payouts", _t("Slot-Auszahlungen"), _t("Drei gleiche Symbole"), "\n".join(payouts) + _t(".\n\nNur drei gleiche Symbole zahlen aus. Gemischte Reihen zahlen 0. Auszahlung = Einsatz × Multiplikator; der Einsatz wurde beim Start bereits abgezogen. Die Symbole stehen hier für Gewinnklassen und verleihen keine Kampfeffekte.")))
	entries.append(_entry("permanent_upgrades", _t("Permanente Fortschritte"), _t("Freischaltungen statt Kampfkarten"), _t("Permanente Sonderkarten wirken ab ihrem Erhalt und bleiben gespeichert. Sie benötigen keinen Deckplatz und können weder kämpfen noch verschmolzen werden. Karten mit Voraussetzungen erscheinen erst nach der vorherigen Freischaltung. Einmalige Karten werden nicht erneut vergeben; stapelbare Upgrades zählen pro Kopie.")))
	entries.append(_entry("lucky_rewards", _t("Glück & Händlerlizenz"), _t("Bessere Funde, günstigere Preise"), _t("Die Glücksmünze erhöht die relative Chance auf Selten oder höher um %s%%. Dafür sinkt vor allem Gewöhnlich; garantierte Seltenheiten bleiben gleich. Die Glücksmünze selbst ist besonders selten. Die Händlerlizenz senkt normale Shop-Preise um %s%%, einschließlich Packs und Karten-Upgrades.") % [_number(_configured_modifier("lucky_coin", "lucky_coin_bonus") * 100.0), _number(_configured_modifier("dealer_license", "shop_discount") * 100.0)]))
	entries.append(_entry("income_boosts", _t("SoulCoins & XP-Boosts"), _t("Nur die höchste Stufe zählt"), _t("SoulCoin-Stufen: %s. XP-Stufen: %s. Jede Stufe benötigt ihre Vorgängerstufe. Es gilt jeweils der höchste Gesamtbonus; die Stufen werden nicht addiert. SoulCoin-Boosts erhöhen normale Einnahmen, XP-Boosts reguläre Erfahrung. Kleine Bruchteile bleiben bis zum nächsten ganzen Cent bzw. XP-Punkt gespeichert. Rückerstattungen erhalten keinen Bonus.") % [_boost_tier_summary("soulcoin"), _boost_tier_summary("xp")]))
	return entries



static func _t(source: String) -> String:
	return Localization.text(source)
