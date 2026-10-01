extends Node
signal finished(failures: int)
var failures := 0
var _wins := 0
func _ready() -> void:
	await _test_intro_and_outro(1)
	await _test_intro_and_outro(9)
	await _test_retry_feedback()
	await _test_elevated_exit()
	print("Campaign story: %d failures" % failures)
	finished.emit(failures)
func _step(count: int) -> void:
	for i in count:
		await get_tree().process_frame
func _check(label: String, okay: bool) -> void:
	print("%s %s" % ["PASS" if okay else "FAIL",label])
	if not okay:
		failures += 1
func _test_intro_and_outro(number: int) -> void:
	var level = load("res://scenes/game/levels/level_%d.tscn" % number).instantiate()
	add_child(level)
	var story = level.get_node("EscapeDirector")
	var player = level.get_player()
	await _step(3)
	var initial: Vector2 = player.position
	await _step(53)
	_check("intro holds player and excludes cinematic time",story.cinematic_active and player.position.is_equal_approx(initial) and is_zero_approx(level.elapsed_time))
	_check("ZhangAss visibly carries Yoo",story.yoo.get_parent() == story.boss and story.boss.visible and story.yoo.visible)
	if number == 1:
		Input.action_press("ui_accept")
		await _step(2)
		Input.action_release("ui_accept")
		_check("Enter skips intro and restores input",not story.cinematic_active and player._input_enabled and player.is_physics_processing())
	else:
		await _step(100)
		_check("unskipped intro completes and restores input",not story.cinematic_active and player._input_enabled)
	var waiting_position: Vector2 = story.boss.position
	var goal_position: Vector2 = level.get_node("Goal").position
	_check("boss and Yoo wait visibly beyond the exit before arrival", story.boss.visible and story.yoo.visible and story.yoo.get_parent() == story.boss and waiting_position.x > goal_position.x + 40.0 and is_equal_approx(waiting_position.y,goal_position.y+16.0))
	# Avoid hazards while exercising the actual win/outro flow.
	player.set_physics_process(false)
	level.get_node("Goal").monitoring = false
	_wins = 0
	level.level_won.connect(func(_path: String): _wins += 1)
	level.elapsed_time = 40.0
	level.win_level()
	_check("outro starts from the waiting position without teleporting",story.boss.position.is_equal_approx(waiting_position))
	level.win_level()
	_check("win waits for the escape animation",_wins == 0 and story.cinematic_active)
	await _step(115)
	_check("outro emits completion once with run time preserved",_wins == 1 and not story.cinematic_active and is_equal_approx(level.elapsed_time,40.0))
	if number == 9:
		_check("final level lets Yoo escape the boss",story.yoo.get_parent() == story and not story.yoo.worried and story.yoo.visible)
	else:
		_check("boss leaves carrying Yoo on earlier levels",story.yoo.get_parent() == story.boss and not story.boss.visible)
	level.queue_free()
	await _step(3)

func _test_retry_feedback() -> void:
	var level = load("res://scenes/game/levels/level_9.tscn").instantiate()
	level.play_intro = false
	add_child(level)
	await _step(3)
	var player = level.get_player()
	player.set_physics_process(false)
	player.position = Vector2(4000,800)
	var camera: Camera2D = player.get_node("Camera2D")
	camera.reset_smoothing()
	camera.force_update_scroll()
	level.elapsed_time = 12.5
	level.total_play_time = 31.0
	player._dash_available = false
	player._dash_cooldown_timer = 1.2
	var story = level.get_node("EscapeDirector")
	var waiting_position: Vector2 = story.boss.position
	level.kill_player()
	await _step(25)
	_check("retry resets attempt time and keeps total play time",level.elapsed_time < 0.2 and level.total_play_time >= 31.0)
	_check("retry restores spawn, dash and control without intro",player.position.is_equal_approx(level.spawn_point.position) and player._dash_available and player._input_enabled and not level.get_node("EscapeDirector").cinematic_active)
	var center := camera.get_screen_center_position()
	_check("retry camera immediately returns to the tall map spawn",center.y > level.spawn_point.position.y-400.0 and center.x < 800.0)
	_check("retry keeps the kidnappers waiting at the exit",story.boss.visible and story.yoo.visible and story.boss.position.is_equal_approx(waiting_position))
	_check("tall map spawn is above its kill plane",level.kill_plane_y > level.spawn_point.position.y+100.0)
	level.queue_free()
	await _step(3)

func _test_elevated_exit() -> void:
	var level = load("res://scenes/game/levels/level_1.tscn").instantiate()
	level.play_intro = false
	add_child(level)
	var player = level.get_player()
	var goal: Area2D = level.get_node("Goal")
	var floor_y := goal.position.y + 16.0
	player.respawn_at(Vector2(goal.position.x-120.0,floor_y-0.1))
	await _step(3)
	Input.action_press("jump")
	await _step(25)
	Input.action_release("jump")
	_check("jumping through the elevated exit triggers completion above the flag-sized area",level._is_completed and player.position.y < floor_y-40.0 and level.get_node("EscapeDirector").cinematic_active)
	await _step(115)
	level.queue_free()
	await _step(3)
