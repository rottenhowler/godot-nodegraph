tool
class_name NodeGraphEdit
extends Control

signal node_selection_changed(node)
signal node_position_changed(node)
signal node_size_changed(node)
signal node_layer_changed(node)

signal node_connection_request(source_node, source_port, destination_node, destination_port)
signal node_disconnection_request(source_node, source_port, destination_node, destination_port)
signal node_connection_with_empty(source_node, source_port, release_position)
signal node_delete_request(node)

signal node_added(node)
signal node_removed(node)

export(Dictionary) var allowed_connections

enum SelectionMode {NORMAL, ADDITIVE, SUBTRACTIVE}

var scroll_offset: Vector2 = Vector2() setget _set_scroll_offset

var _resort_queued: bool = false
var _doing_layout: bool = false

var _top_layer: CanvasItem
var _connection_layers: Dictionary

var _port_filter_settings_pool = PortFilterSettingsPool.new()
var _connecting_port: PortInfo = null
# Current connection curve in node space
var _connecting_curve: Curve2D

var _last_pressed_node: NodeGraphNode = null
var _dragging: bool = false
var _distance_dragged: int = 0
var _panning: bool = false
var _box_selecting: bool = false
var _box_selection_mode: int = SelectionMode.NORMAL setget _set_box_selection_mode
# Selection box coordinates in screen space
var _box_select_start: Vector2
var _box_select_end: Vector2

var _cutting: bool = false
var _cut_points = PoolVector2Array()

var snap: float = 10

var zoom: float = 1.0 setget _set_zoom
export(float) var zoom_min = 0.1
export(float) var zoom_max = 4.0
export(float) var zoom_step = 0.1

func calculate_aabb(points: Array) -> Rect2:
	var xmin = points[0].x
	var xmax = points[0].x
	var ymin = points[0].y
	var ymax = points[0].y
	for point in points:
		xmin = min(xmin, point.x)
		xmax = max(xmax, point.x)
		ymin = min(ymin, point.y)
		ymax = max(ymax, point.y)
	return Rect2(xmin, ymin, xmax - xmin, ymax - ymin)

class ConnectionLayer extends Control:
	var layer: int = 0
	var count: int = 0

class Connection:
	var node_graph_edit: NodeGraphEdit
	var source_node: NodeGraphNode
	var source_port: int
	var destination_node: NodeGraphNode
	var destination_port: int
	
	var layer: int
	
	# Connection curve in screen space
	var _curve: Curve2D
	# Bounding box in screen space
	var _aabb: Rect2
	
	func _init(node_graph_edit: NodeGraphEdit, source_node: NodeGraphNode, source_port: int, destination_node: NodeGraphNode, destination_port: int):
		self.node_graph_edit = node_graph_edit
		self.source_node = source_node
		self.source_port = source_port
		self.destination_node = destination_node
		self.destination_port = destination_port
		self.layer = max(source_node.layer, destination_node.layer)
		
		self._curve = Curve2D.new()
		self._curve.add_point(Vector2())
		self._curve.add_point(Vector2())
		self.update_curve()

	func update_curve() -> void:
		_curve.set_point_position(0, node_graph_edit.node_to_screen_position(source_node.get_port_position(source_port)))
		_curve.set_point_out(0, source_node.get_port_control_point(source_port) * node_graph_edit.zoom)
		_curve.set_point_position(1, node_graph_edit.node_to_screen_position(destination_node.get_port_position(destination_port)))
		_curve.set_point_in(1, destination_node.get_port_control_point(destination_port) * node_graph_edit.zoom)
		_aabb = node_graph_edit.calculate_aabb(_curve.get_baked_points())

class NodeGraphNodeIterator:
	var graph_edit: NodeGraphEdit
	var index: int
	
	func _init(graph_edit: NodeGraphEdit):
		self.graph_edit = graph_edit
	
	func _advance() -> bool:
		while index < graph_edit.get_child_count():
			if graph_edit.get_child(index) is NodeGraphNode:
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

class ReverseNodeGraphNodeIterator:
	var graph_edit: NodeGraphEdit
	var index: int
	
	func _init(graph_edit: NodeGraphEdit):
		self.graph_edit = graph_edit
	
	func _advance() -> bool:
		while index > 0:
			if graph_edit.get_child(index-1) is NodeGraphNode:
				return true
			index -= 1
		return false
	
	func _iter_init(arg) -> bool:
		index = graph_edit.get_child_count()
		return _advance()
	
	func _iter_next(arg) -> bool:
		index -= 1
		return _advance()
	
	func _iter_get(arg):
		return graph_edit.get_child(index-1)

