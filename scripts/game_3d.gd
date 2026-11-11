extends Node3D

const TILE_SIZE := 2.0
const MAX_EXPANSIONS := 6
const EXPAND_FILL_RATIO := 0.5
const DAY_LENGTH := 5.0
const SAVE_PATH := "user://tiny_kingdom_save.json"
const TOOLS := ["house", "farm", "lumber", "quarry", "market", "road", "rotate", "demolish"]
const TOOL_NAMES := ["ДОМ", "ФЕРМА", "ЛЕСОПИЛКА", "КАМЕНОЛОМНЯ", "РЫНОК", "ДОРОГА", "ПОВОРОТ", "СНЕСТИ"]
const TOOL_COSTS := ["35 З · 20 Д", "25 З · 15 Д", "40 З · 20 Д", "45 З · 25 Д", "30 З · 15 Д", "2 З", "БЕСПЛАТНО", "ВОЗВРАТ 25%"]

const MAT_GRASS := Color("#718f58")
const MAT_GRASS_ALT := Color("#799761")
const MAT_WOOD := Color("#69452f")
const MAT_WOOD_LIGHT := Color("#a7774a")
const MAT_PLASTER := Color("#dfcfaa")
const MAT_ROOF := Color("#934e3d")
const MAT_STONE := Color("#97958a")
const MAT_GOLD := Color("#d4ad59")

var camera: Camera3D
var world_root: Node3D
var ui: Control
var gold := 140
var wood := 90
var stone := 65
var food := 32
var population := 4
var happiness := 76
var day := 1
var day_timer := 0.0
var running := true
var speed := 1
var selected_tool := "house"
var message := "Построй ферму, чтобы запасти еду."
var buildings: Dictionary = {}
var building_nodes: Dictionary = {}
var last_click_time := 0.0
var last_click_cell := Vector2i(-999, -999)
var cam_dragging := false
var drag_moved := false
var drag_press_pos := Vector2.ZERO
var drag_ground_start := Vector3.ZERO
var drag_cam_start := Vector3.ZERO
var resource_labels: Dictionary = {}
var stats_labels: Dictionary = {}
var message_label: Label
var hover_marker: MeshInstance3D
var villagers: Array[Node3D] = []
var grid_min := Vector2i(0, 0)
var grid_max := Vector2i(16, 10)
var grid_anchor := Vector3(-15.0, 0.0, -9.0)
var blocked: Dictionary = {}
var decor_by_cell: Dictionary = {}
var meadow_cells: Dictionary = {}
var expansions := 0
var expand_pending := false
var ground_mesh: BoxMesh
var ground_instance: MeshInstance3D
var hover_material: StandardMaterial3D


func _ready() -> void:
	_build_world()
	_build_ui()
	_add_building(Vector2i(7, 4), "keep")
	for cell in [Vector2i(7, 5), Vector2i(8, 5), Vector2i(9, 5), Vector2i(9, 4)]:
		_add_building(cell, "road")
	_add_village_props()
	_add_villagers()
	_update_ui()


func _process(delta: float) -> void:
	if running:
		day_timer += delta * speed
		while day_timer >= DAY_LENGTH:
			day_timer -= DAY_LENGTH
			_advance_day()
	_update_hover()
	for i in range(villagers.size()):
		var villager := villagers[i]
		villager.position.x += sin(Time.get_ticks_msec() * 0.0005 + i * 2.0) * delta * 0.18


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var zoom_factor := 0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1
		camera.size = clampf(camera.size * zoom_factor, 12.0, 60.0)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		cam_dragging = true
		drag_moved = false
		drag_press_pos = event.position
		drag_cam_start = camera.position
		var press_hit: Variant = _cursor_ground_position(event.position)
		drag_ground_start = press_hit if press_hit != null else Vector3.ZERO
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if cam_dragging:
			cam_dragging = false
			if not drag_moved:
				_handle_click(event.position)
	elif event is InputEventMouseMotion and cam_dragging and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if event.position.distance_to(drag_press_pos) > 6.0:
			drag_moved = true
		var hit: Variant = _cursor_ground_position(event.position)
		if hit != null:
			var delta := (Vector3(hit) - drag_ground_start) * -0.5
			var new_pos := drag_cam_start + Vector3(delta.x, 0.0, delta.z)
			new_pos.x = clampf(new_pos.x, -60.0, 60.0)
			new_pos.z = clampf(new_pos.z, -50.0, 50.0)
			camera.position = new_pos
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			running = not running
			_update_ui()
		elif event.keycode == KEY_1:
			speed = 1
			_update_ui()
		elif event.keycode == KEY_2:
			speed = 2
			_update_ui()


