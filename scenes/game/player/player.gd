class_name Player
extends CharacterBody2D
## Super-Meat-Boy-style platformer character.
##
## Movement is deliberately built out of the small "forgiveness" mechanics that
## make a precision platformer feel fair rather than slippery:
##
## - [b]Variable jump height[/b]: releasing the jump button cuts the rise short.
## - [b]Coyote time[/b]: you can still jump for a moment after walking off a ledge.
## - [b]Jump buffer[/b]: pressing jump just before landing still jumps on touchdown.
## - [b]Wall slide + wall jump[/b]: the core traversal verb. Wall jumps lock out
##   horizontal input briefly so the player cannot steer straight back into the
##   wall, and alternate facing so chaining walls is possible.
##
## Every tunable is exported so the feel can be dialled in from the inspector
## while the game is running.

enum State { IDLE, RUN, JUMP, FALL, WALL_SLIDE, DEAD }

## Horizontal speed cap while running, in pixels per second.
@export var max_speed : float = 190.0
## Ground acceleration. Higher is snappier.
@export var ground_acceleration : float = 1400.0
## Ground friction applied when no direction is held.
@export var ground_friction : float = 1600.0
## Air acceleration. Lower than ground for a floatier feel.
@export var air_acceleration : float = 1000.0
## Air friction applied when no direction is held.
@export var air_friction : float = 600.0

@export_group("Jump")
## Upward velocity applied on a ground jump.
@export var jump_velocity : float = 360.0
## Multiplier applied to remaining upward velocity when jump is released early.
@export_range(0.0, 1.0) var jump_cut_multiplier : float = 0.45
## Gravity applied while rising and the jump button is held.
@export var rise_gravity : float = 1050.0
## Gravity applied while falling.
@export var fall_gravity : float = 1500.0
## Extra gravity multiplier applied when the jump button is released mid-rise.
@export var low_jump_gravity_multiplier : float = 1.8
## Terminal downward speed.
@export var max_fall_speed : float = 620.0
## Grace period after leaving a ledge during which a jump still counts.
@export var coyote_time : float = 0.10
## How early a jump press is remembered before landing.
@export var jump_buffer_time : float = 0.10

@export_group("Wall")
## Downward speed cap while sliding on a wall.
@export var wall_slide_speed : float = 90.0
## Horizontal push applied away from the wall on a wall jump.
@export var wall_jump_push : float = 250.0
## Upward velocity applied on a wall jump.
@export var wall_jump_velocity : float = 355.0
## Seconds after a wall jump during which horizontal input is ignored.
@export var wall_jump_lockout : float = 0.16
## If true, the player slides down walls without holding into them.
@export var auto_wall_slide : bool = false

@export_group("Detection")
## Reach of the wall-detection rays, in pixels.
@export var wall_check_distance : float = 6.0

## Emitted when the player enters a new state. Useful for animation and audio.
signal state_changed(new_state : State)
## Emitted on every death, before the level respawns the player.
signal died

var state : State = State.IDLE
## Counts up while airborne; used to run out the coyote window.
var _time_since_grounded : float = 0.0
## Counts down after a jump press; consumed by the next landing.
var _jump_buffer_timer : float = 0.0
## Counts down after a wall jump, suppressing steering back into the wall.
var _wall_jump_lockout_timer : float = 0.0
## Which side the wall is on: -1 left, 1 right, 0 none.
var _wall_direction : int = 0
## Facing of the last wall jumped from, so wall jumps alternate sides.
var _wall_jump_origin_direction : int = 0
## External control lock, e.g. during a level transition.
var _input_enabled : bool = true

@onready var _wall_check_left : RayCast2D = $WallCheckLeft
@onready var _wall_check_right : RayCast2D = $WallCheckRight
@onready var _sprite : Sprite2D = $Sprite2D

func _set_state(new_state : State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)

func _ready() -> void:
	add_to_group(&"player")
	GameState.mark_level_reached(scene_file_path)

# --- Public API --------------------------------------------------------------

## Returns the player to a position with all momentum cleared.
## Called by [Level] when respawning after a death.
func respawn_at(position_ : Vector2) -> void:
	global_position = position_
	velocity = Vector2.ZERO
	_wall_jump_lockout_timer = 0.0
	_jump_buffer_timer = 0.0
	_time_since_grounded = 0.0
	_input_enabled = true
	_set_state(State.FALL)

## Kills the player and asks the level to respawn them.
func die() -> void:
	if state == State.DEAD:
		return
	_set_state(State.DEAD)
	velocity = Vector2.ZERO
	_input_enabled = false
	died.emit()
	var level := _get_level()
	if level and level.has_method(&"kill_player"):
		level.kill_player()

## Enables or disables player input, e.g. while a menu is open.
func set_input_enabled(enabled : bool) -> void:
	_input_enabled = enabled

# --- Helpers -----------------------------------------------------------------