class CollectionIterator:
	var collection: Array
	var index: int
	
	func _init(collection: Array):
		self.collection = collection
	
	func _iter_init(arg) -> bool:
		index = 0
		return index < collection.size()
	
	func _iter_next(arg) -> bool:
		index += 1
		return index < collection.size()
	
	func _iter_get(arg):
		return collection[index]

class FilteringIterator:
	var iterator
	func _init(iterator):
		self.iterator = iterator
	
	func _matches(obj) -> bool:
		return true
	
	func _advance() -> bool:
		while true:
			if _matches(iterator._iter_get(null)):
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
	
class SelectedNodesIterator extends FilteringIterator:
	func _init(iterator).(iterator):
		pass
	
	func _matches(node: NodeGraphNode) -> bool:
		return node and node.selected

var connections: Array = []

func array(items) -> Array:
	var a = []
	for item in items:
		a.push_back(item)
	return a

func _init():
	_top_layer = Control.new()
	_top_layer.connect("draw", self, "_top_layer_draw")
	_top_layer.set_anchors_preset(Control.PRESET_WIDE)
	_top_layer.mouse_filter = MOUSE_FILTER_PASS
	add_child(_top_layer)
	
	_connection_layers = {}
	
	_cut_points.resize(2)

func _enter_tree() -> void:
	connect("child_entered_tree", self, "_on_child_entered_tree")
	connect("child_exiting_tree", self, "_on_child_exiting_tree")

func _ready() -> void:
	rect_clip_content = true
	
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
	
	draw_style_box(get_stylebox("frame", "NodeGraphEdit"), Rect2(Vector2(), rect_size))

#		var p = points[points.size()-1]
#		var i = points.size() - 1
#		var l = 0
#		while i > 0 and l < 25:
#			i -= 1
#			l += (points[i] + points[i+1]).length()
#		var d = (points[i] - p).normalized() * 15 * zoom
#		print("i = ", i)
#		print("l = ", l)
#		var n = Vector2(-d.y, d.x) * 0.5
#		var triangle = PoolVector2Array()
#		triangle.push_back(p)
#		triangle.push_back(p + d)
##		triangle.push_back(p + d + n)
##		triangle.push_back(p + d - n)
#		var colors = PoolColorArray()
#		colors.push_back(color)
#		colors.push_back(color)
#		colors.push_back(color)
##		draw_polygon(triangle, colors)
#		draw_polyline(triangle, Color.red, 2.0 * zoom)


func _on_connection_layer_draw(layer: ConnectionLayer) -> void:
	for connection in connections:
		if connection.layer != layer.layer:
			continue
		
		var points = connection._curve.get_baked_points()
		var color = connection.source_node.get_port(connection.source_port).color
		layer.draw_polyline(points, color, 2.0 * zoom, true)

	if _connecting_port and _connecting_port.node.layer == layer.layer:
		var curve_points = _connecting_curve.get_baked_points()
		var points = PoolVector2Array()
		for point in curve_points:
			points.push_back(node_to_screen_position(point))
		layer.draw_polyline(points, _connecting_port.node.get_port(_connecting_port.index).color, 2.0 * zoom, true)

func _top_layer_draw() -> void:
	if _box_selecting:
		var stylebox_name = "selection_normal"
		match _box_selection_mode:
			SelectionMode.NORMAL:
				pass
			SelectionMode.ADDITIVE:
				stylebox_name = "selection_additive"
			SelectionMode.SUBTRACTIVE:
				stylebox_name = "selection_subtractive"
		
		_top_layer.draw_style_box(get_stylebox(stylebox_name, "NodeGraphEdit"), _get_selection_box())
	
	if _cutting:
		_top_layer.draw_polyline(_cut_points, Color.red)

func _on_child_entered_tree(child: Node) -> void:
	if !(child is NodeGraphNode):
		return
	
	# Setup before connecting to node's signals
	child.rect_position = node_to_screen_position(child.node_position)
	child.rect_size = child.node_size
	child.rect_scale = Vector2(zoom, zoom)
	
	child.connect("item_rect_changed", self, "_on_node_rect_changed", [child])