func _build_world() -> void:
	world_root = Node3D.new()
	world_root.name = "Village"
	add_child(world_root)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#5883a0")
	sky_material.sky_horizon_color = Color("#e5c89b")
	sky_material.ground_bottom_color = Color("#454d38")
	sky_material.ground_horizon_color = Color("#c2aa7c")
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b4b9a7")
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssr_enabled = false
	environment.environment = env
	add_child(environment)
	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-48, -28, 0)
	sunlight.light_color = Color("#ffe0ad")
	sunlight.light_energy = 1.25
	sunlight.shadow_enabled = true
	sunlight.directional_shadow_max_distance = 70.0
	add_child(sunlight)
	camera = Camera3D.new()
	camera.name = "VillageCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 23.0
	camera.position = Vector3(19.0, 22.0, 27.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	_build_ground()
	_build_tiles()
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(1.92, 0.025, 1.92)
	hover_marker = MeshInstance3D.new()
	hover_marker.mesh = marker_mesh
	hover_material = StandardMaterial3D.new()
	hover_material.albedo_color = Color(1.0, 0.88, 0.4, 0.38)
	hover_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hover_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hover_marker.material_override = hover_material
	hover_marker.visible = false
	add_child(hover_marker)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_PASS
	layer.add_child(ui)
	var header := _panel(ui, Vector2(0, 0), Vector2(1600, 82), Color("#202721", 0.94), Color("#bb995a"))
	_add_label(header, "TINY KINGDOM", Vector2(27, 11), Vector2(240, 22), 12, Color("#d8c28e"))
	_add_label(header, "МАЛЕНЬКОЕ КОРОЛЕВСТВО", Vector2(27, 34), Vector2(330, 32), 20, Color("#f0e4c7"))
	var resources := [["ЗОЛОТО", "gold", Color("#e6c26a")], ["ДЕРЕВО", "wood", Color("#d7a56a")], ["КАМЕНЬ", "stone", Color("#c2c5bd")], ["ЕДА", "food", Color("#9bc36f")]]
	for i in range(resources.size()):
		var x := 405.0 + i * 155.0
		var resource_title := _add_label(header, resources[i][0], Vector2(x, 13), Vector2(120, 17), 10, Color("#aeb8a5"))
		resource_title.tooltip_text = _resource_help(str(resources[i][1]))
		var label := _add_label(header, "0", Vector2(x, 34), Vector2(120, 31), 23, resources[i][2])
		label.tooltip_text = _resource_help(str(resources[i][1]))
		resource_labels[resources[i][1]] = label
	_add_label(header, "ДЕНЬ", Vector2(1048, 15), Vector2(90, 18), 10, Color("#aeb8a5"))
	stats_labels["day"] = _add_label(header, "01", Vector2(1048, 35), Vector2(90, 28), 20, Color("#f0e4c7"))
	var save_button := _button(header, "СОХРАНИТЬ", Rect2(1146, 21, 78, 42))
	save_button.pressed.connect(_save_game)
	var load_button := _button(header, "ЗАГРУЗИТЬ", Rect2(1230, 21, 82, 42))
	load_button.pressed.connect(_load_game)
	var pause_button := _button(header, "Ⅱ  ПАУЗА", Rect2(1320, 21, 104, 42))
	pause_button.pressed.connect(_toggle_pause)
	var speed_button := _button(header, "СКОРОСТЬ  x1", Rect2(1430, 21, 145, 42))
	speed_button.pressed.connect(_toggle_speed)
	var build_panel := _panel(ui, Vector2(20, 105), Vector2(230, 700), Color("#252c25", 0.95), Color("#a3844d"))
	build_panel.name = "BuildPanel"
	_add_label(build_panel, "ПОСТРОЙКИ", Vector2(16, 14), Vector2(195, 25), 16, Color("#efdfbc"))
	_add_label(build_panel, "Сначала построй источник ресурсов", Vector2(16, 40), Vector2(205, 24), 10, Color("#aeb5a3"))
	for i in range(TOOLS.size()):
		var button := _button(build_panel, TOOL_NAMES[i] + "\n" + TOOL_COSTS[i], Rect2(14, 77 + i * 62, 202, 56))
		button.name = "BuildButton%d" % i
		button.tooltip_text = _tool_help(str(TOOLS[i]))
		button.pressed.connect(_select_tool.bind(TOOLS[i]))
	_add_label(build_panel, "1. Выбери постройку\n2. Нажми свободную клетку\nЗ — золото, Д — дерево\nЛКМ + тяни — карта\nКолесо — масштаб", Vector2(15, 592), Vector2(205, 80), 10, Color("#c6baa0"))
	var kingdom_panel := _panel(ui, Vector2(1320, 105), Vector2(260, 640), Color("#252c25", 0.95), Color("#a3844d"))
	_add_label(kingdom_panel, "КОРОЛЕВСТВО", Vector2(18, 14), Vector2(220, 25), 16, Color("#efdfbc"))
	_add_label(kingdom_panel, "НАСЕЛЕНИЕ", Vector2(18, 55), Vector2(220, 18), 10, Color("#aeb5a3"))
	stats_labels["population"] = _add_label(kingdom_panel, "4 / 6", Vector2(18, 75), Vector2(220, 35), 24, Color("#f0e4c7"))
	_add_label(kingdom_panel, "СЧАСТЬЕ", Vector2(18, 120), Vector2(220, 18), 10, Color("#aeb5a3"))
	stats_labels["happiness"] = _add_label(kingdom_panel, "76%", Vector2(18, 140), Vector2(220, 28), 17, Color("#a9ca7b"))
	_add_label(kingdom_panel, "ГДЕ БРАТЬ РЕСУРСЫ", Vector2(18, 194), Vector2(220, 20), 10, Color("#d5bd82"))
	stats_labels["production"] = _add_label(kingdom_panel, "", Vector2(18, 220), Vector2(224, 147), 11, Color("#e7ddc6"))
	_add_label(kingdom_panel, "ЗДАНИЯ В ГОРОДЕ", Vector2(18, 383), Vector2(220, 19), 10, Color("#aeb5a3"))
	stats_labels["buildings"] = _add_label(kingdom_panel, "", Vector2(18, 409), Vector2(224, 115), 12, Color("#e7ddc6"))
	_add_label(kingdom_panel, "ТЕРРИТОРИЯ", Vector2(18, 534), Vector2(220, 18), 10, Color("#aeb5a3"))
	stats_labels["territory"] = _add_label(kingdom_panel, "", Vector2(18, 554), Vector2(224, 72), 11, Color("#e7ddc6"))
	message_label = _add_label(ui, message, Vector2(270, 850), Vector2(1000, 28), 13, Color("#fff2d2"))
	var footer := _panel(ui, Vector2(260, 838), Vector2(1030, 45), Color("#202721", 0.88), Color("#866f43"))
	message_label.reparent(footer)
	message_label.position = Vector2(17, 10)
	message_label.size = Vector2(990, 25)


func _panel(parent: Control, pos: Vector2, size: Vector2, color: Color, border: Color) -> Panel:
	var panel := Panel.new()
	panel.position = pos
	panel.size = size
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 8
	style.content_margin_top = 6
	style.content_margin_right = 8
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func _add_label(parent: Control, text_value: String, pos: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = pos
	label.size = size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent: Control, text_value: String, rect: Rect2) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color("#eadfca"))
	button.add_theme_color_override("font_hover_color", Color("#fff1c8"))
	button.add_theme_color_override("font_pressed_color", Color("#fff1c8"))
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#343c31") if state != "hover" else Color("#48513d")
		style.border_color = Color("#77643f")
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.content_margin_left = 7
		style.content_margin_right = 7
		button.add_theme_stylebox_override("normal" if state == "normal" else state, style)
	parent.add_child(button)
	return button