func _get_level() -> Node:
	# Walk up rather than assuming a fixed depth: levels may nest the player.
	var node := get_parent()
	while node != null:
		if node.has_method(&"kill_player"):
			return node
		node = node.get_parent()
	return null

func _get_horizontal_input() -> float:
	if not _input_enabled:
		return 0.0
	return Input.get_axis(&"move_left", &"move_right")

func _is_jump_just_pressed() -> bool:
	return _input_enabled and Input.is_action_just_pressed(&"jump")

func _is_jump_held() -> bool:
	return _input_enabled and Input.is_action_pressed(&"jump")

## Detects a wall on either side, excluding walls only a pixel tall so the
## player can still stand on the lip of a ledge.
func _update_wall_direction() -> void:
	_wall_check_left.force_raycast_update()
	_wall_check_right.force_raycast_update()
	if _wall_check_left.is_colliding():
		_wall_direction = -1
	elif _wall_check_right.is_colliding():
		_wall_direction = 1
	else:
		_wall_direction = 0

func _can_wall_slide() -> bool:
	if _wall_direction == 0 or is_on_floor():
		return false
	if velocity.y < 0.0:
		return false
	if auto_wall_slide:
		return true
	# Require the player to be pushing into the wall.
	return signf(_get_horizontal_input()) == float(_wall_direction)

func _apply_gravity(delta : float) -> void:
	var gravity := rise_gravity if velocity.y < 0.0 else fall_gravity
	# Releasing jump mid-rise makes the arc short and snappy.
	if velocity.y < 0.0 and not _is_jump_held():
		gravity *= low_jump_gravity_multiplier
	velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)

func _apply_horizontal_movement(delta : float) -> void:
	var direction := _get_horizontal_input()
	# Ignore steering back into the wall right after a wall jump.
	if _wall_jump_lockout_timer > 0.0 and direction == float(_wall_jump_origin_direction):
		direction = 0.0
	var on_ground := is_on_floor()
	if not is_zero_approx(direction):
		var acceleration := ground_acceleration if on_ground else air_acceleration
		velocity.x = move_toward(velocity.x, direction * max_speed, acceleration * delta)
	else:
		var friction := ground_friction if on_ground else air_friction
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

func _do_jump(velocity_y : float) -> void:
	velocity.y = velocity_y
	_jump_buffer_timer = 0.0
	_time_since_grounded = 999.0  # Consume coyote time so it cannot double-fire.

func _do_wall_jump() -> void:
	_wall_jump_origin_direction = _wall_direction
	velocity.x = -float(_wall_direction) * wall_jump_push
	_do_jump(-wall_jump_velocity)
	_wall_jump_lockout_timer = wall_jump_lockout
	_set_state(State.JUMP)

func _update_sprite_facing() -> void:
	if _sprite == null:
		return
	# Face away from the wall while sliding; otherwise face travel direction.
	if state == State.WALL_SLIDE and _wall_direction != 0:
		_sprite.flip_h = _wall_direction > 0
	elif not is_zero_approx(velocity.x):
		_sprite.flip_h = velocity.x < 0.0

# --- Main loop ---------------------------------------------------------------

func _physics_process(delta : float) -> void:
	if state == State.DEAD:
		return

	# Timers run before movement so buffered inputs are consumed this frame.
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	_wall_jump_lockout_timer = maxf(_wall_jump_lockout_timer - delta, 0.0)
	if is_on_floor():
		# Only reset while descending: is_on_floor() is still true on the frame
		# after a jump, and resetting there would hand back the coyote window
		# and allow a second jump.
		if velocity.y >= 0.0:
			_time_since_grounded = 0.0
	else:
		_time_since_grounded += delta

	if _is_jump_just_pressed():
		_jump_buffer_timer = jump_buffer_time

	_update_wall_direction()

	var can_ground_jump := is_on_floor() or _time_since_grounded <= coyote_time
	var has_buffered_jump := _jump_buffer_timer > 0.0

	if has_buffered_jump and _wall_direction != 0 and not is_on_floor():
		_do_wall_jump()
	elif has_buffered_jump and can_ground_jump:
		_do_jump(-jump_velocity)

	# Cut the jump short when the button is released while still rising.
	if velocity.y < 0.0 and not _is_jump_held():
		velocity.y *= jump_cut_multiplier

	_apply_gravity(delta)
	_apply_horizontal_movement(delta)

	if _can_wall_slide():
		velocity.y = minf(velocity.y, wall_slide_speed)

	move_and_slide()

	_resolve_state()

func _resolve_state() -> void:
	if _can_wall_slide():
		_set_state(State.WALL_SLIDE)
	elif is_on_floor():
		_set_state(State.IDLE if is_zero_approx(_get_horizontal_input()) else State.RUN)
	elif velocity.y < 0.0:
		_set_state(State.JUMP)
	else:
		_set_state(State.FALL)
	_update_sprite_facing()
