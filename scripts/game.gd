extends Node2D

const GRID_WIDTH := 16
const GRID_HEIGHT := 10
const TILE_SIZE := 48
const BOARD_ORIGIN := Vector2(250, 130)
const DAY_LENGTH := 5.0
const TOOLS := ["house", "farm", "lumber", "quarry", "road", "demolish"]
const TOOL_NAMES := ["ДОМИК", "ФЕРМА", "ЛЕСОПИЛКА", "КАМЕНОЛОМНЯ", "ДОРОГА", "СНЕСТИ"]
const TOOL_HINTS := ["Жильё +4", "Еда +7 в день", "Дерево +5 в день", "Камень +3 в день", "Соединяет кварталы", "Вернуть часть затрат"]
const TOOL_COSTS := ["35 З 20 Д", "25 З 15 Д", "40 З 20 Д", "45 З 25 Д", "2 З", "БЕСПЛАТНО"]

const INK := Color("#26372e")
const MUTED := Color("#657468")
const PAPER := Color("#f5edda")
const PAPER_DARK := Color("#e9dec4")
const GREEN := Color("#58784e")
const GREEN_LIGHT := Color("#83a46c")
const GOLD := Color("#e5b94e")
const RED := Color("#bd654e")

var font: Font
var buildings: Dictionary = {}
var selected_tool := "house"
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
var message := "Построй ферму, чтобы запасти еду."
var message_timer := 8.0


func _ready() -> void:
	font = ThemeDB.fallback_font
	buildings[Vector2i(7, 4)] = "keep"
	buildings[Vector2i(7, 5)] = "road"
	buildings[Vector2i(8, 5)] = "road"
	buildings[Vector2i(9, 5)] = "road"
	buildings[Vector2i(9, 4)] = "road"
	queue_redraw()


func _process(delta: float) -> void:
	if running:
		day_timer += delta * speed
		while day_timer >= DAY_LENGTH:
			day_timer -= DAY_LENGTH
			_advance_day()
	if message_timer > 0.0:
		message_timer -= delta
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_click(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			running = not running
			_set_message("Симуляция " + ("запущена." if running else "на паузе."))
		elif event.keycode == KEY_1:
			speed = 1
		elif event.keycode == KEY_2:
			speed = 2
		queue_redraw()


func _draw() -> void:
	_draw_background()
	_draw_header()
	_draw_toolbar()
	_draw_board()
	_draw_kingdom_panel()
	_draw_footer()


func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color("#d9d4bd"), true)
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 88)), Color("#283c32"), true)
	draw_rect(Rect2(Vector2(0, 86), Vector2(1280, 3)), Color("#d0a853"), true)


func _draw_header() -> void:
	_draw_text("TINY KINGDOM", 28, 35, 13, Color("#c9d5be"))
	_draw_text("МАЛЕНЬКОЕ КОРОЛЕВСТВО", 28, 62, 23, PAPER)
	_draw_text("ЗОЛОТО", 275, 30, 10, Color("#c9d5be"))
	_draw_text("%d" % gold, 275, 61, 22, GOLD)
	_draw_text("ДЕРЕВО", 415, 30, 10, Color("#c9d5be"))
	_draw_text("%d" % wood, 415, 61, 22, Color("#d8b887"))
	_draw_text("КАМЕНЬ", 555, 30, 10, Color("#c9d5be"))
	_draw_text("%d" % stone, 555, 61, 22, Color("#d3d8d0"))
	_draw_text("ЕДА", 695, 30, 10, Color("#c9d5be"))
	_draw_text("%d" % food, 695, 61, 22, Color("#f0bd79"))
	_draw_line(Vector2(795, 22), Vector2(795, 67), Color("#53675a"), 1)
	_draw_text("ДЕНЬ %02d" % day, 825, 43, 15, PAPER)
	_draw_text("СКОРОСТЬ x%d" % speed, 825, 64, 11, Color("#c9d5be"))
	var status_color := GREEN_LIGHT if running else GOLD
	_draw_circle(Vector2(1100, 40), 5, status_color)
	_draw_text("МИРНАЯ ЖИЗНЬ" if running else "ПАУЗА", 1115, 45, 12, PAPER)


func _draw_toolbar() -> void:
	_draw_panel(Rect2(18, 108, 210, 570), Color("#f5edda"))
	_draw_text("СТРОИТЕЛЬСТВО", 32, 139, 15, INK)
	_draw_text("Выбери постройку", 32, 156, 11, MUTED)
	for i in range(TOOLS.size()):
		var y := 170.0 + i * 70.0
		var selected: bool = selected_tool == String(TOOLS[i])
		var card_color := Color("#dce6cf") if selected else Color("#fffaf0")
		_draw_panel(Rect2(28, y, 190, 61), card_color, selected)
		_draw_circle(Vector2(49, y + 30), 10, _tool_color(TOOLS[i]))
		_draw_text(_tool_letter(TOOLS[i]), 45, y + 34, 12, Color.WHITE)
		_draw_text(TOOL_NAMES[i], 67, y + 25, 11, INK)
		_draw_text(TOOL_COSTS[i], 67, y + 43, 10, MUTED)
	_draw_text("ЛКМ — построить", 32, 609, 10, MUTED)
	_draw_text("Пробел — пауза", 32, 628, 10, MUTED)
	_draw_text("Клавиши 1 / 2 — скорость", 32, 647, 10, MUTED)


