extends RefCounted

# Fixed local fixtures and mutable state shared by the running scene.
class Port:
    extends RefCounted
    var id: String
    var position: Vector2
    func _init(port_id: String, at: Vector2) -> void:
        id = port_id
        position = at

class Good:
    extends RefCounted
    var id: String
    var name: String
    func _init(good_id: String, display_name: String) -> void:
        id = good_id
        name = display_name

class Cargo:
    extends RefCounted
    var quantities: Dictionary = {}
    func quantity(good_id: String) -> int:
        return int(quantities.get(good_id, 0))
    func total() -> int:
        var count: int = 0
        for amount in quantities.values():
            count += int(amount)
        return count

class Ship:
    extends RefCounted
    var id: String = "player_ship"
    var capacity: int = 20
    var speed: float = 200.0
    var position: Vector2 = Vector2(450, 420)
    var cargo: Cargo = Cargo.new()

class PlayerWallet:
    extends RefCounted
    var coins: int = 100

class Market:
    extends RefCounted
    var port_id: String
    var inventory: Dictionary
    var prices: Dictionary
    var initial_inventory: Dictionary
    var base_prices: Dictionary
    var minimum_prices: Dictionary = {}
    var maximum_prices: Dictionary = {}
    func _init(location: String, stock: Dictionary, unit_prices: Dictionary) -> void:
        port_id = location
        inventory = stock.duplicate(true)
        initial_inventory = stock.duplicate(true)
        base_prices = unit_prices.duplicate(true)
        prices = unit_prices.duplicate(true)
        for good_id in base_prices:
            minimum_prices[good_id] = 1
            maximum_prices[good_id] = int(base_prices[good_id]) * 2
    func price_at_stock(good_id: String, stock: int) -> int:
        var scarcity: int = int(initial_inventory[good_id]) - stock
        return clampi(int(base_prices[good_id]) + scarcity, int(minimum_prices[good_id]), int(maximum_prices[good_id]))
    func refresh_price(good_id: String) -> void:
        prices[good_id] = price_at_stock(good_id, int(inventory[good_id]))
    # Selling receives the quote after adding supply, preventing round-trip profit.
    func trade_total(good_id: String, quantity: int, purchasing: bool) -> int:
        var stock: int = int(inventory[good_id])
        var total: int = 0
        for index in range(quantity):
            var unit_stock: int = stock - index if purchasing else stock + index + 1
            total += price_at_stock(good_id, unit_stock)
        return total

class Contract:
    extends RefCounted
    var id: String = "deliver_sugar"
    var destination_id: String = "Port B"
    var good_id: String = "sugar"
    var quantity: int = 3
    var reward: int = 30
    var completed: bool = false

class Voyage:
    extends RefCounted
    var origin_id: String = ""
    var destination_id: String = ""
    var distance: float = 0.0
    var duration: float = 0.0
    var progress: float = 0.0
    var remaining_time: float = 0.0
    var active: bool = false
    var provisions_consumed: int = 0

const PROVISION_PRICE: int = 2
const DISTANCE_PER_PROVISION: float = 100.0
# Three port-to-port legs of starter supplies support the repeatable delivery demo.
# Supplies are separate from trade cargo and never occupy the commodity hold.
var provisions: int = 12
var departure_feedback: String = "Choose a port to see required provisions."
var ports: Dictionary = {}
var goods: Dictionary = {}
var markets: Dictionary = {}
var contracts: Dictionary = {}
var ship: Ship
var cargo: Cargo
var wallet: PlayerWallet
var voyage: Voyage
var docked_port_id: String = ""

func _init() -> void:
    ports = {
        "Port A": Port.new("Port A", Vector2(290, 240)),
        "Port B": Port.new("Port B", Vector2(590, 350))
    }
    goods = {
        "sugar": Good.new("sugar", "Sugar"),
        "rum": Good.new("rum", "Rum"),
        "coffee": Good.new("coffee", "Coffee")
    }
    markets = {
        "Port A": Market.new("Port A", {"sugar": 20, "rum": 10, "coffee": 15}, {"sugar": 5, "rum": 10, "coffee": 12}),
        "Port B": Market.new("Port B", {"sugar": 10, "rum": 20, "coffee": 8}, {"sugar": 8, "rum": 7, "coffee": 18})
    }
    ship = Ship.new()
    cargo = ship.cargo
    wallet = PlayerWallet.new()
    voyage = Voyage.new()
    var contract: Contract = Contract.new()
    contracts[contract.id] = contract

func can_trade() -> bool:
    return not voyage.active and markets.has(docked_port_id)