func _material(color: Color, roughness := 0.95) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _mesh_instance(mesh: Mesh, material: Material, size: Vector3, pos: Vector3) -> MeshInstance3D:
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	return instance


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color)
	instance.position = pos
	parent.add_child(instance)
	return instance


func _cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color, segments := 8) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color)
	instance.position = pos
	parent.add_child(instance)
	return instance


func _sphere(parent: Node3D, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color)
	instance.position = pos
	parent.add_child(instance)
	return instance


func _add_building(cell: Vector2i, kind: String) -> void:
	buildings[cell] = kind
	var origin := _cell_center(cell)
	if kind == "road":
		var road_root := Node3D.new()
		road_root.position = origin
		road_root.name = "Road"
		world_root.add_child(road_root)
		_box(road_root, Vector3(1.94, 0.12, 1.94), Vector3(0, -0.02, 0), Color("#aa8d65"))
		for i in range(3):
			_box(road_root, Vector3(0.42, 0.06, 0.24), Vector3(-0.55 + i * 0.55, 0.06, 0.1), Color("#c3a47a"))
		building_nodes[cell] = road_root
		return
	var building := Node3D.new()
	building.position = origin
	building.name = kind.capitalize()
	world_root.add_child(building)
	building_nodes[cell] = building
	match kind:
		"keep": _make_keep(building)
		"house": _make_house(building, false)
		"farm": _make_farm(building)
		"lumber": _make_lumberyard(building)
		"quarry": _make_quarry(building)
		"market": _make_market(building)


func _make_house(parent: Node3D, large: bool) -> void:
	var s := 1.0 if not large else 1.35
	_box(parent, Vector3(1.35 * s, 1.28 * s, 1.3 * s), Vector3(0, 0.68 * s, 0), MAT_PLASTER)
	# Timber frame around the plaster walls.
	for x in [-0.61, 0.61]:
		_box(parent, Vector3(0.11, 1.5 * s, 0.12), Vector3(x * s, 0.72 * s, -0.67 * s), MAT_WOOD)
		_box(parent, Vector3(0.11, 1.5 * s, 0.12), Vector3(x * s, 0.72 * s, 0.67 * s), MAT_WOOD)
	for z in [-0.65, 0.65]:
		_box(parent, Vector3(1.45 * s, 0.12, 0.12), Vector3(0, 1.3 * s, z * s), MAT_WOOD_LIGHT)
	for side in [-1.0, 1.0]:
		var roof := _box(parent, Vector3(1.72 * s, 0.16, 0.98 * s), Vector3(0, 1.55 * s, side * 0.33 * s), MAT_ROOF)
		roof.rotation.x = side * 0.52
	_box(parent, Vector3(0.32, 0.72 * s, 0.08), Vector3(0.25 * s, 0.38 * s, 0.69 * s), MAT_WOOD)
	_box(parent, Vector3(0.26, 0.3, 0.08), Vector3(-0.34 * s, 0.8 * s, 0.7 * s), Color("#9fb4a0"))
	_box(parent, Vector3(0.3, 0.3, 0.08), Vector3(0.62 * s, 0.8 * s, 0.7 * s), Color("#9fb4a0"))
	_box(parent, Vector3(0.22, 0.78 * s, 0.22), Vector3(-0.42 * s, 1.88 * s, -0.28 * s), Color("#8f7964"))


