@tool
extends SceneTree
## Smoke test: instantiates each level, bakes its map, and reports what appeared.
##
##     /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##         --script res://tools/smoke_test_levels.gd
##
## This catches the failures a parse check cannot: a map that never reaches the
## builder, a builder with no TileSet, a level with no spawn, a player that fails
## to instance, a goal that is never placed. Exits non-zero if anything is wrong.
##
## The check runs from _process rather than _initialize because the scene tree
## is not usable during initialization: nodes added in _initialize never enter
## the tree, so their _ready never fires and everything looks empty.

const LEVELS_DIR := "res://scenes/game/levels/"
const LEVEL_COUNT := 9

var _done : bool = false

func _process(_delta : float) -> bool:
	if _done:
		return true
	_done = true
	var failures := 0
	for number in range(1, LEVEL_COUNT + 1):
		failures += _check_level(number)
	print("")
	if failures:
		print("FAILED: %d level(s) with problems" % failures)
		quit(1)
	else:
		print("all %d levels baked and spawned correctly" % LEVEL_COUNT)
		quit()
	return true

func _check_level(number : int) -> int:
	var path := "%slevel_%d.tscn" % [LEVELS_DIR, number]
	var packed : PackedScene = load(path)
	if packed == null:
		print("level_%d: FAILED to load %s" % [number, path])
		return 1

	var root := packed.instantiate()
	var problems := PackedStringArray()

	var builder := root.get_node_or_null("TileBuilder")
	var terrain : TileMapLayer = null
	var collision : Node = null
	var hazards : Node2D = null
	if builder == null:
		problems.append("no TileBuilder node")
	else:
		if builder.map.strip_edges().is_empty():
			problems.append("builder map is empty")
		terrain = builder.get_node_or_null("Terrain")
		collision = builder.get_node_or_null("TerrainCollision")
		hazards = builder.get_node_or_null("Hazards")
		if terrain == null:
			problems.append("no Terrain layer")
		elif terrain.tile_set == null:
			problems.append("Terrain has no TileSet")
		if collision == null:
			problems.append("no TerrainCollision node")
		elif collision is not StaticBody2D and collision is not AnimatableBody2D:
			# Shapes under anything but a physics body are silently inert.
			problems.append(
				"TerrainCollision is a %s; it must be a StaticBody2D or the "
				% collision.get_class()
				+ "player will fall through the floor")
		if hazards == null:
			problems.append("no Hazards node")

	# Adding to the tree fires _ready on the builder and the level, which is what
	# actually bakes the map, spawns the player and places the goal.
	var host := Node.new()
	get_root().add_child(host)
	host.add_child(root)

	var cell_count := terrain.get_used_cells().size() if terrain else 0
	var collision_count := collision.get_child_count() if collision else 0
	var hazard_count := hazards.get_child_count() if hazards else 0

	if terrain and cell_count == 0:
		problems.append("Terrain has no cells after baking")
	if collision and collision_count == 0:
		problems.append("no terrain collision was built")

	var player_count := 0
	var goal_count := 0
	for child in root.get_children():
		if child.is_in_group(&"player"):
			player_count += 1
		if child.name == "Goal":
			goal_count += 1
	if player_count != 1:
		problems.append("expected 1 player, found %d" % player_count)
	if goal_count != 1:
		problems.append("expected 1 goal, found %d" % goal_count)

	root.free()
	host.free()

	if problems.is_empty():
		print("level_%d: ok  (%d tiles, %d collision runs, %d hazards)"
			% [number, cell_count, collision_count, hazard_count])
		return 0
	print("level_%d: PROBLEMS" % number)
	for problem in problems:
		print("    - %s" % problem)
	return 1