func required_provisions(destination_id: String) -> int:
    if not ports.has(destination_id) or destination_id == docked_port_id:
        return 0
    var destination: Port = ports[destination_id]
    return ceili(ship.position.distance_to(destination.position) / DISTANCE_PER_PROVISION)

func buy_provisions(quantity: int) -> bool:
    if not can_trade() or quantity <= 0:
        return false
    # Divide before multiplying so oversized requests reject without overflow.
    if quantity > wallet.coins / PROVISION_PRICE:
        return false
    wallet.coins -= quantity * PROVISION_PRICE
    provisions += quantity
    return true

# Validate the entire marginal-price batch before changing any state.
func buy(good_id: String, quantity: int) -> bool:
    if not can_trade() or not goods.has(good_id) or quantity <= 0:
        return false
    var market: Market = markets[docked_port_id]
    var stock: int = int(market.inventory.get(good_id, 0))
    if quantity > stock or quantity > ship.capacity - cargo.total():
        return false
    var cost: int = market.trade_total(good_id, quantity, true)
    if cost > wallet.coins:
        return false
    wallet.coins -= cost
    cargo.quantities[good_id] = cargo.quantity(good_id) + quantity
    market.inventory[good_id] = stock - quantity
    market.refresh_price(good_id)
    return true

func sell(good_id: String, quantity: int) -> bool:
    if not can_trade() or not goods.has(good_id) or quantity <= 0:
        return false
    if cargo.quantity(good_id) < quantity:
        return false
    var market: Market = markets[docked_port_id]
    var proceeds: int = market.trade_total(good_id, quantity, false)
    cargo.quantities[good_id] = cargo.quantity(good_id) - quantity
    wallet.coins += proceeds
    market.inventory[good_id] = int(market.inventory.get(good_id, 0)) + quantity
    market.refresh_price(good_id)
    return true

# Largest affordable batch, accounting for every successive price step.
func max_buy_quantity(good_id: String) -> int:
    if not can_trade() or not goods.has(good_id):
        return 0
    var market: Market = markets[docked_port_id]
    var stock: int = int(market.inventory[good_id])
    var limit: int = maxi(0, mini(stock, ship.capacity - cargo.total()))
    var cost: int = 0
    var count: int = 0
    for index in range(limit):
        cost += market.price_at_stock(good_id, stock - index)
        if cost > wallet.coins:
            break
        count += 1
    return count

func buy_all(good_id: String) -> bool:
    return buy(good_id, max_buy_quantity(good_id))

func sell_all(good_id: String) -> bool:
    return sell(good_id, cargo.quantity(good_id))

func start_voyage(destination_id: String) -> bool:
    if voyage.active:
        departure_feedback = "Already sailing; supplies were charged at departure."
        return false
    if not ports.has(destination_id):
        departure_feedback = "Unknown destination."
        return false
    if destination_id == docked_port_id:
        departure_feedback = "Already docked at %s; requires 0 provisions." % destination_id
        return false
    var required: int = required_provisions(destination_id)
    if provisions < required:
        departure_feedback = "Cannot depart to %s: requires %d provisions; aboard %d. Buy at dock." % [destination_id, required, provisions]
        return false
    var destination: Port = ports[destination_id]
    # Commit supplies and voyage together only after all departure gates pass.
    provisions -= required
    voyage.provisions_consumed = required
    departure_feedback = "Departure to %s requires %d provisions; consumed %d." % [destination_id, required, required]
    voyage.origin_id = docked_port_id
    voyage.destination_id = destination_id
    voyage.distance = ship.position.distance_to(destination.position)
    voyage.duration = voyage.distance / maxf(ship.speed, 0.001)
    voyage.progress = 0.0
    voyage.remaining_time = voyage.duration
    voyage.active = true
    docked_port_id = ""
    if is_zero_approx(voyage.distance):
        advance_voyage(0.0)
    return true

func advance_voyage(delta: float) -> void:
    if not voyage.active:
        return
    var destination: Port = ports[voyage.destination_id]
    ship.position = ship.position.move_toward(destination.position, maxf(ship.speed, 0.0) * maxf(delta, 0.0))
    var remaining: float = ship.position.distance_to(destination.position)
    voyage.remaining_time = remaining / maxf(ship.speed, 0.001)
    voyage.progress = clampf(1.0 - remaining / maxf(voyage.distance, 0.001), 0.0, 1.0)
    if remaining <= 0.001:
        ship.position = destination.position
        docked_port_id = destination.id
        voyage.active = false
        voyage.progress = 1.0
        voyage.remaining_time = 0.0