#	child.connect("node_port_added", self, "_on_node_port_added")
#	child.connect("node_port_updated", self, "_on_node_port_updated")
	child.connect("node_port_removed", self, "_on_node_port_removed", [child])
	child.connect("node_selection_changed", self, "_on_node_selection_changed", [child])
	child.connect("node_position_changed", self, "_on_node_position_changed", [child])
	child.connect("node_size_changed", self, "_on_node_size_changed", [child])
	child.connect("node_layer_changed", self, "_on_node_layer_changed", [child])

	_queue_resort()
	emit_signal("node_added", child)

func _on_child_exiting_tree(child: Node) -> void:
	if !(child is NodeGraphNode):
		return
	
	child.disconnect("node_selection_changed", self, "_on_node_selection_changed")
	child.disconnect("node_position_changed", self, "_on_node_position_changed")
	child.disconnect("node_size_changed", self, "_on_node_size_changed")
	child.disconnect("node_layer_changed", self, "_on_node_layer_changed")
	child.disconnect("item_rect_changed", self, "_on_node_rect_changed")
#	child.disconnect("node_port_added", self, "_on_node_port_added")
#	child.disconnect("node_port_updated", self, "_on_node_port_updated")
	child.disconnect("node_port_removed", self, "_on_node_port_removed")

	for connection in get_node_connections(child):
		remove_connection(connection)

	emit_signal("node_removed", child)

func _on_node_port_removed(node: NodeGraphNode, index: int) -> void:
	for connection in get_node_connections(node):
		if connection.source_port != index and connection.destination_port != index:
			continue
		connections.erase(connection)

func _on_node_rect_changed(node: NodeGraphNode) -> void:
	if _doing_layout:
		return
	
	var found_connections = false
	for connection in connections:
		if connection.source_node != node and connection.destination_node != node:
			continue
		
		connection.update_curve()
		found_connections = true
	
	if found_connections:
		update_all()

func _on_node_selection_changed(node: NodeGraphNode) -> void:
	emit_signal("node_selection_changed", node)

func _on_node_position_changed(node: NodeGraphNode) -> void:
	node.rect_position = node_to_screen_position(node.node_position)
	emit_signal("node_position_changed", node)

func _on_node_size_changed(node: NodeGraphNode) -> void:
	node.rect_size = node.node_size
	emit_signal("node_size_changed", node)

func _on_node_layer_changed(node: NodeGraphNode) -> void:
	emit_signal("node_layer_changed", node)
	for connection in get_node_connections(node):
		var new_layer = max(connection.layer, node.layer)
		if new_layer != connection.layer:
			_dec_connection_layer(connection.layer)
			connection.layer = new_layer
			_inc_connection_layer(connection.layer)
	_queue_resort()

func _inc_connection_layer(layer: int) -> void:
	var node = _connection_layers.get(layer)
	if !node:
		node = ConnectionLayer.new()
		node.layer = layer
		node.set_anchors_preset(Control.PRESET_WIDE)
		node.connect("draw", self, "_on_connection_layer_draw", [node])
		var idx = get_children().bsearch_custom(node, self, "_layer_lte", true)
		add_child(node)
		move_child(node, idx)
		_connection_layers[layer] = node
	else:
		node.update()
	node.count += 1

func _dec_connection_layer(layer: int) -> void:
	var node = _connection_layers.get(layer)
	if !node:
		return
	node.count -= 1
	if node.count <= 0:
		_connection_layers.erase(layer)
		node.free()
		return
	node.update()

func _update_connection_layer(layer: int) -> void:
	var node = _connection_layers.get(layer, null)
	if !node:
		return
	node.update()

func _update_all_connection_layers() -> void:
	for layer in _connection_layers:
		_connection_layers[layer].update()

func _get_layer(node: Node) -> int:
	if node is NodeGraphNode:
		return (node as NodeGraphNode).layer
	elif node is ConnectionLayer:
		return (node as ConnectionLayer).layer
	return 0

func _layer_lte(node1: Node, node2: Node) -> bool:
	return _get_layer(node1) < _get_layer(node2)

func _queue_resort() -> void:
	if _resort_queued:
		return
	
	_resort_queued = true
	call_deferred("_resort")

func _resort() -> void:
	_resort_queued = false

	var sorted = []
	for i in get_child_count():
		var child = get_child(i)
		var layer = _get_layer(child)

		var idx = 0
		if child is ConnectionLayer:
			idx = sorted.bsearch_custom(child, self, "_layer_lte", true)
		else:
			idx = sorted.bsearch_custom(child, self, "_layer_lte", false)
		sorted.insert(idx, child)
	
	for i in sorted.size():
		move_child(sorted[i], i)

