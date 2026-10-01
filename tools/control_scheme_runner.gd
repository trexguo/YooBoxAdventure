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
	await _test_crouch_enters_low_tunnel()
	await _test_crouch_keeps_full_speed()
	await _test_cannot_stand_under_ceiling()
	await _test_stands_up_after_clearing_ceiling()
	await _test_stable_body_at_wall()
	await _test_death_animation_and_respawn()
	await _test_air_dash()
	await _test_dash_wall_collision()

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
	for action in ["move_left", "move_right", "jump", "crouch"]:
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

# --- Slide -------------------------------------------------------------------

## Builds a floor with a ceiling slab `gap_tiles` above it, spanning `ceiling_x0`
## to `ceiling_x1` (inclusive tiles). Returns [host, player, ceiling_top_y].
func _make_tunnel_world(ceiling_x0 : int, ceiling_x1 : int, gap_tiles : float) -> Array:
	var host := Node2D.new()
	add_child(host)

	var body := StaticBody2D.new()
	body.collision_layer = SOLID
	body.collision_mask = 0
	host.add_child(body)

	# Floor: top surface at y=0.
	var floor_shape := RectangleShape2D.new()
	floor_shape.size = Vector2(2000, 64)
	var floor_col := CollisionShape2D.new()
	floor_col.shape = floor_shape
	floor_col.position = Vector2(1000, 32)
	body.add_child(floor_col)

	# Ceiling slab: bottom surface `gap_tiles * 32` above the floor.
	var gap := gap_tiles * 32.0
	var width := (ceiling_x1 - ceiling_x0 + 1) * 32.0
	var ceil_shape := RectangleShape2D.new()
	ceil_shape.size = Vector2(width, 200)
	var ceil_col := CollisionShape2D.new()
	ceil_col.shape = ceil_shape
	ceil_col.position = Vector2(ceiling_x0 * 32.0 + width * 0.5, -gap - 100.0)
	body.add_child(ceil_col)

	var player = load(PLAYER_SCENE).instantiate()
	host.add_child(player)
	player.toggle_direction_control = true
	player.facing = 1
	player._direction_held = 0
	player.global_position = Vector2(ceiling_x0 * 32.0 - 120, -40)
	return [host, player]

func _is_crouched(player) -> bool:
	return player._crouched

func _test_crouch_enters_low_tunnel() -> void:
	# Ceiling 1 tile above the floor, from tile 4 to tile 6: the standing body
	# cannot pass, the crouched one can. The key must be held for the whole
	# crossing, since crouching is hold-to-crouch, not a timed slide.
	var world := _make_tunnel_world(4, 6, 1.0)
	var player = world[1]
	await _step(30)
	var start_x : float = player.global_position.x

	Input.action_press("crouch")
	await _step(60)
	Input.action_release("crouch")
	await _step(5)

	# The player should be past the far edge of the ceiling (tile 7 onward).
	var past_ceiling : bool = player.global_position.x > 7 * 32.0
	_expect("holding crouch carries the player under a one-tile ceiling",
		past_ceiling,
		"x=%.1f; expected to be past %.1f" % [player.global_position.x, 7 * 32.0])
	var travelled : float = player.global_position.x - start_x
	_expect("the crouched player kept moving",
		travelled > 64.0,
		"travelled %.1fpx; expected to clear the 3-tile ceiling" % travelled)
	_release_all()
	world[0].free()

func _test_crouch_keeps_full_speed() -> void:
	# Crouching changes the hitbox only. In open ground, the horizontal speed
	# while crouched must match the speed while running: no slowdown, no lunge.
	var world := _make_tunnel_world(4, 4, 8.0)   # ceiling high enough to stand
	var player = world[1]
	await _step(50)
	var running_speed : float = absf(player.velocity.x)

	Input.action_press("crouch")
	await _step(30)
	var crouched_speed : float = absf(player.velocity.x)
	_expect("crouching does not slow the player down",
		is_equal_approx(crouched_speed, running_speed) or crouched_speed + 1.0 >= running_speed,
		"running %.1f px/s vs crouched %.1f px/s" % [running_speed, crouched_speed])
	_release_all()
	world[0].free()

func _test_cannot_stand_under_ceiling() -> void:
	# Long ceiling (tiles 4..20). Releasing crouch under it must NOT stand the
	# player up: the tall capsule would be driven into the ceiling. The short
	# hitbox has to persist until they have run clear.
	var world := _make_tunnel_world(4, 20, 1.0)
	var player = world[1]
	await _step(30)

	Input.action_press("crouch")
	await _step(10)
	Input.action_release("crouch")
	await _step(20)

	var under_ceiling : bool = player.global_position.x < 20 * 32.0
	_expect("the crouched body is held after release while under a ceiling",
		under_ceiling and _is_crouched(player),
		"x=%.1f crouched=%s; expected to still be crouched under the ceiling"
			% [player.global_position.x, _is_crouched(player)])
	_release_all()
	world[0].free()

