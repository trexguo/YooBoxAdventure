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
## - [b]Slide[/b]: holding the slide button drops the player into a short
##   hitbox so they can pass under one-tile gaps without slowing down.
##
## Every tunable is exported so the feel can be dialled in from the inspector
## while the game is running.

enum State { IDLE, RUN, JUMP, FALL, WALL_SLIDE, CROUCH, DEAD, DASH }
const VISUAL_POSES := ["idle", "run", "jump", "fall", "wall_slide", "crouch", "dead", "dash"]

## Horizontal speed cap while running, in pixels per second.
@export var max_speed : float = 300.0
## Ground acceleration. Higher is snappier.
@export var ground_acceleration : float = 1900.0
## Ground friction applied when no direction is held.
@export var ground_friction : float = 2100.0
## Air acceleration. Lower than ground for a floatier feel.
@export var air_acceleration : float = 1400.0
## Air friction applied when no direction is held.
@export var air_friction : float = 600.0

@export_group("Jump")
## Upward velocity applied on a ground jump.
@export var jump_velocity : float = 400.0
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
@export var wall_jump_push : float = 300.0
## Upward velocity applied on a wall jump.
@export var wall_jump_velocity : float = 355.0
## Seconds after a wall jump during which horizontal input is ignored.
@export var wall_jump_lockout : float = 0.16
## If true, the player slides down walls without holding into them.
@export var auto_wall_slide : bool = false

@export_group("Air Dash")
@export var dash_speed: float = 620.0
@export var dash_duration: float = 0.16
## Minimum interval between launches, independent of landing.
@export var dash_cooldown: float = 1.6
var _dash_timer := 0.0
var _dash_cooldown_timer := 0.0
var _dash_available := true
var _dash_direction := 1

@export_group("Crouch")
## Collision layer to test for headroom when the player straightens up.
@export_flags_2d_physics var headroom_mask : int = 1

@export_group("Control Scheme")
## If true, the player always runs: pressing a direction key sets which way they
## face and they accelerate that way on their own, rather than only moving while
## the key is held.
##
## This suits a handheld D-pad, where holding a direction for the whole level is
## tiring. Set it to false for the traditional hold-to-move feel.
@export var toggle_direction_control : bool = true
## How quickly the player accelerates up to full speed under toggle control.
## Kept separate from [member ground_acceleration] because the two are doing
## different jobs: this is the turnaround, not the response to a held key.
@export var turn_acceleration : float = 1900.0
## If true, releasing all direction keys stops the player instead of leaving
## them running. Off by default: a precision platformer reads better when the
## character keeps its momentum.
@export var stop_when_no_direction : bool = false
## Facing chosen when the level starts. 1 is right, -1 is left.
@export var initial_facing : int = 1

@export_group("Screen Controls")
## Viewport pixels needed to recognize a downward swipe.
@export var swipe_down_distance: float = 48.0
## Short horizontal swipes select the autorun direction.
@export var swipe_side_distance: float = 32.0
## Brief recognition window lets a downward swipe crouch without jumping first.
@export var screen_press_delay: float = 0.08
var _pointer_id: int = -2 # -2: none; -1: mouse; >= 0: touch index.
var _pointer_origin := Vector2.ZERO
var _pointer_age := 0.0
var _pointer_swiped := false
var _pointer_crouching := false
var _pointer_direction_pending: int = 0
var _pointer_jump_started := false
var _pointer_jump_pending := false
var _pointer_crouch_pending := false
var _pointer_jump_this_tick := false
var _pointer_crouch_this_tick := false

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
## Set once a jump's rise has been cut short, so the cut is not re-applied.
var _jump_cut_applied : bool = false
## Which side the wall is on: -1 left, 1 right, 0 none.
var _wall_direction : int = 0
## Facing of the last wall jumped from, so wall jumps alternate sides.
var _wall_jump_origin_direction : int = 0
## External control lock, e.g. during a level transition.
var _input_enabled : bool = true
## True while the short hitbox is active. Tracks the shape swap directly, so
## code (and tests) can read it without waiting for the deferred swap to apply.
var _crouched : bool = false

## Which way the player is heading: 1 right, -1 left.
##
## Under toggle control this is the authoritative direction and persists when no
## key is held. Under hold-to-move control it mirrors the keys and falls to 0
## when nothing is pressed.
var facing : int = 1
## Set while a direction key is physically held, so toggle control can tell
## "still pushing the same way" from "tapped and released".
var _direction_held : int = 0