func _make_keep(parent: Node3D) -> void:
	_box(parent, Vector3(2.2, 1.6, 2.0), Vector3(0, 0.85, 0), Color("#b3aa93"))
	for x in [-0.78, 0.78]:
		for z in [-0.72, 0.72]:
			_cylinder(parent, 0.36, 3.2, Vector3(x, 1.65, z), Color("#a59e8b"), 8)
			var roof := _cylinder(parent, 0.54, 1.0, Vector3(x, 3.75, z), MAT_ROOF, 6)
			roof.mesh.top_radius = 0.0
			roof.mesh.bottom_radius = 0.55
	_box(parent, Vector3(1.3, 2.7, 1.12), Vector3(0, 1.4, 0), Color("#c4b99d"))
	var hall_roof := _cylinder(parent, 1.1, 1.2, Vector3(0, 3.15, 0), MAT_ROOF, 4)
	hall_roof.rotation.y = PI / 4.0
	hall_roof.mesh.top_radius = 0.0
	hall_roof.mesh.bottom_radius = 1.05
	_box(parent, Vector3(0.52, 0.85, 0.08), Vector3(0, 0.44, 0.59), MAT_WOOD)


func _make_farm(parent: Node3D) -> void:
	_box(parent, Vector3(1.78, 0.1, 1.78), Vector3(0, 0.03, 0), Color("#866542"))
	for row in range(5):
		var z := -0.68 + row * 0.34
		_box(parent, Vector3(1.58, 0.12, 0.06), Vector3(0, 0.11, z), Color("#bd9862"))
		for plant in range(5):
			_cylinder(parent, 0.07, 0.27, Vector3(-0.58 + plant * 0.29, 0.27, z), Color("#70984d"), 5)
	var house_parent := Node3D.new()
	house_parent.position = Vector3(-0.42, 0, -0.38)
	house_parent.scale = Vector3.ONE * 0.46
	parent.add_child(house_parent)
	_make_house(house_parent, false)


func _make_lumberyard(parent: Node3D) -> void:
	_box(parent, Vector3(1.78, 0.12, 1.78), Vector3(0, 0.04, 0), Color("#8d744d"))
	var shed := Node3D.new()
	shed.position = Vector3(-0.22, 0, -0.2)
	parent.add_child(shed)
	_box(shed, Vector3(0.98, 0.85, 0.88), Vector3(0, 0.47, 0), Color("#9a7550"))
	for side in [-1.0, 1.0]:
		var roof := _box(shed, Vector3(1.15, 0.12, 0.58), Vector3(0, 1.02, side * 0.18), Color("#65432f"))
		roof.rotation.x = side * 0.45
	for i in range(4):
		_cylinder(parent, 0.15, 1.15, Vector3(0.28 + i * 0.1, 0.18 + i * 0.14, 0.52), Color("#b88751"), 8)


func _make_quarry(parent: Node3D) -> void:
	_box(parent, Vector3(1.82, 0.1, 1.82), Vector3(0, 0.02, 0), Color("#8c8b7e"))
	for i in range(9):
		var x := -0.55 + (i % 3) * 0.48
		var z := -0.38 + floori(i / 3.0) * 0.45
		var rock := _sphere(parent, 0.32 + float(i % 2) * 0.07, Vector3(x, 0.32, z), Color("#a9a99d") if i % 2 == 0 else Color("#888d82"))
		rock.scale = Vector3(1.0, 0.7, 0.85)
	var small_shed := Node3D.new()
	small_shed.position = Vector3(0.45, 0, 0.32)
	parent.add_child(small_shed)
	_box(small_shed, Vector3(0.65, 0.56, 0.55), Vector3(0, 0.3, 0), Color("#817767"))


func _make_market(parent: Node3D) -> void:
	_box(parent, Vector3(1.82, 0.12, 1.82), Vector3(0, 0.02, 0), Color("#a38a63"))
	for x in [-0.55, 0.55]:
		for z in [-0.45, 0.45]:
			_box(parent, Vector3(0.1, 1.7, 0.1), Vector3(x, 0.86, z), MAT_WOOD)
	_box(parent, Vector3(1.45, 0.14, 1.18), Vector3(0, 1.65, 0), Color("#d9c89f"))
	for i in range(5):
		_box(parent, Vector3(1.5, 0.06, 0.22), Vector3(0, 1.56, -0.48 + i * 0.24), MAT_ROOF if i % 2 == 0 else Color("#e2d6ba"))
	_box(parent, Vector3(1.3, 0.16, 0.55), Vector3(0, 0.72, 0.54), MAT_WOOD_LIGHT)
	for x in [-0.43, 0, 0.43]:
		_sphere(parent, 0.15, Vector3(x, 0.95, 0.52), Color("#bc7546"))


