extends Control

onready var graph_edit = get_node("%MyGraphEdit")
onready var add_node_popup_menu = get_node("%AddNodePopupMenu")

var add_node_source_node = null
var add_node_source_port = -1

func _on_MyGraphEdit_connection_request(source_node, source_port, destination_node, destination_port):
	graph_edit.connect_nodes(source_node, source_port, destination_node, destination_port)


func _on_MyGraphEdit_disconnection_request(source_node, source_port, destination_node, destination_port):
	graph_edit.disconnect_nodes(source_node, source_port, destination_node, destination_port)


func _on_MyGraphEdit_connection_with_empty(source_node, source_port, release_position):
	add_node_source_node = source_node
	add_node_source_port = source_port
	add_node_popup_menu.popup(Rect2(graph_edit.node_to_screen_position(release_position), add_node_popup_menu.rect_size))

func create_node() -> NodeGraphNode:
	var node = NodeGraphNode.new()
	node.size = Vector2(100, 50)
	node.port_count = 2
	var port1 = node.get_port(0)
	port1.vanchor = 0.5
	var port2 = node.get_port(1)
	port2.hanchor = 1.0
	port2.vanchor = 0.5
	port2.type = 1
	graph_edit.add_child(node)
	return node

func _on_AddNodePopupMenu_id_pressed(id):
	if id == 0:
		var node = create_node()
		node.position = graph_edit.screen_to_node_position(add_node_popup_menu.rect_position) - node.get_port(0).get_position()
		graph_edit.connect_nodes(add_node_source_node, add_node_source_port, node, 0)

func _on_MyGraphEdit_delete_request(node):
	node.free()