func _draw_board() -> void:
	var board_rect := Rect2(BOARD_ORIGIN - Vector2(7, 7), Vector2(GRID_WIDTH * TILE_SIZE, GRID_HEIGHT * TILE_SIZE) + Vector2(14, 14))
	draw_rect(board_rect, Color("#49594c"), true)
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			var cell := Vector2i(x, y)
			var rect := _cell_rect(cell)
			draw_rect(rect, _grass_color(cell), true)
			if (x * 11 + y * 7) % 9 == 0 and not buildings.has(cell):
				_draw_circle(rect.position + Vector2(12, 35), 1.5, Color("#9eaf77"))
				draw_line(rect.position + Vector2(15, 36), rect.position + Vector2(17, 33), Color("#9eaf77"), 1)
			draw_rect(rect, Color("#ffffff", 0.13), false, 1)
	for cell in buildings:
		_draw_building(cell, buildings[cell])
	var hovered := _screen_to_cell(get_global_mouse_position())
	if _inside_board(get_global_mouse_position()):
		draw_rect(_cell_rect(hovered), Color("#fff3b4", 0.55), false, 2)


func _draw_building(cell: Vector2i, kind: String) -> void:
	var r := _cell_rect(cell)
	var p := r.position
	_draw_ellipse(Rect2(p + Vector2(7, 34), Vector2(34, 9)), Color("#344535", 0.32))
	match kind:
		"keep":
			_draw_rect(Rect2(p + Vector2(10, 17), Vector2(28, 25)), Color("#d6bd8b"))
			_draw_rect(Rect2(p + Vector2(13, 10), Vector2(7, 11)), Color("#d6bd8b"))
			_draw_rect(Rect2(p + Vector2(28, 10), Vector2(7, 11)), Color("#d6bd8b"))
			_draw_rect(Rect2(p + Vector2(12, 8), Vector2(9, 4)), Color("#a65b45"))
			_draw_rect(Rect2(p + Vector2(27, 8), Vector2(9, 4)), Color("#a65b45"))
			_draw_rect(Rect2(p + Vector2(21, 26), Vector2(7, 16)), Color("#754d38"))
			_draw_rect(Rect2(p + Vector2(15, 23), Vector2(5, 5)), Color("#91b9a0"))
			_draw_rect(Rect2(p + Vector2(28, 23), Vector2(5, 5)), Color("#91b9a0"))
		"house":
			_draw_rect(Rect2(p + Vector2(9, 22), Vector2(30, 21)), Color("#e5d1a6"))
			draw_colored_polygon(PackedVector2Array([p + Vector2(6, 24), p + Vector2(24, 9), p + Vector2(42, 24)]), Color("#b95f48"))
			_draw_rect(Rect2(p + Vector2(21, 31), Vector2(7, 12)), Color("#79523b"))
			_draw_rect(Rect2(p + Vector2(12, 27), Vector2(6, 6)), Color("#91b9a0"))
			_draw_rect(Rect2(p + Vector2(30, 27), Vector2(6, 6)), Color("#91b9a0"))
		"farm":
			_draw_rect(Rect2(p + Vector2(5, 9), Vector2(38, 34)), Color("#9a7442"))
			for i in range(4):
				var row_y := 15.0 + i * 7.0
				draw_line(p + Vector2(8, row_y), p + Vector2(40, row_y), Color("#dfbb75"), 2)
				for j in range(4):
					_draw_circle(p + Vector2(12 + j * 8, row_y - 2), 1.5, Color("#9cbc69"))
		"lumber":
			_draw_rect(Rect2(p + Vector2(10, 22), Vector2(28, 20)), Color("#a7794e"))
			_draw_rect(Rect2(p + Vector2(8, 19), Vector2(32, 6)), Color("#754d38"))
			_draw_rect(Rect2(p + Vector2(12, 42), Vector2(24, 2)), Color("#d0a56b"))
			_draw_circle(p + Vector2(34, 15), 6, Color("#567c50"))
			_draw_rect(Rect2(p + Vector2(33, 18), Vector2(3, 8)), Color("#76533b"))
		"quarry":
			_draw_circle(p + Vector2(16, 30), 9, Color("#9ca49b"))
			_draw_circle(p + Vector2(29, 24), 12, Color("#c4c8ba"))
			_draw_circle(p + Vector2(35, 34), 7, Color("#858e83"))
			_draw_line(p + Vector2(10, 39), p + Vector2(38, 39), Color("#665a43"), 2)
		"road":
			_draw_rect(Rect2(p + Vector2(1, 1), Vector2(46, 46)), Color("#987b55"))
			draw_line(p + Vector2(5, 24), p + Vector2(43, 24), Color("#ad916b"), 2)


