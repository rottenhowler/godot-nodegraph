tool
class_name MyGraphNode
extends Container

signal port_added(node, port_index)
signal port_updated(node, port_index)
signal port_removed(node, port_index)
signal graph_position_changed

const PORT_SIZE = 5
const CORNER_RADIUS = 10

class Port extends Resource:
	export(int) var type: int
	export(Color) var color: Color = Color.white
	export(bool) var enabled: bool = true
	
	export(float) var hanchor: float
	export(float) var vanchor: float
	
	export(float) var hoffset: float
	export(float) var voffset: float

	var updated_signal_pending: bool = false
	var position_dirty: bool = false
	var position: Vector2

export(bool) var selected: bool setget set_selected
export(int) var port_count: int setget set_port_count, get_port_count

var _top_layer: CanvasItem
var _ports: Array = []

func _init():
	_top_layer = Control.new()
	_top_layer.connect("draw", self, "_top_layer_draw")
	_top_layer.set_anchors_preset(Control.PRESET_WIDE)
	_top_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_layer)

func _ready() -> void:
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = Color(0.7, 0.7, 0.7, 0.5)
	stylebox.set_corner_radius_all(CORNER_RADIUS)
	add_stylebox_override("body", stylebox)
	
	var border_normal = StyleBoxFlat.new()
	border_normal.draw_center = false
	border_normal.set_corner_radius_all(CORNER_RADIUS)
	border_normal.border_color = Color.black
	border_normal.set_border_width_all(1.0)
	add_stylebox_override("border_normal", border_normal)
	
	var border_selected = StyleBoxFlat.new()
	border_selected.draw_center = false
	border_selected.set_corner_radius_all(CORNER_RADIUS)
	border_selected.border_color = Color.yellow
	border_selected.set_border_width_all(1.0)
	add_stylebox_override("border_selected", border_selected)
	
	mouse_filter = Control.MOUSE_FILTER_PASS
	connect("item_rect_changed", self, "_on_rect_changed")

func _on_rect_changed() -> void:
	for port in _ports:
		port.position_dirty = true

func _get_property_list() -> Array:
	var property_list = []
	for i in _ports.size():
		var port = _ports[i]
		property_list.append_array(_get_port_properties(port, "ports/" + str(i) + "/"))
	
	return property_list

func _get_port_properties(port: Port, prefix: String) -> Array:
	var properties = []
	properties.push_back({"name": prefix + "type", "type": TYPE_INT})
	properties.push_back({"name": prefix + "color", "type": TYPE_COLOR})
	properties.push_back({"name": prefix + "enabled", "type": TYPE_BOOL})
	properties.push_back({"name": prefix + "horizontal_anchor", "type": TYPE_REAL, "hint": PROPERTY_HINT_RANGE, "hint_string": "0,1"})
	properties.push_back({"name": prefix + "vertical_anchor", "type": TYPE_REAL, "hint": PROPERTY_HINT_RANGE, "hint_string": "0,1"})
	properties.push_back({"name": prefix + "horizontal_offset", "type": TYPE_REAL})
	properties.push_back({"name": prefix + "vertical_offset", "type": TYPE_REAL})
	
	return properties

func _get(path: String):
	if path.begins_with("ports/"):
		return _get_port_property(_ports, path.substr(6))
	return null

func _set(path: String, value) -> bool:
	if path.begins_with("ports/"):
		return _set_port_property(_ports, path.substr(6), value)
	return false

func _get_port_property(ports: Array, path: String):
	var parts = path.split("/")
	var index = int(parts[0])
	if index < 0 or index >= ports.size():
		return false
	if parts.size() != 2:
		return false
	match parts[1]:
		"type":
			return ports[index].type
		"color":
			return ports[index].color
		"enabled":
			return ports[index].enabled
		"horizontal_anchor":
			return ports[index].hanchor
		"vertical_anchor":
			return ports[index].vanchor
		"horizontal_offset":
			return ports[index].hoffset
		"vertical_offset":
			return ports[index].voffset
		_:
			return null

func _set_port_property(ports: Array, path: String, value) -> bool:
	var parts = path.split("/")
	var index = int(parts[0])
	if index < 0 or index >= ports.size():
		return false
	if parts.size() != 2:
		return false
	match parts[1]:
		"type":
			ports[index].type = value
		"color":
			ports[index].color = value
		"enabled":
			ports[index].enabled = value
		"horizontal_anchor":
			ports[index].hanchor = value
			ports[index].position_dirty = true
		"vertical_anchor":
			ports[index].vanchor = value
			ports[index].position_dirty = true
		"horizontal_offset":
			ports[index].hoffset = value
			ports[index].position_dirty = true
		"vertical_offset":
			ports[index].voffset = value
			ports[index].position_dirty = true
		_:
			return false
	update()
	return true

func get_port_count() -> int:
	return _ports.size()

func set_port_count(value: int) -> void:
	if value == _ports.size():
		return
	
	for i in range(value, _ports.size()):
		emit_signal("port_removed", self, i)
	
	_ports.resize(value)
	
	for i in _ports.size():
		if !_ports[i]:
			var port = Port.new()
			port.updated_signal_pending = false
			_ports[i] = port
			emit_signal("port_added", self, i)
	
	property_list_changed_notify()
	update()