func _add_village_props() -> void:
	# A ring of orchards and woodland frames the opening settlement.
	for coord in [Vector2(-14, -8), Vector2(-13, -5), Vector2(-14, 4), Vector2(-12, 8), Vector2(13, -8), Vector2(14, -5), Vector2(14, 5), Vector2(12, 8), Vector2(-10, -9), Vector2(10, -9)]:
		_add_prop_tree(Vector3(coord.x, 0, coord.y), 0.82 + float(abs(int(coord.x + coord.y)) % 4) * 0.09)
	for x in [-4.0, 4.0]:
		for z in [-2.0, 2.0]:
			_add_prop_tree(Vector3(x, 0, z), 0.62)


func _add_prop_tree(pos: Vector3, scale_value: float) -> void:
	var cell := _world_to_cell(pos)
	if _inside_grid(cell):
		if buildings.has(cell):
			return
		var tree := _add_tree(pos, scale_value)
		if not decor_by_cell.has(cell):
			decor_by_cell[cell] = []
		decor_by_cell[cell].append(tree)
	else:
		_add_tree(pos, scale_value)


func _add_tree(pos: Vector3, scale_value: float) -> Node3D:
	var tree := Node3D.new()
	tree.position = pos
	tree.scale = Vector3.ONE * scale_value
	world_root.add_child(tree)
	_cylinder(tree, 0.15, 1.55, Vector3(0, 0.78, 0), Color("#654832"), 7)
	var shades := [Color("#496b43"), Color("#5a7b49"), Color("#66864d")]
	for i in range(4):
		var foliage := _sphere(tree, 0.7 - i * 0.06, Vector3(sin(i * 3.2) * 0.25, 1.7 + i * 0.35, cos(i * 2.5) * 0.24), shades[i % shades.size()])
		foliage.scale = Vector3(1.0, 1.1, 1.0)
	return tree


func _add_villagers() -> void:
	var robe_colors := [Color("#774b3d"), Color("#49664c"), Color("#c5a35e"), Color("#5b6471"), Color("#9b6348")]
	for i in range(5):
		var person := Node3D.new()
		person.position = Vector3(-4.8 + i * 2.1, 0.08, 1.4 + sin(i * 2.0) * 0.55)
		world_root.add_child(person)
		_cylinder(person, 0.2, 0.66, Vector3(0, 0.47, 0), robe_colors[i], 7)
		_sphere(person, 0.16, Vector3(0, 0.94, 0), Color("#dbb48f"))
		_cylinder(person, 0.17, 0.16, Vector3(0, 1.08, 0), MAT_WOOD_LIGHT, 8)
		villagers.append(person)


func _cell_center(cell: Vector2i) -> Vector3:
	return grid_anchor + Vector3(cell.x * TILE_SIZE, 0.0, cell.y * TILE_SIZE)


func _world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(floori((pos.x - grid_anchor.x) / TILE_SIZE), floori((pos.z - grid_anchor.z) / TILE_SIZE))


func _inside_grid(cell: Vector2i) -> bool:
	return cell.x >= grid_min.x and cell.x < grid_max.x and cell.y >= grid_min.y and cell.y < grid_max.y


func _build_ground() -> void:
	ground_mesh = BoxMesh.new()
	ground_instance = MeshInstance3D.new()
	ground_instance.mesh = ground_mesh
	ground_instance.material_override = _material(Color("#697f4e"))
	world_root.add_child(ground_instance)
	_resize_ground()


func _build_tiles() -> void:
	for y in range(grid_min.y, grid_max.y):
		for x in range(grid_min.x, grid_max.x):
			_add_tile(Vector2i(x, y))


func _add_tile(cell: Vector2i) -> void:
	var tile := BoxMesh.new()
	tile.size = Vector3(1.98, 0.08, 1.98)
	var tint := MAT_GRASS if posmod(cell.x + cell.y, 3) != 0 else MAT_GRASS_ALT
	var tile_instance := MeshInstance3D.new()
	tile_instance.mesh = tile
	tile_instance.material_override = _material(tint)
	tile_instance.position = _cell_center(cell) + Vector3(0, -0.12, 0)
	world_root.add_child(tile_instance)


func _resize_ground() -> void:
	var width := float(grid_max.x - grid_min.x) * TILE_SIZE + 3.0
	var depth := float(grid_max.y - grid_min.y) * TILE_SIZE + 3.0
	ground_mesh.size = Vector3(width, 0.35, depth)
	ground_instance.position = Vector3(
		grid_anchor.x + float(grid_min.x + grid_max.x - 1) * TILE_SIZE * 0.5,
		-0.35,
		grid_anchor.z + float(grid_min.y + grid_max.y - 1) * TILE_SIZE * 0.5
	)


func _buildable_count() -> int:
	var total := 0
	for y in range(grid_min.y, grid_max.y):
		for x in range(grid_min.x, grid_max.x):
			if not blocked.has(Vector2i(x, y)):
				total += 1
	return total


func _expand_cost() -> Vector2i:
	var level := expansions + 1
	return Vector2i(50 + level * 30, 30 + level * 20)


