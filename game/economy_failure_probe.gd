extends Node

# Opt-in failure-path probe: attach after EconomyStateCheck in main.tscn.
# The normal scene does not attach this script.
func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        get_parent().get_node("EconomyStateCheck").require_condition(false, "deliberately failing economy condition for exit-code verification")
