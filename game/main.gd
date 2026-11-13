extends Control

func _ready():
    print("Caribbean Tradewinds: map ready")

    # Create ColorRect and Label children programmatically
    var ocean = ColorRect.new()
    ocean.position = Vector2(100, 100)
    ocean.size = Vector2(400, 200)
    ocean.color = Color(0.2, 0.2, 0.2)
    var ocean_label = Label.new()
    ocean_label.text = "Ocean"
    ocean_label.size = ocean.size
    ocean_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    ocean_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    ocean.add_child(ocean_label)

    var island = ColorRect.new()
    island.position = Vector2(550, 100)
    island.size = Vector2(200, 200)
    island.color = Color(0.5, 0.5, 0.5)
    var island_label = Label.new()
    island_label.text = "Island"
    island_label.size = island.size
    island_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    island_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    island.add_child(island_label)

    var ship = ColorRect.new()
    ship.position = Vector2(100, 400)
    ship.size = Vector2(200, 100)
    ship.color = Color(0.8, 0.8, 0.8)
    var ship_label = Label.new()
    ship_label.text = "Ship"
    ship_label.size = ship.size
    ship_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    ship_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    ship.add_child(ship_label)

    add_child(ocean)
    add_child(island)
    add_child(ship)

    var title = Label.new()
    title.text = "Caribbean Tradewinds"
    title.size = Vector2(400, 50)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    add_child(title)