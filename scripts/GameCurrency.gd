extends Node

signal coins_changed(coins: float)
signal progression_changed(level: int, xp: int, xp_required: int)
signal level_up(level: int, coins_bonus: float)
signal basement_cat_choice_changed(choice: String)
signal cat_clicker_changed(active: bool)
signal cat_clicker_frame_changed(frame: int)
signal cat_clicker_clicked

const STARTING_COINS := 20
const CENTS_PER_COIN := 100
const BASE_XP_REQUIRED := 100
const XP_PER_LEVEL := 50
const BASE_LEVEL_BONUS := 25
const COINS_PER_LEVEL := 10
const AUTO_CLICK_INTERVAL := 1.0
const BASE_MANUAL_CLICK_REWARD := 0.02
const CLICKER_UPGRADE_REWARD := 0.01
const REWARD_ROUNDING_EPSILON := 0.00000001
const BASEMENT_CAT_REWARD_COINS := 1000
const CAT_CLICKER_FRAMES := 3
const CAT_CLICKER_FPS := 3.0

var _coin_cents: int = STARTING_COINS * CENTS_PER_COIN
# Keep the public amount in Soul Coins; arithmetic and persistence use whole
# hundredths so repeated 0.01/0.02 rewards cannot accumulate rounding errors.
var coins: float:
	get:
		return float(_coin_cents) / CENTS_PER_COIN
	set(value):
		_coin_cents = _to_coin_cents(value)
var level: int = 1
var xp: int = 0
# Keep fractions that have not yet reached a cent / XP point. A 2% boost must
# also benefit one-cent clicks and one-point XP rewards across save/load.
var _coin_reward_remainder := 0.0
var _xp_reward_remainder := 0.0
var _auto_click_elapsed := 0.0
var _auto_click_rate := 0.0
# Override before loading to use an isolated profile (for example in tests).
var _save_path_override := ""
var save_path: String:
	get:
		return _save_path_override if not _save_path_override.is_empty() else SaveSlots.get_save_path("currency.cfg")
	set(value):
		_save_path_override = value
var _slot_spin_pending := false
var _pending_slot_payout_cents := 0
var _slot_transaction_active := false
var _queued_pack_count := 0
var _queued_pack_unit_cents := 0
var _pack_reservation_id := 0
var _pack_transaction_active := false
var _black_market_transaction: Dictionary = {}
var _black_market_transaction_active := false
var _basement_cat_choice := ""
var _basement_cat_transaction_active := false
var _basement_cat_left := false
var _cat_clicker_active := false
var _cat_clicker_frame := 0
var _cat_clicker_frame_elapsed := 0.0
var _cat_clicker_advancing := false

func _ready() -> void:
	load_currency()
	CollectionManager.collection_changed.connect(_on_collection_changed)


func _process(delta: float) -> void:
	advance_auto_clicker(delta)
	advance_cat_clicker(delta)


func _on_collection_changed(_card_ids: Array[String]) -> void:
	var current_rate := CollectionManager.get_auto_click_rate()
	if current_rate <= 0.0 or _auto_click_rate <= 0.0:
		_auto_click_elapsed = 0.0
	_auto_click_rate = current_rate
	# SaveSlots suppresses signals while loading managers, then emits one final
	# collection update. Publish the loaded state even if the cache is current.
	_refresh_cat_clicker(true)


func is_cat_clicker_active() -> bool:
	return _basement_cat_choice == "spared" and _basement_cat_left and CollectionManager.is_clicker_unlocked()


func has_basement_cat_left() -> bool:
	return _basement_cat_left


func mark_basement_cat_left() -> bool:
	# Save the departure even before Clicker is unlocked. A later unlock can
	# then move the cat to the button without requiring another basement visit.
	if _basement_cat_transaction_active or _basement_cat_choice != "spared" or _basement_cat_left:
		return false
	_basement_cat_transaction_active = true
	_basement_cat_left = true
	if not save():
		_basement_cat_left = false
		_basement_cat_transaction_active = false
		return false
	_refresh_cat_clicker()
	_basement_cat_transaction_active = false
	return true


func get_cat_clicker_frame() -> int:
	return _cat_clicker_frame


