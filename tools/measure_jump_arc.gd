extends SceneTree
## Measures the player's real jump arc by running the actual scene headless.
##
##     /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##         --script res://tools/measure_jump_arc.gd
##
## tools/verify_level_geometry.py mirrors the physics constants in Python, which
## is fast but can drift from the GDScript. This measures the real thing, so the
## two can be compared when a number looks wrong.
##
## Reports, from a full-speed run:
##   - peak height of a held jump
##   - horizontal distance covered before returning to launch height
##   - the same for a jump released immediately (the short hop)
##
## The measuring lives on a Node rather than on the SceneTree script: awaiting
## physics_frame from a SceneTree coroutine never resumes, so the run would hang
## before its first print. See tools/measure_jump_arc_runner.gd.

const RUNNER := preload("res://tools/measure_jump_arc_runner.gd")

func _initialize() -> void:
	var runner := Node.new()
	runner.set_script(RUNNER)
	get_root().add_child(runner)
	runner.finished.connect(_on_finished)

func _on_finished(report : String) -> void:
	print(report)
	quit()
