extends Node
## Test body for tools/test_control_scheme.gd. See that file for how to run it.
##
## Lives on a Node so that `await get_tree().physics_frame` works; a SceneTree
## script's own coroutines do not resume.

signal finished(failures : int)

const PLAYER_SCENE := "res://scenes/game/player/player.tscn"
const SOLID := 1

var _failures : int = 0

func _ready() -> void:
	await _run_suite()
	finished.emit(_failures)

func _run_suite() -> void:
	await _test_runs_without_input()
	await _test_press_flips_direction()
	await _test_tap_does_not_flip()
	await _test_hold_to_move_mode()
	await _test_wall_jump_turns_away()

# --- World helpers -----------------------------------------------------------

## Builds a floor and an optional wall, returns [host, player].
func _make_world(floor_tiles : int, wall_at_tile : int = -1) -> Array:
	var host := Node2D.new()
	add_child(host)

	var body := StaticBody2D.new()
	body.collision_layer = SOLID
	body.collision_mask = 0
	host.add_child(body)

	# Floor: spans from x=0, top surface at y=0, 64px thick.
	var floor_shape := RectangleShape2D.new()
	floor_shape.size = Vector2(floor_tiles * 32 + 64, 64)
	var floor_col := CollisionShape2D.new()
	floor_col.shape = floor_shape
	floor_col.position = Vector2(floor_tiles * 16, 32)
	body.add_child(floor_col)

	if wall_at_tile >= 0:
		var wall_shape := RectangleShape2D.new()
		wall_shape.size = Vector2(32, 320)
		var wall_col := CollisionShape2D.new()
		wall_col.shape = wall_shape
		wall_col.position = Vector2(wall_at_tile * 32 + 16, -128)
		body.add_child(wall_col)

	var player = load(PLAYER_SCENE).instantiate()
	host.add_child(player)
	player.global_position = Vector2(64, -40)
	return [host, player]

func _step(frames : int) -> void:
	for _i in frames:
		await get_tree().physics_frame

func _release_all() -> void:
	for action in ["move_left", "move_right", "jump"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)

# --- Tests -------------------------------------------------------------------

func _test_runs_without_input() -> void:
	var world := _make_world(30)
	var player = world[1]
	player.toggle_direction_control = true
	player.initial_facing = 1
	player.facing = 1
	var start_x : float = player.global_position.x
	await _step(40)
	var moved : float = player.global_position.x - start_x
	_expect("runs with no key held",
		moved > 50.0,
		"expected travel right over 40 frames, moved %.1fpx" % moved)
	_release_all()
	world[0].free()

func _test_press_flips_direction() -> void:
	var world := _make_world(60)
	var player = world[1]
	player.toggle_direction_control = true
	player.initial_facing = 1
	player.facing = 1
	await _step(10)

	Input.action_press("move_left")
	await _step(5)
	Input.action_release("move_left")
	_expect("a press left flips the facing",
		player.facing == -1,
		"facing is %d, expected -1" % player.facing)

	var before : float = player.global_position.x
	await _step(30)
	var moved : float = player.global_position.x - before
	_expect("keeps running left after the key is released",
		moved < -50.0,
		"moved %.1fpx; negative means it kept going left" % moved)
	_release_all()
	world[0].free()

func _test_tap_does_not_flip() -> void:
	var world := _make_world(60)
	var player = world[1]
	player.toggle_direction_control = true
	player.facing = 1
	player._direction_held = 0
	Input.action_press("move_right")
	await _step(5)
	Input.action_release("move_right")
	_expect("pressing the direction already faced keeps it",
		player.facing == 1,
		"facing is %d, expected 1" % player.facing)
	_release_all()
	world[0].free()

func _test_hold_to_move_mode() -> void:
	var world := _make_world(40)
	var player = world[1]
	player.toggle_direction_control = false
	player.facing = 0
	# Hold-to-move with nothing pressed must stand still.
	await _step(40)
	var drift : float = absf(player.velocity.x)
	Input.action_press("move_left")
	await _step(30)
	var vel_while_held : float = player.velocity.x
	_expect("hold-to-move stands still with no key held",
		drift < 5.0,
		"velocity was %.1f with nothing pressed; expected ~0" % drift)
	_expect("hold-to-move moves while a key is held",
		vel_while_held < -50.0,
		"velocity.x was %.1f while holding left" % vel_while_held)
	_release_all()
	world[0].free()

func _test_wall_jump_turns_away() -> void:
	# Floor 30 tiles wide, wall at tile 12. Start airborne beside the wall.
	var world := _make_world(30, 12)
	var player = world[1]
	player.toggle_direction_control = true
	player.facing = 1
	player._direction_held = 0
	player.global_position = Vector2(12 * 32 - 20, -120)
	await _step(20)

	var sliding : bool = player.state == player.State.WALL_SLIDE or player._wall_direction == 1
	_expect("toggle control slides on a wall it runs into",
		sliding,
		"state=%d wall_dir=%d x=%.1f" % [player.state, player._wall_direction, player.global_position.x])

	Input.action_press("jump")
	await _step(3)
	Input.action_release("jump")
	var facing_after : int = player.facing
	var vel_x : float = player.velocity.x
	_expect("a wall jump turns the player away from the wall",
		facing_after == -1 and vel_x < 0.0,
		"facing=%d velocity.x=%.1f; expected facing -1 and leftward velocity" % [facing_after, vel_x])

	await _step(30)
	_expect("the player does not steer straight back into the wall",
		player.global_position.x < 12 * 32 - 20,
		"x=%.1f, expected to have moved left of the start" % player.global_position.x)
	_release_all()
	world[0].free()

# --- Harness -----------------------------------------------------------------

func _expect(label : String, condition : bool, detail : String) -> void:
	if condition:
		print("  [PASS] %s" % label)
	else:
		_failures += 1
		print("  [FAIL] %s\n         %s" % [label, detail])
