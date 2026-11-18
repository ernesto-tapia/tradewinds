extends Node

const Main = preload("res://main.gd")
const Board = preload("res://contract_board.gd")
const Provisioning = preload("res://provisioning.gd")

func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        call_deferred("run_checks")

func require_condition(value: bool, message: String) -> bool:
    if not value:
        push_error("KAN-24 contract UI: " + message)
        get_tree().quit(1)
    return value

func run_checks() -> void:
    var game = Main.new()
    add_child(game)
    game.set_process(false)
    var board = Board.new()
    game.add_child(board)
    var supplies = Provisioning.new()
    game.add_child(supplies)
    await get_tree().process_frame
    await get_tree().process_frame
    board.set_process(false)
    if not require_condition(board.delivery != null and board.accept_button.disabled and board.complete_button.disabled, "board builds with a game parent and blocks actions at sea"):
        return
    if not require_condition(supplies.buy_button.disabled, "provision purchases are disabled at sea"):
        return
    if not require_condition(not board.get_contract_data().active and board.get_contract_data().completed_count == 0, "initial offer is inactive"):
        return
    game.sail_to(game.get_node("Port A"))
    game._process(game.voyage_time + 1.0)
    board.refresh_contract()
    supplies.refresh_provisioning()
    if not require_condition(not board.accept_button.disabled and board.accept_button.visible and not board.complete_button.visible, "origin docking enables the offer"):
        return
    if not require_condition(not supplies.buy_button.disabled, "docking enables provision purchases"):
        return
    var purchase_coins: int = game.game_state.wallet.coins
    var purchase_balance: int = game.game_state.provisions
    if not require_condition(supplies.buy_provisions() and game.game_state.provisions == purchase_balance + 4 and game.game_state.wallet.coins == purchase_coins - 8 and "Bought 4 provisions" in supplies.feedback.text, "dock purchase updates real resources and feedback"):
        return
    if not require_condition(board.accept_contract() and board.feedback.text == "Accepted: bring 3 Sugar to Port B." and board.get_contract_data().active, "acceptance updates feedback and active state"):
        return
    if not require_condition(board.complete_button.visible and board.complete_button.disabled and not board.accept_button.visible, "active contract shows a disabled delivery action at origin"):
        return
    if not require_condition(game.buy("sugar", 3), "purchase the required cargo at origin"):
        return
    board.refresh_contract()
    if not require_condition(board.complete_button.disabled, "cargo alone cannot enable delivery at origin"):
        return
    game.sail_to(game.get_node("Port B"))
    game._process(game.voyage_time + 1.0)
    board.refresh_contract()
    if not require_condition(not board.complete_button.disabled, "destination docking with cargo enables delivery"):
        return
    var coins: int = game.game_state.wallet.coins
    if not require_condition(board.complete_contract() and board.feedback.text == "Delivered! +30 coins. Return to Port A to replay.", "delivery updates result feedback"):
        return
    if not require_condition(game.game_state.wallet.coins == coins + 30 and game.game_state.cargo.quantity("sugar") == 0 and board.get_contract_data().completed_count == 1 and not board.get_contract_data().active, "delivery consumes cargo and pays exactly once"):
        return
    if not require_condition(board.accept_button.visible and board.accept_button.disabled and not board.complete_button.visible and "Completed: 1" in board.details.text, "completed board displays the updated offer and count"):
        return
    game.queue_free()
    print("KAN-24 contract UI passed: real game parent, initial offer, origin docking, acceptance feedback, cargo and destination gates, delivery feedback, exact cargo consumption and reward, completed controls; KAN-16 dock purchase resources and feedback")
