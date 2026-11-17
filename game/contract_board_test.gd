extends TestScene

func test_accept_contract() -> void:
    var board = ContractBoard.new()
    board.build_board()
    board.accept_contract()
    assert(board.feedback.text == "Accepted: bring 3 Sugar to Port B.")

func test_complete_contract() -> void:
    var board = ContractBoard.new()
    board.build_board()
    board.accept_contract()
    board.complete_contract()
    assert(board.feedback.text == "Delivered! +30 coins. Return to Port A to replay.")

func test_get_contract_data() -> void:
    var board = ContractBoard.new()
    board.build_board()
    var data = board.get_contract_data()
    assert(data.active == true)
    assert(data.completed_count == 0)

func test_refresh_contract() -> void:
    var board = ContractBoard.new()
    board.build_board()
    board.refresh_contract()
    assert(board.details.text == "Active\nDeliver 3 Sugar to Port B.\nReward: 30 coins\nOwned: 0/3\nCompleted: 0")