func update_all() -> void:
	update()
	_top_layer.update()
	_update_all_connection_layers()

func _set_scroll_offset(offset: Vector2) -> void:
	if scroll_offset == offset:
		return
	
	scroll_offset = offset
	_do_layout()

func _set_box_selection_mode(mode: int) -> void:
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

func _set_zoom(value: float) -> void:
	zoom = min(zoom_max, max(zoom_min, value))
	_do_layout()

func zoom_at(position: Vector2, amount: float) -> void:
	var new_zoom = min(zoom_max, max(zoom_min, zoom + amount))
	if new_zoom == zoom:
		return
	scroll_offset = screen_to_node_position(position) - position / new_zoom
	zoom = new_zoom
	_do_layout()

func _do_layout() -> void:
	_doing_layout = true
	for node in get_nodes():
		node.rect_scale = Vector2(zoom, zoom)
		node.rect_position = node_to_screen_position(node.node_position)
	_doing_layout = false
	for connection in connections:
		connection.update_curve()
	update_all()

# Returns iterator for all nodes
func get_nodes():
	return NodeGraphNodeIterator.new(self)

func get_nodes_reversed():
	return ReverseNodeGraphNodeIterator.new(self)

# Returns iterator for selected nodes only
func get_selected_nodes():
	return SelectedNodesIterator.new(get_nodes())

func set_selected_nodes(nodes: Array) -> void:
	for node in get_selected_nodes():
		if !nodes.has(node):
			node.selected = false
	for node in nodes:
		if !(node is NodeGraphNode):
			continue
		node.selected = true

func _find_node_at_position(position: Vector2) -> NodeGraphNode:
	for node in get_nodes_reversed():
		if node.get_node_rect().has_point(position):
			return node
		
	return null

class PortInfo:
	var node: NodeGraphNode
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
			if filter.enabled and !node.get_port(i).enabled:
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

# Handle keyboard events
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
	elif event is InputEventKey and (event.scancode == KEY_DELETE or event.scancode == KEY_BACKSPACE):
		for node in array(get_selected_nodes()):
			emit_signal("node_delete_request", node)

func screen_to_node_position(screen_position: Vector2) -> Vector2:
	return screen_position / zoom + scroll_offset

func node_to_screen_position(node_position: Vector2) -> Vector2:
	return (node_position - scroll_offset) * zoom