func _refresh_cat_clicker(force_emit: bool = false) -> void:
	var active := is_cat_clicker_active()
	if active == _cat_clicker_active:
		if force_emit:
			cat_clicker_changed.emit(active)
		return
	_cat_clicker_active = active
	_cat_clicker_frame_elapsed = 0.0
	if _cat_clicker_frame != 0:
		_cat_clicker_frame = 0
		cat_clicker_frame_changed.emit(_cat_clicker_frame)
	cat_clicker_changed.emit(active)


func advance_cat_clicker(delta: float) -> void:
	# The wallet owns this clock, so hidden or duplicate UI instances cannot
	# pause or multiply income. Nothing accrues while the game is closed.
	if not _cat_clicker_active or _cat_clicker_advancing or not is_finite(delta) or delta <= 0.0:
		return
	_cat_clicker_frame_elapsed += delta
	var frame_duration := 1.0 / CAT_CLICKER_FPS
	var steps := floori((_cat_clicker_frame_elapsed + REWARD_ROUNDING_EPSILON) / frame_duration)
	if steps <= 0:
		return
	_cat_clicker_advancing = true
	_cat_clicker_frame_elapsed = maxf(_cat_clicker_frame_elapsed - steps * frame_duration, 0.0)
	# Arrival at frame 2 (the third sprite) is the click. Count crossings, not
	# the currently displayed frame, including multiple cycles in a long frame.
	@warning_ignore("integer_division")
	var clicks: int = (_cat_clicker_frame + steps + 1) / CAT_CLICKER_FRAMES - (_cat_clicker_frame + 1) / CAT_CLICKER_FRAMES
	var next_frame := (_cat_clicker_frame + steps) % CAT_CLICKER_FRAMES
	if next_frame != _cat_clicker_frame:
		_cat_clicker_frame = next_frame
		cat_clicker_frame_changed.emit(_cat_clicker_frame)
	if clicks > 0 and _cat_clicker_active:
		# add_coins applies the Soul Coin multiplier once and preserves fractional
		# cents, exactly like the manual button and alongside the Auto Clicker.
		add_coins(get_manual_click_base_reward() * clicks)
		cat_clicker_clicked.emit()
	_cat_clicker_advancing = false


func advance_auto_clicker(delta: float) -> void:
	# Elapsed play time only: no clock timestamp is saved or recovered. Batch
	# income once per interval, rather than saving the profile every frame.
	# Ownership changes refresh the rate through collection_changed, so the
	# card collection does not need to be scanned on every rendered frame.
	if _auto_click_rate <= 0.0 or not is_finite(delta) or delta <= 0.0:
		return
	_auto_click_elapsed += delta
	var ticks := floori((_auto_click_elapsed + REWARD_ROUNDING_EPSILON) / AUTO_CLICK_INTERVAL)
	if ticks <= 0:
		return
	_auto_click_elapsed = maxf(_auto_click_elapsed - ticks * AUTO_CLICK_INTERVAL, 0.0)
	add_coins(_auto_click_rate * ticks * AUTO_CLICK_INTERVAL)


func get_manual_click_base_reward() -> float:
	if not CollectionManager.is_clicker_unlocked():
		return 0.0
	return BASE_MANUAL_CLICK_REWARD + CollectionManager.get_clicker_upgrade_count() * CLICKER_UPGRADE_REWARD + CollectionManager.get_manual_click_bonus()


func get_manual_click_reward() -> float:
	return get_manual_click_base_reward() * CollectionManager.get_soulcoin_multiplier()


func award_manual_click() -> void:
	add_coins(get_manual_click_base_reward())

func add_coins(amount: float) -> void:
	if not is_finite(amount) or amount <= 0.0:
		return
	_credit_regular_income(amount * CENTS_PER_COIN)


func add_coin_cents(amount: int) -> void:
	_credit_regular_income(float(maxi(amount, 0)))


func _credit_regular_income(base_cents: float) -> void:
	if base_cents <= 0.0:
		return
	var gained := _boosted_coin_cents(base_cents)
	_coin_cents += gained
	save()
	if gained > 0:
		coins_changed.emit(coins)


func _boosted_coin_cents(base_cents: float) -> int:
	if base_cents <= 0.0:
		return 0
	var precise := base_cents * CollectionManager.get_soulcoin_multiplier() + _coin_reward_remainder
	var gained := floori(precise + REWARD_ROUNDING_EPSILON)
	_coin_reward_remainder = maxf(precise - gained, 0.0)
	return gained


