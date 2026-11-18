extends Node2D

const Models = preload("res://data_models.gd")
const UI = preload("res://ui/menu_ui.gd")
var game_state = Models.new()
var ship: ColorRect
var current_destination: Control = null
var docked_port: Control = null
var voyage_time: float = 0.0
var voyage_progress: float = 0.0
var remaining_time: float = 0.0
var destination_feedback: Label
var trade_feedback: Label
var trade_button: Button
var economy_feedback: Label
var market_panel: PanelContainer
var market_title: Label
var market_rows: Dictionary = {}
var buy_buttons: Dictionary = {}
var sell_buttons: Dictionary = {}
var buy_all_buttons: Dictionary = {}
var sell_all_buttons: Dictionary = {}
var cargo_values: Dictionary = {}
var wallet_value: Label
var capacity_value: Label
var active_menu: String = "contracts"
var selected_good: String = "sugar"
var commodity_sections: Dictionary = {}
var menu_buttons: Dictionary = {}
var commodity_selector: Button
var commodity_chooser: PanelContainer
var commodity_content: VBoxContainer
var commodity_choices: Dictionary = {}

func box(id: String, at: Vector2, dimensions: Vector2, tint: Color, text: String, parent: Node = self) -> ColorRect:
    var control := ColorRect.new()
    control.name = id
    control.position = at
    control.size = dimensions
    control.color = tint
    control.theme = UI.DEMO_THEME
    control.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(control)
    var label := Label.new()
    label.position = Vector2.ZERO
    label.size = dimensions
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.text = text
    control.add_child(label)
    return control

func caption(control: Control) -> Label:
    return control.get_child(0) as Label

func _ready() -> void:
    box("Ocean", Vector2.ZERO, Vector2(1280, 720), Color("163e58"), "Ocean")
    var title := UI.panel(self, "Title", Vector2(10, 10), Vector2(1260, 48))
    var header := UI.row(title)
    UI.label(header, "Caribbean Tradewinds", "Heading")
    UI.label(header, "Coins").size_flags_horizontal = Control.SIZE_SHRINK_END
    wallet_value = UI.label(header, "0")
    wallet_value.size_flags_horizontal = Control.SIZE_SHRINK_END
    UI.label(header, "Cargo").size_flags_horizontal = Control.SIZE_SHRINK_END
    capacity_value = UI.label(header, "0/20")
    capacity_value.size_flags_horizontal = Control.SIZE_SHRINK_END
    for item in header.get_children():
        if item is Label:
            item.autowrap_mode = TextServer.AUTOWRAP_OFF
    box("Island", Vector2(220, 170), Vector2(140, 130), Color("476445"), "Island")
    box("Island B", Vector2(530, 300), Vector2(150, 120), Color("476445"), "Island")
    for port_id in game_state.ports:
        var port := box(port_id, game_state.ports[port_id].position, Vector2(90, 45), Color("815a39"), port_id)
        port.mouse_filter = Control.MOUSE_FILTER_STOP
        port.add_to_group("ports")
        port.set_meta("destination_id", port_id)
        port.gui_input.connect(_port_input.bind(port))
    ship = box("Ship", game_state.ship.position, Vector2(70, 35), Color("7c667d"), "Ship")
    ship.mouse_filter = Control.MOUSE_FILTER_STOP
    ship.add_to_group("player_ship")
    ship.set_meta("selected", false)
    ship.gui_input.connect(_ship_input)
    var destination := UI.panel(self, "Destination", Vector2(10, 68), Vector2(690, 92))
    destination_feedback = UI.label(destination, "Choose Port A or Port B to sail")
    destination_feedback.add_to_group("destination_feedback")
    # This permission query stays available at sea; transactions enforce docking.
    trade_button = UI.button(self, "Trade", "", open_trade, true)
    trade_button.theme = UI.DEMO_THEME
    trade_button.position = Vector2(220, 470)
    trade_button.size = Vector2(480, 56)
    trade_button.accessibility_name = "Check trade permission"
    trade_feedback = UI.label(trade_button, "Trade unavailable at sea", "Warning")
    trade_feedback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    trade_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    trade_feedback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    var navigation := HBoxContainer.new()
    navigation.name = "MenuNavigation"
    navigation.theme = UI.DEMO_THEME
    navigation.position = Vector2(710, 68)
    navigation.size = Vector2(560, 48)
    add_child(navigation)
    for menu in ["market", "contracts", "cargo"]:
        var action := UI.button(navigation, "Open_" + menu, menu.capitalize(), show_menu.bind(menu))
        action.custom_minimum_size.y = 48
        action.toggle_mode = true
        action.button_pressed = menu == active_menu
        menu_buttons[menu] = action
    var cargo := UI.panel(self, "Economy", Vector2(710, 126), Vector2(560, 584))
    cargo.visible = false
    var cargo_column := UI.scroll_column(cargo)
    economy_feedback = UI.label(cargo_column, "Cargo manifest", "Heading")
    var cargo_row := UI.row(cargo_column)
    var quantities := UI.column(cargo_row)
    for good_id in game_state.goods:
        cargo_values[good_id] = UI.value_row(quantities, game_state.goods[good_id].name)
    _build_market()
    set_meta("at_sea", true)
    refresh_market()
    refresh_route_requirements()

