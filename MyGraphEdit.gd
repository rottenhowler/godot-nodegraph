tool
class_name MyGraphEdit
extends Control

enum SelectionMode {NORMAL, ADDITIVE, SUBTRACTIVE}

var _top_layer: CanvasItem
var _scroll_offset: Vector2 = Vector2()

var _port_filter_settings_pool = PortFilterSettingsPool.new()
var _connecting_port: PortInfo = null
var _connecting_curve: Curve2D

var _selected_nodes: Array = []
var _last_pressed_node: MyGraphNode = null
var _dragging: bool = false
var _distance_dragged: int = 0
var _panning: bool = false
var _box_selecting: bool = false
var _box_selection_mode: int = SelectionMode.NORMAL setget _set_box_selection_mode
var _box_select_start: Vector2
var _box_select_end: Vector2

class Connection:
	var source_node: MyGraphNode
	var source_port: int
	var destination_node: MyGraphNode
	var destination_port: int
	
	var _curve: Curve2D
	
	func _init(source_node: MyGraphNode, source_port: int, destination_node: MyGraphNode, destination_port: int):
		self.source_node = source_node
		self.source_port = source_port
		self.destination_node = destination_node
		self.destination_port = destination_port
		
		self._curve = Curve2D.new()
		self._curve.add_point(Vector2())
		self._curve.add_point(Vector2())
		self.update_curve()

	func update_curve() -> void:
		_curve.set_point_position(0, source_node.get_port_position(source_port))
		_curve.set_point_out(0, source_node.get_port_control_point(source_port))
		_curve.set_point_position(1, destination_node.get_port_position(destination_port))
		_curve.set_point_in(1, destination_node.get_port_control_point(destination_port))

class MyGraphNodeIterator:
	var graph_edit: MyGraphEdit
	var index: int
	
	func _init(graph_edit: MyGraphEdit):
		self.graph_edit = graph_edit
	
	func _advance() -> bool:
		while index < graph_edit.get_child_count():
			if graph_edit.get_child(index) is MyGraphNode:
				return true
			index += 1
		return false
	
	func _iter_init(arg) -> bool:
		index = 0
		return _advance()
	
	func _iter_next(arg) -> bool:
		index += 1
		return _advance()
	
	func _iter_get(arg):
		return graph_edit.get_child(index)

class SelectedNodesIterator:
	var iterator
	func _init(node_iterator):
		iterator = node_iterator
	
	func _advance() -> bool:
		while true:
			if iterator._iter_get(null).selected:
				break
			if !iterator._iter_next(null):
				return false
		return true
	
	func _iter_init(arg) -> bool:
		if !iterator._iter_init(arg):
			return false
		return _advance()
	
	func _iter_next(arg) -> bool:
		if !iterator._iter_next(arg):
			return false
		return _advance()
	
	func _iter_get(arg):
		return iterator._iter_get(arg)
	
var connections: Array = []

func _init():
	_top_layer = Control.new()
	_top_layer.connect("draw", self, "_top_layer_draw")
	_top_layer.set_anchors_preset(Control.PRESET_WIDE)
	_top_layer.mouse_filter = MOUSE_FILTER_PASS
	add_child(_top_layer)

func _enter_tree() -> void:
	connect("child_entered_tree", self, "_on_child_entered_tree")
	connect("child_exiting_tree", self, "_on_child_exiting_tree")

func _ready() -> void:
	_selected_nodes = []
	_dragging = false
	_panning = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	_connecting_curve = Curve2D.new()
	_connecting_curve.add_point(Vector2())
	_connecting_curve.add_point(Vector2())

func _make_transparent(color: Color, amount: float) -> Color:
	return Color(color.r, color.g, color.b, amount)

func _draw() -> void:
	_top_layer.raise()
	
	var stylebox = StyleBoxFlat.new()
#	draw_style_box(stylebox, Rect2(rect_position, rect_size))

	for connection in connections:
		draw_polyline(connection._curve.get_baked_points(), connection.source_node.get_port_color(connection.source_port), 2.0, true)

	if _connecting_port:
		draw_polyline(_connecting_curve.get_baked_points(), _connecting_port.node.get_port_color(_connecting_port.index), 2.0, true)