@onready var _wall_check_left : RayCast2D = $WallCheckLeft
@onready var _wall_check_right : RayCast2D = $WallCheckRight
@onready var _camera: Camera2D = $Camera2D
@onready var _sprite : Node2D = $Sprite2D
@onready var _stand_shape : CollisionShape2D = $CollisionShape2D
@onready var _crouch_shape : CollisionShape2D = $CrouchCollisionShape2D

## A zero-size shape used to probe the space the standing body would occupy.
var _headroom_shape := RectangleShape2D.new()
var _headroom_query := PhysicsShapeQueryParameters2D.new()

func _set_state(new_state : State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)

func _ready() -> void:
	add_to_group(&"player")
	GameState.mark_level_reached(scene_file_path)
	facing = -1 if initial_facing < 0 else 1
	_camera.position.x = float(facing)*96.0
	_setup_crouch()

## Prepares the crouch geometry and the reusable headroom probe.
##
## The headroom probe is not the standing capsule: the standing body always
## overlaps the floor it is standing on, so testing it would report "blocked"
## forever and the player could never get up. It is instead the slab of space
## the standing body needs [i]above[/i] the crouched one, which is empty exactly
## when standing up is safe.
func _setup_crouch() -> void:
	var stand := _stand_shape.shape as CapsuleShape2D
	var crouch := _crouch_shape.shape as CapsuleShape2D
	if stand == null or crouch == null:
		return
	var extra : float = stand.height - crouch.height
	# The slab spans from the top of the crouched body upward by the difference
	# in height, centred on the player's feet (y = 0 is the feet under both
	# shapes, which are bottom-anchored).
	_headroom_shape.size = Vector2(stand.radius * 2.0, extra)
	_headroom_query.shape = _headroom_shape
	_headroom_query.collision_mask = headroom_mask
	_headroom_query.collide_with_areas = false
	_headroom_query.collide_with_bodies = true
	# Never let the player's own body count as blocking itself.
	_headroom_query.exclude = [get_rid()]

# --- Public API --------------------------------------------------------------

## Returns the player to a position with all momentum cleared.
## Called by [Level] when respawning after a death.
func respawn_at(position_ : Vector2) -> void:
	_reset_screen_input()
	global_position = position_
	velocity = Vector2.ZERO
	_dash_timer = 0.0
	_dash_cooldown_timer = 0.0
	_dash_available = true
	_wall_jump_lockout_timer = 0.0
	_jump_buffer_timer = 0.0
	_jump_cut_applied = false
	_time_since_grounded = 0.0
	_input_enabled = true
	_direction_held = 0
	_set_body_crouched(false)
	_sprite.reset()
	# Restart facing the level's default way, so a respawn is consistent.
	facing = -1 if initial_facing < 0 else 1
	_camera.position.x = float(facing)*96.0
	_set_state(State.FALL)
	reset_physics_interpolation()

## Kills the player and asks the level to respawn them.
func die() -> void:
	if state == State.DEAD:
		return
	_reset_screen_input()
	_dash_timer = 0.0
	_set_state(State.DEAD)
	_update_visual_pose()
	velocity = Vector2.ZERO
	_input_enabled = false
	died.emit()
	var level := _get_level()
	if level and level.has_method(&"kill_player"):
		level.kill_player()

## Enables or disables player input, e.g. while a menu is open.
func set_input_enabled(enabled : bool) -> void:
	_input_enabled = enabled
	if not enabled:
		_reset_screen_input()
		_dash_timer = 0.0

# Screen input stays local: releasing a finger never releases a keyboard key.
func _reset_screen_input() -> void:
	_pointer_id = -2
	_pointer_direction_pending = 0
	_pointer_jump_pending = false
	_pointer_crouch_pending = false
	_pointer_jump_this_tick = false
	_pointer_crouch_this_tick = false
	_pointer_swiped = false
	_pointer_crouching = false
	_pointer_jump_started = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_reset_screen_input()

func _screen_input_allowed() -> bool:
	return _input_enabled and state != State.DEAD and not get_tree().paused

func _over_screen_ui(at: Vector2) -> bool:
	for control in get_tree().get_nodes_in_group("gameplay_pointer_blocker"):
		if control is Control and control.is_visible_in_tree() and control.get_global_rect().has_point(at):
			return true
	return false

