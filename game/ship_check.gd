extends Node

const Ship = preload("res://ship.gd")

func require_condition(value: bool, message: String) -> bool:
    if not value:
        push_error("KAN-16 ship: " + message)
        get_tree().quit(1)
    return value

func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        call_deferred("run_checks")

func run_checks() -> void:
    var ship = Ship.new()
    var before: Vector2 = ship.position
    ship.set_position(Vector2(100, 200))
    if not require_condition(ship.position == Vector2(100, 200) and ship.velocity == Vector2.ZERO and ship.acceleration == Vector2.ZERO, "position must update immediately"):
        return
    ship.set_velocity(Vector2(5, 10))
    ship.set_acceleration(Vector2(1, 2))
    ship._process(0.1)
    if not require_condition(ship.position == Vector2(105.1, 210.2) and ship.velocity == Vector2(5.1, 10.2) and ship.acceleration == Vector2(1, 2), "velocity and acceleration must update and apply drag"):
        return
    ship.set_velocity(Vector2.ZERO)
    ship.set_acceleration(Vector2.ZERO)
    ship._process(1.0)
    if not require_condition(ship.position == Vector2(105.1, 210.2) and ship.velocity == Vector2.ZERO and ship.acceleration == Vector2.ZERO, "velocity and acceleration must decay to zero"):
        return
    print("KAN-16 ship passed: position, velocity, acceleration, drag and decay")