func _top_layer_draw() -> void:
	if _box_selecting:
		var box_color = Color.white
		match _box_selection_mode:
			SelectionMode.NORMAL:
				pass
			SelectionMode.ADDITIVE:
				box_color = Color.green
			SelectionMode.SUBTRACTIVE:
				box_color = Color.red
		
		var stylebox_boxselect = StyleBoxFlat.new()
		stylebox_boxselect.bg_color = _make_transparent(box_color, 0.1)
		stylebox_boxselect.border_color = _make_transparent(box_color, 0.3)
		stylebox_boxselect.set_border_width_all(1.0)
		_top_layer.draw_style_box(stylebox_boxselect, _get_selection_box())

func _on_child_entered_tree(child: Node) -> void:
	if !(child is MyGraphNode):
		return
	
	child.connect("item_rect_changed", self, "_on_node_rect_changed", [child])
#	child.connect("port_added", self, "_on_node_port_added")
	child.connect("port_removed", self, "_on_node_port_removed")
#	child.connect("port_updated", self, "_on_node_port_updated")
#	child.connect("resized", self, "_on_node_resized", [child])
	
	# TODO: register node bounding box
	# TODO: register all node ports

func _on_child_exiting_tree(child: Node) -> void:
	if !(child is MyGraphNode):
		return
	
	child.disconnect("item_rect_changed", self, "_on_node_rect_changed")
#	child.disconnect("port_added", self, "_on_node_port_added")
	child.disconnect("port_removed", self, "_on_node_port_removed")
#	child.disconnect("port_updated", self, "_on_node_port_updated")
#	child.disconnect("resized", self, "_on_node_resized")

	for connection in get_node_connections(child):
		remove_connection(connection)
	# TODO: unregister node bounding box
	# TODO: unregister all node ports

#func _on_node_port_added(node: MyGraphNode, port) -> void:
#	# TODO: register port
#	pass
#
func _on_node_port_removed(node: MyGraphNode, index: int) -> void:
	for connection in get_node_connections(node):
		if connection.source_port != index and connection.destination_port != index:
			continue
		connections.erase(connection)

#func _on_node_port_updated(node: MyGraphNode, port) -> void:
#	# TODO: update port
#	pass
#
#func _on_node_resized(node: Control) -> void:
#	# TODO: update node bounding box
#	pass

func _on_node_rect_changed(node: MyGraphNode) -> void:
	for connection in connections:
		if connection.source_node != node and connection.destination_node != node:
			continue
		
		connection.update_curve()

func _set_box_selection_mode(mode: int) -> void:
	print("Set box selection mode to ", mode)
	if _box_selection_mode == mode:
		return
	_box_selection_mode = mode
	_top_layer.update()
	update()

func _get_selection_box() -> Rect2:
	var xs = [_box_select_start.x, _box_select_end.x]
	var ys = [_box_select_start.y, _box_select_end.y]
	xs.sort()
	ys.sort()
	return Rect2(xs[0], ys[0], xs[1] - xs[0], ys[1] - ys[0])

func get_nodes():
	return MyGraphNodeIterator.new(self)

func get_selected_nodes():
	return SelectedNodesIterator.new(get_nodes())

func _find_node_at_position(position: Vector2) -> MyGraphNode:
	for node in get_nodes():
		if node.get_rect().has_point(position):
			return node
		
	return null

class PortInfo:
	var node: MyGraphNode
	var index: int

class PortFilterSettings:
	var threshold: int
	var enabled: bool
	var connect_from: int
	
	func _init():
		reset()
	
	func reset() -> void:
		threshold = 10
		enabled = true
		connect_from = -1

class PortFilterSettingsPool:
	var available: Array
	func _init():
		available = [PortFilterSettings.new()]
	
	func acquire() -> PortFilterSettings:
		if available.size() == 0:
			available.push_back(PortFilterSettings.new())
		return available.pop_back()
	
	func release(settings: PortFilterSettings) -> void:
		settings.reset()
		available.push_back(settings)

func _find_port_at_position(position: Vector2, filter: PortFilterSettings) -> PortInfo:
	var best_port = PortInfo.new()
	var best_distance = -1

	for node in get_nodes():
		for i in node.port_count:
			if filter.enabled and !node.get_port_enabled(i):
				continue
			
			var port_position = node.get_port_position(i)
			var distance = (port_position - position).length()
			if best_distance == -1 or distance < best_distance:
				best_port.node = node
				best_port.index = i
				best_distance = distance
		
	if best_distance == -1 or best_distance > filter.threshold:
		return null
		
	return best_port

