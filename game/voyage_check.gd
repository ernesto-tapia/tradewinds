extends Node

var state
var owns_state: bool = false
var voyage_time: float = 0.0

func _init(game_state = null) -> void:
    state = game_state
    owns_state = game_state != null

func _ready() -> void:
    if state == null:
        state = get_parent().game_state

func sail_to(destination: Node) -> void:
    if not owns_state:
        get_parent().sail_to(destination)
    else:
        state.start_voyage(str(destination.name))
    voyage_time = state.voyage.remaining_time

func _process(delta: float) -> void:
    if state == null:
        return
    # The main scene advances its shared state. Standalone callers advance here.
    if owns_state:
        state.advance_voyage(delta)
    voyage_time = state.voyage.remaining_time

func get_voyage_time() -> float:
    return state.voyage.remaining_time

func get_docked_port_id() -> String:
    return state.docked_port_id