func _draw_kingdom_panel() -> void:
	_draw_panel(Rect2(1035, 108, 227, 570), Color("#f5edda"))
	_draw_text("КОРОЛЕВСТВО", 1052, 139, 15, INK)
	_draw_text("ДЕНЬ %02d" % day, 1052, 172, 12, MUTED)
	_draw_text("ЖИТЕЛИ", 1052, 205, 10, MUTED)
	_draw_text("%d" % population, 1052, 236, 26, INK)
	_draw_text("/ %d мест" % _housing_capacity(), 1085, 235, 11, MUTED)
	_draw_text("СЧАСТЬЕ", 1052, 267, 10, MUTED)
	_draw_rect(Rect2(1052, 278, 190, 8), Color("#d8d3c2"))
	_draw_rect(Rect2(1052, 278, 190.0 * happiness / 100.0, 8), Color("#83a46c"))
	_draw_text("%d%%" % happiness, 1052, 305, 12, INK)
	_draw_line(Vector2(1052, 326), Vector2(1244, 326), Color("#d8d0bd"), 1)
	_draw_text("РЕСУРСЫ", 1052, 350, 10, MUTED)
	_draw_text("Еда", 1052, 377, 12, INK)
	_draw_text("%d" % food, 1210, 377, 13, INK)
	_draw_text("Прирост за день", 1052, 405, 10, MUTED)
	_draw_text("+%d еды" % _daily_food(), 1052, 425, 12, GREEN)
	_draw_text("+%d дерева" % _daily_wood(), 1052, 446, 12, Color("#987047"))
	_draw_text("+%d камня" % _daily_stone(), 1052, 467, 12, Color("#68766d"))
	_draw_text("+%d золота" % population, 1052, 488, 12, Color("#9a762a"))
	_draw_line(Vector2(1052, 508), Vector2(1244, 508), Color("#d8d0bd"), 1)
	_draw_text("ПОСТРОЙКИ", 1052, 532, 10, MUTED)
	_draw_text("Домов: %d" % _count_buildings("house"), 1052, 554, 11, INK)
	_draw_text("Ферм: %d" % _count_buildings("farm"), 1052, 573, 11, INK)
	_draw_text("Мастерских: %d" % (_count_buildings("lumber") + _count_buildings("quarry")), 1052, 592, 11, INK)
	var button_color := Color("#dce6cf") if running else Color("#f1dfaa")
	_draw_panel(Rect2(1052, 616, 190, 42), button_color, true)
	_draw_text("ПАУЗА" if running else "ПРОДОЛЖИТЬ", 1083, 643, 12, INK)
	_draw_text("x%d" % speed, 1204, 643, 12, GREEN)


func _draw_footer() -> void:
	_draw_panel(Rect2(250, 637, 768, 41), Color("#eee5d1"))
	var color := RED if message_timer > 0.0 and message.begins_with("Не") else MUTED
	_draw_text(message, 266, 662, 12, color)
	_draw_text("День длится 5 секунд", 825, 662, 10, MUTED)


func _draw_panel(rect: Rect2, color: Color, highlighted := false) -> void:
	draw_rect(Rect2(rect.position + Vector2(2, 3), rect.size), Color("#29372c", 0.13), true)
	draw_rect(rect, color, true)
	draw_rect(rect, Color("#c5bda9") if not highlighted else Color("#789267"), false, 1)