func _maybe_expand() -> void:
	if expand_pending or expansions >= MAX_EXPANSIONS or buildings.is_empty():
		return
	var capacity := _buildable_count()
	if capacity == 0:
		return
	if float(buildings.size()) / float(capacity) < EXPAND_FILL_RATIO:
		return
	var cost := _expand_cost()
	if gold < cost.x or wood < cost.y:
		expand_pending = true
		_set_message("Земли застроены, но не хватает ресурсов на расширение: %d З / %d Д." % [cost.x, cost.y])
		return
	expand_pending = false
	gold -= cost.x
	wood -= cost.y
	_expand_map()


func _expand_map() -> void:
	var old_min := grid_min
	var old_max := grid_max
	grid_min -= Vector2i.ONE
	grid_max += Vector2i.ONE
	for y in range(grid_min.y, grid_max.y):
		for x in range(grid_min.x, grid_max.x):
			var cell := Vector2i(x, y)
			if cell.x >= old_min.x and cell.x < old_max.x and cell.y >= old_min.y and cell.y < old_max.y:
				continue
			_add_tile(cell)
			_scatter_cell(cell)
	_resize_ground()
	expansions += 1
	_set_message("Королевство расширило границы! Появились новые земли.")
	_update_ui()


func _scatter_cell(cell: Vector2i) -> void:
	var crowded := false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if blocked.has(cell + d):
			crowded = true
			break
	var roll := randf() * (0.45 if crowded else 1.0)
	if roll < 0.06:
		blocked[cell] = "mountain"
		_add_mountain(cell)
	elif roll < 0.13:
		blocked[cell] = "forest"
		_add_forest(cell)
	elif roll < 0.50:
		_add_meadow_decor(cell)


func _add_mountain(cell: Vector2i) -> void:
	var root := Node3D.new()
	root.position = _cell_center(cell)
	world_root.add_child(root)
	var peak := _sphere(root, 0.72, Vector3(-0.28, 0.5, -0.05), Color("#8d8b80"))
	peak.scale = Vector3(1.25, 0.95, 1.05)
	_sphere(root, 0.55, Vector3(0.38, 0.38, 0.28), Color("#7b7a70"))
	var top := _sphere(root, 0.42, Vector3(0.02, 0.95, -0.32), Color("#99978c"))
	top.scale = Vector3(1.0, 0.8, 1.0)
	_sphere(root, 0.2, Vector3(0.02, 1.32, -0.32), Color("#e8e6df"))


func _add_forest(cell: Vector2i) -> void:
	var center := _cell_center(cell)
	var angle := randf() * TAU
	var offset := Vector3(cos(angle) * randf_range(0.2, 0.6), 0.0, sin(angle) * randf_range(0.2, 0.6))
	_add_tree(center + offset, randf_range(0.6, 0.95))


func _add_meadow_decor(cell: Vector2i) -> void:
	var root := Node3D.new()
	root.position = _cell_center(cell)
	world_root.add_child(root)
	var count := 2 + randi() % 3
	var flower_colors := [Color("#d98a9e"), Color("#e6c26a"), Color("#b48ad6"), Color("#e8e6df")]
	for i in range(count):
		var offset := Vector3(randf_range(-0.62, 0.62), 0.0, randf_range(-0.62, 0.62))
		_cylinder(root, 0.02, 0.22, offset + Vector3(0, 0.11, 0), Color("#55713f"), 4)
		var bloom := _sphere(root, 0.07, offset + Vector3(0, 0.26, 0), flower_colors[randi() % flower_colors.size()])
		bloom.scale = Vector3(1.0, 0.6, 1.0)
	decor_by_cell[cell] = [root]
	meadow_cells[cell] = true