func _unhandled_input(event):
	if _box_selecting and event is InputEventKey:
		# Massage modifier keys
		if event.scancode == KEY_ALT:
			event.alt = event.pressed
		elif event.scancode == KEY_SHIFT:
			event.shift = event.pressed
		
		var mode = _box_selection_mode
		if mode == SelectionMode.ADDITIVE and !event.shift:
			mode = SelectionMode.NORMAL
		elif mode == SelectionMode.SUBTRACTIVE and !event.alt:
			mode = SelectionMode.NORMAL
		
		if mode == SelectionMode.NORMAL:
			if event.alt:
				mode = SelectionMode.SUBTRACTIVE
			elif event.shift:
				mode = SelectionMode.ADDITIVE
		
		_set_box_selection_mode(mode)

func _gui_input(event):
	if _connecting_port:
		if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and !event.pressed:
			var settings = _port_filter_settings_pool.acquire()
			settings.enabled = true
			var port_info = _find_port_at_position(event.position + _scroll_offset, settings)
			_port_filter_settings_pool.release(settings)
			if port_info and port_info.node != _connecting_port.node and port_info.node.get_port_type(port_info.index) != _connecting_port.node.get_port_type(_connecting_port.index):
				connect_nodes(_connecting_port.node, _connecting_port.index, port_info.node, port_info.index)
			
			_connecting_port = null
			accept_event()
			update()
		elif event is InputEventMouseMotion:
			var position = event.position + _scroll_offset
			
			var settings = _port_filter_settings_pool.acquire()
			settings.enabled = true
			var port_info = _find_port_at_position(position, settings)
			_port_filter_settings_pool.release(settings)
			if port_info and port_info.node != _connecting_port.node and port_info.node.get_port_type(port_info.index) != _connecting_port.node.get_port_type(_connecting_port.index):
				_connecting_curve.set_point_position(1, port_info.node.get_port_position(port_info.index))
				_connecting_curve.set_point_in(1, port_info.node.get_port_control_point(port_info.index))
			else:
				_connecting_curve.set_point_position(1, position)
				var control = _connecting_curve.get_point_out(0)
				var direction = position - _connecting_curve.get_point_position(0)
				
				if control.dot(direction) >= 0:
					_connecting_curve.set_point_in(1, -_connecting_curve.get_point_out(0))
				else:
					_connecting_curve.set_point_in(1, _connecting_curve.get_point_out(0))
			
			update()
		return
	
	if _box_selecting:
		if event is InputEventMouseMotion:
			_box_select_end = event.position + _scroll_offset
			_top_layer.update()
			update()
		elif event is InputEventMouseButton and event.button_index == BUTTON_LEFT and !event.pressed:
			# TODO: box selection
			_box_selecting = false
			var box = _get_selection_box()
			if event.alt:
				for node in get_nodes():
					if !box.encloses(node.get_rect()):
						continue
					if !_selected_nodes.has(node):
						continue
					_selected_nodes.erase(node)
					node.selected = false
			else:
				if !event.shift:
					for node in get_selected_nodes():
						node.selected = false
					_selected_nodes = []
				for node in get_nodes():
					if !box.encloses(node.get_rect()):
						continue
					if node.selected:
						continue
					_selected_nodes.push_back(node)
					node.selected = true
			_top_layer.update()
			update()
			accept_event()
	
	if _dragging:
		if event is InputEventMouseMotion:
			_distance_dragged += event.relative.length()
			if _last_pressed_node:
				if !_selected_nodes.has(_last_pressed_node):
					if event.shift:
						_selected_nodes.push_back(_last_pressed_node)
						_last_pressed_node.selected = true
					else:
						for node in get_selected_nodes():
							node.selected = false
						_last_pressed_node.selected = true
						_selected_nodes = [_last_pressed_node]
				_last_pressed_node = null
			
			for node in get_selected_nodes():
				node.rect_position += event.relative
				for connection in get_node_connections(node):
					connection.update_curve()
			update()
		elif event is InputEventMouseButton and event.button_index == BUTTON_LEFT and !event.pressed:
			if _last_pressed_node and _distance_dragged == 0:
				# It was a click on a node
				if event.shift:
					if _selected_nodes.has(_last_pressed_node):
						_selected_nodes.erase(_last_pressed_node)
						_last_pressed_node.selected = false
					else:
						_selected_nodes.push_back(_last_pressed_node)
						_last_pressed_node.selected = true
				else:
					for selected_node in get_selected_nodes():
						selected_node.selected = false
					_last_pressed_node.selected = true
					_selected_nodes = [_last_pressed_node]
				_last_pressed_node = null
			
			_dragging = false
			accept_event()
			update()
		return
	
	if _panning:
		if event is InputEventMouseMotion:
			# _scroll_offset += event.relative
			for child in get_nodes():
				child.rect_position += event.relative
			update()
		elif event is InputEventMouseButton and event.button_index == BUTTON_MIDDLE and !event.pressed:
			_panning = false
			accept_event()
			update()
		return
		
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed:
		var position = event.position + _scroll_offset
		
		var settings = _port_filter_settings_pool.acquire()
		settings.enabled = true
		var port_info = _find_port_at_position(position, settings)
		_port_filter_settings_pool.release(settings)
		
		if port_info:
			# Clicked on a port, start connection
			var conns = get_destination_node_connections(port_info.node, port_info.index)
			if conns.size() > 0:
				# There are already connections ending at this port.
				# Disconnect one of them and start connecting as if it was new.
				port_info.node = conns[0].source_node
				port_info.index = conns[0].source_port
				connections.erase(conns[0])
			
			_connecting_port = port_info
			# Setup temporal connection curve
			_connecting_curve.set_point_position(0, port_info.node.get_port_position(port_info.index))
			_connecting_curve.set_point_out(0, port_info.node.get_port_control_point(port_info.index))
			_connecting_curve.set_point_position(1, event.position + _scroll_offset)
			_connecting_curve.set_point_in(1, -port_info.node.get_port_control_point(port_info.index))
			accept_event()
			update()
			return
		
		var node = _find_node_at_position(position)
		if node:
			# Clicked on a node
			_last_pressed_node = node
			
			_dragging = true
			_distance_dragged = 0
			accept_event()
			update()
			return

		# Pressed on an empty space, deselect all nodes
		_box_selecting = true
		if event.alt:
			_box_selection_mode = SelectionMode.SUBTRACTIVE
		elif event.shift:
			_box_selection_mode = SelectionMode.ADDITIVE
		else:
			_box_selection_mode = SelectionMode.NORMAL
		_box_select_start = position
		_box_select_end = position
		
		accept_event()
		_top_layer.update()
		update()
		return
	
	if event is InputEventMouseButton and event.button_index == BUTTON_MIDDLE and event.pressed:
		_panning = true
	
	if event is InputEventMouseButton:
		if event.button_index == BUTTON_WHEEL_UP:
			rect_scale *= 0.9
		elif event.button_index == BUTTON_WHEEL_DOWN:
			rect_scale *= 1.11