func _draw_text(value: String, x: float, y: float, size: int, color: Color = INK) -> void:
	if font != null:
		draw_string(font, Vector2(x, y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw_rect(rect: Rect2, color: Color) -> void:
	draw_rect(rect, color, true)


func _draw_circle(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center, radius, color)


func _draw_line(from: Vector2, to: Vector2, color: Color, width: float = 1.0) -> void:
	draw_line(from, to, color, width)


func _draw_ellipse(rect: Rect2, color: Color) -> void:
	for i in range(9):
		var x := rect.position.x + 2.0 + i * 3.75
		var inset := absf(4.0 - i) * 1.5
		draw_line(Vector2(x, rect.position.y + inset), Vector2(x, rect.position.y + rect.size.y - inset), color, 1)


func _grass_color(cell: Vector2i) -> Color:
	var pattern := (cell.x * 13 + cell.y * 5) % 7
	if pattern == 0:
		return Color("#91a66f")
	if pattern == 1:
		return Color("#849c67")
	return Color("#8ba36c")


func _tool_color(tool: String) -> Color:
	match tool:
		"house": return Color("#b95f48")
		"farm": return Color("#bd9a55")
		"lumber": return Color("#8b6545")
		"quarry": return Color("#89938a")
		"road": return Color("#987b55")
		_: return RED


func _tool_letter(tool: String) -> String:
	match tool:
		"house": return "Д"
		"farm": return "Ф"
		"lumber": return "Л"
		"quarry": return "К"
		"road": return "П"
		_: return "×"


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(BOARD_ORIGIN + Vector2(cell.x * TILE_SIZE, cell.y * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE))


func _inside_board(point: Vector2) -> bool:
	return point.x >= BOARD_ORIGIN.x and point.y >= BOARD_ORIGIN.y and point.x < BOARD_ORIGIN.x + GRID_WIDTH * TILE_SIZE and point.y < BOARD_ORIGIN.y + GRID_HEIGHT * TILE_SIZE


func _screen_to_cell(point: Vector2) -> Vector2i:
	return Vector2i(floori((point.x - BOARD_ORIGIN.x) / TILE_SIZE), floori((point.y - BOARD_ORIGIN.y) / TILE_SIZE))


func _handle_click(point: Vector2) -> void:
	if point.x >= 28 and point.x <= 218 and point.y >= 170 and point.y < 170 + TOOLS.size() * 70:
		var index := floori((point.y - 170) / 70)
		if index >= 0 and index < TOOLS.size():
			selected_tool = TOOLS[index]
			_set_message("Выбрано: " + TOOL_NAMES[index].to_lower() + ".")
			return
	if Rect2(1052, 616, 190, 42).has_point(point):
		if point.x > 1170:
			speed = 2 if speed == 1 else 1
		else:
			running = not running
			_set_message("Симуляция " + ("запущена." if running else "на паузе."))
		return
	if _inside_board(point):
		var cell := _screen_to_cell(point)
		if selected_tool == "demolish":
			_demolish(cell)
		else:
			_place_building(cell, selected_tool)


func _place_building(cell: Vector2i, kind: String) -> void:
	if buildings.has(cell):
		_set_message("Не удалось: клетка уже занята.")
		return
	var cost := _cost_for(kind)
	if gold < cost.x or wood < cost.y or stone < cost.z:
		_set_message("Не хватает ресурсов для постройки.")
		return
	gold -= cost.x
	wood -= cost.y
	stone -= cost.z
	buildings[cell] = kind
	_set_message("Построено: " + TOOL_NAMES[TOOLS.find(kind)].to_lower() + ".")


func _demolish(cell: Vector2i) -> void:
	if not buildings.has(cell) or buildings[cell] == "keep":
		_set_message("Не удалось: здесь нечего снести.")
		return
	var kind: String = buildings[cell]
	var cost := _cost_for(kind)
	gold += floori(cost.x * 0.25)
	wood += floori(cost.y * 0.25)
	stone += floori(cost.z * 0.25)
	buildings.erase(cell)
	_set_message("Постройка снесена. Часть материалов возвращена.")


func _cost_for(kind: String) -> Vector3i:
	match kind:
		"house": return Vector3i(35, 20, 0)
		"farm": return Vector3i(25, 15, 0)
		"lumber": return Vector3i(40, 20, 0)
		"quarry": return Vector3i(45, 25, 0)
		"road": return Vector3i(2, 0, 0)
		_: return Vector3i.ZERO


func _advance_day() -> void:
	day += 1
	var food_produced := _daily_food()
	var wood_produced := _daily_wood()
	var stone_produced := _daily_stone()
	food += food_produced
	wood += wood_produced
	stone += stone_produced
	gold += population
	if food >= population:
		food -= population
		happiness = mini(100, happiness + 1)
	else:
		food = 0
		happiness = maxi(0, happiness - 8)
		_set_message("Не хватает еды! Жители теряют счастье.")
	if day % 3 == 0 and population < _housing_capacity() and food >= population + 3:
		food -= 3
		population += 1
		_set_message("В королевстве появился новый житель!")
	elif message_timer <= 0.0:
		_set_message("День %d: +%d еды, +%d дерева, +%d камня." % [day, food_produced, wood_produced, stone_produced])
	queue_redraw()


func _daily_food() -> int:
	return _count_buildings("farm") * 7


func _daily_wood() -> int:
	return _count_buildings("lumber") * 5


func _daily_stone() -> int:
	return _count_buildings("quarry") * 3


func _housing_capacity() -> int:
	return 6 + _count_buildings("house") * 4


func _count_buildings(kind: String) -> int:
	var count := 0
	for cell in buildings:
		if buildings[cell] == kind:
			count += 1
	return count


func _set_message(value: String) -> void:
	message = value
	message_timer = 5.0