func _cursor_ground_position(screen_pos: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var plane := Plane(Vector3.UP, 0.0)
	return plane.intersects_ray(origin, direction)


func _update_hover() -> void:
	var hit: Variant = _cursor_ground_position(get_viewport().get_mouse_position())
	if hit == null:
		hover_marker.visible = false
		return
	var cell := _world_to_cell(hit)
	if not _inside_grid(cell):
		hover_marker.visible = false
		return
	hover_marker.visible = true
	hover_marker.position = _cell_center(cell) + Vector3(0, 0.035, 0)
	if _cell_action_valid(cell):
		hover_material.albedo_color = Color(0.45, 0.9, 0.45, 0.4)
	else:
		hover_material.albedo_color = Color(0.9, 0.35, 0.3, 0.45)


func _cell_action_valid(cell: Vector2i) -> bool:
	if selected_tool == "rotate":
		return buildings.has(cell)
	if selected_tool == "demolish":
		return buildings.has(cell) and buildings[cell] != "keep"
	if blocked.has(cell) or buildings.has(cell):
		return false
	var cost := _cost_for(selected_tool)
	return gold >= cost.x and wood >= cost.y and stone >= cost.z


func _place_building(cell: Vector2i, kind: String) -> void:
	if blocked.has(cell):
		_set_message("Эта земля непригодна для застройки.")
		return
	if buildings.has(cell):
		_set_message("Это место уже занято.")
		return
	var cost := _cost_for(kind)
	if gold < cost.x or wood < cost.y or stone < cost.z:
		_set_message("Не хватает ресурсов для постройки.")
		return
	gold -= cost.x
	wood -= cost.y
	stone -= cost.z
	if decor_by_cell.has(cell):
		for node in decor_by_cell[cell]:
			node.queue_free()
		decor_by_cell.erase(cell)
		meadow_cells.erase(cell)
	_add_building(cell, kind)
	_set_message("Построено: " + TOOL_NAMES[TOOLS.find(kind)].to_lower() + ".")
	_maybe_expand()
	_update_ui()


func _demolish(cell: Vector2i) -> void:
	if not buildings.has(cell) or buildings[cell] == "keep":
		_set_message("Здесь нечего снести.")
		return
	var kind: String = buildings[cell]
	var cost := _cost_for(kind)
	gold += floori(cost.x * 0.25)
	wood += floori(cost.y * 0.25)
	stone += floori(cost.z * 0.25)
	buildings.erase(cell)
	var node: Node3D = building_nodes.get(cell)
	building_nodes.erase(cell)
	if node != null and is_instance_valid(node):
		node.queue_free()
	_set_message("Постройка снесена, часть материалов возвращена.")
	_update_ui()


func _handle_click(screen_pos: Vector2) -> void:
	var hit: Variant = _cursor_ground_position(screen_pos)
	if hit == null:
		return
	var cell := _world_to_cell(hit)
	if not _inside_grid(cell):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var is_double_click := now - last_click_time < 0.4 and cell == last_click_cell
	last_click_time = now
	last_click_cell = cell
	if is_double_click:
		_rotate_building(cell)
	elif selected_tool == "rotate":
		_rotate_building(cell)
	elif selected_tool == "demolish":
		_demolish(cell)
	else:
		_place_building(cell, selected_tool)


func _rotate_building(cell: Vector2i) -> void:
	if not buildings.has(cell):
		_set_message("Здесь нет постройки.")
		return
	var node: Node3D = building_nodes.get(cell)
	if node == null or not is_instance_valid(node):
		return
	node.rotation.y += PI * 0.5
	_set_message("Постройка повёрнута.")


func _cost_for(kind: String) -> Vector3i:
	match kind:
		"house": return Vector3i(35, 20, 0)
		"farm": return Vector3i(25, 15, 0)
		"lumber": return Vector3i(40, 20, 0)
		"quarry": return Vector3i(45, 25, 0)
		"market": return Vector3i(30, 15, 0)
		"road": return Vector3i(2, 0, 0)
		_: return Vector3i.ZERO


func _near_road(cell: Vector2i) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if buildings.get(cell + d) == "road":
			return true
	return false


func _count(kind: String) -> int:
	var result := 0
	for cell in buildings:
		if buildings[cell] == kind:
			result += 1
	return result


func _advance_day() -> void:
	day += 1
	var produced_food := 0
	var produced_wood := 0
	var produced_stone := 0
	var market_income := 0
	for cell in buildings:
		var bonus := 1 if _near_road(cell) else 0
		match buildings[cell]:
			"farm": produced_food += 7 + bonus
			"lumber": produced_wood += 5 + bonus
			"quarry": produced_stone += 3 + bonus
			"market": market_income += 2 + bonus
	food += produced_food
	wood += produced_wood
	stone += produced_stone
	gold += population + market_income
	if food >= population:
		food -= population
		happiness = mini(100, happiness + 1)
	else:
		food = 0
		happiness = maxi(0, happiness - 8)
		_set_message("Не хватает еды! Жители теряют счастье.")
	if day % 3 == 0 and population < 6 + _count("house") * 4 and food >= population + 3:
		food -= 3
		population += 1
		_set_message("В королевстве появился новый житель!")
	_maybe_expand()
	_update_ui()


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _key_to_cell(key: String) -> Vector2i:
	var parts := key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))