func _gui_input(event):
	if _connecting_port:
		if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and !event.pressed:
			var settings = _port_filter_settings_pool.acquire()
			settings.enabled = true
			var port_info = _find_port_at_position(screen_to_node_position(event.position), settings)
			_port_filter_settings_pool.release(settings)
			if port_info:
				if is_connection_allowed(_connecting_port.node, _connecting_port.index, port_info.node, port_info.index):
					emit_signal("node_connection_request", _connecting_port.node, _connecting_port.index, port_info.node, port_info.index)
					# connect_nodes(_connecting_port.node, _connecting_port.index, port_info.node, port_info.index)
			else:
				emit_signal("node_connection_with_empty", _connecting_port.node, _connecting_port.index, screen_to_node_position(event.position))
			
			_dec_connection_layer(_connecting_port.node.layer)
			_connecting_port = null
			mouse_default_cursor_shape = CURSOR_ARROW
			accept_event()
			update()
		elif event is InputEventMouseMotion:
			var position = screen_to_node_position(event.position)
			
			var settings = _port_filter_settings_pool.acquire()
			settings.enabled = true
			var port_info = _find_port_at_position(position, settings)
			_port_filter_settings_pool.release(settings)
			if port_info and is_connection_allowed(_connecting_port.node, _connecting_port.index, port_info.node, port_info.index):
				_connecting_curve.set_point_position(1, port_info.node.get_port_position(port_info.index))
				_connecting_curve.set_point_in(1, port_info.node.get_port_control_point(port_info.index))
				mouse_default_cursor_shape = CURSOR_CROSS
			else:
				if port_info:
					mouse_default_cursor_shape = CURSOR_FORBIDDEN
				else:
					mouse_default_cursor_shape = CURSOR_ARROW
				_connecting_curve.set_point_position(1, position)
				var control = _connecting_curve.get_point_out(0)
				var direction = position - _connecting_curve.get_point_position(0)
				
				if control.dot(direction) >= 0:
					_connecting_curve.set_point_in(1, -_connecting_curve.get_point_out(0))
				else:
					_connecting_curve.set_point_in(1, _connecting_curve.get_point_out(0))
			
			accept_event()
			update()
			_update_connection_layer(_connecting_port.node.layer)
		return
	
	if _box_selecting:
		if event is InputEventMouseMotion:
			_box_select_end = event.position
			accept_event()
			_top_layer.update()
		elif event is InputEventMouseButton and event.button_index == BUTTON_LEFT and !event.pressed:
			# TODO: box selection
			_box_selecting = false
			var box = _get_selection_box()
			box = Rect2(screen_to_node_position(box.position), box.size / zoom)
			if event.alt:
				for node in get_nodes():
					if !box.encloses(node.get_node_rect()):
						continue
					if !node.selected:
						continue
					node.selected = false
			else:
				if !event.shift:
					for node in get_selected_nodes():
						node.selected = false
				for node in get_nodes():
					if !box.encloses(node.get_node_rect()):
						continue
					if node.selected:
						continue
					node.selected = true
			accept_event()
			_top_layer.update()
		return
	
	if _dragging:
		if event is InputEventMouseMotion:
			_distance_dragged += event.relative.length()
			_last_pressed_node = null
			
			for node in get_selected_nodes():
				node.node_position += event.relative / zoom
				for connection in get_node_connections(node):
					connection.update_curve()
					_update_connection_layer(connection.layer)
			accept_event()
			update()
		elif event is InputEventMouseButton and event.button_index == BUTTON_LEFT and !event.pressed:
			if _last_pressed_node:
				# It was a click on a node
				for selected_node in get_selected_nodes():
					selected_node.selected = false
				_last_pressed_node.selected = true
				_last_pressed_node = null
			
			_dragging = false
			mouse_default_cursor_shape = CURSOR_ARROW
			accept_event()
			update()
		return
	
	if _panning:
		if event is InputEventMouseMotion:
			scroll_offset -= event.relative / zoom
			_do_layout()
			accept_event()
			update()
			_update_all_connection_layers()
		elif event is InputEventMouseButton and event.button_index == BUTTON_MIDDLE and !event.pressed:
			_panning = false
			accept_event()
			update()
			_update_all_connection_layers()
		return

	if _cutting:
		if event is InputEventMouseMotion:
			_cut_points[1] = event.position
			accept_event()
			_top_layer.update()
		elif event is InputEventMouseButton and event.button_index == BUTTON_RIGHT and !event.pressed:
			_cutting = false
			var cut_aabb = calculate_aabb(_cut_points)
			var connections_to_erase = []
			for connection in connections:
				if !cut_aabb.intersects(connection._aabb):
					continue
				var intersects = false
				var connection_points = connection._curve.get_baked_points()
				for i in range(1, connection_points.size()):
					if Geometry.segment_intersects_segment_2d(_cut_points[0], _cut_points[1], connection_points[i-1], connection_points[i]):
						intersects = true
						break
				if intersects:
					connections_to_erase.push_back(connection)
			for conn in connections_to_erase:
				emit_signal("node_disconnection_request", conn.source_node, conn.source_port, conn.destination_node, conn.destination_port)
			accept_event()
			update()
			_top_layer.update()
		return

	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed:
		var position = screen_to_node_position(event.position)
		
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
				var conn = conns[0]
				# Emit signal and check if signal handler has removed the connection.
				# If so, convert it to a connecting state
				emit_signal("node_disconnection_request", conn.source_node, conn.source_port, conn.destination_node, conn.destination_port)
				if !connections.has(conn):
					port_info.node = conn.source_node
					port_info.index = conn.source_port
			
			_connecting_port = port_info
			# Setup temporal connection curve
			_connecting_curve.set_point_position(0, port_info.node.get_port_position(port_info.index))
			_connecting_curve.set_point_out(0, port_info.node.get_port_control_point(port_info.index))
			_connecting_curve.set_point_position(1, screen_to_node_position(event.position))
			_connecting_curve.set_point_in(1, -port_info.node.get_port_control_point(port_info.index))
			accept_event()
			update()
			_inc_connection_layer(_connecting_port.node.layer)
			return
		
		var node = _find_node_at_position(position)
		if node:
			# Clicked on a node
			if !node.selected:
				if !event.shift:
					for selected_node in get_selected_nodes():
						selected_node.selected = false
				node.selected = true
			else:
				if event.shift:
					node.selected = false
				else:
					_last_pressed_node = node
					_dragging = true
					_distance_dragged = 0
					mouse_default_cursor_shape = CURSOR_MOVE
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
		_box_select_start = event.position
		_box_select_end = event.position
		
		accept_event()
		_top_layer.update()
		return
	
	if event is InputEventMouseButton and event.button_index == BUTTON_MIDDLE and event.pressed:
		_panning = true
		mouse_default_cursor_shape = CURSOR_DRAG
		accept_event()
		return
	
	if event is InputEventMouseButton and event.button_index == BUTTON_RIGHT and event.pressed:
		_cutting = true
		_cut_points[0] = event.position
		_cut_points[1] = event.position
		accept_event()
		return
	
	if event is InputEventMouseButton:
		if event.button_index == BUTTON_WHEEL_UP:
			zoom_at(event.position, zoom_step)
		elif event.button_index == BUTTON_WHEEL_DOWN:
			zoom_at(event.position, -zoom_step)
		accept_event()
		return
		
	var position = screen_to_node_position(event.position)
	
	var settings = _port_filter_settings_pool.acquire()
	settings.enabled = true
	var port_info = _find_port_at_position(position, settings)
	_port_filter_settings_pool.release(settings)
	if port_info:
		mouse_default_cursor_shape = CURSOR_CROSS
	else:
		mouse_default_cursor_shape = CURSOR_ARROW