func _begin_screen_press(id: int, at: Vector2) -> void:
	if _pointer_id != -2 or not _screen_input_allowed() or _over_screen_ui(at):
		return
	_pointer_id = id
	_pointer_origin = at
	_pointer_age = 0.0
	_pointer_swiped = false
	_pointer_crouching = false
	_pointer_jump_started = false

func _end_screen_press(cancelled: bool = false) -> void:
	if not cancelled and not _pointer_swiped and not _pointer_jump_started and _screen_input_allowed():
		_pointer_jump_pending = true
	_pointer_id = -2
	_pointer_jump_started = false

func _drag_screen_press(at: Vector2) -> void:
	if _pointer_swiped or not _screen_input_allowed():
		return
	var travel := at - _pointer_origin
	if absf(travel.x) >= swipe_side_distance and absf(travel.x) > absf(travel.y):
		_pointer_swiped = true
		_pointer_jump_pending = false
		_pointer_jump_started = false
		_pointer_direction_pending = 1 if travel.x > 0.0 else -1
	elif travel.y >= swipe_down_distance and travel.y > absf(travel.x):
		_pointer_swiped = true
		_pointer_jump_pending = false
		_pointer_jump_started = false
		_pointer_crouching = true
		_pointer_crouch_pending = true

func _input(event: InputEvent) -> void:
	# GUI emulation can consume screen events. Handle gameplay presses first,
	# reserving UI hit areas and ignoring synthetic mouse copies of touches.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch and event.pressed and not event.canceled:
		_begin_screen_press(event.index,event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_begin_screen_press(-1,event.position)
	# Owned gestures must release even when the pointer ends over a UI control.
	if _pointer_id == -2 or event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch and event.index == _pointer_id and (not event.pressed or event.canceled):
		_end_screen_press(event.canceled)
	elif event is InputEventScreenDrag and event.index == _pointer_id:
		_drag_screen_press(event.position)
	elif _pointer_id == -1 and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_end_screen_press()
	elif _pointer_id == -1 and event is InputEventMouseMotion:
		_drag_screen_press(event.position)

func _update_screen_input(delta: float) -> void:
	if _pointer_id != -2 and not _pointer_swiped and not _pointer_jump_started:
		_pointer_age += delta
		if _pointer_age >= screen_press_delay:
			_pointer_jump_started = true
			_pointer_jump_pending = true
	_pointer_jump_this_tick = _pointer_jump_pending
	_pointer_crouch_this_tick = _pointer_crouch_pending
	_pointer_jump_pending = false
	_pointer_crouch_pending = false

# --- Helpers -----------------------------------------------------------------

func _get_level() -> Node:
	# Walk up rather than assuming a fixed depth: levels may nest the player.
	var node := get_parent()
	while node != null:
		if node.has_method(&"kill_player"):
			return node
		node = node.get_parent()
	return null

## Reads the direction keys and updates [member facing].
##
## Under toggle control a fresh press sets the facing, which then persists. The
## player keeps running that way with no key held. Under hold-to-move control
## the facing follows the keys and drops to 0 when they are released.
func _update_facing() -> void:
	var input := Input.get_axis(&"move_left", &"move_right") if _input_enabled else 0.0
	var pressed := 0
	if input > 0.5:
		pressed = 1
	elif input < -0.5:
		pressed = -1

	if not toggle_direction_control:
		_direction_held = pressed
		facing = pressed
		return

	# Toggle mode: a new press (or a change of direction) sets the facing.
	if pressed != 0 and pressed != _direction_held:
		facing = pressed
	_direction_held = pressed
	if pressed == 0 and stop_when_no_direction:
		facing = 0
	if _input_enabled and _pointer_direction_pending != 0:
		facing = _pointer_direction_pending
		_pointer_direction_pending = 0

## Returns the horizontal direction to move this frame.
##
## Both control schemes read the same [member facing] value; they differ only in
## how it is produced (see [method _update_facing]).
func _get_move_direction() -> float:
	if not _input_enabled:
		return 0.0
	return float(facing)

func _is_jump_just_pressed() -> bool:
	return _input_enabled and (Input.is_action_just_pressed(&"jump") or _pointer_jump_this_tick)

func _is_jump_held() -> bool:
	return _input_enabled and (Input.is_action_pressed(&"jump") or (_pointer_id != -2 and _pointer_jump_started and not _pointer_swiped))

# --- Crouch ------------------------------------------------------------------

## True when there is room for the standing body above the crouched one.
##
## False while under a low ceiling, which is what keeps the player down: the
## slide simply continues until they clear the gap.
##
## Both shapes are bottom-anchored at the feet (y = 0), so the space standing up
## needs is the band from the crouched body's top up to the standing body's top.
## Testing the whole standing capsule instead would always overlap the floor the
## player is standing on, and they could never get up at all.
func _has_headroom() -> bool:
	var stand := _stand_shape.shape as CapsuleShape2D
	var crouch := _crouch_shape.shape as CapsuleShape2D
	if stand == null or crouch == null:
		# Shape missing (scene edited without the crouch node); stand up rather
		# than trapping the player in a permanent slide.
		return true
	var extra : float = stand.height - crouch.height
	# Centre of the required band, measured up from the feet.
	var band_center : float = -crouch.height - extra * 0.5
	_headroom_query.transform = Transform2D(0.0, global_position + Vector2(0.0, band_center))
	var hit := get_world_2d().direct_space_state.intersect_shape(_headroom_query, 1)
	return hit.is_empty()

## True while the player is holding the crouch button.
func _is_crouch_held() -> bool:
	return _input_enabled and (Input.is_action_pressed(&"crouch") or (_pointer_id != -2 and _pointer_crouching) or _pointer_crouch_this_tick)

## Swaps the hitbox and animates the feet-anchored box pose.
##
## Both shapes are bottom-anchored at the feet, so this never moves the player:
## the shorter body simply occupies the lower part of the space the tall one did.
func _set_body_crouched(crouched : bool) -> void:
	if _crouched == crouched:
		return
	_crouched = crouched
	if _stand_shape == null or _crouch_shape == null:
		return
	_stand_shape.set_deferred(&"disabled", crouched)
	_crouch_shape.set_deferred(&"disabled", not crouched)
	_update_visual_pose()

## Keeps the hitbox in sync with the crouch button and the ceiling.
##
## Holding the button crouches. Releasing it stands back up, except under a low
## ceiling, where the player stays down until they have run clear: the short
## hitbox is what makes a one-tile tunnel passable, so standing up inside one
## would drive the tall body into the roof.
func _update_crouch() -> void:
	if not is_on_floor():
		# Airborne, the body stays as it is: a crouch that leaves a ledge keeps
		# the short hitbox for the whole fall, so the arc under a ceiling clears.
		return
	var wants_crouch := _is_crouch_held() or (_crouched and not _has_headroom())
	_set_body_crouched(wants_crouch)

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
	# Under toggle control the player is always running, so a slide starts
	# whenever they touch a wall with any downward speed: there is no "pushing
	# into the wall" to detect.
	if toggle_direction_control:
		return true
	# Hold-to-move: require the keys to be pushing into the wall.
	return signf(_get_move_direction()) == float(_wall_direction)

func _apply_gravity(delta : float) -> void:
	var gravity := rise_gravity if velocity.y < 0.0 else fall_gravity
	# Releasing jump mid-rise makes the arc short and snappy.
	if velocity.y < 0.0 and not _is_jump_held():
		gravity *= low_jump_gravity_multiplier
	velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)

