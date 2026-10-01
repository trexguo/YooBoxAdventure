extends SceneTree
const RUNNER := preload("res://tools/campaign_story_runner.gd")
const SAVE := "user://global_state.tres"
var _had_save := false
var _original := PackedByteArray()
func _initialize() -> void:
	_had_save = FileAccess.file_exists(SAVE)
	if _had_save:
		_original = FileAccess.get_file_as_bytes(SAVE)
	var runner := Node.new()
	runner.set_script(RUNNER)
	get_root().add_child(runner)
	runner.finished.connect(_finish)
func _finish(failures: int) -> void:
	if _had_save:
		var file := FileAccess.open(SAVE,FileAccess.WRITE)
		file.store_buffer(_original)
		file.close()
	elif FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(1 if failures else 0)