func get_shop_price(base_price: float, shop_pool: String = "normal") -> float:
	if not is_finite(base_price) or base_price < 0.0:
		return INF
	# Pool-specific discounts are composed centrally; callers pass base prices
	# once and transactions/refunds preserve that final cent-accurate amount.
	var discount := clampf(CollectionManager.get_shop_discount(shop_pool), 0.0, 1.0)
	return float(_to_coin_cents(base_price * (1.0 - discount))) / CENTS_PER_COIN

func spend_coins(amount: float) -> bool:
	if not is_finite(amount):
		return false
	if amount <= 0:
		return true
	var cost := _to_coin_cents(amount)
	if _coin_cents < cost:
		return false

	_coin_cents -= cost
	save()
	coins_changed.emit(coins)
	return true

func has_coins(amount: float) -> bool:
	return is_finite(amount) and _coin_cents >= _to_coin_cents(amount)

func get_coins() -> float:
	return coins


func get_coin_cents() -> int:
	return _coin_cents


func get_basement_cat_choice() -> String:
	return _basement_cat_choice


func resolve_basement_cat_choice(choice: String) -> Dictionary:
	var result := {"ok": false, "reason": "", "choice": _basement_cat_choice, "reward_coins": 0}
	if choice not in ["spared", "shot"]:
		result["reason"] = "invalid_choice"
		return result
	if _basement_cat_transaction_active:
		result["reason"] = "busy"
		return result
	if not _basement_cat_choice.is_empty():
		result["reason"] = "already_resolved"
		return result
	_basement_cat_transaction_active = true
	var reward := BASEMENT_CAT_REWARD_COINS if choice == "shot" else 0
	_basement_cat_choice = choice
	# The promised fixed reward and the irreversible choice share one atomic
	# currency save. Income boosts and fractional income carry never apply.
	_coin_cents += reward * CENTS_PER_COIN
	if not save():
		_coin_cents -= reward * CENTS_PER_COIN
		_basement_cat_choice = ""
		_basement_cat_transaction_active = false
		result["reason"] = "save_failed"
		return result
	result["ok"] = true
	result["choice"] = choice
	result["reward_coins"] = reward
	# Listeners see durable state; retain the guard through synchronous callbacks.
	if reward > 0:
		coins_changed.emit(coins)
	basement_cat_choice_changed.emit(choice)
	_basement_cat_transaction_active = false
	return result


func begin_black_market_purchase(transaction_id: String, price_cents: int) -> bool:
	if _black_market_transaction_active or not _black_market_transaction.is_empty() or transaction_id.is_empty() or price_cents <= 0 or _coin_cents < price_cents:
		return false
	_black_market_transaction_active = true
	_coin_cents -= price_cents
	_black_market_transaction = {"id": transaction_id, "price_cents": price_cents}
	if not save():
		_coin_cents += price_cents
		_black_market_transaction = {}
		_black_market_transaction_active = false
		return false
	_black_market_transaction_active = false
	return true


func resolve_black_market_purchase(committed: bool) -> bool:
	if _black_market_transaction_active or _black_market_transaction.is_empty():
		return false
	_black_market_transaction_active = true
	if not committed:
		# Exact refunds bypass all income multipliers. Keep the corrected amount
		# in memory even if this write fails: the old file still holds its debit
		# plus refundable transaction, so another load can recover it exactly once.
		_coin_cents += int(_black_market_transaction.get("price_cents", 0))
	_black_market_transaction = {}
	var saved := save()
	coins_changed.emit(coins)
	_black_market_transaction_active = false
	return saved


func begin_slot_spin(stake_cents: int, payout_cents: int) -> bool:
	# Bets and committed gambling payouts are transactions, not regular income.
	# Their advertised payout table, like refunds, is unaffected by boosts.
	if _slot_transaction_active or _slot_spin_pending or stake_cents <= 0 or payout_cents < 0 or _coin_cents < stake_cents:
		return false
	_slot_transaction_active = true
	_coin_cents -= stake_cents
	_slot_spin_pending = true
	_pending_slot_payout_cents = payout_cents
	# Debit and the already determined result survive together before animation.
	if not save():
		_coin_cents += stake_cents
		_slot_spin_pending = false
		_pending_slot_payout_cents = 0
		_slot_transaction_active = false
		return false
	coins_changed.emit(coins)
	_slot_transaction_active = false
	return true