func _test_stands_up_after_clearing_ceiling() -> void:
	var world := _make_tunnel_world(4, 6, 1.0)
	var player = world[1]
	await _step(30)

	Input.action_press("crouch")
	await _step(60)
	Input.action_release("crouch")
	await _step(10)

	_expect("the player stands back up after clearing the ceiling",
		not _is_crouched(player),
		"still crouched at x=%.1f after passing the ceiling" % player.global_position.x)
	_release_all()
	world[0].free()

# --- Harness -----------------------------------------------------------------

func _expect(label : String, condition : bool, detail : String) -> void:
	if condition:
		print("  [PASS] %s" % label)
	else:
		_failures += 1
		print("  [FAIL] %s\n         %s" % [label, detail])

func _test_stable_body_at_wall() -> void:
	var world := _make_world(30, 5)
	var player = world[1]
	var standing_height: float = player._sprite._height
	await _step(80)
	_expect("wall contact does not automatically crouch or resize the body",
		not player._crouched and is_equal_approx(player._sprite._height, standing_height),
		"unpressed crouch must leave the standing silhouette stable")
	world[0].queue_free()
	await _step(2)

func _test_death_animation_and_respawn() -> void:
	var level = load("res://scenes/game/levels/level_1.tscn").instantiate()
	level.play_intro = false
	add_child(level)
	var player = level.get_player()
	var deaths_before: int = level.level_state.deaths
	await _step(3)
	var death_position: Vector2 = player.global_position
	level.kill_player()
	level.kill_player()
	_expect("hazard death enters DEAD before respawning",
		player.state == player.State.DEAD and level.player_is_dead,
		"the death animation must run at the point of impact")
	await _step(6)
	_expect("dead player stays at impact and plays fragments",
		player.global_position.is_equal_approx(death_position) and player._sprite.pose == "dead" and player._sprite._death_time > 0.07,
		"death must freeze motion without teleporting immediately")
	_expect("repeated hazard contact only counts one death",
		level.level_state.deaths == deaths_before + 1,
		"death calls during animation must be ignored")
	await _step(25)
	_expect("respawn restores movement and clears death visuals",
		not level.player_is_dead and player.state != player.State.DEAD and player._sprite.pose != "dead" and player._input_enabled,
		"respawn must reset both movement and presentation")
	level.level_state.deaths = deaths_before
	level.queue_free()
	await _step(2)

func _test_air_dash() -> void:
	var world := _make_world(200)
	var player = world[1]
	player.position = Vector2(200,-1500)
	await _step(2)
	var start: Vector2 = player.position
	Input.action_press("crouch")
	await _step(2)
	start = player.position
	await _step(3)
	_expect("air crouch starts dash and suspends falling",
		player.state == player.State.DASH and player.position.x-start.x > 20 and absf(player.position.y-start.y) < 0.01,
		"state=%d dx=%.2f dy=%.2f" % [player.state,player.position.x-start.x,player.position.y-start.y])
	Input.action_release("crouch")
	await _step(8)
	_expect("dash ends and gravity resumes",player._dash_timer <= 0 and player.velocity.y > 0,
		"dash must end after its configured duration")
	await _step(105)
	Input.action_press("crouch")
	await _step(2)
	_expect("dash cannot repeat in one airtime even after cooldown",
		player._dash_timer <= 0 and not player._dash_available,
		"landing is required to recharge")
	_release_all()
	player.respawn_at(Vector2(200,-100))
	player.set_input_enabled(false)
	Input.action_press("crouch")
	await _step(2)
	_expect("locked input cannot dash",player._dash_timer <= 0,"cinematics must lock dash")
	_release_all()
	player.set_input_enabled(true)
	await _step(100)
	Input.action_press("jump")
	await _step(6)
	Input.action_press("move_left")
	Input.action_press("crouch")
	await _step(3)
	_expect("landing restores dash and left input selects its direction",
		player.state == player.State.DASH and player.velocity.x < 0,
		"dash should follow the selected direction after landing")
	player.die()
	_expect("death cancels active dash",player._dash_timer <= 0 and player.state == player.State.DEAD,
		"a dead player must not continue dashing")
	player.respawn_at(Vector2(200,-100))
	_expect("respawn restores dash availability",player._dash_available and player._dash_cooldown_timer <= 0,
		"a new life must clear dash timers")
	_release_all()
	world[0].free()

func _test_dash_wall_collision() -> void:
	var world := _make_world(30,12)
	var player = world[1]
	player.position = Vector2(350,-160)
	await _step(2)
	Input.action_press("crouch")
	await _step(8)
	_expect("dash stops at solid walls without passing through",
		player.position.x <= 374.1 and player._dash_timer <= 0,
		"move_and_slide must preserve terrain collision")
	_release_all()
	world[0].free()