func _build_market() -> void:
    market_panel = UI.panel(self, "Market", Vector2(710, 126), Vector2(560, 584))
    var column := UI.column(market_panel)
    UI.label(column, "Port market", "Heading")
    market_title = UI.label(column, "Dock to open market")
    commodity_selector = UI.button(column, "CommoditySelector", "Sugar — Change commodity", toggle_commodity_chooser)
    commodity_chooser = PanelContainer.new()
    commodity_chooser.name = "CommodityChooser"
    commodity_chooser.theme = UI.DEMO_THEME
    column.add_child(commodity_chooser)
    var choices := UI.column(commodity_chooser)
    UI.label(choices, "Choose a commodity")
    for good_id in game_state.goods:
        commodity_choices[good_id] = UI.button(choices, "Choose_" + good_id, game_state.goods[good_id].name, select_commodity.bind(good_id))
    commodity_chooser.hide()
    var content := UI.scroll_column(column)
    commodity_content = content
    for good_id in game_state.goods:
        var section := PanelContainer.new()
        section.name = "Row_" + good_id
        section.visible = good_id == selected_good
        commodity_sections[good_id] = section
        content.add_child(section)
        var rows := UI.column(section)
        UI.label(rows, game_state.goods[good_id].name, "Heading")
        var values := UI.row(rows)
        var stock := UI.value_row(values, "Stock")
        var owned := UI.value_row(values, "Owned")
        market_rows[good_id] = {"stock": stock, "owned": owned}
        var actions := GridContainer.new()
        actions.columns = 2
        rows.add_child(actions)
        buy_buttons[good_id] = UI.button(actions, "Buy_" + good_id, "Buy 1", _transaction.bind(good_id, true, false), true)
        buy_all_buttons[good_id] = UI.button(actions, "BuyAll_" + good_id, "Buy all", _transaction.bind(good_id, true, true))
        sell_buttons[good_id] = UI.button(actions, "Sell_" + good_id, "Sell 1", _transaction.bind(good_id, false, false))
        sell_all_buttons[good_id] = UI.button(actions, "SellAll_" + good_id, "Sell all", _transaction.bind(good_id, false, true))
        actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    commodity_selector.tooltip_text = "Prices change after each unit traded. Bulk buttons show the total."

func toggle_commodity_chooser() -> void:
    var opened := not commodity_chooser.visible
    commodity_chooser.visible = opened
    commodity_content.get_parent().visible = not opened
    if opened:
        commodity_choices[selected_good].grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_cancel") and commodity_chooser.is_visible_in_tree():
        toggle_commodity_chooser()
        commodity_selector.grab_focus()
        get_viewport().set_input_as_handled()

func select_commodity(good_id: String) -> void:
    selected_good = good_id
    commodity_selector.text = game_state.goods[good_id].name + " — Change commodity"
    commodity_chooser.hide()
    commodity_content.get_parent().show()
    if commodity_selector.is_visible_in_tree():
        commodity_selector.grab_focus()
    for key in commodity_sections:
        commodity_sections[key].visible = key == good_id

func show_menu(menu: String) -> void:
    commodity_chooser.hide()
    commodity_content.get_parent().show()
    active_menu = menu
    for key in menu_buttons:
        menu_buttons[key].button_pressed = key == menu
    get_node("Economy").visible = menu == "cargo"
    var contracts := get_node_or_null("ContractPanel") as Control
    if contracts != null:
        contracts.visible = menu == "contracts"
    market_panel.visible = menu == "market" and can_trade()

func pressed(event: InputEvent) -> bool:
    return event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed

func _port_input(event: InputEvent, port: Control) -> void:
    if pressed(event):
        sail_to(port)

func _ship_input(event: InputEvent) -> void:
    if pressed(event):
        ship.set_meta("selected", true)
        ship.color = Color("b68a43")
        caption(ship).text = "Selected"

func _transaction(good_id: String, purchasing: bool, all_units: bool) -> void:
    var accepted: bool
    if all_units:
        accepted = buy_all(good_id) if purchasing else sell_all(good_id)
    else:
        accepted = buy(good_id, 1) if purchasing else sell(good_id, 1)
    UI.status(trade_feedback, "Trade permitted: transaction completed" if accepted else "Trade unavailable: check stock, coins, cargo and docking", not accepted)

func _transaction_input(event: InputEvent, good_id: String, purchasing: bool, all_units: bool = false) -> void:
    if pressed(event):
        _transaction(good_id, purchasing, all_units)