func complete_slot_spin() -> bool:
	if _slot_transaction_active or not _slot_spin_pending:
		return false
	_slot_transaction_active = true
	var payout := _pending_slot_payout_cents
	_slot_spin_pending = false
	_pending_slot_payout_cents = 0
	_coin_cents += payout
	if not save():
		_coin_cents -= payout
		_slot_spin_pending = true
		_pending_slot_payout_cents = payout
		_slot_transaction_active = false
		return false
	# Keep the guard through synchronous listeners, including a zero payout.
	coins_changed.emit(coins)
	_slot_transaction_active = false
	return true


func has_pending_slot_spin() -> bool:
	return _slot_spin_pending


func begin_pack_purchase(unit_cost_cents: int, quantity: int) -> int:
	if _pack_transaction_active or _queued_pack_count > 0 or unit_cost_cents <= 0 or quantity < 1:
		return 0
	# Compare before multiplying so an invalid quantity cannot overflow the debit.
	@warning_ignore("integer_division")
	var affordable_count: int = _coin_cents / unit_cost_cents
	if quantity > affordable_count:
		return 0
	_pack_transaction_active = true
	var total_cost := unit_cost_cents * quantity
	_coin_cents -= total_cost
	# The first pack is handed over immediately, just like an individual purchase.
	# Only packs still waiting in the queue are refundable after interruption.
	_queued_pack_count = quantity - 1
	_queued_pack_unit_cents = unit_cost_cents if _queued_pack_count > 0 else 0
	if not save():
		_coin_cents += total_cost
		_queued_pack_count = 0
		_queued_pack_unit_cents = 0
		_pack_transaction_active = false
		return 0
	_pack_reservation_id += 1
	var reservation := _pack_reservation_id
	coins_changed.emit(coins)
	_pack_transaction_active = false
	return reservation


func consume_queued_pack(reservation: int) -> bool:
	if _pack_transaction_active or reservation != _pack_reservation_id or _queued_pack_count <= 0:
		return false
	_pack_transaction_active = true
	var unit_cost := _queued_pack_unit_cents
	_queued_pack_count -= 1
	if _queued_pack_count == 0:
		_queued_pack_unit_cents = 0
	if not save():
		_queued_pack_count += 1
		_queued_pack_unit_cents = unit_cost
		_pack_transaction_active = false
		return false
	_pack_transaction_active = false
	return true


func refund_queued_packs(reservation: int = 0) -> bool:
	if _pack_transaction_active or _queued_pack_count <= 0 or (reservation != 0 and reservation != _pack_reservation_id):
		return false
	_pack_transaction_active = true
	var count := _queued_pack_count
	var unit_cost := _queued_pack_unit_cents
	var refund := count * unit_cost
	_queued_pack_count = 0
	_queued_pack_unit_cents = 0
	_coin_cents += refund
	if not save():
		_coin_cents -= refund
		_queued_pack_count = count
		_queued_pack_unit_cents = unit_cost
		_pack_transaction_active = false
		return false
	coins_changed.emit(coins)
	_pack_transaction_active = false
	return true


func get_queued_pack_count(reservation: int = 0) -> int:
	return _queued_pack_count if reservation == 0 or reservation == _pack_reservation_id else 0


func format_coins(amount: float = -1.0, compact: bool = false) -> String:
	var value := coins if amount < 0.0 else amount
	if compact and is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return Localization.decimal(value)


func _to_coin_cents(amount: float) -> int:
	return maxi(roundi(amount * CENTS_PER_COIN), 0) if is_finite(amount) else 0


func get_level() -> int:
	return level


func get_xp() -> int:
	return xp


func get_xp_required() -> int:
	return BASE_XP_REQUIRED + (level - 1) * XP_PER_LEVEL


func get_level_bonus(target_level: int = -1) -> int:
	if target_level < 0:
		target_level = level + 1
	return BASE_LEVEL_BONUS + maxi(target_level - 2, 0) * COINS_PER_LEVEL


func get_level_bonus_reward(target_level: int = -1) -> float:
	return get_level_bonus(target_level) * CollectionManager.get_soulcoin_multiplier()


