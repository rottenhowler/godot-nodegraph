tool
extends EditorPlugin

func _enter_tree() -> void:
	var theme = preload("res://addons/NodeGraph/Theme.tres")
	get_editor_interface().get_base_control().theme.merge_with(theme)