func sail_to(port: Control) -> void:
    var accepted: bool = game_state.start_voyage(str(port.name))
    if not accepted:
        UI.status(destination_feedback, game_state.departure_feedback, true)
        refresh_provisioning_panel()
        return
    voyage_time = game_state.voyage.duration
    set_meta("destination_id", str(port.name))
    if game_state.voyage.active:
        current_destination = port
        docked_port = null
        set_meta("at_sea", true)
    else:
        current_destination = null
        docked_port = get_node(game_state.docked_port_id) as Control
        set_meta("at_sea", false)
    refresh_voyage()
    refresh_market()
    refresh_provisioning_panel()

func _process(delta: float) -> void:
    if game_state.voyage.active:
        game_state.advance_voyage(delta)
        refresh_voyage()
        if not game_state.voyage.active:
            docked_port = get_node(game_state.docked_port_id) as Control
            current_destination = null
            set_meta("at_sea", false)
            refresh_market()
            refresh_provisioning_panel()

func refresh_route_requirements() -> void:
    for port_id in game_state.ports:
        var port := get_node_or_null(NodePath(port_id)) as Control
        if port != null:
            port.tooltip_text = "%s requires %d provisions; aboard %d. Supplies cost 2 coins each at dock." % [port_id, game_state.required_provisions(port_id), game_state.provisions]

func refresh_provisioning_panel() -> void:
    refresh_route_requirements()
    var provisioning := get_node_or_null("Provisioning")
    if provisioning != null and is_instance_valid(provisioning.buy_button):
        provisioning.refresh_provisioning()

func refresh_voyage() -> void:
    ship.position = game_state.ship.position
    voyage_progress = game_state.voyage.progress
    remaining_time = game_state.voyage.remaining_time
    if game_state.voyage.active:
        UI.status(destination_feedback, "Sailing to %s: %d%% | %.1f seconds remaining\n%s" % [game_state.voyage.destination_id, roundi(voyage_progress * 100.0), remaining_time, game_state.departure_feedback])
    else:
        UI.status(destination_feedback, "Docked at %s · Aboard: %d provisions\nPort A requires %d; Port B requires %d provisions." % [game_state.docked_port_id, game_state.provisions, game_state.required_provisions("Port A"), game_state.required_provisions("Port B")])
    refresh_route_requirements()

func can_trade() -> bool:
    return game_state.can_trade()

func request_trade() -> bool:
    trade_feedback.text = "Trade permitted at " + game_state.docked_port_id if can_trade() else "Trade unavailable at sea"
    trade_feedback.theme_type_variation = "Label" if can_trade() else "Warning"
    return can_trade()

func open_trade() -> void:
    if request_trade():
        show_menu("market")

func buy(good_id: String, quantity: int) -> bool:
    var accepted: bool = game_state.buy(good_id, quantity)
    refresh_market()
    return accepted

func sell(good_id: String, quantity: int) -> bool:
    var accepted: bool = game_state.sell(good_id, quantity)
    refresh_market()
    return accepted

func buy_all(good_id: String) -> bool:
    var accepted: bool = game_state.buy_all(good_id)
    refresh_market()
    return accepted

func sell_all(good_id: String) -> bool:
    var accepted: bool = game_state.sell_all(good_id)
    refresh_market()
    return accepted

func get_market_data(port_id: String) -> Dictionary:
    if not game_state.markets.has(port_id):
        return {}
    var market = game_state.markets[port_id]
    return {"port_id": port_id, "inventory": market.inventory.duplicate(true), "prices": market.prices.duplicate(true), "wallet_coins": game_state.wallet.coins}

func refresh_market() -> void:
    if not is_instance_valid(market_panel):
        return
    wallet_value.text = str(game_state.wallet.coins)
    capacity_value.text = "%d/%d" % [game_state.cargo.total(), game_state.ship.capacity]
    for good_id in cargo_values:
        cargo_values[good_id].text = str(game_state.cargo.quantity(good_id))
    market_panel.visible = can_trade() and active_menu == "market"
    for good_id in market_rows:
        var owned: int = game_state.cargo.quantity(good_id)
        var maximum: int = game_state.max_buy_quantity(good_id)
        buy_buttons[good_id].disabled = maximum == 0
        buy_all_buttons[good_id].disabled = maximum == 0
        sell_buttons[good_id].disabled = not can_trade() or owned == 0
        sell_all_buttons[good_id].disabled = not can_trade() or owned == 0
        if not can_trade():
            continue
        var market = game_state.markets[game_state.docked_port_id]
        var price: int = int(market.prices.get(good_id, 0))
        var sell_price: int = market.trade_total(good_id, 1, false)
        market_rows[good_id].stock.text = str(market.inventory.get(good_id, 0))
        market_rows[good_id].owned.text = str(owned)
        buy_buttons[good_id].text = "Buy 1\n%d coins" % price
        sell_buttons[good_id].text = "Sell 1\n%d coins" % sell_price
        buy_all_buttons[good_id].text = "Buy all (%d)\n%d coins" % [maximum, market.trade_total(good_id, maximum, true)]
        sell_all_buttons[good_id].text = "Sell all (%d)\n%d coins" % [owned, market.trade_total(good_id, owned, false)]
    if can_trade():
        market_title.text = game_state.docked_port_id
    request_trade()