func get_match_reward_multiplier(difficulty: String = "normal") -> float:
	match difficulty:
		"easy": return 0.5
		"hard": return 1.5
		"insane": return 3.0
	return 1.0


func get_match_xp(outcome: String, difficulty: String = "normal") -> int:
	var base_xp := 0
	match outcome:
		"win":
			base_xp = 100
		"draw":
			base_xp = 50
		"loss":
			base_xp = 25
	return roundi(base_xp * get_match_reward_multiplier(difficulty))


func get_match_coins(outcome: String, difficulty: String = "normal") -> float:
	var base_coins := 0.0
	match outcome:
		"win":
			base_coins = 10.0
		"draw":
			base_coins = 5.0
		"loss":
			base_coins = 2.0
	return base_coins * get_match_reward_multiplier(difficulty)


func award_match(outcome: String, difficulty: String = "normal") -> Dictionary:
	return _add_rewards(get_match_xp(outcome, difficulty), get_match_coins(outcome, difficulty))


func add_xp(amount: int) -> Dictionary:
	return _add_rewards(amount, 0)


func _add_rewards(xp_amount: int, coin_amount: float) -> Dictionary:
	var gained := 0
	if xp_amount > 0:
		var precise_xp := xp_amount * CollectionManager.get_xp_multiplier() + _xp_reward_remainder
		gained = floori(precise_xp + REWARD_ROUNDING_EPSILON)
		_xp_reward_remainder = maxf(precise_xp - gained, 0.0)
	var coin_reward_cents := _boosted_coin_cents(maxf(coin_amount, 0.0) * CENTS_PER_COIN)
	var previous_level := level
	var bonus_cents := 0
	var earned_levels: Array[Dictionary] = []
	if xp_amount > 0 or coin_amount > 0:
		xp += gained
		while xp >= get_xp_required():
			xp -= get_xp_required()
			level += 1
			var level_bonus_cents := _boosted_coin_cents(get_level_bonus(level) * CENTS_PER_COIN)
			bonus_cents += level_bonus_cents
			earned_levels.append({"level": level, "coins_bonus": float(level_bonus_cents) / CENTS_PER_COIN})
		_coin_cents += coin_reward_cents + bonus_cents
		# Match coins, XP and every level bonus are saved as one transaction.
		save()
		if coin_reward_cents + bonus_cents > 0:
			coins_changed.emit(coins)
		if gained > 0:
			progression_changed.emit(level, xp, get_xp_required())
		for earned_level in earned_levels:
			level_up.emit(int(earned_level["level"]), float(earned_level["coins_bonus"]))
	return {
		"xp_awarded": gained,
		"coins_reward": float(coin_reward_cents) / CENTS_PER_COIN,
		"coins_awarded": float(coin_reward_cents + bonus_cents) / CENTS_PER_COIN,
		"old_level": previous_level,
		"new_level": level,
		"levels_gained": level - previous_level,
		"coins_bonus": float(bonus_cents) / CENTS_PER_COIN,
	}


func clear_profile_state() -> void:
	coins = STARTING_COINS
	level = 1
	xp = 0
	_coin_reward_remainder = 0.0
	_xp_reward_remainder = 0.0
	_auto_click_elapsed = 0.0
	_auto_click_rate = 0.0
	_slot_spin_pending = false
	_pending_slot_payout_cents = 0
	_slot_transaction_active = false
	_queued_pack_count = 0
	_queued_pack_unit_cents = 0
	_pack_transaction_active = false
	_black_market_transaction = {}
	_black_market_transaction_active = false
	_basement_cat_choice = ""
	_basement_cat_transaction_active = false
	_basement_cat_left = false
	_cat_clicker_frame_elapsed = 0.0
	_refresh_cat_clicker()
	# Never reuse a reservation identity while old scene callbacks can exist.
	_pack_reservation_id += 1
	if has_meta("slot_spin_visual_owner"):
		remove_meta("slot_spin_visual_owner")


func reload_profile() -> void:
	load_currency()


func reset_progression(persist: bool = true) -> void:
	clear_profile_state()
	# Resetting currency within the same slot preserves its owned clicker.
	_on_collection_changed([])
	if persist:
		save()
	coins_changed.emit(coins)
	progression_changed.emit(level, xp, get_xp_required())
	basement_cat_choice_changed.emit(_basement_cat_choice)