func get_cursor_shape(position: Vector2 = Vector2()) -> int:
	var filter = _port_filter_settings_pool.acquire()
	var port_info = _find_port_at_position(position, filter)
	_port_filter_settings_pool.release(filter)
	if port_info:
		return CURSOR_CROSS
	return CURSOR_ARROW

func connect_nodes(source_node: MyGraphNode, source_port: int, destination_node: MyGraphNode, destination_port: int) -> void:
	if !source_node:
		print("add_connection: Invalid source node")
		return
	
	if !destination_node:
		print("add_connection: Invalid destination node")
		return
	
	if source_port < 0 or source_port >= source_node.port_count:
		print("add_connection: Invalid source port")
		return
	
	if destination_port < 0 or destination_port >= destination_node.port_count:
		print("add_connection: Invalid destination port")
		return
	
	var connection = Connection.new(source_node, source_port, destination_node, destination_port)
	connections.push_back(connection)
	update()

func disconnect_nodes(source_node: MyGraphNode, source_port: int, destination_node: MyGraphNode, destination_port: int) -> void:
	for i in connections.size():
		var c = connections[i]
		if c.source_node == source_node and c.source_port == source_port and c.destination_node == destination_node and c.destination_port == destination_port:
			connections.remove(i)
			break

func remove_connection(connection: Connection) -> void:
	connections.erase(connection)

func get_connections() -> Array:
	return connections

func get_source_node_connections(source_node: MyGraphNode, source_port: int = -1) -> Array:
	var result = []
	for connection in connections:
		if connection.source_node == source_node and (source_port == -1 or connection.source_port == source_port):
			result.push_back(connection)
	return result

func get_destination_node_connections(destination_node: MyGraphNode, destination_port: int = -1) -> Array:
	var result = []
	for connection in connections:
		if connection.destination_node == destination_node and (destination_port == -1 or connection.destination_port == destination_port):
			result.push_back(connection)
	return result

func get_node_connections(node: MyGraphNode) -> Array:
	var result = []
	for connection in connections:
		if connection.source_node == node or connection.destination_node == node:
			result.push_back(connection)
	return result
