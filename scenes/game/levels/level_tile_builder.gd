@tool
class_name LevelTileBuilder
extends Node
## Builds a level's terrain [TileMapLayer] from an ASCII map.
##
## Authoring a TileMapLayer by hand in a .tscn means writing out packed cell
## arrays, which is unreadable and unreviewable in a diff. Instead each level
## stores its layout as plain text and this node bakes it into the TileMapLayer
## at load time (and in the editor, so it can be seen while building).
##
## Map legend:
## [codeblock]
##   `#`  solid terrain block
##   `^`  spikes (hazard, kills on contact)
##   `P`  player spawn point
##   `G`  goal (level exit)
##   `.`  or space: empty
## [/codeblock]
##
## All rows are padded to the longest row, so trailing spaces are optional.

## The map, one string per row. See the class docs for the legend.
@export_multiline var map : String = ""
## TileMapLayer that terrain cells are written into. Defaults to a child named
## "Terrain".
@export var terrain_layer_path : NodePath
## Physics body that terrain collision is built into as merged rectangles.
## Must be a StaticBody2D (or another physics body): a CollisionShape2D only
## registers with the physics server when its parent is one, so shapes under a
## plain Node2D silently do nothing. Defaults to a child named
## "TerrainCollision".
@export var collision_body_path : NodePath
## Node that spike Areas are parented under. Defaults to a child named "Hazards".
@export var hazards_path : NodePath
## Rebuild in the editor whenever the map changes.
@export var rebuild_in_editor : bool = true
## Print a summary of what was baked.
@export var debug_logging : bool = false

const SOLID_CHAR := "#"
const SPIKE_CHAR := "^"
const SPAWN_CHAR := "P"
const GOAL_CHAR := "G"

const SPIKE_SCENE := "res://scenes/game/levels/spike.tscn"
## Emitted after a bake with the resolved spawn and goal positions. The level
## uses this to move its spawn marker and place the goal Area2D.
signal baked(spawn_position : Vector2, goal_position : Vector2)

var _terrain : TileMapLayer
var _collision_body : CollisionObject2D
var _hazards : Node2D

var _spawn_position : Vector2
var _goal_position : Vector2
var _has_spawn : bool = false
var _has_goal : bool = false

## Set by [Level] so hazard contact reaches the level's kill handler.
var hazard_handler : Callable

func _resolve(path : NodePath, fallback_name : String) -> Node:
	if not path.is_empty():
		return get_node_or_null(path)
	return get_node_or_null(NodePath(fallback_name))

func _ready() -> void:
	_terrain = _resolve(terrain_layer_path, "Terrain") as TileMapLayer
	_collision_body = _resolve(collision_body_path, "TerrainCollision") as CollisionObject2D
	_hazards = _resolve(hazards_path, "Hazards") as Node2D
	if Engine.is_editor_hint() and not rebuild_in_editor:
		return
	bake()

func _validate() -> bool:
	if _terrain == null:
		push_error("%s: no terrain TileMapLayer found" % name)
		return false
	if _terrain.tile_set == null:
		push_error("%s: terrain TileMapLayer has no TileSet" % name)
		return false
	if _terrain.tile_set.get_source_count() == 0:
		push_error("%s: terrain TileSet has no sources" % name)
		return false
	# A CollisionShape2D under a non-body node is silently inert, which shows up
	# only as the player falling through the floor. Catch it here instead.
	if _collision_body == null:
		push_error("%s: no TerrainCollision body found; the level would have no solid ground" % name)
		return false
	if _collision_body is not StaticBody2D and _collision_body is not AnimatableBody2D:
		push_error(
			"%s: TerrainCollision must be a StaticBody2D or AnimatableBody2D to hold "
			% name
			+ "solid collision; it is a %s. CollisionShape2D nodes under a plain "
			% _collision_body.get_class()
			+ "Node2D or an Area2D do not create solid ground."
		)
		return false
	return true

## Row strings, padded to equal length. Null entries mark blank rows.
func _get_rows() -> PackedStringArray:
	var rows := PackedStringArray()
	var longest := 0
	for raw_row in map.split("\n"):
		rows.append(raw_row)
		longest = maxi(longest, raw_row.length())
	for i in rows.size():
		if rows[i].length() < longest:
			rows[i] = rows[i] + " ".repeat(longest - rows[i].length())
	return rows

func _char_at(rows : PackedStringArray, column : int, row : int) -> String:
	if row < 0 or row >= rows.size():
		return " "
	var line := rows[row]
	if column < 0 or column >= line.length():
		return " "
	return line[column]