func save() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("currency", "coins", coins)
	cfg.set_value("currency", "coin_cents", _coin_cents)
	cfg.set_value("currency", "reward_remainder", _coin_reward_remainder)
	cfg.set_value("currency", "slot_spin_pending", _slot_spin_pending)
	cfg.set_value("currency", "slot_payout_cents", _pending_slot_payout_cents)
	cfg.set_value("currency", "queued_pack_count", _queued_pack_count)
	cfg.set_value("currency", "queued_pack_unit_cents", _queued_pack_unit_cents)
	cfg.set_value("currency", "black_market_transaction", _black_market_transaction)
	cfg.set_value("basement", "cat_choice", _basement_cat_choice)
	cfg.set_value("basement", "cat_left", _basement_cat_left)
	cfg.set_value("progression", "level", level)
	cfg.set_value("progression", "xp", xp)
	cfg.set_value("progression", "xp_reward_remainder", _xp_reward_remainder)
	var temporary_path := save_path + ".tmp"
	var error := cfg.save(temporary_path)
	if error == OK:
		error = DirAccess.rename_absolute(temporary_path, save_path)
	if error != OK:
		push_error("Could not save currency and level progress: %s" % error_string(error))
	return error == OK

func load_currency() -> void:
	clear_profile_state()
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK:
		if cfg.has_section_key("currency", "coin_cents"):
			_coin_cents = maxi(int(cfg.get_value("currency", "coin_cents", STARTING_COINS * CENTS_PER_COIN)), 0)
		else:
			# Preserve whole-coin legacy saves, including any existing fractions.
			coins = float(cfg.get_value("currency", "coins", STARTING_COINS))
		# Existing currency-only saves start at level 1 without losing any coins.
		level = maxi(int(cfg.get_value("progression", "level", 1)), 1)
		xp = clampi(int(cfg.get_value("progression", "xp", 0)), 0, get_xp_required() - 1)
		_coin_reward_remainder = _load_reward_remainder(cfg, "currency", "reward_remainder")
		_xp_reward_remainder = _load_reward_remainder(cfg, "progression", "xp_reward_remainder")
		_slot_spin_pending = bool(cfg.get_value("currency", "slot_spin_pending", false))
		_pending_slot_payout_cents = maxi(int(cfg.get_value("currency", "slot_payout_cents", 0)), 0) if _slot_spin_pending else 0
		_queued_pack_count = maxi(int(cfg.get_value("currency", "queued_pack_count", 0)), 0)
		_queued_pack_unit_cents = maxi(int(cfg.get_value("currency", "queued_pack_unit_cents", 0)), 0) if _queued_pack_count > 0 else 0
		var market_transaction: Variant = cfg.get_value("currency", "black_market_transaction", {})
		if market_transaction is Dictionary and not str(market_transaction.get("id", "")).is_empty() and int(market_transaction.get("price_cents", 0)) > 0:
			_black_market_transaction = market_transaction.duplicate(true)
		var cat_choice := str(cfg.get_value("basement", "cat_choice", ""))
		_basement_cat_choice = cat_choice if cat_choice in ["spared", "shot"] else ""
		_basement_cat_left = _basement_cat_choice == "spared" and cfg.get_value("basement", "cat_left", false) == true

	# Recovery pays the committed result and clears it in the same save, so a
	# second load cannot pay again. Older profiles have no pending transaction.
	var slot_recovered := complete_slot_spin()
	var packs_recovered := refund_queued_packs()
	var market_recovered := false
	if not _black_market_transaction.is_empty():
		market_recovered = resolve_black_market_purchase(CollectionManager.has_black_market_receipt(str(_black_market_transaction["id"])))
	if not slot_recovered and not packs_recovered and not market_recovered:
		coins_changed.emit(coins)
	progression_changed.emit(level, xp, get_xp_required())
	basement_cat_choice_changed.emit(_basement_cat_choice)
	_on_collection_changed([])


func _load_reward_remainder(cfg: ConfigFile, section: String, key: String) -> float:
	var value := float(cfg.get_value(section, key, 0.0))
	return clampf(value, 0.0, 1.0 - REWARD_ROUNDING_EPSILON) if is_finite(value) else 0.0