func set_selected(value: bool) -> void:
	selected = value
	_top_layer.update()
	update()

func _draw() -> void:
	_top_layer.raise()
	
	var stylebox = get_stylebox("body")
	draw_style_box(stylebox, Rect2(Vector2(), get_size()))

func _top_layer_draw() -> void:
	var stylebox = get_stylebox("border_normal")
	if selected:
		stylebox = get_stylebox("border_selected")
	
	_top_layer.draw_style_box(stylebox, Rect2(Vector2(), get_size()))
	
	for i in _ports.size():
		_draw_port(i)

func _draw_port(index) -> void:
	var position = get_port_position(index) - rect_position
	_top_layer.draw_circle(position, PORT_SIZE, get_port_color(index))
	_top_layer.draw_arc(position, PORT_SIZE, 0, TAU, 32, Color.black, 1, true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		for port in _ports:
			port.position_dirty = true

func _queue_port_updated(index: int) -> void:
	var port = _ports[index]
	if port.updated_signal_pending:
		return
	port.updated_signal_pending = true
	call_deferred("_emit_port_updated", index)

func _emit_port_updated(index: int) -> void:
	emit_signal("port_updated", self, index)
	_ports[index].updated_signal_pending = false

func get_port_position(index: int) -> Vector2:
	if index < 0 or index >= _ports.size():
		return Vector2()
	
	var port = _ports[index]
	if port.position_dirty:
		port.position = Vector2(port.hoffset + port.hanchor * rect_size.x, port.voffset + port.vanchor * rect_size.y)
		port.position_dirty = false
	return rect_position + port.position

func get_port_control_point(index: int) -> Vector2:
	var position = get_port_position(index) - rect_position
	
	var control = Vector2(-20, 0)
	var best_distance = abs(position.x)
	
	if abs(rect_size.x - position.x) < best_distance:
		best_distance = abs(rect_size.x - position.x)
		control = Vector2(20, 0)
	if abs(position.y) < best_distance:
		best_distance = abs(position.y)
		control = Vector2(0, -20)
	if abs(rect_size.y - position.y) < best_distance:
		best_distance = abs(rect_size.y - position.y)
		control = Vector2(0, 20)
	return control

func get_port_type(index: int) -> int:
	if index < 0 or index >= _ports.size():
		return -1
	
	return _ports[index].type

func set_port_type(index: int, type: int) -> void:
	if index < 0 or index >= _ports.size():
		return
	
	var port = _ports[index]
	
	if port.type == type:
		return
	
	port.type = type
	_queue_port_updated(index)
	update()

func get_port_color(index: int) -> Color:
	if index < 0 or index >= _ports.size():
		return Color()

	return _ports[index].color

func set_port_color(index: int, value: Color) -> void:
	if index < 0 or index >= _ports.size():
		return
	
	var port = _ports[index]

	if port.color == value:
		return
	
	port.color = value
	_queue_port_updated(index)
	update()

func get_port_enabled(index: int) -> bool:
	if index < 0 or index >= _ports.size():
		return false
	
	return _ports[index].enabled

func set_port_enabled(index: int, value: bool) -> void:
	if index < 0 or index >= _ports.size():
		return
		
	var port = _ports[index]
	
	if port.enabled == value:
		return
	
	port.enabled = value
	_queue_port_updated(index)
	update()

func get_port_horizontal_anchor(index: int) -> float:
	if index < 0 or index >= _ports.size():
		return 0.0
	
	return _ports[index].hanchor
 
func set_port_horizontal_anchor(index: int, value: float) -> void:
	if index < 0 or index >= _ports.size():
		return
	
	var port = _ports[index]
	
	if port.hanchor == value:
		return
	
	port.hanchor = value
	port.position_dirty = true
	_queue_port_updated(index)
	update()

func get_port_vertical_anchor(index: int) -> float:
	if index < 0 or index >= _ports.size():
		return 0.0
	
	return _ports[index].vanchor
 
func set_port_vertical_anchor(index: int, value: float) -> void:
	if index < 0 or index >= _ports.size():
		return
	
	var port = _ports[index]
	
	if port.vanchor == value:
		return
	
	port.vanchors = value
	port.position_dirty = true
	_queue_port_updated(index)
	update()

func get_port_horizontal_offset(index: int) -> float:
	if index < 0 or index >= _ports.size():
		return 0.0
	
	return _ports[index].hoffset

func set_port_horizontal_offset(index: int, value: float) -> void:
	if index < 0 or index >= _ports.size():
		return

	var port = _ports[index]
	
	if port.hoffset == value:
		return
	
	port.hoffset = value
	port.position_dirty = true
	_queue_port_updated(index)
	update()
	
func get_port_vertical_offset(index: int) -> float:
	if index < 0 or index >= _ports.size():
		return 0.0
	
	return _ports[index].voffset

func set_port_vertical_offset(index: int, value: float) -> void:
	if index < 0 or index >= _ports.size():
		return

	var port = _ports[index]
	
	if port.voffset == value:
		return
	
	port.voffset = value
	port.position_dirty = true
	_queue_port_updated(index)
	update()