func _apply_horizontal_movement(delta : float) -> void:
	var direction := _get_move_direction()
	# Ignore steering back into the wall right after a wall jump.
	if _wall_jump_lockout_timer > 0.0 and direction == float(_wall_jump_origin_direction):
		direction = 0.0
	var on_ground := is_on_floor()
	# Crouching changes the hitbox only, never the speed: the player keeps running
	# at [member max_speed] so a low tunnel is a gap to thread, not a timing test.
	if not is_zero_approx(direction):
		var acceleration := ground_acceleration if on_ground else air_acceleration
		if toggle_direction_control:
			acceleration = turn_acceleration
		# A direction change is a reversal, not just a nudge: use the faster
		# turnaround so the character does not slide the wrong way for a moment.
		elif signf(direction) != signf(velocity.x) and not is_zero_approx(velocity.x):
			acceleration = turn_acceleration
		velocity.x = move_toward(velocity.x, direction * max_speed, acceleration * delta)
	else:
		var friction := ground_friction if on_ground else air_friction
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

func _do_jump(velocity_y : float) -> void:
	velocity.y = velocity_y
	_jump_buffer_timer = 0.0
	_jump_cut_applied = false
	_time_since_grounded = 999.0  # Consume coyote time so it cannot double-fire.

func _do_wall_jump() -> void:
	_wall_jump_origin_direction = _wall_direction
	# Turn to face the way we are leaving, or toggle control would immediately
	# steer the player back into the wall we just jumped off.
	facing = -_wall_direction
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