func _save_game() -> void:
	var b := {}
	for cell in buildings:
		b[_cell_key(cell)] = buildings[cell]
	var bl := {}
	for cell in blocked:
		bl[_cell_key(cell)] = blocked[cell]
	var md := []
	for cell in meadow_cells:
		md.append(_cell_key(cell))
	var data := {
		"gold": gold, "wood": wood, "stone": stone, "food": food,
		"population": population, "happiness": happiness, "day": day,
		"speed": speed, "running": running, "expansions": expansions,
		"grid_min": [grid_min.x, grid_min.y], "grid_max": [grid_max.x, grid_max.y],
		"buildings": b, "blocked": bl, "meadows": md,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_set_message("Не удалось сохранить игру.")
		return
	file.store_string(JSON.stringify(data))
	file.close()
	_set_message("Игра сохранена.")


func _load_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_set_message("Нет сохранения.")
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(data) != TYPE_DICTIONARY:
		_set_message("Сохранение повреждено.")
		return
	buildings.clear()
	building_nodes.clear()
	blocked.clear()
	decor_by_cell.clear()
	meadow_cells.clear()
	villagers.clear()
	day_timer = 0.0
	expand_pending = false
	for child in world_root.get_children():
		child.queue_free()
	grid_min = Vector2i(int(data["grid_min"][0]), int(data["grid_min"][1]))
	grid_max = Vector2i(int(data["grid_max"][0]), int(data["grid_max"][1]))
	_build_ground()
	_build_tiles()
	for key in data["blocked"]:
		var cell := _key_to_cell(key)
		blocked[cell] = data["blocked"][key]
		if blocked[cell] == "mountain":
			_add_mountain(cell)
		elif blocked[cell] == "forest":
			_add_forest(cell)
	for key in data["meadows"]:
		_add_meadow_decor(_key_to_cell(key))
	for key in data["buildings"]:
		_add_building(_key_to_cell(key), data["buildings"][key])
	_add_village_props()
	_add_villagers()
	gold = int(data["gold"])
	wood = int(data["wood"])
	stone = int(data["stone"])
	food = int(data["food"])
	population = int(data["population"])
	happiness = int(data["happiness"])
	day = int(data["day"])
	expansions = int(data["expansions"])
	speed = int(data["speed"])
	running = bool(data["running"])
	_set_message("Игра загружена.")
	_update_ui()


func _toggle_pause() -> void:
	running = not running
	_update_ui()


func _toggle_speed() -> void:
	speed = 2 if speed == 1 else 1
	_update_ui()


func _select_tool(tool: String) -> void:
	selected_tool = tool
	_set_message("Выбран инструмент: " + TOOL_NAMES[TOOLS.find(tool)].to_lower() + ".")
	_update_ui()


func _set_message(value: String) -> void:
	message = value
	if is_instance_valid(message_label):
		message_label.text = value


func _resource_help(resource: String) -> String:
	match resource:
		"gold": return "Золото: ежедневный налог с жителей. Каждый рынок добавляет +2 золота в день."
		"wood": return "Дерево производит лесопилка: +5 в день за каждую."
		"stone": return "Камень производит каменоломня: +3 в день за каждую."
		"food": return "Еду производит ферма: +7 в день. Каждый житель съедает 1 еду в день."
	return "Ресурс поселения."


func _tool_help(tool: String) -> String:
	match tool:
		"house": return "Дом добавляет 4 места для жителей. Новые жители приходят при запасе еды."
		"farm": return "Источник еды: производит 7 еды в день. Житель съедает 1 еду в день."
		"lumber": return "Источник дерева: производит 5 дерева в день."
		"quarry": return "Источник камня: производит 3 камня в день."
		"market": return "Источник золота: приносит 2 золота в день. Жители также платят налог."
		"road": return "Дорога: здания рядом с дорогой добывают на +1 больше в день."
		"rotate": return "Повернуть постройку на 90°. Кликни по готовому зданию."
		"demolish": return "Снести постройку и вернуть 25% её стоимости."
	return ""


func _update_ui() -> void:
	if not is_instance_valid(ui):
		return
	resource_labels["gold"].text = str(gold)
	resource_labels["wood"].text = str(wood)
	resource_labels["stone"].text = str(stone)
	resource_labels["food"].text = str(food)
	stats_labels["day"].text = "%02d" % day
	stats_labels["population"].text = "%d / %d мест" % [population, 6 + _count("house") * 4]
	stats_labels["happiness"].text = "%d%%" % happiness
	stats_labels["production"].text = "Золото +%d/день — налог, рынок\nДерево +%d/день — лесопилка\nКамень +%d/день — каменоломня\nЕда +%d/день — ферма\nЗдания у дорог: +1 бонус.\nЖитель съедает 1 еды в день." % [population + _count("market") * 2, _count("lumber") * 5, _count("quarry") * 3, _count("farm") * 7]
	stats_labels["buildings"].text = "Дома: %d\nФермы: %d\nРынки: %d\nДороги: %d" % [_count("house"), _count("farm"), _count("market"), _count("road")]
	var map_w := grid_max.x - grid_min.x
	var map_h := grid_max.y - grid_min.y
	var capacity := _buildable_count()
	var fill_pct := 0.0 if capacity == 0 else float(buildings.size()) / float(capacity) * 100.0
	var expand_text := "Максимальный размер" if expansions >= MAX_EXPANSIONS else "%d З / %d Д" % [_expand_cost().x, _expand_cost().y]
	stats_labels["territory"].text = "Карта %d × %d\nЗастроено %d / %d (%.0f%%)\nРасширение: %s" % [map_w, map_h, buildings.size(), capacity, fill_pct, expand_text]
	for i in range(TOOLS.size()):
		var button := ui.get_node_or_null("BuildPanel/BuildButton%d" % i)
		if button is Button:
			button.modulate = Color("#fff0ba") if selected_tool == TOOLS[i] else Color.WHITE
	for button in ui.find_children("", "Button", true, false):
		if button.text.begins_with("Ⅱ") or button.text.begins_with("▶"):
			button.text = "Ⅱ  ПАУЗА" if running else "▶  ДАЛЬШЕ"
		elif button.text.begins_with("СКОРОСТЬ"):
			button.text = "СКОРОСТЬ  x%d" % speed