## Clears and rebuilds everything. Safe to call repeatedly.
func bake() -> void:
	if not _validate():
		return
	_clear()
	var rows := _get_rows()
	var source_id := _terrain.tile_set.get_source_id(0)

	# Pass 1: place tiles and collect solid cells for collision merging.
	var solid_cells : Array[Vector2i] = []
	for row in rows.size():
		for column in rows[row].length():
			var marker := _char_at(rows, column, row)
			var cell := Vector2i(column, row)
			match marker:
				SOLID_CHAR:
					_terrain.set_cell(cell, source_id, Vector2i.ZERO)
					solid_cells.append(cell)
				SPIKE_CHAR:
					_add_hazard(column, row)
				SPAWN_CHAR:
					_spawn_position = _cell_center(column, row)
					_has_spawn = true
				GOAL_CHAR:
					_goal_position = _cell_center(column, row)
					_has_goal = true

	_build_collision(solid_cells)

	if debug_logging:
		print("%s: baked %d solid, %d spike cells (spawn %s, goal %s)" % [
			name, solid_cells.size(), _hazards.get_child_count(),
			_has_spawn, _has_goal,
		])
	baked.emit(_spawn_position, _goal_position)

func _clear() -> void:
	_terrain.clear()
	for container in [_collision_body, _hazards]:
		if container == null:
			continue
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()

func _cell_center(column : int, row : int) -> Vector2:
	var map_to_local := _terrain.map_to_local
	var local := map_to_local.call(Vector2i(column, row)) as Vector2
	return _terrain.to_global(local)

## Merges horizontally adjacent solid cells into a single rectangle, then emits
## one CollisionShape2D per run. Far fewer shapes than one-per-tile, which keeps
## 2D physics cheap on the handheld target.
func _build_collision(solid_cells : Array[Vector2i]) -> void:
	if _collision_body == null or solid_cells.is_empty():
		return
	var tile_size := _terrain.tile_set.tile_size
	var by_row : Dictionary = {}
	for cell in solid_cells:
		by_row.get_or_add(cell.y, [] as Array[Vector2i]).append(cell)
	for row in by_row.keys():
		var cells : Array = by_row[row]
		cells.sort_custom(func(a : Vector2i, b : Vector2i) -> bool: return a.x < b.x)
		var run_start : int = cells[0].x
		var run_end : int = cells[0].x
		for index in range(1, cells.size()):
			var column : int = cells[index].x
			if column == run_end + 1:
				run_end = column
				continue
			_add_collision_run(run_start, run_end, row, tile_size)
			run_start = column
			run_end = column
		_add_collision_run(run_start, run_end, row, tile_size)

func _add_collision_run(start_column : int, end_column : int, row : int, tile_size : Vector2i) -> void:
	var width := (end_column - start_column + 1) * tile_size.x
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, tile_size.y)
	# Collision runs are built every bake, so they are never saved into the
	# scene file and must not participate in the editor's undo history.
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(
		start_column * tile_size.x + width * 0.5,
		row * tile_size.y + tile_size.y * 0.5
	)
	_collision_body.add_child(collision)
	collision.owner = null

## Adds an instant-kill Area2D covering one spike tile, with its art.
func _add_hazard(column : int, row : int) -> void:
	if _hazards == null:
		return
	var tile_size := _terrain.tile_set.tile_size
	var area := Area2D.new()
	area.name = "Spike_%d_%d" % [column, row]
	area.collision_layer = 0
	area.collision_mask = 2  # Player layer.
	area.monitoring = true
	# Position the Area2D at the tile centre and let the shape sit at its origin,
	# rather than leaving the area at (0,0) with an offset shape. Anything
	# parented to the area (the sprite below, later a sound) then lands correctly.
	area.position = _cell_center(column, row) - _hazards.global_position

	# The spike art fills its tile, but the lethal region is a little shorter so
	# brushing the very tip does not kill.
	var shape := RectangleShape2D.new()
	shape.size = Vector2(tile_size.x, tile_size.y * 0.7)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	area.add_child(collision)

	var spike_scene : PackedScene = load(SPIKE_SCENE)
	if spike_scene != null:
		area.add_child(spike_scene.instantiate())

	_hazards.add_child(area)
	area.body_entered.connect(_on_hazard_body_entered)

func _on_hazard_body_entered(body : Node2D) -> void:
	if hazard_handler.is_valid():
		hazard_handler.call(body)

## Global position of the spawn marker, once baked.
func get_spawn_position() -> Vector2:
	return _spawn_position

## Global position of the goal marker, once baked.
func get_goal_position() -> Vector2:
	return _goal_position