## Keep the upcoming route visible at the closer zoom. Wall jumps do not
## reverse camera lead on every bounce; direction changes on ground ease it.
func _update_camera_lead(delta: float) -> void:
	if is_on_floor() and _input_enabled and state != State.DEAD:
		_camera.position.x = move_toward(_camera.position.x, float(facing)*96.0, delta*400.0)

# --- Main loop ---------------------------------------------------------------

func _physics_process(delta : float) -> void:
	_update_screen_input(delta)
	_update_camera_lead(delta)
	if state == State.DEAD:
		return

	_dash_cooldown_timer = maxf(_dash_cooldown_timer - delta, 0.0)
	if is_on_floor() and velocity.y >= 0.0:
		_dash_available = true
	_update_facing()
	if _input_enabled and not is_on_floor() and (Input.is_action_just_pressed("crouch") or _pointer_crouch_this_tick) and _dash_available and _dash_cooldown_timer <= 0.0:
		_dash_available = false
		_dash_timer = dash_duration
		_dash_cooldown_timer = dash_cooldown
		_dash_direction = facing if facing != 0 else (-1 if _sprite.flip_h else 1)
		_jump_buffer_timer = 0.0
		_wall_jump_lockout_timer = 0.0
		_time_since_grounded = 999.0
	if _dash_timer > 0.0:
		var dash_delta := minf(delta, _dash_timer)
		# move_and_slide uses a full physics tick; prorate the last tick.
		velocity = Vector2(float(_dash_direction) * dash_speed * dash_delta / delta, 0.0)
		_dash_timer = maxf(_dash_timer - delta, 0.0)
		move_and_slide()
		_set_state(State.DASH)
		_update_sprite_facing()
		_update_visual_pose()
		if is_on_wall() or is_on_floor():
			_dash_timer = 0.0
		if _dash_timer <= 0.0:
			velocity.x = float(_dash_direction) * max_speed
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

	_update_facing()
	_update_wall_direction()
	_update_crouch()

	var can_ground_jump := is_on_floor() or _time_since_grounded <= coyote_time
	var has_buffered_jump := _jump_buffer_timer > 0.0

	var jumped_this_frame := false
	# Jumping stands the player up first, but only when there is room: jumping
	# from inside a low tunnel would drive the tall body straight into the
	# ceiling. The buffered jump stays banked and fires once the player clears it.
	if has_buffered_jump and not _crouched and _wall_direction != 0 and not is_on_floor():
		_do_wall_jump()
		jumped_this_frame = true
	elif has_buffered_jump and can_ground_jump and not _crouched:
		_do_jump(-jump_velocity)
		jumped_this_frame = true
	elif has_buffered_jump and _crouched and _has_headroom():
		_set_body_crouched(false)
		_do_jump(-jump_velocity)
		jumped_this_frame = true

	# Cut the jump short when the button is released while still rising.
	#
	# Two details matter. First it must fire at most once per jump: applying the
	# multiplier every frame compounds it (0.45, 0.20, 0.09 ...) and kills the
	# jump outright. Second it is skipped on the launch frame, so a one-frame tap
	# still gets a full frame of the launch velocity rather than losing half of
	# it before the player has moved at all.
	if velocity.y < 0.0 and not _is_jump_held() and not jumped_this_frame and not _jump_cut_applied:
		velocity.y *= jump_cut_multiplier
		_jump_cut_applied = true

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
		if _crouched:
			# Crouching still counts as running: the state is only used for
			# animation, and the player is moving at full speed.
			_set_state(State.CROUCH)
		else:
			_set_state(State.IDLE if is_zero_approx(_get_move_direction()) else State.RUN)
	elif velocity.y < 0.0:
		_set_state(State.JUMP)
	else:
		_set_state(State.FALL)
	_update_sprite_facing()
	_update_visual_pose()

func _update_visual_pose() -> void:
	if _sprite != null:
		_sprite.set_pose(VISUAL_POSES[state], _crouched)
		_sprite.set_motion(velocity.x, max_speed)
