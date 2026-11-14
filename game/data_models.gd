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
    func _init(location: String, stock: Dictionary, unit_prices: Dictionary) -> void:
        port_id = location
        inventory = stock.duplicate(true)
        prices = unit_prices.duplicate(true)

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
        "rum": Good.new("rum", "Rum")
    }
    markets = {
        "Port A": Market.new("Port A", {"sugar": 20, "rum": 10}, {"sugar": 5, "rum": 10}),
        "Port B": Market.new("Port B", {"sugar": 10, "rum": 20}, {"sugar": 8, "rum": 7})
    }
    ship = Ship.new()
    cargo = ship.cargo
    wallet = PlayerWallet.new()
    voyage = Voyage.new()
    var contract: Contract = Contract.new()
    contracts[contract.id] = contract

func can_trade() -> bool:
    return not voyage.active and markets.has(docked_port_id)

# Reject invalid transactions before touching any shared state.
func buy(good_id: String, quantity: int) -> bool:
    if not can_trade() or not goods.has(good_id) or quantity <= 0:
        return false
    var market: Market = markets[docked_port_id]
    var stock: int = int(market.inventory.get(good_id, 0))
    var price: int = int(market.prices.get(good_id, 0))
    if price <= 0 or quantity > stock or quantity > ship.capacity - cargo.total():
        return false
    if quantity > wallet.coins / price:
        return false
    wallet.coins -= quantity * price
    cargo.quantities[good_id] = cargo.quantity(good_id) + quantity
    market.inventory[good_id] = stock - quantity
    return true

func sell(good_id: String, quantity: int) -> bool:
    if not can_trade() or not goods.has(good_id) or quantity <= 0:
        return false
    var market: Market = markets[docked_port_id]
    var price: int = int(market.prices.get(good_id, 0))
    if price <= 0 or cargo.quantity(good_id) < quantity:
        return false
    cargo.quantities[good_id] = cargo.quantity(good_id) - quantity
    wallet.coins += quantity * price
    market.inventory[good_id] = int(market.inventory.get(good_id, 0)) + quantity
    return true

func start_voyage(destination_id: String) -> bool:
    if voyage.active or not ports.has(destination_id):
        return false
    var destination: Port = ports[destination_id]
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