# Returns true if connection from given source port type to given destination port type is allowed
func is_connection_allowed(source_node: NodeGraphNode, source_port: int, destination_node: NodeGraphNode, destination_port: int) -> bool:
	var p1 = source_node.get_port(source_port)
	var p2 = destination_node.get_port(destination_port)
	if !p1 or !p2:
		return false
	
	if allowed_connections.size() > 0:
		return allowed_connections.has(p1.type) and allowed_connections[p1.type].has(p2.type)
	
	# By default only allow everything
	# return p1.direction == NodeGraphNode.OUTPUT and p2.direction == NodeGraphNode.INPUT and p1.type == p2.type
	return true

# Creates connection between given nodes&ports
func connect_nodes(source_node: NodeGraphNode, source_port: int, destination_node: NodeGraphNode, destination_port: int) -> void:
	if !source_node:
		push_error("add_connection: Invalid source node")
		return
	
	if !destination_node:
		push_error("add_connection: Invalid destination node")
		return
	
	if source_port < 0 or source_port >= source_node.port_count:
		push_error("add_connection: Invalid source port")
		return
	
	if destination_port < 0 or destination_port >= destination_node.port_count:
		push_error("add_connection: Invalid destination port")
		return
	
	var connection = Connection.new(self, source_node, source_port, destination_node, destination_port)
	connections.push_back(connection)
	_inc_connection_layer(connection.layer)
	update()

# Removes connection from given source node&port to given node&port
func disconnect_nodes(source_node: NodeGraphNode, source_port: int, destination_node: NodeGraphNode, destination_port: int) -> void:
	for i in connections.size():
		var c = connections[i]
		if c.source_node == source_node and c.source_port == source_port and c.destination_node == destination_node and c.destination_port == destination_port:
			connections.remove(i)
			_dec_connection_layer(c.layer)
			break

# Removes given connection
func remove_connection(connection: Connection) -> void:
	connections.erase(connection)

func clear_connections() -> void:
	connections = []

# Returns all connections
func get_connections() -> Array:
	return connections

# Returns all connections from given node (and given port, if port index is set)
func get_source_node_connections(source_node: NodeGraphNode, source_port: int = -1) -> Array:
	var result = []
	for connection in connections:
		if connection.source_node == source_node and (source_port == -1 or connection.source_port == source_port):
			result.push_back(connection)
	return result

# Returns all connections to given node (and given port, if port index is set)
func get_destination_node_connections(destination_node: NodeGraphNode, destination_port: int = -1) -> Array:
	var result = []
	for connection in connections:
		if connection.destination_node == destination_node and (destination_port == -1 or connection.destination_port == destination_port):
			result.push_back(connection)
	return result

# Returns all connections involving given node (both in and out)
func get_node_connections(node: NodeGraphNode) -> Array:
	var result = []
	for connection in connections:
		if connection.source_node == node or connection.destination_node == node:
			result.push_back(connection)
	return result
