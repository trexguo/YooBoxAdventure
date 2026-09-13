extends Node
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

signal finished(report : String)

const PLAYER_SCENE := "res://scenes/game/player/player.tscn"
const SOLID := 1

func _ready() -> void:
	var lines := PackedStringArray()
	lines.append("Measured jump arc (real scene, headless physics)")
	lines.append("")
	for entry in [["held", true], ["tapped", false]]:
		var label : String = entry[0]
		var hold : bool = entry[1]
		var result := await _measure_jump(hold)
		lines.append("  %-6s peak %6.1f px (%4.2f tiles)   range %6.1f px (%4.2f tiles)"
			% [label, result[0], result[0] / 32.0, result[1], result[1] / 32.0])
	finished.emit("\n".join(lines))

func _measure_jump(hold : bool) -> Array:
	# A long flat floor; no ceiling, so the arc is unobstructed.
	var host := Node2D.new()
	add_child(host)
	var body := StaticBody2D.new()
	body.collision_layer = SOLID
	body.collision_mask = 0
	host.add_child(body)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(4000, 64)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(1600, 32)
	body.add_child(col)

	var player = load(PLAYER_SCENE).instantiate()
	host.add_child(player)
	player.toggle_direction_control = true
	player.facing = 1
	player.global_position = Vector2(200, -40)

	# Let it settle onto the floor and reach full speed.
	for _i in 30:
		await get_tree().physics_frame

	var launch_y : float = player.global_position.y
	var launch_x : float = player.global_position.x
	Input.action_press("jump")
	if not hold:
		# Release after a single frame: the jump-cut path.
		await get_tree().physics_frame
		Input.action_release("jump")

	var peak : float = launch_y
	var land_x : float = launch_x
	# Wait for the player to actually leave the ground first, or the very first
	# frame still reports is_on_floor() and the loop exits immediately.
	var airborne := false
	for _i in 240:
		await get_tree().physics_frame
		peak = minf(peak, player.global_position.y)
		if not airborne:
			if not player.is_on_floor():
				airborne = true
			continue
		if hold and player.velocity.y >= 0.0:
			# Holding stops mattering once descending.
			Input.action_release("jump")
		if player.is_on_floor() and player.velocity.y >= 0.0:
			land_x = player.global_position.x
			break
	Input.action_release("jump")
	host.free()
	return [launch_y - peak, land_x - launch_x]
