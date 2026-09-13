extends SceneTree
## Verifies the player's direction-toggle control scheme.
##
##     /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##         --script res://tools/test_control_scheme.gd
##
## Headless physics runs fine, so the player is instantiated in a bare world and
## driven with simulated input. Checks the behaviours the toggle scheme
## promises: the player runs unaided, a press flips direction and the flip
## sticks, pressing the direction already faced keeps it, hold-to-move still
## stands still when idle, and a wall jump turns the player away from the wall
## rather than back into it.
##
## The tests live on a Node rather than on the SceneTree script: awaiting
## physics_frame from a SceneTree coroutine never resumes, so the suite would
## hang after its first print.

const RUNNER := preload("res://tools/control_scheme_runner.gd")

func _initialize() -> void:
	var runner := Node.new()
	runner.set_script(RUNNER)
	get_root().add_child(runner)
	runner.finished.connect(_on_finished)

func _on_finished(failures : int) -> void:
	if failures:
		print("FAILED: %d assertion(s)" % failures)
		quit(1)
	else:
		print("all control-scheme assertions passed")
		quit()
