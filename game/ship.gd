extends Control

var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var acceleration: Vector2 = Vector2.ZERO
var max_speed: float = 10.0
var max_acceleration: float = 5.0
var drag: float = 0.1

func _ready() -> void:
    pass

func _process(delta: float) -> void:
    apply_drag(delta)
    apply_velocity(delta)
    update_position(delta)

func apply_drag(delta: float) -> void:
    acceleration += -velocity * drag * delta

func apply_velocity(delta: float) -> void:
    velocity += acceleration * delta
    velocity = velocity.clamped(-max_speed, max_speed)

func update_position(delta: float) -> void:
    position += velocity * delta

func set_position(new_position: Vector2) -> void:
    position = new_position

func set_velocity(new_velocity: Vector2) -> void:
    velocity = new_velocity

func set_acceleration(new_acceleration: Vector2) -> void:
    acceleration = new_acceleration

func get_position() -> Vector2:
    return position

func get_velocity() -> Vector2:
    return velocity

func get_acceleration() -> Vector2:
    return acceleration