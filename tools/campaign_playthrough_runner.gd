extends Node
## Plays actual physics for all nine maps, without counting intro/outro time.
signal finished(failures: int)
var failures := 0

func _ready() -> void:
	await _run()
	finished.emit(failures)

func _run() -> void:
	var campaign = JSON.parse_string(FileAccess.get_file_as_string("res://resources/campaign.json"))
	for design in campaign:
		await _play(design)
	print("Campaign traversal: %d failures" % failures)

func _play(design: Dictionary) -> void:
	var level = load("res://scenes/game/levels/level_%d.tscn" % int(design.number)).instantiate()
	level.play_intro = false
	add_child(level)
	var player = level.get_player()
	# Track the real completion without writing best times or playing the outro.
	level.get_node("Goal").monitoring = false
	var rows: PackedStringArray = level.get_node("TileBuilder").map.split("\n")
	var deaths_before: int = level.level_state.deaths
	var ticks := 0
	var reached := false
	var last_jump := -20
	var jump_release := -1
	var last_x := 0.0
	var stuck := 0
	var tower_index := 0
	while ticks < 7200:
		await get_tree().physics_frame
		ticks += 1
		if player.state == player.State.DEAD:
			break
		var x: float = player.position.x
		var y: float = player.position.y
		if absf(x - last_x) < 0.05:
			stuck += 1
		else:
			stuck = 0
		last_x = x
		if player.position.distance_to(level.get_node("Goal").position) < 38.0:
			reached = true
			break
		if ticks == jump_release:
			Input.action_release("jump")
		var shaft_x := INF
		if tower_index < design.towers.size():
			var tower: Dictionary = design.towers[tower_index]
			shaft_x = float(tower.left)*32.0
			if x > float(tower.right)*32.0+38.0 and y <= float(tower.top)*32.0+2.0:
				tower_index += 1
				shaft_x = float(design.towers[tower_index].left)*32.0 if tower_index < design.towers.size() else INF
			elif x > shaft_x+42:
				Input.action_release("move_right")
				Input.action_release("crouch")
				if y <= float(tower.top)*32.0-2.0:
					Input.action_press("move_right")
				if player._wall_direction != 0 and not player.is_on_floor() and ticks-last_jump > 15:
					Input.action_release("jump")
					Input.action_press("jump")
					last_jump = ticks
					jump_release = ticks+38
				elif player.is_on_floor() and player._wall_direction == 1 and ticks-last_jump > 20:
					Input.action_release("jump")
					Input.action_press("jump")
					last_jump = ticks
					jump_release = ticks+20
				continue
		Input.action_press("move_right")
		if x > shaft_x-100.0:
			Input.action_release("crouch")
			continue
		var bay_floor := int(design.bays[mini(tower_index,design.bays.size()-1)].floor)
		var col := int(x/32.0)
		var floor_row := int(round(y/32.0))
		var crouch_needed := false
		for probe in range(col,col+3):
			if _cell(rows,probe,bay_floor-2) == "#" and _cell(rows,probe,bay_floor-1) == ".":
				crouch_needed = true
		if crouch_needed:
			Input.action_press("crouch")
		else:
			Input.action_release("crouch")
		if not player.is_on_floor() or player._crouched or ticks-last_jump < 3:
			continue
		var should_jump := false
		for ahead in range(col+1,col+5):
			var d := float(ahead)*32.0-x
			var above := _cell(rows,ahead,floor_row-1)
			var ground := _cell(rows,ahead,floor_row)
			if above == "^":
				var shelf := _cell(rows,ahead,floor_row-2) == "#"
				if d < (82.0 if shelf else 52.0):
					should_jump = true
			elif above == "#" and not crouch_needed:
				var tall := _cell(rows,ahead,floor_row-2) == "#"
				if d < (82.0 if tall else 60.0):
					should_jump = true
			elif ground != "#" and d < 26.0:
				should_jump = true
		if stuck > 12 and not crouch_needed:
			should_jump = true
		if should_jump:
			Input.action_release("jump")
			Input.action_press("jump")
			last_jump = ticks
			jump_release = ticks+38
	var seconds := float(ticks)/60.0
	if not reached or seconds < 20.0:
		failures += 1
		print("FAIL level %d: reached=%s %.2fs x=%.1f y=%.1f state=%d facing=%d crouch=%s" % [int(design.number),reached,seconds,player.position.x,player.position.y,player.state,player.facing,player._crouched])
	else:
		print("PASS level %d: actual route %.2fs without deaths or cinematics" % [int(design.number),seconds])
	level.level_state.deaths = deaths_before
	for action in ["jump","crouch","move_left","move_right"]:
		Input.action_release(action)
	level.queue_free()
	await get_tree().physics_frame

func _cell(rows: PackedStringArray, x: int, y: int) -> String:
	if y < 0 or y >= rows.size() or x < 0 or x >= rows[y].length():
		return "."
	return rows[y][x]
